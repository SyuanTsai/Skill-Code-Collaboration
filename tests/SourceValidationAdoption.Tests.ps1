# SPDX-FileCopyrightText: 2026 SyuanTsai
# SPDX-License-Identifier: Apache-2.0
Describe 'Protected Standard Core SourceValidation preparation' {
    BeforeAll {
        $script:RepositoryRoot = Split-Path -Parent $PSScriptRoot
        $script:DriverPath = Join-Path $script:RepositoryRoot 'scripts/StandardSourceDriver.psm1'
        $script:ConfigPath = Join-Path $script:RepositoryRoot 'config/standard-v1.json'
        $script:SourceSetupFailureStage = $null
        $script:SourceSetupPreparedPath = $null
        $script:SourceRepository = $null
        $script:SourceCleanupFailed = $false
        $script:SourceInvalidInput = $false

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

        function New-SourceAuthorityConfigFixture {
            param([Parameter(Mandatory)] $Pin)

            return [pscustomobject]@{
                schemaVersion = 1
                standardVersion = 'v1'
                authority = [pscustomobject]@{
                    repository = $Pin.repository
                    commit = $Pin.commit
                    archiveUrl = $Pin.archiveUrl
                    archiveSha256 = $Pin.archiveSha256
                    files = @($Pin.files.GetEnumerator() | ForEach-Object {
                        [pscustomobject]@{ path = [string]$_.Key; sha256 = [string]$_.Value }
                    })
                }
            }
        }

        function New-FormalSourceAuthorityPinFixture {
            # Start from the checked-in active config fixture, never the production getter,
            # so this expectation independently checks all 32 returned hashes.
            $baseConfig = Get-Content -LiteralPath $script:ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 20
            $basePin = $baseConfig.authority
            $ff85Commit = 'ff85d5f80fe795b96354e753074b5ce59ad04ecd'
            $ff85ArchiveSha256 = '3dc38613f2e2316ad8fcc79d4bf48d0b03fd8398f8dacc72d156abcbce95ea9d'
            $formalCommit = '8e627baf54bd6e47862e6291b25e71cc45a2f2b7'
            $formalArchiveSha256 = '9aa4a7fc8fc7c7f0ff9e774c79c77a64077b4003212a523dda519d034ff99989'
            $formalHashes = [ordered]@{
                'docs/standards/skill-repository-standard.md' = 'f7457bc6dbc13b475bcffc532b75961ff838e8d184162188dbbb1c766fd17e98'
                'scripts/Invoke-StandardAuthorityGate.ps1' = 'c4609b7f88f9b88be8583cc52f939837d49f2fa5e784977156cfe3d7c752082e'
                'scripts/Invoke-StandardValidation.ps1' = 'd13cea68b471aea60142665ee787a1bb2111d5ea7f8d45dfea14e0a2a59409b8'
            }
            if ([string]$basePin.repository -cne 'https://github.com/SyuanTsai/SyuanTsai-AI-Instructions.git' -or
                @($basePin.files).Count -ne 32) {
                throw 'The checked-in active config fixture does not match the known repository and 32-file authority shape.'
            }
            $files = [ordered]@{}
            foreach ($entry in @($basePin.files)) { $files[[string]$entry.path] = [string]$entry.sha256 }
            $expectedUrl = "https://codeload.github.com/SyuanTsai/SyuanTsai-AI-Instructions/zip/$($basePin.commit)"
            if ([string]$basePin.commit -ceq $ff85Commit) {
                if ([string]$basePin.archiveUrl -cne $expectedUrl -or [string]$basePin.archiveSha256 -cne $ff85ArchiveSha256) {
                    throw 'The checked-in ff85 config fixture does not match its reviewed archive identity.'
                }
                foreach ($path in $formalHashes.Keys) { $files[[string]$path] = [string]$formalHashes[$path] }
            }
            elseif ([string]$basePin.commit -ceq $formalCommit) {
                if ([string]$basePin.archiveUrl -cne $expectedUrl -or [string]$basePin.archiveSha256 -cne $formalArchiveSha256) {
                    throw 'The checked-in formal config fixture does not match its reviewed archive identity.'
                }
                foreach ($path in $formalHashes.Keys) {
                    if ([string]$files[[string]$path] -cne [string]$formalHashes[$path]) {
                        throw "The checked-in formal config fixture has an unreviewed hash for $path."
                    }
                }
            }
            else { throw 'The checked-in config fixture must name an exact reviewed ff85 or 8e authority revision.' }

            return [pscustomobject]@{
                repository = $basePin.repository
                commit = $formalCommit
                archiveUrl = "https://codeload.github.com/SyuanTsai/SyuanTsai-AI-Instructions/zip/$formalCommit"
                archiveSha256 = $formalArchiveSha256
                files = $files
            }
        }

        function New-SourceBindingFixture {
            param(
                [Parameter(Mandatory)][string] $Root,
                [string] $AuthorityRevision = 'ff85d5f80fe795b96354e753074b5ce59ad04ecd'
            )

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
                authorityRevision = $AuthorityRevision
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
                sourceRevision = $candidateRevision; authorityRevision = $AuthorityRevision
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
                manifestPath = [IO.Path]::GetFullPath($manifestPath); authorityRevision = $AuthorityRevision
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
            foreach ($eventSpec in @(
                [pscustomobject]@{ toolId = 'package-adapter'; stageId = 'package-validation'; skillId = $null; hasNativeReports = $false }
                [pscustomobject]@{ toolId = 'skill-validator'; stageId = 'package-validation'; skillId = 'demo'; hasNativeReports = $true }
                [pscustomobject]@{ toolId = 'skill-tools'; stageId = 'package-validation'; skillId = 'demo'; hasNativeReports = $true }
                [pscustomobject]@{ toolId = 'static-analyzer'; stageId = 'skillspector-static'; skillId = $null; hasNativeReports = $true }
            )) {
                $toolId = [string]$eventSpec.toolId
                $stdout = ''
                if ($eventSpec.hasNativeReports) {
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
                    $stdout = ($envelope | ConvertTo-Json -Depth 30) + "`r`n"
                }
                $stderr = ''
                $eventIdentity = [ordered]@{
                    eventId = [guid]::NewGuid().ToString('D'); stageId = [string]$eventSpec.stageId
                    toolId = $toolId; skillId = $eventSpec.skillId; candidateId = ('f' * 64)
                }
                $eventRecord = [ordered]@{
                    schemaVersion = 1; eventId = $eventIdentity.eventId; stageId = $eventIdentity.stageId
                    toolId = $eventIdentity.toolId; skillId = $eventIdentity.skillId; candidateId = $eventIdentity.candidateId
                    process = [ordered]@{ exitCode = 0; status = 'passed'; cleanedUp = $true }
                    stdout = $stdout; stderr = $stderr
                }
                $eventPath = Write-SourceBindingFixtureFile -Path (Join-Path $eventRoot "$toolId-event.json") -Text (($eventRecord | ConvertTo-Json -Depth 30 -Compress) + "`n")
                $outputSha256 = Get-A031TextSha256 -Value ($stdout + "`n---stderr---`n" + $stderr)
                $events += [pscustomobject]@{
                    eventId = $eventIdentity.eventId; stageId = $eventIdentity.stageId; toolId = $eventIdentity.toolId
                    skillId = $eventIdentity.skillId; candidateId = $eventIdentity.candidateId
                    exitCode = 0; status = 'passed'; cleanedUp = $true
                    outputPath = $eventPath; outputSha256 = $outputSha256
                }
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
            $processCommand = Get-Command -Name Invoke-StandardValidationProcess -CommandType Function -ErrorAction Stop
            $expectedRunnerPath = [IO.Path]::GetFullPath($RunnerPath)
            $boundRunnerPath = [IO.Path]::GetFullPath([string]$processCommand.ScriptBlock.File)
            $pathComparison = if ($IsWindows) { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal }
            if (-not $boundRunnerPath.Equals($expectedRunnerPath, $pathComparison)) {
                throw 'The invoked process supervisor function did not originate from the admitted authority runner.'
            }

            $processParameters = @{
                Command = $PowerShellPath
                Arguments = $Arguments
                WorkingDirectory = $WorkingDirectory
                Environment = $Environment
                TimeoutSeconds = 90
            }
            $coreLifecycleOnlyAdmitted = $processCommand.Parameters.ContainsKey('CoreLifecycleOnly')
            if ($coreLifecycleOnlyAdmitted) { $processParameters.CoreLifecycleOnly = $true }
            $script:A031LastProcessInvocation = [pscustomobject]@{
                runnerPath = $expectedRunnerPath
                functionPath = $boundRunnerPath
                admittedParameters = @($processCommand.Parameters.Keys | Sort-Object)
                coreLifecycleOnlyAdmitted = $coreLifecycleOnlyAdmitted
                coreLifecycleOnlyPassed = $coreLifecycleOnlyAdmitted
            }
            return Invoke-StandardValidationProcess @processParameters
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
        function Invoke-SourceSetupLateTimingBlockForTest {
            param([Parameter(Mandatory)][string] $Root, [string] $FailureStage)

            $validatePath = Join-Path $script:RepositoryRoot 'scripts/Validate.ps1'
            $tokens = $null
            $parseErrors = $null
            $validateAst = [System.Management.Automation.Language.Parser]::ParseFile($validatePath, [ref]$tokens, [ref]$parseErrors)
            if (@($parseErrors).Count -gt 0) { throw 'Validate.ps1 did not parse for setup timing behavior test.' }
            $setupAst = $validateAst.Find({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq 'Invoke-CodeSourceToolSetup' }, $true)
            if ($null -eq $setupAst) { throw 'Invoke-CodeSourceToolSetup was not found.' }
            $outerTry = @($setupAst.Body.EndBlock.Statements | Where-Object { $_ -is [System.Management.Automation.Language.TryStatementAst] })
            if ($outerTry.Count -ne 1) { throw 'Invoke-CodeSourceToolSetup did not have one direct outer try block.' }
            $statements = $outerTry[0].Body.Statements
            $startIndex = -1
            $endIndex = -1
            for ($index = 0; $index -lt $statements.Count; $index++) {
                $text = $statements[$index].Extent.Text
                if ($startIndex -lt 0 -and ($text.Contains('$finalFrozenVerificationSeconds = $null') -or $text.Contains('$frozenRecords = @($sourceFrozenFiles.files)'))) { $startIndex = $index }
                if ($text.Contains('Source setup timing evidence:')) { $endIndex = $index }
            }
            if ($startIndex -lt 0 -or $endIndex -lt $startIndex) { throw 'The production late setup receipt span could not be located.' }
            $productionTimingSpan = [string]::Join([Environment]::NewLine, @($statements[$startIndex..$endIndex] | ForEach-Object { $_.Extent.Text }))

            foreach ($name in @('Get-FileSha256', 'Assert-NoReparseAncestors', 'Test-PathEqual', 'Write-Utf8NoBomCreateNew')) {
                $definition = $validateAst.Find({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq $name }, $true)
                if ($null -eq $definition) { throw "The production helper function was not found: $name" }
                . ([scriptblock]::Create($definition.Extent.Text))
            }

            $fixture = New-SourceBindingFixture -Root $Root
            $earlyTimingPath = Join-Path $fixture.prepared.ownedRoot 'setup-timing.json'
            $earlyBytes = [IO.File]::ReadAllBytes($earlyTimingPath)
            $earlyHashBefore = Get-SourceBindingFixtureHash -Path $earlyTimingPath
            $earlyInput = Get-Content -LiteralPath $earlyTimingPath -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 40
            $setupStageSeconds = [ordered]@{}
            foreach ($property in $earlyInput.stageSeconds.PSObject.Properties) { $setupStageSeconds[$property.Name] = [double]$property.Value }
            $resolverStageSeconds = [ordered]@{}
            foreach ($property in $earlyInput.resolverSeconds.PSObject.Properties) { $resolverStageSeconds[$property.Name] = [double]$property.Value }
            $setupStartedAtUtc = [DateTimeOffset]::Parse([string]$earlyInput.startedAtUtc)
            $setupRoot = [IO.Path]::GetFullPath($fixture.root)
            $preparedPath = Join-Path $setupRoot "prepared-timing-$($fixture.runId).json"
            $runId = [string]$fixture.runId
            $ownedRoot = [IO.Path]::GetFullPath($fixture.prepared.ownedRoot)
            $setupTimingPath = [IO.Path]::GetFullPath($earlyTimingPath)
            $setupTimingRecord = [pscustomobject]@{ path = $setupTimingPath; sha256 = $earlyHashBefore }
            $sourceDispatch = $fixture.prepared.sourceValidation
            $sourceFrozenFiles = [pscustomobject]@{
                files = @($sourceDispatch.frozenFiles | Where-Object { [IO.Path]::GetFullPath([string]$_.path) -cne $setupTimingPath })
            }
            $RepositoryRoot = $fixture.root
            $CandidateRevision = [string]$fixture.candidateRevision
            $pin = [pscustomobject]@{ commit = [string]$fixture.authorityRevision }
            $archivePath = [string]$fixture.prepared.candidateArchivePath
            $archiveSha256 = [string]$fixture.prepared.candidateArchiveSha256
            $moduleManifestPath = [string]$fixture.prepared.pesterRuntime.moduleManifestPath
            $lockPath = [string]$fixture.prepared.pesterRuntime.closureLockPath
            $lockHash = [string]$fixture.prepared.pesterRuntime.closureLockSha256
            $setupReceiptPath = [string]$fixture.prepared.pesterRuntime.setupReceiptPath
            $runtimeRoot = [string]$fixture.prepared.pesterRuntime.runtimeRoot
            $powerShell = [string]$fixture.prepared.pesterRuntime.runtimeExecutablePath
            $runtimeInventoryPath = [string]$fixture.prepared.pesterRuntime.runtimeInventoryPath
            $runtimeInventorySha256 = [string]$fixture.prepared.pesterRuntime.runtimeInventorySha256
            $trustedRoot = [string]$fixture.prepared.pesterRuntime.sourceTrustedToolRoot
            $runnerModule = [pscustomobject]@{ testModule = $true }
            $setupTimer = [Diagnostics.Stopwatch]::StartNew()

            $previousSourceSetupFailureStage = $script:SourceSetupFailureStage
            $previousSourceSetupPreparedPath = $script:SourceSetupPreparedPath
            $script:SourceSetupFailureStage = $FailureStage
            $script:SourceSetupPreparedPath = [IO.Path]::GetFullPath($preparedPath)
            $writerDefinition = $validateAst.Find({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq 'Write-Utf8NoBomCreateNew' }, $true)
            if ($null -eq $writerDefinition) { throw 'The production create-only writer was not found.' }
            $writerAliasText = [string]$writerDefinition.Extent.Text -replace '(?i)\bfunction\s+Write-Utf8NoBomCreateNew\b', 'function Write-Utf8NoBomCreateNewForTimingTest'
            . ([scriptblock]::Create($writerAliasText))
            function Write-Utf8NoBomCreateNew {
                param([string] $Path, [string] $Text)
                if ($script:SourceSetupFailureStage -ceq 'prepared' -and (Test-PathEqual -Left $Path -Right $script:SourceSetupPreparedPath)) {
                    throw 'fixture prepared metadata write failure'
                }
                Write-Utf8NoBomCreateNewForTimingTest -Path $Path -Text $Text
            }
            function Invoke-CodeSourceStandardValidationModule {
                param($Module, [string] $FunctionName, $Arguments)
                if (($script:SourceSetupFailureStage -ceq 'frozen' -and $FunctionName -ceq 'Assert-StandardCoreFrozenFiles') -or
                    ($script:SourceSetupFailureStage -ceq 'receipts' -and $FunctionName -ceq 'Assert-StandardCoreSourceToolReceipts')) {
                    throw "fixture $($script:SourceSetupFailureStage) verification failure"
                }
            }

            $productionBlock = [scriptblock]::Create($productionTimingSpan)
            $failure = $null
            try { $null = & $productionBlock }
            catch { $failure = $_.Exception.Message }
            $earlyHashAfter = Get-SourceBindingFixtureHash -Path $earlyTimingPath
            $script:SourceSetupFailureStage = $previousSourceSetupFailureStage
            $script:SourceSetupPreparedPath = $previousSourceSetupPreparedPath
            return [pscustomobject]@{
                setupRoot = $setupRoot
                preparedPath = [IO.Path]::GetFullPath($preparedPath)
                setupTimingPath = $setupTimingPath
                completedPath = [IO.Path]::GetFullPath((Join-Path $setupRoot "source-tools-setup-completed-$runId.json"))
                runId = $runId
                setupStageSeconds = $setupStageSeconds
                resolverStageSeconds = $resolverStageSeconds
                setupTimingBytesBefore = $earlyBytes
                setupTimingHashBefore = $earlyHashBefore
                setupTimingHashAfter = $earlyHashAfter
                failure = $failure
                preparedExists = [IO.File]::Exists($preparedPath)
                completedExists = [IO.File]::Exists((Join-Path $setupRoot "source-tools-setup-completed-$runId.json"))
            }
        }

        function Invoke-SourceValidationOuterTryForTest {
            param(
                [Parameter(Mandatory)][string] $Root,
                [ValidateSet('success', 'reader', 'binding', 'nonzero', 'cancel', 'cleanup', 'snapshot', 'adapter')]
                [string] $Scenario = 'success'
            )

            $authorityBinding = Get-A031AuthoritySupervisorBinding
            $fixture = New-SourceBindingFixture -Root (Join-Path $Root 'prepared') -AuthorityRevision ([string]$authorityBinding.revision)
            $validatePath = Join-Path $script:RepositoryRoot 'scripts/Validate.ps1'
            $tokens = $null
            $parseErrors = $null
            $validateAst = [System.Management.Automation.Language.Parser]::ParseFile($validatePath, [ref]$tokens, [ref]$parseErrors)
            if (@($parseErrors).Count -gt 0) { throw 'Validate.ps1 did not parse for source timing behavior test.' }
            $sourceFunction = $validateAst.Find({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq 'Invoke-CodeSourceValidation' }, $true)
            if ($null -eq $sourceFunction) { throw 'Invoke-CodeSourceValidation was not found.' }
            $outerTry = @($sourceFunction.Body.EndBlock.Statements | Where-Object {
                $_ -is [System.Management.Automation.Language.TryStatementAst] -and $null -ne $_.Finally -and $_.Finally.Extent.Text.Contains('$timingEvidence')
            })
            if ($outerTry.Count -ne 1) { throw 'Invoke-CodeSourceValidation did not have one direct outer try block.' }

            foreach ($name in @('Assert-NoDuplicateJsonProperties', 'Convert-JsonElementToPowerShellObject', 'Get-FileSha256', 'Read-JsonFile',
                'Assert-NoReparseAncestors', 'Assert-OutsideRoot', 'Test-PathWithinOrEqual', 'Test-PathEqual', 'Assert-PathWithinRoot',
                'Write-Utf8NoBomCreateNew', 'Write-CodeSourceRunnerOutputDiagnostic')) {
                $definition = $validateAst.Find({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq $name }, $true)
                if ($null -eq $definition) { throw "The production source timing helper was not found: $name" }
                . ([scriptblock]::Create($definition.Extent.Text))
            }

            $realPowerShell = [IO.Path]::GetFullPath([Diagnostics.Process]::GetCurrentProcess().MainModule.FileName)
            $trustedRoot = [IO.Path]::GetFullPath((Split-Path -Parent $realPowerShell))
            $prepared = $fixture.prepared
            $prepared.pesterRuntime.runtimeExecutablePath = $realPowerShell
            $prepared.pesterRuntime.runtimeExecutableSha256 = Get-FileSha256 -Path $realPowerShell
            $prepared.pesterRuntime.runtimeRoot = $trustedRoot
            $prepared.pesterRuntime.sourceTrustedToolRoot = $trustedRoot
            $preparedPath = [IO.Path]::GetFullPath($fixture.preparedPath)
            [IO.File]::WriteAllText($preparedPath, (($prepared | ConvertTo-Json -Depth 80) + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))

            $authorityRoot = [IO.Path]::GetFullPath([string]$authorityBinding.root)
            $authorityRevision = [string]$authorityBinding.revision
            $git = Get-Command git -CommandType Application -ErrorAction Stop | Select-Object -First 1

            $script:SourceTimingTestScenario = $Scenario
            $script:SourceTimingTestAdapterRoot = Join-Path $Root ".core-v2-adapter-$($fixture.runId)"
            $script:SourceTimingTestPin = [pscustomobject]@{
                commit = $authorityRevision
                files = [ordered]@{ 'scripts/Invoke-StandardValidation.ps1' = ('0' * 64) }
            }
            function New-CodeSourceAuthoritySnapshot {
                param([string] $GitPath, [string] $SourceRoot, [string] $OwnedRoot, $AuthorityPin)
                if ($script:SourceTimingTestScenario -ceq 'snapshot') { throw 'fixture authority snapshot failure' }
                $runnerPath = Join-Path $OwnedRoot 'authority/scripts/Invoke-StandardValidation.ps1'
                [void](New-Item -ItemType Directory -Path (Split-Path -Parent $runnerPath) -Force)
                # This fragment substitutes only the expensive external Core runner payload; it does not assert the formal runner hash, prepared-runtime admission, or full-gate outcome.
                $runnerText = @'
[CmdletBinding()]
param(
    [string] $CandidateRoot, [string] $AdapterPath, [string] $ArtifactsRoot, [string] $OutputPath,
    [string] $SourceRepository, [string] $SourceRevision, [string] $BaseRevision, [string] $EventName,
    [string] $AuthorityRevision, [int] $TimeoutSeconds, [string] $TrustedToolRoot,
    [switch] $SourceValidation, [string] $RunId, [string] $CancellationPath
)
$code = [int][Environment]::GetEnvironmentVariable('SYP326_SOURCE_TEST_EXIT_CODE', 'Process')
if ($code -eq 0) { [IO.File]::WriteAllText($OutputPath, '{"fixture":true}', [Text.UTF8Encoding]::new($false)) }
[Console]::Out.WriteLine("controlled source runner exit=$code")
exit $code
'@
                [IO.File]::WriteAllText($runnerPath, $runnerText, [Text.UTF8Encoding]::new($false))
                $AuthorityPin.files['scripts/Invoke-StandardValidation.ps1'] = Get-FileSha256 -Path $runnerPath
                return [pscustomobject]@{ root = [IO.Path]::GetFullPath((Join-Path $OwnedRoot 'authority')); runnerPath = [IO.Path]::GetFullPath($runnerPath) }
            }
            function Get-CodeSourceCoreRunPaths {
                param([string] $ArtifactsRoot, [bool] $ArtifactsRootWasExplicit, [string] $RunId, [string] $OutputPath)
                $fullArtifactsRoot = [IO.Path]::GetFullPath($ArtifactsRoot)
                $adapterRoot = Join-Path (Split-Path -Parent $fullArtifactsRoot) ".core-v2-adapter-$RunId"
                $adapterPath = Join-Path $adapterRoot 'source-core-adapter.json'
                $reportPath = if ([string]::IsNullOrWhiteSpace($OutputPath)) { Join-Path $fullArtifactsRoot 'standard-core-validation-v2-report.json' } else { [IO.Path]::GetFullPath($OutputPath) }
                return [pscustomobject]@{ artifactsRoot = $fullArtifactsRoot; adapterRoot = [IO.Path]::GetFullPath($adapterRoot); adapterPath = [IO.Path]::GetFullPath($adapterPath); outputPath = [IO.Path]::GetFullPath($reportPath) }
            }
            function New-CodeCoreAdapterV2 {
                param($PowerShellPath, $TrustedToolRoot, $CandidateAuthorityAdapterRunId, $CandidateRevision,
                    $CandidateGitEntryModeManifestPath, $CandidateGitEntryModeManifestSha256, $ActiveSkillIds, $SourceValidation, $PesterRuntime)
                if ($script:SourceTimingTestScenario -ceq 'adapter') { throw 'fixture source adapter creation failure' }
                return [ordered]@{ schemaVersion = 2; runId = [string]$CandidateAuthorityAdapterRunId }
            }
            function Get-ActiveSkillIds { param([string] $Root) return @('demo') }
            function New-CodeSourceStandardValidationModule {
                param($RunnerPath, $RunnerSha256, $RunnerArguments, [switch] $SourceValidation)
                if ($script:SourceTimingTestScenario -ceq 'reader') { throw 'fixture protected report reader failure' }
                return $null
            }
            function Invoke-CodeSourceStandardValidationModule { param($Module, [string] $FunctionName, $Arguments) }
            function Assert-CodeSourceReportBinding {
                param($Report, $Prepared, $CandidateRevision, $BaseRevision, $AuthorityRevision, $EventName,
                    $ArtifactsRoot, $OutputPath, $ProcessExitCode, $CleanupSucceeded, $CancellationRequested)
                if ($script:SourceTimingTestScenario -ceq 'binding') { throw 'fixture source report binding failure' }
                if ($script:SourceTimingTestScenario -ceq 'cancel' -and $CancellationRequested) { throw 'fixture cancellation report binding failure' }
            }
            function Remove-Item {
                [CmdletBinding()]
                param([string] $LiteralPath, [switch] $Recurse, [switch] $Force)
                if ($script:SourceTimingTestScenario -ceq 'cleanup' -and (Test-PathEqual -Left $LiteralPath -Right $script:SourceTimingTestAdapterRoot)) {
                    throw 'fixture source adapter cleanup failure'
                }
                $removeArguments = @{ LiteralPath = $LiteralPath }
                if ($Recurse) { $removeArguments.Recurse = $true }
                if ($Force) { $removeArguments.Force = $true }
                if ($PSBoundParameters.ContainsKey('ErrorAction')) { $removeArguments.ErrorAction = [string]$PSBoundParameters['ErrorAction'] }
                Microsoft.PowerShell.Management\Remove-Item @removeArguments
            }

            $candidateRoot = [IO.Path]::GetFullPath((Join-Path $Root 'candidate'))
            $artifactsRoot = [IO.Path]::GetFullPath((Join-Path $Root 'core-run'))
            $null = New-Item -ItemType Directory -Path $candidateRoot -Force
            $preparedPath = [IO.Path]::GetFullPath($preparedPath)
            $preparedRoot = [IO.Path]::GetFullPath((Split-Path -Parent $preparedPath))
            $setupTimingPath = Join-Path ([string]$prepared.ownedRoot) 'setup-timing.json'
            $setupTimingBinding = @($prepared.sourceValidation.frozenFiles | Where-Object { Test-PathEqual -Left ([string]$_.path) -Right $setupTimingPath })
            $setupTiming = Read-JsonFile -Path $setupTimingPath -Context 'Prepared source setup timing evidence'
            $setupCompletedTimingPath = Join-Path $preparedRoot "source-tools-setup-completed-$($prepared.runId).json"
            $setupCompleted = [ordered]@{
                schemaVersion = 1; runId = [string]$prepared.runId; setupStartedAtUtc = [string]$setupTiming.startedAtUtc
                setupTotalSeconds = 10.0; diagnosticTargetSeconds = 1200
                totalBoundary = 'after complete frozen-file verification and prepared metadata creation'
            }
            [IO.File]::WriteAllText($setupCompletedTimingPath, (($setupCompleted | ConvertTo-Json -Depth 20 -Compress) + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))
            $setupCompletedTiming = Read-JsonFile -Path $setupCompletedTimingPath -Context 'Completed source setup timing evidence'
            $setupCompletedTimingSha256 = Get-FileSha256 -Path $setupCompletedTimingPath
            $RepositoryRoot = $candidateRoot
            $CandidateRevision = [string]$fixture.candidateRevision
            $BaseRevision = 'b' * 40
            $EventName = 'pull_request'
            $TimeoutSeconds = 10800
            $GitPath = [IO.Path]::GetFullPath([string]$git.Path)
            $powerShell = $realPowerShell
            $authority = [pscustomobject]@{ root = $authorityRoot }
            $pin = $script:SourceTimingTestPin
            $TrustedToolRoot = $trustedRoot
            $OutputPath = $null
            $ArtifactsRootWasExplicit = $true
            $CancellationPath = $null
            if ($Scenario -ceq 'cancel') {
                $CancellationPath = Join-Path $Root 'cancel.signal'
                [IO.File]::WriteAllText($CancellationPath, 'cancel', [Text.UTF8Encoding]::new($false))
            }
            $paths = Get-CodeSourceCoreRunPaths -ArtifactsRoot $artifactsRoot -ArtifactsRootWasExplicit $ArtifactsRootWasExplicit -RunId $fixture.runId -OutputPath $OutputPath
            [void](New-Item -ItemType Directory -Path $paths.artifactsRoot -Force)
            [void](New-Item -ItemType Directory -Path $paths.adapterRoot)
            $adapterRootCreated = $true
            $cleanupSucceeded = $false
            $runnerModuleCleanupSucceeded = $true
            $processExitCode = 1
            $reportRunnerModule = $null
            $sourceValidationStartedAtUtc = [DateTimeOffset]::UtcNow
            $sourceValidationTimer = [Diagnostics.Stopwatch]::StartNew()
            $centralRunnerSeconds = 0.0
            $sourceReportAccepted = $false
            $cleanupErrorMessage = $null
            $sourceStageSeconds = [ordered]@{
                preadmissionSeconds = $null; snapshotAndAdapterSeconds = $null; outputRelaySeconds = $null
                protectedReportReaderSeconds = $null; codeReportBindingSeconds = $null; cleanupSeconds = $null
            }
            $stageCollectionAssignment = @($sourceFunction.FindAll({
                param($node)
                $node -is [System.Management.Automation.Language.AssignmentStatementAst] -and $node.Left.Extent.Text -ceq '$sourceStageSeconds'
            }, $true))
            if ($stageCollectionAssignment.Count -eq 1) {
                . ([scriptblock]::Create($stageCollectionAssignment[0].Extent.Text))
            }
            $previousTestValidateSource = 'fixture prior value'
            $script:SourceTimingTestAdapterRoot = [IO.Path]::GetFullPath($paths.adapterRoot)
            $previousEnvironment = [Environment]::GetEnvironmentVariable('SYP154_TEST_VALIDATE_SOURCE', 'Process')
            [Environment]::SetEnvironmentVariable('SYP154_TEST_VALIDATE_SOURCE', $previousTestValidateSource, 'Process')
            $previousExitEnvironment = [Environment]::GetEnvironmentVariable('SYP326_SOURCE_TEST_EXIT_CODE', 'Process')
            $childExitCode = if ($Scenario -ceq 'nonzero') { '23' } else { '0' }
            [Environment]::SetEnvironmentVariable('SYP326_SOURCE_TEST_EXIT_CODE', $childExitCode, 'Process')
            $previousSourceRepository = $script:SourceRepository
            $previousSourceCleanupFailed = $script:SourceCleanupFailed
            $previousSourceInvalidInput = $script:SourceInvalidInput
            $script:SourceRepository = 'https://github.com/SyuanTsai/Skill-Code-Collaboration.git'
            $script:SourceCleanupFailed = $false
            $script:SourceInvalidInput = $false

            $errorText = $null
            $outerOutput = @()
            $functionRestoredTestValidateSource = $null
            try { $outerOutput = @(& ([scriptblock]::Create($outerTry[0].Extent.Text))) }
            catch { $errorText = $_.ToString() }
            finally {
                $functionRestoredTestValidateSource = [Environment]::GetEnvironmentVariable('SYP154_TEST_VALIDATE_SOURCE', 'Process')
                [Environment]::SetEnvironmentVariable('SYP154_TEST_VALIDATE_SOURCE', $previousEnvironment, 'Process')
                [Environment]::SetEnvironmentVariable('SYP326_SOURCE_TEST_EXIT_CODE', $previousExitEnvironment, 'Process')
            }
            $timingPath = Join-Path (Split-Path -Parent $paths.artifactsRoot) "source-validation-timing-$($fixture.runId).json"
            $receipt = if ([IO.File]::Exists($timingPath)) { Read-JsonFile -Path $timingPath -Context 'Source timing test receipt' } else { $null }
            $cleanupFailedAfterBlock = [bool]$script:SourceCleanupFailed
            $invalidInputAfterBlock = [bool]$script:SourceInvalidInput
            $script:SourceRepository = $previousSourceRepository
            $script:SourceCleanupFailed = $previousSourceCleanupFailed
            $script:SourceInvalidInput = $previousSourceInvalidInput
            return [pscustomobject]@{
                fixture = $fixture; prepared = $prepared; timingPath = [IO.Path]::GetFullPath($timingPath); receipt = $receipt
                artifactsRoot = $paths.artifactsRoot; adapterRoot = $paths.adapterRoot; errorText = $errorText; outerOutput = @($outerOutput)
                authorityRoot = $authorityRoot; authorityHead = $authorityRevision
                priorTestValidateSourceAfter = $functionRestoredTestValidateSource
                cleanupFailed = $cleanupFailedAfterBlock; invalidInput = $invalidInputAfterBlock
            }
        }

        function Invoke-SourcePreadmissionFailureForTest {
            param([Parameter(Mandatory)][string] $Root)
            $validatePath = Join-Path $script:RepositoryRoot 'scripts/Validate.ps1'
            $tokens = $null
            $parseErrors = $null
            $validateAst = [System.Management.Automation.Language.Parser]::ParseFile($validatePath, [ref]$tokens, [ref]$parseErrors)
            if (@($parseErrors).Count -gt 0) { throw 'Validate.ps1 did not parse for source pre-admission timing test.' }
            $sourceFunction = $validateAst.Find({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq 'Invoke-CodeSourceValidation' }, $true)
            if ($null -eq $sourceFunction) { throw 'Invoke-CodeSourceValidation was not found.' }
            . ([scriptblock]::Create($sourceFunction.Extent.Text))
            function Assert-CodeSourceAuthorityConfig { param($Config) throw 'fixture pre-admission authority rejection' }
            $candidateRoot = Join-Path $Root 'candidate'
            $artifactsRoot = Join-Path $Root 'artifacts'
            [void](New-Item -ItemType Directory -Path $candidateRoot -Force)
            $powerShellPath = [IO.Path]::GetFullPath([Diagnostics.Process]::GetCurrentProcess().MainModule.FileName)
            $gitPath = [IO.Path]::GetFullPath([string](Get-Command git -CommandType Application -ErrorAction Stop | Select-Object -First 1).Path)
            $authorityRoot = [IO.Path]::GetFullPath([string](Get-A031AuthoritySupervisorBinding).root)
            $script:SourceCleanupFailed = $false
            $script:SourceInvalidInput = $false
            $previousTestValidateSource = [Environment]::GetEnvironmentVariable('SYP154_TEST_VALIDATE_SOURCE', 'Process')
            [Environment]::SetEnvironmentVariable('SYP154_TEST_VALIDATE_SOURCE', 'fixture pre-admission value', 'Process')
            $failure = $null
            try {
                Invoke-CodeSourceValidation -GitPath $gitPath -PowerShellPath $powerShellPath -RepositoryRoot $candidateRoot `
                    -CandidateRevision ('a' * 40) -BaseRevision ('b' * 40) -AuthorityConfig ([pscustomobject]@{}) `
                    -SourceToolsPath (Join-Path $Root 'not-opened.json') -AuthorityRepositoryRoot $authorityRoot `
                    -TrustedToolRoot (Split-Path -Parent $powerShellPath) -ArtifactsRoot $artifactsRoot -EventName 'pull_request' -TimeoutSeconds 10800
            }
            catch { $failure = $_.ToString() }
            $functionPreservedTestValidateSource = [Environment]::GetEnvironmentVariable('SYP154_TEST_VALIDATE_SOURCE', 'Process')
            [Environment]::SetEnvironmentVariable('SYP154_TEST_VALIDATE_SOURCE', $previousTestValidateSource, 'Process')
            return [pscustomobject]@{
                failure = $failure; artifactsRootExists = [IO.Directory]::Exists($artifactsRoot)
                sourceReceiptFiles = @(Get-ChildItem -LiteralPath $Root -Filter 'source-validation-timing-*.json' -File -ErrorAction SilentlyContinue).Count
                cleanupFailed = [bool]$script:SourceCleanupFailed; invalidInput = [bool]$script:SourceInvalidInput
                functionPreservedTestValidateSource = $functionPreservedTestValidateSource
            }
        }

        function New-SourceResidentRouteFixtureForTest {
            param([Parameter(Mandatory)][string] $Root, [string] $AuthorityRoot)
            Import-Module -Name $script:DriverPath -Force
            $fullRoot = [IO.Path]::GetFullPath($Root)
            $source = New-SourceReportFixture -Root (Join-Path $fullRoot 'source')
            $candidateRoot = Join-Path $fullRoot 'candidate'
            [void](New-Item -ItemType Directory -Path $candidateRoot -Force)

            $pin = Get-PreparedSourceAuthorityPin -AuthorityRevision $source.fixture.authorityRevision
            $authorityConfig = New-SourceAuthorityConfigFixture -Pin $pin
            $authorityFixtureInput = [pscustomobject]@{
                candidateRoot = [IO.Path]::GetFullPath($candidateRoot)
                artifactsRoot = [IO.Path]::GetFullPath($source.artifactRoot)
                trustedToolRoot = [string]$source.fixture.prepared.pesterRuntime.sourceTrustedToolRoot
                prepared = $source.fixture.prepared
                baseRevision = [string]$source.baseRevision
            }
            $authorityFixture = $null
            if ([string]::IsNullOrWhiteSpace($AuthorityRoot)) {
                $authorityFixture = New-SourceResidentAuthorityModuleForTest -Fixture $authorityFixtureInput `
                    -AuthorityRevision ([string]$source.fixture.authorityRevision)
                if ($null -ne $authorityFixture.module) { Remove-Module -ModuleInfo $authorityFixture.module -Force -ErrorAction SilentlyContinue }
                $fixtureAuthorityRoot = [IO.Path]::GetFullPath([string]$authorityFixture.authority.root)
            }
            else {
                $fixtureAuthorityRoot = [IO.Path]::GetFullPath($AuthorityRoot)
                if (-not (Test-Path -LiteralPath $fixtureAuthorityRoot -PathType Container)) {
                    throw 'Reused resident route authority root must identify the already verified fixture checkout.'
                }
            }

            $report = $source.report
            $report.authority | Add-Member -NotePropertyName runnerSha256 `
                -NotePropertyValue ([string]$pin.files['scripts/Invoke-StandardValidation.ps1']) -Force
            $caseBinding = $report.sourceValidation.pesterCaseInventory
            $caseLedger = [pscustomobject]@{
                schemaVersion = 1
                report = 'standard-core-pester-case-inventory-v1'
                coreRunId = [string]$source.fixture.runId
                complete = $true
                terminalStatus = 'complete'
                caseDiscoveryCount = 1
                caseExecutionCount = 1
                reportedCounts = [pscustomobject]@{ Passed = 1; Failed = 0; Skipped = 0; Inconclusive = 0; NotRun = 0 }
                containerFileInventory = @([pscustomobject]@{ path = 'tests/fixture.ps1' })
            }
            $coreRunRoot = [IO.Path]::GetFullPath((Join-Path (Join-Path $source.artifactRoot 'runs') $source.fixture.runId))
            $eventsRoot = Join-Path $coreRunRoot 'events'
            $nativeRoot = Join-Path $coreRunRoot 'native'
            [void](New-Item -ItemType Directory -Path $eventsRoot -Force)
            [void](New-Item -ItemType Directory -Path $nativeRoot -Force)
            foreach ($event in @($report.sourceValidation.events)) {
                $previousEventPath = [string]$event.outputPath
                $eventRecord = Get-Content -LiteralPath $previousEventPath -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 60
                if ([string]$event.toolId -cne 'package-adapter') {
                    $envelope = ConvertFrom-Json -InputObject ([string]$eventRecord.stdout) -Depth 60
                    foreach ($native in @($envelope.nativeReports)) {
                        foreach ($fieldName in @('path', 'stdoutPath', 'stderrPath')) {
                            $previousNativePath = [string]$native.$fieldName
                            $nativePath = Join-Path $nativeRoot (Split-Path -Leaf $previousNativePath)
                            Copy-Item -LiteralPath $previousNativePath -Destination $nativePath
                            $native | Add-Member -NotePropertyName $fieldName -NotePropertyValue ([IO.Path]::GetFullPath($nativePath)) -Force
                        }
                    }
                    $eventRecord | Add-Member -NotePropertyName stdout -NotePropertyValue (($envelope | ConvertTo-Json -Depth 60 -Compress)) -Force
                }
                $eventPath = Join-Path $eventsRoot (Split-Path -Leaf $previousEventPath)
                [IO.File]::WriteAllText($eventPath, (($eventRecord | ConvertTo-Json -Depth 70 -Compress) + "`n"), [Text.UTF8Encoding]::new($false))
                $event.outputPath = [IO.Path]::GetFullPath($eventPath)
                $event.outputSha256 = Get-A031TextSha256 -Value ([string]$eventRecord.stdout + "`n---stderr---`n" + [string]$eventRecord.stderr)
            }
            $report.artifacts.runRoot = $coreRunRoot
            $caseBinding.path = Join-Path $coreRunRoot 'standard-core-pester-case-inventory-v1.json'
            [IO.File]::WriteAllText([string]$caseBinding.path, (($caseLedger | ConvertTo-Json -Depth 30 -Compress) + "`n"), [Text.UTF8Encoding]::new($false))
            $caseBinding.sha256 = Get-SourceBindingFixtureHash -Path ([string]$caseBinding.path)
            $reportPath = [IO.Path]::GetFullPath([string]$report.artifacts.outputPath)
            [IO.File]::WriteAllText($reportPath, (($report | ConvertTo-Json -Depth 80 -Compress) + "`n"), [Text.UTF8Encoding]::new($false))

            $timingPath = Join-Path (Split-Path -Parent ([string]$source.artifactRoot)) "source-validation-timing-$($source.fixture.runId).json"
            $timing = [pscustomobject]@{
                schemaVersion = 1
                runId = [string]$source.fixture.runId
                candidateRevision = [string]$source.fixture.candidateRevision
                baseRevision = [string]$source.baseRevision
                authorityRevision = [string]$source.fixture.authorityRevision
                processExitCode = 0
                reportAccepted = $true
                cleanupSucceeded = $true
                sourceValidationTotalSeconds = 0.1
            }
            [IO.File]::WriteAllText($timingPath, (($timing | ConvertTo-Json -Depth 20 -Compress) + "`n"), [Text.UTF8Encoding]::new($false))

            return [pscustomobject]@{
                root = $fullRoot
                protectedBaseRoot = $fullRoot
                source = $source
                prepared = $source.fixture.prepared
                preparedPath = $source.fixture.preparedPath
                candidateRoot = [IO.Path]::GetFullPath($candidateRoot)
                artifactsRoot = [IO.Path]::GetFullPath($source.artifactRoot)
                report = $report
                reportPath = $reportPath
                coreRunRoot = $coreRunRoot
                timing = $timing
                timingPath = [IO.Path]::GetFullPath($timingPath)
                caseLedger = $caseLedger
                caseLedgerPath = [IO.Path]::GetFullPath([string]$caseBinding.path)
                authorityPin = $pin
                authorityConfig = $authorityConfig
                authorityRoot = $fixtureAuthorityRoot
                gitPath = [string](Get-Command git -CommandType Application -ErrorAction Stop | Select-Object -First 1).Path
                evidenceRoot = [IO.Path]::GetFullPath((Join-Path (Split-Path -Parent $fullRoot) ("resident-evidence-$([guid]::NewGuid().ToString('N'))")))
            }
        }

        function New-SourceResidentSampleModuleForTest {
            param([int] $FailureCall = 0, [switch] $OmitCounters)
            $moduleName = 'SourceResidentTimingFixture_' + [guid]::NewGuid().ToString('N')
            return New-Module -Name $moduleName -ArgumentList $FailureCall, [bool]$OmitCounters -ScriptBlock {
                param([int] $FixtureFailureCall, [bool] $FixtureOmitCounters)
                $script:StandardValidationTimingEnabled = $false
                $script:StandardValidationTimingStage = 'validation'
                $script:StandardValidationClosureTiming = [pscustomobject]@{ before = 'closure' }
                $script:StandardValidationReadObserver = [pscustomobject]@{ before = 'observer' }
                $script:SourceResidentFixtureFailureCall = $FixtureFailureCall
                $script:SourceResidentFixtureOmitCounters = $FixtureOmitCounters
                $script:SourceResidentFixtureCalls = 0
                $script:SourceResidentFixtureArguments = [Collections.Generic.List[object]]::new()
                function Assert-StandardCoreSourceToolReceipts {
                    [CmdletBinding()]
                    param(
                        [object[]] $Bindings, [object[]] $FrozenFiles, [string] $RunId,
                        [string] $CandidateRoot, [string] $ArtifactsRoot,
                        [object] $RetainedReceiptMap, [string[]] $ToolNames = @(),
                        [string[]] $AdditionalPaths = @(), [switch] $ReturnReceiptMap
                    )
                    $script:SourceResidentFixtureCalls++
                    $script:SourceResidentFixtureArguments.Add([pscustomobject]@{
                        bindings = @($Bindings); frozenFiles = @($FrozenFiles); runId = $RunId
                        candidateRoot = $CandidateRoot; artifactsRoot = $ArtifactsRoot
                        mapRunId = [string]$RetainedReceiptMap.runId; toolNames = @($ToolNames)
                        additionalPaths = @($AdditionalPaths); returnReceiptMap = [bool]$ReturnReceiptMap
                    })
                    if (-not $script:SourceResidentFixtureOmitCounters) {
                        [Console]::Error.WriteLine((ConvertTo-Json -Compress -InputObject ([ordered]@{
                            stage = 'source-resident'; phase = 'source-integrity'; state = 'completed'
                            calls = 1; files = 3; bytes = 96; elapsedSeconds = 0.001
                        })))
                    }
                    if ($script:SourceResidentFixtureFailureCall -gt 0 -and $script:SourceResidentFixtureCalls -eq $script:SourceResidentFixtureFailureCall) {
                        [Console]::Error.WriteLine((ConvertTo-Json -Compress -InputObject ([ordered]@{
                            stage = 'source-resident'; phase = 'source-integrity'; state = 'failed'
                            calls = 1; files = 1; bytes = 4; elapsedSeconds = 0.001
                        })))
                        throw 'fixture retained receipt validation failure'
                    }
                    return $true
                }
                function Get-StandardCoreSourceToolGroups {
                    param([hashtable] $Receipts, [object[]] $FrozenFiles)
                    return [pscustomobject]@{ groups = @(); byTool = @{}; externalAssetsByTool = @{} }
                }
                function New-StandardValidationPhase {
                    param([string] $Stage, [string] $Phase, [switch] $Aggregate, [switch] $Silent)
                    return [pscustomobject]@{ stage = $Stage; phase = $Phase }
                }
                function Update-StandardValidationPhase { param($Timing, [long] $Calls, [long] $Files, [long] $Bytes) }
                function Complete-StandardValidationPhase { param($Timing, [string] $State) }
                Export-ModuleMember -Function @() -Cmdlet @() -Alias @() -Variable @()
            }
        }

        function New-SourceResidentActualRunnerForTest {
            param(
                [Parameter(Mandatory)][string] $Root,
                [Parameter(Mandatory)][string] $RunId,
                [Parameter(Mandatory)][string] $CandidateRevision,
                [Parameter(Mandatory)][string] $BaseRevision
            )
            Import-Module -Name $script:DriverPath -Force
            $validatePath = Join-Path $script:RepositoryRoot 'scripts/Validate.ps1'
            $tokens = $null
            $parseErrors = $null
            $validateAst = [System.Management.Automation.Language.Parser]::ParseFile($validatePath, [ref]$tokens, [ref]$parseErrors)
            if (@($parseErrors).Count -gt 0) { throw 'Validate.ps1 did not parse for resident runner fixture.' }
            $factoryAst = $validateAst.Find({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq 'New-CodeSourceStandardValidationModule' }, $true)
            if ($null -eq $factoryAst) { throw 'The production protected runner module factory is unavailable to the resident fixture.' }
            . ([scriptblock]::Create($factoryAst.Extent.Text))

            $fixtureRoot = [IO.Path]::GetFullPath($Root)
            $candidateRoot = Join-Path $fixtureRoot 'candidate'
            $artifactsRoot = Join-Path $fixtureRoot 'artifacts'
            $trustedToolRoot = Join-Path $fixtureRoot 'trusted-tools'
            foreach ($directory in @($candidateRoot, $artifactsRoot, $trustedToolRoot)) {
                [void](New-Item -ItemType Directory -Path $directory -Force)
            }
            $authorityFixture = New-SourceResidentAuthorityModuleForTest -Fixture ([pscustomobject]@{
                candidateRoot = [IO.Path]::GetFullPath($candidateRoot)
                artifactsRoot = [IO.Path]::GetFullPath($artifactsRoot)
                trustedToolRoot = [IO.Path]::GetFullPath($trustedToolRoot)
                prepared = [pscustomobject]@{ runId = $RunId; sourceRevision = $CandidateRevision }
                baseRevision = $BaseRevision
            }) -AuthorityRevision '8e627baf54bd6e47862e6291b25e71cc45a2f2b7'
            $authority = [pscustomobject]@{
                root = [string]$authorityFixture.authority.root
                revision = [string]$authorityFixture.authorityPin.commit
                path = [string]$authorityFixture.runnerPath
                sha256 = [string]$authorityFixture.runnerSha256
            }
            return [pscustomobject]@{
                module = $authorityFixture.module; authority = $authority; authorityPin = $authorityFixture.authorityPin
                candidateRoot = [IO.Path]::GetFullPath($candidateRoot)
                artifactsRoot = [IO.Path]::GetFullPath($artifactsRoot)
                trustedToolRoot = [IO.Path]::GetFullPath($trustedToolRoot)
            }
        }

        function New-SourceResidentAuthorityModuleForTest {
            param(
                [Parameter(Mandatory)] $Fixture,
                [Parameter(Mandatory)][string] $AuthorityRevision
            )
            Import-Module -Name $script:DriverPath -Force
            $functionNames = @(
                'Assert-CodeSourceAuthorityCheckout', 'Assert-NoReparseAncestors', 'Test-PathWithinOrEqual', 'Assert-PathWithinRoot',
                'Get-FileSha256', 'Get-GitBlobSha256', 'Get-ResolvedGitPath', 'Resolve-GitRevision', 'Test-PathEqual',
                'New-CodeSourceAuthoritySnapshot', 'New-CodeSourceStandardValidationModule'
            )
            $validatePath = Join-Path $script:RepositoryRoot 'scripts/Validate.ps1'
            $tokens = $null
            $parseErrors = $null
            $validateAst = [System.Management.Automation.Language.Parser]::ParseFile($validatePath, [ref]$tokens, [ref]$parseErrors)
            if (@($parseErrors).Count -gt 0) { throw 'Validate.ps1 did not parse for authority compatibility fixture.' }
            foreach ($functionName in $functionNames) {
                $functionAst = $validateAst.Find({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq $functionName }, $true)
                if ($null -eq $functionAst) { throw "The production authority function was not found: $functionName" }
                . ([scriptblock]::Create($functionAst.Extent.Text))
            }

            $authorityPin = Get-PreparedSourceAuthorityPin -AuthorityRevision $AuthorityRevision
            $gitPath = Get-ResolvedGitPath
            $activeAuthorityBinding = Get-A031AuthoritySupervisorBinding
            $activeConfigPath = Join-Path $script:RepositoryRoot 'config/standard-v1.json'
            $activeConfig = Get-Content -LiteralPath $activeConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 40 -ErrorAction Stop
            if ([string]$activeConfig.authority.commit -cne '8e627baf54bd6e47862e6291b25e71cc45a2f2b7' -or
                @($activeConfig.authority.files).Count -ne 32) {
                throw 'Resident authority fixture requires the exact configured 8e 32-file source pin.'
            }
            $activeAuthorityPin = Get-PreparedSourceAuthorityPin -AuthorityRevision ([string]$activeConfig.authority.commit)
            if ([string]$activeAuthorityBinding.revision -cne [string]$activeAuthorityPin.commit -or
                [string]$activeAuthorityBinding.sha256 -cne [string]$activeAuthorityPin.files['scripts/Invoke-StandardValidation.ps1']) {
                throw 'The configured resident authority checkout does not match its exact active 8e pin.'
            }
            $activeAuthority = Assert-CodeSourceAuthorityCheckout -GitPath $gitPath `
                -AuthorityRoot ([string]$activeAuthorityBinding.root) -AuthorityPin $activeAuthorityPin
            if ([string]$activeAuthority.revision -cne [string]$activeAuthorityPin.commit) {
                throw 'The configured resident authority checkout changed while it was being validated.'
            }

            if ([string]$authorityPin.commit -ceq [string]$activeAuthority.revision) {
                $authority = $activeAuthority
            }
            else {
                $artifactParent = Split-Path -Parent ([IO.Path]::GetFullPath([string]$Fixture.artifactsRoot))
                $authorityOwnedRoot = Join-Path $artifactParent ('.resident-authority-' + [guid]::NewGuid().ToString('N'))
                [void](New-Item -ItemType Directory -Path $authorityOwnedRoot -ErrorAction Stop)
                $authority = New-CodeSourceAuthoritySnapshot -GitPath $gitPath `
                    -SourceRoot ([string]$activeAuthority.root) -OwnedRoot $authorityOwnedRoot -AuthorityPin $authorityPin
            }
            $runnerSha256 = Get-FileSha256 -Path ([string]$authority.runnerPath)
            if ($runnerSha256 -cne [string]$authorityPin.files['scripts/Invoke-StandardValidation.ps1']) {
                throw 'Resident authority fixture runner does not match the selected authority pin.'
            }
            $runnerArguments = [ordered]@{
                CandidateRoot = [string]$Fixture.candidateRoot
                AdapterPath = Join-Path ([string]$Fixture.artifactsRoot) 'source-core-adapter.json'
                ArtifactsRoot = [string]$Fixture.artifactsRoot
                OutputPath = ''
                SourceRepository = [string]$authorityPin.repository
                SourceRevision = [string]$Fixture.prepared.sourceRevision
                BaseRevision = [string]$Fixture.baseRevision
                EventName = 'pull_request'
                RunId = [string]$Fixture.prepared.runId
                AuthorityRevision = [string]$authorityPin.commit
                TimeoutSeconds = 10800
                CancellationPath = ''
                TrustedToolRoot = [string]$Fixture.trustedToolRoot
            }
            $module = New-CodeSourceStandardValidationModule -RunnerPath ([string]$authority.runnerPath) `
                -RunnerSha256 $runnerSha256 -RunnerArguments $runnerArguments -SourceValidation
            return [pscustomobject]@{
                module = $module; authority = $authority; authorityPin = $authorityPin
                runnerPath = [IO.Path]::GetFullPath([string]$authority.runnerPath); runnerSha256 = $runnerSha256
            }
        }

        function New-SourceResidentSeriesFixtureForTest {
            param(
                [Parameter(Mandatory)][string] $Root,
                [int] $FailureSample = 0,
                [switch] $OmitSampleDiagnostics,
                [switch] $MalformedSampleDiagnostics,
                [ValidateSet('none','candidate','base','authority')][string] $TimingRevisionMismatch = 'none',
                [switch] $RejectReport,
                [switch] $TimingCleanupFailed,
                [ValidateSet('different-footprints','same-count-different-bytes','equal-footprints')][string] $FootprintMode = 'different-footprints',
                [switch] $ChangeFrozenFileOnLastSample,
                [switch] $AddUnfrozenFileOnLastSample
            )
            $runId = [guid]::NewGuid().ToString('N')
            $candidateRevision = 'd' * 40
            $baseRevision = 'e' * 40
            $runner = New-SourceResidentActualRunnerForTest -Root (Join-Path $Root 'runner') `
                -RunId $runId -CandidateRevision $candidateRevision -BaseRevision $baseRevision
            $module = $runner.module
            $ownedRoot = [IO.Path]::GetFullPath((Join-Path $Root "source-tools-$runId"))
            $smallRoot = Join-Path $ownedRoot 'installed/skill-validator'
            $largeRoot = Join-Path $ownedRoot 'installed/shared-tools'
            [void](New-Item -ItemType Directory -Path $smallRoot -Force)
            [void](New-Item -ItemType Directory -Path $largeRoot -Force)
            $launcherPath = Write-SourceBindingFixtureFile -Path (Join-Path $ownedRoot 'launchers/skill-validator.cmd') -Text '@echo off'
            $sharedPath = Write-SourceBindingFixtureFile -Path (Join-Path $ownedRoot 'shared/source-policy.json') -Text '{"fixture":true}'
            $toolPaths = @{
                'skill-validator' = @(Write-SourceBindingFixtureFile -Path (Join-Path $smallRoot 'skill-validator.bin') -Text 'validator')
                'skill-tools' = @(Write-SourceBindingFixtureFile -Path (Join-Path $largeRoot 'skill-tools.bin') -Text 'skill-tools')
                'skillspector' = @(Write-SourceBindingFixtureFile -Path (Join-Path $largeRoot 'skillspector.bin') -Text 'skillspector')
            }
            if ($FootprintMode -ceq 'same-count-different-bytes' -or $FootprintMode -ceq 'equal-footprints') {
                $smallExtraText = if ($FootprintMode -ceq 'equal-footprints') { '12345678901234' } else { 'extra small closure file' }
                $toolPaths['skill-validator'] += Write-SourceBindingFixtureFile -Path (Join-Path $smallRoot 'skill-validator-extra.dat') -Text $smallExtraText
            }
            if ($FootprintMode -ceq 'different-footprints') {
                $toolPaths['skill-tools'] += Write-SourceBindingFixtureFile -Path (Join-Path $largeRoot 'skill-tools-extra.dat') -Text 'extra closure file'
            }

            $receipts = [Collections.Hashtable]::new([StringComparer]::Ordinal)
            $bindings = [Collections.Hashtable]::new([StringComparer]::Ordinal)
            $receiptBindings = [Collections.Generic.List[object]]::new()
            $frozenFiles = [Collections.Generic.List[object]]::new()
            foreach ($toolName in @('skill-validator', 'skill-tools', 'skillspector')) {
                $installRoot = if ($toolName -ceq 'skill-validator') { $smallRoot } else { $largeRoot }
                $executablePath = [string]$toolPaths[$toolName][0]
                $launcher = [pscustomobject]@{
                    kind = 'fixture-launcher'; shimPath = ''; shimSha256 = ''
                    payloadPath = ''; payloadSha256 = ''; runtimePath = ''; runtimeSha256 = ''
                }
                if ($toolName -ceq 'skill-validator') {
                    $launcher.shimPath = $launcherPath
                    $launcher.shimSha256 = Get-SourceBindingFixtureHash -Path $launcherPath
                }
                $installedClosureSha256 = & $module {
                    param([string] $Root)
                    Get-StandardValidationDirectoryClosureSha256 -Root $Root -Context 'fixture installed closure'
                } ([IO.Path]::GetFullPath($installRoot))
                $receipt = [pscustomobject]@{
                    toolName = $toolName; resolutionRunId = $runId; frozenForRun = $true
                    installRoot = [IO.Path]::GetFullPath($installRoot)
                    executablePath = $executablePath; executableSha256 = Get-SourceBindingFixtureHash -Path $executablePath
                    launcher = $launcher; installedClosureSha256 = [string]$installedClosureSha256
                }
                $receipts[$toolName] = $receipt
                $receiptPath = Write-SourceBindingFixtureFile -Path (Join-Path $ownedRoot "receipt-$toolName.json") -Text (($receipt | ConvertTo-Json -Depth 20 -Compress) + "`n")
                $binding = [pscustomobject]@{ path = [IO.Path]::GetFullPath($receiptPath); sha256 = Get-SourceBindingFixtureHash -Path $receiptPath }
                $bindings[$toolName] = $binding
                $receiptBindings.Add($binding)
                $frozenFiles.Add($binding)
                foreach ($toolPath in $toolPaths[$toolName]) {
                    $frozenFiles.Add([pscustomobject]@{ path = [IO.Path]::GetFullPath([string]$toolPath); sha256 = Get-SourceBindingFixtureHash -Path ([string]$toolPath) })
                }
            }
            foreach ($path in @($sharedPath, $launcherPath)) {
                $frozenFiles.Add([pscustomobject]@{ path = [IO.Path]::GetFullPath($path); sha256 = Get-SourceBindingFixtureHash -Path $path })
            }
            $frozenInventory = [object[]]$frozenFiles.ToArray()
            $groups = & $module {
                param([hashtable] $ReceiptValues, [object[]] $FrozenValues)
                Get-StandardCoreSourceToolGroups -Receipts $ReceiptValues -FrozenFiles $FrozenValues
            } $receipts $frozenInventory
            $receiptMap = [pscustomobject]@{
                schemaVersion = 1; runId = $runId; receipts = $receipts; bindings = $bindings; groups = $groups
            }
            $wrapperPath = Write-SourceBindingFixtureFile -Path (Join-Path $ownedRoot 'Invoke-CodeCollaborationValidationChild.ps1') -Text 'param()'
            $toolchainPath = Write-SourceBindingFixtureFile -Path (Join-Path $ownedRoot 'toolchain.json') -Text '{"fixture":true}'
            $manifestPath = Write-SourceBindingFixtureFile -Path (Join-Path $ownedRoot 'candidate-git-entry-modes.json') -Text '{"entries":[]}'
            $dispatchCommand = [IO.Path]::GetFullPath([string][Environment]::ProcessPath)
            foreach ($path in @($wrapperPath, $toolchainPath, $manifestPath, $dispatchCommand, [string]$runner.authority.path)) {
                if (@($frozenInventory | Where-Object { [IO.Path]::GetFullPath([string]$_.path).Equals([IO.Path]::GetFullPath($path), [StringComparison]::OrdinalIgnoreCase) }).Count -eq 0) {
                    $frozenFiles.Add([pscustomobject]@{ path = [IO.Path]::GetFullPath($path); sha256 = Get-SourceBindingFixtureHash -Path $path })
                }
            }
            $frozenInventory = [object[]]$frozenFiles.ToArray()
            $commonArguments = @('-NoProfile', '-NonInteractive', '-File', $wrapperPath, '-ToolchainPath', $toolchainPath,
                '-ToolchainSha256', (Get-SourceBindingFixtureHash -Path $toolchainPath), '-GitEntryModeManifestPath', $manifestPath,
                '-GitEntryModeManifestSha256', (Get-SourceBindingFixtureHash -Path $manifestPath))
            $preparedSourceValidation = [pscustomobject]@{
                packageAdapter = [pscustomobject]@{ command = $dispatchCommand; arguments = @($commonArguments + @('-Mode', 'package-adapter')) }
                skillValidator = [pscustomobject]@{ command = $dispatchCommand; arguments = @($commonArguments + @('-Mode', 'skill-validator')) }
                skillTools = [pscustomobject]@{ command = $dispatchCommand; arguments = @($commonArguments + @('-Mode', 'skill-tools')) }
                staticAnalyzer = [pscustomobject]@{ command = $dispatchCommand; arguments = @($commonArguments + @('-Mode', 'static')) }
                frozenFiles = $frozenInventory; toolReceipts = [object[]]$receiptBindings.ToArray()
            }
            $prepared = [pscustomobject]@{
                schemaVersion = 1; preparation = 'code-collaboration-source-tools'; runId = $runId
                sourceRevision = $candidateRevision; authorityRevision = [string]$runner.authorityPin.commit
                ownedRoot = $ownedRoot; sourceValidation = $preparedSourceValidation
            }
            $coreRunRoot = [IO.Path]::GetFullPath((Join-Path (Join-Path $runner.artifactsRoot 'runs') $runId))
            [void](New-Item -ItemType Directory -Path $coreRunRoot -Force)
            $snapshotRoot = Join-Path $coreRunRoot 'candidate'
            [void](New-Item -ItemType Directory -Path $snapshotRoot -Force)
            $caseLedgerPath = Write-SourceBindingFixtureFile -Path (Join-Path $coreRunRoot 'repository-pester-case-inventory-v1.json') -Text '{}'
            $caseLedger = [pscustomobject]@{
                schemaVersion = 1; report = 'standard-core-pester-case-inventory-v1'; coreRunId = $runId
                complete = $true; terminalStatus = 'complete'; caseDiscoveryCount = 1; caseExecutionCount = 1
                reportedCounts = [pscustomobject]@{ Passed = 1; Failed = 0; Skipped = 0; Inconclusive = 0; NotRun = 0 }
                containerFileInventory = @([pscustomobject]@{ path = 'tests/fixture.ps1' })
            }
            [IO.File]::WriteAllText($caseLedgerPath, (($caseLedger | ConvertTo-Json -Depth 20 -Compress) + "`n"), [Text.UTF8Encoding]::new($false))
            $caseLedgerSha256 = Get-SourceBindingFixtureHash -Path $caseLedgerPath
            $reportSourceValidation = [pscustomobject]@{
                status = 'passed'; runId = $runId; candidateId = 'a' * 64; sourceRevision = $candidateRevision
                contentSha256 = 'b' * 64; authorityRevision = [string]$runner.authorityPin.commit
                activeSkills = @('fixture'); skillsRoot = 'skills'; toolReceipts = [object[]]$receiptBindings.ToArray()
                frozenFiles = $frozenInventory; events = @(); adapterSnapshot = [pscustomobject]@{ path = 'adapter.json'; sha256 = 'c' * 64 }
                pesterCaseInventory = [pscustomobject]@{ path = $caseLedgerPath; sha256 = $caseLedgerSha256 }
            }
            $reportPath = Write-SourceBindingFixtureFile -Path (Join-Path $runner.artifactsRoot 'standard-core-validation-v2-report.json') -Text '{"state":"PASS","fixture":true}'
            $report = [pscustomobject]@{
                schemaVersion = 2; state = 'PASS'; exitCode = 0; releaseEligible = $false; contentMode = 'immutable-source'; runId = $runId
                candidate = [pscustomobject]@{ sourceRevision = $candidateRevision; baseRevision = $baseRevision; eventName = 'pull_request' }
                authority = [pscustomobject]@{ revision = [string]$runner.authorityPin.commit; runnerSha256 = [string]$runner.authority.sha256 }
                artifacts = [pscustomobject]@{ root = $runner.artifactsRoot; outputPath = $reportPath; runId = $runId; runRoot = $coreRunRoot; snapshotRoot = $snapshotRoot }
                sourceValidation = $reportSourceValidation
                checks = @(
                    [pscustomobject]@{ kind = 'general'; status = 'passed'; exitCode = 0; cleanedUp = $true }
                    [pscustomobject]@{ kind = 'pester'; status = 'passed'; exitCode = 0; cleanedUp = $true }
                )
            }
            if ($RejectReport) { $report.state = 'FAIL'; $report.exitCode = 1 }
            [void](Write-SourceBindingFixtureFile -Path (Join-Path $Root 'prepared.json') -Text (($prepared | ConvertTo-Json -Depth 40 -Compress) + "`n"))
            [void][IO.File]::WriteAllText($reportPath, (($report | ConvertTo-Json -Depth 40 -Compress) + "`n"), [Text.UTF8Encoding]::new($false))
            $timingEvidence = [pscustomobject]@{
                schemaVersion = 1; runId = $runId
                candidateRevision = if ($TimingRevisionMismatch -ceq 'candidate') { 'f' * 40 } else { $candidateRevision }
                baseRevision = if ($TimingRevisionMismatch -ceq 'base') { 'a' * 40 } else { $baseRevision }
                authorityRevision = if ($TimingRevisionMismatch -ceq 'authority') { 'b' * 40 } else { [string]$runner.authorityPin.commit }
                processExitCode = 0; reportAccepted = $true
                cleanupSucceeded = (-not $TimingCleanupFailed); sourceValidationTotalSeconds = 0.01
            }
            $timingEvidencePath = Write-SourceBindingFixtureFile -Path (Join-Path $Root 'source-validation-timing.json') `
                -Text (($timingEvidence | ConvertTo-Json -Depth 20 -Compress) + "`n")
            $evidenceRoot = [IO.Path]::GetFullPath((Join-Path $Root 'resident-evidence'))
            $mutationPath = if ($ChangeFrozenFileOnLastSample) { [string]$frozenInventory[0].path } else { '' }
            $addPath = if ($AddUnfrozenFileOnLastSample) { Join-Path $smallRoot 'post-sample-unfrozen-extra.bin' } else { '' }
            & $module {
                param($Map, [int] $FailureCall, [bool] $OmitDiagnostics, [bool] $MalformedDiagnostics, [string] $ChangePath, [string] $AddPath)
                $script:SourceResidentFixtureMap = $Map
                $script:SourceResidentFixtureFailureCall = $FailureCall
                $script:SourceResidentFixtureOmitDiagnostics = $OmitDiagnostics
                $script:SourceResidentFixtureMalformedDiagnostics = $MalformedDiagnostics
                $script:SourceResidentFixtureChangePath = $ChangePath
                $script:SourceResidentFixtureAddPath = $AddPath
                $script:SourceResidentFixtureCalls = 0
                $script:SourceResidentFixtureFullReceiptChecks = 0
                $script:SourceResidentFixtureArguments = [Collections.Generic.List[object]]::new()
                function Assert-StandardCoreSourceToolReceipts {
                    [CmdletBinding()]
                    param(
                        [object[]] $Bindings, [object[]] $FrozenFiles, [string] $RunId,
                        [string] $CandidateRoot, [string] $ArtifactsRoot,
                        [object] $RetainedReceiptMap, [string[]] $ToolNames = @(),
                        [string[]] $AdditionalPaths = @(), [switch] $ReturnReceiptMap
                    )
                    if ($null -eq $RetainedReceiptMap -and $ReturnReceiptMap) { return $script:SourceResidentFixtureMap }
                    if ($null -eq $RetainedReceiptMap) {
                        if (-not $ReturnReceiptMap -and @($ToolNames).Count -eq 0) {
                            $script:SourceResidentFixtureFullReceiptChecks++
                            Assert-StandardCoreFrozenFiles -Files $FrozenFiles
                            foreach ($binding in $Bindings) {
                                if ((Get-StandardValidationFileSha256 -Path ([string]$binding.path) -Context 'fixture full receipt binding') -cne [string]$binding.sha256) {
                                    throw 'fixture full source receipt binding changed'
                                }
                            }
                            foreach ($receipt in $script:SourceResidentFixtureMap.receipts.Values) {
                                $closureSha256 = Get-StandardValidationDirectoryClosureSha256 -Root ([string]$receipt.installRoot) -Context 'fixture full installed closure'
                                if ([string]$closureSha256 -cne [string]$receipt.installedClosureSha256) {
                                    throw 'fixture full receipt admission found an installed closure change'
                                }
                            }
                            $afterPostflightReceipt = Get-Variable -Name SourceResidentFixtureAfterPostflightReceipt -Scope Script -ErrorAction SilentlyContinue
                            if ($null -ne $afterPostflightReceipt -and $afterPostflightReceipt.Value -is [scriptblock]) {
                                & $afterPostflightReceipt.Value ([string]$script:StandardValidationTimingStage) ([int]$script:SourceResidentFixtureFullReceiptChecks)
                            }
                        }
                        return $true
                    }
                    if (@($ToolNames).Count -eq 0 -and -not $ReturnReceiptMap) { return $true }

                    $script:SourceResidentFixtureCalls++
                    $script:SourceResidentFixtureArguments.Add([pscustomobject]@{
                        moduleName = [string]$ExecutionContext.SessionState.Module.Name
                        bindings = @($Bindings); frozenFiles = @($FrozenFiles); runId = $RunId
                        candidateRoot = $CandidateRoot; artifactsRoot = $ArtifactsRoot
                        mapRunId = [string]$RetainedReceiptMap.runId; toolNames = @($ToolNames)
                        additionalPaths = @($AdditionalPaths); returnReceiptMap = [bool]$ReturnReceiptMap
                        timingStage = [string]$script:StandardValidationTimingStage
                    })
                    $sampleTiming = $null
                    $receiptTiming = $null
                    $sampleState = 'completed'
                    $previousTimingEnabled = [bool]$script:StandardValidationTimingEnabled
                    try {
                        if ($script:SourceResidentFixtureOmitDiagnostics) { $script:StandardValidationTimingEnabled = $false }
                        $sampleTiming = New-StandardValidationPhase -Stage $script:StandardValidationTimingStage -Phase 'source-integrity' `
                            -Silent:(-not $script:StandardValidationTimingEnabled)
                        $receiptTiming = New-StandardValidationPhase -Stage $script:StandardValidationTimingStage -Phase 'source-receipt-bytes' `
                            -Aggregate -Silent:(-not $script:StandardValidationTimingEnabled)
                        foreach ($binding in $Bindings) {
                            $receiptItem = Get-Item -LiteralPath ([string]$binding.path) -Force -ErrorAction Stop
                            if ((Get-StandardValidationFileSha256 -Path ([string]$binding.path) -Context 'fixture retained source receipt') -cne [string]$binding.sha256) {
                                throw 'fixture retained source receipt bytes changed'
                            }
                            Update-StandardValidationPhase -Timing $receiptTiming -Calls 1 -Files 1 -Bytes ([long]$receiptItem.Length)
                        }
                        Complete-StandardValidationPhase -Timing $receiptTiming -State 'completed'
                        $receiptTiming = $null

                        $sampleFileMap = [Collections.Generic.Dictionary[string,object]]::new([StringComparer]::OrdinalIgnoreCase)
                        $addSampleFile = {
                            param($File)
                            if ($null -eq $File) { return }
                            $fullFilePath = [IO.Path]::GetFullPath([string]$File.path)
                            $key = $fullFilePath.ToUpperInvariant()
                            if ($sampleFileMap.ContainsKey($key)) { return }
                            $matches = @($FrozenFiles | Where-Object {
                                [IO.Path]::GetFullPath([string]$_.path).Equals($fullFilePath, [StringComparison]::OrdinalIgnoreCase)
                            })
                            if ($matches.Count -ne 1) { throw 'fixture sample path is not frozen exactly once' }
                            $sampleFileMap.Add($key, $matches[0])
                        }
                        $selectedGroups = [Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal)
                        foreach ($name in $ToolNames) {
                            $selectedGroup = $RetainedReceiptMap.groups.byTool[[string]$name]
                            $selectedGroups[[string]$selectedGroup.id] = $selectedGroup
                        }
                        foreach ($selectedGroup in $selectedGroups.Values) {
                            foreach ($file in @($selectedGroup.rootFiles) + @($selectedGroup.externalAssets)) { & $addSampleFile $file }
                        }
                        foreach ($file in @($RetainedReceiptMap.groups.byTool['skill-validator'].sharedFiles)) { & $addSampleFile $file }
                        foreach ($pathValue in $AdditionalPaths) {
                            $pathFull = [IO.Path]::GetFullPath([string]$pathValue)
                            $matches = @($FrozenFiles | Where-Object {
                                [IO.Path]::GetFullPath([string]$_.path).Equals($pathFull, [StringComparison]::OrdinalIgnoreCase)
                            })
                            if ($matches.Count -ne 1) { throw 'fixture sample dispatch path is not frozen exactly once' }
                            & $addSampleFile $matches[0]
                        }
                        Assert-StandardCoreFrozenFiles -Files @($sampleFileMap.Values)
                        foreach ($selectedGroup in $selectedGroups.Values) {
                            foreach ($root in @($selectedGroup.roots | Sort-Object -Unique -CaseSensitive)) {
                                [void](Get-StandardValidationDirectoryClosureSha256 -Root ([string]$root) -Context 'fixture retained source closure')
                            }
                        }
                        if ($script:SourceResidentFixtureMalformedDiagnostics -and $script:SourceResidentFixtureCalls -eq 1) {
                            [Console]::Error.WriteLine('[StandardValidation timing] {"stage":"source-resident-sample","phase":"fixture-malformed","state":"completed","calls":"not-a-number","files":0,"bytes":0,"elapsedSeconds":0.0}')
                        }
                        if ($script:SourceResidentFixtureFailureCall -eq $script:SourceResidentFixtureCalls) {
                            throw 'fixture retained source receipt validation failure'
                        }
                        if ($script:SourceResidentFixtureCalls -eq 6 -and -not [string]::IsNullOrWhiteSpace($script:SourceResidentFixtureChangePath)) {
                            [IO.File]::WriteAllText($script:SourceResidentFixtureChangePath, 'changed after resident samples', [Text.UTF8Encoding]::new($false))
                        }
                        if ($script:SourceResidentFixtureCalls -eq 6 -and -not [string]::IsNullOrWhiteSpace($script:SourceResidentFixtureAddPath)) {
                            [IO.File]::WriteAllText($script:SourceResidentFixtureAddPath, 'added after resident samples', [Text.UTF8Encoding]::new($false))
                        }
                    }
                    catch {
                        $sampleState = 'failed'
                        throw
                    }
                    finally {
                        if ($null -ne $receiptTiming) { Complete-StandardValidationPhase -Timing $receiptTiming -State $sampleState }
                        if ($null -ne $sampleTiming) { Complete-StandardValidationPhase -Timing $sampleTiming -State $sampleState }
                        $script:StandardValidationTimingEnabled = $previousTimingEnabled
                    }
                    return $RetainedReceiptMap
                }
                Set-Item -Path Function:script:Assert-StandardCoreSourceToolReceipts -Value (Get-Item -Path Function:Assert-StandardCoreSourceToolReceipts).ScriptBlock
                Export-ModuleMember -Function @() -Cmdlet @() -Alias @() -Variable @()
            } $receiptMap $FailureSample ([bool]$OmitSampleDiagnostics) ([bool]$MalformedSampleDiagnostics) $mutationPath $addPath
            & $module {
                $script:StandardValidationTimingEnabled = $true
                $script:StandardValidationTimingStage = 'fixture-original-stage'
                $script:StandardValidationClosureTiming = [pscustomobject]@{ marker = 'closure-before' }
                $script:StandardValidationReadObserver = [pscustomobject]@{ marker = 'observer-before' }
            }
            return [pscustomobject]@{
                module = $module; authority = $runner.authority; authorityPin = $runner.authorityPin
                runnerPath = [string]$runner.authority.path; runnerSha256 = [string]$runner.authority.sha256
                prepared = $prepared; report = $report; timingEvidence = $timingEvidence; caseLedger = $caseLedger
                preparedPath = [IO.Path]::GetFullPath((Join-Path $Root 'prepared.json'))
                timingEvidencePath = $timingEvidencePath; caseLedgerPath = $caseLedgerPath
                candidateRoot = $runner.candidateRoot; baseRevision = $baseRevision; artifactsRoot = $runner.artifactsRoot
                trustedToolRoot = $runner.trustedToolRoot
                reportPath = $reportPath; reportSha256 = Get-SourceBindingFixtureHash -Path $reportPath
                frozenFiles = $frozenInventory; receiptMap = $receiptMap; evidenceRoot = $evidenceRoot
                sharedPath = $sharedPath; launcherPath = $launcherPath; mutationPath = $mutationPath; addPath = $addPath
                cancellationPath = Join-Path $Root 'cancel-resident.json'
            }
        }

        function Get-SourceResidentModuleStateForTest {
            param([Parameter(Mandatory)][System.Management.Automation.PSModuleInfo] $Module)
            return & $Module {
                $enabledVariable = Get-Variable -Name StandardValidationTimingEnabled -Scope Script -ErrorAction SilentlyContinue
                $stageVariable = Get-Variable -Name StandardValidationTimingStage -Scope Script -ErrorAction SilentlyContinue
                $closureVariable = Get-Variable -Name StandardValidationClosureTiming -Scope Script -ErrorAction SilentlyContinue
                $observerVariable = Get-Variable -Name StandardValidationReadObserver -Scope Script -ErrorAction SilentlyContinue
                [pscustomobject]@{
                    enabledPresent = ($null -ne $enabledVariable)
                    enabled = if ($null -eq $enabledVariable) { $null } else { [bool]$enabledVariable.Value }
                    stagePresent = ($null -ne $stageVariable)
                    stage = if ($null -eq $stageVariable) { $null } else { [string]$stageVariable.Value }
                    closurePresent = ($null -ne $closureVariable)
                    closure = if ($null -eq $closureVariable) { $null } else { $closureVariable.Value }
                    readObserverPresent = ($null -ne $observerVariable)
                    readObserver = if ($null -eq $observerVariable) { $null } else { $observerVariable.Value }
                }
            }
        }

        function Invoke-SourceResidentSeriesForTest {
            param([Parameter(Mandatory)] $Fixture, [string] $CancellationPath, [ValidateSet('Flush', 'Dispose', 'PersistentDispose')][string] $SinkFaultMode)
            $validatePath = Join-Path $script:RepositoryRoot 'scripts/Validate.ps1'
            $tokens = $null
            $parseErrors = $null
            $validateAst = [System.Management.Automation.Language.Parser]::ParseFile($validatePath, [ref]$tokens, [ref]$parseErrors)
            if (@($parseErrors).Count -gt 0) { throw 'Validate.ps1 did not parse for resident sample behavior test.' }
            foreach ($functionName in @(
                'Get-CodeSourceResidentCaseCountValues', 'Get-CodeSourceResidentRetainedApiContract', 'Invoke-CodeSourceStandardValidationModule',
                'Invoke-CodeSourceResidentSampleSeries'
            )) {
                $functionAst = $validateAst.Find({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq $functionName }, $true)
                if ($null -eq $functionAst) { throw "The production resident sample function is unavailable: $functionName" }
                $functionText = [string]$functionAst.Extent.Text
                if ($functionName -ceq 'Invoke-CodeSourceResidentSampleSeries' -and -not [string]::IsNullOrWhiteSpace($SinkFaultMode)) {
                    $openExpression = '$rawStream = [IO.File]::Open($rawPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::Read)'
                    $faultExpression = '$rawStream = New-SourceResidentControlledFaultStreamForTest -Path $rawPath -Mode ' + "'" + $SinkFaultMode + "'"
                    $replacementCount = [regex]::Matches($functionText, [regex]::Escape($openExpression)).Count
                    if ($replacementCount -ne 1) { throw "Expected exactly one raw stream factory expression to replace; found $replacementCount." }
                    $faultFunctionText = $functionText.Replace($openExpression, $faultExpression)
                    if ($faultFunctionText.Replace($faultExpression, $openExpression) -cne $functionText) {
                        throw 'The controlled stream substitution changed text outside the single raw stream factory expression.'
                    }
                    $script:SourceResidentSinkFaultAstProofForTest = [pscustomobject]@{
                        functionName = $functionName
                        replacementCount = $replacementCount
                        originalFunctionSha256 = Get-A031TextSha256 -Value $functionText
                        substitutedFunctionSha256 = Get-A031TextSha256 -Value $faultFunctionText
                        originalExpression = $openExpression
                        substitutedExpression = $faultExpression
                        reversibleSingleExpressionReplacement = $true
                        streamWriterConstructionUnchanged = $faultFunctionText.Contains('$rawWriter = [IO.StreamWriter]::new($rawStream, [Text.UTF8Encoding]::new($false)')
                        autoFlushUnchanged = $faultFunctionText.Contains('$rawWriter.AutoFlush = $true')
                    }
                    $functionText = $faultFunctionText
                }
                . ([scriptblock]::Create($functionText))
            }
            if ($SinkFaultMode -ceq 'PersistentDispose') {
                $script:SourceResidentSinkFaultContractForTest = Get-CodeSourceResidentRetainedApiContract -Module $Fixture.module
            }
            $arguments = @{
                Module = $Fixture.module; Prepared = $Fixture.prepared; Report = $Fixture.report
                TimingEvidence = $Fixture.timingEvidence; CaseLedger = $Fixture.caseLedger
                PreparedPath = $Fixture.preparedPath; TimingEvidencePath = $Fixture.timingEvidencePath
                CaseLedgerPath = $Fixture.caseLedgerPath
                AuthorityPin = $Fixture.authorityPin; RunnerPath = $Fixture.runnerPath; RunnerSha256 = $Fixture.runnerSha256
                RepositoryRoot = $script:RepositoryRoot; CandidateRoot = $Fixture.candidateRoot; BaseRevision = $Fixture.baseRevision
                ArtifactsRoot = $Fixture.artifactsRoot; EvidenceRoot = $Fixture.evidenceRoot
            }
            if (-not [string]::IsNullOrWhiteSpace($CancellationPath)) { $arguments.CancellationPath = $CancellationPath }
            return Invoke-CodeSourceResidentSampleSeries @arguments
        }

        function New-SourceResidentControlledFaultStreamForTest {
            param([Parameter(Mandatory)][string] $Path, [Parameter(Mandatory)][ValidateSet('Flush', 'Dispose', 'PersistentDispose')][string] $Mode)
            if ($null -eq ('Syp326.Testing.SourceResidentFaultStream' -as [type])) {
                $source = @'
using System;
using System.Collections.Generic;
using System.IO;
using System.Text;

namespace Syp326.Testing
{
    public sealed class SourceResidentFaultStream : Stream
    {
        private static SourceResidentFaultStream _latest;
        private readonly Stream _inner;
        private readonly string _mode;
        private readonly List<string> _events = new List<string>();
        private int _ordinal;
        private bool _armed;
        private bool _faultThrown;
        private string _stage = "unarmed";
        private int _fullReceiptChecks;

        public SourceResidentFaultStream(Stream inner, string mode)
        {
            _inner = inner ?? throw new ArgumentNullException(nameof(inner));
            _mode = mode ?? throw new ArgumentNullException(nameof(mode));
            _latest = this;
            Record("create", "", null);
        }

        public static SourceResidentFaultStream Latest { get { return _latest; } }
        public static void ArmLatest(string stage, int fullReceiptChecks)
        {
            if (_latest == null) throw new InvalidOperationException("No controlled stream has been created.");
            _latest.Arm(stage, fullReceiptChecks);
        }

        public List<string> Events { get { return _events; } }
        public string Mode { get { return _mode; } }
        public bool Armed { get { return _armed; } }
        public bool FaultThrown { get { return _faultThrown; } }
        public bool UnderlyingClosed { get; private set; }
        public string Stage { get { return _stage; } }
        public int FullReceiptChecks { get { return _fullReceiptChecks; } }

        public void Arm(string stage, int fullReceiptChecks)
        {
            if (_armed) throw new InvalidOperationException("The controlled stream was armed more than once.");
            _armed = true;
            _stage = stage ?? "";
            _fullReceiptChecks = fullReceiptChecks;
            Record("arm", "", null);
        }

        private static string Escape(string value)
        {
            return (value ?? "").Replace("\\", "\\\\").Replace("\"", "\\\"").Replace("\r", "\\r").Replace("\n", "\\n");
        }

        private void Record(string eventName, string detail, Exception exception)
        {
            int ordinal = ++_ordinal;
            string type = exception == null ? "" : exception.GetType().FullName;
            string message = exception == null ? "" : exception.Message;
            string line = "{\"ordinal\":" + ordinal.ToString(System.Globalization.CultureInfo.InvariantCulture) +
                ",\"event\":\"" + Escape(eventName) + "\",\"detail\":\"" + Escape(detail) +
                "\",\"mode\":\"" + Escape(_mode) + "\",\"stage\":\"" + Escape(_stage) +
                "\",\"armed\":" + (_armed ? "true" : "false") +
                ",\"fullReceiptChecks\":" + _fullReceiptChecks.ToString(System.Globalization.CultureInfo.InvariantCulture) +
                ",\"exceptionType\":\"" + Escape(type) + "\",\"exceptionMessage\":\"" + Escape(message) + "\"}" + Environment.NewLine;
            _events.Add(line.TrimEnd('\r', '\n'));
            string tracePath = Environment.GetEnvironmentVariable("SYP326_SINK_FAULT_TRACE_PATH");
            if (!String.IsNullOrWhiteSpace(tracePath)) File.AppendAllText(tracePath, line, new UTF8Encoding(false));
        }

        public override bool CanRead { get { return _inner.CanRead; } }
        public override bool CanSeek { get { return _inner.CanSeek; } }
        public override bool CanWrite { get { return _inner.CanWrite; } }
        public override long Length { get { return _inner.Length; } }
        public override long Position { get { return _inner.Position; } set { _inner.Position = value; } }
        public override long Seek(long offset, SeekOrigin origin) { return _inner.Seek(offset, origin); }
        public override void SetLength(long value) { _inner.SetLength(value); }
        public override int Read(byte[] buffer, int offset, int count) { return _inner.Read(buffer, offset, count); }

        public override void Write(byte[] buffer, int offset, int count)
        {
            Record("write", "count=" + count.ToString(System.Globalization.CultureInfo.InvariantCulture), null);
            _inner.Write(buffer, offset, count);
        }

        public override void Flush()
        {
            if (_armed && _mode == "Flush" && !_faultThrown)
            {
                _faultThrown = true;
                IOException failure = new IOException("controlled sink Flush fault");
                Record("flush", "throw", failure);
                throw failure;
            }
            if (_mode != "PersistentDispose" || !_armed || !UnderlyingClosed) _inner.Flush();
            Record("flush", "completed", null);
        }

        protected override void Dispose(bool disposing)
        {
            if (!disposing) { base.Dispose(disposing); return; }
            Exception failure = null;
            if (_armed && (_mode == "PersistentDispose" || (_mode == "Dispose" && !_faultThrown)))
            {
                _faultThrown = true;
                failure = new IOException(_mode == "PersistentDispose" ? "controlled persistent sink Dispose fault" : "controlled sink Dispose fault");
                Record("dispose", "throw", failure);
            }
            else { Record("dispose", "completed", null); }
            try { _inner.Dispose(); }
            finally
            {
                UnderlyingClosed = true;
                base.Dispose(disposing);
            }
            if (failure != null) throw failure;
        }
    }
}
'@
                Add-Type -TypeDefinition $source -Language CSharp -ErrorAction Stop
            }
            $inner = [IO.File]::Open($Path, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::Read)
            $stream = [Syp326.Testing.SourceResidentFaultStream]::new($inner, $Mode)
            $script:SourceResidentFaultStreamForTest = $stream
            if ($Mode -ceq 'PersistentDispose') {
                [Syp326.Testing.SourceResidentFaultStream]::ArmLatest('source-resident-unsupported-open', 0)
            }
            return $stream
        }

        function Invoke-SourceResidentSinkFaultCaseForTest {
            param([Parameter(Mandatory)][string] $Mode, [int] $FailureSample = 0)
            $root = Join-Path $TestDrive ("source-resident-sink-fault-{0}-{1}" -f $Mode, [guid]::NewGuid().ToString('N'))
            $fixture = $null
            $savedConsoleError = [Console]::Error
            $beforeState = $null
            $afterState = $null
            $result = $null
            $invocationError = $null
            $script:SourceResidentFaultStreamForTest = $null
            $script:SourceResidentSinkFaultAstProofForTest = $null
            $script:SourceResidentSinkFaultContractForTest = $null
            try {
                $fixture = New-SourceResidentSeriesFixtureForTest -Root $root -FailureSample $FailureSample
                $beforeState = Get-SourceResidentModuleStateForTest -Module $fixture.module
                $armAction = {
                    param($stage, $fullReceiptChecks)
                    if ([string]$stage -cne 'source-resident-postflight' -or [int]$fullReceiptChecks -ne 1) {
                        throw 'The controlled stream fault was armed outside the final complete postflight receipt check.'
                    }
                    [Syp326.Testing.SourceResidentFaultStream]::ArmLatest([string]$stage, [int]$fullReceiptChecks)
                }.GetNewClosure()
                & $fixture.module { param($Action) $script:SourceResidentFixtureAfterPostflightReceipt = $Action } $armAction
                try { $result = Invoke-SourceResidentSeriesForTest -Fixture $fixture -SinkFaultMode $Mode }
                catch { $invocationError = $_.Exception.Message }
                $afterState = Get-SourceResidentModuleStateForTest -Module $fixture.module
                $consoleRestored = [object]::ReferenceEquals([Console]::Error, $savedConsoleError)
                $stream = [Syp326.Testing.SourceResidentFaultStream]::Latest
                $stateRestoredExactly = $null -ne $beforeState -and $null -ne $afterState -and
                    [bool]$afterState.enabled -eq [bool]$beforeState.enabled -and
                    [string]$afterState.stage -ceq [string]$beforeState.stage -and
                    [object]::ReferenceEquals($afterState.closure, $beforeState.closure) -and
                    [object]::ReferenceEquals($afterState.readObserver, $beforeState.readObserver)
                $evidence = [ordered]@{
                    case = if ($FailureSample -gt 0) { 'sample-error-plus-flush' } else { $Mode.ToLowerInvariant() }
                    mode = $Mode; failureSample = $FailureSample; invocationError = $invocationError
                    result = if ($null -eq $result) { $null } else { [ordered]@{
                        complete = $result.complete; status = $result.status; reason = $result.reason; message = $result.message
                        sampleCount = $result.sampleCount; sampleDiagnosticErrors = @($result.sampleDiagnosticErrors)
                        postflightErrors = @($result.postflightErrors)
                        cleanupErrors = if ($null -eq $result.PSObject.Properties['cleanupErrors']) { @() } else { @($result.cleanupErrors) }
                        timingStateRestored = $result.timingStateRestored
                    } }
                    moduleStateBefore = if ($null -eq $beforeState) { $null } else { [ordered]@{ enabled = $beforeState.enabled; stage = $beforeState.stage } }
                    moduleStateAfter = if ($null -eq $afterState) { $null } else { [ordered]@{ enabled = $afterState.enabled; stage = $afterState.stage } }
                    moduleScalarsExact = ($null -ne $beforeState -and $null -ne $afterState -and [bool]$beforeState.enabled -eq [bool]$afterState.enabled -and [string]$beforeState.stage -ceq [string]$afterState.stage)
                    closureTimingSameReference = ($null -ne $beforeState -and $null -ne $afterState -and [object]::ReferenceEquals($beforeState.closure, $afterState.closure))
                    readObserverSameReference = ($null -ne $beforeState -and $null -ne $afterState -and [object]::ReferenceEquals($beforeState.readObserver, $afterState.readObserver))
                    moduleStateRestoredExactly = $stateRestoredExactly; consoleErrorSameReference = $consoleRestored
                    stream = if ($null -eq $stream) { $null } else { [ordered]@{
                        mode = $stream.Mode; armed = $stream.Armed; stage = $stream.Stage; fullReceiptChecks = $stream.FullReceiptChecks
                        faultThrown = $stream.FaultThrown; underlyingClosed = $stream.UnderlyingClosed; events = @($stream.Events)
                    } }
                    astProof = $script:SourceResidentSinkFaultAstProofForTest
                    postflightFullReceiptChecks = if ($null -eq $fixture) { $null } else { & $fixture.module { $script:SourceResidentFixtureFullReceiptChecks } }
                }
                $resultPath = [Environment]::GetEnvironmentVariable('SYP326_SINK_FAULT_RESULT_PATH')
                if (-not [string]::IsNullOrWhiteSpace($resultPath)) {
                    [IO.File]::AppendAllText($resultPath, (($evidence | ConvertTo-Json -Depth 12 -Compress) + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))
                }
                $assertionFailures = [Collections.Generic.List[string]]::new()
                if ($null -eq $stream) { $assertionFailures.Add('controlled stream was not created') }
                else {
                    if (-not $stream.Armed) { $assertionFailures.Add('stream did not arm after final postflight') }
                    if ($stream.Stage -cne 'source-resident-postflight' -or $stream.FullReceiptChecks -ne 1) { $assertionFailures.Add('fault arming stage/check count was not the final postflight') }
                    if (-not $stream.FaultThrown) { $assertionFailures.Add('controlled stream fault did not execute') }
                    if ($Mode -ceq 'Dispose' -and -not $stream.UnderlyingClosed) { $assertionFailures.Add('Dispose fault did not close the real backing stream') }
                }
                $astProof = $script:SourceResidentSinkFaultAstProofForTest
                if ($null -eq $astProof -or [int]$astProof.replacementCount -ne 1 -or -not [bool]$astProof.reversibleSingleExpressionReplacement -or
                    -not [bool]$astProof.streamWriterConstructionUnchanged -or -not [bool]$astProof.autoFlushUnchanged) {
                    $assertionFailures.Add('test extraction did not prove the sole file-open substitution while preserving StreamWriter and AutoFlush')
                }
                if ($null -eq $result) { $assertionFailures.Add('resident sampling must return an incomplete result after sink failure') }
                else {
                    if ([bool]$result.complete) { $assertionFailures.Add('resident result was complete after sink failure') }
                    if ([string]$result.status -cne 'incomplete') { $assertionFailures.Add('resident result status was not incomplete') }
                    if ($null -eq $result.cleanupErrors -or @($result.cleanupErrors).Count -eq 0) { $assertionFailures.Add('result did not retain the secondary sink cleanup error') }
                    if (-not [bool]$result.timingStateRestored) { $assertionFailures.Add('result did not report exact module timing-state restoration') }
                }
                if (-not $stateRestoredExactly) { $assertionFailures.Add('four module values and reference identities were not restored') }
                if (-not $consoleRestored) { $assertionFailures.Add('Console.Error reference was not restored') }
                if ($null -eq $fixture -or (& $fixture.module { [int]$script:SourceResidentFixtureFullReceiptChecks }) -ne 1) { $assertionFailures.Add('the complete postflight receipt check did not run exactly once') }
                if ($FailureSample -gt 0) {
                    if ($null -eq $result -or [string]$result.reason -cne 'sample-exception') { $assertionFailures.Add('earliest sample error reason was not preserved') }
                    if ($null -eq $result -or [string]$result.message -cne 'fixture retained source receipt validation failure') { $assertionFailures.Add('earliest sample error message was overwritten') }
                    if ($null -eq $result -or $null -eq $result.cleanupErrors -or @($result.cleanupErrors).Count -eq 0) { $assertionFailures.Add('secondary sink fault was not preserved alongside the sample error') }
                }
                if ($assertionFailures.Count -gt 0) { throw ('Controlled sink fault assertions failed: ' + ($assertionFailures -join '; ')) }
            }
            finally {
                [Console]::SetError($savedConsoleError)
                if ($null -ne $fixture -and $null -ne $fixture.module) { Remove-Module -ModuleInfo $fixture.module -Force -ErrorAction SilentlyContinue }
                $script:SourceResidentFaultStreamForTest = $null
                $script:SourceResidentSinkFaultAstProofForTest = $null
            }
        }

        function Invoke-SourceResidentUnsupportedDisposeFaultCaseForTest {
            $root = Join-Path $TestDrive ('source-resident-ff85-persistent-dispose-' + [guid]::NewGuid().ToString('N'))
            $runId = [guid]::NewGuid().ToString('N')
            $candidateRevision = 'd' * 40
            $baseRevision = 'e' * 40
            $savedConsoleError = [Console]::Error
            $runner = $null
            $fixture = $null
            $contract = $null
            $result = $null
            $invocationError = $null
            $script:SourceResidentFaultStreamForTest = $null
            $script:SourceResidentSinkFaultAstProofForTest = $null
            try {
                $runner = New-SourceResidentActualRunnerForTest -Root (Join-Path $root 'runner') `
                    -RunId $runId -CandidateRevision $candidateRevision -BaseRevision $baseRevision
                $fixture = [pscustomobject]@{
                    module = $runner.module; authority = $runner.authority; authorityPin = $runner.authorityPin
                    runnerPath = [string]$runner.authority.path; runnerSha256 = [string]$runner.authority.sha256
                    prepared = [pscustomobject]@{ runId = $runId; sourceRevision = $candidateRevision; authorityRevision = [string]$runner.authorityPin.commit }
                    report = [pscustomobject]@{ artifacts = [pscustomobject]@{ outputPath = Join-Path $runner.artifactsRoot 'unsupported-report.json' } }
                    timingEvidence = [pscustomobject]@{}; caseLedger = [pscustomobject]@{}
                    preparedPath = Join-Path $root 'prepared-unused.json'; timingEvidencePath = Join-Path $root 'timing-unused.json'
                    caseLedgerPath = Join-Path $root 'ledger-unused.json'; candidateRoot = $runner.candidateRoot
                    baseRevision = $baseRevision; artifactsRoot = $runner.artifactsRoot; trustedToolRoot = $runner.trustedToolRoot
                    evidenceRoot = [IO.Path]::GetFullPath((Join-Path $root 'resident-evidence'))
                }
                $ff85 = New-SourceResidentAuthorityModuleForTest -Fixture $fixture -AuthorityRevision 'ff85d5f80fe795b96354e753074b5ce59ad04ecd'
                if ([string]$ff85.authorityPin.commit -cne 'ff85d5f80fe795b96354e753074b5ce59ad04ecd' -or
                    [string]$ff85.runnerSha256 -cne [string]$ff85.authorityPin.files['scripts/Invoke-StandardValidation.ps1']) {
                    throw 'The persistent Dispose case did not load the exact FF85 authority runner.'
                }
                Remove-Module -ModuleInfo $fixture.module -Force -ErrorAction Stop
                $fixture.module = $ff85.module
                $fixture.authority = $ff85.authority
                $fixture.authorityPin = $ff85.authorityPin
                $fixture.runnerPath = $ff85.runnerPath
                $fixture.runnerSha256 = $ff85.runnerSha256
                try { $result = Invoke-SourceResidentSeriesForTest -Fixture $fixture -SinkFaultMode PersistentDispose }
                catch { $invocationError = $_.Exception.Message }
                $contract = $script:SourceResidentSinkFaultContractForTest

                $stream = [Syp326.Testing.SourceResidentFaultStream]::Latest
                $events = if ($null -eq $stream) { @() } else { @($stream.Events | ForEach-Object { $_ | ConvertFrom-Json -ErrorAction Stop }) }
                $disposeEvents = @($events | Where-Object { [string]$_.event -ceq 'dispose' })
                $disposeFailures = @($disposeEvents | Where-Object { [string]$_.exceptionMessage -ceq 'controlled persistent sink Dispose fault' })
                $flushFailures = @($events | Where-Object { [string]$_.event -ceq 'flush' -and -not [string]::IsNullOrEmpty([string]$_.exceptionMessage) })
                $cleanupErrorText = if ($null -eq $result) { '' } else { @($result.cleanupErrors) -join ' | ' }
                $outerWriterFlushFailedAfterEarlyDispose = $cleanupErrorText.Contains('outer fallback raw timing writer Flush failed') -and
                    $cleanupErrorText.Contains('Cannot write to a closed TextWriter.')
                $consoleRestored = [object]::ReferenceEquals([Console]::Error, $savedConsoleError)
                $evidence = [ordered]@{
                    case = 'ff85-unsupported-persistent-dispose'; authorityRevision = [string]$fixture.authorityPin.commit
                    authorityRunnerPath = [string]$fixture.runnerPath; authorityRunnerSha256 = [string]$fixture.runnerSha256
                    moduleName = [string]$fixture.module.Name; retainedApiContract = $contract
                    invocationError = $invocationError
                    result = if ($null -eq $result) { $null } else { [ordered]@{
                        complete = $result.complete; status = $result.status; reason = $result.reason; message = $result.message
                        sampleCount = $result.sampleCount; cleanupErrors = if ($null -eq $result.PSObject.Properties['cleanupErrors']) { @() } else { @($result.cleanupErrors) }
                        timingStateRestored = $result.timingStateRestored
                    } }
                    moduleStateAccessesBySampler = 'none expected on unsupported API branch; contract timingStateProbed is false'
                    sampleAccessCount = if ($null -eq $result) { $null } else { [int]$result.sampleCount }
                    consoleErrorSameReference = $consoleRestored
                    stream = if ($null -eq $stream) { $null } else { [ordered]@{
                        mode = $stream.Mode; armed = $stream.Armed; stage = $stream.Stage; fullReceiptChecks = $stream.FullReceiptChecks
                        underlyingClosed = $stream.UnderlyingClosed; events = $events
                        disposeAttemptCount = $disposeEvents.Count; disposeFailureCount = $disposeFailures.Count; flushFailureCount = $flushFailures.Count
                        outerWriterFlushFailedAfterEarlyDispose = $outerWriterFlushFailedAfterEarlyDispose
                        underlyingDisposeRetryObserved = ($disposeFailures.Count -gt 1)
                    } }
                    astProof = $script:SourceResidentSinkFaultAstProofForTest
                }
                $resultPath = [Environment]::GetEnvironmentVariable('SYP326_SINK_FAULT_RESULT_PATH')
                if (-not [string]::IsNullOrWhiteSpace($resultPath)) {
                    [IO.File]::AppendAllText($resultPath, (($evidence | ConvertTo-Json -Depth 16 -Compress) + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))
                }

                $assertionFailures = [Collections.Generic.List[string]]::new()
                if ($null -eq $contract -or [bool]$contract.supported -or @($contract.missingParameters).Count -eq 0 -or [bool]$contract.timingStateProbed) {
                    $assertionFailures.Add('actual FF85 API contract was not unsupported without timing-state probing')
                }
                if ($null -eq $result) { $assertionFailures.Add('FF85 unsupported resident sampling did not return a result') }
                else {
                    if ([bool]$result.complete) { $assertionFailures.Add('result was complete after persistent unsupported-branch Dispose failures') }
                    if ([string]$result.status -cne 'incomplete') { $assertionFailures.Add("result status was '$($result.status)', expected incomplete after cleanup failure") }
                    if ([string]$result.reason -cne 'retained-receipt-api-unsupported') { $assertionFailures.Add('the unsupported API reason was not retained') }
                    if (-not [string]$result.message.Contains('controlled persistent sink Dispose fault')) { $assertionFailures.Add('the earliest Dispose error message was not retained') }
                    if ($null -eq $result.cleanupErrors -or @($result.cleanupErrors).Count -eq 0) { $assertionFailures.Add('persistent cleanup errors were not retained') }
                    if ([int]$result.sampleCount -ne 0) { $assertionFailures.Add('unsupported API branch accessed samples') }
                }
                if (-not $consoleRestored) { $assertionFailures.Add('Console.Error reference was not restored') }
                if ($null -eq $stream -or -not $stream.Armed -or $stream.Stage -cne 'source-resident-unsupported-open' -or $stream.FullReceiptChecks -ne 0) {
                    $assertionFailures.Add('persistent Dispose fault was not armed immediately after stream creation')
                }
                if ($null -eq $stream -or -not $stream.UnderlyingClosed) { $assertionFailures.Add('persistent Dispose failure did not close the real backing file') }
                if ($disposeFailures.Count -ne 1) { $assertionFailures.Add('the controlled persistent fault did not match the single underlying Dispose invocation observed by the runtime') }
                if (-not $outerWriterFlushFailedAfterEarlyDispose) { $assertionFailures.Add('the actual outer writer cleanup retry boundary after the early Dispose failure was not evidenced') }
                if ($flushFailures.Count -ne 0) { $assertionFailures.Add('the controlled stream also faulted during Flush') }
                if ($null -eq $script:SourceResidentSinkFaultAstProofForTest -or
                    [int]$script:SourceResidentSinkFaultAstProofForTest.replacementCount -ne 1 -or
                    -not [bool]$script:SourceResidentSinkFaultAstProofForTest.reversibleSingleExpressionReplacement -or
                    -not [bool]$script:SourceResidentSinkFaultAstProofForTest.streamWriterConstructionUnchanged -or
                    -not [bool]$script:SourceResidentSinkFaultAstProofForTest.autoFlushUnchanged) {
                    $assertionFailures.Add('test extraction did not prove the sole File.Open replacement with real StreamWriter and AutoFlush')
                }
                if ($assertionFailures.Count -gt 0) { throw ('Unsupported FF85 persistent Dispose assertions failed: ' + ($assertionFailures -join '; ')) }
            }
            finally {
                [Console]::SetError($savedConsoleError)
                if ($null -ne $fixture -and $null -ne $fixture.module) { Remove-Module -ModuleInfo $fixture.module -Force -ErrorAction SilentlyContinue }
                $script:SourceResidentFaultStreamForTest = $null
                $script:SourceResidentSinkFaultAstProofForTest = $null
                $script:SourceResidentSinkFaultContractForTest = $null
            }
        }

    }


    # Scenario: a no-argument reader caller coexists with the newly active formal config.
    # Purpose: preserve the ff85 reader default while requiring the active config to select the complete 8e tuple.
    It 'UnitT10_preserves_ff85_default_and_selects_the_formal_active_authority' {
        Test-Path -LiteralPath $script:DriverPath -PathType Leaf | Should -BeTrue
        Import-Module -Name $script:DriverPath -Force
        $pin = Get-PreparedSourceAuthorityPin
        $pin.repository | Should -Be 'https://github.com/SyuanTsai/SyuanTsai-AI-Instructions.git'
        $pin.commit | Should -Be 'ff85d5f80fe795b96354e753074b5ce59ad04ecd'
        $pin.archiveUrl | Should -Be 'https://codeload.github.com/SyuanTsai/SyuanTsai-AI-Instructions/zip/ff85d5f80fe795b96354e753074b5ce59ad04ecd'
        $pin.archiveSha256 | Should -Be '3dc38613f2e2316ad8fcc79d4bf48d0b03fd8398f8dacc72d156abcbce95ea9d'
        $pin.files.Count | Should -Be 32

        $active = Get-Content -LiteralPath $script:ConfigPath -Raw | ConvertFrom-Json -Depth 20
        $active.authority.commit | Should -Be '8e627baf54bd6e47862e6291b25e71cc45a2f2b7'
        $active.authority.archiveUrl | Should -Be 'https://codeload.github.com/SyuanTsai/SyuanTsai-AI-Instructions/zip/8e627baf54bd6e47862e6291b25e71cc45a2f2b7'
        $active.authority.archiveSha256 | Should -Be '9aa4a7fc8fc7c7f0ff9e774c79c77a64077b4003212a523dda519d034ff99989'
        Assert-CodeSourceAuthorityConfig -Config $active
    }

    # Scenario: the protected reader selects the exact delivered 8e627 tuple while callers omit the revision or name ff85.
    # Purpose: preserve ff85 as the default and keep the formally delivered authority bound to its complete ordered closure.
    It 'UnitT15_selects_and_accepts_the_exact_formal_authority_tuple' {
        Import-Module -Name $script:DriverPath -Force
        $formalRevision = '8e627baf54bd6e47862e6291b25e71cc45a2f2b7'
        $expectedFormalPin = New-FormalSourceAuthorityPinFixture
        $defaultPin = Get-PreparedSourceAuthorityPin
        $defaultPin.commit | Should -Be 'ff85d5f80fe795b96354e753074b5ce59ad04ecd'

        $formalPin = Get-PreparedSourceAuthorityPin -AuthorityRevision $formalRevision
        $formalPin.repository | Should -Be 'https://github.com/SyuanTsai/SyuanTsai-AI-Instructions.git'
        $formalPin.commit | Should -Be $expectedFormalPin.commit
        $formalPin.archiveUrl | Should -Be $expectedFormalPin.archiveUrl
        $formalPin.archiveSha256 | Should -Be $expectedFormalPin.archiveSha256
        $formalPin.files.Count | Should -Be 32
        foreach ($path in $expectedFormalPin.files.Keys) {
            $formalPin.files.Contains([string]$path) | Should -BeTrue
            $formalPin.files[[string]$path] | Should -Be $expectedFormalPin.files[[string]$path]
        }

        $formalConfig = New-SourceAuthorityConfigFixture -Pin $expectedFormalPin
        $selectedPin = Assert-CodeSourceAuthorityConfig -Config $formalConfig
        $selectedPin.commit | Should -Be $formalRevision
        Assert-CodeSourceRunRequest -ExecutionMode Run -PrepareSourceTools -SourceToolsPath 'C:\temp\source.json' `
            -AdapterVersion 2 -AuthorityCommit $formalRevision | Should -Be 'PrepareSourceTools'
        Assert-CodeSourceRunRequest -ExecutionMode Run -SourceValidation -SourceToolsPath 'C:\temp\source.json' `
            -AdapterVersion 2 -AuthorityCommit $formalRevision -RunId ('a' * 32) | Should -Be 'SourceValidation'
    }

    # Scenario: a candidate authority changes one identity member or closure record from the delivered 8e627 tuple.
    # Purpose: reject unknown, mixed, partial, reordered, and wrong-hash data instead of admitting by commit alone.
    It 'UnitT16_rejects_unknown_and_malformed_formal_authority_tuples' {
        Import-Module -Name $script:DriverPath -Force
        $formalRevision = '8e627baf54bd6e47862e6291b25e71cc45a2f2b7'
        $formalPin = New-FormalSourceAuthorityPinFixture
        $formalConfig = New-SourceAuthorityConfigFixture -Pin $formalPin

        $unknown = ConvertFrom-Json -InputObject ($formalConfig | ConvertTo-Json -Depth 20 -Compress) -Depth 20
        $unknown.authority.commit = '0' * 40
        { Assert-CodeSourceAuthorityConfig -Config $unknown } | Should -Throw

        $mixed = ConvertFrom-Json -InputObject ($formalConfig | ConvertTo-Json -Depth 20 -Compress) -Depth 20
        $mixed.authority.commit = 'ff85d5f80fe795b96354e753074b5ce59ad04ecd'
        { Assert-CodeSourceAuthorityConfig -Config $mixed } | Should -Throw

        $partial = ConvertFrom-Json -InputObject ($formalConfig | ConvertTo-Json -Depth 20 -Compress) -Depth 20
        $partial.authority.files = @($partial.authority.files | Select-Object -SkipLast 1)
        { Assert-CodeSourceAuthorityConfig -Config $partial } | Should -Throw

        $reordered = ConvertFrom-Json -InputObject ($formalConfig | ConvertTo-Json -Depth 20 -Compress) -Depth 20
        $reordered.authority.files = @($reordered.authority.files[1], $reordered.authority.files[0]) + @($reordered.authority.files | Select-Object -Skip 2)
        { Assert-CodeSourceAuthorityConfig -Config $reordered } | Should -Throw

        $wrongHash = ConvertFrom-Json -InputObject ($formalConfig | ConvertTo-Json -Depth 20 -Compress) -Depth 20
        $wrongHash.authority.files[7].sha256 = '0' * 64
        { Assert-CodeSourceAuthorityConfig -Config $wrongHash } | Should -Throw

        { Assert-CodeSourceRunRequest -ExecutionMode Run -PrepareSourceTools -SourceToolsPath 'C:\temp\source.json' `
            -AdapterVersion 2 -AuthorityCommit ('f' * 40) } | Should -Throw
    }

    # Scenario: the protected Validate reader sees a formal source authority alongside its retained 8a and ff85 fixtures.
    # Purpose: ensure protected-driver validation admits only the complete reviewed source tuples and preserves legacy 8a.
    It 'UnitT18_protected_driver_accepts_formal_source_authority_and_retains_previous_authorities' {
        Import-Module -Name $script:DriverPath -Force
        $validatePath = Join-Path $script:RepositoryRoot 'scripts/Validate.ps1'
        $tokens = $null
        $parseErrors = $null
        $validateAst = [System.Management.Automation.Language.Parser]::ParseFile($validatePath, [ref]$tokens, [ref]$parseErrors)
        @($parseErrors).Count | Should -Be 0
        $functionAst = $validateAst.Find({
            param($node)
            $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
                $node.Name -ceq 'Assert-ProtectedDriverAuthorityConfig'
        }, $true)
        $functionAst | Should -Not -BeNullOrEmpty

        $shimRoot = Join-Path $TestDrive "protected-driver-$([guid]::NewGuid().ToString('N'))"
        [void](New-Item -ItemType Directory -Path $shimRoot -Force)
        Copy-Item -LiteralPath $script:DriverPath -Destination (Join-Path $shimRoot 'StandardSourceDriver.psm1')
        $shimPath = Join-Path $shimRoot 'ProtectedDriverReader.ps1'
        $shimContent = @'
$script:AuthorityCommit = '8aabd22694a05771f98639f6d726cc9a620eb94b'
function Assert-AuthorityConfig { param([Parameter(Mandatory)] $Config) }
'@ + "`n" + $functionAst.Extent.Text + "`n"
        [IO.File]::WriteAllText($shimPath, $shimContent, [Text.UTF8Encoding]::new($false))
        $testModule = New-Module -Name "ProtectedDriverReader_$([guid]::NewGuid().ToString('N'))" -ArgumentList $shimPath -ScriptBlock {
            param($readerPath)
            . $readerPath
        }
        try {
            $legacyConfig = [pscustomobject]@{ authority = [pscustomobject]@{ commit = '8aabd22694a05771f98639f6d726cc9a620eb94b' } }
            { & $testModule { param($Config) Assert-ProtectedDriverAuthorityConfig -Config $Config } $legacyConfig } | Should -Not -Throw

            $ff85Pin = Get-PreparedSourceAuthorityPin
            $ff85Config = New-SourceAuthorityConfigFixture -Pin $ff85Pin
            { & $testModule { param($Config) Assert-ProtectedDriverAuthorityConfig -Config $Config } $ff85Config } | Should -Not -Throw

            $formalPin = New-FormalSourceAuthorityPinFixture
            $formalConfig = New-SourceAuthorityConfigFixture -Pin $formalPin
            { & $testModule { param($Config) Assert-ProtectedDriverAuthorityConfig -Config $Config } $formalConfig } | Should -Not -Throw
        }
        finally {
            Remove-Module -ModuleInfo $testModule -Force -ErrorAction SilentlyContinue
        }
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

    # Scenario: a prepared receipt names either reviewed authority, while the source reader is given its independently selected revision.
    # Purpose: accept both exact bindings and reject a prepared self-report that differs from the selected authority.
    It 'UnitT35_binds_prepared_metadata_to_the_selected_authority_revision' {
        Import-Module -Name $script:DriverPath -Force
        $formalRevision = '8e627baf54bd6e47862e6291b25e71cc45a2f2b7'
        $formalFixture = New-SourceBindingFixture -Root (Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))) `
            -AuthorityRevision $formalRevision
        { Assert-CodeSourcePreparedBindings -Prepared $formalFixture.prepared -PreparedPath $formalFixture.preparedPath `
            -CandidateRevision $formalFixture.candidateRevision -PowerShellPath $formalFixture.runtimeExecutable `
            -SourceRepository 'https://github.com/SyuanTsai/Skill-Code-Collaboration.git' `
            -ExpectedAuthorityRevision $formalRevision } | Should -Not -Throw

        $ff85Fixture = New-SourceBindingFixture -Root (Join-Path $TestDrive ([guid]::NewGuid().ToString('N')))
        { Assert-CodeSourcePreparedBindings -Prepared $ff85Fixture.prepared -PreparedPath $ff85Fixture.preparedPath `
            -CandidateRevision $ff85Fixture.candidateRevision -PowerShellPath $ff85Fixture.runtimeExecutable `
            -SourceRepository 'https://github.com/SyuanTsai/Skill-Code-Collaboration.git' `
            -ExpectedAuthorityRevision $formalRevision } | Should -Throw
        { Assert-CodeSourcePreparedBindings -Prepared $ff85Fixture.prepared -PreparedPath $ff85Fixture.preparedPath `
            -CandidateRevision $ff85Fixture.candidateRevision -PowerShellPath $ff85Fixture.runtimeExecutable `
            -SourceRepository 'https://github.com/SyuanTsai/Skill-Code-Collaboration.git' } | Should -Not -Throw
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

    # Given: original setup stage maps and one frozen source input, with acquisition already complete.
    # When: the extracted production setup receipt span runs through its real create-only JSON writer.
    # Then: the completion receipt has independent late timings while the early receipt bytes and frozen hash remain unchanged.
    # Scenario: source setup publishes late verification and prepared-write timing fields.
    # Purpose: preserve frozen early timing evidence and the existing completion boundary.
    It 'UnitT70_records_late_setup_stages_without_changing_frozen_early_receipt' {
        $fixtureRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $result = Invoke-SourceSetupLateTimingBlockForTest -Root $fixtureRoot

        $prepared = Get-Content -LiteralPath $result.preparedPath -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 80
        $completed = Get-Content -LiteralPath $result.completedPath -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 40
        $setupTimingBytes = [IO.File]::ReadAllBytes($result.setupTimingPath)
        $setupTimingHash = ([Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($setupTimingBytes))).ToLowerInvariant()
        $early = [Text.UTF8Encoding]::new($false).GetString($setupTimingBytes) | ConvertFrom-Json -Depth 40
        $lateNames = @('finalFrozenVerificationSeconds', 'finalReceiptVerificationSeconds', 'preparedMetadataWriteSeconds')

        $completed.schemaVersion | Should -Be 1
        $completed.totalBoundary | Should -BeExactly 'after complete frozen-file verification and prepared metadata creation'
        $completed.stageTimingSha256 | Should -BeExactly $setupTimingHash
        $result.setupTimingHashAfter | Should -BeExactly $result.setupTimingHashBefore
        $setupTimingHash | Should -BeExactly $result.setupTimingHashBefore
        [Convert]::ToBase64String($setupTimingBytes) | Should -BeExactly ([Convert]::ToBase64String($result.setupTimingBytesBefore))
        $early.stageSeconds.PSObject.Properties.Name | Should -Not -Contain 'finalFrozenVerificationSeconds'
        $early.stageSeconds.PSObject.Properties.Name | Should -Not -Contain 'finalReceiptVerificationSeconds'
        $early.stageSeconds.PSObject.Properties.Name | Should -Not -Contain 'preparedMetadataWriteSeconds'
        foreach ($name in $lateNames) {
            @($result.setupStageSeconds.Keys | Where-Object { $_ -ceq $name }).Count | Should -Be 0
            $completed.stageSeconds.PSObject.Properties.Name | Should -Contain $name
            $stageValue = $completed.stageSeconds.PSObject.Properties[$name].Value
            ($stageValue -is [double]) | Should -BeTrue
            [double]::IsNaN($stageValue) | Should -BeFalse
            [double]::IsInfinity($stageValue) | Should -BeFalse
            $stageValue | Should -BeGreaterOrEqual 0
        }
        foreach ($name in $result.setupStageSeconds.Keys) {
            [double]$completed.stageSeconds.$name | Should -Be ([double]$early.stageSeconds.$name)
        }
        foreach ($name in $result.resolverStageSeconds.Keys) {
            [double]$completed.resolverSeconds.$name | Should -Be ([double]$early.resolverSeconds.$name)
        }
        $setupBinding = @($prepared.sourceValidation.frozenFiles | Where-Object { [string]$_.path -ceq $result.setupTimingPath })
        $setupBinding.Count | Should -Be 1
        $setupBinding[0].sha256 | Should -BeExactly $setupTimingHash
        $prepared.runId | Should -BeExactly $result.runId
        [double]$prepared.sourceValidation.frozenFiles.Count | Should -BeGreaterThan 0
        $result.failure | Should -BeNullOrEmpty
    }

    # Scenario: a final setup check or prepared metadata write fails before setup is complete.
    # Purpose: preserve the existing completion boundary and frozen early timing bytes on every late-stage failure.
    It 'UnitT71_does_not_publish_completed_setup_receipts_when_a_late_stage_fails' {
        foreach ($failureStage in @('frozen', 'receipts', 'prepared')) {
            $fixtureRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
            $result = Invoke-SourceSetupLateTimingBlockForTest -Root $fixtureRoot -FailureStage $failureStage
            $expectedFailure = if ($failureStage -ceq 'prepared') { 'fixture prepared metadata write failure' } else { "fixture $failureStage verification failure" }
            $result.failure | Should -BeExactly $expectedFailure -Because $failureStage
            $result.preparedExists | Should -BeFalse
            $result.completedExists | Should -BeFalse
            $result.setupTimingHashAfter | Should -BeExactly $result.setupTimingHashBefore
            [Convert]::ToBase64String([IO.File]::ReadAllBytes($result.setupTimingPath)) | Should -BeExactly ([Convert]::ToBase64String($result.setupTimingBytesBefore))
        }
    }

    # Scenario: the extracted production source transaction runs against a tiny child emitter, then retains its real JSON receipt and cleanup behavior.
    # Purpose: validate numeric elapsed fields, null downstream stages, and unchanged failure decisions without invoking the full Standard Core gate.
    It 'UnitT72_records_source_stage_timings_and_preserves_success_failure_and_cleanup_semantics' {
        $success = Invoke-SourceValidationOuterTryForTest -Root (Join-Path $TestDrive ([guid]::NewGuid().ToString('N')))
        $success.receipt | Should -Not -BeNullOrEmpty
        $success.authorityHead | Should -BeExactly $success.prepared.authorityRevision
        $success.receipt.runId | Should -BeExactly $success.fixture.runId
        $success.receipt.candidateRevision | Should -BeExactly $success.fixture.candidateRevision
        $success.receipt.authorityRevision | Should -BeExactly $success.prepared.authorityRevision
        $success.receipt.diagnosticTargetSeconds | Should -Be 1200
        $success.receipt.reportAccepted | Should -BeTrue
        $success.receipt.cleanupSucceeded | Should -BeTrue
        $success.receipt.processExitCode | Should -Be 0
        $success.receipt.stageSeconds | Should -Not -BeNullOrEmpty
        $success.receipt.stageSeconds.PSObject.Properties.Name | Should -Contain 'preadmissionSeconds'
        $success.receipt.stageSeconds.PSObject.Properties.Name | Should -Not -Contain 'centralRunnerSeconds'
        $success.receipt.centralRunnerSeconds | Should -BeGreaterOrEqual 0
        foreach ($name in @('snapshotAndAdapterSeconds', 'outputRelaySeconds', 'protectedReportReaderSeconds', 'codeReportBindingSeconds', 'cleanupSeconds')) {
            $success.receipt.stageSeconds.PSObject.Properties.Name | Should -Contain $name -Because 'the source timing receipt binds all stage names'
            $value = $success.receipt.stageSeconds.PSObject.Properties[$name].Value
            ($value -is [double]) | Should -BeTrue -Because $name
            [double]::IsNaN($value) | Should -BeFalse -Because $name
            [double]::IsInfinity($value) | Should -BeFalse -Because $name
            $value | Should -BeGreaterOrEqual 0 -Because $name
        }
        $success.receipt.stageSeconds.preadmissionSeconds | Should -BeNullOrEmpty -Because 'the controlled AST seam starts after pre-admission'
        $success.errorText | Should -BeNullOrEmpty
        $success.priorTestValidateSourceAfter | Should -BeExactly 'fixture prior value'
        (Test-Path -LiteralPath $success.adapterRoot) | Should -BeFalse

        foreach ($case in @(
            [pscustomobject]@{ scenario = 'snapshot'; attempted = 'snapshotAndAdapterSeconds'; next = 'outputRelaySeconds'; message = 'fixture authority snapshot failure'; processExitCode = 1; reportAccepted = $false; cleanupSucceeded = $true }
            [pscustomobject]@{ scenario = 'adapter'; attempted = 'snapshotAndAdapterSeconds'; next = 'outputRelaySeconds'; message = 'fixture source adapter creation failure'; processExitCode = 1; reportAccepted = $false; cleanupSucceeded = $true }
            [pscustomobject]@{ scenario = 'reader'; attempted = 'protectedReportReaderSeconds'; next = 'codeReportBindingSeconds'; message = 'fixture protected report reader failure'; processExitCode = 0; reportAccepted = $false; cleanupSucceeded = $true }
            [pscustomobject]@{ scenario = 'binding'; attempted = 'codeReportBindingSeconds'; next = ''; message = 'fixture source report binding failure'; processExitCode = 0; reportAccepted = $false; cleanupSucceeded = $true }
            [pscustomobject]@{ scenario = 'nonzero'; attempted = 'outputRelaySeconds'; next = 'protectedReportReaderSeconds'; message = ''; processExitCode = 23; reportAccepted = $false; cleanupSucceeded = $true }
            [pscustomobject]@{ scenario = 'cancel'; attempted = 'codeReportBindingSeconds'; next = ''; message = 'fixture cancellation report binding failure'; processExitCode = 0; reportAccepted = $false; cleanupSucceeded = $true }
            [pscustomobject]@{ scenario = 'cleanup'; attempted = 'cleanupSeconds'; next = ''; message = 'SOURCE_CLEANUP|'; processExitCode = 0; reportAccepted = $true; cleanupSucceeded = $false }
        )) {
            $result = Invoke-SourceValidationOuterTryForTest -Root (Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))) -Scenario $case.scenario
            $result.receipt | Should -Not -BeNullOrEmpty -Because $case.scenario
            $result.receipt.stageSeconds | Should -Not -BeNullOrEmpty -Because $case.scenario
            $result.receipt.stageSeconds.PSObject.Properties.Name | Should -Contain $case.attempted -Because $case.scenario
            $value = $result.receipt.stageSeconds.PSObject.Properties[$case.attempted].Value
            ($value -is [double]) | Should -BeTrue -Because "$($case.scenario) attempted stage"
            [double]::IsNaN($value) | Should -BeFalse -Because "$($case.scenario) attempted stage"
            [double]::IsInfinity($value) | Should -BeFalse -Because "$($case.scenario) attempted stage"
            $value | Should -BeGreaterOrEqual 0 -Because "$($case.scenario) attempted stage"
            if (-not [string]::IsNullOrWhiteSpace([string]$case.next)) {
                $result.receipt.stageSeconds.PSObject.Properties.Name | Should -Contain $case.next -Because $case.scenario
                $result.receipt.stageSeconds.PSObject.Properties[$case.next].Value | Should -BeNullOrEmpty -Because "$($case.scenario) downstream stage"
            }
            $result.receipt.processExitCode | Should -Be $case.processExitCode -Because $case.scenario
            $result.receipt.reportAccepted | Should -Be $case.reportAccepted -Because $case.scenario
            $result.receipt.cleanupSucceeded | Should -Be $case.cleanupSucceeded -Because $case.scenario
            if ([string]::IsNullOrWhiteSpace([string]$case.message)) { $result.errorText | Should -BeNullOrEmpty -Because $case.scenario }
            else { $result.errorText | Should -Match ([regex]::Escape([string]$case.message)) -Because $case.scenario }
            if ($case.scenario -ceq 'cleanup') { (Test-Path -LiteralPath $result.adapterRoot) | Should -BeTrue -Because $case.scenario }
            else { (Test-Path -LiteralPath $result.adapterRoot) | Should -BeFalse -Because $case.scenario }
        }
    }

    # Scenario: source authority admission fails before the existing outer try/finally.
    # Purpose: ensure pre-admission rejection still creates no timing receipt, child process, or cleanup work.
    It 'UnitT73_preserves_source_pre_admission_failure_boundary' {
        $result = Invoke-SourcePreadmissionFailureForTest -Root (Join-Path $TestDrive ([guid]::NewGuid().ToString('N')))
        $result.failure | Should -Match 'fixture pre-admission authority rejection'
        $result.artifactsRootExists | Should -BeFalse
        $result.sourceReceiptFiles | Should -Be 0
        $result.cleanupFailed | Should -BeFalse
        $result.invalidInput | Should -BeFalse
        $result.functionPreservedTestValidateSource | Should -BeExactly 'fixture pre-admission value'
    }

    # Scenario: the new source-only resident measurement request is admitted independently of setup and the canonical source gate.
    # Purpose: expose a strict resident mode guard before adding any sampling behavior.
    It 'UnitT74_admits_only_the_explicit_source_resident_request' {
        $validatePath = Join-Path $script:RepositoryRoot 'scripts/Validate.ps1'
        $tokens = $null
        $parseErrors = $null
        $validateAst = [System.Management.Automation.Language.Parser]::ParseFile($validatePath, [ref]$tokens, [ref]$parseErrors)
        @($parseErrors).Count | Should -Be 0
        $guardAst = $validateAst.Find({
            param($node)
            $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
                $node.Name -ceq 'Assert-CodeSourceResidentRunRequest'
        }, $true)
        $guardAst | Should -Not -BeNullOrEmpty -Because 'the new mode needs an executable admission guard before it can be dispatched'
        if ($null -eq $guardAst) { return }

        Import-Module -Name $script:DriverPath -Force -ErrorAction Stop
        . ([scriptblock]::Create($guardAst.Extent.Text))
        $valid = Assert-CodeSourceResidentRunRequest -ExecutionMode 'Run' -AdapterVersion 2 `
            -SourceResidentTiming -SourceToolsPath (Join-Path $TestDrive 'source-tools.json') `
            -AuthorityRevision 'ff85d5f80fe795b96354e753074b5ce59ad04ecd' -RunId ('a' * 32)
        $valid | Should -BeExactly 'SourceResidentTiming'

        { Assert-CodeSourceResidentRunRequest -ExecutionMode 'Run' -AdapterVersion 2 `
            -SourceResidentTiming -SourceValidation -SourceToolsPath (Join-Path $TestDrive 'source-tools.json') `
            -AuthorityRevision 'ff85d5f80fe795b96354e753074b5ce59ad04ecd' -RunId ('a' * 32) } |
            Should -Throw '*separate*'
        { Assert-CodeSourceResidentRunRequest -ExecutionMode 'Run' -AdapterVersion 1 `
            -SourceResidentTiming -SourceToolsPath (Join-Path $TestDrive 'source-tools.json') `
            -AuthorityRevision 'ff85d5f80fe795b96354e753074b5ce59ad04ecd' -RunId ('a' * 32) } |
            Should -Throw '*Core adapter v2*'
        { Assert-CodeSourceResidentRunRequest -ExecutionMode 'Run' -AdapterVersion 2 `
            -SourceResidentTiming -SourceToolsPath (Join-Path $TestDrive 'source-tools.json') `
            -AuthorityRevision 'ff85d5f80fe795b96354e753074b5ce59ad04ecd' -RunId 'invalid' } |
            Should -Throw '*RunId*'
    }

    # Scenario: the pinned legacy receipt API lacks retained-map arguments while the delivered 8e runner exposes them.
    # Purpose: probe the actual command in the same owned module and decline unsupported authority without timing-state fallback.
    It 'UnitT75_probes_the_owned_retained_receipt_api_without_fallback' {
        Import-Module -Name $script:DriverPath -Force
        $validatePath = Join-Path $script:RepositoryRoot 'scripts/Validate.ps1'
        $tokens = $null
        $parseErrors = $null
        $validateAst = [System.Management.Automation.Language.Parser]::ParseFile($validatePath, [ref]$tokens, [ref]$parseErrors)
        @($parseErrors).Count | Should -Be 0
        $probeAst = $validateAst.Find({
            param($node)
            $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
                $node.Name -ceq 'Get-CodeSourceResidentRetainedApiContract'
        }, $true)
        $probeAst | Should -Not -BeNullOrEmpty -Because 'resident sampling needs an API probe before it can touch retained timing state'
        if ($null -eq $probeAst) { return }
        . ([scriptblock]::Create($probeAst.Extent.Text))
        $moduleFactoryAst = $validateAst.Find({
            param($node)
            $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
                $node.Name -ceq 'New-CodeSourceStandardValidationModule'
        }, $true)
        $moduleFactoryAst | Should -Not -BeNullOrEmpty
        if ($null -eq $moduleFactoryAst) { return }
        . ([scriptblock]::Create($moduleFactoryAst.Extent.Text))

        $legacyModule = New-Module -Name ('SourceResidentLegacyApi_' + [guid]::NewGuid().ToString('N')) -ScriptBlock {
            function Assert-StandardCoreSourceToolReceipts {
                param([object[]] $Bindings, [object[]] $FrozenFiles, [string] $RunId,
                    [string] $CandidateRoot, [string] $ArtifactsRoot)
            }
            Export-ModuleMember -Function @() -Cmdlet @() -Alias @() -Variable @()
        }
        $actualModule = $null
        try {
            $legacyContract = Get-CodeSourceResidentRetainedApiContract -Module $legacyModule
            $legacyContract.supported | Should -BeFalse
            ($legacyContract.missingParameters -join ',') | Should -BeExactly 'RetainedReceiptMap,ToolNames,AdditionalPaths,ReturnReceiptMap'
            $legacyContract.timingStateProbed | Should -BeFalse

            $formalPin = Get-PreparedSourceAuthorityPin -AuthorityRevision '8e627baf54bd6e47862e6291b25e71cc45a2f2b7'
            $fixtureRoot = [IO.Path]::GetFullPath((Join-Path $TestDrive ('resident-api-' + [guid]::NewGuid().ToString('N'))))
            $candidateRoot = Join-Path $fixtureRoot 'candidate'
            $artifactsRoot = Join-Path $fixtureRoot 'artifacts'
            $trustedToolRoot = Split-Path -Parent ([IO.Path]::GetFullPath([Diagnostics.Process]::GetCurrentProcess().MainModule.FileName))
            foreach ($directory in @($candidateRoot, $artifactsRoot, $trustedToolRoot)) {
                [void](New-Item -ItemType Directory -Path $directory -Force)
            }
            $authorityFixture = New-SourceResidentAuthorityModuleForTest -Fixture ([pscustomobject]@{
                candidateRoot = [IO.Path]::GetFullPath($candidateRoot)
                artifactsRoot = [IO.Path]::GetFullPath($artifactsRoot)
                trustedToolRoot = [IO.Path]::GetFullPath($trustedToolRoot)
                prepared = [pscustomobject]@{ runId = 'c' * 32; sourceRevision = 'a' * 40 }
                baseRevision = 'b' * 40
            }) -AuthorityRevision ([string]$formalPin.commit)
            $authority = [pscustomobject]@{
                revision = [string]$authorityFixture.authorityPin.commit
                sha256 = [string]$authorityFixture.runnerSha256
                path = [string]$authorityFixture.runnerPath
            }
            [string]$authority.revision | Should -BeExactly ([string]$formalPin.commit)
            [string]$authority.sha256 | Should -BeExactly ([string]$formalPin.files['scripts/Invoke-StandardValidation.ps1'])
            $actualModule = $authorityFixture.module
            $before = & $actualModule {
                [pscustomobject]@{
                    enabled = [bool]$script:StandardValidationTimingEnabled
                    stage = [string]$script:StandardValidationTimingStage
                    closure = $script:StandardValidationClosureTiming
                    readObserver = $script:StandardValidationReadObserver
                }
            }
            $before.enabled | Should -BeFalse
            $before.stage | Should -BeExactly 'validation'
            $before.closure | Should -BeNullOrEmpty
            $before.readObserver | Should -BeNullOrEmpty

            $actualContract = Get-CodeSourceResidentRetainedApiContract -Module $actualModule
            $actualContract.supported | Should -BeTrue
            $actualContract.missingParameters | Should -BeNullOrEmpty
            $actualContract.timingStateProbed | Should -BeFalse
            foreach ($name in @('RetainedReceiptMap', 'ToolNames', 'AdditionalPaths', 'ReturnReceiptMap')) {
                $actualContract.parameterNames | Should -Contain $name
            }
            [IO.Path]::GetFullPath([string]$actualContract.runnerScriptFile) | Should -BeExactly ([IO.Path]::GetFullPath([string]$authority.path))
            $after = & $actualModule {
                [pscustomobject]@{
                    enabled = [bool]$script:StandardValidationTimingEnabled
                    stage = [string]$script:StandardValidationTimingStage
                    closure = $script:StandardValidationClosureTiming
                    readObserver = $script:StandardValidationReadObserver
                }
            }
            $after.enabled | Should -BeExactly $before.enabled
            $after.stage | Should -BeExactly $before.stage
            $after.closure | Should -BeNullOrEmpty
            $after.readObserver | Should -BeNullOrEmpty
        }
        finally {
            if ($null -ne $actualModule) { Remove-Module -ModuleInfo $actualModule -Force -ErrorAction SilentlyContinue }
            if ($null -ne $legacyModule) { Remove-Module -ModuleInfo $legacyModule -Force -ErrorAction SilentlyContinue }
        }
    }

    # Scenario: resident timing samples the two natural closure-size extremes only after an accepted, cleaned canonical run.
    # Purpose: exercise same-run bindings, actual 8e frozen diagnostics, 3x2 retained calls, and failure-safe evidence restoration.
    It 'UnitT76_samples_two_natural_closures_and_preserves_lifecycle_evidence' {
        Import-Module -Name $script:DriverPath -Force
        $validatePath = Join-Path $script:RepositoryRoot 'scripts/Validate.ps1'
        $tokens = $null
        $parseErrors = $null
        $validateAst = [System.Management.Automation.Language.Parser]::ParseFile($validatePath, [ref]$tokens, [ref]$parseErrors)
        @($parseErrors).Count | Should -Be 0
        $seriesAst = $validateAst.Find({
            param($node)
            $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
                $node.Name -ceq 'Invoke-CodeSourceResidentSampleSeries'
        }, $true)
        $seriesAst | Should -Not -BeNullOrEmpty -Because 'the resident sample protocol must have behavior beyond mode admission and capability probing'
        if ($null -eq $seriesAst) { return }
        $contractAst = $validateAst.Find({
            param($node)
            $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
                $node.Name -ceq 'Get-CodeSourceResidentRetainedApiContract'
        }, $true)
        $contractAst | Should -Not -BeNullOrEmpty -Because 'the FF85 capability case must use the production retained-API probe'
        if ($null -eq $contractAst) { return }
        . ([scriptblock]::Create($contractAst.Extent.Text))

        $scenarioTrace = [Collections.Generic.List[string]]::new()
        $scenarioErrors = [Collections.Generic.List[string]]::new()
        if ($seriesAst.Extent.Text -match 'Get-A031AuthoritySupervisorBinding') {
            [void]$scenarioErrors.Add('production sample identity depends on the test-only A031 authority helper')
        }
        $scenarios = @(
            [pscustomobject]@{ name = 'success-3x2'; option = 'success' }
            [pscustomobject]@{ name = 'same-count-different-bytes'; option = 'same-count-different-bytes' }
            [pscustomobject]@{ name = 'insufficient-distinct-footprints'; option = 'equal' }
            [pscustomobject]@{ name = 'sample-exception'; option = 'failure' }
            [pscustomobject]@{ name = 'cancellation'; option = 'cancel' }
            [pscustomobject]@{ name = 'missing-raw-sample-diagnostics'; option = 'omit' }
            [pscustomobject]@{ name = 'malformed-sample-counters'; option = 'malformed' }
            [pscustomobject]@{ name = 'postflight-frozen-change'; option = 'mutation' }
            [pscustomobject]@{ name = 'postflight-unfrozen-file-added'; option = 'extra-file' }
            [pscustomobject]@{ name = 'mismatched-case-ledger'; option = 'ledger' }
            [pscustomobject]@{ name = 'wrong-retained-receipt-map'; option = 'receipt-map' }
            [pscustomobject]@{ name = 'timing-candidate-revision-mismatch'; option = 'timing-candidate' }
            [pscustomobject]@{ name = 'timing-base-revision-mismatch'; option = 'timing-base' }
            [pscustomobject]@{ name = 'timing-authority-revision-mismatch'; option = 'timing-authority' }
            [pscustomobject]@{ name = 'canonical-report-not-accepted'; option = 'report-failed' }
            [pscustomobject]@{ name = 'canonical-cleanup-not-accepted'; option = 'cleanup-failed' }
            [pscustomobject]@{ name = 'formal-ff85-retained-api-unsupported'; option = 'ff85-unsupported' }
        )
        foreach ($scenario in $scenarios) {
            $scenarioTrace.Add([string]$scenario.name)
            $fixture = $null
            $result = $null
            try {
                $root = Join-Path $TestDrive ('resident-series-' + [guid]::NewGuid().ToString('N'))
                $fixtureArguments = @{ Root = $root }
                switch ([string]$scenario.option) {
                    'same-count-different-bytes' { $fixtureArguments.FootprintMode = 'same-count-different-bytes' }
                    'equal' { $fixtureArguments.FootprintMode = 'equal-footprints' }
                    'failure' { $fixtureArguments.FailureSample = 3 }
                    'cancel' { }
                    'omit' { $fixtureArguments.OmitSampleDiagnostics = $true }
                    'malformed' { $fixtureArguments.MalformedSampleDiagnostics = $true }
                    'mutation' { $fixtureArguments.ChangeFrozenFileOnLastSample = $true }
                    'extra-file' { $fixtureArguments.AddUnfrozenFileOnLastSample = $true }
                    'ledger' { }
                    'receipt-map' { }
                    'timing-candidate' { $fixtureArguments.TimingRevisionMismatch = 'candidate' }
                    'timing-base' { $fixtureArguments.TimingRevisionMismatch = 'base' }
                    'timing-authority' { $fixtureArguments.TimingRevisionMismatch = 'authority' }
                    'report-failed' { $fixtureArguments.RejectReport = $true }
                    'cleanup-failed' { $fixtureArguments.TimingCleanupFailed = $true }
                }
                $fixture = New-SourceResidentSeriesFixtureForTest @fixtureArguments
                if ([string]$scenario.option -ceq 'cancel') {
                    [void](Write-SourceBindingFixtureFile -Path $fixture.cancellationPath -Text '{"cancelled":true}')
                }
                elseif ([string]$scenario.option -ceq 'ledger') {
                    $badLedger = Get-Content -LiteralPath $fixture.caseLedgerPath -Raw | ConvertFrom-Json -Depth 20
                    $badLedger.coreRunId = 'f' * 32
                    [IO.File]::WriteAllText($fixture.caseLedgerPath, (($badLedger | ConvertTo-Json -Depth 20 -Compress) + "`n"), [Text.UTF8Encoding]::new($false))
                }
                elseif ([string]$scenario.option -ceq 'receipt-map') {
                    & $fixture.module { $script:SourceResidentFixtureMap.runId = 'f' * 32 }
                }
                elseif ([string]$scenario.option -ceq 'ff85-unsupported') {
                    $ff85 = New-SourceResidentAuthorityModuleForTest -Fixture $fixture `
                        -AuthorityRevision 'ff85d5f80fe795b96354e753074b5ce59ad04ecd'
                    Remove-Module -ModuleInfo $fixture.module -Force -ErrorAction Stop
                    $fixture.module = $ff85.module
                    $fixture.authorityPin = $ff85.authorityPin
                    $fixture.runnerPath = $ff85.runnerPath
                    $fixture.runnerSha256 = $ff85.runnerSha256
                    & $fixture.module {
                        $script:SourceResidentFixtureCalls = 0
                        $script:SourceResidentFixtureFullReceiptChecks = 0
                    }
                    $ff85Contract = Get-CodeSourceResidentRetainedApiContract -Module $fixture.module
                    $ff85Contract.supported | Should -BeFalse
                    $ff85Contract.timingStateProbed | Should -BeFalse
                    @($ff85Contract.missingParameters).Count | Should -BeGreaterThan 0
                }

                $reportHashBefore = Get-SourceBindingFixtureHash -Path $fixture.reportPath
                $stateBefore = Get-SourceResidentModuleStateForTest -Module $fixture.module
                $consoleErrorBefore = [Console]::Error
                $cancellationPath = if ([string]$scenario.option -ceq 'cancel') { $fixture.cancellationPath } else { '' }
                $result = Invoke-SourceResidentSeriesForTest -Fixture $fixture -CancellationPath $cancellationPath
                $sampleCalls = [int](& $fixture.module { $script:SourceResidentFixtureCalls })
                $fullReceiptChecks = [int](& $fixture.module { $script:SourceResidentFixtureFullReceiptChecks })
                $stateAfter = Get-SourceResidentModuleStateForTest -Module $fixture.module
                [object]::ReferenceEquals($consoleErrorBefore, [Console]::Error) | Should -BeTrue
                $stateAfter.enabledPresent | Should -BeExactly $stateBefore.enabledPresent
                $stateAfter.enabled | Should -BeExactly $stateBefore.enabled
                $stateAfter.stagePresent | Should -BeExactly $stateBefore.stagePresent
                $stateAfter.stage | Should -BeExactly $stateBefore.stage
                $stateAfter.closurePresent | Should -BeExactly $stateBefore.closurePresent
                [object]::ReferenceEquals($stateBefore.closure, $stateAfter.closure) | Should -BeTrue
                $stateAfter.readObserverPresent | Should -BeExactly $stateBefore.readObserverPresent
                [object]::ReferenceEquals($stateBefore.readObserver, $stateAfter.readObserver) | Should -BeTrue
                (Get-SourceBindingFixtureHash -Path $fixture.reportPath) | Should -BeExactly $reportHashBefore

                switch ([string]$scenario.option) {
                    'success' {
                        $result.status | Should -BeExactly 'complete'
                        $result.complete | Should -BeTrue
                        $result.sampleCount | Should -Be 6
                        $sampleCalls | Should -Be 6
                        $fullReceiptChecks | Should -Be 1
                        @($result.selectedGroups).Count | Should -Be 2
                        @($result.selectedGroups | ForEach-Object { [int]$_.rootFileCount } | Sort-Object -Unique) | Should -Be @(1, 3)
                        @($result.samples | Where-Object { [string]$_.sourceIntegrity.state -ceq 'completed' }).Count | Should -Be 6
                        @($result.samples | Where-Object { [long]$_.sourceIntegrity.calls -ne 0 -or [long]$_.sourceIntegrity.files -ne 0 -or [long]$_.sourceIntegrity.bytes -ne 0 }).Count | Should -Be 0
                        @($result.samples | Where-Object {
                            @($_.phaseRecords | Where-Object phase -ceq 'source-receipt-bytes').Count -eq 0 -or
                            @($_.phaseRecords | Where-Object phase -ceq 'frozen-file-hashes').Count -eq 0 -or
                            @($_.phaseRecords | Where-Object phase -ceq 'closure-content-hash').Count -eq 0
                        }).Count | Should -Be 0
                        @($result.samples | Group-Object groupId | ForEach-Object Count | Where-Object { $_ -ne 3 }).Count | Should -Be 0
                        $sampleArguments = @(& $fixture.module { $script:SourceResidentFixtureArguments.ToArray() })
                        @($sampleArguments).Count | Should -Be 6
                        @($sampleArguments | Where-Object { $_.mapRunId -cne [string]$fixture.prepared.runId -or $_.moduleName -cne $fixture.module.Name }).Count | Should -Be 0
                        @($sampleArguments | Where-Object { $_.timingStage -cne 'source-resident-sample' }).Count | Should -Be 0
                        foreach ($sampleArgument in $sampleArguments) {
                            $expectedDispatchSlots = foreach ($tool in @($sampleArgument.toolNames)) {
                                switch ([string]$tool) { 'skill-validator' { 'skillValidator' } 'skill-tools' { 'skillTools' } 'skillspector' { 'staticAnalyzer' } }
                            }
                            $expectedPaths = [Collections.Generic.List[string]]::new()
                            foreach ($slot in @($expectedDispatchSlots)) {
                                $dispatch = $fixture.prepared.sourceValidation.PSObject.Properties[[string]$slot].Value
                                $expectedPaths.Add([IO.Path]::GetFullPath([string]$dispatch.command))
                                foreach ($argument in @($dispatch.arguments)) {
                                    if ([IO.Path]::IsPathRooted([string]$argument)) { $expectedPaths.Add([IO.Path]::GetFullPath([string]$argument)) }
                                }
                            }
                            @($sampleArgument.additionalPaths | Sort-Object -Unique) | Should -Be @($expectedPaths.ToArray() | Sort-Object -Unique)
                        }
                        $raw = Get-Content -LiteralPath $result.rawDiagnosticsPath -Raw
                        $raw | Should -Match '\[StandardValidation timing\].*frozen-file-hashes'
                        $raw | Should -Match '\[StandardValidation timing\].*source-receipt-bytes'
                        $raw | Should -Match '\[StandardValidation timing\].*source-resident-sample'
                        $result.counters | Should -Not -BeNullOrEmpty
                        [double]$result.seriesWallSeconds | Should -BeGreaterThan 0
                        [string]$result.preparedSha256 | Should -Be (Get-SourceBindingFixtureHash -Path $fixture.preparedPath)
                        [string]$result.reportSha256 | Should -Be $reportHashBefore
                    }
                    'same-count-different-bytes' {
                        $result.status | Should -BeExactly 'complete'
                        $result.sampleCount | Should -Be 6
                        @($result.selectedGroups | ForEach-Object { [int]$_.rootFileCount } | Sort-Object -Unique) | Should -Be @(2)
                        @($result.selectedGroups | ForEach-Object { [long]$_.rootBytes } | Sort-Object -Unique).Count | Should -Be 2
                        $fullReceiptChecks | Should -Be 1
                    }
                    'equal' {
                        $result.complete | Should -BeFalse
                        $result.reason | Should -BeExactly 'insufficient-distinct-closure-footprints'
                        $result.sampleCount | Should -Be 0
                        $sampleCalls | Should -Be 0
                        $fullReceiptChecks | Should -Be 1
                    }
                    'failure' {
                        $result.complete | Should -BeFalse
                        $result.status | Should -BeExactly 'incomplete'
                        $result.sampleCount | Should -Be 3
                        $sampleCalls | Should -Be 3
                        @($result.samples | Where-Object { [string]$_.sourceIntegrity.state -ceq 'failed' }).Count | Should -Be 1
                        (Get-Content -LiteralPath $result.rawDiagnosticsPath -Raw) | Should -Match '"state":"failed"'
                        $fullReceiptChecks | Should -Be 1
                    }
                    'cancel' {
                        $result.complete | Should -BeFalse
                        $result.status | Should -BeExactly 'cancelled'
                        $result.sampleCount | Should -Be 0
                        $sampleCalls | Should -Be 0
                        $fullReceiptChecks | Should -Be 1
                    }
                    'omit' {
                        $result.complete | Should -BeFalse
                        $result.reason | Should -BeExactly 'missing-sample-terminal-diagnostics'
                        $result.sampleCount | Should -Be 6
                        $result.counters | Should -BeNullOrEmpty
                        $sampleCalls | Should -Be 6
                        $fullReceiptChecks | Should -Be 1
                    }
                    'malformed' {
                        $result.complete | Should -BeFalse
                        $result.reason | Should -BeExactly 'invalid-sample-diagnostic-counters'
                        $result.sampleCount | Should -Be 6
                        $sampleCalls | Should -Be 6
                        $result.sampleDiagnosticCountersValid | Should -BeFalse
                        @($result.sampleDiagnosticErrors | Where-Object { $_ -match 'calls' }).Count | Should -BeGreaterThan 0
                        $fullReceiptChecks | Should -Be 1
                    }
                    'mutation' {
                        $result.complete | Should -BeFalse
                        $result.status | Should -BeExactly 'incomplete'
                        $result.sampleCount | Should -Be 6
                        $sampleCalls | Should -Be 6
                        $fullReceiptChecks | Should -Be 1
                    }
                    'extra-file' {
                        $result.complete | Should -BeFalse
                        $result.status | Should -BeExactly 'incomplete'
                        $result.sampleCount | Should -Be 6
                        $sampleCalls | Should -Be 6
                        $fullReceiptChecks | Should -Be 1
                        @($result.postflightErrors).Count | Should -BeGreaterThan 0
                    }
                    'ledger' {
                        $result.complete | Should -BeFalse
                        $result.reason | Should -BeExactly 'metadata-mismatch'
                        $result.sampleCount | Should -Be 0
                        $sampleCalls | Should -Be 0
                    }
                    'receipt-map' {
                        $result.complete | Should -BeFalse
                        $result.reason | Should -BeExactly 'receipt-map-mismatch'
                        $result.sampleCount | Should -Be 0
                        $sampleCalls | Should -Be 0
                    }
                    { $_ -in @('timing-candidate', 'timing-base', 'timing-authority') } {
                        $result.complete | Should -BeFalse
                        $result.reason | Should -BeExactly 'metadata-mismatch'
                        $result.sampleCount | Should -Be 0
                        $sampleCalls | Should -Be 0
                    }
                    { $_ -in @('report-failed', 'cleanup-failed') } {
                        $result.complete | Should -BeFalse
                        $result.reason | Should -BeExactly 'metadata-mismatch'
                        $result.sampleCount | Should -Be 0
                        $sampleCalls | Should -Be 0
                    }
                    'ff85-unsupported' {
                        $result.complete | Should -BeFalse
                        $result.status | Should -BeExactly 'unsupported'
                        $result.reason | Should -BeExactly 'retained-receipt-api-unsupported'
                        $result.sampleCount | Should -Be 0
                        $sampleCalls | Should -Be 0
                        $fullReceiptChecks | Should -Be 0
                    }
                }
            }
            catch {
                $resultDetail = if ($null -eq $result) { '' } else {
                    " [status=$($result.status); reason=$($result.reason); message=$($result.message); postflight=$(@($result.postflightErrors) -join ' | ')]"
                }
                $scenarioErrors.Add("$($scenario.name)$resultDetail`: $($_.Exception.Message)")
            }
            finally {
                if ($null -ne $fixture -and $null -ne $fixture.module) {
                    Remove-Module -ModuleInfo $fixture.module -Force -ErrorAction SilentlyContinue
                }
            }
        }
        @($scenarioTrace.ToArray()) | Should -Be @(
            'success-3x2', 'same-count-different-bytes', 'insufficient-distinct-footprints', 'sample-exception', 'cancellation',
            'missing-raw-sample-diagnostics', 'malformed-sample-counters', 'postflight-frozen-change', 'postflight-unfrozen-file-added',
            'mismatched-case-ledger', 'wrong-retained-receipt-map', 'timing-candidate-revision-mismatch',
            'timing-base-revision-mismatch', 'timing-authority-revision-mismatch', 'canonical-report-not-accepted',
            'canonical-cleanup-not-accepted', 'formal-ff85-retained-api-unsupported'
        )
        @($scenarioErrors.ToArray()) | Should -BeNullOrEmpty -Because 'every resident sub-scenario must execute before the consolidated assertion'
    }

    # Scenario: resident receipt timing has a separate command and runs only after the accepted canonical source gate.
    # Purpose: keep resident evidence on the protected event-base driver and the exact active authority supervisor.
    It 'UnitT77_routes_resident_timing_through_the_protected_post_gate_entry' {
        $validatePath = Join-Path $script:RepositoryRoot 'scripts/Validate.ps1'
        $tokens = $null
        $parseErrors = $null
        $validateAst = [System.Management.Automation.Language.Parser]::ParseFile($validatePath, [ref]$tokens, [ref]$parseErrors)
        @($parseErrors).Count | Should -Be 0
        $parameterNames = @($validateAst.ParamBlock.Parameters | ForEach-Object { [string]$_.Name.VariablePath.UserPath })
        $issues = [Collections.Generic.List[string]]::new()
        foreach ($requiredParameter in @('SourceResidentTiming', 'ResidentEvidenceRoot')) {
            if ($parameterNames -cnotcontains $requiredParameter) { $issues.Add("CLI parameter is missing: $requiredParameter") }
        }
        $mainTry = @($validateAst.EndBlock.Statements | Where-Object {
            $_ -is [System.Management.Automation.Language.TryStatementAst] -and
            $_.Body.Extent.Text.Contains('Assert-CodeSourceRunRequest')
        } | Select-Object -First 1)
        if ($mainTry.Count -ne 1 -or
            -not $mainTry[0].Body.Extent.Text.Contains('Assert-CodeSourceResidentRunRequest') -or
            -not $mainTry[0].Body.Extent.Text.Contains('Invoke-CodeSourceResidentTiming')) {
            $issues.Add('Top-level request routing does not select the explicit resident guard and resident operation.')
        }

        $workflowPath = Join-Path $script:RepositoryRoot '.github/workflows/validate.yml'
        $workflowText = Get-Content -LiteralPath $workflowPath -Raw
        $gateMarker = '- name: Run full source validation'
        $residentMarker = '- name: Capture resident source timing'
        $uploadMarker = '- name: Upload source validation evidence'
        $gateIndex = $workflowText.IndexOf($gateMarker, [StringComparison]::Ordinal)
        $residentIndex = $workflowText.IndexOf($residentMarker, [StringComparison]::Ordinal)
        $uploadIndex = $workflowText.IndexOf($uploadMarker, [StringComparison]::Ordinal)
        if ($gateIndex -lt 0 -or $residentIndex -le $gateIndex -or $uploadIndex -le $residentIndex) {
            $issues.Add('Resident source timing is not ordered after the full gate and before evidence upload.')
        }
        if ($residentIndex -ge 0 -and $uploadIndex -gt $residentIndex) {
            $residentStep = $workflowText.Substring($residentIndex, $uploadIndex - $residentIndex)
            $activeAuthority = (Get-Content -LiteralPath $script:ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json).authority
            $supervisorBindings = @($activeAuthority.files | Where-Object { $_.path -ceq 'scripts/Invoke-StandardValidation.ps1' })
            if ($supervisorBindings.Count -ne 1) {
                $issues.Add('Active authority does not contain exactly one supervisor binding.')
            }
            else {
                foreach ($requiredBinding in @(
                    'SYP154_CANDIDATE_AUTHORITY_ROOT: ${{ github.workspace }}/authority-8e627',
                    "Join-Path `$env:GITHUB_WORKSPACE 'authority-8e627'",
                    [string]$supervisorBindings[0].sha256
                )) {
                    if (-not $residentStep.Contains($requiredBinding, [StringComparison]::Ordinal)) {
                        $issues.Add("Workflow resident step differs from its active authority binding: $requiredBinding")
                    }
                }
            }
            foreach ($requiredPattern in @(
                '\$protectedDriver', '\$candidateRoot', '\$supervisor', '\$supervisorSha256',
                'Invoke-StandardValidationProcess', '\$pwshPath', '-SourceResidentTiming', '-ResidentEvidenceRoot'
            )) {
                if ($residentStep -notmatch $requiredPattern) { $issues.Add("Workflow resident step is missing protected entry contract: $requiredPattern") }
            }
            if ($residentStep -match 'Join-Path\s+\$candidateRoot\s+''scripts/Validate[.]ps1''' -or
                $residentStep -match 'evidence-index[.]json') {
                $issues.Add('Workflow resident step uses a candidate driver or rewrites the parent-owned evidence index.')
            }
        }
        $issues.ToArray() | Should -BeNullOrEmpty -Because 'the resident timing request stays separate, protected, and downstream of canonical acceptance'
    }

    # Scenario: an accepted source run is admitted into the resident route, while failed report or cleanup evidence is stopped before sampling.
    # Purpose: bind the same prepared run, canonical report, timing receipt, case ledger, owned runtime and selected authority into the sampler call.
    It 'UnitT78_binds_resident_sampling_to_the_accepted_canonical_run' {
        $fixture = New-SourceResidentRouteFixtureForTest -Root (Join-Path $TestDrive ([guid]::NewGuid().ToString('N')))
        $script:SourceRepository = 'https://github.com/SyuanTsai/Skill-Code-Collaboration.git'
        Import-Module -Name $script:DriverPath -Force
        $validatePath = Join-Path $script:RepositoryRoot 'scripts/Validate.ps1'
        $tokens = $null
        $parseErrors = $null
        $validateAst = [System.Management.Automation.Language.Parser]::ParseFile($validatePath, [ref]$tokens, [ref]$parseErrors)
        @($parseErrors).Count | Should -Be 0
        foreach ($functionName in @(
            'Assert-CodeSourceAuthorityCheckout', 'Assert-NoReparseAncestors', 'Assert-PathWithinRoot',
            'Convert-JsonElementToPowerShellObject', 'Get-CodeSourceCoreRunPaths', 'Get-FileSha256',
            'Get-GitBlobSha256', 'Get-ResolvedGitPath', 'Get-CodeSourceResidentRetainedApiContract',
            'Invoke-CodeSourceResidentSampleSeries', 'Invoke-CodeSourceStandardValidationModule',
            'New-CodeSourceStandardValidationModule', 'Read-JsonFile', 'Resolve-GitRevision',
            'Test-PathEqual', 'Test-PathWithinOrEqual', 'Assert-NoDuplicateJsonProperties',
            'Get-CodeSourceResidentCaseCountValues', 'Invoke-CodeSourceResidentTiming'
        )) {
            $definition = $validateAst.Find({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq $functionName }, $true)
            $definition | Should -Not -BeNullOrEmpty -Because "the route depends on production function $functionName"
            if ($null -ne $definition) { . ([scriptblock]::Create($definition.Extent.Text)) }
        }

        $invoke = {
            param([string] $EvidenceRoot, [Parameter(Mandatory)] $RouteFixture)
            $routeArguments = @{
                GitPath = $RouteFixture.gitPath
                PowerShellPath = [string]$RouteFixture.source.fixture.runtimeExecutable
                RepositoryRoot = $RouteFixture.candidateRoot
                CandidateRevision = [string]$RouteFixture.prepared.sourceRevision
                BaseRevision = [string]$RouteFixture.source.baseRevision
                AuthorityConfig = $RouteFixture.authorityConfig
                AuthorityRepositoryRoot = $RouteFixture.authorityRoot
                SourceToolsPath = $RouteFixture.preparedPath
                RunId = [string]$RouteFixture.prepared.runId
                EventName = 'pull_request'
                ArtifactsRoot = $RouteFixture.artifactsRoot
                OutputPath = $RouteFixture.reportPath
                ArtifactsRootWasExplicit = $true
                ResidentEvidenceRoot = $EvidenceRoot
                TrustedToolRoot = [string]$RouteFixture.prepared.pesterRuntime.sourceTrustedToolRoot
                TimeoutSeconds = 10800
            }
            $routeDefinition = $validateAst.Find({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq 'Invoke-CodeSourceResidentTiming' }, $true)
            if (@($routeDefinition.Body.ParamBlock.Parameters | ForEach-Object { [string]$_.Name.VariablePath.UserPath }) -ccontains 'ProtectedBaseRoot') {
                $routeArguments.ProtectedBaseRoot = [string]$RouteFixture.protectedBaseRoot
            }
            Invoke-CodeSourceResidentTiming @routeArguments
        }

        $valid = & $invoke $fixture.evidenceRoot $fixture
        $valid.status | Should -BeExactly 'unsupported'
        $valid.reason | Should -BeExactly 'retained-receipt-api-unsupported'
        $valid.sampleCount | Should -Be 0
        $valid.runId | Should -BeExactly ([string]$fixture.prepared.runId)
        (Test-Path -LiteralPath $valid.summaryPath -PathType Leaf) | Should -BeTrue
        $summary = Get-Content -LiteralPath $valid.summaryPath -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 40
        $summary.status | Should -BeExactly 'unsupported'
        $summary.sampleCount | Should -Be 0
        $summary.runId | Should -BeExactly ([string]$fixture.prepared.runId)

        $fixtureEvidenceParent = Split-Path -Parent $fixture.root
        $wrongRunRootEvidence = Join-Path $fixtureEvidenceParent ("resident-wrong-run-root-$([guid]::NewGuid().ToString('N'))")
        $fixture.report.artifacts.runRoot = Join-Path $fixture.artifactsRoot 'runs/wrong-run-id'
        [IO.File]::WriteAllText($fixture.reportPath, (($fixture.report | ConvertTo-Json -Depth 80 -Compress) + "`n"), [Text.UTF8Encoding]::new($false))
        { & $invoke $wrongRunRootEvidence $fixture } | Should -Throw '*exact prepared Core run namespace*'
        (Test-Path -LiteralPath $wrongRunRootEvidence) | Should -BeFalse

        $fixture.report.artifacts.runRoot = [string]$fixture.coreRunRoot
        [IO.File]::WriteAllText($fixture.reportPath, (($fixture.report | ConvertTo-Json -Depth 80 -Compress) + "`n"), [Text.UTF8Encoding]::new($false))
        $badReportEvidence = Join-Path $fixtureEvidenceParent ("resident-bad-report-$([guid]::NewGuid().ToString('N'))")
        $fixture.report.state = 'FAIL'
        $fixture.report.exitCode = 1
        [IO.File]::WriteAllText($fixture.reportPath, (($fixture.report | ConvertTo-Json -Depth 80 -Compress) + "`n"), [Text.UTF8Encoding]::new($false))
        { & $invoke $badReportEvidence $fixture } | Should -Throw '*partial, cross-run, wrong candidate/base/authority/event, or failing identity*'
        (Test-Path -LiteralPath $badReportEvidence) | Should -BeFalse

        $badCleanupEvidence = Join-Path $fixtureEvidenceParent ("resident-bad-cleanup-$([guid]::NewGuid().ToString('N'))")
        $fixture.report.state = 'PASS'
        $fixture.report.exitCode = 0
        $fixture.timing.cleanupSucceeded = $false
        [IO.File]::WriteAllText($fixture.reportPath, (($fixture.report | ConvertTo-Json -Depth 80 -Compress) + "`n"), [Text.UTF8Encoding]::new($false))
        [IO.File]::WriteAllText($fixture.timingPath, (($fixture.timing | ConvertTo-Json -Depth 20 -Compress) + "`n"), [Text.UTF8Encoding]::new($false))
        { & $invoke $badCleanupEvidence $fixture } | Should -Throw '*cannot pass after cancellation, cleanup failure*'
        (Test-Path -LiteralPath $badCleanupEvidence) | Should -BeFalse

        $script:residentRouteSamplerCalls = 0
        function Invoke-CodeSourceResidentSampleSeries {
            [CmdletBinding()]
            param(
                [Parameter(Mandatory)] $Module, [Parameter(Mandatory)] $Prepared, [Parameter(Mandatory)] $Report,
                [Parameter(Mandatory)] $TimingEvidence, [Parameter(Mandatory)] $CaseLedger,
                [Parameter(Mandatory)][string] $PreparedPath, [Parameter(Mandatory)][string] $TimingEvidencePath,
                [Parameter(Mandatory)][string] $CaseLedgerPath, [Parameter(Mandatory)] $AuthorityPin,
                [Parameter(Mandatory)][string] $RunnerPath, [Parameter(Mandatory)][string] $RunnerSha256,
                [Parameter(Mandatory)][string] $RepositoryRoot, [Parameter(Mandatory)][string] $CandidateRoot,
                [Parameter(Mandatory)][string] $BaseRevision, [Parameter(Mandatory)][string] $ArtifactsRoot,
                [Parameter(Mandatory)][string] $EvidenceRoot, [string] $CancellationPath
            )
            $script:residentRouteSamplerCalls++
            $script:residentRouteSamplerArguments = [pscustomobject]@{
                repositoryRoot = $RepositoryRoot
                candidateRoot = $CandidateRoot
                evidenceRoot = $EvidenceRoot
            }
            return [pscustomobject]@{
                status = 'captured'; reason = 'test-leaf-capture'; sampleCount = 0
                runId = [string]$Prepared.runId; summaryPath = ''
            }
        }
        $routeAuthorityRoot = [string]$fixture.authorityRoot
        $fixture = New-SourceResidentRouteFixtureForTest -Root (Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))) `
            -AuthorityRoot $routeAuthorityRoot
        $protectedBaseFailures = [Collections.Generic.List[string]]::new()
        $forwardedEvidenceRoot = Join-Path (Split-Path -Parent $fixture.root) ("resident-forwarded-root-$([guid]::NewGuid().ToString('N'))")
        $forwarded = $null
        try { $forwarded = & $invoke $forwardedEvidenceRoot $fixture }
        catch { $protectedBaseFailures.Add("valid sampler route failed before root assertions: $($_.Exception.Message)") }
        if ($null -eq $forwarded -or [string]$forwarded.status -cne 'captured') { $protectedBaseFailures.Add('valid sampler route did not reach the captured leaf sampler') }
        if ($script:residentRouteSamplerCalls -ne 1) { $protectedBaseFailures.Add("expected one leaf call before overlap check; observed $script:residentRouteSamplerCalls") }
        if ([string]$script:residentRouteSamplerArguments.repositoryRoot -cne [string]$fixture.protectedBaseRoot) { $protectedBaseFailures.Add('sampler RepositoryRoot did not bind to protectedBaseRoot') }
        if ([string]$script:residentRouteSamplerArguments.candidateRoot -cne [string]$fixture.candidateRoot) { $protectedBaseFailures.Add('sampler CandidateRoot did not remain bound to candidateRoot') }

        $insideProtectedBaseEvidenceRoot = Join-Path $fixture.protectedBaseRoot 'resident-under-protected-base'
        $protectedOverlapError = $null
        try { [void](& $invoke $insideProtectedBaseEvidenceRoot $fixture) }
        catch { $protectedOverlapError = $_.Exception.Message }
        if ($protectedOverlapError -notlike '*overlap*') { $protectedBaseFailures.Add("protected-base evidence overlap was not rejected: $protectedOverlapError") }
        if (Test-Path -LiteralPath $insideProtectedBaseEvidenceRoot) { $protectedBaseFailures.Add('protected-base evidence directory was created before rejection') }
        if ($script:residentRouteSamplerCalls -ne 1) { $protectedBaseFailures.Add('protected-base evidence overlap reached the leaf sampler') }

        $unpassedLedgerFailures = [Collections.Generic.List[string]]::new()
        foreach ($counterName in @('Failed', 'Skipped', 'Inconclusive', 'NotRun')) {
            $fixture = New-SourceResidentRouteFixtureForTest -Root (Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))) `
                -AuthorityRoot $routeAuthorityRoot
            $fixture.caseLedger.reportedCounts.Passed = 0
            $fixture.caseLedger.reportedCounts.$counterName = 1
            [IO.File]::WriteAllText($fixture.caseLedgerPath, (($fixture.caseLedger | ConvertTo-Json -Depth 30 -Compress) + "`n"), [Text.UTF8Encoding]::new($false))
            $fixture.report.sourceValidation.pesterCaseInventory.sha256 = Get-FileSha256 -Path $fixture.caseLedgerPath
            [IO.File]::WriteAllText($fixture.reportPath, (($fixture.report | ConvertTo-Json -Depth 80 -Compress) + "`n"), [Text.UTF8Encoding]::new($false))
            $failedEvidenceRoot = Join-Path (Split-Path -Parent $fixture.root) ("resident-unpassed-$counterName-$([guid]::NewGuid().ToString('N'))")
            $beforeCalls = $script:residentRouteSamplerCalls
            $routeError = $null
            try { [void](& $invoke $failedEvidenceRoot $fixture) }
            catch { $routeError = $_.Exception.Message }
            if ($routeError -notlike '*requires every discovered Pester case to pass*') { $unpassedLedgerFailures.Add("$counterName did not fail the zero-unpassed case guard: $routeError") }
            if (Test-Path -LiteralPath $failedEvidenceRoot) { $unpassedLedgerFailures.Add("$counterName created resident evidence before rejection") }
            if ($script:residentRouteSamplerCalls -ne $beforeCalls) { $unpassedLedgerFailures.Add("$counterName reached the leaf sampler") }
        }
        $typedCountScenarios = @(
            [pscustomobject]@{ field = 'Passed'; value = [double]1.5; rawJsonValue = $null; rangeFailure = $false }
            [pscustomobject]@{ field = 'Failed'; value = [double]0.5; rawJsonValue = $null; rangeFailure = $false }
            [pscustomobject]@{ field = 'Skipped'; value = '0'; rawJsonValue = $null; rangeFailure = $false }
            [pscustomobject]@{ field = 'Inconclusive'; value = [bool]$false; rawJsonValue = $null; rangeFailure = $false }
            [pscustomobject]@{ field = 'NotRun'; value = $null; rawJsonValue = $null; rangeFailure = $false }
            [pscustomobject]@{ field = 'caseDiscoveryCount'; value = [double]2.1; rawJsonValue = $null; rangeFailure = $false }
            [pscustomobject]@{ field = 'caseExecutionCount'; value = [double]2.2; rawJsonValue = $null; rangeFailure = $false }
            [pscustomobject]@{ field = 'Passed'; value = [double]::PositiveInfinity; rawJsonValue = '1e400'; rangeFailure = $false }
            [pscustomobject]@{ field = 'Passed'; value = [System.Numerics.BigInteger]::Parse('9223372036854775808'); rawJsonValue = '9223372036854775808'; rangeFailure = $true }
        )
        foreach ($scenario in $typedCountScenarios) {
            $typedRouteFixture = New-SourceResidentRouteFixtureForTest -Root (Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))) `
                -AuthorityRoot $routeAuthorityRoot
            foreach ($name in @('Passed', 'Failed', 'Skipped', 'Inconclusive', 'NotRun')) {
                $typedRouteFixture.caseLedger.reportedCounts.$name = if ($name -ceq 'Passed') { 2 } else { 0 }
            }
            $typedRouteFixture.caseLedger.caseDiscoveryCount = 2
            $typedRouteFixture.caseLedger.caseExecutionCount = 2
            if ($scenario.field -in @('Passed', 'Failed', 'Skipped', 'Inconclusive', 'NotRun')) {
                $typedRouteFixture.caseLedger.reportedCounts.PSObject.Properties[[string]$scenario.field].Value = $scenario.value
            }
            else {
                $typedRouteFixture.caseLedger.PSObject.Properties[[string]$scenario.field].Value = $scenario.value
            }
            $typedLedgerText = $typedRouteFixture.caseLedger | ConvertTo-Json -Depth 30 -Compress
            if ($null -ne $scenario.rawJsonValue) {
                $infinityFragment = '"' + [string]$scenario.field + '":"Infinity"'
                $rawNumberFragment = '"' + [string]$scenario.field + '":' + [string]$scenario.rawJsonValue
                if ($scenario.rawJsonValue -ceq '1e400') {
                    if (-not $typedLedgerText.Contains($infinityFragment)) { $unpassedLedgerFailures.Add("$($scenario.field) non-finite route fixture did not serialize the expected source value") }
                    $typedLedgerText = $typedLedgerText.Replace($infinityFragment, $rawNumberFragment)
                }
                elseif (-not $typedLedgerText.Contains($rawNumberFragment)) {
                    $unpassedLedgerFailures.Add("$($scenario.field) out-of-range route fixture did not emit the exact numeric JSON literal $($scenario.rawJsonValue)")
                }
            }
            [IO.File]::WriteAllText($typedRouteFixture.caseLedgerPath, ($typedLedgerText + "`n"), [Text.UTF8Encoding]::new($false))
            $typedRouteFixture.report.sourceValidation.pesterCaseInventory.sha256 = Get-FileSha256 -Path $typedRouteFixture.caseLedgerPath
            [IO.File]::WriteAllText($typedRouteFixture.reportPath, (($typedRouteFixture.report | ConvertTo-Json -Depth 80 -Compress) + "`n"), [Text.UTF8Encoding]::new($false))
            $typedEvidenceRoot = Join-Path (Split-Path -Parent $typedRouteFixture.root) ("resident-invalid-$($scenario.field)-$([guid]::NewGuid().ToString('N'))")
            $typedSamplerCallsBefore = $script:residentRouteSamplerCalls
            $typedRouteError = $null
            try { [void](& $invoke $typedEvidenceRoot $typedRouteFixture) }
            catch { $typedRouteError = $_.Exception.Message }
            $fieldPattern = [regex]::Escape([string]$scenario.field)
            $diagnosticIsSpecific = $typedRouteError -match "(?i)\b$fieldPattern\b" -and
                $typedRouteError -match '(?i)count' -and $typedRouteError -match '(?i)finite' -and
                $typedRouteError -match '(?i)\bnon[- ]negative\b' -and $typedRouteError -match '(?i)\binteger\b'
            if (-not $diagnosticIsSpecific) { $unpassedLedgerFailures.Add("$($scenario.field) typed count did not name the field and finite non-negative integer contract: $typedRouteError") }
            if ($scenario.rangeFailure -and $typedRouteError -notmatch '(?i)range') { $unpassedLedgerFailures.Add("$($scenario.field) out-of-range count did not explain the supported range: $typedRouteError") }
            if (Test-Path -LiteralPath $typedEvidenceRoot) { $unpassedLedgerFailures.Add("$($scenario.field) typed count created resident evidence before rejection") }
            if ($script:residentRouteSamplerCalls -ne $typedSamplerCallsBefore) { $unpassedLedgerFailures.Add("$($scenario.field) typed count reached the leaf sampler") }
        }

        $routeFailures = [Collections.Generic.List[string]]::new()
        foreach ($failure in @($unpassedLedgerFailures.ToArray())) { $routeFailures.Add($failure) }
        foreach ($failure in @($protectedBaseFailures.ToArray())) { $routeFailures.Add($failure) }
        if ($routeFailures.Count -gt 0) {
            Write-Host ("Resident route boundary failures: " + ($routeFailures.ToArray() | ConvertTo-Json -Compress))
        }
        @($routeFailures.ToArray()) | Should -BeNullOrEmpty -Because 'every resident route boundary must be verified before evidence creation or sampling'
    }

    # Scenario: a legacy protected-driver command shape lacks the optional resident endpoint.
    # Purpose: exercise the workflow's bounded capability probe with a self-contained fixture that does not require Git metadata in the candidate snapshot.
    It 'UnitT79_records_unsupported_for_the_old_protected_driver_without_launching_it' {
        $workflowPath = Join-Path $script:RepositoryRoot '.github/workflows/validate.yml'
        $workflowText = Get-Content -LiteralPath $workflowPath -Raw
        $residentMarker = '- name: Capture resident source timing'
        $uploadMarker = '- name: Upload source validation evidence'
        $residentIndex = $workflowText.IndexOf($residentMarker, [StringComparison]::Ordinal)
        $uploadIndex = $workflowText.IndexOf($uploadMarker, [StringComparison]::Ordinal)
        ($residentIndex -ge 0 -and $uploadIndex -gt $residentIndex) | Should -BeTrue
        $residentStep = $workflowText.Substring($residentIndex, $uploadIndex - $residentIndex)
        $runMarker = 'run: |'
        $runIndex = $residentStep.IndexOf($runMarker, [StringComparison]::Ordinal)
        ($runIndex -ge 0) | Should -BeTrue
        $scriptLines = @($residentStep.Substring($runIndex + $runMarker.Length) -split "`r?`n" | ForEach-Object {
            if ($_.StartsWith('          ')) { $_.Substring(10) } elseif ([string]::IsNullOrWhiteSpace($_)) { '' } else { $_ }
        })
        $workflowScript = $scriptLines -join [Environment]::NewLine
        $tokens = $null
        $parseErrors = $null
        $workflowAst = [System.Management.Automation.Language.Parser]::ParseInput($workflowScript, [ref]$tokens, [ref]$parseErrors)
        @($parseErrors).Count | Should -Be 0
        $probeAst = $workflowAst.Find({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq 'Invoke-ResidentDriverCompatibilityProbe' }, $true)
        $probeAst | Should -Not -BeNullOrEmpty

        $oldDriverText = @'
[CmdletBinding()]
param(
    [string] $RepositoryRoot,
    [string] $BaseCommit,
    [switch] $PrepareSourceTools,
    [switch] $SourceValidation,
    [string] $SourceToolsPath
)
$sentinelPath = [Environment]::GetEnvironmentVariable('SYP326_TEST_LEGACY_DRIVER_EXECUTION_SENTINEL', 'Process')
if ([string]::IsNullOrWhiteSpace($sentinelPath)) { throw 'Legacy protected driver fixture was executed without its test sentinel path.' }
[IO.File]::WriteAllText($sentinelPath, 'executed', [Text.UTF8Encoding]::new($false))
throw 'Legacy protected driver fixture must not be executed.'
'@
        $oldDriver = Write-SourceBindingFixtureFile -Path (Join-Path $TestDrive (([guid]::NewGuid().ToString('N')) + '-Validate.ps1')) -Text $oldDriverText
        . ([scriptblock]::Create($probeAst.Extent.Text))
        $evidenceRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $sentinelPath = Join-Path $TestDrive 'legacy-driver-executed.txt'
        $sentinelVariableName = 'SYP326_TEST_LEGACY_DRIVER_EXECUTION_SENTINEL'
        $previousSentinelPath = [Environment]::GetEnvironmentVariable($sentinelVariableName, 'Process')
        [Environment]::SetEnvironmentVariable($sentinelVariableName, $sentinelPath, 'Process')
        $script:residentNativeLaunchCount = 0
        function Invoke-StandardValidationProcess { $script:residentNativeLaunchCount++ }
        try {
            $probe = Invoke-ResidentDriverCompatibilityProbe -DriverPath $oldDriver -EvidenceRoot $evidenceRoot `
                -CandidateRevision ('a' * 40) -BaseRevision ('b' * 40) -RunId ('c' * 32)
        }
        finally {
            [Environment]::SetEnvironmentVariable($sentinelVariableName, $previousSentinelPath, 'Process')
        }

        $probe.supported | Should -BeFalse
        $probe.reason | Should -BeExactly 'protected-driver-resident-entry-unsupported'
        $script:residentNativeLaunchCount | Should -Be 0
        (Test-Path -LiteralPath $sentinelPath -PathType Leaf) | Should -BeFalse
        (Test-Path -LiteralPath (Join-Path $evidenceRoot 'resident-timing-summary.json') -PathType Leaf) | Should -BeTrue
        $summary = Get-Content -LiteralPath (Join-Path $evidenceRoot 'resident-timing-summary.json') -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 20
        $summary.status | Should -BeExactly 'unsupported'
        $summary.reason | Should -BeExactly 'protected-driver-resident-entry-unsupported'
        $summary.runId | Should -BeExactly ('c' * 32)
        $probeParameters = @($probeAst.Extent.Text)
        $probeParameters[0] | Should -Match 'Get-Command'

        $probeCallIndex = $workflowScript.IndexOf('Invoke-ResidentDriverCompatibilityProbe', [StringComparison]::Ordinal)
        $unsupportedGuardIndex = $workflowScript.IndexOf('if (-not $driverCapability.supported)', [StringComparison]::Ordinal)
        $launchIndex = $workflowScript.IndexOf('Invoke-StandardValidationProcess', [StringComparison]::Ordinal)
        ($probeCallIndex -ge 0 -and $unsupportedGuardIndex -gt $probeCallIndex -and $launchIndex -gt $unsupportedGuardIndex) | Should -BeTrue
        $workflowScript.Substring($unsupportedGuardIndex, $launchIndex - $unsupportedGuardIndex) | Should -Match 'return'
        $workflowScript | Should -Not -Match 'Join-Path\s+\$candidateRoot\s+''scripts/Validate[.]ps1'''
    }

    # Scenario: the hosted workflow resolves the executable basename for its Windows-owned PowerShell runtime.
    # Purpose: accept the prepared pwsh.exe identity and reject an extensionless pwsh path on Windows.
    It 'UnitT80_requires_the_prepared_windows_resident_runtime_executable' {
        $workflowPath = Join-Path $script:RepositoryRoot '.github/workflows/validate.yml'
        $workflowText = Get-Content -LiteralPath $workflowPath -Raw
        $residentMarker = '- name: Capture resident source timing'
        $uploadMarker = '- name: Upload source validation evidence'
        $residentIndex = $workflowText.IndexOf($residentMarker, [StringComparison]::Ordinal)
        $uploadIndex = $workflowText.IndexOf($uploadMarker, [StringComparison]::Ordinal)
        ($residentIndex -ge 0 -and $uploadIndex -gt $residentIndex) | Should -BeTrue
        $residentStep = $workflowText.Substring($residentIndex, $uploadIndex - $residentIndex)
        $runIndex = $residentStep.IndexOf('run: |', [StringComparison]::Ordinal)
        ($runIndex -ge 0) | Should -BeTrue
        $scriptLines = @($residentStep.Substring($runIndex + 'run: |'.Length) -split "`r?`n" | ForEach-Object {
            if ($_.StartsWith('          ')) { $_.Substring(10) } elseif ([string]::IsNullOrWhiteSpace($_)) { '' } else { $_ }
        })
        $workflowScript = $scriptLines -join [Environment]::NewLine
        $tokens = $null
        $parseErrors = $null
        $workflowAst = [System.Management.Automation.Language.Parser]::ParseInput($workflowScript, [ref]$tokens, [ref]$parseErrors)
        @($parseErrors).Count | Should -Be 0
        $runtimeAst = $workflowAst.Find({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq 'Assert-ResidentDriverPreparedRuntime' }, $true)
        $runtimeGuardAst = $workflowAst.Find({
            param($node)
            $node -is [System.Management.Automation.Language.IfStatementAst] -and
                $node.Extent.Text.Contains('Prepared owned PowerShell runtime') -and
                $node.Extent.Text.Contains('runtimeExecutableSha256')
        }, $true)
        ($null -ne $runtimeAst -or $null -ne $runtimeGuardAst) | Should -BeTrue
        if ($null -eq $runtimeAst -and $null -eq $runtimeGuardAst) { return }
        if ($null -ne $runtimeAst) {
            . ([scriptblock]::Create($runtimeAst.Extent.Text))
            $workflowScript | Should -Match 'Assert-ResidentDriverPreparedRuntime\s+-Prepared\s+\$prepared'
        }
        $runtimeGuardScript = if ($null -ne $runtimeGuardAst) { [scriptblock]::Create($runtimeGuardAst.Extent.Text) } else { $null }

        $ownedRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $runtimeRoot = Join-Path $ownedRoot 'runtime'
        $trustedToolRoot = Join-Path $ownedRoot 'trusted-tools'
        [void](New-Item -ItemType Directory -Path $runtimeRoot -Force)
        [void](New-Item -ItemType Directory -Path $trustedToolRoot -Force)
        $windowsExecutable = Join-Path $runtimeRoot 'pwsh.exe'
        $extensionlessExecutable = Join-Path $runtimeRoot 'pwsh'
        [IO.File]::WriteAllText($windowsExecutable, 'prepared Windows runtime bytes', [Text.UTF8Encoding]::new($false))
        [IO.File]::WriteAllText($extensionlessExecutable, 'alternate runtime bytes', [Text.UTF8Encoding]::new($false))
        $prepared = [pscustomobject]@{
            ownedRoot = $ownedRoot
            pesterRuntime = [pscustomobject]@{
                runtimeRoot = $runtimeRoot
                runtimeExecutablePath = $windowsExecutable
                runtimeExecutableSha256 = (Get-FileHash -LiteralPath $windowsExecutable -Algorithm SHA256).Hash.ToLowerInvariant()
                sourceTrustedToolRoot = $trustedToolRoot
            }
        }

        $validatePreparedRuntime = {
            param($Candidate)
            if ($null -ne $runtimeAst) {
                return (Assert-ResidentDriverPreparedRuntime -Prepared $Candidate -Windows $true)
            }
            $prepared = $Candidate
            $runtimeRoot = [IO.Path]::GetFullPath([string]$prepared.pesterRuntime.runtimeRoot)
            $trustedToolRoot = [IO.Path]::GetFullPath([string]$prepared.pesterRuntime.sourceTrustedToolRoot)
            $pwshPath = [IO.Path]::GetFullPath([string]$prepared.pesterRuntime.runtimeExecutablePath)
            . $runtimeGuardScript
            return [pscustomobject]@{ runtimeExecutablePath = $pwshPath }
        }
        $windowsAccepted = $true
        try { $resolved = & $validatePreparedRuntime $prepared } catch { $windowsAccepted = $false }
        $resolvedWindowsPath = if ($null -ne $resolved) { [string]$resolved.runtimeExecutablePath } else { '' }
        $prepared.pesterRuntime.runtimeExecutablePath = $extensionlessExecutable
        $prepared.pesterRuntime.runtimeExecutableSha256 = (Get-FileHash -LiteralPath $extensionlessExecutable -Algorithm SHA256).Hash.ToLowerInvariant()
        $extensionlessRejected = $false
        try { [void](& $validatePreparedRuntime $prepared) } catch { $extensionlessRejected = $true }
        ($windowsAccepted -and $extensionlessRejected) | Should -BeTrue -Because 'a Windows prepared run must name pwsh.exe, and an extensionless pwsh path must not be accepted'
        $resolvedWindowsPath | Should -BeExactly ([IO.Path]::GetFullPath($windowsExecutable))
    }

    # Scenario: an explicitly false optional switch must keep ordinary Core on the legacy request guard.
    # Purpose: preserve compatibility for callers that bind SourceResidentTiming:$false.
    It 'UnitT81_keeps_explicitly_false_resident_switch_on_the_legacy_core_guard' {
        Import-Module -Name $script:DriverPath -Force
        $validatePath = Join-Path $script:RepositoryRoot 'scripts/Validate.ps1'
        $tokens = $null
        $parseErrors = $null
        $validateAst = [System.Management.Automation.Language.Parser]::ParseFile($validatePath, [ref]$tokens, [ref]$parseErrors)
        @($parseErrors).Count | Should -Be 0
        $mainTry = @($validateAst.EndBlock.Statements | Where-Object {
            $_ -is [System.Management.Automation.Language.TryStatementAst] -and
            $_.Body.Extent.Text.Contains('Assert-CodeSourceRunRequest')
        } | Select-Object -First 1)
        $mainTry.Count | Should -Be 1
        if ($mainTry.Count -ne 1) { return }
        $statements = @($mainTry[0].Body.Statements)
        $assignmentIndex = -1
        $guardIndex = -1
        for ($index = 0; $index -lt $statements.Count; $index++) {
            $statement = $statements[$index]
            if ($statement -is [System.Management.Automation.Language.AssignmentStatementAst] -and
                $statement.Left -is [System.Management.Automation.Language.VariableExpressionAst] -and
                [string]$statement.Left.VariablePath.UserPath -ceq 'sourceRequestArgs') { $assignmentIndex = $index }
            if ($statement -is [System.Management.Automation.Language.TryStatementAst] -and
                $statement.Body.Extent.Text.Contains('Assert-CodeSourceRunRequest') -and
                $statement.Body.Extent.Text.Contains('Assert-CodeSourceResidentRunRequest')) { $guardIndex = $index; break }
        }
        ($assignmentIndex -ge 0 -and $guardIndex -gt $assignmentIndex) | Should -BeTrue
        if ($assignmentIndex -lt 0 -or $guardIndex -le $assignmentIndex) { return }
        $routerText = ($statements[$assignmentIndex..$guardIndex] | ForEach-Object { $_.Extent.Text }) -join [Environment]::NewLine
        $wrapperTemplate = @'
function Invoke-SourceResidentFalseGuardCase {
    [CmdletBinding()]
    param([switch] $SourceResidentTiming)
    $ExecutionMode = 'Run'
    $AdapterVersion = 2
    $PrepareSourceTools = $false
    $SourceValidation = $false
    $SourceToolsPath = ''
    $config = [pscustomobject]@{ authority = [pscustomobject]@{ commit = '' } }
    $script:SourceModeRequested = $false
__ROUTER_BODY__
    return $sourceRequest
}
'@
        $wrapperText = $wrapperTemplate.Replace('__ROUTER_BODY__', $routerText)
        . ([scriptblock]::Create($wrapperText))
        Invoke-SourceResidentFalseGuardCase -SourceResidentTiming:$false | Should -BeExactly 'Core'
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

    # Scenario: canonical ledger JSON uses types that the sampler's integer casts can disguise independently.
    # Purpose: exercise the real JSON reader and prove each count field is rejected before the first resident sample.
    It 'UnitT82_rejects_noninteger_resident_case_ledger_values_before_sampling' {
        Import-Module -Name $script:DriverPath -Force
        $validatePath = Join-Path $script:RepositoryRoot 'scripts/Validate.ps1'
        $tokens = $null
        $parseErrors = $null
        $validateAst = [System.Management.Automation.Language.Parser]::ParseFile($validatePath, [ref]$tokens, [ref]$parseErrors)
        @($parseErrors).Count | Should -Be 0
        foreach ($functionName in @('Assert-NoDuplicateJsonProperties', 'Convert-JsonElementToPowerShellObject', 'Read-JsonFile')) {
            $definition = $validateAst.Find({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq $functionName }, $true)
            $definition | Should -Not -BeNullOrEmpty -Because "the resident test reads the ledger through production helper $functionName"
            if ($null -ne $definition) { . ([scriptblock]::Create($definition.Extent.Text)) }
        }
        $scenarios = @(
            [pscustomobject]@{ field = 'Passed'; value = [double]1.5; jsonType = 'System.Double'; rawJsonValue = $null; rangeFailure = $false }
            [pscustomobject]@{ field = 'Failed'; value = [double]0.5; jsonType = 'System.Double'; rawJsonValue = $null; rangeFailure = $false }
            [pscustomobject]@{ field = 'Skipped'; value = '0'; jsonType = 'System.String'; rawJsonValue = $null; rangeFailure = $false }
            [pscustomobject]@{ field = 'Inconclusive'; value = [bool]$false; jsonType = 'System.Boolean'; rawJsonValue = $null; rangeFailure = $false }
            [pscustomobject]@{ field = 'NotRun'; value = $null; jsonType = 'null'; rawJsonValue = $null; rangeFailure = $false }
            [pscustomobject]@{ field = 'caseDiscoveryCount'; value = [double]2.1; jsonType = 'System.Double'; rawJsonValue = $null; rangeFailure = $false }
            [pscustomobject]@{ field = 'caseExecutionCount'; value = [double]2.2; jsonType = 'System.Double'; rawJsonValue = $null; rangeFailure = $false }
            [pscustomobject]@{ field = 'Passed'; value = [double]::PositiveInfinity; jsonType = 'System.Double'; rawJsonValue = '1e400'; rangeFailure = $false }
            [pscustomobject]@{ field = 'Passed'; value = [System.Numerics.BigInteger]::Parse('9223372036854775808'); rawJsonValue = '9223372036854775808'; rangeFailure = $true }
        )
        $failures = [Collections.Generic.List[string]]::new()
        $readerObservations = [Collections.Generic.List[string]]::new()
        foreach ($scenario in $scenarios) {
            $fixture = New-SourceResidentSeriesFixtureForTest -Root (Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))) -FailureSample 1
            foreach ($name in @('Passed', 'Failed', 'Skipped', 'Inconclusive', 'NotRun')) {
                $fixture.caseLedger.reportedCounts.$name = if ($name -ceq 'Passed') { 2 } else { 0 }
            }
            $fixture.caseLedger.caseDiscoveryCount = 2
            $fixture.caseLedger.caseExecutionCount = 2
            if ($scenario.field -in @('Passed', 'Failed', 'Skipped', 'Inconclusive', 'NotRun')) {
                $fixture.caseLedger.reportedCounts.PSObject.Properties[[string]$scenario.field].Value = $scenario.value
            }
            else {
                $fixture.caseLedger.PSObject.Properties[[string]$scenario.field].Value = $scenario.value
            }
            $ledgerText = $fixture.caseLedger | ConvertTo-Json -Depth 30 -Compress
            if ($null -ne $scenario.rawJsonValue) {
                $infinityFragment = '"' + [string]$scenario.field + '":"Infinity"'
                $rawNumberFragment = '"' + [string]$scenario.field + '":' + [string]$scenario.rawJsonValue
                if ($scenario.rawJsonValue -ceq '1e400') {
                    if (-not $ledgerText.Contains($infinityFragment)) { $failures.Add("$($scenario.field) non-finite sampler fixture did not serialize the expected source value") }
                    $ledgerText = $ledgerText.Replace($infinityFragment, $rawNumberFragment)
                }
                elseif (-not $ledgerText.Contains($rawNumberFragment)) {
                    $failures.Add("$($scenario.field) out-of-range sampler fixture did not emit the exact numeric JSON literal $($scenario.rawJsonValue)")
                }
            }
            $ledgerText += "`n"
            [IO.File]::WriteAllText($fixture.caseLedgerPath, $ledgerText, [Text.UTF8Encoding]::new($false))
            $fixture.report.sourceValidation.pesterCaseInventory.sha256 = Get-SourceBindingFixtureHash -Path $fixture.caseLedgerPath
            [IO.File]::WriteAllText($fixture.reportPath, (($fixture.report | ConvertTo-Json -Depth 40 -Compress) + "`n"), [Text.UTF8Encoding]::new($false))
            $fixture.reportSha256 = Get-SourceBindingFixtureHash -Path $fixture.reportPath

            $readLedger = Read-JsonFile -Path $fixture.caseLedgerPath -Context "Typed resident ledger test $($scenario.field)"
            $readValue = if ($scenario.field -in @('Passed', 'Failed', 'Skipped', 'Inconclusive', 'NotRun')) {
                $readLedger.reportedCounts.PSObject.Properties[[string]$scenario.field].Value
            }
            else { $readLedger.PSObject.Properties[[string]$scenario.field].Value }
            $actualReadType = if ($null -eq $readValue) { 'null' } else { $readValue.GetType().FullName }
            $actualReadValue = if ($null -eq $readValue) { '<null>' } else { [string]$readValue }
            if ($null -ne $scenario.rawJsonValue) { $readerObservations.Add("$($scenario.field) raw=$($scenario.rawJsonValue) readType=$actualReadType readValue=$actualReadValue") }
            if ($scenario.rawJsonValue -ceq '1e400') {
                if ($actualReadType -cne 'System.Double' -or -not [double]::IsPositiveInfinity([double]$readValue)) {
                    $failures.Add("$($scenario.field) raw 1e400 did not remain a positive-infinity Double in Read-JsonFile: type=$actualReadType value=$actualReadValue")
                }
            }
            elseif ($scenario.rangeFailure) {
                $numericTypes = @('System.Byte', 'System.SByte', 'System.Int16', 'System.UInt16', 'System.Int32', 'System.UInt32', 'System.Int64', 'System.UInt64', 'System.Single', 'System.Double', 'System.Decimal', 'System.Numerics.BigInteger')
                if ($actualReadType -notin $numericTypes) { $failures.Add("$($scenario.field) out-of-range JSON literal was not read as a numeric type: $actualReadType") }
            }
            elseif ([string]$scenario.jsonType -ceq 'null') {
                if ($null -ne $readValue) { $failures.Add("$($scenario.field) JSON null did not remain null in Read-JsonFile") }
            }
            elseif ($null -eq $readValue -or $readValue.GetType().FullName -cne [string]$scenario.jsonType) {
                $actualType = if ($null -eq $readValue) { 'null' } else { $readValue.GetType().FullName }
                $failures.Add("$($scenario.field) JSON type changed in Read-JsonFile: expected $($scenario.jsonType), observed $actualType")
            }

            $result = $null
            $invokeError = $null
            try { $result = Invoke-SourceResidentSeriesForTest -Fixture $fixture }
            catch { $invokeError = $_.Exception.Message }
            if ($null -ne $invokeError) { $failures.Add("$($scenario.field) threw before returning a rejection receipt: $invokeError") }
            elseif ($result.complete -or $result.reason -cne 'metadata-mismatch' -or [int]$result.sampleCount -ne 0) {
                $failures.Add("$($scenario.field) did not reject its malformed count before sampling (complete=$($result.complete), reason=$($result.reason), samples=$($result.sampleCount))")
            }
            if ($null -ne $result) {
                $fieldPattern = [regex]::Escape([string]$scenario.field)
                $message = [string]$result.message
                $diagnosticIsSpecific = $message -match "(?i)\b$fieldPattern\b" -and
                    $message -match '(?i)count' -and $message -match '(?i)finite' -and
                    $message -match '(?i)\bnon[- ]negative\b' -and $message -match '(?i)\binteger\b'
                if (-not $diagnosticIsSpecific) { $failures.Add("$($scenario.field) did not return a field-specific finite non-negative integer count message: $message") }
                if ($scenario.rangeFailure -and $message -notmatch '(?i)range') { $failures.Add("$($scenario.field) out-of-range sampler count did not explain the supported range: $message") }
                if (@($result.samples).Count -ne 0) { $failures.Add("$($scenario.field) retained $(@($result.samples).Count) sample record(s) before count rejection") }
                $sampleOrdinals = @($result.samples | Where-Object { $_.PSObject.Properties.Name -contains 'sampleIndex' -or $_.PSObject.Properties.Name -contains 'sampleOrdinal' })
                if ($sampleOrdinals.Count -ne 0) { $failures.Add("$($scenario.field) recorded sample ordinals before count rejection") }
            }
            $sampleCalls = [int](& $fixture.module { $script:SourceResidentFixtureCalls })
            if ($sampleCalls -ne 0) { $failures.Add("$($scenario.field) reached the retained sampler $sampleCalls time(s)") }
        }
        if ($readerObservations.Count -gt 0) { Write-Host ("Typed resident ledger raw JSON reader observations: " + ($readerObservations.ToArray() | ConvertTo-Json -Compress)) }
        if ($failures.Count -gt 0) { Write-Host ("Typed resident ledger failures: " + ($failures.ToArray() | ConvertTo-Json -Compress)) }
        @($failures.ToArray()) | Should -BeNullOrEmpty -Because 'each JSON count value must remain typed and be rejected before the retained sampler runs'
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
        function New-UnitT44Arguments {
            param([Parameter(Mandatory)] $Fixture)
            return @{
                Report = $Fixture.report; Prepared = $Fixture.fixture.prepared
                CandidateRevision = $Fixture.fixture.candidateRevision; BaseRevision = $Fixture.baseRevision
                AuthorityRevision = $Fixture.fixture.authorityRevision; EventName = 'pull_request'
                ArtifactsRoot = $Fixture.artifactRoot; OutputPath = $Fixture.report.artifacts.outputPath
                ProcessExitCode = 0; CleanupSucceeded = $true
            }
        }
        function Get-UnitT44EventBinding {
            param([Parameter(Mandatory)] $Fixture, [Parameter(Mandatory)][string] $ToolId)
            $event = @($Fixture.report.sourceValidation.events | Where-Object { [string]$_.toolId -ceq $ToolId })[0]
            $record = Get-Content -LiteralPath ([string]$event.outputPath) -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 60
            return [pscustomobject]@{ event = $event; record = $record; path = [string]$event.outputPath }
        }
        function Save-UnitT44EventRecord {
            param([Parameter(Mandatory)] $Binding)
            [IO.File]::WriteAllText($Binding.path, (($Binding.record | ConvertTo-Json -Depth 60 -Compress) + "`n"), [Text.UTF8Encoding]::new($false))
        }
        $arguments = New-UnitT44Arguments -Fixture $reportFixture
        $formatFixture = Get-UnitT44EventBinding -Fixture $reportFixture -ToolId 'skill-validator'
        [IO.File]::WriteAllText($formatFixture.path, (($formatFixture.record | ConvertTo-Json -Depth 60) + "`n"), [Text.UTF8Encoding]::new($false))
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

        foreach ($streamName in @('stdout', 'stderr')) {
            $streamFixture = New-SourceReportFixture -Root (Join-Path $fixtureRoot "$streamName-tamper")
            $streamArguments = New-UnitT44Arguments -Fixture $streamFixture
            $streamBinding = Get-UnitT44EventBinding -Fixture $streamFixture -ToolId 'skill-validator'
            $streamBinding.record.$streamName = [string]$streamBinding.record.$streamName + 'tampered'
            Save-UnitT44EventRecord -Binding $streamBinding
            { Assert-CodeSourceReportBinding @streamArguments } | Should -Throw '*output hash differs from its report binding*'
        }

        $hashFixture = New-SourceReportFixture -Root (Join-Path $fixtureRoot 'hash-tamper')
        $hashArguments = New-UnitT44Arguments -Fixture $hashFixture
        (@($hashFixture.report.sourceValidation.events | Where-Object { $_.toolId -ceq 'skill-validator' })[0]).outputSha256 = '0' * 64
        { Assert-CodeSourceReportBinding @hashArguments } | Should -Throw '*output hash differs from its report binding*'

        $rawIdentityFixture = New-SourceReportFixture -Root (Join-Path $fixtureRoot 'raw-identity-tamper')
        $rawIdentityArguments = New-UnitT44Arguments -Fixture $rawIdentityFixture
        $rawIdentityBinding = Get-UnitT44EventBinding -Fixture $rawIdentityFixture -ToolId 'skill-validator'
        $rawIdentityBinding.record.candidateId = 'e' * 64
        Save-UnitT44EventRecord -Binding $rawIdentityBinding
        { Assert-CodeSourceReportBinding @rawIdentityArguments } | Should -Throw '*does not bind report metadata*'

        $reportIdentityFixture = New-SourceReportFixture -Root (Join-Path $fixtureRoot 'report-identity-tamper')
        $reportIdentityArguments = New-UnitT44Arguments -Fixture $reportIdentityFixture
        (@($reportIdentityFixture.report.sourceValidation.events | Where-Object { $_.toolId -ceq 'skill-validator' })[0]).eventId = [guid]::NewGuid().ToString('D')
        { Assert-CodeSourceReportBinding @reportIdentityArguments } | Should -Throw '*does not bind report metadata*'

        $statusFixture = New-SourceReportFixture -Root (Join-Path $fixtureRoot 'status-tamper')
        $statusArguments = New-UnitT44Arguments -Fixture $statusFixture
        $statusBinding = Get-UnitT44EventBinding -Fixture $statusFixture -ToolId 'skill-validator'
        $statusBinding.record.process.status = 'failed'
        Save-UnitT44EventRecord -Binding $statusBinding
        { Assert-CodeSourceReportBinding @statusArguments } | Should -Throw '*clean passing tool process*'

        foreach ($exitCodeSource in @('report', 'process')) {
            $exitFixture = New-SourceReportFixture -Root (Join-Path $fixtureRoot "$exitCodeSource-exit-code-tamper")
            $exitArguments = New-UnitT44Arguments -Fixture $exitFixture
            $exitBinding = Get-UnitT44EventBinding -Fixture $exitFixture -ToolId 'skill-validator'
            if ($exitCodeSource -ceq 'report') {
                $exitBinding.event.exitCode = $null
            }
            else {
                $exitBinding.record.process.exitCode = '0'
                Save-UnitT44EventRecord -Binding $exitBinding
            }
            { Assert-CodeSourceReportBinding @exitArguments } | Should -Throw '*clean passing tool process*'
        }

        $cleanupFixture = New-SourceReportFixture -Root (Join-Path $fixtureRoot 'cleanup-tamper')
        $cleanupArguments = New-UnitT44Arguments -Fixture $cleanupFixture
        (@($cleanupFixture.report.sourceValidation.events | Where-Object { $_.toolId -ceq 'skill-validator' })[0]).cleanedUp = 'true'
        { Assert-CodeSourceReportBinding @cleanupArguments } | Should -Throw '*clean passing tool process*'

        $processCleanupFixture = New-SourceReportFixture -Root (Join-Path $fixtureRoot 'process-cleanup-tamper')
        $processCleanupArguments = New-UnitT44Arguments -Fixture $processCleanupFixture
        $processCleanupBinding = Get-UnitT44EventBinding -Fixture $processCleanupFixture -ToolId 'skill-validator'
        $processCleanupBinding.record.process.cleanedUp = $false
        Save-UnitT44EventRecord -Binding $processCleanupBinding
        { Assert-CodeSourceReportBinding @processCleanupArguments } | Should -Throw '*clean passing tool process*'

        $pathFixture = New-SourceReportFixture -Root (Join-Path $fixtureRoot 'path-tamper')
        $pathArguments = New-UnitT44Arguments -Fixture $pathFixture
        (@($pathFixture.report.sourceValidation.events | Where-Object { $_.toolId -ceq 'skill-validator' })[0]).outputPath = Join-Path $fixtureRoot 'outside-event.json'
        { Assert-CodeSourceReportBinding @pathArguments } | Should -Throw '*missing or outside the Core run root*'

        $nativeFixture = New-SourceReportFixture -Root (Join-Path $fixtureRoot 'native-file-tamper')
        $nativeArguments = New-UnitT44Arguments -Fixture $nativeFixture
        $nativeBinding = Get-UnitT44EventBinding -Fixture $nativeFixture -ToolId 'skill-validator'
        $nativeEnvelope = ConvertFrom-Json -InputObject ([string]$nativeBinding.record.stdout) -Depth 60
        [IO.File]::AppendAllText([string]$nativeEnvelope.nativeReports[0].path, 'tampered', [Text.UTF8Encoding]::new($false))
        { Assert-CodeSourceReportBinding @nativeArguments } | Should -Throw '*Source native JSON report hash differs from its report binding*'

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
            supervisorApiCall = $script:A031LastProcessInvocation
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
            supervisorApiCall = $script:A031LastProcessInvocation
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
        [void](Save-A031EvidenceJson -Name 'nonzero-child-supervisor.json' -Value ([ordered]@{ authorityRunner = $supervisor; supervisorApiCall = $script:A031LastProcessInvocation; childPath = $exitPath; childSha256 = Get-SourceBindingFixtureHash -Path $exitPath; supervisorResult = $processResult }))
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
        try {
            [void](New-Item -ItemType Junction -Path $junctionRunRoot -Target $junctionTarget -ErrorAction Stop)
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

    # Scenario: canonical CI validates the immutable candidate through the protected event-base source gate.
    # Purpose: require the Windows source route, same-run setup and validation, retained evidence, and existing mirror contexts.
    It 'InterT20_runs_the_full_source_gate_from_the_protected_event_base' {
        $workflow = Get-Content -LiteralPath (Join-Path $script:RepositoryRoot '.github/workflows/validate.yml') -Raw
        $integrationTest = Get-Content -LiteralPath (Join-Path $script:RepositoryRoot 'tests/CommonToolReportIntegration.Tests.ps1') -Raw

        $workflow | Should -Match ([regex]::Escape('ref: ${{ github.event.pull_request.base.sha || (github.event.before != ''0000000000000000000000000000000000000000'' && github.event.before) || github.sha }}'))
        $workflow | Should -Match ([regex]::Escape('ref: ${{ github.event.pull_request.head.sha || github.sha }}'))
        $workflow | Should -Not -Match 'github\.event\.pull_request\.merge_commit_sha'
        $workflow | Should -Match 'runs-on:\s*windows-latest'
        $workflow | Should -Match 'Checkout immutable 8e authority fixture'
        $workflow | Should -Match 'ref:\s*8e627baf54bd6e47862e6291b25e71cc45a2f2b7'
        $workflow | Should -Match 'path:\s*authority-8e627'
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

    # Scenario: CI receives a candidate branch whose driver and workflow have changed.
    # Purpose: require the exact protected base driver to validate an immutable candidate checkout.
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

    # Scenario: the resident raw timing sink throws from Flush after postflight completes.
    # Purpose: exercise the actual extracted production cleanup path and require timing state, Console.Error, and the earliest result to survive.
    It 'UnitT83_preserves_resident_state_when_raw_timing_flush_fails' {
        # Given: a fresh resident fixture and a controlled real-file stream armed only after the final postflight receipt check.
        # When: the extracted production sampler reaches raw-writer Flush and the stream throws once.
        # Then: the result stays incomplete, all four module values and Console.Error are restored, and the secondary cleanup error is retained.
        Invoke-SourceResidentSinkFaultCaseForTest -Mode Flush
    }

    # Scenario: the resident raw timing sink throws from Dispose after Flush succeeds.
    # Purpose: exercise production disposal and require cleanup evidence without losing state restoration.
    It 'UnitT84_preserves_resident_state_when_raw_timing_dispose_fails' {
        # Given: a fresh resident fixture and a controlled real-file stream armed only after the final postflight receipt check.
        # When: the extracted production sampler disposes the raw stream and the stream closes its backing file before throwing once.
        # Then: the result stays incomplete, all four module values and Console.Error are restored, and the secondary disposal error is retained.
        Invoke-SourceResidentSinkFaultCaseForTest -Mode Dispose
    }

    # Scenario: a sample failure precedes a raw timing sink Flush failure during cleanup.
    # Purpose: preserve the original sample error and record the later sink failure as secondary cleanup evidence.
    It 'UnitT85_keeps_the_sample_error_when_raw_timing_flush_also_fails' {
        # Given: a fresh resident fixture whose first sample throws and a controlled stream armed after postflight.
        # When: the postflight cleanup Flush also throws.
        # Then: the sample-exception reason and message remain primary while sink failure evidence is retained and state is restored.
        Invoke-SourceResidentSinkFaultCaseForTest -Mode Flush -FailureSample 1
    }

    # Scenario: the unsupported FF85 retained API branch encounters persistent raw stream Dispose failures.
    # Purpose: ensure an early writer Dispose and its real outer cleanup retry cannot leave cleanup-failed evidence classified as unsupported.
    It 'UnitT86_downgrades_ff85_unsupported_result_after_persistent_dispose_failure' {
        # Given: the actual FF85 runner lacks the retained receipt API and a real create-new stream that faults only on every Dispose.
        # When: the production sampler reaches its unsupported-branch writer cleanup and outer fallback cleanup.
        # Then: the backing file closes, the actual Dispose failure and closed-writer fallback Flush are evidenced, and the result is incomplete with the first error retained.
        Invoke-SourceResidentUnsupportedDisposeFaultCaseForTest
    }
}
