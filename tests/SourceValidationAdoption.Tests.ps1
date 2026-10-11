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
            $frozenFiles = @([pscustomobject]@{ path = $manifestPath; sha256 = $manifestHash },
                [pscustomobject]@{ path = $archivePath; sha256 = $archiveHash },
                [pscustomobject]@{ path = $sourceIdentityPath; sha256 = Get-SourceBindingFixtureHash -Path $sourceIdentityPath })
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
            $adapterText = ([ordered]@{ schemaVersion = 2; sourceValidation = [ordered]@{ frozenFiles = @($frozenFiles); toolReceipts = @($toolReceipts) } } | ConvertTo-Json -Depth 30 -Compress) + "`n"
            $retainedAdapterPath = Write-SourceBindingFixtureFile -Path (Join-Path $runRoot 'source-core-adapter.json') -Text $adapterText
            $adapterRoot = Join-Path (Split-Path -Parent $base) ".core-v2-adapter-$runId"
            $adapterPath = Write-SourceBindingFixtureFile -Path (Join-Path $adapterRoot 'standard-core-adapter-v2.json') -Text $adapterText
            $activeSkills = @((Get-Content -LiteralPath (Join-Path $candidateRoot 'catalog/source.json') -Raw | ConvertFrom-Json -Depth 20).skills)
            return [pscustomobject]@{
                runId = $runId; candidateRevision = $candidateRevision; artifactRoot = [IO.Path]::GetFullPath($artifactRoot)
                runRoot = [IO.Path]::GetFullPath($runRoot); candidateRoot = [IO.Path]::GetFullPath($candidateRoot)
                adapterPath = [IO.Path]::GetFullPath($adapterPath); retainedAdapterPath = [IO.Path]::GetFullPath($retainedAdapterPath)
                manifestPath = [IO.Path]::GetFullPath($manifestPath); manifestSha256 = Get-SourceBindingFixtureHash -Path $manifestPath
                sourceOwnedRoot = [IO.Path]::GetFullPath($sourceOwnedRoot); protectedCopyPaths = $protectedCopyPaths
                activeSkills = $activeSkills; wrapperPath = [IO.Path]::GetFullPath((Join-Path $candidateRoot 'scripts/Invoke-RepositoryCheck.ps1'))
            }
        }
    }

    # Scenario: the active source authority allowlist pins the reviewed ff85 commit and all 32 closure records.
    # Purpose: require the complete approved authority tuple used by canonical SourceValidation.
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
        $active.schemaVersion | Should -Be 1
        $active.standardVersion | Should -Be 'v1'
        $active.authority.repository | Should -Be $pin.repository
        $active.authority.commit | Should -Be $pin.commit
        $active.authority.archiveUrl | Should -Be $pin.archiveUrl
        $active.authority.archiveSha256 | Should -Be $pin.archiveSha256
        @($active.authority.files).Count | Should -Be 32
        @($active.authority.files.path) | Should -Be @($pin.files.Keys)
        foreach ($entry in @($active.authority.files)) { $entry.sha256 | Should -Be $pin.files[$entry.path] }
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
        $pwsh = [IO.Path]::GetFullPath([Diagnostics.Process]::GetCurrentProcess().MainModule.FileName)
        try {
            [Environment]::SetEnvironmentVariable('STANDARD_VALIDATION_CORE_RUN_ID', $fixture.runId, 'Process')
            [Environment]::SetEnvironmentVariable('STANDARD_VALIDATION_CORE_CHECK_ID', 'repository-general', 'Process')
            [Environment]::SetEnvironmentVariable('STANDARD_VALIDATION_CORE_SKILLS', ($fixture.activeSkills -join ';'), 'Process')
            Push-Location -LiteralPath $fixture.candidateRoot
            try {
                & $pwsh -NoLogo -NoProfile -NonInteractive -File $fixture.wrapperPath `
                    -CandidateRevision $fixture.candidateRevision 1> $stdoutPath 2> $stderrPath
                $exitCode = $LASTEXITCODE
            }
            finally { Pop-Location }
        }
        finally {
            [Environment]::SetEnvironmentVariable('STANDARD_VALIDATION_CORE_RUN_ID', $previousRunId, 'Process')
            [Environment]::SetEnvironmentVariable('STANDARD_VALIDATION_CORE_CHECK_ID', $previousCheckId, 'Process')
            [Environment]::SetEnvironmentVariable('STANDARD_VALIDATION_CORE_SKILLS', $previousSkills, 'Process')
        }

        $stderr = Get-Content -LiteralPath $stderrPath -Raw -Encoding UTF8
        $stdout = Get-Content -LiteralPath $stdoutPath -Raw -Encoding UTF8
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

    # Scenario: canonical CI validates the immutable candidate through the protected event-base source gate.
    # Purpose: require the Windows source route, same-run setup and validation, retained evidence, and existing mirror contexts.
    It 'InterT20_runs_the_full_source_gate_from_the_protected_event_base' {
        $workflow = Get-Content -LiteralPath (Join-Path $script:RepositoryRoot '.github/workflows/validate.yml') -Raw
        $integrationTest = Get-Content -LiteralPath (Join-Path $script:RepositoryRoot 'tests/CommonToolReportIntegration.Tests.ps1') -Raw

        $workflow | Should -Match ([regex]::Escape('ref: ${{ github.event.pull_request.base.sha || (github.event.before != ''0000000000000000000000000000000000000000'' && github.event.before) || github.sha }}'))
        $workflow | Should -Match ([regex]::Escape('ref: ${{ github.event.pull_request.head.sha || github.sha }}'))
        $workflow | Should -Not -Match 'github\.event\.pull_request\.merge_commit_sha'
        $workflow | Should -Match 'runs-on:\s*windows-latest'
        $workflow | Should -Match 'Checkout immutable ff85 authority fixture'
        $workflow | Should -Match 'ref:\s*ff85d5f80fe795b96354e753074b5ce59ad04ecd'
        $workflow | Should -Match 'path:\s*authority-ff85'
        $workflow | Should -Match 'fetch-depth:\s*0'
        $workflow | Should -Match 'PULL_REQUEST_BASE_SHA:\s*\$\{\{\s*github\.event\.pull_request\.base\.sha\s*\}\}'
        $workflow | Should -Match 'PULL_REQUEST_HEAD_SHA:\s*\$\{\{\s*github\.event\.pull_request\.head\.sha\s*\}\}'
        $workflow | Should -Match 'PUSH_BEFORE_SHA:\s*\$\{\{\s*github\.event\.before\s*\}\}'
        $workflow | Should -Match 'persist-credentials:\s*false'
        $workflow | Should -Match 'GIT_CONFIG_KEY_0:\s*core\.autocrlf'
        $workflow | Should -Match 'GIT_CONFIG_VALUE_0:\s*''false'''
        $workflow | Should -Match 'GIT_CONFIG_KEY_1:\s*core\.eol'
        $workflow | Should -Match 'GIT_CONFIG_VALUE_1:\s*lf'
        $workflow | Should -Match 'ls-tree -r --full-tree'
        $workflow | Should -Match 'hash-object --no-filters'
        $workflow | Should -Match 'merge-base --is-ancestor'
        $workflow | Should -Match 'A supplied BaseCommit must resolve to a distinct candidate ancestor'
        $workflow | Should -Match 'TimeoutSeconds 10800'
        $workflow | Should -Match 'actions/upload-artifact@[0-9a-f]{40}'
        $workflow | Should -Match 'if:\s*\$\{\{\s*always\(\)\s*\}\}'
        $uploadBlock = [regex]::Match($workflow, '(?ms)- name: Upload source validation evidence(?<body>.*?)(?=^\s{2}[A-Za-z0-9_-]+:)')
        $uploadBlock.Success | Should -BeTrue
        $uploadBlock.Groups['body'].Value | Should -Match '\$\{\{\s*runner\.temp\s*\}\}/code-collaboration/'
        $uploadBlock.Groups['body'].Value | Should -Match '!\$\{\{\s*runner\.temp\s*\}\}/code-collaboration/source-tools/source-tools-\*/runtime/\*\*'
        $uploadBlock.Groups['body'].Value | Should -Match '!\$\{\{\s*runner\.temp\s*\}\}/code-collaboration/source-tools/source-tools-\*/installed/\*\*'
        $uploadBlock.Groups['body'].Value | Should -Not -Match '!.*(?:core-v2|runs|repository-pester-case-inventory)'
        $sourceToolsSetup = [regex]::Match($workflow, '(?ms)- name: Prepare source tools once(?<body>.*?)(?=^      - name: Run full source validation)')
        $sourceValidation = [regex]::Match($workflow, '(?ms)- name: Run full source validation(?<body>.*?)(?=^      - name: Upload source validation evidence)')
        $sourceToolsSetup.Success | Should -BeTrue
        $sourceValidation.Success | Should -BeTrue
        foreach ($step in @($sourceToolsSetup.Groups['body'].Value, $sourceValidation.Groups['body'].Value)) {
            $step | Should -Match '\$protectedDriver'
            $step | Should -Match '\$candidateRoot'
            $step | Should -Match '\$authorityRoot'
            $step | Should -Match '\$sourceToolsPath'
            $step | Should -Match '\$baseCommit'
            $step | Should -Match 'TimeoutSeconds 10800'
        }
        $sourceToolsSetup.Groups['body'].Value | Should -Match '\-PrepareSourceTools'
        $sourceValidation.Groups['body'].Value | Should -Match '\-SourceValidation'
        $sourceToolsSetup.Groups['body'].Value | Should -Not -Match '\-RunId\b'
        $sourceToolsSetup.Groups['body'].Value | Should -Match 'source-tools-setup-completed'
        $sourceToolsSetup.Groups['body'].Value | Should -Match '\[string\]\$prepared\.ownedRoot.*setup-timing\.json'
        $sourceToolsSetup.Groups['body'].Value | Should -Match 'prepared\.sourceValidation\.frozenFiles'
        $sourceToolsSetup.Groups['body'].Value | Should -Match 'setupTimingPath -NotePropertyValue \$setupTimingPath'
        $sourceValidation.Groups['body'].Value | Should -Match 'source-validation-timing'
        $sourceValidation.Groups['body'].Value | Should -Match 'standard-core-validation-v2-report'
        $sourceValidation.Groups['body'].Value | Should -Match 'Split-Path -Parent \$artifactsRoot.*source-validation-timing'
        $sourceValidation.Groups['body'].Value | Should -Match '\$report\.sourceValidation\.pesterCaseInventory'
        $sourceValidation.Groups['body'].Value | Should -Match '\$report\.artifacts\.runRoot'
        $sourceValidation.Groups['body'].Value | Should -Match 'reportedCounts\.Passed'
        $sourceValidation.Groups['body'].Value | Should -Match '\$caseLedger\.containerFileInventory'
        $sourceValidation.Groups['body'].Value | Should -Match 'combinedSetupToValidationSeconds'
        $sourceValidation.Groups['body'].Value | Should -Match '\$setupTimingPath = Join-Path \$ownedRoot ''setup-timing\.json'''
        $sourceValidation.Groups['body'].Value | Should -Match 'prepared\.sourceValidation\.frozenFiles'
        $sourceValidation.Groups['body'].Value | Should -Match 'source-validation\.stdout\.txt'
        $sourceValidation.Groups['body'].Value | Should -Match 'source-validation\.stderr\.txt'
        $sourceValidation.Groups['body'].Value | Should -Match 'if \(-not \[string\]::IsNullOrWhiteSpace\(\$baseCommit\)\)'
        $sourceValidation.Groups['body'].Value | Should -Match ([regex]::Escape("@('-BaseCommit', `$baseCommit)"))

        $integrationTest | Should -Match 'SYP154_CANDIDATE_AUTHORITY_ROOT'
        $integrationTest | Should -Match 'rev-parse HEAD'
        $integrationTest | Should -Match 'remote get-url --all origin'
        $integrationTest | Should -Match 'raw SHA-256 differs'
        $integrationTest | Should -Match 'exact HEAD Git blob'
        $integrationTest | Should -Match 'InterT35_rejects_a_crlf_only_authority_fixture_change'
        $integrationTest | Should -Match 'git -C \$script:sourceAuthorityRoot archive --format=zip'
        $integrationTest | Should -Not -Match 'Invoke-WebRequest|Invoke-RestMethod'

        foreach ($context in @('repository-contract', 'skill-validator', 'skill-tools')) {
            $workflow | Should -Match ("(?m)^  " + [regex]::Escape($context) + ':\r?$')
        }
    }

    # Scenario: the candidate driver and workflow differ from the trusted event base.
    # Purpose: require both source phases to use the same protected base driver and source-tools file.
    It 'InterT10_runs_the_candidate_through_a_separate_protected_base_checkout' {
        $workflow = Get-Content -LiteralPath (Join-Path $script:RepositoryRoot '.github/workflows/validate.yml') -Raw
        $workflow | Should -Match 'path:\s*candidate'
        $workflow | Should -Match 'Checkout protected base driver'
        $workflow | Should -Match 'protectedDriver\s*=\s*Join-Path\s+\$baseRoot\s+''scripts/Validate\.ps1'''
        $workflow | Should -Match ([regex]::Escape("'-RepositoryRoot', `$candidateRoot"))
        $workflow | Should -Match ([regex]::Escape("'-BaseCommit', `$baseCommit"))
        $workflow | Should -Match 'persist-credentials:\s*false'
        $workflow | Should -Match '\-PrepareSourceTools'
        $workflow | Should -Match '\-SourceValidation'
        $workflow | Should -Match ([regex]::Escape("'-SourceToolsPath', `$sourceToolsPath"))
        $workflow | Should -Match ([regex]::Escape("'-AuthorityRepositoryRoot', `$authorityRoot"))
        $workflow | Should -Not -Match 'CompleteLifecycle|DevelopmentHarness'
    }
}
