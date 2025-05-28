#!/bin/bash

SCRIPT_PATH="/Library/Management/demoter/demote-unlisted-admins"
DAEMON_PATH="/Library/LaunchDaemons/com.demote.demoteadmins.plist"
LOG_DIR="/Library/Management/demoter/logs"
SCRIPT_LOG="/Library/Management/demoter/logs/demoteadmins.log"
DEMOTER_DIR="/Library/Management/demoter"
ALLOWLIST_PLIST="/Library/Managed Preferences/com.demote.adminallow.plist"

scriptName="DemoteAdmin Uninstall"
scriptVersion="1.2"

function updateScriptLog() {
    echo "${scriptName} ($scriptVersion): $(date +%Y-%m-%d\ %H:%M:%S) - ${1}"
}

# Unload LaunchDaemon
if [ -f "$DAEMON_PATH" ]; then
    updateScriptLog "Unloading LaunchDaemon: $DAEMON_PATH"
    launchctl bootout system "$DAEMON_PATH" 2>/dev/null || \
    launchctl unload "$DAEMON_PATH" 2>/dev/null
    updateScriptLog "Removing LaunchDaemon: $DAEMON_PATH"
    rm -f "$DAEMON_PATH"
else
    updateScriptLog "LaunchDaemon not found: $DAEMON_PATH"
fi

# Remove demoter script
if [ -f "$SCRIPT_PATH" ]; then
    updateScriptLog "Removing script: $SCRIPT_PATH"
    rm -f "$SCRIPT_PATH"
else
    updateScriptLog "Demoter script not found: $SCRIPT_PATH"
fi

# Remove logs (optional, will delete all logs for this tool!)
if [ -d "$LOG_DIR" ]; then
    updateScriptLog "Removing log directory: $LOG_DIR"
    rm -rf "$LOG_DIR"
else
    updateScriptLog "Log directory not found: $LOG_DIR"
fi

# Remove main demoter dir if empty (optional)
if [ -d "$DEMOTER_DIR" ]; then
    updateScriptLog "Removing empty demoter directory: $DEMOTER_DIR"
    rm -rf "$DEMOTER_DIR"
fi

# Remove allow-list config (Optional: if managed via Jamf, profile will repush this)
if [ -f "$ALLOWLIST_PLIST" ]; then
    updateScriptLog "Removing allow-list config: $ALLOWLIST_PLIST"
    rm -f "$ALLOWLIST_PLIST"
else
    updateScriptLog "Allow-list config not found: $ALLOWLIST_PLIST"
fi

updateScriptLog "Demoter uninstall completed."
exit 0