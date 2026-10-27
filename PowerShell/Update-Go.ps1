#Requires -Version 5.1

param(
    [string] $SdkRoot = 'D:\Go\sdk',
    [string] $GoPath = 'D:\Go\workspace',
    [string] $GoCache = 'D:\Go\cache\build',
    [string] $GoTemp = 'D:\Go\cache\tmp',
    [string] $GoEnv = 'D:\Go\config\env',
    [ValidateSet('amd64', 'arm64')]
    [string] $Architecture = $(if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'arm64' } else { 'amd64' })
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
# Large recursive deletions can leave stale progress records in Windows Terminal.
$ProgressPreference = 'SilentlyContinue'

$tools = @(
    'golang.org/x/tools/gopls@latest'
    'github.com/go-delve/delve/cmd/dlv@latest'
    'golang.org/x/tools/cmd/goimports@latest'
    'golang.org/x/vuln/cmd/govulncheck@latest'
    'honnef.co/go/tools/cmd/staticcheck@latest'
)

function Stop-GoProcess {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string[]] $Paths
    )

    $fullPaths = @($Paths | ForEach-Object {
        [System.IO.Path]::GetFullPath(
            [Environment]::ExpandEnvironmentVariables($_)
        ).TrimEnd('\')
    })

    foreach ($process in Get-Process -ErrorAction Stop) {
        if (-not $process.Path) {
            continue
        }

        $matchesPath = $false
        foreach ($path in $fullPaths) {
            if ($process.Path.Equals($path, [System.StringComparison]::OrdinalIgnoreCase) -or
                $process.Path.StartsWith("$path\", [System.StringComparison]::OrdinalIgnoreCase)) {
                $matchesPath = $true
                break
            }
        }

        if ($matchesPath -and $PSCmdlet.ShouldProcess(
            "$($process.Path) (PID $($process.Id))", 'Stop process before removing Go files'
        )) {
            Write-Host "Stopping $($process.Path) (PID $($process.Id))..."
            try {
                Stop-Process -Id $process.Id -Force -ErrorAction Stop
                Wait-Process -InputObject $process -Timeout 10 -ErrorAction Stop
            }
            catch {
                throw "Could not stop $($process.Path) (PID $($process.Id)). Close editors and other programs using Go, then rerun this script. $($_.Exception.Message)"
            }
        }
    }
}

function Move-GoToolCache {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('gopls', 'goimports')]
        [string] $Name,

        [Parameter(Mandatory)]
        [string] $Destination
    )

    $source = Join-Path $env:LOCALAPPDATA $Name
    $destinationPath = [System.IO.Path]::GetFullPath(
        [Environment]::ExpandEnvironmentVariables($Destination)
    ).TrimEnd('\')
    if ($destinationPath.Equals($source, [System.StringComparison]::OrdinalIgnoreCase) -or
        $destinationPath.StartsWith("$source\", [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "The $Name cache destination must be outside $source."
    }

    $sourceJunction = $null
    $sourceExists = Test-Path -LiteralPath $source -ErrorAction Stop
    if ($sourceExists) {
        $item = Get-Item -LiteralPath $source -Force -ErrorAction Stop
        if ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
            if ($item.LinkType -eq 'Junction' -and
                $destinationPath.Equals([string] $item.Target, [System.StringComparison]::OrdinalIgnoreCase) -and
                (Test-Path -LiteralPath $destinationPath -PathType Container -ErrorAction Stop)) {
                if ($Name -eq 'goimports') {
                    return
                }
                $sourceJunction = $item
                $sourceExists = $false
            }
            else {
                throw "$source already links to another location or has a missing target. Resolve it before moving the cache."
            }
        }
        if (-not $item.PSIsContainer) {
            throw "$source is not a cache directory."
        }
        if ($sourceExists -and (Test-Path -LiteralPath $destinationPath -ErrorAction Stop)) {
            throw "Both $source and $destinationPath exist. Resolve the conflicting cache directories before retrying."
        }
    }

    if ($PSCmdlet.ShouldProcess($source, "Move $Name cache to $destinationPath")) {
        Write-Host "Redirecting $source to $destinationPath..."
        New-Item -ItemType Directory -Path $destinationPath -Force -ErrorAction Stop | Out-Null
        if ($sourceJunction) {
            $sourceJunction.Delete()
        }
        if ($sourceExists) {
            # Robocopy supports cross-volume moves; Move-Item cannot move directories between drives.
            $copyOutput = & robocopy.exe $source $destinationPath /E /MOVE /COPY:DAT /DCOPY:DAT /XJ /R:1 /W:1 /NFL /NDL /NP
            if ($LASTEXITCODE -ge 8) {
                throw "Failed to move $source to $destinationPath (robocopy exit code $LASTEXITCODE). Both locations may contain cache files. $($copyOutput -join [Environment]::NewLine)"
            }
            if (Test-Path -LiteralPath $source -ErrorAction Stop) {
                if (@(Get-ChildItem -LiteralPath $source -Force -ErrorAction Stop).Count -gt 0) {
                    throw "Files remain in $source after moving the cache. Resolve them before creating the junction."
                }
                Remove-Item -LiteralPath $source -Force -ErrorAction Stop
            }
        }
        if ($Name -eq 'goimports') {
            New-Item -ItemType Junction -Path $source -Target $destinationPath -ErrorAction Stop | Out-Null
        }
    }
}

function Remove-GoPath {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string] $Path
    )

    $fullPath = [System.IO.Path]::GetFullPath(
        [Environment]::ExpandEnvironmentVariables($Path)
    ).TrimEnd('\')
    $root = [System.IO.Path]::GetPathRoot($fullPath).TrimEnd('\')
    $protectedPaths = @(
        $root
        $HOME
        $env:USERPROFILE
        $env:LOCALAPPDATA
        $env:APPDATA
        $env:TEMP
    ) |
        Where-Object { $_ } |
        ForEach-Object {
            [System.IO.Path]::GetFullPath(
                [Environment]::ExpandEnvironmentVariables($_)
            ).TrimEnd('\')
        }

    if ($protectedPaths -contains $fullPath) {
        throw "Refusing to remove protected path $fullPath."
    }

    if (Test-Path -LiteralPath $fullPath) {
        Write-Host "Removing $fullPath..."
        if ($PSCmdlet.ShouldProcess($fullPath, 'Remove Go installation or cache path')) {
            Remove-Item -LiteralPath $fullPath -Recurse -Force
        }
    }
}

function Clear-GoToolCache {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string] $Path
    )

    if ($PSCmdlet.ShouldProcess($Path, 'Clear Go tool cache contents')) {
        Write-Host "Clearing cache contents in $Path..."
        Get-ChildItem -LiteralPath $Path -Force -ErrorAction Stop |
            ForEach-Object {
                Remove-GoPath -Path $_.FullName -ErrorAction Stop
            }
    }
}

function Set-UserGoPath {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string[]] $Add,

        [Parameter(Mandatory)]
        [string[]] $Remove
    )

    $pathsToRemove = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::OrdinalIgnoreCase
    )
    $Remove | Where-Object { $_ } | ForEach-Object {
        [void] $pathsToRemove.Add(
            [System.IO.Path]::GetFullPath(
                [Environment]::ExpandEnvironmentVariables($_)
            ).TrimEnd('\')
        )
    }

    $updatedPath = [System.Collections.Generic.List[string]]::new()
    $seenPaths = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::OrdinalIgnoreCase
    )

    $Add | Where-Object { $_ } | ForEach-Object {
        $fullPath = [System.IO.Path]::GetFullPath(
            [Environment]::ExpandEnvironmentVariables($_)
        ).TrimEnd('\')
        if ($seenPaths.Add($fullPath)) {
            $updatedPath.Add($_)
        }
    }

    ([Environment]::GetEnvironmentVariable('Path', 'User') -split ';') |
        Where-Object { $_ } |
        ForEach-Object {
            $fullPath = [System.IO.Path]::GetFullPath(
                [Environment]::ExpandEnvironmentVariables($_)
            ).TrimEnd('\')
            if (-not $pathsToRemove.Contains($fullPath) -and $seenPaths.Add($fullPath)) {
                $updatedPath.Add($_)
            }
        }

    if ($PSCmdlet.ShouldProcess('User PATH', 'Replace Go SDK and tool entries')) {
        [Environment]::SetEnvironmentVariable('Path', ($updatedPath -join ';'), 'User')
    }
}

$previousGoEnvironment = $null
$previousGo = Get-Command go -ErrorAction SilentlyContinue
if ($previousGo) {
    $previousGoEnvironment = & $previousGo.Source env -json GOROOT GOPATH GOBIN GOMODCACHE GOCACHE GOTMPDIR GOENV GOTELEMETRYDIR |
        ConvertFrom-Json
    if ($LASTEXITCODE -ne 0) {
        throw 'Failed to inspect the existing Go environment.'
    }
}

Write-Host 'Finding the latest stable Go release...'

$releases = Invoke-RestMethod -Uri 'https://go.dev/dl/?mode=json'
$release = @($releases) |
    Where-Object { $_.stable } |
    Select-Object -First 1

$archive = $release.files |
    Where-Object {
        $_.os -eq 'windows' -and
        $_.arch -eq $Architecture -and
        $_.kind -eq 'archive'
    } |
    Select-Object -First 1

if (-not $archive) {
    throw "No Windows $Architecture archive was found for $($release.version)."
}

$tempDirectory = Join-Path $env:TEMP ('update-go-' + [guid]::NewGuid().ToString('N'))
$archivePath = Join-Path $tempDirectory $archive.filename
$extractPath = Join-Path $tempDirectory 'extracted'
$extractedSdk = Join-Path $extractPath 'go'

try {
    New-Item -ItemType Directory -Path $tempDirectory | Out-Null

    Write-Host "Downloading $($archive.filename)..."
    Invoke-WebRequest -Uri "https://go.dev/dl/$($archive.filename)" -OutFile $archivePath

    Write-Host 'Verifying SHA-256 checksum...'
    $actualHash = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash
    if (-not $actualHash.Equals($archive.sha256, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Checksum verification failed. Expected $($archive.sha256), received $actualHash."
    }

    Write-Host 'Extracting the SDK...'
    Expand-Archive -LiteralPath $archivePath -DestinationPath $extractPath

    if (-not (Test-Path -LiteralPath (Join-Path $extractedSdk 'bin\go.exe'))) {
        throw 'The downloaded archive does not contain go\bin\go.exe.'
    }

    Write-Host 'Removing previous Go installations, tools, and caches...'

    $pathsToRemove = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::OrdinalIgnoreCase
    )

    @(
        $SdkRoot
        $GoPath
        $GoCache
        $GoTemp
        $GoEnv
        (Join-Path $HOME 'go')
        (Join-Path $env:LOCALAPPDATA 'go-build')
        (Join-Path $env:LOCALAPPDATA 'go')
        (Join-Path $env:APPDATA 'go')
    ) | ForEach-Object {
        if ($_) {
            [void] $pathsToRemove.Add($_)
        }
    }

    if ($previousGoEnvironment) {
        @(
            $previousGoEnvironment.GOROOT
            $previousGoEnvironment.GOBIN
            $previousGoEnvironment.GOMODCACHE
            $previousGoEnvironment.GOCACHE
            $previousGoEnvironment.GOTMPDIR
            $previousGoEnvironment.GOENV
            $previousGoEnvironment.GOTELEMETRYDIR
        ) | ForEach-Object {
            if ($_) {
                [void] $pathsToRemove.Add($_)
            }
        }

        $previousGoEnvironment.GOPATH -split [System.IO.Path]::PathSeparator |
            Where-Object { $_ } |
            ForEach-Object {
                [void] $pathsToRemove.Add($_)
            }
    }

    $versionedSdkDirectory = Join-Path $HOME 'sdk'
    if (Test-Path -LiteralPath $versionedSdkDirectory) {
        Get-ChildItem -LiteralPath $versionedSdkDirectory -Directory -Force |
            Where-Object { $_.Name -match '^go\d' } |
            ForEach-Object {
                [void] $pathsToRemove.Add($_.FullName)
            }
    }

    Stop-GoProcess -Paths @($pathsToRemove)

    $toolCacheRoot = Split-Path -Parent $SdkRoot
    Move-GoToolCache -Name gopls -Destination (Join-Path $toolCacheRoot 'gopls')
    $env:GOPLSCACHE = $toolCacheRoot
    [Environment]::SetEnvironmentVariable('GOPLSCACHE', $toolCacheRoot, 'User')
    Move-GoToolCache -Name goimports -Destination (Join-Path $toolCacheRoot 'goimports')

    foreach ($name in @('gopls', 'goimports')) {
        Clear-GoToolCache -Path (Join-Path $toolCacheRoot $name)
    }

    foreach ($path in $pathsToRemove) {
        Remove-GoPath -Path $path
    }

    Get-ChildItem -LiteralPath $env:TEMP -Directory -Force -ErrorAction SilentlyContinue |
        Where-Object {
            $_.Name -like 'go-build*' -or
            $_.Name -like 'go-toolchain-*' -or
            $_.Name -like 'update-go-*'
        } |
        Where-Object { $_.FullName -ne $tempDirectory } |
        ForEach-Object {
            Remove-GoPath -Path $_.FullName
        }

    foreach ($variable in @('GOROOT', 'GOPATH', 'GOBIN', 'GOMODCACHE', 'GOCACHE', 'GOTMPDIR', 'GOTELEMETRYDIR')) {
        Remove-Item "Env:$variable" -ErrorAction SilentlyContinue
        [Environment]::SetEnvironmentVariable($variable, $null, 'User')
    }

    New-Item -ItemType Directory -Path (Split-Path -Parent $SdkRoot) -Force | Out-Null
    Move-Item -LiteralPath $extractedSdk -Destination $SdkRoot

    $go = Join-Path $SdkRoot 'bin\go.exe'
    $toolBin = Join-Path $GoPath 'bin'
    $moduleCache = Join-Path $GoPath 'pkg\mod'
    $sdkBin = Join-Path $SdkRoot 'bin'

    New-Item -ItemType Directory -Path $toolBin -Force | Out-Null
    New-Item -ItemType Directory -Path $GoCache -Force | Out-Null
    New-Item -ItemType Directory -Path $GoTemp -Force | Out-Null
    New-Item -ItemType Directory -Path (Split-Path -Parent $GoEnv) -Force | Out-Null

    $env:GOENV = $GoEnv
    & $go env -w "GOPATH=$GoPath" "GOMODCACHE=$moduleCache" "GOCACHE=$GoCache" "GOTMPDIR=$GoTemp"
    if ($LASTEXITCODE -ne 0) {
        throw 'Failed to write the Go environment configuration.'
    }

    $env:GOPATH = $GoPath
    $env:GOBIN = $toolBin
    $env:GOMODCACHE = $moduleCache
    $env:GOCACHE = $GoCache
    $env:GOTMPDIR = $GoTemp

    [Environment]::SetEnvironmentVariable('GOPATH', $env:GOPATH, 'User')
    [Environment]::SetEnvironmentVariable('GOMODCACHE', $env:GOMODCACHE, 'User')
    [Environment]::SetEnvironmentVariable('GOCACHE', $env:GOCACHE, 'User')
    [Environment]::SetEnvironmentVariable('GOTMPDIR', $env:GOTMPDIR, 'User')
    [Environment]::SetEnvironmentVariable('GOENV', $env:GOENV, 'User')

    Write-Host 'Disabling Go telemetry...'
    & $go telemetry off
    if ($LASTEXITCODE -ne 0) {
        throw 'Failed to disable Go telemetry.'
    }

    $oldGoPathEntries = @(
        (Join-Path $HOME 'go\bin')
        (Join-Path $env:ProgramFiles 'Go\bin')
    )
    if ($previousGoEnvironment) {
        $oldGoPathEntries += @(
            $(if ($previousGoEnvironment.GOROOT) { Join-Path $previousGoEnvironment.GOROOT 'bin' })
            $previousGoEnvironment.GOBIN
        )
        $oldGoPathEntries += $previousGoEnvironment.GOPATH -split [System.IO.Path]::PathSeparator |
            Where-Object { $_ } |
            ForEach-Object { Join-Path $_ 'bin' }
    }

    Set-UserGoPath -Add @($sdkBin, $toolBin) -Remove $oldGoPathEntries

    Write-Host 'Updating Go developer tools...'
    foreach ($tool in $tools) {
        Write-Host "  $tool"
        & $go install $tool
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to install $tool."
        }
    }

    Write-Host ''
    & $go version
    & $go env GOROOT GOPATH GOBIN GOMODCACHE GOCACHE GOTMPDIR GOENV GOTELEMETRYDIR
}
finally {
    if (Test-Path -LiteralPath $tempDirectory) {
        Remove-Item -LiteralPath $tempDirectory -Recurse -Force
    }
}
