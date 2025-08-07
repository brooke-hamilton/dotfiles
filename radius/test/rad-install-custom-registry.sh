#!/bin/bash

set -e

k3d cluster delete
k3d cluster create -p "8081:80@loadbalancer" \
    --k3s-arg "--disable=traefik@server:*" \
    --k3s-arg "--disable=servicelb@server:*"

rad install kubernetes --set global.imageTag="0.48"

kubectl describe pod controller -n radius-system


# During initial installation with custom registry
# rad install kubernetes \
#     --set global.imageRegistry=ghcr.io/radius-project \
#     --set global.imageTag=v0.49.0

# During initial installation with custom tag
# rad install kubernetes \
#   --set global.imageTag=v0.48.0

# # Combine custom registry and tag
# rad install kubernetes \
#   --set global.imageRegistry=myregistry.azurecr.io \
#   --set global.imageTag=v0.48.0

# # During upgrade
# rad upgrade kubernetes \
#   --set global.imageRegistry=myregistry.azurecr.io \
#   --set global.imageTag=v0.48.0

# # During initialization
# rad init \
#   --set global.imageRegistry=myregistry.azurecr.io \
#   --set global.imageTag=v0.48.0