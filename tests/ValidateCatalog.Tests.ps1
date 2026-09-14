# SPDX-FileCopyrightText: 2026 SyuanTsai
# SPDX-License-Identifier: Apache-2.0
Describe 'Code Collaboration profile catalog contract' {
    BeforeAll {
        $script:RepositoryRoot = Split-Path -Parent $PSScriptRoot
        $script:CatalogValidatorPath = Join-Path $script:RepositoryRoot 'tests/validate-catalog.ps1'
        $script:SourceSkillId = 'write-copilot-implementation-prompt'
        $script:AddSafeCatalogSkillFixture = {
        param([Parameter(Mandatory = $true)][string] $Root)

        $newSkillId = 'safe-fixture-skill'
        $sourceSkillRoot = Join-Path $Root "skills/$($script:SourceSkillId)"
        $newSkillRoot = Join-Path $Root "skills/$newSkillId"
        Copy-Item -LiteralPath $sourceSkillRoot -Destination $newSkillRoot -Recurse
        foreach ($path in @('SKILL.md', 'agents/openai.yaml')) {
            $file = Join-Path $newSkillRoot $path
            $text = Get-Content -LiteralPath $file -Raw
            $text = $text.Replace($script:SourceSkillId, $newSkillId)
            Set-Content -LiteralPath $file -Value $text -Encoding utf8NoBOM -NoNewline
        }

        $sourcePath = Join-Path $Root 'catalog/source.json'
        $source = Get-Content -LiteralPath $sourcePath -Raw | ConvertFrom-Json
        $source.skills = @($source.skills + $newSkillId | Sort-Object)
        $source | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $sourcePath -Encoding utf8NoBOM

        $catalogPath = Join-Path $Root 'catalog/profiles.json'
        $catalog = Get-Content -LiteralPath $catalogPath -Raw | ConvertFrom-Json
        $existingSkill = @($catalog.skills | Where-Object id -eq $script:SourceSkillId)[0]
        $newSkill = $existingSkill | ConvertTo-Json -Depth 20 | ConvertFrom-Json
        $newSkill.id = $newSkillId
        $newSkill.source.path = "skills/$newSkillId"
        $catalog.skills = @($catalog.skills + $newSkill | Sort-Object -Property id)
        $profile = @($catalog.profiles | Where-Object id -eq 'copilot')[0]
        $profile.includes = @($profile.includes + $newSkillId | Sort-Object)
        $catalog | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $catalogPath -Encoding utf8NoBOM
        }
    }

    BeforeEach {
        $script:FixtureRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $script:FixtureRoot | Out-Null
        foreach ($directory in @('catalog', 'skills', 'docs')) {
            Copy-Item -LiteralPath (Join-Path $script:RepositoryRoot $directory) -Destination $script:FixtureRoot -Recurse
        }
        foreach ($file in @('VERSION', 'scripts/Get-SourcePin.ps1')) {
            $destination = Join-Path $script:FixtureRoot $file
            New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
            Copy-Item -LiteralPath (Join-Path $script:RepositoryRoot $file) -Destination $destination
        }
    }

    It 'accepts the current source and profile catalog' {
        # Scenario: the checked-in catalog and all current packages are internally consistent.
        # Purpose: establish the valid baseline for the canonical Repository Tests child.
        { & $script:CatalogValidatorPath -RepositoryRoot $script:FixtureRoot } | Should -Not -Throw
    }

    It 'accepts a newly declared safe Skill and its metadata' {
        # Scenario: a new valid package is added to source inventory and a profile.
        # Purpose: prove future Skills are automatically covered without adding a new hard-coded gate.
        & $script:AddSafeCatalogSkillFixture -Root $script:FixtureRoot
        { & $script:CatalogValidatorPath -RepositoryRoot $script:FixtureRoot } | Should -Not -Throw
    }

    It 'keeps output-path execution JSON-only for the central runner' {
        # Scenario: the central Repository Tests adapter requests a file report from the catalog validator.
        # Purpose: prevent a second stdout JSON document from corrupting the child-runner envelope.
        $outputPath = Join-Path $script:FixtureRoot 'artifacts/catalog-report.json'
        $stdout = @(& $script:CatalogValidatorPath -RepositoryRoot $script:FixtureRoot -OutputPath $outputPath)
        $stdout | Should -BeNullOrEmpty
        Test-Path -LiteralPath $outputPath -PathType Leaf | Should -BeTrue
        { Get-Content -LiteralPath $outputPath -Raw | ConvertFrom-Json } | Should -Not -Throw
    }

    It 'rejects a catalog whose Skill path has a case or identity drift' {
        # Scenario: catalog metadata points at a different or differently cased package path.
        # Purpose: keep stable Skill ID, source path, and filesystem identity exact.
        $catalogPath = Join-Path $script:FixtureRoot 'catalog/profiles.json'
        $catalog = Get-Content -LiteralPath $catalogPath -Raw | ConvertFrom-Json
        $catalog.skills[0].source.path = 'skills/Write-Copilot-Implementation-Prompt'
        $catalog | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $catalogPath -Encoding utf8NoBOM
        { & $script:CatalogValidatorPath -RepositoryRoot $script:FixtureRoot } | Should -Throw '*source path*'
    }

    It 'rejects duplicate catalog Skill IDs' {
        # Scenario: profile catalog repeats a Skill record with the same stable ID.
        # Purpose: prevent ambiguous metadata and receipt attribution.
        $catalogPath = Join-Path $script:FixtureRoot 'catalog/profiles.json'
        $catalog = Get-Content -LiteralPath $catalogPath -Raw | ConvertFrom-Json
        $catalog.skills = @($catalog.skills + $catalog.skills[0])
        $catalog | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $catalogPath -Encoding utf8NoBOM
        { & $script:CatalogValidatorPath -RepositoryRoot $script:FixtureRoot } | Should -Throw '*Skill IDs must be unique*'
    }

    It 'rejects a catalog that omits a source-inventory Skill' {
        # Scenario: source inventory declares a package that the profile catalog forgot to describe.
        # Purpose: keep catalog cardinality equal to the canonical source inventory.
        & $script:AddSafeCatalogSkillFixture -Root $script:FixtureRoot
        $catalogPath = Join-Path $script:FixtureRoot 'catalog/profiles.json'
        $catalog = Get-Content -LiteralPath $catalogPath -Raw | ConvertFrom-Json
        $catalog.skills = @($catalog.skills | Where-Object id -ne 'safe-fixture-skill')
        $catalog | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $catalogPath -Encoding utf8NoBOM
        { & $script:CatalogValidatorPath -RepositoryRoot $script:FixtureRoot } | Should -Throw '*exactly match source inventory*'
    }
}
