# weapon_tweaker — 3P grip OFFSETS reference

Single discoverable home for "which offset surface applies where, and why."
Written after the **+0.569 Scythe failure** (looked right in the inventory model
preview, wrong in-game) so the next maintainer never repeats it. 3P-ONLY topic —
1P (first person) grip is universal across all six characters and is **never**
touched (see `feedback_cross_char_transforms_3p_only`).

> TL;DR: there are TWO offset application paths. A one-shot
> `Unit.set_local_position` written at spawn **survives in the model preview but
> is stomped every animation tick in-game.** Large offsets (e.g. the Scythe's
> +6) MUST use the DURABLE per-frame re-apply path or they revert to raw position
> in-game while still looking correct in the preview.

---

## The offset surfaces that exist

| # | Surface | Where it's set | Persists in-game? | Persists in preview? | Use for |
|---|---------|----------------|-------------------|----------------------|---------|
| 1 | One-shot `set_local_position` on weapon node 0 | `_offset_weapon_units` (`weapon_tweaker.lua`), called from the `GearUtils.create_equipment` hook (in-game path) AND the `MenuWorldPreviewer._spawn_item_unit` hook (preview path) | **NO** (stomped per tick) | **YES** | small static nudges (≤~0.15) where the per-tick stomp isn't visible |
| 2 | DURABLE per-frame re-apply on weapon node 0 | `mod._reapply_durable_grip_offsets` (`weapon_tweaker.lua`), driven every frame from `mod.update` (`weapon_tweaker_backend.lua`) | **YES** | n/a (preview uses #1) | large offsets the stomp would erase (the Scythe) |
| 3 | `unit_attachment_node_linking.third_person` raw write on the weapon TEMPLATE | (not used for cross-character) | YES | YES | **FORBIDDEN for shared templates** — the linking table is shared with the NATIVE wielder, so a raw write breaks their grip |

The offset **value** for both #1 and #2 lives in ONE place: the
`_weapon_grip_offsets` table in `weapon_tweaker.lua`. `_DURABLE_GRIP_OFFSETS` (a
sibling table) is just the membership set of weapon_keys that ALSO need the
per-frame re-apply. Single source of truth — never split the value across files.

### Active offsets (catalog)

| Weapon (key) | Receiver | Offset (x,y,z) | Path | Notes |
|---|---|---|---|---|
| Necromancer Ghost Scythe (`bw_ghost_scythe`) | Kruber (`es_`) | `{0, 0, 6}` | #2 durable | renders as Greathammer; `es_`-only; v0.12.151-dev |
| Elven 2H Axe / Glaive (`we_2h_axe`, `two_handed_axes_template_2`) | Kruber (`es_`) | `{0, 0, 0.285}` | #2 durable | renders as Greathammer; `es_`-only; +0.285 Z; v0.12.152-dev. Grip offset is independent of the anim bake — the Glaive's 3P anim is NOT yet baked (still in the dev picker). |

The small static nudges (`we_1h_sword`/`bw_sword`/`es_1h_sword` +0.05, the wh hammers
+0.15, the `es_2h_sword`/`wh_2h_sword` −0.085) use path #1 only and are not listed
here — they're tiny enough that the per-tick stomp isn't visible. See
`_weapon_grip_offsets` in `weapon_tweaker.lua` for the full set.

---

## The preview-OK / in-game-wrong failure (post-mortem)

**Symptom:** the Necromancer Ghost Scythe on Kruber (`bw_ghost_scythe`, `es_`
careers) looked correctly gripped in the character-screen **model preview** at a
`+0.569` Z offset, but in **actual gameplay** the grip was wrong (hands not on
the haft) — and bumping the value didn't help in-game.

**Root cause:** the offset was applied as a one-shot `Unit.set_local_position` on
the weapon unit's node 0 at spawn (path #1). In-game, the running animation
system re-applies each weapon unit's **canonical attachment-node pose every
frame** (the next tick after spawn), which resets node 0 and **erases our
offset**. The model preview does NOT continuously re-drive node 0
(`MenuWorldPreviewer` poses the weapon once), so the one-shot survives there.
Net result: preview shows the offset, in-game shows raw position.

This is **source-confirmed** by the dev tool that was used to TUNE the value:
`wt_dev_hold_pose.lua:16-21` —

> "a one-shot `Unit.set_local_pose` write is overwritten on the very next
> animation tick when the engine re-applies the canonical attachment-node pose.
> Hooking a per-frame state update and re-writing the local pose every frame
> keeps the slider value visible."

The dev tuner only works in-game because it re-applies **every frame**. The
static `_offset_weapon_units` did not — so the tuned number never actually held
in gameplay.

**Fix (v0.12.151-dev):**
1. Bumped the Scythe to `+6` Z in `_weapon_grip_offsets` (single source).
2. Added `_DURABLE_GRIP_OFFSETS = { bw_ghost_scythe = true }` and
   `mod._reapply_durable_grip_offsets()`, driven every frame from `mod.update`.
   It re-applies the same offset to the local player's wielded 3P scythe unit so
   the engine's per-tick reset can't stomp it — exactly the mechanism the dev
   tuner proved.
3. The preview path keeps using path #1 (the one-shot survives there), reading
   the SAME `_weapon_grip_offsets` value, so preview and in-game share one number.

---

## Additive-from-canonical (why it never compounds)

Both paths are **additive**: they read node 0's current local position and add
the offset (`current + pos`), rather than setting an absolute pose. That matters:

- The one-shot path (#1) adds once on top of the spawn-time canonical pose.
- The durable path (#2) reads the **freshly-reset** canonical pose the engine
  wrote *this* tick, then adds the offset. Because the engine zeroes our prior
  write before we read each frame, `canonical + offset` is **stable
  frame-to-frame and never accumulates**. (Read-and-add would be a compounding
  bug if the engine did NOT reset — here the reset is exactly what makes a
  one-shot fail, and exactly what makes the per-frame read-and-add safe.)

Because both paths add the same delta from the same canonical pose, the SAME
value in `_weapon_grip_offsets` produces the same visual result in preview and
in-game.

---

## Invariants (do not break)

- **3P-ONLY.** Every offset write targets `right_unit_3p` / `left_unit_3p` only.
  NEVER the `*_unit_1p` units. First person is universal and vanilla-correct; the
  `*_1p` fields were a latent bug once (every offset silently shifted 1P) and
  were removed in v0.12.136-dev. (`feedback_cross_char_transforms_3p_only`.)
- **CAREER-ONLY.** Offsets are prefix-gated (`es_` = Kruber, etc.). The native
  wielder's career prefix finds no entry → offset stays nil → early return. The
  Scythe's `es_` entry never moves Sienna's native scythe.
- **NEVER raw-write a shared linking table.** `unit_attachment_node_linking
  .third_person` on `staff_scythe` is shared with Sienna — a raw write there
  would break her grip. The durable re-apply is career-gated instead.
- **LOCAL player only** for the durable path (owner-authoritative; husks re-pose
  from their own host). Keeps the per-frame cost to one unit.
- **SINGLE SOURCE OF TRUTH.** The offset value lives only in
  `_weapon_grip_offsets`. `_DURABLE_GRIP_OFFSETS` carries no values, just keys.

---

## How to add / change an offset

1. Set the value in `_weapon_grip_offsets[weapon_key] = { <career_prefix>_ = {x, y, z[, hand="right"|"left"]} }`.
2. If the offset is large enough that it doesn't visually hold in-game (anything
   that gets stomped — generally anything beyond a tiny nudge), ALSO add
   `<weapon_key> = true` to `_DURABLE_GRIP_OFFSETS`.
3. Tune live with the dev hold-pose tuner (`/wt_dump_hold_pose` →
   `wt_dev_hold_pose.lua`), which does the same per-frame re-apply, so the number
   you see while tuning is the number that will hold in-game on the durable path.
4. Verify in BOTH the inventory model preview AND in actual gameplay — they
   should match. If they don't, the value is being read from two places (bug) or
   one path is missing.
