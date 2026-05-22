<#
.SYNOPSIS
    Runs install.ps1 unattended in two passes (admin, then user) with at
    most one UAC prompt.

.DESCRIPTION
    The admin pass runs first because its installs (rustup, node, etc.) put
    binaries on PATH that the user pass needs (cargo install, npm install -g,
    rustup target add).

    Elevation uses Windows `sudo` (inline mode). Arguments are passed to the
    elevated helper structurally - no string interpolation, no temp scripts
    built with quote escaping.

    The legacy "lower HKLM ConsentPromptBehaviorAdmin to 0 for the duration
    of the install" behavior is now opt-in via -ConsentToLowerUAC. Without
    that switch, child installers that explicitly re-elevate (Visual Studio,
    Office bootstrappers) may produce additional UAC prompts. With the
    switch you get a single prompt and silent child elevation, but you must
    accept that a hard kill of the elevated pwsh leaves UAC at "elevate
    silently" until you restore it manually.

.PARAMETER Skip
    Comma-separated or array list of step names to skip in install.ps1.

.PARAMETER Only
    Run only the named steps. Overrides -Skip when set.

.PARAMETER AdminOnly
    Run only the elevated pass.

.PARAMETER UserOnly
    Run only the unelevated pass.

.PARAMETER Plan
    Dry-run: prints the step plan and runs `dsc config test` for DSC steps
    without changing system state.

.PARAMETER ConsentToLowerUAC
    Opt in to temporarily setting HKLM ConsentPromptBehaviorAdmin = 0 during
    the admin pass so child installers do not raise additional UAC dialogs.
    Off by default. See SECURITY NOTE in the file header above.

.EXAMPLE
    .\Invoke-Unattended.ps1

.EXAMPLE
    .\Invoke-Unattended.ps1 -ConsentToLowerUAC

.EXAMPLE
    .\Invoke-Unattended.ps1 -Plan
#>
[CmdletBinding()]
param(
    [string[]]$Skip = @(),
    [string[]]$Only = @(),
    [switch]$AdminOnly,
    [switch]$UserOnly,
    [switch]$Plan,
    [switch]$ConsentToLowerUAC
)

$ErrorActionPreference = 'Stop'

if ($AdminOnly -and $UserOnly) {
    throw '-AdminOnly and -UserOnly are mutually exclusive.'
}

$here    = Split-Path -Parent $MyInvocation.MyCommand.Path
$install = Join-Path $here 'install.ps1'
$helper  = Join-Path $here 'PowerShell\Invoke-AdminPhase.ps1'

foreach ($p in @($install, $helper)) {
    if (-not (Test-Path -LiteralPath $p)) { throw "required script not found: $p" }
}

# Flatten any "a,b" strings into a real array, then re-join into a single
# comma-joined value when forwarding (install.ps1 splits again).
$skipFlat = @($Skip | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
$onlyFlat = @($Only | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })

# ------------------------------------------------------------------
# Phase 1: admin pass
# ------------------------------------------------------------------
if (-not $UserOnly) {
    Write-Host ''
    Write-Host '################################################################'
    if ($Plan) {
        Write-Host '# Phase 1 (PLAN): admin steps'
    } else {
        Write-Host '# Phase 1: admin steps (one UAC prompt, then runs silently)'
    }
    Write-Host '################################################################'

    if (-not (Get-Command sudo -ErrorAction SilentlyContinue)) {
        throw "sudo not found on PATH. Enable Windows sudo (Settings > System > For developers > Enable sudo, mode = Inline) or run this script from an elevated terminal."
    }

    $sudoArgs = @(
        'pwsh', '-NoProfile', '-ExecutionPolicy', 'Bypass',
        '-File', $helper,
        '-InstallScript', $install
    )
    if ($ConsentToLowerUAC) { $sudoArgs += '-LowerUAC' }
    if ($skipFlat)          { $sudoArgs += @('-Skip', ($skipFlat -join ',')) }
    if ($onlyFlat)          { $sudoArgs += @('-Only', ($onlyFlat -join ',')) }
    if ($Plan)              { $sudoArgs += '-Plan' }

    & sudo @sudoArgs
    $adminExit = $LASTEXITCODE
    if ($adminExit -ne 0) {
        Write-Warning "Admin phase reported $adminExit failed step(s); continuing with user phase."
    }
}

if ($AdminOnly) { return }

# ------------------------------------------------------------------
# Phase 2: user pass
# ------------------------------------------------------------------
Write-Host ''
Write-Host '################################################################'
if ($Plan) {
    Write-Host '# Phase 2 (PLAN): user steps'
} else {
    Write-Host '# Phase 2: user-context steps (no elevation)'
}
Write-Host '################################################################'

$userArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $install, '-UserOnly')
if ($skipFlat) { $userArgs += @('-Skip', ($skipFlat -join ',')) }
if ($onlyFlat) { $userArgs += @('-Only', ($onlyFlat -join ',')) }
if ($Plan)     { $userArgs += '-Plan' }

& pwsh @userArgs
exit $LASTEXITCODE
