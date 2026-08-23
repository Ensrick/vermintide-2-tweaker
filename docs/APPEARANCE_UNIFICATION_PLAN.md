# Appearance Unification Execution Plan (#660)

**Status:** ACTIVE - execution started 2026-07-18 (overnight session).
**Owner issue:** #660 (umbrella). Normative contract: `docs/WEAPON_APPEARANCE_STANDARD.md`.
Shared-primitive state: `docs/WEAPON_APPEARANCE_EXTRACTION_420.md`.

## 1. Root cause of the whack-a-mole (why fixes never generalize)

Every new item (weapon, variant, illusion, cosmetic) must declare 17 canonical
acceptance surfaces (owner 1P, owner 3P, bot, remote husk, inventory hero
preview, illusion browser, CIM/Athanor preview, ordinary crafting-bench
preview, lobby, score/team, Hold-Tab, specials, remote audio, HUD panels,
portraits, 2D item cards, and inventory tooltips) across eight canonical
lifecycle edges. That is a 136-cell matrix per item family, and every cell is
explicit rather than inferred:

1. **No enumeration.** Nothing in the codebase or CI knows the matrix exists.
   A new feature that implements 52 cells and misses 8 ships silently; the 8
   become next week's issues. This is the generator of the recurring class -
   `WEAPON_APPEARANCE_STANDARD.md` already lists 29 issue numbers as
   instances, and #660's history counts 138.
2. **Per-mod, per-surface re-implementation.** CWV, cosmetics_tweaker, WT,
   WOC, and cim each resolve identity, hand, perspective, career, residency,
   and render path independently at each hook site. The shared geometry
   primitive (`_lib_weapon_appearance.lua`, #420) now owns ordinary transform
   math for CWV, both WT streams, WOC, and the source-complete Cosmetics
   adapter; material fallbacks and ALL identity/lifecycle logic remain
   family-owned or forked.
3. **Setter-success verification.** Fix validation has repeatedly asserted
   that a setter call succeeded rather than that the engine RETAINED the
   state (#660's documented false-positive: WOC logged target
   {0,0,-0.3}/{0.9} while the retained state stayed identity). Fixes ship
   with green logs and wrong pixels.
4. **No bounded reconciler.** Lifecycle edges (peer-ready replay, mission
   transition, preview reopen) are hand-wired per feature; a family wired at
   equip-time regresses at transition-time because nothing replays the same
   descriptor at every edge.

## 2. Solution architecture (from #660, now being executed)

- **S1 Canonical immutable descriptor** per exact item instance: identities
  (primary/offhand), authored units + packages, materials/glow, complete
  pose/transform per perspective, effective animation template, icon/name,
  peer-capability requirement, vanilla-safe fallback. Pure data; engine-free
  library: `tools/shared_lib/_lib_appearance_descriptor.lua`.
- **S2 Enumerated adapters** - one per acceptance cell, each declaring which
  descriptor fields it consumes and returning RETAINED observed state.
- **S3 One bounded lifecycle reconciler** - applies the descriptor once per
  edge (instance load, peer-ready/hot-join, equip/wield, customization
  change, preview open/reopen, mission transition, respawn, score/lobby
  build, mod-disable restore); coalesces duplicates; never streams per-frame.
- **S4 Postcondition-first verification** - every apply returns retained unit
  identity + pose + material state; partial-channel application is failure;
  owner and observer logs correlate the same descriptor fingerprint.
- **S5 Family-at-a-time migration with deletion** - each family moves behind
  the pipeline and its legacy per-surface hooks are DELETED in the same
  change; two writers never race.

## 3. Execution waves

| Wave | Deliverable | Gate | State |
|---|---|---|---|
| W0 | **Adapter/lifecycle census + CI gate**: machine-readable registry of every registered custom appearance family x SURFACE x EDGE pair (implemented / declared-unsupported-with-fallback); the gate is `qa/lua/tests/test_appearance_census.lua` (in the Lua suite) plus the `qa/check_appearance_census_gaps.ps1` drift check - a `check_appearance_census.ps1` script never existed. Retroactive census of every existing family = the true backlog, currently 3,613 unsupported pairs of 4,624 (`docs/generated/APPEARANCE_CENSUS_GAPS.generated.md`). | census gates green with every existing gap DECLARED (not fixed) | DONE 2026-08-13 (#1157: surface-x-edge schema and six new surfaces; #1198: distinct crafting preview; #1197: all 17 surfaces required by contracts; wt_dev validated as a parity mirror) |
| W1 | **Descriptor library + contract tests**: `_lib_appearance_descriptor.lua` (pure build/validate/fingerprint) + engine-free tests in `qa/lua/tests/`; CWV owns the first synchronized runtime copy. | 966+ suite green | DONE 2026-08-06 (#1155 pilot prerequisite) |
| W2 | **Reconciler skeleton + pilot family**: lifecycle-edge reconciler in the shared lib; migrate ONE worst-record family (CWV Old Musket, #474 controls); enumerate unsupported cells with fail-closed fallbacks instead of inventing coverage. | exact applicable owner/preview/transition postconditions pass in game; unsupported cells stay explicit | DONE 2026-08-21 (#1155 verified on CWV 0.1.526-dev; #1156 false-negative oracle repaired and closed 2026-08-22) |
| W3 | **Extraction-420 cutover completion**: shared transform ownership is source-complete across CWV, Cosmetics, both WT streams, and WOC; the remaining Cosmetics material/texture fallback belongs to the broader #660 migration. | per-step four-render-path regression + in-game verify | Cosmetics source candidate pending release/no-drift verification; material fallback pending under #660 |
| W4 | **Remaining families**, one per change, closing their symptom issues as they migrate; #660's issue index burns down. | each family's implemented cells retain the descriptor postconditions in game; unsupported cells remain explicit and safe | ACTIVE 2026-08-22 (Greatsword/Imperial Longsword Combat Style source candidate is the first family; release and live evidence pending) |
| W5 | **OOP completion**: ct_dev + cwv decomposition (last two god files), #727 logging sweep, doc reconciliation. | full QA green, per-mod module contracts documented | DONE 2026-08-12 (#1159: all 10 decomposition contracts complete; final CT Dev entry 1,498 nonblank lines, CWV entry 1,490) |

### W2 verified outcome and W4 boundary (updated 2026-08-22)

The Old Musket pilot declares all 136 surface-x-edge cells under one
descriptor/reconciler contract. Seventeen cells have source-backed runtime
delivery/adapters: owner 1P/3P `instance_load`, `equip`, and `customize`; bot
`instance_load` and `equip`; remote husk `instance_load`, `equip`, and
`peer_ready`; plus `instance_load` and stable `preview_open` for inventory,
illusion browser and CIM Athanor. Lobby and score/team lack an exact selected-
slot identity producer and therefore remain explicit vanilla-safe fallbacks.
All other cells are explicit fallback declarations, not claims that those
lifecycle paths ran.

CIM shares `LootItemUnitPreviewer` with the illusion browser. CWV consumes CIM
Dev's public `cim_preview_context_v1` exact-instance provider across Weapons,
Properties, and Overview. A genuinely absent marker remains
`illusion_browser`; a present but invalid, foreign, stale, or identity-mismatched
marker stays CIM-classified and is terminally rejected so it cannot mutate an
Athanor row through the ordinary-browser fallback. Loot construction owns
`instance_load`, while `_enable_item_units_visibility(visible=true)` is the
separate package/mip-stable `preview_open` edge. Unsupported mission-transition
and respawn census cells do not become supported merely because equipment
recreation happens to route through an implemented construction/equip edge.

The 2026-08-20 CWV `0.1.523-dev` live run falsified the earlier donor-package
theory. Both Handgun packages completed before the first spawn, yet each custom
unit's FBX `rifle_mat` still resolved to `#ID[b6d0945a]`/null. Engine source shows
ordinary GearUtils and preview spawns never interpret arbitrary
`data.mat_to_use`; package residency was not material attachment. The same run
also exhausted both historical retries synchronously and let the synthetic
#1155 regression pass while every real renderer reported `retained=false`.

The final `0.1.526-dev` pilot preserves the proven self-contained asset pattern:
both `.unit` files bind `rifle_mat` to a CWV-owned `.material`, the root package
owns that material and all five textures, and runtime proves the exact closure,
performs one authored-material bind, then reads every mesh handle back. A token
has one attempt; only a distinct source-backed edge may retry. Rain's pinned
solo run verified the authored model as visible, textured, upright, and distinct
from the vanilla Handgun in the Athanor, owner first person, owner third person,
inventory character, illusion browser, after weapon swapping, and after the
Keep-to-Righteous-Stand transition. Its log contains 115 bounded retention
receipts; every receipt retained application, materials, position, scale, and
rotation through `atomic-local-pose`, with no transform error.

The repair also makes attachment-parent identity part of the descriptor. Held
rifle and held polearm recipes are distinct in owner 1P and character 3P, while
the camera-world preview carrier selects a separate display profile. This is not
surface-local pose duplication: consumers select one closed-vocabulary profile,
and the descriptor owns every profile's transform. The remaining small grip,
aim, and preview-framing adjustments are numerical presentation calibration
under #474, not descriptor, resource, lifecycle, or orientation failures.

The aggregate `/cwv_regression_test` in the successful live run was not clean:
its #1155 oracle incorrectly demanded two stance rows from an illusion browser
that has no stance control. #1156 repaired that false-negative instrument under
PR #1356 and closed only after exact-master QA. W2 therefore closes on observed
retained state plus a corrected oracle, not on the earlier aggregate count.

W2 is a structural pilot, not a claim that every family or peer surface is now
fixed. W4 must migrate one registered family at a time, reuse the descriptor and
bounded reconciler, delete the superseded family-specific writers in the same
change, and verify the affected leaf issues at their actual topology. Remote
husk, bot, role-reversal, hot-join, dual/offhand, lobby, score/team, Hold-Tab,
and other provider-specific gaps remain work until their exact census cells and
leaf acceptance criteria have direct evidence.

The first W4 source candidate is the Greatsword/Imperial Longsword Combat Style
family. Its exact loadout snapshot builds one immutable descriptor containing
skin, complete hand paths and fallbacks, effective template, remap, transform,
style, and generation. The same descriptor now crosses the existing exact
identity lifecycle, reconstructs locally on the observer, owns the husk
postcondition, and drives local/remote transform selection. Arrival order,
same-style/new-fingerprint transitions, tampering, unavailable local state, and
targeted peer teardown have executable host coverage. This is not yet live
evidence and does not promote any census cell until a released build passes the
localized solo card and then the remaining co-op topology.

## 3a. Single-vocabulary rule (#1158, 2026-08-08)

**New appearance surface and edge names enter through
`tools/shared_lib/_lib_appearance_descriptor.lua` (`M.CELLS` / `M.EDGES`) ONLY.**

W0 shipped the census vocabulary, but `qa/appearance_contracts.psd1` kept its
own older spellings for the same surfaces (`bot_3p`/`bot`,
`remote_husk_3p`/`husk`, `cosmetic_preview`/`illusion_browser`,
`athanor_preview`/`cim_preview`, `lobby_preview`/`lobby`,
`score_screen`/`score_team`, `customization_change`/`customize`) and never read
the census. Two vocabularies for one domain reintroduce the exact W0 failure at
one remove: a hole can sit between them because neither gate can tell that two
rows are the same row.

The manifest is now spelled canonically, and
`qa/check_appearance_contracts.ps1` validates every name - its own required
minimum included - against
`tools/shared_lib/_lib_appearance_name_authority.lua`. That authority binds each
legacy spelling to its canonical name, records the contract names that are
deliberately FINER than the census as refinements of a canonical edge (the
contracts declare per-mod behavioural CONCERNS and replay coverage; the census
declares per-family surface x edge SUPPORT - different measurements, one name
space), and records genuine census gaps. An unmapped name fails the gate.

Two things stay deliberately distinct rather than folded away. The vanilla
`crafting_preview` bench is now the seventeenth canonical census surface
(**#1198**) and is not an alias of `cim_preview`, the CIM Athanor forge;
`initial_spawn` refines `equip` rather than `instance_load`. The authority lives
outside the descriptor because
`tools/shared_lib/manifest.psd1` byte-syncs the descriptor into the CWV mod
bundle, and a QA-only naming change must not rewrite a shipped mod file.

**Bidirectional coverage - issue #1197.** Every one of the 15 behavioral
contracts now declares all 17 canonical surfaces, including the six added by
#1157 and `crafting_preview` from #1198. `check_appearance_contracts.ps1`
retains an explicit required list so the manifest cannot shrink its own
boundary, and reverse-checks that list against every canonical surface emitted
by the descriptor authority. A future surface therefore fails until the gate,
manifest, and every concern are expanded together. The edge axis needs no
equivalent migration: all eight canonical edges were already represented by at
least one contract edge or refinement.

## 4. Release rule (restating #660's mandate as policy)

No appearance/model/transform/glow/style issue receives `verify-fix` from a
setter-success log or a single-surface check. The label requires the census
row for that family to be green across cells, and the test-method comment
must name the cells exercised.

## 5. Evidence base

- 2026-07-18 co-op session logs (Downloads, 03:22-04:10 UTC): forensic sweep
  in progress - peer map, appearance incident timeline, per-surface failure
  list. Findings land in #660 comments.
- 321-open-issue classification sweep (in progress): every open issue tagged
  APPEARANCE-class or not, umbrella assignment, fix-state verdict.
