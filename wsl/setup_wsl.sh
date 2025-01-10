# shellcheck disable=SC2148

# Description: Installs and configures tools for WSL.
# Usage: ./wsl-setup.sh

sudo apt-get update && sudo apt-get dist-upgrade -y

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

# WSL Utilities
# https://wslutiliti.es/wslu/install.html#debian
sudo apt install wslu -y

# Check if the "[user]" setting already exists in /etc/wsl.conf. If not, add the current user.
# This setting is not required when installing WSL from the Windows Store, but it is helpful when exporting the
# distro and importing it as another distro on the same machine.
if ! grep -q "\[user\]" /etc/wsl.conf; then
    # Append the "[user]" setting to /etc/wsl.conf
    echo -e "\n[user]\ndefault=$(whoami)" | sudo tee -a /etc/wsl.conf > /dev/null
fi
