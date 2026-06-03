#!/bin/sh

set -u

ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)
. "$ROOT_DIR/src/core/device_identity.sh"

TEST_TMP="${TMPDIR:-/tmp}/telegram-bot-device-identity-test-$$"
LEASES_FILE="$TEST_TMP/dhcp.leases"
KNOWN_DEVICES_FILE="$TEST_TMP/known-devices"
_SEEN_EVER_FILE="$TEST_TMP/seen-devices"
UCI_DB_FILE="$TEST_TMP/uci-db"
EMPTY_BIN_DIR="$TEST_TMP/empty-bin"
TEST_SHELL=$(command -v sh)
MESSAGES=""

mkdir -p "$TEST_TMP"
mkdir -p "$EMPTY_BIN_DIR"

write_leases() {
    cat > "$LEASES_FILE"
}

write_uci_db() {
    cat > "$UCI_DB_FILE"
}

create_tool_wrapper() {
    tool_name="$1"
    tool_path=$(command -v "$tool_name")

    cat > "$EMPTY_BIN_DIR/$tool_name" <<EOF
#!/bin/sh
exec "$tool_path" "\$@"
EOF
    chmod +x "$EMPTY_BIN_DIR/$tool_name"
}

uci() {
    if [ "$1" = "-q" ] && [ "$2" = "show" ] && [ "$3" = "dhcp" ]; then
        awk -F'|' '{print "dhcp." $1 "=host"}' "$UCI_DB_FILE" 2>/dev/null
        return 0
    fi

    if [ "$1" = "-q" ] && [ "$2" = "get" ]; then
        awk -F'|' -v key="$3" '
            key == "dhcp." $1 ".mac" { print $2; found=1; exit }
            key == "dhcp." $1 ".name" { print $3; found=1; exit }
            END { exit(found ? 0 : 1) }
        ' "$UCI_DB_FILE" 2>/dev/null
        return $?
    fi

    return 1
}

write_leases <<'EOF'
1717420000 92:27:f0:1a:66:6c 192.168.1.20 MCel *
1717420001 5c:cd:5b:c3:29:45 192.168.1.21 notebook-avell *
1717420002 aa:bb:cc:dd:ee:ff 192.168.1.22 * *
1717420003 11:22:33:44:55:66 192.168.1.23
EOF

write_uci_db <<'EOF'
host1|92:27:f0:1a:66:6c|celular-marcia
host2|de:ad:be:ef:00:01|kitchen & <tablet>
EOF

create_tool_wrapper awk
create_tool_wrapper head
create_tool_wrapper tr

telegram_send() {
    MESSAGES="${MESSAGES}$1|$2
"
}

log_info() {
    :
}

config_add_list() {
    :
}

config_del_list() {
    :
}

config_get_list() {
    :
}

config_set() {
    :
}

reset_messages() {
    MESSAGES=""
}

assert_equals() {
    actual="$1"
    expected="$2"
    description="$3"

    [ "$actual" = "$expected" ] || {
        echo "FAIL: $description" >&2
        echo "expected: $expected" >&2
        echo "actual: $actual" >&2
        exit 1
    }
}

static_name=$(_device_identity_static_name "92:27:F0:1A:66:6C")
static_status=$?
assert_equals "$static_status" "0" "static hostname lookup should return success status"
assert_equals "$static_name" "celular-marcia" "static hostname lookup should return matching configured name"

raw_html_name=$(_device_identity_static_name "DE:AD:BE:EF:00:01")
assert_equals "$raw_html_name" "kitchen & <tablet>" "static hostname helper should keep raw stored hostname for persistence use cases"

name=$(device_identity_hostname "92:27:F0:1A:66:6C")
assert_equals "$name" "celular-marcia" "static hostname should win with case-insensitive MAC match"

name=$(device_identity_hostname "DE:AD:BE:EF:00:01")
assert_equals "$name" "kitchen &amp; &lt;tablet&gt;" "display hostname should escape Telegram HTML metacharacters from static names"

name=$(device_identity_hostname "5C:CD:5B:C3:29:45")
assert_equals "$name" "notebook-avell" "lease hostname should be used when no static host exists"

name=$(device_identity_hostname "aa:bb:cc:dd:ee:ff")
assert_equals "$name" "Unknown" "wildcard lease hostname should fall back to Unknown"

name=$(device_identity_hostname "11:22:33:44:55:66")
assert_equals "$name" "Unknown" "empty lease hostname should fall back to Unknown"

# $ROOT_DIR is passed as an env var and must expand inside the child shell ("$TEST_SHELL" -c),
# not in this parent shell, so the single quotes are intentional.
# shellcheck disable=SC2016
name=$(PATH="$EMPTY_BIN_DIR" LEASES_FILE="$LEASES_FILE" ROOT_DIR="$ROOT_DIR" "$TEST_SHELL" -c '. "$ROOT_DIR/src/core/device_identity.sh"; device_identity_hostname "5C:CD:5B:C3:29:45"')
assert_equals "$name" "notebook-avell" "without uci, helper should fall back to lease hostname"

# shellcheck disable=SC2016
name=$(PATH="$EMPTY_BIN_DIR" LEASES_FILE="$LEASES_FILE" ROOT_DIR="$ROOT_DIR" "$TEST_SHELL" -c '. "$ROOT_DIR/src/core/device_identity.sh"; device_identity_hostname "aa:bb:cc:dd:ee:ff"')
assert_equals "$name" "Unknown" "without uci, wildcard lease hostname should still fall back to Unknown"

# shellcheck disable=SC2016
name=$(PATH="$EMPTY_BIN_DIR" LEASES_FILE="$LEASES_FILE" ROOT_DIR="$ROOT_DIR" "$TEST_SHELL" -c '. "$ROOT_DIR/src/core/device_identity.sh"; device_identity_hostname "11:22:33:44:55:66"')
assert_equals "$name" "Unknown" "without uci, empty lease hostname should still fall back to Unknown"

. "$ROOT_DIR/src/modules/devices.sh"
. "$ROOT_DIR/src/modules/monitor.sh"

LEASES_FILE="$TEST_TMP/dhcp.leases"
KNOWN_DEVICES_FILE="$TEST_TMP/known-devices"
_SEEN_EVER_FILE="$TEST_TMP/seen-devices"

direct_hostname_calls=$(awk 'index($0, "hostname=$(device_identity_hostname \"$mac\")") > 0 { count++ } END { print count + 0 }' "$ROOT_DIR/src/modules/devices.sh")
assert_equals "$direct_hostname_calls" "3" "devices module should call shared resolver directly in devices_list, devices_kick, and devices_block"

name=$(_devices_hostname "92:27:F0:1A:66:6C")
assert_equals "$name" "celular-marcia" "devices hostname helper should use shared static hostname resolution"

reset_messages
devices_list "123"
case "$MESSAGES" in
    *"celular-marcia"*) ;;
    *)
        echo "FAIL: devices list should prefer static hostname from shared resolver" >&2
        exit 1
        ;;
esac

write_leases <<'EOF'
1717420004 de:ad:be:ef:00:01 192.168.1.24 tablet *
EOF
reset_messages
devices_list "123"
case "$MESSAGES" in
    *"kitchen &amp; &lt;tablet&gt;"*) ;;
    *)
        echo "FAIL: devices list should escape HTML metacharacters from shared resolver" >&2
        exit 1
        ;;
esac

rm -f "$KNOWN_DEVICES_FILE" "$_SEEN_EVER_FILE"
write_leases <<'EOF'
EOF
monitor_init
write_leases <<'EOF'
1717420000 de:ad:be:ef:00:01 192.168.1.24 tablet *
EOF
reset_messages
monitor_check "123"
case "$MESSAGES" in
    *"kitchen &amp; &lt;tablet&gt;"*) ;;
    *)
        echo "FAIL: monitor alerts should escape HTML metacharacters from shared resolver" >&2
        exit 1
        ;;
esac

rm -rf "$TEST_TMP"

if [ -d "$TEST_TMP" ]; then
    echo "FAIL: temporary directory cleanup failed" >&2
    exit 1
fi
