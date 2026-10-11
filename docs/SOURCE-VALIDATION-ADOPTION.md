<!--
SPDX-FileCopyrightText: 2026 SyuanTsai
SPDX-License-Identifier: Apache-2.0
-->
# Protected source-validation adoption

This document describes an opt-in preparation and validation route for a future candidate whose `config/standard-v1.json` contains the exact approved ff85 authority tuple. The active candidate and required CI gate remain on the 8a authority pin and the canonical Standard v1 check. These commands do not make source validation a required release or CI gate.

Use the verified ff85 authority Git checkout and an immutable event-base commit. Check out that base separately as the trusted driver, with its Git HEAD equal to the base commit. The candidate is a separate clean Git checkout containing the future authority configuration. Both checkouts must preserve the committed bytes; on Windows, use `core.autocrlf=false` and `core.eol=lf` before checkout. Prepare a fresh run-owned tool closure once, then execute source validation with that same prepared file:

```powershell
$sourceTools = Join-Path $env:RUNNER_TEMP 'code-collaboration/source-tools.json'
$authorityRoot = '<verified ff85 authority Git checkout>'
$baseCommit = '<immutable event-base commit SHA>'
$protectedDriver = Join-Path '<trusted event-base checkout>' 'scripts/Validate.ps1'
$candidateRoot = '<clean immutable candidate Git checkout>'

pwsh -File $protectedDriver -RepositoryRoot $candidateRoot -AdapterVersion 2 -PrepareSourceTools `
  -SourceToolsPath $sourceTools -AuthorityRepositoryRoot $authorityRoot `
  -TrustedToolRoot $PSHOME -BaseCommit $baseCommit -TimeoutSeconds 10800

pwsh -File $protectedDriver -RepositoryRoot $candidateRoot -AdapterVersion 2 -SourceValidation `
  -SourceToolsPath $sourceTools -AuthorityRepositoryRoot $authorityRoot `
  -TrustedToolRoot $PSHOME -BaseCommit $baseCommit `
  -ArtifactsRoot (Join-Path $env:RUNNER_TEMP 'code-collaboration/core-v2') `
  -TimeoutSeconds 10800
```

Preparation resolves the central validation tools once and stores their receipts, a run-owned PowerShell/Pester closure, the candidate archive and Git entry-mode manifest, and frozen input hashes beside `source-tools.json`. Use a new output path for every preparation. `setup-timing.json` inside the run-owned source-tools directory records stage durations; `source-tools-setup-completed-<runId>.json` beside `source-tools.json` records the completed setup wall time after frozen-file verification; source execution writes `source-validation-timing-<runId>.json` beside the Core artifacts. Together these records include per-tool setup durations, inventory/hash/sort time, setup total, validation time, and setup-to-validation wall time. The 1200-second target is diagnostic evidence only and does not fail a run. Retain the setup timing files and the source-validation timing file with the validation report when using this adoption path.

The candidate's Core check wrappers and checker dependencies must be byte-identical to the trusted base: `scripts/Invoke-RepositoryCheck.ps1`, `scripts/Invoke-CorePester.ps1`, `scripts/CorePesterIntegrity.psm1`, `scripts/Test-Repository.ps1`, and `tests/validate-catalog.ps1`. Preparation and execution reject substitutions, including a changed run-owned checker copy with a matching replacement metadata hash. Changes to this protected foundation require preparation in the base before adopting it in a later candidate.

Each setup is create-only and gets a fresh run ID. Do not reuse a prepared file after changing the candidate, authority checkout, runtime, or tool closure. For release and rollback rules, see [RELEASE.md](RELEASE.md) and [ROLLBACK.md](ROLLBACK.md).
