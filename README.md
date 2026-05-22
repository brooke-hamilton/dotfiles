# dotfiles

A Windows 11 + WSL development environment for working on the
[Radius](https://github.com/radius-project) project.

## Prerequisites

- Windows 11 24H2 Pro or Enterprise.
- [`winget`](https://learn.microsoft.com/en-us/windows/package-manager/winget/#install-winget)
  1.6 or higher (`winget --version`).
- Windows `sudo` enabled in **Inline** mode (Settings → System → For developers →
  Enable sudo → Configure how sudo runs applications → **Inline**), or run
  the installer from an already-elevated terminal. From an elevated PowerShell:

  ```powershell
  sudo config --enable normal
  ```

- WinGet **Configuration** (extended features) enabled. The installer also
  runs this for you in its first admin step, but on a brand-new machine it's
  worth doing once up front so the Microsoft Store agreement prompt is out
  of the way:

  ```powershell
  winget configure --enable
  ```

- **OneDrive signed in and finished syncing.** The `git-ssh` step expects
  `%ONEDRIVE%\.gitconfig` and `%ONEDRIVE%\.gitconfig-windows` to be present.
  If OneDrive isn't ready, the install still completes but the git-config
  symlinks are skipped — re-run [install.ps1](install.ps1) `-Only git-ssh`
  later once sync has caught up.

## Install

1. Clone this repo into your profile folder:

   ```powershell
   git clone https://github.com/brooke-hamilton/dotfiles "$env:USERPROFILE\dotfiles"
   cd "$env:USERPROFILE\dotfiles"
   ```

2. From a **non-elevated** PowerShell, run the orchestrator:

   ```powershell
   .\Invoke-Unattended.ps1
   ```

   This:
   - **Phase 1 (admin):** elevates once via `sudo`, runs every step tagged
     `-RequiresAdmin` in [install.ps1](install.ps1) — winget feature enable,
     DSC install, the `apps`/`apps-to-remove` DSC documents (which also
     enables Windows Developer Mode so unprivileged symlinks work), Visual
     Studio Build Tools, Docker Desktop, the radius dev config, and
     `Remove-DesktopShortcuts.ps1`.
   - **Phase 2 (user):** runs the remaining steps unelevated — git/SSH
     symlinks, `.wslconfig`, cloud-init copy, HKCU desktop tweaks,
     `rustup target add`, `cargo install cargo-zigbuild`,
     `npm install -g @devcontainers/cli`, and the `apt-cacher-ng` container
     (after waiting for Docker Engine to come up).

   Admin runs first because user-pass steps depend on tools the admin pass
   installs (cargo, rustup, npm, docker).

3. Reboot.
4. Open Windows Terminal and launch the Ubuntu WSL distro. Complete the
   Ubuntu [OOBE](https://en.wikipedia.org/wiki/Out-of-box_experience).
5. From the Ubuntu shell, run the WSL setup script at
   `/mnt/c/users/<username>/dotfiles/wsl/setup.sh`.

### Single UAC prompt (opt-in)

Some bundled installers (Visual Studio, Office) re-elevate themselves via
the `runas` verb and produce additional UAC dialogs even though we already
elevated with `sudo`. To get exactly **one** UAC prompt for the entire
install, pass `-ConsentToLowerUAC`:

```powershell
.\Invoke-Unattended.ps1 -ConsentToLowerUAC
```

That switch temporarily writes
`HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System\ConsentPromptBehaviorAdmin = 0`
for the duration of the admin pass and restores the original value in a
`finally` block.

> **Security note:** while that registry value is `0`, any process running
> under your admin token can elevate without prompting. A hard kill of the
> elevated `pwsh` (taskkill, BSOD, power loss) leaves UAC at "elevate
> silently". The switch is opt-in for that reason. Without the switch, you
> may see a handful of extra UAC dialogs during installs.

### Dry-run

```powershell
.\Invoke-Unattended.ps1 -Plan
```

Prints the step plan and, for steps that own a DSC document, runs
`dsc config test` to show what state currently differs. Makes no changes.

### Running `install.ps1` directly

[install.ps1](install.ps1) can be invoked on its own:

| Switch                | Effect                                              |
| --------------------- | --------------------------------------------------- |
| `-Only step1,step2`   | Run only the named steps.                           |
| `-Skip step1,step2`   | Skip the named steps.                               |
| `-UserOnly`           | Only run steps that do not require admin.           |
| `-AdminOnly`          | Only run steps that require admin (must be elevated). |
| `-Plan`               | Dry-run; print the plan and test DSC state.         |

Steps that require admin are skipped with a warning when the script is not
elevated.

## What gets installed where

- [.configurations/apps.dsc.yaml](.configurations/apps.dsc.yaml) — most
  packages (VS Code, Node, Rustup, Zig, Office, Teams, PowerToys,
  SysInternals, …) plus the Developer Mode registry value.
- [.configurations/apps-to-remove.dsc.yaml](.configurations/apps-to-remove.dsc.yaml)
  — Store apps to uninstall.
- [.configurations/desktop-settings.dsc.yaml](.configurations/desktop-settings.dsc.yaml)
  — HKCU explorer / taskbar / theme tweaks.
- Visual Studio Build Tools and Docker Desktop are installed imperatively
  from [install.ps1](install.ps1) because they need installer switches
  the current DSC v3 `Microsoft.WinGet/Package` resource doesn't yet
  expose.

## Side effects worth knowing about

- `radius-dev-env` step clones
  `https://github.com/brooke-hamilton/radius-dev-config` into a sibling
  directory of this repo (`..\radius-dev-config`).
- [PowerShell/Initialize-GitSshConfiguration.ps1](PowerShell/Initialize-GitSshConfiguration.ps1)
  creates symlinks `~\.gitconfig` and `~\.gitconfig-windows` pointing at
  files under `%ONEDRIVE%`, sets the `ssh-agent` service to Automatic,
  and sets the machine-wide `SSH_AUTH_SOCK` environment variable.
- `dsc-desktop-settings` is followed by `refresh-explorer`, which kills and
  restarts `explorer.exe` so HKCU tweaks take effect immediately.

## Tests

[install.tests.ps1](install.tests.ps1) covers `Invoke-Step`'s selection
logic (`-Only`, `-Skip`, `-AdminOnly`, `-UserOnly`, `-Plan`, and admin
gating). Run with Pester:

```powershell
Invoke-Pester .\install.tests.ps1
```

## Troubleshooting

When WSL hangs and `wsl --shutdown` does nothing and the Windows service
won't restart, kill the service directly:

```powershell
taskkill /f /im wslservice.exe
```
