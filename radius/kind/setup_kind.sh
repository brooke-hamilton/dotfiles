#!/bin/bash

set -e

# https://docs.radapp.io/guides/operations/kubernetes/overview/#supported-kubernetes-clusters
# Check if kind-config.yaml exists in the home directory
if [ ! -f "$HOME/kind-config.yaml" ]; then
    echo "Copying kind-config.yaml to home directory"
    cp "$(dirname "$0")/kind-config.yaml" "$HOME/kind-config.yaml"
fi

# Ensure the .rad directory exists in the home directory
if [ ! -d "$HOME/.rad" ]; then
    echo "Creating .rad directory in home directory"
    mkdir -p "$HOME/.rad"
fi

# Copy the config.yaml file from the current directory to .rad directory
echo "Copying config.yaml to $HOME/.rad/config.yaml"
cp "$(dirname "$0")/config.yaml" "$HOME/.rad/config.yaml"

# Delete any existing kind clusters
echo "Checking for existing kind clusters..."
existing_clusters=$(kind get clusters 2>/dev/null)

if [ -n "$existing_clusters" ]; then
    echo "Found existing clusters: $existing_clusters"
    for cluster in $existing_clusters; do
        echo "Deleting kind cluster: $cluster"
        kind delete cluster --name "$cluster"
    done
    echo "All existing kind clusters have been deleted."
else
    echo "No existing kind clusters found."
fi

# Create a new kind cluster using the config file
echo "Creating kind cluster with configuration from $HOME/kind-config.yaml..."
kind create cluster --config="$HOME/kind-config.yaml"

# Verify the cluster was created
echo "Verifying cluster creation..."
if kubectl cluster-info; then
    echo "Kind cluster successfully created and configured."
else
    echo "Error: Failed to create kind cluster. Please check the logs above for details."
    exit 1
fi

echo "Creating namespace radius-testing..."
kubectl create namespace radius-testing

echo "Remaining steps:"
echo "1. Run 'make install' to build and install a local copy of the CLI."
echo "2. Run 'rad init' to install Radius in the Kind cluster."
echo "3. Modify cmd/ucpd/ucp-dev.yaml to set the manifestDirectory element to the full local path."
echo "4. Run the 'Launch Control Plane (all)' task in the debug pane of VS Code."
echo "See https://github.com/radius-project/radius/blob/main/docs/contributing/contributing-code/contributing-code-control-plane/running-controlplane-locally.md for details on debugging Radius."
