# character_weapon_variants - engine contact surface

What vanilla VT2/Stingray does at every seam `cwv` touches, and why the mod is
there. This is the per-mod companion to the subsystem set in `docs/engine/`
(read `docs/engine/README.md` for house style). It does **not** re-explain a
subsystem the engine docs own - it names the seam, cites the vanilla behavior,
and links out. Decompile paths are relative to
`C:\Users\danjo\source\repos\Vermintide-2-Source-Code`; `cwv` line numbers are
`character_weapon_variants.lua` unless a private owner module is named. `§N` = a `docs/BUG_CLASSES.md`
class; `#N` = a GitHub issue. Grep-verified 2026-07-11 against the decompile.

`cwv` is the highest engine-contact mod in the monorepo: it clones cross-character
base templates into brand-new MoreItemsLibrary items, so it has to intercept every
path that resolves an item to a mesh, a template, an animation event, a network id,
or a preview unit - on the owner, on the husk, in four preview surfaces, and across
the wire.

## Hook table

91 hook registrations, grouped below into 8 logical rows-of-concern. `[hook]` =
full wrapper (`mod:hook`, can rewrite args/returns); `[safe]` = `mod:hook_safe`
(post-callback, no override); `[tbl]` = table-form hook (plain-table target, nil-guarded).

### Items / gear / inventory spawn - owner path (owner doc: `docs/engine/06`)

| Class.method (kind) | Vanilla behavior at the seam | Why cwv hooks it | Trap / invariant |
|---|---|---|---|
| `GearUtils.create_equipment` [hook] `_cwv_world_equipment_owner.lua` | Builds the in-world equipment record and spawns 1p/3p units for a slot [src: `scripts/unit_extensions/default_player_unit/inventory/gear_utils.lua:7`] | Supply cwv variant's overrides and enroll the finished custom 3P units through the shared complete-snapshot FadeSystem adapter (#922) | Multi-return collapse (`docs/VMF_RECIPES.md` §2); career must come from `inventory_system._career_name`, not `player:owner()` (CLAUDE.md in-mission caveat); fade enrollment uses the player root and never a partial hand-only list |
| `GearUtils.spawn_inventory_unit` [hook] `:4741` | Spawns one hand's inventory unit from `item_template`+`item_units`, attaches `ammo_unit` if `ammo_data.ammo_hand` matches [src: `gear_utils.lua:155`] | Force cwv per-hand mesh + grip/scale on the spawned unit (`:4741`) | `ammo_unit` fassert: only mirror held mesh as ammo when `base.ammo_unit` exists (DEVELOPMENT "ammo_unit trap", #`2df233ae`) |
| `GearUtils.destroy_wielded` [hook] `:5152` | Destroys the currently-wielded unit on unwield/swap [src: `gear_utils.lua:332`] | Tear down cwv carrier visuals / linked pickups alongside the weapon (`:5152`) | - |
| `GearUtils.link_units` [hook] `:5543` | Attaches source->target units by `attachment_node_linking`, via `Unit.node` per link [src: `gear_utils.lua:293`] | Guard character-specific unwielded bones inherited from a cross-character clone (`:5543`) | `j_leftweaponattach` / `a_unwielded_brw_mace` class - missing node is an uncatchable fatal (`J_LEFTWEAPONATTACH_INVESTIGATION.md`; DEVELOPMENT "Attachment node linking") |
| `BackendUtils.get_item_units` [hook,tbl] | Resolves per-hand unit paths for an item: skin entry first, else `item_data` fallback; the husk calls it with `backend_id=nil`, wire skin, and career immediately before branching on the returned hand fields [src: `backend_utils.lua:144-208`; `simple_husk_inventory_extension.lua:662-670`] | Force cwv override mesh for backend-identified skinless owner/preview items; for a skinless unambiguous husk `(base,career)`, preselect the variant's authored hands before vanilla chooses which spawn calls exist (#478) | Fires for EVERY caller incl. all 4 previewers. Husk preselection requires no backend id, no skin, and shared resolver reason `base_career`; explicit skin/native/ambiguous pairs pass through. The later per-hand residency suppression remains the crash floor. |
| `BackendUtils.get_item_template` [hook,tbl] `:4367` | Resolves the `weapon_template` for an item id [src: `backend_utils.lua:136`] | Return the exact instance's selected Combat Style template before the existing Crowbill/Old Musket/CWV clone resolution (#620) | CONSOLIDATED table-form seam. Style templates and referenced power rows are registered immutable clones; never mutate or send the tables. Nil-guard the cold `_G.BackendUtils` vs post-LA ref. |

### Inventory extension - owner + husk (owner docs: `docs/engine/02`, `docs/engine/06`)

| Class.method (kind) | Vanilla behavior | Why cwv hooks it | Trap / invariant |
|---|---|---|---|
| `SimpleInventoryExtension.wield` [safe] `_cwv_cross_access.lua` | Sets the wielded slot, flips 1p/3p unit visibility, updates career/weapon state [src: `simple_inventory_extension.lua:627`] | Track local cross-access animation state, publish exact Sword+Mace cosmetics (#567), and publish the exact instance's Combat Style edge (#620) | CONSOLIDATED - `hook_safe` does not chain. Exact-pair/style publication is event-driven, not polled. Combat Style transitions preflight both hands, canonically interrupt weapon actions, and rebuild one slot through vanilla destroy/add/wield with rollback. |
| `WeaponUnitExtension.stop_action` [direct call] `_cwv_combat_styles.lua` | Finishes the current weapon action, its animation/audio/buffs, and clears action state [src: `scripts/unit_extensions/weapons/weapon_unit_extension.lua:661-740`] | End current light/heavy/charge/block/push actions before an explicit Combat Style switch (#944) | Call once per distinct active hand with reason `interrupted`, only after both hands pass preflight. Never cancel a career action; never persist or rebuild when interruption fails. Async styles interrupt only after their resource and exact-instance transaction are revalidated. |
| `SimpleInventoryExtension._wield_slot` [hook] `:5035` | Shows/hides the 1p/3p units for the slot being wielded [src: `simple_inventory_extension.lua:1926`] | Per-hand cwv fixups plus complete owner-side 3P fade enrollment at wield time (#922) | Self-owned class only - husk is a separate root (see husk rows); local third-person cameras expose this owner-only engine gap |
| `SimpleInventoryExtension.show_first_person_inventory` / `show_third_person_inventory` [safe] `:5106`/`:5118` | Toggles visibility of the equipped 1p / 3p units [src: `simple_inventory_extension.lua:917`] | Keep cwv scale/grip applied across 1p<->3p visibility flips (`:5106`) | - |
| `SimpleInventoryExtension.game_object_initialized` [hook] `_cwv_item_identity_transport_owner.lua` | First network broadcast of the loadout once the unit's GO id is ready, via `rpc_add_equipment` [src: `simple_inventory_extension.lua:249-282`] | Unconditionally null every CWV skin around the vanilla sender, publish schema-3 `cwv_item_identity`, and publish exact Sword+Mace state after the vanilla call (#396/#416/#483/#567/#579/#660/#741) | Same-mod presence is not numeric lookup parity. CWV skin indexes never ride vanilla equipment RPCs; exact string-key identity is authoritative. Identity retry is capped at eight attempts per peer/slot/fingerprint at 0.5-second cadence and stops only on a matching receiver acknowledgement. |
| `SimpleInventoryExtension._spawn_resynced_loadout` [hook] | Respawns and re-broadcasts one queued equipment slot [src: `simple_inventory_extension.lua:1429-1468`] | Same unconditional vanilla-wire skin fallback plus changed-slot semantic identity and exact Sword+Mace state on live resync (#396/#567/#741) | Exception-safe helper restores the owner's live skin after the send; native items clear stale ownership; exact-pair publication is transition-driven. |
| `SimpleHuskInventoryExtension._wield_slot` [hook] `:5189` | Husk-side wield: resolves the template, gets the unit table, then conditionally calls `spawn_inventory_unit` once per non-nil right/left field [src: `simple_husk_inventory_extension.lua:641,661-670`; `init` stores `extension_init_data.player` at `:5-36`] | Establish one synchronous peer+slot Combat Style context, apply exact appearance/stance state, then enroll the complete custom 3P snapshot after all CWV adapters finish (#620/#760/#914/#922) | CONSOLIDATED wrapper. Context is always cleared after vanilla returns/errors. The outer vanilla `wield` subsequently replaces the list from the same current inventory fields; Cosmetics separately owns post-replacement attachment composition. At spawn, exact identity first validates the extension's human `_player` and owner unit because `PlayerManager:owner` may not be populated yet; later paths fall back to the shared resolver. Readiness failures retry locally at 0.25 s for at most eight attempts; no network or per-frame unbounded replay (#786/#914). |
| `SimpleHuskInventoryExtension.start_weapon_fx` [hook] `:4595` | Plays weapon fx on the remote/husk view [src: `simple_husk_inventory_extension.lua:790`] | Suppress/redirect fx that reference a bone the cross-character husk lacks (`:4595`) | Husk class is a separate root from the owner - hooking one does not cover the other (CLAUDE.md "Self-owned vs husk") |
| `PlayerManager.remove_player` [hook] `_cwv_identity_peer_cleanup.lua` | Removes a player record on disconnect and during level transitions [src: `scripts/managers/player/player_manager.lua:407`] | On clients only, retire one departed remote human's exact CWV identity, pending delivery, accepted request, and recipient-specific dedupe routes after vanilla returns (#914) | Capture the human before vanilla removes it; skip local peer, bots, and servers. Never clear `others|slot` broadcast signatures or globally disable dedupe. This narrow cache is safe to clear on transitions because the bounded peer-ready request rehydrates it after local inventory becomes ready; persistent cosmetic state still follows the deferred-cleanup rule in `docs/BUG_CLASSES.md` class 24. |

### Weapon animation / spread / ammo (tangent to `docs/engine/10`)

Infantry Spear adds no hook. It deep-clones `two_handed_spears_elf_template_1`, scales only attack-bearing action time/profile fields, and supplies Kruber's 3P polearm stance through the existing network-bound remap seam [src: `spears_wood_elf.lua:1-4,1559`; `action_utils.lua:538-563`; `weapon_unit_extension.lua:627-655`]. Its visuals copy only `right_hand_unit` from the `es_deus_01` skin family; the shield field is intentionally absent [src: `weapon_skins_morris.lua:144-267`].

| Class.method (kind) | Vanilla behavior | Why cwv hooks it | Trap / invariant |
|---|---|---|---|
| `WeaponUnitExtension._play_3p_anim` [hook] `_cwv_cross_access.lua` | Resolves `event_3p`, encodes it through `NetworkLookup.anims`, sends the animation RPC, then fires the same event locally [src: `scripts/unit_extensions/weapons/weapon_unit_extension.lua:627-655`] | Substitute the receiver-career baked event (#398) or enabled dev-picker choice (#317) before vanilla encodes it, keeping owner and husks on one animation/audio timeline | Never defer this to `Unit.animation_event`: that call is after the RPC and therefore owner-local only. Picker choices must be receiver-closed-vocabulary and master-toggle gated; target must already exist in `NetworkLookup.anims`, else decline safely. |
| `ActionHandgun.client_owner_post_update` [hook] | Simulates the owning peer's handgun shot; only calls `play_hud_sound_event` when the action declares `fire_sound_event` [src: `scripts/unit_extensions/weapons/actions/action_handgun.lua:67,180-184`] | On the exact Old Musket hip/ADS shot edge, send its compiled rifle report through CWV's bounded presentation channel; observers trigger it on the owner husk (#474) | Do not add `fire_sound_event`: that duplicates owner-local compiled audio. `player_combat_weapon_rifle_fire` is not in `NetworkLookup.sound_events`, so it must not enter a native sound RPC. |
| VMF `cwv_old_musket_mode_v1` [network channel] | Mod-presence-only event transport; vanilla equipment wire identity remains `es_handgun` | Carries Old Musket owner/slot mode transitions, join/state queries, and exact remote shot edges (#474) | Schema-gated and positive backend-id-gated. Send only on toggle, wield, state enter, query reply, and completed shot; never per frame. |
| Weapon template `allowed_chain_actions` [table mutation] | While an action runs, `CharacterStateHelper._get_chain_action_data` considers only its authored chain; `WeaponUnitExtension:start_action` finishes a same-hand predecessor with `new_interupting_action` [src: `player_character_state_helper.lua:1069-1158`; `weapon_unit_extension.lua:336-430`] | Install one frame-zero `action_three` edge in every non-toggle Old Musket ranged/melee sub-action (#412) | Preserve native chains, deduplicate idempotently, use engine field `clear_buffer`, exclude the toggle itself, and add no transport; the existing mode edge remains the only remote state. |
| `HeroPreviewer._spawn_item` / `MenuWorldPreviewer._spawn_item` [post hooks] | Vanilla resolves preview template from inherited base item name and drops mutable stance data | Resolve exact backend-instance stance, compose the complete saved 3P transform, and replay the selected template's career-aware wield animation (#474/#760) | Consume cached state only for positively identified Old Musket or the exact Outrider item. Outrider uses one receiver-career-scoped `to_repeater_pistol` replay because mutating its shared `dr_deus_01` base would alter the genuine Trollhammer. Event availability and unit liveness are validated before dispatch; failure retains vanilla presentation. |
| `WeaponSpreadExtension.init` [safe] `:4240` / `update` [hook] `:4254` | Captures the spread template on spawn; recomputes spread each frame [src: `scripts/unit_extensions/weapons/spread/weapon_spread_extension.lua:7` / `:59`] | Patch spread data BEFORE vanilla's update runs for cwv ranged variants (full wrapper, `:4254`) | `update` must be `[hook]` not `[safe]` to land before vanilla reads it (`:4252` comment) |
| `GenericAmmoUserExtension.update` / `add_ammo` / `remove_ammo` / `add_ammo_to_reserve` / `instant_reload` / `refresh_buffs` / `reset` / `max_ammo` [hook] `_cwv_musket_ammo_pool.lua`; `SimpleInventoryExtension.add_ammo_from_pickup` [hook] | Native weapon units own independent chambers/reserves; reload completion and several public mutations write `_available_ammo` directly, while pickups visit every equipped ammo slot [src: `generic_ammo_user_extension.lua:145,345-410,504-584`; `simple_inventory_extension.lua:1253-1306`] | Give one player's primary/secondary Old Muskets separate chambers but one owner+slot-scoped reserve and native HUD/status values (#932) | Never key a gameplay pool only by extension or process. Never mutate `_max_ammo`; adapt its public query. Wrap the complete reserve-mutation set, preserve replacement state, unregister exact non-Musket slot replacements, and collapse one multi-slot pickup traversal to one pooled transaction. |

### Thrown-weapon projectiles + carried pickups (javelin / boar spear / throwing axe)

| Class.method (kind) | Vanilla behavior | Why cwv hooks it | Trap / invariant |
|---|---|---|---|
| `PlayerProjectileUnitExtension.init` [safe] `:6016` / `hit_level_unit` [safe] `:6082` / `_handle_linking` [hook] `:6112` / `_spawn_linked_pickup_projectile` [hook] `:6160` / `_spawn_pickup_projectile` [hook] `:6175` | Inits a fired/thrown projectile, resolves level-geometry impact, decides whether it links (sticks), and spawns the pickup it becomes [src: `scripts/unit_extensions/weapons/projectiles/player_projectile_unit_extension.lua:14`/`:948`/`:1161`/`:1327`/`:1362`] | Route cwv thrown-weapon variants through the pickup-projectile path so the thrown item is recoverable (`:6016`+) | Pickup-sampler total must stay `>= 1` (memory `reference_vt2_pickup_sampler_total_crash`); linked-pickup RPC overflow class (memory `reference_vt2_cw_boon_aoe_rpc_overflow_crash`) |
| `ActionThrownProjectile._fire` / `_use_ammo` [hook] | The owner action emits the projectile, then consumes one ammunition [src: `scripts/unit_extensions/weapons/actions/action_thrown_projectile.lua:117-137,165-190`] | With #424 exact thrown capability unproven, suppress an exact CWV Tuskgor Javelin before projectile creation and preserve its ammo; vanilla `we_javelin` passes | Identify through the action's OWN `self.item_name` **and** the live wielded slot's CWV backend/skin identity - the two disagree on a grenade-slot throw and across a mid-flight wield swap, and the slot read alone let those throws through. Never inherited `item_data.name == we_javelin`; emit one notice per blocked action object, not per frame. The gate is closed unless BOTH the presence beacon and the exact thrown catalog are proven |
| `ActionUtils.spawn_pickup_projectile` [hook] | Encodes husk, pickup, and item lookup ids before the regular/limited/explosive pickup-projectile RPC family [src: `scripts/helpers/action_utils.lua:455-527`] | Fail closed if the dormant grenade-slot Tuskgor Javelin reaches its separate drop sender without enabled capability | This is a distinct sender from projectile impact. It remains installed while the bomb feature is off so a future re-enable cannot bypass #424 |
| `ProjectileSystem._get_projectile_units_names` [hook] `:6200` | Resolves the projectile's unit + template names from `projectile_info` [src: `scripts/entity_system/systems/projectile/projectile_system.lua:159`] | UNCONDITIONALLY substitute the cwv thrown unit/template names for the proven vanilla donor (`:6200`); return nil when that donor cannot be proven | Husk has its own `_get_projectile_units_names` [src: `player_projectile_husk_extension.lua:727`] - cover both sides. The floor is never parity- or toggle-gated (memory `reference_vt2_wire_safety_never_toggle_gated`). Donor proof spans `NetworkLookup.projectile_units` + `husks` + the `ProjectileUnitsFromUnitName` inverse; "the key exists" is not proof. **Returning nil is only survivable because of the `spawn_player_projectile` preflight below** |
| `ProjectileSystem.spawn_player_projectile` [hook] `_cwv_javelin_gate.lua` | Resolves the weapon template action, then dereferences `projectile_units.projectile_unit_name` on the very next line with no nil contract [src: `scripts/entity_system/systems/projectile/projectile_system.lua:178`, `:247-249`] | #424 preflight: probe the already-hooked resolver for a cwv thrown item and refuse the native spawn when neither an exact row nor a proven vanilla donor resolves | Required by construction once donor revalidation can produce a DROP - without it the nil above is an engine-level fatal. Probe only for `is_cwv_javelin(item_name)`; a vanilla weapon must never pay the extra resolve. Sole cwv registration on this method (cwv also hooks `_get_projectile_units_names` and `rpc_spawn_pickup_projectile`) |
| `ProjectileSystem.rpc_spawn_pickup_projectile` [hook] `:6221` / `PickupSystem.rpc_spawn_linked_pickup` [hook] `:6206` | Receiver RPCs: spawn a (linked) pickup projectile from networked name ids [src: `projectile_system.lua:436` / `scripts/entity_system/systems/pickups/pickup_system.lua:1415`] | Decode cwv projectile/pickup ids that only exist as local appends on the sender (`:6221`) | RPC receivers ARE hookable (memory `reference_vt2_rpc_dispatch_dynamic_hookable`); modded `NetworkLookup` key CTDs a non-mod peer (`docs/engine/03`, §31) |
| `/cwv_smoke_bomb_probe` [command] `_cwv_smoke_bomb_probe.lua` | Ranger smoke is two separate systems: the explosion supplies stagger/FX/sound [src: `explosion_templates.lua:1005-1023`], while `bardin_ranger_activated_ability` spawns a shared 8 m `buff_aoe_unit`; `BuffExtension.add_buff` accepts `params.buff_area_position` [src: `talent_settings_bardin.lua:1038-1072`; `buff_extension.lua:362-382`] | #343 records whether the frag projectile, Ranger visual/template/buff assets, landing-position contract, and normalized grenade pool exist at runtime before another bomb-slot item is registered | Observation only, three explicit runs; no lookup/item/pool/buff/unit writes. Stock explosion scale is scalar, not an independent Z-axis effect transform, and the existing Tuskgor bomb-slot registration remains quarantined after its v0.1.352/.353 load-time content regression. |
| `ProjectileLinkerSystem.link_pickup` [hook] `:6347` | Links a pickup unit to a hit unit's node [src: `scripts/entity_system/systems/projectile/projectile_linker_system.lua:202`] | Guard bone lookups when the linked cwv pickup targets a foreign rig (`:6347`) | Same `Unit.node` fatal class as `link_units` |
| `OutlineSystem.outline_unit` [hook] `:6331` | Applies/removes the interaction outline on a unit [src: `scripts/entity_system/systems/outlines/outline_system.lua:637`] | Keep the recoverable thrown-weapon pickup outlined like vanilla ammo (`:6331`) | Signature is `(self, unit, flag, color, ...)` in vanilla - match arg names |
| `LimitedOwnedPickupUnitExtension` / `LifeTimePickupUnitExtension` / `PlayerTeleportingPickupExtension` `.extensions_ready` [safe] `:6339-6341` + `.destroy` [safe] `:6342-6344` | The three carrier-pickup extension classes (all `class(X, PickupUnitExtension)` [src: `pickup_system.lua:6-8`]); base `extensions_ready` [src: `scripts/unit_extensions/pickups/pickup_unit_extension.lua:54`], `destroy` [src: `:100`] | Attach/detach the carried thrown-weapon visual on whichever carrier extension the pickup uses (`_attach_carrier_visual`/`_detach_carrier_visual`) | Three separate root classes - must hook all three, exactly the self-owned-vs-husk pattern (CLAUDE.md) |

### UI / previewers (owner docs: `docs/engine/09`, `docs/engine/06`)

| Class.method (kind) | Vanilla behavior | Why cwv hooks it | Trap / invariant |
|---|---|---|---|
| `MenuWorldPreviewer.equip_item` [safe] `:2922` | Keep-inventory previewer equips an item into a preview slot (body copied from `HeroPreviewer.equip_item`) [src: `scripts/ui/views/world_hero_previewer.lua:649`] | Apply cwv grip/scale and default-mesh correction; for #567, rewrite a precomputed Sword+Mace recipe from the authoritative selected generated-skin row | Hook the DERIVED class, never the base - `class()` copies methods at load. `info.skin_name` is authoritative when the callback loses `skin`; exact pair hands are residency-gated before replacing `spawn_data`. |
| `HeroPreviewer._spawn_item` [hook] `:10973` + `MenuWorldPreviewer._spawn_item` [hook] `:10981` | Spawns a single preview unit for an item [src: `world_hero_previewer.lua:895` / `scripts/ui/views/menu_world_previewer.lua:635`] | Bridge grip via `info.spawn_data[1].slot_index` and force cwv mesh in preview (`:10973`) | Both hooked because the base copy and derived copy are independent post-load (CLAUDE.md); v0.1.84 numeric-key fix |
| `HeroWindowWeaveProperties._create_item_previewer` [hook] `_cwv_menu_preview_owner.lua` | Constructs, configures, and returns the Athanor properties pane's `LootItemUnitPreviewer`; its package/spawn work runs later from `post_update` [src: `scripts/ui/views/hero_view/windows/hero_window_weave_properties.lua:2947-2967`; `scripts/ui/views/hero_view/loot_item_unit_previewer.lua:230-243`] | Mark only the returned instance as `cim_preview` so the Old Musket appearance adapter can issue an exact retained-state receipt (#1155) | Full wrapper preserves every trailing argument (including CIM's `activate_spin` extension). Never infer CIM from item identity or relabel the shared previewer class; an unmarked instance remains `illusion_browser`. |
| `LootItemUnitPreviewer.spawn_units` [hook] `:13031` | Illusion/skin browser and CIM's Athanor selector spawn display units, writing `self._spawned_units` AFTER return via `_spawn_items` [src: `scripts/ui/views/hero_view/loot_item_unit_previewer.lua:538`, `:504`] | Pre-pass `_om._cwv_browser_meshswap_apply` rewrites base-mesh spawn_data to variant units (#419), then applies shared appearance and Old Musket's per-unit texture binding (#617); #1155 resolves the exact marked instance as `cim_preview` | MUST be `[hook]` not `[safe]` - `_spawned_units` is nil at safe-callback time. Old Musket painting first proves all texture resources and binds its resident vanilla 3P parent material; `pcall` alone cannot catch a Stingray texture/material access violation. `_load_item_units` rebinds item_data to the BASE IML entry (:254-255), so resolve against `self._item`; dual-rig `j_leftweaponattach` (see dead-ends). |
| `HeroWindowItemCustomization._setup_illusions` [hook] `:10931` | Builds the illusion grid for the selected item [src: `scripts/ui/views/hero_view/windows/hero_window_item_customization.lua:1518`] | Inject cwv cross-character illusions into the grid (`:10931`) | Console variant `HeroWindowCosmeticsLoadoutPoseInventoryConsole._setup_illusions` is a separate class if console support is added |
| `HeroWindowLoadout._populate_loadout` / `_handle_input` [hook] `_cwv_combat_styles.lua` | Populates selected equipment-slot presentations and handles loadout slot clicks [src: `hero_window_loadout.lua:213`/`:124`] | Show one contextual current-style button for supported exact instances and cycle it on release (#620) | Mutates the cached definitions table before window construction; no copied view. Unsupported items hide the control. The hotkey uses the same exact-instance transaction. |
| VMF `custom_gui_textures` renderer injections [data contract] | Loads a private atlas only into the explicitly named GUI renderers | Package nine paired Dual Axe inventory icons and publish their exact renderer/fallback capabilities through `_cwv_inventory_icons.lua` (#620); complete VMF's missing masked+saturated atlas field for the already-injected `ingame_ui` top renderer used by CIM (#787) | A packaged material is not globally resident. `hero_view_state_weave_forge` creates a separate preview renderer; it does not own the weapon-list draw. Each listed renderer is only a capability candidate: CIM still proves the exact material in the live Gui, and any failed proof uses the declared vanilla fallback before draw (#617). |
| `BackendInterfaceItemPlayfab.get_filtered_items` [hook] `:4180` | Returns backend items matching a filter for inventory/forge lists [src: `scripts/managers/backend_playfab/backend_interface_item_playfab.lua:627`] | Surface cwv variant items in the relevant lists and remove exact Tuskgor Javelins from the ranged picker while #424 capability is unproven | DLC ownership gate - filter unowned-DLC entries before surfacing (CLAUDE.md "DLC Ownership Gate"); hiding is presentation only, so the action sender gate must independently contain an already-equipped item |
| `BackendInterfaceCraftingPlayfab.get_unlocked_weapon_skins` [safe] `:9056` | Returns the unlocked-skin set the forge treats as available [src: `scripts/managers/backend_playfab/backend_interface_crafting_playfab.lua:138`] | Mark cwv custom skins unlocked so illusions appear (`:9056`) | Backing store is `PlayFabMirrorBase.get_unlocked_weapon_skins` [src: `playfab_mirror_base.lua:2233`] - never commit to PlayFab (`docs/engine/11`) |
| `_G.Localize` [hook] `:7234` | Global loc-key -> string lookup | Supply display names/descriptions for `cwv_*` keys and `item_type` labels (`:7234`) | VMF `_localization.lua` is NOT auto-registered into global `Localize` (`docs/VMF_RECIPES.md`); item_type leak class (DEVELOPMENT "Naming flow") |

### Packages / residency + Unit C-API guards + lifecycle

| Class.method (kind) | Vanilla behavior | Why cwv hooks it | Trap / invariant |
|---|---|---|---|
| `PackageManager.load` / `unload` / `has_loaded` [hook,tbl] `:5338`/`:5343`/`:5348`; direct lease `:4443` | Refcounted package load/unload/state query [src: `foundation/scripts/managers/package/package_manager.lua:20`/`:196`/`:286`] | Treat the bundled Old Musket units as resident; hold the source-derived vanilla Dual Axes FP state-machine package across CWV equip/resync (`:4443`, #586) | A wield-time state-machine miss C-fatals at `PlayerUnitFirstPerson.set_state_machine` [src: `scripts/unit_extensions/default_player_unit/player_unit_first_person.lua:165`]; the #586 lease is synchronous, unique-ref, idempotent, and symmetrically released. Do not queue arbitrary mod unit paths (issue #403). |
| `Unit.set_texture_for_materials` [C-API] | Writes a named texture slot across the materials bound to one spawned unit [src: `scripts/helpers/gear_utils.lua:150`] | Paint the custom Old Musket without mutating its shared compiled donor material (#617/#742) | `Application.can_get("texture", ...)` proves texture residency only. The native call dereferences the spawned unit's material handles and can access-violate at `0x8` before Lua `pcall` returns. First census every mesh through pcall-wrapped `Unit.num_meshes` / `Unit.mesh` / `Mesh.num_materials` / `Mesh.material`; any absent/empty/null `#ID[00000000]` binding skips the whole paint transaction. Never probe the crashifying `Material.num_parameters` family. |
| `Unit.node` / `has_node` / `flow_event` / `set_flow_variable` [hook] `:5459`/`:5466`/`:5481`/`:5490` | Engine C-API: node index lookup and flow-graph events on a unit; a missing node in `Unit.node` is an engine-level fatal, not a Lua error | Guard against missing bones / flow vars on cross-character rigs before the engine faults (`:5459`) | `Unit.node` errors bypass `pcall` - use `has_node` for existence (CLAUDE.md Lua quirks; J_LEFTWEAPONATTACH F2) |
| `StateInGameRunning.on_enter` [safe] `:9632` | Fires on entering keep/mission gameplay state [src: `scripts/game_state/state_ingame_running.lua:28`] | Run `_auto_register_all()` - backend is nil at mod init, ready here (`:9632`); rebuild custom skin associations (#567); then migrate retired style-only CIM UUIDs onto native items (#620) | Registration precedes migration. The pure migration planner validates every native target and matching skin before mutation; persistence failure rolls CIM rows back and remains retryable. |
| `DeusMechanism._setup_run` [hook] `_cwv_item_registration_owner.lua` | Builds Chaos Wastes starting-weapon identities immediately before the run reads `DeusStartingWeaponTypeMapping` | Install exact CWV Deus owners only when the shared parity gate's committed `applied_state()` is `enabled` (#1204); otherwise retain the resident vanilla fallback | The raw roster classifier can turn true during the two-second settle interval, before senders are allowed to use custom identity. Unknown, pending, disabled, or throwing committed-state accessors fail closed. The bounded `[cwv:273]` receipt includes the exact-state verdict. |
| `TransientPackageLoader.hot_join_sync` [hook] / `GameNetworkManager.set_peer_synchronizing` [hook] / `NetworkServer.is_network_state_fully_synced_for_peer` [hook] / `remove_peer` [safe] | During `PeerStates.Loading`, transient sync encodes tracked projectile/husk names as numeric ids; immediately before `GameSession.add_peer`, the network manager begins GameObject synchronization and checks the sync predicate; real leave removes the peer [src: `scripts/game_state/components/transient_package_loader.lua:175-209`; `scripts/network/peer_states.lua:232,383-393`; `scripts/network/network_server.lua:242`; `scripts/managers/network/game_network_manager.lua:814,830-836`] | #424 shadows CWV transient refs to proven vanilla ids, calls `require_peer` at the first sender, removes BOTH live custom recovery pickups and tracked in-flight projectiles before object replay, re-reads both trackers after the commit, holds a cleanup-failed peer outside `GameSession`, and on real leave retires the peer's proof on ALL THREE parity instances (presence + both exact channels) | Numeric lookup equality is never inferred from same-mod presence: the per-peer verdict requires a `peer_has` ack on the exact channel plus an undrifted local catalog. **Ref shadowing cannot rewrite an ALREADY-SPAWNED projectile GameObject** - `GameSession.add_peer` replays it after `set_peer_synchronizing` returns, which is why the in-flight tracker (`_tracked_projectiles.units`, populated at `transient_package_loader.lua:155`) is swept as part of the same transaction. A deletion that did not take must NOT report success. `remove_peer` is the ONLY registration on that pair and owns every per-peer teardown: the parity library expires an ack only after a bounded ABSENCE window, so a fast same-id rejoin would otherwise reuse a pre-disconnect exact proof. Never wait in either join hook; saved inventory/settings remain untouched |
| `WeaponSystem.send_rpc_attack_hit` [hook] `_cwv_exact_wire_runtime.lua` | Client->server attack RPC carrying a `NetworkLookup.damage_profiles` INDEX; the host decodes it strictly, with no `rawget` [src: `scripts/entity_system/systems/weapons/weapon_system.lua:148`, send `:182`, decode `:243`] | #423 sole choke point for the profile id: substitute an unproven `cwv_*` index for its recorded vanilla clone SOURCE, then vanilla `default`, and drop the hit if neither is provable | Sole cwv registration on `WeaponSystem` (any method), and it lives in the owner module - re-adding one in the entry file silently drops the second (NON-NEGOTIABLE 8). Substitution is a GAMEPLAY degradation, so it rides the exact catalog + committed `applied_state`; the `is_server` path never substitutes (the RPC runs in-process, `:179-180`). Every named RPC param is forwarded positionally with the tail on `...` (memory `reference_vmf_hook_drops_skip_sync_rpc_loop`) |
| `LoadoutUtils.sync_loadout_slot` [hook,tbl] `:10555` | Encodes an item as `rpc_sync_loadout_slot`, `item_id = NetworkLookup.item_names[item.key]` [src: `scripts/helpers/loadout_utils.lua:13`, id at `:25`] | Substitute a `base_weapon` shadow item so the cwv LOCAL-append id never desyncs a peer without the same append order (`:10555`, #278) | Plain table, table-form + nil guard; strict `__index` at [src: `network_lookup.lua:2521`] CTDs the decode; cross-peer wire-safety (`docs/engine/03`; project `project_vt2_cross_peer_wire_safety`) |
| `GearUtils.hot_join_sync` [hook] | Re-broadcasts a peer's equipment to a joining peer [src: `gear_utils.lua:462-495`] | Target the stable string-key identity to the joining peer, track its fingerprint for bounded acknowledgement retry, and unconditionally null the CWV skin around vanilla equipment replay (#396/#425/#474/#567/#579/#660/#741) | No parity callback may replay a numeric CWV skin. A peer without CWV receives only the vanilla base/`n/a`; a CWV peer reconstructs exact units locally after accepting semantic identity. |

### Same-mod network channels

| Channel | Payload | Purpose / safety |
|---|---|---|
| `cwv_item_identity` schema 3 | Semantic descriptor `{ slot, provider, item_key, base_item_key, skin_key, offhand_skin_key, fingerprint }`; acknowledgement sentinel `{ slot = "cwv_identity_ack", ack_slot, fingerprint }` | Carries provider-qualified exact identity for a vanilla-base equipment wire shape (#396/#579/#660/#741). Cosmetics contributes only its catalog-validated, committed offhand skin key; receivers reconstruct both hand-unit paths from local registries, validate schema/base/family/fingerprint, and acknowledge only after acceptance. Owner retry is peer+slot+fingerprint keyed, 0.5-second paced, and capped at eight attempts; wrong/stale acknowledgements do not clear it. Native/unavailable state fails closed, unit paths and numeric lookup indexes never cross this wire. |
| `cwv_exact_pair_state_v1` schema 1 | `{ owner_peer, slot, exact_skin }` | Carries the validated generated Sword+Mace skin only between CWV peers (#567). It never enters vanilla lookup tables, publishes only on lifecycle edges, and may cache until the remote husk exists. |
| `cwv_combat_style_v1` schema 1 | `{ op, slot, family_id, style_id }` | Carries only bounded known Combat Style state between CWV peers (#620/#645). Publishes on transition/wield/gameplay entry and direct hot-join query reply; a query reply never emits another query, and no template, backend id, custom lookup id, or per-frame pose crosses the wire. Reciprocal families resolve their template/resource/DLC/presentation/remap through the validated descriptor registry before this unchanged transport. |

## Subsystem notes (how the vanilla flow runs end-to-end, for cwv's cases)

Each note is the minimum needed to read the hooks above; the owning `docs/engine`
doc carries the full architecture.

### Item -> mesh resolution (owner: `docs/engine/06`)

The one mesh seam is `BackendUtils.get_item_units` [src: `backend_utils.lua:144`]:
it resolves per-hand units from the skin entry when a skin is applied, otherwise
from `item_data.right_hand_unit`. cwv variants inherit `entry.name`/`entry.key`
from their clone (kept deliberately, per `feedback_cwv_clone_name_clobber`), so the
fallback path can land on the BASE entry's mesh - hence the cwv override hook forces
the variant mesh when `result.skin` is empty and the `backend_id` matches
`cwv_<key>_NNN` (`:10485`). In-world spawning runs through `GearUtils.create_equipment`
[src: `gear_utils.lua:7`] -> `spawn_inventory_unit` [src: `:155`] -> `link_units`
[src: `:293`], the last of which is where a cross-character clone's inherited
`a_unwielded_*` bone name faults. See `docs/engine/06` for the four-render-path
coverage matrix.

### Owner vs husk inventory (owner: `docs/engine/02`, `docs/engine/06`)

`SimpleInventoryExtension` (local/authoritative) and `SimpleHuskInventoryExtension`
(remote view) are separate root classes with no inheritance - a hook on one never
fires for the other [src: `simple_inventory_extension.lua:627` vs
`simple_husk_inventory_extension.lua:314`]. The husk resolves the inherited BASE
`item_data`, so a cwv item shows as its base weapon on a remote player unless the
husk `_wield_slot` hook re-keys mesh+transform off base+career (`:4634`, #392).
Because the husk mesh is spawned during hot-join before the skeleton is guaranteed
ready, every `Unit.node`-adjacent access must go through `has_node` first.

### Network lookups / RPC (owner: `docs/engine/03`)

cwv registers its item and skin keys into `NetworkLookup.item_names` /
`NetworkLookup.weapon_skins` as local index-appends (`#tbl + 1`), so a given key's
numeric id depends on which other mods appended before cwv on THAT peer (notably
Loremaster's Armoury clone entries, appended only where LA is enabled). A host
with LA and a client without it disagree on the id, and the receiver's decode hits
the strict error `__index` [src: `network_lookup.lua:2521`] -> client CTD (#278).
The fix substitutes a boot-stable `base_weapon` shadow before the encode on all
three live-slot senders (`game_object_initialized`, `_spawn_resynced_loadout`,
`LoadoutUtils.sync_loadout_slot`) plus the always-nulled hot-join replay. Wire
safety is unconditional, never behind a toggle (`docs/engine/03`, §31; memory
`reference_vt2_wire_safety_never_toggle_gated`).

### Previewers (owner: `docs/engine/09`)

Four preview surfaces resolve items differently. The keep inventory previewer is
`MenuWorldPreviewer`, whose methods are copies of `HeroPreviewer` taken at class
definition [src: `class.lua:51-57`] - so cwv hooks the derived class, and where a
method exists on both it hooks both (`_spawn_item` at `:10973`/`:10981`). The
illusion browser is `LootItemUnitPreviewer`; its `spawn_units` writes
`_spawned_units` only AFTER returning [src: `loot_item_unit_previewer.lua:504`,
`:538`], forcing a full `[hook]` wrapper. Grip offset bridges the string-keyed
`_item_info_by_slot` to the numeric-keyed `_equipment_units` via
`info.spawn_data[1].slot_index`. All three ride `BackendUtils.get_item_units`, so
the cwv mesh override there covers preview too (which is also why the dual-rig
crash below was so hard to isolate). A selected illusion is already recorded in
`info.skin_name`; that stored value outranks a nil post-hook argument and prevents
the default variant mesh correction from clobbering vanilla's selected spawn data.

### Packages / residency (owner: `docs/engine/05`)

Cross-character variants can also resolve a first-person state machine absent
from the receiver's native loadout. Vanilla adds that resource in
`WeaponUtils.get_weapon_packages` [src: `scripts/helpers/weapon_utils.lua:48-111`],
but `ProfileSynchronizer.profile_packages` derives its list from the backend
loadout visible at that instant [src:
`scripts/game_state/components/profile_synchronizer.lua:71-175`]. A later CWV
resync may therefore wield a different template against the stale package list.
Issue #586 holds the exact vanilla `.../melee/dual_axes` resource under one CWV
reference before wield; acquisition is synchronous because
`SimpleInventoryExtension._wield_slot` immediately calls
`PlayerUnitFirstPerson.set_state_machine` [src:
`simple_inventory_extension.lua:2096-2102`], whose engine blend-base-layer call
cannot be protected by `pcall` [src: `player_unit_first_person.lua:165-173`].
The lease remains stable across loadout/character changes and is released by
`on_disabled` / `on_unload`, then reacquired by `on_enabled`; gameplay-state
entry supplies an idempotent retry if PackageManager was cold at chunk load. See
`docs/engine/05` for the refcount + shutdown-leak model (#282).

## What the engine will NOT let us do (dead ends, already paid for)

Pulled from `DEVELOPMENT.md` and `J_LEFTWEAPONATTACH_INVESTIGATION.md` - do not
re-discover these.

- **No new animation clips.** System B can only pick from clips the target
  skeleton's state machine already authors; there is no path to ship animation
  files from a Workshop mod (DEVELOPMENT "Hard limits"). When Kruber's body lacks
  any clip for the donor's motion, the best available is the closest in-SM clip.
- **No per-career sub-action anim on a shared template.** The engine reads
  `anim_event_3p` directly with no career context [src:
  `weapon_unit_extension.lua:512`]. For cross-access on a vanilla item you cannot
  fix the foreign wielder without changing the native wielder, so the only options
  are a per-career variant item (System B) or the network-bound
  `WeaponUnitExtension._play_3p_anim` hook (`:1618`). Mutating the shared vanilla template's per-action
  events is wrong (DEVELOPMENT "cross-access").
- **No cross-sub-graph clip grafting.** Firing `to_<other_sm>` as
  `pre_action_anim_event` to borrow a clip from a foreign SM sub-graph does not
  cleanly route a single action - two reproducible failure modes (the switch clip
  eats the damage window; `anim_end_event_condition_func` strands the body in the
  new sub-graph). Confirmed v0.1.89 (DEVELOPMENT "Reaching clips that live in a
  different SM sub-graph"). Use the wield-commit pattern or accept the in-SM clip.
- **`force3p exists=true` is not proof a clip plays.** `Unit.has_animation_event`
  returns true whenever the master SM knows the name; the destination state in the
  current sub-graph may be a stub that animates nothing. Only visible motion counts
  (DEVELOPMENT "Discovery commands").
- **Display-rig node schema is invisible to Lua.** The `j_leftweaponattach`
  requirement only surfaces at runtime when the previewer's `Unit.node` lookup runs
  against the spawned `display_unit`. Single-sword rigs author only
  `j_rightweaponattach`; dual-wield variants must use a dual-attach rig
  (`display_dual_weapons` etc.) set on BOTH the `WeaponSkins.skins` and
  `ItemMasterList` skin entries, or the picker crashes on open/click
  (`J_LEFTWEAPONATTACH_INVESTIGATION.md`, ~20 versions to isolate).
- **`BackendUtils.get_item_units` cannot see its caller.** No clean way to
  distinguish "in-game equip" from "cosmetic picker" without fragile thread-local
  or stack-inspection hacks - a mirror there leaks across contexts. The durable fix
  is to populate the skin/IML entries correctly so no runtime mirror is needed
  (J_LEFTWEAPONATTACH L4).
- **The previewer reads the BASE template, not the cwv clone.** The character
  previewer resolves `ItemHelper.get_template_by_item_name(item_name)` on the
  inherited base name, so per-career wield poses and hand-attachment fields set on
  the clone are ignored - they must ALSO be patched onto the base template, scoped
  to cwv careers so vanilla wielders fall through (DEVELOPMENT "BASE template
  patching", crash `c847908d`).

## #749 borrowed-renderer residency boundary

Old Musket preview/owner/husk painting now delegates texture-set and spawned-unit
material closure to `_lib_resource_residency.lua` V2 after its source-backed
preview parent bind. The generic `_lib_weapon_appearance` texture seam remains
censused as legacy rather than being falsely claimed covered.

## #1155 Old Musket appearance pilot

Old Musket is the first family routed through the immutable appearance descriptor
and bounded reconciler. `BackendUtils.get_item_units` remains the unit-selection
seam, while `GearUtils.create_equipment`, owner/husk wield, peer-ready replay,
inventory/illusion previews, the exactly marked CIM Athanor preview, lobby
preview, and score-team preview submit the
resulting live unit to `_cwv_old_musket_appearance.lua`. The adapter owns the only
model/material/texture/pose recipe; each lifecycle token permits at most two
attempts and is accepted only after an independent local position, scale,
quaternion, and material-handle readback. Unsupported surface/edge cells retain
the vanilla handgun explicitly. State exit, mod disable, and unload disconnect the
weak target ledger; dev tuning advances descriptor generation and replays tracked
units once rather than polling per frame.

## Doc maintenance

Follows `docs/engine/README.md` maintenance rules: if a cwv hook moves, a guard is
added, or a cited vanilla line drifts after a game patch, edit the affected row in
the SAME commit. Line numbers are against the 2026-07-11 decompile - match crash
logs by function name, not line. This doc is the template for the other mods'
`ENGINE_SURFACE.md`; keep the section shape (hook table -> subsystem notes ->
dead ends) stable.
