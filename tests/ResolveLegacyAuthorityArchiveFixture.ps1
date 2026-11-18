# SPDX-FileCopyrightText: 2026 SyuanTsai
# SPDX-License-Identifier: Apache-2.0

function Copy-CodeCollaborationFixture {
    param(
        [Parameter(Mandatory)][string] $RepositoryRoot,
        [Parameter(Mandatory)][string] $DestinationRoot
    )

    [void](New-Item -ItemType Directory -Path $DestinationRoot -Force)
    foreach ($directory in @('catalog', 'config', 'docs', 'skills')) {
        Copy-Item -LiteralPath (Join-Path $RepositoryRoot $directory) -Destination $DestinationRoot -Recurse
    }
    [void](New-Item -ItemType Directory -Path (Join-Path $DestinationRoot 'scripts') -Force)
    foreach ($name in @('Test-CodeCollaborationCatalog.ps1', 'Test-CodeCollaborationRepository.ps1')) {
        Copy-Item -LiteralPath (Join-Path $RepositoryRoot "scripts/$name") -Destination (Join-Path $DestinationRoot "scripts/$name")
    }
    foreach ($name in @('README.md', 'REUSE.toml', 'VERSION')) {
        Copy-Item -LiteralPath (Join-Path $RepositoryRoot $name) -Destination (Join-Path $DestinationRoot $name)
    }
    return [IO.Path]::GetFullPath($DestinationRoot)
}

function Write-CodeCollaborationJson {
    param(
        [Parameter(Mandatory)][string] $Path,
        [Parameter(Mandatory)] $Value
    )

    $json = ($Value | ConvertTo-Json -Depth 50).Replace("`r`n", "`n") + "`n"
    [IO.File]::WriteAllText($Path, $json, [Text.UTF8Encoding]::new($false))
}

function Get-CodeCollaborationTreeDigest {
    param([Parameter(Mandatory)][string] $Root)

    [string[]]$rows = @(Get-ChildItem -LiteralPath $Root -Recurse -File -Force | ForEach-Object {
            $relative = [IO.Path]::GetRelativePath($Root, $_.FullName).Replace([IO.Path]::DirectorySeparatorChar, '/')
            $sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
            "$relative`t$sha256"
        })
    [Array]::Sort($rows, [StringComparer]::Ordinal)
    $text = ($rows -join "`n") + "`n"
    [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.UTF8Encoding]::new($false).GetBytes($text))).ToLowerInvariant()
}

function Invoke-CodeCollaborationCheck {
    param(
        [Parameter(Mandatory)][string] $Path,
        [Parameter(Mandatory)][string] $RepositoryRoot
    )

    $output = @(& $Path -RepositoryRoot $RepositoryRoot -ReadOnlySnapshot)
    ($output -join "`n") | ConvertFrom-Json -Depth 50
}
