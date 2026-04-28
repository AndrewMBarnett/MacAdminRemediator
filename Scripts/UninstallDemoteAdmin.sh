#!/bin/bash

SCRIPT_NAME="DemoteAdmin Uninstall"
SCRIPT_VERSION="2.0"

# Install paths (must match DemoteAdminInstall.sh)
DEMOTER_DIR="/Library/Management/.demoter"
DAEMON_PATH="/Library/LaunchDaemons/com.demote.demoteadmins.plist"
TRIGGER_DAEMON_PATH="/Library/LaunchDaemons/com.demote.privileges-trigger.plist"
REMEDIATE_DAEMON_PATH="/Library/LaunchDaemons/com.demote.remediate.plist"
WRAPPER_PATH="/usr/local/bin/.privileges-demote-trigger"
TRACKING_DIR="/var/db/.systemconfig"
TRACKING_PLIST="${TRACKING_DIR}/.tracking.plist"

# Remediation artifacts
REMEDIATE_TRIGGER_SCRIPT="/tmp/demoter-remediate-trigger.sh"
REMEDIATE_LOG="/tmp/demoter-remediate.log"

function LOG() {
    echo "${SCRIPT_NAME} ($SCRIPT_VERSION): $(date +%Y-%m-%d\ %H:%M:%S) - ${1}"
}

if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root. Please run with sudo."
    exit 1
fi

LOG "=========================================="
LOG "Starting DemoteAdmin uninstallation"
LOG "=========================================="
LOG ""

### ====== Unload and Remove LaunchDaemons ======

LOG "Step 1/6: Unloading LaunchDaemons..."

for label in com.demote.demoteadmins com.demote.privileges-trigger com.demote.remediate; do
    if launchctl list | grep -q "$label"; then
        launchctl bootout "system/${label}" 2>/dev/null
        LOG "   Unloaded $label"
    fi
done

for plist in "$DAEMON_PATH" "$TRIGGER_DAEMON_PATH" "$REMEDIATE_DAEMON_PATH"; do
    if [[ -f "$plist" ]]; then
        rm -f "$plist"
        LOG "   Removed $(basename $plist)"
    fi
done

### ====== Remove Wrapper Script ======

LOG "Step 2/6: Removing wrapper script..."

if [[ -f "$WRAPPER_PATH" ]]; then
    rm -f "$WRAPPER_PATH"
    LOG "   Removed $WRAPPER_PATH"
else
    LOG "   Wrapper not found (already removed)"
fi

### ====== Remove Demoter Directory (logs, script, trigger, version) ======

LOG "Step 3/6: Removing demoter directory..."

if [[ -d "$DEMOTER_DIR" ]]; then
    rm -rf "$DEMOTER_DIR"
    LOG "   Removed $DEMOTER_DIR"
else
    LOG "   Demoter directory not found (already removed)"
fi

### ====== Remove Tracking Plist ======

LOG "Step 4/6: Removing security tracking data..."

if [[ -f "$TRACKING_PLIST" ]]; then
    # Remove immutable flag before deleting
    chflags nouchg "$TRACKING_PLIST" 2>/dev/null
    rm -f "$TRACKING_PLIST"
    LOG "   Removed $TRACKING_PLIST"
else
    LOG "   Tracking plist not found (already removed)"
fi

# Remove tracking directory only if empty
if [[ -d "$TRACKING_DIR" ]] && [[ -z "$(ls -A "$TRACKING_DIR" 2>/dev/null)" ]]; then
    rmdir "$TRACKING_DIR"
    LOG "   Removed empty tracking directory $TRACKING_DIR"
fi

### ====== Remove Remediation Artifacts ======

LOG "Step 5/6: Removing remediation artifacts..."

for artifact in "$REMEDIATE_TRIGGER_SCRIPT" "$REMEDIATE_LOG"; do
    if [[ -f "$artifact" ]]; then
        rm -f "$artifact"
        LOG "   Removed $artifact"
    fi
done

### ====== Note on Configuration Profile ======

LOG "Step 6/6: Configuration profile..."
LOG "   NOTE: The com.demote.adminallow configuration profile must be"
LOG "   removed separately via Jamf Pro (Computers > Profiles)."
LOG "   File at /Library/Managed Preferences/com.demote.adminallow.plist"
LOG "   is managed by MDM and will be removed when the profile is unscoped."

### ====== Verification ======

LOG ""
LOG "=========================================="
LOG "Uninstallation complete"
LOG "=========================================="
LOG ""

LEFTOVER=false

[[ -d "$DEMOTER_DIR" ]]          && LOG "   WARNING: $DEMOTER_DIR still exists"          && LEFTOVER=true
[[ -f "$DAEMON_PATH" ]]          && LOG "   WARNING: $DAEMON_PATH still exists"          && LEFTOVER=true
[[ -f "$TRIGGER_DAEMON_PATH" ]]  && LOG "   WARNING: $TRIGGER_DAEMON_PATH still exists"  && LEFTOVER=true
[[ -f "$REMEDIATE_DAEMON_PATH" ]] && LOG "   WARNING: $REMEDIATE_DAEMON_PATH still exists" && LEFTOVER=true
[[ -f "$WRAPPER_PATH" ]]         && LOG "   WARNING: $WRAPPER_PATH still exists"         && LEFTOVER=true
[[ -f "$TRACKING_PLIST" ]]       && LOG "   WARNING: $TRACKING_PLIST still exists"       && LEFTOVER=true

if [[ "$LEFTOVER" == false ]]; then
    LOG "   All components removed successfully"
fi

LOG ""
exit 0
