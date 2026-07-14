# Weapon Tweaker Code Review (2026-05-23, v0.12.68-dev)

> **[SUPERSEDED 2026-07-14 — #433 retired the implementation]** The Big Rebalance implementation and definitions described below were deleted from both WT trees. Hidden `br_*` identifiers remain reserved only for save compatibility; historical source is recoverable from git. Do not treat BR findings in this snapshot as current work.

## Summary

Weapon Tweaker (mod id `wt`, Workshop 3712896117) is a mature, heavily-used mod that enables cross-career weapon unlocks, animation remapping across character skeletons, and per-weapon visual tweaks (scale, grip offset, skin swaps). The codebase spans 4056 lines in `weapon_tweaker.lua`, 2552 in `weapon_tweaker_big_rebalance.lua` (BR integration via sister mod `bt`), 242 in `weapon_tweaker_backend.lua`, plus localization and settings data files.

**Overall health:** READY. The animation system is production-hardened with battle-tested redirect/remap logic (three-layer architecture, per-unit career resolution, force-fire scoping). Major fixes in recent versions include the v0.12.60 polearm preview nil-career bug, v0.12.64 billhook swing-animation regression repair, v0.12.65 `set_loadout_item` passthrough audit fix, and v0.12.68 cleanup removing the unused `mod.weapon_unlock_map` public export.

**Key risk:** File sizes flagged by QA — main lua 4056 lines (27× over 150-line advisory target), big_rebalance 2552 lines (1.7× over 1500-line target). Big Rebalance is table-driven and naturally dense; main file couples unrelated features (unlocks, animations, backend hooks, cosmetics, crafting subsystem was split 2026-05-05) into a single monolith. Refactor not blocking release.

---

## Architecture overview

### Major feature areas and line ranges

| Feature | Lines | Notes |
|---------|-------|-------|
| **Cross-career weapon unlocks** | 59–195 | `weapon_unlock_map` (all 5 characters × careers); `apply_weapon_unlocks` strips/re-adds `ItemMasterList[key].can_wield` per toggle state |
| **Career ability injection** | 204–240 | Patches ability actions onto cross-career weapons so abilities work on swapped weapons |
| **Animation system (3 layers)** | 267–520 | `_anim_redirect` (global event renames); `_career_anim_redirect` (career-prefix aware); `_suffix_career_map` (suffix-based swaps) |
| **3P anim remap tables** | 425–520 | Per-weapon-pair tables (`_3p_remap_spear_to_billhook`, `_3p_remap_billhook_to_polearm`, etc.) + prefix-triggered resolver `_3p_remap_triggers` |
| **Unit.animation_event hook** | 969–1200 | Central dispatch (every 3P anim event fires through here); redirects, remaps, force-fire logic; 1P early-return guard |
| **Per-unit state tracking** | 1237–1320 | Weak-keyed `_unit_state` table caching career/template/remap per 3P unit; tied to unit lifetime |
| **Scale & grip overrides** | 1325–1410 | `_weapon_scale_overrides`, `_weapon_grip_offsets`, `_offset_weapon_units` mutator; applied post-spawn via hook |
| **Wield hook & anim capture** | 1415–1510 | Captures local 1P unit, resolves per-unit career + weapon template for state tracking |
| **MenuWorldPreviewer hooks** | 1570–1660 | Inventory preview weapon-swap; scale + brace swap applied via equip_item hook (DERIVED CLASS, not base HeroPreviewer) |
| **Brace-to-repeater skin swap** | 1665–1855 | 3P model swap for `brace_of_pistols` when wielded by non-WHC careers (bw_, dr_, we_) |
| **Polearm preview template patches** | 1860–2050 | `_WIELD_ANIM_CAREER_3P_PATCHES` — writes cross-career `wield_anim_career_3p` entries so keep inventory preview poses match in-mission |
| **Longbow zoom overrides** | 2052–2150 | Kruber Longbow disable/manual-zoom toggles; template patches at init (Restart required); zoom_condition_function gate after v6.11.0 |
| **Moonfire cosmetics & AOE** | 2160–2310 | v0.12.49+: puff VFX on impact + optional AOE revert (1.5m poison-class); dual-hook coverage for UnitExtension + HuskExtension |
| **Big Rebalance integration** | 2320–3130 | ~113 BR sub-toggles via `weapon_tweaker_big_rebalance.lua`; master delegates to `bt:is_br_active()` (v0.12.62+); apply + function hooks |
| **Regression test scaffold** | 38–57 | `/regression_test` command; four smoke checks validating past bug-fix state |
| **Debug commands** | 760–912 | `/animlog`, `/force3p`, `/force1p`, `/sm_probe`, `/dump_actions`, `/brace_to_repeater_dump` |
| **Backend hooks** | ~separate file | `weapon_tweaker_backend.lua`: loadout cache, cross-mod item unlock gating |

---

## Strengths

- **Animation system maturity.** Three-layer redirect/remap architecture with explicit per-career override tables. Polearm-class cross-character pairs (halberd↔billhook, spear↔polearm) handled through both template patches (inventory preview) and runtime hooks (in-mission). v0.12.60 nil-career guard prevents preview-unit redirect corruption.

- **Derived-class hook discipline.** Hooks target `MenuWorldPreviewer` (inventory preview), NOT base `HeroPreviewer`, per v0.12.17 fix and `feedback_vt2_class_hook_derived` rule. Separate equipment units for keep vs. mission vs. illusion browser (intentional asymmetry — illusion browser explicitly NOT hooked per `feedback_grip_offset_sign`).

- **Per-unit state tracking via weak keys.** `_unit_state[unit]` isolates per-unit career + weapon context using weak-keyed table, avoiding global player reference assumptions. Correctly handles husks (remote players' 3P bodies) by reading `career_system` extension first, then falling back.

- **Big Rebalance opt-in pattern.** ~113 BR sub-toggles all gate on `(get_mod("bt") or {}):is_br_active()`, with master registration outsourced to `buff_tweaker` (v0.12.62). Per-toggle apply functions run once at load and on setting change; function hooks installed unconditionally when master is on. **[bt retired 2026-06: the master registry is gone; with `get_mod("bt")` nil these toggles are now permanently inert.]**

- **Force-fire scoping.** Billhook stab_02 force-fire guarded with `_3p_weapon_remap == _3p_remap_spear_to_billhook` to avoid hijacking other weapons. Bypass mechanism via `_original_animation_event` capture prevents infinite hook recursion on `/force3p` commands.

- **Defensive DLC checks.** Interlocks with DLC unlock system; weapons with `required_dlc` that player doesn't own are silently excluded from unlocks and UI.

---

## Concerns / pending items

### [HIGH] File sizes exceed target (main: 4056 lines, br: 2552 lines)

**Status:** Flagged by QA, non-blocking for release. Main file ~18× target (150 advisory). BR file ~1.7× soft target (1500).

**Context:** Main file couples three distinct subsystems:
1. Cross-career unlocks + career action injection (120 lines)
2. Animation system (500 lines)
3. Everything else (3400+ lines: hooks, preview, scale/grip, cosmetics, BR wrapper, backend, debug commands)

BR file is table-driven (weapon/buff/damage profile patches) — size is natural for declarative content.

**Recommendation:** Future refactor could split main into:
- `_animation_system.lua` (~500 lines) — redirect/remap tables, hooks
- `_cosmetics.lua` (~300 lines) — scale/grip, skin swaps
- `_big_rebalance_wrapper.lua` (~200 lines) — simplified BR apply + hooks

Remaining core: ~2000 lines. **No production impact; structural only.**

---

### [MED] Audit P1 item (from 2026-05-01 pass): `mod.weapon_unlock_map` export

**Status:** RESOLVED in v0.12.68-dev. Export deleted per cross-repo grep confirming zero consumers. Internal `local weapon_unlock_map` (line 59) retained — load-bearing for apply logic.

---

### [MED] `weapon_tweaker_backend.lua:91` `set_loadout_item` hook signature

**Status:** Audit finding, v0.12.65 partial fix.

**Current:** Hook receives 4 positional args (`func, self, backend_id, career_name, slot_name`) but vanilla method has 5th arg `optional_loadout_index`. Passing all args to `func()` now corrected in v0.12.65 per CHANGELOG.

**Verification needed:** Versus mode loadouts with multiple loadout indices to confirm 5th arg propagates correctly.

---

### [MED] ItemMasterList lookups without `rawget` on user-input paths

**Status:** ~3 locations flagged in prior pass. Most are safe by code-path inspection but not defensive.

**High-priority sites:**
- `/forge <key>` command (user-typed weapon key) — should use `rawget` before lookup
- Stale inventory item keys from save data — should use `rawget` before access

**Low-priority sites** (iteration over `pairs(ItemMasterList)`, backend item keys):
- Safe by context (existing keys) but brittle on future refactors
- No crash path known

**Recommendation:** Wrap high-priority user-input paths in `rawget` checks per CLAUDE.md §DLC Ownership Gate pattern. Low-priority can stay as-is.

---

### [MED] Polearm preview diagnostic still in place (v0.12.56+)

**Status:** Intentional temporary debug code from v0.12.56 onwards. `_wt_polearm_preview_diag` helper logs on every equip of polearm-class weapons.

**Plan:** Remove once all four polearm weapons (halberd / Tuskgor / billhook / elf spear) confirmed visually correct on every career across one user session. Cost: 4 log lines per equip while debugging active. No user-facing impact.

---

### [LOW] Grip offset compounds on unit recycle (line 1063)

**Status:** Safe in practice. Engine spawns fresh unit instances per equip, so offset applies once. If future refactor recycles units, offset would apply additively.

**Safeguard:** Position capture at line 1063 is NOT pcall-wrapped (reads) while set on next line IS (writes). Inconsistent for symmetry, though both are safe by inspection.

---

### [LOW] `_last_3p_unit` assigned but never read (line 992)

**Status:** Dead variable. Set inside animation_event hook, never read. Was likely used for debug in earlier versions.

**Recommendation:** Safe to remove.

---

### [LOW] Three widget IDs defined but never read

**Status:** `debug`, `enable_weapon_debug_logging` in `_data.lua` — both defined but `mod:get(...)` never called.

**Recommendation:** Either add code that reads them (gating debug output) or delete from data + localization.

---

## What's changed since v0.12.01 (2026-05-01 baseline)

**v0.12.68-dev (2026-05-23):** Removed unused `mod.weapon_unlock_map` public export. Cross-repo audit confirmed zero callers.

**v0.12.67-dev (2026-05-22):** Authentic Brace primary spread 3× → 2× per user feel-test feedback.

**v0.12.66-dev (2026-05-22):** Added `/regression_test` command with four smoke checks for past bug-fix state.

**v0.12.65-dev (2026-05-22):** Fixed `set_loadout_item` passthrough to forward all args (including optional 5th `optional_loadout_index`).

**v0.12.64-dev (2026-05-22):** Fixed Kruber-on-billhook missing swing animations. Regression was actually in v0.12.55/56 (not v0.12.60); added fallback `_resolve_3p_remap` call in wield-event path.

**v0.12.63-dev (2026-05-21):** Fixed 10 trait-description localization strings with literal `%` characters triggering VMF `safe_string_format` crashes. Escaped to `%%`.

**v0.12.62-dev (2026-05-21):** Externalized Big Rebalance master toggle + 419-line registration list to new sister mod `buff_tweaker` (`bt`). wt now delegates to `bt:is_br_active()` for master gate.

**v0.12.61-dev (2026-05-21):** Integrated Core's Big Rebalance (opt-in). Added `weapon_tweaker_big_rebalance.lua` (~2400 lines) + BR sub-toggles (~113 widgets).

**v0.12.60-dev (2026-05-20):** Fixed polearm preview pose bug — added `career and` short-circuit to `should_redirect` formula to prevent nil-career preview units from firing incorrect redirect on alternate bodies.

**v0.12.58-dev (2026-05-20):** Kruber Longbow disable-zoom switched to `zoom_condition_function` gate after game v6.11.0 dropped `aim_zoom_delay` from 2.0 → 0.22.

**v0.12.57-dev (2026-05-20):** Removed Skullsplitter / Skull-Splitter+Shield / Bardin Hammer+Shield from Kruber per user direction. Twelve `(career, weapon)` pairs stripped from `weapon_unlock_map`.

**v0.12.55/56/59-dev (2026-05-20):** Polearm preview root-cause investigation and diagnostic additions (billhook/halberd/Tuskgor/elf-spear stances in keep inventory).

**v0.12.49-dev (2026-05-19):** Added Moonfire cosmetic puff + AOE revert toggles (both opt-in, default OFF).

**v0.12.48-dev (2026-05-19):** Dropped Warrior Priest from ranged cross-character ports (completes `feedback_vt2_no_bows_on_warrior_priest` rule).

---

## File / module map

| Module | Lines | Purpose |
|--------|-------|---------|
| `weapon_tweaker.lua` | 4056 | Main logic: unlocks, animation system, hooks, scale/grip, BR wrapper, debug commands |
| `weapon_tweaker_backend.lua` | 242 | Backend hooks: loadout cache, mod-unlock gating, deferred init |
| `weapon_tweaker_big_rebalance.lua` | 2552 | BR apply logic + function hooks (Flamethrower/Beam/TrueFlight), deferred to `buff_tweaker` master |
| `weapon_tweaker_big_rebalance_defs.lua` | ~800 | BR-owned pure-data definitions (damage profiles, explosion templates, buff templates) |
| `weapon_tweaker_data.lua` | ~999 | VMF settings widgets (595 setting IDs, ~113 BR toggles) |
| `weapon_tweaker_localization.lua` | ~689 | Display labels for all settings |
| `weapon_tweaker.mod` | 35 | VMF mod registration entry point |
| `itemV2.cfg` | 20 | Workshop metadata (visibility=friends_only per user-dictates rule) |

---

## Cross-mod dependencies (consumption & externals)

**Inbound (others consume wt):**
- `mod.weapon_unlock_map` — removed in v0.12.68; no external consumer found.
- ~~`mod.MOD_VERSION`~~ — currently `local MOD_VERSION`; not exposed. `lobby_tweaker` manifest reader expects `mod.MOD_VERSION` and falls back to nil when not found — functional but inelegant.

**Outbound (wt calls get_mod on others):**
- `character_weapon_variants` — presence detection only (guarded with `~= nil` check). ~~When installed, wt skips adding `_cwv_managed` career rows for certain weapons to avoid duplicate unlock widgets.~~ **Superseded (Issue #368, 2026-07-05):** wt and CWV are independent (overlap allowed); the `cwv_managed` cede is being removed. wt now uses the presence flag to default its overlapping cross-char toggles ON and to cover CWV's `cwv_variant` items — it is the availability control surface. See `CROSS_MOD_ARCHITECTURE.md`.
- `buff_tweaker` (`bt`) — BR master gate. Pattern: `if not (bt and bt.is_br_active) then return false end`.

**Shared global writes:**
- `DamageProfileTemplates` / `ExplosionTemplates` / `BuffTemplates` — wt writes per-name overlays for BR features (e.g., Moonfire AOE template, Hagbane DoT profile). Coordinated by `if not BT[name] then` guard in `bt` and `if not NL.buff_templates[name] then` guard in `crt`. Status: coordinated, no stomp.

---

## Code quality findings

**Strengths:**
- Forward-ref audit clean. `_safe_has_anim` (line 372) defined BEFORE all callers (fixed after v0.9.x era bugs).
- Hook variant discipline: zero instances of `mod:hook_safe(..., function(func, ...))` with wrong signature.
- Early returns prevent 1P interference: `_local_fp_unit` guard at line 987 short-circuits before any redirect/remap.
- Per-unit career resolution (line 926–963) reads from `career_system` extension first, correct.

**Minor issues:**
- `_last_3p_unit` (line 992) set but never read — dead variable.
- Three widget IDs (`debug`, `enable_weapon_debug_logging`, three feature_enabled ones) never read via `mod:get(...)` — dead settings.
- Position capture at line 1063 NOT pcall-wrapped (inconsistent; both safe by inspection).

**No blocking issues.** All prior P1 items resolved or verified safe.

---

## Verdict

**READY (heavily-used, mature).** The animation system is production-hardened with comprehensive bug fixes (v0.12.60 preview, v0.12.64 billhook regression). Big Rebalance integration is clean (delegated to `bt`). Cross-career unlock paths are solid. File sizes exceed structural targets but are non-blocking.

**Deploy confidence:** HIGH. No HIGH-severity bugs open. MED items are audit findings or minor hygiene (unused exports, optional code path improvements). One intentional debug helper (polearm diagnostic) scheduled for removal once testing complete.

---

## Notes for future maintainers

1. **Animation remap changes require deep context.** Read `feedback_animation_remap_rules.md` + `feedback_animation_remap.md` before touching `_anim_redirect`, `_career_anim_redirect`, `_3p_remap_*` tables, or the Unit.animation_event hook. The three-layer system is correct but fragile — nil event names, wrong career resolution, and skipped clears on non-weapon `to_` events have each caused regressions in past versions.

2. **Derived-class hook on MenuWorldPreviewer, not HeroPreviewer.** The `equip_item` hook MUST target the derived class (keep inventory), not the base class (team preview). VT2's `class()` copies parent methods at definition time — no `__index` chain. v0.12.16 shipped the bug; v0.12.17 fixed it. Never regress.

3. **Big Rebalance master is in `buff_tweaker` mod.** Do NOT re-ship registration list in wt. wt sub-toggles gate on `bt:is_br_active()`. Out-of-order load (bt after wt) = silent no-op for that session but doesn't crash. **[SUPERSEDED 2026-07-07 — bt retired 2026-06: bt no longer exists, so wt's BR sub-toggles are permanently inert (the guard returns false). Do not attempt to re-home the registry.]**

4. **MOD_VERSION bump on every build.** Required to visually verify hot-reload or restart loaded the new code. Appended to Workshop title automatically by launcher.

5. **The "promo" rarity patch must stay at top of file.** Line 8-16 rewrites `NetworkLookup.weapon_rarity_to_item_rarity` to add `"promo"` → `"exotic"` mapping. Without it, equipping a crafted item crashes NetworkLookup. Idempotent; no side effects.

6. **Three weapon rendering paths: in-game, inventory preview, illusion browser.** wt covers 1 & 2 only (intentional per `feedback_grip_offset_sign` — illusion browser should show un-offset weapon). Do not add grip-offset hook to `LootItemUnitPreviewer` without consulting user.

7. **Three BR sub-dependencies unfixed in wt (per v0.12.61 CHANGELOG).** `DamageUtils.stagger_ai`, `apply_buffs_to_damage`, `calculate_damage` rewrites are et-owned. Some wt BR toggles reference them — toggles work alone but reach full balance only with et's stagger rewrite. This is intentional cross-mod design.

8. **Audit clean (v0.12.68).** `mod.weapon_unlock_map` was removed — no external consumer found via cross-repo grep.
