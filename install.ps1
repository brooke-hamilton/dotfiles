<#
.SYNOPSIS
    Bootstraps a Windows 11 dev environment for the Radius project.

.DESCRIPTION
    A small step runner around three concerns:

      1. A handful of imperative bootstrapping calls (winget feature enable,
         install Microsoft.DSC, install packages that require custom
         installer switches winget DSC v3 cannot express - Visual Studio
         Build Tools, Docker Desktop).
      2. Declarative state applied via DSC v3 yaml documents under
         .configurations\ (apps, apps-to-remove, desktop-settings).
      3. Per-user setup that depends on the above (rustup targets, cargo
         install, npm -g install, dotfile symlinks).

    The script is normally driven by Invoke-Unattended.ps1 which splits
    execution into an admin pass (-AdminOnly) and a user pass (-UserOnly).
    Running install.ps1 directly also works.

    See README.md for prerequisites.

.PARAMETER Skip
    Names of steps to skip. Accepts an array or a single comma-separated
    string.

.PARAMETER Only
    Names of steps to run. Overrides -Skip when set. Accepts an array or a
    single comma-separated string.

.PARAMETER AdminOnly
    Run only the steps tagged -RequiresAdmin. Used by Invoke-Unattended.ps1.

.PARAMETER UserOnly
    Run only the steps NOT tagged -RequiresAdmin. Used by
    Invoke-Unattended.ps1.

.PARAMETER Plan
    Dry-run. Print the step plan and, for steps that point at a DSC document,
    run `dsc config test`. Does not modify system state.
#>
[CmdletBinding()]
param(
    [string[]]$Skip = @(),
    [string[]]$Only = @(),
    [switch]$AdminOnly,
    [switch]$UserOnly,
    [switch]$Plan
)

$ErrorActionPreference = 'Continue'

# Allow comma-separated values when passed as a single string.
$Skip = @($Skip | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
$Only = @($Only | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })

if ($AdminOnly -and $UserOnly) {
    throw '-AdminOnly and -UserOnly are mutually exclusive.'
}

# Make selection state visible to Invoke-Step.
$script:Skip      = $Skip
$script:Only      = $Only
$script:AdminOnly = [bool]$AdminOnly
$script:UserOnly  = [bool]$UserOnly
$script:Plan      = [bool]$Plan
$script:IsAdmin   = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

$logDir = Join-Path $PSScriptRoot 'logs'
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir | Out-Null }
$logFile = Join-Path $logDir ("install-{0:yyyyMMdd-HHmmss}.log" -f (Get-Date))
Start-Transcript -Path $logFile -Append | Out-Null
Write-Output "Transcript: $logFile"
if ($Plan) { Write-Output 'PLAN mode: no system changes will be made.' }

$script:results = [System.Collections.Generic.List[object]]::new()

function Update-PathEnvVar {
    $machine = [System.Environment]::GetEnvironmentVariable('Path', 'Machine')
    $user    = [System.Environment]::GetEnvironmentVariable('Path', 'User')
    $env:Path = ($machine, $user | Where-Object { $_ }) -join ';'
}

function Invoke-Step {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][scriptblock]$Action,
        [switch]$RequiresAdmin,
        # Optional: path to a DSC v3 document this step applies. Used by -Plan
        # mode (runs `dsc config test` instead of the Action).
        [string]$DscFile
    )

    $addResult = {
        param($status, [int]$seconds = 0, $err = $null)
        $script:results.Add([pscustomobject]@{
            Step          = $Name
            Status        = $status
            Seconds       = $seconds
            RequiresAdmin = [bool]$RequiresAdmin
            Error         = $err
        })
    }

    # ---- selection / gating ----
    if ($script:Only -and ($script:Only -notcontains $Name)) {
        Write-Output "[SKIP-not-in-Only] $Name"; & $addResult 'Skipped'; return
    }
    if ($script:Skip -contains $Name) {
        Write-Output "[SKIP] $Name"; & $addResult 'Skipped'; return
    }
    if ($script:AdminOnly -and -not $RequiresAdmin) {
        Write-Output "[SKIP-user-step] $Name"; & $addResult 'Skipped'; return
    }
    if ($script:UserOnly -and $RequiresAdmin) {
        Write-Output "[SKIP-admin-step] $Name"; & $addResult 'Skipped'; return
    }

    # ---- plan mode (runs even when not elevated so dry-run is complete) ----
    if ($script:Plan) {
        $tag = if ($RequiresAdmin) { '[admin]' } else { '[user]' }
        Write-Output "[PLAN] $Name $tag"
        if ($DscFile) {
            if (Test-Path -LiteralPath $DscFile) {
                Write-Output "       dsc config test --file $DscFile"
                if (Get-Command dsc -ErrorAction SilentlyContinue) {
                    & dsc config test --file $DscFile *>&1 | ForEach-Object { Write-Output "       $_" }
                }
                else {
                    Write-Output '       (dsc CLI not installed; cannot run test)'
                }
            }
            else {
                Write-Warning "[PLAN] DSC file missing: $DscFile"
            }
        }
        & $addResult 'Planned'
        return
    }

    # ---- execute ----
    if ($RequiresAdmin -and -not $script:IsAdmin) {
        Write-Warning "[SKIP-needs-admin] $Name (re-run elevated to apply)"
        & $addResult 'Skipped'; return
    }

    Write-Output ''
    Write-Output '=========================================='
    Write-Output ">> $Name$(if ($RequiresAdmin) {' [admin]'} else {' [user]'})"
    Write-Output '=========================================='
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        & $Action
        $sw.Stop()
        Write-Output "[OK] $Name ($([int]$sw.Elapsed.TotalSeconds)s)"
        & $addResult 'OK' ([int]$sw.Elapsed.TotalSeconds)
    }
    catch {
        $sw.Stop()
        Write-Warning "[FAIL] $Name : $($_.Exception.Message)"
        & $addResult 'Failed' ([int]$sw.Elapsed.TotalSeconds) $_.Exception.Message
    }
}

# ==================================================================
# Admin pass: package management bootstrap + declarative system state
# ==================================================================

Invoke-Step 'winget-configure-enable' -RequiresAdmin {
    # --enable must be passed alone; winget rejects it combined with other args.
    winget configure --enable
    Update-PathEnvVar
}

Invoke-Step 'winget-upgrade-all' -RequiresAdmin {
    # winget upgrade can return non-zero when some packages fail / require interaction.
    # Treat that as a warning, not a step failure.
    winget upgrade --all --force --nowarn --disable-interactivity --accept-package-agreements --accept-source-agreements
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "winget upgrade --all returned $LASTEXITCODE (continuing)"
    }
}

Invoke-Step 'install-dsc' -RequiresAdmin {
    # Chicken-and-egg: DSC must exist before the dsc-* steps can apply.
    winget install --id Microsoft.DSC --disable-interactivity --source winget --accept-package-agreements --accept-source-agreements
    if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne -1978335189) {
        # -1978335189 = APPINSTALLER_CLI_ERROR_UPDATE_NOT_APPLICABLE (already installed/up to date)
        Write-Warning "winget install Microsoft.DSC returned $LASTEXITCODE (continuing)"
    }
    Update-PathEnvVar
}

# Removes unwanted Microsoft Store apps.
Invoke-Step 'dsc-apps-to-remove' -RequiresAdmin -DscFile "$PSScriptRoot\.configurations\apps-to-remove.dsc.yaml" {
    dsc config set --file "$PSScriptRoot\.configurations\apps-to-remove.dsc.yaml"
}

# Installs the bulk of the toolchain (VS Code, Node, Rustup, Zig, Office, etc.)
# and enables Developer Mode (HKLM) so the user pass can create symlinks.
Invoke-Step 'dsc-apps' -RequiresAdmin -DscFile "$PSScriptRoot\.configurations\apps.dsc.yaml" {
    dsc config set --file "$PSScriptRoot\.configurations\apps.dsc.yaml"
    Update-PathEnvVar
}

# Visual Studio Build Tools - imperative because the new DSC v3 WinGet/Package
# resource has no field for `--override` installer switches yet.
Invoke-Step 'vs-build-tools' -RequiresAdmin {
    winget install --id Microsoft.VisualStudio.2022.BuildTools --disable-interactivity --source winget --accept-package-agreements --accept-source-agreements `
        --override "--wait --passive --add Microsoft.VisualStudio.Workload.VCTools --add Microsoft.VisualStudio.Component.VC.Tools.x86.x64 --add Microsoft.VisualStudio.Component.Windows11SDK.26100 --add Microsoft.VisualStudio.Component.VC.CMake.Project --add Microsoft.VisualStudio.Component.VC.Runtimes.x86.x64.Spectre"
    if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne -1978335189) {
        Write-Warning "winget install BuildTools returned $LASTEXITCODE (continuing)"
    }
    Update-PathEnvVar
}

# Docker Desktop - imperative for the same reason as vs-build-tools. Pre-installed
# silently here so the radius-dev-env step doesn't trigger its interactive setup.
Invoke-Step 'docker-desktop' -RequiresAdmin {
    winget install --id Docker.DockerDesktop --source winget --disable-interactivity `
        --accept-package-agreements --accept-source-agreements `
        --override "install --quiet --accept-license --backend=wsl-2"
    if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne -1978335189) {
        Write-Warning "winget install Docker.DockerDesktop returned $LASTEXITCODE (continuing)"
    }
}

Invoke-Step 'radius-dev-env' -RequiresAdmin {
    $radiusDevConfigPath = Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'radius-dev-config'
    $radiusYaml = Join-Path -Path $radiusDevConfigPath -ChildPath '.configurations\radius.dsc.yaml'
    if (-not (Test-Path -Path $radiusDevConfigPath)) {
        # NOTE: side effect on the parent of $PSScriptRoot. Documented in README.
        git clone https://github.com/brooke-hamilton/radius-dev-config $radiusDevConfigPath
    }
    if (-not (Test-Path $radiusYaml)) {
        throw "radius config not found at $radiusYaml"
    }
    # The radius config is a winget configuration document (not DSC v3 schema),
    # so use `winget configure --file`, not `dsc config set`. Stream + capture
    # output so we can detect winget's silent "Extended features are not enabled"
    # bail-out which exits 0 but applies nothing.
    $output = & winget configure --file $radiusYaml --accept-configuration-agreements --disable-interactivity 2>&1 |
        ForEach-Object { Write-Host $_; $_ }
    if ($output -match 'Extended features are not enabled') {
        throw "winget configure refused to run: extended features not enabled. Run 'winget configure --enable' (or the winget-configure-enable step) and retry."
    }
}

Invoke-Step 'remove-desktop-shortcuts' -RequiresAdmin {
    . "$PSScriptRoot\PowerShell\Remove-DesktopShortcuts.ps1"
}

# ==================================================================
# User pass: per-user config that builds on what the admin pass installed
# ==================================================================

# git-ssh used to require admin because of symlinks; Developer Mode is now
# enabled by dsc-apps so SeCreateSymbolicLinkPrivilege is no longer needed.
# The ssh-agent service tweak still needs admin -- that part is guarded below.
Invoke-Step 'git-ssh' {
    . "$PSScriptRoot\PowerShell\Initialize-GitSshConfiguration.ps1"
}

Invoke-Step 'wslconfig' {
    Copy-Item -Force -Path "$PSScriptRoot\wsl\.wslconfig" -Destination "$env:USERPROFILE\.wslconfig"
}

Invoke-Step 'cloud-init' {
    . "$PSScriptRoot\PowerShell\Copy-CloudInitFiles.ps1"
}

Invoke-Step 'dsc-desktop-settings' -DscFile "$PSScriptRoot\.configurations\desktop-settings.dsc.yaml" {
    dsc config set --file "$PSScriptRoot\.configurations\desktop-settings.dsc.yaml"
}

Invoke-Step 'refresh-explorer' {
    # Explorer owns shell/taskbar rendering; restart it so HKCU tweaks apply immediately.
    Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
    Start-Process explorer.exe
}

Invoke-Step 'cmake-path' {
    if (-not (Get-Command cmake -ErrorAction SilentlyContinue)) {
        $cmakeSearchPaths = @(
            "${env:ProgramFiles}\Microsoft Visual Studio\*\*\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin"
            "${env:ProgramFiles}\CMake\bin"
        )
        foreach ($pattern in $cmakeSearchPaths) {
            $found = Resolve-Path $pattern -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($found) {
                $userPath = [System.Environment]::GetEnvironmentVariable('Path', 'User')
                if (-not $userPath) { $userPath = '' }
                $entries = $userPath.Split(';', [StringSplitOptions]::RemoveEmptyEntries)
                if ($entries -notcontains $found.Path) {
                    $newPath = if ($userPath) { "$userPath;$($found.Path)" } else { $found.Path }
                    [System.Environment]::SetEnvironmentVariable('Path', $newPath, 'User')
                    Write-Output "Added CMake to PATH: $($found.Path)"
                }
                else {
                    Write-Output "CMake already on User PATH: $($found.Path)"
                }
                Update-PathEnvVar
                break
            }
        }
    }
}

Invoke-Step 'cargo-zigbuild' {
    if (-not (Get-Command cargo -ErrorAction SilentlyContinue)) {
        throw 'cargo not available; the dsc-apps step (rustup install) likely failed.'
    }
    if (-not (Get-Command cargo-zigbuild -ErrorAction SilentlyContinue)) {
        cargo install --locked cargo-zigbuild
    }
    else {
        Write-Output 'cargo-zigbuild already installed; skipping.'
    }
}

Invoke-Step 'rust-targets' {
    if (-not (Get-Command rustup -ErrorAction SilentlyContinue)) {
        throw 'rustup not available; the dsc-apps step (rustup install) likely failed.'
    }
    rustup target add x86_64-pc-windows-msvc
    rustup target add x86_64-unknown-linux-musl
    rustup target add wasm32-wasip2
    rustup target add wasm32-unknown-unknown
    rustup component add rustfmt clippy rust-analyzer rust-src
}

Invoke-Step 'devcontainer-cli' {
    Update-PathEnvVar
    if (-not (Get-Command npm -ErrorAction SilentlyContinue)) {
        throw 'npm not available; Node.js install (via dsc-apps) likely did not complete.'
    }
    # Idempotency: skip if @devcontainers/cli is already a global install.
    $listed = & npm ls -g --depth=0 --silent 2>$null
    if ($LASTEXITCODE -eq 0 -and ($listed -match '@devcontainers/cli')) {
        Write-Output '@devcontainers/cli already installed globally; skipping.'
        return
    }
    npm install -g @devcontainers/cli
}

Invoke-Step 'apt-cacher-ng' {
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
        Write-Warning 'docker not on PATH; skipping apt-cacher-ng container start.'
        return
    }
    # Docker Desktop was just installed in the admin pass; the engine may
    # still be starting. Probe up to ~2 minutes.
    $deadline = (Get-Date).AddMinutes(2)
    $ready = $false
    while ((Get-Date) -lt $deadline) {
        & docker info *> $null
        if ($LASTEXITCODE -eq 0) { $ready = $true; break }
        Start-Sleep -Seconds 5
    }
    if (-not $ready) {
        Write-Warning 'Docker engine not responding after 2 minutes; skipping apt-cacher-ng. Re-run "install.ps1 -Only apt-cacher-ng" after Docker Desktop has started.'
        return
    }
    $existing = docker ps -a --filter name=^apt-cacher-ng$ --format '{{.Names}}'
    if ($existing -eq 'apt-cacher-ng') {
        Write-Output 'apt-cacher-ng container already exists; skipping.'
        return
    }
    docker run --detach --name apt-cacher-ng --publish 3142:3142 --restart=unless-stopped sameersbn/apt-cacher-ng
}

# ==================================================================
# Summary
# ==================================================================
Write-Output ''
Write-Output '=========================================='
Write-Output 'Install summary'
Write-Output '=========================================='
$script:results | Format-Table -AutoSize
$failed = @($script:results | Where-Object { $_.Status -eq 'Failed' })
if ($failed) {
    Write-Warning "$($failed.Count) step(s) failed. See transcript: $logFile"
}
Stop-Transcript | Out-Null

exit $failed.Count
