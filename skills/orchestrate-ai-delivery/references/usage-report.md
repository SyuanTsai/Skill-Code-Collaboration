<!--
SPDX-FileCopyrightText: 2026 SyuanTsai
SPDX-License-Identifier: Apache-2.0
-->

# Usage report reference

Verified on 2026-11-02 with claude 2.1.309, codex-cli 0.154.0, GitHub Copilot CLI 1.0.80 (Windows host). Re-verify with each CLI's --help after upgrades.

Record usage after every controller, executor, and reviewer run. Use the table
format below; one row is one reportable run or the last cumulative value for a
resumed session.

| Role | Step | Tool (CLI or sub agent) | Model | Effort | Input tokens | Output tokens | Credit (with unit) | Cost (currency) | Source |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| controller | Planning | `<tool>` | `<model>` | `<effort>` | `<value or Unavailable>` | `<value or Unavailable>` | `<value and unit or Unavailable>` | `<value and currency or Unavailable>` | `<event, result, or summary>` |
| executor | Step 1 | `<tool>` | `<model>` | `<effort>` | `<value or Unavailable>` | `<value or Unavailable>` | `<value and unit or Unavailable>` | `<value and currency or Unavailable>` | `<event, result, or summary>` |
| reviewer | Step 1 | `<tool>` | `<model>` | `<effort>` | `<value or Unavailable>` | `<value or Unavailable>` | `<value and unit or Unavailable>` | `<value and currency or Unavailable>` | `<event, result, or summary>` |
| Total (tokens only) | All Steps | — | — | — | `<input-token total>` | `<output-token total>` | Unavailable — different units are separate | Unavailable — currency is separate | Sum only compatible token values |
| Total (AI Credits) | All Steps | — | — | — | Unavailable — credits are not tokens | Unavailable — credits are not tokens | `<AI Credit total>` | Unavailable — currency is separate | Sum text-summary AI Credits only |
| Total (nanoAIU) | All Steps | — | — | — | Unavailable — raw unit only | Unavailable — raw unit only | `<totalNanoAiu total, raw nanoAIU>` | Unavailable — currency is separate | Sum only raw nanoAIU values when their scope is known |
| Total (currency) | All Steps | — | — | — | Unavailable — currency is not tokens | Unavailable — currency is not tokens | Unavailable — currency is not a credit | `<currency total>` | Sum only the same currency |

Write `Unavailable` (or the conversation-language equivalent, such as 無法取得)
and the reason whenever a value is absent. For example: `Unavailable — not reported
by codex exec`. Never estimate, infer, or back-calculate a missing field.

Keep units separate. Codex reports tokens only. Copilot's text summary reports AI
Credits, input, and output; JSON also has raw `totalNanoAiu`, which must not be
converted to AI Credits. Claude reports `total_cost_usd` as currency. Never add
tokens, CLI credits, other-tool usage, nanoAIU, and monetary cost together.

For a resumed session, count a session-cumulative figure once: retain its last
cumulative value only. Example: three resumes report 10k, then 25k, then 40k
cumulative tokens. Report 40k, not 75k. If it is unclear whether a value is
per-turn or cumulative, state that uncertainty and list raw values per run without
summing them.

## Per-source notes

| Source | What to record |
| --- | --- |
| Codex CLI | From the `turn.completed` event: `usage.input_tokens`, `cached_input_tokens`, `cache_write_input_tokens`, `output_tokens`, and `reasoning_output_tokens`. Credit and cost are `Unavailable` because `codex exec` does not report them. |
| GitHub Copilot CLI | Prefer the non-silent text summary for AI Credits plus input and output tokens. JSON supplies `assistant.message.data.outputTokens`, raw `session.usage_checkpoint.data.totalNanoAiu`, and `result.usage.premiumRequests`, but no input tokens. AI-Credit conversion from nanoAIU is **Unverified**; do not convert. |
| Claude Code | JSON result fields include `usage.input_tokens`, `cache_creation_input_tokens`, `cache_read_input_tokens`, `output_tokens`, per-model `modelUsage`, and currency `total_cost_usd`. Field structure was seen, but values are **Unverified** because login was unavailable during verification. |
| Built-in sub agents | Record only reported total tokens, tool-call count, duration, or other explicitly reported values. If input/output split, credit, cost, or per-agent attribution is absent, write `Unavailable` with that reason. |

## Waste note

If consumption was unnecessary, add a short note below the table. State the cause
(for example, duplicate run, oversized model, or oversized context) and the
specific improvement that prevents repetition. Do not conceal waste and do not
assign a made-up cost to it.

Example: `Waste: Step 2 was launched twice after an unclear status check. Improvement:
check running executors, worktrees, and branches before dispatching.`
