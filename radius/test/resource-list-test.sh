#!/bin/bash

# This script tests listing resources for an environment, PR #9507
# Prerequisites: 
# - Kubernetes cluster with Radius installed
# - No rad init

set -e

rad group create banana-group
rad group switch banana-group
rad deploy "$(dirname "$0")/bananaApp.bicep"
rad resource list Applications.Core/containers
rad resource list Applications.Core/containers --environment banana-env