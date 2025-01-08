#Requires -RunAsAdministrator

# Personal preferences
. "$PSScriptRoot\.configurations\Set-WinGetConfiguration.ps1" -YamlConfigFilePath "$PSScriptRoot\.configurations\desktop-settings.dsc.yaml"
. "$PSScriptRoot\.configurations\Set-WinGetConfiguration.ps1" -YamlConfigFilePath "$PSScriptRoot\.configurations\apps-to-remove.dsc.yaml"
. "$PSScriptRoot\.configurations\Set-WinGetConfiguration.ps1" -YamlConfigFilePath "$PSScriptRoot\.configurations\apps.dsc.yaml"
. "$PSScriptRoot\.configurations\Set-WinGetConfiguration.ps1" -YamlConfigFilePath "$PSScriptRoot\.configurations\office-apps.dsc.yaml"

# Radius setup
. "$PSScriptRoot\.configurations\Set-WinGetConfiguration.ps1" -YamlConfigFilePath "$PSScriptRoot\submodules\radius-dev-config\.configurations\radius.dsc.yaml"

