#!/bin/sh

set -u

ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)

TEST_TMP="${TMPDIR:-/tmp}/telegram-bot-notify-test-$$"
mkdir -p "$TEST_TMP"

# Bot context required by the module
VERSION="0.2.2"
BOT_CHAT_IDS="12345 67890"
BOT_LANG="en"

# i18n strings normally provided by the sourced language file
T_UPDATED="Bot updated to v%s"
T_UPDATE_AVAILABLE="New version available: v%s (you have v%s)."

# Keep all state inside the sandbox (read before sourcing so derived paths use it)
NOTIFY_STATE_DIR="$TEST_TMP/state"

MESSAGES=""
SET_COMMANDS_CALLED=0
MOCK_REMOTE=""
MOCK_HOUR="09"
MOCK_TODAY="2026-06-05"

telegram_send() {
    local chat_id="$1"
    local text="$2"
    MESSAGES="${MESSAGES}${chat_id}|${text}
"
}

SET_COMMANDS_RC=0
telegram_set_commands() { SET_COMMANDS_CALLED=1; return "$SET_COMMANDS_RC"; }

_updater_remote_version() { echo "$MOCK_REMOTE"; }

# Deterministic clock
date() {
    case "$1" in
        +%H)       echo "$MOCK_HOUR" ;;
        +%Y-%m-%d) echo "$MOCK_TODAY" ;;
        *)         command date "$@" ;;
    esac
}

log_info()  { :; }
log_error() { :; }
log_warn()  { :; }

# Source the module under test (uses NOTIFY_STATE_DIR set above)
. "$ROOT_DIR/src/modules/notify.sh"

# ---- assertions ----

assert_contains() {
    case "$1" in
        *"$2"*) ;;
        *) printf 'FAIL: %s\nExpected to find: %s\n' "$3" "$2" >&2; return 1 ;;
    esac
}

assert_not_contains() {
    case "$1" in
        *"$2"*) printf 'FAIL: %s\nDid not expect: %s\n' "$3" "$2" >&2; return 1 ;;
        *) ;;
    esac
}

assert_equals() {
    if [ "$1" != "$2" ]; then
        printf 'FAIL: %s\nExpected: %s\nActual: %s\n' "$3" "$2" "$1" >&2
        return 1
    fi
}

assert_file_absent() {
    if [ -f "$1" ]; then
        printf 'FAIL: %s\nUnexpected file: %s\n' "$2" "$1" >&2
        return 1
    fi
}

FAILURES=0

run_test() {
    local name="$1"
    shift
    MESSAGES=""
    SET_COMMANDS_CALLED=0
    SET_COMMANDS_RC=0
    BOT_LANG="en"
    rm -rf "$NOTIFY_STATE_DIR"
    if "$@"; then
        printf 'PASS: %s\n' "$name"
    else
        FAILURES=$((FAILURES + 1))
    fi
}

# ---- version-change tests (A) ----

test_fresh_install_registers_menu_no_message() {
    # No seen_version file -> first run
    notify_check_version_change
    assert_equals "$SET_COMMANDS_CALLED" "1" "menu should be registered on first run" || return 1
    assert_not_contains "$MESSAGES" "updated" "no update message on fresh install" || return 1
    assert_equals "$(cat "$NOTIFY_SEEN_VERSION_FILE")" "0.2.2|en" "seen version+lang recorded" || return 1
}

test_version_bump_announces_to_all_chats() {
    mkdir -p "$NOTIFY_STATE_DIR"
    echo "0.2.1|en" > "$NOTIFY_SEEN_VERSION_FILE"
    notify_check_version_change
    assert_equals "$SET_COMMANDS_CALLED" "1" "menu re-registered on update" || return 1
    assert_contains "$MESSAGES" "Bot updated to v0.2.2" "announces new version" || return 1
    assert_contains "$MESSAGES" "12345|" "notifies first chat" || return 1
    assert_contains "$MESSAGES" "67890|" "notifies second chat" || return 1
    assert_equals "$(cat "$NOTIFY_SEEN_VERSION_FILE")" "0.2.2|en" "seen version updated" || return 1
}

test_same_version_no_action() {
    mkdir -p "$NOTIFY_STATE_DIR"
    echo "0.2.2|en" > "$NOTIFY_SEEN_VERSION_FILE"
    notify_check_version_change
    assert_equals "$SET_COMMANDS_CALLED" "0" "menu not touched on same version+lang" || return 1
    assert_equals "$MESSAGES" "" "no message on same version" || return 1
}

test_language_change_reregisters_menu_no_announce() {
    mkdir -p "$NOTIFY_STATE_DIR"
    echo "0.2.2|en" > "$NOTIFY_SEEN_VERSION_FILE"
    BOT_LANG="pt"
    notify_check_version_change
    assert_equals "$SET_COMMANDS_CALLED" "1" "menu re-registered after language change" || return 1
    assert_equals "$MESSAGES" "" "no update message on language-only change" || return 1
    assert_equals "$(cat "$NOTIFY_SEEN_VERSION_FILE")" "0.2.2|pt" "seen lang updated" || return 1
}

test_registration_failure_does_not_persist_state() {
    SET_COMMANDS_RC=1
    notify_check_version_change && return 1   # should return non-zero
    assert_equals "$SET_COMMANDS_CALLED" "1" "registration was attempted" || return 1
    assert_file_absent "$NOTIFY_SEEN_VERSION_FILE" "state not persisted on failure (retry next start)" || return 1
    assert_equals "$MESSAGES" "" "no announcement when registration failed" || return 1
}

# ---- daily check tests (B) ----

test_daily_before_hour_is_noop() {
    MOCK_HOUR="07"
    MOCK_REMOTE="0.3.0"
    notify_daily_update_check
    assert_equals "$MESSAGES" "" "no message before 08:00" || return 1
    assert_file_absent "$NOTIFY_LAST_CHECK_FILE" "timestamp not written before 08:00" || return 1
}

test_daily_already_checked_today_is_noop() {
    MOCK_HOUR="09"
    MOCK_REMOTE="0.3.0"
    mkdir -p "$NOTIFY_STATE_DIR"
    echo "$MOCK_TODAY" > "$NOTIFY_LAST_CHECK_FILE"
    notify_daily_update_check
    assert_equals "$MESSAGES" "" "no message when already checked today" || return 1
}

test_daily_newer_version_suggests_update() {
    MOCK_HOUR="08"
    MOCK_REMOTE="0.3.0"
    notify_daily_update_check
    assert_contains "$MESSAGES" "0.3.0" "suggests remote version" || return 1
    assert_contains "$MESSAGES" "0.2.2" "mentions installed version" || return 1
    assert_contains "$MESSAGES" "12345|" "notifies first chat" || return 1
    assert_contains "$MESSAGES" "67890|" "notifies second chat" || return 1
    assert_equals "$(cat "$NOTIFY_LAST_CHECK_FILE")" "$MOCK_TODAY" "timestamp recorded" || return 1
}

test_daily_up_to_date_no_message() {
    MOCK_HOUR="09"
    MOCK_REMOTE="0.2.2"
    notify_daily_update_check
    assert_equals "$MESSAGES" "" "no message when up to date" || return 1
    assert_equals "$(cat "$NOTIFY_LAST_CHECK_FILE")" "$MOCK_TODAY" "timestamp still recorded" || return 1
}

test_daily_network_failure_no_message_but_records() {
    MOCK_HOUR="09"
    MOCK_REMOTE=""
    notify_daily_update_check
    assert_equals "$MESSAGES" "" "no message on network failure" || return 1
    assert_equals "$(cat "$NOTIFY_LAST_CHECK_FILE")" "$MOCK_TODAY" "timestamp recorded to retry tomorrow" || return 1
}

# ---- run all ----

run_test "version: fresh install registers menu, no message" test_fresh_install_registers_menu_no_message
run_test "version: bump announces to all chats"              test_version_bump_announces_to_all_chats
run_test "version: same version is a no-op"                  test_same_version_no_action
run_test "version: language change re-registers menu"       test_language_change_reregisters_menu_no_announce
run_test "version: registration failure does not persist"  test_registration_failure_does_not_persist_state
run_test "daily: before 08:00 is a no-op"                    test_daily_before_hour_is_noop
run_test "daily: already checked today is a no-op"           test_daily_already_checked_today_is_noop
run_test "daily: newer version suggests update"             test_daily_newer_version_suggests_update
run_test "daily: up to date sends nothing"                  test_daily_up_to_date_no_message
run_test "daily: network failure records and stays quiet"  test_daily_network_failure_no_message_but_records

rm -rf "$TEST_TMP"

if [ "$FAILURES" -ne 0 ]; then
    exit 1
fi
