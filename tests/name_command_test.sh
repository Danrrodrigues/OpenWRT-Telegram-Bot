#!/bin/sh

set -u

ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)
. "$ROOT_DIR/src/core/device_identity.sh"
. "$ROOT_DIR/src/modules/devices.sh"

TEST_TMP="${TMPDIR:-/tmp}/telegram-bot-name-command-test-$$"
UCI_DB_FILE="$TEST_TMP/uci-db"
UCI_CALLS_FILE="$TEST_TMP/uci-calls"
MESSAGES_FILE="$TEST_TMP/messages"
NEXT_SECTION_FILE="$TEST_TMP/next-section"
BOT_SOURCE_FILE="$TEST_TMP/bot-functions.sh"

mkdir -p "$TEST_TMP"
: > "$UCI_DB_FILE"
: > "$UCI_CALLS_FILE"
: > "$MESSAGES_FILE"
printf '1\n' > "$NEXT_SECTION_FILE"

telegram_send() {
    printf '%s|%s\n' "$1" "$2" >> "$MESSAGES_FILE"
}

log_info() {
    :
}

assert_contains() {
    haystack="$1"
    needle="$2"
    description="$3"

    case "$haystack" in
        *"$needle"*) ;;
        *)
            printf 'FAIL: %s\nExpected to find: %s\n' "$description" "$needle" >&2
            exit 1
            ;;
    esac
}

assert_not_contains() {
    haystack="$1"
    needle="$2"
    description="$3"

    case "$haystack" in
        *"$needle"*)
            printf 'FAIL: %s\nDid not expect to find: %s\n' "$description" "$needle" >&2
            exit 1
            ;;
        *) ;;
    esac
}

assert_equals() {
    actual="$1"
    expected="$2"
    description="$3"

    [ "$actual" = "$expected" ] || {
        printf 'FAIL: %s\nExpected: %s\nActual: %s\n' "$description" "$expected" "$actual" >&2
        exit 1
    }
}

write_uci_db() {
    cat > "$UCI_DB_FILE"
}

read_messages() {
    cat "$MESSAGES_FILE"
}

read_uci_calls() {
    cat "$UCI_CALLS_FILE"
}

reset_output() {
    : > "$UCI_CALLS_FILE"
    : > "$MESSAGES_FILE"
}

next_section_name() {
    section_id=$(cat "$NEXT_SECTION_FILE")
    printf '%s\n' $((section_id + 1)) > "$NEXT_SECTION_FILE"
    printf 'cfg-test-host-%s\n' "$section_id"
}

uci() {
    printf '%s\n' "$*" >> "$UCI_CALLS_FILE"

    if [ "$1" = "-q" ] && [ "$2" = "show" ] && [ "$3" = "dhcp" ]; then
        awk -F'|' 'NF >= 1 && $1 != "" { print "dhcp." $1 "=host" }' "$UCI_DB_FILE" 2>/dev/null
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

    if [ "$1" = "add" ] && [ "$2" = "dhcp" ] && [ "$3" = "host" ]; then
        section=$(next_section_name)
        printf '%s||\n' "$section" >> "$UCI_DB_FILE"
        printf '%s\n' "$section"
        return 0
    fi

    if [ "$1" = "set" ]; then
        uci_assignment=$2
        uci_key=${uci_assignment%%=*}
        uci_value=${uci_assignment#*=}
        uci_section=$(printf '%s\n' "$uci_key" | cut -d'.' -f2)
        uci_field=$(printf '%s\n' "$uci_key" | cut -d'.' -f3)
        awk -F'|' -v section="$uci_section" -v field="$uci_field" -v value="$uci_value" '
            BEGIN { updated=0 }
            $1 == section {
                if (field == "mac") {
                    $2 = value
                } else if (field == "name") {
                    $3 = value
                }
                updated=1
            }
            { print $1 "|" $2 "|" $3 }
            END {
                if (!updated) {
                    if (field == "mac") {
                        print section "|" value "|"
                    } else if (field == "name") {
                        print section "||" value
                    } else {
                        print section "||"
                    }
                }
            }
        ' "$UCI_DB_FILE" > "$UCI_DB_FILE.tmp" && mv "$UCI_DB_FILE.tmp" "$UCI_DB_FILE"
        return 0
    fi

    if [ "$1" = "commit" ] && [ "$2" = "dhcp" ]; then
        return 0
    fi

    return 1
}

reset_output
devices_set_name "123" ""
messages=$(read_messages)
assert_contains "$messages" "Usage: <code>/name &lt;MAC&gt; &lt;hostname&gt;</code>" "missing arguments should return usage"

reset_output
devices_set_name "123" "not-a-mac kitchen-tablet"
messages=$(read_messages)
assert_contains "$messages" "Usage: <code>/name &lt;MAC&gt; &lt;hostname&gt;</code>" "invalid MAC should return usage"

write_uci_db <<'EOF'
EOF
reset_output
devices_set_name "123" "92:27:F0:1A:66:6C celular-marcia"
uci_calls=$(read_uci_calls)
messages=$(read_messages)
saved_name=$(_device_identity_static_name "92:27:f0:1a:66:6c")
assert_contains "$uci_calls" "add dhcp host" "new MAC should create a dhcp host section"
assert_contains "$uci_calls" "set dhcp.cfg-test-host-1.mac=92:27:f0:1a:66:6c" "new MAC should persist lowercase MAC"
assert_contains "$uci_calls" "set dhcp.cfg-test-host-1.name=celular-marcia" "new MAC should persist hostname"
assert_contains "$uci_calls" "commit dhcp" "new MAC should commit dhcp changes"
assert_contains "$messages" "Name set for <code>92:27:f0:1a:66:6c</code>: <b>celular-marcia</b>" "new MAC should confirm saved hostname"
assert_equals "$saved_name" "celular-marcia" "new MAC should be readable through static name helper"

write_uci_db <<'EOF'
cfg-existing|92:27:f0:1a:66:6c|old-name
EOF
reset_output
devices_set_name "123" "92:27:f0:1a:66:6c updated-name"
uci_calls=$(read_uci_calls)
messages=$(read_messages)
saved_name=$(_device_identity_static_name "92:27:f0:1a:66:6c")
section=$(_device_identity_find_static_section "92:27:f0:1a:66:6c")
assert_not_contains "$uci_calls" "add dhcp host" "existing MAC should update in place instead of creating a new section"
assert_contains "$uci_calls" "set dhcp.cfg-existing.name=updated-name" "existing MAC should update the current section name"
assert_equals "$saved_name" "updated-name" "existing MAC should keep the section and update the stored hostname"
assert_equals "$section" "cfg-existing" "existing MAC lookup helper should return the current section"
assert_contains "$messages" "Name set for <code>92:27:f0:1a:66:6c</code>: <b>updated-name</b>" "existing MAC should confirm the updated hostname"

write_uci_db <<'EOF'
EOF
reset_output
devices_set_name "123" "   92:27:F0:1A:66:6C 		kitchen & <tablet>   "
uci_calls=$(read_uci_calls)
messages=$(read_messages)
saved_name=$(_device_identity_static_name "92:27:f0:1a:66:6c")
assert_contains "$uci_calls" "set dhcp.cfg-test-host-2.name=kitchen & <tablet>" "parser should trim repeated spaces and tabs around hostname before saving"
assert_equals "$saved_name" "kitchen & <tablet>" "saved hostname should preserve the raw user-supplied value"
assert_contains "$messages" "Name set for <code>92:27:f0:1a:66:6c</code>: <b>kitchen &amp; &lt;tablet&gt;</b>" "success message should escape Telegram HTML metacharacters"

awk -v root_dir="$ROOT_DIR" '
    /^SCRIPT_DIR=/ {
        print "SCRIPT_DIR=\"" root_dir "/src\""
        next
    }
    /^# ---- main ----/ { exit }
    { print }
' "$ROOT_DIR/src/bot.sh" > "$BOT_SOURCE_FILE"
# BOT_SOURCE_FILE is generated at runtime by the awk command above, so there is no
# static path for shellcheck to follow.
# shellcheck disable=SC1090
. "$BOT_SOURCE_FILE"

telegram_send() {
    printf '%s|%s\n' "$1" "$2" >> "$MESSAGES_FILE"
}

log_info() {
    :
}

write_uci_db <<'EOF'
EOF
reset_output
_bot_dispatch "123" "/name	92:27:F0:1A:66:6C 	kitchen & <tablet>   "
uci_calls=$(read_uci_calls)
messages=$(read_messages)
saved_name=$(_device_identity_static_name "92:27:f0:1a:66:6c")
assert_contains "$uci_calls" "add dhcp host" "dispatch should route /name to the device naming handler"
assert_contains "$uci_calls" "set dhcp.cfg-test-host-3.name=kitchen & <tablet>" "dispatch should preserve /name hostname text through command parsing"
assert_contains "$messages" "Name set for <code>92:27:f0:1a:66:6c</code>: <b>kitchen &amp; &lt;tablet&gt;</b>" "dispatch should produce the escaped success message"
assert_equals "$saved_name" "kitchen & <tablet>" "dispatch should persist the raw hostname after routing"

bot_source=$(cat "$ROOT_DIR/src/bot.sh")
assert_contains "$bot_source" "/name)" "bot dispatch should include /name command"
assert_contains "$bot_source" "devices_set_name \"\$chat_id\" \"\$args\"" "bot dispatch should call devices_set_name"
assert_contains "$bot_source" "/name &lt;MAC&gt; &lt;hostname&gt; — Save a device name by MAC" "help output should document /name"
assert_contains "$bot_source" "/wake)" "bot dispatch should include /wake command"
assert_contains "$bot_source" "devices_wake \"\$chat_id\" \"\$args\"" "bot dispatch should call devices_wake"
assert_contains "$bot_source" "/wake &lt;MAC or IP&gt; — Wake device with Wake-on-LAN" "help output should document /wake"

rm -rf "$TEST_TMP"
