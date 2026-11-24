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
    $script:RealGetJunieAvailableModels = ${function:Get-JunieAvailableModels}
    $script:RealGetCopilotAvailableModels = ${function:Get-CopilotAvailableModels}

    $script:Baseline = Get-Content -LiteralPath $script:BaselinePath -Raw | ConvertFrom-Json
    $script:BaselineIdentity = Get-ModelBaselineIdentity -Baseline $script:Baseline
    $script:ClaudeIds = @($script:Baseline.models | Where-Object cli -eq 'claude' | ForEach-Object id)
    $script:CodexIds = @($script:Baseline.models | Where-Object cli -eq 'codex' | ForEach-Object id)
    $script:JunieIds = @($script:Baseline.models | Where-Object cli -eq 'junie' | ForEach-Object id)
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

            [psobject]$Clis = ([pscustomobject]@{}),

            [AllowNull()]
            [string]$BaselineSha256 = $script:BaselineIdentity,

            [switch]$OmitBaselineSha256,

            [string[]]$Warnings = @()
        )

        $null = New-Item -ItemType Directory -Path $Directory -Force
        $cache = [pscustomobject][ordered]@{
            schemaVersion  = 1
            status         = 'updated'
            environment    = $Environment
            baselineSource = 'explicit'
            lastCheckedUtc = $LastCheckedUtc
            warnings       = $Warnings
            suggestions    = @()
            clis           = $Clis
            models         = @($Models)
        }
        if (-not $OmitBaselineSha256) {
            $cache | Add-Member -NotePropertyName baselineSha256 -NotePropertyValue $BaselineSha256
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
        foreach ($cliName in @('claude', 'codex', 'copilot', 'junie')) {
            $states[$cliName] = [pscustomobject][ordered]@{
                stale      = $cliName -eq $StaleCli
                checkedUtc = $CheckedUtc
            }
        }
        return [pscustomobject]$states
    }
}

BeforeEach {
    Mock Invoke-ModelBaselineDownload { $script:Baseline }
    Mock Get-Command {
        [pscustomobject]@{ Name = $Name }
    } -ParameterFilter { $Name -in @('claude', 'codex', 'copilot', 'junie') }
    Mock Get-ClaudeLoginState { $true }
    Mock Get-CodexAvailableModels { @($script:CodexIds) }
    Mock Get-CopilotAvailableModels { @($script:CopilotIds) }
    Mock Get-JunieAvailableModels { @($script:JunieIds) }
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
        Should -Invoke Get-JunieAvailableModels -Times 0 -Exactly
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
        Should -Invoke Get-JunieAvailableModels -Times 1 -Exactly
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
                junie   = [pscustomobject]@{ stale = $false; checkedUtc = $thisWeek }
            })

        $result = Invoke-ModelAvailabilityUpdate `
            -Environment personal `
            -CacheDirectory $cacheDirectory `
            -Now ([DateTimeOffset]'2026-11-02T01:00:00+08:00')

        $result.status | Should -Be 'updated'
        Should -Invoke Get-ClaudeLoginState -Times 1 -Exactly
        Should -Invoke Get-CodexAvailableModels -Times 1 -Exactly
        Should -Invoke Get-CopilotAvailableModels -Times 1 -Exactly
        Should -Invoke Get-JunieAvailableModels -Times 1 -Exactly
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
        Should -Invoke Get-JunieAvailableModels -Times 0 -Exactly
    }

    # Scenario: all CLI states and the baseline identity are current. Purpose: reuse a cache only for the baseline it describes.
    It 'UnitT70_returns fresh without probing when the baseline identity matches' {
        $cacheDirectory = Join-Path $TestDrive 'matching-baseline'
        $thisWeek = '2026-11-01T16:30:00.0000000Z'
        $null = Write-TestAvailabilityCache -Directory $cacheDirectory -Environment personal `
            -LastCheckedUtc $thisWeek -Clis (New-TestCliStates -CheckedUtc $thisWeek)

        $result = Invoke-ModelAvailabilityUpdate -Environment personal -CacheDirectory $cacheDirectory `
            -BaselinePath $script:BaselinePath -Now ([DateTimeOffset]'2026-11-02T01:00:00+08:00')

        $result.status | Should -Be 'fresh'
        $result.baselineSha256 | Should -Be $script:BaselineIdentity
        Should -Invoke Get-ClaudeLoginState -Times 0 -Exactly
        Should -Invoke Get-CodexAvailableModels -Times 0 -Exactly
        Should -Invoke Get-CopilotAvailableModels -Times 0 -Exactly
        Should -Invoke Get-JunieAvailableModels -Times 0 -Exactly
    }

    # Scenario: a forced single-CLI refresh has the current baseline identity. Purpose: retain the caller's narrow probe scope.
    It 'UnitT75_probes only the selected CLI when the baseline identity matches' {
        $cacheDirectory = Join-Path $TestDrive 'matching-baseline-forced-cli'
        $thisWeek = '2026-11-01T16:30:00.0000000Z'
        $null = Write-TestAvailabilityCache -Directory $cacheDirectory -Environment personal `
            -LastCheckedUtc $thisWeek -Clis (New-TestCliStates -CheckedUtc $thisWeek)

        $result = Invoke-ModelAvailabilityUpdate -Environment personal -CacheDirectory $cacheDirectory `
            -BaselinePath $script:BaselinePath -Cli codex -Force -Now ([DateTimeOffset]'2026-11-02T01:00:00+08:00')

        $result.baselineSha256 | Should -Be $script:BaselineIdentity
        Should -Invoke Get-ClaudeLoginState -Times 0 -Exactly
        Should -Invoke Get-CodexAvailableModels -Times 1 -Exactly
        Should -Invoke Get-CopilotAvailableModels -Times 0 -Exactly
        Should -Invoke Get-JunieAvailableModels -Times 0 -Exactly
    }

    # Scenario: the cache belongs to a different baseline. Purpose: re-probe and stamp the newly resolved identity.
    It 'UnitT80_reprobes every CLI when a forced partial refresh has a different baseline identity' {
        $cacheDirectory = Join-Path $TestDrive 'different-baseline'
        $thisWeek = '2026-11-01T16:30:00.0000000Z'
        $oldModels = @(
            [pscustomobject]@{ cli = 'claude'; id = 'old-claude'; family = 'anthropic'; status = 'unavailable'; selectable = $false; reason = 'old-baseline' }
            [pscustomobject]@{ cli = 'codex'; id = 'old-codex'; family = 'openai'; status = 'unavailable'; selectable = $false; reason = 'old-baseline' }
            [pscustomobject]@{ cli = 'copilot'; id = 'old-copilot'; family = 'openai'; status = 'unavailable'; selectable = $false; reason = 'old-baseline' }
        )
        $null = Write-TestAvailabilityCache -Directory $cacheDirectory -Environment personal `
            -LastCheckedUtc $thisWeek -Models $oldModels -Clis (New-TestCliStates -CheckedUtc $thisWeek) -BaselineSha256 ('0' * 64)

        $result = Invoke-ModelAvailabilityUpdate -Environment personal -CacheDirectory $cacheDirectory `
            -BaselinePath $script:BaselinePath -Cli codex -Force -Now ([DateTimeOffset]'2026-11-02T01:00:00+08:00')

        $result.status | Should -Be 'updated'
        $result.baselineSha256 | Should -Be $script:BaselineIdentity
        @($result.models | Where-Object reason -eq 'old-baseline').Count | Should -Be 0
        Should -Invoke Get-ClaudeLoginState -Times 1 -Exactly
        Should -Invoke Get-CodexAvailableModels -Times 1 -Exactly
        Should -Invoke Get-CopilotAvailableModels -Times 1 -Exactly
        Should -Invoke Get-JunieAvailableModels -Times 1 -Exactly
    }

    # Scenario: a legacy cache has no baseline identity. Purpose: re-probe rather than trusting an unbound cache.
    It 'UnitT90_reprobes a fresh cache with no baseline identity' {
        $cacheDirectory = Join-Path $TestDrive 'missing-baseline-identity'
        $thisWeek = '2026-11-01T16:30:00.0000000Z'
        $null = Write-TestAvailabilityCache -Directory $cacheDirectory -Environment personal `
            -LastCheckedUtc $thisWeek -Clis (New-TestCliStates -CheckedUtc $thisWeek) -OmitBaselineSha256

        $result = Invoke-ModelAvailabilityUpdate -Environment personal -CacheDirectory $cacheDirectory `
            -BaselinePath $script:BaselinePath -Cli codex -Now ([DateTimeOffset]'2026-11-02T01:00:00+08:00')

        $result.status | Should -Be 'updated'
        $result.baselineSha256 | Should -Be $script:BaselineIdentity
        Should -Invoke Get-CodexAvailableModels -Times 1 -Exactly
    }
}

Context 'CLI output parsing' {
    BeforeAll {
        function Invoke-TestCopilotProbeLineVerdict {
            param([string]$Line)

            $helper = ${function:Test-CopilotCandidate}.Ast.Find({
                param($node)
                $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
                    $node.Name -eq 'Get-CopilotProbeLineVerdict'
            }, $true)
            if ($null -eq $helper) { throw 'Copilot probe line verdict helper not found.' }
            & ($helper.Body.GetScriptBlock()) -Line $Line
        }
    }

    # Scenario: Copilot reports an unavailable model as a session.error JSON event.
    # Purpose: classify the event as unavailable.
    It 'UnitT20_classifies a Copilot unavailable session error' {
        $line = '{"type":"session.error","data":{"errorType":"query","message":"Execution failed: Model \"gpt-5.6-terra\" is not available."},"id":"example","timestamp":"example","parentId":"example"}'
        Invoke-TestCopilotProbeLineVerdict -Line $line | Should -Be 'unavailable'
    }

    # Scenario: Copilot emits an assistant turn start event.
    # Purpose: retain the existing available-model classification.
    It 'UnitT30_classifies a Copilot assistant turn as available' {
        Invoke-TestCopilotProbeLineVerdict -Line '{"type":"assistant.turn_start"}' | Should -Be 'available'
    }

    # Scenario: Copilot emits unrelated session events.
    # Purpose: leave their availability undecided.
    It 'UnitT40_ignores unrelated Copilot session events' {
        Invoke-TestCopilotProbeLineVerdict -Line '{"type":"session.warning"}' | Should -BeNullOrEmpty
        Invoke-TestCopilotProbeLineVerdict -Line '{"type":"session.start"}' | Should -BeNullOrEmpty
    }

    # Scenario: Copilot emits a session error for a rate limit.
    # Purpose: avoid classifying unrelated errors as unavailable models.
    It 'UnitT50_ignores other Copilot session errors' {
        Invoke-TestCopilotProbeLineVerdict -Line '{"type":"session.error","data":{"message":"Rate limit exceeded"}}' | Should -BeNullOrEmpty
    }

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

    # Scenario: Junie emits a startup log line followed by a JSON catalog.
    # Purpose: extract model IDs without treating the startup log as catalog data.
    It 'UnitT10_parses Junie model IDs after a startup log' {
        Mock Invoke-JunieListModels {
            [pscustomobject]@{
                Lines = @('Junie 1.0 (pid=123): log file: junie.log', '{', '  "models": [{ "id": "one", "name": "First" }, { "id": "two" }]', '}')
                ExitCode = 0
            }
        }

        @(& $script:RealGetJunieAvailableModels) | Should -Be @('one', 'two')
        Should -Invoke Invoke-JunieListModels -Times 1 -Exactly
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

Context 'Junie availability' {
    # Scenario: Junie returns a startup log without a JSON payload while Codex succeeds.
    # Purpose: isolate Junie probe failures and report a safe warning.
    It 'UnitT10_marks only Junie stale when its output has no JSON' {
        Mock Invoke-JunieListModels { [pscustomobject]@{ Lines = @('Junie startup log'); ExitCode = 0 } }
        Mock Get-JunieAvailableModels { & $script:RealGetJunieAvailableModels }

        { & $script:RealGetJunieAvailableModels } | Should -Throw '*unexpected output*'
        $result = Invoke-ModelAvailabilityUpdate -Environment personal -BaselinePath $script:BaselinePath `
            -CacheDirectory (Join-Path $TestDrive 'junie-bad-output') -Cli junie, codex

        $result.status | Should -Be 'partial'
        $result.clis.junie.stale | Should -BeTrue
        $result.clis.codex.stale | Should -BeFalse
        $result.warnings | Should -Contain 'junie: availability not updated (unexpected output)'
    }

    # Scenario: Junie lists a catalog ID absent from the baseline, including a duplicate.
    # Purpose: require review before selection and count the new ID only once.
    It 'UnitT20_reports a new Junie model as unevaluated' {
        Mock Invoke-JunieListModels {
            [pscustomobject]@{
                Lines = @('{"models":[{"id":"gpt-6.1-terra"},{"id":"new-junie"},{"id":"new-junie"}]}')
                ExitCode = 0
            }
        }
        Mock Get-JunieAvailableModels { & $script:RealGetJunieAvailableModels }
        $result = Invoke-ModelAvailabilityUpdate -Environment personal -BaselinePath $script:BaselinePath `
            -CacheDirectory (Join-Path $TestDrive 'junie-new-model') -Cli junie
        $newModel = $result.models | Where-Object id -eq 'new-junie'

        $newModel.status | Should -Be 'unevaluated'
        $newModel.reason | Should -Be 'not-in-baseline'
        $newModel.selectable | Should -BeFalse
        $newModel.reviewedOn | Should -BeNullOrEmpty
        $newModel.reviewOverdue | Should -BeFalse
        ($result.models | Where-Object id -eq 'gpt-6.1-terra').reason | Should -Be 'listed-by-cli'
        ($result.models | Where-Object id -eq 'gpt-6.2-astra').reason | Should -Be 'not-listed-by-cli'
        @($result.review.unevaluated | Where-Object { $_.cli -eq 'junie' -and $_.id -eq 'new-junie' }).Count | Should -Be 1
    }
}

Context 'Rating review' {
    BeforeEach {
        $script:ReviewFixturePath = Join-Path $TestDrive 'review-fixture.json'
        $fixture = [pscustomobject][ordered]@{
            schemaVersion = 2
            reviewMaxAgeDays = 30
            models = @(
                [pscustomobject]@{ cli = 'codex'; id = 'old'; family = 'openai'; status = 'active'; reviewedOn = '2026-11-01'; capability = 3; cost = 2; evidence = 'official'; notes = '' }
                [pscustomobject]@{ cli = 'codex'; id = 'boundary'; family = 'openai'; status = 'active'; reviewedOn = '2026-11-02'; capability = 3; cost = 2; evidence = 'official'; notes = '' }
                [pscustomobject]@{ cli = 'codex'; id = 'unrated'; family = 'openai'; status = 'unevaluated'; reviewedOn = '2026-11-01'; capability = $null; cost = $null; evidence = 'measured'; notes = '' }
            )
            efforts = $script:Baseline.efforts
        }
        Set-Content -LiteralPath $script:ReviewFixturePath -Value ($fixture | ConvertTo-Json -Depth 6)
        Mock Get-CodexAvailableModels { @('old', 'boundary', 'unrated') }
    }

    # Scenario: two active ratings were reviewed 31 and 30 days ago.
    # Purpose: enforce a strict greater-than threshold without changing selectability.
    It 'UnitT10_flags only active ratings older than 30 days' {
        $result = Invoke-ModelAvailabilityUpdate -Environment personal -BaselinePath $script:ReviewFixturePath `
            -CacheDirectory (Join-Path $TestDrive 'review-overdue') -Cli codex -Now ([DateTimeOffset]'2026-12-02T10:00:00+08:00')

        $result.review.maxAgeDays | Should -Be 30
        @($result.review.overdue.id) | Should -Be @('old')
        $result.review.overdue[0].ageDays | Should -Be 31
        $old = $result.models | Where-Object id -eq 'old'
        $old.reviewedOn | Should -Be '2026-11-01'
        $old.reviewOverdue | Should -BeTrue
        $old.selectable | Should -BeTrue
        ($result.models | Where-Object id -eq 'boundary').reviewOverdue | Should -BeFalse
        ($result.models | Where-Object id -eq 'unrated').reviewOverdue | Should -BeFalse
        $result.warnings | Should -Contain 'review: codex/old rating last reviewed 2026-11-01 (31 days ago); re-rate it before relying on it'
        $result.warnings | Should -Contain 'review: 1 unevaluated models; rate them and update references/models.json by pull request'
    }

    # Scenario: Taipei has reached December 2 while UTC is still December 1.
    # Purpose: use the Taipei calendar day to age ratings.
    It 'UnitT20_calculates age across the Taipei date boundary' {
        $baseline = Get-Content -LiteralPath $script:ReviewFixturePath -Raw | ConvertFrom-Json
        $result = Get-ModelReviewStatus -Baseline $baseline -Now ([DateTimeOffset]'2026-12-01T16:00:00Z')

        @($result.overdue.id) | Should -Be @('old')
        $result.overdue[0].ageDays | Should -Be 31
    }

    # Scenario: the cache was written on the 30-day boundary and is still fresh one day later.
    # Purpose: replace outdated review warnings and flags without probing again.
    It 'UnitT30_recalculates review data from a fresh cache' {
        $cacheDirectory = Join-Path $TestDrive 'review-fresh'
        $lastCheckedUtc = '2026-12-01T02:00:00Z'
        $baseline = Get-Content -LiteralPath $script:ReviewFixturePath -Raw | ConvertFrom-Json
        $cachedModels = @(
            [pscustomobject]@{ cli = 'codex'; id = 'old'; status = 'available'; reason = 'listed-by-cli'; reviewedOn = '2026-11-01'; reviewOverdue = $false }
            [pscustomobject]@{ cli = 'codex'; id = 'discovered'; status = 'unevaluated'; reason = 'not-in-baseline' }
        )
        $null = Write-TestAvailabilityCache -Directory $cacheDirectory -Environment personal -LastCheckedUtc $lastCheckedUtc `
            -Clis (New-TestCliStates -CheckedUtc $lastCheckedUtc) -Models $cachedModels `
            -BaselineSha256 (Get-ModelBaselineIdentity -Baseline $baseline) -Warnings @('review: old warning', 'keep this warning')

        $result = Invoke-ModelAvailabilityUpdate -Environment personal -BaselinePath $script:ReviewFixturePath `
            -CacheDirectory $cacheDirectory -Now ([DateTimeOffset]'2026-12-02T10:00:00+08:00')

        $result.status | Should -Be 'fresh'
        @($result.review.overdue.id) | Should -Be @('old')
        @($result.review.unevaluated.id) | Should -Be @('unrated', 'discovered')
        ($result.models | Where-Object id -eq 'old').reviewOverdue | Should -BeTrue
        $result.warnings | Should -Not -Contain 'review: old warning'
        $result.warnings | Should -Contain 'keep this warning'
        $result.warnings | Should -Contain 'review: codex/old rating last reviewed 2026-11-01 (31 days ago); re-rate it before relying on it'
        $result.warnings | Should -Contain 'review: 2 unevaluated models; rate them and update references/models.json by pull request'
        Should -Invoke Get-CodexAvailableModels -Times 0 -Exactly
        Should -Invoke Get-JunieAvailableModels -Times 0 -Exactly
    }

    # Scenario: a scheduler requests rating review from an explicit baseline and an empty cache directory.
    # Purpose: report ratings without probing any CLI or creating a cache.
    It 'UnitT40_reviews the explicit baseline without probing or caching' {
        $cacheDirectory = Join-Path $TestDrive 'review-only-explicit'
        $result = Invoke-ModelAvailabilityUpdate -Environment personal -BaselinePath $script:ReviewFixturePath `
            -CacheDirectory $cacheDirectory -ReviewOnly -Now ([DateTimeOffset]'2026-12-02T10:00:00+08:00')

        $result.schemaVersion | Should -Be 1
        $result.status | Should -Be 'review'
        $result.environment | Should -Be 'personal'
        $result.baselineSource | Should -Be 'explicit'
        @($result.review.overdue.id) | Should -Be @('old')
        $result.warnings | Should -Contain 'review: 1 unevaluated models; rate them and update references/models.json by pull request'
        Test-Path -LiteralPath $cacheDirectory | Should -BeFalse
        Should -Invoke Invoke-ModelBaselineDownload -Times 0 -Exactly
        Should -Invoke Get-ClaudeLoginState -Times 0 -Exactly
        Should -Invoke Get-CodexAvailableModels -Times 0 -Exactly
        Should -Invoke Get-CopilotAvailableModels -Times 0 -Exactly
        Should -Invoke Get-JunieAvailableModels -Times 0 -Exactly
    }

    # Scenario: an existing availability cache contains invalid JSON.
    # Purpose: review the baseline without reading or rewriting that cache.
    It 'UnitT42_ignores an existing availability cache in review-only mode' {
        $cacheDirectory = Join-Path $TestDrive 'review-only-existing-cache'
        $null = New-Item -ItemType Directory -Path $cacheDirectory
        $cachePath = Join-Path $cacheDirectory 'model-availability.personal.json'
        Set-Content -LiteralPath $cachePath -Value 'invalid JSON' -NoNewline

        $result = Invoke-ModelAvailabilityUpdate -Environment personal -BaselinePath $script:ReviewFixturePath `
            -CacheDirectory $cacheDirectory -ReviewOnly

        $result.status | Should -Be 'review'
        (Get-Content -LiteralPath $cachePath -Raw) | Should -BeExactly 'invalid JSON'
    }

    # Scenario: a scheduled review has no explicit baseline and a successful mocked download.
    # Purpose: resolve the baseline normally without persisting a cache file.
    It 'UnitT45_reviews the resolved baseline without writing a local copy' {
        $cacheDirectory = Join-Path $TestDrive 'review-only-resolved'
        $result = Invoke-ModelAvailabilityUpdate -Environment work -CacheDirectory $cacheDirectory -ReviewOnly

        $result.status | Should -Be 'review'
        $result.baselineSource | Should -Be 'downloaded'
        $result.baselineSha256 | Should -Be $script:BaselineIdentity
        Test-Path -LiteralPath $cacheDirectory | Should -BeFalse
        Should -Invoke Invoke-ModelBaselineDownload -Times 1 -Exactly
    }

    # Scenario: a caller supplies both the review and force switches.
    # Purpose: reject conflicting modes before attempting a probe.
    It 'UnitT50_rejects ReviewOnly with Force' {
        { Invoke-ModelAvailabilityUpdate -Environment personal -ReviewOnly -Force } | Should -Throw '*ReviewOnly*Force*'
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

Context 'Resolve-ModelBaseline' {
    # Scenario: no local copy exists. Purpose: download and persist the reviewed main-branch baseline.
    It 'UnitT10_downloads and writes a missing copy' {
        $cacheDirectory = Join-Path $TestDrive 'baseline-missing'
        $result = Resolve-ModelBaseline -CacheDirectory $cacheDirectory -Now ([DateTimeOffset]'2026-11-02T01:00:00+08:00')
        $result.source | Should -Be 'downloaded'
        (Test-Path -LiteralPath (Join-Path $cacheDirectory 'models-baseline.json')) | Should -BeTrue
        Should -Invoke Invoke-ModelBaselineDownload -Times 1 -Exactly
    }

    # Scenario: the saved copy was fetched during the current Taipei week. Purpose: avoid unnecessary network access.
    It 'UnitT20_uses a fresh copy without downloading' {
        $cacheDirectory = Join-Path $TestDrive 'baseline-fresh'
        $copy = [pscustomobject][ordered]@{ fetchedUtc = '2026-11-01T16:00:00Z'; baseline = $script:Baseline }
        Write-ModelAvailabilityCache -Value $copy -Path (Join-Path $cacheDirectory 'models-baseline.json')
        $result = Resolve-ModelBaseline -CacheDirectory $cacheDirectory -Now ([DateTimeOffset]'2026-11-02T01:00:00+08:00')
        $result.source | Should -Be 'local-copy'
        Should -Invoke Invoke-ModelBaselineDownload -Times 0 -Exactly
    }

    # Scenario: the saved copy predates the current week. Purpose: replace it with a current download.
    It 'UnitT30_redownloads an old copy' {
        $cacheDirectory = Join-Path $TestDrive 'baseline-old'
        $copy = [pscustomobject][ordered]@{ fetchedUtc = '2026-10-25T16:00:00Z'; baseline = $script:Baseline }
        Write-ModelAvailabilityCache -Value $copy -Path (Join-Path $cacheDirectory 'models-baseline.json')
        $result = Resolve-ModelBaseline -CacheDirectory $cacheDirectory -Now ([DateTimeOffset]'2026-11-02T01:00:00+08:00')
        $result.source | Should -Be 'downloaded'
        Should -Invoke Invoke-ModelBaselineDownload -Times 1 -Exactly
    }

    # Scenario: refresh fails while an old readable copy exists. Purpose: retain known baseline data and warn.
    It 'UnitT40_falls back to an old local copy after download failure' {
        $cacheDirectory = Join-Path $TestDrive 'baseline-fallback-copy'
        $copy = [pscustomobject][ordered]@{ fetchedUtc = '2026-10-25T16:00:00Z'; baseline = $script:Baseline }
        Write-ModelAvailabilityCache -Value $copy -Path (Join-Path $cacheDirectory 'models-baseline.json')
        Mock Invoke-ModelBaselineDownload { throw 'offline' }
        $result = Resolve-ModelBaseline -CacheDirectory $cacheDirectory -Now ([DateTimeOffset]'2026-11-02T01:00:00+08:00')
        $result.source | Should -Be 'local-copy'
        $result.warnings | Should -Contain 'baseline: using local copy from 2026-10-25T16:00:00.0000000Z; refresh failed'
    }

    # Scenario: refresh fails and no copy exists. Purpose: remain operational with the bundled baseline and warn.
    It 'UnitT50_falls back to bundled after failure without a copy' {
        Mock Invoke-ModelBaselineDownload { throw 'offline' }
        $result = Resolve-ModelBaseline -CacheDirectory (Join-Path $TestDrive 'baseline-fallback-bundled') `
            -Now ([DateTimeOffset]'2026-11-02T01:00:00+08:00')
        $result.source | Should -Be 'bundled'
        $result.warnings | Should -Contain 'baseline: using the bundled list; it may be out of date'
    }

    # Scenario: a download has an unsupported schema. Purpose: reject malformed or incompatible remote data.
    It 'UnitT60_rejects an unsupported downloaded schema' {
        Mock Invoke-ModelBaselineDownload { [pscustomobject]@{ schemaVersion = 3; models = @() } }
        $result = Resolve-ModelBaseline -CacheDirectory (Join-Path $TestDrive 'baseline-rejected') `
            -Now ([DateTimeOffset]'2026-11-02T01:00:00+08:00')
        $result.source | Should -Be 'bundled'
        $result.warnings | Should -Contain 'baseline: using the bundled list; it may be out of date'
    }

    # Scenario: the caller supplies a baseline path. Purpose: preserve explicit-path behavior without remote access.
    It 'UnitT70_never downloads for an explicit baseline path' {
        $result = Invoke-ModelAvailabilityUpdate -Environment personal -CacheDirectory (Join-Path $TestDrive 'baseline-explicit') `
            -BaselinePath $script:BaselinePath -Cli codex -Force -Now ([DateTimeOffset]'2026-11-02T01:00:00+08:00')
        $result.baselineSource | Should -Be 'explicit'
        Should -Invoke Invoke-ModelBaselineDownload -Times 0 -Exactly
    }

    # Scenario: remote payloads violate one required contract rule. Purpose: reject every incomplete or ambiguous baseline shape.
    It 'UnitT80_rejects a downloaded payload with <Defect>' -TestCases @(
        @{ Defect = 'missing family'; Mutate = { param($value) $value.models[0].PSObject.Properties.Remove('family') } }
        @{ Defect = 'invalid status'; Mutate = { param($value) $value.models[0].status = 'retired' } }
        @{ Defect = 'active without capability'; Mutate = { param($value) $value.models[0].capability = $null } }
        @{ Defect = 'duplicate id'; Mutate = { param($value) $value.models = @($value.models) + @($value.models[0]) } }
        @{ Defect = 'missing efforts'; Mutate = { param($value) $value.PSObject.Properties.Remove('efforts') } }
        @{ Defect = 'schema version 1'; Mutate = { param($value) $value.schemaVersion = 1 } }
        @{ Defect = 'missing reviewed date'; Mutate = { param($value) $value.models[0].PSObject.Properties.Remove('reviewedOn') } }
        @{ Defect = 'invalid reviewed date format'; Mutate = { param($value) $value.models[0].reviewedOn = '2026/11/24' } }
        @{ Defect = 'invalid reviewed calendar date'; Mutate = { param($value) $value.models[0].reviewedOn = '2026-02-30' } }
        @{ Defect = 'zero review age limit'; Mutate = { param($value) $value.reviewMaxAgeDays = 0 } }
        @{ Defect = 'unknown cli'; Mutate = { param($value) $value.models[0].cli = 'unknown' } }
        @{ Defect = 'missing Junie efforts'; Mutate = { param($value) $value.efforts.PSObject.Properties.Remove('junie') } }
    ) {
        param($Defect, $Mutate)
        $invalid = ($script:Baseline | ConvertTo-Json -Depth 6 | ConvertFrom-Json)
        & $Mutate $invalid
        Mock Invoke-ModelBaselineDownload { $invalid }

        $result = Resolve-ModelBaseline -CacheDirectory (Join-Path $TestDrive "baseline-contract-$Defect") `
            -Now ([DateTimeOffset]'2026-11-02T01:00:00+08:00')

        $result.source | Should -Be 'bundled'
        $result.warnings | Should -Contain 'baseline: using the bundled list; it may be out of date'
    }

    # Scenario: an invalid download arrives while a valid old copy exists. Purpose: reject remote corruption and retain the local baseline with its warning.
    It 'UnitT85_falls back to a valid local copy after rejecting a download' {
        $cacheDirectory = Join-Path $TestDrive 'baseline-invalid-download-local-copy'
        $copy = [pscustomobject][ordered]@{ fetchedUtc = '2026-10-25T16:00:00Z'; baseline = $script:Baseline }
        Write-ModelAvailabilityCache -Value $copy -Path (Join-Path $cacheDirectory 'models-baseline.json')
        $invalid = ($script:Baseline | ConvertTo-Json -Depth 6 | ConvertFrom-Json)
        $invalid.models[0].PSObject.Properties.Remove('family')
        Mock Invoke-ModelBaselineDownload { $invalid }

        $result = Resolve-ModelBaseline -CacheDirectory $cacheDirectory `
            -Now ([DateTimeOffset]'2026-11-02T01:00:00+08:00')

        $result.source | Should -Be 'local-copy'
        $result.warnings | Should -Contain 'baseline: using local copy from 2026-10-25T16:00:00.0000000Z; refresh failed'
    }

    # Scenario: the repository baseline is passed to the payload validator. Purpose: keep the committed contract accepted.
    It 'UnitT90_accepts the committed models json' {
        (Test-ModelBaselinePayload -Value $script:Baseline) | Should -BeTrue
    }
}

Context 'Baseline integrity' {
    It 'has valid unique model entries and rating rules' {
        { Get-Content -LiteralPath $script:BaselinePath -Raw | ConvertFrom-Json } | Should -Not -Throw
        $baseline = Get-Content -LiteralPath $script:BaselinePath -Raw | ConvertFrom-Json
        $baseline.schemaVersion | Should -Be 2
        $baseline.reviewMaxAgeDays | Should -Be 30

        foreach ($entry in $baseline.models) {
            foreach ($field in @('cli', 'id', 'family', 'capability', 'cost', 'status', 'evidence', 'reviewedOn', 'notes')) {
                @($entry.PSObject.Properties.Name) -contains $field | Should -Be $true
            }
            $entry.status | Should -BeIn @('active', 'unevaluated', 'excluded', 'unavailable')
            $entry.evidence | Should -BeIn @('official', 'measured', 'inferred')

            if ($entry.status -eq 'active') {
                $entry.capability | Should -BeIn @(1, 2, 3, 4)
                $entry.cost | Should -BeIn @(1, 2, 3, 4)
            }
            elseif ($entry.status -in @('unevaluated', 'excluded')) {
                $entry.capability | Should -BeNullOrEmpty
                $entry.cost | Should -BeNullOrEmpty
            }
            else {
                if ($null -ne $entry.capability) { $entry.capability | Should -BeIn @(1, 2, 3, 4) }
                if ($null -ne $entry.cost) { $entry.cost | Should -BeIn @(1, 2, 3, 4) }
            }
        }

        $duplicates = @($baseline.models | Group-Object cli, id | Where-Object Count -gt 1)
        $duplicates.Count | Should -Be 0
        @($baseline.efforts.claude) | Should -Be @('low', 'medium', 'high', 'xhigh', 'max')
        @($baseline.efforts.codex) | Should -Be @('low', 'medium', 'high', 'xhigh', 'max', 'ultra')
        @($baseline.efforts.copilot) | Should -Be @('none', 'minimal', 'low', 'medium', 'high', 'xhigh', 'max')
        @($baseline.efforts.junie) | Should -Be @('low', 'medium', 'high')
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
        $baselinePath = Join-Path $TestDrive 'claude-rated-baseline.json'
        $baseline = Get-Content -LiteralPath $script:BaselinePath -Raw | ConvertFrom-Json
        $baseline.models = @($baseline.models | Where-Object status -ne 'unevaluated')
        Set-Content -LiteralPath $baselinePath -Value ($baseline | ConvertTo-Json -Depth 6)

        $result = Invoke-ModelAvailabilityUpdate `
            -Environment work `
            -BaselinePath $baselinePath `
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
