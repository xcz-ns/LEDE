# System-wide .bashrc file

clean_bash_hist() {
    history -c
    > ~/.bash_history
    unset HISTFILE
}
trap clean_bash_hist EXIT

export PS1="\[\033[31m\]\u\[\033[0m\]@\[\033[36m\]\h\[\033[0m\]:\[\033[34m\]\w\[\033[0m\]# "

# Continue if running interactively
[[ $- == *i* ]] || return 0

[ \! -s /etc/shinit ] || . /etc/shinit
