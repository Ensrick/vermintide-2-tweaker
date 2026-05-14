# Chaos Wastes Tweaker Changelog

## 0.7.0-alpha (2026-05-13)

First experimental public release. Marks the formal opening of the mod to a broader audience after months of internal iteration. Title changed to "Tweaker: Chaos Wastes" (was "Tweaker: Chaos Wastes (WIP)"), Workshop description rewritten to cover the full feature surface, new thumbnail in place.

Headline since the last released build: the **Adventure Maps in Chaos Wastes** subsystem. Adventure missions are now injectable into the CW random map pool with full mission lifecycle (curses, boons, finale routing) intact: tomes/grims become Chests of Trials, pickups rewrite to CW types, altars seed at 5/map (1 upgrade + 1 melee swap + 1 ranged swap + 2 boon), cursed nodes carry the matching sky/lighting tint, and altars/chests use `filter_trigger` so the player walks through them.

## 0.6.33-dev (2026-05-13)

### Fixed: Event barrels spawning as potions (broke scripted events)

`_can_spawn` hook was returning true for `deus_potions`/`deus_soft_currency`/`deus_weapon_chest` on EVERY adventure spawner (except tome/grim), including **triggered event spawners** for scripted lamp_oil / explosive_barrel / training_dummy_bob spawns. `_spawn_guaranteed_pickup` iterates all pickup names asking `_can_spawn` for each, then picks randomly from candidates — so a triggered barrel-spawner could roll `healing_draught` instead of `lamp_oil` and break the scripted event.

Fix: in the `_can_spawn` adventure-fallback, also short-circuit to `false` when:
- `Unit.get_data(spawner, "guaranteed_spawn")` is truthy (book / specified spawners)
- `Unit.get_data(spawner, "triggered_spawn_id")` is a non-empty string (event-driven spawners)

CW types still flow onto generic primary spawners (the ones without any specific event tag) so coin / potion / altar counts are unaffected.

## 0.6.32-dev (2026-05-13)

### Fixed: Chest of Trials interaction broken in v0.6.28+

v0.6.28's `Actor.set_scene_query_enabled(actor, false)` made altars/chests walk-through BUT broke interaction with them. Cause: `GenericUnitInteractorExtension._find_best_interaction_unit` (interactor extension line 254) discovers interactables via `PhysicsWorld.immediate_overlap(..., "collision_filter", "filter_overlap_interaction")` which needs scene_query=true on the actor. The "proximity check" assumption in the v0.6.28 comment was wrong — interaction discovery is scene-query-driven.

Fix: revert scene_query disable. Instead, reclassify the actor's collision filter to `filter_trigger` via `Actor.set_collision_filter` — the vanilla "non-blocking interactable" filter (see `ai_utils.lua:521` for the canonical pattern). The player_mover sweep ignores `filter_trigger` actors so the player walks through; raycast overlaps still hit them so interaction works.

`set_collision_enabled(false)` is also kept as belt-and-braces but the filter change is the load-bearing piece.

## 0.6.31-dev (2026-05-13)

### Fixed: Exact cursed-mission count

Setting `cursed_mission_count` was driving `CURSES_HOT_SPOTS_MIN/MAX_COUNT` only, but vanilla `spread_curse` (deus_populate_graph.lua:681) then *spread* each cluster center to neighbouring nodes within `CURSES_HOT_SPOT_MIN_RANGE..MAX_RANGE`, so requesting N would typically yield 5–15 cursed nodes. Fix: when the override is active, also force `CURSES_HOT_SPOT_MIN_RANGE = MAX_RANGE = 0` so each cluster curses only its center node. Both ranges are saved before the override and restored in `restore_curse_count` so vanilla CW spread behaviour returns intact when the setting is back to 0.

## 0.4.1-dev (2026-05-10)

### Fixed: `<<1>>`..`<<9>>` in altar count dropdowns

The four altar-count dropdowns (Upgrade / Melee Swap / Ranged Swap / Boon Altars) showed `<<1>>` through `<<9>>` instead of plain `1`–`9`. Cause: `altar_count_options` used `text = "1"`..`"9"` as labels, expecting VMF to fall through to the literal string when no loc entry matched. VMF actually wraps missing keys in `<<>>`. Fix: added explicit `["1"]` … `["9"]` entries in `_localization.lua`. Updated the misleading comment in `_data.lua` to document the real VMF behaviour.

## 0.4.0-dev (2026-05-10)

### Added: Bomb-boon balance toggles

Four new toggles in **Modified Boons** group, sourced from a community balance thread:

- **Bomb Boon Cooldown (s)** — uniform cooldown override for the *Drop bomb on ability use* boon. Vanilla per-item cooldowns are 180s (Rally Flag), 180s (Morgrim's Bomb), 120s (Endless Bombs Potion); a single positive value here applies uniformly to all three. 0 = vanilla. Implemented by mutating `DeusPowerUpTemplates.drop_item_on_ability_use.buff_template.buffs[1].cooldown_durations` (read at proc time in `morris_buff_settings.lua:2830`). Mirrors the Khaine's Fury save-and-restore pattern; reverts on `on_disabled` and re-applies on setting change.

- **Bomb Boons Mutually Exclusive** — once any bomb boon is owned (`drop_item_on_ability_use` or `deus_grenade_multi_throw`), other bomb boons are stripped from the random pool for the rest of the run. Implemented inside the existing `generate_random_power_ups` save-and-restore filter (the third hook arg is `existing_power_ups`); piggybacks on the same removed-then-restored pool list.

- **Endless Bombs Consumes Morgrim's** — when the Endless Bombs potion is drunk, any saved Morgrim's Bomb is permanently destroyed instead of dropped on the ground. Hooks `BuffFunctionTemplates.functions.apply_pockets_full_of_bombs_buff` and calls `destroy_slot("slot_level_event")` only when the slot item is `holy_hand_grenade`; other level-event items keep vanilla drop behaviour.

- **Block Ranger Veteran from Saving Morgrim's** — RV's `bardin_ranger_passive_consumeable_dupe_grenade` (10% chance not to consume on grenade throw, applied via `not_consume_grenade` proc stat_buff) cannot fire when the thrown grenade is a Morgrim's Bomb. Hooks `ActionChargedProjectileUtility.fire_charged_projectile`; instance-level monkey-patch of the buff_extension's `apply_buffs_to_value` for the duration of the call (with `rawget`-aware restore through `__index`), gated on `projectile_context.item_name == "holy_hand_grenade"`.

## 0.3.9-dev (2026-05-09)

Version bump for batch deploy. No behaviour changes since 0.3.4-dev — the gap reflects internal version increments during cross-mod work that didn't land separate CW changes.

## 0.3.4-dev (2026-05-01)

### Fixed: Banned Weapon Traits list

The previous list had 20 entries, of which **7 were no-ops** because the names didn't match any real CW weapon trait: `increased_punch_through`, `off_balance`, `power_vs_skaven` (a property, not a trait), `resourceful_combatant`, `scrounger` (a deus weapon theme name), `shockwave` (also a theme), `swiftslaying`. The other 13 silently missed real traits like Swift Slaying, Shockwave, Off Balance, Piercing Projectiles, Resourceful Sharpshooter, etc. — so users couldn't actually ban those.

Replaced with the **31 real traits** that appear in `DeusWeapons[*].baked_trait_combinations`, dumped via the new `dump_traits` command and labeled with Fatshark's official display names + descriptions as tooltips. Banned-trait setting names now match `WeaponTraits.traits[name]` keys exactly, so the runtime check `mod:get("ban_trait_" .. trait)` actually fires.

## 0.3.3-dev (2026-05-01)

### Added: `dump_traits` command

New console command lists every weapon trait that can roll on any CW weapon (union of `DeusWeapons[*].baked_trait_combinations`), resolving each trait's `display_name` and `advanced_description` via `Localize()`. Used to gather the official Fatshark text needed to give the Banned Weapon Traits options proper labels and tooltips.

## 0.3.2-dev (2026-05-01)

### Fixed: `<<key>>` placeholders in mod options menu

40 boon-disable / starting-boon widgets referenced tooltip keys (`disable_boon_squats_tooltip`, `start_boon_squats_tooltip`, `..._deus_power_up_quest_granted_test_01_tooltip`, and all 36 `*_talent_N_M_tooltip`) that were never defined in `_localization.lua`. VMF rendered the unresolved keys as raw `<<key>>` strings on hover. Removed the broken tooltip refs from the widgets — the labels themselves were already auto-generated stubs (`"Talent 1 1"`, `"Squats"`, etc.) with no descriptive text to put in tooltips.

## 0.3.0-dev (2026-05-01)

### Fixed: Campaign potions in CW now actually spawn

The `enable_campaign_potions` toggle never produced visible results because the patch shared the campaign potion settings tables by reference. Engine-startup normalization (in `pickups.lua`) divides each entry's `spawn_weighting` by the sum of its group, so campaign-potion entries had weights ~3× the CW potions. The random sampler iterates with `pairs()` and breaks on the first cumulative weight that hits the random value (in `[0,1)`); the CW potions consistently exhausted that range first, so campaign potions never got picked. Fix: clone the entries and override their `spawn_weighting` to match the CW potion scale.

### Fixed: Boon labeled as "Reckless Swings" is actually called "Khaine's Fury"

Renamed the modified-boon toggle to "Tweak: Khaine's Fury" to match the in-game display name.

### Changed: Altar count defaults are now 0 = vanilla random

`chest_upgrade_count`, `chest_swap_melee_count`, `chest_swap_ranged_count`, and `chest_power_up_count` now default to 0 (leave vanilla distribution untouched). Range expanded from 0–8 to 0–9. Setting any of the four to a non-zero value still replaces the entire chest distribution; types still at 0 produce no altars of that type.

## 0.2.5-dev (2026-04-28)

### Added: Disabled Boons

All 172 boons can now be individually disabled from appearing at shrines, chests, altars, and Belakor's Temple. Boons are organized into 6 sub-groups: Properties, Talents, Skulls & Sets, Combat, Healing & Sustain, Utility & Team.

### Added: Starting Boons

All 172 boons can be toggled on as starting boons granted at the beginning of a Chaos Wastes run. Uses the same 6 sub-groups. Starting boons bypass the disabled-boons list and are granted to all players based on host settings.

### Added: Modified Boons

New "Modified Boons" section for per-boon gameplay tweaks. First entry: **Reckless Swings** — reduces self-damage from 3 to 1 per hit and lowers the health threshold from 50% to 25%, letting the boon stay active longer. Tooltip updates dynamically when the tweak is enabled.

### Added: Banned Weapon Traits

20 Chaos Wastes weapon traits can be individually banned from appearing on weapon upgrades.

### Fixed: Boon localization

Boon names in settings UI now display readable names instead of raw internal keys (e.g. "Attack Speed" instead of `<attack_speed>`). Localization is generated at mod registration time from the static boon key list, then upgraded to actual game display names on first Chaos Wastes entry.

### Changed: Removed redundant settings wrapper

Settings are no longer nested inside a redundant "Chaos Wastes" collapsible group.

## 0.2.0-dev (2026-04-24)

### Added: Version logging

Mod now logs `Chaos Wastes Tweaker v<version> loaded` on init so the running version can be verified in the console log.
