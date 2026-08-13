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
| W0 | **Adapter/lifecycle census + CI gate**: machine-readable registry of every registered custom appearance family x SURFACE x EDGE pair (implemented / declared-unsupported-with-fallback); the gate is `qa/lua/tests/test_appearance_census.lua` (in the Lua suite) plus the `qa/check_appearance_census_gaps.ps1` drift check - a `check_appearance_census.ps1` script never existed. Retroactive census of every existing family = the true backlog, currently 3,624 unsupported pairs of 4,624 (`docs/generated/APPEARANCE_CENSUS_GAPS.generated.md`). | census gates green with every existing gap DECLARED (not fixed) | DONE 2026-08-13 (#1157: surface-x-edge schema and six new surfaces; #1198: distinct crafting preview; #1197: all 17 surfaces required by contracts; wt_dev validated as a parity mirror) |
| W1 | **Descriptor library + contract tests**: `_lib_appearance_descriptor.lua` (pure build/validate/fingerprint) + engine-free tests in `qa/lua/tests/`; CWV owns the first synchronized runtime copy. | 966+ suite green | DONE 2026-08-06 (#1155 pilot prerequisite) |
| W2 | **Reconciler skeleton + pilot family**: lifecycle-edge reconciler in the shared lib; migrate ONE worst-record family (CWV Old Musket, #474 controls) across all cells; delete its legacy paths. | pilot family passes the co-op matrix in-game | source complete in CWV 0.1.513-dev with exact Athanor preview identity; Workshop deployment, solo proof, then co-op runtime proof pending |
| W3 | **Extraction-420 cutover completion**: shared transform ownership is source-complete across CWV, Cosmetics, both WT streams, and WOC; the remaining Cosmetics material/texture fallback belongs to the broader #660 migration. | per-step four-render-path regression + in-game verify | Cosmetics source candidate pending release/no-drift verification; material fallback pending under #660 |
| W4 | **Remaining families**, one per change, closing their symptom issues as they migrate; #660's issue index burns down. | each family's cells green | pending |
| W5 | **OOP completion**: ct_dev + cwv decomposition (last two god files), #727 logging sweep, doc reconciliation. | full QA green, per-mod module contracts documented | DONE 2026-08-12 (#1159: all 10 decomposition contracts complete; final CT Dev entry 1,498 nonblank lines, CWV entry 1,490) |

### W2 exact readiness (updated 2026-08-13)

The `0.1.513-dev` Old Musket pilot declares all 136 surface-x-edge
cells under one descriptor/reconciler contract. Twelve cells have runtime
delivery/adapters that apply and read back the authored custom presentation:
owner 1P equip/customize, owner 3P equip/customize, bot equip, remote husk
equip/peer-ready, and preview-open for inventory, illusion browser, CIM
Athanor, lobby, and score/team. The other 124 cells are census declarations
with vanilla-safe fallbacks; many have no runtime call site and are enumerated,
not fixed.

CIM shares `LootItemUnitPreviewer` with the illusion browser, but CWV now marks
only the exact previewer returned by
`HeroWindowWeaveProperties._create_item_previewer`. The shared spawn owner
therefore classifies that instance as `cim_preview` while every unmarked generic
previewer remains `illusion_browser`; `cim_preview/preview_open` is the twelfth
implemented cell. Mission-transition and respawn cells remain unsupported until
directly observed, even when equipment recreation may route through the
implemented equip edge.

Phase 3 merged in PR #1165 and remains an ancestor of the current deployed
source. PR #1275 repaired a package-lifecycle defect exposed by the live pilot:
the custom Old Musket units are carried by CWV's master bundle but borrow the
vanilla Handgun's first- and third-person materials. The old package shim
reported the custom paths loaded without loading those donor packages, allowing
preview and world spawns before their materials existed. CWV `0.1.512-dev` now
bridges each custom path through the matching reference-counted donor-package
lifecycle while preserving callbacks and caller reference names. Exact merged-
master QA passed at `9d09865e18e8bccf941a73bf454d2f1f8fdf6ea5`, and Workshop
item `3716869446` accepted manifest `4902287303108476249`. This strengthens the
deployed pilot. The 0.1.513-dev source adds the exact Athanor marker and retained
`[cwv:1155] surface=cim_preview` receipt, but the new build still requires
deployment and does not satisfy the live gate by source inspection: the pinned
solo owner-and-preview test on #1155/#474 must pass first, followed by the
remote-husk and bot co-op matrix.

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
