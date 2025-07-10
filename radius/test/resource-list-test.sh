#!/bin/bash

set -ex

# Create a group with one environment and one application
rad group create group1
rad env create env1 --group group1
rad deploy app.bicep -g group1 -e env1 --parameters "appName=app1" --parameters containerName="container1"

# Create a second environment in the same group with a different application
rad env create env2 --group group1
rad deploy app.bicep -g group1 -e env2 --parameters "appName=app2" --parameters containerName="container2"

# Create a second group with one environment and one application
rad group create group2
rad env create env3 --group group2
rad deploy app.bicep -g group2 -e env3 --parameters "appName=app3" --parameters containerName="container3"
