# Crafting in Modded: scoped official promotion review

## Scope

This snapshot covers the official 0.8.149 promotion for #1530 and #1694.
It is not an exhaustive audit of the mod or evidence of in-game acceptance.
The prior official baseline is 0.8.148; no Community Builds, unrelated Dev
features, new backend operations or hook registrations are promoted here.

## Boundaries reviewed

- Mod Tweaker owns the Base Power control's 25-point stepping. CIM's existing
  `_cim_base_power` remains a range clamp, preserving off-grid values; the
  promotion corrects text rather than adding craft-time quantization.
- The Forge-open diagnostic uses the existing entry-owned native-first realm
  predicate. It does not infer current realm from the retired EAC flag or write
  realm, backend or user-setting state. Inventory diagnostics retain that same
  owner. The callback stays in its existing consolidated dispatch.
- The named wording check uses the official runner registrar and official
  localization module. Missing dependencies or a throwing reader must not be
  reported as success. It reads live values without temporary setting writes.
- Consecutive canonical clean builds produced three then four bundles solely
  because the known SDK tool-only sidecar appeared intermittently. Official
  CIM now adopts the same exact-name/SHA exclusion as its Dev stream. The
  deletion has an explicit retirement trailer; active/common bundles remain.
  No launcher, uploader or normalization implementation is changed.

## Verification and remaining risk

The official-source rollup executes the existing real Forge diagnostic fixture
through its namespace adapter; production bytes are not rewritten or replaced
with Dev code. Slider coverage selects both actual stream localizations. The
named wording check is exercised with missing and adversarial dependencies.

Canonical BuildOnly, hosted QA and authenticated Workshop transfer are separate
release gates. They do not establish physical Forge interaction or rendered
tooltip behavior. Those remain solo in-game checks on the exact official build
after publication; no gameplay pass is claimed by this review.
