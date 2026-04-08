# shellcheck shell=bash
# core/config.sh -- INI profile parser.
# Source this file; do not execute it directly.

# ---------------------------------------------------------------------------
# Global state
# ---------------------------------------------------------------------------

# shellcheck disable=SC2034  # variables used by sourcing scripts

declare -gA _CONFIG=()

# ---------------------------------------------------------------------------
# _parse_ini <file>
# Reads an INI file into the global _CONFIG associative array.
# Keys are stored as "section.key". Sectionless keys use an empty section
# prefix (e.g. ".key"). Later calls overlay earlier values (last write wins).
# ---------------------------------------------------------------------------
_parse_ini() {
    local file="$1"
    [[ -f "$file" ]] || return 0

    local section="" line key value

    while IFS= read -r line || [[ -n "$line" ]]; do
        # Strip leading/trailing whitespace
        line="${line#"${line%%[![:space:]]*}"}"
        line="${line%"${line##*[![:space:]]}"}"

        # Skip blanks and comments
        [[ -z "$line" || "$line" == \#* ]] && continue

        # Section header
        if [[ "$line" =~ ^\[([^]]+)\]$ ]]; then
            section="${BASH_REMATCH[1]}"
            # Trim whitespace from section name
            section="${section#"${section%%[![:space:]]*}"}"
            section="${section%"${section##*[![:space:]]}"}"
            continue
        fi

        # Key = value pair
        if [[ "$line" == *=* ]]; then
            key="${line%%=*}"
            value="${line#*=}"

            # Trim whitespace from key and value
            key="${key#"${key%%[![:space:]]*}"}"
            key="${key%"${key##*[![:space:]]}"}"
            value="${value#"${value%%[![:space:]]*}"}"
            value="${value%"${value##*[![:space:]]}"}"

            _CONFIG["${section}.${key}"]="$value"
        fi
    done < "$file"
}

# ---------------------------------------------------------------------------
# load_profile <base_dir>
# Parses config.default.ini then overlays config.local.ini (later values win).
# Exports PROFILE_SECTION_KEY env vars for every entry in _CONFIG.
# ---------------------------------------------------------------------------
load_profile() {
    local base_dir="$1"

    _CONFIG=()

    _parse_ini "${base_dir}/config.default.ini"
    _parse_ini "${base_dir}/config.local.ini"

    # Warn about sectionless keys (common mistake: commenting out [section] headers)
    local compound_key
    for compound_key in "${!_CONFIG[@]}"; do
        if [[ "$compound_key" == .* ]]; then
            echo "Warning: profiles: key '${compound_key#.}' has no [section] header -- it will be ignored (check config.local.ini)" >&2
        fi
    done

    # Export as PROFILE_SECTION_KEY environment variables
    local section key var_name
    for compound_key in "${!_CONFIG[@]}"; do
        section="${compound_key%%.*}"
        key="${compound_key#*.}"

        # Build var name: PROFILE_SECTION_KEY (uppercased, dashes to underscores)
        var_name="PROFILE_"
        if [[ -n "$section" ]]; then
            var_name+="${section^^}_"
        fi
        var_name+="${key^^}"
        var_name="${var_name//-/_}"

        export "$var_name"="${_CONFIG[$compound_key]}"
    done
}

# ---------------------------------------------------------------------------
# profile_get <section> <key>
# Returns the value for section.key, or empty string if not set.
# ---------------------------------------------------------------------------
profile_get() {
    local section="$1"
    local key="$2"
    printf '%s' "${_CONFIG["${section}.${key}"]:-}"
}

# ---------------------------------------------------------------------------
# validate_profile
# Checks all keys in _CONFIG against a known-key registry.
# Rejects unknown keys and validates boolean types.
# Must be called after load_profile. Exits non-zero on any error.
# ---------------------------------------------------------------------------
validate_profile() {
    local -A _KNOWN_KEYS=(
        # [system]
        ["system.hostname"]=string
        ["system.keyboard_layout"]=string
        ["system.sway_spin"]=tristate
        ["system.firewalld"]=boolean
        ["system.bluetooth"]=boolean
        ["system.tuned"]=boolean
        # [packages]
        ["packages.dnf_update"]=boolean
        ["packages.rpm_fusion"]=boolean
        ["packages.codec_swaps"]=boolean
        ["packages.flatpak"]=boolean
        ["packages.cli_tools"]=boolean
        ["packages.security"]=boolean
        ["packages.rocm"]=boolean
        ["packages.desktop_toolkit"]=string
        ["packages.devops"]=boolean
        ["packages.kvm"]=boolean
        ["packages.protonvpn"]=boolean
        ["packages.firefox_wayland"]=boolean
        # [theme]
        ["theme.accent"]=string
        ["theme.gtk_theme"]=string
        ["theme.icon_theme"]=string
        ["theme.cursor_theme"]=string
        ["theme.tela_icons"]=boolean
        ["theme.sddm_theme"]=string
        # [shell]
        ["shell.docker_alias"]=boolean
        ["shell.qt_env"]=boolean
        ["shell.unset_ssh_askpass"]=boolean
    )

    local errors=0
    local compound_key type val

    for compound_key in "${!_CONFIG[@]}"; do
        # Skip sectionless keys (already warned by load_profile)
        [[ "$compound_key" == .* ]] && continue

        type="${_KNOWN_KEYS[$compound_key]:-}"
        if [[ -z "$type" ]]; then
            echo "ERROR: Unknown profile key '${compound_key}' -- check for typos in config.local.ini" >&2
            (( errors++ ))
            continue
        fi

        val="${_CONFIG[$compound_key]}"

        case "$type" in
            boolean)
                if [[ "$val" != "true" && "$val" != "false" ]]; then
                    echo "ERROR: Profile key '${compound_key}' must be 'true' or 'false', got '${val}'" >&2
                    (( errors++ ))
                fi
                ;;
            tristate)
                if [[ "$val" != "true" && "$val" != "false" && "$val" != "auto" ]]; then
                    echo "ERROR: Profile key '${compound_key}' must be 'true', 'false', or 'auto', got '${val}'" >&2
                    (( errors++ ))
                fi
                ;;
        esac
    done

    if [[ "$errors" -gt 0 ]]; then
        echo "ERROR: ${errors} profile validation error(s). Fix config.local.ini and re-run." >&2
        return 1
    fi

    return 0
}
