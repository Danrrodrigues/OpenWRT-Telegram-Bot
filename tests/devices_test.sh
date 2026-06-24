#!/bin/sh

set -u

ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)

. "$ROOT_DIR/src/core/device_identity.sh"
. "$ROOT_DIR/src/modules/devices.sh"

TEST_TMP="${TMPDIR:-/tmp}/telegram-bot-devices-test-$$"
LEASES_FILE="$TEST_TMP/dhcp.leases"
MESSAGES_FILE="$TEST_TMP/messages"
ETHERWAKE_CALLS_FILE="$TEST_TMP/etherwake-calls"

mkdir -p "$TEST_TMP"
: > "$MESSAGES_FILE"
: > "$ETHERWAKE_CALLS_FILE"

WIFI_MACS=""
WIFI_MAC_SSID=""
IW_INTERFACES=""
HOSTAPD_RESULT="OK"
ETHERWAKE_RC=0
BLOCKED_MACS=""

T_BTN_CANCEL="Cancel"

# --- mocks ---

telegram_send() {
    printf '%s|%s\n' "$1" "$2" >> "$MESSAGES_FILE"
}

telegram_send_keyboard() {
    local chat_id="$1"
    local text="$2"
    shift 2
    printf '%s|%s|%s\n' "$chat_id" "$text" "$*" >> "$MESSAGES_FILE"
}

log_info() { :; }
config_add_list() { :; }
config_del_list() { :; }
config_get_list() { printf '%s' "$BLOCKED_MACS"; }

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

install_etherwake_mock() {
    eval 'etherwake() {
        printf "%s\n" "$*" >> "$ETHERWAKE_CALLS_FILE"
        return "$ETHERWAKE_RC"
    }'
}

uninstall_etherwake_mock() {
    unset -f etherwake 2>/dev/null || true
}

# --- helpers ---

reset_output() {
    : > "$MESSAGES_FILE"
    : > "$ETHERWAKE_CALLS_FILE"
    ETHERWAKE_RC=0
}

write_leases() {
    cat > "$LEASES_FILE"
}

read_messages() {
    cat "$MESSAGES_FILE"
}

read_etherwake_calls() {
    cat "$ETHERWAKE_CALLS_FILE"
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

test_kick_no_target_shows_device_picker() {
    write_leases <<'EOF'
1717420000 aa:bb:cc:dd:ee:ff 192.168.1.10 Phone *
EOF
    reset_output
    devices_kick "123" ""
    messages=$(read_messages)
    assert_contains "$messages" "kick:aa:bb:cc:dd:ee:ff" "missing target should offer a device picker keyboard"
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

# --- devices_wake ---

test_wake_no_target_shows_device_picker() {
    write_leases <<'EOF'
1717420000 aa:bb:cc:dd:ee:ff 192.168.1.10 Phone *
EOF
    reset_output
    uninstall_etherwake_mock
    devices_wake "123" ""
    messages=$(read_messages)
    assert_contains "$messages" "wake:aa:bb:cc:dd:ee:ff" "missing target should offer a device picker keyboard"
}

test_wake_unknown_ip_shows_not_found() {
    write_leases <<'EOF'
1717420000 aa:bb:cc:dd:ee:ff 192.168.1.10 Phone *
EOF
    reset_output
    uninstall_etherwake_mock
    devices_wake "123" "192.168.1.99"
    messages=$(read_messages)
    assert_contains "$messages" "Device not found" "unknown wake target should return not-found error"
}

test_wake_missing_etherwake_shows_install_hint() {
    write_leases <<'EOF'
1717420000 aa:bb:cc:dd:ee:ff 192.168.1.10 Phone *
EOF
    reset_output
    uninstall_etherwake_mock
    devices_wake "123" "aa:bb:cc:dd:ee:ff"
    messages=$(read_messages)
    assert_contains "$messages" "etherwake is not installed" "missing etherwake should explain the missing package" || return 1
    assert_contains "$messages" "opkg update &amp;&amp; opkg install etherwake" "missing etherwake should include install command"
}

test_wake_by_mac_sends_packet_on_br_lan() {
    write_leases <<'EOF'
1717420000 aa:bb:cc:dd:ee:ff 192.168.1.10 Phone *
EOF
    reset_output
    install_etherwake_mock
    devices_wake "123" "AA:BB:CC:DD:EE:FF"
    calls=$(read_etherwake_calls)
    messages=$(read_messages)
    assert_contains "$calls" "-i br-lan aa:bb:cc:dd:ee:ff" "wake should call etherwake on br-lan with normalized MAC" || return 1
    assert_contains "$messages" "Wake packet sent to <b>Phone</b> (<code>aa:bb:cc:dd:ee:ff</code>)" "successful wake should confirm hostname and MAC"
}

test_wake_by_ip_resolves_mac_before_sending() {
    write_leases <<'EOF'
1717420000 aa:bb:cc:dd:ee:ff 192.168.1.10 Phone *
EOF
    reset_output
    install_etherwake_mock
    devices_wake "123" "192.168.1.10"
    calls=$(read_etherwake_calls)
    assert_contains "$calls" "-i br-lan aa:bb:cc:dd:ee:ff" "wake by IP should resolve MAC from DHCP leases before sending"
}

test_wake_etherwake_failure_shows_error() {
    write_leases <<'EOF'
1717420000 aa:bb:cc:dd:ee:ff 192.168.1.10 Phone *
EOF
    reset_output
    install_etherwake_mock
    # shellcheck disable=SC2034
    ETHERWAKE_RC=1
    devices_wake "123" "aa:bb:cc:dd:ee:ff"
    messages=$(read_messages)
    assert_contains "$messages" "Could not send wake packet" "etherwake failure should show friendly error" || return 1
    assert_not_contains "$messages" "Wake packet sent" "etherwake failure should not claim success"
}

# --- devices_block / devices_unblock ---

test_block_no_target_shows_device_picker() {
    write_leases <<'EOF'
1717420000 aa:bb:cc:dd:ee:ff 192.168.1.10 Phone *
EOF
    reset_output
    devices_block "123" ""
    messages=$(read_messages)
    assert_contains "$messages" "block:aa:bb:cc:dd:ee:ff" "missing target should offer a device picker keyboard"
}

test_unblock_no_target_shows_blocked_picker() {
    BLOCKED_MACS="aa:bb:cc:dd:ee:ff"
    reset_output
    devices_unblock "123" ""
    messages=$(read_messages)
    assert_contains "$messages" "unblock:aa:bb:cc:dd:ee:ff" "missing target should offer a picker of currently blocked devices"
}

test_unblock_no_target_no_blocked_devices() {
    BLOCKED_MACS=""
    reset_output
    devices_unblock "123" ""
    messages=$(read_messages)
    assert_contains "$messages" "No blocked devices" "no blocked devices should say so instead of an empty keyboard"
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

run_test "kick: missing target shows device picker"         test_kick_no_target_shows_device_picker
run_test "kick: unknown IP shows not-found error"           test_kick_unknown_ip_shows_not_found
run_test "kick: offline device warns not on Wi-Fi"          test_kick_device_not_on_wifi_shows_warning
run_test "kick: kicking by IP for offline device warns"     test_kick_device_by_ip_not_on_wifi_shows_warning
run_test "kick: Wi-Fi device deauths successfully"          test_kick_wifi_device_deauths_successfully
run_test "kick: deauth failure shows could-not-kick"        test_kick_wifi_device_deauth_failure_shows_warning

run_test "wake: missing target shows device picker"         test_wake_no_target_shows_device_picker
run_test "wake: unknown IP shows not-found error"           test_wake_unknown_ip_shows_not_found
run_test "wake: missing etherwake shows install hint"       test_wake_missing_etherwake_shows_install_hint
run_test "wake: MAC sends packet on br-lan"                 test_wake_by_mac_sends_packet_on_br_lan
run_test "wake: IP resolves MAC before sending"             test_wake_by_ip_resolves_mac_before_sending
run_test "wake: etherwake failure shows error"              test_wake_etherwake_failure_shows_error

run_test "block: missing target shows device picker"        test_block_no_target_shows_device_picker
run_test "unblock: missing target shows blocked picker"     test_unblock_no_target_shows_blocked_picker
run_test "unblock: missing target, none blocked"            test_unblock_no_target_no_blocked_devices

rm -rf "$TEST_TMP"

if [ "$FAILURES" -ne 0 ]; then
    exit 1
fi
