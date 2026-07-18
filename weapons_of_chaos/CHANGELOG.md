# Weapons of Chaos — Changelog

## 0.1.30-dev (2026-07-17) - #661 shared clone-action preparation [verify-fix]

- Replaced Blightreaper's one-off inherited-action repair with the shared
  WT/CWV/WOC clone-preparation primitive. It now also removes claim metadata
  copied from the Elf Sword donor before WOC claims the private template.
- Kept #690's exact provenance rule: only a donor row with canonical
  `ActionTemplates` identity is restored. Unknown provider rows still abort
  registration rather than being overwritten.
- Added offline coverage for copied claims, repeated preparation, provider
  release order, and foreign replacement.

**Solo verify:** Equip Blightreaper on Bardin and Kruber, use both career
abilities before and after swapping weapons, then run `/woc_regression_test`.
Registration must remain ready and no career-action conflict may appear.

## 0.1.29-dev (2026-07-18) - #712 authored render-node transform

- Corrected the stale node-0 diagnosis with two live-session proofs: the
  requested `{-90,-90,-90}` rotation, `-0.3` Z offset, and `0.9` scale reached
  WOC, but Stingray rejected the atomic write on the linked attachment root.
- Resolve the exact imported `blightreaper` render node on each 1P, 3P, husk,
  and preview unit and apply the canonical pose there. GearUtils retains sole
  ownership of attachment node 0.
- Extended the shared WeaponAppearance descriptor with an explicit transform
  node and bounded write-error reporting. Missing named nodes fail closed.
- Added structural coverage for owner 1P/3P, bot/husk, character and item
  previews, replacement units across mission transitions, root-write rejection,
  and retained-state repair. In-game and two-peer verification remain required.

## 0.1.28-dev (2026-07-17) - #690 Blightreaper registration regression

- Reconciled only deep-cloned career-action rows that can be proven to inherit
  the donor's canonical `ActionTemplates` identity. The v0.1.27 shared
  ownership guard now distinguishes those safe inherited rows from genuine
  provider conflicts instead of aborting Blightreaper registration.
- Added one-per-distinct-gate, 12-line-budget `printf` diagnostics for deferred
  registration. Retries remain limited to the existing keep/mission entry
  lifecycle boundary; no frame/update retry was added.
- Added offline integration coverage for the exact clone/identity failure and
  a live `issue690_blightreaper_registration_gate_contract` check.

**Solo verify:** start with Blightreaper enabled and More Items Library above
WOC. The log must contain `[WOC] registered Blightreaper`, CIM must not report a
missing `ItemMasterList` row, and `/woc_regression_test` must report
`issue690_blightreaper_registration_gate_contract` PASS with zero failures.
This fix is offline-verified only until that in-game evidence is attached.

## 0.1.27-dev (2026-07-17) - #661 shared career-action ownership [verify-fix]

- Registered Blightreaper career actions through the shared WT/CWV/WOC claim contract so another provider cannot remove a still-required ability row.
- Expanded the shared matrix for alternate rows, release order, external replacement, repeated reconciliation, and conflicts.

**Solo verify:** equip the Blightreaper on at least two careers, use every career ability before and after a weapon swap, and run `/woc_regression_test`. The career-action check must pass.

## 0.1.26-dev (2026-07-17) - #613/#632 mission replay, Shyish, and career actions [verify-fix-coop]

- Preserved 0.1.25-dev's atomic `Unit.set_local_pose` linked-root transform and
  durable retained-state owner. Added exact-relic `BackendUtils.get_item_units`
  replay before owner, husk, character-preview, and item-preview recipes so a
  mission transition cannot silently rebuild Blightreaper with the inherited
  normal-Sword unit descriptor.
- Added bounded requested/returned unit diagnostics without replacing the
  atomic transform lifecycle or its WT-dev tuner-yield boundary.
- Repaired Shyish at the earliest logged failure: the source-backed package's
  loaded reference now gates spawn, and contact reproduces `mutator_death.lua`
  with host `death_explosion` damage followed by a `mutator` heal for accepted
  damage, yielding THP while preserving one green health.
- Added all ten weapon-bound career ability actions used by the nine applicable
  careers, including Waywatcher's alternate piercing row. WOC, WT beta, and
  WT-dev share one provider-neutral integration helper and report incomplete
  providers instead of silently disabling ultimates.
- Added offline/live checks for canonical unit replay, package/contact
  damage-heal behavior, and the complete career-action matrix. In-game and
  two-peer confirmation remain required; this commit is not deployed.

## 0.1.25-dev (2026-07-17) - #613 atomic linked-root transform [verify-fix-coop]

- Fixed the log-proven residual in `0.1.24-dev`: an immediate read after the
  three nominally successful node-0 setters retained rotation but left position
  at `0,0,0` and scale at `1,1,1` on owner 1P, owner 3P, and husk 3P.
- Changed the shared WeaponAppearance consumer to build the complete
  rotation/position/scale matrix and issue one `Unit.set_local_pose` write, the
  same linked-node primitive vanilla uses in `GearUtils.restore_scene_graph`.
- Hardened `WA.apply`: it now returns false when any requested channel fails and
  supplies a per-channel report. WOC's bounded proof line records the atomic or
  fallback write mode so a partially accepted write can no longer masquerade as
  a delivered transform.
- Added offline coverage for atomic linked-root composition and partial-channel
  failure, while retaining the existing next-update durability, tuner-yield,
  preview, husk, and quaternion-sign checks.

Verification: with two players on WOC `0.1.25-dev`, equip Blightreaper and
compare owner 1P, owner 3P, inventory preview, and remote husk after an attack
and mission transition. The log's `[WOC:613] transform proof` must report
`mode=atomic-local-pose`, position Z `-0.300`, scale `0.900` on every axis, and
never `drift-unrepaired`.

## 0.1.24-dev (2026-07-16) - #613 Blightreaper durable grip transform [verify-fix-coop]

- Fixed the Blightreaper grip transform being reset after its successful
  spawn-time application. Source and prior WT runtime evidence show that node 0
  is the correct linked weapon node, but running weapon animation can restore
  its native pose on the following update.
- Kept one canonical transform for first person, local third person, bots, and
  remote husks: absolute XYZ scale `0.9`, absolute Euler XYZ rotation `-90`,
  and linked-position Z offset `-0.3`.
- Added a weak gameplay owner that reads retained node-0 state and writes only
  after numeric drift. Preview surfaces remain one-shot, no transform RPC is
  sent, dead units are pruned, and intentional WT live or one-shot tuner edits
  win while their relevant channel contains a non-identity value.
- Replaced success-only diagnostics with bounded numeric before/after/target
  proof and added offline coverage for owner 1P/3P, husks, animation resets,
  previews, tuner ownership, and quaternion equivalence.

Verification: with two players on WOC 0.1.24-dev, equip the Blightreaper and
exercise attacks, swaps, and a mission transition. Confirm the `-0.3` grip,
`0.9` scale, and `-90/-90/-90` rotation in owner first person, owner third
person, and the peer's remote view; also confirm inventory preview. The log must
show `[WOC:613] transform proof` with numeric before/after/target values and a
retained or repaired result, never `drift-unrepaired`.

## 0.1.23-dev (2026-07-16) - #655 Blightreaper intrinsic and reusable traits [verify-fix-coop]

- Added intrinsic `Poisoned Edge` and `Shyish Health Curse` trait rows to the
  Blightreaper. Poisoned Edge is now the sole owner of the native Hagbane DOT,
  eliminating the old template-plus-trait double-proc risk.
- Used resident vanilla poison and Shyish death-spirit icons; the latter is the
  exact `mutator_icon_death_spirits` material used by `mutator_death.lua`.
- Exported only Poisoned Edge to CIM through exact capability
  `woc.poison_trait.v1`, allowing other eligible melee weapons to select it when
  both mods are installed. The Shyish curse remains intrinsic to Blightreaper.
- Stripped WOC-protected traits from transient vanilla loadout shadows without
  mutating live items, so no custom `NetworkLookup.traits` identifier reaches a
  peer without WOC.
- Added offline and live contracts for trait rows, icons, canonical proc
  ownership, wire safety, and provider integration.

Verification: with WOC+CIM, confirm both traits on Blightreaper and Poisoned
Edge in CIM's melee trait picker. Poison must apply once on hit and Shyish
spirits must occur only for Blightreaper kills. Verify once with a peer lacking
WOC: neither equip, swap, transition, nor hot-join may crash that peer.

## 0.1.22-dev (2026-07-16) - #654 Blightreaper property wire crash

- Fixed the reproduced `NetworkLookup.properties` crash when the Blightreaper
  resynchronized. The existing vanilla-key/promo wire shadow was a shallow copy
  and retained `woc_power_vs_order` plus the intrinsic-critical display row;
  vanilla tried to encode those WOC-only keys in
  `LoadoutUtils.properties_to_rpc_params` and fatally rejected them.
- WOC relic shadows now remove all item properties and traits before vanilla
  loadout synchronization. Their combat bonuses remain baked into the private
  template and their rows remain visible on the untouched local item.
- Hardened the missing-policy fallback so a marker-owned WOC relic with an
  inherited vanilla key fails closed instead of bypassing the explicit `woc_`
  prefix check.
- Added offline and live regression coverage for vanilla item/rarity fallback,
  property/trait removal, and live-item immutability.

Verification: equip the Blightreaper, swap away and back, transition into an
Adventure mission, and repeat once with a peer who does not have WOC. Neither
peer may crash; the local item still displays both intrinsic property rows.

## 0.1.21-dev (2026-07-16) - Blightreaper combat completion and resident Shyish spirits [verify-fix-coop]

- Fixed the empirically observed Shyish failure. The latest test log repeatedly
  recorded `[WOC:632] native Shyish unit not resident; spawn skipped`; the WOC
  runtime now acquires the source-declared real package
  `resource_packages/dlcs/mutators_batch_04`, whose installed bundle hash
  `64E79277358D543D` was verified to contain the unit. Runtime remains
  host-authoritative and bounded to 32 spirits, with no unit-path load or
  per-frame RPC.
- Changed the light chain to two ordinary Sword lights, the authored Empire Sword
  overhead as light three, and Kerillian Sword's stab as light four. Releasing a
  light after any heavy now enters overhead, then stab.
- Applied the Greataxe light damage profile to every light and its heavy profile to
  every heavy, retaining the existing Greataxe impact sounds/effects. Every sweep
  receives an intrinsic, non-rerollable `+15%` critical chance.
- Added the exact display-only property `+50% Power vs. Order`; it is backed by a
  no-op buff row and therefore cannot alter damage. Added a matching display row
  for the intrinsic critical chance.
- Recovered the Executioner Sword unit's exact `sword_2h_swing` and
  `rare_sword_2h_charge_swing_execution` events and play them at the native
  ActionSweep/ActionMeleeStart seams for the positively identified local WOC
  unit. Its Wwise bank is added to the private template, while the working
  Greataxe impact events remain unchanged. Playback still requires in-game
  verification.
- Preserved the canonical first-/third-person transform: `0.9` XYZ scale,
  `-90/-90/-90` rotation, and `-0.3` Z offset.
- Added offline coverage for the four-light chain, post-heavy routing, authored
  overhead sweep, light/heavy profiles, intrinsic crit, no-op property rows,
  audio dependency, and the real-package Shyish residency contract.

Verification: confirm `[WOC] v0.1.21-dev loaded`. With two WOC-enabled players,
test all four lights and each heavy-to-overhead-to-stab transition; verify light
and heavy armor behavior, property text, swing/impact audio, poison, and a direct
and poison kill from both host and client. Every qualifying kill must create a
visible spirit that reaches its owner and converts green health to temporary
health. Run `/woc_regression_test` and require zero failures.

## 0.1.20-dev (2026-07-16) - #632 Blightreaper Shyish spirits and axe audio [verify-fix-coop]

- Added the missing host-authoritative kill listener. Direct Blightreaper kills
  now spawn the native Shyish death-spirit unit at the victim, wait three
  seconds, chase the wielder for up to six seconds, then convert up to five
  green health to temporary health while retaining the native one-green-health
  floor, release/loop/explode audio, and explosion FX.
- Attributed client-owned Hagbane damage-over-time kills without a custom RPC.
  The host observes the already-native `arrow_poison_dot` synchronized-buff RPC
  and retains one weak, four-second victim-to-owner marker. Host-owned poison is
  marked at the same proc. Swapping weapons before the poison kill therefore
  does not lose the owning Blightreaper.
- Bounded runtime work to 32 active spirits, O(active spirits) host-only
  updates, 16 diagnostic lines per mission, and full cleanup on state exit.
  Missing native Shyish residency fails closed instead of force-loading a DLC
  package; the observed boot already has `resource_packages/dlcs/scorpion`.
- Replaced inherited sword strike presentation. Every damaging sweep now uses
  the native Greataxe `axe_2h_hit`, `melee_hit_axes_2h`, and
  `blunt_hit_armour` contract. Sword swing events are translated action by
  action to their safe native one-handed Axe counterparts because transplanting
  two-handed Greataxe events would change baked timing and sweep geometry.
- Added pure attribution/conversion/audio policy tests, production-boundary
  tests, expanded moveset tests, and live regression
  `issue632_blightreaper_shyish_spirit_contract`.

### Verification

Confirm `[WOC] v0.1.20-dev loaded` with two WOC-enabled players. Test a direct
kill as host and client, then let Blightreaper's poison land the killing blow
after swapping away. Each kill must release one visible spirit from the corpse;
after the three-second pause it must follow that exact wielder, preserve at
least one green health, and convert at most five green health to THP on contact.
Verify release/loop/explode audio and that weapon strikes use axe rather than
sword swing/impact presentation. Run `/woc_regression_test` and require
`issue632_blightreaper_shyish_spirit_contract` PASS. In the log require bounded
`[WOC:632]` listener/spawn/hit evidence and no missing-resource, RPC, or Lua
errors.

## 0.1.19-dev (2026-07-16) - #633 Blightreaper inspect audio [diagnostics-armed]

- Added the native `nds_skull_inspect` whisper to Blightreaper's existing
  local one-handed-sword inspect action. Playback is attached to the exact WOC
  first-person unit and owns only the playing id returned by Wwise.
- Bound cleanup to inspect release/interruption, repeated inspect, equipment
  destruction, dead-unit/timeout detection, game-state exit, mod disable, and
  mod unload. The eight-second cap is a final leak guard.
- Locked provenance to the boot-loaded Geheimnisnacht package. Missing package,
  API, or unit state fails closed without affecting an ordinary Sword inspect.
- Recovered `emitter_trophy_evil_sword` from the level-scoped `wwise/level_hub`
  bank, but did not claim mission residency or force-load that bank. Added the
  explicit `/woc_audio_probe` command: at most three eight-second attempts,
  spatially attached to the local third-person Blightreaper, with owned cleanup
  and no RPC. `/woc_audio_contract` records the exact functional/diagnostic
  boundary in the log.
- Added offline and runtime coverage for provenance, ownership, package
  failure, every cleanup edge, spatial probe targeting, hard caps, singleton
  hooks, bundle closure, and the no-force-load/no-network invariant.

### Verification

Confirm `[WOC] v0.1.19-dev loaded`. Hold weapon inspect with Blightreaper and
confirm the whisper starts, then releases on button-up, weapon swap, repeated
inspect, and mission transition. Confirm a normal one-handed Sword remains
unchanged. Run `/woc_regression_test` and require
`issue633_blightreaper_audio_contract` PASS. Run `/woc_audio_contract`, then
run `/woc_audio_probe` once in the keep and once in a mission and retain every
`[WOC:633]` line. The ambient feature is diagnostic, not yet a verified fix;
do not expect other peers to hear it until mission residency is proven.

## 0.1.18-dev (2026-07-16) - #613 Blightreaper presentation scale [verify-fix-coop]

- Reduced the authored Blightreaper model uniformly to `0.9` scale on X, Y,
  and Z while preserving its existing `{-90, -90, -90}` rotation and
  `{0, 0, -0.3}` offset.
- Kept the transform in the canonical appearance policy. The same exact scale,
  rotation, and offset therefore apply to first person, owner third person,
  bots, same-WOC remote husks, inventory/lobby/score character previews, and
  item/crafting/illusion/Athanor previews.
- Preserved the forward-only vanilla package aliases and vanilla sword fallback
  for peers without WOC; no custom transform or resource identity crosses to
  those peers.
- Extended offline and live regression contracts to lock the uniform scale,
  the unchanged rotation/offset, and both explicit 1P/3P consumers.

### Verification

Confirm `[WOC] v0.1.18-dev loaded`. Equip Blightreaper and verify it is about
10% smaller in first person, owner third person, and the inventory character
preview while retaining the same grip position. With a second WOC player,
verify the same scale and `Z = -0.3` placement on the remote husk. Check the
score/team and item/Athanor previews, then run `/woc_regression_test` and require
`issue613_blightreaper_appearance_contract` PASS with zero failures. A peer
without WOC must still see only the stable vanilla-sword fallback.

## 0.1.17-dev (2026-07-16) - #632 Cursed Blightreaper combat identity [verify-fix-coop]

- Replaced the inherited Kruber Sword behavior with a private deep clone of
  Kerillian's one-handed Sword action graph. Only attack action timing is scaled
  to 75%; the donor template and every vanilla damage profile remain untouched.
- Applied Weapon Tweaker's six proven elf-Sword third-person remaps at the
  pre-RPC animation boundary for every non-Kerillian career.
- Added the native `arrow_poison_dot` Hagbane effect on light and heavy melee
  hits. The wielder sends only the vanilla DOT identifier, so its damage and
  visible poisoned status work for hosts and clients without custom combat RPCs.
- Added WOC's Cursed rarity and the supplied byte-exact green rarity background.
  Local WOC peers render Cursed; mixed-peer loadout traffic remains the vanilla
  `es_1h_sword` / `promo` shadow.
- Fixed Blightreaper power at 600 outside Chaos Wastes and 900 inside an
  expedition. Chaos Wastes serialization carries only the vanilla
  `deus_es_1h_sword` / `unique` identity plus an ignored WOC marker; WOC peers
  restore the Cursed relic locally. If a non-WOC authority strips that unknown
  marker, the otherwise impossible 900/unique identity restores it safely
  (vanilla Chaos Wastes weapons top out at 700).
- Made Blightreaper ineligible for tempering and scrubbed only WOC's own Cursed
  key from Deus weapon-pool excludes before vanilla can index a missing pool.
- Registered every Deus and third-person hook by delayed VMF class name so
  lazy engine script order cannot silently omit the feature for a session.
- Added offline and runtime regression coverage for action cloning, attack
  speed, poison transport, 3P remaps, rarity registration and asset packaging,
  600/900 power, vanilla-safe serialization, and temper blocking.

### Verification

Confirm `[WOC] v0.1.17-dev loaded`. In Adventure, verify Blightreaper shows a
Cursed background, 600 power, Kerillian Sword attacks at 75% speed, and visible
Hagbane poison/DOT on struck enemies. Repeat as both host and client on a
non-Kerillian career and verify the remote third-person attacks animate. Start a
Chaos Wastes expedition with it equipped: verify 900 power, unchanged maximum
quality, no temper purchase, and no replacement by an ordinary sword. A peer
without WOC must receive only the vanilla sword fallback without errors.

## 0.1.16-dev (2026-07-16) - #613 authored Blightreaper icon [verify-fix-coop]

- Added the supplied transparent 80x80 Blightreaper inventory icon as a
  WOC-owned GUI texture and material.
- Assigned the custom icon only to the WOC provider row. The inherited generic
  sword HUD icon remains unchanged.
- Injected the private material into the four proven inventory/equipment
  renderers. CIM's Athanor top renderer receives the cloned vanilla sword icon
  through `cim_inventory_icon_fallback`, so an unproven custom material never
  reaches `Gui.bitmap_uv`.
- Preserved the existing vanilla-key wire identity. Peers without WOC do not
  receive the custom icon name or resource and continue to render the vanilla
  sword fallback.
- Added offline and runtime coverage for packaging, renderer ownership,
  Athanor fallback, and non-WOC pass-through behavior.

### Verification

Confirm `[WOC] v0.1.16-dev loaded`. Inspect Blightreaper in the local inventory,
equipment, and item-preview surfaces. With CIM Dev active, open the Athanor
selector and confirm it remains stable and uses a resident fallback where the
private material is unavailable. With a second player, confirm each WOC-enabled
player sees the authored icon on their own Blightreaper while a peer without WOC
continues to receive only vanilla-safe item identity, without errors or missing
materials.

## 0.1.15-dev (2026-07-15) - #613 native Blightreaper pulse

### Fixed

- Replaced the static authored Blightreaper material path with a resident
  base-game runed Empire-sword shader donor and WOC-owned albedo, normal,
  packed, noise, emissive-mask, and color-mask textures.
- Applied the native-style gold intensity and pulse variables through the same
  bounded appearance path used by owner first person, local/remote third
  person, inventory/lobby heroes, and item previews. Application is event
  driven at unit spawn/replay; it does not add a per-frame update or RPC.
- Added fail-closed donor/texture residency checks and bounded diagnostics so a
  missing compiled resource cannot crash startup or silently paint unrelated
  units.

### Verification

Confirm `[WOC] Weapons of Chaos v0.1.15-dev loading`, then craft/equip the
Blightreaper and verify the animated gold pulse in first person, local third
person, inventory character preview, item preview, and on a remote client.
Confirm ordinary Empire swords remain unchanged. Audio/inspect whispers remain
tracked separately in #633; this release does not fabricate an audio contract
that is absent from the extracted weapon unit.

## 0.1.14-dev (2026-07-15) - #637 unique immutable WOC relics [verify-fix]

### Unique relic inventory (#637)

- Defined one provider-owned `woc_unique_relic` contract for every present and
  future WOC item. Each enabled definition now registers one deterministic
  local backend instance and uses vanilla `promo` rarity to stay outside
  crafting, salvage, upgrade, reroll, illusion, and Athanor edit surfaces.
- Repaired MoreItemsLibrary's intentional live-row `rarity = "default"`
  overwrite after registration. The actual backend row, its `CustomData`, and
  the provider definition now carry the same immutable marker and rarity.
- Added bounded migration for old CIM-crafted duplicates. Exact unequipped CIM
  instances are removed through CIM's ownership transaction; equipped or
  uncertain rows are retained fail-closed and retried at later state edges.
  The deterministic canonical item is never a deletion candidate.
- CIM dev now rejects the provider marker both while building acquisition
  catalogues and at its single crafting dispatcher, closing ordinary Forge,
  customization, illusion, salvage, reroll, upgrade, and future recipe paths.
- Added engine-free multi-item reconciliation coverage plus the live
  `issue637_unique_immutable_relic_inventory` regression.

### Canonical presentation work (not ready for verification)

- Applied the author-reviewed rotation `{-90, -90, -90}` degrees and offset
  `{0, 0, -0.3}` through the canonical shared weapon-appearance primitive.
  The same bounded spawn-time transform now covers owner 1P/3P, bots, remote
  husks, inventory/lobby/score character previews, and item/Athanor previews.
- Kept the forward-only vanilla package aliases and same-WOC identity sideband;
  peers without WOC still receive only the vanilla Empire-sword fallback.
- Added offline locks for the exact transform, rendering-surface coverage,
  shared-library parity, and package residency.
- The extracted native material resolves to parent resource hash
  `EA15CAA2A17CD818`, but Stingray's source compiler cannot resolve a hash-only
  parent (`File does not exist EA15CAA2A17CD818.material`). The compile-valid
  authored PBR material remains in this build. Native gold pulse restoration
  therefore remains tracked separately and is not presented as a deployed fix.

### Verification

Confirm Blightreaper appears exactly once in inventory and does not
appear in Craft Item, Salvage, Athanor, Upgrade, Reroll, or Illusion choices.
Restart after any historical duplicate is unequipped, then require
`issue637_unique_immutable_relic_inventory` PASS in `/woc_regression_test`.

## 0.1.13-dev (2026-07-15) - #613 actual Blightreaper model and complete appearance path [verify-fix-coop]

### Changed
- Recovered the actual Blightreaper sword placed beside the cage in the
  Bögenhafen city level (`A9AECA9EA15818DA`), rather than trying to wield the
  keep-trophy diorama. Authored explicit WOC-owned 1P/3P units, material, and
  albedo/normal/metallic/roughness/emissive textures.
- Added the assets to WOC's master resource package. Vanilla package collectors
  and previewers borrow Empire-sword package leases while keeping the authored
  WOC unit as the local render unit; a missing-residency path fails visibly to
  the vanilla sword instead of crashing.
- Added forward-only `NetworkLookup.inventory_packages` aliases and a bounded
  same-WOC identity sideband. WOC peers re-key remote husks to Blightreaper;
  peers without WOC continue receiving only the safe vanilla sword identity.
- Covered inventory character, score/team, item/illusion/Athanor, owner 1P/3P,
  bots, and remote husk reconstruction, with engine-free package/lookup tests
  and a live `/woc_regression_test` residency check.

### Test method
1. Equip Blightreaper and verify its authored model in 1P, owner 3P, inventory
   character preview, item preview, and score/team preview.
2. Join with a second WOC peer; verify both peers see the authored model on the
   remote husk after join, weapon swaps, respawn, and a mission transition.
3. Join once with a peer that does not have WOC; verify that peer remains stable
   and sees the vanilla sword fallback.
4. Run `/woc_regression_test`; require zero failures.

## 0.1.12-dev (2026-07-14) - #595 startup crash: bundled wire policy + fail-closed guard [verify-fix]

### Why
Weapons of Chaos v0.1.11-dev could not finish entering the keep. The source
called `mod:dofile("scripts/mods/weapons_of_chaos/_woc_wire_policy")`, but the
resource package still enumerated only the original three Lua files. VMB
therefore omitted the helper from the Workshop bundle. The failed load returned
`nil`, and the first player loadout sync indexed `_wire_policy.safe_item`,
crashing at `weapons_of_chaos.lua:338` (crash GUID
`5906f1d7-ed94-444b-8f61-832ee17c1e49`).

### Changed
- Added `_woc_wire_policy` to WOC's compiled Lua resource manifest.
- Added a module-shape guard: ordinary vanilla items still delegate unchanged,
  while an explicit `woc_` identity fails closed instead of reaching the wire
  or crashing if the helper is ever unavailable again.
- Added the repository-wide `check_dofile_package_coverage` quick gate so every
  literal `mod:dofile` target must exist in source and be covered by its active
  mod's `.package` Lua list (exactly or by wildcard).
- Extended WOC's Lua regression coverage for the package entry and fallback
  guard.

### Test method
1. Enable Weapons of Chaos v0.1.12-dev and More Items Library.
2. Start the game and enter the keep.
3. Confirm the initial player unit spawns and the log contains no
   `_woc_wire_policy.lua` resource error or `_wire_policy` nil crash.
4. Run `/woc_regression_test`; require zero failures.

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
