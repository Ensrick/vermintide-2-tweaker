# Weapon Appearance Standard

**Status:** normative. This is the contract every weapon-appearance override in the
monorepo must satisfy. It exists to kill one recurring bug class: *an attribute
(mesh / transform / texture / ammo) is correct in ONE render path or for ONE
observer and wrong in another.* Issues #237, #392, #394, #396, #397, #399, #401,
#409, #415, #416, #204, #227 are all instances of it.

The rule the whole document enforces:

> **A weapon's appearance is a function of its variant definition, NOT of which
> code path happens to be spawning it or who is looking at it.** Every render
> path resolves the SAME six appearance concerns from the SAME source of truth,
> through the SAME interface. No path may re-implement a concern inline.

Applies to `character_weapon_variants` (CWV), `cosmetics_tweaker`, and
`weapon_tweaker` — any mod that overrides how a weapon looks.

The shared primitive and incremental consumer cutover boundary are tracked in
`WEAPON_APPEARANCE_EXTRACTION_420.md`. The copied library landing alone does not
mean a consumer has retired its legacy apply path.

For imported FBX/GLB/OBJ/DAE geometry, package residency, preview package
translation, and multiplayer serialization are governed by the canonical
[Custom Weapon Model Import Pipeline](CUSTOM_WEAPON_MODEL_PIPELINE.md). A
correct appearance recipe cannot compensate for an unreachable or wire-unsafe
resource.

---

## §1 The four spawn paths and every presentation surface

A weapon unit is spawned by exactly one of four paths depending on WHO is
looking and WHERE. A fix that only touches one path is by definition incomplete.

| # | Path | Hook target | Who / where | Per-hand handles |
|---|------|-------------|-------------|------------------|
| 1 | **Owner in-world** | `GearUtils.create_equipment` | The wielder's own screen (and bots) in keep + mission | `result.{right,left}_unit_{1p,3p}` |
| 2 | **Husk (remote)** | `GearUtils.spawn_inventory_unit` (discriminator: `owner_unit_1p == nil`) | Every OTHER player's screen — the wielder rendered as a husk | returned 3P weapon units |
| 3 | **Inventory preview** | `MenuWorldPreviewer._spawn_item` → `_cwv_spawn_item_post` | Hero/inventory character-preview mannequin | `self._equipment_units[slot_index].{right,left}` |
| 4 | **Illusion browser** | `LootItemUnitPreviewer.spawn_units` | Cosmetic/illusion picker preview pane | returned `units` array (1=left, 2=right) |

Those four engine spawn paths do not reduce the verification surface to four
screens. Owner local 3P, bots, remote husks, the inventory-screen character
preview, illusion/Athanor previews, lobby presentation, and score/team previews
are separate acceptance cells even when two cells eventually reuse one spawn
primitive. Never infer that an inventory preview works because owner 3P works,
or that a score preview works because the inventory preview works.

**Load-bearing facts (do not relearn the hard way):**

- Paths 1 & 2 are SEPARATE ROOT CLASSES with no inheritance
  (`SimpleInventoryExtension` vs `SimpleHuskInventoryExtension`,
  `create_equipment` vs `spawn_inventory_unit`). A hook on one never fires for
  the other. `[src: scripts/network/unit_extension_templates.lua]`
- Path 3 MUST hook `MenuWorldPreviewer` (the derived class), never
  `HeroPreviewer` (the base) — VT2 copies parent methods into the child at
  class-definition time, so a base-class hook never fires on the runtime
  instance. `[bugclass: CLAUDE.md "HOOK THE DERIVED CLASS"]`
- Path 3's `_item_info_by_slot` is STRING-keyed (`"melee"`/`"ranged"`) but
  `_equipment_units` is NUMERIC-keyed (`slot_index`). Bridge via
  `info.spawn_data[1].slot_index`. `[bugclass: CLAUDE.md]`
- Path 4 MUST use `mod:hook` (full wrapper), never `hook_safe` — vanilla writes
  `self._spawned_units` AFTER `spawn_units` returns. Read the return value.
- Paths 3 & 4 receive `item_name` = the variant's **base weapon key** (a CWV
  clone keeps `entry.name = base_weapon`), so vanilla spawns the BASE mesh.
  Overriding to the variant mesh is the mod's job on these paths (§4.1).
- Path 3's `MenuWorldPreviewer._spawn_item_unit` fires once per unit with NO
  hand indicator - not usable for per-hand targeting. Use `_spawn_item` /
  `equip_item` instead.
- Path 4's spawn order is fixed by `_load_item_units`, which always appends
  left then right - hence `units[1]` = left (shield), `units[2]` = right
  (weapon), identified via the `spawn_data` entries.
- Path 1 career-gated hooks must read career from
  `ScriptUnit.has_extension(unit, "inventory_system")._career_name`, never
  `Managers.player:owner(unit):career_name()` - the unit-to-player reverse
  association is nil at mission-spawn timing, so the hook silently bails.
  `[memory: feedback_vt2_mission_spawn_career_lookup]`

---

## §2 The six appearance concerns (the interface)

Every render path resolves these six concerns. This is the interface; the code
module that owns each is named. New code calls the module — it never re-derives.

| Concern | Owns | Source of truth | Module |
|---------|------|-----------------|--------|
| **Units** | which mesh renders per hand/perspective | `def.right_hand_unit` / `def.left_hand_unit` | `_resolve_variant_units(def)` |
| **Transform** | scale / offset / position / rotation | `_type_transforms` + per-variant `_1p`/`_3p` fields, via `_resolve_field` | `WA` (WeaponAppearance) |
| **Texture** | per-material texture set + per-instance persistence | variant custom texture set; LA `_la_persistence` per `backend_id` | `_resolve_variant_textures` (Phase 2) |
| **Ammo** | attach / strip projectile+ammo units | `def.no_ammo_unit` | husk ammo-strip block |
| **Residency** | force-load override units so the spawn yields a unit | data-driven walk of every def's override units | `_force_load_husk_override_units` |
| **Pose/animation** | wield/idle state and attack playback on each 3P body | native template wield event plus canonical career/template remap data | weapon animation resolver; preview reuses the selected native event |

Plus a cross-cutting concern:

| **Sync** | make the variant identity survive the network so husks resolve it | net-safe marker on the equipment/loadout wire | §5, issue #392 |

---

## §3 Concern × Path matrix — what each path MUST apply

`✓` = path must apply this concern. `data` = resolved at the data level (the
cloned `ItemMasterList` entry or a `get_item_units` hook) so vanilla spawns it
correctly with no per-path apply. `swap` = path spawns the base and must
explicitly swap. `—` = not applicable.

| Concern | 1 Owner | 2 Husk | 3 Preview | 4 Browser |
|---------|:-------:|:------:|:---------:|:---------:|
| Units | data (`_build_entry` + `get_item_units`) | data (entry) | **swap** ✓ | **swap** ✓ |
| Transform (3P) | ✓ | ✓ | ✓ | ✓ |
| Transform (1P) | ✓ | — (husks have no 1P) | — | — |
| Texture | ✓ | ✓ | ✓ | ✓ |
| Ammo | data | ✓ (strip) | — | — |
| Residency | ✓ (owner too — #415) | ✓ | n/a (preview world resident) | n/a |
| Pose/animation (3P) | ✓ | ✓ | ✓ | preview-specific / n/a when no body |
| Sync | source | consumer (§5) | — | — |

**The gaps this standard is closing** (as of 2026-07-07):
- Units, path 3 (inventory preview): fixed v0.1.370-dev — `_cwv_preview_meshswap_apply`
  swaps the previewer spawn_data (#237, pending in-game verify). → §4.1.
- Units, path 4 (illusion browser): resolves upstream via the shared
  `get_item_units` hook (loot_item_unit_previewer.lua:270 calls it; CWV forces the
  override there) — PLUS, as of cwv v0.1.385-dev, a belt-and-suspenders spawn-time
  pre-pass (`_om._cwv_browser_meshswap_apply`) closing the #419 residual edge: the
  browser rebinds item_data to the BASE IML entry (:254-255), killing the #482
  stamp rung inside the get_item_units hook, so a skinless UUID-bid crafted
  instance could fall to the base mesh; the pre-pass resolves the ladder against
  `self._item` (stamp rung alive) and is idempotent vs the data-level swap. → §4.1.
- Units/Transform coupling: mesh-swap resolves via `_find_def` (registration-
  independent) but transform via `_transform_map` (registration-gated), so a
  unit-bearing variant that forgets a transform field swaps its mesh with NO
  transform, silently — this is why the musket needs the `force_register` crutch
  (issue #417). → §4.1 / §4.2.
- Residency ref-string is duplicated producer↔consumer with no shared constant;
  a rename silently degrades every preview swap to base mesh (issue #418). → §4.5.
- Residency, path 1: the boot pass `_force_load_husk_override_units` already runs
  on the host, so owner residency IS covered; #415's residual absent-shield is the
  ranged-slot offhand-attach root, pending the disambiguating in-game test. → §4.5.
- Texture, all paths: bespoke `Material.set_texture` copies (BANNED primitive —
  §4.3 mandates `Unit.set_texture_for_materials`), no per-instance persistence,
  `WA` not shared cross-mod (#227, #416, issue #420). → §4.3.
- Sync: husk resolves BASE `item_data` (#392). Husk display resolution
  (v0.1.377-dev, #474/#475, superseding the Phase C base+career-primary model)
  runs through ONE decision point (`_om._husk_resolve_display_def`) in this
  order:
  1. **Wire skin PRIMARY**: a skin in either cwv namespace (base
     `<item_key>_skin` or pairing `<item_key>_<tail>`, lazy longest-prefix)
     positively identifies the variant → re-key mesh + transform REGARDLESS of
     `can_wield` (#474: wieldability-exclusion had suppressed the re-key of a
     positively-skinned variant). The skin template's own per-hand units win
     over def defaults (pairing skins keep their exact combination).
  2. **Non-cwv skin present → NEVER re-key** (#475 Invariant 1: never
     mis-apply a variant to a native weapon; a variant degrading to base
     display is the accepted lesser harm).
  3. **Skinless echo only**: base+career positive signal, `can_wield`
     evaluated LAZILY at wield time (respects weapon_tweaker's runtime
     expansion whatever the boot order; #475's snapshot hole). A
     currently-wieldable pair declines — ambiguous shows base; the following
     skinned wield still re-keys via arm 1.
  Residency: vanilla overrides via the shared resident-3p guard (#403/#418);
  mod-bundled custom meshes (Old Musket) via `_om._husk_custom_bundle_unit`.
  Closes #394/#396/#397/#401 for skin-carrying wields; skinless parity under
  wt-expanded `can_wield` still needs the per-wearer marker. → §5.

---

## §4 Per-concern contract

### §4.1 Units — `_resolve_variant_units(def)`

Returns the per-hand mesh paths the variant should render:
`{ right = def.right_hand_unit, left = def.left_hand_unit }` (either may be nil =
keep base). Paths 1 & 2 apply this at the data level (`_build_entry` writes the
paths onto the cloned entry; the `BackendUtils.get_item_units` hook forces them
when no skin is applied). Paths 3 & 4 receive the base `item_name`, so they MUST
explicitly swap:

Both previewers spawn from a mutable, precomputed recipe (`spawn_data` /
`units_to_spawn`), so the swap is **data mutation, not despawn/respawn**
(weapon_tweaker's proven preview-swap pattern):

1. Resolve the variant `def` by `backend_id` (`^(cwv_.-)_%d%d%d$`) via
   `_find_def` — a direct walk of `_variant_definitions`, so it resolves EVERY
   variant including those with no transform (registration-independent; see
   below). Bail if a user-selected illusion is active (non-empty `skin` arg —
   the illusion's mesh wins).
2. In the `equip_item` hook (fires BEFORE vanilla's `World.spawn_unit`), rewrite
   each matching `spawn_data` entry's `unit_name` to `def.<hand>_hand_unit ..
   "_3p"` (entries already carry the `_3p` suffix). **unit_name only** — cwv
   variants reuse the base template's node vocabulary, so the entry's
   `unit_attachment_node_linking` is already correct; rewriting the node table
   risks an engine-fatal `Unit.node` on a mesh missing the source's nodes.
3. Guard, so worst case = today's base mesh, never a crash: swap only vanilla
   `units/weapons/player/` meshes (a mod-bundled custom mesh has no `_3p`
   package and `World.spawn_unit` engine-fatals — #403 class), only when the
   target `_3p` unit is already force-loaded resident (§4.5), never the
   invisible-weapon sentinel, never ammo-unit entries. Idempotent by keyed
   assignment (`equip_item` fires twice per equip).

**Registration vs resolution.** Two different lookups, do not conflate:
- **Unit-swap** (this section) resolves via `_find_def` — registration-INDEPENDENT,
  so a transform-less cross-character melee variant still previews its own mesh.
- **Transform apply** (§4.2) on paths 3 & 4 resolves via `_transform_map`
  (`_resolve_preview_def`), which is gated: a def registers when it contributes
  ANY transform field or `force_register = true`. A native-scale variant needs
  no transform, so not being registered is correct — its mesh still swaps.

### §4.2 Transform — `WA` (WeaponAppearance)

The single module that owns scale/offset/position/rotation math. Already unified
across all four paths (v0.1.369-dev). Conventions:

- **scale** — ABSOLUTE set. Idempotent.
- **offset** — ADDITIVE from native local position. Guarded-idempotent (weak
  table) because `MenuWorldPreviewer._spawn_item`'s super-call fires the hook
  twice per spawn.
- **position** — ABSOLUTE set (custom-mesh full pose reset; e.g. Old Musket).
  Mutually exclusive with offset; position wins.
- **rotation** — ABSOLUTE set. Accepts `{x,y,z}` euler DEGREES
  (`Quaternion.from_euler_angles_xyz` takes degrees `[memory: reference_vt2_euler_angles_degrees]`)
  OR a QuaternionBox / raw Quaternion.
- **1P and 3P are applied to SEPARATE units BY THE CALLER.** `WA` never infers
  perspective; the caller resolves `<field>_1p` / `<field>_3p` / unified via
  `_resolve_field` and hands `WA` the resolved value. A 3P change can never
  touch the 1P grip. Husks and both previewers apply 3P only.

Call `WA.apply(unit, { scale=, offset=, position=, rotation= })`. Never
re-implement `Unit.set_local_scale/position/rotation` at a call site.

### §4.3 Texture — `_resolve_variant_textures` (Phase 2)

- **Primitive:** `Unit.set_texture_for_materials` (per-UNIT, auto-cleaned on
  despawn). NEVER `Material.set_texture` — that mutates the SHARED material
  asset, leaking onto every weapon using it and risking the #199 missing-fallback
  crash class.
- **Per-instance persistence:** custom textures (LA armoury paints, variant
  skins) persist per `backend_id`, exactly like vanilla illusions, via the
  `cosmetics_tweaker/_la_persistence.lua` store (`illusions[backend_id] =
  skin_name`, `save_illusion`/`get_saved_illusion`). Re-equip / unequip must
  restore the same texture on the same instance.
- Applied on every path that spawns a unit (1–4). On husks the source is the
  networked cosmetic state (§5), not local selection.

### §4.4 Ammo

Variants with `def.no_ammo_unit` must attach NO projectile/ammo unit. Path 1
resolves this at the data level; path 2 (husk) must actively STRIP the returned
3P ammo unit (hide + `mark_for_deletion`, return nil so equipment never tracks
it). Husk signal must be cwv-POSITIVE (base_weapon + career membership), never a
bare base-key match that would touch a real vanilla weapon (#399).

### §4.5 Residency

A husk 3P unit must be force-loaded resident on EVERY peer before
`_wield_slot` can spawn it, else the husk renders absent/base (#396, #401). The
residency pass is DATA-DRIVEN: walk every def, force-load any per-hand override
unit (and `_3p`) that differs from the base weapon's. This boot pass runs
UNCONDITIONALLY (host included), so it already covers the owner path — #415's
absent Bretonnian shield on non-GK Empire careers is therefore NOT a residency
gap but a ranged-slot offhand-attach issue (verify in-game before treating it as
residency). The producer ref string and the `_3p`+`has_loaded` guard must live
in a SINGLE shared constant + predicate, not re-inlined per site (issue #418):
`_force_load_axe_shield_husk_units` currently omits the safety predicates that
the data-driven pass and the preview swap both carry.

### §4.6 Pose/animation

Model correctness does not prove pose correctness. Every 3P-capable surface
must resolve the weapon's wield/idle event and combat events from the canonical
template plus career-remap data. Do not create a second independent table for
the inventory character preview or score/team preview.

The inventory-screen character is a `MenuWorldPreviewer` body, not the owner's
in-world 3P unit. Vanilla selects
`wield_anim_career_3p[career]`, then `wield_anim_career[career]`, then
`wield_anim`. A preview correction must preserve that precedence, target the
derived preview class, and fire only on `self.character_unit`. A body reporting
`Unit.has_animation_event == true` proves capability, not that an earlier event
survived later spawn/link transitions; when evidence proves a timing loss,
reassert the same canonically selected event after spawn rather than changing
mission routing.

For every pose change, explicitly cover owner local 3P, bots, remote husks,
inventory-screen character preview, score/team preview, and any other body
preview. First-person behavior is a separate control and must remain unchanged
unless the issue explicitly targets it.

---

## §5 Sync contract

Owner paths (self + bots) have the full variant `item_data` and resolve every
concern correctly. **Husks do not.** The equipment RPC encodes
`NetworkLookup.item_names[item_data.name]`, and a CWV clone keeps
`entry.name = base_weapon` — so the husk receives the BASE key plus (maybe) a
synced skin, never the cwv instance identity. Any husk-side concern resolution
that keys on the cwv identity silently no-ops for a skinless / cim-crafted
variant. This is issue #392, the true umbrella under #394/#396/#397/#399/#416.

**Contract:**
- The loadout-panel RPC deliberately substitutes the vanilla base key to avoid a
  cross-peer `item_names` divergence CTD (#278) — keep that.
- To make husks RESOLVE the variant, a **net-safe cwv marker** must ride an
  independent channel (a small per-wearer cosmetic-state broadcast keyed by
  `backend_id → { right_hand, left_hand, variant_key }`), consumed on the husk
  spawn path to drive units + transform + texture + ammo. Hot-join must resync
  (`AttachmentUtils.hot_join_sync`). This is the generic replacement for the
  per-item LA-only husk paint bridge (#416, #204).
- Until the marker ships, husk correctness is limited to variants whose skin
  survives the vanilla weapon_skin sync. Document that limit; don't claim husk
  parity without a 2-player mission test.

---

## §6 Verification matrix

No appearance change is "done" until confirmed in EVERY applicable cell (user
in-game; compile is not verification `[bugclass: CLAUDE.md #10]`).

| Observer / surface | Units/model | Transform | Texture | Pose/animation | Ammo |
|--------------------|:-----------:|:---------:|:-------:|:--------------:|:----:|
| Owner, keep local 3P | ☐ | ☐ | ☐ | ☐ | ☐ |
| Owner, mission local 3P | ☐ | ☐ | ☐ | ☐ | ☐ |
| Owner, 1P view | — | ☐ (1P sep.) | ☐ | control | — |
| Bot, keep + mission | ☐ | ☐ | ☐ | ☐ | ☐ |
| Client/remote husk, keep + mission | ☐ | ☐ | ☐ | ☐ | ☐ |
| **Inventory-screen character preview (path 3)** | ☐ | ☐ | ☐ | ☐ | — |
| Illusion/Athanor or other item preview (path 4) | ☐ | ☐ | ☐/n/a | n/a | — |
| Lobby character presentation | ☐ | ☐ | ☐ | ☐ | — |
| End-of-mission score/team preview | ☐ | ☐ | ☐ | ☐ | — |
| Re-equip / unequip (persistence) | ☐ | — | ☐ | ☐ | — |
| Hot-join (husk resync) | ☐ | ☐ | ☐ | ☐ | ☐ |

A row that passes for the owner but fails for the husk is the #392 class. A cell
that passes in-world but fails in preview is the #237 class.

---

## §7 Open-issue map (each cell → the pipeline gap it is)

| Issue | Concern | Path(s) | Note |
|-------|---------|---------|------|
| #237 | Units | 3 | elf sword+shield previews as Kruber base — no mesh-swap |
| #409 | Units/Texture | 3 | Old Musket preview — resolver bailed (fixed v0.1.369 force_register) |
| #396 | Residency | 2 | Imperial Longsword invisible on husk |
| #401 | Residency/Units | 2 | Axe+Shield reverts to dwarf base — wrong units force-loaded |
| #415 | Units/attach | 1 | Shield offhand absent for HOST — offhand-attach, NOT residency (verify) |
| #394 | Transform | 2 | Poleaxe grip offset not on husk |
| #397 | Transform | 2 | umbrella: all transforms on husk |
| #399 | Ammo | 2 | Trollhammer torpedo on husk |
| #227 | Texture | 4 | Old Musket illusion entry red/transparent in browser |
| #416 | Texture/Sync | 2 | per-hand illusion picks don't replicate to peers |
| #204 | Texture/Sync | 2 | LA shield texture warps onto wrong mesh on husk |
| #392 | Sync | 2 | umbrella: husk resolves base item_data |
| #417 | Units/Transform | 1,3 | mesh swaps but transform silently skips (reg-gate fork) |
| #418 | Residency | 2,3 | ref-string / guard duplicated — rename → silent base mesh |
| #419 | Units | 4 | illusion browser previews base mesh (path-3 swap not mirrored) |
| #420 | Texture | all | WA not shared; Material.set_texture banned-primitive copies |
| #617 | Texture | 4 | Old Musket custom unit spawned in Athanor/browser without its texture consumer |

---

## §8 DoD gate — `G-APPEARANCE`

Add to `character_weapon_variants/DEFINITION_OF_DONE.md`. Trigger: the variant
overrides ANY of units / transform / texture / ammo / pose relative to its base weapon
(i.e. essentially every cross-character variant).

Walk:
1. Every overridden concern, including wield/idle pose, resolves through its
   §2 owner — NO inline `Unit.set_local_*` / `Material.set_texture` /
   hand-spawned unit at a call site.
2. The §6 verification matrix is walked for every applicable cell, host AND
   client, with the user confirming in-game.
3. If husk correctness depends on the cwv identity surviving the wire, the §5
   sync marker is in place OR the CHANGELOG explicitly declares the husk limit.
4. Registration: the variant is in `_transform_map` (transform field,
   `force_register`, or override unit) so paths 3 & 4 resolve it.

CHANGELOG footer: `**DoD:** ... Gates: G-APPEARANCE (matrix cells verified: <list>).`
