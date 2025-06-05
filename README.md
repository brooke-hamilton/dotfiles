# dotfiles

This setup is for Windows 11 + WSL as a dev environment for [Radius](https://github.com/radius-project). The [radius-dev-config](https://github.com/brooke-hamilton/radius-dev-config) repo is included as a submodule and is part of the setup process.

## Prerequisites

- Windows 11 24H2 Pro or Enterprise
- [`winget`](https://learn.microsoft.com/en-us/windows/package-manager/winget/#install-winget) version 1.6 or higher (Open a terminal window and run `winget --version` to check.)

## Steps

1. Log into Windows and clone this repo into the %userprofile% profile folder. Be sure to include submodules: `git clone https://github.com/brooke-hamilton/dotfiles --recurse-submodules`
1. Open a PowerShell terminal window as Administrator, navigate to the repo folder, and run `.\install.ps1`
1. Reboot.
1. Open Windows Terminal and launch the Ubuntu WSL distro. Complete the Ubuntu [OOBE](https://en.wikipedia.org/wiki/Out-of-box_experience) setup, i.e., log into Ubuntu and set your credentials.
1. From the Ubuntu terminal, run `./install_wsl.sh`. (You can run it from its Windows location at `/mnt/c/users/<username>/dotfiles`.)

## Notes

When WSL hangs, and `wsl --shutdown` does not work, and the Windows Service does not respond to a restart command, run this command to kill the service.

```PowerShell
taskkill /f /im wslservice.exe
```
