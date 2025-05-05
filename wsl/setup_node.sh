#!/bin/bash

set -e

# Adapted from https://nodejs.org/en/download
echo "Installing Node.js..."

# Download and install nvm:
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash

# in lieu of restarting the shell
# shellcheck disable=SC1091
\. "$HOME/.nvm/nvm.sh"

# Download and install Node.js:
nvm install 22

# Install packages
npm install -g typescript
npm install -g autorest
npm install -g oav
