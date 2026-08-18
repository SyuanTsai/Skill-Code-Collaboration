[CmdletBinding()]
param(
    [string] $Ref = 'HEAD'
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot

function Invoke-GitText {
    param([Parameter(Mandatory = $true)][string[]] $Arguments)

    $output = & git -C $repoRoot @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "git $($Arguments -join ' ') failed: $($output -join [Environment]::NewLine)"
    }

    return @($output | ForEach-Object { [string] $_ })
}

$resolvedCommit = (Invoke-GitText -Arguments @('rev-parse', "$Ref^{commit}"))[0].Trim()
if ($resolvedCommit -notmatch '^[0-9a-f]{40}$') {
    throw "Ref '$Ref' did not resolve to a full commit SHA."
}

# The full recursive Git tree is a deterministic manifest of tracked paths,
# modes, object types and blob/tree object IDs. Hashing this normalized stream
# produces a stable source-content fingerprint without filesystem timestamps.
$treeLines = @(Invoke-GitText -Arguments @('ls-tree', '-r', '--full-tree', $resolvedCommit) | Sort-Object -CaseSensitive)
if ($treeLines.Count -eq 0) {
    throw "Ref '$Ref' contains no tracked files."
}

$normalizedTree = ($treeLines -join "`n") + "`n"
$bytes = [System.Text.Encoding]::UTF8.GetBytes($normalizedTree)
$sha = [System.Security.Cryptography.SHA256]::Create()
try {
    $contentSha256 = ([System.BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant()
}
finally {
    $sha.Dispose()
}

$versionPath = Join-Path $repoRoot 'VERSION'
$version = if (Test-Path -LiteralPath $versionPath) { (Get-Content -LiteralPath $versionPath -Raw).Trim() } else { $null }

$result = [ordered]@{
    sourceId = 'code-collaboration'
    repository = 'https://github.com/SyuanTsai/Skill-Code-Collaboration.git'
    requestedRef = $Ref
    resolvedCommit = $resolvedCommit
    resolvedVersion = $version
    contentSha256 = $contentSha256
}

$result | ConvertTo-Json -Depth 4
