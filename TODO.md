# Remaining Tasks and Dead Code Analysis

## ShellCheck Warnings
1. **`modules/sway/module.sh`**:
   - `[[ "$status" == "ok" ]] && (( linked++ )) || true` generates a `SC2015` warning indicating `A && B || C` is not an `if-then-else`. This should be rewritten for clarity and safety.
2. **`modules/shell/config/bash/completions.sh`**:
   - Missing shebang. Generates `SC2148`.
3. **`modules/shell/config/bash/prompt.sh`**:
   - Literal `{` and `}` characters around `{{ACCENT_ANSI}}` cause `SC1083` warnings, though this is expected due to the template engine replacing these placeholders.

## Dead Code / Missing Implementations
1. **Missing Git Dependencies**: The system relies heavily on `git clone` (e.g., for `sddm-theme-corners` and `tela-icon-theme`), but there is no explicit validation or preflight check confirming `git` is installed before attempting network clones in `modules/theme/module.sh`.
2. **Missing `apt-get` Support**: The project is heavily oriented toward Fedora and DNF/RPM Fusion. There is no support for Debian/Ubuntu environments, but `smoke.sh` testing scripts do not cleanly abort if run on an unsupported system.
3. **Template Rendering Robustness**: `core/templates.sh` explicitly replaces specific `ACCENT_*` placeholders via `sed`, but it doesn't dynamically support all color variables, meaning new presets might be ignored unless the script is updated manually.

## Next Steps
- Implement proper `if-then-else` blocks in `modules/sway/module.sh` to resolve SC2015.
- Add an explicit `#!/bin/bash` or `#!/usr/bin/env bash` shebang to `modules/shell/config/bash/completions.sh`.
- Consider adding an explicit warning or ignoring `SC1083` for template files containing `{{PLACEHOLDER}}` syntax.
- Ensure all modules include `git` in their preflight dependencies if they plan to clone repositories.
