#!/bin/bash
set -e

# Enhanced k3d setup script for PR dev containers
# This script sets up a k3d cluster with Radius deployed

echo "Setting up k3d cluster for Radius PR dev container..."

# Clean up any existing cluster
k3d cluster delete k3d-k3s-default || true

# Create k3d cluster with proper configuration
echo "Creating k3d cluster..."
k3d cluster create k3d-k3s-default \
    -p "8081:80@loadbalancer" \
    --k3s-arg "--disable=traefik@server:*" \
    --k3s-arg "--disable=servicelb@server:*" \
    --wait

# Verify cluster is ready
echo "Waiting for cluster to be ready..."
kubectl wait --for=condition=ready nodes --all --timeout=300s

# Install Radius if rad CLI is available
if command -v rad >/dev/null 2>&1; then
    echo "Installing Radius to cluster..."
    rad install kubernetes --set rp.publicEndpointOverride=localhost:8081
    
    echo "Creating Radius workspace..."
    rad workspace create kubernetes k3d --context k3d-k3s-default --force
    
    echo "Radius version:"
    rad version
    
    echo "Radius workspace list:"
    rad workspace list
else
    echo "Warning: rad CLI not found, skipping Radius installation"
fi

echo "k3d cluster setup complete!"
echo "Cluster info:"
kubectl cluster-info

echo "Nodes:"
kubectl get nodes

echo "Pods:"
kubectl get pods -A