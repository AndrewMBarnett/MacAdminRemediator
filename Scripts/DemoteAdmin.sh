#!/bin/bash

### ====== Variables ======

DEMOTER_DIR="/Library/Management/demoter"
SCRIPT_PATH="${DEMOTER_DIR}/demote-unlisted-admins"
DEMOTER_LOGS_DIR="${DEMOTER_DIR}/logs"
LOG_PATH="${DEMOTER_LOGS_DIR}/demoteadmins.log"
DAEMON_PATH="/Library/LaunchDaemons/com.demote.demoteadmins.plist"
PROFILE_PLIST="/Library/Managed Preferences/com.demote.adminallow.plist"
CONSOLE_USER=$( scutil <<< "show State:/Users/ConsoleUser" | awk '/Name :/ && !/loginwindow/ { print $3 }' )

# Default values if nothing found in Config Profile
DEFAULT_ALLOWED_ADMINS=()     # e.g. ("admin1" "admin2")
DEFAULT_DEMOTER_INTERVAL=900  # 15m in seconds; edit as you like

### ====== Directories and Logging ======

if [[ ! -d "$DEMOTER_DIR" ]]; then
    echo "Creating $DEMOTER_DIR directory"
    mkdir -p "$DEMOTER_DIR"
fi

if [[ ! -d "$DEMOTER_LOGS_DIR" ]]; then
    echo "Creating $DEMOTER_LOGS_DIR directory"
    mkdir -p "$DEMOTER_LOGS_DIR"
fi

if [[ ! -f "$LOG_PATH" ]]; then
    echo "Creating script log at $LOG_PATH"
    touch "$LOG_PATH"
    if [[ $? -ne 0 ]]; then
        echo "Failed to create script log at $LOG_PATH."
        exit 1
    fi
fi

if [[  -f "$LOG_PATH_ARCHIVE" ]]; then
    echo "Archiving old log to $LOG_PATH_ARCHIVE"
     "$LOG_PATH" "$LOG_PATH_ARCHIVE"
fi

### ====== Write Demoter Script ======

cat << 'EOSCPT' > "$SCRIPT_PATH"
#!/bin/bash

# === Configuration Paths ===
SCRIPT_NAME="DemoteAdmin"
SCRIPT_VERSION="2.15"
DEMOTER_DIR="/Library/Management/demoter"
DEMOTER_LOGS_DIR="${DEMOTER_DIR}/logs"
DEMOTER_LOGS_DIR_ARCHIVE="${DEMOTER_LOGS_DIR}/log-archive"
SCRIPT_LOG="${DEMOTER_LOGS_DIR}/demoteadmins.log"
SCRIPT_PATH="${DEMOTER_DIR}/demote-unlisted-admins"
PROFILE_PLIST="/Library/Managed Preferences/com.demote.adminallow.plist"

# === Privileges App Paths ===
PRIV_APP="/Applications/Privileges.app"
PRIVILEGES_INFOPLIST="$PRIV_APP/Contents/Info.plist"
PRIVILEGES_CLI_V1="$PRIV_APP/Contents/Resources/PrivilegesCLI"
PRIVILEGES_CLI_V2="$PRIV_APP/Contents/MacOS/PrivilegesCLI"

# === Default Values ===
DEFAULT_ALLOWED_ADMINS=()
DEFAULT_DEMOTER_INTERVAL=900

# === Log Rotation ===
MAX_SIZE="512000"  # 500 KB in bytes
mkdir -p "$DEMOTER_LOGS_DIR_ARCHIVE"
if [[ -f "$SCRIPT_LOG" ]]; then
    log_size=$(stat -f %z "$SCRIPT_LOG" 2>/dev/null || stat -c %s "$SCRIPT_LOG")
    if [[ "$log_size" -ge "$MAX_SIZE" ]]; then
        TS=$(date +%Y-%m-%d.%H-%M-%S)
        ZIP_PATH="${SCRIPT_LOG%.log}_$TS.zip"
        zip -j "$ZIP_PATH" "$SCRIPT_LOG"
        : > "$SCRIPT_LOG"
        echo "$SCRIPT_NAME ($SCRIPT_VERSION): $(date '+%Y-%m-%d %H:%M:%S') - Old log $log_size bytes, archived to $ZIP_PATH and rotated." >> "$SCRIPT_LOG"
        mv "$ZIP_PATH" "$DEMOTER_LOGS_DIR_ARCHIVE"
        chown -R root:wheel "$DEMOTER_LOGS_DIR_ARCHIVE"
        chmod 600 "$DEMOTER_LOGS_DIR_ARCHIVE" 2>/dev/null

    fi
fi

# Allow-list of admins if not set in config profile
# This is a placeholder for the allow-list. You can add admin usernames here.
# Example: ALLOWED_ADMINS=("admin1" "admin2")
ALLOWED_ADMINS=()

# User-defined variables
ALL_USERS=$(dscl . list /Users UniqueID | awk '$2 >= 501 {print $1}')
CONSOLE_USER=$( scutil <<< "show State:/Users/ConsoleUser" | awk '/Name :/ && !/loginwindow/ { print $3 }' )
CONSOLE_USER_UID=$(id -u "$CONSOLE_USER" 2>/dev/null)

# Functions for logging
function UPDATE_SCRIPT_LOG() {
    echo "${SCRIPT_NAME} ($SCRIPT_VERSION): $(date +%Y-%m-%d\ %H:%M:%S) - ${1}"
}
function NOTICE() {
    UPDATE_SCRIPT_LOG "[NOTICE]          ${1}"
}
function FATAL() {
    UPDATE_SCRIPT_LOG "[FATAL]           ${1}"
    exit 1
}

# Read an array/list from the config profile
get_allowed_admins_from_profile() {
    local admins=()
    if [[ -f "$PROFILE_PLIST" ]]; then
        admins=($(defaults read "$PROFILE_PLIST" AllowedAdmins 2>/dev/null | awk 'NR>1 && !/\)/ {gsub(/[" ,]/,""); if(length($1)>0) print $1}'))
    elif [[ -f "/Library/Managed Preferences/${CONSOLE_USER}/com.demote.adminallow.plist" ]]; then
        # Fallback to user preferences if profile not found
        admins=($(defaults read "/Library/Managed Preferences/${CONSOLE_USER}/com.demote.adminallow.plist" AllowedAdmins 2>/dev/null | awk 'NR>1 && !/\)/ {gsub(/[" ,]/,""); if(length($1)>0) print $1}'))
    else
        FATAL "No allow-list found in profile or user preferences."
    fi
    echo "${admins[@]}"
}

# Read interval from the config profile
get_demoter_interval_from_profile() {
    if [[ -f "$PROFILE_PLIST" ]]; then
        out=$(defaults read "$PROFILE_PLIST" DemoterInterval 2>/dev/null)
    elif [[ -f "/Library/Managed Preferences/${CONSOLE_USER}/com.demote.adminallow.plist" ]]; then
        # Fallback to user preferences if profile not found
        out=$(defaults read "/Library/Managed Preferences/${CONSOLE_USER}/com.demote.adminallow.plist" DemoterInterval 2>/dev/null)
    else
        FATAL "No demoter interval found in profile or user preferences."
    fi
    echo "$out"
}

# Create the log file if it does not exist
touch "${SCRIPT_LOG}" || FATAL "Unable to create log file at $SCRIPT_LOG. Is script running as root?"

profile_allowed_admins=($(get_allowed_admins_from_profile))
profile_demoter_interval=$(get_demoter_interval_from_profile)

if [[ -n "$profile_demoter_interval" && "$profile_demoter_interval" =~ '^[0-9]+$' ]]; then
    DEMOTER_INTERVAL="$profile_demoter_interval"
else
    DEMOTER_INTERVAL="$DEFAULT_DEMOTER_INTERVAL"
fi

if [[ ${#profile_allowed_admins[@]} -gt 0 ]]; then
    ALLOWED_ADMINS=("${profile_allowed_admins[@]}")
else
    ALLOWED_ADMINS=("${DEFAULT_ALLOWED_ADMINS[@]}")
fi

ALLOWED_PATTERN="^($(IFS="|"; echo "${ALLOWED_ADMINS[*]}"))$"

if [[ -d "$PRIV_APP" && -f "$PRIVILEGES_INFOPLIST" ]]; then
    PRIV_PRESENT=true
    PRIV_VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$PRIVILEGES_INFOPLIST" 2>/dev/null | awk '{print $1}')
    PRIV_VERSION_MAJOR=$(echo "${PRIV_VERSION}" | awk -F. '{print $1}')
else
    PRIV_PRESENT=false
fi

if [[ "$CONSOLE_USER" == "loginwindow" || -z "$CONSOLE_USER" ]]; then
    LOGINWINDOW_ACTIVE=true
    NOTICE "Machine is at the login window (no user logged in); will demote all non-allowed admins."
else
    LOGINWINDOW_ACTIVE=false
fi

# --- Main demotion loop ---
for user in $ALL_USERS; do
    if [[ $user =~ $ALLOWED_PATTERN ]]; then
        NOTICE "User $user is allow-listed, skipping."
        continue
    fi

    if dseditgroup -o checkmember -m "$user" admin | grep -q "yes"; then
        keep_admin=false

        # Privileges.app check: only applies for active GUI user, not when at loginwindow
        if [[ "$LOGINWINDOW_ACTIVE" == false && "$PRIV_PRESENT" == "true" && "$user" == "$CONSOLE_USER" && -n "$CONSOLE_USER_UID" ]]; then
            if [[ "$PRIV_VERSION_MAJOR" -ge 2 && -x "$PRIVILEGES_CLI_V2" ]]; then
                status=$(/bin/launchctl asuser "$CONSOLE_USER_UID" sudo -u "$CONSOLE_USER" "$PRIVILEGES_CLI_V2" --status 2>&1)
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
            NOTICE "User $user is currently a Privileges.app admin (still valid) — skipping demotion${timeleft:+ (time left: $timeleft min)}."
            continue
        fi

        if [[ "$LOGINWINDOW_ACTIVE" == true ]]; then
            NOTICE "At loginwindow: Demoting unauthorized admin: $user"
        else
            NOTICE "Demoting unauthorized admin: $user"
        fi
        dseditgroup -o edit -d "$user" admin
    fi
done

# Permissioning, in case the script has been viewed or modified
chown -R root:wheel "${DEMOTER_DIR}"
chmod -R go-rwx "${DEMOTER_DIR}"
chmod 700 "${SCRIPT_PATH}"
chmod 700 "${DEMOTER_LOGS_DIR}"
chmod 700 "${DEMOTER_LOGS_DIR_ARCHIVE}"
chmod 600 "${SCRIPT_LOG}"
exit 0
EOSCPT

if [[ $? -ne 0 ]]; then
    FATAL "Failed to create the script at $SCRIPT_PATH"
fi

# Permissioning
chown -R root:wheel "${DEMOTER_DIR}"
chmod -R go-rwx "${DEMOTER_DIR}"
chmod 700 "${SCRIPT_PATH}"
chmod 700 "${DEMOTER_LOGS_DIR}"
chmod 700 "${DEMOTER_LOGS_DIR_ARCHIVE}"
chmod 600 "${LOG_PATH}"


### ====== Utility Functions ======

# Read an array/list from the config profile
get_allowed_admins_from_profile() {
    local admins=()
    if [[ -f "$PROFILE_PLIST" ]]; then
        admins=($(defaults read "$PROFILE_PLIST" AllowedAdmins 2>/dev/null | awk 'NR>1 && !/\)/ {gsub(/[" ,]/,""); if(length($1)>0) print $1}'))
    elif [[ -f "/Library/Managed Preferences/${CONSOLE_USER}/com.demote.adminallow.plist" ]]; then
        # Fallback to user preferences if profile not found
        admins=($(defaults read "/Library/Managed Preferences/${CONSOLE_USER}/com.demote.adminallow.plist" AllowedAdmins 2>/dev/null | awk 'NR>1 && !/\)/ {gsub(/[" ,]/,""); if(length($1)>0) print $1}'))
    else
        echo "No allow-list found in profile or user preferences."
    fi
    echo "${admins[@]}"
}

# Read interval from the config profile
get_demoter_interval_from_profile() {
    if [[ -f "$PROFILE_PLIST" ]]; then
        out=$(defaults read "$PROFILE_PLIST" DemoterInterval 2>/dev/null)
    elif [[ -f "/Library/Managed Preferences/${CONSOLE_USER}/com.demote.adminallow.plist" ]]; then
        # Fallback to user preferences if profile not found
        out=$(defaults read "/Library/Managed Preferences/${CONSOLE_USER}/com.demote.adminallow.plist" DemoterInterval 2>/dev/null)
    else
        echo "No demoter interval found in profile or user preferences."
    fi
    echo "$out"
}

### ====== Load Config/Defaults ======

# Try to get settings from profile first, fall back if missing
profile_allowed_admins=($(get_allowed_admins_from_profile))
profile_demoter_interval=$(get_demoter_interval_from_profile)

if [[ -n "$profile_demoter_interval" ]]; then
    DEMOTER_INTERVAL="$profile_demoter_interval"
    echo "Demoter interval set to $DEMOTER_INTERVAL seconds from config profile."
else
    DEMOTER_INTERVAL="$DEFAULT_DEMOTER_INTERVAL"
    echo "No interval set in config profile, defaulting to 15 minutes."
fi

if [[ ${#profile_allowed_admins[@]} -gt 0 ]]; then
    ALLOWED_ADMINS=("${profile_allowed_admins[@]}")
else
    ALLOWED_ADMINS=("${DEFAULT_ALLOWED_ADMINS[@]}")
fi

### ====== LaunchDaemon plist (dynamic interval) ======

cat <<EOLD > "$DAEMON_PATH"
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
    <integer>${DEMOTER_INTERVAL}</integer>
    <key>RunAtLoad</key>
    <true/>
    <key>StandardOutPath</key>
    <string>$LOG_PATH</string>
    <key>StandardErrorPath</key>
    <string>$LOG_PATH</string>
</dict>
</plist>
EOLD

if [[ $? -ne 0 ]]; then
    echo "Failed to create the launch daemon at $DAEMON_PATH"
    exit 1
fi

chmod 644 "$DAEMON_PATH"
chown root:wheel "$DAEMON_PATH"

launchctl bootout system "$DAEMON_PATH" 2>/dev/null || \
launchctl unload "$DAEMON_PATH" 2>/dev/null

launchctl load "$DAEMON_PATH"

chmod 755 "$DEMOTER_DIR"
chmod 644 "$DEMOTER_LOGS_DIR"

echo "Demoter installed. Current interval: $DEMOTER_INTERVAL seconds"
echo "Allowed Admins: ${ALLOWED_ADMINS[*]}"
exit 0