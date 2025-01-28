#!/bin/bash

# Modified from:
# https://learn.microsoft.com/en-us/powershell/scripting/install/install-ubuntu?view=powershell-7.4

# Install pre-requisite packages.
sudo sudo apt-get update && sudo apt-get install -y wget jq

# Get the download URL for the latest PowerShell deb package
url=$(curl -s https://api.github.com/repos/PowerShell/PowerShell/releases/latest | \
        jq -r '.assets[] | select(.name | endswith(".deb")) | .browser_download_url')

# Download the PowerShell package file
wget -O powershell.deb "$url"

# Install the PowerShell package
sudo dpkg -i powershell.deb

# Resolve missing dependencies and finish the install (if necessary)
sudo apt-get install -f

# Delete the downloaded package file
rm powershell.deb
