#!/usr/bin/env bash
# mihomo 代理一键安装/管理(只含一条 vpn1 线路),官方二进制直接运行,不需要 Docker
#   Linux: systemd 托管;macOS: launchd 托管(TUN 需要 sudo)
#   默认开 TUN + 全局模式(mode: global),本机所有流量都走 vpn1
#
# 用法: install-mihomo-proxy.sh [install|start|stop|restart|status|logs|uninstall]
#       install-mihomo-proxy.sh switch '<链接>'   切换上游节点(配置校验失败自动回滚)
#       install-mihomo-proxy.sh tun on|off        开关 TUN 接管本机流量
#       install-mihomo-proxy.sh mode global|rule  全局走 vpn1 / 按规则分流(国内直连)
#
# install 需要 vpn1 节点,支持 VLESS + Reality / HTTP(S) / SOCKS5,二选一:
#   VPN1_LINK='vless://uuid@host:port?security=reality&sni=...&pbk=...&sid=...#vpn1'
#   VPN1_LINK='http://user:pass@host:port'     (https:// 为 TLS 的 HTTP 代理)
#   VPN1_LINK='socks5://user:pass@host:port'   (用户名密码可省略,含特殊字符需 URL 编码)
#   或按字段给,VPN1_TYPE=vless(默认)|http|socks5:
#     vless : VPN1_SERVER / VPN1_PORT / VPN1_UUID / VPN1_SNI / VPN1_PUBLIC_KEY / VPN1_SHORT_ID
#     http  : VPN1_SERVER / VPN1_PORT / VPN1_USER / VPN1_PASS / VPN1_TLS=true|false / VPN1_SNI
#     socks5: VPN1_SERVER / VPN1_PORT / VPN1_USER / VPN1_PASS
#   都不给时交互式输入链接;已安装过则沿用原配置。
#
# 可选环境变量:
#   MIHOMO_DIR      安装目录,默认 root 为 /opt/mihomo-proxy,其他用户为 ~/mihomo-proxy
#   MIHOMO_TUN      true/false,默认 true(macOS 开 TUN 需 sudo)
#   MIHOMO_MODE     global/rule,默认 global
#   (这两项首装用默认值,之后沿用配置里的值;显式传入则覆盖)
#   PROXY_USER      代理认证用户名,默认 proxy;PROXY_PASS 不给则随机生成
#   GH_PROXY        GitHub 下载加速前缀,如 https://gh-proxy.com/
#   MIHOMO_URL      直接指定 mihomo 二进制 .gz 下载地址
set -euo pipefail

MIHOMO_VERSION="v1.19.31"
RAW_BASE="https://raw.githubusercontent.com/zhengdechang/install-software/main"
SERVICE="mihomo-proxy"
LABEL="com.mihomo.proxy"
OS="$(uname -s)"
GH_PROXY="${GH_PROXY:-}"

if [[ $(id -u) -eq 0 ]]; then
  SUDO=""
  MIHOMO_DIR="${MIHOMO_DIR:-/opt/mihomo-proxy}"
else
  SUDO="sudo"
  MIHOMO_DIR="${MIHOMO_DIR:-$HOME/mihomo-proxy}"
fi
DATA_DIR="$MIHOMO_DIR/data"
BIN="$MIHOMO_DIR/bin/mihomo"

# 读已有配置里 tun.enable 的值
read_tun_config() {
  [[ -f "$DATA_DIR/config.yaml" ]] || return 0
  awk '/^tun:/ { t = 1; next } t && /^  enable:/ { print $2; exit } /^[^ ]/ { t = 0 }' "$DATA_DIR/config.yaml"
}

# 读已有配置里顶层 mode 的值
read_mode_config() {
  [[ -f "$DATA_DIR/config.yaml" ]] || return 0
  awk '/^mode:/ { print $2; exit }' "$DATA_DIR/config.yaml"
}

case "$OS" in
  Linux | Darwin) ;;
  *) echo "不支持的系统 $OS" >&2; exit 1 ;;
esac

# 优先级: 环境变量 > 已有配置 > 默认(TUN 开 + 全局)
TUN_FROM_ENV="${MIHOMO_TUN:-}"
MODE_FROM_ENV="${MIHOMO_MODE:-}"
MIHOMO_TUN="${MIHOMO_TUN:-$(read_tun_config)}"
MIHOMO_TUN="${MIHOMO_TUN:-true}"
MIHOMO_MODE="${MIHOMO_MODE:-$(read_mode_config)}"
MIHOMO_MODE="${MIHOMO_MODE:-global}"
[[ "$MIHOMO_TUN" == "true" || "$MIHOMO_TUN" == "false" ]] || { echo "MIHOMO_TUN 只能是 true/false" >&2; exit 1; }
[[ "$MIHOMO_MODE" == "global" || "$MIHOMO_MODE" == "rule" ]] || { echo "MIHOMO_MODE 只能是 global/rule" >&2; exit 1; }

log() { printf '\033[32m[mihomo]\033[0m %s\n' "$*"; }
die() { printf '\033[31m[mihomo]\033[0m %s\n' "$*" >&2; exit 1; }

# ---------------------------------------------------------------- 配置渲染

sed_escape() { printf '%s' "$1" | sed -e 's/[|&\\]/\\&/g'; }

urldecode() { local s="${1//+/ }"; printf '%b' "${s//%/\\x}"; }

# YAML 双引号字符串,转义 \ 和 "
yaml_str() {
  local s="${1//\\/\\\\}"
  printf '"%s"' "${s//\"/\\\"}"
}

# 解析 vless:// http:// https:// socks5:// 链接,填 VPN1_* 变量
parse_link() {
  local link="$1" scheme rest auth="" hostport query="" kv k v
  [[ "$link" == *://* ]] || die "链接格式不对: $link"
  scheme="${link%%://*}"
  rest="${link#*://}"
  rest="${rest%%#*}"
  [[ "$rest" == *\?* ]] && query="${rest#*\?}"
  rest="${rest%%\?*}"
  rest="${rest%%/*}"
  if [[ "$rest" == *@* ]]; then
    auth="${rest%@*}"
    hostport="${rest##*@}"
  else
    hostport="$rest"
  fi
  # 端口:最后一个 : 之后,且不是 IPv6 地址内部的冒号
  VPN1_PORT=""
  VPN1_SERVER="$hostport"
  if [[ "$hostport" =~ ^\[(.*)\](:([0-9]+))?$ ]]; then
    VPN1_SERVER="${BASH_REMATCH[1]}"
    VPN1_PORT="${BASH_REMATCH[3]}"
  elif [[ "$hostport" =~ ^([^:]+):([0-9]+)$ ]]; then
    VPN1_SERVER="${BASH_REMATCH[1]}"
    VPN1_PORT="${BASH_REMATCH[2]}"
  fi

  case "$scheme" in
    vless)
      VPN1_TYPE="vless"
      VPN1_UUID="$auth"
      local IFS='&'
      for kv in $query; do
        k="${kv%%=*}"
        v="$(urldecode "${kv#*=}")"
        case "$k" in
          sni) VPN1_SNI="$v" ;;
          pbk) VPN1_PUBLIC_KEY="$v" ;;
          sid) VPN1_SHORT_ID="$v" ;;
          security) [[ "$v" == "reality" ]] || die "vless 只支持 Reality 节点(security=$v)" ;;
        esac
      done
      ;;
    http | https)
      VPN1_TYPE="http"
      VPN1_TLS=false
      [[ "$scheme" == "https" ]] && VPN1_TLS=true
      [[ -n "$VPN1_PORT" ]] || VPN1_PORT=$([[ "$VPN1_TLS" == "true" ]] && echo 443 || echo 80)
      ;;
    socks5 | socks5h | socks)
      VPN1_TYPE="socks5"
      [[ -n "$VPN1_PORT" ]] || VPN1_PORT=1080
      ;;
    *) die "不支持的链接协议 $scheme://(支持 vless/http/https/socks5)" ;;
  esac
  if [[ "$VPN1_TYPE" != "vless" && -n "$auth" ]]; then
    VPN1_USER="$(urldecode "${auth%%:*}")"
    [[ "$auth" == *:* ]] && VPN1_PASS="$(urldecode "${auth#*:}")"
  fi
  return 0
}

# 按节点类型输出 proxies 下的 vpn1 条目
render_proxy() {
  local server port
  server="$(yaml_str "$VPN1_SERVER")"
  port="$VPN1_PORT"
  case "$VPN1_TYPE" in
    vless)
      cat <<YAML
  - name: vpn1
    type: vless
    server: $server
    port: $port
    uuid: $(yaml_str "$VPN1_UUID")
    network: tcp
    udp: true
    tls: true
    flow: xtls-rprx-vision
    servername: $(yaml_str "$VPN1_SNI")
    reality-opts:
      public-key: $(yaml_str "$VPN1_PUBLIC_KEY")
      short-id: $(yaml_str "${VPN1_SHORT_ID:-}")
    client-fingerprint: chrome
YAML
      ;;
    http | socks5)
      printf '  - name: vpn1\n    type: %s\n    server: %s\n    port: %s\n' "$VPN1_TYPE" "$server" "$port"
      [[ "$VPN1_TYPE" == "socks5" ]] && printf '    udp: true\n'
      if [[ -n "${VPN1_USER:-}" ]]; then
        printf '    username: %s\n    password: %s\n' "$(yaml_str "$VPN1_USER")" "$(yaml_str "${VPN1_PASS:-}")"
      fi
      if [[ "$VPN1_TYPE" == "http" && "${VPN1_TLS:-false}" == "true" ]]; then
        printf '    tls: true\n'
        [[ -n "${VPN1_SNI:-}" ]] && printf '    sni: %s\n' "$(yaml_str "$VPN1_SNI")"
      fi
      ;;
  esac
  return 0
}

need_vpn1_input() {
  [[ -n "${VPN1_LINK:-}" || -n "${VPN1_SERVER:-}" ]] && return 0
  [[ -f "$DATA_DIR/config.yaml" ]] && return 1
  [[ -r /dev/tty ]] || die "未提供 VPN1_LINK,且无法交互输入"
  printf '请粘贴 vpn1 链接(vless:// http:// https:// socks5://): ' >/dev/tty
  read -r VPN1_LINK </dev/tty
  [[ -n "$VPN1_LINK" ]] || die "链接为空"
}

fetch_template() {
  local here
  here="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || true)"
  if [[ -n "$here" && -f "$here/mihomo-proxy/config.yaml.tpl" ]]; then
    cat "$here/mihomo-proxy/config.yaml.tpl"
  else
    curl -fsSL "$RAW_BASE/mihomo-proxy/config.yaml.tpl?t=$(date +%s)"
  fi
}

render_config() {
  mkdir -p "$DATA_DIR"
  if ! need_vpn1_input; then
    log "沿用已有配置 $DATA_DIR/config.yaml"
    [[ -n "$TUN_FROM_ENV" ]] && write_tun_config "$MIHOMO_TUN"
    [[ -n "$MODE_FROM_ENV" ]] && write_mode_config "$MIHOMO_MODE"
    return 0
  fi
  [[ -n "${VPN1_LINK:-}" ]] && parse_link "$VPN1_LINK"
  VPN1_TYPE="${VPN1_TYPE:-vless}"
  local v required
  case "$VPN1_TYPE" in
    vless) required="VPN1_SERVER VPN1_PORT VPN1_UUID VPN1_SNI VPN1_PUBLIC_KEY" ;;
    http | socks5) required="VPN1_SERVER VPN1_PORT" ;;
    *) die "VPN1_TYPE 只支持 vless/http/socks5(当前 $VPN1_TYPE)" ;;
  esac
  for v in $required; do
    [[ -n "${!v:-}" ]] || die "缺少 $v"
  done
  [[ "$VPN1_PORT" =~ ^[0-9]+$ ]] || die "端口不对: $VPN1_PORT"

  # 认证沿用已有 credentials,避免重装后客户端密码失效
  local user="" pass=""
  if [[ -f "$DATA_DIR/credentials" ]]; then
    user="$(cut -d: -f1 "$DATA_DIR/credentials")"
    pass="$(cut -d: -f2- "$DATA_DIR/credentials")"
  fi
  user="${PROXY_USER:-${user:-proxy}}"
  pass="${PROXY_PASS:-${pass:-$(openssl rand -hex 18)}}"

  # 节点条目是多行,先写到临时文件再用 awk 整行替换占位符
  local tpl tmp proxy_file
  tpl="$(fetch_template)" || die "下载配置模板失败"
  tmp="$(mktemp)"
  proxy_file="$(mktemp)"
  render_proxy >"$proxy_file"
  printf '%s\n' "$tpl" | sed \
    -e "s|__TUN_ENABLE__|$(sed_escape "$MIHOMO_TUN")|g" \
    -e "s|__MODE__|$(sed_escape "$MIHOMO_MODE")|g" \
    -e "s|__PROXY_USER__|$(sed_escape "$user")|g" \
    -e "s|__PROXY_PASS__|$(sed_escape "$pass")|g" |
    awk -v f="$proxy_file" '$0 == "__VPN1_PROXY__" { while ((getline l < f) > 0) print l; next } { print }' >"$tmp"
  rm -f "$proxy_file"
  mv "$tmp" "$DATA_DIR/config.yaml"
  printf '%s:%s\n' "$user" "$pass" >"$DATA_DIR/credentials"
  chmod 600 "$DATA_DIR/config.yaml" "$DATA_DIR/credentials"
  log "已生成 $DATA_DIR/config.yaml(vpn1=$VPN1_TYPE,TUN=$MIHOMO_TUN,mode=$MIHOMO_MODE)"
}

# 原地改已有配置里的 tun.enable
write_tun_config() {
  local tmp
  tmp="$(mktemp)"
  awk -v v="$1" '/^tun:/ { t = 1; print; next } t && /^  enable:/ { print "  enable: " v; t = 0; next } /^[^ ]/ { t = 0 } { print }' \
    "$DATA_DIR/config.yaml" >"$tmp"
  mv "$tmp" "$DATA_DIR/config.yaml"
  chmod 600 "$DATA_DIR/config.yaml"
  log "TUN=$1"
}

write_mode_config() {
  local tmp
  tmp="$(mktemp)"
  awk -v v="$1" '/^mode:/ { print "mode: " v; next } { print }' "$DATA_DIR/config.yaml" >"$tmp"
  mv "$tmp" "$DATA_DIR/config.yaml"
  chmod 600 "$DATA_DIR/config.yaml"
  log "mode=$1"
}

# ---------------------------------------------------------------- 二进制

install_bin() {
  local os arch gz url
  os="$(printf '%s' "$OS" | tr '[:upper:]' '[:lower:]')"
  case "$(uname -m)" in
    x86_64 | amd64) arch="amd64-compatible" ;;
    arm64 | aarch64) arch="arm64" ;;
    *) die "不支持的架构 $(uname -m)" ;;
  esac
  if [[ -x "$BIN" ]] && "$BIN" -v 2>/dev/null | grep -q "$MIHOMO_VERSION"; then
    log "mihomo $MIHOMO_VERSION 已安装"
    return
  fi
  gz="mihomo-${os}-${arch}-${MIHOMO_VERSION}.gz"
  url="${MIHOMO_URL:-${GH_PROXY}https://github.com/MetaCubeX/mihomo/releases/download/${MIHOMO_VERSION}/${gz}}"
  log "下载 $url"
  mkdir -p "$MIHOMO_DIR/bin"
  curl -fL --retry 3 "$url" -o "$BIN.gz"
  gunzip -f "$BIN.gz"
  chmod +x "$BIN"
  [[ "$OS" == "Darwin" ]] && xattr -d com.apple.quarantine "$BIN" 2>/dev/null || true
}

install_self() {
  local dst="$MIHOMO_DIR/mihomo.sh" src="${BASH_SOURCE[0]:-}"
  if [[ -f "$src" ]]; then
    [[ "$(cd "$(dirname "$src")" && pwd)/$(basename "$src")" == "$dst" ]] || cp "$src" "$dst"
  else
    curl -fsSL "$RAW_BASE/install-mihomo-proxy.sh?t=$(date +%s)" -o "$dst"
  fi
  chmod +x "$dst"
}

# ---------------------------------------------------------------- Linux: systemd

UNIT="/etc/systemd/system/$SERVICE.service"

linux_write_unit() {
  command -v systemctl >/dev/null 2>&1 || die "需要 systemd"
  $SUDO tee "$UNIT" >/dev/null <<EOF
[Unit]
Description=mihomo proxy (vpn1)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=${BIN} -d ${DATA_DIR} -f ${DATA_DIR}/config.yaml
Restart=always
RestartSec=3
LimitNOFILE=1048576
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW

[Install]
WantedBy=multi-user.target
EOF
  $SUDO systemctl daemon-reload
}

# ---------------------------------------------------------------- macOS: launchd

# TUN 需要 root,走系统级 LaunchDaemon;否则走用户级 LaunchAgent,无需 sudo
set_mac_target() {
  if [[ "$1" == "true" ]]; then
    PLIST="/Library/LaunchDaemons/$LABEL.plist"
    DOMAIN="system"
  else
    PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
    DOMAIN="gui/$(id -u)"
  fi
}
set_mac_target "$MIHOMO_TUN"

mac_sudo() { if [[ "$MIHOMO_TUN" == "true" ]]; then $SUDO "$@"; else "$@"; fi; }

mac_write_plist() {
  mac_sudo mkdir -p "$(dirname "$PLIST")"
  mac_sudo tee "$PLIST" >/dev/null <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>${LABEL}</string>
  <key>ProgramArguments</key>
  <array>
    <string>${BIN}</string>
    <string>-d</string><string>${DATA_DIR}</string>
    <string>-f</string><string>${DATA_DIR}/config.yaml</string>
  </array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>StandardOutPath</key><string>${MIHOMO_DIR}/mihomo.log</string>
  <key>StandardErrorPath</key><string>${MIHOMO_DIR}/mihomo.log</string>
</dict>
</plist>
EOF
}

mac_loaded() { mac_sudo launchctl print "$DOMAIN/$LABEL" >/dev/null 2>&1; }

# ---------------------------------------------------------------- 服务操作
# stop 后重启机器也保持停止(systemd disable / launchd disable),start 再恢复

svc_start() {
  if [[ "$OS" == "Linux" ]]; then
    $SUDO systemctl enable --now "$SERVICE"
  else
    [[ -f "$PLIST" ]] || die "未安装,请先执行 install"
    mac_sudo launchctl enable "$DOMAIN/$LABEL"
    if mac_loaded; then
      mac_sudo launchctl kickstart "$DOMAIN/$LABEL"
    else
      mac_sudo launchctl bootstrap "$DOMAIN" "$PLIST"
    fi
  fi
}

svc_stop() {
  if [[ "$OS" == "Linux" ]]; then
    $SUDO systemctl disable --now "$SERVICE"
  else
    mac_sudo launchctl disable "$DOMAIN/$LABEL"
    if mac_loaded; then mac_sudo launchctl bootout "$DOMAIN/$LABEL"; fi
  fi
}

svc_restart() {
  if [[ "$OS" == "Linux" ]]; then
    $SUDO systemctl enable "$SERVICE" >/dev/null 2>&1
    $SUDO systemctl restart "$SERVICE"
  elif mac_loaded; then
    mac_sudo launchctl kickstart -k "$DOMAIN/$LABEL"
  else
    svc_start
  fi
}

# ---------------------------------------------------------------- 命令

print_usage_hint() {
  local cred test_cmd
  cred="$(cat "$DATA_DIR/credentials" 2>/dev/null || echo 'user:pass')"
  if [[ "$MIHOMO_TUN" == "true" ]]; then
    test_cmd="curl https://api.ipify.org"
  else
    test_cmd="curl -x http://${cred}@127.0.0.1:7890 https://api.ipify.org"
  fi
  cat <<EOF

  TUN      ${MIHOMO_TUN}
  模式     ${MIHOMO_MODE}
  配置     $DATA_DIR/config.yaml
  认证     $DATA_DIR/credentials
  代理     127.0.0.1:7890  (HTTP/SOCKS5, ${cred})

  测试出口: ${test_cmd}

  管理: $MIHOMO_DIR/mihomo.sh <命令>
    start / stop / restart / status / logs / uninstall
    switch '<链接>'      切换上游节点
    tun on|off           开关 TUN
    mode global|rule     全局 / 国内直连分流
EOF
}

# 校验配置,失败则用备份回滚
check_config_or_rollback() {
  local backup="$1"
  if ! "$BIN" -t -d "$DATA_DIR" -f "$DATA_DIR/config.yaml" >/dev/null; then
    [[ -n "$backup" && -f "$backup" ]] && mv "$backup" "$DATA_DIR/config.yaml"
    die "配置校验失败,已回滚到原配置"
  fi
  [[ -n "$backup" ]] && rm -f "$backup"
  return 0
}

backup_config() {
  local backup="$DATA_DIR/config.yaml.bak"
  cp -p "$DATA_DIR/config.yaml" "$backup"
  printf '%s' "$backup"
}

require_installed() {
  [[ -x "$BIN" && -f "$DATA_DIR/config.yaml" ]] || die "未安装,请先执行 install"
}

cmd_switch() {
  require_installed
  [[ -n "${1:-}" ]] && VPN1_LINK="$1"
  [[ -n "${VPN1_LINK:-}" || -n "${VPN1_SERVER:-}" ]] ||
    die "用法: $0 switch '<vless/http/https/socks5 链接>'(或设 VPN1_LINK / VPN1_* 环境变量)"
  local backup
  backup="$(backup_config)"
  # 链接解析失败时 render_config 不会动配置,只需清掉备份
  trap 'rm -f "$DATA_DIR/config.yaml.bak"' EXIT
  render_config
  check_config_or_rollback "$backup"
  svc_restart
  log "已切换上游节点并重启"
}

cmd_mode() {
  require_installed
  case "${1:-}" in
    global | rule) ;;
    *) die "用法: $0 mode global|rule(当前 mode=$MIHOMO_MODE)" ;;
  esac
  local backup
  backup="$(backup_config)"
  write_mode_config "$1"
  check_config_or_rollback "$backup"
  MIHOMO_MODE="$1"
  svc_restart
  log "已重启生效"
}

cmd_tun() {
  require_installed
  local want old
  case "${1:-}" in
    on) want=true ;;
    off) want=false ;;
    *) die "用法: $0 tun on|off(当前 TUN=$MIHOMO_TUN)" ;;
  esac
  old="$MIHOMO_TUN"
  local backup
  backup="$(backup_config)"
  write_tun_config "$want"
  check_config_or_rollback "$backup"
  if [[ "$OS" == "Darwin" && "$old" != "$want" ]]; then
    # TUN 开关会在系统级/用户级 launchd 之间搬家,先卸旧的再装新的
    if mac_loaded; then mac_sudo launchctl bootout "$DOMAIN/$LABEL"; fi
    mac_sudo rm -f "$PLIST"
    MIHOMO_TUN="$want"
    set_mac_target "$want"
    mac_write_plist
    svc_start
  else
    MIHOMO_TUN="$want"
    svc_restart
  fi
  log "已重启生效"
}

cmd_install() {
  command -v curl >/dev/null 2>&1 || die "需要 curl"
  command -v openssl >/dev/null 2>&1 || die "需要 openssl"
  mkdir -p "$MIHOMO_DIR"
  render_config
  install_bin
  "$BIN" -t -d "$DATA_DIR" -f "$DATA_DIR/config.yaml" >/dev/null || die "配置校验失败: $DATA_DIR/config.yaml"
  if [[ "$OS" == "Linux" ]]; then
    linux_write_unit
  else
    if mac_loaded; then mac_sudo launchctl bootout "$DOMAIN/$LABEL"; fi
    mac_write_plist
  fi
  install_self
  svc_restart
  log "安装完成,目录 $MIHOMO_DIR"
  print_usage_hint
}

cmd_status() {
  echo "TUN=$MIHOMO_TUN  模式=$MIHOMO_MODE  配置 $DATA_DIR/config.yaml"
  if [[ "$OS" == "Linux" ]]; then
    systemctl status "$SERVICE" --no-pager || true
  elif mac_loaded; then
    mac_sudo launchctl print "$DOMAIN/$LABEL" | grep -E 'state =|pid =' || true
  else
    echo "未运行"
  fi
}

cmd_logs() {
  if [[ "$OS" == "Linux" ]]; then
    $SUDO journalctl -u "$SERVICE" -n 100 -f
  else
    tail -n 100 -f "$MIHOMO_DIR/mihomo.log"
  fi
}

cmd_uninstall() {
  if [[ "$OS" == "Linux" ]]; then
    $SUDO systemctl disable --now "$SERVICE" 2>/dev/null || true
    $SUDO rm -f "$UNIT"
    $SUDO systemctl daemon-reload
  else
    if mac_loaded; then mac_sudo launchctl bootout "$DOMAIN/$LABEL"; fi
    mac_sudo launchctl enable "$DOMAIN/$LABEL" 2>/dev/null || true
    mac_sudo rm -f "$PLIST"
  fi
  log "已卸载服务,配置保留在 $MIHOMO_DIR(不需要可手动 rm -rf)"
}

case "${1:-install}" in
  install) cmd_install ;;
  start) svc_start && log "已启动" ;;
  stop) svc_stop && log "已停止(重启机器后也保持停止,start 恢复)" ;;
  restart) svc_restart && log "已重启" ;;
  status) cmd_status ;;
  logs) cmd_logs ;;
  uninstall) cmd_uninstall ;;
  switch) cmd_switch "${2:-}" ;;
  tun) cmd_tun "${2:-}" ;;
  mode) cmd_mode "${2:-}" ;;
  *) die "用法: $0 [install|start|stop|restart|status|logs|uninstall|switch <链接>|tun on|off|mode global|rule]" ;;
esac
