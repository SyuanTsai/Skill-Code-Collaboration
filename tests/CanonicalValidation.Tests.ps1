# SPDX-FileCopyrightText: 2026 SyuanTsai
# SPDX-License-Identifier: Apache-2.0
$ErrorActionPreference = 'Stop'

BeforeAll {
    $script:RepositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
    $script:PinPath = Join-Path $script:RepositoryRoot 'config/authority-pin.json'
    $script:GatePath = Join-Path $script:RepositoryRoot 'config/consumer-gate.json'
}

Describe 'Canonical consumer gate configuration' {
    It 'validates the canonical authority pin contract' {
        $pin = Get-Content -Raw -LiteralPath $script:PinPath | ConvertFrom-Json
        @($pin.PSObject.Properties.Name) | Should -Be @('schemaVersion', 'repository', 'commit')
        $pin.schemaVersion | Should -Be 1
        $pin.repository | Should -BeExactly 'https://github.com/SyuanTsai/SyuanTsai-AI-Instructions.git'
        $pin.commit -is [string] | Should -BeTrue
        [regex]::IsMatch([string]$pin.commit, '^[0-9a-f]{40}$') | Should -BeTrue
    }

    It 'declares only consumer identity active Skills and repository checks' {
        $gate = Get-Content -Raw -LiteralPath $script:GatePath | ConvertFrom-Json -Depth 20
        @($gate.PSObject.Properties.Name) | Should -Be @('schemaVersion', 'repositoryId', 'sourceRepository', 'activeSkills', 'repositoryChecks')
        $gate.schemaVersion | Should -Be 1
        $gate.repositoryId | Should -BeExactly 'skill-code-collaboration'
        $gate.sourceRepository | Should -BeExactly 'https://github.com/SyuanTsai/Skill-Code-Collaboration.git'
        $gate.PSObject.Properties.Name | Should -Not -Contain 'requiredRepositoryChecks'
    }

    It 'keeps active Skills identical to the source inventory' {
        $gate = Get-Content -Raw -LiteralPath $script:GatePath | ConvertFrom-Json -Depth 20
        $source = Get-Content -Raw -LiteralPath (Join-Path $script:RepositoryRoot 'catalog/source.json') | ConvertFrom-Json
        (@($gate.activeSkills) -join "`n") | Should -BeExactly (@($source.skills) -join "`n")
    }

    It 'declares the exact repository check set and every path exists' {
        $gate = Get-Content -Raw -LiteralPath $script:GatePath | ConvertFrom-Json -Depth 20
        $expected = @(
            'repository-code-collaboration|general|scripts/Test-CodeCollaborationRepository.ps1'
            'repository-catalog|general|scripts/Test-CodeCollaborationCatalog.ps1'
            'repository-pester|pester|tests'
        )
        $actual = @($gate.repositoryChecks | ForEach-Object { '{0}|{1}|{2}' -f $_.id, $_.kind, $_.path })
        ($actual -join "`n") | Should -BeExactly ($expected -join "`n")
        foreach ($check in @($gate.repositoryChecks)) {
            Test-Path -LiteralPath (Join-Path $script:RepositoryRoot ([string]$check.path)) | Should -BeTrue
        }
    }

    It 'keeps all authority templates at the reviewed byte identities' {
        $expected = [ordered]@{
            'scripts/Invoke-PinnedAuthority.ps1' = '4bde1cf7ca72a1a65ddc2ea30799daa3ff26deb69361406a38e1c9d4a7ae9835'
            '.github/workflows/consumer-gate.yml' = 'e67b40ac2b18f6d13aab573a17b8a55eed74df9ed41721f710bfb46a52881519'
        }
        foreach ($entry in $expected.GetEnumerator()) {
            $actual = (Get-FileHash -LiteralPath (Join-Path $script:RepositoryRoot $entry.Key) -Algorithm SHA256).Hash.ToLowerInvariant()
            $actual | Should -BeExactly $entry.Value
        }

        $transitionPath = Join-Path $script:RepositoryRoot '.github/workflows/consumer-gate-transition.yml'
        if (Test-Path -LiteralPath $transitionPath -PathType Leaf) {
            $actual = (Get-FileHash -LiteralPath $transitionPath -Algorithm SHA256).Hash.ToLowerInvariant()
            $actual | Should -BeExactly '61032baf65fd52829e327470253df22d9a832986c6efdbfb3da9d8f7bba4ffac'
        }
    }
}
