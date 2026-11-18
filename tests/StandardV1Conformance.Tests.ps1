# SPDX-FileCopyrightText: 2026 SyuanTsai
# SPDX-License-Identifier: Apache-2.0
$ErrorActionPreference = 'Stop'

BeforeAll {
    $script:RepositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
}

Describe 'Code Collaboration consumer conformance' {
    It 'uses the canonical schema v2 source inventory and source root' {
        $source = Get-Content -Raw -LiteralPath (Join-Path $script:RepositoryRoot 'catalog/source.json') | ConvertFrom-Json
        $source.schemaVersion | Should -Be 2
        $source.sourceId | Should -BeExactly 'code-collaboration'
        $source.skillsRoot | Should -BeExactly 'skills'
        @($source.skills) | Should -Be @('orchestrate-ai-delivery', 'write-implementation-prompt')
    }

    It 'preserves the orchestration Skill policy boundary' {
        $text = Get-Content -Raw -LiteralPath (Join-Path $script:RepositoryRoot 'skills/orchestrate-ai-delivery/SKILL.md')
        $text.Contains('Never commit or push without user consent.', [StringComparison]::Ordinal) | Should -BeTrue
        $text.Contains('Only Jira, Git, and CLIs are in scope. Confluence is not.', [StringComparison]::Ordinal) | Should -BeTrue
        $text.Contains('If execution mode is missing, ask; never assume it.', [StringComparison]::Ordinal) | Should -BeTrue
    }

    It 'preserves the implementation prompt output contract' {
        $text = Get-Content -Raw -LiteralPath (Join-Path $script:RepositoryRoot 'skills/write-implementation-prompt/SKILL.md')
        foreach ($heading in @('Changed files', 'Summary', 'Test commands', 'Test results', 'Blockers')) {
            $text.Contains($heading, [StringComparison]::Ordinal) | Should -BeTrue
        }
        $text.Contains('never include local user names, absolute paths, machine identifiers, credentials, or tokens.', [StringComparison]::Ordinal) | Should -BeTrue
    }

    It 'keeps OpenAI metadata bound to exact Skill tokens' {
        $cases = @(
            @{ Id = 'orchestrate-ai-delivery'; Token = '$orchestrate-ai-delivery' }
            @{ Id = 'write-implementation-prompt'; Token = '$write-implementation-prompt' }
        )
        foreach ($case in $cases) {
            $text = Get-Content -Raw -LiteralPath (Join-Path $script:RepositoryRoot "skills/$($case.Id)/agents/openai.yaml")
            $text.Contains($case.Token, [StringComparison]::Ordinal) | Should -BeTrue
            $text.Contains('short_description: "', [StringComparison]::Ordinal) | Should -BeTrue
        }
    }

    It 'documents pinned consumer validation and the three repository checks' {
        $readme = Get-Content -Raw -LiteralPath (Join-Path $script:RepositoryRoot 'README.md')
        $readme.Contains('config/authority-pin.json', [StringComparison]::Ordinal) | Should -BeTrue
        $readme.Contains('consumer-gate', [StringComparison]::Ordinal) | Should -BeTrue
        foreach ($name in @('Test-CodeCollaborationRepository.ps1', 'Test-CodeCollaborationCatalog.ps1', 'tests/')) {
            $readme.Contains($name, [StringComparison]::Ordinal) | Should -BeTrue
        }
    }

    It 'keeps release rollback adoption and Windows guidance on the consumer model' {
        foreach ($relative in @('docs/RELEASE.md', 'docs/ROLLBACK.md', 'docs/SOURCE-VALIDATION-ADOPTION.md', 'docs/WINDOWS-SUPPORT.md')) {
            $text = Get-Content -Raw -LiteralPath (Join-Path $script:RepositoryRoot $relative)
            $text.Contains('consumer gate', [StringComparison]::OrdinalIgnoreCase) | Should -BeTrue
            $text.Contains('config/authority-pin.json', [StringComparison]::Ordinal) | Should -BeTrue
        }
    }

    It 'exposes both general checks with the snapshot parameter contract' {
        foreach ($relative in @('scripts/Test-CodeCollaborationRepository.ps1', 'scripts/Test-CodeCollaborationCatalog.ps1')) {
            $tokens = $null
            $errors = $null
            $ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $script:RepositoryRoot $relative), [ref]$tokens, [ref]$errors)
            @($errors) | Should -HaveCount 0
            $parameters = @($ast.ParamBlock.Parameters.Name.VariablePath.UserPath)
            $parameters | Should -Contain 'RepositoryRoot'
            $parameters | Should -Contain 'ReadOnlySnapshot'
        }
    }
}
