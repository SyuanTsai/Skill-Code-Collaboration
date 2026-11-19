<!--
SPDX-FileCopyrightText: 2026 SyuanTsai
SPDX-License-Identifier: Apache-2.0
-->
# Rollback

Rollback keeps the consumer gate intact. Revert the affected repository change in a new reviewed commit and require the pinned three-platform consumer gate to pass again.

If the failure was introduced by an authority upgrade, restore the previously reviewed immutable `commit` in `config/authority-pin.json`. Do not rewrite a released tag, replace the bootstrap, or introduce repository-local authority policy.

If initial conversion is withdrawn before merge, withdraw the conversion as a unit. After conversion has merged, cleanup removes only the transition workflow; the permanent consumer gate, both general checks, and the complete `tests/` suite remain required.

Consumers must treat an unavailable Skill as absent and must not delete unrelated Skill content during rollback.
