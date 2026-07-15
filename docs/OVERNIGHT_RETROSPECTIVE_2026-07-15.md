# Overnight engineering retrospective - 2026-07-15

## Scope and evidence

This pass reviewed all 298 issues that were open after issue #625 was created.
The machine-readable row-by-row matrix is
`_investigating/open_issue_doctrine_2026-07-15.json`; the reproducible,
report-only collector is `tools/github/audit-open-issues.ps1`. Each row records
labels, doctrine findings, applicable lessons, risk tier, verification scope,
and a next action. Regex lesson matches are a review queue, not proof of a root
cause or completed fix.

Evidence also included current source, today's crash logs, the decompiled VT2
source references already captured in subsystem docs, the latest GitHub Actions
runs, and Git ancestry. No bulk issue state changes were made from heuristics.

## What today taught us

1. **A resident asset is not necessarily drawable.** Custom GUI materials must
   close over the exact renderer/Gui that performs the pass. The Athanor crash
   and the abandoned Options integration both reached native drawing with a
   material absent from that renderer. Bug class 47 now records the per-renderer
   proof-and-fallback rule.
2. **Appearance must be data, not per-screen behavior.** Inventory,
   customization, Athanor, lobby, score, owner, bot, and husk paths need one
   canonical presentation descriptor. `WEAPON_APPEARANCE_STANDARD.md` now makes
   this adapter boundary explicit; #420 remains the implementation umbrella.
3. **A custom unit is more than a mesh.** The Encarmine helmet showed that a
   visual clone can drop the donor's armature, state machine, dynamic feather
   joints, LOD behavior, fade shader, and camera-fade contract. Bug class 49
   requires a nonvisual contract inventory before import.
4. **PNG inspection is not compiled-asset QA.** Broad low-alpha pixels become
   translucent film, mips can change silhouettes, and diffuse brightness cannot
   substitute for the correct packed gloss/material channels. Bug class 50
   adds quantitative alpha, mip, luminance, and render-distance checks.
5. **Catalog keys are not product identities.** Raw ItemMasterList/provider
   aliases create duplicate craft rows. Family identity must be canonical and
   authored variants must remain distinct; display/localization text is never a
   key. This applies directly to #524 and future CWV consolidation/migration.
6. **Owner state and render state have different lifetimes.** UUID-backed
   customization/style state, wire-safe peer state, and spawned unit state need
   explicit boundaries and convergence. Initial join, map transition, wield,
   inventory preview, and score preview are independent consumers, as captured
   by bug classes 24, 27, 43, and 48.
7. **Native APIs fail below Lua.** `pcall` cannot make an invalid material,
   resource, node, world, or shading variation safe. Positive preflight plus a
   fail-closed substitute must happen before the native call.
8. **Reuse vanilla transactions when policy alone changes.** The physical forge
   should preserve its native callback/UI flow and only narrow the access
   predicate. Similar features should not duplicate backend or view-opening
   behavior.
9. **Dynamic mechanics require dynamic text.** Talent descriptions must switch
   with active rework toggles and restore exact vanilla strings when disabled.
   Popup bodies must not repeat their titles. This applies to #619 and #222.
10. **Parallel completion is not integration.** There are 114 local unmerged
    `agent/*` branches (43 currently visible on the remote). Issue #528 is the
    confirmed witness: cleanup commit `d95399a` is not an ancestor of master,
    and master still contains the retired Options hooks. Bug class 51 and #625
    define ancestry, patch-equivalence, ship-manifest, and disposition checks.

## Tracker audit

The 298 open issues have exactly one lifecycle label after the earlier
normalization pass:

| Lifecycle | Count | Next action |
|---|---:|---|
| `not-started` | 17 | source-backed scope, then implementation or diagnostics |
| `diagnostics-armed` | 62 | run the documented repro and collect bounded evidence |
| `verify-fix` | 145 | solo in-game verification |
| `verify-fix-coop` | 69 | two-player in-game verification |
| `Fixed` | 5 | post-fix hardening/test/docs, then close |

The five post-fix issues are #83, #304, #381, #402, and #438. They should not
remain open indefinitely: either complete the persistence-after-fix pass or
record why it is not applicable and close them.

Mechanical doctrine review found 136 issues whose current verify/diagnostic
state has no comment containing both a test method and expected result. Eight
tooling/documentation issues (#2, #302, #303, #317, #355, #540, #546, #558)
use a human in-game lifecycle even though tooling work should be verified and
closed by the maintainer workflow. Historical issue bodies also account for 150
titles over eight words, 100 heading-form bodies, and 77 bodies over 220 words.
These are cleanup debt, not reasons to rewrite empirical history in bulk.

The co-op detector intentionally treats the newest explicit test comment as
authoritative because older comments are often superseded. Remaining findings
must be inspected individually before changing labels; keyword evidence alone
does not authorize a label swap.

The risk heuristic classified 17 critical, 77 high, 141 moderate, and 63 low
rows. These tiers are triage hints. Existing repository priority labels and
fresh crash evidence remain authoritative.

## Applicability across open issues

The row-level JSON contains every issue. The highest-value cross-cutting groups
for engineering work are:

| Lesson | High-confidence affected issues | Existing owner |
|---|---|---|
| Renderer material closure | #155, #228, #481, #528, #612, #617, #618 | #420; bug classes 22, 23, 47 |
| Shared preview descriptor and render fanout | #149, #154, #203, #237, #392, #394, #396, #401, #419, #474, #478, #481, #482, #483, #513, #574, #579, #583, #599, #603, #604, #610, #612, #617 | #420/#504; bug classes 27, 43, 48 |
| Native preflight/custom asset contract | #228, #604, #612, #617 | #420; bug classes 22, 28, 35, 45, 47, 49, 50 |
| Canonical catalog and instance identity | #524, #582, #604, #618, #620 | #428/#504; bug classes 40, 43, 46 |
| Bounded transactions and lifecycle | #205, #524, #565, #573, #579, #583, #598, #602, #604, #609, #624 | #428/#504; bug classes 19, 24, 41, 43 |
| Backend/realm isolation | #573, #578, #607, #624 | #428; bug class 36 |
| Dynamic localization and popup contract | #222, #505, #557, #571, #578, #602, #605, #612, #619 | #504; localization standard |
| Integration and repository trust | #2, #498, #528, #540, #546, #558, #625 | #540/#546/#625; bug classes 10, 45, 51 |

This mapping is intentionally many-to-one. It prevents opening another narrow
architecture issue when #420, #428, #498, #504, #540, #546, or #625 already
owns the systemic work.

## Repository hardening performed

- Added bug classes 47-51 for renderer closure, shared presentation,
  behavioral custom-unit contracts, alpha/mip conversion, and stranded agent
  branches.
- Strengthened `WEAPON_APPEARANCE_STANDARD.md` with the canonical presentation
  descriptor and per-renderer material proof boundary.
- Extended the report-only issue audit locally with reproducible per-row risk,
  scope, next-action, umbrella, and doctrine fields; its self-test passes.
- Kept all changes outside active CWV, Cosmetics, WT, CIM, and Lua harness
  ownership paths.

## Repository health and tomorrow's order

GitHub CI is currently red. The latest observed run failed on five Lua tests,
generated-catalogue/file-size policy, fixture command false positives, and
current name-integrity errors. Concurrent root work is repairing the fixture
scanner and generated-catalogue exemption; CI must be green before branch
protection from #540 can be trusted.

Tomorrow's safest order is:

1. Finish and integrate the active crash/resource work, then verify the exact
   loaded versions from tester logs.
2. Integrate #528's cleanup from current source through QA; do not test the
   abandoned Options bridge merely because an old Workshop build contains it.
3. Verify CIM renderer-safe icon fallback and native forge work (#617/#618/#624).
4. Verify Encarmine structure/material behavior (#612): plume alpha/brightness,
   jiggle, camera fade, preview, owner, and remote views.
5. Verify CWV combat-style migration and peer convergence (#620), then the
   client crash families #586/#588/#604.
6. Implement/verify the shared preview adapter for #481/#420 rather than adding
   another surface-specific patch.
7. Complete dynamic talent descriptions and popup deduplication (#619/#222).
8. Drain the five `Fixed` issues through post-fix hardening and closure, then
   reconcile all 114 unmerged branches under #625.

Do not infer test readiness from a branch, source diff, compile, or agent
message. Canonical master ancestry, successful ship manifest, and the tester's
`[<mod>:LOAD]` banner are the truth chain.
