# General Tweaker Changelog

## 0.2.261-dev (2026-08-03) -- bot-rescue evidence lines reach the log (#300) [verify-fix][untested]

- The four [gt:bot-rescue] markers moved from mod:debug (a channel the user''s
  config provably drops) to printf, so the #300 card can finally capture
  evidence. Payloads unchanged; offline needles pin the channel.
## v0.2.260-dev (2026-08-02) -- #242 spawn-disable nil-id crash fix + pickup passthrough [untested]

- **Fixed a latent crash in Disable Enemy Spawns (#242).** [untested] The hard refusal in the
  `ConflictDirector.spawn_queued_unit` hook returned bare nil, but vanilla consumers use the
  returned spawn-queue id as a real handle: a live Chaos Sorcerer writes it as a TABLE KEY
  (`bt_chaos_sorcerer_summoning_action.lua:406-408`, a nil key is an instant Lua error), and the
  sorcerer death cleanup, roaming-AI recycler, necromancer pets, and CW curse mutators all hand
  the stored id back to `remove_queued_unit`, which ferrors on any id not in the queue
  (`conflict_director.lua:1832`). Since the toggle deliberately leaves existing enemies alive, a
  live sorcerer at toggle-flip reached the nil path. The refusal now lives at the queue's single
  drain point instead: `spawn_queued_unit` always enqueues (every consumer holds a real, removable
  id), and a new `ConflictDirector.update_spawn_queue` hook parks the queue while the block is on -
  the same "queued but not yet spawned" state vanilla already produces for breeds not loaded on all
  peers (`conflict_director.lua:1847-1857`). Trade-off: enemies queued while blocked spawn at the
  vanilla one-per-frame drain rate if the toggle is turned off mid-mission, instead of never.
- **Disable Enemy Spawns no longer swallows pickups (#242).** [untested]
  `ConflictDirector.spawn_unit_immediate` was refused unconditionally, but its only vanilla callers
  are the training-dummy level-event PICKUPS (`pickups.lua:147/179`, spawn category `"pickup"`,
  `Breeds.training_dummy` with `race = "dummy"`). The refusal is now scoped to AI enemy spawns:
  pickup-category and dummy-race spawns always pass through; the nil,nil refusal remains only for
  mod-injected immediate enemy spawns (no vanilla caller consumes that nil).
- Extended the `issue242_all_spawn_classes_blocked` regression check to assert the dequeue-gate and
  pickup-passthrough markers in addition to the `script_data.ai_*_disabled` flag set, and rewrote
  `qa/lua/tests/test_gt_disable_enemy_spawns.lua` to execute the shipped hook closures offline:
  blocked `spawn_queued_unit` must still return a real table-key-safe queue id, the
  `update_spawn_queue` gate must park/drain on toggle and Freeze AI state, and
  `spawn_unit_immediate` must pass pickups while refusing enemies.
- Freeze AI (#303) rides the same gates: comment references in `_gt_freeze_ai.lua` and the
  `ENGINE_SURFACE.md` ConflictDirector row updated to the new design.

1. Start a mission, let a Chaos Sorcerer (Vortex) spawn, then enable "Disable Enemy Spawns"
   (or `/no_enemies`). Stay near the sorcerer: it must keep casting without a crash and no new
   vortex may appear. Kill it: no crash on death cleanup.
2. With the toggle ON from the keep, load Trail of Treachery (or any dummy level event) and confirm
   training dummies still spawn.
3. Toggle OFF mid-mission and confirm spawning resumes (a short backlog of deferred spawns
   appearing over the following seconds is expected).

## v0.2.259-dev (2026-08-02) -- godmode debuff immunity (#548) + downed-mood regression lock (#380) [untested]

- Godmode now suppresses a curated, cite-verified set of DEBUFFS that ride the
  buff funnel rather than the HP-damage funnel: Troll Bile's ground pool
  (DoT + slow), the vomit-in-face blind, and generic slow volumes. Damage
  immunity alone never blocked these because they apply through
  BuffExtension:add_buff, which the existing #548 probe only observed. The set
  is curated so godmode can never strip an unrelated status (heal/buff); gas and
  warpfire stay out until the observer captures their authored template names.
- Extended the existing add_buff hook (no second hook on the pair) and added a
  pure predicate (mod._gt548_should_deny_buff) covered by /gt_regression_test.
- #380: locked the downed-mood swallow set (knocked_down + bleeding_out +
  wounded) behind a regression check so a future edit cannot silently drop the
  bleedout grayscale back out. No behaviour change - the disable-downed-fx
  toggle already covers all three moods; this only prevents regressing it.
- (Salvaged from a 2026-07-20 draft authored as 0.2.253-dev; renumbered onto
  current master, which meanwhile shipped 0.2.254 through 0.2.258.)

**Solo verify:** with godmode ON, walk into a Troll Bile pool (no slow, no green
debuff, HP flat), take a troll vomit to the face (no blind/slow), and stand in a
generic slow volume (unaffected). Toggle godmode OFF and confirm every debuff
behaves vanilla. Run /gt_regression_test; issue548_... and issue380_... pass.

## v0.2.258-dev (2026-08-01) -- Godmode outgoing armor boundary (#1008) [verify-fix]

- Preserved #549's positive final-damage override and added one earlier,
  source-backed boundary at `DamageUtils.calculate_damage`, where vanilla still
  exposes hard invulnerability and the resolved hit-zone armor categories.
- With Godmode and **9999 Damage Per Strike** enabled, an armor-rejected zero
  against ordinary armor or super armor is promoted to 9999. Vanilla
  invulnerability, authored no-damage/zero-power profiles, unarmored zeros,
  allies, self hits, enemy players, and Godmode-off calls remain unchanged.
- No damage profile, armor table, lookup, or RPC is changed. Classification is
  fail-open, successful/failing classifications have a shared eight-line log
  cap, and pure offline plus runtime regression checks cover the boundary.

## v0.2.257-dev (2026-08-01) -- Godmode Blightstorm capture boundary (#1009) [verify-fix]

- Godmode now rejects only the server-authored Blightstorm entering edge at
  `StatusUtils.set_in_vortex_network`, positively identified by its enemy
  `VortexExtension`. The status mutation and client RPC never begin, and the
  vortex receives the native `false` result instead of recording a capture.
- The exit/cleanup edge, non-Godmode players, attraction outside the capture
  radius, Sister of the Thorn's summoned vortex, damage handling, and every
  unrelated status remain vanilla. This adds no movement or per-frame hook.
- Added a pure Lua 5.1 truth table, singleton hook-ownership coverage, bounded
  runtime evidence, and `/gt_regression_test` wiring coverage.

## v0.2.256-dev (2026-07-28) -- Host-side melee latency compensation (#1034)

- Added a default-on, host-authoritative grace window for ordinary blockable AI
  melee hits against remote human players. The window uses a capped exponential
  moving average of the host's own `GameNetworkManager:ping_by_peer` sample;
  clients provide no custom ping or combat claims.
- Eligible damage is queued for at most 350 ms. At the deadline, a host-observed
  dodge, valid directional block, attacker death, or stagger caused by that
  player cancels the hit. Host players, bots, grabs, projectiles, hazards,
  unblockable attacks, and already-blocked damage remain vanilla.
- The common overlap-attack path defers the complete player-impact method, so
  damage, blocking, pushes, and hit callbacks resolve together. Vanilla
  block/dodge RPC rising edges and player-authored stagger resolve matching
  pending hits immediately, preserving even short defensive inputs.
- Bounded the global pending queue to 256 hits and fail open on missing network
  context, invalid ping samples, or overflow. Added per-session bounded
  `[gt_dev:LC]` cancellation evidence and `/gt_lag_comp_status` counters.
- Common overlap hits have one owner: when the whole-impact hook fails open, it
  suppresses the lower damage-only fallback for that call so damage, pushes,
  and callbacks can never split across two timing decisions.

## v0.2.255-dev (2026-07-26) -- Source-backed live player stat HUD (#797) [not deployed]

- Added a default-off, local/read-only HUD for health, stamina, movement,
  cooldown/charge state, attack speed, critical, power, damage, impact/cleave,
  healing, block/push, regeneration, ammo, and reload families. It displays
  consumer-effective values only where the complete deterministic engine path
  is available, labels exact retained modifiers as factors, and marks
  target/profile/proc-dependent finals `UNSUPPORTED`.
- Separate chain/action (`is_animation=false`) and animation
  (`is_animation=true`) time-scale rows compose the authored action base with
  generic, melee/ranged, drakefire, and charge-time stages in engine order.
  `scale_chain_window_by_charge_time_buff` applies to both rows, while
  `scale_anim_by_charge_time_buff` applies only to the animation row. The
  action-settings critical path composes career base, action bonus,
  melee/ranged, heavy, and generic stages, while the effective critical final
  is explicitly unsupported because call-site runtime overrides are not
  observable. Authoritative health and stamina getters expose any otherwise
  unattributable remainder as an explicit reconciling delta. Movement final is
  explicitly unsupported because native walking additionally consumes stance,
  `current_move_speed_multiplier`, `current_movement_speed_scale`, and
  `player_speed_scale`; the settings-table base is never presented as final.
- `activated_cooldown` is shown only as an **activation factor**, never as
  `max_cooldown * factor`: vanilla first adds the ability's actual cost to its
  current cooldown, subtracts the call-site refund, and only then applies the
  stat. Refund and modified-cost arguments are not retained outside that call.
  Stamina regeneration derives the exact native gauge rate
  `1.5 / authoritative_max_fatigue_points * 100` before applying
  `fatigue_regen`; the row fails closed when the live max-fatigue getter is
  unavailable.
- Preserved native `BuffExtension` stage keys and its deterministic ordered
  stage/root equation. Proc, function/table multiplier, and missing-base paths
  are explicitly `UNSUPPORTED`; the HUD never invokes proc-bearing methods.
  Retained sources are identified by parent/child/id and classified by their
  authored active lifetime as timed or persistent.
- Static provenance rebuilds only on unit/equipment/action/buff edges. A 4 Hz
  bounded sampler formats only changed results, bounds active-source discovery
  before allocation, exposes truncation, clears stale panels on missing units
  and on native health/status death even while `Unit.alive` remains true, wraps
  every line before pagination, and reports counters through
  `/gt_stat_hud_metrics`.
- Reused the singleton HUD dispatcher and bottom-corner anchors to avoid the
  existing top-left bot HUD and top-right Godmode indicator. No background
  chrome, network traffic, gameplay mutation, or deployment is included. This
  reviewed candidate remains source-only; no VMB build or generated root-bundle
  update is included yet.

## v0.2.254-dev (2026-07-22) -- Godmode ledge repair and Raise Dead trace (#939, #659) [not-started]

- Godmode now treats authored ledge-hang triggers as a boundary for the owning
  player. When vanilla positively identifies a ledge, the player is restored
  to the engine-maintained last on-ground navmesh position and the disabled
  hanging state is rejected.
- The fix composes through noclip's existing singleton ledge helper hook. If a
  safe recovery sample or locomotion extension is unavailable, vanilla ledge
  hanging is preserved instead of risking an uncontrolled fall.
- Added offline truth-table/ownership coverage and a `/gt_regression_test`
  structural check. The live diagnostic is transition-bounded to one line per
  ledge encounter.
- Added an observation-only Necromancer Raise Dead trace across projectile
  targeting, action-finish gating, passive queueing, and authoritative server
  spawn. It runs only for the local human Necromancer in the Keep and has
  independent hard caps at every boundary.
- The trace does not alter targeting, cooldowns, pet queues, navigation, RPCs,
  or spawn results. Its first live capture will select the next repair from the
  exact boundary that rejects or loses the summon.

## v0.2.253-dev (2026-07-21) -- strict debug-renderer residency (#749)

- Bot Teleport Lab and Debug Highlights now require a positive shared V2
  material proof immediately before their native screen-Gui creation calls.
- Missing, throwing, or indeterminate resource probes skip the optional debug
  overlay and preserve gameplay instead of crossing the native crash boundary.

## v0.2.252-dev (2026-07-19) -- client-owned ragdoll retention (#332) [verify-fix-coop]

- Snapshot dead client AI husks into bounded, static, non-colliding visual
  clones before authoritative destroy or BreedFreezer reuse removes them.
- Preserve the original teardown/RPC paths, add no network surface, and trim
  retained client visuals immediately when the local ragdoll cap is lowered.

## v0.2.251-dev (2026-07-19) -- bounded runtime evidence (#254, #797) [diagnostics-armed]

- Added a bounded host-side Chaos Wastes creature-spawn queue trace that
  preserves the exact request, director, effective breed, blocker, and terminal
  outcome without adding a ConflictDirector hook or changing spawn behavior.
- Added inert one-shot/five-sample player-stat probes that inventory exact buff,
  equipment, and action context without guessing unsupported final values or
  polluting game chat.
- Added transition-only Steam, PlayFab, P2P, and NetworkClient teardown evidence;
  the captured PlayFab reason is frozen at vanilla's actual disconnect promotion
  edge so later queued errors cannot overwrite attribution.
- All probes are read-only, session-capped, fail closed, and reuse existing
  lifecycle/network owners. Offline coverage locks bounds and ownership.

## v0.2.250-dev (2026-07-18) -- aid-errand pin + explosion-arity pin [untested]

Two root-cause clusters, one combined build. Not shipped (issue 625 freeze).

**Cluster A (issue 332) - mutator-explosion full-arity regression pin.**
- Mechanism re-verified against the decompile: vanilla `AiUtils.generic_mutator_explosion(unit, blackboard, explosion_template_name, do_damage)` (`ai_utils.lua:575`; `do_damage` gates the attacker arg of `DamageUtils.create_explosion` at `:583`) and client `AreaDamageSystem.rpc_create_explosion` with 12 params (`area_damage_system.lua:473`). The v0.2.186-dev fix already captures and forwards all args on both hooks in `_gt_solo_qol.lua`; every branch passes full arity (the suppression branch intentionally returns nothing - that is the toggle's purpose).
- What was missing was the regression pin: new offline suite `qa/lua/tests/test_gt_solo_qol_explosion_arity.lua` pins the exact 4-arg capture + forward, rejects the exact 3-arg regression shape (`func(killed_unit, blackboard, explosion_template_name)`), pins the full 12-param client signature + forward, and asserts both hooks stay singletons per (Class, method). BUG_CLASSES class 19 (dropped trailing param).

**Cluster B (issues 139, 384, 385) - aid-errand PIN so the teleport veto holds.**
- Forensics: issue 384's log (`console-2026-07-06-20.23.14`) showed a bot leash-teleported to the standing human 3x starting ~2 s after the downed ally's aid flag cleared with VETOED=0; the 2026-07-18 sweep of gt 0.2.248 sessions added 410x `[gt_bot:139] TELEPORT executed`, a `[gt:139:chain] VETO bot=... reason=tighter_leash` followed 0.02 s later by `TELEPORT ... veto_age=0.02s same_aid=false` (the veto did not hold), and `[gt:492] ... BAILED aid pursuit (reason=no-progress)` releasing the veto in the same chain while the ally was still down.
- Root cause (decompile-verified): `_ally_path_allowed` failed-path cooldowns (1 s ahead / 5-10 s behind / 3-12 s scaled, `player_bot_base.lua:1948-1983` - note the real path is `scripts/unit_extensions/human/player_bot_unit/`, not `ai_player_unit/`) make `_select_ally_by_utility` skip or de-label the downed ally (`:960-964`), and `_update_target_ally` then clears `target_ally_needs_aid`/`target_ally_need_type` (`:721-724`). Every consumer of that field - vanilla's own teleport aid exception (`bt_bot_conditions.lua:1226-1228`), gt's tighter leash, and `can_revive` (`:738`) - flickers off mid-errand.
- Fix in `_gt_bot_fixes.lua`: per-bot aid-errand PIN. Armed at every aid-pick return site (vanilla pick, FIX 3 awaiting-rescue relabel, FIX 3b force pick); on any tick where the chain produced no aid pick but the pinned ally STILL classifies via live status (`_gt_teleport_loop_policy.pin_need_type`: knocked_down / ledge / hook, plus awaiting-rescue relabel only while `gt_bot_rescue_awaiting` is on and the unit is health-alive), the picker re-returns the pinned errand, so `target_ally_need_type` never drops and all three consumers stay engaged. Release is state-based only (BUG_CLASSES class 34: no wall-clock): ally recovered/gone, or an issue-492 bail with reason no-path on the pinned ally.
- Issue-492 composition: the watchdog now stamps `blackboard._gt492_bailout_reason` ("no-path" = sustained `cb_ally_path_result` failure, the authoritative give-up; "no-progress" = straight-line stall). A no-progress bail no longer hard-drops the errand in the picker and no longer releases the should_teleport / cant_reach_ally vetoes while the pin is live - per the log evidence it was firing while the ally was still down (combat hold, not unreachability). No-path bails keep the exact shipped release everywhere. `[gt:139:chain] VETO` rows now carry `bailout=` and `pin=` fields; `[gt:384:pin] ARMED / HELD / RELEASED` printf edges trace the pin lifecycle.
- Issue 384's other two directives were already shipped in v0.2.212-dev and are now regression-locked: the veto backstop scans `side:player_units()` (bots + awaiting included; `side_manager.lua:338-340` filters awaiting out of the human-only frame tables) with the full disabler predicate (all 7 grab states + awaiting-rescue, matching `generic_status_extension.lua:2158` minus the deliberate dead/overpowered exclusions). The source-text invariants that issue 511 evicted from runtime checks (io is nil in the VMF sandbox) now live in the offline suite.
- Issue 385 instrument (log-only, capped; diagnose-before-mitigating): `BTBotTeleportToAllyAction.run` now prints `[gt:385] below-leash TELEPORT n/24 bot=... branch=... follow_dist=... leash=...` for any executed teleport whose PRE-snap navmesh follow distance is below min(leash slider, vanilla 40 m) - tagging WHICH should_teleport / cant_reach_ally branch fired, the datum the issue-385 log lacked (`trigger=unknown`, 9 of 40 events below leash). Distance from the same whereabouts source the decision reads; capped at 24 lines/session via `_gt_teleport_loop_policy.BELOW_LEASH_LOG_CAP`; the existing bounded no-path retry suppression is unchanged.
- New markers `GT_BOT384_AID_ERRAND_PIN_MARKER_v0_2_250` / `GT_BOT385_BELOW_LEASH_INSTRUMENT_MARKER_v0_2_250`; new `/gt_regression_test` checks `gt_bot384_aid_errand_pin` + `gt_bot385_below_leash_instrument`; new offline suite `qa/lua/tests/test_gt_bot_aid_pin_policy.lua` (pin truth tables, release matrix, below-leash log gate, source invariants). Full offline suite green (1148 tests); mod-lint clean (163 hooks, 0 duplicates). Host-side only - no RPC, no NetworkLookup, no wire surface.

### Co-op verify

Aid-priority ON, team split, one player goes down far from the bots' follow target: bots must path to the revive with zero `[gt_bot:139] TELEPORT executed` lines between the down and the revive (or a `[gt:384:pin] HELD` line proving the pin bridged a flicker). A genuinely unreachable down must still release within ~4-8 s via `[gt:492] BAILED ... reason=no-path` followed by a regroup teleport. Any below-leash teleport now prints its `[gt:385] ... branch=` attribution.

## v0.2.249-dev (2026-07-18) -- lobby appearance-parity banner [untested]

- New client-side banner (issue 737 mitigation): after a SUCCESSFUL join, posts one chat line when an appearance mod (wt / cosmetics / cwv / cim / woc) is enabled on only one side of the session, or when host and client run different streams or versions of the same mod. Appearance mismatches let the join succeed and then desync the NetworkLookup index spaces mid-session (score-screen CTD, husk/preview failures) - this makes the divergence visible at join time instead.
- Manifest travels in `ltw_*` lobby_data slots via the shared `_lib_appearance_parity` module (canonical copy in `tools/shared_lib/`, byte-exact per the shared-lib gate). Banner text: `Parity warning: <Mod Label> - host: <state>, you: <state> - modded appearance may desync`.
- Toggle `gt_lobby_appearance_parity_enabled` (default ON) in the Lobby group.
- 16 Lua 5.1 tests cover manifest encode/decode, mismatch classification, and banner suppression when states agree.
- NOT SHIPPED: gt_dev upload remains frozen until issue 625 reconciles master with the Workshop build. Bundle in this commit exists only to satisfy release-bundle atomicity (issue 724); no deploy, no upload.

## v0.2.248-dev (2026-07-18) -- #731 VOIP disconnect channel guard

- Source inspection confirmed that `Voip._ensure_left_voip_room` clears its local room and then sends `rpc_voip_room_request(false)`. During disconnect, the server's `PEER_ID_TO_CHANNEL` entry can already be gone, so vanilla passes `nil` to the engine RPC and crashes on `Channel must be an integer`.
- Added an exact preflight gate for only that VOIP request. It drops the teardown message when the server peer or numeric channel is already absent, and a narrow race guard contains the same engine assertion if the channel closes between preflight and send. All other RPC names and all other failures preserve the vanilla path.
- Consolidated the existing noclip `rpc_suicide` decision and the new VOIP decision behind one `NetworkTransmit.send_rpc_server` hook owner. This avoids introducing duplicate hooks on a shared engine seam.
- Added Lua 5.1 coverage for live/missing channels, server/local paths, exact error matching, singleton hook ownership, and noclip composition.

### Co-op verify

Join another player's lobby as a client, then leave or disconnect during a transition and repeat several times. The client must return without a crash. If the server channel closed before VOIP teardown, the log may contain one `[gt:731][WARN] Dropped stale VOIP leave-room RPC` line for the session; unrelated RPC failures must not be swallowed.

## v0.2.247-dev (2026-07-18) -- #659 extension-ready keep-pet reconciliation [diagnostics-armed]

- The failed 2026-07-18 verification ran GT Dev `v0.2.245-dev`; the live Necromancer extension reached vanilla `warm_up_skeletons`, but GT emitted no `[gt:659]` lifecycle decision. The offline truth-table passing therefore did not prove that the live initialized extension consumed the policy.
- Reused one idempotent, engine-free reconciliation policy at two distinct vanilla lifecycle edges: `_on_talents_changed`, where the hub flag is written, and `extensions_ready`, after the passive extension has finished initialization. This is the issue's pre-recorded fallback 2 and preserves later talent refreshes without duplicate hooks on either method.
- Replaced mutation-only evidence with at most four phase/before/after records per passive extension. Direct Lua coverage now exercises human reconciliation, bot gating, missing owners, idempotence, and singleton hook ownership.

### Solo diagnostic verify

Enter the keep as Necromancer with **Allow Bots in Keep** disabled. Before using Raise Dead, the log must contain `[gt:659] phase=talents_changed` and/or `phase=extensions_ready` with `owner=human` and `after=false`. Then use Raise Dead. If skeletons still do not spawn, that evidence falsifies the hub-ban hypothesis and the next diagnostic belongs at the action/spawn entry rather than another lifecycle hook.

## v0.2.246-dev (2026-07-18) -- #693 client Creature Spawner [verify-fix-coop]

- Release reconciliation: aligned the Workshop descriptor title with the already-merged `MOD_VERSION` before the atomic `0.2.246-dev` bundle build. The source-only merge was never uploaded.

- Clients can now use the Creature Spawner. Spawning is host-authoritative (only the host drains the ConflictDirector spawn queue, `state_ingame.lua:950-958`), and the old host gate silently swallowed every client spawn/destroy press with no feedback. A client now sends a schema-tagged request over the mod's own VMF network channel (`gt_cs_request`, `mod.GT_CS_RPC_SCHEMA` v1); the host validates the breed against its live `Breeds` table and performs the spawn at the client's crosshair position, facing the client, with the client's own grudge-mark configuration. `gt_cs_ack` relays the host's result line back to the requesting client.
- Breed cycling, the unit-list dropdown, save slots, and `/selectedcreatures` now work locally on a client instead of no-oping; `/savecreature` slots feed the client's spawn requests.
- Wire safety: VMF `network_send` rides the vanilla `rpc_mod_user_data` mod-manager RPC (`mod_manager.lua:595-621`); a receiving peer dispatches only into callbacks it registered itself, so vanilla peers and peers without gt drop the payload inside vanilla code - no modded `NetworkLookup` keys, no custom vanilla RPCs (the issue 278/371 crash class is untouched). When the host lacks the mod, the request degrades silently and the client-side message says the host must run the mod.
- Added `/gt_regression_test` checks `gt_cs_rpc_schema_present` and `gt693_cs_client_request_wired`.

### Co-op verify

Both peers on gt_dev. CLIENT: cycle breeds (next/previous keys or the dropdown; the selection line must echo), aim, and press Spawn Creature - the enemy must appear at the CLIENT's crosshair and the client chat must show the host's "[Spawn]: Created ..." ack; Destroy Spawned Creatures must clear enemies and ack "Removed all enemies (host)". HOST: spawn/destroy/cycling must behave exactly as before, and the host log must show one `[gt_cs:693] client spawn request from=... ok=true` line per client spawn. Regression: a client whose host does NOT run the mod must see only the "needs this mod on the host" line, with no crash on any peer.

## v0.2.245-dev (2026-07-17) -- runtime module boundaries (#2) [tooling]

- Extracted the runtime regression catalogue from the entry point without changing registration order or command ownership.
- Extracted the consolidated bot-update policies from `_gt_bot_fixes.lua`; the entry point and bot owner are back below their frozen size ceilings.
- Added focused module-boundary coverage so future hooks cannot silently duplicate registration or update ownership.

## v0.2.244-dev (2026-07-17) -- correlated bot aid teleport diagnostics (#139, #384) [diag] [coop-required]

- Replaced the structurally ambiguous issue-139 veto line with one bounded `[gt:139:chain]` event carrying the bot, preserved aid ally, final follow target, teleport reason, `target_ally_need_type`, and issue-492 bailout state. A later teleport by the same bot now reports the prior veto age and whether the aid identity is unchanged.
- Moved the D2 follow trace to the final exit of the existing `_assign_destination_points` hook. It now records the exact post-vanilla/post-FIX-9 follow target consumed by the leash instead of the vanilla pre-override value that made two correctly split bots appear assigned to the same human.
- Replaced execution-side `POSITION_LOOKUP` sampling with immediate `Unit.world_position` reads. The old source stayed stale until the next system tick and printed identical pre/post coordinates even when the following D3 sample proved the bot had moved.
- Preserved the v0.2.212 aid/rescue veto and the #492 bailout behavior unchanged. This is diagnostics-only because the v0.2.241 two-player log proves the existing attribution is ambiguous: it contains a Victor veto at 05:31:10 followed by a Victor teleport at 05:31:11, but does not retain which aid state cleared or changed between them.
- Added Lua 5.1 coverage for the three-second identity-correlation window and source wiring, plus `/gt_regression_test` check `issue139_aid_trace_correlation`.

### Co-op diagnostic capture

Host with two humans and bots, enable Bot Behavior Improvements, aid priority, Split follow mode, and a 15 m snap-back distance. Down or disable the human beside one bot while the other human remains over 15 m away. The next log should contain one connected `[gt:139:chain] FOLLOW` / `VETO` / `TELEPORT` sequence naming the same bot and aid ally; `TELEPORT` must show whether the state cleared, changed ally, or was deliberately released by `bailout=true`. Lifecycle intent: #139 remains `diagnostics-armed` + `coop-required`; #384 retains `verify-fix-coop` until this capture disproves the v0.2.212 behavior.

## v0.2.243-dev (2026-07-17) -- #659 human Necromancer keep skeletons [verify-fix]

- Extended GT's existing Necromancer keep-pet policy to human owners. Fatshark's `_pets_forbidden_in_level` hub flag previously remained true for the local player, so `spawn_pet` returned before queuing any Raise Dead skeleton.
- Preserved the original bot contract: bot Necromancers are allowed only while **Allow Bots in Keep** is enabled. Mission and other non-hub states are never mutated.
- Added bounded `[gt:659]` apply evidence with owner/server/local state, runtime truth-table coverage for human, bot-enabled, bot-disabled, and mission cases, and updated the engine-surface contract.

### Solo verify

Enter the keep as Necromancer and use Raise Dead. Skeletons should spawn and the log should contain one `[gt:659] necromancer keep pets allowed owner=human` row. Run `/gt_regression_test` and confirm `necromancer_keep_pet_policy_659` passes.
## v0.2.242-dev (2026-07-16) -- startup-safe ammo reconciliation (#662)

- Stopped the persisted Godmode unlimited-ammo child from calling `PlayerManager:local_player()` while the title/loading state has no network backend. The shared reconciler now uses a network-game-gated, `pcall`-contained `local_player_safe` policy and remains dormant until a real local player exists.
- Preserved both ownership paths after readiness: Godmode's child stays owner-local and `/infinite_ammo` retains its host-wide behavior. No new update consumer, hook, RPC, or retry loop was added.
- Added engine-free coverage for missing network state, a throwing network transition, a throwing `local_player_safe`, the ready-player path, and the absence of the unsafe API in the reconciler.

### Solo verify

Launch with Godmode and its Unlimited Ammo child persisted on. From GT load through arrival in the Keep, the log must contain no `consumer 'infinite_ammo' raised` or `Network backend has not been set` line. Ammo/overcharge must become unlimited after the local player spawns; disabling Godmode must restore consumption. Run `/gt_regression_test` and confirm the existing #549 ownership check passes.

## v0.2.241-dev (2026-07-16) -- bot follow utility crash guard [verify-fix]

- Fixed the host crash in `Utility.get_action_utility` when a GT ally-selection branch left the player-bot `ally_distance` input nil and the native follow consideration immediately subtracted it.
- Preserved the source-backed vanilla contract at the producer: every no-target result from GT's `_select_ally_by_utility` wrapper now carries `math.huge`, matching `AISystem.set_default_blackboard_values` and vanilla's selector sentinel.
- Removed Creature Spawner's unrelated global Utility hook. Its attempted repair only rebound a local table and then called vanilla with the original nil state. Bot fixes now own one consolidated utility guard: the exact player follow input is restored to vanilla's sentinel, while any unrelated missing/non-numeric input gives that malformed action zero utility without feeding invented infinity values into unknown behavior.
- Added engine-free tests for the follow repair, generic fail-closed path, valid condition/number behavior, and singleton hook ownership, plus `/gt_regression_test` check `gt_bot_utility_nil_guard`.

### Solo verify

Host a mission with bots and repeat the prior bot-follow/heal/rescue sequence. The mission must continue without `Utility.get_action_utility` reporting arithmetic on nil. Run `/gt_regression_test` and confirm `gt_bot_utility_nil_guard` passes; a recovered race produces at most one `[gt:utility-guard] repaired player-bot follow ally_distance` log row.

## v0.2.240-dev (2026-07-15) -- #600 aimed Wait order [verify-fix]

- Corrected **Wait** on the bot command wheel to preserve the wheel's own raycast world position and move the selected bot there. Adventure mode deliberately disables world-marker pings, so the previous post-chat lookup had no position and fell back to the player's feet.
- Copied the live social-wheel context into a fresh `Vector3Box` inside GT's existing singleton `SocialWheelUI._open_menu` hook, consumed it once when **Wait** executes, and removed the player-position fallback. A command with no valid aimed world point now fails closed instead of parking at the player.
- Increased the bounded hold from 15 to 30 seconds. The apply trace now records the selected bot, aimed coordinates, radius, duration, and `source=wheel_aim` under `[gt:600]`.
- Added engine-free regression coverage and `/gt_regression_test` check `issue600_wait_aim_and_duration`.

### Solo verify

Host an Adventure mission with at least one bot, enable **Bot command wheel**, aim at navigable ground several metres away, and choose **Wait**. The nearest bot should move to that aimed point, remain held around it for 30 seconds, then resume following. Run `/gt_regression_test` and confirm `issue600_wait_aim_and_duration` passes; the log should contain one `[gt:600] wait applied` row with `source=wheel_aim` and `duration=30.0`.

## v0.2.239-dev (2026-07-14) -- #247 keep-slot bot takeover [verify-fix-coop]

- Replaced the hard-disabled owner-destructive swap with a source-backed keep-slot transaction for Adventure, Chaos Wastes, and Weaves. The human `Player`, peer/profile assignment, and party slot remain authoritative while one temporary same-profile bot uses a free slot or safely replaces one remembered native bot.
- Reclaim removes only the recorded takeover bot, restores the displaced bot to its exact profile/career/slot, and returns the human through native `force_respawn`; the retired `remove_player`, human party/profile reassignment, and locomotion-override path is absent.
- Bumped the AI RPC schema to v2, authenticated requests to the VMF sender, rejected claimed peer/local-id mismatches, and added host-only bounded result acknowledgements so client settings converge after rejection.
- Added exact admission/authentication policy coverage, displacement/rollback structural tests, runtime `issue247_keep_slot_takeover_wired`, `AI_TAKEOVER_247.md`, and co-op verification steps. Four-human parties and unsupported modes fail before despawn.
- Adversarial follow-up rejects non-boolean takeover intents and malformed host acknowledgements, keeps the live camera intact when human despawn fails, native-respawns after observer setup failure, and verifies reclaim APIs before removing the temporary bot.

## v0.2.238-dev (2026-07-14) -- #219 remove confirmed orphan MOTD localization

- Removed only the unused `gt_lobby_motd_text` title and tooltip localization records left by the retired invalid text-input widget. The command-authored persisted setting and every MOTD send/read path remain intact.
- This is the General Tweaker portion of the cross-mod orphan-localization cleanup; runtime behavior is unchanged.

## v0.2.237-dev (2026-07-14) -- #488 bounded bot hazard fix and Ratling-shield diagnostics [not deployed]

- Added a default-on child beneath the default-off Bot Behavior Improvements master. Host-owned bots keep independent gas and warpfire ledgers: each positive hit adds one two-second stack after resolving, and each active prior stack reduces the next matching hit by 20%, capped at five. Human players, other damage types, and the first hit remain vanilla.
- Composed at GT's existing singleton `DamageUtils.apply_buffs_to_damage` hook after vanilla mitigation. The implementation adds no buff template, lookup row, RPC, shared breed mutation, or per-frame update; weak unit keys release replaced bots and milestone logging caps at 16 rows.
- Kept shield-blocking Ratling fire diagnostic-only. The existing `_in_line_of_fire` owner records up to 12 distinct live state shapes: wielded/melee shield capability, blocking, projectile-hit attribution, cover state, victim identity, and input-extension readiness. It never suppresses cover or requests an action.
- Added pure stack/classifier tests, structural singleton-hook coverage, runtime `issue488_bot_improvement_families`, and `BOT_IMPROVEMENTS_488.md`. Hazard resistance is ready for solo bot verification; shield blocking remains diagnostics-armed.

## v0.2.236-dev (2026-07-14) -- #242 complete enemy-spawn suppression [verify-fix]

- Regression-locked the existing two-layer spawn block: both `ConflictDirector` spawn entry points refuse future units while the native `script_data` gates stop patrol, monster, horde, roaming, special, and critter producers before they queue work.
- Added `/gt_regression_test` check `issue242_all_spawn_classes_blocked` and engine-free source coverage. The toggle remains reversible and does not despawn enemies that already exist.

### Solo verify

Enable **Disable Enemy Spawns** before starting a mission and play through a full level. No ambient enemies, hordes, specials, patrols, monsters, or critters should spawn. Disable it and confirm pacing resumes. Run `/gt_regression_test` and require `issue242_all_spawn_classes_blocked` to pass.

## v0.2.235-dev (2026-07-14) -- #333 offline Twitch mode and event allow-list [verify-fix-coop]

- Added a default-off **Offline Twitch Mode** that lets the host run ordinary Twitch votes without an account, channel, or stream. It reuses Fatshark's native Twitch game-mode object, timers, random tie resolution, effects, vote UI, game objects, and RPCs.
- Added default-on category controls for buffs/effects, item giveaways, mutators, and enemy spawns. They compose with vanilla's game-mode whitelist at its single candidate gate and also apply when a real Twitch account is connected.
- Synthetic connectivity is scoped to the mission lifecycle, ignores irrelevant IRC disconnect notifications, and is cleared after vanilla destroys vote state.
- Added pure classifier/allow-list coverage, runtime regression check `issue333_offline_twitch_policy`, and vanilla-client verification notes in `OFFLINE_TWITCH.md`.

### Co-op verify

Enable **Offline Twitch Mode** on the host without linking Twitch, load a supported mission with a second player, and confirm normal vote UI, local random resolution, and effects remain synchronized. Disable each category in turn and confirm its events stop appearing. Repeat with a client that does not run GT. Run `/gt_regression_test` and confirm `issue333_offline_twitch_policy` passes.

## v0.2.234-dev (2026-07-14) -- #72 failed-join popup ownership hardening [verify-fix]

- Closed the remaining F4 regression gap around the enriched failed-join popup. The live `StateLoading.create_popup` hook now routes successful takeover through one injectable ownership boundary that queues into GT's private pending registry without assigning `StateLoading._popup_id`.
- Added `/gt_regression_test` check `issue72_lobby_failnotify_never_hands_popup_to_vanilla`, which drives that exact boundary against a write-trapping synthetic state. Added a blocking tier-a absence invariant so a future direct `_popup_id` assignment anywhere in the module fails repo QA even if it bypasses the helper.
- Corrected `_gt_debug_probes.lua`'s legacy `mod.update(self, dt)` wrapper to VMF's real `mod.update(dt)` callback contract. Forwarding remains behavior-identical, but no longer relies on Lua discarding the accidentally shifted second argument.
- Added engine-free coverage for ownership wiring, absence of StateLoading handoff, runtime regression wiring, and the dt-only update wrapper.

### Solo verify

Run `/gt_regression_test` and confirm `issue72_lobby_failnotify_never_hands_popup_to_vanilla`, `gt_lobby_failnotify_teardown_driver`, `gt_lobby_failnotify_unknown_result_drives_teardown`, `gt_lobby_failnotify_popup_up_soft_defers`, and `gt_lobby_failnotify_unpack_preserves_leading_nils` all pass. The popup itself requires a real failed lobby join to exercise, but the remaining fix changes no user-facing branch.

## v0.2.233-dev (2026-07-14) -- #359 host bot command wheel [verify-fix]

- Added a default-off **Bot command wheel** option for the host. It inserts the existing Versus **Attack Now**, **Group Up**, **Cover Me**, and **Wait** commands as the second page of the ordinary mission social wheel.
- Reused the four vanilla social-wheel event IDs already present in `NetworkLookup`; no custom RPC, lookup mutation, or per-frame network traffic is introduced. Clients do not receive the command page and cannot issue authoritative bot orders.
- **Attack Now** promotes the host's last living enemy ping into vanilla's urgent-target table for 10 seconds. **Group Up** and **Cover Me** override the normal follow assignment for 8 and 12 seconds respectively while retaining bot combat/rescue safety. **Wait** uses the wheel's crosshair position and vanilla `AIBotGroupExtension.set_hold_position` to park the nearest bot within 4 m for 15 seconds.
- Expiry clears only hold state carrying GT's matching token, preventing a stale timer from clearing a newer order. Follow commands compose through the existing singleton `_assign_destination_points` hook instead of registering a duplicate.
- Added pure event/time/nearest-bot policy coverage and `/gt_regression_test` check `issue359_bot_command_wheel`.

### Solo verify

Host a mission with bots and enable **Bot command wheel**. Hold the social-wheel input and cycle to page two. Ping an enemy, choose **Attack Now**, and confirm bots prioritize it temporarily. Aim at navigable ground and choose **Wait**; confirm the nearest bot holds near that point, then resumes after 15 seconds. Choose **Group Up** and **Cover Me** and confirm bots gather around the host only for their bounded windows. Disable the option and confirm the added page disappears on its next open. Run `/gt_regression_test` and confirm `issue359_bot_command_wheel` passes.

## v0.2.232-dev (2026-07-14) -- #381 persistent Godmode HUD indicator [verify-fix]

- Added a small, persistent **GODMODE** indicator in the upper-right HUD whenever the local `godmode_enabled` setting is exactly on. It is part of the dev stream only and draws no remote-peer status.
- Reused General Tweaker's existing singleton `IngameHud.update` hook. The indicator owns a separate `hud_scale_fit` scenegraph and draw consumer, while `_gt_melee_warning.lua` remains the only hook registrant and dispatches both visuals.
- The renderer is acquired only from the live in-game UI context, uses the proven resident Arial HUD font, and fails closed when no renderer exists. Layout clamps measured text width to 600 pixels so the cue remains wholly on the 1920x1080 logical canvas.
- Added pure layout/visibility coverage and `/gt_regression_test` check `issue381_godmode_hud_indicator`.

### Solo verify

Enter the keep or a mission, enable Godmode, and confirm **GODMODE** appears in the upper-right without opening a menu. Disable Godmode and confirm it disappears on the next HUD frame. If Melee Attack Warning is enabled, trigger its red edge flash and confirm both visuals render together. Run `/gt_regression_test` and confirm `issue381_godmode_hud_indicator` passes.

## v0.2.231-dev (2026-07-14) -- #365 smart bot Ranger ale use [verify-fix]

- Added a default-off **Bots drink surplus Ranger ale** child under Bot Behavior Improvements. The host allows a bot to target the exact `bardin_survival_ale` pickup only when every active teammate has all three `ale_defence` and `ale_attack_speed` stacks and both refreshed durations are strictly above 50%.
- Kept #364's human reservation as the default. A weak, per-update allow-set exempts only the policy-approved live ale unit, so ordinary greedy and instant pickup cannot consume other ale.
- Consolidated the behavior into the existing `AIBotGroupSystem._update_mule_pickups` hook. The team census is bounded to `side.PLAYER_AND_BOT_UNITS`, cached for 0.5 seconds per side, and fails closed on missing units, buff extensions, stacks, or duration fields. Vanilla still owns auto-wield and consumption.
- Added pure offline policy coverage and `/gt_regression_test` check `issue365_smart_bot_ale_policy`.

### Solo verify

Host with bots and enable Bot Behavior Improvements plus Bots drink surplus Ranger ale. Confirm bots leave ale alone when any active teammate has fewer than three stacks, exactly 50% duration, or less. With every teammate at three stacks and above 50%, place an ale within the normal 20 m follow radius and confirm a bot picks it up and drinks it. Disable the child and confirm ale remains human-reserved. Run `/gt_regression_test` and confirm `issue365_smart_bot_ale_policy` passes.

## v0.2.230-dev (2026-07-14) -- #345 localization lifecycle sync [verify-fix]

- Re-derived General Tweaker's visible lifecycle markers from live GitHub labels. Closed, user-confirmed work for #65, #255, #261, #293, #295, #297, #448, #468, #492, #515, and #529 now reads `[working]` instead of retaining stale diagnostic or verification text.
- Kept the Bot Behavior Improvements master tied only to its open verification work (#139, #142, and #469), and kept Follow snap-back distance tied only to #139.
- Added missing `[verify-fix]` markers for #469, the #523 heal-allies controls, #298, and #304.
- Added `/gt_regression_test` coverage (`issue345_gt_loc_status_sync`) so stale lifecycle markers and closed issue references are caught in-game.

### Verification

Open General Tweaker's settings and confirm the corrected labels above, then run `/gt_regression_test` and confirm `issue345_gt_loc_status_sync` passes.

## v0.2.229-dev (2026-07-14) -- #298 Improved Bot Combat advanced controls [verify-fix]

- Converted **Improved Bot Combat** into a VMF master checkbox with live child controls for smarter attacks, pinging attacking elites, special chasing, distant-gunner cover behavior, boss focus, and six-career ability timing.
- Added distance sliders for special chasing (7.1 m), gunner cover response (11.8 m), and boss engagement (15 m). These reproduce the previous hard-coded squared-distance thresholds, so untouched child defaults preserve existing behavior.
- Every child delegates only its hook family back to vanilla when disabled. The existing host-side master remains default-off, and the nil-weapon crash guard remains ungated.
- Added offline policy coverage and `/gt_regression_test` check `issue298_improved_bot_combat_controls`.

### Solo verify

Host with bots, enable Improved Bot Combat, and toggle each child independently. Confirm the other families remain active, the three distance boundaries respond to their sliders, disabling the master restores vanilla decisions, and transient weapon swaps remain crash-free.

## v0.2.228-dev (2026-07-14) -- #523 configurable bot healing of allies [verify-fix]

- Expanded Medical Supplies heal-allies with separate non-wounded and wounded permanent-health thresholds. Non-wounded defaults to 15%; 0 effectively disables ordinary top-offs. Wounded defaults to 100%, preserving immediate eligibility after a wound while allowing the host to delay it.
- Added **Do not heal non-wounded Zealots** (on by default) and **Heal Zealot when wounded** (on by default), so Zealot players can retain low permanent health without making a wound lethal.
- While enabled, the configured policy replaces vanilla's fixed 25% / Zealot target-selection rule, then returns only `in_need_of_heal`; vanilla's `BTConditions.can_heal_player` and `BTBotInteractAction` still own threat checks, navigation completion, bandaging, consumption, wound removal, healing, and networking (`player_bot_base.lua:843-1008`, `bt_bot_conditions.lua:773-807`, `bt_bot.lua:87-93`). No heal RPC or replacement action was added.
- Added pure Lua coverage and `/gt_regression_test` check `issue523_bot_heal_allies_policy`.

### Test method

1. Solo-host with bots. Enable Bot Behavior Improvements and Bots heal hurt allies; give a bot Medical Supplies. At the default 15% ordinary threshold, verify it heals the human at or below 15% permanent health but not just above it. Set the threshold to 0 and verify no ordinary top-off occurs.
2. Become wounded at high permanent health. At the default 100% wounded threshold the bot should bandage the human once the coast is clear. Lower the wounded threshold and verify it waits until that value.
3. As non-wounded Zealot below the ordinary threshold, confirm the default exclusion preserves low permanent health. Become wounded and confirm the default wounded-Zealot toggle permits healing; turn that toggle off and confirm it no longer does.
4. A revive/rescue and nearby enemies must retain vanilla priority/safety. Run `/gt_regression_test` and confirm `issue523_bot_heal_allies_policy` passes.

## v0.2.227-dev (2026-07-14) -- #549 Godmode power and ammo children [verify-fix-coop]

- Added two default-off child toggles beneath Godmode: **9999 Damage Per Strike** and **Unlimited Ammo**. Both are inert while the Godmode parent is off.
- Outgoing damage uses the existing `gt_godmode_state` heartbeat's optional trailing flag so a client's setting reaches the authoritative host. The single new `DamageUtils.apply_buffs_to_damage` hook calls vanilla first, preserves its victim/mitigation side effects, then raises only positive enemy damage from the opted-in human to 9999. Friendly fire, self damage, immune zero-damage results, bots, and players without the child toggle stay vanilla.
- Unlimited Ammo reconciles the existing vanilla `twitch_no_overcharge_no_ammo_reloads` buff on the owning player only. It composes with the independent `/infinite_ammo` command: disabling either source cannot strip the buff while the other still owns it, and the command retains its host-wide behavior.
- This fully supersedes duplicate request #382's narrower dev-only fixed-damage cheat: #549 supplies the same fixed high-damage behavior, enemy-only scope, and host-authoritative client state as a Godmode child.
- Added `/gt_regression_test` check `issue549_godmode_power_and_ammo` for the settings, synced predicate, ammo reconciler, positive/enemy-only damage policy, and direct/source-attacker paths.

### Test method (two players)

1. Host enables Godmode and both children. Hit an enemy and fire/reload a ranged or heat weapon; the hit should deal 9999 and ammo/overcharge should not be consumed. Disable Godmode while leaving both children checked; ordinary damage and resource consumption must return.
2. Joining client repeats the same test. The host must apply 9999 to the client's enemy hit, while the ammo effect remains confined to that client.
3. With 9999 Damage enabled, hit an invulnerable/immune enemy result and (where difficulty permits) a teammate; zero immunity and normal friendly-fire behavior must remain, never 9999.
4. Toggle `/infinite_ammo` on, enable the Godmode ammo child, then toggle the command off; the local Godmode child must remain effective. Turn Godmode off and confirm the buff clears. Run `/gt_regression_test` and confirm `issue549_godmode_power_and_ammo` passes.

## v0.2.226-dev (2026-07-14) -- #385 bound close-range no-path teleport retries [verify-fix]

- Source audit identified the formerly `unknown` trigger: vanilla's bot tree has a second `BTBotTeleportToAllyAction` node named `teleport_no_path`, driven by `BTConditions.cant_reach_ally` after sustained path failures and without the 40 m leash distance floor.
- The existing `cant_reach_ally` hook now stamps `vanilla_no_path`, so Bot Teleport Lab D1 records name the real branch instead of inferring only from distance.
- The first close-range no-path teleport remains available. Further no-path teleports while the bot is still below the configured leash are suppressed for five seconds, then allowed to retry; outside-leash, ordinary leash, aid, backward-threshold, and invalid-state paths remain unchanged. Suppression emits one latched raw-console `[gt:385]` line per burst.
- Added pure offline policy coverage and `/gt_regression_test` check `gt_bot385_close_no_path_retry_bound`.

### Test method

As solo host with bots and a 15 m follow distance, reproduce the geometry/path-failure location that previously caused repeated close-range teleports. The first unstick may occur, but no bot may teleport repeatedly within five seconds while below 15 m. D1 must name `vanilla_no_path` or `backward_no_path`, and suppressed repeats must emit one bounded `[gt:385]` line.

## v0.2.225-dev (2026-07-13) -- #241 cover every noclip boundary-death route [verify-fix-coop]

- The latest attached reproduction was a solo listen host, but never emitted the existing `HealthSystem.suicide` suppression record. Source audit identified the missing route: authored kill volumes call `PlayerUnitHealthExtension.entered_kill_volume`, which sends `rpc_request_insta_kill` even on a listen host.
- Noclip now suppresses that local kill-volume callback before it queues or sends the instant-kill request. The existing host `z < -240` suicide gate remains in place.
- Client `z < -240` checks use a third path, `NetworkTransmit.send_rpc_server("rpc_suicide", go_id)`. An exact local-unit/go-id gate now drops only that request while noclip is active, avoiding any need for the remote host to know a client's noclip state.
- All gates require active noclip and the local player identity. Ordinary deaths, other RPCs, remote players, and every route with noclip off remain vanilla; the broad `PlayerUnitHealthExtension.die` funnel is deliberately not hooked.
- Added offline policy coverage and `/gt_regression_test` check `issue241_noclip_boundary_routes`.

### Test method

As solo host, enable noclip and fly sideways through an authored instant-death boundary, then below `z=-240`; neither route may kill the player. Repeat as a joining client for both boundary types. Confirm one bounded `[gt][noclip] issue #241: suppressed ...` record per encountered route, turn noclip off, and verify an ordinary death still works.

## v0.2.224-dev (2026-07-13) -- #548 godmode stagger gate and debuff trace [diagnostics-armed]

- Source audit confirmed that boss launches bypass the HP-damage result through the separate `DamageUtils.stagger_player` funnel. Godmode now drops that stagger call for the protected human without writing a persistent status flag or changing ordinary stagger behavior.
- Added an automatic, observation-only `BuffExtension.add_buff` trace while godmode is active. It records each unique template as `[gt:548]` and stops after 24 session records, allowing Troll Bile and other reported debuffs to be identified from the next normal reproduction without a manual command or speculative blanket buff removal.
- Added `/gt_regression_test` check `issue548_godmode_stagger_and_debuff_probe`. Damage, disabler, stamina, and multiplayer godmode behavior remain on their existing gates.

### Test method

Enable godmode, take a direct monster/boss launch hit, then stand in Troll Bile and reproduce any other debuff. The player must not be launched. Attach the latest log containing `[gt:548]` template records for any effects that still apply, and confirm the #548 regression check passes.

## v0.2.223-dev (2026-07-13) -- #347 trace closed-chest bot pickups [diagnostics-armed]

- Source audit found that human interaction explicitly rejects pickups behind `filter_interactable_in_chest`, while bots use an exclusive-interaction path that bypasses that check. GT's Instant Pickup already forces any pickup that the bot group assigns, so source alone cannot establish whether a closed chest's authored level flow has registered its contents, assignment failed, navigation failed, or pickup consumption failed.
- Added the host-only `/gt_chest_pickup_probe` command. It observes the vanilla availability, chest-raycast, navmesh, `can_loot`, chest-stop, and pickup-stop seams without opening a chest or changing any bot blackboard/pickup state. One explicit arm is capped at 32 classifications and 16 phase-deduplicated `[gt:347]` records.
- Added pure Lua regression coverage and `/gt_regression_test` check `issue347_closed_chest_pickup_diagnostics` for the bounded probe contract.

### Test method (solo host with one bot)
1. Enable Bot Behavior Improvements, Instant Pickup, and Greedy Pickup, then approach a known ordinary closed chest with a bot.
2. Run `/gt_chest_pickup_probe`, wait about five seconds with the chest closed, open it normally, then wait another five seconds.
3. Attach every `[gt:347]` line. A census that changes only after opening identifies dormant/unregistered contents; `available_inside_chest assigned=false` identifies assignment; an assignment without a successful nav/`can_loot` phase identifies dispatch; `can_loot=true` without `pickup_stop` identifies interaction/consumption.
4. Run `/gt_regression_test` and confirm `issue347_closed_chest_pickup_diagnostics` passes.

## v0.2.222-dev (2026-07-13) -- #300 bound awaiting-rescue bot pursuit [verify-fix]

- Added nested controls under `gt_bot_rescue_awaiting`: `Ignore follow leash for awaiting rescues` remains on by default to preserve the existing unlimited pursuit, while turning it off bounds bot selection to the current `gt_bot_follow_distance_m` leash. An off-by-default custom-range toggle can instead use a dedicated 40 m default slider with a 10-100 m range.
- The bound is applied inside gt's existing `PlayerBotBase._select_ally_by_utility` candidate scan before the awaiting ally is relabelled `knocked_down`; no new hook, navigation implementation, interaction, RPC, or network field was added.
- Vanilla source establishes the seams: its ally picker excludes `is_ready_for_assisted_respawn()` players (`player_bot_base.lua:843-1008`), its normal follow teleport threshold is 40 m (`bt_bot_conditions.lua:14,451-480`, `FOLLOW_TELEPORT_DISTANCE_SQ = 1600`), and the native bot interaction remains contextual (`bt_bot_interact_action.lua:71`) so the selected respawn unit still resolves to `assisted_respawn` (`interactions.lua:562`).
- Added `/gt_regression_test` check `issue300_rescue_awaiting_range_policy` for widget defaults/ranges, all three policy modes, clamping, and exact-boundary behavior.

### Test method
1. Host a solo mission with bots and enable `Bots rescue allies awaiting respawn`.
2. Leave `Ignore follow leash for awaiting rescues` on. Enter assisted respawn far from the bots and confirm the historical cross-map rescue pursuit remains available.
3. Turn ignore-leash off and custom range off. Set `Follow snap-back distance` to a recognizable value such as 20 m; confirm an awaiting ally beyond it is not selected, while one inside it is.
4. Enable the custom range, set it to 40 m, and repeat on either side of the boundary. Confirm ordinary revives/rescues and normal follow behavior are unchanged.
5. Run `/gt_regression_test` and confirm `issue300_rescue_awaiting_range_policy` passes.

## v0.2.221-dev (2026-07-13) -- #309 disconnect lifecycle trace [diagnostics-armed]

- Audited the host disconnect path rather than adding a speculative invulnerability flag. Vanilla enters `PeerStates.Disconnecting.on_enter`, removes the peer from the `GameSession`, calls `GameNetworkManager.remove_peer` (which removes every player owned by that peer), clears the party slot, and only then lets the game mode fill the opening with a new host-owned bot. Delaying that function would also delay EAC, game-object, profile, party, and mechanism teardown.
- Added `/gt_disconnect_grace_probe`, an explicit host-only one-event probe. It records the remote player's player/unit/party/slot state immediately before and after `Disconnecting.on_enter`, then at 0.05, 0.25, 1, 3, 10, and 30 seconds. A same-peer `add_remote_player` event is correlated as a reconnect. The probe is capped at 10 records and makes no gameplay or network mutation.
- Added runtime check `issue309_disconnect_grace_diagnostics_armed` and offline coverage for one-shot arming, bounded sampling, and exact-peer reconnect correlation.

### Co-op test method

1. Host enables `gt_dev`, starts a mission with one client, and runs `/gt_disconnect_grace_probe`.
2. The client disconnects while alive, then reconnects within 30 seconds.
3. Attach the host log containing all `[gt:309]` lines. Confirm the pre/post lines establish whether the human unit survives the synchronous teardown and the samples establish when the replacement bot occupies the slot.
4. Run `/gt_regression_test`; `issue309_disconnect_grace_diagnostics_armed` must pass.

## v0.2.220-dev (2026-07-13) -- #304 keep dummy player collision toggle [verify-fix]

- Added an off-by-default Gameplay toggle that lets the local player walk through training dummies in keep-type levels.
- Source tracing showed that player blocking comes from `Breeds.training_dummy.player_locomotion_constrain_radius = 0.7`, copied onto authoritative and husk AI extensions and consumed by `PlayerUnitLocomotionExtension`; it does not require disabling the dummy's collision actors.
- The implementation clears only that per-unit locomotion constraint while enabled in an inn level. It snapshots and restores the native value on toggle-off, level-scope changes, and mod disable, leaving hit-zone actors, targeting, visibility, and damage behavior untouched.
- Added pure Lua policy coverage and `/gt_regression_test` check `gt304_keep_dummy_constraint_scope`.

### Test method
1. In the keep, leave Gameplay > No Player Collision with Keep Dummies off and confirm a training dummy blocks movement normally.
2. Turn it on and confirm you can walk through the dummy while melee/ranged hits still register and its damage readout still works.
3. Turn it off and confirm blocking returns immediately. Enter a mission and confirm ordinary enemies still constrain movement normally.
4. Run `/gt_regression_test` and confirm `gt304_keep_dummy_constraint_scope` passes.

## v0.2.219-dev (2026-07-13) -- #302 invoke local wireframes from active HUD seam [verify-fix]

- The `0.2.216-dev` verification log proved every Debug Highlights toggle was persisted `true` and the `IngameUI.update` hook installed, but the callback never emitted its master-state or draw breadcrumb. The screen projection code therefore never ran.
- Removed the silent `IngameUI.update` hook. Debug Highlights now exposes a draw consumer that is merge-dispatched from GT's existing singleton `IngameHud.update` hook, the same proven HUD-composite seam used by the visible melee-warning overlay.
- Added bounded console-only diagnostics for HUD invocation and distinct world, camera, or screen-GUI blockers. Wireframes remain entirely client-local; no geometry or draw state is networked.
- Added `/gt_regression_test` check `gt_dh_hud_update_invocation_302` for the consumer/export contract.

### Test method
1. In the keep, enable Dev Tools > Debug Highlights and Interactables.
2. Expected: local yellow projected wireframes appear on nearby crafting stations/chests. The log contains `[gt:302] invocation=IngameHud.update active`, `master ON`, and a positive edge count (or one explicit blocker reason).

## v0.2.218-dev (2026-07-13) -- #428 canonical copied debug helper [untested]

- Replaced gt_dev's top-level `_dbg` / `_dbg_alert` implementation with the first consumer of canonical `tools/shared_lib/_lib_debug.lua`. The bundled copy preserves standalone loading; there is no runtime dependency on another mod.
- Behavior is unchanged: expected diagnostics use VMF's gated `mod:debug`, while alerts use pcall-guarded raw `printf` so they reach the console log without repeating issue #240's `mod:warning` chat spam.
- Added a manifest-driven build-time sync tool and blocking exact-byte QA drift check for all copied libraries. Existing peer-parity copies are now covered too.

## v0.2.217-dev (2026-07-13) -- #364 reserve Bardin's Survival Ale for human players [verify-fix]

Bots no longer automatically target Bardin's Survival Ale through either the instant-pickup path or the greedy mule-pickup postpass. The host-owned `AIBotGroupSystem._update_mule_pickups` pass now releases an ale claim vanilla assigned earlier in the tick and excludes ale while selecting a replacement; ordinary potions and bombs retain their existing behavior. The reservation keys off the pickup extension's exact `pickup_name` (`bardin_survival_ale`), matching the career-drop definition in `scripts/settings/equipment/pickups.lua:741-759`, rather than broadly excluding the entire `slot_level_event` slot.

The pickup and consumable helpers are now isolated in `_gt_bot_pickups.lua` and `_gt_bot_consumables.lua`; newer bot fixes remain intact and `_gt_bot_fixes.lua` stays below the repository's 2,500-line hard limit. The existing `PlayerBotBase.update` dispatch remains consolidated, and the pickup module is the sole owner of both `AIBotGroupSystem` pickup hooks.

### Regression
- New `/gt_regression_test` check `gt364_survival_ale_reserved_for_humans` proves the exact ale name is reserved while a normal potion, grenade, and nil remain unreserved.

### Test method (solo host + one Bardin bot suffices)
1. Enable Bot Behavior Improvements, instant pickup, and greedy pickup; trigger Bardin's Survival Ale drop near the bot and an ordinary potion or bomb nearby.
2. Confirm the bot does not target or remotely grab the ale, but can still collect the ordinary mule pickup.
3. Run `/gt_regression_test` and confirm `gt364_survival_ale_reserved_for_humans` passes.
## v0.2.216-dev (2026-07-13) -- #302 Debug Highlights: rewrite renderer to screen projection (the reason it never rendered) [verify-fix]

The user reported (issue #302, 2026-07-12) that the Debug Highlights overlay "has never worked in any way whatsoever" despite four shipped phases. Empirical root cause, from the user's own logs: the draw loop was NOT the problem. `console-2026-07-12-22.03.01` shows `[gt_dev:DH] drawn ... interact=48..60 players=1` once per second in-game -- 48 to 60 wireframe boxes were built and `LineObject.dispatch`ed into `level_world` every frame -- yet nothing appeared. That is direct proof that **a raw `LineObject.dispatch` does not visibly render in retail Vermintide 2.**

### Why LineObject renders nothing in retail (cited)
- Fatshark stripped Lua debug drawing from release builds. The vanilla drawer wrappers resolve to `DebugDrawerRelease` in release (`debug_manager.lua:103`), whose every method -- line/box/sphere/circle AND `update` (which is what dispatches) -- is a bare `return` no-op (`debug_drawer_release.lua`). `Debug.active = BUILD ~= "release"` (`debug.lua:9`), so `Debug.update` never dispatches either. The debug-line render pass is dead for retail mods; calling the native `LineObject.*` directly (as we did) submits into nothing.
- Every overlay that DOES render in retail (floating damage numbers, HUD world markers, objective/ping icons) is a **screen-space gui projected with `Camera.world_to_screen`**, never a LineObject (`damage_numbers_ui.lua:410`, `world_marker_ui.lua:618-624`, `floating_icon_ui.lua:117-131`).
- Timing was not the cause: `Managers.mod:update` runs at the top of the frame, before the world render (`boot.lua:748-772`), so the dispatch was early enough -- it just had no render pass to land in.

### Fix: render exactly the way the shipped HUD does
`_gt_debug_highlights.lua` no longer touches `LineObject`. It now:
- Gets the local player's level-world camera (`Managers.camera:has_viewport("player_1")` -> `ScriptWorld.viewport` -> `ScriptViewport.camera`, per `floating_icon_ui.lua:117-131`).
- Projects each world point with `Camera.world_to_screen` (raw pixels, `.x`/`.y`; confirmed against `world_marker_ui.lua:623` and `ingame_hud.lua:515`), guarded by a forward-dot behind-camera test (`world_marker_ui.lua:359`) so points behind the view are skipped instead of wrapping to garbage.
- Draws 2D lines on a `World.create_screen_gui` (gw_fonts, `immediate`, with the `Application.can_get` material-residency pre-filter that fixed the #293/#295 create CTD) using `ScriptGUI.hud_line` (`script_gui.lua:45`, a rotated `Gui.rect_3d`). A box is its 8 projected `Unit.box` OOBB corners joined by 12 edges (an edge is skipped if either endpoint is behind the camera). Headshot = a small camera-facing square at the head node. Aggro = a 20-segment world ground-circle at `breed.detection_radius`, projected and joined.
- Draws from a `hook_safe("IngameUI", "update")` -- the phase the working retail info mods draw screen guis from (StreamingInfo), which ticks in BOTH the keep and a mission (the user tests in the keep / `inn_level`). NOT `mod.update`: screen-gui draws issued from the frame-top mod update do not reliably render. Rule #8 pre-flight: grep-verified no other gt_dev hook targets `(IngameUI, "update")` (the existing `IngameHud.update` hook is `_gt_melee_warning`'s -- a different pair); whole-mod lint clean (145 hooks, 0 duplicates).

### Secondary fix: `local_player_safe` throw during load
`console-2026-07-12-17.56` logged **929** `player_manager.lua: Network backend has not been set` errors, aborting the draw every frame pre-mission: `local_player_safe` still calls `Network.peer_id()` (`player_manager.lua:595`), which throws during the `StateLoading` window even when `:game()` is truthy. The local-player read is now `pcall`-wrapped -- a nil player is a clean skip. Drawing from `IngameUI.update` (in-game only) removes most of the window anyway.

### Diagnostics (empirical, per the issue's ask to "discover the method")
- One-shot `[gt:302]` breadcrumb on the first frame that emits any edge: logs the edge count, the resolution, and the player's projected `sx/sy`. If that logs positive counts while the user sees nothing, the screen gui itself is the failure point (not enumeration, not projection) -- a decisive single-test result.
- Per-second `[gt_dev:DH] drawn ... edges=N` summary now counts screen edges actually emitted per category.

### Category status (unchanged from prior analysis; render method is the only change this build)
Reachable and rewired to the new renderer: interactables (yellow), item pickups (green), pickup spawn points (grey, visible when empty), enemy boxes (red), player boxes (dark green), headshot markers (orange), aggro rings (amber). Documented-unreachable / deferred, no toggle shipped: level geometry (no `Level.*` collision/mesh API from retail Lua), other trigger volumes (name-keyed only, no enumeration/bounds getter), monster/patrol spawn triggers (host-only conflict-director state), navmesh (host-only + segment-heavy), AI vision cones (regular breeds have no per-breed FOV field; drawing fabricated cones would mislead). These stay for a follow-up once the user confirms the new renderer draws.

### Regression
- Kept all three `_gt_debug_highlights.lua` provenance markers (`gt_dh_live_pos_reads`, `gt_dh_local_player_safe`, `gt459_liveness_gated_dh`); the #459 world-liveness identity gate now guards `World.destroy_gui` (a Gui on a dead world is the same uncatchable AV class as a LineObject was).

### Test method (verify-fix; solo host in the keep suffices for the decisive check)
1. Full Steam restart -> confirm `[gt:LOAD] v0.2.216-dev`.
2. In the keep: Dev Tools -> Debug Highlights ON + Interactables ON. Expected: yellow wireframe boxes appear on the crafting station, chests, and other interactables. Grep the log for `[gt:302] method=world_to_screen: drew N edges` -- N should be > 0.
3. Toggle Item Pickups / Player Hitboxes; start a mission and toggle Enemy Hitboxes / Headshot Zones / Aggro Ranges in a horde. Confirm boxes track units, orange squares on heads, amber rings on the ground.
4. Client check (join as non-host): enemy boxes/heads/rings should still draw (enumeration is per-peer).
## v0.2.215-dev (2026-07-13) -- #303 Freeze AI dev tool (command + keybind) [untested]

A dev-only testing tool that halts every enemy AI in place so you can inspect positioning, hitboxes, or set up a scenario, and pauses new spawns while it is held. Ships BOTH as the `/freezeai` chat command and as a keybind-able "Freeze AI" setting in the dev-only Dev Tools group (`keybind_type = function_call` -> `mod.gt_freeze_ai_toggle`). Host-only: AI brains run on the server, so the toggle refuses on a client with one echo. One confirmation echo per toggle ("AI frozen" / "AI unfrozen"); diagnostics are printf-only (`[gt:303]`).

### Mechanism (two vanilla-respected switches -- cited)
Freeze flips one in-memory flag, `mod._gt_freeze_ai_active` (never set on a client or in the stable stream), which two seams read:
1. **Halt existing + future AI:** the brain gate is MERGED into gt's existing `mod:hook(AISystem, "update_brains")` in `_gt_creature_spawner.lua` (no second hook -- VMF drops it). While frozen it skips the whole brain tick, so `bt:root():evaluate` (`ai_system.lua:882`) never runs for any alive AI unit -- no enemy picks a new attack, target, move, or nav goal. An enemy already moving settles at its last nav step; one already mid-attack may finish that swing before going still (whether the hit lands is breed-dependent -- some fire damage off animation events, not the brain tick -- so this is not claimed either way pending in-game verification). Newly-spawned enemies are frozen the instant their brain would first tick.
2. **Pause new spawns:** `mod._gt_apply_spawn_block()` (main) sets the same `script_data.ai_*_disabled` flag set the vanilla dedicated-server `disable_ai_and_bots` command (`dedicated_server_commands.lua:824-845`) and the Testify `disable_ai` snippet (`testify_snippets.lua:52-73`) flip. Those flags gate the conflict-director pipelines at their read sites: `ai_pacing_disabled` (`conflict_director.lua:930/1475/1536`), `ai_horde_spawning_disabled` (`753/1321/1550`), `ai_specials_spawning_disabled` (`1544`; `specials_pacing.lua:807/892`), `ai_roaming_spawning_disabled` (`1601`), `ai_mini_patrol_disabled` (`1558`), `ai_boss_spawning_disabled` (`enemy_recycler.lua:429`), `ai_critter_spawning_disabled` (`enemy_recycler.lua:387`). Composed (OR) with the `/no_enemies` toggle in `_apply_script_data_no_enemies` + the `ConflictDirector.spawn_unit_immediate` hook, so neither source clobbers the other on toggle-off.

There is no engine `script_data.disable_ai` that gates the retail brain loop (`AISystem.update`/`update_brains` read no such flag), and the `ai_*_disabled` flags only gate spawning -- so freezing already-spawned enemies requires gating the brain tick, which is exactly what the creature-spawner "Mission AI" toggle already proves out.

### Scope / dev-only
Whole feature is dev-stream gated: the module (`_gt_freeze_ai.lua`) registers nothing off the dev stream, and the keybind lives in the Dev Tools group (appended only in the dev clone). State persists until toggled off or a mod reload; the echo makes each transition explicit.

### Regression
- New `/gt_regression_test` check `gt303_freeze_ai_wired`: asserts the toggle body + composed spawn-block applicator are exposed, the Dev Tools keybind is present and points `function_call` at `gt_freeze_ai_toggle`, and `AISystem.update_brains` still exists (catches an engine rename that would silently no-op the freeze).

### Test method (solo host + bots suffices; client is refused by design)
1. In a mission with a horde present, run `/freezeai` (or press the Dev Tools "Freeze AI" keybind): every enemy stops advancing/attacking within a step, and no new enemies spawn. Echo shows "AI frozen".
2. Run it again: enemies resume and spawning returns to normal. Echo shows "AI unfrozen".
3. As a CLIENT, `/freezeai` echoes "Only the host can freeze AI." and does nothing.
4. Compose check: turn on `/no_enemies`, then `/freezeai` on, then `/freezeai` off -- spawns must stay blocked (no_enemies still holds); then `/no_enemies` off restores spawns.
5. `/gt_regression_test` must pass `gt303_freeze_ai_wired`.

## v0.2.214-dev (2026-07-13) -- #355 /suicide and /down self-state dev commands [untested]

Two testing commands for your OWN local player: `/suicide` kills you, `/down` knocks you into bleedout. Both refuse in the keep and echo one confirmation line.

### Mechanism (vanilla client->server request RPCs -- cited)
Both use the SAME idiom vanilla already uses to let a player request its own death/knockdown, so they are network-correct as HOST *and* as CLIENT and carry no modded NetworkLookup key (immune to the #278/#371 wire-safety class):
- `/suicide` sends `rpc_request_insta_kill(go_id, damage_types.forced)` -- the path `PlayerUnitHealthExtension.entered_kill_volume` fires (`player_unit_health_extension.lua:945-955`). The server handler asserts `is_server`, then `die() -> DeathSystem:forced_kill -> kill_unit` and syncs to every peer via `rpc_forced_kill` (`health_system.lua:706-724`, `death_system.lua:282-293`).
- `/down` sends `rpc_request_knock_down(go_id)` -- the path the celebrate "falling down" buff fires (`celebrate_buff_settings.lua:668-671`). The server handler asserts `is_server`, then `knock_down(unit) -> StatusUtils.set_knocked_down_network` (`health_system.lua:668-675`, `player_unit_health_extension.lua:223-228`); the health update transitions health->0 with a full bleedout bar (`player_unit_health_extension.lua:327-330`), so you bleed out like a normal knockdown (same end state `/downbots` drives for bots).

`send_rpc_server` loops back locally on the host and routes to the server channel on a client (`network_transmit.lua:185-198`), so one code path serves both -- no host/client branch and no gt RPC channel. (Contrast the pre-existing `/die`, which calls `death_system:kill_unit` locally: fine solo-host, but a CLIENT `/die` is a local-only death that desyncs. `/suicide` is the correct client-safe replacement.)

### Godmode interaction (#355 req 4)
Both work with gt godmode ON. Godmode only intercepts `DamageUtils.add_damage_network` / `add_damage_network_player` (returns 0 for a godmode unit); the death/knockdown paths bypass that damage layer, so NO self-action exemption is needed (unlike the #529 fatigue gate, which sits on the drain funnel). Documented caveat, not a bug: a godmode player who `/down`s will not bleed out (the knockdown_bleed DoT is add_damage_network, zeroed by godmode) -- they stay down until revived, which is the desired state for testing rescue/aid. `/unkillable` is likewise bypassed by `/suicide` by design.

### Regression
- New `/gt_regression_test` check `gt355_suicide_down_vanilla_rpc_path`: asserts both command bodies are wired, the source marker is present (catches a revert to a local desyncing write), and the two vanilla RPCs + `damage_types.forced` still exist (catches a vanilla API rename).

### Test method (solo host + bots suffices; client path is code-identical)
1. In a mission (not the keep), run `/down` -- you drop into bleedout; run `/suicide` -- you die outright. Both echo a confirmation; neither works in the keep.
2. Turn on `/god`, then `/suicide` (dies) and `/down` (goes down and stays down -- godmode blocks the bleedout, expected).
3. `/gt_regression_test` must pass `gt355_suicide_down_vanilla_rpc_path`.
4. Coop nicety (not required to close): a CLIENT running `/suicide` / `/down` should die/down on ALL peers (proves the host-authoritative sync), whereas the old `/die` desyncs on a client.

## v0.2.213-dev (2026-07-13) -- #378 client watchdog for a missing-mod join that hangs instead of erroring [untested]

Joining a modded host while missing a required mod could hang the loading screen forever with no popup, forcing alt-F4. A client-side watchdog now times the pre-game-start join phase and, on timeout, surfaces the missing-mods reveal (or a plain "join stalled" notice for a non-broadcasting host) plus a Leave button that returns to the main menu. Local-only: it reads Steam lobby_data and shows a local popup -- no new networked sends; fully inert unless we are the joining client (the host path early-outs on `lobby.is_host`).

### Root cause (why the existing reveal never fired -- cited)
The failed-join reveal (`_gt_lobby_failed_join_reveal.lua`) only triggers when a join RESOLVES to `failure_start_join_server_incorrect_hash` (`state_loading.lua:1084`). But the `network_hash` covers only the compiled network config, engine/content revision, the DLC set and the level-key count -- NOT the VMF mod set (`scripts/network/lobby_aux.lua:16-48`, `LobbyAux.create_network_hash`). A host mod that changes breeds/items/buffs or adds a VMF RPC WITHOUT adding a level_key or a DLCSetting leaves the hash EQUAL, so the client passes the hash gate (`state_loading.lua:1068`) and then stalls with no timeout:
- **Pre-hash:** `_verify_joined_lobby`'s `ready_to_compare_data` gate (`state_loading.lua:1004`) never turns true if the host's Steam lobby_data (`network_hash`/`matchmaking_type`/`difficulty`) or `host` never populate client-side -- it loops every frame, `_lobby_verified` never set, no popup.
- **Post-hash:** the `NetworkClient` state machine has a timeout ONLY on `connecting` (`network_client.lua:372-382`, CONNECTION_TIMEOUT=15). `loading` / `loaded` / `waiting_enter_game` wait on host RPCs (`rpc_loading_synced`, `rpc_game_started`) with no bound.

### Fix (client-side; no RPC, host unaffected)
- New watchdog inside `_gt_lobby_failed_join_reveal.lua`: a single `hook_safe` on `StateLoading.update` (grep-verified singleton -- gt's only other StateLoading hook is `create_popup`) captures the live state instance + dt and times the pre-game-start join phase as a non-host client. Level loading (the legitimately slow part) happens AFTER `game_started` (`state_loading.lua:1396-1452`), so gating on pre-game-start means a slow disk cannot false-trip it.
- On timeout it reads the host manifest from Steam lobby_data (reusing the reveal's `_fetch_manifest_for_lobby` / `_diff_mods` / `_build_popup_text`), then reroutes StateLoading to the main menu via vanilla `_destroy_lobby_client` (destroys the session lobby AND sets `_wanted_state = StateTitleScreen`, `state_loading.lua:1128-1145` -- without this a pure hang keeps `_wanted_state` at StateIngame and the teardown would dump the user into a broken session). The popup + Leave-button teardown reuse the existing `_pending_popups` poller. If no manifest is readable (vanilla/non-broadcasting host) the popup states only that the join stalled and offers the Leave -- it never guesses the cause.
- Two new options in Host-Side Lobby Controls > Modded Lobby Manifest: "Recover from a stalled join" (checkbox, default on) and a nested "Stalled-join timeout (seconds)" numeric (default 60, 20-180).

### Regression
- New `/gt_regression_test` check `gt_lobby378_watchdog_abort_reroutes_to_menu`: drives the exported `_wd_reroute_to_menu` against a stub StateLoading and asserts it delegates to `_destroy_lobby_client` (the `_wanted_state` -> menu redirect) and is nil / missing-method safe, so a refactor that force-tears-down WITHOUT the reroute is caught at load.

### Test method (coop, 2 humans -- verify-fix-coop)
1. Human A hosts a lobby with a required (hash-neutral) mod that Human B does NOT have installed -- e.g. enemy_tweaker or a breed/buff mod that changes shared state but adds no level_key/DLC. Human B keeps gt_dev enabled.
2. Human B joins A's lobby. Previously: indefinite loading screen, alt-F4 only exit. Now: within the timeout (default 60s) a popup lists the missing mod(s) with Open Workshop + Leave, OR (if A is not broadcasting its mod list) a "Join timed out" notice with Leave; clicking Leave returns to the main menu.
3. Confirm a NORMAL join (B has all of A's mods) still completes well within the window and shows no watchdog popup.
4. `/gt_regression_test` must pass `gt_lobby378_watchdog_abort_reroutes_to_menu`.

## v0.2.212-dev (2026-07-13) -- #384 bots stop leashing away from a downed teammate mid-aid [untested]

With aid-priority ON, a bot pathing to a downed/disabled/awaiting-rescue teammate no longer gets snap-teleported back to a standing human mid-errand. The bot stays committed until the teammate is up (or the #492 watchdog bails an unreachable one so the bot can regroup). Aid-priority OFF is byte-identical vanilla behavior.

### Root cause (cited)
Vanilla suppresses the bot follow-leash teleport only while `blackboard.target_ally_need_type` is set (`bt_bot_conditions.lua:1226`), but `_update_target_ally` NILS that field on any `_ally_path_allowed` cooldown -- 1 s ahead / 5-10 s behind-segment (`player_bot_base.lua:1948-1983`, the picker drops `in_need_type` at the `not allowed_aid_path` branch). gt's #139 blanket veto is the backstop, but it was blind to the down: it scanned `side.PLAYER_UNITS` (HUMAN-only, and `SideManager.is_valid` drops awaiting-rescue, `side_manager.lua:337-339`,`:396-400`) with a knocked/hook/ledge-only predicate, while `GenericStatusExtension.is_disabled` (`generic_status_extension.lua:2158`) also covers pounce/pack-master/tentacle/chaos-spawn/vortex/corruptor. So a downed BOT, an awaiting-rescue human, or a disabler-grabbed ally produced `VETOED=0` and the bot leashed away (`console-2026-07-06-20.23.14` 10254-10322: bot teleported to the standing human 3x ~2 s after the downed ally's aid flag cleared).

### Fix (host-side; bot AI is server-owned, no RPC/NetworkLookup -- inert on clients)
- `_gt_any_side_teammate_needs_aid` (`_gt_bot_fixes.lua`) now walks `side:player_units()` (`side.lua:222` -- the unfiltered `_player_units` roster that keeps bots AND awaiting-rescue units, the same roster FIX 3's rescue picker uses) with a new broader predicate `_gt_status_needs_aid_or_rescue` (`is_disabled` minus `is_dead()`/`is_overpowered()`, plus awaiting-rescue). Reading the ally's LIVE state every frame is what "pins" the errand across the `target_ally_need_type` flicker. The should_teleport veto and the #515 `cant_reach_ally` veto both consume this helper, so they broaden together; the #492 stall watchdog reads the same scan, so its unreachable-aid bailout composes (an unreachable down/awaiting still bails so the bot regroups -- no stranding).
- Trade-off: a bot no longer leashes past a teammate who merely awaits rescue (the old split+leash micro-benefit). #492 reinstates recovery within its no-progress window.

### Regression
- New `/gt_regression_test` check `gt_bot384_needs_aid_or_rescue_predicate`: drives `_gt_status_needs_aid_or_rescue` through the full 12-case truth table with a stub status extension (knocked/hook/ledge/pounce/pack-master/tentacle/chaos-spawn/vortex/corruptor/awaiting all true; healthy + ledge-pulled-up false) and asserts marker `GT_BOT384_AWAITING_DISABLER_VETO_MARKER`, so narrowing the roster or predicate back is caught at load.

### Test method (coop, 2+ testers -- needs a real downed teammate + a standing human for the leash target)
1. Host with 2 humans + bots (Ensrick + RainReligion pattern), aid-priority ON (Bot Options master + `gt_bot_aid_priority`). One human pushes ~40 m ahead; the other goes down (knocked, then let them bleed to awaiting-rescue) near the bots.
2. Watch a bot assigned to the downed ally: it must path in and stay (revive / rescue), never snap-teleport to the standing human while the ally is knocked, awaiting-rescue, or disabler-grabbed. In the log, `[gt_bot:139] teleport VETOED` should now appear for these states (previously VETOED=0); if the down is genuinely unreachable, `[gt:492] ... BAILED` should fire and only then may the bot regroup.
3. `/gt_regression_test` must pass `gt_bot384_needs_aid_or_rescue_predicate`.

## v0.2.211-dev (2026-07-13) -- #427 _dbg_alert log-only via engine printf [untested]

- `_dbg_alert` rerouted mod:warning -> pcall-guarded engine printf (VMF warning channel posts to chat under default settings; printf survives mod-logging-OFF, never chat; enemy_tweaker issue 240 template). Definition in `general_tweaker_dev.lua`; the `mod._gt_dbg_alert` export consumed by `_gt_lobby_motd.lua` / `_gt_lobby_failed_join_reveal.lua` picks up the new routing automatically.

## v0.2.210-dev (2026-07-13) -- #454 Creature Spawner enumerates breeds live, hardcoded list demoted to category overlay [verify-fix]

The Creature Spawner's unit lists (regular/dummy/misc/special/boss/all) are now built from the LIVE `Breeds` table every time a list is accessed (next/prev cycle, list dropdown change, game-state change), so DLC breeds and mod-added breeds (enemy_tweaker's et_* clones, any other mod's `Breeds[...] = ...` registrations) appear automatically. The old hardcoded 81-entry map no longer gates WHICH breeds are listed; it survives only as a category overlay preserving upstream CreatureSpawner's curated memberships. All lists stay A-Z sorted. Immediate wins vs the old list: `chaos_troll_chief` (boss) and `chaos_tether_sorcerer` (special) were absent from the hardcoded map and now list.

### Mechanics (why this filter, cited)
- Spawnable = has `base_unit`/`opt_base_unit` + `unit_template` (both read unconditionally by `ConflictDirector._spawn_unit`, src conflict_director.lua:1906-1908; nil base_unit is an index crash) + `behavior`/`horde_behavior` (behavior-tree lookup, src ai_simple_extension.lua:106). Player-hero and Versus dark-pact breeds live in the separate `PlayerBreeds` table (src breed_players.lua:5, breed_players_vs.lua:305-311) so they never enter the walk; everything in `Breeds` is stamped `is_ai = true` (src breeds.lua:305-307). Vanilla's own `debug_spawn_all_breeds` walks `pairs(Breeds)` unfiltered (src conflict_director.lua:2606), so field presence is the only real gate.
- Uncurated breeds are slotted by their own flags: `boss = true` to Bosses, `special = true` to Specials, `race = "dummy"` to Dummy/Misc, else Regular.
- Enumeration is LAZY (command time), never at file scope: mods register breeds at their own module load, so a boot snapshot goes stale (the `pairs(Breeds)`-at-boot class from enemy_tweaker ENGINE_SURFACE). Cycling re-locates the saved selection in the fresh list so late registrations do not skip the cursor.

### Regression
- New `/gt_regression_test` check `gt_cs_breed_list_dynamic`: injects a probe breed into `Breeds` at test time, rebuilds via `mod._gt_cs_rebuild_unit_lists`, asserts it lists in all_units + boss_units and that all_units is A-Z, then removes the probe. Marker `GT_CS_DYNAMIC_BREED_LIST_MARKER_v0_2_210` guards against reverts.

### Test method (solo host, 1 tester)
1. Solo host a mission. Set the Creature Spawner list to "All", cycle with next/prev: the list must be A-Z and include `chaos_troll_chief` and `chaos_tether_sorcerer` (absent from the old hardcoded list). Spawn one of them.
2. Enable enemy_tweaker (with its skeleton/warlord breeds registered), same check: its et_* breeds must appear in the list (warlord under Bosses); spawn one.
3. `/gt_regression_test` must pass `gt_cs_breed_list_dynamic`.

## v0.2.209-dev (2026-07-13) -- #529 godmode now makes stamina untouchable by enemies [verify-fix]

With Godmode ON, enemy attacks no longer drain your stamina or break your block/guard: blocked hits, storm vermin sweeps, ogre shoves, boss slams, vomit/plague ground drains, and the grudge-mark and Belakor stamina drains are all skipped. Your OWN stamina costs (push, dodge) still apply as normal (infinite stamina remains the separate /stamina cheat), and stamina-replenish procs (headshot talents) keep working. Blocking looks and sounds normal; the bar just never drops from enemy hits. Godmode OFF is byte-identical behavior.

### Root cause + choke point
Godmode only intercepted the two DamageUtils HP funnels plus disabler states; stamina rides a separate pipe. Every enemy-sourced drain funnels through `GenericStatusExtension.add_fatigue_points` ON THE OWNING MACHINE (`blocked_attack` calls it only when `not player.remote`, src generic_status_extension.lua:630,649; the function hard-rejects remote players, src :781-785; a client's drain arrives via `rpc_player_blocked_attack` and is applied by its own machine, src status_system.lua:466-477). Block-break is inside that same call (fatigue at max -> `set_block_broken`, src :823-825), so skipping the write also fixes guard breaks. The gate is merged into the EXISTING `_gt_hacks.lua` add_fatigue_points hook (singleton (Class, method) discipline) and keys on a self-action allowlist: only enemy/hazard fatigue types are dropped, identified against `PlayerUnitStatusSettings.fatigue_point_costs`. Effective as host AND as client (owner-side write = local authority); nothing networked changes, no max-stamina field touched (consumption-side doctrine).

### Test method (solo, 1 tester)
1. Godmode ON, start a mission, /spawn a horde or stand in one, hold block and let them wail on it: stamina shields must not drop and the guard must never break (block anim/sounds still play). Walk through troll vomit / plague ground while blocking: still no drain.
2. Push and dodge with godmode ON: your own stamina cost still applies and regenerates.
3. Godmode OFF: blocked hits drain stamina and heavy hits break guard exactly as vanilla.
- Regression: /gt_regression_test must pass `gt529_godmode_stamina_gate_wired`.

## v0.2.208-dev (2026-07-12) -- #534 share bot leash lines with other players [untested]

New default-OFF `gt_devtools_share_draws` checkbox under the Dev Tools group. When the host has Bot leash lines on AND this on, the host broadcasts the leash lines it is drawing over a gt-only mod channel; every gt peer with the toggle on redraws them locally with its own LineObject. Only the sparse bot leash lines are shared; dense wireframe highlights and the bot HUD stay local. Host-only source, dev build only, no wire-safety exposure to vanilla peers.

### Slice: why only the leash lines (justified from the draw sites)
The leash lines are the ONE gt overlay whose data is HOST-EXCLUSIVE. Bots exist only on the host and each bot's `follow_unit` is server-side AI state (`_gt_bot_teleport_lab.lua` `_do_draw` reads `_follow_unit(blackboard)`), so a client cannot reproduce them locally. The other draws do not merit sharing: the Debug Highlights wireframes (`_gt_debug_highlights.lua`) enumerate per-peer entities (`get_entities` / `ai_system` broadphase / `human_and_bot_players`) that every peer already has and can draw itself, so sharing them wholesale would flood the channel every frame; the bot behavior HUD is fixed-pixel screen text (`Gui.text`), a per-viewer readout not a world overlay; and `_gt_saved_positions.lua` draws nothing (it is a save/recall teleport tool). The btlab breach/tether "lines" are `printf` log blocks, not world draws.

### Message schema + rate bounds
- RPC `gt_draw_leash`, schema const `mod.GT_DRAW_RPC_SCHEMA = 1` (main file, mirrors GT_LOBBY / GT_AI). Sender prepends it; receiver drops mismatches (VMF_RECIPES § 10).
- Payload = one compact string of `|`-joined groups: `y <x> <y> <z>` (host player, optional) and `b <bx> <by> <bz> [<fx> <fy> <fz>]` per bot (follow coords omitted when the bot has no anchor). RAW world positions as integer decimeters (0.1 m), so no cross-peer unit-id resolution and nothing for a vanilla peer to decode. At the <=4-bot cap the string is ~200 chars, well under the 500-char RPC cap (VMF_RECIPES § 4).
- Host broadcasts to `"others"` at most every 0.15 s (~6-7 Hz); receivers hold the last snapshot and redraw every frame, expiring it after 1.0 s of silence.
- `[gt:534]` printf on send and receive, throttled to 1/s each.

### Wiring (no new class hooks; ONE per pair discipline intact)
- `_broadcast_leash` rides the existing `btlab_draw` update consumer (inside `_do_draw`, host-only path); the client render is a NEW `shared_draw` `mod._gt_register_update` consumer. No `mod:hook` added. The bot machines (448/468/492/515/523) and the 508 dispatcher are untouched.
- The client draw follows the class-32 LineObject lifecycle: `has_world` probe, recreate on world change, identity-gated (`live == w`) cleanup, drop handles on every teardown path. Its own `mod._gt_shared_line_object` handle, separate from the leash / HUD ones.
- Reset `mod._gt_shared_draw` + handles + throttles at the mission boundary in `_reset_mission_state` (mod-table fields, so the above-first-use reset can't hit the class-6 forward-ref-to-global trap).
- Regression checks `gt_draw_rpc_schema_present` + `gt534_leash_share_wired` (runtime-only, no io).

### Test method (needs 2 gt_dev peers: you host + RainReligion client) -- verify-fix-coop
1. Both pin gt_dev (per-mod-id RPC channel; dev and stable can't share it).
2. Host: Dev Tools -> Bot leash lines ON + Share debug draws ON. Play with bots present.
3. Client: Dev Tools -> Share debug draws ON.
4. Expected: the client sees the same yellow bot->follow and cyan bot->host lines the host sees, tracking as bots move (updates ~6 Hz). Host + client logs show throttled `[gt:534] leash-share SENT` / `RECV` lines. Toggling either end off clears that end's overlay within ~1 s; no CTD on Leave Game with the overlay on (class-32 guard).

## v0.2.207-dev (2026-07-12) -- #523 bots actively heal hurt human allies (prototype) [untested]

New default-OFF `gt_bot_heal_allies` sub-toggle (+ a `gt_bot_heal_allies_pct` slider, default 50) under the `gt_bot_behavior_improvements` master. When both are on, a bot carrying Medical Supplies walks up to the neediest hurt HUMAN teammate and channels a heal on them -- wounded (grey health) first, else lowest permanent-health -- when nothing needs reviving and no enemy is right next to the target. With either OFF the `_select_ally_by_utility` hook is byte-for-byte the prior behaviour. Host-side only (bot AI is server-owned); no RPC, no `NetworkLookup` key, no wire field, so nothing a non-host peer can crash or desync on.

### Why (the #468 note was half-wrong)
FIX 12's #468 note asserts "the game has no bot heal-other action". Only half true: `BTBotHealAction` (`bt_bot_heal_action.lua:15,29`) is self-heal only, but a SEPARATE vanilla node already channel-heals an ally -- `bt_bot.lua:87-93` "heal_other", a `BTBotInteractAction` driven by `BotActions.default.use_heal_on_player` (`player_bots_settings.lua:94-97`), gated by `BTConditions.can_heal_player` (`bt_bot_conditions.lua:773-807`). The full navigation + interaction + heal-apply chain exists and works; the bot runs the SAME interaction a human uses, so the heal amount, item consumption, wound removal and networking are all vanilla-native (`interactions.lua:1788` `DamageUtils.heal_network` heal_type "bandage"; `attack_templates.lua:403` `heal_percent` 0.8 = 80% of missing health; wound removed via `StatusUtils.set_wounded_network`, `damage_utils.lua:2545`). Bots "never" heal allies because of the SELECTION gate, not a missing action: `_select_ally_by_utility` only labels an ally `in_need_of_heal` when its PERMANENT health < `WANTS_TO_HEAL_THRESHOLD` (0.25) OR it is wounded, AND the bot values healing them over itself (`self_health_utiliy < health_utility` with `SELF_HEAL_STICKINESS` baked in, `player_bot_base.lua:868,932,935`).

### Shape chosen: widen the dormant node (NOT a BT graft, NOT host-side steering)
The bot tree is compiled ONCE at load from `BotBehaviors.default` via `BehaviorTree:new` (`ai_system.lua:1702-1703`) and the heal_other node is already in it, so neither a runtime graft nor a hand-rolled steer/interact is needed. FIX 13 relaxes only the SELECTION gate from inside gt's EXISTING `_select_ally_by_utility` hook (merged, no new hook -- VMF drops a 2nd on a pair): when `gt_bot_heal_allies` is on, and only when vanilla + FIX 3/3b picked nothing more urgent (need_type nil or attention-only), it relabels the neediest reachable human `in_need_of_heal`. The caller then sets `target_ally_needs_aid` / `interaction_unit` / aid destination (`player_bot_base.lua:710-720,1595-1599`) and the vanilla heal_other node paths the bot in and channels the native heal.

### Added (`_gt_bot_fixes.lua` FIX 13 + data/loc)
- **`gt_bot_heal_allies` (checkbox, default OFF).** Target selection mirrors vanilla's heal-need gates (permanent-health metric, wh_zealot >1-wound skip) but drops the self-vs-other utility bias. Disabled / downed / awaiting-respawn allies are skipped (that is a revive/rescue case, handled by FIX 3/3b), humans only, path-gated (`_ally_path_allowed`), and within a 20 m cap so a bot never abandons the team to chase a far heal.
- **`gt_bot_heal_allies_pct` (slider, default 50, range 10-95):** permanent-health cutoff below which a human is worth healing; wounded players always qualify regardless.
- Helpers `_gt_heal_allies_on` / `_gt_pick_human_heal_target` are declared ABOVE the hook (forward-ref-to-global trap, BUG_CLASSES 6).
- **`[gt:523]` diagnostics (always-on dev, edge-triggered per bot):** `ACQUIRED` on target pick/retarget (hp/wounded/dist) and `CLEARED` when no eligible target remains -- so a field log shows exactly which human the bot chose and why it stopped.
- Corrected the misleading FIX 12 note + `gt_bot_smart_self_heal` tooltip that claimed bots cannot heal others.

### Known limitations (prototype)
- Only fires on a NON-priority-enemy frame (`_update_target_ally` skips the utility picker when the bot has a priority target, `player_bot_base.lua:698`) and `can_heal_player` blocks the channel while any enemy is proximate -- so heal-during-combat does not happen. Intended for a first pass; combat-heal is a later refinement.
- 20 m range cap is fixed (no slider yet).
- Untested in-game; the heal-other node itself is vanilla-proven, but this specific selection widening needs a host + bots repro (below).

## v0.2.206-dev (2026-07-12) -- #469 bots immune to curated mutator/hazard AOE [untested]

New default-OFF `gt_bot_aoe_immunity` sub-toggle under the `gt_bot_behavior_improvements` master. When both are on, BOTS (never humans) take zero damage from a CURATED set of environment/mutator area hazards they cannot reliably path around and die to. With either OFF the two hooks are byte-for-byte the prior godmode behaviour.

### Why
Issue #469: bots can't path around oil-barrel fire, the Khorne exploding-skull curse, and Weaves/Twitch lightning strikes, so they bleed out in AOE fields a human would step out of. Fix negates the hit for bots at the damage seam rather than trying to teach the bot pathing to avoid it.

### Wire safety (no wire work needed)
Bots are owned by the HOST's peer, so the host is the authoritative machine that applies a bot's damage; its decision is final. The feature alters only the LOCAL damage event (`return 0`) -- it sends nothing networked, adds no `NetworkLookup` key, and never touches a `_max_` health field (max-resource doctrine). Gated on `Managers.player.is_server`, so a client never negates a host-bot's damage. Unlike client-godmode there is no client-authoritative bot to broadcast for.

### How (MERGED into the two existing godmode `DamageUtils` hooks -- no new hook, VMF drops a 2nd on a pair)
- `add_damage_network_player` (explosion/profile funnel): match on `damage_profile.name` (every `DamageProfileTemplates` entry carries `.name` = its key, `damage_profile_templates.lua:5646-5650`). `damage_source` is not discriminating here -- timed-explosion sources pass the shared `"undefined"` (`timed_explosion_extension.lua:125`). Signature already captured `damage_profile`.
- `add_damage_network` (liquid/DoT funnel): match on `damage_source`. Signature EXPANDED through arg 8 to capture `damage_source`; all args forwarded verbatim.
- Curated list, each cited (decompile file:line in-code):
  - profile `heavens_lightning_strike` -- Lightning Strike mutator (Weaves/Twitch), `mutator_lightning_strike.lua:44,49` -> `explosion_templates.lua:1417`.
  - profile `curse_skulls_of_fury_explosion` -- Chaos Wastes Khorne skull curse, `mutator_curse_skulls_of_fury.lua:44-48` -> `morris_buff_settings.lua:5174`.
  - profile `bolt_of_change` -- Chaos Wastes Tzeentch bolt curse, `mutator_curse_bolt_of_change.lua:141-147` -> `morris_buff_settings.lua:5050`.
  - source `lamp_oil_fire` (damage_type `burn`) -- oil-barrel ground fire, `liquid_area_damage_templates.lua:768-770`.
- EXCLUDED on purpose (bots still take them): boss slams, warpfire, thrown/friendly bombs, and GAS -- #469 asks for REDUCED (not zero) gas damage, a separate scalar refinement, and death-spirit skulls resolve to the shared `"default"` profile which is not safely filterable.
- **`[gt:469]` diagnostics (always-on dev, per negated event):** logs each negation with the source/profile so a field log proves what was blocked.
- **New `/gt_regression_test` runtime check `gt_bot469_aoe_immunity_wired`:** curated tables loaded with their load-bearing keys, `mod._gt_unit_is_bot` exposed + nil-safe, both settings resolve via `mod:get`. No `io.open` (issue 511).
- Does NOT regress the #492/#515/#468 bot machines in `_gt_bot_fixes.lua`: this is a merge into the main-file godmode hooks and touches none of their code paths.

## v0.2.205-dev (2026-07-12) -- #468 smarter bot self-healing (configurable, anti-waste) [untested]

Gated on the existing `gt_bot_behavior_improvements` master + a NEW default-OFF `gt_bot_smart_self_heal` sub-toggle, so with either OFF the `BTConditions.bot_should_heal` hook is a pure passthrough -- byte-for-byte vanilla. Host-side only (bot AI is server-owned; the hook only reads the host's own bot blackboards and engine extensions -- no RPC, no NetworkLookup key, no wire field), so nothing a non-host peer can crash or desync on.

### Why (the gap behind "supposed to be fixed already")
The heal-decision logic the "Bot Improvements - Combat Returns" workshop mod exposed was DELIBERATELY EXCLUDED from gt (`_gt_improved_bot_combat.lua:23-29`, "no-ops at their defaults"), so "when a bot uses healing" is 100% vanilla and gt had NEVER touched it -- the feature the user remembered does not exist. Two provable wastes in vanilla `BTConditions.bot_should_heal` (`bt_bot_conditions.lua:893-921`): a bot drinks a FULL-heal Draught of Healing at `bot_heal_threshold` 0.40 (`healing_draught.lua:79`), and self-burns Medical Supplies -- which a hurt HUMAN could use -- at 0.20 (`first_aid_kits.lua:72`); plus the item-surplus `force_use_health_pickup` latch (`ai_bot_group_system.lua:2357`) tops a bot off when spare items are on the floor. Note: bots have NO vanilla "heal another player" action (`BTBotHealAction` = self-heal only, `bt_bot_heal_action.lua:15,29`); "bot heals an ally" is a separate new feature, deferred to its own issue.

### Added (`_gt_bot_fixes.lua` FIX 12 + data/loc)
- **`gt_bot_smart_self_heal` (checkbox, default OFF)** under the Bot Behavior master. When on, gt reimplements `bot_should_heal` mirroring vanilla `:904-921` exactly, with three user substitutions:
  - **`gt_bot_self_heal_pct` (slider, default 25, range 5-90):** the HP% threshold, replacing `template.bot_heal_threshold` for both the current- and perma-health checks. Default 25 makes bots hold a draught past vanilla's 40.
  - **`gt_bot_reserve_kits_for_players` (checkbox, default ON):** a heal-OTHER kit (`template.can_heal_other`, Medical Supplies) is held (not self-used) unless the bot is wounded or the surplus latch fired -- so it stays carried/droppable for a human. Draughts (drink-only) unaffected.
  - **`gt_bot_ignore_surplus_selfuse` (checkbox, default ON):** ignore `force_use_health_pickup`.
  - Any missing blackboard field -> passthrough to the vanilla `func` (bot AI ticks every frame; nil deref = hard crash).
- **`[gt:468]` diagnostics (always-on dev, edge-triggered per bot):** logs each decision flip -- `SELF-HEAL greenlit` and, crucially, `self-heal HELD BACK (vanilla would have healed)` with item/hp/perma/wounded/thresholds -- so the next field log shows exactly the waste gt prevented.
- **New `/gt_regression_test` runtime check `gt_bot468_smart_self_heal_wired`:** LOAD marker present, gating helper exposed, all four settings resolve via `mod:get` with the consumed types. No `io.open` (issue 511).
- Does NOT regress the shipped #492/#515 bot machines: FIX 12 is a fresh `(BTConditions, bot_should_heal)` hook (duplicate-hook grep clean) and touches none of their blackboard fields.

## v0.2.204-dev (2026-07-12) -- loc + hygiene: restart_level_hotkey title; mem-probe off _G [untested]

### Fixed
- **`restart_level_hotkey` had a tooltip loc entry but no TITLE entry** - the only `check_name_integrity` failure in the repo (surfaced by the issue 516 full-gate run). Added `[untested] Restart Level` per LOCALIZATION_STANDARD section 13.
- **Mem-probe baseline off the bare `_G` global** (issue 510 class, same fix as mp/dcp/vdl): now `mod._mem_probe_t0` - a mod field rather than a new top-level local because this chunk lives near the Lua 5.1 200-local ceiling. Both in-file readers updated; no cross-file reader exists (grep-verified).

## v0.2.203-dev (2026-07-12) -- #515 bots teleport past no-return thresholds (composes with #142 + #492) [verify-fix]

All three changes are gated on the existing `gt_bot_ignore_backward_gate` (+ Bot Behavior master) toggle, so with the toggle OFF every path stays byte-for-byte vanilla. Host-side only: bot AI is server-owned, and these paths only read/write the host's own bot blackboards and call the vanilla teleport action (which already syncs `has_teleported` over the game object) -- no new RPC / NetworkLookup key / wire field, so nothing a non-host peer can crash or desync on.

### Why (issue 492 rejection, item 3)
There is NO dedicated "point of no return" teleport-disable in vanilla; the only gates that stop a bot regrouping are in `BTConditions.should_teleport` (backward-segment gate `target_segment < self_segment`, bt_bot_conditions.lua:1220-1222; 40 m distance; aid exception) and in `cant_reach_ally` (same backward gate :1183-1187). gt already bypassed the should_teleport segment gate (#142), but three gaps remained: the `has_teleported` one-shot latch could permanently block a re-teleport, the bypass never reached the aid/`teleport_no_path` node, and a #492-bailed bot still could not teleport back across a boundary.

### GAP 1 -- re-arm the one-shot teleport latch (`_gt_bot_fixes.lua`)
Vanilla sets `blackboard.has_teleported = true` in the teleport action (bt_bot_teleport_to_ally_action.lua:93) and clears it ONLY in `BTBotFollowAction.enter` (bt_bot_follow_action.lua:14) -- the follow branch. A bot that teleports and then goes straight into combat / an aid pursuit (never re-entering the follow node) holds the latch forever, so a second shove past a threshold can never teleport.
- **New pure `mod._gt515_should_rearm(has_teleported, toggle_on, now, last_tp)`**: clears the latch when the toggle is on, the latch is set, and it has been held >= `GT515_REARM_COOLDOWN_S = 3` s since the bot's last ACTUAL teleport (the `BTBotTeleportToAllyAction.run` hook now stamps `blackboard._gt515_last_tp_t`). Re-arm runs at the TOP of the `should_teleport` hook (before `func()`), so a cleared latch re-arms vanilla's own 40 m rule too, AND the shared latch for GAP 2. The downstream distance / path-fail gates still gate the ACTUAL teleport, so a close, following bot never re-teleports; the cooldown is only the anti-spam backstop, sized inside the 3..12 s band vanilla itself uses to declare a follow target unreachable (bt_bot_conditions.lua:1203, player_bot_base.lua:1943-1946).

### GAP 2 + GAP 3 -- backward bypass on the aid/`teleport_no_path` node (`_gt_bot_fixes.lua`)
- **New hook on `BTConditions.cant_reach_ally`** (the condition for the follow-selector `teleport_no_path` node, bt_bot.lua:431-435) -- a SEPARATE (Class, method) from `should_teleport`, so no VMF duplicate-hook collision (only other BTConditions hooks in the mod are `can_activate_ability` + `should_teleport`). Vanilla's forward decision is returned untouched; only the NEW backward path is added.
- **New pure `mod._gt515_cant_reach_backward_decide` + engine wrapper `mod._gt_cant_reach_ally_backward_wants`**: mirror vanilla `cant_reach_ally` (bt_bot_conditions.lua:1189-1203) MINUS the `is_backwards` early return (:1183-1187). `is_forwards` is false for a backward target, so the fails threshold is the stricter non-forward 5 and the same `t - last_success > 5` dwell + `moving_toward_follow_position` gate still apply -- a sustained failing path IS the proof of unreachability. Unlike `should_teleport` this node has NO 40 m floor, so it covers the close-range no-return case (a ledge into the next room ~15 m away) the leash misses.
- **Composes with #139 / #492 exactly as `should_teleport` does**: while aid-priority is ON and a teammate needs aid, the new backward teleport is VETOED so the bot does not abandon a REACHABLE revive -- UNLESS the #492 watchdog already bailed this bot out of an UNREACHABLE aid pursuit (`blackboard._gt492_bailout`), in which case the backward teleport is exactly how it regroups (GAP 3). The #492 machine (`_gt492_step`, the `[gt:492]` printfs, the picker/veto actuator) is unchanged.

### Observability (PROJECT_STANDARDS 2.2b tier c, always-on dev, no toggle)
- **`[gt:515]` printf at each new decision point, per-event (never per-frame):** latch re-arm (per re-arm), `cant_reach_ally` backward VETO and backward ALLOW (latched via `blackboard._gt515_creach_latched`, one line per transition). The allow path also stamps `blackboard._gt139_tp_reason = "backward_no_path"` so the existing `BTBotTeleportToAllyAction.run` `[139:bot_tp]` probe names the trigger.

### Regression
- **`gt_bot515_teleport_latch_rearm`** (new): marker + drives `_gt515_should_rearm` across latch-unset / toggle-off / no-time / in-cooldown / cooldown-elapsed / nil-last.
- **`gt_bot515_cant_reach_backward_bypass`** (new): marker + seam exposure + drives `_gt515_cant_reach_backward_decide` across forward-owned-by-vanilla / backward-fires / fails-threshold / dwell / not-moving. Both are runtime-only (no `io.open`, per #511).

### In-game verify (issue 515)
Host a run with 2 bots, Bot Behavior master + "Bots go back for stragglers and past no-return points" both ON. Get a bot shoved past a one-way threshold (over a ledge / through a drop into the next area) so the team is behind it and it cannot walk back. Expected WITH the toggle on: within a few seconds the bot teleports back to regroup, and the newest console log shows `[gt:515] cant_reach_ally backward bypass -> teleport_no_path` (close-range case) or a re-armed latch / backward `should_teleport` for the far case; if it happens twice in a run, the second teleport still fires. Turn the toggle OFF and repeat: the bot stays vanilla-stuck (no `[gt:515]` line, no teleport). Reachable-down control: a teammate down right next to a bot must still be revived normally and NOT trigger a backward teleport away. Requires `[gt:LOAD] v0.2.203-dev` after a full Steam restart.

## v0.2.202-dev (2026-07-12) -- #492 REWORK aid-pursuit recovery + #511 io-nil regression-check repair [verify-fix]

### #511: regression checks threw `io` nil in the VMF sandbox (false FAILs)
The VMF Lua sandbox exposes NO `io` library (discovered via enemy_tweaker; et 0.7.33-dev fixed the same class). Every `/gt_regression_test` check that verified wiring by reading its own source with `io.open` threw `attempt to index global 'io' (a nil value)` and reported FAIL on healthy code. gt_dev had 22 `io.open` sites across ~18 checks.

- **All 22 io source-reads removed.** Each check keeps its RUNTIME residual (marker constant / functional drive / data-tree require walk); the io self-grep is gone.
- **Two positive load-time provenance markers added** where the invariant is genuinely source-level (et pattern, team-lead named): `_gt_debug_highlights.lua` sets `mod._gt_dh_local_player_safe` (issue 508, right where `local_player_safe` is called) and `mod._gt_dh_live_pos_reads` (issue 302/337, next to the `Unit.local_position` live-read helper); the two dh checks now assert those flags in-game.
- **Three more crash-guard invariants kept in-game via load-time markers:** `_gt_bot_teleport_lab.lua` sets `mod._gt_btlab_gui_create_material` to the exact `create_screen_gui` material so `btlab_gui_material_guarded` asserts it is `gw_fonts` (never arial/FONT_MTRL, the #293/#295 C-fatal); both LineObject cleanup sites set `mod._gt459_liveness_gated_lab` / `_dh` so `gt_459_lineobject_cleanup_liveness_gated` asserts the AV guard is present.
- **One check converted to a live runtime assertion:** `bot_fix_delays_read_from_settings` now checks the two delay sliders resolve to numbers via `mod:get` (proving they are registered and readable) instead of grepping for the `mod:get(...)` call text.
- **Duplicate-hook counts routed to their real home:** the several checks that grepped for "exactly one hook on (Class, method)" now rely on `tools/mod-lint/lint-mod.ps1`, which already enforces the VMF single-hook rule mod-wide (PROJECT_STANDARDS 2.2b tier a).
- **Residual STATIC source-text invariants flagged for a repo QA gate (tier a), NOT reimplemented here** (per instruction, no `qa/` scripts written): dh no-`POSITION_LOOKUP` / no-bare-`:local_player()` absence; `#139` veto conjunction + master/sub gate text; aid-scan side-scoped-not-follow body; `#492` picker/veto wiring text; `#383` split-branch follow_position writes; `#261` tighter-leash slider read + FIX 10 follow-range gate refs + improved-combat `CHASE_MAX_DIST_SQ`/`_enemy_path_allowed` cap; `#142` veto-after-backward source ORDER; dev-tools sed-safe `get_mod("gt".."_dev")` gate; btlab `running_nodes`/`gt_devtools_bot_hud`/`[gt:btlab:breach]`/`[gt:btlab:tether]`/`IS_DEV_STREAM` tags; btlab zero-class-hooks; btlab `can_get`-prefilter text; `#459` `live == w` gate text; `#448` `attacker_unit == owner`/`bot_player`/`is_knocked_down` gates; `#62` absent-`IngameUI.handle_menu_hotkeys`-hook; `#73` both `set_override_player` calls.

### #492 REWORK: fast, within-down-window recovery for the aid-pursuit lock

### Why (owner rejected the v0.2.198-dev fix)
The v0.2.198-dev recovery bounded the aid-priority pursuit lock at 35 s of no progress. The owner removed the verify-fix: 35 s is far too long -- a downed player is often dead in under 5 s, so the bound almost always fired AFTER the down had already resolved, making it useless. Two suspected repro conditions also went uninstrumented: (1) the bots themselves were down (cannot aid), and (2) players in a spot the bots cannot path to. This rework acts within the down window, solves the thrash the long timer was guarding against a better way, and instruments both conditions.

### Changed (item 1 -- rework the bound)
- **`_gt_bot_fixes.lua`: the `mod._gt492_step` decision machine now bails on EITHER of two fast signals instead of one 35 s timer, and the signature gains `path_failed`: `_gt492_step(state, aid_unit, aid_dist, path_failed, t)`.**
  - **NO-PATH (fast, primary, `GT492_PATH_FAIL_CONFIRM_S = 4` s):** the engine's own aid pathing already records whether the last path attempt to that ally failed -- `cb_ally_path_result` stores `path_status.failed = not success` into `self._attempted_ally_paths[ally]` (player_bot_base.lua:1911-1934), fed by the aid navigation goal at :1588/:1601. A sustained failure IS the engine saying it cannot route there (nav gap / far ahead / past a threshold). Valid at any distance (a failing path is itself the proof).
  - **NO-PROGRESS (backstop, `GT492_NO_PROGRESS_TIMEOUT_S = 8` s):** far (`> GT492_FAR_DIST_M = 20` m) with the straight-line distance never closing `> GT492_PROGRESS_EPSILON_M = 2` m. Distance-GATED so a bot fighting the horde right next to a reachable down (small, stable distance) is never pulled off the revive -- `can_revive` gates on threat (bt_bot_conditions.lua:748), so a close stall is combat, not unreachability.
- **Numbers justified from the down window:** knocked-down bleed is 10 dmg / 3 s (buff_templates.lua:4521-4531 + buff_function_templates.lua:342-355) against a pool equal to full max health (curse debuffs cleared while down, player_unit_health_extension.lua:193-196) -- a generous floor of tens of seconds, but real combat down windows are far shorter (owner: often < 5 s). Vanilla itself declares a follow target unreachable on this timescale: `cant_reach_ally` uses `t - last_success > 5` (bt_bot_conditions.lua:1203) and `_ally_path_allowed` a 3..12 s distance-scaled wait (player_bot_base.lua:1943-1946), so 4 s sits at the fast end of the band the engine already treats as "give up".
- **Anti-thrash (the better fix for what the 35 s timer protected against):** once bailed for a down-ally the latch HOLDS -- it no longer clears on a couple of metres of transient closing (the old behavior, which let a bot that teleported back near the team re-commit and re-stall). It un-latches ONLY when the ally no longer needs aid (target changes/clears -> #139 "all bots converge" preserved for every reachable case) or the bot gets genuinely close again (`<= GT492_REACHED_DIST_M = 12` m -- reachable now, so revive). `FAR_DIST (20) > REACHED_DIST (12)` gives the hysteresis that kills oscillation.

### Added (item 2 -- observability, PROJECT_STANDARDS 2.2b tier c, always-on dev, no toggle)
- **`[gt:492]` printf at the two decisive branch points, each with a roster census** (`_gt492_aid_census`: alive helpers who could revive, downed humans, downed bots -- via `player.bot_player`, player_bot.lua:23):
  - **FAR-pursuit START:** fires once per new aid target when the down is already far (`> 20` m), so a field log captures the unreachable-looking chase even if the down resolves before a bail. Close downs (the common case) never log.
  - **BAIL:** names WHICH signal fired (`reason=no-path` vs `no-progress`), the downed teammate (name + is_bot), distance, and the census. One line settles the owner's two hypotheses: bots-themselves-down shows `downed_bots` high / `alive_helpers` low; unreachable-spot shows `reason=no-path` + a large distance.

### Regression
- **`gt_bot492_aid_stall_recovery` updated** for the new signature and behaviors: far no-progress bails and latches; a close (in-range) stall NEVER bails; sustained aid-path failure bails fast; reaching the ally clears the latch; a new target resets.

### Item 3 (teleport past a point-of-no-return) -- assessed, NOT implemented here
Decompile assessment (for a dedicated follow-up issue): there is NO separate "point of no return" bot-teleport-disable mechanic in vanilla. The ONLY gates that stop a bot teleporting back to the team are in `BTConditions.should_teleport` -- the backward-segment gate `target_segment < self_segment` (bt_bot_conditions.lua:1220-1222) plus the 40 m distance and aid exception. gt already bypasses that segment gate with `gt_bot_ignore_backward_gate` (via `_gt_backward_teleport_wants`), so item 3 largely REDUCES to that existing toggle. It is separable from this fix and was left alone; see the report for the residual gap (backward-gate default/master gating and the `has_teleported` one-shot latch).

### In-game verify (issue 492)
Host a run with 2 bots, aid-priority ON. Drop down a one-way ledge / cross a gap the bots cannot path across, go down there (or have a teammate go down there), and push ~150 m ahead. Expected: within ~4-8 s the bots stop committing to the unreachable down and teleport up to regroup, and the newest console log shows `[gt:492] ... BAILED aid pursuit (reason=no-path ...)` with the roster census. Compare to a reachable down right next to a bot: it must revive normally and NOT bail. Requires `[gt:LOAD] v0.2.202-dev` after a full Steam restart.

## v0.2.201-dev (2026-07-12) -- issue 448 test harness: `/downbots` forces all bots into bleedout [verify-fix]

### Added
- **New host command `/downbots` (+ "Down Bots (Morr's test)" keybind under Level Control).** The in-game repro harness the user asked for so the shipped issue 448 fix (`_gt_bot_fixes.lua` FIX 11, downed bots must not grant Morr's Protection) can finally be verified: it forces every standing bot into the downed/bleedout state at once. Host-only (`knock_down` is server-authoritative, `player_unit_health_extension.lua:224`; bots are host-side); keep-guarded (`DamageUtils.is_in_inn`); skips bots already down / awaiting rescue / dead.
- **Mechanism -- `set_knocked_down` field, not raw damage.** Sets each bot's health extension `set_knocked_down = true` (a plain boolean field, the SAME one vanilla sets at spawn for `health_state == "knocked_down"`, `player_unit_health_extension.lua:126-127`). The extension's own server update consumes it next tick and calls `self:knock_down(unit)` (`:291-295`) -- the exact path lethal damage takes to down a live player (`:298-301`). Chosen over the user-suggested "10000 damage" because raw lethal damage is wounds-dependent: it would OUTRIGHT KILL a bot on its final wound (or vary by difficulty) instead of downing it. The field path is wounds-independent yet still drives the full network-synced knockdown plus the `knockdown_bleed` DoT (`buff_function_templates.lua:354`) that Morr's `invulnerable` perk blocks -- so the soft-lock repro is faithful.
- New callable lives on `mod.gt_down_bots` (VMF keybind `function_call` + chat command both resolve it), co-located with `gt_kill_bots` in `_gt_level_control.lua`. No new hooks, no RPC, no network wire -- host-local only.

### In-game verify (issue 448)
- Host a Chaos Wastes run with bots; get two bots each carrying the Morr's Protection boon. In a mission (not the keep), stand them within ~10m of each other and run `/downbots` (or the keybind). Expected with the fix ON (default): both bots bleed out normally and the console shows `[gt:448] downed bot carrier: Morr's Protection aura grant suppressed` once per downed bot -- no permanent invulnerability, no soft-lock. Toggle "Downed bots don't grant Morr's Protection" OFF and repeat to see the original bug (neither bleeds out). Requires `[gt:LOAD] v0.2.201-dev` in the newest console log after a full Steam restart.

## v0.2.200-dev (2026-07-12) -- #508 FIX: debug_highlights error spam before the network backend exists [untested]

### Fixed
- **#508: `_gt_debug_highlights.lua` `_local_player_unit()` now uses `PlayerManager.local_player_safe`.** With the `gt_debug_highlights` master toggle persisted ON, the `_draw` consumer ticks in the boot/menu phase too, and bare `local_player()` routes straight to `Network.peer_id()` with no readiness guard (decompile `player_manager.lua:580-586`), asserting `Network backend has not been set` once per frame (60/s in console-2026-07-12-17.56.05, first at 17:56:30.518). `local_player_safe` (`player_manager.lua:588-596`) nil-checks `Managers.state.network` and `network:game()` first - the vanilla API for exactly this update-consumer timing. Draw behavior in-mission is unchanged: by the time a player unit exists, both calls resolve identically.
- **Dispatcher hardening (`mod.update` consumer loop): repeat identical errors are suppressed.** A consumer error now logs once per distinct message per streak instead of every frame; a success (or a different error) re-arms the line. Boot-phase recoverable failures no longer flood chat/log while still leaving one actionable line with the consumer name. Applies to every `mod._gt_register_update` consumer, not just debug_highlights.
- **New `/gt_regression_test` check `gt_dh_local_player_safe_508`:** fails if a bare `:local_player()` call is reintroduced into `_gt_debug_highlights.lua` (sibling-file source-pattern read, soft-skip on packaged builds - same shape as `gt_dh_no_position_lookup_reads`).
- Loc: `gt_debug_highlights` master title tag `[untested]` -> `[verify-fix]` (LOCALIZATION_STANDARD section 13 co-move).

## v0.2.199-dev (2026-07-12) -- #500 remove the stale #198 training-dummy probe (closed issue) [untested]

### Changed
- **#500: removed `_gt_probe_dummy_hits.lua`** (issue 198, `[198:dummy]`, CLOSED). Pure passive telemetry: hook_safe `TrainingDummyHealthExtension.add_damage`, bucketed per-swing hit counts flushed via `mod._gt_register_update("gt_probe_dummy_hits_flush", ...)`. No gameplay effect, no cross-file consumers (whole-mod grep: the only references were its own dofile line + comment; the flush registration key is looked up by nobody). Removed the file (`git rm`) + its `mod:dofile` line from `general_tweaker_dev.lua`. `.package` uses a `scripts/mods/general_tweaker_dev/*` glob, so no manifest edit was needed.
- **KEPT `_gt_debug_probes.lua`** (not in #500, no closed-issue tag). It is the always-on-in-dev Debug Mode harness and exposes load-bearing cross-file symbols consumed elsewhere: `mod._dbg_log` / `mod._dbg_alert` (mission-UI + AI-takeover modules + the `dbg_helpers_two_channel` regression check), `mod._dbg_on` and `mod._gt_dump_ai_now` (AI-takeover module). Its remaining probes (AI-takeover redesign, bot-loadout resolution, patrol-crash, burning-fire VFX) track OPEN/active work, not closed issues. Left byte-identical.
- **NOTE (do not ship without review):** the identical `_gt_probe_dummy_hits.lua` also exists in the STABLE `general_tweaker/` directory. It is promotion-gated and was NOT touched here.

## v0.2.198-dev (2026-07-12) -- #492: bounded recovery for the aid-priority bot pursuit lock (bots strand behind) [untested]

### Why (root cause)
User report (issue 492 / #449, 1-major): with aid-priority ON, two gt bots stranded 130-175 m behind the humans for ~8 min on dlc_castle while a teammate stayed knocked_down, inflating ConflictDirector loneliness to 62.6 (threshold 25) and arming the #449 cutscene-spawn class. The #139 decision ("all bots converge to revive") pins `blackboard.target_ally_need_type = "knocked_down"` and drops the follow leash so the bot paths in -- but NOTHING bounded that pursuit, so an effectively-unreachable down (long detour / nav gap / unclearable threat / humans pushing ahead) commits the bot forever. The #449 log shows the tell: the D4/D5 should_teleport probes (which fire unconditionally at the top of gt's should_teleport hook) went fully silent 01:26:26-01:34:04 -- the BT engine never evaluated should_teleport. BT structure explains it (bt_bot.lua): the teleport node ("teleport_out_of_range", condition should_teleport) sits at :308-312, BELOW the revive selector (:14-32, can_revive) and the priority-combat node (:305, has_priority_or_opportunity_target) in the same top-level BTSelector. So (a) while a higher node wins (fighting the horde around the down, or looping the revive interaction) should_teleport is never reached, and (b) even when reached, vanilla returns false while target_ally_need_type is set (bt_bot_conditions.lua:1226-1228) and gt's own #139 veto also returns false. can_revive keys on target_ally_need_type == "knocked_down" (bt_bot_conditions.lua:738), so clearing that field breaks BOTH locks at once. The prior #139 veto (returning false in should_teleport) was therefore NOT the sole mechanism -- a higher node kept should_teleport from being evaluated at all.

### Changed
- **`_gt_bot_fixes.lua` -- new #492 stall watchdog (`mod._gt492_aid_stall_tick`), dispatched from the SINGLE consolidated `PlayerBotBase.update` hook** so it runs every frame (the picker `_select_ally_by_utility` is skipped by vanilla on a priority-enemy frame, player_bot_base.lua:698, so the update hook is the reliable clock). It tracks the nearest downed/hooked/ledge teammate -- SAME scope as the #139 veto's `_gt_any_side_teammate_needs_aid` -- and its straight-line distance as a progress metric. If the bot goes `GT492_STALL_TIMEOUT_S = 35` s with no net progress (distance never dropped > `GT492_PROGRESS_EPSILON_M = 2` m below the running best), it latches `blackboard._gt492_bailout`.
- **Picker (`_select_ally_by_utility`) actuator:** on `_gt492_bailout` for the bailed target it DROPS the aid pick (returns no ally at both the vanilla-found-aid return and the FIX 3b force-pick return), so `_update_target_ally` clears `target_ally_need_type` (player_bot_base.lua:721-723) -- breaking the revive lock (via can_revive) and the should_teleport refusal at once.
- **#139 veto (`BTConditions.should_teleport` hook) steps aside** on `_gt492_bailout` (added `not blackboard._gt492_bailout`, kept contiguous with the `_gt_aid_priority_on() and _gt_any_side_teammate_needs_aid` gate the regression checks assert). The bot then re-evaluates teleport at >= 40 m and rejoins the team.
- **Self-clearing:** the bailout re-arms aid the instant the bot makes net progress toward the target, the target changes (a nearer/other ally goes down), or the aid need ends -- so the #139 "all bots converge to revive" decision is fully preserved for every REACHABLE case. UNCONDITIONAL within aid-priority (a safety valve, no new menu toggle). Host-side; distance-only (no extra engine pathing calls).
- **Diagnostics:** `[gt_bot:492]` printf when a bailout latches, naming WHO was down (player name via `Managers.player:owner`), the bot, the stall duration, and current/best distance -- so the next log names the stranded teammate (the issue asked for this).
- **New `/gt_regression_test` check `gt_bot492_aid_stall_recovery`:** marker present; the pure state machine (`mod._gt492_step`) bails after the timeout and re-arms on progress / target change (functional, synthetic sequence); and both actuator halves are wired (picker calls `mod._gt492_should_suppress_pick`, veto reads `blackboard._gt492_bailout`).

### Notes
- No new hooks -- the watchdog dispatches from the existing consolidated `PlayerBotBase.update` hook, and the picker/veto edits fold into gt's existing single hooks on those seams (CLAUDE.md non-negotiable 8). No settings/loc changes.
- Scope: recovers the aid-priority pin. If the bot is in genuine sustained close combat (has_priority_or_opportunity_target wins, should_teleport not reached), it keeps fighting until the fight ends -- unchanged, and out of scope for this issue.
- `[untested]` until the user confirms in-game (solo-verifiable: host with 2+ bots; see the verify step).

## v0.2.197-dev (2026-07-11) -- #448: downed bots stop granting Morr's Protection (mutual-invulnerability soft-lock) [untested]

### Why (root cause)
User report (issue 448, 0-critical): two bots downed close together become permanently invulnerable, can't be finished, can't act, and the run soft-locks. "Morr's Protection" is the Chaos Wastes boon `deus_knockdown_damage_immunity_aura` ("Downed friends near you are invulnerable", per the ct boon loc dump). It is a server-authority aura (deus_power_up_settings.lua:2371-2392): every buff tick the CARRIER grants `deus_knockdown_damage_immunity_buff` -- perk `invulnerable`, NO duration (deus_power_up_settings.lua:175-190) -- to every knocked-down ally within 10m, removing it when the target leaves range / stands up / the carrier is dead awaiting rescue (`deus_knockdown_damage_immunity_aura_func`, morris_buff_settings.lua:872-921). The carrier's OWN knocked-down state is never checked (:887 gates only on `is_ready_for_assisted_respawn`), so a downed carrier keeps projecting the aura. Two boon-carrying bots downed within 10m grant each other the invulnerable perk forever: it also blocks the knockdown bleed-out, enemies can't finish them, nobody revives them, soft-lock. The user's requested behavior ("downed bots should not grant Morr's Protection buff") matches the verified mechanism exactly -- the grant source IS the downed carrier; no divergence.

### Changed
- **FIX 11 (`_gt_bot_fixes.lua`):** wraps `BuffFunctionTemplates.functions.deus_knockdown_damage_immunity_aura_func` (dispatch is a dynamic table lookup every tick, buff_extension.lua:794; same shipped pattern as the huntsman hook in `_gt_solo_qol.lua:497`). While the aura owner is a BOT and knocked down: the vanilla grant tick is skipped and any immunity buff THIS owner granted is stripped via vanilla's own removal path (`get_non_stacking_buff` + `buff.server_id` + `remove_server_controlled_buff`, morris_buff_settings.lua:900-908), source-gated on `buff.attacker_unit == owner` (buff_system.lua:244 -> buff_extension.lua:615) so a standing carrier's aura on the same target is untouched. Humans (downed or not) and standing bot carriers pass straight through -- byte-for-byte vanilla behavior. Grants resume the moment the bot is revived.
- **New toggle `gt_bot_no_downed_morrs_grant`** -- independent, default ON. Independent of the default-OFF Bot Options master because a 0-critical soft-lock fix must be live by default; still a toggle (unlike the unconditional FIX 0 crash guard) because it changes a boon's gameplay behavior. Default ON per the issue-142 precedent: the reported behavior is the bug.
- **Diagnostics:** `[gt:448]` printf when a suppression episode starts (latched once per downed episode, cleared on revive -- the aura ticks per-frame, so unlatched logging would spam) plus a not-armed printf if the aura func is missing from `BuffFunctionTemplates.functions` at load.
- **New `/gt_regression_test` check `gt_bot448_downed_morrs_grant_suppressed`:** FIX 11 marker present; exactly ONE hook on the aura func; strip keeps its `attacker_unit == owner` source gate; bot/knocked-down gates present.

### Notes
- Host-side only (vanilla func early-outs on non-server, morris_buff_settings.lua:873; bots exist host-only). No new wire traffic: the strip uses a vanilla API on a vanilla buff, no modded NetworkLookup keys. No new (Class, method) hooks -- the only other `BuffFunctionTemplates` hook in gt_dev targets a different key.
- `[untested]` until the user confirms in-game (solo-verifiable: hosted CW run with the boon on bots, get two bots downed near each other; enemies must be able to finish them).

## v0.2.196-dev (2026-07-11) -- #459: world-liveness identity gate on cached LineObject cleanup (host Leave Game AV) [verify-fix]

### Why (root cause)
Deterministic C-level access violation (0xc0000005 @0x160) on EVERY host Leave Game with the Bot Teleport Lab overlay on. The overlay caches a LineObject and its owning World in mod fields. On Leave Game, `StateIngame.on_exit` calls `PlayerManager.exit_ingame` (nils `is_server`, player_manager.lua:180) five lines before `_teardown_world` destroys the level world (state_ingame.lua:719). VMF `mods_update` keeps ticking between game states, so the next `_btlab_draw` frame took the "not Managers.player.is_server" branch into `_clear_and_null`, which called `LineObject.reset` + `LineObject.dispatch` on the FREED handles. The pcall around the calls cannot catch a C-level AV -- it was on the crashing stack. Vanilla never dispatches into a destroyed world (navigation_group_manager.lua:843, debug.lua:419 clean up while the world is alive).

### Changed
- **`_gt_bot_teleport_lab.lua` `_clear_and_null`:** the reset/dispatch engine calls now run ONLY when the currently-live `level_world` is IDENTICAL to the cached world handle (`live == w`, via `has_world` + `world`). The identity check is load-bearing: `has_world` alone passes when a NEW same-named world exists while the cached handle points at the freed old one. The cached fields are ALWAYS nulled regardless -- a destroyed world already freed its line objects, so dropping the handles IS the teardown. Skip path printfs `[gt:459] skipped LineObject cleanup - cached world is dead` (at most once per teardown; the nulled fields stop repeats).
- **`_gt_debug_highlights.lua` `_clear`:** byte-identical latent bug (it mirrors `_clear_and_null`); same identity gate, tag `[gt:459:DH]`.
- **Bare `world("level_world")` fassert exposure** (`WorldManager.world` fasserts on a missing world, world_manager.lua:111-115): `_gt_bot_teleport_lab.lua` `_do_draw` and `_gt_debug_highlights.lua` `_world()` (both mods_update draw paths) now probe `has_world` first and bail cleanly; `_gt_solo_qol.lua` boss-sphere draw (EnemyRecycler.update hook) gets the same guard; `_gt_melee_warning.lua` `_play_warn_sound` had a nil check BELOW the fasserting call that could never fire -- now probes `has_world` first.
- **New `/gt_regression_test` check `gt_459_lineobject_cleanup_liveness_gated`:** fails if either cleanup site loses the `live == w` identity gate.

### Notes
- No new hooks; no settings/loc changes; guards are unconditional (never toggle-gated). `_reset_mission_state` (btlab) already used the correct drop-handles-only pattern and is untouched. `_gt_creature_spawner.lua:342`'s bare `world()` is user-command-driven in-mission only (camera reads above it fail first outside a mission) -- left as is.
- New repo-level `docs/BUG_CLASSES.md` class 32 (cleanup-on-teardown into a destroyed world is itself a use-after-free; identity-check the cached world).

## v0.2.195-dev (2026-07-06) -- debug highlights: live position reads (fix per-frame error spam, nothing rendering) [verify-fix]

### Why
First live use of the issue 302 debug highlights (in the keep, 2026-07-06 session on v0.2.194-dev) spammed 3031 per-frame errors -- `_gt_debug_highlights.lua:259: bad argument #1 to 'distance_squared' (Vector3 expected, got userdata)` -- and drew nothing: the draw aborts at the first culled unit every frame. Root cause is the issue-337 bug class: the draw runs as a mod.update consumer, where `POSITION_LOOKUP`'s raw Vector3 entries are DEAD temporaries for units the engine has not refreshed in that section. The file already dodged this for the local player read (v0.2.189) but still trusted the lookup for every other unit (`_unit_pos`, the aggro-circle read, and the player-box loop). Not a v0.2.194 regression: all `gt_dh_*` toggles were still false in every earlier session, so the draw path had never executed.

### Changed
- `_gt_debug_highlights.lua`: all unit positions are now LIVE reads (`Unit.local_position` via the pcall-guarded `_unit_pos`); the `POSITION_LOOKUP` alias and its three read sites are gone.
- New `/gt_regression_test` check `gt_dh_no_position_lookup_reads`: fails if anyone reintroduces a `POSITION_LOOKUP` index into `_gt_debug_highlights.lua`.

### Refs
issue 302 (debug highlights), issue 337 (POSITION_LOOKUP-dead-in-mod.update bug class).

## v0.2.194-dev (2026-07-06) -- bot leash: split follow_position (issue 383) + ignore the backward/segment teleport gate (issue 142) [untested]

### Why
Two coupled bot-follow gaps. issue 383: FIX 9 (split bots one-per-human) only re-pointed `data.follow_unit`, leaving `data.follow_position` fanned around vanilla's single selected_unit -- so a split bot followed one human's index but stood next to a DIFFERENT human (movement reads follow_position, `player_bot_base.lua:1655`). issue 142: bots refuse to teleport or path BACKWARD along the main path -- vanilla `should_teleport` (`bt_bot_conditions.lua:1220-1222`) and `_ally_path_allowed` (`player_bot_base.lua:1962-1978`) both bail when the target's conflict segment is behind the bot, so a player who drops behind is abandoned until they catch up.

### Changed
- **issue 383 -- FIX 9 now splits follow_position too.** When the split reassignment moves a bot off vanilla's selected_unit, gt recomputes `data.follow_position` as a navmesh fan point around that bot's OWN human, reusing the engine's own destination-point helpers (`_selected_unit_is_in_disallowed_nav_tag_volume` / `_find_cluster_position` / `_find_destination_points` / `_find_destination_points_outside_volume`, `ai_bot_group_system.lua:744-791`) sized to the per-human bot count, so bots keep vanilla spacing near their human. Any nav failure falls back to leaving the vanilla follow_position untouched (never stamps the raw player position -- the old too-close report). Bots left on vanilla's human keep vanilla's already-correct fan point; hold_position bots are still skipped.
- **issue 142 -- new sub-toggle `gt_bot_ignore_backward_gate`** (default ON, nested under the Bot Options master, `[untested]`). When on: the FIX 7 tighter leash skips its behind-segment gate; a new `_gt_backward_teleport_wants` fallback fires a teleport (same `gt_bot_follow_distance_m` threshold, >= 40 m == vanilla's 1600 sq) to a follow target vanilla and the tighter leash both declined for being behind; and FIX 3b force-revive ignores `_ally_path_allowed`'s behind-segment cooldown for aid-needing allies so the bot retries the revive immediately. The #139 blanket aid veto stays the FINAL check on the combined decision (a downed teammate still overrides a backward leash), and the aid exception is preserved throughout. Vanilla's own `_select_ally_by_utility` segment skip is left untouched.
- **Four new `/gt_regression_test` checks** (always-on in dev): `gt_bot383_fix9_splits_follow_position` (marker + fan-helper nil-return fallback + source pattern), `gt_bot142_backward_wants_no_segment_gate` (stub-blackboard truth table: beyond-threshold behind target -> true; has_teleported / target_ally_need_type / priority target -> false; within threshold -> false), `gt_bot142_veto_still_final` (source order: backward branch before the #139 veto), and `gt_bot261_leash_conflict_invariants` (tighter leash reads the slider; improved-combat `CHASE_MAX_DIST_SQ` still bounds `_enemy_path_allowed`; FIX 10 greedy-pickup follow-range gates intact; exactly one hook each on `should_teleport` and `BTBotTeleportToAllyAction.run`).

### Notes
- No new hooks added -- all changes merge into the already-hooked `should_teleport`, `_select_ally_by_utility`, and `_assign_destination_points` bodies. The Bot Teleport Lab d4 segment probe still reports VANILLA's raw comparison; its comment now flags that the issue-142 override can teleport on a BLOCK.
- Host-side only (bot AI is server-side); no RPC, so all changes are inert / crash-safe on clients. `[untested]` until confirmed in-game.

## v0.2.193-dev (2026-07-06) -- issue 275 CLOSED (user-confirmed in-game): constant-true BTConditions guard collapse

### Why
issue 275 (Nurgloth stuck in his final phase at full health on The Enchanter's Lair) is CLOSED: the user confirmed in-game on v0.2.191-dev that the fight is healthy -- the intro health gate steps 0.65 -> 0.32, `transition_at_two_thirds` flips, and the fight is completable. Root cause was gt's collapsing `(cond and func(...)) or true` guard on `BTConditions.transitioned_one_third_health` (fix commit b166251, shipped v0.2.191-dev). The adjacent gut cutscene wired-`on_skip` policy (gut commit d4784dc) is confirmed CORRECT behavior -- the boss cinematic plays by design -- not part of this softlock. Docs-and-loc close-out only; no gameplay change.

### Changed
- **LOC:** `gt_cs_group` (Creature Spawner) status tag trimmed from `[verify-fix] [Issue 254 & 275]` to `[verify-fix] [Issue 254]` -- issue 254 is still open, so its ref and the verify-fix tag stay; only the confirmed-closed 275 ref is removed (LOCALIZATION_STANDARD s13).
- **Docs:** new `docs/BUG_CLASSES.md` class 26 ("Collapsing `and`/`or` guard in a hook wrapper") -- the constant-true idiom, the "grep BTConditions hooks first on any phase-machine misbehavior" diagnosis order, the explicit-branch fix template, and the repo idiom-sweep caveat. New `general_tweaker_dev/POSTMORTEMS.md` with the full issue 275 timeline (why the symptom pointed at gut Skip Cutscenes, the two wrong level-key identifications, and why diagnosis needed a breed-field-wrapped blackboard probe -- `AiBreedSnippets` table hooks are bypassed by the breed's direct function references captured at load, and `BTConditions` hooks must wrap before `create_all_trees`).

### Notes
- Regression net already lives (v0.2.191-dev): `gt_cs_transitioned_one_third_not_forced` asserts the helper truth table so the collapse cannot silently return. The `[et:275]` phase probe stays armed in enemy_tweaker (untouched here).

## v0.2.192-dev (2026-07-06) -- #139 hardening: regression tests + BUG_CLASSES for the bot-teleport leash veto

### Why
#139 (bots teleport AWAY from downed players) was fixed by the v0.2.185-dev blanket leash veto and confirmed working in-game 2026-07-06; the issue is being closed. This entry adds the regression net so the fix cannot silently regress and future sessions do not repeat the follow-scoped diagnostic mistake that made the bug hard to see. No gameplay change.

### Changed
- **Three new `/gt_regression_test` checks** (always-on in dev, output via the harness echo/printf):
  - `gt_bot139_needs_aid_status_predicate` -- drives the status truth table with a STUB status extension: knocked / hanging-from-hook / ledge-hanging-and-not-pulled-up return true; healthy and already-pulled-up return false. Catches a refactor that narrows the covered disabler set or drops the "not pulled up" clause.
  - `gt_bot139_teleport_veto_singleton_and_gated` -- asserts EXACTLY ONE `BTConditions.should_teleport` hook in `_gt_bot_fixes.lua` (VMF drops a 2nd on the same pair, which would shadow the veto) and that the veto still gates on `_gt_aid_priority_on()` AND a downed side teammate, with the aid gate reading both `gt_bot_behavior_improvements` and `gt_bot_aid_priority`.
  - `gt_bot139_aid_scan_is_side_scoped_not_follow` -- structural + behavioral guard that `_gt_any_side_teammate_needs_aid` scans the SIDE player list (`side.PLAYER_UNITS` via `side_by_unit`) and never the bot's follow target. This is the exact root-cause trap: vanilla `_update_move_targets` (`ai_bot_group_system.lua:695-719`) drops disabled players from the follow set unless every human is down, so a follow-scoped aid check is blind to a teammate who goes down while the bot is leashed to a living far player.
- **Testability seam in `_gt_bot_fixes.lua`** (behavior-identical): the status-extension -> needs-aid boolean is split into a pure `_gt_status_needs_aid(st)` that `_gt_unit_needs_aid` now calls (the OR expression is byte-for-byte the former inline body -- the unit boundary can't be stubbed because `ALIVE[u]` reads the engine `POSITION_LOOKUP` map, `global_utils.lua:15`). Exposes `mod._gt_status_needs_aid` / `_gt_unit_needs_aid` / `_gt_any_side_teammate_needs_aid` / `_gt_aid_priority_on` as pure accessors, matching the existing `mod._gt_apply_fast_reactions` pattern. The veto decision logic in the `should_teleport` hook is untouched.
- **Docs:** new `docs/BUG_CLASSES.md` class 25 (guards scoped to a bot's follow target are structurally blind to downed teammates; residual blind spots: broader `is_disabled` states, awaiting-rescue filtered out of `PLAYER_UNITS`). `docs/BUG_TRIAGE_RUNBOOK.md` gains a log-signature row steering bot-teleport investigations at the btlab probes (`[gt:btlab:d1/d2/d3/breach]`) rather than the follow-scoped `[gt_bot:139]` lines.

### Notes
- Out-of-scope gaps left for the open leash work and deliberately NOT covered by these tests or the fix: pounced / tentacle / vortex / corruptor / pack-master disabler states raise no need-aid; awaiting-rescue teammates are invisible to `PLAYER_UNITS` scans (use `side:player_units()`); `_gt_unit_needs_aid_or_rescue` is probe-only dead code.

## v0.2.191-dev (2026-07-06) -- #275: fix constant-true transitioned_one_third_health guard collapse (Nurgloth final-phase-at-spawn softlock) [verify-fix]

### Why (root cause)
The Creature Spawner's Drachenfels/Nurgloth phase hook read:
```lua
mod:hook(BTConditions, "transitioned_one_third_health", function(func, ...)
    return (_gt_cs_is_in_level("dlc_castle") and func(...)) or true
end)
```
Intent: outside `dlc_castle` force TRUE so a Creature-Spawner-spawned Nurgloth skips
its arena-specific defensive phase; inside the real arena (incl. CW `dlc_castle_*`
variants) defer to vanilla. The boolean COLLAPSES: in `dlc_castle`, when vanilla
correctly returns `false` (boss has not yet passed the one-third-health transition),
`(true and false) or true` still yields `true`. The condition was CONSTANT TRUE
everywhere, forcing Nurgloth's BT straight into "final offense phase"
(`chaos_exalted_sorcerer_drachenfels_behavior.lua:239`) at full health with the
intro's 0.65 min-health gate never lowered - so the real Enchanter's Lair boss
fight was broken/softlocked, always. `BTConditions.transitioned_one_third_health`
(`bt_conditions.lua:355`) returns `current_health_percent <= 0.33 and
one_third_transition_done`; `bt_node.lua` resolves conditions by name every
evaluation, so the collapsed guard poisons every tick.

### Evidence
`[et:275]` probe capture (2026-07-06 author log):
`[et:275] HOOK sorcerer_drachenfels_go_offensive_intense | hp_pct=1.000 ... two_thirds_done=nil one_third_done=nil`
(final-offense phase entered at full health, transitions never flagged).

### Changed
- `_gt_creature_spawner.lua`: rewrote the hook body with explicit branching via a
  new pure helper `mod._gt_cs_one_third_wrapper(in_arena, ...)` - inside the arena
  return vanilla's result unaltered (multi-return preserved), outside force `true`.
  Extended the intent comment with the 2026-07-06 collapse post-mortem + probe line.
- `general_tweaker_dev.lua`: new `/gt_regression_test` check
  `gt_cs_transitioned_one_third_not_forced` asserts the helper's truth table
  ((true,false)->false, (true,true)->true, (false,false)->true, (false,true)->true),
  wired to the same helper the hook calls so the collapse can never silently return.
- Idiom sweep of the whole repo for `(cond and func(...)) or <literal>` hook tails:
  only this line was a genuine collapsing-guard bug (it wraps a BOOLEAN condition
  where `false` is the meaningful in-arena case). The other same-shape lines
  (`BTSpawnAllies.run`, `BTLootRatFleeAction.{enter,run,leave}`, the navmesh-query
  guards) wrap functions that return truthy BT-status strings / tables / discarded
  values in their defer branch, so their `or <default>` tails do not corrupt a
  meaningful return - left unchanged.

### VERIFY IN-GAME (#275)
Enchanter's Lair: Nurgloth must run THREE defensive/offensive phase cycles (waves at
100->66%, 66->33%, 33->0) with the health gate stepping 0.65/0.32/0 (`[et:275]` STATE
lines show `two_thirds_done` then `one_third_done` flipping true), and the fight must
be completable.

## v0.2.190-dev (2026-07-06) -- #241: suppress ledge-grab + out-of-bounds death while noclipping [verify-fix]

### Why
Noclip flips locomotion to `script_driven_no_mover` and teleports the body each
frame, but it never changes the character STATE MACHINE. So while free-flying the
player's CSM sits in `falling` (or `catapulted`), and those states still run two
world-boundary safety mechanics that yank you out of noclip:
- **Forced ledge-grab.** `PlayerCharacterStateFalling.update` (falling.lua:254) and
  `...Catapulted.update` (catapulted.lua:95) call `CharacterStateHelper.is_ledge_hanging`
  every frame; a hit does `csm:change_state("ledge_hanging", ...)`, which lerp-snaps you
  onto the ledge (the "teleport-back" in the report) and disables control.
- **"Fell out of the world" death.** The inline `z < -240` check in both states routes
  through `HealthSystem.suicide(self, unit)` on the host (health_system.lua:176) - so
  flying below the map kills you.

### Changed
- `_gt_noclip.lua`: three new hooks, ALL gated on `(_noclip_active AND unit == local
  player)` so they are completely inert with noclip off or for any other unit:
  - `CharacterStateHelper.is_ledge_hanging` -> `false` for the local player. Both falling
    and catapulted call it by direct table access (no upvalue capture), so one hook covers
    both. Stops the forced grab + the lerp-snap teleport-back.
  - `CharacterStateHelper.will_be_ledge_hanging` -> `false` for the local player (the
    predictive jumping/leaping path).
  - `HealthSystem.suicide` -> no-op for the local player. Kills the `z < -240` host-side
    death (latched `printf` logs the first suppression per fly episode, not per frame).
- KNOWN FOLLOW-UP (noted on #241): when the local player is a *client*, the `z < -240`
  check sends `rpc_suicide` to the remote host, and the death is decided there - out of
  reach of a client-side hook. Covered cleanly for the host case (the repro); the client
  edge is deferred on #241.
- Pre-flight: grepped general_tweaker_dev for existing hooks on these three (Class,
  method) pairs -- none. gt bot code uses the extension method `get_is_ledge_hanging()`,
  a distinct symbol.
- VERIFY IN-GAME: load a mission, `/noclip` on, fly OUT past the level boundary and DOWN
  below the map. Expected: no forced ledge-grab / control loss near ledges, and no "fell
  out of the world" death below the map - you keep flying. `/noclip` off to land normally.
  (Log carries `[gt][noclip] issue #241: boundary-safety suppression armed` on load and
  `... suppressed out-of-bounds suicide` the first time you dip below z=-240.)

## v0.2.189-dev (2026-07-05) -- #337 round 2: POSITION_LOOKUP live seed + debug-highlights + bot-HUD player read (#293/#295 retest) [verify-fix]

### Why
v0.2.188's one-tick deferral did NOT fix the false "teleport failed" (user re-test on
v0.2.188, same error). Root of the miss: mod.update fires from ModManager:update at the
TOP of the frame (boot.lua:749) - the same pre-refresh window chat commands run in
(vmf_loader.lua:52-54, mods_update_event and execute_queued_chat_command are adjacent
lines in the same caller). The LOCAL PLAYER's POSITION_LOOKUP entry is a dead Vector3
handle in every mod-reachable phase - deferral cannot escape it.

### Changed
- `_gt_saved_positions.lua`: seed `POSITION_LOOKUP[unit]` with a context-fresh
  DESTINATION Vector3 immediately before `teleport_to`, so `set_falling_height`
  (its last line, generic_status_extension.lua:2590) reads a live handle carrying the
  correct post-teleport z regardless of phase. Harmless one-frame poke: the engine's
  bulk refresh rewrites the table before any other reader runs. Queue + drain retained
  for re-validation and last-write-wins; docstrings corrected (the v0.2.188 "same phase
  vanilla uses" claim was wrong).
- `_gt_debug_highlights.lua`: same bug class in the overlay draw - it read
  `POSITION_LOOKUP[player_unit]` every frame from mod.update, raising "bad argument #2
  (Vector3 expected, got userdata)" 1182x in `console-2026-07-05-17.19.28` and aborting
  the draw (nothing rendered). Now reads `Unit.world_position(player_unit, 0)` live.
- `_gt_bot_teleport_lab.lua`: SAME bug class in the Dev Tools bot-behavior HUD +
  leash-line draw (the #293/#295 retest -- user confirmed the overlay was INVISIBLE even
  though the log showed "HUD gui created OK"). `_do_draw` read the local player's dead
  `POSITION_LOOKUP` handle for `you_pos` / the follow-unit pos and fed it to
  `Vector3.distance` / `LineObject.add_line`; the throw was silently swallowed by the
  `pcall(_do_draw)` wrapper, so NO `Gui.text` ever ran (hence no error in the log
  either). Added a guarded `_live_pos(unit)` helper (Unit.world_position) and routed
  every draw-phase position read through it; the d1..d10 observer probes keep
  POSITION_LOOKUP (they run in the live BT-action phase where it is valid).
- VERIFY IN-GAME: (1) save + recall a position - lands with saved look AND echoes
  "Recalled to position slot N", no failed message; check the log has no
  `[gt:saved_pos] ... FAILED` line. (2) Turn on a Debug Highlights category - wireframes
  actually render now (and no `debug_highlights ... distance_squared` error spam).
  (3) In a mission with bots, turn on Dev Tools > bot behavior HUD - the per-bot columns
  actually appear on screen now (leash lines too if enabled).

## v0.2.188-dev (2026-07-05) -- #337 fix false "teleport failed" on /recall_position_N [verify-fix]

### Why
User report: the #306 save/recall teleport works (position + look land) but every recall
echoes "teleport failed". Log (`console-2026-07-05-17.19.28-51bb12ee...`, v0.2.187-dev,
inn_level, 3x repro at 17:24:18/:24/:32):
`generic_status_extension.lua:2616: bad argument #1 to '__index' (Vector3 expected, got userdata)`.

### Root cause
`teleport_to` applies mover + position + rotation FIRST, then ends with
`status_extension:set_falling_height()`, which reads `POSITION_LOOKUP[unit].z`
(generic_status_extension.lua:2586-2593). POSITION_LOOKUP holds raw Vector3 stack
temporaries refreshed once per frame in `StateIngame.pre_update` (state_ingame.lua:808),
valid only inside that frame's Vector3 pool. The VMF chat-command callback runs outside
that window, so the entry is a dead handle: the teleport lands, the last line raises, the
pcall reports failure, and `set_ignore_next_fall_damage(true)` is skipped (a recall onto a
high ledge would take fall damage). Every vanilla `teleport_to` caller is an update-phase
BT bot action (bt_bot_teleport_to_ally_action.lua:84 etc.) - vanilla never sees this phase.

### Changed
- `_gt_saved_positions.lua`: `/recall_position_N` now only QUEUES (plain-number payload,
  frame-boundary safe); a new `saved_pos_recall` consumer in the central update registry
  (`mod._gt_register_update`, Issue #16) drains it one tick later inside the game-update
  phase and performs the teleport there. Drain re-validates unit/level and owns the
  success/failure echo. PHASE RULE documented in the file docstring.
- VERIFY IN-GAME: save + recall a position - lands with saved look direction AND echoes
  "Recalled to position slot N" (no failed message). Bonus: recall onto a high ledge -
  no fall damage from the recall itself.

## v0.2.187-dev (2026-07-05) -- #302 Debug Highlights (phase 1: in-world wireframe overlay)

### Why
Issue #302: a nested Dev Tools menu of toggles that visualize normally-invisible gameplay geometry in-world with colored wireframes, to make testing and bug-repro faster. The issue flags this as a research + phase-1 task: ship the feasible categories well, produce evidence-based feasibility verdicts for the rest.

### Changed
- **New file `_gt_debug_highlights.lua`** (dev-only, no new hooks). One shared `LineObject` per level world, rebuilt and dispatched every frame from `mod._gt_register_update("debug_highlights", ...)`. Draw core / lifecycle copied from `_gt_solo_qol.lua`'s boss-sphere debug draw (`Managers.world:world("level_world")` -> recreate on world change -> `World.create_line_object(world, false)` -> `LineObject.reset` -> add primitives -> `LineObject.dispatch(world, lo)`). Everything OFF == zero per-frame work (early-out before any enumeration); `_clear()` erases lingering lines and the mission-enter chain-wrap drops the stale world handle.
- **Seven working categories, all client-safe, all default OFF** (master `gt_debug_highlights`, children under it via the VMF native master-toggle submenu):
  - `[untested] Interactables` (yellow box) -- `get_entities("GenericUnitInteractableExtension"/"LocalInteractableExtension")`, `interactable_system.lua:11-17`.
  - `[untested] Item Pickups` (green box) -- the four pickup extensions `pickup_system.lua:22-28`; `POSITION_LOOKUP[unit]`.
  - `[untested] Pickup Spawn Points` (grey box, shown even when empty) -- `get_entities("PickupSpawnerExtension")`, client-safe route (`pickup_system.lua:110`).
  - `[untested] Enemy Hitboxes` (red box) -- `ai_system` broadphase query around the player (`ai_system.lua:94`), `Unit.box(unit)` OOBB.
  - `[untested] Player Hitboxes` (dark green box) -- `Managers.player:human_and_bot_players()`, `Unit.box(unit)`.
  - `[untested] Headshot Zones` (orange sphere, APPROXIMATE) -- sphere at the breed head node (`breed.hit_zones[headshot-zone].actors[1]`, `breed_skaven_clan_rat.lua:89-97`); true hit-capsule dimensions are not exposed to Lua, so a fixed ~0.28 m radius proxy is drawn and labeled as such in the tooltip.
  - `[untested] Aggro Ranges` (amber ring) -- `add_circle` at `breed.detection_radius` (`breed_skaven_clan_rat.lua:18`). Enemy perception is a radius + line-of-sight, not a cone.
  - `[untested] Draw Distance` dropdown (20/30/50 m, default 30): all enumeration is distance-culled from the local player and unit-capped per category (this runs per frame).
- **Wired** `mod:dofile("scripts/mods/general_tweaker_dev/_gt_debug_highlights")` in the main file; Dev Tools group widgets added to `general_tweaker_dev_data.lua`; loc titles + tooltips added (titles carry `[untested]` per LOCALIZATION_STANDARD section 13; tooltips name the color and both approximations).
- **Always-on dev diagnostic** via engine `printf` tagged `[gt_dev:DH]`: one line when the master flips on/off, and one per second MAX summarizing per-category draw counts. No new `mod:hook` -- update-registry + enumeration only.

### Notes
- **WIREFRAME ONLY this build.** The issue also asks for translucent fills; filled world-gui triangles are deferred to a later phase (LineObject draws outlines, not filled faces).
- **Deferred categories with feasibility verdicts** (evidence for the #302 tracking comment; no widget shipped for these to avoid dead toggles):
  - **Ragdoll hitboxes (deep grey):** DEFERRED -- no clean client-side ragdoll-unit enumeration was established this round. Follow-up: identify the ragdoll unit set (candidate: dead AI still in the broadphase vs a ragdoll-state flag) before shipping.
  - **AI vision cones:** DEFERRED (no honest general implementation). No per-breed FOV/angle field exists in the source (`fov`/`view_angle`/`field_of_view` not found as breed data). Regular enemy perception is 360 degrees within `detection_radius` + a LOS raycast (`target_selection_utils.lua`); the only real cones are hardcoded constants for specific states -- patrol passive `view_cone_dot = 0.5` (`target_selection_utils.lua:938`) and sleeping rat-ogre `view_cone_dot = 1` (`ai_breed_snippets.lua:54-59`). The aggro ring already carries the honest detection-range picture; a real cone would apply only to patrols (host-only blackboard state).
  - **Monster/patrol spawn triggers (light red/pink):** FEASIBLE but HOST-ONLY, deferred. Enumerable via `Managers.state.conflict.level_analysis.terror_spawners[*].spawners` (`level_analysis.lua:650-664`) + patrol main-path nodes (`level_analysis.lua:426-431`, `Vector3Box:unbox()`). Conflict-director data is not populated on clients. A clean host-gated follow-up.
  - **Navmesh (purple):** FEASIBLE but deferred on perf grounds (the issue puts it in the research-only bucket, code only if trivially safe -- a full per-frame navmesh redraw is not). Triangle enumeration IS exposed: `GwNavWorld.build_database_visual_representation` -> `database_tile_count` -> `database_tile_triangle_count` -> `database_triangle` returns per-triangle vertices (`navigation_utils.lua:33-83`). Needs its own tile-cull + throttle design; host-side `nav_world` from the conflict director.
  - **Level geometry (white):** INFEASIBLE-as-specified. No `Level.*` binding returns collision or render meshes to outline (full `Level.*` surface audited; nothing exposes mesh/bounds). Closest proxy would be the navmesh wireframe as a floor stand-in.
  - **Trigger volumes / other triggers:** INFEASIBLE-as-specified. Trigger volumes are name-keyed only -- `Level.is_point_inside_volume(level, name, pos)` membership tests exist, but there is no enumeration and no bounds getter (`volume_system.lua`). Only nav-tag volumes carry exportable geometry (`<level>_nav_tag_volumes.lua`).
- **Host/client:** every SHIPPED category is client-safe (enumeration is per-peer), so no host gating was needed; the deferred spawn-triggers and navmesh categories are the host-only ones.
- Still `[untested]` -- needs an in-game pass per category (see the issue). Enemy/headshot/aggro enumerate via the AI broadphase, proven in-repo host-side; client-side broadphase population is the main thing the in-game test must confirm.

## v0.2.186-dev (2026-07-05) -- #332 Disable mutator death explosions now works client-side

### Why
Issue #332: two Visuals-and-Audio options came from the True-Solo QoL mod (where you are always host) and only worked as host. Part 1 (Disable mutator death explosions) is fixed here; Part 2 (Max Ragdolls) still needs a live client-session verify before deciding its fix, so it is untouched.

### Changed
- **`gt_solo_disable_mutator_explosions` now suppresses the CLIENT render path too.** The purple Explosive-mutator/boon death burst renders via two paths: on the HOST through `AiUtils.generic_mutator_explosion` (already hooked), and on each CLIENT through its own `AreaDamageSystem.rpc_create_explosion` handler (`area_damage_system.lua:489` resolves the network id -> template name, `:494` `DamageUtils.create_explosion`) — which the host-only hook never sees. Added a second `mod:hook` on `AreaDamageSystem.rpc_create_explosion` that drops the local render when the template resolves (via `NetworkLookup.explosion_templates`) to `generic_mutator_explosion` / `_medium` / `_large`. Both hooks filter strictly by template name, so normal bomb/artillery/grenadier explosions are untouched.
- **Client-only, never affects others.** The client-path hook is gated on `not self.is_server`, so the host's re-broadcast to OTHER clients (`area_damage_system.lua:474-478`) is never touched. The client render path runs `is_husk` with `is_server=false`, so no authoritative damage rides it — the change is purely cosmetic to the local player's view, matching the option's intent.
- **Fixed the adjacent host-side arg drop.** The existing `generic_mutator_explosion` hook captured only 3 params and called `func()` with 3, silently passing vanilla's 4th arg `do_damage` (`ai_utils.lua:575`, gates whether the blast deals damage) as nil on every non-suppressed call. Now captured and forwarded. Extracted the shared template test into `_gt_is_mutator_explosion`.
- Duplicate-hook pre-flight (2026-07-05): no other gt hook targets `AreaDamageSystem.rpc_create_explosion`; the only `generic_mutator_explosion` hook is the one edited.

### Notes
- Still `[untested]` — needs an in-game verify as a non-host client (join a friend's lobby, enable the option, confirm the Explosive-mutator death burst no longer renders while normal bombs still do).
- **Part 2 (Max Ragdolls, `gt_more_corpses_count`) NOT addressed here.** Source read is inconclusive: `UnitSpawner.update_death_watch_list` runs client-side and reads the local `RagdollSettings` cap, but the pruning count is host-authoritative (`Managers.state.conflict:total_num_ai_spawned()`) and network-unit deletion is host-driven, so a client cap may be overridden. Per the issue, this needs a live client-session verify before deciding whether it already works, is inherently host-side (tooltip note), or needs a client-local retention approach. #332 stays open for that half.

## v0.2.185-dev (2026-07-05) -- #139 bots teleport AWAY from downed players: blanket leash veto

### Why
Issue #139 (0-critical): when a teammate goes down while the team is split, bots teleport toward a *living* far player instead of pathing in to revive the downed one. Root cause verified in vanilla source: `AIBotGroupSystem._update_move_targets` builds its follow-candidate list from **non-disabled** players and only swaps the disabled list in when EVERY player is down (`ai_bot_group_system.lua:695-719`). So a single down flips the bot's `follow_unit` to a living player, and the follow leash (gt's tighter one OR vanilla's 40 m) yanks the bot AWAY from the downed teammate. The two prior passes (v0.2.148 snap-toward-downed guard, v0.2.152 side-aid guard) only suppressed gt's *tighter* leash and never vetoed vanilla's 40 m path, so the yank still fired in a wide split. The v0.2.148 guard also fought the wrong direction (the reporter clarified: teleporting *to* a downed player is fine; only awaiting-rescue is off-limits).

### Changed
- **New BLANKET leash veto in the `BTConditions.should_teleport` hook.** With aid-priority ON (`gt_bot_behavior_improvements` + `gt_bot_aid_priority`), a bot NEVER teleports while any teammate is downed/disabled (knocked down / hanging from hook / ledge-hanging) — it drops everything and paths in to revive. The veto is applied to the FINAL teleport decision, so it now catches **vanilla's 40 m teleport** (`reason == "vanilla_40m"`) as well as gt's tighter leash — the gap the old guards could not reach. Per the reporter's decision, **all reachable bots converge to revive** (FIX 3b's per-bot force-pick already assigns the downed ally to every bot that can path; the veto removes the teleport-away race). Independent of follow mode (split/host/default) — that only changes who is followed, not the teleport rule.
- **Awaiting-rescue stays owned by `gt_bot_rescue_awaiting`.** The veto keys on `_gt_any_side_teammate_needs_aid` (knocked/hook/ledge only), NOT awaiting-rescue, so a bot can still leash to a living follow while a teammate merely awaits rescue at a respawn point (the intended split+leash benefit: in a 2-player lobby one bot stays with the living player). Awaiting-rescue players are already excluded from the follow set upstream, so the leash can never teleport a bot *to* one.
- **Consolidated the two prior guards.** The v0.2.148 snap-toward-downed guard and the v0.2.152 side-aid guard were removed from `_gt_tighter_leash_wants` (now pure distance logic); the single hook-level veto supersedes both. New shared gate `_gt_aid_priority_on()`. Markers `GT_BOT139_LEASH_AID_GUARD_MARKER_v0_2_148` + `..._SIDEAID_MARKER_v0_2_152` replaced by `GT_BOT139_LEASH_VETO_AIDPRIORITY_MARKER_v0_2_185`.
- **Diagnostics unchanged and still armed:** the `[139:bot_tp]` decision probe (reason / dist_to_downed / post_dist) and `[gt_bot:139] TELEPORT executed` lines remain; a new `[gt_bot:139] teleport VETOED` printf fires when the veto suppresses a leash while a teammate needs aid.
- **Regression test:** the two old marker tests collapse into `bot_leash_veto_while_teammate_needs_aid_present` (marker + source-pattern check that the veto gates on `_gt_aid_priority_on() and _gt_any_side_teammate_needs_aid`, applied to the final `want`).

### Notes
- Still `verify-fix` / needs in-game confirmation: host, split the team, down a teammate at distance, confirm bots WALK in to revive (no teleport to or away), and confirm one bot still leashes to the living player when a teammate is merely *awaiting rescue*.
- Behavior gated on aid-priority ON, matching the issue spec; with it OFF the leash is pure distance again (no downed special-casing).

## v0.2.184-dev (2026-07-04) -- #306 Save coordinates / teleport (per-map position slots)

### Why
Issue #306: a dev tool to bookmark a spot on the map and jump back to it. Useful for testing a specific arena/objective/spawn without re-walking the level.

### Changed
- **New file `_gt_saved_positions.lua`** (command-only, no hooks) registering 20 chat commands in a loop: `/save_position_1` .. `/save_position_10` capture the LOCAL player unit's current position + first-person look rotation; `/recall_position_1` .. `/recall_position_10` teleport that unit back. Each command echoes its result to the invoking player.
- **Saves are PER MAP.** The store is keyed by `Managers.state.game_mode:level_key()` (`game_mode_manager.lua:897`, returns `self._level_key` -- the mod's existing pattern, `_gt_creature_spawner.lua:245`), so each map has its own independent 10 slots. Works in the keep AND in a mission (the keep is a level with a level_key too).
- **Teleport primitive:** `PlayerUnitLocomotionExtension:teleport_to(pos, rot)` (`Vermintide-2-Source-Code/scripts/unit_extensions/default_player_unit/player_unit_locomotion_extension.lua:1005-1023`) -- sets the mover + unit position and, when `rot` is passed, `first_person_extension:set_rotation(rot)`. **Rotation restore ships** (position AND look direction are both restored). Mirrors vanilla's own saved-teleport tool, which stores points as `{x,y,z,qx,qy,qz,qw}` keyed by level and rebuilds with `Vector3(...)` / `Quaternion.from_elements(...)` (`imgui_teleport_tool.lua:352-363`).
- **Persistence:** one VMF setting, `gt_saved_positions`, a plain nested table `positions[level_key][slot] = { x, y, z, qx, qy, qz, qw }`. Slot keys are STRINGS ("1".."10") and every level of nesting is a pure string-keyed hash of numbers -- no mixed array/hash tables, which the engine's user-settings serializer rejects (`vmf/modules/core/settings.lua:10`). Written through `mod:set` on every save so slots survive a crash. Stingray stack-temporary rule honored: only plain number components are persisted; `Vector3`/`Quaternion` are rebuilt fresh at recall time, never stored as userdata.
- **Guards (each with a clear echo):** no local player unit (dead / spectating / not in a level) on save or recall (`Unit.alive` check); no current map yet; recall on a slot with nothing saved for the CURRENT map; recall wrapped in `pcall` so a cold engine field can't crash. `printf` (repo rule 9, mod-logging-off channel) records each save/recall to the console.
- **Client-safe:** everything operates on the LOCAL player unit only (same movement surface noclip uses); no networking, no hooks.

### Regression test
- `/gt_regression_test` gains `saved_positions_module_wired`: asserts the module dofiled and exposed `mod._gt_save_position` / `mod._gt_recall_position`, the 10-slot count, and its marker.

### Notes
- `[untested]` per #301 tag doctrine -- verify in-game before promotion.
- Version bump 0.2.183-dev -> 0.2.184-dev. No data widgets or localization added: the commands carry plain-string descriptions (like every other gt command) and `gt_saved_positions` is a hidden persistence blob, not a UI widget.

## v0.2.183-dev (2026-07-04) -- #320 Bots drink potions: advanced condition options

### Why
Issue #320: the "Bots drink potions when in danger" toggle had its trigger hard-coded (a `breed.boss` monster/lord, or >= 3 elites within 18 m). Players want to decide for themselves what counts as danger worth spending a potion on.

### Changed
- **`gt_bot_drink_potions_in_danger` is now a MASTER toggle (still default OFF) with 7 nested sub-widgets** deciding WHAT counts as danger, all read live inside `_gt_danger_near` each scan (no on_setting_changed wiring). setting_id preserved so persisted user state carries over. Children in feature order (each count slider directly under the trigger it tunes):
  1. `gt_bot_drink_range_m` (slider, 18 m, 5-40) -- danger scan radius; replaces the hard-coded `local _GT_BOT_DANGER_RANGE = 18.0`.
  2. `gt_bot_drink_on_boss` (on) -- drink when any `breed.boss` monster/lord is in range.
  3. `gt_bot_drink_on_special` (off) -- drink when any `breed.special` (disabler/ranged) is in range. NEW condition (vanilla port only reacted to boss + elites).
  4. `gt_bot_drink_on_patrol` (on) -- drink when an elite cluster is in range.
  5. `gt_bot_drink_patrol_count` (slider, 3, 1-10) -- elites needed to count as a patrol; replaces the hard-coded `_GT_BOT_PATROL_ELITE_THRESHOLD = 3`.
  6. `gt_bot_drink_on_horde` (off) -- drink when a trash cluster is in range. NEW condition.
  7. `gt_bot_drink_horde_count` (slider, 8, 3-30) -- trash enemies needed to count as a horde.
- **`_gt_danger_near` rewritten** to a single-pass scan that classifies each in-range enemy by its live Breed table (priority boss > special > elite > trash, where trash = none of those flags -- verified against `Vermintide-2-Source-Code/scripts/settings/breeds/*.lua`) and returns true as soon as an ENABLED condition is met. Disabled cluster conditions use a `math.huge` threshold so their tallies never trip; if every trigger is off the scan is skipped entirely.
- Defaults reproduce the former hard-coded behavior exactly (boss on, patrol on at 3, range 18; special + horde off), so an existing user who never expands the option sees no behavior change.

### Notes
- Still `[untested]` per #301 tag doctrine -- host-side, bots are host-only; verify in-game before promotion.
- Version bump 0.2.182-dev -> 0.2.183-dev; data widgets + localization added for all 7 sub-widgets.

## v0.2.182-dev (2026-07-04) -- #297 Bot Behavior Improvements master toggle + per-fix sub-menu + greedy pickup

### Why
Issue #297: the v0.2.128-dev bundling collapsed eight bot fixes into one opaque checkbox with hard-coded delays. This re-exposes each fix as a nested sub-toggle under the master (VMF native master-toggle pattern: `sub_widgets` on a checkbox auto-hide while it is unchecked, vmf_options_view.lua:4461-4463) and adds one brand-new behavior (greedy pickup, #297 item 8).

### Changed
- **`gt_bot_behavior_improvements` is now a MASTER toggle (still default OFF) with 10 nested sub-widgets, all read live inside the tick/hook bodies (no on_setting_changed wiring).** Every gate is now master AND sub-toggle. The 8 checkboxes default ON so the master alone reproduces the former bundle; checkbox ids reuse the pre-bundle setting ids retired in v0.2.128-dev, restoring any persisted pre-bundle user choices. In feature order:
  1. `gt_bot_necro_potion_handoff` (on) -- FIX 1 Necromancer potion promote/hand-off tick.
  2. `gt_bot_mission_fail_prevention` (on) -- FIX 8 `GameModeHelper.side_is_dead` hook (mission keeps going while a bot lives).
  3. `gt_bot_ledge_pullup` (on) -- FIX 4 auto ledge recovery tick.
  4. `gt_bot_ledge_pullup_delay` (slider, 3s, 0-10; 0 = instant) -- replaces the hard-coded `local delay = 3`.
  5. `gt_bot_ladder_unstick` (on) -- FIX 5 stuck-ladder teleport tick.
  6. `gt_bot_ladder_unstick_delay` (slider, 4s, 3-10) -- replaces the hard-coded `local delay = 4`.
  7. `gt_bot_instant_pickup` (on) -- FIX 6 instant grab of the bot's targeted/pinged pickup.
  8. `gt_bot_greedy_pickup` (on) -- NEW, see below.
  9. `gt_bot_aid_priority` (on) -- FIX 3b force revive/rescue priority (one child drives both `_force_revive` and `_force_rescue`).
  10. `gt_bot_ironbreaker_revive_in_ult` (on) -- FIX 2 `BTConditions.can_activate_ability` hook (revive during the Ironbreaker ult-hold).
- **New behavior: greedy pickup (FIX 10, #297 item 8).** Vanilla bots leave potions/bombs on the ground while any alive human within 20 m has that slot empty (`AIBotGroupSystem._update_mule_pickups` only assigns `blackboard.mule_pickup` when `num_players == 0`, ai_bot_group_system.lua:1983-2012), and health items are reserved one-per-empty-slot-human out of the bot-assignable pool (`_update_health_pickups` :2104-2141, leftovers permutation-assigned at :2216/:2309 with the 15 m `allowed_to_take_health_pickup` follow-range gate :1847/:2236). Two fresh `hook_safe` post-passes (duplicate-hook pre-flight grep: the only prior AIBotGroupSystem hooks are `_assign_destination_points` and `_update_urgent_targets`) re-run the vanilla assignment loops without the human-slot gates for bots left empty-handed, honoring vanilla's own distance rules and never touching `force_use_health_pickup` (:2355-2358) -- so a bot still never self-heals while a human is dying nearby (:2145-2146), it just carries the item and hands it over per vanilla give-scoring (player_bot_base.lua:881-917). Host-side only; no RPC; marker `GT_BOT_GREEDY_PICKUP_MARKER_v0_2_182`.
- **FIX 3's kept-separate `gt_bot_rescue_awaiting` toggle is unchanged**; the shared `_select_ally_by_utility` wrapper now proceeds when rescue-awaiting is on OR (master AND `gt_bot_aid_priority`).
- **Regression tests** (`/gt_regression_test`): `bot_behavior_master_sub_widgets_registered` (all 10 ids present under the master with the right types/defaults), `bot_greedy_pickup_hooks_present` (marker + both `_update_mule_pickups`/`_update_health_pickups` hook lines), `bot_fix_delays_read_from_settings` (delays read via mod:get, hard-coded literals gone).
- Version bump 0.2.181-dev -> 0.2.182-dev; data widgets + localization (per #301 tag doctrine: `[working]` on the sub-toggles the CHANGELOG records as confirmed in-game -- necro handoff, ladder unstick + delay, instant pickup, Ironbreaker revive; `[untested]` on mission-fail prevention, ledge pull-up + delay, aid priority, and the new greedy pickup).

### Notes
- Greedy pickup is brand-new and untested in-game; the other nine children wrap logic that has shipped since v0.2.128-dev.
- Master tooltip updated to say each fix is individually toggleable underneath.

## v0.2.181-dev (2026-07-04) -- #308 melee latency cosmetics: attack warning + health-bar smoothing

### Why
Issue #308 (Melee Latency Smoothing / client-side prediction). VT2 is host-authoritative for enemy melee hits, so nothing here can (or does) change outcomes. Two strictly client-side, cosmetic/informational helpers were scoped from the issue (input buffering was dropped -- it is already vanilla behavior). Both default OFF; both are new, so every option title is `[untested]`.

### Changed
- **New feature: Melee Attack Warning** (`_gt_melee_warning.lua`; "Visuals and Audio" group). Fires a local cue (short "hud_ping" sound and/or a red screen-edge flash) when a nearby enemy plays an attack-windup animation aimed at the local player, so the player can start their client-instant dodge ~1 RTT earlier than the animation alone shows.
  - Windup detection: `hook_safe AnimationSystem.anim_event` (animation_system.lua:119) -- the single convergence point for host-local plays AND client-received plays (rpc_anim_event re-invokes anim_event at :375). RPC dispatch is DYNAMIC (network_event_delegate.lua:52 re-looks-up the class method each call), so the class-method hook fires on the wire path. `event_name` is already a string and `unit` resolved -- no NetworkLookup/unit_storage decode.
  - Enemy filter via `Unit.get_data(unit,"breed").name` (husk-side breed table, ai_husk_base_extension.lua:11 / breeds.lua:306). Attack-anim match is data-driven `{ [breed] = { [anim] = delay_or_false } }` for the 6 high-threat elite breeds (stormvermin+commander, chaos warrior, mauler, bestigor, plague monk, berserker) plus a generic `^attack_` / `^charge_attack_` fallback behind the `all_melee` scope. Verified `bot_threat_start_time` / `damage_done_time` delays are cited per-entry in the source; anim-driven attacks are marked `false`/[unverified].
  - Target heuristic: AI units do NOT sync a target field to clients (game_object_initializers_extractors.lua ai_unit has only bt_action_name/breed/etc.), so it falls back to range (<= 6 m) + facing (`dot(forward, dir_to_player) >= 0.3`). Cheap math, only on attack-anim events.
  - Cues scheduled off gt's shared `mod._gt_register_update` tick (fire at `windup_start + impact_delay - lead`, clamped to now; unverified delays cue immediately). Screen flash drawn from `hook_safe IngameHud.update` via a throwaway 1920x1080 hud_scale_fit scenegraph + begin_pass/end_pass (proven HUD-composite path, mirrors gut's _gut_respawn_timer).
  - Always-on dev diagnostic (`[gt_dev:MW]`, engine `printf`): one line per detected windup (breed, anim, distance, delay) plus a windup->damage delta line when the local player takes damage within 3 s of a windup -- the tuning harness for refining the delay table. Damage is observed by reading the player's `current_health_percent` (READ ONLY, no health-extension hook).
  - Settings: `gt_melee_warning` master (off) + `gt_melee_warning_audio` (on), `gt_melee_warning_visual` (on), `gt_melee_warning_lead` dropdown ms 0/50/100/150/200/250 (100), `gt_melee_warning_scope` dropdown elites_only (default) / all_melee.
- **New feature: Smooth Health-Bar Damage** (`_gt_hp_smoothing.lua`; "Visuals and Audio" group). Eases the DISPLAYED fill of the local player's own unit-frame health bar down to a new lower value over a configurable window, so a batched `rpc_add_damage` chunk reads smoothly.
  - `hook_safe UnitFrameUI.set_total_health_percentage` (unit_frame_ui.lua:765) captures the incoming target; `hook_safe UnitFrameUI.update` (:242) writes the eased value into `content.total_health_bar.bar_value` (:1385) after vanilla's own lerp. Only the local player's frame (`self._frame_type == "player"`, :31). Only downward changes ease; heals/upward snap; knockdown/death snap (reads `self.data.is_knocked_down`/`is_dead`). Never reads or writes any health extension.
  - Settings: `gt_hp_smoothing` master (off) + `gt_hp_smoothing_ms` dropdown 100/150/200/250 ms (150).
- Version bump 0.2.180-dev -> 0.2.181-dev; CHANGELOG entry; data widgets + localization (all new titles `[untested]`, no em dashes, no `%`).

### Notes
- All six new option titles are `[untested]` pending in-game confirmation (dev status-tag doctrine #301).
- Duplicate-hook check: grep confirmed no prior gt_dev hook on `AnimationSystem.anim_event`, `IngameHud.update`, `UnitFrameUI.set_total_health_percentage`, or `UnitFrameUI.update` -- all four are singletons.
- Impact-delay ambiguity: `chaos_raider` `attack_cleave` has two source delays (running 1.0 / special 0.7); stored 0.7. The `[gt_dev:MW]` probe exists to disambiguate these live.

## v0.2.180-dev (2026-07-04) -- #301 localization status-tag doctrine sweep

- **Localization: applied dev status-tag doctrine (#301).** 123 widget titles tagged: 23 [working], 87 [untested], 13 issue-tagged (1 of which also keeps [untested]); of the issue tags, 2 also carry [crash] and 2 also carry [diag]. Tags now cover every option title, master toggle, and group header per LOCALIZATION_STANDARD.md 13. No functional change - loc strings only (plus the version bump and this entry). Dropdown value labels, tooltips, MOTD/popup and failed-join message strings were left untagged as required.
  - **Group headers (all 15 were untagged):** added [working] to the 13 structural groups, [Issue 254] to "Creature Spawner" (open: spawner no-ops in Chaos Wastes), and [untested] to the new dev-only "Dev Tools" group.
  - **Corrected stale / mis-mapped issue tags.** "Allow Bots in Keep" was [Issue 247 & 142] (bot takeover + ledge-pathing, neither about keep bots) -> [crash] [Issue 65] (the open two-class bots-in-keep crash that runtime-kill-switched the feature). Removed #300 from "Bot Behavior Improvements" and "Follow snap-back distance" - #300's GitHub title is literally `gt_bot_rescue_awaiting`, so it belongs only on that toggle (kept there). "Follow snap-back distance" -> [diag] [Issue 261 & 139]; "Bot follow mode" -> [diag] [Issue 261] (the always-on `[gt:btlab:*]` breach/tether/teleport probes instrument both).
  - **New feature -> issue maps:** "Disable Enemy Spawns" [Issue 242], "Noclip" [Issue 241], "Disable ult screen effects" [untested] [Issue 255], "Bot behavior HUD" [crash] [Issue 293 & 295] (the create_screen_gui CTD overlay fixed in v0.2.179; the crash issues remain open pending in-game verification).
  - **Normalized 10 non-standard "[confirmed working]" tags to [working]** (godmode, noclip base speed / boost / toggle, disable friendly fire, tagging, allow duplicate careers, auto-start on vote pass, ready up, unlock ranked weaves).
  - **Not mapped (feature-request issues with no existing widget or requesting not-yet-built sub-options):** #320 (potion-use conditions), #297/#298 already map to their base toggles, #302-#309 (freeze AI, debug highlights, keep dummy collision, save/teleport coords, melee latency, disconnect grace) - all left unmapped per doctrine.

## v0.2.179-dev (2026-07-04) -- #293/#295 fix bot-teleport-lab screen-GUI material (create_screen_gui CTD) + can_get guard + breadcrumbs

- **Crash fix (#293, corroborated by #295) -- ROOT CAUSE was the wrong create material.** The Dev Tools bot HUD (`_gt_bot_teleport_lab.lua` `_do_draw`) built its overlay with `World.create_screen_gui(world, "material", FONT_MTRL, "immediate")` where `FONT_MTRL = "materials/fonts/arial"`. `materials/fonts/arial` is a valid `Gui.text` FONT-material argument but is NOT a resident `create_screen_gui` MATERIAL - so the engine took its C-level "Gui material not found #ID[...]" assert. That assert BYPASSES pcall (the `pcall(_do_draw, ...)` at `_btlab_draw` did not, and could not, catch it), so it hard-killed the process. #293 flushed a Lua crash block; #295 was the same family truncating mid-session with no block (hard/native kill). Every vanilla debug screen GUI creates with `materials/fonts/gw_fonts` (`debug.lua:12`, `graph_drawer.lua:10`, `state_ingame.lua:2279-2280`, `achievement_manager.lua:947`, ...) and only passes `materials/fonts/arial` as the `Gui.text` font arg - the lab conflated the two. Fix: create with a new `GUI_MTRL = "materials/fonts/gw_fonts"`; keep `FONT_MTRL` for the `Gui.text` calls unchanged (that pairing matches vanilla `debug.lua` exactly: `font_mtrl` in `Gui.text`, `gw_fonts` in create).
- **Belt-and-suspenders `can_get` pre-filter (the documented fix for this crash class).** Even with the correct material, `create_screen_gui` can C-fatal if `gw_fonts` is momentarily non-resident during a mission<->keep world swap - and the fatal is uncatchable. So the create is gated on `Application.can_get("material", GUI_MTRL)` (vanilla's own non-faulting existence check, same guard `pickup_system.lua:882` uses for unit spawns; `gw_fonts` is the exact self-test material the gut GUI guard trusts). Not resident -> DEFER the HUD that frame (cached gui stays nil, retries next frame); fail CLOSED (skip) on any error. gt calls `create_screen_gui` directly, so gut's global `UIRenderer.create` guard (`_gut_gui_material_guard.lua`) never covered this path; this is the localized equivalent.
- **#295 breadcrumbs (localize the next hard crash).** Added always-on engine `printf` bracketing: an edge-latched `[gt:btlab] Dev Tools draw ENABLED/DISABLED` line the frame the bot-testing-tools overlay turns on/off, and `[gt:btlab] create_screen_gui: ... resident -- creating HUD gui` immediately BEFORE the risky C call plus `... created OK` after. If the draw path ever hard-crashes with no Lua block again, the log ends right at the enable line and the create bracket, pinpointing the fatal. The DEFERRED path logs once per world (latched on `mod._gt_btlab_gui_deferred`, reset in `_clear_and_null` and `_reset_mission_state`).
- **Regression test** (`/gt_regression_test`): `btlab_gui_material_guarded` - source-pattern check that the create call passes `GUI_MTRL` (never `FONT_MTRL` again) and is still pre-filtered by `can_get("material", GUI_MTRL)`.

- **No behavior change.** The Huntsman `apply_huntsman_activated_ability` wrapper added in v0.2.177 restored the three nop'd engine functions and then re-returned the wrapped call's results with a bare `unpack()`. The `check_unpack_safety` gate (VMF_RECIPES.md 2a) flagged it as a potential nil-hole truncation. The wrapped buff function returns nothing today, so nothing was actually dropped, but the passthrough now captures the pcall result count via a `_pack` helper and calls `unpack(results, 2, n)` with an explicit end index - correct even if the function ever returns interior nils.

## v0.2.177-dev (2026-07-03) -- #255 disable ult + downed screen effects (ported from Neuter Ult Effects)

- **Two new "Visuals and Audio" toggles (both default off, [untested], visual-only, own game only).** Root cause of #255: gt never actually had a "disable ult effects" option - a full setting_id inventory of the data file found only `gt_solo_disable_ult_vo` (the ult VOICE-line silencer). The standalone Neuter Ult Effects mod still works only because Fatshark's `mod_shim.lua` (lines 215-279) translates its now-dead `MOOD_BLACKBOARD` / `StateInGameRunning.update_mood` API onto the modern surface. This ports that modern translation directly into gt.
  - **Disable ult screen effects** (`gt_solo_disable_ult_fx`): removes the fullscreen color/distortion mood and the swirly screenspace FX when a career ability is used. Three hooks, all gating on this toggle and passing through when off: (1) `MoodHandler.set_mood` swallows the ENABLE call for the ult career-skill moods `skill_slayer` / `skill_zealot` / `skill_shade` / `skill_huntsman_surge` / `skill_huntsman_stealth` / `skill_maiden_guard` (Handmaiden stealth dash, `buff_function_templates.lua:5070` - not in the original mod's list, found by grepping every `set_mood("skill_*")` call site); (2) `BuffExtension._play_screen_effect` swallows the 8 ult screenspace effects (Huntsman/Shade/Ranger skill FX + Sister of the Thorn radiance enter+loop); (3) a wrapper on `BuffFunctionTemplates.functions.apply_huntsman_activated_ability` nops `Unit.flow_event` + both `play_remote_hud_sound_event` for the call duration (Huntsman's FOV punch/flow/sound), restoring in all cases via pcall. `skill_ranger` is in the mood set for parity but has no modern `set_mood` call site - Ranger's ult visual is the screenspace FX, covered by hook (2).
  - **Disable downed screen effects** (`gt_solo_disable_downed_fx`): swallows the `MoodHandler.set_mood` ENABLE call for `knocked_down` (`generic_status_extension.lua:1251`), `bleeding_out` (`:1457`), and `wounded` (`:1458`), removing the fullscreen desaturation/vignette while knocked down and while wounded.
- **Enable-only mood swallow (stricter than mod_shim).** The `set_mood` hook intercepts only calls where the enable/disable flag `value` is truthy (`mood_handler.lua:335`); disable calls always pass through, so toggling either option mid-effect can never leave a mood stuck on. Diagnostics are always-on engine `printf` (`[gt:neuterfx] swallowed ...`), visible with mod logging off, for in-game verification.

## v0.2.176-dev (2026-07-03) -- #261 always-on radius-breach / tether instrumentation (diagnose before mitigating)

- **Issue #261 diagnostic data (instrumentation ONLY, no behavior change).** In split follow mode, bots pursue objectives outside the follow radius and then get leash-yanked; the next dev-session log now carries decisive data on what the bot was doing when it left the radius and what caused each yank. All three probes are always-on in the dev build behind `IS_DEV_STREAM`, host-side, event- or cooldown-driven, and use engine `printf` (visible with mod logging off). No new `mod:hook`/`hook_safe` - everything rides the existing merge-dispatch.
  - **Radius-breach probe** (`[gt:btlab:breach]`, in `_gt_bot_teleport_lab.lua` `mod._gt_btlab_observe_update`): edge-triggered per bot when distance to the CURRENT follow anchor crosses ABOVE the leash radius (`gt_bot_follow_distance_m`; treated as OFF at `<= 0` or `>= 40`, matching `_gt_tighter_leash_wants`). Hysteresis re-arms only after the bot drops back under 80% of the radius; per-bot ~3s cooldown. On trigger, printfs a 3-line block: bot name(career) + follow anchor + distance + radius + current BT leaf action; per-human distances + nearest human; and the last-20-action ring buffer as one compact line (newest first, `id@-<age>s`).
  - **Tether dump** (`[gt:btlab:tether]`, `mod._gt_btlab_report_tether`, dispatched from the existing `BTBotTeleportToAllyAction.run` hook in `_gt_bot_fixes.lua`): on every leash snap/teleport, printfs a 2-line block (current action + ring buffer) with a per-bot ~2s cooldown, so every observed yank carries its cause.
  - **Follow-assignment visibility** (`[gt:btlab:d2]`): the follow-tracker line now names the resolved follow MODE (default / follow_host / split) via `mod._gt_resolve_follow_mode`, alongside the existing old -> new follow target by name. Note: this dispatch runs at the TOP of `_assign_destination_points`, so in follow_host/split it reports the pre-override target; the final post-split anchor is what the breach/tether probes read.
- **Action ring buffer is now always-on in dev** (was gated on the `gt_devtools_bot_hud` toggle). The HUD and the new #261 probes both draw from it. Still a per-frame string read plus a small table only on an action transition (capped at 20) - no per-frame log lines.
- **Sibling leash summaries made visible:** the `[gt:bot-split]` round-robin summary in `_gt_bot_fixes.lua` (a `mod:debug` line, invisible with logging off) is mirrored to `printf` in dev via `mod._gt_btlab_pf_dev`; the `mod:debug` call is kept.
- **Regression tests** (`/gt_regression_test`): added `breach_probe_present_dev_gated`, `tether_dump_present`, and `btlab_no_class_hooks` (source-pattern: no `mod:hook(` / `mod:hook_safe(` in the lab file).

## v0.2.175-dev (2026-07-03) -- Bot Teleport Lab settings removed (diagnostics doctrine); new dev-only "Dev Tools" section + bot behavior HUD

- **Removed the entire Bot Teleport Lab settings section** (the `gt_btlab_enabled` master + 10 D-toggles + 10 F-toggles + 4 numeric params, and all their localization). New diagnostics doctrine: data-collecting probes are NEVER menu toggles - they are implicit and always-on when running the dev build. The former D-probes (D1 teleport events, D2 follow tracker, D3 distance readout, D4 segment probe, D5 aid probe, D8 teleport counter, D9 has_teleported probe, D10 snapshot buffer) now run whenever `IS_DEV_STREAM` is true, read no settings, and keep their existing per-bot ~1s throttles. Output is unchanged (engine `printf`, tags `[gt:btlab:dNN]`, visible with mod logging off). `IS_DEV_STREAM` uses the sed-safe `mod == get_mod("gt" .. "_dev")` gate so the whole thing evaluates false in the promoted stable clone.
- **Retired the F1..F10 behavior-fix candidates to dormant.** These were experimental "stop bots teleporting away" toggles; the proven #139 fixes live in `_gt_bot_fixes.lua` and are untouched. Their three dispatch fns (`veto_teleport` / `override_follow_unit` / `redirect_teleport`) now early-return false/nil on a module flag `_BTLAB_FIXES_ARMED = false`, reading no settings, so a friend who had saved the master + an F-toggle ON keeps NO ghost behavior fix now that the widgets are gone. The fix bodies are kept intact and re-armable in code only.
- **New dev-only "Dev Tools" settings section.** Appended to the widget tree only in the dev clone (same sed-safe `get_mod("gt" .. "_dev")` guard), positioned A->Z after "Cheats and Debug". Two toggles, both default off, host-only, `[untested]`:
  - **Bot behavior HUD** (`gt_devtools_bot_hud`): draws one fixed on-screen column per bot - header (name + career), current behavior-tree leaf action, follow target, distance to that teammate and to you, `has_teleported`, teleport tally, and the last 20 behavior-tree actions the bot entered (newest first). Supersedes and folds in the old D6 head-text.
  - **Bot leash lines (3D)** (`gt_devtools_leash_lines`): the former D7 - a world line from each bot to its follow target and to you.
- **HUD action history** reads the current running behavior-tree LEAF action straight off `blackboard.running_nodes` (bt_node.lua records each active container's running child; the leaf is the running node whose own identifier is not itself a key) and pushes a ring-buffer entry per transition, polled from the existing `PlayerBotBase.update` merge-dispatch (no new hooks). The draw and the poll do zero per-frame work unless dev + host + the toggle is on.
- **Kept** the `/bot_tp_dump` and `/bot_tp_snap` chat commands working (commands are fine; only the menu toggles were the problem), now guarded on `IS_DEV_STREAM`.
- **Regression tests** (`/gt_regression_test`): added `btlab_settings_removed` (no `gt_btlab_` widget survives in the tree), `btlab_fixes_dormant` (the three fix dispatchers return false/nil regardless of settings), `devtools_group_dev_gated` (Dev Tools group present + ordered after Cheats and Debug + the data file carries the sed-safe gate), and `devtools_bot_hud_wired` (poll dispatch present + lab source reads `running_nodes` and gates on `gt_devtools_bot_hud`).

## v0.2.174-dev (2026-07-03) -- #222 strict re-sweep round 2: action-hotkey and enable/disable tooltip bodies

- **#222 round 2 (user still saw title repeats after v0.2.171/.173).** The earlier passes rewrote the wordy paragraph tooltips but skipped the short imperative entries, where the body was literally the title as a sentence: "Fail Level" -> "Instantly fails the current mission", "Kill Bots" -> "Kills every bot in your party", "Restart Level" -> "Restarts the current mission", "Win Level" -> "Instantly completes the current mission", "Spawn Saved Slot N" -> "Spawns whatever enemy you saved to slot N", "Unlock All Ranked Weaves" -> "Unlocks every ranked weave", plus the whole "Enable/Disable X" -> "Turns X on/off" and "Send via chat" -> "Show the message in chat" tier. Applied a hard rule this pass: no body may begin with a verb-form or noun-restatement of its title. Rewrote 46 `_tooltip` bodies (action hotkeys, spawner keys, enable/disable toggles, MOTD send-channels, slot reservations / ignore list, time-step keys, pause/ready-up, prioritize-specials weapon lines, fall-damage, adventure trait chance, value setters like crit chance / movement speed / time scale, and the leash-line / bot-HUD diagnostics) to open with the trigger, effect, scope, or a value instead. Verified with an automated title-vs-body-opener pairing scan (`echo-verb` heuristic) so no body leads with a bare "Turns/Sets/Opens/Spawns/Kills/..." that echoes its title. No magnitudes, mechanics, chat commands, `%%` escaping, or host-only/Versus/keep caveats changed.
- **Menu-text hygiene:** `gt_lobby_failnotify_title` "Cannot join -- modded host" -> "Cannot join: modded host" (dropped the em-dash-style double hyphen per the no-em-dash menu rule).

## v0.2.173-dev (2026-07-02) -- #222 strict re-sweep: option tooltips no longer restate their title

- **#222 strict re-sweep (follow-up to the too-lenient v0.2.171 pass).** VMF builds each option popup as `title .. "\n" .. body` (confirmed in VMF source options.lua), so a body that opens by re-naming the option shows the title twice. v0.2.171 only stripped 3 blatant lead-ins; this pass rewrites 18 more `_tooltip` bodies whose openers echoed the title via "Turns on X" / "Hotkey to X" / "Makes ... X" / value-noun forms (bot-teleport-lab fixes, bot AI toggles, ai_takeover, noclip hotkey, keep-AI, lobby manifest broadcast, solo assassin VO, etc.). Each now opens with the behavior, effect, or range. No magnitudes, mechanics, chat commands, `%%` escaping, host-only/PC-only/Versus caveats, or mutex hints changed.

## v0.2.172-dev (2026-07-02) -- /catchup command (alias of /unstuck)

- **New chat command `/catchup`** (user request): teleports you to the nearest living teammate, preferring humans - identical behavior to `/unstuck`. Implemented by extracting the existing `/unstuck` body into a shared local (`_gt_unstuck_to_teammate` in `_gt_godmode_qol.lua`) and registering both command names against it; no behavior change to `/unstuck`. Collision pre-flight: repo-wide grep found no other mod registering `catchup`.

## v0.2.171-dev (2026-07-02) -- #222 loc sweep: drop leading option-title restatement from tooltips

- **#222 loc sweep: removed leading option-title restatement from 3 option tooltips so the popup body no longer repeats the orange header.** VMF draws each option's title as the popup header automatically, so a body that reopened with that same title showed the name twice.
  - `gt_btlab_enabled_tooltip`: dropped "Master switch for the Bot Teleport Lab, ..." opener; now opens with the behavior ("A set of tools for watching and fixing bots that teleport away from you."), master-switch role kept in the second sentence.
  - `base_crit_chance_tooltip`: "Sets your current career's base critical hit chance." -> "Sets how often your current career lands a critical hit." (paraphrase instead of restating "Base Crit Chance").
  - `gt_fall_damage_enabled_tooltip`: "Turns on the fall damage multiplier below; ..." -> "Turns on the multiplier below; ..." (drops the verbatim title phrase). All magnitude numbers, host-scope claims, and mechanics preserved.

## v0.2.170-dev (2026-07-01) -- Settings menu: sort A->Z, nest verified fine-tunes, mirror the loc file to the tree

Menu reorganization only. No functional changes: no setting added, removed, renamed, or re-defaulted; every one of the 144 widget setting_ids is preserved. Data-file widget defaults, ranges, decimals, keybind function_names, and dropdown option values/show_widgets are all unchanged. Localization strings are preserved verbatim except one meta-language fix (below).

- **Within-group A->Z sorting by display label** (status tags like "[untested]" ignored when sorting):
  - **Bots**: loose options re-sorted (AFK Bot Takeover, Allow Bots in Keep, Announce guard breaks, Bot Behavior Improvements, Bot follow mode, Bot Takeover, Bots drink potions, Bots rescue awaiting, Disable Bots, Faster bot reactions, Follow snap-back distance, Improved Bot Combat). Bot Teleport Lab nested group stays first.
  - **Cheats and Debug**: loose primitives A->Z (Clear Enemy Spawns, Disable Enemy Spawns, Godmode, Noclip, Noclip Toggle), then the five nested sub-groups A->Z (Buffs & Stats, Level Control, Spawners, Time & Pause, Ult). Buffs & Stats, Ult, and Level Control leaves re-sorted A->Z.
  - **Info**: Assassin, Boss path progress, Packmaster.
  - **Visuals and Audio**: Assassin/Packmaster VO, Disable fog, Disable mutator explosions, Disable sun shadows, Disable ult VO, Draw boss spheres, Max Ragdolls.
  - **Host-Side Lobby Controls**: Modded Lobby Manifest members A->Z (Broadcast, Send MOTD, Show missing mods); Prioritize Specials sub-toggles A->Z (Deepwood, Soulstealer, Tagging).
- **Nested three verified-gated fine-tune clusters under their existing master checkbox** (code already gates them, so hiding while off is purely visual, no behavior change):
  - `noclip_speed` + `noclip_boost_multiplier` under `noclip_enabled` (read only inside the active movement hook). The `noclip_hotkey` binding stays a loose sibling: it is what turns noclip on, so it must remain visible while noclip is off.
  - `gt_lobby_kick_idle_threshold_minutes` + `gt_lobby_ki_warn_seconds` under `gt_lobby_kick_idle_enabled` (idle tick reads them only past the enable gate).
  - `gt_lobby_motd_send_chat` + `gt_lobby_motd_send_popup` + `gt_lobby_motd_once_per_peer_per_session` under `gt_lobby_motd_enabled` (join handler reads them only past the enable gate).
- **Deliberate orders kept (not A->Z), each noted in a code comment:** Bot Teleport Lab D1..D10 / F1..F10 (numeric, maps to `_gt_bot_teleport_lab.lua`); Creature Spawner grudge sub_widgets (INDEX-LOCKED -- the dropdown's `show_widgets = {1}` / `{2..14}` reveal arrays reference sub_widget positions); Creature Spawner (spawn workflow + saved slots 1/2/3); Item Spawner (next/prev/spawn workflow); Time & Pause (scale then faster/slower then pause); Grail Knight quests 1/2/3 (numbered). Cheats and Debug intentionally lists loose headline cheats above its detail sub-groups so the most-used toggles stay surfaced.
- **Localization file reordered to mirror the widget tree** with a `-- ====` banner per top-level group and blank lines between groups; code-referenced strings that have no widget (MOTD popup title/text buffer, failed-join reveal text, bot guard-break chat line) moved to a trailing section.
- **One style fix:** `gt_bot_toggle_hotkey_tooltip` dropped its "Toggles whether..." meta-language preamble ("Allows or blocks bots on the current level..."); the mechanic and rare-crash caveat are preserved.
- **Suspected orphans (reported, NOT removed):** `gt_lobby_motd_text` + `gt_lobby_motd_text_tooltip` are left over from the removed MOTD text-input widget; the MOTD text is now set via `/lobby_motd_set` and read with `mod:get`, so these two labels are unused.

## v0.2.169-dev (2026-07-01) -- Passive diagnostic probes: #198 training-dummy multi-hit + #139 bot-teleport decision

Two default-on, printf-based diagnostic probes (visible with mod-logging off). No gameplay change, no setting gate, no new user-facing strings.

- **#198 (training dummy hit many times by one attack) -- new probe `_gt_probe_dummy_hits.lua`.** Hooks `TrainingDummyHealthExtension.add_damage` (`hook_safe`, observe-only) -- the exact vanilla function that both applies dummy damage and draws the floating damage number (`add_unit_floating_damage_numbers`, training_dummy_health_extension.lua:70), so one call equals one stacked number in the report screenshot. Events are bucketed per (dummy unit, attacker, damage source) and flushed one line per swing once the swing goes quiet for 0.2s (idle-flush registered on gt's shared `mod._gt_register_update` dispatcher, so `mod.update` is untouched). Emits `[198:dummy] attacker=<career> attack=<damage_source> hits_this_swing=<n> zones=<hit_zones> dmg_total=<x> crit=<bool> t=<time>`. A line with `hits_this_swing > 1` is a single swing landing multiple times on the one dummy; `zones=` distinguishes a re-application bug (same zone repeated) from a multi-actor sweep. Nothing else in gt_dev hooks `TrainingDummyHealthExtension`, so this is a fresh singleton hook (no VMF duplicate-hook drop).
- **#44 (AI-control RPC schema gate) -- schema-mismatch log switched to engine `printf`.** The drop-path log in `_gt_ai_takeover.lua`'s `gt_ai_toggle_request` receiver was `mod:info` (mirrored from the godmode receiver), which is invisible with mod-logging off. A schema mismatch means a peer on an incompatible gt_dev build was silently dropped -- the reason their AI-takeover won't sync -- so it must be visible in the user's normal (logging-off) sessions. Now `printf` (rawget-guarded), same `[rpc:schema]` tag and message. The other `mod:info` traces in that file are ordinary debug chatter and stay as-is.
- **#139 (bots teleport to a newly-downed player instead of reviving) -- merged into the existing bot-teleport hooks in `_gt_bot_fixes.lua`.** No new hook (VMF drops a 2nd hook on an already-hooked pair): the `BTConditions.should_teleport` hook now stamps `blackboard._gt139_tp_reason` (`vanilla_40m` / `tighter_leash` / nil), and the `BTBotTeleportToAllyAction.run` hook emits, once per teleport that fires while a teammate is down or awaiting rescue, `[139:bot_tp] bot=<career> dist_to_downed=<m> reason=<branch> post_dist=<m> target=<x,y,z> t=<time>`. `dist_to_downed` is the pre-teleport distance to the nearest downed/awaiting-rescue teammate; `post_dist` near 0 proves the bot snapped ONTO the downed player (the reported bug), while a large `post_dist` means it leashed to a living follow while a different teammate stayed down. Two helpers added (`_gt_unit_needs_aid_or_rescue`, `_gt_nearest_needing_aid`); `ready_for_assisted_respawn` read as a plain field per generic_status_extension.lua:1329. The prior `[gt_bot:139]` executed/suppressed lines are preserved.

## v0.2.168-dev (2026-07-01) -- Loc: fix tooltip markers + rewrite every option description in plain English

Localization-only pass, no gameplay change.

- **Fixed the "<...>" marker bug on tooltips.** Every widget in the data file wrote its tooltip as `tooltip = mod:localize("key")`, but VMF already localizes each widget's tooltip itself at menu-build time. That double-localization fed the finished English sentence back in as a lookup key, missed, and wrapped the whole tooltip in angle brackets in-game. Converted all **129** eager `tooltip = mod:localize("key")` calls to raw keys (`tooltip = "key"`) so VMF resolves them once. The one correct eager-localize, the top-level `description = mod:localize("mod_description")`, is left as-is.
- **Rewrote every option description.** All ~130 `_tooltip` values plus `mod_description` were rewritten into plain, player-facing English (max two sentences each), dropping internal jargon (function names, engine terms, file references) in favor of what the option actually does in the game. No wording implies behavior the old text did not state; percent signs stay escaped (`%%`), no em dashes, no angle brackets.
- **Key coverage verified:** all 144 widget setting_ids, 129 tooltip keys, and 21 dropdown option-text keys resolve against the loc table; no keys were added, renamed, or removed. No widget defaults, ranges, or structure changed.

## v0.2.167-dev (2026-07-01) -- Net-hardening: RPC schema versioning on the AI Takeover RPC (#44)

Applies the VMF_RECIPES § 10 RPC schema-version pattern to the last unversioned gt RPC — the AI Takeover client->host request (`gt_ai_toggle_request`, sender + receiver both in `_gt_ai_takeover.lua`). Mirrors the existing `mod.GT_LOBBY_RPC_SCHEMA` (lobby MOTD) and `_GT_GODMODE_RPC_SCHEMA` (godmode state) gates.

- **New constant `mod.GT_AI_RPC_SCHEMA = 1`** (defined in `general_tweaker_dev.lua` alongside `GT_LOBBY_RPC_SCHEMA`). Bump only when the `gt_ai_toggle_request` payload shape changes.
- **Sender** (`_gt_ai_takeover.lua`, `_ai_consume_pending_client_send`): prepends `mod.GT_AI_RPC_SCHEMA` as the first positional arg, before the existing `{ peer_id, local_player_id, want_bot }` table.
- **Receiver** (`mod:network_register("gt_ai_toggle_request", ...)`): now `function(sender_peer_id, schema, payload)`; drops the request when `schema ~= mod.GT_AI_RPC_SCHEMA` (or `sender_peer_id == nil`) with a `[rpc:schema] ... mismatch ... Dropping.` `mod:info` line. Graceful degradation — no swap, no crash. A peer on a different/older gt_dev build (older builds send no schema arg, so their payload table lands in `schema` and fails the match) is ignored rather than mis-parsed. No behavior change for matched-version peers; the takeover itself remains disabled pending the keep-slot redesign, so this is forward-looking net-hardening only.
- **Regression check** `gt_ai_rpc_schema_present` (mirrors `gt_lobby_rpc_schema_present`): asserts `mod.GT_AI_RPC_SCHEMA` is a number >= 1.

Also re-verified two previously-shipped fixes against the vanilla decompile (no code change this release):

- **#194 (Disable Bots / `gt_no_bots`)** — fixed in v0.2.143-dev (rawget `_G.script_data` + per-tick `_handle_bots` enforce hooks on Adventure/Deus/Weave). Confirmed against `game_mode_adventure.lua:371` / `game_mode_deus.lua:527` / `game_mode_weave.lua:462`: each mode's `_handle_bots` reads `script_data.ai_bots_disabled` and calls `self:_clear_bots(true)` + early-returns. Mechanism correct; pending host-side in-game confirmation.
- **#59 (Drachenfels boss BT crash)** — fixed in v0.2.149-dev (level-family prefix match + `BTConditions.at_*_health` nil-guards, `_gt_creature_spawner.lua`). Still present and marker-guarded.

## v0.2.166-dev (2026-07-01) -- NEW: Bot Teleport Lab -- 10 diagnostics + 10 fixes for "bots teleport away from the player"

A full in-game toolkit to observe, diagnose, and fix bots teleporting away. New module `_gt_bot_teleport_lab.lua`. Lives in a nested **"Bot Teleport Lab"** group inside **Bots**, gated by a master toggle `gt_btlab_enabled` (default off); everything under it defaults off and is host-side (bot AI is server-side). All logging is engine `printf` (visible with mod-logging off), tagged `[gt:btlab:...]`.

**Mechanics (source-verified):** a bot teleports when it falls >= 40 units from its `follow_unit` (`BTConditions.should_teleport`, `FOLLOW_TELEPORT_DISTANCE_SQ=1600`); the snap executes in `BTBotTeleportToAllyAction.run` (`locomotion:teleport_to`); `follow_unit` is assigned in `AIBotGroupSystem._assign_destination_points`. If a bot's follow_unit is a *different* player/host, it snaps toward them -- i.e. away from you.

**Architecture:** merge-dispatch. The lab adds ZERO new hooks on already-hooked pairs (VMF drops duplicate hooks); instead it exposes `mod._gt_btlab_*` fns called from gt's existing `should_teleport` / `BTBotTeleportToAllyAction.run` (converted hook_safe->hook to capture pre/post position) / `PlayerBotBase.update` / `_assign_destination_points` (FIX 9) hooks. Lint confirms 0 duplicate hooks; each merge-point pair is hooked exactly once. FIX 7 tighter-leash + the #139 guards are preserved verbatim.

**10 diagnostics** (`gt_btlab_d1..d10`): teleport-event log (bot/career/from->to/follow_unit/distance/trigger/toward-or-away-from-you delta); follow-unit change tracker; live distance readout (bot->follow vs bot->you); segment-gate probe; aid-exception probe; on-screen bot HUD; 3D leash-line draw (bot->follow yellow, bot->you cyan); teleport counter (`/bot_tp_dump`); has_teleported lifecycle; snapshot ring buffer (`/bot_tp_snap`).

**10 fixes** (`gt_btlab_f1..f10`, each independent, each logs SUPPRESSED/REDIRECTED so you can prove it): F1 follow you, F2 block away-teleports, F3 teleport to you instead, F4 proximity veto (`f4_radius` def 25), F5 follow nearest human, F6 stuck-only teleport, F7 raise threshold (`f7_distance` def 80), F8 combat hold (`f8_radius` def 15), F9 post-teleport cooldown (`f9_seconds` def 3), F10 direction-aware (no backward yank). Vetoes OR together (first firing logs + blocks, F-number order); F1 beats F5; F3 acts in `.run`.

**Not yet runtime-verified** -- compiles + lint-clean and follows source-verified patterns, but each fix's real behavior needs host-side in-game confirmation via its `[gt:btlab:fNN]` log line. Heuristics flagged: F6 off-navmesh proxy, F8 enemy broadphase, F10 heading source -- all pcall-guarded to degrade to "no veto" on a bad read.

## v0.2.165-dev (2026-07-01) -- FIX: Auto-restart on team wipe now works in Chaos Wastes and Weaves

**Symptom (user, in a Chaos Wastes run):** wiped, wanted to restart the map to keep testing; `/gt_win` did nothing and it "failed 3× with an info popup".

**Diagnosis:** two things. (1) `/win` (`/gt_win`) calls `GameModeManager:complete_level()`, which **cannot override a team wipe** — once the "lost" end-condition latches, force-complete is a no-op, and afterward you're in the keep where level commands are refused ("Can't do that in the keep"). It's the wrong tool for surviving a wipe. (2) The **"Auto-restart on team wipe"** toggle — which *is* the right tool — only hooked `GameModeAdventure.evaluate_end_conditions`, so in **Chaos Wastes** (`GameModeDeus`) and **Weaves** (`GameModeWeave`) it never fired. The log showed an active `deus_run_state`, i.e. Chaos Wastes.

**Fix (`_gt_solo_qol.lua`):** the auto-restart handler is now a shared function hooked on all three mission modes — `GameModeAdventure` / `GameModeDeus` / `GameModeWeave` — each a distinct `(Class, method)` pair (no VMF collision; mirrors `_gt_bots_keep`'s `_handle_bots` hooks). Returning `"reload"` is a valid end reason for all three (`adventure_mechanism.lua:427`, `deus_mechanism.lua:539/545`). Also fixed a latent multi-return drop: the hook now captures and passes through the vanilla third return (`reason_data`) instead of collapsing it. Feature is still off by default; enable "Auto-restart on team wipe" (Host-Side Lobby Controls) and a wipe reloads the current map in place. `/inn` still bails to the keep.

## v0.2.164-dev (2026-07-01) -- Simplify: strip the "gt_" prefix from all chat commands

Renamed **49** chat commands to drop the `gt_` prefix (e.g. `/gt_pause` -> `/pause`, `/gt_win` -> `/win`, `/gt_lobby_reserve` -> `/lobby_reserve`, `/gt_spawncreature` -> `/spawncreature`). Updated all 81 in-code / tooltip references to match, and refreshed `COMMANDS.md`.

- **One exception:** `/gt_regression_test` keeps its prefix — bare `regression_test` collides with GUI Tweaker's command (VT2 chat commands are global; first mod to register wins). Per-mod regression-test names are intentionally prefixed.
- `lobby_*` commands keep their `lobby_` prefix (only `gt_` was removed): `/lobby_reserve`, `/lobby_ignore`, `/lobby_motd_set`, etc.
- **Collision check:** verified against every other mod in the repo — the only clashes were `regression_test` (kept prefixed) and `win` (clashes only with the frozen, non-loadable legacy `tweaker` mod, so safe; gt already uses bare `god`/`unstuck` the same way). Keybind `function_name`s and setting_ids are unchanged — only the chat-command names.
- Note: gt_dev's Workshop **description** still lists old `/gt_*` command names (and references removed features) — a separate refresh is pending.

## v0.2.163-dev (2026-06-30) -- Gameplay menu: sort + convert Prioritize Specials / Grail Knight Quests to master toggles

Menu restructure with one behavior change (the new Prioritize Specials master gate).

- **Prioritize Specials is now a master toggle** (`gt_prio_specials_enabled`, default off) named **"Prioritize Specials (Tagging, Deepwood and Soulstealer)"**, replacing the plain `gt_prio_specials_group`. Its three context sub-toggles — **Tagging**, **Deepwood Staff**, **Soulstealer Staff** (relabelled, dropping the redundant "Prioritize Specials --" prefix) — now default **ON**, so flipping the master on activates all three at once. `_gt_prioritize_specials.lua` gates each hook on `master AND sub` via a new `_prio_on()` helper. **Migration:** the master defaults off (feature stays off by default, as before); a user who had previously enabled a sub-toggle must now also enable the master for it to take effect.
- **Choose Grail Knight Quests unwrapped.** Removed the redundant single-item `gt_gk_group` collapsible (both it and its only child read "Choose Grail Knight Quests"); `gt_gk_quests_enabled` is now a direct master toggle in Gameplay.
- **Gameplay sorted** per the standing rule. With both former groups now master toggles, Gameplay has no nested groups, so all members are loose options alphabetical by label: Choose Grail Knight Quests · Disable Friendly Fire · Healer's Touch… · Prioritize Specials…

(Cheats and Debug still has its nested groups at the bottom — that one's still pending in the full-mod sorting pass.)

## v0.2.162-dev (2026-06-30) -- Loc: remove em dashes from all menu strings

Localization-only style pass. Replaced every em dash (`—`) in the menu labels/tooltips with the file's existing ASCII `--` convention (per user preference — no more em dashes in GT menus). No wording or behavior changes.

## v0.2.161-dev (2026-06-30) -- Loc: rename the "Bot Options" group to "Bots"

Localization-only. The `gt_bot_options_group` label is now **"Bots"** (was "Bot Options"). Still sorts first among the top-level groups (Bots · Cheats and Debug · Gameplay · Host-Side Lobby Controls · Info · Visuals and Audio).

## v0.2.160-dev (2026-06-30) -- "More Corpses" → single "Max Ragdolls" slider (no toggle); drop "(debug)" from Draw boss-event spheres

- **More Corpses reworked into a single "Max Ragdolls" slider.** Dropped the `gt_more_corpses_enabled` enable toggle and the nested sub-widget. `gt_more_corpses_count` is now a standalone, always-live numeric labelled **"Max Ragdolls"**, default **24** (vanilla cap), range **1–300** (was 1–500 nested under the toggle). `_gt_godmode_qol.lua`'s apply function no longer gates on the removed toggle — it always pins both `RagdollSettings.max_num_ragdolls` and `min_num_ragdolls` to the slider value (holds a steady count rather than sawtoothing to vanilla's min of 10). on_setting_changed branch narrowed to `gt_more_corpses_count`. setting_id preserved, so existing values carry over. Note: default 24 now pins min=max=24, marginally more corpses than pure vanilla (min 10) — set lower if you want fewer.
- **"Draw boss-event spheres (debug)" → "Draw boss-event spheres".** Dropped the "(debug)" suffix.

## v0.2.159-dev (2026-06-30) -- Simplify bot follow distance: drop the enable toggle, slider is the sole control (default 40 = off)

Removed the **"Tighter bot follow distance"** enable toggle (`gt_bot_follow_distance_enabled`) — the widget, both loc keys, and the gate in FIX 7 (`_gt_bot_fixes.lua`, `BTConditions.should_teleport`). The **"Follow snap-back distance (meters)"** slider (`gt_bot_follow_distance_m`) is now the sole control, defaulting to **40** — which is vanilla's own teleport gate, so 40 (or above) is a no-op (off). Lower the slider to tighten the leash. Per-distance behavior is unchanged; this just collapses two widgets into one.

- `gt_bot_follow_distance_m` setting_id preserved, so existing values carry over. Untouched users get the new default 40 (= off, same as the old toggle-off default). Edge case: a user who had explicitly lowered the slider *while leaving the old toggle off* will now have that distance take effect — re-set to 40 to disable.

## v0.2.158-dev (2026-06-30) -- Remove duplicate "Disable level intro audio" (GUI Tweaker owns it)

Removed gt's `gt_solo_disable_intro_audio` toggle entirely — the widget (from the Visuals and Audio group), both loc keys, and the `StateLoading._trigger_sound_events` hook in `_gt_solo_qol.lua`. It duplicated GUI Tweaker's **"Disable Level Intro Audio"** (gut's HideBuffs fork, `hb/level_loading_screen.lua`, same hook target). Use the gut toggle instead. No other gt code referenced the setting.

## v0.2.157-dev (2026-06-30) -- FIX invalid-format crash on the save-item slider; lobby menu reorg + sorting rule

### FIX -- "invalid string format" error on the save-item proc-chance slider

v0.2.156's rename put a literal `%` in `gt_adventure_save_trait_chance` ("...Grenadier % Chance"). VMF's `mod:localize` runs every string through `string.format` (safe_string_format), so the bare `%` was read as a format spec (`% C` -> "invalid option to 'format'") and errored on every menu render. It was **not** the commas. Fixed by escaping to `%%` (renders as a literal `%`).

**Test gap closed:** the pre-ship static guard `qa/check_localization.ps1` (Find-UnescapedPercent) already had an unescaped-`%` check, but its logic wrongly treated `% ` (percent-space) as safe, so the bad string shipped in .156. Rewrote it to strip `%%` pairs first, then flag any remaining `%` that doesn't begin a valid Lua format directive. The runtime twin (`localization_format_safe` regression test) already covered this. RULE: any literal `%` in a loc string must be doubled to `%%`.

### Menu reorg
- **Allow Duplicate Careers + Unlock All Ranked Weaves → Host-Side Lobby Controls** (moved out of Gameplay). Allow Duplicate Careers re-tagged **[confirmed working]**.
- **Modded Lobby Manifest → top of Host-Side Lobby Controls**; the group's loose options are now alphabetical by label.

### Sorting rule (now standing convention for this mod)
Within every settings group: **nested sub-groups first (top)**, then **loose options alphabetical by display label** (status tags like `[untested]` ignored for the sort), except where a deliberate order is specified. Dependent sub-options (e.g. idle threshold/warn under Auto-kick) stay directly beneath their parent. Applied to Host-Side Lobby Controls this release; other groups (Cheats and Debug, Gameplay) still have their nested groups at the bottom — a full-mod pass is pending.

## v0.2.156-dev (2026-06-30) -- Menu/loc: Bot Takeover toggles → Bot Options; rename the adventure save-item slider

No behavior change — all setting_ids preserved.

- **Bot Takeover + AFK Bot Takeover → Bot Options.** `ai_takeover_enabled` ("Bot Takeover") and `gt_ai_afk_takeover` ("AFK Bot Takeover") moved out of Gameplay into the Bot Options group — handing your hero to bot AI is a bot-control feature. `/ai` chat command unchanged.
- **Adventure save-item slider renamed.** `gt_adventure_save_trait_chance` label is now **"Healer's Touch, Home Brewer, Grenadier % Chance"** (was "Adventure save-item trait chance (percent)") — names the three traits it controls. range / behavior / tooltip unchanged.

## v0.2.155-dev (2026-06-30) -- Menu reorg: enemy-spawn toggles → Cheats and Debug; MOTD → Modded Lobby Manifest

Pure menu placement — no behavior change, all widget setting_ids preserved.

- **Disable Enemy Spawns + Clear Enemy Spawns → Cheats and Debug.** `disable_enemy_spawns` and the `clear_enemies_hotkey` keybind moved out of Gameplay into Cheats and Debug, beside godmode / noclip (they're cheat-style combat toggles).
- **Message of the Day → Modded Lobby Manifest sub-group.** `gt_lobby_motd_enabled` ("Send MOTD to joiners"), `gt_lobby_motd_send_chat` ("Send via chat"), `gt_lobby_motd_send_popup` ("Send via popup") moved out of the parent Host-Side Lobby Controls into the nested **Modded Lobby Manifest** group. The `gt_lobby_motd_once_per_peer_per_session` sub-option came along so the MOTD block stays together (would otherwise be orphaned in the parent). Both MOTD and the mod-list manifest are host→joiner broadcasts.

## v0.2.154-dev (2026-06-30) -- Menu/loc: auto-restart → Lobby Controls; "Visuals" → "Visuals and Audio"; "AI Takeover" → "Bot Takeover"

Pure menu/labeling changes — no behavior change, all widget setting_ids preserved so existing user settings and `mod:get(...)` reads keep working.

- **Auto-restart on team wipe → Host-Side Lobby Controls.** `gt_solo_auto_restart_on_wipe` moved out of the Visuals group into Host-Side Lobby Controls (beside Ready Up) — it's a host-side match-flow control, not a visual. setting_id unchanged; `_gt_solo_qol.lua` reads it the same way.
- **"Visuals" → "Visuals and Audio".** `gt_solo_group` display label updated (setting_id preserved) — the group also holds the VO / intro-audio toggles, so the name now reflects its contents.
- **"AI Takeover" → "Bot Takeover".** `ai_takeover_enabled` is now **"Bot Takeover"** (dropped the redundant "(bot controls your character)" parenthetical, consistent with the .151/.153 de-parenthetical pass); `gt_ai_afk_takeover` is now **"AFK Bot Takeover"**. Tooltip self-reference updated to match. Chat command `/ai` unchanged.
- **Note — More Corpses duplicate:** the duplicate "More Corpses" toggle (the standalone `gt_corpses_group` that wrapped a same-named checkbox) was already removed in **v0.2.151-dev** when More Corpses merged into Visuals. This build carries that fix for anyone still running a pre-.151 bundle.

Top-level menu order unchanged: Bot Options · Cheats and Debug · Gameplay · Host-Side Lobby Controls · Info · Visuals and Audio · [Debug Logging].

## v0.2.153-dev (2026-06-30) -- Loc: drop "(AI Teammates)" suffix from the Bot Options group label

Cosmetic localization-only change. The top-level settings group `gt_bot_options_group` now reads **"Bot Options"** instead of "Bot Options (AI Teammates)" — the parenthetical was redundant. No widgets, settings, or behavior changed.

## v0.2.152-dev (2026-06-29) -- FIX: bots no longer leash AWAY from a downed teammate (#139 sibling case) + new "Bot follow mode" dropdown

Two bot-fixes shipping together — they were diagnosed together when the user reported "bots teleport away when a player is downed", and the menu consolidation made the diagnosis easier to explain.

### Fix — leash no longer pulls bots away from a downed teammate

**Symptom (user report 2026-06-29):** a teammate goes down and bots **teleport over to a living player** instead of helping. They then have to walk back from far away, often arriving too late.

**Root cause — sibling of #139, not yet covered by the v0.2.148-dev fix.** The tighter leash (FIX 7, `BTConditions.should_teleport`) teleports a bot to its `follow_unit`. FIX 3b's aid-priority exemption only fires after `target_ally_need_type` is set, which the aid-picker only assigns once per BT tick. On the frame a teammate is newly downed, the bot's `follow_unit` is still a LIVING far-away player → the leash fires → bot teleports AWAY from the downed teammate. The v0.2.148-dev #139 fix only suppressed the leash when `follow_unit` itself was downed; it didn't cover the case where `follow_unit` is alive but a different teammate needs aid. This sibling case is what the user was reporting.

**Fix (`_gt_bot_fixes.lua`, FIX 7):** added `_gt_any_side_teammate_needs_aid(self_unit)` helper that walks `side.PLAYER_UNITS` and returns the first knocked-down / hooked / ledge-hanging ally found. The `should_teleport` hook now suppresses the tighter leash whenever this helper returns non-nil — so if anyone on the bot's side needs aid the leash sits out, and FIX 3b's aid-priority gets the chance to assign `target_ally_need_type` so the bot paths in to help instead of teleporting away. Marker `GT_BOT139_LEASH_AID_SIDEAID_MARKER_v0_2_152` + regression test `bot_leash_no_teleport_away_from_side_aid_marker_present`.

**Diagnostics (printf, mod-logging off visible, prefix `[gt_bot:139s]`):** one line per save: `tighter-leash teleport SUPPRESSED -- teammate needs aid (bot will path to help instead of leashing away)`. Per-blackboard dedupe so it doesn't spam.

### New "Bot follow mode" dropdown

The previous two checkboxes — `gt_bot_split_among_players` and `gt_bot_follow_host` — were opposite strategies with implicit precedence (`follow_host` won when both were on). Consolidated into one tri-state dropdown `gt_bot_follow_mode`:

- **Default** — vanilla bot follow behaviour (cluster around whoever is moving, swap after ~20s of standstill).
- **Follow Host** — every bot leashes to the host regardless of party position.
- **Split** — round-robin one bot per human, host first (former `gt_bot_split_among_players`).

Default value: `"default"`. The `_assign_destination_points` hook reads the new dropdown via `mod._gt_resolve_follow_mode()`, which falls back to the legacy `gt_bot_follow_host` / `gt_bot_split_among_players` checkbox values when the dropdown setting hasn't been written yet — so existing user state migrates on first read without a forced reset. Old loc keys retained for documentation; the widgets are gone from the menu. Marker `GT_BOT_FOLLOW_MODE_DROPDOWN_MARKER_v0_2_152` + regression test `bot_follow_mode_dropdown_consolidated`.

**Needs host in-game verification:**
1. Pick **Follow Host**, split the party, down a non-host teammate at distance → bots should walk in to revive, NOT teleport to the host first.
2. Pick **Split**, same scenario → same result.
3. Each mode should still behave as before in steady-state (Follow Host: all bots near host; Split: one bot per human; Default: vanilla).

## v0.2.151-dev (2026-06-29) -- Menu reorg: Ready Up + Manifest into Lobby Controls; More Corpses + Solo merged into Visuals; new "Info" group; "Disable Bots (Solo)" → "Disable Bots"

Pure menu/labeling reorganization, no behavior changes. All widget setting_ids preserved so existing user settings carry over and code reads against `mod:get(...)` keep working unchanged.

- **Ready Up → Host-Side Lobby Controls.** The `gt_readyup_group` ("Ready Up") section is gone; its two widgets (`gt_ready_up_hotkey` keybind, `gt_auto_ready_on_vote_pass` checkbox) now sit at the bottom of Host-Side Lobby Controls. Both are host-side lobby-flow controls, so co-locating them with slot reservations / kick-on-idle / MOTD / etc. makes the menu easier to scan.
- **Modded Lobby Manifest → nested collapsible inside Host-Side Lobby Controls.** The two manifest-related widgets (`gt_lobby_manifest_broadcast_enabled` host-side broadcast, `gt_lobby_manifest_failnotify_enabled` client-side failed-join reveal) are now wrapped in a `gt_lobby_manifest_group` collapsible sub-group inside the parent Host-Side Lobby Controls. Declutters the parent menu; both widgets reachable in one click.
- **More Corpses merged into Visuals.** The standalone `gt_corpses_group` ("More Corpses") top-level menu is gone; its single feature (`gt_more_corpses_enabled` with its `gt_more_corpses_count` sub-slider) now lives at the bottom of the `gt_solo_group` section. The corpse cap is a visual feature, so co-locating it with the other visual toggles (disable fog / sun shadows / mutator explosions / draw boss spheres) consolidates a one-item top-level menu.
- **"Solo & QoL (from True Solo)" → "Visuals".** The `gt_solo_group` display label is renamed (setting_id preserved). Three on-screen-text widgets split out (see next bullet) leaving a section that's primarily visual toggles.
- **New "Info" top-level group.** On-screen text readouts split out of the old Solo group into a focused `gt_info_group`: `gt_solo_assassin_text_warning`, `gt_solo_packmaster_text_warning`, `gt_solo_boss_path_progress`. Widget IDs preserved (still `gt_solo_*`) so the `_gt_solo_qol.lua` reads keep working — only the menu placement moves.
- **"Disable Bots (Solo)" → "Disable Bots".** The trailing parenthetical was redundant (the tooltip already covers the host-only / solo-friendly use case). `gt_no_bots` setting_id unchanged.

Top-level menu order (alphabetical, with Debug Logging pinned last per convention) is now: Bot Options · Cheats and Debug · Gameplay · Host-Side Lobby Controls · Info · Visuals · [Debug Logging].

## v0.2.150-dev (2026-06-29) -- MIGRATE OUT to gui_tweaker: Floating Damage Numbers, Main Menu & Startup (#190), 3rd-Person Camera (#191), Loading-Screen Monologues (#192)

Four features moved out of gt and into `gui_tweaker` (gut), which now owns them. Removed from gt: the options widgets, loc keys, handlers, dispatch branches, and the related regression tests. No behaviour change to anything that stays in gt.

- **Floating Damage Numbers** removed (`gt_damage_numbers_group`). The two `DamageUtils.add_damage_network` / `add_damage_network_player` hooks STAY in gt as **pure godmode** again — only the floating-damage-number feed lines were stripped from them, and the `_gt_damage_numbers.lua` dofile was removed (file → `.bak.v0.2.149-dev`). gut registers its own clean hooks on those methods (different mod, so VMF chains across mods — no conflict).
- **Main Menu & Startup (#190)** removed (`gt_menu_qol_group`: `gt_skip_start_screen`, `gt_return_to_menu_quits`). Dropped the on_setting_changed / on_disabled dispatch, the `/gt_quit` command, `_gt_menu_qol.lua` (→ `.bak`), and the `menu_qol_settings_registered` + `menu_qol_return_quits_roundtrips` regression tests.
- **3rd-Person Camera (#191)** removed (`tp_camera_group` + all `tp_*` settings, `/tp` command, `_gt_camera.lua` → `.bak`). **Care point:** `_gt_camera.lua`'s `PlayerUnitFirstPerson.extensions_ready` hook *also* triggered the godmode/noclip post-spawn re-apply (`mod._gt_schedule_post_spawn_reapply`). Since VMF forbids a 2nd hook on the same pair, a **slim copy of that hook** (only the schedule call) was relocated into the main chunk beside the scheduler, so godmode/noclip re-apply still fires on spawn. Removed the camera on_setting_changed / on_disabled / on_game_state_changed dispatch and the `tp_camera_yields_to_cutscene` regression test.
- **Disable Loading-Screen Monologues (#192)** removed (`gt_cutscenes_group`, now empty after cutscene-skip migrated in #106). Stripped the on_setting_changed branch, the `_gt_godmode_qol.lua` monologue block + `/gt_intromono` command. gut owns `gut_disable_intro_monologue` + `/gut_intromono`.

## v0.2.149-dev (2026-06-29) -- HARDEN: nil-guard BTConditions.at_*_health family (#59 belt-and-suspenders)

**Issue #59** had two suggested fixes: (1) match the `dlc_castle` level family by prefix so CW theme variants (`dlc_castle_slaanesh_path1`, etc.) hit the vanilla Drachenfels boss path instead of gt's arena-less fallback — **already shipped** (`_gt_creature_spawner.lua`, `_gt_cs_is_in_level` with underscore-boundary match) — and (2) **defensively nil-guard** the `BTConditions.at_*_health` family so any first-tick race (boss spawned + BT evaluates a health condition before `AISystem.update_blackboard_health` writes `blackboard.current_health_percent`) biases to FALSE rather than crashing on `nil <= number`. This release ships fix #2.

**Fix (`_gt_creature_spawner.lua`):** wrap each of the eight blackboard-health conditions in a nil-guard helper. Two helpers, one for the seven that read `current_health_percent` and one for the lone `less_than_one_health` that reads raw `current_health`. The guard biases to FALSE (boss has not yet hit the threshold) when the field is nil — the next tick `update_blackboard_health` writes the real value and vanilla logic resumes. Hooks added: `at_half_health`, `at_one_third_health`, `at_two_thirds_health`, `at_one_fifth_health`, `at_three_fifths_health`, `can_transition_half_health`, `can_transition_one_third_health`, `less_than_one_health`. Each is a distinct `(BTConditions, <method>)` pair — no duplicate-hook collision with the existing `transitioned_one_third_health` hook (different method).

**Diagnostics (printf — visible with mod-logging off, per `[gt_bt:#59]` prefix):** the first time the guard saves each `(breed, condition)` pair, it logs one line: `nil-guard suppressed at_one_fifth_health on breed=chaos_exalted_sorcerer_drachenfels (current_health_percent uninitialized -- first-tick race)`. Per-pair dedupe (`_gt_bt_health_nil_seen[breed|cond] = true`) so the BT tick loop doesn't spam — one line per real save. **If you ever see one of these in a log, the race is real** and the guard is doing its job. New regression marker `GT_BT_HEALTH_NILGUARD_MARKER_v0_2_149` + `bt_health_conditions_nilguarded_marker_present` check.

Covers Drachenfels (Chaos Sorcerer) — and now also any other boss BT (Skarrik, Nurgloth, Bödvarr, etc.) that ever races a health-condition tick against blackboard init. No behavior change for the steady-state read; only the first-tick nil window is suppressed.

## v0.2.148-dev (2026-06-29) -- FIX: bots no longer teleport onto a newly-downed teammate when the team is split (#139)

**Symptom (#139):** when a player goes down while the team is split up, bots **teleport onto the downed player** instead of pathing in to revive — abandoning their split position.

**Root cause:** gt's tighter follow-leash (FIX 7, `BTConditions.should_teleport`, default 12 m vs vanilla 40 m) teleports a bot to its `follow_unit`. FIX 7 already exempts a bot that has `target_ally_need_type` set (it's heading to an aid target), but on the frame a split teammate is *newly* downed — **before** the aid-picker assigns that target — the bot is still in follow mode pointed at that teammate. So the tighter leash fires and snaps the bot onto the downed player rather than letting it walk in and revive.

**Fix (`_gt_bot_fixes.lua`, FIX 7):** added a guard — if the leash would fire and the `follow_unit` currently needs aid (knocked down / hook / ledge, via new `_gt_unit_needs_aid` helper), suppress the GT tighter-leash teleport and let the bot path in to revive. Vanilla's 40 m teleport (the wrapped `func()` call at the top of the hook) still applies as a last-resort catch for truly-far cases, so a genuinely stranded bot isn't left behind.

**Diagnostics (printf — visible with mod-logging off):** `[gt_bot:139] tighter-leash teleport SUPPRESSED …` when the guard fires, and `[gt_bot:139] TELEPORT executed (follow downed=…)` on every actual teleport. If the latter ever reports `follow downed=true` after this build, the snap came from vanilla's 40 m path and the fix needs extending to gate that too.

New regression marker `GT_BOT139_LEASH_AID_GUARD_MARKER_v0_2_148` + `bot_leash_no_snap_to_downed_marker_present` check. No new hooks (modified FIX 7's existing `should_teleport` body + enriched the existing `BTBotTeleportToAllyAction.run` probe) — no duplicate-hook risk. **Needs host in-game verification: split the team, down a teammate, confirm bots WALK to revive instead of snapping.**

## v0.2.147-dev (2026-06-29) -- FIX: necromancer bot can raise skeletons in the keep (Bots in Keep sub-feature)

**Symptom (user report 2026-06-29):** with **Allow Bots in Keep** on, a Necromancer bot "keeps trying over and over but can't raise skeletons."

**Root cause:** Fatshark forbids necromancer pets in the hub by design — a necromancer (player *or* bot) can't raise skeletons in the keep / CW hub. The gate is `PassiveAbilityNecromancerCharges._pets_forbidden_in_level`, computed in `_on_talents_changed` as `script_data.pets_forbidden_in_hub and is_in_inn_level` (`passive_ability_necromancer_charges.lua:108-110`). Both `spawn_pet` (line 202) and `_update_pets_server` (line 327) early-return when it's true. The bot's raise-dead AI keeps firing its action, but every `spawn_pet` hits that early-return → endless no-op loop.

**Fix (`_gt_bots_keep.lua`):** when **Bots in Keep** is active, post-hook `_on_talents_changed` (the method where vanilla *sets* the flag, fired as the bot's passive ability initializes on keep entry) and clear `_pets_forbidden_in_level` for **bot necromancers only** (`player.bot_player == true` via `Managers.player:owner`). Human-player keep behavior is left exactly as vanilla. The real spawn path (`_spawn_pet_server` → `Managers.state.conflict:spawn_queued_unit`) uses systems the keep has (conflict director — gt already hooks it; side system; ai_system nav_world — our bots navigate it), and `warm_up_skeletons` preloads the breed packages for the bot on the host, so skeletons can actually spawn once the gate is lifted.

`hook_safe` (post): vanilla computes the flag first, then we clear it. No duplicate-hook risk — grepped gt_dev, this is the only hook on `PassiveAbilityNecromancerCharges`; VMF hook_safe chains across mods. New regression marker `GT_BIK_NECRO_KEEP_PETS_MARKER_v0_2_147` + `bots_in_keep_necro_pets_marker_present` check. **EXPERIMENTAL — needs host in-game verification (keep → bot necromancer raises skeletons, no crash/clutter). If skeletons in the keep prove unstable, fall back to suppressing the bot's raise-dead loop instead.**

## v0.2.146-dev (2026-06-29) -- ENABLE: 'Allow Bots in Keep' revived + both crash classes fixed (#65)

Un-kill-switched **Allow Bots in Keep** (`gt_bots_in_keep`), disabled since v0.2.74-dev. The two crash classes from #65 are fixed structurally by porting the proven inn-bot lifecycle from the **Photo Mode** mod (workshop 3743797855), verified against the decompiled source:

- **Bug 1 — stat-leak fassert on keep exit** (`"Stat id <peer>:<lpid> not unregistered"`, GUID `70b90096…`): bots are now torn down from a `hook_safe` on `GameModeInn`/`GameModeInnDeus.cleanup_game_mode_units`. `StateIngame.on_exit` calls that at `state_ingame.lua:1911` — **before** `check_venture_end` (2119) destroys the venture stats manager — and `_remove_bot_instant` unregisters each bot's stat there, while Player refs are valid. The old `_bik_reset_bookkeeping` (which only dropped the Lua tracking table without unregistering) is now a no-op so it can't race the cleanup hook.
- **Bug 2 — `"No empty slot in party heroes"` on host join** (GUID `faed01a7…`): fill is now driven from the inn mode's `server_update` (only ticks once the session is running) **and** gated on `_bik_host_in_party1()`, so bots are never added until the host already holds its party-1 slot. Fill only ever takes OPEN slots, so it can't claim the host's slot.

Implementation (`_gt_bots_keep.lua`): replaced the old generic per-frame fill tick with `hook_safe` on `GameModeInn`/`InnDeus` `server_update` (fill) + `cleanup_game_mode_units` (teardown). `_bik_active()` now returns the live `gt_bots_in_keep` setting (kill-switch removed). Added engine `printf` on fill. New regression marker `GT_BIK_CRASHFIX_MARKER_v0_2_146` + `bots_in_keep_crashfix_marker_present` check. No duplicate-hook collisions (grepped). VMF hooks chain across mods, so this coexists with Photo Mode if both are installed. **Host-only; needs host in-game verification (keep load → bots fill, keep exit → no crash).**

## v0.2.145-dev (2026-06-29) -- Menu: move bot-roster toggles into Bot Options

Moved **Disable Bots (Solo)** (`gt_no_bots`) and **Allow Bots in Keep** (`gt_bots_in_keep`) out of the **Gameplay** group and into **Bot Options**, where they belong (both are bot-roster controls). Placed at the top of Bot Options — roster presence (whether bots exist / where) before the behavior tweaks (combat, follow, reactions). No behavior change; widget IDs unchanged so existing user settings carry over. `gt_bots_in_keep` is still runtime kill-switched (#65).

## v0.2.144-dev (2026-06-29) -- FIX: `_dbg_on` nil-global error spam (orphaned v0.2.142-dev refactor)

**Symptom (from the 2026-06-29 console log):** `_gt_debug_probes.lua:893: attempt to call global '_dbg_on' (a nil value)` fired on every `StateIngame` enter, and `:744` on unit relinquish.

**Root cause:** the v0.2.142-dev "gate removed; routes through VMF logging" refactor dropped the `_dbg_on` predicate from the logger but left **5 call sites** still gating the heavy AI/menu *dump triggers* on `_dbg_on()` (lines ~724/744/857/863/893). `_dbg_on` was then undefined anywhere in the mod (`mod._dbg_on` was referenced by comments + `_gt_ai_takeover.lua` but never assigned). Caught by VMF's event pcall, so it didn't crash, but it spammed errors and silently killed the AI/menu dump probes. (This is why the orphaned `.142` bump carried no CHANGELOG entry — it was a half-finished refactor.)

**Fix (`_gt_debug_probes.lua`):** restored `_dbg_on` as a file-local predicate gating on `enable_debug_logging`, and exposed it as `mod._dbg_on`. The logger (`_dbg`/`_dbg_log`) correctly stays ungated (routes through VMF `mod:debug`); only the expensive dump triggers use the gate. Pre-existing bug, independent of the #194 no_bots fix.

## v0.2.143-dev (2026-06-28) -- FIX: 'Disable Bots (Solo)' (gt_no_bots) now actually disables bots (#194)

**Symptom:** the **Disable Bots (Solo)** toggle (`gt_no_bots`) did nothing in-game — bots were never despawned or blocked. (`bots_in_keep` remains separately kill-switched, #65 — unchanged here.)

**Root cause:** `mod._gt_apply_no_bots` did `script_data = script_data or {}` — writing the bare `script_data` global *name*. Under VMF's mod environment that rawsets `script_data` into the mod env table; because this file applies the setting once at mod load, if `_G.script_data` wasn't populated yet at that first call it cached a **private empty table** that then permanently shadowed the real `_G.script_data` the game's `_handle_bots` reads. So the `ai_bots_disabled` flag the engine checks every server tick never flipped. The proven no-bots mods (SpawnTweaks / TrueSoloQoL) only ever *field-mutate* `script_data`, never assign the name — which is exactly why they work.

**Fix (`_gt_bots_keep.lua`):**
- `_gt_apply_no_bots` now mutates the **real engine global** via `rawget(_G, "script_data")` and never writes the `script_data` name. If the global isn't up yet at load, it no-ops and lets the enforce hooks / StateIngame re-apply set it.
- **Enforcement hooks (belt-and-suspenders, the proven mechanism):** hook `_handle_bots` on `GameModeAdventure` / `GameModeDeus` / `GameModeWeave` and re-assert `script_data.ai_bots_disabled = true` from the live `gt_no_bots` setting every server tick. Mirrors SpawnTweaks / TrueSoloQoL; immune to any flag-reset / load-order / first-frame timing race. Covers Adventure + Chaos Wastes (Deus) + Weave. Host-only by nature (only the host runs `_handle_bots`).
- **Crash guard:** `pcall` `AdventureSpawning.force_update_spawn_positions` while `gt_no_bots` is on — the proven mods do this ("Prevent a crash with disabled bots"). The crash was latent pre-fix because bots were never actually suppressed.
- **Diagnostics:** added engine `printf` on apply + first enforce tick (`[gt_no_bots] ...`) so the host path is confirmable with mod-logging off. (Remove once verified in-game.)

No duplicate-hook risk: grepped gt_dev — nothing else hooks `_handle_bots` on the three game modes or `AdventureSpawning.force_update_spawn_positions`. **Needs host in-game verification.**

## v0.2.142-dev (2026-06-28) -- Removed per-mod debug toggle; diagnostics routed through VMF logging (#169)

Removed the `enable_debug_logging` per-mod checkbox. All diagnostic calls now go through VMF's built-in logging channels (`mod:debug` / `mod:warning`), gated by VMF's own **output_mode_debug** / **output_mode_warning** settings.

- Removed `enable_debug_logging` widget from data + localization.
- `_dbg` helper → `mod:debug(...)`. `_dbg_alert` helper → `mod:warning(...)`.
- `_log_settings_snapshot` early-return guard removed; inner `mod:info` → `mod:debug`. Command description simplified.
- `_gt_debug_probes.lua`: removed `_dbg_on()` gating function; removed 4 temp-force-enable patterns from the `gt_ai_slotdump` / `gt_bot_loadout_dump` auto-dump commands.
- `_gt_bot_fixes.lua`: ~13 inline `mod:get("enable_debug_logging")` gates dropped; `mod:info` → `mod:debug` throughout.
- `_gt_lobby_motd.lua`: fallback `_dbg_alert` branch simplified.
- Regression test `dbg_helpers_two_channel` updated (remove toggle-save/restore lines).

## v0.2.141-dev (2026-06-28) -- 3rd-person camera distance min lowered 1.0 -> -3.0

`tp_distance` slider range is now `{ -3.0, 10.0 }` (was `{ 1.0, 10.0 }`) so the camera can pull in closer / over-the-shoulder, per user request.

## v0.2.140-dev (2026-06-25) -- Skip Cutscenes moved out to gui_tweaker (gut), issue #106 migration

**Feature MOVED OUT — no behavior change for gt's other features.**

- **Skip Cutscenes migrated to gui_tweaker (gut).** The "Skip Cutscenes" / "Auto-skip Cutscenes" feature (Aussiemon "Skip Cutscenes" port) moved out of gt and into gut as part of issue #106 (the Blood-in-the-Darkness / `dlc_castle` stuck-cutscene investigation — gut adds a printf diagnostic that survives mod-logging-off, which gt's `mod:info` lines did not). Removed from gt:
  - `_gt_cutscenes.lua` (renamed to `_gt_cutscenes.lua.bak.v0.2.139`, not deleted) — owned the `CutsceneSystem.flow_cb_cutscene_effect` / `flow_cb_activate_cutscene_logic` / `skip_pressed` + `ShowCursorStack.pop` hooks, the `cutscene_auto_skip` deferred update consumer, `/gt_skipcutscenes`, and `mod.gt_skip_cutscenes_toggle`.
  - the `on_setting_changed` branch for `gt_skip_cutscenes_enabled` (which set `script_data.skippable_cutscenes`).
  - the `gt_skip_cutscenes_enabled` / `gt_skip_cutscenes_auto` data widgets + their localization keys (the `gt_cutscenes_group` group is retained for the loading-screen monologue toggle, which stays in gt).
  - the two regression checks `cutscene_auto_skip_deferred` / `cutscene_skip_setting_id_present` (now live in gut).
- **Kept in gt:** the Third-Person Camera cutscene-yield fix (v0.2.139-dev, `PlayerUnitFirstPerson.set_first_person_mode` in `_gt_camera.lua`) — it only READS the cutscene system (`is_active()`), never hooks it, so it is a separate feature and unaffected. Its `tp_camera_yields_to_cutscene` regression check stays.

## v0.2.139-dev (2026-06-24) -- FIX: Third-Person Camera no longer breaks the view after a cutscene

**Symptom:** with the Third-Person Camera enabled, the camera was left **broken after a cutscene played** -- reported on "Blood in the Darkness" / `dlc_bastion` when injected as a Chaos Wastes map (cutscenes also fire in other campaign missions; this is not bastion-specific).

**Root cause (source-cited).** At a cutscene's END, vanilla `CutsceneSystem.flow_cb_deactivate_cutscene_cameras` calls `self:set_first_person_mode(true)` (`Vermintide-2-Source-Code/scripts/entity_system/systems/cutscene/cutscene_system.lua:154`), which forwards to `first_person_extension:set_first_person_mode(true)` (cutscene_system.lua:123) with `override == nil` to RESTORE the player's first-person view. gt's Third-Person Camera hook on `PlayerUnitFirstPerson.set_first_person_mode` (`_gt_camera.lua`) blocks any `active and not override` call while TP is on (it exists to stop inspect/other systems from yanking the player back to 1P). The cutscene-end restore matches that exact shape (`active == true`, `override == nil`), so the hook **swallowed it** and the camera was never restored. `_tp_enabled` only clears on a game-state change (`general_tweaker_dev.lua` `on_game_state_changed`); a cutscene start/end is NOT a state change, so the block stayed live across the cutscene.

**Fix.** While a cutscene owns the camera, **yield** the block so the 1P restore goes through. The hook now bails out of the block when `CutsceneSystem:is_active()` is true (`is_active()` == `self.active_camera ~= nil`, cutscene_system.lua:83-85), looked up via `Managers.state.entity:system("cutscene_system")` (canonical access pattern, `flow_callbacks.lua:1050`) and pcall-guarded (the cutscene system isn't present at all times). This is robust at BOTH ends of the cutscene:
- During the cutscene, the per-frame `CutsceneSystem.update` calls `set_first_person_mode(false)` (cutscene_system.lua:64) -- `active == false`, which this block never matched, so nothing changes there.
- At deactivate, vanilla calls the 1P restore (cutscene_system.lua:154) BEFORE clearing `self.active_camera` (:156), so `is_active()` is still true at the exact moment our hook fires -> the restore passes through. The block self-heals the instant the cutscene camera goes away; no persistent state to leak (deliberately NOT clearing `_tp_enabled`, which is only re-armed on player spawn and would turn TP off permanently if flipped on cutscene end).

Normal TP-camera behavior is unchanged: during regular gameplay `is_active()` is false, so the spurious 1P restore (inspect, etc.) is still blocked exactly as before -- the yield is cutscene-only. SOLE hook on `PlayerUnitFirstPerson.set_first_person_mode` (existing hook body modified, no second hook added).

**Regression guard:** new `/gt_regression_test` check `tp_camera_yields_to_cutscene` -- source-pattern guard anchored on `mod._gt_apply_tp` (reads `_gt_camera.lua`) that FAILS if the `set_first_person_mode` hook no longer calls `_gt_cutscene_owns_camera()`, or if that helper no longer queries `cutscene_system` / `is_active`. Needle assembled from two literals so the check doesn't self-match.

## v0.2.138-dev (2026-06-24) -- FIX 1 give-half completion: Necromancer bot no longer gets stuck trying to pass a potion

**Symptom:** the Necromancer (`bw_necromancer`) bot would get **stuck trying to pass a potion but never complete the handoff**, looping in place.

**Root cause (source-cited).** FIX 1 in `_gt_bot_fixes.lua` already solved the *scoring* half: the Necromancer carries a non-droppable "skull" (`bw_necromancer_career_utility_weapon`, `slot_type="potion"`, `is_not_droppable=true`) that occupies the PRIMARY `slot_potion`, so a real potion picked up later lands in ADDITIONAL storage (`_additional_items["slot_potion"].items`). Every vanilla bot potion check reads only the PRIMARY slot:
- scoring `player_bot_base.lua:882-888` (`can_give_potion_to_other` off the primary template), and
- the give interaction `interactions.lua` `give` (`set_interactor_data`:1707-1711 captures `get_wielded_slot_name()`; the transfer `stop`:1640-1664 reads `get_slot_data(item_slot_name)` and gates on `template.can_give_other`:1646).

FIX 1's promote (swap the real potion to primary) is the right mechanism for BOTH halves — once the potion is primary, scoring, the give interaction, and self-drink all just work. **But the promote targeted the wrong storage occupant.** It scanned storage for *a* giveable potion, then called `swap_equipment_from_storage("slot_potion", SwapFromStorageType.First, ...)`. `SwapFromStorageType.First` promotes storage index 1 unconditionally (`get_additional_item_swap_id` returns `item_id=1`, ignoring the compare arg — `simple_inventory_extension.lua:2364-2365`). `slot_potion` storage is **not** potion-only: the **grimoire** also lives in `slot_potion` (`is_grimoire`, no `can_give_other` — `grimoire.lua:62`; bots stash it there — `bt_bot_conditions.lua:1244-1259` `should_drop_grimoire`), and the demoted skull lands there too. So with storage `= {grimoire, real_potion}` (or `{skull, ...}`), the First-swap promoted the grimoire/skull to primary, leaving primary STILL non-giveable. The give interaction could never resolve the real potion, and the bot looped "trying to pass but can't."

**Fix.** Locate the giveable potion's exact `item_data` reference (it lives in the live storage array we already iterate) and promote it **by identity** via `SwapFromStorageType.Same`, passing that `item_data` as the compare item — `get_additional_item_swap_id(Same)` returns the index where `stored_items[i] == compare_item` (`simple_inventory_extension.lua:2374-2385`). The REAL potion now lands in primary regardless of storage ordering; the grimoire/skull are never mis-promoted. Once the potion is primary, the whole vanilla give chain (and the bot drinking its own potion, REPLICANT PORT 2) just works. Necromancer-scoped (gated on `career_name() == "bw_necromancer"`), throttled ~1s, idempotent. No new hook (the existing single `PlayerBotBase.update` consolidation site drives the tick); no RPC; host-side only.

**Regression guard:** new `/gt_regression_test` check `necro_potion_give_half_targeted_promote` pins the `GT_NECRO_POTION_GIVE_HALF_MARKER_v0_2_138` source-pattern marker AND asserts `SwapFromStorageType.Same` exists, so a refactor back to a blind First-swap (or a vanilla enum drop) is caught.

## v0.2.137-dev (2026-06-24) -- In-mission inventory MIGRATED out to gui_tweaker (gut)

The in-mission inventory feature moved out of gt and into **gui_tweaker (gut)**, which now owns it. Removed here:
- **Deleted** `_gt_mission_ui.lua` (Open Inventory In Mission + the `HeroWindowLoadoutConsole._customize_item` cim crash-gate + the `HeroWindowPanelConsole.on_enter` tab-strip restore) and `_gt_keep_menus.lua` (the InventorySettings loadout-access patch + ESC-menu "Open Inventory" entry). Their two `mod:dofile` lines are gone.
- **Removed** the `mission_inventory_enabled` branch from `on_setting_changed` and the `mod._gt_apply_keep_menus()` re-apply from `on_game_state_changed`.
- **Removed** the `mission_inventory_group` settings group (`mission_inventory_enabled` / `gt_mission_menu_tabs` / `gt_open_inv_hotkey`) from `_data.lua` and its loc keys (incl. tooltips) from `_localization.lua`. The `/gt_inv` command + `mod.gt_open_mission_inventory` field are gone (replaced by `/gut_inv` in gut).

**Kept intentionally:** the `gt_no_mission_hotkey_flip` regression test (Issue #62) stays — it guards against the removed `IngameUI.handle_menu_hotkeys` hotkey-flip hook being reintroduced, which is still a gt concern independent of where the inventory feature lives. It anchors on `mod.on_setting_changed` (a main-file field), so it still reads `general_tweaker_dev.lua` correctly. No other gt feature touched. Stale comment blocks describing the removed feature were updated to migration notes.

## v0.2.136-dev (2026-06-23) -- "Cap Bot Ult Cooldown" default hardening (no longer ults bots constantly the instant you enable it)

`ult_bot_cap_value` defaulted to `0`, and the clamp at `_gt_hacks.lua:207` (gated on `ult_bot_cap_enabled` + bot-only) sets every bot ability's remaining cooldown to that cap each `CareerExtension.update` tick — so `0` meant **bots ult constantly** the moment the toggle was switched on. That matched the loc ("0 = bots ult constantly") but is a footgun: a user enabling the toggle to "see bots ult more aggressively" got nonstop ults with no obvious cause. Changed the default to **20s** (aggressive but not unlimited; the loc's stated intent). No logic change — the clamp + gating are unchanged and correct; users can still set `0` explicitly for constant ulting. `ult_player_cap_value` left at `0` (a deliberate self-applied "always ready" cheat, off by default).

## v0.2.135-dev (2026-06-20) -- refactor (Phase 4, final): extract the three largest / highest-coupling feature blocks to modules -- no behavior change

Pure code-reorganization, **no behavior change** (Phase 4, the final phase of the main-file split begun in v0.2.132-dev). Carves ~2499 more lines out of `general_tweaker_dev.lua` (4506 -> 2007 lines) into three new `_gt_*` modules, loaded via the existing `mod:dofile` chain. Each module was lint+build-gated individually; every moved `(Class, method)` hook was grep-verified as a singleton across main + all `_gt_*` modules before the move. Dispatchers (`on_setting_changed` / `on_disabled` / `on_game_state_changed`) stay in main and resolve each moved feature through a `mod._gt_*` / `mod._gt_cs_*` / `mod._gt_ai_*` field at call time. The `/gt_regression_test` block stays in main; every check that referenced a moved symbol was repointed to the matching `mod._*` exposure (all 29 checks preserved, byte-identical name list to the pre-phase file). Lint PASS (0 dup-hook / 0 forward-ref / 0 late-local) and build exit 0 after every step.

### Changed (internal only)
- **New `_gt_creature_spawner.lua`** -- the Aussiemon CreatureSpawner port (Workshop 1395132559), ~983 lines, ~28 hooks. Every hook is a singleton (verified across main + all modules): the keep-spawn `ConflictDirector.update` strip-down (a DIFFERENT method from the consolidated `ConflictDirector.spawn_queued_unit` hook, which STAYS in main), `StateIngame.update`, `AISystem.update_brains`, `AIGroupSystem.update`, `AiBreedSnippets.reward_boss_kill_loot`, `AiUtils.update_aggro`, `ProjectileEtherealSkullLocomotionExtension.init`, `BTEnterHooks.warlord_defensive_on_enter`, `BTSpawnAllies.{enter,run,leave,find_spawn_point}`, `Breeds.chaos_exalted_sorcerer_drachenfels.{run_on_spawn,run_on_death}`, `BTConditions.transitioned_one_third_health`, `BTLootRatFleeAction.{enter,run,leave}`, `NavigationGroupManager.a_star_cached_between_positions`, `LocomotionUtils.pos_on_mesh`, `GwNavQueries.inside_position_from_outside_position`, `Unit.create_actor` (DISTINCT method from `Unit.get_data` in `_gt_hacks.lua`), `BTSkulkAroundAction.get_new_skulk_goal`, `Utility.get_action_utility`, `BuffSystem.add_buff`, `World.spawn_unit`, `EnemyPackageLoader.request_breed`. The two forward-declared file-local callbacks (`_gt_cs_on_setting_changed` / `_gt_cs_on_game_state_changed`, consumed by the main `on_setting_changed` / `on_game_state_changed` DISPATCHERS) were promoted to `mod._gt_cs_*` fields; the helper `_gt_cs_is_in_level` was exposed as `mod._gt_cs_is_in_level` and the `gt_cs_is_in_level_prefix_match` regression check repointed to it. Self-contained otherwise (own `gt_cs_*` settings + commands).
- **New `_gt_ai_takeover.lua`** -- AI Takeover (hand your character to a bot) + AFK->AI takeover, ~615 lines. The destructive swap remains DISABLED pending the keep-slot redesign (`mod._gt_ai_takeover_disabled` -- behavior unchanged; every entry point still bails). The only `(Class, method)` registration is the `_AI_RPC` (`gt_ai_toggle_request`) VMF network event (`mod:network_register`, not a `mod:hook`). **Forward-decl promotions:** the cross-boundary file-locals shared with main's DISPATCHERS / debug dump / regression block were promoted from main file-locals to `mod._gt_ai_*` fields (seeded at the top of main; assigned/used by the module) so both sides resolve them at call time: `mod._gt_ai_pending_client_send`, `_pending_host_toggle`, `_suppress_setting_callback`, `_saved_state`, `_handle_toggle_change`, `_takeover_disabled`, and `_afk_took_over` / `_afk_idle_t` / `_afk_input_stamp` / `_afk_grace_until`. **`ai_pending` consumer decision:** now that those locals are `mod._gt_ai_*` fields, the deferred-consumer half that Phase 3 left in main (split out of the old merged `infinite_ammo_and_ai_pending`) **moved INTO this module** alongside the `_ai_consume_*` drains it calls -- it registers via `mod._gt_register_update` (along with the `afk_autobot` consumer). The `_AI_CLIENT_SEND_*` tuning constants moved here too (they were forward-declared in main but only consumed by the send queue). `_ai_swap_human_to_bot` was exposed as `mod._gt_ai_swap_human_to_bot` for the `ai_locomotion_override_set_and_cleared` source-pattern regression check (which `debug.getinfo`s it -> now reads THIS module's source, where the `set_override_player(bot_player)` / `(nil)` call-pair moved). The two AI marker constants (`CT_GT_AI_CLIENT_SEND_MARKER_v0_2_52` / `CT_GT_AI_LOCOMOTION_OVERRIDE_MARKER_v0_2_73`) STAY in main with their regression checks. The always-on `AICommanderExtension._update_units` crash guard is a SEPARATE feature and STAYS in main (per the spec). The module's debug-toggle dump wrap calls `mod._gt_dump_ai_now` (exposed by `_gt_debug_probes.lua`, nil-guarded, call-time resolved).
- **New `_gt_debug_probes.lua`** -- Debug Mode (auto-dump on key events) + observation/probe hooks + the burning-enemy fire VFX probe, ~951 lines. Gated on `mod:get("enable_debug_logging")` (preserved). **Every observation hook is a singleton and is debug-exclusive** -- the whole-mod `(Class, method)` audit confirmed NONE of `HeroView.{on_enter,on_exit}` / `HeroWindowItemCustomization.{on_enter,on_exit}` / `IngameUI.handle_transition` / `LevelTransitionHandler.load_current_level` / `BackendInterfaceItemPlayfab.refresh_bot_loadouts` / `PlayerManager.{add_remote_player,remove_player,relinquish_unit_ownership}` / `CharacterStateHelper.change_camera_state` / `HeroViewStateOverview.{set_layout_by_name,on_enter,_change_window}` is hooked by any other gt feature (the mission-UI module hooks `HeroWindowLoadoutConsole` / `HeroWindowPanelConsole`, NOT these), so ALL moved (none stayed behind as shared). Exposes `mod._dbg_on` / `mod._dbg_log` (consumed by the mission-UI `_customize_item` hook + the AI Takeover debug wrap), `mod._dbg_alert`, and `mod._gt_dump_ai_now` (consumed by the AI Takeover debug-toggle wrap). Consumes the `mod._gt_ai_*` state fields for the AI dump. The two `mod.on_game_state_changed` observation wraps + the `mod.update` deferred-dump wrap are additive (`prev()` first), so re-wrapping at module-load (loaded first of the modules, closest to original chunk order) is behavior-neutral. The main file retains its OWN top-of-file `_dbg` / `_dbg_alert` pair (which the `dbg_helpers_two_channel` regression check resolves -- the moved debug-block pair previously shadowed it; both are functionally identical, same gate + channels).

### Notes
- **Update-consumer registration order:** `ai_pending` + `afk_autobot` now register when `_gt_ai_takeover.lua` loads (mid-module-chain) rather than interleaved in the original main-file position. They are independent of the other consumers and decoupled across frames via the persistent send/AFK queues, so same-frame ordering does not matter -- behavior is neutral.
- **Final main-file size:** `general_tweaker_dev.lua` is now 2007 lines (bootstrap + `mod._gt_ai_*` seeds + the godmode body + the `_GT_GODMODE_RPC` + the Disable/Clear Enemy Spawns spawns-control block incl. the consolidated `ConflictDirector.spawn_queued_unit` hook + the `AICommanderExtension._update_units` guard + the `on_setting_changed` / `on_disabled` / `on_game_state_changed` DISPATCHERS + the 29-check `/gt_regression_test` block + the `mod:dofile` loader manifest). The whole mod now spans 30 `_gt_*` feature modules.

## v0.2.134-dev (2026-06-20) -- refactor (Phase 3): extract medium / shared-table-hook features to modules -- no behavior change

Pure code-reorganization, **no behavior change** (Phase 3 of the main-file split begun in v0.2.132/.133-dev). Carves ~1247 more lines out of `general_tweaker_dev.lua` (5753 -> 4506 lines) into five new `_gt_*` modules, loaded via the existing `mod:dofile` chain at the bottom of the main file. Each module was lint+build-gated individually; every moved `(Class, method)` hook was grep-verified as a singleton across main + all `_gt_*` modules (and against `_gt_lobby_slot_reservations.lua` / `_gt_solo_qol.lua` specifically) before the move. Dispatchers (`on_setting_changed` / `on_disabled` / `on_game_state_changed`) stay in main and resolve each moved feature through a `mod._gt_*` / `mod.gt_*` field at call time. Lint PASS (0 dup-hook / 0 forward-ref / 0 late-local) and build exit 0 after every step.

### Changed (internal only)
- **New `_gt_mission_ui.lua`** -- in-mission hero-view access (3 features, all singleton hooks): Open Inventory In Mission (`mod.gt_open_mission_inventory` + `/gt_inv`; no hook -- drives `Managers.ui:handle_transition("hero_view_force")` directly), Mission Customize gear-icon cim-gate (`HeroWindowLoadoutConsole._customize_item`), and Show menu tabs in-mission (`HeroWindowPanelConsole.on_enter`). `gt_open_mission_inventory` stays a `mod.` field so the VMF keybind + `/gt_inv` resolve it. The `mission_inventory_enabled` InventorySettings/ESC-menu patch did **not** move here (see `_gt_keep_menus.lua`). The `gt_no_mission_hotkey_flip` Issue-#62 regression test was re-anchored from `mod.gt_open_mission_inventory` to `mod.on_setting_changed` so it keeps reading the MAIN file's source (where the removed `IngameUI.handle_menu_hotkeys` hook lived).
- **New `_gt_bots_keep.lua`** -- two host-side bot-roster features, neither with a `(Class, method)` hook: Bots in Keep (`mod._bik_fill`/`_clear`/`_active`/`_reset_bookkeeping` + the `bots_in_keep` update consumer; still kill-switched in source) and Disable Bots (Solo) (`mod._gt_apply_no_bots`). The forward-declared file-local `_gt_apply_no_bots` was retired in favor of the `mod._gt_apply_no_bots` field; `on_game_state_changed` (StateIngame-enter re-apply) + `on_setting_changed` (`gt_no_bots`) + the `no_bots_apply_sets_ai_bots_disabled` regression test were all repointed to it. The `_bik_*` regression tests already read `mod._bik_*` fields.
- **New `_gt_level_control.lua`** -- co-locates everything between the original "Level Control" and "AI Toggle" sections so the ProfileSynchronizer singleton audit is local: Level Control (win/fail/restart host-exec + client->host RPC), the End-of-level profile fallback / score-screen fix, `gt_kill_bots` / `gt_die`, `/gt_respawn` (client->host RPC), `gt_fix_sound`, `gt_bot_toggle`, and Duplicate Careers. Holds **four DISJOINT** ProfileSynchronizer hooks (`get_persistent_profile_index_reservation` for the score-screen fix vs `get_profile_index_reservation` / `try_reserve_profile_for_peer` / `is_free_in_lobby` for Duplicate Careers) plus `StateInGameRunning._award_end_of_level_rewards`. Verified the gt lobby slot-reservations feature does NOT hook ProfileSynchronizer (no cross-module collision). The block was fully self-contained (own RPC names + helper locals); every keybind-bound callable stays a `mod.` field, so no main-file dispatcher needed repointing.
- **New `_gt_keep_menus.lua`** -- Keep Menus in Missions (the `InventorySettings.inventory_loadout_access_supported_game_modes` patch + the ESC-menu "Open Inventory" entry). Pure data-table mutation, NO hook (the legacy `IngameUI.handle_menu_hotkeys` hook was already removed in v0.2.82-dev). Exposes `mod._gt_apply_keep_menus`; per the dispatcher rule the `on_game_state_changed` + `on_setting_changed` (`mission_inventory_enabled`) DISPATCHERS stay in main and call it at the same points the file-local `_patch_inventory_access()` was called. Applied once at the module's own load (mirrors the original load-time call).
- **New `_gt_hacks.lua`** -- the Janoti "Hacks" port Groups B/C/D/F, co-located for a local singleton audit: Time & Pause (B), Ult Controls (C, `CareerExtension.update`), Buffs & Stat Tweaks (D -- infinite ammo/stamina/`GenericStatusExtension.add_fatigue_points`, giga power, base crit + `ProfileRequester.request_profile`/`GameModeInn._cb_start_menu_closed`, movement speed, fall damage), and the Engine error nil-guards (F -- `VolumetricsFlowCallbacks.unregister_fog_volume`, `Unit.get_data`, `PlayerWhereaboutsExtension.update`, `RoundStartedSystem._players_left_start_area`). The pause flag (was forward-declared file-local `_pause_active`) became the shared `mod._gt_pause_active` field so the `on_game_state_changed` dispatcher's per-transition clear and the toggle's read path see the same value. `gt_time_apply` / `gt_apply_crit_chance` / `gt_apply_move_speed` / `gt_apply_fall_damage` stay `mod.` fields for the `on_setting_changed` branches + the fall-damage regression test. The original merged `infinite_ammo_and_ai_pending` update consumer was **split**: the infinite-ammo refresher half registers here as `infinite_ammo` (via `mod._gt_register_update`); the AI-takeover deferred-consumer half stays in main as `ai_pending` (it references AI-takeover file-locals). The two halves share no state, so the split is behavior-neutral. The always-on `AICommanderExtension._update_units` crash guard (a separate AI-takeover guard) stays in main near the AI Takeover code.

### Not moved (reported)
- **Disable Enemy Spawns + Clear Enemy Spawns** (the planned `_gt_spawns_control.lua`) were **left in the main file**. Disable Enemy Spawns gates inside `ConflictDirector.spawn_queued_unit`, which is a CONSOLIDATED multi-mod hook in main also serving `_gt_solo_qol.lua` (`mod._gt_solo_on_spawn_queued`) and the necro-pet probe -- so per the singleton rule that hook cannot move, and fragmenting half the feature into a module while its primary gate stays in main would add confusion for no benefit. `ConflictDirector.update` (Creature Spawner, Phase 4) is a DIFFERENT method (disjoint, irrelevant here). `_apply_script_data_no_enemies` + `/no_enemies` + Clear Enemy Spawns (`mod.gt_clear_enemies` + `/clear_enemies`) stay alongside it.

## v0.2.133-dev (2026-06-20) -- refactor (Phase 2): extract 5 single-hook self-contained features to modules -- no behavior change

Pure code-reorganization, **no behavior change** (Phase 2 of the main-file split that began in v0.2.132-dev). Carves ~764 more lines out of `general_tweaker_dev.lua` (6517 -> 5753 lines) into five new `_gt_*` modules, loaded via the existing `mod:dofile` chain (the `.mod` package's `lua = ["scripts/mods/general_tweaker_dev/*"]` wildcard auto-bundles them). Each module was lint+build-gated individually; every moved `(Class, method)` hook was grep-verified as a singleton across main + all `_gt_*` modules before the move. Lint PASS (0 dup-hook / 0 forward-ref / 0 late-local) and build exit 0 after every step.

### Changed (internal only)
- **New `_gt_camera.lua`** -- Third-Person Camera. Hooks `PlayerUnitFirstPerson.set_first_person_mode` + `.extensions_ready`; registers its own `tp_camera` `mod.update` consumer. Exposes `mod._gt_apply_tp` / `_gt_patch_camera_offset` / `_gt_restore_camera_offset` (read by the main `on_setting_changed` AND `on_disabled`) + `mod._gt_tp_reset_enabled` (read by `on_game_state_changed`). The shared `extensions_ready` hook ALSO scheduled the godmode/noclip post-spawn re-apply; that timer + its `post_spawn_reapply` consumer stay in main (godmode is not moved), so the hook now calls the new main-file `mod._gt_schedule_post_spawn_reapply()`. Loaded first of the five so its `tp_camera` consumer registers ahead of `cutscene_auto_skip` (original relative order).
- **New `_gt_noclip.lua`** -- Noclip. Hooks `PlayerUnitLocomotionExtension.update_script_driven_no_mover_movement`; owns the `/noclip` command + `mod.gt_noclip_toggle` (the keybind `function_name`). Exposes `mod._gt_apply_noclip` (read by `on_setting_changed` + the shared `post_spawn_reapply` consumer that re-arms godmode AND noclip), `mod._gt_noclip_heartbeat` (per-frame locomotion-state re-assert, called from that same shared consumer), and `mod._gt_noclip_reset_active` (read by `on_game_state_changed`). The `post_spawn_reapply` consumer + `_post_spawn_reapply_timer` stay in main.
- **New `_gt_cutscenes.lua`** -- Skip Cutscenes (Group G). Hooks `CutsceneSystem.flow_cb_cutscene_effect` / `.flow_cb_activate_cutscene_logic` / `.skip_pressed` + `ShowCursorStack.pop`; registers its own `cutscene_auto_skip` consumer via `mod._gt_register_update`; exposes `mod.gt_skip_cutscenes_toggle`. The `on_setting_changed` branch for `gt_skip_cutscenes_enabled` sets `script_data.skippable_cutscenes` inline (no cross-file call), so dispatch is unchanged. The two `/gt_regression_test` cutscene checks stay in main (they read a marker string + `mod:get()`, never a moved function).
- **New `_gt_misc_features.lua`** -- three small features: Choose Grail Knight Quests (`PassiveAbilityQuestingKnight._generate_quest_pool`), Ready Up! (`VoteManager.rpc_client_complete_vote` + `mod.gt_ready_up_now` host shortcut / keybind), and the Adventure save-consumable trait odds (load-time data mutation, no hook; exposes `mod._gt_apply_adv_save_traits`, resolved at call time from `on_setting_changed`). The `gk_quest_dropdowns_dont_share_options` regression check stays in main (it inspects the DATA file).
- **New `_gt_godmode_qol.lua`** -- the QoL/cheat bundle (explicitly NOT the godmode body): Unstuck (`/unstuck`), Friendly Fire Toggle (`DamageUtils.allow_friendly_fire_ranged`/`_melee` -- DISTINCT methods from the godmode `add_damage_network*` hooks that stay in main, so no duplicate-hook collision), Player-state toggles (inn-damage / cloak / unkillable commands), Disable Loading-Screen Monologues, and More Corpses (`RagdollSettings` cap; exposes `mod.gt_apply_corpse_count`, resolved at call time from `on_setting_changed`). The godmode invisibility + `add_damage_network*` damage-blocking body remains in the main file (shared with the floating-damage-numbers feature).

## v0.2.132-dev (2026-06-20) -- refactor: extract dump commands + item spawner to modules -- no behavior change

Pure code-reorganization, **no behavior change**. Carves ~830 lines of command-only code out of the main `general_tweaker_dev.lua` (7529 -> 6515 lines) into two new self-contained `_gt_*` modules, loaded via the existing `mod:dofile` chain (the `.mod` package's `lua = ["scripts/mods/general_tweaker_dev/*"]` wildcard auto-bundles them). Relieves the main chunk's 200-locals pressure and the file-size budget. All moved blocks were verified hook-free before extraction.

### Changed (internal only)
- **New `_gt_dumps.lua`** -- the read-only console dump commands: `/dump_level` (the ~536-line verbose level/world/pickups/breeds/UI snapshot, with its verbose doctrine comment trimmed to 3 bullets), `/dump_glossary`, `/dump_cosmetics`, `/dump_items_by_slot`, `/gt_dump_hero_view`. The shared `_write_dump` log helper moved here too (all four of its callers moved with it), so it's no longer a main-file local.
- **New `_gt_item_spawner.lua`** -- the pickup Item Spawner (`/gt_spawnitem`, `/gt_nextitem`, `/gt_previtem` + the `mod.gt_is_*` helpers and the `_gt_is_*` file-locals). Ported-from-ItemSpawner block lifted verbatim. The `/gt_regression_test` `gt_pickup_lookup_uses_rawget` check and its marker constant `CT_GT_PICKUP_LOOKUP_RAWGET_MARKER_v0_2_48` stay in the main file (the check reads the marker + probes `NetworkLookup.pickup_names` at runtime; it never calls the moved code), so it remains resolvable.

## v0.2.131-dev (2026-06-20) -- Replicant Bots ports, grudge-mark in-game names, A-Z menu sort

### Added (Bot Options -- three Replicant Bots ports, all host-side, default OFF, `[untested]`)
- **Faster bot reactions** (`gt_bot_fast_reactions`). Ported from "Replicant Bots - Different Bots Experimental Branch" (`DifferentBots.lua:273-306` + `:3056-3058`). On enable: overwrites `BotConstants.default.OPPORTUNITY_TARGET_REACTION_TIMES` with `{min=0.2, max=0.5}` for every difficulty the vanilla table defines, and makes `AiUtils.calculate_bot_threat_time` return the raw `bot_threat.start_time, bot_threat.duration` (no random start-delay) so bots react to telegraphed attacks immediately. The source mod's `on_disabled` is author-flagged broken, so gt does a **real** snapshot/restore: the vanilla reaction table is deep-copied on first apply and written back verbatim on toggle-off (wired into `on_setting_changed` + `on_disabled`, plus a boot-time apply if already on). The per-breed `BreedActions` retuning was deliberately skipped. New `mod:hook("AiUtils", "calculate_bot_threat_time", ...)` -- a fresh `(Class, method)` pair (the only other `AiUtils` hook in the repo is `_gt_solo_qol.lua`'s `generic_mutator_explosion`).
- **Bots drink potions when in danger** (`gt_bot_drink_potions_in_danger`). A throttled per-bot tick (gt idiom, mirrors `_gt_ladder_unstick_tick` etc.; NOT a copy of Replicant's `bt_bot_drink_pot_action` BT node) driven from the single consolidated `PlayerBotBase.update` hook. When a bot holds a giveable potion in `slot_potion` AND a danger is within ~18 m -- a `breed.boss` monster/lord, or a cluster of >= 3 `breed.elite` units (a roaming patrol) -- it wields `slot_potion` and holds the use input until the potion is consumed (the same drink primitive `BTBotHealAction` uses). Reads **live** breed data each scan (`Unit.get_data(enemy, "breed")` off `Side:enemy_units()`), not a static name roster. Host-side (bots are host-only).
- **Announce when a bot's guard breaks** (`gt_bot_guard_break_msg`, dropdown: Off / Host only / Host + clients). Ported from `DifferentBots.lua:2443-2472`. Hooks `GenericStatusExtension.set_block_broken`; on the rising edge (was unbroken, now breaking) for a BOT-owned unit, posts a chat line -- `add_local_system_message` for host-only, `send_chat_message` for the whole lobby. New `(Class, method)` pair (the only other gt hook on `GenericStatusExtension` is `update_falling` in the main file).

### Changed
- **Grudge-mark labels -> official in-game names** (Creature Spawner manual toggles). Converted the `gt_cs_grudge_*` labels from internal names to the player-facing in-game display names, verified against Fatshark's "All About Grudge Marks" article cross-checked with the buff mechanics in `scripts/settings/dlcs/grudge_marks/buff_settings_grudge_marks.lua`: `warping`->**Shadow-Step**, `intangible`->**Illusionist** (summons 3 mirror images), `unstaggerable`->**Relentless**, `raging`->**Mighty**, `vampiric`->**Vampiric**, `ranged_immune`->**Rampart** (confirmed), `periodic_shield`->**Invincible** (periodic `buff_perks.invulnerable`), `crippling`->**Crippling**, `crushing`->**Shield-Shatter**, `regenerating`->**Regenerating**, `periodic_curse`->**Cursed Aura**. Internal name kept in parentheses on each label + tooltip for cross-reference. (Note: the two earlier swaps -- `intangible` is the mirror-image "Illusionist", and `periodic_shield` is the invulnerability "Invincible" -- were verified against the buff `update_func`/`perks`, not assumed from the internal name.) `commander` and `frenzy` were outside the requested set and left unchanged.
- **Top-level menu categories sorted A->Z** by display label (standing reorder rule): Bot Options (AI Teammates), Cheats and Debug, Cutscenes & Monologues, Floating Damage Numbers, Gameplay, Host-Side Lobby Controls, Keep Menus in Missions, Main Menu / Startup, More Corpses, Ready Up, Solo & QoL, Third-Person Camera -- with **Debug Logging pinned last** (convention) and the intra-camera distance/height/offset ordering preserved. No widgets or settings changed; only the top-level group order.

## v0.2.130-dev (2026-06-20) -- Hide UI migrated to GUI Tweaker (gut)

### Changed
- **Hide UI (off/partial/complete/camera) moved to GUI Tweaker (`gut`).** The feature, its `gt_hud_mode` dropdown + `gt_hud_cycle_hotkey` keybind, the `/gt_hud` command, and its localization were removed from gt and now live in gut as `gut_hud_*` + `/gut_hud`. Two latent bugs were fixed in the move (the HUD-disable hook now hits the derived game-mode classes, and the force-hide reads the correct `Managers.ui._ingame_ui.ingame_hud` path). Conceptually it belongs with the GUI mod alongside the other HUD/UI tooling.

## v0.2.129-dev (2026-06-20) -- Crash fix: bot melee node hard-crashes on nil slot_data when a bot is given a weapon

Hard-crash fix (HOST, GUID 35c69dda, reported 2026-06-20): `bt_bot_melee_action.lua:83 attempt to index local 'slot_data' (a nil value)` in `BTBotMeleeAction.enter`. When a bot's wielded slot is transient/empty for a frame -- e.g. the bot was just **given a weapon** (CW bot-weapon mirror / cim / wt bot loadout / a vanilla bot inventory re-equip) and the slot has no data yet -- vanilla `enter` (`bt_bot_melee_action.lua:82-83`) reads `inventory_ext:get_slot_data(wielded_slot)` (nil) then immediately derefs `slot_data.item_data` and fatals.

Guarding `enter` alone is insufficient: `enter` writes `blackboard.wielded_item_template` (nil in the empty-slot case) and the **whole** melee node derefs it the same frame -- `_update_melee` (`:418`) -> `_choose_attack` (`:220`), `_defend.defense_meta_data` (`:499`), `_can_stagger_target.actions` (`:562`), `_time_to_next_attack`/`_attack` `.attack_meta_data/.actions/.name` (`:584-600`). So the node must not run a frame with a nil weapon. Two-part fix:

- **`_gt_bot_fixes.lua` -- new ungated hook on `BTBotMeleeAction.enter`.** When the wielded slot has no data, replicate vanilla's always-safe early blackboard setup (`node_timer`, the `melee` table, `set_aiming`) ourselves and leave `wielded_item_template = nil`, skipping the crashing `:83` deref. (Vanilla `func` is never called on the empty-slot path, so `:83` can't run.) When the slot IS populated, vanilla runs unchanged.
- **`_gt_improved_bot_combat.lua` -- consolidated the existing `(BTBotMeleeAction, "run")` hook.** It was a `hook_safe` (ping-the-attacking-elite feature). VMF allows only one hook per `(Class, method)` per mod, so the crash guard was folded INTO it and it was converted to a full `mod:hook`: it now bails the node `("done","evaluate")` whenever `blackboard.wielded_item_template == nil`, so `_update_melee` never derefs the nil weapon, then otherwise calls the original and runs the (gated) ping logic. The bot leaves melee for one frame and the BT re-selects next frame once the slot is populated.

Both halves are **ungated** (the crash guard fires regardless of the `gt_improved_bot_combat` toggle -- it's a crash fix, not the smarter-combat feature). Host-side only (bots are host-only); no RPC, so inert/crash-safe on clients. No new menu toggle. Verified line-for-line against the decompiled vanilla source (`scripts/entity_system/systems/behaviour/nodes/bot/bt_bot_melee_action.lua`).

## v0.2.128-dev (2026-06-20) -- Menu restructure: Cheats and Debug category, bot bundle, flies moved to enemy_tweaker

Large menu reorganization (no behavior change to kept features beyond the bot-toggle bundling):

- **Bot Behavior Improvements bundle.** The eight individual Bot Options toggles -- Necromancer potion handoff, don't-fail-while-a-bot-is-alive, auto ledge pull-up (+delay), ladder unstick (+delay), instant grab targeted items, prioritize revive, allow revive during ult, rescue ledge/hooked/disabled allies -- are now a SINGLE `[confirmed working]` checkbox **Bot Behavior Improvements** (`gt_bot_behavior_improvements`). The two former delay sliders are gone; the delays are hard-coded (ledge pull-up 3s, ladder unstick 4s). Every `_gt_bot_fixes.lua` site that read one of the eight ids (the `PlayerBotBase.update` dispatch, `BTConditions.can_activate_ability` Ironbreaker gate, the `_select_ally_by_utility` revive/rescue-priority gates, and `GameModeHelper.side_is_dead` fail-prevention) now reads the bundled id. **Kept as separate toggles:** Improved Bot Combat, Bots rescue allies awaiting respawn, Split bots among players, Bots always follow host, Tighter bot follow distance (+ its meters slider).
- **New "Cheats and Debug" category** (`cheats_debug_group`). Godmode and the noclip cluster (enable/speed/boost/hotkey) moved out of Gameplay into it; the formerly top-level **Buffs & Stats**, **Ult**, **Time & Pause**, **Level Control**, and **Spawners** groups are now nested sub-groups of it.
- **Removed "Player State Toggles" group** (it held only the Cloak/invisibility hotkey widget). The `/cloak` chat command and `gt_cloak_toggle` function are unchanged -- only the menu widget is gone.
- **Prioritize Specials (targeting)** and **Choose Grail Knight Quests** are now nested under **Gameplay** (were top-level groups).
- **Flies-disable feature moved to enemy_tweaker** (`gt_fly_disable_mult` -> `et_fly_disable_mult`). The Boss Mechanic Tweaks group and `_gt_boss_tweaks.lua` flies logic are removed from gt_dev (file renamed `.bak.v0.2.127-dev`; its `mod:dofile` line dropped).
- **Test-status:** all `gt_cutscenes_group` (Skip Cutscenes, Auto-skip, Disable Loading-Screen Monologues) and `gt_readyup_group` (Ready Up, Auto-start On Vote Pass) labels flipped `[untested]` -> `[confirmed working]`.
- **Debug Logging** moved to the very bottom of the menu (after Main Menu / Startup).

## v0.2.127-dev (2026-06-20) -- Bundle: Creature Spawner + Item Spawner under a "Spawners" menu

Menu organization (start of the dev-side toggle bundling, see memory [[project_dev_granular_live_bundled]]): the **Creature Spawner** (`gt_cs_group`) and **Item Spawner** (`gt_is_group`) groups are now nested inside a new collapsible parent group **"Spawners"** (`gt_spawners_group`). No settings changed -- both spawner sub-menus keep their own labels, toggles, and keybinds; they're just grouped one level deeper so the top-level menu is tidier. VMF nested-group collapsibles (the same pattern career_tweaker's BR menu used).

## v0.2.126-dev (2026-06-20) -- Test-status: godmode + prioritize-specials-when-tagging confirmed

`[confirmed working]`: **Godmode** (`godmode_enabled`) and **Prioritize Specials When Tagging** (`gt_prio_special_tag`, tag specials through enemies/pickups) -- both user-confirmed in-game 2026-06-20. (The ct_dev 0.7.154 tome-in-Adventure fix was also confirmed working in the same session.)

## v0.2.125-dev (2026-06-20) -- Bot-loadout probe: fire under Loremaster's Armoury (LA clone-backend)

The v0.2.123 bot-loadout probe never fired in the field: a session log showed 14 vanilla `refresh_bot_loadouts` runs (18:08:10-18:16:27) with the gt_dev class hook installed at 18:07:57, yet ZERO `[bot_loadout:]` lines -- because Loremaster's Armoury (active) replaces the live item interface with a **clone whose methods are copied**, so a hook on the `BackendInterfaceItemPlayfab` *class* method is bypassed (the documented LA clone-backend dispatch caveat, CROSS_MOD_ARCHITECTURE.md). This is very likely also WHY the designated bot loadout is ignored -- the LA-cloned `refresh_bot_loadouts` path isn't applying `bot_equipment`. Fix: the probe now resolves the **live** interface via `Managers.backend:get_interface("items")` (the accessor cim/CWV use) and table-hooks that instance (LA-safe). Run **`/gt_bot_loadout_dump` in the keep** after configuring bots -- it dumps immediately AND wires auto-dump for subsequent refreshes. The non-LA class hook is retained for setups without LA.

## v0.2.124-dev (2026-06-20) -- Necro-ult / patrol-crash trace (name the crashing unit)

Instrument for the reported Necromancer-bot-ult crash, which so far only ever logs as the vanilla patrol crash (`ai_group_templates_patrol.lua update_units -> Vector3_distance_squared`, "Vector3 expected, got userdata"). Two host-side probes, both unconditional `mod:info` (land with Debug Logging OFF), log-only (no guard, so the crash still yields its backtrace):

- **`[patrol_probe]`** -- table-hooks `AIGroupTemplates.spline_patrol.update` and, each tick, scans the group's `indexed_members`; emits a line naming any member whose `POSITION_LOOKUP` is missing or not a valid `Vector3` (the exact arg that crashes `update_units`) **with its breed** -- so the next crash names the offending unit. If that breed is `pet_skeleton_*`, the Necromancer pets are entering patrol groups (would refute the source analysis that says they can't); if `skaven_*`/`chaos_*`, it's the oversized-patrol path covered by enemy_tweaker 0.7.13's row cap. Only emits on a bad member, so no per-frame spam.
- **`[necro_probe]`** -- folded into the existing `ConflictDirector.spawn_queued_unit` hook (no new hook): logs Necromancer pet-skeleton (`pet_skeleton*`) spawns for timeline correlation with the crash.

Grep `[patrol_probe]` / `[necro_probe]` in the console log. Pre-flight: the patrol hook is a new table-hook on `AIGroupTemplates.spline_patrol` (zero prior gt_dev hooks there); the pet log extends the existing `spawn_queued_unit` hook rather than adding a second.

## v0.2.123-dev (2026-06-20) -- Bot-loadout resolution probe (bots using host's weapons)

Diagnostic for the report that AI bots spawn with the host's last-equipped loadout instead of the loadout the host designated as the bot loadout (via the loadout-slot UI / "Modern UI"). New host-side probe re-derives vanilla `BackendInterfaceItemPlayfab.refresh_bot_loadouts` resolution **read-only** and auto-dumps (forced output, no command / no Debug Logging) on every refresh, logging per career which branch fired: `NO_ASSIGNMENT` (the UI mod's bot-loadout assignment never reached `PlayerData.loadout_selection.bot_equipment`), `ASSIGNED_BUT_MISSING_IN_MIRROR` (`backend_mirror:has_loadout` failed -> assignment cleared), or `OK_DESIGNATED` -- plus a `clones_host_current` flag (the bug signature) and a summary line. Manual: `/gt_bot_loadout_dump`. Grep `[bot_loadout:` in the console log. (Pre-flight: zero prior gt_dev hooks on `BackendInterfaceItemPlayfab`/`refresh_bot_loadouts`.)

## v0.2.122-dev (2026-06-20) -- Migrate "Bot Improvements - Combat Returns" into one "Improved Bot Combat" toggle (+ its crash fix)

### Added — `gt_improved_bot_combat` (Bot Options group, default OFF)
A from-scratch reimplementation (new file `_gt_improved_bot_combat.lua`) of the **non-conflicting** combat features from the "Bot Improvements - Combat Returns" Workshop mod (3560390486), folded into a single host-side toggle:
- **Smarter melee attack choice** — bots prefer the penetrating/wide attack vs armour or crowds, the fast attack otherwise (`BTBotMeleeAction._choose_attack`). **Includes the crash fix:** the standalone mod read `inventory:get_slot_data(wielded_slot):item_data` with no nil-check and fataled (`BotImprovementsCombatReturns.lua:49: attempt to index local 'slot_data' (a nil value)`) when a bot's wielded slot was transient/empty — e.g. a just-swapped **AI-Takeover** bot; the reimplementation nil-guards and falls back to vanilla.
- **Ping attacking elites** — a bot pings the elite that's targeting it (`PingTargetExtension.set_pinged` + `BTBotMeleeAction/BTBotShootAction.run`, LoS-checked, 2 s cooldown).
- **Stop chasing far specials** (`PlayerBotBase._enemy_path_allowed`, ~7 m cap).
- **Ignore distant gunner line-of-fire** — only take cover from close shooters (`PlayerBotBase._in_line_of_fire`).
- **Don't over-focus bosses** — only treat a boss as urgent when close and not mid-crowd (`AIBotGroupSystem._update_urgent_targets`).
- **Smarter ult timing** for Mercenary / Huntsman / Maidenguard / Shade / Captain / Unchained (`BTConditions.can_activate.<career>`).

### Excluded (conflict with gt, or no-op as a single toggle)
- **Ironbreaker ult** → gt's `gt_bot_ironbreaker_revive_in_ult` owns it.
- **Better-revive** (`can_revive` + behaviour-tree edit) → overlaps gt's revive-priority / rescue-awaiting / ironbreaker-revive.
- **Heal-threshold dropdowns** → preference settings that no-op at default; the other/zealot ones hook `PlayerBotBase._select_ally_by_utility`, which gt already owns.

### Note
All migrated hooks are on distinct methods from `_gt_bot_fixes` (no duplicate-hook collision). **If you run the standalone "Bot Improvements - Combat Returns", disable it while this toggle is on** — both hook the same methods and would double-apply.

## v0.2.121-dev (2026-06-19) -- AI-takeover probe: hands-free auto-dump on death/respawn

The instrument-pass slot dump (`/gt_ai_slotdump`) now ALSO **auto-fires** — forced output, **no command and no Debug Logging needed** — on every death (`PlayerManager.relinquish_unit_ownership`) and every camera transition into `observer` (death) or `follow` (respawn). Just play Chaos Wastes normally; dying + respawning captures the full slot / camera-state / ownership cycle the takeover redesign needs, hands-free. Re-entrancy-guarded + pcall-wrapped (restores the debug gate even if the dump throws). Grep `[ai_slotdump:` in the console log.

## v0.2.120-dev (2026-06-19) -- Test-status: bots-rescue-awaiting-respawn confirmed

`[confirmed working]`: Bots rescue allies awaiting respawn (`gt_bot_rescue_awaiting`).

## v0.2.119-dev (2026-06-19) -- Test-status: flies disable confirmed

`[confirmed working]`: Fly disable multiplier (`gt_fly_disable_mult` — Halescourge/Nurgloth fly-swarm disable duration).

## v0.2.118-dev (2026-06-19) -- Split-bots spacing fix + "Bots always follow host" toggle

### Fixed
- **Split bots stood on top of you / blocked shots** (`gt_bot_split_among_players`): FIX 9 was overwriting each bot's `follow_position` with the leader's EXACT position (`POSITION_LOOKUP[human]`), clobbering vanilla's fanned-out spread destination (`ai_bot_group_system.lua:1115`, computed via `_find_points` with range 3 / 1-per-player spacing). Now it re-points only `follow_unit` and leaves vanilla's spaced follow-position intact, so bots keep a comfortable off-shot-line distance while still splitting per-player. (Workflow-diagnosed; `_gt_bot_fixes.lua` ~770.)

### Added
- **`gt_bot_follow_host` — "Bots always follow host"** (Bot Options, default off, `[untested]`): all bots leash to the host instead of spreading out / splitting. Routes through the same `_assign_destination_points` assignment and sets only `follow_unit`, so it inherits the spacing fix — no crowding the host or blocking shots. Takes **precedence** over `gt_bot_split_among_players` if both are on (precedence rather than a mutex avoids the VMF checkbox visual-refresh bug, `reference_vmf_checkbox_cached_display_state`). Bails to vanilla if the host has no live unit. Host-side only.

## v0.2.117-dev (2026-06-19) -- Bot ladder unstick confirmed; removed dev diagnostics

### Confirmed working
- **`gt_bot_ladder_unstick`** (+ its delay setting) is confirmed working in-game and relabeled `[confirmed working]` in the menu. Bots that hang at the foot/top of a ladder now get unstuck on the configured delay.

### Removed (dev diagnostics)
- **Auto-dump vanilla item names** (`gt_auto_name_dump` + the `_gt_name_dump` module). The self-refreshing loc_key->English console dump (and its `/gt_dump_names` force command) that fed `tools/gen-name-map` is gone — the menu checkbox, its loc keys, the `mod:dofile` load, and the feature file are all removed from the bundle. The feature file is preserved out-of-bundle at the mod root as `_gt_name_dump.lua.bak.v0.2.116`.
- **GC mitigation** (`gc_mitigation_enabled` + `gc_full_collect_sec`) and the **Lua memory watchdog** (`memwatch_interval`, plus the `/gt_mem` snapshot command). These leak-hunt instruments (added v0.2.77–v0.2.79 during the 2026-06-06 OOM investigation) are removed: the per-frame `_register_update` consumers, the widgets, and the loc keys are all gone.

## v0.2.116-dev (2026-06-19) -- AI takeover disabled + instrument pass for keep-slot redesign

### Disabled (pending rebuild)
**The convert-in-place AI takeover is disabled** behind a single module-level flag (`_AI_TAKEOVER_DISABLED = true`). It was producing **owner-less player units** (the client kept controlling a unit the host orphaned -> `owner_player` nil in the health extension), **host/client ownership desync** (reload-icon-on-wrong-portrait class), and a string of despawn-race crashes (0.2.113 AICommander, 0.2.114 whereabouts, 0.2.115 round-started). Root cause confirmed by a 4-agent research workflow (`wkcu0v4as`): the old code did only the HOST half of the swap (`player:despawn` host-side + `remove_peer_from_party` + `_add_bot_to_party`) and never told the CLIENT to relinquish its own unit -- and `RemotePlayer.despawn` is a host-side no-op, so the client's unit stayed live and owner-less.

Every takeover ENTRY point now bails before anything destructive runs -- `_ai_handle_toggle_change` (manual `/ai` + VMF checkbox), the `gt_ai_toggle_request` network handler (host receives client requests), the deferred host-self toggle consumer, and the AFK auto-takeover driver -- plus an innermost hard-stop guard inside `_ai_swap_human_to_bot` / `_ai_swap_bot_to_human` themselves, so **no `player:despawn` / `pm:remove_player` / `remove_peer_from_party` / `_add_bot_to_party` / `set_override_player` can execute** while disabled. User-initiated toggles echo `[gt] AI takeover is temporarily disabled while it's rebuilt (v0.2.116-dev).` once and revert the checkbox via the existing `_ai_suppress_setting_callback` path so it can't stick "on"; the per-frame AFK driver returns silently (no per-frame echo). The Group-F nil-guards (whereabouts / AICommander / RoundStartedSystem) and the position-keepalive are untouched and stay active.

### Added (debug-gated probes)
Instrument-only, behind the existing **Debug Logging** (`enable_debug_logging`) toggle; silent in normal play. These capture the vanilla dead/respawn/camera/slot machinery the rewrite will reuse, so the user can reproduce and we diagnose before mitigating:

- **`/gt_ai_slotdump`** chat command -- for every party slot, logs one parseable line with `slot_id` / `peer_id` / `local_player_id` / `is_bot` / `has_unit` / `unit_alive` / `spawn_state` / `health_state` (read from the slot's `player_status.game_mode_data`), plus per-party `num_used_slots` / `num_slots`, and the LOCAL player's live **camera state-machine state** (read off the player's separate `camera_follow_unit`, not `player_unit` -- that unit survives unit despawn, which is why the observer cam works with no controlled unit). Every lookup is nil-guarded (runs with units mid-teardown). The explicit command forces output even with Debug Logging off (mirrors `/gt_dump_ai`).
- **`hook_safe` on `CharacterStateHelper.change_camera_state`** -- logs `player name -> new camera state`, automatically capturing observer entry on death and the return to follow on respawn (bots early-return in vanilla, so they never log a real transition).
- **`hook_safe` on `PlayerManager.relinquish_unit_ownership`** -- logs the owning player + that `player_unit` was nulled (the clean relinquish the rewrite needs the CLIENT to perform on its OWN unit). Both new hooks were grep-verified against the file as the SOLE hook on their `(Class, method)` pair before registration (VMF duplicate-hook rule).

### The confirmed redesign (not implemented here)
Engine-native **keep-slot**: keep the human's Player + party slot intact, despawn ONLY the unit, push the client into the vanilla `observer` camera (the same flow every hero death uses), let a REAL host bot fill a FREE slot, and reclaim via the normal respawn handshake (`rpc_to_client_spawn_player`). This structurally eliminates the owner-less-unit crash, the portrait/reload-icon desync, and the player/peer churn -- all three were artifacts of doing only the host half and re-creating players. Hard constraint: a party has 4 slots, so the bot needs a FREE slot (refuse if the party is full). Adventure-only verified; full plan in research `wkcu0v4as`.

## v0.2.115-dev (2026-06-19) -- Crash fix: AI takeover round-started despawn race (third site)

### Fixed (crash)
**AI takeover crashed via the round-start check (GUID 6fac3e46):** `round_started_system.lua:111 (runtime): bad argument #3 to 'is_point_inside_volume' (userdata expected, got nil)`. Third site of the same despawn-race class (after 0.2.113 AICommander + 0.2.114 whereabouts). `RoundStartedSystem._players_left_start_area` iterates `self._units`, reads `pos = POSITION_LOOKUP[unit]` (`:117`), and feeds it to `Level.is_point_inside_volume(level, volume_name, pos)` (`:119`) with no nil-guard. A unit despawned mid-frame by the takeover (or a disconnect during the round-start window) is gone from `POSITION_LOOKUP` but lingers in `self._units` for a tick → nil pos → crash. Pre-guard: if any tracked unit lacks a position, bail the check this frame (`return false` = "round not started yet"); the despawned unit drops out within a tick and the next call runs vanilla normally — no premature round start.

> A background sweep is enumerating any remaining `POSITION_LOOKUP`-on-despawning-unit sites so the whole finite set can be guarded at once instead of one crash at a time.

## v0.2.114-dev (2026-06-19) -- Crash fix: AI takeover whereabouts despawn race (client) — companion to 0.2.113

### Fixed (crash)
**AI takeover crashed via the whereabouts extension (GUID 955c4549):** `player_whereabouts_extension.lua:200 (runtime): bad argument #2 to 'triangle_from_position' (userdata expected, got nil)`. This is a SECOND, distinct crash site from 0.2.113's AICommander `__add` fix — **same despawn-race cause, different vanilla extension**. `_ai_swap_human_to_bot`'s `player:despawn()` removes the unit from `POSITION_LOOKUP`, and `PlayerWhereaboutsExtension.update` ticks once more before teardown, reading `pos = POSITION_LOOKUP[unit]` (now nil) and feeding it to `GwNavQueries.triangle_from_position` (arg #2 requires userdata) → hard engine crash. Added a Group-F nil-guard on `PlayerWhereaboutsExtension.update` that bails when the unit has no position. One class covers local/husk/bot units.

Adversarially verified (4-agent workflow): the bot→human swap-BACK needs NO guard — `POSITION_LOOKUP[unit]` is written in `spawn_local_unit` (`unit_spawner.lua:302`) strictly before the extension's `init`/`_setup` runs (`:331`), so no nil window on respawn. With this + 0.2.113's AICommander guard, every per-frame nil-`POSITION_LOOKUP` surface in the takeover despawn path is closed on both host and client.

### IMPORTANT — every peer needs this build
The whereabouts crash fires inside the **client's OWN** extension on the client's about-to-be-despawned unit (which is why it surfaced "on client"). The guard runs on whichever machine runs gt_dev, so **every peer must run gt_dev v0.2.114-dev+**. 0.2.113's AICommander guard is host-side; this one protects the client — you need this build on BOTH machines.

## v0.2.113-dev (2026-06-19) -- CRITICAL: fix AI-Takeover host crash; remove broken Free Camera; test-status updates

### Fixed (CRITICAL host crash)
- **A client using AI Takeover hard-crashed the host** with `ai_commander_extension.lua: bad argument #1 to '__add' (userdata expected, got nil)` (host session a81cfea2, 2026-06-19). Root cause is a vanilla bug in `AICommanderExtension._update_units`: it reads `commander_unit_pos = POSITION_LOOKUP[self._unit]` then does `commander_unit_pos + avg_velocity` **without nil-checking the commander's own position** (it only guards the *controlled* unit's position a few lines later). AI Takeover despawns/recreates a player unit mid-frame (human→bot swap), leaving a commander unit with no `POSITION_LOOKUP` entry for a tick → the unguarded `+` fatals on the host. Fix: a symmetric nil-guard hook on `AICommanderExtension._update_units` that skips the tick until the commander has a position again (same behaviour vanilla already uses for the controlled unit). Always-on, host-side. The AI Takeover swap itself completes normally.

### Removed
- **Free Camera** (`freecam_enabled` toggle, `/freecam` command, the `FreeFlightManager._exit_free_flight` hook, all helpers + the localization/data entries) — it didn't work (player walked with the detached cam; later froze locomotion) and is removed for now. Noclip remains the working fly tool.

### Test-status
- `[confirmed working]`: **Unlock All Ranked Weaves** (`gt_unlock_all_weaves`) and **Disable Friendly Fire** (`disable_friendly_fire`) — both confirmed in-game.

## v0.2.112-dev (2026-06-19) -- Test-status: noclip confirmed

`[confirmed working]`: all noclip features (`noclip_enabled`, `noclip_speed`, `noclip_boost_multiplier`, `noclip_hotkey`).

## v0.2.111-dev (2026-06-19) -- Freecam crash fix + test-status confirmations

### Fixed (crash)
- **Free Camera crashed on activate** (GUID 12cb4bfd): `locomotion_templates_player.lua:368 attempt to call field 'run_func' (a nil value)`. `_freecam_freeze_player` disabled the player's locomotion via `set_disabled(freeze, nil, nil, true)` — but `PlayerUnitLocomotionExtension` adds disabled units to `all_disabled_units`, and `update_disabled_units` calls `extension.run_func(unit, dt, extension)` **every frame with no nil-check**. So `run_func=nil` crashed the next frame in the engine update loop (the `pcall` around `set_disabled` can't catch it — the crash is a frame later). Fix: pass a no-op `run_func` when freezing (keeps the player frozen in place without crashing).

### Test-status
- `[confirmed working]`: third-person camera + distance/height/side-offset/disable-zoom-in (`tp_camera_enabled`, `tp_distance`, `tp_height`, `tp_side_offset`, `tp_disable_zoom_in`); `gt_bot_instant_pickup`. `freecam_enabled` stays `[untested]` pending re-test of the fix above.

## v0.2.110-dev (2026-06-19) -- Test-status labels on all menu entries

Prefixed every VMF menu widget with `[untested]` so we know what's safe to promote to stable `gt`. Tooltips, group headers, dropdown options, and `enable_debug_logging` are not labeled. Two features the user confirmed in-game flipped to `[confirmed working]`: **Necromancer bots can hand off potions** (`gt_bot_necro_potion_handoff`) and **Ironbreaker bots revive during their ult** (`gt_bot_ironbreaker_revive_in_ult`). Flip the rest as verified. See `TESTING_STATUS.md`.

## v0.2.109-dev (2026-06-19) -- "AFK → AI takeover" toggle (per-client, input resumes control)

### Added
- **`gt_ai_afk_takeover`** (Bot Options, default off, per-client) — when on, 20 seconds of no input (keyboard / mouse / gamepad) hands your character to gt's AI takeover; the instant you give any input, you resume control. Per-client: each peer measures its own local input and drives only its own character (host on → host's char; client on → client's char), reusing the existing `ai_takeover_enabled` dispatch (host self-swap / client→host RPC). Manual `/ai` (or the manual checkbox) is NOT cancelled by input — only AFK-caused takeovers yield, tracked by an `_afk_took_over` discriminator flag.
  - **Input detection** uses `Managers.input.last_active_time` (the engine stamps it device-level on any press / non-cursor axis move, `input_manager.lua:769-770`) plus a raw `Keyboard`/`Mouse`/gamepad fallback — both independent of the player input controller, so they keep working while the local Player object is despawned during takeover. The `"cursor"` (absolute pointer) axis is excluded and a gamepad-stick deadzone applied so rest-drift doesn't count.
  - **Guards:** mode pre-gate (`_ai_can_swap_in_current_mode`, refused in Versus/keep), host-self-refusal cleared, a 0.25s re-arm grace after trigger/cancel so a held key can't flap the swap, and a full reset of the flag/timers in `on_game_state_changed`. Registered via `_register_update` (no new hook, no `mod.update` clobber).
  - **Note:** inherits the takeover swap's loadout reset — consumables/ammo don't persist across an AFK→return cycle.

## v0.2.108-dev (2026-06-19) -- "Unlock All Ranked Weaves" toggle

### Added
- **`gt_unlock_all_weaves`** (Gameplay, default off, client-side) — unlocks every ranked weave in the Winds of Magic ladder so the player can pick and play any weave without grinding the progression. New module `_gt_weave_unlock.lua` hooks `LevelUnlockUtils.weave_unlocked` (`level_unlock_settings.lua:490`) — the single gate every weave surface routes through (host weave picker `start_game_window_weave_list.lua:504`, selected-weave confirm `start_game_state_settings_overview.lua:132`, lobby-browser join `start_game_window_lobby_browser.lua:1229`, lobby-list entries `lobby_item_list.lua:580`), so one hook covers both hosting and joining. When on, returns `true` for any weave whose DLC the player **owns** — it replicates vanilla's own DLC gate (`:503-509`) so Winds of Magic ownership is still enforced (unlocks progression, never paid content; repo CLAUDE.md "DLC Ownership Gate"). Off → pure vanilla passthrough. Source-verified 2026-06-19; single-hook pre-flight confirmed gt had 0 prior hooks on `weave_unlocked`.

## v0.2.107-dev (2026-06-19) -- "Split bots among players" toggle (one bot per human)

### Added
- **`gt_bot_split_among_players`** (Bot Options, default off, host-side) — distributes bots one-per-human instead of every bot piling onto a single player. 2 players + 2 bots → one bot follows the host, the other the client; 3 players + 1 bot → that bot follows the host (round-robin, host first, when bots outnumber humans). Implemented as FIX 9 — a `hook_safe` on `AIBotGroupSystem._assign_destination_points` (the single per-frame chokepoint where each bot's `data.follow_unit` is written, `ai_bot_group_system.lua:1085`/`:1117-1123`); we stamp last so we override both the engine's scalar "all bots on one human" write AND the ~20s stand-still re-targeting (`AFK_TIME_LIMIT = 20`, `:652`) — a bot stays on its assigned human even when that human is idle. Filters to real humans (`Managers.player:human_players()`, not `side.PLAYER_UNITS` which includes bots), skips vortex/disabled targets, respects parked (hold-position) bots, and re-validates with `HEALTH_ALIVE` each frame so a dead/left human never strands a bot. Deterministic `tostring`-keyed sort so the mapping doesn't oscillate. Composition: follow target ≠ aid target, so the revive/rescue-priority toggles (FIX 3/3b) still preempt follow — a bot assigned to the client still breaks off to revive the host, then returns. FIX 5/7 read the same `follow_unit`, so ladder-unstick + leash retarget to each bot's assigned human.

## v0.2.106-dev (2026-06-19) -- Bot revive-priority + rescue-priority toggles

### Added
Two Bot Options checkboxes (default off, host-side) that make aiding a downed/disabled ally the bot's top priority, ignoring the snap-back leash. Folded into the existing `PlayerBotBase._select_ally_by_utility` wrapper (FIX 3) — no second hook.
- **`gt_bot_revive_priority`** — force-selects the nearest **pathable** knocked-down ally as the top-priority aid target, so the bot leaves the group and walks the whole way to revive.
- **`gt_bot_rescue_priority`** — same for the **rescue** states (`get_is_ledge_hanging` and `is_hanging_from_hook`).
- With both on, bots leave the team the moment a path to the downed player exists. The picker already credits a downed ally `utility=200` (a 200m closeness handicap, no max-aid-distance cap, `player_bot_base.lua:991/909-917`), and FIX 7's leash already exempts a bot once `target_ally_need_type` is set — so the toggles just make the *choice* explicit and distance-independent. Guards: mandatory engine `_ally_path_allowed` gate (no stranding on unreachable allies), 3m sticky-target hysteresis (no flip-flop), position nil-guards. Composes with FIX 3 (awaiting-respawn rescue) and the Ironbreaker ult-yield (which already keys on these need_types).

## v0.2.105-dev (2026-06-18) -- Fix bot snap-back distance (slider dead-band)

### Fixed
- **Bot follow snap-back distance (`gt_bot_follow_distance_m`) appeared to do nothing.** Verified against the decompile: the `BTConditions.should_teleport` hook (FIX 7) is a faithful, live mirror of vanilla and the teleport action has no second distance gate, so the mechanism is sound. The real bug was a **slider dead-band**: the slider ranged `{10, 50}` with a default of `40`, but FIX 7 treats **any value ≥ 40 as a no-op** (40 is vanilla's own leash). So the entire 40–50 half of the slider — and the default — did nothing; enabling the feature and leaving the slider at/above 40 (or raising it toward 50 expecting a *sooner* leash) was silently inert. **Fix:** slider now ranges `{10, 40}` with `default = 20`, so enabling it has visible effect and no value is in a dead band. Tooltip rewritten (40 = max/vanilla, ~15–20m practical floor, host-side only).
- Added debug-gated logging (`[gt:bot-leash] should_teleport TRUE …` + a `BTBotTeleportToAllyAction.run` confirmation) so a log can verify the leash firing + the actual teleport, in case of a host-authority or BT-priority edge.

### Note
- Did **not** add a teleport cooldown: vanilla's `has_teleported` latch (one snap per follow-state entry, re-armed in `BTBotFollowAction.enter`) is already the anti-thrash mechanism and FIX 7 honors it. This is also why a very tight distance can "rarely catch" — the bot snaps once, lands ~5m behind, and won't re-snap until it re-enters follow.

## v0.2.104-dev (2026-06-18) -- Block in-mission inventory in Chaos Wastes + fix auto-skip blackscreen fade

### Changed
- **In-mission inventory is now Adventure-EXCLUSIVE — fully blocked in Chaos Wastes** (hub AND mission). Opening the hero view or changing items/talents during a CW run crashes (CW is loadout-locked via the deus boon system). A 2026-05-25 change had narrowed the block to the CW *hub* only, on the assumption cim's mid-mission fix made the mission case safe — it still crashes, so this reverses that: `gt_open_mission_inventory` (the `/gt_inv` command + `gt_open_inv_hotkey` keybind) now bails on `mech == "deus"`; `_patch_inventory_access` never grants `modes.deus` loadout access and doesn't add the in-mission "Open Inventory" ESC-menu button while in a CW run.

### Fixed
- **Auto-skip cutscenes showed a blackscreen fade in/out in Chaos Wastes.** The v0.2.102 CW auto-skip path stopped setting `_skip_next_fade` (to avoid touching author-locked boss cinematics), so the fades that bracket an ordinary CW cutscene were no longer swallowed. Now both the activation hook (fade-IN) and the deferred processor (fade-OUT) set `_skip_next_fade` **when the cutscene will actually skip** (`script_data.skippable_cutscenes` true after the optional force-unlock) — so auto-skipped cutscenes are clean again, while an author-locked CW boss cinematic (read as not-skippable) keeps its own fade untouched.

## v0.2.103-dev (2026-06-18) -- HOTFIX: score-screen crash (nil hero in experience lookup) after host /gt_win

### Fixed (crash)
- **The v0.2.101 score-screen fix exposed a second nil-profile crash INSIDE the score screen** (GUID `f32490ac`: `backend_interface_hero_attributes_playfab.lua:93: attempt to concatenate local 'hero' (a nil value)`). The client's profile reservation races to nil/0 after a host `/gt_win`, and vanilla reads it in **two** end-of-level places — `_award_end_of_level_rewards` (`:768`, which v0.2.101 shimmed) **and** `_setup_end_of_level_UI` (`:266-280`), which runs *later* (after the shim was restored). The latter left `level_end_view_context.local_player_hero_name = nil` → `EndViewStateSummary._hero_name = nil` → `get_experience(nil)` → `BackendInterfaceHeroAttributes.get` → `nil .. "_experience"` crash. **Fix:** replaced the temporary shim with a **permanent fallback hook on `ProfileSynchronizer.get_persistent_profile_index_reservation`** — when the reservation is stale for our own peer, it returns the local player's real profile (which survives the race). This resolves a real hero for **every** end-of-level consumer (reward + score-screen UI + experience), not just the reward. Healthy reservations pass through untouched; the override only fires when the reservation is nil/0 and we have a valid local profile, so it's semantically correct and client-local (no host desync). The `_award_end_of_level_rewards` hook is now just a last-resort pcall net.

## v0.2.102-dev (2026-06-18) -- Auto-skip cutscenes again in Chaos Wastes (without desyncing boss cinematics)

### Fixed
- **Auto-skip cutscenes stopped auto-skipping in Chaos Wastes runs.** The v0.2.95 Nurgloth fix disabled auto-skip for the *entire* deus run to avoid desyncing author-locked boss cinematics — too broad: it also killed auto-skip for ordinary CW cutscenes like the `forest_ambush_belakor_path1` path intro (`cs_01_skip`), which is author-*skippable* (manual spacebar worked; auto-skip didn't). **Fix:** auto-skip now runs in CW too, but as a plain "auto-press skip" — it defers to vanilla `skip_pressed` **without** force-unlocking, so the engine's own `script_data.skippable_cutscenes` check decides: author-skippable CW cutscenes auto-skip, while author-locked boss/phase cinematics (Nurgloth on Enchanter's Lair) are still left alone (skipping them desyncs the fight). Outside CW it force-unlocks + skips everything, exactly as before. With Debug Logging on, the deferred-skip log now shows `force_unlock=false` in CW vs `true` elsewhere.

## v0.2.101-dev (2026-06-18) -- Fix: client sees the score screen after host /gt_win (was black-loading to keep)

### Fixed
- **A client got no end-of-level score screen after the host force-won via `/gt_win`** — it black-loaded straight back to the keep. The v0.2.89 crash guard prevented a vanilla nil-profile crash by **skipping the entire `_award_end_of_level_rewards`**, but that function is what sets `self.chests_package_name` (`state_ingame_running.lua:785`) and flips `self.rewards:rewards_generated()` true (`:778`) — **both required terms of the `rewards_ready` gate** that `StateInGameRunning.update` checks before calling `_setup_end_of_level_UI` (the results view). Skipping it starved the gate, so the screen never built. **Fix:** instead of skipping, when the client's profile reservation races to nil/0, resolve the client's *real* profile from the cached local-player object (`BulldozerPlayer:profile_index()`, which survives the race), temporarily shim `get_persistent_profile_index_reservation` so vanilla's internal read resolves, and run the **full** vanilla body (building the score screen) — then always restore. Healthy reservations run untouched vanilla; a genuinely-unresolvable profile still falls back to the old safe skip (crash avoidance). Single hook preserved, client-local (no host desync).

## v0.2.100-dev (2026-06-18) -- "Prioritize Specials" targeting toggles (tag / Deepwood Staff / Soulstealer)

### Added (new module `_gt_prioritize_specials.lua`)
Three independent, **default-OFF, client-side** toggles that bias a target picker toward `breed.special` enemies in your aim direction. All are per-local-player (no host install, no RPC, no version-sync) — they only change what *your* tag/shot points at. Every hook body is pcall-guarded (degrades to vanilla, never crashes); each is a single clean hook (pre-flight grep confirmed no existing gt hooks on these methods).
- **Prioritize Specials When Tagging** (`gt_prio_special_tag`) — hooks `ContextAwarePingExtension._check_raycast`. Re-walks the same tag ray; if an alive enemy Special is on it, tags that Special even when it's behind an elite or a pickup/item the crosshair is directly on.
- **Prioritize Specials — Deepwood Staff** (`gt_prio_special_deepwood`) — hooks `PlayerUnitSmartTargetingExtension.update_opt2` (the Deepwood seeking bolt is aim-assist smart-targeting, not trueflight). Gated to the wielded `staff_life`; after the vanilla pick, if it isn't a Special, redirects `targeting_data` to an alive enemy Special inside the ~36° aim cone (broadphase), else leaves vanilla aim.
- **Prioritize Specials — Soulstealer Staff** (`gt_prio_special_soulstealer`) — hooks `ActionTrueFlightBowAim.client_owner_post_update`. Gated to the wielded `staff_death` (so it does NOT also bias Kerillian's shared trueflight career class); overlays the action's `prioritized_breeds` with a metatable that gives any `breed.special` a high priority for the call, so a Special on the aim ray outranks a closer non-Special. Restores the table after.

### To verify (in-game, helpers)
Enable each toggle and confirm: tagging prefers specials behind elites; Deepwood bolt curves to an in-cone special; Soulstealer locks specials first; and each is inert when its weapon isn't wielded / the toggle is off. (Default-off, so zero behavior change until enabled.)

## v0.2.99-dev (2026-06-18) -- Clients can use gt_win / gt_fail / gt_restart

### Changed
- **`/gt_win`, `/gt_fail`, `/gt_restart` are now client-usable.** Level control is host-authoritative (`GameModeManager:complete_level/fail_level/retry_level` assert `is_server`), so previously a client got "Only the host can…". Now a client **requests** the action via a `gt_level_control` RPC and the host performs it for the lobby — mirroring the existing `gt_respawn` client→host pattern (VMF re-handshake + resolve the real host peer via `Managers.mechanism:server_peer_id()`, not the literal `"server"` recipient). The host still runs the command directly. Refactored the three commands onto one executor (`_gt_host_exec_level_control`) + one request helper; the host-only gate is gone. Any peer can trigger it (no extra permission gate — fine for co-op testing; a host opt-out toggle can be added later). Host logs `[gt:level-control-rpc] from=… verb=…`.

## v0.2.98-dev (2026-06-18) -- Fall damage multiplier slider (0–5x)

### Added
- **Fall damage multiplier** (`gt_fall_damage_enabled` checkbox + `gt_fall_damage_mult` slider, in the Buffs group). Slider range **0–5, default 1.0**: `1` = vanilla, `0` = no fall damage, up to `5` = 5× (tall falls become lethal). Off by default; the slider only applies while the checkbox is on.
  - **How:** fall damage is host-authoritative — `HealthSystem.rpc_take_falling_damage` computes `clamp(delta * FALL_DAMAGE_MULTIPLIER, max_health*MIN_%, max_health*MAX_%)` from `PlayerUnitMovementSettings.fall.heights` (vanilla `14 / 0 / 1`; `health_system.lua:657-664`). Scaling all three fields by the multiplier scales the clamped result linearly. We do **not** touch `MIN_FALL_DAMAGE_HEIGHT` (the client-side trigger threshold), so the same falls still register — only the dealt amount changes.
  - **Per-unit clones handled:** the engine deep-clones `PlayerUnitMovementSettings` per unit at spawn (`register_unit` → recursive `table.clone`), so `gt_apply_fall_damage` rewrites the base table **and** every live per-unit snapshot via the same `debug.getupvalue(unregister_unit, 1)` trick as the movement-speed slider. Vanilla values captured once → re-applies recompute from vanilla (no compounding); disabling or setting `1.0` restores vanilla.
  - **Host-side:** the host applies fall damage for everyone, so the host's value governs the whole lobby. Per-session (game restart restores vanilla).

### Tests
- `_rt_register("fall_damage_widgets_and_scaling")` — both widgets exist, the apply fn is callable, a standalone math probe confirms `m=0 → 0` and linearity (`fall_dmg(2) == 2·fall_dmg(1)`), and re-applying leaves a non-negative numeric multiplier.

## v0.2.97-dev (2026-06-18) -- Migrate "Straight to Keep & Quit Game" into gt (Main Menu / Startup)

### Added
- New **Main Menu / Startup** settings group reimplementing the two behaviours of the "Straight to Keep & Quit Game" Workshop mod (internal id "Goodbye Menu", by Amia) as independent gt toggles, both **default OFF**:
  - **Skip start screen (straight to the keep)** (`gt_skip_start_screen`) — bypasses the "press any key" start/title screen on launch so you land at the main menu (keep hub) directly. Sets `GameSettingsDevelopment.skip_start_screen` (read by `state_title_screen` / `state_splash_screen` / `state_ingame` during boot, so it takes effect on the **next launch**). Captures and restores the vanilla value.
  - **"Return to Main Menu" quits to desktop** (`gt_return_to_menu_quits`) — remaps the in-game ESC menu's `return_to_title_screen` (and its confirm-action `do_return_to_title_screen`) transitions to `quit_game` (`scripts/ui/views/ingame_ui_settings.lua:70/104/291`), so that menu entry exits to desktop instead — still behind the vanilla exit-confirmation popup. Applies live, captures originals, and restores on toggle-off **and** on mod-disable.
- **`/gt_quit`** — instant quit to desktop (no confirmation), via the engine's own `Application.quit()`. On-theme bonus with the migration.

### Why
User request: decompile the "Straight to the Keep and Quit Game" Workshop mod (3214214805) and migrate its features into General Tweaker. The original applies both changes unconditionally at load; gt exposes each as its own opt-in toggle with capture/restore. These are plain engine-data reassignments (not hooks), so there's no VMF duplicate-hook concern. The decompiled reference lives at `misc-vermintide-mods/_scratch/3214214805/`.

### Tests
- `_rt_register("menu_qol_settings_registered")` — both new checkboxes exist in the widget tree.
- `_rt_register("menu_qol_return_quits_roundtrips")` — `_gt_apply_return_quits(true)` remaps the return-to-title transitions to `quit_game` and `(false)` restores the originals (skips cleanly when the transitions table isn't loaded yet).

## v0.2.96-dev (2026-06-18) -- Fix Choose Grail Knight Quests dropdowns showing `<<<...>>>`

### Why
Workshop report (Level12Lobster): "Choose Grail Knight Quests have `<<< Quest Name >>>` on all the text." Root cause is the repo's known `vmf-dropdown-options-mutated` bug class: all three quest dropdowns (`gt_gk_quest1/2/3`) shared one `GT_GK_QUEST_OPTIONS` table. VMF's `localize_dropdown_data` mutates each option's `text` **in place** (`option.text = mod:localize(option.text)`), so the 2nd dropdown localized the already-localized strings and the 3rd localized those again — each pass through the missing-key fallback adds an angle-bracket pair, producing the `<<...>>` / `<<<...>>>` cascade. The option `text` values were also plain English ("Random (vanilla)") rather than loc keys.

### Fixed
- **Choose Grail Knight Quests dropdowns no longer render `<<<...>>>`.** Replaced the shared `GT_GK_QUEST_OPTIONS` table with a `_gt_gk_quest_options()` factory that returns a **fresh** table for each of the three dropdowns, so VMF mutates a distinct table per dropdown (no cross-dropdown re-localization). Option `text` is now a real loc key (`gt_gk_opt_*`, defined in `general_tweaker_dev_localization`) that resolves to the display name instead of falling through the `<...>` missing-key fallback. Matches the crt `_talent_swap_options()` / enemy_tweaker dropdown-factory fix for the same bug class.

### Tests
- New `_rt_register("gk_quest_dropdowns_dont_share_options")` — walks the data tree and fails if any two of the three quest dropdowns share an options-table identity, or if option `text` isn't a bare loc key (contains a space/period). Pins the fix so a future refactor can't silently re-share the table.

### Notes (stable-gt feedback also addressed in dev already)
The same Workshop comment thread reported two items that **dev already carries** and that will reach players on the next stable (`gt`) promotion: (1) "No bots toggle doesn't remove bots mid-mission" — dev's `gt_no_bots` ("Disable Bots (Solo)") sets `script_data.ai_bots_disabled`, which `_handle_bots` re-reads each server tick to despawn existing bots and block refill (the old `/gt_bottoggle` → `no_bots_allowed` path can't despawn mid-mission); it's persistent and re-applied on every mission start, so leaving it on also gives a bot-free party from the first frame (the requested "disable by default" / true-solo behaviour). (2) "More Corpses should default to 24 not 100" — dev's `gt_more_corpses_count` default is already 24.

## v0.2.95-dev (2026-06-18) -- Cutscene-skip no longer breaks Chaos Wastes bosses (Nurgloth / Belakor)

### Why
Reported + corrected from user testing: with cutscene-skip on, **Nurgloth on Enchanter's Lair skipped to his final phase and deadlocked.** I was wrong to clear gt earlier — a prior subagent grepped the *breed* code and found no cutscene, but the boss's intro/phase cinematic lives in the **level flow** (the Enchanter's Lair bundle), not the decompiled breed scripts. Traced through source: `CutsceneSystem.skip_pressed` fires the cutscene's `event_on_skip` **level-flow event** early (`cutscene_system.lua:97-105`), and on a boss level that flow event drives the boss's phase/state — so skipping it (especially gt's auto-skip, which fires without the player choosing, AND gt's force-unlock of the author "non-skippable" lock that boss cutscenes carry on purpose) jumps the boss ahead and deadlocks the fight.

### Fixed
- New `_gt_in_deus()` gate (detects a CW run via the deus run controller). In a CW run, gt now **does not auto-skip** cutscenes and **does not force-unlock** author-locked ones — so boss intro/phase cinematics play normally. Outside CW (regular Adventure, etc.) cutscene-skip is unchanged. Author-*skippable* cutscenes can still be skipped manually in CW via vanilla ESC; only the auto-skip and the unskippable-override are disabled there. The `[gt:cutscene]` activation log is kept (and its stale "boss has no cutscene" comment corrected). -- /gt_respawn command (force yourself back in when dead or awaiting rescue)

### Added
- **`/gt_respawn`** -- forces you back into the game when you're DEAD (in the respawn queue) or AWAITING RESCUE (hanging at a beacon). Respawn is server-authoritative, so: as host it runs directly; as **client** it sends a request to the host (re-handshakes VMF first via `ping_vmf_users`, then sends to the resolved `Managers.mechanism:server_peer_id()` -- so it works for you even when nicho hosts). Awaiting-rescue -> `StatusUtils.set_respawned_network(unit, true, helper)` (the same call the assisted_respawn interaction makes); dead/queued -> zeroes *your* `respawn_timer` so the host's `RespawnHandler.server_update` spawns you next pass (per-player, not the whole team). If a client send doesn't land first try (host link just re-synced), run it again. EXPERIMENTAL -- verify in-game. -- Diagnostics: Nurgloth cutscene logging + burning-enemy fire-opacity probe

### Added (diagnostics / probe)
- **Nurgloth / Enchanter's Lair cutscene logging** (`[gt:cutscene]`, ungated). The existing `CutsceneSystem.flow_cb_activate_cutscene_logic` hook now logs every cutscene activation (`on_activate` / `on_skip` event names + level + whether auto-skip is on), and the deferred auto-skip processor logs when it fires. Source proves the Drachenfels boss is BT/animation-driven (no `CutsceneSystem` cutscene in its code), so if **no** `[gt:cutscene]` line appears on Enchanter's Lair near the boss, gt's cutscene-skip is conclusively not the cause of the boss skipping to final phase / deadlocking — it's a vanilla CW AI desync. Quick test regardless: host turns OFF *Auto-skip cutscenes* and re-runs.
- **Burning-enemy fire-opacity probe** (`/gt_fire_probe <cloud> <variable> <value>`). Wraps the `burning` StatusEffect's `on_applied` (and its balefire/elven/warpfire/death variants) to capture the live fire particle ids, and the command pushes `World.set_particles_material_scalar` to every burning enemy so we can discover which material variable controls the fire's opacity (the source only names a color-*tint* variable). Light an enemy on fire, try candidates (e.g. `/gt_fire_probe fire intensity 0.2`), watch which dims the flames — then the real 0–100% opacity slider gets wired to that variable. Client-side/visual only.

## v0.2.92-dev (2026-06-18) -- Adventure save-item trait chance slider (moved here from Chaos Wastes Tweaker)

### Added
- **Adventure save-item trait chance (percent)** (`gt_adventure_save_trait_chance`, in the Gameplay group; slider 1–75, default 25 = vanilla). Sets the proc chance of the Adventure charm traits Home Brewer / Healers Touch / Grenadier (the chance to NOT consume the potion / healing item / grenade), via `WeaponTraits.buff_templates.{trait_ring_not_consume_potion, trait_necklace_not_consume_healing, trait_trinket_not_consume_grenade}.buffs[1].proc_chance` (vanilla 0.25; `weapon_traits.lua:69/84/104`). Absolute load-time data mutation re-applied on setting change; each peer applies its own value to its own data (no host-sync). Adventure-only — Chaos Wastes boons are a separate system and are untouched. **This was mistakenly added to Chaos Wastes Tweaker in ct v0.7.140; it's removed from ct (v0.7.141) and lives here now**, since it's not a CW feature.

## v0.2.91-dev (2026-06-18) -- Godmode: stop it affecting bots + make client godmode actually reach the host; log /gt_win

### Fixed
- **REGRESSION: host godmode made the host's BOTS invincible.** The v0.2.89 MP godmode check (`_gt_godmode_active`) keyed off a unit's owning peer, but bots are owned by the HOST's peer_id -- so with the host's godmode on, every host bot read as god-moded and took no damage. Now gated on `owner:is_player_controlled()` (true for humans, false for bots), so godmode only ever affects actual players.
- **Client godmode was ignored by the host.** Damage to a player is applied on the host; a client's godmode is only honored if its broadcast reaches the host. It wasn't: VMF silently drops the host from a client's `_vmf_users` when the host's bots churn at mission load (VMF_RECIPES §3a, the same bug that bit gt's AI-RPC in v0.2.52). Fix: the godmode broadcast now calls `get_mod("VMF").ping_vmf_users()` to re-handshake before sending, exactly like gt's AI-RPC path. The 3s heartbeat in `mod.update` re-handshakes + resends so it converges within a few seconds even if the first send races the async pong.
- **Godmode-off now expires reliably.** Synced peers are stored with a timestamp and expire after ~9s without a heartbeat, so turning godmode off (or disconnecting) can't leave a remote player stuck invincible even if the explicit "off" send is lost.

### Added
- **`/gt_win` `/gt_fail` `/gt_restart` now log + echo when used** (host). Previously they ran silently, so a force-win was invisible in the console log. The host's log now records `[gt:level-control] /gt_win -> ...complete_level()`.

### Notes (no code change)
- **A reported "/gt_win stuck me on a loading screen" was diagnosed as NOT a gt bug.** Log analysis (2026-06-18): the host force-won, everyone loaded into the victory keep fine, then the HOST quit the game ~70s later -> the client got `remote_disconnected` -> vanilla host-migration hung on its load. That host-migration screen is the "stuck loading", caused by the host closing the game, not by `complete_level`.
- **Fly-disable duration is already host-authoritative lobby-wide** (verified): the boss runs on the host and the fly cloud's lifetime is set from the host's `BreedActions` / `TrueFlightTemplates` data, so the host's value governs every player; clients never read their own value for it. No sync needed.

## v0.2.90-dev (2026-06-18) -- Show the hero-view tab strip in-mission (Inventory/Talents/Cosmetics)

All source citations verified against the decompiled vanilla source 2026-06-18.

### Why
Reported: opening the inventory mid-mission showed NO clickable tabs up top -- you couldn't switch to Talents/Cosmetics. Root cause (verified): on PC, when Options -> "Use PC menu layout" is OFF (the default), the hero view renders the console-style "new GUI" tab strip `HeroWindowPanelConsole`, which **hides and input-disables the entire tab strip in a mission** -- both its draw (`hero_window_panel_console.lua:496`) and its title-button input loop (`:360`) are gated on `self.is_in_inn` (false mid-mission), and `on_enter`'s else-branch (`:87-95`) skips the strip's `_setup_text_buttons_width` / `_setup_input_buttons`. Only system/back/close remain.

### Added
- **"Show menu tabs in-mission (Inventory/Talents/Cosmetics)"** (`gt_mission_menu_tabs`, default OFF, under the Mission Inventory group). New `mod:hook_safe("HeroWindowPanelConsole", "on_enter", ...)` (pre-flight: no prior hook on that class). Mid-mission, when the toggle is on, it flips the instance's `is_in_inn` to true so the strip's setup/draw/input branches run, calls the two setup methods vanilla skipped, and parks `_sync_delay` far in the future so `_sync_news` never runs its keep-leaning news work (the "new" badges just don't refresh; tabs still draw + click). The title-button widgets are always built in `create_ui_elements` (`:132-150`) regardless of `is_in_inn`, so nothing needs re-creating.
  - **Forge tab gated** OFF unless `cim` is loaded -- its item-customization sub-path is the `levels/ui_store_preview/world` crash already guarded by the existing `HeroWindowLoadoutConsole._customize_item` hook (belt-and-suspenders). Loot is not a tab on this strip.
  - **PC console-layout only.** With "Use PC menu layout" ON (`HeroWindowOptions`), the strip already draws in-mission, so that layout needs nothing here.
  - **Caveat:** changing a talent mid-mission applies to your live character immediately (vanilla behavior).

### To verify (in-game)
- Enable the toggle, open `/gt_inv` in a mission: the top tabs (Inventory / Talents / Cosmetics) now render and switch. Forge is greyed unless Crafting in Modded is loaded.

## v0.2.89-dev (2026-06-18) -- Bots rescue awaiting-respawn allies (real fix); MP godmode; gt_win host-gate + results-crash guard

All source citations verified against the decompiled vanilla source 2026-06-18.

### Why
Four issues reported from live MP play (danjo client in nicho's lobby, 2026-06-18):
1. **Bots never rescue allies awaiting (assisted) respawn**, even with the toggle ON for the host. The v0.2.84-dev "rescue trick" was correct *downstream* but scanned the wrong roster.
2. **Godmode doesn't make a CLIENT invincible** (works only when hosting/solo).
3. **The host force-winning via `/gt_win` crashed a client** at the results screen.
4. (`/gt_win` itself was also unguarded for clients.)

### Fixed
- **Bots rescue awaiting-respawn allies (`_gt_bot_fixes.lua`)** — ROOT CAUSE: the FIX 3 wrapper iterated `side.PLAYER_AND_BOT_UNITS`, but `SideManager._update_frame_tables` rebuilds that list every frame and only keeps units where `is_valid(unit)` is true, and `is_valid` (`side_manager.lua:338-339`) is `unit_alive(unit) and not status:is_ready_for_assisted_respawn()` — so an awaiting-rescue ally is **always filtered out** of that list. The wrapper saw `considered = 0` forever and never rescued anyone. Fix: iterate the **unfiltered** `side:player_units()` (`side.lua:222`, the raw `_player_units` roster, which keeps the awaiting unit). The per-candidate gates (ready / health-alive / aid-path) are unchanged, so only a genuine awaiting+reachable ally is picked, then relabeled `knocked_down` so the existing revive branch drives the contextual `assisted_respawn` interaction. Added a nil-guard on the candidate position (a just-spawned remote awaiting unit can briefly lack a `POSITION_LOOKUP` entry).
- **Extra rescue logging (`enable_debug_logging`)** — a throttled `[gt:bot-rescue] scan roster=N` heartbeat (proves the wrapper runs and shows the roster size, fires even when nothing is found), a per-candidate line (`ready / health_alive / aid_path / has_pos`), the existing summary, and a `[gt:bot-rescue] RESCUE picked …` line at the relabel. A future repro now shows exactly where the path stops.
- **Godmode multiplayer sync (`general_tweaker_dev.lua`)** — damage to a player is applied on whatever machine is authoritative for that unit (the HOST for a client's unit), where the old hook saw a remote unit and `_is_local_player_unit()` was false — so a client took full damage. Now each peer broadcasts its godmode state (`gt_godmode_state` VMF event, schema-validated) and the HP-damage hooks (`DamageUtils.add_damage_network` / `add_damage_network_player`) block damage to any unit whose **owning peer** has godmode on (`_gt_godmode_active`). Fire-and-forget + pcall-guarded; VMF drops the event for non-gt / older-gt peers, so no mixed-lobby crash, and host-self still works via the local fast path even if the broadcast fails (no regression). A throttled rebroadcast (~3s while godmode is on) self-heals against a dropped client→host send before the VMF handshake settles. Both peers in a lobby need this build for a client's godmode to be honored.
- **`/gt_win` `/gt_fail` `/gt_restart` host-only gate** — `complete_level`/`fail_level`/`retry_level` are server-authoritative (only the host runs `GameModeManager.server_update` → `evaluate_end_conditions`, `state_ingame.lua:982-983`; the engine's own `flow_callback_complete_level` guards with `if Managers.player.is_server`). A client calling them set a flag nothing reads and fired `trigger_end_level_area_events` out of band → client-side flow desync/crash. Now gated to the host with a friendly echo (`_gt_host_only_level_control`).
- **Results-screen crash guard** — `StateInGameRunning._award_end_of_level_rewards` reads `SPProfiles[profile_synchronizer:get_persistent_profile_index_reservation(peer_id)].display_name`; when a level ends abruptly (host force-win, or any race) the local peer's reservation can come back `0`/nil → `SPProfiles[0]` nil → vanilla crash at the results screen (exactly what killed danjo as a client). New guard hook skips the reward award (which doesn't persist on modded realm) when the profile won't resolve, instead of crashing. Strict no-op when the profile is valid.

### Also
- **Clarified the fly-disable label/tooltip** (`gt_fly_disable_mult`, no behavior change) — it's a MULTIPLIER (× vanilla), not seconds: 1.0 = vanilla (Halescourge missile 10s / Nurgloth swarm 8s), 0.5 = half, 0 = near-instant. Tooltip now spells out that it's host-only (the boss runs on the host, so only the host's value applies), that the two attacks have different baselines (so one multiplier can't set both to an exact second count), and that the cloud is finite/killable regardless.

### To verify (in-game)
- Host with the **Bots rescue allies awaiting respawn** toggle ON: let a human die and reach the awaiting-respawn (hanging) state; a bot should path over and free them. With `enable_debug_logging` on, watch for `[gt:bot-rescue] scan roster=…` then `RESCUE picked awaiting ally`.
- As a CLIENT in a lobby where the host also runs v0.2.89-dev, toggle godmode and take a hit — no damage.
- As a CLIENT, `/gt_win` now echoes "Only the host can complete the level." As host, `/gt_win` completes as before and the client no longer crashes at results.

## v0.2.88-dev (2026-06-17) -- Solo & QoL: port of True Solo QoL Tweaks (error-free)

### Why
Reimplement the useful features of the third-party "True Solo QoL Tweaks" (workshop 1384087820, last updated 2021) as native gt toggles, so it can be dropped. Bonus: the original logs a CareerSettings error every launch (it indexes `career.activated_ability.ability_class` with no nil-check; VT2's Versus entries `vs_undecided`/`spectator` have no `activated_ability`). This port fixes that with a proper nil-guard. New file `_gt_solo_qol.lua`; new "Solo & QoL (from True Solo)" group, all toggles default OFF; Penlight dependency dropped (plain string fns).

### Added (toggles)
- **Auto-restart mission on team wipe** (`gt_solo_auto_restart_on_wipe`) — on a "lost" end-condition, return `"reload"` instead of going to the keep. `/gt_inn` bails to the keep manually.
- **Assassin / Packmaster spawn text warnings** (`gt_solo_assassin_text_warning`, `gt_solo_packmaster_text_warning`) — colored ASS!/PACK! count callout in the area-indicator banner. The spawn detector is **merged into the existing `ConflictDirector.spawn_queued_unit` hook** (no duplicate) via `mod._gt_solo_on_spawn_queued`; also hooks `Localize` / `PlayerHud.set_current_location` / `AreaIndicatorUI.update`.
- **Assassin/Packmaster hero voice callout** (`gt_solo_assassin_hero_vo`) — forces the hero's "I hear a Gutter Runner" / "I see a Skaven slaver" line on spawn.
- **Disable ult voice line** (`gt_solo_disable_ult_vo`) — the crash-fixed feature. Loops `CareerSettings` with `local aa = career.activated_ability; if aa and aa.ability_class …` (the nil-guard), de-dupes shared ability classes, skips `empire_soldier_tutorial`.
- **Disable mutator death explosions** (`gt_solo_disable_mutator_explosions`), **disable level intro audio** (`gt_solo_disable_intro_audio`), **disable fog** (`gt_solo_disable_fog`), **disable sun shadows** (`gt_solo_disable_sun_shadows`).
- **Draw boss-event spheres** (`gt_solo_draw_boss_spheres`) + **boss path progress** (`gt_solo_boss_path_progress`, StreamingInfo-guarded) — share one `EnemyRecycler.update` hook; sphere LineObject recreated on world change (no stale handle, no `on_game_state_changed` clobber).

### Not ported
- **AUTO_KILL_BOTS** — gt already has "Disable Bots (Solo)" (`gt_no_bots`).

### Notes
Pre-flight confirmed the only existing-hook collision was `ConflictDirector.spawn_queued_unit` (merged). All other hooks are fresh `(Class, method)` pairs. All feature bodies are pcall-guarded and gate on their toggle (no cost when off).

## v0.2.87-dev (2026-06-17) -- Fly-disable tweak corrected to cover BOTH bosses + both attack paths

Correction to the v0.2.86 fly tweak after deeper source review (user report: Halescourge also has a fly disable). The earlier version only scaled Nurgloth's melee swarm and wrongly claimed Halescourge had no fly attack.

- **Replaced** `gt_nurgloth_fly_stun_sec` (Nurgloth-only seconds slider) with **`gt_fly_disable_mult`** (multiplier, default 1.00 = vanilla) that scales BOTH "cloud of flies" disable paths used by Burblespue Halescourge AND Nurgloth the Eternal:
  - Nurgloth's close-range fly-swarm BT action — `BreedActions.chaos_exalted_sorcerer_drachenfels.swarm_players.duration` (vanilla 8s; bt_swarm_action.lua:73).
  - The rare seeking **insect-swarm bomb missile** both bosses fire (`seeking_bomb_missile` -> projectile `insect_swarm_missile_01` -> explosion `chaos_slow_bomb_missile` / `_new` "fly_bomb") — `TrueFlightTemplates.sorcerer_slow_bomb_missile.attached_life_time` (vanilla 10s; true_flight_templates.lua:121, ai_breed_snippets.lua:1091, penny_ai_breed_snippets.lua:178, explosion_templates.lua:1325/1355).
  - A multiplier (not seconds) because the two paths have different vanilla durations (8 vs 10); 1.00 reproduces vanilla exactly. Both fly-blobs keep health 5, so the disable can still be ended early by killing the cloud — this only scales the max length.

## v0.2.86-dev (2026-06-17) -- Five new bot options + Nurgloth fly-swarm tweak

Five new bot toggles + one boss-mechanic slider, all default OFF, host-side only (bots/wipe checks run on the host), no network registration. New per-frame bot logic is consolidated into the SINGLE existing `PlayerBotBase.update` hook in `_gt_bot_fixes.lua` (no duplicate hook); new standalone hooks are on distinct `(Class, method)` pairs. All source citations verified against the decompiled vanilla source 2026-06-17.

### Bot Options (added to the existing group)
- **Don't fail the mission while a bot is alive** (`gt_bot_mission_fail_prevention`) — vanilla's wipe check `GameModeHelper.side_is_dead("heroes", ignore_bots=true)` (game_mode_adventure.lua:92) ignores bots, so the run ends when all *humans* are down. Hook forces `ignore_bots=false` for the heroes side so a living bot keeps the run going. Pairs with rescue-awaiting. Experimental.
- **Bots auto pull-up from ledges** (`gt_bot_ledge_pullup` + delay) — no vanilla self-rescue exists (player_character_state_ledge_hanging.lua:91-111); after the delay we call `StatusUtils.set_pulled_up_network(bot, true, helper)` (status_utils.lua:84), crediting the nearest living ally as helper.
- **Bots unstick from ladders** (`gt_bot_ladder_unstick` + delay) — detects a stuck ladder transition (`PlayerBotNavigation._current_transition.type == "ladder"`, player_bot_navigation.lua:276-339) and teleports the bot to the followed teammate via the vanilla teleport primitives (bt_bot_teleport_to_ally_action.lua:82-98).
- **Tighter bot follow distance** (`gt_bot_follow_distance_enabled` + meters) — vanilla snaps a bot back only at >=40 m (`FOLLOW_TELEPORT_DISTANCE_SQ=1600`, bt_bot_conditions.lua:1206). Faithful re-implementation of `BTConditions.should_teleport` with a configurable distance (default 40, set 10 to keep bots close); preserves the go-for-revive exception.
- **Bots instantly grab targeted items** (`gt_bot_instant_pickup`) — points `interaction_unit`/`forced_pickup_unit` at the bot's live pickup candidate so vanilla's `is_forced_pickup` path in `BTConditions.can_loot` (bt_bot_conditions.lua:877-890) bypasses the 3.2 m walk-up gate. Skipped while aiding. Experimental.

### Boss Mechanic Tweaks (new group)
- **Nurgloth fly-swarm disable (seconds)** (`gt_nurgloth_fly_stun_sec`) — slider, default = vanilla 8 s. Mutates `BreedActions.chaos_exalted_sorcerer_drachenfels.swarm_players.duration` (breed_chaos_exalted_sorcerer_drachenfels.lua:2018; the disable is the overpowering-blob "cloud of flies", bt_swarm_action.lua:71-77, breakable by killing the blob). Nurgloth-only — Halescourge's signature attack is the vortex, not flies. New module `_gt_boss_tweaks.lua`.

## v0.2.85-dev (2026-06-17) -- Settings logging + bot-rescue diagnostics

Diagnostics only, no gameplay change; all logging debug-gated. (Same change promoted to stable gt v0.2.71-alpha.)
- **Settings snapshot at load** (`[gt:settings@load] …`) + `/gt_dump_settings` — logs every `setting_id = value` so toggle states (incl. bot toggles) are visible in the console log.
- **Per-change setting log** (`[gt:setting-changed] <id> = <value>`) in `on_setting_changed`.
- **Bot-rescue scan diagnostics** (`_gt_bot_fixes.lua`): per-candidate `ready / health_alive / aid_path` + throttled summary (`awaiting=N picked=… not_health_alive=N path_blocked=N`) to pinpoint why a rescue doesn't fire. Verified CW uses `is_ready_for_assisted_respawn` (`deus_spawning.lua:203`, `respawn_handler.lua:502`) and awaiting allies are `HEALTH_ALIVE` (`side_manager.lua:363`), so the repro log reveals which gate fails.
- **Ironbreaker fix log** when it releases the ult-hold to revive.

## v0.2.84-dev (2026-06-16) -- Bot Options: three AI-teammate behavior fixes

### Why
Three long-standing bot AI gaps, requested as toggles. All default OFF, host-side only (bots only exist on the host), and none registers a network event or sends an RPC, so none can affect non-modded lobby members. New code in `_gt_bot_fixes.lua`, grouped under a new "Bot Options (AI Teammates)" settings group. Source citations are into the decompiled vanilla source (verified 2026-06-16).

### Fixes
- **Necromancer bots can hand off potions** (`gt_bot_necro_potion_handoff`). Her career skull (`bw_necromancer_career_utility_weapon`, `is_not_droppable`, `slot_type="potion"`) becomes the PRIMARY item in `slot_potion` at spawn (`simple_inventory_extension.lua:143-154`), so a picked-up potion lands in ADDITIONAL storage. Every handoff check reads only the primary (scoring `player_bot_base.lua:881-888`; give interaction `interactions.lua:1640-1705`), and the skull has no `can_give_other` -> bot never offers. A human swaps past the skull by tapping the potion key; the bot can't. Fix: a throttled `PlayerBotBase.update` hook promotes a stored giveable potion to primary (`swap_equipment_from_storage`, `simple_inventory_extension.lua:2434`) for Necromancer bots, so all vanilla logic works. Gated to real potions (`can_give_other`) so grimoires aren't promoted.
- **Ironbreaker bots revive during their ult** (`gt_bot_ironbreaker_revive_in_ult`). The IB bot ult holds a `wait_action` (block) for the buff's whole duration (`player_bots_settings.lua` dr_ironbreaker), and `BTConditions.can_activate_ability` short-circuits on `is_using_ability` (`bt_bot_conditions.lua:628`), parking the BT selector on the ability node so the higher-priority revive node (`bt_bot.lua:14-32`) never runs. Fix: hook `can_activate_ability` to return false for an Ironbreaker mid-ult when an ally needs aid, so the bot yields to revive. The ult is a timed buff and keeps running -- not wasted; ability is on cooldown so it won't re-pop.
- **Bots rescue allies awaiting respawn** (`gt_bot_rescue_awaiting`). `PlayerBotBase._select_ally_by_utility:903` excludes `is_ready_for_assisted_respawn` allies from aid entirely, with no branch to handle them. Fix: wrap the picker; when it finds nothing more urgent, scan for a reachable awaiting-respawn ally and return it relabeled `"knocked_down"`. The revive bot-action has no forced `input` (`player_bots_settings.lua` revive), so the interact fires the CONTEXTUAL interaction, which the engine resolves to `assisted_respawn` (`interactions.lua:562`). The wrapper calls the original first, so it composes with other bot mods. Experimental -- verify in-game.

### To verify
- **Necromancer:** play/spectate a Necromancer bot, let it pick up a potion; confirm it can hand it to a player who needs one (and isn't permanently holding the skull).
- **Ironbreaker:** down a teammate while an IB bot's ult is active; the bot should break off to revive instead of standing and blocking.
- **Rescue:** die and reach the awaiting-respawn state with bots free; a bot should path over and perform the assist-respawn.

## v0.2.83-dev (2026-06-14) -- Floating Damage Numbers (client-side; replaces the crash-prone third-party damage mod)

### Why
The third-party floating-damage-numbers mod crashed any lobby that contained a player who didn't have it — the classic signature of a mod that registers a VMF network event / sends RPCs to peers with no matching handler. Rather than decompile and patch it, the capability is rebuilt inside gt, networking-free, so it can't crash non-modded lobby members.

### How it works (all engine-native, no custom GUI)
- **Display:** reuses `DamageNumbersUI` (`scripts/ui/hud_ui/damage_numbers_ui.lua`), which already does world→screen projection + float/crit/fade animation. It's already in the **Adventure** HUD component list, but its `validation_function` only activates it in a mission when `script_data.debug_show_damage_numbers` is set — so we set that flag.
- **Feed:** reuses `DamageUtils.add_unit_floating_damage_numbers` (`damage_utils.lua:3942`) for color/crit/dot/size + the `add_damage_number` event.
- **Capture:** merged into the **existing** godmode `DamageUtils.add_damage_network` / `add_damage_network_player` hooks (the no-duplicate-hook rule forbids a second hook on the same `Class.method`), filtered to the local player as attacker.
- **Why it's crash-proof:** `add_damage_network_player` computes `damage_amount` locally (via `calculate_damage` + `apply_buffs_to_damage`, *before* the `is_server` branch) on host AND client, so accurate numbers need no host round-trip. Feature registers **no** network handlers and sends **no** RPCs.

### Added
- New module `_gt_damage_numbers.lua` (activation-flag sync + `mod._gt_dn_show` trigger; wraps `on_setting_changed` / `on_game_state_changed` via the chain pattern).
- Settings group **Floating Damage Numbers**: `gt_damage_numbers_enabled` (default off) with sub-toggle `gt_damage_numbers_include_dots` (default on — also shows DoT ticks & explosions via the `add_damage_network` path).

### Changed
- The two godmode `DamageUtils` hooks are now consolidated (godmode + damage-number feed) and capture the function's single return `damage_amount`. Behavior-identical for godmode.

### To verify (in-game)
- Enable the setting, **load a mission** (activation is evaluated at HUD build, so it takes effect on the next map), and confirm numbers float over enemies you hit (crit/headshot emphasized, DoT/explosion numbers grey when the sub-toggle is on).
- Join/host a lobby with a player who does **not** have gt and confirm no crash (this is the whole point — there is no network traffic from this feature).
- Toggle the sub-toggle off and confirm only direct weapon hits show numbers.

## v0.2.82-dev (2026-06-13) -- Fix keep-menu-hotkey mid-mission crash (Issue #62) + table-form hook nil-guards (Issue #70.1)

### Why
Multi-agent audit 2026-06-13.

**Issue #62 (crash) — "Keep Menus in Mission hotkeys causes crash".** The "Keep Menus in Missions" feature used three patches; patch (2) hooked `IngameUI.handle_menu_hotkeys` and unconditionally force-flipped the hotkeys-enabled arg to `true` whenever `mission_inventory_enabled` was on. That enabled EVERY keep hotkey mid-mission, not just inventory — Hero Select / Map / Achievements / Weave Forge / Store each transition to a view that spawns a dedicated `levels/ui_*/world` preview level which is NOT in a mission's package set, so pressing those keys fataled with "Level not loaded" + the `c_api_world.cpp:691` assert (confirmed against the attached crash log; same bug class as the closed cim Issue #50). The flip never reliably opened the inventory either (vanilla `can_interact`/transition gates still blocked it) — the working in-mission inventory path is the separate `/gt_inv` command + `gt_open_inv_hotkey` keybind (direct `handle_transition("hero_view_force")`), which does not depend on this hook.

**Issue #70.1 (hygiene).** Four table-form hooks were registered without an existence guard, inconsistent with the rest of the repo (cf. `career_tweaker_balance.lua:2472`). The targets are boot-loaded vanilla class globals so the unguarded form works in practice; the guard is latent load-order safety only.

### Changed
- **Removed** the `IngameUI.handle_menu_hotkeys` hotkey-flip hook (Issue #62). `mission_inventory_enabled` still drives the `InventorySettings` game-mode patch (1) and the ESC-menu "Open Inventory" entry (3) — only the crash-causing patch (2) is gone. The feature-overview comment block was updated accordingly.
- **Nil-guarded** four table-form hooks (Issue #70.1): `CareerExtension.update` (`:3272`), `GenericStatusExtension.add_fatigue_points` (`:3385`), `ProfileRequester.request_profile` + `GameModeInn._cb_start_menu_closed` (`:3456-3457`) now wrap in `if X and X.method then ... end`. Behavior-identical (targets always loaded).

### Tests
- New `/gt_regression_test` check `gt_no_mission_hotkey_flip` — source-pattern guard that FAILS if the `IngameUI.handle_menu_hotkeys` hook is reintroduced (needle split across two string literals to avoid self-match; degrades to no-op when source introspection is unavailable).

### To verify (in-game — behavior-changing)
- Mid-mission, press each keep-menu hotkey (Hero Select / Map / Achievements / Weave Forge / Store) and confirm **no crash** (they now no-op, as in vanilla).
- Confirm `/gt_inv` (and the `gt_open_inv_hotkey` keybind) still opens the inventory mid-mission, and the ESC-menu "Open Inventory" entry still works.

## v0.2.81-dev (2026-06-08) -- Failnotify hardening (Issue #72): leaving_game guard, unknown-result teardown, ungated F17 warning, test backfill

### Why
The 2026-06-08 post-ship re-review of v0.2.80 verified all four lobby fixes correct but flagged hardening gaps (filed as Issue #72). This closes them.

### Changed (`_gt_lobby_failed_join_reveal.lua`)
- **leaving_game guard:** the `create_popup` hook now defers to vanilla when `Managers.account:leaving_game()` — vanilla's own create_popup is a no-op in that window (state_loading.lua:2448-2450), so the mod no longer queues an enriched popup against a dying state object.
- **Unknown popup result:** `_consume_results` (factored out of the update callback, parameterized on popup_mgr for testability) grew an `else` branch — an unrecognized result logs via **ungated `mod:warning`** and still drives the restart_as_server teardown so the user is never stranded on the loading screen. Mirrors vanilla's logging of unknown results (state_loading.lua:1588). Unreachable today (only two button actions exist); defensive.
- **F17 warning ungated:** the popup-already-up soft-defer now logs via `mod:warning` (was debug-gated `_dbg_alert`); decision routed through exported `M._should_defer_for_existing_popup`.

### Tests (Issue #72 backfill)
- `gt_lobby_failnotify_unknown_result_drives_teardown` — injects a synthetic pending popup, drives the real consumer with a stub manager returning an unknown action, asserts the entry is consumed AND teardown fields are set.
- `gt_lobby_failnotify_popup_up_soft_defers` — pins the F17 guard's truth table; raises (instead of soft-deferring) fail the test.
- `gt_lobby_failnotify_unpack_preserves_leading_nils` — replica of the `3 + select("#", ...)` forward idiom under all-nil leading args + trailing format varargs (the state_loading.lua:1084 shape).
- Test exports: `mod._gt_failnotify_consume_results`, `mod._gt_failnotify_pending_popups`, `mod._gt_failnotify_should_defer`.

## v0.2.80-dev (2026-06-07) -- Lobby join-event clobber + failed-join popup race fixes

### Why
Audit 2026-06-07 found four correctness bugs in the `gt_lobby_*` modules:

- **F3 (HIGH) -- event-registration clobber.** `slot_reservations`, `session_ignore`, and `motd` each registered the SAME `(mod, "on_player_joined_party")` pair on `Managers.state.event`. Stingray's `EventManager` keys callbacks by `(object, event_name)` (`foundation/.../event_manager.lua:18-21`), so registering the same pair is last-writer-wins -- only ONE of the three handlers ever fired on a player join; the other two silently never ran. (Separately, every handler was mis-threaded: `EventManager.trigger` calls `object[name](object, ...)` at `event_manager.lua:42`, prepending `mod` as the first arg, so the handlers' `peer_id` param was actually `mod` -- meaning even the surviving handler was operating on the wrong value.)
- **F4 (HIGH) -- double consume-once popup race.** The enriched failed-join popup id was assigned to `state_loading_self._popup_id` AND polled by the mod's own update consumer, while vanilla `StateLoading._try_next_state` -> `_handle_popup` (`state_loading.lua:1308-1310`/`1565-1566`) ALSO polls/consumes the same id. `query_result` is consume-once, so one poller gets the result and the other sees `nil` -- if the mod won the read, vanilla never ran its `restart_as_server` teardown and the loading screen could hang.
- **F17 (LOW) -- hard assert in hook.** `assert(self._popup_id == nil, ...)` inside the `create_popup` hook could hard-crash if a popup was already up at intercept time.
- **unpack-safety.** The vanilla-fallback built `args = { header, action, right_button, ... }` (leading three often nil, trailing format varargs present) and `unpack(args)`'d it -- a bare `#args` boundary search over an array with nil holes truncates non-deterministically (VMF_RECIPES § 2a), silently dropping vanilla's `string.format` args.

### Changed
- `general_tweaker_dev.lua:6191-6249` -- NEW shared `on_player_joined_party` dispatcher. Defines `mod._gt_lobby_join_handlers`, `mod._gt_lobby_register_join_handler(name, fn)`, and the single registered method `mod.gt_lobby_on_player_joined_party` (swallows the EventManager-prepended `self`, then pcall-invokes every appended handler in order). Owns the ONE `(mod, "on_player_joined_party")` registration plus the per-state-transition re-register via `_gt_register_update`. (F3)
- `_gt_lobby_session_ignore.lua:111-120` -- dropped the module's own `em:register` + `on_game_state_changed` wrap; now `mod._gt_lobby_register_join_handler("session_ignore", _on_player_joined_party)`. Exposed `M.on_player_joined_party`. (F3)
- `_gt_lobby_slot_reservations.lua:202-217` -- dropped the module's own `_update_register` + boot register; now `mod._gt_lobby_register_join_handler("slot_reservations", ...)`. (F3)
- `_gt_lobby_motd.lua:213-226` -- dropped the module's own `_update_register` + boot register; now `mod._gt_lobby_register_join_handler("motd", ...)`. Exposed `M.on_player_joined_party`. (F3)
- `_gt_lobby_failed_join_reveal.lua:240-266` -- `_queue_enriched_popup` no longer assigns `state_loading_self._popup_id`; the enriched popup lives ONLY in `_pending_popups` (now also stashing the StateLoading instance as `entry.sl`). (F4)
- `_gt_lobby_failed_join_reveal.lua:277-315` -- new `_drive_restart_as_server_teardown(sl)` mirrors vanilla `_handle_popup`'s `restart_as_server` branch (`state_loading.lua:1570-1577`); the mod poller is now the SOLE owner of both popup actions and drives the teardown itself. Exposed as `mod._gt_failnotify_drive_teardown` (line 408) for the regression test. (F4)
- `_gt_lobby_failed_join_reveal.lua:365-368` -- replaced `assert(self._popup_id == nil, ...)` with a soft guard: `_dbg_alert` + fall through to vanilla. Added a local `_dbg_alert` (line 43) deferring to `mod._gt_dbg_alert`. (F17)
- `_gt_lobby_failed_join_reveal.lua:323-334` -- captured true arity via `local n = 3 + select("#", ...)` and pass `unpack(args, 1, n)` in the vanilla fallback. (unpack-safety)

### Tests
- `general_tweaker_dev.lua` `/gt_regression_test` adds:
  - `gt_lobby_join_dispatch_consolidated` -- all three join-handlers (`session_ignore`, `slot_reservations`, `motd`) are reachable from the single `mod._gt_lobby_join_handlers` list and the single registered method exists. FAILS if any module reverts to self-registration.
  - `gt_lobby_join_dispatch_pcall_isolated` -- drives the dispatcher with two synthetic handlers (first raises, second records); asserts the second still runs (pcall isolation) and receives the true `peer_id` (object-prepend stripped).
  - `gt_lobby_failnotify_teardown_driver` -- runs the F4 teardown driver against a synthetic StateLoading and asserts it sets `_teardown_network=true`, `_permission_to_go_to_next_state=true`, and `force_done()`s the first-time view; tolerates a nil sl.

### To verify
- Host a modded lobby with `slot_reservations`, `session_ignore`, AND `motd` all enabled; have a non-reserved/ignored peer join -- all three behaviors should now fire (kick-if-reserved / kick-if-ignored / MOTD send) rather than only one.
- Attempt to join a modded host with a missing/mismatched mod set: the enriched failed-join popup appears; clicking "Open Workshop" opens the URL AND leaves the loading screen cleanly; clicking "Close" (restart_as_server) returns to title without a hang.
- `/gt_regression_test` -- all three new checks PASS.

## v0.2.79-dev (2026-06-06) -- Memory Watchdog rides Debug Logging (drop redundant toggle)

The Lua Memory Watchdog (v0.2.77) had its own `memwatch_enabled` checkbox, separate from the universal `enable_debug_logging` toggle. That was the wrong call — the heap curve is a debug diagnostic like every other, and a separate switch to remember just meant a leak session got missed (the watchdog defaulted off, so the 2026-06-06 OOM logs had zero `[memwatch]` lines despite the mod being installed).

**Fix:** the watchdog now gates on `enable_debug_logging` — it runs automatically whenever Debug Logging is on (which is already on during any data-gathering session). Removed the `memwatch_enabled` checkbox + its loc keys; kept `memwatch_interval`. The `[memwatch]` log prefix stays greppable, so it's trivially separated from the rest of the debug stream when reading the log. `/gt_mem` on-demand snapshot unchanged.

## v0.2.78-dev (2026-06-06) -- GC mitigation to survive long sessions despite the leak

### Why
A Chaos Wastes expedition runs ~1 hour, but the Lua heap OOM'd at 26 minutes (v0.2.77 investigation). "Restart between missions" loses the run — not viable. This adds runtime GC mitigation so a full run can complete while the leaking mod is still being isolated + fixed.

### What this adds (two settings, under the watchdog toggles)
- **`gc_mitigation_enabled`** (checkbox, default off): tightens Lua's incremental GC — `setpause` 200→110 and `setstepmul` 200→400. Lua's default waits until the heap doubles before collecting; under heavy churn the collector falls behind and the heap climbs even though much of it is COLLECTABLE. Tightening keeps the heap near the true live set. On disable, restores the 200/200 defaults.
- **`gc_full_collect_sec`** (numeric 0-120, default 0=off): when aggressive GC is on, force a complete `collectgarbage("collect")` this often. Reclaims everything the incremental collector hasn't between cycles. Each collect is a brief frame hitch (bigger heap = longer) — but a short stutter beats a hard crash. Logs `[gc_mit] full collect: X KB -> Y KB (freed Z KB)` so you can see how much it reclaims (large freed = collectable garbage that was piling up = mitigation working; near-zero freed = true reference leak, only fixable in the offending mod).

### Honest caveat
If the growth is a TRUE reference leak (objects stay reachable), neither lever reclaims them — only fixing the offending mod does. These buy time when the growth is collectable garbage / GC-falling-behind, which the thrashing-GC signature in the crash log suggests is at least part of it. Pair with the Memory Watchdog (v0.2.77) to confirm the heap actually stays lower — and the `freed` number on each full collect tells you directly whether it's helping.

### Recommended for a long run tonight
1. Turn ON "Aggressive GC", set "Force Full GC Every" to 45-60s.
2. Turn ON "Lua Memory Watchdog" (interval 10s) to capture the curve.
3. Turn OFF Debug Logging on all -dev mods (cim_dev, cosmetics_tweaker, wt, ct_dev, gt_dev) — removes a large allocation source.

## v0.2.77-dev (2026-06-06) -- Lua Memory Watchdog (leak-hunt instrumentation)

### Why
User hit a hard Lua heap OOM crash on 2026-06-06 (`cemetery_belakor_path1`, GUID 2b762ad3): `Not enough memory reserved for heap lua_heap` — the 1 GB Lua scripting heap filled in 26 minutes with the GC thrashing (repeated 286-692ms full collections that couldn't reclaim enough = ~1 GB of LIVE Lua objects = a true reference leak). Static audit of the weapon-spawn-path mods (ct / wt / cosmetics_tweaker / Loremaster's Armoury) found them all independently leak-clean: cosmetics uses weak-keyed (`__mode="k"`) per-unit tables, wt's safe/traced_hook only allocates transient garbage, LA flushes its queue every frame, ct isn't in the per-frame path. The leak is in a not-yet-audited mod and can't be pinned by reading logs alone — it needs runtime memory instrumentation.

### What this adds
A **Lua Memory Watchdog**: logs the live Lua heap size every N seconds so a leak session shows the growth curve directly.

- **Settings** (under the debug toggles, top-level): `memwatch_enabled` (checkbox, default off) + `memwatch_interval` (numeric 2-60s, default 10). Independent of `enable_debug_logging` on purpose — a leak hunt wants the memory curve WITHOUT the rest of gt's per-event debug spam (which is itself allocation churn that muddies the signal).
- **Per-frame consumer** registered via the existing `_register_update` registry (pcall-isolated like every other gt update consumer). Accumulates `dt`; every interval logs:
  ```
  [memwatch] lua_kb=487213 (475.8 MB, 46.5% of 1GB cap) delta=+8420 peak_kb=487213 level=cemetery_belakor_path1 units=1842 t=600s
  ```
  `collectgarbage("count")` is the KB ground-truth for the same `lua_heap` the engine caps at 1 GB. `delta` per window is the leak rate; the window where `delta` spikes pins the trigger (which level, after which action). `pct` shows proximity to the OOM ceiling. Reading the counter does NOT force a collection — it's cheap.
- **`/gt_mem` command** — on-demand snapshot to chat regardless of the toggle, for quick before/after marks around a suspected leaky action.

### How to use it (next session)
1. Enable "Lua Memory Watchdog" in gt settings (leave Debug Logging OFF for a clean signal).
2. Play until the leak manifests (or just play a full session).
3. Read the `[memwatch]` lines in the console log. Monotonic `lua_kb` climb with a positive `delta` every window = leak confirmed; the level/timeframe where `delta` jumps is the trigger.
4. Bisect the modlist across runs (disable half, repeat) to isolate the single offending mod, then audit + fix THAT mod so it's independently leak-clean.

### Cost
Enabled: one `collectgarbage("count")` (counter read, no collection) + one log line per interval — negligible. Disabled: a single dt-accumulate + early return — free.

## v0.2.76-dev (2026-06-02) -- Add "Disable Bots (Solo)" toggle; fix that bots weren't removed mid-mission

### Why
User report: the existing "no bots" path didn't remove bots mid-mission, and there was no way to start a mission bot-free (wanted for true solo runs / speedruns). The only bot-off control was the `/gt_bottoggle` chat command, which flips `level_settings.no_bots_allowed` — a load-time gate with **no despawn path**, so existing bots stayed in the party and it isn't re-read per server tick. Confirmed against `GameModeAdventure._handle_bots` (game_mode_adventure.lua:371): the per-tick gate the engine actually honors is `script_data.ai_bots_disabled`, not `no_bots_allowed`.

### Mechanic
`script_data.ai_bots_disabled` is checked inside `_handle_bots` on every `server_update` across all three mission modes:
- `GameModeAdventure._handle_bots` (game_mode_adventure.lua:371)
- `GameModeDeus._handle_bots` (game_mode_deus.lua:527)
- `GameModeWeave._handle_bots` (game_mode_weave.lua:462)

When the flag is true and bots exist, vanilla runs `self:_clear_bots(true)` then returns early — so:
- Flipping it **ON mid-mission** despawns the current bots on the next tick AND blocks the delta-fill that would re-add them.
- Leaving it **ON** keeps the party bot-free from the first frame of every subsequent mission.
- Flipping it **OFF** lets the normal top-up logic refill on the next tick.

### Changed
- **`general_tweaker_dev_data.lua`**: new `gt_no_bots` checkbox appended to `gameplay_group` (after `gt_bots_in_keep`).
- **`general_tweaker_dev_localization.lua`**: `gt_no_bots` ("Disable Bots (Solo)") + tooltip.
- **`general_tweaker_dev.lua`**:
  - New "Disable Bots (Solo)" section with `_gt_apply_no_bots(enabled)` → sets `script_data.ai_bots_disabled = enabled and true or nil`. Forward-declared near the top (both `on_setting_changed` and `on_game_state_changed` reference it before its definition).
  - `on_setting_changed("gt_no_bots")` → apply immediately (instant mid-mission despawn / re-enable).
  - `on_game_state_changed` StateIngame-enter → re-apply so "no bots from mission start" survives level transitions and the game's own `ai_bots_disabled` resets.
  - Applied once at load so a persisted ON survives a mod reload.
  - Chat alias `/gt_no_bots`.

### Compatibility
- Host-only effective: bots are server-managed and `script_data` is local, so the flag only does anything on the host. Tooltip says so. Set locally on clients too (harmless).
- Independent of `gt_bots_in_keep` (keep-fill) — that feature calls `_add_bot_to_party` directly in inn modes, which don't run `_handle_bots`, so the two don't fight. Running both ON means bots in the keep for preview, none in missions.
- The old `/gt_bottoggle` (level `no_bots_allowed` flip) is left in place for its keep-spawn use; the new toggle is the correct mission-facing control.

### Regression tests (`/gt_regression_test`)
- `no_bots_setting_registered` — `gt_no_bots` widget exists in the data tree.
- `no_bots_apply_sets_ai_bots_disabled` — `_gt_apply_no_bots(true)` sets `script_data.ai_bots_disabled = true`, `(false)` clears it. Pins the correct engine flag so a future refactor can't silently regress to the no-despawn `no_bots_allowed` path. Saves/restores the live flag value around the probe.

## v0.2.75-dev (2026-05-30) -- Self-refreshing vanilla-name localization dump (feeds tools/gen-name-map)

### Why
`tools/gen-name-map/gen-name-map.ps1` resolves every mod-created display name from repo data but leaves ~3,010 VANILLA names `unresolved`: their English strings live in undumped `.package` bundles, not in the decompiled source. The only place those strings exist resolved is the running game (`Localize(loc_key)`). The maintainer wanted the vanilla half captured the same way the boon dump already is -- but **automatically, with no command to remember**.

### What
New sibling module `_gt_name_dump.lua`:
- On **keep/inn entry** (`StateIngame` enter), **once per game build** (gated on `Application.build_identifier()` stored in VMF settings; re-fires only after a game patch -- exactly when vanilla names could change), **silently** walks the in-memory `ItemMasterList` (`display_name` + `description`), `SPProfiles` (careers/heroes), and `Breeds`, calls `Localize()` on each loc key, and emits `[gt:name_dump] <loc_key>\t<English>` lines (same tab-separated shape as `dumps/boon_loc_dump.txt`) to the console log.
- **Output is the console log, not a file.** PHASE-0 FINDING (confirmed against the existing `/dump_level` code): VMF mods cannot write arbitrary files -- `io.open(...,"w")`, `mod:get_temp_data_directory`, and `Application.save_user_settings_to_file` are all unavailable from sandboxed mod code. The console-log + repo-side-grep route is the established gt dump doctrine.
- New VMF setting `gt_auto_name_dump` (checkbox, **default ON**) gates the auto-fire; new `/gt_dump_names` command forces a re-dump on demand (bypasses the build gate).
- Logging per PROJECT_STANDARDS § 3.6: payload via `mod:info` (operational telemetry, always logged); the "dump complete" confirmation is `_dbg` (log only); a dump FAILURE is `_dbg_alert` (chat+log, gated on debug logging). Applied marker untouched.

The generator side (`tools/gen-name-map/gen-name-map.ps1`) now auto-discovers and ingests the freshest dump with no flags (repo `dumps/name_loc_dump.txt` -> Fatshark user-dir file -> newest `console_logs/*.log` with `[gt:name_dump]` lines), fills any still-`unresolved` vanilla entry whose loc_key the dump knows (`display_name_source = "game_dump"`), and records the dump path/build/counts in the generated headers. No dump -> vanilla stays unresolved (never fabricated). Loop documented in `docs/generated/README.md`.

### Verify
Fixture (`dumps/name_loc_dump.SAMPLE.txt`, real vanilla loc_keys) flips 5 entries unresolved->resolved with `display_name_source = game_dump`; no-dump baseline returns to all-vanilla-unresolved. Requires a ship signal before Workshop upload.

## v0.2.73-dev (2026-05-27) -- Fix Issue #60: Host AI Takeover crashes `LocomotionSystem.update_animation_lods` next frame

### Why
User crash 2026-05-27 15:31:22 (session `7409d362-369e-43aa-a8e7-35b789b3b79d`). Crashify-tagged with "AI takeover crash". Engine reported `locomotion_system.lua:242: attempt to index local 'player' (a nil value)` in `update_animation_lods`. Stack contains no gt frames — vanilla `LocomotionSystem.update` called directly from `entity_system_bag.lua:62`. Lua locals at frame [1] show `player = nil`.

### Mechanic
Vanilla `LocomotionSystem.update_animation_lods` (in our decompile around line 227, in the shipped binary at the line the engine reports):

```lua
local player = self._override_player or Managers.player:local_player()
local viewport_name = player.viewport_name  -- crash here
```

Gt's host AI Takeover path (`_ai_swap_human_to_bot`) destroys the host's local Player object as part of the swap (line 2401: `pm:remove_player(peer_id, local_player_id)`). After that:
- `Managers.player:local_player()` returns nil (no local human exists).
- `self._override_player` is nil (gt never set it).
- `nil or nil` = nil → next frame crashes on `player.viewport_name`.

The crash fires ~0.6 s after the swap (`15:31:22.239 [ai_toggle:host] human->bot: ok` → `15:31:22.858` Lua Error). Confirmed reproducible — any host using `/ai` or the AI Takeover checkbox while in a mission will hit this.

Vanilla has a parallel case in benchmark mode where the human is replaced by a bot. The fix lives at `scripts/utils/benchmark/benchmark_handler.lua:423`:
```lua
locomotion_system:set_override_player(bot_player)
```

We mirror it.

### Changed
- **`general_tweaker_dev.lua`** `_ai_swap_human_to_bot`:
  - Captured the bot Player from `game_mode:_add_bot_to_party(...)` return value.
  - For host self-toggle (`not player.remote`), looks up `Managers.state.entity:system("locomotion_system")` and calls `set_override_player(bot_player)`. Bot reuses the host's slot, so `bot_player.viewport_name` is `"player_1"` (same as the host had). Vanilla's `update_animation_lods` now finds a valid viewport.
- **`general_tweaker_dev.lua`** `_ai_swap_bot_to_human`:
  - Before re-adding the human Player (or, in the remote-toggle case, returning to caller), clears the override: `locomotion_system:set_override_player(nil)`. Otherwise the override would dangle on the now-removed bot Player object and `update_animation_lods` would read `viewport_name` from a destroyed instance.
- **New marker** `CT_GT_AI_LOCOMOTION_OVERRIDE_MARKER_v0_2_73 = "gt-ai-locomotion-override-on-host-swap"` near the top of the file alongside the other AI Takeover markers.

### Regression tests (`/gt_regression_test`)
Two new checks:
- `ai_locomotion_override_marker_present` — marker constant unchanged. Belt-and-suspenders for refactors that drop the source-pattern check.
- `ai_locomotion_override_set_and_cleared` — reads the on-disk file via `debug.getinfo` source introspection and asserts the swap path contains `locomotion_system:set_override_player(bot_player)` AND the swap-back path contains `locomotion_system:set_override_player(nil)`. Catches partial reverts that keep the marker but drop one of the two calls. Degrades gracefully (no failure) when the install path doesn't expose the source for introspection.

### Stable status
The same bug exists in public `general_tweaker/` v0.2.69-alpha — host AI Takeover was added there in v0.2.52 and has the same `pm:remove_player` call with no `set_override_player` follow-up. Any host on stable using `/ai` mid-mission will crash. Per the dev-stream rule, we hold the merge until the user signs off, but flag it as a crash-class candidate for fast-tracking alongside the Issue #59 prefix-match fix.

## v0.2.72-dev (2026-05-26) -- Fix Issue #59: Drachenfels boss BT crash on CW dlc_castle_*_path1 (bt_conditions.lua:309)

### Why
Host crash 2026-05-26 in a CW Drachenfels run on level `dlc_castle_slaanesh_path1` (host running stable gt v0.2.69-alpha, same `_gt_cs_is_in_level` code as dev). `<<Script Error>> bt_conditions.lua:309: attempt to compare nil with number`. The crashed BT condition was `at_one_fifth_health`, called from the chaos_exalted_sorcerer_drachenfels `final offense phase` selector. Stack frame [6] = `general_tweaker.lua:4127` (the `AISystem.update_brains` hook) — gt was on the stack because every BT update routes through that pass-through gate, but the bug was downstream of it.

### Mechanic
1. gt hooks `BTConditions.transitioned_one_third_health` and biases the return to `true` when **outside** `dlc_castle` (the comment says "so the boss skips its arena-specific defensive phase outside its arena"). The hook body is `(_gt_cs_is_in_level("dlc_castle") and func(...)) or true`.
2. `_gt_cs_is_in_level(level_name)` previously did **exact-match**: `return level_key == level_name`. In CW, the Drachenfels arena loads under the level key `dlc_castle_slaanesh_path1` (or `_khorne_path1` / `_chaos_boss_path1` / etc. depending on the CW path). Exact-match against `"dlc_castle"` returned **false**.
3. With the gate false, the hook returned `true` without calling vanilla. The BT believed the boss had transitioned to one-third-health and entered the `final offense phase` branch.
4. Phase-init for that branch normally runs as part of vanilla `transitioned_one_third_health` — which we skipped. So `blackboard.current_health_percent` was never populated.
5. The first child condition in the offense-phase branch is `at_one_fifth_health` at bt_conditions.lua:309: `return blackboard.current_health_percent <= 0.2`. nil <= 0.2 → fatal compare. Host drops, everyone disconnects.

The bug existed on every CW variant of dlc_castle for as long as the exact-match gate has been in place. Bookmark Issue #59.

### Changed
- **`general_tweaker_dev.lua`**: `_gt_cs_is_in_level` now matches `level_key == level_name` OR `string.sub(level_key, 1, #level_name + 1) == (level_name .. "_")`. The underscore-boundary check prevents false positives against hypothetical levels with a shared word stem (e.g. a `dlc_castled_*` map). Three other gt_cs hooks call this helper (run_on_spawn arena init, level_analysis skip, the BT condition itself) — all benefit identically from the prefix match.

### Regression test (`/gt_regression_test`)
- `gt_cs_is_in_level_prefix_match` — table-driven assertion over seven cases: exact match, vanilla path variant, **Issue #59 CW theme variant**, CW boss variant, unrelated level, shared-prefix-without-underscore, keep level. Stubs `Managers.state.game_mode:level_key()` to drive each case, restores state on exit. Catches a refactor that reverts the prefix-match OR changes the underscore-boundary semantics.

### Stable status
The same bug exists in the public `general_tweaker/` v0.2.69-alpha (`_gt_cs_is_in_level` at line 3767 — identical exact-match code). Any host on stable will keep crashing on CW dlc_castle_*_path1 runs until we merge this fix down. Per the dev-stream rule we hold here until the user signs off on a stable release.

## v0.2.71-dev (2026-05-26) -- Add "Allow Bots in Keep" toggle (gameplay_group)

### Why
User direction 2026-05-26: vanilla VT2 doesn't spawn bots in the keep / Chaos Wastes hub / Versus inn, so the party visually reads as one-player even when the host has reserved an empty 4-slot lobby. Friends use the lobby state to preview party composition before launching a mission — empty slots make this confusing. Reproducing the adventure-mode bot-fill against the inn party gives the host a populated lobby for testing and visual continuity. Dev-stream first; merges to stable after a stability cycle.

### Mechanic
- **Why vanilla skips it.** `GameModeInn` / `GameModeInnDeus` / `GameModeInnVs` are distinct game-mode classes (not `GameModeAdventure`); their `server_update` deliberately omits the `_handle_bots()` call adventure mode runs. But `_add_bot_to_party` and `_remove_bot_instant` are defined on `GameModeBase` and inherited — they're callable on every inn mode, just never invoked.
- **What we do.** Register a 1Hz `mod.update` consumer (`_register_update("bots_in_keep", ...)`) that, while the toggle is on AND host AND `DamageUtils.is_in_inn`, tops party 1 up to its `num_slots`. Profile picking mirrors `GameModeAdventure._get_first_available_bot_profile` exactly: walk `PROFILES_BY_AFFILIATION.heroes`, filter by `profile_synchronizer:is_profile_in_use`, sort by `PlayerData.bot_spawn_priority` (or `ProfileIndexToPriorityIndex` as the vanilla fallback), then read `bot_career_index` off `hero_attributes`. No engine-internal field reads — every input is a global.
- **Bookkeeping.** `_bik_spawned` (Player table → true) tracks the bots we added so toggle-off / leave-keep can clear only ours without disturbing anything vanilla logic might have left behind. State-shutdown destroys bot units; `on_game_state_changed` calls `_bik_reset_bookkeeping()` (table-only reset, no engine calls on torn-down references).

### Changed
- **`general_tweaker_dev_data.lua`**: new `gt_bots_in_keep` checkbox appended to `gameplay_group` (alongside `ai_takeover_enabled`).
- **`general_tweaker_dev_localization.lua`**: `gt_bots_in_keep` ("Allow Bots in Keep") + `gt_bots_in_keep_tooltip` entries.
- **`general_tweaker_dev.lua`**:
  - New "Bots in Keep" section after the AI Toggle block. Provides `_bik_in_inn` / `_bik_is_host` / `_bik_game_mode` / `_bik_active` gates, `_bik_pick_next_bot` (priority-aware profile selector), `_bik_fill` (top up party 1), `_bik_clear` (remove our bots), `_bik_reset_bookkeeping` (drop tracking table). Exposed as `mod._bik_*` so the early `on_setting_changed` / `on_game_state_changed` closures can drive them (table-field reads resolve at call time, no forward-decl needed).
  - `on_setting_changed("gt_bots_in_keep")` → immediate fill on ON / clear on OFF (responsive UX; the 1Hz tick is the steady-state backstop).
  - `on_game_state_changed` → `_bik_reset_bookkeeping` on every state transition (prevents dangling Player references from the previous session).
  - Chat alias `/gt_bots_in_keep`.

### Compatibility
- Host-only behavior; clients see whatever bots the host spawned via the standard `_add_bot_to_party` path. No new RPC.
- Doesn't interact with `ai_takeover_enabled` directly — they target different game-mode contexts (`gt_bots_in_keep` requires `is_in_inn`; `ai_takeover_enabled` is refused in inn modes).
- DLC gate: `_add_bot_to_party` itself doesn't enforce DLC ownership, but `is_profile_in_use` covers any human-reserved profile and the bot profile list comes from `PROFILES_BY_AFFILIATION.heroes` which already respects which careers vanilla considers playable. No additional gate needed.

### Regression tests (`/gt_regression_test`)
Four new checks pin the feature's invariants — surfaced by post-deploy log scour 2026-05-26:
- `bots_in_keep_helpers_exposed` — `mod._bik_fill` / `_clear` / `_active` / `_reset_bookkeeping` are all functions. Catches a refactor that drops the `mod._bik_*` exposure (would silently no-op `on_setting_changed` and `on_game_state_changed`).
- `bots_in_keep_active_default_false` — `_bik_active()` returns false with the toggle off (default install state). Catches inverted gates and raises from missing dependencies.
- `bots_in_keep_reset_bookkeeping_safe` — `_bik_reset_bookkeeping` is idempotent and never raises (it fires on every state transition).
- `bots_in_keep_setting_registered` — walks the data widget tree and asserts `gt_bots_in_keep` exists. Catches a refactor that drops the checkbox from `gameplay_group` without updating the feature module.

## v0.2.70-dev — 2026-05-26

- **FORK POINT**: friends-only dev stream for in-flight gt work. Parent `general_tweaker/` (Workshop ID 3713619122) remains the public stable stream.
- Mod_id renamed `gt` → `gt_dev`. Scripts dir renamed `general_tweaker` → `general_tweaker_dev`. itemV2.cfg: visibility friends_only, published_id cleared.
- **RPC schema caveat**: `GT_LOBBY_RPC_SCHEMA` is per-mod-id; gt_dev clients can't sync lobby state with gt-stable clients (different mod_id, different network channel). Dev cohort should pin to one stream.

## v0.2.66-dev (2026-05-25) -- Restore dev/alpha/beta load banner (PROJECT_STANDARDS § 3.6 update)

### Why
User feedback 2026-05-25 EOD: earlier today's chat-spam cleanup pulled the `mod:echo("General Tweaker v" .. MOD_VERSION)` startup line from every mod. That's correct for stable (>=1.0.0) builds but hides the active version for in-flight dev/alpha/beta work. PROJECT_STANDARDS § 3.6 amended: dev/alpha/beta/0.x versions MUST echo `[<mod_id>] v<version> loaded` at module load; stable versions stay silent.

### Changed
- `general_tweaker.lua` -- added a track-detector `if` after the applied-marker line: matches `-dev$` / `-alpha$` / `-beta$` / `-rc%d*$` / `^0%.`. When any branch fires, `mod:echo("[gt] v<MOD_VERSION> loaded")` runs once.

## v0.2.62-dev (2026-05-25) -- Add /gt_lobby_motd_set + /gt_lobby_motd_clear chat commands (replaces the invalid VMF text_input widget removed in v0.2.61)

### Why
v0.2.61-dev inlined a fix to `general_tweaker_data.lua` that REMOVED the `gt_lobby_motd_text` widget — it had `type = "text_input"`, which is not a valid VMF widget type, and caused widget#103 to fail VMF validation and break gt options init entirely on 2026-05-25. Removing the widget eliminated the only authoring surface for the MOTD body, so this version restores host authoring via chat commands instead.

### Changed
- **`_gt_lobby_motd.lua`:** Added two chat commands.
  - `/gt_lobby_motd_set <text>` — writes `mod:set("gt_lobby_motd_text", text)`. With no arg, prints the currently-stored MOTD (or `(empty)`) and a usage hint. Echoes a confirmation and logs an info line on set.
  - `/gt_lobby_motd_clear` — clears the stored MOTD (sets to empty string).
- **`general_tweaker.lua`:** `MOD_VERSION` bumped `0.2.60-dev` -> `0.2.62-dev` (skips `0.2.61-dev`, which was the inline widget-removal fix landed without a CHANGELOG entry; see "Notes" below).
- **`itemV2.cfg`:** Title suffix refreshed to `v0.2.62-dev` (will be re-stamped on next upload by VMBLauncher anyway).

### Compatibility
The send/receive RPC path is unchanged — `_on_player_joined_party` still reads `mod:get("gt_lobby_motd_text")` and `_send_motd_to_peer` still chunks + sends with the same schema. Whether the text got there via the old widget (pre-0.2.61) or the new chat command (0.2.62+), the read path is identical. No bump to `mod.GT_LOBBY_RPC_SCHEMA` required.

### Notes
v0.2.61-dev was an inline fix to `general_tweaker_data.lua` removing the broken `gt_lobby_motd_text` widget; the MOD_VERSION constant in `general_tweaker.lua` was not bumped at the time. This 0.2.62 bump reconciles MOD_VERSION with the on-disk widget state.

The orphaned `gt_lobby_motd_text` / `gt_lobby_motd_text_tooltip` localization keys (general_tweaker_localization.lua:529-530) are harmless — VMF resolves them only when a widget references the setting_id, which no longer happens. Left in place against the possibility of a future custom widget type or HeroView authoring UI.

## 0.2.60-dev (2026-05-25) -- Absorb lobby_tweaker (slot reservations, session ignore, kick-idle, MOTD, failed-join mod-list reveal); add GT_LOBBY_RPC_SCHEMA versioning (closes Issue #43)

### Why
User direction 2026-05-25: "I deleted lobby tweaker, merge its features into general tweaker." Following the same archive-not-delete pattern used for `la_prefix_patch` earlier the same day. Issue #43 -- "Propagate RPC schema_version pattern to lobby_tweaker (lt_motd_show)" -- becomes gt's responsibility on absorption and is closed simultaneously.

### Changed
- **New files:** Seven `_gt_lobby_*.lua` modules under `general_tweaker/scripts/mods/general_tweaker/` migrated 1:1 from lt v0.1.7-dev:
  - `_gt_lobby_slot_reservations.lua` (was `lobby_tweaker/_slot_reservations.lua`)
  - `_gt_lobby_session_ignore.lua` (was `_session_ignore.lua`)
  - `_gt_lobby_kick_idle.lua` (was `_kick_idle.lua`; warn-lead-time hardcoded constant promoted to live read of `gt_lobby_ki_warn_seconds` setting)
  - `_gt_lobby_motd.lua` (was `_motd.lua`; RPC renamed `lt_motd_show` -> `gt_lobby_motd_show`; **NEW:** schema-versioned per VMF_RECIPES § 10)
  - `_gt_lobby_modded_manifest.lua` (was `_modded_manifest.lua`; lobby-data key prefix `ltw_` RETAINED for cross-mod compat with peers still on lt)
  - `_gt_lobby_failed_join_reveal.lua` (was `_failed_join_reveal.lua`; popup action key `lt_open_workshop` -> `gt_lobby_open_workshop`)
  - `_gt_lobby_known_mods.lua` (was `_known_mods.lua`; dropped retired `lobby_tweaker` and `la_prefix_patch` entries; `gt` retagged "C")
- **`general_tweaker.lua`:**
  - `MOD_VERSION = "0.2.60-dev"` (bumped from `0.2.59-dev`).
  - **NEW:** `mod.MOD_VERSION` exposed as a public field on the gt mod table (mirroring lt convention; consumed by bt's `/bug_report` walker and the new gt_lobby manifest broadcaster).
  - **NEW:** `mod.GT_LOBBY_RPC_SCHEMA = 1` declared near MOD_VERSION per VMF_RECIPES § 10. First positional arg of every `mod:network_send` on `gt_lobby_motd_show`; receiver gates on the value and drops with `_dbg_alert` on mismatch.
  - **NEW:** `mod._gt_register_update` exposed so `_gt_lobby_*` modules can plug into gt's central per-frame tick (gt Issue #16's update-consumer registry) instead of using the old `_prev_update = mod.update; mod.update = function(dt) ... end` chain.
  - **NEW:** `mod._gt_dbg` / `mod._gt_dbg_alert` exposed for sibling-file consistency.
  - Six `mod:dofile` calls at the bottom load the new `_gt_lobby_*` modules.
  - **NEW:** `_rt_register("gt_lobby_rpc_schema_present", ...)` regression test verifies `mod.GT_LOBBY_RPC_SCHEMA` is a number >= 1 (matches the ct pattern from v0.7.114-dev).
- **`general_tweaker_data.lua`:** New top-level group `gt_lobby_controls_group` with 12 sub-widgets (slot-reservations / session-ignore / 3x kick-idle / 5x MOTD / 2x manifest), inserted above the universal `enable_debug_logging` toggle.
- **`general_tweaker_localization.lua`:** ~30 new keys for the new group + sub-widget tooltips + the failed-join popup body strings.
- **`itemV2.cfg`:** Updated title (auto-managed via MOD_VERSION suffix) and description (mention "now includes Tweaker: Lobby's host-side controls").

### Chat-command rename
| Old (`lt`) | New (`gt`) |
|---|---|
| `/lt_reserve` / `/lt_unreserve` / `/lt_reservations` | `/gt_lobby_reserve` / `/gt_lobby_unreserve` / `/gt_lobby_reservations` |
| `/lt_ignore` / `/lt_ignore_persist` / `/lt_unignore` / `/lt_ignored` / `/lt_ignore_last` | `/gt_lobby_ignore` / `/gt_lobby_ignore_persist` / `/gt_lobby_unignore` / `/gt_lobby_ignored` / `/gt_lobby_ignore_last` |
| `/lt_idle_whitelist` / `/lt_idle_unwhitelist` / `/lt_idle_status` | `/gt_lobby_idle_whitelist` / `/gt_lobby_idle_unwhitelist` / `/gt_lobby_idle_status` |
| `/lt_motd_test` | `/gt_lobby_motd_test` |
| `/lt_manifest_dump` / `/lt_manifest_probe` | `/gt_lobby_manifest_dump` / `/gt_lobby_manifest_probe` |

### Settings migration note
Settings carry NEW keys (`gt_lobby_*`) under the gt mod-id, NOT under lt's mod-id. Previously-saved lt settings (`%APPDATA%\Fatshark\Vermintide 2\user_settings.config` -> lobby_tweaker entries) are NOT carried over -- users will see defaults on first load and need to re-enable any features they were using. The user_settings.config lt block becomes inert; it can be hand-deleted but is otherwise harmless.

### Archive
- `lobby_tweaker/` moved to `_archive/lobby_tweaker_v0.1.7-dev/` via `Move-Item` (per the global "no recursive-delete" rule + la_prefix_patch precedent).
- `_archive/lobby_tweaker_v0.1.7-dev/_ARCHIVED.md` documents the merge with full feature-inventory mapping table.
- Workshop item `3729845515` left in place on Steam (user can mark private / hidden via Steam web when convenient).
- GitHub release `mods-2026-05-24` still ships `lobby_tweaker.zip` -- left intentionally so existing vt2-mod-updater consumers don't break. Will fall out of next release tag (lt entry removed from `tools/publish-release/publish-release.ps1`).

### Dereferenced
- `CLAUDE.md` -- removed the lobby_tweaker row from the Mod Directory; gt row expanded to list the absorbed features. Mod count: 17 -> 15 active (la_prefix_patch + lobby_tweaker both retired today).
- `MOD_OWNERSHIP.md` -- removed lt row; added the second NOTE at the bottom (alongside the la_prefix_patch one).
- `tools/publish-release/publish-release.ps1` -- removed lt entry from `$mods`.
- `COMMANDS.md` -- gt section expanded with the 14 new `/gt_lobby_*` commands; snapshot-date note updated.

### Build
`VMBLauncher.exe build general_tweaker` -- OK, 4 bundles, 1.72s. NOT deployed, NOT uploaded (per 2026-05-25 EOD doctrine: no Workshop pushes without per-build user approval).

### Closes
- GitHub Issue #43 (Propagate RPC schema_version pattern to lobby_tweaker (lt_motd_show)) -- resolved by merge.

## 0.2.59-dev (2026-05-25) -- Remove startup banner echo + tidy on_setting_changed (chat-echo policy: PROJECT_STANDARDS § 3.6)

### Why
User feedback 2026-05-25: `"on enabling debug logging, I'm getting needless echos to the chat that it's enabled"` and `"on startup before enabling debug logging, I'm getting things echo'd to the chat for CWV"`. Audit found 13 mods with redundant `mod:echo("<Name> v" .. MOD_VERSION)` lines at module load and one mod with `mod:echo("Setting changed: " .. setting_id)` in on_setting_changed (career_tweaker -- the source of the Debug Logging chat echo).

Policy decision codified in PROJECT_STANDARDS.md § 3.6 "Chat-echo policy":
- **NEVER** at module load -- the applied marker `[gt] enabled v<X> settings_fp=<hash>` line is the canonical version surface, lives in the log, never spams chat.
- **NEVER** in on_setting_changed for routine settings -- use `_dbg` (gated on enable_debug_logging) if a diagnostic trace is needed.
- **OK** in on_setting_changed only for explicit high-impact toggles (bt master toggle, gt AI toggle).
- **OK** in user-typed chat command bodies (`/<feature>_regression_test`, `/verify_*`, etc.).

### Changed
- general_tweaker.lua -- removed the load-time `mod:echo("general_tweaker v" .. MOD_VERSION)` banner. The applied marker line (`mod:info("[gt] enabled v%s settings_fp=%s", ...)`) further down already surfaces the version + settings hash in the log. `mod:info("general_tweaker v%s loaded", MOD_VERSION)` retained for log-side visibility.
- itemV2.cfg -- updated the description's "Mention the mod version" bug-report instruction. Previous text told users to find the version "at the top of the in-game chat when you load into the keep" -- now points them at the console log (search for the `enabled v` line) or `/<mod>_regression_test`.

### Build
VMBLauncher.exe build general_tweaker -- verification only. NOT deployed, NOT uploaded.

## 0.2.58-dev (2026-05-25) -- Fix unescaped %APPDATA% in Debug Logging tooltip + add localization_format_safe runtime test

### Why
User report: "invalid string format on mouseover for Debug Logging" -- the canonical Universal Debug Logging tooltip (PROJECT_STANDARDS.md S 3.6) shipped with a literal %APPDATA%. Lua's string.format reads %A as a format directive and raises invalid option '%A' to 'format', surfacing as a red error tooltip in the VMF settings UI. All 16 active mods were affected (every mod ships the same canonical tooltip text).

### Changed
- general_tweaker_localization.lua -- escaped literal % in enable_debug_logging_tooltip so VMF's tooltip render path sees %%APPDATA%% (renders as %APPDATA% to the player). Same wording, just escaped.
- general_tweaker.lua -- added _rt_register("localization_format_safe", ...) runtime check. dofiles the loc table and pcall(string.format, value) on every entry; surfaces any unescaped % via /<mod_id>_regression_test. Catches the bug class even when the static check (qa/check_localization.ps1) is skipped.

### Notes
Repo-wide multi-layer defense landing across all 16 mods in this sweep:

1. Layer 1 -- 16 mods' loc strings fixed.
2. Layer 2 -- qa/check_localization.ps1 extended to parse loc.<key> = { en = "..." } assignment style (chaos_wastes_tweaker's pattern -- previously slipped detection).
3. Layer 3 -- _rt_register("localization_format_safe", ...) runtime check in every mod.
4. Layer 4 -- tools/vmb-launcher/CLAUDE.md doctrine update: "Run qa/check_localization.ps1 before declaring any localization edit complete."
5. Layer 5 -- documentation: LOCALIZATION_STANDARD.md S 1 "Recurring offender" worked example, docs/BUG_CLASSES.md S 16 new entry, PROJECT_STANDARDS.md S 3.6 canonical tooltip text now uses %%APPDATA%%.

Static check (qa/check_localization.ps1) reports 0 errors post-fix (down from 15 detected + 1 hidden in chaos_wastes_tweaker).

### Build
VMBLauncher.exe build general_tweaker -- verification only. NOT deployed, NOT uploaded.

## 0.2.57-dev (2026-05-25) — Applied marker (universal — PROJECT_STANDARDS.md § 3.6)

### Why
Every mod now prints a single `mod:info("[gt] enabled v<X.Y.Z> settings_fp=<8-hex>")` line at load — self-documenting console_logs. Walks the data widget tree, FNV-1a-32 hashes setting=value pairs. ALWAYS fires (not gated on debug_logging).

### Changed
- `general_tweaker.lua` — added file-local `_settings_fingerprint()` helper + `mod:info("[gt] enabled ...")` applied-marker line right after the `_dbg_alert` helper.
- `itemV2.cfg` — bumped to v0.2.57-dev.

## 0.2.56-dev (2026-05-25) — Three-issue audit bundle (Issues #13 / #15 / #16)

### Why
Three open audit issues against `general_tweaker.lua` resolved in a single version bump to avoid churn.

### Issue #13 — `_pause_active` forward-ref bug (one-line fix)
`on_game_state_changed` at line ~688 writes `_pause_active = false`, but the file-local `local _pause_active = false` lived at line ~2153 — well below the closure's compile point. Lua name resolution happens at function compile time, so the assignment was binding to a **global** `_pause_active` instead of the file-local that the pause/time-scale toggle (`gt_pause_toggle` / `gt_time_apply`) reads. After a level transition while paused, the next `/gt_pause` toggle desynced from the engine's actual pause state (off-by-one).

**Fix:** added `local _pause_active` forward declaration alongside the existing `_apply_godmode` / `_ai_handle_toggle_change` forward-decls near the top of the file. Changed the line ~2153 declaration from `local _pause_active = false` to `_pause_active = false` (no `local`) so it reuses the forward-decl slot instead of shadowing it.

### Issue #15 — `on_disabled` leaves global mutations behind
The mod has `is_togglable = true` but `on_disabled` previously only restored the camera offset. Every other mutation (script_data flags, RagdollSettings, BuffTemplates.power_level_unbalance, CareerSettings[*].attributes.base_critical_strike_chance, PlayerUnitMovementSettings.move_speed + closed-upvalue per-unit copy, InventorySettings, DamageUtils.is_in_inn, GameSettingsDevelopment.disable_free_flight, ESC-menu inventory entry) persisted after disable.

**Choice:** documented the limitation rather than authoring a snapshot-on-enable + restore-on-disable refactor across every mutated table. Cheap and honest; full unwind deferred as a larger refactor.

**Fix:**
- `on_disabled` now `mod:echo`s a one-line warning: *"Disable does not fully unwind active mutations. Restart the game for a clean vanilla state."*
- `itemV2.cfg` description's **Compatibility** section gained the same caveat as a bullet so users see it before subscribing / disabling.

### Issue #16 — Layered `mod.update` chain (5 rewraps, no registry)
`general_tweaker.lua` previously rewrapped `mod.update` five separate times using the `local _orig = mod.update; mod.update = function(dt) _orig(dt); ... end` chain idiom (lines 287/522/2486/2693/3027). No central registry, no inline `-- consumer #N: <feature>` header, no per-consumer error isolation. A single accidental edit `mod.update = function(dt) ... end` without preserving `_orig` would silently drop every earlier consumer — invisible until the dropped feature stopped working.

**Fix:** added a `_update_consumers` registry near the top of the file (after the `mod:echo` load banner). Single `mod.update = function(dt)` body iterates the consumer list and pcalls each consumer. Converted all 5 sites to `_register_update("<feature>", function(dt) ... end)` with these feature names (registration order preserved so dependencies still run in the original order):
1. `tp_camera` — `_tp_reapply_timer` countdown
2. `post_spawn_reapply` — `_post_spawn_reapply_timer` countdown + noclip locomotion heartbeat
3. `infinite_ammo_and_ai_pending` — 1Hz infinite-ammo refresh + AI takeover queue consumers
4. `cutscene_auto_skip` — deferred auto-skip processor
5. `hide_ui` — per-frame HUD mode enforcement

**Bonus:** pcall isolation per-consumer — one consumer error no longer kills the others. Errors surface as `mod:error("[gt:update] consumer '<name>' raised: ...")`.

### Changed
- `scripts/mods/general_tweaker/general_tweaker.lua`:
  - `MOD_VERSION` → `0.2.56-dev`.
  - Added `local _pause_active` forward declaration (Issue #13).
  - Dropped `local` from the line ~2153 `_pause_active = false` assignment (Issue #13).
  - Added `mod:echo` warning to `on_disabled` (Issue #15).
  - Added `_update_consumers` registry + single `mod.update` dispatcher near top of file (Issue #16).
  - Converted 5 `mod.update = function(dt) ...` rewrap sites to `_register_update("<feature>", function(dt) ...)` (Issue #16).
- `itemV2.cfg` — title bumped to v0.2.56-dev; description gained the disable-caveat bullet (Issue #15).

## 0.2.55-dev (2026-05-25) — Two-helper debug-logging policy (PROJECT_STANDARDS.md § 3.6)

### Why
User-requested two-channel debug discipline: `_dbg` for confirmation / dump / expected behavior (log file only), `_dbg_alert` for unexpected / wrong / mismatch (log file + in-game chat). Helpers installed in every active mod.

### Changed
- `general_tweaker.lua` — installed `_dbg_alert` helper alongside both existing `_dbg` definitions (the top-of-file one at line ~9 and the second observation-hooks one at line ~773 which lexically shadows the first). Added `_rt_register("dbg_helpers_two_channel", ...)` alongside the existing six gt regression checks.
- `itemV2.cfg` — bumped to v0.2.55-dev.

### Notes
- 0 of the existing 7 `_dbg(...)` call sites reclassified to `_dbg_alert` — all are state/transition tracking (e.g. `[state] X | ctx | cim=Y`, `[hero_view] on_enter | ctx`, `[transition] X | ctx`). None match the alert signature words.
- 0 bare `mod:echo` reclassified — all `mod:echo` calls are inside `/gt_*` / `/dump_*` chat command bodies (user-operational, leave alone) or the unconditional load banner.

## 0.2.54-dev (2026-05-25) — Standardize Debug Logging toggle (universal convention)

### Why
Repo-wide convention: every mod now exposes a single `enable_debug_logging` checkbox at the bottom of its VMF widget tree (PROJECT_STANDARDS.md § 3.6). gt previously had `gt_debug_mode` nested in `gt_debug_group` — renamed and un-nested.

### Changed
- `general_tweaker_data.lua` — removed `gt_debug_group` wrapper; `gt_debug_mode` renamed to `enable_debug_logging` at top-level bottom of `options.widgets`.
- `general_tweaker_localization.lua` — removed `gt_debug_group` / `gt_debug_mode` / `gt_debug_mode_tooltip`; added `enable_debug_logging` + `enable_debug_logging_tooltip`.
- `general_tweaker.lua`:
  - `_dbg_on()` now reads `mod:get("enable_debug_logging")` (was `gt_debug_mode`). All existing call sites untouched (they go through the helper).
  - Added file-local `_dbg(fmt, ...)` helper at top of file for new call sites. Output prefix `[gt:dbg]`.
- `itemV2.cfg` — title bumped to v0.2.54-dev.

### Notes
- **Migration**: the saved value of `gt_debug_mode` is not auto-carried into `enable_debug_logging`. Users who had the old toggle on must re-tick the new `Debug Logging` checkbox after first load. VMF defaults the new key to `false`.

## 0.2.53-dev (2026-05-25) — Stop `_ctx_str` from ERRORing on boot/title state transitions (Network backend has not been set)

### Why
Every session logged 4 ERROR-level entries during boot and title-screen transitions:

```
[Lua] Error: scripts/managers/player/player_manager.lua:559: Network backend has not been set
  [3] @scripts/managers/player/player_manager.lua:559: in function local_player
  [4] @scripts/mods/general_tweaker/general_tweaker.lua:784: in function _ctx_str
  [5] @scripts/mods/general_tweaker/general_tweaker.lua:812: in function <810>
  ...
  event_name = "on_game_state_changed"; _ = "gt"
[MOD][gt][ERROR] (event) on_game_state_changed: scripts/managers/player/player_manager.lua:559: Network backend has not been set
```

Not crash-causing, but log noise that hides real warnings.

Root cause: vanilla `PlayerManager:local_player()` (`player_manager.lua:559`) calls `self.network_manager.peer_id()` and asserts when `network_manager` is nil. `_ctx_str`'s existing guard only checked that the `local_player` method EXISTS on `Managers.player`, not that the network backend had been wired up via `PlayerManager.set_is_server(...)`. During the boot transition through `StateTitleScreen` and the 3 follow-on state-machine churns, the manager exists but `network_manager` is still nil.

### Changed
- `general_tweaker.lua` `_ctx_str` — added a precise pre-check for `Managers.player.network_manager ~= nil` alongside the existing method-presence check before calling `Managers.player:local_player()`. When the backend isn't up yet, `profile`/`career` fall back to `<pre-backend>` so the calling `_dbg("[state] ...")` debug log still gets a complete formatted string. Picked the structural pre-check (Option C in the task brief) over `pcall` because it handles future state additions automatically without depending on the engine-level assert being catchable from Lua, and over the state-name skip (Option B) because that would only fix the 4 documented firings.

### Verification
- Boot the game and watch the log: zero `[MOD][gt][ERROR] (event) on_game_state_changed: ... Network backend has not been set` lines.
- `[MOD][gt][DEBUG] [state] exit StateTitleScreen | mech=? level=? in_keep=false view=? profile=<pre-backend> career=<pre-backend> | cim=...` is the expected pre-backend shape; once the network manager is wired the fields populate normally.

## 0.2.52-dev (2026-05-24) — Force VMF re-handshake before AI Takeover client send (vmf_users bot-churn drop)

### Why
v0.2.50 used the correct API path to resolve the host peer_id but the send still silently dropped. Diffing PC-A's `console-2026-05-24-23.07.16*.log` against PC-B's `console-2026-05-24-23.08.54*.log` revealed the actual mechanic:

```
PC-B 23:10:11.110 [MOD][VMF][INFO] Added 11000010ef3befb to the VMF users list.
PC-B 23:10:11.112 [MOD][VMF][INFO] Removed 11000010ef3befb from the VMF users list.
PC-B 23:10:58.511 [MOD][gt][INFO] [ai_toggle emit] CLIENT->req host=11000010ef3befb want_bot=true
PC-A 23:07:53 +   (no [ai_toggle recv] line ever)
```

VMF's `PlayerManager.remove_player` hook (upstream `vmf/scripts/mods/vmf/modules/core/network.lua:375-404`) has a logic bug: when ANY player owned by peer_id is removed AND that peer still has a human_player on the same peer_id, it removes the WHOLE peer from `_vmf_users`. Host bot churn at mission load fires `remove_player(host_peer, bot_local_id)`; the host's own human player matches the "still has human_player" loop check, so VMF drops the host. Once dropped, `convert_names_to_numbers` returns nil and every `mod:network_send(..., host_peer, ...)` silently no-ops.

### Changed
- `general_tweaker.lua` — client toggle path now calls `get_mod("VMF").ping_vmf_users()` to force a VMF re-handshake before each send (pong round-trip ~50–300 ms on Steam P2P repopulates `_vmf_users[host_peer]`).
- Replaced inline send with `_ai_pending_client_send` queue + `_ai_consume_pending_client_send` drainer wired into the existing mod.update chain. Queue retries the send up to `_AI_CLIENT_SEND_MAX_RETRIES = 3` times with `_AI_CLIENT_SEND_DELAY_RETRY = 0.4 s` between attempts, re-pinging VMF each time. Idempotent — the host's RPC handler no-ops if state already matches.

### Regression tests (run `/gt_regression_test` in game)
- `ai_takeover_vmf_ping_api_available` — pins `get_mod("VMF").ping_vmf_users` as a callable function. If VMF ever renames or removes this entry point, our workaround silently no-ops via the pcall and every client toggle would silently drop again. Both the mod presence and the function shape are asserted.
- `ai_takeover_client_send_queue_wired` — synthetic enqueue with an already-elapsed `next_at`, then drives one mod.update tick and asserts the queue drained. Catches "consumer not wired into mod.update" regressions.

### Verification
1. Host on PC-A, client PC-B, mid-mission.
2. PC-B toggles AI Takeover (`/ai` or checkbox).
3. PC-B chat shows "AI ON (requested from host)." and PC-B log shows `[ai_toggle queue] CLIENT host=<pca> want_bot=true retries=3` followed by `[ai_toggle emit] CLIENT->req ... (attempt 1 of 3)`.
4. PC-A log shows `[ai_toggle recv] HOST<-req sender=<pcb> payload=table` followed by `[ai_toggle] human->bot for <pcb>: ok`.
5. PC-B character is bot-controlled. Toggle off → bot removed, human restored.
6. `/gt_regression_test` reports `PASS: ai_takeover_vmf_ping_api_available` and `PASS: ai_takeover_client_send_queue_wired`.

## 0.2.50-dev (2026-05-24) — Fix wrong server_peer_id path in v0.2.49 AI Takeover fix

### Why
v0.2.49-dev resolved the host peer_id via `Managers.state.network.server_peer_id`. That field doesn't exist on `GameNetworkManager` (which IS `Managers.state.network`, set in `state_ingame.lua:2194`). The lookup always returned nil, so every client toggle refused with "AI toggle: host peer_id not yet known (session still loading?)". PC-B log `console-2026-05-24-15.58.17*.log` lines 7570/7609/7612 — three rejected attempts at 16:00:43–16:00:51, well after the session-join handshake at 15:59:57.

### Changed
- `general_tweaker.lua` `_ai_handle_toggle_change` — resolve via the canonical `Managers.mechanism:server_peer_id()` (verified in vanilla at `imgui_career_debug.lua:153` + `versus_mechanism.lua:1845`). Falls back to `Managers.state.network.network_client.server_peer_id` (client) / `.network_server.server_peer_id` (host) for the brief window where mechanism hasn't published yet.
- `VMF_RECIPES.md` § 3 — fixed the (wrong) recipe that v0.2.49 followed. The published recipe now uses `Managers.mechanism:server_peer_id()` with the same fallback chain.

### Verification
1. Host on PC-A, client PC-B, mid-mission.
2. PC-B toggles AI Takeover. PC-B's chat shows "AI ON (requested from host).".
3. PC-B's log has `[ai_toggle emit] CLIENT->req host=<pca-peer> want_bot=true`.
4. PC-A's log has `[ai_toggle recv] HOST<-req sender=<pcb-peer> payload=table` followed by `[ai_toggle] human->bot for <pcb-peer>: ok`.
5. PC-B is now bot-controlled. Toggle off restores the human Player.

## 0.2.49-dev (2026-05-24) — Fix AI Takeover from client (RPC was silently dropped)

### Why
PC-B (client) toggled "AI Takeover" mid-mission. The chat echo printed ("AI ON (requested from host).") but PC-A (host) never received the RPC — the client's character stayed under player control, no bot ever spawned. PC-A's `console-2026-05-24-15.13.52*.log` shows zero `[ai_toggle]` lines; PC-B's `console-2026-05-24-15.09.09*.log` shows the local echo at 15:29:13/25/30 but no corresponding host-side receipt.

Root cause: `_ai_handle_toggle_change` called `mod:network_send(_AI_RPC, "server", ...)`. VMF's `convert_names_to_numbers` accepts exactly four recipient forms — `"all"`, `"others"`, `"local"`, or a literal peer_id. `"server"` falls through the lookup, is treated as a literal peer_id, fails `_vmf_users[peer_id]`, and returns silently with no error and no wire activity. Documented in `VMF_RECIPES.md` § 3 — same gotcha that burned `cosmetics_tweaker` v0.8.67 → v0.9.0.15.

### Changed
- `general_tweaker.lua` `_ai_handle_toggle_change` — resolve the host's real peer_id from `Managers.state.network.server_peer_id` before sending. If the field is nil (transient during host migration / level transition), return `(false, "host peer_id not yet known...")` so the checkbox auto-reverts via the existing failure-revert path.
- Added emit/recv diagnostic `mod:info("[ai_toggle emit] CLIENT->req ...")` at the client send site and `mod:info("[ai_toggle recv] HOST<-req ...")` at the top of the `network_register` handler. Per the VMF_RECIPES detection recipe — if recv ever stops firing again, the asymmetry is now visible in a single grep.

### Verification
1. Host VT2 on PC-A with General Tweaker v0.2.49-dev. Join from PC-B as client.
2. Start any adventure / weave / deus mission.
3. On PC-B, toggle "AI Takeover" in Mod Settings → General Tweaker (or `/ai`).
4. PC-B chat shows "AI ON (requested from host).".
5. PC-A's console log gets a fresh `[ai_toggle recv] HOST<-req sender=<pc-b peer> payload=table` line followed by `[ai_toggle] human->bot for <pc-b peer>: ok`.
6. PC-B's player is now controlled by a bot. Toggle off → bot is removed and the human Player is re-added.

## 0.2.48-dev (2026-05-24) — §15 belt-and-suspenders runtime test for v0.2.47 rawget conversion

### Why
Audit `.test_coverage_audit_2026-05-24.md` PARTIAL row 2: the v0.2.47 `NetworkLookup.pickup_names` rawget conversion was lint-covered (regression-lint.ps1 `strict-table-lookup`) but lacked an in-mod `_rt_register` runtime check. Per the §15 doctrine update appended this round, lint-covered fixes ALSO require a runtime regression test.

### Added
- Source-pattern marker constant `CT_GT_PICKUP_LOOKUP_RAWGET_MARKER_v0_2_48 = "gt-pickup-lookup-rawget-hardened"` near the top of `general_tweaker.lua`.
- `_rt_register("gt_pickup_lookup_uses_rawget", ...)` at the bottom of `general_tweaker.lua`. Two assertions:
  1. The marker constant retains its expected value.
  2. `rawget(NetworkLookup.pickup_names, <known-bad-key>)` returns `nil` without raising.

### Verification
1. Restart VT2 with the mod enabled, load the keep.
2. Run `/gt_regression_test` in chat. Expect `PASS: gt_pickup_lookup_uses_rawget` alongside the pre-existing checks.

## 0.2.47-dev (2026-05-23) — Convert 1 NetworkLookup lookup to rawget (latent strict-__index crash fix)

### Why
`NetworkLookup.*` subtables install a strict `__index = error()` metatable at boot. Plain `NetworkLookup.foo[key]` on a missing key throws — see memory `reference_vt2_strict_lookup_rawget.md`. The lint pass on 2026-05-23 flagged the `/spawn`-pickup site as latent: the key currently comes from the curated `_gt_is_pickup_names` list (all vanilla-registered), so it never misses today, but is a latent bomb if anything changes the surrounding data flow.

### Changed
- `general_tweaker.lua` (`_gt_is_spawn`) — converted `NetworkLookup.pickup_names[pickup_name]` to `rawget(NetworkLookup.pickup_names, pickup_name)` with a guard that echoes "Unknown pickup name" and returns instead of crashing the strict-lookup path.

### Verification
1. `tools/mod-lint/lint-mod.ps1` — passes.
2. `tools/lint/regression-lint.ps1 -Quiet` — site no longer appears in `strict-table-lookup` findings.

## 0.2.46-dev (2026-05-23) — Namespace `regression_test` chat command to avoid cross-mod collision

### Why
Seven mods registered `mod:command("regression_test", ...)`. VT2 chat commands are global — only the first mod wins, the rest fail silently with `[ERROR] (command): command name 'regression_test' is already used by another mod 'cim'`. Detected in PC-A log 2026-05-23 20:50:52.

### Changed
- `general_tweaker.lua` — renamed `regression_test` → `gt_regression_test`. Verification log line added at registration site.

### Verification
1. Restart VT2. No `[ERROR] (command):` line in console_logs about this command name.
2. Run `/gt_regression_test` in chat. Command fires and prints results.
3. Per memory `feedback_vt2_verify_before_shipping.md`.

## 0.2.32-alpha (2026-05-19)

### Fixed: Command-name collisions with Janoti's "Hacks" mod

The v0.2.26 → v0.2.31 port copied 11 command names verbatim from Hacks (Helpers 2). VMF only allows one global registration per command name; the first mod to load wins the slot and the other's registration is silently dropped with an error in console. Gt was loading before Hacks (alphabetical), so Hacks lost `/pause`, `/win`, `/fail`, `/restart`, `/kill_bots`, `/die`, `/ult_reset`, `/infinite_stamina`, `/giga_power`, `/inn_dmg`, and `/unkillable` entirely. Renaming gt's claims here releases all 11 slots back to Hacks.

| Old gt name | New gt name |
|---|---|
| `/pause` | `/gt_pause` |
| `/win` | `/gt_win` |
| `/fail` | `/gt_fail` |
| `/restart` | `/gt_restart` |
| `/kill_bots` | `/gt_killbots` |
| `/die` | `/gt_die` |
| `/ult_reset` | `/gt_ultreset` |
| `/infinite_stamina` | `/gt_stamina` |
| `/giga_power` | `/gt_gigapower` |
| `/inn_dmg` | `/gt_inndmg` |
| `/unkillable` | `/gt_unkillable` |

Hotkey widgets unchanged (they bind to `mod.gt_*` functions which were always gt-namespaced). Settings UI labels unchanged. Tooltips updated to reference the new command names.

`/win` had been a gt command since before the port too (renamed alongside the others — same collision).

## 0.2.31-alpha (2026-05-19)

### Changed: Disable Enemy Spawns now also flips the `script_data.ai_*` flag set
### Added: Engine-error nil-guards from Janoti's "Hacks" (Group F — final port batch)

**Broadened `/no_enemies` toggle:** the two `ConflictDirector` hooks still catch every spawn call, but the toggle now ALSO flips the same `script_data.ai_*_disabled` flag set Hacks uses (mini_patrol, critter, horde, roaming, boss, rush_intervention, specials, pacing, outside_navmesh_intervention). The script_data path aborts spawns earlier in the pacing/intervention pipelines so the spawner doesn't even queue work. Per `feedback_redundant_safeguards_ok` redundancy is welcome here — cost is nine boolean writes per toggle, missed-path failure (an enemy slipping through) is silent. `_apply_script_data_no_enemies` is forward-declared at the top of the file because `on_setting_changed` (which lives above the no_enemies section) needs to call it.

**Engine-error nil-guards (passive):** two `mod:hook` wrappers that no-op the call when the target unit is dead/nil, copied from Hacks:

- `VolumetricsFlowCallbacks.unregister_fog_volume(params, ...)` — bails if `params.unit` is nil or `not Unit.alive(params.unit)`. Suppresses the red `[Engine Error]` spam that occasionally shows up when a fog volume's owner unit was already collected.
- `Unit.get_data(unit, ...)` — bails if `unit` is nil. Suppresses error spam from systems that hand stale unit handles back to the engine during cleanup.

Both guards are pure pre-checks — the original function runs unchanged when inputs are valid.

This concludes the Janoti "Hacks" feature port (Groups A–F across v0.2.26 → v0.2.31). All 17 missing features ported plus 2 expansions to existing gt features.

## 0.2.30-alpha (2026-05-19)

### Added: Player State Toggles group — port from Janoti's "Hacks" (Group E)

Three small toggles kept distinct from gt's existing `god` umbrella:

- **`/inn_dmg`** — host-only flip of `DamageUtils.is_in_inn`. When the inn flag is off, the keep behaves like a mission (damage taken normally). Useful for sparring with bots in the keep without flipping all of godmode.
- **`/cloak`** + hotkey — visual invisibility (model hidden + invisible to AI). Uses `set_invisible(true, false, "gt_cloak")` with its own reason namespace so toggling cloak doesn't clobber godmode's invisibility (which uses `"gt_godmode"`) and vice versa.
- **`/unkillable`** — flips `script_data.player_unkillable`. You take damage normally, you can be grabbed by disablers, but the engine refuses to drop you below 1 HP. Different intent from `god` — this is "I want to feel hits while testing".

Only `cloak` gets a hotkey widget; the other two are command-only since they're niche toggles.

## 0.2.29-alpha (2026-05-19)

### Added: Buffs & Stats group — port from Janoti's "Hacks" (Group D)

New "Buffs & Stats" settings group + three chat commands + two sliders:

- **`/infinite_ammo`** — toggle infinite ammo + zero overheat. Applies the vanilla `twitch_no_overcharge_no_ammo_reloads` buff to the local player; if you're the host, also pushes it to every other player. Periodic re-apply every 1 second via the shared `mod.update` chain keeps the buff refreshed if anything tries to strip it.
- **`/infinite_stamina`** — toggle infinite stamina. Hooks `GenericStatusExtension.add_fatigue_points` and short-circuits the call when the flag is on, so stamina-cost actions (block, push, dodge-cost) never deplete the bar.
- **`/giga_power`** — multiply the Enhanced Power talent buff by 1000x. Snapshots the original `BuffTemplates.power_level_unbalance.buffs[1].multiplier` on first activation and restores it on toggle-off. Requires re-equipping the talent for the buff to refresh.
- **Base Crit Chance slider (0–100%)** — rewrites the current career's `CareerSettings[name].attributes.base_critical_strike_chance`. Auto-snaps back to that career's vanilla value when you switch careers (hooks `ProfileRequester.request_profile` + `GameModeInn._cb_start_menu_closed`). Per-session — game restart restores defaults.
- **Movement Speed slider (0–30 m/s)** — rewrites `PlayerUnitMovementSettings.move_speed` plus every per-unit override already snapshotted by the engine (reached via `debug.getupvalue(unregister_unit, 1)` since the per-unit table is a closure local). Per-session.

The infinite-stamina hook is always-registered (toggling on/off flips a flag inside the closure) to avoid VMF's duplicate-registration error.

## 0.2.28-alpha (2026-05-19)

### Added: Ult Controls group — port from Janoti's "Hacks" (Group C)

New "Ult" settings group with three features, all driven through `CareerExtension`:

- **`/ult_reset`** + hotkey — one-shot reset. Walks `_num_abilities` and calls `:reduce_activated_ability_cooldown_percent(i, 1)` on each, dropping every charge to 0 cooldown. Same primitive ThePageMan's "No Ult Cooldown" mod uses.
- **Cap Player Ult Cooldown** (toggle + 0–120s slider) — clamps every player-controlled career ability's remaining cooldown to at most the configured value, every `CareerExtension.update` tick. Effectively a configurable "short ult" without burning a talent slot.
- **Cap Bot Ult Cooldown** (toggle + 0–120s slider) — same idea but for AI-controlled units. Useful in solo-with-bots to see bots ult more aggressively.

Both caps share `mod._gt_clamp_cooldowns` which walks the ability's `cooldowns` array from the decaying-charge index downward, trims each entry, then re-runs the engine's `cooldown_paused` / `set_activated_ability_cooldown_unpaused` housekeeping so the ability HUD overlay stays in sync. This is the iteration pattern the engine expects — replicating it any other way desyncs the UI.

## 0.2.27-alpha (2026-05-19)

### Added: Time & Pause group — port from Janoti's "Hacks" (Group B)

New "Time & Pause" settings group with five widgets + three chat commands. Both features use the same engine primitive: `Managers.state.debug:set_time_scale(index)` where `index` selects an entry in `debug_manager.lua`'s `time_scale_list` (24 multipliers, index 13 = 1.0x).

- **Time Scale slider (1–24)** — change live; the new value is applied immediately and re-applied on every `StateIngame` entry (vanilla wipes the engine time scale on level transitions).
- **`/time_faster` / `/time_slower`** + bindable hotkeys — step the slider up/down by 1.
- **`/pause`** + hotkey + Pause Speed slider (1–24, default 1) — host-only toggle between the configured pause speed and normal. VT2 has no true freeze primitive; `set_time_scale(1)` is the closest thing (UI still updates). Clients see the change since time scale is server-driven.

The pause feature and the time slider share the same engine setter; if both are touched in the same session, the last write wins. We keep them as separate widgets matching Hacks's UX. Setting the slider while paused updates the post-unpause target but doesn't override the active pause speed.

## 0.2.26-alpha (2026-05-19)

### Added: Level Control group — port from Janoti's "Hacks" (Group A)

New "Level Control" settings group + six chat commands + six bindable hotkeys, sourced from the corresponding features in Janoti's [Hacks](https://steamcommunity.com/sharedfiles/filedetails/?id=3266071368) (uploaded as "Helpers 2"):

- **`/fail`** + hotkey — fail the current mission (`Managers.state.game_mode:fail_level()`).
- **`/restart`** + hotkey — retry the current mission (`Managers.state.game_mode:retry_level()`).
- **`/kill_bots`** + hotkey — kill every bot in the party. On EAC-secure realm only allowed pre-round (vanilla anti-cheat would flag mid-round bot kills); unrestricted on modded realm.
- **`/die`** + hotkey — kill your local character (`death_system:kill_unit`).
- **`/fix_sound`** + hotkey — stop the looping vortex SFX that gets stuck after restarting mid-storm. Fires `sfx_player_in_vortex_false` on the local first-person extension, same trick Craven's script uses.
- **`/win`** also gets a hotkey (the command itself already existed in v0.2.25).

All five level-flow commands no-op in the keep with a friendly echo so a mis-press while sorting loadout doesn't yank you out of the inn state machine. The `mod.gt_*` functions are exposed as named members (not just locals) so VMF's `keybind_type = "function_call"` resolver can find them via the `function_name` string.

## 0.2.24-alpha (2026-05-17)

### Added: Skip Intro Splash Screens toggle

New "Startup" group with a single checkbox: **Skip Intro Splash Screens**. Same end result as bIbIbI's [Skip Intro mod](https://steamcommunity.com/sharedfiles/filedetails/?id=1395453301) — skips the Fatshark/engine logo splash sequence at game launch.

Implementation uses the canonical vanilla bypass: `StateSplashScreen.on_enter` (state_splash_screen.lua:92-110) checks a set of `Development.parameter` flags including `"skip_splash"` — if any are set, `self._skip_splash = true` and the splash sequence is bypassed. Same mechanism as the `-skip-splash` command-line argument.

`Development.set_parameter()` is a no-op in release builds, so we write directly to `Development._hardcoded_dev_params.skip_splash` (same trick the third-person camera section uses for `third_person_mode`). Done at mod load time, which runs before `StateSplashScreen.on_enter`, so the flag is in place when the check fires.

**Note:** changing the setting mid-session shows no immediate change — the splash for the current boot has already run. The flag is still updated so the next launch reflects the new setting.

## 0.2.23-alpha (2026-05-17)

### Added: AI Takeover VMF widget

The `/ai` command from v0.2.22 is now also exposed as a checkbox in the Gameplay group ("AI Takeover (bot controls your character)"). Chat command and checkbox stay in lockstep — the command just flips the setting, and `on_setting_changed` runs the same RPC pipeline. Auto-resets to off on game state change (level transition / leaving a mission) so the checkbox never persists a stale "on" across runs that didn't actually swap.

Same v1 scope as v0.2.22: client-only, refused on host self-toggle, refused in versus and the keep.

## 0.2.22-alpha (2026-05-17)

### Added: AI Toggle (`/ai`) — hand off control to a bot mid-mission

New chat command `/ai` lets a **client** hand their character over to bot AI (and toggle back). Useful for multiplayer testing where the mod author hosts on one machine and wants the second machine's player to behave as a bot, and as a general "stepping away" utility for clients who need to leave mid-run.

VT2 has no hot-swap path between human and bot units — they use different `go_type`s with incompatible extension stacks. So toggling means despawn-human + add-bot (and the reverse). Both halves of the dance exist in vanilla (see `GameModeBase._add_bot_to_party` / `_remove_bot_instant` and `GameModeAdventure.player_entered_game_session`); we compose them and wire them to a player-driven trigger.

Server-driven by necessity — `ProfileSynchronizer` and `PartyManager` mutation APIs all assert `is_server`. Client sends a VMF network request (`gt_ai_toggle_request`) and the host runs the swap. Host saves the original peer/profile metadata; toggling again recreates the human Player object via `add_remote_player`, re-claims the slot via `assign_peer_to_party`, and re-assigns the profile via `assign_full_profile(..., is_bot=false)`. Spawning system picks them up next tick.

**v1 scope:**
- Client (remote peer) self-toggle: supported.
- Host self-toggle: refused with a message — destroying the host's local Player object mid-mission would tear down camera/HUD/input bindings that aren't trivial to recreate.
- Versus: refused (heroes have no bot AI in versus).
- Keep / inn: refused (no spawning system running).

**Known rough edges (acceptable for v1, will iterate based on testing):**
- Inventory / current ammo / temporary buffs don't persist across the swap — the bot inherits the profile's default loadout from the spawning system.
- Client-side camera transition when their unit despawns is whatever vanilla does for "your player_unit just got removed" (likely spectator-style); untested.

## 0.2.21-alpha (2026-05-16)

### Added: Disable Enemy Spawns toggle

New checkbox in the Gameplay group + `/no_enemies` chat command. When on, every enemy spawn — hordes, specials, bosses, patrols, and pre-placed level-load enemies — is refused. Every enemy in VT2 funnels through `ConflictDirector`'s two public entry points (`spawn_queued_unit` for the pacing-system queue, `spawn_unit_immediate` for terror events / scripted triggers); hooks on both refuse the call when the setting is on.

Existing enemies are NOT despawned — the toggle affects future spawns only. Combine with `/god` to walk past anything already alive when toggling mid-mission.

Tooltip + Workshop description updated. Chat-command bullet line in the Workshop description extended with `/no_enemies`.

## 0.2.20-alpha (2026-05-15)

### Changed: Godmode now also makes the player invisible to enemy AI

Uses the engine's own canonical signal — `GenericStatusExtension:set_invisible(true, false, "gt_godmode")` — which AI perception explicitly skips (`perception_utils.lua:381`). Same primitive Shade's Shadowfall ult uses, just with a `reason = "gt_godmode"` namespace so it doesn't clobber other invisibility sources.

`skip_third_person=false` so the 3P body fades as a visual cue that godmode is on. First-person view (1P weapon arms) is unaffected since those are a separate unit.

Belt-and-suspenders re-apply on each `GenericStatusExtension.extensions_ready` — `self.invisible` is reset to `{}` on extension init, so a level transition while godmode is on would otherwise leave the new player unit visible to AI.

Tooltip + Workshop description updated. Forward-declared `_apply_godmode` at the top of the file so `on_setting_changed` (defined before the godmode section) can bind to the local instead of a nil global — see `feedback_lua_forward_reference.md`.

## 0.2.19-alpha (2026-05-15)

### Changed: Godmode now also blocks disablers

The two `DamageUtils` hooks (add_damage_network, add_damage_network_player) stop hp damage but disablers (gutter runner / assassin pounce, packmaster hook, chaos-spawn / corruptor / tentacle grabs, hanging cage) bypass the damage pipeline entirely — they push the character state machine directly into the disabler state.

Hook `GenericStateMachine.change_state` (the chokepoint every `csm:change_state(state_name, params)` call funnels through) and drop the transition when (a) godmode is on AND (b) the unit is the local player AND (c) the requested state is one of: `pounced_down`, `grabbed_by_pack_master`, `grabbed_by_chaos_spawn`, `grabbed_by_corruptor`, `grabbed_by_tentacle`, `in_hanging_cage`. Normal gameplay states (`stunned`, `ledge_hanging`, `overpowered`, `knocked_down`, `dead`) are NOT touched.

Godmode tooltip + Workshop description updated to advertise the broader behaviour.

## 0.2.18-alpha (2026-05-14)

### Fixed: Free camera now actually freezes the player

The free camera (`/freecam`) was supposed to detach the camera while leaving the character in place — but WASD was still moving the character alongside the camera. The engine's `_enter_free_flight` calls `input_manager:block_device_except_service("FreeFlight", "keyboard", ...)` which is meant to stop the Player input service from receiving keyboard input, but empirically that block doesn't reliably stop the character state machine from reading movement.

Belt-and-suspenders fix: while freecam is active, also call `loco:set_disabled(true)` on the local player's locomotion extension. That yanks the unit out of the locomotion update list entirely — character state machine still ticks (animation pose, etc.) but no movement can be applied regardless of what the Player input service produces. On freecam exit (toggle off, F8 press, or level transition via the `_exit_free_flight` hook), `loco:set_disabled(false)` re-enables the character cleanly. `pcall`-wrapped to survive engine API drift.

## 0.2.17-dev — first public Workshop release (2026-05-14)

### Changed: Workshop visibility flipped private → public

gt was uploaded as `friends_only` from its inception. After the noclip feature landed and verified working in 0.2.17-dev, the user flagged the mod ready for a public release. `itemV2.cfg`:

- `visibility`: `"friends_only"` → `"public"`
- `title`: `"Tweaker: General (WIP)"` → `"Tweaker: General"`
- `description`: replaced the one-liner with a sectioned feature description matching ct/cim/the rest of the Tweaker series — Third-Person Camera, Noclip, Keep Menus in Missions, Gameplay toggles, Chat commands, Compatibility — plus the canonical BMC block.
- `preview.jpg`: replaced with the Tweaker General artwork (1024×1024, JPG q=85, 215 KB).

`upload_gt.ps1`'s visibility guard updated `friends_only` → `public` and `--allow-public` added so the launcher's safety gate is satisfied. Upload pushed via `vmblauncher upload general_tweaker --allow-public`; verified live via `ISteamRemoteStorage/GetPublishedFileDetails`: `visibility=0`, `file_size=1346271` (matches `bundleV2/` byte-for-byte).

## 0.2.17-dev (2026-05-14)

### Fixed: Noclip chat command now applies immediately

`/noclip` previously relied on `mod.on_setting_changed` firing after `mod:set("noclip_enabled", ...)` to actually flip the locomotion state. That worked from the VMF settings menu but was unreliable when toggled from the chat command. Added an explicit `_apply_noclip(new_val)` call after the `mod:set`, mirroring the same belt-and-suspenders pattern `/tp` already uses.

Also added `mod:info` diagnostic lines in `_apply_noclip` — every toggle now logs `[noclip] ON — loco.state now '...'` or `[noclip] no locomotion extension yet ...` so post-mortem debugging of "didn't work" reports is one log-grep instead of a re-build cycle.

## 0.2.16-dev (2026-05-14)

### Added: Noclip (player flies through walls)

New "Noclip" toggle in the Gameplay group plus a `/noclip` chat command. Unlike the existing detached freecam, noclip moves the **player body** through walls — WASD flies in look direction, Space/Ctrl for up/down, Left Shift for a speed boost. Two new numeric sliders (`noclip_speed` default 15 m/s, `noclip_boost_multiplier` default 3.0x) tune the base and boost speed.

Built on the engine's `script_driven_no_mover` locomotion state (used by chaos-spawn-grab and tentacle-grab), which teleports the unit by `velocity_wanted * dt` each tick without touching the mover — so static geometry, props, and enemies are all bypassed. The dead-simple `Mover.set_collision_disabled` / `set_mover_disable_reason("noclip", true)` paths don't work for players: the locomotion templates and `PlayerUnitLocomotionExtension` call `Mover.flying_frames(mover)` and `Mover.move(mover, ...)` without nil-guarding the mover, so nuking it fatals immediately. The no-mover *state* path bypasses both calls without touching the mover handle.

Three hooks make it stick:

1. **`PlayerUnitLocomotionExtension.update_script_driven_no_mover_movement`** — when noclip is on for the local player, ignore whatever velocity the character state machine wrote (walking writes ground-plane velocity, falling writes gravity) and compute our own from W/A/S/D + Space/Ctrl projected through the first-person camera rotation.
2. **`mod.update` heartbeat** — re-asserts `loco.state = "script_driven_no_mover"` each tick. Basic states (standing/walking/jumping/falling) don't touch `locomotion.state`, but transitions into ledge-hang / ladder / knockdown call `enable_script_driven_movement()` which would hand us back to the wall-respecting mover update.
3. **`PlayerUnitLocomotionExtension.extensions_ready`** — re-arms noclip on each player spawn (mission entry, respawn) if the persisted VMF setting is on. Without this, the setting stays "on" while the actual locomotion state is whatever the engine initialised it to (usually `script_driven`).

On toggle-off, the mover is snapped to the player's current position before handing control back, otherwise the mover stays at the entry point and the next `Mover.move()` yanks the player back there.

Caveats baked into the tooltip: toggling off mid-air drops you, and special states (ledge-hang/ladder/career-ability/knockdown) may briefly fight the mode.

## 0.2.10-dev (2026-05-01)

### Changed: Migrated to VMB build pipeline

Moved from the raw Stingray SDK build (`gt.mod`, `settings.ini`, `lua_preprocessor_defines.config`, `.build/OUT/`) to VMB (`general_tweaker.mod`, `itemV2.cfg`, `bundleV2/`). Workshop ID `3713619122` and internal mod ID `"gt"` preserved — existing user settings are unaffected.

`itemV2.cfg` set to `visibility = "private"` (overriding the prior local `upload/item.cfg` which had `"public"` — never re-asserted on Workshop because no upload was performed during the migration).
