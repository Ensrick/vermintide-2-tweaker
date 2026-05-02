# Tweaker Repo — Aggregated Code Review (2026-05-01, second pass)

Two passes have been completed against this codebase today:

1. **First pass:** eight reviewers ran in parallel — one per active mod plus one for repo-level docs/scripts. Each produced a per-area `CODE_REVIEW.md` and inline `-- REVIEW:` / `-- QUESTION:` / `-- POTENTIAL BUG:` / `-- CLARIFY:` annotations on the source.
2. **Second pass:** every open item from pass-1 was verified against the current source, fixed where remaining, and the codebase was rebuilt to confirm no syntax errors. This document reflects the post-fix state.

If you pick up this codebase later, start by reading the per-area documents — they have full file:line citations and the inline annotations remain in the source for skimming via `rg "-- (REVIEW|QUESTION|POTENTIAL BUG|CLARIFY):"`.

## Per-area review documents

| Area | Document | First-pass inline comments |
|---|---|---|
| chaos_wastes_tweaker | `chaos_wastes_tweaker/CODE_REVIEW.md` | 37 |
| weapon_tweaker | `weapon_tweaker/CODE_REVIEW.md` | 44 |
| general_tweaker | `general_tweaker/CODE_REVIEW.md` | 12 |
| career_tweaker | `career_tweaker/CODE_REVIEW.md` | 6 |
| cosmetics_tweaker | `cosmetics_tweaker/CODE_REVIEW.md` | 26 |
| character_weapon_variants | `character_weapon_variants/CODE_REVIEW.md` | 24 |
| enemy_tweaker | `enemy_tweaker/CODE_REVIEW.md` | 11 |
| Repo-level docs/scripts | `REPO_REVIEW.md` | scattered |

---

## Fix log

### Pre-second-pass fixes (already in place when second pass started)

**weapon_tweaker v0.11.9:**
- Added `witch_hunter_warrior_priest` to `_3p_state_machine_paths` so `wt sm_probe` covers WP's distinct skeleton.
- `mod.on_game_state_changed` signature reduced to `function()`.
- Re-aligned `wh_priest`-prefixed rows in `_career_anim_redirect` to match sibling column spacing.

**character_weapon_variants v0.1.55–0.1.56:**
- Added `entry.cwv_variant = true` flag in `_build_entry` so sibling mods can skip weapon-name-keyed overrides on cwv variants.
- Mirrored each cwv entry into `ItemMasterList[def.item_key]` after MIL `add_mod_items_to_local_backend`, fixing the `world_hero_previewer.lua:674` nil-`item_data` crash on equip.

**cosmetics_tweaker v0.7.84:**
- Gated `GearUtils.create_equipment` and `LootItemUnitPreviewer.spawn_units` hooks on `not item_data.cwv_variant` so `_breton_sword_thiccc` (and any future weapon-name-keyed override) doesn't leak onto cwv variants whose inherited `item_data.name` matches a base weapon.

### Second-pass fixes

**chaos_wastes_tweaker v0.3.1-dev:**
- **Campaign potions renormalization** (HIGH-leverage MED). The earlier ~0.125-each clone weights pushed total `Pickups.deus_potions` weights to ~1.375; sampler picks `random[0,1)` so entries past cumulative 1.0 were unreachable. Now all weights in the group are renormalized to sum to 1.0 during `populate_pickups`, then restored to vanilla on exit. Inserts use the entries' native `Pickups.potions` weights and the renormalization makes everything reachable.
- **Dead code deletion**: removed `chaos_wastes_tweaker_boon_keys.lua` (174 lines, never `require`d). Static localization in `_localization.lua` replaced the runtime-loc-generation pipeline that this file fed.

**weapon_tweaker v0.11.11-dev:**
- **HIGH — `_safe_has_anim` forward-reference fix.** Moved the function definition above `_try_suffix_redirect`. Lua 5.1 was resolving `_safe_has_anim` at line 311 to a `nil` global (defined at 779) — crash whenever any career hit the suffix-redirect path. 6th instance of `feedback_lua_forward_reference.md`'s exact pattern.
- **MED — `MenuWorldPreviewer.equip_item` hook re-targeted to `HeroPreviewer.equip_item`.** The method is inherited (not directly defined on the subclass), so VMF's string-form hook on the subclass was unreliable. Hooking the parent guarantees both classes' instances trigger it; harmless extra entries from `HeroPreviewer` instances are auto-cleared by the weak-keyed map on GC.
- **MED — `wt forge` rawget guard.** `if not ItemMasterList[item_key] then` was crashifying *itself* on user-typed unknown keys via `__index`. Changed to `rawget` and lifted the lookup.

**general_tweaker v0.2.11-dev:**
- **MED — TP camera sliders wired.** `tp_distance`, `tp_height`, `tp_side_offset` widgets now actually drive `_patch_camera_offset`. Side offset → x; distance → -y (negative pulls camera back); height → z. Zoom variants scale at fixed ratios (60% / 40%) so transitions remain perceptually consistent. `on_setting_changed` re-applies on slider drag.
- **MED — `mission_inventory_enabled` finished.** The `InventorySettings` patch alone unblocked `hero_view` init, but `menu_layouts.in_game.{alone,host,client}` had no inventory button so nothing to click. Now also injects an `interact_open_inventory_chest` / `hero_view_force` entry into all three in-game layouts via `package.loaded["scripts/ui/views/ingame_view_menu_layout"]`. The legacy `menu_access_allowed_in_state` hypothesis from memory was a misdiagnosis (only on `GameModeVersus`).
- **LOW — godmode `add_damage_network_player` hook added.** Player-vs-player damage profiles (area effects, weapon profiles) now also block on `_godmode`. Previously only `add_damage_network` was blocked.
- **LOW — `_tp_reapply_timer` is now time-based** (`dt`-aware) instead of a frame counter that ignored `dt`.
- **LOW — TP tooltip prefix corrected** from legacy `'t tp'` to `'gt tp'`.
- **LOW — Camera offset snapshot + restore.** Snapshots vanilla offsets before mutating; `mod.on_disabled` restores them. Supports clean disable via VMF (the mod is `is_togglable = true`).

**career_tweaker v0.2.5-dev:**
- **MED — `ActionMeleeStart` parry-window hook re-targeted.** Was hooked on `client_owner_start_action` with `self._status_extension` (wrong field; ActionDummy stores it as `self.status_extension`) on a method that doesn't even set `timed_block` (the +0.5 write happens in `client_owner_post_update:65`). Now hooks `client_owner_post_update` with the correct field name. The `t + 1.0` write lands after every original `t + 0.5` write so the window stays extended across ticks.

**cosmetics_tweaker v0.7.86-dev:**
- **MED — `rawget` guards** on the two remaining bare `ItemMasterList[k]` lookups: `apply_cosmetic_unlocks` (cosmetics_tweaker.lua:1154) and `_la_bridge.build_clone_entry` (_la_bridge.lua:92). Both are now safe against keys that don't exist on the user's install (DLC ownership, future-version drift).

**enemy_tweaker v0.2.3-dev:**
- **HIGH — `_apply_preset_to_pacing_keys` preserves `loaded_probs`.** New `_build_loaded_probs(variants)` rebuilds the `LoadedDice.create(weights)` array on the replacement composition. Without this, `LoadedDice.roll_easy(nil)` was crashing the next horde.
- **HIGH — `NetworkLookup.breeds` extended for skeleton breeds.** `_register_skeleton_breeds` now also appends `def.name` to the array part AND sets the reverse string→index mapping. `__index` only fires on GET-of-missing-string-key, so direct assignment is safe post-finalization. Without this, multiplayer serialization of `et_*_skeleton` (17+ call sites) would throw the strict-lookup error.
- **MED — Ambush breed substitution moved to `HordeSpawner.spawn_unit`.** Old hook on `compose_horde_spawn_list` was a no-op (vanilla returns `(sum, sum_a, sum_b)` numbers, not a list). The new per-unit hook substitutes `breed_name` before delegating, catching every spawn path including ambush.

**character_weapon_variants v0.1.57-dev:**
- **LOW — `LootItemUnitPreviewer.spawn_units` backend_id resolution.** Same pattern as `_resolve_cwv_def`: extract cwv key from `item.backend_id` via `^(cwv_.-)_001$` so `_transform_map[cwv_key]` takes precedence over the BASE-key fallback. Latent today (identity scales) but no longer a trap when scales are restored.
- **LOW — `_apply_offset` idempotent guard.** Weak-keyed `_offset_applied` set prevents double-application when both `HeroPreviewer._spawn_item` and `MenuWorldPreviewer._spawn_item` hooks fire (super-call inheritance). Latent today (no variant defines offsets) but a future-proof.

### Third-pass fixes (2026-05-01 evening)

**cosmetics_tweaker v0.7.87 → v0.7.90-dev:** scale system migrated from item-name-keyed to unit-path-keyed.
- v0.7.87: replaced `_weapon_scale_overrides[item.name]` with `_unit_path_scale_overrides[]` (substring match against the resolved skin/item `right_hand_unit` path). New helpers `_resolve_render_unit_path`, `_resolve_factor`, `_apply_unit_path_scale_hand`, `_scale_units(result, item_data, skin)`. All three rendering paths updated.
- v0.7.88: `_spawn_item_post` was iterating `_equipment_units` by numeric `slot_index` and reading `_item_info_by_slot[slot_index]`, but `_item_info_by_slot` is keyed by string slot_type. Walk `_item_info_by_slot` directly and bridge via `info.spawn_data[1].slot_index`.
- v0.7.90: defence-in-depth `not item_data.cwv_variant` gate on `_spawn_item_post` and `LootItemUnitPreviewer.spawn_units`. Hidden debug toggle `cos_thiccc_trace` for diagnostic logging.

**character_weapon_variants v0.1.55 → v0.1.56-dev (recap from pass-1, deferred-to-pass-3 because the unit-path migration in cosmetics required these to land first):**
- v0.1.55: `entry.cwv_variant = true` cross-mod marker contract.
- v0.1.56: mirror cwv entries into `ItemMasterList[def.item_key]` to fix `world_hero_previewer.lua:674` nil-`item_data` crash on equip.

### Open issues (post-third-pass)

**character_weapon_variants — Imperial Longsword still appears thinned in the inventory character preview** despite the v0.7.87 unit-path migration and the v0.7.90 cwv_variant gate. Symptoms:
- In-game (GearUtils path): correct — Imperial Longsword shows at native width, Bretonian Longsword shows thinned.
- Inventory character preview (HeroPreviewer / MenuWorldPreviewer path): Bretonian thinned (correct) BUT Imperial also appears thinned (incorrect).

**Likely culprit:** cosmetics_tweaker's `es_bastard_sword_thiccc` setting still leaks onto the Imperial cwv variant via some path the audit hasn't isolated. Theories: (1) the Imperial's resolved unit path somehow contains the bret pattern in a context we haven't traced, (2) a shared package or mesh substitution swaps the Imperial render to a bret model in the menu only, (3) a different code path (not the three known hooks) applies the scale. The `cos_thiccc_trace` toggle in v0.7.90 will print the resolved paths the menu hook sees — running with that enabled is the next diagnostic step.

**Next steps:** enable `cos_thiccc_trace`, equip Imperial Longsword, open inventory, capture the `[thiccc] preview name=… skin=… right=… left=…` log line. If `right_path` does NOT contain `wpn_emp_gk_sword_`, scaling is coming from outside the audited paths. If it DOES, the resolution chain is producing a wrong path for the cwv item — investigate whether `WeaponSkins.skins[cwv_skin].right_hand_unit` was overwritten somewhere.

### Second-pass documentation fixes

- **`CLAUDE.md`** — character_weapon_variants Workshop ID `(unpublished)` → `3716869446`. The old "deploy_all.ps1 does NOT handle cosmetics_tweaker or character_weapon_variants" claim replaced with the actual current behavior (auto-detects VMB layout).
- **`DEVELOPMENT.md`** — same character_weapon_variants ID fix; enemy_tweaker console prefix `(n/a)` → `enemy_tweaker et_*`.
- **`ANTIGRAVITY.md` moved to `old-backup/`** — described the entire retired SDK pipeline AND contained 3 occurrences of `visibility = "public"` for weapon_tweaker (the exact action that previously got two mods removed-from-community). `old-backup/README.md` updated with a "Stale documentation" section explaining why.

### Build verification

All 7 active mods rebuild clean via VMB after the second-pass edits:

```
chaos_wastes_tweaker      OK
weapon_tweaker            OK
general_tweaker           OK
career_tweaker            OK
cosmetics_tweaker         OK
enemy_tweaker             OK
character_weapon_variants OK
```

### Forward-reference re-audit

Per `feedback_lua_forward_reference.md` (now 6 prior crashes) — every active mod was re-checked.

| Mod | Pass-1 result | Pass-2 result |
|---|---|---|
| chaos_wastes_tweaker | PASS | PASS — `sync_reckless_swings` correctly forward-declared |
| weapon_tweaker | **FAIL** (`_safe_has_anim` at L311 vs L779) | **PASS** — `_safe_has_anim` now defined at L297, before `_try_suffix_redirect` at L302 |
| general_tweaker | PASS | PASS |
| career_tweaker | PASS | PASS |
| cosmetics_tweaker | PASS | PASS |
| character_weapon_variants | PASS | PASS |
| enemy_tweaker | PASS | PASS |

---

## Items still open after the second pass

Items below were either deferred (low-impact, working as-is) or required more design work than fits in this pass. None are confirmed crashes; all are either drift, latent bugs, or polish.

### LOW — chaos_wastes_tweaker
- **40 missing tooltip localizations** for the disable_boon / start_boon talent toggles and a few outliers (`disable_boon_squats_tooltip`, `start_boon_squats_tooltip`, both `deus_power_up_quest_granted_test_01_tooltip`, all 36 talent tooltips). Hovering shows the raw `<setting_id>`. Not a crash — UX polish only.
- **Save-and-restore patterns** in 5 sites (`generate_random_power_ups`, three `apply_weapon_trait_filter` callers, `populate_pickups`) lack `pcall` around `func()`. If `func()` raises mid-call, the global mutation stays in place. Low-risk because the wrapped vanilla functions are well-tested, but a wrapper helper would harden it.
- **Hardcoded array indices** in the Khaine's Fury tweak (`tpl.buff_template.buffs[1]`, `description_values[1]/[3]`). Brittle if FatShark patches reorder these tables.

### LOW — weapon_tweaker
- 6 leftover localization keys from the monolithic Tweaker (`enable_weapon_unlocks_core`, `_runtime_guards`, `_wield_slot_guard`, `_create_equipment_guard`, `_career_action_injection`, `force_bretonnian_shield_unlock`) — orphan, no widget references them.
- 3 keys ARE read by code via `feature_enabled()` (`enable_weapon_animation_redirects`, `_backend_hooks`, `_ui_hooks`) but have NO widget — users can't toggle them. Either add widgets or hardcode the values.

### LOW — cosmetics_tweaker
- **Hat tinting only fires on the in-game body**, not in inventory or hero-selection previewers. Marked "Experimental" so possibly intentional.
- **Fragile `_fields` filter** in the `LootItemUnitPreviewer.spawn_units` hook — only right-only filtering actually works correctly; mixed/left-only field lists misbehave. Today this is fine (only `_breton_sword_thiccc` uses it, right-only) but a future-proof fix would map field names → spawn-order indices explicitly.
- **Captured-but-unused `orig_hook` local** at line 2615.

### LOW — character_weapon_variants
- **CHANGELOG/code drift on Imperial Longsword scales.** v0.1.25 CHANGELOG documents `right_hand_scale = {1.0, 1.0, 1.15}` (base) and `{0.65, 1.0, 0.85}` (veteran), but current code has identity `{1, 1, 1}` on all three entries. Either restore the intended values or remove the field. (The two latent bugs that depended on these — `LootItemUnitPreviewer` lookup and offset double-application — are fixed in the second pass.)

### LOW — career_tweaker
- The `BALANCE_MODS` patch-engine (`apply_balance_mods`/`restore_all_balance_mods`/`_originals`) is currently dormant — both registered mods use hook-based behavior with empty `patches{}`. The framework is kept for future patch-style balance mods. `BALANCE_MODS[*].character` and `.career` fields are display-only; never read by code.
- **`HeroWindowTalentsConsole`** (gamepad UI) is not tracked by the talent-sync refresh; gamepad users may see stale talent UI after a swap. Adventure-pad users only.

### LOW — enemy_tweaker
- Stale `et_status` redirect count, missing-threat-value on mid-session enable (re-enabling adds breeds to `Breeds` without registering threat values, leading to nil arithmetic in `ConflictDirector.calculate_threat_value` if a threat-aware path runs before the next level transition), size multiplier ignored when preset=off, 3 dead `FACTION_*` locals.
- `mod.on_setting_changed` is not host-gated; client setting changes harmlessly mutate `HordeCompositionsPacing` even though spawn decisions are host-authoritative.

### LOW — repo docs
- **TODO.md and ANIMATION_RESEARCH.md** still use the legacy `t` command prefix (`t unstuck`, `t god`, `t probe_3p`) — should be `gt` / `wt`.
- **WORK_ITEMS.md** dated 2026-04-27, predates the VMB migration. Version stickers stale; cosmetics / enemy / cwv sections absent.
- **`.gitignore`** review: `bundleV2/`, `bundleHistory.dat`, `dumps/`, `.vmbrc`, `launcher_screenshot.png` are tracked. Confirm whether each should be ignored.

---

## Memory file to update

`feedback`/project memory entry hypothesizing that `menu_access_allowed_in_state` blocks `mission_inventory_enabled` is a misdiagnosis — that method only exists on `GameModeVersus`, so it doesn't gate adventure/deus. The real blocker was the in-game menu layout, which is now fixed. Update memory so future agents don't chase the wrong fix.

---

## Notes for AI agents working in this codebase

1. **Forward-reference bugs are the #1 source of crashes here (now 6 crashes prevented, 1 caught by this review pass).** Before committing any `.lua` edit, verify each `local <name>` is defined before its first reference — both for variables AND for functions. Lua 5.1 does NOT hoist locals.
2. **Visibility in `itemV2.cfg`:** NEVER set or change without explicit user direction. `chaos_wastes_tweaker` is intentionally `"public"`; everything else is `"private"`. Two prior mods got removed-from-community due to automated public flips — irreversible. `upload_wt.ps1` aborts if it sees `visibility = "public"` as a guardrail.
3. **`ItemMasterList` and `NetworkLookup.weapon_skins` have crashify-on-missing `__index` metamethods.** Always use `rawget(ItemMasterList, key)` when the key may not exist (LA bridge keys, foreign skin keys, post-equip clone backend_ids, cwv variants on users without the dependency). Even `if not ItemMasterList[k] then` is unsafe — the read crashifies before the negation runs. Use `if not rawget(...) then`.
4. **`NetworkLookup.breeds`** has the same strict metatable. To safely add new breeds, append to the array AND set the reverse string→index mapping (see `enemy_tweaker._register_skeleton_breeds` for the canonical pattern). `__index` only fires on GET-of-missing-string-key, so direct assignment after finalize is safe.
5. **Three rendering paths** for any visual override (CLAUDE.md): `GearUtils.create_equipment` (in-game), `HeroPreviewer._spawn_item` (inventory preview), `LootItemUnitPreviewer.spawn_units` (illusion browser). `MenuWorldPreviewer._spawn_item_unit` is NOT usable for per-hand. Skipping any path is a coverage gap.
6. **`MenuWorldPreviewer` extends `HeroPreviewer`** — hooking the same method on both classes fires twice per spawn for MenuWorldPreviewer instances (the super-call dispatches to the parent). Idempotent operations (scale, set-position-from-baseline) survive; additive ones (offset += delta) double. Either hook only the parent and let inheritance fire, or guard with a per-unit applied-state set.
7. **CWV items present as their base weapon in `item_data.key`** (per `feedback_cwv_backend_id_lookup.md`). Always resolve cwv keys via `item.backend_id:match("^(cwv_.-)_001$")` before keyed lookups, or the cwv-specific entry is silently missed.
8. **Hot-reload (Ctrl+Shift+R) is unfixable for `weapon_tweaker` and `cosmetics_tweaker`** — engine-level C++ resource locks. Always do a full game restart for those two.
9. **`mod.on_disabled` should restore any global state mutations** (camera offsets, `Pickups.deus_potions` entries, menu_layouts injections). Most of the mods get this right now, but it's worth checking on every new feature that touches a global table.
10. **Pickup spawn weights must sum to 1.0 within their group.** The sampler in `pickup_system._spawn_spread_pickups` picks `random[0,1)` and breaks on first cumulative ≥ random — entries past cumulative 1.0 are silently unreachable. If you mutate `Pickups.<group>` to add entries, you MUST renormalize the entire group's `spawn_weighting` values, then restore on exit.
