<!--
SPDX-FileCopyrightText: 2026 SyuanTsai
SPDX-License-Identifier: Apache-2.0
-->

# Usage report reference

Verified on 2026-11-24 with claude 2.1.317, codex-cli 0.166.0, GitHub Copilot CLI 1.0.105, and Junie 26.11.2 (Windows host). Re-verify with each CLI's --help after upgrades.

Record usage after every controller, executor, and reviewer run. Use the table
format below. For a resumed session, follow Resumed sessions below. List
separate rows when the source reports usage by agent or model.

| Role | Step | Tool (CLI or sub agent) | Model | Effort | Input tokens | Output tokens | Credit (with unit) | Cost (currency) | Source |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| controller | Planning | `<tool>` | `<model>` | `<effort>` | `<value or Unavailable>` | `<value or Unavailable>` | `<value and unit or Unavailable>` | `<value and currency or Unavailable>` | `<event, result, or summary>` |
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

## Per-source notes

| Source | What to record |
| --- | --- |
| Codex CLI | From the `turn.completed` event: `usage.input_tokens`, `cached_input_tokens`, `cache_write_input_tokens`, `output_tokens`, and `reasoning_output_tokens`. Credit and cost are `Unavailable` because `codex exec` does not report them. |
| GitHub Copilot CLI | Prefer the JSON from `--usage-output-file <file>`. `agentMetrics` lists `inputTokens`, `outputTokens`, `cacheReadTokens`, `cacheWriteTokens`, `reasoningTokens`, and `totalNanoAiu` by agent and model. Convert only at the ratio verified on 2026-11-24: AI Credits = `totalNanoAiu` / 1,000,000,000. Note the conversion and source field in the Source column. Use the non-silent text summary as a cross-check. |
| Claude Code | The logged-in test verified JSON fields and values for `usage.input_tokens`, `cache_creation_input_tokens`, `cache_read_input_tokens`, `output_tokens`, `modelUsage`, `subagent_stats`, and `total_cost_usd`. `modelUsage` reports `inputTokens`, `outputTokens`, `cacheReadInputTokens`, `cacheCreationInputTokens`, and `costUSD` by model, including models used by sub agents. `costUSD` and `total_cost_usd` are currency amounts calculated at list prices. |
| Junie CLI | Record every `llmUsage` entry, including auxiliary models. Each entry reports `model`, `calls`, `cost`, `inputTokens`, `cacheInputTokens`, `cacheCreateTokens`, and `outputTokens`. Record `cost` as reported and write `currency not stated by Junie` when the currency is absent. Leave amounts with unstated currency unconverted and out of totals. |
| Built-in sub agents (Claude Code) | Interactive results report only total tokens, tool-call count, and duration. `claude -p --output-format json` reports `modelUsage` by model and `subagent_stats` counts. Use model-level attribution for `modelUsage`. |
| Built-in sub agents (GitHub Copilot CLI) | Use `agentMetrics` from `--usage-output-file` to verify and report usage by sub-agent ID and actual model. |
| Built-in sub agents (Codex CLI) | The parent's `turn.completed.usage` excludes sub agents. Report `Unavailable — not reported by codex exec` unless the controller can read the sub agent's total token count from local Codex thread state. Report that value as total tokens. Mark the token breakdown unavailable. |

## Waste note

If consumption was unnecessary, add a short note below the table. State the cause
(for example, duplicate run, oversized model, or oversized context) and the
specific improvement that prevents repetition. Do not conceal waste and do not
assign a made-up cost to it.

Example: `Waste: Step 2 was launched twice after an unclear status check. Improvement:
check running executors, worktrees, and branches before dispatching.`
