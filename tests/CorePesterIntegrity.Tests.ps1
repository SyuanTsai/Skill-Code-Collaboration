# SPDX-FileCopyrightText: 2026 SyuanTsai
# SPDX-License-Identifier: Apache-2.0
$ErrorActionPreference = 'Stop'

BeforeAll {
    $script:RepositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))

    function Assert-ConsumerWorkflowLayout {
        param([Parameter(Mandatory)][string] $WorkflowDirectory)

        [string[]]$actual = @(Get-ChildItem -LiteralPath $WorkflowDirectory -File -Force | ForEach-Object Name)
        [string[]]$permanent = @('consumer-gate.yml')
        [string[]]$conversion = @('consumer-gate-transition.yml', 'consumer-gate.yml')
        [Array]::Sort($actual, [StringComparer]::Ordinal)
        [Array]::Sort($conversion, [StringComparer]::Ordinal)
        $actualText = $actual -join "`n"
        if ($actualText -cne ($permanent -join "`n") -and $actualText -cne ($conversion -join "`n")) {
            throw 'The workflow directory contains an unsupported file set.'
        }
    }

    function Get-ReuseAnnotationPatterns {
        param([Parameter(Mandatory)][string] $Path)

        $patterns = [Collections.Generic.List[string]]::new()
        $current = $null
        foreach ($line in Get-Content -LiteralPath $Path -Encoding utf8) {
            if ($line -ceq '[[annotations]]') {
                if ($null -ne $current) { $patterns.Add($current) }
                $current = $null
                continue
            }
            if ($line -cmatch '^path = "(?<Path>[^"]+)"$') { $current = [string]$Matches.Path }
        }
        if ($null -ne $current) { $patterns.Add($current) }
        @($patterns)
    }

    function Get-RepositoryRelativeFiles {
        param([Parameter(Mandatory)][string] $Root)

        @(Get-ChildItem -LiteralPath $Root -Recurse -File -Force | ForEach-Object {
                $relative = [IO.Path]::GetRelativePath($Root, $_.FullName).Replace([IO.Path]::DirectorySeparatorChar, '/')
                if (-not $relative.StartsWith('.git/', [StringComparison]::Ordinal)) { $relative }
            })
    }
}

Describe 'Consumer repository protected layout' {
    It 'contains only the bootstrap and two repository checks under scripts' {
        [string[]]$actual = @(Get-ChildItem -LiteralPath (Join-Path $script:RepositoryRoot 'scripts') -File -Force | ForEach-Object Name)
        [string[]]$expected = @('Invoke-PinnedAuthority.ps1', 'Test-CodeCollaborationCatalog.ps1', 'Test-CodeCollaborationRepository.ps1')
        [Array]::Sort($actual, [StringComparer]::Ordinal)
        [Array]::Sort($expected, [StringComparer]::Ordinal)
        ($actual -join "`n") | Should -BeExactly ($expected -join "`n")
    }

    It 'contains only consumer configuration files' {
        [string[]]$actual = @(Get-ChildItem -LiteralPath (Join-Path $script:RepositoryRoot 'config') -File -Force | ForEach-Object Name)
        [string[]]$expected = @('authority-pin.json', 'consumer-gate.json')
        [Array]::Sort($actual, [StringComparer]::Ordinal)
        [Array]::Sort($expected, [StringComparer]::Ordinal)
        ($actual -join "`n") | Should -BeExactly ($expected -join "`n")
    }

    It 'accepts the conversion workflow set' {
        { Assert-ConsumerWorkflowLayout -WorkflowDirectory (Join-Path $script:RepositoryRoot '.github/workflows') } | Should -Not -Throw
    }

    It 'accepts the permanent workflow without the transition workflow' {
        $fixture = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        [void](New-Item -ItemType Directory -Path $fixture -Force)
        [IO.File]::WriteAllText((Join-Path $fixture 'consumer-gate.yml'), 'fixture', [Text.UTF8Encoding]::new($false))
        { Assert-ConsumerWorkflowLayout -WorkflowDirectory $fixture } | Should -Not -Throw
    }

    It 'rejects a third workflow including a hidden entry' {
        $fixture = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        [void](New-Item -ItemType Directory -Path $fixture -Force)
        [IO.File]::WriteAllText((Join-Path $fixture 'consumer-gate.yml'), 'fixture', [Text.UTF8Encoding]::new($false))
        [IO.File]::WriteAllText((Join-Path $fixture '.third.yml'), 'fixture', [Text.UTF8Encoding]::new($false))
        { Assert-ConsumerWorkflowLayout -WorkflowDirectory $fixture } | Should -Throw '*unsupported file set*'
    }

    It 'keeps every REUSE annotation matched by at least one present file' {
        $patterns = @(Get-ReuseAnnotationPatterns -Path (Join-Path $script:RepositoryRoot 'REUSE.toml'))
        $patterns.Count | Should -BeGreaterThan 0
        $files = @(Get-RepositoryRelativeFiles -Root $script:RepositoryRoot)
        foreach ($value in $patterns) {
            $pattern = [Management.Automation.WildcardPattern]::new($value, [Management.Automation.WildcardOptions]::CultureInvariant)
            @($files | Where-Object { $pattern.IsMatch($_) }).Count | Should -BeGreaterThan 0
        }
    }

    It 'uses one wildcard annotation for both workflow states' {
        $patterns = @(Get-ReuseAnnotationPatterns -Path (Join-Path $script:RepositoryRoot 'REUSE.toml'))
        @($patterns | Where-Object { $_ -ceq '.github/workflows/consumer-gate*.yml' }) | Should -HaveCount 1
    }
}
