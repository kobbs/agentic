#!/bin/bash

declare -A _PROFILE_DATA

load_profile() {
    local file="$1"
    local section=""
    if [[ ! -f "$file" ]]; then
        return 0
    fi
    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line%%#*}" # remove comments
        line="${line#"${line%%[![:space:]]*}"}" # trim leading
        line="${line%"${line##*[![:space:]]}"}" # trim trailing
        if [[ -z "$line" ]]; then continue; fi

        if [[ "$line" =~ ^\[(.*)\]$ ]]; then
            section="${BASH_REMATCH[1]}"
            section="${section^^}"
        elif [[ "$line" =~ ^([^=]+)=(.*)$ ]]; then
            local key="${BASH_REMATCH[1]}"
            local val="${BASH_REMATCH[2]}"
            key="${key#"${key%%[![:space:]]*}"}"
            key="${key%"${key##*[![:space:]]}"}"
            key="${key^^}"
            val="${val#"${val%%[![:space:]]*}"}"
            val="${val%"${val##*[![:space:]]}"}"
            _PROFILE_DATA["${section}_${key}"]="$val"
            export "PROFILE_${section}_${key}"="$val"
        fi
    done < "$file"
}

profile_get() {
    local section="${1^^}"
    local key="${2^^}"
    echo "${_PROFILE_DATA["${section}_${key}"]:-}"
}
