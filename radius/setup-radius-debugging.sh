#!/bin/bash

set -e

rad group create default
rad group switch default
rad env create default --namespace default --group default
rad env switch default
rad workspace create kubernetes dev --environment default --group default --force
rad recipe register default --template-kind bicep --resource-type "Applications.Datastores/redisCaches" --template-path "ghcr.io/radius-project/recipes/local-dev/rediscaches:latest"

# add the overrides section to the config.yaml file
sed -i '/kind: kubernetes/a\                overrides:\n                    ucp: http://localhost:9000' ~/.rad/config.yaml

echo "Creating namespace radius-testing..."
kubectl create namespace radius-testing
