#!/bin/bash
# ================================================
# SSH 端口修改脚本（systemd socket 方式）
# 用法: sudo bash change_ssh_port.sh 22922
# ================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log()    { echo -e "${GREEN}[✓]${NC} $1"; }
warn()   { echo -e "${YELLOW}[!]${NC} $1"; }
error()  { echo -e "${RED}[✗]${NC} $1"; exit 1; }
info()   { echo -e "${BLUE}[→]${NC} $1"; }

# ---- 检查 root ----
[[ $EUID -ne 0 ]] && error "请用 sudo 运行此脚本"

# ---- 读取端口参数 ----
NEW_PORT=${1:-22922}

if ! [[ "$NEW_PORT" =~ ^[0-9]+$ ]] || [ "$NEW_PORT" -lt 1 ] || [ "$NEW_PORT" -gt 65535 ]; then
    error "端口号无效: $NEW_PORT（需在 1~65535 之间）"
fi

echo ""
echo "================================================"
echo "  SSH 端口修改脚本"
echo "  目标端口: $NEW_PORT"
echo "================================================"
echo ""

# ---- 检查是否 socket 模式 ----
if ! systemctl is-active --quiet ssh.socket 2>/dev/null; then
    warn "ssh.socket 未激活，尝试直接修改 sshd_config..."
    sed -i "s/^#*Port .*/Port $NEW_PORT/" /etc/ssh/sshd_config
    systemctl restart ssh
    log "已通过 sshd_config 修改端口为 $NEW_PORT"
else
    info "检测到 ssh.socket 模式，使用 override.conf 修改..."

    # 创建 override 目录和文件
    mkdir -p /etc/systemd/system/ssh.socket.d/

    cat > /etc/systemd/system/ssh.socket.d/override.conf << EOF
[Socket]
ListenStream=
ListenStream=0.0.0.0:${NEW_PORT}
ListenStream=[::]:${NEW_PORT}
EOF

    log "已写入 /etc/systemd/system/ssh.socket.d/override.conf"

    # 重载
    info "重载 systemd 配置..."
    systemctl daemon-reload

    info "重启 ssh.socket..."
    systemctl restart ssh.socket

    log "ssh.socket 重启完成"
fi

# ---- 防火墙处理 ----
echo ""
info "检查防火墙..."

if command -v ufw &>/dev/null && ufw status | grep -q "Status: active"; then
    ufw allow "$NEW_PORT"/tcp
    log "ufw 已放行端口 $NEW_PORT"
elif command -v firewall-cmd &>/dev/null; then
    firewall-cmd --permanent --add-port="$NEW_PORT"/tcp
    firewall-cmd --reload
    log "firewalld 已放行端口 $NEW_PORT"
else
    warn "未检测到活跃防火墙，跳过防火墙配置"
fi

# ---- 验证 ----
echo ""
info "验证监听状态..."
sleep 1

if ss -tlnp | grep -q ":$NEW_PORT"; then
    log "端口 $NEW_PORT 监听成功！"
    ss -tlnp | grep ":$NEW_PORT"
else
    error "端口 $NEW_PORT 未检测到监听，请手动排查"
fi

echo ""
echo "================================================"
echo -e "  ${GREEN}完成！请用新端口重新连接：${NC}"
echo "  ssh -p $NEW_PORT 用户名@服务器IP"
echo "  ⚠️  请勿关闭当前会话，先测试新端口能否连接"
echo "================================================"
echo ""