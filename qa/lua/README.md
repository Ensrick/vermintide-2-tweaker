# Host Lua unit tests

This directory is the repository's fast, engine-free Lua unit sub-layer within
PROJECT_STANDARDS tier (a), not a fourth test tier. It runs under the vendored
PUC-Rio Lua 5.1.5 interpreter, requires no package manager or network access,
and is part of both Quick and full QA.

```powershell
pwsh -NoProfile -File qa/check_lua_unit_tests.ps1
pwsh -NoProfile -File qa/check_lua_unit_tests.ps1 -SelfTest
```

## Suite inventory (#1700)

The PowerShell gate independently discovers every top-level `tests/test_*.lua`
file and writes a small, temporary inventory outside the repository. The Lua
runner requires each discovered module to have actually loaded its registration
function, either from its explicit list or through a listed suite's transitive
`require`. Comments and strings naming a test file do not count. Unreached
files, malformed inventories and duplicate explicit registrations fail before
test execution. Run the PowerShell entry point rather than invoking `run.lua`
without its inventory.

`-SelfTest` proves both the original harness pass/planted-failure paths and the
actual directory-discovery/runner rejection of an unlisted fixture. It does not
replace a normal full-suite run. Every invocation removes its owned temporary
inventory in `finally`; it does not copy the repository or change source files.

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
- `suite_manifest.lua` and `tests/test_suite_manifest.lua`: actual import
  completeness, inventory validation, transitive imports and duplicate roots.
- `tests/test_crt_career_unlock.lua`: level-gate-only career unlock boundaries.
- `tests/test_ct_tab_collectibles_layout.lua`: native collectible row offsets.
- `tests/test_gt_regression_module.lua`: the original 88-registration extraction
  surface (verified against immutable baseline `5afeefef`), unique names and the
  bot update/aid ownership boundaries.
- `tests/test_gut_exclusive_radio.lua`: exclusive-choice layout and input routing.
- `tests/test_gut_selected_loadout_trace.lua`: trace deduplication and bounded state.
- `tests/test_woc_blightreaper_spirits.lua`: native spirit policy plus the current
  entry-to-spirit-owner dispatch, host-gated producers and package-acquisition
  boundary; inert diagnostic strings do not count as a live package load.
- `tests/test_wt_runtime_checks_module.lua`: current public/dev registration
  surfaces; `tests/test_wt_issue946_crowbill_picker.lua`: developer-picker coverage.
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
- `tests/test_gut_mod_tweaker_sound_parity.lua`: #1670 both shipped Mod
  Tweaker twins loaded whole against a PC-shaped world manager: the click and
  hover each twin hands its interaction layer fire on `MUSIC_WWISE_WORLD` on
  the Esc route (standalone view) and the `/mod_tweaker` route (keep
  sub-state) alike, fall back to a registered `music_world`, stay silent with
  no music world, and the real contracts module's
  `issue1670_command_route_sound_path` check passes with no log line of its
  own, skips outside the keep or before the view attaches, and fails on the
  0.2.358-dev lookup. printf,
  WwiseWorld and the worlds resolve through a test-local environment.
- `tests/test_gut_tab_talent_harness.lua`: #250 the shipped Hold-Tab provider
  loaded whole with the real talent refresh and policies:
  `issue250_deus_tab_talent_module_loaded` PASSes in a keep and a Chaos Wastes
  session (through 0.2.359-dev the `check and check.fn() or msg` tail turned
  the inner PASS into "missing"), `issue250_deus_tab_talent_tier_normalization`
  is reported once by its own name, a drifted talent policy fails both, and a
  missing module or check list fails loudly. get_mod, the panel class and
  Managers resolve through a test-local environment.
- `tests/test_gut_dialogue_contract_skip.lua`: #998 the real
  `_gut_dialogue_contract` module and the real Character Dialogue entry:
  `issue998_dialogue_staged_isolation` SKIPs by name with no Character
  Dialogue, with a v5 API (0.1.11-dev shape) or with no versioned API (through
  0.2.360-dev those were a bare PASS and a FAIL), FAILs a v6+ API that lacks the
  `isolation_setting` descriptor or `on_settings_batch_changed`, and PASSes the
  real entry without writing the owner. get_mod resolves through the dialogue
  fixture's test-local environment.
- `tests/test_gut_dx12_fence630_session_budget.lua`: #630 the real
  `_gut_dx12_fence630` probe: after eight healthy Mod Tweaker opens a ninth
  (decisive) session still logs its enter, frame evidence and exit summary
  (through 0.2.361-dev one 48-line run-wide budget dropped them), a frozen
  session keeps its last `frame_evidence`, the exit summary and the reenter
  anomaly are reserved past a spent budget and name the suppressed count,
  output stays at most line_cap + 1 per session with nothing on steady frames,
  an enter/leave loop stops at the run backstop with one `run_cap` line,
  and the contracts module's `issue630_dx12_fence_session_budget` check is
  registered, PASSes, and FAILs on a run-wide budget. emit is a test-local
  ledger; get_mod resolves through a test-local environment.
- `tests/test_gut_dropdown_arrow_glow.lua`: #92 the shipped `create_dropdown`
  and its `DD_*` constants lifted out of the definitions file and driven through
  the real `mod_tweaker_dropdown_arrow_glow` check: the shipped widget passes,
  matches native 31x28 glow / 31x15 base geometry, and a sprite swap, a 31x15
  glow or a glow that no longer shifts on open each fail the check.
- `tests/test_cwv_dual_axes_husk_hands.lua`: #579 per-hand husk write for a
  generated Dual Axes pair through the real peer gate, lifecycle ledger and
  husk re-key: the bare peer_id owner collapses the offhand, the RemotePlayer
  shape keeps both hands, and the shipped check builds that shape.
- `tests/test_cwv_careers_publication.lua`: #1660 the installed registration
  owner's `build_entry` publishes a private `can_wield` copy per row, so a
  sibling mod's in-place append or removal on one published row reaches
  neither the sibling row nor the catalog's shared careers array.
- `tests/test_wt_history_source_anchor.lua`: #1682 weapon-history anchor
  coherence: the canonical anchor is the Game Version 6.13.0 same-commit tip,
  all 13 catalogs and the completeness ledger in both Weapon Tweaker streams
  carry its revision and `Current (Game Version 6.13.0)` label, the Patch 5.2
  rehydrated evidence projects onto it, and no provenance input keeps a
  retired 6.12.0 or 6.12.1 anchor.
- `tests/test_woc_ui_icons.lua`: #1687 every atlas icon WOC hands to the UI
  resolves in the Game Version 6.13.0 atlas (test-local
  `has_atlas_settings_by_texture_name` seam): the Poisoned Edge constant is no
  longer the removed 6.12.1 key, a kept stale row is repaired to the current
  constant (to vanilla's `icons_placeholder` when the helper is unusable),
  atlas drift falls back and fails the audit, a placeholder shown while the
  preferred icon is resident fails the audit, the audit covers both traits and
  the Athanor fallback item icon, a missing helper fails closed, every
  trait-row install routes through the guard, and the registered
  `issue655_blightreaper_trait_contract` closure runs in a test-local
  environment and returns the icon audit failure.
- `tests/test_crt_buff_icons.lua`: #1686 every icon crt hands to the HUD
  resolves in the Game Version 6.13.0 atlas (test-local
  `has_atlas_settings_by_texture_name` seam): no crt module sets an icon
  literal outside the 6.13.0 atlas (the two removed 6.12.1 keys fail it), the
  Dance of Blades and Unchained buffs carry `maidenguard_4_2` and
  `unchained_6_1`, the guard drops only unproven buff icons and fails closed
  without the helper, the apply sweep touches only crt-registered names,
  Leading Shots keeps the vanilla talent icon on a miss and preserves exact
  parent global/package state on success and a throwing perk lookup through a
  private environment (no global monkeypatch), the audit fails on
  constant, factory and live drift, every registration routes through the
  guard, the guard log dedupes drops and prints one summary per sweep site
  (test-local logger seam), and the registered `issue1686_buff_icons_in_atlas`
  closure runs in a test-local environment and fails on a live stale icon. An
  optional case cross-checks the fixture against a local decompiled atlas.
- `tests/test_mp_hook_targets_resolve.lua`: #1671 no mp source file hooks
  the game-6.12-removed `IngameUI.not_in_modded` (or its `can_open_loot`
  successor), the shipped `_mp_hook_targets.TARGETS` inventory equals every
  literal `mod:hook("Class", "method")` site in every mp file reachable
  from the entry, and the `/mp_regression_test` census fails on a missing or
  retired method and on a class that is not loaded (past VMF's delay window
  that hook was refused). The class lookup and log seams are test-local.
- `tests/test_et_issue324_capacity_authority.lua`: #324 a characterization of
  the unchanged boot-shaped registrar refusal (`damage_source_cap_unavailable`
  with NetworkConstants absent and no `Network.type_info` capacity; passes on
  the base too), the read-only `capacity_verdicts` seam, and the bounded
  capacity-authority probe: load and one-shot network samples, the per-phase
  and row bounds, thrown, userdata and `__index`-only reader shapes, the
  literal `[et:324] cap-probe %s` printf route, the in-game check (registered
  before the load sample, network rows required once the authority exists),
  and its single load owner. The probe reads an injected globals table and
  emits through a test-local seam; the route case runs the chunk in a
  test-local environment.
- `tests/test_dcp_portrait_settings_owner.lua`: #509 the production DCP
  portrait-settings owner: exact capture (nil included), repeat-apply
  preservation and its no-write per-frame fast path, cross-career rejection,
  rollback and retained recovery ownership for throwing or silently ignored
  writes, and the named `career_settings_swap_saves_and_restores` body
  (`check_transaction`) passing on a healthy live row while failing on a
  read-only row, a foreign held row, a leaked HUD or hero-select capture, or an unowned DCP
  portrait on the row; `vanilla_portrait` never depends on an apply. The entry
  file's check, sync, restore and unload paths are pinned to the owner.
- `tests/test_dcp_entry_portrait_flow.lua`: #509 runs the real DCP entry chunk
  in a test-local environment with engine stubs: a remote Mercenary's tracked
  portrait on the score screen while the local Mercenary is untracked (the
  0.1.30-dev review regression), untracked remote rows staying vanilla on the
  score screen, Tab list and HUD frames in both local states, hat removal and
  `on_unload` restoring the vanilla pair through the live wrappers, and the
  named `career_settings_swap_saves_and_restores` and
  `score_rows_resolve_without_local_swap_509` checks passing, failing on an
  unowned DCP portrait, and reporting a missing live half as `SKIP` with a
  separate skipped total rather than counting it as `PASS`.
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
