#!/bin/bash

set -e

# Check if repository parameter is provided
if [ $# -eq 0 ]; then
    echo "Usage: $0 <repository>"
    exit 1
fi

REPO="$1"

while true; do
    # Get a batch of workflow run IDs
    run_ids=$(gh run list --repo "$REPO" -L 10 --json databaseId --jq '.[].databaseId')
    
    # Check if we got any results
    if [[ -z "$run_ids" ]]; then
        echo "No more workflow runs found. Exiting."
        break
    fi
    
    # Process each ID in the current batch
    echo "$run_ids" | while read id; do
        echo "Deleting workflow run with ID: $id"
        gh run delete --repo "$REPO" "$id"
    done
    
    echo "Batch completed. Checking for more workflow runs..."
done
