# SPDX-FileCopyrightText: 2026 SyuanTsai
# SPDX-License-Identifier: Apache-2.0
$ErrorActionPreference = 'Stop'

BeforeAll {
    . (Join-Path $PSScriptRoot 'ResolveLegacyAuthorityArchiveFixture.ps1')
    $script:RepositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
    $script:RepositoryCheck = Join-Path $script:RepositoryRoot 'scripts/Test-CodeCollaborationRepository.ps1'
    $script:CatalogCheck = Join-Path $script:RepositoryRoot 'scripts/Test-CodeCollaborationCatalog.ps1'

    function New-JsonFixture {
        $root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        Copy-CodeCollaborationFixture -RepositoryRoot $script:RepositoryRoot -DestinationRoot $root
    }
}

Describe 'Consumer repository strict JSON reading' {
    It 'accepts the committed catalog JSON documents through both checks' {
        $fixture = New-JsonFixture
        { & $script:RepositoryCheck -RepositoryRoot $fixture -ReadOnlySnapshot } | Should -Not -Throw
        { & $script:CatalogCheck -RepositoryRoot $fixture -ReadOnlySnapshot } | Should -Not -Throw
    }

    It 'rejects malformed JSON before returning a model' {
        $fixture = New-JsonFixture
        [IO.File]::WriteAllText((Join-Path $fixture 'catalog/source.json'), '{', [Text.UTF8Encoding]::new($false))
        { & $script:RepositoryCheck -RepositoryRoot $fixture -ReadOnlySnapshot } | Should -Throw '*JSON is invalid*'
        { & $script:CatalogCheck -RepositoryRoot $fixture -ReadOnlySnapshot } | Should -Throw '*not valid unambiguous UTF-8 JSON*'
    }

    It 'rejects duplicate properties in source and profile JSON' {
        $fixture = New-JsonFixture
        $sourcePath = Join-Path $fixture 'catalog/source.json'
        $sourceText = Get-Content -Raw -LiteralPath $sourcePath
        [IO.File]::WriteAllText($sourcePath, $sourceText.Replace('"sourceId":', '"sourceId":"duplicate","sourceId":'), [Text.UTF8Encoding]::new($false))
        { & $script:RepositoryCheck -RepositoryRoot $fixture -ReadOnlySnapshot } | Should -Throw '*duplicate JSON property*'

        $fixture = New-JsonFixture
        $catalogPath = Join-Path $fixture 'catalog/profiles.json'
        $catalogText = Get-Content -Raw -LiteralPath $catalogPath
        [IO.File]::WriteAllText($catalogPath, $catalogText.Replace('"catalogId":', '"catalogId":"duplicate","catalogId":'), [Text.UTF8Encoding]::new($false))
        { & $script:CatalogCheck -RepositoryRoot $fixture -ReadOnlySnapshot } | Should -Throw '*duplicate JSON property*'
    }

    It 'rejects nested duplicate properties through both strict readers' {
        $fixture = New-JsonFixture
        $sourcePath = Join-Path $fixture 'catalog/source.json'
        $sourceText = Get-Content -Raw -LiteralPath $sourcePath
        $sourceNeedle = '    "orchestrate-ai-delivery",'
        $sourceReplacement = '    {"skillId":"wrong","skillId":"orchestrate-ai-delivery"},'
        $mutatedSource = $sourceText.Replace($sourceNeedle, $sourceReplacement)
        $mutatedSource | Should -Not -BeExactly $sourceText
        [IO.File]::WriteAllText($sourcePath, $mutatedSource, [Text.UTF8Encoding]::new($false))
        { & $script:RepositoryCheck -RepositoryRoot $fixture -ReadOnlySnapshot } | Should -Throw "*duplicate JSON property 'skillId'.*"

        $fixture = New-JsonFixture
        $catalogPath = Join-Path $fixture 'catalog/profiles.json'
        $catalogText = Get-Content -Raw -LiteralPath $catalogPath
        $catalogNeedle = '        "path": "skills/orchestrate-ai-delivery"'
        $catalogReplacement = '        "path": "skills/wrong", "path": "skills/orchestrate-ai-delivery"'
        $mutatedCatalog = $catalogText.Replace($catalogNeedle, $catalogReplacement)
        $mutatedCatalog | Should -Not -BeExactly $catalogText
        [IO.File]::WriteAllText($catalogPath, $mutatedCatalog, [Text.UTF8Encoding]::new($false))
        { & $script:CatalogCheck -RepositoryRoot $fixture -ReadOnlySnapshot } | Should -Throw "*duplicate JSON property 'path'.*"
    }

    It 'rejects invalid UTF-8 bytes' {
        $fixture = New-JsonFixture
        $path = Join-Path $fixture 'catalog/source.json'
        [IO.File]::WriteAllBytes($path, [byte[]]@(0x7b, 0x22, 0x78, 0x22, 0x3a, 0xff, 0x7d))
        { & $script:RepositoryCheck -RepositoryRoot $fixture -ReadOnlySnapshot } | Should -Throw
        { & $script:CatalogCheck -RepositoryRoot $fixture -ReadOnlySnapshot } | Should -Throw '*not valid unambiguous UTF-8 JSON*'
    }

    It 'rejects case-colliding property names before validation' {
        $fixture = New-JsonFixture
        $path = Join-Path $fixture 'catalog/source.json'
        $text = Get-Content -Raw -LiteralPath $path
        $mutated = $text.Replace('"sourceId":', '"SourceId":"wrong","sourceId":')
        [IO.File]::WriteAllText($path, $mutated, [Text.UTF8Encoding]::new($false))
        { & $script:RepositoryCheck -RepositoryRoot $fixture -ReadOnlySnapshot } | Should -Throw '*JSON*'
        { & $script:CatalogCheck -RepositoryRoot $fixture -ReadOnlySnapshot } | Should -Throw '*JSON*'
    }

    It 'keeps committed consumer JSON free of BOM and duplicate top-level keys' {
        foreach ($relative in @('config/authority-pin.json', 'config/consumer-gate.json')) {
            $bytes = [IO.File]::ReadAllBytes((Join-Path $script:RepositoryRoot $relative))
            ($bytes.Length -ge 3 -and $bytes[0] -eq 239 -and $bytes[1] -eq 187 -and $bytes[2] -eq 191) | Should -BeFalse
            $json = [Text.UTF8Encoding]::new($false, $true).GetString($bytes)
            $document = [Text.Json.JsonDocument]::Parse($json)
            try {
                $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
                foreach ($property in $document.RootElement.EnumerateObject()) {
                    $seen.Add($property.Name) | Should -BeTrue
                }
            }
            finally { $document.Dispose() }
        }
    }
}
