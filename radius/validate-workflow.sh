#!/bin/bash

# Validation script for the Radius PR dev container workflow

set -e

echo "Validating Radius PR Dev Container workflow files..."

# Check if required files exist
echo "Checking required files..."
files=(
    ".github/workflows/radius-pr-devcontainer.yml"
    ".github/workflows/test-radius-pr-devcontainer.yml"
    "radius/Dockerfile.pr-devcontainer"
    "radius/Dockerfile.pr-devcontainer-test"
    "radius/setup_k3d_pr.sh"
    "radius/test-pr-container.sh"
    "radius/README-PR-DEVCONTAINER.md"
)

for file in "${files[@]}"; do
    if [ -f "$file" ]; then
        echo "✓ $file exists"
    else
        echo "✗ $file missing"
        exit 1
    fi
done

# Validate YAML files
echo "Validating YAML syntax..."
for yaml_file in .github/workflows/*.yml; do
    if python3 -c "import yaml; yaml.safe_load(open('$yaml_file'))" 2>/dev/null; then
        echo "✓ $yaml_file has valid YAML syntax"
    else
        echo "✗ $yaml_file has invalid YAML syntax"
        exit 1
    fi
done

# Validate shell scripts
echo "Validating shell script syntax..."
for script in radius/*.sh; do
    if [ -f "$script" ]; then
        if bash -n "$script"; then
            echo "✓ $script has valid syntax"
        else
            echo "✗ $script has invalid syntax"
            exit 1
        fi
    fi
done

echo "All validation checks passed!"
echo ""
echo "Next steps:"
echo "1. Commit and push these changes"
echo "2. Test the workflow by running it manually with a PR number"
echo "3. Verify the container builds and runs correctly"