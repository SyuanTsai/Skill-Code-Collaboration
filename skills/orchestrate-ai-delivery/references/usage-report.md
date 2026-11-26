<!--
SPDX-FileCopyrightText: 2026 SyuanTsai
SPDX-License-Identifier: Apache-2.0
-->

# Usage report reference

Verified on 2026-11-24 with claude 2.1.317, codex-cli 0.166.0, GitHub Copilot CLI 1.0.105, and Junie 26.11.2 (Windows host); controller-record checks verified on 2026-11-26. Re-verify with each CLI's --help after upgrades.

Record usage after every controller, executor, and reviewer run. Use the table
format below. For a resumed session, follow Resumed sessions below. List
separate rows when the source reports usage by agent or model.

| Role | Step | Tool (CLI or sub agent) | Model | Effort | Input tokens | Output tokens | Credit (with unit) | Cost (currency) | Source |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| controller | Planning | `<tool>` | `<exact model ID>` | `<effort>` | `<value or Unavailable>` | `<value or Unavailable>` | `<value and unit or Unavailable>` | `<value and currency or Unavailable>` | `<event, result, or summary>` |
| executor | Step 1 | `<tool>` | `<model>` | `<effort>` | `<value or Unavailable>` | `<value or Unavailable>` | `<value and unit or Unavailable>` | `<value and currency or Unavailable>` | `<event, result, or summary>` |
| reviewer | Step 1 | `<tool>` | `<model>` | `<effort>` | `<value or Unavailable>` | `<value or Unavailable>` | `<value and unit or Unavailable>` | `<value and currency or Unavailable>` | `<event, result, or summary>` |
| Total (tokens only) | All Steps | — | — | — | `<input-token total>` | `<output-token total>` | Unavailable — different units are separate | Unavailable — currency is separate | Sum only compatible token values |
| Total (AI Credits) | All Steps | — | — | — | Unavailable — credits are not tokens | Unavailable — credits are not tokens | `<AI Credit total>` | Unavailable — currency is separate | Sum Copilot AI Credits, using either converted usage-file values or text summaries for each run |
| Total (nanoAIU) | All Steps | — | — | — | Unavailable — raw unit only | Unavailable — raw unit only | `<totalNanoAiu total, raw nanoAIU>` | Unavailable — currency is separate | Sum raw nanoAIU values of known scope. Divide by 1,000,000,000 to express the same usage in AI Credits. |
| Total (currency) | All Steps | — | — | — | Unavailable — currency is not tokens | Unavailable — currency is not tokens | Unavailable — currency is not a credit | `<currency total>` | Sum only the same currency |

Write `Unavailable` (or the conversation-language equivalent) and the reason
whenever a value is absent. For example, use `Unavailable — not reported by codex exec`.
Never estimate, infer, or back-calculate a missing field.

Keep units separate. Codex reports tokens only. Copilot reports AI Credits and
raw `totalNanoAiu` for the same usage. Count each session once in the AI Credits
total, using the last usage file or summary of a resumed Copilot session.
Claude reports `total_cost_usd` as currency. Preserve Junie's reported `cost`
when currency is unstated and leave it out of totals. Sum only compatible units.

## Resumed sessions

Verified on 2026-11-26 on Windows with codex-cli 0.166.0, claude 2.1.317, and
GitHub Copilot CLI 1.0.116. Junie CLI resume was not verified.

Count each session once. Keep only the last value of a session-cumulative
figure; sum a per-invocation figure across invocations. Never add a cumulative
figure to a per-invocation figure from the same session. Example: three resumes
report 10k, then 25k, then 40k cumulative tokens. Report 40k, not 75k.

| CLI | Resumed-session behavior | What to record |
| --- | --- | --- |
| Codex CLI | `turn.completed.usage` is cumulative across all `exec` and `exec resume` runs on the thread. | Keep the last value: 43,794 / 190 followed by 87,976 / 290 means 87,976 input / 290 output, not 131,770 / 480. |
| Claude Code | `usage` covers the current invocation; `modelUsage` and `total_cost_usd` are session-cumulative. | Sum `usage` across invocations or take the last `modelUsage` and `total_cost_usd`; use the other as a cross-check. Never sum `modelUsage` or `total_cost_usd` across invocations. For example, 149 + 150 output tokens equals the last `modelUsage` of 299; keep the last cost, 0.00532704 USD. |
| GitHub Copilot CLI | The usage-file JSON (`totalNanoAiu`, `tokenDetails`, `modelMetrics`, `agentMetrics`, and `totalUserRequests`) and non-silent text summary are session-cumulative; `sessionStartTime` remains the initial start time. | Keep the last usage file or summary: 212,218,500 followed by 247,579,500 nanoAIU means 0.25 AI Credits, not 0.46. |
| Junie CLI | Resume behavior was not verified. | Apply the uncertainty rule below. |

If it is unclear whether a value is per-turn or cumulative, state that
uncertainty and list raw values per run without summing them.

## Controller self-usage

Always list the controller's exact model ID, read from its own session record, in the Model column; never leave it blank or write only the product name.
Read the controller's own usage from its local session record before delivery; never write it as Unavailable when that record is readable.
Label controller usage read during the session as "known as of <UTC time>, before delivery"; it excludes the delivery turn itself. Do not estimate the remainder.
In the Source column, write record locations with ~ or a repository-relative path, never an absolute path or user name.

Locate the current session's file by picking the newest file in the documented location whose content contains a unique marker from the current conversation, such as the task key or a recent prompt line; if it cannot be identified with certainty, report Unavailable with that reason rather than guessing.

| Controller | Session record | Usage fields | Model ID | Sub agents |
| --- | --- | --- | --- | --- |
| Claude Code | `~/.claude/projects/<cwd-slug>/<session-id>.jsonl` | Assistant lines carry `message.usage`: `input_tokens`, `cache_creation_input_tokens`, `cache_read_input_tokens`, `output_tokens`. Deduplicate by `message.id`, then sum. Credit and Cost: `Unavailable — not in transcript`. | `message.model` | `~/.claude/projects/<cwd-slug>/<session-id>/subagents/agent-<agent-id>.jsonl`; `isSidechain`, `agentId`, model and usage identify each agent. Deduplicate by `message.id`, then sum; one row per agent file and model. |
| Codex CLI | `~/.codex/sessions/YYYY/MM/DD/rollout-<timestamp>-<thread-id>.jsonl` | `event_msg` `token_count` has `payload.info.total_token_usage`; `token_usage_record` has `payload.thread_token_usage`: `input_tokens`, `cached_input_tokens`, `cache_write_input_tokens`, `output_tokens`, `reasoning_output_tokens`, `total_tokens`. Take the last cumulative value, never sum. Credit and Cost: `Unavailable — not reported in the rollout`. | `turn_context` `payload.model`; effort fields are there too. | Each sub-agent rollout has `session_meta` `payload.parent_thread_id` and `payload.source.subagent.thread_spawn`; use its last `thread_token_usage` and `turn_context` model. Report other sub-agent sources with the same parent, such as `guardian`, as separate labeled rows. |
| GitHub Copilot CLI | `~/.copilot/session-state/<session-id>/events.jsonl` | `session.usage_record` has `data.usage` fields `inputTokens`, `outputTokens`, `cacheReadTokens`, `cacheWriteTokens`, `reasoningTokens`, and `copilotUsage.totalNanoAiu`; `session.usage_checkpoint` has cumulative `data.totalNanoAiu`. The last `session.shutdown` has cumulative `data.accountingSnapshot.totalNanoAiu` and per-model `modelMetrics`, including across resumes. AI Credits = `totalNanoAiu` / 1,000,000,000. | `data.usage.model`; also record `reasoningEffort`, `initiator`, and `interactionType`. | Separate `session.usage_record` rows with `initiator` = `sub-agent` and `interactionType` = `conversation-subagent` by model and `parentToolCallId`; exclude them from the controller row. |

Junie CLI and IDE controllers: use the tool's own reported usage when available; otherwise report `Unavailable — controller self-usage source not verified`.

List every built-in sub agent run as its own row (Role `executor` or `reviewer`, Tool `built-in sub agent`), even when it only probed capability.

## Per-source notes

| Source | What to record |
| --- | --- |
| Codex CLI | From the `turn.completed` event: `usage.input_tokens`, `cached_input_tokens`, `cache_write_input_tokens`, `output_tokens`, and `reasoning_output_tokens`. Credit and cost are `Unavailable` because `codex exec` does not report them. |
| GitHub Copilot CLI | Prefer the JSON from `--usage-output-file <file>`. `agentMetrics` lists `inputTokens`, `outputTokens`, `cacheReadTokens`, `cacheWriteTokens`, `reasoningTokens`, and `totalNanoAiu` by agent and model. Convert only at the ratio verified on 2026-11-24: AI Credits = `totalNanoAiu` / 1,000,000,000. Note the conversion and source field in the Source column. Use the non-silent text summary as a cross-check. |
| Claude Code | The logged-in test verified JSON fields and values for `usage.input_tokens`, `cache_creation_input_tokens`, `cache_read_input_tokens`, `output_tokens`, `modelUsage`, `subagent_stats`, and `total_cost_usd`. `modelUsage` reports `inputTokens`, `outputTokens`, `cacheReadInputTokens`, `cacheCreationInputTokens`, and `costUSD` by model, including models used by sub agents. `costUSD` and `total_cost_usd` are currency amounts calculated at list prices. |
| Junie CLI | Record every `llmUsage` entry, including auxiliary models. Each entry reports `model`, `calls`, `cost`, `inputTokens`, `cacheInputTokens`, `cacheCreateTokens`, and `outputTokens`. Record `cost` as reported and write `currency not stated by Junie` when the currency is absent. Leave amounts with unstated currency unconverted and out of totals. |
| Built-in sub agents (Claude Code) | Interactive results report only total tokens, tool-call count, and duration. `claude -p --output-format json` reports `modelUsage` by model and `subagent_stats` counts. Use model-level attribution for `modelUsage`. For a controller, read `subagents/agent-<agent-id>.jsonl` and deduplicate by `message.id`. |
| Built-in sub agents (GitHub Copilot CLI) | Use `agentMetrics` from `--usage-output-file` to verify and report usage by sub-agent ID and actual model. As controller, use `events.jsonl` `session.usage_record` with `initiator` = `sub-agent`. |
| Built-in sub agents (Codex CLI) | The parent's `turn.completed.usage` excludes sub agents. Each sub-agent rollout identified by `session_meta.parent_thread_id` provides the full breakdown in its last `thread_token_usage`. |

## Waste note

If consumption was unnecessary, add a short note below the table. State the cause
(for example, duplicate run, oversized model, or oversized context) and the
specific improvement that prevents repetition. Do not conceal waste and do not
assign a made-up cost to it.

Example: `Waste: Step 2 was launched twice after an unclear status check. Improvement:
check running executors, worktrees, and branches before dispatching.`
