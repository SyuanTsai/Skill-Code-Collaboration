# SPDX-FileCopyrightText: 2026 SyuanTsai
# SPDX-License-Identifier: Apache-2.0

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('personal', 'work')]
    [string]$Environment,

    [switch]$Force,

    [string]$CacheDirectory,

    [string]$BaselinePath,

    [DateTimeOffset]$Now = [DateTimeOffset]::Now,

    [ValidateSet('claude', 'codex', 'copilot')]
    [string[]]$Cli = @('claude', 'codex', 'copilot')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-CodexAvailableModels {
    [CmdletBinding()]
    param()

    $raw = & codex debug models
    if ($LASTEXITCODE -ne 0) {
        throw "codex debug models exited with code $LASTEXITCODE."
    }

    $catalog = ($raw -join [Environment]::NewLine) | ConvertFrom-Json
    if ($null -eq $catalog.PSObject.Properties['models']) {
        throw 'Unexpected output from codex debug models.'
    }

    return @($catalog.models | ForEach-Object {
            if ($null -ne $_.PSObject.Properties['slug'] -and -not [string]::IsNullOrWhiteSpace([string]$_.slug)) {
                [string]$_.slug
            }
        })
}

function Stop-CopilotProbeProcess {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Diagnostics.Process]$Process
    )

    if (-not $Process.HasExited) {
        try {
            $Process.Kill($true)
        }
        catch {
            $Process.Kill()
        }
    }

    $null = $Process.WaitForExit(5000)
}

function Test-CopilotCandidate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ModelId,

        [int]$TimeoutSeconds = 60
    )

    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = 'copilot'
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    foreach ($argument in @(
            '-p',
            'Reply with exactly: OK',
            '--model',
            $ModelId,
            '--no-ask-user',
            '--deny-tool=write',
            '--deny-tool=shell',
            '--output-format',
            'json'
        )) {
        $startInfo.ArgumentList.Add($argument)
    }

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    $started = $false

    try {
        $null = $process.Start()
        $started = $true
        $stdoutTask = $process.StandardOutput.ReadLineAsync()
        $stderrTask = $process.StandardError.ReadLineAsync()
        $stdoutClosed = $false
        $stderrClosed = $false
        $unavailable = $false
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

        while ($stopwatch.Elapsed.TotalSeconds -lt $TimeoutSeconds) {
            if (-not $stdoutClosed -and $stdoutTask.IsCompleted) {
                $line = $stdoutTask.GetAwaiter().GetResult()
                if ($null -eq $line) {
                    $stdoutClosed = $true
                }
                else {
                    if ($line -match 'user\.message|assistant\.turn_start') {
                        Stop-CopilotProbeProcess -Process $process
                        return $true
                    }
                    $stdoutTask = $process.StandardOutput.ReadLineAsync()
                }
            }

            if (-not $stderrClosed -and $stderrTask.IsCompleted) {
                $line = $stderrTask.GetAwaiter().GetResult()
                if ($null -eq $line) {
                    $stderrClosed = $true
                }
                else {
                    if ($line -match 'is not available') {
                        $unavailable = $true
                        Stop-CopilotProbeProcess -Process $process
                        break
                    }
                    $stderrTask = $process.StandardError.ReadLineAsync()
                }
            }

            if ($process.HasExited -and $stdoutClosed -and $stderrClosed) {
                break
            }

            Start-Sleep -Milliseconds 50
        }

        if ($stopwatch.Elapsed.TotalSeconds -ge $TimeoutSeconds) {
            Stop-CopilotProbeProcess -Process $process
            throw "Copilot availability probe timed out for model '$ModelId'."
        }

        if ($unavailable) {
            return $false
        }

        throw "Unexpected output from the Copilot availability probe for model '$ModelId'."
    }
    finally {
        if ($started -and -not $process.HasExited) {
            Stop-CopilotProbeProcess -Process $process
        }
        $process.Dispose()
    }
}

function Get-CopilotConfigModelIds {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string[]]$Lines
    )

    $modelIds = [System.Collections.Generic.List[string]]::new()
    $insideModelList = $false
    foreach ($rawLine in $Lines) {
        $line = [string]$rawLine
        if (-not $insideModelList) {
            if ($line -match '^\s*`?model`?\s*:') {
                $insideModelList = $true
            }
            continue
        }

        if ($line -match '^\s*-\s*"([^"]+)"\s*$') {
            $modelIds.Add($Matches[1])
            continue
        }

        if ($line -match '^\s*`[^`]+`\s*:' -or -not [string]::IsNullOrWhiteSpace($line)) {
            break
        }
    }

    return @($modelIds)
}

function Invoke-CopilotHelpConfig {
    [CmdletBinding()]
    param()

    $output = & copilot help config 2>&1
    return [pscustomobject]@{
        Lines    = @($output)
        ExitCode = $LASTEXITCODE
    }
}

function Get-CopilotAvailableModels {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]]$Candidates
    )

    $candidateSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($candidate in $Candidates) {
        if (-not [string]::IsNullOrWhiteSpace($candidate)) {
            $null = $candidateSet.Add($candidate)
        }
    }

    $configProbe = Invoke-CopilotHelpConfig
    if ($configProbe.ExitCode -ne 0) {
        throw ('copilot help config exited with code {0}.' -f $configProbe.ExitCode)
    }

    foreach ($modelId in @(Get-CopilotConfigModelIds -Lines @($configProbe.Lines))) {
        $null = $candidateSet.Add($modelId)
    }

    $available = [System.Collections.Generic.List[string]]::new()
    foreach ($candidate in @($candidateSet | Sort-Object)) {
        if (Test-CopilotCandidate -ModelId $candidate) {
            $available.Add($candidate)
        }
    }

    return @($available)
}

function Invoke-ClaudeAuthStatus {
    [CmdletBinding()]
    param()

    $output = & claude auth status
    return [pscustomobject]@{
        Lines    = @($output)
        ExitCode = $LASTEXITCODE
    }
}

function Get-ClaudeLoginState {
    [CmdletBinding()]
    param()

    $probe = Invoke-ClaudeAuthStatus
    $status = ($probe.Lines -join [Environment]::NewLine) | ConvertFrom-Json
    if ($null -eq $status.PSObject.Properties['loggedIn']) {
        throw 'Unexpected output from claude auth status.'
    }

    return [bool]$status.loggedIn
}

function Get-DefaultModelAvailabilityCacheDirectory {
    [CmdletBinding()]
    param()

    if ($IsWindows) {
        if ([string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
            throw 'LOCALAPPDATA is not set; specify -CacheDirectory.'
        }
        return (Join-Path $env:LOCALAPPDATA 'orchestrate-ai-delivery')
    }

    $userProfile = [Environment]::GetFolderPath([Environment+SpecialFolder]::UserProfile)
    if ([string]::IsNullOrWhiteSpace($userProfile)) {
        throw 'The user profile directory could not be resolved; specify -CacheDirectory.'
    }

    if ($IsMacOS) {
        return (Join-Path $userProfile 'Library/Caches/orchestrate-ai-delivery')
    }

    if (-not [string]::IsNullOrWhiteSpace($env:XDG_CACHE_HOME)) {
        return (Join-Path $env:XDG_CACHE_HOME 'orchestrate-ai-delivery')
    }

    return (Join-Path $userProfile '.cache/orchestrate-ai-delivery')
}

function Resolve-ModelAvailabilityCacheDirectory {
    [CmdletBinding()]
    param(
        [string]$RequestedDirectory,

        [Parameter(Mandatory)]
        [string]$SkillDirectory
    )

    $candidate = $RequestedDirectory
    if ([string]::IsNullOrWhiteSpace($candidate)) {
        $candidate = $env:ORCHESTRATE_AI_DELIVERY_CACHE_DIR
    }
    if ([string]::IsNullOrWhiteSpace($candidate)) {
        $candidate = Get-DefaultModelAvailabilityCacheDirectory
    }

    $resolvedCache = [System.IO.Path]::GetFullPath($candidate).TrimEnd(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar
    )
    $resolvedSkill = [System.IO.Path]::GetFullPath($SkillDirectory).TrimEnd(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar
    )
    $comparison = if ($IsWindows) {
        [System.StringComparison]::OrdinalIgnoreCase
    }
    else {
        [System.StringComparison]::Ordinal
    }
    $skillPrefix = $resolvedSkill + [System.IO.Path]::DirectorySeparatorChar

    if (
        $resolvedCache.Equals($resolvedSkill, $comparison) -or
        $resolvedCache.StartsWith($skillPrefix, $comparison)
    ) {
        throw 'The availability cache directory must be outside the orchestrate-ai-delivery Skill directory.'
    }

    return $resolvedCache
}

function Get-TaipeiWeekStartUtc {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [DateTimeOffset]$Instant
    )

    $taipeiOffset = [TimeSpan]::FromHours(8)
    $taipeiNow = $Instant.ToOffset($taipeiOffset)
    $daysSinceMonday = (([int]$taipeiNow.DayOfWeek - [int][DayOfWeek]::Monday) + 7) % 7
    $monday = [DateTimeOffset]::new(
        $taipeiNow.Year,
        $taipeiNow.Month,
        $taipeiNow.Day,
        0,
        0,
        0,
        $taipeiOffset
    ).AddDays(-$daysSinceMonday)
    return $monday.ToUniversalTime()
}

function ConvertTo-ModelDateTimeOffset {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Value
    )

    if ($Value -is [DateTimeOffset]) {
        return $Value
    }
    if ($Value -is [DateTime]) {
        return [DateTimeOffset]::new($Value)
    }
    return [DateTimeOffset]::Parse(
        [string]$Value,
        [System.Globalization.CultureInfo]::InvariantCulture,
        [System.Globalization.DateTimeStyles]::RoundtripKind
    )
}

function Get-SafeProbeFailureReason {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Management.Automation.ErrorRecord]$ErrorRecord
    )

    $message = $ErrorRecord.Exception.Message
    if ($message -match 'timed out|timeout') {
        return 'timeout'
    }
    if ($message -match 'network|offline|connect|name resolution|temporarily unavailable') {
        return 'network error'
    }
    if ($message -match 'unexpected output|parse|JSON') {
        return 'unexpected output'
    }
    return 'probe failed'
}

function New-AvailabilityModelRecord {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$CliName,

        [Parameter(Mandatory)]
        [string]$Id,

        [Parameter(Mandatory)]
        [string]$Family,

        [Parameter(Mandatory)]
        [string]$Status,

        [Parameter(Mandatory)]
        [bool]$Selectable,

        [Parameter(Mandatory)]
        [string]$Reason
    )

    return [pscustomobject][ordered]@{
        cli        = $CliName
        id         = $Id
        family     = $Family
        status     = $Status
        selectable = $Selectable
        reason     = $Reason
    }
}

function Write-ModelAvailabilityCache {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject]$Value,

        [Parameter(Mandatory)]
        [string]$Path
    )

    $directory = Split-Path -Parent $Path
    $null = New-Item -ItemType Directory -Path $directory -Force
    $temporaryPath = Join-Path $directory (([System.IO.Path]::GetRandomFileName()) + '.tmp')

    try {
        $json = $Value | ConvertTo-Json -Depth 6
        Set-Content -LiteralPath $temporaryPath -Value $json -Encoding utf8
        Move-Item -LiteralPath $temporaryPath -Destination $Path -Force
    }
    finally {
        if (Test-Path -LiteralPath $temporaryPath) {
            Remove-Item -LiteralPath $temporaryPath -Force
        }
    }
}

function Test-ModelBaselinePayload {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        [object]$Value
    )

    $integerTypes = @([byte], [sbyte], [int16], [uint16], [int32], [uint32], [int64], [uint64])
    if ($null -eq $Value) {
        return $false
    }
    $schemaVersionProperty = $Value.PSObject.Properties['schemaVersion']
    if (
        $null -eq $schemaVersionProperty -or
        $null -eq $schemaVersionProperty.Value -or
        $schemaVersionProperty.Value.GetType() -notin $integerTypes -or
        $schemaVersionProperty.Value -ne 1
    ) {
        return $false
    }
    if ($null -eq $Value.PSObject.Properties['models'] -or $Value.models -isnot [array] -or $Value.models.Count -eq 0) {
        return $false
    }

    $allowedClis = @('claude', 'codex', 'copilot')
    $allowedStatuses = @('active', 'unevaluated', 'excluded', 'unavailable')
    $allowedEvidence = @('official', 'measured', 'inferred')
    $modelKeys = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)

    foreach ($entry in $Value.models) {
        foreach ($field in @('cli', 'id', 'family')) {
            $property = $entry.PSObject.Properties[$field]
            if ($null -eq $property -or $property.Value -isnot [string] -or [string]::IsNullOrWhiteSpace($property.Value)) {
                return $false
            }
        }
        $notesProperty = $entry.PSObject.Properties['notes']
        if ($null -eq $notesProperty -or $notesProperty.Value -isnot [string]) {
            return $false
        }
        foreach ($field in @('status', 'evidence')) {
            $property = $entry.PSObject.Properties[$field]
            if ($null -eq $property -or $property.Value -isnot [string] -or [string]::IsNullOrWhiteSpace($property.Value)) {
                return $false
            }
        }
        if ($entry.cli -cnotin $allowedClis -or $entry.status -cnotin $allowedStatuses -or $entry.evidence -cnotin $allowedEvidence) {
            return $false
        }

        $capabilityProperty = $entry.PSObject.Properties['capability']
        $costProperty = $entry.PSObject.Properties['cost']
        if ($null -eq $capabilityProperty -or $null -eq $costProperty) {
            return $false
        }
        $capability = $capabilityProperty.Value
        $cost = $costProperty.Value
        $capabilityIsRating = $null -ne $capability -and $capability.GetType() -in $integerTypes -and $capability -ge 1 -and $capability -le 4
        $costIsRating = $null -ne $cost -and $cost.GetType() -in $integerTypes -and $cost -ge 1 -and $cost -le 4
        if ($entry.status -eq 'active' -and (-not $capabilityIsRating -or -not $costIsRating)) {
            return $false
        }
        if ($entry.status -in @('unevaluated', 'excluded') -and ($null -ne $capability -or $null -ne $cost)) {
            return $false
        }
        if ($entry.status -eq 'unavailable' -and (
                ($null -ne $capability -and -not $capabilityIsRating) -or
                ($null -ne $cost -and -not $costIsRating)
            )) {
            return $false
        }

        if (-not $modelKeys.Add(('{0}`0{1}' -f $entry.cli, $entry.id))) {
            return $false
        }
    }

    $effortsProperty = $Value.PSObject.Properties['efforts']
    if ($null -eq $effortsProperty -or $null -eq $effortsProperty.Value) {
        return $false
    }
    foreach ($cliName in $allowedClis) {
        $effortProperty = $Value.efforts.PSObject.Properties[$cliName]
        if ($null -eq $effortProperty -or $effortProperty.Value -isnot [array] -or $effortProperty.Value.Count -eq 0) {
            return $false
        }
        foreach ($effort in $effortProperty.Value) {
            if ($effort -isnot [string] -or [string]::IsNullOrWhiteSpace($effort)) {
                return $false
            }
        }
    }
    return $true
}

function Get-ModelBaselineIdentity {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject]$Baseline
    )

    $json = $Baseline | ConvertTo-Json -Depth 6 -Compress
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
    $hash = [System.Security.Cryptography.SHA256]::HashData($bytes)
    return [System.Convert]::ToHexString($hash).ToLowerInvariant()
}

function Invoke-ModelBaselineDownload {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Uri
    )

    return Invoke-RestMethod -Uri $Uri -TimeoutSec 30
}

function Resolve-ModelBaseline {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$CacheDirectory,

        [DateTimeOffset]$Now = [DateTimeOffset]::Now,

        [string]$BundledPath = (Join-Path $PSScriptRoot '../references/models.json')
    )

    $copyPath = Join-Path $CacheDirectory 'models-baseline.json'
    $copy = $null
    $copyReadable = $false
    if (Test-Path -LiteralPath $copyPath -PathType Leaf) {
        try {
            $candidate = Get-Content -LiteralPath $copyPath -Raw | ConvertFrom-Json
            if (
                $null -ne $candidate.PSObject.Properties['fetchedUtc'] -and
                $null -ne $candidate.PSObject.Properties['baseline'] -and
                (Test-ModelBaselinePayload -Value $candidate.baseline)
            ) {
                $null = ConvertTo-ModelDateTimeOffset -Value $candidate.fetchedUtc
                $copy = $candidate
                $copyReadable = $true
            }
        }
        catch {
            $copyReadable = $false
        }
    }

    $weekStartUtc = Get-TaipeiWeekStartUtc -Instant $Now
    if ($copyReadable) {
        $fetchedUtc = ConvertTo-ModelDateTimeOffset -Value $copy.fetchedUtc
        if ($fetchedUtc -ge $weekStartUtc) {
            return [pscustomobject]@{
                baseline = $copy.baseline
                source   = 'local-copy'
                warnings = @()
            }
        }
    }

    $uri = 'https://raw.githubusercontent.com/SyuanTsai/Skill-Code-Collaboration/main/skills/orchestrate-ai-delivery/references/models.json'
    try {
        $downloaded = Invoke-ModelBaselineDownload -Uri $uri
        if (-not (Test-ModelBaselinePayload -Value $downloaded)) {
            throw 'Downloaded model baseline was rejected.'
        }
        $wrapper = [pscustomobject][ordered]@{
            fetchedUtc = $Now.UtcDateTime.ToString(
                "yyyy-MM-dd'T'HH:mm:ss.fffffff'Z'",
                [System.Globalization.CultureInfo]::InvariantCulture
            )
            baseline = $downloaded
        }
        Write-ModelAvailabilityCache -Value $wrapper -Path $copyPath
        return [pscustomobject]@{
            baseline = $downloaded
            source   = 'downloaded'
            warnings = @()
        }
    }
    catch {
        if ($copyReadable) {
            $copyFetchedUtc = (ConvertTo-ModelDateTimeOffset -Value $copy.fetchedUtc).ToUniversalTime().ToString(
                "yyyy-MM-dd'T'HH:mm:ss.fffffff'Z'",
                [System.Globalization.CultureInfo]::InvariantCulture
            )
            return [pscustomobject]@{
                baseline = $copy.baseline
                source   = 'local-copy'
                warnings = @("baseline: using local copy from $copyFetchedUtc; refresh failed")
            }
        }

        $bundled = Get-Content -LiteralPath ([System.IO.Path]::GetFullPath($BundledPath)) -Raw | ConvertFrom-Json
        return [pscustomobject]@{
            baseline = $bundled
            source   = 'bundled'
            warnings = @('baseline: using the bundled list; it may be out of date')
        }
    }
}

function Invoke-ModelAvailabilityUpdate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('personal', 'work')]
        [string]$Environment,

        [switch]$Force,

        [string]$CacheDirectory,

        [string]$BaselinePath,

        [DateTimeOffset]$Now = [DateTimeOffset]::Now,

        [ValidateSet('claude', 'codex', 'copilot')]
        [string[]]$Cli = @('claude', 'codex', 'copilot')
    )

    $skillDirectory = Split-Path -Parent $PSScriptRoot
    $cacheDirectoryArguments = @{
        RequestedDirectory = $CacheDirectory
        SkillDirectory     = $skillDirectory
    }
    $resolvedCacheDirectory = Resolve-ModelAvailabilityCacheDirectory @cacheDirectoryArguments
    $cachePath = Join-Path $resolvedCacheDirectory "model-availability.$Environment.json"

    if ([string]::IsNullOrWhiteSpace($BaselinePath)) {
        $baselineResolution = Resolve-ModelBaseline -CacheDirectory $resolvedCacheDirectory -Now $Now
        $baseline = $baselineResolution.baseline
        $baselineSource = [string]$baselineResolution.source
        $baselineWarnings = @($baselineResolution.warnings)
    }
    else {
        $resolvedBaselinePath = [System.IO.Path]::GetFullPath($BaselinePath)
        $baseline = Get-Content -LiteralPath $resolvedBaselinePath -Raw | ConvertFrom-Json
        $baselineSource = 'explicit'
        $baselineWarnings = @()
    }
    $baselineModels = @($baseline.models)
    $baselineSha256 = Get-ModelBaselineIdentity -Baseline $baseline

    $previous = $null
    if (Test-Path -LiteralPath $cachePath -PathType Leaf) {
        $previous = Get-Content -LiteralPath $cachePath -Raw | ConvertFrom-Json
    }

    $weekStartUtc = Get-TaipeiWeekStartUtc -Instant $Now
    if ($null -ne $previous -and -not $Force) {
        $allCliStatesFresh = (
            $null -ne $previous.PSObject.Properties['clis'] -and
            $null -ne $previous.PSObject.Properties['baselineSha256'] -and
            [string]$previous.baselineSha256 -eq $baselineSha256
        )
        foreach ($requiredCli in @('claude', 'codex', 'copilot')) {
            if (-not $allCliStatesFresh) {
                break
            }

            $cliStateProperty = $previous.clis.PSObject.Properties[$requiredCli]
            if ($null -eq $cliStateProperty) {
                $allCliStatesFresh = $false
                break
            }

            $cliState = $cliStateProperty.Value
            $checkedUtcProperty = $cliState.PSObject.Properties['checkedUtc']
            if (
                ($null -ne $cliState.PSObject.Properties['stale'] -and [bool]$cliState.stale) -or
                $null -eq $checkedUtcProperty
            ) {
                $allCliStatesFresh = $false
                break
            }

            try {
                $checkedUtcValue = $checkedUtcProperty.Value
                $checkedUtc = if ($checkedUtcValue -is [DateTimeOffset]) {
                    $checkedUtcValue
                }
                elseif ($checkedUtcValue -is [DateTime]) {
                    [DateTimeOffset]::new($checkedUtcValue)
                }
                else {
                    [DateTimeOffset]::Parse(
                        [string]$checkedUtcValue,
                        [System.Globalization.CultureInfo]::InvariantCulture,
                        [System.Globalization.DateTimeStyles]::RoundtripKind
                    )
                }
                if ($checkedUtc -lt $weekStartUtc) {
                    $allCliStatesFresh = $false
                    break
                }
            }
            catch {
                $allCliStatesFresh = $false
                break
            }
        }

        if ($allCliStatesFresh) {
            $previous | Add-Member -NotePropertyName status -NotePropertyValue 'fresh' -Force
            $previous | Add-Member -NotePropertyName baselineSource -NotePropertyValue $baselineSource -Force
            $previous | Add-Member -NotePropertyName baselineSha256 -NotePropertyValue $baselineSha256 -Force
            $priorWarnings = if ($null -ne $previous.PSObject.Properties['warnings']) {
                @($previous.warnings | Where-Object { [string]$_ -notlike 'baseline: *' })
            }
            else {
                @()
            }
            $previous | Add-Member -NotePropertyName warnings -NotePropertyValue @($priorWarnings + $baselineWarnings | Select-Object -Unique) -Force
            return $previous
        }
    }

    $previousModels = if ($null -ne $previous -and $null -ne $previous.PSObject.Properties['models']) {
        @($previous.models)
    }
    else {
        @()
    }

    $selectedClis = @($Cli | Select-Object -Unique)
    if (
        $null -ne $previous -and (
            $null -eq $previous.PSObject.Properties['baselineSha256'] -or
            [string]$previous.baselineSha256 -ne $baselineSha256
        )
    ) {
        $selectedClis = @('claude', 'codex', 'copilot')
    }
    $models = [System.Collections.Generic.List[object]]::new()
    foreach ($previousModel in $previousModels) {
        if ([string]$previousModel.cli -notin $selectedClis) {
            $models.Add($previousModel)
        }
    }

    $cliStates = [ordered]@{}
    if ($null -ne $previous -and $null -ne $previous.PSObject.Properties['clis']) {
        foreach ($property in $previous.clis.PSObject.Properties) {
            if ($property.Name -notin $selectedClis) {
                $cliStates[$property.Name] = $property.Value
            }
        }
    }

    $warnings = [System.Collections.Generic.List[string]]::new()
    foreach ($baselineWarning in $baselineWarnings) {
        $warnings.Add([string]$baselineWarning)
    }
    $failureCount = 0
    $checkedUtc = $Now.UtcDateTime.ToString(
        "yyyy-MM-dd'T'HH:mm:ss.fffffff'Z'",
        [System.Globalization.CultureInfo]::InvariantCulture
    )

    foreach ($cliName in $selectedClis) {
        $cliBaseline = @($baselineModels | Where-Object { $_.cli -eq $cliName })
        $command = Get-Command -Name $cliName -CommandType Application -ErrorAction SilentlyContinue

        if ($null -eq $command) {
            foreach ($entry in $cliBaseline) {
                $recordArguments = @{
                    CliName    = $cliName
                    Id         = [string]$entry.id
                    Family     = [string]$entry.family
                    Status     = 'unavailable'
                    Selectable = $false
                    Reason     = 'cli-not-found'
                }
                $models.Add((New-AvailabilityModelRecord @recordArguments))
            }
            $cliStates[$cliName] = [pscustomobject][ordered]@{
                stale      = $false
                checkedUtc = $checkedUtc
            }
            continue
        }

        try {
            $foundIds = @()
            $claudeReason = $null
            switch ($cliName) {
                'codex' {
                    $foundIds = @(Get-CodexAvailableModels)
                }
                'copilot' {
                    $foundIds = @(Get-CopilotAvailableModels -Candidates @($cliBaseline.id))
                }
                'claude' {
                    if (Get-ClaudeLoginState) {
                        $foundIds = @($cliBaseline.id)
                        $claudeReason = 'assumed-when-logged-in'
                    }
                    else {
                        $claudeReason = 'cli-not-logged-in'
                    }
                }
            }

            foreach ($entry in $cliBaseline) {
                $isFound = [string]$entry.id -in $foundIds
                $reason = if ($cliName -eq 'claude') {
                    $claudeReason
                }
                elseif ($isFound) {
                    'listed-by-cli'
                }
                else {
                    'not-listed-by-cli'
                }
                $availabilityStatus = if ($isFound) { 'available' } else { 'unavailable' }
                $isSelectable = $isFound -and [string]$entry.status -eq 'active'
                $recordArguments = @{
                    CliName    = $cliName
                    Id         = [string]$entry.id
                    Family     = [string]$entry.family
                    Status     = $availabilityStatus
                    Selectable = $isSelectable
                    Reason     = $reason
                }
                $models.Add((New-AvailabilityModelRecord @recordArguments))
            }

            $baselineIds = @($cliBaseline.id)
            foreach ($foundId in @($foundIds | Select-Object -Unique)) {
                if ([string]$foundId -notin $baselineIds) {
                    $recordArguments = @{
                        CliName    = $cliName
                        Id         = [string]$foundId
                        Family     = 'unknown'
                        Status     = 'unevaluated'
                        Selectable = $false
                        Reason     = 'not-in-baseline'
                    }
                    $models.Add((New-AvailabilityModelRecord @recordArguments))
                }
            }

            $cliStates[$cliName] = [pscustomobject][ordered]@{
                stale      = $false
                checkedUtc = $checkedUtc
            }
        }
        catch {
            $failureCount++
            $safeReason = Get-SafeProbeFailureReason -ErrorRecord $_
            $warnings.Add("$cliName`: availability not updated ($safeReason)")
            $priorCliModels = @($previousModels | Where-Object { $_.cli -eq $cliName })
            if ($priorCliModels.Count -gt 0) {
                foreach ($priorModel in $priorCliModels) {
                    $models.Add($priorModel)
                }
            }
            else {
                foreach ($entry in $cliBaseline) {
                    $recordArguments = @{
                        CliName    = $cliName
                        Id         = [string]$entry.id
                        Family     = [string]$entry.family
                        Status     = 'unknown'
                        Selectable = $false
                        Reason     = 'probe-failed'
                    }
                    $models.Add((New-AvailabilityModelRecord @recordArguments))
                }
            }
            $cliStates[$cliName] = [pscustomobject][ordered]@{
                stale      = $true
                checkedUtc = $checkedUtc
            }
        }
    }

    $suggestions = @($models | Where-Object {
            $_.status -eq 'unevaluated' -and $_.reason -eq 'not-in-baseline'
        } | ForEach-Object {
            ('{0}/{1}: add to references/models.json via pull request after rating' -f $_.cli, $_.id)
        } | Select-Object -Unique)

    $overallStatus = if ($failureCount -eq 0) {
        'updated'
    }
    elseif ($failureCount -eq $selectedClis.Count) {
        'offline'
    }
    else {
        'partial'
    }

    $result = [pscustomobject][ordered]@{
        schemaVersion  = 1
        status         = $overallStatus
        environment    = $Environment
        baselineSource = $baselineSource
        baselineSha256 = $baselineSha256
        lastCheckedUtc = $Now.UtcDateTime.ToString(
            "yyyy-MM-dd'T'HH:mm:ss.fffffff'Z'",
            [System.Globalization.CultureInfo]::InvariantCulture
        )
        warnings       = @($warnings)
        suggestions    = @($suggestions)
        clis           = [pscustomobject]$cliStates
        models         = @($models)
    }

    Write-ModelAvailabilityCache -Value $result -Path $cachePath
    return $result
}

if ($MyInvocation.InvocationName -ne '.') {
    Invoke-ModelAvailabilityUpdate @PSBoundParameters | ConvertTo-Json -Depth 6
}
