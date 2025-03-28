#!/bin/bash
set -e

# https://docs.radapp.io/guides/operations/kubernetes/overview/#supported-kubernetes-clusters

k3d cluster delete
k3d cluster create -p "8081:80@loadbalancer" \
    --k3s-arg "--disable=traefik@server:*" \
    --k3s-arg "--disable=servicelb@server:*"
