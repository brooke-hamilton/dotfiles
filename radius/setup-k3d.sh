#!/bin/bash
set -e

# https://docs.radapp.io/guides/operations/kubernetes/overview/#supported-kubernetes-clusters

k3d cluster delete
k3d cluster create \
    --port "8081:80@loadbalancer" \
    --k3s-arg "--disable=traefik@server:*" \
    --k3s-arg "--disable=servicelb@server:*" \
    --wait

if command -v rad >/dev/null 2>&1; then
    rad install kubernetes \
        --set rp.publicEndpointOverride=localhost:8081 \
        --skip-contour-install
fi
