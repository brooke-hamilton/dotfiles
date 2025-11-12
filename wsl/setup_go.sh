#!/bin/bash

set -e

# Script to set up Go environment modified from https://go.dev/doc/install
GO_VERSION="1.24.1"
GO_FILE="go${GO_VERSION}.linux-amd64.tar.gz"

echo "Setting up Go version ${GO_VERSION}..."

# Download and install Go
wget -q https://golang.org/dl/${GO_FILE}
sudo rm -rf /usr/local/go
sudo tar -C /usr/local -xzf ${GO_FILE}
rm ${GO_FILE}

# shellcheck disable=SC2016
echo 'export PATH=$PATH:/usr/local/go/bin' | sudo tee -a /etc/profile >/dev/null
# shellcheck disable=SC2016
echo 'export PATH=$PATH:$(go env GOPATH)/bin' >>~/.bashrc
# shellcheck disable=SC1091
. /etc/profile
# shellcheck disable=SC1090
. ~/.bashrc

# Tools
go install gotest.tools/gotestsum@latest
go install sigs.k8s.io/controller-tools/cmd/controller-gen@v0.16.0
go install go.uber.org/mock/mockgen@v0.4.0
go install github.com/stern/stern@latest

# golanci-lint: https://golangci-lint.run/welcome/install/#binaries
curl -sSfL https://raw.githubusercontent.com/golangci/golangci-lint/HEAD/install.sh | sh -s -- -b "$(go env GOPATH)/bin" v1.64.6
