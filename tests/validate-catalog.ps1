# SPDX-FileCopyrightText: 2026 SyuanTsai
# SPDX-License-Identifier: Apache-2.0
[CmdletBinding()]
param(
    [string] $RepositoryRoot,
    [string] $OutputPath
)

$ErrorActionPreference = 'Stop'

function Assert-True {
    param([bool] $Condition, [string] $Message)
    if (-not $Condition) { throw $Message }
}

function Assert-ExactPropertySet {
    param(
        [Parameter(Mandatory = $true)] $Value,
        [Parameter(Mandatory = $true)][string[]] $Expected,
        [Parameter(Mandatory = $true)][string] $Context
    )

    if ($null -eq $Value -or $Value -is [array] -or $Value -is [string]) {
        throw "$Context must be a JSON object."
    }
    $actual = @($Value.PSObject.Properties | ForEach-Object { [string]$_.Name })
    $missing = @($Expected | Where-Object { $actual -cnotcontains $_ })
    $unexpected = @($actual | Where-Object { $Expected -cnotcontains $_ })
    if ($missing.Count -gt 0 -or $unexpected.Count -gt 0 -or $actual.Count -ne $Expected.Count) {
        throw "$Context has an invalid property set. Missing='$($missing -join ',')' Unexpected='$($unexpected -join ',')'."
    }
}

function Assert-NoDuplicateJsonProperties {
    param([Parameter(Mandatory = $true)][System.Text.Json.JsonElement] $Element, [string] $Context = '$')
    if ($Element.ValueKind -eq [System.Text.Json.JsonValueKind]::Object) {
        $names = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        foreach ($property in $Element.EnumerateObject()) {
            if (-not $names.Add($property.Name)) { throw "$Context contains duplicate JSON property '$($property.Name)'." }
            Assert-NoDuplicateJsonProperties -Element $property.Value -Context "$Context.$($property.Name)"
        }
    }
    elseif ($Element.ValueKind -eq [System.Text.Json.JsonValueKind]::Array) {
        $index = 0
        foreach ($item in $Element.EnumerateArray()) {
            Assert-NoDuplicateJsonProperties -Element $item -Context "$Context[$index]"
            $index++
        }
    }
}

function Read-StrictJson {
    param([Parameter(Mandatory = $true)][string] $Path, [Parameter(Mandatory = $true)][string] $Context)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "$Context is missing: $Path" }
    try {
        $text = [IO.File]::ReadAllText($Path, [Text.UTF8Encoding]::new($false, $true))
        $document = [System.Text.Json.JsonDocument]::Parse($text)
        try { Assert-NoDuplicateJsonProperties -Element $document.RootElement -Context $Context }
        finally { $document.Dispose() }
        return $text | ConvertFrom-Json -Depth 50
    }
    catch { throw "$Context is not valid unambiguous UTF-8 JSON: $($_.Exception.Message)" }
}

function Get-SortedSkillIds {
    param([Parameter(Mandatory = $true)] $Values, [Parameter(Mandatory = $true)][string] $Context)
    if ($Values -isnot [array] -or @($Values).Count -eq 0) { throw "$Context must be a non-empty array." }
    $ids = @()
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($value in @($Values)) {
        if ($value -isnot [string] -or [string]$value -cnotmatch '^[a-z0-9]+(?:-[a-z0-9]+)*$') {
            throw "$Context contains an invalid Skill ID '$value'."
        }
        if (-not $seen.Add([string]$value)) { throw "$Context contains duplicate Skill ID '$value'." }
        $ids += [string]$value
    }
    [string[]]$sorted = @($ids)
    [Array]::Sort($sorted, [StringComparer]::Ordinal)
    if (($ids -join "`n") -cne ($sorted -join "`n")) { throw "$Context must use ordinal ascending order." }
    return $sorted
}

function Assert-StringArray {
    param($Value, [string] $Context)
    if ($Value -isnot [array]) { throw "$Context must be an array." }
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($entry in @($Value)) {
        if ($entry -isnot [string] -or [string]::IsNullOrWhiteSpace([string]$entry) -or -not $seen.Add([string]$entry)) {
            throw "$Context must contain unique non-empty strings."
        }
    }
}

$repoRoot = if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
    [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
}
else { [IO.Path]::GetFullPath($RepositoryRoot) }

$source = Read-StrictJson -Path (Join-Path $repoRoot 'catalog/source.json') -Context 'catalog/source.json'
Assert-ExactPropertySet -Value $source -Expected @('schemaVersion', 'sourceId', 'repository', 'skillsRoot', 'skills') -Context 'catalog/source.json'
Assert-True ($source.schemaVersion -eq 2) 'catalog/source.json schemaVersion must be 2.'
Assert-True ([string]$source.sourceId -ceq 'code-collaboration') 'catalog/source.json sourceId must be code-collaboration.'
Assert-True ([string]$source.repository -ceq 'https://github.com/SyuanTsai/Skill-Code-Collaboration.git') 'catalog/source.json repository is invalid.'
Assert-True ([string]$source.skillsRoot -ceq 'skills') 'catalog/source.json skillsRoot must be skills.'
$sourceSkillIds = @(Get-SortedSkillIds -Values $source.skills -Context 'catalog/source.json skills')

$skillsRoot = Join-Path $repoRoot 'skills'
Assert-True (Test-Path -LiteralPath $skillsRoot -PathType Container) 'Canonical skills/ source root is missing.'
$actualSkillIds = @(
    Get-ChildItem -LiteralPath $skillsRoot -Directory -Force |
        ForEach-Object { [string]$_.Name } |
        Sort-Object
)
Assert-True (($actualSkillIds -join "`n") -ceq ($sourceSkillIds -join "`n")) 'skills/ directories must exactly match source inventory.'

$catalog = Read-StrictJson -Path (Join-Path $repoRoot 'catalog/profiles.json') -Context 'catalog/profiles.json'
Assert-ExactPropertySet -Value $catalog -Expected @('schemaVersion', 'catalogId', 'sources', 'profiles', 'skills') -Context 'catalog/profiles.json'
Assert-True ($catalog.schemaVersion -eq 1) 'catalog/profiles.json schemaVersion must be 1.'
Assert-True ([string]$catalog.catalogId -ceq 'code-collaboration') 'catalogId must be code-collaboration.'

$sources = @($catalog.sources)
Assert-True ($sources.Count -eq 1) 'Exactly one catalog source is expected.'
Assert-ExactPropertySet -Value $sources[0] -Expected @('id', 'repository') -Context 'catalog source'
Assert-True ([string]$sources[0].id -ceq 'code-collaboration') 'Catalog source ID is invalid.'
Assert-True ([string]$sources[0].repository -ceq [string]$source.repository) 'Catalog source repository must match source inventory.'

$profiles = @($catalog.profiles)
Assert-True ($profiles.Count -gt 0) 'At least one profile is required.'
$profileIds = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
foreach ($profile in $profiles) {
    Assert-ExactPropertySet -Value $profile -Expected @('id', 'description', 'default', 'includes', 'excludes') -Context 'catalog profile'
    Assert-True ($profile.id -is [string] -and $profile.id -cmatch '^[a-z0-9]+(?:-[a-z0-9]+)*$' -and $profileIds.Add([string]$profile.id)) 'Profile IDs must be unique safe values.'
    Assert-True ($profile.description -is [string] -and -not [string]::IsNullOrWhiteSpace([string]$profile.description)) "Profile '$($profile.id)' must have a description."
    Assert-True ($profile.default -is [bool]) "Profile '$($profile.id)' default must be boolean."
    Assert-StringArray -Value $profile.includes -Context "Profile '$($profile.id)' includes"
    Assert-StringArray -Value $profile.excludes -Context "Profile '$($profile.id)' excludes"
    $overlap = @($profile.includes | Where-Object { @($profile.excludes) -ccontains $_ })
    Assert-True ($overlap.Count -eq 0) "Profile '$($profile.id)' cannot include and exclude the same Skill."
    foreach ($skillId in @($profile.includes) + @($profile.excludes)) {
        Assert-True ($sourceSkillIds -ccontains [string]$skillId) "Profile '$($profile.id)' references unknown Skill '$skillId'."
    }
}

$catalogSkills = @($catalog.skills)
$catalogSkillIds = @($catalogSkills | ForEach-Object { [string]$_.id })
$uniqueCatalogSkillIds = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
foreach ($skillId in $catalogSkillIds) {
    Assert-True ($uniqueCatalogSkillIds.Add($skillId)) "Skill IDs must be unique; duplicate '$skillId'."
}
Assert-True ($catalogSkills.Count -eq $sourceSkillIds.Count) 'Catalog Skill count must exactly match source inventory.'
[string[]]$sortedCatalogIds = @($catalogSkillIds)
[Array]::Sort($sortedCatalogIds, [StringComparer]::Ordinal)
Assert-True (($catalogSkillIds -join "`n") -ceq ($sortedCatalogIds -join "`n")) 'Catalog Skills must use ordinal ascending order.'
Assert-True (($sortedCatalogIds -join "`n") -ceq ($sourceSkillIds -join "`n")) 'Catalog Skill IDs must exactly match source inventory.'

$activeSkills = @()
foreach ($skill in $catalogSkills) {
    $skillId = [string]$skill.id
    Assert-ExactPropertySet -Value $skill -Expected @('id', 'group', 'source', 'profiles', 'compatibility', 'dependencies', 'lifecycle') -Context "catalog Skill '$skillId'"
    Assert-True ([string]$skill.group -ceq 'code-collaboration') "Skill '$skillId' group is invalid."
    Assert-ExactPropertySet -Value $skill.source -Expected @('sourceId', 'path') -Context "Skill '$skillId' source"
    Assert-True ([string]$skill.source.sourceId -ceq [string]$source.sourceId) "Skill '$skillId' sourceId is invalid."
    Assert-True ([string]$skill.source.path -ceq "skills/$skillId") "Skill '$skillId' source path must exactly match its stable ID."
    Assert-StringArray -Value $skill.profiles -Context "Skill '$skillId' profiles"
    foreach ($profileId in @($skill.profiles)) {
        Assert-True ($profileIds.Contains([string]$profileId)) "Skill '$skillId' references unknown profile '$profileId'."
    }
    Assert-ExactPropertySet -Value $skill.compatibility -Expected @('platforms', 'shells', 'requiredCapabilities', 'anyOfCapabilities') -Context "Skill '$skillId' compatibility"
    foreach ($name in @('platforms', 'shells', 'requiredCapabilities', 'anyOfCapabilities')) {
        Assert-StringArray -Value $skill.compatibility.$name -Context "Skill '$skillId' compatibility.$name"
    }
    Assert-True ($skill.dependencies -is [array]) "Skill '$skillId' dependencies must be an array."
    Assert-ExactPropertySet -Value $skill.lifecycle -Expected @('status', 'aliases') -Context "Skill '$skillId' lifecycle"
    Assert-True ([string]$skill.lifecycle.status -ceq 'active') "Skill '$skillId' must be active."
    Assert-StringArray -Value $skill.lifecycle.aliases -Context "Skill '$skillId' lifecycle.aliases"
    $activeSkills += $skillId

    $skillRoot = Join-Path $repoRoot "skills/$skillId"
    Assert-True (Test-Path -LiteralPath (Join-Path $skillRoot 'SKILL.md') -PathType Leaf) "Missing SKILL.md for '$skillId'."
    Assert-True (Test-Path -LiteralPath (Join-Path $skillRoot 'agents/openai.yaml') -PathType Leaf) "Missing agents/openai.yaml for '$skillId'."
}

Assert-True (Test-Path -LiteralPath (Join-Path $repoRoot 'VERSION') -PathType Leaf) 'VERSION is missing.'
$version = (Get-Content -LiteralPath (Join-Path $repoRoot 'VERSION') -Raw).Trim()
Assert-True ($version -match '^\d+\.\d+\.\d+$') 'VERSION must be a SemVer-compatible MAJOR.MINOR.PATCH value.'
Assert-True (Test-Path -LiteralPath (Join-Path $repoRoot 'scripts/Get-SourcePin.ps1') -PathType Leaf) 'Source pin generator is missing.'
Assert-True (Test-Path -LiteralPath (Join-Path $repoRoot 'docs/RELEASE.md') -PathType Leaf) 'Release documentation is missing.'
Assert-True (Test-Path -LiteralPath (Join-Path $repoRoot 'docs/ROLLBACK.md') -PathType Leaf) 'Rollback documentation is missing.'

$result = [pscustomobject][ordered]@{
    schemaVersion = 1
    catalogId = 'code-collaboration'
    sourceId = 'code-collaboration'
    activeSkillCount = $activeSkills.Count
    skills = @($activeSkills | ForEach-Object { [pscustomobject][ordered]@{ skillId = $_; sourcePath = "skills/$_" } })
    profiles = @($profiles | ForEach-Object { [pscustomobject][ordered]@{ profileId = [string]$_.id; includes = @($_.includes); excludes = @($_.excludes) } })
    result = 'passed'
}
$json = $result | ConvertTo-Json -Depth 30
if (-not [string]::IsNullOrWhiteSpace($OutputPath)) {
    $outputFullPath = [IO.Path]::GetFullPath($OutputPath)
    $outputDirectory = Split-Path -Parent $outputFullPath
    if (-not [string]::IsNullOrWhiteSpace($outputDirectory)) { [void](New-Item -ItemType Directory -Path $outputDirectory -Force) }
    if (Test-Path -LiteralPath $outputFullPath -PathType Leaf) { throw "OutputPath already exists: $outputFullPath" }
    [IO.File]::WriteAllText($outputFullPath, $json + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
}
[Console]::Out.WriteLine($json)
