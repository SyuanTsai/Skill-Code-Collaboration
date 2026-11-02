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
4. Recommend the executor and the lowest-capability model that can complete the task reliably. Escalate only for cross-module reasoning, security or authentication, concurrency, data consistency, difficult diagnosis, or other high-risk work, and state the concrete reason.
   - Use the exact model identifier accepted by the chosen executor's model option (`--model` for CLIs), never a tier, family, or generic description.
   - Establish availability in this order: a baseline model list from the calling workflow (for example, an installed `orchestrate-ai-delivery` Skill); the executor's own listing (`codex debug models` for Codex CLI, or the known-model list in `copilot help config` for Copilot CLI, noting it does not establish entitlement); then a user-provided list.
   - If availability cannot be established, ask the user instead of guessing. Also recommend a reasoning effort level supported by the chosen executor.
5. Make the prompt directly executable. Include its objective; relevant files or symbols; allowed files; scope and exclusions; implementation constraints; acceptance criteria; required tests; validation; and a completion report.
6. Write testing and database requirements directly in the prompt rather than citing rule-file paths the executor might not load.
7. Forbid the executor from committing, pushing, or modifying files outside the allowed list. Use repository-relative paths only; never include local user names, absolute paths, machine identifiers, credentials, or tokens.
8. Require a completion report with exactly these headings: Changed files, Summary, Test commands, Test results, Blockers.
9. Write in the user's requested language, defaulting to the conversation language.

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
