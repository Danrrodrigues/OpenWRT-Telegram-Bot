#!/bin/sh

set -u

ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)

. "$ROOT_DIR/src/core/device_identity.sh"
. "$ROOT_DIR/src/modules/devices.sh"

TEST_TMP="${TMPDIR:-/tmp}/telegram-bot-devices-test-$$"
LEASES_FILE="$TEST_TMP/dhcp.leases"
MESSAGES_FILE="$TEST_TMP/messages"

mkdir -p "$TEST_TMP"
: > "$MESSAGES_FILE"

WIFI_MACS=""
WIFI_MAC_SSID=""
IW_INTERFACES=""
HOSTAPD_RESULT="OK"

# --- mocks ---

telegram_send() {
    printf '%s|%s\n' "$1" "$2" >> "$MESSAGES_FILE"
}

log_info() { :; }
config_add_list() { :; }
config_del_list() { :; }

uci() { return 1; }

device_identity_hostname() {
    case "$1" in
        aa:bb:cc:dd:ee:ff) printf 'Phone\n' ;;
        11:22:33:44:55:66) printf 'Laptop\n' ;;
        *) printf 'Unknown\n' ;;
    esac
}

_devices_wifi_mac_ssid() {
    printf '%s' "$WIFI_MAC_SSID"
}

_devices_wifi_macs() {
    printf '%s' "$WIFI_MACS"
}

iw() {
    [ "$1" = "dev" ] && [ "$#" -eq 1 ] && printf '%s\n' "$IW_INTERFACES"
}

hostapd_cli() {
    printf '%s\n' "$HOSTAPD_RESULT"
}

# --- helpers ---

reset_output() {
    : > "$MESSAGES_FILE"
}

write_leases() {
    cat > "$LEASES_FILE"
}

read_messages() {
    cat "$MESSAGES_FILE"
}

assert_contains() {
    local haystack="$1" needle="$2" description="$3"
    case "$haystack" in
        *"$needle"*) ;;
        *)
            printf 'FAIL: %s\nExpected to find: %s\n' "$description" "$needle" >&2
            return 1
            ;;
    esac
}

assert_not_contains() {
    local haystack="$1" needle="$2" description="$3"
    case "$haystack" in
        *"$needle"*)
            printf 'FAIL: %s\nDid not expect to find: %s\n' "$description" "$needle" >&2
            return 1
            ;;
        *) ;;
    esac
}

assert_equals() {
    local actual="$1" expected="$2" description="$3"
    if [ "$actual" != "$expected" ]; then
        printf 'FAIL: %s\nExpected: %s\nActual: %s\n' "$description" "$expected" "$actual" >&2
        return 1
    fi
}

run_test() {
    local name="$1"
    shift
    if "$@"; then
        printf 'PASS: %s\n' "$name"
    else
        FAILURES=$((FAILURES + 1))
    fi
}

# --- _devices_resolve_mac ---

test_resolve_mac_normalises_uppercase_to_lowercase() {
    result=$(_devices_resolve_mac "AA:BB:CC:DD:EE:FF")
    assert_equals "$result" "aa:bb:cc:dd:ee:ff" "uppercase MAC should be normalised to lowercase"
}

test_resolve_mac_passes_through_lowercase() {
    result=$(_devices_resolve_mac "aa:bb:cc:dd:ee:ff")
    assert_equals "$result" "aa:bb:cc:dd:ee:ff" "lowercase MAC should pass through unchanged"
}

test_resolve_mac_resolves_ip_from_leases() {
    write_leases <<'EOF'
1717420000 aa:bb:cc:dd:ee:ff 192.168.1.10 Phone *
EOF
    result=$(_devices_resolve_mac "192.168.1.10")
    assert_equals "$result" "aa:bb:cc:dd:ee:ff" "IP address should resolve to MAC via DHCP leases"
}

test_resolve_mac_returns_empty_for_unknown_ip() {
    write_leases <<'EOF'
1717420000 aa:bb:cc:dd:ee:ff 192.168.1.10 Phone *
EOF
    result=$(_devices_resolve_mac "10.0.0.99")
    assert_equals "$result" "" "IP not in leases should return empty string"
}

# --- devices_list ---

test_list_empty_leases_shows_no_devices_message() {
    write_leases <<'EOF'
EOF
    WIFI_MAC_SSID=""
    reset_output
    devices_list "123"
    messages=$(read_messages)
    assert_contains "$messages" "No devices found in DHCP leases" "empty leases should show no-devices message"
}

test_list_shows_network_devices_header() {
    write_leases <<'EOF'
1717420000 aa:bb:cc:dd:ee:ff 192.168.1.10 Phone *
EOF
    WIFI_MAC_SSID="aa:bb:cc:dd:ee:ff	HomeNetwork
"
    reset_output
    devices_list "123"
    messages=$(read_messages)
    assert_contains "$messages" "Network Devices" "output header should say Network Devices"
}

test_list_wifi_device_shows_ssid_name() {
    write_leases <<'EOF'
1717420000 aa:bb:cc:dd:ee:ff 192.168.1.10 Phone *
EOF
    WIFI_MAC_SSID="aa:bb:cc:dd:ee:ff	HomeNetwork
"
    reset_output
    devices_list "123"
    messages=$(read_messages)
    assert_contains "$messages" "📶 HomeNetwork" "WiFi device badge should show the SSID name" || return 1
    assert_not_contains "$messages" "🔌" "Wi-Fi device should not show wired/offline badge"
}

test_list_offline_device_shows_wired_offline_badge() {
    write_leases <<'EOF'
1717420000 aa:bb:cc:dd:ee:ff 192.168.1.10 Phone *
EOF
    WIFI_MAC_SSID=""
    reset_output
    devices_list "123"
    messages=$(read_messages)
    assert_contains "$messages" "🔌 Wired / Offline" "device not on Wi-Fi should show 🔌 badge" || return 1
    assert_not_contains "$messages" "📶" "offline device should not show Wi-Fi badge"
}

test_list_mixed_devices_show_correct_badges() {
    write_leases <<'EOF'
1717420000 aa:bb:cc:dd:ee:ff 192.168.1.10 Phone *
1717420001 11:22:33:44:55:66 192.168.1.20 Laptop *
EOF
    WIFI_MAC_SSID="aa:bb:cc:dd:ee:ff	HomeNetwork
"
    reset_output
    devices_list "123"
    messages=$(read_messages)
    assert_contains "$messages" "📶 HomeNetwork" "Wi-Fi device should show SSID badge" || return 1
    assert_contains "$messages" "🔌 Wired / Offline" "offline device should have 🔌 badge"
}

test_list_wifi_device_escapes_ssid_html() {
    write_leases <<'EOF'
1717420000 aa:bb:cc:dd:ee:ff 192.168.1.10 Phone *
EOF
    WIFI_MAC_SSID="aa:bb:cc:dd:ee:ff	AT&T <guest>
"
    reset_output
    devices_list "123"
    messages=$(read_messages)
    assert_contains "$messages" "AT&amp;T &lt;guest&gt;" "SSID with HTML metacharacters should be escaped in listing" || return 1
    assert_not_contains "$messages" "AT&T <guest>" "raw unescaped SSID should not appear in listing"
}

test_list_wifi_devices_appear_before_offline() {
    write_leases <<'EOF'
1717420000 11:22:33:44:55:66 192.168.1.20 Laptop *
1717420001 aa:bb:cc:dd:ee:ff 192.168.1.10 Phone *
EOF
    WIFI_MAC_SSID="aa:bb:cc:dd:ee:ff	HomeNetwork
"
    reset_output
    devices_list "123"
    messages=$(read_messages)
    assert_contains "$messages" "1.</b> Phone" "WiFi device should be listed first regardless of lease order" || return 1
    assert_contains "$messages" "2.</b> Laptop" "offline device should be listed second"
}

test_list_shows_ip_and_mac_for_each_device() {
    write_leases <<'EOF'
1717420000 aa:bb:cc:dd:ee:ff 192.168.1.10 Phone *
EOF
    WIFI_MACS=""
    reset_output
    devices_list "123"
    messages=$(read_messages)
    assert_contains "$messages" "192.168.1.10" "device IP should appear in listing" || return 1
    assert_contains "$messages" "aa:bb:cc:dd:ee:ff" "device MAC should appear in listing"
}

# --- devices_kick ---

test_kick_no_target_shows_usage() {
    reset_output
    devices_kick "123" ""
    messages=$(read_messages)
    assert_contains "$messages" "Usage:" "missing target should return usage message"
}

test_kick_unknown_ip_shows_not_found() {
    write_leases <<'EOF'
1717420000 aa:bb:cc:dd:ee:ff 192.168.1.10 Phone *
EOF
    WIFI_MACS=""
    reset_output
    devices_kick "123" "192.168.1.99"
    messages=$(read_messages)
    assert_contains "$messages" "Device not found" "IP not in leases should return not-found error"
}

test_kick_device_not_on_wifi_shows_warning() {
    write_leases <<'EOF'
1717420000 aa:bb:cc:dd:ee:ff 192.168.1.10 Phone *
EOF
    WIFI_MACS=""
    reset_output
    devices_kick "123" "aa:bb:cc:dd:ee:ff"
    messages=$(read_messages)
    assert_contains "$messages" "is not connected via Wi-Fi" "device not on Wi-Fi should show specific warning" || return 1
    assert_not_contains "$messages" "Kicked" "should not claim kick succeeded"
}

test_kick_device_by_ip_not_on_wifi_shows_warning() {
    write_leases <<'EOF'
1717420000 aa:bb:cc:dd:ee:ff 192.168.1.10 Phone *
EOF
    WIFI_MACS=""
    reset_output
    devices_kick "123" "192.168.1.10"
    messages=$(read_messages)
    assert_contains "$messages" "is not connected via Wi-Fi" "kicking by IP for offline device should warn not on Wi-Fi"
}

test_kick_wifi_device_deauths_successfully() {
    write_leases <<'EOF'
1717420000 aa:bb:cc:dd:ee:ff 192.168.1.10 Phone *
EOF
    WIFI_MACS="aa:bb:cc:dd:ee:ff
"
    IW_INTERFACES="Interface wlan0"
    HOSTAPD_RESULT="OK"
    reset_output
    devices_kick "123" "aa:bb:cc:dd:ee:ff"
    messages=$(read_messages)
    assert_contains "$messages" "Kicked" "successful deauth should confirm kick" || return 1
    assert_contains "$messages" "aa:bb:cc:dd:ee:ff" "success message should include the kicked MAC"
}

test_kick_wifi_device_deauth_failure_shows_warning() {
    write_leases <<'EOF'
1717420000 aa:bb:cc:dd:ee:ff 192.168.1.10 Phone *
EOF
    WIFI_MACS="aa:bb:cc:dd:ee:ff
"
    IW_INTERFACES="Interface wlan0"
    HOSTAPD_RESULT="FAIL"
    reset_output
    devices_kick "123" "aa:bb:cc:dd:ee:ff"
    messages=$(read_messages)
    assert_contains "$messages" "Could not kick" "failed deauth should show could-not-kick warning"
}

# --- run ---

FAILURES=0

run_test "resolve MAC: normalises uppercase to lowercase"   test_resolve_mac_normalises_uppercase_to_lowercase
run_test "resolve MAC: passes through lowercase unchanged"  test_resolve_mac_passes_through_lowercase
run_test "resolve MAC: resolves IP to MAC from leases"      test_resolve_mac_resolves_ip_from_leases
run_test "resolve MAC: returns empty for unknown IP"        test_resolve_mac_returns_empty_for_unknown_ip

run_test "list: empty leases shows no-devices message"                 test_list_empty_leases_shows_no_devices_message
run_test "list: header says Network Devices"                           test_list_shows_network_devices_header
run_test "list: Wi-Fi device shows SSID name in badge"                 test_list_wifi_device_shows_ssid_name
run_test "list: offline device shows 🔌 badge"                        test_list_offline_device_shows_wired_offline_badge
run_test "list: mixed devices show correct badges"                     test_list_mixed_devices_show_correct_badges
run_test "list: SSID HTML metacharacters are escaped"                  test_list_wifi_device_escapes_ssid_html
run_test "list: WiFi devices appear before offline"                    test_list_wifi_devices_appear_before_offline
run_test "list: shows IP and MAC for each device"                      test_list_shows_ip_and_mac_for_each_device

run_test "kick: missing target shows usage"                 test_kick_no_target_shows_usage
run_test "kick: unknown IP shows not-found error"           test_kick_unknown_ip_shows_not_found
run_test "kick: offline device warns not on Wi-Fi"          test_kick_device_not_on_wifi_shows_warning
run_test "kick: kicking by IP for offline device warns"     test_kick_device_by_ip_not_on_wifi_shows_warning
run_test "kick: Wi-Fi device deauths successfully"          test_kick_wifi_device_deauths_successfully
run_test "kick: deauth failure shows could-not-kick"        test_kick_wifi_device_deauth_failure_shows_warning

rm -rf "$TEST_TMP"

if [ "$FAILURES" -ne 0 ]; then
    exit 1
fi
