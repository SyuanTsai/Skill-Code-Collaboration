<!--
SPDX-FileCopyrightText: 2026 SyuanTsai
SPDX-License-Identifier: Apache-2.0
-->

# Review

## Review Composition

Review every Step after implementation with:

- The controller, which retains the full Jira, Plan, and dispatch context.
- The `claude` CLI in a fresh read-only session for an independent view.
- The `codex` CLI in a fresh read-only session for an independent view.

Use the launch flags documented in [dispatch.md](dispatch.md). Before the completion gate, obtain review from at least one independent reviewer, not the controller. A cross-family review CLI must not belong to the executor's model family; self-review is not allowed. Prefer an executor choice that allows the reviewers to cover at least two model families.

Determine family from the model actually used, with the baseline list in [models.json](models.json). Do not infer family solely from a CLI name when it can run models from different families.

A review CLI is usable only when it can run and is logged in. Check its actual status; for example, `claude auth status` must report that it is logged in. If usability cannot be determined, report that uncertainty and do not assume the CLI is usable.

## Limited Situations Accepted by the User

### Exactly One Review CLI Remains

If the other CLI is excluded by the family rule, cannot run, or the controller and remaining CLI share a family:

1. Use the one remaining review CLI.
2. Raise its model capability by one tier according to [models.md](models.md).
3. State the limitation and its reason in the delivery.

The controller still performs its own review.

### No Cross-Family Review CLI Remains

If no cross-family review CLI remains, use a reviewer from the executor's family in a different fresh, read-only session. Use a review command or another model at C3 or higher; it must not be the executor session. Raise its model capability by one tier according to [models.md](models.md), where possible.

State the same-family review limitation, its reason, and the actual reviewers in the delivery. The controller still performs its own review.

### No Independent Reviewer Remains

Only when neither a cross-family nor same-family reviewer can run may the controller review alone. At the completion gate, explicitly tell the user that the change was not independently reviewed and let the user decide whether to accept it; do not claim that independent review confirmed zero valid findings. State the actual reviewer, the limitation, and its reason in the delivery.

## Finding Policy

### Valid Findings

Fix valid findings to zero. A finding is valid when it shows one of these conditions:

- The objective is not achieved.
- An acceptance criterion is not met.
- The change introduces a functional bug or regression.
- A required test is missing or failing.
- Cross-Step integration is incorrect.
- A requirement listed in the Jira description is violated.
- A path added by the change can bypass, weaken, or forge an existing check, validation, or evidence binding.

### Finding Sources

Apply this policy to findings from review CLIs and, after publication, failed PR CI and automated or human review comments on the PR. Return valid findings to the fix loop and repeat the pre-publication gate after fixing them.

### Follow-up Items

Record these without stopping progress when they do not satisfy a Valid Findings condition:

- Naming or style suggestions.
- Extra refactoring.
- Optimization.
- Hardening that only strengthens existing behavior; without it, the change is no weaker than before.
- Pre-existing problems unrelated to the change.

Use this tie-breaker: **Does this satisfy a Valid Findings condition?**

Collect all findings from one review round before dispatching fixes once. Merge small cleanups into a required fix only when that keeps the fix small and coherent.

Re-review the fixed part and related regressions. Treat new suggestions about unchanged code as follow-up items when they do not affect acceptance criteria.

## Jira Review Checklist

At the cumulative Jira Review, verify:

- Every acceptance criterion against the completed behavior.
- The cumulative diff, not only each isolated Step diff.
- Cross-Step integration and interactions.
- All required locally executable checks, run by the controller; remote-only CI remains in the post-publication finding loop.
- Each mandatory synchronization rule in repository instructions, such as `AGENTS.md`, `CONTRIBUTING`, and CI workflows.
- Every Jira acceptance criterion maps to a completed change; do not record an acceptance requirement as a follow-up. Follow-ups are only suggestions outside acceptance criteria.
- Every required test execution ran more than zero tests, and its passed plus skipped count equals its total.
- Select the test runner and version declared by the repository CI workflow, configuration, or tests. When a failure indicates incompatible runner semantics, verify that version before judging a finding.
- Scope: no out-of-scope files changed.
- Git state: no unauthorized commit exists.

## Review Prompt Template

```text
Perform a read-only review. Do not edit files, stage changes, commit, push,
or perform any other mutation.

Step objective:
<STEP_OBJECTIVE>

Jira acceptance criteria:
<ACCEPTANCE_CRITERIA>

Allowed files:
<ALLOWED_FILES>

Diff or range to review:
<DIFF_OR_RANGE>

Required tests:
<REQUIRED_TESTS>

Valid Findings conditions (replace this placeholder with the complete list from
the `Valid Findings` section above):
<VALID_FINDINGS>

Limit the review to the Step objective, Jira acceptance criteria, and Valid
Findings conditions. Do not raise hardening, refactoring, style, optimization,
or extra features that do not satisfy a Valid Findings condition.

For every valid finding, cite the applicable Valid Findings condition, the
repository-relative file and line, and concrete evidence. If there are no valid
findings, output exactly: No valid findings

Do not include local absolute paths or credentials in the output.
```

## Recording

In the delivery review summary, record each reviewer and model, every finding,
the decision (`valid` or `follow-up`), and the reason for that decision.
When a review CLI reports all-zero or missing usage, record usage as unavailable,
not as zero.
