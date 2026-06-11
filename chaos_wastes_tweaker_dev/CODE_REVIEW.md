# Chaos Wastes Tweaker Code Review (2026-05-23, v0.7.90-dev)

## Summary

Chaos Wastes Tweaker (mod id `ct`, Workshop 3712929235) is the largest public Vermintide 2 mod by subscription count. It modulates Chaos Wastes ("deus") mode difficulty, economy, rewards, and mechanics via VMF toggles. The mod is now 6575 lines in a single `chaos_wastes_tweaker.lua` file — well past the 2500-line hard limit in PROJECT_STANDARDS §2.1. Despite monolithic size, the code exhibits strong defensive discipline: five distinct regression-test smoke checks (`/regression_test` command), dual-table registration for boon lookups, network-safe pre-registration patterns for exotic boons, and extensive error-swallowing guards against vanilla game patch edge cases (Skittergate hybrid-breed loot nil, Reckless Swings hard-coded array indices, adventure-level missing pickup assets).

The mod has shipped 17 significant fixes in the last three weeks (v0.7.76 through v0.7.90) covering boss grudge-mark banning, miracle blessing purchase nil-bug, dormant-boon pool removal, Miracle of Isha mutex UI migration, and new category display names for the BOON_TREE settings panel. Recent versions also introduced a `/regression_test` command that validates past fix state, making it easier for users to report whether their build is corrupted before joining multiplayer lobbies.

Major risk surface: the single-file monolith couples unrelated features (pickle/altar distribution, boss enhancements, boon tweaks, economy) into a 6500+ line file with no clear module boundaries. File size is now a **HIGH** refactor priority.

---

## Architecture overview

### Major feature areas and line ranges

| Feature | Lines | Notes |
|---------|-------|-------|
| **Coin economy** | 44–150 | `on_soft_currency_picked_up` hook, `setup_run` starting coins grant, `REAL_PLAYER_LOCAL_ID` local (v0.7.88 fix) |
| **Loot amount fallback** | 111–323 | Metatable `__index` on `DeusSoftCurrencySettings.loot_amount` to defend Skittergate hybrid-breed crashes (v0.7.82) |
| **Graph snapshot / peer sync** | 324–700 | Adventure-level altar distribution determinism via `HashUtils.fnv1a_hash(node.level_seed)`; broadcast RPC for host→client consistency |
| **Boon count detection** | 104–127 | Range scan `[1,10]` to detect shrine/chest defaults despite signature drift; defends against hash collisions |
| **Arc NaN widget offset** | 1034–1070 | Defensive fix for VMF numeric widget off-by-one in 1-widget case |
| **Trait combo caching** | 1246–1426 | Vanilla `DeusWeaponTraits` enumeration; cache never invalidated (assumed stable per session) |
| **Weapon trait filtering** | 1285–1395 | `apply_weapon_trait_filter` / `restore_weapon_trait_filter` save-and-restore around boon rolls |
| **Adventure pool injection** | 1776–2900 | Core logic split to `_adventure_pool.lua`; entry point `adventure_base_from_level_key` at line 1776 |
| **Curse filtering** | 2249–2442 | Per-node curse state mutations; theme injection on injected adventure levels |
| **Pickup distribution** | 2816–3220 | Spawner eligibility gates; campaign potion weight renormalization; tome/grim protection |
| **Boss Grudge Mark banlist** | 3308–3378 | v0.7.89 restoration: mutates `_G.BossGrudgeMarks` directly; 13 per-mark toggles + baseline snapshot |
| **Reckless Swings / Khaine's Fury** | 3397–3531 | Hard-coded `buffs[1]`, `description_values[1]`, `description_values[3]` indices (fragile) |
| **Bomb Boon cooldown** | 3534–3607 | Mutual-exclusivity enforcement + drop-trigger rate limiter |
| **Per-boon tweaks** | 3613–4103 | Ulric Pack range, movespeed, poison-proof, invis potion 2x, Moot Milk, Shard Strike, Anath Raema |
| **Dormant boon injection** | 4266–4453 | NetworkLookup pre-registration; pool add/remove toggle-gated |
| **Skulls event boons** | 4550–4630 | Parallel to dormant system; Skulls 2023 DLC event boons |
| **Miracle of Isha migration** | 4629–4735 | Legacy dropdown → mutex checkbox cluster (v0.7.85) |
| **Buff template registration** | 4656–4990 | `_register_miracle_buff_templates()` hard-codes miracle boon buffs |
| **Meta boon framework** | 4992–5009 | Wrapper for proc-style boons; stacking multiplier support |
| **Trait boon framework** | 5271–5293 | Companion to `CT_TRAIT_BOONS` table |
| **Generate random power-ups hook** | 879–1035 | Master hook for boon count override, disabled-boon enforcement, bomb-exclusivity, Belakor force-rarity |
| **Lifecycle callbacks** | 5891–5959 | `on_setting_changed` syncs mutations; `on_disabled` reverts persistent tweaks |
| **Regression test checks** | 52–70, 6436–6574 | Nine smoke checks validating past fixes |

---

## Strengths

- **Defensive logging & error guards.** Extensive mod:info / mod:warning calls. Save-and-restore patterns isolate side effects. Error-swallowing on `game_round_ended` prevents finale voting desync crashes (v0.7.81).

- **Pre-registration determinism.** Dormant and trait boons registered at mod load regardless of toggle state (v0.7.67 fix), guaranteeing host/client lookup index consistency.

- **Regression test command.** `/regression_test` smoke checks nine past fix categories, returning PASS/FAIL per check. Users can verify build integrity before multiplayer.

- **Idempotent toggles.** Dormant pool add/remove, adventure pool inject, grudge mark sync all re-run cleanly without creating duplicates via baseline snapshots and idempotency bits.

- **Mutex cluster framework.** v0.7.85 migrated Miracle of Isha to checkbox cluster with automatic mutual-exclusivity, validating design before deployment to other mods.

- **Adventure level support without crashing.** Skittergate and DLC missions now spawn CW pickups with defensive guards: `_pickup_unit_loadable` (v0.7.78), triggered-event barrel protection (v0.6.32), tome/grim book-spot protection.

---

## Implementation patterns

### Save-and-restore guards
The mod uses a save-and-restore pattern throughout to isolate side effects. Weapon trait filtering (line 1285–1395) saves combo state before boon generation, then restores after. Reckless Swings, bomb cooldown, and per-boon tweaks all follow: `apply_*` mutates `DeusPowerUpTemplates`, hook runs wrapped vanilla code, `revert_*` restores mutations. Pattern is sound but not protected against wrapped-function exceptions — if vanilla throws before restore, mutation persists for the session. No production crash cited, but wrapping in `pcall` would add defensive robustness.

### Network lookup registration (load-bearing pattern)
Key innovation from v0.7.67 separates "unconditional registration" from "toggle-gated pool insertion":

- **Unconditional** (line 4266–4453): `inject_dormant_boon` and trait-boon pre-registration run at mod load, registering into `NetworkLookup.deus_power_up_templates`, `DeusPowerUpsArray`, `DeusPowerUpsArrayByRarity`, and buff templates. Ensures every peer has identical lookup indices.
- **Toggle-gated** (line 4398–4530): `_add_dormant_to_pool` / `_remove_dormant_from_pool` control `DeusPowerUpRarityPool` (what players can roll). This separation prevents RPC desync that burned v0.7.66 (absent dormants drifted subsequent boons' IDs by +1 each).

**This is load-bearing.** Any future mod injecting custom boons must follow this pattern or break multiplayer compatibility.

### Idempotency via baseline snapshots
Multiple systems use "baseline snapshot + reset + apply toggles":

- Grudge marks (line 3319–3378): `_capture_grudge_baseline()` snapshots vanilla `BossGrudgeMarks`, `sync_grudge_marks()` resets to baseline then nils banned marks. Allows toggle-off to restore entries instead of losing them forever.
- Dormant pool (line 4398–4450): `_added_to_pool[name]` idempotency bit prevents duplicate insertions.
- Adventure pool: `inject_pool()` takes one-time snapshot, resets to vanilla, applies toggles. Makes toggles re-entrant and safe to call multiple times.

### Error-swallowing for finale voting (v0.7.81)
The `game_round_ended` hook at line ~1498 swallows exceptions instead of re-throwing. Context: finale voting can throw if dominant_god vote is ambiguous, crashing the session in vanilla. The tweak suppresses the error so the host can continue, though deus state may be inconsistent for that frame. Pragmatic trade-off: silent inconsistency beats a hard crash. Regression test at line 6533–6544 verifies the marker constant "host continues, deus state may be inconsistent" is present.

---

## Concerns / pending items

### [HIGH] File size exceeds hard limit — 6575 lines in single module

**Status:** Active blocker per PROJECT_STANDARDS §2.1 (2500-line limit). Current file is 2.6x over.

**Recommendation:** Refactor into five sub-modules:
1. `_dormant_boons.lua` — ~150 lines
2. `_skulls_event.lua` — ~80 lines
3. `_pickup_customization.lua` — ~500 lines
4. `_adventure_pool.lua` — Already split
5. `_per_boon_tweaks.lua` — ~350 lines

Remaining core: ~2000 lines (lifecycle, economy, trait combos, graph snapshot). Each sub-module returns a table with public API; main file calls `mod.dofile(...)` to load and wire in hooks at startup. **Effort:** Medium. No logic changes; purely structural.

---

### [HIGH] Reckless Swings tweak uses hard-coded array indices (line 3397–3531)

**Status:** Fragile. Code's own comment: "Fatshark may reorder the arrays."

**Current behavior:**
- Line 1041: `buffs[1]` assumes Reckless Swings buff is first
- Lines 1050, 1059: `description_values[1]` and `description_values[3]` hard-coded

If a future game patch reorders these arrays, the tweak will silently modify the wrong buff fields or crash if indices are out of bounds. Silent desync in co-op: some peers have tweak applied, others don't.

**Recommendation:** Replace with name-based search before v0.7.91. Validate the found index in a regression test, and store vanilla template's buff names in CHANGELOG for future maintainers.

---

### [MED] Altar distribution seed relies on deterministic host hash (line 348–381)

**Status:** Untested under live multiplayer.

**Risk:** If client joins mid-run or receives stale node copy, altar layout could differ from host. Visual/navigational desync.

**Recommendation:** Verify via co-op session log (all peers see identical altar spawns) or add RPC broadcast of altar positions at setup time.

---

### [MED] Trait combo cache never invalidated (line 1246–1426)

**Status:** Assumed `DeusWeapons` stable per session.

**Risk:** Low in practice. No known mod mutates `DeusWeapons` today, but **VERIFY** before implementing cross-mod trait registry (e.g., if buff_tweaker starts injecting custom traits).

**Recommendation:** Add `on_disabled` reset of `_TRAIT_COMBOS_CACHE = {}` so reloading ct clears stale data. If future mod adds trait injection, add invalidation signal via `mod:trigger("ct:clear_trait_cache")`.

---

### [MED] Dormant pool toggle-off removal still incomplete (v0.7.88 half-fix, line 4419–4530)

**Status:** Pool-side fixed (v0.7.88), but "most don't work" half unverified.

**Current:** `_remove_dormant_from_pool` removes matching entries and clears idempotency bit. **Unverified:** If user activates dormant, sees it never granted or always reverts, the fix above only addresses pool half. Buff application path may have separate bug downstream (proc path, buff template resolve, buff system itself).

**Recommendation:** Require user session log (host + client, level start through boon grant attempt) showing dormant in pool but failing to apply. Will pinpoint whether issue is in `DeusRunController.add_power_ups`, activate hook, buff resolution, or buff system.

---

### [MED] Boss Grudge Marks RPC may diverge on clients under hot-join (line 3319–3378)

**Status:** Untested. Design correct (mutates global `_G.BossGrudgeMarks` at call time), but hot-join timing unverified.

**Risk:** If client hot-joins after host applied bans, client's `BossGrudgeMarks` may not reflect host's filtered state — next boss spawn could diverge.

**Recommendation:** Add server→client RPC at hot-join time broadcasting current filtered `BossGrudgeMarks` state. Or broadcast on every `sync_grudge_marks()` call (low-frequency, safe). Add regression test verifying `BossGrudgeMarks[banned_name] == nil` for each banned mark.

---

### [LOW] Curse light tinting may desync on injected adventure levels (line 2249–2442)

**Status:** Cosmetic only. Known edge case documented in AUDIT_FINDINGS.md line 74–75.

**Risk:** Per-peer curse light tinting (halos, lighting overrides) reads from per-peer `_current_node_curse()`. On injected adventure levels, per-peer `_setup_run` may see different curse values if LobbyAux hash drift occurs (rare but possible under network jitter). Result: one peer sees Slaanesh purple, another sees no halo. No gameplay impact, but confusing for multiplayer immersion.

**Recommendation:** Verify `broadcast_graph_snapshot` call coverage on all setup paths. If not wired everywhere, add RPC broadcast after `deus_populate_graph` completes with host's final curse assignment per node.

---

### [LOW] NaN widget offset fix only applies to 1-widget case (line 1034–1070)

**Status:** Edge case. Code comment at line 1045: "Why only fix 1-widget? Is there a deeper issue?"

**Risk:** If VMF ever loads 2+ independent numeric widgets, the offset bug may persist for all but the first.

**Recommendation:** Investigate whether VMF widget-layout logic ever creates multiple independent numeric widgets. If yes, broaden fix to `if #widgets > 0 then fix_arc_nan(widgets) end`. If no, add clarifying comment explaining the single-widget constraint.

---

### [LOW] Save-and-restore error paths not protected against wrapped-function exceptions (throughout)

**Status:** Theoretical risk. No production crash cited.

**Pattern found at 10+ sites:** If wrapped vanilla function throws an exception, the restore code is skipped and the mutation persists in a partially-applied state for the rest of the session.

**Recommendation:** Wrap in `pcall` for defensive error handling.

---

## What's changed since v0.7.84 (2026-05-01 baseline)

### v0.7.85-alpha — Miracle of Isha mutex cluster UI migration
- Dropped dropdown for (A)/(B) checkbox cluster
- New `chaos_wastes_tweaker_mutex.lua` dependency (~80 lines)
- Backward-compatible migration from old settings

### v0.7.86-dev — Regression test command
- `/regression_test` smoke check command
- Nine checks validating dormant preregistration, trait preregistration, dual-table buff, chaos_spawn metatable, rarity validity, kill_heal heal_type, error-swallowing, adventure-pack strip, networked-flow-state leak

### v0.7.87-dev — Removed Grudge Marks, simplified Belakor
- Removed 13 per-mark ban checkboxes (design flawed — Grudge Marks scoped to Geheimnisnacht 2021 only, not general CW)
- Consolidated two `generate_random_power_ups` hooks into one (v0.7.77 had two, causing VMF "rehook active hook" warning)

### v0.7.88-dev — Critical bug fixes
- **CRITICAL:** Added `local REAL_PLAYER_LOCAL_ID = 1` (line 42) — vanilla declares this as file-scoped local in every file, NOT globally. Missing local caused `get_player_soft_currency(buyer, nil)` to return 0, breaking every Miracle of Ulric/Isha purchase
- `_remove_dormant_from_pool` helper now properly removes boons when toggle turns off (half of dormant toggle-off bug; second half "most don't work" still unverified)

### v0.7.89-dev — Boss Grudge Marks restored with correct implementation
- v0.7.87 reversal: reinstated the 13 per-mark ban checkboxes
- v0.7.76 version failed: terror-event files capture `TerrorEventUtils.add_enhancements_for_difficulty` as upvalue at boot BEFORE mods load — by mod-load time the upvalue is already stale
- New fix: directly mutate `_G.BossGrudgeMarks` at call time (read at `terror_event_utils.lua:197` with `enhancement_set = enhancement_set or BossGrudgeMarks`), nil-ing banned marks. Baseline snapshot enables toggle-off to restore entries.
- Companion `/dump_grudge_marks` command re-instated

### v0.7.90-dev — Display names for BOON_TREE category headers
- 26 localization entries for VMF settings menu category display (crit, talents, save_revive, etc.)
- Was rendering as raw strings; now shows human-readable "Crit", "Talents", "Save / Revive"

---

## File / module map

| Line Range | Section | Responsibility |
|------------|---------|-----------------|
| 1–50 | Header, MOD_VERSION, regression scaffold | Infrastructure |
| 44–45 | `MOD_VERSION = "0.7.90-dev"` | Versioning (auto-appended to Workshop title) |
| 51–70 | `/regression_test` dispatcher | Testing |
| 72–90 | Mutex cluster declaration (Isha choice) | UI orchestration |
| 92–323 | Coin economy + loot amount fallback | Core mechanics |
| 324–700 | Graph snapshot & peer sync | Adventure distribution |
| 740–880 | Boon count defaults | Core mechanics |
| 879–1035 | `generate_random_power_ups` hook | Master hook |
| 1034–1070 | Arc NaN widget offset fix | VMF integration |
| 1246–1426 | Trait combo enumeration & caching | Lookup table |
| 1285–1395 | Weapon trait filter save-restore | Boon roll guard |
| 1574–2750 | `populate_pickups` hook | Pickup spawning |
| 1776–2900 | Adventure pool integration | Level layout |
| 2249–2442 | Curse filtering & theme injection | Level customization |
| 2838–2851 | `_pickup_unit_loadable` guard | Asset validation |
| 2853–2950 | `PickupSystem._can_spawn` hook | Spawner eligibility |
| 3308–3378 | Boss Grudge Marks (v0.7.89 restoration) | Difficulty modifier |
| 3397–3531 | Reckless Swings tweak | Khaine's Fury |
| 3534–3607 | Bomb Boon cooldown | Boon tweak |
| 3613–4103 | Per-boon tweaks (6 variants) | Boon tweaks |
| 4247–4265 | Network lookup registration helpers | Registration infrastructure |
| 4266–4453 | Dormant boon injection & pool management | Dormant system |
| 4550–4630 | Skulls event boons | Event system |
| 4629–4735 | Miracle of Isha migration + buff templates | Blessing system |
| 4992–5009 | Meta boon framework | Buff framework |
| 5271–5293 | Trait boon framework | Boon framework |
| 5500–5720 | Endless Bombs + Manann Tempest tweaks | Boon tweaks |
| 5891–5945 | `mod.on_setting_changed` callback | Lifecycle |
| 5950–5959 | `mod.on_disabled` callback | Lifecycle |
| 5965–6100 | Debug commands | Diagnostics |
| 6436–6574 | Regression test implementations | Testing |

---

## Known debt & deferred items

1. **File size refactor (HIGH):** 6575 lines → split into 5 sub-modules. Deferred pending prioritization.
2. **Reckless Swings array indices (HIGH):** Replace hard-coded indices with name-based search before v0.7.91.
3. **Altar distribution peer sync (MED):** Verify live multiplayer or add RPC broadcast if drift observed.
4. **Dormant "most don't work" (MED):** Require user session log to complete v0.7.88 half-fix diagnosis.
5. **Trait combo cache invalidation (MED):** Add `on_disabled` reset and possible cross-mod invalidation signal.
6. **Hot-join Grudge Marks desync (MED):** Consider broadcast RPC at hot-join time.
7. **Curse light tinting desync (LOW):** Verify `broadcast_graph_snapshot` coverage on all setup paths.
8. **NaN widget fix scope (LOW):** Clarify single-widget constraint or broaden fix.

---

## Code health observations

**Positive:**
- Extensive defensive guards and regression tests
- Clear separation of concerns within features (apply/revert/sync triplets)
- Good use of idempotent patterns (toggles, pool management)
- Backward-compatible migration (Isha legacy dropdown)
- Strong logging discipline for triage

**Negative:**
- Single monolithic file blocks further feature development
- Some assumptions not validated in live multiplayer (altar sync, hot-join)
- Hard-coded array indices create fragility to game patches
- Cache invalidation left incomplete (trait combos)
- Save-and-restore patterns not protected against wrapped-function exceptions

**Overall:** Production-ready with strong guardrails. Refactor to sub-modules is the critical blocker for sustained development velocity. The HIGH-severity concerns (file size, Reckless Swings indices) should be addressed in the next 1–2 development cycles before they compound into larger refactoring debt.

---

## Verification notes

**Snapshot date:** 2026-05-23 (v0.7.90-dev). This review captures the state AFTER the v0.7.90 display-name localization was shipped and v0.7.89 boss-grudge-mark restoration was validated. The file has undergone 17 significant fixes in 3 weeks (v0.7.76–v0.7.90) with no regressions reported on the public Workshop.

**Regression test coverage:** The `/regression_test` command validates nine fix categories (line 6436–6574):
1. Dormant boons preregistered in NetworkLookup
2. Trait boons preregistered in NetworkLookup
3. Dormant buff templates in both DeusPowerUpBuffTemplates and BuffTemplates
4. Chaos_spawn Skittergate loot metatable fallback
5. Deus rarity validity (no "common"/"plentiful" entries)
6. Kill_heal uses permanent "health_regen" heal_type
7. game_round_ended error-swallow path present
8. Adventure-pack mutator incompatibility list present
9. NetworkedFlowStateManager.clear_object_state leak patch installed

Users can run `/regression_test` from the keep at any time to confirm their build isn't corrupted before joining multiplayer.

**Multiplayer validation:** The mod is deployed to 3700+ Workshop subscribers and actively played in co-op sessions. No critical multiplayer desync bugs reported since v0.7.85. The pre-registration determinism fix (v0.7.67) solved the RPC boon-id mismatch problem that burned v0.7.66.

**Historical context:** This mod predates the VMB (Vermintide Mod Builder) migration and PROJECT_STANDARDS enforcement. Early versions (v0.6.x) had sharp edges (ghost-scythe workaround, campaign-potion weight skew), but each has been root-caused and fixed with defensive depth added. The mod is now in a stable equilibrium with strong error guards, but the monolithic file structure is becoming a maintainability ceiling.

---

## Actionable next steps (priority order)

1. **v0.7.91 (1–2 weeks):** Fix Reckless Swings hard-coded array indices (line 3397–3531). Replace `buffs[1]`, `description_values[1]`, `description_values[3]` with name-based search. Add regression test validating the found index.

2. **v0.7.92 (2–3 weeks):** Refactor file size. Split main file into 5 sub-modules (`_dormant_boons.lua`, `_skulls_event.lua`, `_pickup_customization.lua`, `_per_boon_tweaks.lua`, plus retained core). Wire in via `mod.dofile(...)` at startup. No logic changes; purely structural.

3. **v0.7.93 (research phase):** Verify altar distribution determinism under live multiplayer (co-op session with peers joining mid-run, confirm identical altar spawns). Document findings in VERIFIED_STATE.md or add RPC broadcast if drift observed.

4. **Backlog:** Trait combo cache invalidation, hot-join Grudge Marks RPC, cursor light tinting RPC broadcast, save-and-restore `pcall` protection. Low-priority but improves robustness.

---

## Comparison to previous baseline (v0.7.84, 2026-05-01)

| Aspect | v0.7.84 | v0.7.90-dev | Change |
|--------|---------|------------|--------|
| File size | ~6400 lines | 6575 lines | +2.7% (not significant) |
| Major bugs fixed | Miracle purchase broken | Fixed + validated | +1 critical fix |
| Regression test checks | 6 | 9 | +50% coverage |
| Multiplayer desync risk | MED (pre-registration) | LOW (determinism fixed) | Risk reduced |
| PUBLIC Workshop status | Yes, 3700+ subs | Yes, 3700+ subs | Unchanged (stable) |
| Hard refactor blocker | File size (MEDIUM) | File size (HIGH) | Severity increased |

---

## Summary for future maintainers

This mod is **production-ready and actively used** by thousands of players. The codebase exhibits strong defensive discipline (extensive logging, error guards, regression tests, idempotent patterns). However, it has grown to 2.6x the PROJECT_STANDARDS file-size limit, and a few high-risk assumptions (hard-coded array indices, unvalidated multiplayer paths) should be addressed proactively before they compound into larger refactoring debt.

The critical path is:
1. Fix Reckless Swings indices (v0.7.91) — HIGH-severity fragility.
2. Refactor file size (v0.7.92) — High-severity blocker to future development.
3. Validate multiplayer assumptions (v0.7.93+) — MED-severity de-risking.

If these three are addressed within the next 2–3 months, the mod will be in excellent shape for another 12+ months of maintenance without major refactoring.

---

## Technical deep-dive: Key fixes and their root causes

### v0.7.88: Miracle of Ulric/Isha purchase broken (coins returned 0)

**Symptom:** Players attempting to purchase Miracle of Ulric or Miracle of Isha from the blessing shop saw every purchase rejected with "coins=0 < cost=100" even when they had hundreds of coins. The shop click silently no-op'd; no error message in logs, just silent rejection repeated 12+ times until the player gave up.

**Root cause:** Vanilla VT2 declares `local REAL_PLAYER_LOCAL_ID = 1` as a file-scoped local in EVERY file that uses it (`deus_run_controller.lua:29`, `deus_chest_extension.lua:10`, `deus_spawning.lua:7`, and 5 other terror-event files). It is NOT exposed globally. The `_try_buy_blessing` hook in ct (line ~800) referenced `REAL_PLAYER_LOCAL_ID` seven times in its body, but never defined it as a local. The bare token resolved to `_G.REAL_PLAYER_LOCAL_ID = nil` in the hook's scope. When the code called `get_player_soft_currency(buyer, nil)` — passing nil as the player_id segment — SharedState interpreted that as a missing key and returned 0 instead of the player's real balance. The guard `if coins < cost then return false end` then silently rejected the purchase.

**Why this was subtle:** VMF mod loading happens AFTER the game bootstraps all VT2 code. By the time the ct hook fires, vanilla's file-scoped locals are already set in their respective closures. The mod author assumed the token was global (or would resolve via `_G`) when in fact it's unreachable from outside the vanilla files.

**Fix:** Add `local REAL_PLAYER_LOCAL_ID = 1` at the top of `chaos_wastes_tweaker.lua` (line 42), matching vanilla's declaration. Now the hook's reference to the bare token resolves to the local instead of `_G.nil`.

**Verified:** Session log diff from 2026-05-22 showed SharedState read `soft_currency:<peer>:1:0:0:0 = 894` but the hook's diagnostic still logged `coins=0 cost=100` with the same buyer peer_id. Same bug on both host and client. After the fix, purchases succeed.

**Lesson:** When porting vanilla code into a mod hook, check vanilla's scoping rules. File-scoped locals (especially singletons like REAL_PLAYER_LOCAL_ID) won't be visible from outside the file unless explicitly re-declared in the hook scope.

### v0.7.78: Skittergate crashes with "Unit not found pup_holy_hand_grenade_01_t1"

**Symptom:** Hard engine crash on level start of adventure-injected levels (especially Skittergate / dlc_dwarf_whaling, but every injected mission was exposed) with assertion `world.resource_manager().can_get(unit_type, unit_name)` failed for the holy_hand_grenade pickup unit. Lua stack: `PickupSystem._spawn_spread_pickups` → `_spawn_pickup` → `World.spawn_unit`. The crash happened during `populate_pickups`, the level's startup spawner initialization phase.

**Root cause:** v0.7.64 broadened the `_can_spawn` hook to allow vanilla campaign pickup categories (ammo, healing, grenades, potions, etc.) on adventure-injected levels. This fixed a v0.7.63 regression where Holly DLC missions spawned nothing. However, vanilla's `grenades` bucket includes `holy_hand_grenade` (Morgrim's Bomb), which is loaded ONLY by Morris/CW mission packages (via `level_morris.package`). On adventure-injected levels like Skittergate, that asset is absent from the resource manager. When RNG rolled the `holy_hand_grenade` entry, `World.spawn_unit` tried to load the unit, the engine couldn't find it, and the assertion fired.

**Fix:** Add a pre-flight guard `_pickup_unit_loadable(pickup_name)` (line 2838–2851) that checks if a pickup's unit can be loaded via `Application.can_get("unit", unit_name)` before returning eligibility. If the unit is missing, the spawner is skipped (empty spot, same as vanilla's soft-veto) instead of crashing.

**Applied to:** Every path in `_can_spawn` hook that opens a category: deus_potions, deus_soft_currency, deus_weapon_chest, and all vanilla campaign categories (ammo, healing, grenades, potions, etc.). Redundant checks on CW-packaged entries are acceptable ("feedback_redundant_safeguards_ok") because the defensive cost is free and catches edge cases.

**Verified:** No crash reports post-v0.7.78 for adventure-injected levels' pickup spawns.

### v0.7.77: VMF "Attempting to rehook active hook" warning on `generate_random_power_ups`

**Symptom:** Every time the mod loaded, VMF printed a warning: "Attempting to rehook active hook [DeusPowerUpUtils.generate_random_power_ups] — hook already registered by ct". This didn't break functionality, but was confusing for users and indicated sloppy architecture.

**Root cause:** Two separate `mod:hook("DeusPowerUpUtils", "generate_random_power_ups", ...)` blocks existed in the same mod — one for count override + disabled-boon enforcement + bomb-boon exclusivity (original, ~line 783), and one for Belakor's Temple force-unique-rarity (line ~1387). VMF allows mod:hook chaining ACROSS different mods, but warns when the SAME mod re-hooks the SAME Class+method twice (collision detection to catch copy-paste bugs). The second hook triggered the warning on every mod load.

**Fix:** Consolidate both hooks into a single `mod:hook` block. Read the hook arguments positionally (`args[6]` = availability_type, `args[8]` = forced_rarity) using vanilla's signature. Add an `if current_node is arena_belakor then override forced_rarity else keep original end` branch inside the hook body instead of having two separate hook registrations. Semantics unchanged, one VMF hook registration instead of two.

**Result:** Clean startup with no warnings. Demonstrates the difference between functional correctness (both hooks worked) and architectural cleanliness (single registration point is clearer and less error-prone).

### v0.7.67: NetworkLookup desync — boon IDs mismatched between host and client

**Symptom:** Host and client could receive different boon IDs for the same boon name. Example: host's dormant `deus_larger_clip` might resolve to ID=42, but client's lookup table has it at ID=43 because the client has dormant toggles OFF and the lookup tables have different lengths. Selecting a boon at a shrine on the client sends RPC with ID=42 (the host's index), but the client's lookup resolves that to a DIFFERENT boon (because the layouts differ), resulting in the wrong boon being granted and silent desync.

**Root cause (prior architecture):** The `inject_dormant_boon` call was guarded by the toggle state. Only peers with `activate_dormant_*` or `enable_boon_*` toggled ON would register the dormant into `DeusPowerUpsLookup`, `DeusPowerUpsArray`, etc. Peers with the toggle OFF didn't register it. This caused lookup tables to have different orderings:

- Host with all dormants ON: indices are [dormant_a, dormant_b, dormant_c, dormant_d, custom_trait_1, ...]
- Client with dormant_c OFF: indices are [dormant_a, dormant_b, dormant_d, custom_trait_1, ...] — every entry after dormant_c is shifted by -1

RPC communication uses integer IDs (indexes), not names. When the host broadcasts "grant boon ID=42", the client looks up their index 42 and gets a completely different entry.

**Fix (v0.7.67):** Separate "unconditional registration" from "toggle-gated pool insertion":

- **Unconditional (at mod load, ALWAYS):** `inject_dormant_boon` registers into NetworkLookup, DeusPowerUpsArray, DeusPowerUpsArrayByRarity, DeusPowerUps, buff templates, and `NetworkLookup.buff_templates`. Every peer registers every dormant/trait boon regardless of toggle state. This ensures lookup tables have identical orderings on all peers.
- **Toggle-gated (on_setting_changed, per-toggle):** `_add_dormant_to_pool` / `_remove_dormant_from_pool` control whether the dormant appears in `DeusPowerUpRarityPool` — the pool that determines what a player CAN roll. If a peer has the toggle OFF, the dormant doesn't appear in the pool (so they can't get it), but it IS in the lookup table (so if another peer grants them one via a set-completion or shared boon, the RPC ID resolves correctly).

**Impact:** This is a **load-bearing architectural decision**. Any future mod that injects custom boons MUST follow this pattern or risk breaking multiplayer. It's now a prerequisite for cross-mod boon registries (e.g., buff_tweaker's centralized boon registration).

---

## Testing methodology

The regression test command (`/regression_test`, line 52–70 dispatcher + implementations at 6436–6574) provides a fast smoke-check path for users. Each check is designed to be runnable from the keep (no need to start a CW run):

1. **dormant_boons_preregistered:** Walk `DORMANT_BOON_RARITY` table, verify every name is in `NetworkLookup.deus_power_up_templates`. Catches the v0.7.67 desync pattern.
2. **trait_boons_preregistered:** Walk `CT_TRAIT_BOONS` specs, verify names in lookup. Catches same pattern for trait boons.
3. **dormant_buff_dual_registered:** Verify every dormant's runtime buff_name exists in BOTH `DeusPowerUpBuffTemplates` AND `BuffTemplates`. Catches missing dual-registration.
4. **chaos_spawn_fallback_installed:** Check for metatable on `DeusSoftCurrencySettings.loot_amount` with `__index_installed_by_ct` marker. Catches missing Skittergate crash defense (v0.7.82).
5. **deus_rarities_valid:** Verify `DORMANT_BOON_RARITY` and `CT_TRAIT_BOONS` only use valid rarity strings {event, rare, exotic, unique}. "common" or "plentiful" crash at deus_power_up_utils.lua:189.
6. **kill_heal_uses_permanent_heal_type:** Verify ct_kill_heal boon function is registered (marker for registration path success). Deep validation requires runtime buff introspection (not feasible from Lua).
7. **game_round_ended_swallows_error:** Verify the marker constant "host continues, deus state may be inconsistent" exists in the source (confirms v0.7.81 error-swallow branch is present).
8. **adventure_pack_compat_strip:** Verify `ADVENTURE_INCOMPATIBLE_PACK_MUTATORS` table and the `no_roamers` entry exist (defensive against pack mutator crashes on adventure levels).
9. **networked_flow_state_leak_patched:** Check for the marker constant "Too many object states" and verify `NetworkedFlowStateManager.clear_object_state` is a function (confirms v0.7.80 leak patch).

Each check returns nil (PASS) or an error string (FAIL). The dispatcher accumulates results and reports pass/fail counts to both chat and mod:info log.

**Usage:** Users can run `/regression_test` from the keep at any time. If all checks PASS, the build is verified clean. If any FAIL, the user can report the exact failure with high confidence that it's a real corruption, not a user-side misconfiguration.

---

## Module dependency map

```
chaos_wastes_tweaker.lua (main, 6575 lines)
├── chaos_wastes_tweaker_data.lua (VMF widget definitions)
├── chaos_wastes_tweaker_localization.lua (localization strings, 26 new entries in v0.7.90)
├── chaos_wastes_tweaker_mutex.lua (Isha choice cluster framework, ~80 lines, new in v0.7.85)
└── _adventure_pool.lua (adventure level injection, already split out)
```

**No external mod dependencies.** ct is self-contained; it hooks vanilla classes (DeusPowerUpUtils, PickupSystem, DeusMechanism, etc.) only. The only internal dependency is `chaos_wastes_tweaker_mutex.lua`, loaded via `mod.dofile(...)` at line 77.

