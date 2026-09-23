BeforeAll {
    $script:ScriptPath = Join-Path -Path $PSScriptRoot -ChildPath "Measure-DefenderScanPerformance.ps1"
    . $script:ScriptPath
}

Describe "Measure-DefenderScanPerformance helpers" {
    It "reports administrator status as a Boolean" {
        Test-IsAdministrator | Should -BeOfType ([bool])
    }

    It "throws when a required command is unavailable" {
        { Assert-CommandAvailable -Name "command-that-does-not-exist-for-this-test" } |
            Should -Throw "*is not available*"
    }

    It "creates a timestamped run directory" {
        $directory = New-DefenderPerformanceRunDirectory -Root $TestDrive -Prefix "capture"

        Test-Path -LiteralPath $directory -PathType Container | Should -BeTrue
        (Split-Path -Path $directory -Leaf) | Should -Match "^capture-\d{8}-\d{6}$"
    }
}

Describe "Write-DefenderPerformanceReport" {
    BeforeEach {
        Mock Get-MpPerformanceReport {
            if ($Raw) {
                return [pscustomobject]@{
                    TopFiles = @(
                        [pscustomobject]@{
                            Path         = "C:\src\project\main.go"
                            TotalDuration = 123
                        }
                    )
                    TopPaths = @(
                        [pscustomobject]@{
                            Path          = "C:\src\project"
                            TotalDuration = 123
                        }
                    )
                    TopExtensions = @()
                    TopProcesses = @(
                        [pscustomobject]@{
                            Process       = "compile.exe"
                            TotalDuration = 123
                        }
                    )
                    TopScans = @(
                        [pscustomobject]@{
                            Path     = "C:\src\project\main.go"
                            Duration = 123
                        }
                    )
                }
            }

            return "formatted Defender report"
        }
    }

    It "writes text, JSON, and populated CSV reports" {
        Write-DefenderPerformanceReport -InputTracePath "C:\trace.etl" -OutputDirectory $TestDrive -EntryCount 10 -TopPathDepth 4

        Test-Path -LiteralPath (Join-Path $TestDrive "report.txt") | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $TestDrive "report.json") | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $TestDrive "top-files.csv") | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $TestDrive "top-paths.csv") | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $TestDrive "top-processes.csv") | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $TestDrive "top-scans.csv") | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $TestDrive "top-extensions.csv") | Should -BeFalse
    }
}
