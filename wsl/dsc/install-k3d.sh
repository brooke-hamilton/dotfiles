#!/bin/bash
set -e

# Function to test if k3d is properly installed and configured
test_k3d_installation() {
    echo "Testing k3d installation..."
    
    # Test if k3d command is available
    if ! command -v k3d &> /dev/null; then
        echo "Test failed: k3d command not found" >&2
        return 1
    fi
    
    # Test if configuration directory exists
    if [ ! -d "$HOME/.config/k3d" ]; then
        echo "Test failed: k3d configuration directory not found" >&2
        return 1
    fi
    
    # Test if bash completion is installed
    if [ ! -f "/etc/bash_completion.d/k3d" ]; then
        echo "Test failed: k3d bash completion not found" >&2
        return 1
    fi
    
    echo "All tests passed: k3d is properly installed and configured"
    return 0
}

# If script is called with 'test' argument, run only the test
if [ "$1" = "test" ]; then
    test_k3d_installation
    exit $?
fi

echo "Installing k3d and dependencies..."

# Install curl if not present
if ! command -v curl &> /dev/null; then
    echo "Installing curl..."
    sudo apt-get update
    sudo apt-get install -y curl
fi

# Install k3d if not present
if ! command -v k3d &> /dev/null; then
    echo "Installing k3d..."
    curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash
    
    # Verify installation
    if command -v k3d &> /dev/null; then
        echo "k3d installed successfully"
        k3d version
    else
        echo "k3d installation failed" >&2
        exit 1
    fi
else
    echo "k3d is already installed"
    k3d version
fi

# Create k3d configuration directory
if [ ! -d "$HOME/.config/k3d" ]; then
    echo "Creating k3d configuration directory..."
    mkdir -p "$HOME/.config/k3d"
    echo "Created k3d configuration directory"
else
    echo "k3d configuration directory already exists"
fi

# Set up k3d bash completion
if [ ! -f "/etc/bash_completion.d/k3d" ]; then
    echo "Setting up k3d bash completion..."
    k3d completion bash | sudo tee /etc/bash_completion.d/k3d > /dev/null
    echo "k3d bash completion installed"
else
    echo "k3d bash completion already installed"
fi

echo "k3d installation and configuration complete!"

# Run final test to verify everything is working
test_k3d_installation
