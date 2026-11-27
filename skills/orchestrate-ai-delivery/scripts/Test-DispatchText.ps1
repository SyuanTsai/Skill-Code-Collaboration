# SPDX-FileCopyrightText: 2026 SyuanTsai
# SPDX-License-Identifier: Apache-2.0

<#
.SYNOPSIS
Checks executor prompts and report drafts before sending.

.DESCRIPTION
Reports the locations and kinds of local path and identity matches. With -Prompt,
also reports wording that can suppress review findings. Exit code 1 indicates
findings, and exit code 0 indicates clean input.

.PARAMETER Path
One or more files to read as UTF-8. Each source label uses the path as supplied.

.PARAMETER Text
Text to check, including text received from the pipeline. Each input string is
checked separately and uses the source label <text>.

.PARAMETER Prompt
Enables pattern checks for review-suppression wording in executor and review
prompts. Omit this switch when checking delivery, usage, or Jira comment drafts.

.PARAMETER ForbiddenTerm
Additional literal terms to check for, ignoring case. Comma-joined values are
split, so -ForbiddenTerm a,b works with pwsh -File.

.PARAMETER AllowLiteral
Case-sensitive literal examples to allow. A finding is suppressed when its
entire match is contained in one occurrence of an allowed literal on that line.
Review-suppression findings are always reported in prompt mode.

.PARAMETER NoEnvironmentTerm
Skips checks for the local user name, machine name, and home directory.

.EXAMPLE
./Test-DispatchText.ps1 -Prompt -Path drafts/prompt.md -ForbiddenTerm 'example-user'

.EXAMPLE
./Test-DispatchText.ps1 -Path drafts/report.md

.EXAMPLE
'Review src/main.ps1' | ./Test-DispatchText.ps1 -Prompt -NoEnvironmentTerm
#>
[CmdletBinding(DefaultParameterSetName = 'Text')]
param(
    [Parameter(Mandatory, ParameterSetName = 'Path')]
    [string[]]$Path,

    [Parameter(Mandatory, ParameterSetName = 'Text', ValueFromPipeline)]
    [AllowEmptyString()]
    [string]$Text,

    [string[]]$ForbiddenTerm,
    [string[]]$AllowLiteral,
    [switch]$NoEnvironmentTerm,
    [switch]$Prompt
)

begin {
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    function New-LiteralTermRule {
        param([string]$Kind, [string]$Term)

        $pattern = [regex]::Escape($Term)
        if ($Term -match '\A[\p{L}\p{Nd}_.-]+\z') {
            $pattern = '(?<![\p{L}\p{Nd}])' + $pattern + '(?![\p{L}\p{Nd}])'
        }
        $options = [System.Text.RegularExpressions.RegexOptions]'IgnoreCase, CultureInvariant'
        @{ Kind = $Kind; Pattern = [regex]::new($pattern, $options) }
    }

    function Find-DispatchTextMatch {
        param([string]$Source, [string]$Content)

        $lineNumber = 0
        foreach ($line in ($Content -split '\r?\n')) {
            $lineNumber++
            $allowedSpans = foreach ($pattern in $allowPatterns) {
                foreach ($occurrence in $pattern.Matches($line)) {
                    $occurrence.Groups[1]
                }
            }

            foreach ($rule in $rules) {
                $ruleAllowedSpans = $allowedSpans
                if ($rule['SkipAllowLiteral']) {
                    $ruleAllowedSpans = foreach ($occurrence in $rule.ContextAllowPattern.Matches($line)) {
                        $occurrence.Groups['Acceptance']
                    }
                }

                foreach ($match in $rule.Pattern.Matches($line)) {
                    $allowed = $false
                    foreach ($span in $ruleAllowedSpans) {
                        if ($match.Index -ge $span.Index -and
                            ($match.Index + $match.Length) -le ($span.Index + $span.Length)) {
                            $allowed = $true
                            break
                        }
                    }
                    if (-not $allowed) {
                        [pscustomobject][ordered]@{
                            Source = $Source
                            Line   = $lineNumber
                            Column = $match.Index + 1
                            Kind   = $rule.Kind
                        }
                    }
                }
            }
        }
    }

    $rules = @(
        @{ Kind = 'windows-drive-path'; Pattern = [regex]'(?<![\p{L}\p{Nd}+.-])[A-Za-z]:[\\/]' }
        @{ Kind = 'unc-path'; Pattern = [regex]'(?<![\\:])(?:\\\\[^\\/\s"''<>|:*?]+\\[^\\/\s"''<>|:*?]+|\\\\\\\\[^\\/\s"''<>|:*?]+\\\\[^\\/\s"''<>|:*?]+)' }
        @{ Kind = 'posix-home-path'; Pattern = [regex]'(?<![\p{L}\p{Nd}_.~-])/(?:Users/[\p{L}\p{Nd}_.-]|home/[\p{L}\p{Nd}_.-]|root/)' }
        if (-not $NoEnvironmentTerm) {
            $environmentTerms = @(
                $env:USERNAME
                $env:USER
                [Environment]::UserName
                [Environment]::MachineName
                $HOME
                if ($HOME) {
                    $HOME.Replace('\', '/')
                    $HOME.Replace('/', '\')
                }
            ) | Where-Object { $_ -and $_.Length -ge 3 } | Sort-Object -Unique
            foreach ($term in $environmentTerms) {
                New-LiteralTermRule -Kind 'environment-term' -Term $term
            }
        }
        if ($Prompt) {
            $space = '[\p{Zs}\t]'
            $hyphen = '[-\u00AD\u2010-\u2015\u2212\uFE63\uFF0D]'
            $english = "\b(?:do$space+not$space+re$space*(?:$hyphen$space*)?raise|already$space+accepted|known$space+and$space+accepted)\b"
            $chinese = "(?:不$space*要$space*再$space*提|已$space*(?:知$space*並$space*)?接$space*受)"
            $options = [System.Text.RegularExpressions.RegexOptions]'IgnoreCase, CultureInvariant'
            # Bound both the subject and source to this sentence. Only the acceptance
            # phrase itself is allowed; other findings on the line remain visible.
            $userSubject = "(?:\b(?:the$space+)?user$space+(?:(?:has|had)$space+)?|使用者$space*(?:(?:也|則)$space*)?)"
            $acceptance = "(?:\balready$space+accepted\b|\bknown$space+and$space+accepted\b|已$space*(?:知$space*並$space*)?接$space*受)"
            $sentenceText = '[^。！？.!?\r\n()（）]'
            $source = "[（(]$space*(?:source|來源)$space*[:：]$space*[^\s()（）。，！？.!?][^()（）\r\n]*[）)]"
            $englishInputEnd = "(?=${space}*(?:$|[.,;:?!。，；：？！\p{Ps}\p{Pe}]|(?:must|should|still|will|can|remain|remains)\b))"
            $chineseInputEnd = "(?=${space}*(?:$|[.,;:?!。，；：？！\p{Ps}\p{Pe}]|在變更後|仍|應|須|可|(?:都|皆)(?:仍|應|須|可|必須)))"
            $context = "$userSubject(?<Acceptance>$acceptance)(?=${space}*(?:[^\s。！？.!?()（）]$sentenceText*)?${space}*$source)|\b(?:the$space+)?baseline(?:$space+version)?$space+(?<Acceptance>already$space+accepted)\b$space+(?:(?:these|those|the|valid)$space+)*inputs?\b$englishInputEnd|\binputs$space+(?:the$space+)?baseline(?:$space+version)?$space+(?<Acceptance>already$space+accepted)\b$englishInputEnd|基準(?:版本)?$space*(?<Acceptance>已$space*接$space*受)$space*的$space*輸入$chineseInputEnd"
            @{
                Kind = 'review-suppression'
                Pattern = [regex]::new("$english|$chinese", $options)
                SkipAllowLiteral = $true
                ContextAllowPattern = [regex]::new($context, $options)
            }
        }
        foreach ($term in $ForbiddenTerm) {
            foreach ($part in ($term -split ',')) {
                $part = $part.Trim()
                if ($part) {
                    New-LiteralTermRule -Kind 'forbidden-term' -Term $part
                }
            }
        }
    )

    $allowPatterns = foreach ($literal in $AllowLiteral) {
        if ($literal) {
            # A lookahead captures overlapping occurrences as separate spans.
            [regex]::new('(?=(' + [regex]::Escape($literal) + '))')
        }
    }
    $findingCount = 0
}

process {
    $findings = if ($PSCmdlet.ParameterSetName -eq 'Path') {
        foreach ($file in $Path) {
            if (-not (Test-Path -LiteralPath $file -PathType Leaf)) {
                throw "Input file not found: $file"
            }
            try {
                $content = Get-Content -LiteralPath $file -Raw -Encoding UTF8
            }
            catch {
                throw "Could not read input file: $file"
            }
            Find-DispatchTextMatch -Source $file -Content $content
        }
    }
    else {
        Find-DispatchTextMatch -Source '<text>' -Content $Text
    }

    foreach ($finding in $findings) {
        $findingCount++
        $finding
    }
}

end {
    if ($findingCount -gt 0) {
        Write-Host "Pre-send check: $findingCount finding(s); do not send."
        exit 1
    }
    Write-Host 'Pre-send check: 0 findings.'
    exit 0
}
