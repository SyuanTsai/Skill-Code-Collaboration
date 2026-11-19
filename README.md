<!--
SPDX-FileCopyrightText: 2026 SyuanTsai
SPDX-License-Identifier: Apache-2.0
-->
# Skill Code Collaboration

Independent Agent Skills source repository for code-delegation workflows.

- Stable source ID: `code-collaboration`
- Source inventory: `catalog/source.json`
- Profile catalog: `catalog/profiles.json`
- Current version: `0.1.0`

## Skills

| Skill | Profile | Purpose |
| --- | --- | --- |
| `orchestrate-ai-delivery` | `ai-delivery` | Plan, dispatch, review, and gate delivery of one Jira issue through a selected controller and executor. |
| `write-implementation-prompt` | `ai-delivery` | Create a repository-scoped implementation prompt and recommend an exact available executor model. |

Name a Skill or make a request matching its description to invoke it. The orchestration Skill never commits, pushes, or writes Jira without the user's consent; work-environment Jira issues remain read-only.

## Repository contract

`catalog/source.json` is the canonical active-Skill inventory. `catalog/profiles.json` defines the opt-in `ai-delivery` profile and its dependency relationships. Stable package paths are:

- `skills/orchestrate-ai-delivery`
- `skills/write-implementation-prompt`

The repository-specific checks are:

- `scripts/Test-CodeCollaborationRepository.ps1`
- `scripts/Test-CodeCollaborationCatalog.ps1`
- the complete `tests/` Pester suite

The two PowerShell checks accept `-RepositoryRoot` and `-ReadOnlySnapshot`, operate on an extracted snapshot without Git metadata, and write results to standard output without changing the candidate.

## Consumer gate

Validation is owned by the pinned authority and runs through the `consumer-gate` workflow on Windows, Linux, and macOS. The repository bootstrap reads `config/authority-pin.json`; routine authority upgrades change only that file's `commit`. `config/consumer-gate.json` binds this repository, the active Skill inventory, and the three repository checks above.

The transition workflow is temporary during conversion. After conversion, the cleanup pull request removes only that workflow; the permanent gate, bootstrap, configuration, checks, and full test suite remain.

See [release](docs/RELEASE.md), [rollback](docs/ROLLBACK.md), [consumer-gate adoption](docs/SOURCE-VALIDATION-ADOPTION.md), and [cross-platform support](docs/WINDOWS-SUPPORT.md).

## License and scope

The Apache-2.0 license applies to repository-authored Skills, metadata, catalogs, documentation, checks, tests, and workflow configuration. External services, credentials, tenant data, and user-supplied content remain outside that grant. See [PROVENANCE.md](PROVENANCE.md) and [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

This repository owns only Code Collaboration Skills and their directly required metadata, references, tests, and release contract.
