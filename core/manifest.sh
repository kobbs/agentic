#!/bin/bash

declare -A MODULE_ORDER
declare -A MODULE_CONDITION
declare -A MODULE_REQUIRES
declare -a DISCOVERED_MODULES

parse_manifest() {
    local manifest="$1"
    local mod_name=""
    local order="99"
    local cond="always"
    local req=""

    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ "$line" =~ ^name:[[:space:]]*(.*)$ ]]; then
            mod_name="${BASH_REMATCH[1]}"
        elif [[ "$line" =~ ^order:[[:space:]]*(.*)$ ]]; then
            order="${BASH_REMATCH[1]}"
        elif [[ "$line" =~ ^condition:[[:space:]]*(.*)$ ]]; then
            cond="${BASH_REMATCH[1]}"
        elif [[ "$line" =~ ^[[:space:]]*-[[:space:]]*(.*)$ ]] && [[ -n "$in_requires" ]]; then
            req="$req ${BASH_REMATCH[1]}"
        elif [[ "$line" =~ ^requires: ]]; then
            in_requires=1
        elif [[ "$line" =~ ^provides: ]]; then
            in_requires=
        fi
    done < "$manifest"

    if [[ -n "$mod_name" ]]; then
        MODULE_ORDER["$mod_name"]="$order"
        MODULE_CONDITION["$mod_name"]="$cond"
        MODULE_REQUIRES["$mod_name"]="$req"
        DISCOVERED_MODULES+=("$mod_name")
    fi
}

discover_modules() {
    for manifest in modules/*/manifest.yaml; do
        if [[ -f "$manifest" ]]; then
            parse_manifest "$manifest"
        fi
    done

    # Sort modules by order
    IFS=$'\n' SORTED_MODULES=($(for m in "${DISCOVERED_MODULES[@]}"; do echo "${MODULE_ORDER[$m]} $m"; done | sort -n | awk '{print $2}'))
    unset IFS
}
