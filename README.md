# Mac Admin Demoter

An automated solution for removing unauthorized admin rights from local macOS users, with intelligent integration for [Privileges.app](https://github.com/SAP/macOS-enterprise-privileges).

---

## Features

- **Automatic Local Admin Demotion:**  
    Any user not on the allow-list is demoted from `admin` group.
- **Privileges.app Integration:**  
    Honors temporary admin elevation granted by Privileges.app (both v1 and v2), for the logged-in user, within their allowed window.
- **Flexible Config:**  
    Allow-list and interval are managed via a Jamf Custom Settings Configuration Profile at `/Library/Managed Preferences/com.demote.adminallow.plist`.
- **Jamf Ready:**  
    Deploy as a Jamf policy script (no package needed), works with Jamf Pro Custom Settings profiles.
- **Comprehensive Logging:**  
    All actions are logged to `/Library/Management/demoter/logs/demoteadmins.log`.

---

## How it Works

- The demotion script runs every 15 minutes (default) via a LaunchDaemon.
    - You can adjust the interval via configuration profile (`DemoterInterval`) or script default.
- For every local user (UID >= 501):
    - If user is in the allow-list, they keep admin.
    - If not, and the user is admin **and** is the logged-in user with active Privileges.app elevation: they keep admin for the allowed interval.
    - All others are demoted to standard.

---

## File Structure

| Path                                            | Purpose                       |
|-------------------------------------------------|-------------------------------|
| `/Library/Management/demoter/demote_unlisted_admins` | Main demotion script          |
| `/Library/LaunchDaemons/com.demote.demoteadmins.plist` | LaunchDaemon plist           |
| `/Library/Management/demoter/logs/demoteadmins.log`   | Logging output                |
| `/Library/Managed Preferences/com.demote.adminallow.plist` | Jamf admin allow-list config |

---

## Installation (Jamf Pro Deployment)

1. **Upload your deployment script** (as above) to Jamf as a "Script" policy, or run it once as root.
2. **Deploy a Configuration Profile:**
    - Go to Computers > Configuration Profiles in Jamf Pro.
    - Add a "Custom Settings" payload:
        - **Preference Domain:** `com.demote.adminallow`
        - **Example Property List:**
            ```xml
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0">
            <dict>
                <key>AllowedAdmins</key>
                <array>
                    <string>admin1</string>
                    <string>admin2</string>
                    <!-- Add more IT/admin accounts as needed -->
                </array>
                <!-- Optional: override daemon interval here -->
                <key>DemoterInterval</key>
                <integer>900</integer>
            </dict>
            </plist>
            ```

---

## Uninstall

To completely remove:

- Unload and remove `/Library/LaunchDaemons/com.demote.demoteadmins.plist`
- Delete `/Library/Management/demoter/demote_unlisted_admins`
- (Optionally) remove `/Library/Management/demoter/logs/demoteadmins.log`
- (Optionally) remove `/Library/Managed Preferences/com.demote.adminallow.plist`  
- Remove the configuration profile from your Jamf scope

---

## Requirements

- **macOS 10.15+** (tested through current versions)
- Privileges.app v1 or v2 in `/Applications` for temporary elevation
- Jamf Pro for configuration management and profile deployment

---
## Requirements

- **macOS 10.15 or later** (tested to Sonoma)
- [Privileges.app](https://github.com/SAP/macOS-enterprise-privileges) v1 or v2 in `/Applications`
- **The script will still work if an allowed list of admins is present, even if Privileges is not installed**

---

## Credits & References

- [SAP Privileges.app](https://github.com/SAP/macOS-enterprise-privileges)
---

## License

MIT

---

## Support

Open a GitHub issue for bugs/enhancements or submit a Pull Request.

---
