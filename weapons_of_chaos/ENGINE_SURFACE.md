# weapons_of_chaos - engine contact surface

What vanilla VT2/Stingray does at every seam `weapons_of_chaos` (`WOC`) touches,
and why the mod is there. This is the per-mod companion to the subsystem set in
`docs/engine/` (read `docs/engine/README.md` for house style). It does **not**
re-explain a subsystem the engine docs own, and it does **not** duplicate the
mod's `DEVELOPMENT.md` (enemy-mesh catalog, keep-trophy paths, the full
duplicate-weapon crash post-mortem) - it names each engine seam, cites the
vanilla behavior, and links out. Decompile paths are relative to
`C:\Users\danjo\source\repos\Vermintide-2-Source-Code`; `WOC` line numbers are
`weapons_of_chaos.lua` unless noted. `§N` = a `docs/BUG_CLASSES.md` class; `#N` /
"issue N" = a GitHub issue. Grep-verified 2026-07-12 against the decompile.

`WOC` lets player characters wield ENEMY weapons and named keep-trophy artifacts
via the duplicate-item approach modeled on `character_weapon_variants`: it clones
a player base weapon template into a new MoreItemsLibrary item and swaps the held
mesh to a different `.unit`. There is one registered item - the Blightreaper
(private 75%-speed Kerillian Sword actions, all careers), rendered with the authored Blightreaper mesh
because the intended keep-trophy prop is not runtime-loadable (see dead ends). Its
engine contact includes display/registration/wire safety plus the four canonical
weapon-render consumers: gameplay inventory spawn, character preview, item
preview, and package collection/loading.

`_woc_boss_weapon_catalog.lua` owns two explicit facets: a read-only
breed/inventory source audit for #642, and fail-closed registration descriptors
for #614/#615. The descriptors record player-template fallbacks and authored
resource closure; unclosed rows remain registration-disabled.

## Hook table

The registration sites below are split between `weapons_of_chaos.lua` and
`_woc_mod_unit_preview.lua`. `[hook]` = full wrapper (`mod:hook`, can rewrite
args/returns); `[safe]` = `mod:hook_safe` (post-callback, no override); `[tbl]` =
table-form hook (plain-table target, nil-guarded). The item and NetworkLookup
registration itself is NOT a hook - it is direct `rawset`/assignment inside the
`_register_blightreaper` chokepoint (`:230`), covered in the subsystem notes.

`_woc_relic_policy.lua` is the engine-free inventory authority for issue #637.
It marks every WOC provider definition and actual MIL backend row as one
immutable local `cursed` relic, plans duplicate reconciliation by exact backend id,
and never admits the deterministic canonical id to its deletion set. CIM dev
consumes this marker at its provider validator and sole crafting dispatcher;
this avoids separate Forge/Athanor/Salvage/Illusion UI patches.

### Item resolution + display naming (owner docs: `docs/engine/06`, `docs/engine/09`)

| Class.method (kind) | Vanilla behavior at the seam | Why WOC hooks it | Trap / invariant |
|---|---|---|---|
| `_G.Localize` [hook,tbl] `:168` | Global loc-key -> string lookup; the inventory UI Localizes an item's `display_name` / `description` / `item_type` keys | Supply the Blightreaper display name/description/type labels for `woc_*` keys (`:168`) | VMF `_localization.lua` is NOT auto-registered into the global `Localize` (`docs/VMF_RECIPES.md`); a raw pass-through for every non-`woc_` key. `item_type` is set to `ITEM_KEY` so `Localize(item_type)` yields the item's display label, not the base weapon's |
| VMF `custom_gui_textures` [data contract] | Injects a private GUI material only into explicitly named renderers | Register the authored `icon_wpn_blightreaper` material for inventory/equipment renderers | `_woc_inventory_icons.lua` owns the renderer allow-list. The WOC item retains its cloned vanilla icon in `cim_inventory_icon_fallback`; Athanor and any unproven renderer fail closed. Non-WOC peers receive only the vanilla-keyed loadout identity and never the custom resource name. |

### Registration timing (owner doc: `docs/engine/08`)

| Class.method (kind) | Vanilla behavior at the seam | Why WOC hooks it | Trap / invariant |
|---|---|---|---|
| `StateInGameRunning.on_enter` / `on_exit` [safe] | Fires on entering/leaving the keep and each mission [src: `scripts/game_state/state_ingame/state_ingame_running.lua`] | Register the item once; arm the host kill listener on entry and remove its listener/network units/weak attribution records on exit | Registration remains one-shot; spirit state is mission-scoped and never survives teardown. |

### Wire safety - never crash a non-WOC peer (row-of-concern: issue 422 / issue 278) (owner doc: `docs/engine/03`)

| Class.method (kind) | Vanilla behavior at the seam | Why WOC hooks it | Trap / invariant |
|---|---|---|---|
| `LoadoutUtils.sync_loadout_slot` [hook,tbl] | Encodes item, rarity, properties, and traits through local `NetworkLookup` integers for direct, host-broadcast, client-to-server, and hot-join sync [src: `scripts/helpers/loadout_utils.lua:12-53`; property/trait encoding in the same module] | Observe exact live equip, replace every marker-owned WOC item with a vanilla `BASE_WEAPON` / `promo` shadow, and strip protected WOC traits from ordinary CIM items | ROW-OF-CONCERN. `ITEM_KEY`, `cursed`, and WOC trait keys are not shared lookup ids. None may reach a peer without WOC. The policy is unconditional, shallow-copy/non-mutating, and fails closed if the base index is unavailable. A fail-closed skip records up to three non-WOC caller frames, deduplicated and capped at eight log-only lines per session (#278); it never sends chat or changes the skip decision. |

### Shared relic lease and keep trophy presentation (#934)

| Class.method (kind) | Vanilla behavior at the seam | Why WOC hooks it | Trap / invariant |
|---|---|---|---|
| `LoadoutUtils.sync_loadout_slot` + VMF `woc_relic_lease_intent_v1` / `woc_relic_lease_state_v1` [hook/RPC] | Publishes the current live loadout at ordinary equip, spawn, transition, and hot-join edges | Derive a claim/release intent only for the exact local human at the existing loadout edge; the host grants the first claimant and publishes one authority-epoch-bound `(generation, holder, melee-bit, ranged-bit)` snapshot that atomically owns both lease and remote render identity | No lease identifier enters vanilla transport. Clients target the literal host peer id, never the unsupported `"server"` alias. Bot/remote syncs cannot claim or author render identity. Retail player identity is read through `local_player_id()` with `_local_player_id` as its stored value [src: `scripts/managers/player/bulldozer_player.lua:451-456`; bot marker and storage at `player_bot.lua:16-34`]. Intent, state, and query callbacks reject inactive or closed authority epochs; discovery replies also echo a client-session epoch. The retained epoch floors prevent delayed prior-session packets from mutating a new lobby. A rival is not queued; it must equip again after release. Host promotion rebuilds a fresh epoch from the authenticated holder and exact cached slots; an unknown slot receives one four-second fail-closed reservation while the client immediately reasserts. Four one-second state-query retries are the bounded hot-join/host-migration recovery path, never a per-frame RPC. |
| `HeroViewStateOverview._set_loadout_item` / `BackendUtils.set_loadout_item` / `SimpleInventoryExtension.create_equipment_in_slot` [hooks] | The Hero action calls the backend writer but ignores its return, then unconditionally queues the clicked backend id for live creation [src: `scripts/ui/views/hero_view/states/hero_view_state_overview.lua:1108-1123`; queue drain at `:697-715`]. The backend helper dispatches to the selected per-slot interface and accepts nil to clear a slot [src: `scripts/managers/backend/backend_utils.lua:22-28`; `scripts/ui/views/hero_view/states/hero_view_state_overview.lua:1185`] | Reject a known rival before the ordinary UI can persist or queue it, retain the outer backend gate across interface overrides, and block direct live creation too | Exact canonical backend id and weapon slots only. A simultaneous loser restores only the exact observed prior backend id; a pre-equipped loser clears and verifies the persisted slot rather than guessing a replacement. Release requires both durable readback and the current live slot to converge; queued loadout/hotjoin payloads are never evidence. Denial removes the exact live relic immediately, then retries durable convergence with exponential backoff capped at eight seconds; four failures enter terminal fail-closed mode without ending the retry. Delayed local seeding and every host rebuild/state application re-enforce denial. |
| `KeepDecorationTrophyExtension._load_trophy` [hook] | Replaces the displayed keep trophy with the selected `Trophies[key].unit_name`; selection persistence is owned elsewhere | Transiently substitute the resident `hub_trophy_empty` for `hub_trophy_bogenhafen` while a holder exists, then replay the requested trophy on lease release | Never mutate the saved trophy selection or its vanilla game object. Only WOC peers see the substitution; non-WOC peers keep their vanilla trophy and receive no custom resource identity. Weak extension tracking and edge-only refresh prevent dead-world retention or polling; every session reset replaces the weak registry after restoring presentation. |
| `PlayerManager.player_from_peer_id` [bounded read] | Resolves a connected human peer while the gameplay state is live | On the host, release a stale holder after three continuous seconds without that peer | Do not release synchronously from `PlayerManager.remove_player`: bot/state-transition churn can temporarily remove peer rows. The four-second host-migration reservation outranks the three-second absence grace; session reset also clears the complete remote-identity cache. |

### Combat, poison, and Chaos Wastes identity (#632)

| Class.method (kind) | Vanilla behavior at the seam | Why WOC hooks it | Trap / invariant |
|---|---|---|---|
| Private combat-template clone [data contract] | Sienna's Crowbill supplies the whole graph: four chained lights, three heavies, the push-attack follow-up, `crowbill_stab_hit` / `melee_hit_hammers_1h` / `blunt_hit_armour` impact identity, dodge buffs, the `1h_crowbill` 1P state machine, and `wwise/one_handed_crowbills`; the Greataxe supplies only the armor-capable light/heavy damage profiles; Executioner Sword declares `wwise/two_handed_swords` [src: `scripts/settings/equipment/weapon_templates/1h_crowbills.lua`; `2h_axes.lua`; `2h_swords_executioner.lua:1311-1313`] | Keep the crowbill graph at 83% speed with native chain transitions, bake +15% crit per sweep, override light/heavy damage profiles, normalize the burn stab's fire sounds to the family baseline (its burn profile is replaced by poison), install `wield_anim_career_3p`, and make the Executioner audio bank resident | Clone complete authored sweeps; never pair an animation with another weapon's baked geometry. `+50% Power vs. Order` is a no-op display row and must never gain a stat buff. Exact swing whoosh remains an in-game verification boundary because it is authored in flow/state-machine data, not named in Lua. |
| `WeaponUnitExtension._play_3p_anim` [hook] | Sends and plays one vanilla animation event plus attack-speed variable | Apply Weapon Tweaker's proven per-receiver crowbill redirects for non-Sienna skeletons before vanilla sends the event (wield stance is handled in data via `wield_anim_career_3p`) | No custom animation id or per-frame pose traffic. |
| `WeaponTraits.traits` + local equipment `on_hit` proc | GearUtils resolves item trait keys into equipment buffs; the wielder's buff extension emits light/heavy hit events [src: `scripts/helpers/gear_utils.lua`] | `Poisoned Edge` owns the sole proc and applies native `arrow_poison_dot` with `BuffSyncType.All`; `Shyish Health Curse` is an intrinsic display/gating row using native `mutator_icon_death_spirits` | No custom trait is appended to `NetworkLookup.traits`. Vanilla `apply_dot_on_hit` is server-only and would fail for a client owner; the WOC proc sends only a native buff id. Template-level poison is forbidden because it would double-proc with the trait. |
| `BuffSystem.rpc_add_buff_synced_params` [safe] | Host accepts a client-created native buff and unpacks attacker params [src: `scripts/entity_system/systems/buff/buff_system.lua:957-1010`] | On the host only, observe accepted `arrow_poison_dot` from a client currently wielding Blightreaper and retain one weak victim/owner marker | Observation adds no RPC and no lookup id. Marker TTL is four seconds (native poison lasts three) and is cleared on kill or state exit. |
| `on_player_killed_enemy` event + `mod.update` [event/update] | Death reactions publish the killing blow; Shyish's `mutator_death` spawns `vfx_animation_death_spirit_02`, waits/chases, and converts health through damage/heal [src: `scripts/unit_extensions/generic/death_reactions.lua:677`; `scripts/settings/mutators/mutator_death.lua:7-115,190-224`] | Attribute direct and poison kills to the exact wielder, spawn the native network unit on host, reproduce rank-one movement/audio/FX, then apply `death_explosion` damage and a same-amount `mutator` heal | Host only; 32 active cap; O(active) update; 16 log lines; leave one green health; delete all units at state exit. Spawn gates on the loaded reference for the real `DLCSettings.mutators_batch_04.package_name` package (installed hash `64E79277358D543D`), never `Application.can_get` or a unit-path load. |
| `DeusMechanism._setup_run` + item lookup/generation [hook] | Converts backend item keys through `DeusStartingWeaponTypeMapping`, generates starter weapons, then overwrites their power | Recognize the marker-owned relic through a scoped non-mutating key shadow and restore 900/Cursed at grant | Never serialize a custom Deus key. Pending setup identity is synchronous and cleared on success or error. |
| `DeusWeaponGeneration.serialize_weapon` / `deserialize_weapon` [hook,tbl] | Serializes a comma-delimited item key, power, rarity, traits and properties; ignores unknown fields on read | Send vanilla `deus_es_1h_sword`/`unique` plus `woc=blightreaper`; restore only on WOC peers | Non-WOC readers ignore the marker and remain safe. If a non-WOC authority strips it while reserializing, the exact 900/unique donor signature is recoverable; vanilla generation is source-bounded to 700. |
| `DeusChestExtension.can_be_unlocked` + `DeusWeaponGeneration.upgrade_item` [hook] | Compares rarity order, charges, then creates an upgraded weapon | Reject tempering both before purchase and at execution | Cursed order 7 is already above vanilla altar rarities; explicit identity guard protects against future table changes. |
| `DeusRunController.get_weapon_pool` [hook] | Applies saved rarity-keyed pool exclusions | Remove only WOC's `cursed` key when absent from the base pool | Prevents a subsequent chest from indexing `weapon_pool.cursed == nil` without mutating another mod's rarity state. |

### Appearance and preview parity (owner docs: `docs/engine/05`, `docs/engine/06`, `docs/engine/09`)

| Class.method (kind) | Vanilla behavior at the seam | Why WOC hooks it | Trap / invariant |
|---|---|---|---|
| `BackendUtils.get_item_units` [hook,tbl] | Produces the per-hand unit table consumed before gameplay and preview spawn recipes; inherited item names can resolve the base definition | For an exact relic backend identity, overwrite the result with the authored right-hand unit before every consumer branches | Canonical keep/mission/preview replay owner. Blightreaper is immutable, so no skin supersedes it. Non-relic results pass through by identity. |
| `GearUtils.spawn_inventory_unit` [hook,tbl] | Spawns explicit 3P and optional 1P units, links attachment node 0, and returns `(weapon_3p, ammo_3p, weapon_1p, ammo_1p)` [src: `scripts/unit_extensions/default_player_unit/inventory/gear_utils.lua:155-308`; node mapping `scripts/settings/attachment_node_linking.lua:2726-2753`] | Re-key positively identified WOC husks, log requested/returned unit identity, resolve the exact named `blightreaper` render node, apply the canonical `0.9` baseline scale multiplier, `{-180,-90,-90}` rotation, and `{0,0,-0.3}` offset atomically, then submit the complete custom 3P snapshot to the shared FadeSystem adapter (#712/#922) | Capture and return all four values; never bail from vanilla. Live #712 evidence shows the complete pose is rejected on linked node 0 while both authored units resolve their visible renderable as node 2. That child has native scale `{100,100,100}`, so resolve the `0.9` multiplier to absolute `{90,90,90}` before calling WA; absolute `{0.9,0.9,0.9}` makes the model effectively invisible. Leave the attachment root game-owned, never hard-code the observed child index, require every channel plus node/error detail in the shared WA report, and never submit a partial custom-unit-only fade list. Same-WOC identity and fade enrollment are bounded to loadout/spawn edges, not per frame. |
| `SimpleInventoryExtension._wield_slot` [hook] | Commits the final owner/bot 3P wielded-unit fields but has no husk-style FadeSystem replay [src: `simple_inventory_extension.lua:1926-2169`] | Re-enroll the complete snapshot after a positively identified Blightreaper wield (#922) | Exact relic markers gate the call; ordinary and foreign weapons pass through unchanged, and the adapter deduplicates repeated edges |
| `WeaponUtils.get_weapon_packages` [hook,tbl] | Collects weapon unit paths for package preparation | Replace only WOC unit package identities with resident vanilla lease aliases | Spawn data remains WOC-owned; numeric reverse network lookup remains vanilla. |
| `HeroPreviewer._load_packages` / `MenuWorldPreviewer._load_packages` [hook] | Loads character-preview equipment packages | Borrow the vanilla lease and fall back only when `Application.can_get("unit", custom)` fails | Both classes are required because VT2 copy-inherits methods before mods load. |
| `HeroPreviewer._spawn_item` / `MenuWorldPreviewer._spawn_item` [hook] | Spawns and links inventory, lobby, and score/end-screen equipment | Apply the canonical transform to the exact spawned WOC unit | Weak per-unit guard bounds duplicate traversal; no per-frame writes. |
| `LootItemUnitPreviewer.load_package` / `spawn_units` / `_unload_packages` [hook] | Owns item, illusion, Athanor, and crafting-preview package leases and units | Borrow/unload one vanilla lease per custom key and transform returned WOC units | Never load the WOC unit path through PackageManager; the master package owns residency. |

### Blightreaper audio ownership (#633)

| Class.method (kind) | Vanilla behavior at the seam | Why WOC hooks it | Trap / invariant |
|---|---|---|---|
| `ActionInspect.client_owner_start_action` / `finish` [hook] | The cloned elf Sword uses `ActionTemplates.action_inspect`; start owns local first-person state and finish releases it [src: `scripts/settings/equipment/weapon_templates/1h_swords_wood_elf.lua:1290`; `scripts/unit_extensions/weapons/actions/action_inspect.lua:21-56`] | Start `nds_skull_inspect` only on the positively tracked local WOC 1P unit and stop its exact playing id on finish | The donor package is boot-loaded through `DLCSettings.geheimnisnacht_2021.package_name` [src: `scripts/settings/dlc_settings.lua:274-283`; `scripts/boot.lua:358-363`]. Missing package/API/unit fails closed; vanilla inspect is untouched. |
| `GearUtils.destroy_equipment` [hook] | Destroys wielded 1P/3P units during inventory teardown [src: `scripts/unit_extensions/default_player_unit/inventory/gear_utils.lua:348-370`] | Stop any WOC-owned inspect/probe playing id before its unit is destroyed | Sole WOC hook on this pair. Game-state exit, disable/unload, dead-unit detection, and an eight-second cap close the remaining lifecycle edges. |
| VMF `/woc_audio_probe` [explicit diagnostic] | `WwiseUtils.trigger_unit_event` creates an auto source attached to a unit and applies the sound environment [src: `scripts/helpers/wwise_utils.lua:13-57`] | Attempt `emitter_trophy_evil_sword` on the local 3P Blightreaper for at most eight seconds and three commands | The event belongs to level-scoped `wwise/level_hub`; mission residency is unproven. No force-load, automatic playback, or network traffic exists. Other peers are intentionally unaffected until a resident contract is proven. |

### Boss weapon catalogue (#642)

| Seam | Vanilla behavior | Why WOC reads it | Trap / invariant |
|---|---|---|---|
| `Breeds` + `InventoryConfigurations` + `Application.can_get` + VMF `/woc_boss_catalog` [read-only diagnostic] | A boss breed names its default inventory configuration; that configuration contains item categories whose entries carry concrete enemy `unit_name` paths [src: `scripts/settings/breeds/breed_chaos_exalted_champion.lua:49`; `scripts/settings/ai_inventory_templates.lua:690-700,2002-2008,2255-2266`] | Emit seven bounded `[WOC:642]` source rows plus one bounded authored-resource row per relic descriptor; report current source-unit residency and whether each exact mod-owned 1P/3P unit can be resolved | No spawn, force-load, item registration, lookup injection, or table mutation. Keep trophy props never enter the source facet. `resident_now=false` means unloaded, not absent. Rasknitt remains explicit `deferred_no_inventory` because his breed declares `has_inventory=false` [src: `scripts/settings/breeds/breed_skaven_grey_seer.lua:25`] |

## Subsystem notes (how the vanilla flow runs end-to-end, for WOC's cases)

Each note is the minimum needed to read the hooks above; the owning `docs/engine`
doc and `DEVELOPMENT.md` carry the full architecture.

### Item registration is direct table injection, not a hook (owner: `docs/engine/06`)

`_register_blightreaper` (`:230`) clones the base `es_1h_sword` `ItemMasterList`
entry via `_build_entry` (`:179`), hands it to
`MoreItemsLibrary:add_mod_items_to_local_backend`, then mirrors it into
`ItemMasterList[ITEM_KEY]` so vanilla equip/preview paths resolve it -
`HeroPreviewer.equip_item` does `ItemMasterList[item_name]` [src: engine], and the
missing-key `__index` on `ItemMasterList` throws, so the read/write both go through
`rawget`/direct assignment. The clone deliberately keeps the inherited
`entry.name` = `es_1h_sword` (clobbering it breaks the vanilla equip fallback
`ItemMasterList[item.name]`, the CWV clone-name lesson `feedback_cwv_clone_name_clobber`)
and strips `required_dlc = nil` (a new mod item reusing base-package meshes; the
per-career DLC gate is enforced by the game's own equip check - same intentional
strip as CWV `_build_entry`).

Native `parse_item_master_list` has already stamped that base row with both
`key` and `name` equal to `es_1h_sword` [src:
`scripts/settings/equipment/item_master_list.lua:109-112`]. MoreItemsLibrary's
backend conversion then selects `mod_data.key or item.key or default_item_name`
for both `ItemId` and `key` (`MoreItemsLibrary.lua:343-344`). WOC does not
override those `mod_data` fields, so the actual Blightreaper backend row is
vanilla-keyed even though its backend instance id and presentation are WOC-owned.
Runtime check `issue509_registered_blightreaper_wire_contract` asserts this
against the live backend mirror rather than relying only on static source.

Before MIL insertion, WOC builds its private combat template by deep-cloning
`we_one_hand_sword_template_1`. Vanilla has already attached canonical career
ability rows to that donor (`scripts/settings/equipment/weapons.lua:241-267`).
Deep cloning changes those rows' table identity, while
`_lib_career_weapon_actions` intentionally uses identity to detect conflicting
providers. WOC therefore restores an inherited row to the canonical
`ActionTemplates` object only when the donor itself is that exact object, then
claims it through the shared owner. Any other mismatch remains a hard deferred
registration gate. `issue690_blightreaper_registration_gate_contract` checks
the reconciliation, ownership, final gate state, and master-list row live.
Deferred registration is retried only at `StateInGameRunning.on_enter`; each
distinct gate is logged once through `printf` under a 12-line session budget.

MIL then unconditionally writes `backend_item.rarity` and
`backend_item.CustomData.rarity` to `default`. WOC deliberately repairs the
actual stored row to `cursed` after registration and stamps
`woc_unique_relic`; otherwise the native/CIM selectors would mistake the relic
for a Blacksmith template. `issue637_unique_immutable_relic_inventory` proves
one canonical row and zero removable/deferred duplicates at runtime.

### NetworkLookup append + the wire-safety consequence (owner: `docs/engine/03`)

Registration also appends `ITEM_KEY` into `NetworkLookup.item_names` as a local
index (`#tbl + 1`, `:264`), via `rawset` because the table has an error-throwing
`__index`. That append is per-peer and order-dependent, so the numeric id a
`woc_` key gets is not stable across peers - a host with WOC and a client without
it disagree, and the client's decode hits the strict `__index`
[src: `network_lookup.lua:2362`] -> CTD (issue 278 class). The `sync_loadout_slot`
hook (table above) is the defense-in-depth boundary: every marker-owned
Blightreaper row is substituted with a `BASE_WEAPON` + `promo` shadow before
encode. The shadow also clears `properties` and `traits`: both intrinsic rows
are WOC-local presentation over bonuses baked into the combat template, and
`LoadoutUtils.properties_to_rpc_params` would otherwise strict-index their keys
through a peer-local `NetworkLookup.properties` table (#654). `WOC` applies no
skin; the local `cursed` rarity never crosses this RPC
(`docs/engine/03` §31; project `project_vt2_cross_peer_wire_safety`).

### Held-mesh derivation and preview residency (owner: `docs/engine/06`)

`HELD_UNIT` is the WOC-owned `units/woc_blightreaper/blightreaper`, with an
explicit `_3p` sibling, so vanilla's 1P/3P derivation in `gear_utils.lua` remains
intact. Both units, their material, and their textures are static dependencies
of WOC's master resource package; no unit path is passed to PackageManager.

Vanilla previewers and `WeaponUtils.get_weapon_packages` nevertheless treat a
unit path as a globally discoverable package identity. `_woc_appearance_policy`
maps only those package requests to the matching Empire sword 1P/3P packages;
spawn data remains custom while `Application.can_get("unit", custom)` is true
and visibly falls back to the sword if master-bundle residency is missing.
`NetworkLookup.inventory_packages` receives only forward custom-name -> vanilla
index aliases; numeric reverse entries stay vanilla.

The ordinary loadout RPC remains `es_1h_sword` for non-WOC safety. A bounded
VMF same-mod sideband publishes one Blightreaper bit per loadout-sync edge.
WOC-capable receivers cache it by peer+slot and re-key `GearUtils` husk spawn to
the bundled unit; absent-WOC peers receive no custom resource identity.

## What the engine will NOT let us do (dead ends, already paid for)

Pulled from `DEVELOPMENT.md` (the duplicate-weapon crash post-mortem) and the
in-file header - do not re-discover these.

- **The keep-trophy diorama prop is NOT runtime-loadable as a weapon mesh.**
  `units/props/inn/hub_trophy/hub_trophy_bogenhafen` has no standalone `.package`,
  is absent from the boot-loaded `resource_packages/dlcs/bogenhafen` and base
  `resource_packages/levels/inn` bundles (verified with `vt2_bundle_unpacker`),
  and is loaded on-demand only by the keep-decoration system.
  `Managers.package:load` on its UNIT path HARD-CRASHED on keep entry - an engine
  `resource_package()` C-fatal that bypasses the surrounding `pcall` (confirmed
  Blightreaper v0.1.1-dev). The actual mission-placed sword was separately
  extracted and authored in v0.1.13-dev (its own `_3p` sibling + master-package
  residency); the diorama remains forbidden. General rule: never
  `Managers.package:load` a unit path, only a real `.package` NAME you have
  verified contains the unit (memory
  `reference_vt2_package_load_needs_package_not_unit_path`).
- **Enemy weapon meshes have no `_3p` sibling and use a different attach rig.**
  Meshes under `units/weapons/enemy/...` are a single model with no first-person
  variant, and attach via `AttachmentNodeLinking.ai_1h_weapon` on an enemy
  skeleton [src: `scripts/settings/ai_inventory_templates.lua`], not the player
  weapon attach system. The cloned player `template` supplies the player-side
  attach, but grip offset / scale / rotation almost always need tuning, applied on
  3P units only (memory `feedback_cross_char_transforms_3p_only`). The authored
  Blightreaper is an explicit exception: its reviewed canonical transform is
  shared by its separate 1P and 3P units.
- **A duplicate-item mod that copies the item layer but not the wire layer ships a
  latent non-peer CTD.** `WOC` reproduced CWV's `ItemMasterList` / MIL / display
  machinery yet omitted CWV's `sync_loadout_slot` net-safe hook; the result was
  issue 422 - a `woc_` id on the wire fataling every non-WOC peer at
  `network_lookup.lua:2362`. Wire safety is a mandatory, non-optional layer of the
  duplicate-item pattern, not a follow-up (`docs/engine/03` §31).
- **The keep display prop and the wieldable weapon share a name but are different
  units.** `Trophies.hub_trophy_*` [src: `scripts/settings/trophies.lua:46-81`]
  are posed statues/dioramas, NOT the weapon mesh; the wieldable artifact is the
  boss's enemy weapon `.unit` in `ai_inventory_templates.lua` (Nurgloth ->
  `wpn_chaos_sorcerer_scythe_01` at `:699`). Cloning the statue gets you a
  diorama, not a sword.

## #749 borrowed-renderer residency boundary

Blightreaper pulse application proves its donor material and complete texture
set, performs the source-backed material bind, then proves every live mesh
material handle before the first native texture write. Owner, husk, character
preview, and item preview all consume that one event-driven contract.

## Doc maintenance

Follows `docs/engine/README.md` maintenance rules: if a WOC hook moves, a guard is
added, or a cited vanilla line drifts after a game patch, edit the affected row in
the SAME commit. This doc complements, and must not duplicate, `DEVELOPMENT.md`
(the enemy-mesh catalog + full crash post-mortem) - when a new enemy weapon lands,
`DEVELOPMENT.md` is the primary and this doc gains rows only if the new item adds a
new engine seam (for example, a verified package-name load for a future enemy unit).
The load-bearing wire-safety citations (`loadout_utils.lua:25/72`,
`network_lookup.lua:2362`) were re-verified this pass. `StateInGameRunning.on_enter`
interior line is `[unverified]` (class + method grep-confirmed via the CWV
precedent; the exact decompile line was not pinned this pass) - replace when next
touched. Line numbers are against the 2026-07-12 decompile - match crash logs by
function name, not line. Section shape (hook table -> subsystem notes -> dead
ends) matches `character_weapon_variants/ENGINE_SURFACE.md`. Reverse index:
`docs/engine/README.md` "Per-mod surface docs".
