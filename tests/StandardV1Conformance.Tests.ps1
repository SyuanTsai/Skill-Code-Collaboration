# SPDX-FileCopyrightText: 2026 SyuanTsai
# SPDX-License-Identifier: Apache-2.0
Describe 'Code Collaboration Standard v1 conformance' {
    BeforeAll {
        $script:RepositoryRoot = Split-Path -Parent $PSScriptRoot
        $script:SourcePath = Join-Path $script:RepositoryRoot 'catalog/source.json'
        $script:AdapterPath = Join-Path $script:RepositoryRoot 'config/standard-v1.json'
        $script:ValidatorPath = Join-Path $script:RepositoryRoot 'scripts/Validate.ps1'
        $script:DriverPath = Join-Path $script:RepositoryRoot 'scripts/StandardSourceDriver.psm1'
    }

    It 'UnitT00_uses_the_canonical_schema_v2_source_inventory_and_source_root' {
        # Scenario: a legacy runtime root or source-owned cross-source catalog is reintroduced.
        # Purpose: keep this repository on the canonical source package topology.
        Test-Path -LiteralPath (Join-Path $script:RepositoryRoot 'skills') -PathType Container | Should -BeTrue
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
        if ($exactGitRoot) {
            $trackedAgentEntries = @(& $git.Path -C $script:RepositoryRoot ls-files --cached -- '.agents/skills')
            if ($LASTEXITCODE -ne 0) { throw 'Could not inspect tracked Agent skill entries at the exact repository root.' }
            @($trackedAgentEntries | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }).Count | Should -Be 0
        }
        else {
            # Candidate snapshots may be nested below another worktree. Only inspect
            # their own files; never let an ancestor repository supply inventory.
            Test-Path -LiteralPath (Join-Path $script:RepositoryRoot '.agents') -PathType Container | Should -BeFalse
        }
        $source = Get-Content -LiteralPath $script:SourcePath -Raw | ConvertFrom-Json -Depth 20
        @($source.PSObject.Properties.Name) | Should -Be @('schemaVersion','sourceId','repository','skillsRoot','skills')
        $source.schemaVersion | Should -Be 2
        $source.sourceId | Should -Be 'code-collaboration'
        $source.repository | Should -Be 'https://github.com/SyuanTsai/Skill-Code-Collaboration.git'
        $source.skillsRoot | Should -Be 'skills'
        @($source.skills) | Should -Be @('write-copilot-implementation-prompt')
    }

    # Scenario: The Code config is read from the extracted candidate.
    # Purpose: Keep the reviewed active 8e authority bundle complete without adding local security policy.
    It 'UnitT10_pins_exact_authority_without_local_security_policy' {
        # Scenario: a consumer pins an earlier, partial, or reordered Standard v1 snapshot.
        # Purpose: require the exact protected active 8e tuple without changing the v1 adapter schema.
        $adapter = Get-Content -LiteralPath $script:AdapterPath -Raw | ConvertFrom-Json -Depth 20
        Import-Module -Name $script:DriverPath -Force
        $expectedCommit = '8e627baf54bd6e47862e6291b25e71cc45a2f2b7'
        $pin = Get-PreparedSourceAuthorityPin -AuthorityRevision $expectedCommit
        @($adapter.PSObject.Properties.Name) | Should -Be @('schemaVersion', 'standardVersion', 'authority')
        $adapter.schemaVersion | Should -Be 1
        $adapter.standardVersion | Should -Be 'v1'
        $adapter.authority.repository | Should -Be 'https://github.com/SyuanTsai/SyuanTsai-AI-Instructions.git'
        $adapter.authority.commit | Should -Be $expectedCommit
        $adapter.authority.archiveUrl | Should -Be "https://codeload.github.com/SyuanTsai/SyuanTsai-AI-Instructions/zip/$expectedCommit"
        $adapter.authority.archiveSha256 | Should -Be '9aa4a7fc8fc7c7f0ff9e774c79c77a64077b4003212a523dda519d034ff99989'
        @($adapter.authority.files).Count | Should -Be 32
        @($adapter.authority.files.path) | Should -Be @($pin.files.Keys)
        foreach ($entry in @($adapter.authority.files)) { $entry.sha256 | Should -Be $pin.files[$entry.path] }
        @($adapter.PSObject.Properties.Name) | Should -Not -Contain 'security'
        @($adapter.PSObject.Properties.Name) | Should -Not -Contain 'deviations'
    }

    It 'exposes one canonical validator and catalog domain dispatch' {
        # Scenario: local and CI commands diverge or the profile catalog is left outside the gate.
        # Purpose: expose one entry point while keeping catalog validation inside Repository Tests.
        $validator = Get-Content -LiteralPath $script:ValidatorPath -Raw
        $validator | Should -Match 'Invoke-StandardValidation\.ps1'
        $validator | Should -Match '-DevelopmentHarness'
        $validator | Should -Match 'standard-validation-adapter\.json'
        $validator | Should -Match 'repository-test-catalog'
        $validator | Should -Match 'tests/validate-catalog\.ps1'
        $validator | Should -Match 'repository-test-pester'
    }

    It 'runs repository smoke and profile catalog validation against an extracted snapshot' {
        # Scenario: the central runner executes Repository Tests without .git metadata.
        # Purpose: keep both domain contracts on read-only candidate snapshot inputs.
        $validator = Get-Content -LiteralPath $script:ValidatorPath -Raw
        $validator | Should -Match '(?s)Join-Path \$candidateRoot ''scripts/Test-Repository\.ps1''.*\$validatorPath -RepositoryRoot \$candidateRoot.*-ReadOnlySnapshot'
        $validator | Should -Match '(?s)Join-Path \$candidateRoot ''tests/validate-catalog\.ps1''.*\$validatorPath -RepositoryRoot \$candidateRoot'
    }

    It 'routes CI through the canonical validator without a second installer policy' {
        # Scenario: CI adds a parallel validator or installs tools outside the central resolver.
        # Purpose: keep local, pre-push, and CI validation on the same canonical command and trust boundary.
        $workflow = Get-Content -LiteralPath (Join-Path $script:RepositoryRoot '.github/workflows/validate.yml') -Raw
        $workflow | Should -Match 'scripts/Validate\.ps1'
        $workflow | Should -Not -Match 'tests/validate-catalog\.ps1'
        $workflow | Should -Match 'persist-credentials:\s*false'
        $workflow | Should -Match 'actions/checkout@[0-9a-f]{40}'
        $workflow | Should -Match 'actions/setup-go@[0-9a-f]{40}'
        $workflow | Should -Not -Match '(?m)^\s*(Install-Module|npm install|go install|pip install)\b'
        Test-Path -LiteralPath (Join-Path $script:RepositoryRoot '.github/workflows/skill-validator.yml') | Should -BeFalse

        foreach ($context in @('repository-contract', 'skill-validator', 'skill-tools')) {
            $pattern = "(?ms)^\s+{0}:\s+name:\s+{0}.*?needs:\s+- canonical-validation.*?{1}" -f `
                [regex]::Escape($context),
                [regex]::Escape("needs['canonical-validation'].result")
            $workflow | Should -Match $pattern
        }
    }

    It 'keeps no-base workflow events unbased instead of substituting HEAD^' {
        # Scenario: workflow_dispatch or a push with an all-zero before SHA has no comparison base.
        # Purpose: require the canonical validator to perform full-candidate change detection.
        $workflow = Get-Content -LiteralPath (Join-Path $script:RepositoryRoot '.github/workflows/validate.yml') -Raw
        $workflow | Should -Not -Match 'git rev-parse HEAD\^'
        $workflow | Should -Match "else \{\s*''\s*\}"
        foreach ($stepName in @('Prepare source tools once', 'Run full source validation')) {
            $escapedName = [regex]::Escape($stepName)
            $step = [regex]::Match($workflow, "(?ms)- name: $escapedName(?<body>.*?)(?=^      - name:|^  [A-Za-z0-9_-]+:)")
            $step.Success | Should -BeTrue
            $body = $step.Groups['body'].Value
            $body | Should -Match 'if \(-not \[string\]::IsNullOrWhiteSpace\(\$baseCommit\)\)'
            $body | Should -Match ([regex]::Escape("`$baseArguments = @('-BaseCommit', `$baseCommit)"))
            $body | Should -Match '\+ \$baseArguments'
        }
    }

    It 'keeps public validation documentation on the canonical entry point' {
        # Scenario: component validators become undocumented alternate release gates.
        # Purpose: document Validate.ps1 as the sole public validation command.
        $readme = Get-Content -LiteralPath (Join-Path $script:RepositoryRoot 'README.md') -Raw
        $readme | Should -Match 'scripts/Validate\.ps1'
        $readme | Should -Not -Match 'scripts/(?:Invoke-StandardValidation|Test-Repository)\.ps1'
        $readme | Should -Not -Match '(?i)\b(?:Invoke-Pester|pytest|skill-validator|skill-tools|skillspector)\b'

        $release = Get-Content -LiteralPath (Join-Path $script:RepositoryRoot 'docs/RELEASE.md') -Raw
        $release | Should -Match 'scripts/Validate\.ps1'
        $release | Should -Not -Match 'scripts/(?:Get-SourcePin|Test-Repository)\.ps1'
        $release | Should -Not -Match 'tests/validate-catalog\.ps1'
    }
}
