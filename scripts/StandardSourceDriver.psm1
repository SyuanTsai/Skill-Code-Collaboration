# SPDX-FileCopyrightText: 2026 SyuanTsai
# SPDX-License-Identifier: Apache-2.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:PreparedSourceAuthorityCommit = 'ff85d5f80fe795b96354e753074b5ce59ad04ecd'
$script:PreparedSourceAuthorityArchiveSha256 = '3dc38613f2e2316ad8fcc79d4bf48d0b03fd8398f8dacc72d156abcbce95ea9d'
$script:SourceAuthorityRepository = 'https://github.com/SyuanTsai/SyuanTsai-AI-Instructions.git'
$script:PreparedSourceAuthorityFiles = [ordered]@{
    'docs/standards/README.md' = '43c1526ac55302f62b706688905be160d9805cc3a6a800189d689e66fa727b71'
    'docs/standards/managed-skill-lifecycle.md' = '70950cf8bdd02819efae6f6e06ac5be1da3e70f809c23e3c6f8d3b217797416c'
    'docs/standards/schemas/managed-skill-lifecycle-v1.schema.json' = '9a7f4c02588d2b88194e953a41766a72a9426fa89d4c3781c5750dcc22d35863'
    'docs/standards/schemas/openai-agent-metadata.schema.json' = '23c1aaee28a54fea1946a61d6122a2097906ffa5bdd66c8014fc6b1625c9062a'
    'docs/standards/schemas/source-inventory-v2.schema.json' = '084550944b4141ab5535f58fb6e99730a5c34b56103f6b59fd5a352679caa98e'
    'docs/standards/schemas/validation-security-gate-v1.schema.json' = 'ac58302e0e350c1ab4ba4dad8a33cd3abce12d592537fbdb23dfb1936d064e91'
    'docs/standards/skill-repository-review-matrix.md' = '299925aabe3cab360827baad9bdeb1f0f56fc320dad967e49fe0b6bf9cdf8f8a'
    'docs/standards/skill-repository-standard.md' = '86a24a75eaf96f9eaa02307937a46d1b2ce788cf63b4657c60bec9815b2ca4b3'
    'docs/standards/upstream-interoperability.md' = '4329e8586e88713027bcd95c7537331e050a89b004f2361223efdc01bf44370e'
    'docs/standards/validation-security-gate.json' = '657122dde340f1f7f4442780cc27ffcb00b60c0d2afdcea22d63fbf7dbfdca7d'
    'docs/standards/validation-toolchain.json' = '1dddbf4c5736e22e56f6ecb298542f41d39e116ab00ca24ad18beb7a3eab40ed'
    'scripts/Invoke-StandardAuthorityGate.ps1' = '8e00ee1e48ef8359ab7be3539f8f7585ccde18b41e26d810843715ebc3656a4c'
    'scripts/Resolve-PythonWheelClosure.py' = 'f9fcd99c408849f98564fbc4c30f3d7e6ad8148b60cb4d8f58fc29b040c4519c'
    'scripts/Resolve-StandardValidationTool.ps1' = '71e6d5b191b74202e96f34a856d3317efb18662e17c8368d112d89b7d6795b15'
    'docs/standards/schemas/standard-validation-adapter-v1.schema.json' = '11aa88fc25716d748bd4f514f1a44f02390ad1745dd5a5c5beee07f642fd5639'
    'docs/standards/schemas/standard-validation-evidence-v1.schema.json' = '8ed4a9d7158273d7a1e9d898acf07f57e9170822cb7cbb70f1e2eec7195867ee'
    'docs/standards/standard-validation-contract-v1.json' = '707edf8945ad9a7097df1dfb22a8f05ce47d0e0a66e2e44381036d630e854da0'
    'docs/standards/pr12-source-merge-adoption.json' = '4c5262f2a11d228195230c15fa4faaf9614af6b59f110e5d9c08f242ce809175'
    'docs/standards/trust-anchors/human-approval-public-key.xml' = '1e46153b72d02f3ce2fb26becd449df4f1590d8e5cb441b1954006a5602bbd9b'
    'docs/standards/trust-anchors/trusted-supervisor-public-key.xml' = '4d550851f43405920156f40c9fc648d99a69dd73efc200f6968d8a837e7fbf27'
    'scripts/Invoke-StandardValidation.ps1' = 'a4ee880810171428a6abd2e8fd5db2da1eaeda4abc0fc6c72dc259b4a709174b'
    'docs/standards/schemas/standard-semantic-consent-evidence-v2.schema.json' = '109091979d0a47e2035d3d8b20963fcdb85680e5da737bf1f27121608115d430'
    'scripts/StandardSemanticBridge.psm1' = 'daf90f703898cc56fc3310e1eec462bafa6552edcac0de4f08a3cd4b9f63a429'
    'docs/standards/schemas/upstream-adapter-v1.schema.json' = '3cff6246463188a91cc54c6a46315a949314767a759c6214e5b28e4db95ac8d7'
    'docs/standards/upstream-adapter.json' = 'c4f5133b24841bb9c66182dc3d5a027596f864ec28e410d47249a67b3b97ad31'
    'scripts/Validate-UpstreamAdapter.ps1' = '3b6e6474690b1ae9f9486544b68f50ca29b96f5dbe6aa8d6c6cd8570afad500b'
    'docs/standards/standard-core-validation-v2.json' = '2ba91aec827a642517fd90d294524e0dfc3fed9ae19c27d867d442d73b4915d6'
    'docs/standards/schemas/standard-core-adapter-v2.schema.json' = '7399980e8765528b759a3734a133447eb9581ac24a9c4780dc8faadd6af0c1c5'
    'docs/standards/schemas/standard-core-evidence-v2.schema.json' = '4a8c61f32484bfe928e4f15f6422de7dc7b63d9d1fc95bca4f8f5c4c37334d24'
    'docs/standards/third-party-raw-skill-sources.md' = '18649fd56eada4a94a5d47de778669b0ebcecfb85b84f5c581d283b21979f7ac'
    'docs/standards/schemas/third-party-raw-skill-source-v1.schema.json' = '9d8585d95c606486f947a3f89e39341af840335376e86910eb7f4ed25bdc16ed'
    'docs/standards/examples/third-party-raw-skill-source-v1.json' = 'decbf276cbeea33c60d8b36b7b16838babe951cd84d13ae4a8a7a8261dc6d9c8'
}

function Get-PreparedSourceAuthorityPin {
    return [pscustomobject]@{
        repository = $script:SourceAuthorityRepository
        commit = $script:PreparedSourceAuthorityCommit
        archiveUrl = "https://codeload.github.com/SyuanTsai/SyuanTsai-AI-Instructions/zip/$($script:PreparedSourceAuthorityCommit)"
        archiveSha256 = $script:PreparedSourceAuthorityArchiveSha256
        files = $script:PreparedSourceAuthorityFiles
    }
}

function Assert-CodeSourceAuthorityConfig {
    param([Parameter(Mandatory = $true)] $Config)

    $expectedProperties = @('schemaVersion', 'standardVersion', 'authority')
    $actualProperties = @($Config.PSObject.Properties | ForEach-Object { [string]$_.Name })
    if ($actualProperties.Count -ne $expectedProperties.Count -or
        @($expectedProperties | Where-Object { $actualProperties -cnotcontains $_ }).Count -gt 0 -or
        @($actualProperties | Where-Object { $expectedProperties -cnotcontains $_ }).Count -gt 0) {
        throw 'config/standard-v1.json has an invalid property set.'
    }
    if ($null -eq $Config.schemaVersion -or $Config.schemaVersion.GetType().Name -notin @('Byte', 'Int16', 'Int32', 'Int64', 'UInt16', 'UInt32', 'UInt64') -or
        $Config.schemaVersion -ne 1 -or $Config.standardVersion -isnot [string] -or $Config.standardVersion -cne 'v1') {
        throw 'config/standard-v1.json has an unsupported schema or Standard version.'
    }

    $authority = $Config.authority
    $expectedAuthorityProperties = @('repository', 'commit', 'archiveUrl', 'archiveSha256', 'files')
    $actualAuthorityProperties = @($authority.PSObject.Properties | ForEach-Object { [string]$_.Name })
    if ($actualAuthorityProperties.Count -ne $expectedAuthorityProperties.Count -or
        @($expectedAuthorityProperties | Where-Object { $actualAuthorityProperties -cnotcontains $_ }).Count -gt 0 -or
        @($actualAuthorityProperties | Where-Object { $expectedAuthorityProperties -cnotcontains $_ }).Count -gt 0) {
        throw 'config/standard-v1.json authority has an invalid property set.'
    }

    $pin = Get-PreparedSourceAuthorityPin
    foreach ($field in @('repository', 'commit', 'archiveUrl', 'archiveSha256')) {
        if ($authority.PSObject.Properties[$field].Value -isnot [string] -or [string]$authority.$field -cne [string]$pin.$field) {
            throw "config/standard-v1.json authority '$field' does not match the exact prepared source tuple."
        }
    }
    if ($authority.files -isnot [array] -or @($authority.files).Count -ne $script:PreparedSourceAuthorityFiles.Count) {
        throw 'config/standard-v1.json authority file closure must contain the exact 32 approved records.'
    }

    $expectedPaths = @($script:PreparedSourceAuthorityFiles.Keys)
    for ($index = 0; $index -lt $expectedPaths.Count; $index++) {
        $file = @($authority.files)[$index]
        $fileProperties = @($file.PSObject.Properties | ForEach-Object { [string]$_.Name })
        if ($fileProperties.Count -ne 2 -or $fileProperties -cnotcontains 'path' -or $fileProperties -cnotcontains 'sha256' -or
            $file.path -isnot [string] -or $file.sha256 -isnot [string] -or
            [string]$file.path -cne [string]$expectedPaths[$index] -or
            [string]$file.sha256 -cne [string]$script:PreparedSourceAuthorityFiles[$expectedPaths[$index]]) {
            throw "config/standard-v1.json authority file identity mismatch at index $index."
        }
    }
    return $pin
}

function Assert-CodeSourceRunRequest {
    [CmdletBinding()]
    param(
        [string] $ExecutionMode = 'Run',
        [switch] $PrepareSourceTools,
        [switch] $SourceValidation,
        [string] $SourceToolsPath,
        [int] $AdapterVersion = 1,
        [string] $AuthorityCommit,
        [string] $RunId,
        [switch] $CompleteLifecycle,
        [switch] $DevelopmentHarness
    )

    $setup = [bool]$PrepareSourceTools
    $source = [bool]$SourceValidation
    $hasPath = $PSBoundParameters.ContainsKey('SourceToolsPath')
    if ($setup -and $source) { throw 'PrepareSourceTools and SourceValidation are separate setup and execution requests.' }
    if (($setup -or $source) -and ($ExecutionMode -cne 'Run' -or [string]::IsNullOrWhiteSpace($SourceToolsPath))) {
        throw 'Explicit source setup or validation requires Run and SourceToolsPath.'
    }
    if (-not ($setup -or $source) -and $hasPath) { throw 'Ordinary Core does not accept SourceToolsPath.' }
    if (-not ($setup -or $source)) { return 'Core' }
    if ($AdapterVersion -ne 2 -or $CompleteLifecycle -or $DevelopmentHarness) {
        throw 'SourceValidation requires Core adapter v2 and cannot be combined with a legacy lifecycle or development harness.'
    }
    if ($AuthorityCommit -cne $script:PreparedSourceAuthorityCommit) {
        throw 'Source setup and validation require the exact approved ff85 authority tuple.'
    }
    if ($source -and $RunId -cnotmatch '^[0-9a-f]{32}$') {
        throw 'SourceValidation requires the fresh setup RunId as exactly 32 lowercase hexadecimal characters.'
    }
    if ($setup -and -not [string]::IsNullOrWhiteSpace($RunId)) {
        throw 'PrepareSourceTools creates the fresh setup RunId and does not accept a caller-provided identity.'
    }
    if ($setup) { return 'PrepareSourceTools' }
    return 'SourceValidation'
}

function New-CodeSourcePesterSetupEnvironment {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string] $OwnedRoot)

    if ([string]::IsNullOrWhiteSpace($OwnedRoot) -or -not [IO.Path]::IsPathFullyQualified($OwnedRoot)) {
        throw 'Pester setup root must be a non-empty fully qualified path.'
    }
    try {
        $fullOwnedRoot = [IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath($OwnedRoot))
    }
    catch {
        throw 'Pester setup root must be a resolvable fully qualified path.'
    }
    if ([string]::IsNullOrWhiteSpace($fullOwnedRoot)) {
        throw 'Pester setup root must be a non-empty fully qualified path.'
    }
    return @{
        STANDARD_VALIDATION_RUN_OWNED_ROOT = $fullOwnedRoot
    }
}

function New-CodeSourceFrozenFileInventory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][AllowNull()][object] $RuntimeFiles,
        [Parameter(Mandatory = $true)][AllowNull()][object] $SourceFiles,
        [Parameter(Mandatory = $true)][AllowNull()][object] $PesterFiles,
        [Parameter(Mandatory = $true)][AllowNull()][object] $ReceiptFiles
    )

    $comparison = if ($IsWindows) { [StringComparer]::OrdinalIgnoreCase } else { [StringComparer]::Ordinal }
    $byPath = [Collections.Generic.Dictionary[string, string]]::new($comparison)
    foreach ($group in @($RuntimeFiles, $SourceFiles, $PesterFiles, $ReceiptFiles)) {
        if ($null -eq $group) { continue }
        if ($group -is [string]) { $groupItems = @($group) }
        elseif ($group -is [Collections.IEnumerable]) { $groupItems = @($group) }
        else { throw 'Frozen source file groups must contain string paths or string arrays.' }
        foreach ($pathValue in $groupItems) {
            if ($pathValue -isnot [string] -or [string]::IsNullOrWhiteSpace([string]$pathValue)) {
                throw 'Frozen source file inventory contains a non-string or empty path.'
            }
            $fullPath = [IO.Path]::GetFullPath([string]$pathValue)
            $item = Get-Item -LiteralPath $fullPath -Force -ErrorAction Stop
            if ($item.PSIsContainer -or $item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
                throw "Frozen source input must be a regular file: $fullPath"
            }
            $sha256 = (Get-FileHash -LiteralPath $fullPath -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
            if (-not $byPath.TryAdd($fullPath, $sha256) -and $byPath[$fullPath] -cne $sha256) {
                throw "Frozen source file changed while its input groups were composed: $fullPath"
            }
        }
    }
    if ($byPath.Count -eq 0) { throw 'Frozen source file inventory must not be empty.' }
    $sortedPaths = [string[]]@($byPath.Keys)
    [Array]::Sort($sortedPaths, [StringComparer]::Ordinal)
    $records = @($sortedPaths | ForEach-Object { [pscustomobject][ordered]@{ path = $_; sha256 = $byPath[$_] } })
    return [pscustomobject]@{ files = [object[]]$records; count = $records.Count }
}

function Assert-CodeSourceProtectedDispatchFiles {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string] $ProtectedBaseRoot,
        [Parameter(Mandatory = $true)][string] $CandidateRoot,
        [Parameter(Mandatory = $true)][object[]] $ManifestEntries
    )

    $protectedRoot = [IO.Path]::GetFullPath($ProtectedBaseRoot)
    $candidateRootFull = [IO.Path]::GetFullPath($CandidateRoot)
    $comparison = if ($IsWindows) { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal }
    $protectedPaths = @(
        'scripts/Invoke-RepositoryCheck.ps1',
        'scripts/Invoke-CorePester.ps1',
        'scripts/CorePesterIntegrity.psm1',
        'scripts/Test-Repository.ps1',
        'tests/validate-catalog.ps1'
    )
    $entries = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::Ordinal)
    foreach ($entry in $ManifestEntries) {
        $relative = [string]$entry.path
        $segments = $relative.Split('/')
        if ([string]::IsNullOrWhiteSpace($relative) -or $relative.Contains('\') -or [IO.Path]::IsPathRooted($relative) -or
            $segments -contains '' -or $segments -contains '.' -or $segments -contains '..' -or
            [string]$entry.sha256 -cnotmatch '^[0-9a-f]{64}$' -or
            [string]$entry.mode -cnotin @('100644', '100755') -or $entries.ContainsKey($relative)) {
            throw 'Candidate Git entry mode manifest contains an invalid or duplicate protected dispatch entry.'
        }
        $entries.Add($relative, $entry)
    }

    $result = [Collections.Generic.List[object]]::new()
    foreach ($relative in $protectedPaths) {
        if (-not $entries.ContainsKey($relative)) { throw "Candidate revision is missing the protected dispatch file: $relative" }
        $basePath = Join-Path $protectedRoot ($relative.Replace('/', [IO.Path]::DirectorySeparatorChar))
        $candidatePath = Join-Path $candidateRootFull ($relative.Replace('/', [IO.Path]::DirectorySeparatorChar))
        foreach ($path in @($basePath, $candidatePath)) {
            if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Protected dispatch file is missing: $path" }
            $item = Get-Item -LiteralPath $path -Force -ErrorAction Stop
            if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Protected dispatch file is a reparse point: $path" }
        }
        $baseHash = (Get-FileHash -LiteralPath $basePath -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
        $candidateHash = (Get-FileHash -LiteralPath $candidatePath -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
        if ($baseHash -cne $candidateHash -or [string]$entries[$relative].sha256 -cne $baseHash -or [string]$entries[$relative].mode -cne '100644') {
            throw "Candidate protected dispatch file differs from the trusted driver bytes: $relative"
        }
        $result.Add([pscustomobject]@{ path = $relative; sha256 = $baseHash; protectedPath = [IO.Path]::GetFullPath($basePath) })
    }
    return $result.ToArray()
}

function Assert-CodeSourceProtectedRuntimeCopies {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string] $ProtectedBaseRoot,
        [Parameter(Mandatory = $true)][string] $CandidateRoot,
        [Parameter(Mandatory = $true)][string] $OwnedRoot,
        [Parameter(Mandatory = $true)][object[]] $ManifestEntries,
        [Parameter(Mandatory = $true)][object[]] $FrozenFiles
    )

    $dispatchFiles = @(Assert-CodeSourceProtectedDispatchFiles -ProtectedBaseRoot $ProtectedBaseRoot `
        -CandidateRoot $CandidateRoot -ManifestEntries $ManifestEntries)
    $runtimeRoot = [IO.Path]::GetFullPath((Join-Path $OwnedRoot 'runtime/ProtectedSourceChecks'))
    $comparison = if ($IsWindows) { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal }
    $frozen = [Collections.Generic.Dictionary[string, string]]::new($(if ($IsWindows) { [StringComparer]::OrdinalIgnoreCase } else { [StringComparer]::Ordinal }))
    foreach ($record in $FrozenFiles) {
        $path = [IO.Path]::GetFullPath([string]$record.path)
        if ([string]$record.sha256 -cnotmatch '^[0-9a-f]{64}$' -or -not $frozen.TryAdd($path, [string]$record.sha256)) {
            throw 'Prepared frozen file inventory contains an invalid or duplicate protected-copy record.'
        }
    }
    foreach ($binding in $dispatchFiles) {
        $relative = ([string]$binding.path).Replace('/', [IO.Path]::DirectorySeparatorChar)
        $copyPath = [IO.Path]::GetFullPath((Join-Path $runtimeRoot $relative))
        if (-not $copyPath.StartsWith($runtimeRoot.TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar, $comparison) -or
            -not $frozen.ContainsKey($copyPath)) {
            throw "Run-owned protected dispatch copy is missing from the frozen closure: $($binding.path)"
        }
        foreach ($path in @([string]$binding.protectedPath, $copyPath)) {
            $item = Get-Item -LiteralPath $path -Force -ErrorAction Stop
            if ($item.PSIsContainer -or $item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Run-owned protected dispatch copy is not a regular file: $path" }
            if ((Get-FileHash -LiteralPath $path -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant() -cne [string]$binding.sha256) {
                throw "Run-owned protected dispatch copy differs from the trusted protected-base bytes: $($binding.path)"
            }
        }
        if ($frozen[$copyPath] -cne [string]$binding.sha256) { throw "Run-owned protected dispatch copy has a self-consistent but untrusted frozen hash: $($binding.path)" }
    }
    return $dispatchFiles
}

function Assert-CodeSourceSha256 {
    param([Parameter(Mandatory = $true)][string] $Value, [Parameter(Mandatory = $true)][string] $Context)
    if ($Value -cnotmatch '^[0-9a-f]{64}$') { throw "$Context must be a lowercase SHA-256 value." }
}

function Assert-CodeSourceNoDuplicateJsonProperties {
    param([Parameter(Mandatory = $true)][System.Text.Json.JsonElement] $Element, [Parameter(Mandatory = $true)][string] $Context)
    if ($Element.ValueKind -eq [System.Text.Json.JsonValueKind]::Object) {
        $names = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        foreach ($property in $Element.EnumerateObject()) {
            if (-not $names.Add($property.Name)) { throw "$Context contains duplicate JSON property '$($property.Name)'." }
            Assert-CodeSourceNoDuplicateJsonProperties -Element $property.Value -Context "$Context.$($property.Name)"
        }
    }
    elseif ($Element.ValueKind -eq [System.Text.Json.JsonValueKind]::Array) {
        foreach ($item in $Element.EnumerateArray()) { Assert-CodeSourceNoDuplicateJsonProperties -Element $item -Context $Context }
    }
}

function Assert-CodeSourceRuntimeInventory {
    param(
        [Parameter(Mandatory = $true)] $PesterRuntime,
        [Parameter(Mandatory = $true)][string] $OwnedRoot,
        [Parameter(Mandatory = $true)] $FrozenFiles
    )

    $runtimeRoot = [IO.Path]::GetFullPath([string]$PesterRuntime.runtimeRoot)
    $expectedRoot = [IO.Path]::GetFullPath((Join-Path $OwnedRoot 'runtime'))
    $comparison = if ($IsWindows) { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal }
    if (-not $runtimeRoot.Equals($expectedRoot, $comparison) -or -not (Test-Path -LiteralPath $runtimeRoot -PathType Container)) {
        throw 'Prepared PowerShell runtime root does not match the exact run-owned copy.'
    }
    $runtimeExecutable = [IO.Path]::GetFullPath([string]$PesterRuntime.runtimeExecutablePath)
    $runtimeExecutableName = if ($IsWindows) { 'pwsh.exe' } else { 'pwsh' }
    $expectedExecutable = [IO.Path]::GetFullPath((Join-Path $runtimeRoot $runtimeExecutableName))
    if (-not $runtimeExecutable.Equals($expectedExecutable, $comparison) -or
        -not (Test-Path -LiteralPath $runtimeExecutable -PathType Leaf) -or
        [string]$PesterRuntime.runtimeExecutableSha256 -cnotmatch '^[0-9a-f]{64}$' -or
        (Get-FileHash -LiteralPath $runtimeExecutable -Algorithm SHA256).Hash.ToLowerInvariant() -cne [string]$PesterRuntime.runtimeExecutableSha256) {
        throw 'Prepared PowerShell executable path or hash differs from the run-owned runtime.'
    }

    $inventoryPath = [IO.Path]::GetFullPath([string]$PesterRuntime.runtimeInventoryPath)
    $expectedInventoryPath = [IO.Path]::GetFullPath((Join-Path $OwnedRoot 'powershell-runtime-inventory.json'))
    if (-not $inventoryPath.Equals($expectedInventoryPath, $comparison) -or
        [string]$PesterRuntime.runtimeInventorySha256 -cnotmatch '^[0-9a-f]{64}$' -or
        -not (Test-Path -LiteralPath $inventoryPath -PathType Leaf) -or
        (Get-FileHash -LiteralPath $inventoryPath -Algorithm SHA256).Hash.ToLowerInvariant() -cne [string]$PesterRuntime.runtimeInventorySha256 -or
        -not $FrozenFiles.ContainsKey($inventoryPath) -or $FrozenFiles[$inventoryPath] -cne [string]$PesterRuntime.runtimeInventorySha256) {
        throw 'Prepared PowerShell runtime inventory is missing, changed or not frozen.'
    }
    $runtimeFields = @('schemaVersion', 'root', 'executablePath', 'executableSha256', 'files')
    $document = $null
    try {
        $runtimeJson = [IO.File]::ReadAllText($inventoryPath, [Text.UTF8Encoding]::new($false, $true))
        $document = [System.Text.Json.JsonDocument]::Parse($runtimeJson)
        $propertyNames = @($document.RootElement.EnumerateObject() | ForEach-Object { [string]$_.Name })
        if ($document.RootElement.ValueKind -ne [System.Text.Json.JsonValueKind]::Object -or
            $propertyNames.Count -ne $runtimeFields.Count -or
            @($runtimeFields | Where-Object { $propertyNames -cnotcontains $_ }).Count -gt 0) {
            throw 'Prepared PowerShell runtime inventory has an invalid property set.'
        }
        Assert-CodeSourceNoDuplicateJsonProperties -Element $document.RootElement -Context 'Prepared PowerShell runtime inventory'
        $runtimeInventory = ConvertFrom-Json -InputObject $runtimeJson -Depth 20 -ErrorAction Stop
    }
    finally { if ($null -ne $document) { $document.Dispose() } }
    if ([int]$runtimeInventory.schemaVersion -ne 1 -or
        -not [IO.Path]::GetFullPath([string]$runtimeInventory.root).Equals($runtimeRoot, $comparison) -or
        -not [IO.Path]::GetFullPath([string]$runtimeInventory.executablePath).Equals($runtimeExecutable, $comparison) -or
        [string]$runtimeInventory.executableSha256 -cne [string]$PesterRuntime.runtimeExecutableSha256 -or
        $runtimeInventory.files -isnot [array] -or $runtimeInventory.files.Count -eq 0) {
        throw 'Prepared PowerShell runtime inventory does not bind the exact run-owned runtime.'
    }

    $expectedFiles = [Collections.Generic.Dictionary[string, string]]::new($(if ($IsWindows) { [StringComparer]::OrdinalIgnoreCase } else { [StringComparer]::Ordinal }))
    foreach ($file in @($runtimeInventory.files)) {
        $properties = @($file.PSObject.Properties | ForEach-Object { [string]$_.Name })
        if ($properties.Count -ne 2 -or $properties -cnotcontains 'path' -or $properties -cnotcontains 'sha256' -or
            [string]$file.path -cnotmatch '^(?:[A-Za-z]:\\|/)' -or [string]$file.sha256 -cnotmatch '^[0-9a-f]{64}$') {
            throw 'Prepared PowerShell runtime file inventory contains a malformed entry.'
        }
        $path = [IO.Path]::GetFullPath([string]$file.path)
        $prefix = $runtimeRoot.TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
        if (-not $path.StartsWith($prefix, $comparison) -or
            -not $expectedFiles.TryAdd($path, [string]$file.sha256)) {
            throw 'Prepared PowerShell runtime inventory contains an unsafe or duplicate path.'
        }
    }
    if (-not $expectedFiles.ContainsKey($runtimeExecutable) -or $expectedFiles[$runtimeExecutable] -cne [string]$PesterRuntime.runtimeExecutableSha256) {
        throw 'Prepared PowerShell runtime inventory does not include the exact child executable hash.'
    }
    foreach ($path in $expectedFiles.Keys) {
        $item = Get-Item -LiteralPath $path -Force -ErrorAction Stop
        if ($item.PSIsContainer -or $item.Attributes -band [IO.FileAttributes]::ReparsePoint -or
            (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -cne $expectedFiles[$path] -or
            -not $FrozenFiles.ContainsKey($path) -or $FrozenFiles[$path] -cne $expectedFiles[$path]) {
            throw "Prepared PowerShell runtime file is missing, changed, unsafe or not frozen: $path"
        }
    }
    $actualFiles = @()
    foreach ($item in @(Get-ChildItem -LiteralPath $runtimeRoot -Force -Recurse -ErrorAction Stop)) {
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Prepared PowerShell runtime contains a reparse point: $($item.FullName)" }
        if (-not $item.PSIsContainer) { $actualFiles += [IO.Path]::GetFullPath($item.FullName) }
    }
    if ($actualFiles.Count -ne $expectedFiles.Count -or
        @($actualFiles | Where-Object { -not $expectedFiles.ContainsKey($_) }).Count -gt 0) {
        throw 'Prepared PowerShell runtime has an incomplete or extra file outside its frozen inventory.'
    }
    return $runtimeInventory
}

function Assert-CodeSourcePreparedBindings {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)] $Prepared,
        [Parameter(Mandatory = $true)][string] $PreparedPath,
        [Parameter(Mandatory = $true)][ValidatePattern('^[0-9a-f]{40}$')][string] $CandidateRevision,
        [Parameter(Mandatory = $true)][string] $PowerShellPath,
        [Parameter(Mandatory = $true)][string] $SourceRepository
    )

    $topFields = @('schemaVersion', 'preparation', 'runId', 'sourceRevision', 'authorityRevision', 'ownedRoot', 'candidateArchivePath', 'candidateArchiveSha256', 'sourceValidation', 'pesterRuntime')
    $topProperties = @($Prepared.PSObject.Properties | ForEach-Object { [string]$_.Name })
    if ($topProperties.Count -ne $topFields.Count -or
        @($topFields | Where-Object { $topProperties -cnotcontains $_ }).Count -gt 0 -or
        @($topProperties | Where-Object { $topFields -cnotcontains $_ }).Count -gt 0 -or
        [int]$Prepared.schemaVersion -ne 1 -or $Prepared.preparation -cne 'code-collaboration-source-tools' -or
        [string]$Prepared.runId -cnotmatch '^[0-9a-f]{32}$' -or [string]$Prepared.sourceRevision -cne $CandidateRevision -or
        [string]$Prepared.authorityRevision -cne $script:PreparedSourceAuthorityCommit -or
        [string]$Prepared.candidateArchivePath -cnotmatch '^(?:[A-Za-z]:\\|/)' -or
        [string]$Prepared.candidateArchiveSha256 -cnotmatch '^[0-9a-f]{64}$') {
        throw 'Prepared source tools do not bind the exact source, authority and setup run.'
    }
    $preparedFullPath = [IO.Path]::GetFullPath($PreparedPath)
    $expectedOwnedRoot = [IO.Path]::GetFullPath((Join-Path (Split-Path -Parent $preparedFullPath) "source-tools-$($Prepared.runId)"))
    if (-not [IO.Path]::GetFullPath([string]$Prepared.ownedRoot).Equals($expectedOwnedRoot, $(if ($IsWindows) { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal }))) {
        throw 'Prepared source tools owned root differs from its exact run identity.'
    }
    $archivePath = [IO.Path]::GetFullPath([string]$Prepared.candidateArchivePath)
    if (-not $archivePath.StartsWith([IO.Path]::GetFullPath([string]$Prepared.ownedRoot).TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar,
            $(if ($IsWindows) { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal })) -or
        -not (Test-Path -LiteralPath $archivePath -PathType Leaf) -or
        (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash.ToLowerInvariant() -cne [string]$Prepared.candidateArchiveSha256) {
        throw 'Prepared candidate archive is missing, changed, or outside the exact source setup run.'
    }

    $sourceFields = @('packageAdapter', 'skillValidator', 'skillTools', 'staticAnalyzer', 'frozenFiles', 'toolReceipts')
    $sourceProperties = @($Prepared.sourceValidation.PSObject.Properties | ForEach-Object { [string]$_.Name })
    if ($sourceProperties.Count -ne $sourceFields.Count -or
        @($sourceFields | Where-Object { $sourceProperties -cnotcontains $_ }).Count -gt 0 -or
        @($sourceProperties | Where-Object { $sourceFields -cnotcontains $_ }).Count -gt 0 -or
        $Prepared.sourceValidation.toolReceipts -isnot [array] -or @($Prepared.sourceValidation.toolReceipts).Count -ne 3 -or
        $Prepared.sourceValidation.frozenFiles -isnot [array] -or @($Prepared.sourceValidation.frozenFiles).Count -eq 0) {
        throw 'Prepared source validation payload is partial or has an unexpected property set.'
    }
    $frozen = [Collections.Generic.Dictionary[string, string]]::new($(if ($IsWindows) { [StringComparer]::OrdinalIgnoreCase } else { [StringComparer]::Ordinal }))
    foreach ($file in @($Prepared.sourceValidation.frozenFiles)) {
        $properties = @($file.PSObject.Properties | ForEach-Object { [string]$_.Name })
        if ($properties.Count -ne 2 -or $properties -cnotcontains 'path' -or $properties -cnotcontains 'sha256' -or
            [string]$file.path -cnotmatch '^(?:[A-Za-z]:\\|/)' -or [string]$file.sha256 -cnotmatch '^[0-9a-f]{64}$') {
            throw 'Prepared source frozen file entry is malformed.'
        }
        $path = [IO.Path]::GetFullPath([string]$file.path)
        $item = Get-Item -LiteralPath $path -Force -ErrorAction Stop
        if ($item.PSIsContainer -or $item.Attributes -band [IO.FileAttributes]::ReparsePoint -or
            (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -cne [string]$file.sha256 -or
            -not $frozen.TryAdd($path, [string]$file.sha256)) {
            throw "Prepared source frozen file is missing, unsafe, changed or duplicated: $path"
        }
    }
    $manifestPath = [IO.Path]::GetFullPath((Join-Path ([string]$Prepared.ownedRoot) 'candidate-git-entry-modes.json'))
    $identityPath = [IO.Path]::GetFullPath((Join-Path ([string]$Prepared.ownedRoot) 'source-run-identity.json'))
    $manifestHash = if ($frozen.ContainsKey($manifestPath)) { [string]$frozen[$manifestPath] } else { '' }
    if (-not $frozen.ContainsKey($identityPath) -or [string]::IsNullOrWhiteSpace($manifestHash)) {
        throw 'Prepared source run identity or candidate manifest is missing from the frozen closure.'
    }
    $identity = Get-Content -LiteralPath $identityPath -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json -Depth 30 -ErrorAction Stop
    if ([int]$identity.schemaVersion -ne 1 -or [string]$identity.runId -cne [string]$Prepared.runId -or
        [string]$identity.sourceRevision -cne [string]$Prepared.sourceRevision -or [string]$identity.authorityRevision -cne [string]$Prepared.authorityRevision -or
        -not [IO.Path]::GetFullPath([string]$identity.candidateManifestPath).Equals($manifestPath, $(if ($IsWindows) { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal })) -or
        [string]$identity.candidateManifestSha256 -cne $manifestHash -or
        -not [IO.Path]::GetFullPath([string]$identity.candidateArchivePath).Equals($archivePath, $(if ($IsWindows) { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal })) -or
        [string]$identity.candidateArchiveSha256 -cne [string]$Prepared.candidateArchiveSha256) {
        throw 'Prepared source identity receipt does not bind the exact source revision, authority, archive, manifest and RunId.'
    }
    $receiptNames = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($receiptBinding in @($Prepared.sourceValidation.toolReceipts)) {
        $properties = @($receiptBinding.PSObject.Properties | ForEach-Object { [string]$_.Name })
        if ($properties.Count -ne 2 -or $properties -cnotcontains 'path' -or $properties -cnotcontains 'sha256' -or
            -not $frozen.ContainsKey([IO.Path]::GetFullPath([string]$receiptBinding.path)) -or
            $frozen[[IO.Path]::GetFullPath([string]$receiptBinding.path)] -cne [string]$receiptBinding.sha256) {
            throw 'Prepared source tool receipt is not an exact frozen file.'
        }
        $receipt = Get-Content -LiteralPath ([string]$receiptBinding.path) -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json -Depth 50 -ErrorAction Stop
        $name = [string]$receipt.toolName
        if ($name -cnotin @('skill-validator', 'skill-tools', 'skillspector') -or -not $receiptNames.Add($name) -or
            [string]$receipt.resolutionRunId -cne [string]$Prepared.runId -or $receipt.frozenForRun -isnot [bool] -or -not $receipt.frozenForRun) {
            throw 'Prepared source tool receipt belongs to another run or tool.'
        }
        foreach ($pair in @(@('executablePath', 'executableSha256'), @('entryPointPath', 'entryPointSha256'), @('nodePath', 'nodeSha256'), @('goRuntimePath', 'goRuntimeSha256'), @('resolverHelperPath', 'resolverHelperSha256'))) {
            $pathProperty = $receipt.PSObject.Properties[[string]$pair[0]]
            if ($null -eq $pathProperty -or [string]::IsNullOrWhiteSpace([string]$pathProperty.Value)) { continue }
            $hashProperty = $receipt.PSObject.Properties[[string]$pair[1]]
            $path = [IO.Path]::GetFullPath([string]$pathProperty.Value)
            if ($null -eq $hashProperty -or [string]$hashProperty.Value -cnotmatch '^[0-9a-f]{64}$' -or
                -not $frozen.ContainsKey($path) -or $frozen[$path] -cne [string]$hashProperty.Value) {
                throw "Prepared source receipt path/hash pair is missing from the frozen closure: $($pair[0])"
            }
        }
        foreach ($pair in @(@('shimPath', 'shimSha256'), @('payloadPath', 'payloadSha256'), @('runtimePath', 'runtimeSha256'))) {
            $pathProperty = $receipt.launcher.PSObject.Properties[[string]$pair[0]]
            if ($null -eq $pathProperty -or [string]::IsNullOrWhiteSpace([string]$pathProperty.Value)) { continue }
            $hashProperty = $receipt.launcher.PSObject.Properties[[string]$pair[1]]
            $path = [IO.Path]::GetFullPath([string]$pathProperty.Value)
            if ($null -eq $hashProperty -or [string]$hashProperty.Value -cnotmatch '^[0-9a-f]{64}$' -or
                -not $frozen.ContainsKey($path) -or $frozen[$path] -cne [string]$hashProperty.Value) {
                throw "Prepared source launcher path/hash pair is missing from the frozen closure: $($pair[0])"
            }
        }
        $installRoot = [IO.Path]::GetFullPath([string]$receipt.installRoot)
        if (-not (Test-Path -LiteralPath $installRoot -PathType Container)) { throw 'Prepared source receipt install root is missing.' }
        $installFiles = @(Get-ChildItem -LiteralPath $installRoot -Force -Recurse -ErrorAction Stop)
        foreach ($installFile in $installFiles) {
            if ($installFile.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Prepared source tool closure contains a reparse point: $($installFile.FullName)" }
            if ($installFile.PSIsContainer) { continue }
            $path = [IO.Path]::GetFullPath($installFile.FullName)
            if (-not $frozen.ContainsKey($path) -or (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -cne $frozen[$path]) {
                throw "Prepared source tool closure file is missing or changed in the frozen closure: $path"
            }
        }
    }
    foreach ($name in @('skill-validator', 'skill-tools', 'skillspector')) {
        if (-not $receiptNames.Contains($name)) { throw "Prepared source tool receipt is missing: $name" }
    }

    $pesterFields = @('moduleManifestPath', 'closureLockPath', 'closureLockSha256', 'setupReceiptPath', 'setupReceiptSha256',
        'runtimeRoot', 'runtimeExecutablePath', 'runtimeExecutableSha256', 'runtimeInventoryPath', 'runtimeInventorySha256', 'sourceTrustedToolRoot')
    $pesterProperties = @($Prepared.pesterRuntime.PSObject.Properties | ForEach-Object { [string]$_.Name })
    if ($pesterProperties.Count -ne $pesterFields.Count -or
        @($pesterFields | Where-Object { $pesterProperties -cnotcontains $_ }).Count -gt 0 -or
        @($pesterProperties | Where-Object { $pesterFields -cnotcontains $_ }).Count -gt 0) {
        throw 'Prepared Pester runtime binding has an invalid property set.'
    }
    foreach ($binding in @(
        [pscustomobject]@{ path = [string]$Prepared.pesterRuntime.closureLockPath; sha = [string]$Prepared.pesterRuntime.closureLockSha256; name = 'closure lock' },
        [pscustomobject]@{ path = [string]$Prepared.pesterRuntime.setupReceiptPath; sha = [string]$Prepared.pesterRuntime.setupReceiptSha256; name = 'setup receipt' }
    )) {
        $full = [IO.Path]::GetFullPath($binding.path)
        if (-not $frozen.ContainsKey($full) -or $frozen[$full] -cne $binding.sha -or
            (Get-FileHash -LiteralPath $full -Algorithm SHA256).Hash.ToLowerInvariant() -cne $binding.sha) {
            throw "Prepared Pester $($binding.name) is missing from the frozen closure or changed."
        }
    }
    $manifest = [IO.Path]::GetFullPath([string]$Prepared.pesterRuntime.moduleManifestPath)
    if (-not $frozen.ContainsKey($manifest)) { throw 'Prepared Pester manifest is missing from the frozen closure.' }
    $runtimeInventory = Assert-CodeSourceRuntimeInventory -PesterRuntime $Prepared.pesterRuntime -OwnedRoot ([string]$Prepared.ownedRoot) -FrozenFiles $frozen
    $receipt = Get-Content -LiteralPath ([string]$Prepared.pesterRuntime.setupReceiptPath) -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json -Depth 50 -ErrorAction Stop
    if ([string]$receipt.runId -cne [string]$Prepared.runId -or [string]$receipt.lockSha256 -cne [string]$Prepared.pesterRuntime.closureLockSha256 -or
        [string]$receipt.terminalStatus -cne 'verified' -or
        -not [IO.Path]::GetFullPath([string]$receipt.runtimeExecutable).Equals([IO.Path]::GetFullPath($PowerShellPath), $(if ($IsWindows) { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal })) -or
        -not [IO.Path]::GetFullPath([string]$receipt.runtimeModuleRoot).Equals([IO.Path]::GetFullPath((Split-Path -Parent $manifest)), $(if ($IsWindows) { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal })) -or
        [string]$runtimeInventory.executableSha256 -cne [string]$Prepared.pesterRuntime.runtimeExecutableSha256) {
        throw 'Prepared Pester setup receipt does not bind the source run, lock and exact runtime.'
    }
    $dispatchRoot = [IO.Path]::GetFullPath([string]$Prepared.ownedRoot)
    $wrapperPath = [IO.Path]::GetFullPath((Join-Path $dispatchRoot 'Invoke-CodeCollaborationValidationChild.ps1'))
    $toolchainPath = [IO.Path]::GetFullPath((Join-Path $dispatchRoot 'toolchain.json'))
    $manifestPath = [IO.Path]::GetFullPath((Join-Path $dispatchRoot 'candidate-git-entry-modes.json'))
    foreach ($path in @($wrapperPath, $toolchainPath, $manifestPath, $archivePath)) {
        if (-not $frozen.ContainsKey($path)) { throw "Prepared source dispatch input is not frozen: $path" }
    }
    $commonArguments = @(
        '-NoProfile', '-NonInteractive', '-File', $wrapperPath,
        '-ToolchainPath', $toolchainPath, '-ToolchainSha256', [string]$frozen[$toolchainPath],
        '-SourceRepository', $SourceRepository, '-SourceRevision', $CandidateRevision,
        '-ArchiveSha256', [string]$Prepared.candidateArchiveSha256,
        '-GitEntryModeManifestPath', $manifestPath, '-GitEntryModeManifestSha256', [string]$frozen[$manifestPath]
    )
    $expectedModes = [ordered]@{
        packageAdapter = 'package-adapter'
        skillValidator = 'skill-validator'
        skillTools = 'skill-tools'
        staticAnalyzer = 'static'
    }
    foreach ($slot in @('packageAdapter', 'skillValidator', 'skillTools', 'staticAnalyzer')) {
        $dispatch = $Prepared.sourceValidation.$slot
        $properties = @($dispatch.PSObject.Properties | ForEach-Object { [string]$_.Name })
        if ($properties.Count -ne 2 -or $properties -cnotcontains 'command' -or $properties -cnotcontains 'arguments' -or
            [string]$dispatch.command -cne [IO.Path]::GetFullPath($PowerShellPath) -or $dispatch.arguments -isnot [array] -or
            @($dispatch.arguments).Count -ne ($commonArguments.Count + 2)) { throw "Prepared source dispatch '$slot' is incomplete or changed." }
        $expectedArguments = @($commonArguments + @('-Mode', [string]$expectedModes[$slot]))
        for ($index = 0; $index -lt $expectedArguments.Count; $index++) {
            if ([string]$dispatch.arguments[$index] -cne [string]$expectedArguments[$index]) {
                throw "Prepared source dispatch '$slot' does not select the exact protected wrapper, source inputs, and mode."
            }
        }
    }
    return $true
}

function Assert-CodeSourceAuthorityToolchain {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)] $Toolchain,
        [Parameter(Mandatory = $true)][string] $AuthorityRoot,
        [Parameter(Mandatory = $true)] $AuthorityPin
    )

    $root = [IO.Path]::GetFullPath($AuthorityRoot)
    $comparison = if ($IsWindows) { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal }
    foreach ($binding in @(
        [pscustomobject]@{ pathProperty = 'centralRunnerPath'; hashProperty = 'centralRunnerSha256'; relative = 'scripts/Invoke-StandardValidation.ps1' },
        [pscustomobject]@{ pathProperty = 'upstreamAdapterValidatorPath'; hashProperty = 'upstreamAdapterValidatorSha256'; relative = 'scripts/Validate-UpstreamAdapter.ps1' },
        [pscustomobject]@{ pathProperty = 'upstreamPolicyPath'; hashProperty = 'upstreamPolicySha256'; relative = 'docs/standards/upstream-adapter.json' }
    )) {
        $expectedHash = [string]$AuthorityPin.files[[string]$binding.relative]
        $expectedPath = [IO.Path]::GetFullPath((Join-Path $root ([string]$binding.relative -replace '/', [IO.Path]::DirectorySeparatorChar)))
        $pathValue = $Toolchain.PSObject.Properties[[string]$binding.pathProperty]
        $hashValue = $Toolchain.PSObject.Properties[[string]$binding.hashProperty]
        if ([string]::IsNullOrWhiteSpace($expectedHash) -or $null -eq $pathValue -or $null -eq $hashValue -or
            -not [IO.Path]::GetFullPath([string]$pathValue.Value).Equals($expectedPath, $comparison) -or
            [string]$hashValue.Value -cne $expectedHash -or
            -not (Test-Path -LiteralPath $expectedPath -PathType Leaf) -or
            (Get-FileHash -LiteralPath $expectedPath -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant() -cne $expectedHash) {
            throw "Prepared Standard Core helper does not match the actual exact authority checkout: $($binding.relative)"
        }
    }
    return $true
}

function Assert-CodeSourceReportBinding {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)] $Report,
        [Parameter(Mandatory = $true)] $Prepared,
        [Parameter(Mandatory = $true)][ValidatePattern('^[0-9a-f]{40}$')][string] $CandidateRevision,
        [Parameter(Mandatory = $true)][ValidatePattern('^[0-9a-f]{40}$')][string] $BaseRevision,
        [Parameter(Mandatory = $true)][ValidatePattern('^[0-9a-f]{40}$')][string] $AuthorityRevision,
        [Parameter(Mandatory = $true)][string] $EventName,
        [Parameter(Mandatory = $true)][string] $ArtifactsRoot,
        [Parameter(Mandatory = $true)][string] $OutputPath,
        [Parameter(Mandatory = $true)][int] $ProcessExitCode,
        [Parameter(Mandatory = $true)][bool] $CleanupSucceeded,
        [bool] $CancellationRequested = $false
    )

    if ($CancellationRequested -or -not $CleanupSucceeded -or $ProcessExitCode -ne 0) {
        throw 'Source report cannot pass after cancellation, cleanup failure, or a non-zero central exit.'
    }
    if ([int]$Report.schemaVersion -ne 2 -or [string]$Report.evidence -cne 'standard-core-validation-evidence-v2' -or
        [string]$Report.state -cne 'PASS' -or [int]$Report.exitCode -ne 0 -or $Report.releaseEligible -isnot [bool] -or $Report.releaseEligible -or
        [string]$Report.contentMode -cne 'immutable-source' -or [string]$Report.runId -cne [string]$Prepared.runId -or
        [string]$Report.candidate.contentMode -cne 'immutable-source' -or [string]$Report.candidate.sourceRevision -cne $CandidateRevision -or
        [string]$Report.candidate.baseRevision -cne $BaseRevision -or [string]$Report.candidate.eventName -cne $EventName -or
        [string]$Report.authority.contentMode -cne 'source' -or [string]$Report.authority.revision -cne $AuthorityRevision -or
        [string]$Report.artifacts.root -cne [IO.Path]::GetFullPath($ArtifactsRoot) -or
        [string]$Report.artifacts.outputPath -cne [IO.Path]::GetFullPath($OutputPath) -or
        [string]$Report.artifacts.runId -cne [string]$Prepared.runId) {
        throw 'Source report has a partial, cross-run, wrong candidate/base/authority/event, or failing identity.'
    }
    $source = $Report.PSObject.Properties['sourceValidation']
    if ($null -eq $source -or $null -eq $source.Value -or [string]$source.Value.status -cne 'passed' -or
        [string]$source.Value.runId -cne [string]$Prepared.runId -or
        [string]$source.Value.sourceRevision -cne $CandidateRevision -or [string]$source.Value.authorityRevision -cne $AuthorityRevision) {
        throw 'Core-only or partial report cannot satisfy SourceValidation.'
    }
    foreach ($field in @('toolReceipts', 'frozenFiles')) {
        if ((ConvertTo-Json -InputObject @($source.Value.$field) -Depth 50 -Compress) -cne
            (ConvertTo-Json -InputObject @($Prepared.sourceValidation.$field) -Depth 50 -Compress)) {
            throw "Source report $field differ from the prepared run identity."
        }
    }
    if ($Report.checks -isnot [array] -or @($Report.checks).Count -ne 2 -or
        [string]$Report.checks[0].kind -cne 'general' -or [string]$Report.checks[1].kind -cne 'pester' -or
        @($Report.checks | Where-Object { [string]$_.status -cne 'passed' -or [int]$_.exitCode -ne 0 -or $_.cleanedUp -isnot [bool] -or -not $_.cleanedUp }).Count -ne 0) {
        throw 'Source report must contain exactly two clean passing Core checks.'
    }
    $caseBinding = $source.Value.pesterCaseInventory
    if ($null -eq $caseBinding -or [string]$caseBinding.path -notmatch 'standard-core.*case|pester.*case' -or
        [string]$caseBinding.sha256 -cnotmatch '^[0-9a-f]{64}$' -or -not (Test-Path -LiteralPath ([string]$caseBinding.path) -PathType Leaf) -or
        (Get-FileHash -LiteralPath ([string]$caseBinding.path) -Algorithm SHA256).Hash.ToLowerInvariant() -cne [string]$caseBinding.sha256) {
        throw 'Source report Pester case sidecar is missing or changed.'
    }

    function Assert-CodeSourceReportEvidenceFile {
        param([Parameter(Mandatory)][string] $Path, [Parameter(Mandatory)][string] $Sha256,
            [Parameter(Mandatory)][string] $RunRoot, [Parameter(Mandatory)][string] $Context)
        $full = [IO.Path]::GetFullPath($Path)
        $root = [IO.Path]::GetFullPath($RunRoot).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
        $comparison = if ($IsWindows) { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal }
        $prefix = $root + [IO.Path]::DirectorySeparatorChar
        if ($Sha256 -cnotmatch '^[0-9a-f]{64}$' -or -not $full.StartsWith($prefix, $comparison) -or
            -not (Test-Path -LiteralPath $full -PathType Leaf)) { throw "$Context is missing, malformed, or outside the Core run root." }
        $cursor = $full
        while (-not $cursor.Equals($root, $comparison)) {
            $item = Get-Item -LiteralPath $cursor -Force -ErrorAction Stop
            if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "$Context contains a reparse path component." }
            $cursor = Split-Path -Parent $cursor
            if ([string]::IsNullOrWhiteSpace($cursor) -or $cursor.Equals([IO.Path]::GetPathRoot($cursor), $comparison)) {
                throw "$Context escaped the Core run root."
            }
        }
        if ((Get-FileHash -LiteralPath $full -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant() -cne $Sha256) {
            throw "$Context hash differs from its report binding."
        }
    }

    $runRoot = [IO.Path]::GetFullPath([string]$Report.artifacts.runRoot)
    $activeSkills = @($Report.candidate.activeSkills | ForEach-Object { [string]$_ })
    if ($activeSkills.Count -eq 0 -or @($activeSkills | Select-Object -Unique).Count -ne $activeSkills.Count) {
        throw 'Source report native evidence has no exact active Skill inventory.'
    }
    $nativeEventCounts = @{ 'skill-validator' = 0; 'skill-tools' = 0; 'static-analyzer' = 0 }
    foreach ($event in @($source.Value.events)) {
        $toolId = [string]$event.toolId
        if (-not $nativeEventCounts.ContainsKey($toolId)) { continue }
        Assert-CodeSourceReportEvidenceFile -Path ([string]$event.outputPath) -Sha256 ([string]$event.outputSha256) -RunRoot $runRoot -Context 'Source native event output'
        $eventRecord = Get-Content -LiteralPath ([string]$event.outputPath) -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json -Depth 60 -ErrorAction Stop
        if ([int]$eventRecord.schemaVersion -ne 1 -or [string]$eventRecord.toolId -cne $toolId -or
            [int]$eventRecord.process.exitCode -ne 0 -or [string]$eventRecord.process.status -cne 'passed') {
            throw 'Source native event output does not bind a clean passing tool process.'
        }
        $envelope = $null
        try { $envelope = ConvertFrom-Json -InputObject ([string]$eventRecord.stdout) -Depth 60 -ErrorAction Stop }
        catch { throw 'Source native event stdout does not contain a valid tool envelope.' }
        $nativeReports = @($envelope.nativeReports)
        if ($nativeReports.Count -eq 0) { throw 'Source native event omitted its native report inventory.' }
        foreach ($native in $nativeReports) {
            if ([string]$native.skillId -cnotin $activeSkills -or [int]$native.exitCode -ne 0 -or
                $native.arguments -isnot [array] -or @($native.arguments).Count -eq 0) {
                throw 'Source native report does not bind the expected Skill, arguments, or successful exit.'
            }
            Assert-CodeSourceReportEvidenceFile -Path ([string]$native.path) -Sha256 ([string]$native.sha256) -RunRoot $runRoot -Context 'Source native JSON report'
            Assert-CodeSourceReportEvidenceFile -Path ([string]$native.stdoutPath) -Sha256 ([string]$native.stdoutSha256) -RunRoot $runRoot -Context 'Source native stdout'
            Assert-CodeSourceReportEvidenceFile -Path ([string]$native.stderrPath) -Sha256 ([string]$native.stderrSha256) -RunRoot $runRoot -Context 'Source native stderr'
        }
        $nativeEventCounts[$toolId] += $nativeReports.Count
    }
    foreach ($toolId in @('skill-validator', 'skill-tools', 'static-analyzer')) {
        if ([int]$nativeEventCounts[$toolId] -ne $activeSkills.Count) {
            throw "Source report native raw evidence is incomplete for $toolId."
        }
    }
    return $true
}

function New-CodeCoreAdapterV2 {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string] $PowerShellPath,
        [Parameter(Mandatory = $true)][string] $TrustedToolRoot,
        [Parameter(Mandatory = $true)][string] $CandidateAuthorityAdapterRunId,
        [Parameter(Mandatory = $true)][ValidatePattern('^[0-9a-f]{40}$')][string] $CandidateRevision,
        [Parameter(Mandatory = $true)][string] $CandidateGitEntryModeManifestPath,
        [Parameter(Mandatory = $true)][ValidatePattern('^[0-9a-f]{64}$')][string] $CandidateGitEntryModeManifestSha256,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]] $ActiveSkillIds,
        [Parameter(Mandatory = $true)] $SourceValidation,
        [Parameter(Mandatory = $true)] $PesterRuntime
    )

    $fullPowerShellPath = [IO.Path]::GetFullPath($PowerShellPath)
    $fullTrustedToolRoot = [IO.Path]::GetFullPath($TrustedToolRoot).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    $pathComparison = if ($IsWindows) { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal }
    if (-not (Test-Path -LiteralPath $fullPowerShellPath -PathType Leaf)) { throw 'Trusted PowerShell executable is missing.' }
    if (-not $fullPowerShellPath.Equals($fullTrustedToolRoot, $pathComparison) -and
        -not $fullPowerShellPath.StartsWith($fullTrustedToolRoot + [IO.Path]::DirectorySeparatorChar, $pathComparison)) {
        throw 'Trusted PowerShell executable must be within TrustedToolRoot.'
    }
    if ($CandidateAuthorityAdapterRunId -cnotmatch '^[0-9a-f]{32}$') { throw 'Core source adapter requires one canonical RunId.' }
    if ($ActiveSkillIds.Count -eq 0) { throw 'Core source adapter requires at least one active Skill.' }
    [string[]]$ids = @($ActiveSkillIds)
    $sorted = @($ids)
    [Array]::Sort($sorted, [StringComparer]::Ordinal)
    if (($ids -join "`n") -cne ($sorted -join "`n") -or @($ids | Select-Object -Unique).Count -ne $ids.Count) {
        throw 'Core source adapter Skill inventory must be unique and ordinal sorted.'
    }
    foreach ($skillId in $ids) {
        if ($skillId -cnotmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$') { throw "Core source adapter contains an invalid Skill ID: '$skillId'." }
    }
    $sourceFields = @('packageAdapter', 'skillValidator', 'skillTools', 'staticAnalyzer', 'frozenFiles', 'toolReceipts')
    $sourceProperties = @($SourceValidation.PSObject.Properties | ForEach-Object { [string]$_.Name })
    if ($sourceProperties.Count -ne $sourceFields.Count -or
        @($sourceFields | Where-Object { $sourceProperties -cnotcontains $_ }).Count -gt 0 -or
        @($sourceProperties | Where-Object { $sourceFields -cnotcontains $_ }).Count -gt 0) {
        throw 'Prepared source validation payload has an invalid property set.'
    }
    foreach ($slot in @('packageAdapter', 'skillValidator', 'skillTools', 'staticAnalyzer')) {
        $dispatch = $SourceValidation.$slot
        $dispatchProperties = @($dispatch.PSObject.Properties | ForEach-Object { [string]$_.Name })
        if ($dispatchProperties.Count -ne 2 -or $dispatchProperties -cnotcontains 'command' -or $dispatchProperties -cnotcontains 'arguments' -or
            [string]$dispatch.command -cne $fullPowerShellPath -or $dispatch.arguments -isnot [array] -or @($dispatch.arguments).Count -lt 5) {
            throw "Prepared source validation dispatch '$slot' is incomplete or does not use the verified PowerShell executable."
        }
    }
    $pesterFields = @('moduleManifestPath', 'closureLockPath', 'closureLockSha256', 'setupReceiptPath', 'setupReceiptSha256',
        'runtimeRoot', 'runtimeExecutablePath', 'runtimeExecutableSha256', 'runtimeInventoryPath', 'runtimeInventorySha256', 'sourceTrustedToolRoot')
    $pesterProperties = @($PesterRuntime.PSObject.Properties | ForEach-Object { [string]$_.Name })
    if ($pesterProperties.Count -ne $pesterFields.Count -or
        @($pesterFields | Where-Object { $pesterProperties -cnotcontains $_ }).Count -gt 0 -or
        @($pesterProperties | Where-Object { $pesterFields -cnotcontains $_ }).Count -gt 0) {
        throw 'Prepared Pester runtime binding has an invalid property set.'
    }
    foreach ($field in @('moduleManifestPath', 'closureLockPath', 'setupReceiptPath', 'runtimeRoot', 'runtimeExecutablePath', 'runtimeInventoryPath', 'sourceTrustedToolRoot')) {
        if ([string]::IsNullOrWhiteSpace([string]$PesterRuntime.$field) -or -not [IO.Path]::IsPathRooted([string]$PesterRuntime.$field)) {
            throw "Prepared Pester runtime '$field' must be an absolute path."
        }
    }
    Assert-CodeSourceSha256 -Value ([string]$PesterRuntime.closureLockSha256) -Context 'Prepared Pester closure lock'
    Assert-CodeSourceSha256 -Value ([string]$PesterRuntime.setupReceiptSha256) -Context 'Prepared Pester setup receipt'
    Assert-CodeSourceSha256 -Value ([string]$PesterRuntime.runtimeExecutableSha256) -Context 'Prepared PowerShell executable'
    Assert-CodeSourceSha256 -Value ([string]$PesterRuntime.runtimeInventorySha256) -Context 'Prepared PowerShell runtime inventory'
    foreach ($field in @('moduleManifestPath', 'closureLockPath', 'setupReceiptPath')) {
        if (-not (Test-Path -LiteralPath ([string]$PesterRuntime.$field) -PathType Leaf)) {
            throw "Prepared Pester runtime '$field' is missing."
        }
    }
    foreach ($binding in @(
        [pscustomobject]@{ path = [string]$PesterRuntime.closureLockPath; hash = [string]$PesterRuntime.closureLockSha256; name = 'Pester closure lock' },
        [pscustomobject]@{ path = [string]$PesterRuntime.setupReceiptPath; hash = [string]$PesterRuntime.setupReceiptSha256; name = 'Pester setup receipt' },
        [pscustomobject]@{ path = [string]$PesterRuntime.runtimeInventoryPath; hash = [string]$PesterRuntime.runtimeInventorySha256; name = 'PowerShell runtime inventory' },
        [pscustomobject]@{ path = [string]$PesterRuntime.runtimeExecutablePath; hash = [string]$PesterRuntime.runtimeExecutableSha256; name = 'PowerShell executable' }
    )) {
        if ((Get-FileHash -LiteralPath $binding.path -Algorithm SHA256).Hash.ToLowerInvariant() -cne $binding.hash) { throw "$($binding.name) changed after source setup." }
    }

    $powerShellSha256 = (Get-FileHash -LiteralPath $fullPowerShellPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $trustedRuntimeRoot = [IO.Path]::GetFullPath([string]$PesterRuntime.runtimeRoot)
    $trustedRuntimeExecutable = [IO.Path]::GetFullPath([string]$PesterRuntime.runtimeExecutablePath)
    if (-not $trustedRuntimeExecutable.Equals($fullPowerShellPath, $pathComparison) -or
        -not $trustedRuntimeExecutable.StartsWith($trustedRuntimeRoot.TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar, $pathComparison) -or
        $powerShellSha256 -cne [string]$PesterRuntime.runtimeExecutableSha256) {
        throw 'Core adapter executable does not match the exact prepared run-owned PowerShell runtime.'
    }
    $runtimeFrozenFiles = [Collections.Generic.Dictionary[string, string]]::new($(if ($IsWindows) { [StringComparer]::OrdinalIgnoreCase } else { [StringComparer]::Ordinal }))
    foreach ($file in @($SourceValidation.frozenFiles)) {
        if ($null -eq $file -or [string]$file.path -cnotmatch '^(?:[A-Za-z]:\\|/)' -or [string]$file.sha256 -cnotmatch '^[0-9a-f]{64}$') {
            throw 'Core adapter source frozen file entry is malformed.'
        }
        $path = [IO.Path]::GetFullPath([string]$file.path)
        if (-not $runtimeFrozenFiles.TryAdd($path, [string]$file.sha256)) { throw 'Core adapter source frozen file inventory contains a duplicate path.' }
    }
    [void](Assert-CodeSourceRuntimeInventory -PesterRuntime $PesterRuntime -OwnedRoot (Split-Path -Parent $trustedRuntimeRoot) -FrozenFiles $runtimeFrozenFiles)
    $generalArguments = @('-NoProfile', '-NonInteractive', '-File', 'scripts/Invoke-RepositoryCheck.ps1',
        '-CandidateRevision', $CandidateRevision)
    $pesterArguments = @('-NoProfile', '-NonInteractive', '-File', 'scripts/Invoke-CorePester.ps1',
        '-CandidateAuthorityAdapterRunId', $CandidateAuthorityAdapterRunId, '-CandidateRevision', $CandidateRevision)
    return [ordered]@{
        schemaVersion = 2
        adapter = 'standard-core-adapter-v2'
        skillsRoot = 'skills'
        activeSkills = @($ids)
        sourceValidation = $SourceValidation
        checks = @(
            [ordered]@{ id = 'repository-general'; kind = 'general'; executable = $fullPowerShellPath; executableSha256 = $powerShellSha256; arguments = $generalArguments }
            [ordered]@{ id = 'repository-pester'; kind = 'pester'; executable = $fullPowerShellPath; executableSha256 = $powerShellSha256; arguments = $pesterArguments }
        )
    }
}

Export-ModuleMember -Function Get-PreparedSourceAuthorityPin, Assert-CodeSourceAuthorityConfig, Assert-CodeSourceRunRequest, New-CodeSourcePesterSetupEnvironment, New-CodeSourceFrozenFileInventory, Assert-CodeSourceProtectedDispatchFiles, Assert-CodeSourceProtectedRuntimeCopies, Assert-CodeSourcePreparedBindings, Assert-CodeSourceAuthorityToolchain, Assert-CodeSourceReportBinding, New-CodeCoreAdapterV2
