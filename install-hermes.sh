#!/bin/bash
# Hermes Agent 一键安装脚本（含 Feishu/Lark 配置，可选 WeCom）
# 支持 Linux / macOS / WSL2

set -euo pipefail

# 兼容 curl | bash 场景，确保 read 可交互
if [ ! -t 0 ]; then
    exec < /dev/tty
fi

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

has() { command -v "$1" >/dev/null 2>&1; }

OS_TYPE=""
SHELL_RC=""
HERMES_CMD=""
HERMES_ENV_FILE="$HOME/.hermes/.env"

trim() {
    local value="$1"
    # shellcheck disable=SC2001
    value="$(echo "$value" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    echo "$value"
}

prompt_yes_no() {
    local prompt_text="$1"
    local default_choice="${2:-N}"  # Y or N
    local answer=""

    if [ "$default_choice" = "Y" ]; then
        read -rp "$prompt_text [Y/n] " answer
        answer="$(trim "$answer")"
        [ -z "$answer" ] && return 0
    else
        read -rp "$prompt_text [y/N] " answer
        answer="$(trim "$answer")"
        [ -z "$answer" ] && return 1
    fi

    case "$answer" in
        y|Y|yes|YES|Yes) return 0 ;;
        *) return 1 ;;
    esac
}

detect_os() {
    local os
    os="$(uname -s)"

    case "$os" in
        Linux)
            OS_TYPE="linux"
            SHELL_RC="$HOME/.bashrc"
            ;;
        Darwin)
            OS_TYPE="macos"
            SHELL_RC="$HOME/.zshrc"
            [ "${SHELL:-}" = "/bin/bash" ] && SHELL_RC="$HOME/.bash_profile"
            ;;
        *)
            err "不支持的操作系统: $os"
            err "请在 Linux / macOS / WSL2 中运行"
            exit 1
            ;;
    esac

    if grep -qi microsoft /proc/version 2>/dev/null; then
        info "检测到 WSL 环境"
    fi

    ok "系统检测完成: $OS_TYPE"
}

ensure_local_bin_on_path() {
    touch "$SHELL_RC"
    if ! grep -Fq 'export PATH="$HOME/.local/bin:$PATH"' "$SHELL_RC"; then
        echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$SHELL_RC"
        info "已写入 PATH 到 $SHELL_RC"
    fi
    export PATH="$HOME/.local/bin:$PATH"
}

ensure_env_file() {
    mkdir -p "$(dirname "$HERMES_ENV_FILE")"
    touch "$HERMES_ENV_FILE"
}

remove_env_key() {
    local key="$1"
    ensure_env_file
    local tmp_file
    tmp_file="$(mktemp)"
    grep -vE "^${key}=" "$HERMES_ENV_FILE" > "$tmp_file" || true
    mv "$tmp_file" "$HERMES_ENV_FILE"
}

upsert_env_key() {
    local key="$1"
    local value="$2"
    ensure_env_file

    local tmp_file
    tmp_file="$(mktemp)"
    grep -vE "^${key}=" "$HERMES_ENV_FILE" > "$tmp_file" || true
    printf '%s=%s\n' "$key" "$value" >> "$tmp_file"
    mv "$tmp_file" "$HERMES_ENV_FILE"
}

resolve_hermes_cmd() {
    if has hermes; then
        HERMES_CMD="$(command -v hermes)"
        return 0
    fi

    if [ -x "$HOME/.local/bin/hermes" ]; then
        HERMES_CMD="$HOME/.local/bin/hermes"
        return 0
    fi

    HERMES_CMD=""
    return 1
}

install_hermes() {
    header "安装 Hermes Agent"

    local need_install="true"
    if resolve_hermes_cmd; then
        warn "检测到 Hermes 已安装: $HERMES_CMD"
        "$HERMES_CMD" version || true
        if prompt_yes_no "是否重新安装 Hermes？" "N"; then
            need_install="true"
        else
            need_install="false"
        fi
    fi

    if [ "$need_install" = "true" ]; then
        info "执行 Hermes 官方安装脚本（--skip-setup）..."
        curl -fsSL https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.sh | bash -s -- --skip-setup
        ok "Hermes 安装完成"
    fi

    ensure_local_bin_on_path

    if ! resolve_hermes_cmd; then
        err "Hermes 安装后仍未找到命令，请执行: source $SHELL_RC 后重试"
        exit 1
    fi

    ok "Hermes 命令可用: $HERMES_CMD"
    "$HERMES_CMD" version || true
}

configure_openrouter() {
    header "配置 LLM Key（可选）"

    if ! prompt_yes_no "是否写入 OPENROUTER_API_KEY 到 ~/.hermes/.env？" "N"; then
        info "跳过 OPENROUTER_API_KEY 配置"
        return 0
    fi

    local openrouter_key=""
    read -rsp "  OPENROUTER_API_KEY: " openrouter_key
    echo
    openrouter_key="$(trim "$openrouter_key")"

    if [ -z "$openrouter_key" ]; then
        warn "未输入 Key，跳过"
        return 0
    fi

    upsert_env_key "OPENROUTER_API_KEY" "$openrouter_key"
    ok "已写入 OPENROUTER_API_KEY"
}

configure_feishu() {
    header "配置 Feishu / Lark"

    if ! prompt_yes_no "是否配置飞书（Feishu / Lark）？" "Y"; then
        info "跳过 Feishu / Lark 配置"
        return 0
    fi

    if prompt_yes_no "是否使用官方向导（hermes gateway setup）进行扫码创建/配置？" "Y"; then
        "$HERMES_CMD" gateway setup
        ok "官方向导执行完成"
        return 0
    fi

    local app_id=""
    local app_secret=""
    local domain=""
    local connection_mode=""
    local dm_choice=""
    local group_choice=""
    local allowed_users=""
    local home_channel=""
    local webhook_host=""
    local webhook_port=""
    local webhook_path=""
    local encrypt_key=""
    local verification_token=""

    divider
    read -rp "  FEISHU_APP_ID: " app_id
    read -rsp "  FEISHU_APP_SECRET: " app_secret
    echo

    app_id="$(trim "$app_id")"
    app_secret="$(trim "$app_secret")"

    if [ -z "$app_id" ] || [ -z "$app_secret" ]; then
        err "FEISHU_APP_ID / FEISHU_APP_SECRET 不能为空"
        return 1
    fi

    read -rp "  域名（feishu/lark，默认 feishu）: " domain
    domain="$(trim "$domain")"
    case "$domain" in
        ""|feishu|lark) ;;
        *)
            warn "无效域名，使用默认 feishu"
            domain="feishu"
            ;;
    esac
    [ -z "$domain" ] && domain="feishu"

    read -rp "  连接模式（websocket/webhook，默认 websocket）: " connection_mode
    connection_mode="$(trim "$connection_mode")"
    case "$connection_mode" in
        ""|websocket|webhook) ;;
        *)
            warn "无效模式，使用默认 websocket"
            connection_mode="websocket"
            ;;
    esac
    [ -z "$connection_mode" ] && connection_mode="websocket"

    echo
    echo "  DM 授权策略:"
    echo "    1) DM 配对审批（推荐）"
    echo "    2) 全部用户可直接私聊"
    echo "    3) 仅白名单用户"
    read -rp "  请选择 [1-3]（默认 1）: " dm_choice
    dm_choice="$(trim "$dm_choice")"
    [ -z "$dm_choice" ] && dm_choice="1"

    case "$dm_choice" in
        1)
            upsert_env_key "FEISHU_ALLOW_ALL_USERS" "false"
            upsert_env_key "FEISHU_ALLOWED_USERS" ""
            ;;
        2)
            upsert_env_key "FEISHU_ALLOW_ALL_USERS" "true"
            upsert_env_key "FEISHU_ALLOWED_USERS" ""
            ;;
        3)
            read -rp "  FEISHU_ALLOWED_USERS（逗号分隔）: " allowed_users
            allowed_users="$(trim "$allowed_users")"
            upsert_env_key "FEISHU_ALLOW_ALL_USERS" "false"
            upsert_env_key "FEISHU_ALLOWED_USERS" "$allowed_users"
            ;;
        *)
            warn "无效选择，使用 DM 配对审批"
            upsert_env_key "FEISHU_ALLOW_ALL_USERS" "false"
            upsert_env_key "FEISHU_ALLOWED_USERS" ""
            ;;
    esac

    echo
    echo "  群聊策略:"
    echo "    1) 仅 @ 机器人时响应（推荐）"
    echo "    2) 禁用群聊"
    read -rp "  请选择 [1-2]（默认 1）: " group_choice
    group_choice="$(trim "$group_choice")"
    [ -z "$group_choice" ] && group_choice="1"

    case "$group_choice" in
        1) upsert_env_key "FEISHU_GROUP_POLICY" "open" ;;
        2) upsert_env_key "FEISHU_GROUP_POLICY" "disabled" ;;
        *)
            warn "无效选择，默认启用 @mention 响应"
            upsert_env_key "FEISHU_GROUP_POLICY" "open"
            ;;
    esac

    read -rp "  FEISHU_HOME_CHANNEL（可留空）: " home_channel
    home_channel="$(trim "$home_channel")"

    upsert_env_key "FEISHU_APP_ID" "$app_id"
    upsert_env_key "FEISHU_APP_SECRET" "$app_secret"
    upsert_env_key "FEISHU_DOMAIN" "$domain"
    upsert_env_key "FEISHU_CONNECTION_MODE" "$connection_mode"

    if [ -n "$home_channel" ]; then
        upsert_env_key "FEISHU_HOME_CHANNEL" "$home_channel"
    else
        remove_env_key "FEISHU_HOME_CHANNEL"
    fi

    if [ "$connection_mode" = "webhook" ]; then
        echo
        info "Webhook 模式可选参数（直接回车使用 Hermes 默认值）"
        read -rp "  FEISHU_WEBHOOK_HOST（默认 127.0.0.1）: " webhook_host
        read -rp "  FEISHU_WEBHOOK_PORT（默认 8765）: " webhook_port
        read -rp "  FEISHU_WEBHOOK_PATH（默认 /feishu/webhook）: " webhook_path
        read -rp "  FEISHU_ENCRYPT_KEY（可留空）: " encrypt_key
        read -rp "  FEISHU_VERIFICATION_TOKEN（可留空）: " verification_token

        webhook_host="$(trim "$webhook_host")"
        webhook_port="$(trim "$webhook_port")"
        webhook_path="$(trim "$webhook_path")"
        encrypt_key="$(trim "$encrypt_key")"
        verification_token="$(trim "$verification_token")"

        [ -n "$webhook_host" ] && upsert_env_key "FEISHU_WEBHOOK_HOST" "$webhook_host"
        [ -n "$webhook_port" ] && upsert_env_key "FEISHU_WEBHOOK_PORT" "$webhook_port"
        [ -n "$webhook_path" ] && upsert_env_key "FEISHU_WEBHOOK_PATH" "$webhook_path"

        if [ -n "$encrypt_key" ]; then
            upsert_env_key "FEISHU_ENCRYPT_KEY" "$encrypt_key"
        fi
        if [ -n "$verification_token" ]; then
            upsert_env_key "FEISHU_VERIFICATION_TOKEN" "$verification_token"
        fi
    fi

    ok "Feishu / Lark 配置完成"
}

configure_wecom() {
    header "配置 WeCom（企业微信，可选）"

    if ! prompt_yes_no "是否配置企业微信 WeCom？" "N"; then
        info "跳过 WeCom 配置"
        return 0
    fi

    local bot_id=""
    local secret=""
    local auth_choice=""
    local allowed_users=""
    local home_channel=""

    divider
    read -rp "  WECOM_BOT_ID: " bot_id
    read -rsp "  WECOM_SECRET: " secret
    echo

    bot_id="$(trim "$bot_id")"
    secret="$(trim "$secret")"

    if [ -z "$bot_id" ] || [ -z "$secret" ]; then
        err "WECOM_BOT_ID / WECOM_SECRET 不能为空"
        return 1
    fi

    echo
    echo "  授权策略:"
    echo "    1) DM 配对审批（推荐）"
    echo "    2) 全开放"
    echo "    3) 白名单"
    read -rp "  请选择 [1-3]（默认 1）: " auth_choice
    auth_choice="$(trim "$auth_choice")"
    [ -z "$auth_choice" ] && auth_choice="1"

    case "$auth_choice" in
        1)
            upsert_env_key "WECOM_ALLOW_ALL_USERS" "false"
            upsert_env_key "WECOM_ALLOWED_USERS" ""
            ;;
        2)
            upsert_env_key "WECOM_ALLOW_ALL_USERS" "true"
            upsert_env_key "WECOM_ALLOWED_USERS" ""
            ;;
        3)
            read -rp "  WECOM_ALLOWED_USERS（逗号分隔）: " allowed_users
            allowed_users="$(trim "$allowed_users")"
            upsert_env_key "WECOM_ALLOW_ALL_USERS" "false"
            upsert_env_key "WECOM_ALLOWED_USERS" "$allowed_users"
            ;;
        *)
            warn "无效选择，默认使用 DM 配对审批"
            upsert_env_key "WECOM_ALLOW_ALL_USERS" "false"
            upsert_env_key "WECOM_ALLOWED_USERS" ""
            ;;
    esac

    read -rp "  WECOM_HOME_CHANNEL（可留空）: " home_channel
    home_channel="$(trim "$home_channel")"

    upsert_env_key "WECOM_BOT_ID" "$bot_id"
    upsert_env_key "WECOM_SECRET" "$secret"

    if [ -n "$home_channel" ]; then
        upsert_env_key "WECOM_HOME_CHANNEL" "$home_channel"
    else
        remove_env_key "WECOM_HOME_CHANNEL"
    fi

    ok "WeCom 配置完成"
}

print_next_steps() {
    header "完成"
    echo "1) 重新加载 shell 环境变量:"
    echo "   source $SHELL_RC"
    echo
    echo "2) 检查 Hermes 版本:"
    echo "   $HERMES_CMD version"
    echo
    echo "3) 启动网关（前台）:"
    echo "   $HERMES_CMD gateway run"
    echo
    echo "4) 或安装后台服务:"
    echo "   $HERMES_CMD gateway install"
    echo "   $HERMES_CMD gateway start"
    echo
    echo "5) 查看状态:"
    echo "   $HERMES_CMD gateway status"
    echo "   $HERMES_CMD doctor"
}

main() {
    detect_os

    echo -e "${BOLD}${BLUE}"
    echo "  ╔══════════════════════════════════════════════╗"
    echo "  ║      Hermes Agent + Feishu 安装脚本         ║"
    echo "  ╚══════════════════════════════════════════════╝"
    echo -e "${NC}"

    install_hermes
    configure_openrouter
    configure_feishu
    configure_wecom
    print_next_steps
}

main "$@"
