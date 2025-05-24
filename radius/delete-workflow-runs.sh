#!/bin/bash

set -e

# Check if repository parameter is provided
if [ $# -eq 0 ]; then
    echo "Usage: $0 <repository>"
    exit 1
fi

REPO="$1"
GH_TOKEN="$(gh auth token)"
export GH_TOKEN

while true; do
    # Get a batch of workflow run IDs
    run_ids=$(gh run list --repo "$REPO" -L 30 --json databaseId --jq '.[].databaseId')
    
    # Check if we got any results
    if [[ -z "$run_ids" ]]; then
        echo "No more workflow runs found. Exiting."
        break
    fi
    
    # Process each ID in the current batch
    echo "$run_ids" | while read id; do
        echo "Deleting workflow run with ID: $id"
        # The gh CLI command is simpler but much slower than using curl
        #gh run delete --repo "$REPO" "$id"
        curl -sL -X DELETE \
            -H "Accept: application/vnd.github+json" \
            -H "Authorization: Bearer $GH_TOKEN" \
            -H "X-GitHub-Api-Version: 2022-11-28" \
            "https://api.github.com/repos/$REPO/actions/runs/$id"
    done
    
    echo "Batch completed. Checking for more workflow runs..."
done
