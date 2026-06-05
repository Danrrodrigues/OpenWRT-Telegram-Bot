#!/bin/sh

set -u

ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)

TEST_TMP="${TMPDIR:-/tmp}/telegram-bot-commands-test-$$"
mkdir -p "$TEST_TMP"

# Context consumed by telegram.sh
BOT_TOKEN="TESTTOKEN"
SEND_RESPONSE_FILE="$TEST_TMP/response.json"

log_info()  { :; }
log_error() { :; }
log_warn()  { :; }

# Capture the JSON payload instead of hitting the network.
CURL_URL=""
CURL_DATA=""
curl() {
    local prev=""
    for a in "$@"; do
        case "$prev" in
            -d) CURL_DATA="$a" ;;
        esac
        case "$a" in
            *api.telegram.org*) CURL_URL="$a" ;;
        esac
        prev="$a"
    done
    return 0
}

# jsonfilter is OpenWRT-only; stub it to report success on the ok field.
JSONFILTER_OK="true"
jsonfilter() {
    # invoked as: jsonfilter -i FILE -e '@.ok'  (or '@.description')
    for a in "$@"; do
        case "$a" in
            *'@.ok'*)          echo "$JSONFILTER_OK" ;;
            *'@.description'*) echo "stub error" ;;
        esac
    done
}

. "$ROOT_DIR/src/core/telegram.sh"

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

# ---- tests ----

test_builds_valid_json_from_commands() {
    I18N_COMMANDS='start|Show help
devices|List connected devices'
    telegram_set_commands || return 1
    assert_contains "$CURL_DATA" '{"commands":[' "payload opens commands array" || return 1
    assert_contains "$CURL_DATA" '{"command":"start","description":"Show help"}' "start command encoded" || return 1
    assert_contains "$CURL_DATA" '{"command":"devices","description":"List connected devices"}' "devices command encoded" || return 1
    assert_contains "$CURL_DATA" ']}' "payload closes correctly" || return 1
}

test_posts_to_setmycommands_endpoint() {
    I18N_COMMANDS='help|Show this message'
    telegram_set_commands || return 1
    assert_contains "$CURL_URL" "/setMyCommands" "calls setMyCommands endpoint" || return 1
    assert_contains "$CURL_URL" "TESTTOKEN" "uses configured token" || return 1
}

test_skips_blank_lines() {
    I18N_COMMANDS='start|Show help

help|Show this message'
    telegram_set_commands || return 1
    assert_contains "$CURL_DATA" '{"command":"start","description":"Show help"},{"command":"help","description":"Show this message"}' "blank line skipped, no empty entry" || return 1
}

test_fails_without_token() {
    I18N_COMMANDS='start|Show help'
    BOT_TOKEN="" telegram_set_commands && return 1
    return 0
}

test_fails_without_commands() {
    I18N_COMMANDS="" telegram_set_commands && return 1
    return 0
}

test_reports_api_error() {
    I18N_COMMANDS='start|Show help'
    JSONFILTER_OK="false"
    telegram_set_commands && { JSONFILTER_OK="true"; return 1; }
    JSONFILTER_OK="true"
    return 0
}

# ---- run all ----

run_test "setMyCommands: builds valid JSON"          test_builds_valid_json_from_commands
run_test "setMyCommands: posts to correct endpoint"  test_posts_to_setmycommands_endpoint
run_test "setMyCommands: skips blank lines"          test_skips_blank_lines
run_test "setMyCommands: fails without token"        test_fails_without_token
run_test "setMyCommands: fails without commands"     test_fails_without_commands
run_test "setMyCommands: reports API error"          test_reports_api_error

rm -rf "$TEST_TMP"

if [ "$FAILURES" -ne 0 ]; then
    exit 1
fi
