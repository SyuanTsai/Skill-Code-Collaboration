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
        $newSkill.profiles = @()
        $catalog.skills = @($catalog.skills + $newSkill | Sort-Object -Property id)
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
        { & $script:CatalogValidatorPath -RepositoryRoot $script:FixtureRoot -OutputPath (Join-Path $script:FixtureRoot ("artifacts/{0}.json" -f [guid]::NewGuid().ToString('N'))) } | Should -Not -Throw
    }

    It 'accepts a newly declared safe Skill and its metadata' {
        # Scenario: a new valid package is added to source inventory and a profile.
        # Purpose: prove future Skills are automatically covered without adding a new hard-coded gate.
        & $script:AddSafeCatalogSkillFixture -Root $script:FixtureRoot
        { & $script:CatalogValidatorPath -RepositoryRoot $script:FixtureRoot -OutputPath (Join-Path $script:FixtureRoot ("artifacts/{0}.json" -f [guid]::NewGuid().ToString('N'))) } | Should -Not -Throw
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

    It 'uses ordinal sorting for the filesystem Skill inventory' {
        # Scenario: valid Skill IDs differ under culture-sensitive and ordinal sorting.
        # Purpose: keep filesystem discovery aligned with the canonical source inventory contract.
        $validator = Get-Content -LiteralPath $script:CatalogValidatorPath -Raw
        $validator | Should -Match '\[Array\]::Sort\(\$actualSkillIds, \[StringComparer\]::Ordinal\)'
        $validator | Should -Not -Match '\|\s*Sort-Object'
    }

    It 'rejects non-reciprocal profile membership' {
        # Scenario: a profile includes a Skill while that Skill omits the profile.
        # Purpose: keep profile.includes and Skill.profiles as one consistent membership relation.
        $catalogPath = Join-Path $script:FixtureRoot 'catalog/profiles.json'
        $catalog = Get-Content -LiteralPath $catalogPath -Raw | ConvertFrom-Json
        $catalog.skills[0].profiles = @()
        $catalog | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $catalogPath -Encoding utf8NoBOM
        { & $script:CatalogValidatorPath -RepositoryRoot $script:FixtureRoot -OutputPath (Join-Path $script:FixtureRoot ("artifacts/{0}.json" -f [guid]::NewGuid().ToString('N'))) } | Should -Throw '*profiles must include profile*'
    }

    It 'requires the established Copilot profile to remain opt-in' {
        # Scenario: a catalog changes the existing Copilot profile to default-on.
        # Purpose: prevent consumers from receiving the delegation Skill without explicit opt-in.
        $catalogPath = Join-Path $script:FixtureRoot 'catalog/profiles.json'
        $catalog = Get-Content -LiteralPath $catalogPath -Raw | ConvertFrom-Json
        $catalog.profiles[0].default = $true
        $catalog | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $catalogPath -Encoding utf8NoBOM
        { & $script:CatalogValidatorPath -RepositoryRoot $script:FixtureRoot -OutputPath (Join-Path $script:FixtureRoot ("artifacts/{0}.json" -f [guid]::NewGuid().ToString('N'))) } | Should -Throw '*Copilot profile must be opt-in*'
    }

    It 'requires the established Copilot profile identity' {
        # Scenario: a catalog renames the compatibility-sensitive Copilot profile.
        # Purpose: keep the documented opt-in profile available to existing consumers.
        $catalogPath = Join-Path $script:FixtureRoot 'catalog/profiles.json'
        $catalog = Get-Content -LiteralPath $catalogPath -Raw | ConvertFrom-Json
        $catalog.profiles[0].id = 'renamed-profile'
        $catalog | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $catalogPath -Encoding utf8NoBOM
        { & $script:CatalogValidatorPath -RepositoryRoot $script:FixtureRoot -OutputPath (Join-Path $script:FixtureRoot ("artifacts/{0}.json" -f [guid]::NewGuid().ToString('N'))) } | Should -Throw '*established copilot profile is required*'
    }

    It 'keeps the established Copilot profile restricted to its Skill' {
        # Scenario: a catalog adds another valid Skill to the compatibility-sensitive Copilot profile.
        # Purpose: preserve the documented exact opt-in membership instead of allowing containment-only drift.
        & $script:AddSafeCatalogSkillFixture -Root $script:FixtureRoot
        $catalogPath = Join-Path $script:FixtureRoot 'catalog/profiles.json'
        $catalog = Get-Content -LiteralPath $catalogPath -Raw | ConvertFrom-Json
        $profile = @($catalog.profiles | Where-Object id -eq 'copilot')[0]
        $profile.includes = @($profile.includes + 'safe-fixture-skill' | Sort-Object)
        $safeSkill = @($catalog.skills | Where-Object id -eq 'safe-fixture-skill')[0]
        $safeSkill.profiles = @('copilot')
        $catalog | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $catalogPath -Encoding utf8NoBOM
        { & $script:CatalogValidatorPath -RepositoryRoot $script:FixtureRoot -OutputPath (Join-Path $script:FixtureRoot ("artifacts/{0}.json" -f [guid]::NewGuid().ToString('N'))) } | Should -Throw '*select exactly the established Copilot Skill*'
    }

    It 'rejects a catalog whose Skill path has a case or identity drift' {
        # Scenario: catalog metadata points at a different or differently cased package path.
        # Purpose: keep stable Skill ID, source path, and filesystem identity exact.
        $catalogPath = Join-Path $script:FixtureRoot 'catalog/profiles.json'
        $catalog = Get-Content -LiteralPath $catalogPath -Raw | ConvertFrom-Json
        $catalog.skills[0].source.path = 'skills/Write-Copilot-Implementation-Prompt'
        $catalog | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $catalogPath -Encoding utf8NoBOM
        { & $script:CatalogValidatorPath -RepositoryRoot $script:FixtureRoot -OutputPath (Join-Path $script:FixtureRoot ("artifacts/{0}.json" -f [guid]::NewGuid().ToString('N'))) } | Should -Throw '*source path*'
    }

    It 'rejects duplicate catalog Skill IDs' {
        # Scenario: profile catalog repeats a Skill record with the same stable ID.
        # Purpose: prevent ambiguous metadata and receipt attribution.
        $catalogPath = Join-Path $script:FixtureRoot 'catalog/profiles.json'
        $catalog = Get-Content -LiteralPath $catalogPath -Raw | ConvertFrom-Json
        $catalog.skills = @($catalog.skills + $catalog.skills[0])
        $catalog | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $catalogPath -Encoding utf8NoBOM
        { & $script:CatalogValidatorPath -RepositoryRoot $script:FixtureRoot -OutputPath (Join-Path $script:FixtureRoot ("artifacts/{0}.json" -f [guid]::NewGuid().ToString('N'))) } | Should -Throw '*Skill IDs must be unique*'
    }

    It 'rejects a catalog that omits a source-inventory Skill' {
        # Scenario: source inventory declares a package that the profile catalog forgot to describe.
        # Purpose: keep catalog cardinality equal to the canonical source inventory.
        & $script:AddSafeCatalogSkillFixture -Root $script:FixtureRoot
        $catalogPath = Join-Path $script:FixtureRoot 'catalog/profiles.json'
        $catalog = Get-Content -LiteralPath $catalogPath -Raw | ConvertFrom-Json
        $catalog.skills = @($catalog.skills | Where-Object id -ne 'safe-fixture-skill')
        $catalog | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $catalogPath -Encoding utf8NoBOM
        { & $script:CatalogValidatorPath -RepositoryRoot $script:FixtureRoot -OutputPath (Join-Path $script:FixtureRoot ("artifacts/{0}.json" -f [guid]::NewGuid().ToString('N'))) } | Should -Throw '*exactly match source inventory*'
    }
}
