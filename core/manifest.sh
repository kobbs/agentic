# shellcheck shell=bash
# core/manifest.sh -- Lightweight YAML parser for module manifests.
# Source this file; do not execute it directly.
#
# Handles only the flat key-value subset used by manifest.yaml files:
#   - Scalar values:  key: value
#   - Simple lists:   key:
#                       - item
#   - Comments (#) and empty lines are skipped.

# ---------------------------------------------------------------------------
# Global state
# ---------------------------------------------------------------------------

declare -ga _MODULE_NAMES=()
declare -gA _MODULE_DIRS=()

# ---------------------------------------------------------------------------
# _manifest_key_to_var <key>
# Converts a YAML key to an uppercase bash-safe variable name segment.
# Uppercases and replaces dashes with underscores.
# ---------------------------------------------------------------------------
_manifest_key_to_var() {
    local key="$1"
    key="${key^^}"
    key="${key//-/_}"
    printf '%s' "$key"
}

# ---------------------------------------------------------------------------
# parse_manifest <file> <prefix>
# Parses a manifest.yaml into bash variables prefixed with <prefix>_.
#
# Scalars:  ${PREFIX}_${KEY}=value
# Lists:    ${PREFIX}_${KEY}=("item1" "item2" ...)
#
# Example: parse_manifest modules/sway/manifest.yaml SWAY
#   → sets SWAY_NAME, SWAY_ORDER, SWAY_REQUIRES=("packages" "shell"), etc.
# ---------------------------------------------------------------------------
parse_manifest() {
    local file="$1"
    local prefix="$2"

    [[ -f "$file" ]] || { echo "parse_manifest: file not found: ${file}" >&2; return 1; }

    local line key varname value
    local current_list_var=""
    # _list_items: associative array keyed by varname, value is newline-joined items
    # _list_keys: ordered list of varnames that are arrays
    local -A _list_items=()
    local -a _list_keys=()
    local found k

    while IFS= read -r line || [[ -n "$line" ]]; do
        # Strip trailing whitespace
        line="${line%"${line##*[![:space:]]}"}"

        # Skip empty lines and comments
        [[ -z "$line" || "$line" == \#* ]] && continue

        # List item: line starts with whitespace followed by "- "
        if [[ "$line" =~ ^[[:space:]]+-[[:space:]]+(.*) ]]; then
            value="${BASH_REMATCH[1]}"
            value="${value%"${value##*[![:space:]]}"}"
            if [[ -n "$current_list_var" ]]; then
                # Append item (newline-delimited; YAML values are single-line)
                _list_items["$current_list_var"]+="${value}"$'\n'
                # Track key order (only add once)
                found=0
                for k in "${_list_keys[@]}"; do
                    [[ "$k" == "$current_list_var" ]] && found=1 && break
                done
                [[ $found -eq 0 ]] && _list_keys+=("$current_list_var")
            fi
            continue
        fi

        # Key: value pair (top-level, no leading whitespace)
        if [[ "$line" =~ ^([A-Za-z_-]+):[[:space:]]*(.*) ]]; then
            key="${BASH_REMATCH[1]}"
            value="${BASH_REMATCH[2]}"
            value="${value%"${value##*[![:space:]]}"}"

            varname="${prefix}_$(_manifest_key_to_var "$key")"

            if [[ -z "$value" ]]; then
                # Empty value — start of a list (or empty scalar treated as empty list)
                current_list_var="$varname"
                # Register key if not already present
                found=0
                for k in "${_list_keys[@]}"; do
                    [[ "$k" == "$varname" ]] && found=1 && break
                done
                [[ $found -eq 0 ]] && _list_keys+=("$varname")
                # Initialise storage to empty string if not set
                [[ -v "_list_items[$varname]" ]] || _list_items["$varname"]=""
            else
                # Scalar value — close any open list context
                current_list_var=""
                printf -v "$varname" '%s' "$value"
            fi
            continue
        fi
    done < "$file"

    # Materialise list variables as bash arrays
    local lvar items_raw item
    local -a arr
    for lvar in "${_list_keys[@]}"; do
        items_raw="${_list_items[$lvar]}"
        arr=()
        if [[ -n "$items_raw" ]]; then
            while IFS= read -r item; do
                [[ -n "$item" ]] && arr+=("$item")
            done <<< "$items_raw"
        fi
        # shellcheck disable=SC2294  # eval required for dynamic array assignment
        eval "${lvar}=(\"\${arr[@]+\${arr[@]}}\")"
    done
}

# ---------------------------------------------------------------------------
# discover_modules <modules_dir>
# Scans <modules_dir>/*/manifest.yaml, parses each manifest, then populates:
#   _MODULE_NAMES  — module names sorted by their order field (numeric)
#   _MODULE_DIRS   — associative array: module_name → absolute path
# ---------------------------------------------------------------------------
discover_modules() {
    local modules_dir
    modules_dir="$(realpath "$1")"

    _MODULE_NAMES=()
    _MODULE_DIRS=()

    local manifest module_dir module_name prefix order_var order_val
    local -a _raw_names=()
    local -A _raw_orders=()

    for manifest in "${modules_dir}"/*/manifest.yaml; do
        [[ -f "$manifest" ]] || continue

        module_dir="$(dirname "$manifest")"
        module_name="$(basename "$module_dir")"
        prefix="$(_manifest_key_to_var "$module_name")"

        parse_manifest "$manifest" "$prefix"

        order_var="${prefix}_ORDER"
        order_val="${!order_var:-999}"

        _raw_names+=("$module_name")
        _raw_orders["$module_name"]="$order_val"
        _MODULE_DIRS["$module_name"]="$module_dir"
    done

    # Sort module names by their numeric order field
    local sorted name
    sorted=$(
        for name in "${_raw_names[@]}"; do
            printf '%s %s\n' "${_raw_orders[$name]}" "$name"
        done | sort -n | awk '{print $2}'
    )

    while IFS= read -r module_name; do
        [[ -n "$module_name" ]] && _MODULE_NAMES+=("$module_name")
    done <<< "$sorted"
}

# ---------------------------------------------------------------------------
# validate_module_requires <module_name>
# Checks that all modules listed in this module's REQUIRES array exist in
# _MODULE_NAMES. Prints warnings for missing deps. Always returns 0.
# ---------------------------------------------------------------------------
validate_module_requires() {
    local module_name="$1"
    local prefix dep name found
    prefix="$(_manifest_key_to_var "$module_name")"

    local requires_var="${prefix}_REQUIRES"
    local decl
    decl="$(declare -p "$requires_var" 2>/dev/null)"

    # If the variable isn't declared as an array, nothing to check
    [[ "$decl" == *"declare -a"* ]] || return 0

    local -a requires=()
    # shellcheck disable=SC2294  # eval required for dynamic array expansion
    eval "requires=(\"\${${requires_var}[@]+\${${requires_var}[@]}}\")"

    for dep in "${requires[@]}"; do
        found=0
        for name in "${_MODULE_NAMES[@]+"${_MODULE_NAMES[@]}"}"; do
            [[ "$name" == "$dep" ]] && found=1 && break
        done
        if [[ $found -eq 0 ]]; then
            echo "Warning: module '${module_name}' requires '${dep}' which is not in the discovered module list" >&2
        fi
    done

    return 0
}

# ---------------------------------------------------------------------------
# evaluate_condition <condition>
# Returns 0 if the condition is satisfied.
# Handles: "always" or "" → always true
#          "sway"         → true if sway is on PATH
#          "fish"         → true if fish is on PATH
# ---------------------------------------------------------------------------
evaluate_condition() {
    local condition="${1:-always}"

    case "$condition" in
        always|"")
            return 0
            ;;
        sway)
            command -v sway &>/dev/null
            ;;
        fish)
            command -v fish &>/dev/null
            ;;
        *)
            echo "Warning: unknown condition '${condition}', treating as false" >&2
            return 1
            ;;
    esac
}
