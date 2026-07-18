# weapon_tweaker — 3P grip OFFSETS reference

Single discoverable home for "which offset surface applies where, and why."
Written after the **+0.569 Scythe failure** (looked right in the inventory model
preview, wrong in-game) so the next maintainer never repeats it. 3P-ONLY topic —
1P (first person) grip is universal across all six characters and is **never**
touched (see `feedback_cross_char_transforms_3p_only`).

> TL;DR: there are TWO offset application paths. A one-shot
> `Unit.set_local_position` written at spawn **survives in the model preview but
> is stomped every animation tick in-game.** Large offsets (e.g. the Scythe's
> +0.6) MUST use the DURABLE per-frame re-apply path or they revert to raw position
> in-game while still looking correct in the preview.

---

## The offset surfaces that exist

| # | Surface | Where it's set | Persists in-game? | Persists in preview? | Use for |
|---|---------|----------------|-------------------|----------------------|---------|
| 1 | One-shot `set_local_position` on weapon node 0 | `_offset_weapon_units` (`weapon_tweaker.lua`), called from the `GearUtils.create_equipment` hook (in-game path) AND the `MenuWorldPreviewer._spawn_item_unit` hook (preview path) | **NO** (stomped per tick) | **YES** | small static nudges (≤~0.15) where the per-tick stomp isn't visible |
| 2 | DURABLE per-frame re-apply on weapon node 0 | Spawn/wield weak tracker + `mod._reapply_durable_grip_offsets` (`weapon_tweaker.lua`), driven every frame from `mod.update` (`weapon_tweaker_backend.lua`) | **YES**, on owner, bot, and remote-husk renderers | n/a (preview uses #1) | large offsets the stomp would erase (the Scythe) |
| 3 | `unit_attachment_node_linking.third_person` raw write on the weapon TEMPLATE | (not used for cross-character) | YES | YES | **FORBIDDEN for shared templates** — the linking table is shared with the NATIVE wielder, so a raw write breaks their grip |

The offset **value** for both #1 and #2 lives in ONE place: the
`_weapon_grip_offsets` table in `weapon_tweaker.lua`. `_DURABLE_GRIP_OFFSETS` (a
sibling table) is just the membership set of weapon_keys that ALSO need the
per-frame re-apply. Single source of truth — never split the value across files.

### Active offsets (catalog)

| Weapon (key) | Receiver | Offset (x,y,z) | Path | Notes |
|---|---|---|---|---|
| Necromancer Ghost Scythe (`bw_ghost_scythe`) | Kruber (`es_`) | `{0, 0, 0.6}` | #2 durable | renders as Greathammer; `es_`-only; corrected in v0.12.153-dev; husk fan-out v0.12.229-dev |
| Elven 2H Axe / Glaive (`we_2h_axe`, `two_handed_axes_template_2`) | Kruber (`es_`) | `{0, 0, 0.285}` | #2 durable | renders as Greathammer; `es_`-only; +0.285 Z; v0.12.152-dev. Grip offset is independent of the anim bake — the Glaive's 3P anim is NOT yet baked (still in the dev picker). |
| Empire Handgun (`es_handgun`) | Saltzpyre (`wh_`) | `{0, -0.17, -0.05}` | #2 durable | Restores the receiver-scoped correction lost after the unsafe shared-linking-table bake was removed in v0.12.136; standard Saltzpyre careers only; v0.12.249-dev. |
| Saltzpyre Crossbow (`wh_crossbow`) | Kruber (`es_`) | `{0, 0.100, 0.025, hand="left"}` | #2 durable | User-recorded LEFT-hand offset (#701, spec in issue 109 census). `hand="left"` = the crossbow's only 3P unit (template declares left_hand_unit only, linked j_leftweaponattach); explicit scoping guards the issue 735 paired-unit class. v0.12.275-beta. |

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

This is also the boundary used by the dev Hold-Pose tuner: a one-shot write is
overwritten on the next animation tick, so its live mode re-applies every
frame. Since v0.12.222-dev (#569 follow-up), the tuner never writes an absolute
`set_local_pose`: it composes position and rotation deltas independently over a
captured canonical/baked pose, preserving the untouched component and scale.

The dev tuner works in-game because it re-applies **every frame**. The
static `_offset_weapon_units` did not — so the tuned number never actually held
in gameplay.

**Fix (v0.12.151-dev, value corrected in v0.12.153-dev):**
1. Baked the Scythe offset in `_weapon_grip_offsets` (single source); the current
   corrected value is `+0.6` Z.
2. Added `_DURABLE_GRIP_OFFSETS = { bw_ghost_scythe = true }` and
   `mod._reapply_durable_grip_offsets()`, driven every frame from `mod.update`.
   Since v0.12.229-dev, owner, bot, and remote-husk renderers register their 3P
   unit at spawn/wield and reapply the same shipped value, so the engine's
   per-tick reset cannot stomp it on any viewer.
3. The preview path keeps using path #1 (the one-shot survives there), reading
   the SAME `_weapon_grip_offsets` value, so preview and in-game share one number.

---

## Additive-from-canonical (why it never compounds)

Both paths preserve the spawn-time canonical pose and add the baked delta:

- The one-shot path (#1) adds once on top of the spawn-time canonical pose.
- The durable path (#2) boxes the canonical pose before the one-shot spawn write,
  then sets `boxed canonical + offset` each tick. This absolute reconstruction is
  **stable frame-to-frame and never accumulates**, independent of hook order.

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
- **POSITION COMPOSES.** Baked offsets use only `Unit.set_local_position`.
  Rotation (#569) and scale retain their own canonical setters, so the Handgun's
  Y/Z correction cannot zero either component.
- **NEVER raw-write a shared linking table.** `unit_attachment_node_linking
  .third_person` on `staff_scythe` is shared with Sienna — a raw write there
  would break her grip. The durable re-apply is career-gated instead.
- **Renderer-local owner/bot/husk fan-out.** Vanilla remote husks do not call
  `GearUtils.create_equipment`; WT registers their spawned 3P units after
  `SimpleHuskInventoryExtension._wield_slot`. Every client reads identical baked
  tables from its installed WT. No transform RPC or per-frame network payload is
  created, and transient Hold-Pose sliders remain local-player-only.
- **SINGLE SOURCE OF TRUTH.** The offset value lives only in
  `_weapon_grip_offsets`. `_DURABLE_GRIP_OFFSETS` carries no values, just keys.

---

## How to add / change an offset

1. Set the value in `_weapon_grip_offsets[weapon_key] = { <career_prefix>_ = {x, y, z[, hand="right"|"left"]} }`.
   `hand="left"` entries DO reach the inventory preview: since v0.12.275-beta the
   `MenuWorldPreviewer._spawn_item_unit` fake slot is keyed `left_unit_3p` when the
   weapon template declares ONLY a `left_hand_unit` (crossbow class). Paired
   weapons (both hands declared) still present as `right_unit_3p` per unit - the
   previewer has no hand indicator, so a hand-scoped entry on a PAIRED weapon
   will not preview-match; verify those in-game.
2. If the offset is large enough that it doesn't visually hold in-game (anything
   that gets stomped — generally anything beyond a tiny nudge), ALSO add
   `<weapon_key> = true` to `_DURABLE_GRIP_OFFSETS`.
3. Tune live with the dev hold-pose tuner (`/wt_dump_hold_pose` →
   `wt_dev_hold_pose.lua`), which does the same per-frame re-apply, so the number
   you see while tuning is the number that will hold in-game on the durable path.
4. Verify in BOTH the inventory model preview AND in actual gameplay — they
   should match. If they don't, the value is being read from two places (bug) or
   one path is missing.
