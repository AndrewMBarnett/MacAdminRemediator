#!/bin/bash

# This EA checks if the LaunchDaemon for demoting unauthorized admins is loaded.
LAUNCHD_LABEL="com.demote.demoteadmins"
# The LaunchDaemon plist file path
PLIST="/Library/LaunchDaemons/com.demote.demoteadmins.plist"

# Check if the LaunchDaemon plist file exists
if [ -f "$PLIST" ]; then
    if launchctl list | grep -qw "$LAUNCHD_LABEL"; then
        echo "<result>Demote Admins Loaded</result>"
    else
        echo "<result>Demote Admins Not Loaded</result>"
    fi
else
    # If the plist file does not exist, report it
    echo "<result>Demote Admins LaunchDaemon Not Found</result>"
fi
