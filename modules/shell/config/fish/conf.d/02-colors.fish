# Syntax highlighting colors + accent color definitions
# Template placeholders are resolved by render_module_templates.

status is-interactive; or return

# -- Accent colors (resolved by render_module_templates) -------------------
set -g __accent_primary   "{{ACCENT_PRIMARY}}"
set -g __accent_dim       "{{ACCENT_DIM}}"
set -g __accent_dark      "{{ACCENT_DARK}}"
set -g __accent_bright    "{{ACCENT_BRIGHT}}"
set -g __accent_secondary "{{ACCENT_SECONDARY}}"

# -- Fish syntax highlighting ----------------------------------------------
# Derive bare hex values from accent vars (fish_color_* needs hex without #)
set -l _ap (string replace '#' '' $__accent_primary)
set -l _ab (string replace '#' '' $__accent_bright)
set -l _as (string replace '#' '' $__accent_secondary)

# Dark theme — accent on key elements, muted base
set -g fish_color_normal         brwhite
set -g fish_color_command        $_ap            # commands pop in accent
set -g fish_color_keyword        $_ab            # builtins in bright accent
set -g fish_color_quote          $_as            # strings in secondary
set -g fish_color_redirection    brwhite
set -g fish_color_end            brwhite         # ; and &
set -g fish_color_error          ff6666          # red for errors
set -g fish_color_param          cccccc          # muted — arguments
set -g fish_color_comment        666666          # dim grey
set -g fish_color_selection      --background=333333
set -g fish_color_search_match   --background=333333
set -g fish_color_operator       $_as            # secondary accent
set -g fish_color_escape         $_as            # secondary accent
set -g fish_color_autosuggestion 555555          # very dim
set -g fish_color_cancel         ff6666

# -- Pager (tab completions) -----------------------------------------------
set -g fish_pager_color_progress   $_ap --bold
set -g fish_pager_color_prefix     $_ap --bold
set -g fish_pager_color_completion cccccc
set -g fish_pager_color_description 888888
