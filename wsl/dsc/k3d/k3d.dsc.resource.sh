#!/bin/bash
set -euo pipefail

# DSC 3 command-based resource: Ensure k3d is installed
# Install source: https://k3d.io/stable/#installation

# Ensure standard paths are available — DSC may invoke with a minimal PATH
export PATH="/usr/local/bin:/usr/bin:/bin:${PATH}"

emit_log() {
    local level="${1}"
    local message="${2}"
    jq --null-input --compact-output \
        --arg message "${message}" \
        --arg level "${level}" \
        '{"message":$message,"level":$level}' >&2
}

emit_error() {
    emit_log "error" "${1}"
}

get_current_state() {
    if command -v k3d >/dev/null 2>&1; then
        local ver
        ver="$(k3d version 2>/dev/null | head -n1 | awk '{print $3}')"
        jq --null-input --compact-output \
            --arg version "${ver}" \
            '{"_exist":true,"version":$version}'
    else
        printf '{"_exist":false,"version":""}\n'
    fi
}

do_get() {
    cat > /dev/null
    get_current_state
}

do_test() {
    local input_json
    input_json="$(cat)"
    local desired_exist
    desired_exist="$(printf '%s' "${input_json}" | jq --raw-output '._exist // true')"

    local actual
    actual="$(get_current_state)"
    local actual_exist
    actual_exist="$(printf '%s' "${actual}" | jq --raw-output '._exist')"
    local actual_version
    actual_version="$(printf '%s' "${actual}" | jq --raw-output '.version')"

    local in_desired_state="false"
    if [[ "${desired_exist}" == "true" && "${actual_exist}" == "true" ]]; then
        in_desired_state="true"
    elif [[ "${desired_exist}" == "false" && "${actual_exist}" == "false" ]]; then
        in_desired_state="true"
    fi

    jq --null-input --compact-output \
        --argjson _exist "${actual_exist}" \
        --arg version "${actual_version}" \
        --argjson _inDesiredState "${in_desired_state}" \
        '{"_exist":$_exist,"version":$version,"_inDesiredState":$_inDesiredState}'
}

do_set() {
    local input_json
    input_json="$(cat)"
    local desired_exist
    desired_exist="$(printf '%s' "${input_json}" | jq --raw-output '._exist // true')"

    local actual
    actual="$(get_current_state)"
    local actual_exist
    actual_exist="$(printf '%s' "${actual}" | jq --raw-output '._exist')"

    if [[ "${desired_exist}" == "true" && "${actual_exist}" == "false" ]]; then
        emit_log "information" "Installing k3d..."
        curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash >&2
    elif [[ "${desired_exist}" == "false" && "${actual_exist}" == "true" ]]; then
        local k3d_path
        k3d_path="$(command -v k3d)"
        emit_log "information" "Removing k3d at ${k3d_path}..."
        rm -f "${k3d_path}"
    fi

    get_current_state
}

do_export() {
    get_current_state
}

if [[ "$#" -eq 0 ]]; then
    emit_error "Command not provided; expected: get, test, set, export"
    exit 1
fi

case "$1" in
    get)
        do_get
        ;;
    test)
        do_test
        ;;
    set)
        do_set
        ;;
    export)
        do_export
        ;;
    *)
        emit_error "Invalid command: $1"
        exit 1
        ;;
esac
