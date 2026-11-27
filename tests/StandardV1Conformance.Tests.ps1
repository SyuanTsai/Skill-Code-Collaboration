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

    It 'forbids copying CLI credentials or redirecting CLI home directories' {
        $skill = Get-Content -Raw -LiteralPath (Join-Path $script:RepositoryRoot 'skills/orchestrate-ai-delivery/SKILL.md')
        $skill.Contains('Never copy, move, or read CLI credential or auth files, and never redirect an executor''s CLI configuration or home directory through environment variables.', [StringComparison]::Ordinal) | Should -BeTrue
        $dispatch = Get-Content -Raw -LiteralPath (Join-Path $script:RepositoryRoot 'skills/orchestrate-ai-delivery/references/dispatch.md')
        $dispatch.Contains('## CLI credentials and home directories', [StringComparison]::Ordinal) | Should -BeTrue
        foreach ($token in @('`CLAUDE_CONFIG_DIR`', '`CODEX_HOME`')) {
            $dispatch.Contains($token, [StringComparison]::Ordinal) | Should -BeTrue
        }
        $normalized = $dispatch -replace '\s+', ' '
        $normalized.Contains('Never copy, move, or read CLI credential or auth files', [StringComparison]::Ordinal) | Should -BeTrue
        $normalized.Contains('Sessions, logs, and caches that an executor CLI writes under its own home directory are normal CLI behavior.', [StringComparison]::Ordinal) | Should -BeTrue
        $normalized.Contains('Do not work around them by relocating credentials; note in the delivery which CLI wrote state outside the repository.', [StringComparison]::Ordinal) | Should -BeTrue
        $skill.Contains('CLI state an executor writes under its own home directory is normal; note it in the delivery.', [StringComparison]::Ordinal) | Should -BeTrue
    }

    # Scenario: The finding policy covers unchanged behavior, baseline regressions, and re-review.
    # Purpose: Preserve explicit user decisions and all valid findings through review.
    It 'UnitT10_preserves the unchanged-behavior and baseline-regression finding policy' {
        $review = Get-Content -Raw -LiteralPath (Join-Path $script:RepositoryRoot 'skills/orchestrate-ai-delivery/references/review.md')
        foreach ($sentence in @(
            '### Unchanged Behavior and Baseline Regressions'
            'The change regresses behavior relative to the baseline: an input or environment that succeeded before the change, such as a file-name length, a permission, or a platform difference, now fails.'
            'The change modifies behavior that the requirement states must remain unchanged.'
            'When the requirement states that behavior must remain unchanged, do not modify that behavior. If a pre-existing defect is found in it, preserve the original behavior, record the defect as a follow-up item, and ask the user to decide.'
            'A functional regression relative to the baseline remains a valid finding until it is fixed or the user explicitly accepts that specific regression, even when the controller''s own change introduced it. Never downgrade it to a follow-up item.'
            'If the requirements cannot all be met, disclose the blocker, keep the delivery incomplete, and stop at the human gate for the user''s decision. Record the affected scope and decision source only after the user explicitly accepts that specific regression.'
            'Re-review the fixed part and related regressions. Preserve the reviewer''s ability to report every valid finding within that scope, including findings that recur. A documented, explicit user decision may give the reviewer scope context when cited with its source. Keep directions to omit valid findings out of every review prompt.'
            'Only suggestions such as hardening or refactoring that do not satisfy a Valid Findings condition become follow-up items.'
            'Pre-existing defects in behavior that the requirement states must remain unchanged; preserve the original behavior and ask the user to decide.'
            'Baseline regressions: verify that inputs and environments that succeeded at the baseline still succeed, including file-name length after an added prefix or suffix, file permissions or attributes, and platform differences. Verify the scope and decision source for any specific regression the user explicitly accepted.'
            'Behavior that the requirement states must remain unchanged is unchanged, including its pre-existing defects.'
        )) {
            $review.Contains($sentence, [StringComparison]::Ordinal) | Should -BeTrue
        }

        $skill = Get-Content -Raw -LiteralPath (Join-Path $script:RepositoryRoot 'skills/orchestrate-ai-delivery/SKILL.md')
        foreach ($sentence in @(
            'A functional regression relative to the baseline remains a valid finding until it is fixed or the user explicitly accepts that specific regression. If the requirements cannot all be met, disclose the blocker, keep the delivery incomplete, and stop at the human gate. Record the scope and decision source only when the user explicitly accepts the specific regression.'
            'Keep re-review scoped to the fix and related regressions. Let reviewers report every valid finding in scope, including recurring findings. When an explicit user decision applies, cite its source as scope context and preserve the reviewer''s ability to raise findings.'
            'When the requirement states that behavior must remain unchanged, never modify that behavior; if a pre-existing defect is found in it, preserve the original behavior, record it as a follow-up item, and ask the user to decide.'
            'A regression relative to the baseline is valid even when the controller''s own change introduced it.'
        )) {
            $skill.Contains($sentence, [StringComparison]::Ordinal) | Should -BeTrue
        }
    }

    It 'preserves the implementation prompt output contract' {
        $text = Get-Content -Raw -LiteralPath (Join-Path $script:RepositoryRoot 'skills/write-implementation-prompt/SKILL.md')
        foreach ($heading in @('Changed files', 'Summary', 'Test commands', 'Test results', 'Blockers')) {
            $text.Contains($heading, [StringComparison]::Ordinal) | Should -BeTrue
        }
        $text.Contains('never include local user names, absolute paths, machine identifiers, credentials, or tokens.', [StringComparison]::Ordinal) | Should -BeTrue
    }

    It 'requires controller self-usage and model ID in usage reports' {
        $text = Get-Content -Raw -LiteralPath (Join-Path $script:RepositoryRoot 'skills/orchestrate-ai-delivery/references/usage-report.md')
        $text.Contains("Always list the controller's exact model ID, read from its own session record, in the Model column; never leave it blank or write only the product name.", [StringComparison]::Ordinal) | Should -BeTrue
        $text.Contains("Read the controller's own usage from its local session record before delivery; never write it as Unavailable when that record is readable.", [StringComparison]::Ordinal) | Should -BeTrue
        $text.Contains('Label controller usage read during the session as "known as of <UTC time>, before delivery"; it excludes the delivery turn itself. Do not estimate the remainder.', [StringComparison]::Ordinal) | Should -BeTrue
        $text.Contains('In the Source column, write record locations with ~ or a repository-relative path, never an absolute path or user name.', [StringComparison]::Ordinal) | Should -BeTrue
        $text.Contains('message.id', [StringComparison]::Ordinal) | Should -BeTrue
        $text.Contains('thread_token_usage', [StringComparison]::Ordinal) | Should -BeTrue
        $text.Contains('session.usage_record', [StringComparison]::Ordinal) | Should -BeTrue
        $text | Should -Not -Match '[A-Za-z]:\\Users\\|/Users/|/home/'
    }

    It 'requires evidence-scoped dispatch for code-evidence documentation prompts' {
        $text = Get-Content -Raw -LiteralPath (Join-Path $script:RepositoryRoot 'skills/write-implementation-prompt/SKILL.md')
        $text.Contains('When delegated work must investigate code before writing or updating documentation (code-evidence documentation), require an evidence-scoped dispatch; for a single small documentation edit, allow a streamlined dispatch without an evidence table.', [StringComparison]::Ordinal) | Should -BeTrue
        $text.Contains('Classify evidence as at least `confirmed in code`, `confirmed not mapped`, or `unconfirmed`; never mark inference, a missing result, a DTO declaration, or recent documentation as confirmed.', [StringComparison]::Ordinal) | Should -BeTrue
        $text.Contains('Require symbol-first searches, then only necessary excerpts, and return relevant excerpts, diffs, and summaries rather than whole files or storage XML without justification; allow justified reinspection for new evidence, failures, or state drift, without hard read-count limits.', [StringComparison]::Ordinal) | Should -BeTrue
        $text.Contains('For an evidence-scoped dispatch, within the existing five report headings, put a compact evidence table under `Summary` with source, target, condition, status, commit/file/symbol; do not add or rename headings.', [StringComparison]::Ordinal) | Should -BeTrue
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
