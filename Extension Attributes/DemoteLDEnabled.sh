#!/bin/bash

# This EA checks if the LaunchDaemon for demoting unauthorized admins is loaded.
LAUNCHD_LABEL="com.demote.demoteadmins"
PLIST="/Library/LaunchDaemons/com.demote.demoteadmins.plist"

if [ ! -f "$PLIST" ]; then
    echo "<result>LaunchDaemon plist Not Found</result>"
    exit 0
fi

if launchctl list | grep -qw "$LAUNCHD_LABEL"; then
    echo "<result>Loaded</result>"
else
    echo "<result>Not Loaded</result>"
fi