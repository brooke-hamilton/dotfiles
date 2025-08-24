#!/bin/bash

set -ex

# Create a group with one environment and one application
rad group create group1
rad env create env1 --group group1
rad deploy app.bicep -g group1 -e env1

echo ""
echo "Applications deployed successfully. Now deleting..."

# Delete applications from each environment
rad app delete todoapp --yes

# Delete environments
rad env delete env1 --group group1 --yes

# Delete groups
rad group delete group1 --yes

echo "Cleanup completed successfully."
