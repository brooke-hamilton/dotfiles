#!/bin/bash

# ============================================================================
# Download Radius CLI Binary
#
# This script downloads a specific version of the Radius CLI (rad) binary
# from GitHub releases and makes it executable.
# ============================================================================

set -euo pipefail

# Configuration
readonly GITHUB_ORG="radius-project"
readonly GITHUB_REPO="radius"

# Default values
RELEASE_VERSION_NUMBER=""
OS="linux"
ARCH="amd64"
OUTPUT_PATH="" # Will be set based on version

# Functions
usage() {
    echo "Usage: $0 <version> [options]"
    echo ""
    echo "Arguments:"
    echo "  version               Release version (required, e.g., 0.24.0)"
    echo ""
    echo "Options:"
    echo "  -o, --os OS          Operating system: linux (default) or darwin"
    echo "  -a, --arch ARCH      Architecture: amd64 (default) or arm64"
    echo "  -p, --path PATH      Output path for the binary (default: ./rad-<version>)"
    echo "  -h, --help           Show this help"
    echo ""
    echo "Examples:"
    echo "  $0 0.24.0                           # Download Linux AMD64 to ./rad-0.24.0"
    echo "  $0 0.24.0 --os darwin               # Download macOS AMD64 to ./rad-0.24.0"
    echo "  $0 0.24.0 --os darwin --arch arm64  # Download macOS ARM64 to ./rad-0.24.0"
    echo "  $0 0.24.0 --path /usr/local/bin/rad # Download to specific path"
    exit 0
}

validate_requirements() {
    # Check for required commands
    local required_commands=("curl")
    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" &>/dev/null; then
            echo "Error: Required command '$cmd' is not installed or not in PATH" >&2
            exit 1
        fi
    done

    # Validate required parameters
    if [[ -z "$RELEASE_VERSION_NUMBER" ]]; then
        echo "Error: Version number is required" >&2
        usage
    fi

    # Validate version format
    if [[ ! "$RELEASE_VERSION_NUMBER" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-rc[0-9]+)?$ ]]; then
        echo "Error: Invalid version format. Expected format: X.Y.Z or X.Y.Z-rcN" >&2
        exit 1
    fi

    # Validate OS
    if [[ "$OS" != "linux" && "$OS" != "darwin" ]]; then
        echo "Error: Invalid OS '$OS'. Must be 'linux' or 'darwin'" >&2
        exit 1
    fi

    # Validate architecture
    if [[ "$ARCH" != "amd64" && "$ARCH" != "arm64" ]]; then
        echo "Error: Invalid architecture '$ARCH'. Must be 'amd64' or 'arm64'" >&2
        exit 1
    fi
}

download_rad_cli() {
    # Set default output path if not provided
    if [[ -z "$OUTPUT_PATH" ]]; then
        OUTPUT_PATH="./rad-${RELEASE_VERSION_NUMBER}"
    fi

    local artifact_name="rad_${OS}_${ARCH}"
    local download_base="https://github.com/${GITHUB_ORG}/${GITHUB_REPO}/releases/download"
    local download_url="${download_base}/v${RELEASE_VERSION_NUMBER}/${artifact_name}"

    echo "============================================================================"
    echo "Downloading Radius CLI"
    echo "============================================================================"
    echo "Version: ${RELEASE_VERSION_NUMBER}"
    echo "OS: ${OS}"
    echo "Architecture: ${ARCH}"
    echo "Download URL: ${download_url}"
    echo "Output path: ${OUTPUT_PATH}"
    echo ""

    # Create output directory if it doesn't exist
    local output_dir
    output_dir=$(dirname "$OUTPUT_PATH")
    if [[ ! -d "$output_dir" ]]; then
        echo "Creating directory: $output_dir"
        mkdir -p "$output_dir"
    fi

    # Download the binary
    echo "Downloading..."
    if ! curl -sSL "$download_url" -o "$OUTPUT_PATH"; then
        echo "Error: Failed to download rad CLI from $download_url" >&2
        echo "Please check that the version exists and the URL is accessible" >&2
        exit 1
    fi

    # Make it executable
    chmod +x "$OUTPUT_PATH"

    echo "============================================================================"
    echo "Download completed successfully!"
    echo "============================================================================"
    echo "Binary location: $OUTPUT_PATH"
    echo ""
    echo "You can now run: $OUTPUT_PATH version"
}

main() {
    validate_requirements
    download_rad_cli
}

# Parse arguments
if [[ $# -eq 0 ]]; then
    echo "Error: Version number is required" >&2
    usage
fi

# Check for help first
if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    usage
fi

# First argument is always the version
RELEASE_VERSION_NUMBER="$1"
shift

# Parse remaining options
while [[ $# -gt 0 ]]; do
    case $1 in
    -o | --os)
        OS="$2"
        shift 2
        ;;
    -a | --arch)
        ARCH="$2"
        shift 2
        ;;
    -p | --path)
        OUTPUT_PATH="$2"
        shift 2
        ;;
    -h | --help)
        usage
        ;;
    *)
        echo "Unknown option: $1" >&2
        echo "Use --help for usage information" >&2
        exit 1
        ;;
    esac
done

# Execute main function
main
