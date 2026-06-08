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
# --- updater messages ---
T_CHECKING="Checking for updates..."
T_CHECK_FAIL="Could not check for updates. Is the router connected to the internet?"
T_UP_TO_DATE="Already on the latest version (<code>%s</code>)."
T_UPDATE_AVAILABLE_CMD="<b>Update available!</b>

Current:    <code>%s</code>
Available: <code>%s</code>

Send /update confirm to update."
T_UPDATING="Updating... the bot will restart shortly.
Send /status to confirm when back."
T_UPDATE_FAIL_EXTRACT="Update failed: installation archive not found."
T_UPDATE_FAIL_DOWNLOAD="Update failed: could not download the package. Check the internet connection."
T_ROLLBACK_NONE="No backup available. Run /update first to create a restore point."
T_ROLLBACK_AVAILABLE="<b>Rollback available</b>

Backup: <code>%s</code>
Current: <code>%s</code>

Send /rollback confirm to restore."
T_ROLLBACK_RUNNING="Restoring version <code>%s</code>... the bot will restart shortly."

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
