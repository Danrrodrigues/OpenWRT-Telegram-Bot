#!/bin/sh
# OpenWRT Telegram Bot — Installer
# https://github.com/Danrrodrigues/OpenWRT-Telegram-Bot

set -e

# Paths are overridable via the environment so the test suite can sandbox them.
INSTALL_DIR="${INSTALL_DIR:-/usr/lib/telegram-bot}"
CONFIG_FILE="${CONFIG_FILE:-/etc/config/telegram-bot}"
SERVICE_FILE="${SERVICE_FILE:-/etc/init.d/telegram-bot}"
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
        if ! { opkg update && opkg install curl; }; then
            _die "Failed to install curl. Please run: opkg install curl"
        fi
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
    printf '%s' "  Bot Token: " >/dev/tty
    read -r token </dev/tty
    [ -z "$token" ] && _die "Token cannot be empty"
    echo "$token"
}

_get_chat_id() {
    echo "" >/dev/tty
    echo "  To get your Chat ID: open Telegram, search @userinfobot, send /start" >/dev/tty
    printf '%s' "  Chat ID: " >/dev/tty
    read -r chat_id </dev/tty
    [ -z "$chat_id" ] && _die "Chat ID cannot be empty"
    echo "$chat_id"
}

_get_mode() {
    echo "" >/dev/tty
    echo "  Run mode:" >/dev/tty
    echo "    d) daemon — runs as a service, responds in ~2 seconds (recommended)" >/dev/tty
    echo "    c) cron   — runs every minute, responds in up to 60 seconds" >/dev/tty
    printf '%s' "  Choice [d]: " >/dev/tty
    read -r choice </dev/tty
    case "$choice" in
        c|cron) echo "cron" ;;
        *)      echo "daemon" ;;
    esac
}

_get_lang() {
    echo "" >/dev/tty
    echo "  Language / Idioma:" >/dev/tty
    echo "    e) English (default)" >/dev/tty
    echo "    p) Português" >/dev/tty
    printf '%s' "  Choice [e]: " >/dev/tty
    read -r choice </dev/tty
    case "$choice" in
        p|pt|pt-br|portugues|português) echo "pt" ;;
        *)                              echo "en" ;;
    esac
}

_write_uci_config() {
    local token="$1"
    local chat_id="$2"
    local mode="$3"
    local lang="${4:-en}"

    _info "Writing config to ${CONFIG_FILE}..."

    # Create the file first so UCI has something to commit to
    touch "$CONFIG_FILE"

    uci -q batch <<EOF
delete telegram-bot.bot
set telegram-bot.bot=telegram
set telegram-bot.bot.token='${token}'
set telegram-bot.bot.chat_ids='${chat_id}'
set telegram-bot.bot.mode='${mode}'
set telegram-bot.bot.lang='${lang}'
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
    mkdir -p "${INSTALL_DIR}/core" "${INSTALL_DIR}/modules" "${INSTALL_DIR}/lang"

    cp "${SCRIPT_DIR}/src/bot.sh"                "${INSTALL_DIR}/bot.sh"
    cp "${SCRIPT_DIR}/src/core/config.sh"        "${INSTALL_DIR}/core/config.sh"
    cp "${SCRIPT_DIR}/src/core/device_identity.sh" "${INSTALL_DIR}/core/device_identity.sh"
    cp "${SCRIPT_DIR}/src/core/logger.sh"        "${INSTALL_DIR}/core/logger.sh"
    cp "${SCRIPT_DIR}/src/core/i18n.sh"          "${INSTALL_DIR}/core/i18n.sh"
    cp "${SCRIPT_DIR}/src/core/telegram.sh"      "${INSTALL_DIR}/core/telegram.sh"
    cp "${SCRIPT_DIR}/src/core/keyboard.sh"      "${INSTALL_DIR}/core/keyboard.sh"
    cp "${SCRIPT_DIR}/src/core/session.sh"       "${INSTALL_DIR}/core/session.sh"
    cp "${SCRIPT_DIR}/src/modules/monitor.sh"    "${INSTALL_DIR}/modules/monitor.sh"
    cp "${SCRIPT_DIR}/src/modules/devices.sh"    "${INSTALL_DIR}/modules/devices.sh"
    cp "${SCRIPT_DIR}/src/modules/firewall.sh"   "${INSTALL_DIR}/modules/firewall.sh"
    cp "${SCRIPT_DIR}/src/modules/system.sh"     "${INSTALL_DIR}/modules/system.sh"
    cp "${SCRIPT_DIR}/src/modules/bandwidth.sh"  "${INSTALL_DIR}/modules/bandwidth.sh"
    cp "${SCRIPT_DIR}/src/modules/updater.sh"    "${INSTALL_DIR}/modules/updater.sh"
    cp "${SCRIPT_DIR}/src/modules/notify.sh"     "${INSTALL_DIR}/modules/notify.sh"
    cp "${SCRIPT_DIR}/src/modules/lang.sh"       "${INSTALL_DIR}/modules/lang.sh"
    cp "${SCRIPT_DIR}/src/lang/en.sh"            "${INSTALL_DIR}/lang/en.sh"
    cp "${SCRIPT_DIR}/src/lang/pt.sh"            "${INSTALL_DIR}/lang/pt.sh"

    # Keep install/uninstall scripts accessible after download folder is gone
    cp "${SCRIPT_DIR}/install.sh"   "${INSTALL_DIR}/install.sh"
    cp "${SCRIPT_DIR}/uninstall.sh" "${INSTALL_DIR}/uninstall.sh"
    chmod +x "${INSTALL_DIR}/bot.sh" "${INSTALL_DIR}/install.sh" "${INSTALL_DIR}/uninstall.sh"
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
    command -v nft >/dev/null 2>&1 || return 0
    _info "Setting up nftables MAC blocklist..."
    # Delegate to the shared module — single source of truth for the nft include.
    . "${SCRIPT_DIR}/src/modules/firewall.sh"
    result=$(firewall_ensure_blocklist) || true
    case "$result" in
        ok)       _info "nftables blocklist configured" ;;
        reverted) _warn "nftables blocklist NOT applied: would break firewall. Internet preserved." ;;
        *)        _info "nft not available, skipping blocklist" ;;
    esac
}

# ---- update ----

_update() {
    _check_root
    _check_openwrt

    if [ ! -d "$INSTALL_DIR" ]; then
        _die "Bot is not installed. Run: sh install.sh"
    fi

    # When the bot triggers /update, this script runs as a child of the
    # telegram-bot service. Restarting the service from here makes procd kill
    # the whole service process tree — including this very script — mid-update,
    # which leaves the bot stopped and half-updated with no way to fix it
    # remotely. So when we are not on an interactive terminal (i.e. launched by
    # the bot), relaunch ourselves in a NEW session via setsid, detached from
    # the service tree, working from a private copy of our own files so the
    # caller is free to clean up its temp dir.
    if [ "${TGBOT_UPDATE_DETACHED:-}" != "1" ] && [ ! -t 1 ]; then
        if command -v setsid >/dev/null 2>&1; then
            local self="${TGBOT_UPDATE_SELF_DIR:-/tmp/telegram-bot-update-self}"
            rm -rf "$self"
            cp -r "$SCRIPT_DIR" "$self"
            _info "Detaching updater from the service process tree (setsid)..."
            TGBOT_UPDATE_DETACHED=1 setsid sh "${self}/install.sh" update \
                >/tmp/telegram-bot-update.log 2>&1 </dev/null &
            return 0
        fi
        _warn "setsid not available — running update inline; a service restart may interrupt it"
    fi

    local new_version old_version
    new_version=$(grep '^VERSION=' "${SCRIPT_DIR}/src/bot.sh" 2>/dev/null | cut -d'"' -f2)
    old_version=$(grep '^VERSION=' "${INSTALL_DIR}/bot.sh" 2>/dev/null | cut -d'"' -f2)
    [ -z "$old_version" ] && old_version="unknown"

    _info "=== OpenWRT Telegram Bot Updater ==="
    echo ""
    echo "  Current version: ${old_version}"
    echo "  New version:     ${new_version:-unknown}"
    echo ""

    # Sanity-check the new code before touching the installed version.
    # A sourced file that is missing causes sh to abort immediately, which leaves
    # the device unresponsive with no way to recover remotely.
    _info "Pre-flight: verifying new bot.sh loads all modules..."
    if ! sh "${SCRIPT_DIR}/src/bot.sh" --help >/dev/null 2>&1; then
        _die "Pre-flight failed: new bot.sh cannot load its modules. Update aborted — current version still running."
    fi

    # Copy the new files FIRST, while the service is still running. The running
    # bot already has its code loaded in memory, so swapping files on disk is
    # safe — and a failure here leaves the old version running instead of a
    # stopped, half-updated one.
    _info "Updating scripts..."
    _copy_files

    _info "Restarting service..."
    if [ -f "$SERVICE_FILE" ]; then
        "$SERVICE_FILE" restart
    else
        /etc/init.d/cron restart 2>/dev/null || true
    fi

    # Best-effort cleanup of the private snapshot created by the detached launch.
    [ "${TGBOT_UPDATE_DETACHED:-}" = "1" ] && rm -rf "${TGBOT_UPDATE_SELF_DIR:-/tmp/telegram-bot-update-self}"

    echo ""
    _info "=== Update complete! ==="
    echo ""
    echo "  Updated: ${old_version} -> ${new_version:-unknown}"
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
    lang=$(_get_lang)

    _write_uci_config "$token" "$chat_id" "$mode" "$lang"

    _info "Restarting service..."
    if [ -f "$SERVICE_FILE" ] && "$SERVICE_FILE" restart 2>/dev/null; then
        :
    else
        /etc/init.d/cron restart 2>/dev/null || true
    fi

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
            lang=$(_get_lang)

            echo ""
            _info "--- Installing ---"
            _copy_files
            _write_uci_config "$token" "$chat_id" "$mode" "$lang"
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
            echo "  Lang:    ${lang}"
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
