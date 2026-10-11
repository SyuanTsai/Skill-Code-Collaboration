# SPDX-FileCopyrightText: 2026 SyuanTsai
# SPDX-License-Identifier: Apache-2.0
#requires -Version 7.0

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string] $RepositoryRoot,
    [Parameter(Mandatory = $true)][string] $ToolchainPath,
    [Parameter(Mandatory = $true)][ValidatePattern('^[0-9a-f]{64}$')][string] $ToolchainSha256
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-UniqueProcessArgumentValue {
    param([Parameter(Mandatory = $true)][string] $Name)

    $arguments = [Environment]::GetCommandLineArgs()
    $matches = [Collections.Generic.List[string]]::new()
    for ($index = 0; $index -lt $arguments.Count; $index++) {
        if ([string]$arguments[$index] -ceq "-$Name") {
            if ($index + 1 -ge $arguments.Count -or [string]::IsNullOrWhiteSpace([string]$arguments[$index + 1])) {
                throw "Process command line is missing the value for -$Name."
            }
            $matches.Add([string]$arguments[$index + 1])
        }
    }
    if ($matches.Count -ne 1) { throw "Process command line must contain exactly one -$Name binding." }
    return $matches[0]
}

function Get-FileSha256 {
    param([Parameter(Mandatory = $true)][string] $Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
}

function Assert-NoReparseAncestors {
    param([Parameter(Mandatory = $true)][string] $Path)
    $cursor = [IO.Path]::GetFullPath($Path)
    while (-not [string]::IsNullOrWhiteSpace($cursor)) {
        $item = Get-Item -LiteralPath $cursor -Force -ErrorAction Stop
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Legacy archive fixture contains a reparse point: $cursor" }
        $parent = Split-Path -Parent $cursor
        if ($parent -ceq $cursor -or [string]::IsNullOrWhiteSpace($parent)) { break }
        $cursor = $parent
    }
}

$root = [IO.Path]::GetFullPath($RepositoryRoot)
$toolchainFullPath = [IO.Path]::GetFullPath($ToolchainPath)
$toolchainArgPath = [IO.Path]::GetFullPath((Get-UniqueProcessArgumentValue -Name 'ToolchainPath'))
$toolchainArgSha = Get-UniqueProcessArgumentValue -Name 'ToolchainSha256'
$pathComparison = if ($IsWindows) { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal }
if (-not $toolchainArgPath.Equals($toolchainFullPath, $pathComparison) -or $toolchainArgSha -cne $ToolchainSha256) {
    throw 'Legacy archive fixture parameters differ from the unique actual process CLI bindings.'
}
if (-not [string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable('SYP154_CANDIDATE_AUTHORITY_ROOT', 'Process'))) {
    throw 'Legacy archive fixture mode requires SYP154_CANDIDATE_AUTHORITY_ROOT to be absent.'
}
Assert-NoReparseAncestors -Path $toolchainFullPath
$toolsRoot = [IO.Path]::GetFullPath((Split-Path -Parent $toolchainFullPath))
if ((Split-Path -Leaf $toolchainFullPath) -cne 'toolchain.json' -or
    (Split-Path -Leaf $toolsRoot) -cnotmatch '^skcv1-tools-(?<run>[0-9a-f]{32})$') {
    throw 'Legacy archive fixture toolchain path is not the exact run-owned legacy tools layout.'
}
$runId = $Matches.run
if (-not (Test-Path -LiteralPath $toolchainFullPath -PathType Leaf) -or (Get-FileSha256 -Path $toolchainFullPath) -cne $ToolchainSha256) {
    throw 'Legacy archive fixture toolchain path or SHA-256 differs from its CLI binding.'
}

$configPath = Join-Path $root 'config/standard-v1.json'
$config = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json -Depth 30 -ErrorAction Stop
$authority = $config.authority
$expectedCommit = '8aabd22694a05771f98639f6d726cc9a620eb94b'
$expectedArchiveSha256 = 'd92df1a8f0aa342970dc9c66a77b6211955b4708de12119cb7f9a360fd265311'
$expectedRepository = 'https://github.com/SyuanTsai/SyuanTsai-AI-Instructions.git'
if ([string]$authority.repository -cne $expectedRepository -or [string]$authority.commit -cne $expectedCommit -or
    [string]$authority.archiveUrl -cne "https://codeload.github.com/SyuanTsai/SyuanTsai-AI-Instructions/zip/$expectedCommit" -or
    [string]$authority.archiveSha256 -cne $expectedArchiveSha256 -or $authority.files -isnot [array] -or @($authority.files).Count -ne 26) {
    throw 'Legacy archive fixture requires the exact active 8a repository, commit, archive digest and 26-file closure.'
}

$entries = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::Ordinal)
foreach ($entry in @($authority.files)) {
    $relative = [string]$entry.path
    $segments = $relative.Split('/')
    if ([string]::IsNullOrWhiteSpace($relative) -or $relative.Contains('\') -or [IO.Path]::IsPathRooted($relative) -or
        $segments -contains '' -or $segments -contains '.' -or $segments -contains '..' -or
        [string]$entry.sha256 -cnotmatch '^[0-9a-f]{64}$' -or -not $entries.TryAdd($relative, $entry)) {
        throw 'Legacy archive fixture authority config has an unsafe, malformed or duplicate file record.'
    }
}

$toolchain = Get-Content -LiteralPath $toolchainFullPath -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json -Depth 30 -ErrorAction Stop
$expectedToolchainFields = @(
    'centralRunnerPath', 'centralRunnerSha256', 'upstreamAdapterValidatorPath', 'upstreamAdapterValidatorSha256',
    'upstreamPolicyPath', 'upstreamPolicySha256', 'skillValidatorPath', 'skillValidatorSha256',
    'skillToolsNodePath', 'skillToolsNodeSha256', 'skillToolsEntryPointPath', 'skillToolsEntryPointSha256',
    'skillSpectorPath', 'skillSpectorSha256', 'pesterModulePath', 'pesterModuleSha256', 'pesterVersion'
)
$actualToolchainFields = @($toolchain.PSObject.Properties | ForEach-Object { [string]$_.Name })
if ($actualToolchainFields.Count -ne $expectedToolchainFields.Count -or
    @($expectedToolchainFields | Where-Object { $actualToolchainFields -cnotcontains $_ }).Count -gt 0 -or
    @($actualToolchainFields | Where-Object { $expectedToolchainFields -cnotcontains $_ }).Count -gt 0) {
    throw 'Legacy archive fixture toolchain does not have the exact trusted receipt identity fields.'
}

$authorityContainer = [IO.Path]::GetFullPath((Join-Path $toolsRoot 'authority'))
$authorityRoot = [IO.Path]::GetFullPath((Split-Path -Parent (Split-Path -Parent ([string]$toolchain.centralRunnerPath))))
if (-not [IO.Path]::GetFullPath((Split-Path -Parent $authorityRoot)).Equals($authorityContainer, $pathComparison) -or
    -not [IO.Path]::GetFullPath([string]$toolchain.centralRunnerPath).Equals([IO.Path]::GetFullPath((Join-Path $authorityRoot 'scripts/Invoke-StandardValidation.ps1')), $pathComparison)) {
    throw 'Legacy archive fixture central runner does not resolve beneath the exact run-owned authority archive extraction.'
}
Assert-NoReparseAncestors -Path $authorityRoot
if (Test-Path -LiteralPath (Join-Path $authorityRoot '.git')) { throw 'Legacy archive fixture must be verified as an extracted archive without Git metadata.' }

$authorityNodes = @(Get-ChildItem -LiteralPath $authorityRoot -Force -Recurse -ErrorAction Stop)
foreach ($node in $authorityNodes) {
    if ($node.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Legacy archive authority contains a reparse entry: $($node.FullName)" }
    if ([string]$node.Name -ceq '.git') { throw 'Legacy archive fixture must be verified as an extracted archive without Git metadata.' }
}
$authorityFileInventory = @($authorityNodes | Where-Object { -not $_.PSIsContainer } | ForEach-Object {
    [IO.Path]::GetRelativePath($authorityRoot, $_.FullName).Replace([IO.Path]::DirectorySeparatorChar, '/').Replace([IO.Path]::AltDirectorySeparatorChar, '/')
} | Sort-Object -CaseSensitive)
foreach ($relative in $entries.Keys) {
    if ($authorityFileInventory -cnotcontains $relative) { throw "Legacy archive fixture omits an approved authority file: $relative" }
}
foreach ($relative in $entries.Keys) {
    $path = [IO.Path]::GetFullPath((Join-Path $authorityRoot ($relative -replace '/', [IO.Path]::DirectorySeparatorChar)))
    $prefix = $authorityRoot.TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
    if (-not $path.StartsWith($prefix, $pathComparison) -or -not (Test-Path -LiteralPath $path -PathType Leaf) -or
        (Get-FileSha256 -Path $path) -cne [string]$entries[$relative].sha256) {
        throw "Legacy archive fixture raw authority SHA-256 differs from the approved 8a pin: $relative"
    }
}

$authorityToolBindings = @(
    [pscustomobject]@{ path = [string]$toolchain.centralRunnerPath; sha = [string]$toolchain.centralRunnerSha256; relative = 'scripts/Invoke-StandardValidation.ps1' },
    [pscustomobject]@{ path = [string]$toolchain.upstreamAdapterValidatorPath; sha = [string]$toolchain.upstreamAdapterValidatorSha256; relative = 'scripts/Validate-UpstreamAdapter.ps1' },
    [pscustomobject]@{ path = [string]$toolchain.upstreamPolicyPath; sha = [string]$toolchain.upstreamPolicySha256; relative = 'docs/standards/upstream-adapter.json' }
)
foreach ($binding in $authorityToolBindings) {
    $expectedPath = [IO.Path]::GetFullPath((Join-Path $authorityRoot ([string]$binding.relative -replace '/', [IO.Path]::DirectorySeparatorChar)))
    if (-not [IO.Path]::GetFullPath([string]$binding.path).Equals($expectedPath, $pathComparison) -or
        [string]$binding.sha -cne [string]$entries[[string]$binding.relative].sha256 -or
        (Get-FileSha256 -Path $expectedPath) -cne [string]$binding.sha) {
        throw "Legacy archive fixture toolchain authority binding is not the exact approved file: $($binding.relative)"
    }
}
foreach ($binding in @(
    [pscustomobject]@{ path = [string]$toolchain.skillValidatorPath; sha = [string]$toolchain.skillValidatorSha256; confined = $true },
    [pscustomobject]@{ path = [string]$toolchain.skillToolsNodePath; sha = [string]$toolchain.skillToolsNodeSha256; confined = $false },
    [pscustomobject]@{ path = [string]$toolchain.skillToolsEntryPointPath; sha = [string]$toolchain.skillToolsEntryPointSha256; confined = $true },
    [pscustomobject]@{ path = [string]$toolchain.skillSpectorPath; sha = [string]$toolchain.skillSpectorSha256; confined = $true },
    [pscustomobject]@{ path = [string]$toolchain.pesterModulePath; sha = [string]$toolchain.pesterModuleSha256; confined = $true }
)) {
    $bindingPath = [IO.Path]::GetFullPath([string]$binding.path)
    $externalRootParent = [IO.Path]::GetFullPath((Split-Path -Parent $toolsRoot))
    $bindingRoot = [IO.Path]::GetFullPath((Join-Path $externalRootParent "skcv1-resolved-tools-$runId"))
    $bindingPrefix = $bindingRoot.TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
    if ([string]$binding.sha -cnotmatch '^[0-9a-f]{64}$' -or -not (Test-Path -LiteralPath $bindingPath -PathType Leaf) -or
        ($binding.confined -and -not $bindingPath.StartsWith($bindingPrefix, $pathComparison)) -or
        ((Get-Item -LiteralPath $bindingPath -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or
        (Get-FileSha256 -Path ([string]$binding.path)) -cne [string]$binding.sha) {
        throw 'Legacy archive fixture toolchain contains a missing or changed resolver-receipt file.'
    }
}
if ([string]$toolchain.pesterVersion -cne '6.2.0') { throw 'Legacy archive fixture toolchain Pester version differs from the pinned test runtime.' }

[ordered]@{
    schemaVersion = 1
    fixtureMode = 'verified-driver-archive'
    runId = $runId
    toolchainPath = $toolchainFullPath
    toolchainSha256 = $ToolchainSha256
    authorityRoot = $authorityRoot
    authorityRevision = $expectedCommit
    authorityFileCount = $entries.Count
    authorityExtraFileCount = $authorityFileInventory.Count - $entries.Count
} | ConvertTo-Json -Depth 10 -Compress
