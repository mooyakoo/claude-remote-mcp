# Caddyfile — Claude MCP 反向代理
# 由 deploy.sh 通过 envsubst 渲染生成，请勿直接修改此文件
# 变量：${DOMAIN}  ${AUTH_TOKEN}  ${MCP_PORT}

{
    email admin@${DOMAIN}
}

${DOMAIN} {
    # ── 只允许带 token 的路径 ──────────────────────────────────
    @valid_token path /${AUTH_TOKEN} /${AUTH_TOKEN}/*

    handle @valid_token {
        uri strip_prefix /${AUTH_TOKEN}

        reverse_proxy 127.0.0.1:${MCP_PORT} {
            # SSE 必需：禁用响应缓冲
            flush_interval -1

            header_up Host              {http.request.host}
            header_up X-Real-IP         {http.request.remote}
            header_up X-Forwarded-For   {http.request.remote}
            header_up X-Forwarded-Proto {http.request.scheme}

            transport http {
                read_buffer 4096
            }
        }
    }

    # 拒绝无 token 的请求
    handle {
        respond "Forbidden" 403
    }

    # 安全响应头
    header {
        Strict-Transport-Security "max-age=31536000; includeSubDomains"
        X-Content-Type-Options    "nosniff"
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
