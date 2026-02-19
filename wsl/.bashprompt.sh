# shellcheck disable=SC2148
__prompt_command() {
    local git_dir common_dir toplevel branch
    git_dir=$(git rev-parse --git-dir 2>/dev/null) || { PS1="\[\033[1;34m\]\w\[\033[0m\] \$ "; return; }
    common_dir=$(git rev-parse --git-common-dir 2>/dev/null)

    # Worktree detection: git_dir differs from common_dir in worktrees
    # Canonicalize both paths before comparing to avoid false positives
    # from mixed relative/absolute path formats
    if [[ "$(cd "$git_dir" 2>/dev/null && pwd -P)" != "$(cd "$common_dir" 2>/dev/null && pwd -P)" ]]; then
        toplevel=$(git rev-parse --show-toplevel 2>/dev/null)
        local wt_name=${toplevel##*/}
        local status="" counts
        local modified=0 staged=0 ahead=0 behind=0

        # Single git status call, single awk pass for both counts
        # M: worktree changes (modified/deleted) + untracked files
        # S: staged changes (index has M, A, D, R, or C)
        read -r modified staged < <(git status --porcelain 2>/dev/null | awk '
            /^\?\?|^.[MD]/ { m++ }
            /^[MADRC]/ { s++ }
            END { print m+0, s+0 }
        ')

        # shellcheck disable=SC1083
        if counts=$(git rev-list --left-right --count @{upstream}...HEAD 2>/dev/null); then
            behind=${counts%%	*}
            ahead=${counts##*	}
        fi

        ((modified)) && status+="M:$modified "
        ((staged)) && status+="S:$staged "
        ((ahead)) && status+="↑$ahead "
        ((behind)) && status+="↓$behind "

        if [[ -n "$status" ]]; then
            PS1="\[\033[1;35m\]$wt_name \[\033[0;33m\](${status% })\[\033[0m\] \$ "
        else
            PS1="\[\033[1;35m\]$wt_name\[\033[0m\] \$ "
        fi
    else
        branch=$(git --no-optional-locks symbolic-ref --short HEAD 2>/dev/null || git --no-optional-locks rev-parse --short HEAD 2>/dev/null)
        if [[ -n "$branch" ]]; then
            PS1="\[\033[1;34m\]\w \[\033[0;36m\](\[\033[1;31m\]$branch\[\033[0;36m\])\[\033[0m\] \$ "
        else
            PS1="\[\033[1;34m\]\w\[\033[0m\] \$ "
        fi
    fi
}
PROMPT_COMMAND=__prompt_command
export PROMPT_DIRTRIM=4
