#!/bin/bash
set -e

# Run this in the WSL Ubuntu distro after manually running the OOBE setup.

# When WSL is enabled but not activated, and Docker Desktop is installed, Docker Desktop becomes the default WSL distro.
# Change the default to Ubuntu.
wsl.exe --set-default Ubuntu

SCRIPT_DIR="$(dirname "$0")"

if command -v apt >/dev/null 2>&1; then
    echo "Using apt (Debian/Ubuntu-based distros)"
    "${SCRIPT_DIR}/wsl/setup_wsl_apt.sh"
    "${SCRIPT_DIR}/wsl/setup_az_apt.sh"
    "${SCRIPT_DIR}/wsl/setup_kubernetes_tools.sh"
    "${SCRIPT_DIR}/wsl/setup_pwsh_apt.sh"
    "${SCRIPT_DIR}/wsl/setup_node.sh"
elif command -v dnf >/dev/null 2>&1; then
    echo "Using dnf (Fedora/RHEL-based distros)"
    "${SCRIPT_DIR}/wsl/setup_wsl_dnf.sh"
else
    echo "Unsupported package manager."
    exit 1
fi

# Setup that does not depend on a specific package manager.
"${SCRIPT_DIR}/wsl/setup_go.sh"
"${SCRIPT_DIR}/wsl/setup_bashrc.sh"
"${SCRIPT_DIR}/wsl/setup-edit.sh"
"${SCRIPT_DIR}/wsl/setup-gitconfig.sh"
