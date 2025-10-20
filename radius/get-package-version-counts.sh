#!/bin/bash

# Script to get version counts for all packages
OWNER=$(gh repo view --json owner --jq '.owner.login')
OWNER_TYPE=$(gh api "/users/$OWNER" --jq '.type' 2>/dev/null)

# Function to get version count for a single package
get_package_info() {
    local package_name=$1
    local endpoint_prefix
    
    if [ "$OWNER_TYPE" = "Organization" ]; then
        endpoint_prefix="orgs"
    else
        endpoint_prefix="users"
    fi
    
    local version_count
    version_count=$(curl -s -H "Authorization: Bearer $GITHUB_TOKEN" \
      "https://api.github.com/${endpoint_prefix}/$OWNER/packages/container/${package_name//\//%2F}/versions?per_page=1" \
      -I | grep -i "link:" | sed -n 's/.*page=\([0-9]*\)>; rel="last".*/\1/p')
    
    # If no pagination header, count directly
    if [ -z "$version_count" ]; then
        version_count=$(curl -s -H "Authorization: Bearer $GITHUB_TOKEN" \
          "https://api.github.com/${endpoint_prefix}/$OWNER/packages/container/${package_name//\//%2F}/versions" \
          | jq '. | length')
    fi
    
    printf "%-50s %s\n" "$package_name" "$version_count"
}

printf "%-50s %s\n" "PACKAGE NAME" "VERSION COUNT"
printf "%-50s %s\n" "$(printf '%0.s-' {1..50})" "$(printf '%0.s-' {1..13})"

# Get all packages and their version counts
# Try organization endpoint first, fallback to user endpoint
if [ "$OWNER_TYPE" = "Organization" ]; then
    packages=$(curl -s -H "Authorization: Bearer $GITHUB_TOKEN" \
      "https://api.github.com/orgs/$OWNER/packages?package_type=container&per_page=100")
else
    packages=$(curl -s -H "Authorization: Bearer $GITHUB_TOKEN" \
      "https://api.github.com/users/$OWNER/packages?package_type=container&per_page=100")
fi

# Validate the response is valid JSON
if ! echo "$packages" | jq empty 2>/dev/null; then
    echo "Error: Failed to fetch packages. Invalid response from API."
    exit 1
fi

# Check if the response is an error message
if echo "$packages" | jq -e '.message' >/dev/null 2>&1; then
    echo "Error: API returned an error:"
    echo "$packages" | jq -r '.message'
    echo "Owner: $OWNER (Type: ${OWNER_TYPE:-User})"
    exit 1
fi

# Check if response is an array
if ! echo "$packages" | jq -e 'type == "array"' >/dev/null 2>&1; then
    echo "Error: Expected an array of packages but got:"
    echo "$packages" | jq '.'
    exit 1
fi

echo "$packages" | jq -r '.[] | .name' | while read -r package; do
    get_package_info "$package"
done