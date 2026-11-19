# SPDX-FileCopyrightText: 2026 SyuanTsai
# SPDX-License-Identifier: Apache-2.0
$ErrorActionPreference = 'Stop'

BeforeAll {
    . (Join-Path $PSScriptRoot 'ResolveLegacyAuthorityArchiveFixture.ps1')
    $script:RepositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
    $script:CheckPath = Join-Path $script:RepositoryRoot 'scripts/Test-CodeCollaborationRepository.ps1'

    function New-RepositoryFixture {
        $root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        Copy-CodeCollaborationFixture -RepositoryRoot $script:RepositoryRoot -DestinationRoot $root
    }

    function Add-RepositorySkillFixture {
        param([Parameter(Mandatory)][string] $Root)

        $sourceSkillId = 'write-implementation-prompt'
        $newSkillId = 'zz-added-skill'
        $sourceSkillRoot = Join-Path $Root "skills/$sourceSkillId"
        $newSkillRoot = Join-Path $Root "skills/$newSkillId"
        Copy-Item -LiteralPath $sourceSkillRoot -Destination $newSkillRoot -Recurse
        foreach ($relative in @('SKILL.md', 'agents/openai.yaml')) {
            $path = Join-Path $newSkillRoot $relative
            $text = Get-Content -Raw -LiteralPath $path
            [IO.File]::WriteAllText($path, $text.Replace($sourceSkillId, $newSkillId), [Text.UTF8Encoding]::new($false))
        }

        $sourcePath = Join-Path $Root 'catalog/source.json'
        $source = Get-Content -Raw -LiteralPath $sourcePath | ConvertFrom-Json
        [string[]]$sourceSkills = @($source.skills) + $newSkillId
        [Array]::Sort($sourceSkills, [StringComparer]::Ordinal)
        $source.skills = $sourceSkills
        Write-CodeCollaborationJson -Path $sourcePath -Value $source

        $catalogPath = Join-Path $Root 'catalog/profiles.json'
        $catalog = Get-Content -Raw -LiteralPath $catalogPath | ConvertFrom-Json -Depth 50
        $template = @($catalog.skills | Where-Object { $_.id -ceq $sourceSkillId })[0]
        $added = $template | ConvertTo-Json -Depth 50 | ConvertFrom-Json -Depth 50
        $added.id = $newSkillId
        $added.source.path = "skills/$newSkillId"
        $added.dependencies = @()
        $catalog.skills = @($catalog.skills) + $added
        foreach ($profile in @($catalog.profiles)) {
            if (@($added.profiles) -ccontains [string]$profile.id) {
                [string[]]$includes = @($profile.includes) + $newSkillId
                [Array]::Sort($includes, [StringComparer]::Ordinal)
                $profile.includes = $includes
            }
        }
        Write-CodeCollaborationJson -Path $catalogPath -Value $catalog

        $gatePath = Join-Path $Root 'config/consumer-gate.json'
        $gate = Get-Content -Raw -LiteralPath $gatePath | ConvertFrom-Json -Depth 50
        [string[]]$activeSkills = @($gate.activeSkills) + $newSkillId
        [Array]::Sort($activeSkills, [StringComparer]::Ordinal)
        $gate.activeSkills = $activeSkills
        Write-CodeCollaborationJson -Path $gatePath -Value $gate
        return $newSkillId
    }
}

Describe 'Code Collaboration repository check' {
    It 'accepts the current snapshot without repository metadata' {
        $fixture = New-RepositoryFixture
        Test-Path -LiteralPath (Join-Path $fixture '.git') | Should -BeFalse
        $result = Invoke-CodeCollaborationCheck -Path $script:CheckPath -RepositoryRoot $fixture
        $result.result | Should -BeExactly 'passed'
        $result.activeSkillCount | Should -Be 2
        @($result.skills.skillId) | Should -Be @('orchestrate-ai-delivery', 'write-implementation-prompt')
    }

    It 'produces deterministic ordinal content inventories' {
        $fixture = New-RepositoryFixture
        $first = Invoke-CodeCollaborationCheck -Path $script:CheckPath -RepositoryRoot $fixture
        $second = Invoke-CodeCollaborationCheck -Path $script:CheckPath -RepositoryRoot $fixture
        ($first.skills | ConvertTo-Json -Depth 20 -Compress) | Should -BeExactly ($second.skills | ConvertTo-Json -Depth 20 -Compress)
        foreach ($skill in @($first.skills)) {
            [string[]]$actual = @($skill.files.path)
            [string[]]$expected = @($actual)
            [Array]::Sort($expected, [StringComparer]::Ordinal)
            ($actual -join "`n") | Should -BeExactly ($expected -join "`n")
            [string]$skill.contentSha256 | Should -Match '^[0-9a-f]{64}$'
        }
    }

    It 'accepts an added valid Skill from the source inventory' {
        $fixture = New-RepositoryFixture
        $newSkillId = Add-RepositorySkillFixture -Root $fixture
        $result = Invoke-CodeCollaborationCheck -Path $script:CheckPath -RepositoryRoot $fixture
        $result.result | Should -BeExactly 'passed'
        $result.activeSkillCount | Should -Be 3
        @($result.skills.skillId) | Should -Be @('orchestrate-ai-delivery', 'write-implementation-prompt', 'zz-added-skill')
        $added = @($result.skills | Where-Object { $_.skillId -ceq $newSkillId })[0]
        [string]$added.contentSha256 | Should -Match '^[0-9a-f]{64}$'
        @($added.files.path) | Should -Contain 'SKILL.md'
        @($added.files.path) | Should -Contain 'agents/openai.yaml'
    }

    It 'includes hidden package files in the content digest' {
        $fixture = New-RepositoryFixture
        $before = Invoke-CodeCollaborationCheck -Path $script:CheckPath -RepositoryRoot $fixture
        $hidden = Join-Path $fixture 'skills/write-implementation-prompt/.fixture-policy'
        [IO.File]::WriteAllText($hidden, 'hidden', [Text.UTF8Encoding]::new($false))
        $after = Invoke-CodeCollaborationCheck -Path $script:CheckPath -RepositoryRoot $fixture
        $beforeHash = @($before.skills | Where-Object skillId -CEQ 'write-implementation-prompt')[0].contentSha256
        $afterSkill = @($after.skills | Where-Object skillId -CEQ 'write-implementation-prompt')[0]
        $afterSkill.files.path | Should -Contain '.fixture-policy'
        $afterSkill.contentSha256 | Should -Not -BeExactly $beforeHash
    }

    It 'rejects a hidden entry beside canonical Skill packages' {
        $fixture = New-RepositoryFixture
        [void](New-Item -ItemType Directory -Path (Join-Path $fixture 'skills/.unexpected') -Force)
        { & $script:CheckPath -RepositoryRoot $fixture -ReadOnlySnapshot } | Should -Throw '*inventory does not exactly match*'
    }

    It 'rejects non-package content at the canonical source root' {
        $fixture = New-RepositoryFixture
        [IO.File]::WriteAllText((Join-Path $fixture 'skills/ignored.ps1'), 'Write-Output unsafe', [Text.UTF8Encoding]::new($false))
        { & $script:CheckPath -RepositoryRoot $fixture -ReadOnlySnapshot } | Should -Throw '*non-package or reparse entry*'
    }

    It 'rejects a second source root' {
        $fixture = New-RepositoryFixture
        [void](New-Item -ItemType Directory -Path (Join-Path $fixture '.agents/skills') -Force)
        { & $script:CheckPath -RepositoryRoot $fixture -ReadOnlySnapshot } | Should -Throw '*must not coexist*'
    }

    It 'rejects schema drift and unknown source fields' {
        $fixture = New-RepositoryFixture
        $path = Join-Path $fixture 'catalog/source.json'
        $source = Get-Content -Raw -LiteralPath $path | ConvertFrom-Json
        $source.schemaVersion = 1
        $source | Add-Member -NotePropertyName unexpected -NotePropertyValue $true
        Write-CodeCollaborationJson -Path $path -Value $source
        { & $script:CheckPath -RepositoryRoot $fixture -ReadOnlySnapshot } | Should -Throw '*invalid property set*'
    }

    It 'rejects duplicate JSON properties before object materialization' {
        $fixture = New-RepositoryFixture
        $path = Join-Path $fixture 'catalog/source.json'
        $text = Get-Content -Raw -LiteralPath $path
        $mutated = $text.Replace('"schemaVersion": 2,', '"schemaVersion": 2,"schemaVersion": 2,')
        $mutated | Should -Not -BeExactly $text
        [IO.File]::WriteAllText($path, $mutated, [Text.UTF8Encoding]::new($false))
        { & $script:CheckPath -RepositoryRoot $fixture -ReadOnlySnapshot } | Should -Throw '*duplicate JSON property*'
    }

    It 'rejects duplicate and unsorted Skill IDs' {
        $fixture = New-RepositoryFixture
        $path = Join-Path $fixture 'catalog/source.json'
        $source = Get-Content -Raw -LiteralPath $path | ConvertFrom-Json
        $source.skills = @('write-implementation-prompt', 'orchestrate-ai-delivery')
        Write-CodeCollaborationJson -Path $path -Value $source
        { & $script:CheckPath -RepositoryRoot $fixture -ReadOnlySnapshot } | Should -Throw '*ordinal ascending order*'

        $source.skills = @('orchestrate-ai-delivery', 'orchestrate-ai-delivery')
        Write-CodeCollaborationJson -Path $path -Value $source
        { & $script:CheckPath -RepositoryRoot $fixture -ReadOnlySnapshot } | Should -Throw '*Duplicate Skill ID*'
    }

    It 'rejects missing required Skill metadata' {
        $fixture = New-RepositoryFixture
        Remove-Item -LiteralPath (Join-Path $fixture 'skills/write-implementation-prompt/agents/openai.yaml')
        { & $script:CheckPath -RepositoryRoot $fixture -ReadOnlySnapshot } | Should -Throw '*is missing*'
    }

    It 'accepts optional license frontmatter and a normal blank line before the body' {
        $fixture = New-RepositoryFixture
        $path = Join-Path $fixture 'skills/write-implementation-prompt/SKILL.md'
        $text = Get-Content -Raw -LiteralPath $path
        $mutated = [regex]::Replace($text, '(?m)^---\r?\n<!--', "license: Apache-2.0`n---`n`n<!--", 1)
        $mutated | Should -Not -BeExactly $text
        [IO.File]::WriteAllText($path, $mutated, [Text.UTF8Encoding]::new($false))
        { & $script:CheckPath -RepositoryRoot $fixture -ReadOnlySnapshot } | Should -Not -Throw
    }

    It 'accepts supported OpenAI fields and rejects an unknown field' {
        $fixture = New-RepositoryFixture
        $path = Join-Path $fixture 'skills/write-implementation-prompt/agents/openai.yaml'
        $text = Get-Content -Raw -LiteralPath $path
        $needle = '  default_prompt: "Use $write-implementation-prompt to prepare a self-contained implementation prompt for the chosen executor."'
        $supported = $needle + "`n" + '  icon_small: "./assets/icon.svg"' + "`n" + '  brand_color: "#123456"'
        [IO.File]::WriteAllText($path, $text.Replace($needle, $supported), [Text.UTF8Encoding]::new($false))
        { & $script:CheckPath -RepositoryRoot $fixture -ReadOnlySnapshot } | Should -Not -Throw

        [IO.File]::WriteAllText($path, $text.Replace($needle, $needle + "`n" + '  unknown_field: "rejected"'), [Text.UTF8Encoding]::new($false))
        { & $script:CheckPath -RepositoryRoot $fixture -ReadOnlySnapshot } | Should -Throw '*unsupported or duplicate interface key*'
    }

    It 'rejects malformed OpenAI metadata lexical style' {
        $fixture = New-RepositoryFixture
        $path = Join-Path $fixture 'skills/write-implementation-prompt/agents/openai.yaml'
        $text = Get-Content -Raw -LiteralPath $path
        $mutated = $text.Replace('display_name: "Write Implementation Prompt"', '"display_name": "Write Implementation Prompt"')
        $mutated | Should -Not -BeExactly $text
        [IO.File]::WriteAllText($path, $mutated, [Text.UTF8Encoding]::new($false))
        { & $script:CheckPath -RepositoryRoot $fixture -ReadOnlySnapshot } | Should -Throw '*quoted mapping key*'
    }

    It 'rejects comments outside the SPDX license header' {
        $fixture = New-RepositoryFixture
        $path = Join-Path $fixture 'skills/write-implementation-prompt/agents/openai.yaml'
        [IO.File]::AppendAllText($path, "# unsupported comment`n", [Text.UTF8Encoding]::new($false))
        { & $script:CheckPath -RepositoryRoot $fixture -ReadOnlySnapshot } | Should -Throw '*unsupported or malformed syntax*'
    }

    It 'rejects an empty Skill body' {
        $fixture = New-RepositoryFixture
        $path = Join-Path $fixture 'skills/write-implementation-prompt/SKILL.md'
        $text = Get-Content -Raw -LiteralPath $path
        $frontmatter = [regex]::Match($text.Replace("`r`n", "`n"), '(?s)\A---\n.*?\n---\n').Value
        [IO.File]::WriteAllText($path, $frontmatter, [Text.UTF8Encoding]::new($false))
        { & $script:CheckPath -RepositoryRoot $fixture -ReadOnlySnapshot } | Should -Throw '*non-empty Markdown body*'
    }
}
