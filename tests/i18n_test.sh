#!/bin/sh

set -u

ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)

# i18n.sh resolves language files relative to I18N_DIR (default ${SCRIPT_DIR}/lang)
I18N_DIR="$ROOT_DIR/src/lang"

. "$ROOT_DIR/src/core/i18n.sh"

# ---- assertions ----

assert_equals() {
    if [ "$1" != "$2" ]; then
        printf 'FAIL: %s\nExpected: %s\nActual: %s\n' "$3" "$2" "$1" >&2
        return 1
    fi
}

assert_nonempty() {
    if [ -z "$1" ]; then
        printf 'FAIL: %s\n(value was empty)\n' "$2" >&2
        return 1
    fi
}

assert_contains() {
    case "$1" in
        *"$2"*) ;;
        *) printf 'FAIL: %s\nExpected to find: %s\n' "$3" "$2" >&2; return 1 ;;
    esac
}

FAILURES=0

run_test() {
    local name="$1"
    shift
    # Reset the variables the language files set
    T_UPDATED=""
    T_UPDATE_AVAILABLE=""
    I18N_COMMANDS=""
    if "$@"; then
        printf 'PASS: %s\n' "$name"
    else
        FAILURES=$((FAILURES + 1))
    fi
}

# ---- tests ----

test_loads_english() {
    BOT_LANG="en"
    i18n_load
    assert_nonempty "$T_UPDATED" "en T_UPDATED defined" || return 1
    assert_contains "$T_UPDATED" "updated" "en uses English wording" || return 1
    assert_contains "$I18N_COMMANDS" "update|" "command list includes update" || return 1
    assert_contains "$I18N_COMMANDS" "rollback|" "command list includes rollback" || return 1
}

test_loads_portuguese() {
    BOT_LANG="pt"
    i18n_load
    assert_nonempty "$T_UPDATED" "pt T_UPDATED defined" || return 1
    assert_contains "$T_UPDATED" "atualizado" "pt uses Portuguese wording" || return 1
    assert_contains "$I18N_COMMANDS" "Listar dispositivos" "pt descriptions present" || return 1
}

test_unknown_lang_falls_back_to_english() {
    BOT_LANG="zz"
    i18n_load
    assert_contains "$T_UPDATED" "updated" "unknown lang falls back to English" || return 1
}

test_empty_lang_defaults_to_english() {
    BOT_LANG=""
    i18n_load
    assert_contains "$T_UPDATED" "updated" "empty lang defaults to English" || return 1
}

test_both_languages_define_same_keys() {
    BOT_LANG="en"; i18n_load
    en_t="$T_UPDATED"; en_a="$T_UPDATE_AVAILABLE"; en_c="$I18N_COMMANDS"
    BOT_LANG="pt"; i18n_load
    assert_nonempty "$en_t" "en T_UPDATED set" || return 1
    assert_nonempty "$en_a" "en T_UPDATE_AVAILABLE set" || return 1
    assert_nonempty "$en_c" "en I18N_COMMANDS set" || return 1
    assert_nonempty "$T_UPDATED" "pt T_UPDATED set" || return 1
    assert_nonempty "$T_UPDATE_AVAILABLE" "pt T_UPDATE_AVAILABLE set" || return 1
    assert_nonempty "$I18N_COMMANDS" "pt I18N_COMMANDS set" || return 1
}

test_command_count_matches_between_languages() {
    BOT_LANG="en"; i18n_load
    en_count=$(printf '%s\n' "$I18N_COMMANDS" | grep -c '|')
    BOT_LANG="pt"; i18n_load
    pt_count=$(printf '%s\n' "$I18N_COMMANDS" | grep -c '|')
    assert_equals "$pt_count" "$en_count" "both languages define the same number of commands" || return 1
}

# ---- run all ----

run_test "i18n: loads English"                       test_loads_english
run_test "i18n: loads Portuguese"                    test_loads_portuguese
run_test "i18n: unknown language falls back to en"   test_unknown_lang_falls_back_to_english
run_test "i18n: empty language defaults to en"       test_empty_lang_defaults_to_english
run_test "i18n: both languages define same keys"     test_both_languages_define_same_keys
run_test "i18n: command count matches across langs"  test_command_count_matches_between_languages

if [ "$FAILURES" -ne 0 ]; then
    exit 1
fi
