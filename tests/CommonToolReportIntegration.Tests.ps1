# SPDX-FileCopyrightText: 2026 SyuanTsai
# SPDX-License-Identifier: Apache-2.0
Describe 'Code child uses central package tool report rules' {
    BeforeAll {
        $script:priorEnv = @{}
        foreach ($name in @('STANDARD_VALIDATION_ACTIVE_SKILLS', 'STANDARD_VALIDATION_SKILLS_ROOT', 'STANDARD_VALIDATION_SKILL_ID', 'STANDARD_VALIDATION_CANDIDATE_ID', 'STANDARD_VALIDATION_CANDIDATE_ROOT', 'STANDARD_VALIDATION_SKILL_INVENTORY_SHA256', 'SYP154_TEST_TOOL_REPORT', 'SYP154_CANDIDATE_AUTHORITY_ROOT')) {
            $script:priorEnv[$name] = [Environment]::GetEnvironmentVariable($name)
        }
        $script:testRoot = $null

        function Assert-IntegrationAuthorityRawFileIdentity {
            param(
                [Parameter(Mandatory = $true)][string] $AuthorityRoot,
                [Parameter(Mandatory = $true)] $Entry
            )

            $relativePath = [string]$Entry.path
            $segments = $relativePath.Split('/')
            if ([string]::IsNullOrWhiteSpace($relativePath) -or $relativePath.Contains('\') -or
                [IO.Path]::IsPathRooted($relativePath) -or $segments -contains '' -or
                $segments -contains '.' -or $segments -contains '..' -or
                [string]$Entry.sha256 -cnotmatch '^[0-9a-f]{64}$') {
                throw 'The active authority config contains an unsafe fixture file record.'
            }
            $fullRoot = [IO.Path]::GetFullPath($AuthorityRoot).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
            $rootPrefix = $fullRoot + [IO.Path]::DirectorySeparatorChar
            $comparison = if ($IsWindows) { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal }
            $path = [IO.Path]::GetFullPath((Join-Path $fullRoot $relativePath))
            if (-not $path.StartsWith($rootPrefix, $comparison) -or -not (Test-Path -LiteralPath $path -PathType Leaf)) {
                throw "Authority fixture file is missing or outside the checkout: $relativePath"
            }

            $content = [IO.File]::ReadAllBytes($path)
            $sha256 = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($content)).ToLowerInvariant()
            if ($sha256 -cne [string]$Entry.sha256) {
                throw "Authority fixture raw SHA-256 differs from the approved config: $relativePath"
            }

            return $path
        }

        function Assert-IntegrationAuthorityFileIdentity {
            param(
                [Parameter(Mandatory = $true)][string] $AuthorityRoot,
                [Parameter(Mandatory = $true)] $Entry,
                [Parameter(Mandatory = $true)] $GitEntry
            )
            $relativePath = [string]$Entry.path
            if ([string]$GitEntry.path -cne $relativePath -or [string]$GitEntry.mode -cne '100644' -or
                [string]$GitEntry.objectId -cnotmatch '^[0-9a-f]{40}$') {
                throw "The authority Git tree has an unexpected path or mode: $relativePath"
            }
            $path = Assert-IntegrationAuthorityRawFileIdentity -AuthorityRoot $AuthorityRoot -Entry $Entry
            $content = [IO.File]::ReadAllBytes($path)

            $header = [Text.Encoding]::ASCII.GetBytes("blob $($content.Length)`0")
            $gitContent = [byte[]]::new($header.Length + $content.Length)
            [Array]::Copy($header, 0, $gitContent, 0, $header.Length)
            [Array]::Copy($content, 0, $gitContent, $header.Length, $content.Length)
            $sha1 = [Convert]::ToHexString([Security.Cryptography.SHA1]::HashData($gitContent)).ToLowerInvariant()
            if ($sha1 -cne [string]$GitEntry.objectId) {
                throw "Authority fixture bytes differ from the exact HEAD Git blob: $relativePath"
            }
        }

        function Get-IntegrationProcessArgumentValue {
            param(
                [Parameter(Mandatory = $true)][string[]] $ProcessArguments,
                [Parameter(Mandatory = $true)][string] $Name
            )
            $found = [Collections.Generic.List[string]]::new()
            for ($index = 0; $index -lt $ProcessArguments.Count; $index++) {
                if ([string]$ProcessArguments[$index] -ceq "-$Name") {
                    if ($index + 1 -ge $ProcessArguments.Count) { throw "Process is missing the value for -$Name." }
                    $found.Add([string]$ProcessArguments[$index + 1])
                }
            }
            if ($found.Count -ne 1 -or [string]::IsNullOrWhiteSpace($found[0])) { throw "The Pester child requires exactly one process CLI -$Name binding." }
            return $found[0]
        }

        function Assert-IntegrationApprovedOrigin {
            param(
                [Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]] $OriginUrls,
                [Parameter(Mandatory = $true)][string] $ExpectedRepository
            )

            if ($OriginUrls.Count -ne 1 -or [string]::IsNullOrWhiteSpace($OriginUrls[0])) {
                throw 'The authority fixture must have exactly one origin URL.'
            }
            $normalizedOrigin = ([string]$OriginUrls[0]).TrimEnd('/') -replace '\.git$', ''
            $normalizedExpectedRepository = $ExpectedRepository.TrimEnd('/') -replace '\.git$', ''
            if ($normalizedOrigin -cne $normalizedExpectedRepository) {
                throw 'The authority fixture has an origin outside the exact approved repository.'
            }
        }

        function Invoke-IntegrationChildProcess {
            param([Parameter(Mandatory = $true)][string[]] $Arguments)

            Push-Location -LiteralPath $script:testRoot
            try {
                $output = @(& $script:pwshPath @Arguments 2>&1)
                $exitCode = $LASTEXITCODE
                return [pscustomobject]@{ output = $output; exitCode = [int]$exitCode }
            }
            finally { Pop-Location }
        }

        $validationPath = if ([string]::IsNullOrWhiteSpace($env:SYP154_TEST_VALIDATE_SOURCE)) { Join-Path (Split-Path -Parent $PSScriptRoot) 'scripts/Validate.ps1' } else { [string]$env:SYP154_TEST_VALIDATE_SOURCE }
        $script:validationPath = $validationPath
        $script:validationSource = Get-Content -LiteralPath $validationPath -Raw
        $script:childMatch = [regex]::Match($script:validationSource, '(?ms)^\$childRunnerText = @''\r?\n(?<body>.*?)^''@')
        if (-not $script:childMatch.Success) { throw 'Code child runner source was not found.' }
        $script:testRoot = Join-Path ([IO.Path]::GetTempPath()) ('syp154-report-' + [guid]::NewGuid().ToString('N'))
        $script:skillRoot = Join-Path $script:testRoot 'candidate/skills/demo'
        [void](New-Item -ItemType Directory -Path $script:skillRoot -Force)
        [IO.File]::WriteAllText((Join-Path $script:skillRoot 'SKILL.md'), '# Demo')
        $script:childPath = Join-Path $script:testRoot 'child.ps1'
        [IO.File]::WriteAllText($script:childPath, $script:childMatch.Groups['body'].Value)
        $script:fakeToolPath = Join-Path $script:testRoot 'skill-validator.ps1'
        [IO.File]::WriteAllText($script:fakeToolPath, 'Get-Content -LiteralPath $env:SYP154_TEST_TOOL_REPORT -Raw; $global:LASTEXITCODE = 0')
        $repositoryRoot = Split-Path -Parent $PSScriptRoot
        $script:pwshPath = (Get-Command pwsh -CommandType Application | Select-Object -First 1).Source
        $authority = (Get-Content -LiteralPath (Join-Path $repositoryRoot 'config/standard-v1.json') -Raw | ConvertFrom-Json -Depth 20).authority
        $expectedRepository = 'https://github.com/SyuanTsai/SyuanTsai-AI-Instructions.git'
        $expectedCommit = '8aabd22694a05771f98639f6d726cc9a620eb94b'
        $expectedArchiveSha256 = 'd92df1a8f0aa342970dc9c66a77b6211955b4708de12119cb7f9a360fd265311'
        if ($authority.repository -cne $expectedRepository -or $authority.commit -cne $expectedCommit -or
            $authority.archiveUrl -cne "https://codeload.github.com/SyuanTsai/SyuanTsai-AI-Instructions/zip/$expectedCommit" -or
            $authority.archiveSha256 -cne $expectedArchiveSha256 -or @($authority.files).Count -ne 26) {
            throw 'The Pester child fixture is only valid while the active authority config remains the exact 8a tuple.'
        }

        if (-not [string]::IsNullOrWhiteSpace($env:SYP154_CANDIDATE_AUTHORITY_ROOT)) {
            # Keep the SourceValidation path's real Git checkout admission strict.
            # The archive fallback below is only for the protected legacy driver.
            $script:authorityFixtureMode = 'verified-git-checkout'
            $moduleRoot = [IO.Path]::GetFullPath([string]$env:SYP154_CANDIDATE_AUTHORITY_ROOT)
            $gitRoot = ((& git -C $moduleRoot rev-parse --show-toplevel 2>$null) -join "`n").Trim()
            if ($LASTEXITCODE -ne 0 -or [IO.Path]::GetFullPath($gitRoot) -cne $moduleRoot) {
                throw 'The Pester child authority fixture is not the root of a Git checkout.'
            }
            $fixtureCommit = ((& git -C $moduleRoot rev-parse HEAD 2>$null) -join "`n").Trim()
            if ($LASTEXITCODE -ne 0 -or $fixtureCommit -cne $expectedCommit) { throw 'The Pester child authority fixture has the wrong Git HEAD.' }
            $fixtureOrigins = @(& git -C $moduleRoot remote get-url --all origin 2>$null)
            if ($LASTEXITCODE -ne 0) { throw 'The Pester child authority fixture origin could not be read.' }
            Assert-IntegrationApprovedOrigin -OriginUrls ([string[]]$fixtureOrigins) -ExpectedRepository $expectedRepository
            $fixtureStatus = @(& git -C $moduleRoot status --porcelain=v1 --untracked-files=all 2>$null)
            if ($LASTEXITCODE -ne 0 -or $fixtureStatus.Count -ne 0) { throw 'The Pester child authority fixture is not clean.' }

            $treeRecords = @(& git -C $moduleRoot ls-tree -r --full-tree --format='%(objectmode)%x09%(objectname)%x09%(path)' $expectedCommit 2>$null)
            if ($LASTEXITCODE -ne 0) { throw 'Could not read the exact authority HEAD Git tree.' }
            $script:authorityGitEntries = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::Ordinal)
            foreach ($record in $treeRecords) {
                $firstSeparator = $record.IndexOf([char]9)
                $secondSeparator = if ($firstSeparator -ge 0) { $record.IndexOf([char]9, $firstSeparator + 1) } else { -1 }
                if ($firstSeparator -le 0 -or $secondSeparator -le $firstSeparator + 1 -or $secondSeparator -ge $record.Length - 1) {
                    throw 'The authority HEAD Git tree contains a malformed entry.'
                }
                $path = $record.Substring($secondSeparator + 1)
                if (-not $script:authorityGitEntries.TryAdd($path, [pscustomobject]@{
                    mode = $record.Substring(0, $firstSeparator)
                    objectId = $record.Substring($firstSeparator + 1, $secondSeparator - $firstSeparator - 1)
                    path = $path
                })) {
                    throw "The authority HEAD Git tree repeats a path: $path"
                }
            }
            foreach ($entry in @($authority.files)) {
                $relativePath = [string]$entry.path
                if (-not $script:authorityGitEntries.ContainsKey($relativePath)) { throw "Authority HEAD Git tree omits an approved path: $relativePath" }
                Assert-IntegrationAuthorityFileIdentity -AuthorityRoot $moduleRoot -Entry $entry -GitEntry $script:authorityGitEntries[$relativePath]
            }
        }
        else {
            $script:authorityFixtureMode = 'verified-driver-archive'
            $processArguments = [Environment]::GetCommandLineArgs()
            $processToolchainPath = Get-IntegrationProcessArgumentValue -ProcessArguments $processArguments -Name 'ToolchainPath'
            $processToolchainSha = Get-IntegrationProcessArgumentValue -ProcessArguments $processArguments -Name 'ToolchainSha256'
            $resolverPath = Join-Path $PSScriptRoot 'ResolveLegacyAuthorityArchiveFixture.ps1'
            $archiveOutput = @(& $script:pwshPath -NoLogo -NoProfile -NonInteractive -File $resolverPath `
                -RepositoryRoot $repositoryRoot -ToolchainPath $processToolchainPath -ToolchainSha256 $processToolchainSha 2>&1)
            $archiveExitCode = $LASTEXITCODE
            if ($archiveExitCode -ne 0) { throw "Legacy archive fixture admission failed: $($archiveOutput -join ' ')" }
            $archiveReceipt = ($archiveOutput -join "`n") | ConvertFrom-Json -Depth 20 -ErrorAction Stop
            if ([string]$archiveReceipt.fixtureMode -cne 'verified-driver-archive' -or [string]$archiveReceipt.authorityRevision -cne $expectedCommit -or
                [int]$archiveReceipt.authorityFileCount -ne 26 -or [int]$archiveReceipt.authorityExtraFileCount -lt 1) {
                throw 'Legacy archive fixture receipt does not bind the selected 8a closure inside a full archive extraction.'
            }
            $moduleRoot = [IO.Path]::GetFullPath([string]$archiveReceipt.authorityRoot)
            $script:authorityGitEntries = $null
        }
        $script:moduleRoot = [IO.Path]::GetFullPath($moduleRoot)
        $script:runnerPath = Join-Path $script:moduleRoot 'scripts/Invoke-StandardValidation.ps1'
        $env:STANDARD_VALIDATION_ACTIVE_SKILLS = 'demo'
        $env:STANDARD_VALIDATION_SKILLS_ROOT = Join-Path $script:testRoot 'candidate/skills'
        $env:STANDARD_VALIDATION_SKILL_ID = 'demo'
        $env:STANDARD_VALIDATION_CANDIDATE_ID = ('a' * 64)
        $env:STANDARD_VALIDATION_CANDIDATE_ROOT = Join-Path $script:testRoot 'candidate'
        $script:manifestPath=Join-Path $script:testRoot 'candidate-manifest.json'
        $manifest=[ordered]@{schemaVersion=3;candidateCommit=('c'*40);entries=@([ordered]@{path='skills/demo/SKILL.md';mode='100644';sha256=(Get-FileHash -LiteralPath (Join-Path $script:skillRoot 'SKILL.md') -Algorithm SHA256).Hash.ToLowerInvariant()})}
        [IO.File]::WriteAllText($script:manifestPath,($manifest|ConvertTo-Json -Depth 10 -Compress))
        $script:manifestHash=(Get-FileHash -LiteralPath $script:manifestPath -Algorithm SHA256).Hash.ToLowerInvariant()
        $env:STANDARD_VALIDATION_SKILL_INVENTORY_SHA256 = ('b' * 64)
        $toolchain = [ordered]@{
            centralRunnerPath = $script:runnerPath
            centralRunnerSha256 = if (Test-Path -LiteralPath $script:runnerPath -PathType Leaf) { (Get-FileHash -Algorithm SHA256 -LiteralPath $script:runnerPath).Hash.ToLowerInvariant() } else { '0' * 64 }
            skillValidatorPath = $script:fakeToolPath
            skillValidatorSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $script:fakeToolPath).Hash.ToLowerInvariant()
        }
        $script:toolchainPath = Join-Path $script:testRoot 'toolchain.json'
        [IO.File]::WriteAllText($script:toolchainPath, ($toolchain | ConvertTo-Json -Compress))
        $script:toolchainHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $script:toolchainPath).Hash.ToLowerInvariant()
    }

    # Scenario: Git checkout helpers omit a trailing .git while another origin or multiple fetch URLs are untrusted.
    # Purpose: admit the approved repository's supported URL spelling without allowing a repository alias.
    It 'UnitT05_accepts_the_exact_origin_with_or_without_git_suffix_and_rejects_other_origins' {
        $expected = 'https://github.com/SyuanTsai/SyuanTsai-AI-Instructions.git'
        { Assert-IntegrationApprovedOrigin -OriginUrls @($expected) -ExpectedRepository $expected } | Should -Not -Throw
        { Assert-IntegrationApprovedOrigin -OriginUrls @('https://github.com/SyuanTsai/SyuanTsai-AI-Instructions') -ExpectedRepository $expected } | Should -Not -Throw
        { Assert-IntegrationApprovedOrigin -OriginUrls @('https://github.com/another-owner/SyuanTsai-AI-Instructions.git') -ExpectedRepository $expected } | Should -Throw '*exact approved repository*'
        { Assert-IntegrationApprovedOrigin -OriginUrls @($expected, $expected) -ExpectedRepository $expected } | Should -Throw '*exactly one origin*'
    }

    BeforeEach {
        [IO.File]::WriteAllText($script:fakeToolPath, 'Get-Content -LiteralPath $env:SYP154_TEST_TOOL_REPORT -Raw; $global:LASTEXITCODE = 0')
        $toolchain = [ordered]@{
            centralRunnerPath = $script:runnerPath
            centralRunnerSha256 = (Get-FileHash -LiteralPath $script:runnerPath -Algorithm SHA256).Hash.ToLowerInvariant()
            skillValidatorPath = $script:fakeToolPath
            skillValidatorSha256 = (Get-FileHash -LiteralPath $script:fakeToolPath -Algorithm SHA256).Hash.ToLowerInvariant()
        }
        [IO.File]::WriteAllText($script:toolchainPath, ($toolchain | ConvertTo-Json -Compress))
        $script:toolchainHash = (Get-FileHash -LiteralPath $script:toolchainPath -Algorithm SHA256).Hash.ToLowerInvariant()
    }

    AfterAll {
        if ($null -ne $script:priorEnv) {
            foreach ($name in $script:priorEnv.Keys) { [Environment]::SetEnvironmentVariable($name, $script:priorEnv[$name]) }
        }
        if (-not [string]::IsNullOrWhiteSpace([string]$script:testRoot) -and (Test-Path -LiteralPath $script:testRoot -PathType Container)) {
            $expectedParent = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
            $actualParent = [IO.Path]::GetFullPath((Split-Path -Parent $script:testRoot)).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
            if ($actualParent -cne $expectedParent -or (Split-Path -Leaf $script:testRoot) -cnotmatch '^syp154-report-[0-9a-f]{32}$') {
                throw 'Integration test cleanup root is not the allocated temporary directory.'
            }
            Remove-Item -LiteralPath $script:testRoot -Recurse -Force
        }
    }

    # Scenario: a package tool emits a success report with a string error count.
    # Purpose: the Code child must reject malformed counts through the shared authority rule.
    It 'InterT10_rejects_string_error_count_from_the_real_Code_child' {
        $rawBefore = @(Get-ChildItem -LiteralPath $script:testRoot -File -Filter 'native-raw-*' | ForEach-Object { $_.FullName })
        $reportPath = Join-Path $script:testRoot 'report.json'
        [IO.File]::WriteAllText($reportPath, (@{ skill_dir = $script:skillRoot; passed = $true; errors = '0'; warnings = 0; results = @(@{ level = 'pass'; file = 'SKILL.md'; category = 'structure'; message = 'clean' }) } | ConvertTo-Json -Depth 10 -Compress))
        $env:SYP154_TEST_TOOL_REPORT = $reportPath
        $child = Invoke-IntegrationChildProcess -Arguments @('-NoProfile', '-NonInteractive', '-File', $script:childPath, '-Mode', 'skill-validator', '-ToolchainPath', $script:toolchainPath, '-ToolchainSha256', $script:toolchainHash, '-SourceRevision', ('c' * 40), '-GitEntryModeManifestPath', $script:manifestPath, '-GitEntryModeManifestSha256', $script:manifestHash)
        $child.exitCode | Should -Be 1
        ($child.output -join "`n") | Should -Match 'typed nonnegative integer|counters must be JSON integers'
        $newRaw = @(Get-ChildItem -LiteralPath $script:testRoot -File -Filter 'native-raw-*' | Where-Object { $rawBefore -cnotcontains $_.FullName })
        @($newRaw | Where-Object { $_.Name -match '\.stdout\.txt$' }).Count | Should -Be 1
        @($newRaw | Where-Object { $_.Name -match '\.stderr\.txt$' }).Count | Should -Be 1
        $rawStdout = @($newRaw | Where-Object { $_.Name -match '\.stdout\.txt$' })
        $rawStderr = @($newRaw | Where-Object { $_.Name -match '\.stderr\.txt$' })
        $rawStdout.Count | Should -Be 1
        $rawStderr.Count | Should -Be 1
        $rawStdout[0].Length | Should -BeGreaterThan 0
        Get-Content -LiteralPath $rawStdout[0].FullName -Raw | Should -Match '"errors":"0"'
        Test-Path -LiteralPath $rawStderr[0].FullName -PathType Leaf | Should -BeTrue
    }

    # Scenario: the real active authority runner is loaded while the caller holds nonempty values that use the runner's parameter names.
    # Purpose: retain the central runner's full module-scoped function closure and script state without overwriting setup or validation locals.
    It 'InterT15_preserves_caller_bindings_when_importing_the_real_authority_runner' {
        $tokens = $null
        $parseErrors = $null
        $sourceAst = [Management.Automation.Language.Parser]::ParseInput($script:validationSource, [ref]$tokens, [ref]$parseErrors)
        $parseErrors.Count | Should -Be 0
        $factoryNodes = @($sourceAst.FindAll({
            param($node)
            $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq 'New-CodeSourceStandardValidationModule'
        }, $true))
        $dispatcherNodes = @($sourceAst.FindAll({
            param($node)
            $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq 'Invoke-CodeSourceStandardValidationModule'
        }, $true))
        $setupNodes = @($sourceAst.FindAll({
            param($node)
            $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq 'Invoke-CodeSourceToolSetup'
        }, $true))
        $validationNodes = @($sourceAst.FindAll({
            param($node)
            $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq 'Invoke-CodeSourceValidation'
        }, $true))
        $factoryNodes.Count | Should -Be 1
        $dispatcherNodes.Count | Should -Be 1
        $setupNodes.Count | Should -Be 1
        $validationNodes.Count | Should -Be 1
        $setupSource = $setupNodes[0].Extent.Text
        $validationSource = $validationNodes[0].Extent.Text
        $setupSource | Should -Match 'New-CodeSourceStandardValidationModule'
        $setupSource | Should -Match 'Invoke-CodeSourceStandardValidationModule'
        $setupSource | Should -Not -Match '(?m)^\s*\.\s+\$runner\s+-DefineFunctionsOnly'
        $validationSource | Should -Match 'New-CodeSourceStandardValidationModule'
        $validationSource | Should -Match 'Invoke-CodeSourceStandardValidationModule'
        $validationSource | Should -Not -Match '(?m)^\s*\.\s+\$centralRunner\s+-DefineFunctionsOnly'
        Invoke-Expression $factoryNodes[0].Extent.Text
        Invoke-Expression $dispatcherNodes[0].Extent.Text

        $runId = 'f' * 32
        $TimeoutSeconds = 10800
        $TrustedToolRoot = Split-Path -Parent $script:pwshPath
        $CancellationPath = Join-Path $script:testRoot 'central-runner-cancel.request'
        $OutputPath = Join-Path $script:testRoot 'central-runner-report.json'
        $EventName = 'pull_request'
        $CandidateRevision = 'd' * 40
        $BaseRevision = 'e' * 40
        $activeAuthority = (Get-Content -LiteralPath (Join-Path (Split-Path -Parent $PSScriptRoot) 'config/standard-v1.json') -Raw | ConvertFrom-Json -Depth 20).authority
        $AuthorityRevision = [string]$activeAuthority.commit
        $expectedSourceValidation = $AuthorityRevision -ceq 'ff85d5f80fe795b96354e753074b5ce59ad04ecd'
        $AuthorityRevision | Should -BeIn @('8aabd22694a05771f98639f6d726cc9a620eb94b', 'ff85d5f80fe795b96354e753074b5ce59ad04ecd')
        $SourceRepository = 'https://github.com/SyuanTsai/Skill-Code-Collaboration.git'
        $expectedCallerBindings = [ordered]@{
            runId = $runId
            TimeoutSeconds = $TimeoutSeconds
            TrustedToolRoot = $TrustedToolRoot
            CancellationPath = $CancellationPath
            OutputPath = $OutputPath
            EventName = $EventName
            CandidateRevision = $CandidateRevision
            BaseRevision = $BaseRevision
            AuthorityRevision = $AuthorityRevision
            SourceRepository = $SourceRepository
        }
        $runnerContext = [ordered]@{
            CandidateRoot = Join-Path $script:testRoot 'candidate'
            AdapterPath = $script:toolchainPath
            ArtifactsRoot = $script:testRoot
            OutputPath = $expectedCallerBindings.OutputPath
            SourceRepository = $expectedCallerBindings.SourceRepository
            SourceRevision = $expectedCallerBindings.CandidateRevision
            BaseRevision = $expectedCallerBindings.BaseRevision
            EventName = $expectedCallerBindings.EventName
            RunId = $expectedCallerBindings.runId
            AuthorityRevision = $expectedCallerBindings.AuthorityRevision
            TimeoutSeconds = $expectedCallerBindings.TimeoutSeconds
            CancellationPath = $expectedCallerBindings.CancellationPath
            TrustedToolRoot = $expectedCallerBindings.TrustedToolRoot
        }
        $runnerToolchain = Get-Content -LiteralPath $script:toolchainPath -Raw | ConvertFrom-Json -Depth 10
        $module = $null
        try {
            $module = New-CodeSourceStandardValidationModule -RunnerPath $script:runnerPath `
                -RunnerSha256 ([string]$runnerToolchain.centralRunnerSha256) -RunnerArguments $runnerContext `
                -SourceValidation:$expectedSourceValidation

            Get-Command Invoke-StandardValidationProcess -CommandType Function -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
            $moduleState = & $module {
                $processFunction = Get-Command Invoke-StandardValidationProcess -CommandType Function -ErrorAction Stop
                $runnerParamTokens = $null
                $runnerParseErrors = $null
                $runnerPathInModule = Join-Path ([string]$script:StandardValidationRepositoryRoot) 'scripts/Invoke-StandardValidation.ps1'
                $runnerAst = [Management.Automation.Language.Parser]::ParseFile($runnerPathInModule, [ref]$runnerParamTokens, [ref]$runnerParseErrors)
                if ($runnerParseErrors.Count -ne 0) { throw 'The selected authority runner did not parse.' }
                $runnerSupportsSourceValidation = @($runnerAst.ParamBlock.Parameters | Where-Object {
                    ([string]$_.Name.VariablePath.UserPath) -ceq 'SourceValidation'
                }).Count -eq 1
                $sourceValidationValue = Get-Variable -Name SourceValidation -ErrorAction SilentlyContinue
                [pscustomobject][ordered]@{
                    processFunctionModule = [string]$processFunction.ModuleName
                    centralRepositoryRoot = [string]$script:StandardValidationRepositoryRoot
                    runId = [string]$RunId
                    timeoutSeconds = [int]$TimeoutSeconds
                    trustedToolRoot = [string]$TrustedToolRoot
                    cancellationPath = [string]$CancellationPath
                    outputPath = [string]$OutputPath
                    eventName = [string]$EventName
                    sourceRevision = [string]$SourceRevision
                    baseRevision = [string]$BaseRevision
                    authorityRevision = [string]$AuthorityRevision
                    processSupportsCoreLifecycleOnly = $processFunction.Parameters.ContainsKey('CoreLifecycleOnly')
                    runnerSupportsSourceValidation = [bool]$runnerSupportsSourceValidation
                    sourceValidationEnabled = ($null -ne $sourceValidationValue -and [bool]$sourceValidationValue.Value)
                }
            }

            $moduleState.processFunctionModule | Should -Be $module.Name
            $moduleState.centralRepositoryRoot | Should -Be $script:moduleRoot
            $moduleState.runId | Should -Be $expectedCallerBindings.runId
            $moduleState.timeoutSeconds | Should -Be $expectedCallerBindings.TimeoutSeconds
            $moduleState.trustedToolRoot | Should -Be $expectedCallerBindings.TrustedToolRoot
            $moduleState.cancellationPath | Should -Be $expectedCallerBindings.CancellationPath
            $moduleState.outputPath | Should -Be $expectedCallerBindings.OutputPath
            $moduleState.eventName | Should -Be $expectedCallerBindings.EventName
            $moduleState.sourceRevision | Should -Be $expectedCallerBindings.CandidateRevision
            $moduleState.baseRevision | Should -Be $expectedCallerBindings.BaseRevision
            $moduleState.authorityRevision | Should -Be $expectedCallerBindings.AuthorityRevision
            $moduleState.runnerSupportsSourceValidation | Should -Be $expectedSourceValidation
            $moduleState.sourceValidationEnabled | Should -Be $expectedSourceValidation
            $moduleState.processSupportsCoreLifecycleOnly | Should -Be $expectedSourceValidation

            $probePath = Join-Path $script:testRoot 'central-runner-import-probe.ps1'
            [IO.File]::WriteAllText($probePath, "[Console]::Out.WriteLine('central-runner-import-ok')", [Text.UTF8Encoding]::new($false))
            $processArguments = @{
                Command = $script:pwshPath
                Arguments = [string[]]@('-NoLogo', '-NoProfile', '-NonInteractive', '-File', $probePath)
                WorkingDirectory = $script:testRoot
                Environment = @{}
                TimeoutSeconds = 30
                CancellationPath = $CancellationPath
            }
            if ($expectedSourceValidation) { $processArguments.CoreLifecycleOnly = $true }
            $processResult = Invoke-CodeSourceStandardValidationModule -Module $module `
                -FunctionName 'Invoke-StandardValidationProcess' -Arguments $processArguments
            $processResult.status | Should -Be 'passed' -Because $processResult.stderr
            $processResult.exitCode | Should -Be 0
            $processResult.cleanedUp | Should -BeTrue
            $processResult.stdout | Should -Match 'central-runner-import-ok'

            foreach ($name in $expectedCallerBindings.Keys) {
                (Get-Variable -Name $name -ValueOnly) | Should -Be $expectedCallerBindings[$name]
            }
        }
        finally {
            if ($null -ne $module) { Remove-Module -ModuleInfo $module -Force -ErrorAction Stop }
        }

        Get-Module -Name $module.Name | Should -BeNullOrEmpty
        Get-Command Invoke-StandardValidationProcess -CommandType Function -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
    }

    # Scenario: setup passes its owned root through the same isolated 8a runner used by the production sender.
    # Purpose: exercise actual sender wiring, prove the namespaced value reaches a child, and keep the old key rejected.
    It 'InterT17_binds_the_production_setup_sender_to_the_namespaced_owned_root' {
        $tokens = $null
        $parseErrors = $null
        $sourceAst = [Management.Automation.Language.Parser]::ParseInput($script:validationSource, [ref]$tokens, [ref]$parseErrors)
        $parseErrors.Count | Should -Be 0
        $setupFunctions = @($sourceAst.FindAll({
            param($node)
            $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq 'Invoke-CodeSourceToolSetup'
        }, $true))
        $factoryNodes = @($sourceAst.FindAll({
            param($node)
            $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq 'New-CodeSourceStandardValidationModule'
        }, $true))
        $dispatcherNodes = @($sourceAst.FindAll({
            param($node)
            $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq 'Invoke-CodeSourceStandardValidationModule'
        }, $true))
        $setupFunctions.Count | Should -Be 1
        $factoryNodes.Count | Should -Be 1
        $dispatcherNodes.Count | Should -Be 1
        $setupBody = $setupFunctions[0].Body
        $assignmentNodes = @($setupBody.FindAll({ param($node) $node -is [Management.Automation.Language.AssignmentStatementAst] }, $true))
        $senderAssignments = @($assignmentNodes | Where-Object {
            $_.Left.Extent.Text -ceq '$setupEnvironment' -and
            $_.Right.Extent.Text -match '(?s)^\s*New-CodeSourcePesterSetupEnvironment\s+-OwnedRoot\s+\$ownedRoot\s*$'
        })
        $senderAssignments.Count | Should -Be 1

        $argumentAssignments = @($assignmentNodes | Where-Object {
            $_.Left.Extent.Text -ceq '$pesterSetupArguments'
        })
        $argumentAssignments.Count | Should -Be 1
        $argumentTables = @($argumentAssignments[0].Right.FindAll({
            param($node)
            $node -is [Management.Automation.Language.HashtableAst]
        }, $true))
        if ($argumentAssignments[0].Right -is [Management.Automation.Language.HashtableAst]) {
            $argumentTables = @($argumentAssignments[0].Right) + $argumentTables
        }
        $argumentTables.Count | Should -BeGreaterThan 0
        $environmentPairs = @($argumentTables[0].KeyValuePairs | Where-Object { $_.Item1.Extent.Text -ceq 'Environment' })
        $environmentPairs.Count | Should -Be 1
        $environmentPairs[0].Item2.Extent.Text | Should -BeExactly '$setupEnvironment'
        $setupDispatches = @($setupBody.FindAll({
            param($node)
            $node -is [Management.Automation.Language.CommandAst] -and
            $node.GetCommandName() -ceq 'Invoke-CodeSourceStandardValidationModule' -and
            $node.Extent.Text -match '(?s)-Arguments\s+\$pesterSetupArguments(?:\s|$)'
        }, $true))
        $setupDispatches.Count | Should -Be 1

        Invoke-Expression $factoryNodes[0].Extent.Text
        Invoke-Expression $dispatcherNodes[0].Extent.Text
        $driverModulePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'scripts/StandardSourceDriver.psm1'
        $driverModule = Import-Module -Name $driverModulePath -Force -PassThru -ErrorAction Stop
        $ownedRoot = [IO.Path]::GetFullPath((Join-Path $script:testRoot ("source-tools-" + [guid]::NewGuid().ToString('N'))))
        [void](New-Item -ItemType Directory -Path $ownedRoot -Force)
        $setupEnvironment = New-CodeSourcePesterSetupEnvironment -OwnedRoot $ownedRoot
        @($setupEnvironment.Keys).Count | Should -Be 1
        $setupEnvironment.Contains('STANDARD_VALIDATION_RUN_OWNED_ROOT') | Should -BeTrue
        [string]$setupEnvironment['STANDARD_VALIDATION_RUN_OWNED_ROOT'] | Should -BeExactly $ownedRoot

        $activeAuthority = (Get-Content -LiteralPath (Join-Path (Split-Path -Parent $PSScriptRoot) 'config/standard-v1.json') -Raw | ConvertFrom-Json -Depth 20).authority
        $runnerToolchain = Get-Content -LiteralPath $script:toolchainPath -Raw | ConvertFrom-Json -Depth 10
        $runnerContext = [ordered]@{
            CandidateRoot = Join-Path $script:testRoot 'candidate'
            AdapterPath = $script:toolchainPath
            ArtifactsRoot = $script:testRoot
            OutputPath = Join-Path $script:testRoot 'a029-namespaced-runner-report.json'
            SourceRepository = 'https://github.com/SyuanTsai/Skill-Code-Collaboration.git'
            SourceRevision = 'd' * 40
            BaseRevision = 'e' * 40
            EventName = 'pull_request'
            RunId = [guid]::NewGuid().ToString('N')
            AuthorityRevision = [string]$activeAuthority.commit
            TimeoutSeconds = 30
            CancellationPath = Join-Path $script:testRoot 'a029-namespaced-cancel.request'
            TrustedToolRoot = Split-Path -Parent $script:pwshPath
        }
        $module = $null
        try {
            $module = New-CodeSourceStandardValidationModule -RunnerPath $script:runnerPath `
                -RunnerSha256 ([string]$runnerToolchain.centralRunnerSha256) -RunnerArguments $runnerContext
            $probePath = Join-Path $script:testRoot 'a029-owned-root-probe.ps1'
            $probeSource = @'
param([string]$MarkerPath)
$root = [Environment]::GetEnvironmentVariable('STANDARD_VALIDATION_RUN_OWNED_ROOT')
[IO.File]::WriteAllText($MarkerPath, $root)
[Console]::Out.WriteLine($root)
'@
            [IO.File]::WriteAllText($probePath, $probeSource, [Text.UTF8Encoding]::new($false))
            $markerPath = Join-Path $script:testRoot 'a029-owned-root-probe.marker'
            $processArguments = @{
                Command = $script:pwshPath
                Arguments = [string[]]@('-NoLogo', '-NoProfile', '-NonInteractive', '-File', $probePath, $markerPath)
                WorkingDirectory = $script:testRoot
                Environment = $setupEnvironment
                TimeoutSeconds = 30
                CancellationPath = $runnerContext.CancellationPath
            }
            $positive = Invoke-CodeSourceStandardValidationModule -Module $module `
                -FunctionName 'Invoke-StandardValidationProcess' -Arguments $processArguments
            $positive.status | Should -Be 'passed' -Because $positive.stderr
            $positive.exitCode | Should -Be 0
            $positive.cleanedUp | Should -BeTrue
            $positive.stdout.Trim() | Should -BeExactly $ownedRoot
            [IO.File]::ReadAllText($markerPath) | Should -BeExactly $ownedRoot

            $legacyMarkerPath = Join-Path $script:testRoot 'a029-legacy-root-probe.marker'
            $legacyArguments = $processArguments.Clone()
            $legacyArguments.Arguments = [string[]]@('-NoLogo', '-NoProfile', '-NonInteractive', '-File', $probePath, $legacyMarkerPath)
            $legacyArguments.Environment = @{ RUN_OWNED_ROOT = $ownedRoot }
            $legacyException = $null
            try {
                $null = Invoke-CodeSourceStandardValidationModule -Module $module `
                    -FunctionName 'Invoke-StandardValidationProcess' -Arguments $legacyArguments
            }
            catch { $legacyException = [string]$_.Exception.Message }
            $legacyException | Should -Match "Validation child environment key 'RUN_OWNED_ROOT' is outside the runner namespace"
            Test-Path -LiteralPath $legacyMarkerPath -PathType Leaf | Should -BeFalse
        }
        finally {
            if ($null -ne $module) { Remove-Module -ModuleInfo $module -Force -ErrorAction Stop }
            if ($null -ne $driverModule) { Remove-Module -ModuleInfo $driverModule -Force -ErrorAction Stop }
        }
        Get-Command Invoke-StandardValidationProcess -CommandType Function -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
    }

    # Scenario: the same candidate-bound tool returns typed zero counts.
    # Purpose: the shared report rule must allow the normal Code envelope path.
    It 'InterT20_accepts_typed_zero_counts_through_the_real_Code_child' {
        $reportPath = Join-Path $script:testRoot 'report.json'
        [IO.File]::WriteAllText($reportPath, (@{ skill_dir = $script:skillRoot; passed = $true; errors = 0; warnings = 0; results = @(@{ level = 'pass'; file = 'SKILL.md'; category = 'structure'; message = 'clean' }) } | ConvertTo-Json -Depth 10 -Compress))
        $env:SYP154_TEST_TOOL_REPORT = $reportPath
        $child = Invoke-IntegrationChildProcess -Arguments @('-NoProfile', '-NonInteractive', '-File', $script:childPath, '-Mode', 'skill-validator', '-ToolchainPath', $script:toolchainPath, '-ToolchainSha256', $script:toolchainHash, '-SourceRevision', ('c' * 40), '-GitEntryModeManifestPath', $script:manifestPath, '-GitEntryModeManifestSha256', $script:manifestHash)
        $child.exitCode | Should -Be 0 -Because ($child.output -join "`n")
        $envelope = ($child.output -join "`n") | ConvertFrom-Json -Depth 10
        $envelope.decision | Should -Be 'PASS'
        $envelope.candidateIdentity | Should -Be ('a' * 64)
        $nativeReports = @($envelope.nativeReports)
        $nativeReports.Count | Should -Be 1
        $native = $nativeReports[0]
        foreach ($binding in @(
            @{ path = [string]$native.path; sha256 = [string]$native.sha256 },
            @{ path = [string]$native.stdoutPath; sha256 = [string]$native.stdoutSha256 },
            @{ path = [string]$native.stderrPath; sha256 = [string]$native.stderrSha256 }
        )) {
            $binding.path.StartsWith([IO.Path]::GetFullPath($script:testRoot) + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase) | Should -BeTrue
            (Get-FileHash -LiteralPath $binding.path -Algorithm SHA256).Hash.ToLowerInvariant() | Should -Be $binding.sha256
        }
        [int]$native.exitCode | Should -Be 0
        [string]$native.command | Should -Be $script:fakeToolPath
        [string]$native.commandSha256 | Should -Be (Get-FileHash -LiteralPath $script:fakeToolPath -Algorithm SHA256).Hash.ToLowerInvariant()
    }

    # Scenario: the package process writes both streams and then returns nonzero.
    # Purpose: preserve raw process evidence before the child rejects the exit status.
    It 'InterT22_preserves_native_streams_when_a_tool_exits_nonzero' {
        $rawBefore = @(Get-ChildItem -LiteralPath $script:testRoot -File -Filter 'native-raw-*' | ForEach-Object { $_.FullName })
        [IO.File]::WriteAllText($script:fakeToolPath, "Write-Output '{`"fixture`":true}'; Write-Error -ErrorAction Continue 'forced failure'; `$global:LASTEXITCODE = 7")
        $toolchain = Get-Content -LiteralPath $script:toolchainPath -Raw | ConvertFrom-Json
        $toolchain.skillValidatorSha256 = (Get-FileHash -LiteralPath $script:fakeToolPath -Algorithm SHA256).Hash.ToLowerInvariant()
        [IO.File]::WriteAllText($script:toolchainPath, ($toolchain | ConvertTo-Json -Compress))
        $script:toolchainHash = (Get-FileHash -LiteralPath $script:toolchainPath -Algorithm SHA256).Hash.ToLowerInvariant()
        $child = Invoke-IntegrationChildProcess -Arguments @('-NoProfile', '-NonInteractive', '-File', $script:childPath, '-Mode', 'skill-validator', '-ToolchainPath', $script:toolchainPath, '-ToolchainSha256', $script:toolchainHash, '-SourceRevision', ('c' * 40), '-GitEntryModeManifestPath', $script:manifestPath, '-GitEntryModeManifestSha256', $script:manifestHash)
        $child.exitCode | Should -Be 1
        ($child.output -join "`n") | Should -Match 'returned exit code 7'
        $newRaw = @(Get-ChildItem -LiteralPath $script:testRoot -File -Filter 'native-raw-*' | Where-Object { $rawBefore -cnotcontains $_.FullName })
        $stdout = @($newRaw | Where-Object { $_.Name -match '\.stdout\.txt$' })
        $stderr = @($newRaw | Where-Object { $_.Name -match '\.stderr\.txt$' })
        $stdout.Count | Should -Be 1
        $stderr.Count | Should -Be 1
        Get-Content -LiteralPath $stdout[0].FullName -Raw | Should -Match 'fixture'
        Get-Content -LiteralPath $stderr[0].FullName -Raw | Should -Match 'forced failure'
    }

    # Scenario: a clean report belongs to a neighboring candidate root.
    # Purpose: the actual candidate child must reject a report from another Skill.
    It 'InterT25_rejects_wrong_root_through_the_real_Code_child' {
        $wrongRoot = Join-Path $script:testRoot 'skills/neighbor'
        [void](New-Item -ItemType Directory -Path $wrongRoot -Force)
        $reportPath = Join-Path $script:testRoot 'report.json'
        [IO.File]::WriteAllText($reportPath, (@{ skill_dir = $wrongRoot; passed = $true; errors = 0; warnings = 0; results = @(@{ level = 'pass'; file = 'SKILL.md'; category = 'structure'; message = 'clean' }) } | ConvertTo-Json -Depth 10 -Compress))
        $env:SYP154_TEST_TOOL_REPORT = $reportPath
        $child = Invoke-IntegrationChildProcess -Arguments @('-NoProfile', '-NonInteractive', '-File', $script:childPath, '-Mode', 'skill-validator', '-ToolchainPath', $script:toolchainPath, '-ToolchainSha256', $script:toolchainHash, '-SourceRevision', ('c' * 40), '-GitEntryModeManifestPath', $script:manifestPath, '-GitEntryModeManifestSha256', $script:manifestHash)
        $child.exitCode | Should -Be 1
        ($child.output -join "`n") | Should -Match 'report root does not match candidate Skill|clean candidate-bound report'
    }

    # Scenario: a clean-root report omits required result category/message fields.
    # Purpose: retain Code's existing domain result checks while adopting shared rules.
    It 'InterT27_retains_Code_result_field_guards' {
        $reportPath=Join-Path $script:testRoot 'report.json'
        [IO.File]::WriteAllText($reportPath,(@{skill_dir=$script:skillRoot;passed=$true;errors=0;warnings=0;results=@(@{level='pass';file='SKILL.md'})}|ConvertTo-Json -Depth 10 -Compress))
        $env:SYP154_TEST_TOOL_REPORT=$reportPath
        $child = Invoke-IntegrationChildProcess -Arguments @('-NoProfile', '-NonInteractive', '-File', $script:childPath, '-Mode', 'skill-validator', '-ToolchainPath', $script:toolchainPath, '-ToolchainSha256', $script:toolchainHash, '-SourceRevision', ('c' * 40), '-GitEntryModeManifestPath', $script:manifestPath, '-GitEntryModeManifestSha256', $script:manifestHash)
        $child.exitCode | Should -Be 1
        ($child.output -join "`n") | Should -Match 'category|required string field'
    }

    # Scenario: changed Skill content requires central semantic review after the Static pass.
    # Purpose: prove the real child emits its typed trigger after one no-LLM scan and leaves consent handling to Stage 6.
    It 'InterT60_keeps_the_real_static_child_no_llm_and_returns_the_central_semantic_trigger' {
        $spyPath = Join-Path $script:testRoot 'skillspector-static-spy-calls.jsonl'
        $spyToolPath = Join-Path $script:testRoot 'skillspector-static-spy.ps1'
        $staticToolchainPath = Join-Path $script:testRoot 'static-toolchain.json'
        $spySource = @'
$callArguments = @($args | ForEach-Object { [string]$_ })
$line = ConvertTo-Json -InputObject ([pscustomobject]@{ arguments = $callArguments }) -Compress -Depth 5
[IO.File]::AppendAllText($env:SYP154_TEST_STATIC_SPY, $line + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
if ($callArguments -notcontains '--no-llm') {
    [Console]::Error.WriteLine('TEST_SPY_REJECTED_SEMANTIC_INVOCATION')
    $global:LASTEXITCODE = 97
    return
}
$outputIndex = [Array]::IndexOf($callArguments, '--output')
if ($outputIndex -lt 0 -or $outputIndex + 1 -ge $callArguments.Count) {
    [Console]::Error.WriteLine('TEST_SPY_REJECTED_MISSING_OUTPUT_PATH')
    $global:LASTEXITCODE = 98
    return
}
$skillRoot = [string]$callArguments[1]
$componentPaths = @(
    Get-ChildItem -LiteralPath $skillRoot -Recurse -File -Force |
        ForEach-Object { $_.FullName.Substring($skillRoot.Length).TrimStart([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar).Replace([IO.Path]::DirectorySeparatorChar, '/') }
)
[Array]::Sort($componentPaths, [StringComparer]::Ordinal)
$components = @($componentPaths | ForEach-Object { [pscustomobject]@{ path = [string]$_ } })
$report = [ordered]@{
    execution_successful = $true
    analysis_completeness = [ordered]@{
        execution_successful = $true
        is_complete = $true
        status = 'complete'
        coverage_percent = 100
        ledger_exceptions = @()
        scope_exclusions = @()
        limitations = @()
    }
    skill = [ordered]@{ name = 'demo'; source = $skillRoot }
    components = @($components)
    issues = @()
}
$outputPath = [string]$callArguments[$outputIndex + 1]
[IO.File]::WriteAllText($outputPath, (ConvertTo-Json -InputObject $report -Depth 20 -Compress), [Text.UTF8Encoding]::new($false))
$global:LASTEXITCODE = 0
'@
        [IO.File]::WriteAllText($spyToolPath, $spySource, [Text.UTF8Encoding]::new($false))
        $toolchain = [ordered]@{
            skillSpectorPath = $spyToolPath
            skillSpectorSha256 = (Get-FileHash -LiteralPath $spyToolPath -Algorithm SHA256).Hash.ToLowerInvariant()
        }
        [IO.File]::WriteAllText($staticToolchainPath, (ConvertTo-Json -InputObject $toolchain -Compress), [Text.UTF8Encoding]::new($false))
        $staticToolchainHash = (Get-FileHash -LiteralPath $staticToolchainPath -Algorithm SHA256).Hash.ToLowerInvariant()
        $previousSpy = [Environment]::GetEnvironmentVariable('SYP154_TEST_STATIC_SPY')
        [Environment]::SetEnvironmentVariable('SYP154_TEST_STATIC_SPY', $spyPath)
        try {
            $rawBefore = @(Get-ChildItem -LiteralPath $script:testRoot -File -Filter 'native-raw-skillspector-*' | ForEach-Object { $_.FullName })
            $child = Invoke-IntegrationChildProcess -Arguments @(
                '-NoProfile', '-NonInteractive', '-File', $script:childPath,
                '-Mode', 'static', '-SemanticRequired', 'true',
                '-ToolchainPath', $staticToolchainPath, '-ToolchainSha256', $staticToolchainHash,
                '-SourceRevision', ('c' * 40),
                '-GitEntryModeManifestPath', $script:manifestPath,
                '-GitEntryModeManifestSha256', $script:manifestHash
            )
            $calls = @()
            if (Test-Path -LiteralPath $spyPath -PathType Leaf) {
                $calls = @([IO.File]::ReadAllLines($spyPath) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { $_ | ConvertFrom-Json -Depth 5 })
            }
            $newRaw = @(Get-ChildItem -LiteralPath $script:testRoot -File -Filter 'native-raw-skillspector-*' | Where-Object { $rawBefore -cnotcontains $_.FullName })
            $stdoutFiles = @($newRaw | Where-Object { $_.Name -match '\.stdout\.txt$' })
            $stderrFiles = @($newRaw | Where-Object { $_.Name -match '\.stderr\.txt$' })
            $child.exitCode | Should -Be 0 -Because ($child.output -join "`n")
            $calls.Count | Should -Be 1
            @($calls[0].arguments | Where-Object { $_ -ceq '--no-llm' }).Count | Should -Be 1
            $envelope = ($child.output -join "`n") | ConvertFrom-Json -Depth 20
            $envelope.status | Should -Be 'passed'
            $envelope.decision | Should -Be 'PASS'
            $envelope.scannerIdentity | Should -Be 'SkillSpector'
            $envelope.analyzerCompleteness | Should -Be 'complete'
            $envelope.semanticRequired | Should -BeOfType ([bool])
            $envelope.semanticRequired | Should -BeTrue
            $envelope.semanticScan.triggered | Should -BeTrue
            $envelope.semanticScan.status | Should -Be 'not-run'
            $envelope.semanticScan.findingCount | Should -Be 0
            @($envelope.findings).Count | Should -Be 0
            @($envelope.nativeReports).Count | Should -Be 1
            $native = $envelope.nativeReports[0]
            $native.arguments | Should -Contain '--no-llm'
            [int]$native.exitCode | Should -Be 0
            $stdoutFiles.Count | Should -Be 1
            $stderrFiles.Count | Should -Be 1
        }
        finally {
            [Environment]::SetEnvironmentVariable('SYP154_TEST_STATIC_SPY', $previousSpy)
        }
    }

    # Scenario: the extracted authority archive contains unpinned repository files alongside the exact selected closure.
    # Purpose: exercise the fallback helper through its real CLI bindings, including missing-hash and raw-file tamper rejection.
    It 'InterT40_accepts_full_archive_extras_and_rejects_missing_or_tampered_bindings' {
        $repositoryRoot = Split-Path -Parent $PSScriptRoot
        $authority = (Get-Content -LiteralPath (Join-Path $repositoryRoot 'config/standard-v1.json') -Raw | ConvertFrom-Json -Depth 20).authority
        $runId = [guid]::NewGuid().ToString('N')
        $toolsRoot = Join-Path $script:testRoot "skcv1-tools-$runId"
        $authorityRoot = Join-Path (Join-Path $toolsRoot 'authority') "SyuanTsai-AI-Instructions-$($authority.commit)"
        $resolvedToolsRoot = Join-Path (Split-Path -Parent $toolsRoot) "skcv1-resolved-tools-$runId"
        [void](New-Item -ItemType Directory -Path $authorityRoot -Force)
        [void](New-Item -ItemType Directory -Path $resolvedToolsRoot -Force)
        $approvedPaths = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        foreach ($entry in @($authority.files)) {
            $relative = [string]$entry.path
            [void]$approvedPaths.Add($relative)
            $sourcePath = Join-Path $script:moduleRoot ($relative -replace '/', [IO.Path]::DirectorySeparatorChar)
            $destinationPath = Join-Path $authorityRoot ($relative -replace '/', [IO.Path]::DirectorySeparatorChar)
            if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) { throw "The verified fixture source is missing: $relative" }
            [void](New-Item -ItemType Directory -Path (Split-Path -Parent $destinationPath) -Force)
            [IO.File]::Copy($sourcePath, $destinationPath, $true)
        }
        # The production archive includes unrelated repository files. Their contents are
        # intentionally not part of the selected authority closure, so model one harmless
        # extra directly in this owned extraction fixture rather than relying on the
        # independently verified source checkout to be non-sparse.
        $extraArchivePath = Join-Path $authorityRoot 'archive-extra.txt'
        [IO.File]::WriteAllText($extraArchivePath, 'unselected archive file', [Text.UTF8Encoding]::new($false))

        function Get-IntegrationFixtureSha256 {
            param([Parameter(Mandatory = $true)][string] $Path)
            return (Get-FileHash -LiteralPath $Path -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
        }
        $centralRunnerPath = Join-Path $authorityRoot 'scripts/Invoke-StandardValidation.ps1'
        $upstreamAdapterPath = Join-Path $authorityRoot 'scripts/Validate-UpstreamAdapter.ps1'
        $upstreamPolicyPath = Join-Path $authorityRoot 'docs/standards/upstream-adapter.json'
        $toolchain = [ordered]@{
            centralRunnerPath = $centralRunnerPath
            centralRunnerSha256 = Get-IntegrationFixtureSha256 -Path $centralRunnerPath
            upstreamAdapterValidatorPath = $upstreamAdapterPath
            upstreamAdapterValidatorSha256 = Get-IntegrationFixtureSha256 -Path $upstreamAdapterPath
            upstreamPolicyPath = $upstreamPolicyPath
            upstreamPolicySha256 = Get-IntegrationFixtureSha256 -Path $upstreamPolicyPath
        }
        $resolvedToolBindings = @(
            @{ property = 'skillValidator'; relativePath = 'skill-validator/skill-validator.exe' },
            @{ property = 'skillToolsNode'; relativePath = 'node/node.exe'; outsideResolvedRoot = $true },
            @{ property = 'skillToolsEntryPoint'; relativePath = 'skill-tools/entrypoint.js' },
            @{ property = 'skillSpector'; relativePath = 'skillspector/skillspector.exe' },
            @{ property = 'pesterModule'; relativePath = 'Pester/6.2.0/Pester.psd1' }
        )
        foreach ($binding in $resolvedToolBindings) {
            $isOutsideResolvedRoot = $binding.ContainsKey('outsideResolvedRoot') -and [bool]$binding['outsideResolvedRoot']
            $bindingRoot = if ($isOutsideResolvedRoot) { $toolsRoot } else { $resolvedToolsRoot }
            $bindingPath = Join-Path $bindingRoot ([string]$binding.relativePath -replace '/', [IO.Path]::DirectorySeparatorChar)
            [void](New-Item -ItemType Directory -Path (Split-Path -Parent $bindingPath) -Force)
            [IO.File]::WriteAllText($bindingPath, "verified fixture bytes: $($binding.property)", [Text.UTF8Encoding]::new($false))
            $pathField = [string]$binding.property + 'Path'
            $shaField = [string]$binding.property + 'Sha256'
            if ($binding.property -ceq 'skillToolsEntryPoint') { $pathField = 'skillToolsEntryPointPath'; $shaField = 'skillToolsEntryPointSha256' }
            if ($binding.property -ceq 'pesterModule') { $pathField = 'pesterModulePath'; $shaField = 'pesterModuleSha256' }
            $toolchain[$pathField] = $bindingPath
            $toolchain[$shaField] = Get-IntegrationFixtureSha256 -Path $bindingPath
        }
        $toolchain.pesterVersion = '6.2.0'
        $toolchainPath = Join-Path $toolsRoot 'toolchain.json'
        [IO.File]::WriteAllText($toolchainPath, ($toolchain | ConvertTo-Json -Depth 20 -Compress), [Text.UTF8Encoding]::new($false))
        $toolchainSha = Get-IntegrationFixtureSha256 -Path $toolchainPath
        $resolverPath = Join-Path $PSScriptRoot 'ResolveLegacyAuthorityArchiveFixture.ps1'
        $previousAuthorityEnv = [Environment]::GetEnvironmentVariable('SYP154_CANDIDATE_AUTHORITY_ROOT', 'Process')
        try {
            [Environment]::SetEnvironmentVariable('SYP154_CANDIDATE_AUTHORITY_ROOT', $null, 'Process')
            $arguments = @('-NoLogo', '-NoProfile', '-NonInteractive', '-File', $resolverPath,
                '-RepositoryRoot', $repositoryRoot, '-ToolchainPath', $toolchainPath, '-ToolchainSha256', $toolchainSha)
            $output = @(& $script:pwshPath @arguments 2>&1)
            $exitCode = $LASTEXITCODE
            $exitCode | Should -Be 0
            $receipt = ($output -join "`n") | ConvertFrom-Json -Depth 20 -ErrorAction Stop
            $receipt.fixtureMode | Should -Be 'verified-driver-archive'
            $receipt.authorityFileCount | Should -Be 26
            $receipt.authorityExtraFileCount | Should -Be 1
            $receipt.authorityRevision | Should -Be $authority.commit

            $withoutHash = @(& $script:pwshPath -NoLogo -NoProfile -NonInteractive -File $resolverPath `
                -RepositoryRoot $repositoryRoot -ToolchainPath $toolchainPath 2>&1)
            $missingHashExitCode = $LASTEXITCODE
            $missingHashExitCode | Should -Not -Be 0
            ($withoutHash -join "`n") | Should -Match 'ToolchainSha256|MissingMandatoryParameter'

            $tamperEntry = @($authority.files | Where-Object { [string]$_.path -cnotin @(
                'scripts/Invoke-StandardValidation.ps1', 'scripts/Validate-UpstreamAdapter.ps1', 'docs/standards/upstream-adapter.json'
            ) } | Select-Object -First 1)[0]
            $tamperPath = Join-Path $authorityRoot ([string]$tamperEntry.path -replace '/', [IO.Path]::DirectorySeparatorChar)
            [IO.File]::AppendAllText($tamperPath, "`n# tampered`n", [Text.UTF8Encoding]::new($false))
            $tampered = @(& $script:pwshPath @arguments 2>&1)
            $tamperedExitCode = $LASTEXITCODE
            $tamperedExitCode | Should -Not -Be 0
            ($tampered -join "`n") | Should -Match 'raw authority SHA-256 differs'
        }
        finally {
            [Environment]::SetEnvironmentVariable('SYP154_CANDIDATE_AUTHORITY_ROOT', $previousAuthorityEnv, 'Process')
        }
    }

    # Scenario: a trusted authority file is changed only from LF to CRLF.
    # Purpose: reject raw-byte normalization in both driver-extracted archives and verified Git checkouts.
    It 'InterT35_rejects_a_crlf_only_authority_fixture_change' {
        $activeConfig = Get-Content -LiteralPath (Join-Path (Split-Path -Parent $PSScriptRoot) 'config/standard-v1.json') -Raw | ConvertFrom-Json -Depth 20
        $entry = @($activeConfig.authority.files)[0]
        $sourcePath = Join-Path $script:moduleRoot ([string]$entry.path)
        $sourceText = [Text.UTF8Encoding]::new($false, $true).GetString([IO.File]::ReadAllBytes($sourcePath))
        $sourceText.Contains("`r") | Should -BeFalse
        $tamperRoot = Join-Path $script:testRoot 'crlf-authority'
        $tamperPath = Join-Path $tamperRoot ([string]$entry.path)
        [void](New-Item -ItemType Directory -Path (Split-Path -Parent $tamperPath) -Force)
        [IO.File]::WriteAllText($tamperPath, $sourceText.Replace("`n", "`r`n"), [Text.UTF8Encoding]::new($false))
        if ($script:authorityFixtureMode -ceq 'verified-git-checkout') {
            $gitEntry = $script:authorityGitEntries[[string]$entry.path]
            { Assert-IntegrationAuthorityFileIdentity -AuthorityRoot $tamperRoot -Entry $entry -GitEntry $gitEntry } | Should -Throw -ExpectedMessage '*raw SHA-256 differs*'
        }
        else {
            { Assert-IntegrationAuthorityRawFileIdentity -AuthorityRoot $tamperRoot -Entry $entry } | Should -Throw -ExpectedMessage '*raw SHA-256 differs*'
        }
    }
    # Scenario: the same report is supplied with a forged central runner digest.
    # Purpose: a candidate cannot substitute an unverified shared validator and still receive PASS.
    It 'InterT30_rejects_a_mismatched_central_runner_before_tool_execution' {
        $reportPath = Join-Path $script:testRoot 'report.json'
        [IO.File]::WriteAllText($reportPath, (@{ skill_dir = $script:skillRoot; passed = $true; errors = 0; warnings = 0; results = @(@{ level = 'pass'; file = 'SKILL.md'; category = 'structure'; message = 'clean' }) } | ConvertTo-Json -Depth 10 -Compress))
        $env:SYP154_TEST_TOOL_REPORT = $reportPath
        $toolchain = Get-Content -LiteralPath $script:toolchainPath -Raw | ConvertFrom-Json
        $toolchain.centralRunnerSha256 = '0' * 64
        [IO.File]::WriteAllText($script:toolchainPath, ($toolchain | ConvertTo-Json -Compress))
        $forgedToolchainHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $script:toolchainPath).Hash.ToLowerInvariant()
        $child = Invoke-IntegrationChildProcess -Arguments @('-NoProfile', '-NonInteractive', '-File', $script:childPath, '-Mode', 'skill-validator', '-ToolchainPath', $script:toolchainPath, '-ToolchainSha256', $forgedToolchainHash, '-SourceRevision', ('c' * 40), '-GitEntryModeManifestPath', $script:manifestPath, '-GitEntryModeManifestSha256', $script:manifestHash)
        $child.exitCode | Should -Be 1
        ($child.output -join "`n") | Should -Match 'central validation runner changed or is missing'
    }
    # Scenario: the reviewed new authority input is supplied to the actual candidate driver guard.
    # Purpose: prove the extracted real driver guard accepts a valid pin before
    # counting its rejection cases as coverage.
    It 'UnitT35_accepts_exact_candidate_authority_config' {
        $config = Get-Content -LiteralPath (Join-Path (Split-Path -Parent $PSScriptRoot) 'config/standard-v1.json') -Raw | ConvertFrom-Json
        $config.authority.commit = '8aabd22694a05771f98639f6d726cc9a620eb94b'
        $config.authority.archiveUrl = 'https://codeload.github.com/SyuanTsai/SyuanTsai-AI-Instructions/zip/8aabd22694a05771f98639f6d726cc9a620eb94b'
        $config.authority.archiveSha256 = 'd92df1a8f0aa342970dc9c66a77b6211955b4708de12119cb7f9a360fd265311'
        ($config.authority.files | Where-Object path -CEQ 'scripts/Resolve-PythonWheelClosure.py').sha256 = 'd209c973f331fdbb82a4d546bda18b1d485bcd1e446dd446b6d8bc4360b5ce35'
        ($config.authority.files | Where-Object path -CEQ 'scripts/Resolve-StandardValidationTool.ps1').sha256 = '86540ff07e1b73177d179ae6a9ee2f0fef8029e27286604d68a9a98d0d205ec2'
        ($config.authority.files | Where-Object path -CEQ 'docs/standards/standard-validation-contract-v1.json').sha256 = '6fa3233e86ec7918aebf1413d41a6d1712f55eb2d1b09262fe18e53ddfbcb8cf'
        ($config.authority.files | Where-Object path -CEQ 'scripts/Invoke-StandardValidation.ps1').sha256 = 'c127309958226417291b512d633caa2120bbd12a663c98fff1d63106cf5a2677'
        $prefix = $script:validationSource.Substring(0, $script:childMatch.Index)
        & {
            param($DriverPrefix, $CandidateConfig)
            . ([scriptblock]::Create($DriverPrefix))
            Assert-AuthorityConfig -Config $CandidateConfig
        } $prefix $config
    }

    # Scenario: candidate authority config substitutes commit, archive or member identity.
    # Purpose: exercise the driver's actual strict guard without acquiring any tools.
    It 'UnitT40_rejects_wrong_authority_archive_or_member_<Field>' -TestCases @(
        @{ Field = 'commit' }, @{ Field = 'archiveSha256' }, @{ Field = 'member' },
        @{ Field = 'obsoleteRevision' },
        @{ Field = 'scripts/Resolve-PythonWheelClosure.py' },
        @{ Field = 'scripts/Resolve-StandardValidationTool.ps1' },
        @{ Field = 'docs/standards/standard-validation-contract-v1.json' },
        @{ Field = 'scripts/Invoke-StandardValidation.ps1' }
    ) {
        param($Field)
        $config = Get-Content -LiteralPath (Join-Path (Split-Path -Parent $PSScriptRoot) 'config/standard-v1.json') -Raw | ConvertFrom-Json
        if ($Field -eq 'obsoleteRevision') {
            $config.authority.commit = '7c65254d96bd21083ae827e54b9e51afee8ce304'
            $config.authority.archiveUrl = 'https://codeload.github.com/SyuanTsai/SyuanTsai-AI-Instructions/zip/7c65254d96bd21083ae827e54b9e51afee8ce304'
            $config.authority.archiveSha256 = '093e511b8ca9d2618d74d42a5ed831a54524bb133cba9f310b33e7a107a6ff9d'
        }
        elseif ($Field.Contains('/')) { ($config.authority.files | Where-Object path -CEQ $Field).sha256 = '0' * 64 }
        elseif ($Field -eq 'member') { $config.authority.files[0].sha256 = '0' * 64 }
        elseif ($Field -eq 'commit') { $config.authority.commit = '0' * 40 }
        else { $config.authority.archiveSha256 = '0' * 64 }
        $prefix = $script:validationSource.Substring(0, $script:childMatch.Index)
        {
            & {
                param($DriverPrefix, $CandidateConfig)
                . ([scriptblock]::Create($DriverPrefix))
                Assert-AuthorityConfig -Config $CandidateConfig
            } $prefix $config
        } | Should -Throw -ExpectedMessage $(if ($Field -eq 'member' -or $Field.Contains('/')) { '*authority file identity mismatch*' } else { '*exact approved P02 authority snapshot*' })
    }
}
