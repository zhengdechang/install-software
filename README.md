# install-software

install software

- install docker and docker compose

```
curl -sSL https://raw.githubusercontent.com/zhengdechang/install-software/main/install-docker-compose.sh | bash
```

or

```
apt update && apt install -y curl && \
curl -fsSL https://raw.githubusercontent.com/zhengdechang/install-software/main/install-docker-compose.sh | bash
```

- install go

```
curl -sSL https://raw.githubusercontent.com/zhengdechang/install-software/main/install-go.sh | bash -s -- --version 1.23.5
```

- install cc

```
curl -fsSL https://raw.githubusercontent.com/zhengdechang/install-software/main/install-cc.sh -o /tmp/install-cc.sh && bash /tmp/install-cc.sh
```

- install Hermes Agent (with Feishu/Lark setup, optional WeCom)

```
curl -fsSL https://raw.githubusercontent.com/zhengdechang/install-software/main/install-hermes.sh -o /tmp/install-hermes.sh && bash /tmp/install-hermes.sh
```

- install certbot, nginx, and certbot nginx plugin

```
curl -fsSL https://raw.githubusercontent.com/zhengdechang/install-software/main/install-certbot-nginx.sh -o /tmp/install-certbot-nginx.sh && sudo bash /tmp/install-certbot-nginx.sh
```

- enable SSH port 22922

```
curl -fsSL https://raw.githubusercontent.com/zhengdechang/install-software/main/enable-22922.sh -o /tmp/enable-22922.sh && sudo bash /tmp/enable-22922.sh 22922
```
