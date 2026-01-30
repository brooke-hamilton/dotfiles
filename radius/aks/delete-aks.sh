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

echo ""
echo "WARNING: This will delete ALL resources in the resource group '${AZURE_RESOURCE_GROUP}'"
echo "Press Ctrl+C to cancel, or press Enter to continue..."
read -r

export APPLICATION_NAME="${K8S_CLUSTER_NAME}-radius-app"

# Get application details if it exists
echo "Checking if Entra ID application '${APPLICATION_NAME}' exists..."
if az ad app list --display-name "${APPLICATION_NAME}" --query "[].appId" -o tsv | grep -q .; then
    APPLICATION_CLIENT_ID="$(az ad app list --display-name "${APPLICATION_NAME}" --query [].appId -o tsv)"
    export APPLICATION_CLIENT_ID
    
    echo "Found application with client ID: ${APPLICATION_CLIENT_ID}"
    
    # Remove role assignment
    echo "Checking if Owner role assignment exists..."
    if az role assignment list --assignee "${APPLICATION_CLIENT_ID}" --scope "/subscriptions/${AZURE_SUBSCRIPTION_ID}/resourceGroups/${AZURE_RESOURCE_GROUP}" --role "Owner" --query "[].principalId" -o tsv | grep -q .; then
        echo "Removing Owner role assignment from application..."
        az role assignment delete --assignee "${APPLICATION_CLIENT_ID}" --role "Owner" --scope "/subscriptions/${AZURE_SUBSCRIPTION_ID}/resourceGroups/${AZURE_RESOURCE_GROUP}" || echo "Failed to remove role assignment, continuing..."
    else
        echo "No Owner role assignment found for application."
    fi
    
    # Delete service principal (this also removes federated credentials)
    echo "Checking if service principal exists..."
    if az ad sp show --id "${APPLICATION_CLIENT_ID}" &>/dev/null; then
        echo "Deleting service principal..."
        az ad sp delete --id "${APPLICATION_CLIENT_ID}" || echo "Failed to delete service principal, continuing..."
    else
        echo "No service principal found for application."
    fi
    
    # Delete the Entra ID application (this removes all federated credentials automatically)
    echo "Deleting Entra ID application '${APPLICATION_NAME}'..."
    az ad app delete --id "${APPLICATION_CLIENT_ID}" || echo "Failed to delete application, continuing..."
else
    echo "Entra ID application '${APPLICATION_NAME}' not found. Skipping application cleanup."
fi

# Delete AKS cluster
echo "Checking if AKS cluster '${K8S_CLUSTER_NAME}' exists..."
if az aks show --subscription "${AZURE_SUBSCRIPTION_ID}" --resource-group "${AZURE_RESOURCE_GROUP}" --name "${K8S_CLUSTER_NAME}" &>/dev/null; then
    echo "Deleting AKS cluster '${K8S_CLUSTER_NAME}'... (this may take several minutes)"
    az aks delete --subscription "${AZURE_SUBSCRIPTION_ID}" --resource-group "${AZURE_RESOURCE_GROUP}" --name "${K8S_CLUSTER_NAME}" --yes --no-wait
    echo "AKS cluster deletion initiated."
else
    echo "AKS cluster '${K8S_CLUSTER_NAME}' not found. Skipping cluster deletion."
fi

# Delete resource group
echo "Checking if resource group '${AZURE_RESOURCE_GROUP}' exists..."
if az group show --subscription "${AZURE_SUBSCRIPTION_ID}" --name "${AZURE_RESOURCE_GROUP}" &>/dev/null; then
    echo "Deleting resource group '${AZURE_RESOURCE_GROUP}'... (this may take several minutes)"
    az group delete --subscription "${AZURE_SUBSCRIPTION_ID}" --name "${AZURE_RESOURCE_GROUP}" --yes --no-wait
    echo "Resource group deletion initiated."
else
    echo "Resource group '${AZURE_RESOURCE_GROUP}' not found. Skipping resource group deletion."
fi

echo ""
echo "============================================================================"
echo "Cleanup initiated successfully!"
echo "============================================================================"
echo "Note: Resource deletions are running in the background and may take several"
echo "minutes to complete. You can check the status in the Azure portal."
echo "============================================================================"