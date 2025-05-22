#!/bin/bash

LABEL="com.demote.demoteadmins"
if launchctl list | grep -qw "$LABEL"; then
    echo "<result>Loaded</result>"
else
    echo "<result>Not Loaded</result>"
fi