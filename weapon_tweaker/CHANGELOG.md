# Weapon Tweaker Changelog

## 0.11.8-dev (2026-05-01) — Migrated to VMB build pipeline

Moved from the raw Stingray SDK build (`wt.mod`, `settings.ini`, `lua_preprocessor_defines.config`, `.build/OUT/`) to VMB (`weapon_tweaker.mod`, `itemV2.cfg`, `bundleV2/`). Workshop ID `3712896117` and internal mod ID `"wt"` preserved — existing user settings are unaffected. `itemV2.cfg` set to `visibility = "private"`.

Intermediate dev versions 0.11.5–0.11.7 were undocumented in this changelog; treat them as iterative cleanup leading into the VMB migration.

## 0.11.4-dev (2026-05-01) — Crafted items: promo rarity (purple icon background)
- **Crafted items now use `"promo"` rarity** — purple icon background (`icon_bg_promo`). Patches `NetworkLookup.rarities` at mod init to add `"promo"` entry, preventing the `NetworkLookup.lua` crash on equip (v0.11.3 used `"promo"` without the lookup patch → crash on re-equip).

## 0.11.3-dev (2026-04-30) — Crafted items: promo rarity attempt (BROKEN)
- Set crafted item rarity to `"promo"` for purple background. **Crashed** on equip: `NetworkLookup.rarities` doesn't contain `"promo"`. Reverted in 0.11.4.

## 0.11.2-dev (2026-04-30) — Mod Weapon Crafting: live property/trait apply
- **Bubble grid changes now apply to the real item.** Added `_forge_apply_to_item()` — converts weave-format properties (slot indices → float values) and traits (weave keys → regular keys) back to the backend item on every set/remove. Also updates `CustomData` JSON for persistence within the session.

## 0.11.1-dev (2026-04-30) — Mod Weapon Crafting: property slot overlap fix
- **Fixed bubble grid slot collision.** Property slot indices now assigned sequentially across all properties (property 1 → slots {1,2,...}, property 2 → slots {N+1,...}) instead of both starting from slot 1. Prevents properties from overriding each other in the weave forge grid.

## 0.11.0-dev (2026-04-30) — Mod Weapon Crafting: item creation system
- **Client-side item crafting.** "Choose Weapon" now shows ALL career weapons (not weave templates). Selecting a weapon and clicking "CRAFT" creates a new item via `backend_mirror:add_item()` with `Application.guid()` backend IDs, power 300, exotic rarity.
- **Hooked 5 methods on `HeroWindowWeaveForgeWeapons`:** `_present_item` (no locked state), `_set_presentation_locked_state` (never locked), `_update_equip_button_status` (CRAFT label), `_on_list_index_selected` (always enable craft), `_equip_item` (create + equip item).
- Crafted items are session-only — lost on game restart (PlayFab resync).

## 0.10.42–0.10.47-dev (2026-04-30) — Forge UI: panel positioning polish
- Iterated icon and text positioning within overview/properties/trait panels. Final offsets: overview Y=740 (icon internal Y=-20), properties Y=500 (option text nudged -10), trait Y=310.

## 0.10.34–0.10.41-dev (2026-04-30) — Forge UI: item detail panels on hover, viewport polish
- **Item detail panels on hover.** Hovering melee (viewport 1) or ranged (viewport 3) shows the weapon's overview, properties, and trait panels in the center viewport 2 area — uses `UIWidgets.create_item_option_overview/properties/trait` factory widgets initialized via `UIWidget.init()`.
- **Viewport 2 (amulet) hidden** — unused in mod forge, all viewport 2 widgets set to `content.visible = false`.
- **Hover highlight color** changed from white to grey (123, 123, 123 RGB).
- **Panel positioning** iterated across multiple versions to align icon, properties, and trait vertically (final offsets: overview Y=630, properties Y=470, trait Y=320).

## 0.10.33-dev (2026-04-30) — Forge UI: hover highlights to white, cluster glow recolor
- Overview viewport hover highlights (`viewport_button_highlight_`, `viewport_button_text_highlight_`) recolored from purple to white.
- Properties sub-menu `cluster_background_effect_1` recolored from purple to deep red.

## 0.10.32-dev (2026-04-30) — Forge UI: enhanced forge_dump_props diagnostics
- `forge_dump_props` command now reports preview state (`_viewport_widget`, `_item_previewer`, `_previewer_initialized`) and property/trait key mapping results for debugging the properties sub-menu.

## 0.10.31-dev (2026-04-30) — Forge UI: properties sub-menu power fix, additional widget hiding
- Properties sub-menu power display now reads from `params.selected_item.backend_id` (was nil via `_item_backend_id`). Shows real weapon power instead of spoofed 1800.
- Additional widget hiding in properties layout: level title/value, mastery, upgrade button, wheel rings.

## 0.10.30-dev (2026-04-30) — Forge UI: forge_dump_props diagnostic command
- Added `wt forge_dump_props` command using `mod:echo` (always flushes) instead of `mod:info`. Dumps properties window widgets, `params.selected_item`, and property/trait key mapping results.

## 0.10.15–0.10.29-dev (2026-04-29–30) — Mod Weapon Crafting forge UI
### Added
- **Athanor forge repurposed as Mod Weapon Crafting UI.** Opens via B hotkey. Backend hooks (`BackendInterfaceWeavesPlayFab`) intercept all weave loadout queries to serve real equipped weapon data.
- **Property/trait pre-fill from real items.** `_forge_seed_item()` reads equipped weapon's `.properties` and `.traits`, maps regular keys to weave-prefixed keys (`crit_boost` → `weave_crit_boost`), and converts float values to bubble-slot arrays. Seed persists across edits so adding/removing properties doesn't discard existing data.
- **`wt forge_dump` command** for traversing forge UI widget hierarchy (`ingame_ui.views[current_view]._machine._state._active_windows`).

### Changed
- **Header rebranded**: "Weave Power" label replaced with "MOD WEAPON CRAFTING" in large white text.
- **Background recolored**: Bottom smoke/ember effects changed from amber/purple to deep red (`bottom_glow_smoke_1/2/3`, `bottom_glow_embers_1`). Top fog layer (`top_glow_smoke_1`) recolored to match.
- **Power displays fixed**: Overview viewports show real weapon power levels. "Level: 999" labels hidden across overview and properties layouts.

### Removed (hidden)
- Forge level display, Athanor essence counter/icon, upgrade button, mastery counter/title/icon, wheel/ring background decorations — all set to `content.visible = false` when custom forge is active.

## 0.10.29-dev (2026-04-30) — Remove on_reload package clearing
### Fixed
- **`on_reload` package clearing caused locked resource crash.** Clearing `loaded_packages = {}` on our mods prevented the engine's `unload_mod` from calling `release_resource_package` on those handles — the resources stayed locked in the resource manager. When the engine then tried to unload a subsequent mod whose package shared or referenced those resources, it hit `ensure_unlocked` and crashed with *"Unloading a locked resource, lock count: 1"*. The `on_reload` hack was originally added to prevent VMF atlas crashes during `/reload`, but that's now handled properly by cosmetics_tweaker's `VMFOptionsView.update` pre-check guard. Removed the package clearing entirely; `on_reload` is now a no-op.

## 0.10.28-dev (2026-04-29) — Match human-readable mod names in OURS lookup
### Fixed
- **Scoped `on_reload` matched zero mods.** v0.10.26 used `m.name = "wt"` etc. as the key into `OURS`, but `mod_manager.lua` sets `mod.name` to the human-readable Workshop title (`"Weapon Tweaker"`, `"Cosmetics Tweaker"`...). The check missed every tweaker mod, so `on_reload` cleared zero packages — defeating the purpose. Symptom: `[WT] on_reload DONE (cleared packages on 0 tweaker mods of 72 total)` followed by *"Unloading a locked resource #ID[ddcb1a7c], lock count: 48"* crash. Fix: switched the `OURS` keys to the actual `m.name` values.

## 0.10.26-dev (2026-04-29) — Scope on_reload package clear to our mods only
### Fixed
- **`on_reload` was nuking third-party atlases.** `wt.mod`'s `on_reload` cleared `loaded_packages` on all 72 installed mods, not just our tweakers. After every `/reload`, VMF's `vmf_atlas`, Loremaster's Armoury's `armoury_atlas` / `la_notification_icon`, and any other mod's atlas got their package handles wiped. The materials stayed in GPU memory until *something* did a name lookup — at which point the engine fataled with `Material 'X' not found in Gui`. Symptoms cascaded across UI surfaces: NewsFeedUI, VMF options view, world markers, inventory exit. Fix: scope the package clear to a known set (`wt`, `ct`, `gt`, `crt`, `t`, `cosmetics_tweaker`) and leave every other mod alone.

## 0.10.11-dev (2026-04-29) — Remove stale forge draw hooks
### Fixed
- **Mod load errors**: Four `mod:hook_safe` calls targeting `HeroWindowWeaveForgeOverview.draw`, `HeroWindowWeaveForgePanel.draw`, `HeroWindowWeaveForgeBackground.draw`, `HeroWindowWeaveProperties.draw` failed at startup — Fatshark removed the `draw` methods on these classes in a prior patch. The hooks were debug instrumentation for the defunct `forge_dump` command. Removed.

## 0.10.21-dev (2026-04-29) — Kerillian spear+shield H2 fix
- Removed erroneous `attack_swing_heavy_down_right` → `attack_swing_heavy_down` from `_3p_remap_deus_to_spear_shield`. The elf's native spear+shield SM uses `attack_swing_heavy_down_right` for its own H2 release — the remap was overriding a natively-working event with one that produces no animation.

## 0.10.20-dev (2026-04-29) — Kerillian greatsword grip tuning
- Z-offset for `es_2h_sword` and `wh_2h_sword` on `we_*` set to `{0, 0, -0.12}` — `-0.25` was overcorrection, `-0.07` was imperceptible.

## 0.10.19-dev (2026-04-29) — Kerillian greatsword grip offset (larger)
- Z-offset for `es_2h_sword` and `wh_2h_sword` on `we_*` increased to `{0, 0, -0.25}` — previous `-0.07` was not noticeable.

## 0.10.17-dev (2026-04-29) — Kerillian greatsword push-attack fix
- Push-attack remap corrected: `attack_swing_down_right` → `attack_swing_heavy` (elf greatsword default heavy release). Previous version used `attack_swing_stab` which didn't match.

## 0.10.16-dev (2026-04-29) — Kerillian greatsword remap refinement
- Changed H1 heavy release remap (`attack_swing_heavy_left_diagonal`) from `attack_swing_heavy` to `attack_swing_left` so Kerillian's H1 release visually matches her L1 swing when wielding Kruber's/Saltzpyre's greatsword.
- Added push-attack remap: `attack_swing_down_right` → `attack_swing_stab`. Push-attack was previously unanimated on Kerillian with the human greatsword.

## 0.9.129-dev (2026-04-28) — Inventory preview now respects scale & grip offset
- Added `MenuWorldPreviewer:equip_item` and `MenuWorldPreviewer:_spawn_item_unit` hooks. The new (post-WoM) inventory preview uses MenuWorldPreviewer instead of HeroPreviewer/GearUtils for character display; the existing in-game scale/offset code never reached those preview units. Now we capture the weapon key from `equip_item` (where it's exposed as the first arg) and apply scale/offset to the unit when it's spawned via `_spawn_item_unit` (where item_data is the weapon TEMPLATE, not the inventory item — so the key isn't directly available there). Per-previewer mapping is weak-keyed so it doesn't pin the previewer in memory.

## 0.9.120-dev (2026-04-28) — Bardin's axe on Kerillian X/Y scale
- Added `dr_1h_axe` scale `{0.85, 0.85, 1}` for `we_*` careers — 15% thinner X/Y, length unchanged.

## 0.9.119-dev (2026-04-28) — Crowbill H1/H3 fix on Bardin
- Added `dr_` override to `one_handed_crowbill`. H1 and H3 used to remap to `attack_swing_heavy` which produces no animation on Bardin's crowbill SM; now they use the elf-sword overhead targets (`attack_swing_charge_left_diagonal` + `attack_swing_heavy_down`). H2 unchanged. Other careers' crowbill behavior preserved via `_default`.

## 0.9.118-dev (2026-04-28) — Bardin grip on Saltzpyre's dual hammers
- Z-offset `{0, 0, 0.15}` for `wh_dual_hammer` on `dr_*`.

## 0.9.116-dev (2026-04-28) — wh_dual_hammer wield-event redirect
- Added `to_dual_hammers_priest` → `to_dual_hammers` redirect for non-Saltzpyre careers. Saltzpyre's dual hammers fire `to_dual_hammers_priest` on wield; this event is missing on Bardin's skeleton, leaving the SM in idle and producing no 3P attack animations. Redirecting to Bardin's native dual-hammers wield event loads his working SM, and since both weapons fire the same chain events, all attacks now animate identically to native.

## 0.9.115-dev (2026-04-28) — Localization: Saltzpyre's dual hammers
- Renamed `Saltzpyre: Dual Hammers` → `Saltzpyre: Dual Skull-Splitters` in all 8 settings entries, matching the Skull-Splitter naming used for the single hammer and hammer+shield variants.

## 0.9.114-dev (2026-04-28) — Heavy chain windup matches release direction
- bw_sword / es_1h_sword on Bardin: H3+ chained heavy charge windup remapped to match the right-swing release direction (was vertical, now right-pose). Visual consistency through long heavy chains.

## 0.9.113-dev — H3+ chain windup added (bw_sword, es_1h_sword)
- Added `attack_swing_charge_left_pose` remap so the third-position heavy in a chain has a visible windup instead of firing native (no animation) on Bardin. Fixes "first heavy loses charge animation" reported in chained heavy sequences.

## 0.9.111-0.9.112-dev — Elf sword H3 fix
- Added `attack_swing_heavy_down_right → attack_swing_heavy_down` and `attack_swing_charge_right_diagonal_pose → attack_swing_charge_left_diagonal` to `we_1h_sword`. The elf sword has 3 distinct heavy event pairs; H3's release is now vertical to match H1.

## 0.9.108-0.9.110-dev — Cross-career H1 fixes (bw_sword, es_1h_sword, wh_1h_falchion)
- Differentiated the two heavy variants in each weapon's chain on Bardin: one variant routed to elf-H1 vertical, the other to elf-H2 right swing. Falchion got a `dr_` override so non-Bardin careers keep their existing `_default` remap unchanged.
- Added grip Z-offset `+0.05` for `bw_sword` and `es_1h_sword` on Bardin (matching the elf sword fix in 0.9.105).

## 0.9.106-0.9.107-dev — Initial bw_sword H1 redirect, scoped to Bardin
- Added `bw_sword` key remap (charge → vertical windup, release → vertical heavy) on cross-career, then scoped to `dr_` only so other careers aren't unintentionally affected.

## 0.9.105-dev — Bardin grip Z-offset
- Z-offset `+0.05` added for `we_1h_sword` (Kerillian's sword) when wielded by Bardin to fix grip riding too high. Coordinate convention discovered: weapon-local Z axis is along the blade.

## 0.9.102-0.9.104-dev — Elf sword heavy chain on Bardin
- `we_1h_sword`: H1 charge `attack_swing_charge_down → attack_swing_charge_left_diagonal`, H2 release `attack_swing_heavy_left_up → attack_swing_heavy_right`, H2 charge `attack_swing_charge_left → attack_swing_charge_right_pose`. L1 charge gains a windup as a side effect (same source event).

## 0.9.96-dev — Saltzpyre flail push-attack fix
- Narrow native-wielder redirect: on `es_1h_flail` + career prefix `wh_*`, `attack_swing_right` → `attack_swing_right_diagonal`. Vanilla `attack_swing_right` produces no visible animation on Saltzpyre's flail SM. The user explicitly authorized this native-wielder modification after `wt force3p` confirmed the vanilla event was broken.

## 0.9.93-dev — Crowbill L2 fix on Kruber
- Removed `attack_swing_left → attack_swing_down` from the crowbill `_default` remap. L2 was collapsing into L1's vertical; native `attack_swing_left` plays a right swing on Kruber's crowbill SM (verified via `wt force3p`).

## 0.9.92-dev — Flaming flail H1 native overhead
- Removed all template-level remaps for `one_handed_flails_flaming_template`. H1 charge `attack_swing_charge_down` and release `attack_swing_heavy_down` fire natively as the correct overhead on Bardin. Earlier versions remapped them and broke the H1 visual.

## 0.9.88-0.9.91-dev — Cross-career flail (Saltzpyre's flail) and flaming flail H2
- `es_1h_flail` on non-Saltzpyre: H1 release (`attack_swing_left`) and H2 release (`attack_swing_heavy_left`) → `attack_swing_heavy`. Direct `func()` calls in the hook (remap-table corrupts the SM for these events — same pattern as billhook `stab_02`).
- `bw_1h_flail_flaming` on non-Sienna: only H2 release (`attack_swing_heavy_left`) needs the same redirect; H1 fires natively as the correct overhead.

## 0.9.89-dev — Husk-safety for the flail redirect
- Added `_unit_career_name` helper using `Managers.player:owner(unit)`. The flail direct-redirect now gates on `is_local` AND uses the unit-owner career, so it only modifies the local player's flail when the local player is non-Saltzpyre. Husks of other players using non-flail weapons no longer have their `attack_swing_left` events hijacked.

## 0.3.0-dev (2026-04-24)

### Added: Cross-character 1H weapon unlocks for all 20 careers

Added 8 base 1H weapons that share compatible animations across all characters:
- `es_1h_sword` (Kruber's Sword) — all non-Kruber careers
- `es_1h_mace` (Kruber's Mace) — all non-Kruber careers
- `bw_sword` (Sienna's Sword) — all non-Sienna careers
- `wh_1h_falchion` (Saltzpyre's Falchion) — all non-Saltzpyre careers
- `dr_1h_axe` (Bardin's Axe) — all non-Bardin careers
- `wh_1h_axe` (Saltzpyre's Axe) — all non-Saltzpyre careers
- `we_1h_sword` (Kerillian's Sword) — all non-Kerillian careers
- `dr_1h_hammer` (Bardin's Hammer) — all non-Bardin careers

### Added: Shield weapons, spears, and career-specific unlocks

- `dr_shield_hammer` (Bardin's Hammer & Shield) — all Kruber careers
- `es_mace_shield` (Kruber's Mace & Shield) — all Bardin careers
- `es_2h_heavy_spear` (Kruber's Spear) — Foot Knight, Grail Knight
- `we_1h_spears_shield` (Kerillian's Spear & Shield) — Waystalker, Shade, Sister of the Thorn, Grail Knight
- `es_halberd` (Halberd) — Grail Knight
- `we_crossbow_repeater` (Volley Crossbow) — Waystalker, Handmaiden, Sister of the Thorn

### Changed: Settings menu restructured

VMF settings menu reorganized into Melee > Character > Career and Ranged > Character > Career hierarchy. Each weapon is an individual checkbox (all off by default).

## 0.2.1-dev (2026-04-24)

### Added: Bretonnian Sword & Shield for Mercenary

Added `es_sword_shield_breton` unlock for `es_mercenary`.

## 0.2.0-dev (2026-04-24)

### Fixed: `BackendUtils.can_wield_item` hook error on every load/toggle

**Symptom:** VMF logs `[MOD][wt][ERROR] (hook): trying to hook function or method that doesn't exist: [BackendUtils.can_wield_item]` each time the mod loads or is toggled.

**Root cause:** `BackendUtils.can_wield_item` does not exist as a hookable method at any point during the weapon_tweaker's lifecycle. The old monolithic tweaker happened to load at a time when it was available, but as a separate Workshop mod the timing is different.

**Investigation:** Tried multiple approaches — string-form hooks (`mod:hook("BackendUtils", ...)`), deferred hooks in `mod.update` with `rawget` and metatable checks — none worked because the method genuinely isn't hookable for this mod.

**Fix:** Removed the `BackendUtils.can_wield_item` hook entirely. Per the AnyWeapon mod (reference implementation), this hook is unnecessary — weapon eligibility is controlled by modifying `ItemMasterList[weapon_key].can_wield` directly (which `apply_weapon_unlocks` already does). The `ItemGridUI._on_category_index_change` hook handles inventory UI filtering.

**Rule of thumb:** Don't hook `BackendUtils.can_wield_item`. Modify `can_wield` lists on `ItemMasterList` entries directly.

### Fixed: Missing localization keys for mod settings

Added localization entries for `kruber_weapons`, `es_mercenary_weapons`, `unlock_es_mercenary_dr_1h_axe`, `debug_group`, and `enable_weapon_debug_logging`. Naming convention follows old tweaker style (e.g. "Axe (Bardin)" not "Unlock Dwarf 1H Axe").

### Added: Version logging

Mod now logs `Weapon Tweaker v<version> loaded` on init so the running version can be verified in the console log.

### Fixed: Deploy workflow

`deploy_all.ps1` now deploys directly to Workshop content folders (e.g. `552500/3712896117`) for hot reload during development, in addition to `upload/content` for Workshop uploads. The fake local install (ID `9000000002`) approach was removed — the game loads from the real Workshop folder.
