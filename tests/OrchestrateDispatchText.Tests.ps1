# SPDX-FileCopyrightText: 2026 SyuanTsai
# SPDX-License-Identifier: Apache-2.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'orchestrate-ai-delivery pre-send text check' {
    BeforeAll {
        $script:ScriptPath = Join-Path (Split-Path -Parent $PSScriptRoot) `
            'skills/orchestrate-ai-delivery/scripts/Test-DispatchText.ps1'
    }

    It 'accepts repository-relative paths, URLs, and placeholders' {
        $text = 'skills/orchestrate-ai-delivery/SKILL.md https://example.com/a ssh://host <worktree> /Users/<name> /home/<name> Step C: do it ~/.codex/config.toml'
        $findings = @(& $script:ScriptPath -Text $text -NoEnvironmentTerm 6>$null)
        $LASTEXITCODE | Should -Be 0
        $findings.Count | Should -Be 0
    }

    It 'reports the line and column of a Windows drive path' {
        $findings = @(& $script:ScriptPath -Text "Review this`r`nUse C:\repo\a.ps1" -NoEnvironmentTerm 6>$null)
        $LASTEXITCODE | Should -Be 1
        $findings.Count | Should -Be 1
        $findings[0].Source | Should -BeExactly '<text>'
        $findings[0].Line | Should -Be 2
        $findings[0].Column | Should -Be 5
        $findings[0].Kind | Should -BeExactly 'windows-drive-path'
    }

    It 'detects the Windows drive form <Form>' -ForEach @(
        @{ Form = 'forward slash'; Text = 'd:/work/x' }
        @{ Form = 'file URI'; Text = 'file:///C:/x' }
        @{ Form = 'JSON escaping'; Text = 'C:\\Users\\x' }
    ) {
        $findings = @(& $script:ScriptPath -Text $Text -NoEnvironmentTerm 6>$null)
        $LASTEXITCODE | Should -Be 1
        $findings.Count | Should -Be 1
        $findings[0].Kind | Should -BeExactly 'windows-drive-path'
    }

    It 'detects the POSIX home form <Form>' -ForEach @(
        @{ Form = 'Users'; Text = '/Users/alice/x' }
        @{ Form = 'home'; Text = '/home/bob' }
        @{ Form = 'root'; Text = '/root/.ssh' }
    ) {
        $findings = @(& $script:ScriptPath -Text $Text -NoEnvironmentTerm 6>$null)
        $LASTEXITCODE | Should -Be 1
        $findings.Count | Should -Be 1
        $findings[0].Kind | Should -BeExactly 'posix-home-path'
    }

    It 'does not report <Name> as a UNC path' -ForEach @(
        @{ Name = 'escaped digit pattern'; Text = '"pattern": "\\d+\\.\\d+"' }
        @{ Name = 'escaped word and space classes'; Text = 'Use regex \\w+\\s+ here' }
        @{ Name = 'escaped newline and tab'; Text = '"msg": "a\\nb\\tc"' }
        @{ Name = 'escaped word boundary'; Text = 'grep -E "\\bfoo\\b"' }
    ) {
        $findings = @(& $script:ScriptPath -Text $Text -NoEnvironmentTerm 6>$null)
        $LASTEXITCODE | Should -Be 0
        $findings.Count | Should -Be 0
    }
    It 'detects a UNC path' {
        $findings = @(& $script:ScriptPath -Text '\\server\share\x' -NoEnvironmentTerm 6>$null)
        $LASTEXITCODE | Should -Be 1
        $findings.Count | Should -Be 1
        $findings[0].Kind | Should -BeExactly 'unc-path'
    }

    It 'detects a JSON-escaped UNC path' {
        $findings = @(& $script:ScriptPath -Text '"path": "\\\\build-server\\shared\\project"' -NoEnvironmentTerm 6>$null)
        $LASTEXITCODE | Should -Be 1
        $findings.Count | Should -Be 1
        $findings[0].Kind | Should -BeExactly 'unc-path'
    }

    It 'requires the specified prefixes to start at a path boundary' {
        $findings = @(& $script:ScriptPath -Text 'abc:/x 2c:/x +c:/x .c:/x -c:/x \\\server\share a/home/bob ~/root/.ssh' -NoEnvironmentTerm 6>$null)
        $LASTEXITCODE | Should -Be 0
        $findings.Count | Should -Be 0
    }

    It 'matches a forbidden term regardless of case and only at letter or digit boundaries' {
        $findings = @(& $script:ScriptPath -Text 'Alice wrote this' -ForbiddenTerm alice -NoEnvironmentTerm 6>$null)
        $LASTEXITCODE | Should -Be 1
        $findings.Count | Should -Be 1
        $findings[0].Kind | Should -BeExactly 'forbidden-term'

        $findings = @(& $script:ScriptPath -Text 'malice alice2' -ForbiddenTerm alice -NoEnvironmentTerm 6>$null)
        $LASTEXITCODE | Should -Be 0
        $findings.Count | Should -Be 0
    }

    It 'splits comma-joined forbidden terms' {
        $findings = @(& $script:ScriptPath -Text 'Alice and Bob wrote this' -ForbiddenTerm 'alice,bob' -NoEnvironmentTerm 6>$null)
        $LASTEXITCODE | Should -Be 1
        $findings.Count | Should -Be 2
        @($findings | Where-Object Kind -eq 'forbidden-term').Count | Should -Be 2
    }

    It 'splits comma-joined forbidden terms when invoked with pwsh -File' {
        $file = Join-Path $TestDrive 'names.txt'
        Set-Content -LiteralPath $file -Value 'Alice and Bob wrote this'
        $output = & (Get-Process -Id $PID).Path -NoProfile -File $script:ScriptPath -Path $file -ForbiddenTerm alice,bob -NoEnvironmentTerm *>&1 | Out-String
        $LASTEXITCODE | Should -Be 1
        $output | Should -Match '2 finding\(s\)'
    }

    It 'allows an exact example and still flags another path on the same line' {
        $findings = @(& $script:ScriptPath -Text 'C:\example\a and D:\other' -AllowLiteral 'C:\example' -NoEnvironmentTerm 6>$null)
        $LASTEXITCODE | Should -Be 1
        $findings.Count | Should -Be 1
        $findings[0].Kind | Should -BeExactly 'windows-drive-path'
        $findings[0].Column | Should -Be 18
    }

    It 'requires a case-sensitive allow literal covering the whole match' {
        $findings = @(& $script:ScriptPath -Text 'alice Alice' -ForbiddenTerm alice -AllowLiteral 'Alice', 'ali' -NoEnvironmentTerm 6>$null)
        $LASTEXITCODE | Should -Be 1
        $findings.Count | Should -Be 1
        $findings[0].Column | Should -Be 1
    }

    It 'returns only safe finding properties in the specified order' {
        $findings = @(& $script:ScriptPath -Text 'alice at C:\repo' -ForbiddenTerm alice -NoEnvironmentTerm 6>$null)
        $LASTEXITCODE | Should -Be 1
        $findings.Count | Should -Be 2
        foreach ($finding in $findings) {
            ($finding.PSObject.Properties.Name -join ',') | Should -BeExactly 'Source,Line,Column,Kind'
            foreach ($property in $finding.PSObject.Properties) {
                [string]$property.Value | Should -Not -Match 'alice|C:\\repo'
            }
        }
    }

    It 'reads both UTF-8 files and preserves the source labels as passed' {
        $first = Join-Path $TestDrive 'prompt.txt'
        $second = Join-Path $TestDrive 'report.txt'
        Set-Content -LiteralPath $first -Value (([char]0x6E2C) + ' C:\repo') -Encoding UTF8
        Set-Content -LiteralPath $second -Value '/home/bob' -Encoding UTF8

        $findings = @(& $script:ScriptPath -Path $first, $second -NoEnvironmentTerm 6>$null)
        $LASTEXITCODE | Should -Be 1
        $findings.Count | Should -Be 2
        $findings[0].Source | Should -BeExactly $first
        $findings[0].Column | Should -Be 3
        $findings[1].Source | Should -BeExactly $second
    }

    It 'throws a terminating error naming a missing file as passed' {
        $missing = Join-Path $TestDrive 'missing.txt'
        { & $script:ScriptPath -Path $missing -NoEnvironmentTerm 6>$null } |
            Should -Throw "*$missing*"
    }

    It 'detects an environment term once and skips it with the switch' {
        $previousUser = $env:USER
        $previousUsername = $env:USERNAME
        try {
            $env:USER = 'zqxuser'
            $env:USERNAME = 'zqxuser'
            $findings = @(& $script:ScriptPath -Text 'owner zqxuser' 6>$null)
            $LASTEXITCODE | Should -Be 1
            $findings.Count | Should -Be 1
            $findings[0].Kind | Should -BeExactly 'environment-term'
            $findings[0].Column | Should -Be 7

            $findings = @(& $script:ScriptPath -Text 'owner zqxuser' -NoEnvironmentTerm 6>$null)
            $LASTEXITCODE | Should -Be 0
            $findings.Count | Should -Be 0
        }
        finally {
            $env:USER = $previousUser
            $env:USERNAME = $previousUsername
        }
    }

    It 'accepts pipeline input and retains the failure status across inputs' {
        $findings = @('C:\x', 'clean text' | & $script:ScriptPath -NoEnvironmentTerm 6>$null)
        $LASTEXITCODE | Should -Be 1
        $findings.Count | Should -Be 1
        $findings[0].Kind | Should -BeExactly 'windows-drive-path'
    }
}
