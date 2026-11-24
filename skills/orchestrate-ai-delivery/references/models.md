<!--
SPDX-FileCopyrightText: 2026 SyuanTsai
SPDX-License-Identifier: Apache-2.0
-->

# Model selection and availability

Use [models.json](models.json) as the reviewed baseline for exact model IDs, ratings,
status, evidence, and supported reasoning-effort values. Availability is a separate,
machine-local observation and never edits that baseline.

## Ratings

Capability is the minimum problem-solving tier a Step requires:

- C4: cross-module design, authentication or security, concurrency, data consistency,
  and difficult diagnosis.
- C3: general multi-file implementation and the default reviewer level.
- C2: a direct change in one area or an ordinary fix.
- C1: formatting, small tests, and mechanical renames.

Cost is relative only within one CLI's billing unit:

- Codex cost is relative plan usage.
- Copilot cost is relative AI Credits.
- Claude cost is relative currency or subscription usage.
- Junie cost is relative to the per-run cost Junie reports.

K1 through K4 values are not comparable across CLIs. Across vendors, compare
capability first, then compare cost only within a model family. Evidence is
`official` when the dominant source is vendor or CLI documentation, `measured` when
the rating or fact comes from an observed run, and `inferred` when it is reasoned
from indirect evidence. Details and exceptions belong in each model's `notes`.
The Codex effort catalog includes `ultra`, but only models that expose it may use
that value.

## Selection rules

1. Pick the lowest capability tier that can complete the Step reliably.
2. At equal capability, pick the lower-cost model.
   At equal capability and cost, pick the entry listed first for that CLI in
   `models.json`. Entries are ordered newest generation first.
3. Default effort is `low` for C1, `medium` for C2 and C3, and `medium` for C4.
   Raise effort only for a concrete difficulty in that Step.
4. Use cheaper models and lower effort for routine additions, small fixes, test
   additions, and formatting.
5. Consider escalation only for authentication or security, concurrency, data
   consistency, or cross-module problems. Name the concrete difficulty when
   escalating; "more reliable" alone is not a reason.
6. Do not carry an expensive model or elevated effort forward from a previous Step
   by default.
7. State the exact model ID, effort, capability tier, the rating's `reviewedOn`
   date, and the reason for every delegated Step.
8. Never select a model whose baseline status is not `active` or whose availability
   cache status is not `available`.
9. When a candidate's rating is overdue (`reviewOverdue` is true), prefer a
   non-overdue model of the same capability. If only overdue models fit, select
   one and state "rating overdue since <date>" with the reason in the Plan.

Reviewers default to C3 or higher. In the limited situation where only one review
CLI is available, raise that reviewer by one capability tier.

## Work-type tiers

Planning, design trade-offs, and root-cause diagnosis belong to the controller and
are never dispatched. Before every dispatch, including each fix round, classify the
work and select from this table; when rows overlap, selection rule 1 applies and the
lowest capable row wins. The Codex column shows the current baseline IDs;
for another CLI, pick the cheapest `active` model of the same capability.

| Work type | Capability and effort | Codex example |
| --- | --- | --- |
| Implement a new Step from a precise controller spec, including normative changes | C3, `medium` | `gpt-5.6-sol` `medium` |
| Precise spec, but the implementation itself is hard, such as native interop or race handling | C4, or C3 `high` | `gpt-6-astra`, or `gpt-5.6-sol` `high` |
| Fix whose root cause the controller has located | C3 `medium`, or C2 | `gpt-5.6-sol` `medium`, or `gpt-5.6-terra` |
| Mechanical work, either a new Step or a fix, such as a rename, formatting, small test addition, test-syntax fix, revert, or hash update | C2 or C1 | `gpt-5.6-terra` or `gpt-5.6-luna` |
| Independent review | C3 `high`; C3 `medium` for a small diff | `gpt-5.6-sol` `high`, or `medium` |

For implementation and fix dispatches, use C4 only when the work, including a fix
round, matches the hard-implementation row. Required reviewer escalation in the
limited situations of [review.md](review.md) is separate and may raise a reviewer
to C4. An open-ended task such as "find the
root cause and fix it" is a sign that the controller has not finished planning or
diagnosis; complete that work instead of escalating the model.

**Self-check:** when two consecutive fix rounds of the same Step used C4, stop and
re-examine the spec. List every root cause the controller can locate from logs and
code, turn the fix into a precise spec, and classify it again before the next
dispatch.

## Weekly availability check

Run `scripts/Update-ModelAvailability.ps1` when a cache is missing or before the
first dispatch after the most recent Monday 00:00 in Taipei (UTC+08:00). The script
checks `personal` and `work` independently and writes
`model-availability.<environment>.json` outside the managed Skill directory.

The default cache locations are:

- Windows: `$env:LOCALAPPDATA/orchestrate-ai-delivery`
- macOS: `~/Library/Caches/orchestrate-ai-delivery`
- Linux: `$env:XDG_CACHE_HOME/orchestrate-ai-delivery`, or
  `~/.cache/orchestrate-ai-delivery` when `XDG_CACHE_HOME` is unset

Use PowerShell 7 on every platform:

```powershell
pwsh -File <skill>/scripts/Update-ModelAvailability.ps1 -Environment personal
pwsh -File <skill>/scripts/Update-ModelAvailability.ps1 -Environment work
```

The normal invocation returns the cache without probing when it is fresh for the
current Taipei week. The check covers `claude`, `codex`, `copilot`, and `junie`.
Junie uses `junie list-models` without calling a model. Provide empty input on
stdin because Junie fails when stdin is a null device. Junie may automatically
apply a staged update at startup.

An available ID that is absent from the baseline is recorded
as `unevaluated`, is never auto-selected, and produces a suggestion to update
`references/models.json` by pull request after rating it.

The result includes a `review` field with the age limit, overdue active
ratings, and unevaluated models, including newly discovered IDs. Each model
record has `reviewedOn` and `reviewOverdue`. Warnings prefixed with `review: `
list overdue ratings and summarize how many models need a rating. Review data
and warnings are recalculated even when the availability cache is fresh.

If a dispatched model fails, re-check its CLI immediately, ignoring weekly
freshness:

```powershell
pwsh -File <skill>/scripts/Update-ModelAvailability.ps1 -Environment personal -Cli codex -Force
```

When a probe is offline, times out, or returns unexpected output, retain that CLI's
existing entries, mark them stale, and report "availability not updated". This does
not block other CLIs or dispatch through previously known available models. A cache
with any stale CLI is retried on the next invocation even when it was written during
the current Taipei week.

## Rating review

Each baseline entry has a `reviewedOn` date. The `reviewMaxAgeDays` limit is 30
days, measured using Taipei calendar dates. The weekly availability check
reports active ratings older than that limit and models that are unevaluated.

Run or schedule the rating check without probing CLIs or writing caches:

```powershell
pwsh -File <skill>/scripts/Update-ModelAvailability.ps1 -Environment personal -ReviewOnly
```

For example, in Windows Task Scheduler, run it at 09:00 on the first day of
each month:

```cmd
schtasks /Create /SC MONTHLY /D 1 /ST 09:00 /TN "orchestrate-ai-delivery rating review" /TR "pwsh -NoProfile -File <skill>\scripts\Update-ModelAvailability.ps1 -Environment personal -ReviewOnly"
```

The command outputs JSON. Redirect it to a file or check the result in your next
conversation.

When re-rating a model, use vendor documentation or the CLI catalog
(`official`), observed delegated runs and usage (`measured`), or indirect
evidence (`inferred`). Update `capability`, `cost`, `status`, `evidence`,
`notes`, and `reviewedOn`, then open a pull request. List each change and its
evidence in the pull request description.

Claude CLI does not list models. A nonexistent ID fails before invocation with
`unrecognized_model` and incurs no charge. Older IDs the CLI still accepts,
such as `claude-fable-5-1`, run a model and incur charges. Use the vendor's
model list to review Claude ratings because the weekly availability check
cannot establish which models Claude offers.

## Baseline source and maintenance

The `references/models.json` file on the repository's main branch is the single
source. `Update-ModelAvailability.ps1` refreshes a local copy once per Taipei week
from
`https://raw.githubusercontent.com/SyuanTsai/Skill-Code-Collaboration/main/skills/orchestrate-ai-delivery/references/models.json`.
It falls back first to the local copy and then to the bundled list, and reports
which source it used.

Model information comes only from the vendor CLIs on the user's machine because
company policy can restrict which models are available. GitHub-hosted CI has no
logged-in CLI, so CI does not discover models; it validates the baseline format
through the Pester baseline-integrity test.

To update the baseline, run `Update-ModelAvailability.ps1` for each environment,
then run:

```powershell
pwsh -File <skill>/scripts/Update-ModelBaseline.ps1 -BaselinePath <repository>/skills/orchestrate-ai-delivery/references/models.json
```

The updater reconciles models from `codex`, `copilot`, and `junie`. New IDs are
added as `unevaluated`. IDs that their CLI does not list in either current
environment (`personal` and `work`) become `unavailable`. Claude is skipped because
its CLI does not list models. Rate new entries, include evidence for ratings, status, and aliases, and
open a pull request. Review cost and capability claims independently of local
availability. The local cache records observations only; it never adds to,
removes from, or changes the reviewed baseline.
