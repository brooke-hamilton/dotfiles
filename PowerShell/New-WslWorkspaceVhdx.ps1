<#
.SYNOPSIS
Creates and configures a shared VHDX workspace drive for WSL distributions.

.DESCRIPTION
Automates the steps to create a VHDX file, format it as ext4, configure WSL to mount it on startup,
and set ownership for the default WSL user. This script must be run as Administrator.

See wsl/how-to-set-up-wsl-workspace-vhdx.md for the manual steps this script automates.

.PARAMETER VhdPath
The path to the VHDX file to create. Defaults to $Env:USERPROFILE\wsl\workspace.vhdx.

.PARAMETER SizeBytes
The size of the VHDX file in bytes. Defaults to 200GB. The VHDX is created as a dynamic disk.

.PARAMETER DistroName
The WSL distribution to use for formatting the disk and configuring wsl.conf.

.PARAMETER StartupScriptPath
The WSL (Linux) path to the startup script that mounts the workspace drive.
Defaults to /mnt/c/users/<USERNAME>/dotfiles/wsl/wsl_startup.sh.

.PARAMETER MountName
The name to use for the WSL mount. Defaults to "workspace".

.EXAMPLE
.\New-WslWorkspaceVhdx.ps1

.EXAMPLE
.\New-WslWorkspaceVhdx.ps1 -DistroName "Ubuntu-24.04" -SizeBytes 500GB
#>
param (
    [string]$VhdPath = $(Join-Path -Path $Env:USERPROFILE -ChildPath "wsl\workspace.vhdx"),

    [long]$SizeBytes = 200GB,

    [string]$DistroName = "Ubuntu",

    [string]$StartupScriptPath,

    [string]$MountName = "workspace"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Check for Administrator privileges
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "This script must be run as Administrator. Please re-run from an elevated PowerShell prompt."
    return
}

# Set default startup script path if not provided
if (-not $StartupScriptPath) {
    $username = $Env:USERNAME.ToLower()
    $StartupScriptPath = "/mnt/c/users/$username/dotfiles/wsl/wsl_startup.sh"
}

# Validate that the distro exists and can be started
wsl.exe -d $DistroName -- true | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Error "WSL distro '$DistroName' was not found or could not be started."
    return
}

# Validate that the startup script exists in the distro
$startupScriptExists = wsl.exe -d $DistroName -- bash -c "test -f '$StartupScriptPath' && echo yes || echo no"
if ($startupScriptExists.Trim() -ne "yes") {
    Write-Error "Startup script not found at '$StartupScriptPath' in distro '$DistroName'."
    return
}

# --- Step 1: Create a new VHDX file ---
Write-Host "`n--- Step 1: Create a new VHDX file ---" -ForegroundColor Cyan

$vhdDir = Split-Path -Path $VhdPath -Parent
if (-not (Test-Path -Path $vhdDir)) {
    Write-Host "Creating directory $vhdDir..."
    New-Item -ItemType Directory -Path $vhdDir | Out-Null
}

$vhdCreated = $false
if (Test-Path -Path $VhdPath) {
    Write-Host "VHDX file already exists at $VhdPath. Leaving it in place." -ForegroundColor Yellow
} else {
    Write-Host "Creating VHDX file at $VhdPath ($([math]::Round($SizeBytes / 1GB))GB dynamic)..."
    New-VHD -Path $VhdPath -SizeBytes $SizeBytes -Dynamic
    $vhdCreated = $true
    Write-Host "VHDX file created." -ForegroundColor Green
}

# --- Step 2: Format the VHDX as ext4 ---
Write-Host "`n--- Step 2: Format the VHDX as ext4 ---" -ForegroundColor Cyan

if (-not $vhdCreated) {
    Write-Host "Skipping format because VHDX already existed (non-destructive mode)." -ForegroundColor Yellow
} else {

    # Capture currently visible disks before mounting so we can reliably detect the new one
    $beforeLsblkJson = wsl.exe -d $DistroName -- lsblk -J --output NAME,TYPE
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to detect existing disks in WSL distro '$DistroName'."
        return
    }

    $beforeDisks = @{}
    try {
        $beforeParsed = $beforeLsblkJson | ConvertFrom-Json
        foreach ($device in $beforeParsed.blockdevices) {
            if ($device.type -eq "disk") {
                $beforeDisks[$device.name] = $true
            }
        }
    } catch {
        Write-Error "Failed to parse lsblk output before mount."
        return
    }

    Write-Host "Mounting VHDX bare into WSL..."
    wsl.exe --mount --vhd $VhdPath --bare
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to mount VHDX file."
        return
    }

    # Find the newly mounted disk by looking for an unformatted disk matching the expected size
    Write-Host "Detecting the mounted disk in WSL..."
    $lsblkOutput = wsl.exe -d $DistroName -- lsblk -J -b --output NAME,SIZE,TYPE
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to run lsblk in WSL distro '$DistroName'."
        wsl.exe --unmount $VhdPath
        return
    }

    # Parse lsblk output to find the newly mounted disk matching expected size
    $diskName = $null
    try {
        $parsed = $lsblkOutput | ConvertFrom-Json
        foreach ($device in $parsed.blockdevices) {
            if ($device.type -eq "disk" -and -not $beforeDisks.ContainsKey($device.name)) {
                if ([int64]$device.size -eq [int64]$SizeBytes) {
                    $diskName = $device.name
                    break
                }
            }
        }
    } catch {
        Write-Error "Failed to parse lsblk output after mount."
        wsl.exe --unmount $VhdPath
        return
    }

    if (-not $diskName) {
        Write-Error "Could not find the newly mounted disk matching size $SizeBytes bytes."
        wsl.exe --unmount $VhdPath
        return
    }

    Write-Host "Found disk: /dev/$diskName"
    Write-Host "Formatting /dev/$diskName as ext4..."
    wsl.exe -d $DistroName -u root -- mkfs.ext4 -F /dev/$diskName
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to format disk /dev/$diskName as ext4."
        wsl.exe --unmount $VhdPath
        return
    }
    Write-Host "Disk formatted as ext4." -ForegroundColor Green

    Write-Host "Unmounting VHDX..."
    wsl.exe --unmount $VhdPath
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to unmount VHDX file."
        return
    }
    Write-Host "VHDX unmounted." -ForegroundColor Green
}

# --- Step 3: Configure WSL to automatically mount the disk on startup ---
Write-Host "`n--- Step 3: Configure wsl.conf to run the startup script ---" -ForegroundColor Cyan

Write-Host "Configuring /etc/wsl.conf [boot] command..."
$escapedStartupScriptPath = $StartupScriptPath.Replace("'", "'""'""'")
$configureWslConfScript = @"
set -e
touch /etc/wsl.conf

if grep -q '^\[boot\]$' /etc/wsl.conf; then
    if awk '
        /^\[boot\]$/ { in_boot=1; next }
        /^\[/ { in_boot=0 }
        in_boot && /^command=/ { found=1 }
        END { exit(found ? 0 : 1) }
    ' /etc/wsl.conf; then
        echo "[boot] command already exists in /etc/wsl.conf; leaving existing config in place."
    else
        sed -i '/^\[boot\]$/a command="$escapedStartupScriptPath"' /etc/wsl.conf
    fi
else
    printf '\n[boot]\ncommand="$escapedStartupScriptPath"\n' >> /etc/wsl.conf
fi
"@

$configureWslConfScript = $configureWslConfScript -replace "`r", ""
wsl.exe -d $DistroName -u root -- bash -c $configureWslConfScript
if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to update wsl.conf."
        return
}
Write-Host "wsl.conf updated." -ForegroundColor Green

Write-Host "Shutting down WSL..."
wsl.exe --shutdown
Write-Host "WSL shut down. The startup script will run the next time a distribution starts." -ForegroundColor Green

# --- Step 4: Change ownership of the workspace mount ---
Write-Host "`n--- Step 4: Change ownership of the workspace mount ---" -ForegroundColor Cyan

Write-Host "Starting WSL distro '$DistroName' to trigger the startup mount..."
# Run a no-op command to start the distro and trigger the boot command
wsl.exe -d $DistroName -- echo "Distro started" | Out-Null

# Wait briefly for the mount to complete
Start-Sleep -Seconds 3

# Check if the mount point exists
$mountExists = wsl.exe -d $DistroName -- bash -c "test -d /mnt/wsl/$MountName && echo yes || echo no"
if ($mountExists.Trim() -ne "yes") {
    Write-Warning "Mount point /mnt/wsl/$MountName not found. The startup script may need additional time or configuration."
    Write-Host "You can manually change ownership later by running:" -ForegroundColor Yellow
    Write-Host "  sudo chown 1000:1000 /mnt/wsl/$MountName" -ForegroundColor Yellow
    return
}

Write-Host "Setting ownership of /mnt/wsl/$MountName to user 1000:1000..."
wsl.exe -d $DistroName -u root -- chown 1000:1000 /mnt/wsl/$MountName
if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to change ownership of /mnt/wsl/$MountName."
    return
}
Write-Host "Ownership set." -ForegroundColor Green

Write-Host "`n--- Setup complete ---" -ForegroundColor Cyan
Write-Host "The workspace VHDX has been created, formatted, and configured."
Write-Host "It is mounted at /mnt/wsl/$MountName (with a symlink at /$MountName)."
