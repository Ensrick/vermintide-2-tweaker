# OOP Refactor Plan

> **Status: ACTIVE** (created 2026-07-07). This is the living execution plan from the
> 2026-07-07 whole-repo OOP/professionalism audit: 14 active mods + the docs/standards/QA
> machinery, each audited against a fixed 10-dimension rubric with mandatory file:line
> evidence. Full per-mod reports + rubric: `_archive/audits/2026-07-07_oop_audit/`
> (external backup: `..\_vt2-tweaker-archive\2026-07-07\oop-audit\`).
> Update the workstream tables here as items land; close via the referenced issues.

## Baseline scoreboard (2026-07-07; 1 = worst, 5 = best)

This table is the immutable audit baseline, not a claim about current source. The
execution inventory below is the current status surface. Re-score only through a
new whole-repository audit; do not silently edit baseline scores as individual
slices land.

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

**Baseline read.** Hook hygiene was uniformly strong (zero duplicate
`(Class, method)` pairs), while decomposition, cross-peer wire safety, and machine
enforcement were the systemic weaknesses. The original finding that zero binding
rules were fully enforced is historical: #429 and #540 subsequently put the full QA
gate on protected `master`. Remaining decomposition debt is still real because the
size gate ratchets nine over-limit files instead of treating them as compliant.

## Current execution inventory (2026-07-19)

Measured on `origin/master` `790c5661` with the same
`(Get-Content | Measure-Object -Line).Lines` metric used by
`qa/check_file_sizes.ps1`. The machine-readable owner is now
`qa/decomposition_contracts.psd1`; `qa/check_decomposition_contracts.ps1`
runs in Quick/full QA, prints the live census, blocks entry-point regrowth or
loss of a declared extracted owner, and self-tests planted failures. This table
explains the contracts; it is not a second hand-maintained numeric authority.

| Scope | State | Current evidence | Owning issue |
|---|---|---|---|
| Event Tweaker | Structural phase complete | 62-line entry manifest; `_evt_*` owners retained by contract | #504 |
| Enemy Tweaker | Structural phase complete | 97-line entry manifest; `_et_*` owners retained by contract | #504 |
| Cosmetics | Partial | Four phase slices plus runtime/wire, exact-item offhand session-state, modded-illusion-swap, magic-family visibility, command ownership, item-grid/illusion-card presentation, one three-callback mod lifecycle owner, and the bounded #660 LA replay coordinator; entry ceiling is machine-owned in `qa/decomposition_contracts.psd1` | #504 / #2 / #1159 |
| Weapon Tweaker | Partial | Animation, runtime-check, and feature-owner slices landed; beta/dev entry ceilings 4,183/4,335 lines | #504 / #2 |
| Career Tweaker | Structural phase complete | 910-line balance orchestrator; bounded early/late declarative catalogs, composition owner, hook owner, and Foot Knight owner retained by contract | #504 / #2 / #1159 |
| CIM Dev | Partial | Forge/inventory/diagnostic/command owners and regression suite extracted; entry ceiling 5,110 lines | #1159 / #504 / #2 |
| CT Dev | Partial | Combat, boon, and regression owners extracted; entry ceiling 11,333 lines | #504 / #2 |
| CWV | Partial | Catalog, core-template constructors, commands, regression, exact-appearance, and husk owners extracted; entry ceiling 9,633 lines | #504 / #2 |
| Shared copied libraries | Partial | exact-byte sync gate is green for five manifested libraries; roadmap items remain under #428 | #428 |
| Appearance consistency | Separate architecture program | descriptor/census work and live diagnostics are owned by #660; module splitting alone does not prove render-surface consistency | #660 |

#504 owns the staged structural decomposition and its module contracts. #2 owns
the executable hard-limit gate, #428 owns cross-mod copied-library migration, and
#660 owns appearance descriptors/adapters across render and lifecycle surfaces.
Completion evidence from one of those issues must not be used to close another.

**Process-residue instrumentation (2026-08-06, #1160).** The decomposition
registry is also the numeric debt owner: pull-request QA compares its total
ceiling sum with the manifest at the target master ref, prints the exact delta,
and blocks an existing ceiling increase or contract removal. The separate
promotion owner remains `docs/PROMOTION_PROCESS.md`; canonical split-stream
ships now print the exact dev/public versions and uncited dev issue references
before the build boundary. Neither signal performs a promotion automatically.

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

**WS1.5 - peer-parity framework (#371, prerequisite for the gameplay axes):** use the
copied `_lib_peer_parity.lua` contract: broadcast a mod fingerprint on peer join, expose
`all_peers_have(mod_id)`, auto-disable + grey out gated features in the gut Mod Tweaker,
notify the user which features are off and which peer lacks the mod. NEVER gate
sender-side substitution on it (BUG_CLASSES 31).

### WS2 - Enforcement machinery (the "rules without gates" fix)

> **STATUS: COMPLETE 2026-07-17.** #429 installed the full policy engine in CI;
> #540 verified a green remote run and applied protected-branch enforcement. #2
> remains open for ratcheted size debt, not because CI is unprotected or absent.

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

> **STATUS: COMPLETE 2026-07-08** - all rows landed via #432 phases 1-3 (commits bf993e8, 9c6f79c, 5792f61). Contradictions/stale claims fixed; status quartet retired to STATUS.md + Issues; overlap clusters merged to owner docs (VMF_RECIPES = hooking, WEAPON_CATALOG absorbed WEAPONS.md, WEAPON_APPEARANCE_STANDARD = render paths, LOCALIZATION_STANDARD = loc, CLAUDE.md = build doctrine); root topic docs moved to docs/ with pointer stubs; PROJECT_STANDARDS gained §7.10 deprecation lifecycle + §9a cross-mod API compat. Module-header standard already existed (§2.2); its QA gate is #429 scope. Issue #432 left open for user review.

| Item | Issue | Effort |
|---|---|---|
| Fix 6 verified contradictions (e.g. `[confirmed working]` canonical in TESTING_STATUS but rejected by LOCALIZATION_STANDARD/loc-tags gate; CHECKS.md says name_integrity "NOT wired" while run_all wires it; mechanics_citations documented advisory but runs blocking) | #432 | S |
| Fix 8 verified stale claims (8-vs-16 oversized files, 16-vs-20 cfgs, la_prefix_patch listed live but folded into cosmetics, etc.) | #432 | S |
| Collapse the status quartet (TODO/WORK_ITEMS/STATUS/TESTING_STATUS) per PROJECT_STANDARDS §11. Historical outcome kept STATUS as a board; superseded 2026-07-16 because it had not been maintained since 2026-07-12. GitHub Issues is now the sole current tracker and STATUS is dated history. | #432 | M |
| De-duplicate overlap clusters: hooking rules (5 places), engine quirks (4), localization (4), WEAPONS.md into WEAPON_CATALOG.md, build doctrine (2) - one owner doc per topic, others cite it | #432 | M |
| Move topic references from root into `docs/` (VMF_RECIPES, LOCALIZATION_STANDARD, WEAPON_CATALOG, CROSS_MOD_ARCHITECTURE, COMMANDS, REGRESSION_CHECKLIST...) | #432 | S |
| Write the missing standards: deprecation/retirement lifecycle, cross-mod public-API compat contract, module-header requirement gate | #432 | M |

### WS4 - Shared-lib extraction (#428, respects the standalone invariant: copied `_lib_*.lua`, build-time sync, never `get_mod` deps)

> **STATUS: PARTIAL 2026-07-19.** `tools/shared_lib/manifest.psd1` currently
> enforces exact copies for `_lib_peer_parity`, `_lib_debug`,
> `_lib_weapon_appearance`, `_lib_career_weapon_actions`, and
> `_lib_effective_weapon_templates`. `_lib_netlookup`, wire substitution,
> DLC ownership, the regression harness, and MIL/build-entry consolidation remain
> roadmap items. Canonical files that are not in the manifest are not migrated
> consumers and do not count as completion.

Priority order by crash-risk: `_lib_dbg` (fixes #427 chat-spam, ~18 mods) ->
`_lib_peer_parity` (WS1.5) -> `_lib_netlookup` (the append idiom is copy-pasted 15+
times in cwv alone) -> wire-substitution helper (cosmetics has 4 inline copies) ->
`_diag_probe` (triplicated) -> MoreItemsLibrary embed (#82) -> WeaponAppearance (#420)
-> CWV<->WOC `_build_entry`/wire-hook single-source.

### WS5 - God-file decomposition (#2, ratcheted)

> **2026-07-11: event_tweaker decomposed** (v0.4.26-dev): 1,433-line monolith split
> into 11 single-responsibility `_evt_*` modules + entry manifest; the Duplication=2
> driver (hand-synced MUTATOR_CATALOG/CATEGORIES + DLC-map copies) consolidated into
> a shared require'd `event_tweaker_catalog.lua`; `_MEM_PROBE_T0_EVT` bare global
> retired (WS6 item). Pure structural, 3-agent adversarial review, zero behavior
> findings. et was not on the worst-offender list below; done as the pilot for the
> per-mod OOP pass. The reusable conventions are codified in PROJECT_STANDARDS
> §2.2a; the doc deliverables per decomposition are WS8.

Enemy and Event are the only phases in this umbrella whose entry points now meet
the manifest-only target. Cosmetics, WT, CRT, CIM Dev, CT Dev, and CWV have real,
tested extraction slices but remain partial at the sizes recorded in the current
execution inventory. PR #744 extracted CT's regression owner and CWV's husk path;
its title's "two remaining god files" means two remaining targets in that batch,
not completion of either entire entry point. Rule: every WS1/WS4 change that
touches a god file extracts its natural owner seam as part of the change, never
"later", without mixing behavior changes into the structural move.

### WS6 - Hygiene sweep (small, high count)

- `_MEM_PROBE_T0_*` bare `_G` globals in 6 mods -> namespace under `mod.`.
- Closed-issue instrumentation still live (cosmetics `[cos:trace]` for #264/265/267/268 etc.).
- Retired Big Rebalance code was deleted from crt, enemy, and both wt trees under #433;
  hidden setting identifiers remain reserved for save compatibility, and source remains
  recoverable from git history.
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

### WS8 - Documentation & guidance (maintainability directive, user 2026-07-11)

Docs are first-class deliverables of every refactor; doc updates land in the SAME
commit as the code they describe. The module-split conventions are codified in
**PROJECT_STANDARDS §2.2a** (added 2026-07-11 from the event_tweaker template) -
that section, not this plan, is where the standard lives across sessions.

| Item | Effort | Notes |
|---|---|---|
| Per-mod doc standard: every decomposed mod's DEVELOPMENT.md carries a "Module contracts" section (per file: responsibility, public surface on `mod`, manifest position) + a "Where new code goes" placement recipe; REGRESSION_CHECKLIST.md detection pointers name the owning files | S per mod | event_tweaker done (pilot); apply as each WS5 decomposition lands |
| Per-mod CLAUDE.md where guardrails exceed one screen (dcp + event_tweaker have one); hub `CLAUDE.md` Tier-3 routing line added in the same commit (per-mod CLAUDE.md files do NOT auto-load - the hub routes to them) | S per mod | Evaluate per mod; thin router + hard rules only, architecture stays in DEVELOPMENT.md (no duplication - WS3 lesson) |
| Hub CLAUDE.md accuracy sweep: mod-directory rows, Tier-3 doc lists, and helper-pattern line citations (file:line refs rot on every split - prefer file + symbol over line numbers) | S | recurring; ride each decomposition |
| Stale-claim purge per mod at decomposition time (event_tweaker had: visibility "private" vs actual public cfg, retired `mod._ET_*` fields, "keep in sync" instructions for retired duplicates) | S per mod | `qa/check_stale_docs.ps1` exists - extend its patterns as classes surface |
| Engine reference material: a separate engine-research workflow produces `docs/engine/` from the decompiled source. Do NOT create that directory here; when it lands, link it from `docs/MECHANICS.md` (the provenance-enforced index owns engine-mechanic pointers) and from per-mod DEVELOPMENT.md sections that currently cite raw decompiled paths | - | coordination note only |

## Sequencing

1. Preserve the completed #429/#540 enforcement and #432 documentation work;
   these are closed prerequisites, not active waves.
2. Address crash-risk wire and authority defects before optional structural churn.
   #660 owns appearance consistency; #504 must not absorb its behavior fixes.
3. Continue #428 migrations one canonical library at a time with exact-copy drift
   coverage and standalone-mod verification.
4. Continue #504/#2 by extracting one natural owner boundary at a time. Each slice
   keeps registration/hook order, adds an engine-free boundary test, updates module
   contracts, and ratchets the measured size downward. Do not batch unrelated mods
   merely to call a phase complete.

## Verification protocol

Every wire change needs a 2-player test (host with mod + clean client, then reversed)
before its issue closes; compile/deploy success is never "fixed" (user confirms in-game).
Dev-stream ships run the full pipeline per doctrine; public promotion only via
`docs/PROMOTION_PROCESS.md` with a fresh per-build ship signal.
