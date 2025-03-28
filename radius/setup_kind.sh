#!/bin/bash
set -e

# https://docs.radapp.io/guides/operations/kubernetes/overview/#supported-kubernetes-clusters

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
kind create cluster --config="$(dirname "$0")/kind-config.yaml"

# Verify the cluster was created
echo "Verifying cluster creation..."
if kubectl cluster-info; then
    echo "Kind cluster successfully created and configured."
else
    echo "Error: Failed to create kind cluster. Please check the logs above for details."
    exit 1
fi

# Call the setup_radius.sh script
echo "Running Radius setup script..."
$(dirname "$0")/setup_radius.sh
echo "Radius setup completed."