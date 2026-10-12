<!--
SPDX-FileCopyrightText: 2026 SyuanTsai
SPDX-License-Identifier: Apache-2.0
-->
# Windows support and Skill inventory

Windows is the only supported host for local development, installation, execution, testing, acceptance, and CI for this repository. Use PowerShell (pwsh) for repository commands. Linux/macOS hosts, WSL, and Linux containers are unsupported.

All four GitHub Actions jobs run on windows-latest. The canonical Standard v1 validation remains the single policy gate; repository-contract, skill-validator, and skill-tools keep their existing status-context names and only mirror its result. The mirrors pass only when the canonical job result is exactly success.

## Per-Skill support matrix

The original values below were audited at the public pre-change foundation commit 53e5d340ba26ba4e5f0195a6466597d1560f0429 (tree b8f8abd838ba47e096f2a8c0689ff976596b9436).

| Skill | Original platform and content | Final host scope | Change and preservation reason | Evidence |
| --- | --- | --- | --- | --- |
| write-copilot-implementation-prompt | Catalog compatibility was any. SKILL.md frontmatter and body, plus UI metadata, were host-neutral. | Run this Skill on Windows. The catalog profile now states Windows support. | The prerequisite change updates catalog compatibility to windows. The reviewed Windows-host versions from public candidate c21efe3480f28fb90dd8735f011fa58f67be72fb (SKILL.md SHA-256 301effeb92806772ebdf11807459a4b1be5e5876859c8291224dd93a956ce71f; UI metadata SHA-256 3f17532b40fd136a6aa31bdc871bfa047bd3fb6e4aea284a89972c46126600d0) are deferred to PR12 after this prerequisite merges; the tracked files retain their e770 baseline bytes here. Preserve the original trigger for implement/fix/refactor/test prompts across consumer repositories, exact currently selectable model recommendation, and task-specific model rationale. Preserve target remote API/deployment semantics. If target local requirements conflict with Windows/PowerShell support, surface that conflict and ask for a supported path instead of offering Linux, WSL, or Linux-container alternatives. | skills/write-copilot-implementation-prompt/SKILL.md; skills/write-copilot-implementation-prompt/agents/openai.yaml; catalog/profiles.json |

## Tracked inventory and distribution audit

Counts use Git-tracked paths plus lifecycle metadata in the catalogs. The source inventory and opt-in profile contain exactly one active Skill; no dormant or bundled Skills are declared.

| Inventory | Count | Evidence paths | Decision or reason |
| --- | ---: | --- | --- |
| Active Skills | 1 | catalog/source.json; catalog/profiles.json | The stable source path resolves to the single active Skill. |
| Dormant Skills | 0 | catalog/profiles.json lifecycle records | No dormant lifecycle records exist. |
| Bundled Skills | 0 | catalog/source.json; PROVENANCE.md | No bundled Skill source or third-party source archive is included. |
| Skill instruction files | 1 | skills/write-copilot-implementation-prompt/SKILL.md | Retains the baseline reusable prompt-writing trigger and exact-model capability. The reviewed Windows-host wording is staged for PR12 after this prerequisite merges. |
| UI metadata files | 1 | skills/write-copilot-implementation-prompt/agents/openai.yaml | Retains the baseline display name and invocation ID. The reviewed Windows-host description and default prompt are staged for PR12 after this prerequisite merges. |
| Skill references | 0 | skills/write-copilot-implementation-prompt/ | No references directory or tracked reference file exists. |
| Skill-local scripts | 0 | skills/write-copilot-implementation-prompt/ | No scripts are bundled in the Skill. Repository validation scripts remain repository tools. |
| Skill assets | 0 | skills/write-copilot-implementation-prompt/ | No Skill-local asset file exists. |
| Standalone example files | 0 | Git-tracked repository paths | No standalone examples directory or tracked example files exist. The inline Markdown output-format template in SKILL.md was audited and retained because it contains no OS commands. |
| Profiles | 1 | catalog/profiles.json | The opt-in copilot profile includes only the active Skill and describes Windows-host support. |
| Source catalog entries | 1 | catalog/source.json | The source ID and repository URL remain unchanged. |
| Plugin or package manifests | 0 | Git-tracked repository paths | The only agents/openai.yaml file is the Skill UI metadata; no plugin or package manifest is tracked. |
| Dedicated installer or package | 0 | README.md; scripts/Get-SourcePin.ps1 | Distribution uses the stable catalog source path and immutable source-pin workflow; no installer/package manager is present. |

The tracked Skill folder contains only its instruction file and UI metadata file. The catalog profile changes compatibility from any to windows; its shells array and capability requirements remain unchanged. The catalog source ID and repository URL remain unchanged, and the profile description identifies Windows-host support. Reproduce the inventory with git ls-files -- skills, then inspect catalog/source.json and catalog/profiles.json. Check repository-level examples, plugin, and package manifests with git ls-files.

## Installation, validation, and CI

README.md documents the stable Skill source path and immutable source-pin approach; there is no separate installer. Local source validation uses scripts/Validate.ps1 through pwsh. The catalog inventory check is tests/validate-catalog.ps1. The required workflow is .github/workflows/validate.yml: canonical-validation and its three existing mirror contexts all use windows-latest; the mirror bodies use pwsh and fail for every canonical result other than success.

This support boundary describes where this repository and the Skill are supported. The reviewed Windows-host versions of the Skill instructions and UI metadata from public candidate c21efe3480f28fb90dd8735f011fa58f67be72fb are deferred to PR12 after this prerequisite merges; the tracked files retain their e770 baseline bytes in this change. The generated prompt will use Windows/PowerShell for local work while preserving the target's remote API/deployment semantics. A target requirement that conflicts with local Windows/PowerShell support must be surfaced for a supported path.

## Local runtime and normative boundaries

Repository-local AGENTS.md, .agents, .codex, and instruction-manifest artifacts supplied by the personal runtime remain ignored local files. They are not distributed Skills, catalog entries, examples, or supported installation payloads, and they are excluded from the counts above.

PROVENANCE.md and THIRD_PARTY_NOTICES.md remain provenance and external-tool boundary records. No third-party source is vendored. Historical commits, protected Standard v1 configuration and authority evidence, and release/source-pin contracts remain supporting or normative records; this host-scope change does not rewrite or reclassify them.
