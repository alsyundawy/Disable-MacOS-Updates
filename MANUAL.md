# Operations & Administration Manual

**Disable-MacOS-Updates Suite — v1.2.0**<br>
_Operations Manual for macOS Automatic Software Update Control_

---

## 🧭 Table of Contents

- [1. Summary & Purpose](#1-summary--purpose)
- [2. System Requirements & Compatibility](#2-system-requirements--compatibility)
- [3. Operational Procedures](#3-operational-procedures)
  - [3.1 Pre-Flight Health Checklist](#31-pre-flight-health-checklist)
  - [3.2 Disabling macOS Automatic Updates](#32-disabling-macos-automatic-updates)
  - [3.3 Restoring macOS Automatic Updates](#33-restoring-macos-automatic-updates)
  - [3.4 Post-Flight Verification Runbook](#34-post-flight-verification-runbook)
- [4. Technical Mechanics](#4-technical-mechanics)
  - [4.1 Defaults Preference Domains & Keys](#41-defaults-preference-domains--keys)
  - [4.2 Apple Update CDN Sinkholing](#42-apple-update-cdn-sinkholing)
  - [4.3 Blocking Methods Comparison](#43-blocking-methods-comparison)
  - [4.4 Background Launch Daemons Topology](#44-background-launch-daemons-topology)
  - [4.5 Cache Invalidation & Storage Footprint](#45-cache-invalidation--storage-footprint)
- [5. Backup, Integrity & Recovery](#5-backup-integrity--recovery)
  - [5.1 Storage Locations & Permissions](#51-storage-locations--permissions)
  - [5.2 Manual Emergency Recovery Runbook](#52-manual-emergency-recovery-runbook)
- [6. Automation & Fleet Deployment Guides](#6-automation--fleet-deployment-guides)
  - [6.1 Jamf Pro Deployment & Extension Attribute](#61-jamf-pro-deployment--extension-attribute)
  - [6.2 Munki Integration (nopkg Manifest)](#62-munki-integration-nopkg-manifest)
  - [6.3 Kandji & Mosyle Custom Scripts](#63-kandji--mosyle-custom-scripts)
  - [6.4 Ansible Playbook with Handlers](#64-ansible-playbook-with-handlers)
- [7. Troubleshooting & Diagnostics](#7-troubleshooting--diagnostics)
- [8. Frequently Asked Questions (FAQ)](#8-frequently-asked-questions-faq)

---

## 1. Summary & Purpose

In audio production (DAW), video editing, or staging environments, unexpected operating system updates can disrupt workflows:

- **Audio Production (DAW)**: Unprompted updates can break CoreAudio driver extensions, PACE iLok authorizations, and AU/VST/AAX audio plugins across Logic Pro, Pro Tools, Ableton Live, and Cubase.
- **Video Rendering & Broadcast**: Overnight reboots abort long render queues in Final Cut Pro, DaVinci Resolve, or Adobe Premiere.
- **Fleet & Staging**: Uncontrolled progression to new major macOS versions can break internal VPN clients, security agents, and corporate device profiles.

**Disable-MacOS-Updates** provides a practical, reversible two-script solution:

1. **`disable_macos_updates.sh`**: Disables background software update discovery, downloads, installation flags, unloads background update daemons, sinkholes Apple update CDN servers in `/etc/hosts`, and purges download caches.
2. **`restore_macos_updates.sh`**: Restores all macOS default update flags, reloads background daemons, cleanses `/etc/hosts` of sinkhole records, flushes DNS caches, and re-triggers an update check.

---

## 2. System Requirements & Compatibility

| Specification             | Requirement / Verified Scope                                                                                                                                                         |
| :------------------------ | :----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Operating System**      | macOS 12 Monterey (12.0–12.7.x), macOS 13 Ventura (13.0–13.7.x), macOS 14 Sonoma (14.0–14.7.x), macOS 15 Sequoia (15.0–15.7.x), macOS 26 Tahoe (26.0+), macOS 27 Golden Gate (27.0+) |
| **Apple Silicon Support** | M1, M2, M3, M4, M5, M6 across Base, Pro, Max, and Ultra tiers                                                                                                                        |
| **Intel x86_64 Support**  | Supported through macOS 26 Tahoe (dropped in macOS 27 Golden Gate)                                                                                                                   |
| **Shell Engine**          | Native macOS `/bin/bash` (v3.2.57+) or modern Bash 4+/5+                                                                                                                             |
| **Privileges**            | Superuser / root execution (`sudo`)                                                                                                                                                  |
| **Dependencies**          | Native macOS utilities (`defaults`, `launchctl`, `dscacheutil`, `mDNSResponder`, `awk`, `mktemp`)                                                                                    |

---

## 3. Operational Procedures

### 3.1 Pre-Flight Health Checklist

Before executing the suite on a machine, verify the following baseline prerequisites:

```bash
# 1. Verify root execution permissions
sudo -v

# 2. Check current macOS version and kernel architecture
sw_vers
uname -m

# 3. Check current /etc/hosts file integrity
ls -la /etc/hosts
```

---

### 3.2 Disabling macOS Automatic Updates

To halt macOS update discovery, background downloads, and automated installs:

```bash
# 1. Navigate to the script location
cd /path/to/Disable-MacOS-Updates

# 2. Make scripts executable (if needed)
chmod +x disable_macos_updates.sh restore_macos_updates.sh

# 3. Execute with root privileges
sudo ./disable_macos_updates.sh
```

#### Step-by-Step Execution Sequence

1. **Preflight Validation**: Validates EUID (`0`), Darwin OS kernel, and existence of all binary dependencies (`defaults`, `launchctl`, `dscacheutil`, `mDNSResponder`, `awk`, `mktemp`, `grep`).
2. **Baseline Backup**: Records initial `com.apple.SoftwareUpdate` values to `/var/db/disable_macos_updates_prefs.bak` and a pristine copy of `/etc/hosts` to `/var/db/disable_macos_updates_hosts.bak`.
3. **Defaults Enforcement**: Writes `false` to all automatic check, download, install, configuration data, and App Store preferences.
4. **Daemon Unloading**: Unloads `com.apple.softwareupdated` and related daemons via modern `launchctl bootout`.
5. **Cache Purging**: Cleans out `/Library/Updates/` staging directory.
6. **CDN Sinkholing**: Atomically appends tagged loopback records (`127.0.0.1`) for Apple update domains to `/etc/hosts`.
7. **DNS Flush**: Flushes local resolver caches via `dscacheutil` and `killall -HUP mDNSResponder`.

---

### 3.3 Restoring macOS Automatic Updates

To revert all settings back to factory defaults and allow standard updates:

```bash
sudo ./restore_macos_updates.sh
```

#### Step-by-Step Restoration Sequence

1. **Defaults Re-enabling**: Sets all update flags back to `-bool true`.
2. **Hosts Cleaning**: Strips all lines matching `# disable_macos_updates:managed` from `/etc/hosts` via atomic temporary file replacement.
3. **Daemon Reloading**: Bootstraps and kickstarts `com.apple.softwareupdated` and related daemons.
4. **DNS Cache Flush**: Re-enables clean resolution of Apple update CDN domains.
5. **Update Check**: Triggers `softwareupdate --list` to populate available updates immediately.

---

### 3.4 Post-Flight Verification Runbook

You can inspect the current status at any time using standard terminal commands:

```bash
# 1. Check SoftwareUpdate preferences (all should be 0 / false when disabled)
defaults read /Library/Preferences/com.apple.SoftwareUpdate

# 2. Check App Store commerce preferences (should be 0 / false when disabled)
defaults read /Library/Preferences/com.apple.commerce AutoUpdate

# 3. Check /etc/hosts sinkhole entries (should show 4 managed records when disabled)
grep -i "disable_macos_updates:managed" /etc/hosts

# 4. Verify DNS resolution of update CDN
dscacheutil -q host -a name swscan.apple.com
# Expected output when disabled: 127.0.0.1
# Expected output when restored: Official Apple Akamai / Cloudflare CDN IP
```

---

## 4. Technical Mechanics

### 4.1 Defaults Preference Domains & Keys

The scripts manipulate system-level preference plists located in `/Library/Preferences/`:

| Domain / Plist             | Key Name                           | Disabled Value | Restored Value | Description                                   |
| :------------------------- | :--------------------------------- | :------------- | :------------- | :-------------------------------------------- |
| `com.apple.SoftwareUpdate` | `AutomaticCheckEnabled`            | `false`        | `true`         | Checks for new updates in the background      |
| `com.apple.SoftwareUpdate` | `AutomaticDownload`                | `false`        | `true`         | Downloads update packages automatically       |
| `com.apple.SoftwareUpdate` | `AutomaticallyInstallMacOSUpdates` | `false`        | `true`         | Triggers installation of major/minor updates  |
| `com.apple.SoftwareUpdate` | `ConfigDataInstall`                | `false`        | `true`         | Installs background system configuration data |
| `com.apple.SoftwareUpdate` | `CriticalUpdateInstall`            | `false`        | `true`         | Installs Rapid Security Responses (RSR)       |
| `com.apple.commerce`       | `AutoUpdate`                       | `false`        | `true`         | Controls App Store application auto-updates   |

---

### 4.2 Apple Update CDN Sinkholing

Even when preference flags are disabled, background helper processes may attempt to contact Apple catalog servers. The suite points these domains to localhost (`127.0.0.1`):

- `swscan.apple.com`: Software Update Catalog index and manifest service.
- `swdownload.apple.com`: Package download CDN.
- `swcdn.apple.com`: Asset and delta update distribution server.
- `updates-http.cdn-apple.com`: HTTP/HTTPS content delivery endpoint.

---

### 4.3 Blocking Methods Comparison

| Blocking Method                   | Scope & Effectiveness                   | User Experience                      | Reversibility                | Impact on App Store             |
| :-------------------------------- | :-------------------------------------- | :----------------------------------- | :--------------------------- | :------------------------------ |
| **Disable-MacOS-Updates (Suite)** | **Defaults + Daemons + Hosts Sinkhole** | **No popups, no background traffic** | **Instant and clean**        | **None (Apps update manually)** |
| GUI System Settings Toggles       | Partial (Daemons often bypass toggles)  | Periodic badge notifications remain  | Manual toggle per machine    | None                            |
| MDM SoftwareUpdate Policy         | Enforced via mobileconfig profile       | Configured by MDM admin              | Requires MDM profile removal | Dependent on profile config     |
| Network Router / Pi-hole Block    | Network-wide (fails when device roams)  | Fails outside local Wi-Fi            | Requires router admin access | Can break iOS/iPadOS if shared  |

---

### 4.4 Background Launch Daemons Topology

The suite addresses the following macOS system services:

- `com.apple.softwareupdated`: Primary system update coordination daemon.
- `com.apple.mobile.softwareupdated`: Mobile device and accessory update daemon.
- `com.apple.InstallAssistantService`: Installer coordination helper.
- `com.apple.storedownloadd`: App Store and system asset downloader.
- `com.apple.storekitagentd`: StoreKit transaction helper.
- `com.apple.commerce`: Mac App Store commerce daemon.

---

### 4.5 Cache Invalidation & Storage Footprint

Whenever `/etc/hosts` is modified, the local DNS cache must be flushed to take effect immediately:

```bash
dscacheutil -flushcache
killall -HUP mDNSResponder
```

In addition, `disable_macos_updates.sh` removes partially downloaded staging packages from the system volume:

```bash
rm -rf /Library/Updates/*
```

This immediately reclaims storage space previously occupied by staged update installers.

---

## 5. Backup, Integrity & Recovery

### 5.1 Storage Locations & Permissions

All backups are stored in `/var/db/`, which is root-owned, persistent across reboots, and protected by macOS System Integrity Protection (SIP):

- `/var/db/disable_macos_updates_hosts.bak`: Pristine `/etc/hosts` captured before any sinkhole injection.
- `/var/db/disable_macos_updates_hosts.bak.YYYYMMDD`: Daily timestamped backups for audit history.
- `/var/db/disable_macos_updates_prefs.bak`: Original `defaults` values before disabling.

All backup files are strictly permissioned to `0600 root:wheel` to prevent unauthorized inspection.

---

### 5.2 Manual Emergency Recovery Runbook

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

## 6. Automation & Fleet Deployment Guides

### 6.1 Jamf Pro Deployment & Extension Attribute

#### Jamf Pro Extension Attribute (Status Reporting)

```bash
#!/bin/bash
# Jamf Pro Extension Attribute: macOS Update Freeze Status
if grep -q "# disable_macos_updates:managed" /etc/hosts && \
   [ "$(defaults read /Library/Preferences/com.apple.SoftwareUpdate AutomaticCheckEnabled 2>/dev/null)" = "0" ]; then
    echo "<result>Frozen</result>"
else
    echo "<result>Active</result>"
fi
```

#### Jamf Pro Policy Script

1. Navigate to **Computers > Management Settings > Scripts** in Jamf Pro.
2. Create a new script named `Disable-MacOS-Updates`.
3. Paste the contents of `disable_macos_updates.sh`.
4. Create a Policy targeting your target Smart Computer Group.

---

### 6.2 Munki Integration (nopkg Manifest)

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

---

### 6.3 Kandji & Mosyle Custom Scripts

#### Kandji Custom Script (Remediation)

- **Audit Script**: Checks for presence of `# disable_macos_updates:managed` in `/etc/hosts`. Returns `0` if present, `1` if absent.
- **Remediation Script**: Executes `disable_macos_updates.sh` directly as root.

---

### 6.4 Ansible Playbook with Handlers

```yaml
---
- name: Manage macOS Software Update Freeze State
  hosts: mac_workstations
  become: true
  tasks:
    - name: Deploy Disable-MacOS-Updates suite
      ansible.builtin.copy:
        src: files/disable_macos_updates.sh
        dest: /usr/local/bin/disable_macos_updates.sh
        owner: root
        group: wheel
        mode: "0755"

    - name: Freeze macOS updates
      ansible.builtin.command: /usr/local/bin/disable_macos_updates.sh
      register: disable_result
      changed_when: "'Applied' in disable_result.stdout"
      tags: [freeze, disable]

    - name: Restore macOS updates
      ansible.builtin.command: /usr/local/bin/restore_macos_updates.sh
      register: restore_result
      changed_when: "'RESTORED' in restore_result.stdout"
      tags: [unfreeze, restore]
```

---

## 7. Troubleshooting & Diagnostics

| Symptom / Observation                     | Root Cause Analysis                                                                             | Remediation Steps                                                                                               |
| :---------------------------------------- | :---------------------------------------------------------------------------------------------- | :-------------------------------------------------------------------------------------------------------------- |
| **System Settings badge persists**        | macOS Dock and System Settings cache notification state in `com.apple.systempreferences.plist`. | Run `killall Dock; killall SystemSettings 2>/dev/null` in terminal.                                             |
| **`softwareupdate --list` hangs**         | The command is attempting to contact sinkholed Apple CDN domains and waiting for TCP timeout.   | This is expected when updates are disabled. To restore normal operation, run `sudo ./restore_macos_updates.sh`. |
| **App Store app updates fail**            | `com.apple.commerce AutoUpdate` is disabled.                                                    | Manual updates within the App Store app still function. Alternatively, re-enable commerce auto-updates.         |
| **Corporate proxy bypasses `/etc/hosts`** | Some network PAC files or proxy agents route HTTP requests directly through proxy servers.      | Add `swscan.apple.com` and `swcdn.apple.com` to your proxy or firewall blackhole list.                          |
| **Rapid Security Response (RSR) prompt**  | Pre-downloaded RSR payload was staged prior to script execution.                                | Purge staging directory: `sudo rm -rf /Library/Updates/*`.                                                      |

---

## 8. Frequently Asked Questions (FAQ)

### Does this script disable the Mac App Store?

No. The Mac App Store remains completely operational for browsing, purchasing, and manually downloading applications. Only automatic background operating system updates and automatic app updates are silenced.

### Will this script break Xcode or Command Line Tools?

No. You can continue to install and update Xcode manually via the App Store or Apple Developer Portal (`developer.apple.com`).

### How do I verify that updates are truly blocked?

Run `dscacheutil -q host -a name swscan.apple.com`. If it returns `127.0.0.1`, network-level catalog requests are successfully sinkholed.
