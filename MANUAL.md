# Comprehensive Operations & Administration Manual

**Disable-MacOS-Updates Suite — v1.2.0**  
*Enterprise-Grade, Fully Reversible macOS Automatic Update Control*

---

## 🧭 Table of Contents

- [1. Executive Summary & Purpose](#1-executive-summary--purpose)
- [2. System Requirements & Compatibility](#2-system-requirements--compatibility)
- [3. Operational Procedures](#3-operational-procedures)
  - [3.1 Disabling macOS Automatic Updates](#31-disabling-macos-automatic-updates)
  - [3.2 Restoring macOS Automatic Updates](#32-restoring-macos-automatic-updates)
  - [3.3 Verifying System State](#33-verifying-system-state)
- [4. In-Depth Technical Mechanics](#4-in-depth-technical-mechanics)
  - [4.1 Defaults Preference Domains & Keys](#41-defaults-preference-domains--keys)
  - [4.2 Apple Update CDN Sinkholing](#42-apple-update-cdn-sinkholing)
  - [4.3 Background Launch Daemons](#43-background-launch-daemons)
  - [4.4 DNS Cache & Update Cache Purging](#44-dns-cache--update-cache-purging)
- [5. Backup & Recovery Architecture](#5-backup--recovery-architecture)
  - [5.1 Storage Locations & Permissions](#51-storage-locations--permissions)
  - [5.2 Manual Emergency Recovery](#52-manual-emergency-recovery)
- [6. Enterprise & Fleet Deployment](#6-enterprise--fleet-deployment)
  - [6.1 Jamf Pro Deployment](#61-jamf-pro-deployment)
  - [6.2 Munki Integration](#62-munki-integration)
  - [6.3 Ansible Playbook](#63-ansible-playbook)
- [7. Troubleshooting & Diagnostics](#7-troubleshooting--diagnostics)
- [8. Frequently Asked Questions (FAQ)](#8-frequently-asked-questions-faq)

---

## 1. Executive Summary & Purpose

In mission-critical, enterprise, audio production (DAW), video editing, or staging environments, unexpected operating system updates can cause severe operational disruptions:
- Unscheduled system restarts during live broadcasts, rendering tasks, or database operations.
- Breaking kernel extensions, audio plugin drivers (AU/VST), or proprietary hardware interfaces.
- Unwanted major version upgrades (e.g., automated progression from macOS Sonoma to Sequoia/Tahoe).

**Disable-MacOS-Updates** provides a surgical, deterministic, and fully reversible dual-script solution:
1. **`disable_macos_updates.sh`**: Disables all background software update discovery, downloads, installation flags, unloads background update daemons, sinkholes Apple update CDN servers in `/etc/hosts`, and purges download caches.
2. **`restore_macos_updates.sh`**: Symmetrically restores all macOS default update flags, reloads background daemons, cleanses `/etc/hosts` of sinkhole records, flushes DNS caches, and re-triggers an update check.

---

## 2. System Requirements & Compatibility

| Specification        | Requirement / Verified Scope                                                                 |
|:---------------------|:---------------------------------------------------------------------------------------------|
| **Operating System** | macOS 12 (Monterey), macOS 13 (Ventura), macOS 14 (Sonoma), macOS 15 (Sequoia), macOS 16 (Tahoe) |
| **Architecture**     | Apple Silicon (M1, M2, M3, M4 series) and Intel x86_64                                      |
| **Shell Engine**     | Native macOS `/bin/bash` (v3.2.57+) or modern Bash 4+/5+                                      |
| **Privileges**       | Superuser / root execution (`sudo`)                                                           |
| **Dependencies**     | 100% native macOS utilities (`defaults`, `launchctl`, `dscacheutil`, `mDNSResponder`, `awk`)  |

---

## 3. Operational Procedures

### 3.1 Disabling macOS Automatic Updates

To completely halt macOS update discovery, background downloads, and automated installs:

```bash
# 1. Navigate to the script location
cd /path/to/Disable-MacOS-Updates

# 2. Make executable (if needed)
chmod +x disable_macos_updates.sh restore_macos_updates.sh

# 3. Execute with root privileges
sudo ./disable_macos_updates.sh
```

#### What Happens During Execution:
1. **Preflight Validation**: Verifies root UID (`EUID == 0`), macOS Darwin kernel, and command dependencies.
2. **Baseline Backup**: Records initial `com.apple.SoftwareUpdate` values to `/var/db/disable_macos_updates_prefs.bak` and a pristine copy of `/etc/hosts` to `/var/db/disable_macos_updates_hosts.bak`.
3. **Defaults Enforcement**: Disables check, download, install, critical updates, and App Store auto-updates.
4. **Daemon Unloading**: Unloads `com.apple.softwareupdated` and related daemons via modern `launchctl bootout`.
5. **Cache Purging**: Cleans out `/Library/Updates/` staging directory.
6. **CDN Sinkholing**: Atomically appends tagged loopback records (`127.0.0.1`) for Apple update domains to `/etc/hosts`.
7. **DNS Flush**: Flushes local resolver caches via `dscacheutil` and `killall -HUP mDNSResponder`.

---

### 3.2 Restoring macOS Automatic Updates

To revert all settings back to factory defaults and allow standard updates:

```bash
sudo ./restore_macos_updates.sh
```

#### What Happens During Execution:
1. **Defaults Re-enabling**: Sets all update flags back to `-bool true`.
2. **Surgical Hosts Cleaning**: Strips all lines matching `# disable_macos_updates:managed` from `/etc/hosts` via atomic temporary file replacement.
3. **Daemon Reloading**: Bootstraps and kickstarts `com.apple.softwareupdated` and related daemons.
4. **DNS Cache Flush**: Re-enables clean resolution of Apple update CDN domains.
5. **Update Check**: Triggers `softwareupdate --list` to populate available updates immediately.

---

### 3.3 Verifying System State

You can inspect the current status at any time:

```bash
# Check SoftwareUpdate preferences
defaults read /Library/Preferences/com.apple.SoftwareUpdate

# Check App Store commerce preferences
defaults read /Library/Preferences/com.apple.commerce AutoUpdate

# Check /etc/hosts sinkhole entries
grep -i "disable_macos_updates" /etc/hosts

# Verify DNS resolution of update CDN
dscacheutil -q host -a name swscan.apple.com
# Output when disabled: 127.0.0.1
# Output when restored: Official Apple Akamai / Cloudflare CDN IPs
```

---

## 4. In-Depth Technical Mechanics

### 4.1 Defaults Preference Domains & Keys

The scripts manipulate system-level preference plists located in `/Library/Preferences/`:

| Domain / Plist                     | Key Name                                | Disabled Value | Restored Value | Description                                   |
|:-----------------------------------|:----------------------------------------|:---------------|:---------------|:----------------------------------------------|
| `com.apple.SoftwareUpdate`         | `AutomaticCheckEnabled`                 | `false`        | `true`         | Checks for new updates in the background      |
| `com.apple.SoftwareUpdate`         | `AutomaticDownload`                     | `false`        | `true`         | Downloads update packages automatically       |
| `com.apple.SoftwareUpdate`         | `AutomaticallyInstallMacOSUpdates`      | `false`        | `true`         | Triggers installation of major/minor updates  |
| `com.apple.SoftwareUpdate`         | `ConfigDataInstall`                     | `false`        | `true`         | Installs background system configuration data |
| `com.apple.SoftwareUpdate`         | `CriticalUpdateInstall`                 | `false`        | `true`         | Installs Rapid Security Responses (RSR)       |
| `com.apple.commerce`               | `AutoUpdate`                            | `false`        | `true`         | Controls App Store application auto-updates   |

---

### 4.2 Apple Update CDN Sinkholing

Even when preference flags are disabled, certain macOS helper processes may attempt to contact Apple catalog servers. The suite enforces defense-in-depth by pointing these domains to localhost (`127.0.0.1`):

- `swscan.apple.com`: Software Update Catalog index and manifest service.
- `swdownload.apple.com`: Package download CDN.
- `swcdn.apple.com`: Asset and delta update distribution server.
- `updates-http.cdn-apple.com`: HTTP/HTTPS content delivery endpoint.

---

### 4.3 Background Launch Daemons

The suite addresses the following macOS system services:
- `com.apple.softwareupdated`: Primary system update coordination daemon.
- `com.apple.mobile.softwareupdated`: Mobile device and accessory update daemon.
- `com.apple.InstallAssistantService`: Installer coordination helper.
- `com.apple.storedownloadd`: App Store and system asset downloader.
- `com.apple.storekitagentd`: StoreKit transaction helper.
- `com.apple.commerce`: Mac App Store commerce daemon.

---

### 4.4 DNS Cache & Update Cache Purging

Whenever `/etc/hosts` is modified, the local DNS cache must be flushed to take effect immediately:
```bash
dscacheutil -flushcache
killall -HUP mDNSResponder
```
In addition, `disable_macos_updates.sh` removes partially downloaded staging packages:
```bash
rm -rf /Library/Updates/*
```

---

## 5. Backup & Recovery Architecture

### 5.1 Storage Locations & Permissions

All backups are stored in `/var/db/`, which is root-owned, persistent across reboots, and protected by macOS System Integrity Protection (SIP):

- `/var/db/disable_macos_updates_hosts.bak`: Pristine `/etc/hosts` captured before any sinkhole injection.
- `/var/db/disable_macos_updates_hosts.bak.YYYYMMDD`: Daily timestamped backups for audit history.
- `/var/db/disable_macos_updates_prefs.bak`: Original `defaults` values before disabling.

All backup files are strictly permissioned to `0600 root:wheel` to prevent unauthorized inspection.

### 5.2 Manual Emergency Recovery

If you ever need to manually restore the system without the scripts:

```bash
# 1. Restore pristine /etc/hosts
if [ -f /var/db/disable_macos_updates_hosts.bak ]; then
    sudo cp -p /var/db/disable_macos_updates_hosts.bak /etc/hosts
fi

# 2. Reset defaults to true
sudo defaults write /Library/Preferences/com.apple.SoftwareUpdate AutomaticCheckEnabled -bool true
sudo defaults write /Library/Preferences/com.apple.SoftwareUpdate AutomaticDownload -bool true
sudo defaults write /Library/Preferences/com.apple.SoftwareUpdate AutomaticallyInstallMacOSUpdates -bool true
sudo defaults write /Library/Preferences/com.apple.SoftwareUpdate ConfigDataInstall -bool true
sudo defaults write /Library/Preferences/com.apple.SoftwareUpdate CriticalUpdateInstall -bool true
sudo defaults write /Library/Preferences/com.apple.commerce AutoUpdate -bool true

# 3. Flush DNS
sudo dscacheutil -flushcache
sudo killall -HUP mDNSResponder
```

---

## 6. Enterprise & Fleet Deployment

### 6.1 Jamf Pro Deployment
1. Navigate to **Computers > Management Settings > Scripts** in Jamf Pro.
2. Create a new script named `Disable-MacOS-Updates`.
3. Paste the contents of `disable_macos_updates.sh`.
4. Create a Policy targeting your production/staging Smart Computer Group with an **Execution Frequency** of *Once per computer* or *Ongoing (Daily Check-in)*.

### 6.2 Munki Integration
For Munki-managed fleets, utilize `nopkg` manifests with `installcheck_script`:

```bash
#!/bin/bash
# installcheck_script for Munki
if grep -q "# disable_macos_updates:managed" /etc/hosts && \
   [ "$(defaults read /Library/Preferences/com.apple.SoftwareUpdate AutomaticCheckEnabled 2>/dev/null)" = "0" ]; then
    exit 1  # Already disabled, no installation required
fi
exit 0      # Needs to run
```

### 6.3 Ansible Playbook

```yaml
---
- name: Enforce macOS Update Freeze
  hosts: macos_workstations
  become: true
  tasks:
    - name: Copy disable script
      ansible.builtin.copy:
        src: disable_macos_updates.sh
        dest: /usr/local/bin/disable_macos_updates.sh
        mode: '0750'
        owner: root
        group: wheel

    - name: Execute disable updates
      ansible.builtin.command:
        cmd: /usr/local/bin/disable_macos_updates.sh
      register: disable_result
      changed_when: "'Adding Apple update CDN domains' in disable_result.stdout"
```

---

## 7. Troubleshooting & Diagnostics

### Problem: "Must be run as root. Use: sudo ..."
- **Cause**: Script was executed without `sudo`.
- **Solution**: Execute with `sudo ./disable_macos_updates.sh`.

### Problem: "Could not bootout: com.apple.softwareupdated"
- **Cause**: On macOS Sonoma and Sequoia, certain system daemons are protected by SIP and cannot be fully unloaded via `launchctl bootout`.
- **Mitigation**: This is expected behavior on recent macOS releases. The script logs a warning and proceeds. The `/etc/hosts` CDN sinkhole and `defaults` flags successfully prevent updates regardless.

### Problem: `softwareupdate --list` still shows cached updates
- **Cause**: macOS SoftwareUpdate daemon caches previously discovered catalog data locally.
- **Solution**: Run `sudo rm -rf /Library/Updates/*` and reboot the system once to clear memory caches.

---

## 8. Frequently Asked Questions (FAQ)

#### Q: Will this break the Mac App Store?
A: Regular app downloads from the Mac App Store remain functional. However, automatic background app updates are paused. Manual updates via the App Store interface continue to operate normally.

#### Q: Is this safe to run on Apple Silicon Macs?
A: Yes. Fully verified on Apple Silicon (M1/M2/M3/M4) as well as Intel-based Macs.

#### Q: Does this survive macOS reboots?
A: Yes. All modifications in `/Library/Preferences/` and `/etc/hosts` are persistent across system restarts.

#### Q: How do I update my Mac after freezing it?
A: Run `sudo ./restore_macos_updates.sh`, complete your desired update, and re-run `sudo ./disable_macos_updates.sh` when finished.
