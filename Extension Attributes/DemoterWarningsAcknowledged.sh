#!/bin/bash

TRACKING_PLIST="/var/db/.systemconfig/.tracking.plist"

if [[ ! -f "$TRACKING_PLIST" ]]; then
    echo "<result>Not Tracked</result>"
    exit 0
fi

chflags nouchg "$TRACKING_PLIST" 2>/dev/null
ack_count=$(defaults read "$TRACKING_PLIST" "warningAcknowledged" 2>/dev/null || echo "0")
chflags uchg "$TRACKING_PLIST" 2>/dev/null

echo "<result>$ack_count</result>"
