#!/bin/sh
# Config read/write via UCI (OpenWRT) with flat-file fallback for testing

UCI_CONFIG="telegram-bot"
FALLBACK_CONFIG="${FALLBACK_CONFIG:-/etc/config/telegram-bot.conf}"

# Returns 0 if running on OpenWRT with uci available
_has_uci() {
    command -v uci >/dev/null 2>&1
}

config_get() {
    local key="$1"
    if _has_uci; then
        uci -q get "${UCI_CONFIG}.bot.${key}" 2>/dev/null
    else
        grep "^${key}=" "$FALLBACK_CONFIG" 2>/dev/null | cut -d'=' -f2-
    fi
}

config_set() {
    local key="$1"
    local value="$2"
    if _has_uci; then
        uci set "${UCI_CONFIG}.bot.${key}=${value}"
        uci commit "$UCI_CONFIG"
    else
        if grep -q "^${key}=" "$FALLBACK_CONFIG" 2>/dev/null; then
            sed -i "s|^${key}=.*|${key}=${value}|" "$FALLBACK_CONFIG"
        else
            echo "${key}=${value}" >> "$FALLBACK_CONFIG"
        fi
    fi
}

# List config (for blocked/limited lists)
config_get_list() {
    local key="$1"
    if _has_uci; then
        uci -q get "${UCI_CONFIG}.rules.${key}" 2>/dev/null | tr ' ' '\n'
    else
        grep "^${key}\[\]=" "$FALLBACK_CONFIG" 2>/dev/null | cut -d'=' -f2-
    fi
}

config_add_list() {
    local key="$1"
    local value="$2"
    if _has_uci; then
        uci -q add_list "${UCI_CONFIG}.rules.${key}=${value}"
        uci commit "$UCI_CONFIG"
    else
        echo "${key}[]=${value}" >> "$FALLBACK_CONFIG"
    fi
}

config_del_list() {
    local key="$1"
    local value="$2"
    if _has_uci; then
        uci -q del_list "${UCI_CONFIG}.rules.${key}=${value}"
        uci commit "$UCI_CONFIG"
    else
        sed -i "/^${key}\[\]=${value}$/d" "$FALLBACK_CONFIG" 2>/dev/null || true
    fi
}

# Load all config into env vars with defaults
config_load() {
    BOT_TOKEN=$(config_get "token")
    BOT_CHAT_IDS=$(config_get "chat_ids")
    BOT_MODE=$(config_get "mode")
    BOT_ALERTS=$(config_get "alerts")
    BOT_ALERT_MODE=$(config_get "alert_mode")
    BOT_POLL_INTERVAL=$(config_get "poll_interval")
    LOG_LEVEL=$(config_get "log_level")

    # Defaults
    BOT_MODE="${BOT_MODE:-daemon}"
    BOT_ALERTS="${BOT_ALERTS:-1}"
    BOT_ALERT_MODE="${BOT_ALERT_MODE:-all}"
    BOT_POLL_INTERVAL="${BOT_POLL_INTERVAL:-30}"
    LOG_LEVEL="${LOG_LEVEL:-info}"
}

# Returns 0 if chat_id is authorized
config_is_authorized() {
    local chat_id="$1"
    [ -z "$BOT_CHAT_IDS" ] && return 1
    echo "$BOT_CHAT_IDS" | tr ' ' '\n' | grep -qx "$chat_id"
}
