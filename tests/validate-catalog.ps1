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
Assert-True ($skills.Count -eq 2) 'Exactly two skills are expected.'
Assert-True (@($skills.id | Sort-Object -Unique).Count -eq 2) 'Skill IDs must be unique.'

$copilot = @($skills | Where-Object id -eq 'write-copilot-implementation-prompt')[0]
$bitbucket = @($skills | Where-Object id -eq 'review-bitbucket-pull-request')[0]
Assert-True ($null -ne $copilot) 'Copilot skill is missing.'
Assert-True ($null -ne $bitbucket) 'Bitbucket skill is missing.'
Assert-True ($copilot.source.sourceId -eq 'code-collaboration') 'Copilot sourceId is invalid.'
Assert-True ($bitbucket.source.sourceId -eq 'code-collaboration') 'Bitbucket sourceId is invalid.'
Assert-True ($copilot.source.path -eq '.agents/skills/write-copilot-implementation-prompt') 'Copilot source path is invalid.'
Assert-True ($bitbucket.source.path -eq '.agents/skills/review-bitbucket-pull-request') 'Bitbucket source path is invalid.'

$profiles = @($catalog.profiles)
Assert-True ($profiles.Count -eq 2) 'Exactly two independently selectable profiles are expected.'
$copilotProfile = @($profiles | Where-Object id -eq 'copilot')[0]
$bitbucketProfile = @($profiles | Where-Object id -eq 'bitbucket')[0]
Assert-True ($null -ne $copilotProfile) 'Copilot profile is missing.'
Assert-True ($null -ne $bitbucketProfile) 'Bitbucket profile is missing.'
Assert-True (-not $copilotProfile.default) 'Copilot profile must be opt-in.'
Assert-True (-not $bitbucketProfile.default) 'Bitbucket profile must be opt-in.'
Assert-True (@($copilotProfile.includes).Count -eq 1) 'Copilot profile must select one skill.'
Assert-True ($copilotProfile.includes[0] -eq 'write-copilot-implementation-prompt') 'Copilot profile selects the wrong skill.'
Assert-True (@($bitbucketProfile.includes).Count -eq 1) 'Bitbucket profile must select one skill.'
Assert-True ($bitbucketProfile.includes[0] -eq 'review-bitbucket-pull-request') 'Bitbucket profile selects the wrong skill.'
Assert-True (($copilotProfile.includes -notcontains 'review-bitbucket-pull-request')) 'Copilot profile must not include Bitbucket review.'
Assert-True (($bitbucketProfile.includes -notcontains 'write-copilot-implementation-prompt')) 'Bitbucket profile must not include Copilot prompt generation.'

Assert-True (@($copilot.compatibility.requiredCapabilities).Count -eq 0) 'Copilot skill must not require Bitbucket/Git capabilities.'
Assert-True (@($copilot.compatibility.anyOfCapabilities).Count -eq 0) 'Copilot skill must be independently available.'

$required = @($bitbucket.compatibility.requiredCapabilities)
Assert-True (($required | Where-Object { $_.kind -eq 'command' -and $_.id -eq 'git' -and $_.state -eq 'available' }).Count -eq 1) 'Bitbucket skill must require git.'

$alternatives = @($bitbucket.compatibility.anyOfCapabilities[0])
Assert-True (($alternatives | Where-Object { $_.kind -eq 'connector' -and $_.id -eq 'bitbucket-cloud' -and $_.state -eq 'configured' }).Count -eq 1) 'Bitbucket connector capability is missing.'
Assert-True (($alternatives | Where-Object { $_.kind -eq 'environment' -and $_.id -eq 'bitbucket-cloud-api' -and $_.state -eq 'configured' }).Count -eq 1) 'Bitbucket API environment capability is missing.'

$skillRoot = Join-Path $repoRoot '.agents/skills'
$actualSkillDirectories = @(Get-ChildItem -LiteralPath $skillRoot -Directory | Select-Object -ExpandProperty Name | Sort-Object)
$expectedSkillDirectories = @('review-bitbucket-pull-request', 'write-copilot-implementation-prompt')
Assert-True (($actualSkillDirectories -join "`n") -eq ($expectedSkillDirectories -join "`n")) 'Repository contains missing or unexpected Skill directories.'

foreach ($skill in $skills) {
    $skillPath = Join-Path $repoRoot $skill.source.path
    Assert-True (Test-Path -LiteralPath (Join-Path $skillPath 'SKILL.md')) "Missing SKILL.md for $($skill.id)."
    Assert-True (Test-Path -LiteralPath (Join-Path $skillPath 'agents/openai.yaml')) "Missing agents/openai.yaml for $($skill.id)."
}

Assert-True (Test-Path -LiteralPath (Join-Path $repoRoot '.agents/skills/review-bitbucket-pull-request/references/bitbucket-cloud-api.md')) 'Bitbucket API reference is missing.'
Assert-True (Test-Path -LiteralPath (Join-Path $repoRoot 'scripts/Get-SourcePin.ps1')) 'Source pin generator is missing.'
Assert-True (Test-Path -LiteralPath (Join-Path $repoRoot 'docs/RELEASE.md')) 'Release documentation is missing.'
Assert-True (Test-Path -LiteralPath (Join-Path $repoRoot 'docs/ROLLBACK.md')) 'Rollback documentation is missing.'

Write-Host 'Code Collaboration repository contract validation passed.'
