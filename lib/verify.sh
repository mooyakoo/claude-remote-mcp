#!/usr/bin/env bash
# lib/verify.sh — MCP 全链路握手验证

verify_mcp() {
    local domain="$1" token="$2"
    local base="https://${domain}/${token}"
    local tmpfile session resp ok=false

    echo -e "\n${CYAN}${BOLD}── [验证] 测试 MCP 全链路连通性 ──${NC}"

    systemctl start "${SERVICE_NAME:-claude-mcp}" 2>/dev/null || true
    sleep 4

    tmpfile=$(mktemp)

    # 后台保持 SSE 连接
    stdbuf -oL curl -Ns --max-time 20 "${base}/sse" > "$tmpfile" &
    local curl_pid=$!

    # 等待 sessionId（最多 10 秒）
    for i in $(seq 1 10); do
        sleep 1
        session=$(grep -o 'sessionId=[a-f0-9-]*' "$tmpfile" 2>/dev/null \
                  | head -1 | cut -d= -f2)
        [[ -n "$session" ]] && break
    done

    if [[ -n "$session" ]]; then
        # 发送 MCP initialize
        curl -s --max-time 5 -X POST \
            "${base}/message?sessionId=${session}" \
            -H "Content-Type: application/json" \
            -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"deploy-verify","version":"1.0"}}}' \
            >/dev/null
        sleep 2

        if grep -q '"protocolVersion"' "$tmpfile" 2>/dev/null; then
            local ver
            ver=$(grep -o '"version":"[^"]*"' "$tmpfile" | tail -1 | cut -d: -f2 | tr -d '"')
            log "MCP 握手验证通过 ✅（serverInfo version: ${ver}）"
            ok=true
        else
            warn "MCP initialize 无响应，请确认 claude login 已完成后重启服务"
        fi
    else
        warn "SSE 连接无响应，请检查 Caddy 和服务状态"
    fi

    kill "$curl_pid" 2>/dev/null; wait "$curl_pid" 2>/dev/null
    rm -f "$tmpfile"
    $ok
}
