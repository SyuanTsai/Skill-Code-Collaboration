<!--
SPDX-FileCopyrightText: 2026 SyuanTsai
SPDX-License-Identifier: Apache-2.0
-->
# Rollback

Rollback is source-pin based. Do not rewrite a released tag or force-update a consumer to a different commit under the same version.

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

## Protected full-source gate rollback

The current required CI gate is the protected full-source route with the active ff85/32 authority tuple. If preparation or validation fails, retain the setup receipts, raw process output, Core report, Pester case inventory, stage timing file, completed setup timing file, and source-validation timing file; the required check must remain failed until a reviewed fix passes. Do not reuse a prepared `source-tools.json` after changing the candidate, authority checkout, runtime, or tool closure; create a fresh run-owned preparation.

To roll the repository back to the previous 8a behavior, revert the Phase B activation in a new reviewed commit so the active config and CI route are restored together. Do not treat the unqualified `pwsh -File ./scripts/Validate.ps1` legacy route as a successful substitute for the current required gate. Release tags remain immutable.
