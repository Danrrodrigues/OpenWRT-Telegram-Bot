#!/bin/sh

set -u

ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)

TEST_TMP="${TMPDIR:-/tmp}/telegram-bot-session-test-$$"
mkdir -p "$TEST_TMP"

SESSION_DIR="$TEST_TMP"
SESSION_PENDING_TTL=120

. "$ROOT_DIR/src/core/session.sh"

# ---- assertions ----

assert_equals() {
    if [ "$1" != "$2" ]; then
        printf 'FAIL: %s\nExpected: %s\nActual: %s\n' "$3" "$2" "$1" >&2
        return 1
    fi
}

assert_file_not_exists() {
    if [ -f "$1" ]; then
        printf 'FAIL: %s\nFile should not exist: %s\n' "$2" "$1" >&2
        return 1
    fi
}

FAILURES=0

run_test() {
    local name="$1"
    shift
    rm -f "$TEST_TMP"/telegram-bot-pending-*
    if "$@"; then
        printf 'PASS: %s\n' "$name"
    else
        FAILURES=$((FAILURES + 1))
    fi
}

# ---- tests ----

test_set_then_get_round_trip() {
    session_set_pending "123" "limit" "aa:bb:cc:dd:ee:ff"
    assert_equals "$(session_get_pending "123")" "limit:aa:bb:cc:dd:ee:ff" "should return the same action:mac that was set"
}

test_get_without_pending_is_empty() {
    assert_equals "$(session_get_pending "999")" "" "no pending file should return empty"
}

test_clear_removes_pending() {
    session_set_pending "123" "name" "aa:bb:cc:dd:ee:ff"
    session_clear_pending "123"
    assert_file_not_exists "$TEST_TMP/telegram-bot-pending-123" "clear should delete the pending file" || return 1
    assert_equals "$(session_get_pending "123")" "" "cleared pending should not be returned"
}

test_expired_pending_is_dropped() {
    printf 'limit aa:bb:cc:dd:ee:ff 1\n' > "$TEST_TMP/telegram-bot-pending-123"
    assert_equals "$(session_get_pending "123")" "" "pending older than TTL should be ignored"
    assert_file_not_exists "$TEST_TMP/telegram-bot-pending-123" "expired pending file should be deleted on read"
}

test_separate_chats_are_independent() {
    session_set_pending "111" "limit" "aa:aa:aa:aa:aa:aa"
    session_set_pending "222" "name" "bb:bb:bb:bb:bb:bb"
    assert_equals "$(session_get_pending "111")" "limit:aa:aa:aa:aa:aa:aa" "chat 111 keeps its own pending" || return 1
    assert_equals "$(session_get_pending "222")" "name:bb:bb:bb:bb:bb:bb" "chat 222 keeps its own pending"
}

# ---- run all ----

run_test "session: set/get round trip"          test_set_then_get_round_trip
run_test "session: get without pending"         test_get_without_pending_is_empty
run_test "session: clear removes pending"       test_clear_removes_pending
run_test "session: expired pending is dropped"  test_expired_pending_is_dropped
run_test "session: chats are independent"       test_separate_chats_are_independent

rm -rf "$TEST_TMP"

if [ "$FAILURES" -ne 0 ]; then
    exit 1
fi
