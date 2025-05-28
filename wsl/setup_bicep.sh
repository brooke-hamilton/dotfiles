#!/bin/bash

set -e

# https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/install#install-manually

# Fetch the latest Bicep CLI binary
curl -Lo bicep https://github.com/Azure/bicep/releases/latest/download/bicep-linux-x64
# Mark it as executable
chmod +x ./bicep
# Add bicep to your PATH (requires admin)
sudo mv ./bicep /usr/local/bin/bicep
