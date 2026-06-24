#!/bin/sh
# OpenWRT Telegram Bot — system-level commands (DNS cache restart, reboot).

# Pure helpers — no logging or Telegram dependencies.

_system_dnsmasq_available() {
    [ -x /etc/init.d/dnsmasq ]
}

_system_dnsmasq_restart() {
    /etc/init.d/dnsmasq restart >/dev/null 2>&1
}

# Reboot survives the current process exiting by detaching into a background
# subshell, the same way _updater_restart_service detaches service restarts.
_system_schedule_reboot() {
    (
        sleep 3
        reboot
    ) >/dev/null 2>&1 &
    return 0
}

# Command: /restartdns
system_restartdns() {
    local chat_id="$1"
    log_info "system: /restartdns requested by $chat_id"

    if ! _system_dnsmasq_available; then
        # shellcheck disable=SC2154
        telegram_send "$chat_id" "$T_RESTARTDNS_MISSING"
        log_warn "system: /restartdns skipped — dnsmasq init script not found"
        return 0
    fi

    if _system_dnsmasq_restart; then
        # shellcheck disable=SC2154
        telegram_send "$chat_id" "$T_RESTARTDNS_OK"
        log_info "system: dnsmasq restarted"
    else
        # shellcheck disable=SC2154
        telegram_send "$chat_id" "$T_RESTARTDNS_FAIL"
        log_error "system: dnsmasq restart failed"
    fi
}

# Command: /reboot [confirm]
system_reboot() {
    local chat_id="$1"
    local args="$2"

    if [ "$args" != "confirm" ]; then
        # shellcheck disable=SC2154
        telegram_send "$chat_id" "$T_REBOOT_CONFIRM"
        return 0
    fi

    # shellcheck disable=SC2154
    telegram_send "$chat_id" "$T_REBOOT_RUNNING"
    log_info "system: /reboot confirmed by $chat_id"
    _system_schedule_reboot
}
