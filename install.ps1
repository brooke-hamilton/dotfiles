#Requires -RunAsAdministrator

# Update the PATH environment variable for the current session
function Update-PathEnvVar {
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
}

# Display a banner for a section of the script
function Write-Banner {
    param([string]$Message)
    Write-Output "=========================================="
    Write-Output $Message
    Write-Output "=========================================="
}

# Configure Git and SSH
Write-Banner "Configuring git ssh..."
. "$PSScriptRoot\PowerShell\Initialize-GitSshConfiguration.ps1"

Write-Banner "Configuring user profile files..."
Copy-Item -Force -Path "$PSScriptRoot\wsl\.wslconfig" -Destination "$env:USERPROFILE\.wslconfig"

Write-Banner "Copying WSL cloud-init files to user profile..."
. "$PSScriptRoot\PowerShell\Copy-CloudInitFiles.ps1"

Write-Banner "Configuring winget..."
winget configure --enable
Update-PathEnvVar

Write-Banner "Upgrading packages..."
winget upgrade --all --force --nowarn --disable-interactivity --accept-package-agreements --accept-source-agreements

Write-Banner "Installing DSC..."
winget install --id Microsoft.DSC --disable-interactivity --source winget
Update-PathEnvVar

Write-Banner "Applying personal preferences..."
dsc config set --file "$PSScriptRoot\.configurations\desktop-settings.dsc.yaml"
dsc config set --file "$PSScriptRoot\.configurations\apps-to-remove.dsc.yaml"
dsc config set --file "$PSScriptRoot\.configurations\apps.dsc.yaml"
dsc config set --file "$PSScriptRoot\.configurations\office-apps.dsc.yaml"

Write-Banner "Installing Dev Container CLI..."
Update-PathEnvVar
npm install -g @devcontainers/cli

Write-Banner "Cloning radius-dev-config repository..."
$radiusDevConfigPath = Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath "radius-dev-config"
if (-not (Test-Path -Path $radiusDevConfigPath)) {
    git clone https://github.com/brooke-hamilton/radius-dev-config $radiusDevConfigPath
}

Write-Banner "Starting Radius dev environment..."
. "$PSScriptRoot\.configurations\Set-WinGetConfiguration.ps1" -YamlConfigFilePath "$PSScriptRoot\..\radius-dev-config\.configurations\radius.dsc.yaml"

Write-Banner "Removing desktop shortcuts..."
. "$PSScriptRoot\PowerShell\Remove-DesktopShortcuts.ps1"

docker run --detach --name apt-cacher-ng --publish 3142:3142 --restart=unless-stopped sameersbn/apt-cacher-ng

# Remove the existing gh config file if it exists.
# Invoke-Wsl $wslInstanceName "[ -d .config/gh ] && rm -r .config/gh" | Write-Verbose
# Create a symlink to the Windows gh config file.
# Invoke-Wsl $wslInstanceName "mkdir -p .config && ln -s /mnt/c/Users/$Env:USERNAME/.config/gh .config/gh" | Write-Verbose
# Set wsl instances with integrated docker in this file: C:\Users\<username>\AppData\Roaming\Docker\settings-store.json
# Turn of bel sound in wsl: in ~/.inputrc add this text: set bell-style none
# Apt cache: docker run -d --name apt-cacher-ng -p 3142:3142 --restart unless-stopped sameersbn/apt-cacher-ng