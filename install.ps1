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

# Dev container CLI (refresh the path first because npm was installed above)
$env:Path = [System.Environment]::GetEnvironmentVariable("Path", "User") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "Machine")
npm install -g @devcontainers/cli

# Copy .wslconfig to user profile
Copy-Item -Force -Path "$PSScriptRoot\wsl\.wslconfig" -Destination "$env:USERPROFILE\.wslconfig"

# Symbolic link to git config
Remove-Item -Path "$env:USERPROFILE\.gitconfig" -ErrorAction Ignore
New-Item -Path "$env:USERPROFILE\.gitconfig" -ItemType SymbolicLink -Target "$env:USERPROFILE\OneDrive - Microsoft\.gitconfig"

. "$PSScriptRoot\PowerShell\Remove-DesktopShortcuts.ps1"

# Run git\configure_git.sh
# Create symlink to gh config file in WSL instance
# Write-Verbose -Message "Creating symlink in WSL instance $wslInstanceName to the gh cli config file..."
# Remove the existing gh config file if it exists.
# Invoke-Wsl $wslInstanceName "[ -d .config/gh ] && rm -r .config/gh" | Write-Verbose
# Create a symlink to the Windows gh config file.
# Invoke-Wsl $wslInstanceName "mkdir -p .config && ln -s /mnt/c/Users/$Env:USERNAME/.config/gh .config/gh" | Write-Verbose
# Set wsl instances with integrated docker in this file: C:\Users\<username>\AppData\Roaming\Docker\settings-store.json
# Turn of bel sound in wsl: in ~/.inputrc add this text: set bell-style none
