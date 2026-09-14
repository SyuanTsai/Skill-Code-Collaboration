# SPDX-FileCopyrightText: 2026 SyuanTsai
# SPDX-License-Identifier: Apache-2.0
Describe 'Code Collaboration Standard v1 conformance' {
    BeforeAll {
        $script:RepositoryRoot = Split-Path -Parent $PSScriptRoot
        $script:SourcePath = Join-Path $script:RepositoryRoot 'catalog/source.json'
        $script:AdapterPath = Join-Path $script:RepositoryRoot 'config/standard-v1.json'
        $script:ValidatorPath = Join-Path $script:RepositoryRoot 'scripts/Validate.ps1'
    }

    It 'uses the canonical schema v2 source inventory and source root' {
        # Scenario: a legacy runtime root or source-owned cross-source catalog is reintroduced.
        # Purpose: keep this repository on the canonical source package topology.
        Test-Path -LiteralPath (Join-Path $script:RepositoryRoot 'skills') -PathType Container | Should -BeTrue
        $legacyEntries = @(& git -C $script:RepositoryRoot ls-tree -r --name-only HEAD -- '.agents/skills')
        $legacyEntries.Count | Should -Be 0
        $source = Get-Content -LiteralPath $script:SourcePath -Raw | ConvertFrom-Json -Depth 20
        @($source.PSObject.Properties.Name) | Should -Be @('schemaVersion','sourceId','repository','skillsRoot','skills')
        $source.schemaVersion | Should -Be 2
        $source.sourceId | Should -Be 'code-collaboration'
        $source.repository | Should -Be 'https://github.com/SyuanTsai/Skill-Code-Collaboration.git'
        $source.skillsRoot | Should -Be 'skills'
        @($source.skills) | Should -Be @('write-copilot-implementation-prompt')
    }

    It 'pins the exact P02 authority bundle without a local security policy' {
        # Scenario: a consumer pins an earlier or partial Standard v1 snapshot.
        # Purpose: require the same immutable authority bundle used by the merged P02/P03/P04 implementations.
        $adapter = Get-Content -LiteralPath $script:AdapterPath -Raw | ConvertFrom-Json -Depth 20
        @($adapter.PSObject.Properties.Name) | Should -Be @('schemaVersion', 'standardVersion', 'authority')
        $adapter.schemaVersion | Should -Be 1
        $adapter.standardVersion | Should -Be 'v1'
        $adapter.authority.repository | Should -Be 'https://github.com/SyuanTsai/SyuanTsai-AI-Instructions.git'
        $adapter.authority.commit | Should -Be 'a403abdf038a3346d775431a6908a71cc3d35a5b'
        $adapter.authority.archiveSha256 | Should -Be '17154929fadfa63487263db1efcb78f4948195af9c11c25a66432eff3411b2d3'
        @($adapter.authority.files).Count | Should -Be 23
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

    It 'keeps public validation documentation on the canonical entry point' {
        # Scenario: component validators become undocumented alternate release gates.
        # Purpose: document Validate.ps1 as the sole public validation command.
        $readme = Get-Content -LiteralPath (Join-Path $script:RepositoryRoot 'README.md') -Raw
        $readme | Should -Match 'scripts/Validate\.ps1'
        $readme | Should -Not -Match 'scripts/(?:Invoke-StandardValidation|Test-Repository)\.ps1'
        $readme | Should -Not -Match '(?i)\b(?:Invoke-Pester|pytest|skill-validator|skill-tools|skillspector)\b'
    }
}
