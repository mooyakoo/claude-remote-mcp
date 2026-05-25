# Claude Remote MCP Server

> One-click deployment script to expose `claude mcp serve` as a remote HTTPS MCP server — so you can control your server from **claude.ai** web interface.

[中文说明](#中文说明) | [English](#english)

---

## 中文说明

### 这是什么？

一键将你的 Debian 服务器变成可被 [claude.ai](https://claude.ai) 网页远程控制的 MCP 节点。

```
claude.ai 网页
    ↓  HTTPS (Let's Encrypt 自动证书)
Caddy 反向代理
    ↓  Token URL 鉴权
supergateway (stdio → SSE 桥接)
    ↓  stdio
claude mcp serve
```

### 特性

- 🔒 **自动 TLS** — Caddy 自动申请并续期 Let's Encrypt 证书
- 🔑 **Token 鉴权** — 48 位随机 Token 内嵌于 URL 路径，无需额外 Header
- 🔁 **开机自启** — systemd 管理，失败自动重启
- 🛡️ **防火墙** — UFW 仅开放 22/80/443，内部 MCP 端口不对外暴露
- ✅ **自动验证** — 脚本结束后自动跑完整 MCP 握手测试

### 系统要求

| 项目 | 要求 |
|------|------|
| 操作系统 | Debian 11 / 12 |
| 架构 | x86_64 |
| 权限 | root 或 sudo |
| 域名 | 需有域名并已解析到服务器（Caddy 自动 TLS 必需）|

### 快速开始

```bash
# 下载脚本
curl -fsSL https://raw.githubusercontent.com/mooyakoo/claude-remote-mcp/main/deploy.sh -o deploy.sh

# 执行（会提示输入域名）
sudo bash deploy.sh
```

脚本自动完成：
1. 安装 Node.js 20 LTS
2. 安装 Claude Code CLI + supergateway
3. 安装 Caddy（自动 HTTPS）
4. 生成随机 Token，创建 systemd 服务
5. 配置 UFW 防火墙
6. 验证 MCP 全链路连通性

### 部署后的步骤

```bash
# ① 登录 Claude 账号（必须）
claude login

# ② 启动服务
systemctl start claude-mcp

# ③ 查看连接信息
cat /opt/claude-mcp/connection-info.txt
```

然后在 claude.ai → **Settings → Integrations → Add MCP Server** 填入 URL 即可。

### 管理命令

```bash
# 查看实时日志
journalctl -u claude-mcp -f

# 重启服务
systemctl restart claude-mcp

# 查看 Token
cat /opt/claude-mcp/.auth_token

# 查看 Caddy 日志
tail -f /var/log/caddy/claude-mcp.log | jq .
```

### 工作原理

| 组件 | 作用 |
|------|------|
| `claude mcp serve` | Anthropic 官方 MCP 服务，暴露 Claude Code 工具集 |
| `supergateway` | 将 stdio MCP 服务转换为 HTTP/SSE，供远程客户端连接 |
| `Caddy` | 反向代理 + 自动 TLS + Token URL 路由鉴权 |
| `systemd` | 进程守护，开机自启，失败自动重启 |
| `UFW` | 防火墙，仅暴露必要端口 |

---

## English

### What is this?

A one-click deployment script that turns your Debian server into a remote MCP node controllable from the [claude.ai](https://claude.ai) web interface.

### Features

- 🔒 **Auto TLS** — Caddy automatically provisions and renews Let's Encrypt certificates
- 🔑 **Token Auth** — 48-char random token embedded in URL path, no custom headers needed
- 🔁 **Auto-restart** — systemd managed, restarts on failure
- 🛡️ **Firewall** — UFW opens only 22/80/443; internal MCP port not exposed
- ✅ **Self-verify** — full MCP handshake test runs at end of deployment

### Requirements

- Debian 11 / 12, x86_64
- root or sudo access
- A domain name pointed to your server (required for Caddy auto-TLS)

### Quick Start

```bash
curl -fsSL https://raw.githubusercontent.com/mooyakoo/claude-remote-mcp/main/deploy.sh -o deploy.sh
sudo bash deploy.sh
```

### After Deployment

```bash
claude login              # authenticate Claude CLI
systemctl start claude-mcp
cat /opt/claude-mcp/connection-info.txt   # get your MCP server URL
```

Add the URL in claude.ai → **Settings → Integrations → Add MCP Server**.

---

## Architecture

```
claude.ai (web)
    │
    │  HTTPS / TLS 1.3  (Let's Encrypt)
    ▼
Caddy :443
    │  validates token in URL path
    │  strips token prefix
    │  flush_interval -1  (SSE passthrough)
    ▼
supergateway :3663 (localhost only)
    │  stdio transport
    ▼
claude mcp serve
    │
    ├── Read / Edit / Write files
    ├── Bash execution
    └── All Claude Code tools
```

## Related Projects

| Project | Description |
|---------|-------------|
| [supercorp-ai/supergateway](https://github.com/supercorp-ai/supergateway) | stdio → SSE bridge (used by this script) |
| [steipete/claude-code-mcp](https://github.com/steipete/claude-code-mcp) | Claude Code as agent-in-agent MCP server |
| [DATANOMIQ/mcp-secure-server](https://github.com/DATANOMIQ/mcp-secure-server) | Supergateway + NGINX + Render deployment |

## License

MIT
