#!/usr/bin/env bash
# lib/setup.sh — 生成 Token、渲染配置文件、注册 systemd 服务

WORK_DIR="${WORK_DIR:-/opt/claude-mcp}"
MCP_PORT="${MCP_PORT:-3663}"
SERVICE_NAME="${SERVICE_NAME:-claude-mcp}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

generate_token() {
    mkdir -p "$WORK_DIR"
    AUTH_TOKEN=$(openssl rand -hex 24)
    echo "$AUTH_TOKEN" > "$WORK_DIR/.auth_token"
    chmod 600 "$WORK_DIR/.auth_token"
    log "认证 Token 已生成（48 位随机，内嵌于 URL 路径）"
    export AUTH_TOKEN
}

setup_supergateway() {
    # 导出模板所需变量
    export MCP_PORT WORK_DIR AUTH_TOKEN DOMAIN
    render_template \
        "$SCRIPT_DIR/config/start.sh.tpl" \
        "$WORK_DIR/start.sh"
    chmod +x "$WORK_DIR/start.sh"
    log "supergateway 启动脚本已写入 ${WORK_DIR}/start.sh"
}

setup_systemd() {
    export WORK_DIR SERVICE_NAME
    render_template \
        "$SCRIPT_DIR/config/claude-mcp.service" \
        "/etc/systemd/system/${SERVICE_NAME}.service"
    systemctl daemon-reload
    systemctl enable "$SERVICE_NAME" --quiet
    log "systemd 服务 [${SERVICE_NAME}] 已注册（开机自启）"
}

setup_caddy() {
    # 备份旧配置
    [[ -f /etc/caddy/Caddyfile ]] && \
        cp /etc/caddy/Caddyfile "/etc/caddy/Caddyfile.bak.$(date +%s)"

    export DOMAIN AUTH_TOKEN MCP_PORT
    render_template \
        "$SCRIPT_DIR/config/Caddyfile.tpl" \
        /etc/caddy/Caddyfile

    # 日志目录
    mkdir -p /var/log/caddy
    chown -R caddy:caddy /var/log/caddy
    chmod 755 /var/log/caddy

    caddy validate --config /etc/caddy/Caddyfile || die "Caddyfile 配置有误"
    systemctl restart caddy
    log "Caddy 已重启，开始自动申请 TLS 证书..."
}

setup_firewall() {
    ufw --force reset        >/dev/null 2>&1
    ufw default deny incoming  >/dev/null 2>&1
    ufw default allow outgoing >/dev/null 2>&1
    ufw allow 22/tcp   comment 'SSH'           >/dev/null 2>&1
    ufw allow 80/tcp   comment 'HTTP ACME'     >/dev/null 2>&1
    ufw allow 443/tcp  comment 'HTTPS MCP'     >/dev/null 2>&1
    ufw deny  "${MCP_PORT}/tcp" comment 'MCP 内部端口' >/dev/null 2>&1
    echo "y" | ufw enable   >/dev/null 2>&1
    log "UFW 防火墙：开放 22/80/443，屏蔽 ${MCP_PORT}"
}

save_connection_info() {
    local url="https://${DOMAIN}/${AUTH_TOKEN}/sse"
    cat > "$WORK_DIR/connection-info.txt" << INFO
MCP 服务器 URL : ${url}
域名           : ${DOMAIN}
TLS            : 自动（Let's Encrypt / ZeroSSL）
内部端口       : ${MCP_PORT}（仅本机）
服务名         : ${SERVICE_NAME}
生成时间       : $(date '+%Y-%m-%d %H:%M:%S %Z')
INFO
    chmod 600 "$WORK_DIR/connection-info.txt"
    export MCP_URL="$url"
}
