
if ($IsWindows) {
    $script:HasGit = $null -ne (Get-Command git -ErrorAction SilentlyContinue)

    function Write-GitPromptSegment {
        param (
            [Parameter(Mandatory = $true)]
            [string]$Prefix,
            [Parameter(Mandatory = $true)]
            [int]$Count
        )

        $segment = "$Prefix$Count"
        if ($Count -ne 0) {
            Write-Host $segment -ForegroundColor Yellow -NoNewline
        } else {
            Write-Host $segment -NoNewline
        }
    }

    function prompt {
        $currentPath = (Get-Location).Path
        Write-Host "PS $currentPath" -NoNewline

        if ($script:HasGit) {
            $branch = $null
            $stagedCount = 0
            $unstagedCount = 0
            $untrackedCount = 0
            $aheadCount = 0
            $statusLines = git status --porcelain=2 --branch 2>$null

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
                Write-Host "(" -NoNewline
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
        Enter-VsDevShell 4fef1e7a -SkipAutomaticLocation
    }

    function vs {
        param (
            [Parameter(Mandatory = $true)]
            [string]$solutionPath
        )
        . "C:\Program Files\Microsoft Visual Studio\2022\Enterprise\Common7\IDE\devenv.com" $solutionPath
    }

    Set-Alias -Name ll -Value Get-ChildItem
    Import-Module "$PSScriptRoot\New-WslFromDevContainer\New-WslFromDevContainer.psm1"
    Import-Module "C:\Program Files\Microsoft Visual Studio\2022\Enterprise\Common7\Tools\Microsoft.VisualStudio.DevShell.dll"
} else {
    Import-Module "$PSScriptRoot/New-WslFromDevContainer/New-WslFromDevContainer.psm1"
}