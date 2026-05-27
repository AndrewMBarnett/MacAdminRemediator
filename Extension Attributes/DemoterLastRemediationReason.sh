#!/bin/bash

TRACKING_DIR="/var/db/.systemconfig"
TRACKING_PLIST="${TRACKING_DIR}/.tracking.plist"

if [[ ! -f "$TRACKING_PLIST" ]]; then
    echo "<result>Not Tracked</result>"
    exit 0
fi

chflags nouchg "$TRACKING_PLIST" 2>/dev/null
reason=$(defaults read "$TRACKING_PLIST" "lastRemediationReason" 2>/dev/null)
timestamp=$(defaults read "$TRACKING_PLIST" "lastRemediationTimestamp" 2>/dev/null)
chflags uchg "$TRACKING_PLIST" 2>/dev/null

if [[ -z "$reason" ]]; then
    echo "<result>Never triggered</result>"
else
    echo "<result>$reason ($timestamp)</result>"
fi
