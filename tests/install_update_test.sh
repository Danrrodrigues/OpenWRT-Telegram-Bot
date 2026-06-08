#!/bin/sh
# Tests for `install.sh update` — focused on the self-update safety mechanism
# that keeps a Telegram-triggered update from killing itself mid-way.

set -u

ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)

TEST_TMP="${TMPDIR:-/tmp}/telegram-bot-install-test-$$"
mkdir -p "$TEST_TMP"

# ---- assertions ----

FAILURES=0

assert_contains() {
    case "$1" in
        *"$2"*) ;;
        *) printf 'FAIL: %s\nExpected to find: %s\n' "$3" "$2" >&2; return 1 ;;
    esac
}

assert_equals() {
    if [ "$1" != "$2" ]; then
        printf 'FAIL: %s\nExpected: %s\nActual: %s\n' "$3" "$2" "$1" >&2
        return 1
    fi
}

assert_file_exists() {
    if [ ! -f "$1" ]; then
        printf 'FAIL: %s\nFile not found: %s\n' "$2" "$1" >&2
        return 1
    fi
}

# Wait (briefly) for a file to become non-empty. The detached updater is
# launched with `&`, so its effects land asynchronously.
_wait_for() {
    f="$1"
    tries=0
    while [ "$tries" -lt 30 ]; do
        [ -s "$f" ] && return 0
        sleep 0.1 2>/dev/null || sleep 1
        tries=$((tries + 1))
    done
    return 1
}

run_test() {
    name="$1"
    shift
    if "$@"; then
        printf 'PASS: %s\n' "$name"
    else
        FAILURES=$((FAILURES + 1))
    fi
}

# Build an isolated "extracted tarball" so SCRIPT_DIR stays small and the real
# repo tree is never touched. Returns the path via stdout.
_make_extracted() {
    dir="$1"
    mkdir -p "$dir"
    cp "$ROOT_DIR/install.sh" "$dir/install.sh"
    cp "$ROOT_DIR/uninstall.sh" "$dir/uninstall.sh"
    cp -r "$ROOT_DIR/src" "$dir/src"
}

# A fake `id` that reports root so install.sh's _check_root passes as a normal
# CI user; placed first on PATH.
_make_fakebin() {
    bindir="$1"
    mkdir -p "$bindir"
    cat > "$bindir/id" <<'EOF'
#!/bin/sh
[ "$1" = "-u" ] && { echo 0; exit 0; }
exec /usr/bin/id "$@"
EOF
    chmod +x "$bindir/id"
}

# ---- test: inline update copies files before restarting ----

test_inline_copies_then_restarts() {
    case="$TEST_TMP/inline"
    rm -rf "$case"; mkdir -p "$case"
    _make_extracted "$case/extracted"
    _make_fakebin "$case/bin"

    install_dir="$case/install"
    mkdir -p "$install_dir"
    printf 'VERSION="0.0.1"\n' > "$install_dir/bot.sh"

    # Fake service records calls and proves bot.sh was already updated by the
    # time `restart` is invoked (i.e. copy happened before restart).
    service="$case/service"
    log="$case/service.log"
    : > "$log"
    cat > "$service" <<EOF
#!/bin/sh
echo "\$1" >> "$log"
if [ "\$1" = "restart" ] && grep -q '0.3.3' "$install_dir/bot.sh" 2>/dev/null; then
    echo "copied-before-restart" >> "$log"
fi
EOF
    chmod +x "$service"

    PATH="$case/bin:$PATH" \
    TGBOT_UPDATE_DETACHED=1 \
    INSTALL_DIR="$install_dir" \
    SERVICE_FILE="$service" \
        sh "$case/extracted/install.sh" update > "$case/out.log" 2>&1

    assert_file_exists "$install_dir/core/config.sh" "core files should be copied" || return 1
    assert_file_exists "$install_dir/lang/pt.sh" "lang files should be copied" || return 1
    assert_contains "$(cat "$install_dir/bot.sh")" '0.3.3' "bot.sh should be the new version" || return 1
    assert_contains "$(cat "$log")" "restart" "service should be restarted" || return 1
    assert_contains "$(cat "$log")" "copied-before-restart" "copy must happen before restart" || return 1
}

# ---- test: non-interactive update detaches via setsid and does NOT copy inline ----

test_noninteractive_detaches() {
    case="$TEST_TMP/detach"
    rm -rf "$case"; mkdir -p "$case"
    _make_extracted "$case/extracted"
    _make_fakebin "$case/bin"

    # Fake setsid just records that it was asked to relaunch the updater; it does
    # not actually run anything, so no real copy/restart happens here.
    setsid_log="$case/setsid.log"
    : > "$setsid_log"
    cat > "$case/bin/setsid" <<EOF
#!/bin/sh
echo "\$*" >> "$setsid_log"
EOF
    chmod +x "$case/bin/setsid"

    install_dir="$case/install"
    mkdir -p "$install_dir"
    printf 'VERSION="0.0.1"\n' > "$install_dir/bot.sh"

    service="$case/service"
    cat > "$service" <<'EOF'
#!/bin/sh
echo "service should not be called in detach path" >&2
exit 1
EOF
    chmod +x "$service"

    # No TGBOT_UPDATE_DETACHED and stdout redirected to a file (not a tty) → the
    # detach branch must trigger.
    PATH="$case/bin:$PATH" \
    INSTALL_DIR="$install_dir" \
    SERVICE_FILE="$service" \
    TGBOT_UPDATE_SELF_DIR="$case/self" \
        sh "$case/extracted/install.sh" update > "$case/out.log" 2>&1

    _wait_for "$setsid_log"
    assert_contains "$(cat "$setsid_log")" "install.sh update" "should relaunch update via setsid" || return 1
    # Inline copy must NOT have happened: bot.sh still the old version.
    assert_equals "$(cat "$install_dir/bot.sh")" 'VERSION="0.0.1"' "must not copy inline before detaching" || return 1
}

run_test "update: inline copies files before restart" test_inline_copies_then_restarts
run_test "update: non-interactive run detaches via setsid" test_noninteractive_detaches

rm -rf "$TEST_TMP"

if [ "$FAILURES" -ne 0 ]; then
    exit 1
fi
