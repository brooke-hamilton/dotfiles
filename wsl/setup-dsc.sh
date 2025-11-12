#!/bin/bash

# Downloads and installs PowerShell DSC to /opt/dsc
# Adds DSC to PATH via ~/.bashrc

set -e

INSTALL_DIR="/opt/dsc"
VERSION="3.0.2"
URL="https://github.com/PowerShell/DSC/releases/download/v${VERSION}/DSC-${VERSION}-x86_64-linux.tar.gz"

# Clean up existing DSC installation and create directory
if [ -d "$INSTALL_DIR" ]; then
    sudo rm -rf "$INSTALL_DIR"/*
fi
sudo mkdir -p "$INSTALL_DIR"

# Download and extract DSC (Desired State Configuration) package from URL to /opt/dsc directory
curl -L "${URL}" | sudo tar -xzf - -C "$INSTALL_DIR"

# Add DSC to PATH only if dsc command is not found
if ! command -v dsc &>/dev/null; then
    echo "export PATH=\"$INSTALL_DIR:\$PATH\"" >>"$HOME/.bashrc"
    echo "DSC added to PATH. Please run 'source ~/.bashrc' or start a new terminal session."
fi
