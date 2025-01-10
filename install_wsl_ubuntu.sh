#!/bin/bash
set -e

# Run this in the WSL Ubuntu distro after manually running the OOBE setup.

# NOTE: This script is interactive - you will be asked for sudo password and GitHub credentials. The GH credential
# prompt will happen twice - once for a scope upgrade and once to reset the scope.

# When WSL is enabled but not activated, and Docker Desktop is installed, Docker Desktop becomes the default WSL distro.
# Change the default Ubuntu.
wsl.exe --set-default Ubuntu

current_dir=$(dirname "$0")
# shellcheck disable=SC1091
source "$current_dir/wsl/setup_wsl.sh"
# shellcheck disable=SC1091
source "$current_dir/git/configure_git.sh"
