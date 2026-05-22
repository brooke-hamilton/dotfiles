<#
.SYNOPSIS
    Runs install.ps1 unattended with at most one UAC prompt.

.DESCRIPTION
    Splits the installation into two passes:

      1. Elevated pass (Phase 1): temporarily sets HKLM
         ConsentPromptBehaviorAdmin = 0 so child installers (Visual Studio,
         Office, MSI bootstrappers) that explicitly re-launch with the "runas"
         verb are elevated silently instead of popping additional UAC dialogs.
         The original value is restored in a finally block even on Ctrl-C /
         exception. Then runs install.ps1 -AdminOnly.

      2. User-context pass (Phase 2): runs steps that do not require admin
         (HKCU registry tweaks, cargo install, rustup target add, git clone
         into your profile, etc.). Runs second because some of these depend
         on tools the admin pass just installed (cargo, rustup).

    Result: exactly one UAC prompt at the start of the elevated pass.

    Security note: while ConsentPromptBehaviorAdmin is 0, any process running
    under your admin token can elevate without prompting. This window lasts
    only as long as the admin pass runs and is always restored.

.EXAMPLE
    .\Invoke-Unattended.ps1

.EXAMPLE
    .\Invoke-Unattended.ps1 -Skip vs-build-tools,radius-dev-env
#>
[CmdletBinding()]
param(
    [string[]]$Skip = @(),
    [string[]]$Only = @(),
    # Skip the user-context pass.
    [switch]$AdminOnly,
    # Skip the elevated pass.
    [switch]$UserOnly
)

$ErrorActionPreference = 'Stop'

if ($AdminOnly -and $UserOnly) {
    throw '-AdminOnly and -UserOnly are mutually exclusive.'
}

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$install = Join-Path $here 'install.ps1'
if (-not (Test-Path $install)) { throw "install.ps1 not found at $install" }

# Forward -Skip/-Only as a single comma-joined string; install.ps1 splits them.
$forward = @()
if ($Skip) { $forward += '-Skip'; $forward += ($Skip -join ',') }
if ($Only) { $forward += '-Only'; $forward += ($Only -join ',') }

# Phase 1: admin pass runs first so its installs (rustup, node, etc.) are on PATH
# before the user pass tries to use them (cargo install, npm install -g, rustup target add).
if (-not $UserOnly) {
    Write-Host ''
    Write-Host '################################################################'
    Write-Host '# Phase 1: admin steps (one UAC prompt, then silent)'
    Write-Host '################################################################'

    # Generate a temp script that, when run elevated, lowers the UAC consent prompt,
    # runs install.ps1 -AdminOnly, and always restores the original value.
    # Escape single quotes in interpolated paths/args to keep the heredoc valid.
    $installEsc = $install.Replace("'", "''")
    $forwardLiteral = ($forward | ForEach-Object { "'$($_.Replace("'", "''"))'" }) -join ', '
    $elevated = @"
`$ErrorActionPreference = 'Continue'
`$key  = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'
`$name = 'ConsentPromptBehaviorAdmin'
`$prop = Get-ItemProperty -Path `$key -Name `$name -ErrorAction SilentlyContinue
`$orig = if (`$prop) { `$prop.`$name } else { `$null }
Write-Host "ConsentPromptBehaviorAdmin original value: `$orig"
try {
    Set-ItemProperty -Path `$key -Name `$name -Value 0 -Type DWord
    Write-Host 'Lowered UAC prompt for admins (value=0) for this install.'
    `$fwd = @($forwardLiteral)
    & pwsh -NoProfile -ExecutionPolicy Bypass -File '$installEsc' -AdminOnly @fwd
    exit `$LASTEXITCODE
} finally {
    if (`$null -ne `$orig) {
        Set-ItemProperty -Path `$key -Name `$name -Value `$orig -Type DWord
    } else {
        Remove-ItemProperty -Path `$key -Name `$name -ErrorAction SilentlyContinue
    }
    Write-Host "ConsentPromptBehaviorAdmin restored to: `$orig"
}
"@

    $tmp = [IO.Path]::Combine([IO.Path]::GetTempPath(), "unattended-$([guid]::NewGuid().ToString('N')).ps1")
    Set-Content -Path $tmp -Value $elevated -Encoding UTF8
    try {
        if (-not (Get-Command sudo -ErrorAction SilentlyContinue)) {
            throw "sudo not found on PATH. Enable Windows sudo (Settings > For developers) or run this script from an elevated terminal."
        }
        sudo pwsh -NoProfile -ExecutionPolicy Bypass -File $tmp
        $adminExit = $LASTEXITCODE
    }
    finally {
        Remove-Item -Path $tmp -ErrorAction SilentlyContinue
    }
    if ($adminExit -ne 0) {
        Write-Warning "Admin phase reported $adminExit failed step(s); continuing with user phase."
    }
}

if ($AdminOnly) { return }

Write-Host ''
Write-Host '################################################################'
Write-Host '# Phase 2: user-context steps (no elevation)'
Write-Host '################################################################'
& pwsh -NoProfile -ExecutionPolicy Bypass -File $install -UserOnly @forward
exit $LASTEXITCODE
