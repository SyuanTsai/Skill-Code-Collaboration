---
name: orchestrate-ai-delivery
description: Plan a Jira issue or ad-hoc requirement into Steps, dispatch each to claude, codex, copilot, or junie CLI or a built-in sub agent with an explicit model, review diffs, fix valid findings, run tests, and stop at a human gate. Use when asked to drive or delegate a Jira issue or described change.
---
<!--
SPDX-FileCopyrightText: 2026 SyuanTsai
SPDX-License-Identifier: Apache-2.0
-->

# Orchestrate AI Delivery

## Setup

### Inputs

Collect the controller AI and host (`CLI` or `IDE`), the Jira issue key or the user's requirement description, the repository and branch, the execution mode (`external CLI` or `built-in sub agent`), and the executor. If execution mode is missing, ask; never assume it. Ask only for truly missing required information. Show routine model choices made under [references/models.md](references/models.md) in the Plan instead of asking about each one again.

### Work without a Jira issue

- Use the user's requirement description as the work source. Write the Objective and Acceptance Criteria in the Plan, and use them for Steps, Review, and completion decisions.
- Determine the environment from the user's local repository-to-environment configuration. Stop and ask if the environment cannot be determined or signals conflict.
- Keep progress and delivery in the conversation. Do not write to Jira.
- Follow the same Plan, dispatch, Review, zero-valid-findings requirement, human gate, and usage reporting.

### Environment Boundary

When an issue key is provided, determine the environment from its prefix using the user's local prefix-to-environment mapping. That mapping is user-local configuration and must not be stored in a repository. Without an issue key, follow [Work without a Jira issue](#work-without-a-jira-issue).

- Work environment (`ROAR-`): Jira is read-only. Keep progress, review results, and delivery in the conversation or local files.
- Private environment (`SYP-`): before any Jira write, preview the write, name the environment and site, and obtain user consent.
- If the environment cannot be determined or signals conflict, stop and ask.

Only Jira, Git, and CLIs are in scope. Confluence is not.

### Roles

- **Controller:** read the Jira issue or the user's requirement, plan, make design trade-offs, write Step specs, diagnose failures and findings, select models, dispatch, review, judge findings, run required tests itself, and stage changes. Never commit or push without user consent.
- **Executor:** use the selected external CLI or built-in sub agent to implement code and tests from the controller's spec within the Step scope. Never use an executor for planning or root-cause diagnosis. Never commit or push.
- **Review CLI:** run `claude` and `codex` CLI in fresh read-only sessions as described in [references/review.md](references/review.md).

### Controller host

The controller can run in a CLI (`claude`, `codex`, `copilot`, or `junie`) or in Codex App or the Codex IDE extension, VS Code Copilot Chat in Agent mode, or Junie in a JetBrains IDE. An IDE controller runs the same dispatch commands through its shell or terminal tool.

In external CLI mode, before the first dispatch, verify from the controller's shell that the executor CLI starts with `--version` and is signed in, and that the required test commands can run in the required directory. If the IDE sandbox or permissions block CLI launches, network access, a user-installed `pwsh`, or unattended execution because each command requires human approval, name the specific restriction and ask the user to run the dispatch command in a local terminal or switch controllers. Report dispatch only when it has been confirmed.

In built-in sub agent mode, no executor CLI is required. Before the first dispatch, verify that the controller's own sub-agent tool is available, that it can select the planned model or that the limitation is recorded, and that the required test commands can run. See the Controller hosts section of [references/dispatch.md](references/dispatch.md) for details.

## Workflow

### Core Principles

- Base the Plan, Steps, and Review on the Jira issue or on the Objective and Acceptance Criteria the controller writes in the Plan from the user's requirement. For Jira work, comments and handoffs are supplementary. A comment explicitly marked authoritative overrides the description.
- Map every change to the objective or an acceptance criterion.
- Preserve explicitly required behavior, including existing exceptions. Keep pre-existing defects unchanged when behavior preservation is required; report them as follow-up items for the user's decision.
- A functional regression relative to baseline is a valid finding: fix and re-verify it, never defer it. Previously successful inputs, filenames, permissions, platforms, and environments must still work.
- Preserve progress: only suggestions outside Valid Findings, such as hardening, refactoring, style, and extra features, become follow-up items and do not stop delivery.
- Review and findings occur after implementation.
- Define pre-publication required checks as tests named by the work source plus affected CI tests reproducible locally, such as licensing or inventory tests for new tracked files. The controller runs them, selects the repository-declared runner version, and confirms every execution ran more than zero tests. Remote-only CI belongs to the post-publication loop.

### Steps

1. **Plan:** Before planning, read repository instructions and CI workflows. Define the Objective and Acceptance Criteria from the Jira issue or, without an issue key, write them from the user's requirement. Define the Scope, required Steps, and verification method, including mandatory synchronization rules, affected locally reproducible CI checks, and remote workflows. Map every acceptance criterion to a Step. Write each Step as a file- and function-level spec: change locations, behavior, test list, and acceptance. Classify each Step with the work-type tiers in [references/models.md](references/models.md), then choose its executor and the review CLIs, each with an exact model, effort, and reason, and show them in the Plan. Run independent Steps in parallel, each in its own Git worktree when it touches the repository.
2. **Dispatch:** Produce every Step prompt with the `write-implementation-prompt` Skill, passing it the executor, model, effort, and reason fixed in the Plan, including objective, allowed files, scope, acceptance criteria, required tests, and completion report. Before sending prompts, review instructions, or delivery content, check for and remove Windows drive paths, `/Users/<name>`, `/home/<name>`, and user names. Apply this check to external CLIs and built-in sub agents. Pass the working directory through `-C` or shell cwd for external CLIs; describe sub-agent worktrees relative to the repository root. Launch it with the executor and model chosen in the Plan using [references/dispatch.md](references/dispatch.md), and record the dispatch line it specifies.
3. **Step Review:** Have the controller and review CLI both review the implemented Step using [references/review.md](references/review.md).
4. **Judge and diagnose findings:** Verify that each finding exists and satisfies a [Valid Findings](references/review.md) condition. For each valid finding or test failure, locate the root cause yourself from logs and code and write the smallest exact fix; record everything else as a follow-up item.
5. **Fix and re-review:** Classify the fix again with the work-type tiers, dispatch it to a new session under the thread strategy in [references/dispatch.md](references/dispatch.md), then re-review only the fixed part and related regressions.
6. **Issue Review:** After all required Steps, check the cumulative changes, cross-Step integration, required tests, and final diff against the Jira issue or the Objective and Acceptance Criteria written in the Plan.
7. **Completion gate:** Request approval to commit, push, and open a PR only after the delivery meets the Jira issue or the Objective and Acceptance Criteria written in the Plan, independent review reaches zero valid findings, and required checks pass. If no independent reviewer can run, explicitly tell the user and ask whether to accept the unreviewed change as required by [references/review.md](references/review.md). After publication, read PR CI and review comments, judge valid findings under [references/review.md](references/review.md), return them to Step 4, and repeat the pre-publication gate after fixing them. If the task has a Jira issue key and a correction changes Jira content already written, include that correction in the next Jira-write preview. Deliver in the conversation and wait for user confirmation before starting the next issue or requirement. Keep this gate by default and adjust it only when the task explicitly asks. Independent work may continue while waiting.

## Issues and Situations

- **Partial completion:** Deliver completed Steps with evidence; list incomplete Steps, reasons, and remaining work. Mark the delivery as incomplete.
- **Integration failure:** When Steps pass alone but fail together, treat this as a valid Issue Review finding, identify the conflicting Steps, and dispatch one integration fix.
- **Non-blocking improvement:** Record it as a follow-up item and continue.
- **Duplicate dispatch:** Before launch, check running executors, worktrees, and branches for the same Step. Never start a duplicate; resume or wait instead.
- **Cancelled or blocked:** Stop affected Steps and report their state, the blocker, and what is needed. Continue unaffected independent Steps only while they remain valid.
- **Awaiting confirmation:** Stay at the gate. Do not commit, push, merge, write Jira, or start the next issue or requirement until the user confirms.

## Delivery

Report in the conversation:

- Completed work and verification results.
- Review summary: who reviewed, each finding adopted or converted to a follow-up, and why.
- Follow-up items, Git and stage state, and human review suggestions.
- Controller, executor, and reviewer usage according to [references/usage-report.md](references/usage-report.md). Mark unavailable values as unavailable; never estimate them.

### Guardrails

- Do not use budget fields, spending caps, or budget-based confirmations. Minimize unnecessary consumption instead.
- Use repository-relative paths only.
- Never read, copy, move, or rewrite any CLI credential or auth file. Never override CLI configuration-directory or home environment variables for executors, including `CLAUDE_CONFIG_DIR`, `CODEX_HOME`, and `COPILOT_HOME`.
- CLI-written sessions, logs, and trust settings in its home directory are normal behavior; disclose them in delivery. Never relocate credentials to avoid these writes.
- Keep work without a Jira issue in the conversation and skip Jira writes.
- Never commit automatically.
- Follow the repository's own instructions.

### References

- [references/dispatch.md](references/dispatch.md): execution modes, CLI invocation, spec-only dispatch, parallelism, thread strategy, and the dispatch record, plus the Built-in sub-agent reference, Controller hosts, and Adding another CLI sections.
- [references/review.md](references/review.md): review composition, finding policy, and review prompt template.
- [references/models.md](references/models.md) and [references/models.json](references/models.json): model selection, work-type tiers, and baseline list; perform the weekly availability check with `scripts/Update-ModelAvailability.ps1`.
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

Request without a Jira issue:

```text
Use orchestrate-ai-delivery in this repository on branch <branch> to correct the export heading. The heading should match the column label shown in the UI.
Controller: VS Code Copilot Chat in Agent mode. Execution mode: external CLI, executor junie.
```

PowerShell 7 dispatch from the controller's terminal, with `$junieExe` resolved as described in the Junie CLI section of [references/dispatch.md](references/dispatch.md):

```powershell
'' | & $junieExe --task (Get-Content -Raw "<step-prompt-file>") --project "<step-worktree>" --model "<model>" --effort "<effort>" --output-format json --json-output-file "<usage-file>"
```
