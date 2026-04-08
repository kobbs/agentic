# shellcheck shell=bash
# modules/shell/module.sh -- Shell and terminal configuration module.
# Source this file; do not execute it directly.
#
# Handles: bootstrap-env.sh generation, .bashrc sourcing, bash prompt +
#          completions, Fish shell, Kitty terminal, tmux.
#
# Assumes core libs sourced. MODULE_DIR set by orchestrator.
# link_file(), check_link(), ensure_local_override() available.

# ---------------------------------------------------------------------------
# Template map: files with {{PLACEHOLDER}} syntax, rendered to staging dir
# ---------------------------------------------------------------------------

_SHELL_TEMPLATE_MAP=(
    "config/bash/prompt.sh"
    "config/fish/conf.d/02-colors.fish"
    "config/kitty/kitty.conf"
    "config/tmux/tmux.conf"
)

# Rendered symlink destinations (custom mapping — prompt.sh goes to ~/.config/shell/, not ~/.config/bash/)
_SHELL_RENDERED_SYMLINK_MAP=()
_shell_build_rendered_links() {
    _SHELL_RENDERED_SYMLINK_MAP=(
        "${RENDERED_DIR}/shell/config/bash/prompt.sh|$HOME/.config/shell/prompt.sh"
        "${RENDERED_DIR}/shell/config/fish/conf.d/02-colors.fish|$HOME/.config/fish/conf.d/02-colors.fish"
        "${RENDERED_DIR}/shell/config/kitty/kitty.conf|$HOME/.config/kitty/kitty.conf"
        "${RENDERED_DIR}/shell/config/tmux/tmux.conf|$HOME/.config/tmux/tmux.conf"
    )
}

# ---------------------------------------------------------------------------
# Declarative symlink map
# Format: "source_relative|target_absolute|condition"
# Conditions: "always", "sway", "fish"
# source paths are relative to MODULE_DIR
# ---------------------------------------------------------------------------

_SHELL_SYMLINK_MAP=(
    # Bash (non-templated)
    "config/bash/completions.sh|$HOME/.config/shell/completions.sh|always"

    # Fish (conditional, non-templated)
    "config/fish/config.fish|$HOME/.config/fish/config.fish|fish"
    "config/fish/conf.d/01-environment.fish|$HOME/.config/fish/conf.d/01-environment.fish|fish"
    "config/fish/conf.d/03-abbreviations.fish|$HOME/.config/fish/conf.d/03-abbreviations.fish|fish"
    "config/fish/conf.d/04-keybinds.fish|$HOME/.config/fish/conf.d/04-keybinds.fish|fish"
    "config/fish/functions/fish_prompt.fish|$HOME/.config/fish/functions/fish_prompt.fish|fish"
    "config/fish/functions/fish_right_prompt.fish|$HOME/.config/fish/functions/fish_right_prompt.fish|fish"
    "config/fish/functions/fish_greeting.fish|$HOME/.config/fish/functions/fish_greeting.fish|fish"
    "config/fish/functions/fish_mode_prompt.fish|$HOME/.config/fish/functions/fish_mode_prompt.fish|fish"
    "config/fish/functions/md.fish|$HOME/.config/fish/functions/md.fish|fish"
)

# Local override files (created once, never overwritten)
# Format: "target|comment_char|condition"
_SHELL_LOCAL_OVERRIDES=(
    "$HOME/.config/fish/config.local.fish|#|fish"
    "$HOME/.config/kitty/config.local|#|always"
    "$HOME/.config/tmux/local.conf|#|always"
)

_SHELL_ENV_FILE="$HOME/.config/shell/bootstrap-env.sh"

# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

_shell_ensure_bashrc_line() {
    local marker="$1" line="$2"
    [[ -f "$HOME/.bashrc" ]] || touch "$HOME/.bashrc"
    grep -qF "$marker" "$HOME/.bashrc" 2>/dev/null \
        || echo "$line" >> "$HOME/.bashrc" \
        || die "Failed to append to .bashrc"
}

# _shell_generate_env
# Emits the full content of bootstrap-env.sh to stdout.
# Each block is gated by a [shell] profile toggle.
_shell_generate_env() {
    cat <<'HEADER'
# Managed by ./setup shell
# Do not edit manually; changes will be overwritten.
HEADER

    # Unconditional -- podman is always installed by the packages module
    if [[ "${PROFILE_SHELL_DOCKER_ALIAS:-true}" == "true" ]]; then
        cat <<'BLOCK'

alias docker=podman
export KIND_EXPERIMENTAL_PROVIDER=podman
BLOCK
    fi

    # Unconditional -- Qt theming requires these env vars for plasma-integration
    if [[ "${PROFILE_SHELL_QT_ENV:-true}" == "true" ]]; then
        cat <<'BLOCK'

export QT_QPA_PLATFORMTHEME=kde
export QT_STYLE_OVERRIDE=Breeze
BLOCK
    fi

    if [[ "${PROFILE_SHELL_UNSET_SSH_ASKPASS:-true}" == "true" ]]; then
        cat <<'BLOCK'

# kde-settings ships /etc/profile.d/kde-openssh-askpass.sh which sets
# SSH_ASKPASS=/usr/bin/ksshaskpass, but ksshaskpass is not installed.
# This breaks git HTTPS credential prompts. Unset unconditionally.
unset SSH_ASKPASS
BLOCK
    fi
}

# ---------------------------------------------------------------------------
# Module contract
# ---------------------------------------------------------------------------

shell::init() { :; }

shell::check() {
    # Check bootstrap-env.sh content
    if [[ -f "$_SHELL_ENV_FILE" ]]; then
        local tmp
        tmp=$(mktemp) || die "Failed to create temp file"
        _shell_generate_env > "$tmp"
        if ! cmp -s "$tmp" "$_SHELL_ENV_FILE"; then
            rm -f "$tmp"
            return 0
        fi
        rm -f "$tmp"
    else
        return 0
    fi

    # Check .bashrc source lines
    grep -qF "bootstrap-env.sh" "$HOME/.bashrc" 2>/dev/null || return 0
    grep -qF "prompt.sh" "$HOME/.bashrc" 2>/dev/null || return 0
    grep -qF "completions.sh" "$HOME/.bashrc" 2>/dev/null || return 0

    # Check config symlinks
    local entry
    for entry in "${_SHELL_SYMLINK_MAP[@]}"; do
        IFS='|' read -r rel dst cond <<< "$entry"
        evaluate_condition "$cond" || continue
        local status
        status=$(check_link "$MODULE_DIR/$rel" "$dst")
        [[ "$status" != "ok" ]] && return 0
    done

    # Check rendered templates
    check_rendered "shell" && return 0

    # Check rendered symlinks
    _shell_build_rendered_links
    local r_entry
    for r_entry in "${_SHELL_RENDERED_SYMLINK_MAP[@]}"; do
        IFS='|' read -r r_src r_dst <<< "$r_entry"
        local r_status
        r_status=$(check_link "$r_src" "$r_dst")
        [[ "$r_status" != "ok" ]] && return 0
    done

    return 1
}

shell::preview() {
    info "[shell] Preview:"

    # bootstrap-env.sh
    if [[ -f "$_SHELL_ENV_FILE" ]]; then
        local tmp
        tmp=$(mktemp) || die "Failed to create temp file"
        _shell_generate_env > "$tmp"
        if ! cmp -s "$tmp" "$_SHELL_ENV_FILE"; then
            echo "  Changes to bootstrap-env.sh:"
            diff "$_SHELL_ENV_FILE" "$tmp" | sed 's/^/    /' || true
        else
            echo "  bootstrap-env.sh: up to date  [OK]"
        fi
        rm -f "$tmp"
    else
        echo "  Will create: ~/.config/shell/bootstrap-env.sh"
    fi

    # .bashrc source lines
    if ! grep -qF "bootstrap-env.sh" "$HOME/.bashrc" 2>/dev/null; then
        echo "  .bashrc: will add bootstrap-env.sh source line  [CHANGE]"
    fi

    # Template rendering status
    if check_rendered "shell"; then
        echo "  Templates: need re-rendering  [CHANGE]"
    else
        echo "  Templates: up to date  [OK]"
    fi

    # Config symlinks
    preview_links "shell" "_SHELL_SYMLINK_MAP"
}

shell::apply() {
    # 1. Generate bootstrap-env.sh
    local tmp
    tmp=$(mktemp) || die "Failed to create temp file"
    _shell_generate_env > "$tmp"
    mkdir -p "$HOME/.config/shell"

    if ! cmp -s "$tmp" "$_SHELL_ENV_FILE" 2>/dev/null; then
        mv "$tmp" "$_SHELL_ENV_FILE" || die "Failed to write bootstrap-env.sh"
        ok "bootstrap-env.sh updated"
    else
        rm -f "$tmp"
    fi

    # 2. Render templates
    render_module_templates "shell"
    ok "Shell templates rendered"

    # 3. Deploy config symlinks (direct + rendered, with stale cleanup)
    _shell_build_rendered_links
    _SHELL_ALL_LINKS=("${_SHELL_SYMLINK_MAP[@]}" "${_SHELL_RENDERED_SYMLINK_MAP[@]}")
    sync_links "shell" "_SHELL_ALL_LINKS"

    # 4. Create local overrides (created once, never overwritten)
    local entry
    for entry in "${_SHELL_LOCAL_OVERRIDES[@]}"; do
        IFS='|' read -r dst comment cond <<< "$entry"
        evaluate_condition "$cond" || continue
        ensure_local_override "$dst" "$comment"
    done

    # 5. .bashrc source lines (idempotent)
    # shellcheck disable=SC2016  # single quotes intentional -- $HOME expands at runtime
    _shell_ensure_bashrc_line "bootstrap-env.sh" \
        '[[ -f "$HOME/.config/shell/bootstrap-env.sh" ]] && source "$HOME/.config/shell/bootstrap-env.sh"'
    # shellcheck disable=SC2016
    _shell_ensure_bashrc_line "prompt.sh" \
        '[[ -f "$HOME/.config/shell/prompt.sh" ]] && source "$HOME/.config/shell/prompt.sh"'
    # shellcheck disable=SC2016
    _shell_ensure_bashrc_line "completions.sh" \
        '[[ -f "$HOME/.config/shell/completions.sh" ]] && source "$HOME/.config/shell/completions.sh"'

    ok "Shell configs deployed"
}

shell::status() {
    local total=0 linked=0
    local entry
    for entry in "${_SHELL_SYMLINK_MAP[@]}"; do
        IFS='|' read -r rel dst cond <<< "$entry"
        evaluate_condition "$cond" || continue
        total=$((total + 1))
        [[ "$(check_link "$MODULE_DIR/$rel" "$dst")" == "ok" ]] && linked=$((linked + 1))
    done

    _shell_build_rendered_links
    for entry in "${_SHELL_RENDERED_SYMLINK_MAP[@]}"; do
        IFS='|' read -r src dst <<< "$entry"
        total=$((total + 1))
        [[ "$(check_link "$src" "$dst")" == "ok" ]] && linked=$((linked + 1))
    done

    local env_status="not deployed"
    [[ -f "$_SHELL_ENV_FILE" ]] && env_status="deployed"

    echo "shell: ${linked}/${total} symlinks, env ${env_status}"
}
