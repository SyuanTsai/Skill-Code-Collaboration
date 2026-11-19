# SPDX-FileCopyrightText: 2026 SyuanTsai
# SPDX-License-Identifier: Apache-2.0
$ErrorActionPreference = 'Stop'

BeforeAll {
    . (Join-Path $PSScriptRoot 'ResolveLegacyAuthorityArchiveFixture.ps1')
    $script:RepositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
    $script:CheckPath = Join-Path $script:RepositoryRoot 'scripts/Test-CodeCollaborationCatalog.ps1'

    function New-CatalogFixture {
        $root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        Copy-CodeCollaborationFixture -RepositoryRoot $script:RepositoryRoot -DestinationRoot $root
    }

    function Add-CatalogSkillFixture {
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

Describe 'Code Collaboration catalog check' {
    It 'accepts the current source and profile catalog in a read-only snapshot' {
        $fixture = New-CatalogFixture
        $result = Invoke-CodeCollaborationCheck -Path $script:CheckPath -RepositoryRoot $fixture
        $result.result | Should -BeExactly 'passed'
        $result.catalogId | Should -BeExactly 'code-collaboration'
        @($result.skills.skillId) | Should -Be @('orchestrate-ai-delivery', 'write-implementation-prompt')
    }

    It 'does not write to the candidate snapshot' {
        $fixture = New-CatalogFixture
        $before = Get-CodeCollaborationTreeDigest -Root $fixture
        $null = Invoke-CodeCollaborationCheck -Path $script:CheckPath -RepositoryRoot $fixture
        $after = Get-CodeCollaborationTreeDigest -Root $fixture
        $after | Should -BeExactly $before
    }

    It 'accepts an added valid Skill across the catalog inventory' {
        $fixture = New-CatalogFixture
        $newSkillId = Add-CatalogSkillFixture -Root $fixture
        $result = Invoke-CodeCollaborationCheck -Path $script:CheckPath -RepositoryRoot $fixture
        $result.result | Should -BeExactly 'passed'
        $result.activeSkillCount | Should -Be 3
        @($result.skills.skillId) | Should -Be @('orchestrate-ai-delivery', 'write-implementation-prompt', 'zz-added-skill')
        $added = @($result.skills | Where-Object { $_.skillId -ceq $newSkillId })[0]
        $added.sourcePath | Should -BeExactly 'skills/zz-added-skill'
        @($result.profiles[0].includes) | Should -Contain $newSkillId
    }

    It 'uses ordinal sorting for the filesystem Skill inventory' {
        $fixture = New-CatalogFixture
        [void](New-Item -ItemType Directory -Path (Join-Path $fixture 'skills/.hidden-package') -Force)
        { & $script:CheckPath -RepositoryRoot $fixture -ReadOnlySnapshot } | Should -Throw '*directories must exactly match*'
    }

    It 'rejects non-reciprocal profile membership' {
        $fixture = New-CatalogFixture
        $path = Join-Path $fixture 'catalog/profiles.json'
        $catalog = Get-Content -Raw -LiteralPath $path | ConvertFrom-Json -Depth 30
        $catalog.skills[0].profiles = @()
        Write-CodeCollaborationJson -Path $path -Value $catalog
        { & $script:CheckPath -RepositoryRoot $fixture -ReadOnlySnapshot } | Should -Throw '*profiles must include profile*'
    }

    It 'rejects a catalog whose Skill path has case or identity drift' {
        $fixture = New-CatalogFixture
        $path = Join-Path $fixture 'catalog/profiles.json'
        $catalog = Get-Content -Raw -LiteralPath $path | ConvertFrom-Json -Depth 30
        $catalog.skills[0].source.path = 'skills/Orchestrate-AI-Delivery'
        Write-CodeCollaborationJson -Path $path -Value $catalog
        { & $script:CheckPath -RepositoryRoot $fixture -ReadOnlySnapshot } | Should -Throw '*source path must exactly match*'
    }

    It 'rejects duplicate catalog Skill IDs' {
        $fixture = New-CatalogFixture
        $path = Join-Path $fixture 'catalog/profiles.json'
        $catalog = Get-Content -Raw -LiteralPath $path | ConvertFrom-Json -Depth 30
        $catalog.skills = @($catalog.skills) + @($catalog.skills[0])
        Write-CodeCollaborationJson -Path $path -Value $catalog
        { & $script:CheckPath -RepositoryRoot $fixture -ReadOnlySnapshot } | Should -Throw '*Skill IDs must be unique*'
    }

    It 'rejects a catalog that omits a source-inventory Skill' {
        $fixture = New-CatalogFixture
        $path = Join-Path $fixture 'catalog/profiles.json'
        $catalog = Get-Content -Raw -LiteralPath $path | ConvertFrom-Json -Depth 30
        $catalog.skills = @($catalog.skills[0])
        Write-CodeCollaborationJson -Path $path -Value $catalog
        { & $script:CheckPath -RepositoryRoot $fixture -ReadOnlySnapshot } | Should -Throw '*count must exactly match*'
    }

    It 'rejects a profile that references an unknown Skill' {
        $fixture = New-CatalogFixture
        $path = Join-Path $fixture 'catalog/profiles.json'
        $catalog = Get-Content -Raw -LiteralPath $path | ConvertFrom-Json -Depth 30
        $catalog.profiles[0].includes = @($catalog.profiles[0].includes) + @('unknown-skill')
        Write-CodeCollaborationJson -Path $path -Value $catalog
        { & $script:CheckPath -RepositoryRoot $fixture -ReadOnlySnapshot } | Should -Throw '*references unknown Skill*'
    }

    It 'rejects duplicate source Skill IDs' {
        $fixture = New-CatalogFixture
        $path = Join-Path $fixture 'catalog/source.json'
        $source = Get-Content -Raw -LiteralPath $path | ConvertFrom-Json
        $source.skills = @('orchestrate-ai-delivery', 'orchestrate-ai-delivery')
        Write-CodeCollaborationJson -Path $path -Value $source
        { & $script:CheckPath -RepositoryRoot $fixture -ReadOnlySnapshot } | Should -Throw '*duplicate Skill ID*'
    }

    It 'rejects missing catalog documentation' {
        $fixture = New-CatalogFixture
        Remove-Item -LiteralPath (Join-Path $fixture 'docs/RELEASE.md')
        { & $script:CheckPath -RepositoryRoot $fixture -ReadOnlySnapshot } | Should -Throw '*Release documentation is missing*'
    }
}
