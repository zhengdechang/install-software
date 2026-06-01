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
