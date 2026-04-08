# shellcheck shell=bash
# modules/sway/module.sh -- Sway compositor stack configuration module.
# Source this file; do not execute it directly.
#
# Handles: sway, waybar, kanshi, swaylock, dunst configs.
#
# Assumes lib/common.sh and lib/links.sh are sourced.
# link_file(), check_link(), ensure_local_override(), MODULE_DIR are available.

# ---------------------------------------------------------------------------
# Template map: files with {{PLACEHOLDER}} syntax, rendered to staging dir
# ---------------------------------------------------------------------------

_SWAY_TEMPLATE_MAP=(
    "config/sway/config"
    "config/waybar/style.css"
    "config/dunst/dunstrc"
    "config/swaylock/config"
)

# ---------------------------------------------------------------------------
# Symlink map: non-templated files, symlinked directly from repo
# Sources are relative to $MODULE_DIR.
# ---------------------------------------------------------------------------

_SWAY_SYMLINK_MAP=(
    "config/waybar/config|${HOME}/.config/waybar/config"
    "config/waybar/scripts|${HOME}/.config/waybar/scripts"
    "config/kanshi/config|${HOME}/.config/kanshi/config"
)

# Local overrides: "target|comment_char"
_SWAY_LOCAL_OVERRIDES=(
    "${HOME}/.config/sway/config.local|#"
    "${HOME}/.config/dunst/dunstrc.local|#"
)

# ---------------------------------------------------------------------------
# Module contract
# ---------------------------------------------------------------------------

sway::init() {
    : # No profile keys to read for this module
}

sway::check() {
    # Check if templates need re-rendering
    check_rendered "sway" && return 0

    # Check direct symlinks
    local entry src dst status
    for entry in "${_SWAY_SYMLINK_MAP[@]}"; do
        src="${MODULE_DIR}/${entry%%|*}"
        dst="${entry##*|}"
        status="$(check_link "$src" "$dst")"
        [[ "$status" != "ok" ]] && return 0
    done

    # Check rendered symlinks
    local -a rendered_links=()
    build_rendered_symlink_map "sway" "_SWAY_TEMPLATE_MAP" "rendered_links"
    for entry in "${rendered_links[@]}"; do
        src="${entry%%|*}"
        dst="${entry##*|}"
        status="$(check_link "$src" "$dst")"
        [[ "$status" != "ok" ]] && return 0
    done

    # Check local overrides
    local override target
    for override in "${_SWAY_LOCAL_OVERRIDES[@]}"; do
        target="${override%%|*}"
        [[ ! -e "$target" ]] && return 0
    done

    return 1
}

sway::preview() {
    info "[sway] Preview:"

    # Template rendering status
    if check_rendered "sway"; then
        echo "  Templates: need re-rendering  [CHANGE]"
    else
        echo "  Templates: up to date  [OK]"
    fi

    # Direct symlinks
    preview_links "sway" "_SWAY_SYMLINK_MAP"

    # Rendered symlinks
    local -a rendered_links=()
    build_rendered_symlink_map "sway" "_SWAY_TEMPLATE_MAP" "rendered_links"
    local entry src dst status tag
    for entry in "${rendered_links[@]}"; do
        src="${entry%%|*}"
        dst="${entry##*|}"
        status=$(check_link "$src" "$dst")
        case "$status" in
            ok)          tag="[OK]" ;;
            missing)     tag="[WILL CREATE]" ;;
            wrong)       tag="[WILL RELINK]" ;;
            blocked)     tag="[WILL BACKUP + LINK]" ;;
            src_missing) tag="[NOT YET RENDERED]" ;;
        esac
        printf "  %-45s → %-45s %s\n" "(rendered) ${entry##*/}" "$dst" "$tag"
    done

    # Local overrides
    local override target
    for override in "${_SWAY_LOCAL_OVERRIDES[@]}"; do
        target="${override%%|*}"
        if [[ -e "$target" ]]; then
            echo "  Local override: $target  [OK]"
        else
            echo "  Local override: $target  [CREATE]"
        fi
    done
}

sway::apply() {
    # 1. Render templates
    render_module_templates "sway"
    ok "Sway templates rendered"

    # 2. Build combined symlink map (direct + rendered)
    local -a rendered_links=()
    build_rendered_symlink_map "sway" "_SWAY_TEMPLATE_MAP" "rendered_links"
    _SWAY_ALL_LINKS=("${_SWAY_SYMLINK_MAP[@]}" "${rendered_links[@]}")
    sync_links "sway" "_SWAY_ALL_LINKS"

    # 3. Local overrides
    local override target comment
    for override in "${_SWAY_LOCAL_OVERRIDES[@]}"; do
        target="${override%%|*}"
        comment="${override##*|}"
        ensure_local_override "$target" "$comment"
    done

    # 4. Waybar scripts
    if compgen -G "$MODULE_DIR/config/waybar/scripts/*.sh" >/dev/null 2>&1; then
        chmod +x "$MODULE_DIR"/config/waybar/scripts/*.sh
        ok "waybar scripts marked executable"
    fi

    ok "Sway compositor stack configured"
}

sway::status() {
    local total=0 linked=0 entry src dst status

    for entry in "${_SWAY_SYMLINK_MAP[@]}"; do
        src="${MODULE_DIR}/${entry%%|*}"
        dst="${entry##*|}"
        (( total++ )) || true
        status="$(check_link "$src" "$dst")"
        [[ "$status" == "ok" ]] && (( linked++ )) || true
    done

    local -a rendered_links=()
    build_rendered_symlink_map "sway" "_SWAY_TEMPLATE_MAP" "rendered_links"
    for entry in "${rendered_links[@]}"; do
        src="${entry%%|*}"
        dst="${entry##*|}"
        (( total++ )) || true
        status="$(check_link "$src" "$dst")"
        [[ "$status" == "ok" ]] && (( linked++ )) || true
    done

    echo "sway: ${linked}/${total} symlinks active"
}
