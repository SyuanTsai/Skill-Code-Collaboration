# SPDX-FileCopyrightText: 2026 SyuanTsai
# SPDX-License-Identifier: Apache-2.0
Describe 'Protected Standard Core SourceValidation preparation' {
    BeforeAll {
        $script:RepositoryRoot = Split-Path -Parent $PSScriptRoot
        $script:DriverPath = Join-Path $script:RepositoryRoot 'scripts/StandardSourceDriver.psm1'
        $script:ConfigPath = Join-Path $script:RepositoryRoot 'config/standard-v1.json'

        function Write-SourceBindingFixtureFile {
            param([Parameter(Mandatory)][string] $Path, [Parameter(Mandatory)][AllowEmptyString()][string] $Text)
            $fullPath = [IO.Path]::GetFullPath($Path)
            [void](New-Item -ItemType Directory -Path (Split-Path -Parent $fullPath) -Force)
            [IO.File]::WriteAllText($fullPath, $Text, [Text.UTF8Encoding]::new($false))
            return $fullPath
        }

        function Get-SourceBindingFixtureHash {
            param([Parameter(Mandatory)][string] $Path)
            return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
        }

        function Get-A031TextSha256 {
            param([Parameter(Mandatory)][AllowEmptyString()][string] $Value)
            $bytes = [Text.UTF8Encoding]::new($false).GetBytes($Value)
            return ([Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes))).ToLowerInvariant()
        }

        function New-SourceBindingFixture {
            param([Parameter(Mandatory)][string] $Root)

            Import-Module -Name $script:DriverPath -Force
            $base = [IO.Path]::GetFullPath($Root)
            [void](New-Item -ItemType Directory -Path $base -Force)
            $runId = [guid]::NewGuid().ToString('N')
            $candidateRevision = 'a' * 40
            $ownedRoot = Join-Path $base "source-tools-$runId"
            $runtimeRoot = Join-Path $ownedRoot 'runtime'
            $runtimeExecutableName = if ($IsWindows) { 'pwsh.exe' } else { 'pwsh' }
            $runtimeExecutable = Write-SourceBindingFixtureFile -Path (Join-Path $runtimeRoot $runtimeExecutableName) -Text 'fixture executable'
            $pesterModuleRoot = Join-Path $runtimeRoot 'Modules/Pester/6.2.0'
            $moduleManifest = Write-SourceBindingFixtureFile -Path (Join-Path $pesterModuleRoot 'Pester.psd1') -Text "@{ ModuleVersion = '6.2.0' }"
            $modulePayload = Write-SourceBindingFixtureFile -Path (Join-Path $pesterModuleRoot 'Pester.psm1') -Text '# fixture module payload'
            $closureLock = Write-SourceBindingFixtureFile -Path (Join-Path $ownedRoot 'pester-6.2.0-closure.lock.json') -Text '{"fixture":true}'
            $closureLockSha256 = Get-SourceBindingFixtureHash -Path $closureLock
            $setupReceiptPath = Write-SourceBindingFixtureFile -Path (Join-Path $ownedRoot 'pester-setup/setup-receipt.json') -Text '{}'
            $candidateArchivePath = Write-SourceBindingFixtureFile -Path (Join-Path $ownedRoot 'candidate.zip') -Text 'immutable candidate archive fixture'
            $manifestPath = Write-SourceBindingFixtureFile -Path (Join-Path $ownedRoot 'candidate-git-entry-modes.json') -Text '{"schemaVersion":3,"candidateCommit":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","entries":[{"path":"skills/demo/SKILL.md","mode":"100644","sha256":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"}]}'
            $sourceIdentityPath = Write-SourceBindingFixtureFile -Path (Join-Path $ownedRoot 'source-run-identity.json') -Text (([ordered]@{
                schemaVersion = 1; runId = $runId; sourceRevision = $candidateRevision
                authorityRevision = 'ff85d5f80fe795b96354e753074b5ce59ad04ecd'
                candidateManifestPath = [IO.Path]::GetFullPath($manifestPath); candidateManifestSha256 = Get-SourceBindingFixtureHash -Path $manifestPath
                candidateArchivePath = [IO.Path]::GetFullPath($candidateArchivePath); candidateArchiveSha256 = Get-SourceBindingFixtureHash -Path $candidateArchivePath
            } | ConvertTo-Json -Depth 20 -Compress) + "`n")
            $wrapperPath = Write-SourceBindingFixtureFile -Path (Join-Path $ownedRoot 'Invoke-CodeCollaborationValidationChild.ps1') -Text '# child fixture'
            $alternateWrapperPath = Write-SourceBindingFixtureFile -Path (Join-Path $ownedRoot 'alternate-frozen-script.ps1') -Text '# alternate frozen fixture script'
            $toolchainPath = Write-SourceBindingFixtureFile -Path (Join-Path $ownedRoot 'toolchain.json') -Text '{}'
            $resolverReceipts = @()
            $receiptPaths = @()
            $toolClosurePaths = @()
            foreach ($toolName in @('skill-validator', 'skill-tools', 'skillspector')) {
                $installRoot = Join-Path $ownedRoot "installed/$toolName"
                $executablePath = Write-SourceBindingFixtureFile -Path (Join-Path $installRoot "$toolName.bin") -Text "$toolName executable"
                $executableSha256 = Get-SourceBindingFixtureHash -Path $executablePath
                $launcher = [pscustomobject]@{
                    kind = 'fixture-launcher'; shimPath = ''; shimSha256 = ''
                    payloadPath = ''; payloadSha256 = ''; runtimePath = ''; runtimeSha256 = ''
                }
                $receipt = [ordered]@{
                    toolName = $toolName; resolutionRunId = $runId; frozenForRun = $true
                    installRoot = [IO.Path]::GetFullPath($installRoot)
                    executablePath = $executablePath; executableSha256 = $executableSha256
                    entryPointPath = ''; entryPointSha256 = ''; nodePath = ''; nodeSha256 = ''
                    goRuntimePath = ''; goRuntimeSha256 = ''; resolverHelperPath = ''; resolverHelperSha256 = ''
                    launcher = $launcher
                }
                if ($toolName -ceq 'skill-tools') {
                    $shimPath = Write-SourceBindingFixtureFile -Path (Join-Path $installRoot 'skill-tools.cmd') -Text '@echo off'
                    $receipt.launcher.shimPath = $shimPath
                    $receipt.launcher.shimSha256 = Get-SourceBindingFixtureHash -Path $shimPath
                    $receipt.entryPointPath = $executablePath
                    $receipt.entryPointSha256 = $executableSha256
                    $receipt.nodePath = $executablePath
                    $receipt.nodeSha256 = $executableSha256
                }
                $receiptPath = Write-SourceBindingFixtureFile -Path (Join-Path $ownedRoot "receipt-$toolName.json") -Text (($receipt | ConvertTo-Json -Depth 20 -Compress) + "`n")
                $receiptPaths += $receiptPath
                $toolClosurePaths += @(Get-ChildItem -LiteralPath $installRoot -File -Recurse | ForEach-Object { [IO.Path]::GetFullPath($_.FullName) })
                $resolverReceipts += [pscustomobject]@{ path = $receiptPath; sha256 = (Get-SourceBindingFixtureHash -Path $receiptPath) }
            }

            $runtimeFiles = @(Get-ChildItem -LiteralPath $runtimeRoot -File -Recurse -Force | ForEach-Object {
                [pscustomobject]@{ path = [IO.Path]::GetFullPath($_.FullName); sha256 = (Get-SourceBindingFixtureHash -Path $_.FullName) }
            })
            $runtimeInventoryPath = Write-SourceBindingFixtureFile -Path (Join-Path $ownedRoot 'powershell-runtime-inventory.json') -Text '{}'
            $runtimeInventory = [ordered]@{
                schemaVersion = 1; root = [IO.Path]::GetFullPath($runtimeRoot)
                executablePath = [IO.Path]::GetFullPath($runtimeExecutable)
                executableSha256 = Get-SourceBindingFixtureHash -Path $runtimeExecutable
                files = @($runtimeFiles | Sort-Object -Property path -CaseSensitive)
            }
            [IO.File]::WriteAllText($runtimeInventoryPath, (($runtimeInventory | ConvertTo-Json -Depth 20) + "`n"), [Text.UTF8Encoding]::new($false))
            $runtimeInventorySha256 = Get-SourceBindingFixtureHash -Path $runtimeInventoryPath
            $setupTimingPath = Write-SourceBindingFixtureFile -Path (Join-Path $ownedRoot 'setup-timing.json') -Text (([ordered]@{
                schemaVersion = 1; runId = $runId; startedAtUtc = [DateTimeOffset]::UtcNow.ToString('O')
                stageTimingCapturedAtUtc = [DateTimeOffset]::UtcNow.ToString('O')
                stageSeconds = [ordered]@{ closureInventoryHashAndSortSeconds = 0.1 }
                resolverSeconds = [ordered]@{ 'skill-validator' = 0.1; 'skill-tools' = 0.1; skillspector = 0.1 }
                stageTimingBoundary = 'runtime copy, candidate manifest/archive, resolver, Pester setup, and first frozen-file inventory/hash/sort intervals only; excludes final verification and prepared metadata write'
            } | ConvertTo-Json -Depth 20 -Compress) + "`n")

            $setupReceipt = [ordered]@{
                schemaVersion = 1; report = 'verified-pester-runtime-setup-v1'; runId = $runId
                lockSha256 = $closureLockSha256; terminalStatus = 'verified'
                runtimeExecutable = [IO.Path]::GetFullPath($runtimeExecutable)
                runtimeModuleRoot = [IO.Path]::GetFullPath($pesterModuleRoot)
            }
            [IO.File]::WriteAllText($setupReceiptPath, (($setupReceipt | ConvertTo-Json -Depth 20 -Compress) + "`n"), [Text.UTF8Encoding]::new($false))
            $setupReceiptSha256 = Get-SourceBindingFixtureHash -Path $setupReceiptPath

            $allSourceFiles = @($candidateArchivePath, $manifestPath, $sourceIdentityPath, $wrapperPath, $alternateWrapperPath, $toolchainPath, $runtimeInventoryPath, $setupTimingPath, $closureLock) + $toolClosurePaths
            $pesterClosureFiles = @($moduleManifest, $modulePayload)
            $receiptFrozenPaths = @($toolClosurePaths)
            $receiptBindingPaths = @($receiptPaths)
            $receiptCommandPaths = @($resolverReceipts | ForEach-Object { [string]$_.path })
            $sourcePesterFiles = @($moduleManifest, $setupReceiptPath) + @($pesterClosureFiles)
            $sourceReceiptFiles = @($receiptFrozenPaths) + @($receiptBindingPaths) + @($receiptCommandPaths) + @($toolClosurePaths)
            $inventory = New-CodeSourceFrozenFileInventory -RuntimeFiles @($runtimeFiles | ForEach-Object { [string]$_.path }) `
                -SourceFiles $allSourceFiles -PesterFiles $sourcePesterFiles -ReceiptFiles $sourceReceiptFiles
            $frozenFiles = @($inventory.files)
            $toolchainSha256 = Get-SourceBindingFixtureHash -Path $toolchainPath
            $manifestSha256 = Get-SourceBindingFixtureHash -Path $manifestPath
            $sourceRepository = 'https://github.com/SyuanTsai/Skill-Code-Collaboration.git'
            $commonArguments = @('-NoProfile', '-NonInteractive', '-File', [IO.Path]::GetFullPath($wrapperPath),
                '-ToolchainPath', [IO.Path]::GetFullPath($toolchainPath), '-ToolchainSha256', $toolchainSha256,
                '-SourceRepository', $sourceRepository, '-SourceRevision', $candidateRevision,
                '-ArchiveSha256', (Get-SourceBindingFixtureHash -Path $candidateArchivePath),
                '-GitEntryModeManifestPath', [IO.Path]::GetFullPath($manifestPath), '-GitEntryModeManifestSha256', $manifestSha256)
            $sourceValidation = [pscustomobject]@{
                packageAdapter = [pscustomobject]@{ command = [IO.Path]::GetFullPath($runtimeExecutable); arguments = @($commonArguments + @('-Mode', 'package-adapter')) }
                skillValidator = [pscustomobject]@{ command = [IO.Path]::GetFullPath($runtimeExecutable); arguments = @($commonArguments + @('-Mode', 'skill-validator')) }
                skillTools = [pscustomobject]@{ command = [IO.Path]::GetFullPath($runtimeExecutable); arguments = @($commonArguments + @('-Mode', 'skill-tools')) }
                staticAnalyzer = [pscustomobject]@{ command = [IO.Path]::GetFullPath($runtimeExecutable); arguments = @($commonArguments + @('-Mode', 'static')) }
                frozenFiles = [object[]]$frozenFiles
                toolReceipts = [object[]]$resolverReceipts
            }
            $trustedRoot = Join-Path $base 'trusted-tools'
            [void](New-Item -ItemType Directory -Path $trustedRoot -Force)
            $prepared = [pscustomobject]@{
                schemaVersion = 1; preparation = 'code-collaboration-source-tools'; runId = $runId
                sourceRevision = $candidateRevision; authorityRevision = 'ff85d5f80fe795b96354e753074b5ce59ad04ecd'
                ownedRoot = [IO.Path]::GetFullPath($ownedRoot)
                candidateArchivePath = [IO.Path]::GetFullPath($candidateArchivePath)
                candidateArchiveSha256 = Get-SourceBindingFixtureHash -Path $candidateArchivePath
                sourceValidation = $sourceValidation
                pesterRuntime = [pscustomobject]@{
                    moduleManifestPath = [IO.Path]::GetFullPath($moduleManifest)
                    closureLockPath = [IO.Path]::GetFullPath($closureLock); closureLockSha256 = $closureLockSha256
                    setupReceiptPath = [IO.Path]::GetFullPath($setupReceiptPath); setupReceiptSha256 = $setupReceiptSha256
                    runtimeRoot = [IO.Path]::GetFullPath($runtimeRoot); runtimeExecutablePath = [IO.Path]::GetFullPath($runtimeExecutable)
                    runtimeExecutableSha256 = Get-SourceBindingFixtureHash -Path $runtimeExecutable
                    runtimeInventoryPath = [IO.Path]::GetFullPath($runtimeInventoryPath); runtimeInventorySha256 = $runtimeInventorySha256
                    sourceTrustedToolRoot = [IO.Path]::GetFullPath($trustedRoot)
                }
            }
            $preparedPath = Join-Path $base 'prepared-source-tools.json'
            [IO.File]::WriteAllText($preparedPath, (($prepared | ConvertTo-Json -Depth 80) + "`n"), [Text.UTF8Encoding]::new($false))
            return [pscustomobject]@{
                root = $base; runId = $runId; candidateRevision = $candidateRevision
                prepared = $prepared; preparedPath = [IO.Path]::GetFullPath($preparedPath)
                runtimeRoot = [IO.Path]::GetFullPath($runtimeRoot); runtimeExecutable = [IO.Path]::GetFullPath($runtimeExecutable)
                manifestPath = [IO.Path]::GetFullPath($manifestPath); authorityRevision = 'ff85d5f80fe795b96354e753074b5ce59ad04ecd'
                toolClosurePaths = $toolClosurePaths; receiptPaths = $receiptPaths
            }
        }

        function New-SourceReportFixture {
            param([Parameter(Mandatory)][string] $Root)
            $fixture = New-SourceBindingFixture -Root (Join-Path $Root 'prepared')
            Import-Module -Name $script:DriverPath -Force
            $artifactRoot = Join-Path $Root 'core-run'
            $eventRoot = Join-Path $artifactRoot 'events'
            [void](New-Item -ItemType Directory -Path $eventRoot -Force)
            $casePath = Write-SourceBindingFixtureFile -Path (Join-Path $artifactRoot 'repository-pester-case-inventory-v1.json') -Text '{"schemaVersion":1,"cases":[]}'
            $events = @()
            foreach ($toolId in @('skill-validator', 'skill-tools', 'static-analyzer')) {
                $nativePath = Write-SourceBindingFixtureFile -Path (Join-Path $artifactRoot "$toolId-native.json") -Text '{"fixture":true}'
                $stdoutPath = Write-SourceBindingFixtureFile -Path (Join-Path $artifactRoot "$toolId.stdout.txt") -Text '{"results":[]}'
                $stderrPath = Write-SourceBindingFixtureFile -Path (Join-Path $artifactRoot "$toolId.stderr.txt") -Text ''
                $native = [ordered]@{
                    skillId = 'demo'; path = $nativePath; sha256 = Get-SourceBindingFixtureHash -Path $nativePath
                    stdoutPath = $stdoutPath; stdoutSha256 = Get-SourceBindingFixtureHash -Path $stdoutPath
                    stderrPath = $stderrPath; stderrSha256 = Get-SourceBindingFixtureHash -Path $stderrPath
                    command = 'fixture-command'; commandSha256 = ('c' * 64); arguments = @('fixture'); exitCode = 0
                }
                $envelope = [ordered]@{ schemaVersion = 1; status = 'passed'; decision = 'PASS'; nativeReports = @($native) }
                $eventRecord = [ordered]@{
                    schemaVersion = 1; toolId = $toolId
                    process = [ordered]@{ exitCode = 0; status = 'passed'; cleanedUp = $true }
                    stdout = ($envelope | ConvertTo-Json -Depth 30 -Compress); stderr = ''
                }
                $eventPath = Write-SourceBindingFixtureFile -Path (Join-Path $eventRoot "$toolId-event.json") -Text (($eventRecord | ConvertTo-Json -Depth 30 -Compress) + "`n")
                $events += [pscustomobject]@{ toolId = $toolId; outputPath = $eventPath; outputSha256 = Get-SourceBindingFixtureHash -Path $eventPath }
            }
            $candidateRevision = $fixture.candidateRevision
            $baseRevision = 'b' * 40
            $report = [pscustomobject]@{
                schemaVersion = 2; evidence = 'standard-core-validation-evidence-v2'; state = 'PASS'; exitCode = 0
                releaseEligible = $false; contentMode = 'immutable-source'; runId = $fixture.runId
                candidate = [pscustomobject]@{
                    contentMode = 'immutable-source'; sourceRevision = $candidateRevision; baseRevision = $baseRevision
                    eventName = 'pull_request'; activeSkills = @('demo')
                }
                authority = [pscustomobject]@{ contentMode = 'source'; revision = $fixture.authorityRevision }
                artifacts = [pscustomobject]@{
                    root = [IO.Path]::GetFullPath($artifactRoot); runRoot = [IO.Path]::GetFullPath($artifactRoot)
                    outputPath = [IO.Path]::GetFullPath((Join-Path $artifactRoot 'standard-core-validation-v2-report.json'))
                    runId = $fixture.runId
                }
                sourceValidation = [pscustomobject]@{
                    status = 'passed'; runId = $fixture.runId; sourceRevision = $candidateRevision
                    authorityRevision = $fixture.authorityRevision
                    toolReceipts = $fixture.prepared.sourceValidation.toolReceipts
                    frozenFiles = $fixture.prepared.sourceValidation.frozenFiles
                    events = [object[]]$events
                    pesterCaseInventory = [pscustomobject]@{ path = $casePath; sha256 = Get-SourceBindingFixtureHash -Path $casePath }
                }
                checks = @(
                    [pscustomobject]@{ kind = 'general'; status = 'passed'; exitCode = 0; cleanedUp = $true }
                    [pscustomobject]@{ kind = 'pester'; status = 'passed'; exitCode = 0; cleanedUp = $true }
                )
            }
            return [pscustomobject]@{ fixture = $fixture; report = $report; baseRevision = $baseRevision; artifactRoot = [IO.Path]::GetFullPath($artifactRoot) }
        }

        function New-GeneralWrapperFixture {
            param([Parameter(Mandatory)][string] $Root)

            $base = [IO.Path]::GetFullPath($Root)
            [void](New-Item -ItemType Directory -Path $base -Force)
            $runId = [guid]::NewGuid().ToString('N')
            $candidateRevision = 'a' * 40
            $artifactRoot = Join-Path $base 'core-artifacts'
            $runRoot = Join-Path $artifactRoot $runId
            $candidateRoot = Join-Path $runRoot 'candidate'
            [void](New-Item -ItemType Directory -Path $candidateRoot -Force)

            $git = Get-Command git -CommandType Application -ErrorAction Stop | Select-Object -First 1
            $gitRootOutput = @(& $git.Path -C $script:RepositoryRoot rev-parse --show-toplevel 2>$null)
            $gitRootExitCode = $LASTEXITCODE
            $exactGitRoot = $false
            if ($gitRootExitCode -eq 0 -and $gitRootOutput.Count -eq 1) {
                $reportedGitRoot = [IO.Path]::GetFullPath([string]$gitRootOutput[0]).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
                $repositoryRoot = [IO.Path]::GetFullPath($script:RepositoryRoot).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
                $pathComparison = if ($IsWindows) { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal }
                $exactGitRoot = $reportedGitRoot.Equals($repositoryRoot, $pathComparison)
            }

            $modeByPath = @{}
            $sourceHashByPath = @{}
            if ($exactGitRoot) {
                $relativePaths = @(& $git.Path -C $script:RepositoryRoot ls-files --cached --others --exclude-standard)
                $listExitCode = $LASTEXITCODE
                if ($listExitCode -ne 0 -or $relativePaths.Count -eq 0) { throw 'Could not enumerate the exact repository fixture paths.' }
                foreach ($line in @(& $git.Path -C $script:RepositoryRoot ls-files -s -- skills)) {
                    if ([string]$line -cmatch '^(?<mode>[0-9]{6}) [0-9a-f]{40} [0-3]\t(?<path>.+)$') { $modeByPath[[string]$Matches.path] = [string]$Matches.mode }
                }
                if ($LASTEXITCODE -ne 0) { throw 'Could not read tracked Skill entry modes from the exact repository root.' }
            }
            else {
                $approvedManifestPath = [string]$env:STANDARD_VALIDATION_CORE_GIT_ENTRY_MODE_MANIFEST_PATH
                $approvedManifestSha256 = [string]$env:STANDARD_VALIDATION_CORE_GIT_ENTRY_MODE_MANIFEST_SHA256
                $relativePaths = @(Get-ChildItem -LiteralPath $script:RepositoryRoot -File -Force -Recurse -ErrorAction Stop | Sort-Object -Property FullName -CaseSensitive | ForEach-Object {
                    if ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Snapshot fixture has a reparse file: $($_.FullName)" }
                    [IO.Path]::GetRelativePath($script:RepositoryRoot, $_.FullName).Replace([IO.Path]::DirectorySeparatorChar, '/').Replace([IO.Path]::AltDirectorySeparatorChar, '/')
                })
                $relativePaths = @($relativePaths | ForEach-Object { [string]$_ } | Sort-Object -CaseSensitive)
                if ($relativePaths.Count -eq 0) { throw 'Could not enumerate the immutable candidate snapshot fixture.' }
                if ([string]::IsNullOrWhiteSpace($approvedManifestPath) -and [string]::IsNullOrWhiteSpace($approvedManifestSha256)) {
                    # The legacy 8a base driver runs Pester directly on its clean
                    # candidate snapshot before it supplies a SourceValidation
                    # adapter. This local test fixture only contains regular files
                    # and the current active Skills are ordinary 100644 documents.
                    foreach ($relative in $relativePaths) { $modeByPath[$relative] = '100644' }
                }
                else {
                    if ([string]::IsNullOrWhiteSpace($approvedManifestPath) -or $approvedManifestSha256 -cnotmatch '^[0-9a-f]{64}$' -or
                        -not (Test-Path -LiteralPath $approvedManifestPath -PathType Leaf) -or
                        (Get-SourceBindingFixtureHash -Path $approvedManifestPath) -cne $approvedManifestSha256) {
                        throw 'A source Core snapshot fixture requires the approved frozen Git entry mode manifest from the retained adapter.'
                    }
                    $approvedManifest = Get-Content -LiteralPath $approvedManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 30
                    if ([int]$approvedManifest.schemaVersion -ne 3 -or [string]$approvedManifest.candidateCommit -cnotmatch '^[0-9a-f]{40}$') {
                        throw 'The retained Core Git entry mode manifest has an invalid identity.'
                    }
                    foreach ($entry in @($approvedManifest.entries)) {
                        $relative = [string]$entry.path
                        if ([string]::IsNullOrWhiteSpace($relative) -or $relative.StartsWith('/') -or $relative.Contains('\\') -or
                            @($relative.Split('/') | Where-Object { $_ -in @('', '.', '..') }).Count -gt 0 -or
                            [string]$entry.mode -cnotin @('100644', '100755') -or [string]$entry.sha256 -cnotmatch '^[0-9a-f]{64}$' -or
                            $modeByPath.ContainsKey($relative)) {
                            throw 'The retained Core Git entry mode manifest has a duplicate, malformed, or unsafe entry.'
                        }
                        $modeByPath[$relative] = [string]$entry.mode
                        $sourceHashByPath[$relative] = [string]$entry.sha256
                    }
                    if (($relativePaths -join "`n") -cne (@($modeByPath.Keys | Sort-Object -CaseSensitive) -join "`n")) {
                        throw 'Snapshot fixture file inventory differs from the retained candidate manifest.'
                    }
                    foreach ($relative in $relativePaths) {
                        $sourcePath = Join-Path $script:RepositoryRoot ($relative -replace '/', [IO.Path]::DirectorySeparatorChar)
                        if ((Get-SourceBindingFixtureHash -Path $sourcePath) -cne [string]$sourceHashByPath[$relative]) {
                            throw "Snapshot fixture file hash differs from the retained candidate manifest: $relative"
                        }
                    }
                }
            }
            $relativePaths = @($relativePaths | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -CaseSensitive)
            if ($relativePaths.Count -eq 0) { throw 'Could not enumerate the public repository fixture paths.' }
            foreach ($relative in $relativePaths) {
                $sourcePath = Join-Path $script:RepositoryRoot ($relative -replace '/', [IO.Path]::DirectorySeparatorChar)
                $targetPath = Join-Path $candidateRoot ($relative -replace '/', [IO.Path]::DirectorySeparatorChar)
                if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) { throw "Public repository fixture file is missing: $relative" }
                $sourceItem = Get-Item -LiteralPath $sourcePath -Force
                if ($sourceItem.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Fixture source has a reparse point: $sourcePath" }
                [void](New-Item -ItemType Directory -Path (Split-Path -Parent $targetPath) -Force)
                Copy-Item -LiteralPath $sourcePath -Destination $targetPath -Force
            }

            $entries = @(
                Get-ChildItem -LiteralPath $candidateRoot -File -Force -Recurse | Sort-Object -Property FullName -CaseSensitive | ForEach-Object {
                    if ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Candidate fixture has a reparse file: $($_.FullName)" }
                    $relative = [IO.Path]::GetRelativePath($candidateRoot, $_.FullName).Replace([IO.Path]::DirectorySeparatorChar, '/').Replace([IO.Path]::AltDirectorySeparatorChar, '/')
                    $mode = if ($modeByPath.ContainsKey($relative)) { [string]$modeByPath[$relative] } else { '100644' }
                    [pscustomobject][ordered]@{ path = $relative; mode = $mode; sha256 = Get-SourceBindingFixtureHash -Path $_.FullName }
                }
            )
            $manifest = [ordered]@{ schemaVersion = 3; candidateCommit = $candidateRevision; entries = @($entries) }
            $sourceOwnedRoot = Join-Path $base "source-tools-$runId"
            [void](New-Item -ItemType Directory -Path $sourceOwnedRoot -Force)
            $manifestPath = Write-SourceBindingFixtureFile -Path (Join-Path $sourceOwnedRoot 'candidate-git-entry-modes.json') -Text (($manifest | ConvertTo-Json -Depth 30 -Compress) + "`n")
            $archivePath = Write-SourceBindingFixtureFile -Path (Join-Path $sourceOwnedRoot 'candidate.zip') -Text 'immutable candidate archive fixture'
            $manifestHash = Get-SourceBindingFixtureHash -Path $manifestPath
            $archiveHash = Get-SourceBindingFixtureHash -Path $archivePath
            $sourceIdentityPath = Write-SourceBindingFixtureFile -Path (Join-Path $sourceOwnedRoot 'source-run-identity.json') -Text (([ordered]@{
                schemaVersion = 1; runId = $runId; sourceRevision = $candidateRevision
                authorityRevision = 'ff85d5f80fe795b96354e753074b5ce59ad04ecd'
                candidateManifestPath = [IO.Path]::GetFullPath($manifestPath); candidateManifestSha256 = $manifestHash
                candidateArchivePath = [IO.Path]::GetFullPath($archivePath); candidateArchiveSha256 = $archiveHash
            } | ConvertTo-Json -Depth 20 -Compress) + "`n")
            $protectedFiles = @('scripts/Invoke-RepositoryCheck.ps1', 'scripts/Invoke-CorePester.ps1', 'scripts/CorePesterIntegrity.psm1', 'scripts/Test-Repository.ps1', 'tests/validate-catalog.ps1')
            $protectedCopyPaths = @()
            foreach ($relative in $protectedFiles) {
                $sourcePath = Join-Path $script:RepositoryRoot ($relative -replace '/', [IO.Path]::DirectorySeparatorChar)
                $copyPath = Join-Path $sourceOwnedRoot ("runtime/ProtectedSourceChecks/" + $relative)
                [void](New-Item -ItemType Directory -Path (Split-Path -Parent $copyPath) -Force)
                Copy-Item -LiteralPath $sourcePath -Destination $copyPath -Force
                $protectedCopyPaths += [IO.Path]::GetFullPath($copyPath)
            }
            $powerShellPath = [IO.Path]::GetFullPath([Diagnostics.Process]::GetCurrentProcess().MainModule.FileName)
            $powerShellSha256 = Get-SourceBindingFixtureHash -Path $powerShellPath
            $frozenFiles = @([pscustomobject]@{ path = $manifestPath; sha256 = $manifestHash },
                [pscustomobject]@{ path = $archivePath; sha256 = $archiveHash },
                [pscustomobject]@{ path = $sourceIdentityPath; sha256 = Get-SourceBindingFixtureHash -Path $sourceIdentityPath },
                [pscustomobject]@{ path = $powerShellPath; sha256 = $powerShellSha256 })
            foreach ($copyPath in $protectedCopyPaths) { $frozenFiles += [pscustomobject]@{ path = $copyPath; sha256 = Get-SourceBindingFixtureHash -Path $copyPath } }
            $toolReceipts = @()
            foreach ($toolName in @('skill-validator', 'skill-tools', 'skillspector')) {
                $receiptPath = Write-SourceBindingFixtureFile -Path (Join-Path $sourceOwnedRoot "receipt-$toolName.json") -Text (([ordered]@{
                    toolName = $toolName; resolutionRunId = $runId; frozenForRun = $true
                } | ConvertTo-Json -Depth 10 -Compress) + "`n")
                $receiptHash = Get-SourceBindingFixtureHash -Path $receiptPath
                $toolReceipts += [pscustomobject]@{ path = $receiptPath; sha256 = $receiptHash }
                $frozenFiles += [pscustomobject]@{ path = $receiptPath; sha256 = $receiptHash }
            }
            $activeSkills = @((Get-Content -LiteralPath (Join-Path $candidateRoot 'catalog/source.json') -Raw | ConvertFrom-Json -Depth 20).skills)
            $generalArguments = @('-NoProfile', '-NonInteractive', '-File', 'scripts/Invoke-RepositoryCheck.ps1', '-CandidateRevision', $candidateRevision)
            $pesterArguments = @('-NoProfile', '-NonInteractive', '-File', 'scripts/Invoke-CorePester.ps1', '-CandidateAuthorityAdapterRunId', $runId, '-CandidateRevision', $candidateRevision)
            $adapterText = ([ordered]@{
                schemaVersion = 2; adapter = 'standard-core-adapter-v2'; skillsRoot = 'skills'; activeSkills = @($activeSkills)
                sourceValidation = [ordered]@{ frozenFiles = @($frozenFiles); toolReceipts = @($toolReceipts) }
                checks = @(
                    [ordered]@{ id = 'repository-general'; kind = 'general'; executable = $powerShellPath; executableSha256 = $powerShellSha256; arguments = $generalArguments }
                    [ordered]@{ id = 'repository-pester'; kind = 'pester'; executable = $powerShellPath; executableSha256 = $powerShellSha256; arguments = $pesterArguments }
                )
            } | ConvertTo-Json -Depth 30 -Compress) + "`n"
            $retainedAdapterPath = Write-SourceBindingFixtureFile -Path (Join-Path $runRoot 'source-core-adapter.json') -Text $adapterText
            $adapterRoot = Join-Path (Split-Path -Parent $base) ".core-v2-adapter-$runId"
            $adapterPath = Write-SourceBindingFixtureFile -Path (Join-Path $adapterRoot 'standard-core-adapter-v2.json') -Text $adapterText
            return [pscustomobject]@{
                runId = $runId; candidateRevision = $candidateRevision; artifactRoot = [IO.Path]::GetFullPath($artifactRoot)
                runRoot = [IO.Path]::GetFullPath($runRoot); candidateRoot = [IO.Path]::GetFullPath($candidateRoot)
                adapterPath = [IO.Path]::GetFullPath($adapterPath); retainedAdapterPath = [IO.Path]::GetFullPath($retainedAdapterPath)
                manifestPath = [IO.Path]::GetFullPath($manifestPath); manifestSha256 = Get-SourceBindingFixtureHash -Path $manifestPath
                sourceOwnedRoot = [IO.Path]::GetFullPath($sourceOwnedRoot); protectedCopyPaths = $protectedCopyPaths
                powerShellPath = $powerShellPath; powerShellSha256 = $powerShellSha256
                activeSkills = $activeSkills; wrapperPath = [IO.Path]::GetFullPath((Join-Path $candidateRoot 'scripts/Invoke-RepositoryCheck.ps1'))
            }
        }

        function Get-A031ProcessArgumentValue {
            param([Parameter(Mandatory)][string] $Name)
            $processArguments = [Environment]::GetCommandLineArgs()
            $matches = [Collections.Generic.List[string]]::new()
            for ($index = 0; $index -lt $processArguments.Count; $index++) {
                if ([string]$processArguments[$index] -ceq "-$Name") {
                    if ($index + 1 -ge $processArguments.Count -or [string]::IsNullOrWhiteSpace([string]$processArguments[$index + 1])) {
                        throw "The Pester process is missing its actual CLI -$Name value."
                    }
                    $matches.Add([string]$processArguments[$index + 1])
                }
            }
            if ($matches.Count -ne 1) { throw "The Pester process must contain exactly one actual CLI -$Name binding." }
            return $matches[0]
        }

        function Get-A031AuthoritySupervisorBinding {
            $authorityRoot = [Environment]::GetEnvironmentVariable('SYP154_CANDIDATE_AUTHORITY_ROOT', 'Process')
            $expectedSha256 = [Environment]::GetEnvironmentVariable('SYP302_A031_EXPECTED_RUNNER_SHA256', 'Process')
            $fixtureMode = $null
            $revision = $null
            $revisionSource = $null
            $toolchainPath = $null
            $toolchainSha256 = $null

            if (-not [string]::IsNullOrWhiteSpace($authorityRoot)) {
                # Keep the trusted Git-checkout path strict whenever CI supplies its authority root.
                $fullAuthorityRoot = [IO.Path]::GetFullPath($authorityRoot)
                $fixtureMode = 'syp154-git-root-head'
                $git = Get-Command git -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
                if ($null -eq $git) { throw 'The trusted SYP154 authority fixture requires Git to identify its actual checkout revision.' }
                $rootOutput = @(& $git.Path -C $fullAuthorityRoot rev-parse --show-toplevel 2>$null)
                $rootExitCode = $LASTEXITCODE
                if ($rootExitCode -ne 0 -or $rootOutput.Count -ne 1) { throw 'The trusted SYP154 authority fixture is not an identifiable Git checkout.' }
                $reportedRoot = [IO.Path]::GetFullPath([string]$rootOutput[0]).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
                $expectedRoot = $fullAuthorityRoot.TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
                $pathComparison = if ($IsWindows) { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal }
                if (-not $reportedRoot.Equals($expectedRoot, $pathComparison)) { throw 'The trusted SYP154 authority path is not the root of its Git checkout.' }
                $revisionOutput = @(& $git.Path -C $fullAuthorityRoot rev-parse HEAD 2>$null)
                if ($LASTEXITCODE -ne 0 -or $revisionOutput.Count -ne 1 -or [string]$revisionOutput[0] -cnotmatch '^[0-9a-f]{40}$') {
                    throw 'The trusted SYP154 authority checkout does not have one exact Git HEAD revision.'
                }
                $revision = [string]$revisionOutput[0]
                $revisionSource = 'exact-authority-git-root'
            }
            else {
                # The protected legacy driver may not pass SYP154_CANDIDATE_AUTHORITY_ROOT.
                # Admit that path only through the existing CLI-bound 8a archive resolver.
                $fixtureMode = 'verified-driver-archive'
                $toolchainPath = Get-A031ProcessArgumentValue -Name 'ToolchainPath'
                $toolchainSha256 = Get-A031ProcessArgumentValue -Name 'ToolchainSha256'
                if ($toolchainSha256 -cnotmatch '^[0-9a-f]{64}$') { throw 'The actual Pester CLI ToolchainSha256 value is malformed.' }
                $resolverPath = Join-Path $script:RepositoryRoot 'tests/ResolveLegacyAuthorityArchiveFixture.ps1'
                $powerShellPath = [IO.Path]::GetFullPath([Diagnostics.Process]::GetCurrentProcess().MainModule.FileName)
                $resolverOutput = @(& $powerShellPath -NoLogo -NoProfile -NonInteractive -File $resolverPath `
                    -RepositoryRoot $script:RepositoryRoot -ToolchainPath $toolchainPath -ToolchainSha256 $toolchainSha256 2>&1)
                $resolverExitCode = $LASTEXITCODE
                if ($resolverExitCode -ne 0) { throw "Verified legacy archive fixture admission failed: $($resolverOutput -join ' ')" }
                $receiptText = ($resolverOutput -join "`n").Trim()
                try { $receipt = $receiptText | ConvertFrom-Json -Depth 30 -ErrorAction Stop }
                catch { throw 'Verified legacy archive fixture did not emit one parseable receipt.' }

                $authorityConfigPath = Join-Path $script:RepositoryRoot 'config/standard-v1.json'
                $authorityConfig = Get-Content -LiteralPath $authorityConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 40 -ErrorAction Stop
                $pinnedRunner = @($authorityConfig.authority.files | Where-Object { [string]$_.path -ceq 'scripts/Invoke-StandardValidation.ps1' })
                if ([string]$receipt.fixtureMode -cne 'verified-driver-archive' -or
                    [string]$receipt.authorityRevision -cne [string]$authorityConfig.authority.commit -or
                    [string]$receipt.authorityRevision -cne '8aabd22694a05771f98639f6d726cc9a620eb94b' -or
                    [int]$receipt.authorityFileCount -ne 26 -or [int]$receipt.authorityExtraFileCount -lt 1 -or
                    [IO.Path]::GetFullPath([string]$receipt.toolchainPath) -cne [IO.Path]::GetFullPath($toolchainPath) -or
                    [string]$receipt.toolchainSha256 -cne $toolchainSha256 -or $pinnedRunner.Count -ne 1) {
                    throw 'Verified legacy archive receipt does not bind the active exact 8a authority and actual process toolchain CLI.'
                }
                $fullAuthorityRoot = [IO.Path]::GetFullPath([string]$receipt.authorityRoot)
                $revision = [string]$receipt.authorityRevision
                $revisionSource = 'verified-driver-archive'
            }

            $runnerPath = [IO.Path]::GetFullPath((Join-Path $fullAuthorityRoot 'scripts/Invoke-StandardValidation.ps1'))
            if (-not (Test-Path -LiteralPath $runnerPath -PathType Leaf)) {
                throw 'The admitted candidate authority fixture does not contain scripts/Invoke-StandardValidation.ps1.'
            }
            $runnerSha256 = Get-SourceBindingFixtureHash -Path $runnerPath
            if ($fixtureMode -ceq 'verified-driver-archive' -and $runnerSha256 -cne [string]$pinnedRunner[0].sha256) {
                throw 'Verified 8a archive runner bytes differ from the active standard-v1 authority pin.'
            }
            if (-not [string]::IsNullOrWhiteSpace($expectedSha256) -and $runnerSha256 -cne $expectedSha256) {
                throw "Trusted A031 supervisor hash differs from the requested immutable fixture: expected=$expectedSha256 actual=$runnerSha256"
            }
            return [pscustomobject]@{
                root = $fullAuthorityRoot
                path = $runnerPath
                sha256 = $runnerSha256
                revision = $revision
                revisionSource = $revisionSource
                fixtureMode = $fixtureMode
                toolchainPath = $toolchainPath
                toolchainSha256 = $toolchainSha256
            }
        }

        function Invoke-A031TrustedSupervisedProcess {
            param(
                [Parameter(Mandatory)][string] $RunnerPath,
                [Parameter(Mandatory)][string] $PowerShellPath,
                [Parameter(Mandatory)][string[]] $Arguments,
                [Parameter(Mandatory)][string] $WorkingDirectory,
                [Parameter(Mandatory)][hashtable] $Environment,
                [Parameter(Mandatory)][string] $CandidateRoot,
                [Parameter(Mandatory)][string] $AdapterPath,
                [Parameter(Mandatory)][string] $ArtifactsRoot,
                [Parameter(Mandatory)][string] $Revision
            )
            . $RunnerPath -CandidateRoot $CandidateRoot -AdapterPath $AdapterPath -ArtifactsRoot $ArtifactsRoot `
                -SourceRepository 'https://github.com/SyuanTsai/Skill-Code-Collaboration.git' `
                -SourceRevision $Revision -BaseRevision $Revision -EventName local -DefineFunctionsOnly
            return Invoke-StandardValidationProcess -Command $PowerShellPath -Arguments $Arguments `
                -WorkingDirectory $WorkingDirectory -Environment $Environment -TimeoutSeconds 90 -CoreLifecycleOnly
        }

        function Save-A031EvidenceJson {
            param([Parameter(Mandatory)][string] $Name, [Parameter(Mandatory)] $Value)
            $text = ($Value | ConvertTo-Json -Depth 80) + "`n"
            return Save-A031EvidenceBytes -Name $Name -Bytes ([Text.UTF8Encoding]::new($false).GetBytes($text))
        }

        function Save-A031EvidenceBytes {
            param([Parameter(Mandatory)][string] $Name, [Parameter(Mandatory)][AllowEmptyCollection()][byte[]] $Bytes)
            $evidenceRoot = [Environment]::GetEnvironmentVariable('SYP302_A031_EVIDENCE_ROOT', 'Process')
            if ([string]::IsNullOrWhiteSpace($evidenceRoot)) { return $null }
            $fullRoot = [IO.Path]::GetFullPath($evidenceRoot)
            [void](New-Item -ItemType Directory -Path $fullRoot -Force)
            if ([IO.Path]::GetFileName($Name) -cne $Name -or [string]::IsNullOrWhiteSpace($Name)) {
                throw "A031 evidence name must be a single file name: $Name"
            }
            $path = Join-Path $fullRoot $Name
            $stream = [IO.File]::Open($path, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
            try { $stream.Write($Bytes, 0, $Bytes.Length) }
            finally { $stream.Dispose() }
            return $path
        }

        function Save-A031EvidenceFile {
            param([Parameter(Mandatory)][string] $Name, [Parameter(Mandatory)][string] $SourcePath)
            $source = Get-Item -LiteralPath $SourcePath -Force -ErrorAction Stop
            if ($source -isnot [IO.FileInfo] -or $source.Attributes -band [IO.FileAttributes]::ReparsePoint) {
                throw "A031 evidence source must be a regular non-reparse file: $SourcePath"
            }
            return Save-A031EvidenceBytes -Name $Name -Bytes ([IO.File]::ReadAllBytes($source.FullName))
        }

        function Save-A031CandidateEvidenceTree {
            param(
                [Parameter(Mandatory)][string] $EvidenceSubdirectory,
                [Parameter(Mandatory)][string] $CandidateRoot,
                [Parameter(Mandatory)][object[]] $ManifestEntries,
                [string] $SignalRelativePath,
                [byte[]] $SignalBytes = [byte[]]@()
            )
            $evidenceRoot = [Environment]::GetEnvironmentVariable('SYP302_A031_EVIDENCE_ROOT', 'Process')
            if ([string]::IsNullOrWhiteSpace($evidenceRoot)) { return $null }
            $targetRoot = Join-Path ([IO.Path]::GetFullPath($evidenceRoot)) $EvidenceSubdirectory
            if (Test-Path -LiteralPath $targetRoot) { throw "A031 candidate evidence destination already exists: $targetRoot" }
            [void](New-Item -ItemType Directory -Path $targetRoot)
            foreach ($entry in $ManifestEntries) {
                $relative = [string]$entry.path
                if ([string]::IsNullOrWhiteSpace($relative) -or $relative.StartsWith('/') -or $relative.Contains('\') -or
                    @($relative.Split('/') | Where-Object { $_ -in @('', '.', '..') }).Count -gt 0) {
                    throw "A031 frozen fixture manifest contains an unsafe path: $relative"
                }
                $sourcePath = Join-Path $CandidateRoot ($relative -replace '/', [IO.Path]::DirectorySeparatorChar)
                $source = Get-Item -LiteralPath $sourcePath -Force -ErrorAction Stop
                if ($source -isnot [IO.FileInfo] -or $source.Attributes -band [IO.FileAttributes]::ReparsePoint -or
                    (Get-SourceBindingFixtureHash -Path $sourcePath) -cne [string]$entry.sha256) {
                    throw "A031 candidate fixture differs from its immutable manifest entry: $relative"
                }
                $targetPath = Join-Path $targetRoot ($relative -replace '/', [IO.Path]::DirectorySeparatorChar)
                [void](New-Item -ItemType Directory -Path (Split-Path -Parent $targetPath) -Force)
                $targetStream = [IO.File]::Open($targetPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
                try {
                    $bytes = [IO.File]::ReadAllBytes($sourcePath)
                    $targetStream.Write($bytes, 0, $bytes.Length)
                }
                finally { $targetStream.Dispose() }
            }
            if (-not [string]::IsNullOrWhiteSpace($SignalRelativePath)) {
                if ($SignalRelativePath.StartsWith('/') -or $SignalRelativePath.Contains('\') -or
                    @($SignalRelativePath.Split('/') | Where-Object { $_ -in @('', '.', '..') }).Count -gt 0 -or
                    @($ManifestEntries | Where-Object { [string]$_.path -ceq $SignalRelativePath }).Count -gt 0) {
                    throw "A031 supervisor signal path conflicts with or escapes the immutable manifest: $SignalRelativePath"
                }
                $signalTarget = Join-Path $targetRoot ($SignalRelativePath -replace '/', [IO.Path]::DirectorySeparatorChar)
                [void](New-Item -ItemType Directory -Path (Split-Path -Parent $signalTarget) -Force)
                $signalStream = [IO.File]::Open($signalTarget, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
                try { $signalStream.Write($SignalBytes, 0, $SignalBytes.Length) }
                finally { $signalStream.Dispose() }
            }
            return [IO.Path]::GetFullPath($targetRoot)
        }
    }

    # Scenario: the source authority allowlist exposes the reviewed ff85 commit and all 32 closure records.
    # Purpose: bind the future SourceValidation path to the complete reviewed authority tuple while the active config stays pinned to 8a.
    It 'UnitT10_accepts_only_the_complete_prepared_authority_closure' {
        Test-Path -LiteralPath $script:DriverPath -PathType Leaf | Should -BeTrue
        Import-Module -Name $script:DriverPath -Force
        $pin = Get-PreparedSourceAuthorityPin
        $pin.repository | Should -Be 'https://github.com/SyuanTsai/SyuanTsai-AI-Instructions.git'
        $pin.commit | Should -Be 'ff85d5f80fe795b96354e753074b5ce59ad04ecd'
        $pin.archiveUrl | Should -Be 'https://codeload.github.com/SyuanTsai/SyuanTsai-AI-Instructions/zip/ff85d5f80fe795b96354e753074b5ce59ad04ecd'
        $pin.archiveSha256 | Should -Be '3dc38613f2e2316ad8fcc79d4bf48d0b03fd8398f8dacc72d156abcbce95ea9d'
        $pin.files.Count | Should -Be 32

        $active = Get-Content -LiteralPath $script:ConfigPath -Raw | ConvertFrom-Json -Depth 20
        $active.authority.commit | Should -Be '8aabd22694a05771f98639f6d726cc9a620eb94b'
        $active.authority.archiveSha256 | Should -Be 'd92df1a8f0aa342970dc9c66a77b6211955b4708de12119cb7f9a360fd265311'
    }

    # Scenario: the prepared tuple has one missing, repeated, reordered, mixed, or altered identity member.
    # Purpose: prevent tuple comparison or PowerShell collection semantics from admitting partial authority closure.
    It 'UnitT20_rejects_partial_duplicate_reordered_mixed_and_wrong_hash_authority_tuples' {
        Import-Module -Name $script:DriverPath -Force
        $pin = Get-PreparedSourceAuthorityPin
        $valid = [pscustomobject]@{
            schemaVersion = 1
            standardVersion = 'v1'
            authority = [pscustomobject]@{
                repository = $pin.repository
                commit = $pin.commit
                archiveUrl = $pin.archiveUrl
                archiveSha256 = $pin.archiveSha256
                files = @($pin.files.GetEnumerator() | ForEach-Object { [pscustomobject]@{ path = [string]$_.Key; sha256 = [string]$_.Value } })
            }
        }
        { Assert-CodeSourceAuthorityConfig -Config $valid } | Should -Not -Throw

        $missing = $valid | ConvertTo-Json -Depth 20 | ConvertFrom-Json -Depth 20
        $missing.authority.files = @($missing.authority.files | Select-Object -SkipLast 1)
        { Assert-CodeSourceAuthorityConfig -Config $missing } | Should -Throw

        $duplicate = $valid | ConvertTo-Json -Depth 20 | ConvertFrom-Json -Depth 20
        $duplicate.authority.files = @($duplicate.authority.files) + @($duplicate.authority.files[0])
        { Assert-CodeSourceAuthorityConfig -Config $duplicate } | Should -Throw

        $reordered = $valid | ConvertTo-Json -Depth 20 | ConvertFrom-Json -Depth 20
        $reordered.authority.files = @($reordered.authority.files[1], $reordered.authority.files[0]) + @($reordered.authority.files | Select-Object -Skip 2)
        { Assert-CodeSourceAuthorityConfig -Config $reordered } | Should -Throw

        $mixed = $valid | ConvertTo-Json -Depth 20 | ConvertFrom-Json -Depth 20
        $mixed.authority.commit = '8aabd22694a05771f98639f6d726cc9a620eb94b'
        { Assert-CodeSourceAuthorityConfig -Config $mixed } | Should -Throw

        $wrongHash = $valid | ConvertTo-Json -Depth 20 | ConvertFrom-Json -Depth 20
        $wrongHash.authority.files[31].sha256 = '0' * 64
        { Assert-CodeSourceAuthorityConfig -Config $wrongHash } | Should -Throw
    }

    # Scenario: Core v2 source setup or execution is requested alongside a legacy adapter or lifecycle mode.
    # Purpose: keep ordinary Core, SourceValidation, and historical v1 execution contracts disjoint.
    It 'UnitT30_rejects_legacy_mode_source_request_mixing_and_missing_setup_identity' {
        Import-Module -Name $script:DriverPath -Force
        Get-Command Assert-CodeSourceRunRequest -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        { Assert-CodeSourceRunRequest -ExecutionMode Run -PrepareSourceTools -SourceToolsPath 'C:\temp\source.json' -AdapterVersion 1 -AuthorityCommit 'ff85d5f80fe795b96354e753074b5ce59ad04ecd' } | Should -Throw
        { Assert-CodeSourceRunRequest -ExecutionMode Run -PrepareSourceTools -SourceValidation -SourceToolsPath 'C:\temp\source.json' -AdapterVersion 2 -AuthorityCommit 'ff85d5f80fe795b96354e753074b5ce59ad04ecd' } | Should -Throw
        { Assert-CodeSourceRunRequest -ExecutionMode Run -PrepareSourceTools -AdapterVersion 2 -AuthorityCommit 'ff85d5f80fe795b96354e753074b5ce59ad04ecd' } | Should -Throw
        { Assert-CodeSourceRunRequest -ExecutionMode Run -SourceValidation -SourceToolsPath 'C:\temp\source.json' -AdapterVersion 2 -AuthorityCommit 'ff85d5f80fe795b96354e753074b5ce59ad04ecd' -RunId 'bad' } | Should -Throw
        { Assert-CodeSourceRunRequest -ExecutionMode Run -SourceValidation -SourceToolsPath 'C:\temp\source.json' -AdapterVersion 2 -AuthorityCommit '8aabd22694a05771f98639f6d726cc9a620eb94b' -RunId ('a' * 32) } | Should -Throw
        { Assert-CodeSourceRunRequest -ExecutionMode Run -SourceToolsPath 'C:\temp\source.json' -AdapterVersion 2 -AuthorityCommit 'ff85d5f80fe795b96354e753074b5ce59ad04ecd' } | Should -Throw
    }

    # Scenario: the source-tools setup sender publishes the run-owned Pester root.
    # Purpose: pass only the environment namespace accepted by the protected Standard runner.
    It 'UnitT90_emits_only_the_namespaced_Pester_owned_root' {
        Import-Module -Name $script:DriverPath -Force -ErrorAction Stop
        Get-Command -Name New-CodeSourcePesterSetupEnvironment -CommandType Function -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        $ownedRoot = [IO.Path]::GetFullPath((Join-Path $TestDrive ("source-tools-" + [guid]::NewGuid().ToString('N'))))
        [void](New-Item -ItemType Directory -Path $ownedRoot -Force)
        $environment = New-CodeSourcePesterSetupEnvironment -OwnedRoot $ownedRoot

        @($environment.Keys).Count | Should -Be 1
        @($environment.Keys)[0] | Should -BeExactly 'STANDARD_VALIDATION_RUN_OWNED_ROOT'
        [string]$environment['STANDARD_VALIDATION_RUN_OWNED_ROOT'] | Should -BeExactly $ownedRoot
        $environment.Contains('RUN_OWNED_ROOT') | Should -BeFalse
    }

    # Scenario: setup receives a relative or malformed run-owned root.
    # Purpose: refuse values that GetFullPath could otherwise resolve against the process directory.
    It 'UnitT91_rejects_non_fully_qualified_Pester_owned_roots' {
        Import-Module -Name $script:DriverPath -Force -ErrorAction Stop
        Get-Command -Name New-CodeSourcePesterSetupEnvironment -CommandType Function -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        foreach ($invalidRoot in @('relative-root', '', '   ', [string][char]0)) {
            { New-CodeSourcePesterSetupEnvironment -OwnedRoot $invalidRoot } | Should -Throw
        }
        if ($IsWindows) {
            foreach ($invalidRoot in @('C:drive-relative-root', '\root-relative')) {
                { New-CodeSourcePesterSetupEnvironment -OwnedRoot $invalidRoot } | Should -Throw
            }
        }
    }

    # Scenario: preparation receives multiple file groups, including runtime and package arrays.
    # Purpose: prove every frozen entry is an individual path/hash record with no nested-array coercion.
    It 'UnitT40_accepts_complete_prepared_metadata_and_flattens_frozen_file_groups' {
        Import-Module -Name $script:DriverPath -Force
        $fixtureRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $fixture = New-SourceBindingFixture -Root $fixtureRoot
        { Assert-CodeSourcePreparedBindings -Prepared $fixture.prepared -PreparedPath $fixture.preparedPath `
            -CandidateRevision $fixture.candidateRevision -PowerShellPath $fixture.runtimeExecutable `
            -SourceRepository 'https://github.com/SyuanTsai/Skill-Code-Collaboration.git' } | Should -Not -Throw

        $frozen = @($fixture.prepared.sourceValidation.frozenFiles)
        $frozen.Count | Should -BeGreaterThan 10
        foreach ($entry in $frozen) {
            $entry.path | Should -BeOfType ([string])
            $entry.sha256 | Should -Match '^[0-9a-f]{64}$'
            $entry.path | Should -Not -Match 'System\.Object\[\]'
        }
    }

    # Scenario: a self-consistent alternate frozen script replaces the protected child wrapper in one dispatch.
    # Purpose: require every dispatch to select the exact protected wrapper and the complete prepared source arguments.
    It 'UnitT45_rejects_a_self_hashed_alternate_frozen_dispatch_script' {
        Import-Module -Name $script:DriverPath -Force
        $fixture = New-SourceBindingFixture -Root (Join-Path $TestDrive ([guid]::NewGuid().ToString('N')))
        $copy = ConvertFrom-Json -InputObject ($fixture.prepared | ConvertTo-Json -Depth 80 -Compress) -Depth 80
        $copy.sourceValidation.skillValidator.arguments[3] = Join-Path $copy.ownedRoot 'alternate-frozen-script.ps1'

        { Assert-CodeSourcePreparedBindings -Prepared $copy -PreparedPath $fixture.preparedPath `
            -CandidateRevision $fixture.candidateRevision -PowerShellPath $fixture.runtimeExecutable `
            -SourceRepository 'https://github.com/SyuanTsai/Skill-Code-Collaboration.git' } | Should -Throw '*protected wrapper*'
    }

    # Scenario: a prepared dispatch points at a different revision while all referenced files stay frozen.
    # Purpose: bind every execution to the same immutable candidate revision admitted by the setup receipt.
    It 'UnitT46_rejects_a_dispatch_with_a_different_source_revision' {
        Import-Module -Name $script:DriverPath -Force
        $fixture = New-SourceBindingFixture -Root (Join-Path $TestDrive ([guid]::NewGuid().ToString('N')))
        $copy = ConvertFrom-Json -InputObject ($fixture.prepared | ConvertTo-Json -Depth 80 -Compress) -Depth 80
        $revisionIndex = [array]::IndexOf([string[]]$copy.sourceValidation.packageAdapter.arguments, '-SourceRevision')
        $revisionIndex | Should -BeGreaterThan -1
        $copy.sourceValidation.packageAdapter.arguments[$revisionIndex + 1] = 'd' * 40

        { Assert-CodeSourcePreparedBindings -Prepared $copy -PreparedPath $fixture.preparedPath `
            -CandidateRevision $fixture.candidateRevision -PowerShellPath $fixture.runtimeExecutable `
            -SourceRepository 'https://github.com/SyuanTsai/Skill-Code-Collaboration.git' } | Should -Throw '*protected wrapper*'
    }

    # Scenario: the static-analysis slot is rewritten to use the skill-tools mode.
    # Purpose: make each named dispatch invoke only its exact reviewed operation.
    It 'UnitT47_rejects_a_source_dispatch_with_the_wrong_mode' {
        Import-Module -Name $script:DriverPath -Force
        $fixture = New-SourceBindingFixture -Root (Join-Path $TestDrive ([guid]::NewGuid().ToString('N')))
        $copy = ConvertFrom-Json -InputObject ($fixture.prepared | ConvertTo-Json -Depth 80 -Compress) -Depth 80
        $modeIndex = [array]::IndexOf([string[]]$copy.sourceValidation.staticAnalyzer.arguments, '-Mode')
        $modeIndex | Should -BeGreaterThan -1
        $copy.sourceValidation.staticAnalyzer.arguments[$modeIndex + 1] = 'skill-tools'

        { Assert-CodeSourcePreparedBindings -Prepared $copy -PreparedPath $fixture.preparedPath `
            -CandidateRevision $fixture.candidateRevision -PowerShellPath $fixture.runtimeExecutable `
            -SourceRepository 'https://github.com/SyuanTsai/Skill-Code-Collaboration.git' } | Should -Throw '*protected wrapper*'
    }

    # Scenario: a candidate substitutes one of the scripts dispatched by the protected Core adapter.
    # Purpose: require both the candidate manifest and candidate bytes to match the exact trusted-base bytes.
    It 'UnitT48_binds_core_dispatch_files_to_the_protected_base_bytes' {
        Import-Module -Name $script:DriverPath -Force
        $fixture = New-GeneralWrapperFixture -Root (Join-Path $TestDrive ([guid]::NewGuid().ToString('N')))
        $manifest = Get-Content -LiteralPath $fixture.manifestPath -Raw | ConvertFrom-Json -Depth 40
        $accepted = Assert-CodeSourceProtectedDispatchFiles -ProtectedBaseRoot $script:RepositoryRoot `
            -CandidateRoot $fixture.candidateRoot -ManifestEntries $manifest.entries
        @($accepted).Count | Should -Be 5

        $adapter = Get-Content -LiteralPath $fixture.retainedAdapterPath -Raw | ConvertFrom-Json -Depth 40
        $frozenFiles = @($adapter.sourceValidation.frozenFiles)
        $protectedCopyBindings = @(Assert-CodeSourceProtectedRuntimeCopies -ProtectedBaseRoot $script:RepositoryRoot `
            -CandidateRoot $fixture.candidateRoot -OwnedRoot $fixture.sourceOwnedRoot `
            -ManifestEntries $manifest.entries -FrozenFiles $frozenFiles)
        $protectedCopyBindings.Count | Should -Be 5

        $runtimeCopy = Join-Path $fixture.sourceOwnedRoot 'runtime/ProtectedSourceChecks/scripts/Test-Repository.ps1'
        [IO.File]::AppendAllText($runtimeCopy, "`n# self-hashed copied substitution`n", [Text.UTF8Encoding]::new($false))
        $selfConsistentFrozenFiles = @($frozenFiles | ForEach-Object {
            if ([IO.Path]::GetFullPath([string]$_.path).Equals([IO.Path]::GetFullPath($runtimeCopy), $(if ($IsWindows) { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal }))) {
                [pscustomobject]@{ path = $_.path; sha256 = Get-SourceBindingFixtureHash -Path $runtimeCopy }
            }
            else { $_ }
        })
        { Assert-CodeSourceProtectedRuntimeCopies -ProtectedBaseRoot $script:RepositoryRoot `
            -CandidateRoot $fixture.candidateRoot -OwnedRoot $fixture.sourceOwnedRoot `
            -ManifestEntries $manifest.entries -FrozenFiles $selfConsistentFrozenFiles } | Should -Throw '*differs from the trusted protected-base bytes*'
        Copy-Item -LiteralPath (Join-Path $script:RepositoryRoot 'scripts/Test-Repository.ps1') -Destination $runtimeCopy -Force

        $target = 'scripts/Invoke-RepositoryCheck.ps1'
        $candidatePath = Join-Path $fixture.candidateRoot ($target -replace '/', [IO.Path]::DirectorySeparatorChar)
        [IO.File]::AppendAllText($candidatePath, "`n# candidate substitution`n", [Text.UTF8Encoding]::new($false))
        $selfHashedEntries = @($manifest.entries | ForEach-Object {
            if ([string]$_.path -ceq $target) {
                [pscustomobject]@{ path = $_.path; mode = $_.mode; sha256 = Get-SourceBindingFixtureHash -Path $candidatePath }
            }
            else { $_ }
        })
        { Assert-CodeSourceProtectedDispatchFiles -ProtectedBaseRoot $script:RepositoryRoot `
            -CandidateRoot $fixture.candidateRoot -ManifestEntries $selfHashedEntries } | Should -Throw '*differs from the trusted driver bytes*'

        foreach ($invalidPath in @('scripts\Invoke-RepositoryCheck.ps1', 'scripts//Invoke-RepositoryCheck.ps1', 'scripts/./Invoke-RepositoryCheck.ps1')) {
            $invalidEntries = @($manifest.entries) + @([pscustomobject]@{ path = $invalidPath; mode = '100644'; sha256 = 'a' * 64 })
            { Assert-CodeSourceProtectedDispatchFiles -ProtectedBaseRoot $script:RepositoryRoot `
                -CandidateRoot $fixture.candidateRoot -ManifestEntries $invalidEntries } | Should -Throw '*invalid or duplicate protected dispatch entry*'
        }
    }

    # Scenario: the Core v2 adapter receives an admitted setup receipt and the exact candidate mode manifest.
    # Purpose: prove positive routing produces one general check plus the complete Pester closure and runtime identity arguments.
    It 'UnitT41_builds_the_complete_two_check_core_adapter_from_prepared_metadata' {
        Import-Module -Name $script:DriverPath -Force
        $fixtureRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $fixture = New-SourceBindingFixture -Root $fixtureRoot
        $adapter = New-CodeCoreAdapterV2 -PowerShellPath $fixture.runtimeExecutable -TrustedToolRoot $fixture.runtimeRoot `
            -CandidateAuthorityAdapterRunId $fixture.runId -CandidateRevision $fixture.candidateRevision `
            -CandidateGitEntryModeManifestPath $fixture.manifestPath `
            -CandidateGitEntryModeManifestSha256 (Get-SourceBindingFixtureHash -Path $fixture.manifestPath) `
            -ActiveSkillIds @('demo') -SourceValidation $fixture.prepared.sourceValidation -PesterRuntime $fixture.prepared.pesterRuntime

        $adapter.schemaVersion | Should -Be 2
        @($adapter.checks).Count | Should -Be 2
        @($adapter.checks | ForEach-Object { [string]$_.kind }) | Should -Be @('general', 'pester')
        $adapter.checks[0].arguments | Should -Contain 'scripts/Invoke-RepositoryCheck.ps1'
        $adapter.checks[1].arguments | Should -Contain 'scripts/Invoke-CorePester.ps1'
        foreach ($check in @($adapter.checks)) {
            [string]$check.executable | Should -Be $fixture.runtimeExecutable
            $check.arguments | Should -Contain '-CandidateRevision'
            $absoluteArguments = @($check.arguments | Where-Object { [IO.Path]::IsPathRooted([string]$_) })
            $absoluteArguments | Should -BeNullOrEmpty
            $encodedOrCommandArguments = @($check.arguments | Where-Object { [string]$_ -in @('-Command', '-EncodedCommand', '-EncodedArguments') })
            $encodedOrCommandArguments | Should -BeNullOrEmpty
        }
        $adapter.checks[1].arguments | Should -Contain '-CandidateAuthorityAdapterRunId'
    }

    # Scenario: one prepared resolver receipt references a skill-tools shim omitted from the frozen file inventory.
    # Purpose: reject an incomplete launcher closure even when the main package files and report hashes remain valid.
    It 'UnitT42_rejects_a_missing_skill_tools_shim_from_the_frozen_closure' {
        Import-Module -Name $script:DriverPath -Force
        $fixtureRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $fixture = New-SourceBindingFixture -Root $fixtureRoot
        $copy = ConvertFrom-Json -InputObject (ConvertTo-Json -InputObject $fixture.prepared -Depth 80 -Compress) -Depth 80
        $skillToolsReceipt = Get-Content -LiteralPath ($copy.sourceValidation.toolReceipts | Where-Object {
            (Get-Content -LiteralPath $_.path -Raw | ConvertFrom-Json -Depth 30).toolName -ceq 'skill-tools'
        } | Select-Object -First 1).path -Raw | ConvertFrom-Json -Depth 30
        $shimPath = [IO.Path]::GetFullPath([string]$skillToolsReceipt.launcher.shimPath)
        $copy.sourceValidation.frozenFiles = @($copy.sourceValidation.frozenFiles | Where-Object {
            -not [IO.Path]::GetFullPath([string]$_.path).Equals($shimPath, [StringComparison]::OrdinalIgnoreCase)
        })

        { Assert-CodeSourcePreparedBindings -Prepared $copy -PreparedPath $fixture.preparedPath `
            -CandidateRevision $fixture.candidateRevision -PowerShellPath $fixture.runtimeExecutable `
            -SourceRepository 'https://github.com/SyuanTsai/Skill-Code-Collaboration.git' } | Should -Throw '*launcher path/hash*'
    }

    # Scenario: prepared metadata names an authority script and hash that are not the reviewed files under its checkout root.
    # Purpose: prevent self-consistent caller metadata from replacing the central runner, upstream validator, or policy.
    It 'UnitT43_rejects_a_self_consistent_wrong_authority_helper_binding' {
        Import-Module -Name $script:DriverPath -Force
        $fixtureRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $authorityRoot = Join-Path $fixtureRoot 'authority'
        $relativePaths = @('scripts/Invoke-StandardValidation.ps1', 'scripts/Validate-UpstreamAdapter.ps1', 'docs/standards/upstream-adapter.json')
        $hashes = [ordered]@{}
        foreach ($relative in $relativePaths) {
            $path = Join-Path $authorityRoot ($relative -replace '/', [IO.Path]::DirectorySeparatorChar)
            [void](Write-SourceBindingFixtureFile -Path $path -Text "authority $relative")
            $hashes[$relative] = Get-SourceBindingFixtureHash -Path $path
        }
        $toolchain = [pscustomobject]@{
            centralRunnerPath = Join-Path $authorityRoot 'scripts/Invoke-StandardValidation.ps1'
            centralRunnerSha256 = $hashes['scripts/Invoke-StandardValidation.ps1']
            upstreamAdapterValidatorPath = Join-Path $authorityRoot 'scripts/Validate-UpstreamAdapter.ps1'
            upstreamAdapterValidatorSha256 = $hashes['scripts/Validate-UpstreamAdapter.ps1']
            upstreamPolicyPath = Join-Path $authorityRoot 'docs/standards/upstream-adapter.json'
            upstreamPolicySha256 = $hashes['docs/standards/upstream-adapter.json']
        }
        $pin = [pscustomobject]@{ files = $hashes }
        { Assert-CodeSourceAuthorityToolchain -Toolchain $toolchain -AuthorityRoot $authorityRoot -AuthorityPin $pin } | Should -Not -Throw

        $toolchain.upstreamAdapterValidatorSha256 = '0' * 64
        { Assert-CodeSourceAuthorityToolchain -Toolchain $toolchain -AuthorityRoot $authorityRoot -AuthorityPin $pin } | Should -Throw '*exact authority checkout*'
    }

    # Scenario: a report is core-only, partial, cross-run, or carries altered candidate/authority/event identity.
    # Purpose: admit only one complete source report whose two checks and native raw streams bind the prepared run.
    It 'UnitT44_accepts_the_complete_source_report_and_rejects_partial_or_cross_identity_reports' {
        Import-Module -Name $script:DriverPath -Force
        $fixtureRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $reportFixture = New-SourceReportFixture -Root $fixtureRoot
        $arguments = @{
            Report = $reportFixture.report; Prepared = $reportFixture.fixture.prepared
            CandidateRevision = $reportFixture.fixture.candidateRevision; BaseRevision = $reportFixture.baseRevision
            AuthorityRevision = $reportFixture.fixture.authorityRevision; EventName = 'pull_request'
            ArtifactsRoot = $reportFixture.artifactRoot; OutputPath = $reportFixture.report.artifacts.outputPath
            ProcessExitCode = 0; CleanupSucceeded = $true
        }
        { Assert-CodeSourceReportBinding @arguments } | Should -Not -Throw

        foreach ($mutation in @(
            { param($r) $r.sourceValidation.runId = 'f' * 32 }
            { param($r) $r.candidate.sourceRevision = 'c' * 40 }
            { param($r) $r.candidate.baseRevision = 'd' * 40 }
            { param($r) $r.authority.revision = 'e' * 40 }
            { param($r) $r.candidate.eventName = 'push' }
            { param($r) $r.checks = @($r.checks | Select-Object -First 1) }
            { param($r) $r.sourceValidation = $null }
        )) {
            $copy = ConvertFrom-Json -InputObject (ConvertTo-Json -InputObject $reportFixture.report -Depth 80 -Compress) -Depth 80
            & $mutation $copy
            $argsCopy = $arguments.Clone()
            $argsCopy.Report = $copy
            { Assert-CodeSourceReportBinding @argsCopy } | Should -Throw
        }

        $nonzero = $arguments.Clone()
        $nonzero.ProcessExitCode = 1
        { Assert-CodeSourceReportBinding @nonzero } | Should -Throw '*cancellation, cleanup failure, or a non-zero central exit*'
        $unclean = $arguments.Clone()
        $unclean.CleanupSucceeded = $false
        { Assert-CodeSourceReportBinding @unclean } | Should -Throw '*cancellation, cleanup failure, or a non-zero central exit*'
        $cancelled = $arguments.Clone()
        $cancelled.CancellationRequested = $true
        { Assert-CodeSourceReportBinding @cancelled } | Should -Throw '*cancellation, cleanup failure, or a non-zero central exit*'

        $caseSidecar = [string]$reportFixture.report.sourceValidation.pesterCaseInventory.path
        [IO.File]::AppendAllText($caseSidecar, 'tampered', [Text.UTF8Encoding]::new($false))
        { Assert-CodeSourceReportBinding @arguments } | Should -Throw '*case sidecar is missing or changed*'
    }

    # Scenario: the real Core general-check wrapper runs from an immutable candidate snapshot with its retained adapter and mode manifest.
    # Purpose: prove both production repository checks execute, pass their read-only bindings, and appear as hashed native reports in the general envelope.
    It 'InterT30_executes_the_real_general_wrapper_against_the_read_only_snapshot' {
        $fixture = New-GeneralWrapperFixture -Root (Join-Path $TestDrive ([guid]::NewGuid().ToString('N')))
        $runRoot = $fixture.runRoot
        $stdoutPath = Join-Path $runRoot 'general-wrapper.stdout.txt'
        $stderrPath = Join-Path $runRoot 'general-wrapper.stderr.txt'
        $previousRunId = [Environment]::GetEnvironmentVariable('STANDARD_VALIDATION_CORE_RUN_ID', 'Process')
        $previousCheckId = [Environment]::GetEnvironmentVariable('STANDARD_VALIDATION_CORE_CHECK_ID', 'Process')
        $previousSkills = [Environment]::GetEnvironmentVariable('STANDARD_VALIDATION_CORE_SKILLS', 'Process')
        $previousBootstrapReleasePath = [Environment]::GetEnvironmentVariable('STANDARD_VALIDATION_BOOTSTRAP_RELEASE_PATH', 'Process')
        $previousBootstrapCommand = [Environment]::GetEnvironmentVariable('STANDARD_VALIDATION_BOOTSTRAP_COMMAND', 'Process')
        $pwsh = [IO.Path]::GetFullPath([Diagnostics.Process]::GetCurrentProcess().MainModule.FileName)
        $foreignBootstrapReleasePath = Join-Path $fixture.sourceOwnedRoot 'a031-foreign-bootstrap-release.sig'
        $foreignBootstrapCommand = $pwsh
        $bootstrapEnvironmentRestored = $false
        try {
            [Environment]::SetEnvironmentVariable('STANDARD_VALIDATION_CORE_RUN_ID', $fixture.runId, 'Process')
            [Environment]::SetEnvironmentVariable('STANDARD_VALIDATION_CORE_CHECK_ID', 'repository-general', 'Process')
            [Environment]::SetEnvironmentVariable('STANDARD_VALIDATION_CORE_SKILLS', ($fixture.activeSkills -join ';'), 'Process')
            # Simulate the outer protected runner's foreign bootstrap context. This direct wrapper
            # invocation is intentionally unsupervised, so clear exactly those two values temporarily.
            [Environment]::SetEnvironmentVariable('STANDARD_VALIDATION_BOOTSTRAP_RELEASE_PATH', $foreignBootstrapReleasePath, 'Process')
            [Environment]::SetEnvironmentVariable('STANDARD_VALIDATION_BOOTSTRAP_COMMAND', $foreignBootstrapCommand, 'Process')
            [Environment]::GetEnvironmentVariable('STANDARD_VALIDATION_BOOTSTRAP_RELEASE_PATH', 'Process') | Should -Be $foreignBootstrapReleasePath
            [Environment]::GetEnvironmentVariable('STANDARD_VALIDATION_BOOTSTRAP_COMMAND', 'Process') | Should -Be $foreignBootstrapCommand
            [Environment]::SetEnvironmentVariable('STANDARD_VALIDATION_BOOTSTRAP_RELEASE_PATH', $null, 'Process')
            [Environment]::SetEnvironmentVariable('STANDARD_VALIDATION_BOOTSTRAP_COMMAND', $null, 'Process')
            Push-Location -LiteralPath $fixture.candidateRoot
            try {
                & $pwsh -NoLogo -NoProfile -NonInteractive -File $fixture.wrapperPath `
                    -CandidateRevision $fixture.candidateRevision 1> $stdoutPath 2> $stderrPath
                $exitCode = $LASTEXITCODE
            }
            finally {
                Pop-Location
                [Environment]::SetEnvironmentVariable('STANDARD_VALIDATION_BOOTSTRAP_RELEASE_PATH', $foreignBootstrapReleasePath, 'Process')
                [Environment]::SetEnvironmentVariable('STANDARD_VALIDATION_BOOTSTRAP_COMMAND', $foreignBootstrapCommand, 'Process')
            }
            [Environment]::GetEnvironmentVariable('STANDARD_VALIDATION_BOOTSTRAP_RELEASE_PATH', 'Process') | Should -Be $foreignBootstrapReleasePath
            [Environment]::GetEnvironmentVariable('STANDARD_VALIDATION_BOOTSTRAP_COMMAND', 'Process') | Should -Be $foreignBootstrapCommand
            $bootstrapEnvironmentRestored = $true
        }
        finally {
            [Environment]::SetEnvironmentVariable('STANDARD_VALIDATION_CORE_RUN_ID', $previousRunId, 'Process')
            [Environment]::SetEnvironmentVariable('STANDARD_VALIDATION_CORE_CHECK_ID', $previousCheckId, 'Process')
            [Environment]::SetEnvironmentVariable('STANDARD_VALIDATION_CORE_SKILLS', $previousSkills, 'Process')
            [Environment]::SetEnvironmentVariable('STANDARD_VALIDATION_BOOTSTRAP_RELEASE_PATH', $previousBootstrapReleasePath, 'Process')
            [Environment]::SetEnvironmentVariable('STANDARD_VALIDATION_BOOTSTRAP_COMMAND', $previousBootstrapCommand, 'Process')
        }

        $stderr = Get-Content -LiteralPath $stderrPath -Raw -Encoding UTF8
        $stdout = Get-Content -LiteralPath $stdoutPath -Raw -Encoding UTF8
        $bootstrapEnvironmentRestored | Should -BeTrue
        if ($exitCode -ne 0) { throw "General wrapper failed with exit $exitCode. stderr=$stderr stdout=$stdout" }
        $exitCode | Should -Be 0
        $stderr | Should -BeNullOrEmpty
        $envelope = ConvertFrom-Json -InputObject $stdout.Trim() -Depth 50
        $envelope.schemaVersion | Should -Be 1
        $envelope.status | Should -Be 'passed'
        $envelope.decision | Should -Be 'PASS'
        $envelope.candidateIdentity | Should -Match '^[0-9a-f]{64}$'
        @($envelope.activeSkills | ForEach-Object { [string]$_ }) | Should -Be $fixture.activeSkills
        @($envelope.nativeReports).Count | Should -Be 2

        $expectedReports = @('Test-Repository ReadOnlySnapshot/GitEntryModeManifest', 'validate-catalog')
        foreach ($native in @($envelope.nativeReports)) {
            [string]$native.id | Should -BeIn $expectedReports
            [string]$native.path | Should -Match ([regex]::Escape((Join-Path $runRoot 'repository-general')))
            [string]$native.sha256 | Should -Be (Get-SourceBindingFixtureHash -Path ([string]$native.path))
            [string]$native.command | Should -Match ([regex]::Escape((Join-Path $fixture.sourceOwnedRoot 'runtime/ProtectedSourceChecks')))
            [string]$native.commandSha256 | Should -Be (Get-SourceBindingFixtureHash -Path ([string]$native.command))
            [int]$native.exitCode | Should -Be 0
        }
        $repositoryReportPath = Join-Path $runRoot 'repository-general/test-repository.json'
        $catalogReportPath = Join-Path $runRoot 'repository-general/validate-catalog.json'
        $repositoryReport = Get-Content -LiteralPath $repositoryReportPath -Raw | ConvertFrom-Json -Depth 50
        $catalogReport = Get-Content -LiteralPath $catalogReportPath -Raw | ConvertFrom-Json -Depth 50
        $repositoryReport.result | Should -Be 'passed'
        $catalogReport.result | Should -Be 'passed'
        [int]$repositoryReport.activeSkillCount | Should -Be $fixture.activeSkills.Count
        [int]$catalogReport.activeSkillCount | Should -Be $fixture.activeSkills.Count
        (Test-Path -LiteralPath (Join-Path $runRoot 'candidate-git-entry-modes.json')) | Should -BeFalse
    }

    # Scenario: the trusted validation supervisor creates its real release signal inside the candidate working directory before launching the general wrapper.
    # Purpose: require the general wrapper to consume only that verified signal before inventory while preserving every frozen candidate entry.
    It 'InterT60_consumes_only_the_real_supervisor_signal_before_general_inventory' {
        $supervisor = Get-A031AuthoritySupervisorBinding
        $fixture = New-GeneralWrapperFixture -Root (Join-Path $TestDrive ([guid]::NewGuid().ToString('N')))
        $probePath = Join-Path $fixture.sourceOwnedRoot 'a031-general-inventory-probe.ps1'
        $observationPath = Join-Path $fixture.runRoot 'a031-general-inventory-observation.json'
        $probeText = @'
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string] $CandidateRoot,
    [Parameter(Mandatory)][string] $WrapperPath,
    [Parameter(Mandatory)][string] $CandidateRevision,
    [Parameter(Mandatory)][string] $ManifestPath,
    [Parameter(Mandatory)][string] $RetainedAdapterPath,
    [Parameter(Mandatory)][string] $ObservationPath
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$candidateFull = [IO.Path]::GetFullPath($CandidateRoot)
$comparison = if ($IsWindows) { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal }
$releaseValue = [Environment]::GetEnvironmentVariable('STANDARD_VALIDATION_BOOTSTRAP_RELEASE_PATH', 'Process')
$releasePath = if ([string]::IsNullOrWhiteSpace($releaseValue)) { '' } else { [IO.Path]::GetFullPath($releaseValue) }
$insideCandidate = -not [string]::IsNullOrWhiteSpace($releasePath) -and $releasePath.StartsWith($candidateFull.TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar, $comparison)
$signalExistsAtEntry = -not [string]::IsNullOrWhiteSpace($releasePath) -and (Test-Path -LiteralPath $releasePath -PathType Leaf)
$signalBytes = if ($signalExistsAtEntry) { [IO.File]::ReadAllBytes($releasePath) } else { [byte[]]@() }
$signalItem = if ($signalExistsAtEntry) { Get-Item -LiteralPath $releasePath -Force } else { $null }
$manifest = Get-Content -LiteralPath $ManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 40
$adapter = Get-Content -LiteralPath $RetainedAdapterPath -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 80
$generalCheck = @($adapter.checks | Where-Object { [string]$_.id -ceq 'repository-general' })
$actualInventory = @(Get-ChildItem -LiteralPath $candidateFull -File -Force -Recurse -ErrorAction Stop | Sort-Object -Property FullName -CaseSensitive | ForEach-Object {
    [pscustomobject]@{
        path = [IO.Path]::GetRelativePath($candidateFull, $_.FullName).Replace([IO.Path]::DirectorySeparatorChar, '/').Replace([IO.Path]::AltDirectorySeparatorChar, '/')
        sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        length = [int64]$_.Length
    }
})
$manifestEntries = @($manifest.entries | Sort-Object -Property path -CaseSensitive | ForEach-Object {
    [pscustomobject]@{ path = [string]$_.path; sha256 = [string]$_.sha256; mode = [string]$_.mode }
})
$manifestNames = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
foreach ($entry in $manifestEntries) { [void]$manifestNames.Add([string]$entry.path) }
$inventoryOnly = @($actualInventory | Where-Object { -not $manifestNames.Contains([string]$_.path) })
$actualByName = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::Ordinal)
foreach ($entry in $actualInventory) { $actualByName.Add([string]$entry.path, $entry) }
$manifestMissing = @($manifestEntries | Where-Object { -not $actualByName.ContainsKey([string]$_.path) })
$manifestHashMismatches = @($manifestEntries | Where-Object { $actualByName.ContainsKey([string]$_.path) -and [string]$actualByName[[string]$_.path].sha256 -cne [string]$_.sha256 })
$bootstrapCommand = [string][Environment]::GetEnvironmentVariable('STANDARD_VALIDATION_BOOTSTRAP_COMMAND', 'Process')
$wrapperExitCode = 0
$wrapperError = $null
try {
    & $WrapperPath -CandidateRevision $CandidateRevision
}
catch {
    $wrapperError = [string]$_.Exception.Message
    $wrapperExitCode = 1
}
$signalPresentAfterWrapper = -not [string]::IsNullOrWhiteSpace($releasePath) -and (Test-Path -LiteralPath $releasePath -PathType Leaf)
$observation = [ordered]@{
    candidateRoot = $candidateFull
    supervisorReleasePath = $releasePath
    supervisorReleasePathInsideCandidate = $insideCandidate
    supervisorReleaseNameMatches = [IO.Path]::GetFileName($releasePath) -cmatch '^b-[0-9a-f]{32}\.sig$'
    supervisorSignalPresentAtEntry = $signalExistsAtEntry
    supervisorSignalLengthBytes = [int64]$signalBytes.Length
    supervisorSignalHex = [Convert]::ToHexString($signalBytes).ToLowerInvariant()
    supervisorSignalBase64 = [Convert]::ToBase64String($signalBytes)
    supervisorSignalSha256 = ([Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($signalBytes))).ToLowerInvariant()
    supervisorSignalAttributes = if ($null -eq $signalItem) { $null } else { [string]$signalItem.Attributes }
    supervisorSignalIsReparsePoint = if ($null -eq $signalItem) { $null } else { [bool]($signalItem.Attributes -band [IO.FileAttributes]::ReparsePoint) }
    supervisorBootstrapCommand = $bootstrapCommand
    generalExecutable = if ($generalCheck.Count -eq 1) { [string]$generalCheck[0].executable } else { $null }
    generalExecutableSha256 = if ($generalCheck.Count -eq 1) { [string]$generalCheck[0].executableSha256 } else { $null }
    generalExecutableBindingMatchesSupervisor = $generalCheck.Count -eq 1 -and [string]$generalCheck[0].executable -ceq $bootstrapCommand -and (Get-FileHash -LiteralPath $bootstrapCommand -Algorithm SHA256).Hash.ToLowerInvariant() -ceq [string]$generalCheck[0].executableSha256
    frozenManifestCount = $manifestEntries.Count
    frozenManifestEntries = $manifestEntries
    beforeInventoryCount = $actualInventory.Count
    beforeInventory = $actualInventory
    beforeInventoryOnly = $inventoryOnly
    beforeInventoryMissing = $manifestMissing
    beforeInventoryHashMismatches = $manifestHashMismatches
    frozenManifestEntriesUnchanged = $manifestMissing.Count -eq 0 -and $manifestHashMismatches.Count -eq 0
    wrapperExitCode = $wrapperExitCode
    wrapperError = $wrapperError
    supervisorSignalPresentAfterWrapper = $signalPresentAfterWrapper
}
[IO.File]::WriteAllText($ObservationPath, (($observation | ConvertTo-Json -Depth 80 -Compress) + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))
if ($wrapperExitCode -ne 0) { [Console]::Error.WriteLine($wrapperError); exit $wrapperExitCode }
exit 0
'@
        [void](Write-SourceBindingFixtureFile -Path $probePath -Text $probeText)
        $arguments = @('-NoLogo', '-NoProfile', '-NonInteractive', '-File', $probePath,
            '-CandidateRoot', $fixture.candidateRoot, '-WrapperPath', $fixture.wrapperPath,
            '-CandidateRevision', $fixture.candidateRevision, '-ManifestPath', $fixture.manifestPath,
            '-RetainedAdapterPath', $fixture.retainedAdapterPath, '-ObservationPath', $observationPath)
        $environment = @{
            STANDARD_VALIDATION_CORE_RUN_ID = $fixture.runId
            STANDARD_VALIDATION_CORE_CHECK_ID = 'repository-general'
            STANDARD_VALIDATION_CORE_SKILLS = ($fixture.activeSkills -join ';')
        }
        $processResult = Invoke-A031TrustedSupervisedProcess -RunnerPath $supervisor.path `
            -PowerShellPath $fixture.powerShellPath -Arguments $arguments -WorkingDirectory $fixture.candidateRoot `
            -Environment $environment -CandidateRoot $fixture.candidateRoot -AdapterPath $fixture.adapterPath `
            -ArtifactsRoot $fixture.artifactRoot -Revision $fixture.candidateRevision
        $observation = Get-Content -LiteralPath $observationPath -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 80
        $manifestRaw = [IO.File]::ReadAllBytes($fixture.manifestPath)
        $manifestEntries = @($observation.frozenManifestEntries)
        $inventoryExtra = @($observation.beforeInventoryOnly)
        $observedSignalBytes = [Convert]::FromBase64String([string]$observation.supervisorSignalBase64)
        $expectedSignalBytes = [Text.UTF8Encoding]::new($false).GetBytes('release' + [Environment]::NewLine)
        $expectedSignalHex = [Convert]::ToHexString($expectedSignalBytes).ToLowerInvariant()
        $evidence = [ordered]@{
            scenario = 'supervisor-owned bootstrap release signal during general candidate inventory'
            authorityRunner = $supervisor
            candidateRevision = $fixture.candidateRevision
            runId = $fixture.runId
            candidateRoot = $fixture.candidateRoot
            adapterPath = $fixture.retainedAdapterPath
            adapterSha256 = Get-SourceBindingFixtureHash -Path $fixture.retainedAdapterPath
            generalExecutablePath = $fixture.powerShellPath
            generalExecutableSha256 = $fixture.powerShellSha256
            protectedWrapperPath = $fixture.wrapperPath
            protectedWrapperSha256 = Get-SourceBindingFixtureHash -Path $fixture.wrapperPath
            modeManifestPath = $fixture.manifestPath
            modeManifestSha256 = Get-SourceBindingFixtureHash -Path $fixture.manifestPath
            modeManifestRawBytes = $manifestRaw.Length
            modeManifestRawSha256 = (Get-FileHash -LiteralPath $fixture.manifestPath -Algorithm SHA256).Hash.ToLowerInvariant()
            frozenManifestCount = $manifestEntries.Count
            frozenManifestEntries = $manifestEntries
            beforeInventoryCount = [int]$observation.beforeInventoryCount
            beforeInventory = @($observation.beforeInventory)
            beforeInventoryOnly = $inventoryExtra
            beforeInventoryMissing = @($observation.beforeInventoryMissing)
            beforeInventoryHashMismatches = @($observation.beforeInventoryHashMismatches)
            frozenManifestEntriesUnchanged = [bool]$observation.frozenManifestEntriesUnchanged
            expectedSupervisorSignalHex = $expectedSignalHex
            observedSupervisorSignalLengthBytes = $observedSignalBytes.Length
            observedSupervisorSignalSha256 = ([Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($observedSignalBytes))).ToLowerInvariant()
            observedSupervisorSignalEqualsExpected = [Convert]::ToHexString($observedSignalBytes) -ceq [Convert]::ToHexString($expectedSignalBytes)
            supervisorStreamsEvidenceEncoding = 'UTF-8 no-BOM re-encoding of the trusted supervisor returned stdout/stderr text; these are not original child byte streams.'
            probePath = $probePath
            probeSha256 = Get-SourceBindingFixtureHash -Path $probePath
            observationPath = $observationPath
            observation = $observation
            supervisorResult = $processResult
        }
        $observedGenuineRed = [int]$observation.frozenManifestCount -gt 0 -and
            [int]$observation.beforeInventoryCount -eq [int]$observation.frozenManifestCount + 1 -and @($inventoryExtra).Count -eq 1 -and
            [string]$inventoryExtra[0].path -ceq [string]$observation.supervisorReleasePath.Substring($fixture.candidateRoot.Length + 1).Replace([IO.Path]::DirectorySeparatorChar, '/') -and
            [bool]$observation.supervisorSignalPresentAtEntry -and [int64]$observation.supervisorSignalLengthBytes -eq $expectedSignalBytes.Length -and
            [string]$observation.supervisorSignalHex -ceq $expectedSignalHex -and [bool]$observation.frozenManifestEntriesUnchanged -and
            [bool]$observation.supervisorReleasePathInsideCandidate -and [bool]$observation.supervisorReleaseNameMatches -and
            [bool]$observation.generalExecutableBindingMatchesSupervisor -and
            [string]$observation.wrapperError -match 'Candidate snapshot inventory differs from the protected Git entry mode manifest\.' -and
            [bool]$observation.supervisorSignalPresentAfterWrapper -and
            [string]$processResult.status -ceq 'failed' -and [int]$processResult.exitCode -ne 0 -and
            [bool]$processResult.cleanedUp -and -not [bool]$processResult.outputQuotaExceeded
        $intendedGreen = [int]$observation.frozenManifestCount -gt 0 -and
            [bool]$observation.frozenManifestEntriesUnchanged -and [bool]$observation.supervisorSignalPresentAtEntry -and
            [int64]$observation.supervisorSignalLengthBytes -eq $expectedSignalBytes.Length -and [string]$observation.supervisorSignalHex -ceq $expectedSignalHex -and
            -not [bool]$observation.supervisorSignalPresentAfterWrapper -and [int]$observation.wrapperExitCode -eq 0 -and
            [string]$processResult.status -ceq 'passed' -and [int]$processResult.exitCode -eq 0 -and
            [bool]$processResult.cleanedUp -and -not [bool]$processResult.outputQuotaExceeded
        $evidence.observedGenuineRed = [bool]$observedGenuineRed
        $evidence.intendedGreenObserved = [bool]$intendedGreen
        $releaseRelativePath = [string]$observation.supervisorReleasePath.Substring($fixture.candidateRoot.Length + 1).Replace([IO.Path]::DirectorySeparatorChar, '/')
        $preserved = [ordered]@{}
        $preserved.candidateInventory = Save-A031CandidateEvidenceTree -EvidenceSubdirectory 'general-candidate-at-wrapper-entry' `
            -CandidateRoot $fixture.candidateRoot -ManifestEntries $manifestEntries -SignalRelativePath $releaseRelativePath -SignalBytes $observedSignalBytes
        $preserved.manifest = Save-A031EvidenceFile -Name 'general-mode-manifest.json' -SourcePath $fixture.manifestPath
        $preserved.retainedAdapter = Save-A031EvidenceFile -Name 'general-retained-adapter.json' -SourcePath $fixture.retainedAdapterPath
        $preserved.adapterInput = Save-A031EvidenceFile -Name 'general-adapter-input.json' -SourcePath $fixture.adapterPath
        $preserved.probe = Save-A031EvidenceFile -Name 'general-probe.ps1' -SourcePath $probePath
        $preserved.observation = Save-A031EvidenceFile -Name 'general-observation.json' -SourcePath $observationPath
        $preserved.signalBytes = Save-A031EvidenceBytes -Name 'general-observed-release-signal.bin' -Bytes $observedSignalBytes
        $preserved.supervisorStdout = Save-A031EvidenceBytes -Name 'general-supervisor-stdout-utf8-reencoded.txt' -Bytes ([Text.UTF8Encoding]::new($false).GetBytes([string]$processResult.stdout))
        $preserved.supervisorStderr = Save-A031EvidenceBytes -Name 'general-supervisor-stderr-utf8-reencoded.txt' -Bytes ([Text.UTF8Encoding]::new($false).GetBytes([string]$processResult.stderr))
        $evidence.preservedFiles = $preserved
        [void](Save-A031EvidenceJson -Name 'general-supervisor-red.json' -Value $evidence)
        $intendedGreen | Should -BeTrue -Because 'the general wrapper must consume that verified signal before binding the full frozen candidate inventory'
    }

    # Scenario: the source-only relay writes a nested emitter's merged diagnostic to a run-owned sidecar and prints a bounded summary.
    # Purpose: execute the actual capture, exit-code, sidecar-writer and summary AST under the trusted supervisor without exceeding its quota.
    It 'InterT61_bounds_the_exact_source_runner_output_relay_under_the_trusted_supervisor' {
        $supervisor = Get-A031AuthoritySupervisorBinding
        $fixture = New-GeneralWrapperFixture -Root (Join-Path $TestDrive ([guid]::NewGuid().ToString('N')))
        $validatePath = Join-Path $script:RepositoryRoot 'scripts/Validate.ps1'
        $tokens = $null
        $parseErrors = $null
        $validateAst = [System.Management.Automation.Language.Parser]::ParseFile($validatePath, [ref]$tokens, [ref]$parseErrors)
        if (@($parseErrors).Count -gt 0) { throw ('Validate.ps1 did not parse for the A031 output relay: ' + (@($parseErrors | ForEach-Object { $_.Message }) -join '; ')) }
        $sourceFunction = $validateAst.Find({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq 'Invoke-CodeSourceValidation' }, $true)
        if ($null -eq $sourceFunction) { throw 'Invoke-CodeSourceValidation is missing from the exact candidate Validate.ps1.' }
        $captureStatements = @($sourceFunction.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.AssignmentStatementAst] -and $node.Extent.Text -match '^\s*\$runnerOutput\s*=\s*@\(&\s*\$powerShell\b'
        }, $true))
        $exitStatements = @($sourceFunction.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.AssignmentStatementAst] -and $node.Extent.Text -match '^\s*\$processExitCode\s*=\s*\$LASTEXITCODE\s*$'
        }, $true))
        $diagnosticTextStatements = @($sourceFunction.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.AssignmentStatementAst] -and $node.Extent.Text -match '^\s*\$runnerDiagnosticText\s*='
        }, $true))
        $diagnosticWriteStatements = @($sourceFunction.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.AssignmentStatementAst] -and $node.Extent.Text -match '^\s*\$runnerDiagnostic\s*=\s*Write-CodeSourceRunnerOutputDiagnostic\b'
        }, $true))
        $summaryStatements = @($sourceFunction.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.PipelineAst] -and $node.Extent.Text -match '^\s*\[Console\]::Out\.WriteLine\(\("Source runner diagnostic retained:'
        }, $true))
        $writerAst = $validateAst.Find({
            param($node)
            $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq 'Write-CodeSourceRunnerOutputDiagnostic'
        }, $true)
        if ($captureStatements.Count -ne 1 -or $exitStatements.Count -ne 1 -or $diagnosticTextStatements.Count -ne 1 -or
            $diagnosticWriteStatements.Count -ne 1 -or $summaryStatements.Count -ne 1 -or $null -eq $writerAst) {
            throw 'The candidate source runner capture, exit preservation, diagnostic write, writer function, or bounded summary AST is not unique.'
        }
        $astRecords = @(
            [pscustomobject]@{ role = 'runner-output-capture'; startLine = $captureStatements[0].Extent.StartLineNumber; endLine = $captureStatements[0].Extent.EndLineNumber; rawText = $captureStatements[0].Extent.Text; sha256 = Get-A031TextSha256 -Value $captureStatements[0].Extent.Text }
            [pscustomobject]@{ role = 'runner-exit-code'; startLine = $exitStatements[0].Extent.StartLineNumber; endLine = $exitStatements[0].Extent.EndLineNumber; rawText = $exitStatements[0].Extent.Text; sha256 = Get-A031TextSha256 -Value $exitStatements[0].Extent.Text }
            [pscustomobject]@{ role = 'runner-diagnostic-text'; startLine = $diagnosticTextStatements[0].Extent.StartLineNumber; endLine = $diagnosticTextStatements[0].Extent.EndLineNumber; rawText = $diagnosticTextStatements[0].Extent.Text; sha256 = Get-A031TextSha256 -Value $diagnosticTextStatements[0].Extent.Text }
            [pscustomobject]@{ role = 'runner-diagnostic-write'; startLine = $diagnosticWriteStatements[0].Extent.StartLineNumber; endLine = $diagnosticWriteStatements[0].Extent.EndLineNumber; rawText = $diagnosticWriteStatements[0].Extent.Text; sha256 = Get-A031TextSha256 -Value $diagnosticWriteStatements[0].Extent.Text }
            [pscustomobject]@{ role = 'runner-diagnostic-summary'; startLine = $summaryStatements[0].Extent.StartLineNumber; endLine = $summaryStatements[0].Extent.EndLineNumber; rawText = $summaryStatements[0].Extent.Text; sha256 = Get-A031TextSha256 -Value $summaryStatements[0].Extent.Text }
            [pscustomobject]@{ role = 'runner-diagnostic-writer-function'; startLine = $writerAst.Extent.StartLineNumber; endLine = $writerAst.Extent.EndLineNumber; rawText = $writerAst.Extent.Text; sha256 = Get-A031TextSha256 -Value $writerAst.Extent.Text }
        )
        $payloadLength = 2097152
        $emitterRoot = Join-Path $fixture.sourceOwnedRoot 'a031-output-emitter'
        [void](New-Item -ItemType Directory -Path $emitterRoot -Force)
        $payloadPath = Join-Path $emitterRoot 'emitter-payload.bin'
        $payloadBytes = [byte[]]::new($payloadLength)
        [Array]::Fill($payloadBytes, [byte]0x41)
        [IO.File]::WriteAllBytes($payloadPath, $payloadBytes)
        $emitterPath = Join-Path $emitterRoot 'emit-output.ps1'
        $emitterText = @'
[CmdletBinding()]
param([Parameter(Mandatory)][string] $PayloadPath)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$payload = [IO.File]::ReadAllText($PayloadPath, [Text.Encoding]::ASCII)
Write-Output $payload
exit 0
'@
        [void](Write-SourceBindingFixtureFile -Path $emitterPath -Text $emitterText)
        $relayTargetPath = Join-Path $emitterRoot 'execute-source-relay.ps1'
        $captureReceiptPath = Join-Path $emitterRoot 'capture-receipt.json'
        $relayParts = @(
            '[CmdletBinding()]'
            'param([Parameter(Mandatory)][string] $PowerShellPath, [Parameter(Mandatory)][string] $EmitterPath, [Parameter(Mandatory)][string] $PayloadPath, [Parameter(Mandatory)][string] $RunRoot, [Parameter(Mandatory)][string] $CandidateRoot, [Parameter(Mandatory)][string] $AuthorityRoot, [Parameter(Mandatory)][string] $CaptureReceiptPath)'
            'Set-StrictMode -Version Latest'
            '$ErrorActionPreference = ''Stop'''
            $writerAst.Extent.Text
            '$powerShell = [IO.Path]::GetFullPath($PowerShellPath)'
            '$centralRunner = [IO.Path]::GetFullPath($EmitterPath)'
            '$arguments = @(''-PayloadPath'', [IO.Path]::GetFullPath($PayloadPath))'
            '$paths = [pscustomobject]@{ artifactsRoot = [IO.Path]::GetFullPath($RunRoot) }'
            '$RepositoryRoot = [IO.Path]::GetFullPath($CandidateRoot)'
            '$authority = [pscustomobject]@{ root = [IO.Path]::GetFullPath($AuthorityRoot) }'
            $captureStatements[0].Extent.Text
            $exitStatements[0].Extent.Text
            $diagnosticTextStatements[0].Extent.Text
            $diagnosticWriteStatements[0].Extent.Text
            $summaryStatements[0].Extent.Text
            '$captureReceipt = [ordered]@{ outputCharacters = $runnerDiagnostic.characterCount; outputBytes = $runnerDiagnostic.byteLength; outputSha256 = $runnerDiagnostic.sha256; processExitCode = [int]$runnerDiagnostic.processExitCode; sidecarPath = [IO.Path]::GetFullPath($runnerDiagnostic.path); payloadPath = [IO.Path]::GetFullPath($PayloadPath) }'
            '[IO.File]::WriteAllText($CaptureReceiptPath, (($captureReceipt | ConvertTo-Json -Depth 20 -Compress) + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))'
            'exit 0'
        )
        $relayTargetText = [string]::Join([Environment]::NewLine, [string[]]$relayParts) + [Environment]::NewLine
        [void](Write-SourceBindingFixtureFile -Path $relayTargetPath -Text $relayTargetText)
        $diagnosticRunRoot = Join-Path (Split-Path -Parent $fixture.sourceOwnedRoot) "a031-relay-run-$([guid]::NewGuid().ToString('N'))"
        [void](New-Item -ItemType Directory -Path $diagnosticRunRoot -ErrorAction Stop)
        $relayArguments = @('-NoLogo', '-NoProfile', '-NonInteractive', '-File', $relayTargetPath,
            '-PowerShellPath', $fixture.powerShellPath, '-EmitterPath', $emitterPath,
            '-PayloadPath', $payloadPath, '-RunRoot', $diagnosticRunRoot, '-CandidateRoot', $fixture.candidateRoot,
            '-AuthorityRoot', $supervisor.root, '-CaptureReceiptPath', $captureReceiptPath)
        $processResult = Invoke-A031TrustedSupervisedProcess -RunnerPath $supervisor.path `
            -PowerShellPath $fixture.powerShellPath -Arguments $relayArguments -WorkingDirectory $emitterRoot `
            -Environment @{} -CandidateRoot $fixture.candidateRoot -AdapterPath $fixture.adapterPath `
            -ArtifactsRoot $fixture.artifactRoot -Revision $fixture.candidateRevision
        $captureReceipt = Get-Content -LiteralPath $captureReceiptPath -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 30
        $capturePath = [IO.Path]::GetFullPath([string]$captureReceipt.sidecarPath)
        $capturedRaw = [IO.File]::ReadAllBytes($capturePath)
        $payloadRaw = [IO.File]::ReadAllBytes($payloadPath)
        $payloadSha256 = (Get-FileHash -LiteralPath $payloadPath -Algorithm SHA256).Hash.ToLowerInvariant()
        $evidence = [ordered]@{
            scenario = 'actual candidate source capture, CreateNew diagnostic sidecar writer and bounded summary under the trusted supervisor fixture'
            authorityRunner = $supervisor
            supervisorStreamsEvidenceEncoding = 'UTF-8 no-BOM re-encoding of the trusted supervisor returned stdout/stderr text; these are not original child byte streams.'
            candidateRevision = $fixture.candidateRevision
            runnerPath = $validatePath
            runnerSha256 = Get-SourceBindingFixtureHash -Path $validatePath
            astStatements = $astRecords
            emitterPath = $emitterPath
            emitterSha256 = Get-SourceBindingFixtureHash -Path $emitterPath
            emitterPayloadPath = $payloadPath
            emitterPayloadBytes = [IO.FileInfo]::new($payloadPath).Length
            emitterPayloadSha256 = $payloadSha256
            targetPath = $relayTargetPath
            targetSha256 = Get-SourceBindingFixtureHash -Path $relayTargetPath
            capturedDiagnosticPath = $capturePath
            capturedDiagnosticBytes = $capturedRaw.Length
            capturedDiagnosticSha256 = (Get-FileHash -LiteralPath $capturePath -Algorithm SHA256).Hash.ToLowerInvariant()
            capturedBytesExactlyMatchEmitterPayload = [Linq.Enumerable]::SequenceEqual[byte]($capturedRaw, $payloadRaw)
            captureReceipt = $captureReceipt
            supervisorResult = $processResult
        }
        $correctDiagnosticCaptured = [int64]$captureReceipt.outputBytes -ge 2097152 -and
            [string]$captureReceipt.outputSha256 -ceq $payloadSha256 -and [int]$captureReceipt.processExitCode -eq 0 -and
            [Linq.Enumerable]::SequenceEqual[byte]($capturedRaw, $payloadRaw)
        $observedQuotaRed = [bool]$processResult.outputQuotaExceeded -and
            [string]$processResult.status -ceq 'failed' -and [int]$processResult.exitCode -ne 0 -and
            [bool]$processResult.cleanedUp
        $intendedGreen = -not [bool]$processResult.outputQuotaExceeded -and
            [string]$processResult.status -ceq 'passed' -and [int]$processResult.exitCode -eq 0 -and
            [bool]$processResult.cleanedUp
        $evidence.correctDiagnosticCaptured = [bool]$correctDiagnosticCaptured
        $evidence.observedQuotaRed = [bool]$observedQuotaRed
        $evidence.intendedGreenObserved = [bool]$intendedGreen
        $fixtureManifest = Get-Content -LiteralPath $fixture.manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 30
        $preserved = [ordered]@{}
        $preserved.candidateSnapshot = Save-A031CandidateEvidenceTree -EvidenceSubdirectory 'output-candidate-snapshot' `
            -CandidateRoot $fixture.candidateRoot -ManifestEntries @($fixtureManifest.entries)
        $preserved.validateSource = Save-A031EvidenceFile -Name 'output-Validate.ps1' -SourcePath $validatePath
        $preserved.emitter = Save-A031EvidenceFile -Name 'output-emitter.ps1' -SourcePath $emitterPath
        $preserved.payload = Save-A031EvidenceFile -Name 'output-payload.bin' -SourcePath $payloadPath
        $preserved.relayTarget = Save-A031EvidenceFile -Name 'output-relay-target.ps1' -SourcePath $relayTargetPath
        $preserved.capturedDiagnostic = Save-A031EvidenceFile -Name 'output-captured-diagnostic.txt' -SourcePath $capturePath
        $preserved.captureReceipt = Save-A031EvidenceFile -Name 'output-capture-receipt.json' -SourcePath $captureReceiptPath
        $preserved.supervisorStdout = Save-A031EvidenceBytes -Name 'output-supervisor-stdout-utf8-reencoded.txt' -Bytes ([Text.UTF8Encoding]::new($false).GetBytes([string]$processResult.stdout))
        $preserved.supervisorStderr = Save-A031EvidenceBytes -Name 'output-supervisor-stderr-utf8-reencoded.txt' -Bytes ([Text.UTF8Encoding]::new($false).GetBytes([string]$processResult.stderr))
        for ($astIndex = 0; $astIndex -lt $astRecords.Count; $astIndex++) {
            $astRecord = $astRecords[$astIndex]
            $preserved[$astRecord.role] = Save-A031EvidenceBytes -Name ("output-ast-{0}.ps1" -f $astRecord.role) `
                -Bytes ([Text.UTF8Encoding]::new($false).GetBytes([string]$astRecord.rawText))
        }
        $evidence.preservedFiles = $preserved
        [void](Save-A031EvidenceJson -Name 'output-relay-supervisor-red.json' -Value $evidence)
        $correctDiagnosticCaptured | Should -BeTrue -Because 'the current merged output capture must retain the full exact 2 MiB diagnostic before relay'
        $intendedGreen | Should -BeTrue -Because 'the source-only relay must keep the exact supervisor output below its quota'
    }

    # Scenario: the trusted process supervisor must preserve a failing child's exit code and cleanup result on small diagnostic output.
    # Purpose: keep non-zero status and cleanup semantics stable while the source relay moves diagnostic bytes to a sidecar.
    It 'InterT62_preserves_nonzero_trusted_child_exit_and_cleanup' {
        $supervisor = Get-A031AuthoritySupervisorBinding
        $fixture = New-GeneralWrapperFixture -Root (Join-Path $TestDrive ([guid]::NewGuid().ToString('N')))
        $exitPath = Join-Path $fixture.sourceOwnedRoot 'a031-exit-child.ps1'
        $exitText = "[Console]::Out.WriteLine('A031 owned child exit probe')`nexit 23`n"
        [void](Write-SourceBindingFixtureFile -Path $exitPath -Text $exitText)
        $processResult = Invoke-A031TrustedSupervisedProcess -RunnerPath $supervisor.path `
            -PowerShellPath $fixture.powerShellPath -Arguments @('-NoLogo', '-NoProfile', '-NonInteractive', '-File', $exitPath) `
            -WorkingDirectory $fixture.sourceOwnedRoot -Environment @{} -CandidateRoot $fixture.candidateRoot `
            -AdapterPath $fixture.adapterPath -ArtifactsRoot $fixture.artifactRoot -Revision $fixture.candidateRevision
        [void](Save-A031EvidenceJson -Name 'nonzero-child-supervisor.json' -Value ([ordered]@{ authorityRunner = $supervisor; childPath = $exitPath; childSha256 = Get-SourceBindingFixtureHash -Path $exitPath; supervisorResult = $processResult }))
        [int]$processResult.exitCode | Should -Be 23
        [bool]$processResult.cleanedUp | Should -BeTrue
        [bool]$processResult.outputQuotaExceeded | Should -BeFalse
    }

    # Scenario: the candidate source-only diagnostic writer retains complete diagnostic text and the child exit code.
    # Purpose: verify the private sidecar contract with a multi-megabyte payload and readback hash.
    It 'InterT63_retains_large_source_diagnostic_bytes_and_nonzero_child_exit' {
        $validatePath = Join-Path $script:RepositoryRoot 'scripts/Validate.ps1'
        $tokens = $null
        $parseErrors = $null
        $validateAst = [System.Management.Automation.Language.Parser]::ParseFile($validatePath, [ref]$tokens, [ref]$parseErrors)
        if (@($parseErrors).Count -gt 0) { throw ('Validate.ps1 did not parse for the A031 diagnostic writer: ' + (@($parseErrors | ForEach-Object { $_.Message }) -join '; ')) }
        $writerAst = $validateAst.Find({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq 'Write-CodeSourceRunnerOutputDiagnostic' }, $true)
        if ($null -eq $writerAst) {
            $false | Should -BeTrue -Because 'Invoke-CodeSourceValidation must expose its private run-owned diagnostic sidecar writer'
            return
        }
        . ([scriptblock]::Create($writerAst.Extent.Text))

        $fixture = New-GeneralWrapperFixture -Root (Join-Path $TestDrive ([guid]::NewGuid().ToString('N')))
        $supervisor = Get-A031AuthoritySupervisorBinding
        $diagnostic = ('A' * 2097152) + "`r`nfull diagnostic tail Ω"
        $expectedBytes = [Text.UTF8Encoding]::new($false).GetBytes($diagnostic)
        $diagnosticRunRoot = Join-Path (Split-Path -Parent $fixture.sourceOwnedRoot) "a031-writer-run-$([guid]::NewGuid().ToString('N'))"
        [void](New-Item -ItemType Directory -Path $diagnosticRunRoot -ErrorAction Stop)
        $result = Write-CodeSourceRunnerOutputDiagnostic -OutputText $diagnostic -RunRoot $diagnosticRunRoot `
            -CandidateRoot $fixture.candidateRoot -AuthorityRoot $supervisor.root -ProcessExitCode 23
        $sidecarPath = [IO.Path]::GetFullPath([string]$result.path)
        $actualBytes = [IO.File]::ReadAllBytes($sidecarPath)
        $actualText = [Text.UTF8Encoding]::new($false).GetString($actualBytes)
        $expectedHash = ([Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($expectedBytes))).ToLowerInvariant()
        $actualHash = (Get-FileHash -LiteralPath $sidecarPath -Algorithm SHA256).Hash.ToLowerInvariant()
        $result.path | Should -Not -BeNullOrEmpty
        $actualText | Should -BeExactly $diagnostic
        $actualHash | Should -Be $expectedHash
        [string]$result.sha256 | Should -Be $expectedHash
        [int64]$result.characterCount | Should -Be $diagnostic.Length
        [int64]$result.byteLength | Should -Be $expectedBytes.Length
        [int]$result.processExitCode | Should -Be 23
        $sidecarPath.StartsWith($fixture.candidateRoot.TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase) | Should -BeFalse
        $sidecarPath.StartsWith($supervisor.root.TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase) | Should -BeFalse

        $preserved = [ordered]@{
            validateSource = Save-A031EvidenceFile -Name 'writer-Validate.ps1' -SourcePath $validatePath
            sidecar = Save-A031EvidenceFile -Name 'writer-large-sidecar.txt' -SourcePath $sidecarPath
        }
        $writerEvidence = [ordered]@{
            authorityRunner = $supervisor; writerAst = $writerAst.Extent.Text; writerAstSha256 = Get-A031TextSha256 -Value $writerAst.Extent.Text
            diagnosticCharacters = $diagnostic.Length; diagnosticBytes = $expectedBytes.Length; diagnosticSha256 = $expectedHash
            result = $result; sidecarActualSha256 = $actualHash; preservedFiles = $preserved
        }
        [void](Save-A031EvidenceJson -Name 'diagnostic-writer-roundtrip.json' -Value $writerEvidence)
    }

    # Scenario: the private diagnostic writer must fail closed when its destination overlaps the candidate or authority, uses a file, or follows a reparse point.
    # Purpose: ensure private sidecar retention cannot become candidate input, protected authority content, or an escaped write.
    It 'InterT64_rejects_unsafe_diagnostic_writer_destinations' {
        $validatePath = Join-Path $script:RepositoryRoot 'scripts/Validate.ps1'
        $tokens = $null
        $parseErrors = $null
        $validateAst = [System.Management.Automation.Language.Parser]::ParseFile($validatePath, [ref]$tokens, [ref]$parseErrors)
        if (@($parseErrors).Count -gt 0) { throw ('Validate.ps1 did not parse for the A031 diagnostic writer guards: ' + (@($parseErrors | ForEach-Object { $_.Message }) -join '; ')) }
        $writerAst = $validateAst.Find({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq 'Write-CodeSourceRunnerOutputDiagnostic' }, $true)
        if ($null -eq $writerAst) {
            $false | Should -BeTrue -Because 'Invoke-CodeSourceValidation must expose its private run-owned diagnostic sidecar writer'
            return
        }
        . ([scriptblock]::Create($writerAst.Extent.Text))
        $fixture = New-GeneralWrapperFixture -Root (Join-Path $TestDrive ([guid]::NewGuid().ToString('N')))
        $authorityRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        [void](New-Item -ItemType Directory -Path $authorityRoot)
        $candidateOverlapRoot = Join-Path $fixture.candidateRoot 'a031-unsafe-output-root'
        [void](New-Item -ItemType Directory -Path $candidateOverlapRoot)
        { Write-CodeSourceRunnerOutputDiagnostic -OutputText 'x' -RunRoot $candidateOverlapRoot -CandidateRoot $fixture.candidateRoot -AuthorityRoot $authorityRoot -ProcessExitCode 0 } | Should -Throw
        { Write-CodeSourceRunnerOutputDiagnostic -OutputText 'x' -RunRoot $authorityRoot -CandidateRoot $fixture.candidateRoot -AuthorityRoot $authorityRoot -ProcessExitCode 0 } | Should -Throw

        $existingRunRootFile = Join-Path $fixture.sourceOwnedRoot 'a031-existing-output-root.bin'
        [IO.File]::WriteAllBytes($existingRunRootFile, [byte[]](0x41, 0x42, 0x43))
        $existingHash = (Get-FileHash -LiteralPath $existingRunRootFile -Algorithm SHA256).Hash
        { Write-CodeSourceRunnerOutputDiagnostic -OutputText 'x' -RunRoot $existingRunRootFile -CandidateRoot $fixture.candidateRoot -AuthorityRoot $authorityRoot -ProcessExitCode 0 } | Should -Throw
        (Get-FileHash -LiteralPath $existingRunRootFile -Algorithm SHA256).Hash | Should -Be $existingHash

        $relativeRunRoot = "a031-relative-diagnostic-run-$([guid]::NewGuid().ToString('N'))"
        $relativeCandidateRoot = "a031-relative-diagnostic-candidate-$([guid]::NewGuid().ToString('N'))"
        $relativeAuthorityRoot = "a031-relative-diagnostic-authority-$([guid]::NewGuid().ToString('N'))"
        $relativeProbePath = Join-Path $fixture.sourceOwnedRoot 'a031-relative-root-guard-probe.bin'
        [byte[]]$relativeProbeBytes = 0x41, 0x30, 0x33, 0x31
        [IO.File]::WriteAllBytes($relativeProbePath, $relativeProbeBytes)
        $relativeProbeHash = Get-SourceBindingFixtureHash -Path $relativeProbePath
        { Write-CodeSourceRunnerOutputDiagnostic -OutputText 'x' -RunRoot $relativeRunRoot -CandidateRoot $fixture.candidateRoot -AuthorityRoot $authorityRoot -ProcessExitCode 0 } | Should -Throw '*fully qualified absolute paths*'
        { Write-CodeSourceRunnerOutputDiagnostic -OutputText 'x' -RunRoot $fixture.runRoot -CandidateRoot $relativeCandidateRoot -AuthorityRoot $authorityRoot -ProcessExitCode 0 } | Should -Throw '*fully qualified absolute paths*'
        { Write-CodeSourceRunnerOutputDiagnostic -OutputText 'x' -RunRoot $fixture.runRoot -CandidateRoot $fixture.candidateRoot -AuthorityRoot $relativeAuthorityRoot -ProcessExitCode 0 } | Should -Throw '*fully qualified absolute paths*'
        (Get-SourceBindingFixtureHash -Path $relativeProbePath) | Should -Be $relativeProbeHash
        (Test-Path -LiteralPath $relativeRunRoot) | Should -BeFalse
        (Test-Path -LiteralPath $relativeCandidateRoot) | Should -BeFalse
        (Test-Path -LiteralPath $relativeAuthorityRoot) | Should -BeFalse

        $junctionTarget = Join-Path $fixture.sourceOwnedRoot 'a031-junction-target'
        $junctionRunRoot = Join-Path $fixture.sourceOwnedRoot 'a031-junction-run-root'
        [void](New-Item -ItemType Directory -Path $junctionTarget -ErrorAction Stop)
        $linkType = if ($IsWindows) { 'Junction' } else { 'SymbolicLink' }
        try {
            [void](New-Item -ItemType $linkType -Path $junctionRunRoot -Target $junctionTarget -ErrorAction Stop)
            $linkItem = Get-Item -LiteralPath $junctionRunRoot -Force -ErrorAction Stop
            (($linkItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) | Should -BeTrue
            { Write-CodeSourceRunnerOutputDiagnostic -OutputText 'x' -RunRoot $junctionRunRoot -CandidateRoot $fixture.candidateRoot -AuthorityRoot $authorityRoot -ProcessExitCode 0 } | Should -Throw '*reparse ancestor*'
            @(Get-ChildItem -LiteralPath $junctionTarget -Force).Count | Should -Be 0
        }
        finally {
            if (Test-Path -LiteralPath $junctionRunRoot) { Remove-Item -LiteralPath $junctionRunRoot -Force -ErrorAction Stop }
            if (Test-Path -LiteralPath $junctionTarget) { Remove-Item -LiteralPath $junctionTarget -Force -Recurse -ErrorAction Stop }
        }
        (Test-Path -LiteralPath $junctionRunRoot) | Should -BeFalse
        (Test-Path -LiteralPath $junctionTarget) | Should -BeFalse
    }

    # Scenario: the general wrapper receives an invalid frozen cleanup binding or a path already committed in the candidate manifest.
    # Purpose: keep cleanup fail-closed for module path/hash, general executable hash, and tracked-file identity.
    It 'InterT65_general_cleanup_bindings_and_tracked_path_fail_closed' {
        function Write-A031GeneralAdapterCopies {
            param([Parameter(Mandatory)] $Fixture, [Parameter(Mandatory)] $Adapter)
            $text = ($Adapter | ConvertTo-Json -Depth 80 -Compress) + [Environment]::NewLine
            $roundTrip = $text | ConvertFrom-Json -Depth 80
            $roundTripManifestCount = @($roundTrip.sourceValidation.frozenFiles | Where-Object {
                [IO.Path]::GetFileName([string]$_.path) -ceq 'candidate-git-entry-modes.json'
            }).Count
            if ($roundTripManifestCount -ne 1) { throw "A031 test adapter serialization lost the candidate manifest binding (count $roundTripManifestCount)." }
            [IO.File]::WriteAllText($Fixture.retainedAdapterPath, $text, [Text.UTF8Encoding]::new($false))
            [IO.File]::WriteAllText($Fixture.adapterPath, $text, [Text.UTF8Encoding]::new($false))
        }

        function Invoke-A031GeneralWrapperProbe {
            param([Parameter(Mandatory)] $Fixture, [string] $ReleasePath, [string] $BootstrapCommand)
            $environmentNames = @('STANDARD_VALIDATION_CORE_RUN_ID', 'STANDARD_VALIDATION_CORE_CHECK_ID',
                'STANDARD_VALIDATION_CORE_SKILLS', 'STANDARD_VALIDATION_BOOTSTRAP_RELEASE_PATH', 'STANDARD_VALIDATION_BOOTSTRAP_COMMAND')
            $previousEnvironment = @{}
            foreach ($name in $environmentNames) { $previousEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, 'Process') }
            $stdoutPath = Join-Path $Fixture.sourceOwnedRoot 'a031-general-guard.stdout.txt'
            $stderrPath = Join-Path $Fixture.sourceOwnedRoot 'a031-general-guard.stderr.txt'
            try {
                [Environment]::SetEnvironmentVariable('STANDARD_VALIDATION_CORE_RUN_ID', $Fixture.runId, 'Process')
                [Environment]::SetEnvironmentVariable('STANDARD_VALIDATION_CORE_CHECK_ID', 'repository-general', 'Process')
                [Environment]::SetEnvironmentVariable('STANDARD_VALIDATION_CORE_SKILLS', ($Fixture.activeSkills -join ';'), 'Process')
                [Environment]::SetEnvironmentVariable('STANDARD_VALIDATION_BOOTSTRAP_RELEASE_PATH', $ReleasePath, 'Process')
                [Environment]::SetEnvironmentVariable('STANDARD_VALIDATION_BOOTSTRAP_COMMAND', $BootstrapCommand, 'Process')
                Push-Location -LiteralPath $Fixture.candidateRoot
                try {
                    & $Fixture.powerShellPath -NoLogo -NoProfile -NonInteractive -File $Fixture.wrapperPath `
                        -CandidateRevision $Fixture.candidateRevision 1> $stdoutPath 2> $stderrPath
                    $exitCode = $LASTEXITCODE
                }
                finally { Pop-Location }
            }
            finally {
                foreach ($name in $environmentNames) { [Environment]::SetEnvironmentVariable($name, $previousEnvironment[$name], 'Process') }
            }
            $stdout = if (Test-Path -LiteralPath $stdoutPath) { Get-Content -LiteralPath $stdoutPath -Raw -Encoding UTF8 } else { '' }
            $stderr = if (Test-Path -LiteralPath $stderrPath) { Get-Content -LiteralPath $stderrPath -Raw -Encoding UTF8 } else { '' }
            return [pscustomobject]@{ exitCode = [int]$exitCode; stdout = [string]$stdout; stderr = [string]$stderr; stdoutPath = $stdoutPath; stderrPath = $stderrPath }
        }

        $results = [Collections.Generic.List[object]]::new()
        $mutations = @(
            [pscustomobject]@{
                name = 'frozen protected module SHA mismatch'
                expectedError = 'Repository general bootstrap cleanup helper differs from its exact retained frozen module binding.'
                mutate = {
                    param($adapter, $fixture)
                    $modulePath = Join-Path $fixture.sourceOwnedRoot 'runtime/ProtectedSourceChecks/scripts/CorePesterIntegrity.psm1'
                    $binding = @($adapter.sourceValidation.frozenFiles | Where-Object { [string]$_.path -ceq [IO.Path]::GetFullPath($modulePath) })
                    if ($binding.Count -ne 1) { throw 'Test fixture does not contain one protected Core integrity module binding.' }
                    $binding[0].sha256 = '0' * 64
                }
            }
            [pscustomobject]@{
                name = 'frozen protected module path mismatch'
                expectedError = 'Repository general bootstrap cleanup helper differs from its exact retained frozen module binding.'
                mutate = {
                    param($adapter, $fixture)
                    $modulePath = Join-Path $fixture.sourceOwnedRoot 'runtime/ProtectedSourceChecks/scripts/CorePesterIntegrity.psm1'
                    $binding = @($adapter.sourceValidation.frozenFiles | Where-Object { [string]$_.path -ceq [IO.Path]::GetFullPath($modulePath) })
                    if ($binding.Count -ne 1) { throw 'Test fixture does not contain one protected Core integrity module binding.' }
                    $binding[0].path = [IO.Path]::GetFullPath((Join-Path (Split-Path -Parent $modulePath) 'CorePesterIntegrity.alternate.psm1'))
                }
            }
            [pscustomobject]@{
                name = 'general runtime frozen SHA mismatch'
                expectedError = 'Repository general PowerShell executable differs from its exact retained frozen binding.'
                mutate = {
                    param($adapter, $fixture)
                    $binding = @($adapter.sourceValidation.frozenFiles | Where-Object { [string]$_.path -ceq $fixture.powerShellPath })
                    if ($binding.Count -ne 1) { throw 'Test fixture does not contain one frozen current PowerShell executable binding.' }
                    $binding[0].sha256 = '0' * 64
                }
            }
        )
        foreach ($mutation in $mutations) {
            $fixture = New-GeneralWrapperFixture -Root (Join-Path $TestDrive ([guid]::NewGuid().ToString('N')))
            $adapter = Get-Content -LiteralPath $fixture.retainedAdapterPath -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 80
            $initialManifestCount = @($adapter.sourceValidation.frozenFiles | Where-Object {
                [IO.Path]::GetFileName([string]$_.path) -ceq 'candidate-git-entry-modes.json'
            }).Count
            $initialManifestCount | Should -Be 1
            & $mutation.mutate $adapter $fixture
            Write-A031GeneralAdapterCopies -Fixture $fixture -Adapter $adapter
            if ($mutation.name -ceq 'frozen protected module SHA mismatch') {
                [void](Save-A031EvidenceFile -Name 'general-guard-mutated-adapter.json' -SourcePath $fixture.retainedAdapterPath)
            }
            $result = Invoke-A031GeneralWrapperProbe -Fixture $fixture
            $combined = [string]$result.stdout + [Environment]::NewLine + [string]$result.stderr
            $assertionText = [regex]::Replace($combined, '\r?\n\s*\|\s*', ' ')
            $assertionText = [regex]::Replace($assertionText, '\s+', ' ').Trim()
            $result.exitCode | Should -Not -Be 0 -Because $mutation.name
            $assertionText | Should -Match ([regex]::Escape([string]$mutation.expectedError))
            $results.Add([pscustomobject]@{
                name = $mutation.name; expectedError = $mutation.expectedError; exitCode = $result.exitCode
                stdout = $result.stdout; stderr = $result.stderr; retainedAdapterSha256 = Get-SourceBindingFixtureHash -Path $fixture.retainedAdapterPath
                frozenFiles = @($adapter.sourceValidation.frozenFiles)
            })
        }

        $trackedFixture = New-GeneralWrapperFixture -Root (Join-Path $TestDrive ([guid]::NewGuid().ToString('N')))
        $trackedAdapter = Get-Content -LiteralPath $trackedFixture.retainedAdapterPath -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 80
        $trackedRelativePath = "b-$([guid]::NewGuid().ToString('N')).sig"
        $trackedSignalPath = Join-Path $trackedFixture.candidateRoot $trackedRelativePath
        $trackedBytes = [Text.UTF8Encoding]::new($false).GetBytes('release' + [Environment]::NewLine)
        [IO.File]::WriteAllBytes($trackedSignalPath, $trackedBytes)
        $trackedSignalSha256 = Get-SourceBindingFixtureHash -Path $trackedSignalPath
        $manifest = Get-Content -LiteralPath $trackedFixture.manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 60
        $manifest.entries = @($manifest.entries) + @([pscustomobject]@{ path = $trackedRelativePath; mode = '100644'; sha256 = $trackedSignalSha256 })
        $manifest.entries = @($manifest.entries | Sort-Object -Property path -CaseSensitive)
        [IO.File]::WriteAllText($trackedFixture.manifestPath, (($manifest | ConvertTo-Json -Depth 60 -Compress) + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))
        $manifestSha256 = Get-SourceBindingFixtureHash -Path $trackedFixture.manifestPath
        $identityPath = Join-Path $trackedFixture.sourceOwnedRoot 'source-run-identity.json'
        $identity = Get-Content -LiteralPath $identityPath -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 30
        $identity.candidateManifestSha256 = $manifestSha256
        [IO.File]::WriteAllText($identityPath, (($identity | ConvertTo-Json -Depth 30 -Compress) + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))
        foreach ($binding in @($trackedAdapter.sourceValidation.frozenFiles)) {
            if ([string]$binding.path -ceq $trackedFixture.manifestPath) { $binding.sha256 = $manifestSha256 }
            elseif ([string]$binding.path -ceq $identityPath) { $binding.sha256 = Get-SourceBindingFixtureHash -Path $identityPath }
        }
        Write-A031GeneralAdapterCopies -Fixture $trackedFixture -Adapter $trackedAdapter
        $trackedBeforeHash = Get-SourceBindingFixtureHash -Path $trackedSignalPath
        $trackedResult = Invoke-A031GeneralWrapperProbe -Fixture $trackedFixture -ReleasePath $trackedSignalPath `
            -BootstrapCommand $trackedFixture.powerShellPath
        $trackedCombined = [string]$trackedResult.stdout + [Environment]::NewLine + [string]$trackedResult.stderr
        $trackedAssertionText = [regex]::Replace($trackedCombined, '\r?\n\s*\|\s*', ' ')
        $trackedAssertionText = [regex]::Replace($trackedAssertionText, '\s+', ' ').Trim()
        $trackedResult.exitCode | Should -Not -Be 0
        $trackedAssertionText | Should -Match 'Tracked candidate file cannot be consumed as a repository general bootstrap signal\.'
        (Get-SourceBindingFixtureHash -Path $trackedSignalPath) | Should -Be $trackedBeforeHash
        $results.Add([pscustomobject]@{
            name = 'tracked supervisor-shaped signal path'; expectedError = 'Tracked candidate file cannot be consumed as a repository general bootstrap signal.'
            exitCode = $trackedResult.exitCode; stdout = $trackedResult.stdout; stderr = $trackedResult.stderr
            signalPath = $trackedSignalPath; signalSha256 = $trackedSignalSha256; signalPreserved = ((Get-SourceBindingFixtureHash -Path $trackedSignalPath) -ceq $trackedBeforeHash)
            manifestSha256 = $manifestSha256; retainedAdapterSha256 = Get-SourceBindingFixtureHash -Path $trackedFixture.retainedAdapterPath
        })
        [void](Save-A031EvidenceJson -Name 'general-cleanup-guard-cases.json' -Value ([ordered]@{ cases = @($results.ToArray()) }))
    }

    # Scenario: the protected event-base driver remains on the active 8a authority while candidate tests run.
    # Purpose: keep the legacy gate compatible with its existing Validate.ps1 parameters and provide its child an exact, verified authority fixture without network resolution.
    It 'InterT20_preserves_the_legacy_8a_gate_and_supplies_its_verified_fixture' {
        $workflow = Get-Content -LiteralPath (Join-Path $script:RepositoryRoot '.github/workflows/validate.yml') -Raw
        $integrationTest = Get-Content -LiteralPath (Join-Path $script:RepositoryRoot 'tests/CommonToolReportIntegration.Tests.ps1') -Raw

        $workflow | Should -Match ([regex]::Escape('ref: ${{ github.event.pull_request.base.sha || (github.event.before != ''0000000000000000000000000000000000000000'' && github.event.before) || github.sha }}'))
        $workflow | Should -Match ([regex]::Escape('ref: ${{ github.event.pull_request.head.sha || github.sha }}'))
        $workflow | Should -Not -Match 'github\.event\.pull_request\.merge_commit_sha'
        $workflow | Should -Match 'Checkout immutable legacy 8a authority fixture'
        $workflow | Should -Match 'ref:\s*8aabd22694a05771f98639f6d726cc9a620eb94b'
        $workflow | Should -Match 'SYP154_CANDIDATE_AUTHORITY_ROOT:\s*\$\{\{\s*github\.workspace\s*\}\}/authority-8a'
        $workflow | Should -Match 'persist-credentials:\s*false'
        $workflow | Should -Match 'GIT_CONFIG_KEY_0:\s*core\.autocrlf'
        $workflow | Should -Match 'GIT_CONFIG_VALUE_0:\s*''false'''
        $workflow | Should -Match 'ls-tree -r --full-tree'
        $workflow | Should -Match 'hash-object --no-filters'
        $legacyRun = [regex]::Match($workflow, '(?ms)- name: Run canonical Standard v1 validation(?<body>.*?)(?=\r?\n  # These jobs|\z)')
        $legacyRun.Success | Should -BeTrue
        $legacyRun.Groups['body'].Value | Should -Match '(?m)^\s*&\s+\./scripts/Validate\.ps1\s+-RepositoryRoot\s+\$candidateRoot'
        $legacyRun.Groups['body'].Value | Should -Not -Match '(?m)^\s*&\s+\./scripts/Validate\.ps1[^\r\n]*\s-(PrepareSourceTools|SourceValidation|SourceToolsPath)\b'

        $integrationTest | Should -Match 'SYP154_CANDIDATE_AUTHORITY_ROOT'
        $integrationTest | Should -Match 'rev-parse HEAD'
        $integrationTest | Should -Match 'remote get-url --all origin'
        $integrationTest | Should -Match 'raw SHA-256 differs'
        $integrationTest | Should -Match 'exact HEAD Git blob'
        $integrationTest | Should -Match 'InterT35_rejects_a_crlf_only_authority_fixture_change'
        $integrationTest | Should -Not -Match 'Invoke-WebRequest|Invoke-RestMethod'
    }

    # Scenario: CI receives a candidate branch whose driver and workflow have changed.
    # Purpose: require the exact protected base driver to validate an immutable candidate checkout.
    It 'InterT10_runs_the_candidate_through_a_separate_protected_base_checkout' {
        $workflow = Get-Content -LiteralPath (Join-Path $script:RepositoryRoot '.github/workflows/validate.yml') -Raw
        $workflow | Should -Match 'path:\s*candidate'
        $workflow | Should -Match 'Checkout protected base driver'
        $workflow | Should -Match 'RepositoryRoot\s+\$candidateRoot'
        $workflow | Should -Match 'persist-credentials:\s*false'
        $workflow | Should -Match 'SourceValidation|candidateRoot'
        $workflow | Should -Not -Match 'CompleteLifecycle|DevelopmentHarness'
    }
}
