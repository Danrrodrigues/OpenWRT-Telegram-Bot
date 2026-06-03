#!/bin/sh
# New device detection — monitors /tmp/dhcp.leases for changes
# shellcheck source=../core/config.sh
# shellcheck source=../core/logger.sh
# shellcheck source=../core/telegram.sh

LEASES_FILE="/tmp/dhcp.leases"
KNOWN_DEVICES_FILE="/tmp/telegram-bot-known-devices"

monitor_init() {
    if [ ! -f "$KNOWN_DEVICES_FILE" ]; then
        [ -f "$LEASES_FILE" ] && awk '{print $2}' "$LEASES_FILE" > "$KNOWN_DEVICES_FILE" || touch "$KNOWN_DEVICES_FILE"
        log_info "monitor: initialized known devices snapshot"
    fi
}

# Check for new devices and send Telegram alert
monitor_check() {
    local chat_id="$1"
    local mac lease ip hostname
    [ -f "$LEASES_FILE" ] || return 0

    while IFS= read -r mac; do
        if ! grep -qx "$mac" "$KNOWN_DEVICES_FILE" 2>/dev/null; then
            lease=$(grep " ${mac} " "$LEASES_FILE" | head -1)
            ip=$(echo "$lease" | awk '{print $3}')
            hostname=$(echo "$lease" | awk '{print $4}')
            [ "$hostname" = "*" ] && hostname="Unknown"

            if [ "$BOT_ALERT_MODE" = "all" ] || ! _monitor_ever_seen "$mac"; then
                log_info "monitor: new device: $hostname ($mac / $ip)"
                _monitor_send_alert "$chat_id" "$hostname" "$mac" "$ip"
                _monitor_mark_seen "$mac"
            fi

            echo "$mac" >> "$KNOWN_DEVICES_FILE"
        fi
    done <<EOF
$(awk '{print $2}' "$LEASES_FILE")
EOF
}

_monitor_send_alert() {
    local chat_id="$1" hostname="$2" mac="$3" ip="$4"
    local ts
    ts=$(date '+%Y-%m-%d %H:%M:%S')
    telegram_send "$chat_id" "$(printf '🔔 <b>New device connected</b>\n\n<b>Name:</b> %s\n<b>IP:</b> <code>%s</code>\n<b>MAC:</b> <code>%s</code>\n<b>Time:</b> %s' \
        "$hostname" "$ip" "$mac" "$ts")"
}

_SEEN_EVER_FILE="/etc/telegram-bot-seen-devices"

_monitor_ever_seen() {
    grep -qx "$1" "$_SEEN_EVER_FILE" 2>/dev/null
}

_monitor_mark_seen() {
    echo "$1" >> "$_SEEN_EVER_FILE"
}

# Command: /alerts on|off
monitor_alerts_toggle() {
    local chat_id="$1"
    local arg="$2"
    local state
    case "$arg" in
        on|1)
            config_set "alerts" "1"
            BOT_ALERTS=1
            telegram_send "$chat_id" "✅ New device alerts <b>enabled</b>."
            ;;
        off|0)
            config_set "alerts" "0"
            BOT_ALERTS=0
            telegram_send "$chat_id" "🔕 New device alerts <b>disabled</b>."
            ;;
        *)
            state=$([ "$BOT_ALERTS" = "1" ] && echo "on" || echo "off")
            telegram_send "$chat_id" "Alerts are currently <b>${state}</b>. Use <code>/alerts on</code> or <code>/alerts off</code>."
            ;;
    esac
}
