#!/bin/sh

set -u

ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)

. "$ROOT_DIR/src/core/device_identity.sh"
. "$ROOT_DIR/src/modules/monitor.sh"

TEST_TMP="${TMPDIR:-/tmp}/telegram-bot-monitor-test-$$"
LEASES_FILE="$TEST_TMP/dhcp.leases"
KNOWN_DEVICES_FILE="$TEST_TMP/known-devices"
_SEEN_EVER_FILE="$TEST_TMP/seen-devices"
CONFIG_WRITES_FILE="$TEST_TMP/config-writes"

mkdir -p "$TEST_TMP"
: > "$CONFIG_WRITES_FILE"

MESSAGES=""
CONFIG_WRITES=""
CURRENT_MACS=""

telegram_send() {
    local chat_id="$1"
    local text="$2"
    MESSAGES="${MESSAGES}${chat_id}|${text}
"
}

log_info() {
    :
}

config_set() {
    local key="$1"
    local value="$2"
    CONFIG_WRITES="${CONFIG_WRITES}${key}=${value}
"
    printf '%s=%s\n' "$key" "$value" >> "$CONFIG_WRITES_FILE"
}

_monitor_current_macs() {
    printf '%s' "$CURRENT_MACS"
}

reset_messages() {
    MESSAGES=""
}

assert_contains() {
    local haystack="$1"
    local needle="$2"
    local description="$3"

    case "$haystack" in
        *"$needle"*) ;;
        *)
            printf 'FAIL: %s\nExpected to find: %s\n' "$description" "$needle" >&2
            return 1
            ;;
    esac
}

assert_not_contains() {
    local haystack="$1"
    local needle="$2"
    local description="$3"

    case "$haystack" in
        *"$needle"*)
            printf 'FAIL: %s\nDid not expect to find: %s\n' "$description" "$needle" >&2
            return 1
            ;;
        *) ;;
    esac
}

assert_equals() {
    local actual="$1"
    local expected="$2"
    local description="$3"

    if [ "$actual" != "$expected" ]; then
        printf 'FAIL: %s\nExpected: %s\nActual: %s\n' "$description" "$expected" "$actual" >&2
        return 1
    fi
}

write_leases() {
    cat > "$LEASES_FILE"
}

set_current_macs() {
    CURRENT_MACS="$1"
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

test_unknown_mode_alerts_only_first_seen() {
    rm -f "$LEASES_FILE" "$KNOWN_DEVICES_FILE" "$_SEEN_EVER_FILE"
    monitor_init

    write_leases <<'EOF'
1717420000 aa:bb:cc:dd:ee:ff 192.168.1.10 Phone *
EOF
    set_current_macs "aa:bb:cc:dd:ee:ff
"
    BOT_ALERT_MODE="unknown"
    reset_messages
    monitor_check "123"
    assert_contains "$MESSAGES" "aa:bb:cc:dd:ee:ff" "unknown mode should alert for first sighting" || return 1

    write_leases <<'EOF'
EOF
    set_current_macs ""
    monitor_check "123" >/dev/null 2>&1

    write_leases <<'EOF'
1717420300 aa:bb:cc:dd:ee:ff 192.168.1.10 Phone *
EOF
    set_current_macs "aa:bb:cc:dd:ee:ff
"
    reset_messages
    monitor_check "123"
    assert_equals "$MESSAGES" "" "unknown mode should stay quiet for known reconnection"
}

test_known_mode_alerts_only_reconnections() {
    rm -f "$LEASES_FILE" "$KNOWN_DEVICES_FILE" "$_SEEN_EVER_FILE"
    printf 'aa:bb:cc:dd:ee:ff\n' > "$_SEEN_EVER_FILE"
    monitor_init

    write_leases <<'EOF'
1717420300 aa:bb:cc:dd:ee:ff 192.168.1.10 Phone *
EOF
    set_current_macs "aa:bb:cc:dd:ee:ff
"
    BOT_ALERT_MODE="known"
    reset_messages
    monitor_check "123"
    assert_contains "$MESSAGES" "aa:bb:cc:dd:ee:ff" "known mode should alert when a known device reconnects"
}

test_all_mode_alerts_unknown_and_known_reconnections() {
    rm -f "$LEASES_FILE" "$KNOWN_DEVICES_FILE" "$_SEEN_EVER_FILE"
    monitor_init

    write_leases <<'EOF'
1717420000 aa:bb:cc:dd:ee:ff 192.168.1.10 Phone *
EOF
    set_current_macs "aa:bb:cc:dd:ee:ff
"
    BOT_ALERT_MODE="all"
    reset_messages
    monitor_check "123"
    assert_contains "$MESSAGES" "aa:bb:cc:dd:ee:ff" "all mode should alert on first connection" || return 1

    write_leases <<'EOF'
EOF
    set_current_macs ""
    monitor_check "123" >/dev/null 2>&1

    write_leases <<'EOF'
1717420300 aa:bb:cc:dd:ee:ff 192.168.1.10 Phone *
EOF
    set_current_macs "aa:bb:cc:dd:ee:ff
"
    reset_messages
    monitor_check "123"
    assert_contains "$MESSAGES" "aa:bb:cc:dd:ee:ff" "all mode should alert on known reconnection"
}

test_off_mode_stays_quiet() {
    rm -f "$LEASES_FILE" "$KNOWN_DEVICES_FILE" "$_SEEN_EVER_FILE"
    monitor_init

    write_leases <<'EOF'
1717420000 aa:bb:cc:dd:ee:ff 192.168.1.10 Phone *
EOF
    set_current_macs "aa:bb:cc:dd:ee:ff
"
    BOT_ALERT_MODE="off"
    reset_messages
    monitor_check "123"
    assert_equals "$MESSAGES" "" "off mode should never alert"
}

test_all_mode_alerts_reconnect_even_if_lease_never_disappears() {
    rm -f "$LEASES_FILE" "$KNOWN_DEVICES_FILE" "$_SEEN_EVER_FILE"
    monitor_init

    write_leases <<'EOF'
1717420000 aa:bb:cc:dd:ee:ff 192.168.1.10 Laptop *
EOF
    BOT_ALERT_MODE="all"
    set_current_macs "aa:bb:cc:dd:ee:ff
"
    reset_messages
    monitor_check "123"
    assert_contains "$MESSAGES" "aa:bb:cc:dd:ee:ff" "all mode should alert on first active presence" || return 1

    set_current_macs ""
    monitor_check "123" >/dev/null 2>&1

    set_current_macs "aa:bb:cc:dd:ee:ff
"
    reset_messages
    monitor_check "123"
    assert_contains "$MESSAGES" "aa:bb:cc:dd:ee:ff" "all mode should alert on active reconnection even if lease persists"
}

test_alerts_command_accepts_new_modes_and_on_maps_to_all() {
    BOT_ALERT_MODE="off"
    reset_messages
    monitor_alerts_toggle "123" "known"
    assert_equals "$BOT_ALERT_MODE" "known" "/alerts known should update runtime mode" || return 1
    assert_contains "$CONFIG_WRITES" "alert_mode=known" "/alerts known should persist config" || return 1
    assert_contains "$MESSAGES" "known" "/alerts known should confirm selected mode" || return 1

    reset_messages
    monitor_alerts_toggle "123" "on"
    assert_equals "$BOT_ALERT_MODE" "all" "/alerts on should map to all" || return 1
    assert_contains "$CONFIG_WRITES" "alert_mode=all" "/alerts on should persist all mode"
}

FAILURES=0

run_test "unknown mode first sighting only" test_unknown_mode_alerts_only_first_seen
run_test "known mode alerts reconnections" test_known_mode_alerts_only_reconnections
run_test "all mode alerts both first and reconnect" test_all_mode_alerts_unknown_and_known_reconnections
run_test "all mode handles reconnect without lease drop" test_all_mode_alerts_reconnect_even_if_lease_never_disappears
run_test "off mode suppresses alerts" test_off_mode_stays_quiet
run_test "alerts command supports mode values" test_alerts_command_accepts_new_modes_and_on_maps_to_all

rm -rf "$TEST_TMP"

if [ "$FAILURES" -ne 0 ]; then
    exit 1
fi
