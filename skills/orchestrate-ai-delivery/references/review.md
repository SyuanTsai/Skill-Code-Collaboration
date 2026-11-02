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

Use the launch flags documented in [dispatch.md](dispatch.md). A review CLI must not belong to the same model family as the executor's model; self-review is not allowed. Prefer an executor choice that allows the reviewers to cover at least two model families.

Determine family from the model actually used, with the baseline list in [models.json](models.json). Do not infer family solely from a CLI name when it can run models from different families.

A review CLI is usable only when it can run and is logged in. Check its actual status; for example, `claude auth status` must report that it is logged in. If usability cannot be determined, report that uncertainty and do not assume the CLI is usable.

## Limited Situations Accepted by the User

### Exactly One Review CLI Remains

If the other CLI is excluded by the family rule, cannot run, or the controller and remaining CLI share a family:

1. Use the one remaining review CLI.
2. Raise its model capability by one tier according to [models.md](models.md).
3. State the limitation and its reason in the delivery.

The controller still performs its own review.

### No Review CLI Remains

If no review CLI remains, the controller reviews alone and the workflow continues; do not pause. State the actual reviewers and the reason in the delivery. For example: `claude` CLI not logged in; `codex` CLI excluded because the executor used an OpenAI model.

The controller's family and executor's family still count toward family coverage. When the complete review set covers only one family, say so in the delivery; the user decides whether to accept that coverage.

## Finding Policy

### Valid Findings

Fix valid findings to zero. A finding is valid when it shows one of these conditions:

- The objective is not achieved.
- An acceptance criterion is not met.
- The change introduces a functional bug or regression.
- A required test is missing or failing.
- Cross-Step integration is incorrect.
- A requirement listed in the Jira description is violated.

### Follow-up Items

Record these without stopping progress unless they make an acceptance criterion fail:

- Naming or style suggestions.
- Extra refactoring.
- Optimization.
- Hardening or checks not requested by the issue.
- Pre-existing problems unrelated to the change.

Use this tie-breaker: **Would this make an acceptance criterion fail?**

Collect all findings from one review round before dispatching fixes once. Merge small cleanups into a required fix only when that keeps the fix small and coherent.

Re-review the fixed part and related regressions. Treat new suggestions about unchanged code as follow-up items when they do not affect acceptance criteria.

## Jira Review Checklist

At the cumulative Jira Review, verify:

- Every acceptance criterion against the completed behavior.
- The cumulative diff, not only each isolated Step diff.
- Cross-Step integration and interactions.
- All required tests, run by the controller.
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

Limit the review to the Step objective and Jira acceptance criteria. Do not
raise hardening, refactoring, style, optimization, or extra features that the
issue did not request.

For every valid finding, cite the objective or acceptance criterion it breaks,
the repository-relative file and line, and concrete evidence. If there are no
valid findings, output exactly: No valid findings

Do not include local absolute paths or credentials in the output.
```

## Recording

In the delivery review summary, record each reviewer and model, every finding,
the decision (`valid` or `follow-up`), and the reason for that decision.
