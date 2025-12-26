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
$hostFolder = (Get-Item -Path $PSScriptRoot).Parent.Parent.FullName

$hostResourcesFolder = "$PSScriptRoot\resources"
$sandboxConfigRootFolder = "C:\dotfiles"
$sandboxWorkingDirectory = Join-Path -Path $sandboxConfigRootFolder -ChildPath '.configurations\sandbox-tests'
$skipConfigurationValue = if ($SkipConfiguration) { '-SkipConfiguration ' } else { '' }
$sandboxBootstrapScript = Join-Path -Path $sandboxWorkingDirectory -ChildPath "Set-ConfigurationOnSandbox.ps1 $skipConfigurationValue"

<#
.SYNOPSIS
Stops the Windows Sandbox process if it is already running.
#>
function Stop-Wsb {
    # Get list of running sandbox instances
    $runningInstances = wsb list | Select-String -Pattern "^[0-9a-f-]+" | ForEach-Object { $_.Matches.Value }
    if ($runningInstances) {
        # Stop each running instance
        foreach ($instanceId in $runningInstances) {
            Write-Host "Stopping sandbox instance: $instanceId"
            wsb stop --id $instanceId
            Start-Sleep -Seconds 2
        }
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
# Copy-VCLibs
$wsbFilePath = Write-WsbConfigFile
Write-Host "$wsbFilePath"
WindowsSandbox $wsbFilePath