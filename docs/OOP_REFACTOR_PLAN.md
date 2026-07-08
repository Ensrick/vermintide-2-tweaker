# OOP Refactor Plan

> **Status: ACTIVE** (created 2026-07-07). This is the living execution plan from the
> 2026-07-07 whole-repo OOP/professionalism audit: 14 active mods + the docs/standards/QA
> machinery, each audited against a fixed 10-dimension rubric with mandatory file:line
> evidence. Full per-mod reports + rubric: `_archive/audits/2026-07-07_oop_audit/`
> (external backup: `..\_vt2-tweaker-archive\2026-07-07\oop-audit\`).
> Update the workstream tables here as items land; close via the referenced issues.

## Scoreboard (1 = worst, 5 = best)

Dimensions: 1 Decomposition, 2 Encapsulation, 3 Duplication, 4 Hook hygiene,
5 Wire/shared-state safety, 6 Error handling, 7 Dead code, 8 Data-driven-ness,
9 Regression tests, 10 Doctrine compliance.

| Mod | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 |
|---|---|---|---|---|---|---|---|---|---|---|
| chaos_wastes_tweaker_dev | **1** | 3 | 3 | 5 | 4 | 4 | **2** | 4 | 5 | 3 |
| character_weapon_variants | **1** | 4 | 3 | 5 | **2** | 4 | 3 | 4 | 4 | 4 |
| cosmetics_tweaker | **2** | 3 | 3 | 4 | 4 | 4 | 3 | 4 | 3 | 4 |
| crafting_in_modded_dev | **2** | 3 | 4 | 5 | 4 | 4 | 3 | 4 | 5 | 4 |
| enemy_tweaker | **2** | 4 | 3 | 5 | 3 | 5 | **2** | 4 | 5 | 5 |
| weapon_tweaker | **2** | 4 | 3 | 5 | 3 | 4 | **2** | 5 | 5 | 4 |
| career_tweaker | 3 | 4 | 3 | 5 | **2** | 4 | 3 | 4 | 3 | 4 |
| gui_tweaker_dev | 3 | 4 | 4 | 5 | 4 | 4 | 4 | 4 | 5 | 5 |
| dynamic_cosmetic_portraits | 4 | 4 | 3 | 5 | **2** | 4 | 3 | 3 | **2** | 5 |
| event_tweaker | 4 | 4 | **2** | 4 | 5 | 4 | 3 | 4 | 3 | 5 |
| general_tweaker_dev | 4 | 3 | 3 | 5 | 3 | 4 | 4 | 4 | 5 | 5 |
| modded_progression | 5 | 4 | 3 | 4 | 3 | **2** | 3 | 4 | **2** | 5 |
| verminious_dreams_lighting_dev | 5 | 4 | 4 | 5 | 5 | 3 | 4 | 5 | 4 | 4 |
| weapons_of_chaos | 5 | 5 | 3 | 5 | 5 | 4 | 3 | 4 | **1** | 4 |

**Read of the results.** Hook hygiene is uniformly strong (the duplicate-hook doctrine
worked - zero duplicate `(Class, method)` pairs found anywhere). The systemic weaknesses
are: (a) god-file decomposition (six mods at 2-4x the 2500-line hard limit), (b) three
mods with open cross-peer wire gaps, (c) dead Big Rebalance code shipping in three mods,
and (d) per the docs/gates audit: **0 of 9 binding rules are fully machine-enforced** -
pre-commit runs `-Quick` (skips ~10 of 18 checks), CI runs 7 checks with 5
`continue-on-error`, and the duplicate-hook lint is absent from CI entirely.

## Workstreams

### WS1 - Cross-peer wire safety (crash-risk, do first)

| Item | Mod | Issue | Effort | Notes |
|---|---|---|---|---|
| Javelin projectile/pickup/husk axes: sender-side base substitution + cwv-receiver re-key (extend the #392 Phase C base+career re-key pattern) | cwv | #424 | M | P0. Receiver-side guards protect the wrong peer. |
| Cloned damage_profile on `rpc_attack_hit` | cwv | #423 | M | Gameplay axis: needs peer-parity gate (WS1.5), not silent substitution. |
| `crt_*` talent buffs on `rpc_add_buff` | crt | #425 | L | Gameplay axis: parity gate. |
| Modded boons/miracles | ct | #426 | L | Gameplay axis: parity gate. |
| Cursed Adventure curse injection CTDs non-ET peer | event_tweaker | #430 | M | Gameplay axis: parity gate; today the only guard is a checkbox label. |
| Custom damage profiles ride vanilla RPCs | wt | #431 | M | Gameplay axis: parity gate. |
| WOC raw `woc_` key fall-through if base-index guard short-circuits | weapons_of_chaos | #422 | S | Make the fallback fail-safe (skip send, not raw key). |

**WS1.5 - peer-parity framework (#371, prerequisite for the gameplay axes):** promote
enemy_tweaker's `et_br_fingerprint` handshake (currently DORMANT - no live broadcaster)
into a copied `_lib_peer_parity.lua`: broadcast a mod fingerprint on peer join, expose
`all_peers_have(mod_id)`, auto-disable + grey out gated features in the gut Mod Tweaker,
notify the user which features are off and which peer lacks the mod. NEVER gate
sender-side substitution on it (BUG_CLASSES 31).

### WS2 - Enforcement machinery (the "rules without gates" fix)

| Item | Issue | Effort |
|---|---|---|
| CI parity: `qa.yml` runs `run_all.ps1` (full, policy engine) instead of 7 hand-picked checks; add `lint-mod.ps1` (duplicate hooks) to CI | #429 | M |
| Ratchet baselines: freeze current violations (16 files over size limit, 13 name-integrity errors, luacheck count), block only NEW violations - stops "permanently red so permanently ignored" | #429 | M |
| New gate `check_logging.ps1`: prefix present, no bare `mod:echo` outside §3.6 matrix, no `mod:info` in per-frame hooks | #429 | S |
| New gate: dev-only-edit guard (flag commits touching split-mod stable dirs outside a promotion) | #429 | S |
| `check_versions.ps1`: flag 4-segment versions instead of silently stripping | #429 | S |
| Diff-triggered checklist gate: touched `NetworkLookup`/`mod:hook`? require a matching `_rt_register` marker in the diff | #429 | M |
| Hook-installed self-check: CI verifies `install-hooks.ps1` state documented; pre-commit presence check | #429 | S |

### WS3 - Standards docs: contradictions, staleness, consolidation

| Item | Issue | Effort |
|---|---|---|
| Fix 6 verified contradictions (e.g. `[confirmed working]` canonical in TESTING_STATUS but rejected by LOCALIZATION_STANDARD/loc-tags gate; CHECKS.md says name_integrity "NOT wired" while run_all wires it; mechanics_citations documented advisory but runs blocking) | #432 | S |
| Fix 8 verified stale claims (8-vs-16 oversized files, 16-vs-20 cfgs, la_prefix_patch listed live but folded into cosmetics, etc.) | #432 | S |
| Collapse the status quartet (TODO/WORK_ITEMS/STATUS/TESTING_STATUS) per PROJECT_STANDARDS §11: GitHub Issues are the sole tracker; keep STATUS.md as the single what-now board | #432 | M |
| De-duplicate overlap clusters: hooking rules (5 places), engine quirks (4), localization (4), WEAPONS.md into WEAPON_CATALOG.md, build doctrine (2) - one owner doc per topic, others cite it | #432 | M |
| Move topic references from root into `docs/` (VMF_RECIPES, LOCALIZATION_STANDARD, WEAPON_CATALOG, CROSS_MOD_ARCHITECTURE, COMMANDS, REGRESSION_CHECKLIST...) | #432 | S |
| Write the missing standards: deprecation/retirement lifecycle, cross-mod public-API compat contract, module-header requirement gate | #432 | M |

### WS4 - Shared-lib extraction (#428, respects the standalone invariant: copied `_lib_*.lua`, build-time sync, never `get_mod` deps)

Priority order by crash-risk: `_lib_dbg` (fixes #427 chat-spam, ~18 mods) ->
`_lib_peer_parity` (WS1.5) -> `_lib_netlookup` (the append idiom is copy-pasted 15+
times in cwv alone) -> wire-substitution helper (cosmetics has 4 inline copies) ->
`_diag_probe` (triplicated) -> MoreItemsLibrary embed (#82) -> WeaponAppearance (#420)
-> CWV<->WOC `_build_entry`/wire-hook single-source.

### WS5 - God-file decomposition (#2, ratcheted)

Worst offenders with the auditors' identified extraction seams (all staged,
behavior-preserving, in-game-verifiable steps; hooks stay in the entry file per §2.2):
ct_dev 14,328 lines; cwv 11,808 (do after WS1 lands to avoid churn); cosmetics 10,499
(cleanest seams: wire-safety block ~500 lines, force-load block ~1,200); cim_dev 8,173;
crt balance file 3,815; enemy 3,396; wt 3.1x limit. Rule: every WS1/WS4 change that
touches a god file extracts its seam as part of the change, never "later".

### WS6 - Hygiene sweep (small, high count)

- `_MEM_PROBE_T0_*` bare `_G` globals in 6 mods -> namespace under `mod.`.
- Closed-issue instrumentation still live (cosmetics `[cos:trace]` for #264/265/267/268 etc.).
- Dead Big Rebalance code: crt 2,774-line file dead-on-disk, enemy 1,287-line dead module,
  wt ~3,500 dormant lines. NEEDS USER DECISION (#433): BR integration is a live initiative;
  archive-and-delete vs keep-dormant is not mine to decide unilaterally.
- ct menu tooltip em dashes (violates a NON-NEGOTIABLE) - fix in dev now.
- Inline TODOs -> GitHub issues (cwv ~10, cim, wt, mp).
- Stale §3.6 migration-table rows (woc), stale "chasm" refs (vdl).

### WS7 - Regression coverage gaps

- cosmetics: `wire_skin_null_ungated` check for the new skin-axis hook (its riskiest new seam is its only untested one).
- crt: wire-safety assert for networked buffs (companion to #425).
- woc: class-31 seam check + `/verify` command (score 1 - no suite at all).
- mp: `_with_eac_off` restore not pcall-protected (P1 - a throw re-enables real-account
  PlayFab writes) + suite omits that seam entirely (#434).
- dcp: suite skips the load-bearing seam; career_settings mutation is career-scoped, not
  player-scoped (P1, behavior-affecting - confirm intended behavior first, #435).
- gut: lifecycle-callback chaining has no regression guard.

## Sequencing

1. **Wave 1 (now):** WS1 cosmetic axes (#424, #422) + mp pcall fix + em-dash sweep +
   mem-probe namespacing + WS7 quick checks + WS2 CI parity (#429).
2. **Wave 2:** WS1.5 parity framework, then the gameplay axes (#423/#425/#426/#430/#431).
3. **Wave 3:** WS4 libs in crash-risk order; WS3 docs consolidation.
4. **Continuous:** WS5 extraction rides every touch of a god file; WS6/WS7 fill agent idle time.

## Verification protocol

Every wire change needs a 2-player test (host with mod + clean client, then reversed)
before its issue closes; compile/deploy success is never "fixed" (user confirms in-game).
Dev-stream ships run the full pipeline per doctrine; public promotion only via
`docs/PROMOTION_PROCESS.md` with a fresh per-build ship signal.
