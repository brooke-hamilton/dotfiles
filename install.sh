#!/bin/bash
set -e

# NOTE: This script is interactive - you will be asked for sudo password and GitHub credentials (twice).

# When WSL is enabled but not activated, and Docker Desktop is installed, Docker Desktop becomes the default WSL distro.
# Change the default Ubuntu.
wsl.exe --set-default Ubuntu

current_dir=$(dirname "$0")
# shellcheck disable=SC1091
source "$current_dir/wsl/setup_wsl.sh"
# shellcheck disable=SC1091
source "$current_dir/git/configure_git.sh"
