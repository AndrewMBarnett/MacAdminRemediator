#!/bin/bash

TRACKING_PLIST="/var/db/.systemconfig/.tracking.plist"

if [[ ! -f "$TRACKING_PLIST" ]]; then
    echo "<result>Not Tracked</result>"
    exit 0
fi

chflags nouchg "$TRACKING_PLIST" 2>/dev/null
tamper_count=$(defaults read "$TRACKING_PLIST" "tamperCount" 2>/dev/null || echo "0")
chflags uchg "$TRACKING_PLIST" 2>/dev/null

if [[ "$tamper_count" -ge 5 ]]; then
    echo "<result>High Risk ($tamper_count events)</result>"
elif [[ "$tamper_count" -ge 3 ]]; then
    echo "<result>Elevated ($tamper_count events)</result>"
elif [[ "$tamper_count" -ge 1 ]]; then
    echo "<result>Low Risk ($tamper_count event)</result>"
else
    echo "<result>Clean Record</result>"
fi
