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
Grep-verified 2026-07-13 against the decompile and the mod source.

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

27 live engine registration sites, grouped below
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
| `Unit.animation_event` [hook] `_wt_anim_remap.lua` | Engine C-API: fires a state-machine event on a unit's anim graph. Per-action 3P resolution reads `anim_event_3p` (falling back to the 1P `event` when absent) and fires it on the OWNER (3P body) with no career branch [src: `scripts/unit_extensions/weapons/weapon_unit_extension.lua:512`, fired at `:652`] | THE singleton remap funnel: for a cross-access career on a foreign weapon, rewrite the 3P event to one the receiver skeleton authors, via the three redirect layers + per-weapon remap tables. The #536 helper in `_wt_reload_3p.lua` also re-arms Saltzpyre's native volley stance before generic elf-volley reload events. | Hottest hook in wt - five early-exits before work (nil event, feature-off, 1P unit by captured ref, then per-unit state); 1P `first_person_unit` gets an unconditional early return so 1P is never remapped (memory `feedback_1p_animations_universal`). **One registration only:** reload routing is called as a helper from this body because VMF drops a second hook on the same pair. No `pcall` around the hook itself (engine C); downstream engine calls are guarded. |
| `GenericAmmoUserExtension.start_reload_animation` [hook] `_wt_reload_3p.lua` | Selects base/no-ammo/last/override reload event, plays it on the first-person extension, then sends `rpc_anim_event`; it never calls the originating owner body's `Unit.animation_event` [src: `scripts/unit_extensions/generic/generic_ammo_user_extension.lua:287-332`]. A client-originated RPC is relayed to every client except the origin [src: `scripts/entity_system/systems/animation/animation_system.lua:358-375`]. | After vanilla completes unchanged, replay the already-selected event once on the local owner's 3P body only. This restores the animation exposed by a local third-person camera without sending a second RPC; the singleton `Unit.animation_event` funnel then applies the receiver-native volley route. | Owner-local + first-person-extension gate. Event selection mirrors vanilla precedence before vanilla clears transient fields. Do not apply this to `ActiveReloadAmmoUserExtension`, whose native update already calls `Unit.animation_event(owner_unit, reload_event)` [src: `scripts/unit_extensions/weapons/ammo/active_reload_ammo_user_extension.lua:85-100`]. Dispatch and `has_animation_event` remain unverified until visually observed. |
| `AnimationSystem.anim_event_with_variable_float` [hook] `:4585` | Fires a 3P anim event AND sets an anim variable (e.g. attack-speed scale) in one call [src: `scripts/entity_system/systems/animation/animation_system.lua:139`] | Guard: bail cleanly when the cross-character 3P body lacks the named anim variable, so a foreign weapon's speed-scaled event does not fault on a receiver whose SM never declared the variable (`:4585`) | Must validate `Unit.animation_find_variable` returns a number BEFORE delegating; the variable set is what differs from the plain `Unit.animation_event` path |

### Owner-local aim presentation

| Class.method (kind) | Vanilla behavior | Why wt hooks it | Trap / invariant |
|---|---|---|---|
| `ActionAim.client_owner_post_update` [safe] `_wt_longbow_variable_zoom.lua` | After base aim/camera work, vanilla cycles `current_action.buffed_zoom_thresholds` only when the owner has the `increased_zoom` perk, is already zooming, and presses action special [src: `scripts/unit_extensions/weapons/actions/action_aim.lua:107-141`] | Restore that authored threshold cycle for the exact Empire Longbow aim-action identity on the six supported non-Huntsman careers (#316) | Owner-local and post-vanilla; exact item + action-table + career allow-list. Native-perk owners, Huntsman, Warrior Priest, unrelated bows, inactive aim, and missing extensions fall through. The action table and thresholds remain vanilla-owned; no shared-template write, RPC, or `NetworkLookup` entry. This held-action callback stays on untraced `hook_safe` to avoid per-frame trace spam. |

### Wield + per-unit remap state (owner + husk; owner doc: `docs/engine/02`)

| Class.method (kind) | Vanilla behavior | Why wt hooks it | Trap / invariant |
|---|---|---|---|
| `SimpleInventoryExtension.wield` [hook via `traced_hook`] `_wt_anim_remap.lua` | Sets the wielded slot; the wield event ultimately fires the 3P body's wield stance [src: `scripts/unit_extensions/default_player_unit/inventory/simple_inventory_extension.lua:627`] | Populate this unit's `state.template`/`state.key` (drives the remap resolution in the `animation_event` hook) AND capture the local 1P hands unit ref for the funnel's 1P early-return (`_wt_anim_remap.lua`; moved v0.12.210-dev Phase 2 with the funnel it feeds) | `traced_hook` (safe_hook + trace) - wield is event-rate, not per-frame, so trace is flood-safe (`_safe_hook.lua` RATE-LIMIT CAVEAT); a raise here would otherwise kill later cosmetics/LA/cwv wield hooks silently (issue 26) |
| `SimpleHuskInventoryExtension.wield` [hook via `safe_hook`] `_wt_anim_remap.lua` | Husk-side wield: attaches units for a REMOTE player's view [src: `simple_husk_inventory_extension.lua:314`] | Populate the husk unit's remap state so a remote player's cross-character weapon renders its remapped 3P anims on the local viewer's screen (`_wt_anim_remap.lua`, v0.12.35 per-unit career) | Husk is a separate root class from the owner - hooking one never covers the other (CLAUDE.md "Self-owned vs husk"); husk resolves the BASE `item_data` (memory `reference_vt2_husk_resolves_base_item_data`) |
| `SimpleHuskInventoryExtension._wield_slot` [safe] `weapon_tweaker.lua` | Destroys prior husk equipment, resolves base item units with `self._career_name`, directly spawns/link 3P hand units, then publishes them on `equipment.*_wielded_unit_3p` [src: `simple_husk_inventory_extension.lua:641-782`; `gear_utils.lua:150-185`] | Apply shipped scale/grip tables after vanilla publishes the new remote units; register stomp-prone roots for renderer-local durable reapply and #569 canonical rotation | This path never calls `GearUtils.create_equipment`. Base item key + husk career are sufficient for deterministic baked lookup; no clone identity or transform RPC is needed. Writes 3P position/scale/rotation through separate setters; never 1P |
| `SimpleInventoryExtension._wield_slot` [safe] `_wt_diagnostics.lua` | Shows/hides 1p/3p units for the wielded slot; `slot_data.id` carries the item key [src: `simple_inventory_extension.lua:1926`] | Diagnostic only: dump everything wt knows about the wielded weapon (`anim_event`/`wield_anim`/`anim_event_3p`/`wield_anim_career_3p`/units) for `/wt_dump_wielded` (`_wt_diagnostics.lua`, v0.12.209-dev OOP split) | Husk deliberately NOT hooked here - we want our own equips, not teammates'; `hook_safe` so it never perturbs wield |
| `SimpleInventoryExtension.show_third_person_inventory` [safe] `:5919` / `SimpleHuskInventoryExtension.` `:5920` | Toggles visibility of the equipped 3P units on show/hide [src: `simple_inventory_extension.lua:1014`; `simple_husk_inventory_extension.lua:471`] | Re-hide the 3P units wt intentionally suppresses for a mesh swap (e.g. brace's left pistol that would clip the repeater body) whenever vanilla re-shows them (`_rehide_hidden_3p_units`) | Both owner + husk hooked (separate roots); shared handler function |

### Gear spawn + link - in-world render path (owner doc: `docs/engine/06`)

| Class.method (kind) | Vanilla behavior | Why wt hooks it | Trap / invariant |
|---|---|---|---|
| `GearUtils.create_equipment` [hook via `traced_hook`] `weapon_tweaker.lua` | Builds the owner/bot in-world equipment record and spawns 1p/3p units for a slot; passes `career_name` down to `spawn_inventory_unit` [src: `gear_utils.lua:7`] | Recover a dropped `career_name`, pre-resolve per-career `*_hand_unit_override` meshes, apply baked transforms, and register durable position + narrowly scoped #569 rotation roots | Read career from `inventory_system._career_name`, NOT `Managers.player:owner`, at mission-spawn timing. Durable position boxes canonical before the one-shot delta; #569 independently boxes/writes rotation. Receiver-scoped values such as `es_handgun.wh_ = {0,-0.17,-0.05}` and `wh_crossbow.es_ = {0,0.100,0.025,hand="left"}` belong in `_weapon_grip_offsets`, never the shared attachment table. #701 reads retained position back through `_wt_grip_offset_policy`; setter success is not evidence. Never touch `*_unit_1p` or shared linking tables [src: `crossbows.lua:258`; `attachment_node_linking.lua:4213-4225`; `gear_utils.lua:7-18`] |
| `GearUtils.spawn_inventory_unit` [hook via `traced_hook`] `_wt_ingame_3p_swap_owner.lua` | Spawns one hand's inventory unit from `item_template`+`item_units`; returns `(weapon_3p, ammo_3p, weapon_1p, ammo_1p)` with the two `ammo_*` nil for melee [src: `gear_utils.lua:155`, returns at `:273`] | Cross-character 3P MESH swap dispatch: after vanilla spawns, swap the 3P unit to the receiver-native model (brace->repeating handgun, longbow/Moonfire->crossbow, Skullsplitter+tome->1H Skullsplitter) inside a pcall so equip never fails (`_wt_ingame_3p_swap_owner.lua`; Moonfire #580) | The canonical 4-return / 2-nil-hole tuple that broke `safe_hook` v0.12.78 - `select("#", ...)` + explicit-`j` `unpack` is load-bearing (`_safe_hook.lua`, `docs/VMF_RECIPES.md` §2a); swapped 3P unit must be force-loaded first (see residency row); returned 1P units remain vanilla |
| `GearUtils.link_units` [hook,tbl] `:4698` | Attaches source->target units by `attachment_node_linking` via `Unit.node` per link; called from `GearUtils.link` [src: `gear_utils.lua:293`, dispatched at `:290`] | UNIVERSAL choke point: receiver-locally copy a missing `a_unwielded_*` body source to `j_hips` so cross-character holsters remain visible (#269), and drop every other link whose source/target is absent (`mod._wt_link_filter`) | Never mutate shared linking tables: valid/native links are zero-copy; the hip fallback is created only after `Unit.has_node(source, "j_hips")`, while missing targets and non-holster sources remain subtractive. `Unit.node` on a missing node bypasses `pcall`; table-form (`GearUtils` is a plain table) |

### Previewers + end-of-mission UI (owner docs: `docs/engine/09`, `/06`, `/01`)

| Class.method (kind) | Vanilla behavior | Why wt hooks it | Trap / invariant |
|---|---|---|---|
| `MenuWorldPreviewer.equip_item` [safe] `_wt_menu_preview_owner.lua` | Keep-inventory previewer equips an item into a preview slot (body copied from `HeroPreviewer.equip_item`) [src: `scripts/ui/views/world_hero_previewer.lua:649`] | Capture the preview item key for `_spawn_item_unit`, then run the preview-side mesh swaps (brace->repeater, longbow/Moonfire->crossbow, repeating-pistol->handgun, Skullsplitter+tome) by mutating `_item_info_by_slot[...].spawn_data.unit_name` (`_wt_menu_preview_owner.lua`; Moonfire #580) | Hook the DERIVED class, never the base - `class()` copies methods at load time (memory-class; [src: `foundation/scripts/util/class.lua:51-57`], `docs/engine/01`); consolidated - `hook_safe` does not chain, so all preview-swap helpers live in this ONE registration (memory `feedback_vmf_no_duplicate_hooks_burned_again`); mission and preview use one shared item-key predicate |
| `MenuWorldPreviewer._spawn_item_unit` [hook] `_wt_menu_preview_owner.lua` | Spawns a single preview unit for an item; fires the wield anim at spawn reading `wield_anim_career_3p` [src: `world_hero_previewer.lua:1050`, wield read at `:1059-1065`] | (a) pre-validate attachment source nodes vs the actual preview body (avoid the `Unit.node` fatal), (b) scale/offset the swapped mesh, (c) correct the preview 3P WIELD POSE for cross-character ports whose `wield_anim_career_3p` omits the previewed career (`_resolve_preview_wield_event`, `_wt_menu_preview_owner.lua`) | `[hook]` not `[safe]` - needs the pre-spawn node validation AND the return; this callback has no hand indicator, so a paired left/right transform descriptor MUST defer to `_spawn_item`; preview `character_unit` has no `career_system`, so the `animation_event` funnel's career-gated redirect is a no-op there - the pose fix re-uses `_career_anim_redirect` data to fire the receiver-native wield event directly (`_wt_anim_remap.lua` resolver, `_wt_menu_preview_owner.lua`) |
| `MenuWorldPreviewer._spawn_item` [hook] | Iterates `spawn_data`, calls `_spawn_item_unit`, and stores each result in `_equipment_units[slot_index].left/right` according to `left_hand`/`right_hand` [src: `scripts/ui/views/world_hero_previewer.lua:895-944`; derived passthrough: `scripts/ui/views/menu_world_previewer.lua:635-644`] | After vanilla spawning, apply hand-scoped grip/rotation descriptors to the exact paired preview unit and enroll its rotation in the durable tracker (#735) | `_item_info_by_slot` is string-keyed but `_equipment_units` is numeric; bridge only through the vanilla `spawn_data[i].slot_index`. Never infer a paired unit's hand inside `_spawn_item_unit`. The adapter is post-spawn and preserves vanilla's return value. |
| `LevelEndView._verify_weapon_data` [hook via `safe_hook`] `:6850` | Victory-screen weapon-pose validation; on a non-wieldable weapon it bails and can leave `verified_weapon.item_name` as a `{ item_name = "..." }` table [src: `scripts/ui/views/level_end/level_end_view_v2.lua:303`] | Unwrap that nested-table `item_name` shape so the downstream `TeamPreviewer` `ItemMasterList[item_name]` index does not crash on a cross-character weapon that failed the wieldable check (`:6850`) | Class is `LevelEndView` even though the file is `level_end_view_v2.lua`; belt-and-suspenders with the `TeamPreviewer` row below (same broken shape, defended at both the producer and the consumer) |
| `TeamPreviewer.cb_hero_unit_spawned_skin_preview` [hook] `:6892` | Spawns hero preview units for the end-screen / character sheet; indexes `ItemMasterList[item.item_name]` per `hero_data.preview_items` [src: `scripts/ui/views/team_previewer.lua:109`, index at `:119-120`] | Sanitize `preview_items[i].item_name`: unwrap the `{ item_name=... }` table shape (A) and null a string that is not a valid `ItemMasterList` key (B - career-name leak, deleted variant, stale skin) before the crash-site index (`:6892`) | String-form hook defers binding until `TeamPreviewer` loads (race-safe); this is the frame just above the `ItemMasterList` index - catches the broken shape regardless of which upstream path produced it |

### Backend - the availability control surface (owner doc: `docs/engine/11`; `weapon_tweaker_backend.lua`)

| Class.method (kind) | Vanilla behavior | Why wt hooks it | Trap / invariant |
|---|---|---|---|
| `items_interface.set_loadout_item` [hook,tbl] | Persists an equipped item to the selected career loadout, or to `optional_loadout_index` when supplied [src: `scripts/managers/backend_playfab/backend_interface_item_playfab.lua:635-669`] | Baseline-native weapons pass through to vanilla so their ordinary per-row persistence is preserved. A genuinely WT-unlocked cross-career weapon is kept out of PlayFab and cached by exact `career_name -> loadout_index -> slot_name`, then the hook returns `true`. | Classify native ownership only through `_wt_native_weapon_ownership.lua`; live `can_wield` is mutable and cannot authorize PlayFab. Resolve `optional_loadout_index` first and the interface's selected row otherwise, then prove that row exists; a `career -> slot` cache or ghost row is invalid because it masks Roman-numeral loadouts (#1190). Hook the RESOLVED interface instance (`Managers.backend:get_interface("items")`), not cold `_G`, for the LA dispatch path (memory `reference_cim_equip_capture_la_dispatch`). |
| `items_interface.get_loadout` [hook,tbl] / `get_loadout_item_id` [hook,tbl] | Read-side loadout resolution the menus and gameplay use; `_refresh_loadouts` reads only the mirror's selected row [src: `backend_interface_item_playfab.lua:109-124,447-458,512-524`] | Resolve the selected loadout index and overlay only that row's cached cross-career IDs. Re-validate ownership on every read so disabling a toggle or replacing an item clears only the affected row. | `get_loadout_item_id` must preserve `is_bot` on fall-through and never overlay the local player's cache onto a bot. Add/delete/reindex operations must keep cache row identity aligned or discard the affected entry; surviving rows may never inherit a deleted row's weapon. |
| `ItemGridUI._on_category_index_change` [hook,tbl] `:230` | Rebuilds the inventory grid's item filter when the category tab changes [src: `scripts/ui/views/hero_view/item_grid_ui.lua:723`] | Restore each category's base `item_filter` so wt's cross-character additions surface in the correct weapon-category tab (`:230`) | Table-form on the resolved `ItemGridUI` (loads early via inventory UI deps; string-form is the safer pattern per CLAUDE.md, noted as a low-risk exception) |
| `Weapons[*].actions` [data contract] `_wt_availability.lua` | `CharacterStateHelper._get_chain_action_data` iterates every active career ability and resolves each declared `action_name` on the currently wielded item template [src: `scripts/unit_extensions/default_player_unit/states/player_character_state_helper.lua:1081-1118`] | Install all weapon-bound ability rows on every enabled native cross-character or CWV template through `_lib_career_weapon_actions.lua` | Ten current actions across nine careers; Waywatcher has two. Preserve donor rows by identity, record/remove only WT insertions, and emit a bounded error for missing career/action providers. Ability-class careers need no fabricated action. |

### Cosmetic projectile FX + custom damage-profile registration

| Class.method (kind) | Vanilla behavior | Why wt hooks it | Trap / invariant |
|---|---|---|---|
| `PlayerProjectileUnitExtension` / `PlayerProjectileHuskExtension` `.hit_enemy` / `.hit_level_unit` / `.hit_non_level_unit` [safe] `:5284` (2 classes x 3 methods) | Resolves a fired projectile's impact on the shooter's machine and on every peer's husk view [src: `scripts/unit_extensions/weapons/projectiles/player_projectile_unit_extension.lua`] | Spawn the Moonfire-arrow impact puff FX on both the shooter's and every observer's screen; hooking both roots is why the puff is visible to all peers (`_wt_moonfire_on_hit`, `:5284`) | Both roots carry the same fields the handler reads; the FX package rides the equipped Moonbow, so `World.create_particles` on hit is safe; cosmetics_tweaker's identical puff defers to this one (no double-up) |
| `WeaponSystem.rpc_start_flamethrower` / `.update_synced_flamethrower_particle_effects` [safe post] `_wt_flamestorm_fx.lua` (#400) | Creates the synchronized 3P flamethrower particle and moves it every update from the wielded 3P weapon's `fx_muzzle` position and rotation [src: `scripts/entity_system/systems/weapon/weapon_system.lua:470-487,744-774`] | For exact `staff_flamethrower_template` use on non-Sienna careers, preserve muzzle position but orient the observer particle from the wearer's replicated `aim_direction`, matching the owner damage ray [src: `scripts/unit_extensions/weapons/actions/action_flamethrower.lua:226-228`] | Visual-only and peer-local. Exact template + non-`bw_` policy excludes Drakegun and native Sienna; one helper owns immediate creation plus the required continuous re-assert because vanilla rewrites the pose rotation every update. One apply log per unit, never per frame. |
| `_lib_network_lookup.register_named(NetworkLookup, "explosion_templates", ...)` [tbl] `wt_moonfire_aoe_revert` registration (#428/#535) | The lookup is built once at engine boot and frozen with a strict `__index` that errors on a missing key [src: `scripts/network_lookup/network_lookup.lua` build `:1211` (`create_lookup({"n/a"}, ExplosionTemplates)`), strict `__index` `:2360-2367`] | Register the pre-nerf Moonfire AoE revert template as an index-append so any `NetworkLookup.explosion_templates[name]` encode cannot strict-`__index`-fatal (index determinism, PROJECT_STANDARDS §9.3) | The canonical helper uses only raw access, validates the complete dense symmetric lookup before trusting or extending it, accepts an existing exact pair idempotently, and rejects malformed state without mutation; rejection evidence is bounded by reason and reaches `wt_535_moonfire_explosion_registered`. The check also pins the fallback's positive integral index and reverse row, and treats a previously registered lookup axis disappearing as failure. **Wire-inert / belt-and-suspenders.** `_wt_moonfire_on_hit` calls `DamageUtils.create_explosion` DIRECTLY, never `AreaDamageSystem.create_explosion`. `DamageUtils.create_explosion` never encodes via `NetworkLookup.explosion_templates`; its only AoE-network touch is `area_damage_system:add_aoe_damage_target` [src: `damage_utils.lua:1470`] -> host-only local ring buffer, name stored as a STRING, resolved via `ExplosionUtils.get_template -> ExplosionTemplates[name]` [src: `area_damage_system.lua:280,331,347`], never `NetworkLookup`. The ONLY `NetworkLookup.explosion_templates[name]` encode in the explosion path is `AreaDamageSystem.create_explosion` [src: `area_damage_system.lua:162`], which moonfire never reaches - so the name never rides the wire and no floor hook is needed. Fallback `machinegun_poison_arrow` recorded in `mod._wt535_explosion_template_fallback` for a future send path. |
| `rawset(NetworkLookup.damage_profiles, ...)` [tbl] `:4832`, `:5146`, `_wt_brett_sword_shield_buff.lua:128` | The lookup is built once at game load and frozen with a strict `__index` that errors on a missing key [src: `scripts/network_lookup/network_lookup.lua` build `:2209` (`create_lookup({}, DamageProfileTemplates)`), strict `__index` `:2360-2367`] | Register wt's cloned damage profiles (authentic brace no-dropoff, priest-punch scaled, brett buff) as index-appends so `PlayerProjectileUnitExtension`'s `NetworkLookup.damage_profiles[...]` lookup at projectile spawn does not fatal (`:4829`) | Forward + reverse append (`idx->key` and `key->idx`), guarded by `rawget` so it registers once; same pattern cwv uses for its custom profiles (`character_weapon_variants.lua:1364`); registration is unconditional at boot for index determinism across wt peers (PROJECT_STANDARDS §9.3) - but the appended index must NEVER wire to a non-wt peer, which is the #431 gate + floor row below |
| `WeaponSystem.send_rpc_attack_hit` [hook] `_wt431_damage_profile_parity.lua` (#431) | THE single choke point every attack-hit send funnels through (melee sweep, hitscan `DamageUtils.process_projectile_hit`, projectiles, shield slam, push stagger, geiser, lunge, AoE): host dispatches the receiver locally, a client wires `damage_profile_id` to the host via `rpc_attack_hit` [src: `weapon_system.lua:148-183`; host decode `:243`] | Unconditional sender-side wire floor: coerce a wt-custom `damage_profile_id` back to its clone-source vanilla id before a CLIENT send whenever peer-parity is not positively confirmed - a non-wt host would fatal on the strict `__index` decode (BUG_CLASSES 31; the parity gate on the three toggles is the primary defense, this floor catches mid-swing latched-id leaks). #1158 application floor: the id resolution is a pure numeric disposition (`_wt431_wire_contract.profile_id_for_send`) over a load-time catalog snapshot - a WT-owned id stays custom ONLY under an installed exact gate plus an intact live catalog; on any policy or lookup failure it substitutes a donor proven RESIDENT in the live lookup (round-trip in both directions, not mere table presence) or returns nil so the hook DROPS the RPC. The custom numeric id can never survive a failure. Dropping also skips the function's local boss-health-bar registration (`weapon_system.lua:185-200`) - accepted, since the alternative on that branch is a hard host-side `NetworkLookup` error; drop logging is bounded per distinct id | Takes no toggle argument by construction (class 31 fix template; wire safety is never toggle-gated, memory `reference_vt2_wire_safety_never_toggle_gated`); every named RPC param forwarded positionally, tail key/value pairs ride `...`; wt's only hook on this (Class, method) - re-grepped 2026-08-08; the mod's other `WeaponSystem` hooks target different methods (`_summon_vortex`, `rpc_start_flamethrower`, `update_synced_flamethrower_particle_effects`), so there is no collision |
| VMF channel `wt_damage_profiles_exact_v1` (`mod:network_register`/`network_send`) `_wt431_damage_profile_parity.lua` (#431) | VMF mod-to-mod messaging delivers only to peers running the same mod id with a matching handler - absence of a reply proves absence of wt | The issue 371 peer-parity beacon (`_lib_peer_parity.lua` copy, master in `tools/shared_lib/`): the custom-damage-profile toggles only repoint at cloned profiles while every human peer proves the same exact catalog; instant revert when one is not | The dedicated exact-generation channel must never alias legacy `wt_peer_parity_present`: its presence-only handler ignores appended proof and would otherwise acknowledge asymmetrically. Fail-safe: inert until positively confirmed; any beacon error forces features OFF; install() wraps `mod.update` (backend's), so it must load after `weapon_tweaker_backend.lua`. #1158: the beacon is published to `mod._wt_peer_parity` only after an install-commit check, so a half-installed beacon can never present itself as a confirmed gate. The install-transaction fanout landed with the shared lib's latch: `install()` performs receiver registration and `mod.update` ownership inside ONE pcall and RETURNS the commit boolean, wt requires BOTH that boolean and `is_installed()`, and a failed attempt is terminal for the instance (no retry can double-register a retained receiver). The transport also rejects a mismatched schema generation BEFORE accepting a peer's epoch or challenge, so a previously acknowledged peer cannot stay exact-safe after presenting an incompatible generation. `_wt431_profiles_allowed()` requires installed AND enabled AND live-catalog integrity against the load-time snapshot. |

### Direct setting-table tweaks (no hook)

| Data seam | Vanilla behavior | Why wt mutates it | Trap / invariant |
|---|---|---|---|
| `PlayerUnitStatusSettings.overcharge_values.spark` `_wt_bolt_staff_overcharge.lua` (#341) | Both alternating Bolt Staff primary sub-actions name the unique `spark` key [src: `staff_spark_spear.lua:24,108`]; `ActionChargedProjectileUtility.fire_charged_projectile` resolves that key at fire time and passes it to `add_charge` [src: `action_charged_projectile.lua:41-58`] | Optional 40% primary-overcharge reduction by scaling the captured scalar to 0.6; live setting changes reapply it | Snapshot and restore the exact pre-WT value; never mutate the charged `spear*` keys, damage, cadence, or action tables. No hook, NetworkLookup entry, or RPC surface |

### VMF bulk-setting lifecycle (no engine hook)

`_wt_settings_runtime.lua` installs `mod.on_settings_batch_changed(ids)` as
WT's explicit opt-in to GUI Tweaker's owner transaction (#560/#1002). VMF has
already persisted every value with
`notify=false` before this callback runs. `_wt_master_toggles.reconcile_batch`
and `_wt_rework_master_runtime.prepare_batch` preserve master-only cascade
semantics while treating a complete master+children DEFAULT/profile snapshot as
authoritative child state. WT then runs availability, career-action, energy,
backend, trait, and balance reconciliation once. The bounded diagnostic is
`[wt:1002] settings=<N> availability_applies=1 action_applies=1`; no class hook,
RPC, package, or per-frame work is added. See `docs/BUG_CLASSES.md` class 79.
| `Weapons[*].actions.action_one` + damage-profile clones `_wt_axe_balance.lua` (#621/#622/#623) | `ActionUtils.get_max_targets` multiplies cleave power by `cleave_distribution.attack/impact` [src: `scripts/helpers/action_utils.lua:22-29`]. Weapon action completion and chain windows divide authored time by `ActionUtils.get_action_time_scale` [src: `scripts/unit_extensions/weapons/weapon_unit_extension.lua:487-489,930-937`] | Three default-off policies: 0.90x 1H Axe cleave by capability, 1/1.10 Cog Hammer heavy release speed, and 1/1.10 native Mace and Sword L1/L2/heavy speed | Private cleave profiles preserve shared donors and register in sorted order even while off; action repointing is #431 parity-gated and wire-floored. Speed allow-lists are exact and restore nil/non-nil authored scales. Dual/shield/2H axes and CWV reversed Sword and Mace are explicit controls. No new hook/RPC/per-frame work |
| local `PlayerUnitOverchargeExtension` scalars + `OverchargeBarUI.set_charge_bar_fraction` [safe,tbl,deferred] `_wt_overcharge_presentation.lua` (#388) | Player creation copies career-keyed `OverchargeData` into the owner extension [src: `bulldozer_player.lua:206`; `player_unit_overcharge_extension.lua:9-77`]; HUD draw independently selects `OverchargeData[player:career_name()].overcharge_ui` [src: `overcharge_bar_ui.lua:234-271`] | While exact `we_life_staff` is ranged-equipped off-career, reversibly project Sister decay/sound/screen/non-explosion fields and apply its native green palette to local/spectator HUD | Owner-local scalar mutation only; overcharge value replication stays vanilla. HUD class is mission-lazy, so install table-form only after `_G.OverchargeBarUI` exists. Clear live particles before profile transitions; restore exact captured nil/non-nil fields on removal/disable. No RPC, NetworkLookup, or husk mutation |

### Dev tooling

| Class.method (kind) | Vanilla behavior | Why wt hooks it | Trap / invariant |
|---|---|---|---|
| `StateInGameRunning.update` [safe] `wt_dev_hold_pose.lua` | Per-frame in-mission tick [src: `scripts/game_state/state_ingame_running.lua`] | Hold-Pose tuner: compose local-player 3P position/rotation deltas and absolute non-uniform scale independently over one captured canonical/baked weapon-root transform | Per-frame hook stays on `hook_safe` (NOT `traced_hook`) to avoid trace flood; inert unless live apply is on. Never use absolute `set_local_pose`: each component has its own setter, identity restores its captured baseline once, and desired values rebuild from scalars rather than the prior frame |

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
flight. The funnel and runtime tables live in `_wt_anim_remap.lua` (extracted
from the entry in v0.12.210-dev Phase 2); its declarative per-template catalog
is built once from `_wt_anim_remap_data.lua` (v0.12.235-dev). Resolution order
in the funnel:

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

Generated/baked picks are an overlay, not a replacement map. The Billhook burn in #290
showed why: its five saved rows are keyed by 1P `anim_event`, while the body actually receives
the authored `anim_event_3p` for those actions. Replacing the receiver safety map deleted the
only rows keyed by those effective events. Bakes must merge into the receiver map and a runtime
contract must enumerate `anim_event_3p or anim_event` for every donor action against either an
explicit remap or the receiver template's native vocabulary.

CWV Combat Styles add a second identity boundary: WT stores the effective
template name returned by CWV in per-unit wield state before resolving this
catalog. If the style deep-clones a donor action graph under a new template
name, that clone must share the donor's receiver-remap and 3P-wield tables by
identity. Otherwise the clone can emit a source action's `anim_event_3p` without
the donor's receiver-safe translation. Issue #732 demonstrated the C-API
failure: `light_attack_stab_1` from `two_handed_spears_elf_template_1` authors
`attack_swing_down_left_axe` [src:
`scripts/settings/equipment/weapon_templates/spears_wood_elf.lua:882-888`];
on Saltzpyre the unaliased `cwv_infantry_spear_template` reached
`Unit.animation_event(owner_unit, event_3p)` [src:
`scripts/unit_extensions/weapons/weapon_unit_extension.lua:644-652`] instead of
the donor contract's `attack_swing_stab` target.

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
`_wt_ingame_3p_swap_owner.lua`) -> preview unit swap (`MenuWorldPreviewer`,
`_wt_menu_preview_owner.lua`). The
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
only, called from the `MenuWorldPreviewer._spawn_item_unit` hook that
`_wt_menu_preview_owner.lua` now owns (#1159 wave 14).

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
  went invisible, v0.12.112/.113). The durable fix is the receiver-local
  `link_units` sanitizer: it copies missing `a_unwielded_*` sources to an
  actually-present `j_hips` (#269), drops other invalid links, and never mutates
  valid data.

## Doc maintenance

Follows `docs/engine/README.md` maintenance rules: if a wt hook moves, a guard
is added, or a cited vanilla line drifts after a game patch, edit the affected
row in the SAME commit. Line numbers are against the 2026-07-12 decompile and
mod source - match crash logs by function name, not line. Structural template is
`character_weapon_variants/ENGINE_SURFACE.md`; keep the section shape (hook table
-> subsystem notes -> dead ends) stable. `weapon_tweaker/` is the public-beta
primary and `weapon_tweaker_dev/` is its friends-only runtime-parity mirror.
Preserve their distinct VMF/settings namespaces and Workshop presentation;
`qa/check_wt_stream_parity.ps1` permits no gameplay-code drift.
