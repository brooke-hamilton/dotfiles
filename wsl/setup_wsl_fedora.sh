#!/bin/bash

# Description: Installs and configures tools for WSL.
# Usage: ./wsl-setup.sh

set -e

sudo dnf upgrade -y
sudo dnf install git make curl wget -y

# install GitHub CLI
sudo dnf config-manager addrepo --from-repofile=https://cli.github.com/packages/rpm/gh-cli.repo
sudo dnf install gh -y

# Install the az cli
sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
sudo dnf install -y https://packages.microsoft.com/config/rhel/9.0/packages-microsoft-prod.rpm
sudo dnf install azure-cli -y
