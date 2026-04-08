# shellcheck shell=bash
# core/templates.sh -- Template rendering library
# Sourced by other scripts, not executed directly.
# Requires: core/common.sh (ok, warn, die), core/colors.sh (ACCENT_* vars)
#           PROFILE_* vars set by core/config.sh

# shellcheck disable=SC2034  # used by callers that source this library
RENDERED_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/v2-modular/rendered"

_TEMPLATE_SED_ARGS=()
_template_sed_args() {
    local icon_theme="${PROFILE_THEME_ICON_THEME:-Tela}-${ACCENT_NAME}"
    _TEMPLATE_SED_ARGS=(
        -e "s|{{ACCENT_NAME}}|${ACCENT_NAME}|g"
        -e "s|{{ACCENT_PRIMARY}}|${ACCENT_PRIMARY}|g"
        -e "s|{{ACCENT_DIM}}|${ACCENT_DIM}|g"
        -e "s|{{ACCENT_DARK}}|${ACCENT_DARK}|g"
        -e "s|{{ACCENT_BRIGHT}}|${ACCENT_BRIGHT}|g"
        -e "s|{{ACCENT_SECONDARY}}|${ACCENT_SECONDARY}|g"
        -e "s|{{ACCENT_ANSI}}|${ACCENT_ANSI}|g"
        -e "s|{{ACCENT_PRIMARY_BARE}}|${ACCENT_PRIMARY#\#}|g"
        -e "s|{{ACCENT_DIM_BARE}}|${ACCENT_DIM#\#}|g"
        -e "s|{{ACCENT_DARK_BARE}}|${ACCENT_DARK#\#}|g"
        -e "s|{{ACCENT_BRIGHT_BARE}}|${ACCENT_BRIGHT#\#}|g"
        -e "s|{{ACCENT_SECONDARY_BARE}}|${ACCENT_SECONDARY#\#}|g"
        -e "s|{{PROFILE_THEME_GTK_THEME}}|${PROFILE_THEME_GTK_THEME:-Adwaita-dark}|g"
        -e "s|{{PROFILE_THEME_CURSOR_THEME}}|${PROFILE_THEME_CURSOR_THEME:-Adwaita}|g"
        -e "s|{{PROFILE_THEME_ICON_THEME}}|${icon_theme}|g"
        -e "s|{{PROFILE_SYSTEM_KEYBOARD_LAYOUT}}|${PROFILE_SYSTEM_KEYBOARD_LAYOUT:-us}|g"
    )
}

render_template() {
    local src="$1" dst="$2"

    if [[ ! -f "$src" ]]; then
        warn "Template source does not exist, skipping: $src"
        return 0
    fi

    mkdir -p "$(dirname "$dst")"

    _template_sed_args

    local tmp="${dst}.tmp"
    sed "${_TEMPLATE_SED_ARGS[@]}" "$src" > "$tmp"

    # Validate: no unresolved placeholders
    local unresolved
    unresolved=$(grep -oP '\{\{[A-Z_]+\}\}' "$tmp" 2>/dev/null | sort -u | tr '\n' ' ' || true)
    if [[ -n "$unresolved" ]]; then
        rm -f "$tmp"
        die "Unresolved placeholders in $src: $unresolved"
    fi

    # Idempotent: skip if identical
    if cmp -s "$tmp" "$dst" 2>/dev/null; then
        rm -f "$tmp"
        return 0
    fi

    mv -f "$tmp" "$dst"
    ok "Rendered: $dst"
}

# ---------------------------------------------------------------------------
# render_module_templates <module_name>
# Renders all templates listed in _<MODULE>_TEMPLATE_MAP.
# Source: MODULE_DIR/<entry>  →  Destination: RENDERED_DIR/<module>/<entry>
# ---------------------------------------------------------------------------
render_module_templates() {
    local mod="$1"
    local map_var
    map_var="_$(echo "$mod" | tr '[:lower:]-' '[:upper:]_')_TEMPLATE_MAP"
    local map_ref="${map_var}[@]"

    # If map is empty or unset, nothing to do
    if [[ -z "${!map_var+x}" ]]; then
        return 0
    fi

    local entry
    for entry in "${!map_ref}"; do
        render_template "$MODULE_DIR/$entry" "$RENDERED_DIR/$mod/$entry"
    done
}

# ---------------------------------------------------------------------------
# check_rendered <module_name>
# Returns 0 if any template would produce different output (changes needed).
# Returns 1 if all rendered files are up-to-date.
# ---------------------------------------------------------------------------
check_rendered() {
    local mod="$1"
    local map_var
    map_var="_$(echo "$mod" | tr '[:lower:]-' '[:upper:]_')_TEMPLATE_MAP"
    local map_ref="${map_var}[@]"

    if [[ -z "${!map_var+x}" ]]; then
        return 1
    fi

    _template_sed_args

    local entry
    for entry in "${!map_ref}"; do
        local src="$MODULE_DIR/$entry"
        local dst="$RENDERED_DIR/$mod/$entry"

        [[ ! -f "$src" ]] && continue
        [[ ! -f "$dst" ]] && return 0

        local rendered
        rendered=$(sed "${_TEMPLATE_SED_ARGS[@]}" "$src")
        if [[ "$rendered" != "$(cat "$dst")" ]]; then
            return 0
        fi
    done

    return 1
}

# ---------------------------------------------------------------------------
# build_rendered_symlink_map <module_name> <template_map_name> <output_array_name>
# Builds symlink map entries for rendered templates.
# Output entries: "RENDERED_DIR/mod/path|~/.config/path"
# The config/ prefix in the template path maps to ~/.config/.
# ---------------------------------------------------------------------------
build_rendered_symlink_map() {
    local mod="$1"
    local map_ref="${2}[@]"
    local -n out_map="$3"

    local entry
    for entry in "${!map_ref}"; do
        # Strip leading "config/" to get the ~/.config/ relative path
        local config_rel="${entry#config/}"
        out_map+=("${RENDERED_DIR}/${mod}/${entry}|${HOME}/.config/${config_rel}")
    done
}
