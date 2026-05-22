# dotfiles

This setup is for Windows 11 + WSL as a dev environment for [Radius](https://github.com/radius-project).

## Prerequisites

- Windows 11 24H2 Pro or Enterprise
- [`winget`](https://learn.microsoft.com/en-us/windows/package-manager/winget/#install-winget) version 1.6 or higher (Open a terminal window and run `winget --version` to check.)
- Windows `sudo` enabled in **Inline** mode. Open Settings → System → For developers → Enable sudo → set "Configure how sudo runs applications" to **Inline**. Or from an elevated PowerShell:

  ```powershell
  sudo config --enable normal
  ```

- WinGet **Configuration** (extended features) enabled. Run once from an elevated PowerShell (accept the Microsoft Store agreement if prompted):

  ```powershell
  winget configure --enable
  ```

- **OneDrive signed in and finished syncing.** The `git-ssh` step expects `%ONEDRIVE%\.gitconfig` and `%ONEDRIVE%\.gitconfig-windows` to be present, and other steps may reference files under your OneDrive root. On a fresh machine — especially a Microsoft Dev Box — first sync can take a while. Confirm the OneDrive tray icon shows "Up to date" before running the installer. If OneDrive isn't ready, the install will still complete but the git-config symlinks will be skipped (you can re-run `install.ps1 -Only git-ssh` later once OneDrive has caught up).

## Steps

1. Log into Windows and clone this repo into the %userprofile% profile folder: `git clone https://github.com/brooke-hamilton/dotfiles`
1. Open a (non-elevated) PowerShell terminal in the repo folder and run `.\Invoke-Unattended.ps1`. This produces a single UAC prompt, then installs everything silently. It:
   - First runs the user-context steps (HKCU registry tweaks, npm/cargo/rustup user installs, git clones).
   - Then elevates once, temporarily lowers `ConsentPromptBehaviorAdmin` so child installers (Visual Studio, Office) do not pop additional UAC dialogs, runs the admin steps, and restores the original UAC setting in a `finally` block.
1. Reboot.
1. Open Windows Terminal and launch the Ubuntu WSL distro. Complete the Ubuntu [OOBE](https://en.wikipedia.org/wiki/Out-of-box_experience) setup, i.e., log into Ubuntu and set your credentials.
1. From the Ubuntu terminal, run `./install_wsl.sh`. (You can run it from its Windows location at `/mnt/c/users/<username>/dotfiles`.)

### Running `install.ps1` directly

`install.ps1` can also be invoked on its own. Useful switches:

- `-Only step1,step2` — run only the named steps.
- `-Skip step1,step2` — skip the named steps.
- `-UserOnly` — only run steps that do not require admin.
- `-AdminOnly` — only run steps that require admin (must be launched elevated).

Steps that require admin are tagged in the script and are skipped with a warning when the script is not elevated.

## Notes

When WSL hangs, and `wsl --shutdown` does not work, and the Windows Service does not respond to a restart command, run this command to kill the service.

```PowerShell
taskkill /f /im wslservice.exe
```
