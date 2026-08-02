> [!WARNING]
> ⚠ **SUPERSEDED** — this snapshot is from 2026-07-17 (16 days old).
> Recent state may differ. Kept for historical context — verify against current
> code before acting on findings. Remove this banner manually after a refresh
> or move the doc to `_archive/audits/2026-07-17/`.
# Major open/closed regression audit — 2026-07-17

## Scope and method

This is a read-only audit of the 20 most recently updated open issues carrying
`0-critical` or `1-major` at the time of capture, with #660, #663, #664, #611,
#613, and #632 excluded by assignment. In practice, all 20 selected issues were
`0-critical`. The evidence set was:

- each issue's current body, labels, and complete comment thread from GitHub;
- all closed issue bodies and comments, searched for explicit references and
  matching engine/subsystem boundaries;
- current `origin/master` at `a5a8a82`, including the integrated ancestry
  through `13f10c5`;
- issue-referencing commits from all local refs; and
- current production code, runtime checks, engine-free tests, changelogs, and
  regression checklists.

"Related" below means there is a concrete shared sender, receiver, state owner,
resource boundary, or lifecycle seam. Superficial title similarity was not
treated as evidence. A closed issue is not presumed to remain fixed merely
because it was closed, and an open issue is not presumed to be a regression
unless the current report crosses a boundary that a closed issue claimed to
cover.

No GitHub labels were changed. The apparently unusual combinations in this set
are evidence-backed: #424 has a verified crash floor but a blocked product
decision; #470 is testable only after its still-open #487 blocker; and `Fixed`
on open #649/#402 denotes the repository's post-fix due-process state rather
than a competing `verify-fix` lifecycle. The mutually exclusive solo/co-op
verification rule is satisfied by every selected issue.

## Evidence table

| Issue | Current evidence/state | Directly related closed work and commits | Regression/staleness finding | Current implementation or diagnostics gap |
|---|---|---|---|---|
| [#423](https://github.com/Ensrick/vermintide-2-tweaker/issues/423) cloned damage profile CTD | Shipped and waiting for a mixed-mod two-player test. `_cwv_damage_profile_wire.lua` owns the single `WeaponSystem.send_rpc_attack_hit` choke; runtime check `cwv_wire_safe_damage_profile_gate` and `qa/lua/tests/test_cwv_damage_profile_wire.lua` exist. | Closed #422/#654 prove the same sender-shadow rule on `rpc_sync_loadout_slot`; closed #495 proves the adjacent skin sender rule. Direct commits: `d590c16`, `f4e0b9a`/`5a83157`, bundle refresh `11241b7`. | **Not stale; verification backlog.** This is the damage-profile axis of the same custom-lookup family, not a recurrence of the closed item/skin axes. | No code gap identified for current CWV producers. Missing evidence is paired logs proving vanilla substitution with a non-CWV host and tuned behavior with all-CWV peers. |
| [#661](https://github.com/Ensrick/vermintide-2-tweaker/issues/661) career abilities fail on modded weapons | New umbrella. Current master now contains provider-neutral action integration in `13f10c5`: `_lib_career_weapon_actions.lua`, alternate ability-row coverage, WT stable/dev consumers, WOC consumer, and `test_shared_career_weapon_actions.lua`. | No closed issue proves this exact weapon-template action contract. Closed #536 is only an adjacent empty-wield/reload network patch; #425 is a buff wire-safety gate, not local action selection. Open #374/#388/#412 are correctly separated career-key/chain/state families. | **High-confidence regression family, candidate fix newly integrated.** The old WT path mutated shared `Weapons[template].actions` and historically examined only part of the ability matrix; provider timing and repeated restore/reapply made recurrence plausible. | `13f10c5` has not yet supplied the issue's live affected-career/weapon matrix or deployed-build evidence. Tests cover collection/install and stable/dev/WOC use, but not a full mission-transition/respawn/hot-reload input rejection matrix. |
| [#630](https://github.com/Ensrick/vermintide-2-tweaker/issues/630) DX12 fence timeout | One dump proves a renderer-thread `WaitForSingleObject` timeout in `D3D12RenderDevice::end_frame`, healthy memory, and no Lua exception. It is correctly `diagnostics-armed`, but repository search found no #630-specific bounded probe. | Closed #76 is the nearest direct ancestor: Mod Tweaker renderer recreation and repeated-open lifecycle. Closed #193/#363 are renderer/material crashes, but their Lua/native signatures differ and must not be reused as the diagnosis. | **Possible recurrence of view ownership, not proven.** The signature is a new GPU fence-timeout class, so #76's renderer-lifecycle lesson applies without claiming the same cause. | No instrumentation yet distinguishes UI world/render-target double ownership, preview-unit/package lifetime, focus transition, or unrelated GPU/driver stall. `BUG_CLASSES.md` also lacks this exact fence-timeout class. |
| [#487](https://github.com/Ensrick/vermintide-2-tweaker/issues/487) Chaos Wastes initialization freeze | The enabled-mission duplication floor shipped, then the user reproduced the freeze again. `_ct_diag_freeze487.lua` and `_adventure_pool.lua` retain bounded `GRAPH-SOLVE`, `POOL-FLOOR`, and frame-stall evidence. Commit `c989a0e` added the diagnostic; later pool-floor work is documented in CT changelogs. | No closed issue proves this exact graph-solver boundary. Open #457/#505 share the mission-pool/loader surface. Closed #386 is a ConflictDirector initialization failure, a different producer. | **Confirmed stale fix hypothesis.** The one-mission underflow fix was insufficient because the freeze recurred after it shipped. The issue is correctly back on diagnostics. | The decisive failing log still must establish whether `GRAPH-SOLVE begin` lacks an end, returns nil/slow, or completes before a later frame stall. The current issue thread has not pinned that boundary. |
| [#279](https://github.com/Ensrick/vermintide-2-tweaker/issues/279) crafted CWV merged model | Diagnostics show the owner-side `ammo_unit` clear can work while the husk path resolves the base item with `backend_id=nil`, reattaching the source ammo mesh. Commit `d9f06af` added the remote decision probe. | Closed #390 fixed CIM-crafted CWV base identity for owner presentation by minting deterministic CWV backend IDs and rescuing units. Closed #397 claimed generic husk transforms. Closed #392 narrowed blacksmith/base resolution into dedicated surface issues. | **High-confidence cross-surface regression/coverage hole.** #390 fixed the crafted owner path, but the remote husk path independently re-derives the base descriptor and can compose two visuals. | Still needs the two-player `[cwv:279]` capture identifying career, strip-set membership, attached ammo unit, and exact final units. The durable fix belongs at the CIM synthetic descriptor/remote resolution contract, not another Outrider-only strip. |
| [#421](https://github.com/Ensrick/vermintide-2-tweaker/issues/421) custom illusion CTD | Cosmetics 0.9.105-dev uses explicit `M.install(owner)` in `_cos_wire.lua` and nulls custom skin identity at all three vanilla senders; the earlier missing-global startup regression is covered. Waiting for co-op verification. | Closed #495 is the same `rpc_add_equipment` skin axis in CWV and was co-op verified. Closed #270 proves receiver-side resource checks for hats, which remains a secondary floor rather than the wire fix. | **Not stale; direct sibling fix awaiting proof.** The 0.9.104 module-extraction regression was found and corrected before this audit. | Need paired mission/keep transition logs showing 0.9.105 loaded, no `_cos_wire` initialization failure, no custom skin on vanilla RPC, and correct compatible-peer replay. |
| [#278](https://github.com/Ensrick/vermintide-2-tweaker/issues/278) crafted CWV loadout CTD | Current code has both unconditional sender floors: CWV shadows `cwv_*` to its vanilla base in `sync_loadout_slot`; CIM rewrites modded rarity to vanilla `unique` outside the persistence toggle. Waiting for mixed-mod verification. | Closed #422/#654 are the exact WOC `rpc_sync_loadout_slot` shadow pattern; closed #495 covers the adjacent equipment skin sender. The original implementation history is recorded in the issue; the broad promotion-tool commit `330cd8d` is not itself the fix. | **Not stale; prior regression already corrected.** The first CIM sender floor was accidentally gated by a default-off persistence setting; the current code hoists it unconditionally. | Need a non-CIM/CWV client log proving both item and rarity IDs are vanilla-resolvable on equip/hot join. Runtime coverage exists, but there is no retained paired proof for the current public versions. |
| [#426](https://github.com/Ensrick/vermintide-2-tweaker/issues/426) CT boon/miracle CTD | Five CT grant/apply surfaces are parity-gated; hot join is fenced before native sync; parity-loss strips present players. Commits `728cf0b`/`e8d7ae7` plus bundle `4b22fee`; co-op test is documented. | Closed #425 is the direct buff-template sibling and was verified with a non-CRT peer. Closed #506 fixed shared parity callback ordering and was verified. | **Mostly verification-ready, with one concrete residual.** This is not a general regression of #425/#506; the remaining gap is CT run-state ownership after departure. | Departed-player run-state keys are not stripped. A player can leave holding a CT boon, leaving stored modded identity for a later no-CT join. That edge needs code containment before full closure even if ordinary co-op tests pass. |
| [#424](https://github.com/Ensrick/vermintide-2-tweaker/issues/424) thrown variant CTD | Unconditional projectile/husk/pickup substitution is shipped (`ffde7b9`, `544c711`) and protects the hot-join race. The user rejected substitution as the product-level mixed-lobby behavior, so the issue is both crash-floor verification and blocked feature policy. | Closed #422/#495/#654 establish sender substitution for keyed payloads; closed #425 demonstrates why a hot-join-safe floor must remain even when a feature is normally gated. | **Split issue, not a silent regression.** Crash prevention exists; requested automatic weapon disable is unbuilt. | Must choose and implement the mixed-lobby UX/runtime state: hide from loadout, block equip with a notice and base fallback, or suppress throw. The floor cannot be removed because no UI gate can cover already-equipped/hot-join state. |
| [#371](https://github.com/Ensrick/vermintide-2-tweaker/issues/371) repository-wide mixed-mod safety | Shared fail-closed `_lib_peer_parity.lua` exists, including #506's commit-before-callback ordering. Several keyed axes are shipped. The body already distinguishes verified, verify-only, and unbuilt surfaces. | Closed #270/#280/#294 are receiver/resource floors; #422/#425/#495/#506/#588/#654 are verified sender/gate/residency exemplars. Commit `544c711` introduced the shared beacon. | **Umbrella remains current.** Repeated per-subsystem fixes demonstrate missing enforcement/presentation, not failure of the shared beacon itself. | Missing generic network-unsafe registry, GUT grey/disabled row and missing-peer popup, VMF hiding, CI lint for new custom IDs/resources/RPC payloads, generalized pre-hot-join containment, and enemy Warlord breed parity gate. |
| [#604](https://github.com/Ensrick/vermintide-2-tweaker/issues/604) Crowbill family | Latest user result says Dawi custom model is absent remotely and `-90/-90/-90` is missing in owner 1P. Eight issue commits attempted model family, preview lifetime, transforms, durability, scale, and remote synchronization (`d94365e` through `1c256ec`). Tests exist in `test_cwv_crowbill_family/runtime/mod_unit_preview.lua`. | Closed #606 verified Bardin Crowbill inventory idle; closed #397 verified a generic husk transform case; closed #576 corrected a falsely confirmed Crowbill tuner-port audit. These claims do not cover custom model identity plus owner 1P. | **Highest-confidence recurring appearance regression.** A new custom family bypassed surfaces that closed generic issues claimed to normalize; registration/test assertions did not prove final spawned resource and retained transform. | Need final resource-name and readback evidence for owner 1P, owner 3P, inventory item/hero previews, remote husk, transition, swap, respawn, and hot join. Existing tests prove declarations and helper invocation, not end-consumer state. |
| [#430](https://github.com/Ensrick/vermintide-2-tweaker/issues/430) package curse CTD | Event Tweaker 0.4.35-dev has a pre-sync session contract: drop curses if parity is missing before start, reject incompatible hot join while an unsafe curse is active, reopen when curses clear. `test_event_curse_join_policy.lua` exists; bundle `755deee`. | Closed #425 is the direct parity-gate exemplar. Closed #270/#294 prove fail-closed resource residency. Open #413 remains the separate weave-only Adventure package class and must not be cited as closed proof. | **Candidate fix awaiting co-op proof.** Earlier ordinary roster gating was insufficient; the active-session join contract is the new containment boundary. | Need both negative paths in paired logs: no-ET peer present before start (curse dropped), and no-ET hot join during active curse (join refused before game-object sync), plus re-open after curse removal. |
| [#653](https://github.com/Ensrick/vermintide-2-tweaker/issues/653) nil `ally_distance` crash | GT 0.2.241-dev is deployed; the patch preserves `math.huge` for no-target distance and bounds missing custom numeric utility input. Bundle commit `395438f`; runtime test `gt_bot_utility_nil_guard` is documented. | Closed #59 is the strongest related lifetime/input lesson: a first-tick missing BT health operand is guarded before arithmetic. Closed #492 concerns bot aid-branch lock, not this nil producer. | **Fresh defect, not proven regression.** Same invalid-input bug family as #59, but a different hook and blackboard value. | Needs solo runtime proof through target changes/leash teleport and an offline source-level assertion that the Creature Spawner hook no longer globally changes unrelated vanilla bot utilities. |
| [#649](https://github.com/Ensrick/vermintide-2-tweaker/issues/649) Helmgart statistics crash | Commit `9da5f2e` guards only missing completion-stat leaves in the mission-selection career iteration. `test_gut_mission_completion_policy.lua` exists. Rain attached a log and explicitly confirmed the issue fixed; `Fixed` is appropriate pending close due process. | Closed #581 is the direct `StatisticsDatabase` ownership-boundary lesson: mod-owned synthetic keys must not be evaluated by vanilla. #649 applies the analogous definition-existence boundary to a third-party career. | **Resolved in evidence; tracker completion is stale, not code.** No recurrence is reported after the targeted guard. | Before closure, reconcile the unrelated failing rows Rain mentioned from `/gut_regression_test`; confirm none weakens the mission-completion invariant, then record post-fix documentation/contingencies. |
| [#474](https://github.com/Ensrick/vermintide-2-tweaker/issues/474) Old Musket surfaces | Current CWV has a bounded stance channel, canonical preview descriptor, remote/cache replay, custom audio, and surface-coverage tests. Latest issue note says in-game surfaces are ready for co-op while CIM consumer residual is tracked separately. Commits `bedc691`/`bb3b850` and preview `1e2daf9`. | Closed #397 verified generic husk transforms; #409 addressed Musket inventory preview; #617 verified Athanor custom preview resources; #495 verified compatible-peer skin replay. | **High-confidence recurrence family with partial systemic repair.** The same weapon repeatedly escaped owner/husk/inventory/Athanor contracts. Current coverage is stronger but still assertion-heavy. | Paired runtime matrix remains: model identity, full transforms, melee/ranged animation state, audio, preview, transition, hot join, role reversal. The issue must not absorb CIM Athanor consumer work if that is tracked elsewhere. |
| [#524](https://github.com/Ensrick/vermintide-2-tweaker/issues/524) duplicate CWV blacksmith selectors | Three fixes (`a446e57`, `3e2d1b7`, `461691b`) attempted template restoration, craft-selector hardening, and bounded selection. Duplicates recurred, so CIM 0.8.84-dev now logs the final post-injection render list in `_cim_diag_524.lua`. | Closed #390 made per-key deterministic CWV crafting; #392 closed blacksmith/base identity; #592 removed auto-granted instances. These are precisely the producer contracts that should prevent inventory instances becoming selectors. | **High-confidence stale fix/late-stage seam gap.** Earlier tests covered the catalogue/template layer, but the visible duplicate exists after final injection or authored soft-duplicate composition. | Need the one bounded final-render dump from the native Craft Item picker. Then distinguish hard duplicate backend/template entries from intentional definitions sharing `item_type`; fix the upstream producer selected by that evidence and add a render-list cardinality test. |
| [#640](https://github.com/Ensrick/vermintide-2-tweaker/issues/640) deleted poison source | `01b05e6`/`482f00a` add `Unit.alive` before owner/breed native calls, neutral-factor early bypass, `issue640_personal_handicap_unit_lifetime`, and `test_et_personal_handicap.lua`. Waiting for a solo Globadier test. | Closed #59 is the nearest validated fail-before-native/invalid-input lesson; closed #270 similarly validates native unit/node guards, but neither owned this damage hook. | **Fresh lifetime bug with adequate code hardening.** No evidence that a closed Enemy issue regressed. | Need live lingering-cloud proof with neutral and non-neutral handicap, audit every adjacent native Unit access in the hook, and retain exact vanilla damage when the source cannot be authenticated as living hostile AI. |
| [#528](https://github.com/Ensrick/vermintide-2-tweaker/issues/528) CKC Options integration | The requirement changed: normal Options must be untouched. Commits `d95399a`/`4ecb24a` remove the bridge; `test_gut_ckc_options_isolation.lua` and runtime `issue528_ckc_vanilla_options_isolated` enforce absence. | Closed #360 is the same now-retired gear/cog surface and records that the cog is gone. Closed #527 only concerns Mod Tweaker organization and remains a separate owned surface. | **Resolved-by-retirement candidate; tracker completion is stale.** Earlier checkbox/cog fixes are superseded, not regressions to preserve. | Run the isolation row on the current deployed GUI, search built bundles for retired bridge symbols, and verify CKC remains configurable only on CKC/Mod Tweaker-owned pages. If all pass, due-process close rather than further geometry work. |
| [#470](https://github.com/Ensrick/vermintide-2-tweaker/issues/470) curse sorcerer rank-8 crash | Commit `1fe0052` unconditionally backfills only missing `max_health[8]` after mutator initialization; runtime `curse_sorcerer_rank8_backfill` exists. The issue remains blocked by #487 because verification requires a later progressive CW node. | Closed #59 is a related sparse/missing runtime-input guard, but not the same producer. No closed issue proves the Skulking Sorcerer data band. | **Candidate fix, not a recurrence.** The reported downstream `health_extension=nil` was traced to a vanilla sparse health table, and the patch is narrowly scoped. | First clear/capture #487, then verify a cataclysm_3 Skulking Sorcerer run, and inspect sibling curse-mutator rank arrays after every game update so the guard is not silently invalidated by source changes. |
| [#402](https://github.com/Ensrick/vermintide-2-tweaker/issues/402) official-realm loadout/frame leak | Commit `ff06327` added prevention/repair. Current stable/dev `_gut_native_loadouts.lua` owns `/scrub_official_loadouts` and runtime `native_loadouts_official_write_chokepoint`. User confirmation of repaired official data is still absent. | Closed #174 is the residual cloud-corruption ancestor; #375 introduced/then fixed seed repair; #379/#387 covered preview/switch consequences. The audit established `PlayFabMirrorBase.set_character_data` as the authoritative write choke for weapons and `slot_frame`. | **Historical regression family, prevention present; repair completion stale.** The code claims no new modded-to-official writes, but old cloud data persists until explicitly scrubbed. | Verify realm round-trip after scrub, make backend commit completion deterministic (current engine backlog notes the command relies on menu idle), and test weapon plus frame slots across official/modded transitions before closing. |

## Three empirical next approaches per issue

The first approach is the preferred next move. The second and third are bounded
fallbacks if the first result disproves the current hypothesis.

### #423

1. Run the documented mixed-host/all-CWV role-reversal test and compare the
   bounded `[cwv:423]` substitutions with the host's survival.
2. Instrument the final numeric `damage_profile_id` at the one sender choke and
   assert it is within the receiver's vanilla floor; do not add per-projectile
   logging.
3. If another RPC carries a CWV profile, extend the existing resolver to that
   empirically identified sender rather than registering indices opportunistically.

### #661

1. Deploy the `13f10c5` integration and capture an affected matrix with expected
   career action, final effective template, action identity, and input result.
2. Add lifecycle tests that run provider registration before and after WT,
   reconcile repeatedly, disable/re-enable, and prove only owner-injected rows
   are removed.
3. If the template contains the exact action yet input still fails, instrument
   the downstream career-action selection/rejection boundary and split that new
   mechanism from template reconciliation.

### #630

1. Reproduce repeated open/close and alt-tab with bounded creation/destruction
   IDs for UI worlds, renderers, render targets, preview units, and package leases.
2. Compare DX11 and DX12 using the same action script to isolate engine/backend
   dependence without changing Lua behavior.
3. If no ownership imbalance precedes the timeout, capture a fresh dump and GPU
   diagnostic state and classify it as an external renderer/driver stall rather
   than hiding it behind a Lua guard.

### #487

1. Reproduce as solo host and use the existing begin/end/nil/slow rows to locate
   the exact last completed graph boundary.
2. Feed the live filtered pools and solver validators into an engine-free
   deterministic graph fixture and assert every permitted pool terminates.
3. If graph solve completes, move the bounded probe one lifecycle step at a time
   through run-controller initialization until the first missing completion row.

### #279

1. Capture the remote-husk `[cwv:279]` decision with a crafted Outrider and prove
   which unit attaches the extra torpedo.
2. Make owner and husk resolve the same immutable synthetic appearance descriptor,
   then assert exactly one primary and one optional offhand/ammo unit.
3. If vanilla reattaches ammo after resolution, hook the single final attachment
   seam with a descriptor-owned suppression flag, tested against native Trollhammer.

### #421

1. Perform the 0.9.105 mixed-mod transition/hot-join matrix and retain both logs.
2. Assert every vanilla equipment sender sees a temporary nil/vanilla skin while
   the live local item remains unchanged.
3. If a new sender leaks, identify it from the receiver stack and route it through
   the same `_cos_wire` policy instead of another custom-skin allowlist.

### #278

1. Test a CIM/CWV host with a client lacking both mods across equip and hot join,
   checking item and rarity IDs at the final loadout sender.
2. Add an engine-free matrix for persistence off/on proving wire coercion never
   depends on the user setting again.
3. If a receiver still crashes, distinguish unknown item, rarity, property, and
   trait IDs from its exact decode stack before changing the sender shadow.

### #426

1. Add departed-player run-state stripping, then test leave-with-boon followed by
   a no-CT hot join and stale-ack rejoin.
2. If run-state ownership cannot be safely rewritten, reject the incompatible
   join before native run-state sync while preserving the host run.
3. If neither is proven safe, keep custom boons inert for any joinable session and
   emit one bounded reason without overwriting saved settings.

### #424

1. Implement the user-requested mixed-lobby disable as block-equip plus resident
   base fallback, while retaining unconditional sender substitution.
2. If equip cannot be intercepted reliably, hide choices while parity is negative
   and suppress the throw action for already-equipped/hot-join state.
3. If genuine projectiles can use vanilla-resident aliases without semantic loss,
   keep the weapon active but formally document/render the degraded identity.

### #371

1. Inventory every custom lookup/resource/network unit producer into one registry
   and fail CI when it lacks substitution or a registered parity fallback.
2. Build the generic GUT/VMF presentation consumer from the same runtime registry,
   including missing peer names and live join/leave refresh.
3. Exercise a mixed-version hot-join matrix across each axis and keep unprovable
   producers inert by default.

### #604

1. Log final spawned resource name plus transform readback at every required
   surface, starting with Dawi owner 1P and remote husk.
2. Route Crowbill identity/transform through the canonical appearance descriptor
   and one lifecycle reconciler rather than surface-local durable writes.
3. Add adversarial tests that simulate a later attachment-owner overwrite and fail
   unless the final settled model/pose matches the descriptor.

### #430

1. Run the documented present-before-start and active-curse hot-join rejection
   cases with a tester lacking ET.
2. Instrument the pre-game-object join decision once to prove rejection occurs
   before any package-bearing unit sync.
3. If that boundary is not authoritative, port the curse to resident vanilla
   resources or leave it disabled in joinable lobbies.

### #653

1. Run a solo bot mission through follow target changes and leash teleport with
   the deployed guard and runtime test.
2. Unit-test the utility wrapper against missing custom numeric, missing vanilla
   condition, false condition, and valid numeric inputs.
3. If nil is still produced, fix the `ally_distance` producer to preserve vanilla's
   `math.huge` sentinel and scope/remove the global consumer hook.

### #649

1. Review Rain's unrelated regression-test failures and record why none touches
   the mission-completion guard, then complete the issue's close process.
2. Add a Pusfume-like late career and a valid vanilla career to one test so the
   filter and identity path are exercised together.
3. If another stat leaf crashes, check exact definition ownership at that leaf;
   never globally suppress `StatisticsDatabase` errors.

### #474

1. Execute the complete two-player model/pose/mode/audio/preview/transition/hot-
   join matrix on the current deployed versions.
2. Compare every surface's resolved descriptor hash/resource/transform rather than
   only asserting that a helper was called.
3. If one consumer diverges, make it an adapter of the shared descriptor and delete
   its Musket-specific guess path.

### #524

1. Capture `_cim_diag_524` from the actual native Craft Item picker with the known
   duplicate inventory state.
2. Reproduce the captured final list in an engine-free injection fixture and assert
   exactly one five-power selector per authored item key.
3. If rows are intentional soft duplicates, expose their actual independent
   accessory/offhand identity rather than deduplicating by `item_type`.

### #640

1. Verify living and dead Globadier cloud damage with neutral and non-neutral
   handicap presets.
2. Sweep the hook for every `Unit.*`, owner, breed, extension, and position access
   and require a preceding lifetime predicate.
3. If a native assertion survives `Unit.alive`, derive authority from safe damage
   metadata or preserve vanilla damage instead of dereferencing the stale unit.

### #528

1. Run `issue528_ckc_vanilla_options_isolated` and scroll all vanilla Options pages
   on the current deployed build, then complete due-process closure.
2. Scan source and compiled resources for retired CKC bridge module/widget/material
   symbols as a build gate.
3. If integration reappears, remove the importing branch; do not revive the old cog,
   checkbox, redirect, or geometry patches.

### #470

1. After #487 yields a loadable run, reach rank 8 with Skulking Sorcerer and verify
   the backfill marker plus spawned enemy health.
2. Test the pure backfill predicate against sparse, complete, nil, and future-rank
   tables without mutating existing ranks.
3. Re-audit the decompiled mutator after updates; if Fatshark fixes the table, make
   the guard a no-op rather than overriding new authoritative values.

### #402

1. Run report/apply scrub in official realm, force a backend commit callback, and
   verify weapon/frame round trips across both realms.
2. Add a fake mirror test proving every official write choke is blocked in modded
   and every modded store write is inert in official.
3. If cloud corruption returns, log the exact writer and payload at the single
   PlayFab mirror choke and quarantine only unresolved/mod-only IDs.

## Highest-confidence regression families

1. **Appearance descriptor fragmentation — #604, #474, #279.** Closed #390,
   #397, #409, #606, and #617 each proved one surface, yet new/custom weapons
   still bypass owner 1P, remote husk, inventory, or Athanor consumers. Tests
   frequently assert registration or helper reach rather than final spawned
   identity and retained transforms.
2. **Craft selector producer/render seam — #524.** Three issue commits and closed
   #390/#392/#592 did not prevent visible 300-power instances from reappearing as
   selectors. The new final-render diagnostic is the first probe at the actual
   user-visible seam.
3. **Shared weapon-template action ownership — #661.** The newly integrated
   `13f10c5` is the first provider-neutral full ability-row helper. Until the live
   lifecycle matrix passes, repeated mutation/restoration of shared action tables
   remains a high-risk regression family.
4. **Mission graph initialization — #487.** The underflow fix shipped and the same
   freeze recurred. This is direct evidence that the original hypothesis or fix
   boundary was incomplete.

The wire-safety issues #423, #421, #278, #426, and #430 should not be folded into
those regressions merely because they are still open: their current code matches
closed, verified sender/gate patterns and primarily needs paired runtime proof,
with the departed-player state gap on #426 explicitly excepted.
