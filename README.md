# dotfiles

This setup is for Windows 11 + WSL as a dev environment for [Radius](https://github.com/radius-project). The [radius-dev-config](https://github.com/brooke-hamilton/radius-dev-config) repo is included as a submodule and is part of the setup process.

## Prerequisites

- Windows 11 24H2 Pro or Enterprise
- [`winget`](https://learn.microsoft.com/en-us/windows/package-manager/winget/#install-winget) version 1.6 or higher (Open a terminal window and run `winget --version` to check.)

## Steps

1. Log into Windows and clone this repo into the %userprofile% profile folder. Be sure to include submodules: `git clone https://github.com/brooke-hamilton/dotfiles --recurse-submodules`
1. Open a PowerShell terminal window as Administrator, navigate to the repo folder, and run `.\install.sh`
1. Reboot.
1. Open Windows Terminal and launch the Ubuntu WSL distro. Complete the Ubuntu [OOBE](https://en.wikipedia.org/wiki/Out-of-box_experience) setup.
1. From the Ubuntu terminal, run `./install_wsl_ubuntu.sh`.

> NOTE: You can run `./install_wsl_ubuntu.sh` from its location on windows by navigating to `/mnt/c/users/<username>/dotfiles`.
