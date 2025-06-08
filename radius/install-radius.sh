#!/bin/bash

# Radius Installation Script
# Installs either the latest release from GitHub or uses a local build

set -e

# Pass parameters to the install script
wget -q "https://raw.githubusercontent.com/radius-project/radius/main/deploy/install.sh" -O - | /bin/bash -s -- "$@"