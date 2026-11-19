<!--
SPDX-FileCopyrightText: 2026 SyuanTsai
SPDX-License-Identifier: Apache-2.0
-->
# Cross-platform validation support

The consumer gate validates this repository on `windows-latest`, `ubuntu-latest`, and `macos-latest`. Repository checks use PowerShell 7 and portable .NET APIs; they do not depend on a Windows-only executable name or filesystem command.

The gate executes `scripts/Test-CodeCollaborationRepository.ps1`, `scripts/Test-CodeCollaborationCatalog.ps1`, and the complete `tests/` tree against an extracted read-only snapshot. Hidden entries are included in inventory checks and path ordering is ordinal on every platform.

Authority selection is controlled by `config/authority-pin.json`. Local diagnostics may run the two general checks with `-RepositoryRoot <snapshot> -ReadOnlySnapshot`, but the pinned three-platform consumer gate remains the release result.

Skill instructions may describe tools available on a user's selected host. That content does not narrow the repository validation matrix.
