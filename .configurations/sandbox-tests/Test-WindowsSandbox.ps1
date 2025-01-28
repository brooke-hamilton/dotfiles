<#
.SYNOPSIS
Tests the winget configuration by generating a Windows Sandbox configuration file and launches Windows Sandbox with
that configuration. NOTE: configurations that require nested virtualization to be enabled, like Docker Desktop, will
throw errors when installing in the sandbox because Windows Sandbox does not support nested virtualization.
#>

param (
    [switch]$SkipConfiguration,
    [string]$YamlConfigFileName = 'desktop-settings.dsc.yaml'
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$progressPreference = 'silentlyContinue'

# Folder from the host machine that contains configuration files
$hostFolder = (Get-Item -Path $PSScriptRoot).Parent.FullName

#$hostResourcesFolder = 'c:\temp\wsb-resources'
$hostResourcesFolder = "$PSScriptRoot\resources"
$sandboxResourcesFolder = 'c:\wsb-resources'
$sandboxConfigRootFolder = "C:\.configurations"
$sandboxWorkingDirectory = Join-Path -Path $sandboxConfigRootFolder -ChildPath 'sandbox-tests'
$yamlConfigFilePath = Join-Path -Path $sandboxConfigRootFolder -ChildPath $YamlConfigFileName
$skipConfigurationValue = if ($SkipConfiguration) { '-SkipConfiguration ' } else { '' }
$sandboxBootstrapScript = Join-Path -Path $sandboxWorkingDirectory -ChildPath "Set-ConfigurationOnSandbox.ps1 $skipConfigurationValue-FileCachePath $sandboxResourcesFolder -YamlConfigFilePath $yamlConfigFilePath"

<#
.SYNOPSIS
Stops the Windows Sandbox process if it is already running.
#>
function Stop-Wsb {
    $sandbox = Get-Process 'vmmemWindowsSandbox' -ErrorAction SilentlyContinue
    if ($sandbox) {
        $sandbox | Stop-Process
        Start-Sleep -Seconds 2
    }
    Remove-Variable sandbox
}

<#
.SYNOPSIS
Copies the Microsoft.VCLibs.x64.14.00.Desktop.appx file from the Windows SDK to the sandbox resources folder.
#>
function Copy-VCLibs {
    $sdkPath = 'C:\Program Files (x86)\Microsoft SDKs\Windows Kits\10\ExtensionSDKs\Microsoft.VCLibs.Desktop\14.0\Appx\Retail\x64\Microsoft.VCLibs.x64.14.00.Desktop.appx'
    $destinationFolder = Join-Path -Path $PSScriptRoot -ChildPath 'resources'

    if (-not (Test-Path $destinationFolder)) {
        New-Item -Path $destinationFolder -ItemType Directory > $null
    }

    if (Test-Path $sdkPath) {
        Write-Host "Copying VCLibs file to sandbox resources folder..."
        Copy-Item -Path $sdkPath -Destination $destinationFolder -Force
    } else {
        throw "VCLibs file not found at expected path: $sdkPath"
    }

    $appInstallerName = "Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle"
    $appInstallerFilePath = Join-Path -Path $destinationFolder -ChildPath $appInstallerName

    $xamlFileName = "Microsoft.UI.Xaml.2.8.x64.appx"
    $xamlFilePath = Join-Path -Path $destinationFolder -ChildPath $xamlFileName

    if (-not (Test-Path $xamlFilePath)) {
        Write-Host "Downloading Xaml dependency package..."
        Invoke-WebRequest -Uri https://github.com/microsoft/microsoft-ui-xaml/releases/download/v2.8.6/$xamlFileName -OutFile $xamlFilePath
    }

    if (-not (Test-Path $appInstallerFilePath)) {
        Write-Host "Downloading WinGet package..."
        Invoke-WebRequest -Uri https://aka.ms/getwinget -OutFile $appInstallerFilePath
    }
}


<#
.SYNOPSIS
Writes out a Windows Sandbox configuration file that maps the current folder into the sandbox and instructs the
sandbox to execute the bootstrap script.
#>
function Write-WsbConfigFile {
    $wsbFileText = @"
<Configuration>
<MappedFolders>
    <MappedFolder>
      <HostFolder>$hostFolder</HostFolder>
      <SandboxFolder>$sandboxConfigRootFolder</SandboxFolder>
      <ReadOnly>false</ReadOnly>
    </MappedFolder>
    <MappedFolder>
      <HostFolder>$hostResourcesFolder</HostFolder>
      <SandboxFolder>$sandboxResourcesFolder</SandboxFolder>
      <ReadOnly>false</ReadOnly>
    </MappedFolder>
</MappedFolders>
<MemoryInMB>16384</MemoryInMB>
<LogonCommand>
    <Command>PowerShell Start-Process PowerShell -WindowStyle Normal -WorkingDirectory '$sandboxWorkingDirectory' -ArgumentList '-ExecutionPolicy Unrestricted -NoExit -NoLogo -File $sandboxBootstrapScript'</Command>
</LogonCommand>
</Configuration>
"@

    if (-not (Test-Path $hostResourcesFolder)) {
        New-Item -Path $hostResourcesFolder -ItemType Directory > $null
    }

    $wsbFilePath = Join-Path -Path $hostResourcesFolder -ChildPath 'SandboxConfig.wsb'
    $wsbFileText | Out-File -FilePath $wsbFilePath -Encoding utf8
    return $wsbFilePath
}

Stop-Wsb
Copy-VCLibs
$wsbFilePath = Write-WsbConfigFile
Write-Host "$wsbFilePath"
WindowsSandbox $wsbFilePath