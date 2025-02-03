Set-StrictMode -Version 3.0
$ErrorActionPreference = "Stop"

function Find-DevContainerJsonFile {
    param (
        [string]$workspaceFolder,
        [string]$devContainerJsonPath
    )

    if ($devContainerJsonPath) {
        if (-not (Test-Path -Path $devContainerJsonPath -PathType Leaf)) {
            throw "No devcontainer.json file found at the specified path."
        }
        return $devContainerJsonPath
    }

    $devContainerJson = Get-ChildItem -Path $workspaceFolder -Filter "devcontainer.json" -Recurse -File
    if(-not $devContainerJson) { throw "No devcontainer.json files found in the workspace folder." }
    switch ($devContainerJson.Count) {
        0 { throw "No devcontainer.json files found in the workspace folder." }
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

    # Get the container name from the json content
    $containerName = $jsonContent.name

    if (-not $containerName) {
        throw "Could not find the name element in $devContainerJsonPath."
    }

    return $containerName.Replace(" ", "")
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
    devcontainer build --workspace-folder="$workspaceFolder" --config="$devContainerJsonPath" --image-name="$containerLabel" `
    | Write-Verbose

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
        [string]$containerName
    )
    if (-not $wslInstanceName) {
        return $containerName
    }
    return $wslInstanceName
}

function Get-WslInstanceFilePath {
    param (
        [string]$wslInstanceName,
        [string]$wslInstancesFolder
    )
    if (-not (Test-Path -Path $wslInstancesFolder -PathType Container)) {
        New-Item -Path $wslInstancesFolder -ItemType Directory | Out-Null
    }
    return Join-Path -Path $wslInstancesFolder -ChildPath $wslInstanceName
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
            if($force) {
                Write-Verbose -Message "Removing existing WSL instance $wslInstanceName..."
                wsl.exe --unregister $wslInstanceName | Write-Verbose
            } else{
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
        $commandRef = Get-Command -Name $commandName -ErrorAction Stop
        Write-Verbose -Message "$commandName is installed: $($commandRef.Path)"
    }
    catch {
        throw "$commandName is not installed. Please install it before running this script."
    }
}

function Test-DockerDaemon {
    $errorOutput = & cmd.exe /c "docker ps 2>&1"
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
        $extensions | ForEach-Object {
            Invoke-Wsl $wslInstanceName "code --install-extension $_" | Write-Verbose
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

    wsl.exe -d $wslInstanceName -- bash -c "$command"
}

function Set-WindowsGitConfig {
    param (
        [string]$wslInstanceName
    )

    Write-Verbose -Message "Creating symlink in WSL instance $wslInstanceName to the Windows git config file..."

    # Remove the existing .gitconfig file if it exists.
    Invoke-Wsl $wslInstanceName "[ -f .gitconfig ] && rm .gitconfig" | Write-Verbose

    # Create a symlink to the Windows git config file.
    Invoke-Wsl $wslInstanceName "ln -s /mnt/c/Users/$Env:USERNAME/.gitconfig ~/.gitconfig" | Write-Verbose
}

<#
.SYNOPSIS
Creates a WSL instance from a dev container specification (devcontainer.json file).

.DESCRIPTION
Automates the creation of a Windows Subsystem for Linux (WSL) instance using a development container specification.
It builds the container image from the dev container specification, runs the container, and then exports the container to a WSL instance.
WSL, Docker Desktop, and the devcontainer CLI must be installed before running this script.

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
The path to the folder where the WSL instances are stored. Defaults to the user's profile folder.

.PARAMETER Force
When set to true, automatically deletes an existing WSL instance with the same name if it exists.

.EXAMPLE
# Create a WSL instance from the current directory's dev container
New-WslFromDevContainer

.EXAMPLE
# Create a WSL instance with a specific name and force overwrite
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
        [string]$NewUserName = $Env:USERNAME,
    
        [switch]$SkipUserNameChange = $false,

        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrWhiteSpace()]
        [string]$WslInstancesFolder = (Join-Path -Path $Env:USERPROFILE -ChildPath "wsl"),

        [Parameter(Mandatory = $false)]
        [switch]$Force
    )

    Write-Verbose "FORCE0 = $Force"
    Test-Command -commandName "devcontainer"
    Test-Command -commandName "docker"
    Test-Command -commandName "wsl"
    Test-DockerDaemon

    $DevContainerJsonPath = Find-DevContainerJsonFile -workspaceFolder $WorkspaceFolder -devContainerJsonPath $DevContainerJsonPath
    $containerName = Get-DevContainerName -devContainerJsonPath $DevContainerJsonPath
    $containerLabel = $containerName.ToLower()
    $WslInstanceName = Get-WslInstanceName -wslInstanceName $WslInstanceName -containerName $containerName
    Write-Verbose "FORCE3 = $Force"
    Test-WslInstanceName -wslInstanceName $WslInstanceName -force $Force
    
    $containerId = Invoke-ContainerBuild `
        -containerName $containerName `
        -containerLabel $containerLabel `
        -workspaceFolder $WorkspaceFolder `
        -devContainerJsonPath $DevContainerJsonPath

    $containerEnv = Get-ContainerEnv -containerId $containerId
    
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

    New-WslConfigFile -wslInstanceName $WslInstanceName -UserName $userName

    Set-WslEnv -containerEnv $containerEnv -wslInstanceName $WslInstanceName

    Set-WindowsGitConfig -wslInstanceName $WslInstanceName

    $extensions = Get-DevContainerExtensions -devContainerJsonPath $DevContainerJsonPath
    Install-Extensions -wslInstanceName $WslInstanceName -extensions $extensions
}

Export-ModuleMember -Function New-WslFromDevContainer
Export-ModuleMember -Function Get-DevContainerName
Export-ModuleMember -Function Get-DevContainerExtensions
Export-ModuleMember -Function Get-ContainerEnv
Export-ModuleMember -Function Invoke-ContainerBuild
Export-ModuleMember -Function Set-WslEnv
