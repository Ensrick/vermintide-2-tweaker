# Host Lua unit tests

This directory is the repository's fast, engine-free Lua unit sub-layer within
PROJECT_STANDARDS tier (a), not a fourth test tier. It runs under the vendored
PUC-Rio Lua 5.1.5 interpreter, requires no package manager or network access,
and is part of both Quick and full QA.

```powershell
pwsh -NoProfile -File qa/check_lua_unit_tests.ps1
pwsh -NoProfile -File qa/check_lua_unit_tests.ps1 -SelfTest
```

## Tier boundary

- Put deterministic transformations here when they run on ordinary Lua values
  and need no live VMF, Stingray, backend, network, or player state.
- A narrow global seam such as `Localize` may be supplied by one test when that
  is the function's complete engine boundary. Do not grow a general VMF mock.
- Keep hook registration, RPC behavior, engine object lifetime, and multiplayer
  behavior in the in-game regression-command tier.
- Keep source spelling and singleton-registration contracts in
  `check_rt_textual_invariants.ps1`.
- Keep repository metadata and cross-file policy in the PowerShell QA checks.

Optional local provenance fixtures, such as a sibling checkout of the
decompiled vanilla source, must be registered with `H.test_if`. A missing
fixture is reported as an explicit skip so a clean clone remains reproducible.
Optional checks may strengthen source provenance only: every production
behavior still needs a deterministic repository-owned test or regression
sentinel that runs in CI.

The first suite exercises the existing Bestiary & Armory attack-label helper:
stable sorting/filtering is fully pure, while ranged-label lookup uses only a
single test-local `Localize` seam. Tests load the production module directly;
there is no copied implementation.

## Layout

- `run.lua`: explicit suite manifest and process entry point.
- `harness.lua`: dependency-free assertions and reporting.
- `tests/test_attack_labeler.lua`: production-helper coverage.
- `tests/test_mod_tweaker_search.lua`: #559 search expansion snapshot/restore/dismissal coverage,
  including last-changed preference and top-result fallback.
- `tests/test_peer_parity_transition.lua`: shared legacy-payload compatibility,
  exact challenge/epoch/replay rejection, and bounded-envelope coverage.
- `tests/test_shared_wire_catalog.lua`: deterministic namespaced catalog identity,
  numeric drift sensitivity, malformed lookup rejection, and payload-size coverage.
- `tests/test_crt_wire_contract.lua`: CRT schema-3 integration plus the independent
  sender, hot-join, receiver, and timed-buff safety floors.
- `tests/test_gut_loadout_paging.lua`: #231 page/slot bijection, strip geometry,
  text Roman numerals and the modded-STORE-Adventure paging predicate.
- `tests/test_gut_bot_loadout_snapshot.lua`: #954 detached bot owner through
  its captured hooks: native-only (modded) career import, late designation
  retry, seed-seam preference, career bounds and drift repair, with printf
  resolved through a test-local environment (the global is never swapped).
- `tests/test_gut_loc_format.lua`: #1651 pure loc format scan: the 0.2.355-dev
  formatter probe reproduced on the live paged label (plain and hooked shape),
  accept/reject tables, the shipped loc table scanned clean, and the live check
  pinned to the pure scan. The formatter shadow counts calls; the global is
  never swapped.
- `tests/test_gut_mod_tweaker_keep_routing.lua`: #1652 the shipped Mod Tweaker
  transition closure and `/gut_regression_test` runner lifted out of the entry
  file: the old keep probe reproduces the live alert and missing fade, both
  routing policies route as designed, the contracts module returns nil, `skip:`
  or the loud mismatch messages, and the runner counts SKIP apart from PASS
  and FAIL with printf resolved through a test-local environment.
- `tests/test_cwv_dual_axes_husk_hands.lua`: #579 per-hand husk write for a
  generated Dual Axes pair through the real peer gate, lifecycle ledger and
  husk re-key: the bare peer_id owner collapses the offhand, the RemotePlayer
  shape keeps both hands, and the shipped check builds that shape.
- `tests/test_cwv_careers_publication.lua`: #1660 the installed registration
  owner's `build_entry` publishes a private `can_wield` copy per row, so a
  sibling mod's in-place append or removal on one published row reaches
  neither the sibling row nor the catalog's shared careers array.
- `fixtures/vanilla_weapon_master_list.lua`: GENERATED vanilla weapon census
  (every `ItemMasterList` melee/ranged entry with its `can_wield` list after the
  DLC `UpdateItemMasterList` patches, each hero career's
  `item_slot_types_by_slot_name` weapon rows, and the demo starting-gear
  seeds). Regenerate from the decompiled source with
  `py -3 qa/lua/fixtures/gen_vanilla_weapon_master_list.py <decompile_root> qa/lua/fixtures/vanilla_weapon_master_list.lua`
  and commit the result; never hand-edit it. Used by
  `tests/test_gut_spawn_weapon_policy.lua` (#1637).
- `vendor/lua-5.1.5-win64/`: pinned Windows interpreter and provenance.

Add a test file to the manifest in `run.lua`. The explicit list keeps ordering
deterministic and makes every new suite visible in review.

## Dependency on issue #543

Issue #544 is based on commit `04de8ba` from `agent/source-provenance` so the
new source-provenance QA wiring remains in `run_all.ps1`. The Lua test layer has
no runtime dependency on the decompiled source manifest, but this branch must be
merged after #543 (or rebased once #543 lands) because its QA wiring is additive
to that commit.
