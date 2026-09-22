# Documentation Notes: Architecture and Engineering Guidelines

## 1. System Philosophy & Bounds

**Disable-MacOS-Updates** provides a surgical, deterministic, and fully reversible mechanism to manage macOS automatic update subsystems.

### Core Bounds & Non-Negotiable Invariants
- **Zero Third-Party Binary Dependencies**: Uses strictly native macOS core utilities (`defaults`, `launchctl`, `dscacheutil`, `mDNSResponder`, `softwareupdate`, `awk`, `mktemp`, `grep`).
- **Strict POSIX / Bash 3.2+ Compatibility**: Compatible with the stock `/bin/bash` (v3.2.57) shipped with macOS Monterey (12) through macOS Tahoe (16), avoiding Bash 4+ / 5+ specific constructs (such as `declare -A`, `mapfile`, or `readarray`).
- **Complete Symmetrical Reversibility**: Any modification made by `disable_macos_updates.sh` is mirrored and deterministically undone by `restore_macos_updates.sh`.
- **Zero-Loss Baseline Retention**: Pristine baseline configurations (both `/etc/hosts` and `com.apple.SoftwareUpdate` preferences) are recorded to `/var/db/` on first execution with root-only (`0600`) permissions and are never overwritten by subsequent re-runs.

---

## 2. Shell Engineering & Defensive Hardening

Both scripts enforce strict defensive programming constructs:

```bash
set -Eeuo pipefail
IFS=$'\n\t'
```

### 2.1 Exception & Trap Handling
- **`ERR` Trap**: Catches unexpected non-zero exit codes immediately, outputting line number diagnostics before exiting.
- **`EXIT` Trap**: Cleans up all temporary files created under `$TMPDIR` via `rm -f -- "${TMP_HOSTS}"`, preventing orphan files in sandbox directories.
- **Signal Normalization**: Maps `HUP` (129), `INT` (130), and `TERM` (143) to standard Unix signal exit statuses.

### 2.2 Pipefail Hazard Mitigation
In bash scripts operating with `set -o pipefail`, pipelines exit with the status of the last non-zero command. Standard pipeline operations like:
```bash
grep -c "pattern" file || echo 0  # CRITICAL HAZARD: emits "0\n0" on no match!
```
are strictly prohibited. We utilize:
```bash
_count="$(grep -c "${HOSTS_TAG}" /etc/hosts 2>/dev/null || true)"
_count="${_count:-0}"
```
Furthermore, verification outputs utilize process substitution (`while IFS= read -r line; do ... done < <(command || true)`) rather than direct pipes to prevent pipeline failures from triggering premature `ERR` traps.

---

## 3. macOS Sandboxing, `$TMPDIR`, and Atomic Moves

### 3.1 Why `${TMPDIR:-/tmp}` Over `/tmp`?
macOS assigns each login session a private, sandboxed temporary folder located under `/var/folders/xx/xxxxxxx/T/`. Using a hardcoded `/tmp` path introduces several security and architectural issues:
1. **Multi-User Race Conditions**: `/tmp` is shared among all local users with `1777` permissions (sticky bit).
2. **Predictable Path Attacks**: Hardcoded naming conventions in `/tmp` allow symlink and TOCTOU (Time-of-Check to Time-of-Use) race exploits.
3. **Sandbox Violations**: macOS system daemons and sandbox profiles frequently restrict writes to global `/tmp`.

By enforcing:
```bash
TMP_HOSTS="$(mktemp "${TMPDIR:-/tmp}/hosts.XXXXXXXX")"
```
the script utilizes the kernel-enforced per-session temporary directory, while falling back gracefully to `/tmp` if `$TMPDIR` is unset.

### 3.2 Atomic Replacement via `rename(2)`
To prevent unprivileged processes or DNS resolvers from reading incomplete or corrupted `/etc/hosts` configurations:
1. The new hosts configuration is written entirely to the temporary file.
2. Permissions (`0644`) and ownership (`root:wheel`) are explicitly configured on the temporary file **before** moving it into place.
3. The atomic POSIX `rename(2)` syscall is invoked via `mv -f -- "${TMP_HOSTS}" /etc/hosts`.

---

## 4. AWK Parsing & Regex Invariants on Darwin (BSD)

macOS ships with standard BSD `awk` (not GNU `gawk`). There is an important syntactic difference between Basic Regular Expressions (BRE) and Extended Regular Expressions (ERE) regarding curly braces:

- In **ERE** (used by awk patterns `/pattern/`), `{m,n}` denotes an interval quantifier.
- Escaping braces with backslashes (`\{m,n\}`) in ERE turns them into **literal characters**.
- Consequently, `/^# =\{20,\}/` matches `# =` followed literally by `{20,}`, which will **never** match a horizontal separator line `# ====================`.
- The invariant form is:
  ```awk
  /^# ={20,}/ { next }
  ```
  which cleanly matches 20 or more consecutive `=` characters following `# `.

---

## 5. Modern `launchctl` Service Architecture

macOS 11 (Big Sur) through macOS 16 (Tahoe) deprecated legacy `launchctl load` / `launchctl unload` commands in favor of domain-targeted subcommands (`bootstrap`, `bootout`, `kickstart`, `enable`, `disable`).

### 5.1 Service Target Matrix
Services are addressed via domain target format `system/<service-label>`:
- `com.apple.softwareupdated`
- `com.apple.mobile.softwareupdated`
- `com.apple.InstallAssistantService`
- `com.apple.storedownloadd`
- `com.apple.storekitagentd`
- `com.apple.commerce`

### 5.2 Plist Resolution Order
The script searches both local and system daemon definitions:
1. `/Library/LaunchDaemons/${_daemon}.plist`
2. `/System/Library/LaunchDaemons/${_daemon}.plist`
3. Direct service domain inspection via `launchctl kickstart -k "system/${_daemon}"` and `launchctl bootout "system/${_daemon}"`.

---

## 6. Symmetrical Tagging & Surgical Removal

To guarantee that `restore_macos_updates.sh` removes **only** lines injected by `disable_macos_updates.sh`, every injected line (including headers, timestamps, comments, and domain entries) is suffixed with:
```text
# disable_macos_updates:managed
```
During restoration, the awk filter checks `index($0, tag)` to delete all managed lines in a single pass without modifying any user-defined or third-party `/etc/hosts` entries.
