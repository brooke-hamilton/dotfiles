<#
.DESCRIPTION
    Uses winget to check for updates to VS Code and VS Code Insiders, upgrades them if a newer
    version is available, and then updates all installed extensions for both editors.
#>

$apps = @(
    @{
        Name      = "VS Code"
        WingetId  = "Microsoft.VisualStudioCode"
        Command   = "code"
    },
    @{
        Name      = "VS Code Insiders"
        WingetId  = "Microsoft.VisualStudioCode.Insiders"
        Command   = "code-insiders"
    }
)

if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    Write-Error "winget is not available on PATH."
    return
}

function Test-WingetPackageMatch {
    param(
        [Parameter(Mandatory)]
        [string]$PackageId,

        [Parameter(Mandatory)]
        [string[]]$CommandArgs
    )

    $output = winget @CommandArgs 2>$null
    return ($LASTEXITCODE -eq 0) -and ($output | Where-Object { $_ -match [regex]::Escape($PackageId) })
}

foreach ($app in $apps) {
    Write-Output "Checking for $($app.Name) updates..."

    $isInstalled = Test-WingetPackageMatch -PackageId $app.WingetId -CommandArgs @(
        "list", "--id", $app.WingetId, "-e", "--accept-source-agreements", "--disable-interactivity"
    )

    if (-not $isInstalled) {
        Write-Output "$($app.Name) is not installed."
        continue
    }

    $hasUpdate = Test-WingetPackageMatch -PackageId $app.WingetId -CommandArgs @(
        "list", "--id", $app.WingetId, "-e", "--upgrade-available", "--accept-source-agreements", "--disable-interactivity"
    )

    if ($hasUpdate) {
        Write-Output "$($app.Name) has an update available. Upgrading..."
        winget upgrade --id $app.WingetId -e --silent --accept-package-agreements --accept-source-agreements --disable-interactivity

        if ($LASTEXITCODE -ne 0) {
            Write-Warning "Failed to upgrade $($app.Name) (exit code $LASTEXITCODE)."
        }
    }
    else {
        Write-Output "$($app.Name) is up to date."
    }

    $cmdPath = Get-Command $app.Command -ErrorAction SilentlyContinue
    if ($cmdPath) {
        Write-Output "Updating $($app.Name) extensions..."
        & $app.Command --update-extensions
    }
    else {
        Write-Output "$($app.Name) ($($app.Command)) not found on PATH, skipping extension update."
    }

    Write-Output ""
}
