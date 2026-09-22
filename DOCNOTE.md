# Documentation Notes: Architecture and Engineering Guidelines

**Disable-MacOS-Updates Suite — v1.2.0**<br>
_Architectural Decision Records (ADR), System Philosophy, and Low-Level Darwin Invariants_

---

## 1. System Philosophy & Engineering Bounds

**Disable-MacOS-Updates** provides a reversible mechanism to manage macOS automatic software update subsystems across workstations, audio rigs (DAW), and render machines.

### Core Bounds & Non-Negotiable Invariants

- **Zero Third-Party Binary Dependencies**: Operates strictly with native Darwin core utilities (`defaults`, `launchctl`, `dscacheutil`, `mDNSResponder`, `softwareupdate`, `awk`, `mktemp`, `grep`, `chmod`, `chown`, `mv`). No Python, Node.js, Homebrew, or external runtimes are permitted.
- **Strict POSIX / Bash 3.2+ Compatibility**: Strictly compatible with Apple's stock `/bin/bash` (v3.2.57) shipped with macOS Monterey (12) through macOS Golden Gate (27). Bash 4+ or 5+ specific constructs (e.g., associative arrays `declare -A`, `mapfile`, `readarray`) are forbidden to ensure zero-installation execution out of the box.
- **Complete Symmetrical Reversibility**: Every modification executed by `disable_macos_updates.sh` is mirrored and undone by `restore_macos_updates.sh`.
- **Zero-Loss Baseline Retention**: Pristine baseline configurations (`/etc/hosts` and `com.apple.SoftwareUpdate` preferences) are recorded to `/var/db/` on first execution with root-only (`0600`) permissions and are never overwritten by subsequent runs.
- **SIP & SSV Non-Invasive Compliance**: Operates completely within user-space and writable `/Library` / `/etc` domains without requiring System Integrity Protection (SIP) disabling, Sealed System Volume (SSV) breakage, or custom kernel extensions (KEXTs).

---

## 2. Architectural Decision Records (ADRs)

### ADR-001: Pure Bash 3.2+ and POSIX Tooling vs. Compiled Binaries

- **Context**: Managing macOS updates can be implemented via Swift/Objective-C binaries, Go/Rust CLI tools, or shell scripts.
- **Decision**: Implement the suite exclusively in hardened, defensive Bash 3.2+ script compatible with macOS stock `/bin/bash`.
- **Rationale**:
  1. Compiled binaries require code signing, notarization, and architecture-specific slices (Universal 2 / `x86_64` / `arm64`), introducing gatekeeper friction and binary maintenance overhead.
  2. Pure shell scripts provide complete visibility and audibility for system administrators.
  3. Stock `/bin/bash` is guaranteed to be present on macOS Monterey (12) through Golden Gate (27) without prerequisites.

### ADR-002: Dual-Layer Approach (Defaults Management + DNS Loopback Sinkholing)

- **Context**: Toggling `defaults write /Library/Preferences/com.apple.SoftwareUpdate AutomaticCheckEnabled -bool false` is often insufficient on modern macOS. Background catalog indexing daemons (`softwareupdated`) and XPC background services can trigger notifications or download metadata regardless of preference toggles.
- **Decision**: Combine plist preference toggles with an `/etc/hosts` loopback sinkhole (`127.0.0.1`) targeting Apple's software distribution endpoints.
- **Rationale**:
  1. If a system daemon ignores a defaults flag, its network requests to `swscan.apple.com` or `swcdn.apple.com` immediately fail locally at the TCP socket layer (connection refused).
  2. App Store manual app installations and iCloud services remain unaffected because they resolve through independent domains (`apps.apple.com`, `itunes.apple.com`).

### ADR-003: Tagged Records and Single-Pass AWK Stream Processing

- **Context**: In modifying `/etc/hosts`, naive appending or `sed -i` operations can corrupt user-defined entries, fail on edge cases, or leave orphaned comment blocks upon rollback.
- **Decision**: Tag every injected line with `# disable_macos_updates:managed` and parse with a single-pass BSD `awk` script.
- **Rationale**:
  1. Tagging allows `restore_macos_updates.sh` to cleanly remove only managed entries without touching any developer or third-party records.
  2. Single-pass `awk` stream processing avoids multi-step temporary file churn and pipeline race conditions.

### ADR-004: Kernel-Enforced Per-Session `$TMPDIR` Sandboxing & Atomic Moves

- **Context**: Writing temporary files directly to `/tmp` exposes scripts to symlink attacks, race hazards, and permission collisions in multi-user environments.
- **Decision**: Always generate temporary files via `mktemp "${TMPDIR:-/tmp}/hosts.XXXXXXXX"` and commit changes using POSIX `rename(2)` (`mv -f`).
- **Rationale**:
  1. macOS assigns each user session a private, isolated directory under `/var/folders/xx/xxxxxxx/T/`, preventing cross-user path sniffing.
  2. Atomic replacement via `mv -f` ensures that system resolvers reading `/etc/hosts` never encounter a partial, empty, or half-written file.

### ADR-005: Modern `launchctl` Service Domain Addressing

- **Context**: Legacy `launchctl load` and `launchctl unload` commands have been deprecated since macOS 11 Big Sur and produce warnings or failures in modern Darwin releases.
- **Decision**: Address services using modern target syntax (`system/<service-label>`) and prefer `bootout` / `bootstrap` / `kickstart`.
- **Rationale**: Ensures robust daemon state transitions across macOS Monterey (12), Ventura (13), Sonoma (14), Sequoia (15), Tahoe (26), and Golden Gate (27).

### ADR-006: Hardware Architecture Divergence & Apple Silicon Support

- **Context**: macOS has transitioned completely from Intel x86_64 to Apple Silicon (M1, M2, M3, M4, M5, M6). macOS 26 (Tahoe) represents the final OS release supporting Intel x86_64, while macOS 27 (Golden Gate) is Apple Silicon exclusive.
- **Decision**: Explicitly detect hardware architecture via `uname -m`, validate Apple Silicon generations (M1–M6) and Intel configurations, and document compatibility parameters across the suite.
- **Rationale**: Provides clarity to system administrators managing heterogeneous hardware fleets during the final phases of the Apple Silicon architecture transition.

---

## 3. Shell Engineering & Defensive Hardening

Both scripts enforce strict defensive programming standards:

```bash
set -Eeuo pipefail
IFS=$'\n\t'
```

### 3.1 Exception & Trap Handling

- **`ERR` Trap**: Catches unexpected non-zero exit codes immediately, logging the exact source file and line number before safe exit.
- **`EXIT` Trap**: Guarantees that any temporary file created under `$TMPDIR` is unlinked (`rm -f -- "${TMP_HOSTS}"`), eliminating file debris upon script termination (whether normal or interrupted).
- **Signal Normalization**: Captures `HUP` (129), `INT` (130), and `TERM` (143), cleans up active locks/temporaries, and restores terminal cursor and formatting.

### 3.2 Pipefail Hazard Mitigation

In bash scripts operating with `set -o pipefail`, pipelines exit with the status of the rightmost non-zero command. Standard pipeline operations such as:

```bash
# HAZARDOUS: grep -c returns 1 on zero matches, producing "0\n0"
count="$(grep -c "pattern" file || echo 0)"
```

cause bash arithmetic evaluations `(( count == 0 ))` to crash. The suite mitigates this via:

```bash
_count="$(grep -c "${HOSTS_TAG}" /etc/hosts 2>/dev/null || true)"
_count="${_count:-0}"
```

Furthermore, verification outputs utilize process substitution rather than direct pipes:

```bash
while IFS= read -r _line; do
    [[ -z "${_line}" ]] && continue
    printf "    %s\n" "${_line}"
done < <(grep -v '^#' "${PREFS_BACKUP}" 2>/dev/null | grep '=' 2>/dev/null || true)
```

This ensures that premature pipe closure (e.g. from `head`) does not propagate `SIGPIPE` (exit code 141) into an unexpected script abortion.

---

## 4. macOS Sandboxing, `$TMPDIR`, and Atomic Moves

### 4.1 Why `${TMPDIR:-/tmp}` Over Hardcoded `/tmp`?

macOS assigns each login session a private, sandboxed temporary directory located under `/var/folders/xx/xxxxxxx/T/`. Using a hardcoded `/tmp` path introduces several security and architectural issues:

1. **Multi-User Race Conditions**: `/tmp` is shared among all local users with `1777` permissions (sticky bit).
2. **Predictable Path Attacks**: Hardcoded naming conventions in `/tmp` allow symlink and TOCTOU (Time-of-Check to Time-of-Use) race exploits.
3. **Sandbox Violations**: macOS system daemons and sandbox profiles frequently restrict writes to global `/tmp`.

By enforcing:

```bash
TMP_HOSTS="$(mktemp "${TMPDIR:-/tmp}/hosts.XXXXXXXX")"
```

the script utilizes the kernel-enforced per-session temporary directory, while falling back gracefully to `/tmp` if `$TMPDIR` is unset.

### 4.2 Atomic Replacement via `rename(2)`

To prevent unprivileged processes or DNS resolvers from reading incomplete or corrupted `/etc/hosts` configurations:

1. The new hosts configuration is written entirely to the temporary file.
2. Permissions (`0644`) and ownership (`root:wheel`) are explicitly configured on the temporary file **before** moving it into place.
3. The atomic POSIX `rename(2)` syscall is invoked via `mv -f -- "${TMP_HOSTS}" /etc/hosts`.

---

## 5. AWK Parsing & Regex Invariants on Darwin (BSD)

macOS ships with standard BSD `awk` (not GNU `gawk`). There is an important syntactic difference between Basic Regular Expressions (BRE) and Extended Regular Expressions (ERE) regarding curly braces:

- In **ERE** (used by awk patterns `/pattern/`), `{m,n}` denotes an interval quantifier.
- Escaping braces with backslashes (`\{m,n\}`) in ERE turns them into **literal characters**.
- Consequently, `/^# =\{20,\}/` matches `# =` followed literally by `{20,}`, which will **never** match a horizontal separator line `# ====================`.
- The invariant form is:

  ```awk
  /^# ={20,}/ { next }
  ```

  which cleanly matches 20 or more consecutive `=` characters following `#`.

---

## 6. Modern `launchctl` Service Architecture

macOS 11 (Big Sur) through macOS 27 (Golden Gate) deprecated legacy `launchctl load` / `launchctl unload` commands in favor of domain-targeted subcommands (`bootstrap`, `bootout`, `kickstart`, `enable`, `disable`).

### 6.1 Service Target Matrix

Services are addressed via domain target format `system/<service-label>`:

- `com.apple.softwareupdated`: Primary update orchestrator and catalog fetcher.
- `com.apple.mobile.softwareupdated`: Mobile software update agent for companion and universal assets.
- `com.apple.InstallAssistantService`: Package payload verification and pre-installation assistant.
- `com.apple.storedownloadd`: App Store background asset download manager.
- `com.apple.storekitagentd`: StoreKit transaction helper.
- `com.apple.commerce`: Commerce and auto-update daemon.

### 6.2 Plist Resolution Order

The script searches both local and system daemon definitions:

1. `/Library/LaunchDaemons/${_daemon}.plist`
2. `/System/Library/LaunchDaemons/${_daemon}.plist`
3. Direct service domain inspection via `launchctl kickstart -k "system/${_daemon}"` and `launchctl bootout "system/${_daemon}"`.

---

## 7. Tagged Records & Clean Removal

To guarantee that `restore_macos_updates.sh` removes **only** lines injected by `disable_macos_updates.sh`, every injected line (including headers, timestamps, comments, and domain entries) is suffixed with:

```text
# disable_macos_updates:managed
```

During restoration, the awk filter checks `index($0, tag)` to delete all managed lines in a single pass without modifying any user-defined or third-party `/etc/hosts` entries.

---

## 8. Author & Contact Identification Specification

To ensure clear identification and maintainer contact, both scripts feature standardized headers detailing:

- **Script Name & Semantic Version**: `1.2.0`
- **Creation (`2026-09-14`) & Modification (`2026-09-22`) Timestamps**
- **Author**: `Harry Dertin Sutisna Alsyundawy (@alsyundawy)`
- **Email**: `alsyundawy@gmail.com`
- **Official Website**: `https://www.alsyundawy.com`
- **GitHub**: `https://github.com/alsyundawy`
- **Twitter / X**: `https://x.com/alsyundawy (@alsyundawy)`
- **Organization**: `WWW.ALSYUNDAWY.NET`
- **Location**: `DKI Jakarta, Indonesia`
