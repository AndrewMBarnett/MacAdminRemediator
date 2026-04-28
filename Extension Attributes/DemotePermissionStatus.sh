#!/bin/bash

SCRIPT_PATH="/Library/Management/.demoter/.demote-unlisted-admins.sh"
TRIGGER_FILE="/Library/Management/.demoter/.trigger"

if [[ ! -f "$SCRIPT_PATH" ]]; then
    echo "<result>Not Installed</result>"
    exit 0
fi

ISSUES=()
SCRIPT_PERMS=$(stat -f "%Sp" "$SCRIPT_PATH" 2>/dev/null)
[[ "$SCRIPT_PERMS" != "-r-x------" ]] && ISSUES+=("Script:$SCRIPT_PERMS")

TRIGGER_PERMS=$(stat -f "%Sp" "$TRIGGER_FILE" 2>/dev/null)
[[ "$TRIGGER_PERMS" != "-rw-rw-rw-" ]] && ISSUES+=("Trigger:$TRIGGER_PERMS")

if [[ ${#ISSUES[@]} -eq 0 ]]; then
    echo "<result>OK</result>"
else
    echo "<result>INCORRECT: ${ISSUES[*]}</result>"
fi