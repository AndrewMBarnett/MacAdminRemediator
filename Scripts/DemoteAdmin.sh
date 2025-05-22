#!/bin/bash

### Variables
SCRIPT_PATH="/Library/Management/Demoter/demote-unlisted-admins"
DAEMON_PATH="/Library/LaunchDaemons/com.demote.demoteadmins.plist"
LOG_PATH="/Library/Management/demoter/logs/demoteadmins.log"
PROFILE_PLIST="/Library/Managed Preferences/com.demote.adminallow.plist"

if [[ ! -d "/Library/Management/demoter" ]]; then
    echo "Creating /Library/Management/demoter directory"
    mkdir -p /Library/Management/demoter
fi

if [[ ! -d "/Library/Management/demoter/logs" ]]; then
    echo "Creating /Library/Management/demoter/logs directory"
    mkdir -p /Library/Management/demoter/logs
fi

###############################################################################
# Demotion script content
###############################################################################
cat << 'EOF' > "$SCRIPT_PATH"
#!/bin/bash

PROFILE_PLIST="/Library/Managed Preferences/com.demote.adminallow.plist"
PRIV_APP="/Applications/Privileges.app"
PRIVILEGES_INFOPLIST="$PRIV_APP/Contents/Info.plist"
PRIVILEGES_CLI_V1="$PRIV_APP/Contents/Resources/PrivilegesCLI"
PRIVILEGES_CLI_V2="$PRIV_APP/Contents/MacOS/PrivilegesCLI"
scriptLog="/Library/Management/demoter/logs/demoteadmins.log"
demoterInterval=900 # 15 minutes in seconds (Clear this variable if you want to set it in the config profile, otherwise it will default to 15 minutes)

# Allow-list of admins if not set in config profile
# This is a placeholder for the allow-list. You can add admin usernames here.
# Example: ALLOWED_ADMINS=("admin1" "admin2")
ALLOWED_ADMINS=()

scriptName="DemoteAdmin"
scriptVersion="2.2"

# User-defined variables
ALLOWED_PATTERN="^($(IFS="|"; echo "${ALLOWED_ADMINS[*]}"))$"
ALL_USERS=$(dscl . list /Users UniqueID | awk '$2 >= 501 {print $1}')
CONSOLE_USER=$( scutil <<< "show State:/Users/ConsoleUser" | awk '/Name :/ && !/loginwindow/ { print $3 }' )
CONSOLE_USER_UID=$(id -u "$CONSOLE_USER" 2>/dev/null)

# Functions for logging
function updateScriptLog() {
    echo "${scriptName} ($scriptVersion): $(date +%Y-%m-%d\ %H:%M:%S) - ${1}"
}
function notice() {
    updateScriptLog "[NOTICE]          ${1}"
}
function fatal() {
    updateScriptLog "[FATAL]           ${1}"
    exit 1
}

# Create the log file if it does not exist
touch "${scriptLog}" || fatal "Unable to create log file at $scriptLog. Is script running as root?"

# Robust allow-list loading
if [[ -e "$PROFILE_PLIST" ]]; then
    ALLOWED_ADMINS=($(defaults read "$PROFILE_PLIST" AllowedAdmins 2>/dev/null | tr -d ',"'))
else
    ALLOWED_ADMINS=(${ALLOWED_ADMINS[@]})
fi

if [[ -z "$demoterInterval" ]]; then
    notice "Demoter interval not set in the script, checking config profile."
    demoterInterval=$(defaults read "$PROFILE_PLIST" DemoterInterval 2>/dev/null)
    if [[ -z "$demoterInterval" ]]; then
        notice "No interval set in config profile, defaulting to 15 minutes."
        demoterInterval=900
    else
        fatal "Demoter interval unable to be set. Check config profile or script."
    fi
fi

if [[ -z "$CONSOLE_USER_UID" ]]; then
    fatal "Unable to determine UID for console user: $CONSOLE_USER"
fi

if [[ -d "$PRIV_APP" && -f "$PRIVILEGES_INFOPLIST" ]]; then
    PRIV_PRESENT=true
    PRIV_VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$PRIVILEGES_INFOPLIST" 2>/dev/null | awk '{print $1}')
    PRIV_VERSION_MAJOR=$(echo "${PRIV_VERSION}" | awk -F. '{print $1}')
else
    PRIV_PRESENT=false
fi

for user in $ALL_USERS; do
    if [[ $user =~ $ALLOWED_PATTERN ]]; then
        continue
    fi
    if dseditgroup -o checkmember -m "$user" admin | grep -q "yes"; then
        keep_admin=false
if [[ "$user" == "$CONSOLE_USER" && "$PRIV_PRESENT" == "true" && -n "$CONSOLE_USER_UID" ]]; then
    if [[ "$PRIV_VERSION_MAJOR" -ge 2 && -x "$PRIVILEGES_CLI_V2" ]]; then
        status=$(/bin/launchctl asuser "$CONSOLE_USER_UID" sudo -u "$CONSOLE_USER" "${PRIVILEGES_CLI_V2}" --status 2>&1)
        if echo "$status" | grep -q "has administrator privileges"; then
            timeleft=$(echo "$status" | awk '/expire/ {for(i=1;i<=NF;i++) if($i~/^[0-9]+$/) print $i}')
            if [[ "${timeleft:-0}" -gt 0 ]]; then
                keep_admin=true
            fi
        fi
    elif [[ "$PRIV_VERSION_MAJOR" -lt 2 && -x "$PRIVILEGES_CLI_V1" ]]; then
        status=$(sudo -u "$CONSOLE_USER" "$PRIVILEGES_CLI_V1" --status 2>&1)
        if echo "$status" | grep -q "$CONSOLE_USER has admin rights"; then
            keep_admin=true
        fi
    fi
fi
        if [[ "$keep_admin" == "true" ]]; then
            notice "$user is currently a Privileges.app admin (still valid) — skipping demotion (time remaining: $timeleft minutes)."
            continue
        fi
        notice "Demoting unauthorized admin: $user"
        dseditgroup -o edit -d "$user" admin
    fi
done
EOF

if [[ $? -ne 0 ]]; then
    fatal "Failed to create the script at $SCRIPT_PATH"
fi

# Permissioning
chmod 755 "$SCRIPT_PATH"
chmod 644 /Library/Management/demoter/logs/demoteadmins.log
chown root:wheel "$SCRIPT_PATH"

# LaunchDaemon to run every interval set
cat << EOF > "$DAEMON_PATH"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.demote.demoteadmins</string>
    <key>ProgramArguments</key>
    <array>
        <string>$SCRIPT_PATH</string>
    </array>
    <key>StartInterval</key>
    <integer>900</integer>
    <key>RunAtLoad</key>
    <true/>
    <key>StandardOutPath</key>
    <string>$LOG_PATH</string>
    <key>StandardErrorPath</key>
    <string>$LOG_PATH</string>
</dict>
</plist>
EOF

if [[ $? -ne 0 ]]; then
    fatal "Failed to create the launch daemon at $DAEMON_PATH"
fi

# Set permissions for the LaunchDaemon
chmod 644 "$DAEMON_PATH"
chown root:wheel "$DAEMON_PATH"

# Load the LaunchDaemon
launchctl unload "$DAEMON_PATH" 2>/dev/null
launchctl load "$DAEMON_PATH"

# Make sure folder and file are readable by all
chmod 755 /Library/Management/demoter
chmod 755 /Library/Management/demoter/logs

exit 0