# SPDX-FileCopyrightText: 2026 SyuanTsai
# SPDX-License-Identifier: Apache-2.0
#requires -Version 7.0

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][ValidatePattern('^[0-9a-f]{40}$')][string] $CandidateRevision
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-FileSha256 {
    param([Parameter(Mandatory = $true)][string] $Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
}

function Get-TextSha256 {
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string] $Value)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([Convert]::ToHexString($sha.ComputeHash([Text.UTF8Encoding]::new($false).GetBytes($Value)))).ToLowerInvariant() }
    finally { $sha.Dispose() }
}

function Assert-PathWithinRoot {
    param([Parameter(Mandatory = $true)][string] $Path, [Parameter(Mandatory = $true)][string] $Root, [Parameter(Mandatory = $true)][string] $Context)
    $fullPath = [IO.Path]::GetFullPath($Path)
    $fullRoot = [IO.Path]::GetFullPath($Root).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    $comparison = if ($IsWindows) { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal }
    if (-not $fullPath.StartsWith($fullRoot + [IO.Path]::DirectorySeparatorChar, $comparison)) { throw "$Context escaped its run-owned parent." }
    return $fullPath
}

function Assert-UniqueJsonProperties {
    param([Parameter(Mandatory)][System.Text.Json.JsonElement] $Element, [Parameter(Mandatory)][string] $Context)
    if ($Element.ValueKind -eq [System.Text.Json.JsonValueKind]::Object) {
        $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        foreach ($property in $Element.EnumerateObject()) {
            if (-not $seen.Add($property.Name)) { throw "$Context contains duplicate JSON property '$($property.Name)'." }
            Assert-UniqueJsonProperties -Element $property.Value -Context "$Context.$($property.Name)"
        }
    }
    elseif ($Element.ValueKind -eq [System.Text.Json.JsonValueKind]::Array) {
        $index = 0
        foreach ($item in $Element.EnumerateArray()) { Assert-UniqueJsonProperties -Element $item -Context "$Context[$index]"; $index++ }
    }
}

$candidateRoot = [IO.Path]::GetFullPath((Get-Location).Path)
$runId = [string]$env:STANDARD_VALIDATION_CORE_RUN_ID
$checkId = [string]$env:STANDARD_VALIDATION_CORE_CHECK_ID
if ([IO.Path]::GetFileName($candidateRoot) -cne 'candidate' -or $runId -cnotmatch '^[0-9a-f]{32}$' -or $checkId -cne 'repository-general') {
    throw 'Repository general check requires the immutable Core candidate snapshot and its trusted run identity.'
}
$runRoot = [IO.Path]::GetFullPath((Split-Path -Parent $candidateRoot))
if ([IO.Path]::GetFileName($runRoot) -cne $runId) { throw 'Repository general check run root differs from the trusted run identity.' }
$coreArtifactsRoot = [IO.Path]::GetFullPath((Split-Path -Parent (Split-Path -Parent $runRoot)))
$adapterParent = Split-Path -Parent $coreArtifactsRoot
$adapterRoot = [IO.Path]::GetFullPath((Join-Path $adapterParent ".core-v2-adapter-$runId"))
$adapterPath = Assert-PathWithinRoot -Path (Join-Path $adapterRoot 'standard-core-adapter-v2.json') -Root $adapterRoot -Context 'Retained Core adapter'
$retainedAdapterPath = Assert-PathWithinRoot -Path (Join-Path $runRoot 'source-core-adapter.json') -Root $runRoot -Context 'Retained Core run adapter'
foreach ($path in @($adapterPath, $retainedAdapterPath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw 'Repository general check cannot locate its retained adapter binding.' }
}
$adapterSha256 = Get-FileSha256 -Path $retainedAdapterPath
if ((Get-FileSha256 -Path $adapterPath) -cne $adapterSha256) { throw 'Repository general check adapter snapshots differ.' }

$adapter = Get-Content -LiteralPath $retainedAdapterPath -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json -Depth 80 -ErrorAction Stop
$sourceSpec = $adapter.sourceValidation
$setupRunId = [string]$env:STANDARD_VALIDATION_CORE_RUN_ID
if ($setupRunId -cnotmatch '^[0-9a-f]{32}$' -or $sourceSpec.frozenFiles -isnot [array] -or $sourceSpec.toolReceipts -isnot [array]) {
    throw 'Repository general check requires the exact prepared source run identity and frozen closure.'
}
$manifestBindings = @($sourceSpec.frozenFiles | Where-Object { [IO.Path]::GetFileName([string]$_.path) -ceq 'candidate-git-entry-modes.json' })
if ($manifestBindings.Count -ne 1) { throw 'Retained Core adapter must contain one candidate Git entry mode manifest.' }
$manifestFullPath = [IO.Path]::GetFullPath([string]$manifestBindings[0].path)
$manifestSha256 = [string]$manifestBindings[0].sha256
$sourceOwnedRoot = [IO.Path]::GetFullPath((Split-Path -Parent $manifestFullPath))
if ([IO.Path]::GetFileName($sourceOwnedRoot) -cne "source-tools-$setupRunId") {
    throw 'Git entry mode manifest path does not bind the actual prepared setup RunId.'
}
$identityPath = Join-Path $sourceOwnedRoot 'source-run-identity.json'
$identityBindings = @($sourceSpec.frozenFiles | Where-Object { [IO.Path]::GetFullPath([string]$_.path).Equals([IO.Path]::GetFullPath($identityPath), $(if ($IsWindows) { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal })) })
if ($identityBindings.Count -ne 1 -or (Get-FileSha256 -Path $identityPath) -cne [string]$identityBindings[0].sha256) { throw 'Repository general check source identity receipt is missing or changed.' }
$sourceIdentity = Get-Content -LiteralPath $identityPath -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json -Depth 30 -ErrorAction Stop
if ([int]$sourceIdentity.schemaVersion -ne 1 -or [string]$sourceIdentity.runId -cne $setupRunId -or
    [string]$sourceIdentity.sourceRevision -cne $CandidateRevision -or [string]$sourceIdentity.authorityRevision -cnotmatch '^[0-9a-f]{40}$' -or
    -not [IO.Path]::GetFullPath([string]$sourceIdentity.candidateManifestPath).Equals($manifestFullPath, $(if ($IsWindows) { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal })) -or
    [string]$sourceIdentity.candidateManifestSha256 -cne $manifestSha256) {
    throw 'Repository general check source identity does not bind the exact revision, RunId and Git entry mode manifest.'
}
$archiveBindings = @($sourceSpec.frozenFiles | Where-Object { [IO.Path]::GetFileName([string]$_.path) -ceq 'candidate.zip' })
if ($archiveBindings.Count -ne 1 -or -not [IO.Path]::GetFullPath([string]$sourceIdentity.candidateArchivePath).Equals([IO.Path]::GetFullPath([string]$archiveBindings[0].path), $(if ($IsWindows) { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal })) -or
    [string]$sourceIdentity.candidateArchiveSha256 -cne [string]$archiveBindings[0].sha256 -or
    (Get-FileSha256 -Path ([string]$archiveBindings[0].path)) -cne [string]$archiveBindings[0].sha256) {
    throw 'Repository general check source identity does not bind the exact frozen candidate archive.'
}
$protectedWrapperPath = [IO.Path]::GetFullPath((Join-Path $sourceOwnedRoot 'runtime/ProtectedSourceChecks/scripts/Invoke-RepositoryCheck.ps1'))
$candidateWrapperPath = [IO.Path]::GetFullPath((Join-Path $candidateRoot 'scripts/Invoke-RepositoryCheck.ps1'))
$protectedWrapperBinding = @($sourceSpec.frozenFiles | Where-Object { [IO.Path]::GetFullPath([string]$_.path).Equals($protectedWrapperPath, $(if ($IsWindows) { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal })) })
if ($protectedWrapperBinding.Count -ne 1 -or
    (Get-FileSha256 -Path $protectedWrapperPath) -cne [string]$protectedWrapperBinding[0].sha256 -or
    (Get-FileSha256 -Path $candidateWrapperPath) -cne [string]$protectedWrapperBinding[0].sha256) {
    throw 'Candidate repository general wrapper is not byte-identical to the exact frozen protected-base copy.'
}
if ($sourceSpec.toolReceipts.Count -ne 3) { throw 'Repository general check requires exactly three prepared resolver receipts.' }
$receiptNames = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
foreach ($receiptBinding in @($sourceSpec.toolReceipts)) {
    $receiptPath = [IO.Path]::GetFullPath([string]$receiptBinding.path)
    if (-not $receiptPath.StartsWith($sourceOwnedRoot.TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar, $(if ($IsWindows) { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal }))) {
        throw 'Prepared resolver receipt escaped the source-owned setup root.'
    }
    if ((Get-FileSha256 -Path $receiptPath) -cne [string]$receiptBinding.sha256) { throw 'Prepared resolver receipt changed after setup.' }
    $receipt = Get-Content -LiteralPath $receiptPath -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json -Depth 50 -ErrorAction Stop
    $toolName = [string]$receipt.toolName
    if ($toolName -cnotin @('skill-validator', 'skill-tools', 'skillspector') -or -not $receiptNames.Add($toolName) -or
        -not $receiptPath.Equals([IO.Path]::GetFullPath((Join-Path $sourceOwnedRoot "receipt-$toolName.json")), $(if ($IsWindows) { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal })) -or
        [string]$receipt.resolutionRunId -cne $setupRunId -or $receipt.frozenForRun -isnot [bool] -or -not $receipt.frozenForRun) {
        throw 'Prepared resolver receipt does not bind the actual setup RunId.'
    }
}
foreach ($expectedTool in @('skill-validator', 'skill-tools', 'skillspector')) {
    if (-not $receiptNames.Contains($expectedTool)) { throw "Repository general check is missing resolver receipt '$expectedTool'." }
}
if (-not (Test-Path -LiteralPath $manifestFullPath -PathType Leaf) -or (Get-FileSha256 -Path $manifestFullPath) -cne $manifestSha256) {
    throw 'Git entry mode manifest path or prepared SHA-256 does not match.'
}
$document = $null
try {
    $manifestBytes = [IO.File]::ReadAllBytes($manifestFullPath)
    $strictUtf8 = [Text.UTF8Encoding]::new($false, $true)
    $manifestJson = $strictUtf8.GetString($manifestBytes)
    $document = [System.Text.Json.JsonDocument]::Parse($manifestJson)
    Assert-UniqueJsonProperties -Element $document.RootElement -Context 'Git entry mode manifest'
    $propertyNames = @($document.RootElement.EnumerateObject() | ForEach-Object { $_.Name })
    if ($document.RootElement.ValueKind -ne [System.Text.Json.JsonValueKind]::Object -or
        $propertyNames.Count -ne 3 -or @('schemaVersion', 'candidateCommit', 'entries' | Where-Object { $propertyNames -cnotcontains $_ }).Count -gt 0) {
        throw 'Git entry mode manifest has an invalid property set.'
    }
    $manifest = ConvertFrom-Json -InputObject $manifestJson -Depth 50 -ErrorAction Stop
}
catch { throw "Git entry mode manifest encoding or JSON is invalid: $($_.Exception.Message)" }
finally { if ($null -ne $document) { $document.Dispose() } }
if ($manifest.schemaVersion -ne 3 -or [string]$manifest.candidateCommit -cne $CandidateRevision -or $manifest.entries -isnot [array] -or $manifest.entries.Count -eq 0) {
    throw 'Git entry mode manifest is not bound to the immutable candidate revision.'
}

$manifestEntries = [Collections.Generic.SortedDictionary[string, object]]::new([StringComparer]::Ordinal)
foreach ($entry in @($manifest.entries)) {
    $relativePath = [string]$entry.path
    $segments = $relativePath.Split('/')
    if ([string]::IsNullOrWhiteSpace($relativePath) -or [IO.Path]::IsPathRooted($relativePath) -or
        $segments -contains '' -or $segments -contains '.' -or $segments -contains '..' -or
        $relativePath.Contains('\') -or $relativePath.Contains(':') -or
        [string]$entry.mode -cnotmatch '^[0-9]{6}$' -or [string]$entry.sha256 -cnotmatch '^[0-9a-f]{64}$' -or
        [string]$entry.mode -cnotin @('100644', '100755') -or
        $manifestEntries.ContainsKey($relativePath)) {
        throw 'Git entry mode manifest contains a duplicate, malformed or unsafe entry.'
    }
    $manifestEntries.Add($relativePath, $entry)
}

$candidateInventory = [Collections.Generic.SortedDictionary[string, object]]::new([StringComparer]::Ordinal)
foreach ($file in @(Get-ChildItem -LiteralPath $candidateRoot -Recurse -File -Force -ErrorAction Stop)) {
    if ($file -isnot [IO.FileInfo]) { throw 'Candidate snapshot contains a non-regular file entry.' }
    $relativePath = [IO.Path]::GetRelativePath($candidateRoot, $file.FullName).Replace([IO.Path]::DirectorySeparatorChar, '/').Replace([IO.Path]::AltDirectorySeparatorChar, '/')
    $candidateInventory.Add($relativePath, [pscustomobject]@{ path = $relativePath; sha256 = (Get-FileSha256 -Path $file.FullName); length = [int64]$file.Length })
}
if ($candidateInventory.Count -ne $manifestEntries.Count) { throw 'Candidate snapshot inventory differs from the protected Git entry mode manifest.' }
foreach ($relativePath in $candidateInventory.Keys) {
    if (-not $manifestEntries.ContainsKey($relativePath) -or [string]$candidateInventory[$relativePath].sha256 -cne [string]$manifestEntries[$relativePath].sha256) {
        throw "Candidate snapshot file differs from the protected Git entry mode manifest: $relativePath"
    }
}
$canonicalInventory = (@($candidateInventory.Values | ForEach-Object { "$($_.path)`t$($_.sha256)`n" }) -join '')
$candidateContentSha256 = Get-TextSha256 -Value $canonicalInventory
$candidateIdentity = Get-TextSha256 -Value "$CandidateRevision`n$candidateContentSha256`n$adapterSha256`n$runId"

$manifestPath = Assert-PathWithinRoot -Path (Join-Path $runRoot 'candidate-git-entry-modes.json') -Root $runRoot -Context 'Run-owned Git entry mode manifest'
$checkRoot = Assert-PathWithinRoot -Path (Join-Path $runRoot 'repository-general') -Root $runRoot -Context 'Run-owned repository checks'
if ((Test-Path -LiteralPath $manifestPath) -or (Test-Path -LiteralPath $checkRoot)) { throw 'Repository general check run-owned output already exists.' }
[void](New-Item -ItemType Directory -Path $checkRoot -ErrorAction Stop)
[IO.File]::WriteAllBytes($manifestPath, $manifestBytes)

try {
    $repositoryReportPath = Join-Path $checkRoot 'test-repository.json'
    $catalogReportPath = Join-Path $checkRoot 'validate-catalog.json'
    $repositoryValidatorPath = Join-Path $sourceOwnedRoot 'runtime/ProtectedSourceChecks/scripts/Test-Repository.ps1'
    $catalogValidatorPath = Join-Path $sourceOwnedRoot 'runtime/ProtectedSourceChecks/tests/validate-catalog.ps1'
    foreach ($path in @($repositoryValidatorPath, $catalogValidatorPath)) {
        $frozen = @($sourceSpec.frozenFiles | Where-Object { [IO.Path]::GetFullPath([string]$_.path).Equals([IO.Path]::GetFullPath($path), $(if ($IsWindows) { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal })) })
        if ($frozen.Count -ne 1 -or -not (Test-Path -LiteralPath $path -PathType Leaf) -or (Get-FileSha256 -Path $path) -cne [string]$frozen[0].sha256) {
            throw "Protected repository contract checker is missing or changed: $path"
        }
    }
    $repositoryArguments = @('-RepositoryRoot', $candidateRoot, '-OutputPath', $repositoryReportPath, '-ReadOnlySnapshot', '-GitEntryModeManifestPath', $manifestPath)
    $repositoryParameters = @{
        RepositoryRoot = $candidateRoot
        OutputPath = $repositoryReportPath
        ReadOnlySnapshot = $true
        GitEntryModeManifestPath = $manifestPath
    }
    & $repositoryValidatorPath @repositoryParameters *> $null
    $repositoryInvocationSucceeded = $?
    $repositoryExitCode = if ($repositoryInvocationSucceeded) { 0 } else { 1 }
    if ($repositoryExitCode -ne 0) { throw "Test-Repository failed with exit code $repositoryExitCode." }
    $catalogArguments = @('-RepositoryRoot', $candidateRoot, '-OutputPath', $catalogReportPath)
    $catalogParameters = @{
        RepositoryRoot = $candidateRoot
        OutputPath = $catalogReportPath
    }
    & $catalogValidatorPath @catalogParameters *> $null
    $catalogInvocationSucceeded = $?
    $catalogExitCode = if ($catalogInvocationSucceeded) { 0 } else { 1 }
    if ($catalogExitCode -ne 0) { throw "validate-catalog failed with exit code $catalogExitCode." }
    $repositoryReport = Get-Content -LiteralPath $repositoryReportPath -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 50 -ErrorAction Stop
    $catalogReport = Get-Content -LiteralPath $catalogReportPath -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 50 -ErrorAction Stop
    $activeSkills = @(([string]$env:STANDARD_VALIDATION_CORE_SKILLS -split ';') | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($repositoryReport.result -cne 'passed' -or $catalogReport.result -cne 'passed' -or
        [int]$repositoryReport.activeSkillCount -ne $activeSkills.Count -or [int]$catalogReport.activeSkillCount -ne $activeSkills.Count) {
        throw 'Repository integrity and catalog checks did not pass the complete active Skill inventory.'
    }
    foreach ($report in @($repositoryReport, $catalogReport)) {
        $reportedSkills = @($report.skills | ForEach-Object { [string]$_.skillId })
        if (($reportedSkills | Sort-Object -CaseSensitive) -join "`n" -cne (@($activeSkills | Sort-Object -CaseSensitive) -join "`n")) {
            throw 'Repository check reported a different active Skill inventory.'
        }
    }
    $envelope = [ordered]@{
        schemaVersion = 1
        status = 'passed'
        decision = 'PASS'
        candidateIdentity = $candidateIdentity
        activeSkills = @($activeSkills)
        findings = @()
        testInventory = @('Test-Repository ReadOnlySnapshot/GitEntryModeManifest', 'validate-catalog')
        testResult = [ordered]@{ status = 'passed'; decision = 'PASS'; result = 'Test-Repository and validate-catalog' }
        domainAdapterResult = [ordered]@{ status = 'passed'; decision = 'PASS'; result = 'Code-Collaboration repository contract' }
        nativeReports = @(
            [ordered]@{ id = 'Test-Repository ReadOnlySnapshot/GitEntryModeManifest'; path = $repositoryReportPath; sha256 = (Get-FileSha256 -Path $repositoryReportPath); command = $repositoryValidatorPath; commandSha256 = (Get-FileSha256 -Path $repositoryValidatorPath); arguments = $repositoryArguments; exitCode = $repositoryExitCode }
            [ordered]@{ id = 'validate-catalog'; path = $catalogReportPath; sha256 = (Get-FileSha256 -Path $catalogReportPath); command = $catalogValidatorPath; commandSha256 = (Get-FileSha256 -Path $catalogValidatorPath); arguments = $catalogArguments; exitCode = $catalogExitCode }
        )
    }
    [Console]::Out.WriteLine(($envelope | ConvertTo-Json -Depth 50 -Compress))
}
finally {
    if (Test-Path -LiteralPath $manifestPath) { Remove-Item -LiteralPath $manifestPath -Force -ErrorAction Stop }
}
