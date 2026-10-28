allow-lan: true
mode: rule
log-level: silent
ipv6: true
unified-delay: true
clash-for-android:
  append-system-dns: false
tcp-concurrent: true
sniffer:
  enable: true
  parse-pure-ip: true
  sniffing:
    - tls
    - http
  force-dns-mapping: true
  override-destination: false
geodata-mode: true
geodata-loader: standard
geo-auto-update: false
geox-url:
  geoip: https://gh-proxy.com/https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/geoip.dat
  geosite: https://gh-proxy.com/https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/geosite.dat
  mmdb: https://gh-proxy.com/https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/country.mmdb
dns:
  enable: true
  listen: 127.0.0.1:1053
  ipv6: true
  enhanced-mode: fake-ip
  fake-ip-range: 198.18.0.1/16
  fake-ip-filter:
    - "*.lan"
    - "*.localdomain"
    - "*.example"
    - "*.invalid"
    - "*.localhost"
    - "*.test"
    - "*.local"
    - "*.home.arpa"
    - time.*.com
    - time.*.gov
    - time.*.edu.cn
    - time.*.apple.com
    - time1.*.com
    - time2.*.com
    - time3.*.com
    - time4.*.com
    - time5.*.com
    - time6.*.com
    - time7.*.com
    - ntp.*.com
    - ntp1.*.com
    - ntp2.*.com
    - ntp3.*.com
    - ntp4.*.com
    - ntp5.*.com
    - ntp6.*.com
    - ntp7.*.com
    - "*.time.edu.cn"
    - "*.ntp.org.cn"
    - +.pool.ntp.org
    - time1.cloud.tencent.com
    - stun.*.*
    - stun.*.*.*
    - +.stun.*.*
    - +.stun.*.*.*
    - +.stun.*.*.*.*
    - swscan.apple.com
    - swquery.apple.com
    - swdownload.apple.com
    - swcdn.apple.com
    - swdist.apple.com
    - mesu.apple.com
    - music.163.com
    - "*.music.163.com"
    - "*.126.net"
    - musicapi.taihe.com
    - music.taihe.com
    - songsearch.kugou.com
    - trackercdn.kugou.com
    - "*.kuwo.cn"
    - api-jooxtt.sanook.com
    - api.joox.com
    - joox.com
    - y.qq.com
    - "*.y.qq.com"
    - streamoc.music.tc.qq.com
    - mobileoc.music.tc.qq.com
    - isure.stream.qqmusic.qq.com
    - dl.stream.qqmusic.qq.com
    - aqqmusic.tc.qq.com
    - amobile.music.tc.qq.com
    - localhost.ptlogin2.qq.com
    - msftconnecttest.com
    - "*.msftconnecttest.com"
    - msftncsi.com
    - "*.msftncsi.com"
    - "*.xiami.com"
    - "*.music.migu.cn"
    - music.migu.cn
    - +.wotgame.cn
    - +.wggames.cn
    - +.wowsgame.cn
    - +.wargaming.net
    - "*.*.*.srv.nintendo.net"
    - "*.*.stun.playstation.net"
    - xbox.*.*.microsoft.com
    - "*.*.xboxlive.com"
    - "*.ipv6.microsoft.com"
    - teredo.*.*.*
    - teredo.*.*
    - speedtest.cros.wr.pvp.net
    - +.jjvip8.com
    - www.douyu.com
    - activityapi.huya.com
    - activityapi.huya.com.w.cdngslb.com
    - www.bilibili.com
    - api.bilibili.com
    - a.w.bilicdn1.com
    - "*.ffxiv.com"
    - localhost.sec.qq.com
    - +.srv.nintendo.net
    - +.stun.playstation.net
    - xbox.*.microsoft.com
    - xnotify.xboxlive.com
    - +.battlenet.com.cn
    - proxy.golang.org
    - heartbeat.belkin.com
    - "*.linksys.com"
    - "*.linksyssmartwifi.com"
    - "*.router.asus.com"
    - lens.l.google.com
    - stun.l.google.com
    - +.nflxvideo.net
    - "*.square-enix.com"
    - "*.finalfantasyxiv.com"
  default-nameserver:
    - 223.5.5.5
    - 119.29.29.29
  proxy-server-nameserver:
    - 223.5.5.5
    - 119.29.29.29
  nameserver:
    - https://dns.alidns.com/dns-query
    - 223.5.5.5
  fallback:
    - https://1.1.1.1/dns-query
    - https://8.8.8.8/dns-query
  fallback-filter:
    geoip: true
    geoip-code: CN
    ipcidr:
      - 240.0.0.0/4
      - 0.0.0.0/32
  nameserver-policy:
    geosite:cn,private:
      - https://dns.alidns.com/dns-query
      - 223.5.5.5
tun:
  enable: __TUN_ENABLE__
  stack: mixed
  auto-route: true
  auto-detect-interface: true
  dns-hijack:
    - any:53
    - tcp://any:53
  auto-redirect: true
  strict-route: false
  inet6-address:
    - fdfe:dcba:9876::1/126
  route-exclude-address-set:
    - cn_ip
  route-exclude-address:
    - 10.0.0.0/8
    - 172.16.0.0/12
    - 192.168.0.0/16
    - 127.0.0.0/8
    - 100.64.0.0/10
    - fc00::/7
    - fe80::/10
    - 38.58.57.57/32
    - 47.111.26.42/32
    - 65.215.31.11/32
    - 65.215.43.2/32
    - 65.215.57.19/32
    - 65.215.60.13/32
    - 65.215.31.241/32
    - 158.62.212.21/32
    - 20.80.89.42/32
proxies:
  - name: vpn1
    type: vless
    server: __VPN1_SERVER__
    port: __VPN1_PORT__
    uuid: __VPN1_UUID__
    network: tcp
    udp: true
    tls: true
    flow: xtls-rprx-vision
    servername: __VPN1_SNI__
    reality-opts:
      public-key: __VPN1_PUBLIC_KEY__
      short-id: "__VPN1_SHORT_ID__"
    client-fingerprint: chrome
proxy-groups:
  - name: GLOBAL
    type: select
    proxies:
      - vpn1
rule-providers:
  cn_ip:
    type: http
    behavior: ipcidr
    format: mrs
    path: ./ruleset/cn.mrs
    url: https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/meta/geo/geoip/cn.mrs
    interval: 86400
rules:
  - IP-CIDR,47.111.26.42/32,DIRECT,no-resolve
  # Docker Hub 直连,不走代理(registry / 鉴权 / 镜像层 CDN)
  - DOMAIN-SUFFIX,docker.io,DIRECT
  - DOMAIN-SUFFIX,docker.com,DIRECT
  - DOMAIN-SUFFIX,r2.cloudflarestorage.com,DIRECT
  # Ubuntu 软件源直连(2026-10-07):镜像构建里的 apt 走 VPN 线路只有几 KB/s
  - DOMAIN,archive.ubuntu.com,DIRECT
  - DOMAIN,security.ubuntu.com,DIRECT
  - GEOSITE,PRIVATE,DIRECT
  - GEOIP,PRIVATE,DIRECT,no-resolve
  - GEOSITE,CN,DIRECT
  - GEOIP,CN,DIRECT
  - MATCH,vpn1
listeners:
  - name: line-1
    type: mixed
    port: 7890
    listen: 0.0.0.0
    udp: true
    proxy: vpn1
    users:
      - username: __PROXY_USER__
        password: __PROXY_PASS__
