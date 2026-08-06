# System-wide .bashrc file

clean_bash_hist() {
    history -c
    > ~/.bash_history
    unset HISTFILE
}
trap clean_bash_hist EXIT

# Continue if running interactively
[[ $- == *i* ]] || return 0

[ \! -s /etc/shinit ] || . /etc/shinit
