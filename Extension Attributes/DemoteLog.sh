#!/bin/bash

# This script checks the last entry in the demote log file and returns it as a result. It is used to provide information about the last demote operation.

# Check if the log file exists and read the last entry
LOG="/Library/Management/demoter/logs/demoteadmins.log"
if [ -f "$LOG" ]; then
    last=$(tail -1 "$LOG" 2>/dev/null)
    echo "<result>$last</result>"
else
    echo "<result>No log found</result>"
fi