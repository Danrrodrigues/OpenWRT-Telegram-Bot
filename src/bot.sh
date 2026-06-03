#!/bin/sh
# OpenWRT Telegram Bot — main entry point

VERSION="0.2.2"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# shellcheck source=core/config.sh
. "${SCRIPT_DIR}/core/config.sh"
# shellcheck source=core/logger.sh
. "${SCRIPT_DIR}/core/logger.sh"
# shellcheck source=core/telegram.sh
. "${SCRIPT_DIR}/core/telegram.sh"
# shellcheck source=core/device_identity.sh
. "${SCRIPT_DIR}/core/device_identity.sh"
# shellcheck source=modules/monitor.sh
. "${SCRIPT_DIR}/modules/monitor.sh"
# shellcheck source=modules/devices.sh
. "${SCRIPT_DIR}/modules/devices.sh"
# shellcheck source=modules/bandwidth.sh
. "${SCRIPT_DIR}/modules/bandwidth.sh"

OFFSET_FILE="/tmp/telegram-bot-offset"

_bot_usage() {
    cat <<EOF
OpenWRT Telegram Bot v${VERSION}

Usage: bot.sh [--daemon|--cron|--help]

  --daemon   Run as background service (default)
  --cron     Process pending updates once and exit (for cron jobs)
  --help     Show this help

Config: /etc/config/telegram-bot (UCI)
Docs:   https://github.com/Danrrodrigues/OpenWRT-Telegram-Bot
EOF
}

_bot_init() {
    config_load

    if [ -z "$BOT_TOKEN" ]; then
        log_error "BOT_TOKEN not configured. Run: sh /usr/lib/telegram-bot/install.sh reconfigure"
        exit 1
    fi

    if [ -z "$BOT_CHAT_IDS" ]; then
        log_error "chat_ids not configured. Run: sh /usr/lib/telegram-bot/install.sh reconfigure"
        exit 1
    fi

    monitor_init
    devices_restore_blocks >/dev/null 2>&1
    bandwidth_restore_limits

    log_info "bot: started v${VERSION} (mode=${BOT_MODE} alert_mode=${BOT_ALERT_MODE})"
}

_bot_dispatch() {
    local chat_id="$1"
    local text="$2"
    local cmd args target down up

    cmd=$(echo "$text" | awk '{print $1}' | tr 'A-Z' 'a-z')
    cmd=$(echo "$cmd" | sed 's/@.*//')
    args=$(printf '%s\n' "$text" | sed 's/^[^[:space:]]*[[:space:]]*//')

    log_info "bot: command $cmd from $chat_id"

    case "$cmd" in
        /start|/help)
            _bot_send_help "$chat_id"
            ;;
        /devices)
            devices_list "$chat_id"
            ;;
        /kick)
            devices_kick "$chat_id" "$args"
            ;;
        /block)
            devices_block "$chat_id" "$args"
            ;;
        /name)
            devices_set_name "$chat_id" "$args"
            ;;
        /unblock)
            devices_unblock "$chat_id" "$args"
            ;;
        /limit)
            target=$(echo "$args" | awk '{print $1}')
            down=$(echo "$args" | awk '{print $2}')
            up=$(echo "$args" | awk '{print $3}')
            bandwidth_limit "$chat_id" "$target" "$down" "$up"
            ;;
        /unlimit)
            bandwidth_unlimit "$chat_id" "$args"
            ;;
        /status)
            devices_status "$chat_id"
            ;;
        /alerts)
            monitor_alerts_toggle "$chat_id" "$args"
            ;;
        *)
            telegram_send "$chat_id" "Unknown command: <code>${cmd}</code>
Type /help for available commands."
            ;;
    esac
}

_bot_send_help() {
    local chat_id="$1"
    telegram_send "$chat_id" "<b>OpenWRT Telegram Bot v${VERSION}</b>

<b>Network monitoring:</b>
/devices — List connected devices
/status — Router status (CPU, RAM, uptime)
/alerts off|known|unknown|all — Set device alert mode

<b>Device control:</b>
/kick &lt;MAC or IP&gt; — Disconnect from Wi-Fi
/block &lt;MAC&gt; — Block device permanently
/name &lt;MAC&gt; &lt;hostname&gt; — Save a device name by MAC
/unblock &lt;MAC&gt; — Remove block

<b>Speed limiting:</b>
/limit &lt;MAC&gt; &lt;down Mbps&gt; &lt;up Mbps&gt; — Set speed limit
/unlimit &lt;MAC&gt; — Remove speed limit

/help — Show this message"
}

_bot_process_updates() {
    local offset count i chat_id text last_id
    if [ -f "$OFFSET_FILE" ]; then
        read -r offset < "$OFFSET_FILE" || offset=0
    else
        offset=0
    fi

    count=$(telegram_get_updates "$offset")

    [ -z "$count" ] && count=0
    [ "$count" -eq 0 ] 2>/dev/null && return

    log_info "bot: processing $count update(s)"

    i=0
    while [ "$i" -lt "$count" ]; do
        chat_id=$(telegram_update_field "$i" "message.chat.id")
        text=$(telegram_update_field "$i" "message.text")

        if [ -n "$chat_id" ] && [ -n "$text" ]; then
            if config_is_authorized "$chat_id"; then
                _bot_dispatch "$chat_id" "$text"
            else
                log_warn "bot: unauthorized chat_id=$chat_id"
            fi
        fi

        i=$((i + 1))
    done

    last_id=$(telegram_last_update_id)
    [ -n "$last_id" ] && echo $((last_id + 1)) > "$OFFSET_FILE"
}

_bot_daemon() {
    log_info "bot: entering daemon loop (poll_interval=${BOT_POLL_INTERVAL}s)"

    local last_monitor_check now cid
    last_monitor_check=0

    while true; do
        _bot_process_updates

        if [ "$BOT_ALERTS" = "1" ]; then
            now=$(date +%s)
            if [ $((now - last_monitor_check)) -ge "$BOT_POLL_INTERVAL" ]; then
                # shellcheck disable=SC2086
                for cid in $BOT_CHAT_IDS; do
                    monitor_check "$cid"
                done
                last_monitor_check=$now
            fi
        fi

        sleep 2
    done
}

_bot_cron() {
    local cid
    log_info "bot: cron run"
    _bot_process_updates

    if [ "$BOT_ALERTS" = "1" ]; then
        # shellcheck disable=SC2086
        for cid in $BOT_CHAT_IDS; do
            monitor_check "$cid"
        done
    fi
}

# ---- main ----

mode="${1:---daemon}"

case "$mode" in
    --help|-h)
        _bot_usage
        exit 0
        ;;
    --cron)
        _bot_init
        _bot_cron
        ;;
    --daemon|"")
        _bot_init
        _bot_daemon
        ;;
    *)
        echo "Unknown option: $mode" >&2
        _bot_usage
        exit 1
        ;;
esac
