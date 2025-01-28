<#
.SYNOPSIS
Installs WinGet and its dependencies.

.PARAMETER FileCachePath
Path to a local folder that contains downloaded cached files.

#>

param (
    [string]$FileCachePath = "$PSScriptRoot\resources"
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$progressPreference = 'silentlyContinue'

$appInstallerName = "Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle"
$appInstallerFilePath = Join-Path -Path $FileCachePath -ChildPath $appInstallerName

$vcLibsFileName = "Microsoft.VCLibs.x64.14.00.Desktop.appx"
$vcLibsFilePath = Join-Path -Path $FileCachePath -ChildPath $vcLibsFileName

$xamlFileName = "Microsoft.UI.Xaml.2.8.x64.appx"
$xamlFilePath = Join-Path -Path $FileCachePath -ChildPath $xamlFileName

Write-Host "Installing WinGet..."
Add-AppxPackage $vcLibsFilePath
Add-AppxPackage $xamlFilePath
Add-AppxPackage $appInstallerFilePath
Write-Host "Installed WinGet version $(winget --version)"
