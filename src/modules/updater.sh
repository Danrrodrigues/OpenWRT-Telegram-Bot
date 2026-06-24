#!/bin/sh
# Remote update and rollback commands

UPDATER_INSTALL_DIR="/usr/lib/telegram-bot"
UPDATER_BACKUP_DIR="/usr/lib/telegram-bot-backup"
UPDATER_BACKUP_VERSION_FILE="/usr/lib/telegram-bot-backup.version"
UPDATER_TMP_DIR="/tmp/telegram-bot-update"
UPDATER_RAW_URL="https://raw.githubusercontent.com/Danrrodrigues/OpenWRT-Telegram-Bot/main/src/bot.sh"
UPDATER_ARCHIVE_URL="https://github.com/Danrrodrigues/OpenWRT-Telegram-Bot/archive/refs/heads/main.tar.gz"

_updater_remote_version() {
    wget -q --timeout=10 -O - "$UPDATER_RAW_URL" 2>/dev/null \
        | grep '^VERSION=' | cut -d'"' -f2 | head -1
}

_updater_backup_current() {
    rm -rf "$UPDATER_BACKUP_DIR"
    cp -r "$UPDATER_INSTALL_DIR" "$UPDATER_BACKUP_DIR"
    echo "$VERSION" > "$UPDATER_BACKUP_VERSION_FILE"
    log_info "updater: backed up version $VERSION"
}

_updater_restart_service() {
    # This runs inside a background subshell of the bot, i.e. a child of the
    # telegram-bot service. A plain restart would have procd kill this subshell
    # along with the service before the restart completes. Detach the restart
    # into a NEW session (setsid) so it survives the service going down.
    if command -v setsid >/dev/null 2>&1; then
        setsid sh -c '
            if [ -f /etc/init.d/telegram-bot ]; then
                /etc/init.d/telegram-bot restart
            else
                /etc/init.d/cron restart
            fi
        ' >/dev/null 2>&1 </dev/null &
    elif [ -f "/etc/init.d/telegram-bot" ]; then
        /etc/init.d/telegram-bot restart 2>/dev/null || true
    else
        /etc/init.d/cron restart 2>/dev/null || true
    fi
}

# Command: /update [confirm]
updater_check() {
    local chat_id="$1"
    local args="$2"

    if [ "$args" = "confirm" ]; then
        updater_run "$chat_id"
        return
    fi

    telegram_send "$chat_id" "$T_CHECKING"

    local remote_version
    remote_version=$(_updater_remote_version)

    if [ -z "$remote_version" ]; then
        telegram_send "$chat_id" "$T_CHECK_FAIL"
        return 1
    fi

    if [ "$VERSION" = "$remote_version" ]; then
        # shellcheck disable=SC2059
        telegram_send "$chat_id" "$(printf "$T_UP_TO_DATE" "$VERSION")"
        return 0
    fi

    # shellcheck disable=SC2059
    telegram_send_keyboard "$chat_id" "$(printf "$T_UPDATE_AVAILABLE_CMD" "$VERSION" "$remote_version")" \
        "${T_BTN_CONFIRM}|update:confirm" "${T_BTN_CANCEL}|cancel:noop"
}

updater_run() {
    local chat_id="$1"

    telegram_send "$chat_id" "$T_UPDATING"
    log_info "updater: starting update from $VERSION"

    (
        sleep 3
        _updater_backup_current
        rm -rf "$UPDATER_TMP_DIR"
        mkdir -p "$UPDATER_TMP_DIR"
        if wget -q --timeout=60 -O "${UPDATER_TMP_DIR}/bot.tar.gz" "$UPDATER_ARCHIVE_URL" 2>/dev/null; then
            tar xzf "${UPDATER_TMP_DIR}/bot.tar.gz" -C "$UPDATER_TMP_DIR" 2>/dev/null
            update_dir="${UPDATER_TMP_DIR}/OpenWRT-Telegram-Bot-main"
            if [ -d "$update_dir" ]; then
                sh "${update_dir}/install.sh" update
            else
                # shellcheck disable=SC2086
                for cid in $BOT_CHAT_IDS; do
                    telegram_send "$cid" "$T_UPDATE_FAIL_EXTRACT"
                done
            fi
        else
            # shellcheck disable=SC2086
            for cid in $BOT_CHAT_IDS; do
                    telegram_send "$cid" "$T_UPDATE_FAIL_DOWNLOAD"
            done
        fi
        rm -rf "$UPDATER_TMP_DIR"
    ) &
}

# Command: /rollback [confirm]
updater_rollback() {
    local chat_id="$1"
    local args="$2"

    local backup_version
    backup_version=$(cat "$UPDATER_BACKUP_VERSION_FILE" 2>/dev/null)

    if [ -z "$backup_version" ]; then
        telegram_send "$chat_id" "$T_ROLLBACK_NONE"
        return 0
    fi

    if [ "$args" = "confirm" ]; then
        _updater_do_rollback "$chat_id" "$backup_version"
        return
    fi

    # shellcheck disable=SC2059
    telegram_send_keyboard "$chat_id" "$(printf "$T_ROLLBACK_AVAILABLE" "$backup_version" "$VERSION")" \
        "${T_BTN_CONFIRM}|rollback:confirm" "${T_BTN_CANCEL}|cancel:noop"
}

_updater_do_rollback() {
    local chat_id="$1"
    local backup_version="$2"

    # shellcheck disable=SC2059
    telegram_send "$chat_id" "$(printf "$T_ROLLBACK_RUNNING" "$backup_version")"
    log_info "updater: rolling back from $VERSION to $backup_version"

    (
        sleep 3
        cp "${UPDATER_BACKUP_DIR}/bot.sh" "${UPDATER_INSTALL_DIR}/bot.sh" 2>/dev/null || true
        for f in "${UPDATER_BACKUP_DIR}/core/"*.sh; do
            if [ -f "$f" ]; then
                cp "$f" "${UPDATER_INSTALL_DIR}/core/" 2>/dev/null || true
            fi
        done
        for f in "${UPDATER_BACKUP_DIR}/modules/"*.sh; do
            if [ -f "$f" ]; then
                cp "$f" "${UPDATER_INSTALL_DIR}/modules/" 2>/dev/null || true
            fi
        done
        cp "${UPDATER_BACKUP_DIR}/install.sh" "${UPDATER_INSTALL_DIR}/install.sh" 2>/dev/null || true
        cp "${UPDATER_BACKUP_DIR}/uninstall.sh" "${UPDATER_INSTALL_DIR}/uninstall.sh" 2>/dev/null || true
        chmod +x "${UPDATER_INSTALL_DIR}/bot.sh" 2>/dev/null || true
        _updater_restart_service
    ) &
}
