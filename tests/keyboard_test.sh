#!/bin/sh

set -u

ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)

TEST_TMP="${TMPDIR:-/tmp}/telegram-bot-keyboard-test-$$"
mkdir -p "$TEST_TMP"

BOT_TOKEN="TESTTOKEN"
SEND_RESPONSE_FILE="$TEST_TMP/response.json"

log_info()  { :; }
log_error() { :; }
log_warn()  { :; }

# Capture every -d / --data-urlencode value and the called URL.
CURL_URL=""
CURL_DATA=""
curl() {
    local prev=""
    for a in "$@"; do
        case "$prev" in
            -d|--data-urlencode) CURL_DATA="${CURL_DATA}${a}&" ;;
        esac
        case "$a" in
            *api.telegram.org*) CURL_URL="$a" ;;
        esac
        prev="$a"
    done
    return 0
}

JSONFILTER_OK="true"
jsonfilter() {
    for a in "$@"; do
        case "$a" in
            *'@.ok'*)          echo "$JSONFILTER_OK" ;;
            *'@.description'*) echo "stub error" ;;
        esac
    done
}

. "$ROOT_DIR/src/core/telegram.sh"
. "$ROOT_DIR/src/core/keyboard.sh"

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
    CURL_URL=""
    CURL_DATA=""
    if "$@"; then
        printf 'PASS: %s\n' "$name"
    else
        FAILURES=$((FAILURES + 1))
    fi
}

# ---- keyboard_build_json ----

test_build_single_button() {
    local json
    json=$(keyboard_build_json "Confirm|reboot:confirm")
    assert_equals "$json" '[[{"text":"Confirm","callback_data":"reboot:confirm"}]]' "single button row"
}

test_build_multiple_buttons() {
    local json
    json=$(keyboard_build_json "Confirm|reboot:confirm" "Cancel|cancel:noop")
    assert_equals "$json" '[[{"text":"Confirm","callback_data":"reboot:confirm"}],[{"text":"Cancel","callback_data":"cancel:noop"}]]' "two button rows"
}

test_build_escapes_quotes() {
    local json
    json=$(keyboard_build_json 'My "Phone"|kick:aa:bb:cc:dd:ee:ff')
    assert_contains "$json" '\"Phone\"' "label quotes are escaped"
}

test_build_label_containing_pipe_keeps_callback_data_intact() {
    local json
    json=$(keyboard_build_json 'Kids|Tablet|kick:aa:bb:cc:dd:ee:ff')
    assert_equals "$json" '[[{"text":"Kids|Tablet","callback_data":"kick:aa:bb:cc:dd:ee:ff"}]]' "label with a pipe (e.g. a /name-set hostname) must not corrupt callback_data"
}

# ---- telegram_send_keyboard ----

test_send_keyboard_posts_inline_keyboard() {
    telegram_send_keyboard "123" "Pick one" "A|a:1" "B|b:2" || return 1
    assert_contains "$CURL_URL" "/sendMessage" "calls sendMessage endpoint" || return 1
    assert_contains "$CURL_DATA" 'reply_markup={"inline_keyboard":[[{"text":"A","callback_data":"a:1"}],[{"text":"B","callback_data":"b:2"}]]}' "encodes inline_keyboard"
}

test_send_keyboard_fails_without_token() {
    BOT_TOKEN="" telegram_send_keyboard "123" "x" "A|a" && return 1
    BOT_TOKEN="TESTTOKEN"
    return 0
}

# ---- telegram_edit_message ----

test_edit_message_posts_to_endpoint() {
    telegram_edit_message "123" "456" "Done" || return 1
    assert_contains "$CURL_URL" "/editMessageText" "calls editMessageText endpoint" || return 1
    assert_contains "$CURL_DATA" "message_id=456" "includes message_id"
}

# ---- telegram_answer_callback ----

test_answer_callback_posts_to_endpoint() {
    telegram_answer_callback "cb123" "Cancelled" || return 1
    assert_contains "$CURL_URL" "/answerCallbackQuery" "calls answerCallbackQuery endpoint" || return 1
    assert_contains "$CURL_DATA" "callback_query_id=cb123" "includes callback_query_id"
}

# ---- run all ----

run_test "keyboard: single button row"            test_build_single_button
run_test "keyboard: multiple button rows"          test_build_multiple_buttons
run_test "keyboard: escapes quotes in labels"      test_build_escapes_quotes
run_test "keyboard: label with pipe keeps data intact" test_build_label_containing_pipe_keeps_callback_data_intact
run_test "send_keyboard: encodes inline_keyboard"  test_send_keyboard_posts_inline_keyboard
run_test "send_keyboard: fails without token"      test_send_keyboard_fails_without_token
run_test "edit_message: calls correct endpoint"    test_edit_message_posts_to_endpoint
run_test "answer_callback: calls correct endpoint" test_answer_callback_posts_to_endpoint

rm -rf "$TEST_TMP"

if [ "$FAILURES" -ne 0 ]; then
    exit 1
fi
