# Chaos Wastes Tweaker — Audit Findings

**Audit date:** 2026-05-13
**Audited version:** v0.6.4-dev (lua) / v0.4.1-dev (CHANGELOG top)
**Method:** AI-assisted, ground-truth verified against `Vermintide-2-Source-Code` decompiled source, cross-mod CHANGELOG files, and memory entries.

This doc catalogues unverified claims and assumption-class content in ct's docs and source comments. It is the companion to `VERIFIED_STATE.md`. New findings land in **History** at the bottom.

---

## Verified clean

- **v0.6.5-0.6.6 ghost-scythe workaround** — REMOVED.
  - Bad code: hard-coded list of weapon unit packages, added in v0.6.5 to mask `Unit not found wpn_bw_ghost_scythe_01_3p` crash for bots equipped with DLC-career weapons.
  - Real fix: `chaos_wastes_tweaker.lua` `GearUtils.create_equipment` hook (career_name recovery + pre-resolved `override_item_units`), cross-ported from `weapon_tweaker/CHANGELOG.md` v0.12.23–v0.12.25.
  - Removal documented in-source: `_adventure_pool.lua:342-346`.
  - Lesson captured: `feedback_search_changelog_for_known_crashes.md` (memory).

---

## Open assumptions

Severity:
- **HIGH** — load-bearing AND likely to break on future game patches or known adverse conditions
- **MED** — load-bearing but stable under normal conditions; verify on adverse paths
- **LOW** — defensive / theoretical / cosmetic

### Code-level assumptions (in `scripts/mods/chaos_wastes_tweaker/chaos_wastes_tweaker.lua`)

| # | Location | Claim | Severity | Notes |
|---|----------|-------|----------|-------|
| 1 | 1027-1070 | Reckless Swings uses hard-coded `buffs[1]`, `description_values[1]`, `description_values[3]` | HIGH | Code's own comment acknowledges fragility if FatShark reorders arrays. Fix path: name-based search instead of literal indices. |
| 2 | 343-381 | Altar-distribution seed deterministic host↔clients via `HashUtils.fnv32_hash(node.level_seed)` | MED | Plausible. Untested under live multiplayer. Risk: clients see different altar layouts. |
| 3 | 104-127 | Boon-count detection by value-range scan `[1,10]` rather than fixed `args[2]` | MED | Defends against signature drift, but assumes 32-bit hash seeds never collide with [1,10]. Works in practice. |
| 4 | 854-858 | `CURSED_CHEST_STATE_OPEN = 3` fires only server-side; hot-join clients use state 4 | LOW | Untested under hot-join. |
| 5 | 388-414 | Trait-combo cache never invalidated after first call | LOW | Acknowledged fragility if `DeusWeapons` mutates; no known mutator alters it today. |
| 6 | 219-241 | NaN widget offset fix only needed for 1-widget case | LOW | Edge case. Code comment open question: "Why only fix 1-widget?" |
| 7 | 95-102 | `on_soft_currency_picked_up(starting, nil)` — `nil` 2nd arg means "server-only branch skips counters" | LOW | Untested branch behavior. Starting coins work in practice. |
| 8 | 899-924 | Revive logic skips units with `is_disabled_by_pact_sworn` to avoid in-progress-disabler desync | LOW | Behavioral assumption; no reproduction case. |
| 9 | various (5 sites) | Save-and-restore error paths — if wrapped fn errors, restore never runs (CODE_REVIEW.md §4) | LOW | Pure theory. No production crash cited. |

### Comment / docstring assumptions

| # | Location | Claim | Severity | Notes |
|---|----------|-------|----------|-------|
| 10 | `chaos_wastes_tweaker.lua` 1-27 | `extensions_ready` fires after `SimpleInventoryExtension.init` | MED | Relied on by ghost-scythe fix. Verify against VT2 source. |

### Design-doc assumptions (in `PER_BOON_SCALING_BOONS_PLAN.md`, feature not yet implemented)

| # | Location | Claim | Severity | Notes |
|---|----------|-------|----------|-------|
| 11 | 154-157 | `max_health` buffs may not retroactively heal mid-run | TBD | Validate before implementing scaling boons. |
| 12 | 154-157 | `cooldown_regen` should compound multiplicatively; may run away at 30+ boons | TBD | Validate before implementing. |
| 13 | 154-157 | `healing_received` covers THP-from-kill talents | TBD | Smoke test needed before implementing. |

---

## Stale

- `CODE_REVIEW.md` (dated 2026-05-01) flags campaign-potion weight skew as MED severity, but `CHANGELOG.md` v0.3.0-dev (same day) says "Fixed." Either CODE_REVIEW is stale, or the fix is partial. Verify completeness before relying on the doc.

---

## Recommended actions

Held — user requested no investigation work at this time. Items above are annotated for future reference. When a user-visible bug ties to one of these items, start by checking this doc first.

---

## History

- **2026-05-13** — Initial audit. v0.6.5-0.6.6 ghost-scythe workaround verified removed; 13 open assumptions catalogued; 1 stale doc reference noted.
- **2026-05-19** — v0.7.64 shipped. Open issues deferred:
  - Curse/mission visual desync across peers (different halos/lighting) — caused by `inject_adventure_maps` divergence between peers (it remains per-peer due to the lobby combined-hash constraint). Fix path: host→client graph snapshot RPC after `deus_populate_graph`. Deferred.
  - Mod-mismatch logging — planned `ct_peer_manifest` RPC + `/peers` chat command for diagnosing version drift in lobbies. Deferred.
  - Chest of Trials revive option needs user-side QA — host-mode log with `state=3` not yet captured; static analysis shows the code path is correct. (Related to existing assumption #4 above.)
