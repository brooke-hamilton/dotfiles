#!/bin/bash

set -euo pipefail

cleanup() {
    rm -f packages-microsoft-prod.deb dotnet-install.sh
}

trap cleanup EXIT

# Install .NET 8 SDK via apt
wget https://packages.microsoft.com/config/debian/12/packages-microsoft-prod.deb -O packages-microsoft-prod.deb
sudo dpkg -i packages-microsoft-prod.deb

sudo apt-get update
sudo apt-get install -y dotnet-sdk-8.0

# Install .NET 10 SDK via dotnet-install.sh
# Temporarily use manual installation due to this issue: https://github.com/dotnet/docs/issues/50349#issuecomment-3618807570
wget https://dot.net/v1/dotnet-install.sh
chmod +x dotnet-install.sh
sudo bash dotnet-install.sh --version 10.0.100 --install-dir /usr/share/dotnet
