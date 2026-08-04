# Cosmetics Tweaker — Changelog

## 0.9.186-dev (2026-08-04) -- per-wearer re-wield coalescer + mid-destroy guard (#1145) [untested]

- Client CTD fix. A single host illusion click fans out over four independent
  sync channels, and each one drove a wield PULSE on the same husk, so one click
  produced 8 full husk re-wield cycles in 220 ms (2026-08-03 client log). That
  churn collapsed the husk's destroy+respawn into ONE frame; the stranded old
  husk's locomotion extension then polled the dead game object id for 33 frames
  to the engine fatal `third_person_idle_fullbody_animation_control.lua:69`
  (via `player_husk_locomotion_extension.lua:59`, an unguarded
  `GameSession.game_object_field` read).
- New owner module `_cos_rewield_coalescer.lua`. Every wield pulse this mod
  initiates -- `_ensure_offhand_mesh` and `mod._la_native_pulse` -- now enqueues
  per wearer instead of firing inline. The drain runs once from `mod.update` and
  executes AT MOST ONE pulse per wearer per frame; same-frame duplicates merge
  and the newest request wins. The queue is swapped out before executors run, so
  a pulse that re-enters cannot recurse within a frame.
- Mid-destroy guard: immediately before executing, the wearer's husk game object
  is re-checked with `GameSession.game_object_exists`, the same gate vanilla uses
  at `simple_husk_inventory_extension.lua:59`. A husk whose game object is gone
  gets its pending pulse DROPPED, never queued across the respawn -- the fresh
  husk re-derives appearance through the normal spawn path.
- `_la_reconcile` now queues the paint re-apply into the pending drain when the
  pulse was coalesced, so deferral cannot silently swallow the re-paint.
- Diagnostics (always-on, bounded to 200 lines): `[cos:1145] DRAIN depth= ...
  executed= merged= dropped_dead_go=` and `[cos:1145] DROP wearer= ... reason=`.
- Regression: `cos_issue1145_coalescer_marker`, `cos_issue1145_coalescer_live`
  (drives the real queue and proves 4 same-frame requests execute exactly once),
  `cos_issue1145_mid_destroy_guard` (proves a dead wearer's pulse is dropped, not
  executed). Marker constant and the check that reads it live in the same file,
  avoiding the #1148 scope-loss class.
- No new hook, no RPC, no `World.destroy_unit`.

## 0.9.185-dev (2026-08-03) -- cold-load persistence contract locked; clear command repaired (#25) [verify-fix][untested]

- New named regression check cos_la_cold_load_contract_25: seeds LA hat,
  illusion, and offhand records, discards the in-process mirror, reloads from
  the persisted setting, and drives the real restore consumers, so the
  persistence pipeline can no longer silently unwire while checks stay green.
- Real bug fixed: /cos_persist_clear wrote the setting directly and left the
  module mirror stale, so the next save resurrected every cleared record after
  restart. Clears now go through LA_PERSIST.reset_all(), which also wipes
  offhand records per the command's wipe-all contract.
## 0.9.184-dev (2026-08-03) -- husk-hat paint failures name the hat (#697) [verify-fix][untested]

- A residual LA paint failure now emits the armoury key and vanilla key on the
  printf-backed alert channel instead of a keyless error, so the next failure
  identifies the hat without a debug-channel session.
## 0.9.183-dev (2026-08-02) — #518 solo-visible deus-yield probes [diag]

- **#518 diagnostics: solo-visible probe coverage for the CW deus-yield path [diag].** The pinned live-test falsifier ("the log records the wielded weapon with a non-empty skin= value") had no solo-visible emitter - the only skin= printf repo-wide is CWV's husk-wield line, remote-only, and both #518 failure-path decisions logged via _dbg only (invisible with user mod-logging OFF). New owner module `_cos_518_probe.lua` (the entry file sits at its decomposition ceiling) carries a bounded emitter `mod._cos518_emit` (engine printf only, rawget-guarded, `[cos:518]` prefix, deduped per key, capped at 16 records per channel, no chat) plus three probes the entry wires in:
  - **OWNER-WIELD probe**, called from the existing consolidated `SimpleInventoryExtension._wield_slot` hook_safe body (no new hook registration): on every LOCAL wield anywhere in a Chaos Wastes run (mechanism "deus": Pilgrimage Chamber, map, mission) logs the wielded item key + the resolved skin the render path consumes (`slot_data.skin` - simple_inventory_extension.lua:259,2106; `item_data.key` - spawning_helper.lua:80) plus the deus-yield verdict. Deduped per (item,skin). One Solo run now discriminates upgrade-selection vs local-rendering vs saved-identity.
  - **PAINT-SKIP promotion**: the ingame LA-paint deus-yield skip in `_apply_la_offhand_to_units` now also emits a deduped-per-backend_id printf (previous _dbg retained).
  - **HUSK-MISS promotion**: the husk mesh-swap authored-variant-unavailable miss in the `BackendUtils.get_item_units` hook now also emits a deduped-per-armoury_key printf (previous _dbg and the existing dedup'd chat warning retained).
  - Offline contract lock: `qa/lua/tests/test_cos_deus_yield_policy.lua` extended with 5 suites - executes the extracted emitter (prefix, printf guard, per-key dedupe, 16-per-channel cap, channel independence, inert-without-printf) and pins the module wiring, the three emit sites, the (item,skin) dedupe key, the mechanism gate, the retained _dbg lines, and the single-`_wield_slot`-hook invariant. (#518)

## 0.9.182-dev (2026-08-01) — #704 borrowed-family owner boundary [verify-fix]

- Borrowed matching-key hand pools now distinguish vanilla apply compatibility
  from CWV presentation ownership. Mod-owned skins are excluded unless an exact
  hand declaration explicitly admits their canonical owner.
- Updated the existing bounded #704 census to prefer canonical owner metadata,
  eliminating the false positive on Sword+Mace's own donor-keyed row while
  identifying Dawi Mace/Cudgel contamination even when its matching key is a
  valid Empire mace family.
- Hardened the live component-pool regression to reject mod-owned sources.

## 0.9.181-dev (2026-08-01) — #641 semantic offhand identity merge [not-started]

- Loremaster shield rows now merge into each hand pool by the same semantic
  component identity used by presentation, instead of blindly appending.
- A Cosmetics-authored component wins over a generic provider row with the
  same identity, preserving its independent name, flavor text, and icon while
  leaving distinct shield identities and saved/network data unchanged.

## 0.9.180-dev (2026-08-01) — publish reviewed #504 extraction [not-started]

- Re-staged the already-reviewed contextual glow-button owner extraction after
  applying the repository's visibility-orthogonality ruling from closed #328.
- Runtime behavior is unchanged from v0.9.179-dev. This entry gives the public
  Workshop transaction a fresh broker-owned version while the incomplete #504
  architecture umbrella remains outside the test queue.

## 0.9.179-dev (2026-08-01) — #504 contextual glow-button owner [not-started]

- Moved the Edit Glow button's family/open-state policy binding, contextual
  refresh, styling, and widget construction into one idempotent owner.
- Preserved the host customization view's position, input, and draw ownership;
  no hook, RPC, polling, persistence, item identity, or renderer path changed.
- Added behavioral create/refresh/idempotence coverage and ratcheted the
  Cosmetics entry decomposition ceiling from 9,808 to 9,740 lines.

This is structural progress only. The #504 umbrella remains incomplete and does
not enter the in-game test queue.

## 0.9.178-dev (2026-08-01) — #504 command-lifecycle owner [not-started]

- Moved the lazy regression registry/runner and the three LA persistence
  maintenance commands into one idempotent command owner at their historical
  registration position.
- Preserved every command name, late runtime-check order, context-absent skip,
  and persistence schema while adding no hook, RPC, renderer, or lifecycle path.
- Added behavioral command/check-count coverage and ratcheted the Cosmetics
  entry decomposition ceiling from 9,915 to 9,808 lines.

This is structural progress only. The #504 umbrella remains incomplete and does
not enter the in-game test queue.

## 0.9.177-dev (2026-08-01) — #796 exact glow preview ownership [verify-fix]

- Bound each newly spawned cosmetic-browser weapon unit to the exact active
  item and illusion before the existing glow painter runs, while preserving a
  dirty editor transaction only for that same identity.
- Apply and Restore Default now advance VT2's native `loadout_sync_id` once so
  the separate inventory character preview rebuilds immediately without
  leaving the inventory screen.
- Kept exact/family identity checks fail-closed and added no hook, RPC, or
  polling path. Added policy and source-contract coverage for the refresh edge.

## 0.9.176-dev (2026-08-01) — #48 magic-family selection gateway [verify-fix]

- Added one default-off **Show Weavebound and Shyish Illusions** option. The
  families remain hidden by default, but can now be revealed, selected, and
  handed to the existing manual Edit Glow transaction.
- Preserved the equipped-skin guard and vanilla illusion-row geometry. The
  gateway does not auto-open the editor or change Apply/rollback behavior.
- Extracted the visibility policy, added pure default/reveal coverage, and
  ratcheted the Cosmetics entry ceiling from 9,948 to 9,915 lines.

## 0.9.175-dev (2026-08-01) — #504 modded-illusion swap owner [not-started]

- Extracted all eight modded-realm illusion selection, crafting, and completion
  hooks into one idempotent owner with its fake backend-id and pending-request
  state. Hook order and CIM-at-fire-time yielding are unchanged.
- Kept the malformed local-craft completion guard with the request producer so
  a future split cannot separate the empty-result defense from its cause.
- Added behavioral hook-cardinality, idempotence, safe custom-key lookup, and
  runtime-owner coverage. Ratcheted the Cosmetics entry ceiling from 10,194 to
  9,948 lines and made the new owner mandatory in decomposition QA.

This structural slice does not complete #504 and does not require live testing.

## 0.9.174-dev (2026-08-01) — #48 CIM exact-instance glow persistence [not-started]

- Apply now mirrors one bounded, versioned item-and-illusion glow blob into
  CIM's existing opaque `custom_glow` field when the edited item is CIM-crafted.
  Cosmetics remains the sole renderer and authoritative local provider.
- Equipment and preview rehydration import CIM only when Cosmetics has no exact
  local value and the blob proves the same backend item and illusion. Dev CIM
  remains preferred when both streams are installed; missing or incomplete
  sibling APIs fail closed to Cosmetics' standalone persistence.
- Restore to Default clears CIM only when the stored illusion identity matches,
  and the bounded CIM restore callback rebinds already-realized local units.
- Added schema, identity-drift, malformed-sibling, stream-precedence, exact-clear,
  runtime-wiring, and appearance-census regression coverage.

This slice does not complete #48: the magic-skin gateway and the once-per-session
CIM notice when Cosmetics is absent remain separate work.

## 0.9.173-dev (2026-08-01) — #504 exact-item offhand session owner

- Extracted pending offhand selections, Apply baselines/markers, legacy-shape
  migration, and snapshot/restore into one exact-backend-item/per-hand session
  owner. Durable persistence, rendering, hooks, and peer transport retain their
  existing boundaries and consume the same table identities.
- Routed the complete-set rebroadcast adapter through the extracted migration
  owner so current transition/hot-join behavior is preserved after the split.
- Ratcheted the Cosmetics entry ceiling from 10,229 to 10,194 lines and added
  pure Lua coverage for item/hand isolation, empty baselines, one-way migration,
  retained Apply maps, and clone-on-restore semantics.

## 0.9.172-dev (2026-07-26) — #923 exact Loremaster icon identity

- Loremaster's Armoury offhand icons now resolve from the exact target weapon
  family and exact selected primary skin instead of borrowing one
  representative icon across compatible mace, spear, sword, and shield
  families.
- An absent or rejected LA mapping now retains the native item icon. Saved
  selections restore through item type, hand, and Armoury identity, while
  provider-owned icon asset names remain local and are not persisted or sent
  over Cosmetics RPCs.
- Added executable coverage for the distinct Kotbs01 mace and spear icons,
  pending-preview selection over stale equipped state, native fallback, and
  exact restore ownership.

## 0.9.171-dev (2026-07-26) — #377 glow editor Information-panel host

- The manually opened Glow editor now replaces the right-side Information
  panel's contents instead of covering the weapon preview. Its geometry and
  toggle position derive from the live vanilla `info_window` scenegraph node.
- The editor scenegraph now uses vanilla's `scale = "fit"` screen transform, so
  the custom controls and native panel share one resolution/UI-scale space.
- The native Information frame, illusion controls, model preview, and
  controller navigation remain vanilla-owned. Closing the editor restores the
  original information contents; the transaction also restores them before a
  wrapped vanilla draw error is propagated.
- Exact item+illusion persistence, explicit Apply, Restore Default, committed
  badges, and the separate #796 live-preview adapter are unchanged. Added
  executable layout, hitbox, and host-restoration regressions.

## 0.9.170-dev (2026-07-26) — #629 complete-set peer-ready replay

- A different peer appearing now re-arms the existing owner's durable
  appearance publication. Replay waits for an exact career, both realized
  equipped weapon records, career-scoped hat/outfit cache, and every persisted
  exact-item offhand hand to converge with its restored selection.
- Managed hat/outfit state is replaced atomically from the current career,
  clearing stale or wrong-career cosmetics while preserving weapon illusions.
- Hat, outfit, shield, vanilla offhand mesh, and custom-illusion publication
  now propagates an actual queued/emitted result. The pending edge clears only
  when every composed operation is accepted; unproven careers and transport
  failures remain retryable.
- Extracted the complete-set replay runtime from the frozen entry file and
  added Lua 5.1 composition coverage for staggered slots, stale clearing, and
  career/send-failure retries.

## 0.9.169-dev (2026-07-26) — #270 native UnitSpawner semantics

- Removed Cosmetics' engine-global non-resident-unit short circuit from
  `UnitSpawner.spawn_local_unit`. The wrapper now delegates exactly once and
  applies Material-Hijack decoration only to the returned live unit.
- Optional Cosmetics headpieces remain fail-closed at their narrower
  `AttachmentUtils.create_attachment` ownership boundary.
- Added regression coverage proving Cosmetics cannot return a fabricated nil
  from unrelated native gameplay spawns.

## 0.9.168-dev (2026-07-25) — #1002 bounded Equipment reset [not-started]

- Opted Cosmetics into Mod Tweaker's owner-level setting transaction. A full
  Equipment DEFAULT/profile restore now coalesces hat, Grail Knight set,
  cosmetic-unlock, glow-sync, and TPE-flush work to at most one call each.
- Added bounded `[cos:1002]` evidence and shared Equipment transaction coverage.
## 0.9.167-dev (2026-07-22) — #149 retained Loremaster shield transition repair [not-started]

- Keep-to-mission replay now resolves the active weapon slot from the common
  equipment-owned field used by both local and husk inventory extensions,
  preserving the direct husk field only as a compatibility fallback.
- A mesh-mismatch paint skip is no longer recorded as a successful replay.
  The bounded reconciler verifies the wielded item, re-wields only from a safe
  lifecycle edge, repaints the realized authored shield, and coalesces the
  generation only after that retained postcondition succeeds.
- Added pure Lua, runtime, and source-contract regressions for local/husk slot
  shapes, bounded replay, and the no-false-success invariant.

## 0.9.166-dev (2026-07-22) — #922/#925 fade and live presentation refresh [not-started]

- After Cosmetics applies an illusion, the retained top-left customization
  card is now refreshed from the same exact backend item and canonical
  `UIUtils.get_ui_information_from_item` resolver that vanilla uses. The
  adapter mutates only vanilla's five owned content fields; it does not rebuild
  the viewport or widget.
- Cosmetics' existing singleton loadout-write hook now publishes bounded,
  scalar-only local presentation invalidations. Loremaster clone identities are
  normalized to their stable vanilla cosmetic key before another mod consumes
  them. No engine object, callback, custom resource, or network identity enters
  shared state.
- Added bounded `[cos:925]` evidence and runtime/offline coverage.

### #922 shared custom-model camera fade

- Restored explicit FadeSystem enrollment for dynamically linked owner and husk
  hats without reverting the exact-donor Encarmine plume/material fix.
- Enrollment submits one complete inventory-and-attachment snapshot rather than
  a partial hat-only list that could evict weapon membership.

## 0.9.165-dev - 2026-07-22 - #918 semantic custom-illusion peer sync [not-started]

- Cosmetics-owned custom weapon illusions now reuse the bounded semantic
  per-hand transport for Cosmetics-capable peers while remaining absent from
  unsafe vanilla numeric skin traffic.
- The exact-family resolver rejects missing or cross-family definitions,
  preserves committed per-instance hand choices, and emits explicit clears
  across respawn, hot join, loadout sync, and state transitions.
- Peers without Cosmetics retain the safe vanilla base model. Added pure policy,
  wire-order, lifecycle, and runtime regression coverage without a new RPC.

## 0.9.164-dev - 2026-07-21 - #749 exact renderer-resource closure

- Loremaster loot previews, live owners and remote husks; custom hats; the
  Grail Knight set; and both embedded Material-Hijack writers now share one
  strict V2 residency contract. Texture transactions require every texture and
  realized material handle before the first native write.
- Animated Material-Hijack frames resolve a fresh live material instead of
  retaining a C handle across renderer lifecycle edges. The mission item
  preview also proves its shading environment before re-pointing the world.
- Removed the obsolete executable shared-material LA painter. Any failed proof
  now preserves the donor/vanilla appearance with bounded log-only evidence.
- Added exhaustive offline coverage for null handles, sparse/malformed texture
  sets, atomic write ordering, parent-material order, and every active writer.

## 0.9.163-dev - 2026-07-21 - #282 session-owned material packages

- Re-read the four current logs attached through #927, #930, #937, and #940.
  The three fatal sessions all emit `#ID[5ab1500d] not unloaded`, while the
  previous lifecycle reports every `cosmetics_tweaker_mh` release complete and
  its Lua delayed queue empty. The fatal sessions then stall in
  `PatchedResourcePackage::unload`. The non-fatal control has the same balanced
  mod references, disproving shutdown `NOT unloaded` volume as the producer.
- Material-Hijack donor packages now hold one mod-owned reference for the
  process session. Cosmetics no longer unloads them from the pre-state callback,
  the post-`StateIngame.on_exit` hook, `mod.update`, or `mod.on_unload`;
  `PackageManager.destroy` is the sole teardown owner after global consumers.
- A reinitialized ownership ledger adopts an existing `cosmetics_tweaker_mh`
  reference rather than incrementing it. This is a refcount safeguard, not a
  claim that Cosmetics hot reload is supported. The bounded `[cos:282]
  session-retained` line reports held, exact, over-count, and missing references
  at every StateIngame exit.
- Lua coverage locks repeated-transition dedupe, ledger reinitialization, absence
  of early-release APIs/hooks, and final PackageManager-owned release.

**Verify:** equip **Midnight Purpure and Azure**, enter and leave at least three
missions (including one Chaos Wastes transition if available), then quit
directly from the final keep or mission. The newest log must show
`[cosmetics:LOAD] v0.9.163-dev`, each `[cos:282] session-retained` line must
report `over=0 missing=0`, and shutdown must not emit `#ID[5ab1500d] not
unloaded`, `PatchedResourcePackage::unload`, or a package deadlock error.

## 0.9.162-dev - 2026-07-21 - #950 partial attachment links

- Preserve Cosmetics' pre-C-API dead-unit guard while filtering mixed-validity
  attachment maps. Valid shared node pairs now reach vanilla linking; only
  absent optional pairs are skipped, and zero-valid maps remain a clean no-op.
- Added a pure attachment-link policy and Lua regression coverage for complete,
  partial, numeric-index, and zero-valid maps. This prevents custom meshes such
  as Pusfume's first-person arms from being stranded at world origin because an
  unused fingertip node is absent.

## 0.9.161-dev - 2026-07-19 - reconciliation: issue 883 icons over the shipped 0.9.160

- Version-number collision: the Workshop's 0.9.160 (uploaded 14:05) carries the issue 154/373/650 fixes but not issue 883; master's 0.9.160 carries both. This build ships the union under 0.9.161-dev.

## 0.9.160-dev - 2026-07-19 - #883 exact Loremaster inventory icons

- Source-backed root cause: Loremaster's Armoury weapon selections persist the
  Armoury key directly, while the Cosmetics bridge maps only contain cloned
  hat/outfit identities. The inventory provider therefore rejected valid
  per-instance weapon selections before consulting LA's authored icon table.
- The shared inventory-icon policy now accepts direct keys only when they have
  positive `SKIN_LIST` membership, resolves the exact backend item's current
  skin before any representative bridge paint, and fails closed for unknown or
  mismatched main-hand identities. Shield cross-family choices retain their
  deliberate representative-icon fallback; dual-weapon icon ownership remains
  on the primary/right-hand selection.
- Added bounded, file-only `[cos:883]` outcome diagnostics (32 distinct states
  maximum), a complete appearance contract, runtime coverage, and Lua 5.1
  regression cases for direct keys, exact-skin precedence, fallback behavior,
  and unknown-key rejection. No global LA/vanilla icon tables are mutated.

## 0.9.159-dev - 2026-07-19 - #154 #373 #650 log-sweep defect fixes [untested]

### #154 husk cache never populated for cross-char weapon slots [untested]

- Root cause (2026-07-18 sweep, every co-op log): the husk render surfaces read
  the LA equip store by the wielded item's TEMPLATE only (the
  `BackendUtils.get_item_units` mesh gate and the post-wield repaint's
  `stored_key == wielded_template` match), but the
  `CosmeticUtils.update_cosmetic_slot` weapon-illusion emit stores entries
  under the cosmetic SLOT name (`slot_melee`/`slot_ranged`). Those entries
  were stored yet unreachable, so every cross-char husk slot logged
  `[cos:sync] decision=no-op(cache-or-kind-miss) cache_entry=false` and the
  cosmetic never rendered on teammates. Native weapons masked the miss via the
  vanilla wire skin; cross-char slots have that skin wire-substituted (issue
  371 family), leaving the mod store as the only delivery path.
- Fix: new `_cos_husk_cache_bridge.lua` wraps the single reconcile entry point
  (`mod._la_reconcile`, issue 264 shape) on every peer: a slot-keyed
  offhand/illusion entry is mirrored under the wearer's live wielded template
  (same entry table, identity alias) and reconciled under that item-matchable
  key; the revert receiver sweeps every alias by identity. Direct
  template-keyed writes always win over mirrors; mirror emits one deduped
  `[cos:sync] event=cache-mirror` line. Wearer-scoped only (issue 268 rule).
- Expected post-fix probe: `[cos:sync] ... event=cache-mirror wearer=... slot=slot_melee -> template=...`
  followed by `husk_meshgate ... cache_entry=true ... decision=resolve-mesh`
  instead of the former `no-op(cache-or-kind-miss)` for cross-char slots.

### #373 weave/magic shield rows absent from LA receiver tables [untested]

- Root cause (2026-07-18 solo log, FS 23.05-23.24): breton sword-and-shield
  RESOLVE ended `resolved_unit=nil ready=false ... kind=texture` because the
  weave (`_magic*`) and glow-event/Shyish (`_runed*`) shield units were absent
  from `_la_shield_parity.lua`'s exact receiver allow-list, so the pure-paint
  LA pick dead-ended on a shader with no diffuse slot (LA_SYNC_MODEL 6.5).
- Added the complete decompile-derived receiver rows for every character's
  shield family: breton +1, empire +4, dwarf +5, wood_elf +2, imperial +2
  (each row cites its scripts/settings skin-table source; receivers are the
  same-directory suffix-stripped plain siblings, keeping the 204/266
  same-family exactness rule).
- Added a boot-time, log-only, capped validation pass (`[cos:373]
  RECEIVER-GAP`, max 10 rows + overflow line) that walks the live WeaponSkins
  tables at LA bridge init and printf-flags any magic/runed shield skin whose
  family lacks a receiver row, so the next missing row self-reports.

### #650 icon compositor mapping gaps and residency spam [untested]

- Mapping closure (from the 36-file sweep + decompile): mapped
  `es_1h_mace_shield_skin_01` and `skin_02_runed_06` (both wpn_emp_mace_02
  family, item_master_list_weapon_skins.lua:734 /
  weapon_skins_morris_2024.lua:320) to the authored mace primary, and the
  Weavebound breton shield unit (`wpn_emp_gk_shield_01_magic_01`) to the
  existing gk_shield_01 art so weave picks compose after the 373 swap.
- Stated split: skins `skin_04`, `skin_04_magic_01/_02`, `skin_05` use the
  different wpn_emp_mace_03 mesh, and the empire kite shields
  (`wpn_emp_shield_02/_02_runed_01/_03_runed_01/_05`) plus the LA
  basic1/2/3 custom meshes have no authored 80x80 layer yet - they stay
  fail-closed to the native icon and self-report via the collapsed
  diagnostic below.
- `missing-primary-resource` class: `ui_icon_availability` now distinguishes
  a genuinely absent resource from the boot window where the shipped
  material is engine-resident (`Application.can_get("material", ...)`,
  the fail-closed residency-guard pattern) but the VMF atlas injection is not
  serving it yet; the latter reports as `transient-*-ui` and self-heals on a
  later grid refresh instead of miscounting as missing.
- Diagnostic spam collapsed: the per-bid descriptor rows now dedup per
  DISTINCT gap (unmapped-primary keyed by skin, unmapped-offhand by
  offhand unit + armoury key, resource/transient classes once per session)
  instead of per instance tuple - the up-to-38-rows-per-file sweep pattern
  becomes a handful of rows.

## 0.9.158-dev - 2026-07-19 - #656 #658 #696 #704 #730 authored appearance integration and bounded evidence [diagnostics-armed]

- Added a vanilla-geometry Reikland griffin cape variant for the red Foot Knight
  outfit (#656). The authored-outfit provider reuses the existing inventory,
  owner, remote-husk, and score replay path; only the cape diffuse changes, and
  the vanilla normal/packed/first-person maps remain intact.

### #658 Purpure/Azure cross-career availability [verify-fix-coop]

- Adds independent, default-off Mercenary, Huntsman, and Foot Knight sharing controls while Grail Knight remains the native default owner.
- Resolves the exact wearer's vanilla hat/outfit fallback for every outgoing peer appearance, persisted replay, and hot join; unknown careers fail closed instead of guessing a donor.
- Preserves explicit saved career choices across the set master switch and keeps render-state invalidation keyed to the exact peer/career pair.

### #696 material-manager boundary diagnostics [diagnostics-armed]

- The shipped material-residency guard did not emit a single `[cos:696]`
  skip in twelve recent sessions, while the same six `MeshObject` lookup
  warnings remained invariant at keep load. This disproves the earlier
  non-resident-material hypothesis; `Application.can_get("material", path)`
  succeeds before the warning.
- Both embedded Material-Hijack bind sites now emit one bounded `bind-start` /
  `bind-end` bracket per binding convention, authored unit-name, slot and
  material immediately around `Unit.set_material`. The start line also records
  mesh count and how many meshes expose the requested slot. The 24-key session
  cap and stable authored identity prevent respawns/transitions from creating
  log spam.
- The diagnostic does not suppress or replace the native bind. Its purpose is
  to distinguish a warning emitted inside `Unit.set_material` from a warning
  emitted by the preceding `World.spawn_unit`, and to name the resource path
  required for the eventual narrow fix.

**Diagnostic (solo):** enter the keep once with the same equipped cosmetics.
Attach the log section containing the six `MeshObject` warnings plus the
adjacent `[cos:696] bind-start` / `bind-end` lines. A warning synchronously
bracketed by a pair identifies that exact binding convention/unit/slot/material.
An unbracketed warning excludes these two traced calls for that instant but does
not, by itself, prove which other spawn or compiled-material boundary emitted it.

### #704 Sword+Mace picker-family census [diagnostics-armed]

- Captures the exact post-vanilla illusion rows plus live right/left component pools when CWV Sword+Mace customization opens.
- Reports missing or foreign families as bounded `[cos:704]` evidence without changing the picker, adding transport, or assuming the reported Bardin hammer's source.

### #730 score-lineup authored armor replay [verify-fix]

- Retains the exact Purpure/Azure armor identity through the score preview's hidden spawn callback and paints once after the mesh becomes visible.
- Invalidates on hide/show and replacement edges without per-frame material writes, sharing the proven inventory-preview visibility contract.

## 0.9.157-dev - 2026-07-19 - #794 #795 #796 glow editor geometry, badge, and live preview [verify-fix]

### #794 glow slider track geometry

- Fixed the glow editor's horizontally displaced click/drag values. VT2 passes
  the style selected by a UI pass directly to `held_function`; the slider
  selected `track` but then incorrectly searched for a nested `track` style,
  dropping the rendered track's 90px label/gap offset.
- Moved cursor normalization, padded hotspot bounds, and thumb-centre placement
  onto one pure track-geometry helper. The offline Lua suite covers both
  endpoints, quartiles, clamping, translated/scaled geometry, and malformed
  zero-width tracks.
- In-game verification: open Edit Glow and click/drag the visible left edge,
  quarter points, midpoint, and right edge at multiple UI scales/resolutions.
  Each RGB/intensity slider must select the matching value and keep its thumb
  centred under the cursor; labels and value text must not change a slider.

### #795 committed glow badge on the illusion selector

- Moved the illusion selector's committed-glow badge pass to the existing
  `UIWidget.init` pre-hook. Vanilla creates every illusion button with
  `UIWidget.init` inside `_setup_illusions`; appending the pass afterward left
  the live widget's positional `pass_data` shorter than its pass list, so the
  new badge could not render reliably after Apply.
- Added an exact pure classifier for the `illusions_root` weapon-illusion
  definition. Unrelated icon widgets and already-initialized widgets fail
  closed, while every button cloned from the shared definition receives the
  badge pass before `pass_data` is built.
- In-game verification: Apply a custom glow and confirm its tinted badge appears
  immediately on the exact selected illusion, survives close/reopen and restart,
  does not leak to another instance/skin, and disappears on Restore Default.

### #796 live glow on the customization preview model

- Routed dirty glow-slider state to the exact `LootItemUnitPreviewer` units
  rendered by `HeroWindowItemCustomization`. The previous live helper repainted
  only the local player's inventory-extension units, which cannot reach the
  customization pane's separate preview world.
- Added a pure backend-item + illusion ownership policy. Stale previewers,
  asynchronous rebuilds, dead units, and a newly selected illusion fail closed
  instead of receiving another item's transient glow.
- Apply and Cancel now repaint the same preview target. Cancel/Restore copies
  the selected illusion's registered native material vectors back immediately;
  slider movement performs local material writes only and creates no RPC or
  per-frame network retry.
## 0.9.156-dev - 2026-07-19 - #835 callable Vector3 constructor [verify-fix]

- Synchronized the shared appearance primitive's protected callable constructor
  boundary. This keeps every standalone consumer byte-identical and prevents a
  future Cosmetics transform path from rejecting retail's callable-table
  `Vector3` binding.

## 0.9.155-dev - 2026-07-18 - #566 harness context preconditions for the glow regression check [untested]

- `cosmetics_tweaker.lua` (regression scaffold only): `_rt_register(name, fn, opts)`
  now accepts `opts.precondition` - a function returning true when the asserted
  runtime context exists, or (false, "reason") when it legitimately does not.
  The /cos_regression_test runner reports such checks as an explicit
  `SKIP: <name> -- context absent: <reason>` result (chat echo + engine `printf`,
  visible with mod logging off), distinct from PASS and FAIL, plus a trailing
  `=== N skipped (context absent) ===` summary. A THROWING precondition reports
  as FAIL, never a skip. Same harness contract as enemy_tweaker 0.7.53-dev
  (issue 512); kills the context-dependent false-failure class of issue 511.
- `_cos_runtime_checks.lua`: `material_settings_templates_loaded` declares the
  engine-catalog population gate (`MaterialSettingsTemplates` /
  `WeaponSkins.skins` boot tables) as its precondition instead of FAILing with
  "global not loaded" when run in a context where the catalogs are not
  populated. The issue 566 inversion shipped in 0.9.89-dev is preserved
  unchanged: the check requires exactly the eight weapon material template
  families vanilla registers (weapon_material_settings_templates.lua:4-115) and
  separately locks the lone Nornaz skin
  (`deus_dw_1h_axe_skin_06_runed_02_white`) mapping to the intentionally
  UNREGISTERED `white_glow` fallback (no-template fail-closed resolution, the
  issue 610 contract) - the suite never demands a `white_glow` registration
  vanilla does not perform. With the catalogs populated, a missing family or a
  drifted Nornaz mapping stays a true FAIL.
- Note: the 2026-07-18 session log attached to issue 566 shows
  `material_settings_templates_loaded` PASSING on 0.9.151-dev; the four
  remaining suite failures in that log belong to issues 612 / 583 / 641 / 204,
  not to issue 566.
## 0.9.154-dev - 2026-07-18 - four-surface custom-skin wire contract (#421) [diagnostics-armed] [coop-required]

- Correlated both 2026-07-18 attachments: the host ran Cosmetics v0.9.147-dev, the non-Cosmetics client crashed in the Old Musket albedo texture path tracked by #742, and neither log exercised a `ct_*` skin or emitted `[cos:421]`. Those logs therefore neither verify nor refute #421.
- Consolidated the fourth, GameSession, `CosmeticUtils.update_cosmetic_slot` surface onto the same pure custom-skin-to-`n/a` policy used by the three `rpc_add_equipment` wrappers. Runtime coverage now fails unless all four surfaces register.
- Made the temporary slot substitution exception-safe: the live custom skin is restored even if a wrapped vanilla sender raises a Lua error.
- Added `/cos_421_diag`, which separately proves catalog symmetry, four-surface registration, custom-skin substitution, restoration, and whether the live reproduction actually has a custom skin equipped.
- Routed that diagnostic's player lookup through the existing teardown-safe player boundary, so gathering evidence cannot itself call the engine network backend during title/transition teardown.
- Added Lua regression coverage for custom and vanilla policy behavior, source wiring, exception restoration, and the bounded diagnostic discriminators.

**Co-op diagnostic:** on the Cosmetics peer, equip `ct_es_mace_gk_shield_01` (or a `ct_es_heavy_spear_deus_*` skin), run `/cos_421_diag`, then have a non-Cosmetics peer join and transition keep → mission → keep. Expected: `catalog=PASS surfaces=PASS policy=PASS restore=PASS live_custom=1`, `[cos:421] wire skin null (<surface>)` for each exercised surface, and no client `NetworkLookup.weapon_skins` failure. Attach both logs.

## 0.9.153-dev - 2026-07-18 - strict LA texture residency gate (#749) [verify-fix-coop]

- #749: the active Loremaster offhand paint path now fails closed before `Unit.set_texture_for_materials`. Missing/throwing `Application.can_get`, non-resident textures, malformed slot/path data, or a non-live unit all skip the native C setter and emit one bounded `[cos:749]` diagnostic instead of trusting `pcall` to catch a renderer crash it cannot catch.
- Added a byte-identical `_lib_resource_residency.lua` contract in `tools/shared_lib` and Cosmetics so future borrowed-renderer fixes have one strict resource-proof shape instead of another local `can_get` variation.
- Audited the shared `WeaponAppearance.apply_textures` helper from the #749 site inventory. It remains a latent hazard if a future consumer feeds borrowed textures through it, but current production evidence shows the active callers are transform-only, so this patch leaves stable consumers untouched and fixes the observed LA bridge boundary first.
- Added Lua regression coverage for strict texture proof, malformed data, absent units, local/shared helper byte identity, and the active LA bridge source seam.

**Co-op verify:** with Cosmetics + Loremaster’s Armoury, have host/client preview/equip LA shield/offhand texture variants in lobby and mission, including a client viewing a host and a host viewing a client. Expected: no renderer/AV crash during customization preview, inventory preview, mission entry, or remote husk rendering. If a texture is not resident, the affected shield may degrade to no LA repaint and the log should contain at most one bounded `[cos:749] residency SKIP` line per reason/path/slot/context.

## 0.9.152-dev - 2026-07-18 - session-score weapon skin crash floor (#734) [verify-fix-coop]

- Added a Cosmetics-side receiver floor for the session-score/player-list weapon-skin read path. `CosmeticUtils.get_weapon_skin_name` now rawget-checks weapon-slot `NetworkLookup.weapon_skins` ids before vanilla's strict lookup can crash the client; an unknown id degrades to no skin and logs one bounded `[cos:734]` line.
- Preserved the existing sender-side safe substitution model: custom/LA/CWV skin identity must travel through mod-owned channels, while vanilla profile/session-score sync receives only vanilla-safe ids such as `n/a`.
- Extended the Cosmetics wire tests to prove the unknown numeric id observed in #734 does not call the strict vanilla decoder, vanilla ids still pass through, non-weapon slot behavior remains vanilla-owned, and hot reload does not stack the new hook.

**Co-op verify:** with a Cosmetics-capable client and a peer whose `NetworkLookup.weapon_skins` table differs, play to a score/session-score update after custom or CWV weapon skins have been equipped. Expected: no `weapon_skins does not contain key` CTD; the receiving log may show one `[cos:734]` fallback line and the score/player-list weapon skin degrades to vanilla/no-skin instead of crashing.

## 0.9.151-dev - 2026-07-18 - per-instance glow policy core (#48) [untested]

- #48: a committed glow must belong to ONE exact inventory instance wearing ONE exact illusion. Authoring was already exact-instance (persistence keyed `backend:<id>|skin:<skin>`, matching the issue 628 synthetic-item contract and the issue 702 exact-commit pattern), but two paths still let a single item's glow bleed onto items that merely shared the family. Both are closed by a new pure policy module, `_cos_glow_instance_policy.lua`, now the single owner of instance identity, runtime rebinding, and remote matching.
- **Local illusion-swap leak.** The runtime paint map is keyed by bare `backend_id` while persistence is keyed by backend id AND skin. `GlowPicker.restore_runtime_for` returned early on a persisted miss without clearing, so swapping the illusion on an instance that had a saved override for the PREVIOUS illusion kept painting the old colour. The policy now returns an explicit `clear` decision and the runtime + identity entries are dropped.
- **Remote family-wide bleed.** `_remote_glow_context_matches` skipped the skin gate entirely when no skin was resolvable, and its slot/name/template gates only bound when both sides were non-nil. An unconstrained payload therefore matched EVERY glow-capable unit on that wearer. The policy fails closed to resident vanilla when no skin is resolvable, per the conditional-presentation rule in `docs/WEAPON_APPEARANCE_STANDARD.md`. An empty skin segment stays a real constraint rather than degrading into a wildcard. No new RPC, no payload shape change, and no modded key added to any vanilla `NetworkLookup` table (issue 278/371 class).
- **Durable per-item OFF.** The renderer (`_cos_glow.lua`), the badge policy, and the composite icon builder already consumed `state.disabled`, but nothing produced it and `_shape_display_state` stripped it, so a saved OFF was rewritten into a colour by the next Apply. `disabled` now round-trips through shape/commit. The picker checkbox that authors it is NOT built yet - see the deferred note below.
- Net line delta in the frozen `cosmetics_tweaker.lua` is ZERO (the file is untouched; both consumers `mod:dofile` the stateless policy directly). `_cos_glow.lua` shrank by 4 lines.
- 15 new suite tests in `qa/lua/tests/test_cos_glow_instance_policy.lua`. The `test_cos_glow_lifecycle` identity-key assertion follows the invariant to its new owner and additionally pins the picker's delegation.

**Deferred (UI):** no in-picker control authors `disabled` yet, so the durable OFF state is reachable only by an existing saved blob, not by a click. Full per-slot remote proof also still needs every `_bind_glow_unit` call site to supply slot/item context; where the receiver has no such evidence a declared constraint is treated as unproven rather than contradicted, which is deliberately permissive.

**Verify (solo):** give a Weavebound/Bretonnian longsword instance a custom glow via the editor and Apply. Equip a SECOND item of the same illusion family - it must stay vanilla. Swap the first item's illusion to a different one with no saved override: the old colour must NOT follow it. Close and reopen the inventory, then restart the game: the original instance keeps its glow.

**Coop verify (2 players):** wearer applies a glow to one weapon and carries a second glow-capable weapon with none. The observer must see the custom glow on exactly the authored weapon and resident vanilla on the other, across a hot-join and a keep/mission transition.

## 0.9.150-dev - 2026-07-18 - husk hat LA paint foreign-key guard (#697) [verify-fix-coop]

- #697: the husk-side hat create step (`PlayerHuskAttachmentExtension.create_attachment` wrap) fetched the LA mod handle unconditionally, so cosmetics-authored variants (GK Purpure/Azure hat, custom hats) fell through to `la.apply_new_skin_from_texture` with a key LA does not own - LA's `funcs.lua:65` indexes `SKIN_LIST[key]` and nil-derefs, logging `[husk-hat-create] paint err` on every such husk hat spawn (17 hits across the 2026-07-17/18 logs, all `cos_gk_purpure_azure_hat_variant`). Visual result was unaffected (GK_SET's own applier had already painted); the LA call was a misdirected no-op that errored.
- The hook now derives `(variant, la)` through the shared `_resolve_la_variant` resolver - identical to the `_apply_la_on_unit` hat branch - so `la` is non-nil only when the armoury key actually resolved from LA's `SKIN_LIST`. Cosmetics-side variants skip the LA painter with a debug marker (`LA paint n/a ... cosmetics-side variant`); genuine LA hats paint exactly as before. Net-zero line delta in the frozen main file.

**Coop verify (2 players):** wearer equips the GK Purpure/Azure hat, second player observes the wearer's husk: hat must render with the Purpure/Azure texture, and the newest log must contain NO `[husk-hat-create] paint err` lines. Then wearer swaps to a genuine LA hat (e.g. Pureheart): observer must still see the LA texture on the husk (`[husk-hat-create] paint <key> ... ok=true`).

- #696: embedded Material-Hijack now preflights material residency before binding. `replace_textures` guarded units, packages, and textures (issue 199) but bound `mat_to_use` / `mat_list` materials via `Unit.set_material` with no `can_get("material")` check, so a vanilla parent material outside the unit's spawn-time resource scope produced the engine's "Failed looking up material" warnings at level load (8/session across 3 hashes) and fallback rendering. Both set sites now skip the bind and keep the unit's current material when the material is not resident, logging one bounded `[cos:696]` line per unit+slot+material naming all three - that marker also separates this emitter from engine-side baked-material resolution at husk spawn, which logs without it.

**Verify (solo, level load):** load a mission with a `mat_to_use` cosmetic/variant equipped. If the "Failed looking up material" warnings persist WITHOUT any `[cos:696]` line, the emitter is the engine husk-spawn path, not Material-Hijack; any `[cos:696]` line names the exact unit/slot/material to chase.

- #233/#149/#203 family: ONE bounded replay reconciler now re-applies persisted LA appearance at peer-ready (remote player added / husk init), session-ready (StateIngame enter), and lobby-return edges - coalesced per (peer, slot, hand, generation), never per-frame, reusing the proven live-change apply path. This closes the "cosmetics only appear after I change something" class.
- #738: the husk identity human-gate is now local_player_id-aware (bot never owns slot 1), and skip lines print local_player_id/controlled - the 2026-07-18 "alias skip" ambiguity (host bots reading as the human) cannot recur.
- STATE-PULL hardening: the responder's two silent early-returns now log their reason host-side; an exhausted client pull re-arms once per reconciler edge instead of dying for the session.
- Rides the 0.9.148-dev #282 post-teardown package-release fix (first upload carrying it).
- 7 new suite tests + a runtime rt-check (cos_replay_reconciler_wired).

**Coop verify (2 players, both join orders):** wearer pre-equips LA shield illusion + hat + skin; cold-join and hot-join peers must see them on the husk with NO customization edit, surviving keep->mission->keep. `[cos:replay] edge=... applied=N` appears per edge; 3-player+bot check: [cos:698] skips show local_player_id=2/3/4 controlled=false only. Quit-to-desktop after transitions: `[cos:282] postcondition-ok`, no `not unloaded ... deadlock`.

## 0.9.148-dev - 2026-07-18 - post-world material-package release (#282) [verify-fix]

- Moved the embedded Material-Hijack skin-package release from the pre-teardown `on_game_state_changed("exit", "StateIngame")` callback to one post-call `StateIngame.on_exit` hook. Vanilla has destroyed player/preview units, entity systems, the level and world before the mod drops its reference, so the Purpure/Azure package no longer enters shutdown's delayed-unload queue merely because live units still consume it.
- Replaced the boolean load registry with a lifecycle ledger that distinguishes held references from engine-delayed releases. Entries remain observable until PackageManager actually removes the delayed handle; `/cos_regression_test` now fails on any retained Cosmetics-owned delayed package.
- Added bounded `[cos:282] release-complete`, `release-DELAYED`, and shutdown postcondition evidence. Added offline regression coverage for three repeated transitions, immediate shutdown with no PackageManager update frame, release retention/reconciliation, and exactly one post-StateIngame hook.

**Verify:** equip the Purpure/Azure outfit, complete at least three keep/mission or Chaos Wastes transitions, then quit immediately after the final return. The log must show `[cos:282] postcondition-ok` before manager destruction, with no `cosmetics_tweaker_mh` delayed package at `PackageManager.destroy`, no `#ID[...] not unloaded` fatal, and no shutdown fence stall attributable to this package.

## 0.9.147-dev - 2026-07-18 - exact dual-illusion persistence lifecycle (#702) [verify-fix-coop]

- Dual/offhand Apply now commits its durable owner record by exact backend item and hand before any live-model or peer delivery work. The previous save was nested under `player_unit` liveness and the LA sender's availability, so a valid inventory Apply could update the session preview while silently omitting the disk write.
- Selection queuing no longer requires a live keep player unit. When delivery is temporarily unavailable, the existing bounded self-rebroadcast path carries the already-persisted state after the owner equipment exists.
- Restart restore no longer consumes a CIM-owned exact instance before CIM/CWV finishes registering it. Exact pending instances retry every 0.5 seconds for at most 15 seconds; candidate resolution accepts only the saved hand, unit, and component skin (with a unique-unit legacy fallback), then fails closed to the native appearance.
- Engine-free coverage proves two same-family inventory instances remain isolated, Apply persists with no render owner, Follow Main clears only the selected exact hand, invalid identities fail closed, and source wiring retains the existing preview/mission/network replay surfaces.
- The bounded commit-and-peer-delivery transaction lives in `_cos_offhand_commit_policy.lua`; the frozen main-file size remains below its existing QA baseline rather than expanding the monolith.
- In-game check: customize the offhand of one dual weapon, press Apply, fully restart the game, and confirm that exact inventory instance keeps both its primary illusion and independently selected offhand while a second copy remains unchanged.

## 0.9.146-dev - 2026-07-17 - reconciliation build: #698 + #713 [verify-fix-coop]

- Reconciliation reship: two different builds were briefly uploaded as `0.9.145-dev` by parallel sessions. This unambiguous version carries BOTH the #698 career-scoped remote appearance identity (below) and #713's unlock-injection log demotion: the per-second `[unlock_all_frames]`/`[unlock_cosmetics]` lines now fire only on the first pass or when counts change (the injection still runs per mirror rebuild; `/cos frames_status` keeps live counters).

**Test:** #698 co-op checklist below, plus solo: idle in the keep 2+ minutes and confirm at most one line of each unlock marker in the newest log.

## 0.9.145-dev - 2026-07-17 - career-scoped remote appearance identity (#698) [verify-fix-coop]

- Fixed the host-side Grail Knight armor repaint recorded after a remote player changed to Foot Knight: `_la_equips_by_peer` was keyed only by Steam peer, while the husk armor replay accepted every cached `slot_skin` without proving that the record belonged to the husk's current career.
- Every LA material/mesh record now carries the exact human wearer's career from the live inventory/player identity. Host requests, authoritative broadcasts, deferred sends, acknowledged state pulls, hot-join replay, receivers, reconcile, and husk wield all preserve or validate that field. The shared RPC schema is now 2 so legacy unstamped state is dropped instead of guessed.
- A confirmed human career change removes mismatched and legacy unstamped records before vanilla husk wield/spawn. A bot sharing its owner's peer id is explicitly barred from consuming or purging that human store, preserving the #513 owner-alias boundary.
- Added a pure career-identity policy, runtime regression, and offline host/client/husk tests. The executable appearance contract now treats career change as a mandatory replay edge and records the exact #698 material scope without claiming in-game verification.

**Co-op verify:** equip the Purpure/Azure Grail Knight outfit, join another Cosmetics-matched peer, then switch that same remote peer to Foot Knight without restarting the lobby. The observer must see Foot Knight's own armor through spawn, wield, keep/mission transition, and hot join. Logs may show `[cos:698] HUSK career-change invalidated ...`, but must not show a later Grail Knight `HUSK wield-repaint` on the Foot Knight. Repeat with a host-owned bot present; the bot must stay native and must not erase the human's current cosmetic state.

## 0.9.144-dev - 2026-07-17 - combined #695 + #481 reconciliation build [verify-fix]

- Reconciliation reship: two different builds were briefly uploaded as `0.9.143-dev` by parallel sessions. This unambiguous version carries both #695's startup backend-readiness guards and #481's exact Athanor offhand-preview ownership.

**Test:** verify the #481 Athanor shield-isolation checklist, then start a fresh modded session and confirm the console contains no `Requesting unknown interface` startup flood.

## 0.9.143-dev - 2026-07-17 - exact Athanor offhand preview ownership (#481)

- Closed the fail-open preview path recorded in `console-2026-07-17-17.50.57-10bc42ac-d630-48e0-95d8-f5de4cdc727c.log`: `LootItemUnitPreviewer` had an exact queued hand-unit path, but unreadable runtime `unit_name` metadata was treated as a mesh match and allowed an authored shield paint onto an unproven target.
- Pending-illusion backend fallback now requires the same normalized weapon family. Exact backend IDs still win, husks never consume the local customization fallback, and an offhand record must be present in that exact item type's current hand pool.
- The returned preview units now consume their corresponding `spawn_data[i].unit_name` evidence. LA and Purpure/Azure paints fail closed when the declared authored 1P/3P mesh does not match, and an exact independent row-2 component prevents a second whole-skin provider from repainting the same shield.
- Preserved the Athanor overview's legitimate melee and ranged previewers; no previewer destruction, new hook, RPC, polling loop, or guessed viewport ownership was added.
- Added Lua 5.1 and runtime regressions for exact LA/Purpure item isolation, same-family fallback, pool ownership, provider arbitration, and mismatched/missing preview targets.

## 0.9.142-dev - 2026-07-17 - pre-login backend warning flood fix (issue 695)

- Preserved the already-uploaded public source delta from the `vt2-cim-promo` ship worktree: offhand-selection restore and delayed instance prune probe `Managers.backend._interfaces.items` before calling `get_interface("items")`.
- Both paths already retried while the backend was unavailable; this only prevents the pre-login miss path from emitting the same unknown-interface warning every frame.

## 0.9.141-dev - 2026-07-17 - independent component flavor text (#641) [diagnostics-armed]

- Extended the shared item-card component descriptor from icon/name to icon/name/description, so an independently selected shield or offhand no longer inherits the primary weapon's flavor text.
- Component text resolves in one bounded order: authored component description, source illusion description, then readable component-safe fallback. It never exposes an internal localization key or falls back to primary-weapon copy.
- Authored Cosmetics description keys resolve only through `mod:localize`, while vanilla source-illusion description keys resolve through `_G.Localize`; a production-boundary regression prevents those ownership paths from being conflated again.
- Added the authored Blood-Bloomed Bouclier description to its canonical shield option and enrich persisted selections from that canonical pool before using stale saved metadata.
- Preserved the existing singleton `UIUtils.get_ui_information_from_item` hook, all four vanilla return values, persistence schema, and RPC payloads. No new hook, wire field, or per-frame owner was added.

**Co-op diagnostic verify:** with two parity-matched players, select The Blood-Bloomed Bouclier and confirm owner inventory/equipment/customization item cards show the shield description, not the primary weapon description. Repeat with a dual offhand that has only source illusion text, restart, transition keep -> mission -> keep, and confirm Hold-Tab titles and mixed-mod parity remain vanilla-safe. Draft PR evidence is structural; no in-game verification is claimed.

## 0.9.140-dev - 2026-07-17 - CWV dual-offhand remote identity (#583/#660) [verify-fix-coop]

- Fixed the exact failure recorded in `console-2026-07-17-04.34.02-36c165bb-5404-48cb-9b75-d8301c460b79.log`: Rain's Dual Axes offhand reached the host, but the husk validator compared its Saltzpyre axe unit with Bardin's vanilla `dr_dual_axes` pool and logged `SKIP(incompatible-hand-mesh)`.
- Cosmetics now consumes CWV's already fingerprint-validated per-peer/per-slot appearance descriptor and validates the offhand against `cwv_es_dual_axes` (or the corresponding exact CWV dual family). Missing providers, schema drift, stale bases, non-exact identity, and unregistered variants retain the vanilla family and fail closed.
- No new RPC, unit-path payload, per-frame work, or family inference was added. The existing bounded direct-mesh transport, package gate, and husk rebuild remain authoritative.

**Co-op verify:** customize the left/offhand of CWV Dual Axes on the client, Apply, and have the host observe it without another edit. The host log must show `decision=APPLIED-vanilla-mesh item_type=cwv_es_dual_axes identity=exact`, not `SKIP(incompatible-hand-mesh)`. Repeat with a second CWV dual family, transition, hot join, and reverse roles. A native Dual Axes control must continue to validate only against its native pool.

## 0.9.139-dev - 2026-07-17 - persisted offhand peer-ready replay (#233/#267) [verify-fix-coop]

- Kept the startup/state-change LA replay armed until the local inventory has a realized melee or ranged weapon slot. Previously the replay flag was consumed as soon as the player unit became alive, even when equipment was not ready, so a persisted pre-launch shield never entered the authoritative peer store and remained invisible to a joining client until a live cosmetic edit.
- Preserved the existing bounded emit deduplication, acknowledged pull-on-ready RPC, exact-item persistence, and live-change transport. No new RPC, polling owner, or asset payload was added.
- Extended the executable `cos_la_reconcile_and_pull_wired` runtime regression with empty-inventory and realized-weapon readiness cases.

**Co-op verify:** equip an LA shield, close the game, relaunch, then have a second player join without opening customization or changing the shield. The joining player must see the persisted shield immediately. Repeat through keep-to-mission transition and hot join; no live edit or weapon swap may be required. Run `/cos_regression_test` and require `PASS: cos_la_reconcile_and_pull_wired`.

## 0.9.138-dev - 2026-07-17 - runtime-owner decomposition

- Extracted the glow diagnostic commands and tick APIs, Loremaster command surface, and all 50 ordered runtime checks from the oversized entry module into explicit dependency-injected owners.
- Preserved command names, hook ownership, callback order, memory probe, Grail Knight verification API, and regression registration order without changing appearance behavior or transport.
- Added executable Lua 5.1 ownership/order/duplicate contracts. The entry module is now below its frozen file-size ceiling.

## 0.9.137-dev - 2026-07-16 - #650 composed shield glow contract [verify-fix]

### Changed

- The exact Mace + Shield instance now resolves one composed appearance
  descriptor containing primary skin, selected Bretonnian offhand, effective
  primary glow, icon layers, and the compatible shield material write.
- A committed custom glow remains authoritative. When no override exists, a
  glow-capable primary may contribute its source-defined native color; unknown
  or template-less native glows still fail closed.
- The runed Bretonnian shield's owner 1P/3P units and inventory hero preview
  consume the descriptor's `rune_emissive_color` write. The item-card glow mask
  consumes the same RGB bytes, so held shield and icon can no longer resolve
  different colors.
- GUI texture residency is now checked only by the icon adapter. A missing
  renderer material restores the native card but cannot suppress the held
  shield appearance.
- No new RPC, custom asset path, or backend ID enters peer transport.

### Regression coverage

- Offline tests require icon tint and held-shield RGB to agree, cover committed
  and native primary states, prove renderer-local icon failure does not erase
  the held descriptor, and retain exact-instance/cache/native-cell safeguards.
- `/cos_regression_test` now pins the composed shield material variable,
  brightness, intensity, and RGB alongside the icon layers.

### Verification

Equip Mace + Shield with a glow-capable mapped primary and `GK Shield (Red,
Runed)`. Confirm the shield glows in owner first person, owner third person,
and the inventory character preview, while the composed item icon shows the
same color. Apply a distinct RGB and repeat; an ordinary shield and an
unsupported item must remain unchanged. Tracking: GitHub issue #650.

## 0.9.136-dev - 2026-07-16 - #650 Lua compile-limit hardening

The unshipped 0.9.135 implementation crossed Lua 5.1's 200-local function
limit in the monolithic entry chunk. Renderer descriptor publication and the
bounded diagnostic ledger now live in `_cos_composite_icons.lua`, preserving
the live Mace + Shield behavior without consuming entry-chunk locals. An exact
`loadfile` regression test now compiles the entry during QA so this class of
failure blocks before packaging.

## 0.9.135-dev - 2026-07-16 - #650 live Mace + Shield composition [verify-fix]

### Fixed

- The live inventory adapter now replaces the native combined weapon icon in
  `content[hotspot_*][item_icon_*]`, matching `ItemGridUI`'s actual nested cell
  storage. The previous top-level write did not feed the native texture pass.
- The first live picker primary (`skin_02`) now uses the authored mace layer.
  The layer also recognizes the 2026 GOTWF
  `es_1h_mace_shield_skin_03_runed_05` variant, which was the active skin in the
  failed verification log.
- Compatible Mace + Shield items emit one bounded diagnostic per distinct
  skin/offhand/outcome. An unmapped identity now explains its native fallback;
  a working identity records `composed` or `cache-hit` without per-frame spam.
- Composite descriptors remain in a renderer-local weak table instead of being
  written onto backend item records. No custom texture name enters a loadout or
  peer transport path; peers without Cosmetics retain native icons.

### Regression coverage

- Offline coverage pins the GOTWF primary mapping, reasoned fail-closed
  outcomes, nested hotspot icon replacement, exact-instance cache behavior,
  shield composition, rune RGB, and unsupported-cell native restoration.

### Verification

Equip Mace + Shield, Apply the skin-03 GOTWF rune primary and `GK Shield
(Red)`, then reopen Equipment. The card must show the authored mace behind the
red shield. With the runed version of that shield, Apply a recognizable RGB and
confirm the neutral rune overlay takes that color. The log must contain one
`[cosmetics:650] descriptor composed` (or `cache-hit`) line for the exact skin
and shield; unsupported choices must state the fallback reason. Tracking:
GitHub issue #650.

## 0.9.134-dev - 2026-07-16 - #650 item-grid pass-data crash guard [verify-fix]

### Fixed

- Opening the gamepad inventory no longer lets the layered-icon adapter insert
  render passes after `UIWidget.init` has already built its positional
  `pass_data` array. That mismatch shifted the native `item_tooltip` pass onto
  a nil data entry and crashed in `ui_passes.lua`.
- Composite-icon and glow-badge grid passes now decorate the widget definition
  in a `UIWidget.init` pre-hook. A live-widget guard rejects any later mutation,
  while `ItemGridUI.init` is refresh-only.

### Regression coverage

- Offline coverage pins both grid decorators before vanilla widget
  initialization, requires the live-widget `pass_data` guard, and rejects any
  ItemGrid post-init enrichment path.

### Verification

Open Equipment with a controller/gamepad UI and select the melee inventory.
The item grid must render without a crash, and mapped Mace + Shield cards must
retain their layered primary/shield icon. Tracking: GitHub issue #650.

## 0.9.133-dev - 2026-07-16 - #650 layered Mace + Shield icon proof [verify-fix]

### Added

- Inventory and equipment item grids can now render an exact-instance layered
  icon descriptor in the order native rarity/background, primary weapon,
  offhand shield, optional glow mask, then native frame. The first Mace +
  Shield picker primary (`es_1h_mace_shield_skin_03`) and the authored
  Bretonnian shield cutouts form the initial
  catalog; unmapped primaries and shields retain the native icon.
- The Bretonnian rune overlay is eligible only for the exact
  `wpn_emp_gk_shield_02_runed_01` offhand identity. Its tint reads the durable
  Apply transaction's exact rune RGB and requires positive saved intensity;
  ordinary Bretonnian shields and dormant rune state never inherit it.
- `_cos_composite_icons.lua` exposes the engine-free descriptor and cache/cell
  restoration policy for later crafting and Hold-Tab adapters. Those surfaces
  intentionally remain native until they carry exact identity and local
  renderer-material proof.

### Regression coverage

- Offline coverage pins layer order, exact RGB conversion, renderer-resource
  fallback, exact-instance isolation, rune-only gating, cache refresh, and
  native-icon restoration when a grid cell is reused. `/cos_regression_test`
  adds `issue650_composite_icon_contract`.

### Verification

Select the first Mace + Shield primary and a mapped Bretonnian shield. The
inventory/equipment card must preserve its native rarity and frame while the
mace sits behind the shield. Select the exact runed Bretonnian shield, Apply a
rune color, and confirm only that shield gains the same RGB overlay without
reopening the game. Switch the same grid cell to an unmapped item and confirm
its native icon is restored. Tracking: GitHub issue #650.

## 0.9.132-dev - 2026-07-16 - #629/#639/#641 combined item presentation [verify-fix-coop]

### Fixed

- Inventory, equipment tooltips, and hold-Tab loadout snapshots now use one
  component presentation descriptor. Weapon-and-shield items compose the
  standalone primary weapon name with the independently named shield and use
  the shield-owned icon. Dual weapons compose the independently named offhand
  while retaining the primary weapon icon.
- Hold-Tab no longer assumes a backend instance ID that vanilla does not send
  in its loadout RPC. It resolves presentation from the existing parity-gated
  peer/slot cosmetic cache. No custom resource or localization key is added to
  the vanilla wire payload.
- CIM's post-vanilla Tab correction now gives the Cosmetics descriptor
  precedence instead of overwriting it with the primary skin icon.
- Missing peer state, mod parity, option metadata, or renderer-local icon
  resources fail closed to vanilla presentation.

### Regression coverage

- Lua coverage proves shield and dual icon ownership, standalone-primary name
  selection, peer-cache and no-cache behavior, renderer-resource fallback, and
  CIM provider precedence/no-clobber behavior.

### Verification

With host and client on Cosmetics `0.9.132-dev` and CIM dev `0.8.86-dev`, equip
an independently customized shield and inspect the item in inventory and while
holding Tab on both peers. The title must read `Primary Weapon + Shield Name`
and the icon must be the shield-owned icon. Repeat with a dual weapon: the
title must include its independently named offhand but the icon must remain
primary-owned. A peer without the required mod/resource must receive only the
resident vanilla fallback.

## 0.9.131-dev - 2026-07-16 - issue 610 native glow defaults + Restore to Default

### Fixed

- Opening Customize Glow on an untouched illusion no longer shows a fixed
  magenta/pink color or forces the weapon pink (issue 610). The editor now reads
  each illusion's native glow from its MaterialSettingsTemplate and shows those
  values. The reconstruction normalizes the brightest channel to 255 and derives
  intensity from the native HDR magnitude, so a later Apply reproduces the
  original glow faithfully (e.g. purple_glow 3/1/9 shows as 85/28/255 at 1.0).
- Opening the editor no longer paints or persists anything. The per-item runtime
  paint entry is created only on an explicit slider edit or Apply, so merely
  opening, closing, or switching illusions can never mark state dirty, apply a
  color, or write an override.
- Cancelling a preview on an item with no committed override now repaints the
  native template on the live weapon, so closing without Apply visibly rolls the
  glow back instead of leaving the preview color.
- Illusions whose template is unknown or absent (baked magic meshes, Stylish
  no-template runed skins) fail closed to neutral white at intensity 0 instead
  of inventing a color.

### Added

- Restore to Default button in the glow editor. It clears the per-item and
  per-variant override for the exact item plus illusion, rebroadcasts the
  cleared coop payload to remote peers, repaints the native template on the live
  weapon, and drops the inventory/illusion badge. It is greyed out when no
  committed override exists.

### Note

This entry was authored as 0.9.125-dev in a parallel workstream and renumbered
to 0.9.131-dev when merged on top of the 0.9.126 - 0.9.130 Grail set line; the
brief 01:49 Workshop upload of the unmerged build is superseded by this one.

### Verification

Confirm `[cosmetics:LOAD] v0.9.131-dev`. On the cosmetic-change screen select a
glow-capable illusion (a runed Veteran skin and a Shyish-Infused magic skin) and
press EDIT GLOW: the sliders must show that illusion's own color and the weapon
must keep its native glow (no pink). Change a slider and Apply: only that item
plus illusion should show the tinted badge. Press Restore Default: the override
clears, the badge disappears, and the weapon returns to native glow. Cancel a
preview (close without Apply): the weapon rolls back to native. Run
`/cos_regression_test`; `glow_picker_native_defaults_610` and
`glow_manual_editor_button_377` must pass. Two-player: after Restore Default the
remote client's copy of that weapon returns to native on the wearer's next
re-wield. Also spot-check the 0.9.126 - 0.9.130 Grail set work still present
(Purpure/Azure icons and component illusion names).

## 0.9.130-dev - 2026-07-15 - #629 finalized Grail set icons

### Changed

- Replaced the three vanilla donor placeholders with the user-authored icons for
  `Couronne de la Lune`, `Midnight Purpure and Azure`, and
  `The Blood-Bloomed Bouclier`.
- Kept the existing icon keys, GUI materials, renderer injections, item
  registration, and resource-package entries so every inventory and cosmetic
  selection surface consumes the same canonical artwork.
- Hardened the offline Grail set asset contract against accidentally restoring
  the donor icons by checking each authored PNG's signature and exact output
  size.

### Verification

Confirm `[cosmetics:LOAD] v0.9.130-dev`. Inspect the helmet and outfit in the
Grail Knight cosmetics screen, then inspect the shield from a compatible
Kruber weapon's independent offhand row. Confirm all three use the new
purple-and-navy artwork in inventory, cosmetic selection, and preview popups.

## 0.9.129-dev - 2026-07-15 - #641 independent component names / #639 approved Grail copy

### Changed

- Added stable, separately qualified localization identities for offhand-weapon
  and shield illusion components. Unauthored component names fall back to the
  localized source illusion instead of exposing an internal key.
- Composed customization hover copy as `Primary + Offhand/Shield`, while
  leaving primary illusion names under vanilla row-one ownership.
- Added `/cos_offhand_name_inventory`, which emits the live deduplicated naming
  queue for incremental authoring across vanilla, DLC, and installed CWV pools.
- Preserved the #639 approved names and descriptions for `Couronne de la Lune`,
  `Midnight Purpure and Azure`, and `The Blood-Bloomed Bouclier` when combining
  the localization and component-name changes in this release.

### Compatibility

- Component names remain presentation-only. Saved choices still use exact
  backend item, hand, source skin, and unit identity; peer replay continues to
  use the existing bounded direct-mesh and authored-shield payloads.

### Verification

Confirm `[cosmetics:LOAD] v0.9.129-dev`. Open a native dual weapon, a CWV dual
weapon when installed, and a weapon-and-shield customization screen. Hover the
component row and confirm the label reads `Primary + Offhand/Shield`; unauthored
rows must show localized source names, never raw keys. Run
`/cos_offhand_name_inventory` and `/cos_regression_test`; the latter must pass
`issue641_independent_offhand_names` and `issue629_grail_knight_set_contract`.
Inspect all three Purpure/Azure set items and confirm the #639 approved names
and descriptions remain exact across inventory and cosmetic-selection views.

## 0.9.128-dev - 2026-07-15 - #639 Grail Knight set localization

### Changed

- Finalized the three Purpure/Azure set names: `Couronne de la Lune`,
  `Midnight Purpure and Azure`, and `The Blood-Bloomed Bouclier`.
- Replaced the temporary color summaries with the approved lore-friendly
  descriptions for the moonlit Couronne helm, the bequeathed Bretonnian
  panoply, and Kruber's four-rose, gouttes-de-sang shield tale.
- Kept the VMF localization table and item-registration fallback table in exact
  agreement, with regression coverage for all six player-facing strings.

### Verification

Confirm `[cosmetics:LOAD] v0.9.128-dev`. Inspect all three set items in the
inventory and cosmetic-selection views. Each must show its finalized name and
description without donor text, raw localization keys, or a repeated title.

## 0.9.127-dev - 2026-07-15 - #629 inventory-preview lifecycle fix

### Fixed

- Deferred the Purpure/Azure outfit material override until the inventory hero
  preview has completed its hidden-to-visible transition. The vanilla preview
  no longer restores the donor outfit material one frame after the custom
  outfit was applied.
- Invalidated the bounded preview cache while the mannequin is hidden so a
  subsequent hide/show or respawn reapplies the outfit exactly once, without
  per-frame material writes.
- Added lifecycle regression coverage for hidden spawn, first visibility,
  steady state, hide/show, and replacement mesh behavior.

### Verification

Confirm `[cosmetics:LOAD] v0.9.127-dev`. Equip the Purpure/Azure outfit and
open the inventory character preview. Verify the custom outfit remains visible
after the mannequin appears, after changing tabs or heroes, and after closing
and reopening inventory. Issue #629 still requires co-op verification for its
remote-player presentation surfaces.

## 0.9.126-dev - 2026-07-15 - #629 authored outfit correction

### Changed

- Replaced the Purpure/Azure Grail Knight third-person outfit diffuse with the
  author's latest revision, correcting the remaining incorrectly colored cloth
  swath while retaining the finished purpure, azure, white, and
  blackened-silver treatment.
- Preserved the donor outfit unit, material bindings, face/skin/hair surfaces,
  normal and combined maps, first-person texture, rig, and custom icon. This
  revision changes only the authored third-person outfit diffuse.

### Verification

Confirm `[cosmetics:LOAD] v0.9.126-dev`. Equip the Purpure/Azure outfit and
verify the corrected cloth on the inventory character preview, live third
person, lobby/team presentation, and a remote client. Confirm Markus's face and
the existing helmet and shield remain correct through a mission transition.

## 0.9.125-dev - 2026-07-15 - #629 authored shield texture refresh

### Changed

- Replaced the Purpure/Azure Shield of Honour Renewed diffuse with the author's
  latest heraldry: the revised rose vine, expanded blood-drop field, white
  fleurs-de-lis, purpure/azure quarters, and retained silver/wood surfaces.
- Preserved the already-working shield unit, first-/third-person descriptors,
  UV family, normal and combined maps, custom icon, and Cosmetics replay path.
  This update changes only the authored shield diffuse.

### Verification

Confirm `[cosmetics:LOAD] v0.9.125-dev`. Equip the Purpure/Azure shield and
verify the revised heraldry in the inventory hero preview, live first person,
live third person, and on a remote client. Swap away and back, then enter a
mission and confirm the shield does not revert or disappear.

## 0.9.124-dev - 2026-07-15 - #629 authored Purpure/Azure textures

### Changed

- Replaced the Purpure/Azure Grail Knight outfit's third-person diffuse with the
  author's finished purpure, azure, white, and blackened-silver texture. The
  existing first-person outfit texture remains unchanged until a matching
  first-person edit is authored.
- Replaced the matching Pureheart helmet diffuse with the author's finished
  navy and blackened-silver texture.
- Preserved the extracted donor units and their original face, eyes, hair,
  skin, normal, packed-map, rig, fade, and physics behavior. This update changes
  only the two authored diffuse inputs; the working shield and render-surface
  repair from v0.9.123 remain unchanged.

### Verification

Confirm `[cosmetics:LOAD] v0.9.124-dev`. Equip the Purpure/Azure outfit and
Pureheart helmet, then verify the new colors on the inventory hero, live third
person, lobby/score presentation, and a remote client. Confirm Markus's face is
unchanged, the helmet uses the original Pureheart geometry, and the existing
Purpure/Azure shield still renders correctly. The first-person outfit remains
on its prior texture by design.

## 0.9.123-dev - 2026-07-15 - #629 Grail Knight render-surface repair

### Fixed

- Corrected the Purpure/Azure Shield of Honour Renewed descriptor to distinguish
  its exact vanilla first-person unit from the real `_3p` sibling. The shared
  mesh-safety gate now accepts and paints the shield on the live owner body and
  remote husks instead of limiting the result to item previews.
- Replayed the Purpure/Azure outfit on the inventory-screen hero's actual body
  mesh after HeroPreviewer finishes spawning it. Replay is cached by mesh
  identity, so view reopen and career respawn each apply once without repainting
  every frame.
- Replaced the outfit's unit-wide texture override with an extracted-donor
  material contract. Only `mtr_outfit` and `mtr_outfit_ds` receive the custom
  diffuse, combined, and normal maps; Markus's face, skin, eyes, hair, beard,
  teeth, and their original materials remain untouched. Missing donor materials
  fail closed before any texture write.

### Verification

Confirm `[cosmetics:LOAD] v0.9.123-dev`. Equip the Purpure/Azure outfit and
shield, then verify Markus's face is unchanged and the outfit is recolored on
the inventory hero and live third person. Verify the shield after mission entry
and melee/ranged swaps on the owner, then repeat with a second player to confirm
the remote husk receives the same shield model and textures.

## 0.9.122-dev - 2026-07-15 - #612 Encarmine donor material ownership

### Fixed

- Corrected the Encarmine Laurel override after in-game verification showed
  that armor and plume textures were reversed. The donor's geometry array is
  not its runtime mesh order: runtime meshes 1-3 reference the native helmet
  material, while meshes 4-6 reference the native feather material.
- Added a semantic compiled-scene contract that follows each runtime mesh's
  `geometry_index` to the donor material slot (`es_k_hat_base` versus
  `es_k_hat_feather`) before selecting the Encarmine texture family. This keeps
  the vanilla Laurel rig, plume physics, alpha, camera fade, normals, tangents,
  LODs, and controller behavior unchanged.

### Verification

Confirm `[cosmetics:LOAD] v0.9.122-dev`, then verify the Encarmine armor texture
is on the helmet and the cloth texture is on the plume in inventory preview,
live third person, score/lobby presentation, and on a remote client. Confirm the
plume still renders on both sides, jiggles, respects alpha and camera fade, and
that the vanilla Laurel helm remains unchanged.

## 0.9.121-dev - 2026-07-15 - #200/#612/#629 cosmetic surface parity

### Fixed

- Rebased the Encarmine helm on the exact vanilla Laurel donor scene and its
  native rig, plume controller, LODs, fade, normals, and alpha behavior.
  Corrected the compiled mesh order and restored the exact user-authored armor
  and cloth diffuse maps; only the donor's spawned material instances change.
- Registered the Purpure/Azure Shield of Honour Renewed as an independent
  offhand component across every compatible Kruber shield family, including
  Bretonnian Sword and Shield, Mace and Shield, and CWV families. The primary
  weapon illusion remains independently selectable.
- Unified authored-shield resolution for Cosmetics and Loremaster choices.
  Variants with a canonical model now spawn that exact 1P/3P model before
  material application in cosmetic/inventory previews, the owner body, remote
  husks, and score/lobby surfaces. This prevents LA textures from wrapping over
  the currently equipped shield on Spear and Shield and Mace and Shield.
- Persisted the custom shield's exact icon and identity per weapon instance,
  including a safe Cosmetics-only fallback when Loremaster's Armoury is absent.

### Verification

Confirm `[cosmetics:LOAD] v0.9.121-dev`. Verify the new helmet, outfit, and
shield on Bretonnian Sword and Shield plus another Kruber shield family; then
verify the final two LA shield choices on both Spear and Shield and Mace and
Shield across inventory preview, owner 1P/3P, and a remote client.
Also verify the Encarmine helm's plume physics, alpha, camera fade, surface
response, inventory preview, live owner, score screen, and remote husk.

## 0.9.120-dev - 2026-07-15 - #377/#629 Cosmetics presentation and Grail Knight set

### Added

- Added a matching Pureheart helm, Gallant of Parravon outfit, and Shield of
  Honour Renewed recolor in purpure, azure, white, and blackened silver.
- Reused the exact vanilla helmet, first-/third-person outfit attachments, and
  shield units. Only per-instance textures change, preserving native rigging,
  animation, physics, camera fade, preview, and husk behavior.
- Added network-safe vanilla fallbacks plus bounded appearance replay for
  Cosmetics peers; custom asset identities are never sent to unmodded peers.

### Changed

- Moved the persistent Edit Glow control down four pixels and replaced its
  plain border with the same `menu_frame_12` ornate frame used by CIM.
- Applied that exact 64x64 nine-slice frame contract to the glow popup and its
  Apply and Close controls, with renderer-safe shared frame construction.

### Verification

Confirm `[cosmetics:LOAD] v0.9.120-dev`, inspect the glow controls, then enable
**Grail Knight: Purpure and Azure Set** and equip all three pieces. Verify first
person, owner third person, inventory mannequin, score screen, and a second
player's remote-husk view.

## 0.9.119-dev - 2026-07-15 - #377 Edit Glow panel alignment [verify-fix]

### Fixed

- Replaced the free-standing `{1272, 380}` Edit Glow offset with an anchor
  derived from the 600x620 glow panel on the shared 1920x1080 virtual canvas.
  The 96px toggle now begins at x=1164, so its right edge aligns exactly with
  the panel's bottom-right edge at x=1260 instead of sitting wholly to its
  right.
- Added offline and runtime checks that pin the panel-relative anchor and reject
  the previous hard-coded placement.

### Verification

Confirm `[cosmetics:LOAD] v0.9.119-dev`, open weapon customization on a
glow-capable illusion, and inspect the Edit Glow toggle with the editor both
open and closed. Its right edge should align with the glow panel's right edge.

## 0.9.118-dev - 2026-07-15 - #612 Encarmine compiled-transform correction [verify-fix]

### Fixed

- Corrected the actual live regression behind the invisible feather. The v0.9.116 rig exporter used Blender's default `FBX_SCALE_NONE`, which wrote the skinned plume with an extra hidden 100x local unit conversion. Stingray's normal root conversion then left the helmet at a 100x imported world basis but compounded the plume to 10,000x. The authored texture alpha, compiled DDS, material binding, six dynamic weights, and Laurel bone rest transforms were all intact; the plume's relative compiled render transform was not.
- Export now uses `FBX_SCALE_UNITS`, preserving scale 1 on the armor, plume, and armature while retaining 744 double-sided plume faces, all 13 Laurel bones, six dynamic feather groups, the native Laurel controller, and FadeSystem enrollment.
- Added a mandatory post-export FBX round-trip gate plus a post-compiler bundle gate. They reject non-unit local/source basis scale, unequal compiled armor/plume basis, live plume bounds outside the Laurel-sized envelope, missing groups, and face/bone-count drift before deployment. The pipeline documentation now records this failure mode.

### Verification

Confirm `[cosmetics:LOAD] v0.9.118-dev`, equip **Encarmine Helmet** on Foot Knight, and inspect the feather in the inventory mannequin and live third person. Expected: the dark-charcoal feather is visible on both sides without rectangular haze, moves through the native Laurel controller, and the helmet fades with the character. Run `/cos_regression_test`; `issue612_encarmine_hat_contract` must pass.

## 0.9.117-dev - 2026-07-15 - #612 Encarmine live-material correction [verify-fix]

### Fixed

- Replaced v0.9.116's ambiguous fractional-alpha plus compiler-cut combination with an explicit cutout contract: alpha 0-15 remains transparent and every retained feather texel is authored at alpha 255. This preserves the measured feather silhouette while preventing the 0.5 compiler threshold from erasing it in the live character renderer.
- Reduced the v0.9.115 armor roughness response by a bounded 10% (paint 184 -> 166; metallic detail 122 -> 110). This restores a modest highlight closer to the Knights Encarmine outfit without returning to v0.9.114's mirror-like all-metal response.
- Added deterministic asset scripts and offline histogram/hash gates for binary plume alpha and the two-value armor roughness map. The rig, double-sided geometry, native controller, FadeSystem enrollment, and peer fallback contracts are unchanged.

### Verification

Confirm `[cosmetics:LOAD] v0.9.117-dev`, equip **Encarmine Helmet** on Foot Knight, and inspect both plume sides plus the helmet beside the Knights Encarmine armor in the inventory mannequin and live third person. Expected: the feather is visible as a clean dark-charcoal cutout with no rectangular film, and the helmet has a subtle metal highlight close to the outfit rather than reading flat/matte or mirror-like. Run `/cos_regression_test`; `issue612_encarmine_hat_contract` must pass.

## 0.9.116-dev - 2026-07-15 - #612 Encarmine plume cutout correction [verify-fix-coop]

### Changed

- Removed the <=15/255 alpha haze left across the recolored plume and enabled the texture compiler's native 0.5 cut-alpha path. The authored anti-aliased feather silhouette remains; the translucent rectangular film does not.
- Raised plume RGB by a measured 4x. Opaque median luminance moves from 22/255 to 88/255, keeping a visible dark-charcoal feather and its strand detail under VT2 character lighting instead of rendering nearly black.
- Re-exported the Laurel high-detail helmet and plume as one skinned FBX, preserving all 13 Laurel bones and six weighted dynamic feather joints. A same-name source `.bones` resource gives the compiled custom unit a real animation skeleton.
- Reuses the already-resident compiled Laurel controller at each bounded spawn surface. This preserves the original feather constraints/secondary motion without bundling or recreating Fatshark's unavailable state-machine source.
- Registers newly linked Encarmine attachments once with `FadeSystem.new_linked_units`, so camera intersection fades the custom helmet with its player instead of leaving an opaque hat over a faded body.
- Retained the verified self-contained armor/cloth material response from v0.9.115 and extended offline/runtime regression coverage to pin cut alpha, repaired texture and rig hashes, compiled bones, controller installation, and fade registration.

### Co-op verification

Confirm `[cosmetics:LOAD] v0.9.116-dev` on both Cosmetics peers. Equip **Encarmine Helmet** on Foot Knight and inspect the plume in inventory, keep/mission third person, hot join, and score presentation. Expected: a visible dark-charcoal feather silhouette with no translucent rectangle or black tape-like strip, visible detail on both sides, Laurel-like secondary motion while moving, and helmet fade matching the character when the third-person camera intersects him. The armor should retain its restrained Encarmine metal response. A peer without Cosmetics must still see Laurel. Run `/cos_regression_test`; `issue612_encarmine_hat_contract` must pass.

## 0.9.115-dev - 2026-07-15 - #612 Encarmine plume and material correction [verify-fix-coop]

### Fixed

- Replaced the plume's opaque material graph with the alpha-aware standard graph. The shader now consumes the supplied cloth diffuse alpha instead of rendering its transparent black background as a solid strip.
- Exported one reversed counterpart for each of the plume's 372 source faces. The alpha-cut feather now has 744 render faces and remains visible from either side under Stingray backface culling without relying on a material-side culling override.
- Corrected the mistakenly decoded PBR response maps. v0.9.114 treated almost the entire armor as metallic and gave it zero roughness; the new maps keep painted carmine at 8% metallic/72% roughness, gold and silver at 62% metallic/48% roughness, and cloth at 0% metallic with 72-95% roughness.
- Lifted the authored armor diffuse by 8% brightness and 10% saturation after comparison with the Knights Encarmine outfit reference. UV layout is unchanged and cloth alpha pixels are byte-identical.
- Added a reproducible Blender plume exporter, a before/after material contact sheet, asset hashes for all response maps and the FBX, and runtime/offline contract checks for alpha, face count, and material revision.

### Verification

Confirm `[cosmetics:LOAD] v0.9.115-dev` on both peers. Equip **Encarmine Helmet** on Foot Knight and inspect both sides of the plume in the inventory mannequin, keep/mission third person, a hot join, and the score screen. Expected: a feather-shaped black plume from both sides, no opaque rectangular background, brighter carmine paint, and restrained gloss with metal response confined to gold/silver regions. A peer without Cosmetics still sees Laurel. Run `/cos_regression_test`; `issue612_encarmine_hat_contract` must pass and neither log may contain a missing-resource error for `BD55DCA31255AAEC`.

## 0.9.114-dev - 2026-07-15 - #612 Encarmine spawn-only renderer [verify-fix-coop]

### Fixed

- Kept `cos_encarmine_hat` and every package-facing preview record permanently bound to the inventory-package-listed vanilla Laurel unit, preventing another fatal request for missing `BD55DCA31255AAEC.package`.
- Added a spawn-only renderer at the four final unit creation surfaces: inventory/career/score preview, local and bot attachments, remote-husk late attachment reconstruction, and bounded Cosmetics appearance replay. Those surfaces substitute the already-resident Encarmine unit immediately before `World.spawn_unit`/`UnitSpawner.spawn_local_unit`; they never submit its path to `PackageManager`.
- The custom renderer activates only when the unit, both authored materials, and all ten textures are resident. Any incomplete peer/build remains on Laurel. Non-Cosmetics peers continue to receive only `knight_hat_0006` over vanilla synchronization.
- Added once-per-surface `[cos:612]` diagnostics and extended `issue612_encarmine_hat_contract` plus offline Lua coverage to lock the package/spawn boundary.

### Co-op verification

Confirm `[cosmetics:LOAD] v0.9.114-dev` on both peers. Equip **Encarmine Helmet** on Foot Knight and inspect the inventory mannequin, keep/mission third person, a hot join, and the score screen. Cosmetics peers should see the exact authored red-and-gold helmet with black plume; a peer without Cosmetics should see Laurel. Neither log may contain a PackageManager request or missing-resource error for `BD55DCA31255AAEC`; `/cos_regression_test` must pass `issue612_encarmine_hat_contract`.

## 0.9.113-dev - 2026-07-15 - #612 Encarmine preview-package crash quarantine [verify-fix]

### Fixed

- The v0.9.112 dependency probe produced a false positive: VMB's same-hash sidecar bundle contains the custom unit/material/texture payload, but no loadable `BD55DCA31255AAEC.package` resource. `Application.can_get("package", path)` still returned true, promoted the item back to the custom unit, and Foot Knight career/inventory preview fatally called `PackageManager:load` on that path.
- Removed that probe as an activation authority. The persisted `cos_encarmine_hat` identity now always resolves to the vanilla Laurel Helm package-safe fallback before every hero preview, career switch, attachment, and reconstruction path. The authored unit and textures remain quarantined for a later spawn-only renderer that preloads the vanilla package and substitutes only an already-resident custom unit.
- Reworked offline and runtime regression coverage so even an all-true `Application.can_get` fixture cannot promote the unsafe path. `issue612_encarmine_hat_contract` now fails if package promotion is re-enabled.

### Solo verification

Confirm `[cosmetics:LOAD] v0.9.113-dev`, start with **Encarmine Helmet** persisted, and switch to Foot Knight/open his inventory preview. The game must not request `units/cosmetics_tweaker/encarmine_hat/encarmine_hat` through PackageManager or crash. This guard build intentionally renders the vanilla Laurel Helm while the custom spawn-only path remains quarantined.

## 0.9.112-dev - 2026-07-15 - #612 Encarmine compiled package/material repair [verify-fix-coop]

### Fixed

- Added the missing same-path `units/cosmetics_tweaker/encarmine_hat/encarmine_hat.package` resource. Hero and loot previewers can now load the custom unit path as a real PackageManager package instead of fatally requesting absent resource `BD55DCA31255AAEC.package`.
- Replaced the invalid Material-Hijack parent binding with two fully compiled, unit-owned materials matching the FBX renderables `encarmine_armored` and `encarmine_cloth`. They use the exact supplied Encarmine armor/cloth diffuse pixels, the unchanged vanilla normal maps, and metallic/AO/roughness channels derived losslessly from the unchanged vanilla packed maps.
- The custom unit activates only after `Application.can_get` proves its package, unit, both materials, and all ten material textures resident. Any incomplete or drifted build continues to render the v0.9.111 Laurel Helm fallback rather than entering PackageManager.
- Extended the compiled-bundle gate: sidecar unit packages must be forwarded from an explicit mod package root, own a standalone bundle, contain their unit, contain every authored material, and contain every texture referenced by those materials.
- Pinned SHA-256 checks for both exact supplied Encarmine diffuse files and all four unchanged vanilla normal/packed sources. Asset replacement or accidental recompression now fails QA.
- Preserved the existing stable item identity, global localization, vanilla fallback wire identity, inventory/mission renderer routing, score presentation, and bounded remote appearance channel.

### Co-op verification

Confirm `[cosmetics:LOAD] v0.9.112-dev`, equip **Encarmine Helmet** on Foot Knight, and inspect the inventory mannequin, keep/lobby third person, a mission, hot join, and score presentation. Both Cosmetics peers must see the exact red/gold armor and black cloth/plume. A peer without Cosmetics must see the vanilla Laurel fallback and must not crash. `/cos_regression_test` must pass `issue612_encarmine_hat_contract`; the log must contain no missing-resource warning for `BD55DCA31255AAEC`.

## 0.9.111-dev - 2026-07-15 - #612 critical Encarmine equip crash guard [in-progress]

### Fixed

- Confirmed the v0.9.110 crash at the exact engine boundary: equipping the persisted `cos_encarmine_hat` asks `PackageManager` to load `units/cosmetics_tweaker/encarmine_hat/encarmine_hat`, whose compiled package references missing resource `#ID[bd55dca31255aaec]`. The resulting engine fatal bypasses Lua `pcall` and crashes the hero preview.
- Failed the item closed to the inventory-package-listed vanilla Laurel Helm unit on every enabled/disabled, preview, bridge, and persisted-item path. The custom unit remains a diagnostic candidate only and cannot reach `PackageManager` until its complete runtime dependency closure is proven.
- Added the item's name and description to the game's global `Localize()` surface and replaced the cloned Laurel Helm cached localization fields, preventing raw `<cos_encarmine_hat_name>` or stale Laurel Helm text.
- Added offline regression coverage proving that even the enabled item resolves only to the safe base unit before PackageManager while its stable network/backend identity remains registered.

### Verification

Launch with the helmet already selected, open Foot Knight's inventory and cosmetics screens, then equip the Encarmine item. The game must not crash and the item must display as `Encarmine Helmet`; this guard build intentionally renders the vanilla Laurel Helm while the custom resource contract is repaired.

## 0.9.110-dev - 2026-07-14 - #612 Encarmine Helmet [verify-fix-coop]

- Added the Encarmine Helmet as an independent Foot Knight cosmetic: a red-and-gold derivative of the hidden vanilla Laurel Helm mesh, with a black plume and authored icon. Its two mesh slots reuse the vanilla hat material contract and receive separate per-unit armor/cloth textures, avoiding global material mutation. It has no DLC ownership requirement.
- Registered one stable item/network identity at startup. The enable toggle changes availability and rendering without mutating lookup order; disabled or non-Cosmetics peers receive the vanilla Laurel Helm fallback.
- Reused the bounded Cosmetics appearance channel for remote husks, hot joins, lobby/hero previews, and score presentation. Added offline asset/identity coverage plus runtime check `issue612_encarmine_hat_contract`.

### Co-op verification

Equip the helmet on Foot Knight and inspect inventory, hero preview, lobby, mission third person, hot join, and score screen. Both Cosmetics peers must see the red/gold helmet with black plume. A peer without Cosmetics must see the safe vanilla Laurel Helm and must not crash. Disable the option and confirm the item becomes unavailable/falls back without lookup errors. Run `/cos_regression_test`; `issue612_encarmine_hat_contract` must pass.

## 0.9.109-dev - 2026-07-14 - #609 safe network-teardown lifecycle [verify-fix]

- Routed every Cosmetics local-player lookup, including the per-frame deferred peer-purge path, through vanilla's `PlayerManager.local_player_safe()`. Title-screen and disconnect teardown now yield no player instead of calling `Network.peer_id()` after the backend is gone; live in-game behavior is unchanged.
- Added runtime check `local_player_safe_network_lifecycle_609` plus offline coverage that rejects lifecycle-reachable bare `:local_player()` calls across the entry point, glow, diagnostics, Loremaster bridge, and third-person equipment modules.

### Solo verification

Enter the keep, then return to the title screen normally. In the newest console log, Cosmetics must contribute zero `Network backend has not been set` callstacks. Run `/cos_regression_test`; `local_player_safe_network_lifecycle_609` must pass.

## 0.9.108-dev - 2026-07-14 - #604 Crowbill cosmetic identity [verify-fix-coop]

- Registered the Imperial and Dawi Crowbill families with the shared exact-instance cosmetic contract. Primary illusion identity remains stable across pick/hammer mode changes without overwriting a player's selected model.
- Added family ownership coverage for local equipment, remote husks, inventory character preview, lobby, score/team, and item/customization previews.

### Co-op verification

Apply different Crowbill illusions on host and client, toggle hammer mode, swap away and back, enter a mission, hot join, and inspect every preview surface. Each exact instance must retain its chosen illusion and both peers must see the same model and active face.

## 0.9.107-dev - 2026-07-14 - #377 glow editor access regression [verify-fix]

- Decoupled the contextual `EDIT GLOW` control from the optional `cos_glow_badge` texture. When custom texture registration is unavailable, glow-capable CWV and vanilla illusions still expose the editor through a material-free button; badge overlays continue to fail closed independently.
- The skin classifier, exact backend-item/illusion identity, explicit Apply transaction, and glow synchronization are unchanged.

### Solo verification

Select several vanilla and CWV glow-capable illusions. `EDIT GLOW` must appear even if the optional badge texture is unavailable; non-glow illusions must keep it disabled. Open/close the editor, change RGB, press Apply, and confirm the committed color persists after a weapon swap.

## 0.9.106-dev - 2026-07-14 - #373 Loremaster textures on Weavebound/Shyish shields [verify-fix-coop]

- Fixed compatible Weavebound/Shyish magic shield units rejecting Loremaster texture painting because those units do not expose the diffuse slot used by LA.
- Added exact, UV-family-safe magic-to-base paint receivers for Bretonnian, Empire sword/mace shield, and Empire spear/shield families. The selected magic model remains equipped while its same-family base receiver supplies the paintable material boundary.
- Wired owner previews, local equipment, remote husks, and the existing bounded re-wield convergence. Exact allow-lists preserve #204/#266 protections against cross-family texture wrapping.

### Co-op verification

On each supported shield family, select a Weavebound/Shyish illusion and apply several Loremaster textures. Inspect customization/inventory preview, owner first/third person, and a second player's remote view before and after a weapon swap and mission transition. The magic model must remain selected, the texture must be visible, and no Bretonnian texture may wrap onto an Imperial shield or vice versa.

## 0.9.105-dev - 2026-07-14 - #421 wire-safety installer startup failure [verify-fix-coop]

- Fixed `_cos_wire.lua` reading a nonexistent file-global `mod`, which caused a startup error before its three custom-skin network sender guards could install.
- Converted the module to an explicit, dependency-validated `install(owner)` contract. Installation is idempotent for hot reload, fails loudly if required state is missing, and preserves the existing frozen helper and regression surfaces.
- Added coverage that loads the module without a global `mod`, validates failure behavior, proves all three sender hooks install exactly once, and preserves null-on-wire/restoration behavior.
- Added the appearance ownership contract for #602's Dawi Mace family: the dual weapon keeps independently selectable hands with a primary-owned icon, while Mace and Shield uses the shield illusion and icon.

### Co-op verification

Start with Cosmetics enabled and confirm the newest log has no `_cos_wire.lua` error. Join a second player, equip and swap custom illusions, then transition into and out of a mission. Both peers should remain connected and see only wire-safe identities until Cosmetics replays the exact appearance. Run `/cos_regression_test` and require the wire-safety checks to pass.

## 0.9.104-dev - 2026-07-14 - #204 CWV Axe+Shield pool and shield-family parity [verify-fix-coop]

- Seeded CWV Empire Axe+Shield with its complete vanilla Empire shield pool before merging Loremaster options, fixing the LA-only picker.
- Restricted texture-only Loremaster variants to their authored Empire/Bretonnian UV family. Cross-family options are allowed only when they carry their own replacement unit; any declared replacement mesh must match the spawned 1P/3P unit before paint. Bretonnian textures can no longer wrap onto Imperial geometry.
- Preserved family/kind provenance through merge, persistence, local preview, and remote reapplication, with regression coverage for pool composition and atomic unit/material pairing.

### Co-op verification

On CWV Empire Axe+Shield, confirm vanilla Empire shields and compatible Loremaster options both appear. Select several Empire texture variants and custom-unit variants; each must swap/render its authored unit and material in customization, inventory preview, mission, swaps, and on a second player's remote husk. Bretonnian texture-only variants must not appear for or paint an Imperial shield. Run `/cos_regression_test` and require `la_kruber_shield_catalogue_compatibility_204` to pass.

## 0.9.103-dev - 2026-07-14 - #377 manual glow editor and committed badges [verify-fix]

- Removed both illusion-selection and wield-triggered glow-editor auto-opening. A persistent authored icon at the picker boundary is now the sole contextual open/close control and disables itself for non-glow skins.
- Added exact backend-item + illusion glow badges to inventory and illusion grids. Badges consume committed Apply state only, tint rune RGB directly, and use a deterministic intensity-weighted blend for magic components; dirty previews do not change them.
- Packaged the authored `glow.png` unchanged as a DXT5 hero-view texture/material and tint it at runtime. Missing material/atlas registration fails closed with one bounded warning. Apply performs one bounded refresh across weakly tracked live surfaces; no per-frame persistence decoding or network traffic was added.
- Preserved the concurrent #376/#583 exact icon-ownership changes: dual/main-right and shield/offhand inventory icon rules are unchanged.

- **Verify (solo):** open weapon customization and select/wield several glow-capable and ordinary skins; nothing should auto-open. Use the bottom-right glow control to open/close the editor. Change RGB without Apply and confirm no badge changes, then Apply and confirm only that exact item+skin gains the tinted badge in both inventory and illusion grids. Verify rune RGB, a multi-component magic blend, restart persistence, and no badge on an unmodified same-type item. Run `/cos_regression_test` and confirm `glow_manual_editor_button_377` passes.

## 0.9.102-dev - 2026-07-14 - #504 OOP Phase 4a wire boundary [verify-fix-coop]

- Extracted the complete #421 custom weapon-skin wire boundary from the entry monolith into `_cos_wire.lua`: the null/restore helper and all three vanilla `rpc_add_equipment` sender hooks now have one owner and one load-bearing manifest edge after custom illusion registration.
- Preserved the established `mod._cos_wire_null_custom_skins` and `mod._cos_skin_wire_surfaces` regression surfaces, hook targets, diagnostics, return arity, and unconditional never-crash policy. No setting, RPC, payload, or gameplay behavior changed.
- Added engine-free coverage for manifest order, all three sender registrations, custom-only nulling, local-state restoration, and four-value continuation forwarding. Existing `/cos_regression_test` checks `wire_skin_null_ungated` and `wire_skin_null_all_senders` remain the in-game assertions.

- **Verify (coop):** with both peers running the same dev build, equip a `ct_*` custom illusion before mission start, change/re-equip it mid-session, and have the second peer hot-join. The owner must retain the illusion locally; the other peer must not crash on any path. Run `/cos_regression_test` and confirm `wire_skin_null_ungated` plus `wire_skin_null_all_senders` pass. The console should show bounded `[cos:421] wire skin null` lines for `game_object_initialized`, `spawn_resynced_loadout`, and `hot_join_sync` as those paths are exercised.

## 0.9.101-dev - 2026-07-14 - #485 authored heroic weapon poses [diagnostics-armed]

- Added a default-off **Unlock Heroic Weapon Poses** option. In the modded realm, the social wheel now receives every valid `weapon_pose` item authored for the currently wielded weapon, sorted by pose index, without writing backend ownership or mutating `ItemMasterList`.
- Reused vanilla's pose-package loading, icon material creation, and local-only emote execution. Toggling the option invalidates the live social-wheel page so the current weapon rebuilds without a restart.
- Weapons with no authored pose catalog remain on vanilla behavior and emit one bounded `[cos:485] ... fallback=deferred` line. Borrowing another weapon's pose package remains diagnostics-armed until its animation and icon compatibility can be proven.
- Added engine-free catalog tests and `/cos_regression_test` check `issue485_authored_weapon_poses_local_only`.

- **Verify (solo):** in the modded realm, enable the option, wield a weapon with authored poses, and open the social wheel. All authored poses for that exact weapon should appear and play. Disable the option and confirm the wheel returns to the officially unlocked set. Repeat with a weapon lacking a catalog and attach the bounded `[cos:485]` line; no borrowed or blank-icon entries should appear.

## 0.9.100-dev - 2026-07-14 - #377 in-view glow auto-open toggle [verify-fix]

- Added one square toggle at middle-left of the weapon customization view. It uses vanilla's illusion-button widget and existing scenegraph, lights when automatic glow-picker opening is ON, and greys/disables itself for non-glow illusions.
- The preference persists per user under `glow_picker_auto_popup_enabled`, defaults ON, and gates both illusion-selection and once-per-keep wield auto-opening. The `/glow_picker` command remains an explicit manual entry point while automatic opening is OFF.
- Reused the consolidated customization setup/draw/illusion hooks; no hook, renderer, RPC, or network state was added. Added runtime regression `glow_auto_open_in_view_toggle_377` for default-ON, persisted-OFF, and non-glow disabled policy.

- **Verify (solo):** open weapon customization on a glow-capable illusion. Confirm the middle-left square is lit and selecting another glow illusion opens the picker. Click the square OFF, select glow illusions, leave/reopen customization, and restart; the square must remain OFF and the picker must not auto-open. `/glow_picker` must still open it manually. Select a non-glow illusion and confirm the square is greyed and cannot be toggled. Run `/cos_regression_test` and confirm `glow_auto_open_in_view_toggle_377` passes.

## 0.9.99-dev - 2026-07-14 - #376 exact-item LA persistence and icons [verify-fix]

- Inventory/loadout grids now show Loremaster's Armoury's authored icon only for the exact backend item carrying the persisted LA illusion or offhand choice. The resolver uses `SKIN_LIST[armoury_key].icons[vanilla_skin]`, preserves the other three vanilla UI-information returns, and never mutates shared `WeaponSkins` or `ItemMasterList` icon fields.
- Added a delayed backend-mirror reconciliation that removes illusion/offhand overrides when their exact item no longer exists, while retaining CIM-forged records during local-mirror restoration. Existing hat/armor, main-illusion, and per-hand save/restore paths are unchanged.
- Added pure offline identity/fail-closed coverage and runtime `la_exact_instance_inventory_icon_376` coverage.

- **Verify (solo):** apply different LA cosmetics to two same-type weapons, restart the game, and open the loadout inventory. Only the modified instance must show the matching LA icon and render that illusion; the other instance keeps its vanilla icon. Salvage/delete the modified item, wait 10 seconds after returning to the keep, and confirm `[la-state] INSTANCE-PRUNE 1 missing item override(s) removed` without changing another item.

## 0.9.98-dev - 2026-07-13 - #266 Kruber LA shield availability parity [verify-fix-coop]

- Every Loremaster's Armour shield illusion is now offered on the same seven Kruber shield item types: Sword and Shield, Mace and Shield, Bretonnian Sword and Shield, Spear and Shield, and CWV Axe, Longsword, and Warrior-Priest Hammer shield variants.
- Replaced Kruber's Empire/Breton availability split with one shared catalogue. The existing generic apply path still swaps to each option's LA-authored shield mesh before painting, preserving its intended UV layout without per-weapon render exceptions.
- Added offline parity coverage for catalogue completeness, uniqueness, identical Empire/Breton expansion, CWV coverage, and non-Kruber isolation.

- **Verify (coop):** with Loremaster's Armour, Cosmetics Tweaker v0.9.98-dev, and CWV enabled on both peers, inspect all seven Kruber shield weapon families. Each offhand row must offer the identical LA armoury-key set. Equip representative Empire-, Breton-, and custom-mesh shields on native and CWV weapons; verify preview, local 1P/3P, weapon swapping, keep-to-mission transition, and the other peer's husk retain the selected authored mesh and texture.

## 0.9.97-dev - 2026-07-13 - #583 independent native/CWV dual offhands [verify-fix-coop]

- The normal illusion row now owns the main/right hand for dual weapons and Cosmetics adds one independent left/offhand row. Its default `Follow Main Illusion` entry carries no mesh override, so changing the main illusion still changes the pair until the user explicitly chooses an offhand.
- Added the missing native Warrior Priest Dual Skullsplitters (`wh_dual_hammer`) from vanilla's dedicated `wh_dual_hammer_skins` table and lazy exact-hand pools for all seven current CWV dual families: Imperial Dual Swords, Sword and Mace, Kruber/Saltzpyre Dual Axes, Kruber/Saltzpyre Dual Maces, and Dual Warrior-Priest Hammers.
- Direct hand choices now persist under the existing owner-only `offhands[backend_id][hand]` store. Restore accepts a unit only when it still belongs to that exact item type's compatible hand pool; missing items, removed variants, wrong hands, and stale paths fall back to the main illusion.
- Reused the existing last-choice-per-hand Apply queue, host-authoritative direct-unit channel, equipment/preview `get_item_units` override, remote-husk store, transition rebroadcast, and acknowledged hot-join state pull. Transition replay no longer depends on Loremaster's Armoury being installed. No RPC, schema, or hook was added.
- Added `independent_dual_offhands_583` plus expanded persistence and Sword-and-Mace regressions.

- **Verify (coop):** with Cosmetics v0.9.97-dev on both peers, customize native Warrior Priest Dual Skullsplitters and at least one CWV dual weapon. Row 1 must change the main hand; the added row must change only the offhand. Apply, swap weapons, reopen the preview, restart, transition keep-to-mission, and leave/rejoin. Local 1P, local 3P, preview, and the other peer's husk must retain the same independent pair. `Follow Main Illusion` must clear only the offhand override.

## Post-fix audit - 2026-07-13 - #514 verified complete

- User solo verification confirmed that a Loremaster shield pick stored on Grail Knight's secondary Bretonnian Sword and Shield no longer wraps onto CWV Sword and Mace's mace at spawn. The uploaded v0.9.87-dev log records the exact restrictive gate (`entry key=one_handed_sword_shield_template_2`, `wielded template=sword_and_mace_template`) and `/cos_regression_test` passes `cos_la_weapon_identity_gate_local_wearer`.
- Audited the shared local/husk resolver and both offhand/illusion call sites. They read `equipment.wielded_slot`, fail closed when the wielded item is unresolved or different, and preserve retry-on-next-wield behavior. The existing runtime regression locks local-owner, own-template, cosmetic-slot, and unresolved-item shapes. This is an instance of the existing owner/husk separate-root bug class, so no new catalog class was needed. No gameplay behavior, mod version, or Workshop deployment changed.

## 0.9.96-dev - 2026-07-13 - #565 reject async preload callbacks after unload [not deployed]

- The shipped async conversion balanced every observed session (100 unique loads and 100 releases), but vanilla retains callbacks on a shared in-flight package when one reference unloads and another owner remains (`package_manager.lua:41-48`, `:196-237`). Cosmetics' old callback could therefore run after mod unload and recreate a `ready` entry in the registry that unload had just cleared.
- Added a generation-scoped lifecycle ledger. Each acquired path carries the active generation; unload invalidates the generation and clears ownership before calling PackageManager. A callback retained by another owner is ignored and cannot repopulate readiness state. Late-callback and release-failure diagnostics are raw-console only and capped at four detailed rows per process.
- Renamed the package reference from the generic `cosmetics_tweaker` to `cosmetics_tweaker_offhand`, making shutdown attribution unambiguous from unrelated package owners. The one-reference-per-path rule, asynchronous/non-prioritized queue, invalid-package filter, and 1P+3P `Application.can_get` render gate are unchanged.
- Added runtime and offline Lua coverage for active completion, exact release snapshots, late shared-handle callback rejection, deduplication, and failed-load cancellation. In-game verification remains: rapid shutdown/restart while packages are loading, ordinary keep/mission transitions, customization previews, local body and remote husks; no late callback may restore state after the lifecycle release marker.

## Post-fix audit - 2026-07-13 - #574 verified complete

- User co-op verification confirms peer glow sync after weapon swaps, exact per-instance persistence across game exit, inventory-preview parity, and automatic reconstruction after a client leaves and rejoins.
- Audited the shipped v0.9.92-dev through v0.9.94-dev transaction, identity, persistence, preview/equipment/husk fan-out, host-authoritative RPC, and bounded join replay. Added offline lifecycle coverage plus tier-a source gates and corrected stale architecture documentation. No gameplay behavior, mod version, or Workshop deployment changed.

## 0.9.95-dev - 2026-07-13 - #513 isolate score-lineup wearer identity [verify-fix-coop]

- The 0.9.93 client log proved that exact profile/career matching was still insufficient by itself: vanilla score rows for Sienna and Warrior Priest carried the host's `peer_id`, so the resolver opened the host's human-only LA store and explicitly swapped both bot helmets to Grail Knight's Loremaster mesh. Vanilla `ScoreboardHelper` records `is_player_controlled` beside that shared network-owner peer.
- Added a pure score identity boundary that requires exact profile plus career, `is_player_controlled == true`, and a complete peer/local-player tuple. Bot and incomplete rows now fail closed and never receive `_cos_wearer_peer`; the non-score `TeamPreviewer` fallback also requires exact profile plus career.
- The same owner/wearer distinction fixes the host-only colour loss. The spawn monitor had treated a host-owned bot's expected skeleton mismatch as a human career switch and purged the host's valid LA hat; the client happened to receive a later re-emit while the host did not. Bot mismatches remain blocked by the existing character guard but can no longer invalidate their human owner's store.
- Bounded diagnostics now classify rejected score bots as `role=bot source=score_snapshot_bot` and retained spawn aliases as `BOT-OWNER-ALIAS`. Runtime and offline regressions reproduce the observed Grail Knight human plus Sienna/Warrior Priest bots sharing one host peer. The independent generated Sword+Mace score rendering remains owned by #416/#483 and is not changed here. No Workshop deployment.
- **Co-op verify:** finish a mission with the host wearing the Grail Knight Loremaster helmet and with Sienna/Warrior Priest bots present. Both peers must see the helmet only on Grail Knight, with its wearer-specific colour. Logs must show `BOT-OWNER-ALIAS retained`, the Grail Knight human as `role=local|remote source=score_snapshot`, bots as `role=bot source=score_snapshot_bot peer=nil`, and no `SCORE-HAT` swap/paint following a bot row.

## 0.9.95-dev - 2026-07-13 - #483 individualized CWV sword/mace cosmetics [verify-fix-coop]

- Added independent right-hand sword and left-hand mace cosmetic rows for CWV's `cwv_es_sword_and_mace`. Each row is sourced from the exact vanilla `ItemMasterList` family (`es_1h_sword` or `es_1h_mace`), rather than the generated paired-skin table, so changing one hand no longer forces a pre-zipped partner onto the other.
- Generalized dual-weapon pool registration with a deterministic, DLC-aware `matching_item_key` source selector. Existing skin-table registrations and all other weapon pools are unchanged.
- The selections use Cosmetics' existing direct-unit `cos_la_apply` transport, host-authoritative per-peer/per-template/per-hand store, state replay, package readiness gate, and husk render path. No RPC name, schema, hook, or CWV source changed. Added `issue483_cwv_sword_mace_individualized_cosmetics` runtime coverage.
- **Co-op verify:** with Cosmetics v0.9.95-dev and CWV enabled on both peers, equip Sword and Mace, open weapon customization, and choose visibly different right-sword and left-mace variants. Apply, wield, swap away/back, and re-open customization; both choices must remain independent locally. Join and hot-join a second peer; both viewers must see the same sword-right/mace-left pair without either player reopening the picker. Run `/cos_regression_test` and confirm `issue483_cwv_sword_mace_individualized_cosmetics` passes.
## 0.9.94-dev - 2026-07-13 - #574 initial/hot-join glow convergence [verify-fix-coop]

- Fixed the remaining join race where the targeted `AttachmentUtils.hot_join_sync` glow push could arrive before the joining peer was an ingame recipient, or its cached glow could arrive before the remote husk had published wielded equipment. The joiner's existing acknowledged `cos_la_state_req` pull-on-ready now also receives the host's cached glow states through the existing `cos_glow_apply` channel; no RPC name, schema, or payload shape was added.
- A received active glow with no ready equipment now arms one local material-only repaint job for that wearer. It checks at 0.25-second cadence, stops immediately when units exist (or when husk `_wield_slot` paints first), and is hard-capped at 40 attempts/10 seconds. The retry tick never sends network traffic.
- `_reapply_glow_for_peer` now reports how many live wield units it repainted, allowing the join path to distinguish success from the peer/husk-not-ready race. Added bounded `[cos:574] state-pull`, `rehydrate armed|complete|expired` evidence and expanded `glow_picker_render_fanout_574` to lock the zero-new-RPC and retry bounds. No Workshop deployment.
- **Co-op verify:** both peers load v0.9.94-dev and have different committed item glows before joining. Join/hot-join without either wearer swapping weapons or opening the picker. Each initial remote husk must show the committed glow once its weapon appears. Repeat by leaving/rejoining and by joining an in-progress mission. Logs should show `state-pull reply ... glow_entries=`, then `rehydrate complete ... path=network_recv|equipment_ready|husk_wield`; no repeating glow RPC stream.

## 0.9.93-dev - 2026-07-13 - #574 glow rehydration and render fan-out [untested]

- Fixed hero/inventory previews reverting after weapon swaps. Vanilla stores backend ID and skin per preview slot before asynchronous package loading; the old single mutable previewer backend ID could point at a later request by spawn time. The post-spawn path now binds from vanilla's durable per-slot record, reloads the saved item+illusion RGB, and repaints the spawned units.
- Fixed remote peers retaining the original cosmetic glow. Husk `_wield_slot` bypasses `GearUtils.create_equipment`, so the existing owner-side map/apply hook never ran. The consolidated husk wrapper now binds the freshly spawned hand units to wearer + wielded slot + illusion and repaints from the authoritative peer cache.
- Leaving a lobby, changing network role, weapon swapping, and equipment respawns now rehydrate the owner-authoritative durable store and repaint local 1P/3P units without opening the picker. Remote matching fails closed on a different illusion or slot; backend IDs remain local and never cross the wire.
- Added a compact active-slot field to the existing glow payload, bounded log-only `[cos:574]` send/receive/rehydrate/husk evidence (48 lines per session), `glow_picker_render_fanout_574`, and updated glow/regression documentation. No new RPC or hook registration; no Workshop deployment in this change.

- **Verify (coop):** Apply distinct colors on both peers. Confirm each player sees their own color in 1P, 3P, and the inventory hero preview, and sees the other player's color. Swap weapons and preview items repeatedly, leave the lobby back to the keep, then rejoin without opening the picker; every surface must restore automatically. Confirm the log contains bounded `sync send`, `sync recv`, `rehydrate path=create_equipment|hero_preview|local_wield`, and `repaint path=husk_wield ... active=true` evidence.

## 0.9.92-dev - 2026-07-13 - #574 explicit per-illusion glow Apply transaction [untested]

- Added the missing Apply button and dirty state. Slider movement remains a local live preview; Apply is the only persistence/network commit, disables itself after success, and repeated clicks do not write or emit again.
- Closing the picker now discards unapplied edits and repaints the last committed value (or vanilla). Applied RGB is keyed by backend item plus illusion, restored during equipment spawn after restart, and repainted on local 1P/3P units.
- Added the active applied glow to the existing host-authoritative `cos_glow_apply_req`/`cos_glow_apply` channel. Receivers cache the wearer's state and immediately repaint already-wielded remote units; hot-join replay uses the existing glow cache path.
- Added bounded log-only `[cos:574] [glow_picker:apply]` evidence and `glow_picker_apply_transaction_574` regression coverage. No Workshop deployment in this change.

- **Verify (coop):** on both peers, change a rune or magic RGB slider and confirm Apply appears active. Close without Apply and confirm the prior color returns. Reopen, change, Apply once, close/reopen, then restart the game; the exact item+illusion must retain the color in 1P and 3P. Each peer must see the other wearer's applied color. A second click without another edit must produce no additional `[glow_picker:apply]` line or peer update.

## 0.9.91-dev - 2026-07-13 - #513 score lineup resolves peers from end-view snapshot [untested]

- The previous 0.9.86 fix hooked the correct `TeamPreviewer`/`HeroPreviewer` render path but resolved each lineup row through live `PlayerManager.human_players()`. Vanilla removes those player rows during the end transition before the team previewer starts loading: the failing log removes players at 21:08:34 and loads `ui_end_screen`/the lineup at 21:08:35. The resolver returned nil, so none of the `SCORE-HAT` paths ran.
- `LevelEndViewBase.context.players_session_score` is the durable end-view snapshot and each entry retains exact `peer_id`, `local_player_id`, `profile_index`, and `career_index`; only `LevelEndView._get_hero_from_score` drops peer identity while building `hero_data`. The score resolver now matches profile+career in that snapshot first and keeps the live-player scan only for non-end-view TeamPreviewers.
- Added bounded raw `[la-state] SCORE-ROW` diagnostics (maximum 16 distinct rows, never chat) that classify local/remote/unresolved rows and report resolver source plus synced LA hat/outfit store state. Existing `SCORE-HAT mesh-swap/equip/paint` and `SCORE-ARMOR` markers remain.
- Expanded `cos_la_score_screen_apply_wired` with pure local/remote snapshot fixtures and a wrong-career rejection. No Workshop deployment in this change.

- **Verify (coop):** load 0.9.91-dev on both peers, equip LA hats, finish a mission, and inspect each other's lineup model. Each client log must show one `SCORE-ROW` per human with `source=score_snapshot`, correct `role=local|remote`, and the expected store hat key, followed by `SCORE-HAT equip`, `mesh-swap`, and `paint`. Both models must visibly wear their LA hats.

## 0.9.90-dev - 2026-07-13 - #565/#570 bounded startup package loading [untested]

- Replaced Cosmetics' 74 blocking offhand `sync-read` calls at startup with deduplicated asynchronous package loads. Vanilla `PackageManager.load(..., asynchronous=true)` queues packages without the call-site `ResourcePackage.flush`; the existing `_override_package_ready` gate requires both 1P and 3P units before any override is exposed, so an unfinished package safely falls back to the base mesh.
- Tracks the single `cosmetics_tweaker` reference owned for each queued package and releases it from the existing unload lifecycle. Added `offhand_preload_async_bounded_565` regression coverage for the async/readiness/release contract.
- Moved automatic glow-picker build/first-hook diagnostics plus dormant dependency and LA hook-registration warnings from chat to console while preserving their evidence. User-triggered command feedback is unchanged.

## 0.9.89-dev - 2026-07-13 - #566 model white_glow as vanilla's fallback case [untested]

- `/cos_regression_test` no longer requires a nonexistent
  `MaterialSettingsTemplates.white_glow`. Vanilla registers the eight other
  weapon material templates in
  `weapon_material_settings_templates.lua:4-115`; `white_glow` is absent.
- Coverage for the exception remains explicit: the test now asserts that
  `deus_dw_1h_axe_skin_06_runed_02_white` still maps to `white_glow`, matching
  `weapon_skins_morris.lua:5-12`. A later vanilla registration is tolerated,
  but the current missing-template fallback no longer produces a false FAIL.

Verify by running `/cos_regression_test` in the keep. The
`material_settings_templates_loaded` check should pass while all eight
vanilla-registered weapon template families remain covered.

## 0.9.88-dev - 2026-07-13 - #518 Pilgrimage Chamber keeps LA weapon cosmetics [untested]

The v0.9.84 Chaos Wastes precedence gate was too broad: it yielded every
Loremaster weapon cosmetic whenever the current mechanism was `deus`. That mechanism
also owns the Pilgrimage Chamber staging keep (`morris_hub`, game mode `inn_deus`) and
the route/shrine map (`map_deus`), so a correctly recalled Spear and Shield cosmetic
disappeared from the live weapon upon entering the chamber even though the inventory
character and cosmetic-menu previews still showed it.

- **Fix.** Yield now requires both mechanism `deus` and game mode `deus`. The live
  `GameModeManager:game_mode_key()` is preferred, with promoted
  `LevelTransitionHandler:get_current_game_mode()` as the early-load fallback. This
  preserves LA weapon rendering in `inn_deus` and `map_deus` while actual expedition
  missions still yield to their starting/upgrade rarity skins. If both game-mode
  surfaces are still starting, the current level uses vanilla's same two-special-level
  classifier (`morris_hub`, `dlc_morris_map`, otherwise mission). Synced state, husk
  handling, preview paths, and return-to-keep reassertion remain unchanged.
- **Source.** `deus_mechanism.lua:28-35,730-744` defines the hub/map/mission game-mode
  split; `deus_node_settings.lua:3-22` maps node types to `inn_deus`, `map_deus`, and
  `deus`; `game_mode_manager.lua:915-917` and
  `level_transition_handler.lua:387-389` expose the live/promoted keys.
- **Diagnostics.** One deduplicated `[la-state] DEUS-YIELD bypass mechanism=deus
  game_mode=inn_deus` line proves the staging exception ran without per-frame spam.
- **Regression.** `cos_la_deus_yield_active_mission_only` exercises normal keep,
  Pilgrimage Chamber, route/shrine map, and active expedition cases as pure data.
- **Verify.** Enter Pilgrimage Chamber with an LA cosmetic equipped on Spear and
  Shield: it remains on the live weapon. Begin an expedition and upgrade the weapon:
  the Chaos Wastes rarity skin wins. Return to a hub: the LA cosmetic reappears.

## 0.9.87-dev - 2026-07-13 - #427 _dbg_alert log-only via engine printf [untested]

- Both `_dbg_alert` copies (`cosmetics_tweaker.lua` + the byte-identical `_cos_glow.lua` copy) rerouted mod:warning -> pcall-guarded engine printf (VMF warning channel posts to chat under default settings; printf survives mod-logging-OFF, never chat; enemy_tweaker issue 240 template).

## 0.9.86-dev — 2026-07-13 — #513 Score-screen hero lineup now wears LA hats/outfits [untested]

Fixes #513: the end-of-round score screen rendered every hero with the vanilla hat -
the reporter's Grail Knight Loremaster helm (purified) showed as the base helm.

- **Root cause.** The score lineup is a FOURTH rendering surface none of the LA apply
  paths covered. `LevelEndView._setup_team_previewer` (`level_end_view_v2.lua:403`)
  spawns `TeamPreviewer`, which instantiates the BASE `HeroPreviewer`
  (`team_previewer.lua:20`) and equips each hero from `players_session_scores` -
  data `ScoreboardHelper.get_grouped_topic_statistics` read from player SYNC data
  (`scoreboard_helper.lua:371` via `CosmeticUtils.get_cosmetic_slot`). That sync data
  carries only the NET-SAFE VANILLA key our `update_cosmetic_slot` hook substitutes
  for wire safety (issue 421 class), and `equip_item` runs with `backend_id = nil`
  (`team_previewer.lua:126`), so every LA identity is stripped before the previewer
  spawns. No attachment extension, no husk wield - none of the existing hooks fire.
- **Fix.** Recover the LA identity from the synced per-peer store
  (`_la_equips_by_peer`, present on every mod peer including the wearer): new
  `TeamPreviewer._spawn_hero` hook resolves the hero's peer from
  `hero_data.profile_index` (new nil-safe `mod._cos_score_peer_for_profile`, using the
  context's profile_synchronizer with player fallbacks) and stamps it on the previewer;
  the existing `HeroPreviewer.equip_item` hook grew a `slot_hat` branch that swaps the
  hat mesh to `variant.new_units[1]` via a bracketed `get_item_units` override
  (residency-gated with `Application.can_get`, issue 270 class - degrades to the
  vanilla hat, never a spawn assert) so the previewer itself preloads the LA unit;
  the existing `_spawn_item_unit_combined` hook paints kind="texture" hats on the
  just-spawned hat unit (`apply_new_skin_from_texture`, LA_SYNC_MODEL 6.2); new
  `TeamPreviewer.cb_hero_unit_spawned_skin_preview` hook_safe paints kind="armor"
  outfits onto the spawned body (mesh_unit + character_unit). Covers the local
  player AND every peer whose LA state is in the store (bots excluded - store is
  human-only). Hooks live on the previewer classes, not the end views: the deus/
  weave views are class-copies (`LevelEndViewDeus = class(_, LevelEndView)`), so
  view-level hooks would miss them. `[la-state] SCORE-*` printf markers at every
  decision point. Weapon-side (offhand/illusion) score rendering is NOT in this
  slice - the lineup weapon resolves through a separate verified-weapon path.
- **Passing fix.** `_spawn_item_unit_combined` now forwards the 8th vanilla arg
  `skip_wield_anim` (`world_hero_previewer.lua:917`) that the 7-param wrapper
  silently dropped (multi-arg truncation, VMF_RECIPES 2).
- **rt-check.** `cos_la_score_screen_apply_wired` (resolver present + nil-safe,
  store present).
- `cosmetics_tweaker.lua` - `MOD_VERSION` -> `0.9.86-dev`.

## 0.9.85-dev — 2026-07-13 — #514 LA shield pick no longer paints onto a different wielded weapon (Sword and Mace mace wrap) [untested]

Fixes #514: with an LA shield pick committed on Grail Knight's secondary Bretonnian
Sword and Shield, the shield texture wrapped around the MACE of the wielded CWV
Sword and Mace at mission spawn. Log evidence (console 2026-07-12 20:09:55.533):
`EMIT ... slot=one_handed_sword_shield_template_2 kind=offhand key=Kruber_bret_shield_basic2_Luidhard01`
immediately followed by `PAINT site=network_husk ... target_mesh=units/weapons/player/wpn_emp_mace_03_t1/...`
(both 1P and 3P mace units), with zero `APPLY SKIP wrong-weapon` lines in the session.

- **Root cause.** The v0.9.72 weapon-identity guard in `_apply_la_on_unit`
  (offhand + illusion branches) read `inv.wielded_slot` - a field that exists ONLY on
  `SimpleHuskInventoryExtension` (`simple_husk_inventory_extension.lua:321`). On the
  LOCAL wearer (`SimpleInventoryExtension`) the wielded slot lives at
  `equipment.wielded_slot` (`simple_inventory_extension.lua:208/669`), so the guard's
  wielded item resolved to nil and the `if w_item then` shape fell through PERMISSIVE,
  painting `equipment.left_hand_wielded_unit_3p`/`_1p` of whatever weapon was in hand.
  The spawn-time state replay of a pick stored under the Bret template key
  (`one_handed_sword_shield_template_2`, `item_master_list_lake.lua:425`) therefore
  landed on the wielded Sword and Mace's mace.
- **Fix.** New shared resolver `mod._la_wielded_item_matches(inv, equipment, key,
  allow_slot_key)` reads `equipment.wielded_slot` first (correct on both inventory
  classes), keeps `inv.wielded_slot` as husk fallback, and both gate call sites are now
  RESTRICTIVE when the wielded item is unresolvable: skip + re-queue (pending retry /
  next-wield reconcile re-applies once the matching weapon is in hand) instead of
  painting blind. Offhand entries match weapon identity only (template/name/key/
  item_type); illusion entries keep their designed cosmetic-slot-key match.
- **rt-check.** `cos_la_weapon_identity_gate_local_wearer` replays the issue 514 shapes
  as a pure-table functional test (Bret template entry vs wielded cwv_es_sword_and_mace
  must skip; own template and illusion slot-key must match; unresolvable must skip).

## 0.9.84-dev — 2026-07-13 — #518 LA weapon cosmetics yield to Chaos Wastes upgrade skins (deus-yield gate) [untested]

Fixes #518: in Chaos Wastes, starting and shrine-upgraded weapons had their deus-rolled
rarity skins overridden by the player's Loremaster offhand/illusion picks. Log evidence
(console 2026-07-12 20:19): `LOCAL wield-reapply stored_key=one_handed_sword_shield_template_2
kind=offhand armoury=Kruber_bret_shield_basic2_Luidhard01` repeating throughout
`SPAWN mechanism=deus` maps.

- **Root cause.** Deus weapon generation rolls `item.skin` per rarity
  (`deus_weapon_generation.lua:246-249`) and RE-rolls it on every shrine upgrade
  (`:318-321`) - the skin change IS the upgrade's visual feedback. But committed LA
  offhand picks are stored under a weapon-TEMPLATE key namespace besides the per-instance
  backend_id (emit sites write both), and deus items clone the base item
  (`create_item` sets `key = base_item`, same template - `deus_weapon_generation.lua:185-202`).
  So the keep instance's pick matched every CW-generated weapon sharing the template, and
  the template-keyed re-apply paths (local wield re-apply, husk wield re-paint, husk
  `get_item_units` mesh swap, reconcile/pending retries) stomped the rolled skin on every
  wield. The live-body `_offhand_selection[backend_id]` mesh/paint path also fired on the
  first CW map, where the deus loadout still resolves the REAL backend items.
- **Precedence decision.** Inside a deus run, CW upgrade cosmetics WIN; LA re-asserts
  outside (the gate reads `Managers.mechanism:current_mechanism_name()` live and the
  synced stores stay warm, so no state is lost). The issue names pooling LA variants into
  the deus skin tables as the desired end state - that is a separate feature, tracked as a
  follow-up, not shipped here. WEAPON-side only: LA hats/outfits (kind hat/armor) are real
  backend cosmetics that persist through CW and stay un-gated. No new menu toggle.
- **Fix.** New `mod._la_deus_weapon_yield()` gate consulted at every weapon-side apply
  choke point: the `BackendUtils.get_item_units` husk LA mesh-swap + husk vanilla-mesh
  (issue 416 store) branches, the live-body `_offhand_selection` mesh branch
  (create_equipment only - preview surfaces render the keep instance and keep the pick),
  the `_apply_la_offhand_to_units` "ingame" paint, `_apply_la_on_unit` (terminal backstop
  for offhand/illusion kinds, dedup'd `[la-state] DEUS-YIELD suppressed` printf), the
  local `_wield_slot` re-apply, and `_la_reconcile` (terminal reason `"deus-yield"`; the
  pending drain treats it like `"no-entry"` so retries do not spin to deadline).
- **rt-check.** `cos_la_deus_yield_gate_wired` verifies the gate exists and returns a
  boolean (false outside deus).

## 0.9.83-dev — 2026-07-13 — #520 LA hats/outfits now actually persist across restarts (save moved to the loadout chokepoint + cache rehydration) [untested]

Fixes #520: the last-equipped Loremaster hat/outfit was lost on every game restart and
the character came back wearing the previous (vanilla-persistable) hat. Log evidence
(sessions 2026-07-12 20:06 through 2026-07-13): `la_persisted_equips.careers = []` and
`illusions = []` on disk across dozens of sessions while `offhands` saved fine, zero
`[la-persist] save/clear/restore` lines for hats despite confirmed LA hat equips
(20:07:38.117 `SYNC emit kind=hat armoury=Kruber_Hippogryph_helm_white` with NO save line).

- **Root cause (two-part).** (1) LA hat/outfit equips are intercepted by the
  `BackendUtils.set_loadout_item` skin-loadout-safety hook, which caches the clone bid in
  the SESSION-ONLY `mod.loadout_cache` and early-returns - the equip never reached any
  persistent store. (2) The intended writer (the v0.9.12 save tap in the
  `CosmeticUtils.update_cosmetic_slot` hook) resolved career via
  `player:career_name()` -> `ProfileSynchronizer.profile_by_peer`
  (bulldozer_player.lua:29-38/91-116), which returns nil while a loadout resync is in
  flight - and the deferred attachment spawn (player_unit_attachment_extension.lua:267-293)
  fires the tap exactly inside that window, so `career_name` came back nil and the save
  was SILENTLY skipped, every time. Net: nothing ever wrote `careers`, and on the next boot
  vanilla restored the last real backend hat - "the hat I had last equipped prior to that".
- **Fix 1 - authoritative save/clear at the chokepoint.** The `set_loadout_item` hook now
  calls `LA_PERSIST.save_cosmetic(career_name, slot, backend_id)` in its clone-cache branch
  and `LA_PERSIST.clear_cosmetic(career_name, slot)` in its vanilla-over-LA branch.
  `career_name` is a call ARGUMENT here - no resolution fragility, and it captures exact
  user intent (menu equips only, never spawn/resync flows).
- **Fix 2 - boot rehydration of `mod.loadout_cache`.** `_install_skin_loadout_safety` now
  refills the cache from `la_persisted_equips.careers` (entries whose LA clone no longer
  exists are skipped, mirroring the offhand restore guard). The first spawn's
  `BackendUtils.get_loadout_item` then resolves the LA clone directly and the hero view
  shows the LA item as equipped after a restart. Log: `[la-state] COSMETIC-RESTORE n
  hat/outfit pick(s) rehydrated from disk, m unresolvable`.
- **Fix 3 - hardened `_career_name_for_player`.** Falls back to the UNIT-resident career
  data (`career_system` extension `career_name()` / `_career_name`, then
  `inventory_system._career_name` - populated at unit init, immune to the resync window)
  before the SPProfiles index math; a failed pcall no longer leaves the index as a
  truthy function. The v0.9.12 update_cosmetic_slot taps stay as redundant writers
  (save_cosmetic dedups); when their career resolution still fails they now printf
  `[la-persist] WARN save/clear skipped (career unresolved)` instead of silently dropping.
- **Regression checks:** `cos_la_cosmetic_persistence_roundtrip` (module save/read/clear
  roundtrip) and `cos_la_loadout_equip_capture_wired` (drives the REAL set_loadout_item
  hook with a fake LA-clone bid; verifies cache + disk both write, then cleans up; asserts
  the `mod._la_skin_safety_installed` load-time marker when LA is present).
- Files: `cosmetics_tweaker.lua` (set_loadout_item hook, rehydration, tap diagnostics,
  rt checks, `MOD_VERSION` -> `0.9.83-dev`), `_la_persistence.lua`
  (`_career_name_for_player` fallbacks, `get_all_saved_cosmetics`).

## 0.9.82-dev — 2026-07-12 — #416 replicate per-hand VANILLA offhand meshes to peers (sync layer + husk apply) [untested]

Closes the offhand half of #416: a per-hand VANILLA shield / held-weapon unit pick
(Stirland / Bretonnian / GK shields — `opt.unit` / `opt.intended_unit`, no LA
`armoury_key`) applied only on the wearer's own body and showed as the base offhand on
every other peer. LA armoury shields already synced; vanilla mesh picks had no networked
representation. This adds the missing sync layer + a generic husk mesh-swap, both hands,
both directions, with hot-join. NEEDS `verify-fix-coop` (2+ players, both with the mod).

- **Sync layer (reuses the existing `cos_la_apply` / `cos_la_apply_req` VMF mod channel — no new channel):** added one ADDITIVE optional payload field `offhand_unit` (a plain unit-path STRING, or `""` = clear/revert-to-base). Handled by a branch placed BEFORE the `armoury_key` gate in both receivers, mirroring the shipped `revert` branch. `COS_RPC_SCHEMA` is NOT bumped (additive-optional rule, same as v0.9.69's revert flag) — old peers ignore the field harmlessly.
- **New parallel store `mod._offhand_mesh_by_peer[wearer][slot/template][hand_field] = unit_path`,** kept SEPARATE from `_la_equips_by_peer` so the armoury-key-centric reconcile / paint / revert machinery is byte-for-byte untouched (no LA-sync regression surface). Populated by the new `cos_la_apply` `offhand_unit` branch only.
- **Emit:** new `mod._send_offhand_mesh` (host-short-circuit / client-request / deferred-queue routing cloned from `_send_la_revert`) + `mod._store_offhand_mesh_recv` (writes the parallel store, enforces per-(wearer,slot,hand) mutual exclusion vs the LA store both directions, and native-pulses the wearer's unit so the swap shows without a manual re-wield). A committed vanilla offhand press queues a deferred `offhand_unit` message on Apply/screen-exit (Apply gate respected).
- **Husk apply:** `BackendUtils.get_item_units` husk branch now reads the parallel store after the LA branch and forces each recorded hand's mesh, package-gated via `_override_package_ready` (`<unit>` + `<unit>_3p`) — a non-resident unit degrades to the base mesh, never the `World.spawn_unit` C-assert (#270/#392 class).
- **Hot-join:** `cos_la_state_req` reply now also replays the vanilla offhand meshes to a late joiner (reuses `cos_la_apply`). Disconnect purge drops the peer's parallel entries.
- **Wire safety (the #421 floor is explicitly intact):** the whole path rides a VMF mod RPC that non-mod peers never receive, and `offhand_unit` is a plain string — never a `NetworkLookup` index, never a vanilla-RPC param. No modded key can ride a vanilla RPC into a non-mod peer's `NetworkLookup`. The `[cos:sync]` diagnostics emit the decision at the store (`offhand_mesh_store/…`) and husk apply (`husk_vanilla/… decision=APPLIED-vanilla-mesh|SKIP(package-not-resident)`).
- **Remaining (not in this slice):** `opt.vanilla_skin`-only opts (a paired vanilla weapon_skin with no `opt.unit` mesh) are NOT networked (the parallel store carries a unit path only); the fix-direction-#3 data-driven picker registration (CWV shields absent from the picker) is untouched; cross-session auto re-emit of a vanilla offhand pick (peer applied it last session, then rejoined) relies on the wearer re-Applying — in-session apply + hot-join are covered.

## 0.9.81-dev — 2026-07-12 — #499 rename _diag_probe.lua -> _cos_diag_lasync.lua (per-cluster diagnostics convention) [untested]

- **#499 probe consolidation (PROJECT_STANDARDS §2.2b):** the passive diagnostic emitter now serves ONLY the open-issue [cos:sync] LA husk/shield sync-divergence cluster (#149/154/200/203/204) after #500 stripped the closed-#174 loadout emits in 0.9.80-dev. Renamed the root-level `_diag_probe.lua` -> `_cos_diag_lasync.lua` (git mv, one path) so its name states its cluster, per the `_<ns>_diag_<topic>.lua` convention (canonical: ct_dev's `_ct_diag_freeze487.lua`).
- **Content byte-identical except the file-header comment.** The `M.emit` / `M.caller_hint` code is unchanged; only the header docstring was rewritten (new name + LA-sync-only purpose + `Owned by:` line per §2.2). The 16 `PROBE.emit("cos:sync", …)` call sites in `cosmetics_tweaker.lua` are untouched, so the [cos:sync] printf prefixes are unchanged.
- Updated references: `cosmetics_tweaker.lua` dofile + comment (line ~53-55), `DEVELOPMENT.md` module list, `ENGINE_SURFACE.md` diagnostic-hooks note. Package is glob-based (`scripts/mods/cosmetics_tweaker/*`), so no `.package`/manifest entry changed.

## 0.9.80-dev — 2026-07-12 — #500 strip the closed-#174 loadout-attribution probe, keep the open-issue [cos:sync] probes [untested]

- **#500: removed the two `[174:loadout]` probe emit sites** (issue 174, CLOSED). The dedicated `#174 VANILLA CHOKEPOINT` `mod:hook_safe("BackendInterfaceItemPlayfab", "set_loadout_item", ...)` was pure post-observation (no return override, no behavior) and is deleted whole. The second emit lived INSIDE the load-bearing `mod:hook(BackendUtils, "set_loadout_item", ...)` LA-clone caching hook (`_install_skin_loadout_safety`); only the `if PROBE then PROBE.emit("174:loadout", ...) end` block was stripped -- the clone-cache write / early-return / cache-clear logic is kept byte-for-byte, so the skin-loadout-safety behavior is unchanged.
- **KEPT `_diag_probe.lua` byte-identical** (git-verified no diff). It is the shared passive emitter (`M.emit` / `M.caller_hint`) still consumed by the OPEN-issue `[cos:sync]` probes (16 emit sites: issues 149, 154, 200, 203, 204 -- LA husk/shield sync divergence). The `PROBE` import stays. Only the file-header comment describing the two channels was updated to drop the now-retired `[174:loadout]` channel.
- No `.package` edit (glob) and no dofile-manifest change: `_diag_probe.lua` is still dofile'd; only the probe call sites in `cosmetics_tweaker.lua` changed.

## 0.9.79-dev — 2026-07-12 — Structural refactor: Phase 3 OOP decomposition (no behavior change) [untested]

Third structural slice of the `cosmetics_tweaker.lua` god file (9,568 -> 9,087 lines):
the weapon glow APPLY subsystem moved VERBATIM into a new single-responsibility module,
following the Phase 1/2 discipline (function-bag moves, zero logic edits, no
hook/localization/data changes). The 505-line block was byte-compared identical against
the previous commit; the adversarial 5-class diff review (orphaned upvalues /
non-verbatim moves / dropped-or-duplicated hooks / load-order / guard drift) returned
zero findings; `lint-mod.ps1` (20 files, 93 hooks, 0 duplicate) + build pass; the new
module was verified present in the compiled bundle by the murmur64 hash of its resource
path (`EBB21A99C09EA540`, in `6448e4de51a26af1.mod_bundle`).

- New module (function-bag extraction; 572 lines): `_cos_glow.lua` — the `_COLOR_PRESETS`
  table, the shader-variable brightness/group maps (`_GLOW_VAR_BRIGHTNESS` +
  `_GLOW_GROUP_COLOR_SETTING`), the per-peer glow read helpers (`_glow_get` /
  `_glow_master_mult` / `_glow_var_mult` / `_glow_override_enabled` / `_glow_main_rgb` /
  `_glow_rgb_for_var` + `_resolve_preset_rgb` + the `_glow_local_peer_id` /
  `_glow_is_local_peer` pair), the wearer-of-unit resolver `_glow_owner_peer_for_unit`,
  the per-unit paint `_apply_glow_to_unit` and its batch wrapper `_apply_glow_override`,
  the live-preview re-paint `mod._reapply_glow_on_wielded`, the template-mutation apply
  hook `_hook_apply_with_template_mutation` (installed on `GearUtils` / `CosmeticUtils` /
  the deferred `_G.apply_material_settings` flow global) + `mod._try_install_flow_glow_hook`,
  and the custom `_cosmetics_tweaker_glow` `MaterialSettingsTemplate` + its
  `GearUtils.spawn_inventory_unit` injection hook.
- Two hook SITES moved with the block (still exactly one registration per
  `(Class, method)` — lint confirms 0 duplicates): the `apply_material_settings` x3
  template-mutation hook and the `GearUtils.spawn_inventory_unit` glow-template injection.
  They now install at `_cos_glow` dofile time (earlier in the same synchronous mod-load
  pass); game globals `CosmeticUtils` / `_G.apply_material_settings` / `MaterialSettingsTemplates`
  have identical readiness at the new install point, and the Phase 1 modules already
  install hooks at dofile time.
- Exports on `mod._cos`: `apply_glow_override` and `glow_owner_peer_for_unit`. The three
  render-hook glow call sites that stay in the entry (`create_equipment` owner-resolve +
  paint, `_spawn_item_post` paint, `LootItemUnitPreviewer.spawn_units` paint) were rebound
  to `mod._cos.*(...)`, mirroring the Phase 2 `mod._cos.scale_units` consumption pattern.
- COUPLING POINT 1 (`_unit_to_backend_id` weak map): it is a pure `mod.` field with NO
  local alias anywhere, so its owner is simply `_cos_glow` (home of its primary reader
  `_apply_glow_to_unit`), which owns the `mod._unit_to_backend_id = ... or setmetatable`
  init; every writer/reader (the `create_equipment` + `_spawn_item_unit` render hooks that
  populate it, the glow-picker diagnostic commands) already goes through
  `mod._unit_to_backend_id` unchanged — nothing to re-plumb.
- COUPLING POINT 2 (peer-owner lookup): `_glow_owner_peer_for_unit` moved into `_cos_glow`
  and is exported as `mod._cos.glow_owner_peer_for_unit`; the one entry call site (the
  in-game `create_equipment` hook) was rebound.
- LOAD-BEARING blocks LEFT IN THE ENTRY, unchanged: the per-peer glow broadcast RPC layer
  (`cos_glow_apply` / `cos_glow_apply_req`, `mod._glow_sync_tick`,
  `mod._on_glow_setting_changed`, hot-join rebroadcast) — it reads/writes the SAME
  `mod._glow_by_peer` table (whose init `_cos_glow` now owns) through a byte-identical
  entry-local `local _glow_by_peer = mod._glow_by_peer` alias set in the manifest; the
  `/glow_status` + `/glow_trace` commands (they read the already-exposed
  `mod._glow_hooks_installed` / `mod._glow_call_counts` fields + the entry-local
  `GlowPicker`); and the LA-bridge + husk, offhand picker, #421 wire senders, #282 MH
  lifecycle. `/dump_glows` is a read-only dump with no apply logic, so nothing moved from
  it — it stays in `_cos_diagnostics.lua`.
- `_cos_glow` is `mod:dofile`'d AFTER `_cos_render` because it captures the shared
  `mod._cos.is_unit` primitive; its own exports are consumed only at runtime by the render
  hooks below. Glow is client-side visual with no networked apply state, so no 2-player
  re-verify is required for this move.

## 0.9.78-dev — 2026-07-12 — Structural refactor: Phase 2 OOP decomposition (no behavior change) [untested]

Second structural slice of the `cosmetics_tweaker.lua` god file (9,712 -> 9,568
lines): the render-path weapon scale/grip apply layer moved VERBATIM into a new
single-responsibility module, following the Phase 1 discipline (function-bag moves,
zero logic edits, no hook/localization/data changes). Adversarial 5-class diff review
(orphaned upvalues / non-verbatim moves / dropped-or-duplicated hooks / load-order /
guard drift) returned zero findings — every moved function and data table was
byte-compared against the previous commit; build + `lint-mod.ps1` (19 files, 93 hooks,
0 duplicate) pass; the new module was verified present in the compiled bundle by the
murmur64 hash of its resource path (`F4A3F10DA4EE5F48.lua`, 2.87 kB).

- New module (function-bag extraction; 208 lines): `_cos_render.lua` — the two
  visual-override data tables (`_unit_path_scale_overrides` + `_breton_sword_thiccc`,
  the empty `_weapon_grip_offsets` extension point) and the resolve/apply helpers
  (`_resolve_for_career`, `_resolve_render_unit_path`, `_resolve_factor`,
  `_apply_unit_path_scale_hand`, `_scale_units`, `_offset_units`), plus the tiny
  `_is_unit` liveness primitive.
- `_is_unit` PROMOTED to `mod._cos.is_unit` because the glow subsystem (still in the
  entry this phase) consumes it. The entry keeps a byte-identical local alias
  (`local _is_unit = mod._cos.is_unit`) so all five glow / glow-dump `_is_unit(...)`
  call sites in the entry stay unchanged.
- The three apply helpers are exported on `mod._cos` (`scale_units`, `offset_units`,
  `apply_unit_path_scale_hand`); the entry's four render-hook call sites that stay in
  place (`create_equipment` scale + offset, `_spawn_item_post` scale x2,
  `LootItemUnitPreviewer.spawn_units` scale x2) were rebound to `mod._cos.*(...)`,
  mirroring the Phase 1 `mod._cos.apply_cosmetic_unlocks()` consumption pattern. This
  pre-namespaces the render call sites so a later render/glow module extraction has no
  re-plumbing to do.
- LOAD-BEARING blocks LEFT IN THE ENTRY, unchanged (deferred to a later phase with a
  2-player re-verify window): the glow subsystem, the #421 wire-safety senders, the
  #282 MH release lifecycle, the LA-bridge + husk region, and the
  HeroWindowItemCustomization offhand-picker UI suite. The render HOOKS themselves stay
  in the entry — only their scale/grip apply helpers moved.
- Manifest position of `_cos_render` is free: it has no load-time reads of other
  modules' exports, and its own exports are consumed only at runtime inside the render
  hooks; it is `mod:dofile`'d with the other `_cos_*` extractions, before the entry's
  `_is_unit` alias.

## 0.9.77-dev — 2026-07-12 — Structural refactor: Phase 1 OOP decomposition (no behavior change) [untested]

Pure structural split of the `cosmetics_tweaker.lua` god file (10,773 -> 9,712 lines):
three self-contained concerns moved VERBATIM into single-responsibility `_cos_*`
modules, following the event_tweaker template (PROJECT_STANDARDS § 2.2a). No logic
edits, no hook changes, no localization/data changes. Adversarial 5-class diff review
(orphaned upvalues / non-verbatim moves / dropped-or-duplicated hooks / load-order /
guard drift) returned zero findings; build + `lint-mod.ps1` (93 hooks, 0 duplicate)
pass; the three new modules were verified present in the compiled bundle by murmur64
hash of their resource paths.

- New modules (function-bag extractions; line counts):
  - `_cos_diagnostics.lua` (513) — read-only dump/probe chat commands: `/flush_log`,
    `/dump_glows`, `/dump_skin_rarities`, `/dump_all_names`, `/check_vmf`,
    `/probe_hat`, `/probe_cosmetics`.
  - `_cos_illusions.lua` (329) — custom weapon-illusion + LA shield skin injection
    (`_custom_illusions`, `_la_shield_skin_specs`), the `get_unlocked_weapon_skins`
    unlock hook and the `_G.Localize` display-name hook for those keys.
  - `_cos_unlocks.lua` (330) — per-career cosmetic unlocks (`apply_cosmetic_unlocks`),
    Unlock-All portrait frames, vanilla-unobtainable cosmetic grants, the two
    `PlayFabMirrorAdventure` hooks (`_create_fake_inventory_items` /
    `get_unlocked_cosmetics`) and the `/frames_status` + `/cosmetics_status` commands.
- Cross-module state now lives on a `mod._cos` namespace table (the event_tweaker
  `mod._evt` pattern): `U`, `LA_BRIDGE`, `flush_log`, `skin_requires_unowned_dlc`,
  `custom_skin_keys`, `custom_illusions`, `apply_cosmetic_unlocks`. The entry keeps
  byte-identical local aliases for the shared tables.
- LOAD-BEARING blocks LEFT IN THE ENTRY, unchanged: the #421 null-and-restore wire
  senders + `ct_*` substitution, the #282 MH package-release lifecycle
  (`on_game_state_changed` / `on_unload`), and the render-path hooks
  (`create_equipment` / `spawn_inventory_unit` / `get_item_units` / the previewers).
  `custom_skin_keys` (read by the wire senders and the regression suite) became a
  shared `mod._cos` table WITH an entry-local alias so every one of those references
  stays byte-unchanged.
- Regression suite (`/cos_regression_test`) unchanged and intact: all checks stay in
  the entry, and none are source-pattern greps, so no needle updates were required.
- Deferred to later phases (too coupled to the render path / wire safety for a
  zero-behavior mechanical move): the glow subsystem, the LA-bridge + husk block, the
  HeroWindowItemCustomization offhand-picker UI suite, and the weapon scale/grip
  overrides (their apply helpers are called from render hooks that stay in the entry).

## 0.9.76-dev — 2026-07-11 — #282 #421: MH package refcount leak (exactly-once + lifecycle release) and the two remaining skin-axis wire senders [untested] [crash] [0-critical]

### #282 — package refcount leak (the cosmetics-owned slice)

- SYMPTOM (two-peer logs on the issue thread, 2026-07-11): every hijacked wield re-loaded the
  same weapon `_3p` package (92 loads of `wpn_empire_handgun_t1_3p` in one host session);
  shutdown on BOTH peers walked ~20 `Package still referenced, NOT unloaded` lines into the
  crashify `not unloaded, this can potentially cause an deadlock` block, with in-mission
  `Locking a resource that is about to be unloaded!` co-occurrence.
- ROOT CAUSE: `_material_hijack_embedded.lua` `_safe_load_package` called
  `Managers.package:load(path, "global")` per event with no unload anywhere in the file.
  Engine semantics: `PackageManager.load` INCREMENTS a per-(package, reference_name) count on
  every call (package_manager.lua:26-27); `unload` decrements by one (package_manager.lua:196-238).
  "global" is an ordinary reference-name string (vanilla uses it for boot-lifetime packages,
  boot.lua:1759-1764), not a required mode.
- FIX: exactly-once loading per path (dedupe registry), a mod-owned reference name
  `cosmetics_tweaker_mh` instead of "global", and a symmetric `release_packages()` called on
  StateIngame EXIT (level world + every hijacked unit torn down; engine stragglers go through
  PackageManager's own delayed-unload queue, package_manager.lua:213-224) and on mod unload.
  Never called while a level world is live.
- SWEEP (same accumulate-per-event shape elsewhere in the mod): `_preload_one` (offhand
  packages) and the LootItemUnitPreviewer parent-package load were already registry-deduped;
  the previewer refs however were NEVER released (one per browser open, unique
  `LootItemUnitPreviewer<id>` reference each) - new `hook_safe` on
  `LootItemUnitPreviewer.destroy` now releases them (vanilla destroy only unloads its own
  tracked packages, loot_item_unit_previewer.lua:64-66/423-451). Offhand preloads stay
  session-lifetime by design (exactly-once, count 1, released by PackageManager.destroy).
- DIAGNOSTICS `[cos:282]` (pcall printf): first-load / dedupe-skip / unload. Solo verify:
  repeated wields of a hijacked weapon must log ONE first-load line then dedupe-skips;
  keep/mission exit logs the unload; the shutdown crashify block must be gone.
- Regression: `/cos_regression_test` check `mh_package_single_reference` fails if any
  registry path holds more than one `cosmetics_tweaker_mh` reference.
- NOTE: this closes the cosmetics-owned slice only; issue 282 stays open for the wt/cwv
  force-load audit.

### #421 — ct_* illusions CTD non-mod peers on equip (remaining senders)

- The 0.9.74 null-and-restore covered ONLY `SimpleInventoryExtension.game_object_initialized`
  (initial spawn). Two more vanilla senders encode `weapon_skin_id =
  NetworkLookup.weapon_skins[<live slot skin>]` and broadcast `rpc_add_equipment`:
  `SimpleInventoryExtension._spawn_resynced_loadout` (simple_inventory_extension.lua:1443-1457,
  encode at :1451 - fires on EVERY mid-session equip/illusion apply; this is the "on equip"
  leak) and `GearUtils.hot_join_sync` (gear_utils.lua:462-488, encode at :484 - host replays
  worn slots to each joining peer). Both now route through the shared null-and-restore helper.
  Local visuals unaffected: vanilla re-derives the slot skin inside `GearUtils.create_equipment`
  (simple_inventory_extension.lua:874), not from the nulled wire field.
- THIRD axis (different channel, same crash class): `CosmeticUtils.update_cosmetic_slot`
  encodes `NetworkLookup.weapon_skins[skin_name]` into the player_sync_data GameSession object
  (cosmetic_utils.lua:205-209/230-251); a non-mod peer decodes it on the playerlist/inspect
  read path (cosmetic_utils.lua:168-178) and fatals. The existing hook substituted LA keys
  only; ct_* keys (in `_custom_skin_keys`, never in `LA_BRIDGE.backend_to_armoury`) now
  substitute to the universal vanilla "n/a" key. Merged INTO the existing hook body (no
  duplicate registration).
- All substitutions UNCONDITIONAL - never toggle-gated (issue 371 / BUG_CLASSES 31).
  Diagnostics `[cos:421]` (pcall printf) on every null, tagged with the sender surface.
- Regression: `/cos_regression_test` check `wire_skin_null_all_senders` asserts all three
  rpc_add_equipment senders are registered (flags in `mod._cos_skin_wire_surfaces`) and drives
  the helper with the resync single-slot shape.
- Needs the 2-player verify: non-mod peer in lobby while a ct_* illusion is equipped
  (mission spawn, mid-session apply, hot-join) - peer must not crash; owner visual intact.

### Files
- `_material_hijack_embedded.lua` - dedupe registry + `cosmetics_tweaker_mh` ref +
  `release_packages`/`loaded_packages` exports (dormant no-ops included).
- `cosmetics_tweaker.lua` - MH release wiring (on_game_state_changed StateIngame exit +
  on_unload), previewer-destroy release, `_spawn_resynced_loadout` + `GearUtils.hot_join_sync`
  wire-null hooks, ct_* substitution in `update_cosmetic_slot`, helper context tag, two new
  regression checks; `MOD_VERSION` -> `0.9.76-dev`.

## 0.9.75-dev — 2026-07-07 — regression coverage for the skin-axis wire-safety hook (issue 421 / issue 371)

### Why
The v0.9.74 skin-axis wire-safety hook (`SimpleInventoryExtension.game_object_initialized`)
shipped with zero regression coverage. BUG_CLASSES §31 mandates a `wire_*_ungated` assertion
on every sender-side substitution; this was the one uncovered surface (issue-371 audit finding F1).

### Changed
- cosmetics_tweaker.lua:6061 — extracted the skin null-and-restore from the hook body into a pure
  helper `_wire_null_custom_skins(slots, send_fn)` (exposed as `mod._cos_wire_null_custom_skins`)
  so the regression check can drive the exact shipped path. Behavior-preserving: the hook still
  nulls every `_custom_skin_keys` skin on the wire, runs vanilla, restores the real skin, and
  threads up to four vanilla returns. The null takes no toggle argument by construction.
- cosmetics_tweaker.lua — new `/cos_regression_test` check `wire_skin_null_ungated`: seeds a fake
  `_custom_skin_keys` entry + fake slot table, drives the helper, and asserts the custom skin is
  nil during the wrapped send, the vanilla skin is untouched, the custom skin is restored after,
  and vanilla returns are threaded. A default-off gate on the null would leave the skin non-nil
  at send time and fail the check. Mirrors cim's `wire_rarity_rewrite_ungated`.
- cosmetics_tweaker.lua:68 — namespaced the bare `_G._MEM_PROBE_T0_COS` global under the mod table
  (`mod._cos_mem_t0`); updated the boot mem-probe readout reader.

### Notes
- Coverage + refactor only; no gameplay behavior change. The larger 4-surface `_wire_safe_call`
  unification (audit finding F5) is deferred and is now guarded by this test.

## 0.9.74-dev — 2026-07-07 — issue 421: ct_* custom weapon illusions CTD non-mod peers on equip [verify-fix] [crash] [0-critical]

Found by the issue-371 cross-mod wire-safety audit. The three existing net-safe surfaces
cover the item/attachment NAME axis (all LA-keyed); the custom weapon-illusion SKIN axis
was uncovered.

- SYMPTOM: applying one of the 4 custom ct_* weapon illusions (ct_es_mace_gk_shield_01 on
  es_mace_shield; ct_es_heavy_spear_deus_01/02/03 on es_2h_heavy_spear) crashes every lobby
  peer without cosmetics_tweaker, on mission spawn.
- ROOT CAUSE: the ct_* key is written into slot_data.skin. Vanilla
  SimpleInventoryExtension.game_object_initialized encodes
  weapon_skin_id = NetworkLookup.weapon_skins[slot_data.skin] and broadcasts rpc_add_equipment
  to every peer (simple_inventory_extension.lua:258-264); a non-mod peer cold-decodes the
  appended index at inventory_system.lua:300 -> strict __index fatal (network_lookup.lua:2362).
  Same class as the shipped fa479a72 crash. The LA-bridge substitution doesn't cover ct_*
  (keys live in _custom_skin_keys, never in LA_BRIDGE.backend_to_armoury).
- FIX (FOURTH sync surface): hook SimpleInventoryExtension.game_object_initialized; null any
  _custom_skin_keys key on the WIRE (encodes as the universal vanilla "n/a" index), restore
  the slot's real skin after the send so the local owner still spawns the custom illusion.
  Remote peers render the base skin. Mirrors cwv v0.1.373-dev.
- Needs a 2-player (cosmetics host + vanilla client) verify.

## 0.9.73-dev — 2026-07-06 — Regression battery for the LA sync fixes (issues closed on user sign-off)

Five new `/regression_test` checks locking the 0.9.69-0.9.72 fixes: `cos_la_reconcile_and_pull_wired` (extended: purge tick, offhand restore, persistence API), `cos_la_reconcile_no_entry_terminal` (#264 revert-safety), `cos_la_peer_purge_defer_and_execute` (BUG_CLASSES 24, functional), `cos_la_revert_recv_deletes_entry` (#265, functional), `cos_la_offhand_persistence_roundtrip` (save/read/clear round-trip, functional). All use fake peers/backend_ids and leave no residue. Issues #264 #265 #267 #268 #270 #373 closed on user in-game sign-off 2026-07-06; #266 stays open for the slice-6 data-parity deliverable.

## 0.9.72-dev — 2026-07-06 — FIX: illusion landing on the WRONG weapon (weapon-identity guard in the apply core) + legacy slot-key namespace retired

> From the 2026-07-06 18:16/18:27 session (user HOSTING, first session where sync held into missions). User report: the illusion appeared on a different weapon after changing.

### Root cause (log + code evidence)
The store keys one offhand pick under THREE namespaces - weapon item key, template key, and a legacy WIELDED-SLOT key ("slot_melee", minted only by the hot-join replay; live in this session: host emit `slot=slot_melee key=Kruber_bret_shield_basic2_Luidhard01` at 18:35:44.704, and the state-pull ack `count=3` shows all three stored). Meanwhile `_apply_la_on_unit`'s offhand branch IGNORED the stored key and painted whatever left-hand unit was currently wielded. Any recv/retry/transition reconcile that fired while a different weapon was in hand painted the pick onto that weapon.

### Fixes
- **Weapon-identity guard in the apply core (offhand + illusion branches).** Offhand: paint only when the stored key matches the wielded item's template/name/key/item_type; otherwise return false (retryable; the correct weapon re-applies on its own wield reconcile). Illusion: entry keys are cosmetic slots - paint only when that slot is the wielded one. Skips log once per pair: `[la-state] APPLY SKIP wrong-weapon`.
- **slot-key namespace retired at the source:** the hot-join replay now emits the weapon TEMPLATE key. Legacy "slot_melee" offhand entries still in stores can never pass the guard, so they are inert.
- **Pull self-target guard:** after leaving a session the host resolver can return our own peer id while `_is_local_server()` is transiently false (18:30:42: 8 retries against self, then GAVE UP) - a self-targeted pull now just disarms.

### Verify in-game (2 players)
Wearer applies an LA shield on weapon A, wields weapon B (another shield weapon or a left-hand-unit weapon like a bow), triggers reconciles (transition, peer join): weapon B must stay untouched on every screen; log shows `APPLY SKIP wrong-weapon` instead of a paint. Weapon A still renders correctly when wielded.

### Files
- `cosmetics_tweaker.lua` - identity guards in `_apply_la_on_unit` (offhand/illusion), hot-join replay template key, pull self-target guard; `MOD_VERSION` -> `0.9.72-dev`.

## 0.9.71-dev — 2026-07-06 — ROOT CAUSE: store wiped on every level transition (remove_player fires on transitions) + pull retry-with-ack + shield picks persist across restarts

> Diagnosis from the 2026-07-06 17:25/17:26 two-machine session (user CLIENT `...ef3befb`, Rain HOST `...beb4a3`), the first with 0.9.70's `[la-state]` instrumentation. Two defects explain the whole in-mission matrix ("only each wearer sees their own shield after leaving keep; client swaps invisible to host; host swaps visible to client").

### Defect 1 (FIX): `PlayerManager.remove_player` fires on LEVEL TRANSITIONS, wiping the store everywhere
Hard evidence: host log 17:28:20.460/.471 - `PlayerManager:remove_player` for the host's OWN peer and the client during the keep->mission load, each followed by this mod's v0.9.0 disconnect purge (`purging _la_equips_by_peer entry`). Client side identically at 17:28:17.531. Result: every machine entered the mission with an EMPTY store - which is why `TRANSITION-WALK armed ... offhand_entries=0` in every session to date, `HUSK-GATE -> no-store-for-wearer` after every transition, and no cosmetic survived into a mission. The audit's "store survives transitions" assumption (section 1.1) was false all along; every transition-window fix built on it (#233 walk, 0.9.70 reconcile) was reading a table that had just been emptied.
**Fix:** purge is now DEFERRED 30s and canceled when the peer re-adds (`add_remote_player` fires within seconds on every transition). Genuine disconnects still purge (30s later), preserving the Steam peer_id-recycling rationale. Own peer never purged. Log: `PEER-PURGE scheduled/canceled/executed`.

### Defect 2 (FIX): packets sent during a peer's load window vanish silently; the 0.9.70 pull fired exactly once
Hard evidence: client sent state-pull 17:28:26.264, re-emit 17:28:28.503, and swap emits 17:28:55.188 - the host log has NO `REQ-RECV`/reply between 17:28:00 and 17:29:14 (its own 17:28:28.932 broadcast also never reached the client). The keep-time req at 17:27:55 round-tripped in 98ms, so the wire itself is fine outside load windows. Delivery to/from a loading peer is silently dropped, and the one-shot pull had no ack and no retry - the same I9 class it was built to fix.
**Fix:** the pull retries every 5s until the host's new `cos_la_state_ack` (carries entry count) lands, capped at 8 attempts, all logged (`STATE-PULL req (attempt n/8)` / `acked` / `GAVE UP`). Ack is an additive RPC name - no schema bump; old hosts simply never ack and the client stops after the cap.

### With both fixed, the expected in-mission flow
Stores survive the transition on BOTH machines -> each machine's transition walk re-applies the OTHER side's cosmetics locally with no network needed; the retried pull covers hot-join and any residual gap; mid-mission swap emits landed outside load windows already (host->client worked at 17:29:14; client->host at 17:28:55 died only because it raced the host's load - it now re-syncs via the acked pull and surviving store on the next reconcile trigger).

### NEW: shield picks persist across game restarts (user report 2026-07-06)
`_offhand_selection` was the only LA store with no on-disk mirror - every shield illusion died with the session. Now: a committed Apply saves `offhands[backend_id][hand] = {armoury_key, vanilla_key}` into the existing `la_persisted_equips` VMF setting (additive section, backward compatible); a committed vanilla revert clears it; on boot, once the LA bridge builds its pools, picks are restored into `_offhand_selection` (same record shape as a fresh pick - mesh override + paint path identical) and the self-rebroadcast arms so peers learn them. Log: `OFFHAND-RESTORE n pick(s)`. Hat/armor/row-1-illusion persistence (`careers`/`illusions` sections) unchanged. Full illusion-system integration (inventory icons per instance, official-item edge cases) tracked in a new issue.

### Verify in-game (2 players)
1. Keep -> mission: BOTH players' LA shields render on the other's screen in mission with no re-equip. Log: `PEER-PURGE scheduled` + `canceled` pairs at the transition, `TRANSITION-WALK armed ... offhand_entries>=1` (first non-zero ever), `STATE-PULL ... acked`.
2. Mid-mission swaps: both directions now sync (client swap -> host sees it; watch `REQ-RECV` on the host).
3. Restart the game: previously Applied shield picks render on your own screen in the keep without re-equipping (`OFFHAND-RESTORE` line), and peers see them once you join a lobby.

### Files
- `cosmetics_tweaker.lua` - deferred peer purge (remove_player/add_remote_player hooks + update tick), pull retry + `cos_la_state_ack` (6th RPC, additive), offhand persistence save/clear taps + `mod._la_restore_offhand_selections`; `MOD_VERSION` -> `0.9.71-dev`.
- `_la_persistence.lua` - `offhands` section + `save_offhand`/`clear_offhand`/`get_saved_offhands` (schema unchanged, additive).

## 0.9.70-dev — 2026-07-06 — LA sync core, slices 2+2b: single reconcile entry point (#264) + hot-join pull-on-ready (#267)

> Slices 2 and 2b of `docs/LA_SYNC_CORE_AUDIT.md` (invariants I3, I9). Ships together with 0.9.69's slices 0+1 for the next playtest.

### #264 - weapon switch-back lost the cosmetic on peers (FIX, invariant I3)
Reconcile was wired per-trigger: recv, retry, transition, husk wield, and local wield each had a bespoke re-apply, and the switch-back wield fell through all of them (confirmed both directions 2026-07-03 21:41). New single entry point `mod._la_reconcile(wearer_peer, slot, tag, allow_pulse)`:
- Reads ONLY the synced store (I1), resolves ONLY the human wearer's unit (I4), applies paint via the existing `_apply_la_on_unit`, and treats mesh+paint as one gated unit (I7).
- Safe contexts (network recv / mod.update: `allow_pulse=true`) pulse a stale kind="unit" mesh via `_ensure_offhand_mesh` as before.
- Wield contexts (`allow_pulse=false` - pulsing inside `_wield_slot` would re-enter wield) now VERIFY the just-spawned mesh against the store and, on a miss (the #264 silent failure), queue a deferred pulse into `_la_pending_apply`; the drain repairs the mesh from mod.update a frame later. A switch-back can no longer die silently: it either re-renders or logs `[la-state] RECONCILE ... mesh stale after wield, deferred pulse queued`.
- All five triggers repointed: `cos_la_apply` recv, pending-drain retry (with `no-entry` now terminal so a reverted cosmetic is never re-imposed by a stale queue entry), #233 transition walk, husk `_wield_slot` post-vanilla repaint, local `_wield_slot` re-apply (the local body's stale-mesh case, previously declared out of scope, now heals via the same deferred pulse).

### #267 - hot-joiner never saw already-equipped cosmetics (FIX, invariant I9)
Every push was timed off "peer appeared" and lost the 17-25ms race against the joiner's `peer_ingame` flip (re-confirmed by the user 2026-07-06); an empty joiner store cannot self-heal. Delivery is now joiner-driven:
- New request RPC `cos_la_state_req` (additive; no schema bump - old peers ignore unknown RPC names). When a peer's own game state enters `StateIngame` (the VMF `on_game_state_changed` "enter"/"StateIngame" signal - vmf_loader.lua:118), it flags a pull; mod.update sends the request once a host peer_id resolves. The request's ARRIVAL proves the joiner is a live session member, so the host's targeted replies cannot lose the pre-ingame race.
- Host replies with one targeted `cos_la_apply` per stored (wearer, slot), reusing the existing payload shape; the joiner's recv path (mirror + reconcile) does the rest. The requester's own entries are included - after a transition they re-drive the local reconcile, hardening #233 from a second direction.
- The existing state-change re-emits and hot-join targeted replay stay as belt-and-suspenders (idempotent); the pull is the correctness path.

### Verify in-game (2 players)
1. #267: host equips an LA shield/hat, THEN the client joins - client renders both WITHOUT the host re-equipping. Log: client `[la-state] STATE-PULL req`, host `STATE-PULL reply: N entr(ies)`, client `RECV`+`RE-SWAP`.
2. #264: mid-mission, wearer swaps to secondary and back - other machine re-renders the cosmetic (watch for `HUSK-GATE` -> `HUSK-SWAP applied`, or `RECONCILE ... deferred pulse queued` -> `RE-SWAP tag=retry`). Test both directions (host wearer + client wearer).
3. #233 regression: keep<->mission transitions still re-render (TRANSITION-WALK lines unchanged).

### Files
- `cosmetics_tweaker.lua` - `mod._la_reconcile` + five trigger repoints, `cos_la_state_req` register + pull trigger/drain, RPC doc comment (5 RPCs), `cos_la_reconcile_and_pull_wired` regression check; `MOD_VERSION` `0.9.69-dev` -> `0.9.70-dev`. One ADDITIVE RPC name, no schema bump, no new hooks, no force-loads, no `World.destroy_unit`.

## 0.9.69-dev — 2026-07-06 — LA sync core, slices 0+1: revert-to-vanilla now broadcasts (#265) + wearer-scoped apply (#268) + [la-state] transport/store instrumentation

> First two slices of `docs/LA_SYNC_CORE_AUDIT.md` (invariants I2, I4, I6). No render-path restructure yet - that is slice 2 (next build).

### #265 - reverting LA -> vanilla never propagated (FIX, invariant I2)
Every equip path emitted `cos_la_apply`; every revert path only cleared local state (`_local_la_equips`, the exit queue, persistence) and sent NOTHING, so remote peers kept the stale LA cosmetic until disconnect. Now revert is a broadcast state change like any other:
- New `mod._send_la_revert` - same routing as apply (host short-circuit / client `cos_la_apply_req` / deferred queue), payload carries `revert=true` and NO armoury_key. Old-version peers drop it harmlessly at their armoury_key guard (COS_RPC_SCHEMA unchanged).
- Receiver (`mod._la_apply_revert_recv`): deletes `_la_equips_by_peer[wearer][slot]`, purges pending re-applies for that (wearer, slot), then restores the native render: offhand/illusion via a slot-level re-equip pulse (`mod._la_native_pulse` - store entry gone, so `get_item_units` re-resolves vanilla mesh AND texture; never `World.destroy_unit`); hat via native re-create (`mod._la_restore_native_hat`, only when the slot still renders the LA unit, residency-gated per the #270 class); armor clears the store and rides the next native resync (active un-paint needs LA API work, noted on issue 265).
- Wearer-side triggers: vanilla hat/armor/illusion equip over LA state (CosmeticUtils hook clear branch - guarded to the LOCAL human player; bots share the host peer_id and must not revert the host's slots), and a committed vanilla offhand pick (queued as a revert entry, drained on customization exit under the existing Apply gate; un-Applied browses still drop the queue).
- Revert-worthiness is checked against the SYNCED store (not just session-local caches) so a cosmetic restored from persistence in an earlier session reverts correctly too.

### #268 - one equip pulsed co-peer BOT units (FIX, invariant I4 targeting)
The recv-path mesh pulse looped `players_at_peer(wearer)`; a host peer owns its bots, so one host equip force-swapped bot shields to the wearer's mesh (client log 2026-07-03 21:39/21:41: three owner units per equip incl. a Witch Hunter bot shield). Now the pulse targets exactly the wearer unit, and `_wearer_unit_for_peer` resolves the HUMAN player at the peer via `PlayerManager.player_from_peer_id` (local_player_id defaults to 1 = human; bots live at 2+ - player_manager.lua:463-470) with a humans-only fallback sweep (`is_player_controlled`). Likely also the mechanism behind several #204 "stretched skin" sightings.

### Slice 0 - `[la-state]` instrumentation (invariant I6, engine printf, mod-logging-OFF visible)
The #264-comment mid-mission transport loss and the #264 switch-back render loss could not be pinned because emit routing and the husk wield gates logged only via `_dbg`/`_trace`. New bounded printf lines:
- `EMIT host->all` / `EMIT client->req` / `EMIT client DEFERRED` (+ drain variants) - which routing branch each emit took.
- `REQ-RECV` on the host BEFORE any validation/dedup - a req that reached the host but was rejected is now distinguishable from one lost on the wire.
- `REVERT[-RECV]` / `NATIVE-PULSE` - the whole revert pipeline narrates itself.
- `HUSK-GATE` / `HUSK-SWAP` / `HUSK-WIELD wearer-unresolved` - dedup'd per (wearer, template, disposition): shows on every husk wield whether the store had the entry, whether the mesh swap fired, or whether wearer resolution failed (the three silent-death candidates for #264).

### Verify in-game (2 players)
1. #265: host applies an LA shield, client sees it; host reverts to a vanilla shield (Apply) -> client's view returns to vanilla without disconnect. Log: `EMIT-REVERT-ON-EXIT` (wearer) -> `[la-state] REVERT-RECV ... -> pulse` (client). Same for an LA hat -> vanilla hat (`hat-restored`).
2. #268: host with bots equips an LA shield -> `RE-SWAP` lines name ONLY the host's own unit; bot shields untouched.
3. #264 evidence (fix lands in slice 2): weapon switch-back now leaves `[la-state] HUSK-GATE ...` lines pinning which gate ate the re-apply.

### Files
- `cosmetics_tweaker.lua` - revert sender/receiver/native-restore primitives (mod-attached, zero new top-level locals - 200-local ceiling), wearer-scoped recv pulse, human-scoped `_wearer_unit_for_peer`, three wearer-side revert triggers, `[la-state]` printf set, `cos_la_revert_pipeline_wired` regression check; `MOD_VERSION` `0.9.68-dev` -> `0.9.69-dev`. No new RPC names, no schema bump, no force-loads, no `World.destroy_unit`.

## 0.9.68-dev — 2026-07-04 — Localization: applied dev status-tag doctrine (#301)

Tagged all 15 option-title loc entries (4 group titles + 11 checkbox/numeric titles) with a dev status prefix: 10 `[working]`, 4 `[untested]` (the experimental Third-Person Equipment group + its 3 options — reimplemented, coarse positions, unverified in-game), 1 `[Issue 230] [verify-fix]` (Cosmetic Availability group — the unobtainable-cosmetic ownership fix shipped 0.9.63-dev, awaiting in-game confirmation). Tags on option titles only; tooltips, descriptions, custom-illusion item name/description entries, and the ~1272 auto-generated Cosmetic Availability sub-toggles (programmatic labels in `_cosmetic_unlocks.lua`, not literal loc entries — represented by the group tag) were left untagged. The large open LA shield/hat rendering + sync + crash cluster (#148/#149/#154/#203/#204/#228/#233/#234/#264-268/#270) has no menu option-title representation (LA-bridge rendering, not a toggle), so it is not reflected in any tag.

## 0.9.67-dev — 2026-07-03 — CRASH HOTFIX: #270 LA hat swap CTDs OTHER players (non-resident headpiece reaches engine spawn/link)

> EMERGENCY hotfix. In the 2026-07-03 21:48 three-player session, TWO viewers crashed to desktop when the Kruber mercenary wearer swapped hats. The mod's hat-swap path equips headpieces outside the native `inventory_list` declaration, so the wearer's chosen vanilla headpiece packages (`es_m_hat_01/05/07/08/09/10/12`) are NOT resident on viewer machines. The pre-existing mh_embed guard DETECTED the non-residency (7 correct `refusing to spawn` log lines across both logs) but the flow proceeded past the refusal and hit the engine two ways. Root-caused from the two crash logs' Lua stacks; wearer's own log shows no crash (resources resident locally).

### Two holes, both closed

**Crash A -- non-resident SPAWN C-assert (client ed0f25d9, 21:53:11).**
Lua stack: `rpc_create_attachment` -> `PlayerHuskAttachmentExtension.create_attachment` -> `AttachmentUtils.create_attachment` (attachment_utils.lua:16 `spawn_local_unit`) -> our mh_embed `UnitSpawner.spawn_local_unit` hook -> `World.spawn_unit` -> `Assertion failed can_get(unit_type, unit_name)` (c_api_world.cpp:67) -> CTD, on `es_m_hat_12`. Root cause: the mh_embed refusal branch logged `refusing to spawn` but then ran `return func(self, unit_name, ...)`, and vanilla `spawn_local_unit` calls `World.spawn_unit` UNCONDITIONALLY (unit_spawner.lua:294) -- so it C-asserted anyway. The "refusal" only skipped our texture work, not the spawn.

**Crash B -- `Unit.node` C-assert on the LINK path (client 294ac4b9, 21:55:53).**
`refusing to spawn es_m_hat_10` -> 678ms later `UnitApi node failed, node j_head not found in unit` -> `Assertion failed index != SceneGraph::NOT_FOUND` (c_api_unit.cpp:74) -> CTD. Stack: `PlayerUnitAttachmentExtension.update_resync_loadout` -> `spawn_resynced_loadout` -> `create_attachment` -> `AttachmentUtils.link` (attachment_utils.lua:70-71 `Unit.node`). A hat unit reached `AttachmentUtils.link` without the `j_head` attach node; `Unit.node` is an engine fatal that bypasses pcall.

### The fix (three layers; minimal, no hat-system restructure)
1. **`AttachmentUtils.create_attachment` residency gate (NEW hook).** Primary choke point -- every hat/attachment apply path funnels through it. If `item_data.unit` is a non-resident unit (`Application.can_get("unit", path)` false), skip cleanly and return the same empty `slot_data` shape vanilla produces for a unit-less item (attachment_utils.lua:38-44). No spawn, no link -> neither C-assert can fire. `item_units.unit` is provably identical to `item_data.unit` (backend_utils.lua:153; skin block never overrides `unit`), so gating on `item_data.unit` is exact -- and side-effect-free (does NOT re-call the heavily-hooked `get_item_units`).
2. **`AttachmentUtils.link` `Unit.has_node` guard.** Converted the existing `hook_safe` to a full wrapper (MERGE, not a 2nd hook -- VMF drops duplicates) so it validates every source/target node with the non-fatal `Unit.has_node` BEFORE native runs; any missing node or nil/dead unit aborts the link cleanly (no partial state). Backstops a resident-but-wrong/nodeless unit reaching link. LA-bridge queue post-logic preserved verbatim.
3. **mh_embed `spawn_local_unit` refusal returns nil, not `func()`.** Engine-boundary backstop for ANY spawn site: a non-resident unit now skips the spawn instead of delegating to the crashing native call.

### New skip diagnostics (log-visible with mod logging OFF, chat-silent)
All via the existing `[cos-la-sync]`-style `mod:info` channel (empirically lands in this user's console log; `mod:debug`/`_trace` do not):
- `[cos-hat] SKIP non-resident headpiece=<path> slot=<slot> owner=<unit>` (create_attachment gate)
- `[cos-hat] SKIP attach no-node=<node> unit=<source|target>` (link guard)
- `[cos-hat] SKIP non-resident spawn unit=<path>` (mh_embed backstop; replaces the misleading chat-spamming `refusing to spawn` mod:warning)

### Verify in-game (3 players)
Wearer plays Kruber mercenary; two others spectate. Wearer rapidly swaps between the vanilla mercenary hats (and any LA hat family). Expected on BOTH viewers: NO crash; if a headpiece package isn't resident the viewer sees the wearer bare-headed (or their prior hat) -- ugly, not fatal. Viewer consoles should show `[cos-hat] SKIP ...` lines instead of the `refusing to spawn` -> `<<Lua Error>>` -> assert -> CTD sequence. Wearer view unchanged.

### Files
- `cosmetics_tweaker.lua` -- new `AttachmentUtils.create_attachment` residency-gate hook + `AttachmentUtils.link` hook_safe->hook conversion with `Unit.has_node` guard (block-scoped `_unit_resident` helper); `MOD_VERSION` `0.9.66-dev` -> `0.9.67-dev`.
- `_material_hijack_embedded.lua` -- `UnitSpawner.spawn_local_unit` refusal branch returns nil instead of the crashing `return func(...)`; log switched mod:warning -> mod:info.
- No new RPCs, no package force-loads, no `World.destroy_unit`.

## 0.9.66-dev — 2026-07-03 — FIX: #233 transition self-heal shipped inert in 0.9.65 (texture illusions never re-painted) + arming diagnostics

> The 0.9.65-dev transition self-heal NEVER FIRED in the 2026-07-03 21:15 two-player retest: zero `[cos-la-sync] RE-SWAP tag=transition` lines in either log across multiple keep<->mission transitions, and the host's LA offhand still reverted on the CLIENT after mission->keep. Root-caused from both logs (HOST `console-...-f5038769`, CLIENT `console-...-be3b66c7`); this build fixes the walk and adds two bounded diagnostics so a silent no-op can never ship undetected again.

### Root cause (why 0.9.65 was a silent no-op)
The walk DID run and DID reach the offhand entries (proven: `on_game_state_changed` fires and the self-rebroadcast drain right above it logged `[ct la-rebroadcast] re-emitted` after transitions at 21:24:01.924 / 21:27:22.471; the client's `_la_equips_by_peer[host]` was populated by RECV at 21:19:03 / 21:23:12 / 21:24:56; and the host's husk was wielding `slot_melee` at 21:20:48, 3s into the 10s window). Two defects made it inert:
1. **Texture illusions were never re-painted.** 0.9.65's walk called ONLY `_ensure_offhand_mesh`, which early-returns for any LA variant whose `kind ~= "unit"` (`cosmetics_tweaker.lua:6707`). The reverted items in the retest were kind="texture" LA variants (the breton shields Alberic01 / Luidhard01 get RECV lines but NEVER a RE-SWAP, unlike the kind="unit" empire shield which does). So for a texture illusion the walk silently no-op'd, and the texture re-paint (`_try_apply_by_peer`) had been dropped from 0.9.65 entirely.
2. **Everything was gated behind the mesh-only path**, so the walk produced zero log lines even when it reached live entries — it looked completely dead.

### The fix
For each remote peer's cached offhand/illusion entry, within the ~10s post-transition window, re-drive the SAME apply the recv/retry paths use:
- `_try_apply_by_peer(...)` — re-paints the texture (handles kind="texture" AND repaints a kind="unit" after its swap) and returns true only when the offhand is currently wielded (its own guard reads `left/right_hand_wielded_unit_3p`, the same field the working recv path uses).
- Only when that reports the offhand wielded, `_ensure_offhand_mesh(..., "transition")` — re-swaps a kind="unit" mesh (self-gated/no-op for kind="texture"), producing the visible `[cos-la-sync] RE-SWAP tag=transition` line.

Gating the mesh pulse on the wield state (via `_try_apply_by_peer`'s return, not a duplicated field read) replaces 0.9.65's brittle pre-guard: it avoids a wasteful melee<->ranged wield flicker on a husk holding a ranged weapon and targets exactly the visible-revert case. Each `(peer|armoury)` is FROZEN once applied, so there is no per-frame repaint; the paint is idempotent and the pulse keeps its per-owner 1.5s cooldown + 3-try cap.

### Never ship a silent no-op again (two bounded diagnostics per window)
- On the first active frame: `[cos-la-sync] TRANSITION-WALK armed local=<peer> remote_peers=<n> offhand_entries=<n>` — distinguishes an empty cache from a walk that reached entries.
- On window close: `[cos-la-sync] TRANSITION-WALK done applied=<n> skipped_unwielded=<n> skipped_unresolved=<n>` — tallied from frozen per-entry dispositions (stable regardless of frame count). Two lines per transition, no per-frame spam. Reuses the existing `[cos-la-sync]` `mod:info` channel that reaches the console log with mod-logging OFF.

### Verify in-game (2 players)
Host equips an LA offhand (test BOTH a kind="unit" empire shield and a kind="texture" breton shield illusion) -> transition mission<->keep. CLIENT console should show `[cos-la-sync] TRANSITION-WALK armed ... offhand_entries>=1`, then for a kind="unit" item `RE-SWAP tag=transition ... ok=true/true`, and `TRANSITION-WALK done applied>=1`; the host's offhand should render correctly (not vanilla) on the client after the transition.

### Files
- `cosmetics_tweaker.lua` — `mod.update` transition-walk block rewritten: `_try_apply_by_peer` (texture re-paint) + wield-gated `_ensure_offhand_mesh` pulse, frozen-per-entry, with armed/summary `mod:info` diagnostics; `mod.on_game_state_changed` comment updated; `MOD_VERSION` `0.9.65-dev` -> `0.9.66-dev`. No new hooks/RPCs/force-loads.

### Also in this build: #235 - in-mission weapon preview now LIT (was pure black in 0.9.65)

> The 0.9.65-dev diagnostic build resolved the data question. Host log 2026-07-03 21:22 `[235]` lines: `env_name=environment/ui_hdr style_level=nil exposure_ok=true exposure=0.1 level_spawned=false`; `residency(shading_environment): ui_hdr=true ui_store_preview=true ui_loot_preview=false`; and the exposure experiment (`0.1 -> 16`, ~160x) left the weapon PURE BLACK per the user. Build-only; in-game verification is the user's.

#### Root cause (data-confirmed)
The mid-mission preview world runs `environment/ui_hdr` (set by gut/cim's mission-safe `_create_item_preview_widget_definition` substitute, which also strips the level -> `level_spawned=false`). `ui_hdr` is a 2D-UI tonemapping env with NO 3D scene radiance, so no exposure value can reveal the weapon (160x stayed black). The keep is lit because there the world runs `environment/ui_store_preview` + the `weapons_default_01` studio-lighting variation.

#### Fix (re-point to the resident lit env; NO new hooks; keep path untouched)
The instrument proved `environment/ui_store_preview` is RESIDENT mid-mission (`residency ui_store_preview=true`). Two existing hooks, extended in place:
- `_create_preview_widget` hook_safe (mission): after the `[235]` env/residency logs, re-point the preview world's shading env from ui_hdr to `environment/ui_store_preview` via `World.set_shading_environment(world, env, name)` -- the spawn_level re-point pattern (`script_world.lua:399-405`). Gated on `Application.can_get("shading_environment", ...)` and pcall'd; on success flags `cos_preview_env_repointed` on the world. The 16x exposure experiment was removed. Runs before the first render (`_create_ui_elements` -> `_create_preview_widget` at hero_window_item_customization.lua:367 precedes `_present_item` -> `_update_environment`).
- `_update_environment` hook (mission): when the world was re-pointed, let vanilla's requested `weapons_default_01` variation blend through (keep-identical studio lighting) instead of forcing "default"; otherwise fall back to forcing "default" (unlit but safe).

#### Why this cannot re-trigger the #228 AV
The #228 AV was specifically an UNDEFINED blend variation: `weapons_default_01` requested on `ui_hdr`, which does not define it, indexes a nil variation -> native AV. `weapons_default_01` IS a defined variation of `environment/ui_store_preview` (keep witnesses: store_window_item_preview.lua:88+1367, hero_window_gotwf_item_preview.lua:67+607, hero_window_item_customization.lua:406+1378), so on the re-pointed env it blends exactly as it does in the keep every day. The guard is structural (residency + defined-variation), which is the only real protection since the per-frame blend in `ScriptWorld.render` is native and cannot be pcall-wrapped. If ui_store_preview is ever not resident, the gate fails closed to today's safe-but-black "default".

#### Verify in-game (#235)
Mid-mission (adventure or CW), open a weapon's customization gear icon through the gut in-mission loadout panel. Expected: the 3D weapon is LIT like the keep (studio lighting), spins, and survives reroll/illusion re-present; no crash. The `[235]` log should show `re-pointed mission preview env environment/ui_hdr -> environment/ui_store_preview` and `_update_environment(mission): ... repointed=true -> ALLOW (studio-lit)`. Keep customization must look exactly as before.

#### Files
- `cosmetics_tweaker.lua` — `_create_preview_widget` and `_update_environment` hook bodies extended in place (NO new hooks): re-point to ui_store_preview + allow weapons_default_01 when re-pointed; 16x exposure experiment removed; env_name/residency `[235]` diagnostics kept. No `MOD_VERSION` bump (shares the 0.9.66-dev bump above).

## 0.9.65-dev — 2026-07-03 — DIAGNOSTIC: in-mission weapon preview renders PURE BLACK (#235 follow-up)

> The 0.9.64-dev crash fix worked (no AV, no blank) but the user's 2026-07-03 in-game test shows the mid-mission 3D weapon panel drawing PURE BLACK. Instrument-only build: it captures the data needed to pick the lighting fix and runs one bounded, self-gated exposure experiment. Build-only; the user runs it in-game and reports back.

### Corrected root cause of the black render (source-proven)
The 0.9.64-dev note predicted the weapon would render "LIT under generic UI-HDR lighting." That was wrong. Mid-mission the customization preview world is NOT `environment/ui_store_preview`, and cosmetics_tweaker does NOT own the widget definition that decides the env -- a sibling mod does. gut's in-mission loadout panel mounts this view via its "cosmetics path" (per the shipped repro line: `es_deus_01` spear+shield, cog opened via the gut panel, `gut logged "customize view mounting mid-mission (cosmetics path, no cim)"`); gut's `_create_item_preview_widget_definition` substitute STRIPS `level_name` and sets `shading_environment = "environment/ui_hdr"` (`gui_tweaker_dev/_gut_mission_inventory.lua:207,236`; cim's equivalent is `crafting_in_modded_dev.lua:2079-2106`). So mid-mission the preview world has NO level (no baked/level light units) and the `ui_hdr` env. `ui_hdr` is a 2D-UI TONEMAPPING environment -- its only other users render emissive 2D GUI (`HeroView._setup_hdr_renderer` hero_view.lua:167-181; `LoadingView` loading_view.lua:113-118) -- and carries no sun / ambient / IBL to light a 3D object. Blending its `"default"` variation therefore leaves the weapon unlit = BLACK. The keep looks right because there it is `environment/ui_store_preview` + `levels/ui_store_preview/world` + the keep-resident `weapons_default_01` studio-lighting variation (`hero_window_item_customization.lua:405-406`, `:1377-1381`).

### Why instrument, not fix
The correct lighting fix cannot be chosen from source alone: the shading-environment resources are binary, so we cannot tell whether `ui_hdr` mid-mission exposes a tonable `exposure`, whether the black is under-exposure (a scalar set fixes it) vs zero captured light (needs a spawned light or a re-pointed lit env), or which lit env / light unit is actually resident. Per project doctrine (diagnose before mitigating), this build gathers that data instead of guessing.

### What it does (both existing hooks extended -- NO new hooks)
- `_create_preview_widget` `hook_safe` (mission branch): logs `[235][cos] mission preview: env_name=... style_level=... env_obj=... exposure_ok=... exposure=... blend[1]=... level_spawned=... osd_level=...`. `env_name`/`style_level` are read DIRECTLY off the widget style (`UIWidget.init` keeps `widget.style` verbatim, ui_widget.lua:15,41), so we get the definitive mission env name and whether the level was stripped without inference; the rest is env-object validity + tonemap exposure via `ShadingEnvironment.scalar` + the live blend target. Plus a `[235][cos] residency(shading_environment): ...` line probing `ui_hdr` / `ui_store_preview` / `ui_loot_preview` via `Application.can_get` (each pcall-guarded so a bad type string can't fatal) to plan the next-round fix.
- Bounded exposure EXPERIMENT: ONLY if the env is valid and `exposure` reads back a number, it installs a per-frame `shading_callback` (the sanctioned post-blend/pre-apply hook, `script_world.lua:120-133`) on the preview world's OWN env object that overrides `exposure` to a high test value (16.0) and logs the before/after once. Changes NO blend variation, so it cannot reintroduce the #228 AV. Keep path stays a pure pass-through.
- `_update_environment` hook: unchanged force-to-`"default"` behavior; now also logs each DISTINCT env vanilla requested (`[235][cos] _update_environment(mission): vanilla requested env=...`) to catch items whose `item_data.item_preview_environment` is not `weapons_default_01`.

### Verify in-game (what to send back)
- Mid-mission (adventure or CW), open a weapon's customization gear icon through the gut in-mission loadout panel, same as the black-render repro.
- Report whether the weapon is now VISIBLE (even over-bright/washed) or STILL BLACK, and paste the `grep [235]` lines from the console log (`%APPDATA%\Fatshark\Vermintide 2\console_logs\`). The decisive lines are `mission preview: env_name=... exposure=... level_spawned=...` (the definitive mission env name + exposure value + whether a level spawned), `residency(shading_environment): ...`, and `shading_callback: exposure X -> 16.0`.
- Outcome map: visible-after-boost => `ui_hdr` has capturable light, fix = set exposure (tune value); still-black with `exposure_ok=true` => `ui_hdr` has no 3D light, fix = spawn a light or re-point to a resident lit env (residency line says which); `exposure_ok=false` => env degenerate, different approach.

### Files
- `cosmetics_tweaker.lua` — `_create_preview_widget` and `_update_environment` hook bodies extended in place (no new hooks); outdated `ui_hdr`-render comments corrected; `MOD_VERSION` `0.9.64-dev` → `0.9.65-dev`.

### Also in this build: FIX — host's LA shield reverts to native on the CLIENT after a level transition (#233 follow-up)

The 0.9.64-dev RE-SWAP fix restored the host's LA shield on the client only when the `cos_la_apply` broadcast arrives LIVE mid-mission; it did NOT survive a mission<->keep transition. A two-player session (2026-07-03, CLIENT `console-...-8be4551c`, HOST `console-...-8ffe6f74`) proved why:

- The host DOES re-broadcast its own shield on every transition (`on_game_state_changed` -> self-rebroadcast -> `SYNC emit HOST->all wearer=<host> ... Kotbs01` at HOST 17:49:52.675, and again at 17:52:02.696). But the client logged ZERO for the host wearer afterwards — no RECV, no RE-SWAP.
- Cause is a TIMING race, not a handler bail: the host emits `network_send(...,"all",...)` ~25ms BEFORE the client's `peer_ingame` flips true (CLIENT 17:49:52.700), so the client isn't yet in the game-session and the RPC isn't delivered; nothing re-sends once it is.
- The asymmetry: the self-rebroadcast is symmetric in code, but the CLIENT (which loads slower) always emits to an already-loaded host (its own shield syncs fine every time — HOST's isolated `RE-SWAP tag=recv` at 17:49:53 is the host applying the CLIENT's rebroadcast, with the RECV line deduped), while the HOST emits to a still-loading client (dropped). The passive husk `get_item_units` swap at spawn is unreliable (the reason the active `_ensure_offhand_mesh` pulse was added in 0.9.64), and it did not restore the host's shield either (CLIENT `HUSK wield_slot entry wearer=<host>` at 17:49:52.710 with no following host-shield swap/paint).

Fix — CLIENT-side self-heal from the surviving cache (no new hook, RPC, or force-load):
- `_la_equips_by_peer` survives transitions (only cleared on peer disconnect), so the authoritative equip is already on the client. `on_game_state_changed` now arms a bounded ~10s window (`mod._la_reapply_remote_until`); `mod.update` walks `_la_equips_by_peer` for every REMOTE peer's `offhand`/`illusion` entry and drives the existing gated `_ensure_offhand_mesh` pulse once the wearer's husk spawns.
- `_ensure_offhand_mesh` self-gates (no-op once the live mesh matches, per-owner 1.5s cooldown + 3-try cap), so it converges then quiesces — no flicker, no pulse-storm. The pulse's re-wield re-runs `get_item_units` (mesh swap) and re-fires the husk paint, so no separate per-frame repaint is needed. Symmetric across peers (idempotent on the host). Diagnostics reuse the existing `[cos-la-sync] RE-SWAP` mod:info line, now tagged `tag=transition`.
- Constraints honored: no new `mod:hook` (reuses the `on_game_state_changed` VMF callback + `mod.update`); no networked-fn hook touched; no `World.destroy_unit`; no force-loads; re-apply via `_ensure_offhand_mesh`.

Files (also in this build):
- `cosmetics_tweaker.lua` — `mod.on_game_state_changed`: arm `mod._la_reapply_remote_until`; `mod.update`: new bounded per-frame drain that re-applies remote peers' cached LA offhand meshes via `_ensure_offhand_mesh` (tag=transition). No new hooks; no `MOD_VERSION` change (already `0.9.65-dev`).

Verify in-game (2 players): host equips a kind="unit" LA shield, transition mission<->keep, and confirm the CLIENT console shows `[cos-la-sync] RE-SWAP tag=transition ... ok=true/true` for wearer=<host> and the shield renders correctly (not vanilla).

## 0.9.64-dev — 2026-07-02 — FIX: post-spawn LA offhand mesh RE-SWAP (#233 host shield late on client, #234 mid-mission model change)

> Diagnosed from the 2026-07-02 client session log (`console-2026-07-02-18.36.15-228bfc0a`, prior build v0.9.63-dev; user = CLIENT of host `110000106beb4a3`). The v0.9.61-dev `[cos-la-sync]` instrumentation captured both failures in the act. Build-only; in-game verification is the user's (the new `[cos-la-sync] RE-SWAP` line proves the path fires next session).

### Shared root cause (log-confirmed)
A kind="unit" LA shield gets its MESH swapped ONLY in the spawn-time `BackendUtils.get_item_units` path. After spawn, the husk repaint and the local wield-reapply can only TEXTURE-paint, and the #204 warp-guard correctly refuses to paint LA heraldry onto the previous/vanilla mesh (`match=false → SKIP-mesh-mismatch`). So a model change that lands after the offhand already spawned silently no-ops:
- **#233:** the host's shield unit spawns on the client at mission start BEFORE the client has the host's `_la_equips_by_peer` entry, so the swap never runs; the later RECV paint SKIPs. (`18:43:44` RECV `applied=true` alongside `PAINT ... target_mesh=wpn_emp_shield_04_3p ... SKIP-mesh-mismatch`.) The existing recv-handler pulse only recovered here because the double-key emit happened to populate the template-keyed cache before its own pulse — fragile, and the `_la_pending_apply` retry only painted (never re-swapped), so a true late spawn stayed vanilla until the host manually swapped weapons.
- **#234:** a mid-mission menu swap to a different-MODEL shield; the live unit still carries the previous skin's mesh so the new key's paint SKIPs. Same-model (texture-only) swaps work because no mesh change is needed.

### Fix
- New guarded helper `_ensure_offhand_mesh(owner_unit, hand_field, armoury_key, tag)`: when a kind="unit" LA mesh is package-resident but the live wielded offhand still carries the wrong mesh, force a slot-level re-equip (pulse-wield through the other weapon slot and back) so vanilla re-runs create_equipment/`_wield_slot` → `get_item_units` re-resolves and RESPAWNS the offhand with the LA mesh. **Slot-level re-equip only — never `World.destroy_unit`** (the gt POSITION_LOOKUP nil-deref crash class). Self-gated: kind="unit" only, package-resident only (`_resolve_la_unit_mesh` `can_get`), **mesh-already-correct no-op** (no flicker on same-model re-apply), per-owner cooldown, a hard try-cap (a mesh that can't converge pulses a few times then stops — no endless flicker), and a re-entrancy guard for the pulse's own `_wield_slot` fire.
- Wired into two SAFE contexts only (never inside a `_wield_slot` body — re-entering wield during wield corrupts inventory state): the `cos_la_apply` receiver (covers the host's husk AND the local body, since the broadcast reaches `players_at_peer(wearer)` for both) and the `_la_pending_apply` mod.update retry (covers the mission-start late-spawn). The caller passes the armoury_key the respawn will actually resolve, so the post-pulse mesh converges and can't ping-pong. Replaces the old unconditional recv pulse-rewield (which flickered on every same-model re-apply).

### Anomalies checked while in there
- **`key=Kruber_empire_shield_basic3_Middenheim01 → expected=...Kruber_Empire_shield_spear01_mesh` is NOT a mapping bug.** That variant's mesh legitimately IS the spear-and-shield mesh: at `18:43:52.850` it painted onto `...spear01_mesh` with `match=true outcome=true`, and the offhand-press WRITE recorded `intended_unit=...Kruber_Empire_shield_spear01_mesh`. Self-consistent LA `SKIN_LIST` data, not a cosmetics_tweaker bug.
- **RECV lines for the user's OWN emits showing `applied=false` is expected/benign.** `applied` comes from `_apply_la_on_unit`, whose offhand branch needs the shield currently WIELDED (`left_hand_wielded_unit_3p` alive); at RECV time (right after screen exit) the local player is often wielding ranged, so it returns false. The local body is painted by the create_equipment/screen-exit path and the local wield-reapply instead, so `applied=false` on an own-emit RECV does not mean the shield was lost.

### Diagnostic
- New `[cos-la-sync] RE-SWAP tag=<recv|retry> owner=... armoury=... try=N from_mesh=... -> <la_unit> ...` line (mod:info) fires whenever the path pulses, so the next test log shows it firing and whether the mesh converges. Existing `[cos-la-sync]` / `[cos:trace]` / `[cos:sync]` instrumentation left intact.

### Files
- `cosmetics_tweaker.lua` — `_ensure_offhand_mesh` helper; recv-handler routed through it (replaces the unconditional pulse); pending-retry drives it; `MOD_VERSION` `0.9.63-dev` → `0.9.64-dev`. No hooks added (edits sit inside existing bodies).

### Also in this build: #235 - in-mission weapon preview renders again (was blank since the 0.9.62 #228 guard)

> Same 0.9.64-dev build. Diagnosed from the reporter's `console-2026-07-02-18.36.15-228bfc0a` log, where the shipped `[228:blend][cos] mission preview world neutered (had_shading_env=true)` line fired. Build-only; in-game verification is the user's.

#### Corrected #228 root cause (supersedes the 0.9.62-dev note)
The 0.9.62-dev entry blamed the AV on `ShadingEnvironment.blend(env, {"default",1})` faulting on the level-less `environment/ui_hdr` mission-substitute world. That is not the trigger. `ui_hdr` + the `"default"` variation is blend-safe mid-mission: `HeroView._setup_hdr_renderer` (`hero_view.lua:174-177`) and `LoadingView` (`loading_view.lua:113-118`) both create-and-blend exactly that every frame in a mission with no crash, and the customization window is a child of `HeroView` so its ui_hdr world is resident while the preview is open. The real trigger is a MISSING BLEND VARIATION: `_present_item` calls `_update_environment(item_data.item_preview_environment or "weapons_default_01")` (`hero_window_item_customization.lua:1377-1381`), which writes `shading_settings[1]` (`:583-594`); `ScriptWorld.render` blends `shading_settings` each frame (`script_world.lua:122`). `on_enter` runs `_create_ui_elements` (`:130`) then `_present_item` (`:132`) synchronously, so the FIRST rendered frame blends `{"weapons_default_01",1}`, never the harmless `{"default",1}`. `weapons_default_01` is a variation of `environment/ui_store_preview` (ships with the keep preview level); `ui_hdr` does not define it, so native `ShadingEnvironment.blend` indexes a nil blend object and access-violates. Signature check: a genuinely-unloaded env RESOURCE throws a clean engine `Resource not loaded` fatal, not an AV (cf. the forge case at `crafting_in_modded_dev.lua:1945-1949`), which confirms the resource is resident and only the variation is absent. The 0.9.62 neuter (nil the world's `shading_environment` so `ScriptWorld.render` early-returns before any blend) stopped the crash but skipped blend + apply + render_world, leaving the 3D weapon panel blank (#235).

#### Fix (render-preserving, chaining-independent, zero package load)
Two sites in `cosmetics_tweaker.lua`, both mission-only (keep is a pure pass-through):
- The existing `[228:blend]` `_create_preview_widget` `hook_safe` no longer neuters. It keeps the ui_hdr shading env intact so the world renders, and is now a pure `[235]` diagnostic printf.
- New `mod:hook("HeroWindowItemCustomization", "_update_environment", ...)` forces `force_default = true` in mission, pinning `shading_settings[1]` to `"default"`. `_update_environment` is the sole writer of `shading_settings[1]` (only caller is `_present_item`), so this one hook covers every re-present (reroll / illusion tabs). Blend then only ever requests the `"default"` variation `ui_hdr` actually has, so the weapon renders LIT under generic UI-HDR lighting instead of blank, with no AV and no mid-mission package hitch. No version bump (shares the 0.9.64-dev bump); grep-verified no prior hook on `_update_environment` and exactly one on `_create_preview_widget` (the site modified in place), so no VMF duplicate-drop.

#### Verify in-game
- Mid-mission (adventure or CW): open a weapon's customization gear icon. Expected: the 3D weapon appears and spins, lit by generic UI-HDR lighting (flatter than the keep studio look, plain backdrop since no preview level loads), no crash. Reroll / illusion tabs must keep it visible on re-present. Keep must look exactly as before (full per-weapon lighting). The `[235][cos]` printf should log the world kept renderable.

## 0.9.63-dev — 2026-07-02 — FIX: vanilla-unobtainable skins/hats never appeared (the per-career toggles only edited can_wield, never granted ownership) — grant all 136 via fake-inventory injection

> User wanted "Ostermark Bowman" and "Nuln Bordermarcher" (Huntsman skins) equippable and reported they were not showing, even though their `cos_unlock_es_huntsman_skin_es_huntsman_ostermark` / `_black_and_gold` toggles are saved `true` (verified in `user_settings.config`). Build-only; in-game verification is the user's.

### Root cause (source-proven)
The per-cosmetic unlock tree only ever edited `can_wield`. `apply_cosmetic_unlocks` (`cosmetics_tweaker.lua:816-849`) adds a career to `ItemMasterList[key].can_wield` when a toggle is on — that governs WHICH careers may equip an item the player already OWNS, nothing more. But a career skin/hat only appears in the customization grid if it is in the player's inventory: `BackendInterfaceItemPlayfab._refresh_items` builds `self._items` from `backend_mirror:get_all_inventory_items()` (`backend_interface_item_playfab.lua:56-76`), and the modded-realm fake inventory is built ONLY from the account's owned `unlocked_cosmetics` (`playfab_mirror_base.lua:1470-1479` → `_create_fake_inventory_items`, `:2315-2344`). Vanilla-unobtainable cosmetics are never in `unlocked_cosmetics`, so they are never owned, never in `_items`, and never shown — regardless of the toggle. These skins already carry their native career in `can_wield` (e.g. `skin_es_huntsman_ostermark` has `can_wield = {"es_huntsman"}`, `item_master_list_exported.lua:517-519`), so the toggle edit was a no-op for them. The mod injected only portrait FRAMES into the fake inventory (`_inject_all_frames`, gated on `unlock_all_frames`), never skins/hats. That is the gap.

### What "unobtainable" means here (full cross-reference sweep)
Enumerated every `item_type == "skin"`/`"hat"` entry across all `item_master_list*.lua` (517 cosmetics) and cross-referenced each against every obtain path: Lohner's Emporium catalog (`store_data.lua`, 455 keys), premium store + bundles (`store_dlc_settings.lua` / `store_bundle_layouts.lua`), the `steam_itemdefid` field (Steam grant), `required_dlc` (DLC grant), `store_optional_skin`/`store_optional_hat` bundling, `base_skin` defaults, and all `achievement*` files. 136 hero cosmetics (54 skins + 82 hats) have NO path at all — verified independently by grepping all 136 keys across `scripts/` outside the item-list/render files: 0 hits. These split into the datamined `_white` "(Purified)" prestige set (rarity `unique`, from eight_ball/cog/lake/woods/shovel) and discontinued promo skins/hats (Nuln Bordermarcher = `skin_es_huntsman_black_and_gold`, Ostermark Bowman = `skin_es_huntsman_ostermark`, etc.). The 15 Versus `vs_*` pactsworn skins are excluded (not hero cosmetics).

### Fix
- New `_unobtainable_cosmetics` list (the 136 keys) + `_inject_unobtainable_cosmetics(target)` helper (`cosmetics_tweaker.lua`, next to `_inject_all_frames`). It mirrors the frame-unlock mechanism exactly: injecting a key into the `_create_fake_inventory_items` input makes vanilla turn it into a fake item and register `_unlocked_cosmetics[key] = backend_id` + `_inventory_items[backend_id]` (`playfab_mirror_base.lua:2394-2401`) — i.e. genuine modded-realm ownership.
- Wired into the two EXISTING `PlayFabMirrorAdventure` hooks (no new hooks — merged into their bodies per the VMF duplicate-drop rule): the `_create_fake_inventory_items` pre-hook now injects unobtainable cosmetics on every `items_type == "cosmetics"` build in modded realm (independent of the frame toggle), and the `get_unlocked_cosmetics` post-hook resyncs them. Both injectors guard `target[key] == nil`, so the pre-hook's real backend_ids are never clobbered.
- **Ownership respects the toggles.** `_cosmetic_ownership_enabled(key)` grants a key only if ANY of its character's `cos_unlock_<career>_<key>` toggles is on (ownership is account-wide); unchecking all of a cosmetic's Cosmetic-Availability toggles hides it again. The 4 wh_priest bless hats (not in the managed tree — wh_priest is excluded from the cross-career system) are granted unconditionally. DLC gate (`_skin_requires_unowned_dlc`) is applied before every grant.
- No changes to `_cosmetic_unlocks.lua`: all 132 managed unobtainable keys already have their native-career toggle `default_value = true`; 0 were default-off. Only the 4 priest hats are outside the managed tree (handled by the unconditional branch).

### Verify in-game
- New `/cosmetics_status` chat command (echoes to chat, since the user runs mod-logging OFF): reports modded-realm state, last inject count, and how many of the 136 are now owned in `_unlocked_cosmetics`.
- The real test: Kruber → Huntsman → customization → Skins should now list "Ostermark Bowman", "Nuln Bordermarcher", and "Huntsman (Purified)". A full restart is required after any toggle change (`get_unlocked_cosmetics` runs once at PlayFab login).

### Risk
- Injecting ownership of a cosmetic the player already owns is an idempotent no-op (guarded on `target[key] == nil`), so any over-inclusion is harmless. Asset-existence of the `_white` material packages is still an in-game render check (they reuse the shared base mesh with only a material swap, so worst case is a fallback material, not a crash).

### Files
- `cosmetics_tweaker.lua` — `_unobtainable_cosmetics` list + `_inject_unobtainable_cosmetics` + `_cosmetic_ownership_enabled` helpers; the two `PlayFabMirrorAdventure` cosmetic hooks extended to inject skins/hats; new `/cosmetics_status` command; `MOD_VERSION` `0.9.62-dev` → `0.9.63-dev`.

## 0.9.62-dev — 2026-07-02 — FIX: native Access-Violation crash opening the weapon-customization screen in a mission (ShadingEnvironment.blend, #228)

> Diagnosed from the reporter's crash log `console-2026-07-02-05.13.47-...8e770416`. Crash `<<Crash>>Access violation (0xc0000005)` at 05:19:20, ~1s after opening the loadout-panel gear icon mid-mission on warcamp (Against the Grain) for `es_deus_01` (spear + shield). Build-only; in-game verification is the user's.

### Root cause (crash-stack + source proven)
Lua stack: `[0] =[C] blend <- foundation/scripts/util/script_world.lua render <- foundation/scripts/managers/world/world_manager.lua render`. The customization view (`HeroWindowItemCustomization`) builds a 3D weapon-preview world via its viewport UI pass (`ui_passes.lua:2436-2492` → `WorldManager.create_world` → `ScriptWorld.create_shading_environment`). In the keep it spawns `levels/ui_store_preview/world` + `environment/ui_store_preview` (both keep-resident, `hero_window_item_customization.lua:405-406`). Mid-mission that preview level is not loaded, so cim/gut strip `level_name` and substitute `shading_environment = "environment/ui_hdr"` (`crafting_in_modded_dev.lua:2086`, `gui_tweaker_dev/_gut_mission_inventory.lua:236`; gut's def won the VMF chain here — its printf `serving level-free preview widget def` is in the log). The world MOUNTS cleanly (no "Resource not loaded" fatal), but on the first rendered frame `ScriptWorld.render` calls `ShadingEnvironment.blend(shading_env, {"default",1})` on that level-less substitute world and access-violates on a null. The "`environment/ui_hdr` is always available" assumption in cim/gut holds for MOUNT, not for the render-time blend of a level-less mission preview world. (This is the same `script_world.lua blend` fault cim already flagged as the reason its in-mission Athanor stays keep-gated, `crafting_in_modded_dev.lua:1814-1817`; that path was gated, this preview path was not.)

### Fix (chaining-independent)
New `hook_safe("HeroWindowItemCustomization", "_create_preview_widget", ...)`. Vanilla calls `_create_preview_widget` AFTER the viewport pass has already created the world (`hero_window_item_customization.lua:373-380`), and no mod hooks it (no VMF duplicate-drop). Post-hook, in mission only, it neuters the freshly created preview world: clears the world's `"shading_environment"` data so `ScriptWorld.render` early-returns at its `if not shading_env then return end` guard (skips blend, apply, and `render_world`), and sets `"avoid_blend"` as belt-and-suspenders. This is robust to WHICH mod's preview-def hook won the chain, because it mutates the actual created world downstream of def creation. Teardown is unaffected: `WorldManager.destroy_world` frees the world via `Application.release_world` and never reads the `"shading_environment"` data key. Keep path untouched (full store-preview lighting). Cost in mission: the 3D weapon-spin panel is blank; the 2D illusion grid + Apply still work (the usable-in-mission goal of #172).

### Diagnostics
- `[228:blend][cos]` printf (engine `printf`, survives mod-logging-OFF) on the guarded path: logs whether a preview world was found and that it was neutered. If the AV recurs, the next log shows whether this guard fired.

### Follow-up (report, not fixed here)
- **gut_dev** `_gut_mission_inventory.lua:207,236` sets `_CUSTOMIZE_MISSION_SAFE_ENV = "environment/ui_hdr"` and its comment claims that env is "always available" — true at mount, false for the render blend. gut_dev owns the def that won this crash's chain; it should either drop `shading_environment` from its level-free def or apply the same post-create neuter. This cosmetics_tweaker guard already covers gut's def in the field (it runs downstream), so it is not a blocker.

### Files
- `cosmetics_tweaker.lua` — new `_create_preview_widget` hook_safe (#228 guard); `MOD_VERSION` `0.9.61-dev` → `0.9.62-dev`.

## 0.9.61-dev — 2026-07-02 — FIX: stale LA offhand broadcast when the final pick is vanilla (#203) + [cos-la-sync] send/recv instrumentation

> Diagnosed from the 2026-07-02 client session log (`console-2026-07-02-05.13.47`, this build's predecessor v0.9.60-dev, user as CLIENT of host `110000106beb4a3`). Build-only; in-game verification is the user's (host log needed to close the loop — see below).

### Root cause (log-proven, deterministic — NOT a race)
`_ct_on_offhand_pressed` wrote the deferred peer broadcast queue `mod._pending_la_emit_on_exit[bid|hand]` **only inside the `if opt.la_armoury_key` branch** (LA picks). A subsequent **vanilla** press updated `_offhand_selection` (so the live body rendered the vanilla shield) but left the **stale LA key still queued**. On screen exit the drain broadcast that stale LA key to the host. The log shows it exactly: the user's final press was `GK Shield (Green)` (vanilla → live body `RESOLVE ... resolved_unit=wpn_emp_gk_shield_04 kind=nil`), yet the exit emit sent `armoury=Kruber_empire_shield_basic2_Kotbs01`. Wearer renders vanilla, peers/host get the stale LA shield — the reported "host could not see it on me" divergence class. The local body's own #203 re-apply then correctly hit the #204 warp-guard (`match=false → SKIP-mesh-mismatch`, target_mesh `wpn_emp_gk_shield_04` vs expected `Kruber_Empire_shield02_mesh_Kotbs01`) because the mesh was never swapped for that vanilla-final pick.

### Fix
- **Clear the stale queue entry on a non-LA press.** New `elseif opt then` branch in `_ct_on_offhand_pressed`: when the pressed option has no `la_armoury_key`, delete `mod._pending_la_emit_on_exit[bid|hand]`. "Last pick wins" now holds for vanilla picks too, so the exit-drain broadcasts only what the wearer actually left equipped. No RPC-schema change; happy path (last press IS the LA shield) is untouched — that press takes the existing `if` branch, the `elseif` never runs.
- **Known follow-up (NOT fixed here):** this stops the stale broadcast at the source, but does not purge a host's *cross-session* stale `_la_equips_by_peer` entry (LA committed+broadcast in an earlier customization visit, then switched to vanilla in a later one). A true "revert to vanilla / clear" broadcast is needed for that; tracked on #203.

### Instrumentation (`[cos-la-sync]`, mod:info so it lands with VMF logging OFF)
- **Send:** `EXIT-QUEUE CLEAR` (a vanilla press superseded a stale LA emit) and `EMIT-ON-EXIT` (the authoritative offhand key actually broadcast on exit).
- **Receive (HOST log — the missing evidence):** `RECV wearer/slot/kind/armoury/applied`, deduped on `(wearer,slot,armoury,applied)` so a per-frame retry can't flood and an `applied=false→true` flip logs both. The mesh-swap + paint decision remains in the existing `[cos:sync]` `husk_meshgate`/`husk_meshswap`/`husk_offhand` printf lines.

### Files
- `cosmetics_tweaker.lua` — `_ct_on_offhand_pressed` non-LA-press queue-clear; exit-drain `EMIT-ON-EXIT` log; `cos_la_apply` receiver `RECV` log; `MOD_VERSION` `0.9.60-dev` → `0.9.61-dev`. No hooks added (edits sit inside existing bodies).

## 0.9.60-dev — 2026-07-01 — Passive diagnostic probes: #174 loadout attribution + LA sync family (#149/#154/#200/#203/#204)
- **No gameplay change.** All additions are passive, default-on, log-only probes that write via engine `printf` (so they survive the user running with VMF mod logging OFF) with a rate-limiter that logs first-sight + on-change (bounded within a startup window, hard flood cap). New file `_diag_probe.lua`.
- **#174 loadout attribution.** Added the single vanilla chokepoint the family needs: a `hook_safe` on `BackendInterfaceItemPlayfab.set_loadout_item` (the concrete backend setter every loadout write funnels through, carrying `optional_loadout_index` = the bot-vs-host discriminator). It logs `[174:loadout]` with profile/slot/item/index, a single-line caller hint (2-4 stack frames), and `mp_eac_window` (read from modded_progression's un-gate flag) so one keep visit after startup names WHO restores the bot slots. Grep confirmed no pre-existing hook on that Class.method in this mod. Also instrumented cosmetics' own `BackendUtils.set_loadout_item` cache path.
- **`[cos:sync]` LA divergence probes.** Six decision points now emit `[cos:sync]` with peer type (local/husk), item/skin key, unit, and gate decision + reason: husk cross-character mesh-swap cache gate (#154), husk mesh-swap APPLIED, local/previewer offhand paint mesh-gate SKIP/PAINT (#200/#204), husk/peer offhand paint SKIP/PAINT (#204), broadcast-receive cache write + apply outcome (#149/#154), mission-entry deferred reapply (#149), and local-body wield reapply (#203). One MP session with LA shields now yields attribution data for the whole family without repro choreography.
- **`[rpc:schema]` visibility fix.** The four cross-version RPC-drop logs (`cos_la_apply` / `cos_la_apply_req` / `cos_glow_apply` / `cos_glow_apply_req`) went only through `_dbg_alert` -> `mod:warning`, which is VMF-gated and invisible with mod logging OFF. Each now also mirrors to engine `printf` so a dropped cross-version payload is never a silent failure.

### Files
- `_diag_probe.lua` (new) — rate-limited `printf` emitter + caller-hint helper.
- `cosmetics_tweaker.lua` — loader; #174 chokepoint hook + BackendUtils probe; 6 `[cos:sync]` sites; 4 `[rpc:schema]` printf mirrors; `MOD_VERSION` `0.9.59-dev` -> `0.9.60-dev`.

## 0.9.59-dev — 2026-07-01 — Menu: fix double-localized tooltips + rewrite option descriptions
- **Double-localize fix.** Every widget-level `tooltip = mod:localize("K")` in `cosmetics_tweaker_data.lua` (11 sites) is now a raw key `tooltip = "K"`. VMF localizes each widget field itself at menu-build time, so eager-localizing produced the English sentence, which VMF then re-localized as a key, missed, and displayed wrapped in angle brackets. The lone correct eager call, the top-level `description = mod:localize("mod_description")`, is unchanged.
- **Descriptions rewritten.** All 11 option tooltips plus `mod_description` reworded to plain, player-facing English: max 2-3 sentences, no internal jargon (dropped references to meshes, item types, mod-internal cross-refs, Workshop IDs, issue numbers, and version stamps), em dashes removed, literal percent signs escaped as `%%`. Meaning preserved from the prior text; no mechanics invented.
- **Placeholder labels cleaned.** The auto-generated cosmetic-unlock tree had 92 labels showing the game's own missing-name marker in literal angle brackets (`Handmaiden/Shade/Waystalker: <test_item_1001>`, `Slayer: <dr_slayer_hair_0002>`). `_gen_unlocks.py` now strips `<` / `>` in `asciify`, and `_cosmetic_unlocks.lua` was regenerated so those labels read without the brackets. No structural or ordering changes.
- **No behavior change.** Setting ids, defaults, ranges, widget structure, and all handler logic are untouched. Menu-text only.

## 0.9.58-dev — Net: RPC schema versioning on all 4 RPCs (#45)
- **#45 — schema-version + drop-on-mismatch on every RPC** (VMF_RECIPES § 10, propagation of the ct v0.7.114-dev pilot). New `local COS_RPC_SCHEMA = 1` next to `MOD_VERSION`, prepended as the FIRST positional arg of every `mod:network_send` this mod emits (11 send sites across `cos_la_apply` / `cos_la_apply_req` / `cos_glow_apply` / `cos_glow_apply_req`) and validated as the first callback arg of all 4 `mod:network_register` receivers. On mismatch the receiver logs `[rpc:schema] <channel> mismatch ... Dropping.` via `_dbg_alert` and returns — no state mutation, no crash.
- **Wire-compat both directions is graceful here** because every receiver already guards `type(payload) ~= "table"`: a NEW sender's schema number lands in an OLD receiver's `payload` slot and fails that existing table-guard (clean drop); an OLD sender's table lands in a NEW receiver's `schema_version` slot and fails the schema gate (clean drop + log). No index-a-number crash on either side.
- **When to bump `COS_RPC_SCHEMA`:** only when any of the 4 RPCs' payload shape changes (add/remove/reorder/retype a field). Adding a new channel or logging-only changes do NOT bump it. One constant shared across all the mod's channels (per VMF_RECIPES § 10 anti-patterns).
- **Regression check:** `_rt_register("cos_rpc_schema_present", ...)` asserts `COS_RPC_SCHEMA` is a number >= 1 (run via `/cos_regression_test`).
- Payload shapes, recipients, dedup/defer/hot-join replay logic, and all handler bodies are unchanged — this is purely the version tag + gate.

## 0.9.57-dev — Menu: rename Bretonian Longsword thiccness option
- **Rename.** `es_bastard_sword_thiccc` display label: "Authentic Bretonian Longsword Thiccccness" → **"Bretonian Longsword: Authentic Thiccness"** (localized `en` string only; setting_id, widget, default, behavior, and tooltip unchanged). Still sorts before "Moonfire Bow: Cosmetic AOE" in the Weapon Visual Tweaks group, so A→Z order is preserved.

## 0.9.56-dev — Menu: rename Moonfire option to "Moonfire Bow: Cosmetic AOE" + alphabetize per-group options A→Z
- **Rename.** `cos_moonfire_cosmetic_puff` display label: "Moonfire Bow: cosmetic AOE puff" → **"Moonfire Bow: Cosmetic AOE"** (localized `en` string only; setting_id, widget, default, behavior, and tooltip unchanged).
- **Alphabetize per-group options A→Z by display label** (per the standing sort-categories rule). Only one block actually needed reordering — the two loose "unlock all" toggles at the bottom of **Cosmetic Availability** now read A→Z: **Unlock All Portrait Frames** (P) before **Unlock All Weapon Illusions** (W). Every other group was already in label order: *Loremaster's Armory* (Disable Okri's Challenges → Hide quest markers → Hide unread-letter notifications → Kill-quest crash guard); *Weapon Visual Tweaks* (Authentic Bretonian… → Moonfire Bow…).
- **Kept exceptions (deliberate orders preserved):** (1) **Third-Person Equipment** — `tpe_enable` ("Show Unwielded Weapons on Body") kept FIRST as the feature's master-enable, with its two dependent options ("Hide Own Equipment in First Person", "Holstered Weapon Scale %") A→Z after it (rather than burying the enable at the bottom of a strict A→Z sort). (2) **Cosmetic Availability** kept LAST among the top-level groups and its large auto-generated Character→Career unlock tree kept its hierarchy (only the two loose toggles below it were sorted) — both per the 0.9.51-dev layout. Pure reordering + one rename; no option added/removed/retuned.

## 0.9.55-dev — 2026-06-30 — FIX: in-mission LA shield drop on the local body (#203) + Empire Sword & Shield wrong-mesh texture wrap (#204) — TRACE-CONFIRMED

> User tested 0.9.53-dev: the keep preview-leak fix (#200) WORKS (previewing no longer applies; correct for clients). Two issues remained, both fixed here. Build-only; in-game verification is the user's. (Supersedes the unshipped 0.9.54-dev intermediate — both fixes were validated against the real 0.9.53-dev session trace before shipping; see the TRACE CONFIRMATION note below.)

### TRACE CONFIRMATION (0.9.53-dev session log)
The 0.9.53-dev in-game trace (mod:info-routed) directly confirmed the #203 root cause and forced one refinement:
- The HUSK path works — peer `110000106beb4a3` shows `RESOLVE husk-mesh-swap APPLIED` + `HUSK wield-repaint` (Empire Middenheim LA shield) on every husk wield. The LOCAL player's `TRANSITION WIELD local` lines have NO corresponding re-apply — the local body never re-paints on wield. Confirmed.
- The local player (host) records its OWN offhand in the synced cache (`SYNC emit HOST->all wearer=<local> … kind=offhand`; `SYNC recv wearer=<local> applied=true`), keyed by BOTH the weapon_key AND the template — so the #203 fix's data source (`_la_equips_by_peer[local_peer]`, matched by `stored_key == wielded_template`) is valid.
- **Refinement forced by the trace:** the working `create_equipment` "ingame" paint hits TWO units — the 3P (`…_mesh_3p`) AND the 1P (`…_mesh`). The local player sees their shield in FIRST PERSON, so re-painting only the 3P (the husk-only path) would NOT restore what the user sees. `_apply_la_on_unit` (offhand) now paints BOTH `left_hand_wielded_unit_3p` and `left_hand_wielded_unit` (the 1P unit, set by vanilla `_wield_slot` at `equipment.left_hand_wielded_unit = slot_data.left_unit_1p` before it returns). Husks have no 1P unit (nil → skipped), so the husk path is unchanged.

### #203 — in-mission LA shield illusion DROPS on the local player's OWN body (mission-entry + primary↔secondary↔back swap)
- **User report:** *"going into a mission and having it not properly equipped is still there. When swapping from a primary weapon to secondary and back, it clears the Loremaster skin."* This is the previously-DEFERRED BUG 3 (area-load drop) + BUG 4 (weapon-switch-back drop) of the #150 family, left logging-only in v0.9.45-dev.
- **Confirmed root cause (code-read).** The HUSK path (peers' view) re-applies the LA offhand on every wield — `SimpleHuskInventoryExtension._wield_slot` is wrapped to re-resolve the mesh-swap (`get_item_units` + `_current_husk_wield`) and re-paint via `_apply_la_on_unit` reading `_la_equips_by_peer[wearer]`. But the **LOCAL player's OWN body had no equivalent re-apply**: the local `SimpleInventoryExtension._wield_slot` hook was diagnostics-only (glow popup + trace), and its own comment stated *"on the host's OWN body a local _wield_slot does NOT re-run create_equipment."* Vanilla local `_wield_slot` only toggles `set_unit_visibility` on already-spawned units (no respawn), so the LA shield paint was missing on the player's own screen after a mission-entry race or a melee↔ranged↔melee swap.
- **Fix.** Mirror the working husk re-apply for the LOCAL player, **merged into the existing** `SimpleInventoryExtension._wield_slot` hook (no new hook): after vanilla, read `_la_equips_by_peer[local_peer]` (the same synced cache the husk uses, populated on Apply via `_send_la_apply`) and re-paint the wielded shield via the same `_apply_la_on_unit` helper. **OFFHAND only** — kind="illusion" is deliberately excluded (its re-apply routes through LA's `apply_new_skin_from_texture`, which permanently mutates inventory icons; re-running it per wield would amplify that). Also corrected the hook's long-misaligned param names to vanilla's `(self, equipment, slot_data, unit_1p, unit_3p, buff_extension)` signature (the prior `(self, world, equipment, slot_name)` was harmless but made the trace log a unit where it meant the slot name). ADDITIVE (paint idempotent) + GATED (the #204 warp guard inside `_apply_la_on_unit`); does NOT touch the husk path.
- **Honest caveat.** A kind="unit" LA shield whose mesh-swap was SKIPPED at spawn (package-load race) stays plain on this path (recovering the mesh needs a respawn, out of scope) — the re-apply correctly degrades to plain rather than warping.

### #204 — Empire Sword and Shield warps the LA shield texture onto the wrong (un-swapped) mesh
- **User report:** *"Empire Sword and Shield has the shield textures getting wrapped around the wrong model when changed. We fixed this on bretonian longsword and shield, but now we have it on other shield weapons."*
- **Confirmed root cause (code-read).** `_resolve_la_unit_mesh` and `_offhand_paint_mesh_ok` are already weapon-independent (keyed off the LA variant's `new_units`, not the weapon). The warp survived because the **HUSK / peer offhand paint path was NOT mesh-gated**: `_apply_la_on_unit` (offhand kind) paints via `LA_BRIDGE.apply_offhand_to_unit(..., "network_husk")`, and the `_offhand_paint_mesh_ok` gate (v0.9.45 / extended to previewer in v0.9.53) only covered the local-body/previewer contexts in `_apply_la_offhand_to_units` — never this path. When the empire shield's kind="unit" mesh-swap is SKIPPED (e.g. `_resolve_la_unit_mesh` not ready / 3P-suffix miss), the un-gated `network_husk` paint warps the heraldry onto the un-swapped vanilla empire shield. The bret case happened to mesh-swap successfully, so its `network_husk` paint matched.
- **Fix.** Gate the `_apply_la_on_unit` offhand paint with `_offhand_paint_mesh_ok` (the same generalized mesh-match check), so a kind="unit" LA texture is never painted onto a unit whose authored mesh isn't the variant's custom mesh — across ALL shield weapons, on the husk AND the local re-apply (#203). The WORKING bret husk swaps successfully → mesh matches → gate passes (no regression); kind="texture" variants and units with an unreadable mesh name stay permissive.
- **Honest caveat.** If the un-swapped empire shield unit exposes NO readable `unit_name`, `_offhand_paint_mesh_ok` stays permissive (to avoid regressing the working preview) and the warp could persist — full `_trace_paint` (mod:info, visible with `output_mode_debug` OFF) dumps `target_mesh` vs expected `new_units[1]` on every offhand paint/skip so the next repro log pins that case precisely.

### Tracing
All new diagnostics route through `mod:info` (`_trace` / `_trace_paint`), since the user runs with VMF `output_mode_debug` OFF. Coverage added/kept for: local `_wield_slot` re-apply (`TRANSITION WIELD local`, `LOCAL wield-reapply`), and the offhand mesh-gate decision (`PAINT … match=… SKIP-mesh-mismatch`).

## 0.9.53-dev — 2026-06-30 — FIX: weapon illusion grid leak onto live character + wrong-mesh texture wrap (weapon analogue of #150) (#200)

> User report (2026-06-30): *"Clicking on a cosmetic from COT without pressing 'Apply' still shows the weapon illusion on the item when I leave the inventory. This also results in textures being wrapped around the wrong model when previewing a different model."* Treated as the WEAPON-side sibling of the OFFHAND bug #150.

### Root cause (code-read; honest scoping)
- **The row-1 MAIN-HAND weapon illusion is NOT the leak source.** A grid press only previews — vanilla `_on_illusion_index_pressed` spawns the pick into the `LootItemUnitPreviewer` and seeds the craft button; the live keep weapon's `item.skin` is committed ONLY via the modded `BackendInterfaceCraftingPlayfab.craft` hook, which fires only when the user holds the Apply/craft button (vanilla `_handle_input` requires `craft_progress >= 1`). There is no eager `item.skin` write on press, so a row-1 pick genuinely cannot stick without Apply. (Verified against `Vermintide-2-Source-Code/.../hero_window_item_customization.lua` + every `HeroWindowItemCustomization` hook in this mod.)
- **The actual without-Apply commit is the OFFHAND (shield) row.** `_ct_on_offhand_pressed` writes the module-global `_offhand_selection[backend_id]` on a genuine cell click and queues `mod._pending_la_emit_on_exit`. The existing `HeroWindowItemCustomization.on_exit` hook then drained that queue **and pulse-wielded the live body** — committing the shield to the live keep weapon with **no Apply gate and no revert**. That is symptom A ("shows the illusion after I leave without Apply"). The user perceives the shield as part of the weapon illusion.
- **Symptom B (texture on wrong mesh while previewing a different model)** is the LA paint, not a mesh swap: cycling row-1 illusions re-spawns the previewer with the NEW illusion's paired shield mesh, but `_apply_la_offhand_to_units` still painted the stale `_offhand_selection` kind="unit" LA heraldry onto it. The 0.9.45 mesh-mismatch gate (`_offhand_paint_mesh_ok`) only covered the `"ingame"` context, leaving the previewer contexts un-gated.

### Fixed
- **Apply-gate the offhand commit (symptom A).** `_setup_illusions` now snapshots the equipped offhand baseline for the screen session (`mod._offhand_baseline[bid]`, taken only on a fresh open so a craft-complete re-running setup preserves it). A genuine Apply is flagged in the craft-complete handlers: a **new** `mod:hook_safe("HeroWindowItemCustomization", "_apply_weapon_skin_craft_complete", …)` (the standard weapon-skin Apply completion — single registration, not previously hooked, fires regardless of cim ownership) plus the **existing** `_upgrade_item_craft_complete` hook (consolidated — set the flag there rather than add a second hook). `on_exit` now: if **no Apply committed this session**, REVERTS `_offhand_selection[bid]` to the baseline and DROPS the queued peer broadcast (so nothing reaches the live keep weapon); if committed, the prior drain + pulse-wield runs unchanged. Mirrors vanilla's row-1 "Apply required" contract. The live body never changed during browse (the #150 `_in_create_equipment` suppression already keeps it at baseline), so the revert is visually a no-op — it just stops the un-Applied pick from sticking.
- **Extend the mesh-mismatch paint gate (symptom B).** `_offhand_paint_mesh_ok` now gates **every non-husk context** (`ingame` + `loot_previewer` + `hero_previewer`), not just `ingame`. Cycling row-1 illusions can no longer warp a stale kind="unit" LA texture onto the previewer's mismatched shield mesh. No regression on the correct case: when the previewer spawned the LA mesh the gate passes (mesh matches) and paint proceeds; when the mesh is unreadable (`<no-unit_name>`) the gate stays permissive. The husk path (`"network_husk"`, always mesh-swaps first) remains un-gated. kind="texture" picks are never gated.

### Notes
- **No `is_held` change for row-1.** The teammate's "mirror the offhand `is_held` genuine-click pattern" only applies if the leak is a hover/sticky-release edge. Row-1 is vanilla's grid (vanilla `_handle_input`/`_on_illusion_index_pressed` handle hover/press; the mod adds no row-1 press handler that could fire on hover), so no `is_held` memory is needed there. The offhand `is_held` gate from 0.9.52 is unchanged.
- Diagnostics route through `mod:info` (`[cos:weapon-leak]` revert line + the existing `_trace_paint` `SKIP-mesh-mismatch` line), since this user runs with VMF `output_mode_debug` OFF.
- **Not in-game verified.** Compile + duplicate-hook lint pass only. Needs the user to confirm in the keep: pick an offhand shield → leave without Apply → it reverts; cycle row-1 illusions → no warped texture on the preview shield; pick + Apply → it sticks. Husk/previewer browse paths intentionally left working.

## 0.9.52-dev — 2026-06-30 — FIX: hovering offhand shield illusions applied to live character (#150) + trace visibility
- **Hover-applies-skin fix (#150).** Mousing over offhand (shield) illusion-grid cells was applying the hovered skin to the **equipped shield on the live keep character** without clicking. Root cause pinned from the user's 2026-06-30 `[cos:trace]` repro: an `on_release` edge fires on the grid cell while merely hovering, and the 0.9.45 `is_hover` guard let it through (hovering a cell means the cursor *is* over it → `is_hover=true`). The leaked press wrote the offhand selection, which a subsequent equipment rebuild (`HeroWindowLoadoutConsole.on_enter`) then painted onto the character's husk mesh (`network_husk` paint of `Kruber_bret_shield_hero1_Alberic01` onto `wpn_emp_gk_shield_03_3p`).
  - **Fix:** added a one-frame `is_held` memory per offhand cell. The press now only acts when the cell was actively **held** (mouse button physically down) on the current or previous frame **and** the cursor is still over it at release — i.e. a genuine click. A pure hover never sets `is_held`, so it is ignored; a drag-off (release off the cell) is cancelled. The previewer/browser thumbnails still update on hover (that's expected); only the leak to the live character is stopped.
- **Trace logging now visible (#150).** The `_trace` channel (`[cos:trace]` INPUT / WRITE / RESOLVE / SYNC / HUSK / TRANSITION) routed through `mod:debug`, but this user runs with VMF `output_mode_debug` OFF — so that entire trace set was **invisible** in their logs (only the `mod:info` PAINT lines + `[offhand-press]` survived), which is why the full hover→write→husk chain and bugs 3/4 never showed. `_trace` now routes through `mod:info` (proven to land in their console log), so the next repro captures the complete causal chain.

## 0.9.51-dev — 2026-06-30 — Settings menu reorg (LA group, Cosmetic Availability, relabels)
- **New "Loremaster's Armory" group.** All four LA integration toggles are now collected under a single top-level group instead of each carrying an `LA:` label prefix. Labels de-prefixed: `Disable Okri's Challenges`, `Hide quest markers`, `Hide unread-letter notifications`, `Kill-quest crash guard` (sorted A→Z within the group). Setting IDs unchanged, so existing saved values carry over.
- **Unlock toggles moved into Cosmetic Availability.** `Unlock All Weapon Illusions` and `Unlock All Portrait Frames` are now loose options at the bottom of the **Cosmetic Availability** category (no longer top-level). Dropped the `(Modded Only)` suffix from both — with this mod installed the player already knows they're in modded realm (the tooltips still spell out the modded-realm behavior). Setting IDs unchanged.
- **Relabel:** `Weapon & Item Appearance` → **Weapon Visual Tweaks** (`appearance_group` id unchanged).
- Top-level groups now ordered A→Z (Loremaster's Armory · Third-Person Equipment · Weapon Visual Tweaks) with the large Cosmetic Availability tree kept last so it doesn't push the small option groups down. No behavior change — pure menu structure / labels.

## 0.9.50-dev — 2026-06-29 — FIX: crash equipping CWV musket (missing MH fallback texture) (#199)
- **Crash fix.** Equipping the CWV custom musket (`cwv_es_musket_custom`) with cosmetics active crashed with `_material_hijack_embedded.lua:230: Can't find a texture 'textures/T_Texture_NR'`. The embedded Material-Hijack (forked from standalone `material_hijack_patched`) hardcodes fallback texture paths `textures/T_Texture_NR` (normal) / `textures/T_Texture_MOS` (MAB) that the standalone **never shipped** — the standalone's own CHANGELOG flagged them as missing, and the file's correct defaults sit in a dead/unused `_DEFAULT_TEX_DICT`. A unit using the `mat_to_use` convention with no per-slot `normals.slotN` (the CWV musket) falls back to `T_Texture_NR`; `Material.set_texture` on a non-resident texture is an engine-level fatal.
- **Fix:** added an `Application.can_get("texture", path)` preflight (`_has_texture`, mirroring the existing `_has_unit`/`_has_package` guards) before every `material_set_texture` — a missing texture is now **skipped + warned**, not fatal. Guards both call sites: `_material_hijack_embedded.lua` (static textures) and `_material_hijack_embedded_anim.lua` (animated frames). Skipping is also the correct visual — the unit keeps the real textures its `mat_to_use` material already carries instead of a flat default. **The CWV musket unit is authored correctly; this was entirely a cosmetics_tweaker bug.**

## 0.9.49-dev — 2026-06-29 — Disable Loremaster's Armoury Okri's Challenges (#186)
- Added **LA: Disable Okri's Challenges** (`la_disable_okri_challenges`, checkbox, **default ON = challenges DISABLED**), placed beside the existing `la_killquest_crash_guard` toggle. Removes Loremaster's Armoury's quest line (its `main_quest` entry + the 12 sub-quests `sub_quest_prologue` / `sub_quest_01`..`sub_quest_10` / `sub_quest_crate_tracker`) from Okri's Book of Grudges / the achievement menu — **display, tracking AND the completion pop-ups** — plus the unread-letter notification banner.
- **Display:** new `_la_okri.lua` hooks `AchievementManager.outline` (the only hook on that pair; string-form, lazy) and returns a shallow-cloned outline whose `.categories` omits LA's category. LA's category is identified by shape — `name == "mod_name"`, or any entry / sub-entry that is an LA quest key (`main_quest` / `^sub_quest`) — never a hardcoded index. The shared outline module is never mutated; vanilla categories are untouched. Vanilla-only / LA-absent installs get the original table back unchanged (zero overhead).
- **Tracking / pop-ups:** a deferred one-time scrub (driven from `mod.update`, fires once LA is loaded and its templates exist) makes each LA quest template in `AchievementTemplates.achievements` INERT — `completed` → a function that always returns false (kept callable so vanilla `get_challenge_progression()` can't crash), `progress`/`requirements` → nil, `display_completion_ui` → false (so `setup_incompleted_achievements` never enqueues it and `_display_completion_ui` never fires "finish the level to complete the challenge"). The global key is deliberately NOT nil'd (vanilla reads templates back by id; a vanished key would nil-deref an already-initialized manager). pcall/`rawget`-guarded throughout; gated on LA being present so it can't touch a same-named key when LA is absent.
- **Notification:** the LA unread-quest-letter NewsFeed banner (`LA_unread_letter`) is silenced under the same toggle by extending the existing `condition_func` wrapper in `_la_prefix_embedded.lua` — reusing the single `NewsFeedUI.init` hook (no duplicate-hook violation).
- Everything gated on the toggle; flipping it OFF restores LA's challenges on the next restart (no live re-add, per scope). Side effect noted in the tooltip: LA's quest also unlocks a few KOTBS weapon skins on completion, so those stay locked while the challenges are disabled. LA's weapons/skins/pickups are otherwise unaffected. Keeps the `la_killquest_crash_guard` (#137) behavior intact.

## 0.9.48-dev — 2026-06-29 — Moonfire Bow cosmetic AOE puff (moved from weapon_tweaker)
- Added **Moonfire Bow: cosmetic AOE puff** under **Weapon & Item Appearance** (`cos_moonfire_cosmetic_puff`, off by default). Spawns the small blue moonfire impact puff on every Moonfire Bow (`we_deus_01*`) arrow hit — cosmetic only, no damage. Hooks the shooter's `PlayerProjectileUnitExtension` + every peer's `PlayerProjectileHuskExtension` (`hit_enemy`/`hit_level_unit`/`hit_non_level_unit`) so it shows on all screens. Skips when weapon_tweaker's `moonfire_aoe_revert` is on (that already puffs as part of the detonation). Moved here from weapon_tweaker (see wt v0.12.185-dev) — the gameplay AOE revert stays in wt.

## 0.9.47-dev — 2026-06-29 — UI: flatten redundant Weapon Model Tweaks submenu
- Collapsed the redundant **Weapon Model Tweaks** group (`weapon_model_group`) in the VMF settings. It previously also held the Weapon Glow Override menu (removed v0.9.37), which left it a single-checkbox group nested two group-levels deep (Weapon & Item Appearance → Weapon Model Tweaks → Authentic Bretonian Longsword Thiccccness). The lone toggle now sits directly under **Weapon & Item Appearance**. Removed the orphaned `weapon_model_group` localization key. No behavior change.

## 0.9.46-dev — 2026-06-28
- Removed per-mod debug toggle; diagnostics now route through VMF logging (mod:debug / mod:warning), gated by VMF output_mode_debug / output_mode_warning. (#169)

## 0.9.45-dev (2026-06-28) — FIX: LA-shield host imperial-texture-on-bret-mesh + hover hardening (bugs 1/2 + 1-hover); bugs 3/4 left tracing

> Built on the v0.9.44-dev `[cos:trace]` investigation. **All `[cos:trace]` diagnostics are retained** so the next in-game repro confirms each fix. Two solid fixes ship; the two lower-confidence bugs (3 area-load drop, 4 weapon-switch-back drop) are left logging-only because their directed fixes are already implemented in the existing sync machinery and a change risks regressing the working husk path (the reference for correct behavior).

### BUG 1/2 — FIXED — host painted the imperial shield TEXTURE onto the un-swapped BRET shield MESH; client/husk rendered correctly
Two-part, belt-and-suspenders (a missed mesh-swap is a silent visual bug):

- **(a) Shared, variant-aware mesh resolution.** New `_resolve_la_unit_mesh(armoury_key)` (next to `_override_package_ready`) derives a `kind="unit"` LA shield's 3P sibling from `new_units[2]` (fallback `..\"_3p\"`) and verifies both halves are loadable. BOTH the husk path (`BackendUtils.get_item_units`, `_current_husk_wield` branch) AND the LOCAL/live-body override path now route through it, so host-own-body and husk-view can never disagree on whether the mesh is swappable. (For today's shields `new_units[2] == new_units[1].."_3p"`, so the old `_override_package_ready` suffix check was already equivalent ON THE SAME MACHINE — the real host/client split is cross-machine package-load timing — but routing both through one resolver removes the divergence by construction and is robust to future LA variants whose 3P path doesn't match the suffix.)
- **(b) Paint gate on the actual mesh.** `_apply_la_offhand_to_units` now refuses to paint a `kind="unit"` LA texture onto an `"ingame"` (live in-keep / in-mission) unit whose authored mesh (`unit_name`) is NOT the variant's custom mesh (`new_units[1]`/`[2]`), via the new `_offhand_paint_mesh_ok`. So even if the host's mesh override is skipped (readiness/package timing), the imperial heraldry is no longer warped onto the vanilla bret shield — it degrades to the plain shield instead. The husk path (`"network_husk"`, always mesh-swaps first) and the previewer paths are NOT gated (avoids regressing the working preview); `kind="texture"` picks and units without a readable `unit_name` are never gated. Non-fatal (`_unit_mesh_name` is pcall-guarded). The `[cos:trace] PAINT … match=…` line now shows `SKIP-mesh-mismatch` when the gate fires.

### BUG 1 (hover half) — HARDENED — model changed on mouse-over with no click
The offhand-row already fires on the vanilla `on_release` press edge. Added a defensive hover→no-mutation boundary: the release edge is consumed but only **acted on** when the cursor is actually over the row (`hotspot.is_hover`). A genuine click (incl. a fast click) releases over the hovered row, so click-to-select is unaffected; a drag-off correctly cancels; a sticky/leaked `on_release` that fires while the cursor is elsewhere (the #37 class) is consumed but ignored, and traced as `INPUT PRESS … IGNORED`. If the user still sees a hover-change after this, the residual is most likely the vanilla illusion-grid previewer reflecting hover (left untouched — fighting it would break vanilla preview), and bug 1/2(b) prevents any warped texture from a stray paint regardless.

### BUG 3 (area/level-load drop) — LEFT LOGGING-ONLY
The directed fix (HOST re-broadcasts its LA offhand on game-state-change so existing peers re-resolve) is **already implemented**: `mod.on_game_state_changed` sets `_la_self_rebroadcast_pending`, and the `mod.update` drain (section B) re-emits the local player's offhand selection keyed by template via the existing `cos_la_apply` machinery (idempotent, dedup-guarded). The host-keeps-warped-texture half of this bug is the SAME local-path issue fixed by bug 1/2 above. The residual client-loses-illusion symptom couldn't be pinned to a safe code change without risking the working husk re-apply path, so it's left tracing — the `[cos:trace] SYNC emit/recv` + `TRANSITION` lines will show on the next test whether the re-emit fires and applies across the transition.

### BUG 4 (mission weapon-switch-back drop) — LEFT LOGGING-ONLY
The husk re-wield repaint (`SimpleHuskInventoryExtension._wield_slot` wrap) and the husk mesh-swap (`get_item_units`) both key the cached offhand by `item_data.template`, and the customization-exit emit caches under BOTH the weapon key AND the template key — so static analysis shows the entry should match on the back-switch. No keying gap was identifiable that could be changed safely without risking the working husk path, so it's left tracing. The `[cos:trace] HUSK wield_slot` / `RESOLVE husk-mesh-swap APPLIED` lines will show whether `equips[template]` is present and matched when the host switches secondary and back.

## 0.9.44-dev (2026-06-28) — DIAGNOSTIC: aggressive `[cos:trace]` logging for LA-shield hover/paint/husk bugs (logging-only)

> Supersedes a short-lived 0.9.43-dev that added a dedicated `HeroWindowItemCustomization.on_enter` hook — the mod-lint duplicate-hook gate caught that `_ui_dump.lua` already wraps that (class, method) for this mod (VMF drops the second registration). The SCREEN-enter anchor was moved to the existing `_setup_illusions` trace; no other change.

**Logging-only build. No cosmetic behavior changed.** Adds a distinct `[cos:trace]` log channel (gated on the existing `enable_debug_logging` toggle, same as `_dbg`/`_dbg_alert`) so a single in-game repro yields the full causal chain for the LA-shield bug set (hover-applies-on-Bret-mesh, host/client mesh-vs-texture split, area-load drop, mission weapon-switch-back drop). Grep the session log for `[cos:trace]` to isolate the trace.

### New trace helpers (`cosmetics_tweaker.lua`, near `_dbg_alert`)
- `_trace(fmt, …)` — `[cos:trace]` prefix, file-only, gated on `enable_debug_logging`.
- `_unit_mesh_name(unit)` — reads a spawned unit's authored `unit_name` mesh path (pcall-safe).
- `_trace_paint(site, context, bid, unit, armoury_key, outcome)` — one fully-provenanced PAINT line; for `kind="unit"` variants compares the target unit's actual mesh against the variant's expected `new_units[1]` and emits `match=false` when the imperial texture is painted onto an un-swapped (e.g. bret) mesh.

### Coverage added (all `[cos:trace]`, deduped where sane)
- **SCREEN** — `HeroWindowItemCustomization.on_enter` (new hook_safe) / `on_exit` / `_setup_illusions`: customization view open/close + `_active_customization_backend_id` set/clear + pending-emit drain.
- **INPUT** — offhand-row HOVER (deduped on hover-target change, with full hotspot state) vs PRESS (on_release edge, with hotspot state), row-1 illusion-grid PRESS (`_on_illusion_index_pressed`), and vanilla `_handle_input` row-1 illusion HOVER (new hook_safe; confirms vanilla hover is label-only). This is the crux — it shows whether the bad paint is hover- or press-triggered.
- **WRITE** — every `_offhand_selection[bid][hand]` write (setup auto-select + user press) and the deferred `_pending_la_emit_on_exit` queue write.
- **RESOLVE** — `BackendUtils.get_item_units`: per-hand override decision with `_override_package_ready` result + the `override_unit.."_3p"` suffix-check result + `kind`/`new_units[1]`/`new_units[2]`; the #150 suppress-browse gate; and the husk mesh-swap APPLIED branch.
- **PAINT** — `_apply_la_offhand_to_units` (loot_previewer/ingame/hero_previewer) and the `cos_la_apply` husk offhand apply, each with the mesh-match boolean.
- **HUSK** — husk `_wield_slot` entry + post-vanilla wield-repaint dispatch.
- **SYNC** — `cos_la_apply` emit (host + client→req) and recv.
- **TRANSITION** — `on_game_state_changed` (world/mission load) and LOCAL-player `_wield_slot` from→to (repro #4).

### Noise reduction
- The benign `[offhand] no standalone package … skipping preload` line (hundreds/session) is now deduped to once per unique path per session so the trace stays readable.

### Root-cause candidates surfaced (read-only — NOT fixed in this build)
- **Bug 1/2 (host imperial-texture-on-bret-mesh; client correct):** on the host's own body/previewer the offhand mesh override (`result[hand_field] = opt.intended_unit`) is gated by `_override_package_ready(override_unit)`, which derives the 3p sibling by **suffix** (`override_unit.."_3p"`). For a `kind="unit"` LA shield the real 3p mesh is `new_units[2]`, not `new_units[1].."_3p"` — so readiness returns false, the mesh swap is SKIPPED, but `_apply_la_offhand_to_units` paints the imperial texture anyway → imperial-on-bret. The husk path (`get_item_units`, `_current_husk_wield` branch) instead checks `new_units[2] or la_unit.."_3p"` and swaps correctly → client is right. Candidate fix: make the local override path use the variant's `new_units[1]`/`new_units[2]` for the readiness check (and/or gate the paint on the mesh actually being swapped).

## 0.9.42-dev (2026-06-27) — PROBE: enrich the husk cross-character-weapon PREFLIGHT WARN to resolve the unit vanilla actually spawns (#154)

### Ownership finding (why this is a probe, not a fix)
#154 logs show, across 6 sessions, 16+ cross-character weapons on teammate husks emitting `[husk-wield-wrap] PREFLIGHT WARN … field=right_hand_unit unit=units/weapons/player/<wpn> NOT in resource manager` paired with `[husk-mesh-swap probe] … cache_has_wearer=false cache_has_entry=false`. Investigation determined **cross-character WEAPON meshes are owned by weapon_tweaker, not cosmetics_tweaker**:
- weapon_tweaker exposes cross-char weapons and renders their 3P on husks via the vanilla per-career override fields (`right_hand_unit_override[career]` / `left_hand_unit_override[career]`) resolved inside `BackendUtils.get_item_units` (`backend_utils.lua:159-188`), and **force-loads those override units on every peer at mod init** (`_force_load_brace_repeater_3p_unit` / `_force_load_sp_crossbow_3p_units` / etc.). cosmetics has no role in resolving or making resident a cross-char weapon mesh.
- cosmetics' `_la_equips_by_peer` cache **correctly** has no entry for these weapons — it only tracks LA hat/armor/offhand-shield/illusion cosmetics synced via `cos_la_apply`. `cache_has_entry=false` is expected and correct, not a bug.
- The `[husk-wield-wrap]` wrap exists for LA kind="unit" shield mesh-swaps; its PREFLIGHT WARN was **reading the wrong field**. It checked the BASE `item_data.right_hand_unit` (the donor character's mesh, non-resident on a viewer not playing that character) when vanilla `_wield_slot` actually spawns the per-career OVERRIDE (force-loaded by wt). So the warn is a **false alarm** whenever the resolved override is resident — which explains why it has logged 160×/session for ages and never crashed (CHANGELOG v0.9.36 "Known" note).

Since residency of cross-char weapon meshes can only be safely resolved/owned by weapon_tweaker, cosmetics must NOT blind-fix (force-loading a weapon unit here would step on wt and risk a resource-not-found fatal). This release ships a precise PROBE instead.

### Changed (`cosmetics_tweaker.lua`, husk `_wield_slot` wrap — diagnostics only)
- The PREFLIGHT block now mirrors vanilla `BackendUtils.get_item_units` resolution (per-career `<field>_override[career]` first, then a skin REPLACE + the skin's own per-career override, `rawget` on `WeaponSkins.skins`) to compute the unit vanilla WILL spawn, and checks the residency of THAT resolved unit:
  - **Resolved unit non-resident** → loud `_dbg_alert` `PREFLIGHT WARN … RESOLVED=<unit>(resident=false) … cross-char weapon force-load (weapon_tweaker's) may have missed this for husks`. This is the genuinely actionable signal.
  - **Base non-resident but resolved unit resident** → quiet file-only `_dbg` `PREFLIGHT OK (false alarm) … RESOLVED=<unit>(resident=true)`. Confirms wt/vanilla handled it; kills the misleading 160×/session spam.
  - Each line now also reports `career`, `template` (`item_data.name`), `base` + residency, `RESOLVED` + residency, and `via_skin`, and is **deduped** per `(status, career, template, field, resolved)` so each distinct weapon logs once, not every wield.
- **Behavior unchanged**: still always delegates to vanilla and proceeds (the v0.9.2.1 warn+proceed decision is preserved — no skip-vanilla, per the v0.9.36 history that a skip caused a worse `wielded_slot`-nil crash). No state writes; cannot regress the #149 kind="unit" shield path (husk-mesh-swap in `get_item_units` + the `cos_la_apply` pulse-rewield are untouched).

### Next session
After the user's next MP test (with `enable_debug_logging` ON, which is how the #154 lines were captured), read the new lines: if every cross-char weapon shows `PREFLIGHT OK (false alarm)`, #154 is confirmed cosmetic log-noise only and can be closed (cross-char weapons render correctly — wt's force-load covers husks). If any shows `PREFLIGHT WARN … RESOLVED=…(resident=false)`, that names the exact weapon + career where wt's husk force-load is missing, and the fix belongs in weapon_tweaker.

MOD_VERSION → 0.9.42-dev.

## 0.9.41-dev (2026-06-27) — Two LA-cosmetic behavioral fixes: illusion-browse mutated the live equipped weapon (#150), kind="unit" LA shield dropped at mission start (#149)

### Why
Two user-reported LA (Loremaster's Armoury) cosmetic bugs, neither caught by the existing hooks:

1. **#150 — browsing illusions mutated the LIVE in-keep equipped weapon.** Customizing a shielded weapon, the offhand (shield) picker writes the in-progress pick into the module-global `_offhand_selection[backend_id]` immediately. That table is the SAME truth source the LIVE in-keep / in-mission player body reads when its equipment (re)spawns — via the `BackendUtils.get_item_units` hook (mesh override) and the `_apply_la_offhand_to_units` "ingame" LA texture paint — so the browse pick leaked onto the player's own equipped weapon, not just the customization preview pane. The mod's own code flagged this as a known follow-up ("scoping local writes to the customization screen's own previewer"). The deferred peer-broadcast was ALREADY scoped to screen-exit; only the LOCAL apply was eager — that asymmetry was the root.
   - Investigation note: the MAIN vanilla illusion grid hook tail-calls vanilla and does NOT itself write to the live body (vanilla previews on the `LootItemUnitPreviewer` pane only; hover updates a text label). The confirmed live-body write path is the offhand picker's `_offhand_selection` reaching `get_item_units` + the "ingame" LA paint. Whether the user's "main grid" report also covers the in-menu offhand shield rows / a preview-vs-live conflation needs one in-game confirmation.

2. **#149 — kind="unit" LA shield (Myrmidia Sun = `Kruber_empire_shield_basic2_Kotbs01`) lost its skin at mission start, host/client diverged.** This is an LA **custom-mesh** shield. HOST: the mesh override survived keep→mission (RAM `_offhand_selection`), but the kind="unit" TEXTURE paint in `_la_bridge.lua` early-returned for every context except `"loot_previewer"`, so the in-mission mesh got no Kotbs heraldry → bare imperial mesh. CLIENT: the husk kind="unit" mesh-swap runs only inside `_wield_slot` reading `_la_equips_by_peer`; at mission start the husk's first wield can precede the host's offhand re-broadcast (cache empty → vanilla Bret mesh), so the LA mesh never swapped in, plus the same texture early-return left it unpainted. (Source check: `SimpleHuskInventoryExtension._wield_slot` does NOT short-circuit on same-slot — it destroy+respawns and re-calls `get_item_units` every wield — so the recovery force-rewield was already re-running the swap; the more likely original cause is the cache-timing race + the texture early-return, both addressed below.)

### Fixed
- **`cosmetics_tweaker.lua` (#150)** — added a `_in_create_equipment` flag set only around the vanilla `GearUtils.create_equipment` call (the live in-keep / in-mission body). While the customization screen is open (`_active_customization_backend_id ~= nil`) and the spawn is for that item, both the `BackendUtils.get_item_units` offhand mesh override AND the `_apply_la_offhand_to_units` "ingame" LA texture paint are SUPPRESSED on the live body. The customization PREVIEWER (`LootItemUnitPreviewer`, context `"loot_previewer"`) is NOT inside create_equipment and still shows the browse pick. On screen exit the existing deferred broadcast + pulse-wield (`on_exit`, which clears `_active_customization_backend_id` first) refreshes the live body with the final committed pick. Missions are unaffected (screen closed → flag-gate is a no-op). No crash risk — suppression just keeps the vanilla (already-loaded) hand unit.
- **`_la_bridge.lua` (#149, host + client texture)** — `_paint_offhand_textures_locally` now routes kind="unit" by context: `"loot_previewer"` keeps its `Unit.set_all_materials` + preview-scale; `"ingame"` / `"network_husk"` now PAINT the heraldry (`_LA_KIND_UNIT_TEXTURES[armoury_key]` via `Unit.set_texture_for_materials`) with NO `set_all_materials` and NO scale (those are previewer-only and made the in-game mesh massive in v0.8.47); `"hero_previewer"`/unknown still skip (LA's own hook paints the mannequin). A non-fatal **AV-safety precheck** (`_kind_unit_paint_is_safe`) runs before the in-mission/husk paint: it confirms the unit carries a real (non-null `#ID[00000000]`) material — all `Unit`/`Mesh` introspection pcall-wrapped, never touching the pcall-bypassing `Material.num_parameters` family — and SKIPs (degrade to no heraldry) rather than risk the offset-0x8 access violation that bypasses pcall. Outcomes log via engine `printf` so they show with VMF mod-logging OFF.
- **`cosmetics_tweaker.lua` (#149, client mesh)** — the `cos_la_apply` receiver's kind="unit" force-rewield now PULSES through the other weapon slot then back (mirroring the customization-exit pulse) instead of `inv:wield(inv.wielded_slot)`. This guarantees a clean destroy/respawn wield cycle after the `_la_equips_by_peer` cache is populated (the client mission-start race), so `_wield_slot` → `get_item_units` → husk-mesh-swap re-runs and the LA mesh swaps in. Ends on the original slot so the husk matches the host's wielded weapon; each wield pcall-guarded. (Robustness improvement — the husk `_wield_slot` re-runs the swap even same-slot, so the dominant client fix is the `"network_husk"` texture paint above.)

### Scope note (kind="texture" LA skins)
The mission-start DROP is specific to kind="unit" custom-mesh shields. kind="texture" LA skins paint in ALL contexts already (the early-return was inside `if variant.kind == "unit"`), and the host resolves their (vanilla) mesh + texture in-mission via the surviving `_offhand_selection`, so they do not share this drop. (One pre-existing limitation, unrelated to #149: the client husk-mesh-swap is kind="unit"-only, so a kind="texture" shield whose `new_units` points at a non-default vanilla mesh can show a mesh/texture mismatch on a peer — out of scope here.)

MOD_VERSION → 0.9.41-dev.

## 0.9.40-dev (2026-06-27) — Three crash fixes: Weave-Forge zoom (#148), LA kill-quest host crash (#137), illusion-craft malformed result (#150)

### Why
Three log-confirmed crashes from a single bug-triage build, none of which the existing hooks intercepted:

1. **#148 — Weave Forge preview zoom.** `loot_item_unit_previewer.lua:142: attempt to index field '_unit_start_position_boxed' (a nil value)` in `LootItemUnitPreviewer.update`, reached from the Weave Forge overview. When an item's display/link unit fails to resolve, `_spawn_link_unit` early-returns without setting `_unit_start_position_boxed`, yet `_items_spawned` still latches true via the separate hand-unit package path. A later zoom request (`set_zoom_fraction` → `_zoom_dirty`) then derefs the nil boxed position. Vanilla nil-guards the sibling rotation branch (`if link_unit`) but not the zoom branch.

2. **#137 — LA kill-quest host crash.** LA's `mod:hook(StatisticsUtil, "register_kill", ...)` (LA `utils/hooks.lua`) nil-derefs `attacker_player.player_unit` when the killer has LEFT the game — `player_from_unique_id(attacker_unique_id)` returns nil for a departed peer whose lingering DoT (e.g. a globadier's poison) scores a kill — crashing the HOST (crash GUID 84c586d3). cosmetics_tweaker is mandated to load BEFORE LA, so a normal `mod:hook` from us would be LA's INNER wrapper and never run before LA crashes.

3. **#150 — illusion-craft malformed result.** `_update_craft_response → _craft_completed → _upgrade_item_craft_complete`, crashing at `local backend_id = result[1][1]` (crash GUID 79bb933a; Grail Knight Bret sword&shield, injected illusion at skin index 4). cosmetics_tweaker's `BackendInterfaceCraftingPlayfab.craft` hook mints a synthetic local craft id and its `update` hook_safe sets `self._craft_requests[id] = {}` (an empty stub). Vanilla `get_craft_result(id)` returns that stub verbatim, so `result[1]` is nil; when the window's `_state` dispatches the completion to `_upgrade_item_craft_complete` (which, unlike the result-ignoring `_apply_weapon_skin_craft_complete`, indexes `result[1][1]`) it crashes.

### Fixed
- **`cosmetics_tweaker.lua`** (#148) — added `mod:hook("LootItemUnitPreviewer", "update", ...)` that clears the pending zoom (`self._zoom_dirty = nil`) when `self._unit_start_position_boxed` is absent. There's no link unit to reposition, so preview rotation/visibility is unaffected. Grouped with the existing `LootItemUnitPreviewer` hooks.
- **`_la_prefix_embedded.lua`** (#137) — the prototype-level `wrap()` (which already de-dupes LA's duplicate hook registrations BEFORE LA loads) now takes an `is_normal_hook` flag and, for LA's `register_kill` registration, replaces its handler with a `pcall`-guarded wrapper. On error it still calls `func(...)` so vanilla `register_kill` stat tracking runs. Order-independent: it intercepts at LA's `mod:hook` call, so our load-before-LA position doesn't matter. Gated on the new `la_killquest_crash_guard` setting (only an explicit `false` disables — fail-safe default ON).
- **`cosmetics_tweaker.lua`** (#150) — added `mod:hook("HeroWindowItemCustomization", "_upgrade_item_craft_complete", ...)` that validates `result and result[1] and result[1][1]` before calling vanilla. When malformed (no real backend_id to relink against) it skips vanilla's relink loop and degrades gracefully: re-presents the current item and rebuilds the upgrade-screen widgets/state (`_present_item` + `_set_loadout_item` + `_state_setup_upgrade` + `_setup_availble_states`) so the customization window stays interactive instead of soft-locking. `_apply_weapon_skin_craft_complete` was checked and is NOT vulnerable (never touches `result`).

### Added (VMF toggle + loc)
- **`cosmetics_tweaker_data.lua`** — `la_killquest_crash_guard` checkbox (`default_value = true`), after the `suppress_la_notifications` widget.
- **`cosmetics_tweaker_localization.lua`** — `la_killquest_crash_guard` label + `la_killquest_crash_guard_tooltip`.

MOD_VERSION → 0.9.40-dev.

## 0.9.39-dev (2026-06-21) — Fix: bots cloned the HOST's loadout (LA-gated `is_bot` drop)

### Why
User-confirmed by bisection (all mods on EXCEPT cosmetics → vanilla bot loadouts work). With Loremaster's Armoury installed, cosmetics' `_install_skin_loadout_safety` hook on `get_loadout_item_id` used the signature `function(func, self, career_name, slot_name)` — it **dropped vanilla's 4th `is_bot` argument**. Vanilla `get_loadout_item_id(self, career, slot, is_bot)` (`backend_interface_item_playfab.lua:512/522`) resolves the BOT's designated loadout when `is_bot=true` and the host's otherwise; with `is_bot` dropped, every bot query fell through as `is_bot=nil` and resolved the **host's** loadout, so AI bots cloned the host's gear instead of using their own designated vanilla loadouts. Identical bug class to the `skip_sync`/`is_bot`-drop family (wt fixed the same thing at v0.12.115).

### Fixed
- `cosmetics_tweaker.lua:4498` — `get_loadout_item_id` hook now captures and forwards `is_bot` (`func(self, career_name, slot_name, is_bot)`), and the host-only `mod.loadout_cache` short-circuit is gated on `not is_bot` so a bot never reads the local player's cross-character cosmetic cache. Mirrors wt's v0.12.115 fix. LA-gated path, so this only affected users running Loremaster's Armoury. MOD_VERSION → 0.9.39-dev.

## 0.9.38-dev (2026-06-20) — Auto-open glow picker + hide glow-family skins are now IMPLICIT (toggles removed)

### Why
Glow is now handled entirely through the in-cosmetic-picker glow menu (`_glow_picker.lua`). Two settings that supported that workflow no longer have any reason to be user-toggleable: the auto-open of the picker, and the hiding of the glow-family (weavebound / shyish) skins from the standard illusion list. Both are now hardcoded ALWAYS ON, and their VMF toggles + loc keys were removed. The glow-family skins are reachable only via the glow menu, so they should never appear in the normal grid.

### Removed (VMF toggles + loc)
- **`cosmetics_tweaker_data.lua`** — deleted the `glow_picker_auto_popup_enabled` checkbox widget and both `hide_weavebound_skins` / `hide_shyish_skins` checkbox widgets.
- **`cosmetics_tweaker_localization.lua`** — deleted the matching loc keys + tooltips: `glow_picker_auto_popup_enabled`(+`_tooltip`), `hide_weavebound_skins`(+`_tooltip`), `hide_shyish_skins`(+`_tooltip`).

### Made implicit (always on)
- **Auto-open glow picker on illusion-select** (`cosmetics_tweaker.lua` ~L1574, `HeroWindowItemCustomization._select_illusion` hook): dropped the `mod:get("glow_picker_auto_popup_enabled") ~= false` gate — now fires whenever a glow-family illusion is selected.
- **Auto-open glow picker on wield** (`cosmetics_tweaker.lua` `_glow_auto_popup_for_local` ~L7312): dropped the `mod:get("glow_picker_auto_popup_enabled") == false` early-return. The once-per-keep `_glow_auto_popup_shown[bid]` guard and the in-keep check are unchanged.
- **Hide weavebound + shyish skins** (`cosmetics_tweaker.lua` `_FILTERED_MAT_FAMILIES` / `mod._filter_illusion_widgets` ~L2529): `_FILTERED_MAT_FAMILIES` is now a plain set (`weaves`/`shyish` → always hidden); the helper no longer consults a per-family setting. The currently-equipped-skin always-keep guard is unchanged. The 3rd `get_setting` arg is retained for signature stability but ignored.

### Tests
- Updated the `filter_illusion_widgets_hides_named_mat` regression test's second pass: a getter returning `false` for every key must now still hide weaves+shyish (implicit hiding), so it asserts `removed == 2` instead of `0`.

## 0.9.37-dev (2026-06-20) — Removed the VMF "Weapon Glow Override" menu (glow now driven by the in-picker glow menu)

### Why
Glow is now fully driven by the in-context Glow Picker popup (`_glow_picker.lua`), which customizes glow per item-instance (backend_id-keyed). The old global "Weapon Glow Override" VMF settings menu (master toggle + preset dropdown + the advanced per-channel color/brightness group) is superseded and was creating two competing entry points for the same visual. Removed the menu; kept the entire picker path intact.

### Removed (VMF menu)
- **`cosmetics_tweaker_data.lua`** — deleted the whole `glow_override_group` widget block (was ~L73–232): `glow_override_enable`, `glow_override_preset`, and the nested `glow_advanced_group` with `glow_mult_master`, `glow_per_channel_color_enable`, `glow_color_lower_gradient` / `_upper_gradient` / `glow_color_dots`, and `glow_mult_rune` / `_glow_high` / `_glow_low` / `_smoke_high` / `_smoke_low` / `_dots`.
- **`cosmetics_tweaker_localization.lua`** — deleted the matching loc keys (labels + tooltips) for all of the above, plus the `glow_preset_default/white/purple/gold/red/green/blue` dropdown option labels. The dropdown labels were only referenced by the removed widgets — the Glow Picker uses the `_COLOR_PRESETS` table directly (keyed `purple_glow`/etc.), not these loc keys, so removing them is safe.

### Kept (Glow Picker path — unchanged)
- `_glow_picker.lua` and its whole per-item pipeline: `mod._per_item_glow_runtime[backend_id]`, `mod._unit_to_backend_id`, `_apply_glow_to_unit` (per-item branch runs BEFORE any global gate and `return`s), `mod._reapply_glow_on_wielded`, the `glow_per_item` JSON persistence setting, `_COLOR_PRESETS`, `_resolve_preset_rgb`, `_GLOW_VAR_BRIGHTNESS`. The picker writes per-instance glow that `_apply_glow_to_unit` reads independent of the removed global toggle, so it is fully unaffected.
- The `cos_glow_apply` coop-broadcast RPC machinery is kept structurally (see below).

### Inerted (global-override apply paths, left guarded — not ripped out)
- `_glow_override_enabled(peer)` reads `mod:get("glow_override_enable")` → now nil → `false`. So the global branch of `_apply_glow_to_unit`, `_apply_glow_override`, and the template-mutation hook's mutation branch all no-op cleanly (no nil-deref — `nil` is falsy). The per-item picker paint is reached before these gates and is unaffected.
- `GearUtils.spawn_inventory_unit` hook's template-injection branch (reads `glow_override_enable`) — now inert (branch never fires); left guarded for a possible future global-glow feature.
- `glow_status` chat command — dropped the dead `glow_override_enable`/`glow_override_preset` echo; now reports apply-hook health + Glow Picker open state (the apply hooks still carry the per-item paint).

### Synced-settings list
- `_GLOW_SETTING_KEYS` emptied to `{}`. It listed the global-override settings broadcast to peers so a wearer's global preset painted on remote husks; those settings no longer exist (`mod:get` → nil). The per-item Glow Picker glow is NOT synced through this channel (local-only — see `GLOW_SYSTEM.md` §7g), so emptying loses nothing the picker relies on. `_collect_local_glow_state` / `cos_glow_apply` broadcast machinery kept intact so a future coop-sync of per-item glow can repopulate the list.

## 0.9.36-dev (2026-06-18) — CRASH FIX: husk hat-attachment j_spine engine-fatal (LA hat in CW keep)

### Fixed (crash)
- **Terminal crash when an LA (Loremaster's Armoury) hat was applied to a husk whose body skeleton wasn't ready yet** (GUID `9533f856`: `UnitApi node failed, node 'j_spine'` → `Assertion failed 'index != SceneGraph::NOT_FOUND' at c_api_unit.cpp:74`, via `rpc_create_attachment`). Vanilla `AttachmentUtils.link` calls `Unit.node(husk_body, link_data.source)` for each hat link; on hot-join / mid-revive the husk body's skeleton (the `j_spine`-family source node) isn't populated yet, and `Unit.node` is an **engine fatal that bypasses pcall** — so the existing `pcall` at the hook couldn't catch it. The v0.9.8.5 character-mismatch gate defends the *target* hat-mesh nodes, not this *body-side* readiness case (same-character `es_gk_hat_04`→`es_gk_hat_03` slipped through and still crashed). **Fix:** before the vanilla call, derive the exact source node names up front from `item_template.attachment_node_linking[slot_name]` (plain Lua data) and verify each on the body with the **non-fatal `Unit.has_node`**; if any is missing, **defer** — call vanilla *unpatched* (so the wearer's real hat shows immediately) and enqueue an LA re-apply via the existing `_la_pending_apply` per-frame queue, so the LA hat lands once the skeleton populates. Crucially this **never drops the hat** (the bug behind the old v0.9.8.3 "no helmet visible" regression). Visual/husk-only — no host desync.

### Known (not changed)
- The 160× `husk-wield-wrap PREFLIGHT WARN … NOT in resource manager` lines are the weapon-side analogue but did **not** crash; a previous skip-vanilla attempt there caused a worse `wielded_slot`-nil crash, so that path stays "warn + proceed". A defer-don't-skip upgrade is possible but lower-confidence (depends on the re-apply path's wield coverage) — deferred.

## 0.9.34-dev (2026-06-11) — Glow release gate, part 1: picker auto-opens on selecting a glow-variant illusion; classifier keys off material_settings_name

### Why
User release gate for this mod: glow menu fully functional + picker auto-popups when selecting a cosmetic/illusion that has a glow variant + glow hidden by default until enabled per-weapon. This lands the selection-triggered popup and the data-driven variant detection it depends on. (Hide-by-default is part 2 — needs one in-game verification session; see Notes.)

### Changed
- **`_glow_picker.lua` — `classify()` rewritten around `WeaponSkins.skins[skin].material_settings_name`** (the same field the engine keys glow on, gear_utils.lua:107/155). Family mapping from the 2026-06-11 decompile sweep of all 9 template families: `weaves`/`versus` → magic (5-channel layout); `blue_glow`/`purple_glow`/`golden_glow`/`deep_crimson`/`life_green`/`lileath`/`white_glow` → rune. Suffix regex kept as fallback (LA custom skins with `skin=""`) and extended with bare `_runed` — the CW deus skins (`dr_deus_01_skin_01_runed` etc., weapon_skins_morris.lua:64) the old digit-suffix-only regex missed.
- **`cosmetics_tweaker.lua` — selection-triggered auto-popup**, merged into the existing consolidated `_on_illusion_index_pressed` hook (no new hook): clicking an illusion whose skin classifies to a glow family opens the picker for that item/family immediately (the host window's `_draw` hook already renders the overlay). Selecting a NON-glow illusion while the picker is up closes it. Honors the existing `glow_picker_auto_popup_enabled` setting; no once-per-keep gate here — explicit selection is explicit intent. The wield-triggered auto-popup (active-glow-only, once per keep visit) is unchanged.

### Tests
- `glow_classify_uses_material_settings` — live-data truth table: blue_glow runed skin → rune, Weavebound magic_01 → magic, bare `_runed` CW deus → rune, base skin → nil; fails loudly on vanilla key drift.

### Notes — glow part 2 (hide-by-default), planned
The per-item zero-paint path (`pi.disabled`) already exists in `_apply_glow_to_unit`; "hidden by default" = defaulting glow-variant items to that path unless the user enables glow. Two open questions need ONE in-game session before wiring: (a) whether zeroing the 5 weave channels fully suppresses the `_magic_01` mesh's baked-in animated swirl, or magic-family hiding needs an illusion-level swap to the base mesh; (b) whether the rune-family zero-paint holds across the husk/late-join re-apply path. Run with debug logging on — `[illusion-probe]` + `/glow_status` capture what's needed.

## 0.9.33-dev (2026-06-08) — LA apply-gate teardown: implement the layered-wrapper guard the F7 comment described

### Why
Post-ship re-review of the v0.9.32 audit fixes (fresh-eyes verification pass, 2026-06-08): the `uninstall_apply_gate()` comment promised to restore the original apply fn "only if the live apply fn is still our gate (don't clobber a different override another mod may have layered on since)" — but the code restored **unconditionally**. A third-party wrapper installed on top of our gate (LA-adjacent mods raw-replace this exact function; that's how our own gate works) would have been silently clobbered on an in-session disable.

### Changed (`_la_bridge.lua`)
- **`install_apply_gate()`** saves the gate closure as `M._gate_fn`, and the gate's blocking branch now also checks `M._gate_installed` — so if uninstall ever *can't* restore (foreign wrapper on top), clearing the flag makes the stranded gate a transparent passthrough instead of a permanent block.
- **`uninstall_apply_gate()`** restores the original only when the live fn is identical to `M._gate_fn` (or `_gate_fn` is unset — pre-0.9.33 state). When a foreign wrapper is detected it leaves the chain intact and logs via **ungated `mod:warning`** (incomplete teardown is a failure the user should see without Debug Logging). `_gate_fn` is cleared on every path.

### Tests
- `la_bridge_uninstall_apply_gate_clears_state` extended: asserts `_gate_fn` is cleared, and adds a layered-wrapper scenario (live fn ≠ saved gate) asserting the foreign wrapper is NOT clobbered while flags still clear.

## 0.9.32-dev (2026-06-07) — Audit fixes: LA apply-gate teardown on disable, glow-picker UILayer guard, unlock-label mojibake

### Why
Three findings from the 2026-06-07 audit:
- **F7 (MEDIUM):** `LA_BRIDGE.install_apply_gate()` raw-replaces
  `LA.apply_new_skin_from_texture` with a blocking closure (saving the original at
  `M._original_apply`) but had no teardown. cosmetics_tweaker is `is_togglable`,
  and `mod.on_disabled` only flushed TPE — so an in-session F4 disable left LA's
  OWN recolor permanently blocked for bridge-managed keys until a game restart.
- **F11 (LOW):** `_glow_picker._make_scenegraph_definition()` dereferenced
  `UILayer.popup` at the top of the returned table. That function is passed as an
  ARGUMENT to `pcall(UISceneGraph.init_scenegraph, _make_scenegraph_definition())`,
  so it is evaluated BEFORE pcall protection engages — a nil/renamed `UILayer`
  global would raise uncaught at build time.
- **F12 (LOW):** 4 `es_hat_0002` unlock labels rendered `BA?genhafen Bonnet`
  mojibake (corrupted `Bögenhafen`). Root cause: `_gen_unlocks.py` read the UTF-8
  `_cos_probe.txt` with the platform-default encoding (cp1252 on Windows), so
  `ö` (0xC3 0xB6) decoded as `Ã¶` and `asciify()` emitted `A?`. Display-only.

### Changed
- `scripts/mods/cosmetics_tweaker/_la_bridge.lua:739-760` — added
  `M.uninstall_apply_gate()`: restores `LA.apply_new_skin_from_texture =
  M._original_apply` (guarded on LA-present + original captured), clears
  `_original_apply` / `_gate_installed` / `_bridge_active`. Injected
  ItemMasterList/NetworkLookup entries are deliberately left in place (can't be
  safely torn down mid-session) — only the apply fn is restored.
- `scripts/mods/cosmetics_tweaker/cosmetics_tweaker.lua:835-844` — `mod.on_disabled`
  now also calls `LA_BRIDGE.uninstall_apply_gate()` after the TPE flush.
- `scripts/mods/cosmetics_tweaker/_glow_picker.lua:44-57` —
  `_make_scenegraph_definition()` now reads the popup layer via
  `rawget(_G, "UILayer")` with a literal `900` fallback instead of a bare
  `UILayer.popup` deref, so a missing global can't raise outside the pcall.
- `_gen_unlocks.py:51` — open `_cos_probe.txt` with `encoding="utf8"` (matching
  the output write) so `ö` transliterates to `o`. Fixed at SOURCE, then
  regenerated `_cosmetic_unlocks.lua`: the 4 `es_hat_0002` labels now read
  `Bogenhafen Bonnet`. (The regen also re-sorted `es_hat_0002` after
  `es_helmet_0003` within the Kruber-career hat lists — labels are sorted
  alphabetically and `Bogenhafen` now sorts after `Blucher's`; keys/defaults
  unchanged.)

### Tests
- `cosmetics_tweaker.lua` `/cos_regression_test`: added
  `la_bridge_uninstall_apply_gate_clears_state` — behavioral test that drives the
  gate state machine (install-flag + sentinel original) through
  `uninstall_apply_gate()` and asserts `_gate_installed`/`_original_apply`/
  `_bridge_active` are cleared and a second call is idempotent; restores live
  state afterward. Would FAIL if the teardown were removed (F7 regression).
- Added `cosmetic_unlock_labels_no_mojibake` — loads the generated unlock table
  and asserts no `en` label contains `BA?genhafen` or any stray `?`; would FAIL
  if a future regen reintroduced the encoding bug (F12 regression).
- F11 is a defensive guard with no keep-observable behavior change in the normal
  (UILayer-present) path; no regression test added (the code path only differs
  when the engine global is missing, which can't be synthesized in-keep).

### To verify
- In-keep: enable cosmetics_tweaker, equip an LA bridge-managed hat/skin so the
  apply gate installs, then F4-disable the mod and re-enable it. LA's own recolor
  for those keys should resume (previously stayed blocked until restart). Run
  `/cos_regression_test` and confirm both new checks PASS.
- Open the per-career cosmetic unlock menu for Kruber and confirm the
  "Bogenhafen Bonnet" label renders with no `?` glyph.
- Open the glow picker on a glow-eligible item and confirm the panel still builds.

## 0.9.31-dev (2026-05-29) — Logging hygiene: hot-path mod:info → two-channel _dbg/_dbg_alert

### Why
The body of `cosmetics_tweaker.lua` was never migrated to the `_dbg` / `_dbg_alert`
two-channel helpers (PROJECT_STANDARDS § 3.6) — it had ~205 ungated `mod:info`
calls vs only 2 helper calls. Many fired on hot paths (every inventory hover,
weapon spawn, husk wield, glow apply, RPC emit/recv), violating § 3.2 (level
discipline) and § 3.3 (no logging on high-frequency events) and spamming the
console log during normal play. weapon_tweaker is the reference model.

### Changed
- Migrated ~120 hot-path diagnostic `mod:info` calls to the two-channel helpers
  per § 3.6 word-list classification: ~100 to `_dbg` (log-only confirmation /
  expected-flow skip / dump) and ~20 to `_dbg_alert` (log + chat for genuine
  failure / mismatch / reject). Both gate on `enable_debug_logging`, so the hot
  paths are silent in normal play.
  - Families converted: `[LA preview]` (per-hover equip_item / _spawn_item),
    `[LA paint]` (the skip chain in `_apply_la_offhand_to_units`), `[GLOW]`
    (per-call apply/inject trace), `[thiccc]` (preview scale dump),
    `[husk-mesh-swap]`, `[husk-wield-wrap]` / `[husk-wield-repaint]`,
    `[husk-hat-create]`, `[cos_la_apply*]` (emit / drain / recv / hat / armor /
    offhand / illusion apply core), `[cos_glow_apply]`, `[la-spawn-monitor]`,
    `[la-state-dump]`, `[net-safe]`, `[loadout]`, `[la-persist]`,
    `[ct offhand]` pulse-wield, `[offhand]` preload + `_setup_illusions`,
    `[hot-join replay]` / `[hot-join glow replay]`, `[illusion-filter]`,
    `[illusion-picker-setup]`, `[apply-trace]`, `[hot-reload-safety]`,
    `[ct la-rebroadcast]`.
- Fixed stale line-number comment near the `cos_la_apply` recv handler: it
  cited the host's `cos_la_apply_req` handler "at line 3958" (the register is
  actually ~5522). Re-worded to reference the handler by name/section per § 7.8
  (don't cite drifting raw line numbers).

### Left as mod:info (deliberate, per § 3.6 conservative bounds)
- Load marker (`[cosmetics:LOAD] ...`), dev-load banner, regression-test
  command registration — operational telemetry that ALWAYS fires.
- One-shot boot / registration summaries: custom-illusion + LA-shield-skin
  registration, dual-wield pool building, `[net-safe] hook registration`,
  `[GLOW]` hook-install lines, `_setup_illusions` lazy-init / force-load
  summaries, `[unload]` lifecycle line.
- Deliberate always-on, low-volume click telemetry kept un-gated as documented
  regression guards: `[offhand-press]` (issue #37) and `[illusion-probe]`
  (Evengleam glow-data gathering) — one line per user click each.
- Chat-command / dump bodies (`/dump_glows`, `/probe_hat`, `/glow_*`, `/la_*`,
  `/cos_*`, etc.) — user-invoked, reply belongs in chat/log.
- Existing `mod:warning` (`[la-spawn-monitor] CROSS-SKELETON MISMATCH`
  regression detector) and the `[LA bridge] dependency missing` boot lines
  (paired with deliberate user-facing `mod:echo`) — left untouched.
- The glow-picker M1 scaffold first-fire traces (`[glow_picker:hook]` /
  `[glow_picker:auto]`) — debug-only entry-point scaffold, first-fire-only.

### Notes
- Conservative migration: ~120 confidently-hot calls converted; ambiguous /
  one-shot / command / scaffold calls left as `mod:info`.
- Build passes (`VMBLauncher build cosmetics_tweaker`). Friends-only dev mod —
  needs a fresh ship signal + in-game smoke test (inventory hover, weapon
  spawn, multiplayer husk wield with debug logging on/off) before any Workshop
  upload.

## 0.9.30-dev (2026-05-28) — Aggressive customizer dump + host/client networking doc

### Why
User asked: "we need to aggressively be dumping more info, so the cosmetic/illusion screen is giving you all the info you need" + "if we know how the game actually works between hosts and clients, that might help too" + "we still need per-weapon-instance glow saved to the weapon and for it to be per-player in a way that others in the lobby can see it."

The v0.9.29 picker filter shipped, but to design the per-instance glow popup (issue #48 second slice) and the cross-peer sync RPC, we need more visibility into:
1. The full `MaterialSettingsTemplates` global (what fields are tunable per glow family)
2. The full `WeaponSkins.skins` entry per illusion (units, display, custom fields)
3. The customizer's state machine surface
4. How vanilla already syncs cosmetics between host + clients, where our LA bridge plugs in, and where the per-instance glow needs the same pattern

### Added
- **One-shot `MaterialSettingsTemplates` global dump** in `_ui_dump.lua`. Fires the first time `HeroWindowItemCustomization` opens per session (when debug logging is on). Walks the entire global table, formats vector3 fields as `v3(x,y,z)`, prints one INFO line per template. Gives us the full tunable surface in one place. Subsequent customizer opens skip the global dump (already captured).
- **Per-skin full enricher dump** for the illusion grid. Beyond the existing `[N] skin_key (mat=... rarity=...)` summary, now emits `[skin-entry][N] skin_key: display=... mat=... rarity=...` + `units: 1p=... 3p=... L=... R=... flat=...` + `extras: <every scalar field>`. Capped at 16 entries per open (matches existing truncation pattern).
- **Customizing context dump** — beyond `key/bid/skin/rarity/power/slot_type`, now also dumps `item.data.skin_combination_table` + `default_skin` so a future maintainer can trace the grid contents back to the source `WeaponSkins.skin_combinations[name]` table.
- **State-machine snapshot** — emits `state: current=<...> selected_idx=<...> current_recipe=<...>` so the active state is captured alongside per-open context.
- **`material_settings_templates_loaded` regression test** — asserts the global is loaded, every weapon-mat family the customizer expects is present (`blue_glow / purple_glow / golden_glow / deep_crimson / life_green / lileath / weaves / versus / white_glow`), and `weaves` carries the expected 5 vector3 fields the per-instance glow popup design depends on (`color_glow_high / color_glow_low / color_smoke_high / color_smoke_low / color_dots`). Catches any future vanilla rename of a family or shape change before subscribers hit it.

### Documented
- **`cosmetics_tweaker/NETWORKING_MODEL.md`** — new doc explaining how VT2's vanilla cosmetic sync works (host's ProfileSynchronizer broadcasts the inventory identity via SharedState; every peer materializes glows locally from their own `WeaponSkins.skins` + `MaterialSettingsTemplates` tables — no glow data ever crosses the wire), where our LA bridge plugs in (the `cos_la_apply` RPC carries (peer, slot, kind, armoury_key) so every peer can apply the LA mesh locally), and what the per-instance glow needs to add (planned `cos_glow_apply` RPC with `(peer, backend_id, glow_blob)` payload; synthetic `MaterialSettingsTemplates._ct_glow_<bid>` registration on recv; CIM `_forged_weapons[bid].custom_glow` persistence — substrate already exists; host hot-join replay on peer-join). Includes bot model (bots are host-owned; cache is per-peer-id; the v0.9.11 char-mismatch guard + v0.9.28 self-heal handle the cross-skeleton case) and a state-cache inventory table (`_la_equips_by_peer` / `la_persisted_equips` / `CIM custom_glow` / live engine material state).
- **Finding: there is no `shyish` mat family on vanilla weapon skins.** Exhaustive grep across `scripts/settings/equipment/weapon_skins_*.lua` + DLC weapon-skin files shows 9 unique mat families: `blue_glow / purple_glow / golden_glow / deep_crimson / life_green / lileath / versus / weaves / white_glow`. The "Shyish-Infused" Necromancer skins (`shovel` DLC) all use `material_settings_name = "weaves"`. The v0.9.29 `hide_shyish_skins` toggle is therefore inert on stock content; left in place defensively for future content or modded skins. Documented in NETWORKING_MODEL.md so the next maintainer doesn't redo the grep.

### Changed
- `_ui_dump.lua` — added `_fmt_v3` helper for vector3 formatting + `_dump_material_templates_once` (fire-once gated on `_mat_templates_dumped` file-local flag) + `_dump_skin_entry_full` (per-illusion detail dump).

### Verification
1. Boot, run `/cos_regression_test` — `material_settings_templates_loaded` + the existing `filter_illusion_widgets_hides_named_mat` + `la_cache_self_heal_purge_helper` all PASS.
2. Enable debug logging, open the illusion customizer on ANY weapon. First open emits the `[mat-templates] === MaterialSettingsTemplates inventory ===` block (one line per template). Subsequent opens skip it.
3. Every customizer open emits per-skin `[skin-entry][N]` lines for up to 16 illusions in the grid, capturing display name + units + extras.
4. Open NETWORKING_MODEL.md side-by-side with the planned per-instance-glow PR — section 5 is the recipe for adding the `cos_glow_apply` RPC.

## 0.9.29-dev (2026-05-27) — Hide weavebound + shyish illusions by default (issue #48 first slice)

### Why
The 2026-05-27 ui-dump on Kruber's Greatsword (`es_2h_sword`) confirmed every illusion in the picker carries a `material_settings_name` field that buckets it into a glow family:

| `mat=` | Family |
|---|---|
| nil | no glow |
| blue_glow / purple_glow / golden_glow | standard runed glows |
| lileath | DLC-specific glow |
| versus | Versus mode skin |
| **weaves** | Weavebound (loud animated arcane particles) |
| **shyish** | Shyish-Infused (Necromancer DLC; same loud-particle style) |

Per issue #48: weaves + shyish are visually jarring on most weapons. The Bret Longsword "Evengleam" pairing is the canonical complaint. Hide them in the picker by default — opt-in via VMF if a user actually wants one.

### Added
- **VMF toggles** (default ON): `hide_weavebound_skins`, `hide_shyish_skins`. Localized labels + tooltips wired in `cosmetics_tweaker_data.lua` + `_localization.lua`.
- **`mod._filter_illusion_widgets(widgets, current_skin_key, get_setting)`** pure helper in `cosmetics_tweaker.lua`. Walks the widget array, drops entries whose `WeaponSkins.skins[skin_key].material_settings_name` matches a filtered family per the per-family setting. Recomputes x-offsets using vanilla's `width=51 spacing=-5` math (mirrors `hero_window_item_customization.lua:1611-1618`).
- **Selection-state guard:** the currently-equipped skin (`item.skin or item.data.default_skin`) is NEVER filtered, even if its family is otherwise hidden. Without this, vanilla's `_select_illusion_by_key` (called inside `_setup_illusions` before our hook runs) would dangle on a now-missing widget.
- **`filter_illusion_widgets_hides_named_mat` regression test.** Synthesizes `WeaponSkins.skins` entries scoped to test-only keys, drives the helper with a setting-getter override, asserts: weaves + shyish unequipped widgets are dropped; nil-mat + blue_glow widgets remain; the currently-equipped skin is always kept; filters-off removes nothing. Restores `WeaponSkins.skins` cleanly.

### Changed
- `HeroWindowItemCustomization._setup_illusions` hook: after the vanilla call returns and the v0.9.18 debug-probe runs, the new filter step prunes `self._illusion_widgets` and (if `enable_debug_logging` is on) logs a `[illusion-filter] dropped N hidden-family skin(s); M remain` line.

### Why not gate per-weapon
The issue spec named the Bret Longsword, but the rationale (weavebound is loud on most weapons) applies universally. A whitelist of weapon keys would be one more thing to maintain — and the selection-state guard already covers the only failure mode (a user who likes a specific weavebound skin can equip it once; from then on the equipped one shows even with the filter on).

### Verification
1. Boot VT2, `/cos_regression_test` — `filter_illusion_widgets_hides_named_mat` PASSES.
2. Open the illusion picker on Kruber's Greatsword. Default state: skins 7 (versus), 8 (lileath), 9-12 (blue/purple/golden runed) visible; skin 13 (weaves) hidden. Toggle "Hide Weavebound" off → skin 13 reappears.
3. Equip the weavebound skin, re-open picker — weavebound entry visible (selection-state guard). Switch to a non-weavebound skin and re-open — weavebound entry disappears again.
4. Open on Bret Longsword (Evengleam) once the user gets to it — weavebound + shyish entries should be hidden; standard glows + base skins remain.

## 0.9.28-dev (2026-05-26) — Self-heal `_la_equips_by_peer` on cross-skeleton mismatch

### Why
Host log from 2026-05-26 multiplayer session showed three `[la-spawn-monitor] CROSS-SKELETON MISMATCH` warnings: client peer `11000013cb862af` had a cached Kerillian Maiden Guard hat (`Kerillian_elf_hat_Windrunner_Avelorn` / `units/beings/player/way_watcher_maiden_guard/headpiece/ww_mg_hat_12`) that the host's spawn-monitor tried to apply to the same peer's later Saltzpyre WHC and Sienna Necromancer spawns. The v0.9.11 character-mismatch guard caught the visible apply, but `_la_equips_by_peer` is keyed `[peer_id][slot]` only — when a peer switches career on the same peer_id and the new career has no LA hat (no cos_la_apply emit), the previous career's entry persists until the peer disconnects. The warning fired on every subsequent spawn of the polluted peer.

### Changed
- `cosmetics_tweaker.lua` — added `_purge_stale_peer_slot(cache, wearer_peer, slot_name)` pure helper. Wired into the spawn-monitor at the existing CROSS-SKELETON MISMATCH detection site (line ~5108): on mismatch, log the warning AND purge `_la_equips_by_peer[wearer_peer].slot_hat` so the cache self-heals on the first post-switch spawn. Empty peer tables are also cleaned up.
- Exposed as `mod._purge_stale_peer_slot` for the regression test.
- `la_cache_self_heal_purge_helper` regression test asserts the helper exists, clears only the named slot, removes empty peer tables, returns false on idempotent / nil-tolerant inputs, and matches the exact contract the spawn-monitor depends on.

### Why this fix instead of re-keying by (peer, career)
Re-keying `_la_equips_by_peer` as `[peer][career][slot]` would touch ~15 read/write sites and require the cos_la_apply RPC payload to carry career. Self-healing on the existing mismatch detector is one line at the call site, one helper, one test — and any future case where stale data slips through (e.g. cross-character body skin) gets caught by the same v0.9.11 guard pipeline. The cache schema stays simple.

### Verification
1. Boot VT2, run `/cos_regression_test` — `la_cache_self_heal_purge_helper` PASSES (alongside the existing `la_chars_compatible_*` tests).
2. Multiplayer session: client subscribes with one LA hat applied as Kerillian; switches to Saltzpyre WHC or Sienna Necromancer. Host log: ONE `CROSS-SKELETON MISMATCH` warning on the first WHC/Necro spawn, then silent (cache cleared). Pre-fix behavior was one warning per spawn for the rest of the session.

## 0.9.27-dev (2026-05-26) — Per-(class, method) existence guard + extended regression test

### Why
v0.9.26 hooked `_clear_item_slot` uniformly on all four loadout-style window classes, but `HeroWindowCosmeticsLoadout` doesn't define that method — vanilla never unequips from the cosmetics loadout (it always swaps in place). VMF raised `(hook_safe): trying to hook function or method that doesn't exist: [HeroWindowCosmeticsLoadout._clear_item_slot]` at every boot. v0.9.25's existence guard only checked CLASSES, not per-method.

### Changed
- `_ui_dump.lua` — refactored `LOADOUT_WINDOWS_WITH_EQUIP` into a structured `M._loadout_hook_pairs` list of `(class_name, method, behavior)` triples. Each pair now goes through `type(_G[class][method]) == "function"` before `mod:hook_safe`. Missing pairs are added to `M._unknown_method_pairs` and logged once with a `[ui-dump] WARN` line — same shape as the v0.9.25 class-level guard. Inline comment documents that the cosmetics-loadout class intentionally lacks `_clear_item_slot`.
- Extracted the equip / unequip handlers into `_make_equip_handler(class_name)` / `_make_unequip_handler(class_name)` closures so the per-class `class_name` binding stays clean.
- `ui_dump_hook_targets_exist` regression test (`cosmetics_tweaker.lua`) now fails on non-empty `UI_DUMP._unknown_method_pairs`, with the failure message naming the exact missing `<class>.<method>` pair(s). Pair-with-message catches both today's bug shape AND any future vanilla rename of an equip/unequip write-site method.

### Verification
1. Boot VT2 — no `[MOD][cosmetics_tweaker][ERROR]` lines.
2. `/cos_regression_test` — `ui_dump_hook_targets_exist` PASSES.
3. With `enable_debug_logging` on, swap loadout slots: `[ui-dump:HeroWindowLoadoutConsole] EQUIP slot_idx=...` lines fire. Cosmetics-loadout swaps emit EQUIP lines but no UNEQUIP (expected — that's how vanilla works).

## 0.9.26-dev (2026-05-26) — UI dump: capture loadout slots at the write site (vanilla populates async)

### Why
v0.9.24's loadout dumps were silently empty. Vanilla initializes `self._equipment_items = {}` in `on_enter` and populates it lazily via `_equip_item_presentation` (called from `_update_loadout_sync` every `update` tick once the loadout sync arrives). v0.9.24's `_dump_slots(self._equipment_items)` enricher ran one tick too early — always saw an empty table — produced zero output. User correctly flagged the data should not be empty since the loadout is always populated.

### Changed
- `_ui_dump.lua` — hook `_equip_item_presentation` and `_clear_item_slot` directly on each of the four loadout-style window classes (`HeroWindowLoadout`, `HeroWindowLoadoutConsole`, `HeroWindowCosmeticsLoadout`, `HeroWindowCosmeticsLoadoutConsole` — verified against vanilla source 2026-05-26). Each `hook_safe` fires once per slot per equip / unequip event. Output: `[ui-dump:<Class>] EQUIP slot_idx=N ui_slot_idx=K slot_type=... key=... bid=... skin=... rarity=...` and the symmetric UNEQUIP line. Self-debouncing — vanilla only calls the write site when the slot data actually changes.
- Dropped the always-empty `_dump_slots(self._equipment_items, ...)` lines from the `HeroWindowLoadout` + `HeroWindowCosmeticsLoadout` enrichers. Replaced with inline pointer comments to the write-site hook so a future reader doesn't re-add the broken pattern.
- Added inline doc note on CIM × UI_DUMP coexistence on `HeroWindowItemCustomization.on_enter` — both register but on different VMF rungs (wrap + hook_safe) so they coexist without conflict. Comment explicitly says "do NOT consolidate" to prevent a future maintainer from collapsing them into the hook_safe-shadow trap.

### Verification
1. Toggle `enable_debug_logging` on, open the keep, switch loadout slots / equip a different weapon. Each click produces a `[ui-dump:HeroWindowLoadoutConsole] EQUIP slot_idx=...` line with backend_id + skin populated.
2. `/cos_regression_test` still passes the `ui_dump_hook_targets_exist` check (the new `_equip_item_presentation` registrations are guarded the same way).

## 0.9.25-dev (2026-05-25) — Hotfix two boot-time hook errors in v0.9.24's UI dump harness

### Why
The v0.9.24 ship logged two `[MOD][cosmetics_tweaker][ERROR]` lines at every boot:
1. `(hook_safe): trying to hook function or method that doesn't exist: [HeroView._change_window]` — I'd guessed at the vanilla method name; the real one is `HeroView._change_screen_by_name` (hero_view.lua:477). VMF skipped the registration cleanly so no functionality regressed, but the ERROR line was noise in every subscriber's log.
2. `(hook): trying to hook object that doesn't exist: HeroWindowEquipmentChoices` — I'd invented this class name. No file `hero_window_equipment_choices.lua` exists; equipment-choice UI lives inside `HeroWindowLoadoutInventory` and friends, which are already monitored.

### Changed
- `_ui_dump.lua` — replaced the `_change_window` hook with `_change_screen_by_name`. Removed `HeroWindowEquipmentChoices` from `WINDOWS_TO_MONITOR`. Both edits are inert at runtime when `enable_debug_logging` is off; the dump harness still covers every cosmetic / inventory / crafting window class that actually exists.
- Verified the remaining 16 class names in `WINDOWS_TO_MONITOR` all map to real `scripts/ui/views/hero_view/windows/hero_window_*.lua` files.

### Verification
1. Boot VT2 with cosmetics_tweaker enabled. Search the console log for `[MOD][cosmetics_tweaker][ERROR]` — must be absent.
2. With `enable_debug_logging` on, navigate keep menus. `[ui-dump:HeroView] _change_screen_by_name -> ...` lines fire on each top-level screen switch.

## 0.9.24-dev (2026-05-25) — UI diagnostic dump harness for every cosmetic / inventory / crafting window

### Why
The Evengleam glow popup (issue #48) and other "parts that aren't working" need accurate knowledge of vanilla's UI surface — which window classes are entered when, what widgets each one builds, what item context each carries, which slots are populated. Source-tree reading gives the static shape but not the runtime context (live `_item_backend_id`, current `_active_category`, populated `_equipment_items`). Manual /probe commands are friction. This patch installs a passive harness that dumps everything once per window-enter, gated on the existing `enable_debug_logging` toggle so it's silent in normal play.

### Added
- **`_la_persistence.lua`'s sibling: `_ui_dump.lua`** — single new module that string-form-hooks `on_enter` on every relevant `HeroWindow*` class (item customization, cosmetics loadout + inventory, weapon loadout + inventory, crafting + console variants). Wrap-style `mod:hook` (chains correctly across mods; `hook_safe` would shadow existing CT registrations on these classes — see VMF_RECIPES.md § 1).
- Per-window enrichers in `_ENRICHERS` table — each class gets a tailored dump beyond the generic widget list. HeroWindowItemCustomization dumps the customized item + the full illusion grid with each skin's `material_settings_name` + rarity (directly captures the data needed for the Evengleam glow popup). HeroWindowCosmeticsLoadout dumps every equipped cosmetic slot. HeroWindowLoadout dumps the weapon loadout. HeroWindowCrafting dumps the recipe list + active recipe + has_all_requirements.
- HeroView `_change_window` `hook_safe` — surfaces every sub-window transition so the log shows the navigation sequence, not just per-window snapshots in isolation.
- Output format: `[ui-dump:<ClassName>] key=value ...`. Greppable in console_logs.
- All dumps gated on `enable_debug_logging`. Single bool check per `on_enter` when the toggle is off — zero performance impact in normal play.

### How to use
1. Toggle `enable_debug_logging` ON in VMF settings before testing.
2. Open the keep. Navigate through cosmetics, inventory, weapon customization, illusion picker, etc.
3. Send the resulting `console-YYYY-MM-DD-*.log`. The `[ui-dump:*]` lines describe the UI surface in enough detail to wire the next feature without source-tree guesswork.

## 0.9.23-dev (2026-05-25) — Restore dev/alpha/beta load banner (PROJECT_STANDARDS § 3.6 update)

### Why
User feedback 2026-05-25 EOD: earlier today's chat-spam cleanup pulled the `mod:echo("Cosmetics Tweaker v" .. MOD_VERSION)` startup line from every mod. That's correct for stable (>=1.0.0) builds but hides the active version for in-flight dev/alpha/beta work. PROJECT_STANDARDS § 3.6 amended: dev/alpha/beta/0.x versions MUST echo `[<mod_id>] v<version> loaded` at module load; stable versions stay silent.

### Changed
- `cosmetics_tweaker.lua` — added a track-detector `if` after the applied-marker line: matches `-dev$` / `-alpha$` / `-beta$` / `-rc%d*$` / `^0%.`. When any branch fires, `mod:echo("[cosmetics] v<MOD_VERSION> loaded")` runs once.

## 0.9.22-dev (2026-05-25) — Absorbs la_prefix_patch (standalone mod retired)

### Why
la_prefix_patch's three deliverables — LA's three duplicate hook deduplication, LA quest marker suppression toggle, LA unread-letter notification suppression toggle — were already mirrored in cosmetics_tweaker's LA bridge (`_la_prefix_embedded.lua`) and have been live for users who had cosmetics_tweaker without the standalone subscribed. la_prefix_patch was redundant. Archived to `_archive/la_prefix_patch_v0.3.6-dev/` per the repo "archive don't delete" rule.

### What this means for users
- la_prefix_patch Workshop subscription: safe to unsubscribe (Workshop item 3721067411 stays published as a stub for now).
- All three features remain available via cosmetics_tweaker's existing settings.

### Notes
- No code change in this version — embedded copy already provided full functionality.
- Standalone-running guard in `_la_prefix_embedded.lua` retained so peers who still have la_prefix_patch subscribed + enabled get a clean no-double-wrap.

### Build
VMBLauncher.exe build cosmetics_tweaker -- verification only. NOT deployed, NOT uploaded.

## 0.9.21-dev (2026-05-25) -- Remove startup banner echo + tidy on_setting_changed (chat-echo policy: PROJECT_STANDARDS § 3.6)

### Why
User feedback 2026-05-25: `"on enabling debug logging, I'm getting needless echos to the chat that it's enabled"` and `"on startup before enabling debug logging, I'm getting things echo'd to the chat for CWV"`. Audit found 13 mods with redundant `mod:echo("<Name> v" .. MOD_VERSION)` lines at module load and one mod with `mod:echo("Setting changed: " .. setting_id)` in on_setting_changed (career_tweaker -- the source of the Debug Logging chat echo).

Policy decision codified in PROJECT_STANDARDS.md § 3.6 "Chat-echo policy":
- **NEVER** at module load -- the applied marker `[cosmetics] enabled v<X> settings_fp=<hash>` line is the canonical version surface, lives in the log, never spams chat.
- **NEVER** in on_setting_changed for routine settings -- use `_dbg` (gated on enable_debug_logging) if a diagnostic trace is needed.
- **OK** in on_setting_changed only for explicit high-impact toggles (bt master toggle, gt AI toggle).
- **OK** in user-typed chat command bodies (`/<feature>_regression_test`, `/verify_*`, etc.).

### Changed
- cosmetics_tweaker.lua -- removed the load-time `mod:echo("cosmetics_tweaker v" .. MOD_VERSION)` banner. The applied marker line (`mod:info("[cosmetics] enabled v%s settings_fp=%s", ...)`) further down already surfaces the version + settings hash in the log. `mod:info("cosmetics_tweaker v%s loaded", MOD_VERSION)` retained for log-side visibility.
- itemV2.cfg -- updated the description's "Mention the mod version" bug-report instruction. Previous text told users to find the version "at the top of the in-game chat when you load into the keep" -- now points them at the console log (search for the `enabled v` line) or `/<mod>_regression_test`.

### Build
VMBLauncher.exe build cosmetics_tweaker -- verification only. NOT deployed, NOT uploaded.

## 0.9.20-dev (2026-05-25) -- Fix unescaped %APPDATA% in Debug Logging tooltip + add localization_format_safe runtime test

### Why
User report: "invalid string format on mouseover for Debug Logging" -- the canonical Universal Debug Logging tooltip (PROJECT_STANDARDS.md S 3.6) shipped with a literal %APPDATA%. Lua's string.format reads %A as a format directive and raises invalid option '%A' to 'format', surfacing as a red error tooltip in the VMF settings UI. All 16 active mods were affected (every mod ships the same canonical tooltip text).

### Changed
- cosmetics_tweaker_localization.lua -- escaped literal % in enable_debug_logging_tooltip so VMF's tooltip render path sees %%APPDATA%% (renders as %APPDATA% to the player). Same wording, just escaped.
- cosmetics_tweaker.lua -- added _rt_register("localization_format_safe", ...) runtime check. dofiles the loc table and pcall(string.format, value) on every entry; surfaces any unescaped % via /<mod_id>_regression_test. Catches the bug class even when the static check (qa/check_localization.ps1) is skipped.

### Notes
Repo-wide multi-layer defense landing across all 16 mods in this sweep:

1. Layer 1 -- 16 mods' loc strings fixed.
2. Layer 2 -- qa/check_localization.ps1 extended to parse loc.<key> = { en = "..." } assignment style (chaos_wastes_tweaker's pattern -- previously slipped detection).
3. Layer 3 -- _rt_register("localization_format_safe", ...) runtime check in every mod.
4. Layer 4 -- tools/vmb-launcher/CLAUDE.md doctrine update: "Run qa/check_localization.ps1 before declaring any localization edit complete."
5. Layer 5 -- documentation: LOCALIZATION_STANDARD.md S 1 "Recurring offender" worked example, docs/BUG_CLASSES.md S 16 new entry, PROJECT_STANDARDS.md S 3.6 canonical tooltip text now uses %%APPDATA%%.

Static check (qa/check_localization.ps1) reports 0 errors post-fix (down from 15 detected + 1 hidden in chaos_wastes_tweaker).

### Build
VMBLauncher.exe build cosmetics_tweaker -- verification only. NOT deployed, NOT uploaded.

## 0.9.19-dev (2026-05-25) — Fix #37 (LA shield auto-apply on browse) + data probes for Evengleam glow feature

### Why
Issue #37: opening the offhand shield picker auto-applied the first LA option (yellow Reynard01) without the user clicking Apply. Root cause: the picker's draw hook dispatched on `hotspot.on_pressed`, but `on_pressed` is sticky in this engine build — it stayed true across multiple draw frames after the picker opened, causing the first widget to fire `_ct_on_offhand_pressed` every frame. Vanilla's own button-press detector (`hero_window_item_customization.lua:611-616`) uses `hotspot.on_release` and clears it manually after consumption; CT now mirrors that pattern.

### Changed
- `cosmetics_tweaker.lua:2643-2660` — switched offhand picker dispatch from `hotspot.on_pressed` to `hotspot.on_release`, and added `hotspot.on_release = false` after consumption so any sticky engine state can't leak across frames. Same pattern vanilla uses for every button in `HeroWindowItemCustomization`.
- `cosmetics_tweaker.lua:~2655` — always-on `[offhand-press]` log line on every legitimate dispatch: hand_field, index, widget name, backend_id. Low volume (one line per click); makes any future regression of #37-style leaks visible in console.

### Added — data probes for the planned Evengleam glow popup feature
Per request to capture data automatically during testing rather than running manual probes between sessions:
- `cosmetics_tweaker.lua:~1503` — always-on `[illusion-probe]` line on every illusion click. Dumps `picked_skin → matching_item_key + material_settings_name + rarity`. Captures which skins belong to which glow family (rune / weaves / magic) directly from `WeaponSkins.skins[...]`.
- `cosmetics_tweaker.lua:~2456` — `[illusion-picker-setup]` dump (gated on `enable_debug_logging`) on every picker open. Lists every illusion built into the picker for the current weapon with its `matching_item_key`, `material_settings_name`, and `rarity`. Enabling debug logging while browsing the Bretonian Longsword will surface the full magic-family skin set (weavebound `_magic_01`, shyish-infused `_magic_02`) we'll need to wire the glow popup against.

### Closes
- #37 (LA shield picker auto-applies first option on browse) — fixed in this version.

## 0.9.17-dev (2026-05-25) — Applied marker (universal — PROJECT_STANDARDS.md § 3.6)

### Why
Every mod now prints a single `mod:info("[cosmetics] enabled v<X.Y.Z> settings_fp=<8-hex>")` line at load. Walks the data widget tree, FNV-1a-32 hashes setting=value pairs. Self-documenting console_logs. ALWAYS fires (not gated on debug_logging).

### Changed
- `cosmetics_tweaker.lua` — added file-local `_settings_fingerprint()` helper + `mod:info("[cosmetics] enabled ...")` applied-marker line right after the `_dbg_alert` helper.
- `itemV2.cfg` — bumped to v0.9.17-dev.

## 0.9.16-dev (2026-05-25) — Fix dead `SimpleHuskInventoryExtension.extensions_ready` hook (issue #35)

### Why
`[MOD][cosmetics_tweaker][ERROR] (hook_safe): trying to hook function or method that doesn't exist: [SimpleHuskInventoryExtension.extensions_ready]` fired every session. The hook (line 5007) attempted to mirror the owned-player `SimpleInventoryExtension.extensions_ready` hook from `_la_persistence.lua` so the LA spawn monitor (`mod._la_spawn_monitor`) would also fire for remote-player husks — but `SimpleHuskInventoryExtension` has NO `extensions_ready` method. Confirmed against `Vermintide-2-Source-Code/scripts/unit_extensions/default_player_unit/inventory/simple_husk_inventory_extension.lua`: the husk class is a separate root class with no inheritance from `SimpleInventoryExtension` (per CLAUDE.md "Self-owned vs husk extension classes"), and its lifecycle entry point is `init` (line 5, signature `function (self, extension_init_context, unit, extension_init_data)`).

### Changed
- `cosmetics_tweaker.lua` line 5007-5012 — rewired the dead hook from `extensions_ready` to `init`, with the correct 4-arg husk-init signature. The body still calls `mod._la_spawn_monitor(unit)` so the cross-skeleton LA mismatch detector (issue #14 regression safety net) now actually runs on remote-player husks.
- `cosmetics_tweaker.lua` — `MOD_VERSION` bumped 0.9.15-dev → 0.9.16-dev.
- `itemV2.cfg` — title + description banner bumped to v0.9.16-dev.

### Notes
- The v0.9.13 CHANGELOG entry claimed the husk-side mismatch detector was already running; it was not — the hook silently no-op'd at VMF registration time. The mismatch detector was effectively half-blind (host + owned bots only, not remote husks) from v0.9.13 through v0.9.15. v0.9.16 closes that gap.
- Surface area for the next regression: there is no static check that catches a typo'd or stale hook target. Issue #35 / #41 both suggest a `qa/mod-lint` scan that grep-asserts every `mod:hook_safe("<global>"...)` resolves against a decompiled-source class file, and that every `(Class, method)` pair exists. Out of scope for this patch.

### Closes
- #35 (cosmetics_tweaker `hook_safe(SimpleHuskInventoryExtension, "extensions_ready")` — function does not exist; silent dead hook).

## 0.9.15-dev (2026-05-25) — Two-helper debug-logging policy (PROJECT_STANDARDS.md § 3.6)

### Why
User-requested two-channel debug discipline: `_dbg` for confirmation / dump / expected behavior (log file only), `_dbg_alert` for unexpected / wrong / mismatch (log file + in-game chat). Helpers installed in every active mod.

### Changed
- `cosmetics_tweaker.lua` — installed `_dbg_alert` helper alongside existing `_dbg`. Added `_rt_register("dbg_helpers_two_channel", ...)` alongside the existing 12 cos regression checks.
- `itemV2.cfg` — bumped to v0.9.15-dev.

### Notes
- 0 existing `_dbg(...)` call sites in the main `cosmetics_tweaker.lua` (helper was previously unused at the top level).
- 0 bare `mod:echo` reclassified — `mod:echo` calls in `cosmetics_tweaker.lua` are inside `/cos_*` chat command bodies (user-operational) or are permanent operational output.
- Subfiles (`_la_bridge.lua`, `_glow_picker.lua`, `_moreitemslibrary_embedded.lua`, `_material_hijack_embedded.lua`) don't import the helpers; their `mod:echo` calls are all chat-command-scoped or permanent operational warnings (e.g. "[Material-Hijack] not active" load banners).

## 0.9.14-dev (2026-05-25) — Standardize Debug Logging toggle (universal convention)

### Why
Repo-wide convention: every mod now exposes a single `enable_debug_logging` checkbox at the bottom of its VMF widget tree (PROJECT_STANDARDS.md § 3.6). cosmetics_tweaker previously had `debug_dumps` as a top-level checkbox placed mid-tree (above `appearance_group`) — renamed and moved to the bottom.

### Changed
- `cosmetics_tweaker_data.lua` — removed the mid-tree `debug_dumps` widget; appended `enable_debug_logging` after the `cosmetic_availability_group` so it lands at the bottom of `widgets`, top-level (NOT inside any group).
- `cosmetics_tweaker_localization.lua` — replaced `debug_dumps` / `debug_dumps_tooltip` strings with `enable_debug_logging` + `enable_debug_logging_tooltip` per the standard.
- `cosmetics_tweaker.lua`:
  - `_debug_dumps_enabled()` now reads `mod:get("enable_debug_logging")` (was `debug_dumps`). All existing call sites untouched (they go through the helper).
  - Added file-local `_dbg(fmt, ...)` helper at top of file for new call sites. Output prefix `[cosmetics:dbg]`.
- `itemV2.cfg` — title + description bumped to v0.9.14-dev.

### Notes
- **Migration**: the saved value of `debug_dumps` is not auto-carried into `enable_debug_logging`. Users who had the old toggle on must re-tick the new `Debug Logging` checkbox after first load. VMF defaults the new key to `false`.

## 0.9.13-dev (2026-05-25) — Regression test + auto-monitor for cross-skeleton LA leak (issue #14)

### Why
The v0.9.11 fix for the GK→WP hat leak shipped without a real test. The pre-existing `character_mismatch_gate_in_apply_la` regression check only asserted that the substring `"character mismatch"` appeared somewhere — it would have passed even with the broken v0.9.8.8 guard (which logged the same string while doing the wrong thing). Without a behavioral test, a future refactor could silently regress the fix.

### Changed
- **Extracted pure helper** `mod._la_chars_compatible(owner_char_path, la_unit_path, profile_base)` from the v0.9.11 inline guard (`cosmetics_tweaker.lua` ~L4836). Returns `(true)` or `(false, reason)`. Unit-testable in isolation.
- **`_apply_la_on_unit` hat branch now delegates to the helper** rather than inlining the comparison.
- **Replaced the marker-only test** with five real `_rt_register` cases:
  - `la_chars_compatible_same_char_allowed` — Kruber GK hat on Kruber GK body passes.
  - `la_chars_compatible_different_char_denied` — exact issue #14 scenario: Kruber GK hat on Saltzpyre WP body → deny.
  - `la_chars_compatible_profile_fallback_match` — early-spawn race with no slot_hat yet; profile base prefix accepts matching character.
  - `la_chars_compatible_profile_fallback_deny` — same fallback, cross-character → deny.
  - `la_chars_compatible_no_sources_denied` — no owner_char + no profile_base → conservative deny (safer than wrong-skeleton attach).
- **Passive runtime monitor** `mod._la_spawn_monitor` fires on every player spawn (host + bots + remote husks) via the existing `SimpleInventoryExtension.extensions_ready` hook in `_la_persistence.lua` (consolidated to avoid hook_safe shadow per VMF_RECIPES.md § 1) and a parallel `SimpleHuskInventoryExtension.extensions_ready` hook in the main file. Compares cached LA hat (`_la_equips_by_peer[wearer_peer]["slot_hat"]`) against the spawned unit's character. **Mismatch detections ALWAYS log** as a warning — this is the regression safety net, so the symptom is visible in console without needing a manual chat command.
- **Mission-start state snapshot** `mod._la_dump_mission_state` called from `mod.on_game_state_changed`. Dumps every cached `_la_equips_by_peer` entry + every persisted career / illusion. Gated on the new `debug_dumps` VMF toggle.
- **New `debug_dumps` VMF toggle** (off by default). Gates the routine state snapshots; the mismatch detector remains always-on.

### Verification
1. Toggle `debug_dumps` on in VMF settings. Enter the keep; observe `[la-state-dump]` lines for cached + persisted state.
2. Start a mission with an LA hat equipped on GK and a WP bot in the party. With debug_dumps on, every spawning unit emits `[la-spawn-monitor]` with the resolved character. If a regression of issue #14 ever attaches the GK hat to the WP body, the monitor emits `[la-spawn-monitor] CROSS-SKELETON MISMATCH ...` as a warning regardless of the toggle.
3. Run `/cos_regression_test` in chat — five new `la_chars_compatible_*` checks all pass.

### Closes
- #14 (GK LA hat leaks to Warrior Priest body at mission start, host-side) — fix shipped in v0.9.11-dev, now covered by behavioral test + runtime monitor.

## 0.9.12-dev (2026-05-24) — Persist LA cosmetics + LA weapon illusions across restart

### Why
User report (issue #25): LA hats / armor / weapon illusions don't persist across game restarts. PlayFab can't store LA item names, so vanilla's loadout-restore drops them every session and the user has to re-equip from scratch. CIM-forged modded weapons persist their item record via `forged_weapons` save, but the LA illusion overlay was lost the same way.

### Changed
- New module `cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_la_persistence.lua` — single VMF setting `la_persisted_equips` shape `{ schema, careers = { [career_name] = { slot_hat, slot_skin } }, illusions = { [backend_id] = la_skin_name } }`.
- `CosmeticUtils.update_cosmetic_slot` hook (cosmetics_tweaker.lua ~L4251):
  - **Save tap** in the existing `_send_la_apply` emit branches — every LA hat / armor equip writes per-career; every LA weapon-illusion equip writes per backend_id (resolved from `inv._equipment.slots[slot].item_data.backend_id`).
  - **Inject tap** at the top of the hook — if the slot's vanilla item / vanilla skin has a saved LA overlay on disk, rewrite the argument to the LA bid before the existing net-safe substitution + emit chain runs. This is how the LA visual comes back on startup without a separate restore code path.
  - **Clear tap** in the vanilla-replacement branch — equipping a vanilla item over a saved LA one clears the on-disk entry too, so next restart doesn't bring back a cosmetic the user already removed.
- `SimpleInventoryExtension.extensions_ready` hook (in `_la_persistence.lua`) queues a per-player restore that fires once `career_name` is populated (1-frame defer). Pumped from `mod.update`. Calls `CosmeticUtils.update_cosmetic_slot` with the saved LA hat / armor name → existing flow takes over.
- Three new chat commands:
  - `/cos_persist_dump` — list saved careers + illusion count.
  - `/cos_persist_replay` — manual re-apply for the local player's current career.
  - `/cos_persist_clear` — wipe all saved entries.

### How it works for CIM-forged modded weapons
CIM's own `forged_weapons` setting already restores the modded item itself (with its `skin = vanilla_substitute` field) into the local backend mirror at boot. After the item is restored, vanilla's loadout-equip runs `CosmeticUtils.update_cosmetic_slot` with the vanilla substitute skin — our inject tap then upgrades the skin arg to the LA bid based on the backend_id key, the LA paint fires, and the visual matches what was equipped. No extra CIM-side wiring needed.

### Verification
1. Equip an LA Pureheart helm on Grail Knight in the keep. Restart VT2. GK still wears Pureheart at next session, no manual re-equip needed.
2. Equip an LA Reiland shield on a specific weapon backend_id. Restart. Same weapon paints Reiland at next session.
3. Run `/cos_persist_dump` — confirm careers + illusion entries are present.
4. Equip a vanilla hat back over the LA one. `/cos_persist_dump` shows that career's `slot_hat` is gone. Restart confirms no LA hat re-applies.

## 0.9.11-dev (2026-05-24) — Fix: LA hat leaks across characters at mission start (host-side)

### Why
User reported (issue #14): equipped an LA hat on Grail Knight, then on mission start the HOST saw the same LA hat attached to a Warrior Priest body (Kruber hat on Saltzpyre skeleton). Client view was unaffected. Reproducible whenever the host has a WP teammate (bot or player) while the cached LA hat is for a different character.

### Root cause
`_apply_la_on_unit`'s character-mismatch gate (`cosmetics_tweaker.lua` ~L4762) derived `owner_char_path` from `vanilla_key`'s `ItemMasterList` entry. But `vanilla_key` is the cached LA emit's vanilla substitute (the EMITTER's hat) — not the owner_unit's character. So for the host's `_wield_slot` repaint flowing through this function against a WP husk_unit, both `owner_char_path` and `la_unit_path` resolved to the host's GK character, the mismatch check passed, and the GK LA mesh was attached to the WP body.

The companion guard at the husk-side `PlayerHuskAttachmentExtension.create_attachment` hook (~L5543) used a different (correct) source — the incoming `item_data.unit` — and was unaffected. But that hook runs AFTER `_apply_la_on_unit` has already patched `item_data.unit` to the LA path, so it can't catch this leak either.

### Changed
- `cosmetics_tweaker.lua` `_apply_la_on_unit` hat branch: resolve `owner_char_path` from the owner_unit's currently-attached `slot_hat` `item_data.unit` instead. Fall back to `SPProfiles[player.profile_index].unit_name` (character base prefix) when the slot is empty during an early-spawn race. Bail without patching if neither source resolves.

### Verification
1. Host as GK with an LA hat equipped (e.g. Pureheart).
2. Start mission with a WP bot in the lobby.
3. Host's view: WP bot wears its vanilla WP hat, NOT the GK LA hat. Host's own GK still wears the LA hat.
4. Console log: `[cos_la_apply hat] character mismatch — owner_char=witch_hunter_priest la_char=empire_soldier_breton ...` for each wield-repaint pass against the WP bot.

## 0.9.10-dev (2026-05-23) — Versioning convention reset (drop 4th segment)

### Why
This mod had drifted to 4-segment versions (`0.9.8.7`, `0.9.9.4`, etc.) while every other mod in the repo uses 3-segment semver (`MAJOR.MINOR.PATCH`). The 4th segment had been used as a within-patch "hotfix counter", but that's not how semver works and it diverged from the rest of the codebase.

### Changed
- `MOD_VERSION` bumped `0.9.9.4-dev` → `0.9.10-dev`. Going forward, every change bumps the patch number (`0.9.10` → `0.9.11` → `0.9.12` → ...). No 4th segment.
- `itemV2.cfg` title + description updated to match.
- Past 4-segment versions (`0.9.8.x`, `0.9.9.x`) stay in the historical record below — they were already shipped under those names.

## 0.9.9.3-dev (2026-05-23) — Namespace `regression_test` chat command to avoid cross-mod collision

### Why
Seven mods registered `mod:command("regression_test", ...)`. VT2 chat commands are global — only the first mod wins, the rest fail silently with `[ERROR] (command): command name 'regression_test' is already used by another mod 'cim'`. Detected in PC-A log 2026-05-23 20:50:52.

### Changed
- `cosmetics_tweaker.lua` — renamed `regression_test` → `cos_regression_test`. Verification log line added at registration site.

### Verification
1. Restart VT2. No `[ERROR] (command):` line in console_logs about this command name.
2. Run `/cos_regression_test` in chat. Command fires and prints results.
3. Per memory `feedback_vt2_verify_before_shipping.md`.

> **Note:** the dynamic-portrait system (v0.7.0–v0.7.102 development line)
> was split out into the `dynamic_cosmetic_portraits` mod on 2026-05-06.
> Pre-split entries below remain the historical record of how the system
> was researched and stabilised; ongoing portrait work lives in
> `dynamic_cosmetic_portraits/CHANGELOG.md`.

## 0.9.0-dev (2026-05-19) — Per-peer glow + LA stabilization (high blast radius)

### Why

Day 4 of host/client desync investigation. Six fan-out research agents (CT audit + LA source + VT2 networking + prior-attempts triage + local PC logs + PC-B logs over SSH) produced four design docs (`HOST_CLIENT_AUDIT.md`, `LA_SYNC_MODEL.md`, `VT2_NETWORKING_REFERENCE.md`, `PRIOR_ATTEMPTS_TIMELINE.md`, `LOGS_LOCAL_PC.md`, `LOGS_PC_B.md`, `PER_PLAYER_VISUAL_INVENTORY.md`, `GLOW_HOOK_INVESTIGATION.md`, `ROOT_CAUSE_SYNTHESIS.md`).

**Single biggest finding:** PC-B (client) was missing MoreItemsLibrary (Workshop ID 1422758813) — a HARD dependency for `LA_BRIDGE.register_all` (`cosmetics_tweaker.lua:3885`). The bridge sentinel was dormant on PC-B the entire time; every host-side `cos_la_apply` RPC arrived but the receiver short-circuited via `[LA paint] skip: bridge not registered` (~50× per session). PC-B subscribed manually after diagnosis; new deploy rule (memory `feedback_deploy_both_machines`) prevents recurrence.

**Smoking-gun bugs surfaced after that:**

- Quadruple-emit per hat equip — `CosmeticUtils.update_cosmetic_slot` + `PUAE.game_object_initialized` + `PUAE.spawn_resynced_loadout` + `AttachmentUtils.hot_join_sync` all called `_send_la_apply` for the same change; receivers re-spawned the attachment 4× per equip, causing `Slot is not empty, remove attachment before creating a new one` errors (host-PC log, solo-repro on Pureheart_helm × Hippogryph_helm).
- Glow customization completely **un-synced**: every viewer's `apply_material_settings` hook read local `mod:get("glow_*")`, so each peer painted THEIR OWN chosen glow onto every remote husk weapon. User's #1 surface complaint.
- Hot-join replay read only the local player's `_local_la_equips`, missing every other peer's equips at join time.
- `_local_la_equips` stale on LA→vanilla swap (line 3284) leaked stale entries into future hot-join replays.
- `_la_equips_by_peer` never purged on peer disconnect.
- `mod.update` defined twice (line 624 + line 4105); the second overwrote the first so `TPE.update` silently never fired since the merge.

### What

**Per-peer GLOW channel (greenfield).** New RPC pair: `cos_glow_apply_req` (client→host) and `cos_glow_apply` (host broadcast to all). `_glow_by_peer` cache on every machine. All five glow read helpers (`_glow_master_mult`, `_glow_var_mult`, `_glow_override_enabled`, `_glow_main_rgb`, `_glow_rgb_for_var`) now accept an optional `peer_id`. The `_hook_apply_with_template_mutation` callback resolves owner-of-unit via `_glow_owner_peer_for_unit(unit)` at paint time and threads it through. Local viewer's own settings still read `mod:get` directly (instant feedback). Remote husks read `_glow_by_peer[wearer_peer]`. **Missing cache entry → no override (vanilla glow), never falls back to local viewer's color.**

Triggers for broadcast: `mod.on_setting_changed` for any `glow_*` setting, `mod.on_game_state_changed` (covers keep enter + mission start + post-host-migration). Coalesced via 300ms throttle so a multi-setting save doesn't burst N RPCs. Hot-join handler rebroadcasts ALL known peers' glow state to the new joiner before husks start spawning. Peer-disconnect purges `_glow_by_peer[peer]` alongside `_la_equips_by_peer[peer]`.

**Emit dedup on `_send_la_apply`.** Per (wearer_peer, slot, kind, armoury_key) within 500ms suppresses duplicate emits. Fixes the quadruple-broadcast → slot-not-empty errors documented in PC-A logs.

**Hat slot teardown** before `create_attachment` in `_apply_la_on_unit kind="hat"`. Uses direct destroy + nil-the-slot path (mirrors `PlayerUnitAttachmentExtension.remove_attachment` local cleanup, minus the RPC) to avoid amplifying traffic on every receive.

**Authoritative hot-join replay.** In `AttachmentUtils.hot_join_sync` hook, the host now iterates `_la_equips_by_peer` for every existing peer and re-emits `_send_la_apply` for every recorded slot. Replaces the local `_local_la_equips` walk that missed non-local peers.

**LA→vanilla swap cache clear.** When `CosmeticUtils.update_cosmetic_slot` fires with neither LA item nor LA skin substituted, any stale `_local_la_equips[player_unit][slot]` is cleared so the next hot-join replay doesn't ghost-restore the prior LA pick.

**Peer-disconnect cleanup.** `mod:hook_safe(PlayerManager, "remove_player")` purges `_la_equips_by_peer[peer]`, `_glow_by_peer[peer]`, and matching `_last_emit_at` entries. Without this, stale state leaks across host migration and Steam-recycled peer_id collisions.

**MIL-missing friendlier log + subscribe URL.** When `get_mod("MoreItemsLibrary")` returns nil at the bridge init gate, log a one-time `mod:echo` with the Workshop URL. Cheap insurance against the 4-day debug spiral repeating.

**Deferred `_G.apply_material_settings` hook.** Per agent investigation (`GLOW_HOOK_INVESTIGATION.md`), the symbol is a bare global in `flow_callbacks_foundation.lua:896`, loaded lazily by Stingray's flow graph on first hub/level enter. Eager install now retries from `mod.on_game_state_changed` until the symbol exists. This only covers NPC display weapons / hub setpieces — player paths route through `GearUtils.apply_material_settings` (always hooked successfully).

**TPE per-frame tick restored.** Merged into the single `mod.update` body.

### Deferred to v0.9.1

- Vanilla-mesh offhand picks broadcast (currently host-only sees their pick)
- `es_bastard_sword_thiccc` per-wearer broadcast (currently per-viewer; clarify intent)
- `SimpleHuskInventoryExtension.wield` re-paint hook (closes the >5s sheathe→unwield LA-illusion gap on peers)
- Receiver-side `_offhand_selection` seed on `cos_la_apply kind="offhand"` (prevents husk re-spawn from losing LA paint)
- LA `kind="unit"` custom-mesh shields visible on husks (currently deferred — vanilla mesh stays)
- 2 ranged backend IDs (`502C1B4B2D86C217`, `29D8DF12F964B3C6`) missing from offhand picker registry

### Verification matrix

- [ ] PC-A host + PC-B client. Host equips LA hat with custom color. Client sees host's hat color (not client's default).
- [ ] Reverse: client equips LA hat with their own color. Host sees client's color.
- [ ] Host equips glow preset purple. Client sees host's weapon glowing purple. Client equips glow preset green. Host sees client's weapon glowing green AND host's still purple.
- [ ] Sequential hat changes (Pureheart_helm_white → Hippogryph_helm_white → Pureheart_helm_red): no `Slot is not empty` errors in host log.
- [ ] Late-join: client disconnects + rejoins mid-mission. Glow + LA state catches up via hot-join broadcast.
- [ ] Host migration: existing client takes over hosting. _la_equips_by_peer + _glow_by_peer cleanups + rebroadcasts on game_state_changed restore state.

---

## 0.8.67-dev (2026-05-19) — Server-authoritative `cos_la_apply` routing

### Why

The v0.8.66 peer-broadcast model (`mod:network_send("cos_la_apply", "others", ...)`) reached the host via VMF's host-relay transport (`mod_manager.lua:595-605`), but the host's apply still silently bailed in observable cases — texture changes only appeared on the equipping player, never on host or other clients. Root cause analysis (2026-05-19 fan-out) identified three compounding issues with the broadcast model:

1. **`go_id` over the wire is host-relative.** `Managers.state.unit_storage:go_id(unit)` returns an id that's only meaningful for units the engine has registered as networked game objects. During the equip → spawn → broadcast race, the receiver's `storage:unit(go_id)` could return nil and the handler silently bailed.
2. **Late-spawn races on join.** A peer receiving a `cos_la_apply` before the wearer's player_unit was locally spawned just dropped it; no retry.
3. **Hot-join replay was per-peer.** Each existing peer's `AttachmentUtils.hot_join_sync` walked the joining peer's slots and emitted private replays. With no central authority, dropped/duplicate messages weren't reconcilable.

### How

Switched to client-request → host-broadcast routing. The host is the only source of `cos_la_apply` messages; clients send `cos_la_apply_req` to the host, which validates, records into per-peer authoritative state, then broadcasts the authoritative apply to ALL peers (including the requesting client, so they apply in lockstep with everyone else). Receivers reject any `cos_la_apply` whose sender_peer_id isn't the host.

**Identity over the wire is now `wearer_peer_id`** (deterministic across peers) instead of `go_id`. Receiver resolves the wearer's player_unit via `Managers.player:players_at_peer(wearer_peer_id)`. If the unit isn't spawned yet (loading screen race / late network spawn / husk not wielding the right slot), the payload is queued and re-tried on `mod.update` for up to 5 seconds.

### Patches

| File / region | Change |
|---|---|
| `cosmetics_tweaker.lua` — `_send_la_apply` (~line 3419) | Rewrote: signature dropped `recipient` arg; resolves `wearer_peer_id` from `Managers.player:owner(unit)`; routes to host via `cos_la_apply_req` (clients) or short-circuits and broadcasts directly to "all" (host). |
| `cosmetics_tweaker.lua` — `cos_la_apply` receiver (~line 3617) | Rewrote: auth-gates on `sender_peer_id == host_peer_id` (rejects spoofed broadcasts). Reads `wearer_peer_id` from payload, calls `_try_apply_by_peer` → `_apply_la_on_unit` (the new unified apply core extracted from the previous receiver). On failure (wearer unit not yet spawned), queues into `_la_pending_apply`. |
| `cosmetics_tweaker.lua` — new `cos_la_apply_req` receiver (host-only) | Validates `armoury_key ∈ LA_BRIDGE.armoury_to_backend`, records into `_la_equips_by_peer[sender_peer_id][slot] = { kind, armoury_key, vanilla_key }`, broadcasts `cos_la_apply` to "all". |
| `cosmetics_tweaker.lua` — new `_apply_la_on_unit` (extracted from receiver) | Returns bool: `true` if applied, `false` if target unit isn't ready (so the caller can re-queue). Same per-`kind` branches as the old receiver — hat / armor / offhand / illusion — all bracketed with `LA_BRIDGE._bridge_active = true / false` for receivers that also have cosmetics_tweaker installed (the apply_gate at `_la_bridge.lua:568` blocks LA-managed keys otherwise). |
| `cosmetics_tweaker.lua` — `mod.update` (~line 3880) | Added pending-queue drain: every frame, retry every queued payload via `_try_apply_by_peer`. Entries past their 5-second deadline are dropped. Bounded retry prevents the queue from leaking when a wearer's unit never spawns (e.g. peer disconnected before replicating into our session). |
| `cosmetics_tweaker.lua` — emit sites at lines 2040, 3284, 3305, 3739, 3758, 3795, 3823, 3845 | Updated signature: `_send_la_apply(unit, slot, kind, ak, vk)` (no recipient arg). All routes now flow through the new server-authoritative function. AttachmentUtils.hot_join_sync emits dropped the `peer_id` arg — the host's broadcast to "all" already includes the joiner. |

### Non-cosmetics_tweaker peers (gracefully degrade)

VMF's `mod:network_register` adds the handler to a dispatch table keyed by message name. Peers that don't have cosmetics_tweaker never registered `cos_la_apply` / `cos_la_apply_req` and silently drop incoming messages on receipt — verified by the pattern in `chaos_wastes_tweaker.lua:274-358` (ct_sync_host_settings_chunk has been live for months in mixed-mod lobbies without crashes). Host without cosmetics_tweaker → all client equip requests are silently dropped; clients see only their own local apply (degraded behavior, no crash).

### Tradeoff

When the equipping client emits a request, they no longer apply locally first — they wait for the host's broadcast to round-trip back. With normal latency that's <50 ms (one client-host RTT plus host broadcast), invisible. On high-latency lobbies the wearer briefly sees vanilla before LA paints. Acceptable for the consistency win — all peers now see the same thing instead of a per-peer desync.

### Known limitation

The host must have cosmetics_tweaker installed for ANY peer to see LA visuals. Without it, the `cos_la_apply_req` is silently dropped at the host's VMF dispatcher → no broadcast → no peer ever applies. The substitute hooks (CosmeticUtils / LoadoutUtils / PUAE / AttachmentUtils) still rewrite outgoing LA bids to vanilla so non-cosmetics_tweaker peers don't crash — they just see vanilla colors. Documented; ship as-is.

## 0.8.66-dev (2026-05-18) — LA shield host crash: divergent NetworkLookup.inventory_packages indices

### Fixed: client equipping a `kind="unit"` LA shield crashed the host with `inventory_packages` key miss

Verbatim crash on lynnd's host machine (session `9daf2cf6-f1a2-4e15-bdfa-e780871424cd`, level `morris_hub`):

```
scripts/network_lookup/network_lookup.lua:2514:
[NetworkLookup.lua] Table inventory_packages does not contain key: 2296
```

Triggered while decoding an `inventory_list` SharedState update from peer `11000010ef3befb` (danjo, the client) — specifically the `first_person_packages` array at position 9 of 17 — when danjo equipped a Loremaster's Armoury shield with `kind="unit"`. The encoded network ID 2296 had no entry in lynnd's `NetworkLookup.inventory_packages`.

Same bug class as ct v0.7.60 (dormants) / v0.7.61 (trait boons) / v0.7.62 (adventure levels) — see `feedback_vt2_gated_registration_diverges.md`. `_la_bridge.lua`'s `build_offhand_options` iterated `pairs(la().SKIN_LIST)` (unordered) and only called `_register_la_path_in_network_lookup` for variants whose `_is_supported_variant` returned true — which calls `Application.can_get("unit", ...)`, a timing-dependent check on LA's asset loading state. With `idx = #ip + 1`, even one skipped or reordered variant shifts every subsequent index → the same path lands on different network IDs across peers → ProfileSynchronizer's RPC fatals the receiver via the strict `__index` on inventory_packages.

`_la_bridge.lua` now exports `pre_register_la_inventory_packages()` that iterates `SKIN_LIST` keys in sorted order and registers every `kind="unit"` left-hand variant's `new_units[1]` + `new_units[2]` unconditionally — no `_is_supported_variant` / `can_get` filtering. It runs at the very top of `M.register_all` so it executes as soon as LA + MIL are detected (the existing gate in `cosmetics_tweaker.lua:3712-3727`). Both existing `pairs(la().SKIN_LIST)` loops in `register_all` and `build_offhand_options` are also converted to sorted-key iteration so the downstream `NetworkLookup.item_names` appends in `register_all` (lines 505-514) are deterministic across peers too — a latent twin bug for hat/armor clones.

The new registration is purely additive: `_register_la_path_in_network_lookup` guards on `rawget(ip, path)` so re-runs are no-ops. Diagnosed from the host's console log; same incident also produced an unrelated GPU-driver deadlock on amand's machine (NvMemMapStoragex / nvwgf2umx during inn_level pipeline-state creation) — that's a Material-Hijack × NVIDIA driver interaction, not addressed here.

### Fixed: LA recolors didn't sync to peers — armor + weapon illusion

Three coordinated changes covering the second half of the bug report ("host can't see the color change when a client equips an LA recolor"):

**1. Receiver-side `apply_gate` blocked the husk paint.** `cos_la_apply` receiver `kind="armor"` (cosmetics_tweaker.lua:3489) called LA's `apply_new_skin_from_texture` directly. On receivers that ALSO have cosmetics_tweaker, the `apply_gate` installed by `_la_bridge.lua:568` blocks any LA-managed armoury_key when `_bridge_active=false`. The husk-side paint never ran → host saw vanilla even when the cos_la_apply RPC arrived. Bracketed the `pcall` with `LA_BRIDGE._bridge_active = true / false` (matches the local `apply_direct` pattern at `_la_bridge.lua:595-597`).

**2. Missing RPC for weapon illusions (row-1 picker).** `update_cosmetic_slot` v0.8.64 substitutes LA `skin_name` → vanilla for crash-safety, but never emitted a `cos_la_apply` to tell peers to repaint. Peers saw vanilla colors on the wielded weapon. Added a new send branch that fires `cos_la_apply` with `kind="illusion"` when `la_skin_subbed and not la_item_subbed`. New receiver branch in `cos_la_apply` paints the husk's `right_hand_wielded_unit_3p` / `left_hand_wielded_unit_3p` via `apply_new_skin_from_texture` — also bracketed with `_bridge_active`. Hot-join replay (`AttachmentUtils.hot_join_sync` extension) re-emits to joiners for weapon-illusion entries recorded in `_local_la_equips` (now keyed by any slot — not just slot_hat / slot_skin).

**3. Local player saw vanilla on themselves.** `find_active_clone_for_unit_path` (`_la_bridge.lua:532`) read the loadout via `items_iface:get_loadout()`, but the `get_loadout` hook in `cosmetics_tweaker.lua:3114` rewrites LA backend_ids back to vanilla for net-safety. The lookup missed → `apply_direct` never fired → `_bridge_active` stayed false → LA's own update-loop apply was blocked by the gate → vanilla render on the wearer's own view. Fixed by consulting `cosmetics_tweaker.mod.loadout_cache` (the un-rewritten cache populated by the `set_loadout_item` hook for slot_hat / slot_skin) FIRST, then falling back to vanilla loadout. The cache merge in `get_loadout` (cosmetics_tweaker.lua:3135-3140) re-injects on top of the rewrite so the fallback still works for steady-state cache hits, but checking the cache first catches the race window during initial equip before the merge runs.

#### Patches at a glance

| # | File | Region | Change |
|---|---|---|---|
| 1 | `_la_bridge.lua` | `pre_register_la_inventory_packages` (~line 230) | Drop the `swap_hand == "left_hand_unit"` filter — register every `kind="unit"` variant in sorted order. *(covered above — Patch 1.)* |
| 2 | `_la_bridge.lua` | `find_active_clone_for_unit_path` (~line 532) | Consult `cosmetics_tweaker.mod.loadout_cache` first; fall back to vanilla loadout. |
| 3 | `cosmetics_tweaker.lua` | `cos_la_apply` receiver `kind="armor"` (~line 3489) | Bracket the `pcall(la.apply_new_skin_from_texture, ...)` with `LA_BRIDGE._bridge_active = true / false`. |
| 4 | `cosmetics_tweaker.lua` | `update_cosmetic_slot` hook (~line 3268) + `cos_la_apply` receiver new `kind="illusion"` branch + `AttachmentUtils.hot_join_sync` replay | New end-to-end `kind="illusion"`: emit, decode, paint husk wielded weapon, hot-join replay. |

### Known issue — NOT patched in v0.8.66

After a host-migration kick (`broken_connection ... authentication_denied`), the `[LA fix kind=unit] set_all_materials` step stops firing in the inventory previewer — every subsequent `[LA paint]` reports `ok=false`. Reproduced in the 2026-05-19 01:59:11 log lines 6911-6983. Likely root cause: `LootItemUnitPreviewer.spawn_units` `mod:hook` (not `hook_safe`) timing in the standalone post-migration state — `_offhand_selection` lookup fails because the loadout reference changed after migration. Tracked for v0.8.67-dev.

### Verification

- Both peers must restart VT2 to pick up v0.8.66 (cosmetics_tweaker hooks unit-creation paths and material managers; the C++-level resource locks make Ctrl+Shift+R reload unsafe per CLAUDE.md "Important Constraints").
- Patch 2 repro: equip an LA hat/armor recolor. Pre-v0.8.66 the LOCAL player saw vanilla on themselves until alt-tab; v0.8.66+ the LA paint applies on the first frame after equip.
- Patch 3 repro: equip an LA `kind="texture"` armor recolor with another peer (who also has cosmetics_tweaker) in the lobby. Pre-v0.8.66 the peer saw vanilla; v0.8.66+ the peer sees the LA paint.
- Patch 4 repro: equip an LA-cloned weapon illusion (row-1 picker) in lobby. Pre-v0.8.66 peers saw vanilla colors on the wielded weapon; v0.8.66+ peers paint the LA illusion. Hot-joiners get the paint too.

## 0.8.65-dev (2026-05-18) — Custom-illusion DLC paywall bypass fix

**Bug.** `get_unlocked_weapon_skins` hook's custom-skin loop (cosmetics_tweaker.lua:1043) unconditionally wrote `mirror._unlocked_weapon_skins[skin_key] = true` for every entry in `_custom_skin_keys`. Custom illusions are cloned on top of DLC-gated base weapons and inherit `required_dlc` at registration time, so a player without (e.g.) the relevant Bardin/Saltz DLC was getting the apply-button for the cloned illusion unlocked anyway. The vanilla-skin path on the next branch already consults `_skin_requires_unowned_dlc`; the custom path was the inconsistency.

**Fix.** Gate the custom-loop write with `_skin_requires_unowned_dlc(skin_key)`, matching the vanilla branch. Modded crafting still grants the power-up over career-level / crafting-material progression; DLC ownership remains the hard line via `Managers.unlock:is_dlc_unlocked`.

## [2026-05-18 v0.8.64-dev]
### Unified LA peer-sync — cos_la_apply covers hats + armor + shields, plus weapon-skin leak fix and 1P/3P path fix

Four-bug bundle from a fan-out audit on the v0.8.58 → v0.8.62 LA peer-sync stack. The substitute hooks from v0.8.58-v0.8.61 (CosmeticUtils, LoadoutUtils, PUAE×2, AttachmentUtils — the "replace" half of replace-not-append) are preserved; this version adds the "apply" half across all three LA visual surfaces and closes a latent crash that v0.8.58 left behind.

**A. Shields (gap 1) — peer-sync the offhand picker.** `_offhand_selection` is per-peer LOCAL: each peer reads their OWN selection in `BackendUtils.get_item_units` when spawning ANY husk, so each peer renders their own picker choice on everyone instead of the actual wearer's. The v0.8.62 changelog claimed `_offhand_selection` was "host-controlled" — it isn't. Now sent via `cos_la_apply` (kind="offhand") from two sites: (1) when the local user clicks a row-2 shield in `HeroWindowItemCustomization._ct_on_offhand_pressed`, and (2) when `AttachmentUtils.hot_join_sync` fires for a joining peer (replay the local player's currently-wielded shield).

**B. Hats (gap 2) — 1P/3P path verification.** `cos_la_attach` (v0.8.62) checked `Application.can_get("unit", la_unit_path)` only for the 1P path, but husks render the 3P attachment. When the 3P unit wasn't loadable on the viewer the hat silently vanished — most likely cause of "LA hats invisible on peers". The receiver now verifies BOTH the 1P path AND `<path>_3p`; if neither loads it logs and bails. Also removed the async race: cos_la_apply replaces (not appends to) the vanilla send, because vanilla NEVER carries an LA key over the wire after the substitution.

**C. Armor (gap 3) — texture-paint replay on the husk body.** v0.8.62 explicitly punted armor. LA's `apply_new_skin_from_texture` paints the player_unit 3P body directly with hardcoded material slots (`texture_map_64cc5eb8` / `_861dbfdc` / `_abb81538`) for `swap_hand=='armor'` variants. Husk body uses the same slot names, so the receiver calls `LA.apply_new_skin_from_texture(armoury_key, level_world, vanilla_key, husk_player_unit)` directly. Dispatched from `CosmeticUtils.update_cosmetic_slot` for live equips (slot_skin is "cosmetic" category, NOT "attachment", so it doesn't flow through PUAE / AttachmentUtils.hot_join_sync) and from `AttachmentUtils.hot_join_sync` to joiners via a new `_local_la_equips` map recorded at equip time.

**D. Weapon-skin leak (gap 4 — latent crash).** The existing `CosmeticUtils.update_cosmetic_slot` hook substituted the 4th arg `item_name` but NOT the 5th arg `skin_name`. `cosmetic_utils.lua:245` reads `NetworkLookup.weapon_skins[skin_name]` and `:249` broadcasts via `player:set_data`. If the user equipped an LA-cloned WEAPON ILLUSION (not a hat or armor — a row-1 illusion pick), the LA skin_name reached peers' decode path and crashed them in the same class as the v0.8.58 fa479a72 crash. Hook now substitutes BOTH args.

### Implementation notes

- New RPC `cos_la_apply` with payload `{go_id, slot, kind, armoury_key, vanilla_key}`, dispatched by `kind ∈ {"hat", "armor", "offhand"}`.
- Identity key is **armoury_key** (LA's deterministic `Kruber_Pureheart` etc.), not `la_backend_id`. la_backend_id is mostly deterministic across peers but has a silent-bail failure mode when the receiver's `ItemMasterList[la_backend_id]` lookup misses; armoury_key matches what LA's own `SKIN_LIST` keys by and sidesteps the issue.
- Forward decl `local _send_la_apply` near the `_offhand_selection` table (~line 1709) so `_ct_on_offhand_pressed` (~line 2004) can call it before the real impl in the cos_la_apply block (~line 3290). Without the forward decl the closure would capture `_G._send_la_apply` (nil) instead of the local slot — same forward-reference rule documented in `feedback_lua_forward_reference.md`.
- Offhand RPC sends the WEARER's player_unit go_id (not the left-hand unit go_id) — `left_hand_wielded_unit_3p` is a local-spawned unit with no network identity. Receiver looks up its own husk's `inventory_extension._equipment.left_hand_wielded_unit_3p` and paints that. If the husk isn't currently wielding the shielded slot at receive time, the call is skipped — the next wield re-spawns the unit and re-triggers via the wearer's existing equip path.
- `_paint_offhand_textures_locally` in `_la_bridge.lua` now formally documents four contexts: `ingame`, `hero_previewer`, `loot_previewer`, `network_husk`. The kind="unit" early-return remains: husk-side mesh swap would require despawning/respawning a network-coupled unit, so kind="unit" husk variants are deferred (vanilla mesh stays). kind="texture" variants paint normally.
- v0.8.58-v0.8.61 substitute hooks UNCHANGED — they are the "replace" half of replace-not-append. The substitute makes vanilla peers crash-free; cos_la_apply makes LA-aware peers visually correct. Both halves are required.
- VMF namespace handling: peers without cosmetics_tweaker never receive cos_la_apply (no-op, vanilla substitute is what they see). Peers with cosmetics_tweaker but without LA bail at the SKIN_LIST lookup.

### Tradeoffs preserved from v0.8.62

- Brief visual flicker on peer-side as vanilla spawns then immediately gets replaced/repainted by LA. Acceptable for the v0.8.64 ship.
- kind="unit" LA shields on peers: vanilla mesh stays (no peer-side mesh swap). Texture-paint LA shields work end-to-end.

## [2026-05-17 v0.8.63-dev]
### Experimental: Third-Person Equipment
Adds a togglable feature that spawns 3P meshes of every loadout weapon you aren't currently holding, attached to your character. Inspired by the standalone Third Person Equipment mod (Workshop 1387440934).

Scope this pass: clean reimplementation of the spawn/link/visibility machinery in `_tpe.lua`. Off by default (`tpe_enable` checkbox).

Implementation:
- New file `_tpe.lua`: per-`item_type` attachment table (categories: `two_handed_back`, `one_handed_belt`, `one_handed_shield`, `dual_belt`, `ranged_back`, `bow_back`, `throwable_belt`, `potion_hip`, `grenade_hip`, `healthkit_back`, `default`). Maps every vanilla `item_type` from `item_master_list_*.lua` into one of those categories. Per-career fine tuning deferred — positions are coarse defaults.
- Hooks installed once at module load, all early-return when `tpe_enable` is OFF: `PlayerUnitFirstPerson.set_first_person_mode` (toggle visibility on FP/3P switch), `SimpleInventoryExtension.wield` + `SimpleHuskInventoryExtension.wield` (track wielded slot, hide its mesh), `SimpleInventoryExtension.destroy`/`destroy_slot` + husk variants (cleanup), `PlayerUnitHealthExtension.die` (cleanup).
- Per-frame `create_items_if_needed` driven by new `mod.update(dt)` — iterates `Managers.player:human_and_bot_players()`, calls `add_all_items` for any alive player_unit we haven't seen yet. Skips while packages are still queueing.
- Weapon-skin awareness: resolves `WeaponSkins.skins[slot.skin].right_hand_unit`/`.left_hand_unit` per equipped skin before appending `_3p`, then applies `material_settings` via `GearUtils.apply_material_settings`.
- Defensive: `Application.can_get("unit", path)` pre-check before `World.spawn_unit` so CWV custom-mesh weapons whose 3P unit isn't in memory simply skip rather than fatal.
- Two tuning settings: `tpe_show_self_in_3p` (hide own holstered weapons while in first-person; default ON), `tpe_downscale_big_weapons` (percent scale 25-100, default 100). Any TPE setting change calls `M.flush()` which destroys every spawned unit so the next tick respawns with new geometry.

Caveats vs. the original Third Person Equipment mod:
- No per-career / per-skin position tuning — TPE ships hundreds of lines of dwarf/elf/saltz/etc. specific position+rotation tables, this ships one set keyed only by item_type.
- No dwarf-backpack alternate node (engineer/ranger backpack carry positions).
- No slayer dual-axe replace-on-conflict logic.
- CWV custom-mesh variants will appear at the category-default position, not their actual visual shape's correct holster point.

Expect to tune positions per item_type once we see what looks acceptable in-game. The whole feature is gated experimental; release after the tuning pass.

## [2026-05-17 v0.8.62-dev]
### LA peer fidelity — peers with LA + cosmetics_tweaker see the real LA hat
v0.8.58→v0.8.61 stopped the crash by substituting the LA backend_id for its vanilla equivalent in every outgoing sync. Peers never see a bad NetworkLookup index — but they also never see the LA hat; the host renders the vanilla equivalent of the user's Grail Knight LA hat instead of LA's mesh. Confirmed in a two-PC test (Moonlight-controlled client on PC-B, host on PC-A): host shows vanilla Kruber hat where LA hat was expected.

Fix: parallel VMF custom RPC `cos_la_attach` fired AFTER every vanilla `rpc_create_attachment` send. Payload `{go_id, slot, key=la_backend_id}`. Sent from the same three send sites the substitute hook already covered (`PUAE.game_object_initialized` → all others; `PUAE.spawn_resynced_loadout` → all others; `AttachmentUtils.hot_join_sync` → targeted to the joining peer).

Receive side resolves the LA mesh path locally:
1. `LA_BRIDGE.backend_to_armoury[key]` → LA armoury_key.
2. `Loremasters-Armoury.SKIN_LIST[armoury_key].new_units[1]` → LA mesh unit path (peer's own LA install — works even if the wearer's exact LA version differs, as long as the armoury_key resolves to a unit on the peer).
3. `Application.can_get("unit", path)` to verify the mesh is loadable; bail if not.
4. Clone `ItemMasterList[la_backend_id]`, override `.unit` to the LA mesh, call `attachment_extension:create_attachment` — which removes the just-spawned vanilla and re-spawns the LA mesh in the same slot.

VMF namespace handling means: peers without cosmetics_tweaker never receive this event (no-op, vanilla substitute is what they see). Peers with cosmetics_tweaker but without LA bail at step 1.

Scope: hats only this pass. Armor uses LA's texture-paint pipeline (no unit swap), and would need a separate replay-the-texture-paint RPC. Shields use cosmetics_tweaker's local-only `_offhand_selection` and are never sent to peers — they're already host-controlled visuals and out of scope.

Tradeoff: brief visual flicker on peer-side as vanilla spawns then immediately gets replaced by LA. Acceptable for the v0.8.62 ship.

## [2026-05-16 v0.8.61]
### Pre-alpha audit — close the 3 remaining peer-sync surfaces for LA cosmetics
Followup to v0.8.58→v0.8.60. Vanilla source audit found three more send sites that read `NetworkLookup.item_names[<LA backend_id>]` inline (no function wrapper to intercept), all under attachment-spawn RPCs:
- **`PlayerUnitAttachmentExtension.game_object_initialized` (line 63)** — local player initial spawn; sends `rpc_create_attachment` for every attachment slot to clients (host) / server (client).
- **`PlayerUnitAttachmentExtension.spawn_resynced_loadout` (line 301)** — fires after a mid-mission loadout resync (e.g. dropped item).
- **`AttachmentUtils.hot_join_sync` (line 99)** — fires PER NEWLY-JOINED PEER for every attachment slot already worn; the most likely public-alpha trigger (the v0.8.58 crash was Friend joining a Lobby).

Fix shape: since these read the lookup directly via raw table access (not through any function we can wrap), the substitution happens by mutating `slot_data.item_data.name` (or `slot_data.name` for the AttachmentUtils path) to the vanilla equivalent immediately before vanilla runs, then restoring after. The swap window is the single vanilla call; no other code runs mid-call, so the swap is invisible to LOCAL apply. `pcall` guarantees restoration even if vanilla errors.

`AttachmentUtils` is a plain table (`AttachmentUtils = AttachmentUtils or {}` at `attachment_utils.lua:1`) — same string-form pitfall that burned v0.8.58/v0.8.59 — so the hook uses table-form with a nil guard.

### Hook-registration startup verification
Added `_net_safe_hook_status` map for the four plain-table sync hooks (CosmeticUtils, LoadoutUtils, AttachmentUtils, PUAE). `mod:info` logs applied/missing state at end of mod init, and if ANY hook failed to register the user sees a warning in chat: `WARNING: one or more LA peer-sync hooks did NOT register`. Closes the v0.8.58→v0.8.59 silent-failure mode where a string-form hook on a plain table would no-op without diagnostics.

### Out-of-scope from this pass (verified safe)
- Pickup-projectile extractors at `game_object_initializers_extractors.lua:1226/1281/1330` send `NetworkLookup.item_names[item_name]` for pickup units — but `item_name` resolves through `AllPickups[pickup_name].item_name`, which only contains vanilla pickup item keys (potions, grenades, healthkits, etc.). LA doesn't author pickup items, so no LA backend_id can reach those extractors.
- Versus mode party-selection sync (`versus_party_selection_logic.lua:500-504/939-943`) writes cosmetic-slot indices, but is unreachable from Adventure/Chaos Wastes — the primary cosmetics_tweaker user surface — and Versus has its own mod-compat story.
- The receive sites in inventory_system / cosmetic_utils / etc. are decode-only; they fatal on bad indices but cannot leak local indices.

## [2026-05-16 v0.8.60-dev]
### Peer crash — second sync path (LoadoutUtils.sync_loadout_slot RPC)
- **Same crash GUID-pattern as v0.8.58/v0.8.59 — still reproduces after v0.8.59.** v0.8.59 correctly hooked `CosmeticUtils.update_cosmetic_slot` (the SyncData path) — but `SimpleInventoryExtension.add_equipment` (line 885) calls `update_cosmetic_slot` AND **then immediately** calls `LoadoutUtils.sync_loadout_slot(self.player, slot_name, item)`. The latter sends an `rpc_sync_loadout_slot` RPC whose payload includes `item_id = NetworkLookup.item_names[item.key]` — i.e. the same local LA index the v0.8.58 patch was meant to stop. v0.8.59 left this path untouched.
- Same plain-table pitfall as CosmeticUtils: `LoadoutUtils = LoadoutUtils or {}` at `loadout_utils.lua:1`, so the hook must be table-form with a nil guard. String-form `mod:hook("LoadoutUtils", ...)` would silently never register and we'd be back here for v0.8.61.
- Fix: hook `LoadoutUtils.sync_loadout_slot` table-form. If `item.key` is an LA backend_id (`LA_BRIDGE.backend_to_armoury[item.key] ~= nil`), build a `shadow` table copying every field and substituting `shadow.key = LA_BRIDGE.backend_to_vanilla[item.key]` before calling vanilla. If no vanilla fallback exists, skip the call entirely (peer sees no equipment change for this slot — preferable to a fatal). Also covers `LoadoutUtils.hot_join_sync`, which re-invokes `sync_loadout_slot` per loadout slot for each newly-joined peer.
- **Both peers must restart VT2 to pick up v0.8.60 before re-testing LA cosmetics in lobby.** A peer running v0.8.59 still has the leaky RPC path even if the other peer is on v0.8.60 — the RPC is sent from the client wearing the LA cosmetic, decoded on the receiver, so the SENDER must be on v0.8.60 for the substitution to fire.

## [2026-05-16 v0.8.59-dev]
### Re-fix peer crash — v0.8.58 hook never registered (string-form on plain table)
- **Crash GUID 2b0ff53d** — same `NetworkLookup.lua:2514: item_names key 2959` crash reproduced on v0.8.58 even though v0.8.58 was meant to fix exactly this. Root cause: `CosmeticUtils` is a **plain table** (`CosmeticUtils = CosmeticUtils or {}` at `cosmetic_utils.lua:3`), not a class. v0.8.58 hooked it via string-form `mod:hook("CosmeticUtils", ...)`, which VMF can't resolve for plain tables — the hook silently never registered and the sync ran vanilla, leaking the local LA item_names index 2959 to peers.
- Same pitfall is documented for BackendUtils in CLAUDE.md "Hooking" section: plain tables require table-form `mod:hook(TableRef, ...)` with a nil guard.
- Fix: switched to `if CosmeticUtils then mod:hook(CosmeticUtils, "update_cosmetic_slot", ...) end`. Hook now actually fires and the substitution v0.8.58 described is in effect.
- **Note for the friend in your lobby:** when both peers have cosmetics_tweaker the friend's client also rawsets LA indices into THEIR `NetworkLookup.item_names`, and pairs() iteration order in `_la_bridge.register_all` is unspecified, so the two clients may have assigned DIFFERENT local indices to the same LA item. v0.8.59's hook prevents the user's client from sending LA indices in the first place — but the friend needs to restart VT2 to pick up the updated mod (and ideally needs v0.8.59 themselves before trying on LA cosmetics from their side).

## [2026-05-16 v0.8.58-dev]
### Stop network-syncing LA cosmetic backend_ids to peers (peer-crash fix)
- **Crash GUID fa479a72** — friend hosting a lobby crashed with `NetworkLookup.lua:2514: Table item_names does not contain key: 2959` when the user (with cosmetics_tweaker + LA) tried on a Grail Knight LA hat.
- Root cause: cosmetics_tweaker's LA bridge `register_all()` adds each LA clone's backend_id to the LOCAL `NetworkLookup.item_names` via `rawset` (necessary to make the items addressable in this client's session). When the user equips an LA cosmetic, vanilla `CosmeticUtils.update_cosmetic_slot` calls `player:set_data(slot, NetworkLookup.item_names[la_backend_id])` — the LOCAL index gets broadcast via SyncData. Peers without the matching local rawset have no entry at that index → `__index` metamethod fatal on decode.
- Fix: hook `CosmeticUtils.update_cosmetic_slot`. If `item_name` matches `LA_BRIDGE.backend_to_armoury`, substitute with `LA_BRIDGE.backend_to_vanilla[item_name]` (the vanilla item key the LA clone was minted from — every vanilla client knows it) before calling vanilla. If no vanilla fallback exists, skip the sync entirely.
- Local visual unaffected: the local player's LA hat is applied via the loadout cache + LA's own apply path, not via sync_data. Peers see the vanilla equivalent — closest thing they can render without our mod or LA.
- Covers every cosmetic slot CosmeticUtils handles: slot_hat, slot_skin, slot_frame, slot_melee, slot_ranged, slot_pose.

## [2026-05-16 v0.8.57-dev]
### LA offhand pool: family-aware cross-pollination + bow filter

Two cross-pollination bugs reported in v0.8.56:

1. **Bret-textured shield skins wrapped around Empire shield mesh** on Kruber's `es_1h_sword_shield` (and `es_1h_mace_shield`, `es_deus_01`). Root cause: `_LA_CHARACTER_SHIELD_TYPES` (introduced v0.8.54-dev) cross-pollinated every Kruber LA shield variant onto all 4 of his shield item_types. For `kind="texture"` variants — which paint onto whatever mesh the base item uses, without swapping the mesh — a Bret-authored texture painted onto an Empire kite-shield mesh wraps incorrectly (Bret UV layout authored for a heater shield).
2. **Kerillian's LA bow models appeared as offhand options** on her `we_1h_spears_shield`. Root cause: LA bow variants share `swap_hand = "left_hand_unit"` with shields (the bow body wields in the left hand), so they entered the offhand pool via the outer `swap_hand == "left_hand_unit"` filter. No subsequent check verified that the variant's authored icons actually map to shield item_types.

Fixes (both in `_la_bridge.lua build_offhand_options`):

- Replaced flat `_LA_CHARACTER_SHIELD_TYPES` with `_LA_CHARACTER_SHIELD_FAMILIES`, splitting Kruber's shields into `empire` (sword+shield, mace+shield, deus_01) and `breton` (sword+shield_breton). Bardin / Kerillian / Saltzpyre each have a single family.
- During variant parsing, derive `authored_family` from the variant's first icon-key that matches a known shield item_type, and set `has_shield_authored = true` if any icon does.
- Skip variants where `has_shield_authored == false` (filters bows and other non-shield left-hand variants).
- Family-aware cross-pollination: `kind="unit"` variants still get the broad pool (their `new_units[1]` swaps the displayed mesh on apply, so they render correctly on any base). `kind="texture"` variants get cross-pollinated only WITHIN their authored family.
- Reverse-lookup tables (`_SHIELD_TYPE_TO_FAMILY`, `_LA_CHARACTER_ALL_SHIELDS`, `_ALL_SHIELD_TYPES`) built once at module load from the families table.

Existing memory `feedback_la_offhand_paint.md` already documented "mesh-must-match-texture for LA shields"; this version operationalizes that constraint for cross-pollination, not just for the per-variant `intended_unit` resolution.

## [2026-05-16 v0.8.56-dev]
### Independent offhand swap for ALL dual-wield weapons
Two bugs discovered in v0.8.51's W2 work:
1. **Pool used `right_hand_unit`** for every skin, but mixed-pair dual-wields (Bret hammer+sword, Saltzpyre axe+falchion, Kerillian sword+dagger) have DIFFERENT right- and left-hand weapons. The picker overrides `left_hand_unit`, so it was offering the wrong half. For Bret hammer+sword the picker was offering mace variants for the left hand instead of sword variants.
2. **Half the dual-wield item_types reference skin_combination_tables that DON'T EXIST in vanilla.** `dr_dual_wield_hammers_skins`, `es_dual_wield_hammer_sword_skins`, `wh_dual_wield_axe_falchion_skins`, and `wh_dual_hammer_skins` are all referenced by IML entries but missing from `WeaponSkins.skin_combinations`. Pools for these came back empty, so no picker appeared.

Fixes:
- Replaced `_DUAL_WIELD_SKIN_TABLES` with `_DUAL_WIELD_POOLS` keyed by item_type, each entry is `{ skin_table, unit_field }`. `unit_field` is `"left_hand_unit"` for native dual-wield tables (universally correct: matched-pair = same as right, mixed-pair = the actual offhand).
- For the 4 dual-wields with missing tables, borrow a single-hand skin table that matches the LEFT-hand weapon kind:
  - `dr_dual_wield_hammers` (left = 1h dwarf hammer) → `dr_1h_hammer_skins`
  - `es_dual_wield_hammer_sword` (left = 1h Empire sword) → `es_1h_sword_skins`
  - `wh_dual_wield_axe_falchion` (left = Saltzpyre falchion) → `wh_1h_falchion_skins`
  - `wh_dual_hammer`: omitted (only one base unit and no 1h skin table exists; picker would be a single-element no-op).
- `_build_offhand_options_from_skin_table` now takes a `unit_field` parameter so borrowed single-hand tables work correctly (1h skins store the weapon in `right_hand_unit`).

Result: every Kruber dual-wield (sword+sword via dr_dual etc. doesn't exist for him, but hammer+sword now works), Bardin dual-wield (axes + hammers), Kerillian dual-wield (daggers, swords, sword+dagger), Saltzpyre dual-wield (axe+falchion) gets a meaningful offhand picker. Same-character rule unaffected — pools are derived from character-prefixed skin tables.

## [2026-05-16 v0.8.55-dev]
### Fix main-hand cycling swapping the shield preview
- Bug: cycling main-hand axe/sword illusions in the row-1 picker was flipping the previewed shield (row-2 offhand) to whatever the new skin's `left_hand_unit` paired. The user's offhand pick was preserved in `_offhand_selection[backend_id]` but never applied during preview-cycle because vanilla `_on_illusion_index_pressed` rebuilds the previewer with the PENDING skin's IML entry (`item.data = ItemMasterList[pending_skin]`, no `backend_id` stamped). Our `BackendUtils.get_item_units` hook reads `_offhand_selection` by backend_id; with backend_id=nil it found nothing and let the new skin's paired shield through.
- Fix: new module-level `_active_customization_backend_id` set in `_setup_illusions` from `item.backend_id`, cleared on `HeroWindowItemCustomization.on_exit`. `BackendUtils.get_item_units` and the `LootItemUnitPreviewer.spawn_units` LA-paint call both fall back to it when `effective_backend_id == nil`. Row-1 cycling now leaves the shield mesh AND LA paint frozen on the row-2 selection. Row-2 click + row-1 cycle interaction still works in both directions.

## [2026-05-16 v0.8.54-dev]
### Per-character cross-pool: all LA shields on all of that character's shield weapons
- New `_LA_CHARACTER_SHIELD_TYPES` table in `_la_bridge.lua`. Every LA shield variant whose `la_key` starts with a character prefix is now automatically merged into every shield-bearing item_type for that character.
  - **Kruber:** every Kruber LA shield (Bret natives — Bastonne/Reynard/Luidhard/Lothar/Alberic; Empire natives — Ostermark/Kotbs hero1 + 6 new kind=unit Empire shields = Reiland/Ostermark01-on-basic1/basic2/Kotbs01-on-basic2/Middenheim-on-basic2/Middenheim01-on-basic3) appears on all 4 Kruber shield item_types: `es_1h_sword_shield`, `es_1h_mace_shield`, `es_1h_sword_shield_breton`, `es_deus_01`.
  - **Bardin:** both Bardin LA shields (basicClean + heroClean KarakNorn) appear on both `dr_1h_axe_shield` and `dr_1h_hammer_shield`.
  - **Kerillian:** no change (only one shield item_type, `we_1h_spears_shield` — all 13 Kerillian LA shields already pool there).
  - **Saltzpyre:** no LA shields exist; entries reserved for forward compat.
- `_LA_EXTRA_WEAPON_TYPES` retained but now empty — the 3 Bret-extra entries (Ostermark/Kotbs/Reiland) are subsumed by the character rule. Table kept available for one-off non-shield cross-pollination if needed later.
- Same-character invariant from v0.8.52 preserved: rule only expands WITHIN a character's family, never across characters.

## [2026-05-16 v0.8.53-dev]
### Open the LA focus gate — show every LA shield
- Replaced the 3-entry `_LA_FOCUS_KEYS` whitelist (`Ostermark01`, `Kotbs01`, `Kruber_empire_shield_basic1`) with an empty table. The "one shield at a time" testing policy from early development was silently hiding every other LA shield from the picker even though registration was complete. With the gate open, every LA variant whose `icons` table targets the current weapon type now appears, still scoped to the wielding character per the v0.8.52 same-character rule (LA's icons are already character-correct).
- Expected visible counts per weapon: Bret sword+shield now ~8 LA (5 Bret-native + 3 Empire extras), Empire mace+shield / sword+shield ~6 LA, Kerillian spear+shield ~14 LA, Bardin axe+shield / hammer+shield ~2 LA. Crash risk on click is acknowledged for unverified `kind="unit"` variants — see TODO and v0.8.51 entry's W1 note.

## [2026-05-16 v0.8.52-dev]
### Same-character-only shield pools (cross-character pollution removed)
- Per user direction: a weapon's offhand-shield picker now strictly only offers shields from the wielding character's asset family. Kruber weapons share Kruber's 12 shields (Empire 01-05, GK 01-05, Deus 02/03). Kerillian gets only the 2 elven shields. Bardin gets only the 8 dwarf shields. Saltzpyre gets only the 3 WP shield variants. Previously `we_1h_spears_shield` exposed Empire shields, `dr_1h_axe_shield` exposed Empire+Elven+WP, `wh_flail_shield` exposed Empire+GK+Elven+Dwarf, and `es_1h_sword_shield` had a stray WP entry.
- LA shields remain merged in per LA's `icons` table targeting — that's already character-correct so no change needed there.
- Pool size impact: Kerillian dropped from ~7 to 2, Bardin dropped from ~12 to 8, Saltzpyre dropped from ~9 to 3. Kruber dropped by 1 (WP removed).

## [2026-05-16 v0.8.51-dev]
### Public-alpha prep, part 1
- **Stripped TEMP DIAGNOSTIC `[SPAWN_TRACE]` block** at the top of `cosmetics_tweaker.lua` (the `World.spawn_unit` / `World.spawn_unit_with_position` hooks + `/spawn_trace_reset` command). Diagnostic served its purpose during the Imperial-hero crash investigation; the workaround in `_la_bridge._resolve_intended_unit` (returns `nil` for crash-prone variants) covers the Imperial Hero shield issue for now, and the spawn-trace data we gathered is recorded in TODO. Removes 36 lines of unconditional per-frame logging.
- **Marked `unlock_all_frames` toggle resolved in TODO** — user confirmed in-game on v0.7.100-dev (frames inject after restart with toggle on, all 239 frames appear in cosmetics inventory).

### W1 (LA shields) — full kind="unit" coverage extracted from LA source `.unit` files
- Extended `_LA_KIND_UNIT_TEXTURES` from 1 entry (Reiland only) to **20 entries** covering every `kind="unit"` LA shield variant:
  - 6 Empire (Kruber): `_basic1` (Reiland), `_basic1_Ostermark01`, `_basic2`, `_basic2_Kotbs01`, `_basic2_Middenheim`, `_basic3_Middenheim01`
  - 2 Bardin (Dwarf): `_basicClean_KarakNorn01`, `_heroClean_KarakNorn01`
  - 12 Kerillian (Elf): `_basic_Avelorn01_mesh`, `_basic2_mesh`, 5× `_heroClean_*` (Saphery01, Caledor01, Avelorn02, Eataine01, Chrace01), 5× `_basicClean*` (basicClean, Eaglegate01, Saphery01, Caledor01, Chrace01)
- Extended `M.la_kind_unit_parent_packages` to the same 20 entries — all share `mat_to_use = wpn_empire_handgun_02_t2` (LA consistently uses the handgun material as the parent across the whole custom-mesh family).
- **Extraction methodology:** every variant's diff/norm/pack paths sourced verbatim from `C:\Users\danjo\source\repos\Loremasters-Armoury\units\<dir>\<key>.unit`'s `data.colors / .normals / .MABs` fields. Two case-sensitive trap entries documented: `Kerillian_elf_shield_basic2_Eaglegate01`'s texture directory is `EagleGate01` with capital G while the diffuse filename uses lowercase g; `Kerillian_elf_shield_basic_Avelorn01_mesh`'s diff filename ends in `_diffuse1` (trailing 1).
- **Kerillian limitation (acknowledged for alpha):** Kerillian shields have TWO `mat_slots` in vanilla LA (`slot1=handle, slot2=shield`); the current `Unit.set_texture_for_materials` painter writes uniformly across all materials on the unit, so we use slot2's textures (the shield face — the primary visual). The handle face will render with the same texture and will look imperfect on close inspection. A per-material painter is a post-alpha improvement.
- The customization-preview-only `Unit.set_all_materials` swap + `Unit.set_local_scale` from v0.8.46-v0.8.49 now applies to every entry above. In-game and inventory-mannequin contexts continue to early-return per v0.8.48 (LA's own hook handles those paths correctly).

### W2 (offhand picker) — extended coverage to dual-wield weapons
- Independent offhand picker now appears on the customization screen for dual-wield weapons in addition to shield weapons. Eight new item_types covered:
  - `dr_dual_axes` (Bardin Slayer dual axes)
  - `dr_dual_wield_hammers` (Bardin dual hammers)
  - `ww_dual_daggers` + `we_dual_wield_daggers` aliased pool (Kerillian Shade dual daggers — both the ww_* canonical adventure item_type and the 2024-Q2 cosmetic-pack we_* item_type point to the same pool)
  - `ww_dual_swords` (Kerillian dual swords)
  - `ww_sword_and_dagger` (Kerillian sword+dagger)
  - `es_dual_wield_hammer_sword` (Kruber Foot Knight bret hammer+sword)
  - `wh_dual_hammer` (Saltzpyre dual hammers)
  - `wh_dual_wield_axe_falchion` (Saltzpyre dual axe+falchion)
- **Implementation:** new local `_build_offhand_options_from_skin_table(skin_table_name)` derives the pool dynamically by walking `WeaponSkins.skin_combinations[<table>]` over all rarity buckets, looking up each referenced skin in `WeaponSkins.skins`, and collecting the unique `right_hand_unit` paths. Right-hand and left-hand units are the same for matched-pair dual wields, so the set works as left-hand candidates. Auto-includes vanilla, DLC, and any future skin additions — unlike the hand-curated shield pools (which were necessary because shields cross-pollinate across weapon types).
- Rendering, package preload, and `_offhand_selection[backend_id]` machinery are unchanged from the shield path — dual-wield options have only `unit` (no `intended_unit` since they're not LA bridge entries), so they flow through the same `BackendUtils.get_item_units` override hook + `_preload_offhand_for_option` preload that shield options use.
- Sort order within each pool: plentiful → common → rare → exotic → unique → bogenhafen → promotion → unknown, so picker order is predictable launch-to-launch.

## [2026-05-13 v0.8.50-dev]
### Coexist with crafting_in_modded (cim): yield illusion-swap to cim when it's loaded

cim now ships its own copy of the modded-realm illusion-swap pipeline. When both mods are installed cim is authoritative — cosmetics_tweaker's six illusion-swap hooks now check `get_mod("cim")` at fire time and early-return to the original function, leaving cim's hooks to handle the customization. Hooks gated:

- `BackendInterfaceItemPlayfab.get_weapon_skin_from_skin_key` — `_custom_skin_keys` path still runs (LA bridge + our recolored skins) so those keep working; only the eac-untrusted vanilla-skin path is delegated to cim.
- `HeroWindowItemCustomization._enable_craft_button`
- `HeroWindowItemCustomization._on_illusion_index_pressed`
- `HeroWindowItemCustomization._update_state_craft_button`
- `BackendInterfaceCraftingPlayfab.craft`
- `BackendInterfaceCraftingPlayfab.update`

No behavior change when cim isn't loaded. The offhand-shield picker, custom-illusion registry, and veteran-skin glow overrides are unaffected — they remain cosmetics_tweaker-only features.

## [2026-05-12 v0.8.49-dev]
### Polish
- **Preview-only 2x scale for `kind="unit"` LA shields.** Custom-mesh LA shields render visibly smaller than vanilla shield illusions in the LootItemUnitPreviewer's intrinsic zoom. Adds `Unit.set_local_scale(unit, 0, Vector3(2, 2, 2))` in the same context-gated block as the v0.8.48 material swap — runs ONLY for `context == "loot_previewer"`, leaves in-game and inventory-mannequin rendering untouched.
- New tables in `_la_bridge.lua`:
  - `M.la_kind_unit_preview_scale_default = 2.0` — base multiplier when no override exists.
  - `M.la_kind_unit_preview_scale = {}` — per-`armoury_key` override map. Empty by default; add `Kruber_empire_shield_basic1 = 1.5` (or similar) only if a future shield needs a different preview size.
- The scale lives in the customization-preview unit's own world, so it doesn't follow the equipped item anywhere else; the apply-and-equip path uses the in-game world's unit, which is never scaled by this code.

## [2026-05-12 v0.8.48-dev]
### Fixed (v0.8.47 regression — massive in-game shield)
- v0.8.47 added `Unit.set_all_materials(unit, handgun_path)` to `_paint_offhand_textures_locally` for `kind="unit"` variants. This **fixed** the customization preview (Reiland renders with textures, mesh just smaller because of the previewer's intrinsic zoom). It also **broke** the in-game render — Reiland appears massive on both 1P and 3P views. Root cause: the function is called from THREE rendering paths via `_apply_la_offhand_to_units`:
  - `GearUtils.create_equipment` hook (in-game / mission body)
  - `HeroPreviewer/MenuWorldPreviewer` hook (inventory mannequin)
  - `LootItemUnitPreviewer.spawn_units` hook (customization preview)
- The in-game and inventory paths already had the LA mesh bound to the correct material (LA's own hook does this for the inventory mannequin; in-game has correct world-scope resolution). v0.8.47 ran the swap in all three, overwriting the correct binding with the handgun's material, which carries different renderable metadata → massive scale in-game.
- The inventory mannequin still rendered normally because LA's `HeroPreviewer._spawn_item_unit` hook fires after ours and re-applies the correct binding, masking our damage.
- **Fix:** threaded a `context` arg through `_apply_la_offhand_to_units` → `LA_BRIDGE.apply_offhand_to_unit` → `_paint_offhand_textures_locally`. Three call sites tagged: `"ingame"`, `"hero_previewer"`, `"loot_previewer"`. The `kind="unit"` material swap + paint now ONLY runs when `context == "loot_previewer"`. For `"ingame"` and `"hero_previewer"`, we early-return (the v0.8.46 safe behavior — vanilla rendering path handles those correctly).

### What this leaves us with
- In-game: LA mesh renders correctly (v0.8.46 behavior restored — no swap).
- Inventory mannequin: LA mesh renders correctly (LA's own hook handles paint).
- Customization preview: LA mesh renders with textures via the v0.8.47 swap+paint mechanism.
- Future `kind="unit"` LA shields: just add an entry to `M.la_kind_unit_parent_packages[armoury_key]` pointing to whichever vanilla material the LA `.unit`'s `mat_to_use` directive references.

## [2026-05-12 v0.8.47-dev]
### Experimental (material swap via `Unit.set_all_materials`)
- v0.8.46 API surface dump revealed `Unit.set_all_materials`, `Unit.set_material`, `Unit.set_material_from_id`, `Unit.get_material_resource_id`, and confirmed `Material.set_texture` (signature `Unit.set_material(unit, slot_name, material_path)` from vanilla `keep_decoration_painting_extension.lua:397` and `world_hero_previewer.lua:179`).
- User's idea: "Since it loads correctly elsewhere, perhaps there's a way to put one of the elsewhere models into the cosmetic menu in place of whatever we're currently doing." Implemented as a per-unit material swap: don't move the LA mesh to a different world, swap the LA mesh's *broken material binding* with the *vanilla material* it was compiled against.
- **Change in `_paint_offhand_textures_locally`:** when `variant.kind == "unit"`, BEFORE running the texture-paint, call `Unit.set_all_materials(unit, parent_path)` where `parent_path = M.la_kind_unit_parent_packages[armoury_key]` (the vanilla material from the LA `.unit`'s `mat_to_use` directive — already package-preloaded since v0.8.39). Forces an explicit binding instead of relying on implicit resolution that's caching null.
- **Removed the v0.8.38 `return false` skip** for `kind="unit"`. Paint now runs after the material swap. If the swap succeeded, the handgun material has the `texture_map_c0ba2942 / 59cd86b9 / 0205ba86` slot vocabulary (LA was designed against this material), so the existing `Unit.set_texture_for_materials` calls bind LA's diff/pack/norm textures onto real slots and Reiland renders with textures in the customization preview.
- Probe (v0.8.45) STILL runs after the swap so the log shows whether `material[0]` flipped from `#ID[00000000]` to a real binding.

### Pass/fail signal
- **Pass:** customization preview shows Reiland with textures. Log shows `set_all_materials ok=true` and `material[0]` is no longer `#ID[00000000]`.
- **AV returns:** the material was swapped (or attempted) but `set_texture_for_materials` still AVed. Means the handgun material loaded into the previewer's world also has a degraded binding — chase that path or accept the limitation.
- **No crash, no texture:** the swap silently no-op'd (set_all_materials returned ok but didn't actually bind). Log will show this — next step would be `Unit.set_material(unit, "slot1", path)` with a guessed slot name.

## [2026-05-11 v0.8.46-dev]
### Diagnostic (enumerate engine API surface for Unit/Mesh/Material)
- v0.8.45 confirmed Reiland's spawned mesh has `material[0] = #ID[00000000]` (null) in the customization preview — and that v0.8.39's parent-package preload IS firing 2ms before the probe but does NOT make the material resident. So the next move is to swap the null material via `Mesh.set_material` (or whichever primitive exists) using a known-loaded vanilla material as the donor.
- But: we don't know which mutation APIs exist in this engine build. The v0.8.45 probe revealed `Unit.num_nodes` and `Unit.is_visible` are absent — those Stingray method tables are version-specific.
- New `_dump_api_surface()` helper in `_la_bridge.lua` iterates the global `Unit`, `Mesh`, and `Material` tables via `pcall`'d `pairs()` and logs every method name + value type, chunked 6-per-line. Runs once per process (`_LA_PROBE_API_DUMPED` flag), called from the start of `_probe_la_unit_materials`.

### What we're looking for in the next log
- Whether `Mesh.set_material` exists (or `Unit.set_material` / `Unit.set_material_for_mesh` / similar).
- Whether `Material.set_texture` is in the table (we use it already in `_la_bridge.lua:713`, so it should be — but the dump will confirm and may reveal alternate names like `set_texture_for_variable`).
- Whether `Material.has_variable` / `Material.variable_count` exist (the v0.8.45 probe assumed they did, found neither logs anything; the dump confirms whether they're absent or whether the call signature was wrong).
- Any non-obvious primitives we haven't considered (e.g., `Unit.set_material`, `Renderable.*`, etc.).

## [2026-05-11 v0.8.45-dev]
### Diagnostic (probe LA bundled-mesh material state in customization preview)
- Added `_probe_la_unit_materials(unit, armoury_key)` in `_la_bridge.lua`. Walks the spawned LA unit and logs (all pcall-wrapped):
  - `Unit.alive`, `Unit.num_actors`, `Unit.num_nodes`, `Unit.is_visible`
  - `Unit.num_meshes` and for each mesh: `Unit.mesh_name`, `Mesh.num_materials`
  - For each material: `Material.has_variable(slot)` and `Material.get_texture(slot)` for the three SHIELD slot hashes (diff/pack/norm).
- Wired into `_paint_offhand_textures_locally` at the `variant.kind == "unit"` branch BEFORE the early return. Probe runs every time the painter is called for a `kind="unit"` variant, paint remains disabled (no AV).
- Per `cosmetics_tweaker.lua:435-438` memo, the probe avoids `Material.num_parameters / parameter_name / parameter_type` — those raise a Stingray `resource_manager.cpp` fault that pcall doesn't catch.

### What we're looking for
1. **`num_meshes == 0` or err** → the LA mesh isn't actually loaded into the previewer's world. The fix path is whatever LA does in `swap_units_new` to alias the mesh into the world's reference graph.
2. **`num_meshes > 0` but `Mesh.num_materials == 0`** → mesh loaded, materials not instantiated. Same fix path roughly.
3. **`num_materials > 0` but `has_variable(slot)` returns false** → the material exists but the slot variable names we're using don't match the compiled material. We'd need different slot hashes (or to call `Material.set_texture` with the slot names from the mesh's own material file rather than the LA `.unit`'s nominal slot hashes).
4. **`has_variable(slot)` returns true, `get_texture(slot)` returns a default or empty** → material is fully bound but `Unit.set_texture_for_materials` is faulting for a different reason (binding lifecycle, per-material write protection, etc.).

Each outcome points to a different fix. No code change to in-game / inventory paths; this is preview-only diagnostic.

## [2026-05-11 v0.8.44-dev]
### Reverted (v0.8.43 hypothesis falsified)
- v0.8.43 re-enabled `kind="unit"` painting on the assumption that v0.8.39's parent-package preload (`wpn_empire_handgun_02_t2`) would make `Unit.set_texture_for_materials` safe on Reiland's bundled mesh. **Result:** same AV at address 0x8 (GUID 45a2a017-3fb2-419e-aa20-e6f7ea0d3535). Identical crash signature to v0.8.34 (GUID a739e6e5).
- **What this rules out:** the AV is NOT the LA mesh's compiled material trying to resolve a missing shader graph. The parent package WAS loaded (v0.8.40 confirmed the preload mechanism fires correctly), and the crash signature is identical. The 0x8 dereference is something else — most likely the LA mesh's per-material instance isn't bound in the customization preview's specific render world. Stingray materials are per-world resources; globally-loading a unit package does not automatically scope its materials into every world's reference graph. `LootItemUnitPreviewer` runs its own world.
- **Restored:** v0.8.38 skip in `_paint_offhand_textures_locally` for `variant.kind == "unit"`. Reiland (and future `kind="unit"` shields) preview as mesh-only-no-texture but DON'T crash. In-game and inventory mannequin remain unaffected (LA's own HeroPreviewer paint hook handles those).
- **Parent-package preload from v0.8.39 is RETAINED** even though it didn't fix the crash. It may still help with other failure modes; cheap to leave in. If a future investigation removes the need, we can drop it then.

### Investigation path forward (not yet attempted)
1. **Probe the spawned Reiland unit in the LootItemUnitPreviewer's world**: dump `Unit.num_materials(unit)`, iterate slots, log what's actually bound (or unbound) at paint time. This tells us whether the material is instantiated-but-empty, or not instantiated at all.
2. **Mirror LA's `swap_units_new` NetworkLookup aliasing for the customization preview**: LA's own mechanism for getting bundled meshes to render relies on aliasing its mesh paths to vanilla unit indices in `NetworkLookup.inventory_packages` and mutating `WeaponSkins.skins` globally. We skipped that path back in v0.8.31 to avoid the global side effects, but it may be the only way to get the previewer's world to scope the bundled meshes correctly.
3. **Accept the limitation**: document that the customization preview can't render `kind="unit"` LA bundled meshes; in-game and inventory mannequin already work. The cosmetics picker is still functional — user just doesn't get live preview for these specific shields.

## [2026-05-11 v0.8.43-dev]
### Experimental (re-enable `kind="unit"` paint with parent shader loaded)
- v0.8.40 confirmed the v0.8.39 parent-package preload mechanism is wired up correctly (no crash, mesh spawns), but Reiland's customization preview is still untextured — because v0.8.38 disabled `_paint_offhand_textures_locally` for `kind="unit"` variants entirely (safety after the v0.8.34 AV crash).
- **Hypothesis:** the AV at 0x8 was the LA mesh's compiled material trying to bind a shader graph (`mat_to_use = "units/weapons/player/wpn_empire_handgun_02_t2/wpn_empire_handgun_02_t2"`) that wasn't in the previewer's world. With v0.8.39's preload now in place, that parent package IS loaded before paint runs — the material slot pointers should be valid, and `Unit.set_texture_for_materials` should bind without dereferencing nil.
- **Change:** lifted the v0.8.38 `if variant.kind == "unit" then return false end` guard in `_paint_offhand_textures_locally`. Painter now runs for both `kind="texture"` and `kind="unit"` variants. The `_LA_KIND_UNIT_TEXTURES` fallback table (manual extraction from LA's source `.unit` files) supplies the texture paths for variants whose SKIN_LIST entry has no `textures` array.

### Test plan (full restart required)
- Full game restart (hot-reload unsafe for cosmetics_tweaker per CLAUDE.md).
- Equip Kruber Bret longsword+shield → cosmetics menu → row-2 picker → click Reiland.
- **Pass:** preview now shows Reiland's mesh with textures bound. Ostermark/Kotbs still display correctly (unaffected). Apply still works.
- **Fail (AV crash returns):** the parent-package load isn't sufficient — paint timing or some other unresolved material reference is the real issue. Revert this change and consider deferring paint until a package-load callback completes (vs the current sync-load that returns immediately).

## [2026-05-10 v0.8.42-dev]
### Changed
- **Per-character cosmetic-unlock widgets nested under a single "Cosmetic Availability" group.** The auto-generated per-character/career hat/skin toggle tree from `_cosmetic_unlocks.lua` (~1272 individual widgets across the 5 characters) was previously appended at the top level of the settings list, dominating the main settings view. Now wrapped in one collapsible group at the bottom of the widget list. Same data, same checkboxes, just collapsed by default. Added `cosmetic_availability_group` localization entry ("Cosmetic Availability").

## [2026-05-10 v0.8.41-dev]
### Removed
- **"Experimental Tints" settings group and its `tint_pureheart_white` toggle.** The Grail Knight Pureheart Helm white-tint feature didn't visibly work on the hat material (the shader's parameter names don't match any of the candidate names we tried), and the v0.8.32-dev "remove dirt from Purified outfits" TODO outlines the proper Material-Hijack + MoreItemsLibrary asset-pipeline approach for color-changing cosmetics. Cleaned up:
  - `experimental_tints_group` + `tint_pureheart_white` widgets removed from `cosmetics_tweaker_data.lua`
  - `experimental_tints_group` / `tint_pureheart_white` / `tint_pureheart_white_tooltip` localization entries removed
  - `_TINT_PARAM_NAMES`, `_hat_tints` table, `_apply_tint_to_unit`, `_maybe_tint` helpers removed from `cosmetics_tweaker.lua`
  - Call site inside `GearUtils.create_equipment` post-hook removed (the loop that ran `_maybe_tint` on each hand unit, with its outdated "POTENTIAL BUG" comment about preview-path coverage)
  - `/probe_hat` chat command retained — it's still useful for future material introspection work.

## [2026-05-10 v0.8.40-dev]
### Fixed
- **Forward-reference crash from v0.8.39.** `register_all` (line 401) called `_build_la_path_to_parent_package` but the local function was declared at line 561 — Lua's `local function` declarations are scoped at parse time, so the name resolved to nil at call time and the global lookup AVed. Per `feedback_lua_forward_reference.md` this is the recurring forward-ref bug class (now 6 incidents — that memory is load-bearing). Fixed by hoisting onto the module table (`M._build_la_path_to_parent_package`) so name resolution is dynamic table-access at call time, decoupled from declaration order. Same defensive pattern we use elsewhere when the call site lives in an earlier function than the declaration.
- Functionally identical to v0.8.39 once the registration runs successfully — same parent-package preload mechanism. Should now actually fire instead of throwing every frame.

## [2026-05-10 v0.8.39-dev]
### Experimental (parent-package preload for `kind="unit"` LA shields)
- v0.8.38 confirmed the v0.8.34 click-Reiland crash was post-spawn texture painting (`Unit.set_texture_for_materials`), not the spawn itself. Paint stays disabled for `kind="unit"` for now.
- New mechanism: when `LootItemUnitPreviewer.load_package` short-circuits for an LA bundled mesh path, ALSO sync-load the LA mesh's parent vanilla package onto the previewer's reference. The parent is the unit specified by `mat_to_use` in LA's source `.unit` (the shader-graph inheritance pointer used at compile time).
- Two new fields in `_la_bridge.lua`:
  - `M.la_kind_unit_parent_packages` — armoury_key → vanilla parent package path. First entry: `Kruber_empire_shield_basic1` → `units/weapons/player/wpn_empire_handgun_02_t2/wpn_empire_handgun_02_t2`.
  - `M.la_path_to_parent_package` — reverse map (LA mesh path 1p / _3p → parent package), built at register-all time so the previewer hook can look up the parent without knowing the armoury_key.
- `_la_parent_pkg_ref_by_previewer` (weak-keyed) tracks per-previewer references already taken so we don't sync-load twice for one previewer.
- Sync load (`async=false`) so the parent is fully bound BEFORE `_spawn_items` runs in the same frame. Wrapped in pcall so a load failure logs but doesn't crash. Vanilla VT2 packages are well-tested so this is much safer than v0.8.27's attempt to sync-load LA's whole main package (which has its own broken references).

### Hypothesis
If Reiland's customization preview now renders WITH textures: the parent vanilla package was the missing piece — the LA mesh's compiled material couldn't bind its inherited shader graph without it. We extend `la_kind_unit_parent_packages` for every kind="unit" shield as we add them.

If textures STILL don't bind: parent-package-load wasn't enough. Either the actual issue is more nuanced (per-world material caching, or LA's compiled material has additional unresolved references) or the load happened too late despite sync. Next step would be re-enabling the kind="unit" paint with the parent loaded — material may now initialize correctly and accept the texture override without crashing.

## [2026-05-09 v0.8.38-dev]
### Experimental
- **Hypothesis: the v0.8.34 click-Reiland AV crash was post-spawn texture painting, not the spawn itself.** Logic: LA's own design only hooks `HeroPreviewer` for its painting queue (inventory mannequin), NOT `LootItemUnitPreviewer` (customization preview). LA relies on `swap_units_new`'s global `WeaponSkins.skins` mutation + NetworkLookup aliasing + the compiled `.unit`'s baked materials for the preview to render. Our path skipped `swap_units_new` to avoid the global side effects, but ALSO added our own per-unit `Unit.set_texture_for_materials` paint via the v0.8.32 `_LA_KIND_UNIT_TEXTURES` map. That paint may be the C++ AV trigger when the bundled mesh's materials aren't fully bound.
- v0.8.38 isolates the test: stamp `backend_id` unconditionally on `preview_item` (revert v0.8.36's conditional skip) so the previewer actually tries to spawn Reiland — but **skip texture painting for kind="unit" variants entirely** (early return in `_paint_offhand_textures_locally`). Mesh may render magenta or with un-bound textures; either is informative.
  - If preview now spawns Reiland's mesh without crashing → painting was the culprit; we look for a different paint timing or primitive.
  - If still crashes → the spawn itself is unsafe in the previewer's world; we revert and pursue a different path (e.g. mirror swap_units_new's NetworkLookup aliasing).
- Ostermark / Kotbs unchanged (kind="texture" + is_vanilla_unit; their paint still runs and they still display correctly).

## [2026-05-09 v0.8.36-dev]
### Fixed (regression from v0.8.34)
- **Clicking Reiland in the row-2 picker no longer C++-AV-crashes the engine.** GUID a739e6e5-0760-4faf-9d4d-266ed64dddc4. Root cause: v0.8.34 unconditionally stamped `backend_id` on `preview_item`, which made our `BackendUtils.get_item_units` hook fire correctly during the customization preview's spawn — for the FIRST TIME for `kind="unit"` LA bundled paths. In-game and inventory mannequin worlds spawn LA bundled meshes fine (broader resource scope, mesh + materials all bind), but `LootItemUnitPreviewer`'s background world can't safely spawn them and the engine null-derefs at C++ level (not Lua-recoverable). Earlier v0.8.32-33 builds didn't crash because the missing `backend_id` made our hook bail in the previewer, so Reiland's mesh was never actually spawned there.
- Conditional fix: stamp `backend_id` ONLY when the click's `override_unit` has a standalone package (`Application.can_get("package", path)` true). LA bundled meshes (engine-resident via LA's main package only, no standalone) skip the stamp. For those options the previewer's hook bail returns to v0.8.32-33 behaviour — preview shows the vanilla skin's native shield instead of the clicked LA mesh.
- Vanilla offhand options and `kind="texture" + is_vanilla_unit` LA options (Ostermark/Kotbs — `intended_unit` IS a vanilla mesh with a standalone package) keep the v0.8.34 preview-update behaviour. Clicking them still updates the customization preview live.
- The override still fires for `kind="unit"` LA shields in-game and on the inventory mannequin; only the customization preview is degraded. User Apply still results in the LA shield correctly equipped.
- Documented limitation: customization preview can't render `kind="unit"` LA bundled meshes. Investigation needed: probably resource-scope binding for LA's textures/materials in the previewer's world. Outside the safe edit window.

## [2026-05-09 v0.8.34-dev]
### Fixed
- **Customization preview now updates when you click a different row-2 shield option.** v0.8.32's per-backend-id keying was correct, but `_ct_on_offhand_pressed` constructed the preview item without `backend_id`, so when `_spawn_item_unit(preview_item, true)` triggered the new previewer, our `BackendUtils.get_item_units` hook got `backend_id=nil` and `item_data.backend_id=nil` (item_data is the IML SKIN entry, not a backend item). Hook bailed → no override → preview rendered the vanilla skin's native shield instead of the clicked option's shield. User observation: "every shield option again looks like the current one." Fix: stamp `self._item_backend_id` onto the preview_item so our hook can resolve the per-backend-id selection set by the click. Vanilla row-1 illusion preview is unaffected — it constructs its own item without backend_id, so our hook still correctly bails for those (showing the illusion's native shield, not the offhand override).

## [2026-05-09 v0.8.32-dev]
### Fixed
- **Cross-weapon leak: `_offhand_selection` re-keyed from `item_type` to `backend_id`.** Each weapon instance now has its own selection slot, so applying Reiland on the Bret weapon no longer surfaces it on a CWV imperial sword+shield (or any other weapon sharing the item_type via clone). All seven touch sites updated:
  - The selection table itself (now keyed by backend_id).
  - `_setup_illusions` auto-select read/write.
  - `_ct_on_offhand_pressed` write on click.
  - `BackendUtils.get_item_units` hook read (uses the existing `effective_backend_id` resolution chain).
  - `_apply_la_offhand_to_units` LA-paint pipeline read (signature extended to accept `backend_id_arg`; falls back to `item_data.backend_id` which vanilla stamps on equipment resync).
  - HeroPreviewer / MenuWorldPreviewer call site (now passes `stored_bid` from a new `_get_equip_backend_id` helper that mirrors the existing `_get_equip_skin` tracking).
  - LootItemUnitPreviewer call site (passes `item.backend_id` directly).
  - `_offhand_selection_backend_id` (the old stale-tracking map) removed — redundant under per-instance keying.
- **Customization preview missing texture for kind="unit" LA shields: explicit per-unit texture binding from a manual extraction of the source `.unit` file.** Investigation:
  1. LA's source `.unit` file (`units/empire_shield/Kruber_Empire_shield01_mesh.unit`) declares textures via `colors / normals / MABs` fields with paths like `textures/Kruber_empire_shield_basic1/Kruber_empire_shield_basic1_diffuse`. These textures live in LA's globally-loaded resource_package.
  2. LA's `utils/hooks.lua:270-295` hooks `PackageManager.load`/`unload`/`has_loaded` and silently swallows any load attempt for its own mesh paths. The customization preview's per-instance package load is therefore a no-op — LA's package is globally loaded but not per-previewer scoped, so the engine's material binding falls back to default (mesh-only no texture).
  3. Reiland's SKIN_LIST entry has NO `textures` array (it's `kind="unit"` and the textures are stored in the source `.unit` file only).
- New `_LA_KIND_UNIT_TEXTURES` table in `_la_bridge.lua` holds the manually-extracted texture paths per LA armoury_key. `_paint_offhand_textures_locally` now accepts `armoury_key` and falls back to this map when the variant's `textures` array is empty. Per-unit `Unit.set_texture_for_materials` (the v0.8.18 primitive) handles the binding regardless of world/scope. First entry: `Kruber_empire_shield_basic1`. As more `kind="unit"` shields are added to the focus gate, each gets one entry in the map (3 lines per shield).

### Test plan (full restart)
- Equip Kruber Bret longsword+shield → cosmetics menu → row-2 picker → Reiland.
- Apply. Expect Reiland mesh + textures correctly in:
  1. Customization preview (the new path — should now work).
  2. Inventory mannequin.
  3. In-game body.
- Equip a DIFFERENT weapon (modded imperial sword+shield, or any other Kruber shield weapon). Expect to NOT see Reiland on that weapon — selection is per-backend-instance now.
- Equip a SECOND Kruber shield weapon and select Ostermark. Both weapons should hold their own selection independently. Pop back to weapon A → still Reiland. Weapon B → still Ostermark.
- Note: in-memory only this round; selections lost on game restart. Disk persistence (via mod settings or backend mirror) is the next architectural round.

## [2026-05-09 v0.8.31-dev]
### Reverted
- **v0.8.30 LA-shield skin injection rolled back.** It registered LA shields as first-class row-1 skins, but applying a row-1 skin swaps the whole weapon visual (left+right bundled together). The user's "cosmetics_tweaker is where the shield and main weapon are changed separately" model rules that out — they want the row-2 offhand picker (independent shield selection) to keep working. Net of the rollback: `_register_all_la_shield_skins()` is commented out and `_merge_la_offhand_options()` is restored in `mod.update`, so LA shields surface in the offhand picker again. The skin-injection code stays in the file for future reference.
- The cross-weapon leak (Reiland appearing on a modded imperial weapon that shares item_type) and the customization-preview missing-texture issue both come back with this revert. They need a different design — most likely per-backend_id selection keying with backend-mirror persistence so the offhand pick is scoped to the specific weapon instance the user applied it to. Tracked as the next architectural round.

## [2026-05-09 v0.8.33-dev]
### Added
- **Advanced glow submenu (per-channel brightness multipliers).** New "Advanced: Per-Channel Brightness" sub-group under the existing Weapon Glow Override settings, exposing 7 numeric multipliers (range 0.0–5.0):
  - **Master Brightness ×** (default 1.0) — scales all channels uniformly
  - **Rune Emissive ×** (default 1.0) — drives themed Veteran (`_runed_02..06`) and Stylish loot-chest (`_runed_01`)
  - **Glow High ×** + **Glow Low ×** (default 1.0) — drive the lower part of the visible gradient on `_magic_*` weapons (per probe v0.8.22)
  - **Smoke High ×** + **Smoke Low ×** (default 1.0) — drive the upper part of the gradient
  - **Dots Particles ×** (default 0.0 / SKIP) — experimental; probe showed `color_dots` darkens Weavebound when high and has unclear effect on Shyish-Infused
- A multiplier of `0.0` SKIPS that channel entirely (no `Unit.set_vector3` call) — leaves whatever vanilla wrote (or doesn't write at all for non-templated meshes). For Shyish-Infused weapons, default `mult_dots = 0` preserves vanilla's color_dots = (8.35, 3.5, 7).
- `color_dots` added to the `_cosmetics_tweaker_glow` injected template so users can experiment with it on Weavebound/Stylish via the multiplier. Inert by default (mult 0).

### Math
- Effective per-channel brightness = `native_magnitude × master_mult × channel_mult`. User RGB is normalized so its max channel hits this effective value, preserving hue and tunable magnitude. Without per-channel scaling, multi-channel templates (versus has 5 channels at very different brightness) over-bloomed when set to a uniform user RGB (v0.8.29 bug).

## [2026-05-09 v0.8.30-dev]
### Architectural change (Phase 1 of LA-shield skin injection — REVERTED in 0.8.31)
- **LA shields now inject as first-class VT2 skins instead of runtime offhand-row-2 overrides.** New `_la_shield_skin_specs` table (above `_register_custom_illusions` in `cosmetics_tweaker.lua`) drives `_register_la_shield_skin(spec)`, which writes a real entry into `ItemMasterList`, `WeaponSkins.skins`, the appropriate `WeaponSkins.skin_combinations` tier, and `NetworkLookup.weapon_skins`. Same pipeline `_register_custom_illusions` already uses for the `ct_*` cross-character illusions — point `left_hand_unit` at LA's authored mesh path while inheriting `right_hand_unit / display_unit / template / can_wield` from the matching vanilla weapon's default skin.
- This eliminates two issues from v0.8.27/v0.8.28 testing:
  1. **Cross-weapon leak.** `_offhand_selection` was keyed by `item_type`; modded CWV variants sharing an `item_type` with a vanilla weapon picked up Reiland on their 3P body in inventory. Vanilla's apply pipeline writes `item.skin = skin_key` onto a specific backend item — application is per-weapon-instance with zero shared state.
  2. **Customization preview missing textures.** The previewer's `_load_item_units` calls `Managers.package:load(unit_path_3p, ...)` with the previewer's reference. For a vanilla skin (which the LA-injected skin now IS) this binds the matching weapon's full asset graph into the previewer's scope. The LA mesh still goes through our v0.8.12 `load_package` short-circuit (no standalone `.package` exists for LA's bundled meshes), but the *right hand* package and other matching-weapon assets DO load via the standard path, which drags in shared materials/shaders LA's compiled `.unit` references at compile time.
- Phase 1 spec: ONE entry — `la_kruber_empire_shield_basic1_breton`, the Reiland mesh registered as a skin for `es_1h_sword_shield_breton`. Validates the architecture across all four spawn paths (in-game body, inventory mannequin, customization preview, illusion browser) before extending to all 4 weapon types and the rest of the LA shield catalogue.
- Row-2 LA bridge merge (`_merge_la_offhand_options`) intentionally not called — leaving it would surface LA shields in two places simultaneously and re-introduce the cross-weapon leak. The vanilla-only row-2 picker (independent left swap with vanilla shields) still works for users who want it.
- The runtime `BackendUtils.get_item_units` override path keyed off `_offhand_selection` is still in place but dormant for LA shields (no LA entries are populated there now). It still serves the vanilla offhand picker.

### Test plan (full restart)
- Equip Kruber Bret longsword+shield → cosmetics menu → row-1 illusion grid should now contain a new entry: `Empire Shield 01 (LA)`.
- Apply it. Expect the LA mesh + textures to render correctly in:
  1. Customization preview itself.
  2. Illusion browser (LootItemUnitPreviewer post-apply).
  3. Inventory mannequin after returning to the inventory tab.
  4. In-game once you start a mission.
- Equip a different weapon (modded imperial sword+shield, or any other Kruber shield weapon). Expect to NOT see Reiland anywhere — the skin is per-weapon-instance, scoped to the specific Bret backend item.
- Tell me what's wrong if anything still goes wrong (preview / mannequin / in-game / cross-weapon).

## [2026-05-09 v0.8.29-dev]
### Changed
- **Glow override redesigned: per-family routing decoupled from color choice.** The user's preset choice now selects an RGB triple; the mod writes that triple to whichever shader variables drive emissive on the target weapon — no separate code paths per family. New design: `_COLOR_PRESETS[preset_key] = { r, g, b }` (just RGB) plus a fixed list of candidate variables (`rune_emissive_color`, `color_glow_high`, `color_glow_low`, `color_smoke_high`, `color_smoke_low`) written on every painted unit. Variables that don't exist on a given mesh silently no-op (verified empirically via `/glow_scan` in v0.8.22).
- **Template-mutation hook now mutates EVERY vector3 variable in the template** to user RGB, not just `rune_emissive_color`. Covers any source-defined template — rune family (single channel), versus (5 channels), and any future template — without per-template knowledge.
- **`color_dots` (versus 5th channel) intentionally omitted** from the direct-paint variable list (probe showed minimal visible color contribution; possibly drives particle behaviour). Template-mutation path still mutates it as part of the versus template — that's fine because the visible contribution is minor.

### Added
- **"White" preset** in the dropdown (key `white_glow`, RGB {10, 10, 10}). Coverage now: White / Purple / Gold / Red / Green / Blue. Underlying preset keys preserved from older builds for save-data compatibility.
- **All four glow families now covered by one color picker** (probe-confirmed in v0.8.22):
  - `_runed_02..06` themed Veteran: rune_emissive_color via template mutation
  - `_runed_01` Stylish loot-chest white-glow (~160 weapons): rune_emissive_color via direct post-spawn paint
  - `_magic_02` Shyish-Infused (Versus rewards): 5 versus channels via template mutation on `versus`
  - `_magic_01` Weavebound (WoM Athanor): 4 versus channels via direct post-spawn paint (no vanilla template — direct write mandatory)
- `/glow_status` now reports the active RGB alongside the preset key.

### Tooltip
- Updated `glow_override_enable` to clarify coverage spans all four glow families through one color picker.

## [2026-05-09 v0.8.22-dev]
### Added
- **Glow probe diagnostic suite** (`/glow_dump`, `/glow_probe <name>`, `/glow_scan`, `/glow_scan_stop`, `/glow_restore`) — finds what shader uniform controls baked emissive on weapon meshes that don't go through the rune-emissive `MaterialSettingsTemplates` system (specifically Stylish `_runed_01` and Weavebound `_magic_01`). The scan sweeps ~63 candidate variable names with bright HDR red on the wielded weapon's units, flashing red on hit. Works because `Material.num_parameters` / `parameter_name` crashes Stingray (resource_manager.cpp:245, NOT pcall-recoverable) so direct enumeration is impossible — brute force is the only viable approach.

### Fixed
- **Vector3 frame-allocation gotcha (v0.8.20 → v0.8.22).** The original probe shipped with `local _GLOW_PROBE_HDR = Vector3(15, 0, 0)` cached at module load. Stingray Vector3 is frame-allocated; the storage is invalidated across frames. Every `pcall(Unit.set_vector3_for_materials, unit, name, cached_vec)` returned `false` because the cached Vector3 was no longer a valid argument. Symptom: scan reported `painted=0` on every candidate × every unit. v0.8.22 changed to `local function _probe_red() return Vector3(15, 0, 0) end` and the probe started actually painting. Same gotcha applies to any Stingray vector type — never cache `Vector3()` results across frames; reconstruct per call site.

### Empirical probe results
- **`_runed_02` (Veteran themed, e.g. purple_glow)**: red glow flash on candidate **#8 = `rune_emissive_color`**. Confirms the existing v0.8.16 template-mutation override pipeline targets the right variable for this family.
- **`_magic_02` (Shyish-Infused, Versus rewards)**: red glow flash on candidates **#50-53** (uniform red across the visible glow); **#54 (`color_dots`) minimal/unclear visible contribution**. Channels 50-53 are 4 of the 5 source-defined `versus` template channels.
- **`_magic_01` (Weavebound, WoM Athanor)** — Bretonnian longsword: SAME 5 versus channels respond, with empirically-mapped roles:
  - **50 `color_glow_high` + 51 `color_glow_low`** → drives the LOWER part of the visible gradient
  - **52 `color_smoke_high` + 53 `color_smoke_low`** → drives the UPPER part of the visible gradient
  - **54 `color_dots`** → went dark / minimal contribution (probably the small particle dots; minor color)
  - **Important consequence:** `_magic_01` mesh materials expose the same uniform names as `_magic_02` even though `_magic_01` has NO source-defined `material_settings_name` — vanilla never paints them, but the variables are there waiting to be written. Earlier I'd assumed Weavebound used a wholly different shader and required asset-level work — wrong; the variables are paintable from Lua, no asset work needed.
- **`_runed_01` (Stylish loot-chest white-glow)**: red glow flash on candidate **#8 = `rune_emissive_color`**. Clearing to (0,0,0) made the glow vanish entirely → the "white" appearance IS that variable set to a white HDR value, NOT a separate baked-in shader effect. Same variable as the themed `_runed_02..06` family. Earlier docs claimed Stylish "has no template-driven glow" — that was wrong. They have NO `material_settings_name` (so vanilla never paints them), but the mesh material exposes `rune_emissive_color` and the mesh's authored white default lives in there from somewhere (mesh asset default, likely). Our `Unit.set_vector3_for_materials` calls override it cleanly.

### Implementation plan derived from probe
With the Stylish probe added, all 4 weapon families are now probe-confirmed paintable. The redesign:

1. **Stop conflating "preset key" with "shader variable to write".** Current design: `_GLOW_PRESETS[preset_key] = { var = rgb }` — the user's preset choice (`purple_glow` / `golden_glow` / etc.) determines BOTH the color AND which variable gets written. New design: `_COLOR_PRESETS[preset_key] = { r, g, b }` (just an RGB) plus a per-weapon-family routing layer that decides which shader variable(s) to write. Lets one user choice drive every family appropriately.

2. **Per-family variable routing** (write the chosen RGB into):
   - **`_runed_02..06` (themed)**: `rune_emissive_color`. Already working via template mutation.
   - **`_runed_01` (Stylish)**: `rune_emissive_color`. Same variable. Vanilla never calls apply_material_settings here, so use the existing post-spawn `_apply_glow_override` path. Verify it's already firing for these — it should be.
   - **`_magic_02` (Shyish-Infused)**: 4 channels (`color_glow_high`, `color_glow_low`, `color_smoke_high`, `color_smoke_low`) — leave `color_dots` alone. Use template mutation on `MaterialSettingsTemplates.versus`.
   - **`_magic_01` (Weavebound)**: SAME 4 channels. No vanilla template — direct post-spawn paint via `_apply_glow_override`, with detection by unit_name suffix.

3. **Detect family per weapon** at paint time. Read the resolved unit_name (already available in `slot_data` and in the create_equipment result) and match the suffix:
   - `_runed_01` → Stylish
   - `_runed_02..06` → themed (template-driven)
   - `_magic_01` → Weavebound (no template, paint directly)
   - `_magic_02` → Shyish (template-driven via versus)
   - other → no glow override applies

4. **UI**: keep the simple 5-color dropdown (Purple / Gold / Red / Green / Blue) — the routing is invisible to the user. One color picker drives every weapon family. Add a "white" preset since loot-chest Stylish weapons are natively white and a no-op preset is meaningful for them. Versus preset doesn't need to come back as a separate user-facing choice — same color picker handles it.

### Open follow-ups
- Verify Stylish post-spawn paint actually fires (the user previously reported it didn't, but probe shows the variable is paintable — gate bug to find).
- Live re-paint (Phase 2 task — wield-event hook).
- Husks (Phase 2 task — peer player_units).
- Per-skin custom RGB picker on customization screen (Phase 2 task).

## [2026-05-09 v0.8.28-dev]
### Reverted
- **`LootItemUnitPreviewer.load_package` hook reverted to plain v0.8.12 short-circuit.** v0.8.26 (async per-previewer reference on LA's main package) didn't fix the texture-less customization preview; v0.8.27 (sync) crashed with `[Engine Error]: Resource '#ID[3ac73385950a26ea]' was not found` (GUID 930aff6f-7e47-4f72-a661-b8222e862fc2). The sync load forced the engine to resolve every resource in LA's package up front and one of them (a Stingray hash, undecodable from Lua) isn't actually in the loaded asset graph — async didn't surface it because the lookup never happened.
- Net state: `kind="unit"` LA shields (Reiland) render mesh+textures correctly **in-game** and on the **inventory mannequin**. The **customization preview** shows the mesh without textures. This is a documented limitation of the current approach; needs a different angle (probably related to the LA compiled `.unit` referencing vanilla material paths that are only in scope when the matching vanilla weapon is loaded). Reiland stays in the focus gate so in-game usage continues to work.

## [2026-05-09 v0.8.27-dev]
### Changed
- **`LootItemUnitPreviewer.load_package` hook re-ordered: per-previewer reference on LA's main package taken BEFORE flipping the gate, sync (`async=false`).** v0.8.26 took the reference async and flipped the gate first, so `_spawn_items` could race ahead of the package-scope binding and the unit rendered without textures (user confirmed v0.8.26 fix didn't help). Sync blocks until LA's package is fully bound to the previewer's reference scope before the gate opens. Added `[LA preview-load]` diagnostic gated on `mod:get("la_preview_trace")` so we can see in the log which path the hook took if textures still don't bind. If this still doesn't fix it, the issue is elsewhere (likely the LA compiled `.unit` references vanilla material paths that aren't in scope when only the shield is being previewed) and needs a different approach.

## [2026-05-09 v0.8.26-dev] (superseded by 0.8.27)
### Fixed (didn't actually fix)
- **`kind="unit"` LA shield now textures correctly in customization preview.** v0.8.25 wired up Reiland and it rendered correctly in-game and on the inventory mannequin, but the customization/illusion menu preview spawned the mesh without textures (just the bare mesh). Root cause: our `LootItemUnitPreviewer.load_package` short-circuit (added v0.8.12 for "no model at all" fix) flipped the loaded-flag and let the spawn proceed against LA's globally-loaded resource package — which works for the in-game body and the inventory mannequin (different worlds with broader resource scope) but doesn't bind LA's materials/textures into the previewer's per-instance resource scope. Fix: when the short-circuit fires for an LA-bundled path, ALSO call `Managers.package:load(_LA_MAIN_PACKAGE, "LootItemUnitPreviewer<id>", nil, true)` to take a per-previewer reference. Tracked per-previewer in a weak-keyed map so we only register once per previewer instance. The package is already globally loaded by VMF, so this is a refcount bump that ties LA's assets to the previewer's lifetime — the engine then binds materials properly when the unit spawns.

## [2026-05-09 v0.8.25-dev]
### Added
- **First `kind="unit"` LA custom-mesh shield: `Kruber_empire_shield_basic1` (Empire shield 01 / Reiland-style).** New architectural class — LA's own authored mesh, not a recolor of a vanilla shield. Three pieces wired in `_la_bridge.lua`:
  1. `_is_supported_variant` now accepts `kind="unit"` if both halves of `variant.new_units` pass `Application.can_get("unit", path)` (engine-resident check). Anything the engine can't actually spawn still skips silently.
  2. `_register_la_path_in_network_lookup(path)` adds bidirectional entries (`string→idx, idx→string`) to `NetworkLookup.inventory_packages` via `rawset`, bypassing the strict `__index` that crashed the older integration attempts (GUID 60180105). Called for both `new_units[1]` (1p) and `new_units[2]` (_3p) of every kind="unit" variant during `build_offhand_options`. Idempotent.
  3. `_LA_EXTRA_WEAPON_TYPES` and `_LA_FOCUS_KEYS` extended to include `Kruber_empire_shield_basic1` (Bret extra + focus). Icons table covers sword/mace/deus already.
- We don't call any LA helpers in this path. `BackendUtils.get_item_units` returns the LA mesh path; the previewer's package-load short-circuit (v0.8.12) flips the loaded-flag immediately because LA's mesh is engine-resident; the texture binds from the compiled `.unit`'s embedded material slots (Reiland has no `textures` array, so the per-unit paint pass is a no-op).

### Test plan (full restart)
- Equip Kruber Bret longsword+shield → cosmetics → expect Ostermark01, Kotbs01, AND `Empire Shield Basic1 (LA)` (or however it humanizes).
- Same for sword+shield, mace+shield, deus spear+shield.
- Apply Reiland → expect a different shield SHAPE (Empire shield 01 mesh, not deus shield) with its embedded materials. No magenta. No leak onto adjacent shields in the inventory mannequin.
- `/la_offhand_dump` after a full equip: Reiland line should show `1p=true 3p=true` (engine-resident).
- If a sync-time crash hits in MP, capture the GUID + missing-key message and we'll add the relevant rawset for whichever NetworkLookup table it points to.

## [2026-05-08 v0.8.24-dev]
### Added
- **Kotbs01 added to focus gate.** `_LA_FOCUS_KEYS` now `{ Ostermark01 = true, Kotbs01 = true }`. Same architecture as Ostermark (kind="texture", is_vanilla_unit=true, intended_unit=`wpn_es_deus_shield_03`); appears on Kruber's sword+shield, mace+shield, deus spear+shield (icon-driven) and Bret longsword+shield (via the v0.8.21 `_LA_EXTRA_WEAPON_TYPES` extras + v0.8.22 alias). No new routing, just visibility.

### Test plan
- Restart VT2.
- For each of Kruber's 4 shield weapons (sword+shield, mace+shield, Bret longsword+shield, deus spear+shield): cosmetics menu → expect Ostermark01 AND Kotbs01 both visible. Apply each → expect deus shield mesh + their respective heraldry texture, no magenta, no leak.

## [2026-05-08 v0.8.23-dev]
### Changed
- **Focus gate at picker-display time.** Per the "one shield at a time" working policy: registration data (icon parsing, `_LA_EXTRA_WEAPON_TYPES`, `_LA_WEAPON_TYPE_ALIAS`) stays intact for every LA shield, but `_merge_la_offhand_options` only surfaces shields whose `armoury_key` is in `_LA_FOCUS_KEYS`. Currently set to `{ Kruber_empire_shield_hero1_Ostermark01 = true }`. Widening to the next focus shield (or removing the gate entirely once all are verified) is a one-line edit at the top of `_merge_la_offhand_options` in `cosmetics_tweaker.lua`. Set to nil/empty table to surface every LA shield.
- This intentionally preserves all the v0.8.19/v0.8.21/v0.8.22 fanout fixes (icon-driven, item_type alias, manual extras) — those are background plumbing that needs to be correct so that flipping the focus gate exposes a working picker. The gate just controls *visibility*, not the underlying routing.

### Test plan
- Restart VT2.
- Equip Kruber Bret longsword+shield → cosmetics menu → expect ONLY `Empire Shield Hero1 Ostermark01 (LA)` in the LA section. Nothing else from the LA bridge.
- Equip Kruber mace+shield → same: only Ostermark01 from LA. (Vanilla offhands are unaffected.)
- Apply Ostermark01 on Bret → expect the deus shield mesh + Ostermark texture combo, identical to mace+shield.

## [2026-05-08 v0.8.22-dev]
### Fixed
- **Bret-weapon LA shields were silently invisible.** Dump showed `es_sword_shield_breton offhand pool: 7 entries`, but the in-game log showed `[LA paint] skip: no _offhand_selection for es_1h_sword_shield_breton`. Naming gap: LA's icon keys use `es_sword_shield_breton_skin_*` (no `_1h_` infix) but the game's actual `ItemMasterList[item].item_type` for the Bret weapon is `es_1h_sword_shield_breton`. v0.8.19's icon-driven fanout bucketed every Bret LA shield (Bastonne, Reynard, Luidhard, Lothar, Alberic, plus the v0.8.21 Ostermark/Kotbs extras) into a pool the game never queried. The picker showed only vanilla Bret shield options because the LA pool was unreachable.
- Added `_LA_WEAPON_TYPE_ALIAS` in `_la_bridge.lua` to translate LA's icon-derived weapon_type to the game's item_type. Currently one entry: `es_sword_shield_breton -> es_1h_sword_shield_breton`. Applied via `_normalize_weapon_type()` in both the icon-driven fanout AND the `_LA_EXTRA_WEAPON_TYPES` map (which I already updated to use the canonical game item_type, but the alias is the safety net so future entries can use either form).
- Re-running `/la_offhand_dump` after this build should show `es_1h_sword_shield_breton` (with `_1h_`) as the pool key, with all 7 entries (5 Bret-authored + Ostermark + Kotbs).

### Test plan
- Restart VT2 fully.
- Equip Kruber Bret longsword+shield → cosmetics menu → expect to see all 7 LA shields in the picker now: Bastonne02, Reynard01, Luidhard01, Lothar01, Alberic01, Ostermark01, Kotbs01.
- Apply Bastonne02 / Reynard01 / etc. (pure-paint Bret shields) → expect Bret shield silhouette + Bret-authored heraldry texture.
- Apply Ostermark01 / Kotbs01 → expect deus shield mesh + Empire heraldry texture (same combo as on mace+shield).
- If something is still wrong, name the exact LA shield + skin combo and what you see.

## [2026-05-08 v0.8.21-dev]
### Added
- **`_LA_EXTRA_WEAPON_TYPES` map (`_la_bridge.lua`)** for opting individual LA shields into weapon types that aren't in their `icons` table. v0.8.19's icon-driven fanout was correct as a default but excluded Ostermark from Bret longsword+shield, which the user explicitly wants — they want the LA combo (deus shield mesh + Ostermark texture) on the Bret weapon, the same combo as on mace+shield. The map is a per-variant additive override.
- Initial entries:
  - `Kruber_empire_shield_hero1_Ostermark01 = { es_sword_shield_breton = true }`
  - `Kruber_empire_shield_hero1_Kotbs01     = { es_sword_shield_breton = true }`
- These two LA shields will now also appear on Bret longsword+shield. Their `intended_unit = wpn_es_deus_shield_03` triggers the BackendUtils.get_item_units mesh-override path so the deus shield mesh is rendered (matching the texture's UVs) instead of the Bret shield mesh. The texture binds via the v0.8.18 per-unit `Unit.set_texture_for_materials` path so there's no shared-material leak onto adjacent shields.
- Adding more LA shields to other weapon types is one entry per shield in this map, on a one-shield-at-a-time basis as we walk the catalogue and decide what should appear where.

### Test plan (this build, on a fresh game restart)
- Restart VT2 to clear any shared-material residue.
- Equip Kruber's Bret longsword+shield → cosmetics menu → expect Ostermark01 and Kotbs01 in the LA section alongside the Bret-authored variants (Bastonne02, Reynard01, Luidhard01, Lothar01, Alberic01).
- Apply Ostermark01 → expect deus shield mesh + Ostermark texture, no magenta, no leak onto adjacent shields. Same combo as on mace+shield.
- Run `/la_offhand_dump` and confirm `Kruber_empire_shield_hero1_Ostermark01` lists `es_sword_shield_breton` in its weapons column alongside `es_1h_mace_shield`, `es_1h_sword_shield`, `es_deus_01`.

## [2026-05-08 v0.8.19-dev]
### Changed (architectural)
- **No more whitelist. No more per-character LA fan-out. LA shields appear ONLY on the weapon types LA's own `icons` table actually authored them for.** This was the structural mistake under the "Ostermark wraps wrong on Bret" report. The previous fan-out (`_la_character_weapon_pools`) gave Kruber's whole LA pool to every shield-bearing weapon Kruber has, which painted Empire-shield textures (UVs authored for `wpn_es_deus_shield_03`) onto Bret shield UVs and produced the wrong-wrap.
- New flow in `_la_bridge.lua`:
  - For each LA SKIN_LIST entry with `swap_hand="left_hand_unit"`, parse its `icons` table. Each icon key is a vanilla skin key of form `<weapon_type>_skin_<...>` (e.g. `es_1h_mace_shield_skin_03`, `es_sword_shield_breton_skin_01`). The prefix before `_skin_` is the weapon type LA targeted.
  - The variant joins `M.la_offhand_options_by_weapon_type[wt]` for each weapon type in its icons table — and only those.
  - LA SKIN_LIST entries WITHOUT an `icons` table are skipped (no authoring metadata to drive routing).
- New flow in `cosmetics_tweaker.lua`:
  - `_la_character_weapon_pools` and the `_LA_KEY_WHITELIST` are gone.
  - `_offhand_options.es_1h_mace_shield`, `es_1h_sword_shield_breton`, `es_deus_01`, `dr_1h_hammer_shield`, `wh_hammer_shield` are now SHALLOW COPIES of their alias targets, not the same table reference. LA fan-out can append per-weapon-type without bleeding across.
  - `_merge_la_offhand_options` reads `LA_BRIDGE.la_offhand_options_by_weapon_type[weapon_key]` directly. No character-level indirection, no `seen_lists` dedupe.
  - The Bret-mesh guard in `BackendUtils.get_item_units` is removed. It was a bandaid for the cross-pollination that this build prevents at the source: LA Empire shields (Ostermark, Kotbs) won't appear on Bret weapons at all, so we never need to drop their `intended_unit` override.
- The v0.8.18 per-unit `Unit.set_texture_for_materials` paint primitive stays in place — it kills the shared-material leak class.
- `/la_offhand_dump` now prints each variant's `weapon_types` list so you can verify which weapon types each LA shield will surface in.
- `kind="unit"` LA variants remain filtered (separate problem; needs LA `swap_units_new` integration with `rawget`/`rawset` accessors per `feedback_la_custom_mesh_unsupported.md`).

### Test plan (this build, on a fresh game restart)
- Restart VT2 to clear shared-material residue from earlier sessions.
- Kruber mace+shield → expect Ostermark01, Kotbs01, and other Empire LA shields whose `icons` include `es_1h_mace_shield_skin_*`. The deus-shield mesh is correct.
- Kruber Bret longsword+shield → expect Bastonne02, Reynard01, Luidhard01, Lothar01, Alberic01 (Bret-authored pure-paint variants). Bret silhouette stays, Bret-authored UVs.
- Kruber sword+shield → Empire LA pool again (Ostermark, Kotbs, etc.).
- Pick an LA option on weapon A → in-game shield only changes on weapon A. Adjacent shields in inventory should not magenta or wrong-texture. Pick Default → re-equip yields a clean vanilla shield.
- If something is still wrong, name the exact weapon type + LA shield + skin combo so we can pinpoint.

## [2026-05-08 v0.8.18-dev]
### Fixed (root cause)
- **Switched LA shield paint from shared-material `Material.set_texture` to per-unit `Unit.set_texture_for_materials`.** This was the architectural mistake underlying every "magenta-on-default" / "wrong texture on a different shield" report since LA bridge integration began. The old path called `Material.set_texture(mat, slot, path)` against materials returned by `Mesh.material(unit_mesh, j)` — those materials are the SHARED material instances baked into the vanilla shield's compiled bundle, so painting one shield's LA texture actually rebound the slot for every unit referencing that material (other shield illusions, the inventory mannequin, the customization preview). One click leaked across the entire UI, and once an LA texture was unloaded (or any package reload occurred) every leaked binding flipped to the engine's missing-asset magenta. The fix uses the same primitive vanilla VT2 uses everywhere it does per-cosmetic texture binding (`gear_utils.lua:150`, `cosmetic_utils.lua:72`, `flow_callbacks_foundation.lua:939`, `outline_system.lua:666`): `Unit.set_texture_for_materials(unit, slot_name, texture_path)`. The engine sets up a per-unit material override; the shared material is never written to. When the unit is destroyed (next re-equip) the override drops with it.
- **Limitation:** `Unit.set_texture_for_materials` doesn't have a per-mesh exclusion equivalent of LA's `skip_meshes` / `textures_other_mesh`. The new `_paint_offhand_textures_locally` logs a warning when those nuance fields are set on the variant. The first focused-triage candidate (`Kruber_empire_shield_hero1_Ostermark01`) has empty `skip_meshes`, so this isn't a problem for the current round; if a later LA shield in the whitelist has skip_meshes we'll need a per-mesh fallback path. Old per-mesh implementation kept inline as `_legacy_paint_offhand_textures_via_shared_material` for reference (delete after verification).
- **No code change required for selecting Default to "revert".** Because each spawn now applies its overrides per-unit (or doesn't, when no LA option is selected), the next re-equip naturally produces a clean unit with no leftover LA binding. The vanilla material itself was never mutated.

### Test plan (this build, on a fresh game restart)
- **Restart VT2 fully** so the shared-material state from earlier sessions is wiped out. Without a clean restart you'll see leaked magenta from prior versions even though this build never writes to a shared material.
- Equip Kruber's mace+shield → cosmetics menu → ONE LA option visible ("Empire Shield Hero1 Ostermark01 (LA)") + all vanilla mace+shield options.
- Apply Ostermark01 on a vanilla Empire mace skin → expect deus-shield mesh + Ostermark heraldry texture, no magenta.
- Equip Kruber's Bret longsword+shield → same ONE LA option visible.
- Apply Ostermark01 on a Bret skin → expect Bret silhouette + Ostermark texture overlay (UV-imperfect, since LA authored the texture for deus shield UVs).
- After applying, click Default → re-equip should produce a clean vanilla shield. No magenta on Default. No magenta on any other shield in the inventory mannequin or illusion browser.
- If still seeing magenta, capture the precise combination (which mace skin / which shield it leaked onto) so we can pinpoint whether it's a different leak or the shared-material residue.

## [2026-05-07 v0.8.16-dev]
### Fixed
- **Glow override now lands on FIRST PERSON weapons.** Verified in-game by user. v0.8.4–v0.8.15 reliably painted 3p but never visually changed 1p, even though the v0.8.5 `[GLOW-trace]` proved every `Unit.set_vector3_for_materials` call returned `ok=true` on the 1p unit. User confirmed vanilla 1P glow IS paintable (deep_crimson skin glows red in 1P with override off), so it wasn't a 1P-shader-doesn't-have-the-variable limit. Switched mechanism from "let vanilla apply, then overlay" (`hook_safe`) to "mutate the global `MaterialSettingsTemplates[name]` table BEFORE vanilla reads it, restore after" (`hook` with template mutation). Same trick NoGlow uses to zero emissive. Vanilla itself becomes the only writer to the unit's materials, so whatever was rejecting our second write on 1p is no longer in play. Applies to all three apply_material_settings copies (`GearUtils`, `_G`, `CosmeticUtils`). User must apply a new cosmetic / re-equip the weapon to trigger a respawn for the override to take effect — live re-paint was removed in v0.8.10 because walking spawned units to repaint destabilised adjacent unit state.

### Changed
- **Focused-triage scope: one LA shield at a time.** Per user request, the LA picker is now narrowed to a single shield until each is fully verified. v0.8.15's broad exposure caused too many simultaneous failure modes (mesh-wrapping issues, magenta from shared-material texture leaks, sticky paint from previous selections) for any of them to be diagnosed in isolation.
- Whitelist in `_la_bridge.lua`: `_LA_KEY_WHITELIST` set to `{ Kruber_empire_shield_hero1_Ostermark01 = true }`. Build_offhand_options now requires the LA key to be in this set in addition to passing `_is_supported_variant`. Other LA keys are excluded from the picker but the iteration code is intact — adding the next shield is a one-line edit.
- Kruber fan-out narrowed to `{ "es_1h_mace_shield", "es_1h_sword_shield_breton" }`. `es_1h_sword_shield` and `es_deus_01` excluded for this round even though Ostermark01's `icons` table covers them; we'll re-enable once mace+breton is verified.
- Other characters' (Kerillian/Bardin/Saltzpyre) fan-out tables unchanged in shape, but the whitelist filter empties their LA pools too — so their pickers show vanilla offhands only this round.
- The Bret-mesh wrapping guard from v0.8.13 (drop the `intended_unit` override when `resolved_skin` matches `_breton_` AND selection has `la_armoury_key`) stays in place.
### Test plan (this build, on a fresh game restart)
- **Restart VT2 fully.** The shared-material texture leak documented in `reference_la_offhand_paint.md` persists across in-session reloads — only a fresh game start clears stale LA texture bindings. Without this, you'll see leaked magenta from earlier sessions and won't be able to attribute behaviour to this build.
- Equip Kruber's mace+shield → cosmetics menu → expect ONE LA option labeled "Empire Shield Hero1 Ostermark01 (LA)" (or similar) plus all vanilla mace+shield options. Confirm vanilla options still all present and unchanged.
- Apply Ostermark01 on a vanilla Empire mace skin → expect a deus-shield-shape painted with Ostermark heraldry (`is_vanilla_unit=true` swaps the mesh to `wpn_es_deus_shield_03`).
- Equip Kruber's Bret longsword+shield → cosmetics menu → expect the same ONE LA option to appear here too.
- Apply Ostermark01 on a Bret skin → expect the Bret shield silhouette with Ostermark texture overlaid (UV fit imperfect because LA authored the texture for the deus shield UVs, but the Bret silhouette is correct).
- Click Default after applying → expect to revert to whatever the underlying skin's native shield is.
- Document anything else (magenta, missing textures, wrong mesh) in detail per combo so we can fix surgically.

## [2026-05-07 v0.8.15-dev]
### Reverted
- **`kind="unit"` LA custom-mesh shields filtered out again; `re_apply_illusion` integration removed.** The v0.8.13 attempt to invoke LA's `re_apply_illusion` from our offhand handler crashed at `network_lookup.lua:2514` with `Table inventory_packages does not contain key: units/empire_shield/Kruber_Empire_shield02_mesh_3p` (user crash 60180105-bd15-49f2-9fa6-9f70dd851846). Two architectural barriers, neither fixable by surface-level patching:
  1. **State-machine race with LA's `mod.update` loop.** LA iterates `SKIN_CHANGED` every frame and calls `re_apply_illusion(mod:get(skin), skin, unit)` on each entry. If our setting and LA's persisted setting disagree, our `swap_units_new` and LA's `swap_units_old` (or vice-versa) interleave with stale `changed_model` flags, leaving `WeaponSkins.skins[skin][hand]` pointing at an LA path that wasn't aliased on this run. The next `swap_units_new` call (ours OR theirs) reads `inventory_packages[<la_path>.."_3p"]` and crashes against the strict `__index`.
  2. **`NetworkLookup.inventory_packages.__index` is fatal on miss.** Every LA call path that goes through `swap_units_new`/`swap_units_old` does naked reads against this table. Per `feedback_vt2_strict_lookup_rawget.md`, anything we do to that table must use `rawget`/`rawset`. Calling LA's pre-existing helpers means we can't swap in safe accessors without wrapping each helper.
- A safe integration would need to either (a) take ownership of LA's update loop for the affected skins (suspend its `re_apply_illusion` calls while ours are in flight), or (b) replicate `swap_units_new` end-to-end with our own state machine and `rawget`/`rawset` accessors. Both are substantial; deferred until there's a focused session for it.
- The Bret-skin mesh-wrapping fix from v0.8.13 is preserved (`kind="texture"` Empire variants still drop the mesh swap on Bret skins; LA's paint overlay handles the texture).
- `/la_offhand_dump` retains the `1p=<bool> 3p=<bool> pkg=<bool>` triage columns from v0.8.12.

## [2026-05-07 v0.8.13-dev]
### Fixed
- **Bret skin no longer wraps LA texture onto the wrong shield mesh.** LA's `kind="texture"` Empire-shield variants (Ostermark, Kotbs, etc.) declare `new_units = wpn_es_deus_shield_03` AND list `es_sword_shield_breton_skin_*` keys in their `icons` table, meaning LA expects them to apply on Bret skins as well — but the mesh swap forces the Bret weapon to render the deus-shield model with LA heraldry painted onto it. User reported the texture wraps incorrectly. Added a guard in `BackendUtils.get_item_units`: when the resolved skin contains `_breton_` AND the selection has an `la_armoury_key` (so this is one of our LA bridge entries, not a vanilla swap), drop the mesh override. The LA paint pass still runs, overlaying the texture on whatever Bret shield the skin already provides. UV fit isn't perfect (LA authored the texture for the deus shield), but the silhouette is now correctly Bretonian.
### Added
- **`kind="unit"` LA shields integrate with LA's swap pipeline.** v0.8.11+ exposed LA's custom-mesh shields in the picker, but they rendered magenta because our override path (just rewriting `result.left_hand_unit`) skipped LA's `swap_units_new` step that aliases `NetworkLookup.inventory_packages` and mutates `WeaponSkins.skins[skin][hand]` — the bookkeeping the engine relies on to bind LA's compiled materials. Added `_ct_apply_la_unit_swap` (file-local, forward-defined per `feedback_lua_forward_reference.md`): when the user clicks a `kind="unit"` LA option, we call `LA.re_apply_illusion(armoury_key, skin, original_unit)` which internally invokes `swap_units_new` + `re_equip_weapons`. Tracking table `_la_active_unit_swap_by_skin` records the active swap per skin so a subsequent click on a different option (texture variant or default) issues a `re_apply_illusion("default", ...)` revert before installing the new one — prevents LA's `changed_model` flag from blocking re-application and keeps `WeaponSkins` mutations balanced. Texture-only and default options remain on the existing override path (no LA pipeline call needed).

## [2026-05-07 v0.8.12-dev]
### Fixed
- **LA custom-mesh shields now actually render in the customization preview.** v0.8.11 made `kind="unit"` LA variants appear in the picker, but selecting one showed "no model at all" — the slot went empty. Root cause: vanilla shields ship as standalone `units/.../wpn_xxx.package` files, so `LootItemUnitPreviewer.load_package` -> `Managers.package:load(unit_path_3p, ...)` succeeds and fires `_on_load_complete`, flipping `self._loaded_packages[path] = true`. The previewer's spawn gate (`loot_item_unit_previewer.lua:511`) only proceeds to `World.spawn_unit` after that flag flips. LA bundles every custom shield mesh into one big `resource_packages/Loremasters-Armoury/Loremasters-Armoury` package — there is no per-unit standalone `.package`. So `Managers.package:load("units/Kerillian_elf_shield/<...>_3p", ...)` phantom-succeeds without firing the callback, the gate stays closed forever, and `World.spawn_unit` never runs. VMF auto-loads each mod's main package on register, so LA's custom meshes ARE engine-resident — just not via the `package`-id lookup the previewer is doing. Fix: hook `LootItemUnitPreviewer.load_package`; when `Application.can_get("unit", path)` is true AND `Application.can_get("package", path)` is false (engine has the unit, but there's no standalone package), short-circuit by setting `_packages_to_load[path] = true` and `_loaded_packages[path] = true` so `_spawn_items` proceeds straight to `World.spawn_unit`. The unit spawn then resolves against LA's globally-loaded resource package. Vanilla weapons are unaffected because their paths satisfy both can_get checks; we only short-circuit the bundled-into-larger-package case. Also extended `/la_offhand_dump` to print per-variant `1p=<bool> 3p=<bool> pkg=<bool>` so future "no model" reports can be triaged in one command.

## [2026-05-07 v0.8.11-dev]
### Added
- **Custom-mesh LA shields now appear in the picker.** Previously `_la_bridge._is_supported_variant` rejected every `kind="unit"` SKIN_LIST entry — LA's own authored 3D shield meshes (Caledor, Chrace, Eaglegate, Eataine, Griffongate, KarakNorn, Kotbs/Ostermark spear+round variants, etc.) — because an early "Unit not found" crash in v0.7.92 made me skip them wholesale. Re-enabled them: LA's resource_package includes `unit = ["units/*"]` so all of LA's `.unit` files are engine-resident as soon as LA finishes loading, and the runtime gate in `BackendUtils.get_item_units` (`_override_package_ready` -> `Application.can_get("unit", path)` AND its `_3p` sibling) will silently skip the override for any mesh the engine genuinely can't spawn. So we get every custom-mesh shield exposed, with a per-spawn safety net for the rare case where one isn't actually engine-resident. For `kind="unit"` variants without a `textures` table, LA's `apply_new_skin_from_texture` early-outs at the `if mod.SKIN_LIST[Armoury_key].textures` check, so no paint is applied — the visual change comes purely from the mesh swap, which is the right behaviour for a custom-mesh variant.

## [2026-05-07 v0.8.10-dev]
### Removed
- **Live glow re-paint reverted.** v0.8.7's `mod._refresh_glow` (and the v0.8.9 `/repaint_glow` chat command) walked `ScriptUnit.extension(local_player_unit, "inventory_system")._equipment.slots` and painted every `right_unit_1p / right_unit_3p / left_unit_1p / left_unit_3p`. Worked for the wielded slot but destabilised adjacent units — user reported that after running the repaint, pressing X (inspect) made hand meshes disappear and 1P state break, only recoverable by switching characters. Root cause not pinned (likely the engine doesn't tolerate `set_vector3_for_materials` on currently-invisible / sheathed 1P units), and I don't have enough data to fix it safely. Removed the function, the command, and the `mod.on_setting_changed` glow dispatch. The hook on `GearUtils.apply_material_settings` (v0.8.4+) is unaffected and still paints any newly-spawned weapon at equip time. Net effect for the user: changing the override or preset now takes effect on the NEXT weapon equip / spawn rather than instantly. To re-add live updates safely, the future approach is to hook the wield event and paint only the weapon at the moment it becomes visible.

## [2026-05-07 v0.8.8-dev]
### Changed
- **Glow override presets renamed to plain colors.** Settings dropdown now reads "Purple / Gold / Red / Green / Blue" instead of the lore names ("Weave-Forged / Geheimnisnacht Dawn / Skulls / Sister of the Thorn / Bitter Dreams"). Underlying preset keys (`purple_glow`, `golden_glow`, `deep_crimson`, `life_green`, `lileath`) unchanged so saved user settings carry over. The Versus / Shyish-Infused preset (5-channel `color_glow_high/low`, `color_smoke_high/low`, `color_dots`) was REMOVED from the dropdown — it drives a different shader path and the user reports it doesn't visibly affect Shyish-Infused weapons via the rune-emissive overlay. Tracked: Weavebound (`magic` rarity, `_magic_01` mesh, baked swirl shader) and Shyish-Infused (`versus` template) likely need their own toggle / probe-driven approach if they're tunable at all. The `versus` entry in `_GLOW_PRESETS` is left in place so the code can still be invoked from a future per-skin UI; it's just not user-facing right now.

### Fixed
- **Apply now works when only the offhand was changed.** Previously, clicking an LA shield without first changing the primary illusion enabled the Apply button but did nothing — the user had to make a primary-row change to "kick" Apply into running. Root cause: vanilla's craft loop (`_handle_input` → `_craft(self._material_items, ...)`) is a no-op when `_material_items` is empty, and `_ct_on_offhand_pressed` never seeded it. Fix: when handling an offhand click, if `_material_items` is empty, look up the currently-effective skin's backend id via `Managers.backend:get_interface("items"):get_weapon_skin_from_skin_key(...)` (which will mint a fake id via our existing `_fake_skin_backend_ids` machinery if the skin isn't in the player's owned set) and push it into `_material_items`. Also flip `_skin_dirty = true` so the post-craft state transition runs `_present_item`. The craft itself is a no-op skin re-apply (same skin in, same skin out), but the ensuing `_apply_weapon_skin_craft_complete → _set_loadout_item` path triggers a weapon re-spawn — and that re-spawn is what our `BackendUtils.get_item_units` hook needs to pull in the new offhand selection.

## [2026-05-07 v0.8.7-dev]
### Added
- **Live glow override re-paint.** Toggling `glow_override_enable` or switching `glow_override_preset` now immediately repaints the local player's currently-spawned weapon units — no re-equip needed. Mechanism: `mod.on_setting_changed` dispatches into `mod._refresh_glow`, which walks `ScriptUnit.extension(local_player_unit, "inventory_system")._equipment.slots` (same access pattern as `/probe_hat`), and for each `right_unit_1p` / `right_unit_3p` / `left_unit_1p` / `left_unit_3p` slot field either overlays the chosen preset or, when the toggle has just been turned OFF, restores the skin's native template via vanilla `GearUtils.apply_material_settings(unit, WeaponSkins.skins[skin_key].material_settings_name)`. Stylish (`_runed_01`, no template) skins can't be restored — but they also weren't being painted, so that's a no-op. New chat command `/repaint_glow` triggers the same walk manually for diagnostics. Forward-reference safety: `_refresh_glow` is attached to `mod` rather than declared as a bare local so the early `mod.on_setting_changed` callback can dispatch through a runtime table lookup (per `feedback_lua_forward_reference.md`). Husks (other players' 3p weapons) NOT covered yet — they live on a different inventory extension. Tracked as follow-up.

## [2026-05-06 v0.8.6-dev]
### Changed
- **Glow override 1P verified working; stripped diagnostic logging.** v0.8.5 added a `[GLOW-trace]` line per `GearUtils.apply_material_settings` call (~6 lines per equip). With user testing on console-2026-05-07-00.25.35.log: every call lands on a live `userdata` unit (alive_ok=true, alive=true) for both 3p and 1p paths, and `Unit.set_vector3_for_materials` returns `ok=true` for each. The hook works as designed. v0.8.6 keeps the hook-safe overlay but gates the trace behind `mod:get("glow_trace")` (off by default; same pattern as `cos_thiccc_trace` and `apply_trace`). User confirmed 1P glow now follows the chosen preset.

## [2026-05-06 v0.8.5-dev]
### Added
- **`[GLOW-trace]` diagnostic logging** on every `GearUtils.apply_material_settings` invocation — unconditional in this build to investigate the "1P glow override doesn't paint" report after v0.8.4. Logs template name, unit type, `Unit.alive` status, and per-variable `set_vector3_for_materials` ok/err. Verified the hook pipeline is sound; trace gated behind toggle in v0.8.6.

## [2026-05-06 v0.8.0] — Dynamic portraits split out
### Removed
- The dynamic-portrait system moved into the standalone
  `dynamic_cosmetic_portraits` mod (Workshop 3721036701, private). Removed
  ~570 lines covering `_PORTRAIT_MATERIALS`, `_hat_portrait_map`,
  `_skin_portrait_map`, state vars, `_collect_all_guis`,
  `_check_portrait_materials_ready`, `_get_kruber_merc_*_key`,
  `_restore/_sync_portrait_settings`, the `portrait_diag` /
  `portrait_dump` / `test_portrait` commands, and the `UnitFrameUI:draw`
  hook. The orphan `_get_hat_item_key_for_unit` helper was deleted.
- Removed the `dynamic_portraits` setting widget + `custom_gui_textures`
  block from `cosmetics_tweaker_data.lua`, plus the matching localization
  entries.
- Removed 30 portrait `material =` and 30 `texture =` declarations from
  `cosmetics_tweaker.package`.
- Moved 90 asset files (30 `.material` + 30 `.png` + 30 `.texture`) and
  `CHARACTER_COSMETIC_CATALOG.md` into the new mod.

### Kept
- The `NewsFeedUI:draw` hot-reload safety hook stayed here — it protects
  illusion / LA bridge atlases, not portrait materials.

## [2026-05-06 v0.8.4-dev]
### Fixed
- **Glow override now lands on first-person weapons.** v0.8.1's `create_equipment` post-hook only painted 3p reliably; 1p stayed the template's original color. Replaced the post-spawn paint with a `hook_safe` on `GearUtils.apply_material_settings` itself — vanilla calls this for both 3p AND 1p weapon units inside `spawn_inventory_unit` (gear_utils.lua:198 + 270), as well as ammo units, projectile dummies, pickups, and the loot-item previewer. Same trick `NoGlow` uses to zero out emissive. Verified test path: equipping a Veteran skin with `purple_glow` then switching the override preset to Crimson now turns BOTH the keep mannequin's blade and the wielded first-person blade red on the next equip. Known caveat (separate issue): skins that don't already have a `material_settings_name` (Stylish `_runed_01` items) still don't take the override — vanilla never calls `apply_material_settings` on them, so this hook never fires for them. Fix path is to also paint at spawn time when no template was set, but that requires understanding why our v0.8.1 post-spawn paint silently no-ops on Stylish materials — separate investigation.

## [2026-05-06 v0.8.3-dev]
### Changed
- **Gated `[apply-trace]` logging behind `mod:get("apply_trace")` toggle.** v0.8.2 added per-event trace lines on `_enable_craft_button` and `_on_illusion_index_pressed` to investigate the "Apply doesn't update the weapon" report. The trace did its job (verified Apply now commits correctly — 4 successful `Applied illusion` events in console-2026-05-06-19.06.33), but at ~50 lines per customization session it drowns out other diagnostics. Now off by default; enable via mod settings file when needed. No widget — same pattern as `cos_thiccc_trace`.

## [2026-05-06 v0.8.2-dev]
### Added
- **`[apply-trace]` diagnostic logging** on `_enable_craft_button` and `_on_illusion_index_pressed` to investigate user report "the weapon doesn't get updated when I hit apply". Pre-fix log analysis (console-2026-05-06-18.50.02 covering 3 customization sessions): zero `Applied illusion` events, backend-resolved skin remained `skin_01` throughout, suggesting Apply was either greyed-out at click time OR never clicked. Trace will surface: every craft-button enable/disable transition with `_skin_dirty` + `_current_recipe_name` + `eac-untrusted` state; every illusion pick with `picked_skin` vs `current_skin`/`default_skin` and the `differs` boolean that gates vanilla's `_skin_dirty = true`. Once the user repros, this pinpoints whether Apply was greyed (no `enable=true` log) or fired without committing (enable=true but no `Applied illusion`).

## [2026-05-06 v0.8.1-dev]
### Added
- **Weapon Glow Override (Phase 1)** — new settings group under "Weapon & Item Appearance". Master toggle `glow_override_enable` plus a 6-option preset dropdown (Purple / Gold / Crimson / Green / Lileath / Versus). When enabled, every spawned weapon has the chosen preset's material variables applied — `rune_emissive_color` (vector3) for the 5 rune templates, or the 5-channel `color_glow_high/low`, `color_smoke_high/low`, `color_dots` set for Versus. Templates verbatim from `weapon_material_settings_templates.lua`. Engine silently no-ops on materials that don't expose the variable, so the override is safe to call universally — only runed/versus-capable meshes change visually. Hooked into all three render paths (`GearUtils.create_equipment` for in-game, `HeroPreviewer/MenuWorldPreviewer._spawn_item` for inventory mannequin, `LootItemUnitPreviewer.spawn_units` for the illusion browser). Phase 1 is global only — per-skin customization comes in Phase 2 once Phase 1 proves the substrate.

## [2026-05-06 v0.7.102-dev]
### Fixed
- **Pending row-1 illusion was reverted to the last-Applied skin every time the user clicked a shield in row-2.** `_ct_on_offhand_pressed` re-resolved the skin via `self:_get_item(backend_id)` → `item.skin` / `items_iface:get_skin(backend_id)` / `WeaponSkins.default_skins`. All three return the BACKEND-stored skin — i.e. the LAST APPLIED illusion. So if the user picked a new row-1 illusion (which only updates `_skin_dirty` and the customization-preview previewer, not the backend) and then clicked a shield in row-2, our respawn discarded the pending row-1 pick and re-rendered with the previously-Applied illusion. **Fix:** read `self._previewer._item.data` and `._previewer._item.skin` first (vanilla `_on_illusion_index_pressed` writes the pending selection there) and only fall back to backend resolution when the previewer isn't initialized yet.

## [2026-05-06 v0.7.101-dev]
### Fixed
- **Crash on Apply with runed/glowy Bret illusion (`Unit not found #ID[f3ec09a279311ac8]` at `world.spawn_unit`)** — GUID 1a7b27db-e813-467d-87f3-6bc0efd9c472. Root cause: `BackendUtils.get_item_units` is called from `GearUtils.create_equipment` with `backend_id=nil, skin=nil` and relies on `item_data.backend_id` (which vanilla stamps onto item_data during loadout resync) to internally resolve the equipped illusion. **Our hook only consulted the explicit `backend_id` arg**, so it bailed at the `has_skin=false` gate for every in-game equip — the user's row-2 selection never applied to the player body, AND we never had a chance to redirect away from a runed-shield path whose package the engine hadn't preloaded. Fix: mirror vanilla's resolution chain — check `item_data.backend_id` as a third fallback after the explicit args. With this, in-game spawns now consistently see the user's offhand selection and route to a preloaded shield mesh, eliminating the `_runed_01` resource-not-found crash. Crash trace verified at console-2026-05-06-04.53.08 line 6926: trying to spawn `wpn_emp_gk_shield_02_runed_01_3p` AFTER LootItemUnitPreviewer had unloaded that package at 05:11:25.073, while `_offhand_selection["es_1h_sword_shield_breton"] = "Empire Shield (Gold)"` (`unit = wpn_emp_gk_shield_05`, both 1p+3p preloaded at 05:11:30) was sitting unused.

### Documented limitations (carry-forward)
- **LA texture paint is invisible on `_magic_*` / `_runed_*` Bret illusions** — confirmed empirically via the v0.7.99 log. The glow-emissive material variants don't expose the standard shield diffuse slot hash (`texture_map_c0ba2942`), so `Material.set_texture` returns `ok=true` but no pixel changes — every LA option visually looks identical to the equipped shield. LA's own `icons` table enumerates compatibility per LA variant (e.g. `Reynard01.icons.es_sword_shield_breton_skin_03_runed_01` = a *bluegrlow* icon variant); we currently don't honor it. To restore visible paint on glow shields we'd need to either (a) filter LA options by `icons` compatibility, (b) force a mesh swap to a compatible non-glow vanilla shield before painting (re-introducing the v0.7.86-disabled override path with safer mesh choices), or (c) drive a per-frame re-paint loop the way LA's normal mode does. Not in this release.
- **LA paint "sticks" across shield changes — switching to a different shield (vanilla or LA) keeps showing the previous LA texture.** This is the shared-material-instance problem: VT2/Stingray's `Material.set_texture` mutates the material asset in place, and shield meshes that share a material file inherit the override globally. We can't reset textures from Lua (no `Material.reset_texture` in VT2), and we can't snapshot originals (no `Material.get_texture` either). LA itself "solves" this by re-painting every shield in the world every frame — we don't, and only paint at spawn time. Future fix candidates: per-frame re-paint loop; per-unit material cloning via `World.create_material`; or restore-on-deselect by remembering a known vanilla diffuse texture per shield mesh. Not in this release.

### UX clarification on Apply for row-2-only changes
- **Apply only commits row-1 (illusion) changes** — that's vanilla `HeroWindowItemCustomization._skin_dirty` behaviour gating `_apply_weapon_skin_craft_complete`. Row-2 offhand selections are stored in `_offhand_selection` the moment the button is clicked and apply on the next item spawn (in-game equip, mannequin re-render). With v0.7.101's `item_data.backend_id` fix, the in-game body and mannequin now reliably reflect row-2 changes on the next spawn — but **Apply itself doesn't trigger a respawn for row-2-only changes**. Forcing an immediate mannequin refresh from row-2 click would require reaching the parent HeroView's previewer instance from inside `HeroWindowItemCustomization`. Tracked as TODO. Workaround for now: close customization (Back) → mannequin re-renders with the new row-2 selection.

## [2026-05-06 v0.7.100-dev]
### Fixed
- **`Unlock All Portrait Frames` toggle never injected anything** (silent no-op since the feature shipped in v0.7.0-dev). Root cause: the hook targeted `PlayFabMirrorBase` but the runtime instance is `PlayFabMirrorAdventure`. VT2's foundation `class()` helper at `foundation/scripts/util/class.lua:51-57` defines inheritance by **copying** parent methods into the child table at class-definition time — there is no `__index` chain to the base. So `mod:hook("PlayFabMirrorBase", "_create_fake_inventory_items", ...)` registered correctly but wrapped a function value the runtime instance never dispatches to. Verified empirically against `console-2026-05-06-02.40.42.log`: VMF logged `Hooking '_create_fake_inventory_items' from [PlayFabMirrorBase]` at mod load (02:41:12.686), well before PlayFab login at 02:41:22, but the in-game `/frames_status` diagnostic reported `inject hook fired 0 time(s)` even with the toggle on and modded realm detected. **Fix:** re-targeted both hooks to `PlayFabMirrorAdventure`. Added a more reliable pre-hook on `_create_fake_inventory_items` that mutates the `fake_inventory_items` parameter to inject all frame keys *before* the original mints fake backend IDs — this is the actual gate that registers items into `_inventory_items` (the table the UI's `get_filtered_items("slot_type == frame")` reads). The companion safe hook on `get_unlocked_cosmetics` keeps the table in sync for later UI re-queries. DLC ownership still respected via `_skin_requires_unowned_dlc`. Toggle still requires a full restart to take effect (the gate runs once at PlayFab login). Memory note: `feedback_vt2_class_hook_derived.md`. Diagnostic command `/frames_status` retained.
- **LA shield paint not visible on the inventory loadout mannequin for vanilla-crafted Bretonnian sword & shield** ("Apply seems to do nothing", "all LA shield options look like the equipped shield"). Root cause: vanilla `equip_item` is called with `skin=nil` for vanilla-crafted Bret weapons because the applied illusion is stored only on the backend `BackendItem` object, not passed through the call chain. Vanilla relies on `BackendUtils.get_item_units` to resolve the skin internally during spawn — but our `_store_equip_skin` hook was caching the literal `nil` arg, so `_spawn_item_post`'s `has_skin` gate failed and LA paint was skipped on the mannequin. **Fix:** `_store_equip_skin` now falls back to `Managers.backend:get_interface("items"):get_skin(backend_id)` when the passed `skin` is nil, mirroring the same resolution chain `_setup_illusions` and `_ct_on_offhand_pressed` already use. Now logs `[LA preview] backend-resolved skin for X: Y` whenever the fallback fires, so future regressions are visible. The customization-screen preview (`LootItemUnitPreviewer`) and in-game body (`GearUtils.create_equipment`) were already painting correctly — only the inventory mannequin path was broken. Verified against console-2026-05-06-02.40.42 log: `[LA paint] skip: has_skin=false` repeating after `equip_item key=es_sword_shield_breton ... skin=nil`.

### Note on Apply button UX
The `Apply` button in the customization screen only commits the row-1 (illusion) selection — that's vanilla behaviour, not a bug. Row-2 offhand selections are stored in `_offhand_selection` the moment the button is clicked and applied on the next item spawn (mannequin re-render, in-game equip). Before this fix, the user-facing symptom on Bret weapons was that the mannequin re-rendered after Apply but never showed the LA paint, making it look like Apply ignored the shield change. With the backend-resolve fix the mannequin now paints correctly on the first re-render after Apply, so the row-1+row-2 changes appear together as the user expects.

## [2026-05-05 v0.7.98-dev]
### Fixed
- **Imperial Longsword (cwv) was being thinned in the inventory character preview** despite the v0.7.87 unit-path migration and the v0.7.90 `cwv_variant` gate. Root cause: the menu hook resolved per-hand paths via `item_data.right_hand_unit` + a separate `info.skin_name` -> `WeaponSkins.skins[skin].right_hand_unit` lookup, which was redundant with what vanilla `equip_item` had already computed. Vanilla calls `BackendUtils.get_item_units` once and stores the resolved per-hand path on each `spawn_data` entry as `unit_name` — that's the only truth source for "what unit IS rendered in this slot right now". Switched both menu hooks (`HeroPreviewer/MenuWorldPreviewer._spawn_item` and `LootItemUnitPreviewer.spawn_units`) to read paths straight from `spawn_data[i].unit_name`. Side-effects: dropped the `cwv_variant` defence-in-depth gate (no longer needed — a cwv item's `unit_name` is always its variant model and can't accidentally match a base-weapon pattern); dropped the now-unused skin-resolution branch on the LootItem path. The GearUtils in-game hook keeps `_resolve_render_unit_path` because it doesn't have a pre-resolved spawn_data array — it gets `result.skin` from the spawn result and looks up the rendered path itself.

## [2026-05-05 v0.7.95-dev]
### Removed
- **"Elven Spear" / "Elven Spear (Exotic)" cosmetic options on Kruber's spear & shield** (`ct_es_deus_we_01/02`). Cross-character (Wood Elf models on a Kruber weapon) — same no-cross-character rule that drove the v0.7.94 Kerillian-side removal.

## [2026-05-05 v0.7.94-dev]
### Removed
- **"Empire Spear & Shield" cosmetic options on Kerillian's spear & shield** (`ct_we_spear_shield_es_01/02/03`). These violated the no-cross-character rule (Empire models on a Wood Elf weapon). Reverting per user.

### Changed
- **"Elven Spear & Shield" illusions on Kruber's spear & shield (`ct_es_deus_we_01/02`) now swap only the spear**, not the shield. Removed `left_hand_unit` from both entries and renamed to "Elven Spear" / "Elven Spear (Exotic)". Picking one in the row-1 illusion picker leaves the shield untouched, so the user's row-2 offhand selection (or the base weapon's default shield) stays in place. Fixes the "equipping the spear model also changes the shield" report — the bundled `left_hand_unit` was forcing both swaps in one click.

## [2026-05-01 v0.7.90-dev]
### Fixed
- **Bretonian thiccc was leaking onto cwv Imperial Longsword in the inventory character preview** (regression introduced by v0.7.87's unit-path migration plus the `_spawn_item_post` slot-walk bug fixed in v0.7.88). Added an explicit `not item_data.cwv_variant` gate to `_spawn_item_post` AND to the `LootItemUnitPreviewer.spawn_units` hook for symmetry with the GearUtils path. Unit-path matching alone *should* exclude cwv variants (their models don't contain `wpn_emp_gk_sword_`), but the gate is defence-in-depth — guarantees no future model collision can cause cwv items to be scaled by a base-weapon override even accidentally.
- Hidden debug toggle: `mod:get("cos_thiccc_trace")` enables `[thiccc]` log lines on each menu apply (item name, skin, resolved right/left paths). No widget — set via mod settings file when needed.

## [2026-05-01 v0.7.88-dev]
### Fixed
- **Character preview in inventory wasn't applying any scale to the Bretonian Longsword** (regression from v0.7.87). `_spawn_item_post` was iterating `self._equipment_units` by numeric `slot_index` and trying to read `_item_info_by_slot[slot_index]`, but `_item_info_by_slot` is keyed by string slot_type (`"melee"` / `"ranged"`). The lookup always returned nil so the per-slot info was never resolved. Now walk `_item_info_by_slot` directly and bridge to `_equipment_units` via `info.spawn_data[1].slot_index`.

## [2026-05-01 v0.7.87-dev]
### Changed
- **Migrated `_weapon_scale_overrides` (item-name-keyed) → `_unit_path_scale_overrides` (model-path-keyed).** The old schema scaled any item whose `item_data.name` matched a registered key (e.g. `es_bastard_sword`). This collided with character_weapon_variants items, which inherit `name = "es_bastard_sword"` from their base via `table.clone` — even with the v0.7.84 `cwv_variant` gate, the gate on the GearUtils hook didn't cover the menu paths that match by `item_name` parameter (the cwv item key, which doesn't match the base name). The new schema matches against the actual model unit path resolved through skin/item, so cwv variants (Imperial Longsword loads `wpn_2h_sword_*`, Helmgart Watchsword loads `wpn_greatsword`) are intrinsically excluded — they don't load the Bretonian model.
- New helpers: `_resolve_render_unit_path(item_data, skin, hand_field)` mirrors `BackendUtils.get_item_units` resolution (skin path takes precedence), `_resolve_factor(factor)` normalizes function/table/number factors into a Vector3, `_apply_unit_path_scale_hand(unit_3p, unit_1p, path, hand_label)` is the per-hand apply primitive.
- `_unit_path_scale_overrides` schema:
  ```
  { pattern = <substring>, factor = <function|{x,y,z}|number>, hand = "right"|"left"|nil }
  ```
- `_weapon_grip_offsets` is unchanged (still item-name-keyed) and currently empty. Grip-offset runs only in-game per `feedback_grip_offset_sign.md`. See DEVELOPMENT.md "Weapon Scale Overrides" for the full schema documentation.

## [2026-05-01 v0.7.86-dev]
### Changed
- **Disabled mesh override for LA shield variants** (deferred fix): even with sync preload, `can_get("unit", ...)`, and `has_loaded()` gates, swapping `left_hand_unit` to LA's declared `new_units[1]` (e.g. `wpn_es_deus_shield_03` for Imperial Hero Ostermark/Kotbs) consistently crashed `World.spawn_unit` with "Unit not found #ID[9405eeb80a227a76]" across v0.7.81–v0.7.85. The `_3p` variant of those deus shield meshes doesn't appear to be reliably available in keep contexts (LA's flow assumes the user has a CW weapon equipped, which loads the deus shield packages — our flow has no such guarantee). `Application.can_get("unit", path)` returned true but the actual `World.spawn_unit` still asserted, suggesting `can_get` checks resource registry availability rather than spawn-readiness.
- All LA shield variants now paint LA textures onto the user's currently-equipped shield mesh (same as the Bret pure-texture variants did successfully). UVs may not match perfectly when an Imperial Hero variant authored for the deus shield shape lands on a Bret GK shield, but it's a survivable visual mismatch vs. a hard crash.
- **TODO** (tracked in `_la_bridge.lua` `_resolve_intended_unit` doc-comment): identify which resource_package actually owns the deus shield 3p variants. Once known, either preload it on demand at customization screen open, OR filter affected LA variants out of the picker pool when their packages aren't engine-resident.

## [2026-05-01 v0.7.85-dev]
### Fixed
- **Crash on Apply with Imperial LA shields (real root cause)**: LA's `Kruber_empire_shield_hero1_*` variants target `wpn_es_deus_shield_03`, which has NO standalone `units/.../wpn_es_deus_shield_03.package` file — the deus shield meshes live INSIDE `resource_packages/levels/dlcs/morris/wastes_common`, which LA loads at boot. Calling `Managers.package:load("units/.../wpn_es_deus_shield_03", ...)` on a non-existent package_name still wrote `self._packages[path]` (because `Application.resource_package` returns a handle anyway and `ResourcePackage.load` runs without erroring) — `has_loaded` then lied, the override fired, and `World.spawn_unit` asserted because the unit isn't actually in the resource manager. **Fix:** preload now uses `Application.can_get("unit", path)` to check whether the unit is engine-resident from ANY source (resource_package or standalone) before attempting to load. The defensive `_override_package_ready` gate also switched to `Application.can_get("unit", ...)`. Together these handle both packaging styles correctly.
- **LA selection reset after Apply**: clicking Apply rebuilt the customization screen with the new skin → `_setup_illusions` re-fired → the v0.7.79 stale-mesh-mismatch check discarded the user's LA selection because the new skin's `left_hand_unit` no longer matches the LA `intended_unit`. **Fix:** track `_offhand_selection_backend_id[weapon_key]` per selection. Only discard when the screen reopens for a DIFFERENT item (different backend_id) of the same item_type. Reload-after-Apply keeps the same backend_id, so the user's pick persists. Mesh mismatch alone no longer wipes the selection.

### Addressed (from REVIEW_AGGREGATE.md, 2026-05-01)
- **rawget audit (review item 9)**: replaced 7 unguarded `ItemMasterList[<dynamic_key>]` lookups with `rawget`. Sites: `_get_weapon_skin_from_skin_key` hook (3 lookups, lines ~1600), `register_custom_illusion` matching_weapon (line 1460), `_get_weapon_key_from_item` (line 1982), `_setup_illusions` item.key fallback (line 2001), `BackendUtils.get_item_units` matching_item_key (line 2257), `_resolve_item_type` matching_item_key (line 2361), `_spawn_item_post` item_name (line 2490), `LootItemUnitPreviewer.spawn_units` weapon_key (line 2615). Per CLAUDE.md, `ItemMasterList.__index` Crashifies on unknown keys; rawget bypasses the metamethod.
- **Custom illusion `_description` shadowed by `_name` (review item)**: `_custom_loc[skin_key .. "_description"] = illusion.display_name` made the Localize hook return the title text for description tooltips, hiding the descriptive entries in `cosmetics_tweaker_localization.lua`. Removed the override; description keys now fall through to the vanilla localizer.
- **Captured-but-unused `orig_hook` in `_fixup_server_clones`**: deleted.

### Notes on remaining REVIEW_AGGREGATE items
The aggregate review covers all 7 mods; this version addresses the cosmetics_tweaker high/medium-priority items plus the user's active offhand-picker bugs. Other mods' items (weapon_tweaker forward-reference at line 256, enemy_tweaker breed registration timing, chaos_wastes potion weight renormalization, ANTIGRAVITY.md banner, doc drift) need separate per-mod sessions and are tracked in `REVIEW_AGGREGATE.md`'s recommended fix order.

## [2026-05-01 v0.7.84-dev]
### Fixed
- **Equipment menu's character preview showed the default (un-painted) shield**: the inventory/loadout view's character preview uses `HeroPreviewer:_spawn_item(item_name, spawn_data)` — `item_name` is the WEAPON master key (e.g. `es_breton_sword`, item_type = `es_1h_sword_shield_breton`), not a skin entry. Our existing `has_skin` gate (`item_data.item_type == "weapon_skin"`) returned false here even though the player HAS an illusion equipped (set via `equip_item(..., skin, ...)`), so `_apply_la_offhand_to_units` was skipped on this path. Now hook `HeroPreviewer:equip_item` (mirroring the existing `MenuWorldPreviewer:equip_item` hook) to capture the `skin` arg into a per-previewer-per-item map (`_equip_skin_by_item`, weak keys on previewer). `_spawn_item_post` reads back the stored skin — if non-empty, has_skin is true and the LA paint runs. Base weapons hovered in the inventory grid hit neither the weapon_skin item_type nor a stored skin → pass-through unchanged, matching the "we add options on top of illusions, never mutate base templates" rule.

## [2026-05-01 v0.7.83-dev]
### Fixed
- **Crash on Apply (root cause: async preload race)**: previous preloads called `Managers.package:load(path, ref, nil, true)` with `async=true`, returning immediately while the load happened in the background. If the user hit Apply before the load completed, `BackendUtils.get_item_units` returned an override path the engine couldn't spawn yet → assertion in `world.spawn_unit`. Switched to **synchronous** load (`async=false`, the VT2 default — `ResourcePackage.load + flush` blocks until ready). One shield package is small; the hitch is unnoticeable. Verified against `foundation/scripts/managers/package/package_manager.lua:80-86`. Wrapped in pcall to swallow "package not found" errors for paths that don't exist on the user's install.
- **Defensive package-loaded gate in `BackendUtils.get_item_units` hook**: even with sync preload, an `_override_package_ready(unit_path)` check now verifies BOTH 1p and 3p packages are fully loaded before applying the override. If not, we skip the override (logs the skip). Belt-and-suspenders against future regressions and unknown paths.
- **Extra diagnostic logging** in `_apply_la_offhand_to_units`: now logs why the LA paint is skipped (no bridge / no world / has_skin=false / no item_type / no selection) and reports paint success/failure per unit. Use this to diagnose the "Bret LA shields not visually changing" report — share the `[LA paint]` lines from `Console.log` so we can see exactly where the flow stops.

## [2026-05-01 v0.7.82-dev]
### Fixed
- **Crash on Apply (still happening after v0.7.81 preload)**: the v0.7.81 preload only loaded the base unit path. Vanilla VT2 packages the 1p and 3p meshes in SEPARATE packages — LA's own bootstrap proves it (`Managers.package:load("...wpn_X", "global")` AND `Managers.package:load("...wpn_X_3p", "global")`). The in-game body spawns both halves; the customization previewer only spawns 3p. Now preload both `<unit_path>` and `<unit_path>_3p` for every offhand override.
- **Bret offhand picker had no visible effect (clicks did nothing)**: vanilla-crafted Bret weapons sometimes have their equipped illusion stored only in the backend, with `item.skin` nil on the BackendItem object. The respawn-after-click branch in `_ct_on_offhand_pressed` was checking `item.skin or WeaponSkins.default_skins[item.key]` — both nil → no respawn, click was a no-op. Now falls through to `items_iface:get_skin(item.backend_id)` before giving up, mirroring the auto-select resolution path.

### Kruber LA shield count
13 Kruber LA shield variants total in `swap_hand="left_hand_unit"`. 7 currently exposed in the picker:
- 5 Bret/GK pure-texture (Bastonne02, Reynard01, Luidhard01, Lothar01, Alberic01)
- 2 Empire heroic texture (Ostermark01, Kotbs01)

The other 6 are LA's `kind="unit"` Empire basic variants (basic1, basic1_Ostermark01, basic2, basic2_Kotbs01, basic2_Middenheim, basic3_Middenheim01) with custom-authored mesh paths under `units/empire_shield/`. They're filtered out for now — restoring them needs LA's custom-mesh packages preloaded via `Managers.package:load`, which I haven't added yet.

## [2026-05-01 v0.7.81-dev]
### Fixed
- **Crash on Apply: "Unit not found" / `world.spawn_unit` assertion** — different cause from v0.7.80. Each vanilla weapon-skin's package chain bundles only its OWN `left_hand_unit`. Our override pointed `result.left_hand_unit` to a different shield mesh whose package was never part of the newly-applied skin's chain, so on re-equip the engine asserted. Fix: preload the override mesh's package via `Managers.package:load(unit_path, "cosmetics_tweaker", nil, true)` whenever the offhand selection changes. Wired into both `_setup_illusions` (auto-select on screen open) and `_ct_on_offhand_pressed` (manual click). Packages stay resident under the `cosmetics_tweaker` reference name for the rest of the session — small per-shield cost, ~one shield package per option the user has touched.

## [2026-05-01 v0.7.80-dev]
### Fixed
- **Crash: "Unit not found" / `world.spawn_unit` assertion** — v0.7.79's `new_units[1]` mesh resolution started forwarding LA's `kind="unit"` variants too. Those variants point to LA's custom-authored mesh files (e.g. `units/empire_shield/Kruber_Empire_shield01_mesh`) that ship without standalone packages — `LootItemUnitPreviewer:load_package` can't fetch them, and the engine asserts on `world.resource_manager().can_get(unit_type, unit_name)` when we set `result.left_hand_unit` to one of those paths. Filter LA's offhand pool to `kind="texture"` variants only (those paint onto a vanilla mesh the engine already has). LA's custom-mesh variants (`kind="unit"`) are excluded — supporting them would require loading LA's packages via `Managers.package:load`, which we'd need to add separately.
- **Pure-texture LA variants** (the Bret heraldic shields with no `new_units` field): no longer fall back to a guessed mesh from the first lex-sorted icon key. With `intended_unit = nil`, we leave the user's currently-equipped shield in place and let LA paint onto it — which is what LA's normal flow does, and matches the user-confirmed "Bret shields look fine" outcome.

### Known limitation
- LA's custom-mesh shield variants (e.g. `Kruber_empire_shield_basic1`-`basic3`, `Kerillian_elf_shield_basic_Avelorn01_mesh`, etc.) are not exposed in the picker yet. Restoring them requires hooking into LA's package-load bootstrap so the engine can spawn them. Tracked separately.

## [2026-05-01 v0.7.79-dev]
### Fixed
- **LA shield model resolution was wrong for Imperial heroic shields**: every LA `swap_hand="left_hand_unit"` SKIN_LIST entry explicitly declares its target mesh in `variant.new_units[1]`. The previous resolution path (texture-path regex + lex-sorted first-icon-key) was unreliable and assumed mesh hints from filenames; it routed Empire heroic shields like `Kruber_empire_shield_hero1_Ostermark01` and `_Kotbs01` to wrong meshes. Replaced both heuristics with a direct `variant.new_units[1]` lookup. Texture variants get the vanilla mesh LA paints onto; unit variants get LA's custom-authored mesh. Falls back to the first-icon heuristic only if `new_units` is missing (doesn't appear in current LA skin_list.lua).
- **Picker not highlighting the current shield for officially-crafted weapons**: `_setup_illusions` now resolves the equipped illusion via `items_iface:get_skin(item.backend_id)` when `item.skin` is nil (vanilla-crafted weapons sometimes hit this path), then falls back to `item_data.left_hand_unit`. Also discards stale `_offhand_selection` entries whose mesh no longer matches the rendered shield, so the picker always reflects what's visible — not whatever the user last clicked. Added diagnostic logging (`mod:info` to log) for `weapon_key`, `item.skin`, resolved skin, current `left_hand_unit`, and the auto-selected option.

## [2026-05-01 v0.7.78-dev]
### Fixed
- **LA paint leaking into vanilla inventory icons & base weapon visuals** ("blazing sun on the mace and shield", "default Bret longsword shows LA reskin"): two distinct leaks both addressed.
  1. **Global state mutation** — `LA.apply_new_skin_from_texture` permanently writes `WeaponSkins.skins[skin].inventory_icon` and `ItemMasterList[skin].inventory_icon` whenever it runs. Before v0.7.74 this never fired (stale `_spawned_units` short-circuited our call). Once v0.7.74 fixed the hook timing, every preview leaked LA icons globally. Replaced the LA-apply call with a local `_paint_offhand_textures_locally` reimplementation in `_la_bridge.lua` that only touches the supplied unit's mesh materials — no `WeaponSkins` / `ItemMasterList` writes.
  2. **Override leaking onto base weapon template** — `_offhand_selection` is keyed by `item_type`, so an LA pick on a skinned Bret weapon also overrode the unrelated base Bret weapon (same `item_type`). Added a hard gate: the `BackendUtils.get_item_units` override and the LA paint both require an active skin (illusion). Base weapon spawns with no `skin` arg fall through to vanilla. Mirrors LA's own behavior — illusions can be customized; the base template can't.
- **Note:** existing icon pollution from prior sessions (where the previous code path leaked) only clears on game restart. Fresh sessions on v0.7.78+ will not leak.

### Added
- **`/la_offhand_dump` command** — dumps each LA shield variant -> resolved `intended_unit` mapping with the source (`texture_hint` / `first_icon` / `unresolved`) and the variant's texture path. Use this to identify variants whose intended mesh is wrong and refine `_texture_mesh_hints` in `_la_bridge.lua`.
- **Texture-path hint parser** in `_la_bridge.lua` — `_texture_mesh_hints` table maps LA folder-name patterns (e.g. `Grail_Knight_shield(%d+)`, `bret_shield_`, `Knight_shield_(%d+)`) to canonical vanilla shield unit paths. Replaces the previous nondeterministic "first key from `pairs(variant.icons)`" heuristic that could pick different shields on different runs. Falls back to the lex-sorted first icon key when no pattern matches.

## [2026-05-01 v0.7.77-dev]
### Fixed
- **Cycling main-hand illusions visually swapped the shield too**: when no offhand had been explicitly chosen, the previewer fell back to each illusion's default `left_hand_unit`, so cycling skins changed BOTH the weapon and the shield even though the offhand picker exists. Now `_setup_illusions` auto-selects the offhand option whose `unit` matches the currently-equipped illusion's `left_hand_unit` (resolved via `WeaponSkins.skins[item.skin].left_hand_unit`, falling back to `item_data.left_hand_unit`). Once auto-selected, the existing `BackendUtils.get_item_units` hook locks the shield mesh, so cycling main-hand illusions only changes the weapon. The user can still pick any other shield from the offhand picker explicitly.

## [2026-05-01 v0.7.76-dev]
### Fixed
- **LA shields painting onto the wrong shield mesh** ("skin wrapped around the wrong model"): each LA `swap_hand="left_hand_unit"` variant in `mod.SKIN_LIST` is authored against a *specific* shield mesh — the one used by any skin listed in its `icons` table. Previously we left `result.left_hand_unit` alone and let LA paint on top of whatever shield the user's vanilla weapon happened to spawn (e.g. the Bret sword + shield's default mesh), which produced visibly wrong UVs whenever the LA texture was authored for a different shield (round Empire, GK, etc.). Now `_la_bridge.build_offhand_options` resolves the first `icons` key to `WeaponSkins.skins[k].left_hand_unit` and stores it as `intended_unit`. The `BackendUtils.get_item_units` hook swaps `result.left_hand_unit` to that intended mesh before LA paints, so the heraldic texture lands on the mesh it was authored for.

## [2026-05-01 v0.7.75-dev]
### Changed
- **Restored WP Shield to Kruber's offhand pool** (kept removed: Elven / Elven Exotic). Kruber now has 13 vanilla offhand options: 5 Empire + 5 GK + 2 Deus + WP Shield.

## [2026-05-01 v0.7.74-dev]
### Fixed
- **LA offhand paint never applied in the customization-screen preview**: the `LootItemUnitPreviewer.spawn_units` hook was using `mod:hook_safe` and reading `self._spawned_units`, but that field is only assigned by the *caller* (`_on_packages_loaded`) AFTER `spawn_units` returns — so inside `hook_safe` it was nil or stale. Switched to `mod:hook` and capture the returned `units` array directly. The same fix applies to the weapon-scale override path that runs in the same hook.
- Used `self._background_world` (the field actually set on `LootItemUnitPreviewer`) as the primary world lookup, with the previous `self._world`/`self.world` as fallbacks.

### Changed
- **Trimmed Kruber's vanilla offhand pool**: removed Elven Shield / Elven Shield (Exotic) / WP Shield. Kruber now sees only Imperial-themed shields (5 Empire variants, 5 GK variants, 2 Deus variants) — matches "imperial weapon and Bretonnian shields" intent.

## [2026-05-01 v0.7.73-dev]
### Added
- **Independent offhand swap for all shield-bearing weapons**: extended `_offhand_options` to cover Bardin's `dr_1h_axe_shield` and `dr_1h_hammer_shield`, plus Saltzpyre Warrior Priest's `wh_flail_shield` and `wh_hammer_shield`. Each pool includes the character's native shield models (5 dwarf shield families with runed/magic variants; WP shield + runed/magic variants) plus a curated cross-character set (Empire/GK/Elven/Dwarf/WP) for consistency with the Kruber and Kerillian pools.
- **`_la_character_weapon_pools.Saltzpyre`**: added `wh_flail_shield` / `wh_hammer_shield` mapping so any future Loremaster's Armoury Saltzpyre/WP heraldic shields automatically appear in the second-row picker. No-op until LA bridge populates a Saltzpyre entry.

## [2026-05-01 v0.7.72-dev]
### Added
- **LA shields in the two-row offhand picker**: Loremaster's Armoury heraldic shield variants are now selectable from the second row on the weapon customization screen, alongside the existing vanilla shield options. Per-character pool with cross-career fan-out: all Kruber shield heraldics (Bret + Empire) appear on every Kruber shield-bearing weapon (`es_1h_sword_shield`, `es_1h_mace_shield`, `es_1h_sword_shield_breton`, `es_deus_01`); Kerillian Elf heraldics on `we_1h_spears_shield`; Bardin Dwarf heraldics on `dr_1h_axe_shield` / `dr_1h_hammer_shield`. No cross-character.
- **`_la_bridge.la_offhand_options_by_character`** — bridge now parses LA SKIN_LIST entries with `swap_hand="left_hand_unit"` and groups them by character prefix.
- **`_la_bridge.apply_offhand_to_unit(world, unit, armoury_key, vanilla_skin)`** — paints LA heraldic textures onto a vanilla shield unit after spawn. Wired into `GearUtils.create_equipment` (in-game body), `_spawn_item_post` (HeroPreviewer/MenuWorldPreviewer inventory preview), and `LootItemUnitPreviewer.spawn_units` (illusion browser preview).

### Changed
- **`_offhand_selection[weapon_key]` now stores the option table itself** (was a unit-path string). Vanilla entries: `{ name, unit }`. LA entries: `{ name, la_armoury_key, vanilla_skin, rarity }`. The `BackendUtils.get_item_units` hook only overrides `result.left_hand_unit` for vanilla selections; LA selections leave the vanilla mesh in place so LA can paint heraldics on top at spawn time.

## [2026-04-30 v0.7.70-dev]
### Added
- **Armor clone support**: LA bridge now registers armor/outfit recolors (e.g. Kruber KOTBS, Kerillian Autumn Weave) as separate selectable items in the skin grid. Armor entries use `cosmetic_key` fallback when `new_units` unit-path matching fails, since armor `new_units` point to body meshes not found in IML `.unit` fields.
- **Rarity background colors**: LA clone items now show red "unique" rarity backgrounds in the cosmetics grid instead of gray "default". Hooked `items_iface:get_item_rarity` to return `"unique"` for any backend_id in `LA_BRIDGE.backend_to_armoury`.

### Fixed
- **`set_loadout_item` caching ALL slot_skin writes**: The hook was caching every `slot_skin` write, preventing vanilla skin equips from reaching the server. Narrowed condition to only cache writes where `LA_BRIDGE.backend_to_armoury[backend_id]` is truthy.
- **Armor clone `.name` handling**: Armor clones must keep `entry.name = vanilla_cosmetic_key` (not `suffix_id`) because `_load_hero_unit` does `Cosmetics[item.data.name]` lookup for skin spawning. Added `name_override` parameter to `build_clone_entry`; armor entries pass the vanilla key as override.

## [2026-04-30 v0.7.61-dev]
### Fixed
- **LA clone preview not updating when switching from vanilla hat**: `_populate_loadout` in `HeroWindowCharacterPreview` compares `item.data.name` against the previewer's stored `current_item_name` to decide whether to call `equip_item`. The game's `parse_item_master_list()` sets `item.name = key` on every IML entry at boot, but our clones were created after boot via `table.clone(original)` — inheriting the vanilla key as `.name`. Since vanilla hat and all its clones shared the same `.name`, the previewer thought nothing changed and skipped the re-equip. Fix: set `entry.name = suffix_id` in `build_clone_entry` so each clone has a unique `.name`.

## [2026-04-30 v0.7.60-dev]
### Fixed
- **Server-stored clone backend_ids persisting across sessions**: Clone backend_ids leaked to the PlayFab server in sessions before the `set_loadout_item` hook was properly installed (v0.7.58). On subsequent startups, `get_loadout_item_id` returned the server's stale clone id, which the cosmetics grid showed as "equipped" even when the user had switched to vanilla. Three-layer defense:
  1. **Startup fixup** (`_fixup_server_clones`): On mod init, reads raw server loadout (bypassing cache), finds any career/slot with a clone backend_id, and replaces it with the corresponding vanilla backend_id via `get_loadout_interface_by_slot().set_loadout_item()`.
  2. **Read-time redirect** (`get_loadout_item_id` hook): If the server returns a clone backend_id and no cache entry exists, finds and returns the vanilla backend_id instead.
  3. **Loadout-table redirect** (`get_loadout` hook): Same redirect applied to the full loadout table before cache merge.

### Changed
- **`la_hats` diagnostic enhanced**: Now shows cache state, raw server value, and gate status for each hat item, making clone-vs-vanilla debugging trivial.

## [2026-04-30 v0.7.59-dev]
### Changed
- **`la_hats` diagnostic command expanded**: Shows VANILLA vs CLONE labels, rarity, equipped status, and cache entries per career for the current hat slot.

## [2026-04-30 v0.7.58-dev (LA bridge)]
### Fixed
- **`set_loadout_item` hook never firing for hat equips**: The hook was installed on `items_iface` (the items backend interface), but `BackendUtils.set_loadout_item` dispatches via `Managers.backend:get_loadout_interface_by_slot(slot_name)` which returns a DIFFERENT interface for cosmetic slots. Moved the hook to `BackendUtils.set_loadout_item` directly (table-form hook on the BackendUtils table) so it intercepts ALL loadout writes regardless of which interface handles the slot.

### Added
- **Loadout cache system** (mirrors AllHats pattern): Clone backend_ids are cached locally in `mod.loadout_cache[career_name][slot_name]` instead of being written to the server. This prevents vanilla clients from crashing on unknown backend_ids. Cache is merged into `get_loadout` and `get_loadout_item_id` reads so the game sees the clone as equipped. Clearing the cache (by equipping a vanilla hat) restores the server-side vanilla backend_id.

## [2026-04-30 v0.7.57-dev]
### Added
- **`la_hats` diagnostic command**: Lists all hat items for the current career with VANILLA/CLONE labels, backend_id, rarity, and equipped status. Essential for debugging clone registration and loadout cache behavior.

## [2026-04-30 v0.7.62-dev]
### Changed
- **Portrait system rewritten: career_settings source-level swap** (confirmed working). Instead of per-widget per-frame content swapping (which only caught the HUD unit frame), the mod now modifies `SPProfiles[5].careers[1].portrait_image` directly at the source. Every UI surface that reads the career portrait — HUD, hero selection, ESC menu, tab overlay, end-of-round — gets the custom portrait automatically because they all read from `career_settings.portrait_image` and dynamically prefix `"medium_"` / `"small_"`.
- Removed `_maybe_swap_portrait_widget`, `_vanilla_portraits`, `_portrait_swapped` (per-widget approach).
- Added `_sync_portrait_settings()` / `_restore_portrait_settings()` which swap/restore career_settings.
- `_sync_portrait_settings()` called from: `UnitFrameUI.draw` hook (for early detection), `on_game_state_changed`, `on_setting_changed("dynamic_portraits")`.
- `_restore_portrait_settings()` called from `on_unload` to clean up.
- `test_portrait` command now triggers `_sync_portrait_settings()` and reports career_settings state.
- `portrait_diag` now shows career_settings.portrait_image and picking_image values.

### Architecture decision record
The portrait feature went through 20+ versions (v0.7.37–v0.7.62) exploring multiple approaches. Key lessons:
1. **Don't hook individual UI surfaces** — VT2 has 5+ places that render portraits, each with different widget structures and content keys. Hooking them individually is fragile and incomplete.
2. **Swap at the data source** — `career_settings.portrait_image` is the single source of truth. Changing it once propagates to every UI surface automatically.
3. **Alpha must be baked into the PNG** — no widget-level masking exists. Copy alpha channel from vanilla portraits.
4. **VMF `custom_gui_textures` format** — MUST use nested tables in `ui_renderer_injections` (`{ {"ingame_ui", "material_path"} }`). Flat strings are silently skipped.
5. **Detect materials via `Gui.material()` probe** — don't hook `UIRenderer.create` (VMF bypasses it).

## [2026-04-30 v0.7.58-dev]
### Fixed
- **`portrait_dump` strict table crash**: Brute-force scan of `ingame_ui` fields accessed `_widgets` on strict tables (e.g. `ui_renderer`) which triggered `"Reading from key '_widgets' not in interface <strict table>"`. Fix: wrap all field accesses in pcall. Same protection added to hero_view windows, end-screen views, and HUD sub-elements.

## [2026-04-30 v0.7.56-dev]
### Fixed
- **Portrait alpha masking**: Custom portrait PNGs were fully opaque rectangles (A=255 everywhere). Vanilla portraits have shaped alpha channels — small portraits (60x70) have a pentagonal/shield-shaped mask with transparent corners (A=0), medium portraits (110x130) have subtle edge alpha (A=241 at corners). Applied vanilla alpha masks to all three custom portrait sizes. HUD portrait (86x108) used a scaled version of the small mask since the vanilla HUD portrait is in the atlas (not extractable as standalone PNG).

### Added
- **`portrait_dump` diagnostic command**: Deep-walks all UI surfaces (HUD unit frames, hero_view, end-screen, brute-force ingame_ui scan, HUD sub-elements) and dumps every widget with `character_portrait` or `portrait` in its content. Reports content keys, style fields (texture refs, mask fields, sizes), and all pass definitions. Run in keep, during hero selection, and at end-of-round to map all three portrait contexts.

### Research findings (portrait system architecture)
- **Portrait naming**: Career settings define `portrait_image` (base name, e.g. `"unit_frame_portrait_kruber_mercenary"`). Prefixes added at display time: `"medium_" ..` for hero selection, `"small_" ..` for matchmaking/rewards.
- **Three portrait contexts use different content keys**:
  - HUD unit frame: `widget.content.character_portrait` (base name, 86x108)
  - Hero selection: `widget.content.portrait` = `"medium_" .. base_name` (110x130)
  - End-of-round: `widget.content.character_portrait` (base name)
- **Current `UnitFrameUI.draw` hook covers only the HUD** — hero selection and end-of-round need separate hooks.
- **Frame rendering**: Frame is a SEPARATE widget drawn on top (higher z-layer) via `UIWidgets.create_portrait_frame()`. No widget-level masking — portrait alpha must be baked into the PNG texture.
- **Portrait set via**: `UnitFrameUI.set_portrait(self, portrait_texture)` → `widget_content.character_portrait = portrait_texture` (source: `unit_frame_ui.lua:470`).

## [2026-04-30 v0.7.55-dev]
### Fixed
- **LA clone preview now updates immediately**: Converted `MenuWorldPreviewer.equip_item` from `hook_safe` to wrapping hook. When the cosmetics grid passes a clone's `backend_id`, the hook swaps `item_name` from the vanilla key to the clone's `suffix_id`, so `ItemMasterList[suffix_id]` is used (custom display name, custom rarity). This makes `_spawn_item` receive the clone key directly — the fragile `_cos_la_pending_backend` mechanism (which was wiped by rapid non-hat equip_item calls for other slots) is eliminated entirely.
- **Vanilla hats no longer show LA texture overrides**: Simplified the apply gate to unconditionally block all managed armoury_keys (previously only blocked when a clone was equipped in the loadout). LA's own `_spawn_item_unit` hook would still apply textures to vanilla hats via its queue system; now the gate blocks those calls at the `apply_new_skin_from_texture` entry point regardless of loadout state. Vanilla hat = vanilla appearance.
- **Removed `_cos_la_pending_backend` mechanism**: The pending stash/consume pattern was inherently fragile — `equip_item` fires for ALL slots (hat, skin, weapons, trinkets) in rapid succession, and any non-hat equip cleared the pending state before the hat's `_spawn_item` could consume it. With the wrapping hook swapping `item_name` directly, the pending mechanism is no longer needed.

### Changed
- **LA clone entries now have `rarity = "exotic"`**: Clone items in the cosmetics grid display an orange rarity border, distinguishing them visually from vanilla hats (which retain their original rarity border).

## [2026-04-30 v0.7.54-dev]
### Fixed
- **Forward-reference crash (3rd occurrence)**: `_check_portrait_materials_ready()` (line 296) called `_collect_all_guis()` (line 360) — Lua locals are NOT hoisted. Fix: moved `_check_portrait_materials_ready` definition below `_collect_all_guis`. This is the same class of bug as v0.7.37 and v0.7.1. See `feedback_lua_forward_reference.md` for the rule.

### Removed
- **Dead `portrait_inject` command**: Manual UIRenderer destroy+create probe no longer needed — VMF handles material injection automatically via `custom_gui_textures` in `_data.lua`.

## [2026-04-30 v0.7.52-dev]
### Changed
- **Portrait material detection rewritten**: `_maybe_swap_portrait_widget` and `test_portrait` now call `_check_portrait_materials_ready()` which probes the Gui directly via `Gui.material()`, instead of relying on `_portrait_materials_ready` flag. The flag was never set because it was gated on a `UIRenderer.create` hook that VMF bypasses internally (VMF destroys+recreates the renderer in its own hook, so our hook never fires).
- `portrait_diag` now actively probes on run instead of reporting the stale flag.

## [2026-04-30 v0.7.51-dev]
### Fixed
- **Root cause: VMF `custom_gui_textures` silent failure** — `ui_renderer_injections` was a flat list of material path strings. VMF's processing iterates entries and checks `type(entry) == "table"` — strings fail this check and are silently skipped. Fix: each entry must be a nested table `{"ui_renderer_creator", "material_path_1", ...}`. The `ui_renderer_creator` is the Lua filename (no path/extension) of the script that calls `UIRenderer.create` — `"ingame_ui"` for the HUD renderer.
- Removed manual `_injected_material_sets` manipulation and `inject_materials()` calls — VMF handles injection automatically when the data format is correct.

### Research findings (v0.7.42–v0.7.50)
Systematic investigation of GUI material injection. Dead ends confirmed: `Gui.create_material` (nil), `Gui.create` (nil), `Material.set_texture` on GUI materials, manual `_injected_material_sets` append (only affects future creates), `UIRenderer.create` hook (never fires — VMF's hook runs at boot). Root cause found by comparing against InventoryFavorites and Loremasters Armoury mods which use the correct nested-table format.

## [2026-04-30 v0.7.42-dev]
### Fixed
- **`uv00_table` nil crash** (`ui_renderer.lua:106`): The v0.7.40 UIAtlasHelper `get_atlas_settings_by_texture_name` hook returned `{ material_name = texture_name }` without UV coordinate fields (`uv00`, `uv11`, `size`). The UI renderer destructures these, crashing on nil. Root cause: a single multi-definition material file (`cosmetics_tweaker_portraits.material`) doesn't work — Stingray's `Gui.create_material` creates ONE material named after the *file*, not the individual definitions inside it. So `material_name = "portrait_kruber_mercenary_hat_1002"` can never resolve.

### Changed
- **Split portrait materials into individual files**: Replaced single `cosmetics_tweaker_portraits.material` (3 definitions) with three files: `portrait_kruber_mercenary_hat_1002.material`, `medium_portrait_kruber_mercenary_hat_1002.material`, `small_portrait_kruber_mercenary_hat_1002.material`. Each file's name matches the texture name, so Stingray creates a GUI material with the correct name.
- **Removed UIAtlasHelper hooks**: `has_atlas_settings_by_texture_name` and `get_atlas_settings_by_texture_name` hooks deleted. Standalone textures don't need atlas settings — the UI falls through to `Gui.bitmap` using the material name directly.
- **Per-file material injection**: `_inject_portrait_materials()` now injects all three material paths into `_injected_material_sets` individually.

### Technical
- Dead-end confirmed: multi-definition `.material` files in Stingray GUI — `Gui.create_material(gui, path)` registers ONE material named after the file basename, not the definition names within. For GUI textures, each texture needs its own `.material` file.

## [2026-04-30 v0.7.39-dev]
### Fixed
- **LA bridge preview not updating live**: Texture swaps now apply directly via `LA.apply_new_skin_from_texture()` instead of routing through LA's deferred queues. The old queue approach required LA's `mod.update()` to process the correct queue (preview_queue vs level_queue), but preview hat swaps came through `AttachmentUtils.link` with the wrong queue routing. Direct application makes the texture change visible in the same frame, matching how weapon scaling works.
- **LA clone loadout cache not cleared on vanilla equip**: Equipping the original vanilla hat after an LA clone left the clone's backend_id cached in `loadout_cache`. `get_loadout` then overwrote the vanilla hat with the stale clone, making it impossible to re-equip the original. Fix: clear `slot_hat` from `loadout_cache` when equipping a non-clone hat.
- **Forward-reference bugs (5 locations)**: `_la_bridge_init_done` was declared at line ~1590 but referenced in closures defined earlier (equip_item hook, _spawn_item_wrapper, _spawn_item_unit_la_hook, AttachmentUtils.link hook, World.link_unit hook). All captured `nil` instead of the variable. Switched all to `LA_BRIDGE.registered` which is always accessible on the module table.
- **Wrong world reference in preview hook**: `_spawn_item_unit_la_hook` used `self._world` but HeroPreviewer stores the world as `self.world`. Changed to `self._world or self.world`.

## [2026-04-30 v0.7.37-dev]
### Changed
- **Portrait system: VMF custom_gui_textures API** — replaced dead-end `Material.set_texture` approach (which doesn't work on GUI materials) with VMF's built-in `custom_gui_textures` system. Custom portrait textures are now declared in `_data.lua` and VMF handles UIAtlasHelper registration + material injection into UIRenderers automatically.

### Fixed
- **`custom_gui_textures` format**: Material path goes in `ui_renderer_injections`, texture names go in `textures`. Previous attempt put the material path as first entry in `textures`, which VMF silently ignored.
- **`custom_gui_textures` location**: Belongs in `_data.lua` return table (processed during mod_data init), NOT in `.mod` file's `new_mod()` argument.
- **Forward reference crash** (`_get_local_player_hat_key` nil): Hat detection functions were defined after the `portrait_diag` command that called them. Lua locals are not hoisted — moved definitions above all call sites.
- **UnitFrameUI hook crash**: `set_portrait_frame_slot_info` and `_set_widget_data` don't exist on UnitFrameUI. Replaced with `draw` hook.
- **Portrait swap safety guard**: Added `_check_textures_registered()` gate — the draw hook now verifies UIAtlasHelper has our texture before swapping widget content, preventing "Material not found in Gui" crashes when registration fails.

### Technical
- Dead-end code removed: `test_swap`, `test_swap_vanilla`, `test_probe_mat` commands (all relied on `Material.set_texture` which doesn't work on GUI materials).
- `_hat_portrait_map` now stores VMF texture names (e.g. `portrait_kruber_mercenary_hat_1002`) instead of file paths.

## [2026-04-30 v0.7.22-dev]
### Fixed
- **Hero selection / end-of-round crash** (`Material 'medium_portrait_kruber_mercenary_hat_1002' not found in Gui`): The `_setup_hero_selection_widgets` and `_setup_player_scores` portrait hooks were missing the `_portrait_material_loaded` guard that the HUD hook had. With material injection disabled (v0.7.21), these hooks still set custom portrait material names on widgets, crashing when the renderer tried to resolve them. Fix: added `_portrait_material_loaded` early-return to both hooks, matching the existing guard in `_sync_player_stats`.

## [2026-04-30 v0.7.21-dev]
### Fixed
- **VMF options menu crash / blank menu** (root cause found): The portrait material injection system (`_ensure_material_injected`) was adding `cosmetics_tweaker_portraits` to `UIRenderer._injected_material_sets` globally. When Stingray's native `UIRenderer.create` couldn't resolve this material, it poisoned the **entire** Gui material loading pass — `vmf_atlas`, `armoury_atlas`, and all other materials failed to load on every subsequently-created UIRenderer. This caused: (1) VMF options menu crash (`Material 'vmf_atlas' not found in Gui`), (2) NewsFeedUI crash (`armoury_atlas not found in Gui`), (3) the previous VMFOptionsView.update safety hook blocking the menu entirely. Fix: disabled global portrait material injection. Portrait map data retained for future per-renderer injection approach.
- **ItemMasterList crashify crash loop**: `_skin_requires_unowned_dlc` used `ItemMasterList[skin_key]` which triggers ItemMasterList's `__index` metamethod — this calls crashify for unknown keys (e.g. Loremaster's Armoury keys like `Kruber_KOTBS_armor` in `WeaponSkins.skins`). Fix: use `rawget(ItemMasterList, skin_key)`.
- **VMFOptionsView.update safety hook removed**: The hook was masking the material injection root cause by blocking the VMF menu. With the injection disabled, vmf_atlas loads normally and the hook is no longer needed.

### Technical
- Portrait material injection (`_ensure_material_injected`, `_remove_injected_material`, `UIRenderer.create` hook) disabled pending a safe per-renderer injection approach. The `_portrait_material_loaded` guard prevents the portrait override path from firing.
- Added `mod.on_unload` callback for future cleanup needs.

## [2026-04-30 v0.7.13-dev]
### Fixed
- **VMFOptionsView crash when `gui` is nil**: The `vmf_atlas` pre-check guard (`if gui and not _gui_has_material(...)`) fell through to calling the original `update` when `gui` was nil — because `nil and ...` is falsy, the guard was skipped entirely. When VMF's update then tried to draw widgets, `UIRenderer_draw_texture` hit the missing material and fataled the engine. Fix: invert the condition to `if not gui or not _gui_has_material(...)` so a nil gui also triggers the early return.

## [2026-04-29 v0.7.10-dev]
### Fixed
- **Crash on first frame: `attempt to call global '_gui_has_material' (a nil value)`**. The function had been deleted from the file but its call site in the new VMFOptionsView pre-check (added in v0.7.9) was left referencing it. Restored the helper near the top of the file alongside `_skin_requires_unowned_dlc`. Same class of bug as the earlier `_skin_requires_unowned_dlc` forward-reference — should have caught both before deploying.

## [2026-04-29 v0.7.9-dev]
### Fixed
- **Persistent UIRenderer pass-stack corruption after VMF options view crash** — root-cause fix. v0.7.7's pcall-around-update caught the inner crash but left `UIRenderer.begin_pass` without a matching `end_pass`. The dirty pass-stack state PERSISTED across frames AND across UI surfaces. When the user exited VMF options (back to game HUD), the next surface to call `begin_pass` was `positive_reinforcement_ui.update` — it hit the imbalanced state and asserted *"Must provide parent scenegraph id when building multiple depth passes"*, crashing the game even though VMF options view itself was no longer active. Solution: PRE-CHECK that `vmf_atlas` is on the active Gui before letting `VMFOptionsView.update` run at all. If it's missing, skip the entire update — `begin_pass` never gets called, renderer stays clean. Settings panel renders blank until atlas reloads, but the game stays alive.

## [2026-04-29 v0.7.7-dev]
### Fixed
- **VMFOptionsView pcall cascade crash**: v0.7.6 only swallowed `"not found in Gui"` errors and re-raised everything else. When the inner crash left `begin_pass` without `end_pass`, the *next* call in the update tick threw *"Must provide parent scenegraph id when building multiple depth passes"* — a different message that bypassed our filter, got re-raised, and crashed the game. Solution: swallow ALL errors in the VMFOptionsView scope (it's narrow enough that masking real bugs there is preferable to crashing the entire game). Throttled error logging to first 5 + every 60th occurrence to avoid log spam.

## [2026-04-29 v0.7.6-dev]
### Changed
- **Reverted broad `UIRenderer.draw_widget` pcall** — it was swallowing per-widget render errors across the entire UI, making vanilla menu items briefly disappear on hover (every animation/highlight redraw that referenced a missing material got dropped). Replaced with a targeted `VMFOptionsView.update` pcall that only protects the VMF settings panel, where the original crash occurred. Vanilla menus retain normal behavior.

## [2026-04-29 v0.7.5-dev]
### Fixed
- **VMF options menu crash** (`Material 'vmf_atlas' not found in Gui`): even on a fresh boot (no reload), opening VMF's mod settings panel could crash because `vmf_atlas` wasn't injected into the active screen Gui. Crash chain: `vmf_options_view.update → draw_widgets → UIRenderer.draw_widget → ui_passes.lua:134 → engine fatal`. Added a global `pcall` wrapper around `UIRenderer.draw_widget` to swallow per-widget render errors. Doesn't fix the underlying VMF/material-loading issue, but prevents the engine from dying. Also catches the broader class of missing-material crashes after `/reload`.

## [2026-04-29 v0.7.4-dev]
### Fixed
- **Hot-reload UI crashes (cascading)**: After `/reload`, third-party mod atlases (VMF's `vmf_atlas`, LA's `armoury_atlas` / `la_notification_icon`) were getting torn down while their widgets were still on screen. The next material lookup fataled the engine on whichever surface drew first — NewsFeedUI, VMF options view, world markers. Multiple bugs contributed:
  1. `wt.mod`'s `on_reload` cleared `loaded_packages` on all 72 mods (see weapon_tweaker changelog) — root cause; fixed in `wt` v0.10.26.
  2. `mod:hook(UIRenderer, "draw_texture", ...)` was useless: `ui_passes.lua` captures `UIRenderer.draw_texture` as a *file-local* at load time, so post-load hooks are bypassed.
  3. `pcall`-wrapping the entire `NewsFeedUI.draw` left `begin_pass`/`end_pass` unbalanced, crashing `world_marker_ui.post_update` next frame with *"Must provide parent scenegraph id when building multiple depth passes."*
- Final fix: `mod:hook_origin("NewsFeedUI", "draw", ...)` replaces the draw entirely, with a per-widget pcall inside the loop so begin/end_pass stay balanced. Stale widgets are pruned after the pass closes.

## [2026-04-29 v0.7.1-dev]
### Fixed
- **Mod failed to initialize on reload**: `_skin_requires_unowned_dlc` was defined at line 791 but used at lines 713 and 748 — Lua locals must be defined before reference. Hoisted the DLC gate function to the top of the file.

## [2026-04-29 v0.7.0-dev]
### Added
- **Unlock All Portrait Frames toggle** (modded only): Makes every portrait frame equippable in the cosmetics loadout. Hooks `PlayFabMirrorBase.get_unlocked_cosmetics` to inject all `item_type == "frame"` entries into `_unlocked_cosmetics` before fake inventory items are generated. DLC-gated frames (`required_dlc`) remain locked if the player doesn't own the DLC. Requires restart after toggling.

## [2026-04-29 v0.6.38-dev]
### Added
- **DLC ownership gate**: Skins with `required_dlc` in ItemMasterList are blocked from unlock/apply if the player doesn't own that DLC (`Managers.unlock:is_dlc_unlocked`). Prevents the mod from bypassing paid cosmetic DLC paywalls in modded realm.

### Fixed
- **Locked illusions not applying**: Three separate bugs prevented locked-but-visible illusions from being applied in modded realm:
  1. `get_weapon_skin_from_skin_key` only searches `_fake_items` (unlocked skins), not `_items`. Vanilla locked skins returned no backend ID, so `_material_items` was empty and the craft hook never received a skin to apply. Fix: generate synthetic fake backend items for any skin in modded realm.
  2. `_on_illusion_index_pressed` checked `content.locked` before enabling the Apply button. Locked skins disabled the button regardless of the unlock toggle. Fix: hook `_on_illusion_index_pressed` to force `content.locked = false` in modded realm (respecting DLC ownership).
  3. `_update_state_craft_button` baked `script_data["eac-untrusted"]` directly into `disable_button` on the craft button widget (separate from `_enable_craft_button`). Fix: hook `_update_state_craft_button` to temporarily clear eac-untrusted for `apply_weapon_skin` recipe.
- **Skin stripped after applying**: `BackendInterfaceItemPlayfab._refresh_items` wipes `item.skin` on every dirty refresh if the skin isn't in `unlocked_weapon_skins` and `bypass_skin_ownership_check` is not set. Our craft hook set the skin, then called `dirtify_interfaces()`, which triggered refresh, which wiped the skin. Fix: set `bypass_skin_ownership_check = true` on the weapon item when applying locally.

### Technical
- Illusion swap in modded realm now intercepts five points (was three):
  1. `_enable_craft_button` — clear eac-untrusted for Apply button + force-clear `is_held`/`input_pressed` on disable
  2. `get_weapon_skin_from_skin_key` — synthetic backend IDs for any skin (not just custom `ct_*` skins)
  3. `craft` + `update` — local backend mirror write with deferred result delivery
  4. `_on_illusion_index_pressed` — force `content.locked = false` for non-DLC-gated skins
  5. `_update_state_craft_button` — clear eac-untrusted for craft button disable_button flag
- `_skin_requires_unowned_dlc(skin_key)` helper checks `ItemMasterList[skin_key].required_dlc` against `Managers.unlock:is_dlc_unlocked`

## [2026-04-29 v0.6.23-dev]
### Fixed
- **Mod failed to initialize** when `_register_custom_illusions` ran: `NetworkLookup.weapon_skins[skin_key]` access threw because the table has a metatable that errors on missing keys. Switched to `rawget` so the membership check no longer trips the guard. This was masking the LA bridge entirely — every `/la_*` command failed silently because mod_script init bailed before the commands were registered.

## [2026-04-29 v0.6.20–v0.6.22-dev]
### Added
- **LA bridge diagnostics**: `/la_dump` (registry contents), `/la_trace 1` (per-hook tracing of `AttachmentUtils.link` and `HeroPreviewer._spawn_item_unit`), `/la_loadout` (find equipped LA-clone backend_ids), `/la_force <armoury_key>` (bypass detection and apply a specific LA variant directly to the player's hat unit, for isolating queue-routing vs LA-pipeline failures).

## [2026-04-28 v0.6.19-dev]
### Added
- **Modded-realm illusion swap**: Weapon illusions can now be applied in modded realm. The Apply button is re-enabled and craft calls are intercepted locally instead of sending to PlayFab (which rejects modded-realm crafting). Changes persist for the session and reset on restart.
- **Custom illusion injection**: New weapon skins can be defined in `_custom_illusions` and appear as selectable illusions in the vanilla skin browser. First entry: "Mace & Bretonnian Shield" (`ct_es_mace_gk_shield_01`) — pairs an Empire mace with a Grail Knight Bretonnian shield.
- **Unlock All Weapon Illusions toggle** (modded only): Makes every weapon illusion selectable in the illusion browser.
- **Bretonnian Sword & Shield thickness fix**: The `es_bastard_sword_thiccc` setting now also applies to the sword portion of Bretonnian Sword and Shield (`es_sword_shield_breton`), without affecting the shield. Uses `_fields` targeting to scale only right-hand units.
- **Loremaster's Armoury bridge toggle** (`la_bridge_enable`): Adds LA hat/skin recolors as separate inventory items.
- Per-hand `_fields` support in `_weapon_scale_overrides` for independent weapon/shield scaling.
- `HeroPreviewer._spawn_item` hook for correct inventory character preview scaling (replaces `MenuWorldPreviewer._spawn_item_unit` which lacked per-hand access).
- `LootItemUnitPreviewer.spawn_units` hook for illusion browser preview scaling, with skin-key-to-weapon-key resolution via `matching_item_key`.

### Fixed
- **Craft button sound loop**: Fast local craft completion left the UI hotspot's `is_held` flag set (engine only clears it on mouse release, not on `disable_button`), causing infinite craft→complete→re-craft cycles. Fixed by force-clearing `is_held` and `input_pressed` when disabling the craft button after illusion application.
- Inventory preview no longer scales both sword and shield on Bretonnian weapons — only the right-hand unit is affected when `_fields` targets right-hand.
- Illusion browser preview now resolves skin keys (e.g. `es_bastard_sword_skin_01`) to weapon keys via `matching_item_key` before applying scale overrides.
