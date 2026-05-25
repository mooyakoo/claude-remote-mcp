#!/usr/bin/env bash
# lib/utils.sh — 颜色输出 & 工具函数

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

log()  { echo -e "  ${GREEN}✓${NC}  $*"; }
warn() { echo -e "  ${YELLOW}⚠${NC}  $*"; }
die()  { echo -e "\n  ${RED}✗  $*${NC}\n"; exit 1; }
step() { echo -e "\n${CYAN}${BOLD}── [$1] $2 ${NC}"; }

banner() {
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
}

# 用 envsubst 渲染模板文件，输出到目标路径
render_template() {
    local tpl="$1" dest="$2"
    envsubst < "$tpl" > "$dest"
}
