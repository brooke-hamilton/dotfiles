#!/bin/bash

set -ex

# Creates the following:
# group 1
#   env1
# group 2
#   app.bicep, associated to env1

rad group create group1
rad env create env1 --group group1
rad group create group2

# The full environment ID is required if deploying with an environment that is in a different group.
rad deploy app.bicep \
    --group group2 \
    --environment "/planes/radius/local/resourcegroups/group1/providers/Applications.Core/environments/env1"
