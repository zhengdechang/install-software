#!/bin/bash
# Claude Code + Feishu AI Agent 一键安装脚本
# 支持 macOS / Ubuntu / Debian

# 脚本可能通过 curl | bash 执行，stdin 是管道而非终端
# 重定向到 /dev/tty 确保所有 read 命令能正常交互
if [ ! -t 0 ]; then
    exec < /dev/tty
fi

# ============================================================
# Colors & helpers
# ============================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

info()    { echo -e "${CYAN}[INFO]${NC}  $*"; }
ok()      { echo -e "${GREEN}[ OK ]${NC}  $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
err()     { echo -e "${RED}[ERR ]${NC}  $*"; }
header()  { echo -e "\n${BOLD}${BLUE}━━━  $*  ━━━${NC}\n"; }
divider() { echo -e "${BLUE}────────────────────────────────────────────────${NC}"; }

has() { command -v "$1" &>/dev/null; }

ensure_run_as_non_root_user() {
    if [ "$(id -u)" -ne 0 ]; then
        return 0
    fi

    # 如果是通过 sudo 提权进来的，自动切回原始用户执行，避免装到 root 家目录
    if [ -n "$SUDO_USER" ] && [ "$SUDO_USER" != "root" ]; then
        local script_path
        script_path="$(readlink -f "$0" 2>/dev/null || echo "$0")"
        if [ -f "$script_path" ]; then
            warn "检测到当前为 root，自动切换到用户 $SUDO_USER 执行安装"
            exec sudo -u "$SUDO_USER" -H bash "$script_path" "$@"
        fi
        err "当前以 root 运行，且脚本来源不可重入（可能是 curl | bash）"
        err "请切换到普通用户后重新执行脚本"
        exit 1
    fi

    err "请使用普通用户执行安装脚本（不要直接用 root）"
    exit 1
}

ensure_valid_cwd() {
    # Some remote shells keep a stale/deleted cwd, which breaks git/apt/curl commands.
    if ! pwd >/dev/null 2>&1; then
        warn "当前工作目录已失效，自动切换到 $HOME"
        cd "$HOME" 2>/dev/null || cd /
    fi
}

has_claude_auth_config() {
    python3 - <<'PYEOF'
import json, os, sys
path = os.path.expanduser("~/.claude/settings.json")
try:
    with open(path, "r", encoding="utf-8") as f:
        data = json.load(f)
except Exception:
    sys.exit(1)
token = (((data or {}).get("env") or {}).get("ANTHROPIC_AUTH_TOKEN") or "").strip()
sys.exit(0 if token else 1)
PYEOF
}

has_lark_skills_installed() {
    [ -f "$HOME/.claude/skills/lark-base/SKILL.md" ] || \
    [ -L "$HOME/.claude/skills/lark-base" ] || \
    [ -d "$HOME/.claude/skills/lark-base" ]
}

is_gstack_installed() {
    [ -x "$HOME/.claude/skills/gstack/setup" ] && \
    [ -x "$HOME/.claude/skills/gstack/browse/dist/browse" ]
}

is_cc_connect_installed() {
    has cc-connect && [ -f "$HOME/.cc-connect/config.toml" ]
}

confirm_reuse() {
    # 询问是否复用已有配置；默认 y。返回 0=复用，1=重新输入。
    local desc="$1"
    local ans
    read -rp "  复用已有${desc}? [Y/n]: " ans
    case "${ans:-y}" in
        [yY]|[yY][eE][sS]|"") return 0 ;;
        *) return 1 ;;
    esac
}

load_existing_claude_config() {
    # Reuse existing Claude config from ~/.claude/settings.json if current inputs are empty.
    local current_key="${ANTHROPIC_API_KEY_INPUT:-}"
    local current_base="${ANTHROPIC_BASE_URL_INPUT:-}"
    local out

    out="$(CURRENT_KEY="$current_key" CURRENT_BASE="$current_base" python3 - <<'PYEOF'
import json, os, sys
path = os.path.expanduser("~/.claude/settings.json")
cur_key = os.environ.get("CURRENT_KEY", "")
cur_base = os.environ.get("CURRENT_BASE", "")

if not os.path.exists(path):
    print(f"{cur_key}\n{cur_base}")
    raise SystemExit(0)

try:
    with open(path, "r", encoding="utf-8") as f:
        data = json.load(f)
except Exception:
    print(f"{cur_key}\n{cur_base}")
    raise SystemExit(0)

env = (data or {}).get("env") or {}
key = cur_key or (env.get("ANTHROPIC_AUTH_TOKEN") or "").strip()
base = cur_base or (env.get("ANTHROPIC_BASE_URL") or "").strip()
print(key)
print(base)
PYEOF
)"

    ANTHROPIC_API_KEY_INPUT="$(echo "$out" | sed -n '1p')"
    ANTHROPIC_BASE_URL_INPUT="$(echo "$out" | sed -n '2p')"
}

load_existing_feishu_config() {
    # Reuse existing Feishu app_id/app_secret from ~/.cc-connect/config.toml if missing.
    [ -z "${APP_ID:-}" ] || [ -z "${APP_SECRET:-}" ] || return 0

    local cfg="$HOME/.cc-connect/config.toml"
    [ -f "$cfg" ] || return 0

    if [ -z "${APP_ID:-}" ]; then
        APP_ID="$(sed -n 's/^[[:space:]]*app_id[[:space:]]*=[[:space:]]*"\(.*\)".*/\1/p' "$cfg" | head -n 1)"
    fi
    if [ -z "${APP_SECRET:-}" ]; then
        APP_SECRET="$(sed -n 's/^[[:space:]]*app_secret[[:space:]]*=[[:space:]]*"\(.*\)".*/\1/p' "$cfg" | head -n 1)"
    fi
}

# ============================================================
# OS 检测
# ============================================================
detect_os() {
    OS="$(uname -s)"
    case "$OS" in
        Darwin)
            OS_TYPE="macos"
            OS_NAME="macOS $(sw_vers -productVersion 2>/dev/null || echo '')"
            SHELL_RC="$HOME/.zshrc"
            # 如果用户用的是 bash
            [ "$SHELL" = "/bin/bash" ] && SHELL_RC="$HOME/.bash_profile"
            ;;
        Linux)
            OS_TYPE="linux"
            if [ -f /etc/os-release ]; then
                . /etc/os-release
                OS_NAME="$NAME $VERSION_ID"
            else
                OS_NAME="Linux"
            fi
            SHELL_RC="$HOME/.bashrc"
            ;;
        *)
            err "不支持的操作系统: $OS"
            exit 1
            ;;
    esac
    export OS_TYPE OS_NAME SHELL_RC
}

# ============================================================
# OS 差异封装
# ============================================================

# sed -i 兼容（macOS 需要 sed -i ''）
sed_i() {
    if [ "$OS_TYPE" = "macos" ]; then
        sed -i '' "$@"
    else
        sed -i "$@"
    fi
}

# 包管理器安装
pkg_install() {
    if [ "$OS_TYPE" = "macos" ]; then
        brew install "$@"
    else
        sudo apt-get install -y "$@" -qq
    fi
}

# 包管理器更新
pkg_update() {
    if [ "$OS_TYPE" = "macos" ]; then
        brew update
    else
        # 修复损坏的 cdrom apt 源（Ubuntu 镜像常见问题）
        if grep -qE "^deb.*cdrom" /etc/apt/sources.list 2>/dev/null; then
            sudo sed -i \
                -e 's|^deb \[check-date=no\] file:///cdrom|# deb [check-date=no] file:///cdrom|g' \
                -e 's|^deb cdrom:|# deb cdrom:|g' \
                /etc/apt/sources.list
            info "已注释掉损坏的 cdrom apt 源"
        fi
        sudo apt-get update -qq
    fi
}

# ============================================================
# NVM & Node
# ============================================================
load_nvm() {
    export NVM_DIR="$HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
    [ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"
}

load_bun() {
    export PATH="$HOME/.bun/bin:$PATH"
}

persist_bun_path() {
    touch "$SHELL_RC"
    if ! grep -Fq 'export PATH="$HOME/.bun/bin:$PATH"' "$SHELL_RC"; then
        echo 'export PATH="$HOME/.bun/bin:$PATH"' >> "$SHELL_RC"
    fi
}

cpu_has_avx() {
    # Only meaningful on Linux; other OS treat as supported.
    if [ "$OS_TYPE" != "linux" ]; then
        return 0
    fi
    grep -m1 -i '^flags' /proc/cpuinfo 2>/dev/null | grep -qw 'avx'
}

install_nvm_node() {
    header "NVM + Node.js 24"
    load_nvm

    # 已安装且主版本已满足，直接跳过
    if has nvm && has node && node -v 2>/dev/null | grep -qE '^v24\.'; then
        warn "NVM + Node.js 24 已安装，跳过"
        return 0
    fi

    if has nvm; then
        warn "NVM 已安装，检查 Node.js 版本..."
    else
        info "下载并安装 NVM..."
        curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash
        load_nvm
        ok "NVM 安装完成"
    fi

    info "安装 Node.js 24..."
    nvm install 24
    nvm use 24
    nvm alias default 24
    ok "Node.js $(node -v) / npm $(npm -v)"
}

# ============================================================
# 写入 ~/.claude/settings.json（daemon 读取环境变量的来源）
# ============================================================
write_claude_settings() {
    local api_key="$1"
    local base_url="$2"

    mkdir -p "$HOME/.claude"

    CLAUDE_API_KEY="$api_key" CLAUDE_BASE_URL="$base_url" python3 - <<'PYEOF'
import json, os

settings_path = os.path.expanduser('~/.claude/settings.json')
api_key  = os.environ.get('CLAUDE_API_KEY', '')
base_url = os.environ.get('CLAUDE_BASE_URL', '')

try:
    with open(settings_path) as f:
        settings = json.load(f)
except (FileNotFoundError, json.JSONDecodeError):
    settings = {}

settings['model'] = 'claude-opus-4-7'

env = settings.setdefault('env', {})
env.pop('ANTHROPIC_API_KEY', None)          # 移除旧格式
env['ANTHROPIC_AUTH_TOKEN'] = api_key        # daemon/sdk 统一用 Bearer token
env['CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC'] = '1'
env['CLAUDE_CODE_ATTRIBUTION_HEADER'] = '0'
if base_url:
    env['ANTHROPIC_BASE_URL'] = base_url
else:
    env.pop('ANTHROPIC_BASE_URL', None)

with open(settings_path, 'w') as f:
    json.dump(settings, f, indent=2)
    f.write('\n')
PYEOF
    ok "API Key 已写入 $HOME/.claude/settings.json"
}

set_claude_settings_model_opus_46() {
    mkdir -p "$HOME/.claude"

    python3 - <<'PYEOF'
import json
import os

settings_path = os.path.expanduser('~/.claude/settings.json')

try:
    with open(settings_path, 'r', encoding='utf-8') as f:
        settings = json.load(f)
except (FileNotFoundError, json.JSONDecodeError):
    settings = {}

settings['model'] = 'opus'

with open(settings_path, 'w', encoding='utf-8') as f:
    json.dump(settings, f, indent=2)
    f.write('\n')
PYEOF
}

set_claude_settings_model_opus_47() {
    header "Claude模型更新4.7"
    mkdir -p "$HOME/.claude"

    python3 - <<'PYEOF'
import json
import os

settings_path = os.path.expanduser('~/.claude/settings.json')

try:
    with open(settings_path, 'r', encoding='utf-8') as f:
        settings = json.load(f)
except (FileNotFoundError, json.JSONDecodeError):
    settings = {}

settings['model'] = 'claude-opus-4-7'

with open(settings_path, 'w', encoding='utf-8') as f:
    json.dump(settings, f, indent=2)
    f.write('\n')
PYEOF

    ok "已更新 $HOME/.claude/settings.json: model = claude-opus-4-7"
}

# ============================================================
# Claude Code
# ============================================================
install_claude_code() {
    header "Claude Code"
    load_nvm
    load_existing_claude_config

    if has claude; then
        warn "Claude Code 已安装: $(claude --version 2>&1 | head -1 || echo '未知版本')"
    else
        info "安装 @anthropic-ai/claude-code..."
        npm install -g @anthropic-ai/claude-code
        ok "Claude Code 安装完成"
    fi

    # 已有配置时询问是否复用
    if [ -n "$ANTHROPIC_API_KEY_INPUT" ] && has_claude_auth_config; then
        echo
        echo -e "${BOLD}  Claude API 配置${NC}"
        divider
        if confirm_reuse "Claude API 配置"; then
            info "复用已有 Claude API 配置"
            divider
            return 0
        fi
        ANTHROPIC_API_KEY_INPUT=""
        ANTHROPIC_BASE_URL_INPUT=""
        read -rsp "  Anthropic API Key (sk-ant-...): " ANTHROPIC_API_KEY_INPUT
        echo
        read -rp "  Base URL (留空使用官方 https://api.anthropic.com): " ANTHROPIC_BASE_URL_INPUT
        divider
    elif [ -z "$ANTHROPIC_API_KEY_INPUT" ]; then
        echo
        echo -e "${BOLD}  Claude API 配置${NC}"
        divider
        read -rsp "  Anthropic API Key (sk-ant-...): " ANTHROPIC_API_KEY_INPUT
        echo
        read -rp "  Base URL (留空使用官方 https://api.anthropic.com): " ANTHROPIC_BASE_URL_INPUT
        divider
    fi

    if [ -z "$ANTHROPIC_API_KEY_INPUT" ]; then
        warn "未输入 API Key，跳过环境变量配置"
        warn "请手动设置: export ANTHROPIC_API_KEY=your_key"
        return 0
    fi

    # 写入 shell RC 文件（去重后追加）
    touch "$SHELL_RC"
    sed_i '/^export ANTHROPIC_API_KEY=/d' "$SHELL_RC"
    sed_i '/^export ANTHROPIC_BASE_URL=/d' "$SHELL_RC"

    echo "export ANTHROPIC_API_KEY=\"$ANTHROPIC_API_KEY_INPUT\"" >> "$SHELL_RC"
    if [ -n "$ANTHROPIC_BASE_URL_INPUT" ]; then
        echo "export ANTHROPIC_BASE_URL=\"$ANTHROPIC_BASE_URL_INPUT\"" >> "$SHELL_RC"
    fi

    # 当前 session 立即生效
    export ANTHROPIC_API_KEY="$ANTHROPIC_API_KEY_INPUT"
    [ -n "$ANTHROPIC_BASE_URL_INPUT" ] && export ANTHROPIC_BASE_URL="$ANTHROPIC_BASE_URL_INPUT"

    ok "API Key 已写入 $SHELL_RC"
    [ -n "$ANTHROPIC_BASE_URL_INPUT" ] \
        && ok "Base URL: $ANTHROPIC_BASE_URL_INPUT" \
        || info "Base URL: 使用官方默认"

    # 同步写入 ~/.claude/settings.json，供 daemon 读取
    write_claude_settings "$ANTHROPIC_API_KEY_INPUT" "$ANTHROPIC_BASE_URL_INPUT"

    # 若 cc-connect daemon 已在运行，自动重启以加载新配置
    if has cc-connect && cc-connect daemon status 2>&1 | grep -q "Running"; then
        info "检测到 cc-connect 正在运行，重启以加载新配置..."
        cc-connect daemon restart
        ok "cc-connect 已重启"
    fi
}

# ============================================================
# Homebrew (macOS)
# ============================================================
ensure_brew() {
    if [ "$OS_TYPE" != "macos" ]; then return 0; fi
    if has brew; then return 0; fi

    info "安装 Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

    # Apple Silicon 路径
    if [ -f /opt/homebrew/bin/brew ]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
        echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> "$SHELL_RC"
    fi
    ok "Homebrew 安装完成"
}

# ============================================================
# 飞书 CLI + Lark Skills
# ============================================================
install_feishu_cli() {
    header "飞书 CLI + Lark Skills"
    load_nvm
    load_existing_feishu_config

    if has lark-cli; then
        warn "飞书 CLI 已安装，跳过安装步骤"
    else
        info "安装 @larksuite/cli..."
        npm install -g @larksuite/cli
        ok "飞书 CLI 安装完成"
    fi

    if has_lark_skills_installed; then
        warn "Lark Skills 已安装，跳过安装步骤"
    else
        info "安装 Lark Skills (23 个)..."
        npx skills add https://github.com/larksuite/cli -y -g
        ok "Lark Skills 安装完成"
    fi

    if [ -n "$APP_ID" ] && [ -n "$APP_SECRET" ]; then
        info "复用已有飞书配置 (App ID: $APP_ID)"
        info "配置 lark-cli (App ID: $APP_ID)..."
        echo "$APP_SECRET" | lark-cli config init --app-id "$APP_ID" --app-secret-stdin
        ok "lark-cli 配置完成"
        echo
        warn "用户授权（可选）: 运行以下命令完成飞书账号登录"
        echo "    lark-cli auth login --recommend"
    else
        warn "未提供 App ID，跳过 lark-cli 配置"
    fi
}

# ============================================================
# bun
# ============================================================
install_bun() {
    load_bun
    if [ ! -x "$(command -v bun 2>/dev/null)" ] && [ -x "$HOME/.bun/bin/bun" ]; then
        load_bun
    fi

    if has bun; then
        persist_bun_path
        warn "bun 已安装: v$(bun --version)"
        return 0
    fi

    if [ "$OS_TYPE" = "linux" ]; then
        info "安装 unzip (bun 前置依赖)..."
        pkg_update
        pkg_install unzip
    fi
    # macOS：unzip 系统自带，无需安装

    info "安装 bun..."
    curl -fsSL https://bun.sh/install | bash
    load_bun
    if ! has bun; then
        err "bun 安装后仍不可用，请检查 ~/.bun/bin/bun 是否存在"
        return 1
    fi
    persist_bun_path
    ok "bun v$(bun --version) 安装完成"
    info "已将 bun PATH 写入 $SHELL_RC（新终端自动生效）"
}

patch_gstack_for_non_avx() {
    local gstack_dir="$1"
    local build_fix_marker=0
    local non_avx_marker=0
    local setup_node_fallback_marker=0

    if [ ! -d "$gstack_dir" ]; then
        return 1
    fi

    # Fix Bun build regression: server build may output extra assets, so outfile breaks.
    build_fix_marker="$(python3 - "$gstack_dir" <<'PYEOF'
import sys
from pathlib import Path

root = Path(sys.argv[1])
changed = False

build_node = root / "browse" / "scripts" / "build-node-server.sh"
if build_node.exists():
    text = build_node.read_text(encoding="utf-8")
    old = '--outfile "$DIST_DIR/server-node.mjs"'
    new = '--outdir "$DIST_DIR" \\\n  --entry-naming "server-node.mjs"'
    if old in text and '--outdir "$DIST_DIR"' not in text:
        build_node.write_text(text.replace(old, new, 1), encoding="utf-8")
        changed = True

print("1" if changed else "0")
PYEOF
)"

    # Non-AVX machines: avoid bun run gen:skill-docs during build (known Bun crash).
    if ! cpu_has_avx; then
        non_avx_marker="$(python3 - "$gstack_dir" <<'PYEOF'
import json, re, sys
from pathlib import Path

pkg = Path(sys.argv[1]) / "package.json"
if not pkg.exists():
    print("0")
    raise SystemExit(0)

data = json.loads(pkg.read_text(encoding="utf-8"))
scripts = data.get("scripts", {})
build = scripts.get("build")
if not isinstance(build, str):
    print("0")
    raise SystemExit(0)

if "bun run gen:skill-docs --host all" not in build:
    print("0")
    raise SystemExit(0)

build = re.sub(r"\bbun run gen:skill-docs --host all;?\s*", "", build, count=1)
scripts["build"] = build
data["scripts"] = scripts
pkg.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print("1")
PYEOF
)"
        if [ "$non_avx_marker" = "1" ]; then
            warn "检测到 CPU 无 AVX：已跳过 gstack build 里的 gen:skill-docs（避免 Bun 崩溃）"
        fi
    fi

    if [ "$build_fix_marker" = "1" ]; then
        info "已修复 gstack Node server 打包参数（兼容 Bun 多产物输出）"
    fi

    # Some Linux servers fail to launch Playwright via Bun runtime.
    # Patch setup to try Node first, then fallback to Bun.
    setup_node_fallback_marker="$(python3 - "$gstack_dir" <<'PYEOF'
import sys
from pathlib import Path

root = Path(sys.argv[1])
setup = root / "setup"
if not setup.exists():
    print("0")
    raise SystemExit(0)

text = setup.read_text(encoding="utf-8")
old = "      bun --eval 'import { chromium } from \"playwright\"; const browser = await chromium.launch(); await browser.close();'"

if old not in text or "node -e \"const { chromium } = require('playwright')" in text:
    print("0")
    raise SystemExit(0)

new = """      if command -v node >/dev/null 2>&1; then
        node -e "const { chromium } = require('playwright'); (async () => { const b = await chromium.launch(); await b.close(); })()" 2>/dev/null \\
          || bun --eval 'import { chromium } from "playwright"; const browser = await chromium.launch(); await browser.close();'
      else
        bun --eval 'import { chromium } from "playwright"; const browser = await chromium.launch(); await browser.close();'
      fi"""

setup.write_text(text.replace(old, new, 1), encoding="utf-8")
print("1")
PYEOF
)"
    if [ "$setup_node_fallback_marker" = "1" ]; then
        info "已为 gstack setup 注入 Node 回退逻辑（Playwright 启动更稳定）"
    fi

    return 0
}

# ============================================================
# gstack
# ============================================================
install_gstack() {
    header "gstack (AI 工程工作流)"
    local gstack_dir="$HOME/.claude/skills/gstack"
    ensure_valid_cwd
    load_nvm
    install_bun || return 1

    if is_gstack_installed; then
        warn "gstack 已安装，跳过"
        return 0
    fi

    # If current shell is inside gstack dir, deleting it will invalidate $PWD.
    # Move to a safe directory first.
    if [ -d "$gstack_dir" ]; then
        case "$PWD" in
            "$gstack_dir"|"$gstack_dir"/*)
                warn "当前目录位于 gstack 安装目录内，先切换到 $HOME"
                cd "$HOME" || cd /
                ;;
        esac
    fi

    if [ -d "$gstack_dir" ]; then
        warn "检测到旧的 gstack 目录，但安装不完整，自动清理后重装"
        rm -rf "$gstack_dir"
        # Ensure cwd is still valid even if shell started from removed directory.
        pwd >/dev/null 2>&1 || cd "$HOME" || cd /
    fi

    info "检查系统依赖..."
    if [ "$OS_TYPE" = "linux" ]; then
        # Linux 需要 apt 元数据，后续 playwright install-deps 会用到
        pkg_update || {
            err "apt 更新失败，无法安装 Playwright 依赖"
            return 1
        }
    fi

    info "克隆 gstack..."
    ensure_valid_cwd
    git clone --single-branch --depth 1 \
        https://github.com/garrytan/gstack.git \
        "$gstack_dir" || {
            err "gstack 克隆失败"
            return 1
        }

    info "应用 gstack 兼容补丁..."
    patch_gstack_for_non_avx "$gstack_dir" || warn "兼容补丁应用失败，将继续尝试 setup"

    if [ "$OS_TYPE" = "linux" ]; then
        info "安装 Playwright Linux 运行时依赖..."
        (
            cd "$gstack_dir" && \
            (bunx playwright install-deps chromium || (command -v npx >/dev/null 2>&1 && npx -y playwright install-deps chromium))
        ) || {
            err "Playwright Linux 依赖安装失败（请检查 sudo 权限和 apt 源）"
            return 1
        }
    fi

    info "安装 Playwright Chromium..."
    (
        cd "$gstack_dir" && \
        (bunx playwright install chromium || (command -v npx >/dev/null 2>&1 && npx -y playwright install chromium))
    ) || warn "Playwright Chromium 预安装失败，setup 将继续重试"

    info "运行 gstack setup..."
    (
        cd "$gstack_dir" && PATH="$HOME/.bun/bin:$PATH" ./setup --host claude
    )
    local setup_rc=$?
    if [ "$setup_rc" -ne 0 ]; then
        err "gstack setup 失败（退出码: $setup_rc）"
        warn "可手动重试: export PATH=\"$HOME/.bun/bin:\$PATH\" && cd ~/.claude/skills/gstack && ./setup --host claude"
        return 1
    fi

    ok "gstack 安装完成 (37 个 skills)"
}

# ============================================================
# cc-connect
# ============================================================
set_cc_connect_agent_model_opus_47() {
    local cfg="$HOME/.cc-connect/config.toml"
    [ -f "$cfg" ] || return 1

    python3 - "$cfg" <<'PYEOF'
import pathlib
import re
import sys

path = pathlib.Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
lines = text.splitlines()

inside = False
changed = False
for idx, line in enumerate(lines):
    stripped = line.strip()
    if stripped == "[projects.agent.options]":
        inside = True
        continue
    if inside and stripped.startswith("["):
        inside = False
    if inside and re.match(r"^\s*model\s*=", line):
        indent = re.match(r"^(\s*)", line).group(1)
        lines[idx] = f'{indent}model = "claude-opus-4-7"'
        changed = True
        break

if not changed:
    sys.exit(1)

path.write_text("\n".join(lines) + "\n", encoding="utf-8")
PYEOF
}

refresh_cc_connect_daemon() {
    info "配置后台服务..."
    if cc-connect daemon status 2>&1 | grep -qE "Running|Stopped|Installed"; then
        cc-connect daemon uninstall 2>/dev/null || true
    fi
    cc-connect daemon install --work-dir "$HOME/.cc-connect"

    # Linux 额外配置 linger（开机无需登录即自启）
    if [ "$OS_TYPE" = "linux" ]; then
        info "配置开机自启 (loginctl linger)..."
        sudo loginctl enable-linger "$USER"
        ok "开机自启已配置 (systemd linger)"
    else
        ok "开机自启已配置 (launchd)"
    fi

    sleep 2
    echo
    cc-connect daemon status
}

install_cc_connect() {
    header "cc-connect (飞书 AI 机器人)"
    load_nvm
    load_existing_feishu_config

    if is_cc_connect_installed; then
        warn "cc-connect 已安装，跳过"
        cc-connect daemon status 2>/dev/null || true
        return 0
    fi

    # 确保 npm 可用
    if ! has npm; then
        warn "npm 未找到，尝试安装 NVM + Node.js..."
        install_nvm_node || {
            err "Node.js 安装失败，无法继续安装 cc-connect"
            return 1
        }
        load_nvm
    fi

    info "安装 cc-connect..."
    npm install -g cc-connect@latest || {
        err "cc-connect 安装失败"
        return 1
    }
    ok "cc-connect $(cc-connect --version 2>&1 | grep -oE 'v[0-9]+\.[0-9]+\.[^ ]+') 安装完成"

    # 生成随机 token
    BRIDGE_TOKEN=$(openssl rand -hex 16)
    MGMT_TOKEN=$(openssl rand -hex 32)

    local work_dir="${HOME:-}"
    if [ -z "$work_dir" ]; then
        work_dir="$(eval echo "~$(id -un)")"
    fi
    if [ -z "$work_dir" ] || [ "$work_dir" = "~$(id -un)" ]; then
        err "无法自动获取当前用户主目录，退出"
        return 1
    fi

    info "写入基础配置 ~/.cc-connect/config.toml..."
    mkdir -p "$HOME/.cc-connect"
    cat > "$HOME/.cc-connect/config.toml" <<TOML
data_dir = ""
attachment_send = ""
language = "en"

[[projects]]
  name = "default"
  show_context_indicator = true
  quiet = false

  [projects.agent]
    type = "claudecode"

    [projects.agent.options]
      mode = "bypassPermissions"
      model = "claude-opus-4-7"
      work_dir = "$work_dir"

[log]
  level = "info"

[speech]
  enabled = false
  provider = ""
  language = ""

  [speech.openai]
    api_key = ""
    base_url = ""
    model = ""

  [speech.groq]
    api_key = ""
    model = ""

  [speech.qwen]
    api_key = ""
    base_url = ""
    model = ""

[tts]
  enabled = false
  provider = ""
  voice = ""
  tts_mode = ""
  max_text_len = 0

  [tts.openai]
    api_key = ""
    base_url = ""
    model = ""

  [tts.qwen]
    api_key = ""
    base_url = ""
    model = ""

  [tts.minimax]
    api_key = ""
    base_url = ""
    model = ""

[display]
  thinking_max_len = 300
  tool_max_len = 500

[stream_preview]
  enabled = true
  interval_ms = 1500
  min_delta_chars = 30
  max_chars = 2000

[webhook]
  port = 0

[bridge]
  enabled = true
  port = 9810
  token = "$BRIDGE_TOKEN"
  path = "/bridge/ws"

[management]
  enabled = true
  port = 9820
  token = "$MGMT_TOKEN"
  cors_origins = ["*"]
TOML
    ok "基础配置写入完成"
    info "Bridge token:     $BRIDGE_TOKEN"
    info "Management token: $MGMT_TOKEN"

    # 选择飞书凭据配置方式
    echo
    echo -e "${BOLD}  飞书机器人配置${NC}"
    divider
    echo -e "  ${CYAN}1)${NC}  扫码创建/绑定  ${YELLOW}← 推荐（无需手动输入 App ID）${NC}"
    echo -e "  ${CYAN}2)${NC}  手动输入 App ID / App Secret"
    echo -e "  ${CYAN}3)${NC}  跳过（稍后手动配置）"
    echo
    local feishu_choice
    read -rp "  请选择 [1-3]: " feishu_choice

    case "$feishu_choice" in
        1)
            # QR 扫码方式：cc-connect feishu setup 自动创建机器人
            echo
            info "即将显示飞书二维码，请用飞书 App 扫码完成机器人创建..."
            info "（超时时间 10 分钟，按 Ctrl+C 可取消）"
            local qr_png="/tmp/feishu-qr-$$.png"
            info "二维码同时保存到: $qr_png"
            echo
            QR_SMALL=1 cc-connect feishu setup --project default --timeout 600 --qr-image "$qr_png"
            local qr_rc=$?
            if [ "$qr_rc" -eq 0 ]; then
                ok "飞书机器人配置完成！"
            else
                err "飞书扫码配置失败（退出码: $qr_rc）"
                if [ -f "$qr_png" ]; then
                    warn "二维码已保存到 $qr_png，可用图片查看器打开后扫码"
                fi
                warn "可稍后手动执行: cc-connect feishu setup"
            fi
            ;;
        2)
            # 手动输入方式（兼容旧流程）
            if [ -n "$APP_ID" ] && [ -n "$APP_SECRET" ]; then
                if ! confirm_reuse "飞书凭据 (App ID: $APP_ID)"; then
                    APP_ID=""
                    APP_SECRET=""
                fi
            fi
            if [ -z "$APP_ID" ]; then
                read -rp "  飞书 App ID (例: cli_xxxxxxxxxxxxxxxx): " APP_ID
            fi
            if [ -z "$APP_SECRET" ]; then
                read -rsp "  飞书 App Secret: " APP_SECRET
                echo
            fi
            if [ -n "$APP_ID" ] && [ -n "$APP_SECRET" ]; then
                cc-connect feishu bind --project default --app "$APP_ID:$APP_SECRET"
                if [ $? -eq 0 ]; then
                    ok "飞书凭据绑定完成"
                else
                    err "飞书凭据绑定失败"
                    warn "可稍后手动执行: cc-connect feishu bind --app <app_id:app_secret>"
                fi
            else
                warn "未输入完整凭据，跳过飞书配置"
                warn "稍后执行: cc-connect feishu setup"
            fi
            ;;
        3|*)
            warn "跳过飞书配置，稍后可执行: cc-connect feishu setup"
            ;;
    esac
    divider

    refresh_cc_connect_daemon
}

update_cc_connect() {
    header "更新 cc-connect"
    load_nvm

    if ! has cc-connect; then
        err "cc-connect 未安装，请先选择安装"
        return 1
    fi

    info "更新 cc-connect..."
    npm install -g cc-connect@latest
    ok "cc-connect $(cc-connect --version 2>&1 | grep -oE 'v[0-9]+\.[0-9]+\.[^ ]+') 更新完成"
    set_claude_settings_model_opus_47

    if [ -f "$HOME/.cc-connect/config.toml" ]; then
        if ! set_cc_connect_agent_model_opus_47; then
            warn "未能更新 ~/.cc-connect/config.toml，请手动检查"
        fi
        refresh_cc_connect_daemon
    else
        warn "未找到 ~/.cc-connect/config.toml，仅完成 cc-connect 更新"
        warn "如需生成配置，请先执行安装菜单"
    fi
}

# ============================================================
# 凭据输入
# ============================================================
prompt_credentials() {
    load_existing_claude_config

    echo
    echo -e "${BOLD}  Claude API 配置${NC}"
    divider
    if [ -n "$ANTHROPIC_API_KEY_INPUT" ]; then
        if confirm_reuse "Claude API Key"; then
            info "复用已有 Claude API Key 配置"
        else
            ANTHROPIC_API_KEY_INPUT=""
        fi
    fi
    if [ -z "$ANTHROPIC_API_KEY_INPUT" ]; then
        read -rsp "  Anthropic API Key (sk-ant-...): " ANTHROPIC_API_KEY_INPUT
        echo
    fi
    if [ -n "$ANTHROPIC_BASE_URL_INPUT" ]; then
        if confirm_reuse "Claude Base URL ($ANTHROPIC_BASE_URL_INPUT)"; then
            info "复用已有 Claude Base URL: $ANTHROPIC_BASE_URL_INPUT"
        else
            ANTHROPIC_BASE_URL_INPUT=""
            read -rp "  Base URL (留空使用官方 https://api.anthropic.com): " ANTHROPIC_BASE_URL_INPUT
        fi
    else
        read -rp "  Base URL (留空使用官方 https://api.anthropic.com): " ANTHROPIC_BASE_URL_INPUT
    fi
    divider
    [ -z "$ANTHROPIC_API_KEY_INPUT" ] \
        && warn "未输入 API Key，Claude Code 配置将跳过" \
        || ok "API Key 已记录"

    # 飞书凭据不再提前收集，cc-connect 安装时通过扫码或交互式输入
    info "飞书凭据将在 cc-connect 安装步骤中通过扫码配置"

    export ANTHROPIC_API_KEY_INPUT ANTHROPIC_BASE_URL_INPUT
}

# ============================================================
# 重启服务
# ============================================================
restart_cc_connect() {
    header "重启 cc-connect"
    load_nvm
    if ! has cc-connect; then
        err "cc-connect 未安装，请先选择安装"
        return 1
    fi
    info "重启 cc-connect daemon..."
    cc-connect daemon restart
    sleep 2
    echo
    cc-connect daemon status
    ok "cc-connect 重启完成"
}

restart_gstack_browserd() {
    header "重启 gstack browserd"
    local gstack_dir="$HOME/.claude/skills/gstack"
    if [ ! -d "$gstack_dir" ]; then
        err "gstack 未安装，请先选择安装"
        return 1
    fi
    info "停止 gstack browserd 进程..."
    pkill -f "browserd" 2>/dev/null && ok "browserd 已停止" || info "browserd 当前未运行"
    sleep 1
    info "启动 gstack browserd..."
    cd "$gstack_dir"
    if [ -f "./browserd" ]; then
        ./browserd &>/dev/null &
        sleep 2
        pgrep -f browserd &>/dev/null \
            && ok "gstack browserd 已启动 (PID: $(pgrep -f browserd | head -1))" \
            || warn "browserd 未检测到运行中进程（部分版本按需启动，属正常现象）"
    else
        warn "未找到 browserd 可执行文件，gstack 将在下次调用时自动启动"
    fi
    cd - >/dev/null
}

restart_menu() {
    while true; do
        echo
        echo -e "${BOLD}  重启服务:${NC}"
        echo
        echo -e "  ${CYAN}1)${NC}  cc-connect      (飞书 AI 机器人)"
        divider
        echo -e "  ${RED}0)${NC}  返回主菜单"
        echo
        read -rp "  请输入选项 [0-1]: " RESTART_CHOICE

        case "$RESTART_CHOICE" in
            1) restart_cc_connect ;;
            0) return 0 ;;
            *) err "无效选项: $RESTART_CHOICE" ;;
        esac
    done
}

# ============================================================
# Banner & 菜单
# ============================================================
banner() {
    clear
    echo -e "${BOLD}${BLUE}"
    echo "  ╔══════════════════════════════════════════════╗"
    echo "  ║   Claude Code + Feishu AI Agent 安装脚本    ║"
    echo "  ╚══════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo -e "  系统: ${BOLD}$OS_NAME${NC}  ($(uname -m))"
    echo -e "  用户: $USER   主目录: $HOME"
    echo -e "  RC  : $SHELL_RC"
    echo
}

menu() {
    echo -e "${BOLD}  选择安装项:${NC}"
    echo
    echo -e "  ${GREEN}${BOLD}1)${NC}  全部安装  ${YELLOW}← 推荐${NC}"
    divider
    echo -e "  ${CYAN}2)${NC}  NVM + Node.js 24"
    echo -e "  ${CYAN}3)${NC}  Claude Code  (含 API Key / Base URL 配置)"
    echo -e "  ${CYAN}4)${NC}  飞书 CLI + Lark Skills  (23 个)"
    echo -e "  ${CYAN}5)${NC}  gstack  (AI 工程师工作流, 37 个 skills)"
    echo -e "  ${CYAN}6)${NC}  cc-connect  (飞书机器人桥接服务)"
    divider
    echo -e "  ${YELLOW}7)${NC}  更新 cc-connect"
    echo -e "  ${YELLOW}8)${NC}  重启服务"
    echo -e "  ${YELLOW}9)${NC}  Claude模型更新4.7"
    divider
    echo -e "  ${RED}0)${NC}  退出"
    echo
    read -rp "  请输入选项 [0-9]: " CHOICE
}

# ============================================================
# 主入口
# ============================================================
main() {
    ensure_run_as_non_root_user "$@"
    detect_os
    ensure_valid_cwd
    banner
    menu

    case "$CHOICE" in
        1)
            if [ "$OS_TYPE" = "macos" ]; then
                ensure_brew || return 1
            fi
            install_nvm_node || return 1
            install_claude_code || return 1
            install_feishu_cli || return 1
            install_gstack || return 1
            install_cc_connect || return 1
            echo
            echo -e "${BOLD}${GREEN}"
            echo "  ╔══════════════════════════════════════════════╗"
            echo "  ║           全部安装完成！                     ║"
            echo "  ╚══════════════════════════════════════════════╝"
            echo -e "${NC}"
            echo -e "  ${YELLOW}下一步:${NC}"
            echo "    1. 重新加载 shell:  source $SHELL_RC"
            echo "    2. 飞书用户授权:    lark-cli auth login --recommend"
            echo "    3. 查看机器人状态:  cc-connect daemon status"
            echo "    4. 查看机器人日志:  cc-connect daemon logs -f"
            ;;
        2) install_nvm_node || return 1 ;;
        3) install_claude_code || return 1 ;;
        4) install_feishu_cli || return 1 ;;
        5) install_gstack || return 1 ;;
        6) install_cc_connect || return 1 ;;
        7) update_cc_connect || return 1 ;;
        8) restart_menu ;;
        9)
            set_claude_settings_model_opus_47 || return 1
            if [ -f "$HOME/.cc-connect/config.toml" ]; then
                if set_cc_connect_agent_model_opus_47; then
                    ok "已更新 ~/.cc-connect/config.toml: model = claude-opus-4-7"
                    if has cc-connect; then
                        refresh_cc_connect_daemon
                    else
                        warn "未检测到 cc-connect 命令，请手动重启服务"
                    fi
                else
                    warn "未能更新 ~/.cc-connect/config.toml，请手动检查"
                fi
            else
                warn "未找到 ~/.cc-connect/config.toml，仅更新 Claude settings"
            fi
            ;;
        0) echo "退出。"; exit 0 ;;
        *) err "无效选项: $CHOICE"; exit 1 ;;
    esac

    echo
    ok "完成！"
}

main "$@"
