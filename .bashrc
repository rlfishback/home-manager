PS1='\[\e[1;33m\]\w\[\e[0m\]\$ '

# Append history to the history file rather than overwriting it.
shopt -s histappend

# Ignore commands starting with a space, and ignore duplicates.
export HISTCONTROL=ignoreboth

# Increase the maximum number of commands to store in history (in memory and file).
# Default values are 1000 for HISTSIZE and 2000 for HISTFILESIZE, {Link: according to Cherry Servers https://www.cherryservers.com/blog/a-complete-guide-to-linux-bash-history}.
export HISTSIZE=100000 
export HISTFILESIZE=100000

# Immediately append and reload history after each command.
# This ensures that history is kept up-to-date across multiple sessions,
# including potentially isolated Nix shells.
# $PROMPT_COMMAND is preserved to avoid interfering with other configurations.
export PROMPT_COMMAND="history -a; history -c; history -r; ${PROMPT_COMMAND}"

