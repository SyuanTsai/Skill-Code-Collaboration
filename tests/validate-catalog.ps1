$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$catalogPath = Join-Path $repoRoot 'catalog/skills-catalog.json'
$catalog = Get-Content -LiteralPath $catalogPath -Raw | ConvertFrom-Json

function Assert-True {
    param([bool] $Condition, [string] $Message)
    if (-not $Condition) { throw $Message }
}

Assert-True ($catalog.schemaVersion -eq 1) 'schemaVersion must be 1.'
Assert-True ($catalog.catalogId -eq 'code-collaboration') 'catalogId must be code-collaboration.'
Assert-True (@($catalog.sources).Count -eq 1) 'Exactly one source is expected.'
Assert-True ($catalog.sources[0].id -eq 'code-collaboration') 'Stable source ID must be code-collaboration.'
Assert-True ($catalog.sources[0].repository -eq 'https://github.com/SyuanTsai/Skill-Code-Collaboration.git') 'Repository URL is invalid.'

$version = (Get-Content -LiteralPath (Join-Path $repoRoot 'VERSION') -Raw).Trim()
Assert-True ($version -match '^\d+\.\d+\.\d+$') 'VERSION must be a SemVer-compatible MAJOR.MINOR.PATCH value.'

$skills = @($catalog.skills)
Assert-True ($skills.Count -eq 1) 'Exactly one skill is expected.'
Assert-True (@($skills.id | Sort-Object -Unique).Count -eq 1) 'Skill IDs must be unique.'

$copilot = @($skills | Where-Object id -eq 'write-copilot-implementation-prompt')[0]
Assert-True ($null -ne $copilot) 'Copilot skill is missing.'
Assert-True ($copilot.source.sourceId -eq 'code-collaboration') 'Copilot sourceId is invalid.'
Assert-True ($copilot.source.path -eq '.agents/skills/write-copilot-implementation-prompt') 'Copilot source path is invalid.'

$profiles = @($catalog.profiles)
Assert-True ($profiles.Count -eq 1) 'Exactly one profile is expected.'
$copilotProfile = @($profiles | Where-Object id -eq 'copilot')[0]
Assert-True ($null -ne $copilotProfile) 'Copilot profile is missing.'
Assert-True (-not $copilotProfile.default) 'Copilot profile must be opt-in.'
Assert-True (@($copilotProfile.includes).Count -eq 1) 'Copilot profile must select one skill.'
Assert-True ($copilotProfile.includes[0] -eq 'write-copilot-implementation-prompt') 'Copilot profile selects the wrong skill.'

Assert-True (@($copilot.compatibility.requiredCapabilities).Count -eq 0) 'Copilot skill must not require Bitbucket/Git capabilities.'
Assert-True (@($copilot.compatibility.anyOfCapabilities).Count -eq 0) 'Copilot skill must be independently available.'

$skillRoot = Join-Path $repoRoot '.agents/skills'
$actualSkillDirectories = @(Get-ChildItem -LiteralPath $skillRoot -Directory | Select-Object -ExpandProperty Name | Sort-Object)
$expectedSkillDirectories = @('write-copilot-implementation-prompt')
Assert-True (($actualSkillDirectories -join "`n") -eq ($expectedSkillDirectories -join "`n")) 'Repository contains missing or unexpected Skill directories.'

foreach ($skill in $skills) {
    $skillPath = Join-Path $repoRoot $skill.source.path
    Assert-True (Test-Path -LiteralPath (Join-Path $skillPath 'SKILL.md')) "Missing SKILL.md for $($skill.id)."
    Assert-True (Test-Path -LiteralPath (Join-Path $skillPath 'agents/openai.yaml')) "Missing agents/openai.yaml for $($skill.id)."
}

Assert-True (Test-Path -LiteralPath (Join-Path $repoRoot 'scripts/Get-SourcePin.ps1')) 'Source pin generator is missing.'
Assert-True (Test-Path -LiteralPath (Join-Path $repoRoot 'docs/RELEASE.md')) 'Release documentation is missing.'
Assert-True (Test-Path -LiteralPath (Join-Path $repoRoot 'docs/ROLLBACK.md')) 'Rollback documentation is missing.'

Write-Host 'Code Collaboration repository contract validation passed.'
