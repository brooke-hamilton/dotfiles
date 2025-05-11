#!/bin/bash

set -e

sudo dnf upgrade -y
sudo dnf install git make curl wget -y

# Install GitHub CLI
sudo dnf config-manager addrepo --from-repofile=https://cli.github.com/packages/rpm/gh-cli.repo
sudo dnf install gh -y

# Install GitHub copilot CLI
GITHUB_TOKEN=$(gh.exe auth token)
export GITHUB_TOKEN
gh extension install github/gh-copilot
gh alias set co copilot --clobber

# Install the az cli
sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
sudo dnf install -y https://packages.microsoft.com/config/rhel/9.0/packages-microsoft-prod.rpm
sudo dnf install azure-cli -y
