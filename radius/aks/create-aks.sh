#!/bin/bash

set -euo pipefail

if [ "$#" -lt 2 ] || [ "$#" -gt 3 ]; then
    echo "Usage: $0 <K8S_CLUSTER_NAME> <AZURE_RESOURCE_GROUP> [AZURE_SUBSCRIPTION_ID]"
    exit 1
fi

export K8S_CLUSTER_NAME=$1
export AZURE_RESOURCE_GROUP=$2

if [ "$#" -eq 3 ]; then
    export AZURE_SUBSCRIPTION_ID=$3
else
    echo "Fetching subscription ID from current az account..."
    AZURE_SUBSCRIPTION_ID=$(az account show --query id -o tsv)
    export AZURE_SUBSCRIPTION_ID
fi

echo "Configuration:"
echo "  Cluster Name: ${K8S_CLUSTER_NAME}"
echo "  Resource Group: ${AZURE_RESOURCE_GROUP}"
echo "  Subscription ID: ${AZURE_SUBSCRIPTION_ID}"

# Create resource group if it doesn't exist
echo "Checking if resource group '${AZURE_RESOURCE_GROUP}' exists..."
if ! az group show --subscription "${AZURE_SUBSCRIPTION_ID}" --name "${AZURE_RESOURCE_GROUP}" &>/dev/null; then
    echo "Resource group '${AZURE_RESOURCE_GROUP}' does not exist. Creating..."
    az group create --subscription "${AZURE_SUBSCRIPTION_ID}" --name "${AZURE_RESOURCE_GROUP}" --location "eastus"
else
    echo "Resource group '${AZURE_RESOURCE_GROUP}' already exists."
fi

echo "Checking if AKS cluster '${K8S_CLUSTER_NAME}' exists..."
if ! az aks show --subscription "${AZURE_SUBSCRIPTION_ID}" --resource-group "${AZURE_RESOURCE_GROUP}" --name "${K8S_CLUSTER_NAME}" &>/dev/null; then
    echo "Creating AKS cluster '${K8S_CLUSTER_NAME}'..."
    az aks create --subscription "${AZURE_SUBSCRIPTION_ID}" \
        --resource-group "${AZURE_RESOURCE_GROUP}" \
        --name "${K8S_CLUSTER_NAME}" \
        --os-sku AzureLinux \
        --enable-oidc-issuer \
        --kubernetes-version 1.34.1 \
        --auto-upgrade-channel patch
else
    echo "AKS cluster '${K8S_CLUSTER_NAME}' already exists. Skipping creation."
fi

# Get the OIDC issuer URL from the newly created cluster
echo "Retrieving OIDC issuer URL from cluster..."
SERVICE_ACCOUNT_ISSUER=$(az aks show \
    --subscription "${AZURE_SUBSCRIPTION_ID}" \
    --resource-group "${AZURE_RESOURCE_GROUP}" \
    --name "${K8S_CLUSTER_NAME}" \
    --query "oidcIssuerProfile.issuerUrl" -o tsv)
export SERVICE_ACCOUNT_ISSUER
echo "OIDC Issuer URL: ${SERVICE_ACCOUNT_ISSUER}"

# Create the Entra ID Application
export APPLICATION_NAME="${K8S_CLUSTER_NAME}-radius-app"
echo "Creating Entra ID application '${APPLICATION_NAME}'..."
az ad app create --display-name "${APPLICATION_NAME}" --service-management-reference 7505bbbe-ccd0-4e63-8497-0e172a7725f3

# Get the client ID and object ID of the application
echo "Retrieving application client ID and object ID..."
APPLICATION_CLIENT_ID="$(az ad app list --display-name "${APPLICATION_NAME}" --query [].appId -o tsv)"
export APPLICATION_CLIENT_ID

APPLICATION_OBJECT_ID="$(az ad app show --id "${APPLICATION_CLIENT_ID}" --query id -otsv)"
export APPLICATION_OBJECT_ID

# Create the applications-rp federated credential for the application
echo "Creating federated credential for applications-rp..."
cat <<EOF > params-applications-rp.json
{
  "name": "radius-applications-rp",
  "issuer": "${SERVICE_ACCOUNT_ISSUER}",
  "subject": "system:serviceaccount:radius-system:applications-rp",
  "description": "Kubernetes service account federated credential for applications-rp",
  "audiences": [
    "api://AzureADTokenExchange"
  ]
}
EOF
az ad app federated-credential create --id "${APPLICATION_OBJECT_ID}" --parameters @params-applications-rp.json

# Create the bicep-de federated credential for the application
echo "Creating federated credential for bicep-de..."
cat <<EOF > params-bicep-de.json
{
  "name": "radius-bicep-de",
  "issuer": "${SERVICE_ACCOUNT_ISSUER}",
  "subject": "system:serviceaccount:radius-system:bicep-de",
  "description": "Kubernetes service account federated credential for bicep-de",
  "audiences": [
    "api://AzureADTokenExchange"
  ]
}
EOF
az ad app federated-credential create --id "${APPLICATION_OBJECT_ID}" --parameters @params-bicep-de.json

# Create the ucp federated credential for the application
echo "Creating federated credential for ucp..."
cat <<EOF > params-ucp.json
{
  "name": "radius-ucp",
  "issuer": "${SERVICE_ACCOUNT_ISSUER}",
  "subject": "system:serviceaccount:radius-system:ucp",
  "description": "Kubernetes service account federated credential for ucp",
  "audiences": [
    "api://AzureADTokenExchange"
  ]
}
EOF
az ad app federated-credential create --id "${APPLICATION_OBJECT_ID}" --parameters @params-ucp.json

# Create the dynamic-rp federated credential for the application
echo "Creating federated credential for dynamic-rp..."
cat <<EOF > params-dynamic-rp.json
{
  "name": "radius-dynamic-rp",
  "issuer": "${SERVICE_ACCOUNT_ISSUER}",
  "subject": "system:serviceaccount:radius-system:dynamic-rp",
  "description": "Kubernetes service account federated credential for dynamic-rp",
  "audiences": [
    "api://AzureADTokenExchange"
  ]
}
EOF
az ad app federated-credential create --id "${APPLICATION_OBJECT_ID}" --parameters @params-dynamic-rp.json

# Set the permissions for the application
echo "Creating service principal for application..."
az ad sp create --id "${APPLICATION_CLIENT_ID}"

echo "Assigning Owner role to application on resource group..."
az role assignment create --assignee "${APPLICATION_CLIENT_ID}" --role "Owner" --scope "/subscriptions/${AZURE_SUBSCRIPTION_ID}/resourceGroups/${AZURE_RESOURCE_GROUP}"
echo "AKS cluster '${K8S_CLUSTER_NAME}' created successfully with OIDC and Entra ID application '${APPLICATION_NAME}'."