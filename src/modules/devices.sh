#!/bin/sh
# Device control — list, kick (deauth), block, unblock

LEASES_FILE="/tmp/dhcp.leases"

# Command: /devices
# Lists all connected devices from ARP + DHCP leases
devices_list() {
    local chat_id="$1"
    local output="*Connected Devices*\n\n"
    local count=0

    while IFS= read -r line; do
        local mac ip hostname
        mac=$(echo "$line" | awk '{print $2}')
        ip=$(echo "$line" | awk '{print $3}')
        hostname=$(echo "$line" | awk '{print $4}')
        [ "$hostname" = "*" ] && hostname="Unknown"

        count=$((count + 1))
        output="${output}*${count}.* ${hostname}\n   IP: \`${ip}\`\n   MAC: \`${mac}\`\n\n"
    done < "$LEASES_FILE"

    if [ "$count" -eq 0 ]; then
        telegram_send "$chat_id" "No devices found in DHCP leases."
        return
    fi

    telegram_send "$chat_id" "$(printf '%b' "$output")"
}

# Command: /kick <mac|ip>
# Deauthenticates device from all Wi-Fi interfaces
devices_kick() {
    local chat_id="$1"
    local target="$2"

    if [ -z "$target" ]; then
        telegram_send "$chat_id" "Usage: \`/kick <MAC or IP>\`"
        return
    fi

    # Resolve IP to MAC if needed
    local mac
    mac=$(_devices_resolve_mac "$target")
    if [ -z "$mac" ]; then
        telegram_send "$chat_id" "❌ Device not found: \`${target}\`"
        return
    fi

    local kicked=0
    local iface

    # Try all wireless interfaces
    for iface in $(iw dev 2>/dev/null | awk '/Interface/{print $2}'); do
        if hostapd_cli -i "$iface" deauthenticate "$mac" 2>/dev/null | grep -q "OK"; then
            kicked=$((kicked + 1))
        fi
    done

    if [ "$kicked" -gt 0 ]; then
        local hostname
        hostname=$(_devices_hostname "$mac")
        telegram_send "$chat_id" "✅ Kicked *${hostname}* (\`${mac}\`) from Wi-Fi."
        log_info "devices: kicked $mac ($hostname)"
    else
        telegram_send "$chat_id" "⚠️ Could not kick \`${mac}\`. Device may be on wired connection or already disconnected."
    fi
}

# Command: /block <mac>
# Adds MAC to nftables set and persists via UCI
devices_block() {
    local chat_id="$1"
    local target="$2"

    if [ -z "$target" ]; then
        telegram_send "$chat_id" "Usage: \`/block <MAC>\`\nExample: \`/block AA:BB:CC:DD:EE:FF\`"
        return
    fi

    local mac
    mac=$(_devices_resolve_mac "$target")
    if [ -z "$mac" ]; then
        telegram_send "$chat_id" "❌ Device not found: \`${target}\`"
        return
    fi

    # Add to nftables MAC blocklist (fw4 on OpenWRT 22+)
    if command -v nft >/dev/null 2>&1; then
        # Ensure set exists
        nft list set inet fw4 telegram_blocked 2>/dev/null || \
            nft add set inet fw4 telegram_blocked { type ether_addr \; } 2>/dev/null
        nft add element inet fw4 telegram_blocked { "$mac" } 2>/dev/null
    fi

    # Also kick from Wi-Fi immediately
    for iface in $(iw dev 2>/dev/null | awk '/Interface/{print $2}'); do
        hostapd_cli -i "$iface" deauthenticate "$mac" 2>/dev/null || true
    done

    # Persist in UCI
    config_add_list "blocked" "$mac"

    local hostname
    hostname=$(_devices_hostname "$mac")
    telegram_send "$chat_id" "🚫 Blocked *${hostname}* (\`${mac}\`). Device cannot reconnect."
    log_info "devices: blocked $mac ($hostname)"
}

# Command: /unblock <mac>
devices_unblock() {
    local chat_id="$1"
    local target="$2"

    if [ -z "$target" ]; then
        telegram_send "$chat_id" "Usage: \`/unblock <MAC>\`"
        return
    fi

    local mac="$target"

    if command -v nft >/dev/null 2>&1; then
        nft delete element inet fw4 telegram_blocked { "$mac" } 2>/dev/null || true
    fi

    config_del_list "blocked" "$mac"

    telegram_send "$chat_id" "✅ Unblocked \`${mac}\`. Device can now reconnect."
    log_info "devices: unblocked $mac"
}

# Restore blocks from UCI on bot startup (call from bot.sh)
devices_restore_blocks() {
    command -v nft >/dev/null 2>&1 || return 0

    nft list set inet fw4 telegram_blocked 2>/dev/null || \
        nft add set inet fw4 telegram_blocked { type ether_addr \; } 2>/dev/null

    config_get_list "blocked" | while IFS= read -r mac; do
        [ -n "$mac" ] && nft add element inet fw4 telegram_blocked { "$mac" } 2>/dev/null || true
    done
    log_info "devices: restored blocked MACs from config"
}

# Router status for /status command
devices_status() {
    local chat_id="$1"
    local uptime cpu_load mem_total mem_free mem_used

    uptime=$(cat /proc/uptime 2>/dev/null | awk '{printf "%d days, %02d:%02d:%02d", $1/86400, ($1%86400)/3600, ($1%3600)/60, $1%60}')
    cpu_load=$(cat /proc/loadavg 2>/dev/null | awk '{print $1, $2, $3}')
    mem_total=$(awk '/MemTotal/{print $2}' /proc/meminfo 2>/dev/null)
    mem_free=$(awk '/MemAvailable/{print $2}' /proc/meminfo 2>/dev/null)
    mem_used=$(( (mem_total - mem_free) / 1024 ))
    mem_total=$(( mem_total / 1024 ))

    local device_count
    device_count=$(wc -l < "$LEASES_FILE" 2>/dev/null | tr -d ' ')

    telegram_send "$chat_id" "$(printf '*Router Status*\n\n*Uptime:* %s\n*Load:* %s\n*Memory:* %s/%s MB\n*Connected devices:* %s' \
        "$uptime" "$cpu_load" "$mem_used" "$mem_total" "${device_count:-0}")"
}

# ---- helpers ----

# Resolve MAC or IP to MAC address
_devices_resolve_mac() {
    local target="$1"
    # Already a MAC (contains colons with hex pairs)
    if echo "$target" | grep -qE '^([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}$'; then
        echo "$target" | tr 'A-Z' 'a-z'
        return
    fi
    # Treat as IP — look up in leases
    awk -v ip="$target" '$3==ip{print $2}' "$LEASES_FILE" 2>/dev/null | tr 'A-Z' 'a-z' | head -1
}

_devices_hostname() {
    local mac="$1"
    local name
    name=$(awk -v m="$mac" 'tolower($2)==tolower(m){print $4}' "$LEASES_FILE" 2>/dev/null | head -1)
    [ -z "$name" ] || [ "$name" = "*" ] && name="Unknown"
    echo "$name"
}
