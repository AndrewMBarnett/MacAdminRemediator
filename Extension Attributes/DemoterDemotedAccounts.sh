#!/bin/bash

TRACKING_PLIST="/var/db/.systemconfig/.tracking.plist"

if [[ ! -f "$TRACKING_PLIST" ]]; then
    echo "<result>Not Tracked</result>"
    exit 0
fi

chflags nouchg "$TRACKING_PLIST" 2>/dev/null
demotion_count=$(defaults read "$TRACKING_PLIST" "demotionCount" 2>/dev/null || echo "0")
last_account=$(defaults read "$TRACKING_PLIST" "lastDemotedAccount" 2>/dev/null)
last_time=$(defaults read "$TRACKING_PLIST" "lastDemotionTime" 2>/dev/null)
chflags uchg "$TRACKING_PLIST" 2>/dev/null

if [[ -z "$last_account" || "$demotion_count" -eq 0 ]]; then
    echo "<result>No demotions recorded</result>"
else
    echo "<result>$demotion_count demotion(s) — Last: $last_account ($last_time)</result>"
fi
