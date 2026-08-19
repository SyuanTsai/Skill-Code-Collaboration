# Skill Code Collaboration

Independent Agent Skills source repository for code-delegation workflows.

- Stable source ID: `code-collaboration`
- Catalog: `catalog/skills-catalog.json`
- Current repository version: `0.1.0`

## Skills

| Skill | Profile | Purpose | Capability gate |
| --- | --- | --- | --- |
| `write-copilot-implementation-prompt` | `copilot` | Build self-contained GitHub Copilot implementation prompts and select an exact available model. | None |

Bitbucket pull-request review belongs to the separately versioned `Skill-Atlassian-Ecosystem` source so Atlassian credentials and product workflows have one ownership boundary.

## Repository layout

```text
.agents/skills/
  write-copilot-implementation-prompt/
    SKILL.md
    agents/openai.yaml
catalog/
  skills-catalog.json
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

Consumers discover this source through `catalog/skills-catalog.json`. The Copilot Skill uses `sourceId: code-collaboration` and the `copilot` profile.

Direct paths are stable within a pinned version:

- `.agents/skills/write-copilot-implementation-prompt`

Consumers should resolve a release tag to an immutable commit SHA and persist that SHA plus a reproducible repository content hash. `scripts/Get-SourcePin.ps1` produces the pin metadata used for that purpose.

## Validation

Run from the repository root:

```powershell
pwsh -File ./tests/validate-catalog.ps1
pwsh -File ./scripts/Get-SourcePin.ps1 -Ref HEAD
```

The GitHub Actions workflow runs catalog/layout validation for pull requests and pushes to `main`.

## Versioning and rollback

This repository is independently versioned. Release and pin rules are documented in `docs/RELEASE.md`. A consumer can roll back without modifying Skill content by restoring its previous source pin; see `docs/ROLLBACK.md`.

## Scope

This repository owns only Code Collaboration Skills and their directly required metadata, references, tests, and release contract. General AI instructions, unrelated Skills, and consumer-specific installation state belong outside this repository.
