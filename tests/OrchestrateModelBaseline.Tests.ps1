# SPDX-FileCopyrightText: 2026 SyuanTsai
# SPDX-License-Identifier: Apache-2.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'orchestrate-ai-delivery model baseline update' {
BeforeAll {
    $script:RepositoryRoot = Split-Path -Parent $PSScriptRoot
    $script:SkillRoot = Join-Path $script:RepositoryRoot 'skills/orchestrate-ai-delivery'
    $script:ScriptPath = Join-Path $script:SkillRoot 'scripts/Update-ModelBaseline.ps1'
    $script:RealBaselinePath = Join-Path $script:SkillRoot 'references/models.json'
    . $script:ScriptPath -BaselinePath $script:RealBaselinePath

    function Write-TestBaseline {
        param([string]$Path, [object[]]$Models)
        $value = [pscustomobject][ordered]@{
            schemaVersion = 1
            reviewedOn = '2026-11-02'
            models = @($Models)
            efforts = [pscustomobject][ordered]@{ codex = @('low'); copilot = @('none'); claude = @('low') }
        }
        $null = New-Item -ItemType Directory -Path (Split-Path -Parent $Path) -Force
        Set-Content -LiteralPath $Path -Value ($value | ConvertTo-Json -Depth 6) -Encoding utf8
    }

    function New-TestBaselineModel {
        param(
            [string]$Cli = 'codex', [string]$Id = 'existing', [string]$Status = 'active',
            [AllowNull()][object]$Capability = 3, [AllowNull()][object]$Cost = 2,
            [string]$Evidence = 'official', [string]$Notes = 'original'
        )
        [pscustomobject][ordered]@{
            cli = $Cli; id = $Id; family = 'vendor'; capability = $Capability; cost = $Cost
            status = $Status; evidence = $Evidence; notes = $Notes
        }
    }

    function Write-TestCache {
        param(
            [string]$Directory, [string]$Environment, [object[]]$Models,
            [string]$CheckedUtc = '2026-11-01T16:30:00.0000000Z', [bool]$Stale = $false,
            [string]$Cli = 'codex'
        )
        $null = New-Item -ItemType Directory -Path $Directory -Force
        $clis = [ordered]@{}
        $clis[$Cli] = [pscustomobject]@{ stale = $Stale; checkedUtc = $CheckedUtc }
        $cache = [pscustomobject][ordered]@{
            schemaVersion = 1; status = 'updated'; environment = $Environment
            lastCheckedUtc = $CheckedUtc; warnings = @(); suggestions = @()
            clis = [pscustomobject]$clis; models = @($Models)
        }
        Set-Content -LiteralPath (Join-Path $Directory "model-availability.$Environment.json") `
            -Value ($cache | ConvertTo-Json -Depth 6) -Encoding utf8
    }

    function New-TestAvailabilityModel {
        param([string]$Id, [string]$Status, [string]$Reason, [string]$Cli = 'codex')
        [pscustomobject]@{ cli = $Cli; id = $Id; family = 'vendor'; status = $Status; selectable = $false; reason = $Reason }
    }
}

Context 'Input safety' {
    # Scenario: no personal or work observation cache exists. Purpose: require an explicit local discovery run.
    It 'UnitT10_throws when no availability cache exists' {
        $baselinePath = Join-Path $TestDrive 'no-cache/models.json'
        Write-TestBaseline -Path $baselinePath -Models @(New-TestBaselineModel)
        { Invoke-ModelBaselineUpdate -BaselinePath $baselinePath -CacheDirectory (Join-Path $TestDrive 'empty') -DryRun } |
            Should -Throw 'No availability cache found; run Update-ModelAvailability.ps1 first.'
    }

    # Scenario: the target is the installed Skill baseline. Purpose: prohibit runtime mutation of managed Skill files.
    It 'UnitT20_rejects a baseline inside the Skill directory' {
        Mock Test-ModelBaselineRepositoryCheckout { $false }
        { Invoke-ModelBaselineUpdate -BaselinePath $script:RealBaselinePath -CacheDirectory $TestDrive -DryRun } |
            Should -Throw 'The baseline must be edited in a repository working copy, not in the installed Skill directory.'
    }

    # Scenario: a maintainer runs the script from a repository checkout against that checkout's baseline.
    # Purpose: allow the documented maintenance flow; the guard only blocks installed Skill directories.
    It 'UnitT21_allows the baseline of the repository checkout that contains the script' {
        # The canonical test run uses a snapshot without .git, so the checkout shape is built in TestDrive.
        $checkoutSkill = Join-Path $TestDrive 'checkout/skills/orchestrate-ai-delivery'
        $null = New-Item -ItemType Directory -Path $checkoutSkill -Force
        $null = New-Item -ItemType Directory -Path (Join-Path $TestDrive 'checkout/catalog') -Force
        Set-Content -LiteralPath (Join-Path $TestDrive 'checkout/catalog/source.json') -Value '{}'
        Set-Content -LiteralPath (Join-Path $TestDrive 'checkout/.git') -Value 'gitdir: elsewhere'
        Test-ModelBaselineRepositoryCheckout -SkillDirectory $checkoutSkill | Should -BeTrue

        Mock Test-ModelBaselineRepositoryCheckout { $true }
        { Invoke-ModelBaselineUpdate -BaselinePath $script:RealBaselinePath -CacheDirectory (Join-Path $TestDrive 'empty-repo') -DryRun } |
            Should -Throw 'No availability cache found; run Update-ModelAvailability.ps1 first.'
    }

    # Scenario: an installed Skill directory has no repository catalog or Git metadata around it.
    # Purpose: keep rejecting installed copies.
    It 'UnitT22_does not treat an installed Skill directory as a repository checkout' {
        $installed = Join-Path $TestDrive 'home/.agents/skills/orchestrate-ai-delivery'
        $null = New-Item -ItemType Directory -Path $installed -Force
        Test-ModelBaselineRepositoryCheckout -SkillDirectory $installed | Should -BeFalse
    }
}

Context 'Baseline reconciliation' {
    BeforeEach {
        $script:CaseRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $script:Baseline = Join-Path $script:CaseRoot 'repo/models.json'
        $script:Cache = Join-Path $script:CaseRoot 'cache'
        $script:Now = [DateTimeOffset]'2026-11-05T10:00:00+08:00'
    }

    # Scenario: two current environments list the same new ID. Purpose: append it once with exact evidence text and stable environment order.
    It 'UnitT10_adds a new codex ID once as unevaluated' {
        Write-TestBaseline -Path $script:Baseline -Models @(New-TestBaselineModel)
        $new = New-TestAvailabilityModel -Id 'new-model' -Status unevaluated -Reason not-in-baseline
        Write-TestCache -Directory $script:Cache -Environment work -Models @($new)
        Write-TestCache -Directory $script:Cache -Environment personal -Models @($new)

        $result = Invoke-ModelBaselineUpdate -BaselinePath $script:Baseline -CacheDirectory $script:Cache -Now $script:Now
        $saved = Get-Content -LiteralPath $script:Baseline -Raw | ConvertFrom-Json
        $added = @($saved.models | Where-Object id -eq 'new-model')
        $result.added | Should -Be @('codex/new-model')
        $added.Count | Should -Be 1
        $added[0].status | Should -Be 'unevaluated'
        $added[0].notes | Should -Be 'listed by codex CLI in personal and work on 2026-11-05; not yet rated'
    }

    # Scenario: only personal has a current missing observation. Purpose: require both environments before removing an ID.
    It 'UnitT20_skips removal when only the personal cache is observed' {
        Write-TestBaseline -Path $script:Baseline -Models @(New-TestBaselineModel -Id 'personal-only')
        Write-TestCache -Directory $script:Cache -Environment personal -Models @(
            New-TestAvailabilityModel -Id personal-only -Status unavailable -Reason not-listed-by-cli)
        $result = Invoke-ModelBaselineUpdate -BaselinePath $script:Baseline -CacheDirectory $script:Cache -Now $script:Now
        $result.status | Should -Be 'unchanged'
        $result.warnings | Should -Contain 'codex: removals skipped; run Update-ModelAvailability.ps1 for both personal and work this week'
        @($result.warnings | Where-Object { $_ -eq 'codex: removals skipped; run Update-ModelAvailability.ps1 for both personal and work this week' }).Count |
            Should -Be 1
        (Get-Content $script:Baseline -Raw | ConvertFrom-Json).models[0].status | Should -Be 'active'
    }

    # Scenario: personal reports an ID missing while work lists it. Purpose: require absence in both current environments.
    It 'UnitT25_keeps an ID absent from personal but listed in work' {
        Write-TestBaseline -Path $script:Baseline -Models @(New-TestBaselineModel -Id 'mixed')
        Write-TestCache -Directory $script:Cache -Environment personal -Models @(
            New-TestAvailabilityModel -Id mixed -Status unavailable -Reason not-listed-by-cli)
        Write-TestCache -Directory $script:Cache -Environment work -Models @(
            New-TestAvailabilityModel -Id mixed -Status available -Reason listed-by-cli)
        $result = Invoke-ModelBaselineUpdate -BaselinePath $script:Baseline -CacheDirectory $script:Cache -Now $script:Now
        $result.status | Should -Be 'unchanged'
        (Get-Content $script:Baseline -Raw | ConvertFrom-Json).models[0].status | Should -Be 'active'
    }

    # Scenario: every current observation lacks a rated model. Purpose: mark unavailable while preserving ratings and evidence.
    It 'UnitT30_marks unanimous absence unavailable and keeps ratings' {
        Write-TestBaseline -Path $script:Baseline -Models @(New-TestBaselineModel -Id 'gone')
        $missing = New-TestAvailabilityModel -Id gone -Status unavailable -Reason not-listed-by-cli
        Write-TestCache -Directory $script:Cache -Environment personal -Models @($missing)
        Write-TestCache -Directory $script:Cache -Environment work -Models @($missing)
        $result = Invoke-ModelBaselineUpdate -BaselinePath $script:Baseline -CacheDirectory $script:Cache -Now $script:Now
        $saved = (Get-Content $script:Baseline -Raw | ConvertFrom-Json).models[0]
        $result.markedUnavailable | Should -Be @('codex/gone')
        $saved.status | Should -Be 'unavailable'
        $saved.capability | Should -Be 3
        $saved.cost | Should -Be 2
        $saved.evidence | Should -Be 'official'
        $saved.notes | Should -Be 'original; not listed by codex CLI on 2026-11-05'
    }

    # Scenario: stale and prior-week observations exist. Purpose: ignore both and emit per-environment warnings.
    It 'UnitT40_ignores stale and last-week caches with warnings' {
        Write-TestBaseline -Path $script:Baseline -Models @(New-TestBaselineModel -Id 'keep')
        $missing = New-TestAvailabilityModel -Id keep -Status unavailable -Reason not-listed-by-cli
        Write-TestCache -Directory $script:Cache -Environment personal -Models @($missing) -Stale $true
        Write-TestCache -Directory $script:Cache -Environment work -Models @($missing) -CheckedUtc '2026-10-25T16:00:00Z'
        $result = Invoke-ModelBaselineUpdate -BaselinePath $script:Baseline -CacheDirectory $script:Cache -Now $script:Now -DryRun
        $result.status | Should -Be 'unchanged'
        $result.warnings | Should -Contain 'personal/codex: cache not current; not used'
        $result.warnings | Should -Contain 'work/codex: cache not current; not used'
    }

    # Scenario: Claude data and protected statuses are present. Purpose: skip Claude and never rewrite excluded/unavailable rows.
    It 'UnitT50_ignores Claude and leaves excluded and unavailable entries untouched' {
        $models = @(
            New-TestBaselineModel -Cli claude -Id claude-one
            New-TestBaselineModel -Id excluded -Status excluded -Capability $null -Cost $null
            New-TestBaselineModel -Id old -Status unavailable
        )
        Write-TestBaseline -Path $script:Baseline -Models $models
        Write-TestCache -Directory $script:Cache -Environment personal -Cli claude -Models @(
            New-TestAvailabilityModel -Cli claude -Id claude-one -Status unavailable -Reason not-listed-by-cli)
        Write-TestCache -Directory $script:Cache -Environment work -Models @(
            New-TestAvailabilityModel -Id excluded -Status unavailable -Reason not-listed-by-cli
            New-TestAvailabilityModel -Id old -Status unavailable -Reason not-listed-by-cli)
        $before = Get-Content -LiteralPath $script:Baseline -Raw
        $result = Invoke-ModelBaselineUpdate -BaselinePath $script:Baseline -CacheDirectory $script:Cache -Now $script:Now
        $result.status | Should -Be 'unchanged'
        (Get-Content -LiteralPath $script:Baseline -Raw) | Should -BeExactly $before
    }

    # Scenario: an unavailable model is listed again. Purpose: require human review instead of automatic activation.
    It 'UnitT60_suggests review when an unavailable model reappears' {
        Write-TestBaseline -Path $script:Baseline -Models @(New-TestBaselineModel -Id returned -Status unavailable)
        Write-TestCache -Directory $script:Cache -Environment personal -Models @(
            New-TestAvailabilityModel -Id returned -Status available -Reason listed-by-cli)
        $result = Invoke-ModelBaselineUpdate -BaselinePath $script:Baseline -CacheDirectory $script:Cache -Now $script:Now -DryRun
        $result.suggestions | Should -Contain 'codex/returned: listed again; review its status'
        $result.status | Should -Be 'unchanged'
    }

    # Scenario: a change is calculated in dry-run mode. Purpose: return the proposal without touching bytes on disk.
    It 'UnitT70_dry run does not write changes' {
        Write-TestBaseline -Path $script:Baseline -Models @(New-TestBaselineModel)
        Write-TestCache -Directory $script:Cache -Environment personal -Models @(
            New-TestAvailabilityModel -Id new -Status unevaluated -Reason not-in-baseline)
        $before = [System.IO.File]::ReadAllBytes($script:Baseline)
        $result = Invoke-ModelBaselineUpdate -BaselinePath $script:Baseline -CacheDirectory $script:Cache -Now $script:Now -DryRun
        $result.status | Should -Be 'changed'
        $result.written | Should -BeFalse
        [System.IO.File]::ReadAllBytes($script:Baseline) | Should -Be $before
    }

    # Scenario: observations imply no edit. Purpose: avoid rewriting an unchanged baseline.
    It 'UnitT80_does not rewrite unchanged input' {
        Write-TestBaseline -Path $script:Baseline -Models @(New-TestBaselineModel -Id present)
        Write-TestCache -Directory $script:Cache -Environment personal -Models @(
            New-TestAvailabilityModel -Id present -Status available -Reason listed-by-cli)
        $before = [System.IO.File]::ReadAllBytes($script:Baseline)
        $result = Invoke-ModelBaselineUpdate -BaselinePath $script:Baseline -CacheDirectory $script:Cache -Now $script:Now
        $result.status | Should -Be 'unchanged'
        $result.written | Should -BeFalse
        [System.IO.File]::ReadAllBytes($script:Baseline) | Should -Be $before
    }
}

Context 'Serialization' {
    # Scenario: the committed baseline is parsed and serialized. Purpose: prevent formatting-only repository churn.
    It 'UnitT10_round trips the committed models json byte identically' {
        # Checkouts may convert line endings; the repository stores LF.
        $raw = [System.IO.File]::ReadAllText($script:RealBaselinePath).Replace("`r`n", "`n")
        $formatted = Format-ModelBaselineJson -Value ($raw | ConvertFrom-Json)
        $formatted | Should -BeExactly $raw
    }
}
}
