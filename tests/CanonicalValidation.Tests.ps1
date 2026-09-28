# SPDX-FileCopyrightText: 2026 SyuanTsai
# SPDX-License-Identifier: Apache-2.0
Describe 'Canonical Standard v1 validation adapter' {
    BeforeAll {
        $script:RepositoryRoot = Split-Path -Parent $PSScriptRoot
        $script:ValidatorPath = Join-Path $script:RepositoryRoot 'scripts/Validate.ps1'
        $script:Validator = Get-Content -LiteralPath $script:ValidatorPath -Raw
        $script:RepositoryValidator = Get-Content -LiteralPath (Join-Path $script:RepositoryRoot 'scripts/Test-Repository.ps1') -Raw
        $script:Adapter = Get-Content -LiteralPath (Join-Path $script:RepositoryRoot 'config/standard-v1.json') -Raw |
            ConvertFrom-Json -Depth 20
        $script:ExpectedAuthorityCommit = '7c65254d96bd21083ae827e54b9e51afee8ce304'
        $script:ExpectedAuthorityArchiveSha256 = '093e511b8ca9d2618d74d42a5ed831a54524bb133cba9f310b33e7a107a6ff9d'
        $script:ExpectedAuthorityFiles = [ordered]@{
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
            'scripts/Resolve-PythonWheelClosure.py' = '7fa1511a3e3ba257c6d9e37f929f68e5684184a3a2756a3f9e765ccc6e69d208'
            'scripts/Resolve-StandardValidationTool.ps1' = '3bdda55964acb92fb32d06ffdbf6f98c9397b1857a88271c398b3f28e4bd6295'
            'docs/standards/schemas/standard-validation-adapter-v1.schema.json' = '11aa88fc25716d748bd4f514f1a44f02390ad1745dd5a5c5beee07f642fd5639'
            'docs/standards/schemas/standard-validation-evidence-v1.schema.json' = '8ed4a9d7158273d7a1e9d898acf07f57e9170822cb7cbb70f1e2eec7195867ee'
            'docs/standards/standard-validation-contract-v1.json' = '014e82d2db4f3a95be53f5120460790fc613f32b13d06f4e43f4a41dd89f53ee'
            'docs/standards/pr12-source-merge-adoption.json' = '4c5262f2a11d228195230c15fa4faaf9614af6b59f110e5d9c08f242ce809175'
            'docs/standards/trust-anchors/human-approval-public-key.xml' = '1e46153b72d02f3ce2fb26becd449df4f1590d8e5cb441b1954006a5602bbd9b'
            'docs/standards/trust-anchors/trusted-supervisor-public-key.xml' = '4d550851f43405920156f40c9fc648d99a69dd73efc200f6968d8a837e7fbf27'
            'scripts/Invoke-StandardValidation.ps1' = '9aefa495189a177bd0b429c1274517deaf0519156a05b43ae1ad03e8ace393e1'
            'docs/standards/schemas/standard-semantic-consent-evidence-v2.schema.json' = '109091979d0a47e2035d3d8b20963fcdb85680e5da737bf1f27121608115d430'
            'scripts/StandardSemanticBridge.psm1' = 'daf90f703898cc56fc3310e1eec462bafa6552edcac0de4f08a3cd4b9f63a429'
            'docs/standards/schemas/upstream-adapter-v1.schema.json' = '3cff6246463188a91cc54c6a46315a949314767a759c6214e5b28e4db95ac8d7'
            'docs/standards/upstream-adapter.json' = 'c4f5133b24841bb9c66182dc3d5a027596f864ec28e410d47249a67b3b97ad31'
            'scripts/Validate-UpstreamAdapter.ps1' = '3b6e6474690b1ae9f9486544b68f50ca29b96f5dbe6aa8d6c6cd8570afad500b'
        }
    }

    # Scenario: The Code adapter and validator are loaded with the e69 authority inventory.
    # Purpose: Reject mismatched commit, archive, or required-file hashes before validation.
    It 'UnitT10_pins_exact_authority_without_local_deviation_policy' {
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
        $script:Validator | Should -Match 'function Get-PropertyValue'
        $script:Validator | Should -Match 'return ,\$Object\.PSObject\.Properties\[\$Name\]\.Value'
        $script:Validator | Should -Match 'foreach \(\$result in \$results\)'
    }

    It 'keeps repository domain, catalog, and Pester child output JSON-only' {
        # Scenario: a repository component writes a human-readable success line before its JSON evidence.
        # Purpose: keep the central runner envelope parseable and make catalog validation a canonical child stage.
        $script:Validator | Should -Match '& \$validatorPath -RepositoryRoot \$candidateRoot -OutputPath \$reportPath -ReadOnlySnapshot -GitEntryModeManifestPath \$GitEntryModeManifestPath \*> \$null'
        $script:Validator | Should -Match 'tests/validate-catalog\.ps1'
        $script:Validator | Should -Match 'Invoke-Pester -Path \$testRoot -Output None -PassThru 6>\$null'
    }

    It 'carries immutable Git entry modes into snapshot integrity validation' {
        # Scenario: ZIP extraction changes a committed symlink into an ordinary file.
        # Purpose: keep snapshot validation bound to the candidate commit's original Git entry types.
        $script:Validator | Should -Match 'Get-GitEntryModeManifest'
        $script:Validator | Should -Match 'ls-tree.*--format=.*objectmode.*objectname.*path'
        $script:Validator | Should -Match 'Get-GitBlobSha256'
        $script:Validator | Should -Match 'sha256 = Get-GitBlobSha256'
        $script:Validator | Should -Match 'candidate Git entry manifest'
        $script:Validator | Should -Match 'candidate-git-entry-modes\.json'
        $script:Validator | Should -Match '& \$validatorPath -RepositoryRoot \$candidateRoot -OutputPath \$reportPath -ReadOnlySnapshot -GitEntryModeManifestPath \$GitEntryModeManifestPath \*> \$null'
        $script:Validator | Should -Match '\[string\] \$GitEntryModeManifestPath'
        $script:Validator | Should -Match "'-GitEntryModeManifestPath', \`$candidateGitEntryModeManifestPath"
    }

    It 'binds extracted Skill bytes to committed Git blob digests' {
        # Scenario: git archive export-subst rewrites a committed placeholder before extraction.
        # Purpose: prevent rewritten snapshot bytes from becoming trusted integrity evidence.
        $script:RepositoryValidator | Should -Match 'filesystem content is not bound to its committed Git blob'
        $script:Validator | Should -Match 'schemaVersion = 3; candidateCommit = \$CandidateCommit; entries = \$entries'
        $script:RepositoryValidator | Should -Match "Expected @\('path', 'mode', 'sha256'\)"
        $script:Validator | Should -Match 'Assert-CandidateSnapshotMatchesManifest'
        $script:Validator | Should -Match 'GitEntryModeManifestSha256'
    }

    It 'requires scalar authority identity fields before comparison' {
        # Scenario: an authority identity field is encoded as a singleton JSON array.
        # Purpose: prevent PowerShell collection comparison from accepting schema-invalid authority metadata.
        $script:Validator | Should -Match '\$Config\.standardVersion -isnot \[string\]'
        $script:Validator | Should -Match '\$Config\.authority\.repository -isnot \[string\]'
        $script:Validator | Should -Match '\$Config\.authority\.commit -isnot \[string\]'
        $script:Validator | Should -Match 'authority identity fields must be scalar strings'
    }

    It 'requires scalar authority file identity fields before comparison' {
        # Scenario: an authority file path or digest is encoded as a singleton JSON array.
        # Purpose: prevent explicit string casts from accepting schema-invalid file inventory entries.
        $script:Validator | Should -Match '\$file\.path -isnot \[string\] -or \$file\.sha256 -isnot \[string\]'
        $script:Validator | Should -Match 'authority file at index \$index must contain scalar string path and sha256 values'
    }

    It 'validates raw SkillSpector arrays before deserialization' {
        # Scenario: a SkillSpector report returns a null or schema-drifted issues value.
        # Purpose: distinguish a valid empty JSON array from a null report field after PowerShell deserialization.
        $script:Validator | Should -Match 'function Assert-JsonText'
        $script:Validator | Should -Match '\.ValueKind -ne \[System\.Text\.Json\.JsonValueKind\]::Array'
        $script:Validator | Should -Match '-ArrayPropertyPaths \$skillspectorArrayPropertyPaths'
        $script:Validator | Should -Match '\$issues = Get-PropertyValue -Object \$Report -Name ''issues'' -Context ''SkillSpector report'''
        $script:Validator | Should -Match '\$issues\s+-isnot\s+\[array\]'
    }

    It 'executes and validates conditional semantic SkillSpector analysis' {
        # Scenario: a Skill change or static Finding requires the semantic pass.
        # Purpose: ensure SemanticRequired triggers a real non-static scan before the envelope is emitted.
        $script:Validator | Should -Match '\$semanticTriggered = \(\$SemanticRequired -ceq ''true''\) -or \$findings\.Count -gt 0'
        $script:Validator | Should -Match 'scan \$skillRoot --format json --output \$semanticReportPath'
        $script:Validator | Should -Match 'Assert-SkillSpectorReport -Report \$semanticReport .* -Stage ''conditional-semantic-scan'''
        $script:Validator | Should -Match 'semanticScan = \[ordered\]@'
    }

    It 'rejects ambiguous JSON and scalar skill-validator collections' {
        # Scenario: a resolved package validator emits duplicate properties or a non-array results value.
        # Purpose: prevent lossy ConvertFrom-Json materialization from turning malformed evidence into PASS.
        $script:Validator | Should -Match 'function Assert-NoDuplicateJsonProperties'
        $script:Validator | Should -Match 'Assert-NoDuplicateJsonProperties -Element \$document.RootElement'
        $script:Validator | Should -Match '-ArrayPropertyPaths @\(''results''\)'
        $script:Validator | Should -Match '\$results = Get-PropertyValue -Object \$Report -Name ''results'''
    }

    It 'preserves SARIF arrays and validates complete typed package-tool results' {
        # Scenario: a package tool emits a singleton/non-array SARIF run, an incomplete validator result, or string coverage.
        # Purpose: reject schema drift before PowerShell normalization or numeric coercion can turn malformed evidence into PASS.
        $script:Validator | Should -Match '\$runs = Get-PropertyValue -Object \$Report -Name ''runs'''
        $script:Validator | Should -Match 'skill-tools SARIF runs must be an array'
        $script:Validator | Should -Match '-ArrayPropertyPaths @\(''runs'', ''runs\[\]\.tool\.driver\.rules'''
        $script:Validator | Should -Match '\$categoryValue = Get-PropertyValue -Object \$result -Name ''category'''
        $script:Validator | Should -Match '\$messageValue = Get-PropertyValue -Object \$result -Name ''message'''
        $script:Validator | Should -Match 'result is missing a required string field'
        $script:Validator | Should -Match 'skill-validator report counters must be JSON integers'
        $script:Validator | Should -Match 'skill-validator result line must be a positive JSON integer'
        $script:Validator | Should -Match '\$coverageType = if'
        $script:Validator | Should -Match '\[TypeCode\]::Double'
        $script:Validator | Should -Match 'function Assert-JsonArrayPropertyPath'
        $script:Validator | Should -Match 'runs\[\]\.results\[\]\.locations'
        $script:Validator | Should -Match '\$rules = Get-PropertyValue -Object \$driver -Name ''rules'''
        $script:Validator | Should -Match '\$locations = Get-PropertyValue -Object \$result -Name ''locations'''
        $script:Validator | Should -Match '\[Collections\.Generic\.Dictionary\[string, object\]\]::new\(\[StringComparer\]::Ordinal\)'
        $script:Validator | Should -Match 'skill-tools SARIF contains a duplicate rule ID'
        $script:Validator | Should -Match 'function Get-ScalarProperty'
        $script:Validator | Should -Match '\$execution = Get-ScalarProperty -Object \$Report -Name ''execution_successful'''
        $script:Validator | Should -Match '\$statusValue = Get-ScalarProperty -Object \$completeness -Name ''status'''
        $script:Validator | Should -Match '\$statusValue = Get-ScalarProperty -Object \$report -Name ''status'''
        $script:Validator | Should -Match 'scalar JSON value'
        $script:Validator | Should -Match '\$schemaVersionType = if'
        $script:Validator | Should -Match 'schemaVersion must be integer 1'
        $script:Validator | Should -Match 'if \(\$toolName -ceq ''skillspector''\) \{\s+Remove-Item -LiteralPath ''Env:GITHUB_TOKEN'', ''Env:GH_TOKEN'''
        $script:Validator | Should -Match '\[void\]\(Assert-PathWithinRoot -Path \$toolPath -Root \$resolvedToolsRoot'
        $script:Validator | Should -Match 'if \(\$entry\.confineToResolvedRoot\)'
        $script:Validator | Should -Match 'skill-tools Node''; confineToResolvedRoot = \$false'
        $script:Validator | Should -Match 'Assert-NoReparseAncestors -Path \$toolPath -Context "\$\(\$entry\.name\) receipt path"'
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

    # Scenario: the Code source builds repository-test adapters for the e69 central runner.
    # Purpose: keep all three repository-test IDs paired with schema-valid kinds before Stage 1 starts.
    It 'UnitT20_declares_exact_repository_test_kinds' {
        $script:Validator | Should -Match "id = 'repository-test-integrity'; kind = 'general';"
        $script:Validator | Should -Match "id = 'repository-test-catalog'; kind = 'general';"
        $script:Validator | Should -Match "id = 'repository-test-pester'; kind = 'pester';"
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
        $script:Validator | Should -Match '\$changedRecords = @\(& \$gitPath -C \$repoRoot diff --find-renames=100% --name-status \$changeDetectionBase \$candidateCommit\)'
        $script:Validator | Should -Match '\$pathValues = if \(\$status -cmatch ''\^\[RC\]\[0-9\]\+\$''\)'
        $script:Validator | Should -Match '\$changedPaths \+= \[string\]\$pathValue'
    }

    It 'keeps generated roots outside the artifact root when local defaults share the system temp path' {
        # Scenario: RUNNER_TEMP is unset and ArtifactsRoot defaults to the system temp directory.
        # Purpose: prevent trusted tools and candidate extraction from being rejected as artifact descendants.
        $script:Validator | Should -Match '\$externalRootParent = Split-Path -Parent \$artifactsRootPath'
        $script:Validator | Should -Match 'skcv1-artifacts-'
        $script:Validator | Should -Match '\$outputFull = if \(\[string\]::IsNullOrWhiteSpace\(\$OutputPath\)\) \{ Join-Path \$runRoot'
        $script:Validator | Should -Match 'Join-Path \$externalRootParent "skcv1-tools-\$runId"'
        $script:Validator | Should -Match 'Join-Path \$externalRootParent "skcv1-candidate-\$runId"'
        $script:Validator | Should -Match 'Join-Path \$externalRootParent "skcv1-resolved-tools-\$runId"'
        $script:Validator | Should -Match 'externalRootCandidates'
        $script:Validator | Should -Match 'LocalApplicationData'
    }

    It 'cleans run-owned external roots after validation' {
        # Scenario: a persistent workstation or self-hosted runner executes validation repeatedly.
        # Purpose: reclaim the run-specific tool, candidate, and resolved-tool roots after success or failure.
        $script:Validator | Should -Match '\$script:ExternalCleanupRoots = @\(\$trustedRoot, \$candidateExtractRoot, \$resolvedToolsRoot\)'
        $script:Validator | Should -Match 'Remove-Item -LiteralPath \$cleanupRoot -Recurse -Force'
        $script:Validator | Should -Match '\$script:ValidationExitCode = \$centralExitCode'
        $script:Validator | Should -Match '(?s)catch \{\s+throw\s+\}\s+finally \{.*ExternalCleanupRoots'
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
