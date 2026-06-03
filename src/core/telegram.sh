#!/bin/sh
# Telegram Bot API — send messages and poll for updates

TELEGRAM_API="https://api.telegram.org/bot"
TELEGRAM_TIMEOUT=30
UPDATES_FILE="/tmp/telegram-bot-updates.json"

# Send a plain text message to a chat
# Usage: telegram_send <chat_id> <text>
telegram_send() {
    local chat_id="$1"
    local text="$2"
    [ -z "$BOT_TOKEN" ] && { log_error "BOT_TOKEN not set"; return 1; }
    curl -s --max-time 10 \
        -X POST "${TELEGRAM_API}${BOT_TOKEN}/sendMessage" \
        -d "chat_id=${chat_id}" \
        --data-urlencode "text=${text}" \
        -d "parse_mode=Markdown" \
        > /dev/null
}

# Send message and return response body (for error checking)
telegram_send_verbose() {
    local chat_id="$1"
    local text="$2"
    [ -z "$BOT_TOKEN" ] && { log_error "BOT_TOKEN not set"; return 1; }
    curl -s --max-time 10 \
        -X POST "${TELEGRAM_API}${BOT_TOKEN}/sendMessage" \
        -d "chat_id=${chat_id}" \
        --data-urlencode "text=${text}" \
        -d "parse_mode=Markdown"
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

    local count
    count=$(jsonfilter -i "$UPDATES_FILE" -e '@.result' 2>/dev/null | jsonfilter -e 'length' 2>/dev/null) || count=0
    echo "${count:-0}"
}

# Extract field from update at given index
# Usage: telegram_update_field <index> <field>
# Field examples: update_id, message.chat.id, message.text, message.from.first_name
telegram_update_field() {
    local idx="$1"
    local field="$2"
    jsonfilter -i "$UPDATES_FILE" -e "@.result[${idx}].${field}" 2>/dev/null
}

# Returns the highest update_id in the current batch (for offset advancement)
telegram_last_update_id() {
    local count="$1"
    local last_idx=$(( count - 1 ))
    telegram_update_field "$last_idx" "update_id"
}
