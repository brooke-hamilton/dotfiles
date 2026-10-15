#!/bin/bash

# Install Docker Engine in an Ubuntu WSL 2 development distro, on demand.
set -euo pipefail

main() (
    if [[ "$(uname -r)" != *[Ww][Ss][Ll]2* ]]; then
        echo "Error: run this script inside a WSL 2 distro." >&2
        return 1
    fi
    if [[ "$(id -u)" == 0 ]]; then
        echo "Error: run as your regular WSL user, not with sudo." >&2
        return 1
    fi
    # shellcheck source=/dev/null
    . /etc/os-release
    if [[ "${ID}" != ubuntu ]]; then
        echo "Error: this installer supports Ubuntu WSL distros only." >&2
        return 1
    fi
    if [[ "$(ps -p 1 -o comm=)" != systemd ]]; then
        echo "Error: enable systemd in /etc/wsl.conf before installing." >&2
        echo "Set systemd=true under [boot], preserving other settings." >&2
        echo "Then terminate only this distro from Windows and reopen it." >&2
        return 1
    fi

    local user
    user="$(id -un)"

    if command -v docker >/dev/null; then
        if ! systemctl cat docker.service >/dev/null; then
            echo "Error: Docker CLI exists without a local Docker service." >&2
            echo "Disable Docker Desktop integration or repair Docker Engine." >&2
            return 1
        fi
        echo "Docker Engine is already installed; skipping installation."
    else
        local codename arch
        codename="${UBUNTU_CODENAME:-${VERSION_CODENAME:-}}"
        if [[ -z "${codename}" ]]; then
            echo "Error: /etc/os-release has no Ubuntu release codename." >&2
            return 1
        fi
        arch="$(dpkg --print-architecture)"

        echo "Installing Docker Engine from Docker's official APT repository."
        sudo apt-get update
        sudo apt-get install -y ca-certificates curl
        sudo install -m 0755 -d /etc/apt/keyrings
        sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
            -o /etc/apt/keyrings/docker.asc
        sudo chmod a+r /etc/apt/keyrings/docker.asc

        printf '%s\n' \
            'Types: deb' \
            'URIs: https://download.docker.com/linux/ubuntu' \
            "Suites: ${codename}" \
            'Components: stable' \
            "Architectures: ${arch}" \
            'Signed-By: /etc/apt/keyrings/docker.asc' |
            sudo tee /etc/apt/sources.list.d/docker.sources >/dev/null

        sudo apt-get update
        sudo apt-get install -y docker-ce docker-ce-cli containerd.io \
            docker-buildx-plugin docker-compose-plugin
    fi

    if systemctl is-enabled --quiet docker &&
        systemctl is-active --quiet docker; then
        echo "Docker service is already enabled and active."
    else
        sudo systemctl enable --now docker
    fi

    if [[ " $(id -nG "${user}") " != *" docker "* ]]; then
        echo "Adding ${user} to docker (grants root-equivalent access)."
        sudo usermod -aG docker "${user}"
    fi

    # A fresh group session avoids changing socket permissions or logging out.
    # Pin the local socket so a Desktop/remote context cannot pass validation.
    sg docker -c 'docker --host unix:///var/run/docker.sock version &&
        docker --host unix:///var/run/docker.sock ps'

    echo "Docker Engine is ready and enabled for future distro starts."
    echo "If this shell lacks the docker group, log in again or run newgrp docker."
    echo "Use the default Docker context and unset DOCKER_HOST/DOCKER_CONTEXT"
    echo "if your shell previously used Docker Desktop or a remote engine."
)

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
