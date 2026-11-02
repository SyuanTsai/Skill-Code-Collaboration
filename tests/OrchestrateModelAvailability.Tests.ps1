# SPDX-FileCopyrightText: 2026 SyuanTsai
# SPDX-License-Identifier: Apache-2.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'orchestrate-ai-delivery model availability' {
BeforeAll {
    $script:RepositoryRoot = Split-Path -Parent $PSScriptRoot
    $script:SkillRoot = Join-Path $script:RepositoryRoot 'skills/orchestrate-ai-delivery'
    $script:ScriptPath = Join-Path $script:SkillRoot 'scripts/Update-ModelAvailability.ps1'
    $script:BaselinePath = Join-Path $script:SkillRoot 'references/models.json'
    . $script:ScriptPath -Environment personal
    $script:RealGetClaudeLoginState = ${function:Get-ClaudeLoginState}
    $script:RealGetCopilotAvailableModels = ${function:Get-CopilotAvailableModels}

    $script:Baseline = Get-Content -LiteralPath $script:BaselinePath -Raw | ConvertFrom-Json
    $script:ClaudeIds = @($script:Baseline.models | Where-Object cli -eq 'claude' | ForEach-Object id)
    $script:CodexIds = @($script:Baseline.models | Where-Object cli -eq 'codex' | ForEach-Object id)
    $script:CopilotIds = @($script:Baseline.models | Where-Object cli -eq 'copilot' | ForEach-Object id)

    function Write-TestAvailabilityCache {
        param(
            [Parameter(Mandatory)]
            [string]$Directory,

            [Parameter(Mandatory)]
            [ValidateSet('personal', 'work')]
            [string]$Environment,

            [Parameter(Mandatory)]
            [string]$LastCheckedUtc,

            [object[]]$Models = @(),

            [psobject]$Clis = ([pscustomobject]@{})
        )

        $null = New-Item -ItemType Directory -Path $Directory -Force
        $cache = [pscustomobject][ordered]@{
            schemaVersion  = 1
            status         = 'updated'
            environment    = $Environment
            lastCheckedUtc = $LastCheckedUtc
            warnings       = @()
            suggestions    = @()
            clis           = $Clis
            models         = @($Models)
        }
        $path = Join-Path $Directory "model-availability.$Environment.json"
        Set-Content -LiteralPath $path -Value ($cache | ConvertTo-Json -Depth 6) -Encoding utf8
        return $path
    }

    function New-TestCliStates {
        param(
            [Parameter(Mandatory)]
            [string]$CheckedUtc,

            [string]$StaleCli
        )

        $states = [ordered]@{}
        foreach ($cliName in @('claude', 'codex', 'copilot')) {
            $states[$cliName] = [pscustomobject][ordered]@{
                stale      = $cliName -eq $StaleCli
                checkedUtc = $CheckedUtc
            }
        }
        return [pscustomobject]$states
    }
}

BeforeEach {
    Mock Get-Command {
        [pscustomobject]@{ Name = $Name }
    } -ParameterFilter { $Name -in @('claude', 'codex', 'copilot') }
    Mock Get-ClaudeLoginState { $true }
    Mock Get-CodexAvailableModels { @($script:CodexIds) }
    Mock Get-CopilotAvailableModels { @($script:CopilotIds) }
}

Context 'Weekly availability trigger' {
    It 'treats a cache checked exactly at Taipei Monday 00:00 as fresh' {
        $cacheDirectory = Join-Path $TestDrive 'monday-exact'
        $mondayUtc = '2026-11-01T16:00:00.0000000Z'
        $null = Write-TestAvailabilityCache `
            -Directory $cacheDirectory `
            -Environment personal `
            -LastCheckedUtc $mondayUtc `
            -Clis (New-TestCliStates -CheckedUtc $mondayUtc)

        $result = Invoke-ModelAvailabilityUpdate `
            -Environment personal `
            -CacheDirectory $cacheDirectory `
            -Now ([DateTimeOffset]'2026-11-02T00:00:00+08:00')

        $result.status | Should -Be 'fresh'
        Should -Invoke Get-ClaudeLoginState -Times 0 -Exactly
        Should -Invoke Get-CodexAvailableModels -Times 0 -Exactly
        Should -Invoke Get-CopilotAvailableModels -Times 0 -Exactly
    }

    It 'uses the preceding Monday for Sunday 23:59 in Taipei' {
        $cacheDirectory = Join-Path $TestDrive 'sunday-boundary'
        $null = Write-TestAvailabilityCache `
            -Directory $cacheDirectory `
            -Environment personal `
            -LastCheckedUtc '2026-10-25T16:00:00.0000000Z' `
            -Clis (New-TestCliStates -CheckedUtc '2026-10-25T16:00:00.0000000Z')

        $result = Invoke-ModelAvailabilityUpdate `
            -Environment personal `
            -CacheDirectory $cacheDirectory `
            -Now ([DateTimeOffset]'2026-11-01T23:59:00+08:00')

        $result.status | Should -Be 'fresh'
        Should -Invoke Get-CodexAvailableModels -Times 0 -Exactly
    }

    It 'refreshes a pre-boundary cache when UTC is Sunday but Taipei is Monday' {
        $cacheDirectory = Join-Path $TestDrive 'utc-sunday'
        $null = Write-TestAvailabilityCache `
            -Directory $cacheDirectory `
            -Environment personal `
            -LastCheckedUtc '2026-11-01T15:59:00.0000000Z' `
            -Clis (New-TestCliStates -CheckedUtc '2026-11-01T15:59:00.0000000Z')

        $result = Invoke-ModelAvailabilityUpdate `
            -Environment personal `
            -CacheDirectory $cacheDirectory `
            -Now ([DateTimeOffset]'2026-11-01T16:30:00Z')

        $result.status | Should -Be 'updated'
        Should -Invoke Get-ClaudeLoginState -Times 1 -Exactly
        Should -Invoke Get-CodexAvailableModels -Times 1 -Exactly
        Should -Invoke Get-CopilotAvailableModels -Times 1 -Exactly
    }

    It 'retries a cache checked this week when any CLI state is stale' {
        $cacheDirectory = Join-Path $TestDrive 'stale-this-week'
        $null = Write-TestAvailabilityCache `
            -Directory $cacheDirectory `
            -Environment personal `
            -LastCheckedUtc '2026-11-01T16:30:00.0000000Z' `
            -Clis (New-TestCliStates -CheckedUtc '2026-11-01T16:30:00.0000000Z' -StaleCli codex)

        $result = Invoke-ModelAvailabilityUpdate `
            -Environment personal `
            -CacheDirectory $cacheDirectory `
            -Cli codex `
            -Now ([DateTimeOffset]'2026-11-02T01:00:00+08:00')

        $result.status | Should -Be 'updated'
        Should -Invoke Get-CodexAvailableModels -Times 1 -Exactly
    }

    It 're-probes every CLI when carried-over CLI states were checked last week' {
        $cacheDirectory = Join-Path $TestDrive 'mixed-cli-freshness'
        $thisWeek = '2026-11-01T16:30:00.0000000Z'
        $lastWeek = '2026-10-25T16:00:00.0000000Z'
        $null = Write-TestAvailabilityCache `
            -Directory $cacheDirectory `
            -Environment personal `
            -LastCheckedUtc $thisWeek `
            -Clis ([pscustomobject][ordered]@{
                claude  = [pscustomobject]@{ stale = $false; checkedUtc = $lastWeek }
                codex   = [pscustomobject]@{ stale = $false; checkedUtc = $thisWeek }
                copilot = [pscustomobject]@{ stale = $false; checkedUtc = $lastWeek }
            })

        $result = Invoke-ModelAvailabilityUpdate `
            -Environment personal `
            -CacheDirectory $cacheDirectory `
            -Now ([DateTimeOffset]'2026-11-02T01:00:00+08:00')

        $result.status | Should -Be 'updated'
        Should -Invoke Get-ClaudeLoginState -Times 1 -Exactly
        Should -Invoke Get-CodexAvailableModels -Times 1 -Exactly
        Should -Invoke Get-CopilotAvailableModels -Times 1 -Exactly
    }

    It 'returns fresh when every CLI state was checked this week and is not stale' {
        $cacheDirectory = Join-Path $TestDrive 'all-cli-fresh'
        $thisWeek = '2026-11-01T16:30:00.0000000Z'
        $null = Write-TestAvailabilityCache `
            -Directory $cacheDirectory `
            -Environment personal `
            -LastCheckedUtc $thisWeek `
            -Clis (New-TestCliStates -CheckedUtc $thisWeek)

        $result = Invoke-ModelAvailabilityUpdate `
            -Environment personal `
            -CacheDirectory $cacheDirectory `
            -Now ([DateTimeOffset]'2026-11-02T01:00:00+08:00')

        $result.status | Should -Be 'fresh'
        Should -Invoke Get-ClaudeLoginState -Times 0 -Exactly
        Should -Invoke Get-CodexAvailableModels -Times 0 -Exactly
        Should -Invoke Get-CopilotAvailableModels -Times 0 -Exactly
    }
}

Context 'CLI output parsing' {
    It 'uses valid Claude logged-out JSON even when auth status exits non-zero' {
        Mock Invoke-ClaudeAuthStatus {
            [pscustomobject]@{
                Lines    = @('{"loggedIn":false,"subscriptionType":"none"}')
                ExitCode = 1
            }
        }

        (& $script:RealGetClaudeLoginState) | Should -Be $false
        Should -Invoke Invoke-ClaudeAuthStatus -Times 1 -Exactly
    }

    It 'extracts only model IDs from the Copilot model config list' {
        $lines = @(
            '  `model`: AI model to use for Copilot CLI; can be changed with /model command or --model flag option.'
            '    - "claude-sonnet-5"'
            '    - "gpt-5.6-luna"'
            ''
            '  `contextTier`: context window tier for tiered-pricing models (e.g., "default" or "long_context").'
            '    - "default"'
            '    - "long_context"'
        )

        @(Get-CopilotConfigModelIds -Lines $lines) | Should -Be @(
            'claude-sonnet-5'
            'gpt-5.6-luna'
        )
    }
}

Context 'Selection safety' {
    It 'does not select discovered or baseline unevaluated models' {
        $cacheDirectory = Join-Path $TestDrive 'unevaluated'
        Mock Get-CodexAvailableModels { @($script:CodexIds) + 'gpt-new-candidate' }

        $result = Invoke-ModelAvailabilityUpdate `
            -Environment personal `
            -CacheDirectory $cacheDirectory `
            -Cli codex `
            -Force `
            -Now ([DateTimeOffset]'2026-11-02T01:00:00+08:00')

        $discovered = @($result.models | Where-Object id -eq 'gpt-new-candidate')
        $discovered.Count | Should -Be 1
        $discovered[0].status | Should -Be 'unevaluated'
        $discovered[0].selectable | Should -Be $false
        @($result.suggestions | Where-Object { $_ -match 'gpt-new-candidate.*pull request' }).Count | Should -Be 1

        $baselineUnevaluated = @($result.models | Where-Object id -eq 'gpt-reserve')
        $baselineUnevaluated.Count | Should -Be 1
        $baselineUnevaluated[0].status | Should -Be 'available'
        $baselineUnevaluated[0].selectable | Should -Be $false
    }

    It 'forces a fresh cache to re-check a model that disappeared' {
        $cacheDirectory = Join-Path $TestDrive 'forced'
        $cachedModel = [pscustomobject]@{
            cli = 'codex'; id = 'gpt-5.6-luna'; family = 'openai'
            status = 'available'; selectable = $true; reason = 'listed-by-cli'
        }
        $null = Write-TestAvailabilityCache `
            -Directory $cacheDirectory `
            -Environment personal `
            -LastCheckedUtc '2026-11-01T16:30:00.0000000Z' `
            -Models @($cachedModel) `
            -Clis ([pscustomobject]@{ codex = [pscustomobject]@{ stale = $false } })
        Mock Get-CodexAvailableModels { @($script:CodexIds | Where-Object { $_ -ne 'gpt-5.6-luna' }) }

        $result = Invoke-ModelAvailabilityUpdate `
            -Environment personal `
            -CacheDirectory $cacheDirectory `
            -Cli codex `
            -Force `
            -Now ([DateTimeOffset]'2026-11-02T01:00:00+08:00')

        $luna = @($result.models | Where-Object id -eq 'gpt-5.6-luna')[0]
        $result.status | Should -Be 'updated'
        $luna.status | Should -Be 'unavailable'
        $luna.selectable | Should -Be $false
        Should -Invoke Get-CodexAvailableModels -Times 1 -Exactly
    }

    It 'records a Copilot model discovered from help config as unevaluated' {
        $cacheDirectory = Join-Path $TestDrive 'copilot-discovered'
        Mock Invoke-CopilotHelpConfig {
            [pscustomobject]@{ Lines = @('mocked'); ExitCode = 0 }
        }
        Mock Get-CopilotConfigModelIds { 'copilot-new-candidate' }
        Mock Test-CopilotCandidate { $true }
        Mock Get-CopilotAvailableModels {
            & $script:RealGetCopilotAvailableModels -Candidates $Candidates
        }

        $result = Invoke-ModelAvailabilityUpdate `
            -Environment personal `
            -CacheDirectory $cacheDirectory `
            -Cli copilot `
            -Force `
            -Now ([DateTimeOffset]'2026-11-02T01:00:00+08:00')

        $discovered = @($result.models | Where-Object id -eq 'copilot-new-candidate')
        $discovered.Count | Should -Be 1
        $discovered[0].status | Should -Be 'unevaluated'
        $discovered[0].selectable | Should -Be $false
        @($result.suggestions | Where-Object { $_ -match 'copilot-new-candidate.*pull request' }).Count | Should -Be 1
        Should -Invoke Get-CopilotConfigModelIds -Times 1 -Exactly
        Should -Invoke Test-CopilotCandidate -ParameterFilter {
            $ModelId -eq 'copilot-new-candidate'
        } -Times 1 -Exactly
    }
}

Context 'Probe failure handling' {
    It 'keeps the prior CLI entries and reports offline without throwing' {
        $cacheDirectory = Join-Path $TestDrive 'offline'
        $cachedModel = [pscustomobject]@{
            cli = 'codex'; id = 'gpt-5.6-luna'; family = 'openai'
            status = 'available'; selectable = $true; reason = 'listed-by-cli'
        }
        $null = Write-TestAvailabilityCache `
            -Directory $cacheDirectory `
            -Environment personal `
            -LastCheckedUtc '2026-10-25T16:00:00.0000000Z' `
            -Models @($cachedModel) `
            -Clis ([pscustomobject]@{ codex = [pscustomobject]@{ stale = $false } })
        Mock Get-CodexAvailableModels { throw 'network unavailable' }

        {
            $script:OfflineResult = Invoke-ModelAvailabilityUpdate `
                -Environment personal `
                -CacheDirectory $cacheDirectory `
                -Cli codex `
                -Force `
                -Now ([DateTimeOffset]'2026-11-02T01:00:00+08:00')
        } | Should -Not -Throw

        $script:OfflineResult.status | Should -Be 'offline'
        $script:OfflineResult.clis.codex.stale | Should -Be $true
        @($script:OfflineResult.warnings | Where-Object { $_ -match '^codex: availability not updated' }).Count | Should -Be 1
        $kept = @($script:OfflineResult.models | Where-Object id -eq 'gpt-5.6-luna')[0]
        $kept.status | Should -Be 'available'
        $kept.selectable | Should -Be $true
    }

    It 'reports partial when one of multiple selected CLI probes fails' {
        $cacheDirectory = Join-Path $TestDrive 'partial'
        Mock Get-CodexAvailableModels { throw 'unexpected output' }

        $result = Invoke-ModelAvailabilityUpdate `
            -Environment personal `
            -CacheDirectory $cacheDirectory `
            -Cli @('codex', 'copilot') `
            -Force `
            -Now ([DateTimeOffset]'2026-11-02T01:00:00+08:00')

        $result.status | Should -Be 'partial'
        $result.clis.codex.stale | Should -Be $true
        $result.clis.copilot.stale | Should -Be $false
        @($result.models | Where-Object { $_.cli -eq 'codex' -and $_.status -eq 'unknown' }).Count | Should -Be $script:CodexIds.Count
    }
}

Context 'Cache isolation and safety' {
    It 'separates personal and work caches and does not reuse another environment' {
        $cacheDirectory = Join-Path $TestDrive 'environments'
        $personal = Invoke-ModelAvailabilityUpdate `
            -Environment personal `
            -CacheDirectory $cacheDirectory `
            -Cli codex `
            -Force `
            -Now ([DateTimeOffset]'2026-11-02T01:00:00+08:00')
        Mock Get-CodexAvailableModels { throw 'network unavailable' }
        $work = Invoke-ModelAvailabilityUpdate `
            -Environment work `
            -CacheDirectory $cacheDirectory `
            -Cli codex `
            -Force `
            -Now ([DateTimeOffset]'2026-11-02T01:01:00+08:00')

        (Test-Path -LiteralPath (Join-Path $cacheDirectory 'model-availability.personal.json')) | Should -Be $true
        (Test-Path -LiteralPath (Join-Path $cacheDirectory 'model-availability.work.json')) | Should -Be $true
        @($personal.models | Where-Object { $_.status -eq 'available' }).Count | Should -BeGreaterThan 0
        @($work.models | Where-Object { $_.status -eq 'unknown' }).Count | Should -Be $script:CodexIds.Count
    }

    It 'rejects a cache directory inside the Skill directory' {
        $unsafeDirectory = Join-Path $script:SkillRoot 'local-cache-for-test'

        {
            Invoke-ModelAvailabilityUpdate `
                -Environment personal `
                -CacheDirectory $unsafeDirectory `
                -Cli codex `
                -Force
        } | Should -Throw '*must be outside*'
    }
}

Context 'Baseline integrity' {
    It 'has valid unique model entries and rating rules' {
        { Get-Content -LiteralPath $script:BaselinePath -Raw | ConvertFrom-Json } | Should -Not -Throw
        $baseline = Get-Content -LiteralPath $script:BaselinePath -Raw | ConvertFrom-Json
        $baseline.schemaVersion | Should -Be 1

        foreach ($entry in $baseline.models) {
            foreach ($field in @('cli', 'id', 'family', 'capability', 'cost', 'status', 'evidence', 'notes')) {
                @($entry.PSObject.Properties.Name) -contains $field | Should -Be $true
            }
            $entry.status | Should -BeIn @('active', 'unevaluated', 'excluded')
            $entry.evidence | Should -BeIn @('official', 'measured', 'inferred')

            if ($entry.status -eq 'active') {
                $entry.capability | Should -BeIn @(1, 2, 3, 4)
                $entry.cost | Should -BeIn @(1, 2, 3, 4)
            }
            else {
                $entry.capability | Should -BeNullOrEmpty
                $entry.cost | Should -BeNullOrEmpty
            }
        }

        $duplicates = @($baseline.models | Group-Object cli, id | Where-Object Count -gt 1)
        $duplicates.Count | Should -Be 0
        @($baseline.efforts.claude) | Should -Be @('low', 'medium', 'high', 'xhigh', 'max')
        @($baseline.efforts.codex) | Should -Be @('low', 'medium', 'high', 'xhigh', 'max', 'ultra')
        @($baseline.efforts.copilot) | Should -Be @('none', 'minimal', 'low', 'medium', 'high', 'xhigh', 'max')
    }
}

Context 'CLI state reasons' {
    It 'marks all baseline models unavailable when a CLI is missing' {
        $cacheDirectory = Join-Path $TestDrive 'missing-cli'
        Mock Get-Command { $null } -ParameterFilter { $Name -eq 'codex' }

        $result = Invoke-ModelAvailabilityUpdate `
            -Environment personal `
            -CacheDirectory $cacheDirectory `
            -Cli codex `
            -Force `
            -Now ([DateTimeOffset]'2026-11-02T01:00:00+08:00')

        @($result.models).Count | Should -Be $script:CodexIds.Count
        @($result.models | Where-Object reason -eq 'cli-not-found').Count | Should -Be $script:CodexIds.Count
        @($result.models | Where-Object selectable -eq $true).Count | Should -Be 0
        Should -Invoke Get-CodexAvailableModels -Times 0 -Exactly
    }

    It 'marks Claude models unavailable when the CLI is not logged in' {
        $cacheDirectory = Join-Path $TestDrive 'claude-login'
        Mock Get-ClaudeLoginState { $false }

        $result = Invoke-ModelAvailabilityUpdate `
            -Environment work `
            -CacheDirectory $cacheDirectory `
            -Cli claude `
            -Force `
            -Now ([DateTimeOffset]'2026-11-02T01:00:00+08:00')

        @($result.models).Count | Should -Be $script:ClaudeIds.Count
        @($result.models | Where-Object reason -eq 'cli-not-logged-in').Count | Should -Be $script:ClaudeIds.Count
        @($result.models | Where-Object selectable -eq $true).Count | Should -Be 0
        Should -Invoke Get-ClaudeLoginState -Times 1 -Exactly
    }

    It 'reports logged-out Claude as unavailable without a warning or stale state' {
        $cacheDirectory = Join-Path $TestDrive 'claude-logged-out-nonzero'
        Mock Invoke-ClaudeAuthStatus {
            [pscustomobject]@{
                Lines    = @('{"loggedIn":false,"subscriptionType":"none"}')
                ExitCode = 1
            }
        }
        Mock Get-ClaudeLoginState { & $script:RealGetClaudeLoginState }

        $result = Invoke-ModelAvailabilityUpdate `
            -Environment work `
            -CacheDirectory $cacheDirectory `
            -Cli claude `
            -Force `
            -Now ([DateTimeOffset]'2026-11-02T01:00:00+08:00')

        @($result.models | Where-Object reason -eq 'cli-not-logged-in').Count | Should -Be $script:ClaudeIds.Count
        @($result.models | Where-Object status -eq 'unavailable').Count | Should -Be $script:ClaudeIds.Count
        @($result.warnings).Count | Should -Be 0
        $result.clis.claude.stale | Should -Be $false
        Should -Invoke Invoke-ClaudeAuthStatus -Times 1 -Exactly
    }
}
}
