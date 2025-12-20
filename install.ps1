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

Write-Banner "Configuring winget and installing DSC..."

winget configure --enable
winget upgrade --all --force --nowarn --disable-interactivity --accept-package-agreements --accept-source-agreements
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

Write-Banner "Starting Radius installation..."

# Radius setup
. "$PSScriptRoot\.configurations\Set-WinGetConfiguration.ps1" -YamlConfigFilePath "$PSScriptRoot\..\radius-dev-config\.configurations\radius.dsc.yaml"

Write-Banner "Configuring user profile files..."
Copy-Item -Force -Path "$PSScriptRoot\wsl\.wslconfig" -Destination "$env:USERPROFILE\.wslconfig"

# Copy cloud-init files to user profile
. "$PSScriptRoot\PowerShell\Copy-CloudInitFiles.ps1"

# Symbolic link to git config
if (Test-Path -Path "$env:ONEDRIVE\.gitconfig") {
    Write-Output "Creating symbolic link to git config file in OneDrive..."
    Remove-Item -Path "$env:USERPROFILE\.gitconfig" -ErrorAction Ignore
    New-Item -Path "$env:USERPROFILE\.gitconfig" -ItemType SymbolicLink -Target "$env:ONEDRIVE\.gitconfig"
} else {
    Write-Warning "OneDrive git config file not found. Skipping symbolic link creation."
}

# Set up OpenSSH Agent to start automatically
Set-Service ssh-agent -StartupType Automatic
Start-Service ssh-agent

. "$PSScriptRoot\PowerShell\Remove-DesktopShortcuts.ps1"

# Create symlink to gh config file in WSL instance
# Remove the existing gh config file if it exists.
# Invoke-Wsl $wslInstanceName "[ -d .config/gh ] && rm -r .config/gh" | Write-Verbose
# Create a symlink to the Windows gh config file.
# Invoke-Wsl $wslInstanceName "mkdir -p .config && ln -s /mnt/c/Users/$Env:USERNAME/.config/gh .config/gh" | Write-Verbose
# Set wsl instances with integrated docker in this file: C:\Users\<username>\AppData\Roaming\Docker\settings-store.json
# Turn of bel sound in wsl: in ~/.inputrc add this text: set bell-style none
# Apt cache: docker run -d --name apt-cacher-ng -p 3142:3142 --restart unless-stopped sameersbn/apt-cacher-ng