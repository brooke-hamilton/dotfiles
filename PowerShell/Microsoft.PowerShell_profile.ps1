
function devshell {
    Enter-VsDevShell 4fef1e7a -SkipAutomaticLocation
}

function vs {
    param (
        [Parameter(Mandatory=$true)]
        [string]$solutionPath
    )
    . "C:\Program Files\Microsoft Visual Studio\2022\Enterprise\Common7\IDE\devenv.com" $solutionPath
}

Set-Alias -Name ll -Value Get-ChildItem
Import-Module "$PSScriptRoot\New-WslFromDevContainer\New-WslFromDevContainer.psm1"
Import-Module "C:\Program Files\Microsoft Visual Studio\2022\Enterprise\Common7\Tools\Microsoft.VisualStudio.DevShell.dll"
