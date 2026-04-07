# v2-modular Architecture Overview

This document describes the overall architecture of the v2-modular bootstrap system. For module-specific details, refer to the ARCH.md file in each module directory (e.g., `modules/sway/ARCH.md`).

## 1. System Overview

The v2-modular system bootstraps a Fedora 43 + Sway (Wayland) workstation. It is structured as a collection of self-contained, reusable modules that apply configuration in a deterministic order.

**Key principles:**

- **Declarative:** System state is defined via YAML manifests and INI profiles, not imperative scripts.
- **Modular:** Each module is isolated with its own directory, manifest, configuration, and implementation.
- **Idempotent:** All modules can be safely re-run without causing duplicate changes or side effects.
- **Composable:** Modules declare their dependencies and capabilities; the orchestrator validates and orders them.
- **Dry-run first:** The default mode previews changes without applying them; `--apply` is required to execute.

## 2. Module Contract

Every module directory contains:

1. **`manifest.yaml`** — Metadata describing the module
2. **`module.sh`** — Implementation exporting five standard functions

### Module Functions

Each `module.sh` implements this interface:

```bash
MODULE::init [args...]      # Read PROFILE_* vars, parse flags, cache state once (called before any check)
MODULE::check [args...]     # Return 0 if changes needed, 1 if up-to-date
MODULE::preview [args...]   # Print what would change (read-only, no side effects)
MODULE::apply [args...]     # Execute changes (idempotent, safe to re-run)
MODULE::status [args...]    # Return one-line current state summary
```

**Naming convention:** Functions use the actual module name. For module `modules/sway/`, implement `sway::init()`, `sway::check()`, etc.

**Orchestrator behavior:**

1. Sets `MODULE_DIR` to the module's absolute path
2. Sources `module.sh`
3. Calls `MODULE::init` (once per run)
4. Calls `MODULE::check` to determine if changes are needed
5. Calls `MODULE::preview` (dry-run) or `MODULE::apply` (if `--apply` flag is set)

Note: `MODULE::status` is defined by all modules but is not called by the orchestrator automatically. It is available for direct invocation.

### Symlink Declarations

Modules that own config files declare a symlink map array in `module.sh`, named `_<MODULE>_SYMLINK_MAP`:

```bash
_SWAY_SYMLINK_MAP=(
    "config/waybar/config|$HOME/.config/waybar/config"
    "config/kanshi/config|$HOME/.config/kanshi/config"
)
```

The shell module adds a third pipe-delimited field for conditional deployment (`always`, `fish`, `sway`). The symlink map is consulted during `apply()` to deploy files from the module's `config/` directory into the user's `~/.config/`.

### Template Declarations

Modules with config files that contain `{{PLACEHOLDER}}` syntax declare a template map array, named `_<MODULE>_TEMPLATE_MAP`:

```bash
_SWAY_TEMPLATE_MAP=(
    "config/sway/config"
    "config/waybar/style.css"
    "config/dunst/dunstrc"
    "config/swaylock/config"
)
```

Template files are rendered to `~/.local/share/v2-modular/rendered/<module>/` during `apply()`. The resulting symlinks point to the rendered output, not the repo source. Non-templated files remain in `_SYMLINK_MAP` and are symlinked directly from the repo. See Section 7 for the full template rendering pipeline.

## 3. Manifest Schema

Each module's `manifest.yaml` declares:

```yaml
name: <string>              # Module identifier (must match directory name)
description: <string>       # Human-readable purpose
version: <semver>           # Module version (e.g., 1.0.0)
order: <integer>            # Execution priority (lower = earlier in sequence)
condition: <string>         # "always", "sway", "fish", or other valid conditions
requires:                   # List of module names that must run before this one
  - <module-name>
provides:                   # List of capabilities this module makes available
  - <capability-name>
```

**Example:**

```yaml
name: sway
description: Sway window manager, Waybar, Kanshi, Dunst, Swaylock config
version: 1.0.0
order: 40
condition: sway
requires:
  - packages
  - shell
provides:
  - sway-config
  - waybar-config
  - dunst-config
```

### Execution Order

Modules are sorted by the `order` field (lower numbers first). Common ordering:

```
order: 10   → system (hostname, keyboard, GPU, firewall)
order: 20   → packages (system + user packages, repos, Flatpaks, DevOps)
order: 30   → shell (env vars, bash, fish, kitty, tmux)
order: 40   → sway (only if condition matches)
order: 50   → theme (icon theme, SDDM, GTK/Qt/KDE config rendering)
```

### Conditions

- `always` — Run unconditionally
- `sway` — Run only if Sway is installed/enabled
- `fish` — Run only if Fish shell is installed
- Other custom conditions evaluated by orchestrator

## 4. Execution Flow

### Startup

```
./setup [flags]
  ├─ source core/*.sh (common, config, colors, links, manifest, templates)
  ├─ load profiles (config.default.ini + config.local.ini overlay)
  ├─ load_all_presets (read colors/*.conf into COLOR_PRESETS)
  ├─ load_accent (resolve ACCENT_* variables from active preset)
  ├─ discover_modules (scan modules/*/manifest.yaml)
  ├─ sort by order field
  ├─ validate requires (warn if dependency missing)
  └─ enter main loop
```

Accent loading happens at startup so that `ACCENT_*` variables are available to all modules regardless of execution order (e.g. sway at order 40 needs them before theme at order 50).

### Per-Module Loop

For each module in sorted order:

```
1. Evaluate condition (skip if false)
2. Set MODULE_DIR = /path/to/module
3. Source module.sh
4. Call MODULE::init (parse flags, cache state)
5. Call MODULE::check
   └─ If check returns 0 (changes needed):
       ├─ If --apply:
       │   └─ Call MODULE::apply (execute)
       └─ If --dry-run (default):
           └─ Call MODULE::preview (print summary)
```

### Exit

```
If dry-run: print "Dry run complete. Pass --apply to execute all changes."
Exit 0 on success; set -euo pipefail aborts on any error
```

## 5. Directory Structure

```
systems/                      Repository root
│
├── setup                     Orchestrator entry point (bash script)
│
├── core/                     Shared libraries (sourced by setup and modules)
│   ├── common.sh             Logging, preflight, pkg_install, error handling
│   ├── config.sh             INI profile parser (load_profile, profile_get)
│   ├── colors.sh             Color preset loader (load_all_presets, load_accent)
│   ├── templates.sh          Template renderer (render_template, render_module_templates)
│   ├── links.sh              Symlink helpers (link_file, check_link, ensure_local_override)
│   └── manifest.sh           YAML manifest parser (parse_manifest, discover_modules)
│
├── modules/                  Module implementations (each is self-contained)
│   ├── system/               System config (hostname, keyboard, firewall)
│   │   ├── manifest.yaml     Metadata and dependencies
│   │   ├── module.sh         Implementation (system::init/check/preview/apply/status)
│   │   └── config/           Config files (if any)
│   ├── packages/             Package management (system + user pkgs, repos, Flatpaks)
│   │   ├── packages.conf     Package lists (sections gated by profile toggles)
│   ├── shell/                Shell env, bash, fish, kitty, tmux configs
│   ├── sway/                 Sway window manager config (with ARCH.md)
│   └── theme/                Theming (GTK/Qt/KDE + accent colors)
│
├── config.default.ini        Base profile — machine settings (checked in)
├── config.local.ini          Per-machine overrides (gitignored)
│
├── colors/                   Color preset definitions (one file per preset)
│   ├── green.conf            Green accent preset
│   ├── orange.conf           Orange accent preset
│   └── blue.conf             Blue accent preset
│
├── documentation/            Documentation
│   ├── ARCH.md               This file (top-level overview)
│   └── (module ARCH.md files in their respective directories)
│
├── tests/                    Container-based smoke tests (Podman)
│   ├── Containerfile         Test environment definition (Fedora 43)
│   └── smoke.sh              Integration test runner (~27 test cases)
│
└── (runtime directories, not in repo)
    └── ~/.local/share/v2-modular/
        └── rendered/         Template render output (symlink targets)
            ├── sway/         Rendered sway/waybar/dunst/swaylock configs
            ├── theme/        Rendered gtk/kde/sddm configs
            └── shell/        Rendered kitty/tmux/fish/bash configs
```

## 6. Profile System

Profiles are **INI-format configuration files** at the repo root that define per-machine settings. The system uses a two-layer overlay:

1. **`config.default.ini`** — Checked in; defines defaults for all keys
2. **`config.local.ini`** — Gitignored; overrides defaults on each machine

### Parsing

`core/config.sh` provides `load_profile()` and `profile_get()`:

```bash
load_profile /path/to/profile.conf
value=$(profile_get section key)
```

### Variable Naming

Profile keys are exported as bash variables in the form `PROFILE_SECTION_KEY`. For example:

```ini
[system]
hostname = myworkstation
keyboard_layout = us
```

becomes:

```bash
PROFILE_SYSTEM_HOSTNAME="myworkstation"
PROFILE_SYSTEM_KEYBOARD_LAYOUT="us"
```

### Sections

```ini
[system]
hostname =
keyboard_layout =
sway_spin = auto
firewalld = true
bluetooth = true
tuned = true

[packages]
dnf_update = true
rpm_fusion = true
codec_swaps = true
flatpak = true
cli_tools = true
security = true
rocm = false
desktop_toolkit = qt
devops = false
kvm = false
protonvpn = false
firefox_wayland = true

[theme]
accent = green                  # Color preset: green, orange, blue
gtk_theme = Adwaita-dark
icon_theme = Tela
cursor_theme = Adwaita
tela_icons = true
sddm_theme = stock

[shell]
docker_alias = true
qt_env = true
unset_ssh_askpass = true
```

### Package Registry (packages.conf)

The `packages` module uses a separate config file, `modules/packages/packages.conf`, as the single source of truth for all managed packages. It uses an INI-like format with a qualifier convention that gates sections by profile toggles:

```
[name]              Always-installed RPM packages
[name:qualifier]    Gated by PROFILE_PACKAGES_<QUALIFIER> boolean
[name:gtk]          Installed only when desktop_toolkit = gtk
[name:qt]           Installed only when desktop_toolkit = qt
[flatpak:name]      Flatpak apps (gated by packages.flatpak)
[sway-extra]        Special: installed only on non-Sway-Spin systems
```

**Qualifier resolution** (in `_pkg_get_rpm_targets`):

1. No qualifier → install unconditionally
2. `gtk` or `qt` → compare against `PROFILE_PACKAGES_DESKTOP_TOOLKIT`
3. Any other qualifier → check `PROFILE_PACKAGES_<qualifier>` (uppercased) is `true`
4. `flatpak:*` sections → handled separately by `_pkg_get_flatpak_targets`
5. `sway-extra` → skipped if `SWAY_SPIN == true` (packages already present on Sway Spin)

**Current sections:**

| Section | Qualifier | Contents |
|---------|-----------|----------|
| `[sway]` | none | Core system packages (fish, kitty, podman, bemenu, plasma-integration, etc.) |
| `[sway-extra]` | special | Sway compositor stack (sway, waybar, kanshi, swayidle, swaylock, etc.) |
| `[cli:cli_tools]` | `cli_tools` | CLI tools (btop, fzf, ripgrep, tmux, etc.) |
| `[security:security]` | `security` | YubiKey support (pam-u2f, yubikey-manager) |
| `[rocm:rocm]` | `rocm` | AMD GPU compute (ROCm runtime, SMI, OpenCL) |
| `[browsers]` | none | Firefox, Brave |
| `[mesa]` | none | Mesa GPU drivers and VA-API |
| `[misc]` | none | KeePassXC, Nextcloud client |
| `[kvm:kvm]` | `kvm` | Virtualization (libvirt, qemu-kvm, virt-manager) |
| `[desktop:gtk]` | `gtk` | GTK desktop apps (Thunar, Evince, Celluloid, etc.) |
| `[desktop:qt]` | `qt` | Qt desktop apps (Dolphin, Okular, Gwenview, etc.) |
| `[devops:devops]` | `devops` | Ansible, Helm, kind, kubectl, podman-compose |
| `[flatpak:audio]` | flatpak | EasyEffects |
| `[flatpak:comm]` | flatpak | Slack, Signal |

Adding a package is a one-line edit to the appropriate section — no code changes needed.

### External Repository Setup

The packages module configures several third-party repositories before installing packages. Each setup function is idempotent (skips if repo file already exists):

| Repository | Profile gate | Version handling |
|------------|-------------|------------------|
| RPM Fusion (free + nonfree) | `rpm_fusion` | Auto-detects Fedora version via `rpm -E %fedora` |
| Brave browser | Presence of `brave-browser` in `[browsers]` | Static URL |
| HashiCorp | `devops` | `find_fedora_version` probes for compatible release; pins version via sed if needed |
| Kubernetes | `devops` | Static version (`v1.34`, overridable via `K8S_VERSION` env) |
| ROCm / AMDGPU | `rocm` + discrete AMD GPU | RHEL 9.5 compat repos (overridable via `ROCM_RHEL_VER` env) |
| ProtonVPN | `protonvpn` | `find_fedora_version` probes per-version repo URL |

**`find_fedora_version`** (`core/common.sh`): Probes a URL template starting from the current Fedora version and falling back up to 3 versions. Used by HashiCorp and ProtonVPN to handle repo availability lag when Fedora releases a new version.

### Codec Swaps

When `codec_swaps = true`, the packages module replaces limited-functionality codec packages with their full RPM Fusion equivalents:

1. Enables the Cisco OpenH264 repository
2. `ffmpeg-free` → `ffmpeg` (via `dnf swap --allowerasing`)
3. `mesa-va-drivers` → `mesa-va-drivers-freeworld` (via `dnf swap --allowerasing`)

These swaps are conditional — they only run if the old package is installed and the new one is not.

## 7. Color System

The theming system uses **data-driven color presets** and a **template rendering pipeline** to apply accent colors to config files without mutating source files in the repository.

### Preset Format

Each file in `colors/` defines a name and 6 color values:

```conf
# colors/green.conf
name = green
primary = #88DD00
dim = #557700
dark = #2A3B00
bright = #8BE235
secondary = #ffaa00
ansi = 92
```

### Adding a Preset

1. Create `colors/<name>.conf` with the name and 6 color values
2. Update `config.default.ini` to reference it:
   ```ini
   [theme]
   accent = <name>
   ```
3. Users can override via `config.local.ini`

### Template Rendering Pipeline

Config files in the repository are **templates** that use `{{PLACEHOLDER}}` syntax for dynamic values. A rendering step in each module's `apply()` substitutes placeholders with resolved values and writes the output to a staging directory. Symlinks in `~/.config/` point to the rendered output, not the repo source files.

This design keeps the git working tree clean — `./setup --apply` never modifies tracked files.

**Rendering flow:**

```
Template (repo source)              Rendered (staging)                    Live (~/.config/)
modules/sway/config/sway/config  →  rendered/sway/sway/config          ←  ~/.config/sway/config
modules/sway/config/kanshi/config  ─────────────────────────────────────←  ~/.config/kanshi/config  (direct, no template)
```

**Rendering location:** `~/.local/share/v2-modular/rendered/<module>/` — follows XDG convention, per-module isolation.

**Rendering properties:**
- Single-pass sed with a fixed variable list (no multi-pass, no color matching)
- Atomic writes: renders to `.tmp`, then `mv` into place
- Validation: unresolved `{{...}}` placeholders after rendering cause a fatal error
- Idempotent: `cmp -s` skips the write if rendered output is identical to existing file

### Placeholder Reference

**Accent color placeholders:**

| Placeholder | Format | Example |
|---|---|---|
| `{{ACCENT_NAME}}` | Preset name | `green` |
| `{{ACCENT_PRIMARY}}` | `#hex` | `#88DD00` |
| `{{ACCENT_DIM}}` | `#hex` | `#557700` |
| `{{ACCENT_DARK}}` | `#hex` | `#2A3B00` |
| `{{ACCENT_BRIGHT}}` | `#hex` | `#8BE235` |
| `{{ACCENT_SECONDARY}}` | `#hex` | `#ffaa00` |
| `{{ACCENT_ANSI}}` | Number | `92` |
| `{{ACCENT_PRIMARY_BARE}}` | `hex` (no `#`) | `88DD00` |
| `{{ACCENT_DIM_BARE}}` | `hex` (no `#`) | `557700` |
| `{{ACCENT_DARK_BARE}}` | `hex` (no `#`) | `2A3B00` |
| `{{ACCENT_BRIGHT_BARE}}` | `hex` (no `#`) | `8BE235` |
| `{{ACCENT_SECONDARY_BARE}}` | `hex` (no `#`) | `ffaa00` |

**Profile placeholders:**

| Placeholder | Source | Example |
|---|---|---|
| `{{PROFILE_THEME_GTK_THEME}}` | config.*.ini | `Adwaita-dark` |
| `{{PROFILE_THEME_CURSOR_THEME}}` | config.*.ini | `Adwaita` |
| `{{PROFILE_THEME_ICON_THEME}}` | Computed: base + accent | `Tela-green` |
| `{{PROFILE_SYSTEM_KEYBOARD_LAYOUT}}` | config.*.ini | `us` |

### Template Examples

**Sway border colors:**
```
client.focused          {{ACCENT_PRIMARY}} #555754 #FFFFFF {{ACCENT_PRIMARY}} {{ACCENT_PRIMARY}}
client.focused_inactive {{ACCENT_DIM}} #2E3537 #FFFFFF {{ACCENT_DIM}} {{ACCENT_DIM}}
```

**Swaylock (bare hex, no `#` prefix):**
```
ring-color={{ACCENT_PRIMARY_BARE}}
key-hl-color={{ACCENT_PRIMARY_BARE}}
```

**Sway gsettings (profile-driven values):**
```
gsettings set org.gnome.desktop.interface gtk-theme '{{PROFILE_THEME_GTK_THEME}}'
gsettings set org.gnome.desktop.interface icon-theme '{{PROFILE_THEME_ICON_THEME}}'
```

### Which Files Are Templates

Each module declares its template files in a `_<MODULE>_TEMPLATE_MAP` array. Only files with `{{...}}` placeholders need to be in this array — non-templated config files continue to use direct symlinks via `_<MODULE>_SYMLINK_MAP`.

When adding a new config file that uses accent colors or profile values:

1. Use `{{PLACEHOLDER}}` syntax for dynamic values
2. Add the file's relative path to the module's `_TEMPLATE_MAP` array
3. The module's `apply()` renders it via `render_module_templates`

## 8. Shell Environment

The `shell` module generates `~/.config/shell/bootstrap-env.sh`, which is sourced by `.bashrc`. The file is rebuilt on every run from `_shell_generate_env()` and compared with `cmp -s`; it is only written when content changes. Each block is gated by a `[shell]` profile toggle:

- **Docker alias** (`docker_alias`): `alias docker=podman` and `KIND_EXPERIMENTAL_PROVIDER=podman`
- **Qt theme variables** (`qt_env`): `QT_QPA_PLATFORMTHEME=kde`, `QT_STYLE_OVERRIDE=Breeze`
- **SSH_ASKPASS unset** (`unset_ssh_askpass`): Clears `SSH_ASKPASS` to fix git HTTPS credential prompts broken by `kde-openssh-askpass.sh`

Disabling a toggle in the profile removes the corresponding block from the generated file on the next run (see Section 11, Generated File Regeneration).

### .bashrc Integration

The shell module appends three guarded source lines to `~/.bashrc` (idempotent — each line is checked with `grep -qF` before appending):

```bash
[[ -f "$HOME/.config/shell/bootstrap-env.sh" ]] && source "$HOME/.config/shell/bootstrap-env.sh"
[[ -f "$HOME/.config/shell/prompt.sh" ]]        && source "$HOME/.config/shell/prompt.sh"
[[ -f "$HOME/.config/shell/completions.sh" ]]   && source "$HOME/.config/shell/completions.sh"
```

The `$HOME` variable is single-quoted in the module source — it expands at shell startup, not at install time.

### Local Override Files

Modules create per-machine override files on first run. These are never overwritten by subsequent runs, preserving user customizations:

| File | Module | Condition |
|------|--------|-----------|
| `~/.config/fish/config.local.fish` | shell | fish installed |
| `~/.config/kitty/config.local` | shell | always |
| `~/.config/tmux/local.conf` | shell | always |
| `~/.config/sway/config.local` | sway | sway condition |
| `~/.config/dunst/dunstrc.local` | sway | sway condition |

The sway config includes its local override via `include ~/.config/sway/config.local`.

## 9. System Detection

The `system` module (order 10) runs first and detects hardware and environment state used by downstream modules.

### GPU Detection

`detect_gpu()` (`core/common.sh`) scans `lspci` output for `VGA.*AMD.*Navi` or `VGA.*AMD.*RDNA` patterns. If found, sets `_HAS_DISCRETE_AMD_GPU=true`.

**Downstream effects:**

| Consumer | Behavior when GPU detected |
|----------|---------------------------|
| `system` module | Adds user to `video` and `render` groups via `usermod -aG` |
| `packages` module | Enables ROCm repo setup (if `rocm = true` in profile) |

If no discrete AMD GPU is found, GPU group setup is skipped and ROCm is disabled regardless of profile setting.

### Sway Spin Mode Detection

`detect_mode()` (`core/common.sh`) determines whether the system is a Fedora Sway Spin (Sway packages pre-installed) or base Fedora (full Sway stack needs installing). This is a **tri-state** controlled by `sway_spin` in the `[system]` profile section:

| Value | Behavior |
|-------|----------|
| `true` | Force Sway Spin mode — assume core Sway packages are present |
| `false` | Force base Fedora mode — install full Sway stack |
| `auto` (default) | Read cached result from `~/.config/shell/.bootstrap-mode`; if absent, detect via `rpm -q sway` and persist result |

**Why caching matters:** On a base Fedora install, the first run detects `sway` as absent and installs it. Without caching, the second run would detect `sway` as present and flip to Sway Spin mode, skipping packages that should have been installed. The cache file prevents this mode flip.

The cached mode file is validated with `grep -qxE 'true|false'` — if corrupted, falls through to auto-detection.

### Managed System Resources

The system module manages six resources, all with bidirectional state sync (see Section 11):

| Resource | Detect | Apply (enabled) | Apply (disabled) |
|----------|--------|-----------------|------------------|
| Hostname | `hostname -s` vs profile | `hostnamectl set-hostname` | Skipped if empty |
| Keyboard | `localectl status` X11 Layout | `localectl set-x11-keymap` | Skipped if empty |
| GPU groups | `id -Gn` for video/render | `usermod -aG video,render` | Skipped (no GPU) |
| Firewall | `systemctl is-active firewalld` | `enable --now` | `disable --now` |
| Bluetooth | `systemctl is-enabled bluetooth` | `enable --now` | `disable --now` |
| Tuned | `systemctl is-enabled tuned` | `enable --now` | `disable --now` |

## 10. Adding a New Module

To add a new module to the system:

### 1. Create Directory and Files

```bash
mkdir -p modules/<name>
touch modules/<name>/manifest.yaml
touch modules/<name>/module.sh
```

### 2. Write `manifest.yaml`

```yaml
name: <name>
description: <description>
version: 1.0.0
order: <number>
condition: always
requires: []
provides:
  - <capability>
```

### 3. Implement `module.sh`

```bash
# shellcheck shell=bash

<name>::init() {
    # Parse flags, read PROFILE_* vars, cache state
}

<name>::check() {
    # Return 0 if changes needed, 1 if up-to-date
}

<name>::preview() {
    # Print what would change
}

<name>::apply() {
    # Execute changes (idempotent)
}

<name>::status() {
    # Print one-line status
}
```

### 4. Add Config Files (if needed)

```bash
mkdir -p modules/<name>/config
# Add your config files here
```

### 5. Declare Symlinks and Templates (if applicable)

```bash
# In modules/<name>/module.sh:

# Direct symlinks (non-templated config files):
_NAME_SYMLINK_MAP=(
    "config/myapp/config|$HOME/.config/myapp/config"
)

# Template files (contain {{PLACEHOLDER}} syntax):
_NAME_TEMPLATE_MAP=(
    "config/myapp/theme.conf"
)
```

If config files use accent colors or profile values, add `{{PLACEHOLDER}}` syntax and list them in `_TEMPLATE_MAP`. The module's `apply()` calls `render_module_templates` to render them to the staging directory before deploying symlinks.

### 6. Verify Discovery

```bash
./setup install    # dry-run — your module should appear in the output
```

## 11. State Sync

The system uses a **bidirectional state sync** model. Modules do not merely deploy configuration — they synchronize the live system to match the desired state declared in the profile. When a feature is disabled or a config file is removed from a symlink map, the system actively reverts the corresponding state on the live system.

### Problem: Deploy-Only Drift

A deploy-only model creates configuration drift. If a module enables a service on the first run and the user later disables it in the profile, re-running `./setup --apply` skips the service but does not disable it. The same applies to symlinks: removing an entry from `_SYMLINK_MAP` leaves a stale symlink in `~/.config/`.

Examples of drift under a deploy-only model:

| Profile change | Expected outcome | Deploy-only outcome |
|---|---|---|
| `firewalld = false` | firewalld disabled | firewalld stays active |
| `docker_alias = false` | alias removed from bootstrap-env.sh | old alias persists |
| Entry removed from `_SWAY_SYMLINK_MAP` | stale symlink cleaned up | stale symlink remains |
| `tela_icons = false` | icon theme removed | icon theme stays installed |

### State-Aware Module Logic

Every `check()`, `preview()`, and `apply()` function handles both the desired state (feature enabled) and the undesired state (feature disabled). This means modules must detect resources that are present but should not be, and actively remove or disable them.

**Service management pattern:**

```bash
if [[ "${PROFILE_SYSTEM_TUNED:-true}" == "true" ]]; then
    sudo systemctl enable --now tuned
else
    if systemctl is-enabled --quiet tuned 2>/dev/null; then
        sudo systemctl disable --now tuned
    fi
fi
```

**Check function:** Returns `0` (changes needed) when a service is enabled but the profile says it should be disabled, not only when a service is disabled but should be enabled.

**Preview function:** Indicates reversions explicitly:

```
Tuned: enabled → disable  [REVERT]
```

### Generated File Regeneration

Files generated from profile keys (e.g. `bootstrap-env.sh` in the shell module) are regenerated on every run and compared against the deployed version. This ensures that disabling a profile toggle removes its corresponding block from the generated file. The shell module already follows this pattern via `_shell_generate_env()` and `cmp -s`.

### Symlink Lifecycle Management

Symlinks are managed through a tracked lifecycle. The system maintains a state directory at:

```
$HOME/.local/state/v2-modular/links/
```

For each module, a file `<module_name>.list` records the absolute paths of symlinks currently deployed by that module. On each run, the system:

1. **Resolves desired destinations** from the module's `_SYMLINK_MAP`, evaluating conditions
2. **Deploys new or changed symlinks** via `link_file()`
3. **Compares desired set against previous state** to find stale entries
4. **Removes stale symlinks** — only if the target is still a symlink (not a user-replaced regular file)
5. **Updates the state file** with the new desired set

This is handled by a `sync_links` helper in `core/links.sh`:

```bash
# sync_links <module_name> <map_array_name>
# Deploys symlinks from the map, removes stale symlinks from previous runs,
# and updates the persistent state file.
sync_links() {
    local mod="$1"
    local map_name="$2[@]"
    local map=("${!map_name}")
    local state_dir="$HOME/.local/state/v2-modular/links"
    local state_file="${state_dir}/${mod}.list"

    mkdir -p "$state_dir"

    # 1. Deploy desired symlinks, collect destination list
    local desired=()
    for entry in "${map[@]}"; do
        IFS='|' read -r src dst cond <<< "$entry"
        # Evaluate condition if present (shell module uses 3-field entries)
        if [[ -n "${cond:-}" ]]; then
            evaluate_condition "$cond" || continue
        fi
        desired+=("$dst")
        link_file "$MODULE_DIR/$src" "$dst"
    done

    # 2. Remove stale symlinks from previous run
    if [[ -f "$state_file" ]]; then
        while IFS= read -r old_dst; do
            if [[ ! " ${desired[*]} " =~ " ${old_dst} " ]]; then
                if [[ -L "$old_dst" ]]; then
                    rm "$old_dst"
                    ok "Removed stale symlink: $old_dst"
                elif [[ -e "$old_dst" ]]; then
                    warn "Stale path is not a symlink (kept): $old_dst"
                fi
            fi
        done < "$state_file"
    fi

    # 3. Persist current state
    printf "%s\n" "${desired[@]}" > "$state_file"
}
```

Modules call `sync_links` in place of manual `link_file` loops:

```bash
sway::apply() {
    sync_links "sway" "_SWAY_SYMLINK_MAP"
    # ... local overrides, scripts, etc.
}
```

### Edge Cases and Safety

- **User-replaced files:** If a file at a tracked path is a regular file (not a symlink), the cleanup step warns but does not remove it. The user explicitly replaced the symlink with their own file.
- **Interrupted runs:** If a run is interrupted between deploying symlinks and writing the state file, the next run rebuilds the state file from the current symlink map. No symlinks are orphaned because the state file is always written last.
- **First run (no state file):** When no state file exists, the system deploys all symlinks and creates the state file. No cleanup is performed since there is no prior state to compare against.
- **Collisions:** If two modules declare the same symlink destination, the last module to run (by `order`) wins the state entry. Manifest validation should prevent this; if it occurs, a warning is logged.
- **Manual deletions:** If a user manually deletes a symlink that the system tracks, the next run recreates it (idempotency is preserved).

### Scope of State Sync by Resource Type

| Resource | Sync mechanism | Revert action |
|---|---|---|
| Symlinks | `sync_links` with state tracking | Remove stale symlinks |
| System services (firewalld, bluetooth, tuned) | State-aware `check()`/`apply()` | `systemctl disable --now` |
| Generated files (bootstrap-env.sh) | Regenerate and `cmp -s` on every run | Omit disabled blocks |
| Installed packages | Package manifest tracking | Out of scope (no uninstall) |
| Git-cloned resources (Tela icons, SDDM corners) | Presence check in `apply()` | Remove directory when disabled |

Package uninstallation is explicitly out of scope. Removing packages risks breaking user-installed dependencies. The package manifest tracks what was installed but does not perform removals.

## 12. Key Design Patterns

### Idempotency

All modules follow idempotency patterns:

- **Package installation:** `dnf install` and `flatpak install` are inherently idempotent
- **File appends:** Guarded by `grep -qF` to prevent duplicates
- **Symlinks:** Uses `link_file` helper which checks `readlink` first
- **Env file writes:** Uses `cmp -s` to skip if content unchanged
- **Mode detection:** Cached in `~/.config/shell/.bootstrap-mode` on first run; re-runs reuse the saved mode

### Error Handling

All modules inherit `set -euo pipefail` from the orchestrator. Additional robustness:

- **`link_file` validates source exists** before creating symlinks — warns and continues if a config file is missing
- **Mode file validated** with `grep -qxE 'pattern'` — falls through to auto-detection if corrupted
- **Network operations have timeouts** — `curl --connect-timeout 5` on URL probes
- Avoid `return 1` from helper functions unless you want script to abort; use `return 0` with a warning for non-fatal issues

### Deduplication

- **Shared functions** go in `core/*.sh` (common.sh, config.sh, colors.sh, links.sh)
- **Identical config files** use a single source with multiple symlinks in the per-module symlink map
- **Package lists** are deduplicated arrays in shared locations
- **Color presets** are data files — adding a preset requires no code changes

## 13. Theming Integration

For theming to work across all platforms (GTK, Qt, KDE, SDDM), all layers must align:

| Layer | Mechanism | Module | Template |
|-------|-----------|--------|----------|
| GTK 3/4 | gsettings + settings.ini | theme | `config/gtk/settings.ini` (rendered) |
| Qt (all apps) | QT_QPA_PLATFORMTHEME=kde + plasma-integration | shell + theme | `config/kde/kdeglobals` (rendered) |
| Qt style | QT_STYLE_OVERRIDE=Breeze | shell | bootstrap-env.sh (generated) |
| SDDM greeter | sddm-theme-corners (Qt6) | theme | `config/sddm/theme.conf` (rendered) |
| Accent color | Template rendering from `colors/*.conf` presets | per-module | `{{ACCENT_*}}` placeholders in config templates |
| Sway borders | Template rendering | sway | `config/sway/config` (rendered) |
| Waybar accent | Template rendering | sway | `config/waybar/style.css` (rendered) |
| Dunst frame | Template rendering | sway | `config/dunst/dunstrc` (rendered) |
| Swaylock ring | Template rendering (bare hex) | sway | `config/swaylock/config` (rendered) |

**Rendered vs direct symlinks:** Files marked "(rendered)" are templates — symlinks point to `~/.local/share/v2-modular/rendered/<module>/`. Files without accent colors or profile values are symlinked directly from the repo.

**Important:** Do not remove Qt5 packages. The SDDM greeter uses Qt6, but the dark theme integration still requires Qt5 libraries (`kf5-frameworkintegration`, etc.).

## 14. Sway Compositor Configuration

The sway module (order 40, condition `sway`) manages the full Wayland compositor stack. The sway config (`modules/sway/config/sway/config`) is a template — accent colors and profile values are rendered at deploy time.

### Keyboard Layout

The config assumes an **AZERTY keyboard layout** for workspace bindings. Workspaces 1–10 use the AZERTY number row (`ampersand`, `eacute`, `quotedbl`, `apostrophe`, `parenleft`, `minus`, `egrave`, `underscore`, `ccedilla`, `agrave`). Workspaces 11–20 use `$mod+Alt+<digit>`.

**If switching to QWERTY**, the workspace bindings must be rewritten to use digit keys directly.

### Keybinding Summary

| Binding | Action |
|---------|--------|
| `$mod+Return` | Launch kitty terminal |
| `$mod+d` | bemenu app launcher (styled with accent colors) |
| `$mod+Shift+A` | Kill focused window |
| `$mod+f` | Toggle fullscreen |
| `$mod+Shift+space` | Toggle floating |
| `$mod+space` | Toggle focus tiling/floating |
| `$mod+j/k/l/m` | Focus left/down/up/right |
| `$mod+Shift+j/k/l/m` | Move window left/down/up/right |
| Arrow keys | Also work for focus/move (with Shift) |
| `$mod+h` | Split horizontal |
| `$mod+v` | Split vertical |
| `$mod+s` | Stacking layout |
| `$mod+z` | Tabbed layout |
| `$mod+e` | Toggle split layout |
| `$mod+Shift+s` | Toggle sticky |
| `$mod+a` / `$mod+q` | Focus parent / child |
| `Ctrl+$mod+Left/Right` | Previous / next workspace |
| `$mod+r` | Enter resize mode (arrows to resize, Escape to exit) |
| `$mod+Shift+c` | Reload config |
| `$mod+Shift+r` | Restart sway |
| `$mod+Shift+e` | Exit sway (with confirmation dialog) |

### Autostart Services

The sway config starts these processes at login:

```
dbus-update-activation-environment    # Exports WAYLAND_DISPLAY to systemd/dbus
gnome-keyring-daemon                  # Secrets + SSH agent
kanshi                                # Dynamic display profile management
polkit-mate-authentication-agent      # Privilege escalation agent
waybar                                # Status bar
dunst                                 # Notification daemon
protonvpn-app                         # VPN client
```

### Idle and Lock

```
swayidle:
  300s  → swaylock -f         (lock screen)
  600s  → output * power off  (DPMS off)
  resume → output * power on
  before-sleep → swaylock -f  (lock before suspend)
```

### Theme Integration

- Font: Droid Sans Fallback 12
- Border: 1px pixel
- Window borders use `{{ACCENT_PRIMARY}}`, `{{ACCENT_DIM}}`, `{{ACCENT_DARK}}`, `{{ACCENT_BRIGHT}}` for focused/inactive/unfocused/placeholder states
- Cursor theme: Adwaita 24px (set via `seat * xcursor_theme`)
- GTK/icon/cursor themes applied via `gsettings` in an `exec_always` block

### Waybar Layout

The status bar is configured in `modules/sway/config/waybar/config` (direct symlink, not templated):

```
Left:    [workspaces] [window title]
Center:  [bandwidth ↓/↑]
Right:   [VPN status] [WiFi] [GPU temp/load] [CPU] [Memory] [Disk] [Audio] [Clock] [Tray]
```

**Custom scripts** (in `modules/sway/config/waybar/scripts/`):

- **`bandwidth.sh`** — Reads rx/tx bytes from `/sys/class/net/<iface>/statistics/`, computes rate delta, formats as KB/s or MB/s. State persisted in `$XDG_RUNTIME_DIR/waybar_bw_prev`. Interval: 2s.
- **`gpu.sh`** — Reads AMD GPU temperature from `/sys/class/drm/card*/device/hwmon/hwmon*/temp1_input` and load from `gpu_busy_percent`. Displays "GPU N/A" if no sensor found. Interval: 5s.

**VPN monitoring**: The `network#vpn` module watches the `proton0` interface and shows the VPN IP or "VPN: Off".

## 15. SDDM and Icon Theme Installation

### SDDM Theming

The theme module supports two SDDM variants, controlled by `sddm_theme` in the `[theme]` profile section:

**Stock variant** (`sddm_theme = stock`, default):
1. Targets the existing `03-sway-fedora` theme directory in `/usr/share/sddm/themes/`
2. Deploys a dark grey background PNG image
3. Writes `theme.conf.user` to point at the background (idempotent via `cmp -s`)

**Corners variant** (`sddm_theme = corners`):
1. Installs Qt6 compatibility packages (`qt6-qt5compat`, `qt6-qtsvg`)
2. Shallow-clones `https://github.com/aczw/sddm-theme-corners.git` to a temp directory
3. Copies the `corners/` subdirectory to `/usr/share/sddm/themes/corners`
4. **Qt5 → Qt6 QML patching**: replaces `import QtGraphicalEffects.*` with `import Qt5Compat.GraphicalEffects` in all `*.qml` files (the upstream theme targets Qt5, but Fedora's SDDM uses Qt6)
5. Injects dark background color (`color: "#222222"`) into `Main.qml`
6. Renders `config/sddm/theme.conf` (accent-colored) and deploys it to the theme directory

**Both variants** then:
- Write `/etc/sddm.conf.d/theme.conf` with `[Theme]\nCurrent=<name>`
- Enable the `sddm` systemd service, disable `greetd` if present

**State detection**: `_theme_sddm_state()` returns one of: `disabled`, `not_installed`, `missing_dir`, `wrong_theme`, `wrong_accent`, `ok` — used by both `check()` and `preview()`.

All SDDM operations require `sudo` (system theme directory). The module uses a temp directory with a cleanup trap that saves and restores any previous EXIT trap to avoid clobbering the orchestrator.

### Tela Icon Theme

When `tela_icons = true` (default), the theme module installs the [Tela icon theme](https://github.com/vinceliuice/Tela-icon-theme) with the active accent color:

1. Check if `~/.local/share/icons/Tela-<accent>` exists
2. If present, verify it's accent-colored by checking `default-folder.svg` for the default blue fill (`#5294e2`) — if found, the theme was installed without an accent and needs reinstalling
3. If incomplete (missing marker SVG), remove and reinstall
4. Shallow-clone the GitHub repo to a temp directory
5. Run `install.sh -d ~/.local/share/icons <accent_name>`

When `tela_icons = false`, the icon directory is removed if present (state sync revert).

## 16. Working Guidelines

### Verify Before Declaring Done

For config/theming changes, don't just check that a file exists. Trace the full chain:

1. Does the source file exist in the module's `config/` directory?
2. Is it in the module's symlink map (e.g. `_SWAY_SYMLINK_MAP`)?
3. Is it symlinked correctly in `~/.config/`?
4. Does the target application discover and apply the config?
5. Are all required env vars set?

### Changes Span Multiple Files

A single feature often touches:

1. The config file itself (e.g., `modules/sway/config/sway/config`)
2. The symlink map in the module's `module.sh`
3. The shell module (if env vars are needed)
4. The profile in `config.default.ini` (if new settings are introduced)
5. The theme module (if accent colors are involved)

Always check all layers.

### Maintainability Conventions

- **Package lists:** One package per line, alphabetically sorted (clean diffs, easy to spot duplicates)
- **No dead code:** Don't comment out old configs; they're in git history. Keep only active configs.
- **Constants over magic numbers:** Define `KB`, `MB`, `GB`, etc. at script top if doing unit math
- **Log files:** Use `$XDG_RUNTIME_DIR` (user-private, tmpfs), not `/tmp` (world-writable)
- **Naming:** Modules use short descriptive names; config dirs match XDG target names

## 17. Testing

Container-based smoke tests in `tests/` provide integration coverage via `smoke.sh`, which builds a Fedora 43 container image and runs each test case in an isolated `podman run`:

- **Profile system:** loading, validation, unknown-key detection, type-mismatch detection
- **Color presets:** preset loading, accent resolution, green fallback
- **Link management:** symlink creation, stale symlink removal, conditional deployment, user-file preservation
- **Template rendering:** placeholder substitution, unresolved-placeholder detection, idempotency, module-level rendering, change detection (`check_rendered`)
- **End-to-end dry-run:** minimal and full-profile configurations through the orchestrator
- **Per-module dry-run:** each module individually (system, packages, shell, sway, theme)
- **Static analysis:** ShellCheck on all `.sh` files

Run tests with:

```bash
./tests/smoke.sh
```

## 18. See Also

- **Module-specific details:** `modules/<name>/ARCH.md` (e.g., `modules/sway/ARCH.md`)
- **Orchestrator code:** `setup` script
- **Common helpers:** `core/common.sh`
- **Profile parsing:** `core/config.sh`
- **Color preset loading:** `core/colors.sh`
- **Template rendering:** `core/templates.sh`
- **Symlink deployment:** `core/links.sh`
- **Manifest discovery:** `core/manifest.sh`
