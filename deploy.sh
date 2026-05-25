#!/usr/bin/env bash
# ╔══════════════════════════════════════════════════════════╗
# ║   Claude MCP 远程部署脚本  ·  Debian + Caddy + TLS      ║
# ║   用途：将服务器变成可被 claude.ai 控制的 MCP 节点       ║
# ╚══════════════════════════════════════════════════════════╝
set -euo pipefail

# ── 颜色 ─────────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

log()  { echo -e "  ${GREEN}✓${NC}  $*"; }
warn() { echo -e "  ${YELLOW}⚠${NC}  $*"; }
die()  { echo -e "\n  ${RED}✗  $*${NC}\n"; exit 1; }
step() { echo -e "\n${CYAN}${BOLD}── [$1] $2 ${NC}"; }

# ── 横幅 ─────────────────────────────────────────────────────────────────────
echo -e "${CYAN}${BOLD}"
cat << 'BANNER'
   _____ _                 _        __  __  ____ ____
  / ____| |               | |      |  \/  |/ ___|  _ \
 | |    | | __ _ _   _  __| | ___  | \  / | |   | |_) |
 | |    | |/ _` | | | |/ _` |/ _ \ | |\/| | |   |  __/
 | |____| | (_| | |_| | (_| |  __/ | |  | | |___| |
  \_____|_|\__,_|\__,_|\__,_|\___| |_|  |_|\____|_|
     Debian + Caddy + TLS  远程部署脚本
BANNER
echo -e "${NC}"

# ── 检查 root ─────────────────────────────────────────────────────────────────
[[ "$EUID" -eq 0 ]] || die "请用 root 或 sudo 运行：sudo bash $0"
[[ -f /etc/debian_version ]] || warn "非 Debian 系统，脚本可能有兼容问题"

# ── 交互：读取域名 ────────────────────────────────────────────────────────────
echo -e "${BOLD}请输入你的域名${NC}（已解析到本机，例如：mcp.example.com）："
read -rp "  域名 > " DOMAIN
[[ -n "$DOMAIN" ]] || die "域名不能为空"

# 去掉用户可能误加的 http:// 前缀
DOMAIN="${DOMAIN#https://}"; DOMAIN="${DOMAIN#http://}"; DOMAIN="${DOMAIN%%/*}"
echo -e "  ${GREEN}使用域名：${BOLD}${DOMAIN}${NC}"

# ── 参数 ─────────────────────────────────────────────────────────────────────
MCP_PORT="${MCP_PORT:-3663}"      # supergateway 本机端口（不对外）
SERVICE_NAME="claude-mcp"
CADDY_SERVICE="caddy"
WORK_DIR="/opt/claude-mcp"
NODE_VERSION="${NODE_VERSION:-20}"

# ── 域名解析简单预检 ──────────────────────────────────────────────────────────
echo ""
echo -n "  正在检查域名解析..."
RESOLVED_IP=$(getent hosts "$DOMAIN" | awk '{print $1}' | head -1 || true)
MY_IP=$(curl -s --connect-timeout 5 ifconfig.me || curl -s ipinfo.io/ip || echo "")
if [[ -n "$RESOLVED_IP" ]]; then
    if [[ "$RESOLVED_IP" == "$MY_IP" ]]; then
        echo -e " ${GREEN}✓ 解析正确（${RESOLVED_IP}）${NC}"
    else
        echo -e " ${YELLOW}⚠ 解析到 ${RESOLVED_IP}，本机 IP 为 ${MY_IP}${NC}"
        warn "如果域名 A 记录未更新，Caddy 申请证书可能失败"
        read -rp "  继续安装？[y/N] " confirm
        [[ "${confirm,,}" == "y" ]] || die "已取消"
    fi
else
    echo -e " ${YELLOW}⚠ 无法解析，请确认 DNS 设置正确${NC}"
fi

# ─────────────────────────────────────────────────────────────────────────────
step "1/6" "安装系统依赖"
# ─────────────────────────────────────────────────────────────────────────────
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq curl openssl ufw gnupg2 debian-keyring debian-archive-keyring apt-transport-https
log "基础依赖安装完成"

# ─────────────────────────────────────────────────────────────────────────────
step "2/6" "安装 Caddy（官方 apt 源）"
# ─────────────────────────────────────────────────────────────────────────────
if command -v caddy &>/dev/null; then
    log "Caddy 已存在：$(caddy version)"
else
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' \
        | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' \
        | tee /etc/apt/sources.list.d/caddy-stable.list
    apt-get update -qq
    apt-get install -y -qq caddy
    log "Caddy 安装完成：$(caddy version)"
fi

# ─────────────────────────────────────────────────────────────────────────────
step "3/6" "安装 Node.js ${NODE_VERSION} & Claude Code & supergateway"
# ─────────────────────────────────────────────────────────────────────────────
if command -v node &>/dev/null && node -v | grep -q "^v${NODE_VERSION}"; then
    log "Node.js 已存在：$(node -v)"
else
    curl -fsSL "https://deb.nodesource.com/setup_${NODE_VERSION}.x" | bash - >/dev/null 2>&1
    apt-get install -y -qq nodejs
    log "Node.js 安装完成：$(node -v)"
fi

if ! command -v claude &>/dev/null; then
    npm install -g --quiet @anthropic-ai/claude-code
    log "Claude Code 安装完成"
else
    log "Claude Code 已存在：$(claude --version 2>/dev/null || echo '已安装')"
fi

npm install -g --quiet supergateway
log "supergateway 安装完成"

# ─────────────────────────────────────────────────────────────────────────────
step "4/6" "生成密钥 & 创建工作目录"
# ─────────────────────────────────────────────────────────────────────────────
mkdir -p "$WORK_DIR"

AUTH_TOKEN=$(openssl rand -hex 24)
echo "$AUTH_TOKEN" > "$WORK_DIR/.auth_token"
chmod 600 "$WORK_DIR/.auth_token"
log "认证 Token 已生成（48 位随机，内嵌于 URL 路径）"

# supergateway 启动脚本
# --baseUrl 告知客户端完整的 message 端点（含 token 前缀），MCP 握手必需
cat > "$WORK_DIR/start.sh" << SCRIPT
#!/usr/bin/env bash
export HOME=/root
export PATH="\$PATH:/usr/local/bin:/usr/bin"
exec npx supergateway \\
  --stdio "claude mcp serve" \\
  --port ${MCP_PORT} \\
  --cors \\
  --baseUrl "https://${DOMAIN}/${AUTH_TOKEN}"
SCRIPT
chmod +x "$WORK_DIR/start.sh"

# systemd service
cat > "/etc/systemd/system/${SERVICE_NAME}.service" << UNIT
[Unit]
Description=Claude MCP Server Bridge (supergateway)
After=network.target
Wants=network.target

[Service]
Type=simple
User=root
WorkingDirectory=${WORK_DIR}
Environment=HOME=/root
ExecStart=${WORK_DIR}/start.sh
Restart=on-failure
RestartSec=10
StandardOutput=journal
StandardError=journal
SyslogIdentifier=${SERVICE_NAME}

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable "$SERVICE_NAME" --quiet
log "systemd 服务 [${SERVICE_NAME}] 已注册（开机自启）"

# ─────────────────────────────────────────────────────────────────────────────
step "5/6" "配置 Caddyfile（自动 TLS + SSE 反代）"
# ─────────────────────────────────────────────────────────────────────────────

# 备份旧配置
[[ -f /etc/caddy/Caddyfile ]] && \
    cp /etc/caddy/Caddyfile "/etc/caddy/Caddyfile.bak.$(date +%s)"

cat > /etc/caddy/Caddyfile << CADDYFILE
# Claude MCP Server — 自动 HTTPS + SSE 反向代理
# 生成时间：$(date '+%Y-%m-%d %H:%M:%S')

{
    # 全局设置：申请证书时用的 email（可改成你自己的）
    email admin@${DOMAIN}
}

${DOMAIN} {
    # ── 只允许带 token 的路径访问 ────────────────────────────────
    @valid_token path /${AUTH_TOKEN} /${AUTH_TOKEN}/*

    handle @valid_token {
        # 去掉 URL 里的 token 前缀再转发
        uri strip_prefix /${AUTH_TOKEN}

        reverse_proxy 127.0.0.1:${MCP_PORT} {
            # SSE 关键：禁用响应缓冲，立即 flush
            flush_interval -1

            # 透传原始请求头
            header_up Host {http.request.host}
            header_up X-Real-IP {http.request.remote}
            header_up X-Forwarded-For {http.request.remote}
            header_up X-Forwarded-Proto {http.request.scheme}

            # SSE 长连接超时（24h）
            transport http {
                read_buffer 4096
            }
        }
    }

    # 拒绝所有无 token 的请求
    handle {
        respond "Forbidden" 403
    }

    # 安全 Header
    header {
        Strict-Transport-Security "max-age=31536000; includeSubDomains"
        X-Content-Type-Options "nosniff"
        -Server
    }

    # 访问日志
    log {
        output file /var/log/caddy/claude-mcp.log {
            roll_size 10mb
            roll_keep 5
        }
        format json
    }
}
CADDYFILE

mkdir -p /var/log/caddy
chown -R caddy:caddy /var/log/caddy
chmod 755 /var/log/caddy

# 验证配置语法
caddy validate --config /etc/caddy/Caddyfile || die "Caddyfile 配置有误，请检查"
log "Caddyfile 配置验证通过"

systemctl restart caddy
log "Caddy 已重启，开始自动申请 TLS 证书..."

# ─────────────────────────────────────────────────────────────────────────────
step "6/6" "配置 UFW 防火墙"
# ─────────────────────────────────────────────────────────────────────────────
ufw --force reset >/dev/null 2>&1
ufw default deny incoming  >/dev/null 2>&1
ufw default allow outgoing >/dev/null 2>&1
ufw allow 22/tcp   comment 'SSH'     >/dev/null 2>&1
ufw allow 80/tcp   comment 'HTTP (ACME 验证)' >/dev/null 2>&1
ufw allow 443/tcp  comment 'HTTPS MCP' >/dev/null 2>&1
ufw deny "${MCP_PORT}/tcp" comment 'MCP 内部端口' >/dev/null 2>&1
echo "y" | ufw enable >/dev/null 2>&1
log "UFW 防火墙：开放 22/80/443，屏蔽 ${MCP_PORT}"

# ── 保存连接信息 ───────────────────────────────────────────────────────────
MCP_URL="https://${DOMAIN}/${AUTH_TOKEN}/sse"
cat > "$WORK_DIR/connection-info.txt" << INFO
MCP 服务器 URL : ${MCP_URL}
域名           : ${DOMAIN}
TLS            : 自动（Let's Encrypt / ZeroSSL）
内部端口       : ${MCP_PORT}（仅本机）
服务名         : ${SERVICE_NAME}
生成时间       : $(date '+%Y-%m-%d %H:%M:%S %Z')
INFO
chmod 600 "$WORK_DIR/connection-info.txt"

# ── 自动验证 MCP 全链路 ───────────────────────────────────────────────────
echo ""
echo -e "${CYAN}${BOLD}── [验证] 测试 MCP 全链路连通性 ──${NC}"

# 启动服务（如果还没启动）
systemctl start "$SERVICE_NAME" 2>/dev/null || true
sleep 4

MCP_OK=false
VERIFY_TMPFILE=$(mktemp)

# 后台保持 SSE 连接
stdbuf -oL curl -Ns --max-time 20 "https://${DOMAIN}/${AUTH_TOKEN}/sse" > "$VERIFY_TMPFILE" &
VERIFY_PID=$!

# 等待 sessionId
for i in $(seq 1 10); do
    sleep 1
    SESSION=$(grep -o 'sessionId=[a-f0-9-]*' "$VERIFY_TMPFILE" 2>/dev/null | head -1 | cut -d= -f2)
    [[ -n "$SESSION" ]] && break
done

if [[ -n "$SESSION" ]]; then
    # 发送 MCP initialize
    RESP=$(curl -s --max-time 5 -X POST \
        "https://${DOMAIN}/${AUTH_TOKEN}/message?sessionId=${SESSION}" \
        -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"deploy-verify","version":"1.0"}}}')
    sleep 2
    if grep -q '"protocolVersion"' "$VERIFY_TMPFILE" 2>/dev/null; then
        MCP_OK=true
        VER=$(grep -o '"version":"[^"]*"' "$VERIFY_TMPFILE" | tail -1 | cut -d: -f2 | tr -d '"')
        log "MCP 握手验证通过 ✅（serverInfo version: ${VER}）"
    else
        warn "MCP initialize 无响应，请确认 claude login 已完成后重启服务"
    fi
else
    warn "SSE 连接无响应，请检查 Caddy 和服务状态"
fi

kill $VERIFY_PID 2>/dev/null; wait $VERIFY_PID 2>/dev/null
rm -f "$VERIFY_TMPFILE"

# ── 完成 ──────────────────────────────────────────────────────────────────
echo ""
if $MCP_OK; then
    echo -e "${GREEN}${BOLD}╔══════════════════════════════════════════════════════════════╗"
    echo -e "║              🎉  部署完成且验证通过！                         ║"
    echo -e "╚══════════════════════════════════════════════════════════════╝${NC}"
else
    echo -e "${YELLOW}${BOLD}╔══════════════════════════════════════════════════════════════╗"
    echo -e "║         ⚠  部署完成，但 MCP 握手未通过（见上方提示）         ║"
    echo -e "╚══════════════════════════════════════════════════════════════╝${NC}"
fi
echo ""
echo -e "  ${BOLD}MCP 服务器 URL（HTTPS）：${NC}"
echo -e "  ${BLUE}${MCP_URL}${NC}"
echo ""
echo -e "  ${BOLD}连接信息已保存至：${NC}${CYAN}${WORK_DIR}/connection-info.txt${NC}"
echo ""
echo -e "${YELLOW}${BOLD}══════════════════════════════════════════════════════════════"
echo -e "  ⚠   还需手动完成以下步骤"
echo -e "══════════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "${BOLD}① 登录 Claude 账号：${NC}"
echo -e "   ${CYAN}claude login${NC}"
echo -e "   完成浏览器授权后，token 保存在 /root/.claude/"
echo ""
echo -e "${BOLD}② 启动 MCP 服务：${NC}"
echo -e "   ${CYAN}systemctl start ${SERVICE_NAME}${NC}"
echo ""
echo -e "${BOLD}③ 验证服务是否正常：${NC}"
echo -e "   ${CYAN}systemctl status ${SERVICE_NAME}${NC}"
echo -e "   ${CYAN}curl -Nv https://${DOMAIN}/${AUTH_TOKEN}/sse${NC}"
echo -e "   （应看到 SSE 流，按 Ctrl+C 退出）"
echo ""
echo -e "${BOLD}④ 在 claude.ai 添加 MCP 服务器：${NC}"
echo -e "   Settings → Integrations → Add MCP Server"
echo -e "   URL：${BLUE}${MCP_URL}${NC}"
echo ""
echo -e "${BOLD}─── 常用命令 ──────────────────────────────────────────────────${NC}"
echo -e "  MCP 实时日志：${CYAN}journalctl -u ${SERVICE_NAME} -f${NC}"
echo -e "  Caddy 日志：  ${CYAN}tail -f /var/log/caddy/claude-mcp.log | jq .${NC}"
echo -e "  证书状态：    ${CYAN}caddy environ | grep CADDY${NC}"
echo -e "  重启服务：    ${CYAN}systemctl restart ${SERVICE_NAME}${NC}"
echo -e "  查看 Token：  ${CYAN}cat ${WORK_DIR}/.auth_token${NC}"
echo ""
echo -e "${CYAN}  💡 TLS 证书由 Caddy 全自动管理，每 60 天无感续期${NC}"
echo ""
