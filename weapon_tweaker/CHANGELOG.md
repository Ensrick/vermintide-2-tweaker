# Weapon Tweaker Changelog

## 0.12.14-dev (2026-05-09) — Authentic Brace: 2x penetration
- Added: `wt_authentic_pistol` damage profile clone now halves `cleave_distribution.attack` and `cleave_distribution.impact` from shot_sniper's vanilla 0.3/0.3 → 0.15/0.15. Each target consumes half the cleave power, so the projectile passes through roughly twice as many enemies. Vanilla shot_sniper penetrates ~3 targets; Authentic Brace shots now penetrate ~6.
- Implementation lives in `_wt_clone_shot_sniper_no_dropoff()` alongside the dropoff-flattening pass — runs once at module init when the toggle is on, registered in `NetworkLookup.damage_profiles` like before. No new network surface area.

## 0.12.13-dev (2026-05-09) — Authentic Brace: kill fast_shot rapid-fire path
- Fixed: holding right-click and clicking after reload (or other action transitions) could put the brace into `action_one.fast_shot`, whose `allowed_chain_actions` self-chain at `start_time = 0.25` — halved to 0.125 by the v0.12.12 2x speed pass, that's ~8 shots/sec rapid-fire. v0.12.10's action_two.default mutation removed the obvious vanilla path (action_two → fast_shot at lines 303/309 of `brace_of_pistols.lua`), but at least one path the user found still reached fast_shot.
- Fix: defensive walk of every sub-action's chain table — any chain entry whose `sub_action == "fast_shot"` is rewritten to `"default"`. Touches fast_shot's own self-loop (lines 132/144 of the brace template), so even if some unaccounted-for path lands the player in fast_shot, the chains exit to single-shot after one shot. Belt-and-suspenders: also rewrites any other action's chains that happen to point at fast_shot. Done as new step (6) in `_apply_authentic_brace_mode`, before the 2x-speed pass (now step 7), so the speed-up sees the fixed chain entries.

## 0.12.12-dev (2026-05-09) — Authentic Brace: hide off-hand pistol, 8-round cap, 2x action speed
- Fixed: in 3P, Kruber's repeater swap left the **left-hand brace pistol** still rendering, clipping through the repeater. The right-hand 3P swap (in `GearUtils.spawn_inventory_unit` hook) only fires for `hand == "right"`. Hooking the spawn for the left hand and hiding it isn't sufficient because `SimpleInventoryExtension.show_third_person_inventory` (`simple_inventory_extension.lua:1014-1075`) flips visibility back to `true` on every wield. New approach: post-hook `show_third_person_inventory` and force `equipment.left_hand_wielded_unit_3p` invisible whenever the wielded item is `wh_brace_of_pistols` and the wielder's career starts with `es_` (Kruber). Mirrors the visibility-group branching vanilla uses so it applies to whichever path the unit was rendered through. Active regardless of the authentic-brace toggle — the left pistol is unwanted on Kruber whether or not the brace is "authenticated".
- Changed: `Authentic Brace of Pistols` ammo cap reduced 12 → 8. `ammo_per_clip = 8`, `ammo_per_reload = 8`, `max_ammo = 8`. Matches the brace's "8 pistols on the bandolier" cosmetic. No-reserve / no-per-shot-reload behavior from v0.12.8 is unchanged.
- Added: 2x action speed when the toggle is ON. Walks `Weapons.brace_of_pistols_template_1.actions[*][*]` and halves `total_time`, `total_time_secondary`, `fire_time`, `minimum_hold_time`, `cooldown`, `reload_time`, and every `allowed_chain_actions[*].start_time`. `0` and `math.huge` are skipped (preserves "instant" and "hold-forever" semantics). Applied last in `_apply_authentic_brace_mode` so the new aim action's fields from step (2) (`minimum_hold_time = 0.3`, `cooldown = 0.3`) get halved too — zoom snaps in/out at 0.15s.

## 0.12.11-dev (2026-05-09) — Fix Authentic Brace zoom crash in 3rd-person mode
- Fixed: right-click aim crashed in 3rd-person mode at `camera_manager.lua:387` (`attempt to index field 'node' (a nil value)`). v0.12.10 set `default_zoom = "first_person_node"` on the aim action. `GenericStatusExtension.set_zooming` (`generic_status_extension.lua:1519`) appends `_third_person` to the camera name when 3P mode is on, producing `"first_person_node_third_person"` — which doesn't exist in the camera tree. `CameraManager.set_camera_node` then constructs `next_node = { node = tree.nodes[node_name] }` with `node = nil` and crashes when it dereferences it later in the function.
- Fix: clear `default_zoom` (set to `nil`). Engine default is `"zoom_in"`, which has both `zoom_in` and `zoom_in_third_person` defined in `camera_settings.lua:18-19` — works in either camera mode. Vanilla Empire handgun also omits this field for the same reason; matching that prior art.
- Compatible with general_tweaker's third-person camera toggle. Right-click in 3P now zooms the over-shoulder camera in just like the handgun does.

## 0.12.10-dev (2026-05-09) — Fix Authentic Brace right-click crash (lookup_data preservation)
- Fixed: right-click on the brace with the toggle ON crashed at `action_utils.lua:834` (`attempt to index field 'lookup_data' (a nil value)` in the user's runtime, line 927 in their build). v0.12.9 replaced `Weapons.brace_of_pistols_template_1.actions.action_two.default` with a freshly-constructed table — but at game load `weapons.lua:312` walks every weapon template and attaches `lookup_data = { item_template_name, action_name, sub_action_name }` to each sub-action. `ActionUtils.resolve_action_selector` dereferences that field on every action transition; a fresh table without it crashed on the first right-click.
- Fix: mutate the existing `action_two.default` table in place instead of replacing it. Strip the dummy/lock-target fields (`anim_event`, `anim_end_event`, `anim_end_event_condition_func`, `spread_template_override`, `buff_data`) and overwrite the rest with the aim-action config. `lookup_data` and any other engine-attached metadata stays attached. End-user behavior identical to the v0.12.9 intent: handgun-style FOV zoom on right-click, no animation.

## 0.12.9-dev (2026-05-09) — Authentic Brace: right-click is now handgun-style zoom (no anim)
- Changed: `action_two.default` is now a clean optical zoom instead of being disabled outright. v0.12.6 left it as a dead `kind="dummy"` (lock-target pose, fast-shot mode) with `condition_func = always_false` to short-circuit it; v0.12.9 replaces it with a fresh `kind="aim"` action that triggers the engine's standard zoom path (`set_zooming(true, default_zoom)` in `action_aim.lua:134`) with `default_zoom = "first_person_node"` — same zoom the Empire handgun uses on right-click.
- No animation: `anim_event` and `anim_end_event` are deliberately omitted. The brace's state machine (`dual_pistol`) doesn't have `to_zoom`/`to_unzoom` events so any anim would be a missing-event warning anyway, and the user wanted "no ADS animation, just a zoom" specifically. The shoulder stays at hip; the camera FOV tightens.
- Chain actions: while zoomed, `action_one` (left-click) still fires the regular shot, `weapon_reload` and `action_wield` still chain — same set the handgun exposes. `fast_shot` and the lock-target pose are unreachable now (action_two no longer leads to them).
- `condition_func` mirrors the handgun: aim is denied if `total_remaining_ammo <= 0`, so an empty brace can't pretend to zoom. `unzoom_condition_function` follows the standard "don't unzoom on interrupting action" idiom.
- `_disable_action` (the always-false sentinel) is still in use for `weapon_reload.default` — only the action_two patch path changed.

## 0.12.8-dev (2026-05-09) — Authentic Brace: no reload animation between shots
- Changed: with `Authentic Brace of Pistols` ON, ammo is now `ammo_per_clip = 12 / ammo_per_reload = 12 / max_ammo = 12` instead of `1 / 1 / 12`. The whole 12-round pool lives in the clip, reserve is zero. Player clicks → fires → clicks → fires straight through 12 shots with no reload animation between any of them.
- How it works: `weapon_reload.auto_reload.condition_func` (`brace_of_pistols.lua:475`) returns `ammo_count() == 0 AND can_reload()`. With clip == max_ammo, the clip is non-empty until the very last shot, so the auto-reload chain — still wired in `action_one.default.allowed_chain_actions` — never gates true and the animation never plays. After the 12th shot, `can_reload()` is also false (reserve=0), so even the empty-click moment doesn't trigger an animation. Effectively the brace becomes a 12-round magazine that just runs out when empty (until ammo pickup).
- Trade-off: starting reserve goes from 11 to 0. Total ammo capacity is unchanged at 12 — you're still firing the same number of shots per ammo refill, just with all of them immediately accessible instead of staged through a chamber.

## 0.12.7-dev (2026-05-09) — Authentic Brace damage profile NetworkLookup fix
- Fixed: `Authentic Brace of Pistols` toggle silently did nothing in v0.12.6. The cloned damage profile `wt_authentic_pistol` was added to `DamageProfileTemplates` but never registered in `NetworkLookup.damage_profiles`. That lookup is built once at game-load (`network_lookup.lua:2203`) and frozen with an `__index` metatable that errors on unknown keys (`:2356`); `PlayerProjectileUnitExtension._init` (`:92`) does `NetworkLookup.damage_profiles[impact_data.damage_profile]` at every projectile spawn, so every brace shot threw and the firing path bailed out before any damage was applied — making the entire toggle invisible in-game.
- Fix: mirror the CWV pattern (`character_weapon_variants.lua:1364`) — after inserting the clone into `DamageProfileTemplates`, also `rawset` the key into `NetworkLookup.damage_profiles` at both `#tbl+1` (numeric → string) and `[key]` (string → numeric) so projectile spawn finds a valid network ID.
- Spread template clone (`wt_authentic_brace_of_pistols_spread`) didn't need the same treatment — `SpreadTemplates` isn't in `NetworkLookup` and is read by-reference at fire time.
- All other v0.12.6 patches (ammo_data clip/reload/max, `weapon_reload.default` condition_funcs, `action_two.default` ADS gate, `ignore_shield_hit` per sub-action) were already applying correctly; only the damage-profile path was broken.

## 0.12.6-dev (2026-05-09) — Authentic Brace of Pistols toggle
- Added: new `Weapon Overrides → Authentic Brace of Pistols` VMF setting (default OFF). When ON, patches `Weapons.brace_of_pistols_template_1` in place at mod init with five behavior changes that turn the brace into a flintlock-style single-shot pistol:
  - **Damage**: every firing sub-action's `impact_data.damage_profile` switches from `shot_carbine` to `wt_authentic_pistol` (a clone of Kruber's handgun's `shot_sniper` with the near→far dropoff flattened — full damage at all ranges). Plus `ignore_shield_hit = true` on the firing sub-actions, mirroring the handgun's shield-break behavior.
  - **No ADS / rapid-fire**: `action_two.default.condition_func` returns false, so right-click no longer enters lock-target mode. The `fast_shot` chain it gates is unreachable, leaving only the single-shot left-click.
  - **No manual reload**: `weapon_reload.default` `condition_func` and `chain_condition_func` both return false. The `auto_reload` chain (`auto_chain = true`) still fires automatically from action_one and refills the chamber after each shot — same pattern as throwing axes / bows.
  - **Ammo**: `ammo_per_clip = 1`, `ammo_per_reload = 1`, `max_ammo = 12` (vanilla: clip 12 / reload 2 / max 30). One shot in the chamber, auto-loads the next from a 12-round reserve.
  - **Spread**: `default_spread_template` switches to `wt_authentic_brace_of_pistols_spread`, a clone of `SpreadTemplates.brace_of_pistols` with every `max_pitch` / `max_yaw` / `immediate_pitch` / `immediate_yaw` scaled by 1.087 (~8% wider = ~8% less accurate). Recursive scale walk handles the nested `continuous` / `immediate` / per-stance leaves.
- Toggle requires a restart to apply or revert — the patches are applied in place to the global `Weapons.brace_of_pistols_template_1` and there's no snapshot of vanilla state to restore from.
- Affects every wielder of the brace (Saltzpyre native + Kruber via WT cross-access). The 3P unit swap on Kruber is independent of this toggle and continues to work as before.

## 0.12.5-dev (2026-05-09) — Brace of Pistols 3P-swap package fix
- Fixed: Kruber equipping `wh_brace_of_pistols` crashed with `[Script Error]: Unit not found` when the brace-3P-swap hook tried to spawn the Empire repeater rifle 3P unit (crash GUID d9e1d3d3). The repeater unit's per-unit package isn't pre-loaded by the brace's vanilla inventory package — Saltzpyre never needed it because his brace 3P stays the brace, and Kruber's other career packages don't share assets with Saltzpyre's repeater-rifle pool.
- Fix mirrors the CWV Tuskgor-Javelin pattern (`feedback_cwv_cross_character_unit_packages.md`): force-load the repeater 3P unit at WT mod init via `Managers.package:load(unit_path, "wt_brace_repeater_3p", nil, async=true, prioritize=true)`. Stingray treats the unit path as a synthetic per-unit package, same way `PickupPackageLoader` does — by the time any equip flow runs, the resource is loaded and `spawn_local_unit_with_extensions` finds it.
- Defensive guard: the swap hook now checks `Managers.package:has_loaded(_BRACE_REPEATER_3P_UNIT, "wt_brace_repeater_3p")` before attempting the spawn, falling back to vanilla brace 3P unit if the load hasn't completed yet (rare race during very-early equip before the async load lands).

## 0.12.4-dev (2026-05-08) — Adventure trait pool toggles + Chaos Wastes traits
- Added: new collapsible `Weapon Traits (Adventure)` group in the VMF settings with four sub-groups:
  - `Adventure Melee Traits` — checkboxes for the 6 vanilla melee traits (Swift Slaying, Parry, Off Balance, Heroic Intervention, Resourceful Combatant, Opportunist). All default ON.
  - `Adventure Ranged Traits` — checkboxes for the 8 unique vanilla ranged traits across the `ranged_ammo` and `ranged_heat` pools (Inspirational Shot, Scrounger, Conservative Shooter, Resourceful Sharpshooter, Hunter, Barrage, Thermal Equalizer, Heat Sink). All default ON.
  - `Chaos Wastes Melee Traits` — 15 CW traits (Shockwave, Armor Breaker, Shield of Isha, Bloodthirst, Headhunter, Home Run, Shield of Splinters, Serrated Blade, Crescendo Strike, Follow Up, Always Blocking, Big Swing Stagger, Crit Chain Lightning, Collateral Damage, melee Heal on Crit). All default OFF.
  - `Chaos Wastes Ranged Traits` — 5 CW ranged-only traits (Refilling Shot, Piercing Projectile, Extra Shot, Ranged Crit Explosion, Ammo Pickup Reload Speed). All default OFF.
- Mechanism: rewrites `WeaponTraits.combinations[melee/ranged_ammo/ranged_heat/trollhammer_torpedo]` in place to reflect the toggles. Existing CW traits are already in `WeaponTraits.traits` and `BuffTemplates` (merged at game load by `weapon_traits_morris.lua`) — they only failed to appear in adventure crafting because the vanilla pools didn't list them.
- UI gating: the two `Chaos Wastes …` groups are stripped from the widget tree when `crafting_in_modded` is not installed (mirrors the existing `_strip_cwv_widgets` pattern). The runtime always honours stored values regardless of cim presence.
- Lifecycle: trait filters re-apply on `on_setting_changed` (any `trait_*` or `cw_trait_*` id) and on `on_game_state_changed`. `on_disabled` reverts the pools to a snapshot captured on first apply.
- Empty-pool safety: if every toggle in a pool ends up off, the pool falls back to the captured vanilla snapshot rather than leaving cim's reroll with nothing to pick.
- Cross-mod contract: `crafting_in_modded` already reads `WeaponTraits.combinations[trait_table]` dynamically (no hardcoded keys) so weapon_tweaker's mutations propagate automatically. Documented this contract above `_reroll_traits` in `cim/standard_forge.lua` to lock in the design.

## 0.12.3-dev (2026-05-08)
- Wired: `wh_brace_of_pistols` checkbox in `_data.lua` for all 4 Kruber career ranged groups + matching `_localization.lua` labels ("Saltzpyre: Brace of Pistols"). v0.12.2 added the unlock to `weapon_unlock_map` but missed the UI checkbox definitions — without those the unlock UI didn't surface the option, so the user couldn't actually toggle it on. Default OFF (per the existing pattern for cross-character ranged weapons).
- Removed: `unlock_es_*_dr_handgun` checkboxes for all 4 Kruber careers + the `dr_handgun` entry in each Kruber career's `weapon_unlock_map` list + the matching localization entries. Per user — Bardin's Handgun ("rifle") was a cross-character cosmetic curiosity that the user doesn't want surfaced as a Kruber option. Bardin's natives (`dr_ranger`, `dr_ironbreaker`) and the other Bardin careers' lists are unchanged.

## 0.12.2-dev (2026-05-08) — Brace of Pistols on Kruber (migrated from CWV)
- Added: `wh_brace_of_pistols` cross-access on all 4 Kruber careers (`es_mercenary` / `es_huntsman` / `es_knight` / `es_questingknight`) in `weapon_unlock_map`. Kruber can now equip Saltzpyre's brace via the standard wt unlock UI.
- Added: 3P unit swap hook on `GearUtils.spawn_inventory_unit`. When a Kruber career equips `wh_brace_of_pistols`, the brace's 3P body unit is destroyed and replaced with the Empire repeating handgun mesh (`wpn_emp_handgun_repeater_t1_3p`). The 1P side keeps the brace cross-arm fire animation, so the user sees the brace in first-person but other players (and the inventory preview) see Kruber wielding a repeater. Pcall-wrapped: any swap failure returns vanilla units unchanged → equipping never breaks because of this hook.
- Added: base `brace_of_pistols_template_1` patches scoped to Kruber careers — `wield_anim_career_3p` for `es_*` → `to_repeating_handgun` (Kruber's vanilla repeater wield SM), and per-action `anim_event_3p` remap for `special_action` (the brace's fire-all-8-pistols finisher) → `attack_shoot_fast` (closest repeater clip; the special_action event isn't authored on Kruber's repeater SM). Saltzpyre native wielders fall through unchanged.
- Migrated from `character_weapon_variants` v0.1.189 — the previous `cwv_es_brace_repeater` standalone variant + `_cwv_3p_unit_override_swap` infrastructure has been removed from CWV. Same end-user behavior, but lives on the vanilla brace cross-access path now (no separate inventory item).

## 0.12.0-dev (2026-05-05) — Crafting subsystem split out into Crafting in Modded mod
The entire Athanor crafting subsystem (~1800 lines: NetworkLookup patch, forge persistence, Athanor UI hooks, BackendInterfaceWeavesPlayFab redirects, HeroWindowWeaveForgeWeapons hooks, `wt forge*` console commands, `wt craft_dump` command, `forge_hotkey` keybind) has been moved into a new sibling mod, `crafting_in_modded` (internal ID `cim`). Weapon Tweaker now focuses solely on cross-career weapon unlocks, animation remapping, and scale/offset.

Migration note: weapons crafted under prior versions of `wt` are saved under the `wt` namespace and will not be migrated to `cim`. They are session-only artifacts and will be lost on the upgrade.

## 0.11.20-dev (2026-05-05) — Deduplicate crafting weapon list
- Crafting menu now deduplicates entries by `display_name` — no more duplicate weapons in the list.
- Excluded `promo` rarity items (player's own crafted weapons) from appearing as craft templates.
- Removed `backend_id` lookup from list population (unnecessary for a craft template catalogue).

## 0.11.19-dev (2026-05-05) — Fix startup rehook warnings
- Merged duplicate `HeroPreviewer.equip_item` hook_safe registrations into one (removed dead debug probe).
- Merged duplicate `BackendManagerPlayFab._create_interfaces` hook_safe registrations via forward-declared `_athanor_inject_all`.
- Eliminates two `[WARNING] Attempting to rehook active hook` messages on startup.

## 0.11.18-dev (2026-05-05) — Fix crafted items treated as MIL templates
- Crafted (promo) weapons now inject via `backend_mirror:add_item()` instead of MoreItemsLibrary. Fixes: template-style gray background, blocked cosmetic editing.
- Added `_athanor_inject_item` / `_athanor_inject_all` functions for promo item lifecycle.
- `_forge_inject_all` now skips promo items (handled by Athanor path instead).
- Persistence: `_forge_save` now stores `rarity` and `traits` array.
- Weapon list: cleared "Magic Level" / "1800" power text from craft template entries.
- Added `wt craft_dump` diagnostic command for rarity/localization/backend debugging.

## 0.11.17-dev (2026-05-02) — Dual axes: distinct light chain animations
v0.11.15's light remaps collapsed L1, L3, L4 onto the same dual_hammers `attack_swing_left` (L1 swing), making 3 of the 5 lights look identical. Spread them across all 5 dual_hammers light anim_events instead:
- L2 release `attack_swing_right_diagonal` → `attack_swing_left` (dual_hammers L1)
- L3 release `attack_swing_left` → `attack_swing_down` (dual_hammers L2)
- L4 release `attack_swing_right` → `attack_swing_up` (dual_hammers L4)
- L5 release `attack_swing_down` → `attack_swing_stab` (dual_hammers L5)
- L1 release `attack_swing_left_diagonal` left native — plays as dual_hammers L3 swing.

Heavy chain unchanged (user confirmed perfect in v0.11.15).

## 0.11.15-dev (2026-05-01) — Dual axes: per-attack remaps to dual-hammers SM
Animlog from v0.11.13 dr_ranger play showed all attack events firing without `[MISSING]` tags but several producing no visible 3P animation — the dual-hammers SM (loaded by the wield redirect) doesn't have transitions for dual-axe-specific events. Added template-based remaps in `_3p_template_remaps[dual_wield_axes_template_1]` for the 5 problematic events:
- `attack_swing_charge_diagonal` → `attack_swing_charge_left` (L3 + H3 charge windup)
- `attack_swing_heavy_right` → `attack_swing_heavy_right_diagonal` (H1 release)
- `attack_swing_heavy` → `attack_swing_heavy_down` (H2 release)
- `attack_swing_right_diagonal` → `attack_swing_left_diagonal` (L2)
- `attack_swing_right` → `attack_swing_left` (L4)

Per-career entries for `dr_ironbreaker` / `dr_ranger` / `dr_engineer`; `dr_slayer` has no entry so `_resolve_template_remap` returns nil and native dual-axes animations play. Targets are the dual_hammers template's anim_events — `Unit.has_animation_event` was TRUE on the original events too (per memory rule), so visual confirmation is the only test that matters.

## 0.11.13-dev (2026-05-01) — Dual axes on Bardin's non-Slayer careers
- Added `to_dual_axes` → `to_dual_hammers` redirect for non-`dr_slayer` careers. `dr_dual_wield_axes` is already unlocked for Ironbreaker/Ranger/Engineer in `weapon_unlock_map`, but `to_dual_axes` is the Slayer-only wield event — without this redirect, the 3P SM stays in idle on the other Bardin careers and no attack animations play. Mirrors the v0.9.116 pattern used for `to_dual_hammers_priest`. Slayer is unaffected (matches the prefix and skips the redirect). Per-attack remaps may follow once `wt animlog` reveals which dual-axe-specific events (`attack_swing_charge_diagonal`, `attack_swing_heavy_right`, `attack_swing_heavy`, `attack_swing_right_diagonal`, `attack_swing_right`) don't animate on the dual-hammers SM.

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
