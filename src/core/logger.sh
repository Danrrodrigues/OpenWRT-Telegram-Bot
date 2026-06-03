#!/bin/sh
# Logging utilities — writes to syslog and optional log file

LOGFILE="${LOGFILE:-/var/log/telegram-bot.log}"
LOG_MAX_SIZE=102400  # 100 KB before rotation

_log() {
    local level="$1"
    local msg="$2"
    local ts
    ts=$(date '+%Y-%m-%d %H:%M:%S')
    local line="[$ts] [$level] $msg"

    logger -t telegram-bot "$level: $msg" 2>/dev/null || true

    if [ -n "$LOGFILE" ] && [ "$LOGFILE" != "/dev/null" ]; then
        echo "$line" >> "$LOGFILE"
        _rotate_log
    fi
}

_rotate_log() {
    [ -f "$LOGFILE" ] || return
    local size
    size=$(wc -c < "$LOGFILE" 2>/dev/null) || return
    if [ "$size" -gt "$LOG_MAX_SIZE" ]; then
        mv "$LOGFILE" "${LOGFILE}.1" 2>/dev/null || true
        touch "$LOGFILE" 2>/dev/null || true
    fi
}

log_debug() {
    [ "${LOG_LEVEL:-info}" = "debug" ] && _log "DEBUG" "$1"
    return 0
}

log_info()  { _log "INFO"  "$1"; }
log_warn()  { _log "WARN"  "$1"; }
log_error() { _log "ERROR" "$1"; }
