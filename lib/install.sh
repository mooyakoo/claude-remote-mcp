#!/usr/bin/env bash
# lib/install.sh — 安装系统依赖、Node.js、Caddy、Claude Code、supergateway

install_system_deps() {
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    apt-get install -y -qq \
        curl openssl ufw gettext-base \
        gnupg2 debian-keyring debian-archive-keyring apt-transport-https
    log "系统依赖安装完成（curl / openssl / ufw / gettext）"
}

install_nodejs() {
    local version="${NODE_VERSION:-20}"
    if command -v node &>/dev/null && node -v | grep -q "^v${version}"; then
        log "Node.js 已存在：$(node -v)"
        return
    fi
    curl -fsSL "https://deb.nodesource.com/setup_${version}.x" | bash - >/dev/null 2>&1
    apt-get install -y -qq nodejs
    log "Node.js 安装完成：$(node -v)"
}

install_caddy() {
    if command -v caddy &>/dev/null; then
        log "Caddy 已存在：$(caddy version)"
        return
    fi
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' \
        | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' \
        | tee /etc/apt/sources.list.d/caddy-stable.list
    apt-get update -qq
    apt-get install -y -qq caddy
    log "Caddy 安装完成：$(caddy version)"
}

install_claude_code() {
    if command -v claude &>/dev/null; then
        log "Claude Code 已存在：$(claude --version 2>/dev/null || echo '已安装')"
    else
        npm install -g --quiet @anthropic-ai/claude-code
        log "Claude Code 安装完成"
    fi
    npm install -g --quiet supergateway
    log "supergateway 安装完成"
}
