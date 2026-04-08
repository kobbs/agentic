# shellcheck shell=bash
# core/colors.sh -- Color preset loader
# Sourced by other scripts, not executed directly.
# Requires: REPO_ROOT set by caller.
# ---------------------------------------------------------------------------

declare -gA COLOR_PRESETS=()

# ---------------------------------------------------------------------------
# load_all_presets [colors_dir]
# Reads all colors/*.conf files into the COLOR_PRESETS associative array.
# Each entry format: "PRIMARY DIM DARK BRIGHT SECONDARY ANSI"
# Uses its own simple key=value parser -- does NOT touch _CONFIG.
# ---------------------------------------------------------------------------
load_all_presets() {
    local dir="${1:-${REPO_ROOT}/colors}"
    COLOR_PRESETS=()

    local conf
    for conf in "$dir"/*.conf; do
        [[ -f "$conf" ]] || continue

        local -A kv=()
        local line
        while IFS= read -r line || [[ -n "$line" ]]; do
            line="${line#"${line%%[![:space:]]*}"}"
            line="${line%"${line##*[![:space:]]}"}"
            [[ -z "$line" || "$line" == \#* ]] && continue
            local key="${line%%=*}" val="${line#*=}"
            key="${key%"${key##*[![:space:]]}"}"
            val="${val#"${val%%[![:space:]]*}"}"
            kv["$key"]="$val"
        done < "$conf"

        local name="${kv[name]:-}"
        [[ -z "$name" ]] && continue

        COLOR_PRESETS["$name"]="${kv[primary]} ${kv[dim]} ${kv[dark]} ${kv[bright]} ${kv[secondary]} ${kv[ansi]}"
    done
}

# ---------------------------------------------------------------------------
# load_accent
# Determines the target accent color and populates ACCENT_* variables.
# Priority: PROFILE_THEME_ACCENT > ACCENT env var > "green"
# ---------------------------------------------------------------------------
# shellcheck disable=SC2034  # ACCENT_* vars used by callers that source this library
load_accent() {
    local name="${PROFILE_THEME_ACCENT:-${ACCENT:-green}}"

    if [[ -z "${COLOR_PRESETS[$name]+x}" ]]; then
        echo "Warning: accent preset '$name' not found, falling back to green" >&2
        name="green"
    fi

    if [[ -z "${COLOR_PRESETS[$name]+x}" ]]; then
        echo "Error: green preset not found -- load_all_presets must be called first" >&2
        return 1
    fi

    local p d dk br s ansi
    read -r p d dk br s ansi <<< "${COLOR_PRESETS[$name]}"

    ACCENT_NAME="$name"
    ACCENT_PRIMARY="$p"
    ACCENT_DIM="$d"
    ACCENT_DARK="$dk"
    ACCENT_BRIGHT="$br"
    ACCENT_SECONDARY="$s"
    export ACCENT_ANSI="$ansi"
}
