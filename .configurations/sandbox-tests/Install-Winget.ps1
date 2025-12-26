<#
.SYNOPSIS
Install WinGet in Windows Sandbox (Windows PowerShell 5.1, Admin).

.DESCRIPTION
Downloads the latest stable GitHub release assets from microsoft/winget-cli and installs:
- DesktopAppInstaller_Dependencies.zip (guided by DesktopAppInstaller_Dependencies.json)
- Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle

Assumptions:
- Running in Windows PowerShell 5.1 as Administrator
- No Microsoft Store access
- winget is not already installed
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-ScriptRoot {
    # $PSScriptRoot should be present for scripts in PS 3+, but keep a fallback.
    if ($PSScriptRoot) { return $PSScriptRoot }
    if ($MyInvocation -and $MyInvocation.MyCommand -and $MyInvocation.MyCommand.Path) {
        return (Split-Path -Path $MyInvocation.MyCommand.Path -Parent)
    }
    throw 'Unable to determine script root. Run this as a script file (.ps1), not from pasted text.'
}

function Invoke-Download {
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$OutFile
    )

    if (Test-Path -LiteralPath $OutFile) {
        Write-Verbose "Using cached download: $OutFile"
        return
    }

    $outDir = Split-Path -Path $OutFile -Parent
    if ($outDir -and -not (Test-Path -LiteralPath $outDir)) {
        New-Item -Path $outDir -ItemType Directory | Out-Null
    }

    Invoke-WebRequest -Uri $Url -Headers @{ 'User-Agent' = 'winget-sandbox-installer' } -OutFile $OutFile -UseBasicParsing
}

function Get-LatestWingetCliRelease {
    $uri = 'https://api.github.com/repos/microsoft/winget-cli/releases/latest'
    Invoke-RestMethod -Uri $uri -Headers @{ 'User-Agent' = 'winget-sandbox-installer' } -Method Get
}

function Get-ReleaseAsset {
    param(
        [Parameter(Mandatory = $true)]$Release,
        [Parameter(Mandatory = $true)][string]$Name
    )

    $asset = @($Release.assets | Where-Object { $_.name -eq $Name } | Select-Object -First 1)
    if (-not $asset) {
        throw "Asset not found on release: $Name"
    }

    $asset
}

function Get-ArchFolderName {
    # PS 5.1-safe architecture detection.
    # Prefer PROCESSOR_ARCHITECTURE / PROCESSOR_ARCHITEW6432; fall back to Is64BitOperatingSystem.
    $arch = $env:PROCESSOR_ARCHITEW6432
    if (-not $arch) { $arch = $env:PROCESSOR_ARCHITECTURE }
    if (-not $arch) {
        if ([Environment]::Is64BitOperatingSystem) { return 'x64' }
        return 'x86'
    }

    switch ($arch.ToUpperInvariant()) {
        'ARM64' { return 'arm64' }
        'AMD64' { return 'x64' }
        default {
            if ([Environment]::Is64BitOperatingSystem) { return 'x64' }
            return 'x86'
        }
    }
}

function Resolve-DependencyAppxPath {
    param(
        [Parameter(Mandatory = $true)][string]$DepsRoot,
        [Parameter(Mandatory = $true)][string]$Arch,
        [Parameter(Mandatory = $true)][string]$FileName
    )

    # Expected layout: <depsRoot>\<arch>\<name>_<version>_<arch>.appx
    $candidate = Join-Path $DepsRoot (Join-Path $Arch $FileName)
    if (Test-Path -LiteralPath $candidate) { return $candidate }

    # Fallback: zip layout sometimes differs; search under depsRoot.
    $match = Get-ChildItem -Path $DepsRoot -Filter $FileName -File -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($match) { return $match.FullName }

    throw "Dependency appx not found: $FileName"
}

# --- Main ---

Import-Module Appx -ErrorAction Stop

$release = Get-LatestWingetCliRelease
Write-Verbose "Using winget-cli release: $($release.tag_name)"

$resourcesDir = Join-Path (Get-ScriptRoot) 'resources'
if (-not (Test-Path -LiteralPath $resourcesDir)) {
    New-Item -Path $resourcesDir -ItemType Directory | Out-Null
}

# Download dependency metadata + archive
$jsonAsset = Get-ReleaseAsset -Release $release -Name 'DesktopAppInstaller_Dependencies.json'
$zipAsset = Get-ReleaseAsset -Release $release -Name 'DesktopAppInstaller_Dependencies.zip'

$jsonFile = Join-Path $resourcesDir $jsonAsset.name
$zipFile = Join-Path $resourcesDir $zipAsset.name
$depsDir = Join-Path $resourcesDir 'deps'

Invoke-Download -Url $jsonAsset.browser_download_url -OutFile $jsonFile
Invoke-Download -Url $zipAsset.browser_download_url -OutFile $zipFile

if (-not (Test-Path -LiteralPath $depsDir)) {
    New-Item -Path $depsDir -ItemType Directory | Out-Null
}

Expand-Archive -Path $zipFile -DestinationPath $depsDir -Force

$deps = Get-Content -Path $jsonFile -Raw | ConvertFrom-Json
if (-not $deps -or -not $deps.Dependencies) {
    throw 'Dependencies json file is invalid.'
}

$arch = Get-ArchFolderName

foreach ($d in $deps.Dependencies) {
    $fileName = ('{0}_{1}_{2}.appx' -f $d.Name, $d.Version, $arch)
    $fullPath = Resolve-DependencyAppxPath -DepsRoot $depsDir -Arch $arch -FileName $fileName
    Write-Verbose "Installing dependency: $fullPath"
    Add-AppxPackage -Path $fullPath -ErrorAction Stop
}

# Download + install the main App Installer bundle
$bundleAsset = Get-ReleaseAsset -Release $release -Name 'Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle'
$bundleFile = Join-Path $resourcesDir $bundleAsset.name
Invoke-Download -Url $bundleAsset.browser_download_url -OutFile $bundleFile

Write-Verbose "Installing bundle: $bundleFile"
Add-AppxPackage -Path $bundleFile -ErrorAction Stop

# Make the alias more likely to resolve in the current session.
$windowsApps = Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps'
if ($env:Path -notlike "*${windowsApps}*") {
    $env:Path = "$env:Path;$windowsApps"
}

Write-Verbose 'Done. If `winget` is still not found, restart the shell.'
