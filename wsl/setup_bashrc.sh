#!/bin/bash

#source ~/.bashprompt
#export GITHUB_TOKEN=$(gh.exe auth token)
# Function to safely append to bashrc if not already present
add_to_bashrc() {
    local line="$1"
    if ! grep -qF "$line" ~/.bashrc; then
        echo "$line" >> ~/.bashrc
        echo "Added '$line' to ~/.bashrc"
    else
        echo "'$line' already exists in ~/.bashrc"
    fi
}

echo "adding configuration to ~/.bashrc"

# Get the full path to .bashprompt.sh in the same directory as this script
SCRIPT_DIR="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"
BASHPROMPT_PATH="$SCRIPT_DIR/.bashprompt.sh"
if [ ! -f "$BASHPROMPT_PATH" ]; then
    echo "Warning: $BASHPROMPT_PATH does not exist"
else
    echo "Found .bashprompt.sh at: $BASHPROMPT_PATH"
fi

add_to_bashrc "source $BASHPROMPT_PATH"
# shellcheck disable=SC2016
add_to_bashrc 'export GITHUB_TOKEN=$(gh.exe auth token)'

echo ".bashrc update complete."
