> [!WARNING]
> ⚠ **SUPERSEDED** — this snapshot is from 2026-07-17 (16 days old).
> Recent state may differ. Kept for historical context — verify against current
> code before acting on findings. Remove this banner manually after a refresh
> or move the doc to `_archive/audits/2026-07-17/`.
# Major open/closed regression audit, part 2 — 2026-07-17

## Scope and corrections

This is the second batch of 20 open `0-critical`/`1-major` issues, selected after
the first report's issues and its explicit exclusions. Evidence was refreshed
from GitHub issue bodies/comments, all closed issue threads, current
`origin/master` at `a717755`, repository history, production code, runtime checks,
and engine-free QA.

Two exact lifecycle defects were corrected while auditing:

- #139 was moved from `verify-fix-coop` to `diagnostics-armed` plus
  `coop-required`. Its latest user report says the previous fix regressed or
  never worked, asks for better diagnostics, and requires two players.
- #469 lost `verify-fix`. Its own latest status says the requested reduced-gas
  scalar is unbuilt. `PROJECT_STANDARDS.md` section 11 forbids a verify label on
  a partially delivered feature.

No issue was closed and no production code was changed.

## Evidence table

| Issue | Current evidence/state | Related closed work and commits | Regression/staleness finding | Current gap |
|---|---|---|---|---|
| [#505](https://github.com/Ensrick/vermintide-2-tweaker/issues/505) Single Mission Loader redesign | Current CT code has `single_mission_loader_redesign_505`, a data-driven mission catalog, `morris_hub` gate, Helmgart/DLC/Event/CW categories, curse-driven theme, existing Starting Boons, and percentage-safe catalog localization. Integrated commit `f2eeef1` is the current-history implementation; `6c242ce`/`cad2b10` are branch/integration variants. | Closed #305 established safe mission-selection ownership and context boundaries, but not the Deus one-node loader. Open #564 is the percentage-localization sibling, not closed proof. | **Verification backlog, not stale code.** The rejected first design was replaced rather than patched around. | One eyes-on Pilgrimage Chamber pass must prove the rendered catalog, chamber-only hotkey, Adventure/CW launch, curse, and selected multi-boons agree with the code contract. |
| [#590](https://github.com/Ensrick/vermintide-2-tweaker/issues/590) level lookup overflow | `42ce9a0` is on master. Duplicate graph choices now use `config.LEVEL_ALIAS` rather than new `LevelSettings`/`NetworkLookup` rows. Blocking `qa/check_level_lookup_budget.ps1` computes 792/1024 with 232 headroom and is wired into release gating. | No closed issue proves this exact fixed-capacity seam. Open #457/#487/#458 share `_adventure_pool.lua`; their behavior tests are the appropriate companions. | **Emergency regression corrected; verify-only.** The first #458 pool strategy caused the startup CTD, was rolled back, then replaced by bounded aliasing. | Need a clean launch/keep entry plus a restricted-pool start-shrine run. The static budget also needs deliberate refresh if a game update changes the vanilla prefix/capacity. |
| [#458](https://github.com/Ensrick/vermintide-2-tweaker/issues/458) Buy Starting Boons shrine | The first implementation caused #590, then co-op exposed `_shop_config=nil` on the client. Integrated `9634fd9` prepares/validates config before full sync, gates host SHOP publication, and fails closed to MAP_DECISION. | Closed #556 covers authored starting-boon catalog behavior, not shop ordering. Closed #425/#506 provide the peer transition/parity acknowledgement lesson used to suppress false roster degradation. | **Confirmed two-stage regression, current candidate awaiting co-op.** Both pool capacity and client config ordering were real failures found after initial shipment. | Host/client proof must show both shop views render, purchases work, Ready returns to MAP_DECISION, no nil config, and no transient false missing-mod warnings. |
| [#557](https://github.com/Ensrick/vermintide-2-tweaker/issues/557) settings layout | Stable/dev share `_mod_tweaker_ordering.lua`; `test_mod_tweaker_ordering.lua` proves group-first/loose-second localized sorting while retaining whole subtrees and explicit authored order. Both standalone and keep sub-state consume it. | Closed #339 fixed the broader category/collapsible ownership error. Closed #559/#497 prove search must not corrupt authored collapsible state. | **Candidate systemic fix, not a known recurrence.** This is one of the stronger examples of replacing row patches with a pure tree policy. | Human verification across nested real mod tabs is still required; authored headers, dependencies, synthetic Equipment ordering, and duplicate localized labels need eyes-on coverage. |
| [#406](https://github.com/Ensrick/vermintide-2-tweaker/issues/406) kill-heal client CTD | CT dev registers the proc with `authority="server"` and still explicitly returns unless `Managers.player.is_server`; Khaine's Communion is catalogued once under Modded Boons. `daea16f` is integrated; `test_ct_boon_catalog.lua` covers discovery. | Closed #405 is the exact `DamageUtils.heal_network` sibling: Fires from Ash was fixed by the same server-authority rule. | **Direct sibling fix awaiting co-op.** Navigation was separately repaired after the safe proc became hard to find. | Need a client holding the boon to get a kill and receive healing without `Only server can heal`; add/retain an engine-free authority test, not only a catalog test. |
| [#484](https://github.com/Ensrick/vermintide-2-tweaker/issues/484) crafted Old Musket identity/pose | The issue is still diagnostics-only. Its last evidence says a skinless crafted backend instance resolves base `es_handgun`, so skin-keyed transforms miss; the old bayonet is still a live attachment system. #279 diagnostics are the current evidence path. | Closed #390 fixed crafted owner identity generally; #397 claimed husk transform parity; #409 fixed Musket inventory pose; #617 verified Athanor custom preview. Closed #486 only collected logs. | **High-confidence appearance regression family.** Crafted Musket still bypasses multiple closed surface fixes because backend instance identity and skin are not canonical. | Need fresh crafted-Musket logs showing final backend ID, item/skin descriptor, attached bayonet unit, 1P/3P transform readback, and remote resource identity. |
| [#413](https://github.com/Ensrick/vermintide-2-tweaker/issues/413) Shadow weave in Adventure | `52c664e`/`c64457e` deliberately drop six weave-only mutators and emit one bounded host notice. Source evidence shows Shadow units exist only in weave level bundles and server code also lacks Adventure `light_radius`. | No closed issue makes weave-only Shadow functional in Adventure. Closed #294/#270 are relevant fail-closed residency precedents, but not feature completion. | **Crash contained; requested gameplay remains blocked.** The user's "no crash, no effect" result is expected for the safe floor, not evidence that Shadow now works. | A product decision remains: all-modded custom asset port, host-only resident reimplementation, or permanent documented exclusion. Current solo verification can prove only safe exclusion/notice deduplication. |
| [#148](https://github.com/Ensrick/vermintide-2-tweaker/issues/148) missing preview auto-zoom CTD | Cosmetics globally clears `_zoom_dirty` when `_unit_start_position_boxed` is nil before vanilla `LootItemUnitPreviewer.update` dereferences it. The clarified test identifies CIM Athanor and its automatic hover/select zoom. | Closed #617 covers custom Athanor package/icon residency; #539 covers a separate missing ItemId customization crash. Neither guards this vanilla missing-link-unit zoom branch. | **Old candidate fix with weak automation.** No recurrence is recorded, but the guard appears only in the god file and changelog; repository search found no focused engine-free or runtime regression row. | Verify a reliably blank LA preview without CTD, then extract/test the policy so future preview refactors cannot silently drop the guard. |
| [#139](https://github.com/Ensrick/vermintide-2-tweaker/issues/139) bots teleport away from downed player | `9978e9f`/`2ae9f21` were once user-confirmed, but the user later reported recurrence and explicitly requested better diagnostics. Existing runtime rows prove predicate/hook presence, not live selector/teleport interaction. Lifecycle corrected to co-op diagnostics. | Closed #261 constrained objectives; #383 fixed split movement/leash anchor mismatch; #492 adds unreachable-aid bailout. Those adjacent changes can conflict with the same selector/veto seam. | **Highest-confidence behavior regression.** A prior verified case resurfaced, and the old probes observe the current follow target after it changes, making them structurally blind to the abandoned ally. | Diagnostics must record pre-switch assigned ally, selector reason, full disabled/rescue state, teleport reason/destination, and which follow-unit copy the leash reads, as one bounded transition record. |
| [#491](https://github.com/Ensrick/vermintide-2-tweaker/issues/491) pairing skins leak | Current thread documents exact coverage by closed #495: `_custom_skin_keys` plus `cwv_` fallback and all three equipment senders, parity-gated with forced hot-join null. | Closed #495 is the same issue and was co-op verified. Closed #475 is appearance behavior dependent on compatible-peer skin delivery. | **Stale duplicate tracker.** There is no distinct unresolved sender in #491's current evidence; the accepted initial-base-display residual belongs to #474 presentation. | Re-run #495's mixed/all-CWV test on current code; if it passes, record patch equivalence and close as duplicate. If it fails, the receiver stack must identify a genuinely fourth sender. |
| [#469](https://github.com/Ensrick/vermintide-2-tweaker/issues/469) bot hazard protection | Binary host-only immunity shipped for a curated Lightning/Skulls/Bolt/oil set. Gas was deliberately excluded even though the issue requests reduced gas damage. | Closed #129 is an AoE/lightning reliability lesson, not bot immunity. No closed issue proves source classification or gas scaling. | **Partial feature; stale verify label removed.** The existing toggle cannot satisfy the complete issue while reduced gas remains unbuilt. | Add a bounded gas scalar with exact damage-source provenance, preserve excluded boss/warpfire/bomb behavior, and then test on/off plus gas reduction before restoring verification status. |
| [#490](https://github.com/Ensrick/vermintide-2-tweaker/issues/490) stable GT world-liveness port | Stable `general_tweaker` now contains the #459 `has_world`, cached-world identity, boss-sphere fail-closed guards, and resident `gw_fonts` material via `871c18f`. This is an intentional stable promotion exception. | Closed #459 is the exact dead-world/native access-violation source. | **Promotion backlog resolved, awaiting stable runtime proof.** No evidence suggests the port diverged from dev. | Exercise debug HUD/line/boss-sphere paths across repeated keep/mission/restart transitions and compare stable guard/test parity with dev. |
| [#384](https://github.com/Ensrick/vermintide-2-tweaker/issues/384) aid errand flicker gap | `c4591e3` widens the backstop to `side:player_units()` and the full disabled/awaiting-rescue predicate while retaining #492 bailout. Runtime `gt_bot384_needs_aid_or_rescue_predicate` exists. | Closed #261/#383 are upstream anchor/selection fixes; closed #492 is the deliberate unreachable-aid escape. #139's own previous fix is the direct lower seam but has now regressed. | **Verification suspect because parent #139 regressed.** #384 may be correct in isolation while another selector/follow copy still causes the same visible teleport. | Co-op evidence must correlate the widened predicate, assigned ally, veto, and actual teleport. Do not close from predicate PASS alone while #139 remains diagnostic. |
| [#662](https://github.com/Ensrick/vermintide-2-tweaker/issues/662) infinite-ammo startup errors | Contrary to its stale 06:27 comment, `d4c1561` is now an ancestor of current master and deployed as GT dev 0.2.242-dev. `_gt_network_readiness.lua` uses network-game gating plus pcall-contained `local_player_safe`; `test_gt_network_readiness.lua` covers unavailable/throwing/ready states. | Closed #508 is the exact pre-backend `local_player_safe` family; closed #609 covers queries after network teardown. | **Tracker comment stale; code integrated and verify-ready.** This also demonstrates #625's stranded-branch risk was real before integration. | Solo startup log must prove silence before readiness and correct ammo ownership afterward. Remaining bare `local_player()` callers should migrate to the same helper in a separate bounded sweep. |
| [#625](https://github.com/Ensrick/vermintide-2-tweaker/issues/625) stranded agent branches | The original #528 witness is patch-equivalent via `4ecb24a`; #653 and #662 were later merged into current master, disproving the latest comment's present-tense claim while validating its risk. No generated branch-by-branch disposition artifact or gate was found. | No closed issue completes branch reconciliation. #528 is a resolved patch-equivalence example, not proof the census is done. | **Open tooling/process gap with stale examples.** Work has happened manually, but the required full census and disposition contract remain unbuilt. | Generate machine-readable ancestry/patch-id/issue/path/ship evidence for every branch, manually adjudicate semantic overlap, and gate abandonment on a recorded disposition. Tooling must be self-verified, not human `verify-*`. |
| [#518](https://github.com/Ensrick/vermintide-2-tweaker/issues/518) LA cosmetics override CW upgrades | `2dc9d0c` mitigation distinguishes `morris_hub` from active expedition: LA stays in staging, Deus rolled skins win in missions. The root is still template-scoped committed picks rather than per-backend-instance state; LA-in-upgrade-pool remains additional scope under #660. | Closed #563 proves primary illusion persistence, but not per-instance ownership. Closed #89 addresses in-mission preview context, not Deus precedence. | **Mitigation verify-ready; architecture remains unresolved.** This is direct evidence that a global/template override can appear correct on some surfaces while violating item-instance semantics. | Verify staging/mission/upgrade/return behavior, then migrate committed LA selection into the canonical per-instance descriptor and separately design pool injection without overriding Deus output. |
| [#273](https://github.com/Ensrick/vermintide-2-tweaker/issues/273) CWV converts to career default | Log evidence pins vanilla `DeusStartingWeaponTypeMapping[cwv_*]` miss. Current CWV `_cwv_deus_identity.lua` derives exact identities for all-CWV lobbies and vanilla family fallback under unknown/mixed parity; deployed 0.1.412-dev. | Open #105 is the same vanilla-run re-resolution class for a WT cross-career longbow. Closed #592 proves CWV acquisition remains CIM-owned and prevents the Deus mapping fix from auto-granting instances. | **Candidate systemic identity fix awaiting co-op.** The issue is not CIM restoration and should stay owned by CWV's Deus adapter. | Verify exact item/illusion through entry, upgrades, transitions, reconstruction, previews, and remote views; also verify mixed lobby degrades to vanilla dual-axes family rather than single axe. |
| [#457](https://github.com/Ensrick/vermintide-2-tweaker/issues/457) mission availability groups | CT contains DLC/Helmgart/CW/Event masters and advanced per-mission children; runtime `mission_availability_groups_457` is documented. Pool underflow shares #487/#590 code. | No closed issue proves this exact menu/pool contract. Closed #339 supplies only the parent/child GUI organization lesson. | **Feature UI appears complete; end-to-end result is coupled to an open regression.** Menu verification can pass while the underflow run still freezes. | Verify tree/master semantics independently, then run zero/one/four-mission graph cases with #487 diagnostics and #590 capacity gate evidence before closure. |
| [#271](https://github.com/Ensrick/vermintide-2-tweaker/issues/271) Devious Delvings brightness | Integrated `eff4c39` sets `_CURSE_MAP_BRIGHTNESS.dlc_termite_2["*"]` to 2.0 for four interior levers while leaving sky/sun/fog profile-owned. | Closed #66 fixed curse tint failing on the same native CW path; open #243 is the Belakor-darkness facet. Closed #68 is map-node presentation, not lighting. | **Visual verify backlog, no reported regression.** Correct map key and shared brightness seam are source-backed. | Use #505 loader for side-by-side cursed captures, verify 2x readability without washout, and tune only the per-map multiplier if it overshoots. |
| [#258](https://github.com/Ensrick/vermintide-2-tweaker/issues/258) Well of Dreams Tzeentch brightness | `eff4c39` correctly maps Well of Dreams to `dlc_termite_3` and applies `ambient_tint_top=2.0` only for Tzeentch. | Closed #66 established curse-lighting application; #68 established native CW path alias/presentation. Open #257 independently probes Well of Dreams fade behavior and must not be conflated with ambient lighting. | **Visual verify backlog, no reported regression.** | Load exact level/theme through #505, compare navigability and curse identity, then inspect runtime shading values if the visual result disagrees with the table. |

## Three empirical next approaches per issue

### #505

1. Run one Pilgrimage Chamber session covering each catalog category, curse, and
   multiple Starting Boons; retain the `[ct:505]` row.
2. Compare every displayed mission key with its owned/unlocked source row and
   declared valid paths.
3. If launch fails after catalog validation, instrument only the final composed
   level key and `debug_load_deus_level` result.

### #590

1. Run the blocking budget check, launch, and enter the keep on the deployed build.
2. Exercise repeated settings reloads and assert lookup length never grows.
3. If startup still overflows, dump only the newly appended level keys and assign
   ownership before changing the 1024-cap model.

### #458

1. Complete the two-player config-before-SHOP ordering test with both logs.
2. Add a deterministic test where client config registration is delayed past host
   intent and prove MAP_DECISION fail-closed behavior.
3. If native full-sync can still outrun the guard, move readiness to the session
   admission/state publication boundary rather than delaying the view.

### #557

1. Inspect nested real tabs and Equipment in stable and dev.
2. Feed duplicate labels, headers, dependencies, and deep subtrees into the pure
   ordering test.
3. If a row remains loose, dump its original VMF depth/parent metadata and fix
   tree reconstruction rather than adding a tab-specific order exception.

### #406

1. Have a client kill with Khaine's Communion and retain both logs.
2. Execute the proc function in an engine-free client/server authority fixture and
   assert `heal_network` is called exactly once on server.
3. If healing is missing rather than crashing, trace buff ownership/event routing
   without removing the server gate.

### #484

1. Re-run a freshly crafted Old Musket with #279 diagnostics and all render views.
2. Resolve the item through one backend-ID appearance descriptor, including an
   explicit bayonet-enabled field and complete pose.
3. If a later attach owner overwrites it, log final spawned units/readback at that
   seam and reconcile there once.

### #413

1. Verify current exclusion and one-line notice after a full Steam restart.
2. Prototype a host-only resident-resource reimplementation in an isolated test,
   never using the weave-only unit IDs.
3. If visual parity is mandatory, require all-peer package parity and pre-hot-join
   containment; otherwise keep the option unavailable in Adventure.

### #148

1. Hover/select a blank LA Athanor preview and confirm the automatic zoom no longer
   crashes.
2. Extract the nil-start-position decision into a pure policy test.
3. If another preview field is nil, fix preview spawn readiness upstream and retain
   this final defensive floor.

### #139

1. Arm transition diagnostics that retain the pre-switch downed ally identity and
   teleport cause; reproduce with two humans and bots.
2. Disable split assignment while retaining the veto, then invert the experiment,
   to identify which owner reintroduces the teleport.
3. If vanilla writes a second follow target after the mod, consolidate both copies
   at the authoritative AIBotGroupSystem assignment seam.

### #491

1. Re-run #495's mixed/all-CWV equip, resync, and hot-join matrix.
2. Enumerate all `rpc_add_equipment` senders and assert each uses the common skin
   policy.
3. If no leak exists, document patch equivalence to #495 and retire this duplicate
   without moving its presentation residual into wire safety.

### #469

1. Identify the exact gas damage source/profile and add a host-owned reduction
   scalar.
2. Test every curated immune source plus explicitly excluded sources and gas.
3. If source names vary by mode, classify from source-backed damage metadata and
   fail vanilla-safe on unknowns.

### #490

1. Run stable debug drawing across repeated world transitions.
2. Diff stable/dev world guard and material assertions in QA.
3. If a native crash recurs, capture cached/current world identity and exact draw
   owner; do not wrap a dead-world native call in `pcall`.

### #384

1. Correlate assigned ally, full need state, veto, watchdog, and actual teleport in
   the same co-op trace.
2. Test knocked, awaiting rescue, and each disabler state as table cases.
3. If state flicker remains, lease the aid errand across bounded transient loss and
   release only on recovery/death/watchdog bailout.

### #662

1. Launch with both Infinite Ammo saved states and verify no pre-backend errors.
2. Exercise command/Godmode ownership composition after readiness.
3. Migrate only empirically unsafe remaining callers to the canonical readiness
   helper and test startup plus teardown.

### #625

1. Generate the complete local/remote branch register with issue refs, patch IDs,
   paths, ancestry, and ship evidence.
2. Classify each non-ancestor using patch equivalence followed by semantic current-
   source review.
3. Add an abandonment/handoff gate requiring one recorded disposition, while
   keeping stale branch versions out of bulk merges.

### #518

1. Verify LA present in keep/staging, Deus skin in mission/upgrade, LA restored on
   return.
2. Migrate selection from template storage to per-backend canonical descriptors.
3. Add LA skins to the upgrade candidate pool with owned-DLC filtering rather than
   applying them as post-roll overrides.

### #273

1. Run exact all-CWV and mixed-parity entry/upgrade/transition matrices.
2. Test every concrete CWV owner mapping for exact identity and vanilla-family
   degraded identity.
3. If reconstruction still collapses, log the first boundary that replaces the
   dedicated Deus row and fix that adapter.

### #457

1. Verify masters and advanced child lists without starting a run.
2. Run zero/one/four-enabled pool cases with #487 begin/end diagnostics.
3. If UI and runtime diverge, serialize the selected mission set once at setup and
   compare it to the pool consumed by the graph solver.

### #271

1. Capture before/after Devious Delvings under the same curse and display settings.
2. Log resolved map/theme multipliers once at shading initialization.
3. If too bright, adjust only `dlc_termite_2["*"]`; if unchanged, trace which
   shading owner overwrites the callback result.

### #258

1. Capture Well of Dreams specifically under Tzeentch via #505.
2. Verify final `ambient_tint_top` multiplier/readback without mixing in #257 fade
   events.
3. If unchanged, trace level alias normalization to ensure `dlc_termite_3` reaches
   the table; if washed out, reduce only that theme/channel multiplier.

## Highest-confidence findings

1. **Bot aid regression: #139, with #384 at risk.** A previously verified fix is
   user-reported broken again, and existing probes lose the abandoned ally identity
   before logging. #384 shares the same veto seam and cannot be validated by a
   predicate PASS alone.
2. **Crafted Musket identity fragmentation: #484.** Closed #390/#397/#409/#617
   each cover a surface, yet the crafted backend instance still resolves as base
   Handgun, misses transforms, and carries the legacy attachment.
3. **Feature-completion drift: #469.** A useful partial toggle was put into the
   human verification queue while an explicit requested gas behavior remained
   unbuilt; the label was corrected.
4. **Process state drift: #625/#662.** #625 correctly identified stranded fixes,
   but its latest concrete #653/#662 claims became stale after both were integrated.
   The missing automated branch disposition report is the durable issue.

The Chaos Wastes cluster #590/#458 is a different pattern: its first shipped
attempts genuinely regressed, but current code directly addresses the two observed
failure boundaries and is now a coordinated verification backlog rather than an
unworked regression.
