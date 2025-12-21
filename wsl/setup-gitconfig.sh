#!/bin/bash

# ============================================================================
# Set up git configuration by linking config files from OneDrive
# ============================================================================

set -euo pipefail

echo "============================================================================"
echo "Setting up git configuration"
echo "============================================================================"

ONEDRIVE_WIN_PATH="$(powershell.exe -NoProfile -Command 'Write-Host -NoNewline $env:ONEDRIVE' | tr -d '\r')"
if [[ -n "$ONEDRIVE_WIN_PATH" ]]; then
    ONEDRIVE_PATH="$(wslpath "$ONEDRIVE_WIN_PATH")"
    
    GITCONFIG_PATH="${ONEDRIVE_PATH}/.gitconfig"
    if [[ -f "$GITCONFIG_PATH" ]]; then
        ln -sf "$GITCONFIG_PATH" ~/.gitconfig
        echo "Linked .gitconfig from OneDrive"
    else
        echo "Warning: .gitconfig not found at $GITCONFIG_PATH"
    fi
    
    GITCONFIG_WSL_PATH="${ONEDRIVE_PATH}/.gitconfig-wsl"
    if [[ -f "$GITCONFIG_WSL_PATH" ]]; then
        ln -sf "$GITCONFIG_WSL_PATH" ~/.gitconfig-wsl
        echo "Linked .gitconfig-wsl from OneDrive"
    else
        echo "Warning: .gitconfig-wsl not found at $GITCONFIG_WSL_PATH"
    fi
else
    echo "Warning: Could not determine OneDrive path"
fi

echo "============================================================================"
echo "Git configuration setup completed"
echo "============================================================================"
