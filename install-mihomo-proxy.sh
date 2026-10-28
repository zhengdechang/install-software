#!/usr/bin/env bash
# mihomo 代理一键安装/管理(只含一条 vpn1 线路),官方二进制直接运行,不需要 Docker
#   Linux: systemd 托管,默认开 TUN 全局接管本机流量
#   macOS: launchd 托管,默认只开 7890 代理端口
#
# 用法: install-mihomo-proxy.sh [install|start|stop|restart|status|logs|uninstall]
#
# install 需要 vpn1 节点(VLESS + Reality),二选一:
#   VPN1_LINK='vless://uuid@host:port?security=reality&sni=...&pbk=...&sid=...#vpn1'
#   或 VPN1_SERVER / VPN1_PORT / VPN1_UUID / VPN1_SNI / VPN1_PUBLIC_KEY / VPN1_SHORT_ID
#   都不给时交互式输入 vless 链接;已安装过则沿用原配置。
#
# 可选环境变量:
#   MIHOMO_DIR      安装目录,默认 root 为 /opt/mihomo-proxy,其他用户为 ~/mihomo-proxy
#   MIHOMO_TUN      true/false,Linux 默认 true,macOS 默认 false(macOS 开 TUN 需 sudo)
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

case "$OS" in
  Linux) MIHOMO_TUN="${MIHOMO_TUN:-true}" ;;
  Darwin) MIHOMO_TUN="${MIHOMO_TUN:-false}" ;;
  *) echo "不支持的系统 $OS" >&2; exit 1 ;;
esac

log() { printf '\033[32m[mihomo]\033[0m %s\n' "$*"; }
die() { printf '\033[31m[mihomo]\033[0m %s\n' "$*" >&2; exit 1; }

# ---------------------------------------------------------------- 配置渲染

sed_escape() { printf '%s' "$1" | sed -e 's/[|&\\]/\\&/g'; }

parse_vless_link() {
  local link="${1#vless://}" rest hostport query kv k v
  link="${link%%#*}"
  VPN1_UUID="${link%%@*}"
  rest="${link#*@}"
  hostport="${rest%%\?*}"
  hostport="${hostport%/}"
  query=""
  [[ "$rest" == *\?* ]] && query="${rest#*\?}"
  VPN1_PORT="${hostport##*:}"
  VPN1_SERVER="${hostport%:*}"
  VPN1_SERVER="${VPN1_SERVER#[}"
  VPN1_SERVER="${VPN1_SERVER%]}"
  local IFS='&'
  for kv in $query; do
    k="${kv%%=*}"
    v="${kv#*=}"
    case "$k" in
      sni) VPN1_SNI="$v" ;;
      pbk) VPN1_PUBLIC_KEY="$v" ;;
      sid) VPN1_SHORT_ID="$v" ;;
      security) [[ "$v" == "reality" ]] || die "只支持 VLESS + Reality 节点(security=$v)" ;;
    esac
  done
}

need_vpn1_input() {
  [[ -n "${VPN1_LINK:-}" || -n "${VPN1_SERVER:-}" ]] && return 0
  [[ -f "$DATA_DIR/config.yaml" ]] && return 1
  [[ -r /dev/tty ]] || die "未提供 VPN1_LINK,且无法交互输入"
  printf '请粘贴 vpn1 的 vless:// 链接: ' >/dev/tty
  read -r VPN1_LINK </dev/tty
  [[ -n "$VPN1_LINK" ]] || die "vless 链接为空"
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
    return
  fi
  [[ -n "${VPN1_LINK:-}" ]] && parse_vless_link "$VPN1_LINK"
  local v
  for v in VPN1_SERVER VPN1_PORT VPN1_UUID VPN1_SNI VPN1_PUBLIC_KEY; do
    [[ -n "${!v:-}" ]] || die "缺少 $v"
  done

  # 认证沿用已有 credentials,避免重装后客户端密码失效
  local user="" pass=""
  if [[ -f "$DATA_DIR/credentials" ]]; then
    user="$(cut -d: -f1 "$DATA_DIR/credentials")"
    pass="$(cut -d: -f2- "$DATA_DIR/credentials")"
  fi
  user="${PROXY_USER:-${user:-proxy}}"
  pass="${PROXY_PASS:-${pass:-$(openssl rand -hex 18)}}"

  local tpl tmp
  tpl="$(fetch_template)" || die "下载配置模板失败"
  tmp="$(mktemp)"
  printf '%s\n' "$tpl" | sed \
    -e "s|__TUN_ENABLE__|$(sed_escape "$MIHOMO_TUN")|g" \
    -e "s|__VPN1_SERVER__|$(sed_escape "$VPN1_SERVER")|g" \
    -e "s|__VPN1_PORT__|$(sed_escape "$VPN1_PORT")|g" \
    -e "s|__VPN1_UUID__|$(sed_escape "$VPN1_UUID")|g" \
    -e "s|__VPN1_SNI__|$(sed_escape "$VPN1_SNI")|g" \
    -e "s|__VPN1_PUBLIC_KEY__|$(sed_escape "$VPN1_PUBLIC_KEY")|g" \
    -e "s|__VPN1_SHORT_ID__|$(sed_escape "${VPN1_SHORT_ID:-}")|g" \
    -e "s|__PROXY_USER__|$(sed_escape "$user")|g" \
    -e "s|__PROXY_PASS__|$(sed_escape "$pass")|g" >"$tmp"
  mv "$tmp" "$DATA_DIR/config.yaml"
  printf '%s:%s\n' "$user" "$pass" >"$DATA_DIR/credentials"
  chmod 600 "$DATA_DIR/config.yaml" "$DATA_DIR/credentials"
  log "已生成 $DATA_DIR/config.yaml(TUN=$MIHOMO_TUN)"
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
if [[ "$MIHOMO_TUN" == "true" ]]; then
  PLIST="/Library/LaunchDaemons/$LABEL.plist"
  DOMAIN="system"
else
  PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
  DOMAIN="gui/$(id -u)"
fi

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
  local cred
  cred="$(cat "$DATA_DIR/credentials" 2>/dev/null || echo 'user:pass')"
  cat <<EOF

代理端口 7890(HTTP/SOCKS5 混合),认证 ${cred}
测试出口 IP:
  curl --proxy "http://${cred}@127.0.0.1:7890" https://api.ipify.org
管理:
  $MIHOMO_DIR/mihomo.sh start|stop|restart|status|logs|uninstall
EOF
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
  *) die "用法: $0 [install|start|stop|restart|status|logs|uninstall]" ;;
esac
