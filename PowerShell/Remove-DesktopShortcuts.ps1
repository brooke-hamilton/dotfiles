<#
.DESCRIPTION
    This script removes all Windows desktop shortcuts (.lnk files) from both the current user's desktop
    and the Public Desktop folder.
#>

$desktopPath = [Environment]::GetFolderPath("Desktop")
$publicDesktopPath = "C:\Users\Public\Desktop"

Get-ChildItem -Path $desktopPath -Filter *.lnk -File -ErrorAction SilentlyContinue | Remove-Item -Force
Get-ChildItem -Path $publicDesktopPath -Filter *.lnk -File -ErrorAction SilentlyContinue | Remove-Item -Force
