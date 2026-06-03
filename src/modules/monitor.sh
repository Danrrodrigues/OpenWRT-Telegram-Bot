#!/bin/sh
# New device detection — monitors /tmp/dhcp.leases for changes

LEASES_FILE="/tmp/dhcp.leases"
KNOWN_DEVICES_FILE="/tmp/telegram-bot-known-devices"

# Initialize known devices snapshot from current leases
monitor_init() {
    if [ ! -f "$KNOWN_DEVICES_FILE" ]; then
        [ -f "$LEASES_FILE" ] && awk '{print $2}' "$LEASES_FILE" > "$KNOWN_DEVICES_FILE" || touch "$KNOWN_DEVICES_FILE"
        log_info "monitor: initialized known devices snapshot"
    fi
}

# Check for new devices. Sends Telegram alert for each new one.
# Usage: monitor_check <chat_id>
monitor_check() {
    local chat_id="$1"
    [ -f "$LEASES_FILE" ] || return 0

    local current_macs new_mac hostname ip mac

    # Build list of current MACs
    current_macs=$(awk '{print $2}' "$LEASES_FILE")

    while IFS= read -r mac; do
        if ! grep -qx "$mac" "$KNOWN_DEVICES_FILE" 2>/dev/null; then
            # New device found
            local lease
            lease=$(grep " ${mac} " "$LEASES_FILE" | head -1)
            ip=$(echo "$lease" | awk '{print $3}')
            hostname=$(echo "$lease" | awk '{print $4}')
            [ "$hostname" = "*" ] && hostname="Unknown"

            if [ "$BOT_ALERT_MODE" = "all" ] || ! _monitor_ever_seen "$mac"; then
                log_info "monitor: new device detected: $hostname ($mac / $ip)"
                _monitor_send_alert "$chat_id" "$hostname" "$mac" "$ip"
            fi

            # Mark as known
            echo "$mac" >> "$KNOWN_DEVICES_FILE"
        fi
    done <<EOF
$(echo "$current_macs")
EOF
}

_monitor_send_alert() {
    local chat_id="$1"
    local hostname="$2"
    local mac="$3"
    local ip="$4"
    local ts
    ts=$(date '+%Y-%m-%d %H:%M:%S')

    telegram_send "$chat_id" "$(printf '🔔 *New device connected*\n\n*Name:* %s\n*IP:* %s\n*MAC:* %s\n*Time:* %s' \
        "$hostname" "$ip" "$mac" "$ts")"
}

# Persistent seen-devices log (survives reboots via overlay)
_SEEN_EVER_FILE="/etc/telegram-bot-seen-devices"

_monitor_ever_seen() {
    local mac="$1"
    grep -qx "$mac" "$_SEEN_EVER_FILE" 2>/dev/null
}

_monitor_mark_seen() {
    local mac="$1"
    echo "$mac" >> "$_SEEN_EVER_FILE"
}

# Command handler: /alerts on|off
monitor_alerts_toggle() {
    local chat_id="$1"
    local arg="$2"
    case "$arg" in
        on|1)
            config_set "alerts" "1"
            BOT_ALERTS=1
            telegram_send "$chat_id" "✅ New device alerts *enabled*."
            ;;
        off|0)
            config_set "alerts" "0"
            BOT_ALERTS=0
            telegram_send "$chat_id" "🔕 New device alerts *disabled*."
            ;;
        *)
            local state
            state=$([ "$BOT_ALERTS" = "1" ] && echo "on" || echo "off")
            telegram_send "$chat_id" "Alerts are currently *${state}*. Use \`/alerts on\` or \`/alerts off\`."
            ;;
    esac
}
