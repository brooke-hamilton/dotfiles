#!/bin/bash

# Exercise Node tooling setup without downloading or installing software.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ $# == 0 ]]; then
    for scenario in windows-path native-rerun startup-order windows-node windows-runtime wrong-prefix \
        npm-failure windows-pnpm windows-copilot; do
        result=0
        bash "${BASH_SOURCE[0]}" "${scenario}" || result=$?
        case "${scenario}" in
            windows-path | native-rerun | startup-order)
                [[ "${result}" == 0 ]]
                ;;
            npm-failure)
                [[ "${result}" == 99 ]]
                ;;
            *)
                [[ "${result}" == 1 ]]
                ;;
        esac
        echo "PASS: ${scenario}"
    done
    exit 0
fi

scenario="${1}"
test_dir="$(mktemp -d)"
trap 'rm -rf -- "${test_dir}"' EXIT
export HOME="${test_dir}/home"
export CALL_LOG="${test_dir}/calls"
export TEST_SCENARIO="${scenario}"
export WINDOWS_BIN="${test_dir}/Windows Node"
export NODE_PREFIX="${HOME}/.nvm/versions/node/v24.0.0"
mkdir -p "${HOME}/.nvm" "${WINDOWS_BIN}" "${NODE_PREFIX}/bin"
touch "${CALL_LOG}"

make_command() {
    printf '#!/bin/bash\nfake_%s "$@"\n' "${2}" >"${1}"
    chmod +x "${1}"
}

fake_windows() {
    echo "Error: executed an inherited Windows tool." >&2
    exit 97
}

fake_node() {
    if [[ "${1}" == -p ]]; then
        if [[ "${TEST_SCENARIO}" == windows-runtime ]]; then
            echo win32
        else
            echo linux
        fi
    else
        echo v24.0.0
    fi
}

fake_pnpm() { echo 10.0.0; }
fake_copilot() { echo 'GitHub Copilot CLI test'; }

wslpath() {
    if [[ "${2}" == "${WINDOWS_BIN}" ]]; then
        printf 'C:\\Windows\\Node\n'
    else
        echo "Linux:${2}"
    fi
}

fake_npm() {
    echo "npm $*" >>"${CALL_LOG}"
    case "${1}" in
        prefix)
            if [[ "${TEST_SCENARIO}" == wrong-prefix ]]; then
                echo "${WINDOWS_BIN}"
            else
                echo "${NODE_PREFIX}"
            fi
            ;;
        install)
            if [[ "${TEST_SCENARIO}" == npm-failure ]]; then
                return 99
            fi
            case "${*}" in
                *'@github/copilot'*)
                    if [[ "${TEST_SCENARIO}" == windows-copilot ]]; then
                        ln -sf "${WINDOWS_BIN}/copilot" \
                            "${NODE_PREFIX}/bin/copilot"
                    else
                        make_command "${NODE_PREFIX}/bin/copilot" copilot
                    fi
                    ;;
                *)
                    if [[ "${TEST_SCENARIO}" == windows-pnpm ]]; then
                        ln -sf "${WINDOWS_BIN}/pnpm" "${NODE_PREFIX}/bin/pnpm"
                    else
                        make_command "${NODE_PREFIX}/bin/pnpm" pnpm
                    fi
                    ;;
            esac
            ;;
        ls) [[ -f "${NODE_PREFIX}/bin/copilot" ]] ;;
        --version) echo 11.0.0 ;;
        *) return 1 ;;
    esac
}

fake_nvm() {
    local NVM_VERSION=mock
    [[ "${NVM_VERSION}" == mock ]]
    echo "nvm $*" >>"${CALL_LOG}"
    case "${1}" in
        install)
            [[ "${2}" == --lts ]]
            if [[ "${TEST_SCENARIO}" == windows-node ]]; then
                ln -sf "${WINDOWS_BIN}/node" "${NODE_PREFIX}/bin/node"
            else
                make_command "${NODE_PREFIX}/bin/node" node
            fi
            make_command "${NODE_PREFIX}/bin/npm" npm
            ;;
        alias) [[ "${2}" == default && "${3}" == 'lts/*' ]] ;;
        use)
            [[ "${2}" == 'lts/*' ]]
            export NVM_BIN="${NODE_PREFIX}/bin"
            export PATH="${NVM_BIN}:${PATH}"
            ;;
        *) return 1 ;;
    esac
}

export -f make_command fake_windows fake_node fake_npm fake_pnpm fake_copilot
for tool in node npm pnpm copilot; do
    make_command "${WINDOWS_BIN}/${tool}" windows
done
make_command "${WINDOWS_BIN}/windows-only-tool" windows
ln -s "${WINDOWS_BIN}" "${test_dir}/windows-link"
export PATH="${test_dir}/windows-link:${WINDOWS_BIN}:${PATH}"
printf 'nvm() { fake_nvm "$@"; }\n' >"${HOME}/.nvm/nvm.sh"

# shellcheck source=setup.sh
source "${SCRIPT_DIR}/setup.sh"
[[ "${WINDOWS_INTEROP_PATH}" == *"${WINDOWS_BIN}"* ]]
use_linux_path
[[ "${PATH}" != *"${WINDOWS_BIN}"* ]]
[[ "${PATH}" != *"${test_dir}/windows-link"* ]]
if type -P windows-only-tool; then
    echo "Error: Windows tool directory survived PATH filtering." >&2
    exit 1
fi
ensure_node
ensure_copilot_cli
for tool in node npm pnpm copilot; do
    is_nvm_command "${tool}"
done
grep -qx 'nvm install --lts' "${CALL_LOG}"
grep -qx 'nvm alias default lts/\*' "${CALL_LOG}"
grep -qx 'nvm use lts/\*' "${CALL_LOG}"
grep -qx 'npm install -g @github/copilot' "${CALL_LOG}"

if [[ "${scenario}" == native-rerun ]]; then
    ensure_node
    ensure_copilot_cli
    [[ "$(grep -cx 'npm install -g @github/copilot' "${CALL_LOG}")" == 1 ]]
fi

if [[ "${scenario}" == startup-order ]]; then
    go() { echo "${HOME}/go"; }
    gh.exe() { echo test-token; }
    ensure_bashrc
    ensure_bashrc
    # shellcheck disable=SC2016
    [[ "$(grep -Fc 'export PATH="$NVM_BIN:$PATH"' "${HOME}/.bashrc")" == 1 ]]

    export PATH="${WINDOWS_BIN}:${NVM_BIN}:/usr/bin:/bin"
    hash -p "${WINDOWS_BIN}/pnpm" pnpm
    # shellcheck disable=SC1091
    source "${HOME}/.bashrc"
    for tool in node npm pnpm copilot; do
        [[ "$(command -v "${tool}")" == "${NVM_BIN}/${tool}" ]]
        "${tool}" --version
    done
    [[ "${PATH}" == "${NVM_BIN}:"* ]]
    native_count_before="$(tr ':' '\n' <<<"${PATH}" | grep -Fxc "${NVM_BIN}")"
    # shellcheck disable=SC1091
    source "${HOME}/.bashrc"
    local_count=0
    IFS=: read -r -a path_entries <<<"${PATH}"
    for entry in "${path_entries[@]}"; do
        if [[ "${entry}" == "${NVM_BIN}" ]]; then
            local_count=$((local_count + 1))
        fi
    done
    [[ "${local_count}" == "${native_count_before}" ]]
fi
