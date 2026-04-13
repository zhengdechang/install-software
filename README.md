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

