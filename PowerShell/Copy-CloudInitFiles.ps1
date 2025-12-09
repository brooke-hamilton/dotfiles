# Copy cloud-init files to user profile
$cloudInitDestPath = "$env:USERPROFILE\.cloud-init"
if (-not (Test-Path -Path $cloudInitDestPath)) {
    New-Item -Path $cloudInitDestPath -ItemType Directory | Out-Null
}

$cloudInitSourcePath = Join-Path -Path $PSScriptRoot -ChildPath "..\wsl\cloud-init"
Get-ChildItem -Path "$cloudInitSourcePath\*.*" | ForEach-Object {
    $destFile = Join-Path -Path $cloudInitDestPath -ChildPath $_.Name
    Copy-Item -Force -Path $_.FullName -Destination $destFile
    # Replace __username__ placeholder with current Windows username
    (Get-Content -Path $destFile -Raw) -replace '__username__', $env:USERNAME | Set-Content -Path $destFile -NoNewline
}

Write-Output "Cloud-init files copied to $cloudInitDestPath"
