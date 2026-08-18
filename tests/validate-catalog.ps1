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

$skills = @($catalog.skills)
Assert-True ($skills.Count -eq 2) 'Exactly two skills are expected.'

$copilot = @($skills | Where-Object id -eq 'write-copilot-implementation-prompt')[0]
$bitbucket = @($skills | Where-Object id -eq 'review-bitbucket-pull-request')[0]
Assert-True ($null -ne $copilot) 'Copilot skill is missing.'
Assert-True ($null -ne $bitbucket) 'Bitbucket skill is missing.'
Assert-True ($copilot.source.sourceId -eq 'code-collaboration') 'Copilot sourceId is invalid.'
Assert-True ($bitbucket.source.sourceId -eq 'code-collaboration') 'Bitbucket sourceId is invalid.'

$profiles = @($catalog.profiles)
$copilotProfile = @($profiles | Where-Object id -eq 'copilot')[0]
$bitbucketProfile = @($profiles | Where-Object id -eq 'bitbucket')[0]
Assert-True (@($copilotProfile.includes).Count -eq 1) 'Copilot profile must select one skill.'
Assert-True ($copilotProfile.includes[0] -eq 'write-copilot-implementation-prompt') 'Copilot profile selects the wrong skill.'
Assert-True (@($bitbucketProfile.includes).Count -eq 1) 'Bitbucket profile must select one skill.'
Assert-True ($bitbucketProfile.includes[0] -eq 'review-bitbucket-pull-request') 'Bitbucket profile selects the wrong skill.'

$required = @($bitbucket.compatibility.requiredCapabilities)
Assert-True (($required | Where-Object { $_.kind -eq 'command' -and $_.id -eq 'git' -and $_.state -eq 'available' }).Count -eq 1) 'Bitbucket skill must require git.'

$alternatives = @($bitbucket.compatibility.anyOfCapabilities[0])
Assert-True (($alternatives | Where-Object { $_.kind -eq 'connector' -and $_.id -eq 'bitbucket-cloud' -and $_.state -eq 'configured' }).Count -eq 1) 'Bitbucket connector capability is missing.'
Assert-True (($alternatives | Where-Object { $_.kind -eq 'environment' -and $_.id -eq 'bitbucket-cloud-api' -and $_.state -eq 'configured' }).Count -eq 1) 'Bitbucket API environment capability is missing.'

foreach ($skill in $skills) {
    $skillPath = Join-Path $repoRoot $skill.source.path
    Assert-True (Test-Path -LiteralPath (Join-Path $skillPath 'SKILL.md')) "Missing SKILL.md for $($skill.id)."
}

Write-Host 'Code Collaboration catalog validation passed.'
