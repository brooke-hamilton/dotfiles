#!/bin/bash

# Script to sync all forked repositories in a GitHub organization
# Uses `gh repo sync` to update forks with their upstream repositories
# Requires GitHub CLI (gh) to be installed and authenticated

set -euo pipefail

# Default values
ORG="brooke-hamilton"

# Functions
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo "Options:"
    echo "  -o, --org   GitHub organization or user (default: brooke-hamilton)"
    echo "  -h, --help  Show this help"
    exit 0
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -o|--org)
            ORG="$2"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Check if gh CLI is installed and authenticated
if ! command -v gh &>/dev/null; then
    echo "Error: GitHub CLI (gh) is not installed"
    exit 1
fi

# Repos that need default branch alignment with upstream
REPOS_NEEDING_BRANCH_SYNC=(
    "brooke-hamilton/radius-docs"
    "brooke-hamilton/radius-samples"
)

# Align fork's default branch with upstream if they differ
align_default_branch() {
    local fork_repo="$1"
    local fork_default upstream_owner upstream_repo upstream_default upstream_sha

    # Get fork's default branch and parent info
    fork_default=$(gh repo view "$fork_repo" --json defaultBranchRef --jq '.defaultBranchRef.name')
    upstream_owner=$(gh repo view "$fork_repo" --json parent --jq '.parent.owner.login')
    upstream_repo=$(gh repo view "$fork_repo" --json parent --jq '.parent.name')

    if [[ -z "$upstream_owner" || -z "$upstream_repo" ]]; then
        echo "  Warning: Could not determine upstream for $fork_repo"
        return 1
    fi

    upstream_default=$(gh repo view "$upstream_owner/$upstream_repo" --json defaultBranchRef --jq '.defaultBranchRef.name')

    if [[ "$fork_default" == "$upstream_default" ]]; then
        echo "  Default branch already aligned: $fork_default"
        return 0
    fi

    echo "  Aligning default branch: $fork_default -> $upstream_default"

    # Check if the upstream default branch exists in the fork
    if ! gh api "repos/$fork_repo/branches/$upstream_default" &>/dev/null; then
        # Create the branch from upstream's commit
        upstream_sha=$(gh api "repos/$upstream_owner/$upstream_repo/git/refs/heads/$upstream_default" --jq '.object.sha')
        echo "  Creating branch $upstream_default from upstream..."
        gh api "repos/$fork_repo/git/refs" -X POST -f ref="refs/heads/$upstream_default" -f sha="$upstream_sha" >/dev/null
    fi

    # Change the default branch
    gh repo edit "$fork_repo" --default-branch "$upstream_default"
    echo "  Default branch changed to $upstream_default"
}

echo "Fetching forked repositories for: $ORG"
echo

# Get all forked repos in the organization
repos=$(gh repo list "$ORG" --fork --json nameWithOwner --jq '.[].nameWithOwner')

if [[ -z "$repos" ]]; then
    echo "No forked repositories found for $ORG"
    exit 0
fi

# Sync each forked repository
while IFS= read -r repo; do
    echo "Syncing $repo..."

    # Check if this repo needs default branch alignment
    for special_repo in "${REPOS_NEEDING_BRANCH_SYNC[@]}"; do
        if [[ "$repo" == "$special_repo" ]]; then
            align_default_branch "$repo"
            break
        fi
    done

    if gh repo sync "$repo"; then
        echo "  Successfully synced $repo"
    else
        echo "  Failed to sync $repo"
    fi
    echo
done <<< "$repos"

echo "Sync complete"
