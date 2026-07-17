# Dev -> stable promotion process

How a change moves from a `*_dev` friends-only Workshop item to its stable
sibling, safely and traceably. Stable-item visibility is read from its current
`itemV2.cfg`; "stable" does not mean "public." This exists because the recurring failure mode is a
**fix rotting in dev and never reaching public users** (issue #278: the cim
crafted-CWV CTD fix sat in `cim_dev` v0.8.51 while public `cim` v0.8.33 kept crashing
real players for weeks). This process makes "what's fixed in dev but not stable"
visible and makes the port mechanical and verified.

Applies to the five split mods: `chaos_wastes_tweaker` (ct), `crafting_in_modded`
(cim), `general_tweaker` (gt), `gui_tweaker` (gut), `verminious_dreams_lighting` (vdl).
Everything else is single-stream (see CLAUDE.md "Dev/stable split workflow").

---

## The one rule that prevents the #278 class

**When you promote a crash/critical fix to stable, cite its issue number in the
stable CHANGELOG entry** (e.g. "issue 278" or "#278"). That single habit makes the
tracking exact — `promotion-status.ps1` can then confirm the fix reached stable, and
will stop flagging it. Tag the fix `[crash]` / `[0-critical]` in the **dev** CHANGELOG
header so the tracker knows it is promotion-critical in the first place.

---

## Tracking: `tools/promote/promotion-status.ps1`

Read-only. Run it **before every stable ship** and in CI. For each split pair it prints:

- **stable vs dev MOD_VERSION**, and how many source files stable trails dev in
  (id-normalized diff — the magnitude of the gap).
- **crash/critical fixes flagged for review**: issue numbers taken from dev CHANGELOG
  *headers* tagged `[crash]`/`0-critical` that are **not cited in the stable CHANGELOG**.
  These are the "did this reach stable?" cases. Confirm each.

```powershell
pwsh tools/promote/promotion-status.ps1              # all split mods
pwsh tools/promote/promotion-status.ps1 -Mod crafting_in_modded -Detailed
pwsh tools/promote/promotion-status.ps1 -Strict      # exit 1 on backlog (CI gate)
```

Older stable CHANGELOGs are summary rollups that don't enumerate issues, so historical
fixes may show as "review" until their entries are back-filled or superseded — that is
expected. Going forward, the citation habit above keeps it exact.

---

## Two promotion modes

Promotion is **selective by default**. Never blind-copy the whole dev tree to stable —
that can dump unverified in-flight work on subscribers (the ~80-cim-subscriber loss,
May 2026). Pick the mode that fits.

### Mode A - Cherry-pick hotfix (the common case)

A single fix (usually a crash) needs to reach stable without dragging the rest of the
in-flight dev line. **Fix it in BOTH dev and stable in the same session**, applying the
same targeted diff to each. This is inherently reviewed (you write the change twice, or
copy the one hunk) and never promotes anything else.

1. Implement + bump + CHANGELOG + regression-test in `*_dev/` (dev ships first, no-ask).
2. Apply the **same hunk** to the stable dir; bump stable to the user-named clean version
   (strip `-dev`); write the stable CHANGELOG entry **citing the issue number**; keep the
   dev-only scaffolding out (always-on diagnostics and dev-only files). Lifecycle
   tags are forbidden in both source streams before promotion (#694).
3. `promotion-status.ps1 -Mod <stable>` -> the issue should now show OK (cited).
4. A clean stable upload needs a **fresh, per-build ship signal from the user naming the version**
   (treated like `git push --force`). Then `ship.ps1 -Mod <stable>`, adding
   `-AllowPublic` iff the stable cfg is public; commit + push.

Worked example this session: cim v0.8.34 (public) + cim_dev v0.8.54-dev (issue #278).

### Mode B - Full rollup (only when the whole dev line is release-ready)

The user has signed off that everything in dev is ready for a stable-stream release.
Port the whole dev source with `tools/promote/promote.ps1` (DryRun by default),
then set the user-named version and update the stable CHANGELOG. Shipping approval
follows the MOD_VERSION suffix rule below.

```powershell
pwsh tools/promote/promote.ps1 -Mod crafting_in_modded            # DryRun: shows the plan
pwsh tools/promote/promote.ps1 -Mod crafting_in_modded -Apply -Version 0.9.0
```

`promote.ps1` does the id-normalizing port (dev dir/id -> stable dir/id), preserves the
stable `itemV2.cfg` identity (`published_id`, `visibility` — NEVER copies the dev
`published_id`; the upload gate aborts on collision), sets the version, and verifies the
result is grep-clean of dev identity. It does **not** ship — run `ship.ps1` after
the suffix rule authorizes it. See the script header for the full contract and the bundle-count gotcha
(dev builds 4 bundles, stable 3 — an orphaned dev render_config bundle; not missing
content). Reference: memory `reference_cim_dev_to_stable_promotion`.

---

## Invariants (do not violate)

- **Edits happen in `*_dev/` only** (CLAUDE.md NON-NEGOTIABLE #3). Stable is written **only**
  by a promotion. Never edit stable "for consistency."
- **MOD_VERSION decides upload approval.** A clean version needs a fresh
  per-build ship signal naming the version; an earlier "ship it" does not carry
  forward. A user-chosen `-alpha`/`-beta`/`-rc<N>` version ships the full
  pipeline without another prompt, even when the cfg is public. `-AllowPublic`
  is a mechanical visibility gate, never an approval signal.
- **Preserve stable identity**: `published_id`, `visibility` in the stable `itemV2.cfg`
  are user-dictated and never inferred from version/dir/stream.
- **Cross-mod `get_mod(...)` refs target STABLE ids** (`cim`, `gt`, ...), never `*_dev`.
- **Keep dev-only artifacts out on promotion**: always-on diagnostics (inert in stable)
  and dev-only files (e.g. `_diag_probe.lua`). Player-facing lifecycle/status tags
  are already forbidden in every stream by `qa/check_loc_tags.ps1` (#694).
- **The promotion RED GATE enforces the checklist** (issue #327): `ship.ps1` runs
  `qa/check_promotion.ps1` BLOCKING for the five stable split dirs — hard fail on
  (a) any forbidden lifecycle/status tag in the stable localization (defense in depth), (b) a pre-release
  suffix on the stable MOD_VERSION (override with `VT2_SUFFIX_OK=1` when the USER
  named a suffixed stable version, issue #328 ruling), (c) MOD_VERSION not equal
  to the top stable CHANGELOG entry, or that entry not increasing over the previous
  one. Self-test: `qa/check_promotion.ps1 -SelfTest` (9 cases, pwsh 7 + PS 5.1).
- **Verify the ship**: `workshop_log.txt` must show `Uploaded new content`; `ship.ps1`
  hash-verifies the deploy. `ugc_tool` prints success even on failure.
