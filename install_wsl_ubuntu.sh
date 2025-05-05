#!/bin/bash
set -e

# Run this in the WSL Ubuntu distro after manually running the OOBE setup.

# When WSL is enabled but not activated, and Docker Desktop is installed, Docker Desktop becomes the default WSL distro.
# Change the default Ubuntu.
wsl.exe --set-default Ubuntu

SCRIPT_DIR="$(dirname "$0")"
"${SCRIPT_DIR}/wsl/setup_wsl.sh"
"${SCRIPT_DIR}/wsl/setup_pwsh.sh"

echo 'Set up git configuration.'