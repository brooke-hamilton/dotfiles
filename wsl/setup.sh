#!/bin/bash

# ============================================================================
# Idempotent WSL setup script
#
# Can be run by cloud-init on first boot or manually at any time. Each
# ensure_* function checks whether the tool is already installed at the
# desired version and only installs or upgrades when necessary.
# ============================================================================

set -euo pipefail

# ============================================================================
# Versions — the single place to bump tool versions
# ============================================================================
readonly GO_VERSION="1.26.0"
readonly NODE_VERSION="24"
readonly NVM_VERSION="0.40.3"
readonly KIND_VERSION="0.29.0"
readonly ORAS_VERSION="1.2.3"
readonly GOLANGCI_LINT_VERSION="1.64.6"
readonly DOTNET_8_PACKAGE="dotnet-sdk-8.0"
readonly DOTNET_10_VERSION="10.0.100"

# ============================================================================
# Helpers
# ============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR

# Detect architecture once
detect_arch() {
    local machine
    machine="$(uname -m)"
    case "${machine}" in
        x86_64 | amd64) echo "amd64" ;;
        aarch64 | arm64) echo "arm64" ;;
        *)
            echo "Error: unsupported architecture: ${machine}" >&2
            exit 1
            ;;
    esac
}

ARCH="$(detect_arch)"
readonly ARCH

# Return the installed version of a command, or "none" if not found.
installed_version() {
    local cmd="${1}"
    local version_flag="${2:---version}"
    local awk_field="${3:-2}"

    if ! command -v "${cmd}" &>/dev/null; then
        echo "none"
        return
    fi
    ${cmd} ${version_flag} 2>/dev/null | head -n1 | awk "{print \$${awk_field}}" | sed 's/^v//'
}

# ============================================================================
# APT packages & repositories
# ============================================================================
ensure_apt_packages() {
    echo "============================================================================"
    echo "APT packages"
    echo "============================================================================"

    sudo apt-get update
    sudo apt-get dist-upgrade -y

    # Core packages
    local -a packages=(
        build-essential
        curl
        wget
        jq
        ripgrep
        shellcheck
        zstd
        pipx
        aspell
        aspell-en
        postgresql-client
        apt-transport-https
        ca-certificates
        gnupg
        lsb-release
    )
    sudo apt-get install -y "${packages[@]}"

    # Git PPA
    if ! apt-cache policy git 2>/dev/null | grep -q "git-core/ppa"; then
        sudo add-apt-repository ppa:git-core/ppa -y
        sudo apt-get update
    fi
    sudo apt-get install -y git

    # GitHub CLI
    if ! command -v gh &>/dev/null; then
        sudo mkdir -p -m 755 /etc/apt/keyrings
        local tmpkey
        tmpkey="$(mktemp)"
        wget -nv -O "${tmpkey}" https://cli.github.com/packages/githubcli-archive-keyring.gpg
        sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg <"${tmpkey}" >/dev/null
        rm -f "${tmpkey}"
        sudo chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
            | sudo tee /etc/apt/sources.list.d/github-cli.list >/dev/null
        sudo apt-get update
    fi
    sudo apt-get install -y gh

    # Terraform
    if ! command -v terraform &>/dev/null; then
        wget -O- https://apt.releases.hashicorp.com/gpg \
            | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
        echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" \
            | sudo tee /etc/apt/sources.list.d/hashicorp.list >/dev/null
        sudo apt-get update
    fi
    sudo apt-get install -y terraform

    echo "APT packages done"
}

# ============================================================================
# Azure CLI
# ============================================================================
ensure_azure_cli() {
    echo "============================================================================"
    echo "Azure CLI"
    echo "============================================================================"

    if command -v az &>/dev/null; then
        echo "az: already installed ($(az version --query '"azure-cli"' -o tsv))"
        return
    fi

    sudo mkdir -p /etc/apt/keyrings
    curl -sLS https://packages.microsoft.com/keys/microsoft.asc \
        | gpg --dearmor | sudo tee /etc/apt/keyrings/microsoft.gpg >/dev/null
    sudo chmod go+r /etc/apt/keyrings/microsoft.gpg

    local az_dist
    az_dist="$(lsb_release -cs)"
    printf 'Types: deb\nURIs: https://packages.microsoft.com/repos/azure-cli/\nSuites: %s\nComponents: main\nArchitectures: %s\nSigned-by: /etc/apt/keyrings/microsoft.gpg\n' \
        "${az_dist}" "$(dpkg --print-architecture)" \
        | sudo tee /etc/apt/sources.list.d/azure-cli.sources >/dev/null
    sudo apt-get update
    sudo apt-get install -y azure-cli
    echo "az: installed"
}

# ============================================================================
# Go
# ============================================================================
ensure_go() {
    echo "============================================================================"
    echo "Go ${GO_VERSION}"
    echo "============================================================================"

    local current
    current="$(installed_version go version 3)"
    if [[ "${current}" == "${GO_VERSION}" ]]; then
        echo "go: ${GO_VERSION} already installed"
        return
    fi

    echo "go: installing ${GO_VERSION} (was: ${current})"
    local tarball="go${GO_VERSION}.linux-${ARCH}.tar.gz"
    wget -q "https://golang.org/dl/${tarball}"
    sudo rm -rf /usr/local/go
    sudo tar -C /usr/local -xzf "${tarball}"
    rm -f "${tarball}"

    # Ensure PATH includes go
    if ! grep -q '/usr/local/go/bin' /etc/profile 2>/dev/null; then
        # shellcheck disable=SC2016
        echo 'export PATH=$PATH:/usr/local/go/bin' | sudo tee -a /etc/profile >/dev/null
    fi
    export PATH="${PATH}:/usr/local/go/bin"
    echo "go: $(go version)"
}

ensure_go_tools() {
    echo "============================================================================"
    echo "Go tools"
    echo "============================================================================"

    local gopath
    gopath="$(go env GOPATH 2>/dev/null || echo "${HOME}/go")"
    export PATH="${PATH}:/usr/local/go/bin:${gopath}/bin"

    local -a tools=(
        "sigs.k8s.io/controller-tools/cmd/controller-gen@latest"
        "github.com/go-delve/delve/cmd/dlv@latest"
        "github.com/suzuki-shunsuke/ghalint/cmd/ghalint@latest"
        "golang.org/x/tools/gopls@latest"
        "gotest.tools/gotestsum@latest"
        "go.uber.org/mock/mockgen@latest"
        "sigs.k8s.io/controller-runtime/tools/setup-envtest@latest"
        "honnef.co/go/tools/cmd/staticcheck@latest"
        "github.com/stern/stern@latest"
    )

    for tool in "${tools[@]}"; do
        echo "go install ${tool}"
        go install "${tool}"
    done

    # golangci-lint
    local current_gl
    current_gl="$(installed_version golangci-lint version 4 2>/dev/null || echo "none")"
    if [[ "${current_gl}" != "${GOLANGCI_LINT_VERSION}" ]]; then
        echo "golangci-lint: installing ${GOLANGCI_LINT_VERSION} (was: ${current_gl})"
        curl -sSfL https://raw.githubusercontent.com/golangci/golangci-lint/HEAD/install.sh \
            | sh -s -- -b "$(go env GOPATH)/bin" "v${GOLANGCI_LINT_VERSION}"
    else
        echo "golangci-lint: ${GOLANGCI_LINT_VERSION} already installed"
    fi

    echo "Go tools done"
}

# ============================================================================
# Node.js (via nvm)
# ============================================================================
ensure_node() {
    echo "============================================================================"
    echo "Node.js ${NODE_VERSION} (via nvm ${NVM_VERSION})"
    echo "============================================================================"

    export NVM_DIR="${HOME}/.nvm"

    # Install or update nvm
    if [[ ! -s "${NVM_DIR}/nvm.sh" ]]; then
        echo "nvm: installing ${NVM_VERSION}"
        curl -o- "https://raw.githubusercontent.com/nvm-sh/nvm/v${NVM_VERSION}/install.sh" | bash
    fi

    # shellcheck disable=SC1091
    \. "${NVM_DIR}/nvm.sh"

    # Install desired Node version if not present
    if ! nvm ls "${NODE_VERSION}" &>/dev/null; then
        echo "node: installing ${NODE_VERSION}"
        nvm install "${NODE_VERSION}"
    else
        echo "node: ${NODE_VERSION} already installed"
    fi

    npm install -g typescript autorest oav
    echo "Node.js done"
}

# ============================================================================
# Kubernetes tools
# ============================================================================
ensure_kubectl() {
    echo "============================================================================"
    echo "kubectl"
    echo "============================================================================"

    local latest
    latest="$(curl -L -s https://dl.k8s.io/release/stable.txt)"
    local current
    current="$(installed_version kubectl version 3 2>/dev/null || echo "none")"
    # kubectl version --client prints "Client Version: v1.x.y"
    current="${current#v}"

    if [[ "v${current}" == "${latest}" ]]; then
        echo "kubectl: ${latest} already installed"
        return
    fi

    echo "kubectl: installing ${latest} (was: ${current})"
    local arch_k8s="${ARCH}"
    curl -LO "https://dl.k8s.io/release/${latest}/bin/linux/${arch_k8s}/kubectl"
    curl -LO "https://dl.k8s.io/release/${latest}/bin/linux/${arch_k8s}/kubectl.sha256"
    echo "$(cat kubectl.sha256)  kubectl" | sha256sum --check
    sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
    rm -f kubectl kubectl.sha256
    echo "kubectl: $(kubectl version --client --short 2>/dev/null || kubectl version --client)"
}

ensure_helm() {
    echo "============================================================================"
    echo "Helm"
    echo "============================================================================"

    if command -v helm &>/dev/null; then
        echo "helm: already installed ($(helm version --short))"
    else
        curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
    fi

    # helm-unittest plugin
    if helm plugin list 2>/dev/null | grep -q unittest; then
        echo "helm-unittest: already installed"
    else
        helm plugin install https://github.com/helm-unittest/helm-unittest.git
    fi
}

ensure_kind() {
    echo "============================================================================"
    echo "Kind ${KIND_VERSION}"
    echo "============================================================================"

    local current
    current="$(installed_version kind version 2)"
    if [[ "${current}" == "${KIND_VERSION}" ]]; then
        echo "kind: ${KIND_VERSION} already installed"
        return
    fi

    echo "kind: installing ${KIND_VERSION} (was: ${current})"
    local arch_kind="${ARCH}"
    [[ "${arch_kind}" == "amd64" ]] && arch_kind="amd64"
    [[ "${arch_kind}" == "arm64" ]] && arch_kind="arm64"
    curl -Lo ./kind "https://kind.sigs.k8s.io/dl/v${KIND_VERSION}/kind-linux-${arch_kind}"
    chmod +x ./kind
    sudo mv ./kind /usr/local/bin/kind
    echo "kind: $(kind version)"
}

ensure_k3d() {
    echo "============================================================================"
    echo "k3d"
    echo "============================================================================"

    if command -v k3d &>/dev/null; then
        echo "k3d: already installed ($(k3d version | head -n1))"
        return
    fi

    curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash
    echo "k3d: $(k3d version | head -n1)"
}

ensure_oras() {
    echo "============================================================================"
    echo "ORAS ${ORAS_VERSION}"
    echo "============================================================================"

    local current
    current="$(installed_version oras version 2 2>/dev/null || echo "none")"
    if [[ "${current}" == "${ORAS_VERSION}" ]]; then
        echo "oras: ${ORAS_VERSION} already installed"
        return
    fi

    echo "oras: installing ${ORAS_VERSION} (was: ${current})"
    local arch_oras="${ARCH}"
    [[ "${arch_oras}" == "amd64" ]] && arch_oras="amd64"
    [[ "${arch_oras}" == "arm64" ]] && arch_oras="arm64"
    local tarball="oras_${ORAS_VERSION}_linux_${arch_oras}.tar.gz"
    curl -LO "https://github.com/oras-project/oras/releases/download/v${ORAS_VERSION}/${tarball}"
    local tmpdir
    tmpdir="$(mktemp -d)"
    tar -zxf "${tarball}" -C "${tmpdir}"
    sudo mv "${tmpdir}/oras" /usr/local/bin/
    rm -rf "${tarball}" "${tmpdir}"
    echo "oras: $(oras version | head -n1)"
}

# ============================================================================
# .NET
# ============================================================================
ensure_dotnet() {
    echo "============================================================================"
    echo ".NET (${DOTNET_8_PACKAGE} + ${DOTNET_10_VERSION})"
    echo "============================================================================"

    # .NET 8 via apt
    if ! dpkg -s dotnet-sdk-8.0 &>/dev/null; then
        wget -q https://packages.microsoft.com/config/debian/12/packages-microsoft-prod.deb -O /tmp/packages-microsoft-prod.deb
        sudo dpkg -i /tmp/packages-microsoft-prod.deb
        rm -f /tmp/packages-microsoft-prod.deb
        sudo apt-get update
    fi
    sudo apt-get install -y "${DOTNET_8_PACKAGE}"

    # .NET 10 via install script
    local dotnet_10_installed="false"
    if command -v dotnet &>/dev/null; then
        if dotnet --list-sdks 2>/dev/null | grep -q "^${DOTNET_10_VERSION}"; then
            dotnet_10_installed="true"
        fi
    fi

    if [[ "${dotnet_10_installed}" == "false" ]]; then
        echo "dotnet: installing SDK ${DOTNET_10_VERSION}"
        local install_script
        install_script="$(mktemp)"
        wget -q https://dot.net/v1/dotnet-install.sh -O "${install_script}"
        chmod +x "${install_script}"
        sudo bash "${install_script}" --version "${DOTNET_10_VERSION}" --install-dir /usr/share/dotnet
        rm -f "${install_script}"
    else
        echo "dotnet: SDK ${DOTNET_10_VERSION} already installed"
    fi
}

# ============================================================================
# Bicep
# ============================================================================
ensure_bicep() {
    echo "============================================================================"
    echo "Bicep"
    echo "============================================================================"

    if command -v bicep &>/dev/null; then
        echo "bicep: already installed ($(bicep --version | head -n1))"
        return
    fi

    local arch_bicep="x64"
    [[ "${ARCH}" == "arm64" ]] && arch_bicep="arm64"
    curl -Lo /tmp/bicep "https://github.com/Azure/bicep/releases/latest/download/bicep-linux-${arch_bicep}"
    chmod +x /tmp/bicep
    sudo mv /tmp/bicep /usr/local/bin/bicep
    echo "bicep: $(bicep --version | head -n1)"
}

# ============================================================================
# PowerShell
# ============================================================================
ensure_powershell() {
    echo "============================================================================"
    echo "PowerShell"
    echo "============================================================================"

    if command -v pwsh &>/dev/null; then
        echo "pwsh: already installed ($(pwsh --version))"
        return
    fi

    local ps_arch="x64"
    [[ "${ARCH}" == "arm64" ]] && ps_arch="arm64"

    local ps_url
    ps_url="$(curl -s https://api.github.com/repos/PowerShell/PowerShell/releases/latest \
        | jq -r ".assets[] | select(.name | contains(\"deb\") and contains(\"${ps_arch}\")) | .browser_download_url" \
        | head -1)"

    wget -q -O /tmp/powershell.deb "${ps_url}"
    sudo dpkg -i /tmp/powershell.deb || sudo apt-get install -f -y
    rm -f /tmp/powershell.deb

    # PowerShell profile
    mkdir -p "${HOME}/.config/powershell"
    local profile_path="${HOME}/.config/powershell/Microsoft.PowerShell_profile.ps1"
    local profile_line=". \${HOME}/dotfiles/PowerShell/Microsoft.PowerShell_profile.ps1"
    if [[ ! -f "${profile_path}" ]] || ! grep -qF "${profile_line}" "${profile_path}"; then
        echo "${profile_line}" >"${profile_path}"
    fi
    echo "PowerShell done"
}

# ============================================================================
# Microsoft Edit
# ============================================================================
ensure_edit() {
    echo "============================================================================"
    echo "Microsoft Edit"
    echo "============================================================================"

    local latest_version
    latest_version="$(curl -s https://api.github.com/repos/microsoft/edit/releases/latest \
        | jq -r '.tag_name' | sed 's/^v//')"

    local current
    current="$(installed_version edit --version 2 2>/dev/null || echo "none")"
    if [[ "${current}" == "${latest_version}" ]]; then
        echo "edit: ${latest_version} already installed"
        return
    fi

    echo "edit: installing ${latest_version} (was: ${current})"
    local arch_edit="x86_64"
    [[ "${ARCH}" == "arm64" ]] && arch_edit="aarch64"
    local archive="edit-${latest_version}-${arch_edit}-linux-gnu.tar.zst"
    local tmpdir
    tmpdir="$(mktemp -d)"
    curl -sSL "https://github.com/microsoft/edit/releases/download/v${latest_version}/${archive}" -o "${tmpdir}/${archive}"
    tar --use-compress-program=zstd -xf "${tmpdir}/${archive}" -C "${tmpdir}"
    local binary
    binary="$(find "${tmpdir}" -name "edit" -type f -executable | head -1)"
    sudo cp "${binary}" /usr/local/bin/edit
    sudo chmod +x /usr/local/bin/edit
    rm -rf "${tmpdir}"
    echo "edit: $(edit --version 2>/dev/null | head -n1)"
}

# ============================================================================
# GitHub CLI extensions
# ============================================================================
ensure_gh_extensions() {
    echo "============================================================================"
    echo "GitHub CLI extensions"
    echo "============================================================================"

    local token
    token="$(gh.exe auth token 2>/dev/null || true)"
    if [[ -z "${token}" ]]; then
        echo "gh extensions: skipped (no Windows gh token available)"
        return
    fi
    export GITHUB_TOKEN="${token}"

    if ! gh extension list 2>/dev/null | grep -q "gh-copilot"; then
        gh extension install github/gh-copilot
    else
        echo "gh-copilot: already installed"
    fi
    gh alias set co copilot --clobber

    echo "GitHub CLI extensions done"
}

# ============================================================================
# pipx packages
# ============================================================================
ensure_pipx_packages() {
    echo "============================================================================"
    echo "pipx packages"
    echo "============================================================================"

    pipx ensurepath

    if pipx list 2>/dev/null | grep -q "pyspelling"; then
        echo "pyspelling: already installed"
    else
        pipx install pyspelling
    fi
}

# ============================================================================
# Git configuration (symlinks from OneDrive)
# ============================================================================
ensure_gitconfig() {
    echo "============================================================================"
    echo "Git configuration"
    echo "============================================================================"

    local onedrive_win
    onedrive_win="$(powershell.exe -NoProfile -Command 'Write-Host -NoNewline $env:ONEDRIVE' 2>/dev/null | tr -d '\r' || true)"
    if [[ -z "${onedrive_win}" ]]; then
        echo "gitconfig: skipped (OneDrive path not available)"
        return
    fi

    local onedrive
    onedrive="$(wslpath "${onedrive_win}")"

    if [[ -f "${onedrive}/.gitconfig" ]]; then
        ln -sf "${onedrive}/.gitconfig" ~/.gitconfig
        echo "Linked .gitconfig"
    fi

    if [[ -f "${onedrive}/.gitconfig-wsl" ]]; then
        ln -sf "${onedrive}/.gitconfig-wsl" ~/.gitconfig-wsl
        echo "Linked .gitconfig-wsl"
    fi
}

# ============================================================================
# Bashrc configuration
# ============================================================================
ensure_bashrc() {
    echo "============================================================================"
    echo "Bashrc configuration"
    echo "============================================================================"

    local bashprompt_path="${SCRIPT_DIR}/.bashprompt.sh"

    add_to_bashrc() {
        local line="${1}"
        if ! grep -qF "${line}" ~/.bashrc 2>/dev/null; then
            echo "${line}" >>~/.bashrc
            echo "Added: ${line}"
        fi
    }

    if [[ -f "${bashprompt_path}" ]]; then
        add_to_bashrc "source ${bashprompt_path}"
    fi

    # shellcheck disable=SC2016
    add_to_bashrc 'export GITHUB_TOKEN=$(gh.exe auth token)'
    # shellcheck disable=SC2016
    add_to_bashrc 'export PATH=$PATH:/usr/local/go/bin:$(go env GOPATH)/bin'
    add_to_bashrc 'export BROWSER="explorer.exe"'
    # shellcheck disable=SC2016
    add_to_bashrc 'export NVM_DIR="$HOME/.nvm"'
    # shellcheck disable=SC2016
    add_to_bashrc '[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"'
    # shellcheck disable=SC2016
    add_to_bashrc '[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"'

    echo "Bashrc done"
}

# ============================================================================
# Main
# ============================================================================
main() {
    echo "============================================================================"
    echo "WSL Setup — $(date)"
    echo "============================================================================"

    ensure_apt_packages
    ensure_azure_cli
    ensure_go
    ensure_go_tools
    ensure_node
    ensure_kubectl
    ensure_helm
    ensure_kind
    ensure_k3d
    ensure_oras
    ensure_dotnet
    ensure_bicep
    ensure_powershell
    ensure_edit
    ensure_gh_extensions
    ensure_pipx_packages
    ensure_gitconfig
    ensure_bashrc

    echo "============================================================================"
    echo "WSL Setup Complete"
    echo "============================================================================"
}

main "$@"
