<#
.SYNOPSIS
    Helper that runs the admin pass of install.ps1, optionally lowering
    ConsentPromptBehaviorAdmin so child installers do not pop UAC dialogs.

.DESCRIPTION
    This script is intended to be invoked elevated (via `sudo` in inline mode
    or `Start-Process -Verb RunAs`) by Invoke-Unattended.ps1. Splitting the
    helper into its own file removes the temp-script / heredoc / quote-escaping
    pattern that the previous orchestrator used: arguments are now passed
    structurally as proper parameters.

    When -LowerUAC is supplied, the original HKLM
    ConsentPromptBehaviorAdmin value is captured, set to 0 for the duration
    of the install, and restored in a finally block. Without -LowerUAC the
    registry is not touched and child installers may raise additional UAC
    prompts.

.PARAMETER InstallScript
    Absolute path to install.ps1.

.PARAMETER LowerUAC
    When set, temporarily writes HKLM ConsentPromptBehaviorAdmin = 0. The
    value is always restored, but note that a hard kill (taskkill on this
    pwsh process, power loss, BSOD) leaves the machine at "elevate silently".
    Do not enable unless you understand and accept that risk.

.PARAMETER Skip
    Comma-joined list of step names forwarded to install.ps1.

.PARAMETER Only
    Comma-joined list of step names forwarded to install.ps1.

.PARAMETER Plan
    Forward -Plan to install.ps1 (dry run; no system changes).
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$InstallScript,
    [switch]$LowerUAC,
    [string]$Skip,
    [string]$Only,
    [switch]$Plan
)

$ErrorActionPreference = 'Continue'

if (-not (Test-Path -LiteralPath $InstallScript)) {
    throw "install script not found: $InstallScript"
}

$key  = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'
$name = 'ConsentPromptBehaviorAdmin'
$orig = $null
$loweredHere = $false

if ($LowerUAC) {
    $prop = Get-ItemProperty -Path $key -Name $name -ErrorAction SilentlyContinue
    if ($prop) { $orig = $prop.$name }
    Write-Host "[admin-phase] Lowering ConsentPromptBehaviorAdmin (was: $orig) for this install."
    Set-ItemProperty -Path $key -Name $name -Value 0 -Type DWord
    $loweredHere = $true
}

try {
    $fwd = @()
    if ($Skip) { $fwd += @('-Skip', $Skip) }
    if ($Only) { $fwd += @('-Only', $Only) }
    if ($Plan) { $fwd += '-Plan' }
    & pwsh -NoProfile -ExecutionPolicy Bypass -File $InstallScript -AdminOnly @fwd
    $exit = $LASTEXITCODE
}
finally {
    if ($loweredHere) {
        if ($null -ne $orig) {
            Set-ItemProperty -Path $key -Name $name -Value $orig -Type DWord
        }
        else {
            Remove-ItemProperty -Path $key -Name $name -ErrorAction SilentlyContinue
        }
        Write-Host "[admin-phase] Restored ConsentPromptBehaviorAdmin to: $orig"
    }
}

exit $exit
