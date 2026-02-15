#!/usr/bin/env bash
set -euo pipefail

# Installs the latest GitHub Release of PowerShell/DSC on Linux.

REPO_OWNER="PowerShell"
REPO_NAME="DSC"
INSTALL_DIR="/usr/local/bin"

for cmd in curl tar jq; do
    command -v "${cmd}" >/dev/null 2>&1 || {
        echo "Missing required command: ${cmd}" >&2
        exit 1
    }
done

ARCH="$(uname -m)"
case "${ARCH}" in
    x86_64 | amd64) ARCH_FILTER="x86_64" ;;
    aarch64 | arm64) ARCH_FILTER="aarch64" ;;
    *)
        echo "Unsupported architecture: ${ARCH}" >&2
        exit 1
        ;;
esac

API_URL="https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/releases/latest"

echo "Fetching latest release from ${REPO_OWNER}/${REPO_NAME}" >&2
JSON="$(curl -fsSL -H "Accept: application/vnd.github+json" "${API_URL}")"

TAG="$(printf '%s' "${JSON}" | jq -r '.tag_name')"
echo "Latest release: ${TAG}" >&2

# Asset naming convention: DSC-{version}-{arch}-linux.tar.gz
ASSET_URL="$(
    printf '%s' "${JSON}" \
        | jq -r --arg arch "${ARCH_FILTER}" \
            '.assets[].browser_download_url
             | select(test("linux")) | select(test($arch))
             | select(test("\\.(tar\\.gz|tgz)$"))'
)"

if [[ -z "${ASSET_URL:-}" ]]; then
    echo "No matching Linux/${ARCH_FILTER} asset found in release ${TAG}" >&2
    exit 1
fi

FILENAME="$(basename "${ASSET_URL}")"
WORKDIR="$(mktemp -d)"
cleanup() { rm -rf "${WORKDIR}"; }
trap cleanup EXIT

echo "Downloading ${FILENAME}" >&2
curl -fL --retry 3 --retry-delay 1 -o "${WORKDIR}/${FILENAME}" "${ASSET_URL}"

tar -xzf "${WORKDIR}/${FILENAME}" -C "${WORKDIR}"

install -m 0755 "${WORKDIR}/dsc" "${INSTALL_DIR}/dsc"

echo "Installed: ${INSTALL_DIR}/dsc" >&2
"${INSTALL_DIR}/dsc" --version