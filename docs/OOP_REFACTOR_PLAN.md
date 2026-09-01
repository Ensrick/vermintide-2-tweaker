# OOP Refactor Plan

> **Status: COMPLETE** (created 2026-07-07; completed 2026-08-22). This is the execution record from the
> 2026-07-07 whole-repo OOP/professionalism audit: 14 active mods + the docs/standards/QA
> machinery, each audited against a fixed 10-dimension rubric with mandatory file:line
> evidence. Full per-mod reports + rubric: `_archive/audits/2026-07-07_oop_audit/`
> (external backup: `..\_vt2-tweaker-archive\2026-07-07\oop-audit\`).
> The six-workstream professionalization program (#1154-#1160) is closed. Continuing
> architecture debt remains owned by the referenced follow-up issues.

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
gate on protected `master`. The original frozen-debt statement is also historical:
the size baseline now retains only the two canonical entries that still exceed the
2,500-line hard limit. Completed entries leave that frozen set and remain protected
by their lower machine-contract ceilings.

## Program-close baseline (whole-repository re-score)

The required second audit was executed on 2026-08-09 against `origin/master`
`14c16160`. It re-scored all 140 mod-by-dimension cells using the archived rubric
and original 14 reports as the comparison baseline. Its comparison ref was
`33927fb4`, the original audit-plan commit. The aggregate
checkpoint was preserved on
[#1154](https://github.com/Ensrick/vermintide-2-tweaker/issues/1154#issuecomment-5230487286);
the complete score table is recorded below now that the final structural phase
closed on 2026-08-22. The July
table above remains immutable; this table is the new scored baseline. Later work is
described by the execution inventory and its machine-owned contracts rather than
being silently folded into these scores. The re-score was a read-only static audit;
it did not rerun QA, and it conservatively retained qualitative error-handling and
dead-code scores unless a specifically named baseline driver could be reverified.

| Mod | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 | Total |
|---|---|---|---|---|---|---|---|---|---|---|---|
| chaos_wastes_tweaker_dev | 2 | 4 | 4 | 5 | 5 | 4 | 3 | 5 | 5 | 5 | 42 |
| character_weapon_variants | 2 | 4 | 5 | 5 | 4 | 4 | 3 | 5 | 5 | 5 | 42 |
| cosmetics_tweaker | 3 | 4 | 4 | 5 | 4 | 4 | 4 | 4 | 5 | 5 | 42 |
| crafting_in_modded_dev | 3 | 4 | 4 | 5 | 4 | 4 | 4 | 4 | 5 | 5 | 42 |
| enemy_tweaker | 5 | 5 | 3 | 5 | 3 | 5 | 4 | 4 | 5 | 5 | 44 |
| weapon_tweaker | 3 | 4 | 4 | 5 | 4 | 4 | 4 | 5 | 5 | 5 | 43 |
| career_tweaker | 4 | 4 | 4 | 5 | 4 | 4 | 4 | 5 | 4 | 5 | 43 |
| gui_tweaker_dev | 3 | 4 | 4 | 5 | 4 | 4 | 4 | 4 | 5 | 5 | 42 |
| dynamic_cosmetic_portraits | 4 | 4 | 3 | 5 | 3 | 4 | 3 | 3 | 4 | 5 | 38 |
| event_tweaker | 5 | 5 | 5 | 5 | 5 | 4 | 4 | 5 | 5 | 5 | 48 |
| general_tweaker_dev | 4 | 4 | 4 | 5 | 3 | 4 | 4 | 4 | 5 | 5 | 42 |
| modded_progression | 4 | 4 | 3 | 4 | 4 | 4 | 3 | 4 | 4 | 5 | 39 |
| verminious_dreams_lighting_dev | 5 | 4 | 4 | 5 | 5 | 3 | 4 | 5 | 4 | 5 | 44 |
| weapons_of_chaos | 3 | 5 | 4 | 5 | 5 | 4 | 4 | 4 | 4 | 5 | 43 |
| **Dimension mean** | **3.57** | **4.21** | **3.93** | **4.93** | **4.07** | **4.00** | **3.71** | **4.36** | **4.64** | **5.00** | **4.24** |

The aggregate moved from **522/700 (3.73)** to **594/700 (4.24)**. Doctrine
compliance reached 5.00 across all 14 mods. Regression testing moved from 3.71 to
4.64 after the offline harness grew from no tests to 2,212 cases / 13,558
assertions, and wire/shared-state safety moved from 3.50 to 4.07 after every WS1
axis gained a named policy owner and offline coverage. The weakest remaining
dimensions at this snapshot were decomposition (3.57), dead code (3.71), and
duplication (3.93). Related continuing architecture work is tracked under #2,
#428, and #660 and does not reopen the completed #1154 program.

All six #1154 structural phases are closed. The final #1155 Old Musket pilot was
verified in game on CWV `0.1.526-dev`: Rain observed the authored model visible and
distinct across the Athanor, owner first person, owner third person, inventory
character, illusion browser, weapon swap, and Keep-to-mission transition. The log's
115 bounded receipts retained application, materials, position, scale, and rotation.
Remaining numerical grip and preview-framing calibration is deliberately owned by
#474, not by the completed descriptor pilot.

## Current execution inventory (2026-08-23)

Measured through CT Dev Wave 26 on its isolated branch, based on
`origin/master` `723abaa5`, with the same
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
| General Tweaker Dev bot fixes | Target-tier helper complete | `_gt_bot_fixes.lua` reduced from 2,483 to 1,485 measured lines; ordered update and aid owners retained by contract | #2 |
| Cosmetics | Structural phase complete | Thirty-nine required owners/helpers retain the exact-instance offhand state/apply, transactional LA registration, strict lookup validation, diagnostics, Deus precedence, and prior render/wire/lifecycle boundaries; current entry ceiling 1,494 nonblank lines meets the 1,500 completion target | #504 / #2 / #1159 / #428 |
| Weapon Tweaker | Structural phase complete | Ten required animation, availability, transform, cross-character safety/template, local/preview presentation, Moonfire AOE, regression, and balance owners retained per stream; stable/dev entry ceilings 1,328/1,487 nonblank lines meet the 1,500 completion target | #504 / #2 / #1159 |
| Career Tweaker | Structural phase complete | 907-line balance orchestrator under its 910-line ceiling; bounded catalog, hook, and Foot Knight owners retained by contract | #504 / #2 / #1159 |
| CIM Dev | Structural phase complete | Thirteen required bootstrap/state/wire/forge/inventory/command/economy/loadout/regression owners retained; current entry ceiling 1,433 nonblank lines meets the 1,500 completion target | #1159 / #504 / #2 |
| CT Dev | Structural phase complete | Twenty-eight required owners include host-state transport, run/backend orchestration, adventure presentation, boon/grudge runtime, settings lifecycle, and every prior specialized boundary; current entry ceiling 1,498 nonblank lines meets the 1,500 completion target | #1159 / #504 / #291 / #107 / #104 / #258 / #271 / #2 |
| CWV | Structural phase complete | Nineteen required catalog, template, skin/illusion, javelin/rapier, bootstrap, identity-transport, world/husk/menu presentation, registration, transform, mesh, musket, and regression owners retained; current entry ceiling 1,490 nonblank lines meets the 1,500 completion target | #504 / #2 / #1159 |
| Weapons of Chaos | Structural phase complete | Fourteen required wire, Blightreaper, rarity, appearance, preview, icon, relic-registration, relic-catalog, and lifecycle owners retained; current entry ceiling 1,390 nonblank lines meets the 1,500 completion target | #504 / #2 / #1159 |
| Shared copied libraries | Partial | exact-byte sync gate covers 14 canonical libraries across 51 manifested consumer copies; roadmap items remain under #428 | #428 |
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

> **STATUS: DELIVERED 2026-08-09** (#371 / #1158, install-transaction fanout slice).
> Evidence:
> - **Install is one transaction.** `tools/shared_lib/_lib_peer_parity.lua`
>   `api:install()` builds the receiver and the wrapped update first, then performs
>   `mod:network_register(CHANNEL, receiver)` AND `mod.update = wrapped_update`
>   inside a single `pcall`; `_installed` commits only after both return, and the
>   receiver is inert until it does. A throw restores the exact previous
>   `mod.update` when the wrapper became externally visible. `_install_attempted`
>   makes a failed attempt TERMINAL, so no retry can double-register a receiver
>   the transport already retained. `install()` returns the commit boolean.
> - **Floors are latched, not caller-disciplined.** `all_peers_have()`,
>   `peer_has()`, `require_peer()` and `tick()` all hard-gate on `_installed`, so
>   an uninstalled beacon is fail-closed by construction.
> - **`all_peers_have(mod_id)` exists.** The lib chunk returns
>   `new_peer_parity, registry`; each instance also carries `inst.registry`.
>   Instances enter the registry at their install commit keyed by `opts.mod_id`
>   (or the host's VMF name). `registry.all_peers_have(mod_id)` returns false for
>   an unknown id and otherwise AND-folds every beacon that mod installed. Query
>   only - it adds no cross-mod coupling and no `get_mod()` dependency.
> - **Fanout is complete.** The canonical lib is byte-identical in all six
>   consumers (career_tweaker, chaos_wastes_tweaker_dev, character_weapon_variants,
>   event_tweaker, weapon_tweaker, weapon_tweaker_dev); `qa/check_shared_lib_drift.ps1`
>   is byte-exact and green. Every consumer seam consumes the commit boolean.
> - **Tests.** `qa/lua/tests/test_peer_parity_install_transaction.lua` covers the
>   partial-install latch, the rollback, the commit path, the aggregator, and the
>   fanout scan, each paired with a planted source mutation proving the assertion
>   is load-bearing.
>
> The Mod Tweaker grey-out half of this row shipped earlier per axis
> (`_ct_wire_policy.runtime_gate_spec`, crt's `runtime_gate_retry_step`).

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

> **STATUS: PARTIAL 2026-08-25.** `tools/shared_lib/manifest.psd1` currently
> enforces 14 canonical libraries across 51 consumer copies. The canonical
> `_lib_network_lookup` now has seven strict, byte-identical consumer copies and Enemy's
> Warlord/Chosen owners share one entry-loaded instance. Remaining-consumer
> migrations for direct NetworkLookup owners, wire substitution, DLC ownership, the
> regression harness, and MIL/build-entry consolidation remain roadmap items.
> Canonical files that are not in the manifest are not migrated consumers and
> do not count as completion.

Remaining priority order by crash-risk: `_lib_network_lookup` per-owner
migrations (bounded individually, not bulk) -> wire-substitution helper
(cosmetics has 4 inline copies) -> `_diag_probe` (triplicated) ->
MoreItemsLibrary embed (#82) -> CWV<->WOC `_build_entry`/wire-hook single-source.

### WS5 - God-file decomposition (#2, ratcheted)

> **2026-07-11: event_tweaker decomposed** (v0.4.26-dev): 1,433-line monolith split
> into 11 single-responsibility `_evt_*` modules + entry manifest; the Duplication=2
> driver (hand-synced MUTATOR_CATALOG/CATEGORIES + DLC-map copies) consolidated into
> a shared require'd `event_tweaker_catalog.lua`; `_MEM_PROBE_T0_EVT` bare global
> retired (WS6 item). Pure structural, 3-agent adversarial review, zero behavior
> findings. et was not on the worst-offender list below; done as the pilot for the
> per-mod OOP pass. The reusable conventions are codified in PROJECT_STANDARDS
> §2.2a; the doc deliverables per decomposition are WS8.

All ten phases in the machine-readable decomposition inventory now meet the
1,500-line structural target. The registry is the authority for their frozen
ceilings and required owners; completion means the entry is bounded and its
tested responsibilities have explicit owners, not that every in-game feature is
verified. Rule: every WS1/WS4 change that touches a completed entry preserves or
lowers its ceiling and extends an existing natural owner (or adds a bounded new
one) without mixing behavior changes into a structural move.

**2026-08-23 GT Dev bot-aid slice:** the contiguous Ironbreaker aid yield,
human-heal/rescue selection, errand pin, and stalled-pursuit cluster moved
verbatim from `_gt_bot_fixes.lua` into `_gt_bot_aid_owner.lua`. The parent fell
from 2,483 to 1,485 measured lines and the new owner begins at 1,087. Its
machine contract retains both ordered child owners, while focused tests pin the
historical install position, two-hook order/cardinality, returned API identity,
dependency rejection, second-load rejection, and registration-error behavior.
This advances #2's target-tier program; it does not complete the remaining file
debt or assert a new in-game behavior.

**2026-08-12 CT wave 26:** host settings and graph transport, run/backend
orchestration, adventure-map presentation, starting-boon/grudge runtime, and
settings lifecycle moved into five explicit owners. An install-order-aware test
source map keeps every existing boundary assertion aimed at the real runtime
position; registration counts remain exactly 16 hooks, 5 safe hooks, 2 network
receivers, and 23 inline regression registrations. CT Dev's entry ceiling falls
from 4,114 to 1,498 nonblank lines, completing the final partial phase: the
registry is now 10 complete, 0 partial.

**2026-08-11 Cosmetics wave 17:** the single VMF `mod.update` scheduler moved
into `_cos_update_scheduler.lua`. Tick order and every existing retry bound are
executable invariants; rebound entry state crosses through paired accessors.
Cosmetics' ratcheted entry ceiling is now 2,915 nonblank lines (down from
3,207). Cosmetics remains partial.

**2026-08-11 Cosmetics wave 18:** exact-instance item-card resolution, the one
`UIUtils.get_ui_information_from_item` hook, and the late Hold-Tab peer adapter
moved together into `_cos_item_presentation_runtime.lua`. Two install phases
preserve the historical post-LA-receiver boundary; executable tests pin vanilla
return preservation and action-time cache refresh. Cosmetics' ratcheted entry
ceiling is now 2,646 nonblank lines (down from 2,915). Cosmetics remains partial.

**2026-08-11 Cosmetics wave 19:** the optional-attachment residency gate,
low-level link replay, and combined Hero/Menu unit-spawn post-processing moved
together into `_cos_spawn_boundary.lua`; the independent Moonfire cosmetic
impact fan-out moved into `_cos_moonfire_puff_runtime.lua`. Executable tests pin
the original hook totals, ordering, headpiece-only fallback, and no-double-puff
gate. Cosmetics' ratcheted entry ceiling is now 2,488 nonblank lines (down from
2,646), below the 2,500 hard limit; Cosmetics remains partial until the
1,500-line completion target.

**2026-08-11 Cosmetics wave 20:** remote wearer identity, LA variant resolution,
stale peer cleanup, mission-world lookup, and the bounded spawn monitor moved
together into `_cos_la_husk_identity_runtime.lua`; the one remote
`SimpleHuskInventoryExtension._wield_slot` transaction moved into
`_cos_husk_wield_runtime.lua`. Executable tests pin identity precedence,
stack-context restoration across vanilla errors, eight-return preservation,
and ordered glow/LA replay. Cosmetics' ratcheted entry ceiling is now 2,051
nonblank lines (down from 2,488), with 32 required owners; Cosmetics remains
partial until the 1,500-line completion target.

**2026-08-11 Cosmetics wave 21:** exact-instance offhand merge/restore/lazy
lookup moved into `_cos_offhand_state_runtime.lua`; local body and preview mesh
validation/paint moved into `_cos_offhand_apply_runtime.lua`; read-only offhand
and glow diagnostics and the Deus mission-only precedence rule gained dedicated
owners. Executable tests pin idempotent merge, bounded restore, fail-closed dual
validation, and mismatched-mesh paint refusal. The entry ceiling remains 1,494
nonblank lines (down from 2,051), now with 39 required owners/helpers after the
transactional LA registrar and manifested lookup consumer. The Cosmetics
structural phase is complete; appearance behavior remains tracked separately.

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
