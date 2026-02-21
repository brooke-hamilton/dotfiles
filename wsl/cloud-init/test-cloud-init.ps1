# This script sets up and tests a WSL distro with cloud-init
# It unregisters any existing test distro, creates a new one from a tar file,
# waits for cloud-init to complete, then terminates and enters the distro

$ErrorActionPreference = 'Stop'

$distroName = "test"

# Only unregister if the distro exists
$distros = wsl --list --quiet
if ($distros -contains $distroName) {
    wsl --unregister $distroName
}

# Copy the cloud init file to the correct location in the user profile.
..\..\PowerShell\Copy-CloudInitFiles.ps1

# Create a new WSL distro
..\..\PowerShell\New-WslDistroFromTarFile.ps1 -NewDistroName $distroName

# Wait for cloud-init to complete
wsl -d $distroName cloud-init status --wait

# Terminate the distro because config changes apply upon restart.
wsl --terminate $distroName

# Launch the distro to verify it starts correctly and to enter it.
wsl -d $distroName
