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
alias gds='git diff --stat'
alias gitreup='git checkout master && git pull'
alias gca='git commit --amend --no-edit'
alias gbr='git branch --sort=-committerdate | head -n 10'

alias gri="grep -rI"

alias tma="tmux attach -t"

alias wstrip="sed -i '' -E 's/[[:space:]]+\$//'"
alias pwreup="source ~/.bash_passwords"

alias cdp="cd ~/repos/picnic"

alias sva='source "$(ls | grep venv)"/bin/activate'
