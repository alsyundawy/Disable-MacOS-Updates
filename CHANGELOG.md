# Changelog

All notable changes to **Disable-MacOS-Updates** will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [1.2.0] - 2026-09-22

### Fixed
- **macOS Sandbox & `$TMPDIR` Compliance**:
  - `disable_macos_updates.sh` & `restore_macos_updates.sh`: Replaced hardcoded `/tmp/hosts.XXXXXXXX` with `mktemp "${TMPDIR:-/tmp}/hosts.XXXXXXXX"`. This ensures compliance with macOS per-session secure temp directory conventions (`/var/folders/...`), eliminating temp-file race hazards and adhering to macOS sandboxing.
- **AWK Extended Regular Expression (ERE) Quantifier Bug**:
  - `restore_macos_updates.sh`: Fixed broken awk separator filter regex `/^# =\{20,\}/`. Under POSIX awk ERE rules, escaped braces `\{` and `\}` are interpreted as literal characters rather than interval quantifiers. This rendered the separator cleanup dead code. Corrected to `/^# ={20,}/` which accurately matches 20 or more consecutive `=` characters.
  - `disable_macos_updates.sh`: Added the symmetrical `/^# ={20,}/` separator filter to ensure clean multi-pass execution.
- **Atomic Pristine Backup Hazard**:
  - `disable_macos_updates.sh`: Replaced bare redirect `grep -v "${HOSTS_TAG}" /etc/hosts > "${HOSTS_BACKUP}"` with atomic `mktemp` intermediate file creation and `mv -f` pattern. If a disk write or pipeline error occurred mid-read, the previous implementation could create an empty or truncated baseline backup. The new implementation guarantees atomic write and halts with `die()` on failure.
- **Backward-Compatible Comment Stripping**:
  - `disable_macos_updates.sh`: Added `/^# added by disable_macos_updates/ { next }` filter to the idempotent awk pipeline. Ensures legacy headers from older script versions without the explicit `# disable_macos_updates:managed` tag are completely purged upon re-execution.

### Added
- **Standardized Author & Contact Metadata Header**:
  - Official script identification header in both scripts containing Script Name, Version (1.2.0), Created Date (2026-09-14), Last Updated (2026-09-22), Author (`alsyundawy` / `༺ Initial H ༻`), Email (`alsyundawy@gmail.com`), Website (`https://www.alsyundawy.com`), GitHub (`https://github.com/alsyundawy`), Twitter / X (`https://x.com/alsyundawy`), Organization (`WWW.ALSYUNDAWY.NET`), and Location (`DKI Jakarta, Indonesia`).
- **Multi-OS Compatibility Invariant**:
  - Verified across macOS Monterey (12), Ventura (13), Sonoma (14), Sequoia (15), and Tahoe (16) on both Apple Silicon (M1–M4) and Intel (x86_64).

### Updated
- `DOCNOTE` in both scripts expanded with entries 7–10 (restore) and 7–12 (disable) to formally document all v1.2.0 architectural enhancements.
- Header Security sections now document `$TMPDIR` sandbox compliance.

---

## [1.1.0] - 2026-09-14

### Fixed
- **ShellCheck Warning SC2034**:
  - Referenced `SCRIPT_NAME` in backup path generation and header banners across both scripts, resolving unused variable warnings.
- **Arithmetic Crash on Zero Matches**:
  - `restore_macos_updates.sh`: Replaced fragile `grep -c || echo 0` with `grep -c ... || true`. Under zero-match conditions, `grep -c || echo 0` produced multiline `0\n0` strings that crashed bash arithmetic evaluations `(( _count == 0 ))`.
- **Launch Daemon Symmetrical Alignment**:
  - Added `com.apple.mobile.softwareupdated` to the `UPDATE_DAEMONS` array in `restore_macos_updates.sh` to ensure complete symmetrical recovery of all unloaded update daemons.
- **Pipeline Pipefail Protection**:
  - Replaced unshielded verification grep pipelines with process substitution loops (`while IFS= read -r ...; do ... done < <(...)`), preventing false-positive `set -o pipefail` script aborts.
- **Preflight Dependency Audit**:
  - Added missing command validations for `awk`, `chmod`, `cp`, `find`, `grep`, and `sw_vers` to the preflight dependency check.
- **Atomic Hosts Filtering**:
  - Replaced multi-step temporary file handling with a streamlined single-pipeline awk filter.
- **App Store Commerce Identifier Normalization**:
  - Added support for both lowercase `com.apple.commerce` and capitalized `com.apple.Commerce` preference domains across macOS releases.

---

## [1.0.0] - 2026-09-14

### Added
- Initial public release of **Disable-MacOS-Updates**.
- Full macOS automatic software update discovery, download, and background installation disabler (`disable_macos_updates.sh`).
- Complete restoration and recovery utility (`restore_macos_updates.sh`).
- Defense-in-depth Apple update CDN sinkholing via `/etc/hosts` targeting `swscan.apple.com`, `swdownload.apple.com`, `swcdn.apple.com`, and `updates-http.cdn-apple.com`.
- Background launch daemon management via modern `launchctl` service targets.
- Baseline preference backup (`/var/db/disable_macos_updates_prefs.bak`) and timestamped `/etc/hosts` backups.
- DNS cache flushing via `dscacheutil` and `mDNSResponder`.
