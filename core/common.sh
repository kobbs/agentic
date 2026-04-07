#!/bin/bash

ok() {
    echo -e "\e[32m[OK]\e[0m $*"
}

warn() {
    echo -e "\e[33m[WARN]\e[0m $*"
}

err() {
    echo -e "\e[31m[ERROR]\e[0m $*" >&2
}

detect_gpu() {
    if command -v lspci >/dev/null 2>&1 && lspci | grep -qE "VGA.*AMD.*(Navi|RDNA)"; then
        export _HAS_DISCRETE_AMD_GPU=true
    else
        export _HAS_DISCRETE_AMD_GPU=false
    fi
}

detect_mode() {
    local cache_file="$HOME/.config/shell/.bootstrap-mode"
    if [[ "${PROFILE_SYSTEM_SWAY_SPIN:-auto}" == "true" ]]; then
        export SWAY_SPIN=true
    elif [[ "${PROFILE_SYSTEM_SWAY_SPIN:-auto}" == "false" ]]; then
        export SWAY_SPIN=false
    elif [[ -f "$cache_file" ]] && grep -qxE 'true|false' "$cache_file"; then
        export SWAY_SPIN=$(cat "$cache_file")
    elif rpm -q sway >/dev/null 2>&1; then
        export SWAY_SPIN=true
        mkdir -p "$(dirname "$cache_file")"
        echo "true" > "$cache_file"
    else
        export SWAY_SPIN=false
        mkdir -p "$(dirname "$cache_file")"
        echo "false" > "$cache_file"
    fi
}

find_fedora_version() {
    local base_url="$1"
    local current_ver=$(rpm -E %fedora 2>/dev/null || echo "43")
    for ver in $(seq $current_ver -1 $((current_ver - 3))); do
        local url="${base_url//\$releasever/$ver}"
        if curl -s --head --connect-timeout 5 "$url" | head -n 1 | grep -q '200 OK\|302 Found'; then
            echo "$ver"
            return 0
        fi
    done
    return 1
}
