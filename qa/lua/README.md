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
- `vendor/lua-5.1.5-win64/`: pinned Windows interpreter and provenance.

Add a test file to the manifest in `run.lua`. The explicit list keeps ordering
deterministic and makes every new suite visible in review.

## Dependency on issue #543

Issue #544 is based on commit `04de8ba` from `agent/source-provenance` so the
new source-provenance QA wiring remains in `run_all.ps1`. The Lua test layer has
no runtime dependency on the decompiled source manifest, but this branch must be
merged after #543 (or rebased once #543 lands) because its QA wiring is additive
to that commit.
