<!--
SPDX-FileCopyrightText: 2026 SyuanTsai
SPDX-License-Identifier: Apache-2.0
-->
# Skill Code Collaboration

## Overview

**What it is:** Two Agent Skills for AI-assisted software delivery.

**Problem it solves:** An AI controller plans one Jira issue, delegates implementation, and reviews the result. The user must approve commits, pushes, and Jira writes.

**Key Skills**

| Skill | What it does |
| --- | --- |
| [`orchestrate-ai-delivery`](skills/orchestrate-ai-delivery/SKILL.md) | Breaks one Jira issue into steps and dispatches each step to Claude CLI, Codex CLI, Copilot CLI, or a built-in subagent with an explicit model. Reviews diffs, addresses valid findings, runs required tests, and stops for human approval. |
| [`write-implementation-prompt`](skills/write-implementation-prompt/SKILL.md) | Writes a self-contained implementation prompt scoped to the target repository and recommends an executor, an exact model, and a reasoning effort level. |

**Platform:** The catalog lists both Skills for any platform. Repository validation uses PowerShell 7 on Windows, Linux, and macOS.

**Quick start:**

1. Install these Agent Skills via [SyuanTsai-AI-Instructions](https://github.com/SyuanTsai/SyuanTsai-AI-Instructions).
2. Enable the opt-in `ai-delivery` profile listed in the [profile catalog](catalog/profiles.json).
3. Invoke `orchestrate-ai-delivery` or `write-implementation-prompt` by name in your request.

**License:** The repository-authored content is licensed under [Apache-2.0](LICENSE). See the [licensing scope](#license-and-scope).

## 概覽

**這是什麼：** 兩個用於 AI 輔助軟體交付的 Agent Skills。

**解決的問題：** 由負責協調的 AI 為單一 Jira 議題規劃工作、委派實作並審查結果。Git commit、push 和寫入 Jira 都須經使用者同意。

**主要 Skills**

| Skill | 功能 |
| --- | --- |
| [`orchestrate-ai-delivery`](skills/orchestrate-ai-delivery/SKILL.md) | 將單一 Jira 議題拆成步驟，為每個步驟指定模型，再交給 Claude CLI、Codex CLI、Copilot CLI 或內建子代理程式執行。審查變更差異、處理經確認的問題、執行必要測試，並停下來等待人工核准。 |
| [`write-implementation-prompt`](skills/write-implementation-prompt/SKILL.md) | 撰寫一份可獨立使用、以目標儲存庫為範圍的實作提示詞，並推薦執行者、確切的模型及推理強度。 |

**平台：** 目錄將兩個 Skill 都列為適用於任何平台。儲存庫在 Windows、Linux 和 macOS 上使用 PowerShell 7 進行驗證。

**快速開始：**

1. 透過 [SyuanTsai-AI-Instructions](https://github.com/SyuanTsai/SyuanTsai-AI-Instructions) 安裝這兩個 Agent Skills。
2. 啟用 [profile 目錄](catalog/profiles.json) 中預設停用的 `ai-delivery` profile。
3. 在請求中指定 `orchestrate-ai-delivery` 或 `write-implementation-prompt` 的名稱來呼叫。

**授權：** 本儲存庫自行撰寫的內容採用 [Apache-2.0](LICENSE) 授權。詳見[授權範圍](#license-and-scope)。

---

Independent Agent Skills source repository for code-delegation workflows.

- Stable source ID: `code-collaboration`
- Source inventory: `catalog/source.json`
- Profile catalog: `catalog/profiles.json`
- Current version: `0.1.0`

## Skills

| Skill | Profile | Purpose |
| --- | --- | --- |
| `orchestrate-ai-delivery` | `ai-delivery` | Plan, dispatch, review, and gate delivery of one Jira issue through a selected controller and executor. |
| `write-implementation-prompt` | `ai-delivery` | Create a repository-scoped implementation prompt and recommend an exact available executor model. |

Name a Skill or make a request matching its description to invoke it. The orchestration Skill never commits, pushes, or writes Jira without the user's consent; work-environment Jira issues remain read-only.

## Repository contract

`catalog/source.json` is the canonical active-Skill inventory. `catalog/profiles.json` defines the opt-in `ai-delivery` profile and its dependency relationships. Stable package paths are:

- `skills/orchestrate-ai-delivery`
- `skills/write-implementation-prompt`

The repository-specific checks are:

- `scripts/Test-CodeCollaborationRepository.ps1`
- `scripts/Test-CodeCollaborationCatalog.ps1`
- the complete `tests/` Pester suite

The two PowerShell checks accept `-RepositoryRoot` and `-ReadOnlySnapshot`, operate on an extracted snapshot without Git metadata, and write results to standard output without changing the candidate.

## Consumer gate

Validation is owned by the pinned authority and runs through the `consumer-gate` workflow on Windows, Linux, and macOS. The repository bootstrap reads `config/authority-pin.json`; routine authority upgrades change only that file's `commit`. `config/consumer-gate.json` binds this repository, the active Skill inventory, and the three repository checks above.

The transition workflow is temporary during conversion. After conversion, the cleanup pull request removes only that workflow; the permanent gate, bootstrap, configuration, checks, and full test suite remain.

See [release](docs/RELEASE.md), [rollback](docs/ROLLBACK.md), [consumer-gate adoption](docs/SOURCE-VALIDATION-ADOPTION.md), and [cross-platform support](docs/WINDOWS-SUPPORT.md).

## License and scope

The Apache-2.0 license applies to repository-authored Skills, metadata, catalogs, documentation, checks, tests, and workflow configuration. External services, credentials, tenant data, and user-supplied content remain outside that grant. See [PROVENANCE.md](PROVENANCE.md) and [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

This repository owns only Code Collaboration Skills and their directly required metadata, references, tests, and release contract.
