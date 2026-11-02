---
name: orchestrate-ai-delivery
description: Plan one Jira issue into Steps, dispatch each to claude, codex, or copilot CLI or a built-in sub agent with an explicit model, review diffs, fix valid findings, run required tests, and stop at a human gate. Use when asked to drive or delegate a Jira issue's implementation.
---
<!--
SPDX-FileCopyrightText: 2026 SyuanTsai
SPDX-License-Identifier: Apache-2.0
-->

# Orchestrate AI Delivery

## Setup

### Inputs

Collect the controller AI, Jira issue key, repository and branch, and execution mode (`external CLI` or `built-in sub agent`). If execution mode is missing, ask; never assume it. Ask only for truly missing required information. Show routine model choices made under [references/models.md](references/models.md) in the Plan instead of asking about each one again.

### Environment Boundary

Determine the environment from the issue-key prefix using the user's local prefix-to-environment mapping. That mapping is user-local configuration and must not be stored in a repository.

- Work environment (`ROAR-`): Jira is read-only. Keep progress, review results, and delivery in the conversation or local files.
- Private environment (`SYP-`): before any Jira write, preview the write, name the environment and site, and obtain user consent.
- If the environment cannot be determined or signals conflict, stop and ask.

Only Jira, Git, and CLIs are in scope. Confluence is not.

### Roles

- **Controller:** read Jira, plan, select models, dispatch, review, judge findings, run required tests itself, and stage changes. Never commit or push without user consent.
- **Executor:** use the selected external CLI or built-in sub agent to implement code and tests within the Step scope. Never commit or push.
- **Review CLI:** run `claude` and `codex` CLI in fresh read-only sessions as described in [references/review.md](references/review.md).

## Workflow

### Core Principles

- Base the Plan, Steps, and Review on the Jira description and acceptance criteria. Comments and handoffs are supplementary; a comment explicitly marked authoritative overrides the description.
- Map every change to the objective or an acceptance criterion.
- Preserve progress: reviewer suggestions not required by the issue, including hardening, refactoring, style, and extra features, become follow-up items and do not stop delivery.
- Review and findings occur after implementation.
- Define pre-publication required checks as Jira-named tests plus affected CI tests reproducible locally, such as licensing or inventory tests for new tracked files. The controller runs them, selects the repository-declared runner version, and confirms every execution ran more than zero tests; remote-only CI belongs to the post-publication loop.

### Steps

1. **Plan:** Before planning, read repository instructions and CI workflows. Define the Objective, Acceptance Criteria, Scope, required Steps, and verification method; include their mandatory synchronization rules, affected locally reproducible CI checks, and remote workflows, and map every Jira acceptance criterion to a Step. Choose each Step's executor and the review CLIs, each with an exact model and effort, using [references/models.md](references/models.md) and show them in the Plan. Run independent Steps in parallel, each in its own Git worktree when it touches the repository.
2. **Dispatch:** Produce every Step prompt with the `write-implementation-prompt` Skill, including objective, allowed files, scope, acceptance criteria, required tests, and completion report. Launch it with the executor and model chosen in the Plan using [references/dispatch.md](references/dispatch.md).
3. **Step Review:** Have the controller and review CLI both review the implemented Step using [references/review.md](references/review.md).
4. **Judge findings:** Verify that each finding exists and satisfies a [Valid Findings](references/review.md#valid-findings) condition before dispatching a fix. Use the smallest fix; record everything else as a follow-up item.
5. **Fix and re-review:** Re-review only the fixed part and related regressions.
6. **Jira Review:** After all required Steps, check the full acceptance criteria, cumulative changes, cross-Step integration, required tests, and final diff.
7. **Completion gate:** This is the pre-publication gate: request approval to commit, push, and open a PR only after independent review reaches zero valid findings and required checks pass. If no independent reviewer can run, explicitly tell the user and ask whether to accept the unreviewed change as required by [references/review.md](references/review.md). After publication, read PR CI and review comments; judge valid findings under [references/review.md](references/review.md), return them to Step 4, and repeat the pre-publication gate after fixing them. If a correction changes Jira content already written, include that correction in the next Jira-write preview. Deliver in the conversation and wait for user confirmation before starting the next Jira issue. Keep this gate by default and adjust it only when the task explicitly asks. Independent work may continue while waiting.

## Issues and Situations

- **Partial completion:** Deliver completed Steps with evidence; list incomplete Steps, reasons, and remaining work. Do not claim the issue is done.
- **Integration failure:** When Steps pass alone but fail together, treat this as a valid Jira Review finding, identify the conflicting Steps, and dispatch one integration fix.
- **Non-blocking improvement:** Record it as a follow-up item and continue.
- **Duplicate dispatch:** Before launch, check running executors, worktrees, and branches for the same Step. Never start a duplicate; resume or wait instead.
- **Cancelled or blocked:** Stop affected Steps and report their state, the blocker, and what is needed. Continue unaffected independent Steps only while they remain valid.
- **Awaiting confirmation:** Stay at the gate. Do not commit, push, merge, write Jira, or start the next issue until the user confirms.

## Delivery

Report in the conversation:

- Completed work and verification results.
- Review summary: who reviewed, each finding adopted or converted to a follow-up, and why.
- Follow-up items, Git and stage state, and human review suggestions.
- Controller, executor, and reviewer usage according to [references/usage-report.md](references/usage-report.md). Mark unavailable values as unavailable; never estimate them.

### Guardrails

- Do not use budget fields, spending caps, or budget-based confirmations. Minimize unnecessary consumption instead.
- Use repository-relative paths only.
- Never commit automatically.
- Follow the repository's own instructions.

### References

- [references/dispatch.md](references/dispatch.md): execution modes, CLI invocation, parallelism, and context control.
- [references/review.md](references/review.md): review composition, finding policy, and review prompt template.
- [references/models.md](references/models.md) and [references/models.json](references/models.json): model selection and baseline list; perform the weekly availability check with `scripts/Update-ModelAvailability.ps1`.
- [references/usage-report.md](references/usage-report.md): usage reporting.

## Example

Request:

```text
Use orchestrate-ai-delivery for SYP-123 in this repository on branch feature/SYP-123-slug.
Controller: you. Execution mode: external CLI, executor codex.
```

Expected flow: run the weekly model check, show the Plan with one Step per acceptance criterion, dispatch each Step with an explicit model, review the diff, fix valid findings, run the required tests, then stop at the completion gate with a usage report. A Step dispatch looks like:

```text
codex exec --model <model> -c 'model_reasoning_effort="medium"' --sandbox workspace-write -C <step-worktree> -
```
