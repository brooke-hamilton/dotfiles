#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Configures Git and SSH settings for development environment.

.DESCRIPTION
    This script performs the following configuration tasks:
    - Creates symbolic links from the user profile directory to git config files stored in OneDrive
    - Configures the OpenSSH Authentication Agent service to start automatically
    - Sets the SSH_AUTH_SOCK environment variable for SSH agent communication

.EXAMPLE
    .\Initialize-GitSshConfiguration.ps1
    Configures Git symlinks, SSH agent service, and SSH environment variables.

.NOTES
    Requires Administrator privileges to create symbolic links and modify system services.
#>

[CmdletBinding()]
param()

# Symbolic link to git config
if (Test-Path -Path "$env:ONEDRIVE\.gitconfig") {
    Write-Output "Creating symbolic link to git config file in OneDrive..."
    Remove-Item -Path "$env:USERPROFILE\.gitconfig" -ErrorAction Ignore
    New-Item -Path "$env:USERPROFILE\.gitconfig" -ItemType SymbolicLink -Target "$env:ONEDRIVE\.gitconfig"
    New-Item -Path "$env:USERPROFILE\.gitconfig-windows" -ItemType SymbolicLink -Target "$env:ONEDRIVE\.gitconfig-windows"
} else {
    Write-Warning "OneDrive git config file not found. Skipping symbolic link creation."
}

# Configure OpenSSH Authentication Agent to start automatically
Write-Output "Configuring OpenSSH Authentication Agent service..."
$sshAgentService = Get-Service -Name ssh-agent -ErrorAction SilentlyContinue
if ($sshAgentService) {
    Set-Service -Name ssh-agent -StartupType Automatic
    if ($sshAgentService.Status -ne 'Running') {
        Start-Service ssh-agent
    }
    Write-Output "OpenSSH Authentication Agent configured to start automatically."
} else {
    Write-Warning "OpenSSH Authentication Agent service not found."
}

# Set SSH_AUTH_SOCK environment variable
Write-Output "Setting SSH_AUTH_SOCK environment variable..."
[System.Environment]::SetEnvironmentVariable('SSH_AUTH_SOCK', '\\.\pipe\openssh-ssh-agent', [System.EnvironmentVariableTarget]::Machine)
$env:SSH_AUTH_SOCK = '\\.\pipe\openssh-ssh-agent'
Write-Output "SSH_AUTH_SOCK environment variable set."

