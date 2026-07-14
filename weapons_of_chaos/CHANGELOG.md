# Weapons of Chaos — Changelog

## 0.1.11-dev (2026-07-14) - #509 live wire-contract evidence [verify-fix] [not deployed]

### Why
The existing backfill could pass in retail without proving the registered Blightreaper was present or wire-safe. Its WOC substitution check accepted `nil` as success, the singleton check source-soft-skipped when `io` was unavailable, and the instruction to equip Blightreaper did not feed any assertion.

Source audit also clarified the two identity layers. Native `parse_item_master_list` stamps the base row with `key/name = es_1h_sword` (`item_master_list.lua:109-112`); MoreItemsLibrary preserves that inherited key on the actual backend item (`MoreItemsLibrary.lua:343-344`). Therefore today's Blightreaper already traverses `LoadoutUtils.sync_loadout_slot` as the boot-stable vanilla sword. The `woc_` substitution remains mandatory defense-in-depth for any future explicit WOC-keyed item.

### Changed
- Extracted pure `_woc_wire_policy.lua`: vanilla items pass by identity, explicit `woc_` items get a shallow `es_1h_sword` shadow, and an unresolvable base fails closed.
- Hardened `wire_woc_never_leaves_woc_key`: with the native base tables present, `nil` is now a failure and the exact outgoing key and `ItemId` must both equal `es_1h_sword`.
- Added `issue509_registered_blightreaper_wire_contract`: asserts the WOC master-list row, symmetric lookup pair, actual MIL backend item, inherited vanilla wire identity, and live traversal of WOC's sync hook after the exact backend item is equipped.
- The WOC runner now reports standards-compliant `SKIP` results. The live traversal check skips with an explicit instruction until Blightreaper is equipped; disabled-feature state also skips rather than generating a false failure.
- Added engine-free policy coverage in `test_woc_wire_policy.lua`.

### Test method
1. Enter the keep with More Items Library and WOC enabled; confirm `[WOC] v0.1.11-dev loaded`.
2. Equip Blightreaper once after entering the keep.
3. Run `/woc_regression_test`. Require `issue509_registered_blightreaper_wire_contract` PASS and zero failures; it must not be SKIP after the equip.
4. Unequip/re-equip a vanilla weapon and confirm ordinary loadout sync remains unchanged.

## 0.1.10-dev (2026-07-12) - #511 io-safe regression checks: source-reads no longer throw in the retail sandbox [untested]

### Why
`/woc_regression_test`'s two source-pattern checks (`issue422_wire_safety_unconditional_singleton`, `no_package_force_load`) read WOC's own source via `io.open` to verify a marker. The VMF retail Stingray VM registers no `io` library (mods are `loadstring`'d into the game's shared `_G`; the engine registers `os` but not `io`), so `io.open` threw `attempt to index global 'io' (a nil value)` and the runner's pcall reported both as FALSE FAILs on healthy code.

### What
- NEW `_rt_src_read(path)` helper (next to `_rt_register`): guards `rawget(_G,"io")` and returns nil when `io` is absent, so each check's existing "unreadable source => skip (PASS)" branch runs instead of throwing. Both `io.open` reads route through it.
- Both invariants are genuinely textual (hook-count singleton; absence of a `Managers.package:load` force-load) anchored on the file-local `_rt_register`, so in retail their source-text half is skipped; they still run under the modding-tools build / CI and are listed as repo QA-gate candidates (PROJECT_STANDARDS 2.2b tier a). No behavior change.

## 0.1.9-dev (2026-07-12) - issue 509: regression-harness backfill (wire-safety + force-load dead end) [untested]

### Why
Issue 509: `/woc_regression_test` locked only one invariant (`wire_woc_never_leaves_woc_key`). The ENGINE_SURFACE.md rows-of-concern - the unconditional sender-side wire-safety hook and the keep-entry package-force-load dead end - had no regression coverage.

### Changed
- `weapons_of_chaos.lua` - added three `_rt_register` checks beside `_wire_safe_item`:
  - `issue422_wire_safety_unconditional_singleton` - source-pattern: the `(LoadoutUtils, sync_loadout_slot)` hook is present exactly ONCE (VMF drops a 2nd silently) and the substitution keys off a plain `woc_` prefix, not a `mod:get` toggle. Locks "unconditional sender-side wire-safety" (issue 422 / issue 278).
  - `wire_non_woc_item_passthrough_identity` - runtime: `_wire_safe_item` returns a non-`woc_` item by identity, so wire safety never mutates vanilla loadout items.
  - `no_unit_path_package_force_load` - source-pattern: no `Managers.package:load` force-load call reappears (the keep-entry `resource_package()` C-fatal that bypasses pcall; DEVELOPMENT.md post-mortem).
- `MOD_VERSION` `0.1.8-dev` -> `0.1.9-dev`.

### Tests
Built via VMBLauncher (compile-only); lint clean. Not deployed/uploaded per task scope.

### To verify
- In-game (keep, Blightreaper equipped): run `/woc_regression_test`. Expect every line `PASS` and a `N passed, 0 failed` tail. `wire_non_woc_item_passthrough_identity` is the load-bearing runtime check; the two source-pattern checks soft-skip on a deployed install (source .lua not on disk).

### Refs
Issue 509 (parent), issue 422 / issue 278 (wire safety). Surface: `weapons_of_chaos/ENGINE_SURFACE.md`.

## 0.1.8-dev (2026-07-12) - issue 427: _dbg_alert routes to log-only printf (no chat spam)

### Why
Issue 427/240: `_dbg_alert` routed through `mod:warning`, which VMF `logging.lua` posts to in-game CHAT under default settings (warning mode >= 2). A "log-only" alert is one repro from spamming chat. (No live callsite in this file today, but the helper is the copied #427 class - migrate it before one lands.)

### Changed
- `weapons_of_chaos.lua` - `_dbg_alert` now routes through pcall-guarded engine `printf` (log-only, survives mod-logging-OFF), matching the enemy_tweaker v0.7.25-dev template (BUG_CLASSES section 17 Variant B). `_dbg` (mod:debug) unchanged.
- `MOD_VERSION` `0.1.7-dev` -> `0.1.8-dev`.

### Refs
Issue 427 (parent), 240 (originating fix). Check: `qa/check_logging.ps1` warn-chat.

## 0.1.7-dev (2026-07-07) — issue 422 hardening: fail-safe wire hook + regression + doctrine parity

### Why
Follow-up to the 0.1.6-dev wire-safety fix, from audit findings F2/F4/F6. The wire hook was correct on the happy path but structurally allowed a raw `woc_` key onto the wire if the base-index guard ever short-circuited, had no regression coverage, and lacked applied-marker/dev-banner doctrine parity.

### Changed
- `weapons_of_chaos.lua` — F2: the `LoadoutUtils.sync_loadout_slot` hook now routes through a new `_wire_safe_item(item)` helper. A `woc_` item whose base index (`BASE_WEAPON` / `NetworkLookup.item_names[BASE_WEAPON]`) can't be resolved now SKIPS the sync (fail-safe, mirrors CWV character_weapon_variants.lua:10183-10188) instead of falling through and emitting the raw `woc_` key — a raw `woc_` key is no longer structurally reachable on the wire. printf diagnostic on the skip path.
- `weapons_of_chaos.lua` — F6/§5.1a: added the `_rt_register` scaffold + `/woc_regression_test` command, with a `wire_woc_never_leaves_woc_key` check (asserts the hook target exists, a fake `woc_` item pushed through `_wire_safe_item` yields no `woc_` key/ItemId, and the live item is not mutated).
- `weapons_of_chaos.lua` — F6/§3.6: added the `_settings_fingerprint()` helper; the applied-marker line now carries `settings_fp=<hash>`; added the required `-dev` load chat banner (`mod:echo("[WOC] v<X> loaded")`).
- `weapons_of_chaos_data.lua` — F4: removed the stale comment claiming an `enable_debug_logging` checkbox "stays LAST" (the widget was removed in v0.1.2-dev).
- `PROJECT_STANDARDS.md` §3.6 — F4: dropped WOC from the "still expose the menu checkbox" migration list (WOC is fully VMF-native).
- `MOD_VERSION` `0.1.6-dev` -> `0.1.7-dev`.

### Notes
- Behavior-preserving: the F2 change only alters the currently-unreachable failure path (`es_1h_sword` is a universal boot index, so the guard passes in practice). Still needs the 0.1.6-dev 2-player verify. Not built, deployed, uploaded, or committed.

## 0.1.6-dev (2026-07-07) — issue 278/422: Blightreaper CTDs non-WOC peers on equip [verify-fix] [crash] [0-critical]

Found by the issue-371 cross-mod wire-safety audit. WOC cloned CWV's item registration
but not its net-safe loadout hook.

- SYMPTOM: equipping the Blightreaper crashes every lobby peer without WOC.
- ROOT CAUSE: WOC injects ITEM_KEY (woc_blightreaper) into NetworkLookup.item_names
  (weapons_of_chaos.lua:191). Equipping fires LoadoutUtils.sync_loadout_slot -> the RPC
  encodes item_id = item_names[item.key] onto rpc_sync_loadout_slot (both directions +
  hot_join_sync); a non-WOC peer lacks the appended index and cold-decodes it at
  loadout_utils.lua:72 -> strict __index fatal (network_lookup.lua:2362). Exact issue-278
  pattern.
- FIX: hook LoadoutUtils.sync_loadout_slot and substitute a shadow item keyed to the
  vanilla BASE_WEAPON (es_1h_sword, a boot-stable index every peer has) for any "woc_"
  key before the RPC encodes; local state untouched. Byte-identical to CWV's issue-278
  fix. No skin/rarity axis to fix (WOC applies no skin, rarity = "default").
- Needs a 2-player (WOC host + vanilla client) verify.

## 0.1.5-dev (2026-07-04) — Localization: applied dev status-tag doctrine (#301). Tagged the 1 option-title loc entry (Enable Blightreaper) with a dev status prefix: 1 [untested] (brand-new mod, placeholder base-sword mesh, unverified in-game). No open issues map to WOC. Tooltips, item name/description, and mod description left untagged per doctrine.

## 0.1.4-dev (2026-07-01) — Localization fixes: the Enable Blightreaper checkbox tooltip was double-localized (rendered wrapped in angle brackets); converted its widget field from an eager mod:localize() call to the raw loc key so VMF localizes it once. Rewrote every option description and tooltip (mod description, Blightreaper item description, Enable Blightreaper tooltip) into plain player-facing English, ASCII-only (dropped the non-ASCII spelling of Bogenhafen).

## 0.1.3-dev (2026-06-29) — Fixed keep-entry crash: the Bögenhafen trophy diorama prop (units/props/inn/hub_trophy/hub_trophy_bogenhafen) is NOT runtime-loadable (no standalone .package; absent from the boot-loaded bogenhafen DLC + base keep `inn` bundles), so force-loading its unit path hard-crashed on keep entry. Interim held mesh reverted to the base Empire 1H sword (HELD_UNIT, crash-free); swap to an extracted Blightreaper .unit once a real model is authored. Research + post-mortem in DEVELOPMENT.md.

## 0.1.2-dev (2026-06-28) — Removed per-mod debug toggle; diagnostics now route through VMF logging (mod:debug / mod:warning), gated by VMF output_mode_debug / output_mode_warning. (#169)

## 0.1.1-dev (2026-06-28) — Initial scaffolding: Blightreaper (Bögenhafen trophy diorama prop as 1H sword), equippable by all 20 careers, MoreItemsLibrary registration, 3P-unit derivation fix, inventory-preview fallback.
