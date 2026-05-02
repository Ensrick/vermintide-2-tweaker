# General Tweaker Code Review (2026-05-01)

Scope: `general_tweaker/` excluding `bundleV2/`. Files reviewed:
- `general_tweaker.mod`
- `itemV2.cfg`
- `resource_packages/general_tweaker/general_tweaker.package`
- `scripts/mods/general_tweaker/general_tweaker.lua`
- `scripts/mods/general_tweaker/general_tweaker_data.lua`
- `scripts/mods/general_tweaker/general_tweaker_localization.lua`
- `CHANGELOG.md`

## Summary

Overall health: solid, small surface area (~408 lines of Lua), no forward-reference issues, hooks follow the project's string-form convention, no obvious crash paths. **Three real bugs**: orphan TP-camera sliders that the user can move with no effect, a misleading tooltip referencing the wrong chat prefix (`'t tp'` instead of `'gt tp'`), and a `mission_inventory_enabled` toggle that is half-implemented (the toggle removes the gate in `hero_view.lua` but the in-mission menu layout still has no button to reach the inventory). Godmode is partial (only one damage path hooked). 12 inline comments added — 4 `POTENTIAL BUG`, 4 `REVIEW`, 4 `CLARIFY`. No `QUESTION`s.

## Confirmed bugs / potential bugs

1. **Orphan TP camera sliders** — `general_tweaker.lua:37`, `general_tweaker_data.lua:21-43`, `general_tweaker_localization.lua:15-32`.
   The widgets `tp_distance`, `tp_height`, and `tp_side_offset` are declared with default values 3.0 / 1.0 / 0.8 and ranges, but `general_tweaker.lua` never calls `mod:get` on any of them. The actual offsets in `_patch_camera_offset()` are hardcoded (`y = -2.5`, `z = 0.5`, etc.). Users can move the sliders without any effect. Either wire `mod:get(...)` into the patch (and re-apply on `on_setting_changed`), or remove the widgets.

2. **`mission_inventory_enabled` is half-implemented** — `general_tweaker.lua:128-160`.
   Patching `InventorySettings.inventory_loadout_access_supported_game_modes` correctly unblocks `hero_view.lua:323`'s early return, BUT the in-mission ESC menu (`scripts/ui/views/ingame_view_menu_layout.lua:428-535`, table `menu_layouts.in_game.<alone|host|client>`) has no `inventory_menu_button_name` / `hero_view_force` entry — only Return, Options, Leave, Quit. So even with the toggle on, there is no UI button to open the inventory mid-mission.
   The `TODO.md` and `project_chaos_wastes_tweaker_ideas.md` memory both blame `game_mode:menu_access_allowed_in_state()` at `ingame_ui.lua:617`. That is a misdiagnosis: that method only exists on `GameModeVersus` (`game_mode_versus.lua:1980`), so the check is skipped for adventure/deus.
   To finish the feature, also `table.insert` an entry like `{ display_name = "inventory_menu_button_name", fade = true, requires_player_unit = true, transition = "hero_view_force", transition_state = "overview" }` into each of `menu_layouts.in_game.alone/host/client` (and the deus equivalents at `ingame_view_menu_layout.lua:688+`).

3. **TP tooltip cites wrong chat prefix** — `general_tweaker_localization.lua:13`.
   `tp_camera_enabled_tooltip` reads "...with the 't tp' chat command." The `t` prefix is the legacy monolithic mod. General Tweaker uses `gt` (DEVELOPMENT.md mod table). Should read `'gt tp'`.

4. **Godmode covers only one damage path** — `general_tweaker.lua:332`.
   The hook only short-circuits `DamageUtils.add_damage_network`. Player-vs-player damage profiles route through `DamageUtils.add_damage_network_player` (`damage_utils.lua:1866`), which is not hooked. Several area effects (and possibly some bot pings) will still bypass godmode. For full invulnerability, also hook `add_damage_network_player` and/or `GenericHealthExtension.add_damage`.

## Open questions

- None. All hooks resolved against verified VT2 source.

## Refactor / cleanup candidates

- **Camera offsets are not restored on disable** (`general_tweaker.lua:65`). `is_togglable = true` allows the user to disable the mod, but `_patch_camera_offset()` mutates `CameraSettings.first_person.over_shoulder.offset_position` (etc.) globally with no snapshot. Disabling the mod leaves the patched offsets in place for the rest of the session.
- **Redundant `_apply_tp` call in `tp` command** (`general_tweaker.lua:113`). `mod:set("tp_camera_enabled", new_val)` triggers `on_setting_changed`, which already calls `_apply_tp(mod:get("tp_camera_enabled"))`. The explicit `_apply_tp(new_val)` after `mod:set` causes a double-apply (idempotent in practice, but redundant). The same minor redundancy exists in the `god` command at `general_tweaker.lua:326-330`.
- **`dump_cosmetics` captures `inventory_icon` but never prints it** (`general_tweaker.lua:264`). Either drop the field or include it in the formatted output line.
- **`_tp_reapply_timer` is a frame counter, not a time counter**. `mod.update(dt)` ignores `dt` and decrements by 1 per call. Works, but the name implies seconds. Consider renaming `_tp_reapply_frames` or switching to dt-based.

## Doc/code mismatches

- Tooltip `tp_camera_enabled_tooltip` says `'t tp'` — should be `'gt tp'`.
- `mission_inventory_enabled_tooltip` says "Allow opening the equipment/loadout screen during adventure, survival, and Chaos Wastes missions." Behaviour-wise the toggle does NOT successfully open anything (see bug #2).
- `tp_distance_tooltip` says "How far behind the character the camera sits." but the slider has no effect (bug #1).
- The block comment at `general_tweaker.lua:21-32` describes the tp implementation faithfully, including the `set_first_person_mode` guard at `player_unit_first_person.lua:907`. Verified accurate.

## Settings coherence

### Orphan setting_ids (declared but never read in code)
- `tp_distance` — widget exists, no `mod:get` call
- `tp_height` — widget exists, no `mod:get` call
- `tp_side_offset` — widget exists, no `mod:get` call

### Settings with read sites
- `tp_camera_enabled` — read in `extensions_ready` hook + `tp` command + `on_setting_changed`
- `godmode_enabled` — initial `mod:get` at line 11, then `on_setting_changed` re-reads
- `allow_duplicate_careers` — read in three `ProfileSynchronizer` hooks
- `mission_inventory_enabled` — read in `_patch_inventory_access`

### Localization coverage
Every `setting_id` in `_data.lua` has a matching key in `_localization.lua`, including all `*_tooltip` companions and group headers (`tp_camera_group`, `gameplay_group`, `mission_inventory_group`). The `mod_description` key used by `_data.lua`'s `description` field is also present.

### Missing localization
- None.

### Unread settings
- `tp_distance`, `tp_height`, `tp_side_offset` (see orphans above).

## Hook patterns

All five hooks use the string-form `mod:hook("ClassName", "method", ...)` convention, matching CLAUDE.md guidance for game classes. None hook `BackendUtils.can_wield_item`. No table-form hooks (so no nil-guard concerns).

| Hook | Target | Style | Notes |
|------|--------|-------|-------|
| `PlayerUnitFirstPerson.set_first_person_mode` | method | string | passes `(self, active, override, unarmed)` correctly |
| `PlayerUnitFirstPerson.extensions_ready` | method | string | calls `func(self, world, unit, ...)` correctly |
| `DamageUtils.add_damage_network` | static | string | hook signature omits `self` — verified static at `damage_utils.lua:1747` |
| `ProfileSynchronizer.get_profile_index_reservation` | method | string | OK |
| `ProfileSynchronizer.try_reserve_profile_for_peer` | method | string | OK |
| `ProfileSynchronizer.is_free_in_lobby` | static | string | hook signature omits `self` — verified static at `profile_synchronizer.lua:860` |

## Mission inventory toggle status

What the code currently does (`general_tweaker.lua:128-160`):
- On init and on every `on_game_state_changed`, calls `_patch_inventory_access()`.
- When `mission_inventory_enabled = true`, sets `InventorySettings.inventory_loadout_access_supported_game_modes.adventure = true`, `.survival = true`, `.deus = true`.
- When false, sets those three keys to nil.

What's missing (verified against VT2 source 2026-05-01):
- The `menu_access_allowed_in_state` blocker hypothesized in TODO.md / `project_chaos_wastes_tweaker_ideas.md` is a non-issue — it only exists on `GameModeVersus`, so adventure/deus skip the check.
- The real blocker is `scripts/ui/views/ingame_view_menu_layout.lua:428-535`. The in-mission `menu_layouts.in_game.<alone|host|client>` tables have no inventory entry. The pause menu in a mission only exposes Return / Options / Leave / Quit. The toggle as written removes the early-return in `hero_view.lua:323` but provides no UI path to actually open the hero view from a mission.
- Likely fix: add an `inventory_menu_button_name` -> `hero_view_force` entry to `menu_layouts.in_game.alone/host/client` (and the matching deus blocks if Chaos Wastes is desired). Patch this from the mod when `mission_inventory_enabled = true`.
- Possible secondary issues to investigate after that: backend item state and ammo/weapon swap restrictions during missions; Chaos Wastes `inn_deus` is the intended modded swap-altar path (per `project_chaos_wastes_tweaker_ideas.md`) and may need a different mechanism (CW weapon pool, not standard backend).

## Console commands

All registered via `mod:command(name, description, fn)` in `general_tweaker.lua`. The `description` is shown by VMF's `/help` and is plain text — no separate localization key is needed.

| Command | Line | Description | What it does |
|---------|------|-------------|--------------|
| `gt tp` | 113 | Toggle third-person camera | Flips `tp_camera_enabled`, calls `_apply_tp(new_val)`, echoes state |
| `gt dump_glossary` | 162 | Dump localized names for heroes, careers, and weapons to log | Iterates `SPProfiles` (skips `empire_soldier_tutorial`), then `ItemMasterList` melee+ranged. Writes via `_write_dump("glossary.txt", ...)` |
| `gt dump_cosmetics [filter]` | 244 | Dump all hats, skins, and frames from ItemMasterList to log | Iterates `ItemMasterList` for `slot_type` in {hat, skin, frame}; optional substring filter on key/careers |
| `gt unstuck` | 295 | Teleport to nearest living teammate | Uses first `HEALTH_ALIVE` teammate; offsets +0.5m on x to avoid stacking |
| `gt god` | 326 | Toggle godmode (invincibility) | Flips `_godmode`, persists via `mod:set`. Hook at line 332 returns 0 damage when local player is the target |
| `gt win` | 348 | Complete the current map | Calls `Managers.state.game_mode:complete_level()` |
| `gt dump_items_by_slot` | 381 | Dump all ItemMasterList slot_type values and counts | Histogram of slot_type values across ItemMasterList |

## Non-obvious things now clarified

- **Why `_tp_reapply_timer = 30` after `extensions_ready`**: We can't set TP immediately on player spawn — the FP system must finish init or the camera ends up half-state. Defer ~0.5s and re-apply.
- **Why a frame counter, not dt-based**: `mod.update(dt)` decrements by 1 per call; `dt` is unused. Functional but confusable.
- **Why hooks omit `self` for `add_damage_network` and `is_free_in_lobby`**: those are static functions in vanilla source (called with `.`, not `:`). VMF passes the same arg list the original was called with.
- **Why `_godmode` is captured into a local at init**: avoids a `mod:get` lookup on every hook fire. `on_setting_changed` keeps it in sync with the saved value.
- **Why `_patch_camera_offset` runs at init (not in a hook)**: `CameraSettings` is a global settings table loaded once; mutating it before the camera system reads from it is sufficient. No re-application needed (except after disable, which the mod does not handle — see Refactor section).

## Dead code

- `dump_cosmetics`: the `icon = item.inventory_icon or "?"` capture (line 264) is never written to output.
- No leftover `print` statements. No commented-out code blocks.
- `_godmode` initial value uses `mod:get(...) or false`; the `or false` is defensive but VMF returns the saved value (or default), so it's effectively `false` already. Harmless.

## Notes for future AI agents

- **Workshop ID 3713619122**, internal mod ID `"gt"`, visibility `"private"` — DO NOT change `visibility` without explicit user instruction (see `feedback_workshop_metadata_user_dictates.md`).
- The mod is now VMB-built (post 2026-05-01 migration). `goto`/`::label::` syntax IS supported (used in `dump_glossary`'s `::continue_hero::`) — earlier SDK builds would not have allowed this.
- `gt.mod` is now `general_tweaker.mod` but still calls `new_mod("gt", ...)` — settings persist across the rename.
- When fixing the `mission_inventory_enabled` toggle, do NOT just attack `menu_access_allowed_in_state` — the actual gate is the menu layout table (`ingame_view_menu_layout.lua:428-535`).
- When wiring the orphan TP sliders, remember to re-apply offsets on `on_setting_changed` (not just at init), and consider snapshotting vanilla offsets so disable + re-enable can restore.
- Do not remove the `pcall` around `set_first_person_mode` / `change_camera_state` in `_apply_tp` — those run during mod boot when the FP extension may not be fully ready.
- The `tp` command flow currently double-calls `_apply_tp` (once explicitly, once via `on_setting_changed`). If you reorganize, keep one path only.
- Hooks in this mod use string-form for game classes — keep this style for consistency with the rest of the project.
