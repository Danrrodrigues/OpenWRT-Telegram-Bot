#!/bin/sh
# English strings (i18n base).
# Values for T_* are printf templates. Keep command descriptions free of
# double quotes and backslashes — they are embedded directly into setMyCommands JSON.
# shellcheck disable=SC2034

# --- notify / updater messages ---
T_UPDATED="✅ Bot updated to v%s"
T_UPDATE_AVAILABLE="📦 New version available: v%s (you have v%s).
Send /update confirm to update."

# --- command menu (command|description per line) ---
I18N_COMMANDS='start|Show help and available commands
devices|List connected devices
status|Router status (CPU, RAM, uptime)
alerts|Configure alerts (off/known/unknown/all)
kick|Disconnect a device (MAC or IP)
block|Block a device permanently (MAC)
unblock|Remove a block (MAC)
name|Save a name for a device (MAC name)
limit|Set speed limit (MAC down up in Mbps)
unlimit|Remove speed limit (MAC)
update|Check for updates (use confirm to apply)
rollback|Restore previous version (use confirm to apply)
help|Show this message'
