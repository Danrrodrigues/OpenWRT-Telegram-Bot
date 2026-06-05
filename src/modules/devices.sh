#!/bin/sh
# Device control — list, kick (deauth), block, unblock
# shellcheck source=../core/config.sh
# shellcheck source=../core/logger.sh
# shellcheck source=../core/telegram.sh

LEASES_FILE="/tmp/dhcp.leases"

# Command: /devices
devices_list() {
    local chat_id="$1"
    local output="<b>Network Devices</b>\n\n"
    local count=0
    local mac ip hostname badge
    local wifi_macs
    wifi_macs=$(_devices_wifi_macs)

    while IFS= read -r line; do
        mac=$(echo "$line" | awk '{print $2}')
        ip=$(echo "$line" | awk '{print $3}')
        hostname=$(device_identity_hostname "$mac")

        if echo "$wifi_macs" | grep -qx "$(echo "$mac" | tr 'A-Z' 'a-z')"; then
            badge="📶 Wi-Fi"
        else
            badge="🔌 Wired / Offline"
        fi

        count=$((count + 1))
        output="${output}<b>${count}.</b> ${hostname}  <i>${badge}</i>\n   IP: <code>${ip}</code>\n   MAC: <code>${mac}</code>\n\n"
    done < "$LEASES_FILE"

    if [ "$count" -eq 0 ]; then
        telegram_send "$chat_id" "No devices found in DHCP leases."
        return
    fi

    telegram_send "$chat_id" "$(printf '%b' "$output")"
}

# Command: /kick <mac|ip>
devices_kick() {
    local chat_id="$1"
    local target="$2"
    local mac kicked iface hostname

    if [ -z "$target" ]; then
        telegram_send "$chat_id" "Usage: <code>/kick &lt;MAC or IP&gt;</code>"
        return
    fi

    mac=$(_devices_resolve_mac "$target")
    if [ -z "$mac" ]; then
        telegram_send "$chat_id" "❌ Device not found: <code>${target}</code>"
        return
    fi

    if ! _devices_wifi_macs | grep -qx "$mac"; then
        hostname=$(device_identity_hostname "$mac")
        telegram_send "$chat_id" "⚠️ <b>${hostname}</b> (<code>${mac}</code>) is not connected via Wi-Fi.\nUse /devices to check its current status."
        return
    fi

    kicked=0
    for iface in $(iw dev 2>/dev/null | awk '/Interface/{print $2}'); do
        if hostapd_cli -i "$iface" deauthenticate "$mac" 2>/dev/null | grep -q "OK"; then
            kicked=$((kicked + 1))
        fi
    done

    if [ "$kicked" -gt 0 ]; then
        hostname=$(device_identity_hostname "$mac")
        telegram_send "$chat_id" "✅ Kicked <b>${hostname}</b> (<code>${mac}</code>) from Wi-Fi."
        log_info "devices: kicked $mac ($hostname)"
    else
        telegram_send "$chat_id" "⚠️ Could not kick <code>${mac}</code>. Device may be wired or already disconnected."
    fi
}

# Command: /block <mac>
devices_block() {
    local chat_id="$1"
    local target="$2"
    local mac iface hostname

    if [ -z "$target" ]; then
        telegram_send "$chat_id" "Usage: <code>/block &lt;MAC&gt;</code>
Example: <code>/block AA:BB:CC:DD:EE:FF</code>"
        return
    fi

    mac=$(_devices_resolve_mac "$target")
    if [ -z "$mac" ]; then
        telegram_send "$chat_id" "❌ Device not found: <code>${target}</code>"
        return
    fi

    if command -v nft >/dev/null 2>&1; then
        # shellcheck disable=SC1083
        nft list set inet fw4 telegram_blocked >/dev/null 2>&1 || \
            nft add set inet fw4 telegram_blocked { type ether_addr \; } 2>/dev/null
        # shellcheck disable=SC1083
        nft add element inet fw4 telegram_blocked { "$mac" } 2>/dev/null
    fi

    for iface in $(iw dev 2>/dev/null | awk '/Interface/{print $2}'); do
        hostapd_cli -i "$iface" deauthenticate "$mac" 2>/dev/null || true
    done

    config_add_list "blocked" "$mac"

    hostname=$(device_identity_hostname "$mac")
    telegram_send "$chat_id" "🚫 Blocked <b>${hostname}</b> (<code>${mac}</code>). Device cannot reconnect."
    log_info "devices: blocked $mac ($hostname)"
}

# Command: /name <mac> <hostname>
devices_set_name() {
    local chat_id="$1"
    local args="$2"
    local mac hostname escaped_hostname

    mac=$(printf '%s\n' "$args" | awk '{print $1}')
    hostname=$(printf '%s\n' "$args" | sed 's/^[[:space:]]*//; s/^[^[:space:]]*[[:space:]]*//; s/[[:space:]]*$//')

    if ! printf '%s\n' "$mac" | grep -Eq '^([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}$' || [ -z "$hostname" ] || [ "$hostname" = "$mac" ]; then
        telegram_send "$chat_id" "Usage: <code>/name &lt;MAC&gt; &lt;hostname&gt;</code>"
        return
    fi

    mac=$(printf '%s\n' "$mac" | tr 'A-Z' 'a-z')
    escaped_hostname=$(device_identity_escape_html "$hostname")

    if device_identity_set_static_name "$mac" "$hostname"; then
        telegram_send "$chat_id" "✅ Name set for <code>${mac}</code>: <b>${escaped_hostname}</b>."
        log_info "devices: named $mac as $hostname"
        return
    fi

    telegram_send "$chat_id" "❌ Could not save name for <code>${mac}</code>."
}

# Command: /unblock <mac>
devices_unblock() {
    local chat_id="$1"
    local target="$2"

    if [ -z "$target" ]; then
        telegram_send "$chat_id" "Usage: <code>/unblock &lt;MAC&gt;</code>"
        return
    fi

    local mac="$target"

    if command -v nft >/dev/null 2>&1; then
        # shellcheck disable=SC1083
        nft delete element inet fw4 telegram_blocked { "$mac" } 2>/dev/null || true
    fi

    config_del_list "blocked" "$mac"

    telegram_send "$chat_id" "✅ Unblocked <code>${mac}</code>. Device can now reconnect."
    log_info "devices: unblocked $mac"
}

# Restore blocks from UCI on bot startup
devices_restore_blocks() {
    command -v nft >/dev/null 2>&1 || return 0

    # shellcheck disable=SC1083
    nft list set inet fw4 telegram_blocked >/dev/null 2>&1 || \
        nft add set inet fw4 telegram_blocked { type ether_addr \; } 2>/dev/null

    config_get_list "blocked" | while IFS= read -r mac; do
        if [ -n "$mac" ]; then
            # shellcheck disable=SC1083
            nft add element inet fw4 telegram_blocked { "$mac" } 2>/dev/null || true
        fi
    done
    log_info "devices: restored blocked MACs from config"
}

# Command: /status
devices_status() {
    local chat_id="$1"
    local uptime cpu_load mem_total mem_free mem_used device_count

    uptime=$(awk '{printf "%dd %02d:%02d:%02d", $1/86400, ($1%86400)/3600, ($1%3600)/60, $1%60}' /proc/uptime 2>/dev/null)
    cpu_load=$(awk '{print $1, $2, $3}' /proc/loadavg 2>/dev/null)
    mem_total=$(awk '/MemTotal/{print $2}' /proc/meminfo 2>/dev/null)
    mem_free=$(awk '/MemAvailable/{print $2}' /proc/meminfo 2>/dev/null)
    mem_used=$(( (mem_total - mem_free) / 1024 ))
    mem_total=$(( mem_total / 1024 ))
    device_count=$(wc -l < "$LEASES_FILE" 2>/dev/null | tr -d ' ')

    telegram_send "$chat_id" "$(printf '<b>Router Status</b>\n\n<b>Uptime:</b> %s\n<b>Load:</b> %s\n<b>Memory:</b> %s/%s MB\n<b>Devices:</b> %s' \
        "$uptime" "$cpu_load" "$mem_used" "$mem_total" "${device_count:-0}")"
}

# ---- helpers ----

_devices_wifi_macs() {
    local iface
    iw dev 2>/dev/null | awk '$1=="Interface"{print $2}' | while IFS= read -r iface; do
        iw dev "$iface" station dump 2>/dev/null | awk '$1=="Station"{print tolower($2)}'
    done | awk 'NF && !seen[$0]++'
}

_devices_resolve_mac() {
    local target="$1"
    if echo "$target" | grep -qE '^([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}$'; then
        echo "$target" | tr 'A-Z' 'a-z'
        return
    fi
    awk -v ip="$target" '$3==ip{print $2}' "$LEASES_FILE" 2>/dev/null | tr 'A-Z' 'a-z' | head -1
}

_devices_hostname() {
    device_identity_hostname "$1"
}
