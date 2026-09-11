<!--
SPDX-FileCopyrightText: 2026 SyuanTsai
SPDX-License-Identifier: Apache-2.0
-->
# Skill Code Collaboration

Independent Agent Skills source repository for code-delegation workflows.

- Stable source ID: `code-collaboration`
- Source inventory: `catalog/source.json`
- Profile catalog extension: `catalog/profiles.json`
- Current repository version: `0.1.0`

## Skills

| Skill | Profile | Purpose | Capability gate |
| --- | --- | --- | --- |
| `write-copilot-implementation-prompt` | `copilot` | Build self-contained GitHub Copilot implementation prompts and select an exact available model. | None |

Bitbucket pull-request review belongs to the separately versioned `Skill-Atlassian-Ecosystem` source so Atlassian credentials and product workflows have one ownership boundary.

## Repository layout

```text
skills/
  write-copilot-implementation-prompt/
    SKILL.md
    agents/openai.yaml
catalog/
  profiles.json
docs/
  RELEASE.md
  ROLLBACK.md
scripts/
  Get-SourcePin.ps1
tests/
  validate-catalog.ps1
.github/workflows/
  validate.yml
VERSION
```

## Discovery and selection

Consumers discover this source through the canonical `catalog/source.json` inventory. The domain-specific `catalog/profiles.json` retains the opt-in `copilot` profile and selection metadata.

Direct paths are stable within a pinned version:

- `skills/write-copilot-implementation-prompt`

Consumers should resolve a release tag to an immutable commit SHA and persist that SHA plus a reproducible repository content hash. `scripts/Get-SourcePin.ps1` produces the pin metadata used for that purpose.

## Validation

Run from the repository root:

```powershell
pwsh -File ./scripts/Validate.ps1
```

The GitHub Actions workflow runs the canonical Standard v1 validation for pull requests and pushes. Component scripts are not additional public validation gates. Use `scripts/Get-SourcePin.ps1 -Ref HEAD` separately when producing source-pin metadata.

## Versioning and rollback

This repository is independently versioned. Release and pin rules are documented in `docs/RELEASE.md`. A consumer can roll back without modifying Skill content by restoring its previous source pin; see `docs/ROLLBACK.md`.

## License and contribution boundary

The Apache-2.0 license in [LICENSE](LICENSE) applies to the repository-authored Skill instructions, agent metadata, catalog data, documentation, validation scripts, tests, and workflow configuration in this repository. It does not grant rights to external services, GitHub/Copilot product materials, consumer prompts or outputs, credentials, tenant data, or other content supplied by a user.

The repository does not vendor third-party source code. CI and developer tools are listed in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md); their upstream terms remain applicable. The evidence and file-by-file decision record is [PROVENANCE.md](PROVENANCE.md).

Contributors must have the right to submit their contribution. Unless a separate written agreement says otherwise, an intentional contribution to this repository is submitted under Apache-2.0; contributors must preserve existing notices and identify material that is not their own.

## Scope

This repository owns only Code Collaboration Skills and their directly required metadata, references, tests, and release contract. General AI instructions, unrelated Skills, and consumer-specific installation state belong outside this repository.
