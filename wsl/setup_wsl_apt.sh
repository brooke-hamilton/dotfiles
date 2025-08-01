#!/bin/bash

set -e

sudo apt-get update && sudo apt-get dist-upgrade -y

sudo apt-get install build-essential -y

# install latest git
sudo add-apt-repository ppa:git-core/ppa -y
sudo apt update
sudo apt install git -y

# install GitHub CLI
(type -p wget >/dev/null || (sudo apt update && sudo apt-get install wget -y)) \
    && sudo mkdir -p -m 755 /etc/apt/keyrings \
    && out=$(mktemp) && wget -nv -O$out https://cli.github.com/packages/githubcli-archive-keyring.gpg \
    && cat $out | sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg > /dev/null \
    && sudo chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
    && sudo apt update \
    && sudo apt install gh -y

GITHUB_TOKEN=$(gh.exe auth token)
export GITHUB_TOKEN
gh extension install github/gh-copilot
gh alias set co copilot --clobber

# WSL Utilities
# https://wslutiliti.es/wslu/install.html#debian
sudo apt install wslu -y

# Pyspelling: https://facelessuser.github.io/pyspelling/
sudo apt install pipx -y
pipx ensurepath
pipx install pyspelling
sudo apt-get install aspell aspell-en -y

# Procmon for Linux
# https://github.com/microsoft/ProcMon-for-Linux/blob/2.0.0.0/INSTALL.md#ubuntu-2004-2204-2404
# wget -q "https://packages.microsoft.com/config/ubuntu/$(lsb_release -rs)/packages-microsoft-prod.deb" -O packages-microsoft-prod.deb
# sudo dpkg -i packages-microsoft-prod.deb
# sudo apt-get update
# sudo apt-get install libncurses6 procmon -y
# rm packages-microsoft-prod.deb

# Postgres client
sudo apt installp ostgresql-client -y

# Terraform
wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt update && sudo apt install terraform