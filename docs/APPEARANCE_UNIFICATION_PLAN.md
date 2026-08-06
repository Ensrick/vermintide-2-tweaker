# Appearance Unification Execution Plan (#660)

**Status:** ACTIVE - execution started 2026-07-18 (overnight session).
**Owner issue:** #660 (umbrella). Normative contract: `docs/WEAPON_APPEARANCE_STANDARD.md`.
Shared-primitive state: `docs/WEAPON_APPEARANCE_EXTRACTION_420.md`.

## 1. Root cause of the whack-a-mole (why fixes never generalize)

Every new item (weapon, variant, illusion, cosmetic) must light up ~10
acceptance cells (owner 1P, owner 3P, bot, remote husk, inventory hero
preview, illusion browser, CIM craft preview, lobby, score/team, Hold-Tab)
across ~6 lifecycle edges (equip, swap/customize, lobby-join replay, hot
join, mission transition, cross-session persistence load). That is a ~60-cell
matrix per item family, and TODAY every cell is opt-in:

1. **No enumeration.** Nothing in the codebase or CI knows the matrix exists.
   A new feature that implements 52 cells and misses 8 ships silently; the 8
   become next week's issues. This is the generator of the recurring class -
   `WEAPON_APPEARANCE_STANDARD.md` already lists 29 issue numbers as
   instances, and #660's history counts 138.
2. **Per-mod, per-surface re-implementation.** CWV, cosmetics_tweaker, WT,
   WOC, and cim each resolve identity, hand, perspective, career, residency,
   and render path independently at each hook site. The shared geometry
   primitive (`_lib_weapon_appearance.lua`, #420) landed but only CWV's
   transform path consumes it; textures, cosmetics, WT, and ALL identity/
   lifecycle logic remain forked (extraction-420 cutover steps 2-5 pending).
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
| W0 | **Adapter/lifecycle census + CI gate**: machine-readable registry of every registered custom appearance family x SURFACE x EDGE pair (implemented / declared-unsupported-with-fallback); the gate is `qa/lua/tests/test_appearance_census.lua` (in the Lua suite) plus the `qa/check_appearance_census_gaps.ps1` drift check - a `check_appearance_census.ps1` script never existed. Retroactive census of every existing family = the true backlog, enumerated once: 3,339 unsupported pairs of 4,352 (docs/generated/APPEARANCE_CENSUS_GAPS.generated.md). | census gates green with every existing gap DECLARED (not fixed) | DONE 2026-08-04 (#1157: re-keyed to surface-x-edge cells, 6 surfaces added, wt_dev brought under validation) |
| W1 | **Descriptor library + contract tests**: `_lib_appearance_descriptor.lua` (pure build/validate/fingerprint) + engine-free tests in `qa/lua/tests/`; CWV owns the first synchronized runtime copy. | 966+ suite green | DONE 2026-08-06 (#1155 pilot prerequisite) |
| W2 | **Reconciler skeleton + pilot family**: lifecycle-edge reconciler in the shared lib; migrate ONE worst-record family (CWV Old Musket, #474 controls) across all cells; delete its legacy paths. | pilot family passes the co-op matrix in-game | source and Workshop deployment complete in CWV 0.1.495-dev; solo/co-op runtime proof pending |
| W3 | **Extraction-420 cutover completion**: CWV textures, cosmetics transforms, cosmetics texture fallback, WT transforms (steps 2-5 of that doc). | per-step four-render-path regression + in-game verify | pending |
| W4 | **Remaining families**, one per change, closing their symptom issues as they migrate; #660's issue index burns down. | each family's cells green | pending |
| W5 | **OOP completion**: ct_dev + cwv decomposition (last two god files), #727 logging sweep, doc reconciliation. | full QA green, per-mod module contracts documented | pending |

### W2 exact readiness (2026-08-06)

The deployed `0.1.495-dev` Old Musket pilot routes all 128 declared
surface-x-edge cells through one descriptor/reconciler contract. Eleven cells
apply and read back the authored custom presentation: owner 1P equip/customize,
owner 3P equip/customize, bot equip, remote husk equip/peer-ready, and
preview-open for inventory, illusion browser, lobby, and score/team. The other
117 cells are declared vanilla-safe fallbacks; they are enumerated, not fixed.

CIM currently shares `LootItemUnitPreviewer` with the illusion browser, but the
shared previewer instance has no empirical CIM marker. The pilot therefore
classifies that call as `illusion_browser`; `cim_preview` is not separately
classified or proven. Mission-transition and respawn cells also remain
unsupported until directly observed, even when equipment recreation may route
through the implemented equip edge.

Phase 3 merged in PR #1165 and is an ancestor of the exact source deployed as
CWV `0.1.495-dev`. The subsequent `0.1.496-dev` source change only extracts the
ordered skin registries; it does not change the descriptor, reconciler, Old
Musket adapters, or their implemented-cell set. The W2 gate remains open for
the pinned solo test followed by the remote-husk co-op matrix.

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
