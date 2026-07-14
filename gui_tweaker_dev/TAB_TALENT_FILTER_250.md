# Issue #250: Chaos Wastes held-Tab talent normalization

## Source boundary

The v2 `IngamePlayerListUI._update_dynamic_widget_information` reads
`talent_extension:get_talent_ids()` and assigns indices 1 through 6 directly to
the six tier widgets. In Chaos Wastes those IDs are not a six-position build:
`DeusRunController._add_initial_power_ups` turns selected loadout talents into
power-ups, `DeusPowerUpUtils.activate_deus_power_up` appends later talent boons,
and `DeusMechanism` stores the resulting flat list in the Deus talents backend.

This makes vanilla's positional assumption fail when a build has an empty tier
or when a purchased/event boon duplicates a tier. Every later icon shifts and a
duplicate can be shown in the wrong tier cell.

## Repair

While the existing held-Tab update hook is active in the `deus` mechanism, GUT
post-processes only the six talent widget contents. It maps every active ID back
through the current career's `TalentTrees` rows, places the first active ID in
its real tier, and leaves empty tiers empty. Initial loadout power-ups are added
before purchased/event boons, so first-per-tier preserves the selected build
when a later boon duplicates that tier.

The implementation does not replace or mutate `get_talent_ids`, the Deus
backend, power-ups, buffs, networking, talent trees, or privacy state. It owns no
second hook on the shared player-list method and caps unique repair diagnostics
at sixteen lines per process.

## Known presentation limit

The stock player list has exactly one widget per tier, so it cannot display two
simultaneously active talents from the same tier. The selected/first talent is
shown; the boon remains active in gameplay and remains visible in native Chaos
Wastes boon presentations.

## Verification

In a Chaos Wastes run, use a build with one unselected tier, then acquire a
talent boon. Hold Tab and confirm talents remain in their actual tier rows, the
empty tier remains empty, and no later icons shift. Repeat with a boon from an
already selected tier and confirm the selected talent remains in that cell.
Attach the bounded `[gut:250]` line and run `/gut_regression_test`; both #250
checks must pass.
