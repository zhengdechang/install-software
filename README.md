# install-software

一键安装脚本集合。所有脚本通过 `curl | bash` 即可使用。

> **注意**: GitHub raw CDN 有 5 分钟缓存，更新后如遇到旧版本，在 URL 末尾加 `?t=$(date +%s)` 强制刷新。

## Claude Code + 飞书 AI Agent

```bash
curl -fsSL "https://raw.githubusercontent.com/zhengdechang/install-software/main/install-cc.sh?t=$(date +%s)" -o /tmp/install-cc.sh && bash /tmp/install-cc.sh
```

包含：NVM + Node.js 24、Claude Code、飞书 CLI + Lark Skills、gstack、cc-connect（飞书扫码配置）

## Docker + Docker Compose

```bash
curl -sSL https://raw.githubusercontent.com/zhengdechang/install-software/main/install-docker-compose.sh | bash
```

或先装 curl：

```bash
apt update && apt install -y curl && \
curl -fsSL https://raw.githubusercontent.com/zhengdechang/install-software/main/install-docker-compose.sh | bash
```

## Go

```bash
curl -sSL https://raw.githubusercontent.com/zhengdechang/install-software/main/install-go.sh | bash -s -- --version 1.23.5
```

## Hermes Agent

```bash
curl -fsSL https://raw.githubusercontent.com/zhengdechang/install-software/main/install-hermes.sh -o /tmp/install-hermes.sh && bash /tmp/install-hermes.sh
```

## Certbot + Nginx

```bash
curl -fsSL https://raw.githubusercontent.com/zhengdechang/install-software/main/install-certbot-nginx.sh -o /tmp/install-certbot-nginx.sh && sudo bash /tmp/install-certbot-nginx.sh
```

## SSH 端口 22922

```bash
curl -fsSL https://raw.githubusercontent.com/zhengdechang/install-software/main/enable-22922.sh -o /tmp/enable-22922.sh && sudo bash /tmp/enable-22922.sh 22922
```

## Mihomo 代理(vpn1)

Linux / macOS 通用，直接用 mihomo 官方二进制运行，不需要 Docker。Linux 用 systemd 托管（默认开 TUN 全局接管），macOS 用 launchd 托管（默认只开代理端口）。

```bash
curl -fsSL "https://raw.githubusercontent.com/zhengdechang/install-software/main/install-mihomo-proxy.sh?t=$(date +%s)" -o /tmp/install-mihomo-proxy.sh && \
VPN1_LINK='vless://uuid@host:port?security=reality&sni=...&pbk=...&sid=...#vpn1' bash /tmp/install-mihomo-proxy.sh install
```

不传 `VPN1_LINK` 时会提示粘贴 vless 链接。安装后代理端口 `7890`（HTTP/SOCKS5），认证信息在安装目录的 `data/credentials`。

管理（安装目录默认 root 为 `/opt/mihomo-proxy`，普通用户为 `~/mihomo-proxy`）：

```bash
~/mihomo-proxy/mihomo.sh start      # 启动并开机自启
~/mihomo-proxy/mihomo.sh stop       # 停止(重启机器后也保持停止)
~/mihomo-proxy/mihomo.sh restart
~/mihomo-proxy/mihomo.sh status
~/mihomo-proxy/mihomo.sh logs
~/mihomo-proxy/mihomo.sh uninstall  # 卸载服务,保留配置
```

可选环境变量：`MIHOMO_TUN=true|false`（macOS 开 TUN 需要 sudo）、`PROXY_USER` / `PROXY_PASS`、`GH_PROXY=https://gh-proxy.com/`（国内加速下载）、`MIHOMO_DIR`。
