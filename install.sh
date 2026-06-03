#!/bin/sh
# OpenWRT Telegram Bot — Installer
# https://github.com/Danrrodrigues/OpenWRT-Telegram-Bot

set -e

INSTALL_DIR="/usr/lib/telegram-bot"
CONFIG_FILE="/etc/config/telegram-bot"
SERVICE_FILE="/etc/init.d/telegram-bot"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

_info()  { echo "[INFO]  $1"; }
_warn()  { echo "[WARN]  $1"; }
_error() { echo "[ERROR] $1" >&2; }
_die()   { _error "$1"; exit 1; }

# ---- checks ----

_check_openwrt() {
    if ! grep -qi openwrt /etc/os-release 2>/dev/null; then
        _warn "This script is designed for OpenWRT. Proceeding anyway..."
    fi
}

_check_root() {
    if [ "$(id -u)" != "0" ]; then
        _die "Please run as root: sudo sh install.sh"
    fi
}

_check_deps() {
    _info "Checking dependencies..."

    if ! command -v curl >/dev/null 2>&1; then
        _info "Installing curl via opkg..."
        opkg update && opkg install curl || _die "Failed to install curl. Please run: opkg install curl"
    fi

    if ! command -v jsonfilter >/dev/null 2>&1; then
        _info "Installing jsonfilter..."
        opkg install jsonfilter 2>/dev/null || _warn "jsonfilter not available — JSON parsing may fail"
    fi
}

# ---- config ----

_get_token() {
    echo "" >/dev/tty
    echo "  To get a token: open Telegram, search @BotFather, send /newbot" >/dev/tty
    echo -n "  Bot Token: " >/dev/tty
    read -r token </dev/tty
    [ -z "$token" ] && _die "Token cannot be empty"
    echo "$token"
}

_get_chat_id() {
    echo "" >/dev/tty
    echo "  To get your Chat ID: open Telegram, search @userinfobot, send /start" >/dev/tty
    echo -n "  Chat ID: " >/dev/tty
    read -r chat_id </dev/tty
    [ -z "$chat_id" ] && _die "Chat ID cannot be empty"
    echo "$chat_id"
}

_get_mode() {
    echo "" >/dev/tty
    echo "  Run mode:" >/dev/tty
    echo "    d) daemon — runs as a service, responds in ~2 seconds (recommended)" >/dev/tty
    echo "    c) cron   — runs every minute, responds in up to 60 seconds" >/dev/tty
    echo -n "  Choice [d]: " >/dev/tty
    read -r choice </dev/tty
    case "$choice" in
        c|cron) echo "cron" ;;
        *)      echo "daemon" ;;
    esac
}

_write_uci_config() {
    local token="$1"
    local chat_id="$2"
    local mode="$3"

    _info "Writing config to ${CONFIG_FILE}..."

    uci -q batch <<EOF
delete telegram-bot.bot
set telegram-bot.bot=telegram
set telegram-bot.bot.token='${token}'
set telegram-bot.bot.chat_ids='${chat_id}'
set telegram-bot.bot.mode='${mode}'
set telegram-bot.bot.alerts='1'
set telegram-bot.bot.alert_mode='all'
set telegram-bot.bot.poll_interval='30'
set telegram-bot.bot.log_level='info'
delete telegram-bot.rules
set telegram-bot.rules=rules
commit telegram-bot
EOF

    chmod 600 "$CONFIG_FILE"
    _info "Config written and secured (chmod 600)"
}

# ---- install files ----

_copy_files() {
    _info "Installing scripts to ${INSTALL_DIR}..."
    mkdir -p "${INSTALL_DIR}/core" "${INSTALL_DIR}/modules"

    cp "${SCRIPT_DIR}/src/bot.sh"                "${INSTALL_DIR}/bot.sh"
    cp "${SCRIPT_DIR}/src/core/config.sh"        "${INSTALL_DIR}/core/config.sh"
    cp "${SCRIPT_DIR}/src/core/logger.sh"        "${INSTALL_DIR}/core/logger.sh"
    cp "${SCRIPT_DIR}/src/core/telegram.sh"      "${INSTALL_DIR}/core/telegram.sh"
    cp "${SCRIPT_DIR}/src/modules/monitor.sh"    "${INSTALL_DIR}/modules/monitor.sh"
    cp "${SCRIPT_DIR}/src/modules/devices.sh"    "${INSTALL_DIR}/modules/devices.sh"
    cp "${SCRIPT_DIR}/src/modules/bandwidth.sh"  "${INSTALL_DIR}/modules/bandwidth.sh"

    chmod +x "${INSTALL_DIR}/bot.sh"
    _info "Scripts installed"
}

# ---- daemon service ----

_install_daemon() {
    _info "Creating init.d service..."
    cat > "$SERVICE_FILE" <<'INITEOF'
#!/bin/sh /etc/rc.common
# OpenWRT Telegram Bot service

START=99
STOP=10
USE_PROCD=1

start_service() {
    procd_open_instance
    procd_set_param command /usr/lib/telegram-bot/bot.sh --daemon
    procd_set_param respawn 3600 5 0
    procd_set_param stdout 1
    procd_set_param stderr 1
    procd_close_instance
}
INITEOF

    chmod +x "$SERVICE_FILE"
    /etc/init.d/telegram-bot enable
    /etc/init.d/telegram-bot start
    _info "Service enabled and started"
}

# ---- cron ----

_install_cron() {
    _info "Adding cron job (every minute)..."
    local cron_entry="* * * * * /usr/lib/telegram-bot/bot.sh --cron"
    if ! crontab -l 2>/dev/null | grep -qF "telegram-bot"; then
        (crontab -l 2>/dev/null; echo "$cron_entry") | crontab -
        /etc/init.d/cron restart 2>/dev/null || true
        _info "Cron job added"
    else
        _warn "Cron job already exists — skipping"
    fi
}

# ---- nftables blocklist setup ----

_setup_nftables() {
    if command -v nft >/dev/null 2>&1; then
        _info "Setting up nftables MAC blocklist..."
        # Add persistent nft rules via fw4 includes
        mkdir -p /etc/nftables.d
        cat > /etc/nftables.d/telegram-bot.nft <<'NFTEOF'
# OpenWRT Telegram Bot — MAC blocklist
# Managed automatically by bot.sh — do not edit manually

table inet fw4 {
    set telegram_blocked {
        type ether_addr
        elements = { }
    }

    chain forward {
        ether saddr @telegram_blocked drop
        ether daddr @telegram_blocked drop
    }
}
NFTEOF
        fw4 reload 2>/dev/null || nft -f /etc/nftables.d/telegram-bot.nft 2>/dev/null || true
        _info "nftables blocklist configured"
    fi
}

# ---- update ----

_update() {
    _info "=== OpenWRT Telegram Bot Updater ==="
    echo ""

    _check_root
    _check_openwrt

    if [ ! -d "$INSTALL_DIR" ]; then
        _die "Bot is not installed. Run: sh install.sh"
    fi

    _info "Stopping service..."
    [ -f "$SERVICE_FILE" ] && "$SERVICE_FILE" stop 2>/dev/null || true

    _info "Updating scripts..."
    _copy_files

    _info "Restarting service..."
    if [ -f "$SERVICE_FILE" ]; then
        "$SERVICE_FILE" start
    else
        /etc/init.d/cron restart 2>/dev/null || true
    fi

    echo ""
    _info "=== Update complete! ==="
    echo ""
    echo "Config was preserved. Send /status to your bot to confirm it's running."
    echo ""
}

# ---- reconfigure ----

_reconfigure() {
    _info "=== Reconfigure OpenWRT Telegram Bot ==="
    echo ""

    _check_root

    if [ ! -d "$INSTALL_DIR" ]; then
        _die "Bot is not installed. Run: sh install.sh"
    fi

    _info "Current config:"
    uci show telegram-bot 2>/dev/null | grep -v token || true
    echo ""

    token=$(_get_token)
    chat_id=$(_get_chat_id)
    mode=$(_get_mode)

    _write_uci_config "$token" "$chat_id" "$mode"

    _info "Restarting service..."
    [ -f "$SERVICE_FILE" ] && "$SERVICE_FILE" restart 2>/dev/null || \
        /etc/init.d/cron restart 2>/dev/null || true

    echo ""
    _info "=== Reconfiguration complete! ==="
    echo ""
    echo "Send /start to your bot to confirm."
    echo ""
}

# ---- main ----

_usage() {
    cat <<EOF
Usage: sh install.sh [command]

  (no argument)   Fresh install — copies files and configures the bot
  update          Update scripts only, preserving existing config
  reconfigure     Change token, chat ID, or run mode
  help            Show this help

Examples:
  sh install.sh
  sh install.sh update
  sh install.sh reconfigure
EOF
}

main() {
    local cmd="${1:-install}"

    case "$cmd" in
        update)
            _update
            ;;
        reconfigure|reconfig)
            _reconfigure
            ;;
        help|--help|-h)
            _usage
            ;;
        install|"")
            _info "=== OpenWRT Telegram Bot Installer ==="
            echo ""

            _check_root
            _check_openwrt
            _check_deps

            echo ""
            _info "--- Configuration ---"
            token=$(_get_token)
            chat_id=$(_get_chat_id)
            mode=$(_get_mode)

            echo ""
            _info "--- Installing ---"
            _copy_files
            _write_uci_config "$token" "$chat_id" "$mode"
            _setup_nftables

            if [ "$mode" = "daemon" ]; then
                _install_daemon
            else
                _install_cron
            fi

            echo ""
            _info "=== Installation complete! ==="
            echo ""
            echo "  Token:   [configured]"
            echo "  Chat ID: ${chat_id}"
            echo "  Mode:    ${mode}"
            echo ""
            echo "  Send /start to your bot on Telegram to test."
            echo "  Logs: logread -e telegram-bot"
            echo ""
            ;;
        *)
            _error "Unknown command: $cmd"
            _usage
            exit 1
            ;;
    esac
}

main "$@"
