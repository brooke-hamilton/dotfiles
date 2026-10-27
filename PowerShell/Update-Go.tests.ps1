BeforeAll {
    $scriptPath = Join-Path $PSScriptRoot 'Update-Go.ps1'
    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile(
        $scriptPath, [ref]$tokens, [ref]$parseErrors
    )
    $functions = $ast.FindAll({
        param($node)
        $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
            $node.Name -in @('Stop-GoProcess', 'Move-GoToolCache', 'Remove-GoPath', 'Clear-GoToolCache')
    }, $true)
    foreach ($function in $functions) {
        . ([scriptblock]::Create($function.Extent.Text))
    }
}

Describe 'Clear-GoToolCache' {
    BeforeEach {
        $script:cacheRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $script:cacheRoot | Out-Null
        $script:cacheJunction = Join-Path $script:cacheRoot 'goimports-link'
    }

    AfterEach {
        if (Test-Path -LiteralPath $script:cacheJunction) {
            (Get-Item -LiteralPath $script:cacheJunction -Force).Delete()
        }
    }

    It 'clears <Name> files while preserving the cache directory and any junction' -TestCases @(
        @{ Name = 'gopls' }
        @{ Name = 'goimports' }
    ) {
        param($Name)
        $cache = Join-Path $script:cacheRoot $Name
        $nested = New-Item -ItemType Directory -Path (Join-Path $cache 'nested')
        Set-Content -LiteralPath (Join-Path $nested.FullName 'index') -Value 'cached data'
        $hidden = New-Item -ItemType File -Path (Join-Path $cache 'hidden-index')
        $hidden.Attributes = $hidden.Attributes -bor [System.IO.FileAttributes]::Hidden
        if ($Name -eq 'goimports') {
            New-Item -ItemType Junction -Path $script:cacheJunction -Target $cache | Out-Null
        }

        Clear-GoToolCache -Path $cache
        Clear-GoToolCache -Path $cache

        Test-Path -LiteralPath $cache -PathType Container | Should -BeTrue
        @(Get-ChildItem -LiteralPath $cache -Force).Count | Should -Be 0
        if ($Name -eq 'goimports') {
            (Get-Item -LiteralPath $script:cacheJunction).LinkType | Should -Be 'Junction'
            Set-Content -LiteralPath (Join-Path $script:cacheJunction 'new-index') -Value 'new data'
            Get-Content -LiteralPath (Join-Path $cache 'new-index') | Should -Be 'new data'
        }
    }

    It 'preserves cache contents under WhatIf' {
        $index = Join-Path $script:cacheRoot 'index'
        Set-Content -LiteralPath $index -Value 'cached data'

        Clear-GoToolCache -Path $script:cacheRoot -WhatIf

        Get-Content -LiteralPath $index | Should -Be 'cached data'
    }

    It 'propagates a deletion failure instead of reporting successful cleanup' {
        Set-Content -LiteralPath (Join-Path $script:cacheRoot 'index') -Value 'cached data'
        Mock Remove-GoPath { throw 'Access denied' }

        { Clear-GoToolCache -Path $script:cacheRoot } | Should -Throw '*Access denied*'
    }
}

Describe 'Stop-GoProcess' {
    BeforeEach {
        Mock Get-Process {
            [pscustomobject]@{ Id = 101; Path = 'D:\Go\workspace\bin\gopls.exe' }
            [pscustomobject]@{ Id = 102; Path = 'D:\Go\sdk\bin\go.exe' }
            [pscustomobject]@{ Id = 103; Path = 'D:\Go\workspace-other\bin\gopls.exe' }
            [pscustomobject]@{ Id = 104; Path = 'C:\Other\gopls.exe' }
            [pscustomobject]@{ Id = 105; Path = $null }
        }
        Mock Stop-Process {}
        Mock Wait-Process {} -RemoveParameterType InputObject
    }

    It 'stops and waits for only processes inside the cleanup directories' {
        Stop-GoProcess -Paths @('d:\go\workspace\', 'D:\Go\sdk')

        Should -Invoke Stop-Process -Exactly 2
        Should -Invoke Stop-Process -Exactly 1 -ParameterFilter { $Id -eq 101 -and $Force }
        Should -Invoke Stop-Process -Exactly 1 -ParameterFilter { $Id -eq 102 -and $Force }
        Should -Invoke Wait-Process -Exactly 2
        Should -Invoke Wait-Process -Exactly 1 -ParameterFilter { $InputObject.Id -eq 101 }
        Should -Invoke Wait-Process -Exactly 1 -ParameterFilter { $InputObject.Id -eq 102 }
    }

    It 'also handles an executable selected directly for removal' {
        Stop-GoProcess -Paths @('D:\Go\workspace\bin\gopls.exe')

        Should -Invoke Stop-Process -Exactly 1 -ParameterFilter { $Id -eq 101 }
    }

    It 'aborts with actionable guidance when a process cannot be stopped' {
        Mock Stop-Process { throw 'Access is denied' }

        { Stop-GoProcess -Paths @('D:\Go\workspace') } |
            Should -Throw '*PID 101*Close editors*Access is denied*'
        Should -Invoke Wait-Process -Exactly 0
    }

    It 'aborts when a stopped process does not exit in time' {
        Mock Wait-Process { throw 'Timed out' }

        { Stop-GoProcess -Paths @('D:\Go\workspace') } |
            Should -Throw '*PID 101*Close editors*Timed out*'
    }

    It 'does not stop processes under WhatIf' {
        Stop-GoProcess -Paths @('D:\Go\workspace') -WhatIf

        Should -Invoke Stop-Process -Exactly 0
        Should -Invoke Wait-Process -Exactly 0
    }
}

Describe 'Move-GoToolCache' {
    BeforeEach {
        $script:previousLocalAppData = $env:LOCALAPPDATA
        $testRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $env:LOCALAPPDATA = Join-Path $testRoot 'local'
        $script:cacheDestination = Join-Path $testRoot 'relocated\goimports'
        New-Item -ItemType Directory -Path $env:LOCALAPPDATA -Force | Out-Null
        Mock robocopy.exe {
            $sourcePath, $targetPath = $args[0], $args[1]
            Get-ChildItem -LiteralPath $sourcePath -Force |
                Move-Item -Destination $targetPath -ErrorAction Stop
            $global:LASTEXITCODE = 1
        }
    }

    AfterEach {
        foreach ($name in @('gopls', 'goimports')) {
            $source = Join-Path $env:LOCALAPPDATA $name
            if (Test-Path -LiteralPath $source) {
                $item = Get-Item -LiteralPath $source -Force
                if ($item.LinkType -eq 'Junction') {
                    $item.Delete()
                }
            }
        }
        $env:LOCALAPPDATA = $script:previousLocalAppData
    }

    It 'moves existing cache files and redirects subsequent writes to the destination' {
        $source = New-Item -ItemType Directory -Path (Join-Path $env:LOCALAPPDATA 'goimports')
        Set-Content -LiteralPath (Join-Path $source.FullName 'index') -Value 'cached data'

        Move-GoToolCache -Name goimports -Destination $script:cacheDestination

        (Get-Item -LiteralPath $source.FullName).LinkType | Should -Be 'Junction'
        Get-Content -LiteralPath (Join-Path $script:cacheDestination 'index') | Should -Be 'cached data'
        Set-Content -LiteralPath (Join-Path $source.FullName 'new-index') -Value 'new data'
        Get-Content -LiteralPath (Join-Path $script:cacheDestination 'new-index') | Should -Be 'new data'
        Should -Invoke robocopy.exe -Exactly 1
    }

    It 'creates a new cache and remains unchanged on subsequent runs' {
        Move-GoToolCache -Name goimports -Destination $script:cacheDestination
        Move-GoToolCache -Name goimports -Destination $script:cacheDestination

        (Get-Item -LiteralPath (Join-Path $env:LOCALAPPDATA 'goimports')).Target |
            Should -Be $script:cacheDestination
        Should -Invoke robocopy.exe -Exactly 0
    }

    It 'does not merge conflicting directories or remove either cache' {
        $source = New-Item -ItemType Directory -Path (Join-Path $env:LOCALAPPDATA 'goimports')
        New-Item -ItemType Directory -Path $script:cacheDestination -Force | Out-Null

        { Move-GoToolCache -Name goimports -Destination $script:cacheDestination } |
            Should -Throw '*conflicting cache directories*'
        (Get-Item -LiteralPath $source.FullName).LinkType | Should -BeNullOrEmpty
        Test-Path -LiteralPath $script:cacheDestination | Should -BeTrue
        Should -Invoke robocopy.exe -Exactly 0
    }

    It 'reports a failed move without deleting the original cache directory' {
        $source = New-Item -ItemType Directory -Path (Join-Path $env:LOCALAPPDATA 'goimports')
        Set-Content -LiteralPath (Join-Path $source.FullName 'index') -Value 'cached data'
        Mock robocopy.exe { $global:LASTEXITCODE = 8; 'Access denied' }

        { Move-GoToolCache -Name goimports -Destination $script:cacheDestination } |
            Should -Throw '*robocopy exit code 8*Access denied*'
        Get-Content -LiteralPath (Join-Path $source.FullName 'index') | Should -Be 'cached data'
        (Get-Item -LiteralPath $source.FullName).LinkType | Should -BeNullOrEmpty
    }

    It 'does not move files or create a destination under WhatIf' {
        Move-GoToolCache -Name goimports -Destination $script:cacheDestination -WhatIf

        Test-Path -LiteralPath $script:cacheDestination | Should -BeFalse
        Should -Invoke robocopy.exe -Exactly 0
    }

    It 'moves the gopls cache without creating a junction and supports repeat runs' {
        $source = New-Item -ItemType Directory -Path (Join-Path $env:LOCALAPPDATA 'gopls')
        $destination = Join-Path (Split-Path -Parent $script:cacheDestination) 'gopls'
        Set-Content -LiteralPath (Join-Path $source.FullName 'index') -Value 'cached data'

        Move-GoToolCache -Name gopls -Destination $destination
        Move-GoToolCache -Name gopls -Destination $destination

        Test-Path -LiteralPath $source.FullName | Should -BeFalse
        Get-Content -LiteralPath (Join-Path $destination 'index') | Should -Be 'cached data'
        Should -Invoke robocopy.exe -Exactly 1
    }
}
