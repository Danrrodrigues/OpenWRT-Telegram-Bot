#!/bin/sh
# New device detection — monitors /tmp/dhcp.leases for changes
# shellcheck source=../core/config.sh
# shellcheck source=../core/logger.sh
# shellcheck source=../core/telegram.sh

LEASES_FILE="/tmp/dhcp.leases"
KNOWN_DEVICES_FILE="/tmp/telegram-bot-known-devices"

monitor_init() {
    if [ ! -f "$KNOWN_DEVICES_FILE" ]; then
        if [ -f "$LEASES_FILE" ]; then
            awk '{print $2}' "$LEASES_FILE" > "$KNOWN_DEVICES_FILE"
        else
            touch "$KNOWN_DEVICES_FILE"
        fi
        log_info "monitor: initialized known devices snapshot"
    fi
}

# Check for new devices and send Telegram alert
monitor_check() {
    local chat_id="$1"
    local mac lease ip hostname ssid current_file
    current_file="${KNOWN_DEVICES_FILE}.current"

    _monitor_current_macs > "$current_file"

    while IFS= read -r mac; do
        [ -n "$mac" ] || continue

        if ! grep -qx "$mac" "$KNOWN_DEVICES_FILE" 2>/dev/null; then
            lease=$(grep " ${mac} " "$LEASES_FILE" | head -1)
            ip=$(echo "$lease" | awk '{print $3}')
            hostname=$(device_identity_hostname "$mac")
            ssid=$(_monitor_wifi_ssid_for_mac "$mac")

            if _monitor_should_alert "$mac"; then
                log_info "monitor: new device: $hostname ($mac / $ip)"
                _monitor_send_alert "$chat_id" "$hostname" "$mac" "$ip" "$ssid"
            fi

            _monitor_mark_seen "$mac"
        fi
    done < "$current_file"

    mv "$current_file" "$KNOWN_DEVICES_FILE"
}

_monitor_current_macs() {
    local iface

    if command -v iw >/dev/null 2>&1; then
        iw dev 2>/dev/null | awk '$1=="Interface"{print $2}' | while IFS= read -r iface; do
            [ -n "$iface" ] || continue
            iw dev "$iface" station dump 2>/dev/null | awk '$1=="Station"{print tolower($2)}'
        done | awk 'NF && !seen[$0]++'
        return
    fi

    [ -f "$LEASES_FILE" ] && awk '{print tolower($2)}' "$LEASES_FILE"
}

_monitor_send_alert() {
    local chat_id="$1" hostname="$2" mac="$3" ip="$4" ssid="$5"
    local ts net
    ts=$(date '+%Y-%m-%d %H:%M:%S')
    if [ -n "$ssid" ]; then
        net="📶 ${ssid}"
    else
        net="🔌 Wired"
    fi
    telegram_send "$chat_id" "$(printf '🔔 <b>New device connected</b>\n\n<b>Name:</b> %s\n<b>Network:</b> %s\n<b>IP:</b> <code>%s</code>\n<b>MAC:</b> <code>%s</code>\n<b>Time:</b> %s' \
        "$hostname" "$net" "$ip" "$mac" "$ts")"
}

_monitor_wifi_ssid_for_mac() {
    local target_mac="$1" iface
    for iface in $(iw dev 2>/dev/null | awk '$1=="Interface"{print $2}'); do
        if iw dev "$iface" station dump 2>/dev/null | \
                awk '$1=="Station"{print tolower($2)}' | grep -qx "$target_mac"; then
            iw dev "$iface" info 2>/dev/null | \
                awk '/[[:space:]]ssid /{sub(/^.*ssid /, ""); print; exit}'
            return
        fi
    done
}

_SEEN_EVER_FILE="/etc/telegram-bot-seen-devices"

_monitor_ever_seen() {
    grep -qx "$1" "$_SEEN_EVER_FILE" 2>/dev/null
}

_monitor_mark_seen() {
    _monitor_ever_seen "$1" || echo "$1" >> "$_SEEN_EVER_FILE"
}

_monitor_should_alert() {
    local mac="$1"

    case "${BOT_ALERT_MODE:-all}" in
        off)
            return 1
            ;;
        all)
            return 0
            ;;
        known)
            _monitor_ever_seen "$mac"
            return
            ;;
        unknown)
            ! _monitor_ever_seen "$mac"
            return
            ;;
        *)
            return 0
            ;;
    esac
}

# Command: /alerts off|known|unknown|all
monitor_alerts_toggle() {
    local chat_id="$1"
    local arg="$2"
    local mode

    case "$arg" in
        on|1)
            mode="all"
            ;;
        off|0)
            mode="off"
            ;;
        all|known|unknown)
            mode="$arg"
            ;;
        *)
            telegram_send "$chat_id" "Alerts mode is currently <b>${BOT_ALERT_MODE:-all}</b>.
Use <code>/alerts off</code>, <code>/alerts known</code>, <code>/alerts unknown</code>, or <code>/alerts all</code>."
            return
            ;;
    esac

    config_set "alert_mode" "$mode"
    BOT_ALERT_MODE="$mode"

    # shellcheck disable=SC2034
    if [ "$mode" = "off" ]; then
        BOT_ALERTS=0
    else
        BOT_ALERTS=1
    fi

    telegram_send "$chat_id" "✅ Device alerts mode set to <b>${mode}</b>."
}
