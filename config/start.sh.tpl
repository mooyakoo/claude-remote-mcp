#!/usr/bin/env bash
# supergateway 启动脚本
# 由 deploy.sh 通过 envsubst 渲染生成，请勿直接修改此文件
# 变量：${MCP_PORT}  ${DOMAIN}  ${AUTH_TOKEN}

export HOME=/root
export PATH="$PATH:/usr/local/bin:/usr/bin"

exec npx supergateway \
  --stdio "claude mcp serve" \
  --port ${MCP_PORT} \
  --cors \
  --baseUrl "https://${DOMAIN}/${AUTH_TOKEN}"
