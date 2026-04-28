#!/bin/bash

TRACKING_DIR="/var/db/.systemconfig" 
TRACKING_PLIST="${TRACKING_DIR}/.tracking.plist"

if [[ ! -f "$TRACKING_PLIST" ]]; then
    echo "<result>Not Tracked</result>"
    exit 0
fi

chflags nouchg "$TRACKING_PLIST" 2>/dev/null
tamper_count=$(defaults read "$TRACKING_PLIST" "tamperCount" 2>/dev/null || echo "0")
last_tamper=$(defaults read "$TRACKING_PLIST" "lastTamperDetected" 2>/dev/null || echo "Never")
chflags uchg "$TRACKING_PLIST" 2>/dev/null

if [[ "$tamper_count" -gt 0 ]]; then
    echo "<result>$tamper_count (Last: $last_tamper)</result>"
else
    echo "<result>0 - Clean</result>"
fi