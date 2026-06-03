#!/bin/sh
# OpenWRT Telegram Bot — main entry point
# Supports daemon mode (background loop) and cron mode (single run)

# Resolve script directory regardless of how it was invoked
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# shellcheck source=core/config.sh
. "${SCRIPT_DIR}/core/config.sh"
# shellcheck source=core/logger.sh
. "${SCRIPT_DIR}/core/logger.sh"
# shellcheck source=core/telegram.sh
. "${SCRIPT_DIR}/core/telegram.sh"
# shellcheck source=modules/monitor.sh
. "${SCRIPT_DIR}/modules/monitor.sh"
# shellcheck source=modules/devices.sh
. "${SCRIPT_DIR}/modules/devices.sh"
# shellcheck source=modules/bandwidth.sh
. "${SCRIPT_DIR}/modules/bandwidth.sh"

OFFSET_FILE="/tmp/telegram-bot-offset"

_bot_usage() {
    cat <<EOF
OpenWRT Telegram Bot

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
        log_error "BOT_TOKEN not configured. Run install.sh or set token via uci."
        exit 1
    fi

    if [ -z "$BOT_CHAT_IDS" ]; then
        log_error "chat_ids not configured. Run install.sh or set chat_ids via uci."
        exit 1
    fi

    monitor_init
    devices_restore_blocks
    bandwidth_restore_limits

    log_info "bot: started (mode=${BOT_MODE} alerts=${BOT_ALERTS})"
}

_bot_dispatch() {
    local chat_id="$1"
    local text="$2"

    # Extract command and argument(s)
    local cmd args
    cmd=$(echo "$text" | awk '{print $1}' | tr 'A-Z' 'a-z')
    # Strip @BotName suffix if present
    cmd=$(echo "$cmd" | sed 's/@.*//')
    args=$(echo "$text" | cut -d' ' -f2-)
    [ "$args" = "$text" ] && args=""

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
        /unblock)
            devices_unblock "$chat_id" "$args"
            ;;
        /limit)
            local target down up
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
            telegram_send "$chat_id" "Unknown command: \`${cmd}\`\nType /help for available commands."
            ;;
    esac
}

_bot_send_help() {
    local chat_id="$1"
    telegram_send "$chat_id" "$(cat <<'EOF'
*OpenWRT Telegram Bot*

*Network monitoring:*
/devices — List connected devices
/status — Router status (CPU, RAM, uptime)
/alerts on|off — Toggle new device alerts

*Device control:*
/kick `<MAC or IP>` — Disconnect from Wi-Fi
/block `<MAC>` — Block device permanently
/unblock `<MAC>` — Remove block

*Speed limiting:*
/limit `<MAC> <↓Mbps> <↑Mbps>` — Set speed limit
/unlimit `<MAC>` — Remove speed limit

/help — Show this message
EOF
)"
}

_bot_process_updates() {
    local offset
    offset=$(cat "$OFFSET_FILE" 2>/dev/null) || offset=0

    local count
    count=$(telegram_get_updates "$offset")
    [ "$count" -eq 0 ] 2>/dev/null && return

    local i=0
    while [ "$i" -lt "$count" ]; do
        local update_id chat_id text
        update_id=$(telegram_update_field "$i" "update_id")
        chat_id=$(telegram_update_field "$i" "message.chat.id")
        text=$(telegram_update_field "$i" "message.text")

        if [ -n "$chat_id" ] && [ -n "$text" ]; then
            if config_is_authorized "$chat_id"; then
                log_debug "bot: update $update_id from $chat_id: $text"
                _bot_dispatch "$chat_id" "$text"
            else
                log_warn "bot: unauthorized message from chat_id=$chat_id"
            fi
        fi

        i=$((i + 1))
    done

    # Advance offset past processed updates
    local last_id
    last_id=$(telegram_last_update_id "$count")
    [ -n "$last_id" ] && echo $((last_id + 1)) > "$OFFSET_FILE"
}

_bot_daemon() {
    log_info "bot: entering daemon loop (poll_interval=${BOT_POLL_INTERVAL}s)"

    local last_monitor_check=0

    while true; do
        _bot_process_updates

        # Run device monitor check
        if [ "$BOT_ALERTS" = "1" ]; then
            local now
            now=$(date +%s)
            if [ $((now - last_monitor_check)) -ge "$BOT_POLL_INTERVAL" ]; then
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
    log_info "bot: cron run"
    _bot_process_updates

    if [ "$BOT_ALERTS" = "1" ]; then
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
