# shellcheck shell=bash
# modules/theme/module.sh -- Theme module (accent colors + icon theme + SDDM).
# Source this file; do not execute it directly.
#
# Assumes all core libs sourced, REPO_ROOT and MODULE_DIR set.
# render_module_templates(), render_template(), check_rendered(),
# pkg_install(), require_cmd(), die() are available.

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

_SDDM_THEME_BASE="/usr/share/sddm/themes"
_TELA_ICON_BASE="$HOME/.local/share/icons"

# ---------------------------------------------------------------------------
# Template map: files with {{PLACEHOLDER}} syntax, rendered to staging dir
# (SDDM theme.conf is handled separately — deployed via sudo to system dir)
# ---------------------------------------------------------------------------

_THEME_TEMPLATE_MAP=(
    "config/gtk/settings.ini"
    "config/kde/kdeglobals"
)

# Rendered symlink destinations (custom — GTK settings.ini symlinks to both gtk-3.0 and gtk-4.0)
_THEME_RENDERED_SYMLINK_MAP=()
_theme_build_rendered_links() {
    _THEME_RENDERED_SYMLINK_MAP=(
        "${RENDERED_DIR}/theme/config/gtk/settings.ini|$HOME/.config/gtk-3.0/settings.ini"
        "${RENDERED_DIR}/theme/config/gtk/settings.ini|$HOME/.config/gtk-4.0/settings.ini"
        "${RENDERED_DIR}/theme/config/kde/kdeglobals|$HOME/.config/kdeglobals"
    )
}

# ---------------------------------------------------------------------------
# Symlink map for theme-owned configs
# ---------------------------------------------------------------------------

_THEME_SYMLINK_MAP=(
    "config/qt5ct/qt5ct.conf|$HOME/.config/qt5ct/qt5ct.conf"
    "config/qt6ct/qt6ct.conf|$HOME/.config/qt6ct/qt6ct.conf"
)

# ---------------------------------------------------------------------------
# Error handling
# ---------------------------------------------------------------------------

_THEME_TMPDIR=""
_THEME_PREV_TRAP=""

_theme_cleanup() {
    [[ -n "$_THEME_TMPDIR" ]] && rm -rf "$_THEME_TMPDIR"
    # Restore previous EXIT trap if one existed
    if [[ -n "$_THEME_PREV_TRAP" ]]; then
        eval "$_THEME_PREV_TRAP"
    else
        trap - EXIT
    fi
}

# ---------------------------------------------------------------------------
# SDDM state detection (single source of truth for check + preview)
# ---------------------------------------------------------------------------

# _theme_sddm_state
# Echoes one of: "disabled", "not_installed", "missing_dir", "wrong_theme",
#                "wrong_accent", "ok"
_theme_sddm_state() {
    [[ "$_THEME_SDDM_VARIANT" == "none" ]] && { echo "disabled"; return; }
    rpm -q sddm &>/dev/null || { echo "not_installed"; return; }

    local expected_theme="03-sway-fedora"
    [[ "$_THEME_SDDM_VARIANT" == "corners" ]] && expected_theme="corners"

    [[ ! -d "${_SDDM_THEME_BASE}/${expected_theme}" ]] && { echo "missing_dir"; return; }

    local current_theme
    current_theme=$(grep -oP 'Current=\K.*' /etc/sddm.conf.d/theme.conf 2>/dev/null || echo "")
    [[ "$current_theme" != "$expected_theme" ]] && { echo "wrong_theme"; return; }

    local deployed_conf="${_SDDM_THEME_BASE}/${expected_theme}/theme.conf"
    if [[ -f "$deployed_conf" ]] && ! grep -qi "$ACCENT_PRIMARY" "$deployed_conf" 2>/dev/null; then
        echo "wrong_accent"
        return
    fi

    echo "ok"
}

# ---------------------------------------------------------------------------
# Tela icon theme
# ---------------------------------------------------------------------------

_theme_install_tela() {
    require_cmd git "sudo dnf install -y git"

    local tela_dir="${_TELA_ICON_BASE}/Tela-${ACCENT_NAME}"
    local need_install=false

    if [[ ! -d "$tela_dir" ]]; then
        need_install=true
    elif [[ -f "$tela_dir/scalable/places/default-folder.svg" ]]; then
        if [[ "$ACCENT_NAME" != "standard" ]] \
            && grep -qi '#5294e2' "$tela_dir/scalable/places/default-folder.svg"; then
            warn "Tela-${ACCENT_NAME} contains default blue icons -- reinstalling..."
            rm -rf "$tela_dir" "${tela_dir}-dark" "${tela_dir}-light"
            need_install=true
        fi
    else
        warn "Tela-${ACCENT_NAME} is incomplete -- reinstalling..."
        rm -rf "$tela_dir" "${tela_dir}-dark" "${tela_dir}-light"
        need_install=true
    fi

    if [[ "$need_install" == true ]]; then
        info "Installing Tela ${ACCENT_NAME} icon theme (user-local)..."
        local tela_tmp="${_THEME_TMPDIR}/tela-icon-theme"
        if ! git clone --depth 1 https://github.com/vinceliuice/Tela-icon-theme.git "$tela_tmp" 2>&1; then
            warn "Failed to clone Tela-icon-theme -- skipping icon theme"
            return 0
        fi
        bash "$tela_tmp/install.sh" -d "${_TELA_ICON_BASE}" "$ACCENT_NAME" \
            || die "Tela icon theme install.sh failed"
        ok "Tela ${ACCENT_NAME} icon theme installed"
    else
        ok "Tela ${ACCENT_NAME} icon theme already installed (skipped)"
    fi
}

# ---------------------------------------------------------------------------
# SDDM theming (split into focused helpers)
# ---------------------------------------------------------------------------

# _theme_install_sddm_corners <theme_dir>
_theme_install_sddm_corners() {
    local sddm_theme_dir="$1"

    pkg_install qt6-qt5compat qt6-qtsvg

    if [[ -d "$sddm_theme_dir" ]]; then
        ok "sddm-theme-corners already installed (skipped)"
    else
        local corners_tmp="${_THEME_TMPDIR}/corners"
        if ! git clone --depth 1 https://github.com/aczw/sddm-theme-corners.git "$corners_tmp" 2>&1; then
            warn "Failed to clone sddm-theme-corners -- skipping"
            return 0
        fi
        sudo cp -r "$corners_tmp/corners" "$sddm_theme_dir" \
            || die "Failed to install sddm-theme-corners to $sddm_theme_dir"
        ok "sddm-theme-corners installed"
    fi

    sudo chmod -R a+rX "$sddm_theme_dir" \
        || die "Failed to set permissions on $sddm_theme_dir"

    # Qt5 -> Qt6 patch
    if compgen -G "$sddm_theme_dir/components/*.qml" >/dev/null; then
        sudo sed -i 's/import QtGraphicalEffects.*/import Qt5Compat.GraphicalEffects/' \
            "$sddm_theme_dir"/components/*.qml \
            || die "Failed to patch QML files for Qt6"
    fi

    # Dark background color
    if [[ -f "$sddm_theme_dir/Main.qml" ]]; then
        if ! sudo grep -q 'color: "#222222"' "$sddm_theme_dir/Main.qml"; then
            sudo sed -i '/id: root/a\    color: "#222222"' "$sddm_theme_dir/Main.qml" \
                || die "Failed to patch Main.qml dark background"
        fi
    fi

    # Deploy theme.conf with accent colors
    local theme_tmp="${_THEME_TMPDIR}/sddm-theme.conf"
    render_template "$MODULE_DIR/config/sddm/theme.conf" "$theme_tmp"
    sudo cp "$theme_tmp" "$sddm_theme_dir/theme.conf" \
        || die "Failed to deploy sddm theme.conf"
    sudo chmod 644 "$sddm_theme_dir/theme.conf"
}

# _theme_apply_sddm_stock <theme_dir>
_theme_apply_sddm_stock() {
    local sddm_theme_dir="$1"
    local bg_src="$MODULE_DIR/config/sddm/background-dark-grey.png"

    if [[ ! -d "$sddm_theme_dir" ]]; then
        warn "Stock SDDM theme not found at $sddm_theme_dir -- is sddm installed?"
        return 0
    fi

    sudo cp "$bg_src" "$sddm_theme_dir/background-dark-grey.png" \
        || die "Failed to copy SDDM background"
    sudo chmod 644 "$sddm_theme_dir/background-dark-grey.png"

    local user_conf_tmp="${_THEME_TMPDIR}/sddm-user.conf"
    printf '[General]\nbackground=background-dark-grey.png\n' > "$user_conf_tmp"
    if ! sudo cmp -s "$user_conf_tmp" "$sddm_theme_dir/theme.conf.user" 2>/dev/null; then
        sudo cp "$user_conf_tmp" "$sddm_theme_dir/theme.conf.user" \
            || die "Failed to deploy sddm theme.conf.user"
        sudo chmod 644 "$sddm_theme_dir/theme.conf.user"
    fi
    ok "Dark grey background applied to stock SDDM theme"
}

# _theme_set_sddm_active <theme_name>
_theme_set_sddm_active() {
    local theme_name="$1"
    local sddm_conf_tmp="${_THEME_TMPDIR}/sddm-active.conf"
    printf '[Theme]\nCurrent=%s\n' "$theme_name" > "$sddm_conf_tmp"
    sudo mkdir -p /etc/sddm.conf.d
    if ! sudo cmp -s "$sddm_conf_tmp" /etc/sddm.conf.d/theme.conf 2>/dev/null; then
        sudo cp "$sddm_conf_tmp" /etc/sddm.conf.d/theme.conf \
            || die "Failed to write /etc/sddm.conf.d/theme.conf"
        sudo chmod 644 /etc/sddm.conf.d/theme.conf
    fi

    if systemctl is-enabled greetd &>/dev/null; then
        sudo systemctl disable greetd
    fi
    sudo systemctl enable sddm
    ok "SDDM configured (theme: $theme_name)"
}

# _theme_apply_sddm -- Orchestrator
_theme_apply_sddm() {
    local state
    state=$(_theme_sddm_state)

    case "$state" in
        disabled)
            info "SDDM theming: disabled by profile -- skipping"
            return 0
            ;;
        not_installed)
            info "SDDM not installed -- skipping SDDM theming"
            return 0
            ;;
    esac

    info "Configuring SDDM theme..."

    case "$_THEME_SDDM_VARIANT" in
        corners)
            _theme_install_sddm_corners "${_SDDM_THEME_BASE}/corners"
            _theme_set_sddm_active "corners"
            ;;
        *)
            _theme_apply_sddm_stock "${_SDDM_THEME_BASE}/03-sway-fedora"
            _theme_set_sddm_active "03-sway-fedora"
            ;;
    esac
}

# ---------------------------------------------------------------------------
# Module contract
# ---------------------------------------------------------------------------

theme::init() {
    _THEME_SDDM_VARIANT="${PROFILE_THEME_SDDM_THEME:-stock}"
    # Accent and presets are loaded by the orchestrator at startup.
}

theme::check() {
    # Check rendered templates
    check_rendered "theme" && return 0

    # Check rendered symlinks
    _theme_build_rendered_links
    local r_entry
    for r_entry in "${_THEME_RENDERED_SYMLINK_MAP[@]}"; do
        IFS='|' read -r r_src r_dst <<< "$r_entry"
        local r_status
        r_status=$(check_link "$r_src" "$r_dst")
        [[ "$r_status" != "ok" ]] && return 0
    done

    # Check theme symlinks
    local entry
    for entry in "${_THEME_SYMLINK_MAP[@]}"; do
        IFS='|' read -r rel dst <<< "$entry"
        local status
        status=$(check_link "$MODULE_DIR/$rel" "$dst")
        [[ "$status" != "ok" ]] && return 0
    done

    # Check icon theme
    if [[ "${PROFILE_THEME_TELA_ICONS:-true}" == "true" ]]; then
        [[ ! -d "${_TELA_ICON_BASE}/Tela-${ACCENT_NAME}" ]] && return 0
    else
        [[ -d "${_TELA_ICON_BASE}/Tela-${ACCENT_NAME}" ]] && return 0
    fi

    # Check SDDM state
    local sddm_state
    sddm_state=$(_theme_sddm_state)
    [[ "$sddm_state" != "ok" && "$sddm_state" != "disabled" && "$sddm_state" != "not_installed" ]] && return 0

    return 1
}

theme::preview() {
    info "[theme] Preview:"
    echo "  Target accent: $ACCENT_NAME"
    echo "  PRIMARY=$ACCENT_PRIMARY DIM=$ACCENT_DIM DARK=$ACCENT_DARK BRIGHT=$ACCENT_BRIGHT SECONDARY=$ACCENT_SECONDARY"
    echo "  GTK theme: ${PROFILE_THEME_GTK_THEME:-Adwaita-dark}"
    echo "  Cursor: ${PROFILE_THEME_CURSOR_THEME:-Adwaita}"
    echo "  Tela icons: ${PROFILE_THEME_TELA_ICONS:-true}"
    echo "  SDDM theme: $_THEME_SDDM_VARIANT"
    echo ""

    # Template rendering status
    if check_rendered "theme"; then
        echo "  Templates: need re-rendering  [CHANGE]"
    else
        echo "  Templates: up to date  [OK]"
    fi

    # Symlink status (direct + rendered)
    _theme_build_rendered_links
    _THEME_ALL_LINKS=("${_THEME_SYMLINK_MAP[@]}" "${_THEME_RENDERED_SYMLINK_MAP[@]}")
    echo "  Symlinks:"
    preview_links "theme" "_THEME_ALL_LINKS"

    # Icon theme
    if [[ "${PROFILE_THEME_TELA_ICONS:-true}" == "true" ]]; then
        local tela_dir="${_TELA_ICON_BASE}/Tela-${ACCENT_NAME}"
        if [[ -d "$tela_dir" ]]; then
            echo "  Icon theme: Tela-${ACCENT_NAME}  [installed]"
        else
            echo "  Icon theme: Tela-${ACCENT_NAME}  [WILL INSTALL]"
        fi
    else
        local tela_dir="${_TELA_ICON_BASE}/Tela-${ACCENT_NAME}"
        if [[ -d "$tela_dir" ]]; then
            echo "  Icon theme: Tela-${ACCENT_NAME} → remove  [REVERT]"
        else
            echo "  Icon theme: not installed  [OK]"
        fi
    fi

    # SDDM
    local sddm_state
    sddm_state=$(_theme_sddm_state)
    case "$sddm_state" in
        disabled)      echo "  SDDM: disabled by profile  [SKIP]" ;;
        not_installed) echo "  SDDM: not installed  [SKIP]" ;;
        ok)            echo "  SDDM: $_THEME_SDDM_VARIANT  [OK]" ;;
        *)             echo "  SDDM: $_THEME_SDDM_VARIANT  [WILL UPDATE ($sddm_state)]" ;;
    esac
}

theme::apply() {
    # Validate preset exists
    if [[ -z "${COLOR_PRESETS[$ACCENT_NAME]+x}" ]]; then
        die "Unknown accent preset: $ACCENT_NAME (available: ${!COLOR_PRESETS[*]})"
    fi

    # Set up temp directory with cleanup trap (save/restore previous trap)
    _THEME_PREV_TRAP=$(trap -p EXIT | sed "s/^trap -- '//;s/' EXIT$//")
    _THEME_TMPDIR=$(mktemp -d) || die "Failed to create temp directory"
    trap _theme_cleanup EXIT

    info "Accent: $ACCENT_NAME ($ACCENT_PRIMARY)"

    # 0. Render templates
    render_module_templates "theme"
    ok "Theme templates rendered"

    # 1. Deploy symlinks (direct + rendered, with stale cleanup)
    _theme_build_rendered_links
    _THEME_ALL_LINKS=("${_THEME_SYMLINK_MAP[@]}" "${_THEME_RENDERED_SYMLINK_MAP[@]}")
    sync_links "theme" "_THEME_ALL_LINKS"

    # 2. Tela icon theme
    if [[ "${PROFILE_THEME_TELA_ICONS:-true}" == "true" ]]; then
        _theme_install_tela
    else
        local tela_dir="${_TELA_ICON_BASE}/Tela-${ACCENT_NAME}"
        if [[ -d "$tela_dir" ]]; then
            rm -rf "$tela_dir"
            ok "Tela icons: removed (disabled by profile)"
        fi
    fi

    # 3. SDDM (if applicable)
    _theme_apply_sddm

    ok "Theme applied: $ACCENT_NAME"
}

theme::status() {
    local tela="not installed"
    [[ -d "${_TELA_ICON_BASE}/Tela-${ACCENT_NAME}" ]] && tela="installed"

    local sddm="not installed"
    if rpm -q sddm &>/dev/null; then
        sddm=$(grep -oP 'Current=\K.*' /etc/sddm.conf.d/theme.conf 2>/dev/null || echo "unknown")
    fi

    echo "theme: accent=$ACCENT_NAME icon=Tela-${ACCENT_NAME}($tela) sddm=$sddm"
}
