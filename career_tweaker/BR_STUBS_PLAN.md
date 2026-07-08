# BR_STUBS_PLAN.md

> **[SUPERSEDED 2026-07-07 — bt retired]** buff_tweaker (`bt`, Workshop 3730358590) was retired 2026-06 and archived to `_archive/buff_tweaker_v0.1.12-alpha/`; `get_mod("bt")` is always nil now. The shared Big Rebalance registry never became a permanent cross-mod dependency, so the stub-completion roadmap below is MOOT — career_tweaker's (`crt`) BR sub-features guard on `if not (bt and bt.is_br_active) then return false end` and are permanently INERT (no crash, and NOT stripped). Every plan item gated on bt shipping proc-registration APIs is DEAD; those futures will not happen. The stub inventory and mechanics notes are preserved below for historical reference.

27 stub pply = function() end entries in BR_TOGGLES (career_tweaker_big_rebalance.lua) 
to fill from Big Rebalance sources. Planning document + execution roadmap.

**Status:** RESEARCH ONLY (no implementations written). Blocked on missing source files.

---

## Executive Summary

- **Total stubs:** 27 (all empty pply = function() end)
- **Already filled (v0.3.2-dev):** 19 stubs with BuffTemplate/ExplosionTemplate overlays
- **Remaining:** 27 stubs across 3 work categories
- **Total BR_TOGGLES entries:** 144 (98 fully implemented + 27 stubs + 19 pre-filled = comprehensive)
- **Time estimate:** ~1-2 days total (parallelizable by career + infrastructure bucket)
- **Blocking issue:** Source files (\_big_rebalance_extract/source/*_changes.lua\) referenced in CHANGELOG v0.3.2 do not exist on disk

---

## Stub Inventory Summary

### Total Count Confirmed: 27 Empty Stubs

These are in career_tweaker_big_rebalance.lua (lines 499-2655):

1. **Framework Hooks (6):** General-purpose mechanic gates
   - cbr_timed_block_framework, cbr_default_dodge_count_2, cbr_infinite_wounds_perk
   - cbr_grab_proof_ledge_self_rescue, cbr_melee_action_three_zoom, cbr_power_level_on_hit_extended

2. **Career Ult Rewrites (15):** Wholesale ability overhaul per character
   - **Kruber:** fk_ult_charge_overhaul, huntsman_ult_explosion_overhaul, gk_ult_vfx_and_kill_buff, gk_side_quest_rework_strength_potion
   - **Bardin:** ranger_extended_ranged_boost_multipliers, slayer_ult_double_leap_overhaul, engineer_crank_gun_no_slowdown_ramp
   - **Kerillian:** ww_extra_shots_loop, ww_cd_on_headshot_proc, ww_throw_speed_action_time_scale, hm_banner_ult_rework, ts_wall_overhaul
   - **Victor:** zealot_ult_rework, whc_ping_persist, whc_ping_handle_rework, bh_clip_full_fix, bh_railgun_cd_proc

3. **Warrior Priest Fury System (3):** Interconnected subsystem
   - cbr_wp_fury_rework, cbr_wp_target_action_init, cbr_wp_target_buff_list

4. **Proc/Buff Cloning (1):** Runtime infrastructure
   - cbr_buff_infinite_burn_dot_clones

5. **Aspirational Deferrals (1):** Out-of-scope (spawn unit templates)
   - cbr_ts_wall_overhaul (marked aspirational; needs spawn unit infra)

---

## Work Breakdown Structure

### Framework Hooks: 6 stubs, ~90-160 LOC total

| Stub | Hook Target | Complexity | Est. LOC |
|---|---|---|---|
| cbr_default_dodge_count_2 | ActionMeleeStart | SIMPLE | 5-10 |
| cbr_melee_action_three_zoom | ActionUtils | SIMPLE | 5-15 |
| cbr_infinite_wounds_perk | TalentExtension.apply_buffs | SIMPLE | 10-15 |
| cbr_grab_proof_ledge_self_rescue | ActionUtils (ledge path) | MEDIUM | 20-30 |
| cbr_timed_block_framework | ActionBlock + GenericStatus | MEDIUM | 30-50 |
| cbr_power_level_on_hit_extended | AiUtils (H3 hook) | MEDIUM | 20-40 |

**Session time:** 2-3 hours | **Risk:** LOW-MEDIUM | **Parallelizable:** NO (hooks may collide)

---

### Career Ult Rewrites: 15 stubs, ~1400-2180 LOC total

**Batch A — Kruber (4 stubs):**
- cbr_fk_ult_charge_overhaul: CareerAbilityESKnight._run_ability override (COMPLEX, 100-150 LOC)
- cbr_huntsman_ult_explosion_overhaul: 2 explosions + buffs overlay (COMPLEX, 80-120 LOC)
- cbr_gk_ult_vfx_and_kill_buff: VFX + buff overlay (COMPLEX, 60-100 LOC)
- cbr_gk_side_quest_rework_strength_potion: Potion rework (MEDIUM, 40-60 LOC)

**Batch B — Bardin (3 stubs):**
- cbr_ranger_extended_ranged_boost_multipliers: CareerExtension.has_ranged_boost override (COMPLEX, 50-80 LOC)
- cbr_slayer_ult_double_leap_overhaul: Double leap + 4 buffs + custom proc (COMPLEX, 120-180 LOC)
- cbr_engineer_crank_gun_no_slowdown_ramp: Buff function override (MEDIUM, 30-50 LOC)

**Batch C — Kerillian (5 stubs):**
- cbr_ww_extra_shots_loop: ActionCareerWEWaywatcher hook + proc (COMPLEX, 80-120 LOC)
- cbr_ww_cd_on_headshot_proc: Proc gate + ActionUtils hook (MEDIUM, 40-60 LOC)
- cbr_ww_throw_speed_action_time_scale: ActionUtils animation hook (MEDIUM, 30-50 LOC)
- cbr_hm_banner_ult_rework: CareerAbilityWEMaidenGuard override + 30+ buffs (COMPLEX, 150-220 LOC)
- cbr_ts_wall_overhaul: 5 ActionCareerWEThornsister hooks + spawn unit (ASPIRATIONAL, DEFER)

**Batch D — Victor (3 stubs):**
- cbr_zealot_ult_rework: CareerAbilityWHZealot._run_ability override (COMPLEX, 100-160 LOC)
- cbr_whc_ping_persist + cbr_whc_ping_handle_rework: PingSystem hooks (MEDIUM, 60-110 LOC combined)
- cbr_bh_clip_full_fix + cbr_bh_railgun_cd_proc: GenericAmmoUserExtension + proc (MEDIUM, 70-130 LOC combined)

**Session time:** ~1.5-2 days (4 sessions × 3-5 hours, parallelizable by batch) | **Risk:** MEDIUM-HIGH | **Parallelizable:** FULL (by career batch)

---

### Warrior Priest Fury System: 3 stubs, ~140-210 LOC total

- cbr_wp_fury_rework: PassiveAbilityWarriorPriest hook + 2 buff overlays (COMPLEX, 80-120 LOC)
- cbr_wp_target_action_init: ActionCareerWHPriest hook (MEDIUM, 40-60 LOC)
- cbr_wp_target_buff_list: Buff overlay (SIMPLE, 20-30 LOC)

**Session time:** 4-6 hours | **Risk:** MEDIUM | **Parallelizable:** NO (interconnected) | **Note:** Must fill as unit

---

### Buff Cloning: 1 stub, ~80-120 LOC

- cbr_buff_infinite_burn_dot_clones: Runtime BuffTemplate + NetworkLookup cloning loop (COMPLEX, 80-120 LOC)

**Session time:** 2-4 hours | **Risk:** HIGH | **Parallelizable:** NO | **Blocker:** Requires bt's proc-function infra **[DEAD 2026-07-07: bt retired 2026-06; this infra will not ship.]**

---

## Execution Roadmap (Suggested Sequence)

### Phase 1: Framework Hooks (1 session, 2-3 hours)

Quick wins to unblock ability tests. Recommended order:
1. cbr_default_dodge_count_2 (SIMPLE)
2. cbr_melee_action_three_zoom (SIMPLE)
3. cbr_infinite_wounds_perk (SIMPLE)
4. cbr_grab_proof_ledge_self_rescue (MEDIUM)
5. cbr_timed_block_framework (MEDIUM)
6. cbr_power_level_on_hit_extended (MEDIUM)

**Risk:** Hooks may collide with existing ct code or other reworks. Check each target in ct for prior hooks.

---

### Phase 2: Career Ult Rewrites (4 parallel sessions, 1.5-2 days wall time)

Run one person per character batch:
- **Stream A:** Batch A (Kruber, 4 stubs, 3-4 hours)
- **Stream B:** Batch B (Bardin, 3 stubs, 3-4 hours)
- **Stream C:** Batch C (Kerillian, 4 stubs, 4-5 hours) — longest batch
- **Stream D:** Batch D (Victor, 3 stubs, 3-4 hours)

All can run in parallel. Regroup for smoke tests.

**Risk:** Each ult is a unique ability override. Require source code review + verbatim copy + in-mission test.

---

### Phase 3: Warrior Priest Fury System (1 session, 4-6 hours)

After Phase 1-2 to understand ct's hook patterns.

**Dependencies:** Must understand vanilla WP passive + ult lifecycle

---

### Phase 4: Buff Cloning (1 session, 2-4 hours, BLOCKED)

> **[SUPERSEDED 2026-07-07 — bt retired]** bt was retired 2026-06; the proc-function infrastructure this phase waited on will never ship. This phase is DEAD, not merely blocked. Preserved below for historical reference.

**Blocker:** Requires bt to expose proc-function registration APIs. Defer until bt infrastructure lands.

---

### Phase 5: Aspirational Deferrals (DEFER INDEFINITELY)

- cbr_ts_wall_overhaul: Mark "aspirational (spawn unit template out-of-scope)" in CHANGELOG
- Spawn unit templates: Out of scope per CLAUDE.md; remove from stub list

---

## Critical Blockers & Dependencies

### BLOCKER 1: Missing Source Files (HIGH PRIORITY)

The CHANGELOG v0.3.2 states:
\\\
Filled the apply/restore bodies of 19 stubs in \career_tweaker_big_rebalance.lua\
with verbatim data from the decompiled Big Rebalance sources at \_big_rebalance_extract/source/\.
\\\

But the \_big_rebalance_extract/\ directory **does not exist** on disk. Also referenced (and missing):
- \_big_rebalance_extract/deprecated_registration_files/\

**Action items:**
1. Locate the original Big Rebalance mod (Core's Workshop #2705276978)
2. Re-extract or reconstruct the career_*_changes.lua files
3. OR: Check project backups for deleted \_big_rebalance_extract/\ directory
4. OR: Request the source files from Core directly

**Unblocks:** All 27 stubs; without this, we cannot verify correctness of copied code.

---

### BLOCKER 2: Proc/Buff Function Registration (MEDIUM PRIORITY)

> **[SUPERSEDED 2026-07-07 — bt retired]** bt was retired 2026-06 and will never expose the `add_proc_function` / `add_buff_function` APIs discussed here. The ~6 stubs that depend on them are permanently DEAD, not deferred. Preserved below for historical reference.

Several stubs depend on infrastructure in bt (Tweaker: Buffs):
- cbr_slayer_ult_double_leap_overhaul: needs custom \gs_slayer_leap_double\ proc
- cbr_buff_infinite_burn_dot_clones: needs runtime BuffTemplate cloning capability
- cbr_bh_railgun_cd_proc: needs custom proc registration
- WP fury system: needs custom buff functions

**Current status:** bt has no public APIs for \mod.add_proc_function()\ or \mod.add_buff_function()\.

**Action items:**
1. Clarify: Will bt expose these APIs?
2. If yes: When? (May affect Phase 4 scheduling)
3. If no: Can these stubs be deferred until a later bt update?

**Unblocks:** ~6 of 27 stubs

---

### BLOCKER 3: Spawn Unit Templates (LOW PRIORITY, ASPIRATIONAL)

- cbr_hm_banner_ult_rework: references banner spawn unit (beyond buff overlays)
- cbr_ts_wall_overhaul: references wall spawn unit + 5 action hooks

Per CLAUDE.md: "Spawn unit templates are intentionally out-of-scope for ct alone."

**Action items:**
1. Confirm spawn units are aspirational (not blocking critical functionality)
2. Mark cbr_ts_wall_overhaul as "intentional forward-compat placeholder" in CHANGELOG
3. Document in tooltips: "Buff overlay only; spawn unit cosmetics deferred"

**Unblocks:** Allows 2 stubs to be completed at reduced scope (buff overlays only)

---

## Gotchas & Mitigations

| Risk | Gotcha | Mitigation |
|---|---|---|
| **Ult override diff** | Each \_run_ability\ override must match BR source exactly. Any delta causes silent behavior divergence. | Copy-paste verbatim from BR source; don't refactor. Snapshot vanilla method in \saved.*\. In-mission test every ult. |
| **Hook collision** | Multiple hooks on same Class+method can shadow each other (see v0.2.34 incident). | Search ct + other mods for existing hooks on target before implementing. Use \hook_safe\ + re-entry guards. |
| **Ranged boost global state** | CareerExtension.has_ranged_boost override affects all ranged abilities across all heroes. | Add career gate: \if not is_ranger() then return vanilla()\. Test cross-career weapon swap + ammo regen. |
| **Dodge count default** | Dodge count may be hardcoded in C++ or set at multiple hook points. Setting only ActionMeleeStart may not stick. | Search decompile for all dodge-count references. Test by melee->range->melee swap cycles. |
| **Ping system data corruption** | PingSystem hooks at low-level networking layer. Incorrect data structure manipulation could corrupt UI state. | Preserve vanilla data structure layout. Test 4-player ping lifecycle (create/update/remove). |
| **Proc registration timing** | If bt doesn't pre-register proc functions unconditionally, toggle divergence risk re-appears. | Coordinate with bt: either pre-register all procs at module load (like buff templates), OR defer proc-dependent stubs. **(Moot 2026-07-07: bt retired 2026-06.)** |
| **NetworkLookup divergence** | Gated per-toggle writes to NetworkLookup can diverge host vs client (see v0.3.3 incident). | All NetworkLookup writes must happen unconditionally at module load (pre-register stubs). Per-toggle apply/restore must work on pre-registered entries only. |

---

## Sample Stub Implementation Pattern

### SIMPLE: Framework Hook

\\\lua
BR_TOGGLES.cbr_default_dodge_count_2 = {
    apply = function(saved)
        -- Set default dodge count to 2 when toggle is on
        -- Hook target: ActionMeleeStart (needs source code to confirm exact location)
        -- Exact implementation: TBD from Big Rebalance source
    end,
    restore = function(saved)
        -- Revert to vanilla default (1)
    end,
}
\\\

---

### COMPLEX: Ability Override

\\\lua
BR_TOGGLES.cbr_fk_ult_charge_overhaul = {
    apply = function(saved)
        if not _G.CareerAbilityESKnight then return end
        saved.fk_ult_old = _G.CareerAbilityESKnight._run_ability
        _G.CareerAbilityESKnight._run_ability = function(self, ...)
            -- Verbatim copy of BR's FK ult rework (~50-100 LOC)
            -- References pre-registered buff/damage-profile names
        end
    end,
    restore = function(saved)
        if saved.fk_ult_old and _G.CareerAbilityESKnight then
            _G.CareerAbilityESKnight._run_ability = saved.fk_ult_old
            saved.fk_ult_old = nil
        end
    end,
}
\\\

---

## Pre-Implementation Checklist

Before coding any stub:

- [ ] Source code location: Big Rebalance repository / decompile / CHANGELOG reference
- [ ] Target method/class: Identified in VT2 decompile
- [ ] Snapshot plan: What state gets saved in \saved.*\ for restore?
- [ ] Restore logic: Written FIRST (easier to verify safety)
- [ ] Apply logic: Copied verbatim from BR source (no hand-translation)
- [ ] No constants hardcoded: All numeric values match BR spec
- [ ] Tooltip/localization: Matches the behavior being added
- [ ] Hook collision check: Search ct + wider codebase for same hook target
- [ ] Vanilla method safety: Don't call nil methods or undeclared functions
- [ ] Smoke test plan: (In-mission or UI test, depending on feature)
- [ ] Co-load test plan: Test with wt + et + bt all enabled

---

## Estimated Completion Timeline

| Phase | Category | Sessions | Duration | Parallelizable |
|---|---|---|---|---|
| 1 | Framework hooks | 1 | 2-3 hours | Partial |
| 2 | Career ults | 4 parallel | 1.5-2 days | FULL |
| 3 | WP fury | 1 | 4-6 hours | NO |
| 4 | Buff cloning | 1 | 2-4 hours | NO (BLOCKED) |
| **Total** | **27 stubs** | **~7 sessions** | **~2-2.5 days** | **60% parallelizable** |

**With 1 person:** 2.5-3 days sequential
**With 2 people:** 1.5-2 days (split phases in parallel)
**With 4 people:** 1 day (run all 4 career batches in parallel during Phase 2)

---

## Files to Modify

`
career_tweaker/
├── scripts/mods/career_tweaker/
│   ├── career_tweaker_big_rebalance.lua  <- PRIMARY (fill 27 stubs, lines 499-2655)
│   └── (no changes to data.lua; toggles already registered)
└── CHANGELOG.md                           <- SECONDARY (document fills + defer decisions)
`

No other files need modification unless new load-time hooks are added (Phase 1).

---

## Final Notes

**Status:** Research complete, execution blocked on source files.

**Recommendation:** Before writing ANY code, recover the Big Rebalance source files (\_big_rebalance_extract/source/*_changes.lua\). Without them, we cannot verify correctness of the stub fills and risk shipping silent divergences from the original balance design.

Once source files are available, Phase 1 (framework hooks) can begin immediately (~2-3 hours). Phases 2-3 can run in parallel while Phase 4 waits on bt infrastructure.

**Post-completion:** Plan a full co-load smoke test with wt + ct + et + bt all enabled, toggling the full BR stack to verify no NetworkLookup divergence, no hook collisions, and no silent feature gaps.

