#!/bin/sh
# OpenWRT Telegram Bot — inline keyboard buttons and callback queries
# shellcheck source=telegram.sh

# Escape a button label for embedding in a JSON string.
_keyboard_json_escape() {
    printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

# Build an inline_keyboard JSON array, one button per row, from
# "label|callback_data" arguments.
# Usage: keyboard_build_json "label1|data1" "label2|data2" ...
keyboard_build_json() {
    local json sep arg label data
    json='['
    sep=''
    for arg in "$@"; do
        label=$(_keyboard_json_escape "${arg%%|*}")
        data=$(_keyboard_json_escape "${arg#*|}")
        json="${json}${sep}[{\"text\":\"${label}\",\"callback_data\":\"${data}\"}]"
        sep=','
    done
    json="${json}]"
    printf '%s' "$json"
}

# Send a message with an inline keyboard attached.
# Usage: telegram_send_keyboard <chat_id> <text> "label1|data1" ...
telegram_send_keyboard() {
    local chat_id="$1"
    local text="$2"
    shift 2
    local keyboard ok desc
    [ -z "$BOT_TOKEN" ] && { log_error "BOT_TOKEN not set"; return 1; }

    keyboard=$(keyboard_build_json "$@")

    curl -s --max-time 10 \
        -X POST "${TELEGRAM_API}${BOT_TOKEN}/sendMessage" \
        -d "chat_id=${chat_id}" \
        --data-urlencode "text=${text}" \
        -d "parse_mode=HTML" \
        --data-urlencode "reply_markup={\"inline_keyboard\":${keyboard}}" \
        > "$SEND_RESPONSE_FILE" 2>/dev/null

    ok=$(jsonfilter -i "$SEND_RESPONSE_FILE" -e '@.ok' 2>/dev/null)
    if [ "$ok" != "true" ]; then
        desc=$(jsonfilter -i "$SEND_RESPONSE_FILE" -e '@.description' 2>/dev/null)
        log_error "sendMessage (keyboard) failed: ${desc:-unknown error}"
        return 1
    fi
    return 0
}

# Edit an existing message's text, dropping any keyboard it had.
# Usage: telegram_edit_message <chat_id> <message_id> <text>
telegram_edit_message() {
    local chat_id="$1"
    local message_id="$2"
    local text="$3"
    [ -z "$BOT_TOKEN" ] && { log_error "BOT_TOKEN not set"; return 1; }

    curl -s --max-time 10 \
        -X POST "${TELEGRAM_API}${BOT_TOKEN}/editMessageText" \
        -d "chat_id=${chat_id}" \
        -d "message_id=${message_id}" \
        --data-urlencode "text=${text}" \
        -d "parse_mode=HTML" \
        > "$SEND_RESPONSE_FILE" 2>/dev/null
    return 0
}

# Acknowledge a callback query so the client stops showing a loading spinner.
# Usage: telegram_answer_callback <callback_id> [text]
telegram_answer_callback() {
    local callback_id="$1"
    local text="${2:-}"
    [ -z "$BOT_TOKEN" ] && { log_error "BOT_TOKEN not set"; return 1; }

    curl -s --max-time 10 \
        -X POST "${TELEGRAM_API}${BOT_TOKEN}/answerCallbackQuery" \
        -d "callback_query_id=${callback_id}" \
        --data-urlencode "text=${text}" \
        > "$SEND_RESPONSE_FILE" 2>/dev/null
    return 0
}
