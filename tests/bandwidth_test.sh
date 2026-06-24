#!/bin/sh

set -u

ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)

TEST_TMP="${TMPDIR:-/tmp}/telegram-bot-bandwidth-test-$$"
LEASES_FILE="$TEST_TMP/dhcp.leases"

mkdir -p "$TEST_TMP"

MESSAGES=""

telegram_send() {
    MESSAGES="${MESSAGES}${1}|${2}
"
}

telegram_send_keyboard() {
    local chat_id="$1"
    local text="$2"
    shift 2
    MESSAGES="${MESSAGES}${chat_id}|${text}|$*
"
}

T_BTN_CANCEL="Cancel"

log_info() { :; }
config_get_list() { :; }
config_add_list() { :; }
config_del_list() { :; }

. "$ROOT_DIR/src/modules/bandwidth.sh"

# ---- assertions ----

assert_contains() {
    case "$1" in
        *"$2"*) ;;
        *) printf 'FAIL: %s\nExpected to find: %s\nIn: %s\n' "$3" "$2" "$1" >&2; return 1 ;;
    esac
}

assert_equals() {
    if [ "$1" != "$2" ]; then
        printf 'FAIL: %s\nExpected: %s\nActual: %s\n' "$3" "$2" "$1" >&2
        return 1
    fi
}

FAILURES=0

run_test() {
    local name="$1"
    shift
    MESSAGES=""
    if "$@"; then
        printf 'PASS: %s\n' "$name"
    else
        FAILURES=$((FAILURES + 1))
    fi
}

write_leases() {
    cat > "$LEASES_FILE"
}

# ---- /limit picker ----

test_limit_no_target_shows_device_picker() {
    write_leases <<'EOF'
1717420000 aa:bb:cc:dd:ee:ff 192.168.1.10 Phone *
EOF
    bandwidth_limit "123" "" "" ""
    assert_contains "$MESSAGES" "limitpick:aa:bb:cc:dd:ee:ff" "missing target should offer a device picker keyboard"
}

test_limit_no_target_no_devices() {
    write_leases <<'EOF'
EOF
    bandwidth_limit "123" "" "" ""
    assert_contains "$MESSAGES" "No devices found in DHCP leases" "no leases should report no devices instead of an empty keyboard"
}

test_limit_with_target_but_missing_speeds_shows_usage() {
    write_leases <<'EOF'
1717420000 aa:bb:cc:dd:ee:ff 192.168.1.10 Phone *
EOF
    bandwidth_limit "123" "aa:bb:cc:dd:ee:ff" "" ""
    assert_contains "$MESSAGES" "Usage:" "explicit target with missing speeds should still show usage, not a picker"
}

# ---- run all ----

run_test "limit: missing target shows device picker"          test_limit_no_target_shows_device_picker
run_test "limit: missing target, no devices"                  test_limit_no_target_no_devices
run_test "limit: target given but speeds missing shows usage" test_limit_with_target_but_missing_speeds_shows_usage

rm -rf "$TEST_TMP"

if [ "$FAILURES" -ne 0 ]; then
    exit 1
fi
