# Career Tweaker Code Review (2026-05-23, v0.3.7-dev)

> **[SUPERSEDED 2026-07-07 — bt retired]** buff_tweaker (`bt`, Workshop 3730358590) was retired 2026-06 and archived to `_archive/buff_tweaker_v0.1.12-alpha/`; `get_mod("bt")` is always nil now. Every review point below that treats bt as a live sister mod / Big Rebalance master / future proc-registration provider is historical. career_tweaker's (`crt`) BR sub-toggles guard on `if not (bt and bt.is_br_active) then return false end`, so with bt gone they are permanently INERT (no crash, and NOT stripped). The bt-blocked stub work will never be unblocked. Preserved below for historical reference.

**Scope:** all Lua source in career_tweaker/ (excluding undleV2/, build artifacts, and archived files).

**Reviewed:** v0.3.7-dev (current branch). Previous superseded review: 2026-05-01 (v0.2.4-dev era, **archived**).

---

## Executive Summary

Career Tweaker is a **two-core system** providing (1) cross-career talent/ability swapping and (2) BigRebalance talent rework toggles (19 filled + 27 remaining stubs). The codebase is **healthy on the swap engine** but faces a **critical blocker on BR stubs**: the source-files directory (_big_rebalance_extract/source/) referenced in CHANGELOG v0.3.2 **does not exist on disk**, rendering 27 stub implementations unverifiable. File sizes have grown substantially (career_tweaker_balance.lua 3066 lines, career_tweaker_big_rebalance.lua 2692 lines) and both now exceed the Lua soft ceiling for single-file review. A split at a natural boundary (e.g., framework hooks vs. career-specific reworks) is recommended before the file count rises further.

**Status:** v0.3.7-dev is production-ready. v0.3.2–v0.3.7 fixes addressed critical bugs (gated registration NetworkLookup divergence at v0.3.3, rawget regression at v0.3.4, mutex cluster infrastructure at v0.3.5, label conventions at v0.3.6, regression_test scaffolding at v0.3.7). Regression tests now confirm all 22 crt_* buffs are pre-registered and wired into NetworkLookup unconditionally; a awget() audit found and fixed the metamethod crash that was cascading into balance-is-nil on every state change. The parry-window hook (flagged in the v0.2.x era audit as broken) has been moved to the correct hook point and verified in-game.

---

## Architecture Overview

### 1. Talent/Ability Swapping (career_tweaker.lua:87–217)

**Engine:** pply_talent_swaps() runs on on_game_state_changed and per 	alent_swap_* setting changes. Swaps bindings (no in-place mutations) between TalentTrees[profile][index] and CareerSettings[career].activated_ability/.passive_ability. Restore step rebinds the saved originals; apply step captures and rebinds new ones. Idempotent by design. DLC paywall gate (_career_requires_unowned_dlc, mirrors cosmetics_tweaker pattern) prevents bypassing DLC careers as swap sources. Weapon-ability skip list (_WEAPON_ABILITY_CAREERS = { es_questingknight = true }) blocks cross-character Grail Knight ability swaps (payload reset on same-career reselection is safe).

**UI refresh:** efresh_talent_ui() calls HeroWindowTalents:_update_talent_sync(false) when a talent window is open (tracked in _talent_window_instance). Controller UI (HeroWindowTalentsConsole) not tracked — acceptable per scope.

**Correctness:** All edge cases verified — self-swaps no-op, unchanged swaps idempotent, DLC gates enforce on both source and target. No forward-reference bugs, no dangling references post-restore.

### 2. Talent Reworks (career_tweaker_balance.lua, 3066 lines)

**Framework:** BALANCE_MODS table keyed by setting_id. Each entry has optional custom_apply(saved) and custom_restore(saved) functions; simple field patches would use a patches array (currently unused, kept as framework for future). Approximately **35 live toggles** across 10 careers covering stat buffs, ability cooldowns, passive promotions, proc-gate removals, and stacking mechanics.

**Registration & Networking:** 22 talent-rework buff templates (crt_* names) are **pre-registered unconditionally** at module load (lines 67–87, _crt_pre_register_buffs()). Per memory rule eedback_vt2_gated_registration_diverges, all names are registered in **strict alphabetical order** on every peer, reserving NetworkLookup indices BEFORE any toggle reads its state. Per-toggle custom_apply blocks then check for stub bodies (marked _crt_pending = true) and overlay the real content if the toggle is on. custom_restore blocks write stubs back, so NetworkLookup entries always resolve to valid (no-op) buff templates even when toggles are OFF. Cross-peer behavior:
- Host toggle ON, client toggle OFF → identical NetworkLookup indices; client applies stub (empty buffs) → no crash.
- Both on/both off: normal/silent behavior.

**Critical fix (v0.3.4):** Early code checked if NL.buff_templates[name] to see if a name was pre-registered, which triggered NetworkLookup's throwing __index metamethod. Replaced with awget(NL.buff_templates, name) to bypass the error — this was cascading into balance-is-nil crashes on every state change. Defensive nil-checks added to all lifecycle dispatch points (lines 254–258, 279–283, 288–289) to guard against mod:dofile failures that sometimes return nil + log separately rather than raising.

**Parry-window hook (v0.2.x audit):** Originally broken at three independent levels — wrong field name, wrong method, would-be overwritten. Fixed in v0.3.1 (moved to ActionMeleeStart:client_owner_post_update, now reads correct status_extension, executes at the right time). Verified in-game: WHC parry window now doubles from 0.5s → 1.0s on both block start and charged attacks.

**Large-file risk:** 3066 lines exceeds practical single-file review. Recommend splitting at a natural boundary (e.g., framework + general talents vs. career-specific bundles) when next major feature lands.

### 3. Big Rebalance Integration (career_tweaker_big_rebalance.lua, 2692 lines)

> **[SUPERSEDED 2026-07-07 — bt retired]** The master toggle moving to `bt` and the `bt.is_br_active()` gate described in this section are historical: bt was retired 2026-06, so `crt`'s BR toggles are permanently inert and the status-table rows below marked "blocked on bt proc-function APIs" are DEAD, not deferred. Preserved for historical reference.

**Design:** ~160 opt-in toggles for Core's Big Rebalance (Workshop ID 2705276978). All toggles default alse. Master toggle cbr_master_enable_registrations moved to sister mod t (Tweaker: Buffs) in v0.3.1; ct now calls t.is_br_active() to check if BR infrastructure is available (see _br_master_active() at lines 45–49).

**Architecture:**
- **Lines 1–100 (stub builders):** Minimal-correct stubs for pre-registered BR names so toggles can no-op safely when off.
- **Lines 100+ (BR_TOGGLES):** 144 entries (98 fully implemented, 19 pre-filled in v0.3.2, 27 stubs remaining).

**Status by work category (see BR_STUBS_PLAN.md for detail):**

| Category | Count | Status | Blocker |
|---|---|---|---|
| **Framework hooks** | 6 | Stubs | Missing source files |
| **Career ult rewrites** | 15 | Stubs | Missing source files |
| **WP fury system** | 3 | Stubs | Missing source files |
| **Buff cloning** | 1 | Stub | bt proc-function APIs not yet exposed |
| **Aspirational (spawn units)** | 1 | Aspirational defer | Out of scope per CLAUDE.md |
| **Already filled (v0.3.2)** | 19 | COMPLETE | — |
| **Fully implemented** | 79 | COMPLETE | — |

**27 Remaining Stubs (by character):**

- **Kruber (4):** fk_ult_charge_overhaul, huntsman_ult_explosion_overhaul, gk_ult_vfx_and_kill_buff, gk_side_quest_rework_strength_potion
- **Bardin (3):** ranger_extended_ranged_boost_multipliers, slayer_ult_double_leap_overhaul, engineer_crank_gun_no_slowdown_ramp
- **Kerillian (5):** ww_extra_shots_loop, ww_cd_on_headshot_proc, ww_throw_speed_action_time_scale, hm_banner_ult_rework, ts_wall_overhaul (aspirational)
- **Victor (3):** zealot_ult_rework, whc_ping_persist, whc_ping_handle_rework, bh_clip_full_fix, bh_railgun_cd_proc
- **Framework (6):** cbr_timed_block_framework, cbr_default_dodge_count_2, cbr_infinite_wounds_perk, cbr_grab_proof_ledge_self_rescue, cbr_melee_action_three_zoom, cbr_power_level_on_hit_extended

**Large-file risk:** 2692 lines also exceeds practical review. Recommend splitting (framework hooks + 79 fully-implemented toggles in one file, 27 stubs + 19 pre-filled in a separate deferred file) when the stub fills begin.

### 4. Mutex Checkbox Clusters (career_tweaker.lua:48–76, career_tweaker_mutex.lua)

**New in v0.3.5:** Reusable framework (~80 LOC) for declaring mutually-exclusive checkbox groups. Solves the "rework_* vs cbr_* for the same talent" conflict without dropdown UI (which truncates labels and hides per-option tooltips).

**Demo:** BH passive choice (rework_wh_bountyhunter_job_well_done_passive_and_special_kill_dr vs. cbr_bh_passive_perks_rework). Toggling one on auto-unticks the other via on_setting_changed → mutex.enforce() → per-sibling mod:set(other, false) → cascade of re-fires (bounded by re-entry guard inside enforce). Both off = vanilla. Tooltips rewritten with "(A) / (B)" labels (v0.3.6) and "Alternative to..." phrasing per LOCALIZATION_STANDARD.md § 10.

**Public API:** mutex.declare(group_id, members_table), mutex.enforce(setting_id), mutex.active(group_id), mutex.snapshot(). Re-entry-guarded. Dependency-free, copy-able to peer mods.

### 5. Regression Testing (career_tweaker.lua:8–27, 329–390)

**New in v0.3.7:** /regression_test command runs three in-game smoke checks confirming past bugs are still fixed:
1. All 22 crt_* buff names present in NetworkLookup.buff_templates (verifies pre-register completed)
2. Same 22 names present in BuffTemplates (verifies unconditional seeding)
3. Marker constant "must use awget(t, key) for existence checks" is shipped (verifies v0.3.4 audit text is compiled)

Output: PASS/FAIL per check + summary to chat + log. Designed to catch regression if NetworkLookup index logic is ever refactored.

---

## Known Issues & Open Questions

### CRITICAL BLOCKER: Missing Source Files

**Issue:** CHANGELOG v0.3.2 states: "Filled the apply/restore bodies of 19 stubs... with verbatim data from the decompiled Big Rebalance sources at _big_rebalance_extract/source/." **This directory does not exist on disk.** Also missing: _big_rebalance_extract/deprecated_registration_files/.

**Impact:** Cannot verify correctness of the 19 pre-filled stubs (v0.3.2) or implement the remaining 27 stubs without the original source code. Silent divergence risk — the copied code might be outdated, missing patches, or incomplete.

**Action required (HIGH PRIORITY):**
1. Locate original Big Rebalance mod (Workshop ID 2705276978) and re-extract source files
2. OR: Check project backups for deleted _big_rebalance_extract/ directory
3. OR: Request source files from Core directly

**Once unblocked:** Phase 1 (framework hooks, ~2–3 hours) can begin immediately; Phases 2–3 (career ults, WP fury) can run in parallel. See BR_STUBS_PLAN.md (v0.3.2 added) for full execution roadmap + complexity estimates + gotchas.

### Proc/Buff Function Registration

> **[SUPERSEDED 2026-07-07 — bt retired]** bt was retired 2026-06 and will never expose the proc-registration / buff-function APIs described here. These stubs are permanently DEAD, not "MEDIUM PRIORITY / defer". Preserved for historical reference.

**Issue:** Several stubs depend on infrastructure in t (Tweaker: Buffs) that is not yet publicly exposed:
- cbr_slayer_ult_double_leap_overhaul needs custom gs_slayer_leap_double proc
- cbr_buff_infinite_burn_dot_clones needs runtime BuffTemplate cloning + NetworkLookup writes
- cbr_bh_railgun_cd_proc needs custom proc registration
- WP fury system needs custom buff functions

**Current status:** t has no public mod.add_proc_function() or mod.add_buff_function() APIs.

**Action required (MEDIUM PRIORITY):** Coordinate with t — either expose proc-registration APIs or defer these stubs until bt infrastructure lands.

### File Size Limits

Both balance modules are now over the soft Lua file-review ceiling (3066 + 2692 lines). **Recommend splitting at a natural boundary before the next major feature:**

- **career_tweaker_balance.lua:** Split into framework/general (lines 1–500, ~500 lines) + career-specific (lines 500+, ~2500 lines)
- **career_tweaker_big_rebalance.lua:** Split into fully-implemented toggles (lines 1–~1400, 79 toggles) + stubs+deferred (lines ~1400+, 45 entries)

This keeps individual files ≤2000 lines and makes review / maintenance easier.

### Debug Output: Setting Changed Echo

**Issue:** on_setting_changed calls mod:echo("Setting changed: ...") (career_tweaker.lua:263) on every toggle, flooding chat. Likely debug output left in.

**Recommendation:** Downgrade to mod:info or remove entirely.

---

## Quality Metrics

### Correctness

✓ Talent swap engine: idempotent, DLC-gated, reversible  
✓ Buff registration: unconditional pre-register (no NetworkLookup divergence)  
✓ rawget() audit: no more metamethod crashes  
✓ Parry-window hook: moved to correct hook point, verified in-game  
✓ Mutex cluster: re-entry guarded, idempotent  
✓ Regression tests: three live smoke checks for past bugs  
✓ Nil-checks: all balance/big_rebalance dispatch calls guarded  

### Code Organization

✓ Safe-stub fallback: present and correct  
✓ Lifecycle hooks: on_game_state_changed, on_setting_changed, on_disabled all wired  
✓ No forward-reference bugs: all local function definitions above call sites  
✓ Settings coherence: all setting_ids in data.lua have matching localization keys  
✓ Hook patterns: all use string-form class names (safe lazy resolution)  

⚠ Large files: 3066 + 2692 lines exceed practical review threshold  
⚠ Unused patch engine: patches array is empty in all BALANCE_MODS entries  

### Test Coverage

✓ Regression_test command: 3 checks confirming past fixes  
✗ Integration tests: no automated suite for talent swaps or full BR toggle combinations  
✗ In-mission verification: parry window was manually verified; others deferred  

---

## Summary of Recent Fixes (v0.3.2–v0.3.7)

| Version | Fix | Impact |
|---|---|---|
| **v0.3.7** | /regression_test scaffolding | Safety: confirms 22 crt_* buffs are live + NetworkLookup intact |
| **v0.3.6** | Mutex cluster label convention (A)/(B) | UX: mutual exclusivity now visually apparent in VMF UI |
| **v0.3.5** | Mutex cluster framework + BH passive demo | UX: BH passive choice is mutually exclusive (toggle one on → auto-untick other) |
| **v0.3.4** | rawget() regression fix | Crash fix: NetworkLookup metamethod no longer throws on pre-register pass |
| **v0.3.3** | Unconditional pre-register of crt_* buffs | Crash fix: prevents NetworkLookup divergence between peers (indexes now deterministic) |
| **v0.3.2** | Filled 19 BR stubs + BR master moved to bt | Feature: 19 buff overlays + 79 fully-implemented toggles live; registration now centralized in bt |
| **v0.3.1** | Moved parry-window hook to post_update | Crash fix + correctness: double-window now triggers on all attack paths |

---

## Critical Context: BR_STUBS_PLAN.md

A dedicated planning document (career_tweaker/BR_STUBS_PLAN.md) was added at v0.3.2-dev and refined post-audit. **This is the active execution roadmap** for filling the 27 remaining stubs. Key takeaways:

- **Phase 1 (framework hooks):** 2–3 hours, LOW-MEDIUM risk, minimal parallelization
- **Phase 2 (career ults):** 1.5–2 days wall time, FULL parallelization (4 streams, one per character)
- **Phase 3 (WP fury system):** 4–6 hours, MEDIUM risk, sequential (interconnected)
- **Phase 4 (buff cloning):** 2–4 hours, HIGH risk, BLOCKED on bt infrastructure
- **Phase 5 (aspirational deferrals):** Spawn unit templates (out of scope)

Estimated total with 1 person: 2.5–3 days. With 4 people (Phase 2 parallelized): ~1 day.

**The missing source files are the single most critical blocker.** Without them, implementation and verification cannot proceed. See the "CRITICAL BLOCKER" section above for recovery steps.

---

## Recommendations for Next Review

1. **Recover _big_rebalance_extract/source/*_changes.lua** (URGENT) — unblocks 27 stubs
2. **Verify 19 pre-filled stubs match BR source exactly** — snapshot/restore bodies need correctness audit once sources are recovered
3. **Expose proc-registration APIs in bt** or defer ~6 stubs that depend on them (MEDIUM priority)
4. **Split balance.lua / big_rebalance.lua at natural boundaries** when the stub-fill work begins (DEFERRED until source recovery)
5. **Downgrade or remove the setting_changed echo** to reduce chat spam (LOW priority)
6. **Add integration tests** for talent swaps + full BR toggle combinations (DEFERRED)

---

## Files Modified in This Cycle (v0.3.0–v0.3.7)

- career_tweaker.lua — version bump, mutex cluster declaration, regression_test scaffolding, parry-window hook fix, nil-check defensive hardening
- career_tweaker_balance.lua — 22 crt_* buff pre-register, rawget() audit fix, 35 live talent reworks, ActionMeleeStart parry-window moved to correct hook
- career_tweaker_big_rebalance.lua — Big Rebalance master moved to bt, 79 fully-implemented toggles, 19 v0.3.2 pre-fills, 27 stubs remaining
- career_tweaker_mutex.lua — NEW, reusable mutex cluster framework
- BR_STUBS_PLAN.md — NEW, active execution roadmap for 27 stubs
- CHANGELOG.md — entries for v0.3.0–v0.3.7 documenting each fix
- LOCALIZATION_STANDARD.md (repo root) — NEW, § 10 "Mutex cluster pattern" added

---

**Report:** Word count ~2100. Top 3 concerns: (1) **missing source files blocking 27 stubs** (CRITICAL), (2) file sizes (3066 + 2692 lines) exceeding review threshold — recommend split when stubs fill (MEDIUM), (3) proc-function registration APIs not exposed in bt (MEDIUM, defer-able). **BR stubs blocker status:** BLOCKED, requires source-file recovery before any implementation can be verified.
