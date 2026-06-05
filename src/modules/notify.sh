#!/bin/sh
# Update notifications:
#  - on version change: register the Telegram command menu and announce the update
#  - daily at 08:00 (router local time): suggest an update when a newer version exists
# Depends on: telegram_set_commands, telegram_send (telegram.sh),
#             _updater_remote_version (updater.sh), i18n strings (i18n.sh),
#             VERSION and BOT_CHAT_IDS (bot context).

NOTIFY_STATE_DIR="${NOTIFY_STATE_DIR:-/usr/lib/telegram-bot/.state}"
NOTIFY_SEEN_VERSION_FILE="${NOTIFY_STATE_DIR}/seen_version"
NOTIFY_LAST_CHECK_FILE="${NOTIFY_STATE_DIR}/last_update_check"
NOTIFY_DAILY_HOUR="${NOTIFY_DAILY_HOUR:-8}"

_notify_broadcast() {
    local msg="$1"
    local cid
    # shellcheck disable=SC2086
    for cid in $BOT_CHAT_IDS; do
        telegram_send "$cid" "$msg"
    done
}

# Runs once per startup. Acts only when the installed version differs from the
# last version we registered the menu / announced for.
notify_check_version_change() {
    mkdir -p "$NOTIFY_STATE_DIR" 2>/dev/null || true

    # State tracks both version and language so a runtime language change also
    # refreshes the menu. Stored as "VERSION|LANG".
    local seen current seen_version
    seen=$(cat "$NOTIFY_SEEN_VERSION_FILE" 2>/dev/null)
    current="${VERSION}|${BOT_LANG:-en}"

    [ "$seen" = "$current" ] && return 0

    # (Re)register the command menu for the current version/language. Persist the
    # new state only on success, so a transient Telegram/API failure is retried
    # on the next start instead of being silently marked as handled.
    if ! telegram_set_commands; then
        log_warn "notify: command menu registration failed; will retry next start"
        return 1
    fi

    # Announce only on a real version upgrade — not on a fresh install and not on
    # a language-only change.
    seen_version="${seen%%|*}"
    if [ -n "$seen_version" ] && [ "$seen_version" != "$VERSION" ]; then
        # T_* come from the sourced language file (see i18n.sh).
        # shellcheck disable=SC2059,SC2154
        _notify_broadcast "$(printf "$T_UPDATED" "$VERSION")"
        log_info "notify: announced update $seen_version -> $VERSION"
    elif [ -z "$seen" ]; then
        log_info "notify: first run, registered command menu for v$VERSION (${BOT_LANG:-en})"
    else
        log_info "notify: refreshed command menu (lang=${BOT_LANG:-en})"
    fi

    echo "$current" > "$NOTIFY_SEEN_VERSION_FILE"
}

# Self-gating daily check. Safe to call on every loop iteration / cron run:
# it does work at most once per day, at or after NOTIFY_DAILY_HOUR.
notify_daily_update_check() {
    mkdir -p "$NOTIFY_STATE_DIR" 2>/dev/null || true

    local hour today last
    hour=$(date +%H)
    today=$(date +%Y-%m-%d)
    last=$(cat "$NOTIFY_LAST_CHECK_FILE" 2>/dev/null)

    # Strip a possible leading zero so arithmetic comparison is safe (e.g. "08"
    # would be read as invalid octal). Parameter expansion is portable to ash.
    hour=${hour#0}
    [ -z "$hour" ] && hour=0

    [ "$hour" -ge "$NOTIFY_DAILY_HOUR" ] || return 0
    [ "$last" = "$today" ] && return 0

    # Record the attempt before the network call so a failure does not retry
    # repeatedly the same day; it naturally retries tomorrow.
    echo "$today" > "$NOTIFY_LAST_CHECK_FILE"

    local remote
    remote=$(_updater_remote_version)
    [ -z "$remote" ] && return 0
    [ "$remote" = "$VERSION" ] && return 0

    # shellcheck disable=SC2059,SC2154
    _notify_broadcast "$(printf "$T_UPDATE_AVAILABLE" "$remote" "$VERSION")"
    log_info "notify: suggested update $VERSION -> $remote"
}
