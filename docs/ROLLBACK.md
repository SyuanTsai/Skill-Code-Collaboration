# Rollback

Rollback is source-pin based. Do not rewrite a released tag or force-update a consumer to a different commit under the same version.

## Consumer rollback

1. Stop selecting the affected profile if the Skill must be removed immediately.
2. Restore the consumer's previous `code-collaboration` requested ref, resolved commit SHA, and content SHA-256.
3. Re-run the consumer's resolver/discovery step.
4. Verify the available Skill set matches the restored pin and that capability filtering is applied again.
5. Remove only artifacts managed by the newer source pin; do not delete unrelated `.agents/skills` content.

## Repository rollback

If a released change must be reverted, create a new commit that restores the previous behavior and release a new patch version. Never move or overwrite an existing release tag.

## Safe fallback behavior

Consumers must treat an unavailable or uninstalled Skill as absent. They must not assume a direct `.agents/skills/...` path exists merely because this repository contains that Skill. This allows consumers to omit the Copilot or Bitbucket profile independently without producing a broken path.

For `review-bitbucket-pull-request`, a consumer must also exclude the Skill from its available set when `git` is unavailable or when neither supported Bitbucket access capability is configured.
