#!/bin/sh
# Telegram Bot API — send messages and poll for updates
# shellcheck source=logger.sh

TELEGRAM_API="https://api.telegram.org/bot"
TELEGRAM_TIMEOUT=30
UPDATES_FILE="/tmp/telegram-bot-updates.json"
SEND_RESPONSE_FILE="/tmp/telegram-bot-send-response.json"

# Send an HTML-formatted message to a chat
# Usage: telegram_send <chat_id> <text>
telegram_send() {
    local chat_id="$1"
    local text="$2"
    local ok desc
    [ -z "$BOT_TOKEN" ] && { log_error "BOT_TOKEN not set"; return 1; }

    curl -s --max-time 10 \
        -X POST "${TELEGRAM_API}${BOT_TOKEN}/sendMessage" \
        -d "chat_id=${chat_id}" \
        --data-urlencode "text=${text}" \
        -d "parse_mode=HTML" \
        > "$SEND_RESPONSE_FILE" 2>/dev/null

    # Log if Telegram returned an error
    ok=$(jsonfilter -i "$SEND_RESPONSE_FILE" -e '@.ok' 2>/dev/null)
    if [ "$ok" != "true" ]; then
        desc=$(jsonfilter -i "$SEND_RESPONSE_FILE" -e '@.description' 2>/dev/null)
        log_error "sendMessage failed: ${desc:-unknown error}"
        return 1
    fi
    return 0
}

# Long-poll for updates. Writes JSON to UPDATES_FILE.
# Usage: telegram_get_updates <offset>
# Returns: number of updates received
telegram_get_updates() {
    local offset="${1:-0}"
    [ -z "$BOT_TOKEN" ] && { log_error "BOT_TOKEN not set"; return 1; }
    curl -s --max-time $((TELEGRAM_TIMEOUT + 5)) \
        "${TELEGRAM_API}${BOT_TOKEN}/getUpdates?offset=${offset}&timeout=${TELEGRAM_TIMEOUT}&allowed_updates=message" \
        > "$UPDATES_FILE" 2>/dev/null

    # Count by extracting all update_ids (one per line)
    local count
    count=$(jsonfilter -i "$UPDATES_FILE" -e '@.result[*].update_id' 2>/dev/null | wc -l | tr -d ' ')
    echo "${count:-0}"
}

# Extract field from update at given index
# Usage: telegram_update_field <index> <field>
telegram_update_field() {
    local idx="$1"
    local field="$2"
    jsonfilter -i "$UPDATES_FILE" -e "@.result[${idx}].${field}" 2>/dev/null
}

# Returns the last update_id in the current batch
telegram_last_update_id() {
    jsonfilter -i "$UPDATES_FILE" -e '@.result[*].update_id' 2>/dev/null | tail -1
}
