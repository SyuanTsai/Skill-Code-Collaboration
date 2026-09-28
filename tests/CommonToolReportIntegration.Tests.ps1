# SPDX-FileCopyrightText: 2026 SyuanTsai
# SPDX-License-Identifier: Apache-2.0
Describe 'Code child uses central package tool report rules' {
    BeforeAll {
        $validationPath = if ([string]::IsNullOrWhiteSpace($env:SYP154_TEST_VALIDATE_SOURCE)) { Join-Path (Split-Path -Parent $PSScriptRoot) 'scripts/Validate.ps1' } else { [string]$env:SYP154_TEST_VALIDATE_SOURCE }
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
        if ([string]::IsNullOrWhiteSpace($env:SYP154_CANDIDATE_AUTHORITY_ROOT)) {
            # Run the actual candidate driver against its immutable authority,
            # including when the protected CI driver still uses an older pin.
            $repositoryRoot = Split-Path -Parent $PSScriptRoot
            $authority = (Get-Content -LiteralPath (Join-Path $repositoryRoot 'config/standard-v1.json') -Raw | ConvertFrom-Json).authority
            $archive = Join-Path $script:testRoot 'authority.zip'
            Invoke-WebRequest -Uri ([string]$authority.archiveUrl) -OutFile $archive -TimeoutSec 60
            if ((Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant() -cne [string]$authority.archiveSha256) {
                throw 'Integration authority archive identity differs from the candidate pin.'
            }
            $extract = Join-Path $script:testRoot 'authority'
            Expand-Archive -LiteralPath $archive -DestinationPath $extract
            $roots = @(Get-ChildItem -LiteralPath $extract -Directory)
            if ($roots.Count -ne 1) { throw 'Integration authority archive must contain one root.' }
            $moduleRoot = $roots[0].FullName
            foreach ($entry in @($authority.files)) {
                $path = Join-Path $moduleRoot ([string]$entry.path)
                if ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -cne [string]$entry.sha256) {
                    throw "Integration authority file identity differs: $($entry.path)"
                }
            }
        }
        else { $moduleRoot = [string]$env:SYP154_CANDIDATE_AUTHORITY_ROOT }
        $script:runnerPath = Join-Path $moduleRoot 'scripts/Invoke-StandardValidation.ps1'
        $script:pwshPath = (Get-Command pwsh -CommandType Application | Select-Object -First 1).Source
        $script:priorEnv = @{}
        foreach ($name in @('STANDARD_VALIDATION_ACTIVE_SKILLS', 'STANDARD_VALIDATION_SKILLS_ROOT', 'STANDARD_VALIDATION_SKILL_ID', 'STANDARD_VALIDATION_CANDIDATE_ID', 'STANDARD_VALIDATION_CANDIDATE_ROOT', 'STANDARD_VALIDATION_SKILL_INVENTORY_SHA256', 'SYP154_TEST_TOOL_REPORT', 'SYP154_CANDIDATE_AUTHORITY_ROOT')) {
            $script:priorEnv[$name] = [Environment]::GetEnvironmentVariable($name)
        }
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

    BeforeEach {
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
        foreach ($name in $script:priorEnv.Keys) { [Environment]::SetEnvironmentVariable($name, $script:priorEnv[$name]) }
        $expectedParent = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([IO.Path]::DirectorySeparatorChar)
        $actualParent = [IO.Path]::GetFullPath((Split-Path -Parent $script:testRoot)).TrimEnd([IO.Path]::DirectorySeparatorChar)
        if ($actualParent -cne $expectedParent -or (Split-Path -Leaf $script:testRoot) -cnotmatch '^syp154-report-[0-9a-f]{32}$') {
            throw 'Integration test cleanup root is not the allocated temporary directory.'
        }
        Remove-Item -LiteralPath $script:testRoot -Recurse -Force
    }

    # Scenario: a package tool emits a success report with a string error count.
    # Purpose: the Code child must reject malformed counts through the shared authority rule.
    It 'InterT10_rejects_string_error_count_from_the_real_Code_child' {
        $reportPath = Join-Path $script:testRoot 'report.json'
        [IO.File]::WriteAllText($reportPath, (@{ skill_dir = $script:skillRoot; passed = $true; errors = '0'; warnings = 0; results = @(@{ level = 'pass'; file = 'SKILL.md'; category = 'structure'; message = 'clean' }) } | ConvertTo-Json -Depth 10 -Compress))
        $env:SYP154_TEST_TOOL_REPORT = $reportPath
        $output = & $script:pwshPath -NoProfile -NonInteractive -File $script:childPath -Mode skill-validator -ToolchainPath $script:toolchainPath -ToolchainSha256 $script:toolchainHash -SourceRevision ('c' * 40) -GitEntryModeManifestPath $script:manifestPath -GitEntryModeManifestSha256 $script:manifestHash 2>&1
        $LASTEXITCODE | Should -Be 1
        ($output -join "`n") | Should -Match 'typed nonnegative integer|counters must be JSON integers'
    }

    # Scenario: the same candidate-bound tool returns typed zero counts.
    # Purpose: the shared report rule must allow the normal Code envelope path.
    It 'InterT20_accepts_typed_zero_counts_through_the_real_Code_child' {
        $reportPath = Join-Path $script:testRoot 'report.json'
        [IO.File]::WriteAllText($reportPath, (@{ skill_dir = $script:skillRoot; passed = $true; errors = 0; warnings = 0; results = @(@{ level = 'pass'; file = 'SKILL.md'; category = 'structure'; message = 'clean' }) } | ConvertTo-Json -Depth 10 -Compress))
        $env:SYP154_TEST_TOOL_REPORT = $reportPath
        $output = & $script:pwshPath -NoProfile -NonInteractive -File $script:childPath -Mode skill-validator -ToolchainPath $script:toolchainPath -ToolchainSha256 $script:toolchainHash -SourceRevision ('c' * 40) -GitEntryModeManifestPath $script:manifestPath -GitEntryModeManifestSha256 $script:manifestHash 2>&1
        $LASTEXITCODE | Should -Be 0 -Because ($output -join "`n")
        $envelope = ($output -join "`n") | ConvertFrom-Json -Depth 10
        $envelope.decision | Should -Be 'PASS'
        $envelope.candidateIdentity | Should -Be ('a' * 64)
    }

    # Scenario: a clean report belongs to a neighboring candidate root.
    # Purpose: the actual candidate child must reject a report from another Skill.
    It 'InterT25_rejects_wrong_root_through_the_real_Code_child' {
        $wrongRoot = Join-Path $script:testRoot 'skills/neighbor'
        [void](New-Item -ItemType Directory -Path $wrongRoot -Force)
        $reportPath = Join-Path $script:testRoot 'report.json'
        [IO.File]::WriteAllText($reportPath, (@{ skill_dir = $wrongRoot; passed = $true; errors = 0; warnings = 0; results = @(@{ level = 'pass'; file = 'SKILL.md'; category = 'structure'; message = 'clean' }) } | ConvertTo-Json -Depth 10 -Compress))
        $env:SYP154_TEST_TOOL_REPORT = $reportPath
        $output = & $script:pwshPath -NoProfile -NonInteractive -File $script:childPath -Mode skill-validator -ToolchainPath $script:toolchainPath -ToolchainSha256 $script:toolchainHash -SourceRevision ('c' * 40) -GitEntryModeManifestPath $script:manifestPath -GitEntryModeManifestSha256 $script:manifestHash 2>&1
        $LASTEXITCODE | Should -Be 1
        ($output -join "`n") | Should -Match 'report root does not match candidate Skill|clean candidate-bound report'
    }

    # Scenario: a clean-root report omits required result category/message fields.
    # Purpose: retain Code's existing domain result checks while adopting shared rules.
    It 'InterT27_retains_Code_result_field_guards' {
        $reportPath=Join-Path $script:testRoot 'report.json'
        [IO.File]::WriteAllText($reportPath,(@{skill_dir=$script:skillRoot;passed=$true;errors=0;warnings=0;results=@(@{level='pass';file='SKILL.md'})}|ConvertTo-Json -Depth 10 -Compress))
        $env:SYP154_TEST_TOOL_REPORT=$reportPath
        $output=& $script:pwshPath -NoProfile -NonInteractive -File $script:childPath -Mode skill-validator -ToolchainPath $script:toolchainPath -ToolchainSha256 $script:toolchainHash -SourceRevision ('c'*40) -GitEntryModeManifestPath $script:manifestPath -GitEntryModeManifestSha256 $script:manifestHash 2>&1
        $LASTEXITCODE|Should -Be 1
        ($output-join "`n")|Should -Match 'category|required string field'
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
        $output = & $script:pwshPath -NoProfile -NonInteractive -File $script:childPath -Mode skill-validator -ToolchainPath $script:toolchainPath -ToolchainSha256 $forgedToolchainHash -SourceRevision ('c' * 40) -GitEntryModeManifestPath $script:manifestPath -GitEntryModeManifestSha256 $script:manifestHash 2>&1
        $LASTEXITCODE | Should -Be 1
        ($output -join "`n") | Should -Match 'central validation runner changed or is missing'
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
