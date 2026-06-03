#!/bin/sh

: "${LEASES_FILE:=/tmp/dhcp.leases}"

device_identity_hostname() {
    device_identity_mac="$1"
    device_identity_name=$(_device_identity_static_name "$device_identity_mac")
    if [ -n "$device_identity_name" ]; then
        device_identity_escape_html "$device_identity_name"
        return
    fi

    device_identity_name=$(awk -v m="$device_identity_mac" 'tolower($2)==tolower(m){print $4}' "$LEASES_FILE" 2>/dev/null | head -1)
    if [ -z "$device_identity_name" ] || [ "$device_identity_name" = "*" ]; then
        device_identity_name="Unknown"
    fi

    device_identity_escape_html "$device_identity_name"
}

device_identity_set_static_name() {
    device_identity_mac=$(_device_identity_normalize_mac "$1")
    device_identity_name="$2"
    device_identity_section=$(_device_identity_find_static_section "$device_identity_mac")

    command -v uci >/dev/null 2>&1 || return 1

    if [ -z "$device_identity_section" ]; then
        device_identity_section=$(uci add dhcp host 2>/dev/null) || return 1
    fi

    [ -n "$device_identity_section" ] || return 1

    uci set "dhcp.${device_identity_section}.mac=${device_identity_mac}" >/dev/null 2>&1 || return 1
    uci set "dhcp.${device_identity_section}.name=${device_identity_name}" >/dev/null 2>&1 || return 1
    uci commit dhcp >/dev/null 2>&1 || return 1
    /etc/init.d/dnsmasq reload >/dev/null 2>&1 || true
}

_device_identity_static_name() {
    device_identity_mac="$1"
    device_identity_section=$(_device_identity_find_static_section "$device_identity_mac")

    [ -n "$device_identity_section" ] || return 1

    uci -q get "dhcp.${device_identity_section}.name"
}

_device_identity_find_static_section() {
    device_identity_lookup_mac=$(_device_identity_normalize_mac "$1")
    device_identity_sections=""

    command -v uci >/dev/null 2>&1 || return 1

    device_identity_sections=$(uci -q show dhcp | awk -F'[.=]' '/=host$/{print $2}')

    while IFS= read -r device_identity_section; do
        [ -n "$device_identity_section" ] || continue
        device_identity_current_mac=$(uci -q get "dhcp.${device_identity_section}.mac" 2>/dev/null)
        if [ "$(_device_identity_normalize_mac "$device_identity_current_mac")" = "$device_identity_lookup_mac" ]; then
            printf '%s\n' "$device_identity_section"
            return 0
        fi
    done <<EOF
$device_identity_sections
EOF

    return 1
}

_device_identity_normalize_mac() {
    printf '%s\n' "$1" | tr 'A-Z' 'a-z'
}

device_identity_escape_html() {
    printf '%s\n' "$1" | awk '
        {
            gsub(/&/, "\\&amp;")
            gsub(/</, "\\&lt;")
            gsub(/>/, "\\&gt;")
            printf "%s", $0
        }
    '
}
