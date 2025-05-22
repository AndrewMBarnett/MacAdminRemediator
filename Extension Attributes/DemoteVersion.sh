#!/bin/bash

# This script checks the version of the demote-unlisted-admins script and returns it as a result. It is used to provide information about the version of the script being used.

SCRIPT="/Library/Management/demoter/demote-unlisted-admins"
if [ -f "$SCRIPT" ]; then
    ver=$(grep scriptVersion "$SCRIPT" | grep -v updateScriptLog | awk -F '"' '{print $2}' | head -1)
    echo "<result>${ver:-Unknown}</result>"
else
    echo "<result>Not Found</result>"
fi