<!--
SPDX-FileCopyrightText: 2026 SyuanTsai
SPDX-License-Identifier: Apache-2.0
-->

# Dispatch reference

Verified on 2026-11-24 with claude 2.1.317, codex-cli 0.166.0, GitHub Copilot CLI 1.0.105, and Junie 26.11.2 (Windows host). Re-verify with each CLI's --help after upgrades.

Use this reference after planning a Jira issue or an ad-hoc requirement into
Steps. The task states its execution mode at the start. If it does not, ask the
user; never assume a mode.

| Mode | When | Executor | Model choice | Usage |
| --- | --- | --- | --- | --- |
| External CLI | The user chooses a CLI or IDE controller and an external executor | `claude`, `codex`, `copilot`, or `junie` CLI launched by the controller, model set with `--model` | Any vendor the CLI offers | From each CLI's actual output |
| Built-in sub agent | An AI agent delegates during its own work | The controller's own built-in sub agent; no separate CLI | Usually the controller's vendor only | Record only what is reported; otherwise mark unavailable |

Both modes use the same planning, review, findings, completion, and usage rules.
Only launching and usage collection differ.

## External CLI reference

Every model-calling dispatch, resume, or review command in this reference runs
through the user's own CLI account and consumes that account's quota or
credits; model-free commands such as `codex debug models`, `codex login status`,
`copilot help config`, `claude auth status`, and `junie list-models` do not.
Before the first dispatch, show the Plan with each Step's executor CLI and every
planned review CLI, each with its exact model and effort, so the user can see
which accounts and models will be billed. The
user's request to run this Skill approves model-calling dispatches to the
executor CLI the user named and to the review CLIs required by
`references/review.md`; ask first before a model-calling dispatch to any other
CLI or account.
The command blocks below are templates with `<placeholder>` values, not
commands to run as written.

### Codex CLI

`codex-cli 0.166.0` provides the following interface.

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

The approval and resume details in this section come from the prior Windows
verification. The user's Codex configuration may name a model that
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
```text
codex exec -C <worktree> --sandbox workspace-write -m <model> -c 'model_reasoning_effort="<effort>"' -c 'approval_policy="never"' --json - < <prompt-file>
```

An implementation that may enter a findings-fix loop must not use
`--ephemeral` at its initial launch, so its `thread.started` ID remains
resumable. Reserve `--ephemeral` for confirmed one-shot work such as a
read-only review. If an implementation was already started with `--ephemeral`,
start a new session for the fix and provide a short handoff. Whether to resume
or start a new session follows the thread strategy in dispatch rule 8.

Resume uses a thread ID from the `thread.started` event in the initial `--json`
output. `codex exec resume` accepts `-m`, `--json`,
`-o`, and `-` for a stdin prompt, but does not accept `-s`/`--sandbox` or
`-C`/`--cd`. Set the shell's current directory to the Step worktree and set
the sandbox with `-c sandbox_mode="workspace-write"`:

PowerShell 7 resume example:
```powershell
Set-Location <worktree>
Get-Content -Raw <prompt-file> | codex exec resume <thread-id> -m <model> -c sandbox_mode="workspace-write" -c approval_policy="never" --json -o <output-file> -
```

POSIX-shell resume example:
```text
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
```text
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

`GitHub Copilot CLI 1.0.105` provides the following verified interface.

| Purpose | Flag or command |
| --- | --- |
| Non-interactive execution | `copilot -p "<prompt>" --no-ask-user` |
| Working directory | `-C <dir>` |
| Model | `--model <id>` |
| Reasoning effort | `--reasoning-effort <none\|minimal\|low\|medium\|high\|xhigh\|max>` (`--effort` still works) |
| Non-interactive tool permission | `--allow-all-tools`, or narrower `--allow-tool=<tool>` |
| Attempted review restriction | `--deny-tool=write --deny-tool=shell` |
| JSONL output | `--output-format json` |
| JSON usage file | `--usage-output-file <file>` |
| Known-model listing | `copilot help config` |

`--allow-all-tools` is required for non-interactive tool use; use narrower allowed
tools when they meet the Step's needs. The read-only restriction is accepted, but
that it blocks every write is **Unverified**.

On Windows, `copilot` can resolve to a Node version manager proxy (such as
`copilot.exe` or `copilot.cmd`) that runs a batch script. That proxy rejects a
multi-line `-p` value with `InvalidBatchScriptArg` before any model call. Run
the package loader with `node` instead (Verified 2026-11-24 with GitHub Copilot
CLI 1.0.115). If `copilot` is installed some other way, check that a
multi-line `-p` value reaches the CLI before the first dispatch.

PowerShell 7 implementation example:

```powershell
$copilotLoader = Join-Path (npm root -g).Trim() '@github\copilot\npm-loader.js'
node $copilotLoader -C <worktree> -p (Get-Content -Raw <prompt-file>) --no-ask-user --allow-all-tools --model <model> --reasoning-effort <effort> --usage-output-file <usage-file>
```

POSIX-shell implementation example:

```text
copilot -C <worktree> -p "$(cat <prompt-file>)" --no-ask-user --allow-all-tools --model <model> --reasoning-effort <effort> --usage-output-file <usage-file>
```

Read-only review example:

```text
copilot -C <worktree> -p "<review-prompt>" --no-ask-user --deny-tool=write --deny-tool=shell --model <model> --reasoning-effort <effort> --usage-output-file <usage-file>
```

The usage file's `agentMetrics` contains `main` and each sub-agent ID. Each agent
lists `inputTokens`, `outputTokens`, `cacheReadTokens`, `cacheWriteTokens`,
`reasoningTokens`, and `totalNanoAiu` by model. One AI Credit equals 1,000,000,000
nanoAIU (Verified 2026-11-24). In the test, `totalNanoAiu` of 562,405,000
corresponded to `AI Credits 0.56` in the non-silent text summary.

The `session.skills_loaded` JSON event contains local absolute paths of installed
Skills. Never paste raw JSON output into prompts or reports. Listing known models
does not establish entitlement. An unavailable `--model <id>` fails before any model call
with `Error: Model "<id>" from --model flag is not available.` and lists available
models. An empty prompt is rejected before model checking, so availability
requires a real launch. The availability script stops it before the model call.
Organization policy can disable
third-party MCP servers; it gives a warning and does not block dispatch.

### Claude Code

`Claude Code 2.1.317` provides the following verified interface.

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

Pass `--strict-mcp-config` without `--mcp-config` so that the run loads no MCP
servers. Otherwise the user's MCP servers load their tool definitions into every
run. A two-turn review measured on 2026-11-24 wrote 792,394 cache tokens and cost
USD 6.36. With the flag, the startup context was about 47,000 tokens.

Implementation example:
```text
claude -p "<implementation-prompt>" --model <model> --effort <effort> --strict-mcp-config --output-format json --no-session-persistence
```

Read-only review example:

```text
claude -p "<review-prompt>" --model <model> --effort <effort> --permission-mode plan --strict-mcp-config --output-format json --no-session-persistence
```

Tool restriction and plan mode exist, but their blocking behavior is **Unverified**.
The logged-in test verified the JSON result fields and values. `usage` has
`input_tokens`, `cache_creation_input_tokens`, `cache_read_input_tokens`, and
`output_tokens`. `modelUsage` lists `inputTokens`, `outputTokens`,
`cacheReadInputTokens`, `cacheCreationInputTokens`, and `costUSD` per model,
including models used by sub agents. `subagent_stats` reports spawned,
completed, and failed counts and `by_type`. `total_cost_usd` and `costUSD`
report currency amounts calculated at list prices.

An unknown model ID fails with `unrecognized_model` before the model call and
incurs no charge. A legacy ID that remains accepted, such as `claude-fable-5-1`,
makes a billable call. An empty prompt is rejected before model validation, so
Claude CLI provides no model-free availability check. Do not use
`--max-budget-usd` in this workflow.

### Junie CLI

`Junie 26.11.2` provides the following interface.

| Purpose | Flag or command |
| --- | --- |
| Non-interactive execution | `junie --task "<prompt>"` or `junie "<prompt>"` |
| Project directory | `-p <dir>` or `--project <dir>` (defaults to the current directory) |
| Model | `--model <id>` |
| Reasoning effort | `--effort <low\|medium\|high>` per help. Check `efforts` in `junie list-models` for the selected model. |
| JSON result file | `--output-format json --json-output-file <file>` |
| Step and tool limits | `--max-steps <n>`, `--allowed-tools <list>` |
| Code review | `--review` (read-only enforcement is **Unverified**) |
| List models without a model call | `junie list-models` |
| Authentication | JetBrains account sign-in or `--auth`. Keep tokens out of commands and prompts. |

On Windows, `junie` resolves to the `junie.bat` launcher. The launcher parses
arguments with cmd delayed expansion and fails with "The syntax of the command
is incorrect" (exit 255) when the task text spans lines. It can also alter `!`
and `%` in the text. Run `junie --version` once through the launcher so it
applies staged updates. Then call the installed `junie.exe` directly with the
full prompt (Verified 2026-11-24 with Junie 26.11.3). If `JUNIE_VERSION` is set,
use that version's directory instead of the `current` file.

PowerShell 7 implementation example:

```powershell
$junieData = if ($env:JUNIE_DATA_DIR) { $env:JUNIE_DATA_DIR } else { Join-Path $HOME '.local\share\junie' }
$junieExe = Join-Path $junieData ('versions\{0}\junie\junie.exe' -f (Get-Content -Raw (Join-Path $junieData 'current')).Trim())
'' | & $junieExe --task (Get-Content -Raw "<prompt-file>") --project "<worktree>" --model "<model>" --effort "<effort>" --output-format json --json-output-file "<usage-file>"
```

POSIX-shell implementation example (shell syntax shown, execution **Unverified** on POSIX):

```sh
printf '' | junie --task "$(cat "<prompt-file>")" --project "<worktree>" --model "<model>" --effort "<effort>" --output-format json --json-output-file "<usage-file>"
```

Code review example (read-only enforcement **Unverified**):

```powershell
'' | & $junieExe --review --task (Get-Content -Raw "<review-prompt-file>") --project "<worktree>" --model "<model>" --effort "<effort>" --output-format json --json-output-file "<usage-file>"
```

The Windows dispatch with `gpt-5.6-luna`, effort `low`, and `--max-steps 3`
completed successfully (Verified 2026-11-24). Supply empty piped stdin in
non-interactive runs. A null device on stdin causes `IOException`, so use
`'' | junie ...` in PowerShell or `printf '' | junie ...` in POSIX shells.

The JSON result includes `sessionId`, `result`, `changes`, and `llmUsage[]`.
Each usage entry contains `model`, `calls`, `cost`, `inputTokens`,
`cacheInputTokens`, `cacheCreateTokens`, and `outputTokens`. Record every entry.
Junie can call auxiliary models alongside the selected model. The test also
used `gpt-6-luna` and `gpt-5.4-nano`. The `cost` field has no stated currency.

`junie list-models` returns JSON containing `id`, `efforts`, `defaultEffort`,
and `default`. A log line can precede the JSON. Parse from the first `{`.
Junie applies staged updates at startup (observed from 26.11.1 to 26.11.2).
Record the version used for each dispatch. An unreachable user-configured MCP
server emits a warning and execution continues.

## Built-in sub-agent reference

| AI | Choose model per sub agent | Usage available | Basis |
| --- | --- | --- | --- |
| Claude Code | The Agent tool accepts `sonnet`, `opus`, `haiku`, or `fable` in `model`. The `haiku` run used `claude-haiku-5-5`. | Interactive sub-agent results report only total tokens, tool-call count, and duration. `claude -p --output-format json` reports `modelUsage` by model, including sub-agent models, and `subagent_stats` counts. | Verified 2026-11-24 |
| GitHub Copilot CLI | The `task` tool accepts `model` and used `gpt-6-luna` when requested. When asked for unavailable `gpt-5.6-terra`, it silently ran `claude-sonnet-5.5` for 5.77 AI Credits while the UI still showed the requested model. | `--usage-output-file` reports `agentMetrics` by agent ID and model. Check the actual model here after every dispatch. | Verified 2026-11-24 |
| Codex CLI | `spawn_agent` accepts `message`, `task_name`, `fork_turns` (`all` or `none`), `model`, and `reasoning_effort`. With a `gpt-5.6-luna` controller at `low`, the requested `gpt-5.6-terra` sub agent ran at `low`. | Parent `turn.completed.usage` excludes sub agents. `codex exec` reports no sub-agent token breakdown. Only the total token count is available in local Codex thread state. | Verified 2026-11-24 |
| Junie CLI | Model selection for custom agents loaded with `--agent-location` is **Unverified**. | Per-sub-agent usage is **Unverified**. Junie CLI reports `llmUsage` by model. | Unverified |

Codex CLI exposes `spawn_agent`, `wait_agent`, `send_message`, `followup_task`,
`interrupt_agent`, and `list_agents` only with `--enable multi_agent_v2`. The flag
is stable and off by default. Without it, `codex exec` has no sub-agent tools.

Copilot `task` agent types are `explore`, `task`, `general-purpose`, `rubber-duck`,
`code-review`, `research`, and `security-review`. A custom agent in
`.github/agents/<name>.agent.md` can set `model:` in its frontmatter. Use
`--add-dir <dir>` to load an external directory. An unavailable model in a custom
agent fails explicitly and lists available models (Verified 2026-11-24).
`copilot help config` documents `model`, `effortLevel`, and `contextTier` under
`subagents.agents.<agent-name>`. This configuration was **Unverified** in the test.

After every sub-agent dispatch, verify the actual model against the usage
source. For Copilot, always use `agentMetrics`. If the actual model differs from
the requested one, stop using the result, state the mismatch in the delivery,
and dispatch again with an available model. If the usage source does not identify
the actual model, record that verification is unavailable.

If a capability is unverified or unsupported by the current controller, say so in
the delivery; do not claim support.

## Controller hosts

The controller can run in `claude`, `codex`, `copilot`, or `junie` CLI, or in
Codex App, the Codex IDE extension, VS Code Copilot Chat in Agent mode, or Junie
in a JetBrains IDE. IDE controllers use their shell or terminal tool to run the
same external dispatch commands as CLI controllers. When an IDE controller uses
built-in sub agents, follow the model-selection, verification, and reporting rules
in [Built-in sub-agent reference](#built-in-sub-agent-reference) and check the
controller's actual tool capabilities.

Before the first dispatch in external CLI mode:

1. Run the executor's `--version` from the controller's shell to confirm it can
   start there. Record the version used for each Junie dispatch.
2. Verify the executor is signed in. Use a model-free login check when available.
3. Verify the required test commands can run from the required repository or
   Step worktree, including the required `pwsh` and test runner where applicable.
   Follow dispatch rule 5 for executor test access.

In external CLI mode, if the IDE blocks child processes or network access,
cannot see a user-installed `pwsh`, or requires human approval for every
command, name the specific limit. Ask the user to run the dispatch command in a
local terminal or switch controllers. Report dispatch only after confirming the
launch.

In built-in sub agent mode, the controller needs no executor CLI. Before the
first dispatch, verify that its sub-agent tool is available, that it can select
the planned model or that the limitation is recorded under
[Built-in sub-agent reference](#built-in-sub-agent-reference), and that the
required test commands can run. If they cannot, follow dispatch rule 5.

Actual dispatch outcomes for Codex App, the Codex IDE extension, and VS Code
Copilot Chat in Agent mode are **Unverified** pending acceptance runs. Dispatch
from Junie in a JetBrains IDE is also **Unverified** in the Windows test results.

## Adding another CLI

Verify and record these items before adding an executor CLI:

- Non-interactive invocation and how to supply the prompt.
- Model flag, effort flag and accepted values, and working-directory selection.
- Review invocation and whether it enforces read-only access.
- Usage source, fields, and units.
- Model-list command that does not call a model, and the failure signal for an
  unavailable model.
- Standard-input behavior, automatic updates, and how to check sign-in.

Update `references/models.json` (`cli` allowed values, `efforts`, and entries),
the probes in `scripts/Update-ModelAvailability.ps1`, the CLI list in
`scripts/Update-ModelBaseline.ps1`, the corresponding tests, this reference,
and `references/usage-report.md` together.

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
6. Dispatch only specs, never planning or diagnosis. Before a new Step, the
   controller writes a file- and function-level spec: what to change and where,
   the intended behavior, the tests to add or update, and acceptance. Before a fix,
   the controller reads the logs and code and locates the root cause itself; the
   fix prompt names the file and the change, plus a regression test when one
   applies or otherwise the validation command or inspection that proves the fix. A sub agent may
   help search a large scope, but the controller makes the decision. Then classify
   the work with the work-type tiers in `references/models.md` and state the exact
   model identifier, effort, and reason. Classify every fix round again; never
   carry a high-cost model into later Steps or rounds by default.
7. If a model fails at launch because it is unavailable, removed, or rejected,
   immediately re-run `scripts/Update-ModelAvailability.ps1` with its force option,
   as specified by `references/models.md`. Select again from the refreshed list and
   report the change. Model-unavailability signals vary by CLI. Copilot's `task`
   sub agent silently falls back, so check the actual model in `agentMetrics`.
8. Keep prompts concise. Do not pass whole conversations, unrelated code, or full
   test logs. Thread strategy: every resume re-reads the whole session history, so
   a cheaper model saves little on a long thread. Dispatch a located or mechanical
   fix to a new session whose prompt carries the needed context. Do not resume a
   session whose last cumulative input tokens exceed 5,000,000; hand off to a new
   session instead. Confirm no Step is already running twice before either. Collect
   all findings from one full review round, then dispatch the fixes once with no
   human gate between review and fix; the human gate is the completion gate. Merge
   small cleanups into required fixes; the controller reads logs, collects usage,
   and views diffs itself.
9. Record every dispatch, fix round, and review as one line in the controller's
   status record, using the model baseline's capability and `reviewedOn` value.
   Use the form
   `<cli>-<model>-<task> | effort <effort> | C<capability> reviewed <reviewedOn> | <reason>`, for example
   `codex-gpt-5.6-terra-S2-fix1 | effort medium | C2 reviewed <reviewedOn> | located root cause, one-line change`.
   Use the same `<cli>-<model>-<task>` text as the name of any background task and
   its output files, so the usage report can map each run back to its choice.

## Example: diagnose, then dispatch a precise fix

A Step's required tests pass on Windows PowerShell 5.1 but fail on PowerShell 7
with a wrong segment count from a path-splitting helper.

Not this: resume the implementation thread with the failure log and "find the root
cause and fix it" on a C4 model.

Instead, the controller reads the failing assertion and the helper, sees that the
helper relies on the 5.1 behavior of `-split '/', -1`, which PowerShell 7 treats
differently, and writes the fix spec:

```text
Objective: make <helper> return the same segments on PowerShell 5.1 and 7.
Change: in <file>, replace the `-split '/', -1` call in <function> with
  <exact replacement>; change nothing else.
Test: add a case to <test-file> asserting the segments for 'a/b/' on both editions.
Acceptance: <required test command> passes; no other file changes.
```

Classification: fix with a located root cause, so C2 or C3 `medium`; dispatch it to
a new session (record line
`codex-gpt-5.6-terra-S3-fix1 | effort medium | C2 reviewed <reviewedOn> | root cause located by controller`).
If two consecutive fix rounds of this Step had used C4, the self-check in
`references/models.md` would require re-examining the spec first.
