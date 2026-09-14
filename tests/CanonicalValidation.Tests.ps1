# SPDX-FileCopyrightText: 2026 SyuanTsai
# SPDX-License-Identifier: Apache-2.0
Describe 'Canonical Standard v1 validation adapter' {
    BeforeAll {
        $script:RepositoryRoot = Split-Path -Parent $PSScriptRoot
        $script:ValidatorPath = Join-Path $script:RepositoryRoot 'scripts/Validate.ps1'
        $script:Validator = Get-Content -LiteralPath $script:ValidatorPath -Raw
        $script:Adapter = Get-Content -LiteralPath (Join-Path $script:RepositoryRoot 'config/standard-v1.json') -Raw |
            ConvertFrom-Json -Depth 20
        $script:ExpectedAuthorityCommit = 'a403abdf038a3346d775431a6908a71cc3d35a5b'
        $script:ExpectedAuthorityArchiveSha256 = '17154929fadfa63487263db1efcb78f4948195af9c11c25a66432eff3411b2d3'
        $script:ExpectedAuthorityFiles = [ordered]@{
            'docs/standards/README.md' = '5e1ddd737d26a5ec1ff1ebd08e158376ddaf1ea21008bb987fc7f51376923f7c'
            'docs/standards/managed-skill-lifecycle.md' = '70950cf8bdd02819efae6f6e06ac5be1da3e70f809c23e3c6f8d3b217797416c'
            'docs/standards/schemas/managed-skill-lifecycle-v1.schema.json' = '9a7f4c02588d2b88194e953a41766a72a9426fa89d4c3781c5750dcc22d35863'
            'docs/standards/schemas/openai-agent-metadata.schema.json' = '23c1aaee28a54fea1946a61d6122a2097906ffa5bdd66c8014fc6b1625c9062a'
            'docs/standards/schemas/source-inventory-v2.schema.json' = '084550944b4141ab5535f58fb6e99730a5c34b56103f6b59fd5a352679caa98e'
            'docs/standards/schemas/validation-security-gate-v1.schema.json' = '56979baa08f3ec5534e3a17f925d53e69accd4cdc500872e92ca56b694044ea6'
            'docs/standards/skill-repository-review-matrix.md' = 'c345ad3ec32d1941df5c5757ce96b4430c0223b3f8ed99f2a4de7dc9923410f2'
            'docs/standards/skill-repository-standard.md' = '78a72aa8214acd5a5e202df34bbb20f8cfd841ab3d181de10645a777267cfd5d'
            'docs/standards/upstream-interoperability.md' = '9c544fbfb6b77a589514f1926aa1488882e932786a303a42ce6c6c9b2ba80c7e'
            'docs/standards/validation-security-gate.json' = 'e303e8c3d484012022f5c4da694c3fe21ff02395b0b9b7e973a4234d4182f485'
            'docs/standards/validation-toolchain.json' = '5925dcb1aea1e545b9787a29825e7a0cc03a04c777cd68ab44c9bdd7482ff579'
            'scripts/Invoke-StandardAuthorityGate.ps1' = 'c98d3f1b181ba0e7d3894729a8f1636984407c20454a27e0e383799c2f90425f'
            'scripts/Resolve-PythonWheelClosure.py' = '7fa1511a3e3ba257c6d9e37f929f68e5684184a3a2756a3f9e765ccc6e69d208'
            'scripts/Resolve-StandardValidationTool.ps1' = '3744bc4549612e5997361315a8fd5e1ea803ade26052cf4eaf2ccdc1776fcf6e'
            'docs/standards/schemas/standard-validation-adapter-v1.schema.json' = '1b45052712450d40df278937d381018b9ce2ded2cbf42845db65f8028e56df44'
            'docs/standards/schemas/standard-validation-evidence-v1.schema.json' = '24d8b0f29f9bddd8af1bee02943fb46c72ca5d4a874727cb107ff68a39af12b9'
            'docs/standards/standard-validation-contract-v1.json' = '2b3d6da1c97c5542a9761445da9de5f101ada53e83cb1f17ee90c8b0d4929356'
            'docs/standards/trust-anchors/human-approval-public-key.xml' = '1e46153b72d02f3ce2fb26becd449df4f1590d8e5cb441b1954006a5602bbd9b'
            'docs/standards/trust-anchors/trusted-supervisor-public-key.xml' = '4d550851f43405920156f40c9fc648d99a69dd73efc200f6968d8a837e7fbf27'
            'scripts/Invoke-StandardValidation.ps1' = '3cee28379d5612e4592f1755d8732e6b869018402b7d82efacd89fa10bcafd57'
            'docs/standards/schemas/upstream-adapter-v1.schema.json' = '3cff6246463188a91cc54c6a46315a949314767a759c6214e5b28e4db95ac8d7'
            'docs/standards/upstream-adapter.json' = 'c4f5133b24841bb9c66182dc3d5a027596f864ec28e410d47249a67b3b97ad31'
            'scripts/Validate-UpstreamAdapter.ps1' = '7fd3c2c34544b21b769ebfa9238c379e094e022381b7ebe11f3e196e623fd376'
        }
    }

    It 'pins the exact merged P02 authority snapshot without a local deviation policy' {
        # Scenario: a consumer repository changes the authority pin or silently adds a local policy.
        # Purpose: require the complete approved P02 bundle and keep policy ownership in the central authority.
        @($script:Adapter.PSObject.Properties.Name) | Should -Be @('schemaVersion', 'standardVersion', 'authority')
        $script:Adapter.authority.commit | Should -Be $script:ExpectedAuthorityCommit
        $script:Adapter.authority.archiveUrl | Should -Be "https://codeload.github.com/SyuanTsai/SyuanTsai-AI-Instructions/zip/$($script:ExpectedAuthorityCommit)"
        $script:Adapter.authority.archiveSha256 | Should -Be $script:ExpectedAuthorityArchiveSha256
        @($script:Adapter.authority.files).Count | Should -Be $script:ExpectedAuthorityFiles.Count
        foreach ($file in @($script:Adapter.authority.files)) {
            $script:ExpectedAuthorityFiles.Contains($file.path) | Should -BeTrue
            $file.sha256 | Should -Be $script:ExpectedAuthorityFiles[$file.path]
        }
        $script:Adapter.PSObject.Properties.Name | Should -Not -Contain 'deviations'
    }

    It 'verifies authority before resolving or executing any validation tool' {
        # Scenario: the authority archive or one of its bound files is tampered with.
        # Purpose: fail closed before any external validator can execute.
        $archiveIndex = $script:Validator.IndexOf('Expand-Archive')
        $archiveHashIndex = $script:Validator.IndexOf('Authority archive SHA-256 does not match')
        $fileHashIndex = $script:Validator.IndexOf('Authority file identity mismatch')
        $resolverIndex = $script:Validator.LastIndexOf('resolverPath = Join-Path')
        $centralIndex = $script:Validator.LastIndexOf('centralRunnerPath = Join-Path')

        $archiveIndex | Should -BeGreaterThan -1
        $archiveHashIndex | Should -BeGreaterThan $archiveIndex
        $fileHashIndex | Should -BeGreaterThan $archiveHashIndex
        $resolverIndex | Should -BeGreaterThan $fileHashIndex
        $centralIndex | Should -BeGreaterThan $resolverIndex
    }

    It 'passes resolver named arguments through the trusted PowerShell host' {
        # Scenario: a resolver argument contains a value that must not be reparsed by a shell.
        # Purpose: preserve the exact argument vector through the trusted host.
        $script:Validator | Should -Match '& \$PowerShellPath -NoProfile -NonInteractive -File \$ResolverPath @Arguments'
        $script:Validator | Should -Match 'Invoke-Resolver -PowerShellPath \$pwshPath'
    }

    It 'expands collection-valued package reports before validating each result' {
        # Scenario: a validator returns more than one result or a PowerShell singleton array.
        # Purpose: validate each report item without scalar/collection ambiguity.
        $script:Validator | Should -Match 'return \$Object\.PSObject\.Properties\[\$Name\]\.Value'
        $script:Validator | Should -Not -Match 'return ,\$Object\.PSObject\.Properties\[\$Name\]\.Value'
        $script:Validator | Should -Match 'foreach \(\$result in \$results\)'
    }

    It 'keeps repository domain, catalog, and Pester child output JSON-only' {
        # Scenario: a repository component writes a human-readable success line before its JSON evidence.
        # Purpose: keep the central runner envelope parseable and make catalog validation a canonical child stage.
        $script:Validator | Should -Match '& \$validatorPath -RepositoryRoot \$candidateRoot -OutputPath \$reportPath -ReadOnlySnapshot \*> \$null'
        $script:Validator | Should -Match 'tests/validate-catalog\.ps1'
        $script:Validator | Should -Match 'Invoke-Pester -Path \$testRoot -Output None -PassThru 6>\$null'
    }

    It 'normalizes a singleton active Skill inventory before child comparisons' {
        # Scenario: a source repository contains exactly one active Skill.
        # Purpose: keep cross-platform PowerShell child validation from treating the Skill ID as a scalar string.
        $script:Validator | Should -Match '\$activeSkills = @\(Get-ActiveSkills\)'
    }

    It 'uses the P02 central runner as the only stage and severity orchestrator' {
        # Scenario: a consumer adapter attempts to recreate stage ordering or security disposition locally.
        # Purpose: leave lifecycle, severity, and approval semantics solely to the central authority runner.
        $script:Validator | Should -Match 'Invoke-StandardValidation\.ps1'
        $script:Validator | Should -Match '-DevelopmentHarness'
        $script:Validator | Should -Match '& \$pwshPath -NoProfile -NonInteractive -File \$centralRunnerPath @centralRunnerArgs'
        $script:Validator | Should -Match 'standard-validation-adapter\.json'
        $script:Validator | Should -Match 'packageAdapter'
        $script:Validator | Should -Match 'skillValidator'
        $script:Validator | Should -Match 'skillTools'
        $script:Validator | Should -Match 'staticAnalyzer'
        $script:Validator | Should -Match 'repositoryTests'
        $script:Validator | Should -Not -Match 'ConvertTo-ValidationSecurityFinding'
        $script:Validator | Should -Not -Match 'deviations\s*='
        $script:Validator | Should -Not -Match 'Get-ValidationSecurityAction'
    }

    It 'runs the upstream adapter and both package tools for every active Skill before Static' {
        # Scenario: a new Skill is added to catalog/source.json after migration.
        # Purpose: prove the adapter exposes the inventory-driven package barrier and does not allow Static to bypass it.
        $script:Validator | Should -Match "packageAdapter = \[ordered\]@"
        $script:Validator | Should -Match "skillValidator = \[ordered\]@"
        $script:Validator | Should -Match "skillTools = \[ordered\]@"
        $script:Validator | Should -Match "staticAnalyzer = \[ordered\]@"
        $script:Validator | Should -Match "repository-test-catalog"
        $script:Validator | Should -Match "repository-catalog"
        $script:Validator | Should -Match "repository-test-pester"
    }

    It 'keeps domain catalog and Pester dispatch after Static' {
        # Scenario: a profile catalog is malformed while package and Static checks pass.
        # Purpose: ensure profile correctness remains inside the canonical Repository Tests barrier.
        $repositoryTestsIndex = $script:Validator.IndexOf('repositoryTests = @(')
        $staticIndex = $script:Validator.IndexOf('staticAnalyzer = [ordered]@')
        $catalogIndex = $script:Validator.IndexOf('repository-test-catalog')
        $pesterIndex = $script:Validator.IndexOf('repository-test-pester')
        $repositoryTestsIndex | Should -BeGreaterThan $staticIndex
        $catalogIndex | Should -BeGreaterThan $repositoryTestsIndex
        $pesterIndex | Should -BeGreaterThan $catalogIndex
    }

    It 'binds an immutable distinct base ancestor before invoking the central runner' {
        # Scenario: a pull request or push supplies an invalid, equal, or unrelated base revision.
        # Purpose: bind one immutable comparison range before candidate execution.
        $script:Validator | Should -Match 'rev-parse --verify --end-of-options'
        $script:Validator | Should -Match 'merge-base --is-ancestor'
        $script:Validator | Should -Match 'Base commit must be a distinct ancestor'
        $script:Validator | Should -Match 'BaseRevision'
        $script:Validator | Should -Match '--prefix=candidate-\$candidateCommit/'
    }

    It 'preserves an unbased run and scans the full candidate from the empty tree' {
        # Scenario: workflow_dispatch or an initial push has no meaningful base commit.
        # Purpose: prevent a HEAD^ fallback from hiding Skill changes in an earlier candidate commit.
        $script:Validator | Should -Not -Match 'IsNullOrWhiteSpace\(\$BaseCommit\).*HEAD\^'
        $script:Validator | Should -Match '4b825dc642cb6eb9a060e54bf8d69288fbee4904'
        $script:Validator | Should -Match '\$semanticRequired = \$unbased'
        $script:Validator | Should -Match '\$changedPaths = @\(& \$gitPath -C \$repoRoot diff --find-renames=100% --name-only \$changeDetectionBase \$candidateCommit\)'
    }

    It 'keeps generated roots outside the artifact root when local defaults share the system temp path' {
        # Scenario: RUNNER_TEMP is unset and ArtifactsRoot defaults to the system temp directory.
        # Purpose: prevent trusted tools and candidate extraction from being rejected as artifact descendants.
        $script:Validator | Should -Match '\$externalRootParent = Split-Path -Parent \$artifactsRootPath'
        $script:Validator | Should -Match 'Join-Path \$externalRootParent "skcv1-tools-\$runId"'
        $script:Validator | Should -Match 'Join-Path \$externalRootParent "skcv1-candidate-\$runId"'
        $script:Validator | Should -Match 'Join-Path \$externalRootParent "skcv1-resolved-tools-\$runId"'
        $script:Validator | Should -Not -Match 'Join-Path \(\[IO.Path\]::GetTempPath\(\)\) "skcv1-(?:tools|candidate|resolved-tools)-'
    }

    It 'keeps generated adapter and evidence roots outside the candidate' {
        # Scenario: an output path or temporary tool root is redirected into the candidate repository.
        # Purpose: prevent evidence and resolved tools from changing the immutable candidate.
        $script:Validator | Should -Match 'Assert-OutsideRoot -Path \$artifactsRootPath -Root \$repoRoot'
        $script:Validator | Should -Match 'trustedRoot'
        $script:Validator | Should -Match 'skcv1-resolved-tools-\$runId'
        $script:Validator | Should -Match 'Assert-NoReparseAncestors -Path \$resolvedToolsRoot'
        $script:Validator | Should -Match 'Assert-PathWithinRoot'
        $script:Validator | Should -Match 'OutputPath'
    }

    It 'does not execute a candidate domain test before the central runner' {
        # Scenario: a consumer wrapper directly invokes Test-Repository or Pester before authority binding.
        # Purpose: keep the central runner as the only public stage orchestrator.
        $directDomainCall = [regex]::Escape("& (Join-Path `$repoRoot 'scripts/Test-Repository.ps1')")
        $script:Validator | Should -Not -Match $directDomainCall
        $childRunnerMarker = '$childRunnerText = @' + [char]39
        $entryPoint = $script:Validator.Substring(0, $script:Validator.IndexOf($childRunnerMarker))
        $entryPoint | Should -Not -Match 'Import-Module.*Pester'
    }
}
