#!/bin/bash

# Simple Radius Image Puller
# Pulls latest Radius images and pushes them to localhost:5000 registry
#
# Usage: ./pull-radius-images.sh

set -e

# Radius images to pull from ghcr.io
RADIUS_IMAGES=(
    "ghcr.io/radius-project/controller"
    "ghcr.io/radius-project/ucpd"
    "ghcr.io/radius-project/de"
    "ghcr.io/radius-project/applications-rp"
)

# Recipe images
RECIPE_IMAGES=(
    "ghcr.io/radius-project/recipes/local-dev/rediscaches"
    "ghcr.io/radius-project/recipes/local-dev/mongodatabases"
    "ghcr.io/radius-project/recipes/local-dev/sqldatabases"
    "ghcr.io/radius-project/recipes/local-dev/rabbitmqmessagequeues"
)

# Get the latest version from GitHub API
get_latest_version() {
    curl -s "https://api.github.com/repos/radius-project/radius/releases/latest" | \
        grep '"tag_name":' | \
        sed 's/.*"tag_name": "v\([^"]*\)".*/\1/'
}

# Convert version to image tag (e.g., "0.49.0" -> "0.49")
version_to_tag() {
    echo "$1" | sed 's/^\([0-9]\+\.[0-9]\+\).*/\1/'
}

# Pull, tag and push an image
pull_and_push() {
    local source_image="$1"
    local version="$2"
    local image_name
    image_name=$(basename "$source_image")
    local local_image="localhost:5000/radius/${image_name}:${version}"
    
    echo "Processing ${source_image}:$(version_to_tag "$version")"
    
    # Pull from ghcr.io
    docker pull "${source_image}:$(version_to_tag "$version")"
    
    # Tag for local registry
    docker tag "${source_image}:$(version_to_tag "$version")" "$local_image"
    
    # Push to local registry
    docker push "$local_image"
    
    echo "✓ Pushed $local_image"
}

# Main execution
main() {
    echo "Getting latest Radius version..."
    LATEST_VERSION=$(get_latest_version)
    
    if [ -z "$LATEST_VERSION" ]; then
        echo "Error: Could not get latest version"
        exit 1
    fi
    
    echo "Latest version: $LATEST_VERSION"
    echo
    
    # Pull core Radius images
    echo "Pulling core Radius images..."
    for image in "${RADIUS_IMAGES[@]}"; do
        pull_and_push "$image" "$LATEST_VERSION"
    done
    
    echo
    echo "Pulling recipe images..."
    # Pull recipe images (using 'latest' tag)
    for image in "${RECIPE_IMAGES[@]}"; do
        local image_name
        image_name=$(basename "$image")
        local local_image="localhost:5000/radius/${image_name}:latest"
        
        echo "Processing ${image}:latest"
        docker pull "${image}:latest"
        docker tag "${image}:latest" "$local_image"
        docker push "$local_image"
        echo "✓ Pushed $local_image"
    done
    
    echo
    echo "Done! All images pushed to localhost:5000"
}

main "$@"
