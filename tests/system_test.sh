#!/bin/sh

set -u

ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)

MESSAGES=""
KEYBOARDS=""

telegram_send() {
    local chat_id="$1"
    local text="$2"
    MESSAGES="${MESSAGES}${chat_id}|${text}
"
}

telegram_send_keyboard() {
    local chat_id="$1"
    local text="$2"
    shift 2
    KEYBOARDS="${KEYBOARDS}${chat_id}|${text}|$*
"
}

# i18n strings for system messages
T_RESTARTDNS_OK="DNS cache restarted (dnsmasq)."
T_RESTARTDNS_FAIL="Failed to restart dnsmasq. Check the logs."
T_RESTARTDNS_MISSING="Nothing to restart: this router has no dnsmasq init script."
T_RESTARTDNS_CONFIRM="This will restart dnsmasq."
T_REBOOT_CONFIRM="This will reboot the router and drop the network for about a minute."
T_REBOOT_RUNNING="Rebooting now... the bot will be back shortly."
T_BTN_CONFIRM="Confirm"
T_BTN_CANCEL="Cancel"

log_info()  { :; }
log_error() { :; }
log_warn()  { :; }

# Source the module under test
. "$ROOT_DIR/src/modules/system.sh"

# Stub the pure helpers so tests never touch a real router.
_DNSMASQ_AVAILABLE_MOCK=0
_DNSMASQ_RESTART_RC=0
_DNSMASQ_RESTART_CALLED=0
_REBOOT_SCHEDULED=0

_system_dnsmasq_available() { return "$_DNSMASQ_AVAILABLE_MOCK"; }
_system_dnsmasq_restart() {
    _DNSMASQ_RESTART_CALLED=1
    return "$_DNSMASQ_RESTART_RC"
}
_system_schedule_reboot() { _REBOOT_SCHEDULED=1; }

# ---- assertions ----

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

assert_equals() {
    local actual="$1"
    local expected="$2"
    local description="$3"

    if [ "$actual" != "$expected" ]; then
        printf 'FAIL: %s\nExpected: %s\nActual: %s\n' "$description" "$expected" "$actual" >&2
        return 1
    fi
}

FAILURES=0

run_test() {
    local name="$1"
    shift
    MESSAGES=""
    KEYBOARDS=""
    _DNSMASQ_AVAILABLE_MOCK=0
    _DNSMASQ_RESTART_RC=0
    _DNSMASQ_RESTART_CALLED=0
    _REBOOT_SCHEDULED=0
    if "$@"; then
        printf 'PASS: %s\n' "$name"
    else
        FAILURES=$((FAILURES + 1))
    fi
}

# ---- /restartdns tests ----

test_restartdns_no_args_shows_keyboard() {
    system_restartdns "123" ""
    assert_equals "$MESSAGES" "" "should not restart yet without confirm" || return 1
    assert_contains "$KEYBOARDS" "restartdns:confirm" "should offer a confirm button" || return 1
    assert_equals "$_DNSMASQ_RESTART_CALLED" "0" "should never call restart without confirm"
}

test_restartdns_confirm_success() {
    _DNSMASQ_RESTART_RC=0
    system_restartdns "123" "confirm"
    assert_contains "$MESSAGES" "restarted" "should confirm dnsmasq restarted" || return 1
}

test_restartdns_confirm_failure() {
    _DNSMASQ_RESTART_RC=1
    system_restartdns "123" "confirm"
    assert_contains "$MESSAGES" "Failed" "should report restart failure" || return 1
}

test_restartdns_confirm_missing() {
    _DNSMASQ_AVAILABLE_MOCK=1
    system_restartdns "123" "confirm"
    assert_contains "$MESSAGES" "Nothing to restart" "should report missing dnsmasq" || return 1
    assert_equals "$_DNSMASQ_RESTART_CALLED" "0" "should never call restart when dnsmasq is missing"
}

# ---- /reboot tests ----

test_reboot_without_confirm_shows_keyboard() {
    system_reboot "123" ""
    assert_equals "$MESSAGES" "" "should not reboot yet without confirm" || return 1
    assert_contains "$KEYBOARDS" "reboot:confirm" "should offer a confirm button" || return 1
    assert_equals "$_REBOOT_SCHEDULED" "0" "should not schedule reboot without confirm"
}

test_reboot_with_confirm() {
    system_reboot "123" "confirm"
    assert_contains "$MESSAGES" "Rebooting" "should send rebooting message" || return 1
    assert_equals "$_REBOOT_SCHEDULED" "1" "should schedule reboot when confirmed"
}

# ---- run all ----

run_test "/restartdns: no args shows confirm keyboard" test_restartdns_no_args_shows_keyboard
run_test "/restartdns: confirm success"                test_restartdns_confirm_success
run_test "/restartdns: confirm failure"                test_restartdns_confirm_failure
run_test "/restartdns: confirm dnsmasq missing"        test_restartdns_confirm_missing
run_test "/reboot: without confirm shows keyboard"     test_reboot_without_confirm_shows_keyboard
run_test "/reboot: confirm schedules reboot"           test_reboot_with_confirm

if [ "$FAILURES" -ne 0 ]; then
    exit 1
fi
