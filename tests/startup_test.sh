#!/bin/sh
# Startup integrity — verifies bot.sh can load all its modules without errors.
# A sourced file that is missing causes sh to abort immediately, which silently
# bricks a remote device after /update with no way to recover remotely.

set -u

ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)
SRC_DIR="$ROOT_DIR/src"

FAILURES=0

run_test() {
    name="$1"
    shift
    if "$@"; then
        printf 'PASS: %s\n' "$name"
    else
        FAILURES=$((FAILURES + 1))
    fi
}

# Runs bot.sh --help with -e so a missing sourced file causes immediate exit.
# On OpenWRT (BusyBox ash) a missing source always aborts; -e enforces the same
# in bash/dash so CI catches the same failure the router would see.
test_bot_help_loads_cleanly() {
    err=$(sh -e "$SRC_DIR/bot.sh" --help 2>&1)
    rc=$?
    if [ "$rc" -ne 0 ]; then
        printf 'FAIL: bot.sh --help exited %d:\n%s\n' "$rc" "$err" >&2
        return 1
    fi
}

# Static check: parse bot.sh for SCRIPT_DIR-relative source paths and verify
# each file exists. Gives a precise error message naming the missing file.
test_all_sourced_files_exist() {
    failed=0
    # Extract relative paths from lines like: . "${SCRIPT_DIR}/some/file.sh"
    while IFS= read -r rel; do
        [ -z "$rel" ] && continue
        if [ ! -f "$SRC_DIR/$rel" ]; then
            printf 'FAIL: sourced file missing: %s\n' "$rel" >&2
            failed=1
        fi
    done << EOF
$(grep '^\. "\${SCRIPT_DIR}/' "$SRC_DIR/bot.sh" | sed 's|.*\${SCRIPT_DIR}/||; s|".*||')
EOF
    return $failed
}

run_test "startup: bot.sh --help loads all modules without error" test_bot_help_loads_cleanly
run_test "startup: every file sourced by bot.sh exists" test_all_sourced_files_exist

if [ "$FAILURES" -ne 0 ]; then
    exit 1
fi
