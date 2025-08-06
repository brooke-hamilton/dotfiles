#!/bin/bash

# Radius Installation Script
# Installs either the latest release from GitHub or uses a local build
#
# Usage:
#   ./install-radius.sh                    # Install latest version
#   ./install-radius.sh 0.35.0             # Install specific version (semver without 'v' prefix)
#   ./install-radius.sh edge               # Install edge version

set -e

wget -q "https://raw.githubusercontent.com/radius-project/radius/main/deploy/install.sh" -O - | /bin/bash -s -- "$@"