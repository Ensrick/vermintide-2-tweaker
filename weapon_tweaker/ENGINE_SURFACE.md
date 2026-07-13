# weapon_tweaker - engine contact surface

What vanilla VT2/Stingray does at every seam `wt` touches, and why the mod is
there. This is the per-mod companion to the subsystem set in `docs/engine/`
(read `docs/engine/README.md` for house style). It does **not** re-explain a
subsystem the engine docs own - it names the seam, cites the vanilla behavior,
and links out. Where a seam is byte-shared with `cwv` / `cosmetics_tweaker`
(gear spawn, previewers, husk inventory, wire ids), this doc reuses
`character_weapon_variants/ENGINE_SURFACE.md`'s vanilla citations and keeps the
"why" column wt-specific. Decompile paths are relative to
`C:\Users\danjo\source\repos\Vermintide-2-Source-Code`; `wt` line numbers are
`weapon_tweaker.lua` unless a `_*.lua` / `weapon_tweaker_*.lua` module is named.
`§N` = a `docs/BUG_CLASSES.md` class; `#N` / "issue N" = a GitHub issue.
Grep-verified 2026-07-12 against the decompile and the mod source.

`wt` is the **availability control surface** for cross-character weapon access
(any character wields any weapon) plus the **cross-character 3P-animation remap
machinery**. 1P is universal (the `first_person_base` unit is shared, so any
weapon's 1P state machine plays on any character) - wt never touches it. Only
the **3P body** is character-specific, so the entire mod exists to make a
foreign weapon's 3P events resolve to clips the receiver's skeleton actually
authors. That is the surface this doc centers on: how vanilla fires 3P anim
events, where the `wield_anim_career_3p` / `anim_event_3p` fields are read, and
how wt's three redirect layers intercept the firing point.

## Hook table

30 engine registration sites (25 live + 5 dormant Big Rebalance), grouped below
into rows-of-concern. `[hook]` = full wrapper (`mod:hook`, can rewrite
args/returns); `[safe]` = `mod:hook_safe` (post-callback, no override); `[tbl]`
= table-form hook (plain-table target, nil-guarded). wt also owns two hook
wrappers of its own over VMF's: `mod:safe_hook` (pcall-isolated `mod:hook`,
chain-safe) and `mod:traced_hook` (safe_hook + `[wt:trace]` entry/exit lines) -
both resolve to a single VMF `mod:hook`, so they appear as `[hook]` here with
the wrapper named in the trap column (`_safe_hook.lua`, issue 26).

### Cross-character 3P animation firing layer (the surface this doc exists for)

| Class.method (kind) | Vanilla behavior at the seam | Why wt hooks it | Trap / invariant |
|---|---|---|---|
| `Unit.animation_event` [hook] `_wt_anim_remap.lua` | Engine C-API: fires a state-machine event on a unit's anim graph. Per-action 3P resolution reads `anim_event_3p` (falling back to the 1P `event` when absent) and fires it on the OWNER (3P body) with no career branch [src: `scripts/unit_extensions/weapons/weapon_unit_extension.lua:512`, fired at `:652`] | THE remap funnel: for a cross-access career on a foreign weapon, rewrite the 3P event to one the receiver skeleton authors, via the three redirect layers + per-weapon remap tables (`_wt_anim_remap.lua`; moved from the entry in v0.12.210-dev Phase 2) | Hottest hook in wt - five early-exits before work (nil event, feature-off, 1P unit by captured ref, then per-unit state); 1P `first_person_unit` gets an unconditional early return so 1P is never remapped (memory `feedback_1p_animations_universal`); no `pcall` (engine C, so downstream `func` calls are `pcall`-wrapped); the module keeps its hot tables as file-local upvalues so the per-event path never indirects through `mod._wt` |
| `AnimationSystem.anim_event_with_variable_float` [hook] `:4585` | Fires a 3P anim event AND sets an anim variable (e.g. attack-speed scale) in one call [src: `scripts/entity_system/systems/animation/animation_system.lua:139`] | Guard: bail cleanly when the cross-character 3P body lacks the named anim variable, so a foreign weapon's speed-scaled event does not fault on a receiver whose SM never declared the variable (`:4585`) | Must validate `Unit.animation_find_variable` returns a number BEFORE delegating; the variable set is what differs from the plain `Unit.animation_event` path |

### Wield + per-unit remap state (owner + husk; owner doc: `docs/engine/02`)

| Class.method (kind) | Vanilla behavior | Why wt hooks it | Trap / invariant |
|---|---|---|---|
| `SimpleInventoryExtension.wield` [hook via `traced_hook`] `_wt_anim_remap.lua` | Sets the wielded slot; the wield event ultimately fires the 3P body's wield stance [src: `scripts/unit_extensions/default_player_unit/inventory/simple_inventory_extension.lua:627`] | Populate this unit's `state.template`/`state.key` (drives the remap resolution in the `animation_event` hook) AND capture the local 1P hands unit ref for the funnel's 1P early-return (`_wt_anim_remap.lua`; moved v0.12.210-dev Phase 2 with the funnel it feeds) | `traced_hook` (safe_hook + trace) - wield is event-rate, not per-frame, so trace is flood-safe (`_safe_hook.lua` RATE-LIMIT CAVEAT); a raise here would otherwise kill later cosmetics/LA/cwv wield hooks silently (issue 26) |
| `SimpleHuskInventoryExtension.wield` [hook via `safe_hook`] `_wt_anim_remap.lua` | Husk-side wield: attaches units for a REMOTE player's view [src: `simple_husk_inventory_extension.lua:314`] | Populate the husk unit's remap state so a remote player's cross-character weapon renders its remapped 3P anims on the local viewer's screen (`_wt_anim_remap.lua`, v0.12.35 per-unit career) | Husk is a separate root class from the owner - hooking one never covers the other (CLAUDE.md "Self-owned vs husk"); husk resolves the BASE `item_data` (memory `reference_vt2_husk_resolves_base_item_data`) |
| `SimpleInventoryExtension._wield_slot` [safe] `_wt_diagnostics.lua` | Shows/hides 1p/3p units for the wielded slot; `slot_data.id` carries the item key [src: `simple_inventory_extension.lua:1926`] | Diagnostic only: dump everything wt knows about the wielded weapon (`anim_event`/`wield_anim`/`anim_event_3p`/`wield_anim_career_3p`/units) for `/wt_dump_wielded` (`_wt_diagnostics.lua`, v0.12.209-dev OOP split) | Husk deliberately NOT hooked here - we want our own equips, not teammates'; `hook_safe` so it never perturbs wield |
| `SimpleInventoryExtension.show_third_person_inventory` [safe] `:5919` / `SimpleHuskInventoryExtension.` `:5920` | Toggles visibility of the equipped 3P units on show/hide [src: `simple_inventory_extension.lua:1014`; `simple_husk_inventory_extension.lua:471`] | Re-hide the 3P units wt intentionally suppresses for a mesh swap (e.g. brace's left pistol that would clip the repeater body) whenever vanilla re-shows them (`_rehide_hidden_3p_units`) | Both owner + husk hooked (separate roots); shared handler function |

### Gear spawn + link - in-world render path (owner doc: `docs/engine/06`)

| Class.method (kind) | Vanilla behavior | Why wt hooks it | Trap / invariant |
|---|---|---|---|
| `GearUtils.create_equipment` [hook via `traced_hook`] `:3712` | Builds the in-world equipment record and spawns 1p/3p units for a slot; passes `career_name` down to `spawn_inventory_unit` [src: `gear_utils.lua:7`] | Recover a dropped `career_name` from the unit's inventory extension (the hook chain loses it on CW bot spawns) and pre-resolve per-career `*_hand_unit_override` meshes via `override_item_units` so a non-native receiver spawns the right (resident) 3P unit (`:3712`) | Read career from `inventory_system._career_name`, NOT `Managers.player:owner`, at mission-spawn timing (CLAUDE.md in-mission caveat; memory `feedback_vt2_mission_spawn_career_lookup`); multi-return collapse (`docs/VMF_RECIPES.md` §2) |
| `GearUtils.spawn_inventory_unit` [hook via `traced_hook`] `:5315` | Spawns one hand's inventory unit from `item_template`+`item_units`; returns `(weapon_3p, ammo_3p, weapon_1p, ammo_1p)` with the two `ammo_*` nil for melee [src: `gear_utils.lua:155`, returns at `:273`] | Cross-character 3P MESH swap dispatch: after vanilla spawns, swap the 3P unit to the receiver-native model (brace->repeating handgun, longbow->crossbow, Skullsplitter+tome->1H Skullsplitter) inside a pcall so equip never fails (`:5315`) | The canonical 4-return / 2-nil-hole tuple that broke `safe_hook` v0.12.78 - `select("#", ...)` + explicit-`j` `unpack` is load-bearing (`_safe_hook.lua`, `docs/VMF_RECIPES.md` §2a); swapped 3P unit must be force-loaded first (see residency row) |
| `GearUtils.link_units` [hook,tbl] `:4698` | Attaches source->target units by `attachment_node_linking` via `Unit.node` per link; called from `GearUtils.link` [src: `gear_utils.lua:293`, dispatched at `:290`] | UNIVERSAL choke point: drop only the links whose source/target node is genuinely absent on the non-native receiver body, which `Unit.node` would otherwise engine-fatal (`mod._wt_link_filter`, `:4698`) | `Unit.node` on a missing node bypasses `pcall` (engine fatal, not a Lua error - CLAUDE.md Lua quirks); purely subtractive so it can NOT regress visibility (unlike the reverted v0.12.112/.113 global template mutation that made elf bows invisible); table-form (`GearUtils` is a plain table) |

### Previewers + end-of-mission UI (owner docs: `docs/engine/09`, `/06`, `/01`)

| Class.method (kind) | Vanilla behavior | Why wt hooks it | Trap / invariant |
|---|---|---|---|
| `MenuWorldPreviewer.equip_item` [safe] `:5964` | Keep-inventory previewer equips an item into a preview slot (body copied from `HeroPreviewer.equip_item`) [src: `scripts/ui/views/world_hero_previewer.lua:649`] | Capture the preview item key for `_spawn_item_unit`, then run the preview-side mesh swaps (brace->repeater, longbow->crossbow, repeating-pistol->handgun, Skullsplitter+tome) by mutating `_item_info_by_slot[...].spawn_data.unit_name` (`:5964`) | Hook the DERIVED class, never the base - `class()` copies methods at load time (memory-class; [src: `foundation/scripts/util/class.lua:51-57`], `docs/engine/01`); consolidated - `hook_safe` does not chain, so all preview-swap helpers live in this ONE registration (memory `feedback_vmf_no_duplicate_hooks_burned_again`) |
| `MenuWorldPreviewer._spawn_item_unit` [hook] `:6184` | Spawns a single preview unit for an item; fires the wield anim at spawn reading `wield_anim_career_3p` [src: `world_hero_previewer.lua:1050`, wield read at `:1059-1065`] | (a) pre-validate attachment source nodes vs the actual preview body (avoid the `Unit.node` fatal), (b) scale/offset the swapped mesh, (c) correct the preview 3P WIELD POSE for cross-character ports whose `wield_anim_career_3p` omits the previewed career (`_resolve_preview_wield_event`, `:6184`) | `[hook]` not `[safe]` - needs the pre-spawn node validation AND the return; preview `character_unit` has no `career_system`, so the `animation_event` funnel's career-gated redirect is a no-op there - the pose fix re-uses `_career_anim_redirect` data to fire the receiver-native wield event directly (`:640` resolver, `:6209`) |
| `LevelEndView._verify_weapon_data` [hook via `safe_hook`] `:6850` | Victory-screen weapon-pose validation; on a non-wieldable weapon it bails and can leave `verified_weapon.item_name` as a `{ item_name = "..." }` table [src: `scripts/ui/views/level_end/level_end_view_v2.lua:303`] | Unwrap that nested-table `item_name` shape so the downstream `TeamPreviewer` `ItemMasterList[item_name]` index does not crash on a cross-character weapon that failed the wieldable check (`:6850`) | Class is `LevelEndView` even though the file is `level_end_view_v2.lua`; belt-and-suspenders with the `TeamPreviewer` row below (same broken shape, defended at both the producer and the consumer) |
| `TeamPreviewer.cb_hero_unit_spawned_skin_preview` [hook] `:6892` | Spawns hero preview units for the end-screen / character sheet; indexes `ItemMasterList[item.item_name]` per `hero_data.preview_items` [src: `scripts/ui/views/team_previewer.lua:109`, index at `:119-120`] | Sanitize `preview_items[i].item_name`: unwrap the `{ item_name=... }` table shape (A) and null a string that is not a valid `ItemMasterList` key (B - career-name leak, deleted variant, stale skin) before the crash-site index (`:6892`) | String-form hook defers binding until `TeamPreviewer` loads (race-safe); this is the frame just above the `ItemMasterList` index - catches the broken shape regardless of which upstream path produced it |

### Backend - the availability control surface (owner doc: `docs/engine/11`; `weapon_tweaker_backend.lua`)

| Class.method (kind) | Vanilla behavior | Why wt hooks it | Trap / invariant |
|---|---|---|---|
| `items_interface.set_loadout_item` [hook,tbl] `:148` | Persists an equipped item to a career loadout (would reject / revert a cross-career equip, or write it to PlayFab) [src: `scripts/managers/backend_playfab/backend_interface_item_playfab.lua:635`] | Intercept a mod-unlocked cross-career equip: cache the `backend_id` in wt's per-career `loadout_cache` and short-circuit `return true` instead of letting vanilla write PlayFab (`:148`) | Pass through `...` for vanilla's `optional_loadout_index` (versus mode) and return `true` so success/fail callers do not see nil (v0.12.65); hook the RESOLVED interface instance (`Managers.backend:get_interface("items")`), not cold `_G`, for the LA dispatch path (memory `reference_cim_equip_capture_la_dispatch`) |
| `items_interface.get_loadout` [hook,tbl] `:171` / `get_loadout_item_id` [hook,tbl] `:198` | Read-side loadout resolution the menus/gameplay use [src: `backend_interface_item_playfab.lua:512` for `get_loadout_item_id`] | Return wt's cached cross-career `backend_id` so the mod-unlocked weapon appears equipped in UI + gameplay; re-validate `is_mod_unlocked_weapon` each read so disabling a toggle reverts cleanly (`:171`,`:198`) | `get_loadout_item_id` must preserve the 4th `is_bot` arg on fall-through - dropping it mis-routed bot loadouts to the player-default path (audit 2026-06-07); only answer the LOCAL player from cache, bots fall through |
| `ItemGridUI._on_category_index_change` [hook,tbl] `:230` | Rebuilds the inventory grid's item filter when the category tab changes [src: `scripts/ui/views/hero_view/item_grid_ui.lua:723`] | Restore each category's base `item_filter` so wt's cross-character additions surface in the correct weapon-category tab (`:230`) | Table-form on the resolved `ItemGridUI` (loads early via inventory UI deps; string-form is the safer pattern per CLAUDE.md, noted as a low-risk exception) |

### Cosmetic projectile FX + custom damage-profile registration

| Class.method (kind) | Vanilla behavior | Why wt hooks it | Trap / invariant |
|---|---|---|---|
| `PlayerProjectileUnitExtension` / `PlayerProjectileHuskExtension` `.hit_enemy` / `.hit_level_unit` / `.hit_non_level_unit` [safe] `:5284` (2 classes x 3 methods) | Resolves a fired projectile's impact on the shooter's machine and on every peer's husk view [src: `scripts/unit_extensions/weapons/projectiles/player_projectile_unit_extension.lua`] | Spawn the Moonfire-arrow impact puff FX on both the shooter's and every observer's screen; hooking both roots is why the puff is visible to all peers (`_wt_moonfire_on_hit`, `:5284`) | Both roots carry the same fields the handler reads; the FX package rides the equipped Moonbow, so `World.create_particles` on hit is safe; cosmetics_tweaker's identical puff defers to this one (no double-up) |
| `rawset(NetworkLookup.damage_profiles, ...)` [tbl] `:4832`, `:5146`, `_wt_brett_sword_shield_buff.lua:128` | The lookup is built once at game load and frozen with a strict `__index` that errors on a missing key [src: `scripts/network_lookup/network_lookup.lua` build `:2209` (`create_lookup({}, DamageProfileTemplates)`), strict `__index` `:2360-2367`] | Register wt's cloned damage profiles (authentic brace no-dropoff, priest-punch scaled, brett buff) as index-appends so `PlayerProjectileUnitExtension`'s `NetworkLookup.damage_profiles[...]` lookup at projectile spawn does not fatal (`:4829`) | Forward + reverse append (`idx->key` and `key->idx`), guarded by `rawget` so it registers once; same pattern cwv uses for its custom profiles (`character_weapon_variants.lua:1364`); registration is unconditional at boot for index determinism across wt peers (PROJECT_STANDARDS §9.3) - but the appended index must NEVER wire to a non-wt peer, which is the #431 gate + floor row below |
| `WeaponSystem.send_rpc_attack_hit` [hook] `_wt431_damage_profile_parity.lua` (#431) | THE single choke point every attack-hit send funnels through (melee sweep, hitscan `DamageUtils.process_projectile_hit`, projectiles, shield slam, push stagger, geiser, lunge, AoE): host dispatches the receiver locally, a client wires `damage_profile_id` to the host via `rpc_attack_hit` [src: `weapon_system.lua:148-183`; host decode `:243`] | Unconditional sender-side wire floor: coerce a wt-custom `damage_profile_id` back to its clone-source vanilla id before a CLIENT send whenever peer-parity is not positively confirmed - a non-wt host would fatal on the strict `__index` decode (BUG_CLASSES 31; the parity gate on the three toggles is the primary defense, this floor catches mid-swing latched-id leaks) | Takes no toggle argument by construction (class 31 fix template; wire safety is never toggle-gated, memory `reference_vt2_wire_safety_never_toggle_gated`); every named RPC param forwarded positionally, tail key/value pairs ride `...`; wt's ONLY `WeaponSystem` hook (pre-flight grepped 2026-07-13) |
| VMF channel `wt_peer_parity_present` (`mod:network_register`/`network_send`) `_wt431_damage_profile_parity.lua` (#431) | VMF mod-to-mod messaging delivers only to peers running the same mod id with a matching handler - absence of a reply proves absence of wt | The issue 371 peer-parity beacon (`_lib_peer_parity.lua` copy, master in `tools/shared_lib/`): the three custom-damage-profile toggles only repoint at cloned profiles while every human peer is confirmed to run wt; instant revert when one is not | Fail-safe: inert until positively confirmed, any beacon error forces features OFF; install() wraps `mod.update` (backend's) so it must load after `weapon_tweaker_backend.lua`; polling roster, zero hook-collision surface |

### Dev tooling + Big Rebalance (dormant)

| Class.method (kind) | Vanilla behavior | Why wt hooks it | Trap / invariant |
|---|---|---|---|
| `StateInGameRunning.update` [safe] `wt_dev_hold_pose.lua:559` | Per-frame in-mission tick [src: `scripts/game_state/state_ingame_running.lua`] | Dev anim-picker only: re-apply the held test pose every frame so the picker can eyeball a candidate `anim_event_3p` on the live 3P body (`:559`) | Per-frame hook - stays on `hook_safe` (NOT `traced_hook`) to avoid trace flood (`_safe_hook.lua` RATE-LIMIT CAVEAT); inert unless the dev picker toggle is on |
| `GenericStatusExtension.init` [safe] `weapon_tweaker_big_rebalance.lua:2326` (dormant - BR on ice, #433) | Constructs the per-unit status extension [src: `scripts/unit_extensions/generic/generic_status_extension.lua`] | Would seed a default `dodge_count` for the BR dodge-count knob | BR module is ON ICE (#433); consumers guard on `bt.is_br_active` so the whole module goes inert without `bt` (buff_tweaker retired) |
| `ActionFlamethrower._select_targets` [hook] `:2407` / `ActionBeam.client_owner_post_update` [hook] `:2472` / `ActionTrueFlightBow.client_owner_start_action` [hook] `:2497` / `.fire` [hook] `:2543` (all dormant - BR on ice, #433) | Vanilla per-action target selection / beam tick / true-flight aim + fire [src: `scripts/unit_extensions/weapons/actions/action_flamethrower.lua`, `action_beam.lua`, `action_true_flight_bow.lua`] | Would apply Big Rebalance behavior tweaks to these weapon actions | Registered only when the BR feature-gate is on; dormant while BR is on ice (#433) |

## Subsystem notes (how the vanilla flow runs, for wt's cases)

Each note is the minimum needed to read the hooks above; the owning `docs/engine`
doc carries the full architecture. Shared-with-`cwv`/`cosmetics` seams
(item->mesh resolution, owner vs husk, previewers, wire-id append) are documented
in `character_weapon_variants/ENGINE_SURFACE.md` and `docs/engine/03`,`/06`,`/09`
- not repeated here. The two notes below are wt's own surface.

### The 3P anim firing point + wt's three redirect layers (the core)

Vanilla resolves a weapon action's animation once, at
`WeaponUnitExtension` action start:
`get_action_anim_event(prev, current, skin_data, "anim_event_3p")` returns the
3P event name, falling back to the 1P `event` when the action has no explicit
`anim_event_3p` [src: `weapon_unit_extension.lua:512`]. It then fires that event
on the OWNER unit - the **3P body** - with `Unit.animation_event(owner_unit,
event_3p)`, gated only on `not
script_data.disable_third_person_weapon_animation_events` [src:
`weapon_unit_extension.lua:644-652`]. There is **no career branch** at this
point: the same event string is fired for every wielder. That is the whole
problem wt solves - a foreign weapon's `event_3p` names a clip that exists on
the native character's 3P skeleton but not the receiver's.

wt cannot change per-career behavior in `anim_event_3p` on a shared template
(that would break the native wielder too - the memory-class shared-template
mutation trap). The one per-career lever the engine exposes is the FIRING call
itself, so wt hooks `Unit.animation_event` and rewrites the event string in
flight. The funnel + all its tables live in `_wt_anim_remap.lua` (extracted from
the entry in v0.12.210-dev Phase 2). Resolution order in the funnel:

1. **Per-unit `state.remap` table** - a weapon-specific substitution
   map (`_3p_remap_spear_to_billhook`, etc.) selected at wield time via
   `_3p_remap_triggers` on `(career, template/key)`. SM-corrupting events that
   can't go in the table are force-fired through the captured original
   (`_original_animation_event`).
2. **`_career_anim_redirect`** - career-prefix-aware renames for
   phantom events that exist on all skeletons but only animate on the right
   character (`overrides[career]` -> `prefix`/`invert` -> `alt`), gated on a
   resolved career so anonymous preview units fall through.
3. **`_anim_redirect`** - global renames, fired only if the original
   event is missing from the skeleton.
4. **`_suffix_career_map`** - suffix swaps (`*_2h_billhook` ->
   `*_polearm`), longest-suffix-first, each verified `has_animation_event`
   before firing.

Every layer targets the 3P body; the 1P `first_person_unit` gets an
unconditional early return at the top of the hook because 1P is
universal (memory `feedback_1p_animations_universal`; DEVELOPMENT "1P animations
are universal"). Career comes from the UNIT
(`_unit_career_name`), not the local viewer, so a remote player's husk
remaps on THEIR career. `_wt_dev_anim_picker.lua` writes `anim_event_3p` values
directly onto the template's sub-actions to author new mappings; the funnel then
fires those values. Owner docs: `weapon_tweaker/DEVELOPMENT.md` ("Three-layer
remap system", "Remap-table gotchas") and `ANIMATION_COVERAGE.md` (the release
walk list).

### `wield_anim_career_3p` is the render lever + the cross-character port pipeline

The in-mission wield STANCE and the keep-previewer stance both read
`wield_anim_career_3p[career]` (then `wield_anim_career[career]`, then the
template's base `wield_anim`) and fire it on the 3P/preview body [src:
`world_hero_previewer.lua:1000-1005` for the character sheet, `:1059-1065` in
`_spawn_item_unit`; the same field feeds the in-mission wield]. Vanilla
cross-character templates carry NO `wield_anim_career_3p`, so wt's template
patcher (`wt_wield_patches.lua`, applied at boot to `Weapons.*`) writes a `to_*`
event per receiver career - both wiring the in-mission stance AND letting the
dev picker resolve each port's target template. It is 3P-only: every value is a
`to_*` wield event on `wield_anim_career_3p`, never `anim_event`/`wield_anim`
(1P). A full cross-character port is four stages - template patcher (this file)
-> package force-load -> in-mission 3P unit swap (`spawn_inventory_unit`,
`:5315`) -> preview unit swap (`MenuWorldPreviewer`, `:5964`/`:6184`). The
mod-side procedure is owned by `weapon_tweaker/CROSS_CHARACTER_PORT_RECIPE.md`
and `DEVELOPMENT.md`; this doc covers only the vanilla read/fire points those
stages hook.

The previewer subtlety: its `character_unit` has no `career_system` extension,
so the `Unit.animation_event` funnel's career-gated redirect is a no-op there
and a port whose `wield_anim_career_3p` omits the previewed career falls back to
the source template's base `wield_anim` (an event the receiver body doesn't
author) - the "missing pose" symptom (no T-pose; memory
`feedback_vt2_no_tpose_default_stance`). `_resolve_preview_wield_event`
(`_wt_anim_remap.lua`; moved with the funnel in v0.12.210-dev Phase 2, exported
as `mod._wt.resolve_preview_wield_event`) re-uses the SAME `_career_anim_redirect`
data to compute and fire the receiver-native wield event on the preview body
only, called from the entry's `MenuWorldPreviewer._spawn_item_unit` hook.

### Packages / residency (owner: `docs/engine/05`)

The 3P mesh swaps render a unit whose package the receiver never loads for its
native loadout, so wt force-loads the target packages at mod init via
`Managers.package:load(path, ref_name, nil, true, true)` under mod-owned
reference names (brace repeater 3P, Saltzpyre crossbow 3P + bolt, fire-explosion
FX, Necromancer FX) [src: `weapon_tweaker.lua:3826`+, guarded by
`Managers.package:has_loaded` at spawn, e.g. `:5418`]. The Necromancer FX load
is DLC-gated (memory `reference_vt2_la_package_force_load_crash`). See
`docs/engine/05` for the refcount + shutdown-leak model (#282).

## What the engine will NOT let us do (dead ends, already paid for)

Distilled from `weapon_tweaker/DEVELOPMENT.md`, `ANIMATION_RESEARCH.md` (repo
root), and the shared anim dead-ends in
`character_weapon_variants/ENGINE_SURFACE.md` - do not re-discover these.

- **No new animation clips.** wt can only pick from clips the receiver
  skeleton's state machine already authors; there is no path to ship animation
  files from a Workshop mod. When the receiver body lacks any clip for the
  donor's motion, the best available is the closest in-SM clip (DEVELOPMENT;
  cwv doc "No new animation clips").
- **No per-career sub-action anim on a shared template.** The engine reads
  `anim_event_3p` directly with no career context [src:
  `weapon_unit_extension.lua:512`]. Mutating a shared vanilla template's
  per-action events changes the NATIVE wielder too (memory-class
  shared-template mutation trap). The only levers are a per-career variant item
  (that is `cwv`'s job) or the `Unit.animation_event` firing-layer hook wt uses.
- **Some events corrupt the whole SM if remapped via the table.** Adding
  `attack_swing_stab_02 -> attack_swing_left_diagonal` to `state.remap` broke
  ALL billhook animations (v0.9.43); firing the same target through
  `_original_animation_event` directly works (`:3136`). Certain flail release
  events are the same class - direct `func()` call only (`:3056`).
- **H1 and H3+ of a 3-position heavy chain share their release event.** The SM
  differentiates by chain state, not event name, so redirecting H1's release
  also redirects H3+'s - you cannot make them visually distinct. What you CAN
  make distinct is the charge windup: remap H3+'s unique charge event to match
  H1's release direction (DEVELOPMENT "Heavy-attack chains are 3-position").
- **`has_animation_event` returning true is not proof a clip plays.** It reports
  true whenever the master SM knows the name; the destination state in the
  current sub-graph may be a stub that animates nothing. Only visible motion
  counts - every remap target must be eyeballed on the live body (DEVELOPMENT;
  cwv doc "force3p exists=true is not proof").
- **The preview `character_unit` has no career.** The `animation_event` funnel's
  career-gated redirect can't fire on it, which is why the preview wield pose
  needs its own resolver (`:640`) and the redirect branch is gated on a resolved
  career (`:3180`) to stop anonymous units routing through a cross-character
  redirect and landing in the wrong stance (v0.12.60).
- **Global template mutation to dodge a missing node breaks the native
  wielder.** Rewriting a template's `attachment_node_linking` source nodes at
  boot to fix a non-native body ALSO rewrote the native body's grip (elf bows
  went invisible, v0.12.112/.113). The durable fix is the per-spawn subtractive
  `link_units` filter (`:4698`) that only drops links the receiver genuinely
  lacks - it never mutates valid data.

## Doc maintenance

Follows `docs/engine/README.md` maintenance rules: if a wt hook moves, a guard
is added, or a cited vanilla line drifts after a game patch, edit the affected
row in the SAME commit. Line numbers are against the 2026-07-12 decompile and
mod source - match crash logs by function name, not line. Structural template is
`character_weapon_variants/ENGINE_SURFACE.md`; keep the section shape (hook table
-> subsystem notes -> dead ends) stable. ACTIVE dir is `weapon_tweaker/`; never
cite `weapon_tweaker_dev/` (stale abandoned clone).
