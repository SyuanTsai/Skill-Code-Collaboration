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

    # Scenario: A review prompt uses an English suppression phrase or a common variant.
    # Purpose: Detect each phrase despite case, spacing, or the choice of hyphen.
    It 'UnitT10_reports English review suppression in <Form>' -ForEach @(
        @{ Form = 'an instruction'; Text = 'Do not re-raise this regression.' }
        @{ Form = 'a spaced form'; Text = "DO  NOT`tRE RAISE the finding." }
        @{ Form = 'an unhyphenated form'; Text = 'Do not reraise the finding.' }
        @{ Form = 'a nonbreaking hyphen'; Text = 'Do not re‑raise the finding.' }
        @{ Form = 'a Unicode hyphen'; Text = 'Do not re‐raise the finding.' }
        @{ Form = 'a dash with spacing'; Text = 'Do not re – raise the finding.' }
        @{ Form = 'prior acceptance'; Text = 'This was already accepted.' }
        @{ Form = 'known acceptance'; Text = "This is KNOWN`tAND  ACCEPTED." }
    ) {
        $findings = @(& $script:ScriptPath -Prompt -Text $Text -NoEnvironmentTerm 6>$null)
        $LASTEXITCODE | Should -Be 1
        $findings.Count | Should -Be 1
        $findings[0].Kind | Should -BeExactly 'review-suppression'
    }

    # Scenario: A Traditional Chinese prompt uses an adjacent or spaced suppression phrase.
    # Purpose: Recognize the phrase without relying on English word boundaries.
    It 'UnitT20_reports Traditional Chinese review suppression in <Form>' -ForEach @(
        @{ Form = 'an instruction within a sentence'; Text = '請不要再提這項退化。' }
        @{ Form = 'prior acceptance within a sentence'; Text = '此項已接受請略過。' }
        @{ Form = 'known acceptance'; Text = '相關退化已知並接受請略過。' }
        @{ Form = 'spaced characters'; Text = "請不 要`t再　提這項退化。" }
        @{ Form = 'spaced known acceptance'; Text = "這項已 知`t並 接 受請略過。" }
    ) {
        $findings = @(& $script:ScriptPath -Prompt -Text $Text -NoEnvironmentTerm 6>$null)
        $LASTEXITCODE | Should -Be 1
        $findings.Count | Should -Be 1
        $findings[0].Kind | Should -BeExactly 'review-suppression'
    }

    # Scenario: A re-review prompt directs the reviewer to skip a baseline regression.
    # Purpose: Report both suppression phrases with safe, one-based diagnostics.
    It 'UnitT30_locates suppression of a recurring regression in a re-review prompt' {
        $text = "Review only the fix and related regressions.`r`n  Do not re-raise the baseline regression. It was already accepted."
        $findings = @(& $script:ScriptPath -Prompt -Text $text -NoEnvironmentTerm 6>$null)
        $LASTEXITCODE | Should -Be 1
        $findings.Count | Should -Be 2
        foreach ($finding in $findings) {
            ($finding.PSObject.Properties.Name -join ',') | Should -BeExactly 'Source,Line,Column,Kind'
            $finding.Source | Should -BeExactly '<text>'
            $finding.Line | Should -Be 2
            $finding.Kind | Should -BeExactly 'review-suppression'
        }
        $findings[0].Column | Should -Be 3
        $findings[1].Column | Should -Be 51
    }

    # Scenario: A prompt scopes a re-review and includes non-matching word fragments and separate lines.
    # Purpose: Preserve normal scope instructions and require complete English words on one line.
    It 'UnitT40_accepts normal review scope and excludes partial or split phrases' {
        $text = @(
            'Limit the re-review to the fix and related regressions. Report every valid finding, including recurring ones.'
            'The user approved the file-format change in the scope decision.'
            'undo not re-raise; do not re-raises; unalready accepted; already acceptedness; unknown and accepted.'
            'The layout was already'
            'accepted by the group.'
        ) -join "`n"
        $findings = @(& $script:ScriptPath -Prompt -Text $text -NoEnvironmentTerm 6>$null)
        $LASTEXITCODE | Should -Be 0
        $findings.Count | Should -Be 0
    }

    # Scenario: Draft reporting text includes acceptance language and a forbidden term.
    # Purpose: Keep legacy checks active without adding the prompt-only finding.
    It 'UnitT50_preserves non-prompt checks for reports and comment drafts' {
        $text = 'The change was already accepted by Alice. 這項已接受。'
        $findings = @(& $script:ScriptPath -Text $text -NoEnvironmentTerm 6>$null)
        $LASTEXITCODE | Should -Be 0
        $findings.Count | Should -Be 0

        $findings = @(& $script:ScriptPath -Text $text -ForbiddenTerm 'alice' -NoEnvironmentTerm 6>$null)
        $LASTEXITCODE | Should -Be 1
        $findings.Count | Should -Be 1
        $findings[0].Kind | Should -BeExactly 'forbidden-term'
    }

    # Scenario: A prompt allow literal spans a sample path and an actual suppression instruction.
    # Purpose: Allow the path while reporting suppression within the allowed span.
    It 'UnitT60_prevents AllowLiteral from masking prompt suppression' {
        $text = 'C:\example Do not re-raise this finding.'
        $findings = @(& $script:ScriptPath -Prompt -Text $text -AllowLiteral $text -NoEnvironmentTerm 6>$null)
        $LASTEXITCODE | Should -Be 1
        $findings.Count | Should -Be 1
        $findings[0].Kind | Should -BeExactly 'review-suppression'
        $findings[0].Column | Should -Be 12
    }

    # Scenario: A UTF-8 prompt file contains a Chinese suppression phrase after a clean line.
    # Purpose: Apply prompt checks to file contents and preserve the path and phrase location.
    It 'UnitT70_reports suppression in a UTF-8 file with the supplied source label' {
        $file = Join-Path $TestDrive 'review-prompt.txt'
        [System.IO.File]::WriteAllText($file, "Review the fix.`n這個已接受請略過。", [System.Text.UTF8Encoding]::new($false))

        $findings = @(& $script:ScriptPath -Prompt -Path $file -NoEnvironmentTerm 6>$null)
        $LASTEXITCODE | Should -Be 1
        $findings.Count | Should -Be 1
        $findings[0].Source | Should -BeExactly $file
        $findings[0].Line | Should -Be 2
        $findings[0].Column | Should -Be 3
        $findings[0].Kind | Should -BeExactly 'review-suppression'
    }

    # Scenario: A suppressive prompt is followed by a clean input string in the same pipeline.
    # Purpose: Retain the prompt finding and exit status across pipeline records.
    It 'UnitT80_checks prompt pipeline input and retains the failure status' {
        $findings = @('這項已知並接受。', 'Report all valid findings.' | & $script:ScriptPath -Prompt -NoEnvironmentTerm 6>$null)
        $LASTEXITCODE | Should -Be 1
        $findings.Count | Should -Be 1
        $findings[0].Source | Should -BeExactly '<text>'
        $findings[0].Column | Should -Be 3
        $findings[0].Kind | Should -BeExactly 'review-suppression'
    }

    # Scenario: Sourced user decisions and adjacent baseline descriptions provide review context.
    # Purpose: Accept only the acceptance phrase when the same sentence supplies a nonempty source.
    It 'UnitT90_accepts sourced context in <Form>' -ForEach @(
        @{ Form = 'Chinese decision'; Text = '使用者已接受檔名格式變更（來源：明確授權留言）。' }
        @{ Form = 'Chinese preceding topic'; Text = '檔名格式變更，使用者已接受（來源：授權留言）。' }
        @{ Form = 'Chinese preceding known topic'; Text = '這項格式，使用者已知並接受（來源：授權留言）。' }
        @{ Form = 'Chinese particle'; Text = '使用者也已接受格式（來源：留言）。' }
        @{ Form = 'English decision'; Text = 'The user has already accepted the filename change (Source: explicit approval).' }
        @{ Form = 'English baseline'; Text = 'The baseline version already accepted these inputs (Source: test results).' }
        @{ Form = 'Chinese baseline'; Text = '基準版本已接受的輸入（來源：測試結果）。' }
        @{ Form = 'Chinese baseline without source'; Text = '確認基準版本已接受的輸入在變更後仍然成功。' }
        @{ Form = 'English baseline without source'; Text = 'Inputs the baseline already accepted must still succeed.' }
        @{ Form = 'English baseline remains valid'; Text = 'Inputs the baseline already accepted remain valid.' }
        @{ Form = 'Chinese baseline all must pass'; Text = '基準版本已接受的輸入都必須繼續通過驗證。' }
    ) {
        $findings = @(& $script:ScriptPath -Prompt -Text $Text -NoEnvironmentTerm 6>$null)
        $LASTEXITCODE | Should -Be 0
        $findings.Count | Should -Be 0
    }

    # Scenario: A sourced decision appears alongside an independent instruction.
    # Purpose: Report only the instruction and retain its exact diagnostic column.
    It 'UnitT95_reports separate suppression in <Form>' -ForEach @(
        @{ Form = 'Chinese'; Text = '使用者已接受格式（來源：留言），不要再提此問題。'; Instruction = '不要再提' }
        @{ Form = 'English'; Text = 'The user already accepted the format (Source: comment), do not re-raise this issue.'; Instruction = 'do not re-raise' }
    ) {
        $findings = @(& $script:ScriptPath -Prompt -Text $Text -NoEnvironmentTerm 6>$null)
        $LASTEXITCODE | Should -Be 1
        $findings.Count | Should -Be 1
        $findings[0].Kind | Should -BeExactly 'review-suppression'
        $findings[0].Column | Should -Be ($Text.IndexOf($Instruction) + 1)
    }

    # Scenario: Acceptance lacks an eligible subject or a nonempty source in the same sentence.
    # Purpose: Continue reporting unsubstantiated and controller assertions.
    It 'UnitT99_reports unsupported acceptance in <Form>' -ForEach @(
        @{ Form = 'missing source'; Text = '使用者已接受格式。' }
        @{ Form = 'empty source'; Text = '使用者已接受格式（來源： ）。' }
        @{ Form = 'different sentence'; Text = '使用者已接受格式。來源（Source: comment）' }
        @{ Form = 'controller'; Text = '控制者已接受格式（來源：留言）。' }
        @{ Form = 'English empty source'; Text = 'The user already accepted this (Source: ).' }
        @{ Form = 'English controller'; Text = 'The controller already accepted this (Source: comment).' }
        @{ Form = 'reverse English input issue'; Text = 'Inputs the baseline already accepted validation issue (Source: previous review).' }
        @{ Form = 'Chinese input format issue'; Text = '基準版本已接受的輸入格式問題（來源：前次審查）。' }
        @{ Form = 'English input validation issue'; Text = 'The baseline already accepted the input validation issue (Source: previous review).' }
        @{ Form = 'English hyphenated input validation issue'; Text = 'The baseline already accepted the input-validation issue (Source: previous review).' }
        @{ Form = 'Chinese input validation issue'; Text = '基準版本已接受的輸入驗證問題（來源：前次審查）。' }
        @{ Form = 'sourced baseline issue'; Text = 'The baseline already accepted this issue (Source: previous review).' }
        @{ Form = 'sourced Chinese baseline issue'; Text = '基準版本已接受這項問題（來源：前次審查）。' }
        @{ Form = 'unsourced baseline claim'; Text = 'The baseline already accepted this issue.' }
        @{ Form = 'unsourced Chinese baseline claim'; Text = '基準版本已接受這項問題。' }
    ) {
        $findings = @(& $script:ScriptPath -Prompt -Text $Text -NoEnvironmentTerm 6>$null)
        $LASTEXITCODE | Should -Be 1
        $findings.Count | Should -Be 1
        $findings[0].Kind | Should -BeExactly 'review-suppression'
    }
}
