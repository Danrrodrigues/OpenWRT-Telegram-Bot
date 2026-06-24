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

# --- fix command ---
T_FIX_OK="🛠️ Firewall repaired. Blocklist rules reloaded and active blocks/limits restored."
T_FIX_REVERTED="⚠️ Repair aborted: the new firewall rules would not load, so nothing was changed and your internet is safe. Check the logs."
T_FIX_NONFT="Nothing to repair: this router has no <code>nft</code> available."

# --- wake command ---
T_WAKE_USAGE="Usage: <code>/wake &lt;MAC or IP&gt;</code>"
T_WAKE_NOT_FOUND="❌ Device not found: <code>%s</code>"
T_WAKE_MISSING_ETHERWAKE="❌ etherwake is not installed. Install it with: <code>opkg update &amp;&amp; opkg install etherwake</code>"
T_WAKE_SENT="✅ Wake packet sent to <b>%s</b> (<code>%s</code>)."
T_WAKE_FAILED="❌ Could not send wake packet to <b>%s</b> (<code>%s</code>)."

# --- lang command ---
T_LANG_CURRENT="Current language: %s
Send /lang en or /lang pt to switch."
T_LANG_CHANGED="Language changed to %s"
T_LANG_SAME="Language is already set to %s"
T_LANG_INVALID="Unknown language: %s. Available: en, pt"

# --- system command (restartdns / reboot) ---
T_RESTARTDNS_OK="✅ DNS cache restarted (dnsmasq)."
T_RESTARTDNS_FAIL="❌ Failed to restart dnsmasq. Check the logs."
T_RESTARTDNS_MISSING="Nothing to restart: this router has no <code>dnsmasq</code> init script."
T_REBOOT_CONFIRM="⚠️ This will reboot the router and drop the network for about a minute.
Send /reboot confirm to proceed."
T_REBOOT_RUNNING="🔄 Rebooting now... the bot will be back shortly.
Send /status in a minute to confirm."
T_RESTARTDNS_CONFIRM="This will restart the DNS cache (dnsmasq)."

# --- inline keyboard buttons (confirm/cancel, device pickers) ---
T_BTN_CONFIRM="✅ Confirm"
T_BTN_CANCEL="❌ Cancel"
T_CANCELLED="Cancelled."
T_KICK_PICK="Pick a device to kick:"
T_BLOCK_PICK="Pick a device to block:"
T_UNBLOCK_PICK="Pick a device to unblock:"
T_WAKE_PICK="Pick a device to wake:"
T_NAME_PICK="Pick a device to name:"
T_LIMIT_PICK="Pick a device to limit:"
T_LIMIT_PROMPT="Send the speed limit as <code>&lt;down Mbps&gt; &lt;up Mbps&gt;</code>, e.g. <code>10 5</code>."
T_NAME_PROMPT="Send the new name for this device."

I18N_COMMANDS='start|Show help and available commands
devices|List connected devices
status|Router status (CPU, RAM, uptime)
alerts|Configure alerts (off/known/unknown/all)
kick|Disconnect a device (MAC or IP)
wake|Wake device with Wake-on-LAN
block|Block a device permanently (MAC)
unblock|Remove a block (MAC)
name|Save a name for a device (MAC name)
limit|Set speed limit (MAC down up in Mbps)
unlimit|Remove speed limit (MAC)
update|Check for updates (use confirm to apply)
rollback|Restore previous version (use confirm to apply)
fix|Repair firewall and blocklist setup
restartdns|Restart DNS cache (dnsmasq)
reboot|Reboot the router (use confirm to apply)
lang|Change bot language (en or pt)
help|Show this message'
