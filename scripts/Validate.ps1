# SPDX-FileCopyrightText: 2026 SyuanTsai
# SPDX-License-Identifier: Apache-2.0
#requires -Version 7.0

[CmdletBinding()]
param(
    [string] $RepositoryRoot,
    [string] $ArtifactsRoot = $(
        if (-not [string]::IsNullOrWhiteSpace($env:RUNNER_TEMP)) { $env:RUNNER_TEMP }
        else { Join-Path ([IO.Path]::GetTempPath()) "skcv1-artifacts-$([guid]::NewGuid().ToString('N'))" }
    ),
    [string] $AuthorityArchivePath,
    [string] $BaseCommit,
    [string] $ExpectedGoRuntimeVersion = $env:STANDARD_GO_RUNTIME_VERSION,
    [string] $OutputPath,
    [int] $TimeoutSeconds = 900,
    [ValidateSet('Run')][string] $ExecutionMode = 'Run',
    [int] $AdapterVersion = 1,
    [switch] $PrepareSourceTools,
    [switch] $SourceValidation,
    [string] $SourceToolsPath,
    [string] $AuthorityRepositoryRoot,
    [string] $TrustedToolRoot,
    [string] $CancellationPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:NativeReports = @()

$script:SourceRepository = 'https://github.com/SyuanTsai/Skill-Code-Collaboration.git'
$script:AuthorityRepository = 'https://github.com/SyuanTsai/SyuanTsai-AI-Instructions.git'
$script:AuthorityCommit = '8aabd22694a05771f98639f6d726cc9a620eb94b'
$script:AuthorityArchiveSha256 = 'd92df1a8f0aa342970dc9c66a77b6211955b4708de12119cb7f9a360fd265311'
$script:EmptyTreeObject = '4b825dc642cb6eb9a060e54bf8d69288fbee4904'
$script:AuthorityFiles = [ordered]@{
    'docs/standards/README.md' = '5e1ddd737d26a5ec1ff1ebd08e158376ddaf1ea21008bb987fc7f51376923f7c'
    'docs/standards/managed-skill-lifecycle.md' = '70950cf8bdd02819efae6f6e06ac5be1da3e70f809c23e3c6f8d3b217797416c'
    'docs/standards/schemas/managed-skill-lifecycle-v1.schema.json' = '9a7f4c02588d2b88194e953a41766a72a9426fa89d4c3781c5750dcc22d35863'
    'docs/standards/schemas/openai-agent-metadata.schema.json' = '23c1aaee28a54fea1946a61d6122a2097906ffa5bdd66c8014fc6b1625c9062a'
    'docs/standards/schemas/source-inventory-v2.schema.json' = '084550944b4141ab5535f58fb6e99730a5c34b56103f6b59fd5a352679caa98e'
    'docs/standards/schemas/validation-security-gate-v1.schema.json' = '32aee32858cdb0f8fa7b01462af05ad2300cb247cd2e3ca769fa36ed1ac205a9'
    'docs/standards/skill-repository-review-matrix.md' = '315204afe428bb51cab5e815b2c40f6d0cbd55c81a3532ad59b686ae5e4c166c'
    'docs/standards/skill-repository-standard.md' = 'c85562f017a09b4f4daa8dd3a1fcbd1d34714eb711ed9c011642247c8d3be61e'
    'docs/standards/upstream-interoperability.md' = '9c544fbfb6b77a589514f1926aa1488882e932786a303a42ce6c6c9b2ba80c7e'
    'docs/standards/validation-security-gate.json' = '2d4ac30449981083d3f3eab850789e7115684f9dfecad48234bc91ffb678e674'
    'docs/standards/validation-toolchain.json' = '1dddbf4c5736e22e56f6ecb298542f41d39e116ab00ca24ad18beb7a3eab40ed'
    'scripts/Invoke-StandardAuthorityGate.ps1' = 'e5e8050df56dd60af7d9eec04fda2e05e331fded18bc69257431c2a11f39a9e9'
    'scripts/Resolve-PythonWheelClosure.py' = 'd209c973f331fdbb82a4d546bda18b1d485bcd1e446dd446b6d8bc4360b5ce35'
    'scripts/Resolve-StandardValidationTool.ps1' = '86540ff07e1b73177d179ae6a9ee2f0fef8029e27286604d68a9a98d0d205ec2'
    'docs/standards/schemas/standard-validation-adapter-v1.schema.json' = '11aa88fc25716d748bd4f514f1a44f02390ad1745dd5a5c5beee07f642fd5639'
    'docs/standards/schemas/standard-validation-evidence-v1.schema.json' = '8ed4a9d7158273d7a1e9d898acf07f57e9170822cb7cbb70f1e2eec7195867ee'
    'docs/standards/standard-validation-contract-v1.json' = '6fa3233e86ec7918aebf1413d41a6d1712f55eb2d1b09262fe18e53ddfbcb8cf'
    'docs/standards/pr12-source-merge-adoption.json' = '4c5262f2a11d228195230c15fa4faaf9614af6b59f110e5d9c08f242ce809175'
    'docs/standards/trust-anchors/human-approval-public-key.xml' = '1e46153b72d02f3ce2fb26becd449df4f1590d8e5cb441b1954006a5602bbd9b'
    'docs/standards/trust-anchors/trusted-supervisor-public-key.xml' = '4d550851f43405920156f40c9fc648d99a69dd73efc200f6968d8a837e7fbf27'
    'scripts/Invoke-StandardValidation.ps1' = 'c127309958226417291b512d633caa2120bbd12a663c98fff1d63106cf5a2677'
    'docs/standards/schemas/standard-semantic-consent-evidence-v2.schema.json' = '109091979d0a47e2035d3d8b20963fcdb85680e5da737bf1f27121608115d430'
    'scripts/StandardSemanticBridge.psm1' = 'daf90f703898cc56fc3310e1eec462bafa6552edcac0de4f08a3cd4b9f63a429'
    'docs/standards/schemas/upstream-adapter-v1.schema.json' = '3cff6246463188a91cc54c6a46315a949314767a759c6214e5b28e4db95ac8d7'
    'docs/standards/upstream-adapter.json' = 'c4f5133b24841bb9c66182dc3d5a027596f864ec28e410d47249a67b3b97ad31'
    'scripts/Validate-UpstreamAdapter.ps1' = '3b6e6474690b1ae9f9486544b68f50ca29b96f5dbe6aa8d6c6cd8570afad500b'
}
function Assert-ExactPropertySet {
    param(
        [Parameter(Mandatory = $true)] $Value,
        [Parameter(Mandatory = $true)][string[]] $Expected,
        [Parameter(Mandatory = $true)][string] $Context
    )

    if ($null -eq $Value -or $Value -is [array] -or $Value -is [string] -or $null -eq $Value.PSObject) {
        throw "$Context must be a JSON object."
    }
    $actual = @($Value.PSObject.Properties | ForEach-Object { [string]$_.Name })
    $missing = @($Expected | Where-Object { $actual -cnotcontains $_ })
    $unexpected = @($actual | Where-Object { $Expected -cnotcontains $_ })
    if ($missing.Count -gt 0 -or $unexpected.Count -gt 0 -or $actual.Count -ne $Expected.Count) {
        throw "$Context has an invalid property set. Missing='$($missing -join ',')' Unexpected='$($unexpected -join ',')'."
    }
}
function Assert-NoDuplicateJsonProperties {
    param(
        [Parameter(Mandatory = $true)][System.Text.Json.JsonElement] $Element,
        [Parameter(Mandatory = $true)][string] $Context
    )

    if ($Element.ValueKind -eq [System.Text.Json.JsonValueKind]::Object) {
        $names = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        foreach ($property in $Element.EnumerateObject()) {
            if (-not $names.Add($property.Name)) { throw "$Context contains duplicate JSON property '$($property.Name)'." }
            Assert-NoDuplicateJsonProperties -Element $property.Value -Context "$Context.$($property.Name)"
        }
    }
    elseif ($Element.ValueKind -eq [System.Text.Json.JsonValueKind]::Array) {
        $index = 0
        foreach ($item in $Element.EnumerateArray()) {
            Assert-NoDuplicateJsonProperties -Element $item -Context "$Context[$index]"
            $index++
        }
    }
}
function Read-JsonFile {
    param(
        [Parameter(Mandatory = $true)][string] $Path,
        [Parameter(Mandatory = $true)][string] $Context
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "$Context is missing: $Path" }
    try {
        $text = [IO.File]::ReadAllText($Path, [Text.UTF8Encoding]::new($false, $true))
        $document = [System.Text.Json.JsonDocument]::Parse($text)
        try { Assert-NoDuplicateJsonProperties -Element $document.RootElement -Context $Context }
        finally { $document.Dispose() }
        return $text | ConvertFrom-Json -Depth 100
    }
    catch { throw "$Context is not valid unambiguous UTF-8 JSON: $($_.Exception.Message)" }
}

function Get-FileSha256 {
    param([Parameter(Mandatory = $true)][string] $Path)
    return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
}

function Get-GitBlobSha256 {
    param(
        [Parameter(Mandatory = $true)][string] $GitPath,
        [Parameter(Mandatory = $true)][string] $RepositoryRoot,
        [Parameter(Mandatory = $true)][string] $ObjectId
    )

    if ($ObjectId -cnotmatch '^[0-9a-f]{40}$') { throw "Invalid Git blob identity '$ObjectId'." }
    $startInfo = [Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $GitPath
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    foreach ($argument in @('-C', $RepositoryRoot, 'cat-file', 'blob', $ObjectId)) {
        [void]$startInfo.ArgumentList.Add($argument)
    }
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    $hasher = [Security.Cryptography.SHA256]::Create()
    try {
        if (-not $process.Start()) { throw "Could not start Git blob reader for '$ObjectId'." }
        $hash = $hasher.ComputeHash($process.StandardOutput.BaseStream)
        $stderr = $process.StandardError.ReadToEnd()
        $process.WaitForExit()
        if ($process.ExitCode -ne 0) { throw "Git blob reader failed for '$ObjectId': $stderr" }
        return ([BitConverter]::ToString($hash) -replace '-', '').ToLowerInvariant()
    }
    finally {
        $hasher.Dispose()
        $process.Dispose()
    }
}

function Get-GitEntryModeManifest {
    param(
        [Parameter(Mandatory = $true)][string] $GitPath,
        [Parameter(Mandatory = $true)][string] $RepositoryRoot,
        [Parameter(Mandatory = $true)][string] $CandidateCommit
    )

    $startInfo = [Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $GitPath
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    foreach ($argument in @('-C', $RepositoryRoot, 'ls-tree', '-r', '-z', '--full-tree', '--format=%(objectmode)%x09%(objectname)%x09%(path)', $CandidateCommit)) {
        [void]$startInfo.ArgumentList.Add($argument)
    }
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    $output = [IO.MemoryStream]::new()
    try {
        if (-not $process.Start()) { throw 'Could not start Git tree inventory process.' }
        $process.StandardOutput.BaseStream.CopyTo($output)
        $stderr = $process.StandardError.ReadToEnd()
        $process.WaitForExit()
        if ($process.ExitCode -ne 0) { throw "Git tree inventory failed: $stderr" }
        $raw = [Text.UTF8Encoding]::new($false, $true).GetString($output.ToArray())
    }
    finally {
        $output.Dispose()
        $process.Dispose()
    }

    $entries = @()
    foreach ($record in $raw.Split([char]0, [StringSplitOptions]::RemoveEmptyEntries)) {
        $firstSeparator = $record.IndexOf([char]9)
        $secondSeparator = if ($firstSeparator -ge 0) { $record.IndexOf([char]9, $firstSeparator + 1) } else { -1 }
        if ($firstSeparator -le 0 -or $secondSeparator -le $firstSeparator + 1 -or $secondSeparator -ge $record.Length - 1) {
            throw 'Git tree inventory returned a malformed entry.'
        }
        $mode = $record.Substring(0, $firstSeparator)
        $objectId = $record.Substring($firstSeparator + 1, $secondSeparator - $firstSeparator - 1)
        $path = $record.Substring($secondSeparator + 1)
        $segments = $path.Split('/')
        if ([IO.Path]::IsPathRooted($path) -or $mode -cnotmatch '^[0-9]{6}$' -or $segments -contains '' -or
            $segments -contains '.' -or $segments -contains '..' -or $path.Contains('\') -or
            $path.Contains(':') -or $path -cmatch '[\x00-\x1f\x7f]' -or $objectId -cnotmatch '^[0-9a-f]{40}$') {
            throw "Git tree inventory returned an unsafe entry '$path' with mode '$mode'."
        }
        $entries += [ordered]@{ path = $path; mode = $mode; sha256 = Get-GitBlobSha256 -GitPath $GitPath -RepositoryRoot $RepositoryRoot -ObjectId $objectId }
    }
    if ($entries.Count -eq 0) { throw 'Git tree inventory did not contain any canonical Skill entries.' }
    return [ordered]@{ schemaVersion = 3; candidateCommit = $CandidateCommit; entries = $entries }
}

function Assert-Sha256 {
    param([Parameter(Mandatory = $true)][string] $Value, [Parameter(Mandatory = $true)][string] $Context)
    if ($Value -cnotmatch '^[0-9a-f]{64}$') { throw "$Context must be a lowercase SHA-256 value." }
}

function Test-PathWithinOrEqual {
    param([Parameter(Mandatory = $true)][string] $Path, [Parameter(Mandatory = $true)][string] $Root)
    $fullPath = [IO.Path]::GetFullPath($Path)
    $fullRoot = [IO.Path]::GetFullPath($Root).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    $comparison = if ($IsWindows) { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal }
    return $fullPath.Equals($fullRoot, $comparison) -or
        $fullPath.StartsWith($fullRoot + [IO.Path]::DirectorySeparatorChar, $comparison)
}

function Test-PathEqual {
    param([Parameter(Mandatory = $true)][string] $Left, [Parameter(Mandatory = $true)][string] $Right)
    $leftFull = [IO.Path]::GetFullPath($Left).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    $rightFull = [IO.Path]::GetFullPath($Right).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    $comparison = if ($IsWindows) { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal }
    return $leftFull.Equals($rightFull, $comparison)
}

function Assert-PathWithinRoot {
    param(
        [Parameter(Mandatory = $true)][string] $Path,
        [Parameter(Mandatory = $true)][string] $Root,
        [Parameter(Mandatory = $true)][string] $Context
    )
    $fullPath = [IO.Path]::GetFullPath($Path)
    if (-not (Test-PathWithinOrEqual -Path $fullPath -Root $Root)) { throw "$Context must stay within '$Root': $Path" }
    return $fullPath
}

function Assert-OutsideRoot {
    param(
        [Parameter(Mandatory = $true)][string] $Path,
        [Parameter(Mandatory = $true)][string] $Root,
        [Parameter(Mandatory = $true)][string] $Context
    )
    if (Test-PathWithinOrEqual -Path $Path -Root $Root) { throw "$Context must be outside '$Root': $Path" }
}

function Assert-NoReparseAncestors {
    param([Parameter(Mandatory = $true)][string] $Path, [Parameter(Mandatory = $true)][string] $Context)
    $current = [IO.Path]::GetFullPath($Path)
    while (-not [string]::IsNullOrWhiteSpace($current)) {
        $item = Get-Item -LiteralPath $current -Force -ErrorAction Stop
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "$Context is backed by a reparse point: $current" }
        $parent = Split-Path -Parent $current
        if ([string]::IsNullOrWhiteSpace($parent) -or $parent -ceq $current) { break }
        $current = $parent
    }
}

function Write-Utf8NoBom {
    param([Parameter(Mandatory = $true)][string] $Path, [Parameter(Mandatory = $true)][string] $Text)
    $parent = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($parent)) { [void](New-Item -ItemType Directory -Path $parent -Force) }
    [IO.File]::WriteAllText([IO.Path]::GetFullPath($Path), $Text, [Text.UTF8Encoding]::new($false))
}

function Get-ResolvedGitPath {
    $command = Get-Command git -CommandType Application -ErrorAction Stop | Select-Object -First 1
    return [IO.Path]::GetFullPath([string]$command.Path)
}

function Get-ResolvedPowerShellPath {
    $command = Get-Command pwsh -CommandType Application -ErrorAction Stop | Select-Object -First 1
    return [IO.Path]::GetFullPath([string]$command.Path)
}

function Resolve-GitRevision {
    param(
        [Parameter(Mandatory = $true)][string] $GitPath,
        [Parameter(Mandatory = $true)][string] $Root,
        [Parameter(Mandatory = $true)][string] $Revision,
        [Parameter(Mandatory = $true)][string] $Context
    )
    $output = @(& $GitPath -C $Root rev-parse --verify --end-of-options "$Revision^{commit}" 2>$null)
    if ($LASTEXITCODE -ne 0 -or $output.Count -ne 1 -or ([string]$output[0]).Trim() -cnotmatch '^[0-9a-f]{40}$') {
        throw "$Context '$Revision' does not resolve to one immutable commit."
    }
    return ([string]$output[0]).Trim()
}

function Resolve-GoRuntimeVersion {
    param([string] $Expected)
    if (-not [string]::IsNullOrWhiteSpace($Expected)) {
        if ($Expected -notmatch '^[0-9]+\.[0-9]+\.[0-9]+$') { throw 'ExpectedGoRuntimeVersion must be a stable semantic Go version.' }
        return $Expected
    }
    $go = Get-Command go -CommandType Application -ErrorAction Stop | Select-Object -First 1
    $output = @(& $go.Path version)
    if ($LASTEXITCODE -ne 0 -or $output.Count -ne 1 -or [string]$output[0] -notmatch '^go version go(?<version>[0-9]+\.[0-9]+\.[0-9]+)\s') {
        throw 'Could not resolve the current stable Go runtime version.'
    }
    return [string]$Matches.version
}

function Get-EventName {
    $event = [string]$env:GITHUB_EVENT_NAME
    switch ($event) {
        'pull_request' { return 'pull_request' }
        'push' { return 'push' }
        'workflow_dispatch' { return 'workflow_dispatch' }
        'pre-push' { return 'pre-push' }
        default { return 'local' }
    }
}

function Assert-AuthorityConfig {
    param([Parameter(Mandatory = $true)] $Config)

    Assert-ExactPropertySet -Value $Config -Expected @('schemaVersion', 'standardVersion', 'authority') -Context 'config/standard-v1.json'
    Assert-ExactPropertySet -Value $Config.authority -Expected @('repository', 'commit', 'archiveUrl', 'archiveSha256', 'files') -Context 'config/standard-v1.json authority'
    $schemaVersionType = if ($null -eq $Config.schemaVersion) { [TypeCode]::Empty } else { [Convert]::GetTypeCode($Config.schemaVersion) }
    $integerTypeCodes = @([TypeCode]::Byte, [TypeCode]::SByte, [TypeCode]::UInt16, [TypeCode]::UInt32, [TypeCode]::UInt64, [TypeCode]::Int16, [TypeCode]::Int32, [TypeCode]::Int64)
    if ($Config.standardVersion -isnot [string] -or $Config.authority.repository -isnot [string] -or
        $Config.authority.commit -isnot [string] -or $Config.authority.archiveUrl -isnot [string] -or
        $Config.authority.archiveSha256 -isnot [string]) {
        throw 'config/standard-v1.json authority identity fields must be scalar strings.'
    }
    if ($schemaVersionType -notin $integerTypeCodes -or [int64]$Config.schemaVersion -ne 1 -or $Config.standardVersion -cne 'v1' -or
        $Config.authority.repository -cne $script:AuthorityRepository -or
        $Config.authority.commit -cne $script:AuthorityCommit -or
        $Config.authority.archiveUrl -cne "https://codeload.github.com/SyuanTsai/SyuanTsai-AI-Instructions/zip/$($script:AuthorityCommit)" -or
        $Config.authority.archiveSha256 -cne $script:AuthorityArchiveSha256) {
        throw 'config/standard-v1.json schemaVersion must be integer 1 and remain bound to the exact approved P02 authority snapshot.'
    }
    Assert-Sha256 -Value ([string]$Config.authority.archiveSha256) -Context 'Authority archive identity'
    if ($Config.authority.files -isnot [array] -or @($Config.authority.files).Count -ne $script:AuthorityFiles.Count) {
        throw 'config/standard-v1.json authority file inventory is incomplete.'
    }
    $expectedPaths = @($script:AuthorityFiles.Keys)
    for ($index = 0; $index -lt $expectedPaths.Count; $index++) {
        $file = @($Config.authority.files)[$index]
        Assert-ExactPropertySet -Value $file -Expected @('path', 'sha256') -Context 'config/standard-v1.json authority file'
        if ($file.path -isnot [string] -or $file.sha256 -isnot [string]) {
            throw "config/standard-v1.json authority file at index $index must contain scalar string path and sha256 values."
        }
        if ([string]$file.path -cne [string]$expectedPaths[$index] -or
            [string]$file.sha256 -cne [string]$script:AuthorityFiles[$expectedPaths[$index]]) {
            throw "config/standard-v1.json authority file identity mismatch at index $index."
        }
    }
}

function Assert-ProtectedDriverAuthorityConfig {
    param([Parameter(Mandatory = $true)] $Config)

    # The protected event-base driver may itself be at either reviewed point
    # in the two-phase rollout. Candidate legacy execution below remains bound
    # to the current 8a tuple; only explicit SourceValidation selects ff85.
    $commit = [string]$Config.authority.commit
    if ($commit -ceq $script:AuthorityCommit) {
        Assert-AuthorityConfig -Config $Config
        return
    }
    if ($commit -ceq 'ff85d5f80fe795b96354e753074b5ce59ad04ecd') {
        Import-Module -Name (Join-Path $PSScriptRoot 'StandardSourceDriver.psm1') -Force -ErrorAction Stop
        [void](Assert-CodeSourceAuthorityConfig -Config $Config)
        return
    }
    throw 'Protected driver config must match one exact reviewed 8a or ff85 authority tuple.'
}

function Get-ActiveSkillIds {
    param([Parameter(Mandatory = $true)][string] $Root)
    $inventory = Read-JsonFile -Path (Join-Path $Root 'catalog/source.json') -Context 'catalog/source.json'
    Assert-ExactPropertySet -Value $inventory -Expected @('schemaVersion', 'sourceId', 'repository', 'skillsRoot', 'skills') -Context 'catalog/source.json'
    if ($inventory.schemaVersion -ne 2 -or $inventory.sourceId -cne 'code-collaboration' -or
        $inventory.repository -cne $script:SourceRepository -or $inventory.skillsRoot -cne 'skills' -or
        $inventory.skills -isnot [array] -or @($inventory.skills).Count -eq 0) {
        throw 'catalog/source.json is not the strict Code Collaboration source inventory.'
    }
    if (Test-Path -LiteralPath (Join-Path $Root 'catalog/skills-catalog.json') -PathType Leaf) {
        throw 'Legacy source-owned cross-source catalog must not coexist with catalog/source.json.'
    }
    [string[]]$declared = @($inventory.skills | ForEach-Object {
        if ($_ -isnot [string] -or [string]$_ -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$') { throw "Invalid Skill ID in catalog/source.json: '$_'." }
        [string]$_
    })
    [string[]]$sorted = @($declared)
    [Array]::Sort($sorted, [StringComparer]::Ordinal)
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($skillId in $declared) { if (-not $seen.Add($skillId)) { throw "Duplicate Skill ID '$skillId'." } }
    if (($declared -join "`n") -cne ($sorted -join "`n")) { throw 'catalog/source.json skills must use ordinal ascending order.' }
    $skillsRoot = Join-Path $Root 'skills'
    if (-not (Test-Path -LiteralPath $skillsRoot -PathType Container)) { throw 'Canonical skills/ source root is missing.' }
    $actual = @(Get-ChildItem -LiteralPath $skillsRoot -Directory -Force | ForEach-Object { [string]$_.Name })
    [Array]::Sort($actual, [StringComparer]::Ordinal)
    if (($actual -join "`n") -cne ($sorted -join "`n")) { throw 'catalog/source.json inventory does not exactly match skills/ directories.' }
    return $sorted
}

function Invoke-Resolver {
    param(
        [Parameter(Mandatory = $true)][string] $PowerShellPath,
        [Parameter(Mandatory = $true)][string] $ResolverPath,
        [Parameter(Mandatory = $true)][string[]] $Arguments
    )
    & $PowerShellPath -NoProfile -NonInteractive -File $ResolverPath @Arguments | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "Validation tool resolver failed with exit code $LASTEXITCODE." }
}

$childRunnerText = @'
# SPDX-FileCopyrightText: 2026 SyuanTsai
# SPDX-License-Identifier: Apache-2.0
#requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][ValidateSet('package-adapter', 'skill-validator', 'skill-tools', 'static', 'repository-knowledge', 'repository-catalog', 'repository-pester')][string] $Mode,
    [Parameter(Mandatory = $true)][string] $ToolchainPath,
    [Parameter(Mandatory = $true)][string] $ToolchainSha256,
    [string] $SourceRepository,
    [string] $SourceRevision,
    [string] $ArchiveSha256,
    [Parameter(Mandatory = $true)][string] $GitEntryModeManifestPath,
    [Parameter(Mandatory = $true)][string] $GitEntryModeManifestSha256,
    [string] $SemanticRequired = 'false'
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:NativeReports = @()

function Get-FileSha256 {
    param([Parameter(Mandatory = $true)][string] $Path)
    return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
}
function Assert-FileIdentity {
    param([Parameter(Mandatory = $true)][string] $Path, [Parameter(Mandatory = $true)][string] $Sha256, [Parameter(Mandatory = $true)][string] $Context)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf) -or (Get-FileSha256 -Path $Path) -cne $Sha256) { throw "$Context changed or is missing." }
}
function Get-Property {
    param([Parameter(Mandatory = $true)] $Object, [Parameter(Mandatory = $true)][string] $Name, [Parameter(Mandatory = $true)][string] $Context)
    if ($null -eq $Object -or $null -eq $Object.PSObject.Properties[$Name]) { throw "$Context is missing '$Name'." }
    return $Object.PSObject.Properties[$Name].Value
}
function Get-PropertyValue {
    param([Parameter(Mandatory = $true)] $Object, [Parameter(Mandatory = $true)][string] $Name, [Parameter(Mandatory = $true)][string] $Context)
    if ($null -eq $Object -or $null -eq $Object.PSObject.Properties[$Name]) { throw "$Context is missing '$Name'." }
    return ,$Object.PSObject.Properties[$Name].Value
}
function Get-ScalarProperty {
    param([Parameter(Mandatory = $true)] $Object, [Parameter(Mandatory = $true)][string] $Name, [Parameter(Mandatory = $true)][string] $Context)
    $value = Get-PropertyValue -Object $Object -Name $Name -Context $Context
    if ($null -eq $value -or $value -is [array]) { throw "$Context property '$Name' must be a non-null scalar JSON value." }
    return $value
}
function Assert-NoDuplicateJsonProperties {
    param(
        [Parameter(Mandatory = $true)][System.Text.Json.JsonElement] $Element,
        [Parameter(Mandatory = $true)][string] $Context
    )
    if ($Element.ValueKind -eq [System.Text.Json.JsonValueKind]::Object) {
        $names = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        foreach ($property in $Element.EnumerateObject()) {
            if (-not $names.Add($property.Name)) { throw "$Context contains duplicate JSON property '$($property.Name)'." }
            Assert-NoDuplicateJsonProperties -Element $property.Value -Context "$Context.$($property.Name)"
        }
    }
    elseif ($Element.ValueKind -eq [System.Text.Json.JsonValueKind]::Array) {
        $index = 0
        foreach ($item in $Element.EnumerateArray()) {
            Assert-NoDuplicateJsonProperties -Element $item -Context "$Context[$index]"
            $index++
        }
    }
}
function Assert-JsonArrayPropertyPath {
    param(
        [Parameter(Mandatory = $true)][System.Text.Json.JsonElement] $Root,
        [Parameter(Mandatory = $true)][string] $PropertyPath,
        [Parameter(Mandatory = $true)][string] $Context
    )
    $segments = @($PropertyPath.Split('.'))
    $current = [Collections.Generic.List[System.Text.Json.JsonElement]]::new()
    [void]$current.Add($Root)
    for ($index = 0; $index -lt $segments.Count; $index++) {
        $segment = $segments[$index]
        $expand = $segment.EndsWith('[]')
        $name = if ($expand) { $segment.Substring(0, $segment.Length - 2) } else { $segment }
        if ([string]::IsNullOrWhiteSpace($name)) { throw "$Context has an invalid JSON array property path '$PropertyPath'." }
        $next = [Collections.Generic.List[System.Text.Json.JsonElement]]::new()
        foreach ($element in $current) {
            if ($element.ValueKind -ne [System.Text.Json.JsonValueKind]::Object) { throw "$Context property path '$PropertyPath' is not an object path." }
            try { $property = $element.GetProperty($name) }
            catch { throw "$Context is missing JSON property '$PropertyPath'." }
            if (($expand -or $index -eq $segments.Count - 1) -and $property.ValueKind -ne [System.Text.Json.JsonValueKind]::Array) {
                throw "$Context property '$PropertyPath' must be a JSON array."
            }
            if ($expand) {
                foreach ($item in $property.EnumerateArray()) { [void]$next.Add($item) }
            }
            else { [void]$next.Add($property) }
        }
        $current = $next
    }
}
function Assert-JsonText {
    param(
        [Parameter(Mandatory = $true)][string] $Text,
        [Parameter(Mandatory = $true)][string] $Context,
        [string[]] $ArrayPropertyPaths = @()
    )
    $document = $null
    try {
        $document = [System.Text.Json.JsonDocument]::Parse($Text)
        Assert-NoDuplicateJsonProperties -Element $document.RootElement -Context $Context
        foreach ($propertyPath in @($ArrayPropertyPaths)) {
            if ([string]::IsNullOrWhiteSpace($propertyPath)) { continue }
            Assert-JsonArrayPropertyPath -Root $document.RootElement -PropertyPath $propertyPath -Context $Context
        }
    }
    catch { throw "$Context is not valid unambiguous UTF-8 JSON: $($_.Exception.Message)" }
    finally {
        if ($null -ne $document) { $document.Dispose() }
    }
}
function ConvertFrom-StrictJsonText {
    param(
        [Parameter(Mandatory = $true)][string] $Text,
        [Parameter(Mandatory = $true)][string] $Context,
        [string[]] $ArrayPropertyPaths = @()
    )
    Assert-JsonText -Text $Text -Context $Context -ArrayPropertyPaths $ArrayPropertyPaths
    try { return ($Text | ConvertFrom-Json -Depth 100) }
    catch { throw "$Context could not be materialized: $($_.Exception.Message)" }
}
function Read-Json {
    param(
        [Parameter(Mandatory = $true)][string] $Path,
        [Parameter(Mandatory = $true)][string] $Context,
        [string[]] $ArrayPropertyPaths = @()
    )
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "$Context is missing: $Path" }
    $text = [IO.File]::ReadAllText($Path, [Text.UTF8Encoding]::new($false, $true))
    return ConvertFrom-StrictJsonText -Text $text -Context $Context -ArrayPropertyPaths $ArrayPropertyPaths
}
function Read-SnapshotBlobManifest {
    param(
        [Parameter(Mandatory = $true)][string] $Path,
        [string] $ExpectedCommit
    )
    $manifest = Read-Json -Path $Path -Context 'candidate Git entry manifest'
    $manifestProperties = @($manifest.PSObject.Properties | ForEach-Object { [string]$_.Name })
    if ($manifestProperties.Count -ne 3 -or $manifestProperties -cnotcontains 'schemaVersion' -or
        $manifestProperties -cnotcontains 'candidateCommit' -or $manifestProperties -cnotcontains 'entries') {
        throw 'Candidate Git entry manifest has an invalid property set.'
    }
    if (($manifest.schemaVersion -isnot [int] -and $manifest.schemaVersion -isnot [long]) -or [int64]$manifest.schemaVersion -ne 3) {
        throw 'Candidate Git entry manifest schemaVersion must be integer 3.'
    }
    if ($manifest.candidateCommit -isnot [string] -or [string]$manifest.candidateCommit -cnotmatch '^[0-9a-f]{40}$') {
        throw 'Candidate Git entry manifest candidateCommit must be a lowercase full Git object ID.'
    }
    if (-not [string]::IsNullOrWhiteSpace($ExpectedCommit) -and [string]$manifest.candidateCommit -cne $ExpectedCommit) {
        throw 'Candidate Git entry manifest is not bound to the requested candidate commit.'
    }
    if ($manifest.entries -isnot [array] -or @($manifest.entries).Count -eq 0) {
        throw 'Candidate Git entry manifest entries must be a non-empty array.'
    }
    $entries = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::Ordinal)
    foreach ($entry in @($manifest.entries)) {
        $properties = @($entry.PSObject.Properties | ForEach-Object { [string]$_.Name })
        if ($properties.Count -ne 3 -or $properties -cnotcontains 'path' -or $properties -cnotcontains 'mode' -or $properties -cnotcontains 'sha256') {
            throw 'Candidate Git entry manifest entry has an invalid property set.'
        }
        if ($entry.path -isnot [string] -or $entry.mode -isnot [string] -or $entry.sha256 -isnot [string]) {
            throw 'Candidate Git entry manifest entries must contain string path, mode, and sha256 values.'
        }
        $pathValue = [string]$entry.path
        $segments = $pathValue.Split('/')
        if ([IO.Path]::IsPathRooted($pathValue) -or $segments -contains '' -or $segments -contains '.' -or $segments -contains '..' -or
            $pathValue.Contains('\') -or $pathValue.Contains(':') -or $pathValue -cmatch '[\x00-\x1f\x7f]') {
            throw "Candidate Git entry manifest contains an unsafe path '$pathValue'."
        }
        $modeValue = [string]$entry.mode
        if ($modeValue -cnotmatch '^[0-9]{6}$') { throw "Candidate Git entry manifest contains invalid mode '$modeValue'." }
        $sha256Value = [string]$entry.sha256
        if ($sha256Value -cnotmatch '^[0-9a-f]{64}$') { throw "Candidate Git entry manifest contains invalid blob sha256 for '$pathValue'." }
        if (-not $entries.TryAdd($pathValue, [pscustomobject][ordered]@{ mode = $modeValue; sha256 = $sha256Value })) {
            throw "Candidate Git entry manifest contains duplicate path '$pathValue'."
        }
    }
    return $entries
}
function Assert-CandidateSnapshotMatchesManifest {
    param(
        [Parameter(Mandatory = $true)][string] $CandidateRoot,
        [Parameter(Mandatory = $true)][Collections.Generic.Dictionary[string, object]] $Manifest
    )
    $root = [IO.Path]::GetFullPath($CandidateRoot)
    $files = [Collections.Generic.Dictionary[string, IO.FileInfo]]::new([StringComparer]::Ordinal)
    foreach ($item in @(Get-ChildItem -LiteralPath $root -Recurse -Force)) {
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Candidate snapshot contains a reparse point: $($item.FullName)"
        }
        if ($item.PSIsContainer) { continue }
        if ($item -isnot [IO.FileInfo]) { throw "Candidate snapshot contains a non-regular entry: $($item.FullName)" }
        $relative = [IO.Path]::GetRelativePath($root, $item.FullName).Replace([IO.Path]::DirectorySeparatorChar, '/')
        $segments = $relative.Split('/')
        if ([IO.Path]::IsPathRooted($relative) -or $segments -contains '' -or $segments -contains '.' -or $segments -contains '..' -or
            $relative.Contains('\') -or $relative.Contains(':') -or $relative -cmatch '[\x00-\x1f\x7f]') {
            throw "Candidate snapshot contains an unsafe inventory path '$relative'."
        }
        if (-not $files.TryAdd($relative, $item)) { throw "Candidate snapshot contains duplicate inventory path '$relative'." }
    }
    if ($files.Count -ne $Manifest.Count) { throw 'Candidate snapshot inventory does not match the committed Git entry manifest.' }
    foreach ($file in $files.GetEnumerator()) {
        if (-not $Manifest.ContainsKey($file.Key)) { throw "Candidate snapshot contains an unlisted file '$($file.Key)'." }
        $actualSha256 = Get-FileSha256 -Path $file.Value.FullName
        $expectedSha256 = [string]$Manifest[$file.Key].sha256
        if ($actualSha256 -cne $expectedSha256) {
            throw "Candidate snapshot file '$($file.Key)' does not match its committed Git blob digest."
        }
    }
    foreach ($entry in $Manifest.GetEnumerator()) {
        $candidatePath = [IO.Path]::GetFullPath((Join-Path $root ($entry.Key -replace '/', [IO.Path]::DirectorySeparatorChar)))
        if (-not (Test-PathWithin -Path $candidatePath -Root $root) -or -not (Test-Path -LiteralPath $candidatePath -PathType Leaf)) {
            throw "Candidate snapshot is missing committed Git entry '$($entry.Key)'."
        }
    }
}
function Test-PathEqual {
    param([Parameter(Mandatory = $true)][string] $Left, [Parameter(Mandatory = $true)][string] $Right)
    $comparison = if ($IsWindows) { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal }
    return [IO.Path]::GetFullPath($Left).Equals([IO.Path]::GetFullPath($Right), $comparison)
}
function Test-PathWithin {
    param([Parameter(Mandatory = $true)][string] $Path, [Parameter(Mandatory = $true)][string] $Root)
    $fullPath = [IO.Path]::GetFullPath($Path)
    $fullRoot = [IO.Path]::GetFullPath($Root).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    $comparison = if ($IsWindows) { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal }
    return $fullPath.Equals($fullRoot, $comparison) -or $fullPath.StartsWith($fullRoot + [IO.Path]::DirectorySeparatorChar, $comparison)
}
function Get-ActiveSkills {
    $values = @([string]$env:STANDARD_VALIDATION_ACTIVE_SKILLS -split ';' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($values.Count -eq 0) { throw 'Central runner did not provide active Skill identities.' }
    return [string[]]$values
}
function Get-SkillRoot {
    param([Parameter(Mandatory = $true)][string] $SkillId)
    $skillsRoot = [IO.Path]::GetFullPath([string]$env:STANDARD_VALIDATION_SKILLS_ROOT)
    $skillRoot = [IO.Path]::GetFullPath((Join-Path $skillsRoot $SkillId))
    if (-not (Test-PathWithin -Path $skillRoot -Root $skillsRoot) -or -not (Test-Path -LiteralPath $skillRoot -PathType Container)) {
        throw "Central runner supplied an unsafe or missing Skill root: $SkillId"
    }
    return $skillRoot
}
function Get-InventoryPaths {
    param([Parameter(Mandatory = $true)][string] $SkillRoot)
    $root = [IO.Path]::GetFullPath($SkillRoot).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    $paths = @(
        Get-ChildItem -LiteralPath $root -Recurse -File -Force |
            ForEach-Object { $_.FullName.Substring($root.Length).TrimStart([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar).Replace([IO.Path]::DirectorySeparatorChar, '/') }
    )
    [Array]::Sort($paths, [StringComparer]::Ordinal)
    if ($paths.Count -eq 0) { throw "Skill inventory is empty: $SkillRoot" }
    return [string[]]$paths
}
function Resolve-ReportedFilePath {
    param(
        [Parameter(Mandatory = $true)] $Value,
        [Parameter(Mandatory = $true)][string] $SkillRoot,
        [Parameter(Mandatory = $true)][string[]] $ExpectedPaths,
        [Parameter(Mandatory = $true)][string] $Context
    )
    if ($Value -isnot [string] -or [string]::IsNullOrWhiteSpace([string]$Value)) { throw "$Context must identify a file." }
    $candidate = [string]$Value
    if ($candidate -cmatch '^file:') {
        $uri = $null
        if (-not [Uri]::TryCreate($candidate, [UriKind]::Absolute, [ref]$uri) -or -not $uri.IsFile) { throw "$Context must be a local file." }
        $candidate = $uri.LocalPath
    }
    elseif (-not [IO.Path]::IsPathRooted($candidate)) { $candidate = Join-Path $SkillRoot $candidate }
    $full = [IO.Path]::GetFullPath($candidate)
    if (-not (Test-PathWithin -Path $full -Root $SkillRoot)) { throw "$Context escapes the Skill root." }
    foreach ($relative in $ExpectedPaths) {
        if (Test-PathEqual -Left $full -Right (Join-Path $SkillRoot $relative)) { return $full }
    }
    throw "$Context is outside the candidate-bound inventory."
}
function Get-TextSha256 {
    param([Parameter(Mandatory = $true)][string] $Text)
    $hasher = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($hasher.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text))) -replace '-', '').ToLowerInvariant() }
    finally { $hasher.Dispose() }
}
function New-Finding {
    param([Parameter(Mandatory = $true)] $Issue, [Parameter(Mandatory = $true)][string] $SkillId, [Parameter(Mandatory = $true)][string] $Stage)
    $severityValue = Get-ScalarProperty -Object $Issue -Name 'severity' -Context "$Stage issue"
    if ($severityValue -isnot [string] -or [string]::IsNullOrWhiteSpace($severityValue)) { throw "$Stage issue severity must be a non-empty string for '$SkillId'." }
    $severity = ([string]$severityValue).ToLowerInvariant()
    $severity = switch ($severity) {
        'critical' { 'critical'; break }
        'high' { 'high'; break }
        'medium' { 'medium'; break }
        'low' { 'low'; break }
        'informational' { 'informational'; break }
        'info' { 'informational'; break }
        default { throw "$Stage returned unsupported severity '$severity' for '$SkillId'." }
    }
    $issueJson = $Issue | ConvertTo-Json -Depth 30 -Compress
    $path = ''
    if ($null -ne $Issue.PSObject.Properties['file']) {
        $pathValue = Get-ScalarProperty -Object $Issue -Name 'file' -Context "$Stage issue"
        if ($pathValue -isnot [string]) { throw "$Stage issue file must be a string for '$SkillId'." }
        $path = [string]$pathValue
    }
    elseif ($null -ne $Issue.PSObject.Properties['path']) {
        $pathValue = Get-ScalarProperty -Object $Issue -Name 'path' -Context "$Stage issue"
        if ($pathValue -isnot [string]) { throw "$Stage issue path must be a string for '$SkillId'." }
        $path = [string]$pathValue
    }
    $ruleId = $Stage
    if ($null -ne $Issue.PSObject.Properties['rule_id']) {
        $ruleIdValue = Get-ScalarProperty -Object $Issue -Name 'rule_id' -Context "$Stage issue"
        if ($ruleIdValue -isnot [string] -or [string]::IsNullOrWhiteSpace($ruleIdValue)) { throw "$Stage issue rule_id must be a non-empty string for '$SkillId'." }
        $ruleId = [string]$ruleIdValue
    }
    elseif ($null -ne $Issue.PSObject.Properties['ruleId']) {
        $ruleIdValue = Get-ScalarProperty -Object $Issue -Name 'ruleId' -Context "$Stage issue"
        if ($ruleIdValue -isnot [string] -or [string]::IsNullOrWhiteSpace($ruleIdValue)) { throw "$Stage issue ruleId must be a non-empty string for '$SkillId'." }
        $ruleId = [string]$ruleIdValue
    }
    $message = $issueJson
    if ($null -ne $Issue.PSObject.Properties['message']) {
        $messageValue = Get-ScalarProperty -Object $Issue -Name 'message' -Context "$Stage issue"
        if ($messageValue -isnot [string] -or [string]::IsNullOrWhiteSpace($messageValue)) { throw "$Stage issue message must be a non-empty string for '$SkillId'." }
        $message = [string]$messageValue
    }
    return [ordered]@{
        severity = $severity
        fingerprint = Get-TextSha256 -Text $issueJson
        ruleId = $ruleId
        message = $message
        path = $path
        skillId = $SkillId
    }
}
function New-Envelope {
    param(
        [Parameter(Mandatory = $true)][string[]] $ActiveSkills,
        [array] $Findings = @(),
        [hashtable] $Additional
    )
    $value = [ordered]@{
        schemaVersion = 1
        status = 'passed'
        decision = 'PASS'
        candidateIdentity = [string]$env:STANDARD_VALIDATION_CANDIDATE_ID
        activeSkills = @($ActiveSkills)
        findings = @($Findings)
    }
    if ($null -ne $Additional) {
        foreach ($key in $Additional.Keys) { $value[$key] = $Additional[$key] }
    }
    if ($Mode -in @('skill-validator', 'skill-tools', 'static') -and $script:NativeReports.Count -gt 0) {
        $value.nativeReports = @($script:NativeReports)
    }
    [Console]::Out.WriteLine(($value | ConvertTo-Json -Depth 100 -Compress))
    exit 0
}
function Invoke-NativeJson {
    param(
        [Parameter(Mandatory = $true)][string] $Command,
        [Parameter(Mandatory = $true)][string[]] $Arguments,
        [Parameter(Mandatory = $true)][string] $Context,
        [string[]] $ArrayPropertyPaths = @()
    )
    $rawRoot = [IO.Path]::GetFullPath((Get-Location).Path)
    $rawId = [guid]::NewGuid().ToString('N')
    $stdoutPath = Join-Path $rawRoot "native-raw-$rawId.stdout.txt"
    $stderrPath = Join-Path $rawRoot "native-raw-$rawId.stderr.txt"
    & $Command @Arguments 1> $stdoutPath 2> $stderrPath
    $exitCode = $LASTEXITCODE
    # Save the raw streams before any process-exit or JSON validation guard.
    $stdout = if (Test-Path -LiteralPath $stdoutPath -PathType Leaf) { Get-Content -LiteralPath $stdoutPath -Raw -Encoding UTF8 } else { '' }
    $stderr = if (Test-Path -LiteralPath $stderrPath -PathType Leaf) { Get-Content -LiteralPath $stderrPath -Raw -Encoding UTF8 } else { '' }
    $stdoutSha256 = if (Test-Path -LiteralPath $stdoutPath -PathType Leaf) { Get-FileSha256 -Path $stdoutPath } else { $null }
    $stderrSha256 = if (Test-Path -LiteralPath $stderrPath -PathType Leaf) { Get-FileSha256 -Path $stderrPath } else { $null }
    if ($exitCode -ne 0) { throw "$Context returned exit code $exitCode. $stderr" }
    $json = $stdout.Trim()
    if ([string]::IsNullOrWhiteSpace($json)) { throw "$Context produced no JSON output." }
    $report = ConvertFrom-StrictJsonText -Text $json -Context $Context -ArrayPropertyPaths $ArrayPropertyPaths
    if ($Mode -in @('skill-validator', 'skill-tools', 'static')) {
        $safeContext = [regex]::Replace($Context, '[^A-Za-z0-9._-]', '-')
        $reportPath = Join-Path $rawRoot ("native-$safeContext-$([guid]::NewGuid().ToString('N')).json")
        [IO.File]::WriteAllText($reportPath, $json + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
        $script:NativeReports += [ordered]@{
            skillId = [string]$env:STANDARD_VALIDATION_SKILL_ID
            path = [IO.Path]::GetFullPath($reportPath)
            sha256 = Get-FileSha256 -Path $reportPath
            stdoutPath = $stdoutPath
            stdoutSha256 = $stdoutSha256
            stderrPath = $stderrPath
            stderrSha256 = $stderrSha256
            command = [IO.Path]::GetFullPath($Command)
            commandSha256 = Get-FileSha256 -Path $Command
            arguments = @($Arguments)
            exitCode = $exitCode
        }
    }
    return $report
}
function Assert-SkillValidatorReport {
    param([Parameter(Mandatory = $true)] $Report, [Parameter(Mandatory = $true)][string] $SkillRoot, [Parameter(Mandatory = $true)][string[]] $Inventory, [Parameter(Mandatory = $true)][string] $SkillId)
    $results = @(Assert-StandardValidationSkillValidatorReport -Report $Report -SkillRoot $SkillRoot -SkillId $SkillId)
    $integerTypeCodes = @([TypeCode]::Byte, [TypeCode]::SByte, [TypeCode]::UInt16, [TypeCode]::UInt32, [TypeCode]::UInt64, [TypeCode]::Int16, [TypeCode]::Int32, [TypeCode]::Int64)
    $findings = @()
    foreach ($result in $results) {
        $levelValue = Get-PropertyValue -Object $result -Name 'level' -Context 'skill-validator result'
        $categoryValue = Get-PropertyValue -Object $result -Name 'category' -Context 'skill-validator result'
        $messageValue = Get-PropertyValue -Object $result -Name 'message' -Context 'skill-validator result'
        if ($levelValue -isnot [string] -or [string]::IsNullOrWhiteSpace($levelValue) -or
            $categoryValue -isnot [string] -or [string]::IsNullOrWhiteSpace($categoryValue) -or
            $messageValue -isnot [string] -or [string]::IsNullOrWhiteSpace($messageValue)) {
            throw "skill-validator result is missing a required string field for '$SkillId'."
        }
        $level = ([string]$levelValue).ToLowerInvariant()
        if ($level -notin @('pass', 'info')) { throw "skill-validator returned a blocking or malformed result for '$SkillId'." }
        $filePath = ''
        if ($null -ne $result.PSObject.Properties['file']) {
            $fileValue = Get-ScalarProperty -Object $result -Name 'file' -Context 'skill-validator result'
            if ($fileValue -isnot [string]) { throw "skill-validator result file must be a string for '$SkillId'." }
            [void](Resolve-ReportedFilePath -Value $fileValue -SkillRoot $SkillRoot -ExpectedPaths $Inventory -Context 'skill-validator result file')
            $filePath = [string]$fileValue
        }
        if ($null -ne $result.PSObject.Properties['line']) {
            $lineValue = Get-PropertyValue -Object $result -Name 'line' -Context 'skill-validator result'
            $lineType = if ($null -eq $lineValue) { [TypeCode]::Empty } else { [Convert]::GetTypeCode($lineValue) }
            if ($lineType -notin $integerTypeCodes -or [int64]$lineValue -le 0) {
                throw "skill-validator result line must be a positive JSON integer for '$SkillId'."
            }
        }
        if ($level -eq 'info') {
            $findings += [ordered]@{ severity = 'informational'; fingerprint = Get-TextSha256 -Text ($result | ConvertTo-Json -Depth 20 -Compress); ruleId = [string]$categoryValue; message = [string]$messageValue; path = $filePath; skillId = $SkillId }
        }
    }
    return ,$findings
}
function Assert-SkillToolsReport {
    param([Parameter(Mandatory = $true)] $Report, [Parameter(Mandatory = $true)][string] $SkillRoot, [Parameter(Mandatory = $true)][string[]] $Inventory, [Parameter(Mandatory = $true)][string] $SkillId)
    $versionValue = Get-ScalarProperty -Object $Report -Name 'version' -Context 'skill-tools SARIF'
    if ($versionValue -isnot [string] -or [string]::IsNullOrWhiteSpace($versionValue)) { throw "skill-tools SARIF version must be a non-empty string for '$SkillId'." }
    $version = [string]$versionValue
    $runs = Get-PropertyValue -Object $Report -Name 'runs' -Context 'skill-tools SARIF'
    if ($null -eq $runs) { $runs = @() }
    elseif ($runs -isnot [array]) { throw "skill-tools SARIF runs must be an array for '$SkillId'." }
    else { $runs = @($runs) }
    if ($version -cne '2.1.0' -or $runs.Count -ne 1) { throw "skill-tools did not produce SARIF 2.1.0 for '$SkillId'." }
    $run = $runs[0]
    $tool = Get-ScalarProperty -Object $run -Name 'tool' -Context 'skill-tools SARIF run'
    $driver = Get-ScalarProperty -Object $tool -Name 'driver' -Context 'skill-tools SARIF tool'
    $driverNameValue = Get-ScalarProperty -Object $driver -Name 'name' -Context 'skill-tools SARIF driver'
    if ($driverNameValue -isnot [string] -or [string]::IsNullOrWhiteSpace($driverNameValue)) { throw "skill-tools SARIF driver name must be a non-empty string for '$SkillId'." }
    $driverName = [string]$driverNameValue
    $rules = Get-PropertyValue -Object $driver -Name 'rules' -Context 'skill-tools SARIF driver'
    if ($null -eq $rules) { $rules = @() }
    elseif ($rules -isnot [array]) { throw "skill-tools SARIF rules must be an array for '$SkillId'." }
    else { $rules = @($rules) }
    $results = Get-PropertyValue -Object $run -Name 'results' -Context 'skill-tools SARIF run'
    if ($null -eq $results) { $results = @() }
    elseif ($results -isnot [array]) { throw "skill-tools SARIF results must be an array for '$SkillId'." }
    else { $results = @($results) }
    if ($driverName -cne 'skill-tools') { throw "skill-tools SARIF driver identity is invalid for '$SkillId'." }
    $ruleById = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::Ordinal)
    foreach ($rule in $rules) {
        $ruleIdValue = Get-PropertyValue -Object $rule -Name 'id' -Context 'skill-tools SARIF rule'
        if ($ruleIdValue -isnot [string] -or [string]::IsNullOrWhiteSpace($ruleIdValue)) { throw "skill-tools SARIF rule ID must be a non-empty string for '$SkillId'." }
        if ($ruleById.ContainsKey([string]$ruleIdValue)) { throw "skill-tools SARIF contains a duplicate rule ID for '$SkillId'." }
        $ruleById.Add([string]$ruleIdValue, $rule)
    }
    $findings = @()
    foreach ($result in $results) {
        $ruleIdValue = Get-PropertyValue -Object $result -Name 'ruleId' -Context 'skill-tools SARIF result'
        if ($ruleIdValue -isnot [string] -or [string]::IsNullOrWhiteSpace($ruleIdValue)) { throw "skill-tools SARIF result ruleId must be a non-empty string for '$SkillId'." }
        $ruleId = [string]$ruleIdValue
        if (-not $ruleById.ContainsKey($ruleId)) { throw "skill-tools SARIF references an unknown rule for '$SkillId'." }
        $levelValue = if ($null -ne $result.PSObject.Properties['level']) {
            Get-ScalarProperty -Object $result -Name 'level' -Context 'skill-tools SARIF result'
        }
        else {
            $defaultConfiguration = Get-ScalarProperty -Object $ruleById[$ruleId] -Name 'defaultConfiguration' -Context 'skill-tools SARIF rule'
            Get-ScalarProperty -Object $defaultConfiguration -Name 'level' -Context 'skill-tools SARIF rule default'
        }
        if ($levelValue -isnot [string] -or [string]::IsNullOrWhiteSpace($levelValue)) { throw "skill-tools SARIF level must be a non-empty string for '$SkillId'." }
        $level = [string]$levelValue
        if ($level -notin @('none', 'note', 'warning', 'error')) { throw "skill-tools SARIF level is malformed for '$SkillId'." }
        if ($level -in @('warning', 'error')) { throw "skill-tools SARIF contains a blocking result for '$SkillId'." }
        $message = Get-ScalarProperty -Object $result -Name 'message' -Context 'skill-tools SARIF result'
        $messageTextValue = Get-ScalarProperty -Object $message -Name 'text' -Context 'skill-tools SARIF message'
        if ($messageTextValue -isnot [string] -or [string]::IsNullOrWhiteSpace($messageTextValue)) { throw "skill-tools SARIF message text must be a non-empty string for '$SkillId'." }
        $messageText = [string]$messageTextValue
        $locations = Get-PropertyValue -Object $result -Name 'locations' -Context 'skill-tools SARIF result'
        if ($null -eq $locations) { $locations = @() }
        elseif ($locations -isnot [array]) { throw "skill-tools SARIF locations must be an array for '$SkillId'." }
        else { $locations = @($locations) }
        if ($locations.Count -eq 0) { throw "skill-tools SARIF lacks candidate-bound evidence for '$SkillId'." }
        foreach ($location in $locations) {
            $physical = Get-ScalarProperty -Object $location -Name 'physicalLocation' -Context 'skill-tools SARIF location'
            $artifact = Get-ScalarProperty -Object $physical -Name 'artifactLocation' -Context 'skill-tools SARIF physical location'
            $uriValue = Get-ScalarProperty -Object $artifact -Name 'uri' -Context 'skill-tools SARIF artifact location'
            if ($uriValue -isnot [string]) { throw "skill-tools SARIF artifact location URI must be a string for '$SkillId'." }
            [void](Resolve-ReportedFilePath -Value $uriValue -SkillRoot $SkillRoot -ExpectedPaths $Inventory -Context 'skill-tools SARIF artifact location')
        }
        if ($level -eq 'note') {
            $findings += [ordered]@{ severity = 'informational'; fingerprint = Get-TextSha256 -Text ($result | ConvertTo-Json -Depth 20 -Compress); ruleId = $ruleId; message = $messageText; path = ''; skillId = $SkillId }
        }
    }
    return ,$findings
}
function Assert-SkillSpectorReport {
    param(
        [Parameter(Mandatory = $true)] $Report,
        [Parameter(Mandatory = $true)][string] $SkillRoot,
        [Parameter(Mandatory = $true)][string] $SkillId,
        [Parameter(Mandatory = $true)][string[]] $Inventory,
        [string] $Stage = 'skillspector-static'
    )
    $execution = Get-ScalarProperty -Object $Report -Name 'execution_successful' -Context 'SkillSpector report'
    $completeness = Get-ScalarProperty -Object $Report -Name 'analysis_completeness' -Context 'SkillSpector report'
    $completenessExecution = Get-ScalarProperty -Object $completeness -Name 'execution_successful' -Context 'SkillSpector completeness'
    $isComplete = Get-ScalarProperty -Object $completeness -Name 'is_complete' -Context 'SkillSpector completeness'
    $statusValue = Get-ScalarProperty -Object $completeness -Name 'status' -Context 'SkillSpector completeness'
    $coveragePercent = Get-PropertyValue -Object $completeness -Name 'coverage_percent' -Context 'SkillSpector completeness'
    $coverageType = if ($null -eq $coveragePercent) { [TypeCode]::Empty } else { [Convert]::GetTypeCode($coveragePercent) }
    if ($execution -isnot [bool] -or -not $execution -or
        $completenessExecution -isnot [bool] -or
        -not $completenessExecution -or
        $isComplete -isnot [bool] -or
        -not $isComplete -or
        $statusValue -isnot [string] -or
        [string]$statusValue -cne 'complete' -or
        $coverageType -notin @([TypeCode]::Byte, [TypeCode]::SByte, [TypeCode]::UInt16, [TypeCode]::UInt32, [TypeCode]::UInt64, [TypeCode]::Int16, [TypeCode]::Int32, [TypeCode]::Int64, [TypeCode]::Single, [TypeCode]::Double, [TypeCode]::Decimal) -or
        [double]$coveragePercent -ne 100) {
        throw "SkillSpector did not prove complete static analysis for '$SkillId'."
    }
    foreach ($name in @('ledger_exceptions', 'scope_exclusions', 'limitations')) {
        $items = Get-PropertyValue -Object $completeness -Name $name -Context 'SkillSpector completeness'
        if ($null -eq $items) { $items = @() }
        elseif ($items -isnot [array]) { throw "SkillSpector completeness '$name' must be an array for '$SkillId'." }
        else { $items = @($items) }
        if ($items.Count -ne 0) { throw "SkillSpector reported incomplete '$name' evidence for '$SkillId'." }
    }
    $skill = Get-ScalarProperty -Object $Report -Name 'skill' -Context 'SkillSpector report'
    $skillName = Get-ScalarProperty -Object $skill -Name 'name' -Context 'SkillSpector skill identity'
    $skillSource = Get-ScalarProperty -Object $skill -Name 'source' -Context 'SkillSpector skill identity'
    if ($skillName -isnot [string] -or [string]$skillName -cne $SkillId -or
        $skillSource -isnot [string] -or -not (Test-PathEqual -Left ([string]$skillSource) -Right $SkillRoot)) {
        throw "SkillSpector report identity does not match '$SkillId'."
    }
    $components = Get-PropertyValue -Object $Report -Name 'components' -Context 'SkillSpector report'
    if ($null -eq $components) { $components = @() }
    elseif ($components -isnot [array]) { throw "SkillSpector report components must be an array for '$SkillId'." }
    else { $components = @($components) }
    if ($components.Count -ne $Inventory.Count) { throw "SkillSpector did not cover the exact inventory for '$SkillId'." }
    $observed = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($component in $components) {
        $pathValue = Get-ScalarProperty -Object $component -Name 'path' -Context 'SkillSpector component'
        if ($pathValue -isnot [string]) { throw "SkillSpector component path must be a string for '$SkillId'." }
        $path = [string]$pathValue
        if (-not ($Inventory -ccontains $path) -or -not $observed.Add($path)) { throw "SkillSpector did not cover the exact inventory for '$SkillId'." }
    }
    # Raw JSON array paths are validated before this function; preserve the
    # deserialized property identity so singleton arrays remain distinguishable.
    $issues = Get-PropertyValue -Object $Report -Name 'issues' -Context 'SkillSpector report'
    if ($null -eq $issues) { $issues = @() }
    elseif ($issues -isnot [array]) { throw "SkillSpector report issues must be an array for '$SkillId'." }
    else { $issues = @($issues) }
    $findings = @()
    foreach ($issue in $issues) { $findings += New-Finding -Issue $issue -SkillId $SkillId -Stage $Stage }
    return ,$findings
}

try {
    $toolchain = Read-Json -Path $ToolchainPath -Context 'run-owned validation toolchain'
    Assert-FileIdentity -Path $ToolchainPath -Sha256 $ToolchainSha256 -Context 'run-owned validation toolchain'
    $candidateRoot = [IO.Path]::GetFullPath([string]$env:STANDARD_VALIDATION_CANDIDATE_ROOT)
    if ($Mode -eq 'skill-validator') {
        Assert-FileIdentity -Path ([string]$toolchain.centralRunnerPath) -Sha256 ([string]$toolchain.centralRunnerSha256) -Context 'central validation runner'
        $sharedReportFunctions = & {
            param($RunnerPath, $CandidateRoot, $ToolchainPath)
            . $RunnerPath -DefineFunctionsOnly -CandidateRoot $CandidateRoot -AdapterPath $ToolchainPath `
                -ArtifactsRoot ([IO.Path]::GetFullPath((Get-Location).Path)) -SourceRepository 'https://example.test' `
                -SourceRevision ('0' * 40) -BaseRevision ('0' * 40)
            $exports = @{}
            foreach ($name in @(
                'Get-StandardValidationFullPath',
                'Get-StandardValidationCaseVariant',
                'Get-StandardValidationPathCaseBehavior',
                'Get-StandardValidationPathComparison',
                'Test-StandardValidationSameResolvedPath',
                'Assert-StandardValidationSkillValidatorReport'
            )) {
                $exports[$name] = (Get-Command $name -CommandType Function -ErrorAction Stop).ScriptBlock
            }
            return $exports
        } ([string]$toolchain.centralRunnerPath) $candidateRoot $ToolchainPath
        foreach ($name in $sharedReportFunctions.Keys) {
            Set-Item -Path "function:$name" -Value $sharedReportFunctions[$name]
        }
    }
    $activeSkills = @(Get-ActiveSkills)
    $candidateId = [string]$env:STANDARD_VALIDATION_CANDIDATE_ID
    if ([string]::IsNullOrWhiteSpace($candidateId)) { throw 'Central runner did not provide a candidate identity.' }
    Assert-FileIdentity -Path $GitEntryModeManifestPath -Sha256 $GitEntryModeManifestSha256 -Context 'candidate Git entry manifest'
    $snapshotManifest = Read-SnapshotBlobManifest -Path $GitEntryModeManifestPath -ExpectedCommit $SourceRevision
    Assert-CandidateSnapshotMatchesManifest -CandidateRoot $candidateRoot -Manifest $snapshotManifest

    switch ($Mode) {
        'package-adapter' {
            Assert-FileIdentity -Path ([string]$toolchain.upstreamAdapterValidatorPath) -Sha256 ([string]$toolchain.upstreamAdapterValidatorSha256) -Context 'upstream adapter validator'
            Assert-FileIdentity -Path ([string]$toolchain.upstreamPolicyPath) -Sha256 ([string]$toolchain.upstreamPolicySha256) -Context 'upstream adapter policy'
            $reportPath = Join-Path (Get-Location) 'upstream-adapter-report.json'
            & ([string]$toolchain.upstreamAdapterValidatorPath) -PackageRoot $candidateRoot -PolicyPath ([string]$toolchain.upstreamPolicyPath) -SourceRepository $SourceRepository -SourceRevision $SourceRevision -ArchiveSha256 $ArchiveSha256 -OutputPath $reportPath | Out-Null
            $report = Read-Json -Path $reportPath -Context 'upstream adapter report'
            $statusValue = Get-ScalarProperty -Object $report -Name 'status' -Context 'upstream adapter report'
            $decisionValue = Get-ScalarProperty -Object $report -Name 'decision' -Context 'upstream adapter report'
            if ($statusValue -isnot [string] -or $decisionValue -isnot [string]) { throw 'Upstream adapter report status and decision must be strings.' }
            $status = [string]$statusValue
            $decision = [string]$decisionValue
            if (($status -eq 'passed' -and $decision -ne 'PASS') -or ($status -eq 'not-applicable' -and $decision -ne 'NOT_APPLICABLE') -or $status -notin @('passed', 'not-applicable')) { throw 'Upstream adapter report did not pass or prove not-applicable.' }
            New-Envelope -ActiveSkills $activeSkills -Additional @{ adapterStatus = $status; adapterSurfaces = @($report.surfaces); semanticRequired = $false }
        }
        'skill-validator' {
            $skillId = [string]$env:STANDARD_VALIDATION_SKILL_ID
            $skillRoot = Get-SkillRoot -SkillId $skillId
            $inventory = Get-InventoryPaths -SkillRoot $skillRoot
            Assert-FileIdentity -Path ([string]$toolchain.skillValidatorPath) -Sha256 ([string]$toolchain.skillValidatorSha256) -Context 'skill-validator executable'
            $report = Invoke-NativeJson -Command ([string]$toolchain.skillValidatorPath) -Arguments @('-o', 'json', 'validate', 'structure', '--allow-dirs=agents', $skillRoot) -Context "skill-validator '$skillId'" -ArrayPropertyPaths @('results')
            $findings = Assert-SkillValidatorReport -Report $report -SkillRoot $skillRoot -Inventory $inventory -SkillId $skillId
            New-Envelope -ActiveSkills $activeSkills -Findings $findings -Additional @{ skillId = $skillId; skillInventorySha256 = [string]$env:STANDARD_VALIDATION_SKILL_INVENTORY_SHA256; semanticRequired = $false }
        }
        'skill-tools' {
            $skillId = [string]$env:STANDARD_VALIDATION_SKILL_ID
            $skillRoot = Get-SkillRoot -SkillId $skillId
            $inventory = Get-InventoryPaths -SkillRoot $skillRoot
            Assert-FileIdentity -Path ([string]$toolchain.skillToolsNodePath) -Sha256 ([string]$toolchain.skillToolsNodeSha256) -Context 'skill-tools Node runtime'
            Assert-FileIdentity -Path ([string]$toolchain.skillToolsEntryPointPath) -Sha256 ([string]$toolchain.skillToolsEntryPointSha256) -Context 'skill-tools entry point'
            $report = Invoke-NativeJson -Command ([string]$toolchain.skillToolsNodePath) -Arguments @([string]$toolchain.skillToolsEntryPointPath, 'check', $skillRoot, '--format', 'sarif', '--fail-on', 'warning', '--min-score', '91') -Context "skill-tools '$skillId'" -ArrayPropertyPaths @('runs', 'runs[].tool.driver.rules', 'runs[].results', 'runs[].results[].locations')
            $findings = Assert-SkillToolsReport -Report $report -SkillRoot $skillRoot -Inventory $inventory -SkillId $skillId
            New-Envelope -ActiveSkills $activeSkills -Findings $findings -Additional @{ skillId = $skillId; skillInventorySha256 = [string]$env:STANDARD_VALIDATION_SKILL_INVENTORY_SHA256; semanticRequired = $false }
        }
        'static' {
            Assert-FileIdentity -Path ([string]$toolchain.skillSpectorPath) -Sha256 ([string]$toolchain.skillSpectorSha256) -Context 'SkillSpector executable'
            $skillspectorArrayPropertyPaths = @(
                'components',
                'issues',
                'analysis_completeness.ledger_exceptions',
                'analysis_completeness.scope_exclusions',
                'analysis_completeness.limitations'
            )
            $findings = @()
            foreach ($skillId in $activeSkills) {
                $skillRoot = Get-SkillRoot -SkillId $skillId
                $inventory = Get-InventoryPaths -SkillRoot $skillRoot
                $reportPath = Join-Path (Get-Location) ("skillspector-$skillId.json")
                $staticArguments = @('scan', $skillRoot, '--no-llm', '--format', 'json', '--output', $reportPath)
                $staticRawId = [guid]::NewGuid().ToString('N')
                $staticStdoutPath = Join-Path (Get-Location) "native-raw-skillspector-$staticRawId.stdout.txt"
                $staticStderrPath = Join-Path (Get-Location) "native-raw-skillspector-$staticRawId.stderr.txt"
                & ([string]$toolchain.skillSpectorPath) @staticArguments 1> $staticStdoutPath 2> $staticStderrPath
                $staticExitCode = $LASTEXITCODE
                $staticStdoutSha256 = Get-FileSha256 -Path $staticStdoutPath
                $staticStderrSha256 = Get-FileSha256 -Path $staticStderrPath
                if ($staticExitCode -ne 0) { throw "SkillSpector static scan failed for '$skillId' with exit code $staticExitCode." }
                if ($Mode -ceq 'static') {
                    $script:NativeReports += [ordered]@{
                        skillId = $skillId
                        path = [IO.Path]::GetFullPath($reportPath)
                        sha256 = Get-FileSha256 -Path $reportPath
                        stdoutPath = [IO.Path]::GetFullPath($staticStdoutPath)
                        stdoutSha256 = $staticStdoutSha256
                        stderrPath = [IO.Path]::GetFullPath($staticStderrPath)
                        stderrSha256 = $staticStderrSha256
                        command = [IO.Path]::GetFullPath([string]$toolchain.skillSpectorPath)
                        commandSha256 = Get-FileSha256 -Path ([string]$toolchain.skillSpectorPath)
                        arguments = @($staticArguments)
                        exitCode = $staticExitCode
                    }
                }
                $report = Read-Json -Path $reportPath -Context "SkillSpector report for '$skillId'" -ArrayPropertyPaths $skillspectorArrayPropertyPaths
                $findings += Assert-SkillSpectorReport -Report $report -SkillRoot $skillRoot -SkillId $skillId -Inventory $inventory
            }
            $semanticTriggered = ($SemanticRequired -ceq 'true') -or $findings.Count -gt 0
            $semanticFindings = @()
            if ($semanticTriggered) {
                foreach ($skillId in $activeSkills) {
                    $skillRoot = Get-SkillRoot -SkillId $skillId
                    $inventory = Get-InventoryPaths -SkillRoot $skillRoot
                    $semanticReportPath = Join-Path (Get-Location) ("skillspector-semantic-$skillId.json")
                    & ([string]$toolchain.skillSpectorPath) scan $skillRoot --format json --output $semanticReportPath | Out-Null
                    if ($LASTEXITCODE -ne 0) { throw "SkillSpector semantic scan failed for '$skillId' with exit code $LASTEXITCODE." }
                    $semanticReport = Read-Json -Path $semanticReportPath -Context "SkillSpector semantic report for '$skillId'" -ArrayPropertyPaths $skillspectorArrayPropertyPaths
                    $semanticFindings += Assert-SkillSpectorReport -Report $semanticReport -SkillRoot $skillRoot -SkillId $skillId -Inventory $inventory -Stage 'conditional-semantic-scan'
                }
            }
            $findings += $semanticFindings
            $semanticStatus = if ($semanticTriggered) { 'passed' } else { 'not-run' }
            New-Envelope -ActiveSkills $activeSkills -Findings $findings -Additional @{ scannerIdentity = 'SkillSpector'; analyzerCompleteness = 'complete'; semanticRequired = $semanticTriggered; semanticScan = [ordered]@{ triggered = $semanticTriggered; status = $semanticStatus; findingCount = @($semanticFindings).Count } }
        }
        'repository-knowledge' {
            $validatorPath = Join-Path $candidateRoot 'scripts/Test-Repository.ps1'
            if (-not (Test-Path -LiteralPath $validatorPath -PathType Leaf)) { throw 'Test-Repository.ps1 is missing from the candidate snapshot.' }
            $reportPath = Join-Path (Get-Location) 'repository-integrity-report.json'
            & $validatorPath -RepositoryRoot $candidateRoot -OutputPath $reportPath -ReadOnlySnapshot -GitEntryModeManifestPath $GitEntryModeManifestPath *> $null
            $report = Read-Json -Path $reportPath -Context 'Test-Repository report'
            if ([string]$report.result -cne 'passed' -or [int]$report.activeSkillCount -ne $activeSkills.Count) { throw 'Test-Repository did not pass the complete active Skill inventory.' }
            $reportedSkills = @($report.skills | ForEach-Object { [string]$_.skillId })
            if ((@($reportedSkills | Sort-Object) -join "`n") -cne (@($activeSkills | Sort-Object) -join "`n")) { throw 'Test-Repository reported a different active Skill inventory.' }
            $testInventory = @($activeSkills | ForEach-Object { "domain-inventory:$($_)" })
            New-Envelope -ActiveSkills $activeSkills -Additional @{ testInventory = $testInventory; testResult = [ordered]@{ status = 'passed'; decision = 'PASS'; result = 'Test-Repository' }; domainAdapterResult = [ordered]@{ status = 'passed'; decision = 'PASS'; result = 'Code-Collaboration-domain-contract' } }
        }
        'repository-catalog' {
            $validatorPath = Join-Path $candidateRoot 'tests/validate-catalog.ps1'
            if (-not (Test-Path -LiteralPath $validatorPath -PathType Leaf)) { throw 'validate-catalog.ps1 is missing from the candidate snapshot.' }
            $reportPath = Join-Path (Get-Location) 'repository-catalog-report.json'
            & $validatorPath -RepositoryRoot $candidateRoot -OutputPath $reportPath *> $null
            $report = Read-Json -Path $reportPath -Context 'profile catalog report'
            if ([string]$report.result -cne 'passed' -or [int]$report.activeSkillCount -ne $activeSkills.Count) { throw 'Profile catalog validation did not cover the complete active Skill inventory.' }
            $reportedSkills = @($report.skills | ForEach-Object { [string]$_.skillId })
            if ((@($reportedSkills | Sort-Object) -join "`n") -cne (@($activeSkills | Sort-Object) -join "`n")) { throw 'Profile catalog reported a different active Skill inventory.' }
            $testInventory = @($activeSkills | ForEach-Object { "catalog-inventory:$($_)" })
            New-Envelope -ActiveSkills $activeSkills -Additional @{ testInventory = $testInventory; testResult = [ordered]@{ status = 'passed'; decision = 'PASS'; result = 'validate-catalog' }; domainAdapterResult = [ordered]@{ status = 'passed'; decision = 'PASS'; result = 'Code-Collaboration-profile-catalog' } }
        }
        'repository-pester' {
            Assert-FileIdentity -Path ([string]$toolchain.pesterModulePath) -Sha256 ([string]$toolchain.pesterModuleSha256) -Context 'Pester module'
            Import-Module -Name ([string]$toolchain.pesterModulePath) -Force -ErrorAction Stop
            $loaded = Get-Module Pester | Select-Object -First 1
            if ($null -eq $loaded -or [string]$loaded.Version -cne [string]$toolchain.pesterVersion) { throw 'The resolved Pester module identity was not loaded.' }
            $testRoot = Join-Path $candidateRoot 'tests'
            $result = Invoke-Pester -Path $testRoot -Output None -PassThru 6>$null
            $failedTests = @()
            if ($null -ne $result -and $null -ne $result.PSObject.Properties['Tests']) {
                $failedTests = @($result.Tests | Where-Object { [string]$_.Result -eq 'Failed' } | ForEach-Object {
                    $name = if ($null -ne $_.PSObject.Properties['ExpandedName']) { [string]$_.ExpandedName } else { [string]$_.Name }
                    $message = if ($null -ne $_.PSObject.Properties['ErrorRecord'] -and $null -ne $_.ErrorRecord) {
                        [string]$_.ErrorRecord.Exception.Message
                    }
                    else { '' }
                    if ([string]::IsNullOrWhiteSpace($message)) { $name } else { "${name}: $message" }
                })
            }
            if ($null -eq $result -or [int64]$result.TotalCount -le 0 -or [int64]$result.FailedCount -ne 0 -or
                [int64]$result.PassedCount + [int64]$result.SkippedCount -ne [int64]$result.TotalCount) {
                $detail = if ($failedTests.Count -gt 0) { $failedTests -join ' | ' } else { 'Pester did not expose failed test details.' }
                [Console]::Error.WriteLine("Pester failure details: $detail")
                throw 'Pester repository regression did not complete successfully.'
            }
            $testInventory = @(
                Get-ChildItem -LiteralPath $testRoot -Recurse -File -Force |
                    ForEach-Object { [IO.Path]::GetRelativePath($candidateRoot, $_.FullName).Replace([IO.Path]::DirectorySeparatorChar, '/') }
            )
            if ($testInventory.Count -eq 0) { throw 'Pester did not receive a non-empty test inventory.' }
            New-Envelope -ActiveSkills $activeSkills -Additional @{ testInventory = $testInventory; testResult = [ordered]@{ status = 'passed'; decision = 'PASS'; total = [int64]$result.TotalCount; passed = [int64]$result.PassedCount; skipped = [int64]$result.SkippedCount }; domainAdapterResult = [ordered]@{ status = 'passed'; decision = 'PASS'; result = 'Pester' } }
        }
    }
}
catch {
    [Console]::Error.WriteLine($_.Exception.Message)
    exit 1
}
'@

function Write-Utf8NoBomCreateNew {
    param([Parameter(Mandatory = $true)][string] $Path, [Parameter(Mandatory = $true)][string] $Text)
    $fullPath = [IO.Path]::GetFullPath($Path)
    $parent = Split-Path -Parent $fullPath
    [void](New-Item -ItemType Directory -Path $parent -Force -ErrorAction Stop)
    Assert-NoReparseAncestors -Path $parent -Context 'Run-owned file parent'
    $bytes = [Text.UTF8Encoding]::new($false).GetBytes($Text)
    $stream = [IO.FileStream]::new($fullPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::Read)
    try { $stream.Write($bytes, 0, $bytes.Length); $stream.Flush($true) }
    finally { $stream.Dispose() }
    return $fullPath
}

function Copy-CodeSourcePowerShellRuntime {
    param(
        [Parameter(Mandatory)][string] $PowerShellPath,
        [Parameter(Mandatory)][string] $TrustedToolRoot,
        [Parameter(Mandatory)][string] $OwnedRoot
    )

    $sourceExecutable = [IO.Path]::GetFullPath($PowerShellPath)
    $sourceRoot = [IO.Path]::GetFullPath((Split-Path -Parent $sourceExecutable))
    $runtimeExecutableName = if ($IsWindows) { 'pwsh.exe' } else { 'pwsh' }
    if ([IO.Path]::GetFileName($sourceExecutable) -ine $runtimeExecutableName -or
        -not (Test-Path -LiteralPath $sourceExecutable -PathType Leaf) -or
        -not (Test-PathWithinOrEqual -Path $sourceExecutable -Root $TrustedToolRoot)) {
        throw "Source runtime copy requires the exact $runtimeExecutableName inside TrustedToolRoot."
    }
    Assert-NoReparseAncestors -Path $sourceExecutable -Context 'Trusted source PowerShell executable'
    $runtimeRoot = Assert-PathWithinRoot -Path (Join-Path $OwnedRoot 'runtime') -Root $OwnedRoot -Context 'Run-owned PowerShell runtime'
    if (Test-Path -LiteralPath $runtimeRoot) { throw 'Run-owned PowerShell runtime destination already exists.' }
    [void](New-Item -ItemType Directory -Path $runtimeRoot -ErrorAction Stop)

    $sourcePrefix = $sourceRoot.TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
    foreach ($item in @(Get-ChildItem -LiteralPath $sourceRoot -Force -Recurse -ErrorAction Stop)) {
        $sourceItemPath = [IO.Path]::GetFullPath($item.FullName)
        if (-not $sourceItemPath.StartsWith($sourcePrefix, $(if ($IsWindows) { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal }))) {
            throw 'Trusted PowerShell runtime inventory escaped its installation root.'
        }
        $relative = [IO.Path]::GetRelativePath($sourceRoot, $sourceItemPath)
        $relativeSegments = @($relative -split '[\\/]')
        if ($relativeSegments.Count -ge 2 -and $relativeSegments[0] -ieq 'Modules' -and $relativeSegments[1] -ieq 'Pester') {
            continue
        }
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
            throw "Trusted PowerShell runtime contains an unexpected reparse point: $sourceItemPath"
        }
        $target = Join-Path $runtimeRoot $relative
        if ($item.PSIsContainer) {
            [void](New-Item -ItemType Directory -Path $target -Force -ErrorAction Stop)
            continue
        }
        $targetParent = Split-Path -Parent $target
        [void](New-Item -ItemType Directory -Path $targetParent -Force -ErrorAction Stop)
        [IO.File]::Copy($sourceItemPath, $target, $false)
    }
    $ownedExecutable = [IO.Path]::GetFullPath((Join-Path $runtimeRoot ([IO.Path]::GetFileName($sourceExecutable))))
    if (-not (Test-Path -LiteralPath $ownedExecutable -PathType Leaf)) { throw "Run-owned PowerShell runtime copy is missing $runtimeExecutableName." }
    Assert-NoReparseAncestors -Path $runtimeRoot -Context 'Run-owned PowerShell runtime'
    $ownedExecutableHash = Get-FileSha256 -Path $ownedExecutable
    $ownedFiles = @(Get-ChildItem -LiteralPath $runtimeRoot -Recurse -File -Force -ErrorAction Stop | ForEach-Object {
        if ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Run-owned PowerShell runtime contains a reparse point: $($_.FullName)" }
        [pscustomobject]@{ path = [IO.Path]::GetFullPath($_.FullName); sha256 = Get-FileSha256 -Path $_.FullName }
    })
    if ($ownedFiles.Count -eq 0 -or @($ownedFiles | Where-Object { Test-PathEqual -Left ([string]$_.path) -Right $ownedExecutable }).Count -ne 1) {
        throw 'Run-owned PowerShell runtime inventory is empty or does not contain its exact executable.'
    }
    return [pscustomobject]@{ root = $runtimeRoot; executablePath = $ownedExecutable; executableSha256 = $ownedExecutableHash; files = $ownedFiles }
}

function Get-CodeSourceReceiptFrozenPaths {
    param([Parameter(Mandatory = $true)] $Receipt, [Parameter(Mandatory = $true)][string] $OwnedRoot)

    $paths = [Collections.Generic.List[string]]::new()
    $installRoot = [IO.Path]::GetFullPath([string]$Receipt.installRoot)
    $installedRoot = [IO.Path]::GetFullPath((Join-Path $OwnedRoot 'installed'))
    [void](Assert-PathWithinRoot -Path $installRoot -Root $installedRoot -Context 'Resolved source tool install root')
    if (-not (Test-Path -LiteralPath $installRoot -PathType Container)) { throw 'Resolved source tool install root is missing.' }
    foreach ($item in @(Get-ChildItem -LiteralPath $installRoot -Force -Recurse -ErrorAction Stop)) {
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Resolved source tool closure contains a reparse point: $($item.FullName)" }
        if (-not $item.PSIsContainer) { $paths.Add([IO.Path]::GetFullPath($item.FullName)) }
    }
    if ($paths.Count -eq 0) { throw 'Resolved source tool installed closure is empty.' }

    $pathHashPairs = @(
        @('executablePath', 'executableSha256'),
        @('entryPointPath', 'entryPointSha256'),
        @('nodePath', 'nodeSha256'),
        @('goRuntimePath', 'goRuntimeSha256'),
        @('resolverHelperPath', 'resolverHelperSha256')
    )
    foreach ($pair in $pathHashPairs) {
        $pathProperty = $Receipt.PSObject.Properties[[string]$pair[0]]
        if ($null -eq $pathProperty -or [string]::IsNullOrWhiteSpace([string]$pathProperty.Value)) { continue }
        $hashProperty = $Receipt.PSObject.Properties[[string]$pair[1]]
        $filePath = [IO.Path]::GetFullPath([string]$pathProperty.Value)
        if ($null -eq $hashProperty -or [string]$hashProperty.Value -cnotmatch '^[0-9a-f]{64}$' -or
            -not (Test-Path -LiteralPath $filePath -PathType Leaf) -or
            (Get-FileSha256 -Path $filePath) -cne [string]$hashProperty.Value) {
            throw "Resolved source tool path/hash pair is incomplete or changed: $($pair[0])"
        }
        Assert-NoReparseAncestors -Path $filePath -Context "Resolved source tool $($pair[0])"
        $paths.Add($filePath)
    }
    $launcher = $Receipt.PSObject.Properties['launcher']
    if ($null -ne $launcher -and $null -ne $launcher.Value) {
        foreach ($pair in @(@('shimPath', 'shimSha256'), @('payloadPath', 'payloadSha256'), @('runtimePath', 'runtimeSha256'))) {
            $pathProperty = $launcher.Value.PSObject.Properties[[string]$pair[0]]
            if ($null -eq $pathProperty -or [string]::IsNullOrWhiteSpace([string]$pathProperty.Value)) { continue }
            $hashProperty = $launcher.Value.PSObject.Properties[[string]$pair[1]]
            $filePath = [IO.Path]::GetFullPath([string]$pathProperty.Value)
            if ($null -eq $hashProperty -or [string]$hashProperty.Value -cnotmatch '^[0-9a-f]{64}$' -or
                -not (Test-Path -LiteralPath $filePath -PathType Leaf) -or
                (Get-FileSha256 -Path $filePath) -cne [string]$hashProperty.Value) {
                throw "Resolved source tool launcher path/hash pair is incomplete or changed: $($pair[0])"
            }
            Assert-NoReparseAncestors -Path $filePath -Context "Resolved source tool launcher $($pair[0])"
            $paths.Add($filePath)
        }
    }
    return @($paths | Select-Object -Unique)
}

function Assert-CodeSourceAuthorityCheckout {
    param([Parameter(Mandatory)][string] $GitPath, [Parameter(Mandatory)][string] $AuthorityRoot, [Parameter(Mandatory)] $AuthorityPin)

    $root = [IO.Path]::GetFullPath($AuthorityRoot)
    if (-not (Test-Path -LiteralPath $root -PathType Container)) { throw "Pinned source authority checkout is missing: $root" }
    Assert-NoReparseAncestors -Path $root -Context 'Pinned source authority checkout'
    $top = @(& $GitPath -C $root rev-parse --show-toplevel 2>$null)
    if ($LASTEXITCODE -ne 0 -or $top.Count -ne 1 -or -not (Test-PathEqual -Left ([string]$top[0]) -Right $root)) {
        throw 'Pinned source authority path is not the root of a Git checkout.'
    }
    $head = Resolve-GitRevision -GitPath $GitPath -Root $root -Revision 'HEAD' -Context 'Pinned source authority HEAD'
    if ($head -cne [string]$AuthorityPin.commit) { throw 'Pinned source authority HEAD does not match the approved ff85 revision.' }
    $origins = @(& $GitPath -C $root config --local --get-all remote.origin.url 2>$null)
    if ($LASTEXITCODE -ne 0 -or $origins.Count -ne 1) { throw 'Pinned source authority checkout must have exactly one origin URL.' }
    $origin = ([string]$origins[0]).Trim().TrimEnd('/') -replace '\.git$', ''
    $expectedOrigin = ([string]$AuthorityPin.repository).Trim().TrimEnd('/') -replace '\.git$', ''
    if (-not $origin.Equals($expectedOrigin, [StringComparison]::OrdinalIgnoreCase)) { throw 'Pinned source authority origin differs from the approved repository.' }
    $dirty = @(& $GitPath -C $root status --porcelain=v1 --untracked-files=all)
    if ($LASTEXITCODE -ne 0 -or $dirty.Count -ne 0) { throw 'Pinned source authority checkout must be clean and immutable.' }
    foreach ($entry in $AuthorityPin.files.GetEnumerator()) {
        $path = Assert-PathWithinRoot -Path (Join-Path $root ($entry.Key -replace '/', [IO.Path]::DirectorySeparatorChar)) -Root $root -Context 'Pinned source authority file'
        Assert-NoReparseAncestors -Path $path -Context 'Pinned source authority file'
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Pinned source authority file is missing: $($entry.Key)" }
        $blob = @(& $GitPath -C $root rev-parse --verify --end-of-options "$head`:$($entry.Key)" 2>$null)
        if ($LASTEXITCODE -ne 0 -or $blob.Count -ne 1 -or ([string]$blob[0]).Trim() -cnotmatch '^[0-9a-f]{40}$' -or
            (Get-GitBlobSha256 -GitPath $GitPath -RepositoryRoot $root -ObjectId ([string]$blob[0]).Trim()) -cne [string]$entry.Value -or
            (Get-FileSha256 -Path $path) -cne [string]$entry.Value) {
            throw "Pinned source authority Git blob or worktree bytes differ: $($entry.Key)"
        }
    }
    return [pscustomobject]@{ root = $root; runnerPath = (Join-Path $root 'scripts/Invoke-StandardValidation.ps1'); revision = $head }
}

function New-CodeSourceAuthoritySnapshot {
    param([Parameter(Mandatory)][string] $GitPath, [Parameter(Mandatory)][string] $SourceRoot,
        [Parameter(Mandatory)][string] $OwnedRoot, [Parameter(Mandatory)] $AuthorityPin)

    $snapshot = Assert-PathWithinRoot -Path (Join-Path $OwnedRoot 'authority') -Root $OwnedRoot -Context 'Source Core authority snapshot'
    if (Test-Path -LiteralPath $snapshot) { throw 'Source Core authority snapshot already exists.' }
    $hooksRoot = Join-Path $OwnedRoot '.empty-git-hooks'
    [void](New-Item -ItemType Directory -Path $hooksRoot -ErrorAction Stop)
    Assert-NoReparseAncestors -Path $hooksRoot -Context 'Source authority snapshot hooks'
    & $GitPath -c "core.hooksPath=$hooksRoot" -c core.autocrlf=false -c core.longpaths=true clone --quiet --local --no-hardlinks --no-checkout -- $SourceRoot $snapshot
    if ($LASTEXITCODE -ne 0) { throw 'Could not materialize protected source authority objects in the run-owned snapshot.' }
    foreach ($setting in @(@('core.autocrlf', 'false'), @('core.longpaths', 'true'))) {
        & $GitPath -C $snapshot config --local $setting[0] $setting[1]
        if ($LASTEXITCODE -ne 0) { throw "Could not set protected authority snapshot option $($setting[0])." }
    }
    $paths = @($AuthorityPin.files.Keys)
    & $GitPath -c "core.hooksPath=$hooksRoot" -C $snapshot sparse-checkout set --no-cone -- $paths
    if ($LASTEXITCODE -ne 0) { throw 'Could not select the exact approved ff85 authority closure.' }
    & $GitPath -C $snapshot config --local --replace-all remote.origin.url ([string]$AuthorityPin.repository)
    if ($LASTEXITCODE -ne 0) { throw 'Could not bind the source authority snapshot origin.' }
    & $GitPath -c "core.hooksPath=$hooksRoot" -c core.autocrlf=false -C $snapshot checkout --quiet --detach ([string]$AuthorityPin.commit)
    if ($LASTEXITCODE -ne 0) { throw 'Could not check out the exact ff85 source authority revision.' }
    return Assert-CodeSourceAuthorityCheckout -GitPath $GitPath -AuthorityRoot $snapshot -AuthorityPin $AuthorityPin
}

function Get-CodeSourceCoreRunPaths {
    param([Parameter(Mandatory)][string] $ArtifactsRoot, [Parameter(Mandatory)][bool] $ArtifactsRootWasExplicit,
        [Parameter(Mandatory)][string] $RunId, [string] $OutputPath)

    $requestedRoot = [IO.Path]::GetFullPath($ArtifactsRoot)
    if ($RunId -cnotmatch '^[0-9a-f]{32}$') { throw 'Prepared source RunId is invalid.' }
    $coreRoot = if ($ArtifactsRootWasExplicit) { $requestedRoot } else { Join-Path $requestedRoot "core-v2-$RunId" }
    $adapterParent = if ($ArtifactsRootWasExplicit) { Split-Path -Parent $coreRoot } else { $requestedRoot }
    if ([string]::IsNullOrWhiteSpace($adapterParent)) { throw 'Could not resolve a separate source adapter root.' }
    $adapterRoot = Join-Path $adapterParent ".core-v2-adapter-$RunId"
    if ((Test-PathWithinOrEqual -Path $adapterRoot -Root $coreRoot) -or (Test-PathWithinOrEqual -Path $coreRoot -Root $adapterRoot)) {
        throw 'Source Core adapter and artifacts root must be separate paths.'
    }
    $outputFull = if ([string]::IsNullOrWhiteSpace($OutputPath)) { Join-Path $coreRoot 'standard-core-validation-v2-report.json' }
        else { Assert-PathWithinRoot -Path $OutputPath -Root $coreRoot -Context 'Source OutputPath' }
    return [pscustomobject]@{ runId = $RunId; artifactsRoot = [IO.Path]::GetFullPath($coreRoot); adapterRoot = [IO.Path]::GetFullPath($adapterRoot); adapterPath = [IO.Path]::GetFullPath((Join-Path $adapterRoot 'standard-core-adapter-v2.json')); outputPath = [IO.Path]::GetFullPath($outputFull) }
}

function New-CodeSourceStandardValidationModule {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string] $RunnerPath,
        [Parameter(Mandatory = $true)][string] $RunnerSha256,
        [Parameter(Mandatory = $true)][System.Collections.IDictionary] $RunnerArguments,
        [switch] $SourceValidation
    )

    $runnerFullPath = [IO.Path]::GetFullPath($RunnerPath)
    if (-not [IO.Path]::IsPathRooted($RunnerPath) -or -not (Test-Path -LiteralPath $runnerFullPath -PathType Leaf)) {
        throw 'The protected Standard Core runner must be an existing absolute file.'
    }
    if ($RunnerSha256 -cnotmatch '^[0-9a-f]{64}$') { throw 'The protected Standard Core runner hash is invalid.' }
    if ((Get-FileHash -LiteralPath $runnerFullPath -Algorithm SHA256).Hash.ToLowerInvariant() -cne $RunnerSha256) {
        throw 'The protected Standard Core runner differs from its verified authority hash.'
    }

    $allowedNames = @(
        'CandidateRoot', 'AdapterPath', 'ArtifactsRoot', 'OutputPath', 'SourceRepository',
        'SourceRevision', 'BaseRevision', 'EventName', 'RunId', 'AuthorityRevision',
        'TimeoutSeconds', 'CancellationPath', 'TrustedToolRoot'
    )
    $requiredNames = @(
        'CandidateRoot', 'AdapterPath', 'ArtifactsRoot', 'OutputPath', 'SourceRepository',
        'SourceRevision', 'BaseRevision', 'EventName', 'RunId', 'AuthorityRevision',
        'TimeoutSeconds', 'CancellationPath', 'TrustedToolRoot'
    )
    $argumentNames = @($RunnerArguments.Keys | ForEach-Object { [string]$_ })
    foreach ($name in $argumentNames) {
        if ($name -cnotin $allowedNames) { throw "Unsupported protected Standard Core runner argument '$name'." }
    }
    foreach ($name in $requiredNames) {
        if (-not $RunnerArguments.Contains($name)) { throw "Protected Standard Core runner context is missing '$name'." }
    }
    foreach ($name in @('CandidateRoot', 'AdapterPath', 'ArtifactsRoot', 'TrustedToolRoot')) {
        $value = [string]$RunnerArguments[$name]
        if ([string]::IsNullOrWhiteSpace($value) -or -not [IO.Path]::IsPathRooted($value)) {
            throw "Protected Standard Core runner context '$name' must be an absolute path."
        }
    }
    foreach ($name in @('OutputPath', 'CancellationPath')) {
        $value = [string]$RunnerArguments[$name]
        if (-not [string]::IsNullOrWhiteSpace($value) -and -not [IO.Path]::IsPathRooted($value)) {
            throw "Protected Standard Core runner context '$name' must be empty or an absolute path."
        }
    }
    foreach ($name in @('SourceRepository', 'SourceRevision', 'BaseRevision', 'RunId', 'AuthorityRevision')) {
        if ([string]::IsNullOrWhiteSpace([string]$RunnerArguments[$name])) {
            throw "Protected Standard Core runner context '$name' must be nonempty."
        }
    }
    foreach ($name in @('SourceRevision', 'BaseRevision', 'AuthorityRevision')) {
        if ([string]$RunnerArguments[$name] -cnotmatch '^[0-9a-f]{40}$') {
            throw "Protected Standard Core runner context '$name' is not a canonical revision."
        }
    }
    if ([string]$RunnerArguments['RunId'] -cnotmatch '^[0-9a-f]{32}$') { throw 'Protected Standard Core runner RunId is invalid.' }
    if ([string]$RunnerArguments['EventName'] -cnotin @('local', 'pre-push', 'pull_request', 'push', 'workflow_dispatch')) {
        throw 'Protected Standard Core runner event is unsupported.'
    }
    if ([int]$RunnerArguments['TimeoutSeconds'] -le 0) { throw 'Protected Standard Core runner timeout must be positive.' }

    $importArguments = [ordered]@{}
    foreach ($name in $argumentNames) { $importArguments[$name] = $RunnerArguments[$name] }
    $importArguments['DefineFunctionsOnly'] = $true
    if ($SourceValidation) {
        $runnerTokens = $null
        $runnerErrors = $null
        $runnerAst = [Management.Automation.Language.Parser]::ParseFile($runnerFullPath, [ref]$runnerTokens, [ref]$runnerErrors)
        if ($runnerErrors.Count -ne 0 -or @($runnerAst.ParamBlock.Parameters | Where-Object {
            ([string]$_.Name.VariablePath.UserPath) -ceq 'SourceValidation'
        }).Count -ne 1) {
            throw 'The protected Standard Core runner does not expose the SourceValidation contract.'
        }
        $importArguments['SourceValidation'] = $true
    }

    $moduleName = 'CodeSourceStandardValidation_' + [guid]::NewGuid().ToString('N')
    $moduleArguments = @($runnerFullPath, $importArguments)
    $module = New-Module -Name $moduleName -ArgumentList $moduleArguments -ScriptBlock {
        param([string] $__runnerPath, [System.Collections.IDictionary] $__runnerArguments)
        . $__runnerPath @__runnerArguments
        Export-ModuleMember -Function @() -Cmdlet @() -Alias @() -Variable @()
    }
    if ($module -isnot [System.Management.Automation.PSModuleInfo] -or $module.Name -cne $moduleName) {
        throw 'Could not create an isolated Standard Core runner module.'
    }
    return $module
}

function Invoke-CodeSourceStandardValidationModule {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][System.Management.Automation.PSModuleInfo] $Module,
        [Parameter(Mandatory = $true)][string] $FunctionName,
        [Parameter(Mandatory = $true)][System.Collections.IDictionary] $Arguments
    )

    $allowedFunctions = @(
        'Invoke-StandardValidationProcess', 'Assert-StandardCoreFrozenFiles',
        'Assert-StandardCoreSourceToolReceipts', 'Assert-StandardCoreSourceCheckReport'
    )
    if ($FunctionName -cnotin $allowedFunctions) { throw "Protected Standard Core operation '$FunctionName' is not allowed." }
    $moduleInvoker = {
        param([string] $Name, [System.Collections.IDictionary] $BoundArguments)
        $command = Get-Command -Name $Name -CommandType Function -ErrorAction Stop
        $currentModule = [string]$ExecutionContext.SessionState.Module.Name
        if ([string]::IsNullOrWhiteSpace($currentModule) -or [string]$command.ModuleName -cne $currentModule) {
            throw 'Protected Standard Core operation is not owned by its isolated runner module.'
        }
        foreach ($argumentName in $BoundArguments.Keys) {
            if (-not $command.Parameters.ContainsKey([string]$argumentName)) {
                throw "Protected Standard Core operation '$Name' does not accept argument '$argumentName'."
            }
        }
        & $command @BoundArguments
    }
    return & $Module $moduleInvoker $FunctionName $Arguments
}

function Invoke-CodeSourceToolSetup {
    param([Parameter(Mandatory)][string] $GitPath, [Parameter(Mandatory)][string] $PowerShellPath,
        [Parameter(Mandatory)][string] $RepositoryRoot, [Parameter(Mandatory)][string] $CandidateRevision,
        [Parameter(Mandatory)] $AuthorityConfig, [Parameter(Mandatory)][string] $SourceToolsPath,
        [Parameter(Mandatory)][string] $AuthorityRepositoryRoot, [string] $TrustedToolRoot,
        [string] $ExpectedGoRuntimeVersion, [Parameter(Mandatory)][int] $TimeoutSeconds)

    $setupStartedAtUtc = [DateTimeOffset]::UtcNow
    $setupTimer = [Diagnostics.Stopwatch]::StartNew()
    $setupStageSeconds = [ordered]@{}
    $resolverStageSeconds = [ordered]@{}
    $pin = Assert-CodeSourceAuthorityConfig -Config $AuthorityConfig
    $authority = Assert-CodeSourceAuthorityCheckout -GitPath $GitPath -AuthorityRoot $AuthorityRepositoryRoot -AuthorityPin $pin
    $sourcePowerShell = [IO.Path]::GetFullPath($PowerShellPath)
    $trustedRoot = if ([string]::IsNullOrWhiteSpace($TrustedToolRoot)) { Split-Path -Parent $sourcePowerShell } else { [IO.Path]::GetFullPath($TrustedToolRoot) }
    if (-not (Test-Path -LiteralPath $trustedRoot -PathType Container)) { throw 'Trusted PowerShell tool root is missing.' }
    Assert-NoReparseAncestors -Path $trustedRoot -Context 'Trusted PowerShell tool root'
    if (-not (Test-PathWithinOrEqual -Path $sourcePowerShell -Root $trustedRoot)) { throw 'PowerShell executable must remain inside TrustedToolRoot.' }
    Assert-OutsideRoot -Path $trustedRoot -Root $RepositoryRoot -Context 'TrustedToolRoot'
    Assert-OutsideRoot -Path $trustedRoot -Root $authority.root -Context 'TrustedToolRoot'

    $preparedPath = [IO.Path]::GetFullPath($SourceToolsPath)
    $setupRoot = [IO.Path]::GetFullPath((Split-Path -Parent $preparedPath))
    if (-not (Test-Path -LiteralPath $setupRoot -PathType Container)) { [void](New-Item -ItemType Directory -Path $setupRoot -Force -ErrorAction Stop) }
    if (-not (Test-PathEqual -Left (Split-Path -Parent $preparedPath) -Right $setupRoot)) { throw 'SourceToolsPath must resolve directly within its setup root.' }
    if (Test-Path -LiteralPath $preparedPath) { throw 'Prepared source toolset output already exists.' }
    Assert-OutsideRoot -Path $setupRoot -Root $RepositoryRoot -Context 'Source setup artifacts'
    Assert-OutsideRoot -Path $setupRoot -Root $authority.root -Context 'Source setup artifacts'
    Assert-OutsideRoot -Path $setupRoot -Root $trustedRoot -Context 'Source setup artifacts'
    Assert-NoReparseAncestors -Path $setupRoot -Context 'Source setup artifacts'

    $runId = [guid]::NewGuid().ToString('N')
    $ownedRoot = Assert-PathWithinRoot -Path (Join-Path $setupRoot "source-tools-$runId") -Root $setupRoot -Context 'Source setup owned root'
    if (Test-Path -LiteralPath $ownedRoot) { throw 'Source setup run-owned root unexpectedly exists.' }
    [void](New-Item -ItemType Directory -Path $ownedRoot -ErrorAction Stop)
    Assert-NoReparseAncestors -Path $ownedRoot -Context 'Source setup owned root'
    $stageTimer = [Diagnostics.Stopwatch]::StartNew()
    $runtimeCopy = Copy-CodeSourcePowerShellRuntime -PowerShellPath $sourcePowerShell -TrustedToolRoot $trustedRoot -OwnedRoot $ownedRoot
    $stageTimer.Stop()
    $setupStageSeconds.runtimeCopyAndInventorySeconds = [Math]::Round($stageTimer.Elapsed.TotalSeconds, 3)
    $powerShell = [string]$runtimeCopy.executablePath
    $runtimeRoot = [string]$runtimeCopy.root

    $runner = [IO.Path]::GetFullPath($authority.runnerPath)
    $resolver = Join-Path $authority.root 'scripts/Resolve-StandardValidationTool.ps1'
    $policy = Join-Path $authority.root 'docs/standards/validation-toolchain.json'
    foreach ($binding in @(@($runner, 'scripts/Invoke-StandardValidation.ps1'), @($resolver, 'scripts/Resolve-StandardValidationTool.ps1'), @($policy, 'docs/standards/validation-toolchain.json'))) {
        if ((Get-FileSha256 -Path $binding[0]) -cne [string]$pin.files[$binding[1]]) { throw "Verified authority file changed before setup: $($binding[1])" }
    }
    $runnerContext = [ordered]@{
        CandidateRoot = $RepositoryRoot
        AdapterPath = $preparedPath
        ArtifactsRoot = $setupRoot
        OutputPath = ''
        SourceRepository = $script:SourceRepository
        SourceRevision = $CandidateRevision
        BaseRevision = $CandidateRevision
        EventName = 'local'
        RunId = $runId
        AuthorityRevision = [string]$pin.commit
        TimeoutSeconds = $TimeoutSeconds
        CancellationPath = ''
        TrustedToolRoot = $trustedRoot
    }
    $runnerModule = New-CodeSourceStandardValidationModule -RunnerPath $runner `
        -RunnerSha256 ([string]$pin.files['scripts/Invoke-StandardValidation.ps1']) -RunnerArguments $runnerContext
    try {

    $stageTimer = [Diagnostics.Stopwatch]::StartNew()
    $manifestPath = Join-Path $ownedRoot 'candidate-git-entry-modes.json'
    $manifest = Get-GitEntryModeManifest -GitPath $GitPath -RepositoryRoot $RepositoryRoot -CandidateCommit $CandidateRevision
    $protectedSourceRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
    $protectedDispatchBindings = @(Assert-CodeSourceProtectedDispatchFiles -ProtectedBaseRoot $protectedSourceRoot `
        -CandidateRoot $RepositoryRoot -ManifestEntries @($manifest.entries))
    Write-Utf8NoBomCreateNew -Path $manifestPath -Text (($manifest | ConvertTo-Json -Depth 40) + [Environment]::NewLine)
    $manifestSha256 = Get-FileSha256 -Path $manifestPath
    $archivePath = Join-Path $ownedRoot 'candidate.zip'
    & $GitPath -C $RepositoryRoot archive --format=zip "--output=$archivePath" $CandidateRevision
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $archivePath -PathType Leaf)) { throw 'Source setup could not archive the exact immutable candidate.' }
    $archiveSha256 = Get-FileSha256 -Path $archivePath
    $stageTimer.Stop()
    $setupStageSeconds.candidateManifestAndArchiveSeconds = [Math]::Round($stageTimer.Elapsed.TotalSeconds, 3)
    $sourceIdentityPath = Join-Path $ownedRoot 'source-run-identity.json'
    $sourceIdentity = [ordered]@{
        schemaVersion = 1
        runId = $runId
        sourceRevision = $CandidateRevision
        authorityRevision = [string]$pin.commit
        candidateManifestPath = [IO.Path]::GetFullPath($manifestPath)
        candidateManifestSha256 = $manifestSha256
        candidateArchivePath = [IO.Path]::GetFullPath($archivePath)
        candidateArchiveSha256 = $archiveSha256
    }
    Write-Utf8NoBomCreateNew -Path $sourceIdentityPath -Text (($sourceIdentity | ConvertTo-Json -Depth 20) + [Environment]::NewLine)

    $receipts = [ordered]@{}
    $receiptBindings = @()
    $goVersion = Resolve-GoRuntimeVersion -Expected $ExpectedGoRuntimeVersion
    foreach ($toolName in @('skill-validator', 'skill-tools', 'skillspector')) {
        $resolverTimer = [Diagnostics.Stopwatch]::StartNew()
        $receiptPath = Join-Path $ownedRoot "receipt-$toolName.json"
        $resolverArguments = @{
            Command = $powerShell
            Arguments = [string[]]@('-NoProfile', '-NonInteractive', '-File', $resolver,
                '-PolicyPath', $policy, '-ToolName', $toolName, '-Install', '-InstallRoot', (Join-Path $ownedRoot 'installed'),
                '-ExpectedGoRuntimeVersion', $goVersion, '-RunId', $runId, '-OutputPath', $receiptPath)
            WorkingDirectory = $ownedRoot
            Environment = @{}
            TimeoutSeconds = $TimeoutSeconds
            CoreLifecycleOnly = $true
        }
        $processResult = Invoke-CodeSourceStandardValidationModule -Module $runnerModule `
            -FunctionName 'Invoke-StandardValidationProcess' -Arguments $resolverArguments
        Write-Utf8NoBomCreateNew -Path (Join-Path $ownedRoot "setup-$toolName-process.json") -Text (($processResult | ConvertTo-Json -Depth 40) + [Environment]::NewLine)
        if ([string]$processResult.status -cne 'passed' -or [int]$processResult.exitCode -ne 0 -or -not [bool]$processResult.cleanedUp) {
            throw "Source tool setup '$toolName' failed with status '$($processResult.status)', exit $($processResult.exitCode), cleanup=$($processResult.cleanedUp)."
        }
        $receipt = Read-JsonFile -Path $receiptPath -Context "$toolName source resolver receipt"
        if ([string]$receipt.toolName -cne $toolName -or [string]$receipt.resolutionRunId -cne $runId -or
            [string]$receipt.channel -cne 'latest-stable' -or $receipt.frozenForRun -isnot [bool] -or -not $receipt.frozenForRun -or
            [string]::IsNullOrWhiteSpace([string]$receipt.resolvedVersion) -or [string]::IsNullOrWhiteSpace([string]$receipt.resolvedIdentity)) {
            throw "Source resolver receipt '$toolName' is not bound to this exact setup run."
        }
        $receipts[$toolName] = $receipt
        $receiptBindings += [pscustomobject]@{ path = [IO.Path]::GetFullPath($receiptPath); sha256 = Get-FileSha256 -Path $receiptPath }
        $resolverTimer.Stop()
        $resolverStageSeconds[$toolName] = [Math]::Round($resolverTimer.Elapsed.TotalSeconds, 3)
    }

    $toolchain = [ordered]@{
        centralRunnerPath = $runner; centralRunnerSha256 = Get-FileSha256 -Path $runner
        upstreamAdapterValidatorPath = Join-Path $authority.root 'scripts/Validate-UpstreamAdapter.ps1'; upstreamAdapterValidatorSha256 = Get-FileSha256 -Path (Join-Path $authority.root 'scripts/Validate-UpstreamAdapter.ps1')
        upstreamPolicyPath = Join-Path $authority.root 'docs/standards/upstream-adapter.json'; upstreamPolicySha256 = Get-FileSha256 -Path (Join-Path $authority.root 'docs/standards/upstream-adapter.json')
        skillValidatorPath = [string]$receipts.'skill-validator'.executablePath; skillValidatorSha256 = [string]$receipts.'skill-validator'.executableSha256
        skillToolsNodePath = [string]$receipts.'skill-tools'.nodePath; skillToolsNodeSha256 = [string]$receipts.'skill-tools'.nodeSha256
        skillToolsEntryPointPath = [string]$receipts.'skill-tools'.entryPointPath; skillToolsEntryPointSha256 = [string]$receipts.'skill-tools'.entryPointSha256
        skillSpectorPath = [string]$receipts.skillspector.executablePath; skillSpectorSha256 = [string]$receipts.skillspector.executableSha256
        skillSpectorReceiptPath = [string]$receiptBindings[2].path; skillSpectorReceiptSha256 = [string]$receiptBindings[2].sha256
    }
    foreach ($toolPath in @(
        [pscustomobject]@{ path = $toolchain.skillValidatorPath; sha = $toolchain.skillValidatorSha256 },
        [pscustomobject]@{ path = $toolchain.skillToolsNodePath; sha = $toolchain.skillToolsNodeSha256 },
        [pscustomobject]@{ path = $toolchain.skillToolsEntryPointPath; sha = $toolchain.skillToolsEntryPointSha256 },
        [pscustomobject]@{ path = $toolchain.skillSpectorPath; sha = $toolchain.skillSpectorSha256 }
    )) {
        Assert-NoReparseAncestors -Path ([string]$toolPath.path) -Context 'Resolved source tool'
        if ((Get-FileSha256 -Path ([string]$toolPath.path)) -cne [string]$toolPath.sha) { throw 'Resolved source tool changed after receipt creation.' }
    }
    $toolchainPath = Join-Path $ownedRoot 'toolchain.json'
    Write-Utf8NoBomCreateNew -Path $toolchainPath -Text (($toolchain | ConvertTo-Json -Depth 30) + [Environment]::NewLine)
    $toolchainSha256 = Get-FileSha256 -Path $toolchainPath
    $wrapperPath = Join-Path $ownedRoot 'Invoke-CodeCollaborationValidationChild.ps1'
    Write-Utf8NoBomCreateNew -Path $wrapperPath -Text $childRunnerText
    $commonArguments = @('-NoProfile', '-NonInteractive', '-File', $wrapperPath, '-ToolchainPath', $toolchainPath,
        '-ToolchainSha256', $toolchainSha256, '-SourceRepository', $script:SourceRepository, '-SourceRevision', $CandidateRevision,
        '-ArchiveSha256', $archiveSha256, '-GitEntryModeManifestPath', $manifestPath, '-GitEntryModeManifestSha256', $manifestSha256)
    $sourceDispatch = [ordered]@{
        packageAdapter = [ordered]@{ command = $powerShell; arguments = @($commonArguments + @('-Mode', 'package-adapter')) }
        skillValidator = [ordered]@{ command = $powerShell; arguments = @($commonArguments + @('-Mode', 'skill-validator')) }
        skillTools = [ordered]@{ command = $powerShell; arguments = @($commonArguments + @('-Mode', 'skill-tools')) }
        staticAnalyzer = [ordered]@{ command = $powerShell; arguments = @($commonArguments + @('-Mode', 'static')) }
        frozenFiles = @(); toolReceipts = @($receiptBindings)
    }

    $lockSource = Join-Path (Split-Path -Parent $PSScriptRoot) 'config/pester-6.2.0-closure.lock.json'
    $prepareScript = Join-Path $PSScriptRoot 'Prepare-PesterRuntime.ps1'
    $integrityModule = Join-Path $PSScriptRoot 'CorePesterIntegrity.psm1'
    foreach ($path in @($lockSource, $prepareScript, $integrityModule)) { if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Protected Pester setup input is missing: $path" } }
    $lockPath = Join-Path $ownedRoot 'pester-6.2.0-closure.lock.json'
    Copy-Item -LiteralPath $lockSource -Destination $lockPath -ErrorAction Stop
    $lockHash = Get-FileSha256 -Path $lockPath
    $moduleRoot = Join-Path $runtimeRoot 'Modules/Pester/6.2.0'
    $moduleManifestPath = Join-Path $moduleRoot 'Pester.psd1'
    $setupReceiptPath = Join-Path $ownedRoot 'pester-setup/setup-receipt.json'
    $setupEnvironment = New-CodeSourcePesterSetupEnvironment -OwnedRoot $ownedRoot
    $pesterSetupTimer = [Diagnostics.Stopwatch]::StartNew()
    $pesterSetupArguments = @{
        Command = $powerShell
        Arguments = [string[]]@('-NoProfile', '-NonInteractive', '-File', $prepareScript,
            '-RuntimeExecutable', $powerShell, '-OwnedRoot', $ownedRoot, '-ModuleRoot', $moduleRoot, '-LockPath', $lockPath,
            '-SetupReceiptPath', $setupReceiptPath, '-RunId', $runId)
        WorkingDirectory = $ownedRoot
        Environment = $setupEnvironment
        TimeoutSeconds = $TimeoutSeconds
        CoreLifecycleOnly = $true
    }
    $setupResult = Invoke-CodeSourceStandardValidationModule -Module $runnerModule `
        -FunctionName 'Invoke-StandardValidationProcess' -Arguments $pesterSetupArguments
    Write-Utf8NoBomCreateNew -Path (Join-Path $ownedRoot 'pester-setup-process.json') -Text (($setupResult | ConvertTo-Json -Depth 40) + [Environment]::NewLine)
    if ([string]$setupResult.status -cne 'passed' -or [int]$setupResult.exitCode -ne 0 -or -not [bool]$setupResult.cleanedUp) {
        throw "Run-owned Pester setup failed with status '$($setupResult.status)', exit $($setupResult.exitCode), cleanup=$($setupResult.cleanedUp)."
    }
    $pesterReceipt = Read-JsonFile -Path $setupReceiptPath -Context 'Pester setup receipt'
    if ([string]$pesterReceipt.runId -cne $runId -or [string]$pesterReceipt.lockSha256 -cne $lockHash -or
        [string]$pesterReceipt.terminalStatus -cne 'verified' -or [string]$pesterReceipt.runtimeExecutable -cne $powerShell -or
        -not (Test-Path -LiteralPath $moduleManifestPath -PathType Leaf)) { throw 'Run-owned Pester setup receipt is incomplete or belongs to a different setup.' }
    $moduleRootFull = [IO.Path]::GetFullPath($moduleRoot)
    $pesterClosureFiles = @(Get-ChildItem -LiteralPath $moduleRootFull -Recurse -File -Force -ErrorAction Stop | ForEach-Object { $_.FullName })
    if ($pesterClosureFiles.Count -eq 0) { throw 'Run-owned Pester module closure is empty.' }
    foreach ($path in @($pesterClosureFiles)) { Assert-NoReparseAncestors -Path $path -Context 'Run-owned Pester closure' }
    $pesterSetupTimer.Stop()
    $setupStageSeconds.pesterRuntimeSetupAndInventorySeconds = [Math]::Round($pesterSetupTimer.Elapsed.TotalSeconds, 3)

    $protectedDispatchCopyRoot = Join-Path $runtimeRoot 'ProtectedSourceChecks'
    foreach ($binding in $protectedDispatchBindings) {
        $destination = Join-Path $protectedDispatchCopyRoot ([string]$binding.path)
        $destinationParent = Split-Path -Parent $destination
        if (-not (Test-Path -LiteralPath $destinationParent -PathType Container)) {
            [void](New-Item -ItemType Directory -Path $destinationParent -Force -ErrorAction Stop)
        }
        Copy-Item -LiteralPath ([string]$binding.protectedPath) -Destination $destination -ErrorAction Stop
        if ((Get-FileSha256 -Path $destination) -cne [string]$binding.sha256) {
            throw "Protected Core dispatch copy changed during source setup: $($binding.path)"
        }
    }

    $inventoryTimer = [Diagnostics.Stopwatch]::StartNew()
    $runtimeFiles = @(Get-ChildItem -LiteralPath $runtimeRoot -Recurse -File -Force -ErrorAction Stop | ForEach-Object {
        if ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Run-owned PowerShell runtime contains a reparse point: $($_.FullName)" }
        [pscustomobject]@{ path = [IO.Path]::GetFullPath($_.FullName); sha256 = Get-FileSha256 -Path $_.FullName }
    })
    $runtimeInventoryPath = Join-Path $ownedRoot 'powershell-runtime-inventory.json'
    $runtimeInventory = [ordered]@{
        schemaVersion = 1
        root = $runtimeRoot
        executablePath = $powerShell
        executableSha256 = Get-FileSha256 -Path $powerShell
        files = @($runtimeFiles | Sort-Object -Property path -CaseSensitive)
    }
    Write-Utf8NoBomCreateNew -Path $runtimeInventoryPath -Text (($runtimeInventory | ConvertTo-Json -Depth 20) + [Environment]::NewLine)
    $runtimeInventorySha256 = Get-FileSha256 -Path $runtimeInventoryPath
    $runtimeCopyFiles = @($runtimeFiles | ForEach-Object { [string]$_.path })
    $receiptFrozenPaths = @()
    foreach ($receipt in @($receipts.Values)) {
        $receiptFrozenPaths += @(Get-CodeSourceReceiptFrozenPaths -Receipt $receipt -OwnedRoot $ownedRoot)
    }
    $sourceFrozenFiles = New-CodeSourceFrozenFileInventory -RuntimeFiles $runtimeCopyFiles `
        -SourceFiles @($runtimeInventoryPath, $powerShell, $runner, $resolver, $policy, $toolchain.upstreamAdapterValidatorPath,
            $toolchain.upstreamPolicyPath, $toolchainPath, $wrapperPath, $manifestPath, $archivePath, $lockPath,
            $sourceIdentityPath, $prepareScript, $integrityModule) `
        -PesterFiles (@($moduleManifestPath, $setupReceiptPath) + @($pesterClosureFiles)) `
        -ReceiptFiles (@($receiptFrozenPaths) + @($receiptBindings | ForEach-Object { [string]$_.path }) + @(
            [string]$toolchain.skillValidatorPath, [string]$toolchain.skillToolsNodePath,
            [string]$toolchain.skillToolsEntryPointPath, [string]$toolchain.skillSpectorPath))
    $inventoryTimer.Stop()
    $setupStageSeconds.closureInventoryHashAndSortSeconds = [Math]::Round($inventoryTimer.Elapsed.TotalSeconds, 3)
    $stageTimingCapturedAtUtc = [DateTimeOffset]::UtcNow
    $setupTimingPath = Join-Path $ownedRoot 'setup-timing.json'
    $setupTiming = [ordered]@{
        schemaVersion = 1
        runId = $runId
        startedAtUtc = $setupStartedAtUtc.ToString('O')
        stageTimingCapturedAtUtc = $stageTimingCapturedAtUtc.ToString('O')
        stageSeconds = $setupStageSeconds
        resolverSeconds = $resolverStageSeconds
        stageTimingBoundary = 'runtime copy, candidate manifest/archive, resolver, Pester setup, and first frozen-file inventory/hash/sort intervals only; excludes final verification and prepared metadata write'
    }
    Write-Utf8NoBomCreateNew -Path $setupTimingPath -Text (($setupTiming | ConvertTo-Json -Depth 30) + [Environment]::NewLine)
    $setupTimingRecord = [pscustomobject]@{
        path = [IO.Path]::GetFullPath($setupTimingPath)
        sha256 = Get-FileSha256 -Path $setupTimingPath
    }
    $frozenRecords = @($sourceFrozenFiles.files) + @($setupTimingRecord)
    $sourceDispatch.frozenFiles = @($frozenRecords | Sort-Object -Property path -CaseSensitive)
    $frozenFiles = @($sourceDispatch.frozenFiles)
    [void](Invoke-CodeSourceStandardValidationModule -Module $runnerModule -FunctionName 'Assert-StandardCoreFrozenFiles' `
        -Arguments @{ Files = @($sourceDispatch.frozenFiles) })
    [void](Invoke-CodeSourceStandardValidationModule -Module $runnerModule -FunctionName 'Assert-StandardCoreSourceToolReceipts' `
        -Arguments @{ Bindings = @($sourceDispatch.toolReceipts); FrozenFiles = @($sourceDispatch.frozenFiles); `
            RunId = $runId; CandidateRoot = $RepositoryRoot; ArtifactsRoot = $setupRoot })

    $prepared = [ordered]@{
        schemaVersion = 1; preparation = 'code-collaboration-source-tools'; runId = $runId
        sourceRevision = $CandidateRevision; authorityRevision = [string]$pin.commit; ownedRoot = $ownedRoot
        candidateArchivePath = $archivePath; candidateArchiveSha256 = $archiveSha256
        sourceValidation = $sourceDispatch
        pesterRuntime = [ordered]@{
            moduleManifestPath = [IO.Path]::GetFullPath($moduleManifestPath)
            closureLockPath = [IO.Path]::GetFullPath($lockPath)
            closureLockSha256 = $lockHash
            setupReceiptPath = [IO.Path]::GetFullPath($setupReceiptPath)
            setupReceiptSha256 = Get-FileSha256 -Path $setupReceiptPath
            runtimeRoot = [IO.Path]::GetFullPath($runtimeRoot)
            runtimeExecutablePath = [IO.Path]::GetFullPath($powerShell)
            runtimeExecutableSha256 = Get-FileSha256 -Path $powerShell
            runtimeInventoryPath = [IO.Path]::GetFullPath($runtimeInventoryPath)
            runtimeInventorySha256 = $runtimeInventorySha256
            sourceTrustedToolRoot = [IO.Path]::GetFullPath($trustedRoot)
        }
    }
    Write-Utf8NoBomCreateNew -Path $preparedPath -Text (($prepared | ConvertTo-Json -Depth 80) + [Environment]::NewLine)
    $setupTimer.Stop()
    $setupCompletedAtUtc = [DateTimeOffset]::UtcNow
    $setupCompletedTimingPath = Join-Path $setupRoot "source-tools-setup-completed-$runId.json"
    $setupCompletedTiming = [ordered]@{
        schemaVersion = 1
        runId = $runId
        setupStartedAtUtc = $setupStartedAtUtc.ToString('O')
        setupCompletedAtUtc = $setupCompletedAtUtc.ToString('O')
        setupTotalSeconds = [Math]::Round($setupTimer.Elapsed.TotalSeconds, 3)
        stageSeconds = $setupStageSeconds
        resolverSeconds = $resolverStageSeconds
        stageTimingPath = [IO.Path]::GetFullPath($setupTimingPath)
        stageTimingSha256 = Get-FileSha256 -Path $setupTimingPath
        diagnosticTargetSeconds = 1200
        diagnosticTargetExceeded = ($setupTimer.Elapsed.TotalSeconds -gt 1200)
        totalBoundary = 'after complete frozen-file verification and prepared metadata creation'
    }
    Write-Utf8NoBomCreateNew -Path $setupCompletedTimingPath -Text (($setupCompletedTiming | ConvertTo-Json -Depth 30) + [Environment]::NewLine)
    [Console]::Out.WriteLine("Prepared source validation tools for RunId $runId at $preparedPath")
    [Console]::Out.WriteLine("Source setup timing evidence: $setupCompletedTimingPath")
    }
    finally {
        if ($null -ne $runnerModule) { Remove-Module -ModuleInfo $runnerModule -Force -ErrorAction Stop }
    }
}

function Read-CodeSourcePreparedTools {
    param([Parameter(Mandatory)][string] $Path, [Parameter(Mandatory)][string] $CandidateRevision,
        [Parameter(Mandatory)][string] $PowerShellPath, [Parameter(Mandatory)][string] $AuthorityRoot,
        [Parameter(Mandatory)] $AuthorityPin, [Parameter(Mandatory)][string] $CandidateRoot,
        [Parameter(Mandatory)][string] $ProtectedBaseRoot)

    $prepared = Read-JsonFile -Path $Path -Context 'Prepared Code-Collaboration source tools'
    [void](Assert-CodeSourcePreparedBindings -Prepared $prepared -PreparedPath $Path -CandidateRevision $CandidateRevision -PowerShellPath $PowerShellPath -SourceRepository $script:SourceRepository)
    $ownedRoot = [IO.Path]::GetFullPath([string]$prepared.ownedRoot)
    $manifestPath = Join-Path $ownedRoot 'candidate-git-entry-modes.json'
    $manifestBindings = @($prepared.sourceValidation.frozenFiles | Where-Object { (Test-PathEqual -Left ([string]$_.path) -Right $manifestPath) })
    if ($manifestBindings.Count -ne 1 -or (Get-FileSha256 -Path $manifestPath) -cne [string]$manifestBindings[0].sha256) {
        throw 'Prepared candidate Git entry mode manifest is missing or changed.'
    }
    $candidateManifest = Read-JsonFile -Path $manifestPath -Context 'Prepared candidate Git entry mode manifest'
    $identityPath = Join-Path $ownedRoot 'source-run-identity.json'
    $identityBindings = @($prepared.sourceValidation.frozenFiles | Where-Object { (Test-PathEqual -Left ([string]$_.path) -Right $identityPath) })
    if ($identityBindings.Count -ne 1 -or (Get-FileSha256 -Path $identityPath) -cne [string]$identityBindings[0].sha256) {
        throw 'Prepared source run identity receipt is missing or changed.'
    }
    $sourceIdentity = Read-JsonFile -Path $identityPath -Context 'Prepared source run identity receipt'
    if ([int]$sourceIdentity.schemaVersion -ne 1 -or [string]$sourceIdentity.runId -cne [string]$prepared.runId -or
        [string]$sourceIdentity.sourceRevision -cne $CandidateRevision -or [string]$sourceIdentity.authorityRevision -cne [string]$AuthorityPin.commit -or
        -not (Test-PathEqual -Left ([string]$sourceIdentity.candidateManifestPath) -Right $manifestPath) -or
        [string]$sourceIdentity.candidateManifestSha256 -cne [string]$manifestBindings[0].sha256 -or
        -not (Test-PathEqual -Left ([string]$sourceIdentity.candidateArchivePath) -Right ([string]$prepared.candidateArchivePath)) -or
        [string]$sourceIdentity.candidateArchiveSha256 -cne [string]$prepared.candidateArchiveSha256) {
        throw 'Prepared source run identity does not bind the exact source, authority, manifest, archive and RunId.'
    }
    $protectedDispatchBindings = @(Assert-CodeSourceProtectedRuntimeCopies -ProtectedBaseRoot $ProtectedBaseRoot `
        -CandidateRoot $CandidateRoot -OwnedRoot $ownedRoot -ManifestEntries @($candidateManifest.entries) `
        -FrozenFiles @($prepared.sourceValidation.frozenFiles))
    $wrapperPath = Join-Path $ownedRoot 'Invoke-CodeCollaborationValidationChild.ps1'
    $expectedWrapperHash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.UTF8Encoding]::new($false).GetBytes($childRunnerText))).ToLowerInvariant()
    if ((Get-FileSha256 -Path $wrapperPath) -cne $expectedWrapperHash) { throw 'Prepared source child wrapper differs from the protected event-base driver.' }
    $toolchainPath = Join-Path $ownedRoot 'toolchain.json'
    if (-not (Test-Path -LiteralPath $toolchainPath -PathType Leaf)) { throw 'Prepared source toolchain is missing.' }
    $toolchainBindings = @($prepared.sourceValidation.frozenFiles | Where-Object { (Test-PathEqual -Left ([string]$_.path) -Right $toolchainPath) })
    if ($toolchainBindings.Count -ne 1 -or (Get-FileSha256 -Path $toolchainPath) -cne [string]$toolchainBindings[0].sha256) { throw 'Prepared source toolchain is not frozen.' }
    $toolchain = Read-JsonFile -Path $toolchainPath -Context 'Prepared source toolchain'
    [void](Assert-CodeSourceAuthorityToolchain -Toolchain $toolchain -AuthorityRoot $AuthorityRoot -AuthorityPin $AuthorityPin)
    foreach ($binding in @(
        [pscustomobject]@{ path = [string]$toolchain.centralRunnerPath; sha = [string]$toolchain.centralRunnerSha256; expected = 'scripts/Invoke-StandardValidation.ps1' },
        [pscustomobject]@{ path = [string]$toolchain.upstreamAdapterValidatorPath; sha = [string]$toolchain.upstreamAdapterValidatorSha256; expected = 'scripts/Validate-UpstreamAdapter.ps1' },
        [pscustomobject]@{ path = [string]$toolchain.upstreamPolicyPath; sha = [string]$toolchain.upstreamPolicySha256; expected = 'docs/standards/upstream-adapter.json' }
    )) {
        $frozen = @($prepared.sourceValidation.frozenFiles | Where-Object { (Test-PathEqual -Left ([string]$_.path) -Right $binding.path) -and [string]$_.sha256 -ceq $binding.sha })
        if ($frozen.Count -ne 1 -or (Get-FileSha256 -Path $binding.path) -cne $binding.sha) { throw "Prepared authority toolchain file is not frozen: $($binding.expected)" }
    }
    if ((Get-FileSha256 -Path ([string]$prepared.candidateArchivePath)) -cne [string]$prepared.candidateArchiveSha256) { throw 'Prepared candidate archive changed.' }
    return $prepared
}

function Invoke-CodeSourceValidation {
    param([Parameter(Mandatory)][string] $GitPath, [Parameter(Mandatory)][string] $PowerShellPath,
        [Parameter(Mandatory)][string] $RepositoryRoot, [Parameter(Mandatory)][string] $CandidateRevision,
        [Parameter(Mandatory)][string] $BaseRevision, [Parameter(Mandatory)] $AuthorityConfig,
        [Parameter(Mandatory)][string] $SourceToolsPath, [Parameter(Mandatory)][string] $AuthorityRepositoryRoot,
        [string] $TrustedToolRoot, [Parameter(Mandatory)][string] $ArtifactsRoot, [string] $OutputPath,
        [Parameter(Mandatory)][string] $EventName, [Parameter(Mandatory)][int] $TimeoutSeconds,
        [bool] $ArtifactsRootWasExplicit = $true, [string] $CancellationPath)

    $sourceValidationStartedAtUtc = [DateTimeOffset]::UtcNow
    $sourceValidationTimer = [Diagnostics.Stopwatch]::StartNew()
    $centralRunnerSeconds = 0.0
    $cleanupErrorMessage = $null
    $sourceReportAccepted = $false
    $pin = Assert-CodeSourceAuthorityConfig -Config $AuthorityConfig
    $authority = Assert-CodeSourceAuthorityCheckout -GitPath $GitPath -AuthorityRoot $AuthorityRepositoryRoot -AuthorityPin $pin
    $preparedPath = [IO.Path]::GetFullPath($SourceToolsPath)
    $preparedHint = Read-JsonFile -Path $preparedPath -Context 'Prepared Code-Collaboration source tools'
    $powerShell = [IO.Path]::GetFullPath([string]$preparedHint.pesterRuntime.runtimeExecutablePath)
    $trustedRoot = [IO.Path]::GetFullPath([string]$preparedHint.pesterRuntime.runtimeRoot)
    if (-not [string]::IsNullOrWhiteSpace($TrustedToolRoot) -and
        -not [IO.Path]::GetFullPath($TrustedToolRoot).Equals([IO.Path]::GetFullPath([string]$preparedHint.pesterRuntime.sourceTrustedToolRoot), $(if ($IsWindows) { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal }))) {
        throw 'SourceValidation TrustedToolRoot differs from the exact root recorded during source setup.'
    }
    if (-not (Test-Path -LiteralPath $powerShell -PathType Leaf) -or
        (Get-FileSha256 -Path $powerShell) -cne [string]$preparedHint.pesterRuntime.runtimeExecutableSha256) {
        throw 'Prepared run-owned PowerShell executable is missing or changed.'
    }
    if (-not [IO.Path]::GetFullPath($PowerShellPath).Equals($powerShell, $(if ($IsWindows) { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal }))) {
        throw 'SourceValidation PowerShell path differs from the exact prepared run-owned executable.'
    }
    if (-not (Test-Path -LiteralPath $trustedRoot -PathType Container) -or -not (Test-PathWithinOrEqual -Path $powerShell -Root $trustedRoot)) {
        throw 'Source validation PowerShell must be within the verified TrustedToolRoot.'
    }
    Assert-NoReparseAncestors -Path $trustedRoot -Context 'Source validation TrustedToolRoot'
    Assert-OutsideRoot -Path $trustedRoot -Root $RepositoryRoot -Context 'TrustedToolRoot'
    Assert-OutsideRoot -Path $trustedRoot -Root $authority.root -Context 'TrustedToolRoot'
    $preparedRoot = [IO.Path]::GetFullPath((Split-Path -Parent $preparedPath))
    Assert-OutsideRoot -Path $preparedRoot -Root $RepositoryRoot -Context 'Prepared source root'
    Assert-OutsideRoot -Path $preparedRoot -Root $authority.root -Context 'Prepared source root'
    Assert-OutsideRoot -Path $preparedRoot -Root $trustedRoot -Context 'Prepared source root'
    $script:SourceInvalidInput = $true
    $prepared = Read-CodeSourcePreparedTools -Path $preparedPath -CandidateRevision $CandidateRevision -PowerShellPath $powerShell `
        -AuthorityRoot $authority.root -AuthorityPin $pin -CandidateRoot $RepositoryRoot `
        -ProtectedBaseRoot ([IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot)))
    if ([string]$prepared.authorityRevision -cne [string]$pin.commit) { throw 'Prepared source tools do not bind the exact ff85 authority revision.' }
    $setupTimingPath = Join-Path ([string]$prepared.ownedRoot) 'setup-timing.json'
    $setupTimingBinding = @($prepared.sourceValidation.frozenFiles | Where-Object {
        (Test-PathEqual -Left ([string]$_.path) -Right $setupTimingPath)
    })
    if ($setupTimingBinding.Count -ne 1 -or (Get-FileSha256 -Path $setupTimingPath) -cne [string]$setupTimingBinding[0].sha256) {
        throw 'Prepared source setup timing evidence is missing or changed.'
    }
    $setupTiming = Read-JsonFile -Path $setupTimingPath -Context 'Prepared source setup timing evidence'
    if ([int]$setupTiming.schemaVersion -ne 1 -or [string]$setupTiming.runId -cne [string]$prepared.runId -or
        [string]$setupTiming.startedAtUtc -cnotmatch '^\d{4}-\d{2}-\d{2}T' -or
        [string]$setupTiming.stageTimingCapturedAtUtc -cnotmatch '^\d{4}-\d{2}-\d{2}T' -or
        $setupTiming.stageSeconds -isnot [pscustomobject] -or [string]::IsNullOrWhiteSpace([string]$setupTiming.stageTimingBoundary)) {
        throw 'Prepared source setup timing evidence is invalid or belongs to a different run.'
    }
    $setupCompletedTimingPath = Join-Path (Split-Path -Parent $preparedPath) "source-tools-setup-completed-$($prepared.runId).json"
    if (-not (Test-Path -LiteralPath $setupCompletedTimingPath -PathType Leaf)) { throw 'Completed source setup timing evidence is missing.' }
    $setupCompletedTimingSha256 = Get-FileSha256 -Path $setupCompletedTimingPath
    $setupCompletedTiming = Read-JsonFile -Path $setupCompletedTimingPath -Context 'Completed source setup timing evidence'
    if ([int]$setupCompletedTiming.schemaVersion -ne 1 -or [string]$setupCompletedTiming.runId -cne [string]$prepared.runId -or
        [string]$setupCompletedTiming.setupStartedAtUtc -cne [string]$setupTiming.startedAtUtc -or
        [double]$setupCompletedTiming.setupTotalSeconds -lt 0 -or [int]$setupCompletedTiming.diagnosticTargetSeconds -ne 1200 -or
        [string]$setupCompletedTiming.totalBoundary -cne 'after complete frozen-file verification and prepared metadata creation') {
        throw 'Completed source setup timing evidence is invalid or belongs to a different run.'
    }
    $script:SourceInvalidInput = $false

    $artifactsRootPath = [IO.Path]::GetFullPath($ArtifactsRoot)
    Assert-OutsideRoot -Path $artifactsRootPath -Root $RepositoryRoot -Context 'Source Core ArtifactsRoot'
    Assert-OutsideRoot -Path $artifactsRootPath -Root $authority.root -Context 'Source Core ArtifactsRoot'
    Assert-OutsideRoot -Path $artifactsRootPath -Root $trustedRoot -Context 'Source Core ArtifactsRoot'
    Assert-OutsideRoot -Path $artifactsRootPath -Root ([string]$prepared.ownedRoot) -Context 'Source Core ArtifactsRoot'
    $paths = Get-CodeSourceCoreRunPaths -ArtifactsRoot $artifactsRootPath -ArtifactsRootWasExplicit $ArtifactsRootWasExplicit `
        -RunId ([string]$prepared.runId) -OutputPath $OutputPath
    foreach ($root in @($paths.artifactsRoot, $paths.adapterRoot)) {
        Assert-OutsideRoot -Path $root -Root $RepositoryRoot -Context 'Source Core run-owned root'
        Assert-OutsideRoot -Path $root -Root $authority.root -Context 'Source Core run-owned root'
        Assert-OutsideRoot -Path $root -Root $trustedRoot -Context 'Source Core run-owned root'
        Assert-OutsideRoot -Path $root -Root ([string]$prepared.ownedRoot) -Context 'Source Core run-owned root'
    }
    Assert-OutsideRoot -Path $paths.adapterRoot -Root $paths.artifactsRoot -Context 'Source Core adapter root'
    if (-not (Test-Path -LiteralPath $paths.artifactsRoot -PathType Container)) { [void](New-Item -ItemType Directory -Path $paths.artifactsRoot -Force -ErrorAction Stop) }
    elseif (-not $ArtifactsRootWasExplicit) { throw 'Default Source Core ArtifactsRoot unexpectedly exists; run-owned paths are create-only.' }
    Assert-NoReparseAncestors -Path $paths.artifactsRoot -Context 'Source Core ArtifactsRoot'
    Assert-PathWithinRoot -Path $paths.outputPath -Root $paths.artifactsRoot -Context 'Source Core OutputPath' | Out-Null
    if (Test-Path -LiteralPath $paths.outputPath) { throw "Source Core output evidence already exists: $($paths.outputPath)" }
    if (Test-Path -LiteralPath $paths.adapterRoot) { throw 'Source Core adapter sibling path already exists.' }
    [void](New-Item -ItemType Directory -Path $paths.adapterRoot -ErrorAction Stop)
    $adapterRootCreated = $true
    $cleanupSucceeded = $false
    $runnerModuleCleanupSucceeded = $true
    $processExitCode = 1
    $reportRunnerModule = $null
    $previousTestValidateSource = [Environment]::GetEnvironmentVariable('SYP154_TEST_VALIDATE_SOURCE', 'Process')
    try {
        Assert-NoReparseAncestors -Path $paths.adapterRoot -Context 'Source Core adapter root'
        $authoritySnapshot = New-CodeSourceAuthoritySnapshot -GitPath $GitPath -SourceRoot $authority.root -OwnedRoot $paths.adapterRoot -AuthorityPin $pin
        $manifestBinding = @($prepared.sourceValidation.frozenFiles | Where-Object {
            [IO.Path]::GetFullPath([string]$_.path).Equals([IO.Path]::GetFullPath((Join-Path ([string]$prepared.ownedRoot) 'candidate-git-entry-modes.json')), $(if ($IsWindows) { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal }))
        })
        if ($manifestBinding.Count -ne 1) { throw 'Prepared source Git entry manifest does not have one exact frozen binding.' }
        $adapter = New-CodeCoreAdapterV2 -PowerShellPath $powerShell -TrustedToolRoot $trustedRoot `
            -CandidateAuthorityAdapterRunId ([string]$prepared.runId) -CandidateRevision $CandidateRevision `
            -CandidateGitEntryModeManifestPath ([string]$manifestBinding[0].path) -CandidateGitEntryModeManifestSha256 ([string]$manifestBinding[0].sha256) `
            -ActiveSkillIds (Get-ActiveSkillIds -Root $RepositoryRoot) -SourceValidation $prepared.sourceValidation -PesterRuntime $prepared.pesterRuntime
        Write-Utf8NoBomCreateNew -Path $paths.adapterPath -Text (($adapter | ConvertTo-Json -Depth 80) + [Environment]::NewLine)
        $adapterSha = Get-FileSha256 -Path $paths.adapterPath
        $centralRunner = [IO.Path]::GetFullPath($authoritySnapshot.runnerPath)
        if ((Get-FileSha256 -Path $centralRunner) -cne [string]$pin.files['scripts/Invoke-StandardValidation.ps1']) { throw 'Run-owned protected Standard Core runner changed.' }
        $arguments = @('-CandidateRoot', $RepositoryRoot, '-AdapterPath', $paths.adapterPath, '-ArtifactsRoot', $paths.artifactsRoot,
            '-OutputPath', $paths.outputPath, '-SourceRepository', $script:SourceRepository, '-SourceRevision', $CandidateRevision,
            '-BaseRevision', $BaseRevision, '-EventName', $EventName, '-AuthorityRevision', [string]$pin.commit,
            '-TimeoutSeconds', [string]$TimeoutSeconds, '-TrustedToolRoot', $trustedRoot, '-SourceValidation', '-RunId', [string]$prepared.runId)
        if (-not [string]::IsNullOrWhiteSpace($CancellationPath)) { $arguments += @('-CancellationPath', [IO.Path]::GetFullPath($CancellationPath)) }
        # The canonical source child inherits this test-only variable. Clear any
        # developer override so CommonToolReportIntegration resolves Validate.ps1
        # from the immutable candidate snapshot under the protected Core run root.
        [Environment]::SetEnvironmentVariable('SYP154_TEST_VALIDATE_SOURCE', $null, 'Process')
        $centralRunnerTimer = [Diagnostics.Stopwatch]::StartNew()
        try {
            $runnerOutput = @(& $powerShell -NoProfile -NonInteractive -File $centralRunner @arguments 2>&1)
            $processExitCode = $LASTEXITCODE
        }
        finally {
            $centralRunnerTimer.Stop()
            $centralRunnerSeconds = [Math]::Round($centralRunnerTimer.Elapsed.TotalSeconds, 3)
        }
        $runnerOutput | Out-Host
        if ($processExitCode -eq 0) {
            $reportRunnerContext = [ordered]@{
                CandidateRoot = $RepositoryRoot
                AdapterPath = $paths.adapterPath
                ArtifactsRoot = $paths.artifactsRoot
                OutputPath = $paths.outputPath
                SourceRepository = $script:SourceRepository
                SourceRevision = $CandidateRevision
                BaseRevision = $BaseRevision
                EventName = $EventName
                RunId = [string]$prepared.runId
                AuthorityRevision = [string]$pin.commit
                TimeoutSeconds = $TimeoutSeconds
                CancellationPath = if ([string]::IsNullOrWhiteSpace($CancellationPath)) { '' } else { [IO.Path]::GetFullPath($CancellationPath) }
                TrustedToolRoot = $trustedRoot
            }
            $reportRunnerModule = New-CodeSourceStandardValidationModule -RunnerPath $centralRunner `
                -RunnerSha256 ([string]$pin.files['scripts/Invoke-StandardValidation.ps1']) -RunnerArguments $reportRunnerContext `
                -SourceValidation
            $report = Read-JsonFile -Path $paths.outputPath -Context 'Standard Core SourceValidation report'
            [void](Invoke-CodeSourceStandardValidationModule -Module $reportRunnerModule -FunctionName 'Assert-StandardCoreSourceCheckReport' `
                -Arguments @{ Report = $report; ExpectedSourceRevision = $CandidateRevision; ExpectedBaseRevision = $BaseRevision; `
                    ExpectedAuthorityRevision = [string]$pin.commit; ExpectedEventName = $EventName; ArtifactsRoot = $paths.artifactsRoot; `
                    OutputPath = $paths.outputPath; ProcessExitCode = $processExitCode })
            [void](Assert-CodeSourceReportBinding -Report $report -Prepared $prepared -CandidateRevision $CandidateRevision `
                -BaseRevision $BaseRevision -AuthorityRevision ([string]$pin.commit) -EventName $EventName -ArtifactsRoot $paths.artifactsRoot `
                -OutputPath $paths.outputPath -ProcessExitCode $processExitCode -CleanupSucceeded $true `
                -CancellationRequested ([bool](-not [string]::IsNullOrWhiteSpace($CancellationPath) -and (Test-Path -LiteralPath $CancellationPath))))
            $sourceReportAccepted = $true
        }
    }
    finally {
        [Environment]::SetEnvironmentVariable('SYP154_TEST_VALIDATE_SOURCE', $previousTestValidateSource, 'Process')
        if ($null -ne $reportRunnerModule) {
            try {
                Remove-Module -ModuleInfo $reportRunnerModule -Force -ErrorAction Stop
                $reportRunnerModule = $null
            }
            catch {
                $runnerModuleCleanupSucceeded = $false
                $script:SourceCleanupFailed = $true
                $cleanupErrorMessage = "Central Standard Core module cleanup failed: $($_.Exception.Message)"
            }
        }
        if ($adapterRootCreated -and (Test-Path -LiteralPath $paths.adapterRoot -PathType Container)) {
            try {
                $expectedAdapterRoot = [IO.Path]::GetFullPath((Join-Path (Split-Path -Parent $paths.artifactsRoot) ".core-v2-adapter-$($prepared.runId)"))
                if (-not (Test-PathEqual -Left $paths.adapterRoot -Right $expectedAdapterRoot) -or
                    -not (Test-PathWithinOrEqual -Path $paths.adapterRoot -Root (Split-Path -Parent $paths.artifactsRoot)) -or
                    (Test-PathWithinOrEqual -Path $paths.adapterRoot -Root $paths.artifactsRoot)) { throw 'Source Core adapter cleanup escaped its unique sibling boundary.' }
                Assert-NoReparseAncestors -Path $paths.adapterRoot -Context 'Source Core adapter cleanup root'
                Remove-Item -LiteralPath $paths.adapterRoot -Recurse -Force -ErrorAction Stop
                if (Test-Path -LiteralPath $paths.adapterRoot) { throw 'Source Core adapter cleanup failed.' }
                $cleanupSucceeded = $true
            }
            catch {
                $script:SourceCleanupFailed = $true
                $cleanupErrorMessage = $_.Exception.Message
            }
        }
        $sourceValidationTimer.Stop()
        $sourceValidationCompletedAtUtc = [DateTimeOffset]::UtcNow
        $combinedWallSeconds = [Math]::Round(($sourceValidationCompletedAtUtc - [DateTimeOffset]::Parse([string]$setupTiming.startedAtUtc)).TotalSeconds, 3)
        $timingRoot = Split-Path -Parent $paths.artifactsRoot
        $sourceTimingPath = Join-Path $timingRoot "source-validation-timing-$($prepared.runId).json"
        $timingEvidence = [ordered]@{
            schemaVersion = 1
            runId = [string]$prepared.runId
            candidateRevision = $CandidateRevision
            baseRevision = $BaseRevision
            authorityRevision = [string]$pin.commit
            setupTimingPath = [IO.Path]::GetFullPath($setupTimingPath)
            setupTimingSha256 = [string]$setupTimingBinding[0].sha256
            setupCompletedTimingPath = [IO.Path]::GetFullPath($setupCompletedTimingPath)
            setupCompletedTimingSha256 = $setupCompletedTimingSha256
            setupTotalSeconds = [double]$setupCompletedTiming.setupTotalSeconds
            sourceValidationStartedAtUtc = $sourceValidationStartedAtUtc.ToString('O')
            sourceValidationCompletedAtUtc = $sourceValidationCompletedAtUtc.ToString('O')
            sourceValidationTotalSeconds = [Math]::Round($sourceValidationTimer.Elapsed.TotalSeconds, 3)
            centralRunnerSeconds = $centralRunnerSeconds
            combinedSetupToValidationSeconds = $combinedWallSeconds
            diagnosticTargetSeconds = 1200
            diagnosticTargetExceeded = ($combinedWallSeconds -gt 1200)
            processExitCode = $processExitCode
            reportAccepted = $sourceReportAccepted
            cleanupSucceeded = ($cleanupSucceeded -and $runnerModuleCleanupSucceeded)
        }
        try {
            Assert-OutsideRoot -Path $sourceTimingPath -Root $RepositoryRoot -Context 'Source timing evidence'
            Assert-OutsideRoot -Path $sourceTimingPath -Root $authority.root -Context 'Source timing evidence'
            Assert-NoReparseAncestors -Path $timingRoot -Context 'Source timing evidence root'
            Write-Utf8NoBomCreateNew -Path $sourceTimingPath -Text (($timingEvidence | ConvertTo-Json -Depth 30) + [Environment]::NewLine)
            [Console]::Out.WriteLine("Source timing evidence: $sourceTimingPath")
        }
        catch {
            if ($null -eq $cleanupErrorMessage) { $cleanupErrorMessage = "Could not retain source timing evidence: $($_.Exception.Message)" }
        }
        if ($null -ne $cleanupErrorMessage) { throw "SOURCE_CLEANUP| $cleanupErrorMessage" }
    }
    if ($processExitCode -eq 0 -and (-not $cleanupSucceeded -or -not $runnerModuleCleanupSucceeded)) { throw 'Source Core cleanup status is not complete.' }
    if ($processExitCode -ne 0 -and (Test-Path -LiteralPath $paths.outputPath -PathType Leaf)) {
        [Console]::Error.WriteLine("Source Core report retained for failed process exit $($processExitCode): $($paths.outputPath)")
    }
    $script:ValidationExitCode = $processExitCode
    if ($processExitCode -ne 0) { exit $processExitCode }
    [Console]::Out.WriteLine("SourceValidation PASS: $($paths.outputPath) (RunId $($prepared.runId), adapter sha256 $adapterSha)")
}

$script:ValidationExitCode = 1
$script:ExternalCleanupRoots = @()
$script:SourceModeRequested = [bool]($PrepareSourceTools -or $SourceValidation)
$script:SourceInvalidInput = $false
$script:SourceCleanupFailed = $false

try {
    $repoRoot = if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
        [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
    }
    else { [IO.Path]::GetFullPath($RepositoryRoot) }
    if (-not (Test-Path -LiteralPath $repoRoot -PathType Container)) { throw "RepositoryRoot does not exist: $repoRoot" }
    $gitPath = Get-ResolvedGitPath
    $candidateCommit = Resolve-GitRevision -GitPath $gitPath -Root $repoRoot -Revision 'HEAD' -Context 'Candidate revision'
    $dirty = @(& $gitPath -C $repoRoot status --porcelain=v1 --untracked-files=all)
    if ($LASTEXITCODE -ne 0 -or $dirty.Count -ne 0) { throw 'Canonical validation requires a clean immutable candidate commit.' }
    $unbased = [string]::IsNullOrWhiteSpace($BaseCommit)
    if ($unbased) {
        # The P02 runner requires a concrete commit identity. Keep the no-base state
        # separately and use the candidate only as that technical identity; semantic
        # change detection below compares the full candidate against the empty tree.
        $baseRevision = $candidateCommit
    }
    else {
        $baseRevision = Resolve-GitRevision -GitPath $gitPath -Root $repoRoot -Revision $BaseCommit -Context 'Base commit'
        & $gitPath -C $repoRoot merge-base --is-ancestor $baseRevision $candidateCommit
        if ($LASTEXITCODE -ne 0 -or $baseRevision -ceq $candidateCommit) { throw 'Base commit must be a distinct ancestor of the immutable candidate.' }
    }

    # The protected driver keeps its exact active 8a authority pin. Candidate
    # source mode may select only the independently reviewed ff85 preparation tuple.
    $driverRoot = Split-Path -Parent $PSScriptRoot
    $trustedConfig = Read-JsonFile -Path (Join-Path $driverRoot 'config/standard-v1.json') -Context 'protected driver config/standard-v1.json'
    Assert-ProtectedDriverAuthorityConfig -Config $trustedConfig
    if ($script:SourceModeRequested) { $script:SourceInvalidInput = $true }
    $config = Read-JsonFile -Path (Join-Path $repoRoot 'config/standard-v1.json') -Context 'config/standard-v1.json'
    $sourceDriverPath = Join-Path $PSScriptRoot 'StandardSourceDriver.psm1'
    Import-Module -Name $sourceDriverPath -Force -ErrorAction Stop
    $sourceRequestArgs = @{
        ExecutionMode = $ExecutionMode
        AdapterVersion = $AdapterVersion
        AuthorityCommit = [string]$config.authority.commit
        CompleteLifecycle = $false
        DevelopmentHarness = $false
    }
    if ($PSBoundParameters.ContainsKey('PrepareSourceTools')) { $sourceRequestArgs.PrepareSourceTools = [bool]$PrepareSourceTools }
    if ($PSBoundParameters.ContainsKey('SourceValidation')) { $sourceRequestArgs.SourceValidation = [bool]$SourceValidation }
    if ($PSBoundParameters.ContainsKey('SourceToolsPath')) { $sourceRequestArgs.SourceToolsPath = [string]$SourceToolsPath }
    if ($sourceRequestArgs.ContainsKey('SourceValidation') -and [bool]$sourceRequestArgs.SourceValidation) {
        try {
            $preparedHint = Read-JsonFile -Path ([string]$SourceToolsPath) -Context 'Prepared source tools'
            $sourceRequestArgs.RunId = [string]$preparedHint.runId
            $ownedRuntime = [IO.Path]::GetFullPath([string]$preparedHint.pesterRuntime.runtimeRoot)
            $ownedPowerShell = [IO.Path]::GetFullPath([string]$preparedHint.pesterRuntime.runtimeExecutablePath)
            if (-not $ownedRuntime.Equals([IO.Path]::GetFullPath((Join-Path ([string]$preparedHint.ownedRoot) 'runtime')), $(if ($IsWindows) { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal })) -or
                -not $ownedPowerShell.Equals([IO.Path]::GetFullPath((Join-Path $ownedRuntime $(if ($IsWindows) { 'pwsh.exe' } else { 'pwsh' }))), $(if ($IsWindows) { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal })) -or
                [string]$preparedHint.pesterRuntime.runtimeExecutableSha256 -cnotmatch '^[0-9a-f]{64}$' -or
                -not (Test-Path -LiteralPath $ownedPowerShell -PathType Leaf) -or
                (Get-FileSha256 -Path $ownedPowerShell) -cne [string]$preparedHint.pesterRuntime.runtimeExecutableSha256) {
                throw 'Prepared owned PowerShell runtime path or executable hash is invalid.'
            }
        }
        catch { throw "INVALID_SOURCE_METADATA| Prepared source tools cannot be admitted: $($_.Exception.Message)" }
    }
    try { $sourceRequest = Assert-CodeSourceRunRequest @sourceRequestArgs }
    catch { if ($script:SourceModeRequested) { throw "INVALID_SOURCE_REQUEST| $($_.Exception.Message)" }; throw }
    if ($sourceRequest -in @('PrepareSourceTools', 'SourceValidation')) {
        [void](Assert-CodeSourceAuthorityConfig -Config $config)
    }
    else {
        Assert-AuthorityConfig -Config $config
    }
    $script:SourceInvalidInput = $false

    # Resolve the child PowerShell only after candidate authority and mode guards.
    $pwshPath = if ($sourceRequest -eq 'SourceValidation') {
        [IO.Path]::GetFullPath([string]$preparedHint.pesterRuntime.runtimeExecutablePath)
    }
    else { Get-ResolvedPowerShellPath }

    if ($sourceRequest -eq 'PrepareSourceTools') {
        $script:ValidationExitCode = 1
        Invoke-CodeSourceToolSetup -GitPath $gitPath -PowerShellPath $pwshPath -RepositoryRoot $repoRoot `
            -CandidateRevision $candidateCommit -AuthorityConfig $config -SourceToolsPath $SourceToolsPath `
            -AuthorityRepositoryRoot $AuthorityRepositoryRoot -TrustedToolRoot $TrustedToolRoot `
            -ExpectedGoRuntimeVersion $ExpectedGoRuntimeVersion -TimeoutSeconds $TimeoutSeconds
        $script:ValidationExitCode = 0
        exit 0
    }
    if ($sourceRequest -eq 'SourceValidation') {
        $script:ValidationExitCode = 1
        Invoke-CodeSourceValidation -GitPath $gitPath -PowerShellPath $pwshPath -RepositoryRoot $repoRoot `
            -CandidateRevision $candidateCommit -BaseRevision $baseRevision -AuthorityConfig $config `
            -SourceToolsPath $SourceToolsPath -AuthorityRepositoryRoot $AuthorityRepositoryRoot `
            -TrustedToolRoot $TrustedToolRoot -ArtifactsRoot $ArtifactsRoot -OutputPath $OutputPath `
            -EventName (Get-EventName) -TimeoutSeconds $TimeoutSeconds `
            -ArtifactsRootWasExplicit ([bool]$PSBoundParameters.ContainsKey('ArtifactsRoot')) -CancellationPath $CancellationPath
        $script:ValidationExitCode = 0
        exit 0
    }

    $activeSkillIds = Get-ActiveSkillIds -Root $repoRoot
    $eventName = Get-EventName
    $goRuntimeVersion = Resolve-GoRuntimeVersion -Expected $ExpectedGoRuntimeVersion

    $artifactsRootPath = [IO.Path]::GetFullPath($ArtifactsRoot)
    Assert-OutsideRoot -Path $artifactsRootPath -Root $repoRoot -Context 'Artifacts root'
    [void](New-Item -ItemType Directory -Path $artifactsRootPath -Force)
    Assert-NoReparseAncestors -Path $artifactsRootPath -Context 'Artifacts root'

    $runId = [guid]::NewGuid().ToString('N')
    $runRoot = Join-Path $artifactsRootPath "skcv1-$($runId.Substring(0, 12))"
    if (Test-Path -LiteralPath $runRoot) { throw 'Run-owned artifact path unexpectedly exists.' }
    [void](New-Item -ItemType Directory -Path $runRoot -Force)
    $outputFull = if ([string]::IsNullOrWhiteSpace($OutputPath)) { Join-Path $runRoot 'code-collaboration-conformance-report.json' } else { Assert-PathWithinRoot -Path $OutputPath -Root $artifactsRootPath -Context 'OutputPath' }
    if (Test-Path -LiteralPath $outputFull -PathType Leaf) { throw "OutputPath already exists and evidence is create-only: $outputFull" }

    $externalRootParent = Split-Path -Parent $artifactsRootPath
    $externalRootCandidates = @(
        [IO.Path]::GetTempPath(),
        [Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData),
        [Environment]::GetFolderPath([Environment+SpecialFolder]::UserProfile),
        $externalRootParent
    )
    $externalRootParent = $null
    foreach ($candidateParent in $externalRootCandidates) {
        if ([string]::IsNullOrWhiteSpace([string]$candidateParent)) { continue }
        $candidateParentFull = [IO.Path]::GetFullPath([string]$candidateParent)
        if (Test-PathWithinOrEqual -Path $candidateParentFull -Root $artifactsRootPath) { continue }
        if (-not (Test-Path -LiteralPath $candidateParentFull -PathType Container)) { continue }
        $externalRootParent = $candidateParentFull
        break
    }
    if ([string]::IsNullOrWhiteSpace($externalRootParent)) { throw 'Could not allocate a writable external run-root parent outside ArtifactsRoot.' }
    $trustedRoot = Join-Path $externalRootParent "skcv1-tools-$runId"
    $candidateExtractRoot = Join-Path $externalRootParent "skcv1-candidate-$runId"
    $resolvedToolsRoot = Join-Path $externalRootParent "skcv1-resolved-tools-$runId"
    if ((Test-Path -LiteralPath $trustedRoot) -or (Test-Path -LiteralPath $candidateExtractRoot) -or (Test-Path -LiteralPath $resolvedToolsRoot)) { throw 'Run-owned temporary root unexpectedly exists.' }
    $script:ExternalCleanupRoots = @($trustedRoot, $candidateExtractRoot, $resolvedToolsRoot)
    [void](New-Item -ItemType Directory -Path $trustedRoot -Force)
    [void](New-Item -ItemType Directory -Path $candidateExtractRoot -Force)
    [void](New-Item -ItemType Directory -Path $resolvedToolsRoot -Force)
    Assert-OutsideRoot -Path $trustedRoot -Root $repoRoot -Context 'Trusted tool root'
    Assert-OutsideRoot -Path $trustedRoot -Root $artifactsRootPath -Context 'Trusted tool root'
    Assert-OutsideRoot -Path $candidateExtractRoot -Root $artifactsRootPath -Context 'Candidate snapshot root'
    Assert-OutsideRoot -Path $resolvedToolsRoot -Root $repoRoot -Context 'Resolved tools root'
    Assert-OutsideRoot -Path $resolvedToolsRoot -Root $artifactsRootPath -Context 'Resolved tools root'
    Assert-NoReparseAncestors -Path $trustedRoot -Context 'Trusted tool root'
    Assert-NoReparseAncestors -Path $candidateExtractRoot -Context 'Candidate snapshot root'
    Assert-NoReparseAncestors -Path $resolvedToolsRoot -Context 'Resolved tools root'

    $candidateGitEntryModeManifestPath = Join-Path $runRoot 'candidate-git-entry-modes.json'
    $candidateGitEntryModeManifest = Get-GitEntryModeManifest -GitPath $gitPath -RepositoryRoot $repoRoot -CandidateCommit $candidateCommit
    Write-Utf8NoBom -Path $candidateGitEntryModeManifestPath -Text ($candidateGitEntryModeManifest | ConvertTo-Json -Depth 20)
    $candidateGitEntryModeManifestSha256 = Get-FileSha256 -Path $candidateGitEntryModeManifestPath

    $candidateArchivePath = Join-Path $runRoot 'candidate.zip'
    & $gitPath -C $repoRoot archive --format=zip "--prefix=candidate-$candidateCommit/" "--output=$candidateArchivePath" $candidateCommit
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $candidateArchivePath -PathType Leaf)) { throw 'Could not create the immutable candidate archive.' }
    $candidateArchiveSha256 = Get-FileSha256 -Path $candidateArchivePath
    Expand-Archive -LiteralPath $candidateArchivePath -DestinationPath $candidateExtractRoot -Force
    $candidateRoots = @(Get-ChildItem -LiteralPath $candidateExtractRoot -Directory -Force)
    if ($candidateRoots.Count -ne 1) { throw 'Candidate archive must contain exactly one repository root.' }
    $candidateRoot = [IO.Path]::GetFullPath($candidateRoots[0].FullName)
    Assert-NoReparseAncestors -Path $candidateRoot -Context 'Candidate snapshot root'

    $authorityArchive = Join-Path $runRoot 'authority.zip'
    if ([string]::IsNullOrWhiteSpace($AuthorityArchivePath)) {
        Invoke-WebRequest -Uri ([string]$config.authority.archiveUrl) -OutFile $authorityArchive
    }
    else {
        $supplied = [IO.Path]::GetFullPath($AuthorityArchivePath)
        if (-not (Test-Path -LiteralPath $supplied -PathType Leaf)) { throw "Supplied authority archive does not exist: $supplied" }
        Copy-Item -LiteralPath $supplied -Destination $authorityArchive -Force
    }
    if ((Get-FileSha256 -Path $authorityArchive) -cne $script:AuthorityArchiveSha256) { throw 'Authority archive SHA-256 does not match the exact P02 authority snapshot.' }
    $authorityExtract = Join-Path $trustedRoot 'authority'
    [void](New-Item -ItemType Directory -Path $authorityExtract -Force)
    Expand-Archive -LiteralPath $authorityArchive -DestinationPath $authorityExtract -Force
    $authorityRoots = @(Get-ChildItem -LiteralPath $authorityExtract -Directory -Force)
    if ($authorityRoots.Count -ne 1) { throw 'Authority archive must contain exactly one repository root.' }
    $authorityRoot = [IO.Path]::GetFullPath($authorityRoots[0].FullName)
    foreach ($entry in $script:AuthorityFiles.GetEnumerator()) {
        $authorityPath = Assert-PathWithinRoot -Path (Join-Path $authorityRoot ($entry.Key -replace '/', [IO.Path]::DirectorySeparatorChar)) -Root $authorityRoot -Context 'Authority file'
        if (-not (Test-Path -LiteralPath $authorityPath -PathType Leaf)) { throw "Authority file is missing: $($entry.Key)" }
        if ((Get-FileSha256 -Path $authorityPath) -cne $entry.Value) { throw "Authority file identity mismatch: $($entry.Key)" }
    }
    $standardText = Get-Content -LiteralPath (Join-Path $authorityRoot 'docs/standards/skill-repository-standard.md') -Raw -Encoding UTF8
    if ($standardText -cnotmatch '(?m)^# Agent Skill Repository Standard v1$' -or $standardText -cnotmatch '(?m)^Status: \*\*Normative\*\*$') { throw 'Verified P02 authority snapshot is not the normative Standard v1.' }

    $resolverPath = Join-Path $authorityRoot 'scripts/Resolve-StandardValidationTool.ps1'
    $policyPath = Join-Path $authorityRoot 'docs/standards/validation-toolchain.json'
    $centralRunnerPath = Join-Path $authorityRoot 'scripts/Invoke-StandardValidation.ps1'
    $upstreamAdapterPath = Join-Path $authorityRoot 'scripts/Validate-UpstreamAdapter.ps1'
    $upstreamPolicyPath = Join-Path $authorityRoot 'docs/standards/upstream-adapter.json'
    $policyReceiptPath = Join-Path $runRoot 'policy.json'
    Invoke-Resolver -PowerShellPath $pwshPath -ResolverPath $resolverPath -Arguments @('-PolicyPath', $policyPath, '-ValidatePolicyOnly', '-OutputPath', $policyReceiptPath)
    $policyReceipt = Read-JsonFile -Path $policyReceiptPath -Context 'Validation tool policy receipt'
    if ([string]$policyReceipt.policy -cne 'latest-stable-per-validation-run' -or
        [string]$policyReceipt.sourceTrust.enforcement -cne 'exact-approved-source' -or $policyReceipt.recordResolvedIdentityWhenAvailable -ne $true) {
        throw 'Validation tool policy receipt does not preserve the central trust contract.'
    }
    $receipts = [ordered]@{}
    foreach ($toolName in @('skillspector', 'skill-validator', 'skill-tools', 'pester')) {
        $receiptPath = Join-Path $runRoot "receipt-$toolName.json"
        Invoke-Resolver -PowerShellPath $pwshPath -ResolverPath $resolverPath -Arguments @('-PolicyPath', $policyPath, '-ToolName', $toolName, '-Install', '-InstallRoot', $resolvedToolsRoot, '-ExpectedGoRuntimeVersion', $goRuntimeVersion, '-OutputPath', $receiptPath)
        $receipt = Read-JsonFile -Path $receiptPath -Context "$toolName resolver receipt"
        if ([string]$receipt.toolName -cne $toolName -or [string]$receipt.channel -cne 'latest-stable' -or $receipt.frozenForRun -ne $true -or
            [string]::IsNullOrWhiteSpace([string]$receipt.resolvedVersion) -or [string]::IsNullOrWhiteSpace([string]$receipt.resolvedIdentity)) { throw "$toolName resolver receipt is not an exact frozen latest-stable identity." }
        $receipts[$toolName] = $receipt
        if ($toolName -ceq 'skillspector') {
            Remove-Item -LiteralPath 'Env:GITHUB_TOKEN', 'Env:GH_TOKEN' -Force -ErrorAction SilentlyContinue
        }
    }

    $toolchain = [ordered]@{
        centralRunnerPath = [IO.Path]::GetFullPath($centralRunnerPath)
        centralRunnerSha256 = [string]$script:AuthorityFiles['scripts/Invoke-StandardValidation.ps1']
        upstreamAdapterValidatorPath = [IO.Path]::GetFullPath($upstreamAdapterPath)
        upstreamAdapterValidatorSha256 = Get-FileSha256 -Path $upstreamAdapterPath
        upstreamPolicyPath = [IO.Path]::GetFullPath($upstreamPolicyPath)
        upstreamPolicySha256 = Get-FileSha256 -Path $upstreamPolicyPath
        skillValidatorPath = [IO.Path]::GetFullPath([string]$receipts.'skill-validator'.executablePath)
        skillValidatorSha256 = [string]$receipts.'skill-validator'.executableSha256
        skillToolsNodePath = [IO.Path]::GetFullPath([string]$receipts.'skill-tools'.nodePath)
        skillToolsNodeSha256 = [string]$receipts.'skill-tools'.nodeSha256
        skillToolsEntryPointPath = [IO.Path]::GetFullPath([string]$receipts.'skill-tools'.entryPointPath)
        skillToolsEntryPointSha256 = [string]$receipts.'skill-tools'.entryPointSha256
        skillSpectorPath = [IO.Path]::GetFullPath([string]$receipts.skillspector.executablePath)
        skillSpectorSha256 = [string]$receipts.skillspector.executableSha256
        pesterModulePath = [IO.Path]::GetFullPath([string]$receipts.pester.modulePath)
        pesterModuleSha256 = [string]$receipts.pester.executableSha256
        pesterVersion = [string]$receipts.pester.resolvedVersion
    }
    foreach ($entry in @(
        [pscustomobject]@{ path = $toolchain.skillValidatorPath; sha = $toolchain.skillValidatorSha256; name = 'skill-validator'; confineToResolvedRoot = $true },
        [pscustomobject]@{ path = $toolchain.skillToolsNodePath; sha = $toolchain.skillToolsNodeSha256; name = 'skill-tools Node'; confineToResolvedRoot = $false },
        [pscustomobject]@{ path = $toolchain.skillToolsEntryPointPath; sha = $toolchain.skillToolsEntryPointSha256; name = 'skill-tools entry point'; confineToResolvedRoot = $true },
        [pscustomobject]@{ path = $toolchain.skillSpectorPath; sha = $toolchain.skillSpectorSha256; name = 'SkillSpector'; confineToResolvedRoot = $true },
        [pscustomobject]@{ path = $toolchain.pesterModulePath; sha = $toolchain.pesterModuleSha256; name = 'Pester'; confineToResolvedRoot = $true }
    )) {
        $toolPath = [IO.Path]::GetFullPath([string]$entry.path)
        if ($entry.confineToResolvedRoot) {
            [void](Assert-PathWithinRoot -Path $toolPath -Root $resolvedToolsRoot -Context "$($entry.name) receipt path")
        }
        Assert-NoReparseAncestors -Path $toolPath -Context "$($entry.name) receipt path"
        Assert-Sha256 -Value ([string]$entry.sha) -Context "$($entry.name) receipt hash"
        if ((Get-FileSha256 -Path $toolPath) -cne [string]$entry.sha) { throw "$($entry.name) changed after resolver completion." }
    }
    $toolchainPath = Join-Path $trustedRoot 'toolchain.json'
    Write-Utf8NoBom -Path $toolchainPath -Text (($toolchain | ConvertTo-Json -Depth 20) + [Environment]::NewLine)
    $toolchainSha256 = Get-FileSha256 -Path $toolchainPath
    $childRunnerPath = Join-Path $trustedRoot 'Invoke-CodeCollaborationValidationChild.ps1'
    Write-Utf8NoBom -Path $childRunnerPath -Text $childRunnerText

    $semanticRequired = $unbased
    $changeDetectionBase = if ($unbased) { $script:EmptyTreeObject } else { $baseRevision }
    $changedRecords = @(& $gitPath -C $repoRoot diff --find-renames=100% --name-status $changeDetectionBase $candidateCommit)
    if ($LASTEXITCODE -ne 0) { throw 'Could not determine the immutable candidate change set.' }
    $changedPaths = @()
    foreach ($changedRecord in $changedRecords) {
        $fields = ([string]$changedRecord) -split "`t"
        if ($fields.Count -lt 2) { throw 'Git change detection returned a malformed status record.' }
        $status = [string]$fields[0]
        $pathValues = if ($status -cmatch '^[RC][0-9]+$') {
            if ($fields.Count -ne 3) { throw 'Git change detection returned a malformed rename or copy record.' }
            @($fields[1], $fields[2])
        }
        else { @($fields[1]) }
        foreach ($pathValue in $pathValues) { $changedPaths += [string]$pathValue }
    }
    foreach ($changedPath in $changedPaths) {
        if ([string]$changedPath -like 'skills/*') { $semanticRequired = $true; break }
    }
    $commonArguments = @('-NoProfile', '-NonInteractive', '-File', $childRunnerPath, '-ToolchainPath', $toolchainPath, '-ToolchainSha256', $toolchainSha256, '-SourceRepository', $script:SourceRepository, '-SourceRevision', $candidateCommit, '-ArchiveSha256', $candidateArchiveSha256, '-GitEntryModeManifestPath', $candidateGitEntryModeManifestPath, '-GitEntryModeManifestSha256', $candidateGitEntryModeManifestSha256)
    $adapter = [ordered]@{
        schemaVersion = 1
        adapter = 'standard-validation-adapter-v1'
        mode = 'development-harness'
        skillsRoot = 'skills'
        activeSkills = @($activeSkillIds)
        canonicalValidatorPath = 'scripts/Validate.ps1'
        packageAdapter = [ordered]@{ command = $pwshPath; arguments = @($commonArguments + @('-Mode', 'package-adapter')) }
        skillValidator = [ordered]@{ command = $pwshPath; arguments = @($commonArguments + @('-Mode', 'skill-validator')) }
        skillTools = [ordered]@{ command = $pwshPath; arguments = @($commonArguments + @('-Mode', 'skill-tools')) }
        staticAnalyzer = [ordered]@{ command = $pwshPath; arguments = @($commonArguments + @('-Mode', 'static', '-SemanticRequired', $semanticRequired.ToString().ToLowerInvariant())) }
        repositoryTests = @(
            [ordered]@{ id = 'repository-test-integrity'; kind = 'general'; command = $pwshPath; arguments = @($commonArguments + @('-Mode', 'repository-knowledge')) }
            [ordered]@{ id = 'repository-test-catalog'; kind = 'general'; command = $pwshPath; arguments = @($commonArguments + @('-Mode', 'repository-catalog')) }
            [ordered]@{ id = 'repository-test-pester'; kind = 'pester'; command = $pwshPath; arguments = @($commonArguments + @('-Mode', 'repository-pester')) }
        )
    }
    $adapterPath = Join-Path $trustedRoot 'standard-validation-adapter.json'
    Write-Utf8NoBom -Path $adapterPath -Text (($adapter | ConvertTo-Json -Depth 50) + [Environment]::NewLine)
    $centralRunnerArgs = @(
        '-CandidateRoot', $candidateRoot,
        '-AdapterPath', $adapterPath,
        '-ArtifactsRoot', $artifactsRootPath,
        '-OutputPath', $outputFull,
        '-SourceRepository', $script:SourceRepository,
        '-SourceRevision', $candidateCommit,
        '-BaseRevision', $baseRevision,
        '-EventName', $eventName,
        '-TimeoutSeconds', [string]$TimeoutSeconds,
        '-TrustedToolRoot', $trustedRoot,
        '-DevelopmentHarness'
    )
    $centralOutput = @(& $pwshPath -NoProfile -NonInteractive -File $centralRunnerPath @centralRunnerArgs 2>&1)
    $centralExitCode = $LASTEXITCODE
    $centralOutput | Out-Host
    if ($centralExitCode -ne 0 -and (Test-Path -LiteralPath $outputFull -PathType Leaf)) {
        try {
            $finalReport = Get-Content -LiteralPath $outputFull -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 100
            foreach ($event in @($finalReport.stages | ForEach-Object { $_.events } | Where-Object { $_.status -ne 'passed' })) {
                $eventPath = [string]$event.outputPath
                if (-not [string]::IsNullOrWhiteSpace($eventPath) -and (Test-Path -LiteralPath $eventPath -PathType Leaf)) {
                    Write-Host "Canonical child diagnostic: $($event.stageId)/$($event.toolId)"
                    Get-Content -LiteralPath $eventPath -Raw -Encoding UTF8 | Out-Host
                }
            }
        }
        catch {
            Write-Warning "Could not print canonical child diagnostics: $($_.Exception.Message)"
        }
    }
    $script:ValidationExitCode = $centralExitCode
}
catch {
    if (-not $script:SourceModeRequested) { throw }
    [Console]::Error.WriteLine($_.Exception.Message)
    if ($script:SourceCleanupFailed) { $script:ValidationExitCode = 20 }
    elseif (-not [string]::IsNullOrWhiteSpace($CancellationPath) -and (Test-Path -LiteralPath $CancellationPath)) { $script:ValidationExitCode = 40 }
    elseif ($script:SourceInvalidInput -or [string]$_.Exception.Message -match '^(INVALID_SOURCE_REQUEST|INVALID_SOURCE_METADATA)\|') { $script:ValidationExitCode = 30 }
    else { $script:ValidationExitCode = 20 }
}
finally {
    foreach ($cleanupRoot in @($script:ExternalCleanupRoots)) {
        if ([string]::IsNullOrWhiteSpace([string]$cleanupRoot) -or -not (Test-Path -LiteralPath $cleanupRoot)) { continue }
        try {
            Remove-Item -LiteralPath $cleanupRoot -Recurse -Force -ErrorAction Stop
        }
        catch {
            $script:ValidationExitCode = if ($script:SourceModeRequested) { 20 } else { 1 }
            [Console]::Error.WriteLine("Could not remove run-owned temporary root '$cleanupRoot': $($_.Exception.Message)")
        }
    }
}
if ($script:ValidationExitCode -ne 0) { exit $script:ValidationExitCode }
