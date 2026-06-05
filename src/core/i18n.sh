#!/bin/sh
# Minimal i18n loader.
# Sources the language file selected by BOT_LANG, defining T_* message templates
# and I18N_COMMANDS. Falls back to English when the requested language is missing.
# shellcheck source=../lang/en.sh

I18N_DIR="${I18N_DIR:-${SCRIPT_DIR}/lang}"

i18n_load() {
    local lang file
    lang="${BOT_LANG:-en}"
    file="${I18N_DIR}/${lang}.sh"
    if [ ! -f "$file" ]; then
        file="${I18N_DIR}/en.sh"
    fi
    # shellcheck disable=SC1090
    . "$file"
}
