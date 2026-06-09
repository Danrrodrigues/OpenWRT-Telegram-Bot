#!/bin/sh

set -u

ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)

TEST_TMP="${TMPDIR:-/tmp}/telegram-bot-lang-test-$$"
mkdir -p "$TEST_TMP"

# Bot context required by the module
# shellcheck disable=SC2034
VERSION="0.3.3"
BOT_LANG="en"

MESSAGES=""

telegram_send() {
    local chat_id="$1"
    local text="$2"
    MESSAGES="${MESSAGES}${chat_id}|${text}
"
}

log_info()  { :; }
log_error() { :; }

# i18n strings for lang command
T_LANG_CURRENT="Current language: %s
Send /lang en or /lang pt to switch."
T_LANG_CHANGED="Language changed to %s"
T_LANG_SAME="Language is already set to %s"
T_LANG_INVALID="Unknown language: %s. Available: en, pt"

# Stubs
_CONFIG_SET_KEY=""
_CONFIG_SET_VAL=""
config_set() {
    _CONFIG_SET_KEY="$1"
    _CONFIG_SET_VAL="$2"
}

_I18N_LOADED=""
i18n_load() { _I18N_LOADED="yes"; }

_NOTIFY_CALLED=""
notify_check_version_change() { _NOTIFY_CALLED="yes"; }

# Source the module under test
. "$ROOT_DIR/src/modules/lang.sh"

# ---- assertions ----

assert_contains() {
    case "$1" in
        *"$2"*) ;;
        *) printf 'FAIL: %s\nExpected to find: %s\n' "$3" "$2" >&2; return 1 ;;
    esac
}

assert_not_contains() {
    case "$1" in
        *"$2"*) printf 'FAIL: %s\nDid not expect to find: %s\n' "$3" "$2" >&2; return 1 ;;
        *) ;;
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
    _CONFIG_SET_KEY=""
    _CONFIG_SET_VAL=""
    _I18N_LOADED=""
    _NOTIFY_CALLED=""
    if "$@"; then
        printf 'PASS: %s\n' "$name"
    else
        FAILURES=$((FAILURES + 1))
    fi
}

# ---- tests ----

test_no_args_shows_current_lang() {
    lang_set "12345" ""
    assert_contains "$MESSAGES" "en" "should show current language" || return 1
    assert_contains "$MESSAGES" "/lang" "should mention available options" || return 1
}

test_switch_to_portuguese() {
    BOT_LANG="en"
    lang_set "12345" "pt"
    assert_contains "$MESSAGES" "pt" "confirmation should mention pt" || return 1
    assert_equals "$_CONFIG_SET_KEY" "lang" "should persist lang to config" || return 1
    assert_equals "$_CONFIG_SET_VAL" "pt" "should persist value pt" || return 1
    assert_equals "$_I18N_LOADED" "yes" "should reload i18n" || return 1
    assert_equals "$_NOTIFY_CALLED" "yes" "should refresh command menu" || return 1
}

test_switch_to_english() {
    BOT_LANG="pt"
    lang_set "12345" "en"
    assert_contains "$MESSAGES" "en" "confirmation should mention en" || return 1
    assert_equals "$_CONFIG_SET_VAL" "en" "should persist value en" || return 1
}

test_same_language_noop() {
    BOT_LANG="en"
    lang_set "12345" "en"
    assert_contains "$MESSAGES" "already" "should say already set" || return 1
    assert_equals "$_CONFIG_SET_KEY" "" "should NOT persist when same" || return 1
    assert_equals "$_I18N_LOADED" "" "should NOT reload when same" || return 1
}

test_accepts_english_alias() {
    BOT_LANG="pt"
    lang_set "12345" "english"
    assert_equals "$_CONFIG_SET_VAL" "en" "english alias should resolve to en" || return 1
}

test_accepts_portuguese_aliases() {
    BOT_LANG="en"
    lang_set "12345" "pt-br"
    assert_equals "$_CONFIG_SET_VAL" "pt" "pt-br alias should resolve to pt" || return 1
}

test_accepts_portugues() {
    BOT_LANG="en"
    lang_set "12345" "português"
    assert_equals "$_CONFIG_SET_VAL" "pt" "português alias should resolve to pt" || return 1
}

test_invalid_lang_shows_error() {
    BOT_LANG="en"
    lang_set "12345" "de"
    assert_contains "$MESSAGES" "de" "should mention the invalid code" || return 1
    assert_contains "$MESSAGES" "en" "should mention available: en" || return 1
    assert_contains "$MESSAGES" "pt" "should mention available: pt" || return 1
    assert_equals "$_CONFIG_SET_KEY" "" "should NOT persist invalid lang" || return 1
}

# ---- run all ----

run_test "/lang no args shows current"          test_no_args_shows_current_lang
run_test "/lang switch to pt"                   test_switch_to_portuguese
run_test "/lang switch to en"                   test_switch_to_english
run_test "/lang same language no-op"            test_same_language_noop
run_test "/lang accepts 'english' alias"        test_accepts_english_alias
run_test "/lang accepts pt-br alias"            test_accepts_portuguese_aliases
run_test "/lang accepts português"              test_accepts_portugues
run_test "/lang invalid shows error"            test_invalid_lang_shows_error

rm -rf "$TEST_TMP"

if [ "$FAILURES" -ne 0 ]; then
    exit 1
fi
