#!/bin/bash

declare -A COLOR_PRESETS

load_all_presets() {
    for f in colors/*.conf; do
        if [[ -f "$f" ]]; then
            local name=""
            while IFS= read -r line || [[ -n "$line" ]]; do
                if [[ "$line" =~ ^name[[:space:]]*=[[:space:]]*(.*)$ ]]; then
                    name="${BASH_REMATCH[1]}"
                    break
                fi
            done < "$f"
            if [[ -n "$name" ]]; then
                COLOR_PRESETS["$name"]="$f"
            fi
        fi
    done
}

load_accent() {
    local preset="${PROFILE_THEME_ACCENT:-green}"
    local preset_file="${COLOR_PRESETS[$preset]:-}"

    if [[ -z "$preset_file" ]]; then
        preset_file="colors/green.conf" # fallback
    fi

    if [[ -f "$preset_file" ]]; then
        while IFS= read -r line || [[ -n "$line" ]]; do
            if [[ "$line" =~ ^([a-z]+)[[:space:]]*=[[:space:]]*(.*)$ ]]; then
                local key="${BASH_REMATCH[1]}"
                local val="${BASH_REMATCH[2]}"
                key="${key^^}"
                export "ACCENT_${key}"="$val"
                # bare hex (no #)
                if [[ "$val" == \#* ]]; then
                    export "ACCENT_${key}_BARE"="${val:1}"
                fi
            fi
        done < "$preset_file"
    fi
}
