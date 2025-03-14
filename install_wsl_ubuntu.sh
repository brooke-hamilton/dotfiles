#!/bin/bash
set -e

# Run this in the WSL Ubuntu distro after manually running the OOBE setup.

# NOTE: This script is interactive - you will be asked for sudo password and GitHub credentials. The GH credential
# prompt will happen twice - once for a scope upgrade and once to reset the scope.

# When WSL is enabled but not activated, and Docker Desktop is installed, Docker Desktop becomes the default WSL distro.
# Change the default Ubuntu.
wsl.exe --set-default Ubuntu

SCRIPT_DIR="$(dirname "$0")"
"${SCRIPT_DIR}/wsl/setup_wsl.sh"
"${SCRIPT_DIR}/git/configure_git.sh"
"${SCRIPT_DIR}/wsl/install_pwsh.sh"
