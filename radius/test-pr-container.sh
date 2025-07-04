#!/bin/bash

# Test script for the Radius PR dev container
# Usage: ./test-pr-container.sh <PR_NUMBER>

set -e

PR_NUMBER=${1:-"1"}
IMAGE_NAME="radius-pr-devcontainer-test"

echo "Testing Radius PR Dev Container for PR #${PR_NUMBER}"

# Build the test container locally
echo "Building test container..."
docker build \
    -f radius/Dockerfile.pr-devcontainer-test \
    --build-arg PR_NUMBER="${PR_NUMBER}" \
    --build-arg PR_BRANCH="test-branch" \
    --build-arg PR_SHA="test-sha" \
    --build-arg PR_REPO_URL="https://github.com/radius-project/radius.git" \
    --build-arg PR_TITLE="Test PR" \
    -t "${IMAGE_NAME}:pr-${PR_NUMBER}" \
    .

echo "Container built successfully!"
echo "To run the container:"
echo "  docker run -it --privileged -p 8081:8081 ${IMAGE_NAME}:pr-${PR_NUMBER}"
echo ""
echo "To run without privileged mode (no k3d):"
echo "  docker run -it ${IMAGE_NAME}:pr-${PR_NUMBER}"