#!/bin/sh

set -u

ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)

TEST_TMP="${TMPDIR:-/tmp}/telegram-bot-updater-test-$$"
mkdir -p "$TEST_TMP"

# Bot context required by the module
VERSION="0.2.2"
BOT_CHAT_IDS="12345"
BOT_TOKEN="test-token"

MESSAGES=""

telegram_send() {
    local chat_id="$1"
    local text="$2"
    MESSAGES="${MESSAGES}${chat_id}|${text}
"
}

log_info()  { :; }
log_error() { :; }
log_warn()  { :; }

# Source the module under test
. "$ROOT_DIR/src/modules/updater.sh"

# Override module paths to keep everything inside TEST_TMP
UPDATER_INSTALL_DIR="$TEST_TMP/install"
UPDATER_BACKUP_DIR="$TEST_TMP/backup"
UPDATER_BACKUP_VERSION_FILE="$TEST_TMP/backup.version"
UPDATER_TMP_DIR="$TEST_TMP/update-tmp"
UPDATER_RAW_URL="file:///dev/null"
UPDATER_ARCHIVE_URL="file:///dev/null"

# Controlled remote version for /update tests
_REMOTE_VERSION_MOCK=""
_updater_remote_version() { echo "$_REMOTE_VERSION_MOCK"; }

# Track service restarts without actually doing them
_RESTART_CALLED=0
_updater_restart_service() { _RESTART_CALLED=1; }

# Prevent any real downloads in background subshells
wget() { return 1; }

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

assert_not_contains() {
    local haystack="$1"
    local needle="$2"
    local description="$3"

    case "$haystack" in
        *"$needle"*)
            printf 'FAIL: %s\nDid not expect to find: %s\n' "$description" "$needle" >&2
            return 1
            ;;
        *) ;;
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

assert_file_exists() {
    local path="$1"
    local description="$2"

    if [ ! -f "$path" ]; then
        printf 'FAIL: %s\nFile not found: %s\n' "$description" "$path" >&2
        return 1
    fi
}

FAILURES=0

run_test() {
    local name="$1"
    shift
    MESSAGES=""
    _RESTART_CALLED=0
    if "$@"; then
        printf 'PASS: %s\n' "$name"
    else
        FAILURES=$((FAILURES + 1))
    fi
}

# ---- /update tests ----

test_already_up_to_date() {
    _REMOTE_VERSION_MOCK="0.2.2"
    updater_check "12345" ""
    assert_contains "$MESSAGES" "mais recente" "should report already on latest" || return 1
    assert_contains "$MESSAGES" "0.2.2" "should include current version" || return 1
}

test_update_available() {
    _REMOTE_VERSION_MOCK="0.3.0"
    updater_check "12345" ""
    assert_contains "$MESSAGES" "0.2.2" "should show current version" || return 1
    assert_contains "$MESSAGES" "0.3.0" "should show remote version" || return 1
    assert_contains "$MESSAGES" "confirm" "should prompt for confirmation" || return 1
}

test_network_failure() {
    _REMOTE_VERSION_MOCK=""
    updater_check "12345" ""
    assert_contains "$MESSAGES" "internet" "should mention internet connectivity" || return 1
    assert_not_contains "$MESSAGES" "confirm" "should not prompt to update when offline" || return 1
}

test_update_confirm_sends_in_progress_message() {
    updater_check "12345" "confirm"
    assert_contains "$MESSAGES" "Atualizando" "should send update in progress message" || return 1
}

# ---- /rollback tests ----

test_rollback_no_backup() {
    rm -f "$UPDATER_BACKUP_VERSION_FILE"
    updater_rollback "12345" ""
    assert_contains "$MESSAGES" "backup" "should mention no backup available" || return 1
    assert_not_contains "$MESSAGES" "confirm" "should not prompt when no backup exists" || return 1
}

test_rollback_shows_versions() {
    echo "0.2.1" > "$UPDATER_BACKUP_VERSION_FILE"
    updater_rollback "12345" ""
    assert_contains "$MESSAGES" "0.2.1" "should show backup version" || return 1
    assert_contains "$MESSAGES" "0.2.2" "should show current version" || return 1
    assert_contains "$MESSAGES" "confirm" "should prompt for confirmation" || return 1
}

test_rollback_confirm_sends_restore_message() {
    echo "0.2.1" > "$UPDATER_BACKUP_VERSION_FILE"
    updater_rollback "12345" "confirm"
    assert_contains "$MESSAGES" "Restaurando" "should send restoring message" || return 1
    assert_contains "$MESSAGES" "0.2.1" "should include backup version in message" || return 1
}

test_rollback_no_confirm_skips_restore() {
    echo "0.2.1" > "$UPDATER_BACKUP_VERSION_FILE"
    updater_rollback "12345" ""
    assert_not_contains "$MESSAGES" "Restaurando" "dry run should not send restore message" || return 1
}

# ---- backup tests ----

test_backup_creates_version_file() {
    rm -f "$UPDATER_BACKUP_VERSION_FILE"
    mkdir -p "${UPDATER_INSTALL_DIR}/core" "${UPDATER_INSTALL_DIR}/modules"
    printf '#!/bin/sh\n' > "${UPDATER_INSTALL_DIR}/bot.sh"
    _updater_backup_current
    assert_file_exists "$UPDATER_BACKUP_VERSION_FILE" "backup version file should be created" || return 1
    assert_equals "$(cat "$UPDATER_BACKUP_VERSION_FILE")" "0.2.2" "version file should contain current version" || return 1
}

test_backup_copies_scripts() {
    rm -rf "$UPDATER_BACKUP_DIR"
    mkdir -p "${UPDATER_INSTALL_DIR}/core" "${UPDATER_INSTALL_DIR}/modules"
    printf '#!/bin/sh\n' > "${UPDATER_INSTALL_DIR}/bot.sh"
    printf '#!/bin/sh\n' > "${UPDATER_INSTALL_DIR}/core/config.sh"
    printf '#!/bin/sh\n' > "${UPDATER_INSTALL_DIR}/modules/devices.sh"
    _updater_backup_current
    assert_file_exists "${UPDATER_BACKUP_DIR}/bot.sh" "backup should include bot.sh" || return 1
    assert_file_exists "${UPDATER_BACKUP_DIR}/core/config.sh" "backup should include core/config.sh" || return 1
    assert_file_exists "${UPDATER_BACKUP_DIR}/modules/devices.sh" "backup should include modules/devices.sh" || return 1
}

test_backup_overwrites_previous() {
    mkdir -p "${UPDATER_INSTALL_DIR}/core" "${UPDATER_INSTALL_DIR}/modules"
    printf '#!/bin/sh\n' > "${UPDATER_INSTALL_DIR}/bot.sh"
    echo "0.1.0" > "$UPDATER_BACKUP_VERSION_FILE"
    _updater_backup_current
    assert_equals "$(cat "$UPDATER_BACKUP_VERSION_FILE")" "0.2.2" "backup should overwrite stale version file" || return 1
}

# ---- run all ----

run_test "/update: already on latest"              test_already_up_to_date
run_test "/update: shows versions when behind"     test_update_available
run_test "/update: network failure"                test_network_failure
run_test "/update confirm: sends in-progress msg"  test_update_confirm_sends_in_progress_message
run_test "/rollback: no backup available"          test_rollback_no_backup
run_test "/rollback: shows backup and current ver" test_rollback_shows_versions
run_test "/rollback confirm: sends restore msg"    test_rollback_confirm_sends_restore_message
run_test "/rollback: no confirm skips restore"     test_rollback_no_confirm_skips_restore
run_test "backup: creates version file"            test_backup_creates_version_file
run_test "backup: copies scripts to backup dir"    test_backup_copies_scripts
run_test "backup: overwrites previous backup"      test_backup_overwrites_previous

rm -rf "$TEST_TMP"

if [ "$FAILURES" -ne 0 ]; then
    exit 1
fi
