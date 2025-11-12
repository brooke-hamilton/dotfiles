#!/bin/bash

# ============================================================================
# Install Microsoft Edit Tool
#
# This script downloads the latest release of Microsoft Edit from GitHub
# and installs it to /usr/local/bin.
# ============================================================================

set -euo pipefail

# Configuration
readonly GITHUB_ORG="microsoft"
readonly GITHUB_REPO="edit"
readonly INSTALL_DIR="/usr/local/bin"

detect_architecture() {
    local machine_arch
    machine_arch=$(uname -m)

    case "$machine_arch" in
    x86_64 | amd64)
        echo "x86_64"
        ;;
    aarch64 | arm64)
        echo "aarch64"
        ;;
    *)
        echo "Error: Unsupported architecture: $machine_arch" >&2
        echo "Supported architectures: x86_64, aarch64" >&2
        exit 1
        ;;
    esac
}

validate_requirements() {
    # Check for required commands
    local required_commands=("curl" "tar" "zstd" "sudo")
    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" &>/dev/null; then
            echo "Error: Required command '$cmd' is not installed" >&2
            if [[ "$cmd" == "zstd" ]]; then
                echo "Install with: sudo apt install zstd" >&2
            fi
            exit 1
        fi
    done

    # Check if installation directory exists, create if needed
    if [[ ! -d "$INSTALL_DIR" ]]; then
        echo "Creating installation directory: $INSTALL_DIR"
        if ! sudo mkdir -p "$INSTALL_DIR"; then
            echo "Error: Failed to create directory $INSTALL_DIR" >&2
            exit 1
        fi
    fi
}

get_latest_version() {
    echo "Fetching latest release information..." >&2

    local api_url="https://api.github.com/repos/${GITHUB_ORG}/${GITHUB_REPO}/releases/latest"
    local version_info

    if ! version_info=$(curl -sSf "$api_url" 2>/dev/null); then
        echo "Error: Failed to fetch release information from GitHub API" >&2
        echo "Please check your internet connection and try again" >&2
        exit 1
    fi

    # Extract version tag (remove 'v' prefix)
    local version
    if ! version=$(echo "$version_info" | grep '"tag_name"' | sed -E 's/.*"tag_name": "v?([^"]+)".*/\1/'); then
        echo "Error: Could not parse version information" >&2
        exit 1
    fi

    if [[ -z "$version" ]]; then
        echo "Error: Could not determine latest version" >&2
        exit 1
    fi

    echo "$version"
}

download_and_install() {
    local version="$1"
    local arch="$2"
    local archive_name="edit-${version}-${arch}-linux-gnu.tar.zst"
    local download_url="https://github.com/${GITHUB_ORG}/${GITHUB_REPO}/releases/download/v${version}/${archive_name}"
    local temp_dir
    temp_dir=$(mktemp -d)
    local archive_path="${temp_dir}/${archive_name}"
    local edit_path="${INSTALL_DIR}/edit"

    # Ensure cleanup on exit
    trap '[[ -n "${temp_dir:-}" ]] && rm -rf "$temp_dir"' EXIT

    echo "Installing Microsoft Edit v${version} (${arch})..."

    # Check if edit already exists
    if [[ -f "$edit_path" ]]; then
        echo "Edit is already installed. Updating..."
    fi

    # Download the archive
    echo "Downloading ${archive_name}..."
    if ! curl -sSL "$download_url" -o "$archive_path"; then
        echo "Error: Failed to download edit" >&2
        exit 1
    fi

    # Extract and install
    echo "Installing to ${INSTALL_DIR}..."
    if ! tar --use-compress-program=zstd -xf "$archive_path" -C "$temp_dir"; then
        echo "Error: Failed to extract archive" >&2
        exit 1
    fi

    # Find and copy the binary
    local extracted_binary
    extracted_binary=$(find "$temp_dir" -name "edit" -type f -executable | head -1)
    if [[ -z "$extracted_binary" ]]; then
        echo "Error: Could not find edit binary in archive" >&2
        exit 1
    fi

    sudo cp "$extracted_binary" "$edit_path"
    sudo chmod +x "$edit_path"

    echo "✅ Edit installed successfully!"
    echo "Run: edit --version"
}

main() {
    local arch
    arch=$(detect_architecture)
    validate_requirements

    local version
    version=$(get_latest_version)

    download_and_install "$version" "$arch"
}

# Execute main function
main
