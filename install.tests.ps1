<#
.SYNOPSIS
    Pester tests for install.ps1's step selection / gating logic.

.DESCRIPTION
    These tests run install.ps1 in -Plan mode (no system changes) and inspect
    the transcript output to verify which steps would have run, would have
    been skipped, etc. Plan mode is also exercised end-to-end this way.

    Plan mode itself never invokes winget, dsc, or any side-effecting
    command -- it only optionally runs `dsc config test` for DSC-backed
    steps, which is read-only. To keep tests environment-independent we
    also -Skip the DSC steps so `dsc config test` is never invoked.

    Run with:
        Invoke-Pester .\install.tests.ps1
#>

BeforeAll {
    $script:RepoRoot = Split-Path -Parent $PSCommandPath
    $script:Install  = Join-Path $script:RepoRoot 'install.ps1'

    if (-not (Test-Path -LiteralPath $script:Install)) {
        throw "install.ps1 not found at $script:Install"
    }

    # All DSC-backed steps -- skipped in every test so `dsc config test` is
    # never invoked and tests don't depend on dsc being installed.
    $script:DscSteps = @('dsc-apps-to-remove', 'dsc-apps', 'dsc-desktop-settings')

    function Invoke-PlanForTest {
        param(
            [string[]]$ExtraArgs = @(),
            [string[]]$AlsoSkip  = @()
        )
        $allSkip = @($script:DscSteps + $AlsoSkip | Select-Object -Unique)
        $args = @(
            '-NoProfile', '-ExecutionPolicy', 'Bypass',
            '-File', $script:Install,
            '-Plan',
            '-Skip', ($allSkip -join ',')
        ) + $ExtraArgs

        $out = & pwsh @args 2>&1
        # Stringify so -match works on the whole transcript.
        return ($out | Out-String)
    }

    # Every step name declared by install.ps1, in source order. Keep in sync
    # with the Invoke-Step calls.
    $script:AdminSteps = @(
        'winget-configure-enable',
        'winget-upgrade-all',
        'install-dsc',
        'dsc-apps-to-remove',
        'dsc-apps',
        'vs-build-tools',
        'docker-desktop',
        'radius-dev-env',
        'remove-desktop-shortcuts'
    )
    $script:UserSteps = @(
        'git-ssh',
        'wslconfig',
        'cloud-init',
        'dsc-desktop-settings',
        'refresh-explorer',
        'cmake-path',
        'cargo-zigbuild',
        'rust-targets',
        'devcontainer-cli',
        'apt-cacher-ng'
    )
}

Describe 'install.ps1 plan mode' {

    It 'announces PLAN mode' {
        $out = Invoke-PlanForTest
        $out | Should -Match 'PLAN mode: no system changes will be made\.'
    }

    It 'plans every non-skipped step exactly once' {
        $out = Invoke-PlanForTest
        $allSteps = $script:AdminSteps + $script:UserSteps |
            Where-Object { $script:DscSteps -notcontains $_ }
        foreach ($s in $allSteps) {
            ([regex]::Matches($out, "\[PLAN\] $([regex]::Escape($s)) ")).Count |
                Should -Be 1 -Because "step '$s' should be planned exactly once"
        }
    }

    It 'tags admin steps with [admin]' {
        $out = Invoke-PlanForTest
        foreach ($s in $script:AdminSteps | Where-Object { $script:DscSteps -notcontains $_ }) {
            $out | Should -Match "\[PLAN\] $([regex]::Escape($s)) \[admin\]"
        }
    }

    It 'tags user steps with [user]' {
        $out = Invoke-PlanForTest
        foreach ($s in $script:UserSteps | Where-Object { $script:DscSteps -notcontains $_ }) {
            $out | Should -Match "\[PLAN\] $([regex]::Escape($s)) \[user\]"
        }
    }
}

Describe 'install.ps1 -Skip / -Only selection' {

    It 'skips a single named step' {
        $out = Invoke-PlanForTest -AlsoSkip @('wslconfig')
        $out | Should -Match '\[SKIP\] wslconfig'
        $out | Should -Not -Match '\[PLAN\] wslconfig '
    }

    It 'accepts comma-joined Skip values' {
        # Pass the comma-joined string through Invoke-PlanForTest's AlsoSkip,
        # which gets re-joined with DSC skips and forwarded as a single -Skip
        # value. Verifies install.ps1 splits "a,b" back into separate names.
        $out = Invoke-PlanForTest -AlsoSkip @('wslconfig,cloud-init')
        $out | Should -Match '\[SKIP\] wslconfig'
        $out | Should -Match '\[SKIP\] cloud-init'
    }

    It '-Only restricts the run to the named steps' {
        $out = Invoke-PlanForTest -ExtraArgs @('-Only', 'cmake-path')
        ([regex]::Matches($out, '\[PLAN\] cmake-path ')).Count | Should -Be 1
        # Every other step should be marked SKIP-not-in-Only.
        $out | Should -Match '\[SKIP-not-in-Only\] git-ssh'
        $out | Should -Match '\[SKIP-not-in-Only\] winget-configure-enable'
    }
}

Describe 'install.ps1 -AdminOnly / -UserOnly gating' {

    It '-UserOnly plans user steps and SKIP-admin-step the admin steps' {
        $out = Invoke-PlanForTest -ExtraArgs @('-UserOnly')
        foreach ($s in $script:UserSteps | Where-Object { $script:DscSteps -notcontains $_ }) {
            $out | Should -Match "\[PLAN\] $([regex]::Escape($s)) \[user\]"
        }
        foreach ($s in $script:AdminSteps | Where-Object { $script:DscSteps -notcontains $_ }) {
            $out | Should -Match "\[SKIP-admin-step\] $([regex]::Escape($s))"
        }
    }

    It '-AdminOnly skips user-step entries' {
        # Not elevated: admin steps will hit either [SKIP-needs-admin] (not elevated)
        # or [PLAN] (elevated). User steps must be SKIP-user-step regardless.
        $out = Invoke-PlanForTest -ExtraArgs @('-AdminOnly')
        foreach ($s in $script:UserSteps | Where-Object { $script:DscSteps -notcontains $_ }) {
            $out | Should -Match "\[SKIP-user-step\] $([regex]::Escape($s))"
        }
    }

    It 'rejects -AdminOnly with -UserOnly' {
        $out = & pwsh -NoProfile -ExecutionPolicy Bypass -File $script:Install -AdminOnly -UserOnly 2>&1
        ($out | Out-String) | Should -Match 'mutually exclusive'
    }
}

Describe 'install.ps1 admin gating when unelevated' {

    It 'skips admin steps with SKIP-needs-admin when not elevated' {
        $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        if ($isAdmin) {
            Set-ItResult -Skipped -Because 'this Pester session is elevated; admin gating cannot be observed.'
            return
        }
        # Use -Only to restrict execution to admin steps without -Plan, so the
        # admin gate (which runs after Plan returns) is actually exercised.
        # Every named admin step is gated; user steps are filtered out by -Only.
        $adminTargets = $script:AdminSteps | Where-Object { $script:DscSteps -notcontains $_ }
        $out = & pwsh -NoProfile -ExecutionPolicy Bypass -File $script:Install -Only ($adminTargets -join ',') 2>&1
        $text = $out | Out-String
        foreach ($s in $adminTargets) {
            $text | Should -Match "\[SKIP-needs-admin\] $([regex]::Escape($s))"
        }
    }
}
