#!/bin/sh
# OpenWRT Telegram Bot — main entry point

VERSION="0.4.0"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# shellcheck source=core/config.sh
. "${SCRIPT_DIR}/core/config.sh"
# shellcheck source=core/logger.sh
. "${SCRIPT_DIR}/core/logger.sh"
# shellcheck source=core/i18n.sh
. "${SCRIPT_DIR}/core/i18n.sh"
# shellcheck source=core/telegram.sh
. "${SCRIPT_DIR}/core/telegram.sh"
# shellcheck source=core/keyboard.sh
. "${SCRIPT_DIR}/core/keyboard.sh"
# shellcheck source=core/session.sh
. "${SCRIPT_DIR}/core/session.sh"
# shellcheck source=core/device_identity.sh
. "${SCRIPT_DIR}/core/device_identity.sh"
# shellcheck source=modules/monitor.sh
. "${SCRIPT_DIR}/modules/monitor.sh"
# shellcheck source=modules/devices.sh
. "${SCRIPT_DIR}/modules/devices.sh"
# shellcheck source=modules/firewall.sh
. "${SCRIPT_DIR}/modules/firewall.sh"
# shellcheck source=modules/system.sh
. "${SCRIPT_DIR}/modules/system.sh"
# shellcheck source=modules/bandwidth.sh
. "${SCRIPT_DIR}/modules/bandwidth.sh"
# shellcheck source=modules/updater.sh
. "${SCRIPT_DIR}/modules/updater.sh"
# shellcheck source=modules/notify.sh
. "${SCRIPT_DIR}/modules/notify.sh"
# shellcheck source=modules/lang.sh
. "${SCRIPT_DIR}/modules/lang.sh"

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
    i18n_load

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

    # Register/refresh the command menu and announce when the version changed.
    notify_check_version_change

    log_info "bot: started v${VERSION} (mode=${BOT_MODE} lang=${BOT_LANG} alert_mode=${BOT_ALERT_MODE})"
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
        /wake)
            devices_wake "$chat_id" "$args"
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
        /update)
            updater_check "$chat_id" "$args"
            ;;
        /rollback)
            updater_rollback "$chat_id" "$args"
            ;;
        /fix)
            firewall_fix "$chat_id"
            ;;
        /restartdns)
            system_restartdns "$chat_id" "$args"
            ;;
        /reboot)
            system_reboot "$chat_id" "$args"
            ;;
        /lang)
            lang_set "$chat_id" "$args"
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
/wake &lt;MAC or IP&gt; — Wake device with Wake-on-LAN
/block &lt;MAC&gt; — Block device permanently
/name &lt;MAC&gt; &lt;hostname&gt; — Save a device name by MAC
/unblock &lt;MAC&gt; — Remove block

<b>Speed limiting:</b>
/limit &lt;MAC&gt; &lt;down Mbps&gt; &lt;up Mbps&gt; — Set speed limit
/unlimit &lt;MAC&gt; — Remove speed limit

<b>Bot management:</b>
/update — Check for updates (add <i>confirm</i> to apply)
/rollback — Restore previous version (add <i>confirm</i> to apply)
/fix — Repair firewall/blocklist setup
/restartdns — Restart DNS cache (dnsmasq)
/reboot — Reboot the router (add confirm to apply)

/lang en|pt — Change bot language
/help — Show this message

<i>Tip: call kick/block/unblock/wake/name/limit/reboot/update/rollback/restartdns with no arguments to get tappable buttons instead of typing them out.</i>"
}

# Handle a button press: acknowledge it, then either resolve it directly
# (cancel, device-picker for a guided flow) or run the same handler function
# the equivalent text command would call. TELEGRAM_REDIRECT_* makes that
# handler's normal telegram_send edit this message instead of sending a new
# one — see telegram_send in core/telegram.sh.
_bot_dispatch_callback() {
    local chat_id="$1"
    local message_id="$2"
    local callback_id="$3"
    local data="$4"
    local command arg

    command="${data%%:*}"
    arg="${data#*:}"

    telegram_answer_callback "$callback_id"
    log_info "bot: callback $command from $chat_id"

    case "$command" in
        cancel)
            telegram_edit_message "$chat_id" "$message_id" "$T_CANCELLED"
            return
            ;;
        limitpick)
            session_set_pending "$chat_id" "limit" "$arg"
            telegram_edit_message "$chat_id" "$message_id" "$T_LIMIT_PROMPT"
            return
            ;;
        namepick)
            session_set_pending "$chat_id" "name" "$arg"
            telegram_edit_message "$chat_id" "$message_id" "$T_NAME_PROMPT"
            return
            ;;
    esac

    TELEGRAM_REDIRECT_CHAT_ID="$chat_id"
    TELEGRAM_REDIRECT_MESSAGE_ID="$message_id"

    case "$command" in
        reboot)     system_reboot "$chat_id" "confirm" ;;
        restartdns) system_restartdns "$chat_id" "confirm" ;;
        update)     updater_check "$chat_id" "confirm" ;;
        rollback)   updater_rollback "$chat_id" "confirm" ;;
        kick)       devices_kick "$chat_id" "$arg" ;;
        block)      devices_block "$chat_id" "$arg" ;;
        unblock)    devices_unblock "$chat_id" "$arg" ;;
        wake)       devices_wake "$chat_id" "$arg" ;;
        *)          log_warn "bot: unknown callback command $command" ;;
    esac

    # In case the handler took a path that never called telegram_send, don't
    # let a stale redirect leak into an unrelated later message.
    TELEGRAM_REDIRECT_CHAT_ID=""
    TELEGRAM_REDIRECT_MESSAGE_ID=""
}

# Resume a guided flow (/limit or /name) once the user replies with the free
# text a device-picker button asked for.
_bot_dispatch_pending() {
    local chat_id="$1"
    local action="$2"
    local mac="$3"
    local text="$4"

    case "$action" in
        limit)
            bandwidth_limit "$chat_id" "$mac" "$(echo "$text" | awk '{print $1}')" "$(echo "$text" | awk '{print $2}')"
            ;;
        name)
            devices_set_name "$chat_id" "${mac} ${text}"
            ;;
    esac
}

_bot_process_updates() {
    local offset count i chat_id text last_id
    local callback_id callback_data message_id pending action mac
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
        callback_id=$(telegram_update_field "$i" "callback_query.id")

        if [ -n "$callback_id" ]; then
            chat_id=$(telegram_update_field "$i" "callback_query.message.chat.id")
            message_id=$(telegram_update_field "$i" "callback_query.message.message_id")
            callback_data=$(telegram_update_field "$i" "callback_query.data")

            if [ -n "$chat_id" ] && config_is_authorized "$chat_id"; then
                _bot_dispatch_callback "$chat_id" "$message_id" "$callback_id" "$callback_data"
            else
                log_warn "bot: unauthorized callback chat_id=$chat_id"
                telegram_answer_callback "$callback_id"
            fi

            i=$((i + 1))
            continue
        fi

        chat_id=$(telegram_update_field "$i" "message.chat.id")
        text=$(telegram_update_field "$i" "message.text")

        if [ -n "$chat_id" ] && [ -n "$text" ]; then
            if config_is_authorized "$chat_id"; then
                case "$text" in
                    /*)
                        session_clear_pending "$chat_id"
                        _bot_dispatch "$chat_id" "$text"
                        ;;
                    *)
                        pending=$(session_get_pending "$chat_id")
                        if [ -n "$pending" ]; then
                            session_clear_pending "$chat_id"
                            action="${pending%%:*}"
                            mac="${pending#*:}"
                            _bot_dispatch_pending "$chat_id" "$action" "$mac" "$text"
                        else
                            _bot_dispatch "$chat_id" "$text"
                        fi
                        ;;
                esac
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

        # Self-gating: does work at most once per day, at/after 08:00.
        notify_daily_update_check

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

    notify_daily_update_check
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
