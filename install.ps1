[CmdletBinding()]
param(
    # Comma-separated list of step names to skip (see Invoke-Step calls below for names).
    [string[]]$Skip = @(),
    # Run only these step names (overrides $Skip when set).
    [string[]]$Only = @(),
    # Only run steps that require admin (used by Invoke-Unattended.ps1's elevated pass).
    [switch]$AdminOnly,
    # Only run steps that do NOT require admin (used by Invoke-Unattended.ps1's user pass).
    [switch]$UserOnly
)

$ErrorActionPreference = 'Continue'

# Allow comma-separated values when passed as a single string from the command line.
$Skip = @($Skip | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
$Only = @($Only | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })

if ($AdminOnly -and $UserOnly) {
    throw '-AdminOnly and -UserOnly are mutually exclusive.'
}

$script:IsAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

# Start a transcript so the full output is captured even when winget spams progress bars.
$logDir = Join-Path $PSScriptRoot 'logs'
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir | Out-Null }
$logFile = Join-Path $logDir ("install-{0:yyyyMMdd-HHmmss}.log" -f (Get-Date))
Start-Transcript -Path $logFile -Append | Out-Null
Write-Output "Transcript: $logFile"

# Track step outcomes for an end-of-run summary.
$script:results = [System.Collections.Generic.List[object]]::new()

function Update-PathEnvVar {
    $machine = [System.Environment]::GetEnvironmentVariable('Path', 'Machine')
    $user = [System.Environment]::GetEnvironmentVariable('Path', 'User')
    $env:Path = ($machine, $user | Where-Object { $_ }) -join ';'
}

function Invoke-Step {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][scriptblock]$Action,
        # When set, the step modifies machine-wide state and needs elevation.
        [switch]$RequiresAdmin
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

    if ($Only -and ($Only -notcontains $Name)) {
        Write-Output "[SKIP-not-in-Only] $Name"; & $addResult 'Skipped'; return
    }
    if ($Skip -contains $Name) {
        Write-Output "[SKIP] $Name"; & $addResult 'Skipped'; return
    }
    if ($AdminOnly -and -not $RequiresAdmin) {
        Write-Output "[SKIP-user-step] $Name"; & $addResult 'Skipped'; return
    }
    if ($UserOnly -and $RequiresAdmin) {
        Write-Output "[SKIP-admin-step] $Name"; & $addResult 'Skipped'; return
    }
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

Invoke-Step 'git-ssh' -RequiresAdmin {
    . "$PSScriptRoot\PowerShell\Initialize-GitSshConfiguration.ps1"
}

Invoke-Step 'wslconfig' {
    Copy-Item -Force -Path "$PSScriptRoot\wsl\.wslconfig" -Destination "$env:USERPROFILE\.wslconfig"
}

Invoke-Step 'cloud-init' {
    . "$PSScriptRoot\PowerShell\Copy-CloudInitFiles.ps1"
}

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
    winget install --id Microsoft.DSC --disable-interactivity --source winget --accept-package-agreements --accept-source-agreements
    if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne -1978335189) {
        # -1978335189 = APPINSTALLER_CLI_ERROR_UPDATE_NOT_APPLICABLE (already installed/up to date)
        Write-Warning "winget install Microsoft.DSC returned $LASTEXITCODE (continuing)"
    }
    Update-PathEnvVar
}

Invoke-Step 'dsc-desktop-settings' {
    dsc config set --file "$PSScriptRoot\.configurations\desktop-settings.dsc.yaml"
}
Invoke-Step 'refresh-explorer' {
    # Explorer owns shell/taskbar rendering; restart it so HKCU tweaks apply immediately.
    Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
    Start-Process explorer.exe
}
Invoke-Step 'dsc-apps-to-remove' -RequiresAdmin {
    dsc config set --file "$PSScriptRoot\.configurations\apps-to-remove.dsc.yaml"
}
Invoke-Step 'dsc-apps' -RequiresAdmin {
    dsc config set --file "$PSScriptRoot\.configurations\apps.dsc.yaml"
}
Invoke-Step 'dsc-office-apps' -RequiresAdmin {
    dsc config set --file "$PSScriptRoot\.configurations\office-apps.dsc.yaml"
}

Invoke-Step 'rust-toolchain' -RequiresAdmin {
    Update-PathEnvVar
    if (-not (Get-Command rustup -ErrorAction SilentlyContinue)) {
        winget install --id Rustlang.Rustup --disable-interactivity --source winget --accept-package-agreements --accept-source-agreements
        Update-PathEnvVar
    }
}

Invoke-Step 'vs-build-tools' -RequiresAdmin {
    winget install --id Microsoft.VisualStudio.2022.BuildTools --disable-interactivity --source winget --accept-package-agreements --accept-source-agreements `
        --override "--wait --passive --add Microsoft.VisualStudio.Workload.VCTools --add Microsoft.VisualStudio.Component.VC.Tools.x86.x64 --add Microsoft.VisualStudio.Component.Windows11SDK.26100 --add Microsoft.VisualStudio.Component.VC.CMake.Project --add Microsoft.VisualStudio.Component.VC.Runtimes.x86.x64.Spectre"
    if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne -1978335189) {
        Write-Warning "winget install BuildTools returned $LASTEXITCODE (continuing)"
    }
    Update-PathEnvVar
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
                } else {
                    Write-Output "CMake already on User PATH: $($found.Path)"
                }
                Update-PathEnvVar
                break
            }
        }
    }
}

Invoke-Step 'zig' -RequiresAdmin {
    if (-not (Get-Command zig -ErrorAction SilentlyContinue)) {
        winget install --id zig.zig --disable-interactivity --source winget --accept-package-agreements --accept-source-agreements
        Update-PathEnvVar
    }
}

Invoke-Step 'cargo-zigbuild' {
    if (-not (Get-Command cargo -ErrorAction SilentlyContinue)) {
        throw "cargo not available; rust-toolchain step likely failed"
    }
    if (-not (Get-Command cargo-zigbuild -ErrorAction SilentlyContinue)) {
        cargo install --locked cargo-zigbuild
    }
}

Invoke-Step 'rust-targets' {
    if (-not (Get-Command rustup -ErrorAction SilentlyContinue)) {
        throw "rustup not available"
    }
    rustup target add x86_64-pc-windows-msvc
    rustup target add x86_64-unknown-linux-musl
    rustup target add wasm32-wasip2
    rustup target add wasm32-unknown-unknown
    rustup component add rustfmt clippy rust-analyzer rust-src
}

Invoke-Step 'devcontainer-cli' -RequiresAdmin {
    Update-PathEnvVar
    if (-not (Get-Command npm -ErrorAction SilentlyContinue)) {
        throw "npm not available; Node.js install (via dsc-apps) likely did not complete"
    }
    npm install -g @devcontainers/cli
}

Invoke-Step 'radius-dev-config-clone' {
    $radiusDevConfigPath = Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'radius-dev-config'
    if (-not (Test-Path -Path $radiusDevConfigPath)) {
        git clone https://github.com/brooke-hamilton/radius-dev-config $radiusDevConfigPath
    } else {
        Write-Output "Already cloned: $radiusDevConfigPath"
    }
}

Invoke-Step 'radius-dev-env' -RequiresAdmin {
    $radiusYaml = "$PSScriptRoot\..\radius-dev-config\.configurations\radius.dsc.yaml"
    if (-not (Test-Path $radiusYaml)) {
        throw "radius config not found at $radiusYaml"
    }
    # Capture output so we can detect winget's silent "Extended features are not enabled" bail-out,
    # which exits 0 but applies nothing. Stream to host as it arrives.
    $output = & "$PSScriptRoot\.configurations\Set-WinGetConfiguration.ps1" -YamlConfigFilePath $radiusYaml 2>&1 |
        ForEach-Object { Write-Host $_; $_ }
    if ($output -match 'Extended features are not enabled') {
        throw "winget configure refused to run: extended features not enabled. Run 'winget configure --enable' (or the winget-configure-enable step) and retry."
    }
}

Invoke-Step 'remove-desktop-shortcuts' -RequiresAdmin {
    . "$PSScriptRoot\PowerShell\Remove-DesktopShortcuts.ps1"
}

Invoke-Step 'apt-cacher-ng' {
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
        Write-Warning "docker not on PATH; skipping apt-cacher-ng container start"
        return
    }
    $existing = docker ps -a --filter name=^apt-cacher-ng$ --format '{{.Names}}'
    if ($existing -eq 'apt-cacher-ng') {
        Write-Output 'apt-cacher-ng container already exists; skipping.'
        return
    }
    docker run --detach --name apt-cacher-ng --publish 3142:3142 --restart=unless-stopped sameersbn/apt-cacher-ng
}

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

# Remove the existing gh config file if it exists.
# Invoke-Wsl $wslInstanceName "[ -d .config/gh ] && rm -r .config/gh" | Write-Verbose
# Create a symlink to the Windows gh config file.
# Invoke-Wsl $wslInstanceName "mkdir -p .config && ln -s /mnt/c/Users/$Env:USERNAME/.config/gh .config/gh" | Write-Verbose
# Set wsl instances with integrated docker in this file: C:\Users\<username>\AppData\Roaming\Docker\settings-store.json
# Turn of bel sound in wsl: in ~/.inputrc add this text: set bell-style none
# Apt cache: docker run -d --name apt-cacher-ng -p 3142:3142 --restart unless-stopped sameersbn/apt-cacher-ng