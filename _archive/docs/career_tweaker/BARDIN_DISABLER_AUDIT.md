> [!WARNING]
> ⚠ **SUPERSEDED** — this snapshot is from 2026-07-12 (21 days old).
> Recent state may differ. Kept for historical context — verify against current
> code before acting on findings. Remove this banner manually after a refresh
> or move the doc to `_archive/audits/2026-07-12/`.
# Bardin and disabler dodge audit — issue #440

Audit date: 2026-07-14. Source: the local 2026-07-12 Vermintide 2 Lua decompile.

## Conclusion

The Lua source does not establish a Bardin-specific dodge disadvantage, so Career
Tweaker does not alter his dodge distance, invulnerability/status window, capsule,
or enemy targeting. Every hero receives a clone of the same global
`PlayerUnitMovementSettings` table. Bardin's shorter `first_person_heights.stand`
value controls camera presentation; none of the three audited disabler paths reads
it.

One uncertainty remains outside the decompiled Lua: the player units are different
compiled assets, so their mover/trigger actors and `j_neck` node can differ. This is
most relevant to Gutter Runners, whose pounce uses a trigger overlap and later neck
tracking. Version 0.3.68 therefore adds bounded comparative diagnostics instead of
a speculative balance change.

## Shared dodge path

`player_movement_settings.lua:3-21,138-169` owns one global settings table and
`register_unit` clones it per unit. Its baseline is distance 2, a common six-point
speed curve, cooldown 0.15, and dodge/jump override 0.35. The dodge state reads that
per-unit clone, sets the same networked `dodging` status, and derives displacement
from the live weapon/buff modifiers (`player_character_state_dodging.lua:38-52,
225-364`). There is no profile-name branch in either file.

`sp_profiles.lua:211-249` does give Bardin a 1.3 standing first-person height,
compared with taller camera values on other heroes. That table is consumed by the
first-person presentation extension; the dodge state and audited disablers do not
read it. Camera height is therefore not evidence of a shorter gameplay dodge.

## Disabler paths

### Packmaster

At its animation callback, `BTPackMasterAttackAction.attack_success` reads the
target's common `get_is_dodging()` flag. A dodge succeeds or fails from the authored
angle/distance gates plus line of sight (`bt_pack_master_attack_action.lua:108-139`).
It never reads profile, camera height, neck node, or player capsule dimensions.

### Lifeleech

`BTCorruptorGrabAction` records whether the common dodge flag became active while
the projectile was in flight. At resolution it combines that flag with projectile
distance, angle/distance gates, and line of sight (`bt_corruptor_grab_action.lua:
108-121,183-238`). Its aim points are both root positions plus the same `Vector3.up()`
offset (`:139-144`). No profile-specific branch exists.

### Gutter Runner

This path is different and is the reason diagnostics remain useful. The initial
trajectory targets the player's root plus exactly 0.2 metres
(`bt_prepare_for_crazy_jump_action.lua:188-219`). In flight it checks a one-metre
sphere against `filter_player_and_husk_trigger`; close snapping tracks each target's
`j_neck` node (`bt_crazy_jump_action.lua:163-205,244-292,413-430,454-471`). It does
not inspect dodge status at all: a successful dodge is purely spatial. Different
compiled trigger or neck geometry could therefore influence a marginal pounce even
though the Lua algorithm is profile-neutral.

## Armed evidence

`_crt_bardin_disabler_probe.lua` automatically logs `[crt:440]` rows. It emits one
profile summary per hero encountered, at most 16 completed local dodge rows when a
disabler is within 25 metres, then at most 16 resolution rows for each disabler
type. Rows include profile, outcome, whether the common dodge status was
active, elapsed dodge time, displacement, remaining dodge distance, attacker
distance, root-to-neck height, actor count, and the disabler-specific tracking gate.
No chat command is required and no gameplay value is written. In co-op, the client
log owns exact local dodge timing while the host log owns authoritative AI outcome;
their timestamps provide the comparison without new RPC traffic.

Useful verification needs Bardin and at least one non-Bardin control under comparable
latency, weapon and dodge direction. Repeated Packmaster, Lifeleech, and Gutter Runner
attempts can then distinguish:

- identical timing but different outcomes: inspect attack distance/tracking geometry;
- delayed or absent dodge status: timing/input/network boundary;
- Gutter-only disparity with similar timing: compiled trigger/neck geometry candidate;
- no outcome separation across repeated controls: anecdote not reproduced; close with
  no balance change.
