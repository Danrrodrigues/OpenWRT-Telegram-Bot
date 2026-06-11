#!/bin/sh
# OpenWRT Telegram Bot — firewall (nftables MAC blocklist) management.
#
# SINGLE SOURCE OF TRUTH for the fw4 include file. Used by BOTH the installer
# (install.sh) and the runtime /fix command, so the two can never drift — a past
# drift wrote `table inet fw4 { ... }` in the include, which fw4 already provides.
# The nested table broke the WHOLE ruleset (NAT included) and cut internet for
# every LAN client after any fw4 reload (boot/restart).
#
# The pure helpers below (content / valid / ensure) have NO logging or Telegram
# dependencies, so install.sh can source this file safely. firewall_fix() is the
# runtime command handler and depends on the bot context (log_*, telegram_send,
# i18n T_* strings, devices_*, bandwidth_*).

NFT_BLOCKLIST_FILE="${NFT_BLOCKLIST_FILE:-/etc/nftables.d/telegram-bot.nft}"

# Canonical fw4 include content.
# IMPORTANT: files in /etc/nftables.d/ are included *inside* `table inet fw4 { }`
# by fw4 — never add a table wrapper here, or the whole firewall fails to load.
firewall_blocklist_content() {
    cat <<'NFTEOF'
# OpenWRT Telegram Bot — MAC blocklist
# Managed automatically — do not edit manually.
# Do NOT wrap this in `table inet fw4 { }`: fw4 already includes this file inside
# that table. A nested table breaks the entire firewall (NAT included).

set telegram_blocked {
    type ether_addr
    elements = { }
}

# Dedicated forward base-chain that runs *before* fw4's filtering (priority -1).
# policy accept so it only drops blocked MACs and lets everything else fall
# through to fw4 for normal processing.
chain telegram_block {
    type filter hook forward priority -1; policy accept;
    ether saddr @telegram_blocked drop
    ether daddr @telegram_blocked drop
}
NFTEOF
}

# Returns 0 if fw4 still renders a loadable ruleset, non-zero otherwise.
firewall_ruleset_valid() {
    fw4 check >/dev/null 2>&1 || fw4 print 2>/dev/null | nft -c -f - >/dev/null 2>&1
}

# Write the include, validate it, and apply. If it would break the ruleset,
# remove our own file and reload so the firewall — and every client's internet —
# keeps working. Echoes one of: ok | reverted | nonft. Returns 0 only on "ok".
firewall_ensure_blocklist() {
    command -v nft >/dev/null 2>&1 || { echo nonft; return 2; }
    mkdir -p "$(dirname "$NFT_BLOCKLIST_FILE")" 2>/dev/null || true
    firewall_blocklist_content > "$NFT_BLOCKLIST_FILE"
    if firewall_ruleset_valid; then
        fw4 reload >/dev/null 2>&1
        echo ok
        return 0
    fi
    rm -f "$NFT_BLOCKLIST_FILE"
    fw4 reload >/dev/null 2>&1 || true
    echo reverted
    return 1
}

# /fix command — repair the firewall blocklist include and re-apply runtime
# state (blocked MACs + speed limits), which a manual fw4 reload would have
# wiped from the live ruleset.
firewall_fix() {
    local chat_id="$1"
    local result
    log_info "firewall: /fix requested by $chat_id"

    result=$(firewall_ensure_blocklist)

    case "$result" in
        ok)
            devices_restore_blocks >/dev/null 2>&1
            bandwidth_restore_limits >/dev/null 2>&1
            # shellcheck disable=SC2154
            telegram_send "$chat_id" "$T_FIX_OK"
            log_info "firewall: /fix applied; blocklist + limits restored"
            ;;
        reverted)
            # shellcheck disable=SC2154
            telegram_send "$chat_id" "$T_FIX_REVERTED"
            log_error "firewall: /fix reverted — include would break the ruleset"
            ;;
        *)
            # shellcheck disable=SC2154
            telegram_send "$chat_id" "$T_FIX_NONFT"
            log_warn "firewall: /fix skipped — nft not available"
            ;;
    esac
}
