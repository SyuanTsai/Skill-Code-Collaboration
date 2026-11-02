<!--
SPDX-FileCopyrightText: 2026 SyuanTsai
SPDX-License-Identifier: Apache-2.0
-->

# Dispatch reference

Verified on 2026-11-02 with claude 2.1.309, codex-cli 0.154.0, GitHub Copilot CLI 1.0.80 (Windows host). Re-verify with each CLI's --help after upgrades.

Use this reference after planning an issue into Steps. The task states its execution
mode at the start. If it does not, ask the user; never assume a mode.

| Mode | When | Executor | Model choice | Usage |
| --- | --- | --- | --- | --- |
| External CLI | The user names a controller in an app conversation | `claude`, `codex`, or `copilot` CLI launched by the controller, model set with `--model` | Any vendor the CLI offers | From each CLI's actual output |
| Built-in sub agent | An AI agent delegates during its own work | The controller's own built-in sub agent; no separate CLI | Usually the controller's vendor only | Record only what is reported; otherwise mark unavailable |

Both modes use the same planning, review, findings, completion, and usage rules.
Only launching and usage collection differ.

## External CLI reference

### Codex CLI

`codex-cli 0.154.0` provides the following verified interface.

| Purpose | Flag or command |
| --- | --- |
| Non-interactive execution | `codex exec [options] "<prompt>"` |
| Long prompt on standard input | Use `-` as the prompt argument |
| Model | `-m <slug>` or `--model <slug>` |
| Approval policy | `-c approval_policy="never"` for non-interactive write-capable `exec` and `exec resume`; `codex exec` does not accept `-a` or `--ask-for-approval` |
| Resume | `codex exec resume <thread-id>` with `-m`, `--json`, `-o`, and `-`; set `sandbox_mode` and `approval_policy` with `-c`, and set the shell cwd to `<worktree>` |
| Review | `codex exec review` with `-m`, `--json`, `-o`, `--uncommitted`, `--base <branch>`, or `--commit <sha>` |
| Reasoning effort | `-c model_reasoning_effort="<level>"`; levels depend on the model in `references/models.json` |
| Working root | `-C <dir>` or `--cd <dir>` |
| Write scope | `--sandbox workspace-write` |
| Extra writable directory | `--add-dir <dir>` |
| Read-only execution | `--sandbox read-only` |
| Machine-readable events | `--json` JSONL |
| Final message file | `-o <file>` or `--output-last-message <file>` |
| Do not persist session | `--ephemeral`; use only for a known one-shot execution that will not need `resume` |
| List models without a model call | `codex debug models` |
| Login check | `codex login status` |

The approval and resume details in this section were tested on a Windows host
with `codex-cli 0.154.0`. The user's Codex configuration may name a model that
no longer exists; an invocation without `-m` can therefore fail with HTTP 400
`model_not_found`. Always pass an explicit `-m <slug>`, including when resuming
or reviewing.

Without a prompt argument, or when standard input is attached, Codex prints
`Reading additional input from stdin...` and reads standard input. Always supply
standard-input content or close standard input so it does not wait.

PowerShell 7 implementation example:
```powershell
Get-Content -Raw <prompt-file> | codex exec -C <worktree> --sandbox workspace-write -m <model> -c model_reasoning_effort="<effort>" -c approval_policy="never" --json -
```

POSIX-shell implementation example:
```sh
codex exec -C <worktree> --sandbox workspace-write -m <model> -c 'model_reasoning_effort="<effort>"' -c 'approval_policy="never"' --json - < <prompt-file>
```

An implementation that may enter a findings-fix loop must not use
`--ephemeral` at its initial launch, so its `thread.started` ID remains
resumable. Reserve `--ephemeral` for confirmed one-shot work such as a
read-only review. If an implementation was already started with `--ephemeral`,
start a new session for the fix and provide a short handoff.

Resume uses a thread ID from the `thread.started` event in the initial `--json`
output. On `codex-cli 0.154.0`, `codex exec resume` accepts `-m`, `--json`,
`-o`, and `-` for a stdin prompt, but does not accept `-s`/`--sandbox` or
`-C`/`--cd`. Set the shell's current directory to the Step worktree and set
the sandbox with `-c sandbox_mode="workspace-write"`:

PowerShell 7 resume example:
```powershell
Set-Location <worktree>
Get-Content -Raw <prompt-file> | codex exec resume <thread-id> -m <model> -c sandbox_mode="workspace-write" -c approval_policy="never" --json -o <output-file> -
```

POSIX-shell resume example:
```sh
cd <worktree>
codex exec resume <thread-id> -m <model> -c 'sandbox_mode="workspace-write"' -c 'approval_policy="never"' --json -o <output-file> - < <prompt-file>
```

`codex exec review` is available and, in the same Windows-host test, accepts
`-m <slug>`, `--json`, `-o <file>`, and the review selectors
`--uncommitted`, `--base <branch>`, and `--commit <sha>`. `--uncommitted`
cannot be combined with a custom prompt. For a custom review scope or prompt,
use `codex exec --sandbox read-only` with the review prompt template instead.
The `codex debug models` catalog also lists the hidden `codex-auto-review`
model, but `references/models.json` marks it `excluded`; do not select it.
Choose an `active`, C3-or-higher reviewer from `references/models.md` and pass
its slug to `codex exec review -m <slug>`.

Read-only review example:
```sh
codex exec -C <worktree> --sandbox read-only -m <model> -c 'model_reasoning_effort="<effort>"' --json --ephemeral "<review-prompt>"
```

The `turn.completed` event reports `usage.input_tokens`, `cached_input_tokens`,
`cache_write_input_tokens`, `output_tokens`, and `reasoning_output_tokens`.
For a background execution, treat `turn.completed` or `turn.failed` in the
JSONL event stream as the completion signal: `turn.completed` means success,
while `turn.failed` or a top-level `error` event means failure. If the
process has ended without any of those events, treat it as an abnormal failure
and inspect the output. The existence of the `-o` last-message file or whether
the process is still running is not a completion signal. While waiting, poll
both the JSONL stream and the process: on every poll check whether the process
ID is still alive and when the JSONL file was last written. A process that has
exited without a terminal event is an abnormal failure. If the process is alive
but the JSONL file has had no new event for 30 minutes, treat the Step as
stalled: stop that process, then resume the thread or dispatch the Step again.
Never wait on events alone. `turn.completed.usage`
is the single source of truth for usage. If a review's usage fields are all
zero, record usage as unavailable rather than as zero.
Credits and cost are not reported; record them as unavailable. `codex debug models`
prints a JSON model catalog for free, without calling a model; all listed models are
OpenAI family.

### GitHub Copilot CLI

`GitHub Copilot CLI 1.0.80` provides the following verified interface.

| Purpose | Flag or command |
| --- | --- |
| Non-interactive execution | `copilot -p "<prompt>" --no-ask-user` |
| Working directory | `-C <dir>` |
| Model | `--model <id>` |
| Reasoning effort | `--effort <none|minimal|low|medium|high|xhigh|max>` |
| Non-interactive tool permission | `--allow-all-tools`, or narrower `--allow-tool=<tool>` |
| Attempted review restriction | `--deny-tool=write --deny-tool=shell` |
| JSONL output | `--output-format json` |
| Known-model listing | `copilot help config` |

`--allow-all-tools` is required for non-interactive tool use; use narrower allowed
tools when they meet the Step's needs. The read-only restriction is accepted, but
that it blocks every write is **Unverified**.

PowerShell 7 implementation example:

```powershell
copilot -C <worktree> -p (Get-Content -Raw <prompt-file>) --no-ask-user --allow-all-tools --model <model> --effort <effort>
```

POSIX-shell implementation example:

```sh
copilot -C <worktree> -p "$(cat <prompt-file>)" --no-ask-user --allow-all-tools --model <model> --effort <effort>
```

Read-only review example:

```sh
copilot -C <worktree> -p "<review-prompt>" --no-ask-user --deny-tool=write --deny-tool=shell --model <model> --effort <effort>
```

Text output, without `-s` or `--silent`, ends with a summary such as
`AI Credits 0.41 (5s)` and `Tokens ↑ 16.2k (16.2k written) • ↓ 5`. This is the
complete source for credits, input, and output. JSON mode reports per-message
`assistant.message.data.outputTokens`, `session.usage_checkpoint.data.totalNanoAiu`,
and `result.usage.premiumRequests`, but no input tokens. Converting nanoAIU to AI
Credits is **Unverified**; do not convert it.

The `session.skills_loaded` JSON event contains local absolute paths of installed
Skills. Never paste raw JSON output into prompts or reports. Listing known models
does not establish entitlement. An unavailable model fails before any model call
with `Error: Model "<id>" from --model flag is not available.` An empty prompt is
rejected before model checking, so availability requires a real launch; the
availability script stops it before the model call. Organization policy can disable
third-party MCP servers; it gives a warning and does not block dispatch.

### Claude Code

`Claude Code 2.1.309` provides the following verified interface.

| Purpose | Flag or command |
| --- | --- |
| Non-interactive execution | `claude -p "<prompt>"` or `--print` |
| Model | `--model <alias-or-full-name>` |
| Model aliases | `fable`, `opus`, `sonnet`, `haiku` |
| Reasoning effort | `--effort <low|medium|high|xhigh|max>` |
| Plan-mode review | `--permission-mode plan` |
| Restrict tools | `--tools` or `--disallowed-tools` |
| JSON output | `--output-format json` or `stream-json` |
| Do not persist session | `--no-session-persistence` |
| Login check without model call | `claude auth status` |

Run `claude` from inside the Step's worktree: set the working directory to
`<worktree>` before launching.

Implementation example:
```sh
claude -p "<implementation-prompt>" --model <model> --effort <effort> --output-format json --no-session-persistence
```

Read-only review example:

```sh
claude -p "<review-prompt>" --model <model> --effort <effort> --permission-mode plan --output-format json --no-session-persistence
```

Tool restriction and plan mode exist, but their blocking behavior is **Unverified**.
The JSON result has `usage.input_tokens`, `cache_creation_input_tokens`,
`cache_read_input_tokens`, `output_tokens`, `modelUsage` per model, and
`total_cost_usd`, a currency amount rather than a credit. Field structure was seen;
values are **Unverified** because the CLI was not logged in during verification.
No command lists available models (**Unverified**). Do not use `--max-budget-usd`:
this workflow does not use budget caps.

## Built-in sub-agent reference

| AI | Choose model per sub agent | Usage available | Basis |
| --- | --- | --- | --- |
| Claude Code | Yes — the agent-launch tool takes a `model` value: `sonnet`, `opus`, `haiku`, or `fable`; `haiku` was verified to run as a Haiku model | Partial — total tokens, tool-call count, and duration per sub agent; no input/output split, credit, or cost | Verified |
| GitHub Copilot CLI | Yes, by configuration — `subagents.agents.<agent-name>` sets model, effortLevel, and contextTier; `/subagents` is interactive and `/fleet` runs sub agents in parallel | **Unverified** — `/usage` shows session totals; per-sub-agent split is mentioned only for experimental `/context` | CLI help |
| Codex CLI | **Unverified** — `multi_agent` is stable and enabled, but no flag or setting was found to select another sub-agent model | **Unverified** | CLI help, model catalog |

If a capability is unverified or unsupported by the current controller, say so in
the delivery; do not claim support.

## Dispatch rules

1. Create every executor prompt with the `write-implementation-prompt` Skill. It
   must be self-contained: objective, allowed files, scope and exclusions,
   constraints, acceptance criteria, required tests with commands, and a completion
   report containing Changed files, Summary, Test commands, Test results, and
   Blockers. Put required testing and database rules in the prompt itself. Do not
   assume the executor sees another workspace, prior conversation, or unstated
   context. If a Skill or model list cannot be confirmed, state what is missing.
2. Use repository-relative paths only. Prompts and reports must not contain user
   names, absolute paths, machine identifiers, credentials, tokens, or sensitive
   full outputs.
3. Dispatch only work required for the objective. Record out-of-scope discoveries
   as follow-up items. Executors never commit or push. Every model-calling Codex
   command (`exec`, `exec resume`, or `exec review`) must pass an explicit
   `-m <slug>`; never rely on the user's configuration file default. Commands
   such as `codex debug models` that do not call a model are excluded.
4. Run independent Steps in parallel, each in its own Git worktree on its own
   branch. The default maximum is three concurrent executors. State the reason for
   any different limit. Before launch, check running executors, worktrees, and
   branches so the same Step is never started twice.
5. For External CLI mode, before launch run one low-cost preflight that verifies
   the executor can run the Step's required test command in its sandbox. If it
   cannot execute the required PowerShell or Pester test (for example, because
   the workspace-write sandbox cannot see a user-installed `pwsh`), say so
   explicitly in the dispatch prompt: "If you cannot execute the required
   tests, state that in the completion report; the controller will run them
   locally." The controller must then run those tests itself. Note that
   sandbox-created files may be owned by the sandbox account and can cause
   later Git ownership warnings. For Built-in sub-agent mode, confirm that the
   sub agent can execute the required test command; if it cannot, use the same
   prompt instruction and have the controller run the tests.
   If the user's global instructions require an instruction bootstrap hook, the
   controller runs it once outside the sandbox before dispatch, because a
   sandboxed executor may be unable to read the user-level inventory and the
   hook then fails closed. After it passes, state that result in the prompt and
   instruct the executor not to run the bootstrap again.
6. Choose models according to `references/models.md`. For every Step state the
   exact model identifier, effort, and reason. Escalate only for a concrete
   difficulty; never carry a high-cost model into later Steps by default.
7. If a model fails at launch because it is unavailable, removed, or rejected,
   immediately re-run `scripts/Update-ModelAvailability.ps1` with its force option,
   as specified by `references/models.md`. Select again from the refreshed list and
   report the change.
8. Keep prompts concise. Do not pass whole conversations, unrelated code, or full
   test logs. Before resuming a long session, consider a short handoff to a new
   session if cheaper, after confirming no Step is already running twice. Collect all
   findings from one full review round, then dispatch the fixes once with no human
   gate between review and fix; the human gate is the completion gate. Merge small
   cleanups into required fixes; the controller reads logs, collects usage, and views
   diffs itself.
