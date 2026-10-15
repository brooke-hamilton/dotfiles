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
   - **Phase 1 (admin):** elevates once via `sudo`, runs every step tagged `-RequiresAdmin` in [install.ps1](install.ps1) — WSL with the `wslc` container CLI, winget feature enable, DSC install, the `apps`/`apps-to-remove` DSC documents (which also enables Windows Developer Mode so unprivileged symlinks work), Visual Studio Build Tools, and `Remove-DesktopShortcuts.ps1`.
   - **Phase 2 (user):** runs the remaining steps unelevated — git/SSH symlinks, `.wslconfig`, cloud-init copy, HKCU desktop tweaks, `rustup target add`, `cargo install cargo-zigbuild`, and `npm install -g @devcontainers/cli`.

   Admin runs first because user-pass steps depend on tools the admin pass installs (cargo, rustup, npm).

   Windows setup installs `wslc` instead of Docker Desktop and does not start an `apt-cacher-ng` container. It also no longer clones or applies the sibling `radius-dev-config` configuration, which installs Docker Desktop. Existing Docker Desktop installations are not removed; WSL configuration files are unchanged.

   The `Start-AptCacherNg` function is retained in [install.ps1](install.ps1), but the installer does not invoke it or register an `apt-cacher-ng` install step.

3. Reboot.
4. Open Windows Terminal and launch the Ubuntu WSL distro. Complete the
   Ubuntu [OOBE](https://en.wikipedia.org/wiki/Out-of-box_experience).
5. From the Ubuntu shell, run the WSL setup script at
   `/mnt/c/users/<username>/dotfiles/wsl/setup.sh`.

   Setup writes `/etc/sysctl.d/99-radius-local-functional.conf` to persist
   `fs.inotify.max_user_instances=1024`, applies it immediately, and displays
   the active value. Re-run setup to apply this to existing instances.

   Run [wsl/setup.sh](wsl/setup.sh) as your regular WSL user, without `sudo`; it elevates individual operations as needed. During setup it removes Windows-backed directories from its process PATH so inherited Windows tools cannot satisfy installation checks, while preserving explicit Windows integrations such as reading OneDrive settings. It installs and activates the latest Node.js LTS through Linux nvm, sets it as the default for new shells, and uses its npm to install pnpm and `@github/copilot`. It verifies that Node, npm, pnpm, and Copilot resolve inside the active Linux nvm installation. Bash startup explicitly puts the active nvm bin directory first, even when nvm preserves an older PATH ordering. After setup, open a new shell or run `source ~/.bashrc` to apply this to your terminal; a child setup process cannot change its parent shell's PATH. The setup-only PATH filtering does not change WSL's global Windows interoperability settings.

### Optional Docker Engine inside WSL

[wsl/install-docker.sh](wsl/install-docker.sh) is a standalone Ubuntu WSL 2 development installer based on the `bh-radius-wsl-setup` skill. Neither the Windows installer nor [wsl/setup.sh](wsl/setup.sh) invokes it. With systemd enabled, run it as your regular WSL user from a clone on the distro's Linux filesystem:

```bash
bash ~/dotfiles/wsl/install-docker.sh
```

It skips an existing Docker Engine installation, configures [Docker's official APT repository](https://docs.docker.com/engine/install/ubuntu/#install-using-the-repository) when Docker is absent, and installs Docker Engine, its CLI, containerd, Buildx, and Compose. This avoids the convenience installer's Docker Desktop warning and delay. It enables the service, adds your user to the `docker` group, and verifies the local daemon in a fresh group session. The `docker` group grants root-equivalent access; the script does not make the Docker socket world-writable. Log in again or run `newgrp docker` to refresh your current shell's groups. It does not modify WSL configuration, install Docker Desktop, or start an APT cache. Existing Docker CLI installations without a local service require manual repair or disabling Docker Desktop integration before retrying.

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

- The `wslc` step in [install.ps1](install.ps1) installs WSL without creating a distro (`wsl --install --no-distribution`), updates it from Microsoft's GitHub releases (`wsl --update --web-download`), and verifies `wslc version`. [Microsoft's WSL container instructions](https://learn.microsoft.com/windows/wsl/tutorials/wsl-containers) require WSL 2.9.3 or newer; `wslc.exe` is bundled with WSL, not a separate package. If installation or verification requires a reboot, reboot and re-run `.\install.ps1 -Only wslc` from an elevated terminal. This leaves existing WSL distros intact. The PowerShell profile already aliases `docker` to `wslc`; Docker inside WSL remains independent.
- [.configurations/apps.dsc.yaml](.configurations/apps.dsc.yaml) — most
  packages (VS Code, Node, Rustup, Zig, Office, Teams, PowerToys,
  SysInternals, …) plus the Developer Mode registry value.
- [.configurations/apps-to-remove.dsc.yaml](.configurations/apps-to-remove.dsc.yaml)
  — Store apps to uninstall.
- [.configurations/desktop-settings.dsc.yaml](.configurations/desktop-settings.dsc.yaml)
  — HKCU explorer / taskbar / theme tweaks.
- Visual Studio Build Tools are installed imperatively from [install.ps1](install.ps1) because they need installer switches the current DSC v3 `Microsoft.WinGet/Package` resource doesn't yet expose.

## Side effects worth knowing about

- [PowerShell/Initialize-GitSshConfiguration.ps1](PowerShell/Initialize-GitSshConfiguration.ps1)
  creates symlinks `~\.gitconfig` and `~\.gitconfig-windows` pointing at
  files under `%ONEDRIVE%`, sets the `ssh-agent` service to Automatic,
  and sets the machine-wide `SSH_AUTH_SOCK` environment variable.
- `dsc-desktop-settings` is followed by `refresh-explorer`, which kills and
  restarts `explorer.exe` so HKCU tweaks take effect immediately.

## Tests

[wsl/setup.tests.sh](wsl/setup.tests.sh) verifies Linux Node tooling selection and Windows PATH isolation with mocked installers, without installing software. Run it inside WSL with `bash ~/dotfiles/wsl/setup.tests.sh`.

[install.tests.ps1](install.tests.ps1) covers `Invoke-Step`'s selection logic (`-Only`, `-Skip`, `-AdminOnly`, `-UserOnly`, `-Plan`, and admin gating) and mocked `wslc` installation, update, reboot, and verification outcomes without installing software. Run with Pester:

```powershell
Invoke-Pester .\install.tests.ps1
```

## Troubleshooting

When WSL hangs and `wsl --shutdown` does nothing and the Windows service
won't restart, kill the service directly:

```powershell
taskkill /f /im wslservice.exe
```
