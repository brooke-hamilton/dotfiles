<#
.SYNOPSIS
Records and analyzes Microsoft Defender Antivirus scan performance.

.DESCRIPTION
Uses the supported Microsoft Defender Antivirus Performance Analyzer to identify the files, paths, extensions, and processes that consume the most scan time. It measures Defender activity caused by any workload, rather than general system CPU usage. Capture mode must run from an elevated PowerShell terminal. Run the workload itself from a separate, non-elevated terminal.

Each run creates a directory containing the ETL trace, a readable report, a machine-readable JSON report, CSV files for each ranked category, and an environment snapshot that includes Defender performance mode. When Go is available, the script also records Go cache locations.

The ETL and reports can contain file paths, process names, and other personally identifiable information. Review them before sharing.

.PARAMETER TracePath
Analyzes an existing Defender performance ETL instead of recording a new trace.

.PARAMETER Seconds
Records for a fixed number of seconds. Omit this parameter to stop the recording interactively by pressing Enter.

.PARAMETER OutputRoot
Directory under which timestamped capture or analysis directories are created.

.PARAMETER Top
Number of entries to include in each ranked report category.

.PARAMETER PathDepth
Directory depth used to aggregate the top-path report.

.EXAMPLE
.\Measure-DefenderScanPerformance.ps1

Starts an interactive recording. While it is running, reproduce the workload in a separate, non-elevated terminal, then return and press Enter.

.EXAMPLE
.\Measure-DefenderScanPerformance.ps1 -Seconds 120

Records Defender scan activity for two minutes and then writes the reports.

.EXAMPLE
.\Measure-DefenderScanPerformance.ps1 -TracePath "$HOME\DefenderPerformance\capture-20260905-091608\defender-scans.etl"

Generates a fresh set of reports from an existing trace.

.LINK
https://learn.microsoft.com/defender-endpoint/tune-performance-defender-antivirus

.LINK
https://learn.microsoft.com/defender-endpoint/microsoft-defender-endpoint-antivirus-performance-mode
#>
[CmdletBinding(DefaultParameterSetName = "Capture")]
param(
    [Parameter(Mandatory, ParameterSetName = "Analyze")]
    [ValidateNotNullOrEmpty()]
    [string]$TracePath,

    [Parameter(ParameterSetName = "Capture")]
    [ValidateRange(1, 86400)]
    [int]$Seconds,

    [ValidateNotNullOrEmpty()]
    [string]$OutputRoot = $(Join-Path -Path $HOME -ChildPath "DefenderPerformance"),

    [ValidateRange(1, 10000)]
    [int]$Top = 50,

    [ValidateRange(1, 20)]
    [int]$PathDepth = 5
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Assert-CommandAvailable {
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )

    if (-not (Get-Command -Name $Name -ErrorAction SilentlyContinue)) {
        throw "Required command '$Name' is not available. Update Microsoft Defender Antivirus and retry."
    }
}

function New-DefenderPerformanceRunDirectory {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$Root,

        [Parameter(Mandatory)]
        [string]$Prefix
    )

    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $runDirectory = Join-Path -Path $Root -ChildPath "$Prefix-$timestamp"
    if ($PSCmdlet.ShouldProcess($runDirectory, "Create Defender performance output directory")) {
        New-Item -ItemType Directory -Path $runDirectory -Force | Out-Null
    }

    return $runDirectory
}

function Write-DefenderEnvironmentSnapshot {
    param(
        [Parameter(Mandatory)]
        [string]$OutputDirectory
    )

    $preference = Get-MpPreference
    $status = Get-MpComputerStatus
    $volumes = @(Get-Volume | Select-Object DriveLetter, FileSystemLabel, FileSystemType, DriveType, HealthStatus, OperationalStatus, Size, SizeRemaining)
    $devDriveQueries = @()

    if (Get-Command -Name "fsutil.exe" -ErrorAction SilentlyContinue) {
        foreach ($volume in $volumes | Where-Object { $_.DriveLetter }) {
            $drive = "$($volume.DriveLetter):"
            $queryOutput = @(& fsutil.exe devdrv query $drive 2>&1)
            $devDriveQueries += [pscustomobject]@{
                Drive    = $drive
                ExitCode = $LASTEXITCODE
                Output   = ($queryOutput -join [Environment]::NewLine)
            }
        }
    }

    $snapshot = [ordered]@{
        CapturedAt             = (Get-Date).ToString("o")
        ComputerName           = $env:COMPUTERNAME
        CurrentDirectory       = (Get-Location).Path
        Temp                   = $env:TEMP
        Tmp                    = $env:TMP
        DefenderProductVersion = $status.AMProductVersion
        DefenderRunningMode    = $status.AMRunningMode
        AntivirusEnabled       = $status.AntivirusEnabled
        RealTimeProtection     = $status.RealTimeProtectionEnabled
        PerformanceModeStatus  = $preference.PerformanceModeStatus
        PerformanceModeNote    = "Microsoft documents 0 as enabled and 1 as disabled."
        Volumes                = $volumes
        DevDriveQueries        = $devDriveQueries
    }

    $snapshot |
        ConvertTo-Json -Depth 6 |
        Set-Content -LiteralPath (Join-Path -Path $OutputDirectory -ChildPath "environment.json") -Encoding utf8

    if (Get-Command -Name "go" -ErrorAction SilentlyContinue) {
        $goEnvironment = & go env -json GOCACHE GOMODCACHE GOTMPDIR GOPATH
        if ($LASTEXITCODE -ne 0) {
            throw "The 'go env' command failed with exit code $LASTEXITCODE."
        }

        $goEnvironment |
            Set-Content -LiteralPath (Join-Path -Path $OutputDirectory -ChildPath "go-environment.json") -Encoding utf8
    }
}

function Write-DefenderPerformanceReport {
    param(
        [Parameter(Mandatory)]
        [string]$InputTracePath,

        [Parameter(Mandatory)]
        [string]$OutputDirectory,

        [Parameter(Mandatory)]
        [int]$EntryCount,

        [Parameter(Mandatory)]
        [int]$TopPathDepth
    )

    $reportArguments = @{
        Path          = $InputTracePath
        TopFiles      = $EntryCount
        TopPaths      = $EntryCount
        TopPathsDepth = $TopPathDepth
        TopExtensions = $EntryCount
        TopProcesses  = $EntryCount
        TopScans      = $EntryCount
        Overview      = $true
    }

    $textReportPath = Join-Path -Path $OutputDirectory -ChildPath "report.txt"
    Get-MpPerformanceReport @reportArguments |
        Out-String -Width 240 |
        Set-Content -LiteralPath $textReportPath -Encoding utf8

    $rawReport = Get-MpPerformanceReport @reportArguments -Raw
    $rawReport |
        ConvertTo-Json -Depth 10 |
        Set-Content -LiteralPath (Join-Path -Path $OutputDirectory -ChildPath "report.json") -Encoding utf8

    $csvReports = [ordered]@{
        TopFiles      = "top-files.csv"
        TopPaths      = "top-paths.csv"
        TopExtensions = "top-extensions.csv"
        TopProcesses  = "top-processes.csv"
        TopScans      = "top-scans.csv"
    }

    foreach ($property in $csvReports.Keys) {
        $items = @($rawReport.$property)
        if ($items.Count -gt 0) {
            $items |
                Export-Csv -LiteralPath (Join-Path -Path $OutputDirectory -ChildPath $csvReports[$property]) -NoTypeInformation -Encoding utf8
        }
    }
}

function Invoke-DefenderScanPerformanceMeasurement {
    param(
        [Parameter(Mandatory)]
        [hashtable]$Parameters
    )

    Assert-CommandAvailable -Name "Get-MpPerformanceReport"

    if ($Parameters.ParameterSetName -eq "Analyze") {
        if (-not (Test-Path -LiteralPath $Parameters.TracePath -PathType Leaf)) {
            throw "Trace file '$($Parameters.TracePath)' does not exist."
        }

        $resolvedTracePath = (Resolve-Path -LiteralPath $Parameters.TracePath).Path
        $traceBaseName = [IO.Path]::GetFileNameWithoutExtension($resolvedTracePath)
        $prefix = "$traceBaseName-analysis"
        $runDirectory = New-DefenderPerformanceRunDirectory -Root $Parameters.OutputRoot -Prefix $prefix
    }
    else {
        Assert-CommandAvailable -Name "New-MpPerformanceRecording"

        if (-not (Test-IsAdministrator)) {
            throw "Capture mode requires an elevated PowerShell terminal. Run this script as Administrator, but run the workload itself from a separate, non-elevated terminal."
        }

        $runDirectory = New-DefenderPerformanceRunDirectory -Root $Parameters.OutputRoot -Prefix "capture"
        $resolvedTracePath = Join-Path -Path $runDirectory -ChildPath "defender-scans.etl"

        Write-Information "Recording Defender scan activity to '$resolvedTracePath'." -InformationAction Continue
        Write-Information "Run the workload you want to investigate from a separate, non-elevated terminal." -InformationAction Continue

        try {
            if ($Parameters.ContainsKey("Seconds")) {
                New-MpPerformanceRecording -RecordTo $resolvedTracePath -Seconds $Parameters.Seconds -ErrorAction Stop
            }
            else {
                New-MpPerformanceRecording -RecordTo $resolvedTracePath -ErrorAction Stop
            }
        }
        catch {
            if ($_.Exception.Message -match "Windows Performance Recorder is already recording") {
                throw "A Defender performance recording is already running. Cancel it with 'wpr -cancel -instancename MSFT_MpPerformanceRecording', then retry."
            }

            throw
        }
    }

    Write-Information "Generating Defender performance reports..." -InformationAction Continue
    Write-DefenderEnvironmentSnapshot -OutputDirectory $runDirectory
    Write-DefenderPerformanceReport -InputTracePath $resolvedTracePath -OutputDirectory $runDirectory -EntryCount $Parameters.Top -TopPathDepth $Parameters.PathDepth

    Write-Information "Reports saved to '$runDirectory'." -InformationAction Continue
    Write-Information "Start with 'top-paths.csv', 'top-files.csv', and 'go-environment.json'." -InformationAction Continue
    Write-Warning "The ETL and reports can contain sensitive file paths and process names. Review them before sharing."

    return [pscustomobject]@{
        TracePath       = $resolvedTracePath
        OutputDirectory = $runDirectory
        TextReport      = Join-Path -Path $runDirectory -ChildPath "report.txt"
        JsonReport      = Join-Path -Path $runDirectory -ChildPath "report.json"
    }
}

if ($MyInvocation.InvocationName -ne ".") {
    $invocationParameters = @{
        ParameterSetName = $PSCmdlet.ParameterSetName
        OutputRoot       = $OutputRoot
        Top              = $Top
        PathDepth        = $PathDepth
    }

    if ($PSCmdlet.ParameterSetName -eq "Analyze") {
        $invocationParameters.TracePath = $TracePath
    }
    elseif ($PSBoundParameters.ContainsKey("Seconds")) {
        $invocationParameters.Seconds = $Seconds
    }

    Invoke-DefenderScanPerformanceMeasurement -Parameters $invocationParameters
}
