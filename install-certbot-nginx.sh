#!/bin/bash
# Install nginx, certbot, and the certbot nginx plugin on Debian/Ubuntu.

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${GREEN}[OK]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
info() { echo -e "${BLUE}[INFO]${NC} $1"; }

if [[ $EUID -ne 0 ]]; then
    error "Please run this script with sudo or as root."
fi

if ! command -v apt-get >/dev/null 2>&1; then
    error "This script currently supports Debian/Ubuntu systems with apt-get."
fi

export DEBIAN_FRONTEND=noninteractive

info "Updating apt package index..."
apt-get update

info "Installing nginx, certbot, and python3-certbot-nginx..."
apt-get install -y nginx certbot python3-certbot-nginx

if command -v systemctl >/dev/null 2>&1; then
    info "Enabling and starting nginx..."
    systemctl enable nginx
    systemctl restart nginx
else
    warn "systemctl not found, skipping nginx service enable/restart."
fi

if command -v ufw >/dev/null 2>&1 && ufw status | grep -q "Status: active"; then
    info "Opening nginx ports in ufw..."
    ufw allow 'Nginx Full'
fi

info "Verifying installation..."
nginx -v
certbot --version

if certbot plugins 2>/dev/null | grep -q "nginx"; then
    log "certbot nginx plugin is installed."
else
    warn "certbot installed, but nginx plugin was not found in certbot plugins output."
fi

echo ""
log "Done. Example certificate command:"
echo "  sudo certbot --nginx -d example.com -d www.example.com"
