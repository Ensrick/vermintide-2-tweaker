# Character Weapon Variants — Changelog

## 0.1.65-dev (2026-05-01)
- Added: `tuskgor_javelin_template` — stat-modified clone of `javelin_template` for `cwv_es_javelin`. Behavioural changes:
  - `ammo_data.max_ammo = 15` (up from vanilla 3) — finite stack
  - `ammo_data.block_ammo_pickup = false`, `unique_ammo_type = false` — standard vanilla ammo crates now refill the stack (Kruber's other ranged weapons share the pool)
  - `actions.weapon_reload.default.condition_func` / `chain_condition_func` overridden to `_always_false` — disables the magic auto-catch that vanilla javelin uses to refill itself on-demand. Action stays defined for state-machine/network purposes; it just never fires.
  - `attack_meta_data.minimum_charge_time` doubled (0.55s → 1.1s) — slower wind-up
  - `total_time` and `minimum_hold_time` doubled on `kind="thrown_projectile"` sub-actions — slower throw recovery. `fire_time` left untouched (would desync projectile spawn from anim).
  - All damage profiles cloned with prefix `cwv_tj_`, `attack` doubled (impact/stagger preserved). Melee stabs use existing `_clone_damage_profile` (PowerLevelTemplates string-key shape); throw projectile uses new `_clone_inline_throw_profile` (inline `default_target.power_distribution_near.attack` shape, verified against `damage_profile_templates_dlc_woods.lua:263`).
- Changed: `cwv_es_javelin` def now sets `template = "tuskgor_javelin_template"` and updated description ("Hits like a kicking mule…"). Old "thrown projectile is still the slim javelin" caveat refined — the template is now cloned but the projectile model isn't (boar spear has no `prj_*_3ps` unit in the anvil package).

## 0.1.64-dev (2026-05-01)
- Fixed: ammo-weapon variant skin registration now mirrors the FULL set of fields BackendUtils.get_item_units overwrites from the skin template — `ammo_unit`, `ammo_unit_3p`, `projectile_units_template`, `pickup_template_name`, `link_pickup_template_name` — from the base ItemMasterList entry. Previously only `ammo_unit` was carried (0.1.60), which left the throw projectile / ground-pickup paths exposed to nil-from-skin once the previewer crash was past. Verified via the v0.1.59 crash log (`[LA preview] equip_item key=we_javelin slot=slot_ranged bid=cwv_es_javelin_001 skin=nil` → previewer concatenated nil ammo_unit). Log line now includes `(ammo_unit=..., projectile=...)` for verification.

## 0.1.63-dev (2026-05-01)
- Added: `cwv_es_dual_swords` ("Imperial Dual Swords") — Kruber dual-wield variant cloned from `we_dual_wield_swords`. Both hands hold Kruber's vanilla 1H sword (`wpn_emp_sword_02_t1`); models scaled to {1.0, 0.80, 1.0} (Y -20%, slimmer along depth) on both hands. Available on all four Kruber careers via `_es_all_careers`. Exotic rarity, default trait Swift Slaying.
- Added: `imperial_dual_swords_template` — runtime clone of `dual_wield_swords_template_1` with stat tweaks: -20% speed (`anim_time_scale * 0.80`), +10% damage (`power_distribution.attack * 1.10`), +10% stagger (`power_distribution.impact * 1.10`). Damage profiles cloned with prefix `cwv_eds_`.
- Added: 3P animation redirect to Kruber's mace+sword (`dual_wield_hammer_sword_template`). Sets `wield_anim_3p = "to_dual_hammer_sword_es"` on both the cloned template and the base template's `wield_anim_career_3p` for Kruber careers (matches the inventory-previewer base-template-lookup pattern documented in `feedback_cwv_previewer_template_lookup.md`). Three elf-only attack events with no Kruber mace+sword counterpart are remapped via `anim_event_3p`: `attack_swing_charge_diagonal → attack_swing_charge_left`, `attack_swing_heavy_right → attack_swing_heavy_right_diagonal`, `push_stab → attack_push`. Same-named events fall through and play Kruber's mace+sword animations natively (the empire skeleton authors them under those names).

## 0.1.62-dev (2026-05-01)
- Fixed: javelin variant equip still crashed after 0.1.60 — the `if not WeaponSkins.skins[skin_key]` guard in `_register_variant_skins` skipped re-registration when a stale skin entry from a prior session/version was already present (e.g. a partial reload that re-ran the lua but kept the existing WeaponSkins table). Removed the guard so we always overwrite with current fields. Added `(ammo_unit=...)` to the registration log line so the value is verifiable from the in-game info log.

## 0.1.61-dev (2026-05-01)
- Added: `cwv_es_priest_greathammer` ("Sigmarite Greathammer") — Kruber variant of the Warrior Priest's Greathammer. Same recipe as the Bardin version (`cwv_dr_priest_greathammer`, 0.1.59): clones `wh_2h_hammer` (preserves `two_handed_hammer_priest_template` chargeable smash moveset) and swaps the held model to Kruber's vanilla greathammer (`wpn_empire_2h_hammer_01_t1`). Available on all four Kruber careers via `_es_all_careers`. Exotic rarity, default trait Swift Slaying.
- Known issues — animation workarounds NOT yet implemented for the priest greathammer line:
  - **Both `cwv_dr_priest_greathammer` (Bardin) and `cwv_es_priest_greathammer` (Kruber) inherit `two_handed_hammer_priest_template`, which was authored against Saltzpyre's skeleton.** No 3P/1P anim event coverage probe has been done for dwarf or empire skeletons against this template's events (`attack_swing_charge_right`, `attack_swing_charge`, light/heavy chains, wield pose).
  - Kruber risk is lower (Saltzpyre and Kruber share the empire-human skeleton family, so most events likely already exist natively); Bardin risk is higher (dwarf skeleton, smaller body, likely event mismatch).
  - Workflow when animations break in-game: use `wt animlog` to dump missing events per career, then add remaps either via this mod's template clone (see `_create_elven_sword_shield_template` for the pattern — `anim_event_3p` overrides + `wield_anim_career_3p` patch on the BASE template per `feedback_cwv_previewer_template_lookup.md`) or via weapon_tweaker's career-prefix-aware `_career_anim_redirect`. Process documented in `reference_3p_anim_fix_process.md`.

## 0.1.60-dev (2026-05-01)
- Fixed: equipping `cwv_es_javelin` crashed `world_hero_previewer.lua` ("attempt to concatenate local 'left_hand_unit' (a nil value)"). Root cause: `BackendUtils.get_item_units` overwrites `units.ammo_unit` from the skin template (`WeaponSkins.skins[skin].ammo_unit`) unconditionally when a skin is set. Our custom skin entries omitted `ammo_unit`, so it became nil — and the previewer does `left_hand_unit = ammo_unit` for `is_ammo_weapon` items before concatenating `_3p`. `_register_variant_skins` now mirrors `def.ammo_unit` (fallback: `def.left_hand_unit`) into the skin entry. Required for any cwv variant cloned from an ammo weapon (javelins, future thrown variants).

## 0.1.59-dev (2026-05-01)
- Added: `cwv_dr_priest_greathammer` ("Sigmarite Greathammer") — Bardin variant of the Warrior Priest's Greathammer. Uses `wh_2h_hammer` as base (preserves `two_handed_hammer_priest_template` — the chargeable smash moveset) but swaps the held model to Bardin's vanilla greathammer (`wpn_dw_2h_hammer_01_t1`). Available on all Bardin careers (Ranger Veteran, Ironbreaker, Slayer, Outcast Engineer). Exotic rarity, default trait Swift Slaying.
- Known issues: `two_handed_hammer_priest_template` was authored against Saltzpyre's skeleton — if any 1P/3P anim events are missing on the dwarf skeleton, fix via weapon_tweaker animation remap (per `reference_3p_anim_fix_process.md`).

## 0.1.58-dev (2026-05-01)
- Added: `cwv_es_javelin` ("Tuskgor Javelin") — Kruber variant of the elf javelin. Uses `we_javelin` as base (preserves `javelin_template`, `slot_type=ranged`, `item_type=we_javelin`, `trait_table_name=ranged_ammo`, `projectile_units_template=javelin`) but swaps the held model to the Tuskgor Spear (`wpn_emp_boar_spear_01`). Available on all Kruber careers (Mercenary, Huntsman, Knight, Questing Knight). Exotic rarity, default trait Scrounger (`ranged_replenish_ammo_headshot`).
- Known issues: thrown projectile remains the slim javelin (`Projectiles.javelin` is hardcoded in `javelin_template`); fixing requires a custom template + projectile clone. Kruber's skeleton may also lack some elf throw events (`attack_throw`, `throw_charge`) — if 3P anims are missing in-game, add remaps via weapon_tweaker.

## 0.1.56-dev (2026-05-01)
- Fixed: equipping a cwv variant crashed `BackendUtils.get_item_units` with `attempt to index local 'item_data' (a nil value)`. Vanilla `HeroPreviewer.equip_item` (world_hero_previewer.lua:674) does `item_data = ItemMasterList[item_name]` and passes the result straight into `BackendUtils.get_item_units`. MIL's `add_mod_items_to_local_backend` stores entries in its private table, NOT in ItemMasterList, so the lookup returned nil. `_register_item` now mirrors each cwv entry into `ItemMasterList[def.item_key]` after MIL registration (guarded with `not ItemMasterList[key]` so we don't clobber another mod's registration or a stale hot-reload entry).
- Cleanup: NetworkLookup item_names injection now uses `def.item_key` directly, not the inherited `entry.key` (which would be the base weapon's name from the clone).

## 0.1.55-dev (2026-05-01)
- Added: `entry.cwv_variant = true` marker in `_build_entry`. This is the cross-mod contract: sibling mods (cosmetics_tweaker, weapon_tweaker, future) check `item_data.cwv_variant` in their hooks and skip item-name-keyed overrides when the flag is set. Necessary because cwv items inherit `entry.name` from the base via `table.clone` (e.g. `cwv_es_longsword.name == "es_bastard_sword"`), so without the gate any item-name-keyed override on the base — `_breton_sword_thiccc`, `_weapon_grip_offsets`, hat tinting — would spuriously fire on every cwv variant of that base.
- Tried-and-rejected: clobbering `entry.name = def.item_key` instead of using a flag. The clobber crashed equip because vanilla code falls back to `ItemMasterList[item.name]` lookups that need the inherited name to resolve. See `feedback_cwv_clone_name_clobber.md` for the full incident log and reasoning.
- Note: cosmetics_tweaker has since (v0.7.87) migrated its scale system from item-name-keyed to unit-path-keyed, which makes the flag redundant for the scale path specifically. The flag is still load-bearing for the grip-offset / tint / LA-paint paths and remains the documented cross-mod contract.

## 0.1.46–0.1.54-dev (2026-05-01)

Iterative dev bumps not documented individually here. See `git log -- character_weapon_variants/` for the actual history. Going forward, please add a heading per substantive change set.

## 0.1.45-dev (2026-05-01)
- Added: `mod.weapon_analogues` table + `mod.get_analogues(item_key)` getter — public API exposing vanilla weapon items that are mechanically analogous and can share cosmetics. Initial mapping: `es_2h_sword ↔ wh_2h_sword` (Kruber Greatsword ↔ Saltzpyre Falchion). Consumed by cosmetics_tweaker's LA bridge to widen cross-character cosmetic targeting when this mod is loaded.

## 0.1.25-dev (2026-05-01)
- Added: Imperial Longsword — `cwv_es_longsword` (default, power 5) and `cwv_es_longsword_veteran` ("Halfling Splitter", exotic rarity). Uses `bastard_sword_template` as base with a custom `imperial_longsword_template` clone: -15% damage, +15% speed (anim_time_scale), +15% cleave, -15% stagger. Available on all Kruber careers.
- Added: `imperial_longsword_template` — runtime clone of `bastard_sword_template` with modified stat multipliers. Clones all 6 melee damage profiles (`DamageProfileTemplates` + `PowerLevelTemplates`) with `cwv_il_` prefix, modifying `power_distribution.attack` (damage), `power_distribution.impact` (stagger), and `cleave_distribution` values. Multiplies `anim_time_scale` on all sub-actions for speed.
- Added: model scaling system — `right_hand_scale` / `left_hand_scale` fields on variant definitions apply `Unit.set_local_scale` across all three rendering paths (GearUtils.create_equipment, HeroPreviewer._spawn_item, LootItemUnitPreviewer.spawn_units). Base longsword: 1h sword model stretched Z +15% ({1.0, 1.0, 1.15}). Veteran: greatsword model thinned X 0.65 + shortened Z -15% ({0.65, 1.0, 0.85}).
- Changed: `_build_entry` now supports `template` override and clears `required_dlc` on cloned entries

## 0.1.24-dev (2026-05-01)
- Fixed: crash `NetworkLookup.lua Table item_names does not contain key` when equipping LA bridge hats. Root cause: `MoreItemsLibrary.add_mod_items_to_local_backend` does NOT inject into `NetworkLookup.item_names` (only `add_mod_items_to_masterlist` does). Items registered via MIL were invisible to the network serialization layer. Now manually inject all mod-created item keys into `NetworkLookup.item_names` using `rawset` after MIL registration — covers variant weapons, custom illusions, and LA bridge hats (cosmetics_tweaker fix).

## 0.1.22-dev (2026-05-01)
- Fixed: `ActionWield.start` hook failed — `ActionWield` isn't loaded at mod init. Changed to `hook_safe("ActionWield", "client_owner_start_action", ...)` which uses lazy string-form resolution and fires after the original (so `self.new_slot` is available for weapon tracking).
- Fixed: removed incorrect `_weapon_remap` table that remapped 9 events. Template analysis shows 12/14 sword+shield events already exist on elf's skeleton (confirmed via elf 1h sword, dual swords, sword+dagger, 2h sword, spear, spear+shield templates). Only `attack_swing_charge_right_pose` (L3/H2 charge) is missing and remapped to `attack_swing_charge_right_diagonal_pose`.

## 0.1.20-dev (2026-04-30)
- Fixed: elf sword+shield missing animations — L1, H1, H3 didn't play because elf's skeleton lacks those specific events from Kruber's sword+shield template. Added career-scoped redirects:
  - `attack_swing_charge` → `attack_swing_charge_left` (L1 charge)
  - `attack_swing_heavy` → `attack_swing_heavy_left` (H1 shield slam)
  - `attack_swing_left_diagonal` → `attack_swing_left` (L1 release)
- Removed verbose info logging from animation redirects to reduce log spam

## 0.1.19-dev (2026-04-30)
- Added: cross-character greatsword illusions — all of Saltzpyre's greatsword skins selectable on Kruber's greatsword and vice versa via cosmetics menu. Includes base skins, runed/red illusions, bogenhafen (purple glow), geheimnisnacht (golden glow), and weavebound (magic) variants. 9 Saltzpyre→Kruber skins, 11 Kruber→Saltzpyre skins.
- Added: `_custom_illusions` system — clones all visual data (name, rarity, icon, glow material, model) from vanilla `WeaponSkins.skins` at runtime. No manual field copying needed — just `skin_key`, `matching_weapon`, `source_skin`, and `can_wield`.
- Added: `_register_custom_illusions()` — injects into `ItemMasterList`, `WeaponSkins.skins`, `skin_combinations` (correct rarity tier), and `NetworkLookup.weapon_skins`. Hooks `get_unlocked_weapon_skins` to mark custom skins as unlocked.
- Added: Elf Sword and Shield — `cwv_we_sword_shield` (magic, weave template) and `cwv_we_sword_shield_veteran` (unique/veteran with Opportunist + block cost + power vs skaven). Uses Kruber's `es_sword_shield` template (`one_handed_sword_shield_template_1`) with elf's weave sword (`wpn_we_sword_03_t1_magic_01`) and weave spear+shield's shield (`wpn_we_shield_02_magic_01`). Available on all elf careers.
- Added: animation redirect system — remaps `to_1h_sword_shield` wield anim to `to_1h_spear_shield` for elf careers, plus suffix-based redirect for any `_1h_sword_shield` suffixed events. Hooks `Unit.animation_event` with career detection.
- Changed: `cwv_es_axe_shield` base variant from magic (weave) to plentiful (green) rarity — now functions as the standard blacksmith's template item with no traits or properties.

## 0.1.18-dev (2026-04-30)
- Fixed: veteran variant showed as template item (no rarity color, no cosmetics menu). Root cause: GiveWeapon pattern requires `entry.rarity = "default"` and `CustomData.rarity = "default"` during registration, then post-registration the actual rarity is set on the live backend item object (`item.rarity`, `item.data.rarity`, `item.CustomData.rarity`).
- Fixed: kept `skin_combination_table` from base weapon instead of clearing it — needed for the cosmetics/illusion menu to appear.
- Fixed: property values use `1` (max roll) instead of decimal fractions — matches GiveWeapon's format.

## 0.1.17-dev (2026-04-30)
- Fixed: auto-registration crashed because backend is nil at mod init. Now deferred via `mod:hook_safe("StateInGameRunning", "on_enter", ...)` — items register when entering the keep/mission, where the backend is guaranteed ready.

## 0.1.16-dev (2026-04-30)
- Changed: veteran variant now uses Opportunist trait (`melee_counter_push_power`), 30% block cost reduction, 10% power vs skaven
- Fixed: auto-registration now runs at mod init (same timing as cosmetics_tweaker's LA bridge) instead of `StateInGameRunning` — weapons appear in inventory immediately without needing to enter a mission first

## 0.1.14-dev (2026-04-30)
- Changed: exotic variant → veteran (unique) rarity so it functions as a proper weapon with properties and traits, not a weapon template
- Added: auto-registration — all variant weapons are automatically added to inventory when entering a game (no `cwv_give` needed). Uses stable backend IDs to prevent duplicates across sessions.
- Changed: `cwv_give` now checks for duplicates and uses stable IDs instead of time-based ones

## 0.1.13-dev (2026-04-30)
- Added: exotic-rarity variant `cwv_es_axe_shield_exotic` — "Imperial Axe and Shield" with power level 300, `melee_attack_speed_on_crit` trait, and attack speed + crit chance properties. Functions as a proper weapon with stats, not just a template.
- Changed: `_build_entry` now serializes traits and properties from variant definitions into `CustomData` JSON strings and parallel Lua tables, matching the format expected by MoreItemsLibrary and the backend.

## 0.1.12-dev (2026-04-30)
- Fixed: `NetworkLookup.weapon_skins` has an error-throwing `__index` metamethod — accessing a missing key crashes instead of returning nil. Now uses `rawget`/`rawset` to bypass the metatable when checking and injecting the custom skin key.

## 0.1.11-dev (2026-04-30)
- Fixed: crash `NetworkLookup.weapon_skins does not contain key: cwv_es_axe_shield_skin` — custom skins must be injected into `NetworkLookup.weapon_skins` for network serialization. The skin is registered in `WeaponSkins.skins` after `NetworkLookup` is built, so it needs a manual append.

## 0.1.10-dev (2026-04-30)
- Fixed: crash `Material not found in Gui` — `inventory_icon` and `hud_icon` are different systems. `inventory_icon` uses texture keys like `icon_wpn_dw_shield_01_axe`, while `hud_icon` uses keys like `weapon_generic_icon_axe_and_sheild`. Using the wrong type in either field crashes the UI renderer.

## 0.1.9-dev (2026-04-30)
- Fixed: crash `Material 'weapon_generic_icon_staff_3' not found in Gui` — that icon key doesn't exist in the GUI atlas. Replaced with `weapon_generic_icon_axe_and_sheild` (Bardin's axe+shield HUD icon) as a working placeholder

## 0.1.8-dev (2026-04-30)
- Fixed: inventory preview showed Bardin's models because `BackendUtils.get_item_units` resolves units through the item's skin, not the base entry's unit paths. Now registers a custom `WeaponSkins.skins` entry per variant with the correct unit paths, and sets it as the item's skin via `mod_data.CustomData.skin`

## 0.1.7-dev (2026-04-30)
- Fixed: inventory preview showed Bardin's model because skin resolution overrode our unit paths — now clears `skin_combination_table` on cloned entries so the entry's `right_hand_unit`/`left_hand_unit` are used directly

## 0.1.6-dev (2026-04-30)
- Fixed: `cwv_give` items now override `display_name` and `description` with custom loc keys so they show our names instead of the base weapon's (e.g. "Axe and Shield" instead of Bardin's name)

## 0.1.5-dev (2026-04-30)
- Added: Saltzpyre's one-handed axe (`wh_1h_axe`) unlocked on all Kruber careers (Mercenary, Huntsman, Foot Knight, Grail Knight) via `can_wield` patch at mod load
- Added: `_weapon_unlocks` table for declarative cross-character weapon unlocks

## 0.1.4-dev (2026-04-30)
- Fixed: `ItemHelper.mark_backend_id_as_new` was called with a table `{backend_id}` instead of the string `backend_id`
- Fixed: `mark_backend_id_as_new` was called before `_refresh()`, so the backend hadn't indexed the new item yet — reordered to refresh first, then mark
- Added pcall guard around `mark_backend_id_as_new` in case the item isn't found

## 0.1.3-dev (2026-04-30)
- Fixed: removed init-time item registration — backend is not ready at mod load; `add_mod_items_to_local_backend` now called on-demand via `cwv_give` command only
- Fixed: no longer overwrites `display_name`/`description` on cloned ItemMasterList entry — MoreItemsLibrary requires these to be real strings, not localization keys; custom names handled via Localize hook instead
- Fixed: base weapon key corrected from `dr_1h_axe_shield` (item_type) to `dr_shield_axe` (actual ItemMasterList key)

## 0.1.2-dev (2026-04-30)
- Fixed: base weapon key `dr_1h_axe_shield` → `dr_shield_axe`

## 0.1.1-dev (2026-04-30)
- Added first variant definition: `cwv_es_axe_shield` (Weave Forged Axe and Shield for Kruber)
  - Mainhand: Saltzpyre's weave-forged hatchet (`wpn_axe_hatchet_t2_magic_01`)
  - Offhand: Kruber's weave-forged CW spear+shield shield (`wpn_es_deus_shield_02_magic`)
  - Base template: Bardin's `dr_shield_axe` (`one_hand_axe_shield_template_1`)
  - Rarity: magic (weavebound)
  - Available on: Mercenary, Huntsman, Foot Knight
- Added `cwv_give <item_key>` command to spawn variant weapons
- Added `cwv` status command
- Added companion mod detection (weapon_tweaker, cosmetics_tweaker)
- Added Localize hook for custom display names and descriptions

## 0.1.0-dev (2026-04-29)
- Initial mod scaffold created via VMB
- Workshop item created (ID: 3716869446, private)
- MoreItemsLibrary integration structure
- Cross-mod architecture documented in `CROSS_MOD_ARCHITECTURE.md`
