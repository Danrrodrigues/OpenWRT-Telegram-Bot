#!/bin/sh
# Tests for the inline-keyboard dispatch layer in bot.sh — routing of
# callback_query button presses (_bot_dispatch_callback) and guided-flow
# follow-up text (_bot_dispatch_pending). Handler functions (system_reboot,
# devices_kick, etc.) are stubbed as recorders: their own behavior is
# covered by system_test.sh/devices_test.sh/bandwidth_test.sh/updater_test.sh —
# this file only verifies the dispatcher routes correctly and that the
# telegram_send → telegram_edit_message redirect actually fires.

set -u

ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)
SRC_DIR="$ROOT_DIR/src"

TEST_TMP="${TMPDIR:-/tmp}/telegram-bot-dispatch-test-$$"
mkdir -p "$TEST_TMP"

# These are consumed by core/telegram.sh, core/session.sh, and the dynamically
# sourced $BOT_SOURCE_FILE below — shellcheck can't see that usage through a
# runtime-generated path, same as the T_* pattern in src/lang/*.sh.
# shellcheck disable=SC2034
BOT_TOKEN="TESTTOKEN"
# shellcheck disable=SC2034
SEND_RESPONSE_FILE="$TEST_TMP/response.json"
# shellcheck disable=SC2034
SESSION_DIR="$TEST_TMP"
BOT_SOURCE_FILE="$TEST_TMP/bot-functions.sh"

# Extract bot.sh up to "# ---- main ----" so we get every sourced core/module
# file plus _bot_dispatch_callback/_bot_dispatch_pending, without running the
# daemon/cron entry point.
awk -v root_dir="$SRC_DIR" '
    /^SCRIPT_DIR=/ { print "SCRIPT_DIR=\"" root_dir "\""; next }
    /^# ---- main ----/ { exit }
    { print }
' "$SRC_DIR/bot.sh" > "$BOT_SOURCE_FILE"
# shellcheck disable=SC1090
. "$BOT_SOURCE_FILE"

# ---- redefine everything that would hit the network or the real
# filesystem (sourcing bot.sh above pulled in the REAL logger.sh/telegram.sh
# implementations, so these overrides must come after, not before) ----

log_info()  { :; }
log_error() { :; }
log_warn()  { :; }

CURL_LOG=""
curl() {
    for a in "$@"; do
        case "$a" in
            *api.telegram.org*) CURL_LOG="${CURL_LOG}${a}
" ;;
        esac
    done
    return 0
}
jsonfilter() {
    for a in "$@"; do
        case "$a" in
            *'@.ok'*) echo "true" ;;
        esac
    done
}

# shellcheck disable=SC2034
T_CANCELLED="Cancelled."
# shellcheck disable=SC2034
T_LIMIT_PROMPT="Send down up Mbps"
# shellcheck disable=SC2034
T_NAME_PROMPT="Send the new name"

# ---- recorders, overriding the real handlers (last definition wins) ----
# telegram_send is left as the REAL implementation from core/telegram.sh —
# its TELEGRAM_REDIRECT_* handling is exactly what's under test here. Only
# telegram_edit_message/telegram_answer_callback are swapped for recorders,
# which the real telegram_send calls into when a redirect is active.

CALLS=""
EDITED=""
ANSWERED=""

telegram_send_keyboard() { :; }

telegram_answer_callback() {
    ANSWERED="${ANSWERED}${1}
"
}

telegram_edit_message() {
    EDITED="${EDITED}${1}|${2}|${3}
"
}

system_reboot() { CALLS="${CALLS}system_reboot:$1:$2
"; telegram_send "$1" "Rebooted"; }
system_restartdns() { CALLS="${CALLS}system_restartdns:$1:$2
"; telegram_send "$1" "Restarted"; }
updater_check() { CALLS="${CALLS}updater_check:$1:$2
"; telegram_send "$1" "Updated"; }
updater_rollback() { CALLS="${CALLS}updater_rollback:$1:$2
"; telegram_send "$1" "RolledBack"; }
devices_kick() { CALLS="${CALLS}devices_kick:$1:$2
"; telegram_send "$1" "Kicked"; }
devices_block() { CALLS="${CALLS}devices_block:$1:$2
"; telegram_send "$1" "Blocked"; }
devices_unblock() { CALLS="${CALLS}devices_unblock:$1:$2
"; telegram_send "$1" "Unblocked"; }
devices_wake() { CALLS="${CALLS}devices_wake:$1:$2
"; telegram_send "$1" "Woke"; }
bandwidth_limit() { CALLS="${CALLS}bandwidth_limit:$1:$2:$3:$4
"; }
devices_set_name() { CALLS="${CALLS}devices_set_name:$1:$2
"; }

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

assert_not_contains() {
    case "$1" in
        *"$2"*) printf 'FAIL: %s\nDid not expect to find: %s\n' "$3" "$2" >&2; return 1 ;;
        *) ;;
    esac
}

FAILURES=0

run_test() {
    local name="$1"
    shift
    CALLS=""
    CURL_LOG=""
    EDITED=""
    ANSWERED=""
    rm -f "$TEST_TMP"/telegram-bot-pending-*
    if "$@"; then
        printf 'PASS: %s\n' "$name"
    else
        FAILURES=$((FAILURES + 1))
    fi
}

# ---- _bot_dispatch_callback ----

test_cancel_edits_message_no_handler_call() {
    _bot_dispatch_callback "123" "456" "cb1" "cancel:noop"
    assert_equals "$CALLS" "" "cancel should not call any handler" || return 1
    assert_contains "$EDITED" "123|456|Cancelled." "cancel should edit the message to the cancelled text" || return 1
    assert_contains "$ANSWERED" "cb1" "cancel should still answer the callback"
}

test_reboot_confirm_routes_and_redirects_to_edit() {
    _bot_dispatch_callback "123" "456" "cb2" "reboot:confirm"
    assert_contains "$CALLS" "system_reboot:123:confirm" "should call system_reboot with confirm" || return 1
    assert_contains "$EDITED" "123|456|Rebooted" "the real telegram_send should redirect into telegram_edit_message" || return 1
    assert_not_contains "$CURL_LOG" "/sendMessage" "no separate sendMessage call should happen (redirect consumed it)"
}

test_kick_routes_mac_argument() {
    _bot_dispatch_callback "123" "456" "cb3" "kick:aa:bb:cc:dd:ee:ff"
    assert_contains "$CALLS" "devices_kick:123:aa:bb:cc:dd:ee:ff" "should call devices_kick with the MAC from callback_data"
}

test_limitpick_sets_pending_and_prompts() {
    _bot_dispatch_callback "123" "456" "cb4" "limitpick:aa:bb:cc:dd:ee:ff"
    assert_equals "$CALLS" "" "limitpick should not call bandwidth_limit yet" || return 1
    assert_equals "$(session_get_pending "123")" "limit:aa:bb:cc:dd:ee:ff" "limitpick should set a pending guided flow" || return 1
    assert_contains "$EDITED" "Send down up Mbps" "limitpick should edit the message with the prompt"
}

test_namepick_sets_pending_and_prompts() {
    _bot_dispatch_callback "123" "456" "cb5" "namepick:aa:bb:cc:dd:ee:ff"
    assert_equals "$(session_get_pending "123")" "name:aa:bb:cc:dd:ee:ff" "namepick should set a pending guided flow" || return 1
    assert_contains "$EDITED" "Send the new name" "namepick should edit the message with the prompt"
}

# ---- _bot_dispatch_pending ----

test_pending_limit_splits_text_into_down_up() {
    _bot_dispatch_pending "123" "limit" "aa:bb:cc:dd:ee:ff" "10 5"
    assert_contains "$CALLS" "bandwidth_limit:123:aa:bb:cc:dd:ee:ff:10:5" "should call bandwidth_limit with mac, down, up parsed from the reply"
}

test_pending_name_combines_mac_and_text() {
    _bot_dispatch_pending "123" "name" "aa:bb:cc:dd:ee:ff" "Kitchen Tablet"
    assert_contains "$CALLS" "devices_set_name:123:aa:bb:cc:dd:ee:ff Kitchen Tablet" "should call devices_set_name with mac + typed text as args"
}

# ---- run all ----

run_test "callback: cancel edits message, no handler call"        test_cancel_edits_message_no_handler_call
run_test "callback: reboot:confirm routes and redirects to edit"  test_reboot_confirm_routes_and_redirects_to_edit
run_test "callback: kick:<mac> routes the mac argument"          test_kick_routes_mac_argument
run_test "callback: limitpick sets pending and prompts"          test_limitpick_sets_pending_and_prompts
run_test "callback: namepick sets pending and prompts"            test_namepick_sets_pending_and_prompts
run_test "pending: limit splits reply into down/up"              test_pending_limit_splits_text_into_down_up
run_test "pending: name combines mac and typed text"             test_pending_name_combines_mac_and_text

rm -rf "$TEST_TMP"

if [ "$FAILURES" -ne 0 ]; then
    exit 1
fi
