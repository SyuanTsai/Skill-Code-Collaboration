<!--
SPDX-FileCopyrightText: 2026 SyuanTsai
SPDX-License-Identifier: Apache-2.0
-->
# Provenance and licensing boundary

- Repository: [Skill-Code-Collaboration](https://github.com/SyuanTsai/Skill-Code-Collaboration)
- Audited baseline: [`2d864e4b0ee0f9e2a0cc00dab29cf2f1cfdae45d`](https://github.com/SyuanTsai/Skill-Code-Collaboration/tree/2d864e4b0ee0f9e2a0cc00dab29cf2f1cfdae45d)
- Review date: 2026-09-04

## Confirmed current-tree facts

The baseline tree contains one generic Skill, its agent metadata, catalog data, release/rollback documentation, PowerShell validation and source-pin scripts, tests, and GitHub Actions workflow configuration. A current-tree blob and path audit found no vendored third-party source, binary dependency, credential, tenant data, private Jira URL, private prompt corpus, or other private company material.

The repository's authored Skill, metadata, catalog, documentation, scripts, tests, and workflow configuration are the scope covered by Apache-2.0. The repository has no bundled external source archive. The previous repository PRs remain part of the public history and were not rewritten.

## Evidence and source timeline

- Baseline tree/blob inventory: [GitHub tree at `2d864e4b0ee0f9e2a0cc00dab29cf2f1cfdae45d`](https://github.com/SyuanTsai/Skill-Code-Collaboration/tree/2d864e4b0ee0f9e2a0cc00dab29cf2f1cfdae45d).
- Earlier repository changes: [PR #1](https://github.com/SyuanTsai/Skill-Code-Collaboration/pull/1) and [PR #2](https://github.com/SyuanTsai/Skill-Code-Collaboration/pull/2).
- The audit was performed against the current default branch commit, not historical line counts.

## Third-party and excluded material

GitHub Actions, the skill validator, skill-tools, PowerShell, Go, Node.js, npm, GitHub, and Copilot are referenced as external tools or services and are not vendored or relicensed here. Their upstream terms apply. Consumer prompts, generated outputs, credentials, account/tenant content, external service content, and future user-supplied material are outside this repository's Apache-2.0 grant.

No additional license is asserted for material that is later added without a provenance review. Historical commits remain historical evidence; this document does not rewrite their authorship or retroactively change third-party rights.

## Decision and limits

Decision: apply Apache-2.0 to the confirmed repository-authored current-tree scope and preserve upstream terms for external dependencies. This is a repository source record, not a legal opinion. The audit confirms the current tree only; it does not establish rights in external services, consumer content, or unreviewed future additions.