#!/bin/bash

# Test Go setup with temporary SDKs, mocked downloads and no real sudo.
set -euo pipefail

if [[ $# == 0 ]]; then
    bash "${BASH_SOURCE[0]}" amd64
    bash "${BASH_SOURCE[0]}" arm64
    exit 0
fi
test_arch="${1}"
uname() {
    case "${test_arch}" in
        amd64) echo x86_64 ;;
        arm64) echo aarch64 ;;
        *) return 1 ;;
    esac
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
test_dir="$(mktemp -d)"
trap 'rm -rf -- "${test_dir}"' EXIT
export HOME="${test_dir}/home"
mkdir -p "${HOME}" "${test_dir}/sdk-parent"
touch "${test_dir}/profile"
printf 'preserved user profile\n' >"${HOME}/.profile"
profile_before="$(sha256sum "${HOME}/.profile")"

# Substitute only system paths in a disposable copy of the real implementation.
sed -e "s|/usr/local/go|${test_dir}/sdk-parent/go|g" \
    -e "s|/etc/profile|${test_dir}/profile|g" \
    "${SCRIPT_DIR}/setup.sh" >"${test_dir}/setup.sh"
# shellcheck disable=SC1091
source "${test_dir}/setup.sh"
[[ "${ARCH}" == "${test_arch}" ]]

calls="${test_dir}/calls"
touch "${calls}"
test_version="1.27.3"
failure=""

sdk() {
    mkdir -p "${1}/bin"
    printf '#!/bin/bash\necho "go version go%s linux/%s"\n' \
        "${2}" "${ARCH}" >"${1}/bin/go"
    printf '#!/bin/bash\nexit 0\n' >"${1}/bin/gofmt"
    chmod +x "${1}/bin/go" "${1}/bin/gofmt"
}

metadata() {
    local checksum
    checksum="$(sha256sum "${test_dir}/archive.tar.gz")"
    checksum="${checksum%% *}"
    jq -n --arg version "${test_version}" --arg arch "${ARCH}" \
        --arg checksum "${checksum}" '
        [{version: ("go" + $version), stable: true, files: [
            {filename: ("go" + $version + ".linux-" + $arch + ".tar.gz"),
             os: "linux", arch: $arch, kind: "archive", sha256: $checksum}
        ]},
         {version: "go1.28rc1", stable: false, files: []},
         {version: "go1.9.9", stable: true, files: []}]
    ' >"${test_dir}/releases.json"
}

wslpath() {
    if [[ "${2}" == "${test_dir}/windows/"* ]]; then
        printf 'C:\\Windows\\Go\n'
    else
        echo "Linux:${2}"
    fi
}

sudo() {
    echo "sudo $*" >>"${calls}"
    # Ownership is asserted from the call; tests never need elevated privileges.
    if [[ "${1}" == chown ]]; then
        return
    fi
    if [[ "${failure}" == promotion && "${1}" == mv &&
        "${2}" == */new-go ]]; then
        echo "Mock SDK promotion failure" >&2
        return 1
    fi
    command "${@}"
}

curl() {
    echo "curl $*" >>"${calls}"
    local url="" output=""
    while [[ $# -gt 0 ]]; do
        case "${1}" in
            -o) output="${2}"; shift 2 ;;
            https:*) url="${1}"; shift ;;
            *) shift ;;
        esac
    done
    if [[ "${failure}" == download ]]; then
        echo "Mock download failure: ${url}" >&2
        return 22
    fi
    case "${url}" in
        *mode=json*) cat "${test_dir}/releases.json" ;;
        *tar.gz)
            cp "${test_dir}/archive.tar.gz" "${output}"
            if [[ "${failure}" == checksum ]]; then
                printf 'corrupt\n' >>"${output}"
            fi
            ;;
        *) echo "Unexpected URL: ${url}" >&2; return 1 ;;
    esac
}

expect_failure() {
    # Keep errexit active inside tested functions by using a child subshell.
    local result=0
    (set -e; "${@}") >"${test_dir}/failure.log" 2>&1 &
    local pid=$!
    wait "${pid}" || result=$?
    if [[ "${result}" == 0 ]]; then
        echo "Expected failure: $*" >&2
        return 1
    fi
}

sdk "${test_dir}/archive/go" "${test_version}"
tar -C "${test_dir}/archive" -czf "${test_dir}/archive.tar.gz" go
metadata
release="$(latest_go_release)"
IFS=$'\t' read -r version tarball checksum <<<"${release}"
[[ "${version}" == "${test_version}" ]]
[[ "${tarball}" == "go${version}.linux-${ARCH}.tar.gz" ]]
for invalid in '{}' '[]' 'not JSON' \
    '[{"version":"go1.28rc1","stable":true,"files":[]}]' \
    '[{"version":"go1.027.3","stable":true,"files":[]}]' \
    '[{"version":"go1.28.0","stable":true,"files":[]}]'; do
    printf '%s\n' "${invalid}" >"${test_dir}/releases.json"
    expect_failure latest_go_release
done
metadata
for filter in '.[0].files[0].sha256 = "invalid"' \
    '.[0].files[0].filename = "wrong.tar.gz"' \
    '.[0].files[0].arch = "unsupported"' \
    '.[0].files += .[0].files'; do
    jq "${filter}" "${test_dir}/releases.json" >"${test_dir}/invalid.json"
    cp "${test_dir}/invalid.json" "${test_dir}/releases.json"
    expect_failure latest_go_release
    metadata
done
failure=download
expect_failure latest_go_release
failure=""
echo "PASS: latest stable release, architecture, checksum and metadata validation"

export PATH="${GO_ROOT}/bin:${PATH}"
ensure_go "${version}" "${tarball}" "${checksum}"
[[ "$(go_sdk_version "${GO_ROOT}")" == "${test_version}" ]]
grep -q '^sudo chown -R root:root .*/new-go$' "${calls}"
echo "PASS: fresh SDK installation (${ARCH})"

sdk "${GO_ROOT}" 1.27.2
export GOTOOLCHAIN=auto
# Simulate automatic toolchain selection hiding the older base SDK.
# shellcheck disable=SC2016
printf '#!/bin/bash\nif [[ "${GOTOOLCHAIN}" == local ]]; then\n' \
    >"${GO_ROOT}/bin/go"
printf 'echo "go version go1.27.2 linux/%s"\nelse\n' \
    "${ARCH}" >>"${GO_ROOT}/bin/go"
printf 'echo "go version go1.27.3 linux/%s"\nfi\n' \
    "${ARCH}" >>"${GO_ROOT}/bin/go"
[[ "$(go version)" == *go1.27.3* ]]
[[ "$(go_sdk_version "${GO_ROOT}")" == 1.27.2 ]]
expect_failure verify_go "${test_version}"
ensure_go "${version}" "${tarball}" "${checksum}"
[[ "$(go_sdk_version "${GO_ROOT}")" == "${test_version}" ]]
[[ "${GOTOOLCHAIN}" == auto ]]
[[ ! -e "${HOME}/.config/go/env" ]]
downloads_before="$(grep -c '^curl ' "${calls}")"
ensure_go "${version}" "${tarball}" "${checksum}"
[[ "$(grep -c '^curl ' "${calls}")" == "${downloads_before}" ]]
[[ "$(grep -Fc 'export PATH=' "${test_dir}/profile")" == 1 ]]
[[ "$(sha256sum "${HOME}/.profile")" == "${profile_before}" ]]
echo "PASS: base SDK upgrade, automatic-selection isolation and rerun"

for failure in checksum download promotion; do
    sdk "${GO_ROOT}" 1.27.2
    expect_failure ensure_go "${version}" "${tarball}" "${checksum}"
    [[ "$(go_sdk_version "${GO_ROOT}")" == 1.27.2 ]]
    [[ -z "$(find "${test_dir}/sdk-parent" -name 'go.stage.*')" ]]
done
failure=""
sdk "${test_dir}/archive/go" 1.27.1
tar -C "${test_dir}/archive" -czf "${test_dir}/archive.tar.gz" go
metadata
release="$(latest_go_release)"
IFS=$'\t' read -r version tarball checksum <<<"${release}"
expect_failure ensure_go "${version}" "${tarball}" "${checksum}"
[[ "$(go_sdk_version "${GO_ROOT}")" == 1.27.2 ]]
sdk "${test_dir}/archive/go" "${test_version}"
tar -C "${test_dir}/archive" -czf "${test_dir}/archive.tar.gz" go
metadata
release="$(latest_go_release)"
IFS=$'\t' read -r version tarball checksum <<<"${release}"
ensure_go "${version}" "${tarball}" "${checksum}"
echo "PASS: download, checksum, archive-version and promotion failures"

rm "${GO_ROOT}/bin/gofmt"
ensure_go "${version}" "${tarball}" "${checksum}"
[[ -x "${GO_ROOT}/bin/gofmt" ]]
mv "${GO_ROOT}" "${test_dir}/sdk-parent/custom"
ln -s "${test_dir}/sdk-parent/custom" "${GO_ROOT}"
expect_failure ensure_go "${version}" "${tarball}" "${checksum}"
[[ -L "${GO_ROOT}" ]]
rm "${GO_ROOT}"
mv "${test_dir}/sdk-parent/custom" "${GO_ROOT}"
echo "PASS: incomplete SDK repair and custom SDK path preservation"

sdk "${HOME}/.local/share/go/old" 1.27.2
mkdir -p "${HOME}/.local/bin"
ln -s "${HOME}/.local/share/go/old/bin/go" "${HOME}/.local/bin/go"
ln -s "${HOME}/.local/share/go/old/bin/gofmt" "${HOME}/.local/bin/gofmt"
base_path="${PATH}"
export PATH="${HOME}/.local/bin:${PATH}"
expect_failure verify_go "${test_version}"
expect_failure ensure_go "${version}" "${tarball}" "${checksum}"
[[ -L "${HOME}/.local/bin/go" ]]
sdk "${HOME}/.local/share/go/old" "${test_version}"
verify_go "${test_version}"
ln -sf "${GO_ROOT}/bin/gofmt" "${HOME}/.local/bin/gofmt"
expect_failure verify_go "${test_version}"
export PATH="${base_path}"
mkdir -p "${test_dir}/windows"
ln -s "${GO_ROOT}/bin/go" "${test_dir}/windows/go"
# A real Windows-backed path is rejected before its executable runs.
sdk "${test_dir}/windows/sdk" "${test_version}"
export PATH="${test_dir}/windows/sdk/bin:${base_path}"
expect_failure verify_go "${test_version}"
export PATH="${base_path}"
echo "PASS: local shadow preservation, matching override and Windows rejection"

calls_before="$(wc -l <"${calls}")"
path_before="${PATH}"
system_profile_before="$(sha256sum "${test_dir}/profile")"
main --verify-go
[[ "$(wc -l <"${calls}")" == "$((calls_before + 1))" ]]
[[ "$(tail -n 1 "${calls}")" == 'curl '*mode=json* ]]
[[ "${PATH}" == "${path_before}" ]]
[[ "$(sha256sum "${test_dir}/profile")" == "${system_profile_before}" ]]
ensure_apt_packages() { echo "Unexpected APT invocation" >&2; exit 98; }
ensure_go_tools() { echo "Unexpected Go tool install" >&2; exit 98; }
main --only go
expect_failure main --only node
expect_failure main --only go --verify-go
expect_failure main --only
expect_failure main --unknown
echo "PASS: read-only verification, scoped setup and argument validation"

# A fresh full bootstrap installs its metadata parser before resolving Go.
# shellcheck disable=SC2317
(
    ensure_sysctl_settings() { :; }
    ensure_apt_packages() { echo apt-ready >>"${calls}"; }
    ensure_azure_cli() { exit 0; }
    main
)
[[ "$(tail -n 2 "${calls}" | head -n 1)" == apt-ready ]]
[[ "$(tail -n 1 "${calls}")" == 'curl '*mode=json* ]]
echo "PASS: full-bootstrap prerequisite ordering"
