#!/bin/bash

set -ex

function get_pod_images() {
    kubectl get pods -n radius-system -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.containers[*].image}{"\n"}{end}'
}

function uninstall() {
    rad uninstall kubernetes
}

clear
k3d cluster delete
k3d cluster create -p "8081:80@loadbalancer" \
    --k3s-arg "--disable=traefik@server:*" \
    --k3s-arg "--disable=servicelb@server:*"

rad install kubernetes \
    --chart /workspace/radius-project/radius/deploy/Chart \
    --set dashboard.enabled=false \
    --skip-contour-install

get_pod_images
uninstall

rad install kubernetes \
    --chart /workspace/radius-project/radius/deploy/Chart \
    --set global.imageTag="0.48" \
    --set de.tag=0.47 \
    --set dashboard.enabled=false \
    --skip-contour-install

get_pod_images
uninstall

rad install kubernetes \
    --chart /workspace/radius-project/radius/deploy/Chart \
    --set global.imageRegistry=ghcr.io/radius-project \
    --set global.imageTag=0.48 \
    --set de.tag=0.47 \
    --set dashboard.enabled=false \
    --skip-contour-install

get_pod_images
uninstall

rad install kubernetes \
    --chart /workspace/radius-project/radius/deploy/Chart \
    --set de.image=localhost:5000/deployment-engine \
    --set de.tag=latest \
    --set dashboard.enabled=false \
    --skip-contour-install

# get_pod_images
# uninstall

# rad install kubernetes \
#     --chart /home/radiususer/radius \
#     --set-file global.rootCA.cert=./airgapped.local.crt \
#     --set rp.image=g4tv7jkap3plmregistry.azurecr.io/applications-rp \
#     --set rp.tag=latest \
#     --set de.image=g4tv7jkap3plmregistry.azurecr.io/deployment-engine \
#     --set de.tag=0.48 \
#     --set ucp.image=g4tv7jkap3plmregistry.azurecr.io/ucpd \
#     --set ucp.tag=latest \
#     --set dynamicrp.image=g4tv7jkap3plmregistry.azurecr.io/dynamic-rp \
#     --set dynamicrp.tag=latest \
#     --set controller.image=g4tv7jkap3plmregistry.azurecr.io/controller \
#     --set controller.tag=latest \
#     --set bicep.image=g4tv7jkap3plmregistry.azurecr.io/bicep \
#     --set bicep.tag=edge \
#     --set dashboard.enabled=false

# rad install kubernetes \
#   --chart /workspace/radius-project/radius/deploy/Chart \
#   --set global.imageTag=0.47 \
#   --set dashboard.enabled=false \
#   --skip-contour-install

# rad upgrade kubernetes \
#   --chart /workspace/radius-project/radius/deploy/Chart \
#   --set global.imageTag=0.48 \
#   --set dashboard.enabled=false \
#   --skip-contour-install

# get_pod_images
# uninstall

# rad install kubernetes \
#     --chart /home/radiususer/radius \
#     --set-file global.rootCA.cert=./airgapped.local.crt \
#     --set rp.image=g4tv7jkap3plmregistry.azurecr.io/applications-rp \
#     --set rp.tag=latest \
#     --set de.image=g4tv7jkap3plmregistry.azurecr.io/deployment-engine \
#     --set de.tag=0.48 \
#     --set ucp.image=g4tv7jkap3plmregistry.azurecr.io/ucpd \
#     --set ucp.tag=latest \
#     --set dynamicrp.image=g4tv7jkap3plmregistry.azurecr.io/dynamic-rp \
#     --set dynamicrp.tag=latest \
#     --set controller.image=g4tv7jkap3plmregistry.azurecr.io/controller \
#     --set controller.tag=latest \
#     --set bicep.image=g4tv7jkap3plmregistry.azurecr.io/bicep \
#     --set bicep.tag=edge \
#     --set dashboard.enabled=false

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
