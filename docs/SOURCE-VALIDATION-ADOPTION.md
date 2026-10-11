<!--
SPDX-FileCopyrightText: 2026 SyuanTsai
SPDX-License-Identifier: Apache-2.0
-->
# Protected full-source validation

The required Windows CI gate runs protected full-source validation for the active `config/standard-v1.json` ff85 authority tuple and its complete 32-file closure. The workflow checks out the immutable event-base driver, clean candidate, and verified ff85 authority Git tree separately, then performs one fresh run-owned setup followed by full source validation with the same prepared `source-tools.json`. The legacy unqualified `Validate.ps1` route remains available as a historical regression path; it is not a substitute for the required gate.

## Hosted Node/npm runtime

The Windows gate pins its host runtime with `actions/setup-node` v7.1.0 at commit `949feb2413d6458794dcd2491c4babbbce0c15c1`, using Node `24.21.0` on `x64`. It disables setup-node's package-manager cache and does not configure a registry or mirror. Before native tool preparation, the workflow verifies the PATH-first `node.exe` and `npm.cmd`, requires both paths to share one runtime root, checks Node `v24.21.0`, npm `11.19.0`, and npm package metadata, and checks the Node executable against the official SHA-256 `ba4e6d110e8c1592a1ecd390f6b05f3da124b13871a5be62b341a07a853c6c32`. It writes the selected paths, versions, and raw SHA-256 values for `node.exe`, `npm.cmd`, `npm-cli.js`, and npm's `package.json` to `runner.temp/code-collaboration/runtime-identity.json`, which is retained with the resolver receipts. The [official Node.js v24.21.0 release archive](https://nodejs.org/en/download/archive/v24.21.0) lists npm `11.19.0`; its [official SHA-256 manifest](https://nodejs.org/download/release/v24.21.0/SHASUMS256.txt) records `158f7685b44de51f6c0df1d153526cbcd3e1bc739a8dfc607721cef75de9e541` for `node-v24.21.0-win-x64.zip` and the executable hash above for `win-x64/node.exe`.

This host pin addresses npm lock generation while the central resolver continues to select the latest stable `skill-tools` package under its existing policy. A controlled comparison resolved the same `skill-tools@0.4.1` package and SHA-512 integrity with both Node/npm pairs: Node `22.23.3` / npm `10.9.9` produced an additional `standard-validation-npm-work=file:../npm-environment` root dependency that the central lock validator rejected, while Node `24.21.0` / npm `11.19.0` produced a lock accepted by that validator. The hosted failed lock was not retained, so this is a controlled runtime comparison rather than a byte-for-byte replay of that hosted failure.

## Hosted Go runtime

The workflow keeps the approved `actions/setup-go` v7.0.0 action at its full commit SHA with stable release selection, `check-latest: true`, and cache disabled. It resolves the PATH-first `go.exe`, verifies the stable version, and inventories the selected runtime's complete directory and file closure. If the selected runtime root is a junction, the workflow resolves it for read-only access; nested reparse entries fail the step. It copies the complete runtime into a fresh GUID directory directly under `runner.temp`, outside the uploaded `code-collaboration` evidence tree, then compares source and materialized relative paths, lengths, and raw SHA-256 values and rechecks the materialized `go.exe` version and hash. The workflow does not write to the hosted toolcache.

It retains the selected, physical source, and materialized paths, the complete inventory, closure digests, and executable identity under `runner.temp/code-collaboration/go-runtime-identity.json` and `go-runtime-inventory.json`. Later validation uses only the materialized `bin` through `GITHUB_PATH` and its root through `GOROOT`.

## Authenticated hosted source acquisition

The workflow grants the built-in `GITHUB_TOKEN` only to the `Prepare source tools once` step while retaining job permission `contents: read`. The protected ff85 resolver uses that token in its GitHub API request headers, then removes authorization headers and `GITHUB_TOKEN`/`GH_TOKEN` from SkillSpector’s managed Python and pip child environment. The workflow does not set a job-wide token or retain it in validation evidence.

### Updating the hosted Node/npm runtime

Changing either pinned version requires the same npm lock comparison against the immutable ff85 resolver and lock validator, including the resolved `skill-tools` version/integrity and resulting root dependency shape. Update the version and executable identity together from the official release archive and signed checksum material, then pass the focused workflow regression, exact-head CI, and a fresh complete full-source validation before adopting the change. A passing npm experiment alone does not establish that the hosted gate is ready.

## Local full-source validation

Use the verified ff85 authority Git checkout and an immutable event-base commit. Check out that base separately as the trusted driver, with its Git HEAD equal to the base commit. The candidate is a separate clean Git checkout containing the active approved ff85 authority configuration. Both checkouts must preserve the committed bytes; on Windows, use `core.autocrlf=false` and `core.eol=lf` before checkout. Prepare a fresh run-owned tool closure once, then execute source validation with that same prepared file:

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

Preparation resolves the central validation tools once and stores their receipts, a run-owned PowerShell/Pester closure, the candidate archive and Git entry-mode manifest, and frozen input hashes beside `source-tools.json`. Use a fresh output path and run ID for every preparation. `setup-timing.json` inside the run-owned source-tools directory records stage durations; `source-tools-setup-completed-<runId>.json` beside `source-tools.json` records completed setup wall time after frozen-file verification; source execution writes `source-validation-timing-<runId>.json` beside the Core artifacts. Together these records include per-tool setup durations, inventory/hash/sort time, setup total, validation time, central runner time, and setup-to-validation wall time. The 1200-second target is diagnostic evidence only and does not fail a run. CI retains the report, raw process output, native reports, Pester case inventory, setup receipts, metadata, and timing records while omitting bulky installed runtime/tool payloads.

The candidate's Core check wrappers and checker dependencies must be byte-identical to the trusted base: `scripts/Invoke-RepositoryCheck.ps1`, `scripts/Invoke-CorePester.ps1`, `scripts/CorePesterIntegrity.psm1`, `scripts/Test-Repository.ps1`, and `tests/validate-catalog.ps1`. Preparation and execution reject substitutions, including a changed run-owned checker copy with a matching replacement metadata hash. Changes to this protected foundation require preparation in the base before adopting it in a later candidate.

Each setup is create-only and gets a fresh run ID. Do not reuse a prepared file after changing the candidate, authority checkout, runtime, or tool closure. The source validation timeout is 10800 seconds; the 1200-second timing target is diagnostic only. The required status remains failed when setup or validation fails. For release and rollback rules, see [RELEASE.md](RELEASE.md) and [ROLLBACK.md](ROLLBACK.md).
