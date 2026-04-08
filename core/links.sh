# shellcheck shell=bash
# core/links.sh -- Symlink management library
# Sourced by other scripts, not executed directly.
# Requires: core/common.sh sourced first (provides ok() and warn())

# link_file <src> <dst>
# Idempotent symlink creator with backup of existing files.
link_file() {
    local src="$1"
    local dst="$2"

    if [[ ! -e "$src" ]]; then
        warn "Source does not exist, skipping: $src"
        return 0
    fi

    mkdir -p "$(dirname "$dst")"

    if [[ "$(readlink "$dst" 2>/dev/null)" == "$src" ]]; then
        ok "$dst already linked (skipped)"
        return 0
    fi

    if [[ -L "$dst" ]]; then
        rm "$dst"
    elif [[ -e "$dst" ]]; then
        local bak
        bak="$dst.bak.$(date +%Y%m%d%H%M%S)"
        warn "Backing up existing file: $dst → $bak"
        mv "$dst" "$bak"
    fi

    ln -s "$src" "$dst"
    ok "$dst → $src"
}

# ensure_local_override <dst> [comment_char]
# Create per-machine override file if missing.
ensure_local_override() {
    local dst="$1"
    local comment="${2:-#}"

    if [[ -e "$dst" ]]; then
        ok "Local override exists (kept): $dst"
        return 0
    fi

    mkdir -p "$(dirname "$dst")"
    cat > "$dst" <<EOF
${comment} Local overrides for this machine (not tracked by git).
${comment} Settings here take precedence over the base config.
EOF
    ok "Created local override: $dst"
}

# check_link <src> <dst>
# Returns status string: "ok", "missing", "wrong", "blocked", "src_missing"
check_link() {
    local src="$1" dst="$2"
    [[ ! -e "$src" ]] && { echo "src_missing"; return; }
    [[ ! -e "$dst" && ! -L "$dst" ]] && { echo "missing"; return; }
    [[ "$(readlink "$dst" 2>/dev/null)" == "$src" ]] && { echo "ok"; return; }
    [[ -L "$dst" ]] && { echo "wrong"; return; }
    echo "blocked"
}

# ---------------------------------------------------------------------------
# State-tracked symlink management (State Sync — ARCH.md Section 11)
# ---------------------------------------------------------------------------

# _links_state_dir
# Returns the state directory path for symlink tracking.
_links_state_dir() {
    echo "${XDG_STATE_HOME:-$HOME/.local/state}/v2-modular/links"
}

# sync_links <module_name> <map_array_name>
# Deploys symlinks from the map, removes stale symlinks from previous runs,
# and updates the persistent state file.
#
# Map entries: "src|dst" (2-field) or "src|dst|condition" (3-field).
# src paths are relative to MODULE_DIR.
# Requires: link_file(), evaluate_condition(), MODULE_DIR set.
sync_links() {
    local mod="$1"
    local map_name="$2[@]"
    local map=("${!map_name}")
    local state_dir
    state_dir="$(_links_state_dir)"
    local state_file="${state_dir}/${mod}.list"

    mkdir -p "$state_dir"

    # 1. Deploy desired symlinks, collect destination list
    local desired=()
    local entry
    for entry in "${map[@]}"; do
        IFS='|' read -r src dst cond <<< "$entry"
        # Evaluate condition if present (3-field entries)
        if [[ -n "${cond:-}" ]]; then
            evaluate_condition "$cond" || continue
        fi
        desired+=("$dst")
        local full_src="$src"
        [[ "$src" != /* ]] && full_src="$MODULE_DIR/$src"
        link_file "$full_src" "$dst"
    done

    # 2. Remove stale symlinks from previous run
    if [[ -f "$state_file" ]]; then
        while IFS= read -r old_dst; do
            [[ -z "$old_dst" ]] && continue
            # shellcheck disable=SC2076
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

    # 3. Persist current state (written last for crash safety)
    if [[ ${#desired[@]} -gt 0 ]]; then
        printf "%s\n" "${desired[@]}" > "$state_file"
    else
        : > "$state_file"
    fi
}

# preview_links <module_name> <map_array_name>
# Read-only companion to sync_links. Shows deployment status and stale markers.
# Call from module::preview() functions.
preview_links() {
    local mod="$1"
    local map_name="$2[@]"
    local map=("${!map_name}")
    local state_dir
    state_dir="$(_links_state_dir)"
    local state_file="${state_dir}/${mod}.list"

    # 1. Show status of each desired entry
    local desired=()
    local entry
    for entry in "${map[@]}"; do
        IFS='|' read -r src dst cond <<< "$entry"
        if [[ -n "${cond:-}" ]]; then
            evaluate_condition "$cond" || continue
        fi
        desired+=("$dst")
        local full_src="$src"
        [[ "$src" != /* ]] && full_src="$MODULE_DIR/$src"
        local status
        status=$(check_link "$full_src" "$dst")
        local tag
        case "$status" in
            ok)          tag="[OK]" ;;
            missing)     tag="[WILL CREATE]" ;;
            wrong)       tag="[WILL RELINK]" ;;
            blocked)     tag="[WILL BACKUP + LINK]" ;;
            src_missing) tag="[SOURCE MISSING]" ;;
        esac
        printf "  %-45s → %-45s %s\n" "$src" "$dst" "$tag"
    done

    # 2. Show stale entries that would be removed
    if [[ -f "$state_file" ]]; then
        while IFS= read -r old_dst; do
            [[ -z "$old_dst" ]] && continue
            # shellcheck disable=SC2076
            if [[ ! " ${desired[*]} " =~ " ${old_dst} " ]]; then
                if [[ -L "$old_dst" ]]; then
                    printf "  %-45s %s\n" "$old_dst" "[STALE — will remove]"
                elif [[ -e "$old_dst" ]]; then
                    printf "  %-45s %s\n" "$old_dst" "[STALE — kept (not a symlink)]"
                fi
            fi
        done < "$state_file"
    fi
}
