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
3. Default effort is `low` for C1, `medium` for C2 and C3, and `medium` for C4.
   Raise effort only for a concrete difficulty in that Step.
4. Use cheaper models and lower effort for routine additions, small fixes, test
   additions, and formatting.
5. Consider escalation only for authentication or security, concurrency, data
   consistency, or cross-module problems. Name the concrete difficulty when
   escalating; "more reliable" alone is not a reason.
6. Do not carry an expensive model or elevated effort forward from a previous Step
   by default.
7. State the exact model ID, effort, and reason for every delegated Step.
8. Never select a model whose baseline status is not `active` or whose availability
   cache status is not `available`.

Reviewers default to C3 or higher. In the limited situation where only one review
CLI is available, raise that reviewer by one capability tier.

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
current Taipei week. An available ID that is absent from the baseline is recorded
as `unevaluated`, is never auto-selected, and produces a suggestion to update
`references/models.json` by pull request after rating it.

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

## Maintenance

Change `models.json` only by pull request and include evidence for ratings, status,
and aliases. Review cost and capability claims independently of local availability.
The local cache records observations only; it never adds to, removes from, or
changes the reviewed baseline.
