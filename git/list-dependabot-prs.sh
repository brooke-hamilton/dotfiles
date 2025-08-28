#!/bin/bash

# Script to list all open Dependabot PRs in the radius-project organization
# Requires GitHub CLI (gh) to be installed and authenticated

set -e

ORG="radius-project"

# Column width constants
REPO_WIDTH=20
TITLE_WIDTH=50
TITLE_MAX_CHARS=$((TITLE_WIDTH - 4))  # Leave room for "... " (4 characters)

echo "Fetching open Dependabot PRs for organization: $ORG"
echo

# Check if gh CLI is installed and authenticated
if ! command -v gh &> /dev/null; then
    echo "Error: GitHub CLI (gh) is not installed"
    exit 1
fi

if ! gh auth status &> /dev/null; then
    echo "Error: Not authenticated with GitHub CLI. Run 'gh auth login' first."
    exit 1
fi

# Print header with consistent formatting
printf "%-${REPO_WIDTH}s %-${TITLE_WIDTH}s %s\n" "Repository" "PR Title" "URL"
printf "%-${REPO_WIDTH}s %-${TITLE_WIDTH}s %s\n" "----------" "--------" "---"

# Get all public repositories for the organization
repos=$(gh repo list "$ORG" --visibility=public --limit 1000 --json name --jq '.[].name')

# Loop through each repository and check for Dependabot PRs
for repo in $repos; do
    # Get open PRs authored by dependabot
    prs=$(gh pr list --repo "$ORG/$repo" --author "app/dependabot" --state open --json title,url --jq '.[] | "\(.title)|\(.url)"')
    
    # If there are PRs, format and output them immediately
    if [ -n "$prs" ]; then
        while IFS='|' read -r title url; do
            # Truncate title if it's too long (leaving room for "... ")
            if [ ${#title} -gt $TITLE_MAX_CHARS ]; then
                truncated_title="${title:0:$TITLE_MAX_CHARS}... "
            else
                truncated_title="$title"
            fi
            printf "%-${REPO_WIDTH}s %-${TITLE_WIDTH}s %s\n" "$repo" "$truncated_title" "$url"
        done <<< "$prs"
    fi
done

echo
echo "Done!"
