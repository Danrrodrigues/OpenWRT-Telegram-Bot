#!/bin/sh
# Speed limiting — uses nft-qos (preferred) or tc (iproute2 fallback)
# shellcheck source=../core/config.sh
# shellcheck source=../core/logger.sh
# shellcheck source=../core/telegram.sh

LEASES_FILE="/tmp/dhcp.leases"

# Command: /limit <mac> <down_mbps> <up_mbps>
bandwidth_limit() {
    local chat_id="$1"
    local target="$2"
    local down_mbps="$3"
    local up_mbps="$4"
    local mac ip down_kbps up_kbps hostname

    if [ -z "$target" ] || [ -z "$down_mbps" ] || [ -z "$up_mbps" ]; then
        telegram_send "$chat_id" "Usage: <code>/limit &lt;MAC&gt; &lt;down Mbps&gt; &lt;up Mbps&gt;</code>
Example: <code>/limit AA:BB:CC:DD:EE:FF 10 5</code>"
        return
    fi

    case "$down_mbps$up_mbps" in
        *[!0-9]*)
            telegram_send "$chat_id" "❌ Speed values must be integers (Mbps)."
            return
            ;;
    esac

    mac=$(_bw_resolve_mac "$target")
    if [ -z "$mac" ]; then
        telegram_send "$chat_id" "❌ Device not found: <code>${target}</code>
Make sure the device is connected and try its MAC address."
        return
    fi

    ip=$(_bw_resolve_ip "$mac")
    if [ -z "$ip" ]; then
        telegram_send "$chat_id" "❌ Cannot resolve IP for <code>${mac}</code>. Device may not have a DHCP lease."
        return
    fi

    down_kbps=$(( down_mbps * 1000 ))
    up_kbps=$(( up_mbps * 1000 ))

    if _bw_has_nftqos; then
        _bw_limit_nftqos "$ip" "$down_kbps" "$up_kbps"
    else
        _bw_limit_tc "$ip" "$down_kbps" "$up_kbps"
    fi

    config_del_list "limited" "$(config_get_list "limited" | grep "^${mac}:")"
    config_add_list "limited" "${mac}:${down_kbps}:${up_kbps}"

    hostname=$(_bw_hostname "$mac")
    telegram_send "$chat_id" "$(printf '✅ Speed limit set for <b>%s</b>\n\n⬇️ Download: <b>%s Mbps</b>\n⬆️ Upload: <b>%s Mbps</b>' \
        "$hostname" "$down_mbps" "$up_mbps")"
    log_info "bandwidth: limited $mac ($hostname) down=${down_mbps}M up=${up_mbps}M"
}

# Command: /unlimit <mac>
bandwidth_unlimit() {
    local chat_id="$1"
    local target="$2"
    local mac ip hostname

    if [ -z "$target" ]; then
        telegram_send "$chat_id" "Usage: <code>/unlimit &lt;MAC or IP&gt;</code>"
        return
    fi

    mac=$(_bw_resolve_mac "$target")
    if [ -z "$mac" ]; then
        telegram_send "$chat_id" "❌ Device not found: <code>${target}</code>"
        return
    fi

    ip=$(_bw_resolve_ip "$mac")

    if [ -n "$ip" ]; then
        if _bw_has_nftqos; then
            _bw_unlimit_nftqos "$ip"
        else
            _bw_unlimit_tc "$ip"
        fi
    fi

    config_del_list "limited" "$(config_get_list "limited" | grep "^${mac}:")"

    hostname=$(_bw_hostname "$mac")
    telegram_send "$chat_id" "✅ Speed limit removed for <b>${hostname}</b> (<code>${mac}</code>)."
    log_info "bandwidth: removed limit for $mac"
}

# Restore limits from UCI on bot startup
bandwidth_restore_limits() {
    local ip
    config_get_list "limited" | while IFS=: read -r mac down_kbps up_kbps; do
        [ -z "$mac" ] && continue
        ip=$(_bw_resolve_ip "$mac")
        [ -z "$ip" ] && continue
        if _bw_has_nftqos; then
            _bw_limit_nftqos "$ip" "$down_kbps" "$up_kbps"
        else
            _bw_limit_tc "$ip" "$down_kbps" "$up_kbps"
        fi
        log_info "bandwidth: restored limit for $mac"
    done
}

# ---- nft-qos backend ----

_bw_has_nftqos() {
    command -v nft-qos >/dev/null 2>&1 || \
        { command -v opkg >/dev/null 2>&1 && opkg list-installed 2>/dev/null | grep -q "^nft-qos "; }
}

_bw_limit_nftqos() {
    local ip="$1" down_kbps="$2" up_kbps="$3"
    nft-qos dynamic add ip "$ip" download "${down_kbps}kbps" upload "${up_kbps}kbps" 2>/dev/null
}

_bw_unlimit_nftqos() {
    local ip="$1"
    nft-qos dynamic remove ip "$ip" 2>/dev/null || true
}

# ---- tc (iproute2) backend ----

_bw_limit_tc() {
    local ip="$1" down_kbps="$2" up_kbps="$3"
    local iface handle
    iface=$(ip route show default 2>/dev/null | awk '/default/{print $5}' | head -1)
    [ -z "$iface" ] && iface="br-lan"

    _bw_unlimit_tc "$ip"

    if ip link show ifb0 >/dev/null 2>&1 || ip link add ifb0 type ifb 2>/dev/null; then
        ip link set ifb0 up 2>/dev/null
        tc qdisc add dev "$iface" ingress 2>/dev/null || true
        handle=$(echo "$ip" | awk -F. '{printf "1:%d", $4}')
        tc filter add dev "$iface" parent ffff: protocol ip u32 \
            match ip dst "$ip/32" \
            action mirred egress redirect dev ifb0 2>/dev/null || true
        tc qdisc add dev ifb0 root handle 1: htb default 99 2>/dev/null || true
        tc class add dev ifb0 parent 1: classid "$handle" htb \
            rate "${down_kbps}kbit" ceil "${down_kbps}kbit" 2>/dev/null || true
        tc filter add dev ifb0 protocol ip parent 1: u32 \
            match ip dst "$ip/32" flowid "$handle" 2>/dev/null || true
    fi

    tc qdisc add dev "$iface" root handle 1: htb default 99 2>/dev/null || true
    handle=$(echo "$ip" | awk -F. '{printf "1:%d", $4}')
    tc class add dev "$iface" parent 1: classid "$handle" htb \
        rate "${up_kbps}kbit" ceil "${up_kbps}kbit" 2>/dev/null || true
    tc filter add dev "$iface" protocol ip parent 1: u32 \
        match ip src "$ip/32" flowid "$handle" 2>/dev/null || true
}

_bw_unlimit_tc() {
    local ip="$1"
    local iface handle
    iface=$(ip route show default 2>/dev/null | awk '/default/{print $5}' | head -1)
    [ -z "$iface" ] && iface="br-lan"

    handle=$(echo "$ip" | awk -F. '{printf "1:%d", $4}')
    tc filter del dev "$iface" parent 1: 2>/dev/null || true
    tc class del dev "$iface" classid "$handle" 2>/dev/null || true
    tc filter del dev ifb0 parent 1: 2>/dev/null || true
    tc class del dev ifb0 classid "$handle" 2>/dev/null || true
}

# ---- helpers ----

_bw_resolve_mac() {
    local target="$1"
    if echo "$target" | grep -qE '^([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}$'; then
        echo "$target" | tr 'A-Z' 'a-z'
        return
    fi
    awk -v ip="$target" '$3==ip{print $2}' "$LEASES_FILE" 2>/dev/null | tr 'A-Z' 'a-z' | head -1
}

_bw_resolve_ip() {
    local mac="$1"
    awk -v m="$mac" 'tolower($2)==tolower(m){print $3}' "$LEASES_FILE" 2>/dev/null | head -1
}

_bw_hostname() {
    local mac="$1"
    local name
    name=$(awk -v m="$mac" 'tolower($2)==tolower(m){print $4}' "$LEASES_FILE" 2>/dev/null | head -1)
    [ -z "$name" ] || [ "$name" = "*" ] && name="$mac"
    echo "$name"
}
