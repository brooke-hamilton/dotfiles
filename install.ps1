#Requires -RunAsAdministrator

# Make sure the submodule was cloned with this repo.
if((Get-ChildItem -Path "$PSScriptRoot\submodules\radius-dev-config" | Measure-Object).Count -eq 0) {
    Write-Output "Clone the submodule with this repo. Run: git submodule update --init --recursive"
    exit
}

# Enable winget configuration
winget configure --enable

# Personal preferences
. "$PSScriptRoot\.configurations\Set-WinGetConfiguration.ps1" -YamlConfigFilePath "$PSScriptRoot\.configurations\desktop-settings.dsc.yaml"
. "$PSScriptRoot\.configurations\Set-WinGetConfiguration.ps1" -YamlConfigFilePath "$PSScriptRoot\.configurations\apps-to-remove.dsc.yaml"
. "$PSScriptRoot\.configurations\Set-WinGetConfiguration.ps1" -YamlConfigFilePath "$PSScriptRoot\.configurations\apps.dsc.yaml"
. "$PSScriptRoot\.configurations\Set-WinGetConfiguration.ps1" -YamlConfigFilePath "$PSScriptRoot\.configurations\office-apps.dsc.yaml"

# Radius setup
. "$PSScriptRoot\.configurations\Set-WinGetConfiguration.ps1" -YamlConfigFilePath "$PSScriptRoot\submodules\radius-dev-config\.configurations\radius.dsc.yaml"

# Dev container CLI
npm install -g @devcontainers/cli

# Copy .wslconfig to user profile
Copy-Item -Force -Path "$PSScriptRoot\wsl\.wslconfig" -Destination "$env:USERPROFILE\.wslconfig"
