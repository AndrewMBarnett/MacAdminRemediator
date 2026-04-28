#!/bin/bash

VERSION_FILE="/Library/Management/.demoter/.version"

if [[ -f "$VERSION_FILE" ]]; then
    ver=$(cat "$VERSION_FILE" 2>/dev/null)
    if [[ -n "$ver" ]]; then
        echo "<result>$ver</result>"
    else
        echo "<result>Unknown</result>"
    fi
else
    echo "<result>Not Installed</result>"
fi