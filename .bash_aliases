alias ll='ls -alFh'
alias la='ls -A'
alias l='ls -CF'

alias vi="vim"
alias vim="vim"
alias vimrc="vim ~/.vimrc"
alias bashrc="vim ~/.bashrc"
alias tree="tree -I '__pycach*|*.pyc'"

alias glga='git log --graph --all --decorate --pretty=oneline'
alias glg='git log --graph --decorate --pretty=oneline --first-parent'
alias gs='git status'
alias gd='git diff'
alias gau='git add -u'
alias gds='git diff --stat'
alias gitreup='git checkout master && git pull'
alias gca='git commit --amend --no-edit'
alias gbr='git branch --sort=-committerdate | head -n 10'

alias gri="grep -rI"

alias tma="tmux attach -t"

alias wstrip="sed -i '' -E 's/[[:space:]]+\$//'"
alias pwreup="source ~/.bash_passwords"

alias cdp="cd ~/picnic"

alias sva='source "$(ls | grep venv)"/bin/activate'

# --- Git worktree helpers (w*) ---

# List worktree names (strips $HOME/picnic- prefix)
_w-names() {
  local dir
  for dir in "$HOME"/picnic-*/; do
    [ -d "$dir" ] && basename "$dir" | sed 's/^picnic-//'
  done
}

# Tab completion for w-cd, w-serve, w-rm
_w-complete() {
  local cur="${COMP_WORDS[COMP_CWORD]}"
  COMPREPLY=($(compgen -W "$(_w-names)" -- "$cur"))
}

wcreate() {
  local name="$1"
  if [ -z "$name" ]; then
    echo "Usage: w-create <name> [base-branch]"
    return 1
  fi
  local base="${2:-origin/master}"
  git worktree add "$HOME/picnic-$name" -b "$name" "$base" && cd "$HOME/picnic-$name" && yarn workspaces focus --all
}

wcd() {
  local name="$1"
  if [ -z "$name" ]; then
    echo "Usage: w-cd <name>"
    return 1
  fi
  cd "$HOME/picnic-$name"
}

wserve() {
  local name="$1"
  if [ -z "$name" ]; then
    # Try to infer from current directory (e.g. ~/picnic-foo -> foo)
    case "$PWD" in
      "$HOME"/picnic-*)
        name="$(echo "$PWD" | sed "s|^$HOME/picnic-||; s|/.*||")"
        ;;
      *)
        echo "Usage: wserve <name> (or run from inside a worktree)"
        return 1
        ;;
    esac
  fi
  local wtpath="$HOME/picnic-$name"
  if [ ! -d "$wtpath" ]; then
    echo "Worktree not found: $wtpath"
    return 1
  fi
  local origdir="$PWD"
  local servedir="$HOME/picnic"
  local branch
  branch="$(git -C "$wtpath" rev-parse --abbrev-ref HEAD)"
  cd "$servedir" || { cd "$origdir"; return 1; }

  local target_sha
  target_sha="$(git -C "$wtpath" rev-parse HEAD)"

  # Try checkout; if untracked files conflict, remove them and retry
  local checkout_output
  if ! checkout_output="$(git checkout "$target_sha" 2>&1)"; then
    local conflicting
    conflicting="$(echo "$checkout_output" | grep $'^\t' | sed $'s/^\t//')"
    if [ -n "$conflicting" ]; then
      echo "Cleaning conflicting untracked files:"
      while IFS= read -r f; do
        echo "  $f"
        rm -f "$servedir/$f"
      done <<< "$conflicting"
      git checkout "$target_sha" || { cd "$origdir"; return 1; }
    else
      echo "$checkout_output" >&2
      cd "$origdir"; return 1
    fi
  fi

  # Copy any uncommitted changes (staged + unstaged) from the worktree
  local dirty_files
  dirty_files="$(git -C "$wtpath" diff --name-only HEAD)"
  if [ -n "$dirty_files" ]; then
    echo "Copying uncommitted changes:"
    while IFS= read -r f; do
      if [ -f "$wtpath/$f" ]; then
        mkdir -p "$servedir/$(dirname "$f")"
        cp "$wtpath/$f" "$servedir/$f"
        echo "  $f"
      else
        # File was deleted in worktree
        rm -f "$servedir/$f"
        echo "  $f (deleted)"
      fi
    done <<< "$dirty_files"
  fi

  # Also copy any untracked new files
  local untracked
  untracked="$(git -C "$wtpath" ls-files --others --exclude-standard)"
  if [ -n "$untracked" ]; then
    echo "Copying untracked files:"
    while IFS= read -r f; do
      mkdir -p "$servedir/$(dirname "$f")"
      cp "$wtpath/$f" "$servedir/$f"
      echo "  $f"
    done <<< "$untracked"
  fi

  echo "Now serving $branch in detached HEAD"
  cd "$origdir"
}

wrm() {
  local name="$1"
  if [ -z "$name" ]; then
    echo "Usage: w-rm <name>"
    return 1
  fi
  local wtpath="$HOME/picnic-$name"
  if [ ! -d "$wtpath" ]; then
    echo "Worktree not found: $wtpath"
    return 1
  fi
  # Move out if currently inside the worktree
  case "$PWD" in "$wtpath"*) cd "$HOME" ;; esac
  git -C "$HOME/picnic" worktree remove "$wtpath" && echo "Removed worktree: $wtpath"
}

wls() {
  _w-names
}

complete -F _w-complete wcd
complete -F _w-complete wserve
complete -F _w-complete wrm
