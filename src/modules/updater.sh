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
    if [ -f "/etc/init.d/telegram-bot" ]; then
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

    telegram_send "$chat_id" "Verificando atualizações..."

    local remote_version
    remote_version=$(_updater_remote_version)

    if [ -z "$remote_version" ]; then
        telegram_send "$chat_id" "Não foi possível verificar atualizações. O roteador está conectado à internet?"
        return 1
    fi

    if [ "$VERSION" = "$remote_version" ]; then
        telegram_send "$chat_id" "Já está na versão mais recente (<code>${VERSION}</code>)."
        return 0
    fi

    telegram_send "$chat_id" "$(printf '<b>Atualização disponível!</b>\n\nAtual:       <code>%s</code>\nDisponível:  <code>%s</code>\n\nEnvie /update confirm para atualizar.' \
        "$VERSION" "$remote_version")"
}

updater_run() {
    local chat_id="$1"

    telegram_send "$chat_id" "Atualizando... o bot reiniciará em instantes.
Envie /status para confirmar quando voltar."
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
                    telegram_send "$cid" "Falha na atualização: arquivo de instalação não encontrado."
                done
            fi
        else
            # shellcheck disable=SC2086
            for cid in $BOT_CHAT_IDS; do
                telegram_send "$cid" "Falha na atualização: não foi possível baixar o pacote. Verifique a conexão."
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
        telegram_send "$chat_id" "Nenhum backup disponível. Faça /update primeiro para criar um ponto de restauração."
        return 0
    fi

    if [ "$args" = "confirm" ]; then
        _updater_do_rollback "$chat_id" "$backup_version"
        return
    fi

    telegram_send "$chat_id" "$(printf '<b>Rollback disponível</b>\n\nBackup: <code>%s</code>\nAtual:  <code>%s</code>\n\nEnvie /rollback confirm para restaurar.' \
        "$backup_version" "$VERSION")"
}

_updater_do_rollback() {
    local chat_id="$1"
    local backup_version="$2"

    telegram_send "$chat_id" "Restaurando versão <code>${backup_version}</code>... o bot reiniciará em instantes."
    log_info "updater: rolling back from $VERSION to $backup_version"

    (
        sleep 3
        cp "${UPDATER_BACKUP_DIR}/bot.sh" "${UPDATER_INSTALL_DIR}/bot.sh" 2>/dev/null || true
        for f in "${UPDATER_BACKUP_DIR}/core/"*.sh; do
            [ -f "$f" ] && cp "$f" "${UPDATER_INSTALL_DIR}/core/" 2>/dev/null || true
        done
        for f in "${UPDATER_BACKUP_DIR}/modules/"*.sh; do
            [ -f "$f" ] && cp "$f" "${UPDATER_INSTALL_DIR}/modules/" 2>/dev/null || true
        done
        cp "${UPDATER_BACKUP_DIR}/install.sh" "${UPDATER_INSTALL_DIR}/install.sh" 2>/dev/null || true
        cp "${UPDATER_BACKUP_DIR}/uninstall.sh" "${UPDATER_INSTALL_DIR}/uninstall.sh" 2>/dev/null || true
        chmod +x "${UPDATER_INSTALL_DIR}/bot.sh" 2>/dev/null || true
        _updater_restart_service
    ) &
}
