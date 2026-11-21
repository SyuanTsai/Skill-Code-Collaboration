---
name: write-implementation-prompt
description: Produce a self-contained, repository-scoped implementation prompt for a delegated executor (claude, codex, or copilot CLI, or a built-in sub agent) and recommend the executor, exact model, and reasoning effort. Use when the user or a controlling workflow asks for a prompt that another AI will use to implement, fix, refactor, or test a change.
---
<!--
SPDX-FileCopyrightText: 2026 SyuanTsai
SPDX-License-Identifier: Apache-2.0
-->

# Write an Implementation Prompt

1. Treat a request to provide a prompt as delegation to an external `claude`, `codex`, or `copilot` CLI, or to a built-in sub agent of the AI currently running.
2. Inspect the current repository for relevant files, symbols, conventions, and applicable rules. Do not assume the executor can access another repository, workspace, prior conversation, or undisclosed context.
3. Generated commands must use the shell and tooling documented by the target repository. If the repository is tied to one operating system, follow it and say so; do not invent a platform.
4. If the calling workflow has already fixed the executor, model, and reasoning effort, use them unchanged and restate its reason. Otherwise, recommend the executor and the lowest-capability model that can complete the task reliably. Escalate only for cross-module reasoning, security or authentication, concurrency, data consistency, difficult diagnosis, or other high-risk work, and state the concrete reason.
   - Use the exact model identifier accepted by the chosen executor's model option (`--model` for CLIs), never a tier, family, or generic description.
   - Establish availability in this order: a baseline model list from the calling workflow (for example, an installed `orchestrate-ai-delivery` Skill); the executor's own listing (`codex debug models` for Codex CLI, or the known-model list in `copilot help config` for Copilot CLI, noting it does not establish entitlement); then a user-provided list.
   - If availability cannot be established, ask the user instead of guessing. Also recommend a reasoning effort level supported by the chosen executor.
5. Make the prompt directly executable. Include its objective; relevant files or symbols; allowed files; scope and exclusions; implementation constraints; acceptance criteria; required tests; validation; and a completion report.
6. Write testing and database requirements directly in the prompt rather than citing rule-file paths the executor might not load.
7. When delegated work must investigate code before writing or updating documentation (code-evidence documentation), require an evidence-scoped dispatch; for a single small documentation edit, allow a streamlined dispatch without an evidence table.
   - State the inspection scope with repository-relative paths, symbols, and an evidence version: a pinned commit or revision, or, for uncommitted changes, a baseline commit plus the identified worktree diff. If the baseline cannot be identified, require the executor to stop and report it rather than cite stale `HEAD`. Classify evidence as at least `confirmed in code`, `confirmed not mapped`, or `unconfirmed`; never mark inference, a missing result, a DTO declaration, or recent documentation as confirmed.
   - Trace every task-relevant code path separately, such as create, update, delete, and exception paths; do not invent paths that do not apply. Require symbol-first searches, then only necessary excerpts, and return relevant excerpts, diffs, and summaries rather than whole files or storage XML without justification; allow justified reinspection for new evidence, failures, or state drift, without hard read-count limits.
   - Bind citations to the evidence version, file, and symbol, identifying the baseline commit and worktree diff for uncommitted changes; obtain line numbers from the source and verify them before finalizing rather than guessing them.
   - For an evidence-scoped dispatch, within the existing five report headings, put a compact evidence table under `Summary` with source, target, condition, status, commit/file/symbol; do not add or rename headings.
   - Keep every required input in the prompt; do not rely on cross-repository or prior-conversation access. Treat page IDs, data-model names, specific draft versions, providers, and project exceptions only as task inputs, not universal rules.
   - Do not define the full external-sync workflow here. Require local content and diff checks plus a report, and forbid publication unless the caller authorized it.
8. Forbid the executor from committing, pushing, or modifying files outside the allowed list. Use repository-relative paths only; never include local user names, absolute paths, machine identifiers, credentials, or tokens.
9. Require a completion report with exactly these headings: Changed files, Summary, Test commands, Test results, Blockers.
10. Write in the user's requested language, defaulting to the conversation language.

Return:

````markdown
Executor: <claude CLI | codex CLI | copilot CLI | built-in sub agent of <AI>>
Recommended model: <exact model identifier>
Reasoning effort: <level>
Reason: <brief task-specific reason>

Prompt:
```text
<self-contained prompt>
```
````

## Error Handling

- If the repository, target change, or applicable rules cannot be inspected, identify the missing evidence and do not invent file paths, symbols, constraints, or acceptance criteria.
- If model availability or a supported reasoning effort cannot be established, ask the user for the exact available model identifiers and effort levels before recommending one.
- If repository instructions conflict or the requested scope is ambiguous, surface the conflict or decision that the executor must not guess and obtain clarification before finalizing the prompt.
- If an exact validation command cannot be verified, require the executor to discover the repository-supported command, run it when safe, and report the command and result instead of fabricating one.
