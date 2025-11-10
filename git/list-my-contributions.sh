#!/bin/bash

# Script to list GitHub repositories where the user has contributed
# Usage: ./list-my-contributions.sh [YYYY-MM-DD]
# If no date is provided, defaults to one year ago

set -e

# Color codes for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if gh CLI is installed
if ! command -v gh &> /dev/null; then
    echo "Error: GitHub CLI (gh) is not installed."
    echo "Please install it from: https://cli.github.com/"
    exit 1
fi

# Check if user is authenticated
if ! gh auth status &> /dev/null; then
    echo "Error: Not authenticated with GitHub CLI."
    echo "Please run: gh auth login"
    exit 1
fi

# Get the current GitHub user
GITHUB_USER=$(gh api user --jq '.login')
echo -e "${BLUE}Finding contributions for user: ${GITHUB_USER}${NC}\n"

# Parse date parameter or default to one year ago
if [ -n "$1" ]; then
    START_DATE="$1"
else
    # Default to one year ago
    START_DATE=$(date -d "1 year ago" +%Y-%m-%d 2>/dev/null || date -v-1y +%Y-%m-%d 2>/dev/null)
fi

echo -e "${BLUE}Searching for contributions since: ${START_DATE}${NC}\n"

# Temporary file to store unique repositories
TEMP_FILE=$(mktemp)
trap 'rm -f $TEMP_FILE' EXIT

echo -e "${YELLOW}Searching for repositories with commits...${NC}"
# Search for commits by the user
gh search commits \
    --author="$GITHUB_USER" \
    --author-date=">=$START_DATE" \
    --limit 1000 \
    --json repository \
    --jq '.[] | .repository.nameWithOwner' 2>/dev/null | sort -u >> "$TEMP_FILE" || true

echo -e "${YELLOW}Searching for repositories with issues created...${NC}"
# Search for issues created by the user
gh search issues \
    --author="$GITHUB_USER" \
    --created=">=$START_DATE" \
    --limit 1000 \
    --json repository \
    --jq '.[] | .repository.nameWithOwner' 2>/dev/null | sort -u >> "$TEMP_FILE" || true

echo -e "${YELLOW}Searching for repositories with issues commented on...${NC}"
# Search for issues where user commented
gh search issues \
    --commenter="$GITHUB_USER" \
    --created=">=$START_DATE" \
    --limit 1000 \
    --json repository \
    --jq '.[] | .repository.nameWithOwner' 2>/dev/null | sort -u >> "$TEMP_FILE" || true

echo -e "${YELLOW}Searching for repositories with pull requests...${NC}"
# Search for PRs created by the user
gh search prs \
    --author="$GITHUB_USER" \
    --created=">=$START_DATE" \
    --limit 1000 \
    --json repository \
    --jq '.[] | .repository.nameWithOwner' 2>/dev/null | sort -u >> "$TEMP_FILE" || true

echo -e "${YELLOW}Searching for repositories with PR reviews...${NC}"
# Search for PRs reviewed by the user
gh search prs \
    --reviewed-by="$GITHUB_USER" \
    --created=">=$START_DATE" \
    --limit 1000 \
    --json repository \
    --jq '.[] | .repository.nameWithOwner' 2>/dev/null | sort -u >> "$TEMP_FILE" || true

# Get unique repositories and sort, filtering out empty lines
REPOS=$(sort -u "$TEMP_FILE" | grep -v '^$')
REPO_COUNT=$(echo "$REPOS" | grep -c '^' || echo 0)

echo ""
echo -e "${GREEN}===========================================${NC}"
echo -e "${GREEN}Found ${REPO_COUNT} repositories with contributions since ${START_DATE}${NC}"
echo -e "${GREEN}===========================================${NC}"
echo ""

if [ -n "$REPOS" ]; then
    echo "$REPOS" | while read -r repo; do
        echo "  - $repo"
    done
else
    echo "No repositories found."
fi

echo ""
echo -e "${BLUE}Summary:${NC}"
echo -e "  User: ${GITHUB_USER}"
echo -e "  Since: ${START_DATE}"
echo -e "  Total repositories: ${REPO_COUNT}"
