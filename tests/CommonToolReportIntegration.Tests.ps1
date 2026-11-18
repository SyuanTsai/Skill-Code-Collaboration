# SPDX-FileCopyrightText: 2026 SyuanTsai
# SPDX-License-Identifier: Apache-2.0
$ErrorActionPreference = 'Stop'

BeforeAll {
    . (Join-Path $PSScriptRoot 'ResolveLegacyAuthorityArchiveFixture.ps1')
    $script:RepositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
    $script:RepositoryCheck = Join-Path $script:RepositoryRoot 'scripts/Test-CodeCollaborationRepository.ps1'
    $script:CatalogCheck = Join-Path $script:RepositoryRoot 'scripts/Test-CodeCollaborationCatalog.ps1'
    $script:PowerShell = (Get-Process -Id $PID).Path

    function Invoke-GeneralCheckProcess {
        param(
            [Parameter(Mandatory)][string] $ScriptPath,
            [Parameter(Mandatory)][string] $CandidateRoot,
            [switch] $WithoutPath
        )

        $start = [Diagnostics.ProcessStartInfo]::new()
        $start.FileName = $script:PowerShell
        $start.WorkingDirectory = $CandidateRoot
        $start.UseShellExecute = $false
        $start.RedirectStandardOutput = $true
        $start.RedirectStandardError = $true
        foreach ($argument in @('-NoProfile', '-NonInteractive', '-File', $ScriptPath, '-RepositoryRoot', $CandidateRoot, '-ReadOnlySnapshot')) {
            [void]$start.ArgumentList.Add($argument)
        }
        if ($WithoutPath) { $start.Environment['PATH'] = '' }
        $process = [Diagnostics.Process]::new()
        try {
            $process.StartInfo = $start
            [void]$process.Start()
            $stdout = $process.StandardOutput.ReadToEndAsync()
            $stderr = $process.StandardError.ReadToEndAsync()
            $process.WaitForExit()
            [pscustomobject]@{
                ExitCode = $process.ExitCode
                Stdout = $stdout.GetAwaiter().GetResult()
                Stderr = $stderr.GetAwaiter().GetResult()
            }
        }
        finally { $process.Dispose() }
    }

    function New-IntegrationFixture {
        $root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        Copy-CodeCollaborationFixture -RepositoryRoot $script:RepositoryRoot -DestinationRoot $root
    }
}

Describe 'Consumer general check process integration' {
    It 'runs the repository check in a snapshot without Git metadata or a Git executable path' {
        $fixture = New-IntegrationFixture
        Test-Path -LiteralPath (Join-Path $fixture '.git') | Should -BeFalse
        $result = Invoke-GeneralCheckProcess -ScriptPath $script:RepositoryCheck -CandidateRoot $fixture -WithoutPath
        $result.ExitCode | Should -Be 0
        $result.Stderr | Should -BeNullOrEmpty
        ($result.Stdout | ConvertFrom-Json).result | Should -BeExactly 'passed'
    }

    It 'runs the catalog check in a snapshot without Git metadata or a Git executable path' {
        $fixture = New-IntegrationFixture
        $result = Invoke-GeneralCheckProcess -ScriptPath $script:CatalogCheck -CandidateRoot $fixture -WithoutPath
        $result.ExitCode | Should -Be 0
        $result.Stderr | Should -BeNullOrEmpty
        ($result.Stdout | ConvertFrom-Json).result | Should -BeExactly 'passed'
    }

    It 'emits machine-readable JSON for both declared general checks' {
        $fixture = New-IntegrationFixture
        foreach ($check in @($script:RepositoryCheck, $script:CatalogCheck)) {
            $result = Invoke-GeneralCheckProcess -ScriptPath $check -CandidateRoot $fixture
            $value = $result.Stdout | ConvertFrom-Json -Depth 50
            $result.ExitCode | Should -Be 0
            $value.schemaVersion | Should -Be 1
            $value.result | Should -BeExactly 'passed'
        }
    }

    It 'leaves the candidate bytes unchanged after both checks' {
        $fixture = New-IntegrationFixture
        $before = Get-CodeCollaborationTreeDigest -Root $fixture
        (Invoke-GeneralCheckProcess -ScriptPath $script:RepositoryCheck -CandidateRoot $fixture).ExitCode | Should -Be 0
        (Invoke-GeneralCheckProcess -ScriptPath $script:CatalogCheck -CandidateRoot $fixture).ExitCode | Should -Be 0
        (Get-CodeCollaborationTreeDigest -Root $fixture) | Should -BeExactly $before
    }

    It 'returns nonzero when the repository contract is mutated' {
        $fixture = New-IntegrationFixture
        [void](New-Item -ItemType Directory -Path (Join-Path $fixture 'skills/.unexpected') -Force)
        $result = Invoke-GeneralCheckProcess -ScriptPath $script:RepositoryCheck -CandidateRoot $fixture
        $result.ExitCode | Should -Not -Be 0
        $result.Stderr | Should -Match 'inventory does not exactly match'
    }

    It 'returns nonzero when the catalog contract is mutated' {
        $fixture = New-IntegrationFixture
        $path = Join-Path $fixture 'catalog/profiles.json'
        $catalog = Get-Content -Raw -LiteralPath $path | ConvertFrom-Json -Depth 30
        $catalog.skills[0].source.path = 'skills/wrong'
        Write-CodeCollaborationJson -Path $path -Value $catalog
        $result = Invoke-GeneralCheckProcess -ScriptPath $script:CatalogCheck -CandidateRoot $fixture
        $result.ExitCode | Should -Not -Be 0
        $result.Stderr | Should -Match 'source path must exactly match'
    }
}
