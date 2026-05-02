# Cross-Mod Consistency & Clarity Review (2026-05-02)

Third-pass meta review across all 7 active mods, focused on stylistic/structural drift and stale-annotation pruning. Two prior passes (per-mod + aggregate) ran on 2026-05-01.

## Summary

Codebase health is solid. Almost every prior-pass annotation describes a genuine remaining concern (LOW open items per `REVIEW_AGGREGATE.md`) — virtually no "fixed but annotation left behind" cases survived. Consistency is good for the basics (file-header shape, `MOD_VERSION` format `0.X.Y-dev`, section divider style `-- ====`), but lifecycle hook coverage diverges meaningfully: only general_tweaker, career_tweaker, and enemy_tweaker provide `mod.on_disabled` cleanup despite weapon_tweaker and chaos_wastes_tweaker mutating persistent global state.

## Annotations pruned

Total: **2 annotations removed**.

| File | Line | Type | Why removed |
|---|---|---|---|
| `general_tweaker/scripts/mods/general_tweaker/general_tweaker_localization.lua` | ~15 | POTENTIAL BUG | `tp_distance / tp_height / tp_side_offset never read` — actually wired in v0.2.11-dev (see general_tweaker.lua:74-76, 269). |
| `weapon_tweaker/scripts/mods/weapon_tweaker/weapon_tweaker.lua` | 1267-1277 | CLARIFY | Multi-paragraph block (11 lines) duplicating both the rendering-paths note and the pcall rationale already covered in the immediately-preceding INVESTIGATION block. Tightened to 4 lines covering only the rendering-path coverage statement. |

The remaining 128 annotations were all verified against current code and either (a) describe genuine still-open issues already tracked in `REVIEW_AGGREGATE.md` "Items still open" or (b) provide non-trivial CLARIFY documentation for non-obvious decisions that the surrounding code does NOT make self-evident.

Notable cases where deletion was considered but rejected:
- `weapon_tweaker.lua:1244-1253` — two POTENTIAL BUG (LOW) annotations about `Unit.local_position` not being pcall-wrapped and grip offset compounding. Both real, both LOW, both tracked.
- `weapon_tweaker.lua:235` — QUESTION about `to_2h_billhook` `prefix = "wh_"` defensive default. Per code review this was not resolved by the v0.11.9 row-realignment fix.
- `chaos_wastes_tweaker.lua:64,161,610` — three QUESTION annotations matching the open-questions section of the per-mod review (count detection, NaN single-widget fix, hook signature drift). All real ambiguities.
- `cosmetics_tweaker.lua:2213-2220` — QUESTION about `hotspot.on_pressed` semantics. Real concern; needs in-game verification.

## Cross-mod consistency findings

### File headers

| Mod | Shape | Notes |
|---|---|---|
| chaos_wastes_tweaker | `mod = get_mod("ct")` → MOD_VERSION → info → echo | canonical |
| weapon_tweaker | same + `weapon_backend = mod:dofile(...)` between line 1 and MOD_VERSION | canonical |
| career_tweaker | `mod = get_mod("crt")` → MOD_VERSION → info → echo → safe-stub balance load | canonical |
| enemy_tweaker | canonical |  |
| cosmetics_tweaker | canonical |  |
| general_tweaker | **DRIFT**: helpers (`_write_dump`, `_godmode`) declared between MOD_VERSION (L3) and the info/echo (L13-14) | minor |
| character_weapon_variants | **DRIFT**: only `mod:info` at top (L5, "loading"); the matching `mod:echo` is at L1643 (end of file) and uses "loaded". Past-tense version-loaded-and-init-complete signal — but the "loaded" announcement is split across the file. | medium |

Recommendation: leave general_tweaker as-is; consider unifying cwv to the canonical 3-line block at top OR explicitly comment why "loading" vs "loaded" is split.

### Section divider style

Canonical: `-- ============================================================` (170 occurrences across 9 files).

Drift:
- `cosmetics_tweaker.lua` uses `-- ----` (2x) and `-- ---` (2x) for sub-section dividers.
- `weapon_tweaker.lua` uses `-- ---` (12x) for sub-section dividers.

The triple-dash sub-divider is consistent within each file but inconsistent across mods. Not worth a mass rewrite.

### Localization helpers

Inline `mod:localize(...)` calls predominate; no caching pattern in place. Consistent across mods.

`%` escaping audit: searched for `%%%%` and `%%`. None found in any active mod's localization file — current strings just don't contain percent signs. Keep this in mind when adding new strings.

### Hook patterns

All hooks correctly use string-form for game classes. Table-form is reserved for plain tables (`BackendUtils`, `_G`, `items_interface` instances) and one acknowledged exception:

- `weapon_tweaker_backend.lua:197` — `mod:hook(ItemGridUI, "_on_category_index_change", ...)` uses table-form. Per CLAUDE.md the safer choice is string-form. Annotated in source with POTENTIAL BUG (LOW) explaining the risk; confirmed not currently failing.
- `cosmetics_tweaker.lua:2291` — `mod:hook(BackendUtils, "get_item_units", ...)` correctly uses table-form (BackendUtils is a plain table), with a CLARIFY at L2285-2290 explaining why and a nil guard.

`_G.Localize` is hooked in both chaos_wastes_tweaker and cosmetics_tweaker and character_weapon_variants — coherent with CLAUDE.md.

`BackendUtils.can_wield_item` is correctly NOT hooked by any active mod.

### Lifecycle hooks

| Mod | `on_game_state_changed` | `on_setting_changed` | `on_disabled` | `on_enabled` | `on_unload` | `update` |
|---|:-:|:-:|:-:|:-:|:-:|:-:|
| chaos_wastes_tweaker | – | YES | – | – | – | – |
| weapon_tweaker | YES | YES | – | – | – | YES (in `_backend.lua` deferred init) |
| general_tweaker | YES | YES | YES (restores camera) | – | – | YES |
| career_tweaker | YES | YES | YES (`balance.restore`) | – | – | – |
| cosmetics_tweaker | YES | YES | – | – | YES (restores portrait) | YES (la_bridge init) |
| enemy_tweaker | – | YES | YES (restores compositions) | YES | – | – |
| character_weapon_variants | – | – | – | – | – | – |

Cross-mod gaps:

- **chaos_wastes_tweaker has no `on_disabled`**. `apply_reckless_swings_tweak()` persistently mutates `DeusPowerUpTemplates.deus_reckless_swings` — disabling the mod via VMF leaves the buff in modified state until a game restart. Same for `_register_skeleton_breeds` in enemy_tweaker (it has on_disabled but skeleton breeds stay in `Breeds`).
- **weapon_tweaker has no `on_disabled`**. `apply_weapon_unlocks()` persistently mutates `ItemMasterList[key].can_wield`. Disabling weapon_tweaker leaves cross-career unlocks active.
- **character_weapon_variants has zero lifecycle handlers**. Item registration is one-shot via `StateInGameRunning.on_enter`. Disabling mid-session leaves variant items in MIL/ItemMasterList.
- general_tweaker's `on_game_state_changed` signature is `function(status, state_name)`; weapon_tweaker's is `function()` (per v0.11.9 fix). Both are valid (extras ignored) but inconsistent.

Recommendation: at minimum add `on_disabled` to chaos_wastes_tweaker and weapon_tweaker so a clean disable doesn't leave stale global mutations. (Per memory note, restart-required is the documented baseline for cosmetics/weapon, so partial restore is fine.)

### Logging

| Symbol | When used |
|---|---|
| `mod:info(...)` | log file only — used liberally for diagnostic output |
| `mod:echo(...)` | in-game chat — used for command results, version banner, error prompts |
| `mod:warning(...)` | log file with WARNING severity — sparse use in cwv (`_register_variant_skins` etc.) and cosmetics_tweaker |
| `mod:error(...)` | log file with ERROR severity — used in weapon_tweaker `create_equipment` pcall fallback and a few in cwv. |

Patterns are consistent: every command's primary user-visible output is `echo`, every passive load message is `info`. No drift.

### rawget audit

Audited every `ItemMasterList[k]`, `NetworkLookup.weapon_skins[k]`, `NetworkLookup.breeds[k]`, `WeaponSkins.skins[k]` access:

- **Already using `rawget`**:
  - `weapon_tweaker.lua` for the `wt forge` user-input path (L3173).
  - `cosmetics_tweaker.lua` for `_skin_requires_unowned_dlc` (L77), `apply_cosmetic_unlocks`, `_la_bridge.build_clone_entry` (per second-pass fix), and `_register_custom_illusions` skin-key check (L1545).
  - `character_weapon_variants.lua` for NetworkLookup `item_names` writes (L1332).
  - `enemy_tweaker.lua` for the `Breeds` registration walk (L121) and `NetworkLookup.breeds` injection (L156).

- **Bare bracket reads remaining (per-mod-review-flagged, all currently safe by inspection)**:
  - `weapon_tweaker.lua`: L1407, L2308, L2423, L2776, L2851, L2962, L2978-2979 (all keys originate from `pairs(ItemMasterList)` iteration or save-data that's been validated). Annotated POTENTIAL BUG (LOW). Recommend switching to `rawget` defensively.
  - `character_weapon_variants.lua` L1080 (`_build_entry`'s `ItemMasterList[def.base_weapon]`) — variants ship known base weapons, but if a future variant references a key from a DLC the user lacks this would crashify. Switch to `rawget` defensively.
  - `character_weapon_variants.lua` L826-827 `_apply_weapon_unlocks` — `ItemMasterList[unlock.item_key]` for a hardcoded list. Safe today, fragile for future entries.

Recommendation: a sweep replacing bare `ItemMasterList[k]` with `rawget(ItemMasterList, k)` would harden the codebase without any behavior change. Already an established pattern in the codebase.

### Local helper naming

Underscore-prefix convention is used for "module-private" helpers but adoption is mixed:

| Mod | Underscore-prefixed | Non-prefixed | Pattern |
|---|---:|---:|---|
| chaos_wastes_tweaker | most | 7 | helpers without underscore: `is_curse_disabled`, `fix_arc_nan`, `get_all_trait_combos`, `apply_weapon_trait_filter`, `restore_weapon_trait_filter`, `apply_reckless_swings_tweak`, `revert_reckless_swings_tweak` |
| weapon_tweaker | most | 3 | non-prefixed: `feature_enabled`, `apply_weapon_unlocks`, `patch_career_actions_on_weapons` (all "operation" names — verb-first) |
| general_tweaker | most | 0 | clean |
| career_tweaker | most | 2 | non-prefixed: `refresh_talent_ui`, `apply_talent_swaps` |
| cosmetics_tweaker | most | 1 | non-prefixed: a few in `_la_bridge.lua` |
| enemy_tweaker | most | 0 | clean |
| character_weapon_variants | most | 0 | clean |

The pattern that emerges: **action-verb functions ("apply_X", "refresh_X")** tend to drop the underscore prefix, while **helpers / utilities ("_local_career_name", "_resolve_3p_remap", "_is_unit")** keep it. This is internally consistent within each mod once you accept that distinction. Leave as-is; flag for user buy-in if a stricter convention is desired.

### Forward declarations

Audit: `^local <name>$` (declaration without assignment) across active mods.

| File | Line | Variable | Has CLARIFY comment? |
|---|---|---|---|
| chaos_wastes_tweaker.lua | 18 | `sync_reckless_swings` | YES (L13-17, points to feedback_lua_forward_reference) |

Only one forward declaration in the active codebase, and it's correctly documented. Past audits identified `_safe_has_anim` (weapon_tweaker) as forward-referenced via closure capture — that's now fixed by reordering, not by a `local <name>` stub. Forward-reference defense is therefore healthy.

### MOD_VERSION format

All seven active mods use `0.X.Y-dev` (or `0.X.Y` released). Consistent.

### Settings coherence (post-second-pass)

Carrying forward open items from `REVIEW_AGGREGATE.md`:

- **chaos_wastes_tweaker**: 40 missing `*_tooltip` localization keys (per per-mod review). Visual only.
- **weapon_tweaker**: 6 orphan localization keys never read (`enable_weapon_unlocks_core`, etc.); 3 keys read but no widget (`enable_weapon_animation_redirects`, `_backend_hooks`, `_ui_hooks`). Annotated in source.
- **enemy_tweaker**: 3 dead `FACTION_*` locals (per `enemy_tweaker.lua:11` REVIEW). Tooltip explanation re: raw-key dropdown labels.
- All other mods: settings are coherent.

### Duplicated helpers across mods

| Helper | Files | Recommendation |
|---|---|---|
| `_is_unit(v)` (3-line `type() == "userdata" and pcall(Unit.alive)` test) | weapon_tweaker.lua:1294, character_weapon_variants.lua:1401, cosmetics_tweaker.lua:2355 | DRY candidate — extract to a shared `scripts/mods/_shared/unit_utils.lua` (or a per-mod `_utils.lua`). Three identical implementations. |
| `_deep_copy(t)` | enemy_tweaker.lua only | Single use — no DRY action needed. (Most other mods use `table.clone(t, true)` from VT2 foundation.) |
| Career-prefix matchers (`career:sub(1, #prefix) == prefix`) | weapon_tweaker (multiple), character_weapon_variants, cosmetics_tweaker | Consistent inline pattern; not worth extracting. |

A single shared utility module would help, but cross-mod sharing in VT2 mods is non-trivial — each mod is a separate Workshop subscription, and inter-mod requires depend on load order. Currently no shared module exists. Defer to user.

### `_data.lua` widget shape

Spot-checked widget definitions across all 7 mods.

Consistent fields:
- `setting_id`, `type` (always present)
- `default_value`, `range`, `decimals_number` (where applicable)

Inconsistent:
- `tooltip = "<setting_id>_tooltip"` is used in all mods but **chaos_wastes_tweaker** has 40 widgets where the tooltip key resolves to nothing (per pass 2 finding). This is data-only drift; no schema inconsistency.
- `unit_text` field: NOT used anywhere (per DEVELOPMENT.md "Known Errors"). Consistent.

`group` widgets with `sub_widgets` are used universally for collapsible sections. Consistent.

## Clarity findings

### Top-of-file overview comments

| Mod | Has top comment? | Notes |
|---|:-:|---|
| chaos_wastes_tweaker | minimal | Short header, no narrative overview. The 3000+ line file would benefit from a 5-10 line "what does this mod do, and what are the major sections" block. |
| weapon_tweaker | minimal | 3270-line file. Same as above. The animation-system 3-layer architecture is well-documented in DEVELOPMENT.md, but the file itself opens straight into `weapon_unlock_map`. |
| general_tweaker | partial | The TP camera section has good in-line commentary but no top-of-file orientation. |
| career_tweaker | minimal |  |
| cosmetics_tweaker | partial | Has commented sections (Material lookup, Hat tinting, etc.) but no high-level introduction. |
| enemy_tweaker | partial | "Breed catalog" section header exists. |
| character_weapon_variants | medium | Has `Cross-character weapon analogues (public API)` block early — clearer than most. |

Recommendation: each main `.lua` could open with a 5-line block describing the mod's purpose and listing the major top-level sections. Defer to user — this is ergonomic polish.

### Magic numbers needing names

Spot-check of obvious magic numbers found in source:

| File | Line | Value | Suggested name |
|---|---|---|---|
| general_tweaker.lua | 139 | `0.5` (`_tp_reapply_timer = 0.5`) | already explained in adjacent comment as "post-extension setup defer" |
| career_tweaker_balance.lua | 73, 86 | `t + 1.0` | `_PARRY_WINDOW_EXTENDED_S` |
| chaos_wastes_tweaker.lua | 7 | `SHRINE_DEFAULT = 4` / `CHEST_DEFAULT = 3` | already named — exemplar |
| character_weapon_variants.lua | 271-274 | `_IL_DAMAGE_MULT = 0.85`, etc. | already named — exemplar |
| weapon_tweaker.lua | 1206-1213 | grip offsets `{0,0,0.05}`, `{0,0,0.15}` | could promote to named constants but inline is OK in a config table |
| weapon_tweaker.lua | 1135-1141 | scale factors `1.15`, `1.10`, `0.85` | same — inline in config table, acceptable |

The codebase actually scores well — most "magic" numbers are either in named constants (chaos_wastes, cwv) or in clearly-labeled config tables (weapon_tweaker scale/offset). One genuine candidate: career_tweaker_balance.lua's parry window `1.0`.

### Misleading names

None identified during this pass. Variable and function names match behavior throughout.

### Why-comments missing

A few concrete cases:

- **weapon_tweaker.lua:1424** `mod.on_game_state_changed = function() ... apply_weapon_unlocks() ... patch_career_actions_on_weapons() end` — the why for re-applying is in the CLARIFY at L1419, good. No gap.
- **character_weapon_variants.lua:1372** `mod:hook_safe("StateInGameRunning", "on_enter", function() _auto_register_all() end)` — the WHY (deferred-until-backend-ready) is in the CLARIFY at L1364-1371. Good.
- **cosmetics_tweaker.lua:2291** `if BackendUtils then mod:hook(BackendUtils, ...)` — the WHY for the gate is in the CLARIFY at L2285-2290. Good.

Generally why-comments are present where they matter. Two small gaps:

- **weapon_tweaker.lua:73** `local function feature_enabled(setting_id, default_value) ... if value == nil then return default_value ~= false` — the `~= false` (rather than `== true`) is subtle; one inline why-comment would help.
- **enemy_tweaker.lua:60-67** `_deep_copy` — generic name, no why for "why a custom deep copy when `table.clone(t, true)` exists". Probably because the function is needed for breed cloning very early before all VT2 utilities are guaranteed available, but that's not stated.

## Recommended fix priorities

1. **Add `mod.on_disabled` to weapon_tweaker and chaos_wastes_tweaker.** Both persistently mutate global state (ItemMasterList.can_wield, DeusPowerUpTemplates) with no clean-disable path. This is the highest-leverage consistency gap because users *can* disable a mod via VMF and currently have no way to back out cross-career unlocks or Khaine's Fury rebalance without restarting.
2. **Sweep bare `ItemMasterList[k]` reads to `rawget`** in weapon_tweaker forge command paths and cwv `_build_entry` / `_apply_weapon_unlocks`. Codebase has the pattern; ten or so call sites are still bare brackets.
3. **Extract `_is_unit(v)` to a shared helper** (DRY): three identical implementations across weapon_tweaker, cosmetics_tweaker, and cwv. Trivial mechanical change but each mod is a separate workshop sub, so options are: (a) inline duplication accepted, (b) per-mod local copy with shared comment "see also X.lua", (c) a `_shared/` module loaded by `mod:dofile`. Defer to user — lowest leverage.
4. **Fix the chaos_wastes_tweaker tooltip-localization gap** (40 missing keys). Pure UX polish but easy: either add the loc entries or strip `tooltip = "..."` from the affected widgets.
5. **Consider top-of-file overview comments** in the 3000-line files (weapon_tweaker.lua, chaos_wastes_tweaker.lua) — this would help any future agent orient quickly.

## Items deferred to user decision

- **Unify file-header order** (general_tweaker has helpers between MOD_VERSION and the info/echo pair) — cosmetic only, not a correctness issue.
- **Naming convention for module-local helpers** (underscore prefix vs. plain) — current pattern (action-verb functions drop the underscore, utilities keep it) is internally coherent. Mass rename would be invasive.
- **Section divider unification** — `-- ====` is canonical (170x); `-- ---` shows up in two files (14x). Not worth a mass rewrite.
- **Whether to add `on_disabled` to character_weapon_variants** — the mod is "register items at run start, leave them" by design. A clean disable would require unregistering from MIL (no public API per CHANGELOG v0.1.45), so deferral is justified. Worth a one-line comment in the mod stating this explicitly.
- **Magic number `1.0` (extended parry window) → `_PARRY_WINDOW_EXTENDED_S`** in career_tweaker_balance.lua — minor polish.
