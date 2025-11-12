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
KIND_CONFIG="$(dirname "$0")/kind-config.yaml"
echo "Creating kind cluster with configuration from $KIND_CONFIG..."
kind create cluster --config="$KIND_CONFIG"

# Verify the cluster was created
echo "Verifying cluster creation..."
if kubectl cluster-info; then
    echo "Kind cluster successfully created and configured."
else
    echo "Error: Failed to create kind cluster. Please check the logs above for details."
    exit 1
fi

if command -v rad >/dev/null 2>&1; then
    rad install kubernetes --set rp.publicEndpointOverride=localhost:8080
fi
