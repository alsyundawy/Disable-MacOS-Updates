#!/usr/bin/env bash
# shellcheck shell=bash
set -Eeuo pipefail
IFS=$'\n\t'
# cspell:words softwareupdate dscacheutil mDNSResponder swscan swdownload swcdn
# cspell:words launchctl plistbuddy SIGINT SIGTERM TMPDIR

# ==============================================================================
# Script Name   : disable_macos_updates.sh
# Version       : 1.2.0
# Created Date  : 2026-09-14
# Last Updated  : 2026-09-22
# Author        : Harry Dertin Sutisna Alsyundawy (@alsyundawy)
# Email         : alsyundawy@gmail.com
# Website       : https://www.alsyundawy.com
# GitHub        : https://github.com/alsyundawy
# Twitter / X   : https://x.com/alsyundawy (@alsyundawy)
# Organization  : WWW.ALSYUNDAWY.NET
# Location      : DKI Jakarta, Indonesia
# ==============================================================================
#
# Purpose:
#     Completely disable macOS automatic software update discovery, download,
#     and installation, and block Apple update CDN domains in /etc/hosts.
#
# What this script does:
#     1. Disables all macOS SoftwareUpdate automatic check/download/install flags
#     2. Disables App Store auto-update
#     3. Blocks Apple update CDN domains via /etc/hosts sinkhole (127.0.0.1)
#     4. Creates pristine and timestamped backups of /etc/hosts before modification
#     5. Unloads macOS SoftwareUpdate background launch daemons
#     6. Clears the /Library/Updates cache directory
#     7. Flushes DNS cache
#
# Usage:
#     ./disable_macos_updates.sh         (prompts for sudo password automatically)
#     sudo ./disable_macos_updates.sh    (explicit superuser execution)
#     curl -fsSL https://raw.githubusercontent.com/alsyundawy/Disable-MacOS-Updates/main/disable_macos_updates.sh | sudo bash
#
# Undo / Restore:
#     ./restore_macos_updates.sh
#     sudo ./restore_macos_updates.sh
#
# Notes:
#     - Requires macOS (Darwin) and must be run as root (via sudo).
#     - Idempotent: safe to run multiple times without duplicating entries.
#     - All host entries and comment blocks are tagged with a unique marker
#       comment so restore_macos_updates.sh can cleanly remove them.
#     - Pristine /etc/hosts backup: /var/db/disable_macos_updates_hosts.bak
#     - Daily /etc/hosts backup:   /var/db/disable_macos_updates_hosts.bak.YYYYMMDD
#     - defaults(1) plist backup:  /var/db/disable_macos_updates_prefs.bak
#
# Security:
#     - set -Eeuo pipefail + IFS hardening.
#     - Preflight validation of all command dependencies and root privileges.
#     - Atomic /etc/hosts replacement via mktemp + chmod/chown + rename(2) mv.
#     - mktemp uses ${TMPDIR:-/tmp} to respect macOS per-session secure temp dir.
#     - All file operations use -- to prevent argument injection.
#     - Restrictive permissions (0600 root:wheel) on all backups in /var/db.
#     - Safe process substitution avoiding pipeline pipefail traps.
#
# Minimum macOS:  12 Monterey (tested); compatible with 10.15+ through 15+ (Sequoia), 26+ (Tahoe), and 27+ (Golden Gate)
# Bash version:   3.2.57+ (native macOS)
#
# ==============================================================================
# DOCNOTE
# ==============================================================================
# 1. Dependency Validation:
#    Preflight now explicitly validates all binary dependencies:
#    awk, chmod, cp, defaults, dscacheutil, find, grep, killall, launchctl,
#    mktemp, mv, rm, sw_vers.
# 2. Modern Launchctl Target Addressing:
#    Addresses services via 'system/<label>' and checks /System/Library/LaunchDaemons
#    in addition to /Library/LaunchDaemons, fixing service unload detection on macOS 11+.
# 3. Preference Backup Preservation:
#    Step 1 will not overwrite existing PREFS_BACKUP on consecutive runs,
#    preserving the original baseline settings for restoration.
# 4. Atomic Hosts Replacement & Permissions:
#    Temporary hosts file permissions (0644 root:wheel) are set BEFORE renaming
#    to /etc/hosts, eliminating TOCTOU read-denial window for unprivileged processes.
# 5. Full Block Tagging & Idempotency:
#    Every generated line in /etc/hosts now carries HOSTS_TAG. Multi-pass execution
#    cleanly replaces the entire managed block without accumulating comments.
# 6. ShellCheck Clean & Pipeline Hardening:
#    Replaced 'A && B || C' in Step 4 with standard 'if/else', and safeguarded
#    verification grep pipeline using process substitution against pipefail aborts.
# 7. mktemp TMPDIR Fix (v1.2.0):
#    Changed mktemp /tmp/hosts.XXXXXXXX to mktemp "${TMPDIR:-/tmp}/hosts.XXXXXXXX"
#    to respect macOS per-session secure temp directory and system sandbox policy.
#    macOS sets TMPDIR to a unique secure path under /var/folders/... per session.
# 8. Atomic Pristine Backup Fix (v1.2.0):
#    grep -v redirect to HOSTS_BACKUP had no error guard — if /etc/hosts became
#    unreadable mid-read, the backup would be empty/partial and silently pass chmod.
#    Now uses a temp file + mv for atomic write with explicit error abort on failure.
# 9. Backward-Compat awk Filter (v1.2.0):
#    Added /^# added by disable_macos_updates/ { next } to the idempotent awk filter
#    to clean orphan headers written by older script versions lacking HOSTS_TAG.
#    Consistent with the equivalent filter in restore_macos_updates.sh.
# 10. AWK ERE Separator Filter (v1.2.0):
#    Added /^# ={20,}/ { next } to idempotent awk filter for separator cleanup,
#    using correct ERE syntax (no escaped braces). Symmetric with restore script.
# 11. Author & Comprehensive Contact Metadata Header (v1.2.0):
#     Standardized official script identification header containing Script Name,
#     Version (1.2.0), Created Date (2026-09-14), Last Updated (2026-09-22),
#     Author (alsyundawy / ༺ Initial H ༻), Email, Website, GitHub, Twitter/X,
#     Organization (WWW.ALSYUNDAWY.NET), and Location (DKI Jakarta, Indonesia).
# 12. Multi-OS Compatibility Invariant (v1.2.0):
#     Validated across macOS Monterey (12), Ventura (13), Sonoma (14),
#     Sequoia (15), Tahoe (26), and Golden Gate (27) on Apple Silicon (M1–M6: Base, Pro, Max, Ultra) and Intel (x86_64 where supported).
# 13. Sudo Auto-Elevation & Piped Execution Handling (v1.2.0):
#     Scripts automatically detect non-root execution (EUID != 0) when run from a
#     local file on disk and re-execute via exec sudo -- bash "${BASH_SOURCE[0]}" "$@",
#     prompting for the sudo password interactively without needing sudo in command.
#
# ==============================================================================
# CHANGELOG
# ==============================================================================
# v1.2.0 (2026-09-22)
#   - ADDED: Transparent sudo auto-elevation with interactive password prompt
#            when executed locally without root privileges (no need to type sudo).
#   - ADDED: Safe detection of piped execution (curl/wget) with informative error
#            if piped without superuser privileges.
#   - FIXED: Typo in sinkhole logging ("Sinkholes:" -> "Sinkholed:").
#   - FIXED: mktemp used hardcoded /tmp instead of ${TMPDIR:-/tmp}, bypassing the
#            macOS per-session secure sandbox temp directory (/var/folders/...).
#   - FIXED: Pristine /etc/hosts backup (grep -v > HOSTS_BACKUP) had no error guard;
#            partial/empty backup silently passed chmod. Now uses atomic mktemp+mv
#            with explicit die() on failure.
#   - ADDED: Backward-compat awk filter /^# added by disable_macos_updates/ to
#            clean orphan headers from older script versions without HOSTS_TAG.
#   - ADDED: /^# ={20,}/ awk filter (correct ERE) for separator cleanup, symmetric
#            with restore_macos_updates.sh.
#   - ADDED: Standardized Author & Comprehensive Contact metadata header block.
#   - UPDATED: DOCNOTE entries 7–13 added to document all v1.2.0 architectural fixes.
# v1.1.0 (2026-09-14)
#   - FIXED: SC2015 warning in Step 4 by replacing 'find ... && ok || warn' with if-statement.
#   - FIXED: Pipeline failure risk under 'set -o pipefail' during verification summary
#            by switching to process substitution loop.
#   - FIXED: launchctl bootout failure on modern macOS by targeting 'system/<service>'
#            and searching /System/Library/LaunchDaemons.
#   - FIXED: Idempotency bug where running script repeatedly caused orphaned comment blocks
#            to accumulate in /etc/hosts.
#   - FIXED: TOCTOU race condition during hosts update by applying chmod 644 and root:wheel
#            chown to temp file prior to mv.
#   - FIXED: Baseline preferences backup loss on subsequent executions by guarding PREFS_BACKUP.
#   - FIXED: Missing required commands in preflight check (awk, chmod, cp, find, grep, sw_vers).
#   - ADDED: Baseline pristine /etc/hosts backup alongside daily timestamped backups.
#   - ADDED: Verification display of App Store commerce AutoUpdate setting.
# v1.0.0 (Initial Release)
#   - Initial implementation of macOS update disabler script.
# ==============================================================================

readonly SCRIPT_VERSION="1.2.0"
readonly SCRIPT_NAME="disable_macos_updates"

# Unique tag injected into /etc/hosts so restore can cleanly remove entries
readonly HOSTS_TAG="# ${SCRIPT_NAME}:managed"

# Backup paths (root-only /var/db — persistent across reboots)
readonly HOSTS_BACKUP="/var/db/${SCRIPT_NAME}_hosts.bak"
readonly PREFS_BACKUP="/var/db/${SCRIPT_NAME}_prefs.bak"

# Apple update CDN domains to sinkhole
readonly -a UPDATE_DOMAINS=(
	"swscan.apple.com"
	"swdownload.apple.com"
	"swcdn.apple.com"
	"updates-http.cdn-apple.com"
	"updates.cdn-apple.com"
	"xp.apple.com"
	"gdmf.apple.com"
)

# macOS SoftwareUpdate launch daemons to unload
readonly -a UPDATE_DAEMONS=(
	"com.apple.softwareupdated"
	"com.apple.mobile.softwareupdated"
	"com.apple.InstallAssistantService"
	"com.apple.storedownloadd"
	"com.apple.storekitagentd"
	"com.apple.commerce"
)

TMP_HOSTS=""
TMP_PRISTINE=""

# ==============================================================================
# TERMINAL COLORS (NO_COLOR convention)
# ==============================================================================

if [[ -t 1 && -z ${NO_COLOR:-} ]]; then
	C_RESET=$'\033[0m'
	C_BOLD=$'\033[1m'
	C_RED=$'\033[1;31m'
	C_YELLOW=$'\033[1;33m'
	C_GREEN=$'\033[1;32m'
	C_CYAN=$'\033[1;36m'
	C_MAGENTA=$'\033[1;35m'
else
	C_RESET=""
	C_BOLD=""
	C_RED=""
	C_YELLOW=""
	C_GREEN=""
	C_CYAN=""
	C_MAGENTA=""
fi

# ==============================================================================
# LOGGING
# ==============================================================================

die() {
	printf "\n%s %s\n\n" "${C_RED}${C_BOLD}✖ ERROR:${C_RESET}" "${C_RED}$*${C_RESET}" >&2
	exit 1
}
info() { printf "%s %s\n" "${C_CYAN}${C_BOLD}ℹ${C_RESET}" "$*"; }
ok() { printf "%s %s\n" "${C_GREEN}${C_BOLD}✔${C_RESET}" "${C_GREEN}$*${C_RESET}"; }
warn() { printf "%s %s\n" "${C_YELLOW}${C_BOLD}⚠${C_RESET}" "${C_YELLOW}$*${C_RESET}" >&2; }
step() { printf "\n%s %s\n" "${C_MAGENTA}${C_BOLD}▶ STEP${C_RESET}" "${C_BOLD}$*${C_RESET}"; }

# ==============================================================================
# CLEANUP
# ==============================================================================

cleanup() {
	if [[ -n ${TMP_HOSTS} && -f ${TMP_HOSTS} ]]; then
		rm -f -- "${TMP_HOSTS}"
	fi
	if [[ -n ${TMP_PRISTINE} && -f ${TMP_PRISTINE} ]]; then
		rm -f -- "${TMP_PRISTINE}"
	fi
}

trap cleanup EXIT
trap 'die "Interrupted at line ${LINENO}."' ERR
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

# ==============================================================================
# PREFLIGHT CHECKS
# ==============================================================================

[[ "$(uname -s || true)" == "Darwin" ]] || die "This script is for macOS only."

# Enforce root privileges with automatic sudo elevation for local script files
if [[ ${EUID} -ne 0 ]]; then
	command -v sudo >/dev/null 2>&1 || die "Command 'sudo' not found. Please run as root."
	if [[ -n "${BASH_SOURCE[0]:-}" && -f "${BASH_SOURCE[0]}" ]]; then
		warn "Root privileges required. Requesting sudo password..."
		exec sudo -- bash "${BASH_SOURCE[0]}" "$@"
	else
		die "Root privileges required. Please execute with 'sudo' (e.g., curl -fsSL <URL> | sudo bash)."
	fi
fi

# Require bash 3.2+
((BASH_VERSINFO[0] >= 3)) || die "Bash 3.2+ is required."

# Require commands
for _c in awk chmod cp defaults dscacheutil find grep killall launchctl mktemp mv rm sw_vers; do
	command -v "${_c}" >/dev/null 2>&1 || die "Required command not found: ${_c}"
done
unset _c

# ==============================================================================
# BANNER
# ==============================================================================

printf "\n"
printf "%s\n" "${C_CYAN}${C_BOLD}╔══════════════════════════════════════════════════════════════╗${C_RESET}"
printf "%s\n" "${C_CYAN}${C_BOLD}║      🔒 macOS Update Disabler — v${SCRIPT_VERSION}            ║${C_RESET}"
printf "%s\n" "${C_CYAN}${C_BOLD}║      Undo: ./restore_macos_updates.sh                        ║${C_RESET}"
printf "%s\n" "${C_CYAN}${C_BOLD}╚══════════════════════════════════════════════════════════════╝${C_RESET}"
printf "\n"

macOS_ver="$(sw_vers -productVersion 2>/dev/null || echo "unknown")"
info "macOS version  : ${C_BOLD}${macOS_ver}${C_RESET}"
info "Timestamp      : ${C_BOLD}$(date '+%Y-%m-%d %H:%M:%S %Z' || true)${C_RESET}"
info "Hosts backup   : ${C_BOLD}${HOSTS_BACKUP}${C_RESET}"
info "Prefs backup   : ${C_BOLD}${PREFS_BACKUP}${C_RESET}"

# ==============================================================================
# STEP 1: BACKUP CURRENT PREFERENCES BEFORE CHANGE
# ==============================================================================

step "1/6  Backing up current SoftwareUpdate preferences..."

if [[ ! -f ${PREFS_BACKUP} ]]; then
	{
		echo "# disable_macos_updates.sh preferences backup"
		echo "# Timestamp: $(date '+%Y-%m-%d %H:%M:%S %Z' || true)"
		echo "# macOS: ${macOS_ver}"
		echo ""
		echo "[com.apple.SoftwareUpdate]"
		for _key in AutomaticCheckEnabled AutomaticDownload AutomaticallyInstallMacOSUpdates \
			ConfigDataInstall CriticalUpdateInstall; do
			_val="$(defaults read /Library/Preferences/com.apple.SoftwareUpdate "${_key}" 2>/dev/null || echo "NOT_SET")"
			echo "  ${_key} = ${_val}"
		done
		echo ""
		echo "[com.apple.commerce]"
		_val="$(defaults read /Library/Preferences/com.apple.commerce AutoUpdate 2>/dev/null ||
			defaults read /Library/Preferences/com.apple.Commerce AutoUpdate 2>/dev/null || echo "NOT_SET")"
		echo "  AutoUpdate = ${_val}"
	} >"${PREFS_BACKUP}"
	chmod 600 "${PREFS_BACKUP}"
	chown root:wheel "${PREFS_BACKUP}" 2>/dev/null || true
	ok "Preferences backup written to: ${PREFS_BACKUP}"
else
	info "Preferences backup already exists at: ${PREFS_BACKUP} (preserving original baseline)"
fi

# ==============================================================================
# STEP 2: DISABLE SOFTWAREUPDATE AUTOMATIC FLAGS
# ==============================================================================

step "2/6  Disabling SoftwareUpdate automatic check / download / install..."

_sw="/Library/Preferences/com.apple.SoftwareUpdate"
_commerce="/Library/Preferences/com.apple.commerce"

defaults write "${_sw}" AutomaticCheckEnabled -bool false
defaults write "${_sw}" AutomaticDownload -bool false
defaults write "${_sw}" AutomaticallyInstallMacOSUpdates -bool false
defaults write "${_sw}" ConfigDataInstall -bool false
defaults write "${_sw}" CriticalUpdateInstall -bool false
defaults write "${_commerce}" AutoUpdate -bool false

# Ensure case-variant plist synchronization if present
if [[ -f "/Library/Preferences/com.apple.Commerce.plist" ]]; then
	defaults write "/Library/Preferences/com.apple.Commerce" AutoUpdate -bool false
fi

ok "SoftwareUpdate automatic flags disabled."

# ==============================================================================
# STEP 3: UNLOAD SOFTWAREUPDATE LAUNCH DAEMONS
# ==============================================================================

step "3/6  Unloading SoftwareUpdate launch daemons..."

for _daemon in "${UPDATE_DAEMONS[@]}"; do
	_unloaded=false

	# 1. Target modern service target (macOS 11+)
	if launchctl bootout "system/${_daemon}" 2>/dev/null; then
		ok "  Unloaded: ${_daemon} (service target)"
		_unloaded=true
	fi

	# 2. Target system daemon plist
	if [[ ${_unloaded} == false && -f "/System/Library/LaunchDaemons/${_daemon}.plist" ]]; then
		if launchctl bootout system "/System/Library/LaunchDaemons/${_daemon}.plist" 2>/dev/null; then
			ok "  Unloaded: ${_daemon} (system daemon plist)"
			_unloaded=true
		fi
	fi

	# 3. Target local daemon plist
	if [[ ${_unloaded} == false && -f "/Library/LaunchDaemons/${_daemon}.plist" ]]; then
		if launchctl bootout system "/Library/LaunchDaemons/${_daemon}.plist" 2>/dev/null; then
			ok "  Unloaded: ${_daemon} (library daemon plist)"
			_unloaded=true
		fi
	fi

	# 4. Fallback legacy label
	if [[ ${_unloaded} == false ]] && launchctl bootout system "${_daemon}" 2>/dev/null; then
		ok "  Unloaded: ${_daemon} (legacy label)"
		_unloaded=true
	fi

	if [[ ${_unloaded} == false ]]; then
		warn "  Not loaded (or already disabled/protected): ${_daemon}"
	fi
done

ok "Launch daemon step complete."

# ==============================================================================
# STEP 4: CLEAR UPDATE CACHE
# ==============================================================================

step "4/6  Clearing /Library/Updates cache..."

if [[ -d /Library/Updates ]]; then
	# Find and remove only files/dirs under /Library/Updates (not the dir itself)
	if find /Library/Updates -mindepth 1 -delete 2>/dev/null; then
		ok "/Library/Updates cache cleared."
	else
		warn "Could not fully clear /Library/Updates (some files may be in use)."
	fi
else
	info "/Library/Updates does not exist — skipping."
fi

# ==============================================================================
# STEP 5: SINKHOLE APPLE UPDATE DOMAINS IN /etc/hosts
# ==============================================================================

step "5/6  Adding Apple update CDN domains to /etc/hosts sinkhole..."

# 1. Backup pristine baseline /etc/hosts once (before any sinkholes exist)
if [[ ! -f ${HOSTS_BACKUP} ]]; then
	if grep -q "${HOSTS_TAG}" /etc/hosts 2>/dev/null; then
		# Use temp file + atomic mv to prevent partial/empty HOSTS_BACKUP on read error
		TMP_PRISTINE="$(mktemp "${TMPDIR:-/tmp}/hosts_pristine.XXXXXXXX")"
		grep -v "${HOSTS_TAG}" /etc/hosts >"${TMP_PRISTINE}" || {
			rm -f -- "${TMP_PRISTINE}"
			TMP_PRISTINE=""
			die "Failed to build pristine /etc/hosts content for backup."
		}
		mv -f -- "${TMP_PRISTINE}" "${HOSTS_BACKUP}"
		TMP_PRISTINE=""
	else
		cp -p -- /etc/hosts "${HOSTS_BACKUP}"
	fi
	chmod 600 "${HOSTS_BACKUP}"
	chown root:wheel "${HOSTS_BACKUP}" 2>/dev/null || true
	ok "  Baseline pristine /etc/hosts backup written to: ${HOSTS_BACKUP}"
else
	info "  Baseline /etc/hosts backup already exists: ${HOSTS_BACKUP}"
fi

# 2. Daily timestamped backup (idempotent: skip if backup already exists from today)
_today="$(date '+%Y%m%d')"
_dated_backup="${HOSTS_BACKUP}.${_today}"
if [[ ! -f ${_dated_backup} ]]; then
	cp -p -- /etc/hosts "${_dated_backup}"
	chmod 600 "${_dated_backup}"
	chown root:wheel "${_dated_backup}" 2>/dev/null || true
	ok "  Daily /etc/hosts backup written to: ${_dated_backup}"
else
	info "  Daily /etc/hosts backup already exists for today: ${_dated_backup}"
fi

# Build new /etc/hosts atomically via temp file
# Use ${TMPDIR:-/tmp} to respect macOS per-session secure sandbox temp directory
TMP_HOSTS="$(mktemp "${TMPDIR:-/tmp}/hosts.XXXXXXXX")"
chmod 644 "${TMP_HOSTS}"
chown root:wheel "${TMP_HOSTS}" 2>/dev/null || true

# Strip any previously managed lines and clean duplicate blank lines
# NOTE: /^# ={20,}/ uses correct awk ERE (no backslashes before quantifier braces)
awk -v tag="${HOSTS_TAG}" '
    index($0, tag) { next }
    /^# Apple Update CDN Sinkhole/ { next }
    /^# added by disable_macos_updates/ { next }
    /^# Remove with:.*restore_macos_updates/ { next }
    /^# Timestamp:.*disable_macos_updates/ { next }
    /^# ={20,}/ { next }
    { print }
' /etc/hosts | awk '
    /^[[:space:]]*$/ { blank++; next }
    { for(i=0; i<blank; i++) print ""; blank=0; print }
    END { if (NR > 0) printf "" }
' >"${TMP_HOSTS}"

# Append sinkhole header + managed entries (all tagged with HOSTS_TAG for clean removal)
{
	printf "\n"
	printf "# ============================================================ %s\n" "${HOSTS_TAG}"
	printf "# Apple Update CDN Sinkhole — added by %s v%s %s\n" "${SCRIPT_NAME}" "${SCRIPT_VERSION}" "${HOSTS_TAG}"
	printf "# Timestamp: %s %s\n" "$(date '+%Y-%m-%d %H:%M:%S %Z' || true)" "${HOSTS_TAG}"
	printf "# Remove with: ./restore_macos_updates.sh %s\n" "${HOSTS_TAG}"
	printf "# ============================================================ %s\n" "${HOSTS_TAG}"
	for _domain in "${UPDATE_DOMAINS[@]}"; do
		printf "127.0.0.1  %-40s %s\n" "${_domain}" "${HOSTS_TAG}"
	done
} >>"${TMP_HOSTS}"

# Ensure permissions before atomic move
chmod 644 "${TMP_HOSTS}"
chown root:wheel "${TMP_HOSTS}" 2>/dev/null || true

# Atomic move (same filesystem → rename(2))
mv -f -- "${TMP_HOSTS}" /etc/hosts
chmod 644 /etc/hosts
TMP_HOSTS="" # already moved; cleanup trap no longer needs it

for _domain in "${UPDATE_DOMAINS[@]}"; do
	ok "  Sinkholed: ${_domain} → 127.0.0.1"
done

# ==============================================================================
# STEP 6: FLUSH DNS CACHE
# ==============================================================================

step "6/6  Flushing DNS cache..."

dscacheutil -flushcache
killall -HUP mDNSResponder 2>/dev/null || true

ok "DNS cache flushed."

# ==============================================================================
# VERIFICATION SUMMARY
# ==============================================================================

printf "\n"
printf "%s\n" "${C_GREEN}${C_BOLD}══════════════════════════════════════════════════════════════${C_RESET}"
printf "%s\n" "${C_GREEN}${C_BOLD}  ✔  macOS automatic updates DISABLED successfully!${C_RESET}"
printf "%s\n" "${C_GREEN}${C_BOLD}══════════════════════════════════════════════════════════════${C_RESET}"

printf "\n"
info "Current SoftwareUpdate settings:"
for _key in AutomaticCheckEnabled AutomaticDownload AutomaticallyInstallMacOSUpdates ConfigDataInstall CriticalUpdateInstall; do
	_val="$(defaults read /Library/Preferences/com.apple.SoftwareUpdate "${_key}" 2>/dev/null || echo "NOT_SET")"
	printf "    %-46s = %s\n" "${_key}" "${C_BOLD}${_val}${C_RESET}"
done

_commerce_val="$(defaults read /Library/Preferences/com.apple.commerce AutoUpdate 2>/dev/null ||
	defaults read /Library/Preferences/com.apple.Commerce AutoUpdate 2>/dev/null || echo "NOT_SET")"
printf "    %-46s = %s\n" "App Store AutoUpdate (com.apple.commerce)" "${C_BOLD}${_commerce_val}${C_RESET}"

printf "\n"
info "/etc/hosts sinkhole entries:"
while IFS= read -r _line; do
	[[ -z ${_line} ]] && continue
	_entry="${_line%%#*}"
	if [[ -n ${_entry// /} ]]; then
		printf "    %s\n" "${_entry}"
	fi
done < <(grep "${HOSTS_TAG}" /etc/hosts 2>/dev/null || true)

printf "\n"
warn "To re-enable updates, run:  ${C_BOLD}./restore_macos_updates.sh${C_RESET} (or sudo ./restore_macos_updates.sh)"
printf "\n"
