# SPDX-FileCopyrightText: 2026 SyuanTsai
# SPDX-License-Identifier: Apache-2.0
$ErrorActionPreference = 'Stop'

BeforeAll {
    $script:RepositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
    $script:PermanentWorkflow = Join-Path $script:RepositoryRoot '.github/workflows/consumer-gate.yml'
    $script:TransitionWorkflow = Join-Path $script:RepositoryRoot '.github/workflows/consumer-gate-transition.yml'

    function Assert-UnambiguousJson {
        param([Parameter(Mandatory)][string] $Path)

        $bytes = [IO.File]::ReadAllBytes($Path)
        if ($bytes.Length -ge 3 -and $bytes[0] -eq 239 -and $bytes[1] -eq 187 -and $bytes[2] -eq 191) { throw 'JSON has a BOM.' }
        $text = [Text.UTF8Encoding]::new($false, $true).GetString($bytes)
        if (-not $text.EndsWith("`n", [StringComparison]::Ordinal) -or $text.Contains("`r", [StringComparison]::Ordinal)) {
            throw 'JSON must use LF and a final newline.'
        }
        $document = [Text.Json.JsonDocument]::Parse($text)
        try {
            $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
            foreach ($property in $document.RootElement.EnumerateObject()) {
                if (-not $seen.Add($property.Name)) { throw 'JSON has duplicate top-level keys.' }
            }
        }
        finally { $document.Dispose() }
    }
}

Describe 'Consumer gate adoption contract' {
    It 'keeps both consumer JSON files unambiguous UTF-8 with LF endings' {
        foreach ($relative in @('config/authority-pin.json', 'config/consumer-gate.json')) {
            { Assert-UnambiguousJson -Path (Join-Path $script:RepositoryRoot $relative) } | Should -Not -Throw
        }
    }

    It 'runs the permanent workflow on all three platforms' {
        $text = Get-Content -Raw -LiteralPath $script:PermanentWorkflow
        foreach ($runner in @('windows-latest', 'ubuntu-latest', 'macos-latest')) {
            $text.Contains($runner, [StringComparison]::Ordinal) | Should -BeTrue
        }
        $text.Contains('scripts/Invoke-PinnedAuthority.ps1', [StringComparison]::Ordinal) | Should -BeTrue
    }

    It 'runs the transition workflow on all three platforms with transition mode' {
        $text = Get-Content -Raw -LiteralPath $script:TransitionWorkflow
        foreach ($runner in @('windows-latest', 'ubuntu-latest', 'macos-latest')) {
            $text.Contains($runner, [StringComparison]::Ordinal) | Should -BeTrue
        }
        $text.Contains('-TransitionFromLegacy', [StringComparison]::Ordinal) | Should -BeTrue
    }

    It 'keeps the permanent workflow independent of transition mode' {
        $text = Get-Content -Raw -LiteralPath $script:PermanentWorkflow
        $text.Contains('-TransitionFromLegacy', [StringComparison]::Ordinal) | Should -BeFalse
    }

    It 'keeps the bootstrap parameter contract portable across gate platforms' {
        $path = Join-Path $script:RepositoryRoot 'scripts/Invoke-PinnedAuthority.ps1'
        $tokens = $null
        $errors = $null
        $ast = [Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errors)
        @($errors) | Should -HaveCount 0
        $parameters = @($ast.ParamBlock.Parameters.Name.VariablePath.UserPath)
        $parameters | Should -Contain 'Platform'
        $parameters | Should -Contain 'TransitionFromLegacy'
        $parameters | Should -Contain 'CandidateRoot'
    }

    It 'allows cleanup to remove only the transition workflow' {
        $fixture = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        [void](New-Item -ItemType Directory -Path $fixture -Force)
        Copy-Item -LiteralPath $script:PermanentWorkflow -Destination (Join-Path $fixture 'consumer-gate.yml')
        Copy-Item -LiteralPath $script:TransitionWorkflow -Destination (Join-Path $fixture 'consumer-gate-transition.yml')
        Remove-Item -LiteralPath (Join-Path $fixture 'consumer-gate-transition.yml')
        [string[]]$remaining = @(Get-ChildItem -LiteralPath $fixture -File -Force | ForEach-Object Name)
        $remaining | Should -Be @('consumer-gate.yml')
    }
}
