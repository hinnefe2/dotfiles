# some more ls aliases
alias ll='ls -alFh'
alias la='ls -A'
alias l='ls -CF'

alias workon="source activate"
alias workoff="source deactivate"

alias vi="nvim"
alias vim="nvim"
alias vimrc="nvim ~/.vimrc"
alias tree="tree -I '__pycach*|*.pyc'"

alias nb="screen -r jupyter"

alias glga='git log --graph --all --decorate --pretty=oneline'
alias glg='git log --graph --decorate --pretty=oneline'
alias gs='git status'
alias gd='git diff'
alias gds='git diff --stat'
alias gitreup='git checkout master && git fetch upstream && git rebase upstream/master && git push'

alias pbimport="printf 'import pandas as pd\nimport matplotlib.pyplot as plt\nimport seaborn as sns\nimport numpy as np\n\n%%matplotlib inline' | pbcopy"

alias tma="tmux attach -t"

alias wstrip="sed -i '' -E 's/[[:space:]]+\$//'"
alias pwreup="source ~/.bash_passwords"
