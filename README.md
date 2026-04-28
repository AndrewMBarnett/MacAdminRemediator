# MacAdminRemediator - Automated Admin Rights Management for macOS

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![macOS](https://img.shields.io/badge/macOS-11.0+-blue.svg)](https://www.apple.com/macos)

A comprehensive solution for automatically demoting unauthorized admin users on macOS while maintaining compatibility with SAP Privileges.app, complete with tamper detection and automatic remediation.

## Features

- **Automatic Admin Demotion**: Removes admin rights from users not on an allow-list
- **Privileges.app Integration**: Respects temporary admin rights granted via SAP Privileges
- **Self-Healing**: Automatically detects and corrects permission tampering
- **Tamper Detection**: SHA-256 hash verification with automatic remediation
- **Audit Trail**: Comprehensive logging and tracking of security events
- **Jamf Pro Integration**: Full MDM support with Extension Attributes and Smart Groups
- **Configuration Profiles**: Managed via MDM configuration profiles
- **Hidden Operation**: Script and files are hidden from casual view

## Table of Contents

- [Architecture](#architecture)
- [Requirements](#requirements)
- [Installation](#installation)
  - [Quick Start](#quick-start)
  - [Configuration Profile](#configuration-profile)
  - [Jamf Pro Setup](#jamf-pro-setup)
- [Security & Integrity](#security--integrity)
  - [Hash Verification System](#hash-verification-system)
  - [Automatic Remediation](#automatic-remediation)
- [Components](#components)
- [Extension Attributes](#extension-attributes)
- [Smart Groups](#smart-groups)
- [Monitoring & Maintenance](#monitoring--maintenance)
- [Troubleshooting](#troubleshooting)
- [Security Considerations](#security-considerations)
- [License](#license)

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Configuration Profile                     │
│              (AllowedAdmins, DemoterInterval)               │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────────┐
│                  Interval-Based Check                        │
│            (LaunchDaemon - Every 15 minutes)                │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────────┐
│                 Privileges.app Trigger                       │
│         (Instant response via WatchPaths trigger)           │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────────┐
│                   DemoteAdmin Script                         │
│  • Checks allow-list                                        │
│  • Validates Privileges.app status                          │
│  • Demotes unauthorized admins                              │
│  • Self-heals permissions                                   │
│  • Logs all actions                                         │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────────┐
│                 SHA-256 Hash Verification                    │
│         (Daily integrity check + auto-remediation)          │
└─────────────────────────────────────────────────────────────┘
```

## Requirements

- macOS 11.0 (Big Sur) or later
- Jamf Pro (for full MDM integration)
- Root/admin access for installation
- (Optional) SAP Privileges.app for temporary admin elevation

## Installation

### Quick Start

1. **Clone or download this repository**
```bash
git clone https://github.com/AndrewMBarnett/MacAdminRemediator.git
cd MacAdminRemediator
```

2. **Run the installer as root**
```bash
sudo bash Scripts/DemoteAdminInstall.sh
```

3. **Deploy the configuration profile** (see below)

### Configuration Profile

Create a configuration profile in Jamf Pro with the following settings:

**Profile Name:** `DemoteAdmin Configuration`

**Payload Type:** `Custom Settings`

**Preference Domain:** `com.demote.adminallow`

**Settings:**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>AllowedAdmins</key>
    <array>
        <string>admin</string>
        <string>admin2</string>
    </array>
    <key>DemoterInterval</key>
    <integer>900</integer>
</dict>
</plist>
```

**Key Descriptions:**
- `AllowedAdmins` (Array): Usernames that are permitted to have admin rights
- `DemoterInterval` (Integer): Check interval in seconds (default: 900 = 15 minutes)

### Jamf Pro Setup

#### 1. Upload Scripts

Upload these scripts to Jamf Pro **Settings → Computer Management → Scripts**:

| Script Name | File | Purpose |
|------------|------|---------|
| Install DemoteAdmin | `DemoteAdminInstall.sh` | Installs the demotion engine, LaunchDaemons, trigger system, and stores SHA-256 hashes for tamper detection |

#### 2. Create Policies

**Policy 1: Initial Deployment**
- **Name:** Install DemoteAdmin
- **Trigger:** Custom event `deployDemoter` OR Self Service
- **Frequency:** Ongoing
- **Scope:** Target computers
- **Script:** `DemoteAdminInstall.sh`

**Policy 2: Remediation (Called automatically on tamper detection)**
- **Name:** DemoteAdmin - Remediation
- **Trigger:** Custom event `redeployDemoter`
- **Frequency:** Ongoing
- **Scope:** All computers
- **Script:** `DemoteAdminInstall.sh`

## Security & Integrity

### Hash Verification System

DemoteAdmin uses SHA-256 cryptographic hashes to detect file tampering:

#### Hash Storage (`DemoteAdminSecurityInstall.sh`)

```bash
# Calculates and stores hashes during deployment
SCRIPT_SHA=$(openssl sha256 "$SCRIPT_PATH" | awk '{print $2}')
defaults write "$TRACKING_PLIST" "scriptHash" "$SCRIPT_SHA"
```

**Tracked Files:**
- Main demotion script
- Wrapper trigger script
- LaunchDaemon plists (interval-based and trigger-based)

**Storage Location:** `/var/db/.systemconfig/.tracking.plist`

#### Self-Healing Verification (built into the demotion script)

At every run, the demotion script checks its own permissions and the permissions of all managed files. If a critical violation is detected:

```bash
# Tampering detected - trigger remediation via Jamf
jamf policy -event redeployDemoter
```

### Automatic Remediation

When tampering is detected:

1. **Log Event** - Record details to tamper log
2. **Increment Counter** - Track tampering frequency
3. **Redeploy** - Trigger Jamf policy `redeployDemoter` to reinstall clean files
4. **Update Tracking** - Record remediation action

**Tamper Event Log:** `/Library/Management/.demoter/.tamper-events`

**Tracking Data (stored in `/var/db/.systemconfig/.tracking.plist`):**
- `tamperCount` - Total tampering events detected
- `warningAcknowledged` - User acknowledgments of security warnings
- `autoFixCount` - Automatic remediation attempts
- `lastTamperDetected` - Timestamp of most recent tampering

## Components

### File Structure

```
/Library/Management/.demoter/                    # Hidden base directory (700)
├── .demote-unlisted-admins.sh                   # Main demotion script (500)
├── .trigger                                     # Trigger file for Privileges (666)
├── .tamper-events                               # Persistent tamper log (400)
├── .version                                     # Installed version number (400)
└── logs/
    ├── demoteadmins.log                         # Main log (400 when locked)
    └── log-archive/                             # Rotated logs (700)
        └── demoteadmins_<timestamp>.zip

/var/db/.systemconfig/
└── .tracking.plist                              # SHA-256 hashes + counters (immutable)

/Library/LaunchDaemons/
├── com.demote.demoteadmins.plist                # Interval-based daemon (644)
└── com.demote.privileges-trigger.plist          # Trigger-based daemon (644)

/usr/local/bin/
└── .privileges-demote-trigger                   # Hidden wrapper script (755)

/Library/Managed Preferences/
└── com.demote.adminallow.plist                  # Configuration profile
```

### LaunchDaemons

**Interval-Based Daemon:**
- **Label:** `com.demote.demoteadmins`
- **Function:** Runs demotion check every 15 minutes (configurable)
- **Trigger:** `StartInterval`

**Trigger-Based Daemon:**
- **Label:** `com.demote.privileges-trigger`
- **Function:** Instant response when Privileges.app grants/revokes admin
- **Trigger:** `WatchPaths` on trigger file

### Permission Model

| File/Directory | Permissions | Owner | Purpose |
|---------------|-------------|-------|---------|
| Base directory | `700` (drwx------) | root:wheel | Hidden, root-only access |
| Main script | `500` (-r-x------) | root:wheel | Read+execute only (no write) |
| Trigger file | `666` (-rw-rw-rw-) | root:wheel | World-writable for user triggers |
| Wrapper | `755` (-rwxr-xr-x) | root:wheel | Executable by all |
| Logs | `400` (-r--------) | root:wheel | Read-only (tamper-proof) |
| LaunchDaemons | `644` (-rw-r--r--) | root:wheel | Standard daemon permissions |

## Extension Attributes

Create these Extension Attributes in Jamf Pro for monitoring:

### EA 1: Version
**Name:** `DemoteAdmin - Version`
```bash
#!/bin/bash
VERSION_FILE="/Library/Management/.demoter/.version"
if [[ -f "$VERSION_FILE" ]]; then
    echo "<result>$(cat $VERSION_FILE 2>/dev/null || echo "Unknown")</result>"
else
    echo "<result>Not Installed</result>"
fi
```

### EA 2: Tamper Count
**Name:** `DemoteAdmin - Tamper Count`
```bash
#!/bin/bash
TRACKING_PLIST="/var/db/.systemconfig/.tracking.plist"
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
```

### EA 3: Warnings Acknowledged
**Name:** `DemoteAdmin - Warnings Acknowledged`  
**File:** `DemoterWarningsAcknowledged.sh`
```bash
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
```

### EA 4: Risk Level
**Name:** `DemoteAdmin - Risk Level`  
**File:** `DemoterRiskLevel.sh`
```bash
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
```

### EA 5: Permissions Status
**Name:** `DemoteAdmin - Permissions Status`
```bash
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
```

## Smart Groups

Create these Smart Groups for automated management:

### Smart Group 1: Repeat Offenders
```
Criteria:
  DemoteAdmin - Tamper Count | greater than or equal | 3
```

### Smart Group 2: High Risk Systems
```
Criteria:
  DemoteAdmin - Risk Level | like | High Risk
```

### Smart Group 3: Permission Issues
```
Criteria:
  DemoteAdmin - Permissions Status | is not | OK
AND
  DemoteAdmin - Permissions Status | is not | Not Installed
```

### Smart Group 4: Needs Deployment
```
Criteria:
  DemoteAdmin - Version | is | Not Installed
AND
  Operating System | like | macOS
```

## Monitoring & Maintenance

### Log Locations

**Main Log:**
```bash
/Library/Management/.demoter/logs/demoteadmins.log
```

**View recent entries:**
```bash
sudo tail -f /Library/Management/.demoter/logs/demoteadmins.log
```

**Tamper Events:**
```bash
sudo cat /Library/Management/.demoter/.tamper-events
```

### Log Rotation

Logs are automatically rotated when they exceed 500KB:
- Compressed to ZIP format
- Moved to archive directory
- Original log cleared
- Rotation logged in new log file

### Manual Commands

**Check LaunchDaemon status:**
```bash
sudo launchctl list | grep com.demote
```

**Manually trigger demotion:**
```bash
sudo /Library/Management/.demoter/.demote-unlisted-admins.sh
```

**Trigger via Privileges wrapper:**
```bash
touch /Library/Management/.demoter/.trigger
```

**View tracking data:**
```bash
sudo chflags nouchg /var/db/.systemconfig/.tracking.plist
sudo defaults read /var/db/.systemconfig/.tracking.plist
sudo chflags uchg /var/db/.systemconfig/.tracking.plist
```

**Manual remediation:**
```bash
sudo bash Scripts/DemoteAdminInstall.sh
```

## Troubleshooting

### Issue: Script not running automatically

**Check LaunchDaemon status:**
```bash
sudo launchctl print system/com.demote.demoteadmins
sudo launchctl print system/com.demote.privileges-trigger
```

**Reload daemons:**
```bash
sudo launchctl bootout system/com.demote.demoteadmins
sudo launchctl bootstrap system /Library/LaunchDaemons/com.demote.demoteadmins.plist
```

### Issue: Configuration profile not found

**Verify profile installation:**
```bash
sudo profiles list | grep com.demote
sudo defaults read /Library/Managed\ Preferences/com.demote.adminallow.plist
```

### Issue: Privileges integration not working

**Check trigger file permissions:**
```bash
ls -la /Library/Management/.demoter/.trigger
# Should show: -rw-rw-rw-
```

**Verify wrapper exists:**
```bash
ls -la /usr/local/bin/.privileges-demote-trigger
```

**Test trigger manually:**
```bash
touch /Library/Management/.demoter/.trigger
sleep 3
tail /Library/Management/.demoter/logs/demoteadmins.log
```

### Issue: Tampering detected but auto-fix failing

**Check Jamf policy trigger:**
```bash
sudo jamf policy -event redeployDemoter -verbose
```

**Verify tracking plist:**
```bash
sudo chflags nouchg /var/db/.systemconfig/.tracking.plist
sudo defaults read /var/db/.systemconfig/.tracking.plist
sudo chflags uchg /var/db/.systemconfig/.tracking.plist
```

## Security Considerations

### Hidden Files
All critical components use hidden file naming (prefix with `.`) to prevent casual discovery:
- Base directory: `.demoter`
- Main script: `.demote-unlisted-admins.sh`
- Trigger file: `.trigger`
- Wrapper: `.privileges-demote-trigger`

### Permission Hardening
- Script is read-execute only (`500`) — cannot be modified without `chmod` first
- Logs are locked read-only (`400`) after writing — prevents tampering
- Base directory is `700` — only root can access
- Tracking plist is immutable (`chflags uchg`) — requires flag removal before any write

### Self-Healing
Script automatically detects and corrects at every run:
- Incorrect file permissions
- Missing trigger file
- Ownership changes
- Directory permission modifications

Minor issues (trigger file) are auto-corrected. Critical issues (script or directory permissions) trigger a full reinstall via `redeployDemoter`.

### Tamper Detection
- SHA-256 cryptographic hashing of all managed files
- Automatic remediation on detection
- Persistent event logging
- Tamper and auto-fix counters preserved across reinstalls

### Audit Trail
Every action is logged with:
- Timestamp
- Script version
- User context
- Action taken
- Result status

## Does This Require Privileges.app?

**No.** Privileges.app is optional.

- If Privileges.app **is installed**, the script honors active temporary admin elevation for the logged-in user within their allowed time window.
- If Privileges.app **is not installed**, the script fully enforces the allow-list: only users in `AllowedAdmins` retain admin rights.

## License

MIT License — See [LICENSE](LICENSE) file for details
