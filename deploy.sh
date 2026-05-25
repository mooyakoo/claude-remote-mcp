#!/usr/bin/env bash
# ╔══════════════════════════════════════════════════════════╗
# ║   Claude Remote MCP — 一键部署脚本                       ║
# ║   https://github.com/mooyakoo/claude-remote-mcp          ║
# ╚══════════════════════════════════════════════════════════╝
set -euo pipefail

# ── 脚本自身目录（支持从任意路径调用）────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── 加载模块 ─────────────────────────────────────────────────
source "$SCRIPT_DIR/lib/utils.sh"
source "$SCRIPT_DIR/lib/install.sh"
source "$SCRIPT_DIR/lib/setup.sh"
source "$SCRIPT_DIR/lib/verify.sh"

# ── 全局配置（可用环境变量覆盖）─────────────────────────────
export NODE_VERSION="${NODE_VERSION:-20}"
export MCP_PORT="${MCP_PORT:-3663}"
export SERVICE_NAME="${SERVICE_NAME:-claude-mcp}"
export WORK_DIR="${WORK_DIR:-/opt/claude-mcp}"

# ── 前置检查 ─────────────────────────────────────────────────
banner
[[ "$EUID" -eq 0 ]] || die "请用 root 或 sudo 运行：sudo bash $0"
[[ -f /etc/debian_version ]] || warn "非 Debian 系统，脚本可能有兼容问题"

# ── 交互：读取域名 ───────────────────────────────────────────
echo -e "${BOLD}请输入你的域名${NC}（已解析到本机，例如：mcp.example.com）："
read -rp "  域名 > " DOMAIN
[[ -n "$DOMAIN" ]] || die "域名不能为空"
DOMAIN="${DOMAIN#https://}"; DOMAIN="${DOMAIN#http://}"; DOMAIN="${DOMAIN%%/*}"
export DOMAIN
echo -e "  ${GREEN}使用域名：${BOLD}${DOMAIN}${NC}"

# ── DNS 预检 ─────────────────────────────────────────────────
echo -n "  正在检查域名解析..."
RESOLVED=$(getent hosts "$DOMAIN" | awk '{print $1}' | head -1 || true)
MY_IP=$(curl -s --connect-timeout 5 ifconfig.me || curl -s ipinfo.io/ip || echo "")
if [[ -n "$RESOLVED" && "$RESOLVED" != "$MY_IP" ]]; then
    echo -e " ${YELLOW}⚠ 解析到 ${RESOLVED}，本机 IP 为 ${MY_IP}${NC}"
    warn "域名 A 记录未指向本机，Caddy 申请证书可能失败"
    read -rp "  继续安装？[y/N] " confirm
    [[ "${confirm,,}" == "y" ]] || die "已取消"
else
    echo -e " ${GREEN}✓ 解析正确（${RESOLVED:-未知}）${NC}"
fi

# ─────────────────────────────────────────────────────────────
step "1/6" "安装系统依赖"
install_system_deps

step "2/6" "安装 Caddy"
install_caddy

step "3/6" "安装 Node.js ${NODE_VERSION} / Claude Code / supergateway"
install_nodejs
install_claude_code

step "4/6" "生成 Token & 写入配置文件"
generate_token
setup_supergateway
setup_systemd

step "5/6" "配置 Caddy（自动 TLS + SSE 反代）"
setup_caddy

step "6/6" "配置 UFW 防火墙"
setup_firewall

# ── 保存连接信息 ─────────────────────────────────────────────
save_connection_info

# ── 自动验证 ─────────────────────────────────────────────────
MCP_OK=false
verify_mcp "$DOMAIN" "$AUTH_TOKEN" && MCP_OK=true || true

# ── 完成输出 ─────────────────────────────────────────────────
echo ""
if $MCP_OK; then
    echo -e "${GREEN}${BOLD}╔══════════════════════════════════════════════════════════════╗"
    echo -e "║              🎉  部署完成且验证通过！                         ║"
    echo -e "╚══════════════════════════════════════════════════════════════╝${NC}"
else
    echo -e "${YELLOW}${BOLD}╔══════════════════════════════════════════════════════════════╗"
    echo -e "║         ⚠  部署完成，MCP 握手未通过（见上方提示）           ║"
    echo -e "╚══════════════════════════════════════════════════════════════╝${NC}"
fi

echo ""
echo -e "  ${BOLD}MCP 服务器 URL：${NC}"
echo -e "  ${BLUE}${MCP_URL}${NC}"
echo -e "  ${BOLD}连接信息：${NC}${CYAN}${WORK_DIR}/connection-info.txt${NC}"
echo ""
echo -e "${YELLOW}${BOLD}══ 后续步骤 ════════════════════════════════════════════════════${NC}"
echo -e "${BOLD}① 登录 Claude 账号：${NC}"
echo -e "   ${CYAN}claude login${NC}"
echo ""
echo -e "${BOLD}② 启动服务（若未自动启动）：${NC}"
echo -e "   ${CYAN}systemctl start ${SERVICE_NAME}${NC}"
echo ""
echo -e "${BOLD}③ 在 claude.ai 添加 MCP 服务器：${NC}"
echo -e "   Settings → Integrations → Add MCP Server"
echo -e "   URL：${BLUE}${MCP_URL}${NC}"
echo ""
echo -e "${BOLD}─── 常用命令 ───────────────────────────────────────────────────${NC}"
echo -e "  实时日志：${CYAN}journalctl -u ${SERVICE_NAME} -f${NC}"
echo -e "  重启服务：${CYAN}systemctl restart ${SERVICE_NAME}${NC}"
echo -e "  Caddy 日志：${CYAN}tail -f /var/log/caddy/claude-mcp.log | jq .${NC}"
echo -e "  查看 Token：${CYAN}cat ${WORK_DIR}/.auth_token${NC}"
echo ""
echo -e "${CYAN}  💡 TLS 证书由 Caddy 全自动管理，每 60 天无感续期${NC}"
echo ""
