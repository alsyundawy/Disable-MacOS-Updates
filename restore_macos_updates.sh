#!/usr/bin/env bash
# shellcheck shell=bash
set -Eeuo pipefail
IFS=$'\n\t'
# cspell:words softwareupdate dscacheutil mDNSResponder swscan swdownload swcdn
# cspell:words launchctl plistbuddy SIGINT SIGTERM TMPDIR

# ==============================================================================
# Script Name   : restore_macos_updates.sh
# Version       : 1.2.0
# Created Date  : 2026-09-14
# Last Updated  : 2026-09-22
# Author        : alsyundawy (༺ Initial H ༻)
# Email         : alsyundawy@gmail.com
# Website       : https://www.alsyundawy.com
# GitHub        : https://github.com/alsyundawy
# Twitter / X   : https://x.com/alsyundawy (@alsyundawy)
# Organization  : WWW.ALSYUNDAWY.NET
# Location      : DKI Jakarta, Indonesia
# ==============================================================================
#
# Purpose:
#     Undo / restore all changes made by disable_macos_updates.sh.
#     Re-enables macOS automatic software update discovery, download, and
#     installation, and removes the Apple update CDN sinkhole from /etc/hosts.
#
# What this script does:
#     1. Re-enables all macOS SoftwareUpdate automatic check/download/install flags
#     2. Re-enables App Store auto-update
#     3. Removes Apple update CDN sinkhole entries from /etc/hosts
#     4. Reloads macOS SoftwareUpdate background launch daemons
#     5. Flushes DNS cache
#     6. Triggers a new software update check (softwareupdate --list)
#
# Usage:
#     sudo ./restore_macos_updates.sh
#
# Notes:
#     - Requires macOS (Darwin) and must be run as root (via sudo).
#     - Idempotent: safe to run multiple times without syntax errors.
#     - Only removes /etc/hosts entries tagged by disable_macos_updates.sh.
#     - If the prefs backup (/var/db/disable_macos_updates_prefs.bak) is found,
#       the original values are displayed for reference; macOS defaults (true) applied.
#
# Security:
#     - set -Eeuo pipefail + IFS hardening.
#     - Preflight validation of all binary dependencies and root privileges.
#     - Atomic /etc/hosts replacement via mktemp + chmod/chown + rename(2) mv.
#     - mktemp uses ${TMPDIR:-/tmp} to respect macOS per-session secure temp dir.
#     - Restrictive permissions (0600 root:wheel) on pre-restore hosts backup.
#     - Safe grep count calculation and process substitution avoiding pipefail aborts.
#
# Minimum macOS:  12 Monterey (tested); compatible with 10.15+ through 15+ (Sequoia) & 16+ (Tahoe)
# Bash version:   3.2.57+ (native macOS)
#
# ==============================================================================
# DOCNOTE
# ==============================================================================
# 1. Variable Usage Fix (SC2034):
#    SCRIPT_NAME is now properly referenced in the backup filename generator
#    and console banner, eliminating ShellCheck warning SC2034.
# 2. Arithmetic Syntax Error Resolution:
#    Replaced fragile 'grep -c || echo 0' with 'grep -c ... || true' to prevent
#    accidental output of '0\n0' when matches are 0, avoiding bash arithmetic crashes.
# 3. Synchronized Daemon List:
#    Added 'com.apple.mobile.softwareupdated' to UPDATE_DAEMONS so all services
#    unloaded by disable_macos_updates.sh are symmetrically re-enabled.
# 4. Modern Launchctl Re-enabling:
#    Supports modern service bootstrap, kickstart, and plist loading across
#    /System/Library/LaunchDaemons, /Library/LaunchDaemons, and service targets.
# 5. Pipeline Pipefail Hardening:
#    Protected preferences backup inspection and hosts entry verification
#    with process substitution loops, preventing false ERR trap triggers.
# 6. Preflight Command Audit:
#    Added awk, chmod, cp, grep, sw_vers to preflight command validation.
# 7. mktemp TMPDIR Fix (v1.2.0):
#    Changed mktemp /tmp/hosts.XXXXXXXX to mktemp "${TMPDIR:-/tmp}/hosts.XXXXXXXX"
#    to respect macOS per-session secure temp directory and system sandbox policy.
#    macOS sets TMPDIR to a unique secure path under /var/folders/... per session.
# 8. AWK ERE Regex Fix (v1.2.0):
#    Fixed broken awk regex /^# =\{20,\}/ — in awk ERE, backslashes before { }
#    make them literal characters, so the pattern never matched any separator line.
#    Corrected to /^# ={20,}/ which properly matches 20+ consecutive '=' chars.
#
# ==============================================================================
# CHANGELOG
# ==============================================================================
# v1.2.0 (2026-09-22)
#   - FIXED: mktemp used hardcoded /tmp instead of ${TMPDIR:-/tmp}, bypassing the
#            macOS per-session secure sandbox temp directory (/var/folders/...).
#   - FIXED: awk ERE regex /^# =\{20,\}/ was incorrect — backslashes escape { } to
#            literal chars in awk ERE, making the separator filter dead code
#            (never matched any line). Corrected to /^# ={20,}/ (proper ERE form).
#   - UPDATED: DOCNOTE entries 7 and 8 added to document the above fixes.
#   - UPDATED: Header Security section now documents TMPDIR mktemp behaviour.
# v1.1.0 (2026-09-14)
#   - FIXED: SC2034 warning by utilizing SCRIPT_NAME in backup path and header banner.
#   - FIXED: Critical arithmetic syntax error in '(( _count == 0 ))' caused by
#            'grep -c || echo 0' producing multiline '0\n0' on zero matches.
#   - FIXED: Missing 'com.apple.mobile.softwareupdated' in UPDATE_DAEMONS array.
#   - FIXED: Pipeline failure risk under 'set -o pipefail' during backup review.
#   - FIXED: Missing command dependencies in preflight check (awk, chmod, cp, grep, sw_vers).
#   - FIXED: Streamlined atomic hosts filtering into single pipeline, removing temporary .clean file.
#   - ADDED: Both lowercase and capitalized bundle identifier support for com.apple.commerce.
# v1.0.0 (Initial Release)
#   - Initial implementation of macOS update restorer script.
# ==============================================================================

readonly SCRIPT_VERSION="1.2.0"
readonly SCRIPT_NAME="restore_macos_updates"

# Must match the tag used by disable_macos_updates.sh
readonly HOSTS_TAG="# disable_macos_updates:managed"

# Backup paths used by disable_macos_updates.sh
readonly PREFS_BACKUP="/var/db/disable_macos_updates_prefs.bak"

# macOS SoftwareUpdate launch daemons to reload (synchronized with disable script)
readonly -a UPDATE_DAEMONS=(
    "com.apple.softwareupdated"
    "com.apple.mobile.softwareupdated"
    "com.apple.InstallAssistantService"
    "com.apple.storedownloadd"
    "com.apple.storekitagentd"
    "com.apple.commerce"
)

TMP_HOSTS=""

# ==============================================================================
# TERMINAL COLORS (NO_COLOR convention)
# ==============================================================================

if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
    C_RESET=$'\033[0m'; C_BOLD=$'\033[1m'
    C_RED=$'\033[1;31m';    C_YELLOW=$'\033[1;33m'
    C_GREEN=$'\033[1;32m';  C_CYAN=$'\033[1;36m'
    C_MAGENTA=$'\033[1;35m'
else
    C_RESET=""; C_BOLD=""; C_RED=""; C_YELLOW=""
    C_GREEN=""; C_CYAN=""; C_MAGENTA=""
fi

# ==============================================================================
# LOGGING
# ==============================================================================

die()  { printf "\n%s %s\n\n" "${C_RED}${C_BOLD}✖ ERROR:${C_RESET}"  "${C_RED}$*${C_RESET}"  >&2; exit 1; }
info() { printf "%s %s\n"     "${C_CYAN}${C_BOLD}ℹ${C_RESET}"        "$*"; }
ok()   { printf "%s %s\n"     "${C_GREEN}${C_BOLD}✔${C_RESET}"       "${C_GREEN}$*${C_RESET}"; }
warn() { printf "%s %s\n"     "${C_YELLOW}${C_BOLD}⚠${C_RESET}"      "${C_YELLOW}$*${C_RESET}" >&2; }
step() { printf "\n%s %s\n"   "${C_MAGENTA}${C_BOLD}▶ STEP${C_RESET}" "${C_BOLD}$*${C_RESET}"; }

# ==============================================================================
# CLEANUP
# ==============================================================================

cleanup() {
    if [[ -n "${TMP_HOSTS}" && -f "${TMP_HOSTS}" ]]; then
        rm -f -- "${TMP_HOSTS}"
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

[[ "$(uname -s)" == "Darwin" ]] || die "This script is for macOS only."
[[ "${EUID}" -eq 0 ]]           || die "Must be run as root. Use: sudo $0"
(( BASH_VERSINFO[0] >= 3 ))     || die "Bash 3.2+ is required."

for _c in awk chmod cp defaults dscacheutil grep killall launchctl mktemp mv rm softwareupdate sw_vers; do
    command -v "${_c}" >/dev/null 2>&1 || die "Required command not found: ${_c}"
done
unset _c

# ==============================================================================
# BANNER
# ==============================================================================

printf "\n"
printf "%s\n" "${C_GREEN}${C_BOLD}╔══════════════════════════════════════════════════════════════╗${C_RESET}"
printf "%s\n" "${C_GREEN}${C_BOLD}║      🔓 macOS Update Restorer — v${SCRIPT_VERSION}                      ║${C_RESET}"
printf "%s\n" "${C_GREEN}${C_BOLD}║      Undoes: disable_macos_updates.sh                        ║${C_RESET}"
printf "%s\n" "${C_GREEN}${C_BOLD}╚══════════════════════════════════════════════════════════════╝${C_RESET}"
printf "\n"

macOS_ver="$(sw_vers -productVersion 2>/dev/null || echo "unknown")"
info "macOS version : ${C_BOLD}${macOS_ver}${C_RESET}"
info "Timestamp     : ${C_BOLD}$(date '+%Y-%m-%d %H:%M:%S %Z')${C_RESET}"
info "Script        : ${C_BOLD}${SCRIPT_NAME}.sh${C_RESET}"

# Show prefs backup status
if [[ -f "${PREFS_BACKUP}" ]]; then
    info "Prefs backup  : ${C_BOLD}${PREFS_BACKUP}${C_RESET} (found — will display for reference)"
else
    warn "Prefs backup not found at ${PREFS_BACKUP} — will apply macOS defaults."
fi

# ==============================================================================
# STEP 1: RE-ENABLE SOFTWAREUPDATE AUTOMATIC FLAGS
# ==============================================================================

step "1/5  Re-enabling SoftwareUpdate automatic check / download / install..."

_sw="/Library/Preferences/com.apple.SoftwareUpdate"
_commerce="/Library/Preferences/com.apple.commerce"

# Re-enable all flags to macOS default (true)
defaults write "${_sw}" AutomaticCheckEnabled            -bool true
defaults write "${_sw}" AutomaticDownload                -bool true
defaults write "${_sw}" AutomaticallyInstallMacOSUpdates   -bool true
defaults write "${_sw}" ConfigDataInstall                -bool true
defaults write "${_sw}" CriticalUpdateInstall            -bool true
defaults write "${_commerce}" AutoUpdate                 -bool true

if [[ -f "/Library/Preferences/com.apple.Commerce.plist" ]]; then
    defaults write "/Library/Preferences/com.apple.Commerce" AutoUpdate -bool true
fi

ok "SoftwareUpdate automatic flags re-enabled."

# If we have a backup, show original values for user awareness safely without pipefail trigger
if [[ -f "${PREFS_BACKUP}" ]]; then
    info "Original values from backup (for reference):"
    while IFS= read -r _line; do
        [[ -z "${_line}" ]] && continue
        printf "    %s\n" "${_line}"
    done < <(grep -v '^#' "${PREFS_BACKUP}" 2>/dev/null | grep '=' 2>/dev/null || true)
fi

# ==============================================================================
# STEP 2: REMOVE APPLE UPDATE DOMAIN SINKHOLE FROM /etc/hosts
# ==============================================================================

step "2/5  Removing Apple update CDN sinkhole from /etc/hosts..."

# Count managed entries before removal safely
_count="$(grep -c "${HOSTS_TAG}" /etc/hosts 2>/dev/null || true)"
_count="${_count:-0}"

if (( _count == 0 )); then
    info "No managed sinkhole entries found in /etc/hosts — already clean."
else
    # Backup current /etc/hosts before removal
    _restore_backup="/var/db/${SCRIPT_NAME}_hosts_$(date '+%Y%m%d_%H%M%S').bak"
    cp -p -- /etc/hosts "${_restore_backup}"
    chmod 600 "${_restore_backup}"
    chown root:wheel "${_restore_backup}" 2>/dev/null || true
    ok "  Pre-restore /etc/hosts backup: ${_restore_backup}"

    # Build clean hosts file (atomic via mktemp + mv)
    # Use ${TMPDIR:-/tmp} to respect macOS per-session secure sandbox temp directory
    TMP_HOSTS="$(mktemp "${TMPDIR:-/tmp}/hosts.XXXXXXXX")"
    chmod 644 "${TMP_HOSTS}"
    chown root:wheel "${TMP_HOSTS}" 2>/dev/null || true

    # Strip all managed sinkhole lines and header comment blocks cleanly in single pipeline
    # NOTE: /^# ={20,}/ uses correct awk ERE syntax (no backslashes before quantifier braces)
    awk -v tag="${HOSTS_TAG}" '
        index($0, tag) { next }
        /^# Apple Update CDN Sinkhole/ { next }
        /^# added by disable_macos_updates/ { next }
        /^# Timestamp:.*disable_macos_updates/ { next }
        /^# Remove with:.*restore_macos_updates/ { next }
        /^# ={20,}/ { next }
        { print }
    ' /etc/hosts | awk '
        /^[[:space:]]*$/ { blank++; next }
        { for(i=0; i<blank; i++) print ""; blank=0; print }
        END { if (NR > 0) printf "" }
    ' > "${TMP_HOSTS}"

    # Ensure permissions before atomic move
    chmod 644 "${TMP_HOSTS}"
    chown root:wheel "${TMP_HOSTS}" 2>/dev/null || true

    mv -f -- "${TMP_HOSTS}" /etc/hosts
    chmod 644 /etc/hosts
    TMP_HOSTS=""

    ok "  Removed ${_count} managed sinkhole entries from /etc/hosts."
fi

# ==============================================================================
# STEP 3: RELOAD SOFTWAREUPDATE LAUNCH DAEMONS
# ==============================================================================

step "3/5  Reloading SoftwareUpdate launch daemons..."

for _daemon in "${UPDATE_DAEMONS[@]}"; do
    _reloaded=false
    _plist="/Library/LaunchDaemons/${_daemon}.plist"
    _sys_plist="/System/Library/LaunchDaemons/${_daemon}.plist"

    # 1. Check local /Library plist
    if [[ -f "${_plist}" ]]; then
        if launchctl bootstrap system "${_plist}" 2>/dev/null; then
            ok "  Loaded: ${_daemon} (library plist)"
            _reloaded=true
        fi
    fi

    # 2. Check /System/Library plist
    if [[ "${_reloaded}" == false && -f "${_sys_plist}" ]]; then
        if launchctl bootstrap system "${_sys_plist}" 2>/dev/null; then
            ok "  Loaded: ${_daemon} (system plist)"
            _reloaded=true
        fi
    fi

    # 3. Modern service target kickstart if already bootstrapped/managed
    if [[ "${_reloaded}" == false ]]; then
        if launchctl kickstart -k "system/${_daemon}" 2>/dev/null; then
            ok "  Reloaded: ${_daemon} (service target)"
            _reloaded=true
        elif launchctl enable "system/${_daemon}" 2>/dev/null; then
            ok "  Enabled: ${_daemon} (service target)"
            _reloaded=true
        fi
    fi

    if [[ "${_reloaded}" == false ]]; then
        warn "  Could not reload (may be running or agent service): ${_daemon}"
    fi
done

ok "Launch daemon reload step complete."

# ==============================================================================
# STEP 4: FLUSH DNS CACHE
# ==============================================================================

step "4/5  Flushing DNS cache..."

dscacheutil -flushcache
killall -HUP mDNSResponder 2>/dev/null || true

ok "DNS cache flushed."

# ==============================================================================
# STEP 5: TRIGGER SOFTWARE UPDATE CHECK
# ==============================================================================

step "5/5  Triggering software update availability check..."

info "Running: softwareupdate --list  (this may take a moment...)"
softwareupdate --list 2>&1 | head -20 || true

# ==============================================================================
# VERIFICATION SUMMARY
# ==============================================================================

printf "\n"
printf "%s\n" "${C_GREEN}${C_BOLD}══════════════════════════════════════════════════════════════${C_RESET}"
printf "%s\n" "${C_GREEN}${C_BOLD}  ✔  macOS automatic updates RESTORED successfully!${C_RESET}"
printf "%s\n" "${C_GREEN}${C_BOLD}══════════════════════════════════════════════════════════════${C_RESET}"

printf "\n"
info "Current SoftwareUpdate settings:"
for _key in AutomaticCheckEnabled AutomaticDownload AutomaticallyInstallMacOSUpdates ConfigDataInstall CriticalUpdateInstall; do
    _val="$(defaults read /Library/Preferences/com.apple.SoftwareUpdate "${_key}" 2>/dev/null || echo "NOT_SET")"
    printf "    %-46s = %s\n" "${_key}" "${C_BOLD}${_val}${C_RESET}"
done

_commerce_val="$(defaults read /Library/Preferences/com.apple.commerce AutoUpdate 2>/dev/null || \
                 defaults read /Library/Preferences/com.apple.Commerce AutoUpdate 2>/dev/null || echo "NOT_SET")"
printf "    %-46s = %s\n" "App Store AutoUpdate (com.apple.commerce)" "${C_BOLD}${_commerce_val}${C_RESET}"

printf "\n"
info "/etc/hosts sinkhole check (should be 0 managed entries):"
_remaining="$(grep -c "${HOSTS_TAG}" /etc/hosts 2>/dev/null || true)"
_remaining="${_remaining:-0}"
if (( _remaining == 0 )); then
    ok "  No sinkhole entries remain in /etc/hosts. ✔"
else
    warn "  ${_remaining} managed entries still remain — inspect /etc/hosts manually."
fi

printf "\n"
ok "macOS software updates are now fully enabled."
info "You may see update notifications shortly."
printf "\n"
