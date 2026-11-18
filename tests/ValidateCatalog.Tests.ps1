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
