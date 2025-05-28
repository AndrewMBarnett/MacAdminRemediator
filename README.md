# Mac Admin Demoter

An automated solution for removing unauthorized admin rights from local macOS users, with intelligent integration for [Privileges.app](https://github.com/SAP/macOS-enterprise-privileges).

---

## Features

- **Automatically demotes all non-allowed Mac admin users**
- **Allows temporary admin via Privileges.app** (honored for duration window)
- **Reads admin allow-list and rotation interval from a Jamf Configuration Profile**
- **Log file rotation and zipped archive when log size > 500 KB**
- **Logs are securely permissioned (root only) and archived**
- **Deploys to `/Library/Management/demoter` for security and auditability**

---

## Deployment (Jamf Pro)

1. **Upload the full deploy script** to Jamf (e.g. as a policy script, or build a package for first-run).
2. The script:
   - Installs the demoter enforcement script: `/Library/Management/demoter/demote-unlisted-admins`
   - Deploys a LaunchDaemon: `/Library/LaunchDaemons/com.demote.demoteadmins.plist`  
     configured for your desired interval (default: every 900s = 15 min)
   - **The script will set a default (currently 15 mins), if it can't find the Configuration Profile for the interval setting**
   - Sets correct permissions (`root:wheel`, 700/600)
   - Ensures log files are rotated and zipped as `/Library/Management/demoter/logs/archive/`
3. **Create a Jamf Configuration Profile (Custom Settings):**
   - Preference Domain: `com.demote.adminallow`
   - Example property list:
     ```xml
     <plist version="1.0">
     <dict>
       <key>AllowedAdmins</key>
       <array>
         <string>admin2</string>
         <string>admin2</string>
       </array>
       <key>DemoterInterval</key>
       <integer>900</integer>
     </dict>
     </plist>
     ```
   - Only accounts in `AllowedAdmins` stay admin; all others are demoted unless using Privileges.app

---

## How Log Management Works

- **Log file:**  
  `/Library/Management/demoter/logs/demoteadmins.log`
- **When log file reaches 500 KB:**  
  - It is zipped and archived in `/Library/Management/demoter/logs/log-archive/demoteadmins_<timestamp>.zip`
  - A new log is started; all permissions restrict logs to root.
- **Permissions:**  
  - Only root can access log/script/archive: directory/files are set to 700/600 and root:wheel.
- **Archived logs** (zipped):  
  - Only root can read/extract contents.

---

## Security & Best Practice

- All script, logs, and archive directories are strictly root-owned/700 or 600 (no user can browse or view).
- Script and daemon are non-editable and non-readable by users.
- LaunchDaemon runs at root every interval (by config profile).

---

## Configuration Profile Reference

| Key             | Type     | Example Value                       | Description                           |
|-----------------|----------|-------------------------------------|---------------------------------------|
| AllowedAdmins   | array    | `admin2`, `admin2`                  | Allowed admin accounts                |
| DemoterInterval | integer  | `900`                               | Run interval (in seconds)             |

---

## How the Enforcement Works

- **At every interval:**
  - All local users are checked for admin status.
  - Any user in `AllowedAdmins` (from config) is skipped.
  - The currently logged-in GUI user is allowed admin for the Privileges.app elevation window.
  - All other admins are demoted to standard users.
- All activity and actions are logged & archived securely.

---

## Uninstallation

- LaunchDaemon can be unloaded and removed.
- All demoter files/logs/archives can be deleted by root.
- Remove the config profile from Jamf scope.

---

## License

MIT
