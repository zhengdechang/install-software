#!/bin/bash
# Claude Code + Feishu AI Agent 一键安装脚本

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

load_nvm() {
    export NVM_DIR="$HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
    [ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"
}

load_bun() {
    export PATH="$HOME/.bun/bin:$PATH"
}

# ============================================================
# 安装模块
# ============================================================

install_nvm_node() {
    header "NVM + Node.js 24"

    load_nvm
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

install_claude_code() {
    header "Claude Code"
    load_nvm

    if has claude; then
        warn "Claude Code 已安装: $(claude --version 2>&1 | head -1 || echo '未知版本')"
        read -rp "  重新安装? [y/N] " yn
        [[ "$yn" != [yY] ]] && return 0
    fi

    info "安装 @anthropic-ai/claude-code..."
    npm install -g @anthropic-ai/claude-code
    ok "Claude Code 安装完成"
}

# bun 是 gstack 的依赖
install_bun() {
    load_bun
    if has bun; then
        warn "bun 已安装: v$(bun --version)"
        return 0
    fi

    info "安装 unzip (bun 前置依赖)..."
    sudo apt-get install -y unzip -qq

    # 修复损坏的 cdrom apt 源（常见于 Ubuntu 镜像）
    if grep -qE "^deb.*cdrom" /etc/apt/sources.list 2>/dev/null; then
        sudo sed -i \
            -e 's|^deb \[check-date=no\] file:///cdrom|# deb [check-date=no] file:///cdrom|g' \
            -e 's|^deb cdrom:|# deb cdrom:|g' \
            /etc/apt/sources.list
        info "已注释掉损坏的 cdrom apt 源"
    fi

    info "安装 bun..."
    curl -fsSL https://bun.sh/install | bash
    load_bun
    ok "bun v$(bun --version) 安装完成"
}

install_feishu_cli() {
    header "飞书 CLI + Lark Skills"
    load_nvm

    info "安装 @larksuite/cli..."
    npm install -g @larksuite/cli
    ok "飞书 CLI 安装完成"

    info "安装 Lark Skills (23 个)..."
    npx skills add https://github.com/larksuite/cli -y -g
    ok "Lark Skills 安装完成"

    if [ -n "$APP_ID" ] && [ -n "$APP_SECRET" ]; then
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

install_gstack() {
    header "gstack (AI 工程工作流)"
    load_nvm
    install_bun

    if [ -d "$HOME/.claude/skills/gstack" ]; then
        warn "gstack 已安装"
        read -rp "  重新安装/更新? [y/N] " yn
        if [[ "$yn" == [yY] ]]; then
            rm -rf "$HOME/.claude/skills/gstack"
        else
            return 0
        fi
    fi

    info "安装 Playwright Chromium 系统依赖..."
    sudo apt-get update -qq
    bun x playwright install-deps chromium

    info "安装 Playwright Chromium 浏览器..."
    bun x playwright install chromium

    info "克隆 gstack..."
    git clone --single-branch --depth 1 \
        https://github.com/garrytan/gstack.git \
        "$HOME/.claude/skills/gstack"

    info "运行 gstack setup..."
    cd "$HOME/.claude/skills/gstack"
    ./setup
    cd - >/dev/null

    ok "gstack 安装完成 (37 个 skills)"
}

install_cc_connect() {
    header "cc-connect (飞书 AI 机器人)"
    load_nvm

    # 若未在"全部安装"流程中输入，则单独询问
    if [ -z "$APP_ID" ]; then
        read -rp "  飞书 App ID (例: cli_xxxxxxxxxxxxxxxx): " APP_ID
    fi
    if [ -z "$APP_SECRET" ]; then
        read -rsp "  飞书 App Secret: " APP_SECRET
        echo
    fi

    if [ -z "$APP_ID" ] || [ -z "$APP_SECRET" ]; then
        err "App ID 和 App Secret 不能为空，退出"
        return 1
    fi

    info "安装 cc-connect (beta)..."
    npm install -g cc-connect@beta
    ok "cc-connect $(cc-connect --version 2>&1 | grep -oE 'v[0-9]+\.[0-9]+\.[^ ]+') 安装完成"

    # 生成随机 token
    BRIDGE_TOKEN=$(openssl rand -hex 16)
    MGMT_TOKEN=$(openssl rand -hex 32)

    info "写入配置 ~/.cc-connect/config.toml..."
    mkdir -p "$HOME/.cc-connect"
    cat > "$HOME/.cc-connect/config.toml" <<TOML
data_dir = ""
attachment_send = ""
language = "en"

[[projects]]
  name = "default"

  [projects.agent]
    type = "claudecode"

    [projects.agent.options]
      mode = "default"
      model = "sonnet"
      work_dir = ""

  [[projects.platforms]]
    type = "feishu"

    [projects.platforms.options]
      allow_from = "*"
      app_id = "$APP_ID"
      app_secret = "$APP_SECRET"
      enable_feishu_card = true
      progress_style = "card"

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
    ok "配置文件写入完成"
    info "Bridge token:     $BRIDGE_TOKEN"
    info "Management token: $MGMT_TOKEN"

    # 安装或重启 daemon
    info "配置 systemd 服务..."
    if cc-connect daemon status 2>&1 | grep -qE "Running|Stopped|Installed"; then
        cc-connect daemon uninstall 2>/dev/null || true
    fi
    cc-connect daemon install --work-dir "$HOME/.cc-connect"

    # 开机自启（linger）
    info "配置开机自启 (loginctl linger)..."
    sudo loginctl enable-linger "$USER"
    ok "开机自启已配置"

    sleep 2
    echo
    cc-connect daemon status
}

# ============================================================
# 凭据输入
# ============================================================
prompt_credentials() {
    echo
    echo -e "${BOLD}  飞书应用凭据 (用于 lark-cli 和 cc-connect)${NC}"
    divider
    read -rp "  App ID    : " APP_ID
    read -rsp "  App Secret: " APP_SECRET
    echo
    divider
    if [ -z "$APP_ID" ] || [ -z "$APP_SECRET" ]; then
        warn "未输入凭据，相关配置步骤将跳过"
    else
        ok "凭据已记录"
    fi
    export APP_ID APP_SECRET
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
    echo -e "  系统: $(uname -srm)"
    echo -e "  用户: $USER  主目录: $HOME"
    echo
}

menu() {
    echo -e "${BOLD}  选择安装项:${NC}"
    echo
    echo -e "  ${GREEN}${BOLD}1)${NC}  全部安装  ${YELLOW}← 推荐${NC}"
    divider
    echo -e "  ${CYAN}2)${NC}  NVM + Node.js 24"
    echo -e "  ${CYAN}3)${NC}  Claude Code"
    echo -e "  ${CYAN}4)${NC}  飞书 CLI + Lark Skills (23 个)"
    echo -e "  ${CYAN}5)${NC}  gstack (AI 工程师工作流, 37 个 skills)"
    echo -e "  ${CYAN}6)${NC}  cc-connect beta (飞书机器人桥接服务)"
    divider
    echo -e "  ${RED}0)${NC}  退出"
    echo
    read -rp "  请输入选项 [0-6]: " CHOICE
}

# ============================================================
# 主入口
# ============================================================
main() {
    banner
    menu

    case "$CHOICE" in
        1)
            prompt_credentials
            install_nvm_node
            install_claude_code
            install_feishu_cli
            install_gstack
            install_cc_connect
            echo
            echo -e "${BOLD}${GREEN}"
            echo "  ╔══════════════════════════════════════════════╗"
            echo "  ║           全部安装完成！                     ║"
            echo "  ╚══════════════════════════════════════════════╝"
            echo -e "${NC}"
            echo -e "  ${YELLOW}下一步:${NC}"
            echo "    1. 重新加载 shell:  source ~/.bashrc"
            echo "    2. 飞书用户授权:    lark-cli auth login --recommend"
            echo "    3. 查看机器人状态:  cc-connect daemon status"
            echo "    4. 查看机器人日志:  cc-connect daemon logs -f"
            ;;
        2) install_nvm_node ;;
        3) install_claude_code ;;
        4) prompt_credentials; install_feishu_cli ;;
        5) install_gstack ;;
        6) install_cc_connect ;;
        0) echo "退出。"; exit 0 ;;
        *) err "无效选项: $CHOICE"; exit 1 ;;
    esac

    echo
    ok "完成！"
}

main "$@"
gary@gary:~$ cat install.sh 
#!/bin/bash
# Claude Code + Feishu AI Agent 一键安装脚本
# 支持 macOS / Ubuntu / Debian

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

install_nvm_node() {
    header "NVM + Node.js 24"
    load_nvm

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
# Claude Code
# ============================================================
install_claude_code() {
    header "Claude Code"
    load_nvm

    if has claude; then
        warn "Claude Code 已安装: $(claude --version 2>&1 | head -1 || echo '未知版本')"
        read -rp "  重新安装? [y/N] " yn
        [[ "$yn" == [yY] ]] && npm install -g @anthropic-ai/claude-code
    else
        info "安装 @anthropic-ai/claude-code..."
        npm install -g @anthropic-ai/claude-code
        ok "Claude Code 安装完成"
    fi

    # 配置 API Key 和 Base URL
    if [ -z "$ANTHROPIC_API_KEY_INPUT" ]; then
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

    info "安装 @larksuite/cli..."
    npm install -g @larksuite/cli
    ok "飞书 CLI 安装完成"

    info "安装 Lark Skills (23 个)..."
    npx skills add https://github.com/larksuite/cli -y -g
    ok "Lark Skills 安装完成"

    if [ -n "$APP_ID" ] && [ -n "$APP_SECRET" ]; then
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
    if has bun; then
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
    ok "bun v$(bun --version) 安装完成"
}

# ============================================================
# gstack
# ============================================================
install_gstack() {
    header "gstack (AI 工程工作流)"
    load_nvm
    install_bun

    if [ -d "$HOME/.claude/skills/gstack" ]; then
        warn "gstack 已安装"
        read -rp "  重新安装/更新? [y/N] " yn
        if [[ "$yn" == [yY] ]]; then
            rm -rf "$HOME/.claude/skills/gstack"
        else
            return 0
        fi
    fi

    info "安装 Playwright Chromium..."
    if [ "$OS_TYPE" = "linux" ]; then
        # Linux 需要先安装系统依赖
        pkg_update
        bun x playwright install-deps chromium
    fi
    # macOS 不需要 install-deps
    bun x playwright install chromium

    info "克隆 gstack..."
    git clone --single-branch --depth 1 \
        https://github.com/garrytan/gstack.git \
        "$HOME/.claude/skills/gstack"

    info "运行 gstack setup..."
    cd "$HOME/.claude/skills/gstack"
    ./setup
    cd - >/dev/null

    ok "gstack 安装完成 (37 个 skills)"
}

# ============================================================
# cc-connect
# ============================================================
install_cc_connect() {
    header "cc-connect (飞书 AI 机器人)"
    load_nvm

    # 若未在"全部安装"流程中输入，则单独询问
    if [ -z "$APP_ID" ]; then
        read -rp "  飞书 App ID (例: cli_xxxxxxxxxxxxxxxx): " APP_ID
    fi
    if [ -z "$APP_SECRET" ]; then
        read -rsp "  飞书 App Secret: " APP_SECRET
        echo
    fi

    if [ -z "$APP_ID" ] || [ -z "$APP_SECRET" ]; then
        err "App ID 和 App Secret 不能为空，退出"
        return 1
    fi

    info "安装 cc-connect (beta)..."
    npm install -g cc-connect@beta
    ok "cc-connect $(cc-connect --version 2>&1 | grep -oE 'v[0-9]+\.[0-9]+\.[^ ]+') 安装完成"

    # 生成随机 token
    BRIDGE_TOKEN=$(openssl rand -hex 16)
    MGMT_TOKEN=$(openssl rand -hex 32)

    info "写入配置 ~/.cc-connect/config.toml..."
    mkdir -p "$HOME/.cc-connect"
    cat > "$HOME/.cc-connect/config.toml" <<TOML
data_dir = ""
attachment_send = ""
language = "en"

[[projects]]
  name = "default"

  [projects.agent]
    type = "claudecode"

    [projects.agent.options]
      mode = "default"
      model = "sonnet"
      work_dir = ""

  [[projects.platforms]]
    type = "feishu"

    [projects.platforms.options]
      allow_from = "*"
      app_id = "$APP_ID"
      app_secret = "$APP_SECRET"
      enable_feishu_card = true
      progress_style = "card"

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
    ok "配置文件写入完成"
    info "Bridge token:     $BRIDGE_TOKEN"
    info "Management token: $MGMT_TOKEN"

    # 安装或重启 daemon
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

# ============================================================
# 凭据输入
# ============================================================
prompt_credentials() {
    echo
    echo -e "${BOLD}  Claude API 配置${NC}"
    divider
    read -rsp "  Anthropic API Key (sk-ant-...): " ANTHROPIC_API_KEY_INPUT
    echo
    read -rp "  Base URL (留空使用官方 https://api.anthropic.com): " ANTHROPIC_BASE_URL_INPUT
    divider
    [ -z "$ANTHROPIC_API_KEY_INPUT" ] \
        && warn "未输入 API Key，Claude Code 配置将跳过" \
        || ok "API Key 已记录"

    echo
    echo -e "${BOLD}  飞书应用凭据 (用于 lark-cli 和 cc-connect)${NC}"
    divider
    read -rp "  App ID    : " APP_ID
    read -rsp "  App Secret: " APP_SECRET
    echo
    divider
    { [ -z "$APP_ID" ] || [ -z "$APP_SECRET" ]; } \
        && warn "未输入飞书凭据，相关配置步骤将跳过" \
        || ok "飞书凭据已记录"

    export APP_ID APP_SECRET ANTHROPIC_API_KEY_INPUT ANTHROPIC_BASE_URL_INPUT
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
    echo -e "  ${CYAN}6)${NC}  cc-connect beta  (飞书机器人桥接服务)"
    divider
    echo -e "  ${RED}0)${NC}  退出"
    echo
    read -rp "  请输入选项 [0-6]: " CHOICE
}

# ============================================================
# 主入口
# ============================================================
main() {
    detect_os
    banner
    menu

    case "$CHOICE" in
        1)
            [ "$OS_TYPE" = "macos" ] && ensure_brew
            prompt_credentials
            install_nvm_node
            install_claude_code
            install_feishu_cli
            install_gstack
            install_cc_connect
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
        2) install_nvm_node ;;
        3) install_claude_code ;;
        4) prompt_credentials; install_feishu_cli ;;
        5) install_gstack ;;
        6) install_cc_connect ;;
        0) echo "退出。"; exit 0 ;;
        *) err "无效选项: $CHOICE"; exit 1 ;;
    esac

    echo
    ok "完成！"
}

main "$@"
