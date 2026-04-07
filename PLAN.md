# Implementation Plan: v2-modular System

## Programming Language
The primary programming language chosen for this implementation is **Bash**. Bash is ideal because the system relies heavily on executing system commands, manipulating files, managing system state (services, packages, symlinks), and integrates directly with the underlying OS (Fedora 43).

## Phase 1: Project Setup & Orchestrator
1. **Initialize Directory Structure:**
   - Create directories for `core/`, `modules/`, `colors/`, `documentation/`, and `tests/`.
2. **Setup Base Configuration:**
   - Create `config.default.ini` with base default settings.
   - Setup `config.local.ini` as a gitignored file for local overrides.
3. **Implement Color Presets:**
   - Create initial color configuration files (e.g., `colors/green.conf`, `colors/blue.conf`) adhering to the defined preset format.
4. **Develop the Orchestrator (`setup`):**
   - Implement the main entry script to parse command-line arguments (e.g., `--apply`, `--dry-run`).
   - Integrate module loading, dependency resolution (based on `requires` and `order`), and execution flow.

## Phase 2: Core Libraries (`core/`)
1. **`core/common.sh`:**
   - Implement logging (`ok`, `warn`, `err`), preflight checks, hardware detection (`detect_gpu`, `detect_mode`), and network operations (`find_fedora_version`).
2. **`core/config.sh`:**
   - Implement INI parser functions: `load_profile` and `profile_get`.
3. **`core/colors.sh`:**
   - Create functions to read presets (`load_all_presets`) and resolve active accent colors (`load_accent`).
4. **`core/manifest.sh`:**
   - Implement `parse_manifest` to read `manifest.yaml` and `discover_modules` to build the execution sequence.
5. **`core/links.sh`:**
   - Develop the `sync_links` system to handle deployment, state tracking, and cleanup of symlinks (lifecycle management).
6. **`core/templates.sh`:**
   - Implement `render_template` and `render_module_templates` for replacing `{{PLACEHOLDER}}` values with resolved variables and writing to staging directories.

## Phase 3: Module Implementation (`modules/`)
1. **System Module (`order: 10`):**
   - Create `manifest.yaml` and `module.sh`.
   - Implement logic to manage hostname, keyboard layout, GPU groups, and services (`firewalld`, `bluetooth`, `tuned`).
2. **Packages Module (`order: 20`):**
   - Create `packages.conf` format for defining software lists with qualifiers.
   - Implement repository setup, conditional package installations (RPMs, Flatpaks, ROCm), and codec swaps.
3. **Shell Module (`order: 30`):**
   - Implement the generation of `~/.config/shell/bootstrap-env.sh` and integration with `.bashrc`.
   - Setup `config.local` files for `fish`, `kitty`, and `tmux`.
4. **Sway Module (`order: 40`, `condition: sway`):**
   - Implement configuration for Wayland compositor stack, Waybar, Kanshi, and Dunst.
   - Define template map for accent rendering and direct symlinks for static configs.
5. **Theme Module (`order: 50`):**
   - Implement SDDM theming (stock and corners variants) with Qt5 to Qt6 QML patching.
   - Implement Tela icon theme installation using the active accent color.
   - Deploy GTK and Qt configuration files.

## Phase 4: State Management & Idempotency Validation
1. **Bidirectional State Sync:**
   - Ensure all modules implement "revert" logic in `check()`, `preview()`, and `apply()` when a feature is disabled in the profile.
2. **Symlink Tracking:**
   - Verify that `sync_links` accurately maintains `$HOME/.local/state/v2-modular/links/*.list` and cleans up stale links.
3. **Template Rendering Robustness:**
   - Guarantee atomic writes and `cmp -s` validation so unchanged templates are not rewritten.

## Phase 5: Testing (`tests/`)
1. **Smoke Tests:**
   - Develop `smoke.sh` and `Containerfile` to spin up a Fedora 43 container.
   - Implement test cases covering profile loading, color presets, symlink management, and template rendering.
2. **Module Integration Tests:**
   - Run full `--dry-run` against both minimal and full profiles inside the container.
3. **Static Analysis:**
   - Setup ShellCheck to validate all `.sh` scripts.
