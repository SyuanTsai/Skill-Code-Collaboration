<!--
SPDX-FileCopyrightText: 2026 SyuanTsai
SPDX-License-Identifier: Apache-2.0
-->
# Consumer gate adoption

The authority-published consumer gate is the only validation orchestrator for this repository. The bootstrap reads `config/authority-pin.json`, acquires the exact immutable authority revision, and runs the declared repository checks on Windows, Linux, and macOS.

`config/consumer-gate.json` declares:

- repository identity `skill-code-collaboration`;
- the active Skills from `catalog/source.json`;
- `scripts/Test-CodeCollaborationRepository.ps1` as the repository-domain check;
- `scripts/Test-CodeCollaborationCatalog.ps1` as the catalog check; and
- `tests/` as the complete Pester check.

Both general checks accept `-RepositoryRoot` and `-ReadOnlySnapshot`. They require no `.git` directory, do not invoke Git in snapshot mode, enumerate hidden entries, use ordinal ordering, and do not write into the candidate.

The conversion pull request includes the permanent and transition workflows. The transition workflow invokes the bootstrap in conversion mode. After conversion merges, a cleanup pull request deletes only the transition workflow. The permanent consumer gate then validates the same repository checks and complete Pester suite for future changes.

Routine authority upgrades modify only the `commit` in `config/authority-pin.json`. The copied bootstrap and workflow templates remain byte-identical to the published authority templates.
