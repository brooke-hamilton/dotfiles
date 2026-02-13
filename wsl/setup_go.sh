#!/bin/bash

set -e

# Script to set up Go environment modified from https://go.dev/doc/install
GO_VERSION="1.26.0"
GO_FILE="go${GO_VERSION}.linux-amd64.tar.gz"

echo "Setting up Go version ${GO_VERSION}..."

# Download and install Go
wget -q "https://golang.org/dl/${GO_FILE}"
rm -rf /usr/local/go
tar -C /usr/local -xzf "${GO_FILE}"
rm "${GO_FILE}"

# shellcheck disable=SC2016
echo 'export PATH=$PATH:/usr/local/go/bin' | tee -a /etc/profile >/dev/null

# Tools
echo "Installing Go tools..."
go install sigs.k8s.io/controller-tools/cmd/controller-gen@latest
go install github.com/go-delve/delve/cmd/dlv@latest
go install github.com/suzuki-shunsuke/ghalint/cmd/ghalint@latest
go install golang.org/x/tools/gopls@latest
go install gotest.tools/gotestsum@latest
go install go.uber.org/mock/mockgen@latest
go install sigs.k8s.io/controller-runtime/tools/setup-envtest@latest
go install honnef.co/go/tools/cmd/staticcheck@latest
go install github.com/stern/stern@latest

# golangci-lint: https://golangci-lint.run/welcome/install/#binaries
curl -sSfL https://raw.githubusercontent.com/golangci/golangci-lint/HEAD/install.sh | sh -s -- -b "$(go env GOPATH)/bin" v1.64.6
