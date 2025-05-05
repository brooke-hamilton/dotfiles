#!/bin/bash

set -e

# Script to set up Kubernetes tools in WSL Ubuntu.
# Modified from https://kubernetes.io/docs/tasks/tools/install-kubectl-linux/
KUBECTL_VERSION="${KUBECTL_VERSION:-$(curl -L -s https://dl.k8s.io/release/stable.txt)}"
echo "Installing kubectl version ${KUBECTL_VERSION}"

# Download kubectl
curl -LO "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl"

# Validate the binary (Optional)
curl -LO "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl.sha256"
echo "$(cat kubectl.sha256)  kubectl" | sha256sum --check

sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

# Verify installation
kubectl version --client

# Clean up
rm -f kubectl.sha256
rm -f kubectl

# Install Helm: https://helm.sh/docs/intro/install/
curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
chmod 700 get_helm.sh
./get_helm.sh
rm -f get_helm.sh

# Install Kind: https://kind.sigs.k8s.io/docs/user/quick-start/#installing-from-release-binaries
curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.27.0/kind-linux-amd64
chmod +x ./kind
sudo mv ./kind /usr/local/bin/kind

# Install k3d: https://k3d.io/stable/#installation
curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash
