$desktopPath = [Environment]::GetFolderPath("Desktop")
$publicDesktopPath = "C:\Users\Public\Desktop"

Get-ChildItem -Path $desktopPath -Filter *.lnk -File -ErrorAction SilentlyContinue | Remove-Item -Force -Verbose
Get-ChildItem -Path $publicDesktopPath -Filter *.lnk -File -ErrorAction SilentlyContinue | Remove-Item -Force -Verbose
