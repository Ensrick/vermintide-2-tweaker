# Weapon Appearance Standard

**Status:** normative. This is the contract every weapon-appearance override in the
monorepo must satisfy. It exists to kill one recurring bug class: *an attribute
(mesh / transform / texture / ammo) is correct in ONE render path or for ONE
observer and wrong in another.* Issues #149, #203, #204, #227, #233, #237,
#392, #394, #396, #397, #399, #401, #409, #415, #416, #419, #474, #481,
#482, #483, #579, #587, #598, #613, #629, #645, #650, #657, and #660 are
instances of it.

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

The four paths above are **unit-spawn paths**, not a complete list of UI data
consumers. Inventory rows and tooltips, the equipment/customization picker,
Athanor, Hold-Tab/player-list cards, lobby cards, and score/team screens are
**presentation adapters**. An adapter may share a spawn primitive with another
surface while receiving a different item-identity shape. It therefore has its
own acceptance cell and must consume the canonical presentation descriptor in
§2 rather than re-derive an icon, name, rarity, skin, or offhand choice.

### Identity available to presentation adapters

| Identity shape | Where it is available | Binding rule |
|---|---|---|
| **Exact instance** | Backend inventory, crafting, equipment, and customization paths that carry `backend_id` / `ItemInstanceId` | Resolve persisted per-instance choices from that exact ID. Do not silently substitute the currently equipped item. |
| **Network/loadout snapshot** | Hold-Tab and other remote-player surfaces reconstructed from `Managers.player:player_loadouts()` | The snapshot has no backend instance ID. Resolve only from wire evidence plus an explicitly synchronized/cacheable `(wearer peer, slot)` presentation identity. If that evidence is absent or ambiguous, preserve the reconstructed vanilla presentation. |
| **Preview slot** | Inventory hero, lobby, score/team, and other preview worlds | The adapter must declare whether it received an exact instance or only a slot snapshot. A slot name alone is not proof of an exact item instance. |

The Hold-Tab constraint is source-backed: `rpc_sync_loadout_slot` reconstructs
the stored loadout item from RPC data without a backend instance ID, and the
player-list UI then calls `UIUtils.get_ui_information_from_item(item)` on that
reconstructed item. `[src: scripts/managers/player/player_manager.lua:69-78]`
`[src: scripts/ui/views/ingame_player_list_ui_v2.lua:1450,1504-1536]`

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

## §2 The six rendered-unit concerns and UI presentation (the interface)

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

UI consumers add one more cross-cutting concern. It is not a seventh unit-spawn
mutation; it is the identity rendered around the unit:

| Concern | Owns | Source of truth |
|---|---|---|
| **UI presentation** | primary and offhand display-name keys/text, their composition order, icon ownership, rarity/background, renderer-capability proof, and vanilla fallback | the same resolved item/variant/illusion identity used by the six concerns above |

### Presentation descriptor boundary

The concern resolvers above produce one immutable **presentation descriptor**
for the strongest identity the caller actually has: exact instance, synchronized
loadout snapshot, or preview slot. The descriptor carries:

- resolved per-hand units, textures/material overrides, perspective transforms,
  pose, residency proof, and ammo policy;
- primary/offhand display identity and composition order;
- inventory/HUD icon ownership plus rarity/background policy;
- the evidence used to resolve the item (`backend_id`, or wearer/slot snapshot);
- required mod/capability and renderer/resource proofs; and
- a wire-safe, resident vanilla fallback for every optional field.

Inventory, illusion browser, Athanor, Hold-Tab, lobby, score, owner, bot, and
husk code are adapters: they translate the same descriptor into their surface's
spawn or renderer API. They do not independently rediscover item identity,
active illusion, icon ownership, display name, or transform policy.

Descriptor fields have a single-writer rule. A surface adapter consumes the
first authoritative resolved value for a field; a later hook must not replace
it with a separately re-derived primary skin, vanilla display name, or slot
default. Optional providers may fill fields that are still unset, but provider
order and ownership are cross-mod API and must be documented in
`docs/CROSS_MOD_ARCHITECTURE.md`.

Custom presentation is conditional. If the observer lacks the owning mod or
declared capability, the item identity is not present on the wire, or the
specific renderer lacks the required icon/material/resource, the adapter must
leave the resident vanilla presentation intact (or omit an optional overlay).
It must not emit a custom unit, skin, localization key, icon, material, or
package path and hope that the receiving renderer can resolve it.

Renderer material closure is deliberately not a global boolean. A texture can
be resident while absent from the specific `Gui` used by `ui_top_renderer` or a
forge/HDR renderer. An adapter may emit a custom GUI material only after it is
registered in the renderer that will draw the pass; otherwise it must choose a
resident vanilla fallback or omit the optional pass. See bug classes 47 and 48
and issues #420/#481.

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

**Registration vs resolution.** Two different lookups remain in the legacy
runtime; they must agree and are not permission to omit a concern:
- **Unit-swap** (this section) resolves via `_find_def` — registration-INDEPENDENT,
  so a transform-less cross-character melee variant still previews its own mesh.
- **Transform apply** (§4.2) on paths 3 & 4 resolves via `_transform_map`
  (`_resolve_preview_def`), which is gated. Since v0.1.371-dev (#417), every
  unit-bearing definition is registered even when its transform is native. This
  keeps mesh, transform, and future def-keyed concerns on the same identity;
  `cwv_unit_bearing_variants_registered` locks the bridge until the legacy maps
  are replaced by the canonical descriptor.

As the first #660 migration slice, inventory-character preview and the
illusion/Athanor browser call
`_cwv_exact_appearance.resolve_spawn_descriptor` once, then translate that
same immutable-by-convention unit descriptor with either the `hand_flags` or
`base_identity` adapter. The adapter may mutate only engine `spawn_data`; it
cannot resolve skin, backend identity, or variant units again. This removes the
duplicated #237/#419 fallback loops. It does **not** establish owner, husk,
transition, material, pose, icon, or name parity; those remain separate slices.

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
re-implement `Unit.set_local_scale/position/rotation` at a call site. When the
complete matrix API is present, `WA` builds the requested local rotation,
position, and scale into one matrix and writes node 0 through
`Unit.set_local_pose`. This is the same primitive vanilla uses to restore a
linked weapon node (`gear_utils.lua:321-327`). The per-channel setters are a
compatibility fallback only: `WA.apply` succeeds only when every requested
channel succeeds, and its second return is a channel report. An OR of setter
results is forbidden because one retained rotation must not mask rejected
position or scale (BUG_CLASSES 58 / WOC #613).

**Animated retention boundary.** `WA.apply` owns pose math, but a successful
one-shot write is not retained proof for an animated gameplay unit. Source
shows that gear is linked at weapon node 0 before the mod's spawn hook; WT's
captured runtime evidence shows animation can restore that linked node on the
following update (`weapon_tweaker/OFFSETS.md`). For an authored transform large
enough to require durable ownership:

- capture the linked baseline and resolve one absolute target through `WA`;
- weak-track only animated gameplay 1P/3P/bot/husk consumers, compare numeric
  retained state, and reconstruct the target only after measured drift;
- keep static preview surfaces one-shot, prune dead units, and send no
  transform RPC or live-tuner stream; and
- yield to an intentional non-identity development-tuner edit so two owners do
  not fight.

Temporary vectors/quaternions used across updates must be copied into Lua
scalars/tables (or boxed), not retained as engine temporary values. WOC
`_woc_durable_transform.lua` is the bounded reference implementation.

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
in a SINGLE shared constant + predicate, not re-inlined per site (issue #418).
The data-driven override pass and preview adapters share
`_om.HUSK_OVERRIDE_REF` / `_resident_override_3p`.

`_force_load_axe_shield_husk_units` is older and hand-authored, but current
source and issue #280 history show that it serves a different crash floor: it
loads the *vanilla base* Axe+Shield units for the no-skin wire path, while
`_force_load_husk_override_units` deliberately loads only authored units that
differ from the base. Do not delete the older writer merely because it is
weapon-specific. Retire it only after a data-driven residency plan explicitly
loads both required base fallbacks and authored overrides under one symmetric
lifecycle, with a no-skin remote control proving the replacement.

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

This is also a build-integration gate, not a reminder for manual cleanup. Every
new visual feature must add one canonical descriptor, enumerate every applicable
keep/mission/preview/husk consumer below, and register executable offline plus
runtime assertions that reject a missing consumer or transition replay. A
feature that survives its creation hook but has no mission-entry replay is
structurally incomplete. Builds must fail when the descriptor, package coverage,
unit resolver, per-surface adapter, or transition/runtime check is absent; do
not wait for a user to rediscover that omission after each visual addition.

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

UI presentation has a separate matrix because these adapters do not all spawn a
unit and do not all receive an exact backend instance:

| Adapter / surface | Identity evidence | Primary + offhand name | Icon owner | Rarity/background | No-parity/resource fallback |
|---|---|:---:|:---:|:---:|:---:|
| Inventory row + tooltip | exact instance | ☐ | ☐ | ☐ | ☐ |
| Equipment/customization picker | exact instance | ☐ | ☐ | ☐ | ☐ |
| Athanor/crafting browser | exact instance or declared preview identity | ☐ | ☐ | ☐ | ☐ |
| Hold-Tab/player list | wearer + slot snapshot; no backend ID | ☐ | ☐ | ☐ | ☐ |
| Inventory character preview | declared exact instance or preview slot | ☐ | ☐ | ☐ | ☐ |
| Lobby character/card | declared exact instance or snapshot | ☐ | ☐ | ☐ | ☐ |
| Score/team preview | declared exact instance or snapshot | ☐ | ☐ | ☐ | ☐ |

For every row, include one unmodified vanilla control and one observer lacking
the optional provider/resource. A correct fallback leaves vanilla data intact;
an empty, unknown, red-placeholder, or custom-resource error is a failure.

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

## §7a Issue #660 empirical regression-family audit (2026-07-17)

This crosscheck used the current GitHub issue state, issue closure comments,
`git log`/`git blame`, and current source. It does not infer that a closed issue
is broken merely because a later issue has a similar symptom. A closed fix is
classified as **surface-local** only where its own acceptance evidence and diff
name a narrower consumer, concern, provider, or lifecycle edge than the current
open report.

### Crosslinked families

| Family | Closed/verified evidence | Open or residual evidence | Empirical boundary |
|---|---|---|---|
| Preview unit selection | #409, #617 | #148, #150, #227, #237, #419, #474, #481, #598, #613 | #237 added `_cwv_preview_meshswap_apply` in `06e9d50`; #419 later added the near-twin `_cwv_browser_meshswap_apply` in `3360f53`. The same unit concern was reconstructed once per preview engine. |
| Husk model, transform, and residency | #270, #282, #397, #418, #475, #495, #580, #587 | #149, #154, #204, #233, #278, #279, #394-#401, #416, #421, #423, #474, #478, #483, #484, #491, #579, #583, #629, #645, #657 | #397 verified the CWV husk-transform route from `d1817a7`; #587 verified WT's separate baked-transform route. Neither is a provider-neutral descriptor/replay contract, so WOC, LA, paired hands, and Combat Styles still have independent paths. |
| Transition, swap, and hot join | #234, #264, #265, #267, #268, #574 | #105, #149, #203, #233, #353, #354, #376, #395, #416, #474, #482, #483, #518, #579, #583, #629, #645, #657 | The LA fixes separately added post-spawn swap, revert broadcast, wearer-scoped reconciliation, and pull/ack. Glow #574 added its own transaction and state pull. There is no shared generation/fingerprint reconciler across providers. |
| Exact instance and crafted identity | #390, #392, #563, #592, #620 | #226, #227, #237, #246, #278, #279, #353, #354, #376, #391, #417, #419, #474, #481, #482, #483, #491, #524, #579, #583, #598, #628, #637, #641, #645, #650, #657 | Backend UUID, stamped `cwv_key`, base `item_data.name`, selected skin, wearer/slot snapshot, and style state still enter different resolvers. #392 correctly closed blacksmith/base identity without claiming every presentation adapter. |
| Transform/pose retention | #397, #409, #569, #587, #603, #606 | #109-#113, #168, #237, #269, #394, #400, #417, #420, #441, #474, #482, #604, #613, #645, #657 | Shared `WeaponAppearance` geometry landed in `3c82f93`, but per-provider ownership and lifecycle remained. WOC #613 proved successful per-channel writes could retain rotation while rejecting position/scale; `5bbb181` repaired the atomic primitive, not every consumer. |
| Texture, glow, and per-hand composition | #234, #265, #514, #563, #574, #612, #617 | #48, #149, #150, #154, #203, #204, #227, #228, #233, #266, #373, #376, #377, #416, #419, #420, #421, #474, #481, #518, #565, #566, #579, #583, #610, #613, #629, #650 | #574 owns exact-item glow transactions; #612 owns donor-preserving hat materials; #617 owns one Athanor resource closure. Those verified fixes do not cover LA mesh/material pairing, composite shield glow, or every renderer. |
| UI identity, icon, name, and score/lobby | #513, #514, #617, #639 | #227, #237, #246, #376, #419, #481, #598, #629, #638, #641, #650 | #513 isolated score-lineup wearer identity, while weapon appearance and offhand text stayed separate. Hold-Tab lacks backend IDs by source contract, so exact-instance UI logic cannot simply be reused there. |
| Imported/custom-unit behavior and fallback | #270, #403, #418, #422, #612, #617, #654 | #227, #278, #279, #396, #421, #474, #478, #491, #604, #613, #627, #629, #633 | Residency, wire substitution, renderer material closure, donor physics/fade, and transform retention are separate contracts. A resident mesh does not prove a safe wire identity, valid material, retained pose, or donor behavior. |
| Combat Style appearance | #620, #644, #648 | #645, #657 | Core selection/cycling and donor cloning were verified, but remote re-wield, model visibility, animation refresh, and mission replay are later lifecycle/adapter evidence. Closing the control feature did not verify this full matrix. |

### Why the regressions recur

1. **Identity is re-derived.** Current code still resolves through `_find_def`,
   `_transform_map`, backend skin lookup, base+career husk heuristics, and
   feature-specific peer stores. These are useful compatibility bridges, not a
   single canonical instance descriptor.
2. **Engine surfaces are genuinely separate.** Owner and husk inventory
   extensions are different root classes; the two preview engines expose
   different recipe shapes; Hold-Tab has no backend ID. Reusing a setter does
   not automatically reuse identity or lifecycle.
3. **Lifecycle replay is feature-owned.** LA, glow, Combat Styles, WOC, and CWV
   each react to different subsets of equip, spawn, transition, preview-open,
   peer-ready, and hot-join edges. No bounded reconciler currently proves that
   one descriptor generation reached every applicable consumer.
4. **Earlier tests often proved registration or call success.** #613 supplied
   the concrete counterexample: target Z/scale were logged, one channel applied,
   and immediate retained Z/scale remained native. Postconditions must compare
   unit identity and full retained pose/material/template state.
5. **Verified closure was usually correct but narrow.** The user verified the
   reported reproduction for #397, #513, #574, #587, #603, #606, #612, #617,
   #620, #639, #644, and #648. Those closures must remain recorded; they are not
   evidence that another mod/provider/surface inherited the fix.

### Current migration and three fallback paths

The first code slice removes the #237/#419 duplicate unit resolvers. Both now
consume one descriptor from `_cwv_exact_appearance` and differ only by their
engine adapter. Offline coverage proves both adapters produce the same per-hand
unit result, preserve an unrelated independently customized offhand, reject an
unresolved explicit skin, leave ammo/unrelated rows unchanged, and do not mutate
the descriptor. Runtime/in-game proof is still required.

If this slice fails, use these evidence-driven fallbacks in order:

1. Capture bounded pre/post recipes plus descriptor fingerprint on both preview
   hooks and correct the pure adapter while retaining the single resolver.
2. If one engine recipe carries an undocumented identity shape, add that shape
   as a named adapter with a vanilla-source citation and a failing fixture; do
   not restore a second identity resolver.
3. If provider composition cannot be represented by the descriptor, split
   provider-owned **resolution** from engine-owned **application** with an
   explicit field-ownership merge contract, then keep one final descriptor and
   one adapter per engine surface. Preserve vanilla presentation on ambiguity.

Residual critical work remains: provider-neutral exact identity, owner/husk
adapters, peer-ready and mission-transition replay, retained postconditions,
UI adapters, and deletion of superseded writers after each migrated family.
Until those land and the applicable co-op matrix passes, #660 remains
`diagnostics-armed` with `coop-required`.

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
