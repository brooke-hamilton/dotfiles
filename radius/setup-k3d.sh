#!/bin/bash

# https://docs.radapp.io/guides/operations/kubernetes/overview/#supported-kubernetes-clusters

set -euo pipefail

# Default values
SKIP_INSTALL=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --skip-install)
            SKIP_INSTALL=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

k3d cluster delete
k3d cluster create \
    --port "8081:80@loadbalancer" \
    --k3s-arg "--disable=traefik@server:*" \
    --k3s-arg "--disable=servicelb@server:*" \
    --wait

if [[ "$SKIP_INSTALL" == "false" ]]; then
    if command -v rad >/dev/null 2>&1; then
        echo "Installing Radius on Kubernetes cluster..."
        rad install kubernetes \
            --set rp.publicEndpointOverride=localhost:8081 \
            --skip-contour-install
    else
        echo "Warning: rad CLI not found, skipping Radius installation"
    fi
else
    echo "Skipping Radius installation (--skip-install specified)"
fi
