# Weapon Tweaker Code Review (2026-05-01)

Scope: every file in `weapon_tweaker/` except `bundleV2/`.
Reviewer: Senior code reviewer pass on weapon_tweaker.lua (3045 → 3272 lines after comments), weapon_tweaker_backend.lua (188 → 245), weapon_tweaker_data.lua (972 → 999), weapon_tweaker_localization.lua (689), weapon_tweaker.mod, itemV2.cfg, weapon_tweaker.package, CHANGELOG.md.

---

## Summary

The code is mature and battle-tested — many of the complex traps described in the project memory (forward-reference bugs, flail SM corruption, `is_local` fp-unit confusion, non-weapon `to_` events clearing the remap) have been hit and fixed historically. Animation system architecture is correct: 3-layer redirect/career/3P-remap, `_local_fp_unit` early-return preventing 1P interference, force-fire scoping per remap table.

Quality: HIGH for the animation pipeline and weapon-unlocks path. The forge UI / crafting subsystem is more recent (v0.10–0.11) and shows it: more dead code, more user-input ItemMasterList lookups without `rawget`, less defensive guarding.

One **HIGH-severity bug** found: forward-reference bug at `_safe_has_anim` callsite inside `_try_suffix_redirect` — the same class of bug that has shipped 5 times before per `feedback_lua_forward_reference.md`. This will crash when any career has an entry in `_suffix_career_map` and the suffix path is reached.

Three rendering paths: only **two** (in-game + HeroPreviewer) are covered. Illusion browser / `LootItemUnitPreviewer` is intentionally NOT covered (per `feedback_grip_offset_sign` — preview shows un-offset weapon). MenuWorldPreviewer hooks attempt path 2b, but the `equip_item` hook may be silently broken (see Hook patterns).

---

## Confirmed bugs / potential bugs

- **weapon_tweaker.lua:256** (HIGH) — `_safe_has_anim(unit, target)` is called inside `_try_suffix_redirect` (defined at line 247), but `_safe_has_anim` is not defined until line 668. Since closures capture upvalues by lexical scope at parse time, the reference resolves to a global (nil), and calling nil crashes the game whenever a career-suffix mapping reaches that branch. **Fix:** move `_safe_has_anim` above `_try_suffix_redirect`. This bug is likely currently shipped because every entry in `_suffix_career_map` (8 entries × multiple careers) covers active cross-career setups including spear, polearm, billhook variants. (Same class of bug as v0.7.1, v0.7.37, v0.7.39, v0.7.51, v0.7.53 in cosmetics_tweaker.)

- **weapon_tweaker.lua:1185** (MED) — `mod:hook_safe("MenuWorldPreviewer", "equip_item", ...)`. `MenuWorldPreviewer.equip_item` does NOT exist as a direct method on MenuWorldPreviewer; it is inherited from HeroPreviewer (verified against decompiled VT2 source `scripts/ui/views/menu_world_previewer.lua`). VMF's string-form hook resolves `_G.MenuWorldPreviewer.equip_item` which on a class with metatable inheritance may return nil (depending on whether the class system pre-copies methods or relies on `__index`). If nil, VMF logs an "trying to hook function or method that doesn't exist" error and the hook fails to install — meaning menu-preview scale/grip-offset never receives the weapon key, leaving the spawn hook to fall back to `_local_career_name()` and bail. Test by toggling animlog and verifying [WIELD] / preview_probe lines fire when changing weapons in the new inventory.

- **weapon_tweaker.lua:2418** (LOW) — `pcall(backend_items.set_loadout_item, backend_items, new_backend_id, career_name, slot_name)` invokes our own backend hook (set_loadout_item is hooked in weapon_tweaker_backend.lua at line 95). For the crafted item (rarity="promo", same career), `is_mod_unlocked_weapon` returns false, so it falls through to `func()` correctly. No bug per se, but the interaction is non-obvious.

- **weapon_tweaker.lua:1063** (LOW) — `Unit.local_position(unit, 0)` is NOT pcall-wrapped while `set_local_position` on the next line IS. Inconsistent. If `unit` becomes invalid between the truthy check and the call, the entire hook crashes. Wrap the read for symmetry.

- **weapon_tweaker.lua:1063** (LOW) — Grip offset compounds if `_offset_weapon_units` runs multiple times against the same unit instance. Currently safe because the engine spawns fresh unit instances per equip, but a future refactor that recycles units would cause additive offsets.

- **weapon_tweaker.lua:2840-2841** (MED) — `if not ItemMasterList[item_key] then` triggers crashify __index when item_key is unknown (per CLAUDE.md). The check is meant to guard, but the lookup itself crashes before the negation. Use `if not rawget(ItemMasterList, item_key) then`.

- **weapon_tweaker.lua:1407** (LOW), **2308** (LOW), **2423** (LOW), **2776** (LOW), **2851** (LOW), **2962** (LOW), **2978-2979** (LOW) — Direct `ItemMasterList[key]` reads where `key` may be stale (forge save data, user-input). All currently safe by code path inspection, but not defensive against future code changes. Switch to `rawget(ItemMasterList, key)`.

- **weapon_tweaker_backend.lua:91** (LOW) — `mod:hook(items_interface, "set_loadout_item", function(func, self, backend_id, career_name, slot_name)`. The vanilla method takes a 5th arg `optional_loadout_index`. Passing only 4 means versus and other multi-loadout modes have their loadout index dropped when the hook returns through `func(self, ...)`. Use `function(func, self, ...)` and `func(self, ...)` to forward all args.

- **weapon_tweaker_backend.lua:95-96** (LOW) — Hook short-circuits with bare `return`. Vanilla returns `true`/`false`. Most callers don't check, but `BackendInterfaceVersusPlayfab.set_loadout_item` propagates the value. Returning `true` here would be more semantically faithful.

- **weapon_tweaker_backend.lua:153** (LOW) — `mod:hook(ItemGridUI, ...)` uses the table-form. If `ItemGridUI` isn't loaded at install time, VMF errors. Class is loaded by inventory UI deps (early), so this hasn't failed in practice — but the safer string-form is recommended by CLAUDE.md.

---

## Open questions

- **weapon_tweaker.lua:215-219** *(style note partially addressed in v0.11.9 — `wh_priest` rows re-aligned to match the column spacing of siblings; full-name-as-prefix retained intentionally with an explanatory inline comment)* — `to_2h_billhook` redirect: `prefix = "wh_"`, `alt = "to_polearm"`. All non-wh careers have explicit `overrides`, so the `alt` fallback never triggers. Is this a defensive default, or leftover from an earlier iteration that didn't list every career?

- **weapon_tweaker.lua:533-534** — `_local_fp_unit` is captured in `SimpleInventoryExtension.wield`, but never explicitly cleared on local player despawn / state change. It remains a stale handle to a dead unit until next wield. The `_safe_has_anim` and `unit ==` comparisons are safe against dead units (they pcall or compare by identity), but worth confirming this is intentional vs. a leak path.

- **weapon_tweaker_data.lua:13** — `_has_cwv` detection runs at _data.lua require time. Mod load order is not deterministic across users — if CWV loads after weapon_tweaker, the duplicate widgets remain for that session. Is this acceptable?

- **weapon_tweaker.lua:2230-2289** — `_setup_weapon_list` filters out `item_data.rarity ~= "magic"`. Weave magic items (300+ in WeaveLoadoutSettings) are excluded. The custom forge presents only "real" weapons. But if a weapon in ItemMasterList ever happens to have rarity="magic" outside weaves (unlikely but possible with mod-injected items), it would silently be excluded.

- **weapon_tweaker.lua:2949-2950** — `_forge_confirm` uses `math.random(1000000)` for backend_id. Application.guid() (used in the UI craft path) is more robust against collisions. Why two different ID schemes?

---

## Refactor / cleanup candidates

- **weapon_tweaker_data.lua:961** — `debug` and `enable_weapon_debug_logging` widgets are NEVER read via `mod:get()` anywhere in code. Dead settings.

- **weapon_tweaker_localization.lua:673-681** — Six localization keys with no matching widget: `enable_weapon_unlocks_core`, `enable_weapon_runtime_guards`, `enable_weapon_wield_slot_guard`, `enable_weapon_create_equipment_guard`, `enable_weapon_career_action_injection`, `force_bretonnian_shield_unlock`. All orphan. Either add widgets or delete keys.

- **weapon_tweaker_localization.lua:674-676** — `enable_weapon_backend_hooks`, `enable_weapon_ui_hooks`, `enable_weapon_animation_redirects`: code reads them via `feature_enabled(... default=true)`, but no widget exists in `_data.lua`. They are user-facing but un-toggleable. Add widgets.

- **weapon_tweaker.lua:530** — `_last_3p_unit` is set at line 712 but never read. Dead.

- **weapon_tweaker.lua:104** — `_career_action_injections` cleanup logic at lines 119-126 only handles re-running `patch_career_actions_on_weapons`. It doesn't handle the case where a setting is toggled off and the action should be uninjected — actually it does (the strip at 119-126 happens unconditionally before the add loop). OK, not dead, but the comment block could be clearer.

- **weapon_tweaker.lua:1097-1163** — `HeroPreviewer.equip_item` hook does extensive `_preview_probe_logged` debug-once probing of self fields. Probably worth removing once the preview path is stable.

- ~~**weapon_tweaker.lua:1209-1213** — `mod.on_game_state_changed` ignores both args. Could be `function() ... end`.~~ **FIXED in v0.11.9** — signature now `function()`.

- **weapon_tweaker.lua:2440-2557** — `forge_dump`, `forge_dump_props`, `forge_dump_backend`, `craft_dump` are debug commands that write large dumps to chat. Useful for development; consider gating with `enable_weapon_debug_logging` (which currently does nothing — see dead settings above).

- ~~**weapon_tweaker.lua:589-595** — `_3p_state_machine_paths` doesn't include warrior_priest. Used only by `wt sm_probe`, so probe is incomplete for that skeleton.~~ **FIXED in v0.11.9** — `witch_hunter_warrior_priest` entry added with the path verified against `cosmetics_bless.lua:8`.

---

## Doc/code mismatches

- DEVELOPMENT.md "Animation System Architecture" lists three layers as `_anim_redirect`, `_career_anim_redirect`, **`_suffix_career_map`**. The current code uses `_3p_template_remaps` and `_3p_key_remaps` as the third layer with `_suffix_career_map` as a fourth, separate layer. The doc is slightly outdated — the third layer is now richer.

- DEVELOPMENT.md says `_3p_template_remaps` resolution: "template first, key as fallback. Both support career-prefix matching with `_default` fallback, and `false` to explicitly skip a career". Code matches this exactly — good.

- WEAPON_CATALOG.md lists `we_1h_sword` heavy 3 mapping with `attack_swing_charge_right_diagonal_pose → attack_swing_charge_left_diagonal`. Code has the same entry at line 487. Match.

- CLAUDE.md describes "Three Weapon Rendering Paths" with `LootItemUnitPreviewer.spawn_units` as path 3. weapon_tweaker does NOT hook this (only paths 1 and 2). This is intentional per `feedback_grip_offset_sign.md`: "weapon_tweaker/cosmetics_tweaker only apply offset in-game (intentional asymmetry — preview shows un-offset weapon)". Documenting this explicitly in CLAUDE.md would help reviewers.

---

## Settings coherence

- **Total widgets:** 648 setting_ids in `_data.lua`
- **Total localization keys:** 659 (including `mod_name`, `mod_description`)
- **Setting IDs in data missing localization:** 0 — clean.

### Orphan localization keys (loc entry exists, no widget)

```
enable_weapon_animation_redirects   (read by code via feature_enabled)
enable_weapon_backend_hooks         (read by code via feature_enabled)
enable_weapon_ui_hooks              (read by code via feature_enabled)
enable_weapon_unlocks_core          (NEVER read)
enable_weapon_runtime_guards        (NEVER read)
enable_weapon_wield_slot_guard      (NEVER read)
enable_weapon_create_equipment_guard (NEVER read)
enable_weapon_career_action_injection (NEVER read)
force_bretonnian_shield_unlock      (NEVER read)
```

The first three need widgets added. The last six should have their localization entries deleted (or widgets added if the toggles are intended to come back).

### `mod:get()` reads NOT in widgets

- `forged_weapons` — internal mod state stored via `mod:set/mod:get`, intentional (not user-facing).
- `unlock_` — base of the dynamic concat `unlock_..career.._..weapon_key`. False positive.

### Widgets NEVER read

- `debug`, `enable_weapon_debug_logging` — dead.

---

## Hook patterns

- ✅ `mod:hook("Unit", "animation_event", ...)` — string-form, correct.
- ✅ `mod:hook("SimpleInventoryExtension", "wield", ...)` — string-form, correct.
- ✅ `mod:hook("GearUtils", "create_equipment", ...)` — string-form, correct.
- ✅ `mod:hook_safe("HeroPreviewer", "equip_item", ...)` — fire-and-forget, no return needed, correct use of hook_safe.
- ⚠️ `mod:hook_safe("MenuWorldPreviewer", "equip_item", ...)` — `equip_item` is INHERITED from HeroPreviewer; whether VMF can resolve through metatable depends on its lookup implementation. Likely silently broken. See Confirmed bugs.
- ✅ `mod:hook_safe("MenuWorldPreviewer", "_spawn_item_unit", ...)` — `_spawn_item_unit` IS directly defined on MenuWorldPreviewer (line 643 of menu_world_previewer.lua). OK.
- ✅ `mod:hook("BackendInterfaceWeavesPlayFab", ...)` × 22 — all methods exist directly on the class; string-form correct.
- ✅ `mod:hook("HeroWindowWeaveForgeWeapons", ...)` × 5 — methods exist; string-form correct.
- ✅ `mod:hook_safe("BackendManagerPlayFab", "_create_interfaces", ...)` — fire-and-forget for re-injecting forged items; correct use.
- ⚠️ `mod:hook(items_interface, "set_loadout_item", ...)` (backend.lua:91) — table-form, deferred behind `Managers.backend._interfaces["items"]` check; correct pattern but signature drops `optional_loadout_index` (5th arg).
- ⚠️ `mod:hook(ItemGridUI, "_on_category_index_change", ...)` (backend.lua:154) — table-form; ItemGridUI is loaded early so works in practice, but string-form would be safer.
- ✅ NEVER hooks `BackendUtils.can_wield_item` — correctly uses ItemMasterList[key].can_wield direct mutation.

---

## Animation system audit

Three layers, correctly implemented per CLAUDE.md / DEVELOPMENT.md:

- **Layer 1 (`_anim_redirect`)** — global event renames; checked at L894 inside `Unit.animation_event` hook. Only fires when source event missing on skeleton (correct guard at L896).

- **Layer 2 (`_career_anim_redirect`)** — career-prefix-aware. Checked at L854. Supports `invert`, `overrides`, `prefix`. Sets `_3p_weapon_remap` via `_resolve_3p_remap` when redirecting. Correct.

- **Layer 3 (`_3p_template_remaps` / `_3p_key_remaps`)** — applied at L818 (`_3p_weapon_remap` lookup). Set on weapon-switch (L727) by template-first, key-fallback resolution. False values are correctly distinguished from nil (deliberate skip vs. no entry). Correct.

- **Layer 4 (suffix-based via `_try_suffix_redirect`)** — invoked at L905. **CONTAINS THE FORWARD-REF BUG** (will crash on any matching suffix entry).

### Non-weapon `to_` events whitelist

The CLAUDE.md says: "Skip non-weapon `to_` events (`to_crouch`, `to_onground`, `to_zoom`) — they should NOT clear `_3p_weapon_remap`."

The code at line 745 reads `if is_local and event_name:sub(1, 3) == "to_" and remap_id and remap_id ~= _last_remap_template then`. The whitelist is implemented as "remap_id changed" rather than an explicit allow-list of weapon events. Since `_current_weapon_template`/`_current_weapon_key` only update via the `wield` hook (and `wield` is only called on actual weapon switches, NOT on crouch/zoom/jump), `remap_id` doesn't change on those events, so the clear is correctly skipped. ✅

### Force-fire blocks scoping

The billhook force-fire block at L827 is correctly guarded with `_3p_weapon_remap == _3p_remap_spear_to_billhook` per `feedback_animation_remap_rules.md` (v0.9.56 fix). ✅

### `_local_fp_unit` early return

Line 759: `if _local_fp_unit and unit == _local_fp_unit then return func(...)` — correctly bails BEFORE any redirect/remap logic, protecting 1P hands animations. ✅

### 3P remap targets the correct unit

The remap block runs on `unit` whether it's the 3P body or a husk. Both need cross-career remaps to look correct. ✅

---

## Three rendering paths audit

| Path | Coverage | Implementation |
|------|----------|----------------|
| In-game (GearUtils.create_equipment) | ✅ | scale, grip-offset, animation hooks |
| Inventory preview (HeroPreviewer.equip_item) | ✅ | scale, grip-offset (via probed slot_data) |
| Inventory preview (MenuWorldPreviewer) | ⚠️ | scale/offset attempted via `_spawn_item_unit`, but `equip_item` capture hook may be broken (see hook patterns) |
| Illusion browser (LootItemUnitPreviewer) | ❌ INTENTIONAL | per `feedback_grip_offset_sign`, weapon_tweaker does NOT cover this path |

Animation remaps don't go through MenuWorldPreviewer (preview is static, not driven by `Unit.animation_event`), so this asymmetry only affects scale/offset.

---

## Crafting system audit

- **Promo rarity patch (L8-16):** Idempotent, runs at module load. Correctly precedes any equip path that could fire. ✅
- **MoreItemsLibrary integration:** `_forge_detect_mil` lazy-detects, returns false if not installed. `_forge_inject_item` echoes warning and returns false on missing dependency. ✅
- **Save/load:** `_forge_save` writes via `mod:set("forged_weapons", ...)`. `_forge_load` reads back. Re-injection via `BackendManagerPlayFab._create_interfaces` hook. ✅
- **Forged weapon item construction (`_forge_create_item`):** Uses `table.clone(master, true)` to deep-copy ItemMasterList entry, then injects `mod_data` table with custom backend_id, ItemInstanceId, CustomData (with traits/properties JSON), and rarity. Skin path overrides `inventory_icon` from WeaveSkins. Looks correct.
- **Network sync in multiplayer:** Custom forged items are session-only and local. The CHANGELOG explicitly notes "Crafted items are session-only — lost on game restart (PlayFab resync)." Multiplayer behavior is undocumented; presumably the equipped weapon is recognized by remote players via the base item key (the network only carries item_key, rarity index, and properties — and rarity "promo" was patched into NetworkLookup). Worth verifying with a real multiplayer test but mechanically sound.
- **Forge UI (1500-2660):** Repurposes Athanor weave-forge UI. ~22 backend hooks neutralize weave gating; 5 `HeroWindowWeaveForgeWeapons` hooks override list/select/equip behavior; `_forge_apply_ui_polish` patches widget visibility/styles each frame. The polish patches re-apply every frame (line 2008+) — minor performance cost but defensible because vanilla code re-creates UI elements on layout changes.
- **Property/trait conversion (`_forge_seed_item`, `_forge_apply_to_item`):** Translates between regular keys and `weave_*` keys for the bubble-grid UI; looks correct, including the slot-index assignment fix (CHANGELOG 0.11.1).

---

## rawget guards on ItemMasterList

The following `ItemMasterList[key]` reads use bracket notation (NOT `rawget`). Most are safe by inspection but should be defensive:

| Location | Source of `key` | Safe? | Recommendation |
|----------|-----------------|-------|----------------|
| L69 | weapon_unlock_map iteration | ✅ Yes (vanilla weapon keys) | OK as-is |
| L87 | weapon_unlock_map iteration | ✅ Yes | OK as-is |
| L129 | weapon_unlock_map iteration | ✅ Yes | OK as-is |
| L1339 | `pairs(ItemMasterList)` | ✅ Yes (existing key) | OK as-is |
| L1407 | `weapon_data.item_key` (save data) | ⚠️ Stale possible | switch to `rawget` |
| L2308 | from `_setup_weapon_list` (existing) | ✅ Yes | OK as-is, fragile |
| L2423 | from selected weapon list | ✅ Yes | OK as-is, fragile |
| L2776 | `item.key` (backend item) | ✅ Yes | OK as-is, fragile |
| L2840-2841 | user-typed `wt forge <key>` | ❌ NO | switch to `rawget` (HIGH priority) |
| L2851 | same as 2840 | ❌ NO | switch to `rawget` |
| L2962 | `_forge_pending.item_key` | ⚠️ user input | switch to `rawget` |
| L2978-2979 | `w.item_key` (save data) | ⚠️ Stale possible | switch to `rawget` |

---

## Non-obvious things now clarified (via inline comments)

- The promo rarity NetworkLookup patch order and idempotency.
- Why `_cwv_managed` exists and the strip-then-add invariant in apply_weapon_unlocks.
- Career-action injection purpose and idempotent revert via `_career_action_injections`.
- `_local_career_name` two-step fallback (career_name then SPProfiles) for early-game timing.
- `_career_anim_redirect` field semantics: `prefix`, `invert`, `overrides`.
- `_suffix_order` longest-first ordering rationale.
- `_resolve_3p_remap` returning `false` vs nil distinction.
- `_3p_weapon_remap` lifecycle (set, clear, false-skip).
- `_current_weapon_template/key/_last_remap_template` purposes.
- `_local_fp_unit` capture rationale (cannot use is_local).
- `_original_animation_event` capture for force-fire bypass.
- `force3p` command's bypass of own hook.
- The non-weapon `to_` whitelist via `remap_id` change check.
- Force-fire scoping per remap table.
- Wield hook scoping to local player only.
- create_equipment hook crashify protection (CW ghost scythe investigation).
- Three rendering paths intentional asymmetry (illusion browser un-offset).
- All BackendInterfaceWeavesPlayFab hooks share a "fake values for our forge" pattern.
- BackendManagerPlayFab.commit blocking scope.
- `_setup_weapon_list` filter rationale.
- `feature_enabled` differences between main and backend modules.
- `set_loadout_item` hook intercept-vs-passthrough strategy.
- `_on_category_index_change` exact-match filter patching.
- `mod.update` deferred init pattern.

---

## Dead code

- weapon_tweaker.lua:530 `_last_3p_unit` — set, never read.
- weapon_tweaker_data.lua `debug`, `enable_weapon_debug_logging` widgets — never read.
- weapon_tweaker_localization.lua: `enable_weapon_unlocks_core`, `enable_weapon_runtime_guards`, `enable_weapon_wield_slot_guard`, `enable_weapon_create_equipment_guard`, `enable_weapon_career_action_injection`, `force_bretonnian_shield_unlock` — orphan localization with no widget and no code reference.
- weapon_tweaker_backend.lua `apply_weapon_unlocks` parameter — never used inside `M.install`.
- weapon_tweaker.lua:119-126 — clears `_career_action_injections`, then re-iterates same map. Pattern is correct, but the cleanup loop runs even on first call when the map is empty (no-op). Tiny perf cost, OK to leave.
- ~~`mod.on_game_state_changed` — `status` and `state_name` parameters unused.~~ **FIXED in v0.11.9.**

---

## Notes for future AI agents

1. **Forward-reference bugs are the #1 cause of crashes.** Always run a forward-ref audit before deploy. The `_safe_has_anim` bug at line ~256 is shipping NOW and should be the user's first fix decision.

2. **Don't change `itemV2.cfg` `visibility` field.** Per project memory, two prior agents flipped to "public" and got mods removed from community.

3. **Do NOT attempt to fix Ctrl+Shift+R hot-reload crashes** for this mod — engine-level C++ resource locks (per `feedback_hot_reload_unfixable.md`).

4. **Animation remap changes:** read `feedback_animation_remap_rules.md` first. Specific traps:
   - `is_local` does NOT distinguish 1P from 3P. Use `_local_fp_unit`.
   - `_3p_weapon_remap` must be cleared ONLY on actual weapon switches (template/key change), not non-weapon `to_` events.
   - Some events (e.g. `attack_swing_stab_02`, `attack_swing_left` on flail) corrupt the SM when added to remap tables — use force-fire instead.
   - Force-fire blocks must be guarded by `_3p_weapon_remap == <specific_table>` to avoid hijacking other weapons.

5. **Never hook `BackendUtils.can_wield_item`** — modify `ItemMasterList[key].can_wield` directly.

6. **Three rendering paths:** in-game + inventory preview + illusion browser. weapon_tweaker covers paths 1 and 2 only (intentional). Don't break that asymmetry without user direction.

7. **`ItemMasterList` lookups need `rawget`** when the key may be unknown — the `__index` calls `crashify`. This is more important in user-facing forge commands than in iterations over `pairs(ItemMasterList)`.

8. **VMB build, not SDK:** the mod was migrated 2026-05-01. Build with `node vmb.js build weapon_tweaker --no-workshop --cwd`. Internal mod ID is still `"wt"` to preserve user settings.

9. **MOD_VERSION bump on every build** — required to visually verify hot-reload (and full restart) loaded the new code.

10. **The "promo" rarity patch** at the top of the file MUST stay — without it, equipping a crafted item crashes via NetworkLookup.lua.

11. **Localization escapes:** `%` becomes `%%` (and sometimes `%%%%`) — VMF runs string.format. None of the current weapon_tweaker localization strings have `%` so this isn't an active concern, but be careful when adding new strings.

12. **The forge UI is a frame-by-frame patch:** `_forge_apply_ui_polish` runs in `HeroViewStateWeaveForge.update`. Vanilla recreates widgets on layout changes, so the patch must idempotently re-apply each frame. Don't try to refactor it to one-shot init.
