#!/bin/bash

LOG="/Library/Management/demoter/logs/demoteadmins.log"
if [ -f "$LOG" ]; then
    last=$(tail -1 "$LOG" 2>/dev/null)
    echo "<result>$last</result>"
else
    echo "<result>No log found</result>"
fi