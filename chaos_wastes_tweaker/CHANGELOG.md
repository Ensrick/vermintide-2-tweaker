# Chaos Wastes Tweaker Changelog

## 0.7.132-beta (2026-09-03) — exact public boon/miracle wire parity (#426) [untested] [crash] [0-critical]

- Freezes the existing public catalog at exactly 29 bidirectional
  `NetworkLookup` rows (10 power-ups and 19 buff templates) in its observed
  registration order. The reservation, composite identity, integrity snapshot,
  peer-parity owner, receiver floors, and hook publication commit as one
  fail-closed transaction; partial or malformed state cannot publish a usable
  catalog.
- CT-owned boons and miracles remain inert until every live human peer proves
  the same exact catalog. Writers, shop/grant/buff receivers, host relays,
  SharedState replay, active buffs, and hot-join admission all enforce that
  boundary; parity loss strips synchronized CT state transactionally before
  native numeric decode, and terminal admission failure rejects the joining
  peer instead of exposing mismatched ids.
- Vanilla and foreign rows pass through unchanged, including Pusfume-owned
  state. The public catalog deliberately excludes the two Dev-only power-ups
  and their two buff rows, so this promotion does not import Dev-only content.
- VT2-Bundle-Retirement: `e7852992f40eb619.mod_bundle`

## 0.7.131-beta (2026-07-07) — HOTFIX: promote issue 406 client heal-crash gate [verify-fix] [crash] [0-critical]

Mode-A cherry-pick promotion (docs/PROMOTION_PROCESS.md) of the issue 406 fix from
ct_dev v0.7.202-dev. ONLY this gate; no other dev work included.

- SYMPTOM (issue 406): a ct CLIENT (non-host) who takes the "kill heal" boon
  (ct_kill_heal) hard-crashes on their next kill: `DamageUtils.heal_network` fasserts
  "Only server can heal" (damage_utils.lua:2636). on_kill procs run on the killer's
  LOCAL machine, so a client fires the server-only heal.
- ROOT CAUSE: `ct_kill_heal_on_kill` (chaos_wastes_tweaker.lua:10781) called
  `heal_network` with no server gate. BUG_CLASSES class 29 (sibling of crt issue 405).
- FIX: gate the proc on `Managers.player.is_server` (vanilla pattern,
  buff_templates.lua:325/:404) - the client instance no-ops; the host's instance of the
  synced buff grants the heal, so no heal is lost.
- Needs an in-game verify: a ct CLIENT takes the boon and kills something without crashing.

## 0.7.130-beta (2026-07-03) — Full promotion: stable brought to parity with ct_dev 0.7.211-dev

Wholesale promotion of all `chaos_wastes_tweaker_dev` work through **0.7.211-dev** into the public stable mod (previously cherry-picked one fix at a time; this catches stable up in one pass). Source mirrored with the `ct_dev`→`ct` / `chaos_wastes_tweaker_dev`→`chaos_wastes_tweaker` rename, the dev-only `[untested]`/`[confirmed working]` menu labels stripped (stable carries none), and version normalized to the stable `-beta` line. Committed only — **no Workshop upload** in this change. Per-fix detail lives in the dev CHANGELOG (0.7.140-dev … 0.7.211-dev); the notable user-facing items:

**Crash / stability fixes**
- Host crash from the settings-sync flood on the Apply-button burst — paced + debounced re-sync (#205, dev .191/.192).
- Host crash on client hot-join from the chunked graph-sync flooding the reliable send queue — paced send-queue (#97, dev .163).
- Mathlann's Storm-Strike AoE capped at 40 targets to stop the reliable-send-queue overflow (#129, dev .172).
- Client rendering injected adventure maps as shrines / losing curse lighting (#68, dev .144).
- CW round-end RPC overflow no longer freezes the next expedition (dev .155); CW pickup transforms no longer leak into real Adventure (dev .154).

**Altars & Chests of Trials**
- Multi-use (reusable) upgrade/swap/boon altars: re-armed altars stay lit/available and only show the looted mesh after the FINAL use (dev .151/.158/.166), collapse-animation fix (#103, dev .193).
- **#102: multi-use temper altar no longer escalates the upgrade to exotic/unique on reuse** — reward rarity decoupled from the keep-lit visual (dev .211).
- Chest of Trials: pay-with-coin schedule, no-repeat boon offerings, uniqueness across consecutive chests (#117), optional revive on completion (#116) (dev .147/.177).

**Boons & curses**
- Disabled boons no longer leak through at grant (#211, dev .159/.200); boon-offer scrollbar + boon-count caps raised to 50 (dev .199).
- Miracle of Isha (Aegis / Unlimited Wounds) now lasts the next mission only (dev .153).
- **Curse lighting: Be'lakor darkness on already-dark interior maps eased + a live "Curse Lighting Brightness" knob** to self-tune the injected-map curse atmosphere (#243, dev .209/.210).
- Bomb-boon balance: Endless-Bombs-consumes-Morgrim's redone to strip on potion expiry (#101), cooldown fixes (#120, dev .178/.180/.181).

**Features & menu**
- Finale God is now a named dropdown instead of a numeric slider (dev .206).
- Pilgrim's-coin starting value settable to an exact figure again (#164, dev .207); guaranteed coin spawns under the Abundance-of-Life curse (dev .165).
- Both voters' map-vote chips render for duplicate careers on the CW map screen (#122, dev .160–.162/.194).
- Skull-stun slider, Adventure RNG-trait odds, Blessed Bots survival boons (dev .140).
- Large settings-menu reorganization: Shrines/Altars/Chests grouping, Disabled Curses god-prefixed + alphabetized, tooltip sweeps so descriptions don't restate the title (#222, dev .190–.208), plus a localization reorder/cleanup (#220, dev .201/.205).
- Traits: #118/#119 trait-gate corrections (dev .177/.178).

**Diagnostics** (route through VMF debug logging — silent unless the user enables it): #144 boon-list trace, #156/#104 spawn-census + gas-cloud guard, #60 baked-spawner cursed-chest cap.

Some of the most recent items (#102 altar decouple, #243 curse brightness) are shipped-but-not-yet-user-verified in-engine; they carry no menu label in stable.

## 0.7.129-beta — 2026-06-28
- Removed per-mod debug toggle; diagnostics now route through VMF logging (mod:debug / mod:warning), gated by VMF output_mode_debug / output_mode_warning. (#169)

## 0.7.128-beta (2026-06-16) — Curse-banner crash fix reworked to a data backfill (kills the "trying to hook object that doesn't exist: DeusCurseUI" error)

Cherry-picked from `ct_dev` v0.7.139-dev.

### Why
The v0.7.126-beta curse-crash fix hooked `DeusCurseUI._update_description_widget`, but that class lives in `scripts/ui/hud_ui/` and only loads inside an actual CW expedition — so at the adventure keep VMF couldn't resolve it, logged a visible **`(hook): trying to hook object that doesn't exist: DeusCurseUI`** error, and the hook likely never installed.

### Changed
- `chaos_wastes_tweaker.lua` — removed the `DeusCurseUI` hook + `mod._ct_curse_desc_color_or_default`; replaced with a load-time backfill of `DeusThemeSettings.<theme>.curse_description_color` (only `wastes` lacks it). Reliable at mod-load (DeusThemeSettings is a boot-global), covers both UI callers, consistent host↔client, no hook → no error. `CURSE_THEME_COLOR_BACKFILL_MARKER`.

### Tests
- Replaced `curse_ui_nil_color_fallback` with `curse_theme_color_backfilled`.

## 0.7.127-beta (2026-06-16) — Trollhammer properties, fire-weapon traits, mid-run boon-count sync, bot-boon chat readout

Cherry-picked from `ct_dev` v0.7.138-dev — four fixes reported 2026-06-17 in live play.

### Why
1. **Trollhammer Torpedo gets traits but no properties on CW upgrade** — vanilla gap: its `property_table_name = "deus_trollhammer_torpedo"` exists only in the trait combinations table, never the property table, so the upgrade's property lookup returns nil.
2. **Fire/heat weapons (Sienna staves, Bardin drakefire pistols / drakegun / flamethrower) get no trait on upgrade** with the trait reworks on — their narrow `deus_ranged_heat` pool has no common-tier trait, so the tier filter returned zero combos at low rarity and the weapon kept vanilla's nil traits. Melee/ranged-ammo weapons carry common-tier traits, hence the asymmetry.
3. **Host changing boons-per-chest/shrine (or any synced setting) mid-run didn't reach clients** for the rest of the run — the chunked settings broadcast fired only at `setup_run` (once per run); `on_setting_changed` never re-broadcast.
4. **No host-visible readout of which boons bots receive** when random/mirror bot boons are on.

### Changed
- **Trollhammer** — at load, alias `WeaponProperties.combinations.deus_trollhammer_torpedo = WeaponProperties.combinations.deus_ranged` (guarded `rawget` + key-exists; idempotent; safe reference-alias). No new hook. `TROLLHAMMER_PROPERTY_ALIAS_MARKER`.
- **Fire-weapon traits** — `get_tier_filtered_combos` falls back to the weapon's OWN baked pool when no tier-eligible combo exists, so restricted-pool weapons draw a trait **only from their own compatible pool**, never a generic one. Behavior-preserving for melee/ranged-ammo (`#filtered` never 0). No new hook. `FIRE_WEAPON_TIER_FALLBACK_MARKER`.
- **Mid-run sync** — extracted the host broadcast into `mod._ct_broadcast_host_settings(reason)` (reuses the existing `ct_sync_host_settings_chunk` RPC + `CT_RPC_SCHEMA`); `setup_run` and `on_setting_changed` (host + synced-setting gated via `mod._ct_synced_set`) both call it, so a mid-run host edit re-syncs immediately. `MIDRUN_SETTING_REBROADCAST_MARKER`.
- **Bot-boon chat readout** — new host-only `announce_bot_boons` checkbox (default off); the existing `add_power_ups` bot loop emits a local `mod:echo` per (bot, boon). No new hook; `mod:echo` is local-only (no RPC/version-sync risk).

### Tests
- New `/ct_regression_test` checks: `trollhammer_property_pool_aliased`, `fire_weapon_tier_fallback_nonempty`, `midrun_setting_rebroadcast_wired`, `bot_boon_announce_wired`.

## 0.7.126-beta (2026-06-16) — HOTFIX: deus curse-banner crash on suppressed-curse nodes (theme="wastes" has no curse color)

### Why
Reported crash 2026-06-17 (client joining a CW run): `deus_curse_ui_definitions.lua:599: attempt to index field 'color' (a nil value)` on Citadel of Eternity (`sig_citadel_khorne_path5`), `theme="wastes"`, `curse="curse_corrupted_flesh"`, `theme_color=nil`. `DeusCurseUI.show_curse_info` reads `DeusThemeSettings[theme].curse_description_color` (nil only for the `wastes` theme — all god themes have it) and passes it into the glow `style.color` tables that the curse-banner animation then indexes. ct forces `node.theme="wastes"` to suppress curse aesthetics, creating a theme="wastes" + real-curse combo vanilla never makes → nil color → crash. Cherry-picked from `ct_dev` v0.7.137-dev (only this crash fix).

### Changed
- `chaos_wastes_tweaker.lua` — new `DeusCurseUI._update_description_widget` hook (0 prior `DeusCurseUI` hooks) substituting a default opaque-white color when `color` is nil (`mod._ct_curse_desc_color_or_default`); downstream of all theme/curse mutation, suppression unaffected, themed colors pass through.

### Tests
- New `/ct_regression_test` check `curse_ui_nil_color_fallback`.

## 0.7.125-beta (2026-06-16) — HOTFIX: host-crash on CW path missions with no deus_weapon_chest_distribution (e.g. cemetery_tzeentch_path1)

### Why
Reported crash 2026-06-16 (hosting): `deus_run_controller.lua:2468: No deus_weapon_chest_distribution set for cemetery_tzeentch_path1` — a **fatal host crash** that ends the run for everyone. Vanilla `DeusRunController.get_deus_weapon_chest_type` reads `LevelSettings[level_key].deus_weapon_chest_distribution`, `assert`s if it is nil, and **rebuilds from that table whenever the distribution is exhausted**. The native Beastmen/Tzeentch CW path variants (`cemetery_tzeentch_path1` and siblings) ship with **no** distribution, so the host dies the moment a deus weapon chest spawns. Same class as Issues #58/#60/#68 (CW path missions missing pickup/chest config), but fatal. This is a **cherry-picked hotfix** from `ct_dev` v0.7.136-dev — only the crash fix, none of the other in-flight dev work.

### Changed
- `chaos_wastes_tweaker.lua` — extended the **existing** `DeusRunController.get_deus_weapon_chest_type` hook (no new hook) with `mod._ct_ensure_deus_chest_distribution(self)`: resolves the current `level_key` as vanilla does and, **only if** `LevelSettings[level_key].deus_weapon_chest_distribution` is nil, injects a balanced fallback (`{ [upgrade]=1, [swap_melee]=1, [swap_ranged]=1, [power_up]=1 }`) **into `LevelSettings[level_key]`** so vanilla never asserts (and survives its rebuild-on-exhaustion). Idempotent, never overwrites an existing distribution, degrades to a no-op if `LevelSettings`/`DEUS_CHEST_TYPES` aren't loaded, logs an ungated `mod:warning`. Pure helpers `_ct_deus_chest_needs_fallback` / `_ct_build_deus_chest_fallback` for testability.

### Tests
- New `/ct_regression_test` check `deus_chest_distribution_fallback` (inject/skip decision + fallback shape).

## 0.7.124-beta (2026-05-26) — Per-mission curse+mutators diagnostic dump + sync level_seed in graph snapshot (citadel curse bug investigation)

### Why
User reported "the citadel of eternity mission curse doesn't match what host set it to. There are 2 final missions, and the curse should match on each, they should be what the host set it to." Plus directive: "Make sure when debug is on, it dumps the curse for the current mission if it has one, and mutators. Make sure the log on Holseher's map dumps which missions have which curse."

Scoured the 2026-05-26 04:14 client + 04:17 host logs for the journey_citadel run. Key findings:

1. **`force_belakor=true` correctly returned from `deus_journey_with_belakor` hook** on both peers (effective_setting fix from v0.7.122 is working).
2. **Per-node populate_graph is non-deterministic across peers despite the same run_seed.** Host's `node_6 = sig_citadel_tzeentch_path5` (level_seed -465327678); client's local populate produced `node_6 = sig_citadel_slaanesh_path5` (level_seed +X). The host snapshot fixes the displayed fields (level/curse/theme), but `level_seed` was NOT in `GRAPH_FIELD_MAP` — so any downstream consumer reading `node.level_seed` (e.g. per-mission terror_event scheduling, curse-halo iconography variant selection, intra-mission generation) diverges between peers.
3. **My v0.7.123 `apply_graph_snapshot` arena_belakor skip is firing correctly** — confirmed by `[ct_graph] apply skipped 1 node(s) for arena_belakor swap preservation (key=node_10)` in the client log, with the temple node showing `level=arena_belakor` in subsequent MAP_OPEN dumps. Issue #53 fix verified working in the wild.
4. **Curse field DID match host/client** on the MAP_OPEN dumps for node_6 (sig_citadel) and final (arena_citadel) — host: `curse_bolt_of_change`/`curse_khorne_champions`, client: same. So either: (a) the mismatch happens in a downstream display path that reads from a different source than `node.curse`, or (b) the user observed the mismatch on a different visual surface (loading screen curse icon? in-mission curse banner? boon-roll curse text?). Need more instrumentation to catch where the actual mismatch surfaces.

### Added — `level_seed` to `GRAPH_FIELD_MAP`
- New short-key `ls = level_seed`. Host snapshot now syncs level_seed alongside level/curse/theme/etc. Closes the determinism gap where same `run_seed` produces different per-node `level_seed` values on host vs client.
- Backward-compatible: v0.7.123 peers receiving from v0.7.124 just ignore the unknown short key; v0.7.124 peers receiving from v0.7.123 see `value == nil` in the iterator and skip (the existing `if value ~= nil then` already handles this). No CT_RPC_SCHEMA bump needed.

### Added — per-mission diagnostic on game start
- New `pcall`-wrapped block at the top of `mod:hook_safe("GameModeDeus", "local_player_game_starts", ...)`. Gated on `enable_debug_logging` via `_dbg`. Fires on BOTH peers when a CW mission starts. Single log line:
  ```
  [mission:start] is_server=<bool> current_node=<key> level=<X> base_level=<X> theme=<X>
                  curse=<X> level_seed=<N> god=<X> node_type=<X>
                  node_mutators={<list>} active_mutators={<list>}
  ```
  - `node_mutators` reads from `current_node.mutators` (the node's declared list)
  - `active_mutators` reads from `Managers.state.game_mode._mutator_handler:activated_mutators()` (what the engine actually activated for this mission)
  - Diff between the two on the same peer = our node data and the engine's mutator activation disagree. Diff between host and client on the same node = sync gap.

### Added — `mutators` + `level_seed` to MAP_OPEN per-node dump
- `[belakor:diag] MAP_OPEN node` lines now include `level_seed=<N> mutators={<list>}`. Both peers' map opens will show the per-node mutator list so any divergence (e.g., host's node_6 has `{curse_bolt_of_change}` but client's node_6 has `{}` or a different curse) is visible at a glance.
- Same fields added to `/dump_journey` chat command's per-node dump.

### Verification path for next co-op session
Both peers turn on `enable_debug_logging`. Host enables `force_belakor`. Run journey_citadel together. At every map open AND on every mission start, both logs get full state dumps. After the session, grep `[mission:start]` + `[belakor:diag] MAP_OPEN node node_6` + `[belakor:diag] MAP_OPEN node final` on both logs and diff host vs client. If `node_mutators` and `active_mutators` diverge on the same peer, that's the bug class. If host/client diverge on the same node's mutators/curse/level_seed, that's a sync gap (and v0.7.124's level_seed sync should plug it).

### Notes
- The Issue #53 client-side Belakor temple fix from v0.7.123 verified in the wild (host log: `arena_belakor_node=node_10` set after locus destruction; client log: same; client's MAP_OPEN shows `level=arena_belakor` — i.e., the swap survives our apply now).
- Host's session ended cleanly at 05:39 with a `serialize_pipeline_library 7578 ms` stall (shader cache write timeout on exit). The accompanying crash dump is a benign shutdown timeout, not a Lua-side fault — no Lua errors precede it in the host log.

## 0.7.123-dev (2026-05-26) — Issue #53 REAL root cause: apply_graph_snapshot was reverting client's arena_belakor swap

### Why
v0.7.122 shipped the `effective_setting("force_belakor")` change plus aggressive `[belakor:diag]` instrumentation and called it Issue #53 done. The instrumentation in last night's session immediately exposed the actual bug — and it was in our own code, not the gated hook. Full grep of the client log captured every relevant signal:

- Client received `with_belakor=true` from host (`_setup_run is_server=false ... with_belakor=true`) ✓
- Client's local populate_graph ran correctly, including arena candidate flagging
- Client received host's graph snapshot via `ct_graph_snapshot_chunk` (7 chunks, 2659 bytes, 16 nodes)
- Client's `apply_graph_snapshot` overlaid host's resolved fields onto its local `_path_graph` — including for the eventual arena_belakor node

The breakage path (verified against vanilla source):
1. Once `_run_state:set_arena_belakor_node(node_X)` writes to SharedState (host-side, after Belakor altar destruction), the vanilla `DeusRunController._get_graph_data()` (deus_run_controller.lua:2035-2056) mutates `_path_graph[node_X]` in place: `level = "arena_belakor"`, `theme = "belakor"`, `base_level = "arena_belakor"`, `minor_modifier_group = {}`, etc. **This swap is what makes the map's prefix-to-unit mapper spawn `ARENA_NODE_UNIT` (the visible temple) for that node.**
2. Vanilla `DeusMapView.start()` (deus_map_view.lua:45) calls `_deus_run_controller:get_graph_data()` first — triggering the swap. Then passes the swapped graph_data to `DeusMapScene:on_enter(graph_data, ...)`.
3. ct's `DeusMapScene.on_enter` hook ran `apply_graph_snapshot(graph_data)` UNCONDITIONALLY when `_ct_host_graph_snapshot` was present — overlaying host's PRE-swap snapshot fields onto the just-swapped node. Net effect: `level="arena_belakor"` got reverted back to (e.g.) `level="bell_belakor_path1"`, `theme="belakor"` got reverted to whatever the host's snapshot had at populate time.
4. Vanilla `DeusMapScene.on_enter` then saw the un-swapped node and spawned `TRAVEL_NODE_UNIT` or `SHRINE_NODE_UNIT` instead of `ARENA_NODE_UNIT`. **No temple.**

Why this was client-only: `_ct_host_graph_snapshot` is populated by the `ct_graph_snapshot_chunk` RPC receiver — only on peers that RECEIVED the broadcast. Host itself never has a snapshot stored, so its `apply_graph_snapshot` call was a no-op (`if _ct_host_graph_snapshot then` short-circuit). Host's swap stayed intact → host saw temple.

Matches the user's exact Issue #53 report: "host sees temple, client does not."

### Changed
- `chaos_wastes_tweaker.lua:apply_graph_snapshot` — resolves `_run_state:get_arena_belakor_node()` at apply time. If non-nil, SKIPS that node when iterating the snapshot. All other nodes still get the host's resolved values (the original purpose of the snapshot — see comments at line ~770 for why we ship the graph at all). When at least one node is skipped, a `_dbg` line is emitted so the next test session can confirm the skip fired.

### Verification — what to look for next session
With `enable_debug_logging=true` on both peers:
- After altar destruction on a belakor mission: grep client log for `[ct_graph] apply skipped 1 node(s) for arena_belakor swap preservation (key=node_X)` on every subsequent map open.
- Grep client `[belakor:diag] MAP_OPEN _start` lines for `arena_belakor_node=node_X` non-nil. Confirms SharedState sync delivered.
- Grep client `[belakor:diag] MAP_OPEN node node_X level=arena_belakor` — confirms the swap survived our snapshot apply. Was previously `level=<original>` post-revert.
- Visual confirmation: client should see Belakor's Temple node on Holseher's map in the same spot host does, after destroying the first locus.

### Notes
- The v0.7.122 `effective_setting("force_belakor")` change is unchanged — it correctly catches the local-call paths (dialogue, telemetry, UI views that read `deus_journey_with_belakor` on every peer). That fix was right; it just wasn't the cause of the map-display gap. Both fixes ship together for completeness.
- The fix is purely additive (1 new lookup + 1 skip-comparison per apply). No behavior change when arena_belakor_node is nil (pre-altar-destruction map opens).

### Closes
- Issue #53 — ct: Belakor's Temple not visible on Holseher's map for CLIENT when host has 'always belakor' enabled (now actually fixed; v0.7.121-122 caught a contributing path but missed this one)

## 0.7.122-dev (2026-05-25) — Fold setup_run diagnostic into existing hook body (mod-lint duplicate-hook fix)

### Why
v0.7.121-dev added a separate `mod:hook_safe("DeusRunController", "setup_run", ...)` for the post-populate graph dump. mod-lint correctly flagged it as a duplicate registration on the same `(Class, method)` pair (the existing full `mod:hook("DeusRunController", "setup_run", ...)` at line ~1224 already registers this hook). VMF silently drops one of two registrations on the same pair, so the published bundle would have only one of the two diagnostics firing.

### Changed
- Removed the separate `mod:hook_safe("DeusRunController", "setup_run", ...)` block.
- Inlined the same diagnostic (arena-node count + arena_keys list) into the existing full hook body at line ~1224, immediately after the vanilla `func(self, unpack(args))` call returns. Same `[belakor:diag]` tag, same payload, wrapped in pcall.
- Block-comment left at the old location pointing readers to the new home.

### Verified
- `tools/mod-lint/lint-mod.ps1 chaos_wastes_tweaker` → no duplicate-hook errors.
- `publish-release.ps1` now passes its lint gate.

## 0.7.121-dev (2026-05-25) — Issue #53 Belakor temple client-side fix + Issue #54 Isha description fix + aggressive `[belakor:diag]` instrumentation

### Why
User-reported gaps (Issues #53, #54). Plus directive: "we should be aggressively dumping data to the log when I'm in game and on menus like Holseher's map or in-game that give you the info you need to fix these issues and make the mod work correctly." So both targeted fixes AND comprehensive instrumentation, gated on `enable_debug_logging` so it doesn't spam normal play.

### Fixed — Issue #53 (Belakor's Temple not visible on client map)
**Root cause:** the `BackendInterfaceDeusPlayFab.deus_journey_with_belakor` hook was gated `is_server and mod:get("force_belakor")` — meaning the host's override only fired on the host. But this method is ALSO called on client peers from non-RPC code paths — specifically `DeusMechanism.get_level_dialogue_context` (deus_mechanism.lua:1337) reads it locally on EVERY peer for dialogue/telemetry, and UI views that ask "does this journey have belakor?" do the same. Pre-v0.7.121 client peers fell through to vanilla which returns the journey's natural belakor-cycle position — wrong answer when host has force_belakor on.

**Fix:** replaced `is_server and mod:get("force_belakor")` with `effective_setting("force_belakor")`. `effective_setting` resolves to host-broadcast value on clients, local value on host — so BOTH peers' local calls now return true when host has the toggle on. The host's `game_round_ended` RPC path is unchanged (still works). The only client-local consumers of this method are display / dialogue / telemetry (none authoritative gameplay state), so mirroring the host is correct.

### Fixed — Issue #54 (Isha description shows wrong mode on client)
**Root cause:** the `Localize` hook's `blessing_of_isha_desc` branch read `effective_setting("tweak_miracle_of_isha_alternative")` — the legacy v0.7.65 dropdown key. v0.7.81 replaced that with a mutex checkbox cluster (`tweak_miracle_of_isha_aegis` / `_wounds`). On any user who migrated past v0.7.81, the legacy key is nil and the Localize hook fell through to vanilla — which displays the wounds-style text regardless of host's choice.

**Fix:** the Localize hook now reads `effective_setting("tweak_miracle_of_isha_aegis")` and `effective_setting("tweak_miracle_of_isha_wounds")` first, falling back to the legacy key for backward compat. Now description text matches the host's selected mode on both peers.

### Added — aggressive `[belakor:diag]` instrumentation (gated on `enable_debug_logging`)
All gated through the existing `_dbg(...)` helper (no-op when toggle is off; full dumps when on). Single grep tag `[belakor:diag]` covers the whole sequence from run-start to map-open.

1. **`DeusMechanism._setup_run` hook_safe** — dumps `run_id / run_seed / journey / dominant_god / with_belakor / mutator_count / boon_count / is_initial_setup / server_peer_id` on BOTH peers as the run starts. Confirms whether client receives `with_belakor=true` from host's RPC.
2. **`DeusRunController.setup_run` hook_safe** — after vanilla setup_run, dumps `_path_graph` arena-node count + arena_keys list per peer. Confirms whether client's `populate_graph` actually produced arena nodes (the temple candidates).
3. **`DeusRunController.unlock_arena_belakor` hook_safe** — fires only on host. Logs `current_node` + picked `arena_belakor_node`. SharedState should sync this value to clients (visible as `<rpc set server> arena_belakor_node = ...` in log).
4. **`DeusMapDecisionView._start` hook_safe** — fires on BOTH peers when the map view opens. Dumps `is_server / journey / current_node / belakor_enabled / arena_belakor_node / has_own_seen / graph_total / arena_in_graph / arena_keys / force_setting` plus per-node `key / level / prefix / theme / curse / god / node_type`. This is the single most diagnostic moment for Issue #53.
5. **`deus_journey_with_belakor` hook** — every call now logs the return value with peer role + setting state, so the dialogue/UI consumer paths are visible.

### Added — `/dump_journey` and `/dump_isha` chat commands
On-demand mid-game state dumps with the same `[belakor:diag]` / `[isha:diag]` tags. Workflow for next co-op session:
1. Both peers turn on `enable_debug_logging` in ct settings.
2. Host enables `force_belakor` (always belakor).
3. Both peers start a CW run together.
4. Between missions, both peers run `/dump_journey` AT THE SAME TIME from chat.
5. Both peers also run `/dump_isha` (with one host-side Isha mode toggled on).
6. Send both log files. Diff `[belakor:diag]` and `[isha:diag]` entries to confirm host/client divergence (if any) or confirm the fix.

### Fixed — `/verify_belakor` was reading non-existent `get_with_belakor`
Vanilla method is `get_belakor_enabled` (deus_run_state.lua:404). Pre-v0.7.121 the command printed `nil` for that field. Fixed to try both names; output label renamed `belakor_enabled` for clarity.

### Closes
- Issue #53 — ct: Belakor's Temple not visible on Holseher's map for CLIENT when host has 'always belakor' enabled
- Issue #54 — ct: Miracle of Isha tweak text shows 'unlimited wounds' when host selected Aegis

### Verification
Live in-game with `enable_debug_logging=true`:
- Both peers in CW with host's `force_belakor=true`: open map → grep `[belakor:diag] MAP_OPEN` → both should show non-nil `arena_belakor_node` + ≥1 arena node in graph.
- Host enables Aegis, client doesn't have any Isha toggle on. Client opens boon picker on a Miracle of Isha roll → tooltip should read "-25% damage taken" (Aegis text), not "unlimited wounds". Confirm via `/dump_isha` on client showing `eff_aegis=true desc_choice=aegis`.

## 0.7.120-dev (2026-05-25) — Fix Issues #39 (slider step-by-25) + #40 (mutex checkbox visual refresh) via two VMFOptionsView hooks

### Why
v0.7.110 filed both as GH Issues and left them for design call. User came back: "the coin increments do not work, find out what's necessary for a slider that increments, because clearly it's not working and neither is the multiple choice options." Re-read VMF source end-to-end and found two hookable callbacks that DO drive widget display in real time. Both fixes shipped.

### Changed
**`chaos_wastes_tweaker.lua`** — two new hooks at file scope, right after `mod.on_setting_changed`:

1. **`mod:hook("VMFOptionsView", "callback_draw_numeric_menu", ...)`** — pre-hook for the `starting_coins` widget. Quantizes `popup_menu_widget.content.internal_value` to multiples of `(25 / full_range)` BEFORE the original (line 4181 of `vmf_options_view.lua`) converts internal_value to a numeric value. Result: when user drags the slider, both the displayed number AND the slider fill visibly snap to multiples of 25 in real time. Gated on `mod_name == "ct" and setting_id == "starting_coins"` so other mods/widgets are unaffected. pcall-wrapped.

2. **`mod:hook("VMFOptionsView", "callback_setting_changed", ...)`** — post-hook fires after VMF's original (which persists the new value and fires `mod.on_setting_changed` — where our mutex enforcer runs and updates sibling values via `mod:set`). Calls `self:update_picked_option_for_settings_list_widgets()`, which walks every widget and re-reads `mod:get(setting_id)` to sync `is_checkbox_checked` / `current_value` / `current_value_text`. Result: when user checks the Aegis variant while Wounds is already checked, Wounds visually unchecks in the same frame. Same fix applies to any future mutex cluster on ct (e.g. isha_choice). Gated on `mod_name == "ct"`; pcall-wrapped.

### Verification (against upstream `vmf/scripts/mods/vmf/modules/ui/options/vmf_options_view.lua`)
- Slider held_function: line 2486-2492 (writes continuous `internal_value`)
- Slider numeric conversion: line 4181-4182 (reads `internal_value`, rounds to `decimals_number`)
- Slider fill render: line 4189-4199 (slider visible position derives from same value)
- Numeric widget popup creation: line 2839 (`popup_menu_widget`)
- `update_picked_option_for_settings_list_widgets`: line 4332-4445 (per-widget sync from `mod:get`)
- View open call site: line 4787 (proves it's only called on `on_enter`, hence the bug)

### Notes
- Existing snap-on-save in `on_setting_changed` is kept as belt-and-suspenders: even if the slider hook ever fails (VMF refactor, etc.), the persisted value still snaps to 25 on save. Belt-and-suspenders is justified here because the two paths fail independently — see `feedback_redundant_safeguards_ok.md`.
- Mutex enforcer in `chaos_wastes_tweaker_mutex.lua` is unchanged — the visual refresh is now driven by the new post-hook, not the enforcer itself, keeping the mutex framework generic for future clusters.
- No CHANGELOG / labels promise behavior the widget doesn't actually do — the `starting_coins` label remains plain `"Starting Coins"` and the slider's visible behavior now matches the persisted-snap-to-25.

### Closes
- Issue #39 — ct: starting_coins VMF slider steps by 1, not 25
- Issue #40 — ct: Miracle of Isha mutex checkboxes don't visually deselect siblings

### Tests
Live in-game (eye-on-outcome verification, per project rule): drag the starting_coins slider, confirm visible snap to 25. Open Reworks > Boons, check Miracle of Isha Wounds while Aegis is checked, confirm Aegis visually unchecks in the same frame.

## 0.7.119-dev (2026-05-25) -- Restore dev/alpha/beta load banner (PROJECT_STANDARDS § 3.6 update)

### Why
User feedback 2026-05-25 EOD: earlier today's chat-spam cleanup pulled the `mod:echo("<Name> v" .. MOD_VERSION)` startup line from every mod. That's correct for stable (>=1.0.0) builds but hides the active version for in-flight dev/alpha/beta work. PROJECT_STANDARDS § 3.6 amended: dev/alpha/beta/0.x versions MUST echo `[<mod_id>] v<version> loaded` at module load; stable versions stay silent.

### Changed
- `chaos_wastes_tweaker.lua` -- added a track-detector `if` after the applied-marker line: matches `-dev$` / `-alpha$` / `-beta$` / `-rc%d*$` / `^0%.`. When any branch fires, `mod:echo("[ct] v<MOD_VERSION> loaded")` runs once.

## 0.7.118-dev (2026-05-25) -- Demote starting-boon grant chat echo to log-only (chat-echo policy: PROJECT_STANDARDS § 3.6)

### Why
`chaos_wastes_tweaker.lua:3690` (inside the `DeusRunController._add_initial_power_ups` hook_safe body) called `mod:echo("Granted %d starting boon(s) to %s (%s)%s", ...)`. The grant is engine-driven -- it fires on every player-add at run start and again on every late-joiner / bot add -- not a user-typed operational toggle. Per PROJECT_STANDARDS § 3.6 ("never echo unless explicit user-typed operational toggle"), this is chat spam. Previous audit comment at line 3643-3644 flagged it as "POTENTIAL BUG (LOW)" with "Once per run would be cleaner" -- the new chat-echo policy makes the call: log-only, not chat.

### Changed
- `chaos_wastes_tweaker.lua` -- starting-boon grant log line at `_add_initial_power_ups` hook_safe body demoted from `mod:echo("Granted %d starting boon(s) to %s (%s)%s", ...)` to `mod:info("[ct:starting_boons] granted %d to %s (%s)%s", ...)`. Same fields, prefixed `[ct:starting_boons]` so the log is greppable. The audit comment at line 3643 is rewritten to document the new behavior (log-only, per § 3.6) instead of flagging it as a known bug.

### Notes
- Per-run-vs-per-player-add frequency is moot now that the line is log-only; if a future maintainer wants to dedupe to per-run, gate on the run_id at the call site -- but it's no longer chat-visible so the urgency is gone.

### Build
VMBLauncher.exe build chaos_wastes_tweaker -- verification only. NOT deployed, NOT uploaded.

## 0.7.117-dev (2026-05-25) -- Remove startup banner echo + tidy on_setting_changed (chat-echo policy: PROJECT_STANDARDS § 3.6)

### Why
User feedback 2026-05-25: `"on enabling debug logging, I'm getting needless echos to the chat that it's enabled"` and `"on startup before enabling debug logging, I'm getting things echo'd to the chat for CWV"`. Audit found 13 mods with redundant `mod:echo("<Name> v" .. MOD_VERSION)` lines at module load and one mod with `mod:echo("Setting changed: " .. setting_id)` in on_setting_changed (career_tweaker -- the source of the Debug Logging chat echo).

Policy decision codified in PROJECT_STANDARDS.md § 3.6 "Chat-echo policy":
- **NEVER** at module load -- the applied marker `[ct] enabled v<X> settings_fp=<hash>` line is the canonical version surface, lives in the log, never spams chat.
- **NEVER** in on_setting_changed for routine settings -- use `_dbg` (gated on enable_debug_logging) if a diagnostic trace is needed.
- **OK** in on_setting_changed only for explicit high-impact toggles (bt master toggle, gt AI toggle).
- **OK** in user-typed chat command bodies (`/<feature>_regression_test`, `/verify_*`, etc.).

### Changed
- chaos_wastes_tweaker.lua -- removed the load-time `mod:echo("chaos_wastes_tweaker v" .. MOD_VERSION)` banner. The applied marker line (`mod:info("[ct] enabled v%s settings_fp=%s", ...)`) further down already surfaces the version + settings hash in the log. `mod:info("chaos_wastes_tweaker v%s loaded", MOD_VERSION)` retained for log-side visibility.
- itemV2.cfg -- updated the description's "Mention the mod version" bug-report instruction. Previous text told users to find the version "at the top of the in-game chat when you load into the keep" -- now points them at the console log (search for the `enabled v` line) or `/<mod>_regression_test`.

### Build
VMBLauncher.exe build chaos_wastes_tweaker -- verification only. NOT deployed, NOT uploaded.

## 0.7.116-dev (2026-05-25) -- Fix unescaped %APPDATA% in Debug Logging tooltip + add localization_format_safe runtime test

### Why
User report: "invalid string format on mouseover for Debug Logging" -- the canonical Universal Debug Logging tooltip (PROJECT_STANDARDS.md S 3.6) shipped with a literal %APPDATA%. Lua's string.format reads %A as a format directive and raises invalid option '%A' to 'format', surfacing as a red error tooltip in the VMF settings UI. All 16 active mods were affected (every mod ships the same canonical tooltip text).

### Changed
- chaos_wastes_tweaker_localization.lua -- escaped literal % in enable_debug_logging_tooltip so VMF's tooltip render path sees %%APPDATA%% (renders as %APPDATA% to the player). Same wording, just escaped.
- chaos_wastes_tweaker.lua -- added _rt_register("localization_format_safe", ...) runtime check. dofiles the loc table and pcall(string.format, value) on every entry; surfaces any unescaped % via /<mod_id>_regression_test. Catches the bug class even when the static check (qa/check_localization.ps1) is skipped.

### Notes
Repo-wide multi-layer defense landing across all 16 mods in this sweep:

1. Layer 1 -- 16 mods' loc strings fixed.
2. Layer 2 -- qa/check_localization.ps1 extended to parse loc.<key> = { en = "..." } assignment style (chaos_wastes_tweaker's pattern -- previously slipped detection).
3. Layer 3 -- _rt_register("localization_format_safe", ...) runtime check in every mod.
4. Layer 4 -- tools/vmb-launcher/CLAUDE.md doctrine update: "Run qa/check_localization.ps1 before declaring any localization edit complete."
5. Layer 5 -- documentation: LOCALIZATION_STANDARD.md S 1 "Recurring offender" worked example, docs/BUG_CLASSES.md S 16 new entry, PROJECT_STANDARDS.md S 3.6 canonical tooltip text now uses %%APPDATA%%.

Static check (qa/check_localization.ps1) reports 0 errors post-fix (down from 15 detected + 1 hidden in chaos_wastes_tweaker).

### Build
VMBLauncher.exe build chaos_wastes_tweaker -- verification only. NOT deployed, NOT uploaded.

## 0.7.115-dev (2026-05-25) — Applied marker (universal — PROJECT_STANDARDS.md § 3.6)

### Why
Every mod now prints a single `mod:info("[ct] enabled v<X.Y.Z> settings_fp=<8-hex>")` line at load — self-documenting console_logs. Walks the data widget tree, FNV-1a-32 hashes setting=value pairs. ALWAYS fires (not gated on debug_logging).

### Changed
- `chaos_wastes_tweaker.lua` — added file-local `_settings_fingerprint()` helper + `mod:info("[ct] enabled ...")` applied-marker line right after the `_dbg_alert` helper.
- `itemV2.cfg` — bumped to v0.7.115-dev.

## 0.7.114-dev (2026-05-25) — Issue #27 pilot: explicit RPC schema_version + drop-on-mismatch

### Why

Cross-peer RPCs between host and client today have implicit schema — host and client peers MUST agree on the positional payload structure of every `mod:network_send` / `mod:network_register` pair, or the receiver silently mis-parses the message and corrupts state. With aggressive dev-iteration (multiple builds per day), the chance of a friend running a stale Workshop bundle while the host runs latest dev is high. Closes GitHub Issue #27 (the Wave-2 RPC-schema hardening tracked alongside the bt net_replay ring buffer from Issue #28).

ct is the pilot for the pattern because it ships the densest RPC traffic in this repo (3 host→client/peer→peer chunked broadcasts: settings sync, graph snapshot, peer manifest). If the pattern works here, follow-up Issues will propagate it to cosmetics_tweaker, lobby_tweaker, enemy_tweaker, crafting_in_modded, and general_tweaker.

### Design

Per-mod `CT_RPC_SCHEMA = 1` constant declared near `MOD_VERSION`. Prepended as the FIRST positional argument of every `mod:network_send` ct emits, and validated as the FIRST argument of every `mod:network_register` callback. On mismatch the receiver:
1. Calls `_dbg_alert("[rpc:schema] <channel> mismatch from peer=<peer>: peer sent v<n>, we expect v<our>. Dropping.")` — logs to file AND surfaces in chat (when debug logging is on).
2. Returns early. No state mutation, no crash.

Bump `CT_RPC_SCHEMA` ONLY when changing RPC payload shape (add/remove/reorder fields). Non-shape changes (logging tweaks, new hooks that don't touch the wire) leave the constant alone.

Graceful-degradation paths for cross-version peers are spelled out in the `CT_RPC_SCHEMA` comment block near `MOD_VERSION` — both directions (new peer to old peer, old peer to new peer) end in a clean drop, not a corruption.

### Changed

- `chaos_wastes_tweaker.lua`:
  - **`CT_RPC_SCHEMA = 1`** added near MOD_VERSION with full comment block (when to bump, graceful-degradation behavior, VMF_RECIPES.md § 10 cross-ref).
  - **`ct_sync_host_settings_chunk`** sender (host's `DeusRunController.setup_run` hook, ~L1178) + receiver (~L630): `CT_RPC_SCHEMA` prepended; receiver gates with `_dbg_alert` mismatch drop.
  - **`ct_graph_snapshot_chunk`** sender (host's `broadcast_graph_snapshot`, ~L839) + receiver (~L771): same wiring.
  - **`ct_peer_manifest_chunk`** sender (`_broadcast_local_manifest`, ~L997) + receiver (~L1002): same wiring.
  - **`_rt_register("ct_rpc_schema_present", ...)`** regression check asserts `CT_RPC_SCHEMA` exists as a number ≥ 1 so a future refactor can't silently drop the constant.
- `itemV2.cfg` — bumped to v0.7.114-dev.
- `VMF_RECIPES.md § 10` — new section "RPC schema versioning" covering the design + when to bump + the migration path for adding new RPCs.
- `PROJECT_STANDARDS.md` — cross-ref under § 3 (logging) pointing at the new recipe section.

### Migration path for follow-up mods

When propagating to bt / lobby_tweaker / cosmetics_tweaker / enemy_tweaker / crafting_in_modded / general_tweaker:
1. Declare `<MOD>_RPC_SCHEMA = 1` near MOD_VERSION.
2. Prepend the constant to every `mod:network_send` for THIS mod's RPCs.
3. Add `schema_version` as the first arg after `sender_peer_id` in every `mod:network_register` callback signature.
4. Gate with `_dbg_alert + return` on mismatch.
5. Add `_rt_register("<mod>_rpc_schema_present", ...)`.

Each propagation is a separate Issue so cross-mod churn doesn't compound. **Don't** add other mods' schema constants in ct's pilot bump.

### Closes

GitHub Issue #27 (senior-eng hardening: explicit RPC schema_version + drop-on-mismatch). Follow-up Issues to file: propagate to cosmetics_tweaker (4 RPCs: cos_la_apply / cos_la_apply_req / cos_glow_apply / cos_glow_apply_req), lobby_tweaker (lt_motd_show), enemy_tweaker (et_br_fingerprint), crafting_in_modded (cim_modded_slot), general_tweaker (one AI RPC).

### Notes

- The initial value is 1 — bumping for the pilot would be incorrect, since this is the FIRST schema version we've ever defined.
- `_dbg_alert` was chosen (not `_dbg`) because a schema mismatch is a "wrong / unexpected" event per PROJECT_STANDARDS.md § 3.6 two-channel discipline — the user wants to see this in chat when debug logging is on.
- Build verification only this version. No deploy, no Workshop upload.

## 0.7.113-dev (2026-05-25) — Issue #6 auto-probe: altar shuffle determinism dump

### Why

`/verify_altars` (v0.7.105) gave the user a point-in-time snapshot of altar shuffle inputs, but required manually running the command on host AND client at the same node. The MP determinism validation that Issue #6 calls for is far easier if the diagnostic data is captured automatically during normal play: enable debug logging, play a CW run, then diff the two console logs offline.

### Changed

- `chaos_wastes_tweaker.lua`:
  - **Inside the `DeusRunController.get_deus_weapon_chest_type` hook** (~line 1597): added `_dbg("[altar:get_chest_type] PRE ...")` and `_dbg("... POST ...")` calls bracketing the `table.shuffle(new_distribution, seed)` call. PRE captures `node_key`, `level_seed`, `fnv32(seed)`, the four `effective_setting` chest_*_count values, `is_server`, and the pre-shuffle distribution. POST captures `is_server` + post-shuffle order. With debug logging on, host and client logs can be diffed line-for-line to confirm identical seeds + identical shuffle output.
  - **Inside the `ct_sync_host_settings_chunk` RPC handler** (~line 685): added `_dbg("[altar:host_sync_arrived] ...")` after the payload merge, dumping the four chest_*_count keys the host pushed. Lets a client-side log confirm what arrived from the host without `/verify_altars`.
  - **Inside `mod.on_setting_changed`** (~line 7044): added `_dbg("[altar:setting_changed] ...")` for the four chest_*_count widgets. Records "what I just clicked locally" so post-session log diff can distinguish a per-peer mis-toggle from an actual sync failure.
- `itemV2.cfg` — bumped to v0.7.113-dev.

### Use

1. VMF menu → Chaos Wastes Tweaker → enable `enable_debug_logging`.
2. Play a CW run on host + client(s).
3. Attach the host's and each client's log from `%appdata%\Fatshark\Vermintide 2\console_logs\` to a bug report.
4. Grep for `[ct:dbg] [altar:` lines across both files. PRE seed/hash/effective values should match between peers; POST shuffle order should match between peers.

If any field differs at the same node_key, that's the root cause of the divergence — surface it in the Issue thread. `/verify_altars` remains as the on-demand alternative.

### Closes

GitHub Issue #6 (altar distribution seed determinism untested under live MP).

### Notes

- `_dbg` gates on `enable_debug_logging`; with the toggle off (default) these calls are zero-cost no-ops.
- No `_dbg_alert` used at altar sites — divergence isn't detectable from one peer's local log alone, only via offline diff, so chat surfacing would be noise.

## 0.7.112-dev (2026-05-25) — Two-helper debug-logging policy (PROJECT_STANDARDS.md § 3.6)

### Why
User-requested two-channel debug discipline: `_dbg` for confirmation / dump / expected behavior (log file only), `_dbg_alert` for unexpected / wrong / mismatch (log file + in-game chat). Helpers installed in every active mod.

### Changed
- `chaos_wastes_tweaker.lua` — installed `_dbg_alert` helper alongside existing `_dbg`. Added `_rt_register("dbg_helpers_two_channel", ...)` alongside the existing 30+ ct regression checks.
- `itemV2.cfg` — bumped to v0.7.112-dev.

### Notes
- 0 existing `_dbg(...)` call sites in this mod (helper was previously unused — only the definition existed).
- 0 bare `mod:echo` reclassified — all `mod:echo` calls are inside `/ct_*` chat command bodies (user-operational, leave alone) or are the load banner.

## 0.7.111-dev (2026-05-25) — Tighten localization strings to vanilla style (~30 entries rewritten)

### Why

Mod-menu tooltips drifted into multi-paragraph essays with meta-language preambles ("Toggle whether...", "When this option is enabled..."). Vanilla VT2 tooltips are uniformly terse, present-tense, and free of meta-language. This pass aligns ct's heavy hitters with the vanilla voice per the new `LOCALIZATION_STANDARD.md` § 11 rules.

### Changed (live entries only — block-commented dormant-boon strings untouched)

- `inject_adventure_maps_tooltip`: 781 → 367 chars; dropped expedition-internals paragraph, kept finale-arena exception + host-only/restart-required.
- `replace_shrines_with_missions_tooltip`: 474 → 219 chars; trimmed "longer expeditions" rationale paragraph.
- `cursed_mission_count_tooltip`, `disable_dominant_god_tooltip`, `altar_count_tooltip`, `cursed_chest_count_tooltip`, `respawn_on_chest_complete_tooltip`, `any_trait_any_weapon_tooltip`, `tweak_trait_tier_by_rarity_tooltip`, `tweak_shard_strike_duration_tooltip`: dropped "Default = vanilla random distribution untouched" / "Side effect:" / "Subtle effect because..." rationale, kept all magnitudes inline.
- Boon tooltips (`disable_boon_ct_meta_ammo_tooltip`, `disable_boon_ct_meta_movespeed_tooltip`, `start_boon_ct_meta_ammo_tooltip`, `description_ct_meta_ammo`, the `enable_boon_*` / `tweak_*` family for Manann's Tempest / Vaul's Anvil / Asuryan's Wrath / Taal's Twinned Arrow / Anath Raema / Wildfire / Ulric / Khaine's Fury / Moot Milk / Killer in the Shadows / Poison Proof / Home Brewer / Miracle of Ulric): dropped implementation-internals paragraphs, kept "Requires a new CW run" gate + every numerical magnitude.
- Mod-boon variant tooltips (`disable_boon_ct_boon_*`, `start_boon_ct_boon_*`): collapsed "Only present in the pool when 'Rework: X as Boon' is enabled in Reworks > Reworks: Boons" → "Requires the matching Rework toggle".
- `enable_skulls_event_boons_tooltip`: 945 → 286 chars (was the worst offender in the file).
- `bots_mirror_host_boons_tooltip`, `tweak_defeat_recovery_tooltip`, `bomb_boon_cooldown_tooltip`, `bomb_boon_exclusive_tooltip`, `endless_bombs_consumes_morgrim_tooltip`, `rv_no_save_morgrim_tooltip`, `tweak_miracle_of_isha_alternative_tooltip`: trimmed.

### Not touched

- Vanilla-template boon descriptions (`disable_boon_boon_skulls_0X_tooltip`, `disable_boon_boon_supportbomb_*_tooltip`, the `X%%%%` placeholder set) — these mirror FT's stock event-boon wording and are already vanilla-style.
- The Miracle of Isha mutex cluster tooltips (`tweak_miracle_of_isha_aegis_tooltip` / `_wounds_tooltip`) — the leading "choice (A/B) of (B). Alternative to '(B/A) X' — these are mutually exclusive..." preamble is load-bearing per LOCALIZATION_STANDARD.md § 10. Cannot tighten.
- Trait tooltips inside `ban_trait_*_tooltip` — sourced verbatim from vanilla trait descriptions; already canonical voice.
- Block-commented entries (Skulls Event Boons, Activate Dormant Boons families inside the `--[[ ... ]]` blocks): edited the live `enable_skulls_event_boons_tooltip` and left the rest alone since they're not live.

### Build

VMBLauncher.exe build chaos_wastes_tweaker — verification only, no deploy/upload.

## 0.7.110-dev (2026-05-25) — Revert misleading "(snaps to nearest 25)" label on starting_coins; document VMF slider limitation in Issue #39

### Why
v0.7.95 added " (snaps to nearest 25)" to the `starting_coins` localization label as a hint that the persisted value gets rounded to a multiple of 25. The label was misleading on two counts: (1) the user did not request it, and (2) the snap happens at save time, not while dragging — the slider still moves in increments of 1 in the live VMF UI. The label promised behavior the slider doesn't visibly exhibit.

### Changed
- `chaos_wastes_tweaker_localization.lua` — reverted `starting_coins` label to `"Starting Coins"`. No code/runtime behavior change (snap-on-save in `on_setting_changed` is untouched).

### Filed
- **Issue #39** — `ct: starting_coins VMF slider steps by 1, not 25`. Documents the VMF numeric-widget limitation: there is no `step` / `snap` / `increment` field in the widget definition (verified against upstream `vmf_options_view.lua` ~L2730 + slider math ~L4181). Options to actually solve in-UI stepping (dropdown of multiples of 25, coarser bin dropdown, upstream VMF PR) listed in the issue for design call.
- **Issue #40** — `ct: Miracle of Isha mutex checkboxes don't visually deselect siblings`. Root cause: VMF's checkbox widget caches display state in `content.is_checkbox_checked` and only re-syncs from persisted value on `view:on_enter` — `mod:set` from inside `on_setting_changed` updates the store but not the open widget. Underlying mutex enforcement IS working (`_get_isha_mode()` returns the right mode); the failure is purely visual until the menu is reopened. Options listed in the issue.

### Notes
- `STARTING_COINS_MODE_MARKER` and the snap-on-save logic in `on_setting_changed`, `setup_run`, and `rpc_deus_set_initial_soft_currency` are unchanged — the bug fix from v0.7.95 (300 setting → 500 actual) stays in.

## 0.7.109-dev (2026-05-25) — Standardize Debug Logging toggle (universal convention)

### Why
Repo-wide convention: every mod now exposes a single `enable_debug_logging` checkbox at the bottom of its VMF widget tree (PROJECT_STANDARDS.md § 3.6). ct previously had no debug toggle at all — added.

### Changed
- `chaos_wastes_tweaker_data.lua` — appended `enable_debug_logging` checkbox (default `false`) AFTER `recursive_sort` so it lands at the bottom of `options.widgets`, top-level (NOT inside any group).
- `chaos_wastes_tweaker_localization.lua` — added `enable_debug_logging` + `enable_debug_logging_tooltip` strings.
- `chaos_wastes_tweaker.lua` — added file-local `_dbg(fmt, ...)` helper gated on `mod:get("enable_debug_logging")`. Output prefixed `[ct:dbg]`.
- `itemV2.cfg` — title + description bumped to v0.7.109-dev.

### Notes
- No existing debug key to rename (ct had none).

## 0.7.108-dev (2026-05-25) — Issue #34: cap ct_meta_ammo Quiver Cascade max_stacks at 30 + belt-and-suspenders _max_ammo clamp

### Why
Closes Issue #34. Pre-v0.7.108 every `ct_meta_*` per-stack buff template (Quiver Cascade `ct_meta_ammo`, Trueshot Talisman `ct_meta_crit`, Heart of Sigmar `ct_meta_health`, etc. — plus the special-cased `ct_meta_movespeed_stack_1` block) wrote `max_stacks = math.huge`. The factory trusted `_make_meta_proc` to never push the stack count beyond the active boon count. That holds under the happy path, but a runaway proc — stale `_get_player_power_ups` list during peer-late-join graph resync, a future RPC race, or any code path that calls `add_buff(stack_name)` outside the proc — can drive the `total_ammo` `stacking_multiplier` geometrically (engine resolution at buff_extension.lua:1391-1448: `final_value = final_value * (multiplier + 1) + bonus` per stack). At enough stacks the result overflows toward `math.huge`, and `tostring(math.huge) == "inf"` then renders on the HUD via `equipment_ui.lua:635` — the same shape as the wt v0.12.77 nil-hole multi-return collapse that surfaced as `inf` ammo earlier this week.

This is the latent CT version of that bug class (sibling). The user-reported infinity-ammo bug 2026-05-25 was actually wt's safe_hook multi-return collapse (already fixed); this fix addresses the matching ct path so the same symptom can't resurface from this side.

### Changed
- **New constant** `CT_META_AMMO_MAX_STACKS = 30` near `MOD_VERSION`. Doc-block explains the rationale: 30 is well past the realistic boon ceiling (typical CW run tops out at 12-18 boons; 30 is endgame-of-endgame). With the v0.7.104 hyperbolic cost floor in place, 30 stacks of +5% `total_ammo` = 1.05^30 ≈ 4.3x — generous, bounded, HUD-safe.
- `register_meta_boon` factory now writes `max_stacks = CT_META_AMMO_MAX_STACKS` (was `math.huge`) on every sub-buff entry.
- Special-cased `ct_meta_movespeed_stack_1` block: same swap.
- `_make_meta_proc` clamps its loop's upper bound: `local stacks_target = math.min(num_boons, CT_META_AMMO_MAX_STACKS)`. The cap in the template AND the clamp on the proc loop are mirrored on purpose — either alone is sufficient, both together close the door against future-code-path drift.

### Added — belt-and-suspenders `_max_ammo` ceiling
- Inside the consolidated `mod:hook_safe("GenericAmmoUserExtension", "_apply_buffs", ...)` body (search for `CT_META_AMMO_MAX_AMMO_SAFETY_CLAMP_v0.7.108`): `if type(self._max_ammo) == "number" and self._max_ammo > 9999 then self._max_ammo = 9999 end`. This is a post-vanilla-`_apply_buffs` clamp that catches the case where some OTHER buff path (talent, weapon trait, foreign mod, future ct feature) ever feeds `total_ammo` enough stacks to push `_max_ammo` toward Lua's float-printable overflow. 9999 sits well above any realistic ammo pool (vanilla max is ~190 on a Drakegun pre-buffs) and well inside Lua's float-printable integer range.
- Consolidation note: VMF doctrine (CLAUDE.md § Hooking) says `hook_safe` does NOT chain on the same (Class, method) — two registrations silently overwrite. So the existing larger-clip `ammo_per_reload` scaling and the new Issue #34 `_max_ammo` clamp now share a single hook body. Both run unconditionally; neither short-circuits the other.

### Added — regression test
- `/ct_regression_test` now includes check `ct_meta_ammo_stacks_bounded`:
  1. Asserts `CT_META_AMMO_MAX_STACKS` sentinel exists and equals 30.
  2. Walks every `ct_meta_*_stack` template in `BuffTemplates`, asserts each sub-buff's `max_stacks` is finite AND `<= CT_META_AMMO_MAX_STACKS` (catches a regression that drops the cap back to `math.huge`).
  3. Synthetic 50-boon stress: simulate the engine's stacking_multiplier formula with base=100, multiplier=0.05, clamp stacks to `CT_META_AMMO_MAX_STACKS`, run the simulated `_max_ammo` through the same `math.min(buffed_max, 9999)` gate — asserts finite AND `<= 9999` AND `> base` (sanity).

### Anti-pattern guardrails (unchanged from v0.7.104)
- Hyperbolic cost-floor curve (`_ct_meta_ammo_cost_multiplier`) is untouched — only the max stack count is bounded, not the per-stack value.
- Multiplier value (0.05) is untouched — fix only the upper bound on stack count.

### Verification
- `/ct_regression_test` in-keep → `ct_meta_ammo_stacks_bounded` should PASS alongside the existing `ct_meta_ammo_*` checks.
- Build-only verification this release (no deploy, no upload). User to drive a CW run with Quiver Cascade and confirm `/verify_ct_meta_ammo` shows finite `_max_ammo` after stacking the boon up.

## 0.7.107-dev (2026-05-25) — Hardening: nil-hole-safe variadic unpack at N call sites (lessons from wt v0.12.77/.78 burn)

### Why
Repo-wide audit of `{ func(...) }` + bare `return unpack(results)` patterns triggered by the weapon_tweaker v0.12.77/.78 silent-truncation burn. Lua 5.1's `#t` operator stops at the first internal nil entry, and bare `unpack(t)` uses `#t` as its upper bound — any wrapped function that returns multi-values with an interior nil silently loses every return after that nil at the caller. The fix is to capture the true return count via `select("#", ...)` and unpack with explicit bounds (`unpack(t, 1, n)`).

### Sites audited (6 in this file)
| Site | Hook target | Vanilla return signature | Verdict |
|---|---|---|---|
| L~1436 | `DeusMechanism._transition_next_node` | single value (`next_state`) | DEFENSIBLE-AS-IS — documented |
| L~1463 | `DeusMechanism.start_next_round` | three values (`game_mode_key`, `side_compositions`, `game_mode_settings`) | **FIXED** — `_capture_returns` + bounded unpack |
| L~2082 | `PickupSystem.populate_pickups` | nothing (bare `return` only) | DEFENSIBLE-AS-IS — documented |
| L~2727 | `DeusMapScene.on_enter` | nothing | DEFENSIBLE-AS-IS — documented |
| L~2936 | `_G.deus_populate_graph` (no-replace path) | single value (`complete_graph`); mod code reads `result[1]` | DEFENSIBLE-AS-IS — documented |
| L~2972 | `_G.deus_populate_graph` (shop-converted path) | same as above | DEFENSIBLE-AS-IS — documented |

### Added
- File-local `_capture_returns(...)` helper near MOD_VERSION (returns `select("#", ...), { ... }`) for any future hook wrapper that needs nil-hole preservation. Doctrine block above the helper documents the pattern.

### Fixed
- `DeusMechanism.start_next_round` hook now uses `local n, results = _capture_returns(func(self, ...))` + `return unpack(results, 1, n)`. Vanilla currently returns three non-nil values, but a future signature change introducing an interior nil (e.g. optional middle value) would have been silently truncated.

### Documented (no behavior change, but inline comments added)
- The five DEFENSIBLE-AS-IS sites now carry a `v0.7.107-dev nil-hole audit:` comment naming the vanilla source line they were verified against and explaining why bare `unpack` is safe at that site.

## 0.7.106-dev (2026-05-25) — Issue #28: demo integration with bt net-replay ring

### Why
Closes Issue #28 (shared net-replay ring buffer for MP desync triage). bt v0.1.2-alpha ships the ring + chat command; ct is the documented demonstrator integration so adopters can see the wiring pattern before Wave-2 (Issue #27) systematizes it across every RPC site.

### Added
- `ct_sync_host_settings_chunk` host→client broadcast is now instrumented on both ends:
  - **Host send side** (~L1098, inside the chunked-broadcast loop in the `DeusRunController.setup_run` hook): per-chunk `record_send("ct", "ct_sync_host_settings_chunk", tag, "others")` where `tag` is `"session=N seq=M total=T chunk=<200 chars>"`.
  - **Client recv side** (top of the `network_register("ct_sync_host_settings_chunk", ...)` callback at L576): per-chunk `record_recv("ct", "ct_sync_host_settings_chunk", tag, sender_peer_id)`.
- Both call sites resolve bt via `get_mod("bt"):net_replay()` and silently no-op if bt isn't installed (same install-independence pattern as the existing `is_br_active()` consumer-side check).

### How to use
1. Run a CW lobby with this mod + bt v0.1.2-alpha installed on every peer.
2. After the host's settings broadcast (fires once at run setup), every peer (host + clients) has populated their bt ring.
3. On any peer, run `/bt_net_replay ct` in chat. The output mirrors to `mod:info` so the trace lands in `%appdata%\Fatshark\Vermintide 2\console_logs\` for offline cross-peer diff.
4. Compare host's `send` lines to each client's `recv` lines: session/seq/total/chunk_str should match end-to-end, and any missing seq number identifies a dropped chunk.

## 0.7.105-dev (2026-05-24) — Issue #6: /verify_altars per-peer determinism diagnostic

### Why
Issue #6 (audit row #3 of CODE_REVIEW.md 2026-05-23 refresh) flags that the custom altar (`deus_weapon_chest`) distribution at `chaos_wastes_tweaker.lua:~1510` uses `HashUtils.fnv32_hash(node.level_seed)` as the shuffle seed — deterministic in theory, but never verified under live multiplayer (hot-join, cross-platform, run-resume). A divergence would silently produce different altar layouts for host vs client peers on the same node.

### Added
- `/verify_altars` chat command (inserted after `/verify_meta_ammo`). On each peer, prints:
  - Current `node_key` (must match across peers — graph-snapshot RPC sync check)
  - `node.level_seed` (must match — the source-of-truth seed)
  - `fnv32_hash(level_seed)` output (must match — pure function of seed)
  - `effective_setting` values for `chest_upgrade_count` / `chest_swap_melee_count` / `chest_swap_ranged_count` / `chest_power_up_count` (must match — host-broadcast settings sync check)
  - Local `mod:get(...)` values for the same four settings (diagnostic — surfaces local-vs-effective divergence if a client's own setting changed but host didn't broadcast)
  - `is_server` flag (so you can tell which peer's output is which)
  - Current `_deus_weapon_chest_distribution` pending pops (only populated AFTER a chest opens on that node)
- Output also mirrored to `mod:info` so the line lands in `console_logs/` for offline cross-peer comparison.

### Validation plan (manual, per Issue #6)
1. Host (PC-A) + client (PC-B) in the same CW lobby, same run, same node.
2. Both run `/verify_altars`. Screenshot or copy both outputs.
3. Every line should match between peers EXCEPT possibly the pending-pops list (depends on whether either peer has opened a chest yet).
4. Hot-join a 3rd peer mid-run and repeat.
5. If `node_key` / `level_seed` / hash differ → graph-snapshot RPC desync.
6. If `effective_setting` values differ → host-broadcast settings desync.
7. If only pending pops differ → shuffle ran with different state somehow.

This release ships the diagnostic but does NOT close Issue #6 — the MP test itself remains for the user to run.

## 0.7.104-dev (2026-05-24) — Quiver Cascade hyperbolic cost-floor (closes 0-cost zero-crossing) + per-meta-boon /verify_ct_meta_* commands

### Why
Two gamebreaking problems, both root-caused by audits this session:

1. **0-cost ammo / energy / overcharge bug** (`.ammo_system_design_2026-05-24.md`): v0.7.102's "consumption-side stat_buff" approach (`ammo_used_multiplier` + `reduced_overcharge`) uses vanilla `stacking_multiplier` resolution which is **linear-additive** (buff_extension.lua:1391-1448). 20 stacks of -0.05 sum to `-1.0`, giving `root_multiplier = 1 + (-1.0) = 0` → cost-per-shot rounds to 0 → infinite ammo, energy, and overcharge headroom. Latent at ~20 boons. Vanilla never ships these stat_buffs at `max_stacks > 1`; ct_meta_ammo's per-boon stacking was unexplored territory and the curve crashed through zero.
2. **User can't eyeball whether meta-boons are taking effect** (`.meta_boons_audit_2026-05-24.md`): every meta-boon stat_buff key IS valid and IS read by vanilla, but per-stack increments (1-5%) on bar-displayed stats are too small to see. Audit confirmed 0 silent-no-op key bugs — the perceived "broken" is actually "invisible". Need runtime probes per boon to distinguish "broken registration" from "tiny but working".

### Changed — Quiver Cascade redesign
- **Dropped** the `reduced_overcharge` and `ammo_used_multiplier` stat_buff entries from `CT_META_BOONS[2]`. Both used linear-additive `stacking_multiplier` resolution → divergence at 20 boons → zero / negative cost per shot.
- **Kept** the `total_ammo` stat_buff (positive-only growth, no zero-crossing — vanilla Waystalker passive ships +100% with no engine issue).
- **Added** new shared helper `_ct_meta_ammo_cost_multiplier(num_boons)` at top of file (next to `_clamp_network_bounded_max`): hyperbolic-saturating curve with hard floor.
  - Formula: `cost_factor = max(1 - (N*step) / (1 + N*step/cap), floor)` where `step=0.05`, `cap=0.75`, `floor=0.25`.
  - Bounded `[0.25, 1.0]` for any non-negative N (asserted by regression tests `ct_meta_ammo_cost_floor_holds` and `ct_meta_ammo_no_zero_cost`).
  - Sample points: N=5 → 0.81, N=10 → 0.70, N=20 → 0.57, N=50 → 0.42, N=100 → 0.35, N→∞ → 0.25 (asymptote, NEVER reaches 0).
- **Added** three direct vanilla hooks (use `mod:hook`, not `hook_safe`, since we mutate the cost arg). Each pcalls its body so a crash in resolution can never break the vanilla consumption path. Throttled per-extension log (1 line per 2s) only when factor < 1.0.
  - `GenericAmmoUserExtension.use_ammo` (vanilla line 425) — scales `ammo_used` with belt-and-suspenders integer floor `math.max(1, math.ceil(...))`.
  - `PlayerUnitEnergyExtension.drain` (vanilla line 85) — scales `amount` (float).
  - `PlayerUnitOverchargeExtension.add_charge` (vanilla line 330) — scales `overcharge_amount`, respecting `_ignored_overcharge_types` (charging, damage_to_overcharge, drakegun_charging, flamethrower — same list vanilla skips at line 343).
- **Hooks gate on local-player ownership** — husk units (remote players) early-return with no scaling. Each peer applies its own discount to its own shots; vanilla networking syncs the result.

### Added — per-meta-boon verify commands
For every entry in `CT_META_BOONS`, a factory-generated `/verify_ct_meta_<suffix>` chat command:
- `/verify_ct_meta_stagger` — probes `power_level_impact` + `power_level_melee_cleave`
- `/verify_ct_meta_crit` — probes `critical_strike_chance` + `critical_strike_effectiveness`
- `/verify_ct_meta_health` — probes `max_health` + `healing_received`
- `/verify_ct_meta_cooldown` — probes `cooldown_regen`
- `/verify_ct_meta_ammo` — probes `total_ammo` AND prints the hyperbolic cost factor from the direct hooks
- `/verify_ct_meta_movespeed` (special-cased) — reads `PlayerUnitMovementSettings.get_movement_settings_table(unit).move_speed` directly (no stat_buff path)

Each command prints `OK`/`FAIL` per stat_buff with `resolved` vs `expected` (linear projection) and `delta`. Tolerance `1e-3`. Lets the user PROVE in-mission "the stat_buff applied" — distinguishes broken-registration from invisible-effect.

### Rewritten — /verify_meta_ammo
Now prints the hyperbolic curve at N=0,1,5,10,20,50,100,1000 so the user can see saturation visually. Live section shows `num_boons`, `cost_factor`, and `total_ammo` live resolution if a player unit is available.

### Sentinel marker swap
- **Retired** `CT_META_AMMO_ENERGY_CONSUMPTION_MARKER` value (v0.7.102) — kept the local declaration as a dead placeholder so any transitional upvalue reads still resolve. The body it anchored (`buff_funcs.functions.ct_meta_ammo_refresh_capacity`) still runs the ammo refresh.
- **Added** `CT_META_AMMO_HYPERBOLIC_MARKER = "CT_META_AMMO_HYPERBOLIC_FLOOR_v0.7.104"` at top-of-file scope, read as upvalue inside `_ct_meta_ammo_cost_multiplier` body and printed by `/verify_meta_ammo`.

### Regression tests (`/ct_regression_test`)
- **Removed** `ct_meta_ammo_uses_consumption_side` — the assertion ("ammo_used_multiplier present in ct_meta_ammo_stack") is now WRONG (the stat_buff was the bug). The new `ct_meta_ammo_hyperbolic_floor_v0_7_104` check actively REJECTS its presence.
- **Added** `ct_meta_ammo_hyperbolic_floor_v0_7_104` — verifies marker constant matches v0.7.104 value, helper is exposed on mod table, `BuffTemplates.ct_meta_ammo_stack` contains `total_ammo` and does NOT contain `ammo_used_multiplier`/`reduced_overcharge`/`max_energy`/`max_overcharge`.
- **Added** `ct_meta_ammo_cost_floor_holds` — runtime probe: asserts `_ct_meta_ammo_cost_multiplier(1000)` returns a number in `[0.25, 1.0]` AND `_ct_meta_ammo_cost_multiplier(0)` returns exactly `1.0` (no behavior change without active boons).
- **Added** `ct_meta_ammo_no_zero_cost` — runtime probe: iterates N from 0 to 50, asserts cost factor stays in `[0.25, 1.0]` AND is monotonically non-increasing (curve-shape sanity).
- **Kept** `ct_clamp_helper_present` and `ct_no_direct_max_energy_mutation` — both still valid (helper still useful for future code, no direct `_max_<X>` writes anywhere in ct).

### Verification
1. Restart VT2 with mod enabled.
2. Run `/ct_regression_test` — all 4 new checks PASS (plus the two retained).
3. Run `/verify_meta_ammo` from keep — see hyperbolic curve printout (N=20→0.571, N=100→0.348, N=1000→0.250).
4. Start a CW run, pick up boons until count > 20, run `/verify_ct_meta_ammo` mid-mission — see `cost_factor` decrease as N grows, total_ammo OK/FAIL line.
5. Fire any ranged weapon with N ≥ 20 boons — ammo counter decrements every shot (not stuck at full); reload triggers at empty. Same for Sienna staff (overcharge rises) and Moonfire bow (energy drains).
6. Run `/verify_ct_meta_<X>` per boon to confirm each stat_buff resolves to its expected linear projection.

### References
- Design source: `.ammo_system_design_2026-05-24.md`
- Audit source: `.meta_boons_audit_2026-05-24.md`
- Prior fix lineage: v0.7.78 (max_overcharge → reduced_overcharge), v0.7.102 (consumption-side stat_buff), v0.7.104 (this — direct hooks).

## 0.7.103-dev (2026-05-23) — Back-fill regression test for v0.7.92 Reckless Swings name-based lookup (GH #5)

### Why
Test-coverage audit `.test_coverage_audit_2026-05-24.md` flagged v0.7.92-dev as the one ct fix shipped without an automated regression check (doctrine PROJECT_STANDARDS §15 violation — "every bug requires a test"). The v0.7.92 verification block was entirely manual (load CW, enable toggle, eyeball log line). If a future refactor reverts the name-based lookup to positional `buffs[1]`/`description_values[1]`/`[3]` indexing, nothing catches it.

### Added
- `CT_RECKLESS_SWINGS_NAME_LOOKUP_MARKER` source-pattern sentinel — file-scope constant declared next to `_find_entry_by`, read as an upvalue inside `apply_reckless_swings_tweak` (anchored anti-bitrot pattern, mirrors v0.7.102's `CT_META_AMMO_ENERGY_CONSUMPTION_MARKER`). A refactor that strips the name-based search code path also breaks the upvalue read site.
- `/ct_regression_test` check `reckless_swings_name_based_lookup` — verifies the marker constant matches the v0.7.92 value AND `_find_entry_by` helper exists AS A FUNCTION at file scope. Also schema-checks `reckless_swings_originals` for the v0.7.92 `buff_index`/`dv_threshold_index`/`dv_damage_index` numeric fields (when the tweak is active — payload-shape regression catch).

### Verification
1. Restart VT2 with mod enabled.
2. Run `/ct_regression_test` in chat — verify line `PASS: reckless_swings_name_based_lookup`.
3. (Optional positive trip) Comment out the marker declaration, rebuild, rerun — expect FAIL with "CT_RECKLESS_SWINGS_NAME_LOOKUP_MARKER not defined".

### References
- Test coverage audit: `.test_coverage_audit_2026-05-24.md` MISSING row 1.
- Doctrine: PROJECT_STANDARDS.md §15.
- Original fix: v0.7.92-dev (below).

## 0.7.102-dev (2026-05-23) — Quiver Cascade energy: consumption-side rewrite + universal `_clamp_network_bounded_max` helper (retires v0.7.101's career-specific gate)

### Why
v0.7.101-dev "fixed" the Necromancer-bot max_energy crash (GUID `10764a92-d642-43c2-a51b-07c5b45508be`) by gating the direct `_max_energy` mutation on `item_name == "we_deus_01"` + a base-sanity check + an engine clamp. User feedback (correct): **career-specific gating is the wrong approach.** If any future career (or any future ANY-careers-can-wield-any-weapon mod, of which we ship one) puts the `energy_system` extension on a different career or wields Moonfire on a non-Kerillian, the gate's whitelist is wrong and the bug class returns. The right fix is the same shape as v0.7.78's `max_overcharge → reduced_overcharge` switch: use the vanilla consumption-side stat_buff so the engine's network-bounded max field is never touched.

Vanilla DOES expose a consumption-side stat_buff for energy: **`ammo_used_multiplier`** (defined `stacking_multiplier` at `buff_templates.lua:28`, read by `PlayerUnitEnergyExtension.drain` line 95: `amount = amount * apply_buffs_to_value(1, "ammo_used_multiplier")`). It's the EXACT parallel of `reduced_overcharge`: per-cast, never network-synced, no engine cap involved. Vanilla CW boon `boon_range_01` (Hand of Drakira) already uses it — `scripts/settings/dlcs/morris/deus_power_up_settings.lua:4974`.

### Changed — three-layer doctrine fix
1. **Consumption-side stat_buff (PRIMARY).** `CT_META_BOONS.ct_meta_ammo.stat_buffs` now includes `{ stat_buff = "ammo_used_multiplier", multiplier = -0.05 }` alongside `reduced_overcharge` (overcharge) and `total_ammo` (ammo). At 12 boons → cumulative -0.60 multiplier; `stacking_multiplier` composes additively so the effective drain multiplier is `1 + (-0.60) = 0.40`. Per-cast energy cost drops to 40% → ~2.5x effective firing capacity. Functionally equivalent to the prior +60% bar buff but with no NetworkConstants ceiling risk for any career, present or future.
2. **Universal clamp helper (UNIVERSAL SAFEGUARD).** New top-of-file helper `_clamp_network_bounded_max(field_name, raw_value)` reads `NetworkConstants[field_name].max` (with safe `or 60` fallback) and clamps to `[min, cap]` with integer rounding. Exposed as `mod._clamp_network_bounded_max` for tests / future code. There are currently ZERO direct `_max_<X>` writes in the entire monorepo (verified via grep) — the helper is purely belt-and-suspenders for future code that might be tempted to write the field directly.
3. **Energy refresh block REMOVED.** The entire energy-extension mutation block at the old L5650-5742 (item-name whitelist + base-sanity gate + engine clamp + `_max_energy = N` write + `_energy` rescale) is gone. The boon's apply func now only refreshes `AmmoExtension` (for `total_ammo`); overcharge and energy ride entirely on their respective consumption-side stat_buffs and need no explicit refresh — that's the whole point of the consumption-side pattern.

### Sentinel marker swap
- **Retired:** `CT_META_AMMO_WEAPON_GATE_MARKER`, `CT_META_AMMO_ENERGY_CLAMP_MARKER` (and their two regression checks). They documented the v0.7.101 weapon-gate approach which is now wrong.
- **Added:** `CT_META_AMMO_ENERGY_CONSUMPTION_MARKER = "CT_META_AMMO_ENERGY_CONSUMPTION_v0.7.102"`. Read as an upvalue inside the `ct_meta_ammo_refresh_capacity` closure so a future refactor that strips the consumption-side comment block also breaks the marker read site (anti-bitrot).

### New `/verify_meta_ammo` (rewritten)
The v0.7.101 command was Moonfire-gate-focused. The v0.7.102 rewrite is career-agnostic. Output:
- `weapon=<name>  num_boons=<N>`
- Per-stack and N-stack totals for all 3 stat_buffs (`total_ammo`, `reduced_overcharge`, `ammo_used_multiplier`)
- Live `apply_buffs_to_value(1, <key>)` resolution from the buff_extension (cross-check vs raw arithmetic when other mods stack)
- Clamp ceilings for `max_overcharge` + `max_energy` (proves the helper works at runtime)
- Direct-mutation scan: prints current `_max_overcharge` / `_max_energy` and FLAGS any value > clamp ceiling
- Sentinel marker

### New regression checks (replaces 3 from v0.7.101)
1. `ct_meta_ammo_uses_consumption_side` — asserts `CT_META_AMMO_ENERGY_CONSUMPTION_MARKER` is the v0.7.102 value AND walks `BuffTemplates.ct_meta_ammo_stack.buffs` to verify `ammo_used_multiplier` is present and no engine-bounded `max_energy`/`max_overcharge` stat_buff is present. Catches a partial revert that puts the bug back in either the marker OR the data path.
2. `ct_clamp_helper_present` — asserts `mod._clamp_network_bounded_max` exists, is callable, and emits a clamped value `<= NetworkConstants.max_<X>.max` for both overcharge and energy when fed a deliberately oversized input (9999).
3. `ct_no_direct_max_energy_mutation` — runtime walk of `Managers.player:human_and_bot_players()` asserting `_max_energy` AND `_max_overcharge` on every player unit stays within their respective engine caps. Best-effort PASS during keep load timing.

### Files modified
- `chaos_wastes_tweaker/scripts/mods/chaos_wastes_tweaker/chaos_wastes_tweaker.lua` (≈170 LOC delta; net negative: full energy mutation block excised, replaced by 1-line consumption-side stat_buff entry + universal clamp helper):
  - `MOD_VERSION` `0.7.101-dev` → `0.7.102-dev`
  - Added top-of-file `_clamp_network_bounded_max(field_name, raw_value)` helper (around line 47), exposed as `mod._clamp_network_bounded_max`
  - `CT_META_BOONS.ct_meta_ammo.stat_buffs` — new `{ stat_buff = "ammo_used_multiplier", multiplier = -0.05 }` entry
  - Retired markers + new sentinel `CT_META_AMMO_ENERGY_CONSUMPTION_MARKER`
  - `ct_meta_ammo_refresh_capacity` — energy mutation block deleted; function body shrunk to its original "refresh AmmoExtension" role + an upvalue read of the new marker
  - `/verify_meta_ammo` — rewritten career-agnostic
  - 3 regression checks swapped (retired v0.7.101 weapon-gate / clamp-marker / energy-within-bounds; added v0.7.102 consumption-side / clamp-helper / no-direct-max-mutation)
- `chaos_wastes_tweaker/itemV2.cfg` — title suffix `v0.7.101-dev` → `v0.7.102-dev` (vmblauncher auto-rewrites on upload)

### Verification recipe
1. Restart VT2.
2. In the keep on ANY career (Necromancer, Outcast Engineer, Sister of the Thorn, Mercenary, Slayer — anything), run `/ct_regression_test` — all v0.7.102 checks PASS (plus the pre-existing ones).
3. Run `/verify_meta_ammo` — should print all three stat_buffs, clamp ceilings ≥ 60, and `violations=NONE`.
4. Start a CW run with **Necromancer** (the original crash career — bot or human). Collect 12+ boons. Open a Chest of Trials. No crash. Run `/verify_meta_ammo` — should show `num_boons=12`, `ammo_used_multiplier  -5% -> -60% (live=0.40)`, `violations=NONE`.
5. Start a CW run with **Kerillian + Moonfire Bow**. Collect 12+ boons. Verify firing the bow drains the energy bar visibly slower (≈40% per shot of the pre-boon rate).
6. Lint: `tools/mod-lint/lint-mod.ps1 -ModPath chaos_wastes_tweaker` PASS.

### Peer-sync safety
The fix is BACKWARD-COMPATIBLE with prior versions IF the player using v0.7.102 never crashes a non-Kerillian host running pre-v0.7.102 (because the host's local stack still mutates `_max_energy` and that's per-peer state). Mixed-version play between v0.7.101 ↔ v0.7.102 is safe; pre-v0.7.101 hosts still risk the original crash on their own side. The BuffTemplates entry is registered via the same `register_buff_in_network_lookup` path as the existing 3 stat_buffs (deterministic sort), so combined_hash is stable.

### Doctrine memory written
`feedback_vt2_max_resource_consumption_side.md` — formalizes the rule: when a boon/buff conceptually means "more of a network-bounded resource", use the consumption-side stat_buff (`reduced_<field>`, `ammo_used_multiplier`, etc.); never write `_max_<field>` directly. Career-specific gating is wrong because the bug class returns the moment another career adopts the resource.

---

## 0.7.101-dev (2026-05-23) — Quiver Cascade Moonfire-only energy gate + engine-bound clamp (fixes Necromancer-bot max_energy crash)

### Why
Crash GUID `10764a92-d642-43c2-a51b-07c5b45508be`. Engine fatal at `foundation/scripts/util/error.lua:26`:
```
Max energy outside value bounds allowed by network variable!
```
fired from `player_unit_energy_extension.lua:43`. Self state at crash: `_max_energy = 64`, `_ct_meta_ammo_base_max = 40`, `_energy = 64`. Career = **Necromancer (bot)**. `NetworkConstants.max_energy.max == 60` so 64 trips the fassert.

Root cause: the Quiver Cascade meta boon's `ct_meta_ammo_refresh_capacity` apply func (v0.7.43–v0.7.100) mutated `_max_energy` on **any** player unit with the `energy_system` extension. But per `scripts/network/unit_extension_templates.lua`, `PlayerUnitEnergyExtension` is registered on EVERY career's player + husk profile. Non-Kerillian careers fall back to `max_value or 40` (player_unit_energy_extension.lua:14) because `EnergyData` (energy_data.lua) only defines entries for Kerillian's four careers (`we_waywatcher` / `we_maidenguard` / `we_shade` / `we_thornsister`, all `max_value = 25`).

So a Necromancer bot collected 12 boons (Quiver Cascade stacks 12 → +60%): `40 × 1.60 = 64`, exceeded the cap, crashed the host. Bots get boons too — `Managers.player:owner(unit)` returns the bot's player object the same as a human's.

The original code (L5650) was AUTHORED only for Moonfire Bow (Kerillian's `we_deus_01`) per the comment, but the gate it used was extension-existence — wrong gate.

### Changed — three-layer defensive gate
`scripts/mods/chaos_wastes_tweaker/chaos_wastes_tweaker.lua` (the `ct_meta_ammo_refresh_capacity` body):

1. **Gate 1 — weapon whitelist.** Reads `inventory_extension:get_slot_data("slot_ranged").item_data.name` and proceeds only when it equals `"we_deus_01"`. Necromancer / Outcast Engineer / Sister of the Thorn / any future career-with-energy-mechanic short-circuit at this gate and the extension is never touched.
2. **Gate 2 — base sanity.** If `_ct_meta_ammo_base_max >= 40`, skip. Moonfire Bow's base on Kerillian is 25 (per `EnergyData.we_<career>.max_value`); a base of 40 means we stashed the value while the extension was on a non-Kerillian career falling back to the `or 40` default. Belt-and-suspenders against gate-1 missing a future Kerillian-equips-non-Moonfire-then-equips-Moonfire transition.
3. **Engine clamp.** Even when both gates pass, clamp `new_max` to `NetworkConstants.max_energy.max` (with hardcoded fallback `60` if the constant isn't loaded yet). That's the same value the engine fassert reads — staying at-or-below it is the only crash-free shape.

### Apply-site logging (per PROJECT_STANDARDS.md §15)
- Gate fires: `[ct/meta_ammo] energy_max gated: weapon=<name> (not Moonfire Bow); skipping`
- Base-sanity gate fires: `[ct/meta_ammo] energy_max gated: base=<n> suspiciously high for Moonfire (expected ~25); skipping`
- Scaling proceeds: `[ct/meta_ammo] energy_max scaled: weapon=we_deus_01 base=25 raw_new=<f> new_max=<n> clamp_ceiling=60 num_boons=<n>`

### New chat command — `/verify_meta_ammo`
Dumps the local player's wielded weapon item_name, base/cur max energy from the extension, num_boons from the deus run controller, the clamp ceiling, and what the refresh func would emit for the current state. Reports `gate=SKIP (not Moonfire)` or `gate=PROCEED (Moonfire)` so the user can confirm the fix works without staring at logs. Works in the keep (no run → num_boons = 0) and mid-run.

### New regression checks
Three new `_rt_register` entries on `/ct_regression_test`:
1. `ct_meta_ammo_weapon_gate_present` — asserts the file-scope marker constant `CT_META_AMMO_WEAPON_GATE_MARKER` shipped to the compiled bundle. The closure uses it as an upvalue, so removing it during a refactor breaks both the read site and this check.
2. `ct_meta_ammo_energy_clamp_present` — same shape for `CT_META_AMMO_ENERGY_CLAMP_MARKER`.
3. `ct_meta_ammo_energy_within_bounds` — runtime: walks `Managers.player:human_and_bot_players()`, finds any unit with an `energy_system` extension, asserts `_max_energy <= NetworkConstants.max_energy.max`. Returns FAIL with the offending player + value if any unit exceeds. Tolerates keep-load timing (PASS if `Managers.player` not ready).

### Files modified
- `chaos_wastes_tweaker/scripts/mods/chaos_wastes_tweaker/chaos_wastes_tweaker.lua` — `MOD_VERSION` `0.7.100-dev` → `0.7.101-dev`; gate + clamp in `ct_meta_ammo_refresh_capacity`; file-scope marker constants; `/verify_meta_ammo` command; 3 new regression checks.
- `chaos_wastes_tweaker/itemV2.cfg` — title suffix `v0.7.100-dev` → `v0.7.101-dev`; description body `v0.7.98-dev` → `v0.7.101-dev` (the stale `0.7.98-dev` reference inside the description was a pre-existing drift, fixed in this bump).

### Verification recipe
1. Restart VT2 with the updated mod.
2. In the keep, run `/ct_regression_test` — all 3 new checks must PASS (plus the existing ones).
3. With a Necromancer in the party (bot or human), wield any non-Moonfire ranged weapon. Run `/verify_meta_ammo` — should report `gate=SKIP (not Moonfire)`.
4. Start a CW run with Kerillian + Moonfire Bow. Collect 12+ boons. Open a Chest of Trials. Run `/verify_meta_ammo` — should report `gate=PROCEED (Moonfire)`, `would_emit` clamped to ≤ 60. No crash.

### Peer-sync safety
The fix only changes the LOCAL apply func body — no new NetworkLookup entries, no new BuffTemplates, no new DeusPowerUp* registrations. Peers running mixed versions remain compatible: pre-v0.7.101 peers crash on Necromancer-with-12-boons; v0.7.101 peers no-op the energy mutation on Necromancer. No combined_hash impact.

---

## 0.7.100-dev (2026-05-23) — Full dormant-boon code-path purge (eliminates the v0.7.99 half-fix that re-crashed at Chest of Trials)

### Why
v0.7.98-dev disabled the dormant feature by emptying `DORMANT_BOON_RARITY = {}`, but every other reference to dormant data in the file remained ACTIVE. v0.7.99-dev added `_G.DORMANT_BOON_RARITY = _G.DORMANT_BOON_RARITY or {}` to fix a Lua scope bug exposed at the Chest of Trials (crash GUID `4c5d2157-e5ee-45fd-8f49-ecdcd2e7ade3`, `chaos_wastes_tweaker.lua:1144`). That was a half-fix: live code still walked the empty table and read `activate_dormant_*` settings from a non-existent widget. User demand: **zero active code referencing dormant data**.

### Changed — full purge inventory
- `chaos_wastes_tweaker.lua` — `MOD_VERSION` bumped `0.7.99-dev` → `0.7.100-dev`.
- `chaos_wastes_tweaker.lua` — Top of file: replaced the `_G.DORMANT_BOON_RARITY = ... or {}` shim with a defensive-style preamble block + the `CT_DORMANT_PURGE_VERIFIED` sentinel constant. The global table is GONE (no empty `{}` either).
- `chaos_wastes_tweaker.lua` — Apply-site breadcrumb reworded `dormant boons disabled` → `dormant/skulls boons purged` (active vs. inactive distinction); now logs the sentinel value.
- `chaos_wastes_tweaker.lua` — `_should_strip` (in `generate_random_power_ups` hook ~L1150): dormant branch removed (`DORMANT_BOON_RARITY[name] ... activate_dormant_<name>` check deleted). Only `disable_boon_<name>` + bomb-mutex remain.
- `chaos_wastes_tweaker.lua` — `stripped_dormants` audit log path and `_should_strip` post-strip `DORMANT_BOON_RARITY[name]` check deleted. The strip loop is still defensive (belt-and-suspenders) but contains no dormant-specific code.
- `chaos_wastes_tweaker.lua` — `add_power_ups` boon-trace hook (~L3435): removed `is_dormant`, `dormant_toggle`, and the `DORMANT GRANTED WITH TOGGLE OFF` warning. The `DISABLED BOON GRANTED` warning (user-facing disable toggle) remains active.
- `chaos_wastes_tweaker.lua` — `/verify_dormants` chat command (~L3670) entire body block-commented (`--[[ ... --]]`). Re-enable is a literal uncomment.
- `chaos_wastes_tweaker.lua` — `pre_register_dormant_lookups` + `sync_dormant_boons` function declarations + apply-site calls (~L4885) wrapped in `--[[ ... --]]`. The functions iterated `DORMANT_BOON_RARITY` directly. `_injected_dormants`, `_added_to_pool`, `inject_dormant_boon`, `_add_dormant_to_pool`, `_remove_dormant_from_pool` stay ACTIVE (used by trait + meta boons as generic injectors; do NOT touch `DORMANT_BOON_RARITY`).
- `chaos_wastes_tweaker.lua` — `sync_host_dependent_state` (~L5931): the inline `sync_dormant_boons()` comment was rewritten to point at the FULL purge.
- `chaos_wastes_tweaker.lua` — `deus_rarities_valid` regression check (~L7155): replaced the `pairs(DORMANT_BOON_RARITY)` iteration with `pairs(CT_DISABLED_DORMANT_RARITIES)` so the check still validates the disabled-set's rarities are vanilla-legal (paranoia against future re-enable bringing back a bad rarity).
- `chaos_wastes_tweaker.lua` — `dormant_boon_rarity_is_table` regression check (v0.7.99) renamed to `dormant_boon_rarity_global_absent` and inverted: PASS now means `_G.DORMANT_BOON_RARITY == nil`. The full purge means no global remains.
- `chaos_wastes_tweaker.lua` — NEW regression check `dormant_setting_keys_not_consumed`: asserts the `CT_DORMANT_PURGE_VERIFIED` sentinel constant is present + correct in the compiled bundle. A future partial revert that drops the sentinel fails this check.
- `chaos_wastes_tweaker.lua` — NEW regression check `dormant_chat_commands_removed`: walks the VMF command registry (`mod._data.commands` + `_G.vmf.commands`) and asserts `verify_dormants` is NOT present.
- `itemV2.cfg` — Title suffix bumped: `v0.7.99-dev` → `v0.7.100-dev`.

### Defensive style guide added
A new preamble near `MOD_VERSION` documents the four defensive rules established after this purge:
1. Top-level tables consumed by mid-file closures: declare at TOP of file.
2. Global table indexes: wrap in `(rawget(_G, "X") or {})` sentinel.
3. NetworkLookup / BuffTemplates: always `rawget()`.
4. Every disabled feature ships with a regression check asserting the disable.

### Regression checks for dormant-related code after this purge

Five checks now cover the dormant-disabled state:
1. `dormant_boons_NOT_registered` — disabled names absent from `NetworkLookup.deus_power_up_templates` + `_G.BuffTemplates`.
2. `dormant_boons_NOT_in_pool` — disabled names absent from `DeusPowerUpRarityPool` + `DeusPowerUps[rarity]`.
3. `dormant_boon_rarity_global_absent` — `_G.DORMANT_BOON_RARITY == nil`.
4. `dormant_setting_keys_not_consumed` — purge-verified sentinel present.
5. `dormant_chat_commands_removed` — `/verify_dormants` absent from VMF registry.

### Verification
1. Restart VT2 with the updated mod.
2. Run `/ct_regression_test` in keep — all 5 dormant-related checks must PASS.
3. Start a CW run and trigger a Chest of Trials. The v0.7.99 crash GUID `4c5d2157` was at line 1144 (`_should_strip` indexing the missing global); the line no longer has that code path.

### Peer-sync safety
No change vs. v0.7.99: every peer running v0.7.100-dev produces the same `NetworkLookup` contents (no names added beyond trait/meta boons). The trait + meta boon injection paths still call `inject_dormant_boon` directly with non-dormant names — `inject_dormant_boon` is just historically named; it's a generic boon injector.

---

## 0.7.98-dev (2026-05-23) — Disable all dormant boons + Skulls event boons + ct_kill_heal (Chest-of-Trials crash mitigation)

### Why
After investigating a possible Chest-of-Trials crash, the user requested all mod-injected dormant CW boons be removed from the game entirely. The 9 vanilla "dormant" power-ups (`squats`, `deus_larger_clip`, `deus_throw_speed_increase`, `deus_ammo_pickup_give_allies_ammo`, `deus_coin_pickup_regen`, `deus_large_ammo_pickup_infinite_ammo`, `deus_timed_block_free_shot`, `deus_transmute_into_coins`, `explosive_pushes_on_damage_taken`) and the mod-defined `ct_kill_heal` boon are no longer registered in any `NetworkLookup` / `BuffTemplates` / `DeusPowerUps*` table. The v0.7.93-dev Skulls event boon mutator-clear is also disabled — Skulls boons remain behind their vanilla `skulls_2023` mutator gate (i.e. pre-v0.7.85 behavior). The implementation code is preserved in block comments so re-enable is a literal uncomment.

### Changed
- `chaos_wastes_tweaker.lua` — `MOD_VERSION` bumped `0.7.97-dev` → `0.7.98-dev`.
- `chaos_wastes_tweaker.lua` — Added apply-site log breadcrumb at mod load: `[ct] dormant boons disabled (v0.7.98-dev); 10 dormants + 10 skulls boons commented out at mod-load.` per `feedback_vt2_verify_before_shipping.md`.
- `chaos_wastes_tweaker.lua` — Added `CT_DISABLED_DORMANT_BOON_NAMES` + `CT_DISABLED_DORMANT_RARITIES` + `CT_DISABLED_SKULLS_BOON_NAMES` constants near the top of the file so the new regression checks can iterate the disabled names without depending on the block-commented originals.
- `chaos_wastes_tweaker.lua` — `DORMANT_BOON_RARITY` populated table replaced with empty `{}`; original entries preserved in block comment immediately above. With the table empty every cross-file reference (`_should_strip`, the `add_power_ups` boon-trace hook, `pre_register_dormant_lookups`, `sync_dormant_boons`, `/verify_dormants`, the `deus_rarities_valid` regression check) becomes a clean no-op without needing per-call edits.
- `chaos_wastes_tweaker.lua` — Apply-site calls `pre_register_dormant_lookups()` + `sync_dormant_boons()` block-commented.
- `chaos_wastes_tweaker.lua` — `sync_dormant_boons()` call inside `sync_host_dependent_state` line-commented so re-enable is symmetric with the apply-site uncomment.
- `chaos_wastes_tweaker.lua` — `on_setting_changed` branches for `activate_dormant_*` and `enable_skulls_event_boons` line-commented — the widgets no longer exist so the branches couldn't fire anyway, but commenting them keeps the disable explicit.
- `chaos_wastes_tweaker.lua` — Entire Skulls block (`SKULLS_EVENT_BOONS` list + `_skulls_original_mutators` + `pre_register_skulls_event_lookups` + `_set_skulls_mutators_active` + `sync_skulls_event_boons` + the two apply-site calls) wrapped in a `--[[ ... --]]` block comment.
- `chaos_wastes_tweaker.lua` — `ct_kill_heal` `do ... end` block wrapped in a `--[[ ... --]]` block comment. The NetworkLookup pre-registration that previously had to fire unconditionally is removed at the same time — acceptable because every peer re-syncing to v0.7.98-dev has identical mod state with no `ct_kill_heal` name in the lookup, so no peer-version-subset can produce divergent indices.
- `chaos_wastes_tweaker.lua` — Regression checks `dormant_boons_preregistered`, `dormant_buff_dual_registered`, `kill_heal_uses_permanent_heal_type`, and `skulls_boons_preregistered` block-commented (they would FAIL given registration is disabled). The `skulls_boons_preregistered` block-comment is mandatory because it references the now-undefined `SKULLS_EVENT_BOONS` local — leaving it live would throw "attempt to index a nil value" at `/ct_regression_test` time.
- `chaos_wastes_tweaker.lua` — Added two new regression checks:
  - `dormant_boons_NOT_registered` — iterates `CT_DISABLED_DORMANT_BOON_NAMES` and verifies each is absent from BOTH `NetworkLookup.deus_power_up_templates` AND `_G.BuffTemplates` (under each name's known rarity variant).
  - `dormant_boons_NOT_in_pool` — verifies the disabled names are not present in any rarity bucket of `DeusPowerUpRarityPool` or `DeusPowerUps[rarity]`.
- `chaos_wastes_tweaker_data.lua` — VMF widget groups `activate_dormant_boons_group` (9 checkboxes) and `skulls_event_boons_group` (1 checkbox) block-commented.
- `chaos_wastes_tweaker_data.lua` — `start_boon_dormant_group` builder block-commented in `build_start_tree()`. A starting-boon checkbox for an unregistered boon would silently no-op and mislead users.
- `chaos_wastes_tweaker_data.lua` — `ct_kill_heal` entry in BOON_TREE's health category line-commented.
- `chaos_wastes_tweaker_data.lua` — `SORT_GROUPS["start_boon_dormant_group"] = true` line-commented.
- `chaos_wastes_tweaker_localization.lua` — Block-commented: `display_name_ct_kill_heal` / `description_ct_kill_heal` / `disable_boon_ct_kill_heal*` / `start_boon_ct_kill_heal*`; `skulls_event_boons_group` / `enable_skulls_event_boons*`; `activate_dormant_boons_group` and all 9 `activate_dormant_<boon_id>` + `_tooltip` entries.
- `itemV2.cfg` — Title version suffix bumped: `v0.7.97-dev` → `v0.7.98-dev`.

### Boons removed from the game

Dormant boons (no longer registered in any lookup or pool):
- `squats`, `deus_larger_clip`, `deus_throw_speed_increase`
- `deus_ammo_pickup_give_allies_ammo`, `deus_coin_pickup_regen`
- `deus_large_ammo_pickup_infinite_ammo`, `deus_timed_block_free_shot`
- `deus_transmute_into_coins`, `explosive_pushes_on_damage_taken`

Mod-defined boon (no longer registered):
- `ct_kill_heal` (Khaine's Communion)

Skulls event boons (now stay behind the vanilla `skulls_2023` mutator gate, never roll outside the Skulls event):
- `boon_skulls_01..08` + `boon_skulls_set_bonus_01` + `boon_skulls_set_bonus_02`

### Peer-sync safety
Because every peer running v0.7.98-dev produces the same `NetworkLookup` contents (no names added beyond what other mod features already register), no `feedback_vt2_gated_registration_diverges` desync class can occur. The user is the host so all clients will re-sync against the same mod state once they update.

### Verification
1. Restart VT2 with the updated mod.
2. Run `/ct_regression_test` in keep — both new checks must PASS:
   - `dormant_boons_NOT_registered` — nil for PASS.
   - `dormant_boons_NOT_in_pool` — nil for PASS.
3. Start a CW run, open a shrine — none of the disabled boon names should appear in the offering.
4. Open a Chest of Trials — should no longer crash (the original symptom that triggered this change).
5. Mod load log line: `[ct] dormant boons disabled (v0.7.98-dev)` confirms the apply-site breadcrumb is firing.

### Re-enable instructions
Every block comment carries a `2026-05-23 v0.7.98-dev DISABLED` header with specific re-enable steps. Search the codebase for that string to find every commented block. Restore order:
1. `chaos_wastes_tweaker.lua` — populated `DORMANT_BOON_RARITY` table; apply-site calls; Skulls block; `ct_kill_heal` block; `sync_host_dependent_state` `sync_dormant_boons()` call; `on_setting_changed` branches; the 4 disabled regression checks.
2. `chaos_wastes_tweaker_data.lua` — VMF widget groups; `start_boon_dormant_group` builder; BOON_TREE `ct_kill_heal` entry; SORT_GROUPS entry.
3. `chaos_wastes_tweaker_localization.lua` — All commented locale keys.
4. Remove the two new `dormant_boons_NOT_*` regression checks (or invert their semantics).
5. Bump MOD_VERSION + itemV2.cfg suffix.

## 0.7.97-dev (2026-05-23) -- Block Outcast Engineer crafted bombs from world pickup spawns

### Why
User bug report 2026-05-23: "Bardin's Outcast Engineer bombs are appearing in the item spawns; those are his crafted bombs. They're not supposed to be there." The Outcast Engineer's bomb (`engineer_grenade_t1`) is a vanilla `Pickups.grenades` entry whose only legitimate path into inventory is the career's cooldown buff handing it out via `inventory_extension:add_equipment(slot_name, ItemMasterList["grenade_engineer"], ...)` (see `scripts/settings/dlcs/cog/buff_settings_cog.lua:232`). It is NOT meant to spawn on the ground, on racks, in chests, or via any other world-spawn path.

The ct adventure-injection broadening in v0.7.64 added `"grenades"` to `ADVENTURE_CATS` (the `_can_spawn` fallback that approves vanilla campaign pickups on injected adventure missions). That allow-list swept in EVERY entry of `Pickups.grenades`, including the engineer-only `engineer_grenade_t1`, so on a CW run with adventure injection the bomb could roll as a ground pickup for any character. Vanilla `_can_spawn` could also accidentally approve it if a spawner unit ever tagged `engineer_grenade_t1 = true` (unlikely but not blocked).

### Changed
- `chaos_wastes_tweaker.lua` — Added `_CAREER_EXCLUSIVE_PICKUPS_BLOCKLIST` constant near the top of the file (next to `BOMB_BOON_NAMES`) listing pickup names that must NEVER be world-spawned. Currently one entry: `engineer_grenade_t1` (Bardin Outcast Engineer's crafted bomb). Doc block explains the vanilla source-of-truth (`scripts/settings/equipment/pickups.lua:698`) and the career-grant path that is intentionally NOT routed through `PickupSystem._spawn_pickup` (so the denial doesn't break legitimate career mechanics).
- `chaos_wastes_tweaker.lua` — Modified the `PickupSystem._can_spawn` hook to apply the blocklist BEFORE vanilla's check and BEFORE the ct ADVENTURE_CATS allow-list. Denial is global (every level, every mechanism) since these names should never world-spawn anywhere.
- `chaos_wastes_tweaker.lua` — Added per-run denial telemetry (`_career_exclusive_denial_counts`, `_career_exclusive_logged_this_run`). Reset at the top of every `populate_pickups` hook entry. The denial path bumps the counter, and the first denial per name per run emits an apply-site `mod:info("[pickup] denied career-exclusive: <name>")` log line (rate-limited to once per name per run -- vanilla's spawn-roller polls each pickup name many times per level).
- `chaos_wastes_tweaker.lua` — Added `/verify_engineer_bombs` chat command per the verify-before-shipping doctrine. Prints the blocklist + each entry's per-run denial count + whether the name still exists in the live `Pickups` table.
- `chaos_wastes_tweaker.lua` — Added two `/ct_regression_test` checks:
  - `engineer_bombs_not_in_world_spawns` — asserts the expected blocklist names are in `_CAREER_EXCLUSIVE_PICKUPS_BLOCKLIST`. Source-pattern check; PASSes from the keep.
  - `engineer_bombs_present_in_vanilla_pickups` — asserts every blocklist name still exists somewhere in the global `Pickups` table (catches a vanilla rename that would silently make our denial path dead code).
- MOD_VERSION bumped: `0.7.96-dev` -> `0.7.97-dev`.

### Verification
1. Restart VT2 with the mod enabled.
2. From the keep, run `/ct_regression_test` -- `engineer_bombs_not_in_world_spawns` and `engineer_bombs_present_in_vanilla_pickups` should PASS.
3. Run `/verify_engineer_bombs` -- should print `engineer_grenade_t1 : denials_this_run=0, present_in_Pickups=true`.
4. Start a CW run on an injected adventure mission (any DLC mission, e.g. Magnus / Cemetery / Forest Ambush).
5. Play for a few minutes so spawn rolls accumulate. Open the keep again or `/verify_engineer_bombs` mid-run -- the denial count should be > 0 if `engineer_grenade_t1` ever rolled (it will, given the equal-weight grenade pool: previously visible as engineer bombs on the ground).
6. Confirm no engineer-style bombs (the cylindrical fragmentation-grenade model) appear as world pickups. Regular frag/fire grenades still spawn normally.
7. Pick Bardin Outcast Engineer and confirm his cooldown-grant bomb mechanic still works (he can still craft bombs via his career passive).

### Why this approach
- Constant blocklist at the top of the file (not embedded inside the hook) for visibility -- future career-exclusive pickups added to the blocklist are immediately discoverable, and the regression check's expected-list constant doubles as a one-line audit summary.
- Applied BEFORE the vanilla call to `func(self, spawner_unit, pickup_name)` so denial covers EVERY path -- not just the ct-broadened adventure fallback. Even if vanilla's per-spawner `Unit.get_data(spawner, "engineer_grenade_t1")` ever flipped true on some level, ct overrides.
- Per-run telemetry (counter + once-per-run log) instead of always-fail / count-every-call: the deny path fires many times per level for the same pickup name (each spawner polls the full grenade pool). Once-per-name-per-run is enough to surface the gate is working without spamming the log.
- The career grant path (`buff_settings_cog.lua:232` -> `inventory_extension:add_equipment`) does NOT go through `PickupSystem._spawn_pickup`, so this denial is surgical: only world-spawn paths are blocked, never the engineer's own bomb-crafting passive.

### Related career-exclusive items NOT blocked (informational; do not auto-fix without user direction)
Audited in vanilla `scripts/settings/equipment/pickups.lua` and `scripts/settings/dlcs/morris/morris_pickups_settings.lua`:
- `Pickups.special.bardin_survival_ale` -- Slayer/Ranger Veteran ale buff pickup. NOT in `ADVENTURE_CATS`, so ct's allow-list does NOT sweep it in. No fix needed.
- `Pickups.special.necromancer_ripped_soul` -- Necromancer-only orb (`can_pickup_orb` gates by `career_name == "bw_necromancer"`). Vanilla-gated, NOT in `ADVENTURE_CATS`. No fix needed.
- `Pickups.grenades.holy_hand_grenade` (Morris/CW deus pickup) -- legitimate CW world spawn, not career-exclusive (anyone in a CW run can pick it up). Already handled by `_pickup_unit_loadable` on injected-adventure levels where its unit isn't packaged. No change.

### References
- Vanilla source: `scripts/settings/equipment/pickups.lua:698` (`Pickups.grenades.engineer_grenade_t1`); `scripts/settings/dlcs/cog/buff_settings_cog.lua:232` (engineer's grant path via `add_equipment`).
- `reference_vt2_adventure_pack_spawning_compat.md` -- related context for the v0.7.78 `_pickup_unit_loadable` guard on Skittergate `holy_hand_grenade`.
- `feedback_vt2_verify_before_shipping.md` -- mandates apply-site log + verify command for behavior changes that wouldn't be obviously visible to the user.

## 0.7.96-dev (2026-05-23) — Miracle of Isha: lock in mutex single-select + verify command + regression checks

### Why
User bug report 2026-05-23: "The Miracle of Isha multiple choice doesn't work and neither of the options are titled. Both can be toggled on at the same time (at least in the GUI even if it has no effect)." All three symptoms were already addressed in the v0.7.81-v0.7.85 mutex-cluster rework that exists in current source — but the live deployed bundle was stale (or the user's machine had stale cached UI) and there was no regression gate locking in the canonical state, so a future accidental drop of the mutex declaration or the suppression hook would silently reintroduce all three symptoms with no test failing.

This release adds the missing belt-and-suspenders: (1) a flag the suppression-hook install path writes only on success, (2) a `/verify_isha` chat command that prints the current resolved mode + flag + per-title localization status, (3) three `/ct_regression_test` checks that fail loud if the mutex cluster, the localization keys, or the suppression hook ever go missing.

### Changed
- `chaos_wastes_tweaker.lua` — Added `_G.__ct_isha_suppression_hook_installed` flag. Initialized `false` immediately before the `MutatorTemplates.blessing_of_isha.server.start_function` hook block; set to `true` only on the success branch (template loaded + hook attached). Also: apply-site `mod:info("[isha] mode=%s, applying alternative ...")` log line per the verify-before-shipping doctrine.
- `chaos_wastes_tweaker.lua` — Added `/verify_isha` chat command. Prints MOD_VERSION header, resolved mode (`_get_isha_mode()`), both raw toggle values, the mutex `active("isha_choice")` member, hook-install state, and per-title localization resolution (echoes `OK` if `mod:localize(key) ~= key` else `MISSING`). Surfaces a WARN line if both toggles happen to read true at the same time (mutex enforcer should have prevented; aegis-preference still resolves deterministically in `_get_isha_mode`).
- `chaos_wastes_tweaker.lua` — Three new `/ct_regression_test` checks (appended to the test scaffold near end of file):
  - `miracle_of_isha_choice_widget_is_dropdown` — verifies mutex cluster `isha_choice` is declared with exactly `{tweak_miracle_of_isha_aegis, tweak_miracle_of_isha_wounds}` members. Failure means the radio-style single-select degraded back to independent checkboxes.
  - `miracle_of_isha_titles_present` — verifies all four localization keys (`tweak_miracle_of_isha_aegis`/`_tooltip`, `tweak_miracle_of_isha_wounds`/`_tooltip`) resolve via `mod:localize` to non-empty strings that are not just the key echoed back.
  - `miracle_of_isha_hook_installed` — verifies `_G.__ct_isha_suppression_hook_installed == true`, which is set only when the vanilla revive mutator's `server.start_function` was hookable at mod init.
- `MOD_VERSION` bumped: `0.7.95-dev` → `0.7.96-dev`.

### Verification
1. Restart VT2 with the mod enabled.
2. Run `/ct_regression_test` — three new checks `miracle_of_isha_choice_widget_is_dropdown`, `miracle_of_isha_titles_present`, `miracle_of_isha_hook_installed` should all PASS.
3. Run `/verify_isha` — should print resolved mode (vanilla / aegis / wounds), both raw toggle values, hook installed=true, and `aegis title: (A) Aegis: ... (OK)` / `wounds title: (B) Unlimited Wounds: ... (OK)`.
4. Open VMF settings → Reworks → Boons. The two Isha rows should show their full titles ("(A) Aegis: -25% damage taken for the rest of the run" and "(B) Unlimited Wounds: recruit-style, every knockdown revivable"). Toggling one ON should programmatically toggle the other OFF.
5. Start a CW run, reach the blessing shrine, purchase Blessing of Isha. Console should print `[isha] mode=<aegis|wounds>, applying alternative (vanilla mutator neutralized at server.start_function)`. If a teammate goes down, vanilla's revive-everyone-once mutator does NOT fire (Aegis: the -25% buff is already active; Wounds: knockdown becomes revivable instead of instakill).

### References
- `LOCALIZATION_STANDARD.md` § 10 — Mutex cluster pattern (the canonical (A) / (B) checkbox + leading-4-space indent label convention).
- `feedback_vt2_mutator_template_server_wrap.md` — hook `template.server.start_function`, not the dead `template.server_start_function` field.
- `feedback_vt2_verify_before_shipping.md` — apply-site log + chat verify command convention.

## 0.7.95-dev (2026-05-23) — Starting Coins: rewrite as SETTER (not adder); fix 300-setting-gives-500 bug

### Why
User report 2026-05-23: "We got an extra 200 coins even though we had the setting for starting at 300 we got 500 somehow." Root cause: the prior implementation (`mod:hook_safe("DeusRunController", "setup_run", ...)`) ran AFTER vanilla's `set_player_soft_currency(own_peer_id, REAL_PLAYER_LOCAL_ID, initial_own_soft_currency)` had already written the rolled-over coins (`~0-200` from prior run's `get_rolled_over_soft_currency()`). The mod then re-entered `on_soft_currency_picked_up(starting)` which ADDED the setting on top. Vanilla 200 + setting 300 = displayed 500.

### What changed (setter, not adder)
- `chaos_wastes_tweaker.lua` — Added full `mod:hook("DeusRunController", "setup_run", ...)` that intercepts vanilla's `initial_own_soft_currency` argument (arg[5]) and REWRITES it to the user's snapped `starting_coins` setting BEFORE vanilla executes. Vanilla's setter then writes exactly the setting value — no addition, no double-grant. Setting=0 leaves vanilla rolled-over behavior intact.
- `chaos_wastes_tweaker.lua` — Added host-side `mod:hook("DeusRunController", "rpc_deus_set_initial_soft_currency", ...)` that overrides the incoming `initial_own_soft_currency` from a joining client with the host's own setting. Keeps the "host controls economy" invariant (precedent across `coin_multiplier` / shrine multipliers).
- `chaos_wastes_tweaker.lua` — Removed the old adder block from the `hook_safe(setup_run)` body (`granting_starting_coins = true; self:on_soft_currency_picked_up(starting); granting_starting_coins = false`). The remaining `hook_safe` body now only carries the host-side settings broadcast.
- `chaos_wastes_tweaker.lua` — Added per-run idempotence flag `_starting_coins_applied_for_run` keyed off `DeusRunState:get_run_id()` to defend against host-migration replay or debug re-runs of `setup_run`. Belt-and-suspenders per `feedback_redundant_safeguards_ok.md`.
- `chaos_wastes_tweaker.lua` — Added `STARTING_COINS_MODE_MARKER = "starting_coins:setter-override-via-setup_run-arg"` embedded in the compiled bundle so the source-pattern regression check (below) can verify the setter mode shipped.
- `chaos_wastes_tweaker.lua` — Added `[ct/coins]` log lines at both apply sites: `starting_coins setter applied: vanilla_initial=X, setting=Y, final=Y (run_id=Z)` on the local setup_run hook, and `host RPC override for joining peer: client_sent=X, host_setting=Y` on the RPC handler.
- `chaos_wastes_tweaker.lua` — Added two regression checks:
  - `starting_coins_setter_not_adder` (source-pattern): asserts `STARTING_COINS_MODE_MARKER == "starting_coins:setter-override-via-setup_run-arg"`. Catches a future refactor that accidentally reverts to adder mode.
  - `starting_coins_value_matches_setting` (runtime): when a CW run is active AND `_starting_coins_applied_for_run` matches the live `run_id`, asserts `get_player_soft_currency(own_peer_id) == snapped_setting`. Gives PASS when not applicable (no run / setting=0) instead of false-positive FAIL.
- `chaos_wastes_tweaker.lua` — Added `/verify_coins` chat command: prints the current coin balance, the snapped setting, whether the override-hook marker is present, and host/client status. Use during a fresh CW run to confirm the value applied.

### Per-peer scoping (design call)
Host's setting wins. The local `setup_run` hook reads via `effective_setting("starting_coins")` (host-broadcast value on clients, own value on host), so both peers compute the same target. The host-side `rpc_deus_set_initial_soft_currency` hook ALSO enforces the host's setting on the value written for the joining client's row — belt-and-suspenders for the case where a hot-joiner's broadcast hasn't landed by the time their RPC fires.

### Verification
1. Restart VT2 with the mod enabled.
2. Run `/ct_regression_test` from the keep — `starting_coins_setter_not_adder` should PASS (the runtime check is N/A in keep).
3. In the VMF menu, set **Starting Coins** to `300`.
4. Start a fresh CW run.
5. After Olesya intro, run `/verify_coins` — should show `setting=300, live=300` (or whatever the snapped value is). Also check the log: a single `[ct/coins] starting_coins setter applied: vanilla_initial=<X>, setting=300, final=300 (run_id=<...>)` line.
6. Run `/ct_regression_test` while in the run — `starting_coins_value_matches_setting` should PASS.
7. Negative test: set Starting Coins to `0`, start another fresh CW run. `/verify_coins` should show vanilla behavior (`live=<rolled-over>` — non-zero only if you carried coins over from a prior run).

### References
- `feedback_redundant_safeguards_ok.md` — belt-and-suspenders for silent-fail surfaces.
- `feedback_vt2_verify_before_shipping.md` — every gated feature ships with a `/verify_*` chat command.
- Vanilla source: `scripts/managers/game_mode/mechanisms/deus_run_controller.lua:273` (setup_run signature), `:315` (host setter), `:350-384` (rpc_deus_set_initial_soft_currency host-side handler), `scripts/managers/game_mode/mechanisms/deus_mechanism.lua:1198` (setup_run call site — passes `rolled_over_coins`).

## 0.7.93-dev (2026-05-23) — Skulls Event Boons: rewrite year-round injection to actually work

### Why
The v0.7.85 "Enable Skulls Event Boons (any time)" toggle was a no-op. It appended new entries to `DeusPowerUpRarityPool` at mod load — but `DeusPowerUpRarityPool` is read ONCE at game boot to populate the runtime arrays the offering generator actually scans (`DeusPowerUps[rarity]`, `DeusPowerUpsArray`, `DeusPowerUpsArrayByRarity[rarity]`, `DeusPowerUpsLookup` — see `scripts/settings/dlcs/morris/deus_power_up_settings.lua:7121-7176`). Post-boot writes to the source pool never reach the arrays scanned by `deus_power_up_utils.lua:138-146`. Verified by tracing the offering generator and confirming Skulls boons never rolled outside the Skulls 2023 mutator regardless of toggle state.

### Changed
- `chaos_wastes_tweaker.lua` — Replaced `_add_skulls_to_pool` / `_remove_skulls_from_pool` (which wrote into the unused `DeusPowerUpRarityPool`) with a runtime mutator-clear approach on the live `DeusPowerUps.event[boon_skulls_*]` records. The offering roller at `deus_power_up_utils.lua:146` calls `compatible_mutator_active(power_up.mutators)` on each record's `mutators` field — clearing that field from `{"skulls_2023"}` to `{}` makes the boon roll on any CW run. Toggle-off restores the cached original array.
- `chaos_wastes_tweaker.lua` — Added `pre_register_skulls_event_lookups()` that unconditionally walks the 10 Skulls boons in sorted order at mod load. Re-registers `NetworkLookup.deus_power_up_templates` + `NetworkLookup.buff_templates` entries (idempotent overlay on vanilla's boot-time registration) and mirrors each `power_up_boon_skulls_<NN>_event` buff template from `DeusPowerUpBuffTemplates` into `_G.BuffTemplates` per `feedback_vt2_dormant_buff_template_dual_register`. Defensive against a future vanilla change that defers the DLCUtils merge.
- `chaos_wastes_tweaker.lua` — Added `skulls_boons_preregistered` regression check to `/ct_regression_test`. Walks the 10 boon names, verifies each present-in-this-build template has its NetworkLookup + BuffTemplates registration.
- `chaos_wastes_tweaker_localization.lua` — Rewrote `enable_skulls_event_boons_tooltip` to reflect the mutator-clear approach (not the old broken pool-append wording). Tooltip now warns boons 06/07/08 are inert outside the Skulls mutator (they trigger on daemon-skull pickups + read `skulls_2023_buff` stacks). Boons 01-05 + set bonuses are fully functional outside the event.
- `itemV2.cfg` — Title version suffix bumped: `v0.7.92-dev` → `v0.7.93-dev`.
- `MOD_VERSION` bumped: `0.7.92-dev` → `0.7.93-dev`.

### Why this approach over re-running `inject_dormant_boon`
The 9 ct dormants + 11 trait boons go through `inject_dormant_boon` because they have no vanilla pool entry — we have to BUILD one. The Skulls boons already have full vanilla infrastructure (template, buff variant `power_up_boon_skulls_01_event`, NetworkLookup entries, `DeusPowerUpsArray` slot, etc.). Calling `inject_dormant_boon` for them would duplicate every record in `DeusPowerUpsArray` / `DeusPowerUpsArrayByRarity` / `DeusPowerUpsLookup` and require keeping the duplicated buff-name registration in sync with the vanilla one. The mutator-clear approach preserves the vanilla `power_up_boon_skulls_set_bonus_01_event` linkage that vanilla's set-bonus amplifier closures hard-code in `deus_power_up_settings.lua:462/487/516/...` — meaning the 5-piece set bonus actually works as designed.

### Set-bonus mechanics — verified intact
Vanilla's set-bonus amplifier code (e.g. `deus_power_up_settings.lua:462`) hard-codes the buff name `power_up_boon_skulls_set_bonus_01_event`. Because we keep the boons at their vanilla "event" rarity (not injecting a new rarity copy), the buff names stay vanilla and the amplifier logic continues to detect set completion correctly. Collecting all 5 of `boon_skulls_01..05` triggers `boon_skulls_set_bonus_01` (`+effect_amplify_amount` boost to attack-speed-per-stack, on-proc multipliers, etc.). Collecting all of `boon_skulls_06..08` triggers `boon_skulls_set_bonus_02` similarly.

### Peer-sync safety
- Pre-registration is unconditional + sorted per `feedback_vt2_gated_registration_diverges` — every peer's NetworkLookup ends up with identical contents regardless of toggle state.
- Mutator-field mutation does NOT affect NetworkLookup indices (only the in-table semantics of each record). Each peer can have different toggle states without crashing — the host's roll output is what gets sent over the wire (`rpc_add_power_up` resolves by `lookup_id`, which stays the same vanilla-assigned id).
- The 2025 boons (06/07/08 + set_bonus_02) early-out cleanly if the vanilla template is missing in older builds — both pre-register and mutator-clear loops nil-check before touching.

### Verification
1. Restart VT2 with the mod enabled.
2. Run `/ct_regression_test` — `skulls_boons_preregistered` should PASS.
3. Toggle **Enable Skulls Event Boons (any time)** ON in the VMF menu.
4. Start a fresh CW run with no Skulls mutator active.
5. Visit a shrine and inspect the offered boons. Skulls boons (recognisable by the daemon-skull icons and `boon_skulls_*` localization keys) should appear in the rotation at "event" rarity.
6. Toggle the setting OFF, return to keep, start another fresh run. Skulls boons should NOT appear.
7. Optional: with toggle ON, intentionally collect 5 of `boon_skulls_01..05` in a single run and verify `boon_skulls_set_bonus_01` activates (boon icon appears in the buff bar; per-stack attack-speed boost is visibly higher).

### Boons covered (rarity: "event" — vanilla-assigned, preserved by this mod)
- `boon_skulls_01` — Frenzied Hacks: on melee hit, stack +N% attack speed. Functional.
- `boon_skulls_02` — Slaughterer's Vigour: on kill, stack +N% power level. Functional.
- `boon_skulls_03` — Crimson Parry: timed-block triggers a stagger explosion. Functional.
- `boon_skulls_04` — Bloodletter's Reservoir: on melee hit, gain THP that converts to a regen proc. Functional.
- `boon_skulls_05` — Wrathful Surge: on melee hit, stack +N% power level. Functional.
- `boon_skulls_06` — Skull-Bound Power: +N% power per `skulls_2023_buff` stack. **Inert outside the Skulls mutator** (no daemon-skull pickups → 0 stacks).
- `boon_skulls_07` — Skull Coin Bounty: daemon-skull pickup grants coins. **Inert outside the Skulls mutator.**
- `boon_skulls_08` — Skull-Bound Cooldown: daemon-skull pickup reduces career skill cooldown. **Inert outside the Skulls mutator.**
- `boon_skulls_set_bonus_01` — Khorne's Favor (5-piece set of 01-05): amplifies effect + duration of all collected set pieces. Functional outside the event.
- `boon_skulls_set_bonus_02` — Khorne's Wrath (3-piece set of 06-08): amplifies effect + duration. **Inert outside the Skulls mutator** (depends on inert source boons).

### References
- `feedback_vt2_gated_registration_diverges` — pre-register unconditionally in sorted order; gate only the pool side.
- `feedback_vt2_dormant_buff_template_dual_register` — dual-write to `DeusPowerUpBuffTemplates` AND `_G.BuffTemplates`.
- `reference_vt2_deus_power_up_rarities` — valid rarities are `event/rare/exotic/unique`. Reusing vanilla "event" rarity avoids "common"/"plentiful" crash risk.
- Vanilla source: `scripts/settings/dlcs/morris/deus_power_up_settings.lua:3069-3362` (boon templates), `:7121-7176` (boot bootstrap), `scripts/helpers/deus_power_up_utils.lua:138-146` (offering roller).

## 0.7.92-dev (2026-05-23) — Migrate Reckless Swings tweak from positional indices to name-based lookup

### Why
GitHub Issue #5: the Khaine's Fury (deus_reckless_swings) boon tweak used hard-coded array indices (`buffs[1]`, `description_values[1]`, `description_values[3]`) to mutate values. v0.7.84 added sanity guards that bail safely if FatShark reorders the arrays, making the tweak safe-but-disabled rather than safe-and-working. This refactor replaces positional indexing with name-based search so the tweak works regardless of array order.

### Changed
- `chaos_wastes_tweaker.lua` — Added `_find_entry_by(arr, predicate)` helper function for array searching.
- `apply_reckless_swings_tweak()` — Now uses `_find_entry_by` to locate:
  - `buff_template.buffs[N]` where `buff_to_add == "deus_reckless_swings_buff"`
  - `description_values[N]` where `value_type == "percent"` (threshold)
  - `description_values[N]` where `value_type == "amount"` (damage)
  - Stored indices in `reckless_swings_originals` table for use in revert.
  - Sanity guards retained as defense-in-depth (name-match + numeric-type checks before mutation).
- `revert_reckless_swings_tweak()` — Now restores using stored indices instead of hard-coded `[1]` and `[3]`.
- Inline comment updated: Issue #5 marked resolved in v0.7.92-dev.
- Logging enhanced: `apply` now reports found indices (`buff_index`, `dv_threshold_index`, `dv_damage_index`) to aide verification.
- MOD_VERSION bumped: 0.7.91-dev → 0.7.92-dev.

### Verification
1. Restart VT2 with the mod enabled.
2. Enter Chaos Wastes and enable the **Khaine's Fury Softened** toggle.
3. Check console logs for: `[khaines-fury] tweak applied via name-based lookup (buff_index=1, dv_threshold_index=1, dv_damage_index=3)` (or equivalent indices if FatShark reorders).
4. Pick the Khaine's Fury deus boon and verify:
   - Health trigger threshold shown in tooltip: 25% (not 50%)
   - Damage per hit shown: 1 (not 3)
   - In-game behaviour: taking damage at <25% health, dealing 1 damage per hit (not 3)
5. Disable the toggle and re-enable to verify revert path restores vanilla values.
6. Run `/ct_regression_test` and verify no new assertion failures.

### References
GitHub Issue #5: https://github.com/Ensrick/vermintide-2-tweaker/issues/5

### Verification (back-filled 2026-05-23 in v0.7.103-dev per PROJECT_STANDARDS §15)
Automated regression check `reckless_swings_name_based_lookup` added in v0.7.103. Run via `/ct_regression_test`.

## 0.7.91-dev (2026-05-23) — Namespace `regression_test` chat command to avoid cross-mod collision

### Why
Seven mods registered `mod:command("regression_test", ...)`. VT2 chat commands are global — only the first mod wins, the rest fail silently with `[ERROR] (command): command name 'regression_test' is already used by another mod 'cim'`. Detected in PC-A log 2026-05-23 20:50:52.

### Changed
- `chaos_wastes_tweaker.lua` — renamed `regression_test` → `ct_regression_test`. Verification log line added at registration site.

### Verification
1. Restart VT2. No `[ERROR] (command):` line in console_logs about this command name.
2. Run `/ct_regression_test` in chat. Command fires and prints results.
3. Per memory `feedback_vt2_verify_before_shipping.md`.

## 0.7.80-alpha (2026-05-20)

### Fixed: ct_meta_ammo (Quiver Cascade) crashed Sienna + Bardin drakefire users with `Max overcharge outside value bounds allowed by network variable!`

Two crash reports from a co-op session (host Sienna + Bardin drakefire client) both hit the same fassert at `player_unit_overcharge_extension.lua:110`:

```
fassert(max_value >= NetworkConstants.max_overcharge.min and max_value <= NetworkConstants.max_overcharge.max, "Max overcharge outside value bounds allowed by network variable!")
```

The crash locals showed `original_max_value = 40, max_value = 64` — Sienna staff buffed from 40 → 64 by twelve stacks of ct_meta_ammo's `+5% max_overcharge` per active boon (12 × 5% = +60%). The network variable bound is ~60 (vanilla designed it around Sienna Scholar's +50% talent: 40 base × 1.5 = 60 exactly). ANY value beyond ~60 crashes both host and husk on the per-frame `update()` call.

The bound lives in the compiled engine `.network_config` binary and is NOT widenable from Lua — `NetworkConstants.max_overcharge` is a read-only snapshot from `Network.type_info` at boot, and the transport layer (`GameSession.set_game_object_field` for `overcharge_max_value`) uses the engine's own type-info, not the Lua table. Even monkey-patching the Lua side wouldn't fix husk reads.

Fix: replaced the `{ stat_buff = "max_overcharge", multiplier = 0.05 }` entry with `{ stat_buff = "reduced_overcharge", multiplier = -0.05 }`. The new stat_buff reduces overcharge GENERATED per cast (consumed locally inside the ActionThrowProjectile / overcharge add paths — not network-synced as a max value), so the gameplay effect is "you cast more spells before overheating," equivalent to a bigger bar. Zero crash risk regardless of boon count, no Scholar talent conflict, works for any weapon with overcharge mechanics (including ones without a max_value field where the prior buff was inert).

Per-cast math: at N boons, heat per cast = `1 + N × -0.05 = 1 - 0.05N` of normal. At 12 boons: 40% heat per cast = 2.5x effective casts before hitting the cap. Stronger than the original "+60% bar" intent (1.6x more casts) but the only stable alternative; users can mentally treat it as the same "more comfortable casting" benefit.

Also removed the now-pointless `_calculate_and_set_buffed_max_overcharge_values` call from `ct_meta_ammo_refresh_capacity` since we no longer buff max_overcharge — eliminates the only ct code path that could ever drive a max_overcharge bounds crash even if another mod adds `max_overcharge` on top of Scholar talent.

Localization updated: tooltips + description now say "-5% overheat per cast" (and explain the equivalence to bigger heat bar) instead of "+5% max overheat."

Confirmed via crash-log scan: not a stacking-math bug — vanilla `stacking_multiplier` math (sum of per-stack multipliers, applied once as `value × (1 + sum)`) produced the exact 64 value. No compounding, no inflated boon count. Just the literal +60% multiplied 40, exceeding the engine cap.

## 0.7.79-alpha (2026-05-20)

### Fixed: VMF crashify exception in `tweak_belakor_temple_unique_boons_tooltip`

The tooltip text contained `"a 14% chance per slot"` — VMF's `localize` runs every string through `string.format`, so the literal `%` was interpreted as a format specifier and triggered `<<crashify-exception>>` every time the options UI initialised. Escaped as `14%%`. Visible symptom was an empty crash dialog on game exit aggregating the queued telemetry events.

## 0.7.78-alpha (2026-05-20)

### Fixed: Engine fatal `Unit not found pup_holy_hand_grenade_01_t1` on adventure-injected levels

Symptom: hard crash on level start (most reliably `dlc_dwarf_whaling` / Skittergate, but every adventure-injected mission was exposed) with engine assertion `world.resource_manager().can_get(unit_type, unit_name)` failed for `units/weapons/player/pup_grenades/pup_holy_hand_grenade_01_t1`. Lua stack: `PickupSystem._spawn_spread_pickups` → `_spawn_pickup` → `World.spawn_unit`.

Root cause: v0.7.64 broadened `_can_spawn` to allow vanilla campaign pickup categories (`ammo`, `healing`, `grenades`, …) on adventure-injected levels, fixing the v0.7.63 regression where Holly DLC missions spawned nothing. Side effect: vanilla's `grenades` bucket includes `holy_hand_grenade` (Morgrim's Bomb), whose pickup unit is only loaded by Morris/CW mission packages. On adventure-injected levels that asset is absent from the resource manager, so when RNG rolled it the engine fataled inside `World.spawn_unit`.

Fix: gate every `return true` in the `_can_spawn` hook on `Application.can_get("unit", settings.unit_name)`. Unloadable pickups soft-veto (empty spawner spot, same as if vanilla's gate had returned false) instead of crashing. Same guard applied to the deus_potions / deus_soft_currency / deus_weapon_chest paths as belt-and-suspenders (`feedback_redundant_safeguards_ok`); those entries are CW-packaged and should always pass, but the redundant check is free.

## 0.7.77-alpha (2026-05-20)

### Fixed: VMF "Attempting to rehook active hook" warning on `generate_random_power_ups`

Two separate `mod:hook("DeusPowerUpUtils", "generate_random_power_ups", ...)` blocks existed in ct — one for count override + disabled-boon enforcement + bomb-boon exclusivity (line ~783, original), one for Belakor-temple force-unique-rarity (was line ~1387). VMF allows mod:hook chaining ACROSS mods but warns when the SAME mod re-hooks the same Class+method; the second hook triggered the warning on every mod load.

Fix: consolidated the Belakor force-rarity logic into the original hook's body. Reads `args[6]` (availability_type) and `args[8]` (forced_rarity) positionally — same vanilla signature both hooks were already targeting. Semantics unchanged; one VMF hook registration instead of two.

## 0.7.76-alpha (2026-05-20)

### Added: Shared Blessings — Bots Mirror Host's Boons (toggle, default OFF)

New checkbox under Reworks → Boons: **Shared Blessings: Bots Mirror Host's Boons** (default OFF).

When enabled, every boon the lobby's heroes gain in Chaos Wastes is also granted to every bot in the warband. Covers all sources — shrine picks, altar rewards, dormant reveals, Belakor's Temple, blessings of the gods, set completions, and end-of-level grants — because every CW boon application funnels through the single canonical entry point `DeusRunController.add_power_ups` (`deus_run_controller.lua:1126`).

**Implementation:**
- `hook_safe` on `DeusRunController.add_power_ups`. When the toggle is on and the receiving player is a HUMAN on the HOST (`_run_state:is_server()`), iterate `Managers.player:human_and_bot_players()`, clone the power-up list with fresh `client_id`s per bot, and re-call `add_power_ups(cloned, bot:local_player_id(), false)` for each. `present=false` so the reward popup doesn't fire for bot grants.
- Reentry guard `_ct_bot_mirror_active` prevents infinite recursion when our mirror invocation re-enters the hook. Set rewards triggered inside a host-side `add_power_ups` (via `_check_set_completed`) also mirror naturally because the flag is only set during the inner bot iteration loop.
- Bots are entirely client-side on the host — remote peers see bots as husk units and receive their buffs via the standard server-authoritative buff_system RPC chain. So mirroring runs only on host.
- Talent-style boons (the ones with `power_up.talent = true`) are routed by vanilla `activate_deus_power_up` through `deus_backend:set_deus_talent_ids` for the receiving career — works on bot careers identically, the talent slot is written into each bot's own talent set.

**Limits / known edge cases:**
- Mid-run bot career swaps (rare) won't re-grant historical boons. Workaround: toggle the bot off and back on.
- The `present` reward popup is suppressed for bots by design (would spam the host's UI with N popups for N bots).

Per `feedback_vt2_gated_registration_diverges.md` — this is a roll-time mirror, NOT a registration-time gate. `DeusPowerUps` table indices remain identical across peers regardless of toggle state.

Localization carries Warhammer flavor: "the heroes' fortunes are bound to the Lords of the Old World" framing in the tooltip.

### Added: Khorne's Champions Banlist — Per-Mark Toggles (defaults all OFF)

New nested menu under Curses: **Khorne's Champions Banlist (Boss Enhancements)** with 13 checkboxes — one per Boss Grudge Mark. Banned marks are excluded from monster-boss enhancement rolls.

**The 13 marks (per `BossGrudgeMarks` in `grudge_mark_settings.lua:127-140`):**
Commander, Crippling Blow, Crushing Blow, Frenzy, Intangible, Periodic Curse Aura, Periodic Shield, Raging, Ranged Immune, Regenerating, Unstaggerable, Vampiric, Warping.

**Implementation:**
- `mod:hook` on `TerrorEventUtils.add_enhancements_for_difficulty` (`terror_event_utils.lua:191`). When the caller passes `enhancement_set = nil` or `enhancement_set = BossGrudgeMarks`, swap in a filtered copy that omits banned marks. Other callers (termite / dwarf-fest event variants with their own enhancement sets) pass through untouched.
- The filter only builds when at least one mark is banned (nothing-banned → return nil → vanilla code path). Empty-set fallback is safe: `generate_enhanced_breed` iterates the set into a candidate list; an empty list yields no enhancements, but the `BreedEnhancements.base` health/damage block is always appended regardless.
- Server-only — boss enhancement assignment is server-authoritative at spawn time. Clients receive the chosen enhancements via the spawn data envelope.

**Display name resolution:**
- Display strings live in compiled localization data, not lua source — internal names map to loc keys via the `display_name` field on each `BreedEnhancements` entry.
- At mod load, `_resolve_grudge_mark_display_name` walks the 13 marks and caches `Localize(display_name_<n>)` results into `mod._ct_grudge_mark_display`. Fallback to title-cased internal name if Localize isn't ready or the key is missing.
- Companion command `/dump_grudge_marks` prints the 13 internal→key→resolved-display mappings to the log for verification.

Per `feedback_vt2_gated_registration_diverges.md` — boss enhancements are not registered into a network-indexed table; the filter operates on the per-spawn random pool. No registration divergence risk.

## 0.7.75-alpha (2026-05-20)

### Added: Belakor's Temple — Reward Unique Boons (toggle, default ON)

New checkbox under Reworks → Boons: **Belakor's Temple: Reward Unique Boons** (default ON).

The Belakor arena node (the SIG zone on the Wastes map) rewards a cursed chest on completion. Vanilla `weight_by_rarity` for cursed chests is `{ event=6, exotic=3, rare=6, unique=1 }` (`deus_power_up_settings.lua:14-19`) — only a ~6% chance per slot of rolling a unique even though the temple is the prestige reward in lore.

With this toggle on, the cursed-chest roll AT THE BELAKOR TEMPLE NODE ONLY forces `forced_rarity = "unique"` via `DeusPowerUpUtils.generate_random_power_ups`. Vanilla's `forced_rarity` parameter already implements the requested fallback semantics — if the unique pool is exhausted (every unique already collected), it walks down through exotic → rare → event automatically (`deus_power_up_utils.lua:192-215`). Other cursed chests / weapon chests / shrines retain vanilla rarity weights — the override is local to the Belakor-temple call only, no global `weight_by_rarity` mutation.

Conditions:
- Toggle on.
- `availability_type == DeusPowerUpAvailabilityTypes.cursed_chest`.
- Current node = `_run_state:get_arena_belakor_node()` (the Belakor arena node, queryable per-peer at boon-roll time).

Per-peer note: each peer rolls its own seed when opening the chest (`deus_cursed_chest_view.lua:58` uses position-derived hash), so the hook runs on every player's machine independently. The boon CHOICE isn't network-sync'd; only the resulting `add_power_up` RPC is, so per-peer override is consistent.

Per `feedback_vt2_gated_registration_diverges.md`: this is a gate-at-roll-time override (not registration-time), so DeusPowerUps array indices remain identical across peers regardless of toggle state.

## 0.7.74-alpha (2026-05-20)

### Added: Myrmidia's Wildfire — Generations Cap slider

New numeric slider under Reworks → Boons: **Myrmidia's Wildfire: Generations Cap** (range 1-10, default 3).

Caps how deep the Wildfire fire-spread chain can propagate. Each spread DoT carries a generation tag — the player's own burn is generation 0, the first spread is 1, the second 2, and so on. When a burning enemy dies, the spread proc fires only if the source's generation is below the cap. Default 3 keeps the boon's chain useful for clearing small groups while preventing the runaway hallway-of-fire cascades that emerge against dense hordes.

**Tradeoffs surfaced via the tooltip:**
- Cap = 1: only the player's own burnt enemies trigger a spread; spread targets never re-spread.
- Cap = 3 (default): up to two re-spreads from a single seed kill.
- Cap = 10: near-uncapped, vanilla-like behavior but with an upper bound to keep mass-burning enemy groups from softlocking the spread loop.

Implementation: generation tracking lives on a weak-keyed `_ct_wildfire_generation` table inside the same `ProcFunctions.boon_dot_burning_01_spread` hook added in v0.7.73 for color matching. When a neighbor is tagged via `DamageUtils.apply_dot`, we record `new_gen = src_gen + 1` against the neighbor unit so the next death reads it back. Weak references mean tags die with the unit and no leak occurs across runs.

Per `feedback_vt2_gated_registration_diverges.md` — the slider is read at proc time (not at boon registration time), so peer indices remain identical regardless of cap value.

Host-authoritative because `boon_dot_burning_01_spread` is registered with `authority = "server"` in vanilla — only the server-side hook fires the spread loop.

## 0.7.73-alpha (2026-05-20)

### Reworked: Myrmidia's Wildfire spread DoT color matches the source burn

The boon `boon_dot_burning_01` (Myrmidia's Wildfire) propagates a fire DoT to nearby enemies when a burning target dies. Vanilla's `boon_dot_burning_01_spread` (`morris_buff_settings.lua:3714`) hardcodes the spread template as `boon_career_ability_burning_aoe` — regardless of what burn source actually killed the target.

ct now hooks the proc and picks the spread template from the dying enemy's active burn status effect:

- **Sister of the Thorn — Moonfire Bow** (`burning_elven_magic`) → spreads as blue flame via `we_deus_01_dot_fast`.
- **Sienna Necromancer balefire** (`burning_balefire`) → spreads as purple flame via the auto-generated `boon_career_ability_burning_aoe_balefire` (vanilla's `BalefireBurnDotLookup` builds this variant at boot via `buff_utils.lua:267`).
- **Warp-flame** (chaos sorcerer / `burning_warpfire`) → keeps vanilla Myrmidia orange — the boon is the player's own fire, not warp-corruption.
- **Vanilla burn** (`burning`) → unchanged, vanilla orange.

Hook target is `ProcFunctions.boon_dot_burning_01_spread` (same merged table as Manann's Tempest's `chain_lightning` — buff_func entries live in `dlc_settings.morris.proc_functions` and merge into the global `ProcFunctions` at boot). Implementation re-walks the vanilla spread loop with `buff.cached_custom_dot.dot_template_name` overwritten per call so each death picks its own color without leaking the previous kill's choice.

This is the contract surface for v0.7.74's generation-cap slider (planned next).

## 0.7.72-alpha (2026-05-20)

### Reworked: Quiver Cascade also extends max overheat and Moonfire energy

The `ct_meta_ammo` boon ("Quiver Cascade") previously granted only +5% total ammo per active boon. Per-stack it now also grants:

- **+5% max overheat** via `stat_buff = "max_overcharge"`. Covers Sienna's staves (firebolt, beam, conflag, fireball, geiser) and Bardin's drakefire weapons (drakegun + brace of drake pistols) — both use `PlayerUnitOverchargeExtension`, which reads `max_overcharge` at `_calculate_and_set_buffed_max_overcharge_values` (`player_unit_overcharge_extension.lua:108`).
- **+5% max Moonfire Bow energy** via a runtime hook on `PlayerUnitEnergyExtension._max_energy`. Vanilla's energy system has NO buff path (`apply_buffs_to_value` is never called on max), so we mutate `_max_energy` directly and scale `_energy` proportionally to keep the fill fraction stable. Base value is stashed at first touch and rescaled relative to live boon count.

The prior vanilla `apply_buff_func = "refresh_ranged_slot_buffs"` only refreshed `ammo_extension:refresh_buffs()`. It's replaced by a custom `ct_meta_ammo_refresh_capacity` that does ammo + overcharge recalc + Moonfire-energy rescale in one pass, so all three caps update live on each boon grant — no weapon swap required.

Localization, dropdown tooltips, and the on-boon-card description updated to reflect the extended coverage. Inertness now only applies on the (unlikely) loadout with no ranged weapon at all — every CW career has a ranged slot by default, so this remains theoretical.

Memory cleanup: prior memory file `reference_vt2_max_overheat_modifier_unified.md` was hallucinated. The correct stat_buff key is `max_overcharge` (verified against `buff_templates.lua:109`), not `max_overheat_modifier` (which exists nowhere in the source). Memory rewritten with verified facts.

## 0.7.71-alpha (2026-05-20)

### Added: Ulric's Pack — Unlimited Aura Range toggle

New checkbox under Reworks → Boons. Vanilla `wolfpack` boon's proximity buff has `range_check.radius = 20` (`deus_power_up_settings.lua:3829-3835`); when enabled, the field is set to `math.huge` so the pack's power bonus stacks regardless of how far apart the heroes have spread. `BuffAreaHelper.update_range_check` re-reads the radius every tick (`buff_area_helper.lua:26`) so a one-time field mutation is sufficient — no per-frame hook. Mirrors the bomb-cooldown save-and-restore pattern: toggling off restores vanilla 20m without restart, and `on_setting_changed` re-syncs live. Boon template is never re-registered — only the existing vanilla field is mutated — so peer index alignment is preserved (`feedback_vt2_gated_registration_diverges.md` compliant). Host-authoritative.

## 0.7.70-alpha (2026-05-20)

### Fixed: Isha dropdown "Aegis" option displayed "[Invalid String Format]"

The `isha_alt_aegis` localization at `_localization.lua:323` was `"Aegis (-25% damage taken, all run)"` with a bare `%`. VMF dropdown labels go through `string.format` via `localize_dropdown_data`; a single `%` followed by a space and a letter (`% d`) is a valid format specifier (signed decimal with leading space), so when the format call has no matching numeric arg the engine returns the canonical `"[Invalid String Format]"` placeholder.

Fix: doubled the percent sign — `(-25%% damage taken, all run)`. Same fix pattern documented in memory `feedback_vt2_localize_string_format_pipeline.md`. The other Isha dropdown labels (`isha_alt_vanilla`, `isha_alt_wounds`) have no `%` and were unaffected. The Aegis blessing DESCRIPTION strings shipped earlier (in `MIRACLE_LOC_OVERRIDES`) already escape correctly.

## 0.7.69-alpha (2026-05-19)

### Fixed: Larger Clip required 2 reloads to refill a doubled shotgun clip (now unconditional)

Per user clarification: the deus_larger_clip dormant boon is cut content re-enabled by ct; its "2 pumps to refill a 4-shell clip" is unintended vanilla behavior, not a rebalance choice. Removed the v0.7.68 toggle gate — the hook now always fires.

The behavior is identical to v0.7.68 with the toggle ON. Old toggle widget + localization entries (`tweak_larger_clip_full_reload`, `tweak_larger_clip_full_reload_tooltip`) removed; the only sane behavior is "larger clip refills in one tick."

## 0.7.68-alpha (2026-05-19)

### Added: Rework — Larger Clip scales ammo-per-reload-tick alongside clip_size

Setting: `tweak_larger_clip_full_reload` (Reworks → Boons group, default OFF).

User report: on shotguns (Grudge-Raker etc.) with `deus_larger_clip` active, the clip goes from 2→4 but refilling it requires 2 pump cycles instead of 1. Each shotgun pump still loads only 2 shells, even though the clip is now 4.

Vanilla cause: `GenericAmmoUserExtension._ammo_per_reload` is set ONCE at extension init from the weapon template (`grudge_raker.lua:155: ammo_per_reload = 2`) and is NEVER passed through `apply_buffs_to_value`. The `clip_size` stat_buff IS applied (line 95 of generic_ammo_user_extension.lua: `_ammo_per_clip = math.ceil(buff_extension:apply_buffs_to_value(_original_ammo_per_clip, "clip_size"))`), but `_ammo_per_reload` is just copied verbatim at line 28. Each reload tick caps at `_ammo_per_reload` shells — so a doubled clip needs two ticks to refill.

This is genuine vanilla behavior, not a CT regression. CT does not touch `larger_clip`, `ammo_per_reload`, or any reload code.

Fix (toggle-gated rebalance): `mod:hook_safe(GenericAmmoUserExtension, "_apply_buffs", ...)` reads the effective clip_size multiplier (`_ammo_per_clip / _original_ammo_per_clip`) and applies the SAME scale to `_ammo_per_reload`. Original value is captured once per extension instance (`_ct_original_ammo_per_reload`) so repeated `_apply_buffs` calls don't compound.

Generic: works for ANY clip_size source (boon, talent, future modded buff). On weapons without an `ammo_per_reload` template entry (everything that already reload-fills in one action) the hook is a no-op. Host-authoritative via `effective_setting`.

## 0.7.67-alpha (2026-05-19)

### Removed redundant name override on `blessing_of_power_name`

Vanilla CW already returns "Miracle of Ulric" for the `blessing_of_power_name` localization key (user-confirmed 2026-05-20). The v0.7.65 Localize hook over-reached and substituted the same string back, which was a no-op visually but conceptually wrong — the user only ever wanted the description changed, not the name. Removed the name from `MIRACLE_LOC_OVERRIDES` and narrowed the `blessing_of_power_*` branch in the Localize hook to `blessing_of_power_desc` only.

### Diagnostic: log every `blessing_of_power` purchase attempt + shop-open offerings

The 2026-05-20 3-player session had the toggle on (host-synced) and the shop was a `shop_strife` (Khorne pillar, which offers `blessing_of_power` per `deus_shop_settings.lua:13-16`), but the user reported "Ulric wasn't purchaseable" and **zero** `_try_buy_blessing` entries appear in either log for the blessing. Buy attempts for the other two blessings (`blessing_holy_hand_grenade`, `blessing_of_grimnir`) recorded normally. Cost was 100; user had 1337 coins remaining after the first two buys, so affordability is not the cause.

Without entry logging in the hook we can't tell if (a) the click never reached `_try_buy_blessing` (UI greyed out the button — most likely) or (b) some silent return-false in our own code fired. v0.7.67 closes that gap:

- **`_try_buy_blessing` entry log** — fires on every call where `blessing_name == "blessing_of_power"`, regardless of toggle state. Logs buyer, is_server, toggle, has_blessing, coins, cost. Next session will tell us whether the click reached the hook at all.
- **Reject-reason logs** — the previously-silent `has_blessing → return false` and `coins < cost → return false` paths now log their cause.
- **`DeusShopView._create_ui_elements` hook augmented** — logs the shop type, full blessing offering list, and current `blessings_with_buyer` state at shop-open. Captures whether `blessing_of_power` is even in the offering pool (it should be, for `shop_strife`).



Same bug class as v0.7.59 / v0.7.60 (gated registration diverges across peers), but at a different table. The v0.7.60 fix split registration from the rarity-pool insert for the `NetworkLookup.deus_power_up_templates` + `BuffTemplates` side tables — but **`DeusPowerUpsLookup` itself** stayed inside the toggle-gated `inject_dormant_boon` body. That table is *also* network-relevant: `deus_mechanism.lua:1256` does `DeusPowerUpsLookup[boon_id]` where `boon_id` is the integer received over RPC. If host's lookup table is ordered differently from client's, host's `rpc_add_buff(id=N)` resolves to a *different* boon on the client.

Caught in pre-deploy QA of the 2026-05-19 multiplayer log: user (client) had `activate_dormant_deus_larger_clip = ON`, friend (host) had it `OFF`. Client log line `deus_larger_clip at rarity rare (lookup_id=165)` doesn't appear in host log; every dormant + trait boon ID after `deus_coin_pickup_regen` was off by +1 on the client. Subsequent host rpc_add_buff calls would have resolved to the wrong boon.

Fix: split `inject_dormant_boon` into two functions.
- `inject_dormant_boon(name, rarity)` — registers EVERYTHING network-relevant (NetworkLookup names, buff_templates, DeusPowerUps / Array / ArrayByRarity / Lookup, BuffTemplates global mirror, DeusPowerUpBuffTemplates). Idempotent via `_injected_dormants[name]`. Called unconditionally for all dormants + trait boons in pre-register passes at mod-load.
- `_add_dormant_to_pool(name, rarity)` — inserts into `DeusPowerUpRarityPool[rarity]`. Idempotent via `_added_to_pool[name]`. Called from the toggle-gated paths (`sync_dormant_boons`, `register_trait_boon`) so each peer only rolls the boons their toggles enabled.

Both pre-register passes (`pre_register_dormant_lookups`, `pre_register_trait_boon_lookups`) now drive full registration. The previous "partial pre-register" code paths in each are simplified — the work is now consolidated in `inject_dormant_boon`. Unconditional registration sites (`register_meta_boon` for CT_META_BOONS, the ct_meta_movespeed do-block, the ct_kill_heal do-block) explicitly call `_add_dormant_to_pool` after `inject_dormant_boon` since meta boons aren't toggle-gated.

Affected dormants (9): `deus_ammo_pickup_give_allies_ammo`, `deus_coin_pickup_regen`, `deus_large_ammo_pickup_infinite_ammo`, `deus_larger_clip`, `deus_throw_speed_increase`, `deus_timed_block_free_shot`, `deus_transmute_into_coins`, `explosive_pushes_on_damage_taken`, `squats`.

Affected trait boons (11): all entries in `CT_TRAIT_BOONS` table — Vaul's Anvil, Manann's Tempest, Taal's Twinned Arrow, Asuryan's Wrath, etc.

**Hardening (pre-deploy QA-caught):** `pre_register_trait_boon_lookups` now writes `DeusPowerUpTemplates[spec.name]` UNCONDITIONALLY (using a placeholder buff array if the source buff is missing on that peer), so `inject_dormant_boon`'s template-existence check never bails — `DeusPowerUpsLookup` stays aligned across peers even for hypothetical DLC-gated source buffs. Today all four source buffs are vanilla so no peer should ever hit the placeholder path; the safety net guards future DLC trait boons.

### Fixed: client-side ct_peers manifest broadcast didn't fire (one-sided handshake)

The v0.7.64 ct_peers diagnostic was supposed to be bidirectional: when a client receives the host's ct_sync_host_settings_chunk, it should auto-reply with its own manifest so the host's log captures every joined peer's ct version + mod list. In practice it was one-sided — host self-logged via the setup_run hook but never received RECV from clients.

Root cause: the `_broadcast_local_manifest("server")` call sat AFTER `sync_host_dependent_state()` in the ct_sync receiver body. `sync_host_dependent_state` calls 11 sync_* re-registration helpers — any one throwing aborts the receiver because VMF's `network_register` safe-wrapper swallows the error. The closure capture analysis was sound; the function was assigned; the call simply never reached.

Fix: moved the manifest broadcast (and added an info log to confirm entry) BEFORE the `sync_host_dependent_state()` call in the ct_sync_host_settings_chunk handler. Now even if a downstream re-registration throws, the manifest reply still goes out.

Next 3-peer session should show `[ct_peers] RECV peer=...` lines on the host log immediately after the ct_sync broadcast lands on each client.

## 0.7.66-alpha (2026-05-19)

### Fixed: Isha alternative drained coins on every shop visit (v0.7.65 dedup bug)

The v0.7.65 Isha alternative branch of `_try_buy_blessing` deliberately skipped writing `blessing_of_isha` to `blessings_with_buyer` because that table drove the vanilla auto-mutator activation. But `DeusRunController.has_blessing` reads the SAME table to decide "is this blessing already bought" — so the shop's purchase-guard never fired and `deus_shop_view_v2.lua:854-867` never marked the slot as bought. Net result: every shop visit, players could re-purchase the Isha alternative for full price, draining coins.

Fix: the buy hook now DOES write to `blessings_with_buyer` (which fixes both the dedup and the shop UI), and a separate `mod:hook` on `MutatorTemplates.blessing_of_isha.server.start_function` suppresses the vanilla mutator behavior by setting `data.hero_side = nil` immediately after vanilla initializes. Every vanilla entry point (`server_update_function`, `server_player_disabled_function`, `server_player_hit_function`) early-returns on `not data.hero_side`, so the entire revive mechanic goes dormant. Localization and persistent buff application remain.

**Hook-target gotcha (caught in pre-deploy QA):** the live dispatch target is `template.server.start_function`, NOT `template.server_start_function`. The engine wraps every mutator's `server_*_function` fields at `mutator_templates.lua:236-269` (which runs at engine boot, before any mod loads) — the original `server_start_function` field becomes a dead pointer captured in an upvalue closure, the wrapper lives at `template.server.start_function`. Hooking the dead field compiles cleanly but suppresses nothing. The fix targets the correct wrapped field.

### Added: Miracle of Isha — Unlimited Wounds variant (recruit-style)

Third option for Isha behavior. When selected, every hero gets unlimited wounds for the rest of the run — every knockdown is revivable, no more "first down was your one wound, second down = instant death" mechanic that higher difficulties enforce.

Implementation: new buff template `ct_miracle_of_isha_wounds` with `perks = { "infinite_wounds" }` and `is_persistent = true`. Mirrors vanilla CW boon `indomitable` (`deus_power_up_settings.lua:5056-5073`). The `infinite_wounds` perk gates `GenericStatusExtension:set_wounded` at `generic_status_extension.lua:1443-1450` — the wounds-counter decrement is skipped, so `has_wounds_remaining()` always returns true, so the death-on-down branch at `player_unit_health_extension.lua:812` is never taken. Recruit difficulty achieves the same effect via `wounds = 5` (effectively unlimited for a CW run length); we use the cleaner perk-based approach.

### Changed: Miracle of Isha is now a dropdown (Vanilla / Aegis / Unlimited Wounds)

Replaces the v0.7.65 `tweak_miracle_of_isha_alternative` checkbox with a 3-option dropdown:
- **Vanilla** (default) — original Blessing of Isha behavior (one team revive when squad reduced to one hero)
- **Aegis** — every hero takes -25% damage for the rest of the run (v0.7.65 alternative)
- **Unlimited Wounds** — every hero gets unlimited wounds for the rest of the run

Migration: users with the v0.7.65 checkbox set to ON automatically get **Aegis** mode on first load after upgrade (the runtime helper `_get_isha_mode` maps boolean `true` → `"aegis"`). Off / nil → Vanilla.

### Fixed: `/ct status` debug output showed stale "(0=vanilla)" legend

The status echo at `chaos_wastes_tweaker.lua:5338-5345` still printed the v0.7.64 sentinel meaning for altar/chest counts. Now reflects v0.7.65 semantics: -1 = Default, 0 = literal zero.

## 0.7.65-alpha (2026-05-19)

### Added: Miracle of Ulric — toggle replaces vanilla "Blessing of Power" with persistent +50 Power that survives weapon swaps

Setting: `tweak_miracle_of_ulric_persistent` (Reworks → Boons group, default OFF).

Vanilla Blessing of Power mutates each player's serialized weapon `power_level` field (+50, applied at purchase time, deus_run_controller.lua:1671-1703). The +50 lives on the weapon ENTRY, so the moment a player swaps weapons at an upgrade / melee swap / ranged swap altar, the new weapon doesn't have it — the bonus EVAPORATES. The user reported this as a long-standing frustration.

When the toggle is ON: ct intercepts `_try_buy_blessing` for `blessing_of_power` and skips the vanilla weapon-mutation branch entirely. Instead, every hero gets a custom `ct_miracle_of_ulric` buff (`stat_buff = "power_level"`, `bonus = 50`, `is_persistent = true`, `max_stacks = 1`) applied directly to their `buff_extension`. Because the buff lives on the player rather than the weapon entry, it survives every weapon swap for the rest of the run. The vanilla blessing-purchase accounting (coins spent, blessings_with_buyer, bought_blessings, coin tracker) is replicated so the blessing still appears in run-stats UI.

Localization is also overridden via the existing `_G.Localize` hook: when the toggle is on, the blessing's name becomes "Miracle of Ulric" and the description reads "Grants every hero +50 Power for the rest of the run. The bonus persists through weapon swaps and upgrades at altars."

Host-authoritative: the toggle is auto-collected into `SYNCED_SETTING_NAMES` and broadcast via `ct_sync_host_settings_chunk`. Clients see whatever the host configured.

### Added: Miracle of Isha (Aegis Alternative) — toggle replaces revive with -25% damage taken for the whole team

Setting: `tweak_miracle_of_isha_alternative` (Reworks → Boons group, default OFF).

Vanilla Blessing of Isha runs `mutator_blessing_of_isha.lua` which grants a single team-revive when the squad is reduced to one hero. Useful, but binary — and the team has to actually wipe to one hero before it does anything.

When the toggle is ON: ct intercepts `_try_buy_blessing` for `blessing_of_isha` and SKIPS adding the blessing to `blessings_with_buyer`. This suppresses `DeusMechanism.start_next_round` from auto-activating the vanilla revive mutator (which reads its blessing list at `deus_mechanism.lua:759-767`). Instead, every hero gets a custom `ct_miracle_of_isha_aegis` buff (`stat_buff = "damage_taken"`, `multiplier = -0.25`, `is_persistent = true`) so the whole team takes 25% less damage for the rest of the run. Coins are still spent + tracked so the purchase feels real.

Trade-off: Isha no longer appears in the run-stats blessing UI when toggled (since the entry isn't added to `blessings_with_buyer`). Description text is rewritten to reflect the aegis behavior; the name stays "Blessing of Isha."

Host-authoritative — same auto-sync as Ulric.

### Implementation notes (shared by both miracles)

- Both buff templates are registered into the global `BuffTemplates` (and mirror-written to `DeusPowerUpBuffTemplates` for the runtime merge path) at mod-load, unconditionally. This avoids the gated-registration-diverges-across-peers bug class (feedback_vt2_gated_registration_diverges.md) — buff template names are pre-allocated in `NetworkLookup.buff_templates` on every peer's machine before any lobby connection.
- Single consolidated `mod:hook("DeusRunController", "_try_buy_blessing", ...)` handles both blessings — VMF silently shadows duplicate same-method hooks (feedback_vmf_hook_safe_no_chain.md), so the branch-on-blessing_name pattern is mandatory.
- Non-ct peers in a ct host's lobby will crash on the rpc_add_buff for these buff names (same failure mode as any other ct-injected buff). This is consistent with existing ct buff-injection behavior — not a new regression class.
- The damage-reduction sign is NEGATIVE (`-0.25`) per the vanilla `ale_defence` pattern at `buff_templates.lua:5325-5333`. Engine accumulates negative multipliers as damage reduction.

### Altar / Chest / Arena-ammo dropdowns: explicit "Default" sentinel separated from literal 0

Pre-0.7.65, the four altar dropdowns (Upgrade / Melee Swap / Ranged Swap / Boon Altars) used `value = 0` to mean "Default — leave vanilla random distribution untouched." There was no way to force literally zero altars of a given type. Similarly, `cursed_chest_count` was a numeric slider 0–10 (default 1) where 0 meant "zero chests" with no separate "use vanilla" sentinel, and `arena_ammo_count` was numeric 0–10 (default 2) with the same limitation.

User intent: explicit per-dropdown choice between "let CW decide" (Default sentinel) and "force zero" (literal 0).

Changes:
- Altar dropdowns: `value = -1` is the new "Default" sentinel. `value = 0` is now a distinct option meaning "literally zero altars of this type." 1-9 still mean "force this many." `default_value` for all four widgets updated to `-1`.
- `cursed_chest_count` converted from numeric to dropdown with the same shape: -1 = Default (vanilla picks the count, defaults to 1/mission), 0 = no chests, 1-10 = override.
- `arena_ammo_count` converted from numeric to dropdown with -1 = Default (vanilla 2), 0 = no arena ammo, 1-10 = override.
- New `count_with_default_options` dropdown table at `_data.lua:351-365` for the wider-range chest/ammo widgets.
- `chaos_wastes_tweaker.lua` consumer hooks updated:
  - `get_deus_weapon_chest_type` (`:1045-1056`): explicit `as_count` helper maps sentinel→0 in the override distribution; `is_custom = any value not -1`. Default-state altars contribute zero to the override total.
  - `populate_pickups` (`:1393-1533`): same sentinel handling; cursed_custom / ammo_custom now key off "value not equal to -1" instead of "value not equal to vanilla default."
  - `_spawn_guaranteed_pickup` cap (`:2528`): sentinel -1 maps to vanilla 1.

Existing user settings stored as 0 will surface as "0 altars" / "0 chests" after this change rather than "Default." Re-pick "Default" if that's what you intended. Tooltip strings updated to document the new semantics (`altar_count_tooltip`, new `cursed_chest_count_tooltip`, updated `arena_ammo_count_tooltip`).

## 0.7.64-alpha (2026-05-19)

Fan-out fix release for issues surfaced in the 2026-05-19 3-player run (host Lyndsey, clients Amanda + user).

### Fixed: Holly DLC adventure-injected levels (Magnus / Cemetery / Forest Ambush) spawned ZERO pickups — no ammo, no healing, no grenades, no Chests of Trials, no altars, no locus

In the bugged run, magnus_belakor_path1 (the actual Belakor cursed mission) loaded and the entire map had nothing on the ground for ~20 minutes. Host log captured 13 PickupSystem spawn-debt warnings the moment the level loaded — every requested pickup type (deus_cursed_chest=4, deus_weapon_chest=7, deus_potions=30, deus_soft_currency=30, ammo=4, grenades=4, healing=4, level_events=8) ended up 100% unfilled.

Root cause: ct's `PickupSystem._can_spawn` hook (`chaos_wastes_tweaker.lua:2163`) only returned true for the three deus pickup categories (`deus_potions`, `deus_soft_currency`, `deus_weapon_chest`). The comment at the bottom of the hook claimed vanilla `_can_spawn` already handled the campaign categories (ammo/healing/grenades) "before our hook runs" — but that's wrong for adventure-injected levels under the deus mechanism: `Managers.mechanism:can_spawn_pickup` routes to the deus pickup whitelist which doesn't recognize campaign pickup names, AND the per-spawner `Unit.get_data(spawner, pickup_name)` check often fails for category-vs-specific mismatches (spawner is tagged "ammo=true" while pickup_name is `ammo_specific_X`).

Net result on the three Holly DLC levels: every spawn-pickup call was vetoed. Other CW maps still worked because vanilla CW pickup_settings only request the three deus types — the bug was latent until adventure-injected levels surfaced it.

Fix: the hook now also returns true on injected-adventure levels for any pickup_name matching a non-deus `Pickups[bucket]` entry. The existing filters for tome/grim, guaranteed_spawn, and triggered_spawn_id stay in place, so triggered barrels / scripted event spawners stay exclusive to their tagged pickup type (no regression of the v0.6.32 burn — barrels showing up as potions).

### Fixed: Belakor locus spawned on the WRONG mission (the first adventure-injected level with `force_belakor` on, not the actual Belakor cursed one)

Host log proves it: at 03:52:51 the locus altar spawned on `nurgle_slaanesh_path1` (node_1, curse=curse_greed_pinata). The actual Belakor cursed mission `magnus_belakor_path1` (node_12, curse=curse_belakor_totems) didn't even load until 04:03:02 — and never spawned a locus (in part because of the Holly-pickup bug above).

The predicate at `chaos_wastes_tweaker.lua:2107` checked `force_belakor` + `not _belakor_altar_spawned_this_level` + `AllPickups.deus_02`. Nothing in there cares which curse the current mission actually has. `force_belakor` only guarantees a Belakor curse appears SOMEWHERE in the run — it doesn't say where.

Fix: added `_current_node_is_belakor()` (`chaos_wastes_tweaker.lua:1629`) — reads `run_controller:get_current_node().curse` and returns true only when it equals `curse_belakor_totems`. Gated both the spawn-side predicate (`:2107`) and the existing `can_spawn_belakor_locus` override (`:2198`) on it. Now the locus only places on the actual Belakor mission, and the Holly-pickup fix above lets it actually spawn there.

### Reworked: Manann's Tempest cooldown is now a single toggle for BOTH boon and trait, default OFF

Previously: trait was gated by `tweak_manann_tempest_cooldown` (toggle, default off), but the boon variant was hard-capped at 8s unconditionally — opt-out only existed for the trait side. User intent was a single toggle that gates BOTH, default off (= vanilla on both).

Changes:
- `chaos_wastes_tweaker.lua:4024` — removed the `is_trait and` qualifier so the toggle now gates both branches before the proc fires. Separate per-source buckets (`boon_next_t`, `trait_next_t`) preserved so a player running both still gets one chain per 8s from each side.
- Localization updated: title is now "Rework: Manann's Tempest — 8s cooldown (boon + trait)"; tooltip clarifies both sources are gated. Boon-enable tooltip also updated to remove the stale "hard-capped" claim and direct to the rework toggle.

### Fixed: per-boon-scaling meta boons (`ct_meta_health`, stagger/crit/cooldown/ammo/movespeed) only updated on next mission load, not on every boon gain

Reported in last night's 3-player run (host Lyndsey, clients Amanda + user): grabbing "% max health per active boon" mid-run didn't lift the player's HP cap until the next mission. Confirmed for all six meta boons.

### Root cause

Same shape as the v0.7.57 `chain_lightning` cooldown fix. `register_meta_boon` (`chaos_wastes_tweaker.lua:3507`) and the special-cased `ct_meta_movespeed` block (`:3580`) both registered the granted-proc handler into `BuffFunctionTemplates.functions`, but the engine resolves `on_boon_granted` callbacks from the flat global `ProcFunctions` (`buff_extension.lua:1350`: `local buff_func = ProcFunctions[buff_func_name]`). Result: the granted proc was dead — VMF logged the registration but the runtime lookup returned `nil`.

The apply_buff_func IS read from `BuffFunctionTemplates.functions` (`buff_extension.lua:397`), so the apply path worked. That's why every meta boon's stack count refreshed correctly on the *next* mission (the engine reapplies all power-ups at level start, running apply fresh) but stayed stuck for the rest of the current mission.

Vanilla reference: `boon_meta_01_boon_granted` lives in `morris_buff_settings.lua:4929` inside `dlc_settings.proc_functions` (merged into `ProcFunctions` at `buff_templates.lua:9533`); `boon_meta_01_apply` lives at line 2024 in `dlc_settings.buff_function_templates`. Two separate tables — ct was only writing to one.

### Fix

Added a single line at each registration site: `proc_functions[granted_name] = proc`. Now the granted proc lives in both `BuffFunctionTemplates.functions` (harmless, unread) AND `ProcFunctions` (the table the engine actually queries). The apply path is unchanged.

Vanilla `PlayerUnitHealthExtension.update` (`player_unit_health_extension.lua:281-426`) recomputes `_calculate_max_health()` every server tick, writes the new total to the GameSession `max_health` game-object field, and rescales current HP when the cap changes (lines 348-360). So once the stack buff actually exists on the buff_extension, max-HP lifts and current-HP scales without ct needing to call any refresh API explicitly.

Affected boons:
- `ct_meta_stagger` (`:3417`)
- `ct_meta_crit` (`:3426`)
- `ct_meta_health` (the reported bug)
- `ct_meta_cooldown` (`:3444`)
- `ct_meta_ammo` (`:3452` — its `refresh_ranged_slot_buffs` apply path was already correct; the stack delta now lands on every boon gain)
- `ct_meta_movespeed` (`:3580`)

Network-sync note: `add_power_ups` triggers `on_boon_granted` both locally (`deus_run_controller.lua:1158`) and via `rpc_deus_add_power_ups` on the server (`:1402`). The idempotent loop in `_make_meta_proc` (`for _ = num_existing + 1, num_boons do buff_extension:add_buff(stack_name) end`) prevents double-apply when both fire.

NOT addressed in this fix: stack decrement on boon loss. ct never removes meta-boon stacks, only grows them. Not user-requested.

### Sync: `tweak_defeat_recovery` and `enable_campaign_potions` moved from per-peer to host-synced

Both were originally per-peer for historical reasons (the wipe-prevention is host-only, so the local penalty arm was per-peer; campaign potions are server-driven spawn so client mutation was irrelevant). User intent is "all settings sync to host," so both are now in `SYNCED_SETTING_NAMES`. The two call sites (`chaos_wastes_tweaker.lua:1038, 3194`) now read via `effective_setting`. `inject_adventure_maps` stays per-peer because it mutates `NetworkLookup.level_keys` which folds into lobby `combined_hash` and can't be re-evaluated post-boot.

### Fixed: curse/mission visual desync (different halos/lighting per peer for the same CW node)

In the 2026-05-19 run, three peers received the same lobby seed `-1029216815` but landed on completely different per-node level/curse/theme assignments because `inject_adventure_maps` toggle states differed across peers. The toggle mutates each peer's local `LEVEL_AVAILABILITY` arrays at module-load — `deus_populate_graph` then picks levels by index into those arrays, so identical seed × different arrays = different graphs. The toggle can't be moved to host-sync (it folds into `combined_hash` via `NetworkLookup.level_keys` count, sealed pre-handshake).

Fix: ct now broadcasts the host's RESOLVED graph after `deus_populate_graph` returns. Clients overwrite the picker-output fields in place — level, base_level, theme, curse, god, node_type, type, terror_event_power_up + rarity, mutators, minor_modifier_group. Topological fields (next, layout_x/y, run_progress, label) are deterministic from base_graph + seed and not shipped. Per-node JSON uses short keys (`l`/`b`/`t`/`c`/`g`/...) to keep payload tight: CW ~22-28 nodes × ~110 bytes ≈ 3.6 KB worst case, well under the existing 9-10 chunk envelope.

Implementation: new `ct_graph_snapshot_chunk` RPC mirroring the existing `ct_sync_host_settings_chunk` chunked-send pattern. Two apply sites — Phase A inside `deus_populate_graph` hook on the client's return path (common case), Phase B inside `DeusMapScene.on_enter` hook for late-arrival races where the RPC lost to the engine's `rpc_deus_setup_run`. In-place mutation preserves `_path_graph` table identity and `next` pointers. Host migration is NOT covered in v1 — new host's snapshot represents its pre-migration state; documented as known limitation. No NetworkLookup writes, no buff template — purely VMF string-keyed RPC, so old-ct peers silently drop the packet without crashing.

### Added: lobby mod-mismatch logging (`/peers` chat command + auto-broadcast)

Diagnostic tool for triaging post-session desync reports: each peer now logs a manifest at lobby join + on-demand via `/peers`. Manifest fields:
- `v`  ct version string (MOD_VERSION)
- `h`  FNV-1a hash of locally-configured SYNCED_SETTING_NAMES values (catches setting drift cheaply)
- `m`  list of enabled Workshop mods (id + name + last_updated timestamp) — the smoking gun for "your friend's halo is different"
- `vt` VMF workshop timestamp
- `nl` `#NetworkLookup.level_keys` (confirms adventure-injection state per peer)

Auto-broadcast: clients reply to the host's `ct_sync_host_settings_chunk` with a manifest packet. Host's log captures every joined peer's manifest right at the first reliable post-loading moment, with a DIFF line per peer flagging ct version / settings hash / num_levels / VMF timestamp / missing-or-extra mods relative to host. New `/peers` chat command lets any peer dump cached manifests + refresh-broadcast on demand.

Network safety: new RPC is VMF string-keyed (`mod:network_register`), NOT index-sequential — does NOT trip the gated-registration-diverges class of bugs documented in `feedback_vt2_gated_registration_diverges.md`. Old-ct peers silently drop the packet with no crash. Forward-compatible: future field additions just add new keys; missing fields decode as `nil`.

The 2026-05-19 desync would have been instantly diagnosable with this in place — the three peers' manifests would have shown identical mods but different `inject_adventure_maps` state (now fixed by the graph snapshot above), making the cause obvious from logs alone.

## 0.7.63-alpha (2026-05-19)

### Fixed: client crashed decoding `deus_power_up_templates` key 177 when host's buff RPC referenced a trait boon the client hadn't pre-registered

Verbatim crash from peer `1100001043e2511` (a client in lynnd's host session), reproduced in two consecutive dumps `2026-05-19-02.59.56-…` and `2026-05-19-03.08.36-…`:

```
scripts/network_lookup/network_lookup.lua:2514:
[NetworkLookup.lua] Table deus_power_up_templates does not contain key: 177
@scripts/managers/game_mode/mechanisms/deus_run_state_spec.lua:76: in function decoder
```

Same bug class as v0.7.60 (dormants) / v0.7.61 (trait-boon templates) / v0.7.62 (adventure-injected levels) — see `feedback_vt2_gated_registration_diverges.md`. Two registration sites still had a condition that could shift the sequential `NetworkLookup.deus_power_up_templates` ids between peers running the same ct version:

1. **`pre_register_trait_boon_lookups`** (`chaos_wastes_tweaker.lua:3718`) — wrapped the entire per-spec body in `if source_template and source_template.buffs`. If a peer's `BuffTemplates` happened to be missing one of the four vanilla source buffs (`always_blocking` / `deus_crit_chain_lightning` / `deus_extra_shot` / `deus_collateral_damage_on_melee_killing_blow`) at module-init time, that entire trait boon's NetworkLookup name + buff-template registration was skipped — shifting every subsequent power-up name's id by one.
2. **`ct_kill_heal`** (`chaos_wastes_tweaker.lua:3790`) — entire registration (including `register_power_up_in_network_lookup`, implicitly via `inject_dormant_boon`) wrapped in `if power_ups and buff_funcs and buff_funcs.functions`. If those globals weren't loaded yet on some peer's machine at the moment this module ran, ct_kill_heal got no NetworkLookup id at all on that peer — but it DID get one on peers where the globals were ready, again shifting the sequential id.

Either path produces "host has id N for boon X, client has id N for boon Y or no boon at all" — when host's `rpc_add_buff` reaches the client carrying id N, the strict `__index` on `NetworkLookup.deus_power_up_templates` raises uncatchable `error()` from inside the shared-state RPC decoder (bypasses pcall — `network_event_delegate.lua:52` doesn't xpcall the decode path).

### Fix

Decouple NetworkLookup name registration from the gated content writes. Both call sites now register the NetworkLookup names unconditionally up-front (in sorted order for trait boons, single-call for ct_kill_heal), then perform the buff-template / DeusPowerUpBuffTemplates / DeusPowerUpTemplates writes inside the existing `if globals_ready` guard. The name registration is what determines the sequential id; the side-table writes only affect whether the boon is actually castable in this peer's run. Same shape as the v0.8.66-dev LA fix for `pre_register_la_inventory_packages`.

Concrete edits:
- `pre_register_trait_boon_lookups`: moved `register_power_up_in_network_lookup(spec.name)` + `register_buff_in_network_lookup("power_up_" .. spec.name .. "_" .. spec.rarity)` into an unconditional first loop over the sorted CT_TRAIT_BOONS specs. The second loop still does the gated template clone + dpubt write.
- `ct_kill_heal do-block`: hoisted `register_power_up_in_network_lookup("ct_kill_heal")` + `register_buff_in_network_lookup("power_up_ct_kill_heal_exotic")` above the `if power_ups and buff_funcs` gate. The full template construction still runs inside the gate; only the lookup-id allocation happens unconditionally.

Both registration helpers (`register_power_up_in_network_lookup`, `register_buff_in_network_lookup`) early-out via `rawget` if the name is already present, so re-runs are no-ops — safe for `sync_host_dependent_state` to invoke without producing duplicate slots.

### Note on version skew

The fix guarantees deterministic indices for peers running the same ct version. Peers on DIFFERENT ct versions can still mismatch (e.g. one peer has a boon another doesn't), and there is no safe mod-side workaround for that — players need matching mod versions. The error message in the log is the canonical diagnostic if it recurs in a mixed-version lobby.

## 0.7.62-alpha (2026-05-18)

### Fixed: client joining a host's adventure-injected Deus run crashed at `state_loading.lua:449`

Same toggle-divergence bug class as v0.7.60 (dormants) and v0.7.61 (trait boons), one layer over: the per-mission registration in `_adventure_pool.lua`'s `inject_pool` (LevelSettings permutation clones, `NetworkLookup.level_keys`, `TerrorEventBlueprints`, `WeightedRandomTerrorEvents`) was inside the toggle-gated branch and only iterated `enabled_missions()`. A peer with the master toggle off — or with a specific mission's per-mission toggle off — never registered the corresponding `<adv>_<theme>_path1` keys. When the host then advertised `magnus_belakor_path1` (or any other unregistered permutation) over SharedState, the client's `state_loading.lua:449` did `LevelSettings[level_key]` and crashed with `attempt to index local 'level_settings' (a nil value)`.

`pre_register_adventure_lookups` now runs unconditionally at the top of `inject_pool` (which itself is called at mod-load and on setting change), iterating `_M.ADVENTURE_MISSIONS` in sorted-by-key order and writing each mission's six theme permutations into LevelSettings + NetworkLookup + TerrorEventBlueprints + WeightedRandomTerrorEvents via the extracted helper `register_mission_resolvables`. Sorted iteration matches the load-bearing rule in `feedback_vt2_gated_registration_diverges.md`: two ct peers must compute identical NetworkLookup indices regardless of which toggles each one has on.

Pool selection (the `DEUS_MAP_POPULATE_SETTINGS.LEVEL_AVAILABILITY` mutation + the `IS_INJECTED_ADVENTURE_LEVEL` flag that drives the tome-to-Chest-of-Trials swap) stays gated by master + per-mission toggles, so each user's own CW runs still reflect their preferences. The defensive registration is purely additive — every write is guarded by `not rawget(...)` so re-runs are no-ops.

The `LobbyAux.create_network_hash` shim (added v0.7.4) already nils injected `level_keys` entries during hash creation, so the always-on registration does not bump the lobby `num_levels` past vanilla and does not regress vanilla-host compat. Diagnosed from amand's session 2026-05-19 (`console-2026-05-19-01.00.42-c840d040-3b0b-4de6-880f-08cb990b26a6.log`) — host migration during a Belakor pilgrimage handed control to a client whose toggles didn't have `magnus_belakor_path1` registered.

## 0.7.61-alpha (2026-05-18)

### Fixed: same toggle-divergence bug class as v0.7.60, but for trait boons

The v0.7.60 audit caught the same shape one layer over: `register_trait_boon` for the four CT_TRAIT_BOONS (Vaul's Anvil / Manann's Tempest / Taal's Twinned Arrow / Asuryan's Wrath) early-outs on `effective_setting(spec.toggle)` before doing any registration. Two peers with different `enable_boon_*` toggles would therefore append a different ordered subset of `power_up_ct_boon_*_unique` entries to `NetworkLookup.buff_templates` and `NetworkLookup.deus_power_up_templates` — same crash and same wrong-buff failure modes as the pre-v0.7.60 dormants.

`pre_register_trait_boon_lookups` now runs unconditionally before the gated registration loop, building each spec's `DeusPowerUpTemplates` entry, writing the resulting `power_up_<name>_unique` buff template to `DeusPowerUpBuffTemplates` and `_G.BuffTemplates`, and appending both names to `NetworkLookup` in sorted (`spec.name`) order. The gated `register_trait_boon` below stays as-is and runs idempotent overwrites for the registration parts, then does pool injection if the toggle is on.

### Fixed: two `respawn_on_chest_complete` reads ran through raw `mod:get` instead of `effective_setting`

`DeusCursedChestExtension._set_state` hook fires on every peer locally (the is-server gate is several lines below the setting read). On a client whose `respawn_on_chest_complete` toggle differed from the host's, the diagnostic log and the early-return both reflected the client's local value instead of the synced host value. Real behavior gating only happens host-side so the wrong-bail had no functional effect, but the diagnostic was misleading and the gate's defensive-programming intent was wrong. Both reads now route through `effective_setting`.

## 0.7.60-alpha (2026-05-18)

### Fixed: dormant-boon toggle mismatch could crash clients on `rpc_add_buff`

Before this version, `sync_dormant_boons` only injected a dormant boon's buff template (`_G.BuffTemplates` + `DeusPowerUpBuffTemplates`) AND its `NetworkLookup` entries when the user had `activate_dormant_<name>` enabled. If a host activated `squats` (or any of the 9 dormants in `DORMANT_BOON_RARITY`) and a client had that toggle off, the host's `rpc_add_buff` for the squats buff would hit the client's `NetworkLookup.buff_templates.__index` on a missing key → fatal `Table buff_templates does not contain key: N` at `network_lookup.lua:2514`. Settings-sync alone (v0.7.59) couldn't fix this because the network table is frozen at boot — a runtime setting flip can't add entries after the fact.

`pre_register_dormant_lookups` now runs unconditionally at mod-load, iterating `DORMANT_BOON_RARITY` in sorted order. For every dormant it writes the buff template into `DeusPowerUpBuffTemplates` and `_G.BuffTemplates`, then appends `power_up_<name>_<rarity>` to `NetworkLookup.buff_templates` and `<power_up_name>` to `NetworkLookup.deus_power_up_templates`. Sorted iteration is load-bearing: with `pairs()`, two peers running the same ct version could theoretically register the same set in different orders and assign different network indices to the same name. After this change, every ct-running peer ends up with identical contents in identical positions regardless of which `activate_dormant_*` toggles they have on.

Pool injection (`DeusPowerUpRarityPool` / `DeusPowerUps` / `DeusPowerUpsArray` / `DeusPowerUpsArrayByRarity` / `DeusPowerUpsLookup`) remains gated by `activate_dormant_*`, so each user's offering pool still reflects their own preferences. The host's preference still wins via the v0.7.59 settings sync — clients see the host's pool composition during runtime. `sync_dormant_boons` is itself now sorted-iteration to match.

`pre_register_dormant_lookups` is purely additive: `register_buff_in_network_lookup` / `register_power_up_in_network_lookup` early-out on names already present, and `BuffTemplates[name]` is overwritten with an identical value when the toggled-on `inject_dormant_boon` runs later. No pool-side behavior changes for users who already had their preferred dormants enabled.

Clients without ct installed at all still cannot receive ct-injected buffs and will still crash on host `rpc_add_buff` for any ct-only buff. That class of mismatch is unfixable from inside ct — those peers must install ct (matching version) to be safe.

## 0.7.59-alpha (2026-05-18)

### Fixed: settings sync silently broken since v0.7.55 — host's settings never reached clients

v0.7.55 switched `ct_sync_host_settings` from three hand-picked scalar parameters to a single 105-entry table containing every synced setting. VMF's `mod:network_send` packs all user args into one JSON-encoded string parameter on the underlying `RPC.rpc_mod_user_data`, and Stingray hard-caps each RPC string parameter at 500 characters (`scripts/helpers/network_utils.lua:93` `STRING_MAX = 500`; same constant drives vanilla `shared_state.lua`'s own chunking). The full settings table JSON-encodes to ~4-5KB, so every host broadcast threw:

```
scripts/managers/mod/mod_manager.lua:627: Failed to pack parameter 3, too many characters in string with max length 500
```

The error fires inside VMF's safe-hook wrapper, so it never surfaced as a crash — clients just silently received zero host settings for three versions. The 500-char cap is a fixed engine constraint and is unaffected by `max_upload_speed` or `small_network_packets` (those control bandwidth/MTU, not parameter packing). Found from PrincessLyndsey666's host log after a Sigmar's Crag client crashed on `rpc_add_buff` with an unknown buff_template ID — a downstream symptom of clients running ct without host-synced injection toggles.

Fix mirrors the engine's own pattern in `shared_state.lua:288-330`: encode the payload to JSON, split into ≤400-char pieces, send each as `(session, seq, total, chunk_str)` via `ct_sync_host_settings_chunk`. Receiver buffers chunks per-sender and decodes when all chunks for the current session have arrived; a partial buffer from a stale broadcast is discarded the moment a new session id appears. 400-char chunks leave headroom for VMF's `[mod_id, rpc_id]` envelope (separate string parameter) plus the JSON array wrapper `[session, seq, total, "<chunk>"]` (~20 chars).

## 0.7.58-alpha (2026-05-18)

### Fixed: Belakor altar spawn fatals `Unit not found #ID[ee6ba7f91c666e61]` on adventure-injected levels

When `force_belakor` was on and the engine rolled a Belakor altar onto an adventure-injected mission's first remaining book spot, `World.spawn_unit("units/props/blk/blk_locus_01", ...)` hit the C-level assert at `c_api_world.cpp:67` because the unit wasn't in any loaded resource package. The locus prop ships in `resource_packages/levels/dlcs/morris/belakor_common`, which vanilla CW belakor-themed levels load via `level_settings_morris.lua`'s `theme_packages_lookup.belakor`. Our adventure-injection clones the adventure level's `packages` table and adds `morris_ingame` + the deus chest unit + DLC career packages — but not the belakor_common package, so the locus unit was unresolvable.

`build_permutation_packages` (`_adventure_pool.lua`) now appends `resource_packages/levels/dlcs/morris/belakor_common` to every injected permutation regardless of theme. `force_belakor` can ignite a Belakor altar on any theme via `_spawn_guaranteed_pickup`, so the package must be available unconditionally. Diagnosed via `crashify://142f40f3-d01d-4811-bd8b-e97272b8afcb` (entered `levels/dlcs/scorpion/alleys_heavens` aka Old Haunts as a Belakor pilgrimage); hash decoded by brute-forcing candidate unit paths through the bundle unpacker.

The `DeusRunController.can_spawn_belakor_locus` permit added in v0.7.51 + the `_spawn_guaranteed_pickup` slot grant added in v0.7.55 stay as-is — they correctly OPEN the spawn gate; v0.7.58 just ensures the asset exists when the spawn actually runs.

## 0.7.57-alpha (2026-05-16)

### Fixed: Manann's Tempest cooldown hook targeted the wrong table → VMF logged "trying to hook function or method that doesn't exist"

The v0.7.48 cooldown hook for `chain_lightning` targeted `BuffFunctionTemplates.functions`, but `chain_lightning` actually lives in the GLOBAL `ProcFunctions` table:

- morris_buff_settings.lua:131-2144 is `dlc_settings.morris.buff_function_templates` (the apply-callback category — that's where `apply_pockets_full_of_bombs_buff` lives, and why our `endless_bombs_consumes_morgrim` hook on the same target works).
- morris_buff_settings.lua:2145+ is `dlc_settings.morris.proc_functions` (event-driven procs — `chain_lightning` is at line 2563 in this block).
- At runtime BuffExtension consults `ProcFunctions[buff_func_name]` (buff_extension.lua:1350) — `BuffFunctionTemplates.functions.chain_lightning` is nil.

VMF logged the registration failure but kept loading (unlike the v0.7.53 crash that killed the entire mod), so this was a soft fail: Manann's Tempest cooldown gating just never engaged. Now hooks `ProcFunctions.chain_lightning` directly — both the boon variant (unconditional 8s cooldown) and the trait variant (gated by `tweak_manann_tempest_cooldown`) work as designed.

## 0.7.56-alpha (2026-05-16)

### Fixed: module-load crash since v0.7.53 silently disabled most of the mod

`v0.7.53` consolidated `_make_meta_apply` + `_make_meta_granted` into a single `_make_meta_proc` factory, but the special-cased `ct_meta_movespeed` registration at line ~3460 (separate from the loop because movespeed uses `apply_movement_buff` instead of stat_buff) was missed in the rename. At mod load, Lua raised `attempt to call global '_make_meta_apply' (a nil value)` — VMF aborted `mod_script` initialization at that point, so EVERY hook, registration, and binding after line 3463 silently never ran. That stripped:

- The four trait-as-boon registrations (Vaul's Anvil / Manann's Tempest / Taal's Twinned Arrow / Asuryan's Wrath boon variants)
- `ct_meta_movespeed` (Boon Bound Steps)
- `ct_kill_heal` (Khaine's Communion)
- The Home Brewer +50% potion-potency hook
- The Manann's Tempest 8s cooldown hook (the entire v0.7.48 feature)
- `endless_bombs_consumes_morgrim`
- The Ranger Vet save-grenade-block hook
- The defeat-recovery handler
- `mod.on_setting_changed` / `mod.on_disabled` (live updates and cleanup gone)
- **The host-side `sync_host_dependent_state` assignment** — meaning settings broadcast was partially broken too

Fix: switch `ct_meta_movespeed` to use `_make_meta_proc(stack_name)` (same as the loop-registered meta boons). Also renamed the inline sub-buff's `name` field from `"ct_meta_movespeed_stack"` to `"ct_meta_movespeed_stack_1"` so the proc's `num_buff_stacks(stack_name .. "_1")` delta-check finds the existing stacks (otherwise it would over-stack each grant, same shape as the Bug 2 from v0.7.53 but for movespeed).

If you've been on any v0.7.53–v0.7.55 build, an unknown swath of features were silently dead. v0.7.56 actually wires them all up.

## 0.7.55-alpha (2026-05-16)

### Changed: Belakor altar now spawns at a book pedestal alongside Chests of Trials on adventure-injected missions

Previously (v0.7.51) the altar was injected via `populate_pickups.primary.deus_02 = 1`, which placed it in a random ammo/healing/grenades primary spot. User asked for it to share the 5 book-spot budget instead — 3 tomes + 2 grimoires on every adventure level. The first `cursed_chest_count` book spots become Chests of Trials (default 1); the next book spot becomes the Belakor altar when `force_belakor` is on (one per mission). Remaining book spots stay hidden as before. Removed the populate_pickups inject and the `_can_spawn` allow-list for `deus_02` — both are unnecessary now that `_spawn_pickup` is invoked directly from the tome/grim spawner hook. The `DeusRunController.can_spawn_belakor_locus` override is still required because `_spawn_pickup` calls `pickup_settings.can_spawn_func`, which routes to `can_spawn_belakor_locus`.

### Changed: sync-all-settings by default — drop hand-maintained `SYNCED_SETTING_NAMES`

After repeated bugs caused by forgetting to add a setting to the synced-broadcast list (most recently: `disable_curse_*` helper bypassed the sync, `finale_dominant_god` / `force_belakor` weren't reaching clients, the `coin_multiplier` / `shrine_boon_count` / `chest_boon_count` / `bomb_boon_exclusive` / `disable_boon_*` / `ban_trait_*` / `tweak_home_brewer_potency` / `endless_bombs_consumes_morgrim` / `rv_no_save_morgrim` toggles all silently diverged on clients), the sync model is now opt-out instead of opt-in.

- `SYNCED_SETTING_NAMES` is built at module load by walking the data file's widget tree (`mod:dofile` + recursive visit of every leaf `setting_id`). Every setting the user can configure gets broadcast from the host to clients automatically.
- A small explicit `PER_PEER_SETTING_NAMES` excludes the three settings that are deliberately each-peer-local: `tweak_defeat_recovery` (per-peer locality is part of the design), `enable_campaign_potions` (server-driven spawn ignores client-side table mutation), `inject_adventure_maps` (lobby-hash-affecting, host/client must match at lobby-join time anyway).
- All the previously-direct `mod:get` callsites that should be host-authoritative now route through `effective_setting`: `coin_multiplier` (coin pickups now use host's multiplier), `shrine_boon_count` / `chest_boon_count` (boon picker counts match host), `bomb_boon_exclusive` (pool filter applies uniformly), `disable_boon_*` (boon pool filter), `ban_trait_*` (weapon trait filter), `tweak_home_brewer_potency` (potion potency scaling), `endless_bombs_consumes_morgrim` (Morgrim destroy-vs-drop), `rv_no_save_morgrim` (Ranger Vet grenade-save proc).
- `effective_setting` is now forward-declared near the top of the file so the early-running `on_soft_currency_picked_up` hook (line ~140) can capture the local slot at closure-creation time — without the forward-declare, that closure would have bound to a nil global.

Net effect: every UI setting in the mod menu now behaves host-authoritatively by default. Adding a new setting requires no bookkeeping — the broadcast picks it up automatically just by living in the data file.

## 0.7.54-alpha (2026-05-16)

### Fixed: `disable_curse_*` toggles weren't host-synced at the call site — client saw different curse text than host

`is_curse_disabled` read `mod:get("disable_curse_<name>")` directly instead of routing through `effective_setting`. Even though all 14 `disable_curse_*` keys ARE in `SYNCED_SETTING_NAMES` (so the host broadcasts them), this helper bypassed the sync and read each peer's local toggle. The two consumers (`MutatorHandler._activate_mutator`, `DeusMechanism.get_current_node_curse`) plus the `_transition_next_node` / `start_next_round` save-restore around `node.curse` therefore made decisions based on whoever-was-asking's settings, not the host's.

Symptom: gameplay-side mutator state could diverge between peers, and (the visible one) Holseher's map / mission-tooltip curse text on a client read the client's local toggle — host could see "no curse" while client saw the curse name, or vice versa, even though the actual mutator was the host's.

Fix: forward-declare `is_curse_disabled` near the top of the file (so existing call sites still bind correctly), assign the body just below `effective_setting`, and route the lookup through `effective_setting`.

## 0.7.53-alpha (2026-05-16)

### Fixed: Quiver Cascade (`ct_meta_ammo`, +5% total ammo per boon) did nothing in-game — two bugs

**Bug 1 (stale ammo cache).** `GenericAmmoUserExtension._apply_buffs` queries `apply_buffs_to_value(_original_max_ammo, "total_ammo")` once at AmmoExtension init and caches the result as `_max_ammo`. Adding new `total_ammo` stat_buffs after that point updates BuffExtension but doesn't bust the AmmoExtension cache, so the +5%-per-boon never showed up even when stacks were present. Fix: `apply_buff_func = "refresh_ranged_slot_buffs"` on the stack sub-buff (vanilla's canonical "I changed an ammo stat, recompute max_ammo" hook, used by Markus huntsman's passive and others; idempotent under repeated calls). `register_meta_boon` now propagates `apply_buff_func` from the spec into the sub-buff entry.

**Bug 2 (quadratic stack growth).** The `_make_meta_granted` proc queried `num_buff_stacks(stack_name)` to decide how many delta-stacks to add. But the actual stored key is `sub_buff_template.name`, which the factory builds as `stack_name .. "_" .. i` — so the query returned 0 every time and the granted proc re-added the full current boon count on every subsequent boon grant (triangular sum: after N additional boons the player had N(N+1)/2 stacks, not N). With Bug 1 masking everything visually, this went unnoticed.

Fix: consolidated apply + granted into a single `_make_meta_proc` that queries `num_buff_stacks(stack_name .. "_1")` (the first sub-buff's actual name) and adds only the delta. Same body for both procs so the result is idempotent regardless of fire order — vanilla `on_boon_granted` fires before the new boon's own apply, so the apply path handles the initial stack-up and granted handles incremental boons.

Other meta boons (stagger / crit / cooldown / health) ran the same buggy granted-proc, but their stat_buffs are queried per-use (not cached like total_ammo), so Bug 1 didn't apply and Bug 2 made them OVER-buffed rather than silently inert. Both are now fixed for every meta boon — expect previously over-buffed runs to feel "weaker" but correct.

### Fixed: finale_dominant_god override didn't reach clients — same bug shape as the v0.7.49 Belakor sync fix

The previous `_setup_run` hook flipped `dominant_god` only in host's local run state. `game_round_ended` (deus_mechanism.lua:551-619) reads `self._vote_data.dominant_god` into a local at the top and uses that single value for BOTH `_setup_run` AND `send_rpc_clients("rpc_deus_setup_run", ..., dominant_god_id, ...)`. The hook never reached the RPC payload, so clients populated their graph with the unmodified god.

Fix: hook `DeusMechanism.game_round_ended` and pre-mutate `self._vote_data.dominant_god` before vanilla runs; restore after. The mutation is host-only, gated on `reason == "start_game"`, and restores even if vanilla errors (pcall + rethrow). Vote_data persists on `self` until next mission-start, so restore-on-return is mandatory.

The `_setup_run` finale_dominant_god branch is removed since it was always redundant for the host and broken for clients.

## 0.7.51-alpha (2026-05-16)

### Added: Belakor altar (`deus_02`) spawns on adventure-injected campaign levels when host has "Always Include Belakor's Temple" on

Three coordinated changes route an altar into each adventure-injected map:

- `populate_pickups` injects `pickup_settings.primary.deus_02 = 1` (with proper save/restore so toggling the setting off cleanly reverts), gated on `on_injected_adventure_level() and effective_setting("force_belakor")`.
- `PickupSystem._can_spawn` adds `deus_02` to the allow-list for adventure-injected levels. The populate_pickups gate is the only place a request gets generated, so vanilla / non-belakor runs are unaffected.
- `DeusRunController.can_spawn_belakor_locus` returns true on adventure-injected levels when force_belakor is on. The vanilla gate rejects every non-belakor-themed node (campaign themes don't qualify), so without this the altar would still be vetoed at spawn time even after populate_pickups requested one.

`force_belakor` is now host-authoritative — added to the synced settings broadcast so clients use the host's value consistently across all three gates.

## 0.7.50-alpha (2026-05-16)

### Fixed: Moot Milk (Hangover Brew) alt rework slowed the player to 25% instead of +25%

The reworked Moot Milk's movement-speed sub-buff had `multiplier = 0.25` with `apply_buff_func = "apply_movement_buff"`. That function does `move_speed *= multiplier`, so 0.25 capped the player at 25% of base speed (a -75% slow) for the entire potion duration. Vanilla speed_boost_potion uses 1.5 for +50%; the intended +25% needs 1.25. Code comments / changelog have always advertised this as +25% — the value was just wrong since the rework shipped. Decanter-extended (`_increased`) variant inherits from the same builder, so it's fixed too.

## 0.7.49-alpha (2026-05-16)

### Fixed: clients couldn't see the Belakor curse on Holseher's map when host had "Always Include Belakor's Temple" on

Previously the `force_belakor` override was applied inside `DeusMechanism._setup_run`. That works for the host's own run state, but the upstream caller (`game_round_ended`) computes `with_belakor` BEFORE calling `_setup_run`, then re-uses that same outer-scope variable when it broadcasts `rpc_deus_setup_run` to clients. The hook never reached the RPC payload, so clients ran graph generation with `with_belakor=false` and rolled no Belakor nodes / no Belakor curse spread.

Fix: hook the upstream `BackendInterfaceDeusPlayFab.deus_journey_with_belakor` so the override happens at the source. Now both `_setup_run` and the RPC use the same modified value, and clients see the Belakor curse propagated through the graph.

Known related bug (NOT fixed in this version): `finale_dominant_god` has the same shape — the `_setup_run` hook flips the host's local `dominant_god` but the RPC keeps the original. Clients on a `finale_dominant_god`-overridden run see vanilla god distribution on their map. File a follow-up if this matters.

## 0.7.48-alpha (2026-05-16)

### Added: Manann's Tempest — 8s per-source cooldown

Wraps `BuffFunctionTemplates.functions.chain_lightning` to enforce a per-owner cooldown:

- **Boon variant** (the Unique-rarity Manann's Tempest boon, when its toggle is on) — always rate-limited to 1 chain per 8 seconds. No new toggle; the boon now ships with this cap baked in.
- **Trait variant** (the vanilla `deus_crit_chain_lightning` weapon trait) — new toggle `tweak_manann_tempest_cooldown` under Reworks > Reworks: Boons. Off (default) = vanilla (no cooldown, fires on every crit). On = 8s cooldown that mirrors the boon.

Boon and trait cooldowns are independent buckets per `owner_unit`, so running both gives you one chain per 8s from each side (matches the existing stacking design). The cooldown gate mirrors the proc's own ALIVE / first_hit / is_critical_strike check so it only consumes on procs that would actually have fired. Trait toggle is host-authoritative via the existing settings sync.

## 0.7.47-alpha (2026-05-16)

### Added: Rework — Killer in the Shadows potion lasts 2x as long

New toggle in Reworks > Reworks: Potions. Doubles the invisibility potion's duration: base 5s → 10s, increased 15s → 30s (Decanter then stacks on the increased variant the usual 50%, giving 15s/45s). Same `BuffTemplates` save-and-restore pattern as the Poison Proof duration rework — mutates `BuffTemplates.killer_in_the_shadows_potion.buffs[1].duration` + `_increased` at apply, restores on revert. Synced via the host-authoritative settings broadcast.

## 0.7.28b → 0.7.40-alpha (2026-05-15) — consolidated session log

Twelve versions in one session. Listed chronologically by version.

### 0.7.28b — Rework: Shard Strike duration nerf (configurable)
Toggle in Reworks > Reworks: Boons. Slider 1–16s controls the duration of Shard Strike's damaging stagger aura (vanilla 16s, overtuned at top tier). Mutates `WeaponTraits.buff_templates.armor_breaker.buffs[1].duration` + the global `BuffTemplates` mirror; save-and-restore so toggling off restores vanilla.

### 0.7.29 — Activate Dormant Boons feature
9 dormant boons (defined in source but never registered in `DeusPowerUpRarityPool`) get individual activation toggles. When enabled, the boon is injected into the rarity pool and all derived runtime tables (`DeusPowerUps`, `DeusPowerUpsArray`, `DeusPowerUpsArrayByRarity`, `DeusPowerUpsLookup`, `DeusPowerUpBuffTemplates`) using the same construction pattern as vanilla's registration loop at `deus_power_up_settings.lua:7121-7176`. Includes: Mathlann's Bounty, Bögenauer's Prosperity, Nethu's Relentlessness, Grungni's Gift, Hashut's Greeting, timed-block free shot, Smednir's Transmutation, Chotec's Touch, Squats. Dormants appear in `starting_boons` with `(Dormant)` suffix; pulled from `disable_boons` since they only roll when activated.

### 0.7.30 — 4 new Mod Boons (per-boon scaling)
Modeled on vanilla's `boon_meta_01` (Lileath's Favour). Each scales different stats per total active boon count:
- **Reactive Bulwark** (`ct_meta_stagger`) — +1% stagger power + 1% melee cleave per boon
- **Crit Cascade** (`ct_meta_crit`) — +1% crit chance + 5% crit power per boon
- **Vitality Cascade** (`ct_meta_health`) — +1% max HP + 1% healing received per boon
- **Ability Cascade** (`ct_meta_cooldown`) — +2% cooldown regen per boon

New "Mod Boons" boon-tree category. Localize hook routes the display name and description keys.

### 0.7.31 — Home Brewer +50% potency for reworked potions
When the player holds Home Brewer (the `not_consume_potion` perk), the Moot Milk rework's numerical multipliers scale by 1.5x for that drink. Implementation: hook `BuffExtension.add_buff`, save the template's multiplier/bonus fields, scale, call vanilla add, restore. Multiplayer-safe via per-peer perk check.

### 0.7.32 — New Mod Boon: Khaine's Communion
Exotic-rarity mod boon: heal 1 permanent HP on every enemy kill. Server-authoritative proc with `authority = "server"`; `DamageUtils.heal_network` with `heal_from_proc` heal type. Catalogued under Defensive > Health by effect, prefixed `(Mod Boon)` in display name.

### 0.7.33 — Addaioth's Splendour description fix
Vanilla in-game text said "Every 30 seconds, ranged Critical Hits explode for 10% of their Damage" but the actual implementation uses cooldown_duration = 10 and damage = 30% (vanilla swapped the values positionally when filling description_values). Static loc override via the existing `_G.Localize` hook returns the corrected string.

### 0.7.34 — Trait-as-Boon: 4 traits as opt-in Unique-rarity boons
Per user request, four weapon traits get optional boon variants (each behind its own toggle, default off):
- **Vaul's Anvil** — naturally non-stacks with the trait (binary perk)
- **Manann's Tempest** — stacks with the trait (each fires its own chain lightning per crit)
- **Taal's Twinned Arrow** — stacks (+2 projectiles if both held)
- **Asuryan's Wrath** — melee-only via the existing proc filter; stacks with the trait (~75% effective proc chance with both)

`register_trait_boon` clones the source trait's buff template, registers a new power-up template, and injects via `inject_dormant_boon` at Unique rarity.

### 0.7.35 — New Mod Boon: Wind Cascade
Exotic-rarity mod boon: +1% movement speed per active boon. Uses `apply_movement_buff` (the only function that actually moves the player's speed needle in vanilla — plain `stat_buff = "movement_speed"` isn't read by anything). Each stack compounds via `1.01^N`; at 1% per stack the compounding diff is tiny (10 stacks = +10.5% vs +10% additive).

### 0.7.36 — Rework: Anath Raema's Swiftness permanent
Swaps the trait's on-ammo-pickup-temporary `+50%` reload speed (10s window) for a permanent passive reload speed while the weapon (with the trait) is wielded. Mutates both `WeaponTraits.buff_templates.deus_ammo_pickup_reload_speed` AND `BuffTemplates.deus_ammo_pickup_reload_speed` with save-and-restore.

### 0.7.37 — Crash fix: dormant boons at "common" rarity
**Crash:** `deus_power_up_utils.lua:208: attempt to index a nil value`. **Root cause:** `DeusPowerUpRarities` is `{ event, rare, exotic, unique }` — only 4 valid boon rarities. "common" and "plentiful" are weapon-drop rarities, NOT boon rarities. I'd injected `squats` and `deus_larger_clip` at "common" → `existing_power_ups_lut["common"]` was nil → crash on next shrine after rolling either boon. **Fix:** moved both to "rare". Memory saved: `reference_vt2_deus_power_up_rarities.md`.

### 0.7.38 — Crash fix: NetworkLookup.buff_templates missing entries
**Crash:** `network_lookup.lua:2514: [NetworkLookup.lua] Table buff_templates does not contain key: power_up_deus_timed_block_free_shot_exotic`. **Root cause:** my `inject_dormant_boon` was registering the buff in `DeusPowerUpBuffTemplates` and `BuffTemplates` but NOT in `NetworkLookup.buff_templates`. NetworkLookup has a metatable that throws on unknown keys. **Fix:** new `register_buff_in_network_lookup(buff_name)` helper called for every injected buff.

### 0.7.39 — Rework: Defeat Recovery (soft wipe rescue)
When the team would wipe and the toggle is on: each peer's coins are zeroed, each peer loses 5 random boons, host force-respawns dead/disabled players. Mission continues from the wipe point (NOT a full level reload — engine doesn't expose a safe mid-run reload path). Fires once per level via `_defeat_recovery_triggered_this_round` flag; resets on `_transition_next_node`.

### 0.7.40 — Crash fix: NetworkLookup.deus_power_up_templates missing entries
**Crash:** `network_lookup.lua:2514: [NetworkLookup.lua] Table deus_power_up_templates does not contain key: ct_boon_asuryan_wrath`. **Root cause:** vanilla has TWO separate NetworkLookup tables for boons — `buff_templates` (fixed v0.7.38) and `deus_power_up_templates`. The latter is used for power-up selection RPCs (chest pick, boon offer, grant). My injected boon names weren't there. Triggered when picking ANY boon at a chest while having an unregistered injected boon as a current power-up — the chest's add-and-resync re-serialized the full power-up list, hit the unregistered name, errored. **Fix:** new `register_power_up_in_network_lookup` helper called at the top of `inject_dormant_boon` for every injected boon (dormants, meta boons, ct_kill_heal, trait-as-boon variants).

## 0.7.28a-alpha (2026-05-15)

### Added: Rework — Trait Tier by Rarity

New toggle in `Reworks` group. When on, every weapon roll and altar upgrade picks a trait combo whose ALL traits are eligible for the rolled rarity (per the user-confirmed tier table walked 2026-05-15; see `TRAITS_REFERENCE.md` for the full per-trait assignment).

**Tier assignments** (34 traits total):
- **T1 Common** (9): Off Balance, Resourceful Combatant, Heroic Intervention, Parry, Resourceful Sharpshooter, Inspirational Shot, Rhya's Thorns, Anath Raema's Swiftness, Myrmidia's Great Leveller
- **T2 Rare** (9 + 2 overlap): Regrowth, Barrage, Hunter, Thermal Equalizer, Heat Sink, Opportunist, Bloodthirst, Deadeye, Follow Up + (Scrounger, Conservative Shooter)
- **T3 Exotic** (4 + 6 overlap): Divine Shield, Shockwave, Huanchi's Fangs, Swift Slaying + (Scrounger, Conservative Shooter, Anatha Raema's Talons, Vaul's Tempo, Asuryan's Wrath, Addaioth's Splendour)
- **T4 Unique** (6 + 4 overlap): Shard Strike, Asaph's Endless Quiver, Quetzl's Repulsion, Manann's Tempest, Taal's Twinned Arrow, Vaul's Anvil + (Anatha Raema's Talons, Vaul's Tempo, Asuryan's Wrath, Addaioth's Splendour)

**Implementation** (`chaos_wastes_tweaker.lua`):
- `TRAIT_RARITY_POOL` table maps each trait → set of allowed rarity strings (`{ common = true, rare = true, ... }`)
- `get_tier_filtered_combos(item_key, rarity)` filters the weapon's `baked_trait_combinations` to combos whose all traits are eligible for the rolled rarity
- `override_traits_in_result(result, rarity)` overwrites `result.traits` with a random tier-eligible pick
- Extended the existing trait-filter hooks (`generate_weapon`, `generate_weapon_for_slot`, `upgrade_item`) to also post-process via `override_traits_in_result`, and added a new hook on `generate_item_from_item_key`

**Side effects of the toggle:**
1. **Traits now roll at ALL rarities** — vanilla `deus_weapon_generation.lua:166-169` only rolls traits at Exotic/Unique. Our override doesn't rely on the vanilla rarity gate (we filter the original `baked_trait_combinations` ourselves), so Common and Rare weapons get traits too. This addresses the user's earlier "every upgrade should offer a trait" wish — every upgrade now does, because every rarity has a pool.
2. **Upgrades effectively reroll the trait** — each upgrade re-picks from the new rarity's pool, so the trait changes on every upgrade. Fulfills the "guaranteed reroll on upgrade" sub-toggle request from the trait walk.

**No-op cases (preserves vanilla):**
- Toggle off → no behavior change
- Weapon has no tier-eligible combos at the rolled rarity → vanilla result kept (probably empty `traits`, same as before)

### Deferred to v0.7.28b
- "Rework: Shard Strike duration" (nerf the 16s damaging aura — configurable)

## 0.7.27a-alpha (2026-05-15)

### Disambiguating prefixes on every boon menu label

Long dropdowns in the disable/start trees were ambiguous — you couldn't tell at a glance whether a given checkbox was a disable toggle or a start-boon toggle, especially after scrolling past the parent group header. Every item and group title now carries a path-aware prefix:

| Widget type | Disable side | Start side |
|---|---|---|
| Item (e.g., Attack Speed) | `Disable Boon: Attack Speed` | `Starting Boon: Attack Speed` |
| Group (e.g., Properties) | `Disable Boons: Properties` | `Starting Boons: Properties` |

Bulk regex transformation applied via PowerShell on `chaos_wastes_tweaker_localization.lua`:

- 172 item labels prefixed on each side (344 total item transformations)
- 10 group titles prefixed on each side (20 total group transformations)
- Tooltips left untouched (`*_tooltip` keys correctly excluded via negative lookbehind)

No tree-structure changes in this phase. v0.7.27b will rebuild the 10-group structure into the new 21-category structure documented in `BOON_CATEGORIZATION_DRAFT.md`.

Backup of original localization preserved at `chaos_wastes_tweaker_localization.lua.v0726.bak` for quick rollback if needed.

## 0.7.26-alpha (2026-05-15)

### Renamed "Modified Boons" group to "Reworks"

Broadens the umbrella to include potion reworks (and anything else we add later that mutates vanilla mechanics). Existing settings (Khaine's Fury tweak, Movement Speed boon tweak, bomb boon cooldown, Morgrim's toggles) are unchanged — only the group label and `setting_id` are renamed (`modified_boons_group` → `reworks_group`). Player-facing settings persist correctly because their own setting_ids are unchanged; VMF keys user values by individual `setting_id`, not by group path.

### Added: Tweak — Poison Proof potion lasts 4 minutes

Doubles the Poison Proof (gas/poison immunity) potion's duration from 120s to 240s. With Decanter, the `_increased` variant extends from 240s → 360s (still +50% over the new base). Implementation mutates `BuffTemplates.poison_proof_potion.buffs[1].duration` and the `_increased` sibling directly at mod load; vanilla's `action_potion.lua:68` resolution picks up `_increased` when `buff_perks.potion_duration` is held, so Decanter composition is automatic.

### Added: Tweak — Hangover Brew alternative effect

Replaces Hangover Brew's (`moot_milk_potion`) vanilla dodge-distance/dodge-speed buff with a different effect package:

- +25% movement speed (apply_movement_buff on `move_speed`)
- Unlimited dodges (`buff_perks.infinite_dodge`)
- +40% stamina regen (`stat_buff = "fatigue_regen"`)
- 60-second duration (90 seconds with Decanter, via `_increased` variant)

The visual `screenspace_drink` activation/loop effects are kept so it still feels like a potion. Implementation replaces `BuffTemplates.moot_milk_potion.buffs` with a 4-buff array (FX + MS + infinite dodge + stamina regen) at mod load; mirrors for `moot_milk_potion_increased`. Save-and-restore pattern matches the other tweaks so toggling off restores vanilla.

### Known limitation: Home Brewer composition deferred to v0.7.27

User asked for Home Brewer to provide a +50% potency boost on top of the rework. Home Brewer in vanilla is `not_consume_potion` (chance to refund the potion), not a potency boon — so the tweak would need:

1. New `<potion>_potion_brewed` and `<potion>_potion_brewed_increased` variants registered in `BuffTemplates`
2. Each variant added to `NetworkLookup.buff_templates` (else RPCs in `action_potion.lua:74` fail)
3. A hook on `ActionPotion:client_owner_buff_function` (or similar) to swap to `_brewed*` when `not_consume_potion` perk is held
4. Numeric scaling at variant-build time (multipliers × 1.5)

That's a 1-2 hour effort with its own test cycle. Splitting it out keeps v0.7.26 small and verifiable.

## 0.7.25-alpha (2026-05-15)

### Boon menu re-categorization (round 2 of 2): Ability Cooldown + Orbs groups

Per user verdict, boons whose primary benefit is ability cooldown reduction now live in their own "Ability Cooldown" group, and orb-like boons (which would otherwise be lumped in with the upcoming Vermintide Skulls event content) get their own "Orbs" group. The "Skulls" group is reserved exclusively for Vermintide Skulls event boons going forward.

**New group: "Ability Cooldown"** (6 boons) — moved out of Properties / Utility & Team:

- From Properties: `ability_cooldown_reduction`
- From Utility & Team: `cooldown_on_friendly_ability`, `deus_cooldown_reg_not_hit`, `deus_cooldown_regen`, `deus_skill_on_special_kill`, `friendly_cooldown_on_ability`

**New group: "Orbs"** (5 boons) — moved out of Combat / Defense / Healing / Utility:

- From Combat: `focused_accuracy`, `static_charge`
- From Defense, Damage Reduction & Parry: `protection_orbs`
- From Healing, THP & Health Gain: `health_orbs`
- From Utility & Team: `sharing_is_caring`

Source groups (Properties, Combat, Defense/DR/Parry, Healing/THP, Utility & Team) lose those entries respectively. Both the `disabled_boons_group` and `starting_boons_group` mirror trees are updated in lockstep, and `recursive_sort` auto-alphabetizes the four new sub-groups by display name.

## 0.7.24-alpha (2026-05-14)

### Fixed: Khaine's Fury (`tweak_reckless_swings`) — damage tweak silently failed

User reported the Khaine's Fury softening tweak didn't actually soften the damage even with the toggle on. Root cause: the apply/revert functions were mutating `DeusPowerUpBuffTemplates.deus_reckless_swings_buff.buffs[1].damage_to_deal` — but the runtime buff system reads from the global `BuffTemplates` table, which received COPIED values via `DLCUtils.merge` at game boot (`buff_templates.lua:9532`). Mutating the source `DeusPowerUpBuffTemplates` had zero effect on what the proc function `deus_reckless_swings_buff_on_hit` actually read at hit time (`template.damage_to_deal` still 3).

Fix: mutate `BuffTemplates.deus_reckless_swings_buff.buffs[1].damage_to_deal` directly instead of the source `DeusPowerUpBuffTemplates`. The outer `health_threshold` tweak via `DeusPowerUpTemplates` was already correct (the apply path at `deus_power_up_utils.lua:250` reads that table directly), so it kept working — only the per-hit damage was uncorked.

Effect: with the toggle on, melee hits now deal 1 self-damage instead of 3, matching the displayed tooltip text. Host-side mutation suffices because the proc function is `is_server()` gated and damage is networked via `add_damage_network`.

## 0.7.23-alpha (2026-05-14)

### Diagnostic: verbose logging on chest-of-trials revive hook

User reports `respawn_on_chest_complete` isn't working. Setting was confirmed `true` in user_settings, hook registered correctly in last session's log, but no observable revives. Added `mod:info` lines to `DeusCursedChestExtension._set_state` hook so the next log shows:

- Whether `_set_state` fires at all, and which state value (verifies the hook isn't being shadowed and state OPEN is being reached).
- Setting value, `is_server` flag (verifies the host-only + setting-on gates pass).
- Per-slot dump at chest-open time: peer_id, `health_state`, `unit_alive`, `is_knocked_down`, `is_disabled_by_pact_sworn`.
- Whether `StatusUtils.set_revived_network` was called (knocked-down branch).
- Whether `pending_chest_respawn[peer]` was set (dead branch).
- Whether `game_mode:force_respawn_dead_players()` was called.

If chest-revive is working but not noticed (host-only hook + no dead teammates during testing), the log will show empty branches. If the hook isn't firing at all, that narrows the diagnosis to either wrong `state` value, missed `is_server` gate (testing as client), or shadowed hook. Strip the logging once root cause is fixed.

## 0.7.22-alpha (2026-05-14)

### Boon menu re-categorization (round 1 of 2)

Started reorganizing the 172-boon disable / starting-boon menus into more cohesive categories. Categories 1 and 2 done this round; remaining 5 groups TBD.

**New group: "Defense, Damage Reduction & Parry"** — aggregates 23 boons that were previously scattered across Properties / Combat / Healing & Sustain:

- From Properties: `block_cost`, `protection_aoe`, `protection_chaos`, `protection_skaven`, `push_block_arc`, `stamina`
- From Combat: `barkskin`, `deus_block_procs_parry`, `deus_damage_reduction_on_incapacitated`, `deus_parry_damage_immune`, `deus_push_cost_reduction`, `deus_standing_still_damage_reduction`, `deus_timed_block_free_shot`, `explosive_pushes_on_damage_taken`, `missing_health_power_up`, `pent_up_anger`, `skill_by_block`, `speed_over_stamina`, `static_blade`, `thorn_skin`
- From Healing & Sustain: `deus_knockdown_damage_immunity_aura`, `hidden_escape`, `protection_orbs`

**Renamed: "Healing & Sustain" → "Healing, THP & Health Gain"** with reshuffled contents:

- Gained: `health` (from Properties), `resolve` (from Combat), `deus_coin_pickup_regen` (from Utility & Team), `boon_supportbomb_healing_01` (from Bombs)
- Lost: the three boons moved to Defense/DR/Parry above

**Other moves (per user verdicts):**

- `last_player_standing_power_reg`: Combat → Utility & Team (user verdict — utility)
- `deus_push_charge`, `deus_push_increased_cleave`: stayed in Combat (user verdict — offense, even though they're push-related)

The `recursive_sort` helper now also auto-sorts the new `disable_boon_defense_and_dr_group` and `start_boon_defense_and_dr_group` alphabetically by display name. Both `disabled_boons_group` and `starting_boons_group` mirror trees have been updated in lockstep.

Categories still pending (TBD next session): Combat (further split into damage / crit / ranged / etc.?), Utility & Team, Bombs, Skulls & Sets, Talents, Properties. User to provide further verdicts.

## 0.7.21-alpha (2026-05-14)

### Added: Host→client settings sync (clients now see host's curse layout, not vanilla)

v0.7.20 fixed the shop_view nil crash by gating the `deus_populate_graph` hook on `is_server` — clients passed through to vanilla, never crashed. But clients still produced a VANILLA local graph while host produced a MUTATED one, so the map and theme on each peer differed (client saw wrong curse on a mission, wrong god on the map).

v0.7.21 replaces the `is_server` gate with proper sync:

1. **Host broadcasts effective settings** at the end of `DeusRunController.setup_run` via VMF's `mod:network_send`. Sent BEFORE the engine's `full_sync` RPC so clients receive the settings before their own `setup_run` triggers `deus_populate_graph`. Settings synced: `cursed_mission_count`, `replace_shrines_with_missions`, `disable_dominant_god`.
2. **Clients receive and stash** in a `_ct_host_settings` table via `mod:network_register("ct_sync_host_settings", ...)`.
3. **The graph hook uses `effective_setting(name)`** instead of `mod:get(name)`. On host this returns the user's actual setting; on client it returns the host's most-recently-broadcast value. If the broadcast hasn't arrived yet (first run, RPC ordering), falls back to vanilla-equivalent defaults — same safety as v0.7.20's gate.

Net effect: with host running e.g. `cursed_mission_count = 30, disable_dominant_god = true`, all peers now produce the same graph from the same seed. Map shows the same cursed nodes for everyone, themes match, no more "wrong curse on a mission" desync.

### Tweaked: Belakor lighting — brightened interior, slightly dimmed exterior

User feedback: Belakor interiors were almost pitch-black. Bumped `ambient_tint` from `{0.45, 0.40, 0.75}` to `{0.75, 0.65, 1.00}` (brighter purple-ish bounce), `ambient_tint_top` from `{0.35, 0.30, 0.80}` to `{0.60, 0.55, 1.00}` (brighter zenith), `secondary_sun_color` slightly brighter too. `skydome_tint_color` and `sun_color` dimmed slightly so the outdoor still feels oppressive. `exposure_mul` from 0.85 → 0.92 (less overall darkening).

## 0.7.20-alpha (2026-05-14)

### Fixed: `deus_shop_view_v2.lua:182: attempt to index field '_shop_config' (a nil value)` crash on client when host/client mod settings differ

Crash reported by user (client) when client had `replace_shrines_with_missions = true` (shops off, converted to missions) and host had it false (vanilla shops on).

Root cause: CW graph generation is deterministic from seed — both peers call `deus_populate_graph` independently (`rpc_deus_setup_run` triggers it on clients). Our hook fired on BOTH peers with their own settings:
- Host: hook saw `replace_shrines_with_missions = false`, no mutation, graph kept SHOP nodes with `level = "shop_strife"` etc.
- Client: hook saw `replace_shrines_with_missions = true`, converted SHOP→TRAVEL with `label = 0`, vanilla level picker then rolled a random TRAVEL level (e.g. `pat_mountain_wastes_path1`) for that node.

Host transitioned the run to the shop node and loaded `shop_strife.level`. Shop UI opened on both peers via flow events. Client's `DeusShopSettings.shop_types[<client's mutated level>]` returned nil → crash on the `_shop_config.blessings` index.

Fix: gate the entire `deus_populate_graph` hook behind `Managers.player.is_server`. Clients now pass straight through to vanilla; their local graph matches what host would have generated without our overrides. UI lookups won't nil-crash because every node has its vanilla level/type. Host's mutations still drive the authoritative shared state.

This same fix prevents future similar bugs from `cursed_mission_count`, `disable_dominant_god`, `filter_available_curses`, and any other graph-modifying override that has differing values between peers.

## 0.7.19-alpha (2026-05-14)

### No code changes — version bump to force Steam Workshop CDN refresh

Friend's subscriber client pulled v0.7.17 despite v0.7.18 being uploaded and the Steam Web API correctly reporting `file_size = 1,399,303`. Steam CDN edges can serve stale content for hours after a metadata update. Bumping MOD_VERSION (visible in chat echo) changes the bundle hash and forces fresh CDN propagation.

## 0.7.18-alpha (2026-05-14)

### Added: `disable_dominant_god` checkbox (default on)

The "all 4 gods rotate uniformly" behaviour from v0.7.14 is now a user-toggleable setting in the Run Structure group. Default on (matches v0.7.14+). Toggle off to restore vanilla CW's "dominant god is reserved for the finale, never appears on regular missions" rule. Independent of `cursed_mission_count` — works at any count value including 0.

### Tweaked: Curse-node exterior shading-env profiles softened (~30% pull toward neutral)

User feedback: Khorne, Nurgle, and Tzeentch exterior tints (sky / sun / ambient / fog) were "oppressive" — the outdoor color saturated the whole scene. Each value pulled approximately 30% toward neutral (1.0):

- Khorne fog `{1.55, 0.25, 0.20}` → `{1.39, 0.48, 0.44}` (less blood-bath)
- Nurgle skydome `{0.45, 1.30, 0.40}` → `{0.62, 1.21, 0.58}`
- Tzeentch sun `{1.55, 0.60, 0.20}` → `{1.39, 0.72, 0.44}` (less deep-orange punch)

Slaanesh and Belakor untouched (user said Slaanesh looks great; Belakor not flagged). Per-light point-light palettes also untouched — those are doing their job; the issue was just the overarching exterior color washing the scene.

## 0.7.17-alpha (2026-05-14)

### Tweaked: Tzeentch lights now 100% deep blue, outdoor light pushed to deep orange

User feedback v0.7.16: "more blue on tzeentch for sure — make all the lights and most of the natural lights a magic blue, but then have just the overarching outdoor light be a deep orange."

- **Per-light palette**: dropped the 10% cool-white slot. 100% of Light components are now deep magic blue (75% deepest cobalt, 25% mid cobalt variant). Caveat: vanilla torches that get their warm glow from particle FX / self-illumination materials (not from Light components) will still look warm — pulling those cool would need a separate hook on the particle effect registry. Holding off until you say it matters.
- **Outdoor shading env**: sun, secondary sun, and ambient pushed from "warm orange" to "deep orange" (R 1.40→1.55, G 0.75→0.60, B 0.35→0.20 on sun_color; same shape for ambient + ambient_top). Fog stays cool blue, sky stays cobalt. Result should read as: cobalt sky with deep-orange sunlight pouring through, hitting magic-blue rooms.

## 0.7.16-alpha (2026-05-14)

### Fixed: `terror_event_mixer.lua:1662: attempt to index a nil value` crash on adventure-injected nodes

Crash reproduced on a `nurgle_tzeentch_path1` node (Festering Ground under tzeentch theme). The level's flow fires `start_random_event("nurgle_end_event_loop")`, which evaluates `WeightedRandomTerrorEvents[level_key][event_chunk_name]` at terror_event_mixer.lua:1595. Our injected adventure permutation keys (`<base>_<theme>_path<n>`) don't have entries in `WeightedRandomTerrorEvents` (vanilla builds it from `LevelSettings` at boot, before our pool injects), so the lookup returns nil and the indexer crashes.

Same fix shape as the existing `TerrorEventBlueprints` mirror in `_adventure_pool.lua`: when injecting each permutation key, also mirror `WeightedRandomTerrorEvents[base_lvl]` to `WeightedRandomTerrorEvents[permutation_key]` if a base entry exists. Adventure end-event chunks now resolve to the same set the base adventure level uses.

## 0.7.15-alpha (2026-05-14)

### Tweaked: Tzeentch point lights are now all deep blue, no accents

v0.7.13 kept some magenta + mint in the Tzeentch per-light palette as variety. User feedback: too much mix; wants every mod-tinted point light to be deep blue, and the warm orange (already set on sun_color / ambient_tint in v0.7.13's shading env profile) to be the only source of warmth in the scene. Reduced palette to just two deep-blue variants + a tiny cool-neutral slot:

- 65% **deep cobalt** (saturated, darker than the v0.7.13 dominant — `{ 0.20, 0.35, 1.45 }`)
- 25% mid cobalt variant (`{ 0.30, 0.55, 1.35 }` — still deep blue, slightly varied)
- 10% cool white spark (`{ 1.00, 1.05, 1.15 }` — rare neutral)

No magenta, no mint, no warm orange in per-light. Vanilla torches stay warm naturally; warm orange ambient/sun comes from the shading-env profile.

## 0.7.14-alpha (2026-05-14)

### Fixed: `cursed_mission_count` override never gave Khorne curses when journey's dominant god was Khorne

User reported 4 runs in a row with no Khorne-themed cursed missions. Log confirmed: `dominant god <khorne>`, and the 13/13 cursed nodes were distributed nurgle/slaanesh/tzeentch only — the final node was the only one to receive a Khorne curse (`curse_khorne_champions` on `arena_ruin_khorne_path1`).

Root cause: vanilla `spread_curse` (deus_populate_graph.lua) reserves the dominant god exclusively for the "final" node (line 686-690) and then EXCLUDES it from the non-final rotation (line 698 — `if NO_DOMINANT_GOD or god ~= context.dominant_god then`). With dominant=khorne, the 12 non-final cursed nodes can only pick from {nurgle, tzeentch, slaanesh}.

Fix: when our count override is active, also set `config.NO_DOMINANT_GOD = true`. All 4 gods enter the uniform rotation. Final loses its "always dominant" guarantee but with `count >= total_curseable` it gets cursed anyway (by whichever god the rotation picks). Saved/restored alongside the other override fields.

## 0.7.13-alpha (2026-05-14)

### Tweaked: Tzeentch lighting — keep point lights cool, warm orange comes from sun/ambient

v0.7.11's Tzeentch palette added a 25% warm-orange complement to per-light tinting. User feedback: vanilla level torches are already warm orange, so adding more warmth to point lights double-saturates the warm channel without producing the contrast we wanted — Tzeentch nodes still read as "blue blue blue" with no real visual pop.

Better approach: keep per-light point lights all cool (blue / magenta / mint / white) and deliver the warm complement via the **sun_color + ambient_tint + secondary_sun_color** entries in the per-frame ShadingEnvironment profile. Daylight + skybounce pours warm orange across the scene; torches stay warm-orange (vanilla); magic point lights stay cool blue (mod). Net visual: cobalt sky lit by warm orange sun rays — strong color separation by light type.

Per-light Tzeentch palette is now blue-dominant: 55% cobalt blue / 20% magenta aurora / 15% cool white / 10% mint. No warm orange in the palette — that's the sky/sun's job now.

## 0.7.12-alpha (2026-05-14)

### Fixed: `cursed_mission_count` override didn't curse the very first nodes (run_progress=0)

v0.7.9-alpha lowered `CURSES_MIN_PROGRESS` to `0` so early nodes would be eligible — but vanilla's `get_nodes_above_progress` (deus_populate_graph.lua:45-55) uses **strict** `progress < node.run_progress`, so nodes with `run_progress = 0` got `0 < 0 = false` and stayed filtered out. User's v0.7.11 run: 14/16 cursed, the missing 2 were the first nodes at run_progress 0 / 0.16. Fix: set `CURSES_MIN_PROGRESS = -1` instead, so `-1 < 0 = true` and the first-mission nodes are in the candidate pool.

With `cursed_mission_count >= total_curseable`, this guarantees every node (including the first 1-2) gets a curse — what the user explicitly wanted.

## 0.7.11-alpha (2026-05-14)

### Tweaked: Curse light palettes — stronger contrast, added neutral white slot

v0.7.10's palettes were still too monotone on Tzeentch (the "cyan ice" complement was too close to its cobalt-blue dominant — visually "blue blue blue"). Rebalanced every god to:

1. **Drop dominant weight** from 50% → 35-40% so more lights pick up accents.
2. **Add a neutral white-ish slot** (15-20% of lights). User feedback that Slaanesh's purple looks good with white light sources generalizes — leaving some lights uncolored makes the colored ones register as deliberate accents instead of the whole scene saturating to one hue.
3. **Use true color-wheel complements** instead of nearby hues:
   - Khorne (red) → cold cyan (was warm gold)
   - Nurgle (green) → pustule magenta (was swamp teal — fine accent but not a complement)
   - **Tzeentch (blue) → warm orange** (was warm gold — orange is the true blue complement, 25% weight, much more contrast)
   - Slaanesh (pink) → yellow-green
   - Belakor (purple) → pale gold
4. Keep an accent slot of a related hue + a small "secondary pop" slot for visual variety in dim corners.

Distribution remains deterministic per light-index hash (`idx * 7919 + 11`), so the look is repeatable per level. The user can compare directly to v0.7.10 by re-entering the same cursed node.

## 0.7.10-alpha (2026-05-14)

### Improved: Cursed-node level lights use a per-curse palette instead of one flat tint

v0.6.x → v0.7.9 painted every level light in a cursed adventure mission the same RGB (e.g. all-blood-red for Khorne) — too monotone. Replaced with per-curse PALETTES: each god gets a dominant color plus accent / warm counterpoint / complementary contrast shades. Lights are deterministically distributed across the palette buckets (50% dominant / 25% accent / 10% warm / 15% complement), so adjacent lights tend to group but the room as a whole reads as themed atmosphere rather than monochrome.

Per-curse identity preserved:
- **Khorne**: blood red dominant, ember orange accent, gold-flame warm pop, cold steel-blue complement
- **Nurgle**: bog green dominant, jaundiced yellow accent, pustule magenta pop, swamp teal complement
- **Tzeentch**: cobalt blue dominant, magenta aurora accent, warm gold flicker, cyan ice complement
- **Slaanesh**: hot pink dominant, deep purple accent, teal yellow-green complement, peach warm pop
- **Belakor**: twilight purple dominant, moonlight blue accent, pale yellow-green ghost complement, shadow violet counterpoint

The distribution hash is stable across game loads (`(idx * 7919 + 11) % total_weight`) so the same level always lights the same way for a given curse — no per-frame rainbow noise.

## 0.7.9-alpha (2026-05-14)

### Diagnostic: cursed_mission_count=30 → 8 cursed nodes confirmed, halo invisible because of node-unit prefix matching

v0.7.8 diagnostic revealed `spread_curse` IS cursing 8 of 11 curseable nodes (so the override works); the visual is missing because `DeusMapScene.spawn_graph_units` (`scripts/ui/views/deus_menu/deus_map_scene.lua:182`) picks the 3D node mesh by string prefix on `node.level`:
- `pat_*` → TRAVEL_NODE_UNIT (has cursed-halo flow events)
- `sig_*` → SIG_NODE_UNIT
- `arena_*` → ARENA_NODE_UNIT
- else (e.g. `military_*`, `nurgle_*`, `farmlands_*`, `dlc_castle_*`) → SHRINE_NODE_UNIT (no halo flow events)

All 8 of the user's cursed nodes use adventure-injected level base names (`military` → Righteous Stand, `nurgle` → Festering Ground, etc.) which don't match any of the vanilla prefixes — so they all render as SHRINE_NODE_UNIT and the halo never appears.

The mod already has a `DeusMapScene.on_enter` hook that rewrites adventure-base level keys to `pat_<icon>_<theme>_path1` before the unit-spawn loop runs. That should fix the visual — but the diagnostic doesn't confirm whether it's firing for the user's graph. This release adds per-node log lines so v0.7.9's log will show exactly how many nodes the hook rewrites and which keys it skips.

### Fixed: `cursed_mission_count` override skips nodes below `CURSES_MIN_PROGRESS`

Same override block now also drops `CURSES_MIN_PROGRESS` to 0 for the duration of `func()`. Vanilla's filter (typically 0.2) was excluding the first 2-3 nodes of every journey from being cluster-center candidates. With `range=0` (exact count), those early nodes were guaranteed-uncursed even when the user set count=30. The user's v0.7.8 dump showed 3 uncursed nodes at progress 0/0.16/0 — all dropped by the filter. Lower it so the early run is also fair game. Saved/restored alongside the existing range/count fields.

## 0.7.8-alpha (2026-05-14)

### Diagnostic only: fix `count_cursed` to read the right field

v0.7.5 / v0.7.6's diagnostic counted nodes by `n.type == "TRAVEL"` etc., but the completed graph returned by `deus_populate_graph` uses `n.node_type` ("ingame"/"shop"/"start") — `type` only lives on the BASE graph (input). My counter never matched any node and reported `cursed=0 / total_curseable=0` on every run, including ones that almost certainly had curses applied. Switched to `n.node_type == "ingame"` and added a `dump_graph` helper that logs EVERY node (cleanly tagged) so we can see the real state. Re-run with v0.7.8 to get accurate cursed-count numbers.

## 0.7.7-alpha (2026-05-14)

### Added: `tweak_boon_movespeed` — double the Movement Speed property boon (5% -> 10%)

New checkbox in the Modified Boons group. The Movement Speed boon is a one-of-a-kind reward awarded on mission completion in Chaos Wastes (boon-treated, not a buff stack). Vanilla `MorrisBuffTweakData.movespeed` is `{ description_value = 0.05, multiplier = 1.05 }`. `deus_power_up_settings.lua` bakes both into runtime tables: the multiplier into `DeusPowerUpBuffTemplates.power_up_movespeed_{common,rare,legendary}.buffs[1].multiplier` (1.05 in all three rarity entries), and the description_value into `DeusPowerUpTemplates.movespeed.description_values[1].value` (single 0.05 entry, referenced by all rarities). The tweak save-and-restores both: writes 1.10 to each rarity's multiplier and 0.10 to the description value. The in-game tooltip auto-reflects "10%" because vanilla `description_properties_movespeed` is formatted off `description_values`.

Mirrors the reckless_swings pattern: forward-declared `sync_boon_movespeed`, called from the boon-roll hook (post-call), `on_setting_changed`, and at mod load; reverted from `on_disabled` so toggling the mod off cleans up the persistent DeusPowerUpBuffTemplates / DeusPowerUpTemplates mutations.

## 0.7.6-alpha (2026-05-14)

### Diagnostic only: extended `deus_populate_graph` logging for the `cursed_mission_count` debug

v0.7.5-alpha added a `post-run cursed=N / total_curseable=M` log but only in the `replace_shrines_with_missions = OFF` branch. The user's failing scenario has the toggle ON, so the log never fired. This release moves the count + dumps every curseable node's `curse`, `god`, `progress`, and `level` so we can see exactly which nodes ended up cursed and which were skipped. No behavior change otherwise.

## 0.7.5-alpha (2026-05-14)

### Improved: Cursed-node atmosphere lighting (richer per-curse profiles)

v0.7.2-alpha's curse sky tint applied one flat RGB multiplier across every shading variable, so e.g. a Khorne node became a single saturated red blanket. Replaced with per-curse PROFILES that tint each shading-environment variable differently — sky, sun, secondary sun, ambient, ambient top, fog, and exposure all get their own multiplier per curse. The result reads as themed atmosphere ("sunset over a burning landscape", "rotten daylight in a bog") rather than a single-color filter.

Color identity is preserved: red Khorne, green Nurgle, blue Tzeentch, pink Slaanesh, dark purple Belakor. But each curse gets accent variation (e.g. Khorne sun is warm orange against a deep red sky; Tzeentch sun has a magenta-aurora glow against cobalt sky).

### Added: Diagnostic logging on `deus_populate_graph` (cursed-mission count debugging)

User reported `cursed_mission_count = 30` produced zero visibly-cursed nodes on Olesya's map. Adding two `mod:info` lines to the existing `deus_populate_graph` hook to confirm (a) the override was read correctly and applied, and (b) how many cursed nodes vanilla's `spread_curse` actually produced in the completed graph. Both log under the `[deus_populate_graph]` prefix.

## 0.7.4-alpha (2026-05-14)

### Fixed: `Join failed - Game version mismatch` when peer has Adventure Maps injection on

Symptom: a player with `inject_adventure_maps` enabled couldn't join a friend hosting without it (or any vanilla lobby) — Steam reported "Game version mismatch" even though mod versions, network_hash, trunk_revision, and engine_revision were all identical between peers.

**Root cause.** VT2's `LobbyAux.create_network_hash` (lobby_aux.lua:26) folds `num_levels = #NetworkLookup.level_keys` into the lobby `combined_hash` that all peers compare at join time. Our `_adventure_pool.lua` registers a new level_keys entry for every injected adventure permutation (each enabled campaign / event mission × 6 themes — see `register_network_lookup_key`); without that registration the multiplayer level-load RPC fatals on a strict `__index` ("Table level_keys does not contain key"). The cost: vanilla `num_levels` ≈ 582, fully-injected ≈ 774. Peers with mismatched counts produced different `combined_hash` values and the matchmaker rejected the join.

Concretely from the failing-join log: client `combined_hash=528235b057837034 num_levels=774` vs host `combined_hash=d0ec3cbd18a2bce0 num_levels=582`, with every other hash input identical.

**Fix.** Hook `LobbyAux.create_network_hash` and temporarily nil out the injected `NetworkLookup.level_keys` entries (indices strictly greater than the vanilla count, captured once at mod load before `inject_pool` runs) for the duration of the call, then restore. Lua's `#` operator returns the contiguous-prefix length, so the vanilla hash-creation code sees vanilla `num_levels` regardless of how much we've injected. Entries are restored before the hook returns so the in-game level-load RPC, which indexes the same table, continues to work.

**Effect.**
- Peers with `inject_adventure_maps` on can join vanilla or non-matching peer lobbies. Hash matches.
- Peers hosting CW with injection on advertise a vanilla lobby hash, so vanilla peers can also join.
- Vanilla CW scenarios play correctly cross-config. The host's `LevelSettings` lookup uses string keys that exist in both configurations.

**Caveats.**
- Picking an injected adventure mission as host while a vanilla peer is in the lobby still crashes the vanilla peer: their `NetworkLookup.level_keys` doesn't contain the injected permutation key, so the level-load RPC fatals on the strict `__index`. Workaround for now: when hosting cross-config, pick a vanilla CW scenario, not an injected adventure node. A future revision could surface peer-side mod state in lobby_data to gate injected-level selection automatically.
- Other mods that legitimately register new `NetworkLookup.level_keys` entries would also be hidden by this shim. If you ever add such a mod, change `_vanilla_level_keys_count` to capture a baseline that includes those entries (or move ct's capture into a deferred init that runs after all level-mutating mods have loaded). Not a problem today — no sibling mod in the active set touches `level_keys`.

Reference: memory entry `reference_vt2_lobby_combined_hash.md` documents the full hash composition and `num_levels` source. The shim follows the pattern from `feedback_vmf_hook_safe_no_chain.md` (single mod:hook on `LobbyAux.create_network_hash` so no chain-shadow risk).

## 0.7.3-alpha (2026-05-14)

### Fixed: `[NetworkedFlowStateManager] Too many object states(512)` crash

Vanilla Fatshark bug. `NetworkedFlowStateManager.clear_object_state` (networked_flow_state_manager.lua:493) nils `_object_states[unit]` when a unit is destroyed but **never decrements `_num_states`**. The counter is monotonic — `_num_states` only grows, and the run fatals once it hits `_max_states` (512). Every destroyed unit that ever held a networked flow state permanently leaks its slot.

Hits hardest in CW runs with adventure-mission injection + curses: the `cursed_chest_objective_unit` buff is applied to every cursed-chest enemy spawn (`apply_objective_unit` in morris_buff_settings.lua:614) which spawns a `units/hub_elements/objective_unit` carrying a `chest_open_state` networked flow state. Each enemy = 1 permanently-leaked slot. Reproduced ~40 min into a Verminious Dreams khorne node after 2 Chests of Trials were activated (crash dump `console-2026-05-14-03.23.33-d86fd894-...`).

Fix: hook `NetworkedFlowStateManager.clear_object_state` to count the states being released and subtract from `_num_states` before delegating to vanilla. One-line vanilla-bug patch.

## 0.7.2-alpha (2026-05-13)

### Added: Curse sky / atmosphere tinting on adventure missions

The per-light tint from v0.6.x only colored individual point/spot lights — adventure-level skies, sun, and atmospheric fog stayed vanilla, so cursed adventure missions looked "too normal." This release adds per-frame multiplicative tinting of the live ShadingEnvironment.

Pattern lifted from Peregrinaje (bundle-unpacked from Workshop install — file 92BC0C4E7BFF8C3A.lua referenced `ShadingEnvironment.set_scalar`, `skydome_tint_color`, `sun_color`, `secondary_sun_color`, `ambient_tint`, `ambient_global_tint`, `fog_color`, `exposure`, `apply_environment_variables`). Implementation:

- `hook_safe` on `CameraManager.shading_callback` so we run AFTER vanilla `MoodHandler.apply_environment_variables` (camera_manager.lua:346) — our curse tint multiplies the post-mood color.
- Gates: only fires on injected adventure levels with a non-`wastes` node theme (khorne/nurgle/tzeentch/slaanesh/belakor).
- Variables tinted: `skydome_tint_color`, `sun_color`, `secondary_sun_color`, `ambient_tint`, `ambient_tint_top`, `fog_color`.
- Per-curse multipliers tuned to be visible without flattening the scene.
- No save/restore: Stingray re-seeds the shading_environment from the level's baked template every frame, so leaving the cursed node automatically restores vanilla atmosphere.

## 0.7.1-alpha (2026-05-13)

### Fixed: Chest of Trials no longer interactable

v0.6.28–v0.7.0 hooked `_spawn_pickup` to mutate the chest's physics actors (scene_query / collision_filter / collision_enabled) in an attempt to make altars/chests walk-through on adventure levels. Each variant broke chest interaction. Reverted the entire actor-manipulation hook.

Researched the Peregrinaje mod's source (bundle-unpacked from Workshop install): Peregrinaje does NOT touch chest collision — it relies on vanilla pickup-spawn flow with `with_physics = false`, which destroys an actor named `"pickup"` via `PickupUnitExtension.set_physics_enabled` (pickup_unit_extension.lua:125-135). That actor is only a small trigger zone though; the chest's main collision body stays. In vanilla CW the level designer places altars/chests in alcoves so they're never on the path — there is no engine mechanism that makes them walk-through on demand.

Accepting that altars/chests can block on adventure-level injections (per user direction: "give up on collisions"). The chests are now back to interacting properly.

### Fixed: Campaign potions appearing when `enable_campaign_potions` is off

Defensive cleanup at the top of `populate_pickups`: when the toggle is off, scrub `damage_boost_potion`, `speed_boost_potion`, `cooldown_reduction_potion` from `Pickups.deus_potions` every call. Guards against a mid-flight error in a previous (toggle-on) call leaving the campaign-potion clones in the table.

## 0.7.0-alpha (2026-05-13)

First experimental public release. Marks the formal opening of the mod to a broader audience after months of internal iteration. Title changed to "Tweaker: Chaos Wastes" (was "Tweaker: Chaos Wastes (WIP)"), Workshop description rewritten to cover the full feature surface, new thumbnail in place.

Headline since the last released build: the **Adventure Maps in Chaos Wastes** subsystem. Adventure missions are now injectable into the CW random map pool with full mission lifecycle (curses, boons, finale routing) intact: tomes/grims become Chests of Trials, pickups rewrite to CW types, altars seed at 5/map (1 upgrade + 1 melee swap + 1 ranged swap + 2 boon), cursed nodes carry the matching sky/lighting tint, and altars/chests use `filter_trigger` so the player walks through them.

## 0.6.33-dev (2026-05-13)

### Fixed: Event barrels spawning as potions (broke scripted events)

`_can_spawn` hook was returning true for `deus_potions`/`deus_soft_currency`/`deus_weapon_chest` on EVERY adventure spawner (except tome/grim), including **triggered event spawners** for scripted lamp_oil / explosive_barrel / training_dummy_bob spawns. `_spawn_guaranteed_pickup` iterates all pickup names asking `_can_spawn` for each, then picks randomly from candidates — so a triggered barrel-spawner could roll `healing_draught` instead of `lamp_oil` and break the scripted event.

Fix: in the `_can_spawn` adventure-fallback, also short-circuit to `false` when:
- `Unit.get_data(spawner, "guaranteed_spawn")` is truthy (book / specified spawners)
- `Unit.get_data(spawner, "triggered_spawn_id")` is a non-empty string (event-driven spawners)

CW types still flow onto generic primary spawners (the ones without any specific event tag) so coin / potion / altar counts are unaffected.

## 0.6.32-dev (2026-05-13)

### Fixed: Chest of Trials interaction broken in v0.6.28+

v0.6.28's `Actor.set_scene_query_enabled(actor, false)` made altars/chests walk-through BUT broke interaction with them. Cause: `GenericUnitInteractorExtension._find_best_interaction_unit` (interactor extension line 254) discovers interactables via `PhysicsWorld.immediate_overlap(..., "collision_filter", "filter_overlap_interaction")` which needs scene_query=true on the actor. The "proximity check" assumption in the v0.6.28 comment was wrong — interaction discovery is scene-query-driven.

Fix: revert scene_query disable. Instead, reclassify the actor's collision filter to `filter_trigger` via `Actor.set_collision_filter` — the vanilla "non-blocking interactable" filter (see `ai_utils.lua:521` for the canonical pattern). The player_mover sweep ignores `filter_trigger` actors so the player walks through; raycast overlaps still hit them so interaction works.

`set_collision_enabled(false)` is also kept as belt-and-braces but the filter change is the load-bearing piece.

## 0.6.31-dev (2026-05-13)

### Fixed: Exact cursed-mission count

Setting `cursed_mission_count` was driving `CURSES_HOT_SPOTS_MIN/MAX_COUNT` only, but vanilla `spread_curse` (deus_populate_graph.lua:681) then *spread* each cluster center to neighbouring nodes within `CURSES_HOT_SPOT_MIN_RANGE..MAX_RANGE`, so requesting N would typically yield 5–15 cursed nodes. Fix: when the override is active, also force `CURSES_HOT_SPOT_MIN_RANGE = MAX_RANGE = 0` so each cluster curses only its center node. Both ranges are saved before the override and restored in `restore_curse_count` so vanilla CW spread behaviour returns intact when the setting is back to 0.

## 0.4.1-dev (2026-05-10)

### Fixed: `<<1>>`..`<<9>>` in altar count dropdowns

The four altar-count dropdowns (Upgrade / Melee Swap / Ranged Swap / Boon Altars) showed `<<1>>` through `<<9>>` instead of plain `1`–`9`. Cause: `altar_count_options` used `text = "1"`..`"9"` as labels, expecting VMF to fall through to the literal string when no loc entry matched. VMF actually wraps missing keys in `<<>>`. Fix: added explicit `["1"]` … `["9"]` entries in `_localization.lua`. Updated the misleading comment in `_data.lua` to document the real VMF behaviour.

## 0.4.0-dev (2026-05-10)

### Added: Bomb-boon balance toggles

Four new toggles in **Modified Boons** group, sourced from a community balance thread:

- **Bomb Boon Cooldown (s)** — uniform cooldown override for the *Drop bomb on ability use* boon. Vanilla per-item cooldowns are 180s (Rally Flag), 180s (Morgrim's Bomb), 120s (Endless Bombs Potion); a single positive value here applies uniformly to all three. 0 = vanilla. Implemented by mutating `DeusPowerUpTemplates.drop_item_on_ability_use.buff_template.buffs[1].cooldown_durations` (read at proc time in `morris_buff_settings.lua:2830`). Mirrors the Khaine's Fury save-and-restore pattern; reverts on `on_disabled` and re-applies on setting change.

- **Bomb Boons Mutually Exclusive** — once any bomb boon is owned (`drop_item_on_ability_use` or `deus_grenade_multi_throw`), other bomb boons are stripped from the random pool for the rest of the run. Implemented inside the existing `generate_random_power_ups` save-and-restore filter (the third hook arg is `existing_power_ups`); piggybacks on the same removed-then-restored pool list.

- **Endless Bombs Consumes Morgrim's** — when the Endless Bombs potion is drunk, any saved Morgrim's Bomb is permanently destroyed instead of dropped on the ground. Hooks `BuffFunctionTemplates.functions.apply_pockets_full_of_bombs_buff` and calls `destroy_slot("slot_level_event")` only when the slot item is `holy_hand_grenade`; other level-event items keep vanilla drop behaviour.

- **Block Ranger Veteran from Saving Morgrim's** — RV's `bardin_ranger_passive_consumeable_dupe_grenade` (10% chance not to consume on grenade throw, applied via `not_consume_grenade` proc stat_buff) cannot fire when the thrown grenade is a Morgrim's Bomb. Hooks `ActionChargedProjectileUtility.fire_charged_projectile`; instance-level monkey-patch of the buff_extension's `apply_buffs_to_value` for the duration of the call (with `rawget`-aware restore through `__index`), gated on `projectile_context.item_name == "holy_hand_grenade"`.

## 0.3.9-dev (2026-05-09)

Version bump for batch deploy. No behaviour changes since 0.3.4-dev — the gap reflects internal version increments during cross-mod work that didn't land separate CW changes.

## 0.3.4-dev (2026-05-01)

### Fixed: Banned Weapon Traits list

The previous list had 20 entries, of which **7 were no-ops** because the names didn't match any real CW weapon trait: `increased_punch_through`, `off_balance`, `power_vs_skaven` (a property, not a trait), `resourceful_combatant`, `scrounger` (a deus weapon theme name), `shockwave` (also a theme), `swiftslaying`. The other 13 silently missed real traits like Swift Slaying, Shockwave, Off Balance, Piercing Projectiles, Resourceful Sharpshooter, etc. — so users couldn't actually ban those.

Replaced with the **31 real traits** that appear in `DeusWeapons[*].baked_trait_combinations`, dumped via the new `dump_traits` command and labeled with Fatshark's official display names + descriptions as tooltips. Banned-trait setting names now match `WeaponTraits.traits[name]` keys exactly, so the runtime check `mod:get("ban_trait_" .. trait)` actually fires.

## 0.3.3-dev (2026-05-01)

### Added: `dump_traits` command

New console command lists every weapon trait that can roll on any CW weapon (union of `DeusWeapons[*].baked_trait_combinations`), resolving each trait's `display_name` and `advanced_description` via `Localize()`. Used to gather the official Fatshark text needed to give the Banned Weapon Traits options proper labels and tooltips.

## 0.3.2-dev (2026-05-01)

### Fixed: `<<key>>` placeholders in mod options menu

40 boon-disable / starting-boon widgets referenced tooltip keys (`disable_boon_squats_tooltip`, `start_boon_squats_tooltip`, `..._deus_power_up_quest_granted_test_01_tooltip`, and all 36 `*_talent_N_M_tooltip`) that were never defined in `_localization.lua`. VMF rendered the unresolved keys as raw `<<key>>` strings on hover. Removed the broken tooltip refs from the widgets — the labels themselves were already auto-generated stubs (`"Talent 1 1"`, `"Squats"`, etc.) with no descriptive text to put in tooltips.

## 0.3.0-dev (2026-05-01)

### Fixed: Campaign potions in CW now actually spawn

The `enable_campaign_potions` toggle never produced visible results because the patch shared the campaign potion settings tables by reference. Engine-startup normalization (in `pickups.lua`) divides each entry's `spawn_weighting` by the sum of its group, so campaign-potion entries had weights ~3× the CW potions. The random sampler iterates with `pairs()` and breaks on the first cumulative weight that hits the random value (in `[0,1)`); the CW potions consistently exhausted that range first, so campaign potions never got picked. Fix: clone the entries and override their `spawn_weighting` to match the CW potion scale.

### Fixed: Boon labeled as "Reckless Swings" is actually called "Khaine's Fury"

Renamed the modified-boon toggle to "Tweak: Khaine's Fury" to match the in-game display name.

### Changed: Altar count defaults are now 0 = vanilla random

`chest_upgrade_count`, `chest_swap_melee_count`, `chest_swap_ranged_count`, and `chest_power_up_count` now default to 0 (leave vanilla distribution untouched). Range expanded from 0–8 to 0–9. Setting any of the four to a non-zero value still replaces the entire chest distribution; types still at 0 produce no altars of that type.

## 0.2.5-dev (2026-04-28)

### Added: Disabled Boons

All 172 boons can now be individually disabled from appearing at shrines, chests, altars, and Belakor's Temple. Boons are organized into 6 sub-groups: Properties, Talents, Skulls & Sets, Combat, Healing & Sustain, Utility & Team.

### Added: Starting Boons

All 172 boons can be toggled on as starting boons granted at the beginning of a Chaos Wastes run. Uses the same 6 sub-groups. Starting boons bypass the disabled-boons list and are granted to all players based on host settings.

### Added: Modified Boons

New "Modified Boons" section for per-boon gameplay tweaks. First entry: **Reckless Swings** — reduces self-damage from 3 to 1 per hit and lowers the health threshold from 50% to 25%, letting the boon stay active longer. Tooltip updates dynamically when the tweak is enabled.

### Added: Banned Weapon Traits

20 Chaos Wastes weapon traits can be individually banned from appearing on weapon upgrades.

### Fixed: Boon localization

Boon names in settings UI now display readable names instead of raw internal keys (e.g. "Attack Speed" instead of `<attack_speed>`). Localization is generated at mod registration time from the static boon key list, then upgraded to actual game display names on first Chaos Wastes entry.

### Changed: Removed redundant settings wrapper

Settings are no longer nested inside a redundant "Chaos Wastes" collapsible group.

## 0.2.0-dev (2026-04-24)

### Added: Version logging

Mod now logs `Chaos Wastes Tweaker v<version> loaded` on init so the running version can be verified in the console log.
