Set-StrictMode -Version 3.0
$ErrorActionPreference = "Stop"

<#
.SYNOPSIS
Finds the devcontainer.json file in the specified workspace folder or at the specified path.

.DESCRIPTION
This function searches for the devcontainer.json file in the given workspace folder. If a specific path is provided,
it checks if the file exists at that path. If multiple devcontainer.json files are found, it throws an error unless
a specific path is provided.
#>
function Find-DevContainerJsonFile {
    param (
        [string]$workspaceFolder,
        [string]$devContainerJsonPath
    )

    if ($devContainerJsonPath) {
        if (-not (Test-Path -Path $devContainerJsonPath -PathType Leaf)) {
            throw "No devcontainer.json file found."
        }
        return $devContainerJsonPath
    }

    [System.IO.FileInfo[]]$devContainerJson = Get-ChildItem -Path $workspaceFolder -Filter "devcontainer.json" -Recurse -File -Force
    if (-not $devContainerJson) { throw "No devcontainer.json files found." }
    switch ($devContainerJson.Count) {
        0 { throw "No devcontainer.json files found." }
        1 { return $devContainerJson[0].FullName }
        default { throw "Multiple devcontainer.json files found. Please provide the DevContainerJsonPath parameter." }
    }
}

function Get-DevContainerJson {
    param (
        [string]$devContainerJsonPath
    )

    $jsonContent = Get-Content -Path $devContainerJsonPath -Raw | ConvertFrom-Json
    return $jsonContent
}

function Get-DevContainerName {
    param (
        [string]$devContainerJsonPath
    )
    # Read the devcontainer.json file
    $jsonContent = Get-DevContainerJson -devContainerJsonPath $devContainerJsonPath

    # Get the container name from the json content, return null if not found
    if ($jsonContent.PSObject.Properties['name']) {
        return $jsonContent.name
    }
    return $null
}

function Get-DevContainerExtensions {
    param (
        [string]$devContainerJsonPath
    )

    $jsonContent = Get-DevContainerJson -devContainerJsonPath $devContainerJsonPath

    $extensions = $null
    if ($jsonContent.PSObject.properties["customizations"]) {
        $customizations = $jsonContent.customizations
        if ($customizations.PSObject.properties["vscode"]) {
            $vscode = $customizations.vscode
            if ($vscode.PSObject.properties["extensions"]) {
                $extensions = $vscode.extensions
            }
        }
    }

    return $extensions
}

function Get-ContainerEnv {
    param (
        [string]$containerId
    )
    
    $dockerEnv = docker inspect $containerId --format '{{json .Config.Env}}' | ConvertFrom-Json
    return $dockerEnv
}

function Invoke-ContainerBuild {
    param (
        [string]$containerName,
        [string]$containerLabel,
        [string]$workspaceFolder,
        [string]$devContainerJsonPath
    )
    Write-Verbose -Message "Building the container image $containerName for $devContainerJsonPath..."

    # Build the dev container
    & devcontainer build --workspace-folder="$workspaceFolder" --config="$devContainerJsonPath" --image-name="$containerLabel" 2>&1 | Write-Verbose

    # Run the dev container - the container will not run in wsl unless exported from a container instance instead of an image
    Write-Verbose -Message "Running the container image $containerLabel..."
    docker run $containerLabel | Write-Verbose

    $containerId = docker ps --latest --quiet
    if (-not $containerId) {
        throw "Could not find the container id."
    }

    Write-Verbose "Ran container $containerId"
    return $containerId
}

function Get-WslUserName {
    param (
        [string]$wslInstanceName
    )

    # Devcontainers create a user name with user id of 1000. The default user name is 'vscode', but it can be changed
    # in the dev container configuration, so it needs to be retrieved from the WSL instance.
    return Invoke-Wsl $wslInstanceName "id -nu 1000"
}

function Set-UserAccount {
    param (
        [string]$wslInstanceName,
        [string]$OldUserName,
        [string]$NewUserName
    )

    Write-Verbose "Changing user account from $OldUserName to $NewUserName..."
    Invoke-Wsl $wslInstanceName "usermod --login $NewUserName $OldUserName" | Write-Verbose
    Invoke-Wsl $wslInstanceName "usermod --home /home/$NewUserName -m $NewUserName" | Write-Verbose
    Invoke-Wsl $wslInstanceName "groupmod --new-name $NewUserName $OldUserName" | Write-Verbose
    
    # Dev containers use sudoers.d files to grant sudo permissions to the user without requiring a password
    # This makes the behavior of the WSL instance consistent with the dev container.
    Invoke-Wsl $wslInstanceName "mv /etc/sudoers.d/$OldUserName /etc/sudoers.d/$NewUserName" | Write-Verbose
    Invoke-Wsl $wslInstanceName "sed -i 's/$OldUserName/$NewUserName/g' /etc/sudoers.d/$NewUserName" | Write-Verbose
}

function New-WslConfigFile {
    param (
        [string]$wslInstanceName,
        [string]$UserName
    )

    Write-Verbose -Message "Writing /etc/wsl.conf in $wslInstanceName..."
    $configFileText = "[boot]`nsystemd=false`n`n[user]`ndefault=$UserName`n"
    $wslCommand = "echo '$configFileText' > /etc/wsl.conf"
    Invoke-Wsl $wslInstanceName "$wslCommand" | Write-Verbose
    
    # Shut down the wsl instance to apply the config file changes
    wsl.exe --terminate $wslInstanceName | Write-Verbose
}

function Get-WslInstanceName {
    param (
        [string]$wslInstanceName,
        [string]$containerName,
        [string]$workspaceFolder
    )
    if ($wslInstanceName) {
        return $wslInstanceName
    }
    if ($containerName) {
        return $containerName.Replace(" ", "")
    }
    # If no explicit name is provided, use the workspace folder name
    return (Split-Path -Leaf $workspaceFolder).Replace(" ", "")
}

function Get-WslInstanceFilePath {
    param (
        [string]$wslInstanceName,
        [string]$wslInstancesFolder
    )
    
    # String instead of script block to force variable expansion.
    $getWslInstanceFilePathScript = @"
        if (-not (Test-Path -Path $wslInstancesFolder -PathType Container)) {
            New-Item -Path $wslInstancesFolder -ItemType Directory | Out-Null
        }
        return Join-Path -Path $wslInstancesFolder -ChildPath $wslInstanceName
"@

    if ($IsWindows) {
        return Invoke-Expression $getWslInstanceFilePathScript
    }
    else {
        return pwsh.exe -Command $getWslInstanceFilePathScript
    }
}

function Test-WslInstanceName {
    param (
        [string]$wslInstanceName,
        [bool]$force
    )

    Write-Verbose "Checking if WSL instance $wslInstanceName already exists..."
    $existingInstances = wsl.exe --list
    $existingInstances | ForEach-Object { 
        $existingInstanceName = $_.Trim()
        if ($existingInstanceName -ieq $wslInstanceName) {
            if ($force) {
                Write-Verbose -Message "Removing existing WSL instance $wslInstanceName..."
                wsl.exe --unregister $wslInstanceName | Write-Verbose
            }
            else {
                throw "A WSL instance with the name $wslInstanceName already exists. Delete the instance or use the -Force parameter to overwrite it."
            }
        }
    }
}

function New-WslInstanceFromContainer {
    param (
        [string]$containerId,
        [string]$wslInstanceName,
        [string]$wslInstancePath
    )

    Write-Verbose -Message "Importing WSL instance $wslInstanceName from container $containerId to $wslInstancePath ..."
    docker export "$containerId" | wsl.exe --import $wslInstanceName $wslInstancePath - | Write-Verbose
    Write-Verbose -Message "Removing container instance $containerId..."
    docker rm $containerId --force --volumes | Write-Verbose
}

function Test-Command {
    param(
        [string]$commandName
    )
    try {
        if ($IsWindows) {
            $commandRef = Get-Command -Name $commandName -ErrorAction Stop
            Write-Verbose -Message "$commandName is installed: $($commandRef.Path)"
        }
        else {
            # In WSL, use 'which' to check for commands
            $result = bash -c "which $commandName 2>/dev/null"
            if ($LASTEXITCODE -ne 0) {
                throw "$commandName not found"
            }
            Write-Verbose -Message "$commandName is installed: $result"
        }
    }
    catch {
        throw "$commandName is not installed. Please install it before running this script."
    }
}

function Test-DockerDaemon {
    if ($IsWindows) {
        $errorOutput = & cmd.exe /c "docker ps 2>&1"
    }
    else {
        $errorOutput = bash -c "docker ps 2>&1"
    }
    if ($LASTEXITCODE -ne 0) {
        throw "Docker is not accessible. $errorOutput"
    }
    Write-Verbose -Message "Docker daemon is accessible."
}

function Install-Extensions {
    param (
        [string]$wslInstanceName,
        [string[]]$extensions
    )

    if ($extensions) {
        Write-Verbose -Message "Installing extensions in WSL instance $WslInstanceName..."
        Write-Progress $script:progressActivity -Status "Installing VS Code Server for Linux" -PercentComplete 85
        Invoke-Wsl $wslInstanceName "code --version" | Write-Verbose
        $extensionCount = $extensions.Count
        for ($i = 0; $i -lt $extensionCount; $i++) {
            $extension = $extensions[$i]
            $percentComplete = (($i / $extensionCount) * 15) + 84
            Write-Progress $script:progressActivity -Status "Installing VS Code extension $($extension)" -PercentComplete $percentComplete
            Invoke-Wsl $wslInstanceName "code --install-extension $extension" | Write-Verbose
        }
    }
    else {
        Write-Verbose -Message "No extensions to install."
    }
}

<# 
.SYNOPSIS
Adds environment variables to the WSL instance from the dev container. 

.DESCRIPTION
Dev containers use the /etc/environment file to set environment variables, but WSL does not read this file,
so this function writes the environment variables to the /etc/profile file in the WSL instance. It also prepends the PATH
variable with the existing path to avoid overwriting it with the container's PATH.
#>
function Set-WslEnv {
    param (
        [string[]]$containerEnv,
        [string]$wslInstanceName
    )

    Write-Verbose -Message "Setting environment variables in WSL instance $wslInstanceName..."

    foreach ($envVar in $containerEnv) {
        if ($envVar -notmatch "=") {
            throw "Environment variable '$envVar' is not valid. It must contain an '=' sign."
        }

        # Docker overwrites the PATH variable with the container's PATH, so change the PATH variable to prepend the
        # existing path. An example of the container path is below:
        #            PATH=/usr/local/go/bin:/go/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
        # Change to: PATH="$PATH:/usr/local/go/bin:/go/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
        if ($envVar.StartsWith("PATH=")) {
            $envVar = $envVar -replace "^PATH=", 'PATH=\$PATH:'
        }

        # Hack because dev containers set the GOPATH to /go. On WSL, access to modify that path requires root permissions.
        if ($envVar -eq "GOPATH=/go") {
            # The dev container sets the GOPATH to /go, but WSL uses $HOME/go. Change it to $HOME/go.
            $envVar = "GOPATH=$HOME/go"
        }
        
        # Enclose the value in double quotes and add 'export'.
        $envVar = $envVar -replace '=(.*)', '="$1"'
        $envVar = "export $envVar"

        # Write to /etc/profile because WSL does not read /etc/environment
        $wslCommand = "echo '$envVar' | sudo tee --append /etc/profile"
        Invoke-Wsl $wslInstanceName "$wslCommand" | Write-Verbose
    }
}

<#
.SYNOPSIS
Creates a WSL instance from a dev container specification (devcontainer.json file).
#>
function Invoke-Wsl {
    param (
        [Parameter(Position = 0, Mandatory = $true)]
        [string]$wslInstanceName,
        [Parameter(Position = 1, Mandatory = $true)]
        [string]$command
    )

    wsl.exe --distribution $wslInstanceName --cd "~" -- bash -c "$command"
}

function Set-WindowsGitConfig {
    param (
        [string]$wslInstanceName
    )

    Write-Verbose -Message "Creating symlink in WSL instance $wslInstanceName to the Windows git config file..."
    
    # Remove the existing .gitconfig file if it exists
    Invoke-Wsl $wslInstanceName "[ -f .gitconfig ] && rm .gitconfig" | Write-Verbose
    
    # Create a symlink to the Windows git config file, handling the path correctly whether we're in Windows or WSL
    $windowsUser = Get-WindowsUser
    Invoke-Wsl $wslInstanceName "ln -s /mnt/c/Users/$windowsUser/.gitconfig ~/.gitconfig" | Write-Verbose
}

function Get-WindowsUser {
    if ($IsWindows) {
        return $Env:USERNAME
    }

    # Use pwsh.exe on Windows when running from WSL.
    if (-not (Test-Path variable:\script:windowsUser)) {
        $script:windowsUser = pwsh.exe -command { $Env:username }
    }
    
    return $script:windowsUser.Trim()
}

function Get-DefaultWslInstancesFolder {

    # Script block to run on Windows to get the Windows path.
    $getDefaultWslInstancesFolder = { Join-Path -Path $Env:USERPROFILE -ChildPath "wsl" }
    
    # If this is not running on Windows, use pwsh.exe on Windows to run the script block.
    if ($IsWindows) {
        return & $getDefaultWslInstancesFolder
    }
    else {
        return pwsh.exe -Command $getDefaultWslInstancesFolder
    }
}

<#
.SYNOPSIS
Creates a WSL instance from a dev container specification (devcontainer.json file).

.DESCRIPTION
Automates the creation of a Windows Subsystem for Linux (WSL) instance using a development container specification.
It builds the container image from the dev container specification, runs the container, and then exports the container 
to a WSL instance. WSL, Docker Desktop, the devcontainer CLI, and pwsh must be installed before running this script.
This script can be run from Windows or WSL.

.NOTES
- Some containers overwrite the PATH variable in /etc/profile, the WSL-injected PATH elements will be overwritten.
- If the container sets up anything in the /etc/environment file, WSL ignores that file and uses /etc/profile instead.
- If the container requires human interaction upon starting, the script will pause and wait for input.

.PARAMETER WorkspaceFolder
The path to the workspace folder containing the devcontainer.json file. Defaults to the current directory.

.PARAMETER DevContainerJsonPath
The path to the devcontainer.json file. If not provided, the script will search for the file in the workspace folder.

.PARAMETER WslInstanceName
The name of the WSL instance. If not provided, it will use the container name.

.PARAMETER NewUserName
The new user name for the WSL instance. Defaults to the current user name.

.PARAMETER SkipUserNameChange
If specified, the script will not change the user name in the WSL instance and will use the default user name from
the dev container, which is typically 'vscode'.

.PARAMETER WslInstancesFolder
The path to the folder where the WSL instances are stored. Defaults to the user's Windows profile folder. 
Must be a Windows path, even when running this script from WSL because WSL instances are stored in the Windows file system.

.PARAMETER Force
When set to true, automatically deletes an existing WSL instance with the same name if it exists.

.EXAMPLE
# Create a WSL instance from the current directory's dev container
New-WslFromDevContainer

.EXAMPLE
# Create a WSL instance with a specific name and force overwrite, which deletes any existing instance with the same name.
New-WslFromDevContainer -WorkspaceFolder "./myproject" -WslInstanceName "mydev" -Force

.NOTES
Requires WSL, Docker Desktop, and devcontainer CLI to be installed.
#>  
function New-WslFromDevContainer {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [string]$WorkspaceFolder = ".",

        [Parameter(Mandatory = $false)]
        [string]$DevContainerJsonPath = $null,

        [Parameter(Mandatory = $false)]
        [string]$WslInstanceName = $null,

        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrWhiteSpace()]
        [string]$NewUserName = (Get-WindowsUser),
    
        [switch]$SkipUserNameChange = $false,

        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrWhiteSpace()]
        [string]$WslInstancesFolder = (Get-DefaultWslInstancesFolder),
        
        [Parameter(Mandatory = $false)]
        [switch]$Force
    )

    $script:progressActivity = "Installing WSL instance from Dev Container"

    Write-Progress $script:progressActivity -Status "Validating Environment" -PercentComplete 1
    Write-Verbose "FORCE = $Force"
    Test-Command -commandName "devcontainer"
    Test-Command -commandName "docker"
    Test-Command -commandName "wsl.exe"
    Test-Command -commandName "pwsh.exe"
    Test-DockerDaemon

    Write-Progress $script:progressActivity -Status "Validating Environment" -PercentComplete 5
    $DevContainerJsonPath = Find-DevContainerJsonFile -workspaceFolder $WorkspaceFolder -devContainerJsonPath $DevContainerJsonPath
    $containerName = Get-DevContainerName -devContainerJsonPath $DevContainerJsonPath
    $WslInstanceName = Get-WslInstanceName -wslInstanceName $WslInstanceName -containerName $containerName -workspaceFolder $WorkspaceFolder
    $containerLabel = $WslInstanceName.ToLower()
    Test-WslInstanceName -wslInstanceName $WslInstanceName -force $Force

    Write-Progress $script:progressActivity -Status "Building Dev Container" -PercentComplete 25
    $containerId = Invoke-ContainerBuild `
        -containerName $WslInstanceName `
        -containerLabel $containerLabel `
        -workspaceFolder $WorkspaceFolder `
        -devContainerJsonPath $DevContainerJsonPath

    $containerEnv = Get-ContainerEnv -containerId $containerId
    
    Write-Progress $script:progressActivity -Status "Importing WSL instance from dev container image" -PercentComplete 50
    $wslInstancePath = Get-WslInstanceFilePath -wslInstanceName $WslInstanceName -wslInstancesFolder $WslInstancesFolder
    New-WslInstanceFromContainer -containerId $containerId -wslInstanceName $WslInstanceName -wslInstancePath $wslInstancePath

    if ($SkipUserNameChange) {
        $userName = Get-WslUserName -wslInstanceName $WslInstanceName
    }
    else {
        $oldUserName = Get-WslUserName -wslInstanceName $WslInstanceName
        Set-UserAccount -wslInstanceName $WslInstanceName -OldUserName $oldUserName -NewUserName $NewUserName
        $userName = $NewUserName
    }

    Write-Progress $script:progressActivity -Status "Configuring WSL instance" -PercentComplete 75
    New-WslConfigFile -wslInstanceName $WslInstanceName -UserName $userName
    Set-WslEnv -containerEnv $containerEnv -wslInstanceName $WslInstanceName
    Set-WindowsGitConfig -wslInstanceName $WslInstanceName

    Write-Progress $script:progressActivity -Status "Installing VS Code extensions" -PercentComplete 80
    $extensions = Get-DevContainerExtensions -devContainerJsonPath $DevContainerJsonPath
    Install-Extensions -wslInstanceName $WslInstanceName -extensions $extensions

    Write-Progress $script:progressActivity -Status "Done" -PercentComplete 100 -Completed
}

Export-ModuleMember -Function New-WslFromDevContainer
Export-ModuleMember -Function Get-DevContainerName
Export-ModuleMember -Function Get-DevContainerJson
Export-ModuleMember -Function Get-DevContainerExtensions
