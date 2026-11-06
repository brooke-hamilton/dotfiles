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
# Versions — Go uses the latest stable release; other tools are pinned here
# ============================================================================
readonly GO_ROOT="/usr/local/go"
readonly NVM_INSTALL_VERSION="0.40.3"
readonly KIND_VERSION="0.29.0"
readonly ORAS_VERSION="1.3.2"
readonly GOLANGCI_LINT_VERSION="2.12.2"
readonly DOTNET_VERSION="10.0.300"

# ============================================================================
# Helpers
# ============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
readonly WINDOWS_INTEROP_PATH="${PATH}"

use_linux_path() {
    local entry resolved windows_path
    local -a entries linux_entries=()
    IFS=: read -r -a entries <<<"${PATH}"
    for entry in "${entries[@]}"; do
        [[ -n "${entry}" && -d "${entry}" ]] || continue
        resolved="$(readlink -f "${entry}")"
        windows_path="$(wslpath -w "${resolved}")"
        if [[ "${windows_path}" =~ ^[A-Za-z]:\\ ]]; then
            echo "Ignoring Windows tool directory: ${entry}"
            continue
        fi
        linux_entries+=("${entry}")
    done
    if [[ ${#linux_entries[@]} == 0 ]]; then
        echo "Error: no Linux tool directories remain on PATH." >&2
        return 1
    fi
    PATH="$(
        IFS=:
        echo "${linux_entries[*]}"
    )"
    export PATH
    hash -r
}

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

is_nvm_command() {
    local command_path resolved_path
    command_path="$(type -P "${1}")" || return 1
    resolved_path="$(readlink -f "${command_path}")" || return 1
    [[ -n "${NVM_BIN:-}" &&
        "${command_path}" == "${NVM_BIN}/"* &&
        "${resolved_path}" == "${NVM_BIN%/bin}/"* ]]
}

# ============================================================================
# Kernel settings
# This setting is useful for running multiple k8s instances fs.inotify.max_user_instances=1024
# ============================================================================
ensure_sysctl_settings() {
    echo "Configuring inotify instances"

    local config="/etc/sysctl.d/99-radius-local-functional.conf"
    printf '%s\n' 'fs.inotify.max_user_instances=1024' |
        sudo tee "${config}"
    sudo sysctl -p "${config}"
    sysctl fs.inotify.max_user_instances
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
        libicu-dev
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
latest_go_release() {
    local url="https://go.dev/dl/?mode=json"
    echo "Reading latest stable Go release from ${url}" >&2
    curl --fail --show-error --silent --location "${url}" |
        jq -er --arg arch "${ARCH}" '
            if type != "array" then error("Invalid Go release metadata") end |
            [.[] | select(.stable == true)] |
            if length == 0 then error("No stable Go release found") end |
            map(if (.version |
                test("^go1\\.(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)$"))
                then . else error("Invalid stable Go version") end) |
            sort_by(.version | ltrimstr("go") | split(".") | map(tonumber)) |
            last |
            .version as $version |
            [.files[] | select(.os == "linux" and .arch == $arch
                and .kind == "archive")] |
            if length != 1 then error("Linux Go archive not found") end |
            .[0] |
            if .filename != ($version + ".linux-" + $arch + ".tar.gz")
                or (.sha256 | test("^[0-9a-f]{64}$") | not)
            then error("Invalid Go archive metadata") end |
            [($version | ltrimstr("go")), .filename, .sha256] | @tsv
        '
}

go_sdk_version() {
    local sdk="${1}" output
    output="$(GOTOOLCHAIN=local "${sdk}/bin/go" version)"
    if [[ ! "${output}" =~ ^go\ version\ go([0-9.]+)\ linux/${ARCH}$ ]]; then
        echo "Error: unexpected Linux Go SDK version: ${output}" >&2
        return 1
    fi
    printf '%s\n' "${BASH_REMATCH[1]}"
}

verify_go() {
    local version="${1}" current selected resolved windows_path
    if [[ ! -x "${GO_ROOT}/bin/go" || ! -x "${GO_ROOT}/bin/gofmt" ]]; then
        echo "Error: Go SDK missing at ${GO_ROOT}; run --only go." >&2
        return 1
    fi
    current="$(go_sdk_version "${GO_ROOT}")"
    if [[ "${current}" != "${version}" ]]; then
        echo "Error: ${GO_ROOT} has Go ${current}; latest stable is ${version}." >&2
        return 1
    fi
    if [[ "$(type -t go || true)" != file ]]; then
        echo "Error: PATH must select a Go executable, not an override." >&2
        return 1
    fi
    selected="$(command -v go)"
    resolved="$(readlink -f "${selected}")"
    windows_path="$(wslpath -w "${resolved}")"
    if [[ "${windows_path}" =~ ^[A-Za-z]:\\ ]]; then
        echo "Error: PATH selects Windows Go: ${selected}" >&2
        return 1
    fi
    current="$(go_sdk_version "$(dirname "$(dirname "${resolved}")")")"
    if [[ "${current}" != "${version}" ]]; then
        echo "Error: ${selected} shadows ${GO_ROOT} with Go ${current}." >&2
        echo "Adjust your PATH or explicitly update that SDK; it was preserved." >&2
        return 1
    fi
    if [[ "$(type -t gofmt || true)" != file ||
        "$(readlink -f "$(command -v gofmt)")" != \
        "$(dirname "${resolved}")/gofmt" ]]; then
        echo "Error: go and gofmt must select the same Linux SDK." >&2
        return 1
    fi
    echo "Go ${version}: SDK ${GO_ROOT}; PATH selects ${selected}"
    if [[ "${resolved}" != "${GO_ROOT}/bin/go" ]]; then
        echo "An existing matching user-selected SDK takes precedence."
    fi
}

ensure_go_sdk() (
    local version="${1}" tarball="${2}" checksum="${3}"
    local current="none" tmpdir="" backupdir=""
    trap 'if [[ -n "${tmpdir}" ]]; then
        rm -rf -- "${tmpdir}"
    fi
    if [[ -n "${backupdir}" ]]; then
        if [[ -d "${backupdir}/previous-go" && ! -e "${GO_ROOT}" ]]; then
            if ! sudo mv "${backupdir}/previous-go" "${GO_ROOT}"; then
                echo "Error: restore the saved SDK from ${backupdir}." >&2
                exit 1
            fi
        fi
        sudo rm -rf -- "${backupdir}"
    fi' EXIT

    echo "============================================================================"
    echo "Go ${version} (latest stable)"
    echo "============================================================================"

    if [[ -L "${GO_ROOT}" || ( -e "${GO_ROOT}" && ! -d "${GO_ROOT}" ) ]]; then
        echo "Error: refusing to replace a custom SDK path: ${GO_ROOT}" >&2
        return 1
    fi
    if [[ -x "${GO_ROOT}/bin/go" ]]; then
        current="$(go_sdk_version "${GO_ROOT}")"
    fi

    if [[ "${current}" != "${version}" ||
        ! -x "${GO_ROOT}/bin/gofmt" ]]; then
        echo "go: installing ${version} (was: ${current})"
        tmpdir="$(mktemp -d)"
        local archive_url="https://go.dev/dl/${tarball}"
        echo "Downloading ${archive_url}"
        curl --fail --show-error --silent --location "${archive_url}" \
            -o "${tmpdir}/${tarball}"
        printf '%s  %s\n' "${checksum}" "${tmpdir}/${tarball}" |
            sha256sum --check -
        tar -C "${tmpdir}" -xzf "${tmpdir}/${tarball}"
        if [[ ! -x "${tmpdir}/go/bin/gofmt" ||
            "$(go_sdk_version "${tmpdir}/go")" != "${version}" ]]; then
            echo "Error: downloaded SDK does not match release metadata." >&2
            return 1
        fi
        backupdir="$(sudo mktemp -d "${GO_ROOT}.stage.XXXXXX")"
        sudo mv "${tmpdir}/go" "${backupdir}/new-go"
        sudo chown -R root:root "${backupdir}/new-go"
        if [[ -d "${GO_ROOT}" ]]; then
            sudo mv "${GO_ROOT}" "${backupdir}/previous-go"
        fi
        sudo mv "${backupdir}/new-go" "${GO_ROOT}"
    else
        echo "go: ${version} already installed"
    fi
)

ensure_go() {
    local version="${1}"
    ensure_go_sdk "${@}"

    # Ensure PATH includes go
    if ! grep -q '/usr/local/go/bin' /etc/profile 2>/dev/null; then
        # shellcheck disable=SC2016
        echo 'export PATH=$PATH:/usr/local/go/bin' | sudo tee -a /etc/profile >/dev/null
    fi
    export PATH="${PATH}:/usr/local/go/bin"
    hash -r
    verify_go "${version}"
}

ensure_go_tools() {
    echo "============================================================================"
    echo "Go tools"
    echo "============================================================================"

    local gopath
    gopath="$(go env GOPATH)"
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
        # Skip if already installed; `go install ...@latest` otherwise always
        # re-resolves and rewrites the binary on every run.
        local bin_name="${tool##*/}"
        bin_name="${bin_name%@*}"
        if command -v "${bin_name}" &>/dev/null; then
            echo "${bin_name}: already installed"
            continue
        fi
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
    echo "Node.js LTS (via nvm ${NVM_INSTALL_VERSION})"
    echo "============================================================================"

    export NVM_DIR="${HOME}/.nvm"

    # Install or update nvm
    if [[ ! -s "${NVM_DIR}/nvm.sh" ]]; then
        echo "nvm: installing ${NVM_INSTALL_VERSION}"
        curl -o- "https://raw.githubusercontent.com/nvm-sh/nvm/v${NVM_INSTALL_VERSION}/install.sh" | bash
    fi

    # shellcheck disable=SC1091
    \. "${NVM_DIR}/nvm.sh" --no-use

    nvm install --lts
    nvm alias default 'lts/*'
    # An explicit alias avoids nvm's unset PROVIDED_VERSION with --lts.
    nvm use 'lts/*'
    hash -r

    local tool
    for tool in node npm; do
        if ! is_nvm_command "${tool}"; then
            echo "Error: ${tool} is not from the active Linux nvm install." >&2
            return 1
        fi
    done
    if [[ "$(node -p 'process.platform')" != linux ]]; then
        echo "Error: the active Node.js runtime is not Linux." >&2
        return 1
    fi
    if [[ "$(npm prefix -g)" != "${NVM_BIN%/bin}" ]]; then
        echo "Error: npm's global prefix is outside the active nvm install." >&2
        echo "Remove conflicting npm prefix settings before retrying." >&2
        return 1
    fi

    npm install -g pnpm typescript autorest oav
    hash -r
    if ! is_nvm_command pnpm; then
        echo "Error: pnpm is not from the active Linux nvm install." >&2
        return 1
    fi
    echo "node: $(node --version)"
    echo "npm: $(npm --version)"
    echo "pnpm: $(pnpm --version)"
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
    # Parse the client version deterministically; `kubectl version` text output
    # is brittle (extra lines, connection warnings) and breaks field matching.
    local current
    current="$(kubectl version --client -o json 2>/dev/null \
        | jq -r '.clientVersion.gitVersion' 2>/dev/null || echo "none")"

    if [[ "${current}" == "${latest}" ]]; then
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
    echo ".NET ${DOTNET_VERSION}"
    echo "============================================================================"

    local dotnet_installed="false"
    if command -v dotnet &>/dev/null; then
        if dotnet --list-sdks 2>/dev/null | grep -q "^${DOTNET_VERSION}"; then
            dotnet_installed="true"
        fi
    fi

    if [[ "${dotnet_installed}" == "false" ]]; then
        echo "dotnet: installing SDK ${DOTNET_VERSION}"
        local install_script
        install_script="$(mktemp)"
        wget -q https://dot.net/v1/dotnet-install.sh -O "${install_script}"
        chmod +x "${install_script}"
        sudo bash "${install_script}" --version "${DOTNET_VERSION}" --install-dir /usr/share/dotnet
        rm -f "${install_script}"
    else
        echo "dotnet: SDK ${DOTNET_VERSION} already installed"
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

    # PowerShell .deb assets use Debian arch naming (amd64/arm64), e.g.
    # powershell_7.6.2-1.deb_amd64.deb. Match that suffix and the non-LTS
    # package (startswith "powershell_") to pick exactly one asset.
    local deb_arch
    deb_arch="$(dpkg --print-architecture)"

    local ps_url
    ps_url="$(curl -s https://api.github.com/repos/PowerShell/PowerShell/releases/latest \
        | jq -r ".assets[] | select(.name | startswith(\"powershell_\") and endswith(\"_${deb_arch}.deb\")) | .browser_download_url" \
        | head -1)"

    if [[ -z "${ps_url}" || "${ps_url}" == "null" ]]; then
        echo "Error: could not resolve PowerShell download URL from GitHub API" >&2
        return 1
    fi

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
    local archive="edit-${latest_version}-${arch_edit}-linux-gnu.tar.gz"
    local tmpdir
    tmpdir="$(mktemp -d)"
    curl -sSL "https://github.com/microsoft/edit/releases/download/v${latest_version}/${archive}" -o "${tmpdir}/${archive}"
    tar -xzf "${tmpdir}/${archive}" -C "${tmpdir}"
    local binary
    binary="$(find "${tmpdir}" -name "edit" -type f -executable | head -1)"
    sudo cp "${binary}" /usr/local/bin/edit
    sudo chmod +x /usr/local/bin/edit
    rm -rf "${tmpdir}"
    echo "edit: $(edit --version 2>/dev/null | head -n1)"
}

# ============================================================================
# GitHub Copilot CLI
# ============================================================================
ensure_copilot_cli() {
    echo "============================================================================"
    echo "GitHub Copilot CLI"
    echo "============================================================================"

    if ! is_nvm_command node || ! is_nvm_command npm; then
        echo "Error: run ensure_node before installing Copilot CLI." >&2
        return 1
    fi

    if is_nvm_command copilot && npm ls -g --depth=0 @github/copilot; then
        echo "copilot: already installed ($(copilot --version))"
        return
    fi

    npm install -g @github/copilot
    hash -r
    if ! is_nvm_command copilot; then
        echo "Error: copilot is not from the active Linux nvm install." >&2
        return 1
    fi
    echo "copilot: $(copilot --version)"
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
    # shellcheck disable=SC2016
    onedrive_win="$(PATH="${WINDOWS_INTEROP_PATH}" powershell.exe -NoProfile -Command 'Write-Host -NoNewline $env:ONEDRIVE' 2>/dev/null | tr -d '\r' || true)"
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

    # nvm can preserve an existing PATH position behind Windows tools.
    # shellcheck disable=SC2016
    local node_path_line='[[ -z "${NVM_BIN:-}" || "$PATH" == "$NVM_BIN:"* ]]'
    # shellcheck disable=SC2016
    node_path_line+=' || export PATH="$NVM_BIN:$PATH"'
    add_to_bashrc "${node_path_line}"

    echo "Bashrc done"
}

# ============================================================================
# Main
# ============================================================================
main() {
    local mode="all" release version tarball checksum
    while [[ $# -gt 0 ]]; do
        case "${1}" in
            --only)
                if [[ $# -lt 2 || "${2}" != go || "${mode}" != all ]]; then
                    echo "Error: use --only go, without --verify-go." >&2
                    return 1
                fi
                mode="go"
                shift 2
                ;;
            --verify-go)
                if [[ "${mode}" != all ]]; then
                    echo "Error: --verify-go cannot be combined with --only." >&2
                    return 1
                fi
                mode="verify"
                shift
                ;;
            --help)
                echo "Usage: bash setup.sh [--only go | --verify-go]"
                return
                ;;
            *)
                echo "Error: unknown setup option: ${1}" >&2
                return 1
                ;;
        esac
    done
    if [[ "${mode}" != all ]]; then
        release="$(latest_go_release)"
        IFS=$'\t' read -r version tarball checksum <<<"${release}"
    fi
    if [[ "${mode}" == verify ]]; then
        verify_go "${version}"
        return
    fi
    if [[ "${mode}" == go ]]; then
        use_linux_path
        ensure_go "${version}" "${tarball}" "${checksum}"
        return
    fi

    echo "============================================================================"
    echo "WSL Setup — $(date)"
    echo "============================================================================"

    use_linux_path

    # Ensure a writable working directory. Some installers download into the
    # current directory before moving files into place; cloud-init runs with
    # cwd=/ which the user cannot write to.
    cd "${HOME}" 2>/dev/null || cd "$(mktemp -d)"

    ensure_sysctl_settings
    ensure_apt_packages
    release="$(latest_go_release)"
    IFS=$'\t' read -r version tarball checksum <<<"${release}"
    ensure_azure_cli
    ensure_go "${version}" "${tarball}" "${checksum}"
    ensure_go_tools
    ensure_node
    ensure_kubectl
    ensure_helm
    # ensure_kind
    ensure_k3d
    ensure_oras
    ensure_dotnet
    ensure_bicep
    ensure_powershell
    ensure_edit
    ensure_copilot_cli
    ensure_pipx_packages
    ensure_gitconfig
    ensure_bashrc

    echo "============================================================================"
    echo "WSL Setup Complete"
    echo "============================================================================"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
