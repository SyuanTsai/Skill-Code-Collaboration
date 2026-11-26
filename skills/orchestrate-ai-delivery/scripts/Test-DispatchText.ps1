# SPDX-FileCopyrightText: 2026 SyuanTsai
# SPDX-License-Identifier: Apache-2.0

<#
.SYNOPSIS
Checks executor prompts and report drafts before sending.

.DESCRIPTION
Reports the locations and kinds of local path and identity matches. Exit code 1
indicates findings, and exit code 0 indicates clean input.

.PARAMETER Path
One or more files to read as UTF-8. Each source label uses the path as supplied.

.PARAMETER Text
Text to check, including text received from the pipeline. Each input string is
checked separately and uses the source label <text>.

.PARAMETER ForbiddenTerm
Additional literal terms to check for, ignoring case. Comma-joined values are
split, so -ForbiddenTerm a,b works with pwsh -File.

.PARAMETER AllowLiteral
Case-sensitive literal examples to allow. A finding is suppressed when its
entire match is contained in one occurrence of an allowed literal on that line.

.PARAMETER NoEnvironmentTerm
Skips checks for the local user name, machine name, and home directory.

.EXAMPLE
./Test-DispatchText.ps1 -Path drafts/prompt.md,drafts/report.md -ForbiddenTerm 'example-user'

.EXAMPLE
'Review src/main.ps1' | ./Test-DispatchText.ps1 -NoEnvironmentTerm
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
    [switch]$NoEnvironmentTerm
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
                foreach ($match in $rule.Pattern.Matches($line)) {
                    $allowed = $false
                    foreach ($span in $allowedSpans) {
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
