<!--
SPDX-FileCopyrightText: 2026 SyuanTsai
SPDX-License-Identifier: Apache-2.0
-->
# Rollback

Rollback is source-pin based. Do not rewrite a released tag or force-update a consumer to a different commit under the same version.

Windows is the only supported host for local installation, execution, testing, rollback verification, and CI. Use PowerShell (pwsh) for repository commands; Linux/macOS hosts, WSL, and Linux containers are unsupported.

## Consumer rollback

1. Stop selecting the affected profile if the Skill must be removed immediately.
2. Restore the consumer's previous `code-collaboration` requested ref, resolved commit SHA, and content SHA-256.
3. Re-run the consumer's resolver/discovery step.
4. Verify the available Skill set matches the restored pin and that capability filtering is applied again.
5. Remove only artifacts managed by the newer source pin; do not delete unrelated `skills/` content.

## Repository rollback

If a released change must be reverted, create a new commit that restores the previous behavior and release a new patch version. Never move or overwrite an existing release tag.

## Safe fallback behavior

Consumers must treat an unavailable or uninstalled Skill as absent. They must not assume a direct `skills/...` path exists merely because a related workflow exists in another source repository.

## Protected source-validation fallback

The source-validation adoption route is opt-in and is not yet a required CI gate. If its preparation or validation fails, retain the setup receipts, raw process output, Core report, stage timing file, completed setup timing file, and source-validation timing file for diagnosis, then continue using the established Standard v1 route with `pwsh -File ./scripts/Validate.ps1` and the active 8a authority pin. Do not reuse a prepared `source-tools.json` after changing the candidate, authority checkout, runtime, or tool closure; create a new run-owned preparation. To roll back an adopted repository change, revert it in a new commit and restore the previous approved authority/source pin through the normal release process.
