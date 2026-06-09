#!/bin/sh
# Language switching command — change bot language at runtime via Telegram
# Depends on: config_set (config.sh), i18n_load (i18n.sh),
#             notify_check_version_change (notify.sh), telegram_send (telegram.sh)

lang_set() {
    local chat_id="$1"
    local args="$2"
    local new_lang input

    if [ -z "$args" ]; then
        # shellcheck disable=SC2059
        telegram_send "$chat_id" "$(printf "$T_LANG_CURRENT" "$BOT_LANG")"
        return 0
    fi

    input=$(echo "$args" | awk '{print $1}' | tr 'A-Z' 'a-z')

    case "$input" in
        en|english)    new_lang="en" ;;
        pt|pt-br|portugues|português) new_lang="pt" ;;
        *)
            # shellcheck disable=SC2059
            telegram_send "$chat_id" "$(printf "$T_LANG_INVALID" "$input")"
            return 1
            ;;
    esac

    if [ "$new_lang" = "$BOT_LANG" ]; then
        # shellcheck disable=SC2059
        telegram_send "$chat_id" "$(printf "$T_LANG_SAME" "$BOT_LANG")"
        return 0
    fi

    config_set "lang" "$new_lang"
    BOT_LANG="$new_lang"
    i18n_load
    notify_check_version_change

    # shellcheck disable=SC2059
    telegram_send "$chat_id" "$(printf "$T_LANG_CHANGED" "$BOT_LANG")"
    log_info "lang: changed to $BOT_LANG by $chat_id"
}
