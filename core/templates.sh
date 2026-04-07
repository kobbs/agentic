#!/bin/bash

render_template() {
    local src="$1"
    local dst="$2"
    mkdir -p "$(dirname "$dst")"

    # Simple sed replacement for placeholders
    sed -e "s/{{ACCENT_PRIMARY}}/${ACCENT_PRIMARY:-}/g" \
        -e "s/{{ACCENT_DIM}}/${ACCENT_DIM:-}/g" \
        -e "s/{{ACCENT_DARK}}/${ACCENT_DARK:-}/g" \
        -e "s/{{ACCENT_BRIGHT}}/${ACCENT_BRIGHT:-}/g" \
        -e "s/{{ACCENT_SECONDARY}}/${ACCENT_SECONDARY:-}/g" \
        -e "s/{{ACCENT_PRIMARY_BARE}}/${ACCENT_PRIMARY_BARE:-}/g" \
        -e "s/{{PROFILE_THEME_GTK_THEME}}/${PROFILE_THEME_GTK_THEME:-}/g" \
        -e "s/{{PROFILE_THEME_CURSOR_THEME}}/${PROFILE_THEME_CURSOR_THEME:-}/g" \
        "$src" > "${dst}.tmp"

    if ! cmp -s "${dst}.tmp" "$dst"; then
        mv "${dst}.tmp" "$dst"
    else
        rm "${dst}.tmp"
    fi
}

render_module_templates() {
    local mod="$1"
    local map_name="$2[@]"
    local map=("${!map_name}")
    local out_dir="$HOME/.local/share/v2-modular/rendered/$mod"

    for src in "${map[@]}"; do
        render_template "$MODULE_DIR/$src" "$out_dir/$src"
    done
}
