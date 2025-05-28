#!/bin/bash

# This script checks the version of the demote-unlisted-admins script and returns it as a result. It is used to provide information about the version of the script being used.

# Script to check version of demote-unlisted-admins script
SCRIPT="/Library/Management/demoter/demote-unlisted-admins"

# Check if the script exists and read the version
if [ -f "$SCRIPT" ]; then
    ver=$(grep SCRIPT_VERSION "$SCRIPT" | grep -v updateScriptLog | awk -F '"' '{print $2}' | head -1)
    # Report if the file has a value
    if [[ -z "$ver" ]]; then
        echo "<result>${ver:-Unknown}</result>"
    else
        echo "<result>No Version Found</result>"
    fi
else
    echo "<result>Not File Found</result>"
fi