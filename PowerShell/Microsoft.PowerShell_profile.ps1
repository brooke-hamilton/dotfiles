
if ($IsWindows) {
    $script:HasGit = $null -ne (Get-Command git -ErrorAction SilentlyContinue)

    function Write-GitPromptSegment {
        param (
            [Parameter(Mandatory = $true)]
            [string]$Prefix,
            [Parameter(Mandatory = $true)]
            [int]$Count
        )

        if ($Count -ne 0) {
            Write-Host " $Prefix$Count" -ForegroundColor Yellow -NoNewline
        }
    }

    function Test-InGitRepo {
        param ([string]$StartPath)

        if ([string]::IsNullOrEmpty($StartPath)) { return $false }

        $dir = $StartPath
        while (-not [string]::IsNullOrEmpty($dir)) {
            $candidate = [System.IO.Path]::Combine($dir, '.git')
            if ([System.IO.Directory]::Exists($candidate) -or [System.IO.File]::Exists($candidate)) {
                return $true
            }
            $parent = [System.IO.Path]::GetDirectoryName($dir)
            if ([string]::IsNullOrEmpty($parent) -or $parent -eq $dir) { return $false }
            $dir = $parent
        }
        return $false
    }

    function prompt {
        $currentPath = (Get-Location).Path
        Write-Host "PS $currentPath" -NoNewline

        try {
            $inRepo = $script:HasGit -and (Test-InGitRepo -StartPath $currentPath)
        } catch {
            $inRepo = $false
        }

        if ($inRepo) {
            $branch = $null
            $stagedCount = 0
            $unstagedCount = 0
            $untrackedCount = 0
            $aheadCount = 0
            $statusLines = git status --porcelain=2 --branch --untracked-files=no 2>$null

            if ($LASTEXITCODE -eq 0) {
                foreach ($line in $statusLines) {
                    $recordType = $line[0]

                    if ($line.StartsWith("# branch.head ")) {
                        $branch = $line.Substring(14).Trim()
                        continue
                    }

                    if ($line.StartsWith("# branch.ab ")) {
                        if ($line -match "\+(\d+)") {
                            $aheadCount = [int]$Matches[1]
                        }
                        continue
                    }

                    if ($recordType -eq '?') {
                        $untrackedCount++
                        continue
                    }

                    if ($recordType -eq '1' -or $recordType -eq '2' -or $recordType -eq 'u') {
                        $xy = $line.Substring(2, 2)
                        if ($xy[0] -ne '.') {
                            $stagedCount++
                        }
                        if ($xy[1] -ne '.') {
                            $unstagedCount++
                        }
                    }
                }
            }

            if (-not [string]::IsNullOrWhiteSpace($branch)) {
                Write-Host " (" -NoNewline
                Write-Host $branch -ForegroundColor Red -NoNewline

                Write-GitPromptSegment -Prefix "+" -Count $stagedCount
                Write-GitPromptSegment -Prefix "u" -Count $unstagedCount
                Write-GitPromptSegment -Prefix "?" -Count $untrackedCount
                Write-GitPromptSegment -Prefix "↑" -Count $aheadCount

                Write-Host ")" -NoNewline
            }
        }

        return "> "
    }

    function devshell {
        $vsWherePath = Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio\Installer\vswhere.exe"
        if (-not (Test-Path $vsWherePath)) {
            Write-Error "vswhere.exe not found."
            return
        }

        $vsInstanceId = & $vsWherePath -latest -property instanceId | Select-Object -First 1
        if ([string]::IsNullOrWhiteSpace($vsInstanceId)) {
            Write-Error "No Visual Studio instance found."
            return
        }

        Enter-VsDevShell $vsInstanceId -SkipAutomaticLocation
    }

    function vs {
        param (
            [Parameter(Mandatory = $true)]
            [string]$solutionPath
        )
        #. "C:\Program Files\Microsoft Visual Studio\2022\Enterprise\Common7\IDE\devenv.com" $solutionPath
        . "C:\Program Files\Microsoft Visual Studio\18\Enterprise\Common7\IDE\devenv.com" $solutionPath
    }

    Set-Alias -Name ll -Value Get-ChildItem
    Import-Module "$PSScriptRoot\New-WslFromDevContainer\New-WslFromDevContainer.psm1"
    #Import-Module "C:\Program Files\Microsoft Visual Studio\2022\Enterprise\Common7\Tools\Microsoft.VisualStudio.DevShell.dll"
    Import-Module "C:\Program Files\Microsoft Visual Studio\18\Enterprise\Common7\Tools\Microsoft.VisualStudio.DevShell.dll"
} else {
    Import-Module "$PSScriptRoot/New-WslFromDevContainer/New-WslFromDevContainer.psm1"
}