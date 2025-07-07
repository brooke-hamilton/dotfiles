#!/bin/bash

set -ex

deploy() {
    local groupName="${1}group"
    local environmentName="${1}env"
    rad group create "$groupName"
    rad env create "$environmentName" --group "$groupName"
    rad deploy app.bicep -g "$groupName" -e "$environmentName"
}

CURRENT_CONTEXT=$(kubectl config current-context)
rad workspace create kubernetes k3d --context "$CURRENT_CONTEXT" --force

deploy avocado
deploy peach

rad resource list Applications.Core/containers -a todoapp -g avocadogroup
rad resource list Applications.Core/containers -a todoapp -g peachgroup
