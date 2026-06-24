#!/bin/sh
# Telegram Bot API — send messages and poll for updates
# shellcheck source=logger.sh

TELEGRAM_API="https://api.telegram.org/bot"
TELEGRAM_TIMEOUT=30
UPDATES_FILE="/tmp/telegram-bot-updates.json"
SEND_RESPONSE_FILE="/tmp/telegram-bot-send-response.json"

# Send an HTML-formatted message to a chat.
# If TELEGRAM_REDIRECT_CHAT_ID matches chat_id, the message is sent by
# editing TELEGRAM_REDIRECT_MESSAGE_ID instead — used by the inline-keyboard
# callback dispatcher so existing handlers can update the original message
# (removing its buttons) without any handler code being keyboard-aware.
# Usage: telegram_send <chat_id> <text>
telegram_send() {
    local chat_id="$1"
    local text="$2"
    local ok desc redirect_message_id
    [ -z "$BOT_TOKEN" ] && { log_error "BOT_TOKEN not set"; return 1; }

    if [ -n "${TELEGRAM_REDIRECT_CHAT_ID:-}" ] && [ "$chat_id" = "$TELEGRAM_REDIRECT_CHAT_ID" ]; then
        redirect_message_id="$TELEGRAM_REDIRECT_MESSAGE_ID"
        TELEGRAM_REDIRECT_CHAT_ID=""
        TELEGRAM_REDIRECT_MESSAGE_ID=""
        telegram_edit_message "$chat_id" "$redirect_message_id" "$text"
        return $?
    fi

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

# Register the bot command menu shown in Telegram clients (setMyCommands).
# Reads command definitions from I18N_COMMANDS ("command|description" per line).
telegram_set_commands() {
    # I18N_COMMANDS comes from the sourced language file (see i18n.sh).
    local commands="${I18N_COMMANDS:-}"
    [ -z "$BOT_TOKEN" ] && { log_error "BOT_TOKEN not set"; return 1; }
    [ -z "$commands" ] && { log_error "I18N_COMMANDS not set"; return 1; }

    local json sep cmd desc ok
    json='{"commands":['
    sep=""
    while IFS='|' read -r cmd desc; do
        [ -z "$cmd" ] && continue
        json="${json}${sep}{\"command\":\"${cmd}\",\"description\":\"${desc}\"}"
        sep=","
    done <<EOF
${commands}
EOF
    json="${json}]}"

    curl -s --max-time 10 \
        -X POST "${TELEGRAM_API}${BOT_TOKEN}/setMyCommands" \
        -H "Content-Type: application/json" \
        -d "$json" \
        > "$SEND_RESPONSE_FILE" 2>/dev/null

    ok=$(jsonfilter -i "$SEND_RESPONSE_FILE" -e '@.ok' 2>/dev/null)
    if [ "$ok" != "true" ]; then
        local desc_err
        desc_err=$(jsonfilter -i "$SEND_RESPONSE_FILE" -e '@.description' 2>/dev/null)
        log_error "setMyCommands failed: ${desc_err:-unknown error}"
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
        -X POST "${TELEGRAM_API}${BOT_TOKEN}/getUpdates" \
        -d "offset=${offset}" \
        -d "timeout=${TELEGRAM_TIMEOUT}" \
        --data-urlencode 'allowed_updates=["message","callback_query"]' \
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
