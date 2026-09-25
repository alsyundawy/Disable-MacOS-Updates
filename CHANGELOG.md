<!-- markdownlint-disable-file MD024 -->

# Changelog

All notable changes to **Disable-MacOS-Updates** will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [1.3.0] - 2026-09-26

### Added

- **Official Cyber-Hardened Banner & Flyer Asset Suite**:
  - `assets/disable-macos-updates-banner.jpg` & `assets/flyer.jpg`: Production-grade high-tech cyber security infographic banner and flyer (1376x768, 16:9). Incorporates dark neon circuit aesthetics, central glowing Apple padlock shield, symmetrical hexagonal badges covering macOS Monterey to Sequoia compatibility, SIP compliance, daemon control, 7-domain CDN sinkholing, 100% symmetrical reversibility, 0% CPU & battery impact, Apple Silicon (M1–M6) & Intel universal support, and strict POSIX Bash 3.2+ invariants.
  - `assets/alsyundawy-banner.png` & `assets/banner.png`: Official maintainer banner for Alsyundawy IT Solution embedded in the Maintainer & Contact sections across project documentation.
- **Defensive Error Trap De-escalation (`trap - ERR`)**:
  - `disable_macos_updates.sh` & `restore_macos_updates.sh`: `die()` now immediately resets the `ERR` trap via `trap - ERR` as its first statement. This eliminates potential re-entrant trap firing loops if any command inside `die()` encounters an error or subshell signal (defense-in-depth).
- **POSIX-Compliant Command Execution Invariants**:
  - `restore_macos_updates.sh`: Replaced legacy `head -20` shorthand with canonical POSIX-1003.1 standard `head -n 20` during the post-restoration software update catalog check.
- **Enhanced Stream Processing & Blank-Line Normalization**:
  - `disable_macos_updates.sh` & `restore_macos_updates.sh`: Streamlined BSD `awk` stream processing by removing dead-code `END { if (NR > 0) printf "" }` no-op blocks, while preserving intermediate multi-line spacing and cleanly stripping trailing EOF blank lines.
- **Comprehensive Documentation Architecture (ADR-008 through ADR-011)**:
  - `DOCNOTE.md`: Expanded with 4 new formal Architectural Decision Records detailing trap de-escalation, stream normalization invariants, POSIX utility compliance, and visual design architecture.
  - `MANUAL.md`: Enriched with low-level TCP loopback socket behavior (`ECONNREFUSED` on port 443/80), daemons lifecycle matrix, and updated fleet management runbooks for Jamf Pro, Kandji, Mosyle, and Ansible.
  - `README.md`: Enriched with What's New in v1.3.0 highlight section, visual hero banner flyer, and updated release badges.

### Fixed

- **Dead-Code AWK `printf ""` Elimination**:
  - Removed redundant `END { if (NR > 0) printf "" }` statement from both scripts' `/etc/hosts` normalizer pipeline. `printf ""` emits zero bytes and has no execution effect.
- **Misleading Inline Parser Documentation**:
  - Corrected internal comments from `"clean duplicate blank lines"` to accurately describe the two-stage parser behavior: preserving intermediate blank line sequences while trimming accumulated trailing blanks at EOF.

### Changed

- Updated version designation to `1.3.0` across all script constants (`readonly SCRIPT_VERSION="1.3.0"`), documentation badges, manual runbooks, and directory trees.
- Updated Last Updated release timestamps to `2026-09-26`.

---

## [1.2.0] - 2026-09-22

### Added

- **Transparent Sudo Auto-Elevation with Interactive Password Prompt**:
  - `disable_macos_updates.sh` & `restore_macos_updates.sh`: Scripts now detect non-root execution (`EUID != 0`) when run directly from a local script file (`[[ -n "${BASH_SOURCE[0]:-}" && -f "${BASH_SOURCE[0]}" ]]`). Instead of abruptly terminating, the scripts automatically request administrator privileges via `exec sudo -- bash "${BASH_SOURCE[0]}" "$@"`, prompting for the sudo password interactively in the terminal without requiring the user to type `sudo` upfront.
- **Safe Remote Piped Execution Detection**:
  - `disable_macos_updates.sh` & `restore_macos_updates.sh`: When piped directly from `curl` or `wget` without superuser privileges (`curl ... | bash`), the scripts safely detect the absence of an on-disk source file and halt with an informative instruction directing the user to pipe to `sudo bash`.
- **Direct Remote Execution via `curl` and `wget`**:
  - `README.md` & `MANUAL.md`: Added direct one-liner execution instructions using native macOS `curl` and `wget` for both disabler and restorer utilities.
- **Standardized Author & Contact Metadata Header**:
  - Official script identification header in both scripts containing Script Name, Version (1.2.0), Created Date (2026-09-14), Last Updated (2026-09-22), Author (`Harry Dertin Sutisna Alsyundawy (@alsyundawy)`), Email (`alsyundawy@gmail.com`), Website (`https://www.alsyundawy.com`), GitHub (`https://github.com/alsyundawy`), Twitter / X (`https://x.com/alsyundawy`), Organization (`WWW.ALSYUNDAWY.NET`), and Location (`DKI Jakarta, Indonesia`).
- **Multi-OS & Apple Silicon Architecture Matrix**:
  - Comprehensive verification and documentation across macOS Monterey (12), Ventura (13), Sonoma (14), Sequoia (15), Tahoe (26), and Golden Gate (27).
  - Explicit hardware coverage across all authentic Apple Silicon processor generations (M1, M2, M3, M4, M5, M6 — Base, Pro, Max, Ultra tiers), documenting Intel x86_64 deprecation after macOS 26 Tahoe.
- **Operations Manual & Architecture Guidelines**:
  - Expanded `MANUAL.md` with complete operational runbooks, pre-flight checklists, and fleet management guides for Jamf Pro, Munki, Kandji, Mosyle, and Ansible.
  - Expanded `DOCNOTE.md` with 7 formal Architectural Decision Records (ADRs including ADR-007 for sudo auto-elevation), low-level Darwin invariants, and BSD awk regex specifications.

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
- **Domain Sinkhole Documentation Discrepancy**:
  - `README.md` & `MANUAL.md`: Corrected documentation stating only 4 Apple CDN domains were sinkholed. Updated all tables and descriptions to reflect all 7 active sinkhole targets (`swscan.apple.com`, `swdownload.apple.com`, `swcdn.apple.com`, `updates-http.cdn-apple.com`, `updates.cdn-apple.com`, `xp.apple.com`, `gdmf.apple.com`).
- **Logging Grammar Polish**:
  - `disable_macos_updates.sh`: Corrected console log message from `Sinkholes:` to `Sinkholed:`.
- **Author & Contact Header Normalization**:
  - Corrected author identification in both script headers and documentation to `Harry Dertin Sutisna Alsyundawy (@alsyundawy)`, replacing placeholder nickname entries.
- **Markdownlint Standalone Configuration**:
  - Replaced unresolvable `extends` dependencies with self-contained root configurations in `.markdownlint.json` and `.markdownlint.yaml`, eliminating VS Code extension crash warnings.

### Updated

- `DOCNOTE` in both scripts expanded with entries 7–11 (restore) and 7–13 (disable) to formally document all v1.2.0 architectural enhancements.
- Header Security sections now document `$TMPDIR` sandbox compliance and transparent `sudo` auto-elevation.

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
- Apple update CDN sinkholing via `/etc/hosts` targeting `swscan.apple.com`, `swdownload.apple.com`, `swcdn.apple.com`, and `updates-http.cdn-apple.com`.
- Background launch daemon management via modern `launchctl` service targets.
- Baseline preference backup (`/var/db/disable_macos_updates_prefs.bak`) and timestamped `/etc/hosts` backups.
- DNS cache flushing via `dscacheutil` and `mDNSResponder`.
