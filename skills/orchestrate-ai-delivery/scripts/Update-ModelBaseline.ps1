# SPDX-FileCopyrightText: 2026 SyuanTsai
# SPDX-License-Identifier: Apache-2.0

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$BaselinePath,

    [string]$CacheDirectory,

    [DateTimeOffset]$Now = [DateTimeOffset]::Now,

    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$entryParameters = @{} + $PSBoundParameters

. (Join-Path $PSScriptRoot 'Update-ModelAvailability.ps1') -Environment personal

function Format-ModelBaselineJson {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject]$Value
    )

    $json = $Value | ConvertTo-Json -Depth 6
    $lines = $json -split "`r?`n"
    $sourceIndentWidth = 2
    $firstIndentedLine = $lines | Where-Object { $_ -match '^ +' } | Select-Object -First 1
    if ($null -ne $firstIndentedLine -and $firstIndentedLine -match '^( +)') {
        $sourceIndentWidth = $Matches[1].Length
    }
    $formatted = foreach ($line in $lines) {
        if ($line -match '^( +)') {
            $level = [int]($Matches[1].Length / $sourceIndentWidth)
            $indent = ' ' * ($level * 2)
            $indent + $line.TrimStart()
        }
        else {
            $line
        }
    }
    return (($formatted -join "`n") + "`n")
}

function Write-ModelBaselineFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject]$Value,

        [Parameter(Mandatory)]
        [string]$Path
    )

    $directory = Split-Path -Parent $Path
    $temporaryPath = Join-Path $directory (([System.IO.Path]::GetRandomFileName()) + '.tmp')
    try {
        $utf8WithoutBom = [System.Text.UTF8Encoding]::new($false)
        $json = Format-ModelBaselineJson -Value $Value
        [System.IO.File]::WriteAllText($temporaryPath, $json, $utf8WithoutBom)
        Move-Item -LiteralPath $temporaryPath -Destination $Path -Force
    }
    finally {
        if (Test-Path -LiteralPath $temporaryPath) {
            Remove-Item -LiteralPath $temporaryPath -Force
        }
    }
}

function Test-ModelBaselineRepositoryCheckout {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$SkillDirectory
    )

    # A repository checkout keeps the Skill at <root>/skills/<id> next to catalog/source.json and Git metadata;
    # an installed Skill directory has neither.
    $skillsDirectory = Split-Path -Parent $SkillDirectory
    if ((Split-Path -Leaf $skillsDirectory) -cne 'skills') { return $false }
    $repositoryRoot = Split-Path -Parent $skillsDirectory
    return (
        (Test-Path -LiteralPath (Join-Path $repositoryRoot '.git')) -and
        (Test-Path -LiteralPath (Join-Path $repositoryRoot 'catalog/source.json') -PathType Leaf)
    )
}

function Invoke-ModelBaselineUpdate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$BaselinePath,

        [string]$CacheDirectory,

        [DateTimeOffset]$Now = [DateTimeOffset]::Now,

        [switch]$DryRun
    )

    $resolvedBaselinePath = [System.IO.Path]::GetFullPath($BaselinePath)
    $skillDirectory = Split-Path -Parent $PSScriptRoot
    $resolvedSkill = [System.IO.Path]::GetFullPath($skillDirectory).TrimEnd(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar
    )
    $comparison = if ($IsWindows) { [System.StringComparison]::OrdinalIgnoreCase } else { [System.StringComparison]::Ordinal }
    $skillPrefix = $resolvedSkill + [System.IO.Path]::DirectorySeparatorChar
    $targetsSkill = $resolvedBaselinePath.Equals($resolvedSkill, $comparison) -or $resolvedBaselinePath.StartsWith($skillPrefix, $comparison)
    if ($targetsSkill -and -not (Test-ModelBaselineRepositoryCheckout -SkillDirectory $resolvedSkill)) {
        throw 'The baseline must be edited in a repository working copy, not in the installed Skill directory.'
    }

    $resolvedCacheDirectory = Resolve-ModelAvailabilityCacheDirectory `
        -RequestedDirectory $CacheDirectory `
        -SkillDirectory $skillDirectory
    $cachePaths = [System.Collections.Generic.List[string]]::new()
    foreach ($environmentName in @('personal', 'work')) {
        $path = Join-Path $resolvedCacheDirectory "model-availability.$environmentName.json"
        if (Test-Path -LiteralPath $path -PathType Leaf) {
            $cachePaths.Add($path)
        }
    }
    if ($cachePaths.Count -eq 0) {
        throw 'No availability cache found; run Update-ModelAvailability.ps1 first.'
    }

    $baseline = Get-Content -LiteralPath $resolvedBaselinePath -Raw | ConvertFrom-Json
    $warnings = [System.Collections.Generic.List[string]]::new()
    $suggestions = [System.Collections.Generic.List[string]]::new()
    $observations = [System.Collections.Generic.List[object]]::new()
    $weekStartUtc = Get-TaipeiWeekStartUtc -Instant $Now

    foreach ($cachePath in $cachePaths) {
        $cache = Get-Content -LiteralPath $cachePath -Raw | ConvertFrom-Json
        $environment = [string]$cache.environment
        foreach ($cliName in @('codex', 'copilot')) {
            $isCurrent = $false
            $cliProperty = if ($null -ne $cache.PSObject.Properties['clis']) { $cache.clis.PSObject.Properties[$cliName] } else { $null }
            if ($null -ne $cliProperty) {
                $cliState = $cliProperty.Value
                try {
                    $checkedUtc = ConvertTo-ModelDateTimeOffset -Value $cliState.checkedUtc
                    $hasEvidence = @($cache.models | Where-Object {
                            $_.cli -eq $cliName -and $_.reason -in @('listed-by-cli', 'not-listed-by-cli', 'not-in-baseline')
                        }).Count -gt 0
                    $isCurrent = -not [bool]$cliState.stale -and $checkedUtc -ge $weekStartUtc -and $hasEvidence
                }
                catch {
                    $isCurrent = $false
                }
            }
            if ($isCurrent) {
                $observations.Add([pscustomobject]@{
                        environment = $environment
                        cli = $cliName
                        models = @($cache.models | Where-Object cli -eq $cliName)
                    })
            }
            else {
                $warnings.Add("$environment/$cliName`: cache not current; not used")
            }
        }
    }

    $removalsEnabled = @{}
    foreach ($cliName in @('codex', 'copilot')) {
        $observedEnvironments = @($observations | Where-Object cli -eq $cliName | ForEach-Object environment | Select-Object -Unique)
        $removalsEnabled[$cliName] = (
            $observedEnvironments.Count -eq 2 -and
            $observedEnvironments -contains 'personal' -and
            $observedEnvironments -contains 'work'
        )
        if (-not $removalsEnabled[$cliName]) {
            $warnings.Add("$cliName`: removals skipped; run Update-ModelAvailability.ps1 for both personal and work this week")
        }
    }

    $existingKeys = @{}
    foreach ($entry in @($baseline.models)) {
        $existingKeys[('{0}`0{1}' -f $entry.cli, $entry.id)] = $true
    }

    $additionCandidates = [System.Collections.Generic.List[object]]::new()
    foreach ($observation in $observations) {
        foreach ($record in @($observation.models)) {
            if ($record.status -ne 'unevaluated' -or $record.reason -ne 'not-in-baseline') { continue }
            if ($existingKeys.ContainsKey(('{0}`0{1}' -f $record.cli, $record.id))) { continue }
            $additionCandidates.Add([pscustomobject]@{
                    cli         = [string]$record.cli
                    id          = [string]$record.id
                    environment = $observation.environment
                })
        }
    }

    $candidateGroups = @{}
    foreach ($candidate in $additionCandidates) {
        $key = '{0}`0{1}' -f $candidate.cli, $candidate.id
        if (-not $candidateGroups.ContainsKey($key)) {
            $candidateGroups[$key] = [pscustomobject]@{
                cli = [string]$candidate.cli
                id = [string]$candidate.id
                environments = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
            }
        }
        $null = $candidateGroups[$key].environments.Add([string]$candidate.environment)
    }
    $candidateKeys = [string[]]@($candidateGroups.Keys)
    [Array]::Sort($candidateKeys, [System.StringComparer]::Ordinal)

    $additions = [System.Collections.Generic.List[object]]::new()
    foreach ($key in $candidateKeys) {
        $group = $candidateGroups[$key]
        $cliName = [string]$group.cli
        $id = [string]$group.id
        $environments = [string[]]@($group.environments)
        [Array]::Sort($environments, [System.StringComparer]::Ordinal)
        $environmentText = $environments -join ' and '
        $date = $Now.ToOffset([TimeSpan]::FromHours(8)).ToString('yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture)
        $additions.Add([pscustomobject][ordered]@{
                cli = $cliName
                id = $id
                family = 'unknown'
                capability = $null
                cost = $null
                status = 'unevaluated'
                evidence = 'measured'
                notes = "listed by $cliName CLI in $environmentText on $date; not yet rated"
            })
    }

    $markedUnavailable = [System.Collections.Generic.List[string]]::new()
    $date = $Now.ToOffset([TimeSpan]::FromHours(8)).ToString('yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture)
    foreach ($entry in @($baseline.models)) {
        $cliName = [string]$entry.cli
        if ($cliName -notin @('codex', 'copilot')) { continue }
        $cliObservations = @($observations | Where-Object cli -eq $cliName)
        if ([string]$entry.status -eq 'unavailable') {
            $listedAgain = @($cliObservations | Where-Object {
                    @($_.models | Where-Object { $_.id -eq $entry.id -and $_.status -eq 'available' }).Count -gt 0
                }).Count -gt 0
            if ($listedAgain) {
                $suggestions.Add(('{0}/{1}: listed again; review its status' -f $cliName, $entry.id))
            }
            continue
        }
        if ([string]$entry.status -notin @('active', 'unevaluated') -or -not $removalsEnabled[$cliName]) { continue }
        $missingEverywhere = @($cliObservations | Where-Object {
                @($_.models | Where-Object {
                        $_.id -eq $entry.id -and $_.status -eq 'unavailable' -and $_.reason -eq 'not-listed-by-cli'
                    }).Count -gt 0
            }).Count -eq $cliObservations.Count
        if ($missingEverywhere) {
            $entry.status = 'unavailable'
            $entry.notes = ([string]$entry.notes) + "; not listed by $cliName CLI on $date"
            $markedUnavailable.Add(('{0}/{1}' -f $cliName, $entry.id))
        }
    }

    if ($additions.Count -gt 0) {
        $baseline.models = @($baseline.models) + @($additions)
    }
    $added = @($additions | ForEach-Object { '{0}/{1}' -f $_.cli, $_.id })
    $changed = $added.Count -gt 0 -or $markedUnavailable.Count -gt 0
    $written = $false
    if ($changed) {
        $suggestions.Add('Review the ratings, then open a pull request with the updated models.json.')
        if (-not $DryRun) {
            Write-ModelBaselineFile -Value $baseline -Path $resolvedBaselinePath
            $written = $true
        }
    }

    return [pscustomobject]@{
        status = if ($changed) { 'changed' } else { 'unchanged' }
        added = @($added)
        markedUnavailable = @($markedUnavailable)
        suggestions = @($suggestions)
        warnings = @($warnings)
        baselinePath = $resolvedBaselinePath
        written = $written
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    Invoke-ModelBaselineUpdate @entryParameters | ConvertTo-Json -Depth 6
}
