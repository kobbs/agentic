#!/bin/bash

link_file() {
    local src="$1"
    local dst="$2"
    mkdir -p "$(dirname "$dst")"
    if [[ -e "$dst" && ! -L "$dst" ]]; then
        warn "File $dst exists and is not a symlink. Skipping."
    else
        ln -sf "$src" "$dst"
    fi
}

evaluate_condition() {
    local cond="$1"
    if [[ "$cond" == "always" ]]; then return 0; fi
    if [[ "$cond" == "sway" ]] && [[ "${PROFILE_SYSTEM_SWAY_SPIN:-auto}" != "false" ]]; then return 0; fi
    # Add more conditions as needed
    return 1
}

sync_links() {
    local mod="$1"
    local map_name="$2[@]"
    local map=("${!map_name}")
    local state_dir="$HOME/.local/state/v2-modular/links"
    local state_file="${state_dir}/${mod}.list"

    mkdir -p "$state_dir"

    local desired=()
    for entry in "${map[@]}"; do
        IFS='|' read -r src dst cond <<< "$entry"
        if [[ -n "${cond:-}" ]]; then
            evaluate_condition "$cond" || continue
        fi
        desired+=("$dst")
        link_file "$MODULE_DIR/$src" "$dst"
    done

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

    printf "%s\n" "${desired[@]}" > "$state_file"
}
