#!/bin/sh
# OpenWRT Telegram Bot — pending-action store for guided multi-step flows
# (e.g. pick a device via button, then reply with free text).
#
# One file per chat in /tmp, holding "<action>:<mac>:<epoch>". Lazily expired
# on read — no background cleanup needed since files are tiny.

SESSION_PENDING_TTL="${SESSION_PENDING_TTL:-120}"
SESSION_DIR="${SESSION_DIR:-/tmp}"

_session_pending_file() {
    echo "${SESSION_DIR}/telegram-bot-pending-$1"
}

# Usage: session_set_pending <chat_id> <action> <mac>
session_set_pending() {
    local chat_id="$1"
    local action="$2"
    local mac="$3"
    printf '%s %s %s\n' "$action" "$mac" "$(date +%s)" > "$(_session_pending_file "$chat_id")"
}

# Usage: session_get_pending <chat_id>
# Echoes "<action>:<mac>" if a non-expired pending entry exists, nothing
# otherwise. Expired entries are deleted as a side effect.
session_get_pending() {
    local chat_id="$1"
    local file action mac epoch now
    file=$(_session_pending_file "$chat_id")
    [ -f "$file" ] || return 0

    read -r action mac epoch < "$file"
    now=$(date +%s)

    if [ -z "$epoch" ] || [ $((now - epoch)) -ge "$SESSION_PENDING_TTL" ]; then
        rm -f "$file"
        return 0
    fi

    printf '%s:%s\n' "$action" "$mac"
}

# Usage: session_clear_pending <chat_id>
session_clear_pending() {
    rm -f "$(_session_pending_file "$1")"
}
