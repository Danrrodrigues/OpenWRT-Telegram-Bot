#!/bin/sh
# OpenWRT Telegram Bot — Uninstaller

set -e

INSTALL_DIR="/usr/lib/telegram-bot"
CONFIG_FILE="/etc/config/telegram-bot"
SERVICE_FILE="/etc/init.d/telegram-bot"
NFT_FILE="/etc/nftables.d/telegram-bot.nft"
SEEN_FILE="/etc/telegram-bot-seen-devices"

_info()  { echo "[INFO]  $1"; }

if [ "$(id -u)" != "0" ]; then
    echo "[ERROR] Please run as root" >&2
    exit 1
fi

_info "Stopping and disabling service..."
if [ -f "$SERVICE_FILE" ]; then
    "$SERVICE_FILE" stop 2>/dev/null || true
    "$SERVICE_FILE" disable 2>/dev/null || true
    rm -f "$SERVICE_FILE"
    _info "Service removed"
fi

_info "Removing cron job..."
crontab -l 2>/dev/null | grep -v "telegram-bot" | crontab - 2>/dev/null || true
/etc/init.d/cron restart 2>/dev/null || true

_info "Removing scripts..."
rm -rf "$INSTALL_DIR"

_info "Removing nftables rules..."
if command -v nft >/dev/null 2>&1; then
    nft flush set inet fw4 telegram_blocked 2>/dev/null || true
    nft delete set inet fw4 telegram_blocked 2>/dev/null || true
fi
rm -f "$NFT_FILE"
fw4 reload 2>/dev/null || true

_info "Removing config..."
uci -q delete telegram-bot 2>/dev/null || true
uci commit 2>/dev/null || true
rm -f "$CONFIG_FILE" "$SEEN_FILE"

_info "Removing temp files..."
rm -f /tmp/telegram-bot-* 2>/dev/null || true

_info "=== Uninstall complete ==="
