# Crafting in Modded Changelog

## 0.8.110-dev (2026-08-01) - #48 custom-glow fallback notice [verify-fix]

- When saved CIM weapons contain opaque custom-glow data but Tweaker:
  Cosmetics is absent, log one bounded informational notice per session and
  retain the vanilla material appearance. CIM still never interprets or
  renders the blob.
- The provider lookup fails closed and remains retryable; repeated forge-load
  passes cannot spam the log. The policy is byte-identical with stable CIM.

## 0.8.109-dev (2026-08-01) - accessory properties apply per layer (#959)

- Fixed accessory property clicks that played their success sound but silently
  rejected the write when the same property was already full on another
  accessory. Per-property and distinct-property capacity now retain the active
  Necklace, Charm, or Trinket layer through the backend mutation.
- Kept ordinary weapon-property capacity global and unchanged.
- Replaced the display-only runtime regression with a production-equivalent
  sibling-layer write and added bounded `[cim:959]` store outcomes for live
  verification.

## 0.8.108-dev (2026-07-26) - transactional synthetic salvage (#628) [not-started]

- Unified keyed backend-item recovery with the canonical synthetic-item
  eligibility contract, including active and saved loadouts, favorites,
  malformed rows, and immutable Weapons of Chaos relics.
- Made mixed CIM-owned and foreign salvage one compensating local transaction.
  A failed deletion restores exact mirror rows, loadouts, illusion overrides,
  persistence, and vanilla new-item metadata without calling PlayFab, eager
  refresh, item normalizers, or autosave.
- Added a commit-aware crafting dispatcher so backend interfaces are dirtied
  only after a successful local salvage commit. Executable regressions cover
  partial multi-item failures, rollback errors, idempotence, and the full outer
  crafting boundary.

## 0.8.107-dev (2026-07-25) - #1002 bounded Equipment reset

- Opted CIM into Mod Tweaker's owner-level setting transaction. A full
  Equipment DEFAULT/profile restore reapplies the movespeed template at most
  once after all values persist, with bounded `[cim:1002]` evidence.

## 0.8.106-dev (2026-07-22) - #959/#628/#882/#598/#921 CIM identity and presentation repairs

- #959: Accessory property usage, removal, and clear actions now preserve the
  property category as part of their identity. Selecting a property for one
  accessory category no longer makes the same property appear selected or
  removable in a sibling category.
- #882: Athanor weapon previews preserve the requested primary/secondary slot
  identity through policy and mission-forge adapters, so ranged and secondary
  previews retain the engine-authored placement instead of drifting left.
- #598: The safe boolean-only Hold-Tab rarity side channel is mirrored for the
  sender as well as receivers. Explicit ordinary-item state clears a stale
  Modded frame without sending custom material or resource names.
- #921: Owner and observer now share one bounded tri-state application path,
  preserving explicit ordinary state across Chaos Wastes transitions and both
  RPC arrival orders. Edge-only diagnostics report convergence without exposing
  custom resource identifiers.

### #628 - restore the canonical salvage adapter

- The attached #930 session ran CIM Dev `0.8.101-dev` and proved crafted Dual Maces remained in the backend mirror, but the old salvage probe reported only aggregate counts. It could not distinguish active equip, saved-loadout ownership, favorite state, stale backend cache, or an identity rejection.
- Root cause: vanilla `BackendInterfaceCommon.filter_items` receives a backend-id keyed item map and enumerates it with `pairs`. CIM's recovery adapter used `ipairs`, so it silently visited zero real items. It now enumerates the same map shape as vanilla; exact eligible CIM instances can be restored to Salvage again.
- The canonical salvage adapter now emits one bounded `[cim:628] salvage_state` line per changed state of each exact CIM-owned instance. It records the item key, exact backend id, visible/hidden result, eligibility verdict and reason, active careers, saved loadout rows, favorite state, and backend dirty state. Identical UI refreshes are deduplicated and the session is capped at 96 lines.
- The provider-gate census no longer reports `cw_conversion` as an unrouted item walk. Current source inspection confirms that boundary only scrubs unsupported custom rarity names from a Chaos Wastes exclusion map; it does not enumerate or convert provider items. The boundary remains explicitly documented as non-enumerator behavior.
- Offline Lua coverage locks the keyed-map iteration contract, salvage-state fingerprint stability/change detection, and the production diagnostic marker. Runtime `/cim_regression_test` adds `issue628_salvage_state_diagnostic` and requires every real provider enumerator to be routed.

**Verify:** Open Salvage on Bounty Hunter after equipping and then replacing Dual Maces; the unequipped exact item must appear. Switch to Kruber and reopen Salvage. The console log must contain bounded `[cim:628] salvage_state` rows naming the exact eligibility or rejection reason and saved loadout owners for each crafted item.
## 0.8.105-dev (2026-07-21) - #592/#928 bounded CWV Blacksmith seed contract [not-started]

- Reconciled the Craft Item selector and runtime diagnostics with CWV's current
  acquisition policy: one real 5-power Blacksmith seed suppresses its synthetic
  twin, while CIM still owns every additional crafted instance.
- Kept provider definitions distinct from CIM persistence/ownership so salvage,
  Athanor locks, and cleanup cannot claim an unpersisted `cwv_` prefix as a CIM
  craft.

## 0.8.104-dev (2026-07-21): #749 exact Athanor renderer closure

- Athanor icon submission now proves that the requested material exists in the
  exact renderer Gui; global `Application.can_get` is no longer treated as
  evidence for that borrowed Gui.
- Mission Forge shading-environment selection now uses the synchronized strict
  V2 proof and retains its resident fallback when proof is unavailable.
- Added offline coverage for nil/null Gui materials and strict fail-closed
  resource behavior.

## 0.8.103-dev (2026-07-21): #822 immutable WOC relic boundary [untested]

- Purges stale CIM save records for every `woc_*` trophy even when WOC has not
  registered its live ItemMasterList marker yet. WOC owns exactly one canonical
  relic; CIM no longer restores, mirrors, or persists a second editable copy.
- Filters both saved and Adventure-equipped WOC relic ids at the Athanor loadout
  boundary, and rejects attempts to set one as the current Athanor edit target.
- Added bounded `[cim:822]` evidence plus offline coverage for pre-registration
  restore, Athanor list, equipped fallback, saved loadout, and set-loadout paths.

## 0.8.102-dev (2026-07-21): #947 Morris trait particle residency [untested]

- Fixed the native crash when a CIM-crafted Chaos Wastes ranged critical-hit
  trait executes in an Adventure mission and asks `WorldApi` for
  `fx/cw_enemy_explosion` while its package is absent.
- CIM now acquires one exact, private, session-long asynchronous reference to
  `resource_packages/dlcs/morris_ingame` during initialization, retrying only on
  game-state changes if the package manager was not ready. It never loads from
  the hit/action path and never unloads while persisted crafted traits can fire.
- Added bounded `[cim:947]` state diagnostics, a runtime residency check, the
  optional `/verify_cim_cw_trait_residency` report command, and offline coverage
  for exact path/reference, idempotence, async flags, late-manager retry, and the
  absence of unload/action hooks.

## 0.8.101-dev (2026-07-19): #682 classified craft rejections + #628 registered provider gate [untested]

- Fixed the confirmed issue 682 boundary (FS logs 2026-07-18/19, dr_ranger and
  wh_bountyhunter): an Athanor craft on `woc_blightreaper` died at resolution
  with `reason=nil`, `mirror_write ok=false`, `resolved key/slot/rarity=<nil>`.
  Two defects, both fixed:
  - The Athanor weapon list enumerated ItemMasterList without consulting the
    provider contract (the issue 793 bypass), so the immutable WOC relic
    rendered as a craftable `cursed` row on every career. The list now routes
    every row through the registered provider gate; excluded rows are logged
    capped as `provider rejected before UI surface=athanor_list`.
  - Every `contract and contract.normalize_record(...)` call site collapsed
    the multi-return through Lua's and/or truncation, so the rejection reason
    was ALWAYS nil (chat: "Craft failed: nil"). All seven collapse sites now
    route `gate_record`/explicit branches and every rejection carries a
    classified reason (for the relic: `provider:immutable_relic`).
- Issue 628 groundwork: the synthetic-item contract now owns a REGISTERED
  provider-gate schema (`gate_item`/`gate_record`/`register_enumerators` +
  `unrouted_surfaces`). Routed surfaces: athanor_list, blacksmith_list
  (template catalog callback), mirror_restore (saved-record load + legacy MIL
  re-inject), mirror_injection (Athanor/standard-forge/import mirror writes +
  persistence registration), salvage (filter adapter), plus the standard-bench
  random-craft pool. `cw_conversion` remains deliberately unrouted and is
  named by a capped `provider gate unrouted walks=` self-report line.
- Extracted the legacy MoreItemsLibrary entry builder verbatim to
  `_cim_mil_entry_builder.lua` (decomposition ceiling; entry stays under its
  5723-line contract).
- Runtime check `issue682_provider_gate_routing` (79-check suite) pins the
  classified relic rejection and the routed-surface census; offline suite
  `test_cim_provider_gate.lua` covers per-career resolution non-nil, the
  validator accept/reject table, capped rejection logging, and the routing
  wiring.

**Solo verification after deployment:** on dr_ranger or wh_bountyhunter, open
the Athanor weapon list for the melee slot: Blightreaper must be absent and the
log must show `provider rejected before UI surface=athanor_list
key=woc_blightreaper missing=immutable_relic`. Craft any normal weapon: the log
must show `craft_synth_result/athanor_equip` with `resolved: key=<key>
slot=melee rarity=modded`, `mirror_write ok=true`, `persisted=true`. No
`reason=nil` line may appear; `/cim_regression_test` must pass
`issue682_provider_gate_routing`.

## 0.8.100-dev (2026-07-19): #277 accessory cleanup and #787 authored Dual Axes icons [verify-fix]

- Extended `/forge_delete_all` from melee/ranged weapons to the complete
  synthetic craft scope already owned by the issue 628 contract: melee,
  ranged, necklace, ring (Charm), and trinket. Exact `_forged_weapons`
  membership plus the normalized owner/schema stamp remains mandatory;
  ordinary inventory, rarity/prefix lookalikes, out-of-scope rows, and
  unresolved provider definitions remain untouched.
- Kept the destructive path fail-closed when any candidate is equipped in a
  current or saved loadout or when equip state cannot be read. Execution now
  revalidates every requested record through the same contract before making
  any mutation.
- Hardened preview/confirm against same-ID replacement. The snapshot now
  fingerprints canonical item identity, owner/schema, live slot/provider, and
  mirror-vs-MIL cleanup route rather than only backend IDs. Cosmetic/property
  edits do not change cleanup identity and do not invalidate the preview.
- Updated command, preview, completion, list, log, checklist, and Workshop copy
  that incorrectly described the forged store as weapons-only.

**Solo verification after integration/deployment:** craft a weapon plus one
necklace, Charm, and trinket; keep ordinary equivalents; unequip every CIM
craft from current and saved loadouts; preview and confirm `/forge_delete_all`.
Only the four CIM crafts should disappear and stay absent after restart. Then
repeat with one CIM accessory equipped and confirm the entire batch refuses.

- The Athanor icon resolver now requests the complete masked-and-saturated atlas material pair from the active `ingame_ui` renderer instead of assuming the weave-forge state supplies it.
- CWV Dual Axes rows consume CWV's paired authored icon for both Kruber and Saltzpyre; missing providers or atlas materials fail closed to the native icon.
- Added cross-mod appearance-contract coverage and kept stable CIM untouched pending its normal promotion path.

## 0.8.99-dev (2026-07-19): #823 prevent regression checks from rehooking live modules [verify-fix]

- Made the modded-rarity owner idempotent so an accidental second load returns
  its existing API instead of registering the same five VMF hooks again.
- Removed the regression suite's side-effecting `mod:dofile` call and read the
  already-published localization table instead.
- Added offline contracts that forbid regression checks from reloading hook
  owners and require the hook-owning module's reload guard.

**Solo verification:** launch CIM Dev, run `/cim_regression_test` twice, and
confirm `no_duplicate_hook_safe_registrations` passes both times. The log must
contain no `Attempting to rehook active hook` warning for `Localize`,
`_state_setup_upgrade`, either inventory `on_enter`, or `get_weapon_pool`.

## 0.8.98-dev (2026-07-19): #404 restore in-mission Athanor preview [verify-fix]

- Accepted Stingray's retail callable-table `Vector3` and `Vector3Box`
  constructors, restoring the preview correction that the earlier defensive
  constructor gate had disabled.
- Preserved the native mission-only ranged preview inversion so ranged and
  melee weapon previews no longer overlap.
- Replaced broad `athanor_*` widget pruning with exact renderer-material
  checks, retaining atlas-backed panels while skipping only unrenderable
  material passes.
- Added bounded `[cim:404]` view/material diagnostics and regression coverage
  for the remaining engine-only seams.

**Verification:** enable in-mission crafting, open both melee and ranged Athanor
weapon overviews, and confirm both weapon models and the surrounding atlas-backed
panels render without overlap or crash. The newest log must show
`[cim:LOAD] v0.8.98-dev`; any remaining rejection should emit one bounded
`[cim:404]` record rather than pruning the complete view.

## 0.8.97-dev (2026-07-18): #524 bound slot-split Craft Item selector injection

- Used the latest `0.8.95-dev` verification log to identify a different seam
  from the old 300-power crafted-instance leak: the native Craft Item picker
  calls `can_craft_with` through slot-split subqueries, and CIM was appending
  the full synthetic selector cache to each matching subquery. That can make
  ordinary 5-power selectors look duplicated even when the final-list probe
  reports `hard_dups=0`.
- The selector injection path now parses a single `slot_type == ...` filter and
  appends only matching synthetic selectors for that subquery. Broad mixed-slot
  queries keep the existing full-cache behavior, and distinct authored CWV
  variants or accessory icon selectors remain separate choices.
- Added engine-free regression coverage proving melee-only and ranged-only
  Craft Item queries receive only their matching synthetic templates.

**Verification:** open the native Keep Craft Item picker, especially on a career
that previously showed two crossbows, dual axes, dual maces, rapiers, or Tuskgor
javelins. Each definition should appear once as a 5-power selector; no 300-power
crafted instances should appear. Run `/cim_regression_test` and require the
`issue524_*` checks to pass.

## 0.8.96-dev (2026-07-18): #661 preserve provider-owned weapon availability

- Removed CIM's independent `can_wield` append from the adventure-visibility
  helper. Crafting visibility still clears non-Adventure `mechanisms`, but
  weapon availability remains owned by native data, WT, or CWV together with
  their paired career-action reconciliation.
- Replaced the runtime regression with a byte-for-byte `can_wield` preservation
  check plus the existing mechanism-clear assertion. This closes the known CIM
  boundary that could make a weapon selectable while its effective template
  lacked the new career's `action_career_*` row.

## 0.8.95-dev (2026-07-18): #703 CWV rows no longer render locked in the Athanor picker

- The Athanor weapon list's lock badge is a vanilla OWNERSHIP gate: vanilla
  `_sync_backend_loadout` resolves each row through
  `backend_interface_items:get_item_from_key(item_key)` and stamps
  `content.locked = not backend_id` (`hero_window_weave_forge_weapons.lua:555`
  + `:565`), which draws the `hero_icon_locked` pass and saturates the icon.
  CWV entries are registration-only definitions with no owned backend instance
  (issue 592), so the lookup could never succeed and every CWV row drew a false
  padlock - while selecting and crafting kept working because CIM already
  overrides `_present_item` / `_on_list_index_selected`.
- Fix rides the existing consolidated `_sync_backend_loadout` hook (no new hook
  registration): rows vanilla just locked are re-classified through the issue
  628 contract's `provider_for` ladder and cleared only when the key resolves
  to provider=cwv. Vanilla and non-cwv provider rows keep their vanilla lock
  state, so genuinely unavailable vanilla items stay locked.
- Added `/cim_regression_test` check `issue703_athanor_cwv_rows_unlocked`
  pinning the classifier boundary (cwv-prefixed true; vanilla, woc, and
  empty/nil keys false) and the contract dependency.

**Verification:** open the Athanor weapon picker on a career with CWV variants
(e.g. Kruber melee): CWV rows show no padlock and no desaturated icon; a vanilla
weapon you own no instance of still shows its lock. Run `/cim_regression_test`
and require `issue703_athanor_cwv_rows_unlocked` PASS.

## 0.8.94-dev (2026-07-18): #404 ranged Athanor properties preview centering

- Replaced the non-diagnostic root-node position probe with a source-backed
  correction at the owning `HeroWindowWeaveProperties._create_item_previewer`
  boundary. The July 18 log confirmed ranged previews still spawned at
  `x=-0.8`; the sibling native forge weapon browser authors centered `x=0`.
- CIM now uses that exact native centered x only for ranged weapons in the
  properties editor, while preserving the properties surface's y/z, vanilla
  melee placement, ordinary Weave behavior, and every non-CIM preview.
- The correction updates both the live link unit and the previewer's boxed
  start position, so zoom cannot restore the old far-left placement. It runs
  once per preview construction and sends no network traffic.
- Added engine-free and `/cim_regression_test` coverage for slot scoping,
  caller-owned position immutability, malformed input, hook ownership, active
  surface gating, and zoom durability. The runtime seam lives in its own module
  so the already-baselined CIM entry does not grow.

**Verification:** confirm `[cim:LOAD] v0.8.94-dev`, open CIM's Athanor, select a
ranged weapon and enter its properties/traits editor. The weapon should be
centered rather than far-left; a single `[cim:404] ranged properties preview
centered` line should name the selected item. Repeat with a melee weapon and
confirm its established placement is unchanged.

## 0.8.93-dev (2026-07-18): exact acquisition-row ownership (#524) [verify-fix]

- Traced the native source contract: `can_craft_with` admits only default-rarity
  weapon/accessory definition rows. CIM's final selector reconciler ignored
  Modded rows for family ownership but still returned them, so any upstream
  mirror/hook leak became the reported crafted 300-power row beside its
  five-power Blacksmith selector.
- The shared synthetic-item contract now owns both exact item identity and the
  row's acquisition role (`selector`, exact crafted `instance`, or unrelated).
  The final native Craft Item seam fails closed by removing instance rows before
  family reconciliation; inventory, salvage, exact persistence, and Cosmetics
  #702 offhand state remain per-instance and untouched.
- Added engine-free and runtime regressions for top-level and nested Modded
  rarity, repeated exact CWV crafts, authored accessory icon selectors, and
  injected contract ownership. The bounded `[cim:524]` final-list probe remains
  armed until in-game verification.

**Verification:** in the native Keep **Craft Item** picker, craft the same CWV
weapon twice, close and reopen the picker, and confirm exactly one five-power
Blacksmith selector remains and no 300-power crafted instance appears. Repeat
with two distinct accessory icon selectors; both selector icons remain while
crafted accessories stay out of the picker. Run `/cim_regression_test` and
require every `issue524_*` check to pass.

## 0.8.92-dev (2026-07-17): #83 dynamic Athanor material closure

- Closed the post-construction gap in CIM's in-mission forge safety. Vanilla
  `_setup_weapon_stats` creates late stat widgets after `create_ui_elements`;
  every texture-bearing pass in those scrollbar lists is now proven against the
  exact `ui_top_renderer` Gui before it can draw.
- A non-resident texture pass is disabled instance-locally. Its text, hotspot,
  and renderer-proven texture siblings remain active, and clone-on-write keeps a
  shared widget definition or later Keep instance untouched.
- Added engine-free and `/cim_regression_test` coverage for the exact observed
  `icon_block_arch_masked` rotated-texture crash plus a future raw-material row.
- The repeated `scenegraph["window"]["scale"]` warning is non-causal: vanilla's
  console forge definition authors `window.scale = "fit"`, and the warning is
  emitted by its legacy scenegraph merge on every entry. The fatal two seconds
  later is the distinct missing-material draw path.

**Verification:** run `/cim_regression_test` and require
`issue83_dynamic_forge_widget_material_closure` PASS. Then open CIM in a mission,
select a melee weapon with block angle, and confirm the stats list remains usable
without a `Material 'icon_block_arch_masked' not found in Gui` fatal.

## 0.8.91-dev (2026-07-17): #428 canonical copied debug helper [tooling]

- Replaced the entry file's behavior-identical `_dbg` / `_dbg_alert` definitions
  with the standalone bundled copy of `tools/shared_lib/_lib_debug.lua`.
- Registered CIM as an exact-copy consumer and added executable ownership tests,
  preserving gated `mod:debug` diagnostics and guarded log-only `printf` alerts.
- Synchronized the tester-visible Workshop description banner with `0.8.91-dev`;
  version QA now blocks any new leading-description version drift.

## 0.8.90-dev (2026-07-17): #628 make normalization consume canonical identity [verify-fix]

- Audited the synthetic-item construction and registration boundary against the
  closed crafting, selector, inventory, Athanor, CWV, and WOC issue families.
  The remaining deterministic split was inside the shared contract itself:
  `normalize_record` accepted only `item_key` / `ItemId` / `key`, while salvage
  and acquisition selection consumed the fuller canonical identity ladder.
- Made normalization delegate to `canonical_item_key`, including the supplied
  backend id for legacy `cwv_<key>_NNN` rows. Reconstructed UUID rows carrying
  `CustomData.cim_acquisition_key`, nested `data.cwv_key` rows, and legacy
  base-shaped CWV rows now produce the same exact acquisition identity as every
  selector and salvage consumer.
- Added engine-free and runtime regression coverage for all three previously
  divergent shapes. Vanilla identity and the immutable WOC relic exclusion are
  unchanged.

**Verification:** run `/cim_regression_test` and require
`issue628_identity_resolvers_unified` PASS, then repeat #628's existing solo
craft, inventory, salvage, exact-delete, and restart matrix.

## 0.8.89-dev (2026-07-17): #540 extract regression registrations [tooling]

- Moved the 74-check late `/cim_regression_test` block into the late-loaded
  `_cim_regression_checks.lua` module while preserving every check name and the
  complete 78-check registration order. Four contract checks remain colocated
  with their initialization-time identity helpers in the entry.
- Kept production hooks, the runner, and the established flat `mod._cim_*` API
  unchanged. Reassigned forge/loadout stores cross the module boundary only
  through private getter/setter closures, preventing stale table captures.
- Reduced the CIM dev entry from 8,468 to 6,165 lines, below its frozen
  7,636-line baseline without changing the baseline or suppressing the gate.
- Added engine-free coverage that proves one manifest load, bounded entry size,
  unique registrations, and the frozen first/last registration order.

**Offline verification:** run `qa/check_file_sizes.ps1`,
`qa/check_lua_unit_tests.ps1`, and `qa/run_all.ps1 -Quick`.

## 0.8.88-dev (2026-07-17): #484 persist crafted provider identity [verify-fix-coop]

- Preserved `cim_acquisition_key`, `cim_provider`, and the CWV `cwv_key` in the
  one synthetic mirror payload. Reconstructed backend/menu wrappers can now
  recover the exact crafted definition even when their visible `.key` remains
  the provider's vanilla fallback (`es_handgun` for the Old Musket).
- Expanded the shared canonical resolver across direct fields, nested item
  data, mod data, and CustomData. The legacy MIL injection path stamps the same
  contract instead of creating an identity-poor exception.
- Added offline and `/cim_regression_test` coverage for a base-shaped Old Musket
  with a UUID instance id, including Athanor/standard selector parity.

**Verification:** confirm CIM `v0.8.88-dev`, craft a new Old Musket in the
Athanor and standard forge, restart once, and verify both retain exact identity
in inventory, preview, equip, mission transition, salvage, and the CWV co-op
test described in CWV `v0.1.438-dev`. `issue484_crafted_old_musket_identity`
must pass in `/cim_regression_test`.

## 0.8.87-dev (2026-07-16): #655 optional WOC poison trait provider [verify-fix-coop]

- Added an exact optional-provider capability boundary for WOC's reusable
  `Poisoned Edge` melee trait. CIM validates provider id, capability, trait row,
  and category before adding it to the Adventure trait pool.
- Persisted provider-owned traits in a parked `external_traits` array whenever
  the provider is absent. Parked keys never reach the live backend item and are
  reactivated on the same saved instance when WOC returns.
- Made registration and pool insertion idempotent and load-order safe. Explicit
  Athanor replacement or standard reroll also clears the parked value so a
  removed trait cannot resurrect.
- Added pure regression coverage for absent-provider parking, exact-capability
  reactivation, bounded pool insertion, and WOC wire-shadow integration.

## 0.8.86-dev (2026-07-16): issue 628 unify synthetic identity across salvage and crafting [verify-fix]

- Root cause of the residual issue 628 divergence: two hand-written identity
  resolvers classified a synthetic item differently. The standard-forge
  acquisition selector (`_cim_template_selector.canonical_key`) is cwv_key-first
  and backend-id-aware, but the salvage eligibility filter's resolver
  (`_cim_synthetic_item_contract` `instance_key`) preferred `ItemId`/`key` and
  had no `cwv_<key>_NNN` fallback. They provably disagree for any CWV row
  presented with its inherited BASE `.key`/`.name` - which is exactly what CWV's
  `_build_entry` keeps (base weapon on `.key`/`.name`, variant only on
  `.cwv_key`, so vanilla equip/preview fallbacks resolve;
  character_weapon_variants.lua:10318-10330). For such an item the salvage filter
  resolved the base weapon, mismatched the variant-keyed CIM record in
  `validate_instance`, and the crafted weapon never appeared in Salvage.
- Made `_cim_synthetic_item_contract` the single owner of canonical synthetic
  identity via `canonical_item_key` (acquisition key, then `data.cwv_key`, then
  the `cwv_<key>_NNN` backend-id band, then `ItemId`/`key`/`data.key`). Salvage
  eligibility now reads through it, and the standard-forge acquisition selector
  is injected with the same resolver at load, so craft, inventory, standard
  forge, and salvage classify one identity. Vanilla items and the existing
  CIM-crafted mirror path resolve identically to before.
- Added a runtime check `issue628_identity_resolvers_unified` that proves the
  selector delegates to the contract (no drifted copy) and that a base-keyed CWV
  instance still resolves to its variant. Extended the engine-free suites: the
  contract test now covers `canonical_item_key` priority and a base-keyed CWV
  salvage instance staying eligible while equipped/loadout/favorite exclusions
  still reject it; the selector test proves it delegates to an injected resolver.
- Note: authored as 0.8.85-dev in a parallel workstream and renumbered to
  0.8.86-dev when merged on top of the Cosmetics Tab presentation entry below.

### Verification

1. With CIM + CWV enabled, craft Dawi Mace, Dawi Mace and Shield, and Dawi Dual
   Maces through CIM's standard forge. Confirm each Modded item is in inventory.
2. Unequip each from every current and saved loadout and clear any favorite mark.
   Open the standard Salvage page: every unequipped, non-favorited crafted Dawi
   Mace must now appear as a salvage candidate.
3. Equip one, favorite another, and add a third to a saved loadout; reopen
   Salvage and confirm those three are excluded while any remaining free copy
   still appears.
4. Salvage one free copy, restart, and confirm only that exact instance is gone
   and the others survive.
5. Run `/cim_regression_test` and require `issue628_identity_resolvers_unified`,
   `issue628_provider_contract`, and `issue628_saved_instance_contract` PASS.

## 0.8.85-dev (2026-07-16): #629/#639/#641 Cosmetics Tab presentation precedence [verify-fix-coop]

- Hold-Tab now asks the installed Cosmetics mod for its locally resolved
  component presentation before applying CIM's exact-primary-skin correction.
- A shield-owned composite icon and name take precedence over the primary skin;
  dual weapons retain the primary icon while accepting the composite name.
- The provider is optional and renderer-local. Missing Cosmetics, peer state,
  parity, or icon resources leaves the existing vanilla/CIM fallback unchanged;
  no new RPC or custom resource identity is transmitted.
- Lua coverage proves provider precedence and the unchanged no-provider path.

Verify with Cosmetics `0.9.132-dev` using the two-player method in its matching
changelog entry. The hold-Tab icon must not revert after CIM's post-update hook.

## 0.8.84-dev (2026-07-16): issue 524 render-seam diagnostics [diagnostics-armed]

- Symptom: the native Craft Item picker still shows duplicate weapon rows
  (reported: two throwing-axes, a javelin cloned off them, two Blightreapers)
  despite ten catalog-policy ships. Every prior `[cim:524]` probe reported only
  CIM's synthetic CATALOG (`acquisition_templates eligible/families/suppressed`)
  and the offline `issue524_*` checks exercise `catalog.build`/`inject` with
  hand-built inputs, so nothing ever observed the list vanilla actually renders.
- Armed a render-seam probe at the one seam that produces the rendered list,
  `standard_forge mod._cim_inject_templates` (after `template_selector.inject`).
  New module `_cim_diag_524.lua` dumps the FINAL injected list once per distinct
  menu-open: a header (`render picker=... rendered=N families=F hard_dups=H
  soft_dups=S`), then, only when a duplicate exists, `render_dup` (>1 row sharing
  one canonical weapon family = a real dedup miss), `render_softdup` (>1 distinct
  family sharing one item_type = two authored definitions that look alike), and
  per-row `render_row` lines naming each implicated key. Every row is tagged by
  SOURCE (synthetic / vanilla-default / crafted-modded / legacy-cwv), so a
  crafted instance leaking past vanilla's `rarity=="default"` filter is explicit.
- No behavior change: this is diagnosis before mitigating. Vanilla `can_craft_with`
  (backend_interface_common.lua:498-510) admits only `rarity=="default"`, and CIM
  writes crafts as `rarity="modded"`, so the source of the visible duplicate must
  be read from a live picker before any policy is touched.
- Engine printf, prefix `[cim:524]`, always-on in dev, bounded (caps + a
  signature throttle so a recipe re-query does not repeat the dump). Added
  runtime check `issue524_render_diagnostics_armed` so the probe cannot be
  stripped while #524 is open.

### Test method

Open the native Craft Item picker on a career with CWV/WOC weapons and browse
Blacksmith choices; if any weapon looks duplicated, note which. Then read the
newest console log for `[cim:524] render ...`: the header gives the rendered row
count and how many hard/soft duplicates were found, `render_dup`/`render_softdup`
name the colliding families/item_types, and `render_row` names each offending key
and its SOURCE. Attach that block to issue 524. Run `/cim_regression_test` and
require `issue524_render_diagnostics_armed` PASS.

## 0.8.83-dev (2026-07-15): #637 immutable WOC relic boundary

- CIM now treats WOC's provider-owned `woc_unique_relic` marker as a hard
  acquisition and mutation boundary. Marked definitions are excluded from the
  native Craft Item catalogue; `promo` keeps them out of Athanor and vanilla
  recipe lists.
- Added one defense at CIM's canonical craft dispatcher before illusion-swap
  handling. Any marked input is converted to a bounded no-op, covering skin,
  salvage, upgrade, reroll, and future CIM recipes without per-screen patches.
- Added engine-free coverage for definition, live-row, and `CustomData` marker
  shapes. WOC owns duplicate migration and the deterministic canonical item.

## 0.8.82-dev (2026-07-15): #524 five-power bounded Blacksmith selectors [verify-fix]

- Restored the native crafting contract requested for CWV: every eligible definition has exactly one Blacksmith selector at power 5. The configured crafting power still applies only to the newly crafted Modded item.
- Extended the native picker compactor to deduplicate legacy/real default-rarity CWV rows as well as CIM's synthetic rows, preferring an existing 5-power row and excluding 300-power template twins. Crafted Modded-rarity instances remain independent inventory records.
- Preserved the deliberate accessory behavior: necklace, charm/ring, and trinket icon variants retain separate 5-power selectors rather than collapsing by shared item type.
- Added offline and runtime regressions for synthetic power, repeated real rows, crafted-instance isolation, and accessory icon families. `/cim_regression_test` now rejects any CWV selector whose power is not exactly 5.

### Test method

Open the native Craft Item picker on Kruber with CWV enabled. Every eligible CWV weapon must appear exactly once as a 5-power Blacksmith item; no 300-power Blacksmith row may appear. Craft one CWV weapon twice at 300 power, close and reopen the picker, and confirm the two crafted items remain in inventory while the picker still contains one 5-power selector. Confirm the distinct accessory icon choices remain available. Run `/cim_regression_test` and require all `issue524_*` checks to pass.

## 0.8.81-dev (2026-07-15): #474 shared authored-preview resource gate

- CIM Athanor now asks an enabled provider for its canonical preview descriptor before resolving the inherited vanilla item. Old Musket therefore uses CWV's exact custom unit, package anchor, material, textures, transform, and fallback instead of a CIM-specific model guess.
- Extracted an engine-free forge preview resource policy. Standalone vanilla packages and resident master-bundle units (including Loremaster shields) are both valid; missing custom and fallback resources fail closed without spawning an unsafe unit.
- Added regression coverage for Old Musket custom/fallback readiness, Loremaster resident custom units, vanilla package controls, and absent or incompatible companion mods.

## 0.8.80-dev (2026-07-15): #628 canonical synthetic items and safe salvage [verify-fix]

- Replaced CIM's screen-specific modded-item exceptions with one normalized synthetic-item contract. Provider mods own complete `ItemMasterList` definitions; CIM now owns one schema-versioned acquired instance carrying its exact backend id, item key, provider, slot, rarity, properties, traits, illusion, and persistence metadata. Athanor crafting, standard crafting, SaveWeapon import, mirror restore, legacy MIL import, inventory filtering, and deletion consume that same contract.
- Removed the salvage hook's unsafe behavior that re-added Modded items regardless of equip, saved-loadout, or favorite state. CIM now preserves vanilla's slot and rarity exclusions and rejects current-equipped, any-loadout-equipped, favorited, default, promo, magic, blacksmith/template, malformed, and non-owned rows. Only exact persisted CIM instances can enter the repair path.
- Routed Salvage through the existing exact-owner #277 deletion transaction. The exact mirror row, `forged_weapons` record, CIM saved-loadout references, and exact-instance illusion override are removed together; ordinary items remain session-local, and no official PlayFab craft/salvage request is issued in the modded realm.
- Added a provider validator before acquisition-selector construction, with bounded `[cim:628]` evidence for incomplete CWV/WOC rows. Added engine-free truth tables for all safety exclusions, malformed provider failure, exact-instance deletion partitioning, idempotent rebuilds, mirror identity, all three Dawi Maces, an older CWV Imperial Longsword, and WOC Blightreaper. Runtime checks `issue628_provider_contract` and `issue628_saved_instance_contract` cover the live registry/save boundary.

### Test method

Craft Dawi Mace, Dawi Mace and Shield, Dawi Dual Maces, Imperial Longsword, and Blightreaper through CIM. Confirm each exact Modded item appears in inventory and its normal preview, survives a restart, and appears in Salvage only after it is removed from every current/saved loadout and is not favorited. Confirm the equipped, saved-loadout-equipped, favorited, and Blacksmith selector copies never appear. Salvage one exact crafted copy while retaining a second copy of the same weapon, restart, and confirm only the selected instance remains deleted. Run `/cim_regression_test` and require `issue628_provider_contract` and `issue628_saved_instance_contract` PASS.

## 0.8.79-dev (2026-07-15): #524 craft-family dedupe; #624 Keep forge; #617 Athanor icon closure [verify-fix]

- Reopened #524 after the native Craft Item picker still showed duplicate weapon choices. The 0.8.76 catalog enumerated exact ItemMasterList keys, which admitted native helper aliases such as `_preview` and Versus rows beside the real weapon. CIM now builds one deterministic selector per ordinary `slot_type + item_type` craft family. Provider localization is never identity, crafted Modded-rarity instances remain separate inventory records, and every authored CWV `cwv_key` remains independently craftable, including veteran/stat variants that intentionally share an item type.
- Added bounded `[cim:524]` catalog evidence naming the kept and dropped keys for at most twelve alias collisions per page open, plus a summary for the remainder. Rebuilds re-evaluate the live career/DLC/WT-mutated availability and cannot accumulate selectors across reopen or hot reload.
- Added #624: the physical forge object in the Keep is interactable in the modded realm while CIM is loaded. Vanilla disables only its `forge_access.can_interact` predicate when `eac-untrusted`; CIM restores that predicate only in a live hub and delegates the native prompt, controller input, successful `hero_view_force/forge` transition, and every official/non-Keep result unchanged. CIM's existing standard-forge lifecycle remains the sole backend-safe craft path, so no PlayFab/EAC request was added.
- Reopened critical #617 after scrolling the Athanor selector attempted to draw CWV's `icon_wpn_axe_hatchet_t1_dual_cwv` with `masked=true, saturated=true`. That custom atlas does not expose a masked+saturated material to the exact Athanor top Gui, so `UIRenderer_draw_texture` received nil and crashed. Every live selector row is now checked against the exact renderer before `_populate_list`: CIM resolves the provider's vanilla fallback, the inherited base-family icon, or a resident vanilla slot placeholder; a row with no proven icon is omitted instead of reaching the draw call. Provider data and icons remain unchanged outside this one render surface.
- Added engine-free family/alias/CWV/localization/live-availability tests, Keep/official/reload interaction tests, exhaustive closure coverage for all nine current CWV paired icons, and runtime checks `issue524_native_craft_families_deduplicated`, `issue624_keep_forge_interaction`, and `issue617_athanor_icon_resource_closure`.

### Test method

In the Keep, use the physical forge and confirm its native prompt opens CIM's standard crafting screen with mouse/controller behavior unchanged. Open Craft Item on Kruber and confirm each ordinary or CWV weapon choice appears once; specifically, preview/Versus aliases must not produce twins while authored Axe and Shield and Imperial Axe and Shield variants remain separate. Craft one CWV weapon twice, close and reopen the forge, and confirm the selector count does not grow while both Modded items remain in inventory. Then open CIM's Athanor weapon selector and scroll through every row, including Dual Axes; it must remain open, using a vanilla Dual Axes fallback icon where its private paired icon is unavailable. Run `/cim_regression_test` and require all three `issue524_*` checks plus `issue624_keep_forge_interaction` and `issue617_athanor_icon_resource_closure` PASS.

## 0.8.78-dev (2026-07-14): #618 crossed-swords salvage icon [verify-fix]

- Corrected the fifth Modded-rarity salvage control to use a dedicated pale-gold crossed-swords glyph matching vanilla's Plentiful, Common, Rare, and Exotic buttons. The first candidate incorrectly reused `icon_bg_modded`, which is the item-card rarity background shown as a bright square.
- Extracted the authoritative 56x56 silhouette from vanilla's `gui_store_menu_atlas` (`materials/ui/ui_1080p_store_menu`, diffuse resource `7A5A590C28ED1213`) and recolored it with CIM's registered Modded rarity color while preserving alpha and luminance.
- Added the texture, material, package entries, renderer injection, engine-free asset-closure assertions, and retained runtime regression `issue618_modded_salvage_autofill`.

### Test method

Open the standard Salvage page and confirm the fifth rarity control shows pale-gold crossed swords matching the four vanilla buttons, not a square rarity background. With at least ten Modded-rarity items, click it and confirm exactly nine Modded items fill the queue while Clear remains sixth. Run `/cim_regression_test` and require `issue618_modded_salvage_autofill` PASS.

## 0.8.77-dev (2026-07-14): #618 modded salvage autofill [verify-fix]

- Added a fifth rarity autofill button to both standard salvage layouts. It uses CIM's existing `icon_bg_modded` resource, selects only `modded` items, and moves Clear to the sixth position.
- Reused vanilla's existing fill paths rather than duplicating salvage selection. Desktop calls `CraftPageSalvage._fill_by_rarity("modded")`; console sends the same rarity through `HeroViewStateOverview.set_auto_fill_rarity`. Both remain bounded by vanilla's nine `CraftingSettings.NUM_SALVAGE_SLOTS` slots.
- Added an idempotent pure definition transformer, desktop/console engine-free tests, apply-site `[cim:618]` traces, and runtime regression `issue618_modded_salvage_autofill`.

### Test method

Open the standard Salvage page with at least ten Modded-rarity items, click the new pale-gold fifth rarity button, and confirm exactly nine Modded items fill the salvage queue while Clear remains the sixth button. Run `/cim_regression_test` and require `issue618_modded_salvage_autofill` PASS.

## 0.8.76-dev (2026-07-14): #524 restore all CWV Blacksmith selectors [verify-fix]

- Fixed every CWV Blacksmith/base selector disappearing from the standard Craft Item grid, including Dual Axes, Infantry Spear, Imperial/Dawi Crowbill, and Kruber Greataxe. CWV registered all 34 craftable definitions in the reported session, but CIM activated its forge/cache only after vanilla `HeroWindowCraftingConsole.on_enter` had already built the initially selected recipe page.
- Converted the existing singleton lifecycle hook into a pre-enter wrapper: CIM now marks the forge active and rebuilds the exact-career selector catalog before vanilla requests `can_craft_with` rows. The post-enter diagnostic remains after UI construction.
- Extracted one pure selector-catalog builder. Each synthetic row keeps the exact CWV ItemMasterList definition as `data`, so the provider's authored icon (including the paired Dual Axes icons), model, skin family, career ownership, and DLC policy remain canonical. Selectors are session-only and never auto-grant or replace existing persisted crafts.
- Added engine-free lifecycle/catalog/DLC tests and `/cim_regression_test` check `issue524_all_cwv_blacksmith_selectors`, which enumerates every registered CWV family across every authored career and rejects missing, crossed-owner, or identity-losing selectors.

### Test method

Open the standard Craft Item page on Kruber and confirm Blacksmith/base rows are present for Dual Axes, Infantry Spear, Imperial Crowbill, and Greataxe, using their authored icons. Craft one, reopen the page, and confirm exactly one base selector remains while the crafted instance remains separately in inventory. Run `/cim_regression_test`; require `issue524_cwv_selector_bounded` and `issue524_all_cwv_blacksmith_selectors` PASS.

## 0.8.75-dev (2026-07-14): #598 safe modded TAB frames [verify-fix-coop]

- Restored CIM's modded rarity frame/background in the hold-TAB equipment preview through a same-mod, schema-gated boolean presentation side channel. Vanilla loadout RPCs continue to transmit the safe `unique` rarity.
- Custom icons render only when the receiving peer's local atlas confirms the texture. No custom icon, model, material, package, or skin resource identifier is added to the wire; peers missing CIM or the owning appearance mod retain a vanilla-safe fallback.
- Added bounded payload, schema mismatch, missing-package, hot-join, and local frame regression coverage.

### Co-op verification

Verify the intended modded frame in hold-TAB with two CIM-capable peers, then repeat with one peer missing CIM or the appearance-owning mod. No peer may crash or resolve an unknown custom resource, and the capable peer must retain its local appearance. Exercise host/client reversal, hot join, and mission transition, then run `/cim_regression_test`.

## 0.8.74-dev (2026-07-14): #244 literal Athanor property values [verify-fix] [not deployed]

- Fixed the Athanor writing its absolute Weave bubble fraction directly into an ordinary item's normalized Adventure property field. Three of five Attack Speed bubbles previously stored `0.6`; vanilla then interpolated that across the 3%-5% Adventure range and displayed/applied 4.2% instead of the forged 3%.
- Added a symmetric conversion for two-endpoint Adventure ranges: bubble writes translate the absolute picker value into normalized storage, and item reads translate the stored value back into the original bubble count. A normalized zero remains a present low-end property instead of disappearing on reopen.
- Descending signed ranges (for example reduction properties) use the same bounded conversion. Existing special handling for stamina, movement speed, scalar values, and discrete bonus tables is unchanged.
- Source boundary: the Athanor displays `UIUtils.get_weave_property_value_text` from its scalar Weave maximum (`ui_utils.lua:115-135`), while ordinary item descriptions and buffs interpolate the stored value across the Adventure range (`ui_utils.lua:137-173`; `buff_extension.lua:207-237`).
- Added pure policy coverage and runtime regression `issue244_athanor_literal_property_values`.

### Test method
1. In the Athanor, set Attack Speed to three bubbles (3%), apply it, and inspect the item in inventory/customization; it must show 3%, not 4.2%.
2. Leave and reopen the Athanor; the same property must still occupy three bubbles.
3. Repeat at four and five bubbles; the item must show 4% and 5% respectively.
4. Check one reduction property with a descending signed range, then confirm stamina and movement speed retain their established special behavior.
5. Run `/cim_regression_test` and require `issue244_athanor_literal_property_values` PASS.

## 0.8.73-dev (2026-07-14): #414 exact-slot Chaos Wastes trait rerolls [verify-fix] [not deployed]

- Fixed `Allow Chaos Wastes traits` flattening every CW trait category into every weapon. Standard-bench rerolls now add only the three vanilla melee families to melee weapons and only the six vanilla ranged families to ranged weapons.
- The Athanor picker now derives the selected item's exact `data.slot_type` and applies the same policy. Its accessory view has no selected weapon, so it receives no CW weapon-trait extras. `Allow any trait and property` remains intentionally unrestricted.
- Shared/universal boons still appear for both weapon slots because vanilla lists those traits in both category families; melee-only and ranged-only traits no longer cross slots.
- Added pure policy tests plus runtime regression `issue414_cw_traits_preserve_slot_family`.

### Test method
1. Enable `Allow Chaos Wastes traits`, reroll a melee weapon repeatedly, and confirm no ranged-only boon appears.
2. Reroll a ranged weapon repeatedly and confirm no melee-only boon appears.
3. Inspect both weapons in the Athanor picker, then open the accessory view; weapon traits must remain exact-slot and accessories must receive no CW extras.
4. Run `/cim_regression_test` and require `cw_trait_pool_includes_boons` and `issue414_cw_traits_preserve_slot_family` PASS.

## 0.8.72-dev (2026-07-13): #524 one bounded CWV acquisition selector [verify-fix] [not deployed]

- Completed the #592 ownership split: CWV registers definition-only `ItemMasterList` rows, while CIM alone creates and persists owned instances. The standard Craft Item grid now runs through one pure acquisition-selector policy instead of an ad hoc key scan.
- Canonical identity prefers CIM's explicit acquisition key and CWV's self-identifying `cwv_key`, with the historical `cwv_<key>_NNN` backend shape as compatibility fallback. This prevents inherited base `.key`/`.name` fields from producing another 300-power selector beside the same CWV weapon.
- The policy compacts stale/repeated CIM selectors, gives a real default-rarity blacksmith row precedence, ignores modded-rarity crafted instances for selector ownership, and appends missing selectors in deterministic key order. Repeated craft and repeated-injection coverage proves the bound remains one selector per CWV key.
- Source boundary: vanilla `can_craft_with` admits only melee/ranged/accessory rows whose backend rarity is `default` (`backend_interface_common.lua:498-508`); CIM crafts remain `modded` and persist only through `_forged_weapons`. No PlayFab write, migration, deletion, or CWV acquisition is added.

### Test method
1. Open the standard Craft Item grid with CIM and CWV enabled and note one blacksmith/base selector for Imperial Longsword.
2. Craft that weapon twice, leave and reopen the grid, and confirm there is still exactly one selector for Imperial Longsword, not one additional 300-power row per craft.
3. Confirm both crafted Modded-rarity instances remain separately visible in the ordinary inventory and run `/cim_regression_test`; require `issue524_cwv_selector_bounded` PASS.

## 0.8.71-dev (2026-07-13): #521 hover tooltip follows weapon panel [verify-fix]

- The first #521 fix removed vanilla's extra equipped-comparison card, but CIM still parented its one shared tooltip to the center viewport for both weapon slots. The ranged card therefore appeared over the primary panel position.
- The tooltip now composes the exact vanilla scenegraph offsets: panel 1 is `-545`, panel 3 is `+545`, with CIM's existing 10px inset. Hovering melee uses `-535`; hovering ranged uses `+555`. Item identity and the one-popup guard are unchanged.
- Runtime regression `issue521_tooltip_follows_hovered_weapon` locks both anchors, their 1090px separation, and any live applied position.
- **Verify:** hover primary and secondary weapon viewports in the Athanor overview. Exactly one card should appear beside the matching hovered viewport and clear on mouse-out. No co-op player is required.

## 0.8.70-dev (2026-07-13): #246 Hold-Tab exact illusion icon [verify-fix-coop] [not deployed]

- Source audit confirmed that Hold-Tab renders `Managers.player:player_loadouts()`, but vanilla `rpc_sync_loadout_slot` omits weapon-skin identity and reconstructs only the base item. The separately synchronized live inventory equipment does retain the exact `skin` key from `rpc_add_equipment`.
- After the player-list refresh, CIM now reconciles only the melee and ranged icons from each live inventory slot's exact registered skin. The same item receives that skin for the existing tooltip path. Default skins clear stale preview state; missing slots or unregistered icons fail closed.
- No new RPC, network value, package load, backend read, or per-frame allocation is introduced. An unknown synchronized skin emits at most one raw-console `[cim:246]` line per key.
- Added pure resolver coverage in `test_cim_tab_preview.lua` and runtime check `issue246_tab_preview_exact_skin_icon`.

### Test method
1. With two CIM users, equip a visibly non-default melee illusion on one player and a different non-default ranged illusion on the other.
2. Have each player hold Tab and verify both remote weapon icons and hover tooltips match the visibly equipped illusions.
3. Swap one illusion to another and one weapon back to its default skin; hold Tab again and verify both changes appear without stale icons.
4. Repeat once as host viewing client and once as client viewing host. Run `/cim_regression_test` and require `issue246_tab_preview_exact_skin_icon` PASS.

## 0.8.69-dev (2026-07-13): #263 modded-rarity upgrade copy [verify-fix] [not deployed]

- Added the missing global `upgrade_description_text_modded` string used by vanilla's customization option card, replacing the blank subtitle with one sentence explaining the Modded rarity.
- Filled the same copy into the detailed Upgrade state after vanilla returns early for custom rarities. The patch does not change recipes, costs, button locks, or rarity transitions, and leaves vanilla-rarity copy untouched.
- Added runtime check `issue263_modded_upgrade_copy` for the global localization, modded detailed-state fallback, and vanilla-rarity no-op boundary.

### Test method
1. Open a weapon that can still be upgraded in the gear-icon customization viewer; verify its existing vanilla Upgrade text and behavior are unchanged.
2. Open a Modded-rarity weapon; verify the Upgrade option and its detailed view show the one-sentence Modded-rarity description rather than a blank label.
3. Run `/cim_regression_test` and require `issue263_modded_upgrade_copy` PASS.

## 0.8.68-dev (2026-07-13): #277 exact-owner bulk weapon cleanup [verify-fix] [not deployed]

- Added `/forge_delete_all` as a two-step destructive workflow: the first call previews and snapshots the exact candidate set; `/forge_delete_all CONFIRM` proceeds only if that set is unchanged.
- Candidates come only from CIM's `_forged_weapons` acquisition store and must resolve to an ItemMasterList `melee` or `ranged` row. Rarity-only items, UUID/CWV-prefix guesses, ordinary backend items, accessories, and unavailable definitions are retained.
- The preflight queries both current equips and every saved loadout using vanilla's `equipped_by` and `is_equipped_by_any_loadout` surfaces. Any equipped candidate or unavailable equip state refuses the entire batch with no partial delete.
- A confirmed batch deletes the exact local mirror rows, legacy MoreItemsLibrary rows when present, forged persistence records, dormant CIM loadout references, and exact-ID illusion overrides, then persists/refreshes once. The existing `/forge_delete` command now shares the same cleanup path and also refuses equipped/uncertain items.
- Source boundary: `PlayFabMirrorBase.remove_item` only unmarks the exact id as new and clears `_inventory_items[backend_id]` (`playfab_mirror_base.lua:2547-2555`); `BackendInterfaceItemPlayfab.is_equipped_by_any_loadout` scans every career loadout (`backend_interface_item_playfab.lua:785-801`). No PlayFab remove request, commit, hook, RPC, or network value is introduced.
- Added pure policy module `_cim_bulk_cleanup_core.lua`, offline suite `test_cim_bulk_cleanup.lua`, and runtime check `issue277_bulk_cleanup_exact_owner_transaction`.

### Test method
1. Craft two weapons and one accessory; unequip both weapons from every current and saved loadout.
2. Run `/forge_delete_all`, verify the preview counts, then run `/forge_delete_all CONFIRM` and confirm only the two weapons disappear.
3. Restart and confirm the deleted weapons do not return, while the accessory and ordinary inventory are unchanged.
4. Negative cases: equip a CIM weapon and verify the batch refuses; preview, craft another weapon, and verify stale confirmation refuses; disable a source mod and verify its unresolved saved record is retained.
5. Run `/cim_regression_test` and require `issue277_bulk_cleanup_exact_owner_transaction` PASS.

## 0.8.67-dev (2026-07-13): #592 exact crafts are the only CWV ownership [untested]

- CWV supplies definition-only rows, so CIM injects the one acquisition template and no longer deduplicates against historical CWV-owned `_001` items.
- `_cim_is_modded_backend_id` recognizes only exact `_forged_weapons` entries; a `cwv_` prefix alone is not ownership. This preserves legitimate CIM crafts while stale auto-grant loadouts become purgeable.
- Verify with CWV 0.1.397-dev; `/cim_regression_test` must pass `cwv_registration_is_not_acquisition`.

## 0.8.66-dev (2026-07-13): #563 newest explicit illusion wins [verify-fix]

- Reopened-log root cause: the original exact-backend-ID fix saved only inside CIM's `_cim_try_illusion_apply` helper. In the in-mission customization flow, cosmetics_tweaker owned the local craft bypass, successfully changed `54DB495DEA391FF` from the old CWV runed skin to `es_2h_sword_skin_06`, and completed through vanilla's UI—but CIM emitted no save/update. The next mirror-ready edge therefore reapplied the stale saved CWV skin.
- Added one exact-ID, copy-on-write persistence helper used by CIM's local craft path and a new observer on vanilla's semantic completion seam, `HeroWindowItemCustomization._apply_weapon_skin_craft_complete`. The customization window retains the latest clicked skin as unpersisted intent and consumes it only when Apply succeeds, so even a mirror-ready callback between craft start and completion cannot turn stale A into the committed value. Keep, mission, CIM-owned, and Cosmetics-owned flows now atomically replace the saved override with B. CIM-owned crafts persist to their forge record and clear any stale vanilla override for the same ID.
- Bounded `[cim:563] explicit_saved`, `explicit_cleared`, and `craft_saved` diagnostics fire only on a persisted state transition. The runtime regression now proves old saved A -> explicit B -> mirror-ready plans B, preserves same-template sibling IDs, and clears stale vanilla state when forge ownership applies.

## 0.8.65-dev (2026-07-13): #563 persist vanilla illusion overrides by exact backend ID [diagnostics-armed]

- Server-owned weapons now save local illusion overrides by exact backend instance ID, so a PlayFab mirror rebuild cannot silently restore the server-side `CustomData.skin` over the user's modded-realm choice.
- Overrides rehydrate only on the mirror-ready edge, prune missing backend IDs, and defer temporarily unavailable sibling-mod skins. They never key by weapon template, so two copies of the same weapon retain independent illusions.
- Raw `[cim:563] saved`, `rehydrated`, `pruned_missing`, and `ready_rehydrate` diagnostics expose the lifecycle. `/cim_regression_test` adds `issue563_vanilla_skin_override_exact_backend_id`.

## 0.8.64-dev (2026-07-13): #562 auto-equip new weapons [verify-fix]

- Added `Automatically equip newly crafted weapons`, default ON. A successful Athanor primary/secondary craft now writes the exact new backend ID to the selected loadout index and recreates the live weapon unit in that same slot. This keeps the loadout record and visible avatar synchronized instead of reviving issue #12's historical icon-only divergence.
- Standard-forge, jewelry, and accessory craft paths are unchanged. Turning the option OFF preserves the Athanor's prior inventory-only behavior.
- Added `/cim_regression_test` check `issue562_auto_equip_contract`: pins the default-ON widget, exact weapon-slot mapping, accessory exclusion, helper availability, and post-use state witness (`backend_id`, target slot, selected loadout index).
- Source basis: `BackendInterfaceItemPlayfab.set_loadout_item` forwards its optional index to the mirror (`backend_interface_item_playfab.lua:635-667`); vanilla's inventory equip path couples the loadout write with a live equipment request and refresh event (`hero_view_state_overview.lua:1070-1139`).

## 0.8.63-dev (2026-07-13): #427 _dbg_alert log-only via engine printf [untested]

- `_dbg_alert` rerouted mod:warning -> pcall-guarded engine printf (VMF warning channel posts to chat under default settings; printf survives mod-logging-OFF, never chat; enemy_tweaker issue 240 template). `crafting_in_modded_dev.lua` only; the v0.7.51 rehook-warning interceptor on `mod.warning` is untouched.

## 0.8.62-dev (2026-07-13): #521 Athanor weapon-slot hover shows exactly ONE popup [untested]

- **#521 (FIX): hovering the equipped melee or ranged slot on the Athanor overview popped BOTH weapons' item popups at once.** The hover popup is cim's own widget (`UIWidgets.create_simple_item_tooltip`, added in 0.3.12-dev, driven from `_forge_apply_ui_polish`); the vanilla weave forge overview has no item tooltip on those viewports at all (`viewport_button_1/3` are bare `create_simple_hotspot`s, `hero_window_weave_forge_overview_definitions.lua:1978-1980`).
  - Root cause: the vanilla `item_tooltip` UI pass AUTO-appends "currently equipped" comparison boxes whenever the widget content does not set `no_equipped_item` - it walks the career loadout and draws every item sharing the hovered item's `slot_type` with a different `backend_id` as an extra popup box (`ui_passes.lua:3599-3645`, append at `:3638-3641`). Under cim/wt modded-realm loadouts the two weapon slots can hold items of the same `slot_type`, so hovering either slot rendered the hovered weapon's box PLUS the other equipped weapon's box.
  - The deus run-stats screen - the exact template cim's `tooltip_passes` list was copied from - suppresses that compare box with `content.no_equipped_item = true` (`deus_run_stats_ui_definitions.lua:955/961`). cim missed the flag when the widget was added.
  - Fix: set `tt.content.no_equipped_item = true` at widget creation. Every second-box path in the pass (explicit `equipped_item` at `:3599` and the loadout walk at `:3609`) is gated on that flag, so the widget now renders exactly one popup: the hovered slot's.
  - New `/cim_regression_test` check `forge_tooltip_no_equipped_compare` (io-safe per issue 511): reads the widget content via the new `mod._cim_tooltip_content` anchor once the forge has been opened; falls back to a source needle otherwise.
- `crafting_in_modded_dev.lua` - one-flag fix + rt anchor + regression check; `MOD_VERSION` `0.8.61-dev` -> `0.8.62-dev`.

## 0.8.61-dev (2026-07-13): #481 round 2 - LA-shield forge-preview probes armed (first-open miss + left offset) [diagnostics-armed]

User retest of the 0.8.58 fix (#481) reported two residual defects on LA custom-mesh shields in the Athanor: (1) the shield is ABSENT on the FIRST forge open and only appears after switching to another weapon and back; (2) when it does render, it sits offset LEFT of where the vanilla shield sits (reproduced on spear+shield and the bretonnian sword+shield). The attached 0.8.58 log has NO `[cim] forge 3D preview skipped` line, so the preview guard passed on the failing open - the miss happens inside the vanilla/cosmetics spawn chain (either the LA path never entered `spawn_data`, or the unit spawned invisible/off-frame). The offset is the same class as the ranged far-left defect (issue 404, diagnostics-armed): per-mesh placement measurable only at runtime, and the 0.8.58 log predates the issue-404 probe, so per the diagnose-before-mitigating + no-UI-guessing doctrine this build arms measurement instead of shipping a guessed correction.

- **Intake probe:** the existing `LootItemUnitPreviewer._load_item_units` hook now dumps (forge-only) the item key/skin/backend_id and every queued `spawn_data` entry's unit path + `Application.can_get` package/unit residency - distinguishes "LA mesh never queued" from "queued but not rendered". One line per item present, user-action-bounded.
- **Per-spawn dump:** the issue-404 `spawn_units` probe dropped its once-per-item-key latch (it masked exactly the first-open vs re-select difference the user reported) and now also prints each unit's `spawn_data` path (LA mesh vs vanilla) plus `n_data` vs `n_units`.
- **Post-cosmetics snapshot (new `hook_safe` on `LootItemUnitPreviewer.update`, forge-gated, one-shot per previewer):** cosmetics_tweaker loads after cim, so its `spawn_units` wrapper is OUTERMOST - its LA offhand paint and kind-unit 2x preview scale run AFTER cim's spawn hook body, invisible to spawn-time reads. Vanilla spawns preview units from inside `update` (`loot_item_unit_previewer.lua:95` -> `_spawn_items` assigns `_spawned_units` at `:532`), so the first post-update pass reads the final world position, delta from the spin pivot, and local scale the user actually sees. If the 2x LA preview scale is doubling the mesh's lever arm from the link node in the forge world, this line proves it (and the fix then belongs on the cosmetics side, context-gated). No prior cim hook on `(LootItemUnitPreviewer, update)` - grep-verified; cosmetics' own update hook is a different mod and chains.
- **Doctrine fix:** the guard-skip notice in `_forge_preview_unsafe` switched from `mod:info` (invisible with mod logging off) to engine `printf` `[cim:481]`, so the next report always shows whether the guard fired.
- New `/cim_regression_test` check `forge_preview_la_diagnostics_armed` (io-safe per issue 511): fails if either probe is stripped while #481 is open; runtime anchor on `mod._cim_forge_preview_unsafe`.
- `crafting_in_modded_dev.lua` - probe bodies + printf swap + regression check; `MOD_VERSION` `0.8.60-dev` -> `0.8.61-dev`.

## 0.8.60-dev (2026-07-12): #524 stop double-injecting a blacksmith template for CWV weapons [untested]

- **#524 (FIX): the standard Craft Item grid showed a DUPLICATE 300-power "base item" for every Character Weapon Variants (CWV) weapon, on top of CWV's real 5-power blacksmith template.** cim's `_cim_inject_templates` mints a synthetic default-rarity blacksmith template (at `base_power`, default 300) for every craftable `ItemMasterList` key, deduping against items already in the recipe grid. CWV registers each non-skin-only variant as its OWN default-rarity blacksmith template (backend_id `cwv_<key>_001`, power 5), which already passes vanilla `can_craft_with` and sits in the grid - but that item carries the INHERITED base `.key`/`.name` (e.g. `es_bastard_sword`; CWV never clobbers them per `clone_name_clobber`, and `item_master_list.lua:110-112`'s boot `item.key = key` stamp ran before CWV inserted its entry). The dedup keyed only on `.key`/`.data.key`, recorded `es_bastard_sword`, and MISSED `tpl.key == "cwv_es_longsword"` - so cim injected a REDUNDANT synthetic template. The power divergence (300 vs 5) only became visible after v0.7.24 raised the synth template from a hardcoded 5 to `base_power`; before that both read 5 and the duplicate was invisible.
  - Root confirmed from log + source + the user's persisted mirror: every crafted CWV item is `rarity="modded"` (`[cim] Crafted cwv_es_longsword ... rarity=modded bid=cwv_es_longsword_100`), which vanilla `can_craft_with` (rarity=="default" only, `backend_interface_common.lua:498`) provably EXCLUDES - so the crafted instances themselves never enter the grid. The 300-power duplicate is purely the mis-deduped synthetic template.
  - Fix: `_cim_inject_templates` now also derives the cwv key from a `cwv_<key>_NNN` backend_id (`^(cwv_.-)_%d%d%d$`, CWV's own render-rescue pattern) when building `seen_keys`. CWV's `cwv_<key>_001` template is in the grid, so its cwv key is now recorded and the synthetic twin is suppressed. Only suppresses cim's synth when a REAL CWV blacksmith item for that key is present, so weapons CWV does not register stay craftable via the synth as before.
  - Nothing persisted / no migration: the synthetic templates are UI-session-only injections rebuilt each session, never written to the save. They stop appearing next session with zero cleanup. The user's real crafted CWV items (`rarity="modded"` in `_forged_weapons` + the mirror) are untouched - they were never showing as base templates and still equip/salvage normally.
  - New `/cim_regression_test` check `cwv_blacksmith_template_not_double_injected` (io-safe #511): runtime anchor on `_cim_inject_templates` + the `_cim524_cwv_blacksmith_dedup` marker + the `cwv_<key>_NNN` key-derivation.

## 0.8.59-dev (2026-07-12): #404 Athanor trait/property picker fills natively; ranged preview offset measured [untested]

Two distinct render defects behind one broken Athanor screen (#404), tracked separately.

- **#404 defect 1 (FIX): the trait/property picker opened with ZERO rows for every weapon.** The Athanor picker enumerates `WeaveTraits.categories[cat]` / `WeaveProperties.categories[cat]`, where `cat` is the item's `trait_table_name` / `property_table_name` (vanilla stamps it at `hero_window_weave_properties.lua:178/186`). For an adventure/CW weapon that key is not a weave category, so `_cim_ensure_weave_category_pools` seeds an empty `{}` pool (dodges `ipairs(nil)`). That empty pool was only ever filled by `_cim_apply_forge_freedom`, which was gated behind the `allow_cw_traits` / `allow_any_trait_property` toggles - both default OFF - so the picker rendered empty for everyone.
  - Root cause confirmed from source: `_setup_menu_options` builds each row from `WeaveTraits.categories[category]` (`:370`) / `WeaveProperties.categories[category]` (`:531`); an empty category array => zero `entries` => empty picker.
  - Fix: `_cim_widen_category` now ALWAYS seeds the weapon's OWN native adventure pool into the category (new `_cim_native_bares_for`, reading `WeaponTraits.combinations[category]` / `WeaponProperties.combinations[category].exotic` - the same pools the standard bench rerolls from), surfaced as the existing `weave_`-twin display stubs. The two freedom toggles now ADD cross options on top of that base instead of gating it. `_cim_apply_forge_freedom` runs for every category in play regardless of toggle state.
  - Secondary (partial-init): the `_sync_backend_loadout` pcall guard now completes `_populate_menu_widgets` (which vanilla calls at `:1753`, and which sets each row's title/icon at `:626-636`) after a guarded throw, so seeded rows still render if the unknown-category tooltip section throws. printf `[cim:404]` in that branch (the pre-existing `mod:warning` is invisible with logging off) so a repeat report shows the path fired.
  - New `/cim_regression_test` check `native_pool_seeded_into_picker_with_toggles_off` (io-safe): drives `_cim_apply_forge_freedom` for a melee-category weapon with both toggles off and asserts the picker category array is non-empty, then restores.
- **#404 defect 2 (DIAGNOSTICS-ARMED, no speculative UI change): ranged weapons render far-LEFT in the 3D preview.** Root confirmed from source: `_create_item_previewer` puts the spin pivot at a uniform `preview_position` (`{-0.85,3,0}`, `:2954`); each hand unit links at `item_template.<hand>_hand_attachment_node_linking.third_person.display` (`loot_item_unit_previewer.lua:292/310`), a node authored for the 3P character hand, so a long two-handed ranged mesh orbits wide of the pivot. The corrective shift is per-weapon (each mesh's hand-node translation differs) and only measurable at runtime, so per the no-VMF-UI-guessing rule this ships a measurement, not a guessed offset: a `mod:hook` on `LootItemUnitPreviewer.spawn_units` (singleton, gated on `_custom_forge_active`) prints `[cim:404]` each spawned unit's world position + delta from the spin pivot, once per item key (also surfaces `n_units=0` if a ranged preview is being stripped). The measured offset feeds the follow-up preview-position fix.

## 0.8.58-dev (2026-07-12): #481 Athanor shows the model preview for LA-skinned shields [untested]

- **#481: opening the Athanor on a weapon whose shield uses a Loremaster's Armoury skin (via cosmetics_tweaker's offhand picker) showed NO model at all - weapon and shield both suppressed.** The forge preview guard `_forge_preview_unsafe` (the CTD shield for CW/deus weapons whose units aren't resident in the forge world) classified LA custom-mesh shields as "missing" and skipped the whole `LootItemUnitPreviewer` spawn. The same shield renders fine in the normal cosmetics customization preview, which uses the same spawn path without the forge gate.
  - Root cause: `pkg_missing()` treated a held unit as unloadable when `Application.can_get("package", <unit>_3p)` was false. LA (`kind="unit"`) shields - e.g. the Kerillian elf shields, Empire basic shields - are bundled in LA's ONE globbed master package (`units/*`) with a compiled `<unit>_3p` unit but NO per-unit `<unit>_3p` `.package` file, so the package check false-failed. LA's `PackageManager.load` silencer no-ops `load_package` on those paths and the `_3p` unit is already resident, so `World.spawn_unit` succeeds - which is why the normal cosmetics previewer works (LA_SYNC_MODEL section 3).
  - Fix: `pkg_missing` now also accepts a held unit when its `<unit>_3p` UNIT resource is resident (`Application.can_get("unit", ...)`), which is exactly what `World.spawn_unit` needs. A genuinely absent CW/deus unit (the Trollhammer `dr_deus_01` case that the guard was written for) is resident in neither form, so it still returns missing and stays skipped - the CTD protection is unchanged.
  - Degrade path preserved: any resolution error in `_forge_preview_unsafe` still defaults to UNSAFE (skip preview), so a broken LA state loses the cosmetic preview rather than crashing.
  - New `/cim_regression_test` check `forge_preview_accepts_resident_3p_unit` (io-safe per #511): asserts the `can_get("unit", ...)` residency fallback is present in `pkg_missing` and the `mod._cim_forge_preview_unsafe` runtime anchor is exposed.

## 0.8.57-dev (2026-07-12): #511 io-safe regression checks: source-reads no longer throw in the retail sandbox [untested]

- **#511: the `/cim_regression_test` source-pattern checks threw `attempt to index global 'io' (a nil value)` in the retail client and reported FALSE FAILs.** The VMF retail Stingray VM registers no `io` library (mods are `loadstring`'d into the game's shared `_G`; the engine registers `os` but not `io`), so every `io.open` self-read threw and the runner's `pcall` surfaced it as a check FAIL on healthy code.
  - NEW `_rt_src_read(path)` helper (next to `_rt_register`): guards `rawget(_G,"io")` and returns nil when `io` is absent, so a check's existing "unreadable source => skip (PASS)" branch runs instead of throwing. All 6 `io.open` source-reads route through it (5 inline blocks + the `read_all` local).
  - The three checks anchored on real public functions (`open_standard_crafting` x2, `open_forge`) gained an explicit runtime anchor assert so a module-load regression is caught in retail even with the source-text half skipped. The two hook-registration checks (`get_talent_required_forge_level` guard, `_populate_menu_option_widget` price-blank) anchor on the file-local `_rt_register`, so their source-text needles are skipped in retail and are listed as repo QA-gate candidates (PROJECT_STANDARDS 2.2b tier a); source IS readable under the modding-tools build / CI where they still run.

## 0.8.56-dev (2026-07-12): #500 remove the stale #174 loadout-attribution probe (closed issue) [untested]

- **#500: removed `_diag_probe.lua`** (issue 174, `[174:loadout]`, CLOSED). cim_dev's copy served ONLY the closed #174 channel (unlike the cosmetics_tweaker copy, which also carries the still-open `[cos:sync]` probes). Deleted the file (`git rm`), removed the `local PROBE = mod:dofile(".../_diag_probe")` import, and stripped the two embedded `if PROBE then PROBE.emit("174:loadout", ...) end` blocks (+ their `#174 probe` comments) from `_restore_modded_loadout` and `_capture_loadout_equip`.
- **No load-bearing behavior removed.** Both emit sites were pure observation embedded in load-bearing functions; the master-gate / capture / restore logic around them is kept byte-for-byte. `PROBE` had no other references (grep verified). The import line WAS the dofile-manifest entry, so no separate manifest edit; `.package` uses a `scripts/mods/crafting_in_modded_dev/*` glob.
- Untouched: `cim_debug.lua`'s `_LOADOUT_PROBE_SLOTS` and the `[mem-probe]` boot-footprint line are unrelated to #174 and stay.

## 0.8.55-dev (2026-07-12): OOP split - three self-contained concerns extracted into _cim_* modules [untested]

**Structural refactor (no behavior change).** The 8,173-line entry
`crafting_in_modded_dev.lua` is now 7,007 lines; three self-contained concerns were
lifted VERBATIM (each moved block byte-compared against the previous commit) into new
single-responsibility modules, dofile'd once each from the entry manifest (VMF
`mod:dofile` is NOT a singleton, so modules never dofile each other). Cross-file surface
stays the established flat `mod._cim_*` namespace. Module map + "where new code goes" in
the new `DEVELOPMENT.md`. Follows PROJECT_STANDARDS 2.2a and the enemy_tweaker/
cosmetics_tweaker/weapon_tweaker split precedents.

- **`_cim_mission_forge_safety.lua` (901 lines)** - every mid-mission render-safety guard
  for the Athanor + gear-icon customization preview: shading-env substitution
  (issue 83/228/235, uncatchable-AV class), preview-level strip + blend-variation pin,
  gamepad-GUI guard + `get_ui_renderer` fallback, `HeroView` HDR-gui skip +
  `hdr_renderer`/`hdr_top_renderer` fallback (issue 73, LA armoury_atlas crash), and the
  HDR-glow / skilltree-ring / bloom-pulse / upgrade-anim draw-site suppressors (Fix B..B5).
  Every guard gates on `_is_in_keep()`; the KEEP path is byte-unchanged. Publishes the
  mid-mission helpers on `mod._cim_*` (consumed by cim_debug.lua's on_enter re-suppression
  + the inline HDR regression checks). The issue-88 `HeroView.on_enter` inventory-access
  hook STAYS in the entry (it shares the entry-local `_cim_open_standard_inv_pending`
  with `open_standard_crafting`).
- **`_cim_inventory_filter.lua` (186 lines)** - the two BackendInterface filter hooks
  (`get_filtered_items` versus-twin re-hide + modded-only filter + template injection;
  `BackendInterfaceCommon.filter_items` salvage surfacing) + the `_cim_is_versus_key` /
  `_cim_is_leaked_versus_twin` discriminators (published on `mod._cim_*`) + `_WEAPON_SLOT_TYPES`.
- **`_cim_dump_commands.lua` (171 lines)** - the two read-only diagnostic chat commands
  `/cim_dump_active_window` + `/craft_dump` (engine reads only; no cim state touched).

- **Left byte-intact in the entry** (coupled to entry-mutable state or load-bearing crash
  paths, deferred to a later phase): the craft-store + backend mirror (`_forged_weapons`,
  reassigned on load), the cross-peer wire-safety region (issue 278/371), the LA
  equip-capture, the whole Athanor UI + Weaves economy (gated on the entry-local
  `_custom_forge_active`, 60 refs), and ALL regression check bodies (they close over entry
  state / call the namespace helpers at runtime - the weapon_tweaker precedent).
- **One regression check re-anchored:** `heroview_hdr_not_forcebuilt_in_mission` now
  source-scans `_cim_mission_forge_safety.lua` (its `_setup_hdr_gui` "Fix B skip" needle
  moved there) via `debug.getinfo(mod._cim_sweep_leaked_hdr_worlds or function() end, "S")`,
  matching the existing robust anchor pattern (open_forge / open_standard_crafting checks).
- **Verify:** lint PASS (13 files, 127 hooks, 0 duplicate-hook); `build` OK (4 bundles);
  `.package` globs `scripts/mods/crafting_in_modded_dev/*` so the new files auto-bundle.
  In-game: `/cim_regression_test` must still pass 100% (57 checks, unchanged); open the
  Athanor + gear-icon customize both in the keep AND (with Allow in mission ON) mid-mission
  to confirm the render-safety guards still fire; run `/craft_dump` + `/cim_dump_active_window`.

## 0.8.54-dev (2026-07-07) - issue 278 REGRESSION: default cim host CTDs non-cim clients on any crafted-item equip [verify-fix] [crash] [0-critical]

- SYMPTOM (issue 278 recurrence): a cim host crashes every player in the lobby who
  does NOT have cim, the moment the host equips a crafted item. Reproduces with
  DEFAULT settings (no toggles changed) - which is why it hit users broadly. Present
  in BOTH public cim (v0.8.33) and cim_dev; the reported crashes are on public cim.
- ROOT CAUSE: cim's sender-side wire-safety rewrite - swap the crafted item's
  "modded" rarity to a vanilla "unique" before `LoadoutUtils.sync_loadout_slot`
  encodes the loadout RPC - was, in the v0.8.15-dev "master gate", bundled behind the
  `persist_modded_loadouts` toggle (DEFAULT OFF). With the toggle off, the hook is a
  pure pass-through, so `rarity_id = NetworkLookup.rarities["modded"]` goes on the wire.
  Every crafted item carries "modded" rarity (modded_rarities.lua:212), and that id is
  undefined on a non-cim client, so it reverse-looks-up nil and fatals at
  `RaritySettings[nil].order` (loadout_utils.lua:73 -> deus_chest_extension.lua:232 /
  reward_popup_ui.lua:451). Wire crash-safety was wrongly coupled to a persistence
  feature. The v0.8.51-dev receiver-side unknown-id guard does NOT help here: it runs
  on a peer that HAS cim, but the crashing peer is the one WITHOUT it.
- FIX (crafting_in_modded_dev.lua sync_loadout_slot hook): hoist the "modded"->"unique"
  wire rewrite OUT of the persistence gate - it now runs UNCONDITIONALLY whenever a
  "modded" item is synced. Only the cim<->cim `cim_modded_slot` side-channel (which
  merely restores modded chrome on cim clients; vanilla drops it) stays gated by
  `persist_modded_loadouts`. Wire safety is now independent of every toggle, per the
  issue-371 mandate (no mod may ever crash a peer that lacks it).
- SCOPE: this is the sender-side (host) protection for the RARITY axis. The item_names
  axis for crafted CWV variants is separately covered by CWV's own unconditional
  `LoadoutUtils.sync_loadout_slot` base-key substitution (cwv v0.1.365+). Needs the
  same fix promoted to PUBLIC cim (v0.8.34) to reach the crashing users.
- REGRESSION: `/cim_regression_test` -> `wire_rarity_rewrite_ungated` asserts the
  rarity coercion is not behind the persist gate. Needs a 2-player (cim host + vanilla
  client) verify.

## 0.8.53-dev (2026-07-07) - issue 407: CWV (and all) items fail to craft on the console/gamepad UI [verify-fix]

- SYMPTOM (issue 407): every craft attempt on the gamepad/console crafting UI is
  dropped with chat warning "Craft dropped - no recipe selected (recipe_override=nil)".
  User could not craft any CWV variant (e.g. cwv_es_axe_shield_veteran). Log shows
  `[craft_attempt] recipe=nil` on all five attempts, all on `HeroWindowCraftingConsole`.
- ROOT CAUSE: vanilla's console "Craft Item" page calls `parent:craft(items)` with NO
  recipe (craft_page_craft_item_console.lua:325) and relies on backend
  auto-detection (backend_interface_crafting_base.lua:42-50 iterates every recipe
  when recipe_override is nil). The PC page instead passes `self._recipe_name`
  explicitly (craft_page_craft_item.lua:322) - which is why crafting only broke on
  the gamepad UI, never on mouse+keyboard. cim's `BackendInterfaceCraftingPlayfab.craft`
  hook can't fall through to vanilla `func` (it would enqueue the EAC-gated PlayFab
  request and kick the player in modded realm), so on a nil recipe it simply dropped
  the craft.
- FIX (standard_forge.lua craft() hook): when recipe_override arrives nil, re-derive
  the craft-item recipe from the dropped item's `slot_type`, exactly as vanilla
  setup_recipe_requirements picks it (craft_page_craft_item_console.lua:80-84):
  melee/ranged -> craft_weapon, and cim's per-slot jewelry synths
  necklace -> craft_necklace, ring -> craft_charm, trinket -> craft_trinket (matching
  the setup_recipe_requirements pin at standard_forge.lua:330-333). Only the console
  craft-item page passes nil; every other console page (salvage/reroll/apply-skin/
  upgrade/extract/convert) already passes self._recipe_name, so a nil override
  unambiguously means craft-item. Mapping exposed as
  `mod._cim407_craft_item_recipe_for_slot` for the regression check.
- DIAGNOSTIC: `[cim:407] console craft-item: nil recipe resolved -> <recipe> (bid=.. slot=..)`
  via engine printf (always in log regardless of the debug-logging toggle).
- REGRESSION: `/cim_regression_test` -> `console_craft_item_nil_recipe_resolves` asserts
  each slot maps to the right synth, non-craftable slots resolve to nil, and every
  resolved recipe has a live synth registered.
- BUG_CLASS: added class 30 (modded craft intercept assumes recipe_override always
  non-nil - true on M+K, false on the console craft-item page).
- VERIFY (2-player not required; single-client gamepad test): open the Athanor forge
  with a controller active, drop a CWV weapon template into Craft Item, press craft.
  Expect a real `cwv_<key>_NNN` item minted (not the "no recipe selected" warning) and
  `[cim:407]` in the log. Repeat for a jewelry template (necklace/ring/trinket).

## 0.8.52-dev (2026-07-06) - issue 390: CWV variants crafted via cim rendered as the base vanilla weapon [verify-fix]

- SYMPTOM (issue 390, two confirmed repros of one root cause): a Nordland Claymore
  (`cwv_es_longsword_nordland`) crafted in cim rendered as a Bretonnian sword with
  wrong grips; a Kruber Rapier (`cwv_es_rapier`) crafted in cim still carried the
  Saltzpyre off-hand pistol. Both are CWV variants that render the BASE weapon's mesh
  and inherited attachments instead of the variant.
- ROOT CAUSE (base-units fallback, traced end-to-end): a CWV clone deliberately keeps
  the BASE weapon's `name` (name-clobber crashes equip, per CWV
  `feedback_cwv_clone_name_clobber.md`). The vanilla equip/preview path re-resolves
  item_data as `item_name = item_data.name` -> `ItemMasterList[item_name]`
  (world_hero_previewer.lua:674; also the backend_utils path), landing on the BASE
  entry, so `BackendUtils.get_item_units` returns the base mesh (Bret sword) and the
  base's inherited `left_hand_unit` (rapier pistol; the CWV entry nils it via
  `no_left_hand`). CWV compensates with hooks (get_item_units units override,
  `_resolve_cwv_def` grip transforms, illusion-picker filter) that ALL key on the
  `cwv_<key>_NNN` backend_id pattern. cim minted the crafted copy with a bare
  `Application.guid()` backend_id (standard_forge.lua), which matches none of them, so
  no rescue fired and the base weapon rendered. CWV's own items work because they
  carry `cwv_<key>_001` backend_ids.
- FIX 1 (craftable set): synthetic "blacksmith template" injection
  (`_cim_inject_templates`) now dedups on the item KEY, not `item_type`. CWV variant
  families share one item_type (Recruit / Black Guard / base longsword all
  `cwv_imperial_longsword`), so the old item_type dedup appended only ONE random
  member per family in non-deterministic pairs() order. Per-key makes every registered
  variant individually and deterministically craftable. skin_only CWV defs (Nordland)
  are never in ItemMasterList, so no template is minted for them - they stay correctly
  non-craftable (get the look via the real family member + the Nordland illusion in
  the cosmetic picker).
- FIX 2 (crafted-copy backend_id): CWV variant crafts now mint a `cwv_<key>_NNN`
  backend_id in the 100..999 instance band (CWV's own items are _001.._002, so no
  collision; uniqueness across crafts incl. restored ones via a persisted-craft scan)
  instead of a guid, so CWV's render-rescue hooks can recognize the crafted copy.
- FIX 3 (cim-side units rescue, self-contained): a new cim hook on
  `(BackendUtils, get_item_units)` (pre-flight grep confirmed cim only CALLED it, never
  hooked it) forces the CWV entry's `right_hand_unit` / `left_hand_unit` onto crafted
  CWV copies when no skin is applied. This makes the MESH correct (Nordland variant
  mesh; rapier drops the pistol) even before the CWV-side pattern widen lands. It
  leaves user-applied illusions alone (bails when `result.skin` is set).
- CWV-SIDE FOLLOW-UP (required for grips, routed separately): CWV's `_001`-literal
  backend_id patterns (character_weapon_variants.lua ~9533 grip transforms, ~9714
  units, ~9997 illusion filter, ~10094 cosmetic scale) must widen to `_%d%d%d` (the
  precedent already at ~9859) so grip/scale transforms and the illusion-picker filter
  also apply to crafted CWV copies. Until then, mesh is fixed cim-side but grips are
  not. This widen also fixes CWV's own latent `instances >= 2` bug (only _001 was
  matched).
- DIAGNOSTIC: `[cim:390]` printf on every CWV craft logs the resolved key, minted
  backend_id, and the CWV vs BASE entry per-hand units (shows the divergence the
  rescue bridges). Always-on in dev; fires only on a craft action.
- TEST: `_rt_register("cim390_cwv_craft_render_fix")` asserts the injection is
  key-keyed and the cim-side units rescue hook installed.
- IN-GAME VERIFY (cim_dev 0.8.52-dev; NOT confirmed yet): in the keep, craft a Nordland
  Claymore (`cwv_es_longsword_nordland` family longsword) - it must render the claymore
  mesh, not a Bretonnian sword. Craft a Kruber Rapier (`cwv_es_rapier`) - it must NOT
  carry the Saltzpyre off-hand pistol. Watch the log for `[cim:390] crafted CWV ...`.

## 0.8.51-dev (2026-07-06) - issue 278: guard clients against unknown item_names ids on loadout sync (receiver side)

- Companion to CWV 0.1.365-dev, which carries the PRIMARY (sender-side) fix and the
  issue-279 render fix. Crash: `console-2026-07-04-00.57.22-2cb5e90e` at 01:00:54 -
  a CLIENT decoding host `rpc_sync_loadout_slot` for a cim-crafted CWV ranged weapon
  hit `network_lookup.lua:2521: Table item_names does not contain key: 3243` via
  `loadout_utils.lua:70 create_loadout_item_from_rpc_data` (locals: `slot_name=
  "slot_ranged" item_id=3243 rarity_id=9 power_level=302`).
- Root cause is cross-peer index divergence, NOT a cim-minted key: cim never writes
  `NetworkLookup.item_names` (the crafted item reuses the statically-registered CWV
  variant key). Modded keys are index-appended (`#tbl + 1`) per peer, so the numeric
  wire id (`NetworkLookup.item_names[item.key]`, loadout_utils.lua:25) is peer-local.
  Decisive divergence in the 07-04 session: the host ran Loremaster's Armoury
  (enabled) whose clone entries cosmetics_tweaker's `_la_bridge.register_all` appends
  into item_names (`_la_bridge.lua:639-645`); the crashing client had LA DISABLED
  (`enabled="false"` in its ModManager list), so host id 3243 was past the client's
  table end.
- FIX (second layer, receiver side): cim's existing hook on
  `(PlayerManager, rpc_sync_loadout_slot)` converted from `mod:hook_safe` to a full
  `mod:hook` wrap (`_cim_consolidated_rpc_sync_loadout_slot_hook`; still the sole cim
  hook on the pair per the duplicate-hook pre-flight). Before vanilla decodes, the
  guard rawget-checks `item_id` against `NetworkLookup.item_names` and DROPS the RPC
  with a printf ALERT (`[cim:278] ALERT dropped rpc_sync_loadout_slot ...`) when the
  id is unknown on this peer - an unknown id can no longer CTD a cim client, whatever
  mod produced it. The pre-existing post-decode "modded"-rarity restore is unchanged
  and runs after the wrapped vanilla call; all 11 vanilla params are threaded through
  so the server relay (player_manager.lua:83) stays intact.
- TEST: new `_rt_register("rpc_sync_loadout_unknown_id_guard")` - asserts the wrap
  hook installed and sanity-checks the guard's rawget decision against a known-vanilla
  id and an absurd sentinel id.
- In-game verify (BOTH peers on cim_dev 0.8.51-dev + cwv 0.1.365-dev, full Steam
  restart each): host equips a crafted CWV ranged weapon in the keep with a client
  connected; the client must not crash.

## 0.8.50-dev (2026-07-05) - #239 CLOSED (user-confirmed in-game): hide the meaningless "Cost: 0" readout in the modded Athanor

- #239 CLOSED - user confirmed the v0.8.45-dev fix works in-game. The modded Athanor
  fakes all essence/mastery costs to 0 (free crafting), so the vanilla per-option
  "Cost: 0" readout on every trait/property/talent row is meaningless clutter. The
  hook_safe on `HeroWindowWeaveProperties._populate_menu_option_widget` blanks
  `content.price_text` and zeroes the separate `price_icon` alpha while
  `_custom_forge_active` (per-widget, layout-safe, modded-forge only). The fix itself
  is unchanged (live since v0.8.45-dev); this build adds the regression guard on close.
- TEST: new `_rt_register("weave_forge_hides_cost_readout")` source-pattern guard -
  asserts BOTH the `_populate_menu_option_widget` hook and the `price_text` blank
  survive, so the Cost:0 readout cannot silently return (`/regression_test`).

## 0.8.49-dev (2026-07-05) - #83 round 2: panel smoke + top-array raw textures (session 9cc7ebf2)

**CRASH FIX.** First in-mission Athanor test on v0.8.48-dev got PAST the blend layer (all three `[cim:83] forge viewport env` probes fired, `ui_store_preview` picked, resident) and crashed one frame later on the NEXT layer of the known keep-only-material class: `ui_passes.lua:194: Material 'forge_overview_top_glow_effect_smoke_1' not found in Gui`, from `HeroWindowWeaveForgePanel._draw` (log 18.29.57-9cc7ebf2, running v0.8.48-dev confirmed).

### Why the existing B5/B6 prune missed it (two gaps, one latent)

- The Panel mixes `top_glow_smoke_1` (`forge_overview_top_glow_effect_smoke_1`, `create_simple_uv_texture`, panel defs :525) into its NON-HDR `_bottom_widgets`. The B6 convergent rule pruned only `athanor_*` non-slot textures, so the smoke widget survived and fataled on the base mission Gui. Two sub-gaps: the prefix family was new, AND uv-texture widgets store `content.texture_id` as a TABLE (`{texture_id=..., uvs=...}`, `ui_widgets.lua:5638-5642`) that the string-only matcher could never match.
- LATENT: the Panel's `_top_widgets` (third loop of its `_draw`, on `ui_top_renderer`) carries six more raw widgets (`athanor_power_bg` x2, `athanor_decoration_corner` x4) that no fix ever iterated - the next crash in line once smoke_1 was gone. Confirmed raw by the v0.8.21 grep rule (only `athanor_skilltree_slot_*` is atlas-backed).

### Fix

`_cim_suppress_skilltree_rings_in_mission` extended: (a) raw-texture predicate now also matches the `forge_overview_top_glow_effect_*` family; (b) texture-name resolver unwraps the uv-table shape; (c) the prune covers BOTH `_bottom_widgets` and `_top_widgets` for all four forge windows (no-op on clean arrays). Keep path untouched as before.

### Regression test

`skilltree_ring_widgets_suppressed_in_mission` rewritten: fixture now includes a uv-table smoke widget in `_bottom_widgets` and a raw-populated `_top_widgets` (power_bg string + decoration_corner uv-table + slot + text widget); asserts both arrays filtered in mission, both intact in keep. Also fixes the test's own off-by-one keep-count (expected 7 of 8 fixture widgets - would have false-failed the keep assertion).

### In-game verify (#83, unchanged)

Enable "Allow crafting bench in mission", start an adventure mission, press the Athanor hotkey (B): forge opens and is usable, no CTD. Log shows the three `[cim:83] forge viewport env` lines.

### Files
- `crafting_in_modded_dev.lua` - predicate + resolver + two-array prune, call-site comment, test rewrite; `MOD_VERSION` `0.8.48-dev` -> `0.8.49-dev`.

## 0.8.48-dev (2026-07-05) - #83: re-enable the in-mission Athanor (blend-AV root fix, not a gate)

**FEATURE RESTORE + CRASH FIX.** The Athanor (weave forge) opens in missions again behind the `allow_in_mission` opt-in (the "Allow crafting bench in mission" toggle in Tweaker: GUI's In-Mission Menus), replacing the v0.8.23 hard keep-only gate. The gate existed because a render-level fatal (`script_world` `blend`) survived the Fix B/B2..B6 material/HDR hardening; that fatal is now root-caused and fixed instead of gated.

### Root cause (corrected via the #228/#235 investigation, cosmetics_tweaker 0.9.62..0.9.66-dev)

Two distinct shading failure modes were being conflated:

- A NON-RESIDENT shading-environment **resource** fails cleanly at world-create ("Resource not loaded" - the original `ui_weave_forge_preview` symptom, already fixed by the env substitution).
- Blending an UNDEFINED shading-environment **variation** is a native `ShadingEnvironment.blend` ACCESS VIOLATION (0xc0000005) that no pcall can catch. `ScriptWorld.render` blends the world's `shading_settings` every frame (`script_world.lua:122`); vanilla `HeroWindowItemCustomization._present_item` -> `_update_environment` writes the per-weapon variation `weapons_default_01` (`hero_window_item_customization.lua:1377-1381` / `:583-594`) into that blend target. cim's mission substitute env was the fixed `environment/ui_hdr`, which does NOT define that variation -> AV on the first rendered frame of the Customization view reachable from the forge surface. The weave-forge windows themselves never write blend variations (grep-verified: their only ShadingEnvironment call is the `set_fullscreen_effect_enable_state` blur set_scalar), so `_update_environment` is the sole variation writer on this surface.

### Fix (three parts, keep paths untouched)

1. **Residency-probed mission env picker** (`mod._cim_pick_mission_env`, replaces the fixed `_FORGE_MISSION_SAFE_ENV = "environment/ui_hdr"`): prefers `environment/ui_store_preview` (the keep's studio-lit item-preview env - probed RESIDENT mid-mission in #235's 0.9.65-dev instrumentation, host log 2026-07-03, and it DEFINES the per-weapon variations), then `environment/ui_hdr`, then `environment/blank` (boot-assets engine default, `game_settings_development.lua:33`, resident everywhere; vanilla's own gamepad forge world uses it, `hero_view_state_weave_forge.lua:145`). Probe = pcall'd `Application.can_get("shading_environment", name)`, evaluated at use time. Applied to the three weave-forge viewport worlds (`_swap_forge_env`) AND cim's mission ItemCustomization preview def. Bonus: with `ui_store_preview` picked, the mission 3D preview is studio-LIT instead of ui_hdr-black (#235).
2. **Blend-variation pin** (new `HeroWindowItemCustomization._update_environment` hook, dup-clean): in mission, vanilla's requested variation passes through only when the preview world's env defines it (`ui_store_preview`) or cosmetics_tweaker's #235 re-point flag (`cos_preview_env_repointed` World data) is set; otherwise `force_default=true` pins the blend to `"default"`, which every `create_world` env carries (`world_manager.lua:44`). Chains safely with cosmetics_tweaker's identical hook in either order (force_default=true is sticky in the safe direction).
3. **Gate change** (`mod.open_forge`): hard keep-only block -> `if not in_keep and not mod:get("allow_in_mission")`, mirroring `open_standard_crafting`. Fix B (no HDR worlds in mission; base-renderer fallback) and the B2..B6 draw-site suppressions are UNCHANGED - the mission forge still drops the keep-only HDR glow decorations.

### Diagnostics (always-on in dev, printf)

- `[cim:83] forge viewport env: <orig> -> <picked> (resident: store=... hdr=...)` per mission forge world.
- `[cim:83] _update_environment(mission): requested=... world_env=... repointed=... -> ALLOW / pin "default"` once per distinct request.
- `[cim:83] weave-forge set_fullscreen_effect_enable_state(...) fired in mission` (hook_safe probe on the one remaining ShadingEnvironment write on the forge surface; never implicated, breadcrumb only).

### Regression tests (/cim_regression_test)

- `forge_mission_env_picker_prefers_resident` - pins the store -> hdr -> blank preference order via injected probes.
- `customization_variation_pin_decision` - pins the allow/pin truth table (store allows, hdr/blank/nil pin, cosmetics re-point unlocks).
- `open_forge_gate_honors_allow_in_mission` - source-pattern: the opt-in gate present in BOTH entry points, the v0.8.23 hard-gate echo gone.
- `morris_hub_passes_open_forge_gate`, `heroview_hdr_not_forcebuilt_in_mission`, and all B2..B6 suppression tests unchanged (those layers stay).

### In-game verify (#83)

Enable "Allow crafting bench in mission" (Tweaker: GUI -> In-Mission Menus), start an adventure mission, press the Athanor hotkey (B): the forge should open and be usable (no CTD), with flat-but-lit weapon previews. The log should show the `[cim:83] forge viewport env` lines with `store=true`.

### Files
- `crafting_in_modded_dev.lua` - env picker + `_swap_forge_env` probe, ItemCustomization def env, `_update_environment` pin hook, `set_fullscreen_effect_enable_state` probe, `open_forge` gate, 3 new regression tests; `MOD_VERSION` `0.8.47-dev` -> `0.8.48-dev`.
- `crafting_in_modded_dev_localization.lua` - `forge_hotkey` title `[working] ... (Keep only)` -> `[verify-fix] [Issue 83] Open Athanor Crafting Menu`; description reflects the opt-in.

## 0.8.47-dev (2026-07-04) - Localization: dev status-tag audit (#301)

- Applied the dev localization status-tag doctrine (#301) to every widget-title loc entry.
- 13 titles tagged: 5 [working], 8 [untested], 0 issue-tagged. Added [working] to the 5 previously-untagged titles (forge_group, forge_hotkey, standard_crafting_hotkey, import_group, inventory_group); the 8 existing [untested] tags were verified and kept (no mapped issue closed).
- No open cim issue mapped high-confidence to a dedicated widget: the Athanor display/behaviour bugs (#244, #239, #86) and the illusion/skin bug (#150) have no dedicated toggle in the data tree; the in-mission-access issues (#88, #96, #83, #80) concern runtime patches or the widget that moved to Tweaker: GUI; the CWV-craft bugs (#279, #278, #226) and enhancements (#277, #263, #87) have no cim widget. Left untagged-with-issue per doctrine rule 5.

### Files
- `crafting_in_modded_dev_localization.lua` - [working] prefix on the 5 untagged widget titles; existing [untested] tags kept.
- `crafting_in_modded_dev.lua` - `MOD_VERSION` `0.8.46-dev` -> `0.8.47-dev`.

## 0.8.46-dev (2026-07-02) - 'Allow crafting bench in mission' widget moved to Tweaker: GUI (user direction)

- The `allow_in_mission` CHECKBOX no longer exists in cim's menu. The option now lives in
  Tweaker: GUI's "In-Mission Menus" group (shown there only when cim is installed - the
  same conditional-build treatment #96 used to apply on cim's side), and gut writes
  through to cim's `allow_in_mission` SETTING, so all main-lua readers
  (open_forge/open_standard_crafting gates, ~:1920) are untouched and existing stored
  values keep working.
- Removed with the widget: the #96 `_gut_present()` conditional-build machinery + loc
  entries; `standard_crafting_hotkey_description` retargeted at the gut option.
- Regression check replaced: `issue96_allow_in_mission_widget_moved_to_gut` (widget must
  NOT re-appear in _data.lua; the `mod:get("allow_in_mission")` readers must remain as
  gut's write-through target).

## 0.8.45-dev (2026-07-02) - Athanor picker follow-ups: trait descriptions (#238) + hide 0-cost (#239)

Two follow-ups to the v0.8.44-dev forge freedom toggles.

- **#238 - Chaos Wastes / injected traits now show their description in the Athanor picker.** The injected weave-twin display stub was omitting `advanced_description` + `description_values` (the crash-safe choice), so boon / adventure-only traits showed only a name. The stub now copies BOTH from the adventure `WeaponTraits` entry. That pair is authored consistently and the base game already renders it via `UIUtils.get_trait_description` in normal crafting, so copying both verbatim is exactly as safe as vanilla's own trait display (the `string.format` crash only occurs for a MISMATCHED pair, which the game never ships).
- **#239 - the modded Athanor no longer shows the meaningless "Cost: 0" on each option.** Crafting in the modded forge is free (cim fakes all essence/mastery costs to 0), so the per-option cost readout is clutter. A new `hook_safe` on `HeroWindowWeaveProperties._populate_menu_option_widget` blanks each option's `price_text` and hides the mastery cost icon (its own texture pass) while the modded forge is open. Per-widget, layout-safe (fixed row height), modded-forge only. The craft button was already relabeled to "CRAFT ...".

### Files
- `crafting_in_modded_dev.lua` - `_cim_ensure_trait_twin` copies the description pair (#238); new `_populate_menu_option_widget` hook_safe hides per-option cost (#239); regression test `trait_twin_copies_description_pair`; `MOD_VERSION` `0.8.44-dev` -> `0.8.45-dev`.

## 0.8.44-dev (2026-07-02) - Forge freedom toggles: Chaos Wastes traits + any-trait/any-property

Two new Athanor options (both default OFF, `[untested]`) widen what the forge will put on a craft. They act on BOTH craft surfaces - the Athanor bubble picker (where you choose) and the standard crafting bench (reroll / craft prefill).

- **Allow Chaos Wastes traits on crafted weapons** (`allow_cw_traits`) - normally the forge mirrors the official bench and drops the Chaos Wastes / deus "boon" traits (`crafting_disabled` traits like `deus_extra_shot`, `shield_splinters`, chain-lightning). ON surfaces those boon traits so they can be rolled at the standard bench and picked in the Athanor trait slot. Traits only.
- **Allow any trait and property on any weapon** (`allow_any_trait_property`) - normally a craft only draws traits/properties from its own slot type. ON pools every trait and every property across all slot types onto any weapon or accessory. Supersedes the Chaos Wastes toggle (its union already includes the boon traits).

How it works:
- **Standard bench** (`standard_forge.lua`) - the reroll and craft-prefill paths now resolve their trait/property pools through toggle-aware helpers (`_cim_trait_pool_for` / `_cim_property_pool_for`) that read live from `WeaponTraits`/`WeaponProperties` at roll time, so weapon_tweaker's runtime trait mutation is still honored. Default (both off) is byte-for-byte the previous behavior.
- **Athanor picker** (`crafting_in_modded_dev.lua`) - the `_setup_menu_options` hook widens the weave trait/property category the selected item uses. Because the picker renders each key from `WeaveTraits.traits`/`WeaveProperties.properties` and the apply path strips the `weave_` prefix to the bare adventure key, options that already have a native weave twin are reused, and boon / adventure-only keys get a crash-safe display stub injected (verified field-for-field against the vanilla picker: trait `display_name`; property `display_name` + registered `buff_name` + non-empty `description_values`). The store path is fully cim-owned when the modded forge is open (no `WeavePropertiesByCareer` fassert), so display stubs suffice. Category arrays are widened only while the modded forge is open and **restored on forge exit**, so real Weaves play is never polluted.
- Six `/cim_regression_test` markers added for the settings/helpers, the CW boon set, the default boon-filter, the twin-stub display field, and the restore.

### Files
- `crafting_in_modded_dev_data.lua` - two `allow_cw_traits` / `allow_any_trait_property` checkboxes in the Athanor group.
- `crafting_in_modded_dev_localization.lua` - titles + plain-English descriptions for both.
- `standard_forge.lua` - toggle-aware trait/property pool helpers; reroll + prefill routed through them; helpers exposed for regression tests.
- `crafting_in_modded_dev.lua` - Athanor picker widener + weave-twin injection + restore-on-exit (merged into the existing `_setup_menu_options` and `on_exit` hooks); regression tests; `MOD_VERSION` `0.8.43-dev` -> `0.8.44-dev`.

## 0.8.43-dev (2026-07-01) - Settings menu: sort top-level groups A->Z

Settings-menu ordering polish, no functional changes.

- Top-level groups now sort A->Z by display label: Athanor, Import, Modded Inventory (previously Athanor, Modded Inventory, Import).
- Modded Inventory group's two toggles now sort A->Z: "Ignore items from inactive mods" before "Show only modded weapons".
- Documented the Athanor group's deliberate functional child order (crafting hotkeys, then the in-mission permission, then craft-output toggles) so it is exempt from the A->Z rule.

### Files
- `crafting_in_modded_dev_data.lua` - reordered the group blocks and the inventory group's children; added ordering comments.
- `crafting_in_modded_dev.lua` - `MOD_VERSION` `0.8.42-dev` -> `0.8.43-dev`.

## 0.8.42-dev (2026-07-01) - Correct standard-bench description: it works in the Chaos Wastes

The standard crafting bench description wrongly claimed the bench "never opens in the Chaos Wastes" (a leftover from the pre-sweep text; user confirmed crafting works there). `standard_crafting_hotkey_description` now says it works in the Keep and the Chaos Wastes. Localization text only; no code changes.

## 0.8.41-dev (2026-07-01) - #174 loadout attribution probe (passive, log-only)

Added a passive, default-on diagnostic probe for issue #174 (bot loadouts replaced on startup by base blacksmith items in modded realm). No gameplay change - it only writes `[174:loadout]` lines to the engine console log via `printf` so a single post-playtest log names whether cim wrote or restored any loadout slots.

- New `_diag_probe.lua` - rate-limited `printf` emitter (logs on first-sight + on-change, with a startup window and a hard flood cap). Shared helper for the `[174:loadout]` channel.
- `_capture_loadout_equip` now logs every capture attempt (career/slot/item/index/from_live) AND the `persist` gate + `restoring` state, BEFORE the master gate returns - so a gated-off no-op is still visible.
- `_restore_modded_loadout` logs at entry whether startup restore even runs (`persist=false` = no-op = cim writes no slots, exonerating it for #174).

### Files
- `_diag_probe.lua` (new) - probe emitter.
- `crafting_in_modded_dev.lua` - loader + 2 probe calls; `MOD_VERSION` `0.8.40-dev` -> `0.8.41-dev`.

## 0.8.40-dev (2026-07-01) - Option menu localization fix + plain-English descriptions

Fixed a mod-options menu display bug and rewrote every option description to read as plain, player-facing text.

- **Menu display fix** - the "Ignore items from inactive mods" option had its tooltip wired so that VMF localized it twice, which made the whole English sentence show up wrapped in angle brackets in the options menu. It now displays the intended description.
- **Rewrote all option descriptions** - every option tooltip (and the mod's own description line) is now one or two plain sentences describing what the option does in game, with no leftover developer notes, version numbers, or internal wording. Titles and defaults are unchanged.

No gameplay behavior changes; menu text only.

### Files
- `crafting_in_modded_dev_data.lua` - the "Ignore items from inactive mods" tooltip now passes the localization key instead of the already-localized string (fixes the double-localize).
- `crafting_in_modded_dev_localization.lua` - rewrote all 10 option/mod descriptions in plain English (2 sentences max, no internal jargon, ASCII only).
- `crafting_in_modded_dev.lua` - `MOD_VERSION` `0.8.39-dev` -> `0.8.40-dev`.

## 0.8.39-dev (2026-07-01) — FIX: accessory buttons now play a sound + press feedback

The 0.8.38 diagnostic was conclusive: `[acc-panel] DIAG click has_music=false` — the click WAS registering (the craft fired every time), but the sound path was resolving a `wwise_world` off `Managers.world:world("music_world")`, and **that world is not registered in the weave-forge UI context**, so the Wwise trigger silently no-op'd. (`world=true ww=true` in the DIAG were false positives — Lua treats `false ~= nil` as true, so the tostring probes lied; the real values were `false`.)

Fix — route audio through the **host window's own vanilla `_play_sound`**, the exact path vanilla uses for every click/hover in this window:

- **Click sound** — on button release, call `HeroWindowWeaveProperties:_play_sound("Play_hud_select")`, which forwards to `self._parent:play_sound(event)` → `HeroViewStateWeaveForge.play_sound` (`hero_view_state_weave_forge.lua:859`). No `music_world` dependency, so it actually fires.
- **Hover sound** — `Play_hud_hover` on the hover-enter edge (`hotspot.on_hover_enter`), matching vanilla forge hover feedback.
- **Press feedback (visual)** — the button background now flashes a bright `_COL_PRESSED` while held (`hotspot.is_held`), so a click is visibly acknowledged, not just audibly. Hover still brightens to `_COL_HOVER`; idle is `_COL_BASE`.

Both sound events (`Play_hud_select`, `Play_hud_hover`) are grep-confirmed real Wwise events in the vanilla source. All calls stay pcall-guarded (a nil parent is silent, never a crash).

### Files
- `_accessory_craft_panel.lua` — replaced `_play_click()` (music_world) with `_play_sound(pw, event)` (host-window path); added `_COL_BASE/_COL_HOVER/_COL_PRESSED` and pressed/hover/idle rect states; hover-enter + release edges consumed in the post-pass loop. Removed the two 0.8.38 DIAG lines.
- `crafting_in_modded_dev.lua` — `MOD_VERSION` `0.8.38-dev` → `0.8.39-dev`.

## 0.8.38-dev (2026-06-30) — DIAGNOSTIC: accessory buttons frame/sound not manifesting

The 0.8.37 accessory-button frame border + click sound didn't appear in-game even though the log confirms v0.8.37-dev is the only active cim and the panel builds 3 buttons. Added two INFO diagnostics (visible in the user's log — INFO is on) to pinpoint the failure instead of guessing:

- `[acc-panel] DIAG passes=[…] content.frame=… style.frame=…` on build — shows whether the `texture_frame` border pass survived `UIWidget.init` and the frame content/style are set.
- `[acc-panel] DIAG click has_music=… world=… ww=… WwiseWorld=…` on button press — shows exactly where the `Play_hud_select` sound path resolves or drops.

No behavior change beyond logging. Next build applies the fix these lines point to.

### Files
- `_accessory_craft_panel.lua` — two DIAG `mod:info` lines; `MOD_VERSION` `0.8.37-dev` → `0.8.38-dev`.

## 0.8.37-dev (2026-06-30) — Accessory craft buttons: GUT-style frame border + click sound

Polished the three Athanor accessory craft buttons (**CRAFT NECKLACE / CHARM / TRINKET**):

- **Border** now uses the ornate **`menu_frame_12`** 9-slice frame — the same frame GUT's Mod Tweaker popups use — instead of the old flat 2px line. Safe on this renderer because the panel draws on `HeroWindowWeaveProperties.self._ui_top_renderer`, which is `ingame_ui_context.ui_top_renderer` (the exact renderer GUT draws `menu_frame_12` on), so the material is guaranteed present (no raw-material CTD risk).
- **Click sound** — pressing a button now fires GUT's option-commit sound `Play_hud_select` (resolved off the `music_world` wwise_world, fully pcall-guarded so a missing world is silent). Matches the audio feedback GUT gives when you click an option.

### Files
- `_accessory_craft_panel.lua` — `texture_frame` (`menu_frame_12`) border replacing the plain border pass; `_play_click()` helper fired on button release; `MOD_VERSION` `0.8.36-dev` → `0.8.37-dev`.

## 0.8.36-dev (2026-06-30) — Fix: crafted WEAPONS ignored the Base Power Level setting (always 300)

**BUGFIX.** Crafting a weapon (e.g. a mace) always produced power **300** regardless of the *Base Power Level* slider — a user set it to 404 and still got 300. Root cause: both weapon craft paths hardcoded `power_level = 300` in their `weapon_data`, while only the amulet path read `_cim_base_power()`:

- `HeroWindowWeaveForgeWeapons._equip_item` hook (weapon-select "CRAFT" → blank weapon)
- `HeroWindowWeaveProperties._upgrade_magic_level` hook (editor "CRAFT" → weapon with edits)

Both now read `(mod._cim_base_power and mod._cim_base_power()) or 300`, matching the amulet path, so crafted weapons take the configured base power. Also made the `/cim_forge` chat-command craft default to the setting (still overridable via its power command) so every craft surface is consistent.

Note: the *item's* power now reflects the slider (0–950); in-combat power is still clamped by the game's per-difficulty power cap (`ActionUtils.scale_power_levels`), which is vanilla behavior and outside cim.

### Files
- `crafting_in_modded_dev.lua` — 3 craft `weapon_data`/`_forge_pending` power_level constants → read `_cim_base_power()`; `MOD_VERSION` `0.8.35-dev` → `0.8.36-dev`.

## 0.8.35-dev (2026-06-30) — Remove the loadout-persistence toggles (moving to Tweaker: GUI)

Removed the two **Modded Inventory** options **"Persist modded-crafted weapons across loadouts/sessions"** (`persist_modded_loadouts`) and **"Restore modded loadout each session"** (`restore_modded_loadout`). The feature never worked reliably; a proper loadout system is being built in Tweaker: GUI (gut), which will own it.

- Both menu widgets + their localization entries deleted.
- The master gate now **force-disables** the whole path at load (`mod:set("persist_modded_loadouts", false, false)`), so any user who had previously enabled the toggle — who'd otherwise be stuck with the machinery running and no toggle to switch it off — is reset. cim no longer captures/syncs/restores/migrates loadouts; vanilla player AND bot loadouts are byte-identical to not having cim installed.
- The `restore_modded_loadout` sub-gate read was removed from `_restore_modded_loadout`.
- The capture/sync/restore/migration machinery is left **dormant** (gated off by the master helper) pending full excision once gut's system lands. The regression sandbox still exercises the dormant round-trip logic (it sets the setting on transiently), so the test suite is unchanged.

### Files
- `crafting_in_modded_dev_data.lua` — removed both checkboxes from `inventory_group`.
- `crafting_in_modded_dev_localization.lua` — removed the 5 associated loc entries.
- `crafting_in_modded_dev.lua` — load-time force-OFF of `persist_modded_loadouts`; removed the `restore_modded_loadout` sub-gate; `MOD_VERSION` `0.8.34-dev` → `0.8.35-dev`.

## 0.8.34-dev (2026-06-29) — Option: ignore items from inactive mods (stop the deferred-craft chat spam)

New checkbox **"Ignore items from inactive mods (no chat spam)"** (Modded Inventory group, `ignore_unloadable_items`, default OFF).

When you have saved crafts that reference items from a mod that isn't currently active (e.g. toggling mods on/off while testing), cim's boot/state-transition re-injection can't find those ItemMasterList entries and defers them, echoing `[cim] N saved crafts deferred …` to chat on every `_create_interfaces` re-fire / state transition. With the new option ON, those two announcements (`_athanor_inject_all` deferred count + `_athanor_retry_pending` recovery) route to the log (`mod:info`) instead of chat. The deferred-injection **retry still runs**, so a craft auto-recovers if you re-enable its mod — only the chat noise is suppressed. Default OFF preserves the existing feedback for normal users.

### Files
- `crafting_in_modded_dev.lua` — gate the two `mod:echo` deferred/recovery messages on `mod:get("ignore_unloadable_items")`; `MOD_VERSION` `0.8.33-dev` → `0.8.34-dev`.
- `crafting_in_modded_dev_data.lua` — new `ignore_unloadable_items` checkbox in `inventory_group`.
- `crafting_in_modded_dev_localization.lua` — `ignore_unloadable_items` title + description.

## 0.8.33-dev (2026-06-29) — Revert the bubble-cap over-correction from 0.8.32 (#86)

**REGRESSION FIX.** v0.8.32-dev fixed the real #86 ceiling (you can now add up to 10 distinct properties) but ALSO changed `_bubble_cap`'s default from 5 → 1. That second change was wrong: it forced every generic property down to a **single bubble**, destroying per-property scaling for all of them at once. In vanilla weaves each property has a 5-bubble row you fill to raise its value (1 bubble = 20%, 5 = full); the default-1 change removed that. Reverted the default to **5**.

What stays from 0.8.32 (the actual #86 fix): `MAX_DISTINCT_PROPERTIES` 10, the load-time trimmer / `KEEP_LIMIT` 10. stamina (2) and movespeed (1) keep their explicit caps; `movespeed_2pct_mode` still uncaps movespeed to 5.

Net behavior: each property scales 1–5 bubbles again (vanilla feel), AND the artificial 2-distinct ceiling is gone. The 10 grid slots per layer are a **shared budget** — 10 distinct properties only all fit if you don't max-fill their bubbles; fewer properties can each be scaled higher.

### Test
Renamed `default_property_cap_is_one_slot` → `default_property_cap_is_five_bubbles`; it now pins the default cap at 5 and asserts the value scales (1 bubble = 0.2, 5 = 1.0), so a relapse to single-bubble fails the test.

**NOT claimed fixed.** Confirm in-game: load echo reads `v0.8.33-dev`, then in the Athanor a generic property (e.g. Crit Chance) should let you fill multiple bubbles again, stamina = 2, movespeed = 1, and you can still place more than 2 distinct properties. (#86)

### Files
- `crafting_in_modded_dev.lua` — `_bubble_cap` default 1→5; `get_property_mastery_costs` comment; regression test renamed + asserts scaling; `MOD_VERSION` `0.8.32-dev` → `0.8.33-dev`.

## 0.8.32-dev (2026-06-29) — Fix #86 (take 6 — the REAL cause: the 2-property ceiling, found from the user's log)

**Root cause, finally traced from empirical evidence (not assumed).** The user's 2026-06-29 console log proved the prior five #86 fixes were aimed at the wrong target. The autodump showed `weave_movespeed` already persisting **1 slot, cap 1** — movespeed was never the problem. The slots were being eaten by `weave_fatigue_regen` ("Stamina Regeneration"), which had **cap 5**, and — more importantly — by a hard **2-distinct-property ceiling** that blocked adding anything past the second property (log: `[cim] Max 2 distinct properties per accessory. Remove one to add fatigue_regen.` × 15). The grid has 10 slots per layer; cim was artificially capping use of it at 2 properties.

Three independent enforcers were holding the ceiling at 2 (all three had to move):

1. **Add-time gate** — `MAX_DISTINCT_PROPERTIES` 2 → **10**. The set_loadout_property hook rejected the 3rd distinct key on a layer.
2. **Load-time trimmer** — was destructively trimming every saved item down to its first 2 properties on each load (the `[trim] … kept=[…,…] dropped=[…]` lines in the log), so even items that had more got clobbered on restart. Raised to the 10-slot grid ceiling.
3. **Per-property slot reservation** — `_bubble_cap` default 5 → **1**. Each property now occupies ONE grid slot at full value (`_value_for_bubbles(key,1)=1.0`), matching how a regular campaign weapon's properties read. stamina (2) and movespeed (1) keep their explicit caps; `movespeed_2pct_mode` still uncaps movespeed to 5 by design.

**Why this is now safe at >2 (the reason it was capped at 2 before):** vanilla's `HeroWindowItemCustomization._update_property_option` indexes `button_hotspot_N` per property and the widget only ships hotspots 1–2, so a 3rd property used to crash that preview tab. That crash is **already independently guarded** by cim's replacement `_update_property_option` hook (standard_forge.lua:192-220), which skips writes for missing hotspot widgets. So the >2 ceiling is no longer load-bearing — extra properties simply aren't surfaced in that one preview tab but still apply and still render in the weave grid. (This is the same nil-index family as issue #150 `hero_window_item_customization.lua:2392`; the property path is guarded, the rarity/skin-hover parts of #150 remain separate.)

### Test
New `/cim_regression_test` check `default_property_cap_is_one_slot` pins the default cap at 1 across several real property keys (and asserts 1 slot still grants full value), so a revert to 5 fails the test instead of shipping.

**NOT claimed fixed.** Confirm in-game: load echo reads `v0.8.32-dev`, then add movespeed + stamina + Stamina Regeneration + others — each should take 1 slot (stamina 2), and you should be able to place up to 10 distinct properties on a layer without the "Max 2 distinct" rejection. (#86)

### Files
- `crafting_in_modded_dev.lua` — `MAX_DISTINCT_PROPERTIES` 2→10; load-time trimmer 2→10 (`KEEP_LIMIT`); `_bubble_cap` default 5→1; new regression check; `MOD_VERSION` `0.8.31-dev` → `0.8.32-dev`.

## 0.8.31-dev — 2026-06-28
- Removed per-mod debug toggle; diagnostics now route through VMF logging (mod:debug / mod:warning), gated by VMF output_mode_debug / output_mode_warning. (#169)

## 0.8.30-dev (2026-06-28) — Fix #86 (take 5 — READ-path guard, NOT another write-path tweak)

**BUGFIX — different approach.** Stamina and movespeed still reserve 5 grid slots each in-game (user report 2026-06-28), despite the take-4 write-path cap. The take-4 cap (`_store_property_slot`) is *provably correct in source* — the `/cim_regression_test` `picker_caps_persisted_slot_array` check passes. So the symptom persisting in-game proves the array reaching the grid is over-filled by a path the WRITE cap doesn't cover: a deployed build predating take-4, a hook instance the write path bypasses, or a stale seed. Takes 1-4 all patched the write path; this patches the **read** path, which is downstream of all of those.

### Fix — cap at the grid's read chokepoint

Grid occupancy is built by vanilla `HeroWindowWeaveProperties._sync_backend_loadout` (`hero_window_weave_properties.lua:1478` reads `get_loadout_properties(...)`; `:1551-1556` maps **one grid slot per slot-index array entry**). cim's `get_loadout_properties` hook returned `data.properties` raw. Now it runs new helper `_cap_grid_property_arrays(data.properties, item_backend_id)` first, trimming each property's array to its bubble cap right before vanilla reads it. Occupancy can no longer exceed the cap **regardless of how the array got filled** — the guarantee the write-path cap couldn't make.

- **Layer-aware.** Single-weapon editor (`item_backend_id` present) = one layer → cap the whole array (movespeed→1, stamina→2). Amulet editor (`item_backend_id == nil`) = cap PER accessory layer (`_AMULET_LAYER_SIZE`), so a property the user put on two accessories isn't wrongly collapsed to one.
- **Self-reporting via engine `printf`.** When it actually has to trim (the leak is present) it logs the raw over-fill count to the engine console *before* trimming. `printf` is visible even with VMF mod-logging OFF — the user's normal config, and the reason every prior `mod:info`/autodump "verification" saw nothing. If the symptom somehow persists, the console line proves which path leaked instead of us guessing.

### Test

New `/cim_regression_test` check `read_chokepoint_caps_grid_occupancy` drives `_cap_grid_property_arrays` with a deliberately over-filled array (movespeed=5, stamina=5) and asserts it trims to 1/2 for a weapon, caps per-layer for the amulet (movespeed across 2 accessories stays 2, not 1), and leaves an already-capped array untouched (no false trim).

**NOT claimed fixed.** This is a downstream guard + a visible diagnostic, not a verified fix. Confirm in-game that the load echo reads `v0.8.30-dev`, then add stamina/movespeed and check the grid slots. If still wrong, the `[cim #86]` console line carries the proof. (#86)

### Files
- `crafting_in_modded_dev.lua` — new `_cap_grid_property_arrays` helper (+ forward decl); `get_loadout_properties` hook calls it; new regression check; `MOD_VERSION` `0.8.29-dev` → `0.8.30-dev`.

## 0.8.29-dev (2026-06-25) — Ship: friends-only dev release (verified)

Friends-only dev ship of the v0.8.28-dev build (#86 take-4 movespeed forge-slot fix). Verification passed; promoting to the friends-only `cim_dev` Workshop item. No behavioral change vs v0.8.28-dev — this is a version-bump ship build (`MOD_VERSION` `0.8.28-dev` → `0.8.29-dev`) so the in-game load echo confirms the deployed bundle.

### Files
- `crafting_in_modded_dev.lua` — `MOD_VERSION` `0.8.28-dev` → `0.8.29-dev`. No other code change.

## 0.8.28-dev (2026-06-24) — Fix #86 (take 4, REAL root cause): movespeed property over-occupied the forge slot grid and blocked other properties

**BUGFIX.** In the Athanor weave forge, adding the movespeed property DISPLAYED as 1 slot (the 0.8.26 bubble-cap display fix works) but BLOCKED the remaining slots from being filled with other properties. Stamina (2 slots) did NOT block — so this was movespeed-specific. The 0.8.26 fix corrected the DISPLAY math (`_bubble_cap` / `_value_for_bubbles`) but never checked the PERSISTED slot-index array, which is what actually drives grid occupancy.

### Root cause — persisted array length, not the displayed bubble count, drives grid occupancy (traced through source)

The forge grid decides which slots are occupied in vanilla `HeroWindowWeaveProperties._sync_backend_loadout` (`hero_window_weave_properties.lua:1553-1556`):

```lua
for key, slot_indices in pairs(properties) do
    for _, slot_index in ipairs(slot_indices) do
        properties_index_map[slot_index] = key   -- one grid slot per ARRAY ENTRY
    end
end
```

So a property occupies **exactly `#props[property_key]` grid slots** — one per entry in its slot-index array. `get_loadout_properties` returns cim's live `data.properties` table directly (`crafting_in_modded_dev.lua:4082`), so whatever cim's picker hook stores is exactly what the grid counts. The visible bubble count (`_bubbles_for_value` → 1 for movespeed) is irrelevant to occupancy; only the array length matters. The prior #86 fixes only validated the display path — the exact "trusted a display-only check" trap.

When `movespeed_2pct_mode` is ON, `_bubble_cap("weave_movespeed")` intentionally returns 5 (each bubble = +2%, max +10% — the documented trade). The picker's array-length cap then allows up to 5 distinct slot indices into `props[weave_movespeed]` → 5 grid slots marked occupied → the remaining slots in movespeed's `utility_accessory` category are blocked. Stamina (always cap 2, in a different category) never over-occupies. **That toggle is the movespeed-specific divergence.** Its default is `false`; a tester who enabled it reproduces the report exactly.

The fix also re-applies two guards vanilla's `set_loadout_property` (`backend_interface_weaves_playfab.lua:1059-1071`) has that cim's hook had DROPPED, hardening the default path regardless of the toggle:
- **cross-property collision** — never store a `slot_index` already held by ANY property (vanilla's `table.contains(slots, slot_index)` early-return). Without it a re-seed or stray re-click could double-list a grid slot.
- **per-property use cap** — stop at `_bubble_cap` entries.

### Fix

- New pure helper `_store_property_slot(props, property_key, slot_index)` applies both guards (collision/dedupe + length cap) and is the single store path. The live `set_loadout_property` hook calls it; the array's resulting length is exactly the property's bubble cap (movespeed 1 / stamina 2 by default), so movespeed occupies one slot and leaves the rest fillable — mirroring how stamina already worked.
- The hook logs the persisted array length after every write via the new debug probe `_cim_autodump_property_array` (gated on `enable_debug_logging`), with a loud `OVER-CAP!` warning if the array ever exceeds the cap — so the divergence is visible in-log next time without a code change.
- New `/cim_regression_test` check `picker_caps_persisted_slot_array` drives the REAL store helper and asserts the PERSISTED array (not the display value): movespeed (2pct OFF) = 1 after 5 clicks, stamina = 2 after 5 clicks, cross-property collision rejected, re-click deduped, and movespeed (2pct ON) = 5 (the trade pinned).

### Movespeed 2pct mode

Default is `false` (verified in `crafting_in_modded_dev_data.lua`). If a tester sees movespeed blocking, the first thing to check is whether they toggled "movespeed 2pct mode" ON — under that config movespeed correctly consumes up to 5 slots and that is intended, not a bug. The non-2pct path is now provably correct (array length pinned to 1).

**Build/structural verification only — user verifies the in-game forge behavior.**

## 0.8.27-dev (2026-06-24) — Regression test for #96 (allow_in_mission gated on gut presence)

**TEST-ONLY.** No runtime behavior change — the #86 stamina bubble-cap fix from 0.8.26-dev is untouched and still in force.

Adds a `/cim_regression_test` source-introspection guard `issue96_allow_in_mission_gated_on_gut` so the Issue #96 fix can't silently regress. The check reads `crafting_in_modded_dev_data.lua` (deriving its path from a main-file function via `debug.getinfo`) and FAILs if either:

- the `_gut_present()` helper is absent — the load-order-safe gut-presence detector (fast-paths `get_mod("gut")`/`get_mod("gut_dev")`, falls back to scanning the ModManager manifest for the `"Tweaker: GUI"` Workshop title), or
- the `allow_in_mission` widget is no longer conditionally pruned from the forge group's `sub_widgets` based on `_gut_present()`.

So if a future edit drops the helper or the gating, the "Allow standard crafting bench in mission" option re-appearing when gut is absent (the #96 symptom) is caught at test time. Self-matching needles are split across two string literals. Degrades to a no-op on the bundle/deploy path where source introspection isn't available.

## 0.8.26-dev (2026-06-24) — Fix #86 (take 3, REAL root cause): Athanor weave bubble-cap keyed by the wrong property-key form

**BUGFIX.** Stamina took 5 forge slots instead of 2, and movespeed showed 79% instead of +5%. The previous "#86 fix" (0.8.9 / earlier dev) shipped UNVERIFIED and was still wrong — its regression test was checking a key form the game never sends, so it passed while the game path silently broke.

### Root cause — key-form mismatch (traced through source, not assumed)

`_bubble_cap` / `_value_for_bubbles` / `_bubbles_for_value` resolved a property's slot cap from `_PROPERTY_BUBBLE_CAP_STATIC`, keyed `properties_stamina` / `properties_movespeed`. The key passed in is run through `_strip_weave`, which strips ONLY the `^weave_` prefix. That table keying is correct **only if every caller passes the `weave_properties_<X>` form** — but the game does not.

Trace of the actual game key form:
- `hero_window_weave_properties.lua:534` iterates `WeaveProperties.categories[category]`, whose entries are `weave_stamina` / `weave_movespeed` (`weave_properties.lua:543+`) — the `weave_`-prefixed but NOT `properties_`-prefixed key form.
- `:550` stores `entry.key` = that form; `:2663` calls `set_loadout_property(career, key, slot_index, item_backend_id)` with it.
- `backend_interface_weaves_playfab.lua:1031` receives it as `property_name`.

So the game's real key is `weave_stamina` / `weave_movespeed`. `_strip_weave("weave_stamina")` → bare `stamina`, but the cap table was keyed `properties_stamina` → **MISS → fell back to the default cap 5**. That default-5 made stamina fill 5 slot_indices and inflated movespeed's mastery-cost array to 5 entries.

**Why 79% for movespeed (value→% chain):** vanilla `UIUtils.get_weave_property_value_text` (`ui_utils.lua:115-131`) computes `display_value = max_value / num_costs * amount`, and movespeed is `baked_percent` → `text = |100 * (display_value - 1)|%`. Movespeed's `max_value = variable_multiplier_max = 1.05` (`weave_properties.lua:70`). With the bug, `num_costs = cap = 5` and one bubble filled (`amount = 1`): `display_value = 1.05/5 * 1 = 0.21` → `|100 * (0.21 - 1)| = 79%`. With the cap correctly = 1: `num_costs = 1`, `amount = 1` → `display_value = 1.05` → `|100 * (1.05 - 1)| = 5%`. So the cap fix alone corrects the displayed percentage; there is no separate display formula to patch.

**Why the prior test fooled the last fix:** it asserted `_bubble_cap("weave_properties_stamina") == 2`. `_strip_weave` leaves `properties_stamina`, which matched the (mis-keyed) table → the test passed. But the game never sends `weave_properties_stamina`; it sends `weave_stamina` → bare `stamina`, which missed. The test validated a key form that doesn't occur at runtime.

### Robust fix — normalize ANY key form to the bare name; key the table by bare names

- `_PROPERTY_BUBBLE_CAP_STATIC` is now keyed `{ stamina = 2, movespeed = 1 }`.
- New `_bare_property(weave_key)` strips `^weave_` THEN `^properties_`, collapsing all of `weave_properties_X` / `weave_X` / `properties_X` / bare `X` to `X`. `_bubble_cap`, `_value_for_bubbles` (its movespeed-2pct guard), and `_bubbles_for_value` (via `_bubble_cap`) all resolve through the bare form, so any caller key form maps correctly. The fix is robust to the exact form the game sends regardless of future call sites.
- Stamina cap=2 tiering and movespeed cap=1 math are unchanged.

### Other confirmations

- `movespeed_2pct_mode` already defaults `false` in `crafting_in_modded_dev_data.lua` (the opt-in 5-bubble/+2%-per-bubble mode). No change needed — base movespeed is 1 slot / +5%.
- Regression test rewritten to assert `_bubble_cap` returns 2 for stamina and 1 for movespeed across ALL key forms — `stamina`, `properties_stamina`, `weave_properties_stamina`, AND the game's real `weave_stamina` (same four for movespeed) — so a future miskeying fails the test on the path the game actually exercises.

**Must verify in-game on cim_dev 0.8.26-dev:** stamina uses exactly 2 forge slots (requires 2 empty), and movespeed uses exactly 1 slot and shows +5%.

## 0.8.25-dev (2026-06-24) — Fix #96: hide the "Allow standard crafting bench in mission" option when GUI Tweaker (gut) isn't installed

**UX.** The `allow_in_mission` option only does something useful when GUI Tweaker (gut) is present (gut supplies the in-mission menu access cim's standard bench rides on), so the checkbox is now HIDDEN in cim's VMF settings when gut isn't installed.

### VMF capability check (read upstream FIRST, per the no-guessing rule)

Confirmed against upstream VMF source (`vmf/scripts/mods/vmf/modules/core/options.lua`, the widget schema/validator): **VMF has NO native conditional-visibility or mod-dependency widget feature.** The validated checkbox fields are `setting_id` / `type` / `title` / `tooltip` / `default_value` / `localize` / `is_collapsed` — no `depends_on` / `requires` / `hide_when` / `enabled_if`. The only conditional widget feature VMF has is dropdown `show_widgets`, which keys off a selected dropdown VALUE, not mod presence. So the gate must be implemented by conditionally BUILDING the widget tree.

### Implementation — conditional widget build with a load-order-safe presence check

- `crafting_in_modded_dev_data.lua` now builds the options table into a local and, when gut is absent, prunes the `allow_in_mission` checkbox out of the `forge_group` sub_widgets before returning (located by `setting_id`, not a fixed index). VMF unfolds the data table immediately at registration, so a pruned widget is simply never built.
- **Load-order safety** (the footgun): `get_mod("gut")` is just `_mods["gut"]` and returns nil if gut hasn't run its `new_mod` yet — and VMF processes cim's data table at cim's registration, which may precede gut's. A bare `get_mod` check would wrongly hide the widget when cim loads before gut. The new `_gut_present()` helper therefore checks BOTH: the fast `get_mod("gut")` / `get_mod("gut_dev")` path (gut already loaded), OR — load-order-independent — an enabled entry in the engine ModManager's manifest (`Managers.mod._mods`, built once from the user's full enabled-mod list at scan time before any mod's Lua runs; `mod_manager.lua:278-343`) whose Workshop title is gut's ("Tweaker: GUI", covering gut and gut_dev). So presence is detected regardless of which mod loads first.
- When gut IS present the widget is unchanged and the in-mission standard bench works exactly as before. When gut is absent the option is hidden; the runtime `open_standard_crafting` keep-gate is unaffected (it independently bails outside the keep).

## 0.8.24-dev (2026-06-24) — Fix #88: in-mission ESC-menu backout leaked the loadout inventory (scope the inventory-access patch)

**BUGFIX.** Backing out of the in-game (ESC) menu during a mission pulled up the loadout INVENTORY; it should only be available in the Keep. The standard crafting bench could still open in-mission via its own hotkey — only the ESC-backout-to-inventory leak is fixed.

### Root cause

`mod.open_standard_crafting` flipped `InventorySettings.inventory_loadout_access_supported_game_modes.adventure / .survival` to `true` **permanently** and never restored them (`crafting_in_modded_dev.lua`, ~line 1848-1860 pre-fix). The ONLY vanilla read of that table is `HeroView.on_enter` → `_fetch_initial_loadout_index` (`hero_view.lua:309/323`), which bails when the current game mode isn't supported. A persistent flip means EVERY subsequent HeroView open in the mission — including the ESC-menu / ingame-menu backout, which cim never initiated — read the mode as supported and initialized the loadout inventory mid-mission.

### Fix — scope the flip to cim's own view open (no persistent global mutation)

- `open_standard_crafting` no longer mutates `InventorySettings`. It sets a one-shot upvalue flag `_cim_open_standard_inv_pending = true` immediately before its `transition_with_fade("hero_view_force", { menu_state_name = "forge" })`.
- New `mod:hook("HeroView", "on_enter", ...)` (cim had no prior `on_enter` hook — grep-verified, no duplicate): when the one-shot flag is set, it consumes the flag, SAVES the current `adventure / survival / deus` values, applies the mission-enabled flip, runs vanilla `on_enter` (the single read site) under `pcall`, then RESTORES the saved values — even if vanilla raises. Deus stays nil (CW is blocked in `open_standard_crafting`).
- Net effect: the inventory-access mode is enabled for EXACTLY the one HeroView that cim opens for the standard bench; every other HeroView open (ESC backout, hero select, map, etc.) reads the untouched vanilla table and bails as before. The standard bench still opens in-mission; the inventory no longer leaks onto ESC-backout. Keep / CW-hub opens are unaffected (mode already supported there; the flag is only set by the in-mission entry).
- Verified there is exactly one vanilla read site (`hero_view.lua:323`), called once per `HeroView.on_enter`, feeding `self._initial_loadout_index` — so a save/restore around vanilla `on_enter` fully covers it with no functional regression to the bench.

### Regression test

`issue88_inventory_access_flip_is_scoped` (`/cim_regression_test`) — source-pattern guard: fails if the one-shot flag, the scoped `HeroView.on_enter` hook, or the save/restore is removed (i.e. if a persistent flip is reintroduced). No-op when source introspection is unavailable.

## 0.8.23-dev (2026-06-24) — Fix #86 (stamina eats 5 slots) + keep-gate the in-mission Athanor (script_world blend crash)

### Fix #86 — the Stamina property consumed 5 inventory slots instead of 2

**BUGFIX.** Adding the Stamina property in the Athanor consumed 5 of the 10 property slots instead of exactly 2, blocking a second property from being added even though `MAX_DISTINCT_PROPERTIES` (2) should have allowed it. (Re-report of the "WHEN APPLIED IT TAKES 5" symptom the v0.7.55-dev array cap was meant to fix.)

**Root cause — the bubble-cap table was keyed wrong.** The weave UI passes the category key `weave_properties_stamina` (`weave_properties.lua:15`) to `set_loadout_property` / `get_property_mastery_costs`. `_strip_weave` strips only the `weave_` prefix, yielding `properties_stamina` (which is also the vanilla `weapon_properties.lua` key). But `_PROPERTY_BUBBLE_CAP_STATIC` was keyed by the BARE `stamina` / `movespeed`, so `_bubble_cap("weave_properties_stamina")` missed the table and fell back to the default cap of **5**. That fed three places:
- `get_property_mastery_costs` returns `cap` zero-cost entries, which the forge renders as `total_uses` → **stamina drew/used 5 slots**.
- the `set_loadout_property` array cap (`#props[key]` capped at `_bubble_cap`) was a silent no-op at 5 → the persisted array held 5 slot_indices.
- `_value_for_bubbles` / `_bubbles_for_value` treated stamina as a 5-bubble linear property instead of the 2-tier snap.

**Fix.** Re-key `_PROPERTY_BUBBLE_CAP_STATIC` to the post-`_strip_weave` keys `properties_stamina = 2` / `properties_movespeed = 1`, and update the two inline `"movespeed"` comparisons in `_bubble_cap` / `_value_for_bubbles` to `"properties_movespeed"`. One change fixes the slot count, the array cap, and the value/seed math. Stamina now renders and consumes exactly 2 slots; movespeed exactly 1 (5 with the 2pct toggle).

**Regression test corrected.** `stamina_movespeed_clamp_at_overcap` previously drove `_value_for_bubbles("stamina", ...)` with the BARE key — which matched the old mis-keyed table, so it passed while the game (using `weave_properties_stamina`) silently got cap=5. The test now uses the REAL weave keys and asserts `_bubble_cap("weave_properties_stamina") == 2` and `_bubble_cap("weave_properties_movespeed") == 1`, so it actually pins #86 on the path the game exercises.

### In-mission Athanor keep-gated (script_world.lua:176 `blend` ShadingEnvironment crash — relates to #81)

**CRASH GUARD.** Opening the Athanor (weave forge) in a mission on cim_dev hit a render-level fatal in the mid-mission shading-environment substitution path (`foundation/scripts/util/script_world.lua:176` → `blend`), surviving the Fix B/B2..B6 material/HDR hardening. `mod.open_forge` now hard-requires the Keep / CW hub regardless of the `allow_in_mission` toggle — the in-mission Athanor cannot open on dev either, matching the public 0.8.8 build. The material-clean **standard crafting bench** (`open_standard_crafting`) still opens in Adventure missions and still honors `allow_in_mission`. The Fix B/B2..B6 hooks are left in place (inert) so re-enabling the in-mission Athanor later is a one-line gate change, not a re-port. Loc/UI updated: `forge_hotkey` → "Keep only"; `allow_in_mission` relabeled to govern the standard bench only.

## 0.8.22-dev (2026-06-23) — Fix: owned Versus (vs_*) weapon twins with illusions leaking into the Adventure inventory grid

**BUGFIX.** Raw owned vanilla Versus weapons (the `vs_*` keys — gutter runner claws, ratling gun, etc., player-facing as Gallant's Blade / Soldier's Coach Gun and similar) were appearing in the normal Adventure inventory grid — most visibly once an illusion was applied to the crafted twin. The leak was a side effect of the deliberate craft-visibility mechanism, not the illusion write.

### Root cause

`_ensure_item_adventure_visible` (`crafting_in_modded_dev.lua`) clears `ItemMasterList[vs_key].mechanisms = nil` so a **crafted** vs_* weapon passes the vanilla `available_in_current_mechanism` filter (`backend_interface_common.lua:537-565`) and shows up in Adventure. That is intended and stays.

The problem: `item.data` is a **shared reference** to that same IML entry — `PlayFabMirrorBase._update_data` sets `item.data = ItemMasterList[item_key]` (`playfab_mirror_base.lua:1786`), not a copy. So the moment `mechanisms` is cleared, the player's **raw owned vs_* twin** (a distinct backend item sharing the same key) also reads `mechanisms = nil`, passes the same filter, and leaks into the inventory grid. There is no per-item data layer to diverge — one table backs both items. (The clear also makes `_cim_is_versus(item.data)` return false afterward, so the existing craft-list de-shadow gate is blind to the leaked twin.)

### Fix — re-hide the owned twin at the DISPLAY layer (inventory only; craft list untouched)

Extended the **existing** `BackendInterfaceItemPlayfab.get_filtered_items` hook (no new hook — VMF duplicate-hook rule respected) to drop owned vs_* twins from the adventure-inventory result while keeping cim-crafted vs_* visible:

- Runs **always** for the adventure inventory grid (gated on the `available_in_current_mechanism` filter infix), independent of the show-only-modded setting, since the leak is independent of it.
- New `_cim_is_leaked_versus_twin(item)` helper: true only when the item's `ItemId`/key has the `vs_` prefix **and** its backend_id is **not** a cim-modded bid. Keyed on the `vs_` prefix because the `mechanisms` field is already nil post-clear; keyed on `_cim_is_modded_backend_id` so a **deliberately-crafted unique vs_*** is NEVER hidden (memory `reference_vt2_versus_items_hidden_in_adventure`).
- The craft list and `_cim_versus_shadowed` de-shadow gate are not touched — vs_* stay fully craftable.

### Regression test

Added `_rt_register("versus_twin_rehidden_from_inventory", ...)`: asserts the helper hides an owned vs_* twin (vanilla bid), keeps a cim-crafted vs_* (modded bid) visible, and never touches a non-versus item. The prior `adventure_visible_stamp_and_mechanism_clear` test (asserting the intended global clear) is unchanged.

## 0.8.21-dev (2026-06-23) — Surface the STANDARD crafting bench in-mission (material-clean; not the Athanor)

**NEW FEATURE.** Adds an in-mission entry point to the VANILLA standard crafting bench — the Keep Smithy: salvage / craft random item / re-roll properties / re-roll traits / upgrade rarity / apply illusion / convert dust. This is the `forge` page's `HeroWindowCrafting`, **NOT** the Athanor (weave forge) that `forge_hotkey`/`open_forge` opens.

### Why this is a separate, CLEAN path from the Athanor

The whole B/B2..B6 crash saga (v0.7.13 → v0.8.20) exists because the **Athanor** (`weave_forge` state) is materially entangled with the keep: its windows hardcode `shading_environment = "environment/ui_weave_forge_preview"` (inn-only) and draw inn-only raw materials (`forge_overview_top_glow_effect_smoke_*`, `athanor_skilltree_*`, `weave_menu_*`) that a mission Gui can't resolve — hence `open_forge` is opt-in and labeled "[untested] may crash".

The **standard bench shares none of that** (verified against decompiled source):
- The crash material `forge_overview_top_glow_effect_smoke_1` lives ONLY in the weave-forge / weave-background definition files (grep-verified: 4 files, all `weave`/`start_game_window_weave`). It does NOT appear in `hero_window_crafting_definitions.lua`.
- `HeroWindowCrafting.draw` (`hero_window_crafting.lua:302-324`) draws plain atlas widgets (`crafting_bg*`, `crafting_fg*`, `item_grid_fg`, standard window-frame/button materials — `hero_window_crafting_definitions.lua:552-586`) on `ui_top_renderer` with **NO viewport, NO create_world, NO shading_environment, NO HDR Gui, NO preview render-target**.
- The craft sub-pages (`craft_page_*`) are icon-based — no spawned-unit preview world.

So the standard bench renders flat in a mission with **zero material/shading shims** — none of the Athanor's three crash sources apply.

The modded-crafting LOGIC already existed and is keep-tested: `standard_forge.lua`'s `HeroWindowCrafting`/`HeroWindowCraftingConsole`/`HeroWindowItemCustomization` on_enter hooks (`standard_forge.lua:222-239`) + the synth paths fire on the WINDOW lifecycle, not gated to the keep — so opening the `forge` page in a mission activates all of it automatically. The only missing piece was the in-mission entry point.

### What changed (no hooks added — pure entry-point function + UI wiring)

- **New `mod.open_standard_crafting`** (`crafting_in_modded_dev.lua`, Athanor section, right after `open_forge`). Modeled on gt's proven `gt_open_mission_inventory` (`general_tweaker_dev/_gt_mission_ui.lua:56-113`): `Managers.ui._ingame_ui:transition_with_fade("hero_view_force", { menu_state_name = "forge" })` (the `forge` page hosts `HeroWindowCrafting`, **not** `"weave_forge"`). Bypasses the hotkey gates the same way vanilla's ESC-menu "Open Inventory" does.
  - **Gates:** `Managers.ui` present + `pending_transition()` bail (same as `open_forge`); **blocks `mech == "deus"`** (Chaos Wastes is loadout-locked — whole run, hub + mission — mirroring `gt_open_mission_inventory`'s 2026-06-18 adventure-exclusive directive); honors the existing **`allow_in_mission`** opt-in so a single toggle governs both crafting surfaces (Keep / CW-hub always opens).
  - **Flips `InventorySettings.inventory_loadout_access_supported_game_modes`** (`adventure`/`survival` on, `deus` nil) for the call so the `forge` page's `inventory` window (layout slot 3) + loadout panel init in a mission. Idempotent; mirrors `_gt_mission_ui.lua:100-107`.
- **New keybind** `standard_crafting_hotkey` (`*_data.lua`, forge group, default UNBOUND) → `function_name = "open_standard_crafting"`.
- **New chat command** `/cim_craft_standard` (dispatches `mod.open_standard_crafting`).
- **Localization** for `standard_crafting_hotkey` (+ description) added.

### The one trap, avoided

Do NOT route the in-mission flow onto the gear-icon Customization view (`HeroWindowItemCustomization`), which pulls `levels/ui_store_preview/world` (the preview-world crash class cim already patched at v0.7.45 / gt #50). A direct transition to `menu_state_name="forge"` lands on the crafting/inventory/options windows — none of which route there.

### Hook safety

**No `mod:hook` / `mod:hook_safe` added or removed.** This is a plain entry-point function plus VMF UI wiring (keybind + command + loc). The existing `standard_forge.lua` window-lifecycle hooks (already singletons) do all the crafting work when the window opens. Respects the VMF duplicate-hook rule by adding zero hooks.

## 0.8.20-dev (2026-06-23) — Converge the in-mission forge raw-material prune (Fix B6): stop the `athanor_background_write_mask` crash + all future siblings

The B5 prune used a per-prefix allow-list (`athanor_skilltree_ring_` / `_background` / `_cluster_`) — one prefix added per crash. It missed `athanor_background_write_mask` (the 7th in-mission crash; log session f9ed28af, `ui_passes.lua:134`), the texture of the `background_write_mask` window widget in `_bottom_widgets`. cim had classified that widget "functional, keep" but never accounted for its raw, inn-only texture faulting on the base mission Gui.

**Root cause is structural, not per-material.** A Stingray Gui bakes its material list at `World.create_screen_gui()` time and never re-reads it — there is NO API to add a material to a live Gui (verified: `ui_renderer.lua:246-251`). So the "B1" idea of force-loading the keep weave/athanor package into the mission renderer is **impossible** — the already-created mission Gui can't resolve the raw materials no matter what's resident. The only viable fix is to keep the offending widgets out of the in-mission draw arrays.

**Fix B6 — converge the prune.** Per the verified note (only `athanor_skilltree_slot_*` lives in `gui_menus_atlas`), `_cim_is_raw_skilltree_texture` now drops ANY `athanor_` texture that isn't an atlas-backed slot — one structural guard that catches `athanor_background_write_mask`, the skill-tree ring/background/cluster set, and every future raw `athanor_` sibling at once, instead of chasing one prefix per crash. Atlas-backed slots and all non-`athanor_` functional widgets (`edge_fade_small`, viewport rects) are untouched; keep path unchanged; same existing hook sites (no new hooks). Losing the background write-mask in mission drops background masking only (a possible minor visual artifact), never a crash. Regression test extended to assert a slot survives + every raw `athanor_` is dropped.

## 0.8.19-dev (2026-06-22) — Fix in-mission skill-tree ring `Material not found` crash (non-HDR `_bottom_widgets` draw path — Fix B5)

**CRASH FIX (opt-in path).** After v0.8.18-dev (Fix B3/B4) closed the per-frame HDR `set_scalar` vectors, opening the forge **in a mission** with **`Allow in mission` ON** and **Loremaster's Armoury installed**, then opening a **weapon's skill tree**, hit a NEW crash:

```
[Script Error] scripts/ui/ui_passes.lua:805: Material 'athanor_skilltree_ring_3' not found in Gui
```

The keep forge and the default `allow_in_mission` OFF path were never affected. This is a NEW vector of the same keep-only-material class B/B2/B3/B4 chased, on a draw path none of the prior fixes touched — the **non-HDR `_bottom_widgets`** array, drawn on the **base mission `ui_renderer`** (not the HDR renderer B2 covered, not the per-frame bloom/upgrade `set_scalar` B3/B4 guarded).

### Root cause (`crafting_in_modded_dev.lua`, non-HDR `_bottom_widgets` draw-array vector)
- `HeroWindowWeaveProperties._draw` (`hero_window_weave_properties.lua:2807-2823`) iterates `self._bottom_widgets` on `self._parent:get_ui_renderer()` — the **base mission renderer**. That array mixes FUNCTIONAL widgets (`background_write_mask`, `viewport_background` rect, `viewport_background_fade` = atlas-backed `edge_fade_small`) with raw, inn-only DECORATIVE textures:
  - `athanor_skilltree_ring_1` / `_2` / `_3` — the `wheel_ring_*` widgets (`hero_window_weave_properties_definitions.lua:4485-4497`) — **the reported crash**
  - `athanor_skilltree_background` — the `background_wheel` widget
  - `athanor_skilltree_cluster_<i>` — the `cluster_background_<i>` widgets, **RE-APPENDED** per cluster by `on_enter` → `_create_slot_grid` → `_create_cluster_background` (`hero_window_weave_properties.lua:894-924`, line 913), so they arrive AFTER `create_ui_elements` (same re-append pattern that bit B2's HDR cluster glow).
- Verified non-atlas: only `athanor_skilltree_slot_*` live in `gui_menus_atlas.lua`; the ring / background / cluster textures are in **no** `atlas_settings` file — same raw-material signature as the `weave_menu_*` keep-only set. They resolve only on a Gui built with `is_in_inn=true`; on the base mission Gui `Gui.material(...)` doesn't find them → `ui_passes.lua:805` fatal.
- Why the prior sweep (v0.8.18) missed it: B2 empties the HDR draw arrays (`_top_hdr_widgets` / `_bottom_hdr_widgets`); B3/B4 guard per-frame HDR `set_scalar`. None of them iterate the **non-HDR** `_bottom_widgets`.

### Fix (filter the raw skill-tree decorations out of `_bottom_widgets` in mission)
- New helper `mod._cim_suppress_skilltree_rings_in_mission(window, in_keep)` — REBUILDS `_bottom_widgets` minus only the raw decorative textures (matched by `content.texture_id` prefix: `athanor_skilltree_ring_` / `athanor_skilltree_background` / `athanor_skilltree_cluster_`), keeping every functional widget. Can't empty the array wholesale — it carries the viewport background. The vanilla `_draw` loop then never resolves the missing materials.
- Wired at the **two append sites** (mirroring B2's two-call pattern), both gated on `not _is_in_keep()`:
  1. **`create_ui_elements`** — covers the static `wheel_ring_*` / `background_wheel`. Folded into cim's EXISTING `create_ui_elements` suppression loop (right after the B2 HDR-array call) — no new hook.
  2. **`on_enter` (post)** — covers the per-cluster `cluster_background_<i>` re-append. Folded into cim_debug.lua's EXISTING `HeroWindowWeaveProperties.on_enter` hook (right after the B2 HDR re-suppression call) — no new hook.
- **KEEP path fully unchanged:** in the keep both call sites are no-ops, so the forge keeps its full animated ring/cluster decoration (drawn on the real keep Gui that carries the inn-only materials). The per-frame `_update_background_animations` rotation still mutates `widgets_by_name[...]` harmlessly — those widgets just aren't in the drawn array in mission.
- **No hooks added or removed, no duplicates.** Both wiring points extend existing cim hooks (`create_ui_elements` loop + cim_debug `on_enter`); grep-verified the only cim hooks on those `(Class, method)` pairs are the ones extended. Respects the VMF duplicate-hook rule.
- **Regression:** `skilltree_ring_widgets_suppressed_in_mission` (`/cim_regression_test`) — drives the helper synthetically (mixed functional/raw `_bottom_widgets`): in mission only the raw `ring`/`background`/`cluster` textures are dropped and the functional widgets survive; in the keep the array is left fully intact; empty/missing array is a safe no-op.

### Audit of the remaining skill-tree widget set (no further `_bottom_widgets` raw-material vectors)
- The other `_bottom_widgets` entries are functional and resident in mission: `background_write_mask` (write-mask material, base-resident — the forge drew it without faulting before reaching the ring), `viewport_background` (a `rect`, no texture material), `viewport_background_fade` (`edge_fade_small`, atlas-backed in `gui_frames_atlas`).
- The per-node skill-tree slot icons (`athanor_skilltree_slot_*`) ARE atlas-backed (`gui_menus_atlas.lua`) and resolve fine in mission — they are NOT a vector and are deliberately left drawn.
- The sibling HDR cluster-effect (`athanor_skilltree_cluster_effect_<i>`) and the HDR `hdr_wheel_ring_*` / `hdr_background_wheel` go to `_bottom_hdr_widgets` and are already covered by B2.

## 0.8.18-dev (2026-06-22) — Fix in-mission forge `set_scalar` nil crashes (per-frame HDR bloom pulse + upgrade flourish — Fix B3/B4, completes the keep-only-HDR hardening)

**CRASH FIX (opt-in path).** After v0.8.17-dev (Fix B/B2) suppressed the keep-only HDR glow at the **draw site**, opening the forge **in a mission** with **`Allow in mission` ON** and **Loremaster's Armoury installed** hit a NEW crash on the first animated frame:

```
[Script Error] scripts/ui/views/hero_view/windows/hero_window_weave_forge_panel.lua:392: bad argument #1 to 'set_scalar' (userdata expected, got nil)
```

Crashify `12a6d563`. The keep forge and the default `allow_in_mission` OFF path were never affected. This is the third keep-only-HDR-object deref surfaced by Fix B (v0.8.16) skipping the HDR-world build in mission — fixed in ONE pass alongside an audit of all four weave-forge windows so the forge stops surfacing new crashes.

### Root cause (`crafting_in_modded_dev.lua`, per-frame bloom-pulse vector — distinct from the B/B2 draw-array vector)
- B2 empties the HDR **draw arrays** (`_top_hdr_widgets` / `_bottom_hdr_widgets`) so the vanilla `_draw` loops skip the missing materials. But two windows ALSO run a **per-frame bloom pulse** that reads `_widgets_by_name` **directly** (not the draw arrays) and writes a material scalar on the HDR Gui — so emptying the draw arrays does not cover it:
  - `HeroWindowWeaveForgePanel._set_background_bloom_intensity` (`hero_window_weave_forge_panel.lua:408-437`)
  - `HeroWindowWeaveProperties._set_background_bloom_intensity` (`hero_window_weave_properties.lua:1218-1248`)
- Both do, every frame: `local gui = parent:hdr_renderer().gui` → `Gui.material(gui, <wheel>.content.texture_id)` → `Material.set_scalar(m, "noise_intensity", value)`. After Fix B, `parent:hdr_renderer()` falls through to the **base mission renderer** (the `hdr_renderer` hook returns `self.ui_renderer` when `_hdr_gui_data` is nil). That Gui's baked material list (built at `create_screen_gui` time with `is_in_inn=false`) does NOT contain the raw, inn-only `weave_menu_*` wheel materials — the same three the B/B2 fix dodged at the draw site. So `Gui.material(gui, <texture>)` returns **nil**, and `Material.set_scalar(nil, ...)` fatals with exactly the reported `userdata expected, got nil`. The crashify cites a `_draw` line number (392) because the build's line table shifts; the only `set_scalar` in the window is in `_set_background_bloom_intensity`.
- Reached every frame in mission: **Panel** — `update` → `_draw` → (`if _draw_background_wheel`) `_update_background_animations` → `_set_background_bloom_intensity`; `_draw_background_wheel` is set true for every layout EXCEPT `weave_properties` (i.e. the default overview), so the panel crashes as soon as the forge opens. **Properties** — `_update_animations` → `_update_background_animations` → `_set_background_bloom_intensity` **unconditionally** (no `_draw_background_wheel` gate), so the properties editor crashes the moment a weapon's skill tree is opened.

### Fix (skip the per-frame bloom pulse in mission)
- New full `mod:hook` (not `hook_safe` — the vanilla body must be SKIPPED, not run after) on `_set_background_bloom_intensity` for **both** `HeroWindowWeaveForgePanel` and `HeroWindowWeaveProperties`. In mission it returns without calling vanilla, so the nil-material `set_scalar` never runs. The bloom pulse is purely the decorative wheel-glow intensity; the wheel widgets are already emptied from the draw arrays by B2, so nothing visible is lost beyond what B/B2 already removed.
- **KEEP path fully unchanged:** gated on `_is_in_keep()` via `mod._cim_skip_bloom_intensity_in_mission`. In the keep the vanilla bloom pulse runs untouched (full HDR there).
- **No hooks removed, no duplicates.** Neither `(HeroWindowWeaveForgePanel, _set_background_bloom_intensity)` nor `(HeroWindowWeaveProperties, _set_background_bloom_intensity)` was hooked anywhere else in cim (grep-verified — cim's existing `HeroWindowWeaveProperties` hooks are on `_create_viewport_definition` / `_create_unit_previewer` / `_setup_menu_options` / `_sync_backend_loadout` / `_draw` / `_set_essence_upgrade_cost` / `_upgrade_magic_level` / `create_ui_elements` / `on_enter`, none of them this method; `HeroWindowWeaveForgePanel` had no method hooks except the `create_ui_elements` suppression loop).

### Second deref site — forge-upgrade "upgrade" transition animation (Fix B4, same crash class)
- The same audit found a SECOND path to the identical `Material.set_scalar(nil, ...)` crash: the forge-**upgrade** transition animation. The `upgrade` animation group's `init`/`update` closures in `hero_window_weave_forge_overview_definitions.lua` (sub-anims `dissolve_in` / `dissolve_out` / `intensity`) and `hero_window_weave_forge_weapons_definitions.lua` (sub-anim `intensity_out`) do `local gui = params.parent:hdr_renderer().gui` → `Gui.material(gui, <skull_circle / upgrade_effect>.content.texture_id)` → `Material.set_scalar(<material>, ...)`. After Fix B those raw, inn-only materials are absent from the base mission Gui → nil material → fatal, same signature as B3.
- Trigger: pressing the athanor / weave **Upgrade** button and the backend call **succeeding** runs `_upgrade_forge_done` (overview line 815) / `_upgrade_item_done` (weapons line 950) → `_start_transition_animation("upgrade")`. Reachable through the cim forge whenever the player upgrades mid-mission.
- Fix: full `mod:hook` on `_start_transition_animation` for the two windows whose `upgrade` animation touches HDR materials (`HeroWindowWeaveForgeOverview`, `HeroWindowWeaveForgeWeapons`). In mission it **drops only the `"upgrade"` animation** — every other animation these windows start (`on_enter`, text fades, font tweens) is HDR-free and runs untouched. The upgrade itself (backend write + loadout sync) is unaffected because that happens in `_upgrade_forge_done` BEFORE the animation starts; only the decorative skull-circle dissolve / glow flourish is skipped in mission. **KEEP path unchanged** (gated on `is_in_inn`). No duplicate hooks (neither method was hooked elsewhere in cim — grep-verified).
- `HeroWindowWeaveProperties` is deliberately NOT guarded here: its animation definitions contain **no** HDR `Material.set_scalar` (its only HDR `set_scalar` was the bloom pulse handled above), so its animations are safe in mission and must run for the normal fade-in.

### Audit of the remaining surfaces (no further vectors found)
- `HeroWindowWeaveForgeOverview` / `HeroWindowWeaveForgeWeapons` runtime-window code touches HDR only via the `_draw` passes (covered by B2's array-emptying) and the upgrade animation (B4 above). `HeroWindowWeaveForgeBackground` builds no HDR arrays and touches no HDR Gui.
- `HeroViewStateWeaveForge.set_fullscreen_effect_enable_state` uses `ShadingEnvironment.set_scalar` on the base UI world's shading env and is **already vanilla-guarded** (`if shading_env then`), reading `self.ui_renderer.world` (present in both keep and mission) — not a mission-only nil vector.
- Confirmed the `hdr_renderer` / `hdr_top_renderer` accessor fallback (v0.7.71-dev) still returns the base renderer instead of indexing a nil `_hdr_gui_data` — that guard remains the draw-time backstop.

### Tests
- New `/cim_regression_test` check `hdr_bloom_setscalar_skipped_in_mission` (B3): asserts `mod._cim_skip_bloom_intensity_in_mission` is exposed and agrees with `_is_in_keep()` (skip in mission, run in keep), and that both windows' `_set_background_bloom_intensity` methods still exist on the vanilla classes.
- New `/cim_regression_test` check `hdr_upgrade_anim_skipped_in_mission` (B4): asserts `mod._cim_skip_upgrade_anim_in_mission` never skips a non-`upgrade` animation, skips `"upgrade"` only in mission (runs it in keep), and that both windows' `_start_transition_animation` methods still exist.

### Verification (requires the opt-in path)
- Reproduces ONLY with **Loremaster's Armoury installed** + **`Allow in mission` ON**, in an **Adventure mission**: open the forge (B hotkey), **browse weapons**, **open a weapon's skill tree** (properties editor), and **upgrade the athanor / a weave**. With this fix the forge should stay open and usable mid-mission through all of those, minus the decorative wheel-glow pulse and the upgrade flourish.

## 0.8.17-dev (2026-06-22) — Fix in-mission forge `weave_menu_*` "Material not found in Gui" crash (completes Fix B at the draw site)

**CRASH FIX (opt-in path).** After v0.8.16-dev (Fix B) stopped the in-mission forge from force-building the keep's HDR worlds, opening the forge **in a mission** with **`Allow in mission` ON** hit a NEW crash on the fade-in frame:

```
[Script Error] scripts/ui/ui_passes.lua:134: Material `weave_menu_upgrade_skull_circle_shade` not found in Gui
```

Session `35046c6c-44fe-4d05-b02d-cd08dee7294c`. The keep forge and the default `allow_in_mission` OFF path were never affected.

### Root cause (`crafting_in_modded_dev.lua`, weave-forge `create_ui_elements` draw path)
- A Stingray `Gui` resolves named materials ONLY from the fixed list baked in at `World.create_screen_gui()` time (`ui_renderer.lua:246-251`). There is no API to add a material to a live `Gui`, and `Managers.package:load` cannot retro-add one — so this is a **Gui material-list gap, NOT a package-residency failure** (the `reference_vt2_la_package_force_load_crash` guard is moot; no force-load is needed or possible).
- The keep's HDR renderer is built with `is_in_inn=true` (`hero_view.lua:178`), so the inn-only material block in `ingame_ui_settings.lua` adds the weave-forge materials. The **base mission renderer** is built once at `IngameUI.init` with `is_in_inn=false` (`ingame_ui.lua:76-77`), so that block is skipped.
- Three RAW (non-atlas) materials the forge's HDR widgets draw live ONLY in that inn-only block: `weave_menu_upgrade_skull_circle`, `weave_menu_upgrade_skull_circle_shade`, `weave_menu_athanor_upgrade_bg`. (Everything else the forge draws is atlas-backed in `gui_menus_atlas`, which rides in the always-loaded `materials/ui/ui_1080p_menu_atlas_textures`, so it never faults.)
- Fix B left `_hdr_gui_data` nil in mission, so the `hdr_renderer` / `hdr_top_renderer` hooks fall through to the base mission renderer. The four forge windows draw their `_bottom_hdr_widgets` / `_top_hdr_widgets` on `parent:hdr_renderer()` (e.g. `hero_window_weave_forge_overview.lua:704-737`) → those three materials aren't resident → `ui_passes.lua:134` fatal. Fix B traded a C-level world assert for a Lua material-resolve error; this completes it.

### Fix (suppress the keep-only HDR glow at the draw site)
- New `hook_safe` on `create_ui_elements` for the four HDR forge windows (`HeroWindowWeaveForgeOverview`, `HeroWindowWeaveProperties`, `HeroWindowWeaveForgeWeapons`, `HeroWindowWeaveForgePanel`; `HeroWindowWeaveForgeBackground` builds no HDR arrays and is omitted). In mission, it **empties** `self._top_hdr_widgets` / `self._bottom_hdr_widgets` (assigned as the last step of vanilla `create_ui_elements`), so the vanilla `_draw` loops iterate nothing and the three keep-only materials are never resolved.
- Emptying the arrays is preferred over `content.visible=false` / `alpha=0`, which still leave the widget in the iterated array (alpha-0 in particular still resolves the material). The widgets stay registered in `_widgets_by_name`, so the existing `_forge_apply_ui_polish` `_forge_hide_widget("upgrade_bg" / "top_hdr_background_write_mask")` calls remain valid no-ops.
- **KEEP path fully unchanged:** gated on `not _is_in_keep()`. In the keep the HDR arrays are left intact and the forge keeps its full HDR glow (drawn on the real keep HDR renderer that carries the inn-only materials).
- Cost: the decorative skull-circle glow ring and the athanor upgrade-panel background glow are absent **in mission only**. The forge is otherwise fully drawn and usable. This is exactly the "drops the HDR glow layer in mission only" cost Fix B already documented — the glow elements just weren't suppressed at the draw site.
- **No hooks removed.** The four `(window, create_ui_elements)` pairs were previously un-hooked by cim (grep-verified — no duplicate-hook violation).

### Fix B2 second vector — skill-tree cluster glow re-appended after suppression (`cim_debug.lua`, `HeroWindowWeaveProperties.on_enter`)
- `HeroWindowWeaveProperties.on_enter` calls `create_ui_elements` (line 151) FIRST — where the suppression above empties the HDR arrays — then calls `_create_slot_grid` (line 200) → `_create_cluster_background` (`hero_window_weave_properties.lua:894-924`), which **re-appends** the raw, inn-only `athanor_skilltree_cluster_effect_*` glow widgets to `_bottom_hdr_widgets` AFTER suppression. Those textures are also raw / non-atlas (not in any `atlas_settings` file) and live only in the inn-only material block, so they would fault on the base mission renderer the same way once a weapon's skill-tree is opened mid-mission.
- The fix folds a second suppression call into the **EXISTING** `mod:hook_safe("HeroWindowWeaveProperties", "on_enter", ...)` in `cim_debug.lua` (NOT a new hook — VMF would silently drop a duplicate `(Class, on_enter)` registration). Because `on_enter` (post) fires after `_create_slot_grid` has re-appended the cluster glow, re-running the helper there re-empties `_bottom_hdr_widgets` in mission. The in-keep detector `_is_in_keep` is now exposed cross-file as `mod._cim_is_in_keep` so the cim_debug hook (a different file) can gate on it.
- **KEEP path unchanged here too:** gated on `mod._cim_is_in_keep()`. In the keep the skill-tree cluster glow survives.

### Tests
- New `/cim_regression_test` check `hdr_glow_widgets_suppressed_in_mission`: drives the exposed `mod._cim_suppress_hdr_glow_in_mission` helper synthetically and asserts (1) in mission the populated HDR arrays are emptied, (2) in the keep they are left intact, (3) already-empty / missing arrays are a safe no-op.
- New `/cim_regression_test` check `hdr_cluster_glow_resuppressed_on_props_enter` (Fix B2 second vector): asserts `mod._cim_is_in_keep` is exposed and returns a boolean, and that the helper — driven with that detector's live value on a synthetic props window carrying a freshly re-appended cluster-effect widget — leaves the array intact in the keep and re-empties it in mission.

### Verification (requires the opt-in path)
- Reproduces ONLY with **Loremaster's Armoury installed** + **`Allow in mission` ON**, opening the forge (B hotkey) in an **Adventure mission**. With this fix the forge should now **OPEN and be usable** mid-mission, minus the three decorative glow elements.

## 0.8.16-dev (2026-06-22) — Fix in-mission forge HARD CRASH with Loremaster's Armoury installed (LA armoury_atlas in HDR world)

**CRASH FIX (opt-in path).** Pressing the **B** hotkey (`forge_hotkey` → `open_forge`) **in a mission** with **`Allow in mission` ON** and **Loremaster's Armoury (LA) installed** hard-crashed the game on the fade-in frame. The keep forge and the default `allow_in_mission` OFF path were never affected — this only hit the opt-in override the menu already labels "(may crash)". Session `b688f241-50e0-4ad4-9808-e843f61eec6c` (2026-06-22), level `dlc_termite_3`, `dr_ironbreaker`.

### Root cause (`crafting_in_modded_dev.lua`, `HeroView._setup_hdr_gui` hook)
- cim's hook flipped `self.is_in_inn = true` then `pcall`'d vanilla `_setup_hdr_gui`, which **force-built the `hero_view_hdr` / `hero_view_hdr_top` HDR worlds mid-mission** (vanilla never builds them outside the keep) to render the forge's HDR glow layer.
- Building those worlds calls `UIRenderer.create_screen_gui`, and VMF's `custom_textures.lua:228` injects **every** mod-registered GLOBAL UI texture into the new world's material list — including LA's `materials/Loremasters-Armoury/armoury_atlas` (#ID[456d0ff315e50d78]).
- A brand-new mid-mission world cannot resolve that global atlas, so the engine fatally asserts at `c_api_world.cpp:568` (`world.resource_manager().can_get(material_type, name)`). That is a **C-level assert, not a Lua error**, so cim's `pcall` could not catch it → hard crash.

### Fix B (stable, lower-risk) — do NOT force-build the in-mission HDR worlds
- In mission, the `_setup_hdr_gui` hook now **skips vanilla entirely**. `_hdr_gui_data` stays nil, so the existing `HeroView.hdr_renderer` / `hdr_top_renderer` hooks fall through to `self.ui_renderer` / `self.ui_top_renderer` (the `heroview_hdr_renderer_guard_failsafe` fallback, now the NORMAL in-mission path). The forge opens against the standard renderer and **never calls `create_screen_gui` on a world that can't host LA's material**.
- Cost: the forge loses its HDR glow layer **in mission only** (it already used the mission-safe `environment/ui_hdr` shading env there). The **keep (`is_in_inn`) forge is fully unchanged — full HDR**.
- The `_cim_sweep_leaked_hdr_worlds` half-built-world sweep (Issue #73) is **retained as a no-op safety net** but is no longer reached on the mission path (we never build the worlds there now).
- **No hooks added or removed.** The three `(HeroView, _setup_hdr_gui / hdr_renderer / hdr_top_renderer)` pairs each still have exactly one cim hook; only the `_setup_hdr_gui` body changed. The separate `HeroViewStateWeaveForge._setup_gamepad_gui` force-build (a different, non-LA `_gui_data` nil-index crash class) is **untouched**.

### Tests
- New `/cim_regression_test` check `heroview_hdr_not_forcebuilt_in_mission`: source-pattern asserts the `_setup_hdr_gui` hook (a) contains the Fix B skip marker and (b) no longer contains the old `saved_is_in_inn`-flip / post-failure HDR-world-sweep force-build sequence. Needles are split literals so the test doesn't self-match, and the negative needles are keyed to tokens unique to the old `_setup_hdr_gui` body so the still-valid `_setup_gamepad_gui` force-build is not flagged.
- Existing `heroview_hdr_renderer_guard_failsafe` (the ui_renderer fallback) is unchanged and is now the primary guarantee that the skipped-build path stays crash-safe.

### Verification (REQUIRES the right environment)
- Must be validated **with Loremaster's Armoury installed** + cim `Allow in mission` **ON**, in an **ADVENTURE mission** (NOT Chaos Wastes). Press B mid-mission; the forge must open against the standard renderer with no `c_api_world.cpp:568` assert. Without LA installed the crash does not reproduce, so a clean open there does not validate the fix.

### Changed
- MOD_VERSION → 0.8.16-dev.

## 0.8.15-dev (2026-06-21) — Loadout persistence is now OPT-IN, DEFAULT OFF (stop perturbing vanilla bot/player loadouts)

**DEFAULT BEHAVIOR CHANGE.** cim no longer persists/restores/syncs/migrates loadouts by default. It was effectively **always-on** before (the only gate was `restore_modded_loadout`, which still left the capture + sync + migration hooks live). Users reported cim breaking their **existing VANILLA bot loadouts** — saved in the base game, with **no cim-crafted weapons involved**: bots cloned the host's loadout instead of getting their designated vanilla loadout, because cim's capture/restore/sync/migration paths were writing into / re-syncing the loadout mirror even when the player had nothing modded equipped. The fix makes cim fully OPT-IN on the loadout path so out of the box vanilla player AND bot loadouts behave exactly as the base game intends.

### New master toggle — `persist_modded_loadouts` (DEFAULT OFF) (`crafting_in_modded_dev_data.lua` / `_localization.lua`)
- New checkbox in the **Modded Inventory** group: "[untested] Persist modded-crafted weapons across loadouts/sessions", default **false**.
- Tooltip: "When OFF (default), cim does NOT touch your loadouts — your vanilla player and bot loadouts behave exactly as the base game. Turn ON only if you want cim-CRAFTED weapons to survive relogs (they won't while this is off; re-equip them as needed)."
- The pre-existing `restore_modded_loadout` checkbox is now a SUB-gate that only matters when this master toggle is ON; its description was updated to say so.

### When OFF (the default): cim is a pure pass-through on every loadout path (`crafting_in_modded_dev.lua`)
A single `_persist_loadouts_enabled()` helper (`mod:get("persist_modded_loadouts") == true`, nil/type-safe) gates every write/sync/migrate site — **no new hooks added, no hooks removed** (each `(Class, method)` pair still has exactly one cim hook, consolidated at the existing body):
- **`_capture_loadout_equip` (entry)** — bails immediately when OFF, so NEITHER the `BackendInterfaceItemPlayfab.set_loadout_item` hook_safe NOR the `BackendUtils.set_loadout_item` full hook records anything into `_modded_loadout`. The BackendUtils hook still calls `func(...)`, so the underlying vanilla write is byte-identical.
- **`LoadoutUtils.sync_loadout_slot` hook** — returns `func(...)` verbatim when OFF: no `item.rarity` "modded"->"unique" wire-rewrite, no `cim_modded_slot` side-channel send. The wire payload is exactly what vanilla would send.
- **`PlayerManager.rpc_sync_loadout_slot` hook_safe** — bails when OFF: no received-slot rarity patching (the side-channel state stays empty anyway because the sender never fired it).
- **`_restore_modded_loadout` (entry)** — no-ops when OFF: no flat->indexed migration (`_run_loadout_migration`), no `_modded_loadout_purge_stale`, no `set_loadout_item` writes, no `_reequip_live_avatar`. The boot/keep restore (`_create_interfaces` hook + the 1.0s/3.0s deferred passes + `/cim_restore_loadout`) all fall through this gate.

Net effect with the toggle OFF: cim writes/syncs/migrates nothing into the loadout mirror, so a bot reads its DESIGNATED vanilla loadout index (never a host clone) and the player's vanilla loadouts are untouched — byte-identical to not having cim installed on the loadout path.

### When ON: unchanged 0.8.14 behavior
- Index-aware capture (threading `optional_loadout_index` / resolving the live selected index), mirror-ready flat->indexed migration, index-correct restore, the modded-rarity wire-rewrite + side-channel, and the bot designated-index handling all work exactly as in 0.8.14-dev.

### Crafting is untouched
- The craft path (Athanor synth, `_athanor_inject_item`, `_forged_weapons` register/save/load, the weave-forge `BackendInterfaceWeavesPlayFab.set_loadout_item` craft-staging hook gated on `_custom_forge_active`) is NOT on the loadout-persist path and is unchanged. You still craft weapons with the toggle off; they just won't auto-persist into loadouts across relogs.

### Debug probe unchanged
- The read-only `[cim:loadout_probe]` mirror dump (`/cim_loadout_dump`, the `set_loadout_index` hook_safe, `_cim_loadout_probe_dump`) is purely diagnostic (no writes) and works either way.

### Tests
- New `/cim_regression_test` check `persist_loadouts_gate_off_is_passthrough`: with the master toggle forced OFF, a real modded `set_loadout_item` call leaves `_modded_loadout` empty (no capture leak), and the gate helper reflects the live setting.
- `_rt_with_loadout_sandbox` now forces `persist_modded_loadouts` ON for the body of the existing persistence round-trip tests (and restores the user's real value on teardown) so those tests still exercise the capture/persist path under the new default-OFF gate.

### Changed
- MOD_VERSION → 0.8.15-dev.

## 0.8.14-dev (2026-06-21) — Fix host-restore regression in the 0.8.13 flat->indexed migration (migration TIMING)

Adversarial review of 0.8.13-dev caught a blocker for the multi-loadout minority: the flat->indexed migration `_migrate_modded_loadout` ran at **MOD SCRIPT-EVAL time** (from `_modded_loadout_load`, called at the file-scope `_modded_loadout_load()` near line 882), **before the backend mirror exists**. So `_resolve_selected_index(career, 1)` always hit its fallback and returned **1**, homing EVERY migrated flat entry under loadout index 1, then persisting. For a player whose actual selected loadout index was NOT 1, their saved modded gear migrated to the index-1 loadout (not their active one), and `_reequip_live_avatar` (which reads the LIVE selected index) found nil there → the keep avatar showed VANILLA weapons after migration. No bid was dropped (self-heals on a re-equip), but it was a real regression versus pre-0.8.13 behavior.

### Fix — DEFER migration to the first mirror-ready moment (`crafting_in_modded_dev.lua`)
- **Removed the migrate call from boot.** `_modded_loadout_load()` now loads the raw saved payload AS-IS (flat or indexed) with no migration; the script-eval `_modded_loadout_load()` no longer mutates/persists anything.
- **New `_run_loadout_migration()` driver, called from `_restore_modded_loadout` right after `_modded_loadout_load()` and BEFORE purge/restore** — i.e. at a mirror-confirmed moment (the `_create_interfaces` hook + the 1.0s/3.0s deferred passes). It resolves each flat career's REAL live selected index via `_resolve_selected_index(career)` and homes the entry there, then persists once. Multi-loadout user whose selected index is 3 now gets their migrated gear homed to index 3 (their active loadout), and `_reequip_live_avatar` finds it → keep avatar re-equips correctly.
- **Idempotent + one-shot.** `_migrate_modded_loadout` takes a `mirror_ready` flag: when the mirror is up it migrates to the resolved real index; when it's NOT up it SKIPS the career (leaves it flat) rather than guess. A `_loadout_migration_done` one-shot flag flips true only after a mirror-ready pass with nothing flat remaining, so the deferred passes / `/cim_restore_loadout` don't re-scan or redundantly persist. Even without the flag the pass is a no-op on already-indexed data (`_career_value_is_flat` returns false). If the mirror is somehow still unavailable at the restore path, migration does nothing this pass and the flag stays unset, so the next deferred pass re-attempts — no data lost.

### Early-consumer audit (consumers that read `_modded_loadout` before the deferred migration)
- **`_cim_clear_modded_loadout_for_bid` (salvage)** — the only pre-mirror consumer. Now tolerates BOTH shapes: flat (career -> slot -> bid) and indexed (career -> index -> slot -> bid), detected per career via `_career_value_is_flat`, so a salvage that runs while a career is still flat still clears the bid (never strands a dangling restore target, never crashes).
- The restore loop, `_modded_loadout_purge_stale`, and `_reequip_live_avatar` all run AFTER `_run_loadout_migration` in the same `_restore_modded_loadout` call, so they always see the indexed shape.
- The read-only debug commands `/cim_dump_loadout` and `/cim_restore_loadout` already guard with `type(indices) == "table"` (flat entries are simply not listed until migration runs); `/cim_restore_loadout` itself triggers the migration via `_restore_modded_loadout`.

### Hardening (non-blocking, flagged by review)
- `_rt_with_loadout_sandbox` teardown loop now carries the symmetric `type() == "table"` guards (`pairs(indices)` / `pairs(slots)`) that the snapshot half already had, so a malformed in-memory shape can't crash the test teardown.

### Unchanged (confirmed correct by the bot-fix review, ok=true)
- Index-aware capture (`BackendInterfaceItemPlayfab` threading `optional_loadout_index`; `BackendUtils` resolving the live selected index), restore passing the saved index as the 4th arg to `set_loadout_item`, the bot designated-index handling, and the `_restoring` guard are all untouched. ONLY the migration timing, the sandbox guard, and the one early-consumer shape-tolerance changed.

### Changed
- MOD_VERSION → 0.8.14-dev.

## 0.8.13-dev (2026-06-21) — INDEX-AWARE modded-loadout persistence (fixes bot loadouts cloning the host)

The v0.8.11/.12 probes confirmed the diagnosis: cim's persisted modded loadout was **FLAT** (`_modded_loadout[career][slot] = bid`, no loadout-index dimension). Both capture hooks dropped `optional_loadout_index`, and restore wrote with no index arg — so every saved modded item was stamped onto the **SELECTED** loadout index. Vanilla reads each **bot's** gear from its **DESIGNATED** index (`PlayerData.loadout_selection.bot_equipment[career]` → `get_character_data(career, slot, bot_loadout_index)`, `backend_interface_item_playfab.lua:150`), so a bot's designated-index modded gear was never persisted/restored to that index → **bots cloned the host's selected loadout**; the player's modded items also got conflated across loadout switches. This version makes the whole persist/capture/restore path index-aware.

This is the real fix for the user-confirmed "bot loadouts clone the host instead of their designated per-career loadouts" report.

### Schema change — index dimension added
- `_modded_loadout` is now `[career_name][loadout_index][slot_name] = backend_id` (was `[career_name][slot_name] = backend_id`). Same single migrate-able table, persisted via `mod:set("modded_loadout", ...)` as before.

### Capture — record the index each equip wrote to (`crafting_in_modded_dev.lua`)
- `_capture_loadout_equip` gains a `loadout_index` param and stores the bid under `[career][index][slot]`, clearing/refreshing only that `(index, slot)` (other indices for the same career/slot are untouched).
- The `BackendInterfaceItemPlayfab.set_loadout_item` hook_safe now passes its 4th arg `optional_loadout_index` through, so a write to a NON-selected index (configuring a bot's designated loadout) is recorded under that index.
- The LA-path `BackendUtils.set_loadout_item` hook is 3-arg (no index) and always writes the SELECTED index, so it passes `nil`; the capture helper resolves the live selected index off the mirror (`_career_loadouts[career]` / `:get_career_loadouts(career)`, LA-safe) and stores under it. New helper `_resolve_selected_index(career, fallback)` — nil/type-safe, never throws, falls back to index 1.

### Restore — stamp each saved item back to ITS index (`crafting_in_modded_dev.lua`)
- `_restore_modded_loadout` now iterates `career -> index -> slot` and passes the saved index as the 4th arg: `items:set_loadout_item(bid, career, slot, index)` → `set_character_data(..., optional_loadout_index)` (`playfab_mirror_base.lua:1928`). This stops stamping everything into the host's selected index, so a bot's designated index keeps its distinct modded gear. A non-numeric (corrupt) index falls back to vanilla's selected-index default rather than throwing.

### Migration — NO DATA LOSS
- On load, `_migrate_modded_loadout` detects the OLD flat shape (career value carrying string slot-keys) and re-homes each flat entry under that career's CURRENT selected loadout index (fallback 1 when the mirror isn't loaded yet), then persists the migrated table once. That's the safe target: pre-0.8.13 cim only ever stamped the selected index, so the flat entries WERE the selected-index gear — assigning them there preserves the exact prior behavior for the active loadout while unlocking per-index storage. Every step is guarded against partial/corrupt entries (stray numeric→table entries are kept intact); no saved bid is ever dropped.

### Safety preserved
- The `_restoring` guard and all existing restore safety (pcall-per-entry, host/owner-authoritative, idempotent deferred passes) are unchanged — the restore path burned issues #22 / #67, so nothing there was loosened. The working host modded-loadout restore (player's selected-index modded weapons) still works; `_reequip_live_avatar` reads the selected index only (the live keep unit shows the selected loadout). All sibling consumers (`_cim_clear_modded_loadout_for_bid`, `_modded_loadout_purge_stale`, the `/cim_dump_loadout` / `/cim_restore_loadout` commands, the regression sandbox + tests) updated to walk the index dimension.

### Probes (validation surface — `cim_debug.lua`)
- The 0.8.12 auto-fire `[cim:loadout_probe]` dump now shows cim's record per index (`_modded_loadout[career][index].slot`), with `<-SELECTED` / `<-BOT` markers — after this fix it should show DISTINCT bot indices, validating the fix in-game.
- `_cim_autodump_equip_event` logs the `captured_index`; `_cim_autodump_restore_entry` logs the `written_index` and reads back AT that index via `mirror:get_character_data(career, slot, index)` (the items-interface `get_loadout_item_id`'s 3rd arg is `is_bot`, not an index — it can't prove a non-selected-index write).
- `modded_loadout_round_trip_save_then_clear` regression test now passes an explicit non-1 index and asserts the indexed shape.

### Changed
- MOD_VERSION → 0.8.13-dev.

## 0.8.12-dev (2026-06-21) — Loadout-index probe: auto-fire the full per-index dump (no command needed)

The v0.8.11 per-index dump required typing `/cim_loadout_dump`. Now it auto-fires (debug-gated) at the three moments that matter, so the user just plays and the log captures it: after cim's restore (`_cim_autodump_restore_done` — exposes which index each modded item was stamped onto), on backend-ready (`_cim_autodump_backend_ready` — keep-entry snapshot), and after every loadout switch (`_cim_loadout_probe_on_switch`). The `/cim_loadout_dump` command stays as a manual fallback. Still read-only diagnostics.

## 0.8.11-dev (2026-06-21) — READ-ONLY loadout-INDEX probe suite (debug-only)

Diagnostic-only. Adds a read-only probe set (tag `[cim:loadout_probe]`, gated on `enable_debug_logging`) to diagnose cim's loadout index-blindness: cim's `_modded_loadout[career][slot]` is **FLAT** (no loadout index), its capture drops `optional_loadout_index`, and `_restore_modded_loadout` (`crafting_in_modded_dev.lua:955`) writes with no index — so modded items always land on the **SELECTED** loadout index, not whatever index the user (or a bot designation) actually wanted. These probes make the per-index reality visible. No gameplay or loadout writes; every mirror/engine call is pcall-guarded; nil/type-safe.

Confirmed loadout model (verified against decompiled source): `PlayFabMirrorBase._career_data[career][loadout_index][slot]` stores gear; `_career_loadouts[career]` = the SELECTED index; `PlayerData.loadout_selection.bot_equipment[career]` = the bot DESIGNATED index; `get_character_data(career, slot, optional_loadout_index)` defaults to the selected index (`playfab_mirror_base.lua:1909`). Mirror reached LA-safe via `Managers.backend:get_interface('items')._backend_mirror`.

### Added (all in `cim_debug.lua`)
- **`/cim_loadout_dump`** chat command. For the current career + every career with a `_modded_loadout` entry, logs: the SELECTED index (`_career_loadouts[career]`); the bot DESIGNATED index (`PlayerData.loadout_selection.bot_equipment[career]`); the loadout count; for EACH index `1..N` the item ids of `slot_melee/slot_ranged/slot_necklace/slot_ring/slot_trinket_1` via `mirror:get_character_data(career, slot, index)` (each tagged MODDED via `mod._cim_is_modded_backend_id`, or vanilla); plus cim's flat `_modded_loadout[career]`. `<-SELECTED` / `<-BOT` markers flag the active and bot-designated indices.
- **Loadout-SWITCH probe** — read-only `hook_safe` on `PlayFabMirrorBase.set_loadout_index` (the chokepoint `BackendInterfaceItemPlayfab.set_loadout_index` forwards to). Logs `career + old_selected -> new_selected`. No existing cim hook on this `(Class, method)` (grepped — VMF no-duplicate-hook rule satisfied).

### Changed (all in `cim_debug.lua`, debug-only)
- `_cim_autodump_equip_event` now also logs `selected_index` (the index the equip wrote to — the GUI 3-arg `set_loadout_item` never passes an index, so equips always hit the SELECTED index).
- `_cim_autodump_restore_entry` now also logs `target_index` (the SELECTED index each restore write resolves to) — making the wrong-index stamping visible.
- MOD_VERSION → 0.8.11-dev.

## 0.8.10-dev (2026-06-21) — Fix false `[cim:diag] Equip read-back MISMATCH` warnings (debug-only)

The equip diagnostic (`cim_debug.lua` `_cim_autodump_equip_event`) did an immediate `get_loadout_item_id` read-back and warned on a mismatch. On the **LA menu-equip path** the capture (`crafting_in_modded_dev.lua:1096` `BackendUtils.set_loadout_item` pre-hook) runs `_capture_loadout_equip` **before** vanilla `func()` commits the write, so the read-back was PRE-write and always reported the *previous* item — a false MISMATCH (the off-by-one log pattern: each read == the prior equip). The actual loadout capture is unaffected (it records the passed `item_id`, line 1054, not the read-back), so equips/restore were always correct; only the warning was spurious.

### Changed
- `_capture_loadout_equip` now threads `from_live_equip` into `_cim_autodump_equip_event` (`crafting_in_modded_dev.lua:1043`).
- `_cim_autodump_equip_event` (`cim_debug.lua`) skips the read-back + MISMATCH warning when `from_live_equip` (the pre-write LA path); the read-back logs as `<pre-write>` there. The post-write `BackendInterfaceItemPlayfab` hook_safe path keeps the real read-back validation.
- MOD_VERSION → 0.8.10-dev.

## 0.8.8-dev (2026-06-19) — Test-status labels on all menu entries

Prefixed every VMF menu widget with `[untested]` so we know what's safe to promote to stable `cim`. Tooltips, group headers, and `enable_debug_logging` are not labeled. Flip to `[confirmed working]` as features are verified in-game. See `TESTING_STATUS.md`.

## 0.8.7-dev (2026-06-18) — Fix Trollhammer select-crash (weave tooltip) + add craft-button audio feedback

### Fixed — crash on selecting the Trollhammer Torpedo (and other deus/CW weapons)
Crash report (nicho, on cim_dev v0.8.6-dev): selecting the Trollhammer Torpedo (`dr_deus_01`) in the Athanor editor hard-crashed `hero_window_weave_properties.lua:1701: attempt to concatenate local 'tooltip_slot_sub_title' (a nil value)` in `_sync_backend_loadout`, via `on_enter`. This is the **next-in-sequence** deus/CW crash after the v0.8.2 `_setup_menu_options` `ipairs(nil)` guard — both run in `on_enter`. cim re-exposes deus/CW weapons whose property/trait/talent **table-names aren't weave categories**, so the per-slot tooltip build does `slot_type_strings[cat] or localized_strings[cat]` → both miss → nil → concatenate crash. Those tooltip-string tables are per-call locals (not pre-seedable like the category pools the v0.8.2 fix handles), so the fix wraps `HeroWindowWeaveProperties._sync_backend_loadout` in a pcall under the modded forge. The property/trait bubbles sync before the failing talent-tooltip section, so editing still works — only the unknown-category tooltip degrades. New hook (distinct class from the existing `HeroWindowWeaveForgeWeapons._sync_backend_loadout` hook — no duplicate).

### Fixed — silent Athanor craft buttons
The weapon-select pane CRAFT (`_equip_item`) and the editor CRAFT (`_upgrade_magic_level`) both crafted and returned **without playing the completion sound** — vanilla's equip/upgrade sound sits past the custom-forge early-return, so those buttons gave no audio feedback (visual echo/pulse only). Both now call `self:_play_sound("play_gui_craft_forge_button_completed")` on a successful craft (the same sound cim already plays on the standard-forge/console craft pages).

## 0.8.6-dev (2026-06-18) — Drop Versus-carousel twins that shadow a real Adventure weapon (the "wh_book" locked entry)

### Why
User report: a non-craftable book entry (reported as `wh_book_name`) showed up **locked** in the Athanor weapon list. Root cause: cim enumerates raw `ItemMasterList` and **intentionally** surfaces `vs_*` Versus-carousel weapons as craftable (it clears their `mechanisms` on craft so the result is Adventure-visible — Gallant's Blade, Soldier's Coach Gun, etc.). But a handful of `vs_*` items have a **real non-versus Adventure twin sharing the same `display_name`** — notably `vs_wh_hammer_book` vs the real `wh_hammer_book`. cim's list dedups by `display_name`, so the Versus twin can win the dedup and render as a locked, uncraftable row (`backend_id = nil`) that **hides** the real craftable weapon.

### Fixed
- New `_cim_versus_shadowed(data, real_names)` gate in `standard_forge.lua` (+ `_cim_is_versus` / `_cim_real_display_names` helpers, exposed on `mod`), applied to all three craft-list builders: the menu weapon list (`_setup_weapon_list`), the standard-forge random-pick pool, and the blacksmith template cache. A versus item is dropped **only when a real (non-versus) item with the same `display_name` exists** — so unique `vs_*` weapons (no real twin) stay craftable, and the real `wh_hammer_book` replaces its locked versus twin. The real-`display_name` set is built once per list-build (O(n), not O(n²)).
- Explicitly **not** a blanket versus exclusion — that would remove the intentional cross-character/versus crafting feature (the user confirmed other `vs_*` weapons work fine).

### To verify (in-game)
- Open the Warrior Priest melee craft list: the locked `wh_hammer_book` twin should be gone, replaced by the real craftable hammer+book. Confirm unique Versus weapons (Gallant's Blade etc.) still appear and craft. If a *specific* item still shows locked, capture the `_cim_autodump_weapon_list_setup` dump (Debug Logging on) to pin the exact key/source.

## 0.8.5-dev (2026-06-17) — Version realignment (no functional change)

Bumped the dev clone's version from `0.7.76-dev` to `0.8.5-dev` so it sits one patch **ahead** of stable cim (`0.8.4`) instead of a MINOR behind it. The lineages had drifted: stable jumped `0.7.48-alpha → 0.8.1` at the 2026-06-08 release and continued into `0.8.x`, while this dev clone kept incrementing `0.7.x-dev` — so the friends-only Workshop title (`v0.7.76-dev`) read as older than public `v0.8.4` even though dev is the bleeding edge. Code/work was already in sync (both top out at Issue #71). Source-only bump; cfg title updated to match. Live friends-only Workshop title refreshes on the next cim_dev upload. Dev now tracks one patch ahead of stable going forward.

## 0.7.76-dev (2026-06-17) — Issue #71 (Option A): re-enable in-editor CRAFT for weapons so "set properties → craft" works

### Why
Issue #71's second report (carlotheemo, on public v0.8.0): "Press B, press weapon, press greatsword, temper, add 5 atsp + 5 crit, add Swift Slayer, back, then craft → Outcome: No properties." Root-caused (2026-06-17): cim splits "craft a weapon" from "edit a weapon's properties". The **weapon-select pane** CRAFT button (`HeroWindowWeaveForgeWeapons._equip_item`) always mints a **blank** weapon (`properties = {}`, `traits = {}`, fresh `Application.guid()`). Property/trait edits in the **weave-properties editor** mutate the in-editor item in place via `_forge_apply_to_item`. The editor's own CRAFT button — which clones those live edits into a new item (`_upgrade_magic_level`, the same machinery the amulet uses) — was **hidden for melee/ranged** and the hook early-returned. So a user who set properties in the editor and then crafted got a blank weapon: the reporter backed out of the editor and used the weapon-select pane's blank CRAFT. Confirmed identical in stable v0.8.0/v0.8.2.

### Changed
- `crafting_in_modded_dev.lua` — `_set_essence_upgrade_cost` hook: removed the melee/ranged branch that hid the `upgrade_button`; the button now shows **"CRAFT"** for weapons (label logic already handled weapon vs jewellery).
- `crafting_in_modded_dev.lua` — `_upgrade_magic_level` hook: removed the melee/ranged early-return so weapons fall through to the existing mint-new path (clones `item.properties` / `item.traits` into a fresh `_athanor_inject_item` craft). No new code path — re-enables one that already shipped for the amulet.

### Behavior
- Working flow is now: open the weave-properties editor on a weapon → set bubbles/trait → press **CRAFT** (in the editor) → a new modded weapon carrying those edits lands in inventory (equip from there). The weapon-select pane's CRAFT still mints a blank weapon as before (pick-and-craft-clean).

### To verify (in-game)
- Open the modded forge, edit a weapon's properties/trait, press CRAFT in the editor, and confirm the crafted weapon in inventory carries the set properties + trait.

## 0.7.75-dev (2026-06-16) — Fix forge stat-editor crash on weapons whose category isn't a weave category (Trollhammer Torpedo)

### Why
Friend crash log (nicho, 2026-06-16): selecting the Trollhammer Torpedo (`dr_deus_01`, on Ironbreaker's `slot_ranged`) in the modded forge crashed `hero_window_weave_properties.lua:385: bad argument #1 to 'ipairs' (table expected, got nil)` in `HeroWindowWeaveProperties._setup_menu_options`. Vanilla `on_enter` clones `WeaveWeaponProgression` for the selected weapon and stamps `slot_unlock.category = item_data.property_table_name / trait_table_name`; `_setup_menu_options` then does `ipairs(WeaveTraits.categories[category])` / `WeaveProperties.categories[category]` / `WeaveLoadoutSettings[career].talent_tree[category]` with no nil-check. cim's Athanor forge re-exposes adventure / Chaos Wastes weapons (the Trollhammer's `property_table_name` is `deus_trollhammer_torpedo`) whose table-names aren't keys in those weave tables → nil → `ipairs(nil)` hard-errors. This is a **distinct crash from the v0.7.70 `_forge_preview_unsafe` guard** — it runs in `on_enter` *before* the 3D previewer, so that guard never gets a chance.

### Changed
- `crafting_in_modded_dev.lua` — new singleton `mod:hook("HeroWindowWeaveProperties", "_setup_menu_options", ...)` (no prior hook on this method) that seeds an empty `{}` pool for every progression category the weave tables don't know about, before vanilla runs. `ipairs({})` is a no-op, so the affected picker renders empty (no weave traits/properties/talents for that weapon) instead of crashing. Idempotent, scoped to the categories in play.

### Tests
- New `/cim_regression_test` check `weave_category_pool_guard_present` — verifies the seeder is wired and idempotently fills the trait + property pools for an unknown category, then cleans up the synthetic key.

## 0.7.74-dev (2026-06-13) — Fix amulet (weave-properties) crash on adventure career talents (Issue #71)

### Why
Multi-agent audit 2026-06-13 (root-caused against the attached crash log). Pressing the amulet (open `HeroWindowWeaveProperties` via B → amulet) under the modded forge crashed: `backend_interface_weaves_playfab.lua:1252: attempt to index local 'progression_data' (a nil value)` in `get_talent_required_forge_level`, called from `hero_window_weave_properties.lua:461`. Under `_custom_forge_active` cim feeds the player's loadout talents (which are ADVENTURE career talents, e.g. `mercenary_helborgs_tutelage`) into the weave talent picker. Vanilla `get_talent_required_forge_level` does `progression_data = self._progression_settings.talents[talent_name]` then `progression_data.required_forge_level` — adventure talents have no weave-progression entry, so `progression_data` is nil and the index is a hard crash. cim already guarded the sibling `get_property_required_forge_level` and `get_trait_required_forge_level` (both `return 0` under the modded forge) but missed the talent one.

### Changed
- `crafting_in_modded_dev.lua` — added the missing `BackendInterfaceWeavesPlayFab.get_talent_required_forge_level` hook returning `0` under `_custom_forge_active` (passthrough otherwise), mirroring the existing property/trait guards. No duplicate-hook conflict (it was previously unhooked).

### Tests
- New `/cim_regression_test` check `weave_talent_forge_level_guard_present` — source-pattern guard that FAILS if the new hook is removed (needle split across two literals to avoid self-match; no-op when source introspection is unavailable).

### To verify (in-game)
- Open the modded forge, press B, click the amulet, and confirm the weave-properties editor opens (talent/property/trait sections render) with **no crash**.

## 0.7.73-dev (2026-06-08) — HDR setup error path: destroy-on-failure sweep + truthful is_in_inn restore (Issue #73)

### Why
The 2026-06-08 post-ship re-review of the in-mission HDR fix found that the pcall converts a mid-body failure into a *deferred* crash: if vanilla `_setup_hdr_gui` fails after creating a world but before `self._hdr_gui_data = hdr_gui_data` (its last statement, hero_view.lua:163), the half-built world leaks unreferenced — `destroy_hdr_gui` never releases it, and the NEXT forge open dies on world_manager's `World "hero_view_hdr" already exists` fassert (engine-fatal, bypasses pcall). Only reachable when the fix is already failing, but the failure mode was worse than the disease.

### Changed
- **`crafting_in_modded_dev.lua`:** new `mod._cim_sweep_leaked_hdr_worlds(world_manager, hdr_gui_data)` — on the `_setup_hdr_gui` error path, destroys any orphaned `hero_view_hdr` / `hero_view_hdr_top` world by name (`WorldManager.destroy_world` accepts the name string, world_manager.lua:64; destroying the world releases its viewport/guis engine-side). No-op when `_hdr_gui_data` was assigned (those worlds are owned by `destroy_hdr_gui`) or when the world manager is absent. Logs **ungated** per failure-path doctrine.
- **is_in_inn restore nit:** the hook now restores the *saved* prior value (`nil` in mission) instead of literal `false` — strictly truthful for any future identity comparison.

### Tests
- `heroview_hdr_failed_setup_sweeps_leaked_worlds` — drives the sweep with a stub world manager: leaked world destroyed by name, owned worlds untouched when `_hdr_gui_data` is set, nil-safe on missing manager.

## 0.7.72-dev (2026-06-07) — Add RPC schema version + receiver gate to `cim_modded_slot`

### Why
Audit 2026-06-07 (finding F10, BUG_CLASSES § 9 / VMF_RECIPES § 10): the `cim_modded_slot` mod-to-mod VMF RPC — the side-channel that tells cim clients which loadout slots hold a "modded"-rarity item — shipped with **no schema-version arg and no receiver validation gate**. Every other versioned RPC in the repo (`gt_lobby_motd_show`) carries `<MOD>_RPC_SCHEMA` as its first positional arg so a payload-shape change between peers on mismatched mod builds is detected and dropped instead of silently mis-decoded (wrong value bound to the wrong positional, corrupting the per-slot modded-flag state). `cim_modded_slot` was the lone exception. This is hardening, not a live crash: today's payload is stable, but a future field add/remove between a host on one cim build and a client on another would mis-bind with no signal.

### Changed
- crafting_in_modded_dev.lua:89 — added `local CIM_RPC_SCHEMA = 1` next to `MOD_VERSION` (mirrors gt's `mod.GT_LOBBY_RPC_SCHEMA`; initial 1, never lower, bump on payload-shape change).
- crafting_in_modded_dev.lua:659 — sender now prepends `CIM_RPC_SCHEMA` as the FIRST positional arg after `target` (`network_send("cim_modded_slot", target, CIM_RPC_SCHEMA, peer_id, local_player_id, slot_name, is_modded)`).
- crafting_in_modded_dev.lua:679-688 — the receiver (extracted into a named local `_rpc_cim_modded_slot` so the regression test can drive it; registration at :705 unchanged in target) now takes `schema_version` as its first wire arg (after VMF's injected `sender_peer_id`) and, on `schema_version ~= CIM_RPC_SCHEMA`, fires `_dbg_alert("[rpc:schema] cim_modded_slot mismatch …")` and returns WITHOUT mutating `_cim_modded_slot_state`.
- crafting_in_modded_dev.lua:710-711 — exposed `mod._cim_rpc_modded_slot` + `mod._cim_modded_slot_state` for the regression test.
- MOD_VERSION → 0.7.72-dev.

### Tests
- `rpc_schema_gate_drops_on_mismatch` (`/cim_regression_test`) — drives the exposed receiver synthetically: a wrong `schema_version` must leave `_cim_modded_slot_state` untouched (drop), and the correct `CIM_RPC_SCHEMA` must record the per-slot modded flag. Restores any pre-existing state entry on teardown. Fails if the schema arg or the receiver gate is removed.

### To verify
Multiplayer (needs_ingame_test): host and a client both on cim_dev v0.7.72 — equip a modded-rarity weapon on the host; the client should still see it render as "unique" chrome upgraded to "modded" exactly as before (no behavior change on matched schema). With Debug Logging on, no `[rpc:schema] cim_modded_slot mismatch` line should appear when both peers run the same build. A mismatched line appearing (different cim builds) confirms the gate now drops rather than mis-decodes.

## 0.7.71-dev (2026-06-07) — Fix: in-mission forge CTD `hero_view.lua:175: attempt to index local 'hdr_gui_data' (a nil value)`

### Why
User report (CIM, 2026-06-07): opening the crafting UI **in a map/mission** (with *Allow in mission* enabled) crashes with `[Script Error]: scripts/ui/views/hero_view/hero_view.lua:175: attempt to index local 'hdr_gui_data' (a nil value)`. Makes the in-mission forge unusable for changing properties / swapping builds mid-run.

### Root cause
Same bug class as the v0.7.13/gamepad `_setup_gamepad_gui` fix, but one level **up** on the parent `HeroView`. Vanilla `HeroView._setup_hdr_gui` (`hero_view.lua:136-165`) gates its entire body on `if self.is_in_inn then ... self._hdr_gui_data = ... end`. In a mission `is_in_inn` is false, so `_hdr_gui_data` is never built. The Athanor forge windows (`HeroWindowWeaveForgeOverview` / `Panel` / `Weapons`, `HeroWindowWeaveProperties`) call `parent:hdr_renderer()` / `hdr_top_renderer()` every draw frame, and those accessors (`hero_view.lua:183-195`) do `local hdr_data = self._hdr_gui_data.bottom` → fatal nil-index. cim's `open_forge` transition (`transition_with_fade("hero_view_force", {menu_state_name="weave_forge"})`) passes no `force_ingame_menu`, so `HeroView.on_enter` (`hero_view.lua:278`) *does* call `_setup_hdr_gui` — confirming the hook fires.

### Changed
- crafting_in_modded_dev.lua (after the `_setup_gamepad_gui` block) — three hooks on the base `HeroView` class (no prior cim hook on `HeroView`, so no duplicate-hook risk):
  1. `mod:hook("HeroView", "_setup_hdr_gui", ...)` — flips `is_in_inn=true` for the duration of the vanilla call (pcall-wrapped, flag restored) so `_hdr_gui_data` is built with real HDR renderers in mission. Cleanup is leak-safe: `HeroView.destroy_hdr_gui` (`hero_view.lua:639`) tears down whatever `_hdr_gui_data` holds regardless of `is_in_inn`.
  2. `mod:hook("HeroView", "hdr_renderer", ...)` / `hdr_top_renderer` — defensive fallback to `self.ui_renderer` / `self.ui_top_renderer` if `_hdr_gui_data` is ever still nil. Belt-and-suspenders so the forge stays usable instead of crashing.
- MOD_VERSION → 0.7.71-dev.

### Tests
- `heroview_hdr_renderer_guard_failsafe` (`/cim_regression_test`) — drives the hooked `HeroView.hdr_renderer` / `hdr_top_renderer` with a synthetic `self` that has nil `_hdr_gui_data` and asserts no raise + fallback to the view renderer. Fails if the guard is removed.

### To verify
Enable *Allow in mission*, start a map, open the crafting menu, and change a weapon's properties — it should no longer crash. Log shows `[cim:dbg] HeroView._setup_hdr_gui built in mission: _hdr_gui_data=true` when Debug Logging is on.

### Notes
- Stable `crafting_in_modded` (public) has the same latent crash — it carries the `_setup_gamepad_gui` fix but not this HDR-level one. **Candidate for promotion + release once verified in dev** (per dev/stable workflow; not auto-promoted).

## 0.7.70-dev (2026-06-05) — Fix: Trollhammer Torpedo ("torpedo cannon") crashes the forge stat editor

**Symptom (user 2026-06-05):** the torpedo cannon for the dwarf (Bardin's **Trollhammer Torpedo**, `dr_deus_01`) crashes the game when you open it to change its stats. The crash left **no Lua traceback in any console log** — the tell for a hard engine-level CTD rather than a caught script error.

**Root cause:** opening a weapon's stat editor (and the forge overview/weapon-list views) spawns that weapon's spinning 3D model through vanilla `LootItemUnitPreviewer`. Two of its spawn sites run with no Lua guard:
1. `_spawn_link_unit` → `World.spawn_unit(world, <skin.display_unit>)` in the previewer's `init`, **before any package load** — it assumes the display unit is already resident (weave weapons live in the `ui_loot_preview` global package).
2. `_load_item_units` → `load_package("<hand_unit>_3p")` → `Managers.package:load(...)`, which fatals on a non-existent package.

The Trollhammer Torpedo is a Chaos Wastes ("morris"/deus) weapon that is **never shown in the vanilla weave forge**, so its display unit (`display_trollhammer`) and held 3P unit (`wpn_dr_deus_01_3p`) live in the CW bundle and are absent from the forge preview package set. cim's Athanor forge re-exposes the weapon for adventure crafting, so spawning its preview hits those absent units → access-violation CTD with no traceback.

**Fix:** before either spawn site runs, check resource availability exactly the way vanilla's `pickup_system.lua:882-899` does — `Application.can_get("unit", display_unit)` for the resident display unit, `Application.can_get("package", "<unit>_3p")` for the load-packaged 3P units. If anything the previewer would touch is unavailable, skip the spawn (nil link / empty spawn list). `spawn_units()` already no-ops on a nil link unit, so the previewer object stays valid and **the stat editor works fully — only the spinning 3D model is omitted for that one weapon.** Guard is gated on `_custom_forge_active` (non-forge previewers — loot reveal, store, hero inventory — are untouched) and defaults to "skip preview" on any resolution error; a missing cosmetic preview always beats a crash. A one-time `mod:info` line names any weapon whose preview is skipped, so the (now non-crashing) case is still diagnosable.

Implemented as two hooks on the `LootItemUnitPreviewer` chokepoint (covers all three forge windows — overview / weapons / properties — in one place; no duplicate-hook risk, the only prior cim previewer hook is on `HeroWindowWeaveProperties._create_unit_previewer`).

**Tests:** `forge_preview_guard_present` (the guard is wired and fails safe — nil / unknown item → UNSAFE, so garbage can never reach the engine spawn) and `forge_preview_guard_allows_loaded_weapon` (a normal equipped melee weapon is NOT flagged unsafe inside the forge, so previews aren't stripped wholesale).

**To verify:** equip/select the Trollhammer Torpedo on Bardin and open its stat editor — it should no longer crash; you can roll properties/traits as normal (the weapon just won't show its 3D model). Other weapons keep their spinning preview. The log will show `[cim] forge 3D preview skipped for 'dr_deus_01' …`.

## 0.7.69-dev (2026-05-30) — Pre-promotion hardening

Issue #22 confirmed working in-game (frame + hat + outfit + every weapon slot on Grail Knight persisted through a restart). Hardening pass before promoting to the public mod, from a full review of the v0.7.62–v0.7.68 changes (no critical bugs found):

- **`_restore_modded_loadout` invariant hardened.** The `items:get_item_from_id` lookup inside the `_restoring = true` bracket is now pcall-guarded. Previously a throw there (LA-clone drift, a stale standard-forge template-cache hit, a malformed mirror entry) would propagate out before `_restoring` was reset to false — silently disabling the equip-capture hook for the rest of the session. Added an explicit INVARIANT comment so future edits don't reintroduce an un-pcall'd throw in the bracket.

Reviewed-and-accepted (no change): the BackendUtils + BackendInterfaceItemPlayfab double-capture is idempotent (no corruption; the redundant `_modded_loadout_save` only occurs for non-LA users and is negligible); slot routing in `_reequip_live_avatar` is complete (cosmetics correctly excluded); the accessory panel draw path is fully pcall-fenced; no intra-cim duplicate hooks; the global `mechanisms` clear is a deliberate, documented one-way session mutation safe for the modded-realm craft flow.

## 0.7.68-dev (2026-05-30) — Issue #22, the REAL cause: LA hides menu equips from cim's capture

v0.7.67 didn't work, and the log showed why: after equipping every slot on es_mercenary, **cim captured ZERO equips** — the only `equip_event` lines were restore's own writes. Two bugs:

**1. Menu equips were never captured (root cause).** With Loremaster's Armoury active, the keep equip path is `HeroViewStateOverview._set_loadout_item` → `BackendUtils.set_loadout_item` → `get_loadout_interface_by_slot(slot):set_loadout_item`, and that inner interface is an **LA clone**, not the `BackendInterfaceItemPlayfab` class cim hooked. So cim's capture hook never fired for the player's actual equips — `_modded_loadout` stayed frozen at 3 ancient Bardin entries, and restore had nothing new to bring back. This is the documented "BackendUtils dispatch / LA bridge" caveat (CLAUDE.md Hooking section). **Fix:** also hook the stable OUTER entry point `BackendUtils.set_loadout_item` (a plain table → TABLE-form `mod:hook` with a nil guard, installed deferred from `mod.update` once the backend/LA bridge are up — the same timing cosmetics_tweaker uses for its own BackendUtils.set_loadout_item hook). Now every menu equip is captured before the LA dispatch.

**2. v0.7.67's re-equip was self-defeating.** Restore's own `set_loadout_item` writes fired cim's capture hook, which set `_reequipped`, which then made `_reequip_live_avatar` think each slot was already done → it skipped (that's why `[reequip]` was empty). **Fix:** a `_restoring` guard — the capture path is fully skipped while restore replays saved state, so restore writes no longer (a) re-process into `_modded_loadout` (which also avoids mutating it mid-`pairs()` iteration) nor (b) pre-mark `_reequipped`. The dedup map is now synced only by genuine live equips (the `BackendUtils` path, `from_live_equip=true`) and by `_reequip_live_avatar` itself.

Capture is centralized in one `_capture_loadout_equip(career, slot, item_id, from_live_equip)` shared by both hooks. The equip probe now resolves its item/read-back via `get_interface("items")` so it works on the self-less BackendUtils path too.

**Test:** `backendutils_capture_installed` — state-witness that the BackendUtils capture actually installed (so menu equips are being recorded).

**To verify:** equip modded weapons in your slots — you should now see `[equip_event] … is_modded_bid=true` lines AND `[cim] BackendUtils.set_loadout_item capture installed` in the log. Restart; they should be equipped, with `[reequip] live avatar …` lines confirming the visual re-equip.

## 0.7.67-dev (2026-05-30) — Issue #22: re-equip last-equipped modded items on game load

**Symptom:** modded weapons you had equipped weren't on your character after a restart. **Confirmed from the log (NOT a data bug):** restore writes the loadout correctly — `[restore] total=3 restored=3 missing=0 errored=0`, every `set_loadout_item` succeeds with read-back `matches=true`. The first restore attempts at boot are `skipped — items backend interface not ready`; restore only succeeds ~16s in — **after the keep character/inventory already spawned holding the pre-restore weapons.** Writing the loadout *data* doesn't re-equip an already-spawned unit (avatar-spawn race).

**Fix:** `_reequip_live_avatar()` — after the restore data write, re-equip the live keep avatar for the current career, replicating vanilla's own equip path (`HeroViewStateOverview` `_equip_request` consumer, `hero_view_state_overview.lua:707-715`):
- melee/ranged → `inventory_extension:create_equipment_in_slot(slot_name, backend_id)`
- trinket/ring/necklace → `attachment_extension:create_attachment_in_slot(slot_name, backend_id)`

This is the sanctioned mechanism (exactly what equipping in the menu does), and is NOT the issue-#12 risk — that was craft-time divergence; here we make the live unit MATCH already-correct data. Fully pcall-guarded and gated to: network game ready, a living local `player_unit` (i.e. in the keep), current career only (other careers re-read from data when next spawned). A per-`career/slot/bid` dedup map (`_reequipped`) prevents the repeated deferred restore passes (1.0s + 3.0s) from re-spawning the same weapon unit (flicker); the equip-capture hook keeps that map in sync on manual equips. `/cim_restore_loadout` now also re-equips the live avatar.

**Test:** `reequip_live_api_ok` — state-witness that captures any error from the live-unit re-equip API (`_cim_reequip_last_err`), so a future signature drift or bad-timing call surfaces from a log instead of silently breaking.

**Also:** standard-forge per-slot accessory buttons disabled (`_STD_FORGE_BTNS_ENABLED = false`) — the standard forge is a select-template-then-craft flow and doesn't need them; jewelry crafting lives on the Athanor accessories view (user, 2026-05-30).

## 0.7.66-dev (2026-05-30) — Accessory panel: tests + hardening + recipe doc

Confirmed working in-game (v0.7.65). This build adds the guardrails:

- **Hardening (`_accessory_craft_panel.lua`):** build failures now log ONCE instead of per-frame (a missing UI global could otherwise spam the log every frame); click dispatch only fires when a callback is wired (always consumes `on_release` so a stray click can't queue); exposed `NUM_BUTTONS` / `BUTTONS` for introspection. Draw pass was already fully pcall-guarded.
- **Regression tests:** `accessory_panel_module_loaded` (module loaded, exposes `draw()`, NUM_BUTTONS == 3, the 3 slot mappings necklace/charm(ring)/trinket_1 are present and unique) and `accessory_panel_built_when_accessories_opened` (state-witness: once the accessories view drew, the lazy build produced exactly NUM_BUTTONS widgets).
- **Documentation:** repo `VMF_RECIPES.md` §13 "Custom buttons / panels in a hero-view menu — use an own-scenegraph overlay" — the wrong way (create_default_button on a host viewport node → black box / corner / overlapping hotspots), the right way (own scenegraph + hand-rolled widgets + own draw pass off the host `_draw` hook), with both canonical examples (`_glow_picker.lua`, `_accessory_craft_panel.lua`) and the burn history. Memory: `reference_vt2_menu_button_overlay_pattern.md`.

## 0.7.65-dev (2026-05-30) — Accessory craft buttons, done right (own-scenegraph overlay)

Three failed attempts (overview + amulet inline buttons) all shared one root mistake: injecting `UIWidgets.create_default_button` widgets into a host window's draw arrays, anchored to the full-size center "viewport" scenegraph node. That gave a screen-covering black box (default button background stretched to fill the giant node), bottom-left corner placement, and overlapping hotspots (one click crafted two slots).

The fix is the pattern cosmetics_tweaker's `_glow_picker.lua` already proved in-game: a **self-contained overlay with its own scenegraph and hand-rolled widgets**. New module `_accessory_craft_panel.lua`:
- Its **own scenegraph** — each of the 3 buttons is a node with an EXPLICIT `position`/`size`/`alignment` (left side, vertically centred). Repositioning is now a reliable 2-number edit, not a guess against an opaque node.
- **Hand-rolled** button widgets (hotspot + sized rect + border + text) — the background is the button's size, not the node's, so no black box.
- Its **own draw pass** (`begin_pass` on our scenegraph → `draw_widget` → `end_pass`) hooked off `HeroWindowWeaveProperties._draw` (hook_safe; grep-verified as the only cim hook on that method), only in the accessories/amulet view.
- **Per-button hotspot reads** on non-overlapping nodes → no double-fire. Hover brightens the button.

Clicking a button routes to `mod._cim_amulet_craft_one_slot(properties_win, idx, slot)` — the same craft helper as before. The vanilla "Craft All" control stays for now (additive overlay; once the 3 buttons are confirmed in-game, Craft All can be hidden). The old inline-button code paths remain gated off (`_OVERVIEW_BTNS_ENABLED` / `_AMULET_BTNS_ENABLED` = false).

## 0.7.64-dev (2026-05-30) — Disable accessory buttons (covered the grid); restore "Craft All"

v0.7.63 made the accessory buttons draw, but anchored to the full-size center/bottom `"viewport"` node they: (1) landed in the bottom-left corner, (2) rendered a screen-covering black box over the property/trait grid, and (3) had overlapping hotspots — one click fired two slots (a single press produced both a trinket and a charm). Same failure class as the overview buttons; blind pixel-anchoring to these viewport nodes does not work.

**This build:** gated the 3 accessory buttons behind `_AMULET_BTNS_ENABLED = false`. In amulet mode the vanilla **"Craft All"** control is restored (relabeled "CRAFT ACCESSORIES", routes through the existing `_upgrade_magic_level` craft hook) and the 3D model is no longer force-hidden — so the accessories view is fully usable again (grid visible, no black box). The render-array fix stays in the code; the buttons will be re-placed correctly against a real screenshot (proper small anchor node + non-overlapping hotspots) before re-enabling.

The v0.7.62 weapons fix (clear `mechanisms` on crafted Versus items) remains active and confirmed.

## 0.7.63-dev (2026-05-29) — Accessory craft buttons: render-array fix (HeroWindowWeaveProperties)

The accessory craft buttons (`_ensure_amulet_buttons`, shown in the amulet/accessories view via `_forge_apply_ui_polish`'s `in_amulet_mode` branch) had the SAME bug as the overview buttons: they appended to `properties_win._widgets`, but HeroWindowWeaveProperties has no `_widgets` — its `_draw` iterates `_top_widgets`/`_bottom_widgets`/`_top_hdr_widgets`/`_bottom_hdr_widgets`. So they were created into a collection the window never drew and NEVER rendered — which is why there were "no buttons to craft jewelry."

**Fix:** append to `_top_widgets`, resolve the scenegraph from `_ui_scenegraph`, anchor to the valid center `"viewport"` node (where the 3D amulet renders, hidden in amulet mode), fall back to `"window"`. The render fix is certain; final on-screen position may need a one-line offset tweak against a screenshot (the overview taught us not to trust blind pixel math on these full-size center/bottom viewport nodes).

The v0.7.62 weapons fix (clear `mechanisms` on crafted Versus items) is **confirmed working** by the `[filtered_items]` probe: crafted `es_bastard_sword` is PRESENT in the melee grid, `es_blunderbuss` PRESENT in the ranged grid.

## 0.7.62-dev (2026-05-29) — ROOT CAUSE of "crafted but not in inventory": Versus-scoped (`mechanisms`) items

**The 5-day bug, solved at the source.** The weapons that vanished are vanilla **Versus carousel** items — `vs_es_bastard_sword` ("Gallant's Blade"), `vs_es_blunderbuss` ("Soldier's Coach Gun"), etc. The `vs_` prefix is *Versus*, not "variant". Their `ItemMasterList` entries (`item_master_list_carousel.lua`) carry `mechanisms = { "versus" }`. The Adventure inventory grid filters every item through `available_in_mechanism_adventure` (`backend_interface_common.lua:524`):

```lua
return is_cosmetic or not mechanisms or table.contains(mechanisms, "adventure")
```

A `{"versus"}` item has `mechanisms ≠ nil` and no `"adventure"` → **rejected from the Adventure grid**. So the craft genuinely succeeded (item in the mirror, `can_wield` ok, `found_in_all=true`), but the Adventure keep grid hid it by game mode. cim's weapon list offered these because they have Kruber `can_wield` and the player owns the Lake DLC, but they were never Adventure-equippable.

**Why it took 5 days:** every prior probe checked `get_all_backend_items` (the broad backend list) and reported `found_in_all=true` — but the grid populates from `get_filtered_items` → `filter_items`, which runs the mechanism/career filter. The probes measured the wrong layer and kept falsely confirming success.

**Fix:** `_ensure_item_adventure_visible(item_key, career_name)` (was `_ensure_item_wieldable`), called from `_athanor_inject_item`, now (1) appends the crafting career to `can_wield` as before, and (2) **clears any non-adventure `mechanisms`** on the crafted item's master entry so `not mechanisms` is true and it passes the Adventure filter. It deliberately leaves `required_dlc` intact — that's the paid-DLC paywall, and cim's weapon list already restricts the player to DLC they own. Because the boot-time `_athanor_inject_all` re-runs this for every saved craft, **already-crafted Versus weapons become visible after the next restart** — no re-craft needed. Mutates `ItemMasterList` directly per repo rule (`BackendUtils.can_wield_item` isn't hookable from a Workshop mod).

**Confirmation probe (kept):** `_cim_autodump_filtered_items` inside the `get_filtered_items` hook logs, per crafted bid, whether it survived the grid filter; if absent it now dumps `slot_type` / `item_type` / `rarity` / `can_wield` / `mechanisms` / `required_dlc`. So the next run verifies the fix landed (and would reveal any other gate). Recent crafts tracked via `mod._cim_note_craft_bid`.

**Regression test:** `adventure_visible_stamp_and_mechanism_clear` — asserts can_wield append is idempotent AND a `{"versus"}` mechanisms field is cleared.

**Also confirmed from the log (NOT a bug):** stamina is correctly capped at 2 (`weave_stamina` wrote only slots 1,2). The "can't add a 3rd property" was `MAX_DISTINCT_PROPERTIES = 2` (stamina + attack_speed = 2 distinct; block_cost was the rejected 3rd) — a vanilla adventure-item constraint. See the separate >2-properties feature work for lifting it (user wants parity with the Athanor/weave system, which supports more).

## 0.7.61-dev (2026-05-29) — Disable overview jewelry buttons (they obscured the B-menu)

v0.7.60's render-array fix made the 3 overview jewelry buttons actually draw — confirmed in the log (`created 3 jewelry craft buttons (anchor=viewport_2)`). But they render on top of the overview's weapon-type selectors (viewport_1/2/3 = primary / accessories / secondary), landing in a corner over the real UI, so the B-menu showed "nothing but two buttons in the corner." Root issue: `viewport_2` is a near-fullscreen center/bottom node — a bad anchor for fixed-size buttons, and the original "Craft All" button the user wanted to match was top-right (532×126), not where the amulet 3D display sat.

**This build:** gated the overview buttons behind `_OVERVIEW_BTNS_ENABLED = false` so the B-menu is fully usable again (weapon-type selection restored). The render-array fix, scenegraph constant, and regression tests stay in place. Placement will be redone against an actual screenshot of the live cim overview — no more blind pixel guesses — then re-enabled.

Everything from v0.7.60 (craft-visibility 3-way coverage: dirtify + `_refresh` + `can_wield` stamp; saveweapon dirtify; pcall guards; career nil-guard) remains active.

## 0.7.60-dev (2026-05-29) — Overview jewelry buttons never rendered + "weapon missing after craft" covered all 3 ways

**"Crafted & saved but the weapon isn't there" — covered defensively, not diagnostically.** User confirmed the symptom is the green *"Crafted & saved"* message firing while the weapon is absent from inventory. That message only prints AFTER a successful `_athanor_inject_item`, so the item IS in the mirror — the gap is mirror → inventory grid. There are exactly three ways a crafted weapon can be missing, and this build firmly closes all three rather than waiting to diagnose which one bit:

1. **Inject failed (item never reached the mirror).** Already covered: inject is pcall-guarded and prints `[cim] Craft failed: <reason>`. Crucially, *"Crafted & saved" is proof of success* — if you see it, the item is in the mirror and the cause is #2 or #3.
2. **Item in mirror, inventory grid serving a stale cached filtered list.** The grid caches its filtered item list and only rebuilds when the interface is marked dirty — so even re-opening inventory served the stale list. Fixed two ways (belt + suspenders): `Managers.backend:dirtify_interfaces()` (from v0.7.59, now at all 5 inject sites + saveweapon import) **and** an explicit `items_iface:_refresh()` immediately after, so an already-open grid rebuilds now instead of on its own next tick.
3. **Item in mirror + wieldable-by-list, but the grid filters it by `can_wield` for the current career.** Structurally near-impossible on the Athanor (the weapon list only offers weapons the current career can already wield), but closed anyway: `_athanor_inject_item` now stamps the crafting career into `ItemMasterList[key].can_wield` (additive + idempotent — only ever appends) before the item enters the mirror. This guarantees visibility even if weapon_tweaker added the cross-career access *after* the craft, or the user later turns that wt toggle off. Per repo rule, `can_wield` is mutated directly (`BackendUtils.can_wield_item` isn't hookable from a Workshop mod). The crafting career is threaded through `weapon_data.career_name` from both `_equip_item` (weapons) and `_cim_amulet_craft_one_slot` (jewelry).

The existing `Post-craft career-gate FAIL` / `Post-craft visibility FAIL` warnings (player-visible via `mod:warning`, fire under debug logging) remain as a live tripwire if any future path slips past all three.

---

### Overview jewelry buttons never rendered (wrong draw array) + pre-stable hardening

**THE overview-button bug, root-caused.** v0.7.57/.58 added 3 jewelry-craft buttons to the Athanor B-menu overview and they still didn't appear. v0.7.58 fixed the *timing* (driver moved into `_forge_apply_ui_polish`) but the buttons still never drew. Reason, confirmed against vanilla source:

`HeroWindowWeaveForgeOverview` has **no `self._widgets` array**. Its `_draw` (hero_window_weave_forge_overview.lua:704–770) iterates four separate hardcoded arrays — `_bottom_hdr_widgets`, `_top_hdr_widgets`, `_top_widgets`, `_bottom_widgets` — plus `_viewports_data`. The button code appended to `overview._widgets` (nil on this class) and the window never iterated it, so the buttons were created (or not) into a collection that is never rendered. Two secondary bugs compounded it: the code read `overview.ui_scenegraph` but vanilla stores it as `overview._ui_scenegraph`, and the fallback anchor `"viewport"` is not a real scenegraph id (the real ones are `viewport_1/2/3`).

**Fix:** append the buttons to `_top_widgets` (drawn on the `ui_top_renderer` pass, above the viewport art, still input-serviced so the hotspot fires), resolve the scenegraph from `_ui_scenegraph`, anchor to the valid `viewport_2`, fall back to root `"window"`. `_forge_hide_widget`/`_forge_get_widget` already worked because they go through `_widgets_by_name`, which DOES exist — that's why hiding the upgrade button succeeded while our appended buttons stayed invisible.

`_widgets` vs `_top_widgets`/`_bottom_widgets` (no unified array) confirmed by reading vanilla `_draw`. `HeroWindowCrafting` (standard forge) DOES draw from `self._widgets`, so the standard-forge buttons were never affected — only the overview ones.

**Regression guards added:**
- `overview_btn_render_target` — pins `_OVERVIEW_BTN_RENDER_FIELD` to the valid drawn-array set so an edit can't silently point it back at `_widgets`.
- `overview_btns_created_when_forge_opened` — state-witness: if the weave forge overview was opened this session, asserts all 3 buttons were created (skips if forge never opened).

**Pre-stable hardening (from a 3-agent audit toward a stable promotion):**
- **saveweapon import missing `dirtify_interfaces`** — `/cim_import_saved_weapons` injects via its own `mirror:add_item` (NOT `_athanor_inject_item`), so it never inherited the v0.7.59 fix. Imported weapons could stay invisible until a menu re-open. Added the guarded `dirtify_interfaces()` call after the import loop.
- **pcall-guarded the two standard-forge `dirtify_interfaces` calls** (`_craft_via_synth` + the craft hook) for parity with the Athanor path's guarded call.
- **`_setup_weapon_list` career nil-guard** — `CareerSettings[career_name]` was dereferenced raw inside a full `mod:hook` wrapper; an unknown/nil career would error and break the weapon-list render instead of falling back to vanilla. Now nil-checked with a vanilla fallback.
- **Doc fix:** the `_athanor_inject_item` comment said "4 callers"; there are 5 (`_athanor_retry_pending`, `_athanor_inject_all`, `_equip_item`, `_cim_amulet_craft_one_slot`, `_upgrade_magic_level`). Corrected.

**Investigated, NOT shipped (needs an in-game data point first — deliberately not touching live units blind):**
- **Issue #22 (last-equipped modded items not re-equipped on restart):** root cause is an avatar-spawn race, not late-overwrite — cim writes the loadout *data* layer (`set_loadout_item`, read-back proven `matches=true`) but never re-equips the already-spawned keep avatar (vanilla's two-step is data-write + unit re-wield via `_equip_request`; cim only does step 1). The fix is a live-unit re-equip, but cim deliberately avoids live-equip at craft time (issue #12: icon/unit divergence), so this needs in-game validation before shipping into stable. Tracked separately from the craft-visibility work above.

**Touched files:** `crafting_in_modded_dev.lua` (overview button render-array fix, render-target constant + 2 regression tests, career nil-guard, `_ensure_item_wieldable` can_wield stamp + redundant `_refresh` in `_athanor_inject_item`, career threaded through `_equip_item` + `_cim_amulet_craft_one_slot`, inject-caller doc fix, version bump), `standard_forge.lua` (pcall-guard 2 dirtify calls), `saveweapon_import.lua` (dirtify after import), `CHANGELOG.md`.

## 0.7.59-dev (2026-05-28) — Athanor crafts: missing `dirtify_interfaces` (THE bug)

**Symptom (user-reported repeatedly):** "I crafted a blunderbuss / bret sword / halberd but it doesn't exist in inventory." Every cim probe — `craft_synth_result`, `craft_visibility`, `mirror_write`, `in_forged_weapons`, `is_modded_bid` — said the item was in the mirror and visible (`found_in_all=true`, `visible_to_career=true`). The data was right. The user was right too. The inventory was just showing **cached pre-craft state**.

**Root cause:** `_athanor_inject_item` (the Athanor + jewelry craft path) calls `backend_mirror:add_item(bid, item)` to put the new item into the mirror's underlying table — but never bumps the backend interface dirty flag. The inventory grid's `get_filtered_items` queries the interface, which serves cached data until `Managers.backend:dirtify_interfaces()` is called.

`standard_forge.lua`'s craft hook does the call at line 1125 (`Managers.backend:dirtify_interfaces()`). The Athanor path was missing it.

**Fix:** added the `dirtify_interfaces()` call inside `_athanor_inject_item` itself, after the `mirror:add_item` succeeds. This covers all 4 call sites in one place:

1. `_equip_item` hook — Athanor weapon craft (the path user has been hitting)
2. `_cim_amulet_craft_one_slot` — properties-view jewelry craft + new overview-button jewelry craft (overview buttons route through `mod._cim_craft_via_synth` which already dirtifies via standard_forge's craft hook — but the properties-view path was hitting this)
3. `_athanor_retry_pending` — deferred re-inject on level transition (also benefits)
4. `_athanor_inject_all` — boot-time restore of all saved crafts (idempotent, harmless to dirtify during boot before any UI is open)

**Two-day debug chase ending here.** The probes weren't lying. The synth was running. The mirror had the items. The UI just wasn't being told to refresh. I should have noticed earlier when the `craft_visibility` check kept showing `found_in_all=true` while the user kept saying the items weren't there — that's the exact "data is correct, UI is stale" pattern. Lesson: when probe says `found_in_all=true` AND user says "no item", the gap is between mirror and UI render, not between synth and mirror.

**Touched files:** `crafting_in_modded_dev.lua` (`dirtify_interfaces()` call inside `_athanor_inject_item` + version bump), `CHANGELOG.md`.

## 0.7.58-dev (2026-05-28) — Fix Athanor overview button creation timing

User report "nothing changed". v0.7.57-dev log (`console-2026-05-28-22.09.19-...log`) shows the overview button creation skipped EVERY FRAME with `[cim] overview jewelry buttons skipped: overview has no _widgets / _widgets_by_name yet` (13 hits across the session). My v0.7.57 hook on `HeroWindowWeaveForgeOverview.update` fires before vanilla populates the overview's widget tables — so the buttons never got created.

The existing `_forge_apply_ui_polish` works because it's called from `HeroViewStateWeaveForge.update` — the PARENT state's update tick — which only fires after all child windows have completed their `on_enter` (including widget creation). Proof in the log: `_forge_hide_widget(overview, "upgrade_button")` etc. succeed in the same code path.

**Fix:** moved the per-frame `_ensure_overview_jewelry_buttons` / `_show_overview_jewelry_buttons` / `_handle_overview_jewelry_button_clicks` calls into `_forge_apply_ui_polish`'s existing `if overview then ...` block. Removed the failed standalone hook on the overview's own `update`.

This is the timing-pattern bug I keep re-discovering: child-window `update` hooks fire before child-window widgets are populated; parent-state hooks fire after. Save the lesson next to the dev-branch and deploy-doesn't-build rules.

**Touched files:** `crafting_in_modded_dev.lua` (relocate button-driver calls + version bump), `CHANGELOG.md`.

## 0.7.57-dev (2026-05-28) — Athanor overview jewelry craft buttons

User request 2026-05-28: put 3 jewelry-craft buttons on the B-menu Athanor **overview** page (the landing window — `HeroWindowWeaveForgeOverview`), in the space where the Amulet of Ashur 3D display used to render. Each button crafts ONE accessory of the chosen slot directly, no need to navigate into the property editor first.

This is sibling to the existing per-slot buttons in `HeroWindowWeaveProperties` (the properties editor view) — those still fire there. The new overview buttons are a shortcut from the Athanor landing page.

### Cross-module API: `mod._cim_craft_via_synth`

`standard_forge.lua` — exposed the previously-local `_craft_via_synth(slot_filter, friendly_label)` as `mod._cim_craft_via_synth`. Same code path the standard-forge accessory buttons and `/cim_craft_necklace` / `/cim_craft_charm` / `/cim_craft_trinket` chat commands use.

### Overview buttons

`crafting_in_modded_dev.lua` — new `_OVERVIEW_JEWELRY_BUTTONS` table, `_ensure_overview_jewelry_buttons` create helper, `_show_overview_jewelry_buttons` toggle helper, `_handle_overview_jewelry_button_clicks` click consumer, and a `HeroWindowWeaveForgeOverview.update` hook that lazy-builds + shows + handles clicks every frame the modded forge is active. Same pattern as the existing `_AMULET_SLOT_BUTTONS` in the properties view and `_STANDARD_FORGE_BUTTONS` in the regular forge.

- 452x80 button size (matches the properties-view buttons; roughly matches the original "Craft All" upgrade_button this build no longer renders)
- Vertically stacked, 95 px center-to-center spacing
- Anchor: `viewport_2` (the center accessories viewport) if the scenegraph has it, fallback to `viewport` (same anchor the properties-view buttons use)
- Visible only when `_custom_forge_active = true`
- Diagnostic log line on first create: `[cim] athanor overview: created 3 jewelry craft buttons (anchor=X, size=452x80)`. If the create fails, separate `mod:info` lines report which dependency was missing (UIWidgets, `_widgets`, etc.)

### What to verify in the next session

1. Boot banner: `[cim:LOAD] v0.7.57-dev`
2. Press B → Athanor overview opens → look for `[cim] athanor overview: created 3 jewelry craft buttons` in the log
3. Verify all 3 buttons render where you wanted them (center of the overview where the Amulet of Ashur display was)
4. Click each button once — verify the `[cim] Crafted <slot>.` echo fires and the item appears in inventory
5. If buttons are misplaced or wrong size, tell me which anchor + dimensions you want — I'll adjust

**Touched files:** `crafting_in_modded_dev.lua` (overview button machinery + version bump), `standard_forge.lua` (expose `mod._cim_craft_via_synth`), `CHANGELOG.md`.

## 0.7.56-dev (2026-05-28) — Widget-list dump for inventory + forge-inventory windows

User stated the disabled search bar is a native vanilla feature. Static grep of `Vermintide-2-Source-Code/` found ZERO text-input / search widgets in `HeroWindowLoadoutInventory`, `HeroWindowInventory`, or `HeroWindowCrafting` (only `HeroWindowCraftingInventoryConsole` has one, console gamepad path). Workshop bundle scans turned up nothing matching `search_input`/`filter_input`/etc. either, but VT2's bundle format hashes string identifiers so a raw ASCII grep doesn't catch obfuscated references.

Conclusion: my decompiled-source/bundle-grep approach has hit its limit. Switching to in-game widget tree dump.

### `_cim_autodump_full_widget_list` probe

New helper in `cim_debug.lua`. On entry to a window, walks `self._widgets_by_name` and logs every widget's name + first 12 content-table keys. Flags interactive widgets (`button_hotspot`) with their disabled/visible state. Flags text-input-like widgets (any `caret_position` / `input_text` / `text` / `text_field` field on content) with `[TEXT-LIKE]`. One-shot per window-open. Gated on `enable_debug_logging`.

Wired into two windows:
- **`HeroWindowLoadoutInventory.on_enter`** — already had a hook (modded_rarities.lua's category-display-name mutation + jewelry probe). Added the full-widget-list call.
- **`HeroWindowInventory.on_enter`** — no existing cim hook; added one, conditionally on the class being loaded at file-load time. Same single-callback-per-Class.method discipline as the rehook-warning regression test enforces.

Next session's log will contain two `[widget_list/...]` dumps (one per window), one line per widget. Whatever's drawing the disabled search bar should appear with a `[TEXT-LIKE]` flag — name + content key list tells us exactly which widget to hook + how to enable.

**Touched files:** `cim_debug.lua` (new probe), `modded_rarities.lua` (probe call wired to existing HeroWindowLoadoutInventory hook + new HeroWindowInventory hook), `crafting_in_modded_dev.lua` (version bump), `CHANGELOG.md`.

## 0.7.55-dev (2026-05-27) — Stamina slot-accounting fix + standard-forge button diagnostics

User report 2026-05-27 EOD: "2 stamina still takes 5 slots even though it should only take 2 on weapons" — clarified as "Stamina looks fine. It only has 2 bubbles, the problem is WHEN APPLIED IT TAKES 5". So the visible bubble count is correct (2), but the underlying `props.weave_stamina` array is being written with 5 slot_indices, which the inventory render treats as "5 of 10 slots used by stamina" → blocks a second property from being added even though the distinct-property cap would allow it.

### Stamina/movespeed slot-array cap (issue #49 take 2)

Root cause: vanilla's property picker calls `set_loadout_property(career, "weave_stamina", slot_index)` once per slot_index when the user selects stamina. cim's v0.7.44 fix removed the per-click REJECTION so the visible bubble grid renders correctly (2 filled, because `_value_for_bubbles("stamina", 5)` clamps to 1.0 = +2 tier), but every one of vanilla's 5 calls now appends to `props.weave_stamina` — array grows to length 5 → inventory sees 5 slots used.

Fix at `crafting_in_modded_dev.lua:~2486`: silently cap `props[property_key]` length at `_bubble_cap(property_key)`. Visible bubble count is unchanged (still 2 for stamina, 1 for default-mode movespeed); only the persisted array stops at the engine cap, freeing the remaining slot_indices for a second property.

```lua
-- v0.7.55-dev replacement:
local cap = _bubble_cap and _bubble_cap(property_key) or 5
local cur_len = #props[property_key]
if cur_len < cap then
    props[property_key][cur_len + 1] = slot_index
end
```

**Existing crafted items** with over-capped arrays still take 5 slots until re-rolled or reapplied. Next session's `[trim]` log will likely show no auto-trim for this since cim's existing trim is for the >2-distinct cap, not per-property array length. A migration to retroactively trim `props.<key>` to cap-length is on the followup list if user wants — but applying the property again on a fresh item works around it.

### Standard-forge button diagnostics

User report: "There are no buttons to craft jewelry now" on the standard forge. The CRAFT NECKLACE / CRAFT CHARM / CRAFT TRINKET buttons in `standard_forge.lua:1231-1235` and the `_ensure_std_forge_buttons` create path should fire from the `HeroWindowCrafting.update` hook every frame the forge is active. No "standard forge: created N cim accessory craft buttons" line in any recent log — but user also hasn't opened the standard forge in any debug-logged session this week.

Added once-per-window-session diagnostic lines to `_ensure_std_forge_buttons` reporting why creation skipped:
- `UIWidgets/UIWidget/create_default_button` missing on the global
- `crafting_win._widgets` or `_widgets_by_name` not ready yet (vanilla on_enter ordering issue)

When user opens the standard forge in v0.7.55-dev with debug logging on, the log will show exactly which dependency is blocking creation (or a "creating now" line if everything's ready).

### Search-bar investigation (deferred)

User asks to enable the vanilla disabled search bar on the regular forge. Dispatched a parallel subagent to map every widget in `HeroWindowCrafting`'s definitions and identify whether the search is a hidden widget to un-hide, a wired-but-unconnected widget, or needs a new cim-injected widget. Implementation lands in a follow-up build once the agent reports.

### Other reported issues queued (no code change this build)

- **#22 equip/restore** — v0.7.54-dev probes already deployed; awaiting fresh log
- **Halberd/blunderbuss won't craft on Kruber merc** — v0.7.53-dev `weapon_list_setup` probe answers next session
- **Sienna bolt staff** — same probe; need a session on Sienna with debug on

**Touched files:** `crafting_in_modded_dev.lua` (slot-cap at property-write + version bump), `standard_forge.lua` (diagnostic logging in `_ensure_std_forge_buttons`), `CHANGELOG.md`.

## 0.7.54-dev (2026-05-27) — Equip + restore-cycle probes for issue #22

User confirmed 2026-05-27 EOD: on **every** career, modded items last equipped do NOT re-equip at next game start. The `[restore] OK <career>/<slot> -> <bid>` log line says the write returned ok, but the engine clearly reads a different value on the next session boot.

Vanilla `BackendInterfaceItemPlayfab.set_loadout_item` (`backend_interface_item_playfab.lua:635-669`) writes via `self._backend_mirror:set_character_data(career, slot, item_id, ...)` and sets `self._dirty = true`. Vanilla `get_loadout_item_id` (`:512-538`) reads from `self:get_loadout()` → `base_loadouts[career_name]` → `loadout[slot_name]`. Hypotheses (need data to discriminate):

1. The mirror write succeeds, but a LATER vanilla path (e.g. `_set_inital_career_data`, `_fix_career_data`, or a PlayFab title-data refresh) overwrites the layer before the keep avatar reads it.
2. `set_character_data` writes to one slot index but `get_loadout` reads from a different one (the `optional_loadout_index` parameter — we pass `nil`).
3. The mirror write succeeds AND `get_loadout_item_id` reflects it AT THE TIME we wrote — but the keep avatar already spawned with the old weapon and doesn't re-equip on the late mirror update.

### Three new probes

**`_cim_autodump_equip_event`** — fires on every `set_loadout_item` (vanilla or modded). Logs career, slot, item_id, resolved key/rarity, `is_modded_bid`, `in_forged_weapons`, and an immediate read-back via `get_loadout_item_id`. If the read-back doesn't match the just-written item_id, emits a `mod:warning [cim:diag] Equip read-back MISMATCH` — the proof that vanilla wrote elsewhere or rejected the write.

**`_cim_autodump_restore_pass`** — dumps the FULL `_modded_loadout` table at the entry of `_restore_modded_loadout`, BEFORE the iteration runs. So we see every saved (career, slot) entry the restore should attempt — not just the ones it successfully restores. Helps detect "I equipped X on career Y but it's not in the table" cases.

**`_cim_autodump_restore_entry`** — fires after EACH `items:set_loadout_item(items, bid, career, slot)` call inside the restore loop. Immediately reads back via `get_loadout_item_id` and asserts the bid matches. If `set_ok=true` but `matches=false`, emits `mod:warning [cim:diag] Restore WRITE-NO-READ — set_loadout_item returned ok ... but get_loadout_item_id reads back X. Mirror silently rejected the write OR a different layer is being read.` That's the smoking gun for hypothesis 2.

### What the next session's log will tell us

For each restore entry, we'll see one of three outcomes:
1. `[restore_entry] career=... matches=true set_ok=true` AND user reports correct weapon in-game → restore is fine, hypothesis 3 (avatar didn't re-spawn) is the real bug. Fix would be triggering a unit re-spawn after restore, OR moving restore earlier in the boot sequence.
2. `[restore_entry] ... matches=false set_ok=true` AND `mod:warning` fires → hypothesis 2 (different layers read/write). Investigate `optional_loadout_index`, alt loadout slot, `_player_loadouts` cache.
3. `[restore_entry] ... matches=true set_ok=true` at restore time, but a LATER `equip_event` shows a different value being written by vanilla → hypothesis 1 (late vanilla overwrite). Move our restore later, or hook the wiping path.

### No code fix yet — diagnostic build only

I deliberately didn't try to "guess-fix" the issue this build. The three hypotheses have meaningfully different fix shapes; picking one without data is the failure mode that's burned this issue for 3 days. Next session's log will discriminate, then v0.7.55-dev ships the actual fix.

**Touched files:** `cim_debug.lua` (3 new probes), `crafting_in_modded_dev.lua` (probe wiring in `set_loadout_item` hook + `_restore_modded_loadout` body + version bump), `CHANGELOG.md`.

## 0.7.53-dev (2026-05-27) — Menu-state INPUT probe complement

v0.7.52-dev's craft-synth probe captures everything about crafts that DO fire — but says nothing about weapons that *should* have been in the menu but weren't. User test on Kruber mercenary (2026-05-27 21:33 log): 27 successful crafts, zero FAIL probes, every gate green for every weapon clicked. The "several didn't get created" weapons must be ones where `_equip_item` never fired — either the weapon wasn't in the Athanor list to click in the first place, or click didn't trigger the synth.

### `_cim_autodump_weapon_list_setup` probe

New helper in `cim_debug.lua`, fired from cim's `HeroWindowWeaveForgeWeapons._setup_weapon_list` hook AFTER `_populate_list` runs. Captures two views per Athanor weapons-window open:

**Section 1 — actual menu contents** (what the user can click):
```
[weapon_list_setup] career=es_mercenary slot=slot_melee slot_types=melee menu_count=27
  MENU: vs_es_halberd [Halberd] slot=melee rarity=default can_wield=[es_huntsman,es_knight,es_mercenary]
  MENU: es_2h_heavy_spear [Tuskgor Spear] slot=melee rarity=default can_wield=[wh_captain,es_questingknight,...]
  ... (one line per weapon)
```

**Section 2 — full ItemMasterList sweep** with per-rejection-reason counts:
```
  ItemMasterList sweep: total=2566 wrong_slot=1980 no_can_wield=14 not_career=480 skin=89 magic=23 promo=0 dlc_locked=8
  PASS-FILTERS-BUT-DEDUPED (3 items — same display_name as something already in menu):
    DEDUPED: vs_es_2h_sword [Greatsword] rarity=default
    DEDUPED: cwv_es_handgun_001 [Handgun] rarity=default
    ...
```

This discriminates every reason a weapon could be missing from the menu:
- `wrong_slot` — weapon's `slot_type` isn't in the slot family the user is browsing (melee vs ranged etc.)
- `no_can_wield` — weapon has no `can_wield` field at all (registration bug in source mod)
- `not_career` — `can_wield` exists but current career isn't in it (most likely cause for "weapon_tweaker toggle is on but weapon doesn't appear" — toggle didn't push the career into `can_wield`)
- `skin` — `item_type == "weapon_skin"` (cosmetic, not a craftable weapon)
- `magic` / `promo` — explicit rarity exclusion by cim
- `dlc_locked` — `_cim_item_requires_unowned_dlc(key)` returned true
- `DEDUPED` — passed all filters but shares display_name with another already in the menu (cim's dedupe rule)

When a user reports "weapon X didn't appear", the next session's log answers it directly: either X is in `MENU:` (UI/click-handler issue, not data) or X appears in one of the rejection buckets (data issue) or X appears in `DEDUPED` (cim is hiding it intentionally — review whether dedupe should be relaxed).

### Why this matters for weapon_tweaker cross-character toggles

User explicitly reports trying weapons "not native to him via weapon tweaker". `weapon_tweaker` adds careers to weapons' `can_wield` lists when toggles are enabled. If a wt toggle is ON but the weapon doesn't appear in the cim Athanor menu, two possibilities:
1. wt didn't actually push `es_mercenary` into `ItemMasterList[key].can_wield` → weapon shows in `not_career` bucket
2. wt did push the career but the weapon got deduped → weapon shows in `DEDUPED` with a display_name that matches another already-in-menu weapon

The probe distinguishes these mechanically. No more guessing.

**Touched files:** `cim_debug.lua` (new probe), `crafting_in_modded_dev.lua` (probe wired into `_setup_weapon_list` hook + version bump), `CHANGELOG.md`.

## 0.7.52-dev (2026-05-27) — Comprehensive post-craft diagnostic probe

User reports weapons not appearing after craft. v0.7.51-dev's log scan showed 9 successful `Crafted & saved: <name>` messages and zero errors — but none of those messages carried the BID, key, slot_type, rarity, or post-craft visibility state needed to diagnose whether the items are reachable through the inventory grid path. Two distinct craft routes are in cim:

- **Athanor (B-menu)** — `HeroWindowWeaveForgeWeapons._equip_item` hook (`crafting_in_modded_dev.lua:2877`). What the user has been using. Only emits a friendly `Crafted & saved: <name> [modded]` echo. No diagnostic detail.
- **Standard forge** — `BackendInterfaceCraftingPlayfab.craft` → `_make_craft_synth` (`standard_forge.lua:760+`). Already echoed `[cim] Crafted <key> (key=X rarity=Y bid=Z)` but only after a verification read — no visibility check.

### `_cim_autodump_craft_synth_result` probe

New helper in `cim_debug.lua`. Called immediately after every mirror write (both craft routes). Captures:

| Field | Source |
|---|---|
| `career`, `item_key`, `backend_id` | Inputs to the synth |
| `mirror_write: ok=… err=…` | The `pcall(mirror.add_item, …)` result |
| `in_mirror=…` | Reads `mirror._inventory_items[bid]` immediately after the write |
| `resolved: key=… slot=… rarity=…` | `items_iface:get_item_from_id(bid)` — the path inventory queries use |
| `can_wield=[…] visible_to_career=…` | Career filter pre-check |
| `is_modded_bid=…` | `mod._cim_is_modded_backend_id(bid)` — the BID heuristic that gates filter passes |
| `persisted=…` | `mod:get("forged_weapons")[bid] ~= nil` after `_forge_save` |
| `n_props, n_traits` | Counts on the input weapon_data |

### 2-frame-later visibility check

Schedules a deferred check via `mod._cim_pending_visibility_checks`. Drained from `mod.update`. Two frames after the craft, re-queries:

- `get_all_backend_items()` — broadest interface view
- `get_item_from_id(bid)` — the resolution path
- `can_wield` vs current career

Emits `[cim:diag] Post-craft visibility FAIL — bid=X (key=Y) not in backend_mirror items 2 frames after craft. Inventory will NOT show it.` as a `mod:warning` (always visible in chat) if the item is missing. Emits `Post-craft career-gate FAIL — bid=X is in mirror but can_wield does not include current career 'Z'. Switch careers to see it.` if the item is present but career-filtered out — the most likely "I crafted but I don't see it" cause.

### Failure-path probe

The failure branches in both craft routes (`_athanor_inject_item` returning nil; `pcall(mirror.add_item)` returning `not ok`) now also call the probe with `path = "<route>_FAIL"` and `mirror_write_ok = false`. So failed crafts get the same diagnostic trail as successful ones.

### `mod:echo` → `mod:warning` on the standard_forge `add_item` failure path

The mirror-write failure echo at `standard_forge.lua:844` was using `mod:echo`, chat-suppressed when `enable_debug_logging` is OFF — so silent for most users. Switched to `mod:warning` (always visible) per the v0.7.44 action-rejection rule.

### What the next session's log will tell us

After this build, a single failed craft will produce in the log:
1. `[cim-debug] [craft_synth_result/athanor_equip] career=… item_key=… bid=…` (the inputs)
2. `  mirror_write: ok=true err=nil in_mirror=true` (or false — which would prove the synth is dropping)
3. `  resolved: key=… slot=… rarity=…` (does the item resolve through the items interface?)
4. `  can_wield=[…] visible_to_career=true/false` (career filter pre-check)
5. `  is_modded_bid=true/false persisted=true/false n_props=… n_traits=…` (the filter gate + persistence)
6. 2 frames later: `[cim-debug] [craft_visibility/athanor_equip] bid=… 2-frames-post-craft: found_in_all=… visible_to_career=… is_modded_bid=… career=…`

That's enough to discriminate every failure mode listed in `reference_cim_weapon_crafting_flow.md` § 10 without further code changes.

**Touched files:** `cim_debug.lua` (new probe + visibility-check drain), `crafting_in_modded_dev.lua` (probe wiring in Athanor `_equip_item` hook + drain in `mod.update` + version bump), `standard_forge.lua` (probe wiring in `_make_craft_synth` + `add_item` failure → `mod:warning`), `CHANGELOG.md`.

**No new regression test added** for this build — the probe IS the diagnostic surface; the next user-session log either reveals the bug or proves it's not present. Once root cause is identified, a regression test can pin the specific assertion.

## 0.7.51-dev (2026-05-27) — Duplicate `hook_safe` fix + rehook-warning interceptor

Boot log scan of `console-2026-05-27-20.37.09-...log` line 983 showed `[cim_dev][WARNING] (hook_safe): Attempting to rehook active hook [on_enter]`. Two `mod:hook_safe("HeroWindowLoadoutInventory", "on_enter", ...)` registrations:

1. `modded_rarities.lua:172` — mutates `self._categories[*].display_name` to "Accessories" (issue #38 layered fix from v0.7.37).
2. `cim_debug.lua:407` — JEWELRY-label probe (v0.7.48-alpha) registered on a loop that included `HeroWindowLoadoutInventory`.

VMF silently drops one of the two. Per `feedback_vmf_hook_safe_no_chain`, sibling `hook_safe` callbacks on the same Class.method do NOT chain — only the first-registered one runs. The probe author (me, prior session) added a "DON'T duplicate" comment listing HeroWindowCrafting / HeroWindowCraftingConsole / HeroWindowItemCustomization but missed that `HeroWindowLoadoutInventory` was already taken by modded_rarities.

### Fix

- `cim_debug.lua`: removed `"HeroWindowLoadoutInventory"` from the probe loop list. Comment expanded to call out all four already-hooked Class.method pairs (the three the original author got + this one).
- `modded_rarities.lua:172`: the surviving `hook_safe` now ALSO calls `mod._cim_autodump_jewelry_probe(self, "HeroWindowLoadoutInventory")` so debug coverage of this surface is preserved.

### Rehook-warning interceptor

`crafting_in_modded_dev.lua` — installed an interceptor on `mod.warning` immediately after the `mod.echo` chat-suppression patch (before any `hook_safe` calls). Captures every warning matching `"rehook active hook"` into `mod._cim_rehook_warnings`. New regression check `no_duplicate_hook_safe_registrations` reads the list and FAILs if any rehook warning was emitted at boot.

This is the first cim regression check that observes boot-time VMF emissions — previous tests inspect post-load state but couldn't catch a hook that was silently dropped during boot.

### Pre-deploy memory correction

While preparing to ship this build I discovered VMBLauncher's `deploy` verb does NOT rebuild — it only copies existing `bundleV2/` artifacts. Every "Deployed N file(s)" message earlier in the day re-copied stale bundles. The user has been running v0.7.49-dev the entire session; none of v0.7.50-dev's work (JEWELLERY fix, craft diagnostics, regression tests) was ever actually in-game. Saved to memory `reference_vmb_launcher_deploy_no_build` so the next session never assumes `deploy` is build+deploy. v0.7.50-dev's content ships in v0.7.51-dev's first real build.

**Touched files:** `crafting_in_modded_dev.lua` (interceptor + version bump + new `_rt_register` block), `cim_debug.lua` (remove duplicate hook), `modded_rarities.lua` (call probe from surviving hook), `CHANGELOG.md`.

## 0.7.50-dev (2026-05-27) — Discriminated craft-failure diagnostics + JEWELLERY→ACCESSORIES fix + regression tests

### JEWELLERY → ACCESSORIES on Athanor overview (issue #38, FINALLY)

The "JEWELRY" label was visible on the main forge page (Athanor overview viewport_title_2). Two prior fix attempts didn't land it (v0.7.35 `Localize` override on `crafting_recipe_craft_jewellery`; v0.7.37 `HeroWindowLoadoutInventory.on_enter` `category.display_name` mutation) — both targeted *other* surfaces where the same word appears.

**Root cause (user-identified 2026-05-27 EOD):** the literal "JEWELLERY" was hardcoded by a prior session of me at `crafting_in_modded_dev.lua:1595` when I first repurposed the Athanor's amulet viewport as the unified accessories editor. The string was never a vanilla loc key on that surface — it was an authored literal in our own source. None of the prior patches could ever fix it because they were intercepting vanilla resolution paths that never ran on this widget.

**Fix:** changed the literal at line 1595 from `"JEWELLERY"` to `"ACCESSORIES"`. The two earlier-layer patches (Localize override for the standard forge recipe title; `category.display_name` mutation for the loadout inventory category header) remain in place — they cover different surfaces that DO route through vanilla and still need translation. Three layers of defense for one user-visible word.

### Discriminated craft-failure diagnostics

User report 2026-05-27: "Crafting several different ranged items, many failed, and I don't know why." Log scan of `console-2026-05-27-15.03.31-...log` shows 5 hits of the generic message `[cim] Craft button pressed without a selected recipe/template (dropped).` (lines 9670, 9951, 10287 [INFO before debug toggle], 10930, 10932 [ECHO after debug toggle]). The message lumped THREE distinct failure modes into one line, so the user — and we — couldn't tell *which* condition was actually nil.

`standard_forge.lua:1106-1118` — the single `if not recipe_override or not item_backend_ids or not item_backend_ids[1]` is now split into two checks with distinct messages:

| Mode | New message |
|---|---|
| `recipe_override` is nil | `"Craft dropped — no recipe selected (recipe_override=nil, career=X, items_len=N). Click a recipe tile (Craft Item / Salvage / Reroll / etc.) before pressing craft."` |
| `item_backend_ids` is nil or empty | `"Craft dropped — no template/item picked (recipe=X, career=Y, items_len=N). Select a weapon/template in the panel before pressing craft."` |

The two existing follow-up drops (`_get_valid_recipe` returned nil, no synth implemented) now also include `career`, `items_len`, and `first_bid`.

**`mod:warning` instead of `mod:echo` on all drops.** The drop helper used `mod:echo`, which the v0.7.38 chat-suppression patch silences into log-only when `enable_debug_logging` is OFF. That's why the user's first 3 attempts went to INFO (invisible in chat) and only the last 2 (after toggling debug on) went to ECHO. Action rejections should always reach chat per the v0.7.44-alpha rule.

**New `_cim_autodump_craft_attempt` helper** in `cim_debug.lua`. Fires at the entry of the `craft()` hook BEFORE any drop check. Gated on `enable_debug_logging`. Logs career, recipe, items_len, first 3 BIDs, plus key/slot_type/rarity for bid[1] via the items interface — tells us whether the BID is a real template or a stale reference.

### Regression tests for v0.7.44 / v0.7.47 / v0.7.33 / v0.7.50-dev fixes

Added five checks to the existing `/cim_regression_test` suite so prior fixes can't silently regress in a future edit:

| Check | Guards against | Original fix |
|---|---|---|
| `stamina_movespeed_clamp_at_overcap` | Engine-effective `_value_for_bubbles` clamp removed (would let stamina/movespeed exceed vanilla tiers via over-cap clicks). | v0.7.44-alpha — issue #49 |
| `action_rejection_uses_warning_channel` | `mod.warning` accidentally aliased to the chat-suppressed `mod.echo` (would re-hide rejection messages). | v0.7.44-alpha — issue #47 |
| `morris_hub_passes_open_forge_gate` | Blanket `mech == "deus"` block re-introduced (would re-break the CW staging-hub Athanor). State-witness: skips unless in `morris_hub`. | v0.7.47-alpha |
| `trim_logging_emits_per_item_detail` | `mod.info` channel removed / silenced (would lose per-item `[trim] <key> kept=[…] dropped=[…]` lines). | v0.7.33-alpha |
| `accessories_label_on_overview` | `crafting_recipe_craft_jewellery` Localize override reverted (would re-show "Jewellery" on the standard forge recipe title). | v0.7.50-dev — issue #38 |

Run via `/cim_regression_test` — PASS/FAIL/SKIP per check.

**Touched files:** `crafting_in_modded_dev.lua` (literal fix line 1595 + version bump + 5 new `_rt_register` blocks), `standard_forge.lua` (discriminated drops + mod:warning), `cim_debug.lua` (new craft-attempt helper), `CHANGELOG.md`.

## v0.7.49-dev — 2026-05-26

- **FORK POINT**: friends-only dev stream for in-flight cim work. Parent `crafting_in_modded/` (Workshop ID 3721038774) remains the public stable stream.
- Mod_id renamed `cim` → `cim_dev`. Scripts dir renamed `crafting_in_modded` → `crafting_in_modded_dev`. itemV2.cfg: visibility friends_only, published_id cleared.
- **Cross-mod API caveat**: external mods (CWV, cosmetics_tweaker) consume cim via `get_mod("cim")` — they continue to reference the STABLE stream by design. The dev clone is for isolated cim feature testing, not cross-mod integration.

## 0.7.48-alpha (2026-05-25) — JEWELRY label-hunt runtime probe (issue #38 data-gathering)

Issue #38 ("JEWELRY" still visible on the main forge page) has resisted two fix attempts (v0.7.35 Localize override + v0.7.37 `HeroWindowLoadoutInventory.on_enter` `category.display_name` mutation). The only literal "Jewellery" string a grep of vanilla UI source turns up is `hero_window_loadout_definitions.lua:602` — already patched — so the surface the user is actually seeing must come from a different rendering path I haven't located by static analysis.

**Approach:** add a runtime probe that walks every active window's `_widgets_by_name` on entry and logs every widget whose content contains "jewel" (case-insensitive, recursive to depth 3 through nested tables). Output goes to the log when `enable_debug_logging` is on. Next session's log will pinpoint exactly which widget needs patching, and the fix becomes mechanical.

Probe fires on entry to:

- `HeroViewStateWeaveForge` parent (via existing autodump hook chain)
- `HeroWindowWeaveProperties` / `HeroWindowWeaveForgeOverview` / `HeroWindowWeaveForgeWeapons` (Athanor surfaces — added probe call to existing on_enter hooks)
- `HeroWindowCrafting` / `HeroWindowCraftingConsole` / `HeroWindowItemCustomization` (routed through `_cim_autodump_forge_open` — the consolidated lifecycle callback in `standard_forge.lua` now passes `self` along; the probe runs there to avoid a duplicate `hook_safe` registration that VMF would silently drop)
- `HeroWindowLoadoutInventory` / `HeroWindowLoadoutInventoryConsole` / `HeroWindowCraftingList` / `HeroWindowCraftingListConsole` / `HeroWindowCraftingInventoryConsole` (new dedicated probe hooks — no existing cim on_enter to collide with)

Output format: each widget that contains "jewel" gets a `widget [<name>] -- N match(es):` header followed by indented `<path.to.field> = "literal text"` lines. Summary `scan complete: N widget(s) with 'jewel' text on <window_name>` per probe run.

**User action required to gather the data:** enable `Debug Logging` in cim's VMF settings, open the menu where the JEWELRY label is visible, then send the latest `console-*.log`. The probe output will tell us the exact widget. With that, the fix is one to a few lines.

**Touched files:** `cim_debug.lua` (new helper + hook fan-out), `standard_forge.lua` (one-arg addition to existing autodump call), `crafting_in_modded.lua` (MOD_VERSION bump), `CHANGELOG.md`.

## 0.7.47-alpha (2026-05-25) — Allow Athanor (B hotkey) in Chaos Wastes staging hub

User report 2026-05-25 EOD: pressing B in the Chaos Wastes staging area echoed `"Crafting menu disabled in Chaos Wastes (would crash on preview world load)"` and refused to open the Athanor. The staging hub is where players configure their loadout between expeditions — closing the menu there defeats one of the mod's core use cases.

**Root cause.** The blanket `mech == "deus" -> block` gate in `mod.open_forge()` was added 2026-05-22 (crash GUID `fa1ec6f8`) to dodge the same `levels/ui_store_preview/world: not loaded` fatal that bit issue #50. That crash was fixed in v0.7.45-alpha by rewriting `_create_item_preview_widget_definition` to skip the un-loaded preview level when not in keep. With the underlying fatal gone, the broad CW block became overcautious.

**Fix.** Removed the deus-mechanism early-return at `open_forge`. The remaining keep-gate (`DamageUtils.is_in_inn`) correctly distinguishes:

- **CW staging hub** (`morris_hub`) → `is_in_inn = true` → **allowed**
- **Active Deus level** (mid-expedition) → `is_in_inn = false` → still gated by `allow_in_mission` toggle (default off; opt-in for crash testing)
- Adventure keeps / Inn variants → `is_in_inn = true` → allowed (unchanged)
- Adventure missions → `is_in_inn = false` → gated by `allow_in_mission` (unchanged)

**Touched files:** `crafting_in_modded.lua`, `CHANGELOG.md`.

## 0.7.46-alpha (2026-05-25) — Restore dev/alpha/beta load banner + expanded crafting-menu autodumps

### Restore dev/alpha/beta load banner (PROJECT_STANDARDS § 3.6 update)

User feedback 2026-05-25 EOD: earlier today's chat-spam cleanup pulled the `mod:echo("Crafting in Modded v" .. MOD_VERSION)` startup line from every mod. That's correct for stable (>=1.0.0) builds but hides the active version for in-flight dev/alpha/beta work. PROJECT_STANDARDS § 3.6 amended: dev/alpha/beta/0.x versions MUST echo `[<mod_id>] v<version> loaded` at module load; stable versions stay silent.

`crafting_in_modded.lua` — added a track-detector `if` after the applied-marker line: matches `-dev$` / `-alpha$` / `-beta$` / `-rc%d*$` / `^0%.`. When any branch fires, `mod:echo("[cim] v<MOD_VERSION> loaded")` runs once.

### Expanded crafting-menu autodumps (user request 2026-05-25 EOD)

User direction: "Crafting in modded should dump info about whatever crafting menu the player is in whenever debug mode is on."

Existing autodumps already covered menu *open* (standard forge / Athanor / property editor / salvage / customization), restore-pass completion, and backend-ready. Added coverage for the navigation events inside an open menu, so the log captures every state change the user might be wondering about:

| New hook point | Dump content |
|---|---|
| `HeroWindowCrafting._change_recipe_page` (+ Console variant) | Recipe tile switch — logs `page=<idx> recipe=<name> display=<display_key>` whenever the user clicks salvage / craft_random_item / reroll_props / etc. |
| `HeroWindowWeaveForgeOverview.on_enter` | Athanor's 3-viewport overview — logs career + `amulet_introduced` flag |
| `HeroWindowWeaveForgeWeapons.on_enter` | Athanor weapon-select pane — logs career + selected_slot_name |
| `set_loadout_property` / `set_loadout_trait` / `remove_*` cim hooks | Every bubble write — logs `verb=<set_property|remove_property|set_trait|remove_trait> career=<x> key=<x> slot=<x> bid=<x>` |
| `mod._cim_autodump_customization_item` (helper, callable from anywhere) | Gear-icon menu selected item — bid + key + rarity + slot + skin + power |

All entries gated on `enable_debug_logging` — every entrypoint short-circuits when off, no overhead during normal play. Bubble-write hooks log BEFORE cim's existing forge-active gate runs, so writes that fall through to vanilla are captured too. Output goes to `mod:info` (log only) — no chat spam.

**New file:** none — extends `cim_debug.lua`. **Touched files:** `cim_debug.lua` (new helpers + 5 new hooks), `crafting_in_modded.lua` (4 autodump calls injected at the top of existing weave-property/trait hooks), `CHANGELOG.md`.

## 0.7.45-alpha (2026-05-25) — CRASH FIX: gear-icon mid-mission (issue #50)

User report 2026-05-25 (crash GUID `3bd92d07-8d83-467d-8098-9142a9c7c9bf`): game **crashed** when clicking general_tweaker's mid-mission inventory gear icon. With cim enabled this should open `HeroWindowItemCustomization` so cosmetics / properties / traits can be edited in-mission.

**Crash banner:** `hero_window_item_customization.lua:410: Level not loaded: levels/ui_store_preview/world`. Triggered at 21:49:30.695, 60s into a `military` adventure mission.

**Root cause.** Vanilla `_create_item_preview_widget_definition` (line 382-435) builds the widget definition inline and calls `LevelResource.object_set_names("levels/ui_store_preview/world")` at line 410 while populating the style table. That call fatals when ui_store_preview isn't loaded — which is every adventure / CW mission. cim's existing hook (added in an earlier patch and documented at lines 1163-1204) called vanilla first and post-stripped `level_name` / `object_sets`, but the strip never ran because vanilla never returned.

**Fix.** Skip the vanilla call entirely when not in keep — construct the widget definition from scratch, mirroring vanilla's shape minus `level_name` and `object_sets`. `_FORGE_MISSION_SAFE_ENV` (`environment/ui_hdr`) used in place of `environment/ui_store_preview`. The item still renders because `LootItemUnitPreviewer` uses `resource_packages/levels/ui_loot_preview` from `GlobalResources`. Sibling hook on `_register_object_sets` (line 1251+) already handles the no-level case correctly.

Keep behavior unchanged — `_is_in_keep()` gate at the top of the hook still calls vanilla.

**Touched files:** `crafting_in_modded.lua`, `CHANGELOG.md`. **Issue #50 stays OPEN until user confirms in-game.**

## 0.7.44-alpha (2026-05-25) — Action-rejection feedback visibility + stamina/movespeed click-cap removal (issues #47, #49)

Two connected user reports from 2026-05-25, same root cause: the v0.7.38 blanket `mod.echo` chat suppression silenced action-rejection messages, making cap-enforced clicks look like "nothing happened" → "100% broken" perception.

### Action-rejection messages now use `mod:warning` (always visible)

Roughly a dozen `mod:echo` calls that fire on rejected user actions (craft failures, backend-not-ready, no-eligible-items, DLC-locked illusions, distinct-property cap, etc.) converted to `mod:warning`. `mod:warning` is NOT patched by v0.7.38's chat-suppression — warnings always surface to chat AND log regardless of `enable_debug_logging`. Semantically correct too: the user attempted an action that wasn't allowed.

Sites converted:
- `crafting_in_modded.lua`: distinct-property cap (issue #47 partial), stamina/movespeed bubble cap (now removed, see below), Athanor craft-failed paths (4 sites), backend-not-ready, "no weapon selected"
- `standard_forge.lua`: reroll-no-input, "Cannot craft / wrong slot_type", "No eligible items", crafting interface not ready, backend mirror not ready
- `illusion_swap.lua`: "Cannot apply illusion — requires DLC you don't own"

Diagnostic / load-time / status echoes stay as `mod:echo` (silenced unless debug logging on).

### Stamina / movespeed per-property bubble cap REMOVED (issue #49)

User report: "the stamina and movement speed properties still require the same number of free slots to be assigned and until enough space is clear it blocks more properties."

Root cause: vanilla's bubble grid renders 10 clickable slots regardless of property type, but cim's `set_loadout_property` hook silently rejected clicks past `_PROPERTY_BUBBLE_CAP_STATIC[property]` (stamina=2, movespeed=1). User would click visibly-empty slots 3-5 on a stamina row and see no fill — cim's check rejected the click before vanilla's bubble render could update.

Fix: removed the per-property bubble-cap rejection in `crafting_in_modded.lua:~2356`. Clicks now succeed for stamina/movespeed up to all 5 visible slots.

**Game value unchanged.** `_value_for_bubbles` still clamps the persisted property value at 1.0 (= vanilla +2 stamina tier 5, = +5% movespeed). Extra clicks beyond the engine cap write redundantly but produce no further game effect.

**Known inconsistency:** on session reload, `_bubbles_for_value` seeds only the engine-max bubble count (2 stamina / 1 movespeed) from the persisted value, so "I had 5 stamina bubbles filled" loads back as 2. The game-effect value is correct throughout — only the displayed bubble count compresses on reload. A full fix needs the click count persisted separately; deferred to a later patch.

**Distinct-property cap (MAX_DISTINCT_PROPERTIES = 2) is unchanged** — it's a vanilla-crash gate for `HeroWindowItemCustomization`'s Apply-Skin preview (only ships widgets for hotspot_1 / hotspot_2; a third distinct key crashes `item_customization.lua:1213`). The distinct-cap warning also goes through `mod:warning` now, so users see "Max 2 distinct properties per item" feedback when they hit that.

**Issues #47 and #49 stay OPEN until the user confirms in-game.**

**Touched files:** `crafting_in_modded.lua`, `standard_forge.lua`, `illusion_swap.lua`, `CHANGELOG.md`.

## 0.7.43-alpha (2026-05-25) -- Fix unescaped %APPDATA% in Debug Logging tooltip + add localization_format_safe runtime test

### Why
User report: "invalid string format on mouseover for Debug Logging" -- the canonical Universal Debug Logging tooltip (PROJECT_STANDARDS.md S 3.6) shipped with a literal %APPDATA%. Lua's string.format reads %A as a format directive and raises invalid option '%A' to 'format', surfacing as a red error tooltip in the VMF settings UI. All 16 active mods were affected (every mod ships the same canonical tooltip text).

### Changed
- crafting_in_modded_localization.lua -- escaped literal % in enable_debug_logging_tooltip so VMF's tooltip render path sees %%APPDATA%% (renders as %APPDATA% to the player). Same wording, just escaped.
- crafting_in_modded.lua -- added _rt_register("localization_format_safe", ...) runtime check. dofiles the loc table and pcall(string.format, value) on every entry; surfaces any unescaped % via /<mod_id>_regression_test. Catches the bug class even when the static check (qa/check_localization.ps1) is skipped.

### Notes
Repo-wide multi-layer defense landing across all 16 mods in this sweep:

1. Layer 1 -- 16 mods' loc strings fixed.
2. Layer 2 -- qa/check_localization.ps1 extended to parse loc.<key> = { en = "..." } assignment style (chaos_wastes_tweaker's pattern -- previously slipped detection).
3. Layer 3 -- _rt_register("localization_format_safe", ...) runtime check in every mod.
4. Layer 4 -- tools/vmb-launcher/CLAUDE.md doctrine update: "Run qa/check_localization.ps1 before declaring any localization edit complete."
5. Layer 5 -- documentation: LOCALIZATION_STANDARD.md S 1 "Recurring offender" worked example, docs/BUG_CLASSES.md S 16 new entry, PROJECT_STANDARDS.md S 3.6 canonical tooltip text now uses %%APPDATA%%.

Static check (qa/check_localization.ps1) reports 0 errors post-fix (down from 15 detected + 1 hidden in chaos_wastes_tweaker).

### Build
VMBLauncher.exe build crafting_in_modded -- verification only. NOT deployed, NOT uploaded.

## 0.7.42-alpha (2026-05-25) — `custom_glow` pass-through field for sibling-mod overlays

### Why
cosmetics_tweaker is building a per-instance weavebound-glow customizer for the Bretonian Longsword (Evengleam) and other magic-family weapons. The glow state needs to persist per backend_id alongside the skin and survive game restarts. CIM already has the right substrate — `_forged_weapons[backend_id]` is keyed by backend_id and round-trips through VMF settings on every save — so the cleanest integration is a single opaque pass-through field on the entry. CIM stores it, doesn't interpret it; cosmetics_tweaker writes / reads / applies.

### Added
- `custom_glow` field on every `_forged_weapons[bid]` entry. Pass-through only — CIM never reads its contents. Persists through `_forge_save` / `_forge_load` / `_cim_register_craft` like every other field.
- `mod._cim_set_custom_glow(backend_id, blob)` — sibling-mod updater that amends just the overlay slot on an existing entry and persists immediately. Returns true on write, false when the backend_id is unknown.

### Behavior when cosmetics_tweaker isn't installed
The `custom_glow` blob sits unread on the in-memory entry. No apply path runs. The weavebound skin renders with its vanilla baked materials — the correct fallback. No crash, no warning spam. cosmetics_tweaker's apply code is the only consumer; if it's not loaded, the field is inert data.

### Schema compatibility
Legacy saves without the field load cleanly (nil = no overlay). New saves include the field for every entry (nil-valued when no overlay is active).

## 0.7.40-alpha (2026-05-25) — Applied marker (universal — PROJECT_STANDARDS.md § 3.6)

### Why
Every mod now prints a single `mod:info("[cim] enabled v<X.Y.Z> settings_fp=<8-hex>")` line at load — self-documenting console_logs. Walks the data widget tree, FNV-1a-32 hashes setting=value pairs. ALWAYS fires (not gated on debug_logging).

### Changed
- `crafting_in_modded.lua` — added file-local `_settings_fingerprint()` helper + `mod:info("[cim] enabled ...")` applied-marker line right after the `_dbg_alert` helper.
- `itemV2.cfg` — bumped to v0.7.40-alpha.

## 0.7.39-alpha (2026-05-25) — Two-helper debug-logging policy (PROJECT_STANDARDS.md § 3.6)

### Why
User-requested two-channel debug discipline: `_dbg` for confirmation / dump / expected behavior (log file only), `_dbg_alert` for unexpected / wrong / mismatch (log file + in-game chat). Helpers installed in every active mod.

### Changed
- `crafting_in_modded.lua` — installed `_dbg_alert` helper alongside existing `_dbg`. Added `_rt_register("dbg_helpers_two_channel", ...)` alongside the existing seven cim regression checks.
- `itemV2.cfg` — bumped to v0.7.39-alpha.

### Notes
- 0 existing `_dbg(...)` call sites in this mod (helper was previously unused).
- 0 bare `mod:echo` reclassified — cim already has a global `mod.echo` redirect (top of file) that routes every `mod:echo` to `mod:info` when the toggle is OFF. The new `_dbg_alert` helper bypasses that redirect (by guarding on the toggle = ON path).

## 0.7.38-alpha (2026-05-25) — Standardize Debug Logging toggle (universal convention)

### Why
Repo-wide convention: every mod now exposes a single `enable_debug_logging` checkbox at the bottom of its VMF widget tree (PROJECT_STANDARDS.md § 3.6). cim previously had `debug_mode` nested inside `debug_group` near the bottom — renamed and un-nested.

### Changed
- `crafting_in_modded_data.lua` — removed `debug_group` wrapper; `debug_mode` widget renamed to `enable_debug_logging` and moved to the bottom of `options.widgets` as a direct top-level child.
- `crafting_in_modded_localization.lua` — removed `debug_group` / `debug_mode` / `debug_mode_description` strings; added `enable_debug_logging` + `enable_debug_logging_tooltip` per the standard.
- `cim_debug.lua` — `_enabled()` now reads `mod:get("enable_debug_logging")` (was `debug_mode`). Module-load info line updated. Header docstring updated.
- `crafting_in_modded.lua` — added file-local `_dbg(fmt, ...)` helper at top of file. Output prefix `[cim:dbg]`.
- `itemV2.cfg` — title + description bumped to v0.7.38-alpha.

### Notes
- **Migration**: the saved value of `debug_mode` is not auto-carried into `enable_debug_logging`. Users who had the old toggle on must re-tick the new `Debug Logging` checkbox after first load. VMF defaults the new key to `false`.

### Chat-output suppression by default (user feedback 2026-05-25)

User reported cim was spamming the in-game chat with load / restore / status messages. New behavior: at the top of `crafting_in_modded.lua` (before any `mod:command` registration or sub-module load) we monkey-patch `mod.echo` so every `mod:echo(...)` call in cim is silently redirected to `mod:info(...)` (log only) UNLESS the universal `enable_debug_logging` setting is ON. When ON, the patched echo calls the original — chat output is restored exactly as before, plus the v0.7.36+ autodumps already pipe to log.

Side effect: user-invoked dump commands (`/inv_dump`, `/forge_list`, `/cim_dump_loadout`, `/mirror_dump`, `/salvage_debug`, `/craft_dump`, etc.) also go log-only when debug logging is OFF. To run them and watch the output in chat, tick `Debug Logging` in cim's VMF settings. `mod:error` and `mod:warning` are not patched and still surface to chat on issue.

Also dropped the redundant startup banner `mod:echo("Crafting in Modded v" .. MOD_VERSION)` — the `mod:info` line immediately above it already records the load.

## 0.7.37-alpha (2026-05-25) — Three user-reported fixes: JEWELRY label, accessory power readout, base-power loc placeholder

### "JEWELRY" → "Accessories" on the loadout inventory grid (issue #38)

v0.7.35-alpha added a `_G.Localize` override for `crafting_recipe_craft_jewellery` etc., which fixed the recipe-page titles inside the crafting forge. But the user reported the **JEWELRY** label still visible on the main loadout inventory page.

Root cause: `hero_window_loadout_definitions.lua:602` defines `display_name = "Jewellery"` as a **literal string** in the `category_settings` table, NOT a loc key. `HeroWindowLoadoutInventory._change_category_by_index` reads it raw and writes it directly to the `item_grid_header` widget — `_G.Localize` is never called on it.

Fix in `modded_rarities.lua`: new `mod:hook_safe("HeroWindowLoadoutInventory", "on_enter", ...)` that walks `self._categories` after vanilla builds it, and mutates the jewellery entry's `display_name` to "Accessories". Vanilla's subsequent header write then naturally uses the new value. Single source mutation — all consumers (header, future tooltips) automatically pick up the change.

**Issue #38 stays OPEN until the user confirms the label in-game**, per user directive 2026-05-25.

### Accessory crafting viewport showed "0" for power — now reflects `base_power_level` setting

The Athanor amulet viewport (viewport 2 — the central "accessory crafting" panel) showed `0` next to the power label. cim's `_forge_apply_ui_polish` updates `viewport_power_value_1` and `viewport_power_value_3` from the equipped melee / ranged item's `power_level`, but the slot_map skipped viewport 2 entirely because the amulet doesn't track a single equipped item.

Fix: write `viewport_power_value_2` with the configured `base_power_level` setting (default 300). That matches what a newly-crafted accessory would actually receive, making the readout meaningful instead of a stuck `0`.

### "Base power for new crafts" setting no longer shows "< >" placeholder

`crafting_in_modded_data.lua` declared `unit_text = ""` on the `base_power_level` numeric widget. VMF treats `unit_text` as a loc key — `Localize("")` returns the unresolved-key placeholder `<>`, which renders next to the value as "< >".

Fix: omit the `unit_text` field entirely. A bare numeric is fine for a power-level value.

**Touched files:** `modded_rarities.lua`, `crafting_in_modded.lua`, `crafting_in_modded_data.lua`, `CHANGELOG.md`.

## 0.7.36-alpha (2026-05-25) — Debug-mode toggle + auto-dump diagnostics on menu opens / key events

New VMF setting under a "Debug" group: **Debug mode (auto-dump diagnostics)**. Default OFF.

When ON, cim fires a curated set of diagnostic snapshots to the game log (`%appdata%\Fatshark\Vermintide 2\console_logs\`, no chat spam) at well-known UI transitions and state changes:

| Hook point | What gets logged |
|---|---|
| Standard forge / customization menu open (`HeroWindowCrafting` / `HeroWindowCraftingConsole` / `HeroWindowItemCustomization` `on_enter`) | EAC flag, forge-active flag, show_only_modded flag, mechanism, current career; mirror modded/vanilla counts; every equipped slot for the current career with bid + rarity |
| Athanor open (`HeroViewStateWeaveForge.on_enter`) | `_forged_weapons` saved count + current career |
| Property editor open (`HeroWindowWeaveProperties.on_enter`) | Selected item bid + key + rarity + slot + skin + properties + traits + power, or "amulet layout" if no selected item |
| Salvage page open (`CraftPageSalvage` / `CraftPageSalvageConsole` `on_enter`) | Vanilla salvage-filter result count + modded item count within it (so a "my modded items don't appear in salvage" report is diagnosable from the log alone) |
| `_restore_modded_loadout` finished | Per-career summary of saved entries — spots careers with 0 saved entries (candidates for "my X career loadout wasn't restored" reports) |
| Backend interfaces ready (`BackendManagerPlayFab._create_interfaces`) | mirror size + forged_weapons count + total `_modded_loadout` entries |

All entries are prefixed `[cim-debug] [<context>] ...` so they're greppable. Every entrypoint is a fast no-op when the setting is OFF — zero overhead for normal play.

**Why a new module:** the existing on-demand chat commands (`/inv_dump`, `/mirror_dump`, `/cim_dump_loadout`, `/forge_list`, `/salvage_debug`) echo to chat for interactive use. The autodumps go log-only and are tuned for diagnosing user-forwarded logs after the fact — no need for the user to remember which command produces which snapshot at which moment.

**New files:** `cim_debug.lua`. **Touched files:** `crafting_in_modded.lua` (sub-module loader + 2 autodump call sites), `crafting_in_modded_data.lua` (new Debug group + setting), `crafting_in_modded_localization.lua` (4 strings), `standard_forge.lua` (autodump in consolidated `on_enter` lifecycle callback), `CHANGELOG.md`.

## 0.7.35-alpha (2026-05-24) — Standard forge accessory craft buttons + "CRAFT NEW WEAPON" removed on property editor + Jewellery→Accessories rename

User direction 2026-05-24, three connected changes to the crafting menu:

### Standard forge now has three on-screen accessory craft buttons

Vanilla's `Craft Jewellery` recipe rolls a random jewelry slot. The template-drop affordance (drop a slot-specific blacksmith template → recipe pins to that slot) shipped in v0.7.27 / v0.7.28 but is undiscoverable — players don't know to drop a template first.

Three new buttons injected into `HeroWindowCrafting.window_bottom`, visible whenever the standard forge is open: **CRAFT NECKLACE**, **CRAFT CHARM**, **CRAFT TRINKET**. Clicking one calls the existing `_craft_via_synth(slot_filter, label)` helper directly — same code path as the `/cim_craft_*` chat commands. New code lives at the bottom of `standard_forge.lua` (`_STANDARD_FORGE_BUTTONS` + `_ensure_std_forge_buttons` + `_show_std_forge_buttons` + `_handle_std_forge_button_clicks`), mirroring the Athanor amulet button pattern in `crafting_in_modded.lua:1106-1194`. Gated on `_cim_standard_forge_active` so the buttons appear only on the forge UI.

**Followup TODO:** `HeroWindowCraftingConsole` (gamepad / inventory-tab variant) has a different scenegraph and needs its own button injection pass.

### "CRAFT NEW WEAPON" button removed from the property editor (melee/ranged)

When the player opens an already-equipped melee or ranged item in `HeroWindowWeaveProperties` and tweaks the bubble grid, `_forge_apply_to_item` already mutates the equipped item in place. The repurposed `upgrade_button` was relabeled "CRAFT NEW WEAPON" and minted a redundant new modded item with the same edits — confusing and inverted the "modify your equipped item" mental model.

`_set_essence_upgrade_cost` hook now hides the button entirely (`btn.content.visible = false`) when `slot_type` is `melee` or `ranged`. The `_upgrade_magic_level` handler also early-returns for that case so a stray gamepad activation doesn't bypass the hidden button and mint a phantom craft. To craft a brand-new weapon, the player picks one in the weapon-select pane.

Amulet case (no `selected_item`) and the three cim per-slot accessory buttons in the amulet view are unchanged.

### "Jewellery" → "Accessories" rename on the main forge menu

Extended the existing `_G.Localize` hook in `modded_rarities.lua` with a `_CIM_LOC_OVERRIDES` table covering:

- `crafting_recipe_craft_jewellery` → "Craft Accessories"
- `description_crafting_recipe_craft_jewellery` → "Craft a new accessory (necklace, charm, or trinket) for your current career."
- `crafting_recipe_jewellery_reroll_properties` → "Reroll Accessory Properties"
- `crafting_recipe_jewellery_reroll_traits` → "Reroll Accessory Traits"

Matches the player-facing slot names (necklace / charm / trinket) — the vanilla "jewellery" label was abstract.

### Sibling-mod post-restore callback shim (for cosmetics_tweaker LA persistence)

New public API on `mod` (cim): `mod._cim_register_restore_callback(fn)`. Registered functions fire at the end of every `_restore_modded_loadout` pass (initial + 1.0s deferred + 3.0s deferred), wrapped in pcall so a misbehaving subscriber can't take down cim's restore.

Use case: cosmetics_tweaker's parallel work on persisting LA-applied weapon illusions (issue #22). cosmetics_tweaker captures `{ illusion_key, paint, offhand }` per (career, slot) at apply time and registers a callback that re-applies the saved selections after cim has restored the modded backend_ids. Callbacks must be idempotent — they fire 3× per session boot.

**Touched files:** `standard_forge.lua`, `crafting_in_modded.lua`, `modded_rarities.lua`, `CHANGELOG.md`.

## 0.7.34-alpha (2026-05-24) — Athanor craft no longer auto-equips (icon/equip divergence)

User report 2026-05-24: pressing **CRAFT** on the Athanor's weapon-select pane (or the CRAFT NEW WEAPON button on a selected melee/ranged item) updated the equipment-slot icon to the freshly crafted item, but the actually-equipped weapon in that slot stayed unchanged — icon and equip diverged.

**Root cause.** Three call sites in `crafting_in_modded.lua` ran `backend_items.set_loadout_item(...)` immediately after creating the new modded item:
- `HeroWindowWeaveForgeWeapons._equip_item` hook (~line 2557) — weapon-select pane CRAFT button
- `_cim_amulet_craft_one_slot` (~line 2682) — per-slot amulet craft
- `HeroWindowWeaveProperties._upgrade_magic_level` hook (~line 2765) — CRAFT NEW WEAPON button on the property editor

`set_loadout_item` updates the PlayFab mirror loadout entry (which drives the slot icon) but doesn't rebuild the in-keep equipped unit, so the slot showed one item while still playing another.

**Fix.** Removed all three `set_loadout_item` calls. The craft path now: mirror-injects the new item → persists to `_forged_weapons` → echoes "Crafted & saved: X — equip from inventory". Player equips manually from inventory when they want to.

The two craft viewports in the Athanor (melee + ranged) now match their intended purpose: surface what's craftable for the selected slot, mint a new modded item into inventory, and stop. Modifying-in-place an already-equipped item remains a separate flow via the gear-icon reroll menu (`HeroWindowItemCustomization`).

**Side-effect cleanup.** Salvage-filter comment block (`filter_items` hook ~line 824) updated — it no longer claims "auto-equip on craft" as the reason for the unconditional salvage surfacing.

**Touched files:** `crafting_in_modded.lua`, `CHANGELOG.md`. Issue [#12](https://github.com/Ensrick/vermintide-2-tweaker/issues/12).

## 0.7.33-alpha (2026-05-23) — Fixed: stale loadout entries overwrote vanilla equip on restore + verbose diagnostic logging

User report 2026-05-23 (cim v0.7.32 load): equipped accessories (necklace / charm / trinket) and last-equipped weapons did not restore after a fresh game load. Log showed `Restored 5 modded loadout entries` firing 3 times across state transitions but no detail on WHICH entries were touched.

**Root cause.** `mod:hook_safe(BackendInterfaceItemPlayfab, "set_loadout_item", ...)` at line ~567 only SAVED entries when the new item was modded. It never CLEARED a slot when the user later equipped a vanilla / Save Weapon / Loadout Manager / etc. item there. Stale modded entries stayed in `_modded_loadout` forever. On next session boot, `_restore_modded_loadout` ran AFTER vanilla PlayFab restored each slot and faithfully re-equipped the stale modded item, clobbering what the user had at session-end.

**Fix.** Hook now ALWAYS clears the slot's cim entry first, then re-saves only if the new item is modded. Vanilla equips clean up the cim record; modded equips refresh it. The saved state always matches currently-equipped, not frozen at first-modded-equip-ever.

**Verbose logging.** Three log surfaces upgraded from aggregate-count to per-entry detail so future user reports are diagnosable from the log alone:

- `_restore_modded_loadout` — now prints `[restore] OK <career>/<slot> -> <bid> (<key>)` for each restored entry, `[restore] MISSING ...` for entries whose bid isn't in the mirror, `[restore] ERROR ...` for pcall failures. Summary line: `[restore] total=N restored=N missing=N errored=N`. Also logs `[restore] skipped` reasons when the function early-returns.
- Property trim in `_create_interfaces` — now prints `[trim] <key> (bid=<bid>) kept=[a,b] dropped=[c,d,e]` per item that gets clipped. Previously only the aggregate `Trimmed N items` line existed, so it was impossible to tell which items lost which properties.

**Touched files:** `crafting_in_modded.lua`, `CHANGELOG.md`.

**Test gap closed.** Regression-test additions queued in a parallel patch:
- `/cim_regression_test` round-trip checks for `_modded_loadout` (modded save → reload → confirm; non-modded equip → confirm stale entry cleared)
- `tools/mod-lint/lint-mod.ps1` static check for any `set_loadout_item` hook missing the clear-before-save pattern

## 0.7.32-dev (2026-05-23) — Namespace `regression_test` chat command to avoid cross-mod collision

### Why
Seven mods registered `mod:command("regression_test", ...)`. VT2 chat commands are global — only the first mod wins, the rest fail silently with `[ERROR] (command): command name 'regression_test' is already used by another mod 'cim'`. Detected in PC-A log 2026-05-23 20:50:52.

### Changed
- `crafting_in_modded.lua` — renamed `regression_test` → `cim_regression_test`. Verification log line added at registration site.

### Verification
1. Restart VT2. No `[ERROR] (command):` line in console_logs about this command name.
2. Run `/cim_regression_test` in chat. Command fires and prints results.
3. Per memory `feedback_vt2_verify_before_shipping.md`.

## 0.7.9-dev (2026-05-18) — DLC gate on craftable weapons
**Report:** "Crafting in modded unlocks all weapons for players, and that's a good thing, but it also unlocks dlc weapons that players may not own."

Vanilla gates DLC weapons behind `required_dlc` on the `ItemMasterList` entry, checked via `Managers.unlock:is_dlc_unlocked`. Modded crafting is a power-up over the vanilla progression unlocks (career levels, crafting materials) — NOT a bypass for paid DLC content. `illusion_swap.lua` already respects this gate for cosmetic skins (`_skin_requires_unowned_dlc`, v0.6 series); the parallel was missing on the weapon side.

**Fix:** new local helper `_item_requires_unowned_dlc(item_key)` in `standard_forge.lua` reads `ItemMasterList[item_key].required_dlc` and returns `not Managers.unlock:is_dlc_unlocked(...)`. Exposed as `mod._cim_item_requires_unowned_dlc` for cross-file use. Added to three weapon-eligibility passes:

1. `_build_template_cache` — the synthetic "blacksmith's template" injection from v0.7.7. This is the main user-visible surface; without this filter, the Craft Item recipe page lists every DLC weapon family alongside owned ones.
2. `_make_craft_synth`'s `eligible` random pool — defense-in-depth for the no-input-item fallback path.
3. `HeroWindowWeaveForgeWeapons._setup_weapon_list` — the custom Athanor forge's weapon list, which walks `ItemMasterList` directly.

CWV / mod-added weapons are unaffected — character_weapon_variants explicitly strips `required_dlc` on its cloned entries (cwv `_build_entry`), so the gate is a no-op for them.

## 0.7.8-dev (2026-05-17) — Fix: v0.7.7 templates never built (rehook warning shadowed callback)
**Symptom:** v0.7.7 logged two rehook warnings at startup —
```
[MOD][cim][WARNING] (hook_safe): Attempting to rehook active hook [on_enter].
```
one for `HeroWindowCrafting`, one for `HeroWindowCraftingConsole`. The standard forge's existing `on_enter` hook (set `_cim_standard_forge_active = true`) and the new template-rebuild `on_enter` hook were registered as TWO separate `mod:hook_safe(Class, "on_enter", ...)` calls. Per `feedback_vmf_hook_safe_no_chain`, VMF silently drops the second registration — so `_build_template_cache()` was never called on forge entry, the template cache stayed empty, and the Craft Item recipe page still hid every unlocked weapon family.

**Fix:** consolidated into one callback. The existing on_enter hook now does both jobs (flip the active flag AND rebuild the cache, the latter via `mod._cim_rebuild_template_cache` resolved at call time). Removed the duplicate hook block at the bottom of `standard_forge.lua`.

The lazy-build at the head of `_cim_inject_templates` (`if not next(_template_cache) then _build_template_cache() end`) stays as defense in depth — covers the edge case where filter runs before the first on_enter fires (it shouldn't, but cheap to keep).

## 0.7.7-dev (2026-05-16) — Standard forge "Craft Item": craft any career-eligible weapon
**Report:** "If a player hasn't unlocked a certain kind of weapon then they can't craft or use it." Vanilla `can_craft_with` (backend_interface_common.lua:498) only matches `rarity == "default"` items, and the player only has those for career-level-unlocked weapon families — so the Craft Item recipe page silently hides every weapon family they haven't grinded to. CWV / mod-added weapons never get a default template at all.

**Fix:** synthesize a "blacksmith's template" item per career-eligible weapon family on standard-forge open and inject them into the Craft Item recipe's inventory list. Templates aren't in the backend mirror — they never leak into the regular inventory tab (different filter). Clicking craft feeds the template's `key` into the existing `_make_craft_synth` path, which clones it into a fresh modded-rarity item via `add_item` the same way as before.

Three additions in `standard_forge.lua`:
1. `_build_template_cache()` — walks `ItemMasterList` for `slot_type in {melee,ranged,ring,necklace,trinket}`, `can_wield contains current career`, rarity not `magic`/`promo`, item_type not `weapon_skin`. Cache is keyed by synthetic bid `"cim_template_<key>"`, rebuilt on every `HeroWindowCrafting{,Console}` `on_enter` to stay in sync with career switches between visits.
2. `mod._cim_inject_templates(items, filter)` — appends one template per `item_type` not already represented by a real default-rarity entry. Gated on `_is_active() and filter:find("can_craft_with")` so it only fires for the right recipe page.
3. `BackendInterfaceItemPlayfab.get_item_from_id` hook — resolves `cim_template_*` bids back to the cached entry. The synth's `item_interface:get_item_from_id(bid)` lookup goes through this hook, reads `.key`, and clones the underlying weapon as usual.

`crafting_in_modded.lua`'s existing `get_filtered_items` hook gets one new line: call `mod._cim_inject_templates(filtered, filter)` after the modded-only filtering pass.

**Net effect:** the Craft Item recipe page lists every melee / ranged / jewellery family the current career can wield, regardless of XP-gate state. Player picks one, clicks craft, gets a new modded-rarity weapon of that type.

## 0.7.6-dev (2026-05-13) — Fix inv_dump crash; narrow modded-bid heuristic; new `mirror_dump`
Three changes diagnosing the "modded items not visible in inventory grid" report:

### 1. Narrow `_cim_is_modded_backend_id`
Old version matched any UUID-format backend_id (`^%x+-%x+-%x+-%x+-%x+$`) on the theory that we use `Application.guid()` for our crafts. But `PlayFabMirrorBase._create_fake_inventory_items` also uses `guid()` for every fake weapon-skin / cosmetic / weapon-pose entry — so when `unlock_all_illusions` is on (now unconditional in cim's `get_unlocked_weapon_skins` hook, v0.7.3+), ~1500 fake skin items get UUID bids and were *all* misclassified as "modded".

Visible symptom: `/inv_dump` reported `modded=1553 vanilla=887` and the sample-item output showed weapon_skin / frame items instead of actual crafted weapons. The 4 real crafts were buried.

Fix: regex removed. Modded backend_ids are now strictly `_forged_weapons[bid]` (cim's own registered crafts) or `cwv_*` prefix (character_weapon_variants). Rarity-based detection (`item.rarity == "modded"` or `"promo"`) still covers anything we miss.

### 2. Fix inv_dump crash
`/inv_dump`'s "FILTERED" pass built a sequential array from the bid-keyed `get_all_backend_items()` dict and passed it to `BackendInterfaceCommon.filter_items`. That function iterates with `for backend_id, item in pairs(items)` — so it saw backend_ids `1, 2, 3, …`. `get_item_rarity(1)` called `get_item_from_id(1)` which returned nil, then crashed on `item.skin` (or `item.rarity` depending on the line). Fix: pass `all` directly (already bid-keyed).

### 3. New `/mirror_dump` command
For diagnosing item-missing-from-grid reports specifically. Walks every saved craft in `mod:get("forged_weapons")` and reports per-bid: key, rarity, slot_type, can_wield, in_mirror (`backend_mirror._inventory_items[bid] ~= nil`), in_items_iface (`get_all_backend_items()[bid] ~= nil`), and current loadout slot. Summary line: `saved=N in_mirror=N in_items_iface=N`.

Use this to find which of (a) item not in mirror, (b) mirror has it but `item.data` is nil, (c) `can_wield` doesn't match current career, (d) other filter drop, is the actual cause.

## 0.7.5-dev (2026-05-13) — Fix rehook warning + consolidate craft hook
**Warning at launch:** `[MOD][cim][WARNING] (hook): Attempting to rehook active hook [craft].`

**Cause:** `standard_forge.lua` and `illusion_swap.lua` both registered a `mod:hook("BackendInterfaceCraftingPlayfab", "craft", ...)`. VMF rejects the second registration on the same class+method silently, dropping the hook — so illusion_swap.lua's craft logic was *dead code*. Illusion-apply would fall through to vanilla `craft()` and PlayFab → EAC kick in modded realm.

**Fix:** moved illusion_swap.lua's craft body into a helper `mod._cim_try_illusion_apply(self, career, ids, recipe)`. `standard_forge.lua`'s existing craft hook now calls this helper FIRST (regardless of `_is_active`) and returns its result if non-nil. One craft hook, both behaviors. No rehook warning.

This pattern matches the [[feedback_vmf_hook_safe_no_chain]] rule — for shared class+method hooks, consolidate into one callback rather than two.

## 0.7.4-dev (2026-05-13) — Fix Chaos Wastes crash from custom rarity in pool_excludes
**Crash:** `deus_run_controller.lua:2130 attempt to index a nil value` when opening a Deus weapon chest. Stack: `get_weapon_pool` → `_generate_stored_weapon` → `DeusChestExtension:update`. Crash locals showed `pool_rarity = "modded"`, `excluded_weapon_group = "es_halberd"`.

**Cause:** When a chest grants a unique-rarity weapon, vanilla calls `DeusRunController._remove_weapon_from_pool`. That asks `RarityUtils.get_lower_rarities("unique")`, which iterates `RaritySettings` and returns every rarity with `order < 5` — including our `"modded"` (order=4). The function then writes `pool_excludes["modded"][weapon_group] = true`. On the next chest, `get_weapon_pool` iterates the excludes:

```lua
weapon_pool[pool_rarity][excluded_weapon_group] = nil
```

`weapon_pool` is built from `DeusDropRarityWeights` (vanilla deus rarities only), so `weapon_pool["modded"]` is nil → crash.

**Fix:** new pre-hook on `DeusRunController.get_weapon_pool` in `modded_rarities.lua`. Before vanilla iterates, scrub `pool_excludes` of any rarity key not in the base deus weapon pool. Idempotent — repairs already-contaminated CW runs AND prevents future crashes regardless of which custom rarity caused the pollution (so adding more rarities via `mod.register_rarity` is safe in CW too).

The fix is co-located with the rarity registry on purpose: custom rarities are the population vector, so the compat patch belongs with the registration logic.

## 0.7.3-dev (2026-05-13) — Unlock all DLC-owned illusions + inv_dump diagnostic
Two changes:

### 1. Unlock all DLC-owned weapon illusions in modded realm
Previously vanilla locked illusions (e.g. "Sword of Bitter Dreams") rendered as locked in cim's illusion-swap grid even though the synthetic-backend-id path would happily craft them — the Apply button was disabled because the backend mirror said the skin wasn't unlocked.

New `hook_safe("BackendInterfaceCraftingPlayfab", "get_unlocked_weapon_skins")` in `illusion_swap.lua` iterates `WeaponSkins.skins` and marks every entry as unlocked on the local mirror, except skins gated behind unowned DLC (`_skin_requires_unowned_dlc` — same DLC gate used by the rest of illusion_swap.lua). Only runs when `script_data["eac-untrusted"]` is true (modded realm).

Mirrors cosmetics_tweaker's `unlock_all_illusions` setting, but unconditional in cim — the modded-realm illusion swap doesn't make sense without the unlock, so there's no toggle.

### 2. New `/inv_dump` diagnostic command
Run in the developer console to dump:
- eac-untrusted flag, standard_forge_active flag, show_only_modded_weapons setting, current mechanism, career
- Modded-item count vs vanilla count in the backend mirror
- Per-item detail for the first 8 modded items (backend_id, key, rarity, slot_type, can_wield, wieldable-by-current-career, mechanisms)
- The result of running the loadout grid's actual filter (`available_in_current_mechanism and can_wield_by_current_career and ...`) against the full backend item list, to identify which filter clause is dropping modded items

For diagnosing "modded items not visible in the inventory grid" reports.

## 0.7.2-dev (2026-05-13) — Migrate illusion-swap UI from cosmetics_tweaker; refreshed `icon_bg_modded`
Two changes:

### 1. Modded-realm illusion swap (migrated from cosmetics_tweaker v0.8.49)
cim now ships its own copy of the "change weapon cosmetics in modded realm" pipeline, so the feature is available even when cosmetics_tweaker isn't installed. cosmetics_tweaker yields to cim when both are loaded — each hook in cosmetics_tweaker's illusion-swap section checks `get_mod("cim")` at fire time and defers to the original.

New file `illusion_swap.lua` registers the six hooks that unlock the vanilla illusion-apply flow against the `eac-untrusted` modded-realm gate:

| Hook | Purpose |
|---|---|
| `BackendInterfaceItemPlayfab.get_weapon_skin_from_skin_key` | Synthetic backend ids for unowned skins so the grid can reference them |
| `HeroWindowItemCustomization._enable_craft_button` | Temporarily clear `eac-untrusted` so the Apply button enables for `apply_weapon_skin`. Force-clear hotspot held flags on disable to prevent the fast-completion sound loop |
| `HeroWindowItemCustomization._on_illusion_index_pressed` | Clear `content.locked = false` on clicked widgets |
| `HeroWindowItemCustomization._update_state_craft_button` | Clear `eac-untrusted` for the state check |
| `BackendInterfaceCraftingPlayfab.craft` | Write `item.skin` to the local backend mirror instead of sending to PlayFab |
| `BackendInterfaceCraftingPlayfab.update` | Defer completion one frame to match vanilla async timing |

DLC ownership is respected — skins with `required_dlc` in ItemMasterList only unlock if the player owns that DLC.

**Persistence for modded items:** when the craft hook applies a skin to a backend_id that `_cim_is_modded_backend_id` recognizes, it writes `craft.skin = skin_key` into `_forged_weapons[bid]` and calls `_cim_persist_crafts()`. cim's existing `_forge_load` already reads `w.skin` from the save and threads it into the rebuilt item on next launch, so modded-item cosmetics survive a game restart.

**What was NOT migrated:** the offhand/shield picker (a separate row of buttons that swaps the left-hand model independently). User explicitly excluded it from this migration.

**What was NOT migrated:** the `_custom_skin_keys` registry (cosmetics_tweaker's own custom illusions). Those still work in cosmetics_tweaker because they live in `WeaponSkins.skins` and its own `get_unlocked_weapon_skins` hook is unaffected by this migration.

### 2. Refreshed `icon_bg_modded` PNG
User updated `D:\Game Mods\Vermintide 2 modding\CWV Item Icons\source pngs 84x84\icon_bg_modded.png` (16455 → 18419 bytes). Copied into the mod, rebundled.

## 0.7.1-dev (2026-05-12) — Ship `icon_bg_modded` rarity-background texture
v0.7.0 introduced the `"modded"` rarity but didn't supply an icon background, so every modded item rendered with the vanilla `icons_placeholder` "missing texture" tile in the inventory grid.

Asset pipeline (mirrors `dynamic_cosmetic_portraits`):
- New 80×80 PNG at `gui/1080p/single_textures/cim/icon_bg_modded.png` (user-authored from extracted `icon_bg_exotic` template, recolored to pale gold)
- Matching `icon_bg_modded.texture` (DXT5, sRGB) compile definition
- Matching `icon_bg_modded.material` using `gui:DIFFUSE_MAP` shader
- `.package` updated with `material = [...]` and `texture = [...]` entries so VMB bundles the asset

VMF wiring in `crafting_in_modded_data.lua`:
- `custom_gui_textures.textures = { "icon_bg_modded" }`
- `custom_gui_textures.ui_renderer_injections` covers 10 UI surfaces: `ingame_ui`, `ingame_ui_settings`, `hero_view`, `hero_view_state_loot`, `hero_view_state_store`, `hero_view_state_weave_forge`, `start_game_state_settings_overview`, `level_end_view_base`, `level_end_view_versus`, `ui_manager`. Matches the broad list dynamic_cosmetic_portraits uses, since rarity backgrounds render in identical surfaces.

`modded_rarities.lua` gained step 8 in `register_rarity()`: writes `opts.texture` into `UISettings.item_rarity_textures[name]` so vanilla code resolves the rarity name to our texture. The default `"modded"` registration now sets `texture = "icon_bg_modded"`.

## 0.7.0-dev (2026-05-12) — Custom `modded` rarity replaces `promo` for crafts
Promo rarity blocked customization. Vanilla source has two hard-coded gates that special-case `"promo"` and `"default"`:

- `ui_widgets_honduras.lua:2407` — the inventory cog icon `content_check_function` disables itself when `(rarity == "default" or "promo")` and the slot type isn't in `InventorySettings.customize_default_slot_types_allowed[mechanism]`. In adventure mode that allowlist is `{}`, so the cog was disabled for every promo item — player couldn't even open the customization window.
- `hero_window_item_customization.lua:179` — `_setup_availble_states` collapses to just `{"item_setting"}` for default/promo, stripping properties, traits, and upgrade tabs.

Fix: register a new rarity `"modded"` that's not in those special-case lists, so both gates fall through to the normal `rarity_rating` chain. With `order = 4` (exotic-level) the cog opens AND all four customization tabs are available.

New file `modded_rarities.lua` exposes a reusable registry — `mod.register_rarity(name, opts)` — that wires a custom rarity into all 6 tables the game reads:

| Table | Purpose |
|---|---|
| `UISettings.item_rarity_order` | Sort order + drives `_setup_availble_states` |
| `UISettings.item_rarities` | Iteration list for rarity-filter UI |
| `RaritySettings` | `{display_name, color, frame_color, order}` |
| `RarityIndex` | Mirror of `.order` |
| `ORDER_RARITY` | Mirrored array (string keys + numeric indices) |
| `NetworkLookup.rarities` | Required for inventory sync round-trip |

Color is data — pass either an existing palette name (`"exotic"`, `"magic"`, etc.) OR a `{a, r, g, b}` table. Default for `"modded"` is soft pale gold `{255, 248, 237, 197}`. Hooks `_G.Localize` to resolve `rarity_display_name_modded` → "Modded".

All four new-craft paths in `crafting_in_modded.lua` (Athanor weapon equip, Athanor amulet, amulet `_upgrade_magic_level`, `_athanor_inject_item` fallback) plus two in `standard_forge.lua` switched from `rarity = "promo"` to `"modded"`.

Backward compat: `_forge_load` migrates pre-v0.7.0 saved crafts (`rarity == "promo"`) to `"modded"` on load and re-saves. `_cim_is_modded_item` accepts both `"modded"` and `"promo"` so any stragglers still surface in the salvage list. `NetworkLookup.rarities` still includes `"promo"` for legacy roundtripping.

Bumped version 0.6.4-dev → 0.7.0-dev (rarity migration = minor version bump).

## 0.6.4-dev (2026-05-10) — Defer-retry saved crafts that need other mods' ItemMasterList entries
Most likely root cause of "purple/crafted weapons treated as blacksmith variants" + "not showing in salvage": the v0.4.1 `rawget(ItemMasterList, item_key)` pre-check in `_athanor_inject_item` skips a saved craft whose `item_key` isn't registered yet (typical case: `cwv_*` keys when CWV hasn't finished its `_create_interfaces` hook). The crafted item never enters the mirror this session, so the player sees the blacksmith template in that slot instead.

Three changes:

1. **Skipped injections are now deferred, not lost.** `_athanor_inject_all` tracks skipped bids in `_pending_inject = { [bid] = weapon_data, ... }`.
2. **Retry on every state change.** New `mod.on_game_state_changed` calls `_athanor_retry_pending()`. Once the sibling mod registers the missing key, the next state transition re-injects the saved craft.
3. **Skip-already-injected.** When `_create_interfaces` fires multiple times (it does), `_athanor_inject_all` checks the mirror's `_inventory_items[bid]` first — avoids duplicate `add_item` calls and misleading "restored N" log lines.

Also promoted the "skipped N saved crafts" message from `mod:info` to `mod:echo` so it's visible in chat without opening the log.

## 0.6.3-dev (2026-05-10) — Amulet CRAFT button visible + clickable (was "Fully Upgraded" greyed)
The amulet's `upgrade_button` was rendering as "Fully Upgraded" and disabled. Two vanilla guards in `HeroWindowWeaveProperties._set_essence_upgrade_cost` (`hero_window_weave_properties.lua:1856-1897`):

- Line 1886: when `essence_amount` is nil, button text falls back to `Localize("menu_weave_forge_upgrade_loadout_button_cap")` = "Fully Upgraded". Our weaves hooks always return 0/nil essence so this branch always fires.
- Line 1895: `disable_button = script_data["eac-untrusted"] or ...` — modded realm sets `eac-untrusted = true`, so the button is permanently disabled.

Post-hooked `_set_essence_upgrade_cost` (runs on every refresh) to override:
- `button_content.title_text` = "CRAFT MODDED JEWELLERY" (amulet path) or "CRAFT NEW WEAPON" (single-item path)
- `button_hotspot.disable_button = false`
- Hides the price-icon alpha + the "not enough essence" warning widget

Combined with the existing `_upgrade_magic_level` hijack (which performs the actual craft on click), the button is now both visible AND functional.

## 0.6.2-dev (2026-05-10) — `/salvage_debug` diagnostic command
Adds a focused diagnostic for "why isn't my modded craft showing in salvage?". Dumps every entry in `_forged_weapons` plus whether it's currently in the backend mirror (`inv=Y/N`), the mirror's rarity, the slot_type, the item_key, and the bid. Also dumps any promo-rarity items in the mirror that AREN'T in our save (orphans).

Most likely failure modes the dump reveals:
- `inv=N` → the saved craft didn't re-inject this session (ItemMasterList key not registered yet — usually a `cwv_*` key with CWV not loaded at our hook time).
- `rarity != promo` → the item's CustomData didn't round-trip through `_update_data` correctly, so the rarity-based salvage fallback misses it.
- `slot=<no data>` → the item's `data` field is nil; usually means the ItemMasterList entry is missing.

## 0.6.1-dev (2026-05-10) — Salvage rarity fallback + forward-declare `_amulet_dirty`
Two fixes:

1. **Salvage now matches by `rarity == "promo"` first.** Added `mod._cim_is_modded_item(item)` — same as the bid-heuristic check, plus an early-return for `item.rarity == "promo"`. Salvage post-hook switched to it. Catches modded crafts whose backend_id format doesn't fit the current regex (older mod versions, items synced from another machine, etc) — the user reported a saved purple-rarity axe+falchion not surfacing.

2. **Forward-declare `_amulet_dirty` at the top of the Athanor section.** v0.6.0 declared it `local` further down (line 959), but the `on_exit` reset at line 474 closed over it as a nil global → indexing `_amulet_dirty[1] = false` would have errored on forge close. Moved the declaration above the hook so both the hook and the helpers see the same upvalue.

## 0.6.0-dev (2026-05-10) — Amulet CRAFT button: per-slot dirty tracking, modded copies on edit
The amulet's CRAFT button (repurposed `upgrade_button`) now handles the 3-accessory case. When the player edits bubbles or trait slots in the amulet, we mark the matching accessory dirty (`_amulet_dirty[1..3]`); pressing CRAFT iterates the three slots and creates a new modded item only for slots that were edited this session.

For each dirty slot we read the equipped item's current `properties` / `traits` (already mutated in-place by auto-apply on bubble click), clone them into a new modded item via `_athanor_inject_item`, persist via `mod._cim_register_craft`, and equip via `set_loadout_item`. Vanilla items the player edited get a permanent modded counterpart; modded items they edited get a fresh saved snapshot.

Pressing CRAFT with no edits echoes "No accessory edits to craft" and does nothing. Dirty flags reset on `HeroViewStateWeaveForge.on_exit`.

Updated `AMULET_OF_ASHUR.md` with full status, slot-order rationale, data-flow summary, and remaining polish items.

## 0.5.6-dev (2026-05-09) — Fix amulet slot index mapping (charm/necklace were inverted)
The user reported necklace data displayed at the top of the amulet view but the picker (the menu where you choose properties / traits) was showing CHARM options. Root cause: vanilla `WeaveCareerProgression` orders the amulet's 3 slots by accessory POOL:

- slot 1 = `offence_accessory` → **charm**
- slot 2 = `defence_accessory` → **necklace**
- slot 3 = `utility_accessory` → **trinket**

`HeroWindowWeaveProperties._setup_menu_options` reads the `category` field on each progression entry and renders the matching property/trait pool in the picker. I'd assigned necklace=1, charm=2, trinket=3 — exactly inverted for slots 1 and 2 — so the necklace's data went into a slot whose picker rendered charm options.

Fixed `_AMULET_SLOT_BY_INDEX` to match `WeaveCareerProgression`. Both `_forge_seed_item` and `_forge_apply_to_amulet` iterate the same table, so the apply path is consistent.

## 0.5.5-dev (2026-05-09) — Adventure talents wired into the amulet's talent picker
The amulet UI's talent picker shows the player's career talent tree from `WeaveLoadoutSettings[career].talent_tree` — which is set to `TalentTrees[profile][index]` (see `weave_loadout_settings_*.lua`), i.e. exactly the same 6×3 tree adventure mode uses. So the talents the player sees ARE adventure talents.

Wired three hooks for read/write:

- **`get_loadout_talents`**: reads the player's adventure picks via `Managers.backend:get_interface("talents"):get_talents(career)` (returns array of 6 column picks 1..3), maps each row's pick to its talent name via `TalentTrees[profile][index][row][pick]`, returns `{[talent_name] = row}` — the format the bubble grid expects.
- **`set_loadout_talent(career, talent_name, row)`**: finds which column in that row owns `talent_name`, calls `talents:set_talents(career, picks)` with the updated array. Write-through to vanilla: the player's actual career talents change immediately and persist via the regular adventure save layer.
- **`remove_loadout_talent`**: no-op. The bubble grid emits remove→set pairs on each swap; we commit the new pick directly in `set_loadout_talent`, no need to model the intermediate state because adventure rows always have one talent.

Now opening the amulet should show your current talent picks highlighted, and changing them in the picker writes through to your actual career.

## 0.5.4-dev (2026-05-09) — Fix amulet slot names (charm + trinket weren't populating)
The amulet seed/apply was reading `slot_charm` and `slot_trinket`, but VT2's `career_settings` names them `slot_ring` (legacy) and `slot_trinket_1`. `get_loadout_item_id(career, "slot_charm")` returned nil, so the seed silently dropped both items — only the necklace populated the bubble grid.

Centralized the slot list in `_AMULET_SLOT_BY_INDEX = { [1] = "slot_necklace", [2] = "slot_ring", [3] = "slot_trinket_1" }` and updated both `_forge_seed_item` and `_forge_apply_to_amulet` to iterate it. Charm and trinket should now populate (and apply correctly to the right items on edit).

Talents (the 6 talent slots in the amulet layout) still aren't populated — that needs translating adventure talent picks (numeric 1-3 per row) into the weave-talent name format the bubble grid expects, which is a separate integration.

## 0.5.3-dev (2026-05-09) — Surface modded items in salvage regardless of equip state
The salvage filter post-hook was respecting vanilla's "no equipped, no in-loadout, no favorited" rule for modded items. That hid every freshly-crafted modded item — we auto-equip on craft via `set_loadout_item`, so the new item is immediately considered equipped + in-loadout, making it un-salvageable.

Modded crafts are throwaway by design — the user owns their lifecycle and should be able to scrap them at will. Relaxed the post-hook to add modded items unconditionally (still slot-typed to weapons/jewellery only). Vanilla items keep the original guards.

## 0.5.2-dev (2026-05-08) — Fix salvage crash on UI reward presentation
Salvage was crashing the game with `backend_interface_item_playfab.lua:354: attempt to index local 'item' (a nil value)`. The salvage page's `on_craft_completed` iterates the craft result and calls `_set_reward_material_by_index(backend_id, amount)` → `item_interface:get_key(backend_id)` → unguarded `item.key`. Vanilla's salvage result contains produced-material bids (scrap / dust); our synth was incorrectly putting the consumed weapon bids in there, and those bids were already removed from the mirror by the time the UI processed them → nil item → crash.

Fix: salvage synth now returns an empty result `{}` (we don't produce materials in modded). The UI iterates nothing, no nil access. The actual removal + unregister + loadout-clear logic is unchanged.

## 0.5.1-dev (2026-05-08) — Amulet bubble seed + apply for properties & traits
Wired the seed/apply chain for the amulet's 3-item case:

**Seed** (`_forge_seed_item` with `item_backend_id == nil`): reads the player's currently equipped necklace, charm, and trinket and packs each item's properties into its own bubble layer (necklace = slot indices 1..10, charm = 11..20, trinket = 21..30). Each item's first trait fills the matching trait widget (necklace = trait slot 1, charm = trait slot 2, trinket = trait slot 3).

**Apply** (`_forge_apply_to_amulet`): groups property fills by layer to figure out which accessory each bubble belongs to, converts back to fractional values, and writes to each accessory's `item.properties` / `item.traits` in the local mirror. Modded items also flush to the `_forged_weapons` save layer.

Talents are still TBD (the 6 talent slots in the layout populate from `BackendInterfaceWeavesPlayFab.get_loadout_talents`, which we currently return `{}` from). Wiring those to adventure talents is the next push.

## 0.5.0-dev (2026-05-08) — Amulet click flows through to vanilla 3-section UI
**Major rework**: vanilla `HeroWindowWeaveProperties.on_enter` already chooses between two pre-built layouts based on `_selected_item()`:
- `weapon_slot_layout` (1 trait + 10 properties) when an item is selected
- `amulet_slot_layout` (3 trait slots × 30 property slots in 3 layers + 6 talent slots) when no item is selected

The amulet viewport's `data.item` is nil, so a click already routes to `weave_properties` with `selected_item = nil` → vanilla auto-renders the WoM-style 3-section amulet UI we wanted. The previous cycling-through-slots approach was OVERRIDING this with the single-item layout. Reverted.

What's now live:
- Amulet viewport title shows "JEWELLERY / Necklace + Charm + Trinket"
- Click flows to vanilla weave_properties → 3-section UI renders
- The CRAFT button (repurposed upgrade_button) still fires our craft logic, but currently expects a single selected_item — needs rework for the 3-item amulet case (next phase)

What's NOT yet wired:
- Bubble grid is empty on entry (our `_forge_seed_item` returns empty for nil item_backend_id) — needs to read necklace + charm + trinket and merge
- Apply (in-place edit) doesn't distribute properties to the correct accessory yet
- CRAFT for amulet should produce 3 new items (one per slot) instead of one
- Talent row reads from `BackendInterfaceWeavesPlayFab.get_loadout_talents` (we return `{}`) — need to redirect to adventure talents

These come in 0.5.x patches. This release exists to verify the right UI renders.

## 0.4.5-dev (2026-05-08) — Per-slot Craft label + non-modded edit hint
- The CRAFT button now reads "CRAFT NEW NECKLACE" / "CRAFT NEW CHARM" / "CRAFT NEW TRINKET" / "CRAFT NEW WEAPON" depending on the source slot.
- When the player opens the editor for a non-modded item, a one-time `mod:echo` reminds them that bubble edits are session-only and CRAFT makes a permanent modded copy.

## 0.4.4-dev (2026-05-08) — Craft button in the bubble-grid editor (Phase A.5 partial)
The properties window's `upgrade_button` (vanilla "Upgrade Power" for Winds of Magic) is now repurposed in the modded forge as **CRAFT**. Hijacked `HeroWindowWeaveProperties._upgrade_magic_level` to short-circuit the vanilla magic-level upgrade and instead:

1. Read the currently selected item's `properties` and `traits` (already up-to-date because the bubble grid mutates them in-place via `_forge_apply_to_item`).
2. Synthesize a new modded item via `_athanor_inject_item` with `rarity = promo`, `via_mirror = true`.
3. Persist it in `_forged_weapons` via `mod._cim_register_craft`.
4. Equip it in the source slot (necklace / charm / trinket / melee / ranged).

The button's text widget is re-labeled to "CRAFT" and kept visible (previous versions hid it). The existing Apply flow (bubble click → in-place mutation) still works in parallel for editing equipped modded items without making a new copy. Greying the button when the equipped item is non-modded is still TBD (Phase A.5 finish).

## 0.4.3-dev (2026-05-08) — Amulet click auto-cycles slots; viewport title shows next slot
The amulet viewport's title now reads `EDIT: NECKLACE` / `EDIT: CHARM` / `EDIT: TRINKET` to indicate which accessory the next click will edit. After each click+edit, the amulet's slot pointer auto-advances to the next accessory — three clicks in a row visit all three.

The slot pointer (`mod._cim_amulet_slot`) is reset to necklace whenever `HeroViewStateWeaveForge.on_enter` fires so each forge session starts in a known state. The `/amulet_n` / `/amulet_c` / `/amulet_t` commands still let the user jump directly.

The existing weave Apply flow (bubble grid → `_forge_apply_to_item` → `item.properties`) already handles accessory items because their property keys map cleanly to `WeaveProperties` weave-prefixed entries. No changes needed for Apply on jewellery.

## 0.4.2-dev (2026-05-08) — Amulet routes to weave_properties for chosen accessory (Phase A.3 partial)
The amulet viewport click now actually opens the bubble-grid editor for the player's selected jewellery slot. We pre-populate `self._params.selected_item / selected_slot_name / selected_unit_name` (matching what vanilla's `_handle_input` does for melee/ranged) and let the parent state transition to `weave_properties` normally.

The slot cycle lives on `mod._cim_amulet_slot` (default `slot_necklace`). Three console commands set it: `/amulet_n`, `/amulet_c`, `/amulet_t`. The next phase will replace these with on-screen Necklace / Charm / Trinket buttons inside the editor and add the Apply / Craft buttons.

The bubble grid renders via `WeaveProperties` weave-prefixed entries; accessory props (`weave_protection_chaos`, `weave_curse_resistance`, etc.) are present in WeaveProperties so the existing `_forge_seed_item` mapping works without changes.

## 0.4.1-dev (2026-05-08) — Crash fix + amulet click stub (Phase A.2)
**Crash fix.** A saved `cwv_*` craft (e.g. `cwv_es_javelin`) was triggering `[ItemMasterList] ItemMaster List has no item cwv_es_javelin → game close` during `_create_interfaces`. The `_athanor_inject_all` re-injection runs before `character_weapon_variants` registers its variants in `ItemMasterList`. Added a `rawget(ItemMasterList, item_key)` pre-check in `_athanor_inject_item`: skip + log if the key isn't registered yet. Affected items just won't be re-injected this session (re-craftable).

**Bogus hook removed.** v0.3.10 added a hook for `HeroWindowCraftingInventory` (non-Console variant) — that class doesn't exist in current VT2 builds, VMF logged "trying to hook object that doesn't exist". Guarded with `rawget(_G, "HeroWindowCraftingInventory")`.

**Phase A.2 stub.** Amulet viewport click now intercepted in `HeroWindowWeaveForgeOverview._handle_input` — echoes a placeholder instead of letting vanilla route to `weave_properties` with a nil item (which would have entered a broken state). Phase A.4 will swap the echo for the real 3-subsection editor window.

## 0.4.0-dev (2026-05-08) — Athanor amulet viewport visible (Phase A.1)
First step of the AMULET_OF_ASHUR.md plan. The central amulet viewport is now visible in the modded Athanor — `_initialize_viewports` hook flips `amulet_introduced` from `false` to `true`, and `_forge_apply_ui_polish` no longer force-hides the viewport_2 widget cluster. Click currently still routes to vanilla `weave_properties` (with no item, so probably a no-op or weird state). Phase A.2+ will wire the click to a custom 3-subsection editor for necklace/charm/trinket plus talents.

## 0.3.12-dev (2026-05-08) — Athanor hover preview uses the standard item-tooltip box
The B-hotkey forge previously rendered a custom three-panel preview (overview / properties / trait) built from `UIWidgets.create_item_option_*`. Replaced with a single `UIWidgets.create_simple_item_tooltip` widget — the same tooltip pass (`item_tooltip`) that the regular inventory and crafting menus show on hover. Same set of `tooltip_passes` as the deus run-stats screen (item_titles, properties, traits, light/heavy/push/ranged attack stats, etc).

`_forge_populate_item_panels` and `_forge_hide_item_panels` collapsed to a single `tt.content.item = item or nil` call. `_wt_overview_widget`/`_wt_properties_widget`/`_wt_trait_widget` removed.

## 0.3.11-dev (2026-05-08) — Reroll properties / traits with shuffle-bag (no repeats)
Implemented `reroll_weapon_properties`, `reroll_jewellery_properties`, `reroll_weapon_traits`, `reroll_jewellery_traits`. Reroll cycles through every entry in `WeaponProperties.combinations[<prop_table>].exotic` (or `WeaponTraits.combinations[<trait_table>]`) before repeating any — when the bag is exhausted it resets and starts over.

Each item's shuffle state lives in its `_forged_weapons` save entry (`rerolled_props_indices`, `rerolled_trait_indices`), so closing/reopening the game doesn't reset the bag. Properties are always set to max value (1.0); the user gets to see every combo without the dice working against them.

Added two public helpers on the mod object: `mod._cim_get_craft(bid)` (returns the saved entry) and `mod._cim_persist_crafts()` (writes `mod:set("forged_weapons")`).

## 0.3.10-dev (2026-05-08) — Hide crafting-material displays
Modded crafting doesn't consume materials, so showing scrap/dust counts and recipe ingredient costs was just clutter. Two hooks:

1. **Per-recipe ingredient list** — post-hook `setup_recipe_requirements` on every material-gated CraftPage (and its console twin) sets `material_text_*` and `material_icon_*` widget visibility to false after vanilla populates them.
2. **Top inventory material panel** — post-hook `HeroWindowCraftingInventoryConsole._update_crafting_material_panel` (and the non-console variant) hides the row showing player material counts.

Both apply each refresh, so any ticks that re-show the widgets are immediately re-hidden.

## 0.3.9-dev (2026-05-08) — Auto-hide vanilla weapons from all crafting menus
The inventory filter now also engages whenever the standard crafting UI is open (`mod._cim_standard_forge_active`), regardless of the "Show only modded weapons" setting. Rationale: vanilla weapons can't actually be salvaged/upgraded/rerolled in modded realm — the commit-block prevents PlayFab from learning about the change, so vanilla items revert on next session. Showing them in crafting menus was misleading.

Default-rarity items (blacksmith's templates) still pass through the filter — the "Craft Item" recipe uses `can_craft_with` which only matches default rarity, so removing them would break the choose-what-to-craft flow.

## 0.3.8-dev (2026-05-08) — Surface modded crafts in the salvage inventory grid
The vanilla `can_salvage` filter macro (`backend_interface_common.lua:412`) explicitly excludes `rarity == "promo"` and `rarity == "magic"`, so our modded crafts (always promo for the purple icon) were filtered out of the salvage tab — the user couldn't drop them in to scrap. Added a post-hook on `BackendInterfaceCommon.filter_items`: when the filter expression contains `can_salvage`, scan the input items for any modded backend_ids that the vanilla filter excluded, and add them back if they pass the same equipped/loadout/favorited checks. The salvage UI now shows promo modded crafts alongside vanilla salvageable items.

## 0.3.7-dev (2026-05-08) — Salvage now persistently removes modded crafts
The salvage synth removed items from the local mirror, but modded crafts saved in `_forged_weapons` would be re-injected on next session — making them effectively unsalvageable across runs. Salvage now also calls `mod._cim_unregister_craft(bid)` (drops the save entry) and `mod._cim_clear_modded_loadout_for_bid(bid)` (removes any (career, slot) entry pointing at the salvaged item, so loadout-restore doesn't try to re-equip a deleted item). Added an `mod:echo` summary so the player sees what was scrapped.

Vanilla items still revert on game restart because the commit-block prevents PlayFab from learning about the local removal — this is intentional, the only way to actually delete a vanilla item is via the live PlayFab session.

## 0.3.6-dev (2026-05-07) — Standard-forge crafts roll 2 max props + 1 trait + promo rarity
Standard-forge crafts now produce the same "good" item shape as the Athanor:
- **Rarity = `promo`** (purple icon background — signals "modded craft" in the inventory grid).
- **2 random properties** rolled from `WeaponProperties.combinations[<weapon's property_table>][exotic]` (the 2-property tier), each set to **max value (1.0)**.
- **1 random trait** rolled from `WeaponTraits.combinations[<weapon's trait_table>]`.
- Properties and traits are also written into `CustomData.properties`/`CustomData.traits` (cjson-encoded) so `_update_data` picks them up after `add_item`, and saved into `_forged_weapons` so they persist across game restarts.

Vanilla rolled within the slot type and didn't always max stats; modded mode prefers reliable maxed gear since players are choosing what to craft.

## 0.3.5-dev (2026-05-07) — Always clone the dropped weapon (default-rarity is the chosen weapon)
v0.3.1–0.3.4 only cloned the dropped weapon when its rarity was NOT "default" — exactly backwards. The "blacksmith's weapons" players drop into the recipe slot ARE default-rarity items (starter weapons like the Imperial Longsword the character spawned with). They represent a specific weapon type, not a generic placeholder. Skipping them sent every craft to the random pool, which happened to land on similar weapons and looked like "always crafts my currently equipped weapon type".

Fix: clone the dropped item's `key` / `ItemId` regardless of rarity. The random pool now only fires when the slot is genuinely empty.

## 0.3.4-dev (2026-05-07) — Re-enable mutating standard-forge recipes (cim was not the cause)
The cosmetic regression reported in 0.3.3 was on the **vanilla gear icon** path (`HeroWindowItemCustomization` → cosmetics_tweaker's own `craft` hook), not cim's standard-forge "Apply Illusion" tab. cim's standard-forge synth was never invoked in that flow because `_cim_standard_forge_active` is only set while `HeroWindowCrafting`/`HeroWindowCraftingConsole` is open — the gear icon opens a different window. Re-enabled `salvage`, `apply_weapon_skin`, `extract_weapon_skin`, `upgrade_item_rarity_*`. Investigating the cosmetics_tweaker side separately.

## 0.3.3-dev (2026-05-07) — Disable mutating standard-forge recipes (cosmetic interaction bug)
User reported that applying a skin to a CWV Imperial Longsword via the standard forge "permanently overrode an existing cosmetic option". The mutating synth functions (`salvage`, `apply_weapon_skin`, `extract_weapon_skin`, `upgrade_item_rarity_*`) all call `mirror:update_item` / `mirror:remove_item`, which writes through `_update_data` and may corrupt the canonical state of mod-injected items (CWV weapons in particular have their own session-regenerated state). Disabled all four until we understand the failure mode. Additive recipes (`craft_random_item` / `craft_weapon` / `craft_jewellery`) remain enabled — they only call `mirror:add_item` with a fresh backend_id, the proven-safe Athanor pattern.

## 0.3.2-dev (2026-05-07) — Resolve craft target via item.key/ItemId; restore CWV in random pool
- **Use `get_item_from_id(bid)`** to resolve the dropped item's `.key` and `.ItemId` (which `_update_data` populates from the ItemMasterList lookup). v0.3.1 used `get_item_masterlist_data` which returns the ItemMasterList entry but doesn't carry the lookup key, so the clone target was nil and the synth fell through to the random pool every time.
- **Re-include `cwv_*` keys in the random pool** — user wants modded variants available there too.
- Added `[cim] Cloning chosen weapon: <key>` echo whenever the synth picks up a real weapon from the slot.

## 0.3.1-dev (2026-05-07) — Specific-weapon crafting + exclude CWV from random pool (superseded by 0.3.2)
- **Drop a real weapon to clone it.** When the player puts a non-default-rarity item in the craft slot, the synth now uses that item's exact `ItemId` instead of rolling random within the slot type. Drop a halberd → get a copy of that halberd.
- **Excluded `cwv_*` keys from the random pool.** They live in `ItemMasterList` from the character_weapon_variants mod and were being rolled, producing duplicates of items the player already owned.
- Random pick is still the fallback when the slot is empty or holds a default-rarity placeholder.

## 0.3.0-dev (2026-05-07) — Persistent modded inventory + filter + loadout restore
Three new behaviors aimed at making modded play feel like a separate sandbox:

1. **Standard-forge crafts now persist across game runs.** Items created via the inventory crafting tab are saved to `mod:set("forged_weapons")` (same layer as the Athanor) and re-injected on `BackendManagerPlayFab._create_interfaces`. New `via_mirror` flag on each saved entry distinguishes mirror-path items (Athanor + standard forge → restored via `backend_mirror:add_item`) from MIL-path items (legacy `/forge_confirm` → restored via MoreItemsLibrary). Public helper: `mod._cim_register_craft(backend_id, weapon_data)`.

2. **Toggleable inventory filter** — VMF setting *"Show only modded weapons in inventory"* (default off). When on, hooks `BackendInterfaceItemPlayfab.get_filtered_items` and drops every item whose `slot_type` is `melee`/`ranged`/`trinket`/`ring`/`necklace` AND whose `backend_id` doesn't match a modded pattern (`cwv_*`, UUID format, or registered in `_forged_weapons`). Crafting materials and cosmetics are unaffected.

3. **Modded loadout restore** — VMF setting *"Restore modded loadout each session"* (default on). Each time the player equips a modded item, the (career, slot) → backend_id is saved to `mod:set("modded_loadout")`. After re-injection on session start, those slots are re-equipped via `backend_items:set_loadout_item`, so switching to vanilla and back doesn't wipe the modded loadout.

New helpers exposed on the mod object: `mod._cim_register_craft`, `mod._cim_unregister_craft`, `mod._cim_is_modded_backend_id`.

## 0.2.7-dev (2026-05-07) — Diagnostics: synth echoes + `/craft_recent`
Added per-craft `mod:echo` showing the rolled item key + rarity + backend_id, plus a console command `/craft_recent` that lists every backend-mirror item flagged as new (post-load additions). Used to diagnose why crafted weapons weren't appearing in the inventory grid.

## 0.2.6-dev (2026-05-07) — Defense-in-depth: drop crafting* requests at the PlayFab queue
Two changes so a stray `crafting*` PlayFab request can never trigger the EAC kick:

1. **`craft()` no longer falls through to the original** when the forge is active. Previously, an unrecognized recipe (e.g. one we haven't synthesized yet) delegated to vanilla `craft()`, which enqueued an `ExecuteCloudScript` request with `send_eac_challenge = true` (`playfab_request_queue.lua:44`). In modded realm the EAC client is unavailable, so the response triggers `playfab_eac_error` (reason 511) → "Backend rejected the challenge response" → quit. Now we silently drop unrecognized recipes with an `mod:echo` instead.

2. **Added a `PlayFabRequestQueue.enqueue` hook** that drops any `crafting*` cloud-function request while the forge is open. Catches every known PlayFab crafting RPC: `craftingSalvage`, `craftingRandomItem`, `craftingSpecificItem`, `craftingRerollProperties`, `craftingRerollTraits`, `craftingUpgradeRarity`, `craftingApplySkin2`, `craftingExtractSkin`, `craftingDowngradeDust`. Other PlayFab traffic (achievements, daily quests, etc) continues to flow normally.

## 0.2.5-dev (2026-05-06) — Hook Console UI variants (real cause of "Backend rejected" kicks)
The inventory crafting tab on PC uses the **Console** UI classes (`HeroWindowCraftingConsole`, `CraftPageCraftItemConsole`, etc), not the desktop variants. v0.2.4 only hooked the non-Console classes, so `_cim_standard_forge_active` was never set, the commit-block never engaged, the craft request short-circuit never fired, the original `craft()` enqueued an EAC challenge to PlayFab, EAC client unavailable in modded realm → `BACKEND_PLAYFAB_ERRORS.ERR_PLAYFAB_EAC_ERROR` (511) → "Backend rejected the challenge response" → quit.

Fix: extended the lifecycle hooks to also cover `HeroWindowCraftingConsole.on_enter`/`on_exit`, and added all `*Console` CraftPage classes (`CraftPageCraftItemConsole`, `CraftPageRollPropertiesConsole`, `CraftPageRollTraitConsole`, `CraftPageUpgradeItemConsole`, `CraftPageApplySkinConsole`, `CraftPageConvertDustConsole`) to the `_MATERIAL_GATED_PAGES` list. Backend hooks (`_get_valid_recipe`, `craft`) are class-level and already fire regardless of UI variant.

## 0.2.4-dev (2026-05-06) — Fix duplicate `commit` hook (root cause of "Backend rejected" kicks)
v0.2.2 introduced a second `BackendManagerPlayFab.commit` hook in `standard_forge.lua` alongside the existing Athanor commit hook in the main module. VMF detected it as a rehook and **silently dropped the second registration** (warning at startup: "Attempting to rehook active hook [commit]"). The Athanor hook only checks `_custom_forge_active`, so during standard-forge use the commit was NOT blocked → mutations leaked to PlayFab → anti-tamper rejected the session.

Fix: single commit hook in main module checks both flags. `standard_forge.lua` now stores its active flag on `mod._cim_standard_forge_active` instead of installing its own hook.

## 0.2.3-dev (2026-05-06) — Implement craft-from-scratch (random item / weapon / jewellery)
- `craft_random_item`, `craft_weapon`, `craft_jewellery` now produce a new item via `backend_mirror:add_item` (purely additive — same pattern as the Athanor, no anti-tamper risk).
- Picks a random `ItemMasterList` entry filtered by: career's `can_wield`, slot_type matching the input placeholder if any, excluding weapon_skin / magic / promo rarities.
- Result rarity = `exotic`, power_level = 300. Properties/traits are empty by default; players can roll them via the Athanor (`B`) or the standard forge's reroll recipes once those are wired up.
- The input slot item is left intact (vanilla would consume it, but that triggers anti-tamper).

## 0.2.2-dev (2026-05-06) — Re-enable standard forge with Athanor commit-block pattern
Same `BackendManagerPlayFab.commit` no-op pattern the Athanor already uses for property/trait edits. The crash in v0.2.0 was caused by `CraftingManager.craft` calling `Managers.backend:commit()` after each craft, which pushed our local mutations to PlayFab → anti-tamper rejection. With the standard forge state tracked via `HeroWindowCrafting.on_enter`/`on_exit`, the commit hook now no-ops both Athanor sessions and standard-forge sessions. Mutations are session-only — they vanish on game restart when PlayFab reloads the canonical inventory.

## 0.2.1-dev (2026-05-06) — Disable standard forge hooks (PlayFab anti-tamper crash)
v0.2.0 mutated existing inventory items (`mirror:remove_item`, `mirror:update_item`) which triggered PlayFab's "Backend rejected the challenge response -1" anti-tamper response, kicking the session. The Athanor works because it only ADDS new items (server-tolerant of unknown GUIDs); modifying server-tracked items causes desync rejection. Re-disabled `standard_forge.lua` until the recipes are redesigned to use the additive pattern.

## 0.2.0-dev (2026-05-06) — Standard Keep forge support (BROKEN — see 0.2.1)
- Added `standard_forge.lua` module that enables the Keep's standard crafting menus (Olesya's Cauldron / Lohner's forge) in modded realm without requiring crafting materials.
- UI: post-hooks `setup_recipe_requirements` on 6 CraftPage classes (`CraftItem`, `RollProperties`, `RollTrait`, `UpgradeItem`, `ApplySkin`, `ConvertDust`) to force `_has_all_requirements = true`.
- Backend: hooks `BackendInterfaceCraftingPlayfab._get_valid_recipe` to bypass material validation; hooks `craft()` to short-circuit the PlayFab roundtrip and synthesize results locally.
- Implemented recipes: `salvage`, `apply_weapon_skin`, `extract_weapon_skin`, `upgrade_item_rarity_*` (4 tiers).
- Stubbed (falls through to vanilla, will fail in modded): `craft_random_item`/`craft_weapon`/`craft_jewellery`, `reroll_weapon_properties`/`reroll_jewellery_properties`, `reroll_weapon_traits`/`reroll_jewellery_traits`, `convert_blue_dust`/`convert_orange_dust`.

## 0.1.0-dev (2026-05-05) — Initial split from Weapon Tweaker
- Spun out the Athanor crafting system from `weapon_tweaker` into its own mod.
- Crafted weapons saved under `mod:set("forged_weapons")` in the new `cim` namespace; weapons saved under the old `wt` namespace are not migrated.
- All Athanor forge UI hooks, the B hotkey opener, item creation/persistence, and the `craft_dump` diagnostic command moved here.
