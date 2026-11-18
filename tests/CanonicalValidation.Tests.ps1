# SPDX-FileCopyrightText: 2026 SyuanTsai
# SPDX-License-Identifier: Apache-2.0
$ErrorActionPreference = 'Stop'

BeforeAll {
    $script:RepositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
    $script:PinPath = Join-Path $script:RepositoryRoot 'config/authority-pin.json'
    $script:GatePath = Join-Path $script:RepositoryRoot 'config/consumer-gate.json'
}

Describe 'Canonical consumer gate configuration' {
    It 'pins the exact approved authority commit' {
        $pin = Get-Content -Raw -LiteralPath $script:PinPath | ConvertFrom-Json
        @($pin.PSObject.Properties.Name) | Should -Be @('schemaVersion', 'repository', 'commit')
        $pin.schemaVersion | Should -Be 1
        $pin.repository | Should -BeExactly 'https://github.com/SyuanTsai/SyuanTsai-AI-Instructions.git'
        $pin.commit | Should -BeExactly '43239581cbf1d0fc6a9d6d82766375a0db72d228'
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
            'scripts/Invoke-PinnedAuthority.ps1' = '2b2941066308b689140bdbd57654b5347f39933e3c91c6097ce4646709a3e76b'
            '.github/workflows/consumer-gate.yml' = 'dffbac5117290e8ca4fd1c1179355a9bae59bcc3496ce3e9413e813f88da19d5'
            '.github/workflows/consumer-gate-transition.yml' = '6c78b69f413f9878d9dd73ad42b7bbe5b4442b82617649122e8e8c9bc992132f'
        }
        foreach ($entry in $expected.GetEnumerator()) {
            $actual = (Get-FileHash -LiteralPath (Join-Path $script:RepositoryRoot $entry.Key) -Algorithm SHA256).Hash.ToLowerInvariant()
            $actual | Should -BeExactly $entry.Value
        }
    }
}
