# Engine reference 06 - Items, gear, skins and husk inventory

**Scope:** `ItemMasterList` (incl. DLC lists), backend item resolution, `GearUtils`
spawn paths (own-1p / own-3p / husk-3p / bots), `SimpleInventoryExtension` vs
`SimpleHuskInventoryExtension`, weapon skins / illusions, attachments (hats,
attached units), the previewer surfaces, and the full cwv / cosmetics_tweaker /
weapon_tweaker display pipeline across every render surface. Written to feed the
issue #474 formal display-process review.

**Citation convention:** vanilla paths are relative to
`C:\Users\danjo\source\repos\Vermintide-2-Source-Code`; our paths are relative to
the monorepo root. Anything not cited is marked `[unverified]`.

**Companion docs (normative, read alongside):**
`docs/WEAPON_APPEARANCE_STANDARD.md` (the four-render-path contract, concern x
path matrix, sync contract), `docs/BUG_CLASSES.md` (crash classes referenced
below), `docs/CROSS_MOD_ARCHITECTURE.md` (LA bridge dispatch).

---

## 1. Architecture map

### 1.1 Vanilla - data layer

| File / symbol | Single responsibility |
|---|---|
| `scripts/settings/equipment/item_master_list.lua` | Root of the item database. Requires the local/exported/weapon_skins/test/steam/weapon_poses sub-lists (`:41-46`) then every DLC list via `DLCUtils.require_list("item_master_list_file_names", true)` (`:47`). Post-processes: applies queued `UpdateItemMasterList` can_wield patches (`:49-61`), builds `SteamitemdefidToMasterList` (`:63-75`), resolves `matching_item_key` can_wield sharing + hat/rune preview envs + `MagicItemByUnlockName` + frame display_unit defaults (`:79-105`), then `parse_item_master_list()` stamps `item.key = item.name = key` and localizes display names (`:109-129`). Finally installs a STRICT metatable: unknown key -> `Crashify.print_exception` via `__index` (`:131-137`). |
| `CanWieldAllItemTemplates` | The career list meaning "wieldable by everyone"; `UpdateItemMasterList(item_names, career_name)` queues per-career can_wield insertions and also appends the career to this list (`item_master_list.lua:7-39`). This is the vanilla-sanctioned mod entry point for expanding wieldability (used for DLC careers; wt mutates `can_wield` directly instead, which is equivalent post-boot). |
| DLC item lists | `scripts/settings/equipment/item_master_list_*.lua` (anvil, belakor, carousel, cosmetics_20xx_qN, karak, morris, scorpion, weapon_skins, ...) and `scripts/settings/dlcs/<dlc>/item_master_list_<dlc>.lua` (lake, bless, cog, woods, shovel, divine, morris_2024/2025, gotwf*, skulls_*, geheimnisnacht_*, anniversary_*, versus_rewards). All merge into the single global `ItemMasterList`. The lake list is where `es_questingknight` Bretonnian items live. |
| `scripts/settings/equipment/weapon_skins.lua` | `WeaponSkins.skins` is authored as an ARRAY of `{name, data}` records (`:7`) and re-keyed to a name->data map at `:7773-7784`; DLC skin files load after via `DLCUtils.require_list("weapon_skins_file_names")` (`:7786`). Also owns `WeaponSkins.skin_combinations` (`:6411`, rarity-tiered skin tables per weapon family), `WeaponSkins.default_skins` (`:7716`), `item_has_skin_table` (`:7788`), `is_matching_skin` (`:7800`), and the lazily built reverse map `matching_weapon_skin_item_key` (`:7824-7866`). A skin entry may carry `right_hand_unit`/`left_hand_unit`, `ammo_unit`, `ammo_unit_3p`, `material_settings_name`, `hud_icon`, per-career `*_hand_unit_override`, `template` (e.g. `weapon_skins.lua:35-47` for a runed axe with `material_settings_name = "blue_glow"`). |
| `scripts/settings/equipment/attachments.lua` | `Attachments` - the item templates for hats/trophies/skins-as-attachments (display_unit, `attachment_node_linking` selected from `AttachmentNodeLinking`, `slots` list) (`:26-78`). Also `FirstPersonAttachments` per-race 1P mesh (`:5-25`). Requires `scripts/settings/attachment_node_linking.lua` (`:3`). |
| `scripts/settings/equipment/cosmetics.lua` | `Cosmetics` - templates for skin-type cosmetics; third fallback in template resolution (see 1.2). [unverified beyond its use at backend_interface_item_playfab.lua:885] |
| `scripts/settings/equipment/weapons.lua` + `weapon_templates/` | `Weapons` (weapon templates: actions, attachment node linking per hand/perspective, wield anims, ammo_data). Resolved via `WeaponUtils.get_weapon_template`. |
| `scripts/network_lookup/network_lookup.lua` | `NetworkLookup.item_names` (`:250`) and `NetworkLookup.weapon_skins` (`:2215`) - the boot-time-frozen wire encodings for equipment RPCs. Strict `__index` on missing key (`:2362`) = instant CTD on decode of an index the peer never registered. THE reason for every wire-substitution hook we ship (BUG_CLASSES 31). |

### 1.2 Vanilla - backend resolution layer

| File / symbol | Single responsibility |
|---|---|
| `scripts/managers/backend/backend_utils.lua` | Stateless dispatch helpers. `get_loadout_item_id` / `set_loadout_item` route through `Managers.backend:get_loadout_interface_by_slot` (`:14-28`); `get_loadout_item` resolves id -> backend item (`:30-46`); `get_item_from_masterlist(backend_id)` clones master data + stamps backend_id (`:63-74`); `get_item_template(item_data, backend_id)` defers to the items interface (`:136-142`); **`get_item_units(item_data, backend_id, skin, career_name)`** (`:144-215`) is THE single mesh-resolution function - see 2.2. |
| `scripts/managers/backend_playfab/backend_interface_item_playfab.lua` | The "items" interface. `get_item_from_id` (`:384-389`), `get_skin(backend_id)` -> `item.skin` (`:344-348`), `get_item_masterlist_data` -> `item.data` (`:350-356`), `get_item_template` resolves `item_data.temporary_template or item_data.template` through `Weapons` -> `Attachments` -> `Cosmetics` in that order, fasserts if none match (`:871-892`). |
| `scripts/helpers/cosmetic_utils.lua` | `CosmeticUtils` - PLAIN TABLE. Cosmetic slot classification (`:104-116`), name/id <-> NetworkLookup translation (`:156-228`), **`update_cosmetic_slot(player, slot, item_name, skin_name)`** writes `player:set_data(slot, id)` + `set_data(slot.."_skin", id)` sync-data (`:230-252`), `get_cosmetic_slot` reads it back (`:254+`). This is the cross-peer cosmetic-state channel (hats, skins, weapon skin visible on husks' claw logic etc.). |
| `scripts/helpers/attachment_utils.lua` | `AttachmentUtils` - PLAIN TABLE. `create_attachment` spawns + links hat/skin attachment units (`:5`), `create_weapon_visual_attachment` (`:47`) spawns a template's attached units, `hot_join_sync` re-sends `rpc_create_attachment` per worn slot to a joining peer (`:81`). |

### 1.3 Vanilla - spawn / runtime layer

| File / class | Single responsibility |
|---|---|
| `scripts/unit_extensions/default_player_unit/inventory/gear_utils.lua` | `GearUtils` - PLAIN TABLE of spawn/destroy primitives. **`create_equipment`** (`:7-105`) - owner/bot path: resolves template + units, spawns both hands, builds the `slot_data` record (`:82-102`: `right_unit_3p/right_unit_1p/left_*/ammo_*`, `skin`, `item_template`). **`spawn_inventory_unit`** (`:155-277`) - the per-hand unit spawner used by BOTH owner (via create_equipment) and husk (directly): spawns `<unit>_3p` with `weapon_unit_3p` extension template, links via node-linking table, applies `material_settings_name` (`:195-199`); only when `owner_unit_1p` is non-nil does it also spawn the 1P unit with ammo/spread/overcharge extensions (`:201-274`). `apply_material_settings` (`:107-153`) writes color/matrix/scalar/vector/**texture** material variables per a `MaterialSettingsTemplates` entry. `link/link_units` (`:288-309`) - `Unit.node` on named nodes (ENGINE-FATAL if missing), `World.link_unit`. `unlink` (`:311`), `destroy_wielded` (`:332-339`, fires `lua_unwield` flow + mark_for_deletion), `destroy_equipment` (`:348-395`), `destroy_slot` (`:397-458`), **`hot_join_sync`** (`:462-514`) - re-sends `rpc_add_equipment` (item + skin ids, `:481-486`) + wield + additional-slot RPCs to a joining peer. `create_attached_particles` / `destroy_attached_particles` (`:669-723`). |
| `scripts/unit_extensions/default_player_unit/inventory/simple_inventory_extension.lua` | `SimpleInventoryExtension` - the OWNER-side (local player AND bot) inventory. See lifecycle 2.1. Key methods: `init` (`:16-70`, sets `_career_name` at `:47` BEFORE extensions_ready - the safe career source for spawn-time hooks), `extensions_ready` (`:92-209`, initial equip + default wield), `add_equipment_by_category` (`:375-447`, backend loadout -> add_equipment), `add_equipment` (`:858-891`, calls `GearUtils.create_equipment`, then `CosmeticUtils.update_cosmetic_slot` `:880`, `LoadoutUtils.sync_loadout_slot` `:885`, equip buffs), `game_object_initialized` (`:249-292`, broadcasts `rpc_add_equipment` per slot with `NetworkLookup.weapon_skins[slot_data.skin or "n/a"]` `:259` + `rpc_wield_equipment`), `wield`/`_wield_slot` (`:627`, `:1926-2163`: unwield flow events + visibility, wield anims incl. `wield_anim_career_3p`, 1P/3P unit bookkeeping), `create_equipment_in_slot` (`:1372-1427`, mid-session re-equip from backend id) -> `_queue_item_spawn` (`:1429`) -> `_spawn_resynced_loadout` (`:1443-1473`, re-broadcasts `rpc_add_equipment` WITH the slot skin `:1451`), `show_first_person_inventory` (`:917-978`, also swaps `first_person_attached_units` vs `third_person_attached_units` `:965-969`), `show_third_person_inventory` (`:1014`), `destroy` (`:449`). |
| `scripts/unit_extensions/default_player_unit/inventory/simple_husk_inventory_extension.lua` | `SimpleHuskInventoryExtension` - the REMOTE-view inventory. **Separate root class, no inheritance from the owner class** (BUG_CLASSES 5). `add_equipment(slot_name, item_name, skin_name)` stores `ItemMasterList[item_name]` + skin, spawns NOTHING (`:185-222`). `wield` (`:314-367`) -> `_wield_slot` (`:641-784`): `GearUtils.destroy_equipment` then re-resolves `BackendUtils.get_item_units(item_data, nil, slot.skin, self._career_name)` (`:662`) and calls `GearUtils.spawn_inventory_unit` per hand with `unit_1p = nil` (`:666`, `:670`) - so husks re-spawn the wielded weapon ON EVERY WIELD and only ever have 3P units. Applies 3P wield anim (`wield_anim_career_3p`, `:709-724`), skin `animation_variation_id` (`:738-745`), sets `equipment.wielded_slot` at `:775`. `start_weapon_fx` (`:790-801`) indexes `equipment.slots[equipment.wielded_slot]` UNGUARDED - the #280 CTD when a wield bailed early. `_spawn_attached_units` (`:380-394`) via `AttachmentUtils.create_weapon_visual_attachment`. `show_third_person_inventory` (`:471-548`). `hot_join_sync` (`:578`) -> `GearUtils.hot_join_sync`. |
| `scripts/entity_system/systems/inventory/inventory_system.lua` | `InventorySystem` - the RPC hub. `rpc_add_equipment` receive: server relays to other clients (`:283-287`), decodes slot/item/skin via NetworkLookup (`:298-300`, the class-31 decode site) and calls the unit's `inventory_system` extension `add_equipment(slot, item, skin)` (`:306`). Also `rpc_wield_equipment`, `rpc_destroy_slot` (`:193`), `rpc_give_equipment` (`:207`), `rpc_add_inventory_slot_item` (`:310`), equipment-buff RPCs (`:342-364`), limited items (`:366`). |
| `scripts/unit_extensions/default_player_unit/attachment/player_unit_attachment_extension.lua` | `PlayerUnitAttachmentExtension` - owner-side hats/trinkets/skins. `game_object_initialized` (`:55`) broadcasts `rpc_create_attachment` reading `NetworkLookup.item_names[...]` INLINE (no function seam - cosmetics pre-mutates slot data around the call, see 3), `create_attachment_in_slot` (`:241`), `spawn_resynced_loadout` (`:295`). |

### 1.4 Vanilla - preview surfaces

| File / class | Single responsibility |
|---|---|
| `scripts/ui/views/world_hero_previewer.lua` | `HeroPreviewer` - BASE class of the character preview. **`equip_item(item_name, slot, backend_id, skin, skip_wield_anim)`** (`:649-786`): resolves `BackendUtils.get_item_units(item_data, backend_id, skin, self._current_career_name)` (`:675`), precomputes a `spawn_data` recipe per hand - `unit_name = <hand_unit> .. "_3p"` (`:697`, `:721`), `slot_index`, `unit_attachment_node_linking` from the weapon template's `.third_person` (`:687`, `:714`), `material_settings_name` (`:683`) - stores it STRING-keyed in `_item_info_by_slot[item_slot_type]` (`:776-782`), queues package loads. After load, `_spawn_item` -> `_spawn_item_unit` (`:1050`) spawns via `World.spawn_unit` from the recipe. `_equipment_units` is NUMERIC-keyed by `slot_index`. Hats spawn from `item_units.unit` + `item_template.attachment_node_linking` (`:739-764`). |
| `scripts/ui/views/menu_world_previewer.lua` | `MenuWorldPreviewer` - the DERIVED class actually instantiated by the keep inventory / character select / store. Class copy at definition time means hooks on HeroPreviewer never fire here (CLAUDE.md "HOOK THE DERIVED CLASS"; `foundation/scripts/util/class.lua:51-57` [as cited in weapon_tweaker.lua:5947-5957]). Own `_spawn_item` (`:635`), `_spawn_item_unit` (`:643`, fires once per unit, NO hand indicator). |
| `scripts/ui/views/hero_view/loot_item_unit_previewer.lua` | `LootItemUnitPreviewer` - illusion/skin browser + loot pane. `_load_item_units` (`:246`) calls `BackendUtils.get_item_units(item_data, backend_id, item_skin, self._career_name_override)` (`:270`), appends left-then-right spawn entries; `_spawn_items` (`:504`) calls `spawn_units` (`:538`) and assigns `self._spawned_units = units` only AFTER it returns (`:532`) - hence the mandatory full-wrapper hook rule. |
| `scripts/ui/views/hero_view/windows/hero_window_item_customization.lua` | Illusion picker window. `_setup_illusions` populates from `item_data.skin_combination_table` + appends `WeaponSkins.default_skins[item_key]` (`:1586` [as cited in character_weapon_variants.lua:10646-10656]); `_spawn_item_unit` (`:1384`) is its own preview spawner. |

### 1.5 Our modules (display-relevant)

| Module | Responsibility | Key sites |
|---|---|---|
| cwv `character_weapon_variants.lua` | Variant item registration (MoreItemsLibrary clones keeping `entry.name/key = base_weapon`), the `WA` WeaponAppearance transform module, per-path applies, husk re-key, wire safety. | WA module `:9913-9981`; four-path map comment `:9884-9893` |
| cwv `_lib_peer_parity.lua` | Copied shared lib: VMF-network presence beacon gating gameplay axes that cannot be wire-substituted (BUG_CLASSES 31). Master at `tools/shared_lib/_lib_peer_parity.lua`. | `character_weapon_variants/scripts/mods/character_weapon_variants/_lib_peer_parity.lua:1-50` |
| cosmetics `cosmetics_tweaker.lua` + `_la_bridge.lua`, `_la_persistence.lua`, `_material_hijack_embedded.lua`, `_moreitemslibrary_embedded.lua` | Custom illusions, LA (Loremaster's Armoury) clone bridge + per-peer husk cosmetic cache, glow system, per-path paints/scales/offsets, wire safety for LA/custom skin keys. | see 3.2 |
| wt `weapon_tweaker.lua` | Cross-character access (`can_wield` mutation), per-career unit overrides, in-game + preview 3P mesh swaps (brace->repeater, longbow->crossbow, repeating pistol->handgun, hammer+book), attachment-node crash guards, preview scale/offset/wield-pose. | see 3.2 |

---

## 2. Lifecycle and data flow

### 2.1 Owner (local player and bots) - spawn to despawn

1. `PlayerBot`/spawn code builds `extension_init_data.initial_inventory` from `GameModeManager.get_initial_inventory` (`scripts/managers/game_mode/game_mode_manager.lua:543`; bot: `scripts/managers/player/player_bot.lua:130-189`).
2. `SimpleInventoryExtension.init` stores profile, career (`:47`), initial inventory (`:48`).
3. `extensions_ready` (`simple_inventory_extension.lua:92-209`): `add_equipment_by_category("weapon_slots")` etc. Each slot resolves `BackendUtils.get_loadout_item(career, slot, is_bot)` (`:384`) - i.e. the PlayFab-backed loadout, item cloned with backend_id (`:390-392`) - else falls back to `initial_inventory[slot_name]` master key (`:386`, `:394`). `slot_to_use` career-skill overrides copy hand units from the overriding slot (`:423-442`). Then `add_equipment` -> **`GearUtils.create_equipment`** (`:874`).
4. `GearUtils.create_equipment` resolves `BackendUtils.get_item_template` + **`get_item_units`** (`gear_utils.lua:9-10`), spawns per hand via `spawn_inventory_unit`, hides all fresh units (`:20-54`), returns `slot_data` incl. `skin = item_units.skin` (`:87`).
5. Back in `add_equipment`: `CosmeticUtils.update_cosmetic_slot` publishes the slot + skin to player sync-data (`:880`); `LoadoutUtils.sync_loadout_slot` broadcasts the loadout-panel item (`:885`); equip buffs apply (`:888-890`).
6. `extensions_ready` wields `profile.default_wielded_slot` via `_wield_slot` (`:176`) and spawns `first_person_attached_units` (`:181`).
7. **`game_object_initialized`** (`:249-292`): for every slot, encodes `NetworkLookup.item_names[item_data.name]` + `NetworkLookup.weapon_skins[slot_data.skin or "n/a"]` and sends `rpc_add_equipment` to all peers (server: `send_rpc_clients` `:262`; client: `send_rpc_server` `:264` and the server relays at `inventory_system.lua:283-287`). Then `rpc_wield_equipment` (`:280-282`).
8. Wield cycle: `wield` -> `_wield_slot` (`:1926+`) - flow events + `Unit.set_unit_visibility` on old units, pointer-swap `equipment.right_hand_wielded_unit*` to the slot's persistent units (owner units are spawned ONCE per add_equipment and toggled; contrast husk). 3P anim via `wield_anim_career_3p` (`:2008-2014`).
9. Mid-session re-equip (hero view keep equip): `create_equipment_in_slot(slot, backend_id)` (`:1372`) -> `destroy_slot` -> `_queue_item_spawn(slot, item_data, item_units.skin)` (`:1408`) -> next update `_spawn_resynced_loadout` (`:1443`) **re-broadcasts `rpc_add_equipment` including the skin id** (`:1451-1457`) then `add_equipment` + `wield`.
10. Hot-join: server-side `hot_join_sync` per unit -> `GearUtils.hot_join_sync` (`gear_utils.lua:462-514`) re-encodes item + skin per slot (`:481-486`) for the joining channel.
11. Despawn: `destroy` -> drop checks + `GearUtils.destroy_equipment` / `destroy_slot`.

### 2.2 The single mesh-resolution function - `BackendUtils.get_item_units`

`backend_utils.lua:144-215`, resolution order:
1. Start with `item_data.left/right_hand_unit`, `ammo_unit`, `ammo_unit_3p`, projectile/pickup templates (`:145-152`).
2. Per-career override: `item_data.<hand>_hand_unit_override[career_name]` wins (`:159-162`).
3. Skin: if `backend_id` given and no explicit skin, `backend_items:get_skin(backend_id)` (`:164-169`); if a skin resolves, the skin template REPLACES all unit fields + `material_settings_name` + icon and sets `skin_name` (`:171-183`), then skin-level per-career override applies (`:185-188`).
4. Returns the units table with `skin = skin_name` (`:205`) - `result.skin` non-nil is the reliable "an illusion took effect" signal.

Every render surface calls this function: owner (`gear_utils.lua:10`), husk (`simple_husk_inventory_extension.lua:662` per wield, plus `add_equipment` career-skill path `:204`), inventory preview (`world_hero_previewer.lua:675`), illusion browser (`loot_item_unit_previewer.lua:270`). **It is the one true data seam for mesh + material-settings overrides** - anything placed on the entry or skin template propagates to all four paths for free.

### 2.3 Husk (remote view) - what actually reaches other screens

1. Owner's `rpc_add_equipment` arrives; `InventorySystem.rpc_add_equipment` decodes name + skin from NetworkLookup (`inventory_system.lua:298-304`) and calls `SimpleHuskInventoryExtension.add_equipment(slot, item_name, skin_name)` (`:306`).
2. The husk stores `ItemMasterList[item_name]` - **the BASE master entry, never the owner's backend item**: no backend_id, no traits, no cwv identity (`simple_husk_inventory_extension.lua:186`). Only `slot.skin` carries any cosmetic identity across the wire. This is BUG_CLASSES 27 / issue #392.
3. `rpc_wield_equipment` -> `wield` -> `_wield_slot`: destroys ALL husk equipment units then re-spawns only the wielded slot's 3P units via `GearUtils.spawn_inventory_unit(world, hand, ..., unit_1p=nil, unit_3p=husk_body)` (`:658-671`). **Husk weapon units are transient - re-created on every weapon swap** (owner units persist per slot). Any per-unit runtime mutation (scale, texture) must therefore re-apply on every husk wield.
4. `_wield_slot` sets `equipment.wielded_slot` only on success (`:775`); `wield` then runs `start_weapon_fx` (`:363`) which indexes `equipment.slots[equipment.wielded_slot]` unguarded (`:790-801`) - nil slot = CTD (#280).
5. Ammo display: husk ammo count comes from GameSession fields (`:58-73`); ammo 3P mesh spawns from `ammo_unit_name_3p or ammo_unit_name .. "_3p"` (`gear_utils.lua:169`).
6. Hats/skins on the husk body ride the ATTACHMENT system + `player:set_data` cosmetic sync (`cosmetic_utils.lua:230-252`; consumed e.g. at `simple_husk_inventory_extension.lua:337-351` for the packmaster claw skin variant), NOT the weapon-equipment RPC.

### 2.4 Preview surfaces

- **Inventory character preview** (keep hero view): `MenuWorldPreviewer` instance. `equip_item` builds `spawn_data` from `get_item_units` (with the true backend_id + skin - full illusion resolution), loads packages, then `_spawn_item`/`_spawn_item_unit` spawn `World.spawn_unit(unit_name)` directly from the recipe. It does NOT route through GearUtils - the recipe (`spawn_data[i].unit_name`, `.unit_attachment_node_linking`, `.material_settings_name`) is the only mutation point (`world_hero_previewer.lua:697-733`).
- **Illusion browser / crafting pane**: `LootItemUnitPreviewer._load_item_units` -> `spawn_units`; same get_item_units resolution (`:270`); spawn order left then right.
- Both previewers append `_3p` to hand units - preview mannequins are 3P-style renders; 1P units never appear on any preview surface.

### 2.5 Skins / illusions identity flow

- Applying an illusion writes `item.skin` on the backend item (PlayFab mirror); `get_item_units` picks it up via `get_skin(backend_id)` (`backend_interface_item_playfab.lua:344-348`).
- On the wire the skin travels ONLY as `NetworkLookup.weapon_skins[skin_name]` inside `rpc_add_equipment` (3 sender sites: `simple_inventory_extension.lua:259-264`, `:1451-1457`, `gear_utils.lua:484-486`) and in `CosmeticUtils.update_cosmetic_slot` sync-data (`cosmetic_utils.lua:244-250`).
- 1P skin anim variation: `_wield_slot` sets `animation_variation_id` from `WeaponSkins.skins[skin].action_anim_overrides` (husk: `simple_husk_inventory_extension.lua:738-745`; own: [unverified, same pattern expected in `simple_inventory_extension.lua:2069+`]).

---

## 3. Hookable seams

### 3.1 Vanilla seams, safe pattern, traps

| Seam | Fires for | Safe pattern | Traps |
|---|---|---|---|
| `BackendUtils.get_item_units` | ALL four render paths + pickup/projectile resolution | Full wrapper, capture the single return table, mutate fields, return it. Table-form hook + nil guard is the repo doctrine (cosmetics_tweaker.lua:4040-4045); NOTE: VMF string-form actually resolves plain global tables via `rawget(_G, name)` with delayed retry (`Vermintide Mod Framework/scripts/mods/vmf/modules/core/hooks.lua:46-58`, `:379-389`), so the real risk is registration-time nil + the LA clone-backend re-dispatch (docs/CROSS_MOD_ARCHITECTURE.md), not string-vs-table per se. | Multi-caller: gate carefully (cosmetics uses a husk-wield context flag, 3.2). `result.skin` non-nil = illusion won; do not stomp it (cwv:10341). |
| `BackendUtils.get_item_template` | template lookup on every equip/wield | Wrapper returning a substitute template (cwv musket stance, cwv:3938-3976). | Husk resolves the BASE entry's template - template-level overrides never reach remote views (#392, cwv:4619-4625). |
| `GearUtils.create_equipment` | Path 1 only (owner + bots) | Full wrapper; post-call the returned `slot_data` exposes all 8 hand/ammo unit handles. | Never fires for husks (BUG_CLASSES 5). `career_name` (arg 13) can arrive nil if ANY earlier wrapper in the cross-mod chain drops it - name every parameter (BUG_CLASSES 19 analog; wt:3712-3749 carries a recovery fallback reading `inventory_system._career_name`). Do not use `Managers.player:owner(unit_3p)` for career at mission-spawn timing (nil; CLAUDE.md, WEAPON_APPEARANCE_STANDARD 1). |
| `GearUtils.spawn_inventory_unit` | Path 1 (via create_equipment) AND Path 2 (husk, direct) | Full wrapper; discriminator `owner_unit_1p == nil` = husk/3P-only spawn (cwv:4759-4764). Capture all four returns `w3p, a3p, w1p, a1p` (BUG_CLASSES 2). Pre-call mutation of `item_units` re-keys the mesh (cwv:10154-10172); post-call transforms apply to returned units. | Husk re-fires on EVERY wield - all applies must be idempotent (cwv WA offset guard, cwv:9921-9931). One hook per mod - wt consolidated its two swaps into one hook (weapon_tweaker.lua:5495-5506). |
| `GearUtils.link_units` | every attachment link, all paths | Full wrapper filtering entries whose named node is missing via `Unit.has_node` (wt:4697-4711, cwv:5526-5548). | `Unit.node` missing-node error is ENGINE-FATAL, bypasses pcall (DEVELOPMENT.md quirks; cwv:5528-5532). This is the universal choke point - `GearUtils.link` calls through the table (`gear_utils.lua:290`), so a table hook intercepts every spawn path. |
| `GearUtils.destroy_wielded` | owner + husk weapon teardown | Pre-call cleanup of anything you linked to the unit (cwv bayonet, cwv:5150-5162). | Runs before `mark_for_deletion`; the unit is still alive - read `Unit.get_data` here, not after. |
| `GearUtils.hot_join_sync` | server-side, per joining peer | Wrapper; substitute wire-unsafe names/skins on slot_data around the call. | **Currently UNHOOKED by cwv/cosmetics - see 5 item 1.** |
| `SimpleInventoryExtension.game_object_initialized` | owner unit go-live | Wrapper that nulls custom skin keys on slot_data, calls through, restores (cosmetics `_wire_null_custom_skins` cosmetics_tweaker.lua:6075-6103; cwv:10424-10447). Preserve up to 4 returns. | The null must be UNCONDITIONAL - never toggle-gated (BUG_CLASSES 31; regression test `wire_skin_null_ungated` cosmetics_tweaker.lua:10467+). |
| `SimpleInventoryExtension._wield_slot` | owner wield | Full wrapper for pre/post work (cwv reload-exploit + bayonet sync, cwv:5033-5094). | Separate class from husk `_wield_slot` - different signature `(self, equipment, slot_data, unit_1p, unit_3p, buff_extension)` vs husk `(self, world, equipment, slot_name, unit_1p, unit_3p)`. Hook both when the concern is both-sided (BUG_CLASSES 5). |
| `SimpleHuskInventoryExtension._wield_slot` | every husk weapon swap | String-form hook (VMF delays until class load - table-form gated on a boot-time rawget silently never registered, cosmetics_tweaker.lua:7988-7994). Set a context flag around the vanilla call for downstream `get_item_units` hooks (cosmetics:7995-8032). | ALWAYS delegate to vanilla - an early bail leaves `wielded_slot` nil and vanilla `wield` then nil-indexes at `simple_husk_inventory_extension.lua:540` (cosmetics v0.9.2 regression, cosmetics:8033-8042). |
| `SimpleHuskInventoryExtension.start_weapon_fx` | husk fx | Guard wrapper: no-op when `equipment.slots[wielded_slot]` is nil (#280; cwv:4595-4611). | The vanilla body is unguarded (`:790-801`). |
| `SimpleInventoryExtension.show_first/third_person_inventory` | 1P/3P camera + visibility flips | `hook_safe` post-pass to mirror visibility onto hand-linked child units (cwv:5104-5145). | `World.link_unit` does NOT propagate visibility to children (cwv:5096-5103). Vanilla re-shows ammo 3P units here - runtime hides must re-apply (cwv:5127-5144). |
| `MenuWorldPreviewer.equip_item` | inventory preview, BEFORE spawn | `hook_safe` (or full hook) mutating `self._item_info_by_slot[slot.type].spawn_data[i].unit_name` / `.unit_attachment_node_linking` (wt:5964-6113; cosmetics:5310-5339). | HOOK THE DERIVED CLASS - HeroPreviewer hooks never fire on the keep previewer (wt:5947-5957). Swapping unit_name to a mesh with different rig requires substituting the whole `.third_person` linking table from the TARGET template (wt:6035-6060) or nodes fatal. Fires twice per equip - keyed assignment is idempotent. |
| `MenuWorldPreviewer._spawn_item` / `HeroPreviewer._spawn_item` | preview, AFTER spawn recipe | Full wrapper; post-call apply transforms via the `_item_info_by_slot` -> `spawn_data[1].slot_index` -> `_equipment_units[slot_index].left/right` bridge (cwv `_cwv_spawn_item_post`, cwv:10531-10641; cosmetics `_spawn_item_post`, cosmetics:5355-5440). | STRING-keyed `_item_info_by_slot` vs NUMERIC-keyed `_equipment_units` (CLAUDE.md; cwv:10550-10563). `item_name` here is the BASE key for cwv clones. |
| `MenuWorldPreviewer._spawn_item_unit` | per-unit preview spawn | Full wrapper: PRE-validate `attachment_node_linking` against the body, POST scale/offset (wt:6184-6209; cosmetics `_spawn_item_unit_combined`, cosmetics:9398-9418). | No hand indicator - never use for per-hand ops (WEAPON_APPEARANCE_STANDARD 1). |
| `LootItemUnitPreviewer.spawn_units` | illusion browser | MUST be `mod:hook` full wrapper reading the returned units array (left=1, right=2) - `_spawned_units` is assigned only after return (`loot_item_unit_previewer.lua:532`; cwv:10735-10747, cosmetics:5554). | `hook_safe` reads nil (CLAUDE.md; burned twice). |
| `CosmeticUtils.update_cosmetic_slot` / `LoadoutUtils.sync_loadout_slot` / `AttachmentUtils.hot_join_sync` / `PlayerUnitAttachmentExtension.game_object_initialized` | cosmetic + loadout wire | Substitute mod-local keys with the vanilla equivalent before the call (cosmetics:5814+, :8491; cwv:10381-10408); for INLINE NetworkLookup reads, pre-mutate slot data around the vanilla call and restore (cosmetics:6105-6139). | All are PLAIN TABLES (table-form + nil guard per repo doctrine). Never skip the local apply - substitute only what rides the wire. |
| `BackendUtils.set_loadout_item` / items-interface `get_loadout` / `get_loadout_item_id` | loadout persistence | Cache-and-substitute for keys PlayFab cannot store (cosmetics:5671-5745). | `get_loadout_item_id(career, slot, is_bot)` - FORWARD `is_bot` or every bot resolves the host's loadout (cosmetics:5726-5737, wt v0.12.115). |

### 3.2 Our display features - seam and surface coverage matrix

Surfaces: **1** owner in-world (1P + own 3P, keep + mission, incl. bots), **2** husk 3P (other players' screens), **3** inventory character preview, **4** illusion browser.

| Feature | Mod | Seam(s) hooked | 1 own-1P | 1 own-3P / bots | 2 husk | 3 preview | 4 browser |
|---|---|---|---|---|---|---|---|
| cwv transforms (scale/offset/rotation, per hand per perspective) | cwv | `GearUtils.create_equipment` (cwv:10457-10499) ; `GearUtils.spawn_inventory_unit` husk branch -> `_husk_apply_cwv_transform` (cwv:4774-4786, 10216-10277) ; previewers `_spawn_item` (cwv:10719-10733) ; `LootItemUnitPreviewer.spawn_units` (cwv:10747) - all through `WA` (cwv:9913-9981) | yes (unless `scale_3p_only`, cwv:10492) | yes | partial - only when def resolves: skin/backend positive signal or unambiguous non-native base+career re-key (cwv:10231-10243); NATIVE-wieldable bases (musket/es_handgun) decline -> no transform on clients (issue #474 symptom 3) | yes | yes |
| cwv mesh override (variant unit paths) | cwv | data level: `_build_entry` writes entry unit fields + `BackendUtils.get_item_units` hook forces def units when no skin applied (cwv:10311-10348) ; husk pre-spawn re-key `_husk_rekey_units` (cwv:4750-4752, 10154-10172) ; preview swap via `equip_item`-recipe mutation (`_cwv_preview_meshswap_apply` [WEAPON_APPEARANCE_STANDARD 4.1], v0.1.370) ; browser resolves upstream via the shared get_item_units hook (#419) | yes | yes | partial - resident vanilla overrides on non-native (base, career) pairs only; custom meshes + native bases fall to BASE mesh (issue #474 symptom 1) | yes (pending verify #237) | yes (upstream) |
| cwv residency (force-load override 3P units) | cwv | boot pass `_force_load_husk_override_units` (cwv:4536-4567), guard predicate `_om._resident_override_3p` shared with re-key + preview (#418) | n/a | covered (runs on host too, #415 note) | yes (every peer) | n/a (preview world resident) | n/a |
| cwv ammo strip (`no_ammo_unit`) | cwv | data level on entry (path 1) ; husk strip `_husk_strip_cwv_ammo` (cwv:4778-4780, 10176-10205) | data | data | yes (career-set gated) | - | - |
| cwv musket bayonet (linked child unit) | cwv | `spawn_inventory_unit` attach (cwv:4839+), `destroy_wielded` detach (cwv:5150), `_wield_slot` + `show_first/third_person_inventory` visibility sync (cwv:5033-5145), orphan prune | yes | yes | **no husk bayonet** (husk resolves base handgun; #392) | via `_cwv_spawn_item_post` musket block (cwv:10592-10634) | [unverified] |
| cwv Old Musket textures / FX proxy / stance transforms | cwv | `spawn_inventory_unit` gated on `cwv_es_musket_old` backend_id (cwv:4814-4836) ; preview inline `Material.set_texture` triples (cwv:10600-10628) | yes | yes | **no** (backend_id absent on husk) | yes | #227 red/transparent (texture set not applied on this path) |
| cwv wire safety (skin + loadout axes) | cwv | `game_object_initialized` skin-null (cwv:10424-10447) ; `LoadoutUtils.sync_loadout_slot` base-key shadow (cwv:10381-10408) | n/a | n/a | send-side only; hot_join/resync senders uncovered (see 5.1) | n/a | n/a |
| cosmetics per-weapon scale ("thiccc") + grip offsets + glow | cosmetics | `create_equipment` post (`_scale_units`/`_offset_units`/`_apply_glow_override`, cosmetics:5225-5254) ; preview `_spawn_item_post` scale by `spawn_data.unit_name` truth source (cosmetics:5399-5439) ; glow template injection `spawn_inventory_unit` (cosmetics:4967-4985, currently inert) ; browser `spawn_units` (cosmetics:5554) | yes | yes | glow: peer-broadcast + hot-join replay (cosmetics:7936-7968); scale/offset: `spawn_inventory_unit` husk branch [unverified coverage] | yes | yes |
| cosmetics LA offhand/illusion mesh + paint | cosmetics + `_la_bridge` | own: `create_equipment` -> `_apply_la_offhand_to_units` (cosmetics:5242) ; husk: `_wield_slot` context wrapper (cosmetics:7995-8032) + `get_item_units` mesh swap from `_la_equips_by_peer` cache (cosmetics:4064-4160) ; preview: `equip_item` + `_spawn_item` wrappers (cosmetics:5310-5456) ; browser: `load_package` short-circuit + `spawn_units` (cosmetics:5499, 5554) ; per-instance persistence `_la_persistence` | yes | yes | yes for peers running cosmetics + LA (cache fed by `cos_la_apply` RPC; vanilla peers see vanilla substitute) | yes | yes |
| cosmetics LA wire safety | cosmetics | `CosmeticUtils.update_cosmetic_slot` (cosmetics:5814), `game_object_initialized` (cosmetics:6095), PUAE/AttachmentUtils pre-mutation (cosmetics:6105-6139, 8491), `set_loadout_item` cache (cosmetics:5671) | n/a | n/a | substitution shipped for cosmetic axes | n/a | n/a |
| wt cross-char 3P mesh swaps (brace->repeater, longbow->crossbow, rep-pistol->handgun, hammer+book hide) | wt | in-game: `spawn_inventory_unit` consolidated hook (wt:5315; spawn-new-unit-then-delete-vanilla pattern wt:5430-5493) ; preview: `MenuWorldPreviewer.equip_item` hook_safe recipe mutation (wt:5964-6148) | 1P untouched by design (universal) | yes | yes (swap runs on husk spawns; visibility bug fixed v0.12.38, wt:5462-5476) | yes | intentionally NOT covered (wt:3700-3702) |
| wt per-weapon scale/offset/wield-pose | wt | `create_equipment` (wt:3712) ; preview `_spawn_item_unit` post (wt:6184-6209+) | yes | yes | [unverified - grip offsets are re-applied per-frame for owner per `reference_wt_grip_offset_oneshot_stomped_durable`; husk coverage unclear] | yes | no (by decision) |
| wt attachment-node crash guards | wt | `GearUtils.link_units` table hook (wt:4697-4711) ; preview `_spawn_item_unit` PRE-validate (wt:6184-6189) | yes (all paths through GearUtils.link) | yes | yes | yes | yes |

---

## 4. Traps and crash classes

Cross-referenced to `docs/BUG_CLASSES.md`:

1. **Husk resolves BASE item_data (BUG_CLASSES 27 / #392).** The equipment wire carries only `NetworkLookup.item_names[item_data.name]` + a weapon_skin id (`simple_inventory_extension.lua:258-264`); cwv clones keep `entry.name = base_weapon`, so no husk-side hook can see the variant identity unless a skin survived the sync or the (base, career) pair is non-native-unambiguous (cwv:10065-10113). Native-wieldable bases (issue #474's musket on Kruber) are unreachable by construction - only the per-wearer marker (#392 Phase 3, ride `_lib_peer_parity`-style VMF network) closes them.
2. **Modded NetworkLookup index on a vanilla RPC = remote CTD (BUG_CLASSES 31).** Strict `__index` at `network_lookup.lua:2362`. Sender-side substitution must be unconditional, never toggle-gated. Known senders of skin/name ids: `game_object_initialized` (covered), `_spawn_resynced_loadout` (`simple_inventory_extension.lua:1451-1457`, NOT covered), `GearUtils.hot_join_sync` (`gear_utils.lua:481-486`, NOT covered), `CosmeticUtils.update_cosmetic_slot` (covered), `LoadoutUtils.sync_loadout_slot` (covered), PUAE/AttachmentUtils attachment RPCs (covered).
3. **Self-owned vs husk class split (BUG_CLASSES 5).** `SimpleInventoryExtension` and `SimpleHuskInventoryExtension` share no code; `GearUtils.create_equipment` never runs for husks; `spawn_inventory_unit` runs for both with `owner_unit_1p == nil` as the husk/bot-3P discriminator (`gear_utils.lua:176`, `simple_husk_inventory_extension.lua:666-670`).
4. **Husk wield re-spawns everything.** `_wield_slot` destroys + re-spawns per wield (`simple_husk_inventory_extension.lua:658-671`) - per-unit mutations must be idempotent AND re-applied every wield; unit handles cached across wields are dead.
5. **`Unit.node` engine-fatal (uncatchable).** Any linking table naming a node the spawned unit lacks kills the process through `GearUtils.link_units` (`gear_utils.lua:297-298`) or previewer link paths. Guard with `Unit.has_node` filters (wt:4677-4711, cwv:5526-5548). pcall does NOT catch it.
6. **Preview class copy.** Hooks on `HeroPreviewer` never fire on the keep previewer (`MenuWorldPreviewer` copies methods at class-definition time). Hook the derived class; hooking both is harmless (CLAUDE.md; wt:5947-5957).
7. **Preview key-space split.** `_item_info_by_slot` string-keyed, `_equipment_units` numeric; bridge via `spawn_data[1].slot_index` (cwv:10550-10566).
8. **`LootItemUnitPreviewer.spawn_units` hook_safe reads nil** - `_spawned_units` assigned after return (`loot_item_unit_previewer.lua:532`).
9. **Guard-that-bails husk wield = downstream nil-index CTD** (`equipment.slots[wielded_slot]` at `simple_husk_inventory_extension.lua:540`, `start_weapon_fx` at `:790`) - always delegate to vanilla, add the fx guard instead (#280; cwv:4595-4611, cosmetics:8033-8042).
10. **Strict `ItemMasterList` / NetworkLookup metatables (BUG_CLASSES 4).** Cold reads of unknown keys raise; use `rawget` + nil-check (`item_master_list.lua:131-137`).
11. **Hook wrapper multi-return collapse (BUG_CLASSES 2).** `spawn_inventory_unit` returns 4 values, `get_item_units` 1 table but other gear fns return 2-3; capture all before transforming.
12. **Package/residency.** A husk 3P spawn of a non-resident unit is an async engine fatal (BUG_CLASSES 28); force-load override units on EVERY peer at boot and gate spawn-time swaps on `has_loaded` (cwv:4536-4567; WEAPON_APPEARANCE_STANDARD 4.5).
13. **career_name drops through the hook chain** on `create_equipment` (wt crash dumps show non-nil at wrapped frames, nil at the vanilla frame) -> per-career unit override at `backend_utils.lua:159-162` silently skipped -> non-preloaded base mesh spawn -> engine fatal (wt:3691-3749). Every wrapper must name and forward all 13 params.
14. **Bot loadout `is_bot` drop.** `get_loadout_item_id(career, slot, is_bot)` - dropping arg 4 makes every bot clone the host's gear (cosmetics:5726-5737).
15. **`Material.set_texture` mutates the SHARED material asset** - leaks onto every unit using it; banned in favor of `Unit.set_texture_for_materials` / `GearUtils.apply_material_settings` (WEAPON_APPEARANCE_STANDARD 4.3; #420, #199 class).

---

## 5. Implications for our mods - concrete improvements

Ordered by severity. Each names our code, the engine-idiomatic alternative, and the citation.

### 5.1 P0 - wire skin-null covers 1 of 3 vanilla senders

`_wire_null_custom_skins` (cosmetics_tweaker.lua:6075-6103) and cwv's twin (character_weapon_variants.lua:10424-10447) null custom skin keys ONLY around `SimpleInventoryExtension.game_object_initialized`, then RESTORE the custom key onto `slot_data.skin`. But vanilla encodes `NetworkLookup.weapon_skins[slot_data.skin]` on two more sender paths that read the RESTORED value:
- `GearUtils.hot_join_sync` (`gear_utils.lua:481-486`) - fires when a peer late-joins while a modded HOST wears a custom illusion / cwv skin;
- `SimpleInventoryExtension._spawn_resynced_loadout` (`simple_inventory_extension.lua:1449-1457`) - fires on every keep/mission re-equip via `create_equipment_in_slot` (`:1408` passes `item_units.skin`).

A vanilla (or differently-registered) peer cold-decodes the appended index -> class-31 CTD - the exact crash the game_object_initialized null was shipped to kill. Engine-idiomatic fix: apply the SAME null-and-restore helper around `SimpleInventoryExtension.hot_join_sync` (`:1108`) and `_spawn_resynced_loadout`, or null `equipment_to_spawn.skin` inside a `_queue_item_spawn` wrapper. The shared helper already exists and is regression-tested (`wire_skin_null_ungated`, cosmetics:10467).

### 5.2 P1 - #474 root cause: native-wieldable bases are unreachable on husks by design

The husk re-key/transform resolver deliberately declines any (base, career) pair the career can natively wield (cwv:10080-10105) - correct as a never-corrupt guard, but it means `cwv_es_musket` (base `es_handgun`, native on Kruber careers) can NEVER render its mesh, transforms, or bayonet on other players' screens, matching #474 symptoms 1 and 3 exactly. The engine offers no data seam that survives the wire (2.3); the fix is the per-wearer variant marker over VMF mod-to-mod network (absence-safe by construction, `_lib_peer_parity.lua:26-33` pattern), consumed in the existing `spawn_inventory_unit` husk branch (cwv:4750-4786) as a higher-priority signal than base+career. Until it ships, no cross-char variant on a native-wieldable base may claim husk parity (WEAPON_APPEARANCE_STANDARD 5).

### 5.3 P1 - Old Musket textures fight the engine; `material_settings_name` does this on all four paths for free

cwv binds musket textures with raw `Material.set_texture` loops per path (preview: character_weapon_variants.lua:10600-10628; owner: `_apply_old_musket_textures` via cwv:4820-4821) - the banned shared-asset primitive (#420), and the browser path is broken (#227). Engine-idiomatic: register a `MaterialSettingsTemplates` entry with `type = "texture"` variables and set `material_settings_name` on the cwv SKIN entry - vanilla then applies it automatically on owner + husk spawns (`gear_utils.lua:195-199` via `apply_material_settings` `:149-151`), inventory preview (`world_hero_previewer.lua:683/706` carries `material_settings_name` into spawn_data), and the illusion browser (same `get_item_units` resolution, `loot_item_unit_previewer.lua:270`). cosmetics already proves the template-registration half (`MaterialSettingsTemplates._cosmetics_tweaker_glow`, cosmetics:4952-4964). Caveat: texture entries are gated on `Application.can_get("texture", ...)` (`gear_utils.lua:149`) - mod-bundled textures must be resident.

### 5.4 P1 - musket bayonet reimplements the engine's attached-units lifecycle

Five hooks hand-roll spawn / despawn / per-camera visibility / orphan pruning for a unit that rides the wielded weapon (cwv:4741+, 5033-5094, 5104-5145, 5150-5162). The engine's item-template `first_person_attached_units` / `third_person_attached_units` already implement this lifecycle: spawned on wield (`simple_inventory_extension.lua:181`, husk `:329`), despawned on unwield/hide, and SWAPPED per camera by `show_first_person_inventory` (`simple_inventory_extension.lua:953-969`) via `AttachmentUtils.create_weapon_visual_attachment` (`attachment_utils.lua:47`). Attaching at the owner-body weapon node (`j_rightweaponattach`) co-moves with the rifle. Migrating the bayonet to template attached-units deletes ~200 lines of visibility/orphan code and removes two whole hook registrations. Caveats to verify in-game: node choice matches the rifle grip, and husk-side attach still requires the husk to resolve the cwv template (5.2) - no worse than today.

### 5.5 P1 - root-cause the career_name drop instead of patching downstream

wt carries two compensations (recover from `inventory_system._career_name`, pre-resolve `override_item_units`; weapon_tweaker.lua:3712-3749) for a wrapper somewhere in the cross-mod `create_equipment` chain that fails to forward arg 13. Every mod in this monorepo that hooks `GearUtils.create_equipment` (wt:3712, cosmetics:5195, cwv:10457, ct:5794, ct_dev:6628, tweaker:229 frozen) should be audited for full-arity forwarding; the frozen `tweaker` `_safe_create_equipment` (tweaker/scripts/mods/tweaker/tweaker.lua:229) is the prime suspect since it predates the 13-arg signature [unverified]. Fixing the dropper makes vanilla's own per-career override (`backend_utils.lua:159-162`) reliable and lets wt delete both compensations.

### 5.6 P2 - preview def resolution first-match on a shared base name

`_find_preview_slot_info` matches `info.name == item_name` across ALL slots and returns the first hit (character_weapon_variants.lua:10502-10509). cwv muskets are cross-slot (equippable in melee AND ranged, cwv:3978-3989) and every instance shares the inherited base name - two slots previewing items with the same base can resolve the wrong def/stance. Engine-idiomatic: `_spawn_item` receives no slot, but the `equip_item` hook does - key the pending def by `slot.type` at equip time (the pattern wt already uses, `_wt_capture_preview_item_key`, weapon_tweaker.lua:6164-6174) instead of name-scanning.

### 5.7 P2 - WA transform module still not shared cross-mod (#420 open)

cosmetics re-implements offset/scale locally (`_offset_units` cosmetics:5029-5042 - additive `Unit.set_local_position` with pcall, no idempotency guard beyond fresh-spawn assumption; `_scale_units`, `_apply_unit_path_scale_hand`) while cwv owns the guarded `WA` module (cwv:9913-9981, exposed as `mod._cwv_weapon_appearance` cwv:9973). The standalone-invariant-compatible fix is the copied-lib pattern already proven by `_lib_peer_parity.lua:4-13` (master in `tools/shared_lib/`, verbatim per-mod copies) - promote WA to `tools/shared_lib/_lib_weapon_appearance.lua` and consume it from cosmetics and wt.

### 5.8 P2 - husk wearer-peer resolution scans the player table

cosmetics resolves the husk's owner by iterating `Managers.player._players` comparing `player_unit` (cosmetics_tweaker.lua:8000-8007). Vanilla's own husk code uses `Managers.player:unit_owner(unit)` for exactly this (`simple_husk_inventory_extension.lua:341`) - one call, covers bots, no private-field dependency.

### 5.9 P2 - javelin spare-spear hide fights vanilla visibility instead of using `ammo_unit_3p`

Two hooks re-hide the duplicated 3P boar spear after every vanilla visibility set (cwv:5083-5091 in `_wield_slot`, cwv:5127-5144 in `show_third_person_inventory`). Vanilla has a dedicated data field to decouple the 3P spare mesh from the 1P/projectile ammo unit: `item_data.ammo_unit_3p` (`backend_utils.lua:148`, consumed at `gear_utils.lua:161/169` as `ammo_unit_name_3p or ammo_unit_name .. "_3p"`). Pointing the entry's `ammo_unit_3p` at a minimal/held-matching unit removes the double render at the data level on owner AND husk with zero hooks. Requires an in-game verify that projectile/pickup paths only read `ammo_unit` (they do in `get_item_units`; the v0.1.314 revert note constrains `ammo_unit`, not `ammo_unit_3p`, cwv:5077-5081).

### 5.10 P2 - unify the plain-table hook doctrine (string vs table form)

cwv hooks `"BackendUtils"` string-form (cwv:3938) while cosmetics documents string-form as unresolvable for plain tables and mandates table-form (cosmetics:4040-4045); both currently work because VMF resolves strings via `rawget(_G, name)` and defers unresolved hooks (`vmf/modules/core/hooks.lua:46-58, :379-389`). The REAL constraints are (a) registration-time existence for table-form, (b) LA's clone-backend reassignment (hook the post-LA reference; docs/CROSS_MOD_ARCHITECTURE.md). Pick one doctrine repo-wide and record WHY, so the next session doesn't "fix" a working hook into a broken one - the v0.8.58 CosmeticUtils burn (cosmetics:5807-5812) deserves a root-cause note (likely registration-order, not string-form per se) [unverified].

### 5.11 P2 - duplicated wire-null implementations

cwv:10424-10447 and cosmetics:6075-6103 are byte-similar null-and-restore wrappers on the same vanilla seam, each keyed to its own skin set. VMF chains cross-mod hooks fine, but the pattern (and its 5.1 gap) is maintained twice. Fold into the shared-lib pattern (5.7) with a per-mod key-set parameter, so closing the hot-join/resync senders (5.1) happens once.

---

## Appendix A - quick seam index for a new display feature

To make a weapon LOOK different, in order of preference:

1. **Data field on the entry / skin** (`ItemMasterList` entry, `WeaponSkins.skins` entry): `right/left_hand_unit`, `*_hand_unit_override[career]`, `ammo_unit_3p`, `material_settings_name`, `hud_icon`. Resolved by `BackendUtils.get_item_units` -> free coverage on all four paths INCLUDING husks (limited to what the wire carries: name + skin).
2. **`BackendUtils.get_item_units` hook** - when the data field cannot express the rule (conditional on backend_id, career, co-installed mods). Still covers all four paths.
3. **Per-path spawn hooks** - only for runtime-unit work (transforms, particles, linked children): `GearUtils.create_equipment` (own), `GearUtils.spawn_inventory_unit` `owner_unit_1p==nil` branch (husk), `MenuWorldPreviewer.equip_item`/`_spawn_item` (preview), `LootItemUnitPreviewer.spawn_units` (browser). All four or the change is incomplete (WEAPON_APPEARANCE_STANDARD 1).
4. **Wire**: if the identity does not survive `rpc_add_equipment` (anything beyond base name + vanilla-registered skin), plan the sync marker FIRST (#392) - and null every modded index at EVERY sender (5.1 list) before shipping.
