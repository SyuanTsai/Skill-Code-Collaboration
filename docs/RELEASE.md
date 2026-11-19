<!--
SPDX-FileCopyrightText: 2026 SyuanTsai
SPDX-License-Identifier: Apache-2.0
-->
# Release contract

This repository uses the pinned authority consumer gate on Windows, Linux, and macOS. The gate executes `scripts/Test-CodeCollaborationRepository.ps1`, `scripts/Test-CodeCollaborationCatalog.ps1`, and the complete `tests/` Pester suite from a read-only candidate snapshot.

For a release:

1. Keep `VERSION` and the intended SemVer tag aligned.
2. Confirm `catalog/source.json` and `catalog/profiles.json` expose only the intended active Skills and profiles.
3. Require the three-platform consumer gate to pass with no skipped, inconclusive, or unexecuted Pester cases.
4. Merge through the protected branch process and create an immutable annotated tag.

Authority validation is selected only by the immutable commit in `config/authority-pin.json`. A routine authority upgrade changes only that value and must pass the same consumer gate. Do not copy authority-owned validation logic into this repository.

During initial conversion, the transition workflow validates the conversion pull request. The following cleanup pull request deletes only the transition workflow; the permanent consumer gate continues to validate the full test suite.
