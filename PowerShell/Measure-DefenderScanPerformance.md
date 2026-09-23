# Trace Microsoft Defender workload overhead

[Measure-DefenderScanPerformance.ps1](Measure-DefenderScanPerformance.ps1) wraps the supported Microsoft Defender Antivirus Performance Analyzer and records the files, paths, extensions, processes, and individual scans that consume the most scan time. It can measure Defender activity caused by any workload, including builds, package restores, tests, file copies, and application startup. It is not a general-purpose CPU profiler; it reports only Microsoft Defender Antivirus scan activity. The capture must run as Administrator, but the workload should run from a separate, non-elevated terminal.

Start an interactive trace from an elevated PowerShell terminal:

```powershell
.\PowerShell\Measure-DefenderScanPerformance.ps1
```

Run the workload you want to investigate in another terminal, then return to the elevated terminal and press Enter. For a fixed capture window, use `-Seconds`:

```powershell
.\PowerShell\Measure-DefenderScanPerformance.ps1 -Seconds 120
```

Each run writes a timestamped directory under `~/DefenderPerformance`. Start with `top-paths.csv`, `top-files.csv`, and `top-scans.csv`. The directory also contains the original ETL, a readable report, a raw JSON report, ranked CSVs, and Defender/volume state in `environment.json`. When `go` is available, the script additionally writes `go-environment.json` with `GOCACHE`, `GOMODCACHE`, `GOTMPDIR`, and `GOPATH`, which can help identify Go directories that are candidates for relocation.

To regenerate reports from an existing ETL without recording another workload:

```powershell
.\PowerShell\Measure-DefenderScanPerformance.ps1 -TracePath "$HOME\DefenderPerformance\capture-20260905-091608\defender-scans.etl"
```

On Windows 11, a trusted Dev Drive can use Defender performance mode, which scans file opens asynchronously instead of disabling scanning. Verify the `PerformanceModeStatus` and `DevDriveQueries` fields in `environment.json`; Microsoft documents `0` as enabled and `1` as disabled. Enable performance mode from an elevated PowerShell terminal if policy permits:

```powershell
Set-MpPreference -PerformanceModeStatus Enabled
```

Prefer relocating measured high-churn directories to a trusted Dev Drive over broad Defender exclusions. Exclusions prevent scans entirely and reduce protection. The ETL and generated reports can contain sensitive file paths and process names, so review them before sharing.
