#!/bin/bash
### ====== Variables ======
SCRIPT_NAME="DemoteAdmin"
SCRIPT_VERSION="2.24"

DEMOTER_DIR="/Library/Management/.demoter"
SCRIPT_PATH="${DEMOTER_DIR}/.demote-unlisted-admins.sh"
DEMOTER_LOGS_DIR="${DEMOTER_DIR}/logs"
DEMOTER_LOGS_DIR_ARCHIVE="${DEMOTER_LOGS_DIR}/log-archive"
LOG_PATH="${DEMOTER_LOGS_DIR}/demoteadmins.log"
DAEMON_PATH="/Library/LaunchDaemons/com.demote.demoteadmins.plist"
TRIGGER_DAEMON_PATH="/Library/LaunchDaemons/com.demote.privileges-trigger.plist"
TRIGGER_FILE="${DEMOTER_DIR}/.trigger"
WRAPPER_PATH="/usr/local/bin/.privileges-demote-trigger"
PROFILE_PLIST="/Library/Managed Preferences/com.demote.adminallow.plist"
CONSOLE_USER=$( scutil <<< "show State:/Users/ConsoleUser" | awk '/Name :/ && !/loginwindow/ { print $3 }' )

# Remediation artifacts
REMEDIATE_DAEMON="/Library/LaunchDaemons/com.demote.remediate.plist"
REMEDIATE_TRIGGER_SCRIPT="/tmp/demoter-remediate-trigger.sh"
REMEDIATE_LOG="/tmp/demoter-remediate.log"

# Default values
DEFAULT_ALLOWED_ADMINS=()
DEFAULT_DEMOTER_INTERVAL=900

function LOG() {
    echo "${SCRIPT_NAME} ($SCRIPT_VERSION): $(date +%Y-%m-%d\ %H:%M:%S) - ${1}"
}

if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root. Please run with sudo."
    exit 1
fi

### ====== Clean Up Remediation Artifacts (Before Main Cleanup) ======

LOG "=========================================="
LOG "Checking for remediation artifacts..."
LOG "=========================================="

ARTIFACTS_FOUND=false
REMEDIATION_SUCCESSFUL=false

# Check remediation log first (to determine if remediation occurred)
if [[ -f "$REMEDIATE_LOG" ]]; then
    LOG "Found remediation log from previous run"
    
    # Check if remediation was successful
    if grep -q "Remediation successful" "$REMEDIATE_LOG" 2>/dev/null || \
       grep -q "exit code: 0" "$REMEDIATE_LOG" 2>/dev/null; then
        REMEDIATION_SUCCESSFUL=true
        LOG "   Previous remediation completed successfully"
    else
        LOG "     Previous remediation may have had issues"
    fi
    
    ARTIFACTS_FOUND=true
fi

# Unload and remove remediation LaunchDaemon
if [[ -f "$REMEDIATE_DAEMON" ]]; then
    LOG "Cleaning up remediation LaunchDaemon..."
    
    if launchctl list | grep -q "com.demote.remediate"; then
        launchctl bootout system/com.demote.remediate 2>/dev/null || \
        launchctl unload "$REMEDIATE_DAEMON" 2>/dev/null
        LOG "   Unloaded daemon"
    fi
    
    rm -f "$REMEDIATE_DAEMON"
    LOG "   Removed daemon plist"
    ARTIFACTS_FOUND=true
fi

# Remove trigger script
if [[ -f "$REMEDIATE_TRIGGER_SCRIPT" ]]; then
    LOG "Removing trigger script..."
    rm -f "$REMEDIATE_TRIGGER_SCRIPT"
    LOG "   Removed"
    ARTIFACTS_FOUND=true
fi

if [[ "$ARTIFACTS_FOUND" == true ]]; then
    LOG "   Remediation artifacts detected and cleaned"
    LOG ""
fi

### ====== Smart Cleanup (Preserve Logs) ======

LOG "Checking for existing installation..."

# Create timestamped backup directory
TEMP_BACKUP_DIR="/tmp/demoter-backup-$(date +%Y%m%d-%H%M%S)"
BACKUP_SUCCESS=false

if [[ -d "$DEMOTER_DIR" ]]; then
    LOG "=========================================="
    LOG "Existing installation found - performing smart cleanup"
    LOG "=========================================="
    
    # Unload daemons
    LOG "Step 1/6: Unloading LaunchDaemons..."
    launchctl bootout system/com.demote.demoteadmins 2>/dev/null && LOG "   Unloaded com.demote.demoteadmins"
    launchctl bootout system/com.demote.privileges-trigger 2>/dev/null && LOG "   Unloaded com.demote.privileges-trigger"
    
    # Backup logs if they exist
    if [[ -d "${DEMOTER_DIR}/logs" ]]; then
        LOG "Step 2/6: Backing up logs..."
        mkdir -p "$TEMP_BACKUP_DIR"
        
        TOTAL_LOG_SIZE=$(du -sh "${DEMOTER_DIR}/logs" 2>/dev/null | awk '{print $1}')
        LOG_FILE_COUNT=$(find "${DEMOTER_DIR}/logs" -type f 2>/dev/null | wc -l | tr -d ' ')
        
        LOG "  - Log directory size: ${TOTAL_LOG_SIZE}"
        LOG "  - Total log files: ${LOG_FILE_COUNT}"
        
        if cp -pR "${DEMOTER_DIR}/logs" "$TEMP_BACKUP_DIR/" 2>/dev/null; then
            LOG "   Logs backed up to: $TEMP_BACKUP_DIR"
            BACKUP_SUCCESS=true
            
            BACKUP_FILE_COUNT=$(find "$TEMP_BACKUP_DIR/logs" -type f 2>/dev/null | wc -l | tr -d ' ')
            if [[ "$BACKUP_FILE_COUNT" -eq "$LOG_FILE_COUNT" ]]; then
                LOG "   Backup verified ($BACKUP_FILE_COUNT files)"
            else
                LOG "     Backup file count mismatch (original: $LOG_FILE_COUNT, backup: $BACKUP_FILE_COUNT)"
            fi
        else
            LOG "   Failed to backup logs"
        fi
    else
        LOG "Step 2/6: No logs directory found to preserve"
    fi
    
    # Backup tamper events
    if [[ -f "${DEMOTER_DIR}/.tamper-events" ]]; then
        LOG "Step 3/6: Backing up tamper event log..."
        if [[ -d "$TEMP_BACKUP_DIR" ]] || mkdir -p "$TEMP_BACKUP_DIR"; then
            if cp -p "${DEMOTER_DIR}/.tamper-events" "$TEMP_BACKUP_DIR/" 2>/dev/null; then
                LOG "   Tamper events backed up"
            else
                LOG "     Failed to backup tamper events"
            fi
        fi
    else
        LOG "Step 3/6: No tamper events to preserve"
    fi
    
    # Remove entire demoter directory
    LOG "Step 4/6: Removing old installation..."
    if rm -rf "$DEMOTER_DIR" 2>/dev/null; then
        LOG "   Demoter directory removed"
    else
        LOG "   Failed to remove demoter directory"
    fi
    
    # Remove LaunchDaemons
    LOG "Step 5/6: Removing LaunchDaemons..."
    REMOVED_COUNT=0
    for plist in /Library/LaunchDaemons/com.demote.*.plist; do
        if [[ -f "$plist" ]]; then
            rm -f "$plist" && ((REMOVED_COUNT++))
        fi
    done
    LOG "   Removed $REMOVED_COUNT LaunchDaemon(s)"
    
    # Remove wrapper
    LOG "Step 6/6: Removing wrapper script..."
    if [[ -f "$WRAPPER_PATH" ]]; then
        rm -f "$WRAPPER_PATH" && LOG "   Wrapper removed"
    else
        LOG "  - Wrapper not found (already removed)"
    fi
    
    LOG "=========================================="
    LOG "Cleanup complete"
    LOG "=========================================="
    echo ""
else
    LOG "Clean installation - no existing files found"
fi

### ====== Create Fresh Directory Structure ======

LOG "Creating fresh directory structure..."

# Create main directory
if mkdir -p "$DEMOTER_DIR" 2>/dev/null; then
    LOG " Created $DEMOTER_DIR"
    chmod 700 "$DEMOTER_DIR"
    chown root:wheel "$DEMOTER_DIR"
else
    LOG " Failed to create $DEMOTER_DIR"
    exit 1
fi

# Create logs directory
if mkdir -p "$DEMOTER_LOGS_DIR" 2>/dev/null; then
    LOG " Created $DEMOTER_LOGS_DIR"
    chmod 700 "$DEMOTER_LOGS_DIR"
    chown root:wheel "$DEMOTER_LOGS_DIR"
else
    LOG " Failed to create $DEMOTER_LOGS_DIR"
    exit 1
fi

# Create log archive directory
if mkdir -p "$DEMOTER_LOGS_DIR_ARCHIVE" 2>/dev/null; then
    LOG " Created $DEMOTER_LOGS_DIR_ARCHIVE"
    chmod 700 "$DEMOTER_LOGS_DIR_ARCHIVE"
    chown root:wheel "$DEMOTER_LOGS_DIR_ARCHIVE"
else
    LOG "   Failed to create archive directory"
fi

### ====== Restore Logs from Backup ======

if [[ "$BACKUP_SUCCESS" == true ]] && [[ -d "$TEMP_BACKUP_DIR/logs" ]]; then
    LOG "Restoring logs from backup..."
    
    # Restore main logs
    if cp -pR "$TEMP_BACKUP_DIR/logs/"* "$DEMOTER_LOGS_DIR/" 2>/dev/null; then
        LOG "  Logs restored successfully"
        
        RESTORED_FILE_COUNT=$(find "$DEMOTER_LOGS_DIR" -type f 2>/dev/null | wc -l | tr -d ' ')
        LOG "  - Restored files: $RESTORED_FILE_COUNT"
        
        if [[ -f "${DEMOTER_LOGS_DIR}/demoteadmins.log" ]]; then
            LOG_SIZE=$(du -sh "${DEMOTER_LOGS_DIR}/demoteadmins.log" 2>/dev/null | awk '{print $1}')
            LOG "  - Main log size: ${LOG_SIZE}"
        fi
        
        if [[ -d "${DEMOTER_LOGS_DIR}/log-archive" ]]; then
            ARCHIVE_COUNT=$(find "${DEMOTER_LOGS_DIR}/log-archive" -type f 2>/dev/null | wc -l | tr -d ' ')
            ARCHIVE_SIZE=$(du -sh "${DEMOTER_LOGS_DIR}/log-archive" 2>/dev/null | awk '{print $1}')
            LOG "  - Archived logs: $ARCHIVE_COUNT file(s), ${ARCHIVE_SIZE}"
        fi
    else
        LOG "   Failed to restore some logs"
    fi
    
    # Restore tamper events
    if [[ -f "$TEMP_BACKUP_DIR/.tamper-events" ]]; then
        if cp -p "$TEMP_BACKUP_DIR/.tamper-events" "$DEMOTER_DIR/" 2>/dev/null; then
            LOG "  Tamper events restored"
            chmod 400 "${DEMOTER_DIR}/.tamper-events"
            chown root:wheel "${DEMOTER_DIR}/.tamper-events"
        fi
    fi
    
    # Clean up temporary backup
    LOG "Cleaning up temporary backup..."
    if rm -rf "$TEMP_BACKUP_DIR" 2>/dev/null; then
        LOG "  Temporary backup removed"
    else
        LOG "   Failed to remove temporary backup at $TEMP_BACKUP_DIR"
    fi
else
    LOG "No logs to restore (fresh installation)"
fi

### ====== Check for Orphaned Backup Directories ======
LOG "=========================================="
LOG "Checking for orphaned backup directories..."
LOG "=========================================="

# Find all demoter backup directories (handle both /tmp and /private/tmp)
shopt -s nullglob 
ORPHANED_BACKUPS=(/private/tmp/demoter-uninstall-backup-* /tmp/demoter-uninstall-backup-*)
shopt -u nullglob

if [[ ${#ORPHANED_BACKUPS[@]} -gt 0 ]]; then
    ORPHAN_COUNT=${#ORPHANED_BACKUPS[@]}
    LOG "Found $ORPHAN_COUNT orphaned backup director(ies)"
    LOG ""
    
    # Ensure archive directory exists
    mkdir -p "$DEMOTER_LOGS_DIR_ARCHIVE"
    
    ARCHIVED_COUNT=0
    REMOVED_COUNT=0
    
    for backup_dir in "${ORPHANED_BACKUPS[@]}"; do
        # Skip if not a directory or doesn't exist
        [[ ! -d "$backup_dir" ]] && continue
        
        BACKUP_NAME=$(basename "$backup_dir")
        LOG "Processing: $BACKUP_NAME"
        
        # Extract timestamp from directory name
        BACKUP_TIMESTAMP=$(echo "$BACKUP_NAME" | grep -oE '[0-9]{8}-[0-9]{6}' | head -1)
        
        if [[ -z "$BACKUP_TIMESTAMP" ]]; then
            LOG "     Could not extract timestamp, using current time"
            BACKUP_TIMESTAMP=$(date +%Y%m%d-%H%M%S)
        fi
        
        # Check if backup has logs
        if [[ -d "$backup_dir/logs" ]] && [[ -n "$(ls -A "$backup_dir/logs" 2>/dev/null)" ]]; then
            LOG "     Backup contains logs, archiving..."
            
            ARCHIVE_NAME="backup-logs-${BACKUP_TIMESTAMP}.tar.gz"
            ARCHIVE_PATH="${DEMOTER_LOGS_DIR_ARCHIVE}/${ARCHIVE_NAME}"
            
            if tar -czf "$ARCHIVE_PATH" -C "$backup_dir" logs 2>/dev/null; then
                LOG "    Archived to: ${ARCHIVE_NAME}"
                chmod 400 "$ARCHIVE_PATH"
                chown root:wheel "$ARCHIVE_PATH"
                
                ARCHIVE_SIZE=$(du -h "$ARCHIVE_PATH" | awk '{print $1}')
                LOG "    Size: ${ARCHIVE_SIZE}"
                ((ARCHIVED_COUNT++))
            else
                LOG "    Failed to create archive"
            fi
        else
            LOG "     Backup empty or no logs, skipping archive"
        fi
        
        # Check for tamper events in backup
        if [[ -f "$backup_dir/.tamper-events" ]]; then
            TAMPER_ARCHIVE_NAME="tamper-events-${BACKUP_TIMESTAMP}.log"
            TAMPER_ARCHIVE_PATH="${DEMOTER_LOGS_DIR_ARCHIVE}/${TAMPER_ARCHIVE_NAME}"
            
            if cp -p "$backup_dir/.tamper-events" "$TAMPER_ARCHIVE_PATH" 2>/dev/null; then
                LOG "    Tamper events archived: ${TAMPER_ARCHIVE_NAME}"
                chmod 400 "$TAMPER_ARCHIVE_PATH"
                chown root:wheel "$TAMPER_ARCHIVE_PATH"
            fi
        fi
        
        # Remove the orphaned backup directory
        if rm -rf "$backup_dir" 2>/dev/null; then
            LOG "    Removed orphaned backup directory"
            ((REMOVED_COUNT++))
        else
            LOG "     Failed to remove: $backup_dir"
        fi
        
        LOG ""
    done
    
    LOG "=========================================="
    LOG "Orphaned Backup Summary:"
    LOG "  - Directories processed: $ORPHAN_COUNT"
    LOG "  - Logs archived: $ARCHIVED_COUNT"
    LOG "  - Directories removed: $REMOVED_COUNT"
    LOG "=========================================="
    LOG ""
else
    LOG "  No orphaned backup directories found"
    LOG ""
fi

### ====== Archive Remediation Log ======

if [[ -f "$REMEDIATE_LOG" ]]; then
    LOG "=========================================="
    LOG "Archiving remediation log..."
    LOG "=========================================="
    
    # Create archive directory if it doesn't exist
    mkdir -p "$DEMOTER_LOGS_DIR_ARCHIVE"
    
    # Generate archive filename with timestamp
    ARCHIVE_NAME="remediation-$(date +%Y%m%d-%H%M%S).log"
    ARCHIVE_PATH="${DEMOTER_LOGS_DIR_ARCHIVE}/${ARCHIVE_NAME}"
    
    # Copy remediation log to archive
    if cp -p "$REMEDIATE_LOG" "$ARCHIVE_PATH" 2>/dev/null; then
        LOG "  Remediation log archived to: ${ARCHIVE_NAME}"
        
        # Set proper permissions
        chmod 400 "$ARCHIVE_PATH"
        chown root:wheel "$ARCHIVE_PATH"
        
        # Show summary of remediation log
        LOG ""
        LOG "Remediation Log Summary:"
        LOG "------------------------"
        
        # Show first line (timestamp)
        head -1 "$ARCHIVE_PATH" | while read line; do
            LOG "  $line"
        done
        
        # Show last 5 lines
        LOG "  ..."
        tail -5 "$ARCHIVE_PATH" | while read line; do
            LOG "  $line"
        done
        
        LOG ""
        
        # Add success indicator to main log
        if [[ "$REMEDIATION_SUCCESSFUL" == true ]]; then
            LOG "   Previous remediation completed successfully"
        else
            LOG "   Previous remediation may have encountered issues"
            LOG "   Review archived log: ${ARCHIVE_PATH}"
        fi
        
        # Remove the temp log after successful archiving
        rm -f "$REMEDIATE_LOG"
        LOG "  Temporary remediation log removed"
        
    else
        LOG "  Failed to archive remediation log"
        LOG "  Temporary log remains at: $REMEDIATE_LOG"
    fi
    
    LOG "=========================================="
    LOG ""
fi

### ====== Initialize Log File ======

if [[ ! -f "$LOG_PATH" ]]; then
    LOG "Creating new script log at $LOG_PATH"
    if touch "$LOG_PATH" 2>/dev/null; then
        chmod 600 "$LOG_PATH"
        chown root:wheel "$LOG_PATH"
        LOG " Log file created"
    else
        LOG " Failed to create script log at $LOG_PATH"
        exit 1
    fi
else
    LOG " Log file exists (restored from backup)"
    chmod 600 "$LOG_PATH"
    chown root:wheel "$LOG_PATH"
fi

LOG ""
LOG "=========================================="
LOG "Directory setup complete"
LOG "=========================================="
echo ""

### ====== Preserve Tracking Data Before Overwriting Script ======
TRACKING_DIR="/var/db/.systemconfig"
TRACKING_PLIST="${TRACKING_DIR}/.tracking.plist"

# Initialize variables
PRESERVED_TAMPER=0
PRESERVED_WARNING=0
PRESERVED_AUTOFIX=0
PRESERVED_DEMOTION_COUNT=0
PRESERVED_LAST_DEPLOY=""
PRESERVED_VERSION="unknown"
PRESERVED_NOTIFY_FLAG="false"

# Read existing tracking data if it exists
if [[ -f "$TRACKING_PLIST" ]]; then
    echo " Reading existing tracking data..."
    
    # Temporarily unlock to read
    chflags nouchg "$TRACKING_PLIST" 2>/dev/null
    chmod 600 "$TRACKING_PLIST" 2>/dev/null
    
    # Preserve values
    PRESERVED_TAMPER=$(defaults read "$TRACKING_PLIST" "tamperCount" 2>/dev/null || echo "0")
    PRESERVED_WARNING=$(defaults read "$TRACKING_PLIST" "warningAcknowledged" 2>/dev/null || echo "0")
    PRESERVED_AUTOFIX=$(defaults read "$TRACKING_PLIST" "autoFixCount" 2>/dev/null || echo "0")
    PRESERVED_DEMOTION_COUNT=$(defaults read "$TRACKING_PLIST" "demotionCount" 2>/dev/null || echo "0")
    PRESERVED_LAST_DEPLOY=$(defaults read "$TRACKING_PLIST" "lastDeployment" 2>/dev/null || echo "")
    PRESERVED_VERSION=$(defaults read "$TRACKING_PLIST" "version" 2>/dev/null || echo "unknown")
    PRESERVED_NOTIFY_FLAG=$(defaults read "$TRACKING_PLIST" "pendingUserNotification" 2>/dev/null || echo "false")

    echo "   • Tamper Count: $PRESERVED_TAMPER"
    echo "   • Warning Acknowledged: $PRESERVED_WARNING"
    echo "   • Auto-Fix Count: $PRESERVED_AUTOFIX"
    echo "   • Demotion Count: $PRESERVED_DEMOTION_COUNT"
    echo "   • Previous Version: $PRESERVED_VERSION"
else
    echo " No existing tracking data found - this is a new installation"
fi

### ====== Write Demoter Script ======
cat << 'EOSCPT' > "$SCRIPT_PATH"
#!/bin/bash
# === Configuration Paths ===
SCRIPT_NAME="DemoteAdmin"
SCRIPT_VERSION="2.24"
DEMOTER_DIR="/Library/Management/.demoter"
DEMOTER_LOGS_DIR="${DEMOTER_DIR}/logs"
DEMOTER_LOGS_DIR_ARCHIVE="${DEMOTER_LOGS_DIR}/log-archive"
SCRIPT_LOG="${DEMOTER_LOGS_DIR}/demoteadmins.log"
TRIGGER_FILE="${DEMOTER_DIR}/.trigger"

# Auto-detect script path
SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
PROFILE_PLIST="/Library/Managed Preferences/com.demote.adminallow.plist"

# Tracking for tamper detection
TRACKING_DIR="/var/db/.systemconfig"
TRACKING_PLIST="${TRACKING_DIR}/.tracking.plist"

# === Privileges App Paths ===
PRIV_APP="/Applications/Privileges.app"
PRIVILEGES_INFOPLIST="$PRIV_APP/Contents/Info.plist"
PRIVILEGES_CLI_V1="$PRIV_APP/Contents/Resources/PrivilegesCLI"
PRIVILEGES_CLI_V2="$PRIV_APP/Contents/MacOS/PrivilegesCLI"

# === Default Values ===
DEFAULT_ALLOWED_ADMINS=()
DEFAULT_DEMOTER_INTERVAL=900

# === Create log if doesn't exist ===
mkdir -p "$DEMOTER_LOGS_DIR"
touch "$SCRIPT_LOG"

# === Functions for logging ===
function UPDATE_SCRIPT_LOG() {
    echo "${SCRIPT_NAME} ($SCRIPT_VERSION): $(date +%Y-%m-%d\ %H:%M:%S) - ${1}" >> "$SCRIPT_LOG"
}
function NOTICE() {
    UPDATE_SCRIPT_LOG "[NOTICE]          ${1}"
}
function FATAL() {
    UPDATE_SCRIPT_LOG "[FATAL]           ${1}"
    exit 1
}

# === Function to increment tamper count ===
increment_tamper_count() {
    if [[ -f "$TRACKING_PLIST" ]]; then
        chflags nouchg "$TRACKING_PLIST" 2>/dev/null
        chmod 600 "$TRACKING_PLIST" 2>/dev/null
        
        current_count=$(defaults read "$TRACKING_PLIST" "tamperCount" 2>/dev/null || echo "0")
        new_count=$((current_count + 1))
        
        defaults write "$TRACKING_PLIST" "tamperCount" -int "$new_count"
        defaults write "$TRACKING_PLIST" "lastTamperDetected" "$(date '+%Y-%m-%d %H:%M:%S')"
        
        chmod 400 "$TRACKING_PLIST" 2>/dev/null
        chflags uchg "$TRACKING_PLIST" 2>/dev/null
        
        NOTICE "  Tamper count incremented: $current_count → $new_count"
    fi
}

# === Function to increment autofix count ===
increment_autofix_count() {
    if [[ -f "$TRACKING_PLIST" ]]; then
        chflags nouchg "$TRACKING_PLIST" 2>/dev/null
        chmod 600 "$TRACKING_PLIST" 2>/dev/null
        
        current_count=$(defaults read "$TRACKING_PLIST" "autoFixCount" 2>/dev/null || echo "0")
        new_count=$((current_count + 1))
        
        defaults write "$TRACKING_PLIST" "autoFixCount" -int "$new_count"
        defaults write "$TRACKING_PLIST" "lastAutoFix" "$(date '+%Y-%m-%d %H:%M:%S')"
        
        chmod 400 "$TRACKING_PLIST" 2>/dev/null
        chflags uchg "$TRACKING_PLIST" 2>/dev/null
        
        NOTICE " Auto-fix count incremented: $current_count → $new_count"
    fi
}

# === Self-Healing Permission Check ===
check_and_fix_permissions() {
    local changes_made=false
    local trigger_remediation=false
    
    # Ensure log is writable temporarily
    chmod 600 "$SCRIPT_LOG" 2>/dev/null
    
    # Check trigger file (minor issue - auto-fix)
    if [[ -f "$TRIGGER_FILE" ]]; then
        current_perms=$(stat -f "%Sp" "$TRIGGER_FILE" 2>/dev/null)
        if [[ "$current_perms" != "-rw-rw-rw-" ]]; then
            NOTICE "Trigger file permissions incorrect ($current_perms), fixing to 666"
            chmod 666 "$TRIGGER_FILE" 2>/dev/null
            changes_made=true
            NOTICE "Calling increment_autofix_count from permissions check"
            increment_autofix_count
        fi
        current_owner=$(stat -f "%Su:%Sg" "$TRIGGER_FILE" 2>/dev/null)
        if [[ "$current_owner" != "root:wheel" ]]; then
            NOTICE "Trigger file ownership incorrect ($current_owner), fixing"
            chown root:wheel "$TRIGGER_FILE" 2>/dev/null
            changes_made=true
            NOTICE "Calling increment_autofix_count from ownership check"
            increment_autofix_count
        fi
    else
        NOTICE "Trigger file missing, recreating"
        touch "$TRIGGER_FILE"
        chmod 666 "$TRIGGER_FILE"
        chown root:wheel "$TRIGGER_FILE"
        changes_made=true
        NOTICE "Calling increment_autofix_count from missing trigger file"
        increment_autofix_count
    fi
    
    # Check script itself (CRITICAL - triggers full reinstall)
    current_script_perms=$(stat -f "%Sp" "$SCRIPT_PATH" 2>/dev/null)
    if [[ "$current_script_perms" != "-r-x------" ]]; then
        NOTICE "  CRITICAL: Script permissions incorrect ($current_script_perms)"
        NOTICE "   Expected: -r-x------ (500)"
        trigger_remediation=true
        NOTICE "Calling increment_tamper_count from script permissions check"
        increment_tamper_count
    fi
    
    # Check base directory (CRITICAL)
    current_dir_perms=$(stat -f "%Sp" "$DEMOTER_DIR" 2>/dev/null)
    if [[ "$current_dir_perms" != "drwx------" ]]; then
        NOTICE "  CRITICAL: Directory permissions incorrect ($current_dir_perms)"
        NOTICE "   Expected: drwx------ (700)"
        trigger_remediation=true
        NOTICE "Calling increment_tamper_count from directory permissions check"
        increment_tamper_count
    fi
    
    # Check log directory (CRITICAL)
    if [[ -d "$DEMOTER_LOGS_DIR" ]]; then
        current_log_perms=$(stat -f "%Sp" "$DEMOTER_LOGS_DIR" 2>/dev/null)
        if [[ "$current_log_perms" != "drwx------" ]]; then
            NOTICE "  CRITICAL: Log directory permissions incorrect ($current_log_perms)"
            NOTICE "   Expected: drwx------ (700)"
            trigger_remediation=true
            NOTICE "Calling increment_tamper_count from log directory permissions check"
            increment_tamper_count
        fi
    fi
    
    # Check archive directory (CRITICAL)
    if [[ -d "$DEMOTER_LOGS_DIR_ARCHIVE" ]]; then
        current_archive_perms=$(stat -f "%Sp" "$DEMOTER_LOGS_DIR_ARCHIVE" 2>/dev/null)
        if [[ "$current_archive_perms" != "drwx------" ]]; then
            NOTICE "  CRITICAL: Archive directory permissions incorrect ($current_archive_perms)"
            NOTICE "   Expected: drwx------ (700)"
            trigger_remediation=true
            NOTICE "Calling increment_tamper_count from archive directory permissions check"
            increment_tamper_count
        fi
    fi
    
    # Check file content integrity via stored SHA-256 hashes
    if [[ -f "$TRACKING_PLIST" ]]; then
        chflags nouchg "$TRACKING_PLIST" 2>/dev/null
        chmod 600 "$TRACKING_PLIST" 2>/dev/null

        stored_script_sha=$(defaults read "$TRACKING_PLIST" "scriptHash" 2>/dev/null)
        stored_wrapper_sha=$(defaults read "$TRACKING_PLIST" "wrapperHash" 2>/dev/null)
        stored_daemon_sha=$(defaults read "$TRACKING_PLIST" "daemonHash" 2>/dev/null)
        stored_trigger_sha=$(defaults read "$TRACKING_PLIST" "triggerDaemonHash" 2>/dev/null)

        chmod 400 "$TRACKING_PLIST" 2>/dev/null
        chflags uchg "$TRACKING_PLIST" 2>/dev/null

        if [[ -n "$stored_script_sha" ]]; then
            current_script_sha=$(openssl sha256 "$SCRIPT_PATH" 2>/dev/null | awk '{print $2}')
            if [[ "$current_script_sha" != "$stored_script_sha" ]]; then
                NOTICE "  CRITICAL: Script content hash mismatch — file may have been modified"
                trigger_remediation=true
                NOTICE "Calling increment_tamper_count from hash verification"
                increment_tamper_count
            fi
        fi

        if [[ -n "$stored_wrapper_sha" ]]; then
            current_wrapper_sha=$(openssl sha256 /usr/local/bin/.privileges-demote-trigger 2>/dev/null | awk '{print $2}')
            if [[ "$current_wrapper_sha" != "$stored_wrapper_sha" ]]; then
                NOTICE "  CRITICAL: Wrapper content hash mismatch — file may have been modified"
                trigger_remediation=true
                NOTICE "Calling increment_tamper_count from hash verification"
                increment_tamper_count
            fi
        fi

        if [[ -n "$stored_daemon_sha" ]]; then
            current_daemon_sha=$(openssl sha256 /Library/LaunchDaemons/com.demote.demoteadmins.plist 2>/dev/null | awk '{print $2}')
            if [[ "$current_daemon_sha" != "$stored_daemon_sha" ]]; then
                NOTICE "  CRITICAL: Daemon plist hash mismatch — file may have been modified"
                trigger_remediation=true
                NOTICE "Calling increment_tamper_count from hash verification"
                increment_tamper_count
            fi
        fi

        if [[ -n "$stored_trigger_sha" ]]; then
            current_trigger_sha=$(openssl sha256 /Library/LaunchDaemons/com.demote.privileges-trigger.plist 2>/dev/null | awk '{print $2}')
            if [[ "$current_trigger_sha" != "$stored_trigger_sha" ]]; then
                NOTICE "  CRITICAL: Trigger daemon hash mismatch — file may have been modified"
                trigger_remediation=true
                NOTICE "Calling increment_tamper_count from hash verification"
                increment_tamper_count
            fi
        fi
    fi

    # If critical permissions or hashes are wrong, create remediation trigger
    if [[ "$trigger_remediation" == true ]]; then
        NOTICE "=========================================="
        NOTICE "  CRITICAL SECURITY VIOLATION DETECTED"
        NOTICE "=========================================="
        NOTICE "Creating self-destruct trigger mechanism"
        
        # Create remediation trigger script with PROPER DELAY
cat > /tmp/demoter-remediate-trigger.sh << 'EOREMEDY'
#!/bin/bash
# Set explicit PATH
export PATH="/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

# Wait for parent script to fully exit and release locks
sleep 10

# Log with timestamps
log_msg() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> /tmp/demoter-remediate.log
}

log_msg "=== Remediation Starting ==="
log_msg "PATH: $PATH"


# Call Jamf with timeout protection
log_msg "Calling Jamf policy: redeployDemoter"
/usr/local/bin/jamf policy -event redeployDemoter 2>&1

EXIT_CODE=${PIPESTATUS[0]}
if [[ $EXIT_CODE -eq 0 ]]; then
    log_msg "Remediation successful"
else
    log_msg "Remediation failed with code $EXIT_CODE"
fi

# Self-cleanup
sleep 2
log_msg "Cleaning up remediation LaunchDaemon"
launchctl bootout system/com.demote.remediate 2>/dev/null
rm -f /Library/LaunchDaemons/com.demote.remediate.plist

log_msg "=== Remediation Complete ==="

exit $EXIT_CODE
EOREMEDY

chmod 755 /tmp/demoter-remediate-trigger.sh
chown root:wheel /tmp/demoter-remediate-trigger.sh

# Create LaunchDaemon with StartInterval instead of RunAtLoad
cat > /Library/LaunchDaemons/com.demote.remediate.plist << 'EOPLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.demote.remediate</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>-c</string>
        <string>exec /tmp/demoter-remediate-trigger.sh</string>
    </array>
    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
    </dict>
    <key>StartInterval</key>
    <integer>5</integer>
    <key>StandardOutPath</key>
    <string>/tmp/demoter-remediate.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/demoter-remediate.log</string>
    <key>AbandonProcessGroup</key>
    <true/>
    <key>ProcessType</key>
    <string>Background</string>
</dict>
</plist>
EOPLIST

chmod 644 /Library/LaunchDaemons/com.demote.remediate.plist
chown root:wheel /Library/LaunchDaemons/com.demote.remediate.plist
        
        if [[ $? -ne 0 ]]; then
            NOTICE " Failed to create remediation LaunchDaemon"
            exit 1
        fi
        
        NOTICE " Remediation LaunchDaemon created: com.demote.remediate.plist"
        
        # Load the LaunchDaemon
        launchctl bootstrap system /Library/LaunchDaemons/com.demote.remediate.plist 2>/dev/null
        
        if [[ $? -eq 0 ]]; then
            NOTICE " Remediation LaunchDaemon loaded successfully"
        else
            # Try alternative load method
            launchctl load /Library/LaunchDaemons/com.demote.remediate.plist 2>/dev/null
            NOTICE "  Used alternative load method"
        fi
        
        NOTICE "=========================================="
        NOTICE "Self-destruct sequence initiated"
        NOTICE "This script will now exit"
        NOTICE "Reinstallation will occur in ~15 seconds"
        NOTICE "=========================================="
        NOTICE "Check logs:"
        NOTICE "  • Trigger log: /tmp/demoter-remediate.log"
        NOTICE "  • Main log: $SCRIPT_LOG"
        
        # Flag that a user notification should be shown after remediation completes
        if [[ -f "$TRACKING_PLIST" ]]; then
            chflags nouchg "$TRACKING_PLIST" 2>/dev/null
            chmod 600 "$TRACKING_PLIST" 2>/dev/null
            defaults write "$TRACKING_PLIST" "pendingUserNotification" -bool true
            chmod 400 "$TRACKING_PLIST" 2>/dev/null
            chflags uchg "$TRACKING_PLIST" 2>/dev/null
        fi

        # Flush logs to disk
        sync

        # Exit immediately to allow remediation
        exit 0
    fi
    
    if [[ "$changes_made" == true ]]; then
        NOTICE "Minor permission corrections completed"
    fi
}

# === Run permission check FIRST ===
check_and_fix_permissions

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
        NOTICE "Old log $log_size bytes, archived to $ZIP_PATH and rotated."
        mv "$ZIP_PATH" "$DEMOTER_LOGS_DIR_ARCHIVE"
        chown root:wheel "$DEMOTER_LOGS_DIR_ARCHIVE"/*
        chmod 600 "$DEMOTER_LOGS_DIR_ARCHIVE"/*.zip 2>/dev/null
    fi
fi

# User-defined variables
ALL_USERS=$(dscl . list /Users UniqueID | awk '$2 >= 501 {print $1}')
CONSOLE_USER=$( scutil <<< "show State:/Users/ConsoleUser" | awk '/Name :/ && !/loginwindow/ { print $3 }' )
CONSOLE_USER_UID=$(id -u "$CONSOLE_USER" 2>/dev/null)

# Read config profile functions
get_allowed_admins_from_profile() {
    local admins=()
    if [[ -f "$PROFILE_PLIST" ]]; then
        admins=($(defaults read "$PROFILE_PLIST" AllowedAdmins 2>/dev/null | awk 'NR>1 && !/\)/ {gsub(/[" ,]/,""); if(length($1)>0) print $1}'))
    elif [[ -f "/Library/Managed Preferences/${CONSOLE_USER}/com.demote.adminallow.plist" ]]; then
        admins=($(defaults read "/Library/Managed Preferences/${CONSOLE_USER}/com.demote.adminallow.plist" AllowedAdmins 2>/dev/null | awk 'NR>1 && !/\)/ {gsub(/[" ,]/,""); if(length($1)>0) print $1}'))
    else
        FATAL "No allow-list found in profile or user preferences."
    fi
    echo "${admins[@]}"
}

get_demoter_interval_from_profile() {
    if [[ -f "$PROFILE_PLIST" ]]; then
        out=$(defaults read "$PROFILE_PLIST" DemoterInterval 2>/dev/null)
    elif [[ -f "/Library/Managed Preferences/${CONSOLE_USER}/com.demote.adminallow.plist" ]]; then
        out=$(defaults read "/Library/Managed Preferences/${CONSOLE_USER}/com.demote.adminallow.plist" DemoterInterval 2>/dev/null)
    else
        FATAL "No demoter interval found in profile or user preferences."
    fi
    echo "$out"
}

# Log Privileges events
log_recent_privileges_events() {
    echo "-------- Recent Privileges Events since last run: $(date '+%Y-%m-%d %H:%M:%S') --------" >> "$SCRIPT_LOG"
    if [[ $EUID -eq 0 ]]; then
        if log show --style syslog --last 16m --predicate '(process "PrivilegesAgent" && eventMessage BEGINSWITH "SAPCorp: A") OR (process "PrivilegesDaemon" && eventMessage BEGINSWITH "SAPCorp: U")' 2>/dev/null | grep "SAPCorp:" >> "$SCRIPT_LOG" 2>&1; then
            echo "(Log collection successful)" >> "$SCRIPT_LOG"
        else
            echo "(No recent Privileges events found)" >> "$SCRIPT_LOG"
        fi
    else
        echo "(Log collection skipped - requires root)" >> "$SCRIPT_LOG"
    fi
    echo "------------------------ End of Privileges Events ------------------------" >> "$SCRIPT_LOG"
}

profile_allowed_admins=($(get_allowed_admins_from_profile))
profile_demoter_interval=$(get_demoter_interval_from_profile)

if [[ -n "$profile_demoter_interval" && "$profile_demoter_interval" =~ ^[0-9]+$ ]]; then
    DEMOTER_INTERVAL="$profile_demoter_interval"
else
    DEMOTER_INTERVAL="$DEFAULT_DEMOTER_INTERVAL"
fi

# Sync LaunchDaemon StartInterval with profile value if it has drifted
DAEMON_PLIST="/Library/LaunchDaemons/com.demote.demoteadmins.plist"
if [[ -f "$DAEMON_PLIST" ]]; then
    current_interval=$(/usr/libexec/PlistBuddy -c "Print :StartInterval" "$DAEMON_PLIST" 2>/dev/null)
    if [[ -n "$current_interval" && "$current_interval" != "$DEMOTER_INTERVAL" ]]; then
        NOTICE "Interval mismatch — daemon: ${current_interval}s, profile: ${DEMOTER_INTERVAL}s — updating"
        /usr/libexec/PlistBuddy -c "Set :StartInterval $DEMOTER_INTERVAL" "$DAEMON_PLIST" 2>/dev/null
        launchctl bootout system/com.demote.demoteadmins 2>/dev/null
        launchctl bootstrap system "$DAEMON_PLIST" 2>/dev/null
        NOTICE "LaunchDaemon reloaded with updated interval: ${DEMOTER_INTERVAL}s"
    fi
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

# Main demotion loop
for user in $ALL_USERS; do
    if [[ $user =~ $ALLOWED_PATTERN ]]; then
        NOTICE "User $user is allow-listed, skipping."
        continue
    fi

    if dseditgroup -o checkmember -m "$user" admin | grep -q "yes"; then
        keep_admin=false

        if [[ "$LOGINWINDOW_ACTIVE" == false && "$PRIV_PRESENT" == true && "$user" == "$CONSOLE_USER" && -n "$CONSOLE_USER_UID" ]]; then
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
        if dseditgroup -o edit -d "$user" admin; then
            if [[ -f "$TRACKING_PLIST" ]]; then
                chflags nouchg "$TRACKING_PLIST" 2>/dev/null
                chmod 600 "$TRACKING_PLIST" 2>/dev/null
                current_demotion_count=$(defaults read "$TRACKING_PLIST" "demotionCount" 2>/dev/null || echo "0")
                new_demotion_count=$((current_demotion_count + 1))
                defaults write "$TRACKING_PLIST" "demotionCount"      -int "$new_demotion_count"
                defaults write "$TRACKING_PLIST" "lastDemotedAccount" "$user"
                defaults write "$TRACKING_PLIST" "lastDemotionTime"   "$(date '+%Y-%m-%d %H:%M:%S')"
                chmod 400 "$TRACKING_PLIST" 2>/dev/null
                chflags uchg "$TRACKING_PLIST" 2>/dev/null
                NOTICE "Recorded demotion of $user (total: $new_demotion_count)"
            fi
        fi
    fi
done

# Log Privileges events
log_recent_privileges_events

# Final permission lock-down
chmod 400 "$SCRIPT_LOG" 2>/dev/null

exit 0
EOSCPT

if [[ $? -ne 0 ]]; then
    LOG "[ ERROR ] Failed to create the script at $SCRIPT_PATH"
    exit 1
fi

LOG "Created hidden script at $SCRIPT_PATH"

# Make script executable
chmod 500 "${SCRIPT_PATH}"
chown root:wheel "${SCRIPT_PATH}"

### ====== Create Trigger File System ======

LOG "Setting up trigger file system..."

# Create trigger file
touch "$TRIGGER_FILE"
chmod 666 "$TRIGGER_FILE"
chown root:wheel "$TRIGGER_FILE"

if [[ ! -f "$TRIGGER_FILE" ]]; then
    LOG "[ ERROR ] Failed to create trigger file at $TRIGGER_FILE"
    exit 1
else
    LOG "Trigger file created at $TRIGGER_FILE"
fi

# Create wrapper script
cat <<'EOWRAP' > "$WRAPPER_PATH"
#!/bin/bash
# Trigger the demote script by touching a watched file
touch /Library/Management/.demoter/.trigger 2>/dev/null || true
exit 0
EOWRAP

chmod 755 "$WRAPPER_PATH"
chown root:wheel "$WRAPPER_PATH"

if [[ ! -f "$WRAPPER_PATH" ]]; then
    LOG "[ ERROR ] Failed to create wrapper script at $WRAPPER_PATH"
    exit 1
else
    LOG "Wrapper script created at $WRAPPER_PATH"
fi

# Create trigger-watcher LaunchDaemon
cat <<EOPLIST > "$TRIGGER_DAEMON_PATH"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.demote.privileges-trigger</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>$SCRIPT_PATH</string>
    </array>
    <key>WatchPaths</key>
    <array>
        <string>$TRIGGER_FILE</string>
    </array>
    <key>RunAtLoad</key>
    <false/>
    <key>StandardOutPath</key>
    <string>$LOG_PATH</string>
    <key>StandardErrorPath</key>
    <string>$LOG_PATH</string>
</dict>
</plist>
EOPLIST

chmod 644 "$TRIGGER_DAEMON_PATH"
chown root:wheel "$TRIGGER_DAEMON_PATH"

# Load trigger daemon
launchctl bootout system/com.demote.privileges-trigger 2>/dev/null
launchctl bootstrap system "$TRIGGER_DAEMON_PATH" 2>/dev/null || \
launchctl load "$TRIGGER_DAEMON_PATH"

LOG "Trigger system installed"

### ====== Utility Functions ======

get_allowed_admins_from_profile() {
    local admins=()
    if [[ -f "$PROFILE_PLIST" ]]; then
        admins=($(defaults read "$PROFILE_PLIST" AllowedAdmins 2>/dev/null | awk 'NR>1 && !/\)/ {gsub(/[" ,]/,""); if(length($1)>0) print $1}'))
    elif [[ -f "/Library/Managed Preferences/${CONSOLE_USER}/com.demote.adminallow.plist" ]]; then
        admins=($(defaults read "/Library/Managed Preferences/${CONSOLE_USER}/com.demote.adminallow.plist" AllowedAdmins 2>/dev/null | awk 'NR>1 && !/\)/ {gsub(/[" ,]/,""); if(length($1)>0) print $1}'))
    fi
    echo "${admins[@]}"
}

get_demoter_interval_from_profile() {
    if [[ -f "$PROFILE_PLIST" ]]; then
        out=$(defaults read "$PROFILE_PLIST" DemoterInterval 2>/dev/null)
    elif [[ -f "/Library/Managed Preferences/${CONSOLE_USER}/com.demote.adminallow.plist" ]]; then
        out=$(defaults read "/Library/Managed Preferences/${CONSOLE_USER}/com.demote.adminallow.plist" DemoterInterval 2>/dev/null)
    fi
    echo "$out"
}

### ====== Load Config/Defaults ======

profile_allowed_admins=($(get_allowed_admins_from_profile))
profile_demoter_interval=$(get_demoter_interval_from_profile)

if [[ -n "$profile_demoter_interval" ]]; then
    DEMOTER_INTERVAL="$profile_demoter_interval"
    LOG "Demoter interval set to $DEMOTER_INTERVAL seconds from config profile."
else
    DEMOTER_INTERVAL="$DEFAULT_DEMOTER_INTERVAL"
    LOG "No interval set in config profile, defaulting to 15 minutes."
fi

if [[ ${#profile_allowed_admins[@]} -gt 0 ]]; then
    ALLOWED_ADMINS=("${profile_allowed_admins[@]}")
else
    ALLOWED_ADMINS=("${DEFAULT_ALLOWED_ADMINS[@]}")
fi

### ====== LaunchDaemon plist (interval-based) ======

cat <<EOLD > "$DAEMON_PATH"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.demote.demoteadmins</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>$SCRIPT_PATH</string>
    </array>
    <key>StartInterval</key>
    <integer>${DEMOTER_INTERVAL}</integer>
    <key>WatchPaths</key>
    <array>
        <string>/var/db/dslocal/nodes/Default/users</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>StandardOutPath</key>
    <string>$LOG_PATH</string>
    <key>StandardErrorPath</key>
    <string>$LOG_PATH</string>
</dict>
</plist>
EOLD

chmod 644 "$DAEMON_PATH"
chown root:wheel "$DAEMON_PATH"

# Load daemon
LOG "Loading interval-based LaunchDaemon..."
launchctl bootout system/com.demote.demoteadmins 2>/dev/null
launchctl bootstrap system "$DAEMON_PATH" 2>/dev/null || \
launchctl load "$DAEMON_PATH"

LOG "Interval-based daemon loaded"

### ====== Permissioning ======

LOG "Setting permissions..."
chmod 666 "${TRIGGER_FILE}"

# Secure the directory
chown -R root:wheel "${DEMOTER_DIR}"
chmod -R go-rwx "${DEMOTER_DIR}"

# Re-apply specific permissions after recursive chmod
chmod 666 "${TRIGGER_FILE}"
chmod 700 "${DEMOTER_LOGS_DIR}"
chmod 500 "${SCRIPT_PATH}"

# Create version file
echo "$SCRIPT_VERSION" > "${DEMOTER_DIR}/.version"
chmod 400 "${DEMOTER_DIR}/.version"

### ====== Verification ======

LOG ""
LOG "=========================================="
LOG " Demoter installed successfully!"
LOG "=========================================="
LOG ""
LOG "Configuration:"
LOG "  Interval: $DEMOTER_INTERVAL seconds"
LOG "  Allowed Admins: ${ALLOWED_ADMINS[*]}"
LOG ""
LOG "File Locations:"
LOG "  Script:  $SCRIPT_PATH"
LOG "  Trigger: $TRIGGER_FILE"
LOG "  Wrapper: $WRAPPER_PATH"
LOG ""
LOG "Permissions:"
LOG "  Script:  $(ls -l ${SCRIPT_PATH} 2>/dev/null | awk '{print $1}')"
LOG "  Trigger: $(ls -l ${TRIGGER_FILE} 2>/dev/null | awk '{print $1}')"
LOG ""
LOG "LaunchDaemons:"
launchctl list | grep com.demote | while read line; do LOG "  $line"; done

### ====== Calculate and Store Security Hashes ======

LOG ""
LOG "=========================================="
LOG "Calculating and storing security hashes..."
LOG "=========================================="

SCRIPT_SHA=$(openssl sha256 "$SCRIPT_PATH" 2>/dev/null | awk '{print $2}')
WRAPPER_SHA=$(openssl sha256 "$WRAPPER_PATH" 2>/dev/null | awk '{print $2}')
DAEMON_SHA=$(openssl sha256 "$DAEMON_PATH" 2>/dev/null | awk '{print $2}')
TRIGGER_DAEMON_SHA=$(openssl sha256 "$TRIGGER_DAEMON_PATH" 2>/dev/null | awk '{print $2}')

[[ -z "$SCRIPT_SHA" ]]         && LOG "  WARNING: Failed to hash main script"
[[ -z "$WRAPPER_SHA" ]]        && LOG "  WARNING: Failed to hash wrapper script"
[[ -z "$DAEMON_SHA" ]]         && LOG "  WARNING: Failed to hash daemon plist"
[[ -z "$TRIGGER_DAEMON_SHA" ]] && LOG "  WARNING: Failed to hash trigger daemon plist"

LOG "  Script:         ${SCRIPT_SHA:0:16}..."
LOG "  Wrapper:        ${WRAPPER_SHA:0:16}..."
LOG "  Daemon:         ${DAEMON_SHA:0:16}..."
LOG "  Trigger daemon: ${TRIGGER_DAEMON_SHA:0:16}..."

### ====== Write Tracking Plist ======

LOG ""
LOG "Writing tracking data to $TRACKING_PLIST..."

mkdir -p "$TRACKING_DIR"
chmod 700 "$TRACKING_DIR"
chown root:wheel "$TRACKING_DIR"

if [[ -f "$TRACKING_PLIST" ]]; then
    chflags nouchg "$TRACKING_PLIST" 2>/dev/null
    chmod 600 "$TRACKING_PLIST" 2>/dev/null
fi

defaults write "$TRACKING_PLIST" "scriptHash"        "$SCRIPT_SHA"
defaults write "$TRACKING_PLIST" "wrapperHash"       "$WRAPPER_SHA"
defaults write "$TRACKING_PLIST" "daemonHash"        "$DAEMON_SHA"
defaults write "$TRACKING_PLIST" "triggerDaemonHash" "$TRIGGER_DAEMON_SHA"

# Preserve existing counters — do not reset on reinstall
defaults write "$TRACKING_PLIST" "tamperCount"         -int "$PRESERVED_TAMPER"
defaults write "$TRACKING_PLIST" "warningAcknowledged" -int "$PRESERVED_WARNING"
defaults write "$TRACKING_PLIST" "autoFixCount"        -int "$PRESERVED_AUTOFIX"
defaults write "$TRACKING_PLIST" "demotionCount"       -int "$PRESERVED_DEMOTION_COUNT"

defaults write "$TRACKING_PLIST" "lastDeployment" "$(date '+%Y-%m-%d %H:%M:%S')"
defaults write "$TRACKING_PLIST" "version"        "$SCRIPT_VERSION"

if [[ -n "$PRESERVED_VERSION" && "$PRESERVED_VERSION" != "unknown" ]]; then
    defaults write "$TRACKING_PLIST" "previousVersion" "$PRESERVED_VERSION"
fi

# Clear notification flag — consumed by this install run
defaults delete "$TRACKING_PLIST" "pendingUserNotification" 2>/dev/null

# Secure the plist — immutable, root-only, hidden
chmod 400 "$TRACKING_PLIST"
chown root:wheel "$TRACKING_PLIST" 2>/dev/null || LOG "  Note: chown redundant — file already root-owned"
chflags uchg "$TRACKING_PLIST"
chflags hidden "$TRACKING_PLIST"

LOG "  Tracking plist secured"
LOG "  Preserved — tamper: $PRESERVED_TAMPER  autofix: $PRESERVED_AUTOFIX  warnings: $PRESERVED_WARNING  demotions: $PRESERVED_DEMOTION_COUNT"

### ====== User Notification (Remediation Runs Only) ======

if [[ "$PRESERVED_NOTIFY_FLAG" == "1" ]]; then
    LOG ""
    LOG "=========================================="
    LOG "Sending security notification to user..."
    LOG "=========================================="

    NOTIFY_USER=$( scutil <<< "show State:/Users/ConsoleUser" | awk '/Name :/ && !/loginwindow/ { print $3 }' )
    NOTIFY_USER_UID=$(id -u "$NOTIFY_USER" 2>/dev/null)

    if [[ -n "$NOTIFY_USER" && "$NOTIFY_USER" != "loginwindow" && "$NOTIFY_USER" != "_mbsetupuser" ]]; then
        LOG "  User logged in: $NOTIFY_USER"

        TAMPER_COUNT="$PRESERVED_TAMPER"

        if launchctl asuser "$NOTIFY_USER_UID" osascript -e "
display dialog \"Security monitoring detected unauthorized modifications to system security tools on this Mac. The system has been automatically remediated.

Tampering with security tools is prohibited and may result in disciplinary action.

Tamper Event #${TAMPER_COUNT}\" \
with title \"Security Alert\" \
buttons {\"Acknowledge\"} \
default button \"Acknowledge\" \
with icon caution" 2>/dev/null; then
            LOG "  User acknowledged warning"

            chflags nouchg "$TRACKING_PLIST" 2>/dev/null
            chmod 600 "$TRACKING_PLIST" 2>/dev/null
            NEW_ACK=$(( $(defaults read "$TRACKING_PLIST" "warningAcknowledged" 2>/dev/null || echo "0") + 1 ))
            defaults write "$TRACKING_PLIST" "warningAcknowledged" -int "$NEW_ACK"
            defaults write "$TRACKING_PLIST" "lastAcknowledgement"  "$(date '+%Y-%m-%d %H:%M:%S')"
            chmod 400 "$TRACKING_PLIST"
            chflags uchg "$TRACKING_PLIST"
            chflags hidden "$TRACKING_PLIST"
            LOG "  Acknowledgment count: $NEW_ACK"
        else
            LOG "  Warning timed out or was dismissed without acknowledgment"
        fi
    else
        LOG "  No user logged in — skipping notification"
    fi
fi

LOG ""
LOG "Exiting"
exit 0