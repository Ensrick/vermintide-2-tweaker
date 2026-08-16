# Loremaster's Armoury cosmetic sync - core-logic audit

**Recensus 2026-08-16 (issue #1088).** This document owns the LA sync-state
invariants. `docs/CROSS_MOD_ARCHITECTURE.md:244` delegates sync-state
invariants + migration status here; `cosmetics_tweaker/LA_SYNC_MODEL.md:8`
points here for the invariants while keeping the LA bridge architecture and its
section 6 gotcha catalogue. The current-state sections below are a source-backed
recensus against the post-#1159 owner-module decomposition; the original
2026-07-03/07-06 audit is preserved verbatim-in-substance as the HISTORICAL
LAYER at the bottom, because its session evidence (timestamps, store-divergence
table) is the empirical record the invariants were derived from.

**Current sources (all current-state claims cite file:line against these):**
- `cosmetics_tweaker/scripts/mods/cosmetics_tweaker/cosmetics_tweaker.lua` (entry; owns the stores and the ordered owner installs)
- `_cos_la_sync_transport.lua` (wire), `_cos_la_apply_runtime.lua` (render apply/revert/reconcile), `_cos_la_replay_policy.lua` (pure readiness + replay reconciler), `_cos_la_replay_runtime.lua` (edge coordinator), `_cos_la_husk_identity_runtime.lua` (identity + spawn monitor), `_cos_la_gate_recovery.lua` (#481 bounded-lease recovery)
- `_cos_appearance_census.lua` (surface x edge truth matrix, schema v2) and `qa/appearance_contracts.psd1` (per-issue appearance contracts registry)
- Issue states re-pulled from GitHub 2026-08-16.

---

## 1. What this core is now (post-#1159 decomposition)

The 2026-07 audit was written against a 9,440-line monolith with five
overlapping stores and per-trigger re-apply sites. Since then the LA sync core
was decomposed into named owner modules installed in a fixed order by the entry,
and the audit's Slice 0-2b designs shipped (see section 6 for the slice
disposition). The runtime shape today:

| Owner module | Installed at (entry) | Owns |
|---|---|---|
| `_cos_la_replay_policy.lua` | `mod:dofile` at `cosmetics_tweaker.lua:76` | PURE policy: inventory/snapshot readiness, snapshot composition, the coalescing replay reconciler. No engine globals; pinned by the offline suite. |
| `_cos_la_sync_transport.lua` | `install` at `:1133`, `install_receivers` after `:1275` | The `cos_la_*` RPC family, peer identity, the three senders, emit dedup + deferred queue, the four receivers + peer purge. |
| `_cos_la_husk_identity_runtime.lua` | `install` at `:1185` | `chars_compatible`, `purge_stale_peer_slot`, `wielded_item_matches`, the LA spawn monitor, the `SimpleHuskInventoryExtension.init` peer-ready edge. |
| `_cos_la_apply_runtime.lua` | `install` at `:1238` | `_apply_la_on_unit` unified apply core, `_ensure_offhand_mesh` pulse, the revert primitives, and `mod._la_reconcile` - the single render-reconcile entry point. |
| `_cos_la_replay_runtime.lua` | `install` at `:1265` | `mod._cos_replay`: per-record apply mapping + bounded-edge coordinator over the policy's reconciler. |
| `_cos_la_gate_recovery.lua` | constructed by `_la_bridge.lua:1314` (`M.gate_recovery`); also consumed by `_cos_cim_preview.lua` | #481 bounded-lease recovery for fail-closed preview refusals (shipped 0.9.212-dev, 2026-08-15). |

Adjacent owners this core calls but does not own (`_cos_la_apply_runtime.lua:86-91`):
`_cos_spawn_boundary` (AttachmentUtils.create_attachment seam),
`_cos_husk_wield_runtime` (husk wield transaction), and `mod._cos_rewield`
(the #1145 per-wearer re-wield coalescer every pulse now defers through,
`_cos_la_apply_runtime.lua:594`).

### 1.1 Stores (as-is, current line numbers)

- **`_la_equips_by_peer[peer][slot]`** - the synced desired-cosmetic store,
  declared `cosmetics_tweaker.lua:829`, handed BY VALUE to the transport, apply,
  replay, and husk-identity owners on a single-assignment proof
  (`_cos_la_apply_runtime.lua:73-84`, `_cos_la_sync_transport.lua:93-100`).
  Entry shape: `{ kind, armoury_key, vanilla_key, hand_field, wearer_career }`
  (`_cos_la_replay_policy.lua:331-333`) - `wearer_career` is the #698 addition
  that keys records to the career that equipped them.
- **`mod._offhand_mesh_by_peer[peer][slot][hand_field] = unit_path`** - the
  #416 vanilla-offhand husk store, `cosmetics_tweaker.lua:840`; replayed
  alongside the LA store by `Policy.build_records`
  (`_cos_la_replay_policy.lua:351-368`).
- **`_la_pending_apply`** - the apply retry queue, `cosmetics_tweaker.lua:1104`.
  Its drain sites REBIND rather than mutate, so it crosses module boundaries as
  a getter/setter accessor pair, never a value (`_cos_la_apply_runtime.lua:59-71`).
- **Local durable owners (still separate, deliberately):** the persistence file
  (`la_persisted_equips`, `_la_persistence.lua`), `mod.loadout_cache`
  (career-scoped hat/outfit bids, accessor `cosmetics_tweaker.lua:1427`),
  `_offhand_selection` (now the session-state module's table,
  `cosmetics_tweaker.lua:620`), and the weak unit-keyed `_local_la_equips`
  (`:663`). The 2026-07 plan to collapse these into one store (old Slice 4) was
  NOT executed; instead the policy layer composes them and refuses to publish a
  partial snapshot - see I1 below.

### 1.2 Transport (`_cos_la_sync_transport.lua`)

One RPC family: `cos_la_apply`, `cos_la_apply_req`, `cos_la_state_req`,
`cos_la_state_ack` (`:7-8`). Three senders with one routing rule - host
short-circuits and broadcasts, client requests the host, no-host emits queue
(`:19-25`): `_send_la_apply` (apply, carries `armoury_key`),
`mod._send_la_revert` (carries `revert = true` - the I2 revert broadcast,
#265), `mod._send_offhand_mesh` (carries `offhand_unit`, #416). Shared queue
state: `_last_emit_at` 0.5s emit-dedup window and the 300s-TTL deferred-emit
drain (`:26-29`). The receive half registers 4 `network_register` handlers plus
the `PlayerManager` remove/add purge pair, in the entry's original order, AFTER
the apply and replay runtimes have published `mod._la_reconcile` /
`mod._la_apply_revert_recv` / `mod._cos_replay` (`:53-77`). The hot-join state
pull (#267) lives here: a joiner pulls the full store when IT is ready, with
bounded attempts; exhaustion is re-armed once per later bounded edge, never
polled (`_cos_la_replay_runtime.lua:69-76`).

### 1.3 Apply core (`_cos_la_apply_runtime.lua`)

`_apply_la_on_unit(owner_unit, slot, kind, armoury_key, vanilla_key)` (`:132`)
is the single funnel every inbound trigger converges on, which is why each gate
exists exactly once:

- **#518 deus-yield** (terminal, weapon-side kinds): CW upgrade cosmetics win;
  dedup'd `[la-state] DEUS-YIELD` printf (`:142-152`), mirrored as a terminal
  reason in `mod._la_reconcile` (`:749-755`).
- **#14 character-mismatch gate** for hats via the pure `_la_chars_compatible`
  (`:195-223`; helper `_cos_la_husk_identity_runtime.lua:11-34`), with the
  SPProfiles fallback and fail-closed "no owner path AND no profile" branch.
- **1P AND 3P residency check** for hat units (`:229-237`, the v0.8.64 fix for
  invisible peer hats).
- **#514 weapon-identity guard** for offhand and illusion: paint only when the
  wielded item matches the stored key, resolved via
  `mod._la_wielded_item_matches` (`:356-368`, `:479-491`; helper
  `_cos_la_husk_identity_runtime.lua:115-129` - matches template/name/key/
  item_type, optional slot-key match for illusions, RESTRICTIVE when
  unresolvable). The store still carries the same pick under multiple key
  namespaces (weapon key, template key, legacy wielded-slot key), which is why
  this guard exists.
- **#204 mesh-mismatch warp guard**: `_offhand_paint_mesh_ok` refuses a
  kind="unit" paint onto an un-swapped mesh (`:406-420`), with `[cos:sync]`
  probe evidence; the paint targets BOTH 3P and 1P wielded units (#203,
  `:381-390`).

`_ensure_offhand_mesh` (`:547-605`) is the sanctioned mesh repair: slot-level
re-equip pulse ONLY (never `World.destroy_unit`), kind="unit" resident-only,
mesh-already-correct no-op, 1.5s per-owner cooldown + 3-try cap (`:544-546`),
and - since #1145 - the wield pair is DEFERRED through the per-wearer
`mod._cos_rewield` coalescer rather than fired inline (`:594-604`), returning
`"coalesced:*"` so the caller queues the paint re-apply behind the deferred
pulse instead of assuming repair happened this frame.

**Revert primitives (#265, audit Slice 1, shipped 0.9.69-dev):**
`mod._la_native_pulse` (`:621`), `mod._la_restore_native_hat`
(residency-gated, convergent regardless of RPC-vs-resync order, `:651`), and
`mod._la_apply_revert_recv` (`:680`) - delete the store entry, purge queued
re-applies for the same (wearer, slot), restore per kind, `[la-state]
REVERT-RECV` printf. Armor un-paint remains deferred to native resync (noted
inline at `:721-724`; the live-repaint half of #265 needs LA API work).

**`mod._la_reconcile(wearer_peer, slot, tag, allow_pulse)`** (`:745-813`) is
the single render-reconcile entry point (#264, audit Slice 2, shipped
0.9.70-dev): reads ONLY the synced store, resolves ONLY the wearer's unit via
`_wearer_unit_for_peer` (the #268 wearer-scoping), applies the #698
career-scope gate (`entry_matches_career` + purge + `[cos:698] RECONCILE SKIP`
printf, `:758-767`), then treats mesh+paint as one gated unit: safe contexts
(`allow_pulse=true`: network callback / mod.update) may pulse; wield contexts
defer a stale mesh to the pending drain (`:791-810`). Returns terminal
`"no-entry"` / `"deus-yield"` vs retryable `"wearer-not-spawned"`.

### 1.4 Replay reconciler (`_cos_la_replay_policy.lua` + `_cos_la_replay_runtime.lua`)

The #660 S3 slice replaced the old per-trigger re-apply sites with a
COALESCING, BOUNDED-EDGE reconciler, pure in the policy file so the offline
suite pins its semantics:

- `Policy.record_generation(record)` (`:272-281`): two records rendering the
  same appearance produce the same generation string; any field change yields a
  new one. Coalescing key = (peer, slot, hand) (`:286-289`).
- `Policy.reconcile_edge(state, edge, records, apply)` (`:384-423`): one pass
  per bounded lifecycle edge; statuses `applied` (mark generation), `skip`
  (terminal - store entry gone / deus-yield, never retry), `defer` (retry on
  the NEXT edge - never per-frame). Already-applied generations are counted
  `coalesced` and do no work.
- `Policy.build_records` (`:336-370`): replays the SURVIVING SYNCED STORES
  (`_la_equips_by_peer` + `_offhand_mesh_by_peer`), never live menu state.
- `Policy.invalidate(state, peer)` / `invalidate_all` (`:299-320`): a joining
  peer's new husk re-applies at unchanged generation; a husk-recreating
  transition resets all coalescing.
- Runtime `replay.apply` (`_cos_la_replay_runtime.lua:40-59`) maps the proven
  machinery onto those statuses: offhand-mesh records pulse via
  `mod._la_native_pulse`; LA records go through `mod._la_reconcile`;
  not-alive wearers defer (BUG_CLASSES husk-skeleton-readiness - never write to
  a dead husk, never poll).
- Edges wired today: **peer-ready** fires from the
  `SimpleHuskInventoryExtension.init` hook (the remote-spawn seam - the class
  has no `extensions_ready`), scoped `only_peer` + `invalidate_peer` to the
  joiner (`_cos_la_husk_identity_runtime.lua:192-215`); session-ready and
  lobby-return edges ride the entry's game-state seam. Every edge logs one
  bounded `[cos:replay] edge=... applied/deferred/coalesced` line
  (`_cos_la_replay_runtime.lua:86-99`).

### 1.5 Publish side: snapshot composition (cold-join cluster #233/#149/#203, #629)

The one-shot "publish my state when a peer appears" decision is now pure and
complete-or-nothing (`_cos_la_replay_policy.lua`):

- `Policy.inventory_ready` (`:30-46`): player-unit existence is NOT enough;
  both weapon slots must have converged on realized `item_data.backend_id`.
- `Policy.local_snapshot_ready` (`:61-71`): all three durable owners must be
  ready - bridge, loadout cache, offhand restore - plus a career name and a
  ready inventory. Consuming the one-shot publish flag before all three
  recreates #629's hat-only cold join; the returned reason names the missing
  owner.
- `Policy.compose_local_snapshot` (`:147-213`): composes ONE immutable plan
  (cosmetics + offhands + custom slots); a saved shield hand whose live
  selection has not converged returns `"offhand-convergence"` so the first
  realized slot cannot consume the edge while the second is still restoring.
- `Policy.publish_local_snapshot` (`:219-261`): counts only positively
  acknowledged sends; the pending flag clears ONLY on `complete = true`, so a
  partial publish stays eligible for retry (transport dedup absorbs repeats).
- `Policy.should_publish_local_on_peer_ready` (`:53-55`): republishes only for
  a DIFFERENT peer - the joiner's pull can replay only records the host already
  has; it cannot reconstruct an owner's unpublished state.

### 1.6 #481 gate recovery (`_cos_la_gate_recovery.lua`, shipped 0.9.212-dev 2026-08-15)

The #617/#742/#749 gates fail closed by design; what was missing (audit
2026-08-03) was recovery - a refused shield stayed base/invisible all session.
The new owner turns every refusal into (a) one bounded `[cos:481] preview gate
REFUSED gate=... reason=... recovery=...` printf per (gate, key), capped at 64
markers (`:29`, `:77-87`), and (b) for the `unit-materials` gate only, AT MOST
ONE session package lease of the refused variant's declared VANILLA parent
package (donor recipe: cwv `_cwv_husk_path.lua` #474). Two structural safety
rules (`:11-22`): only `units/weapons/player/...` packages are ever leased
(`SAFE_LEASE_PREFIX`, `:27`, enforced at `:58`) - a mod-bundled or third-party
package (LA's own bundle included) is NEVER leased, because force-loading a
non-resident foreign bundle is an async C-level fatal that bypasses pcall (gut
v0.2.53 crash GUID ca939793); and one lease attempt per owner package per
session, held as a ref-count pin (`:37`, `:61-74`). The LA-owned `texture-set`
gate is marker-only (`allow_lease=false`, `:47-55`). Consumed by
`_la_bridge.lua:1314` and the exact-identity CIM preview adapter
(`_cos_cim_preview.lua` / `_cos_cim_preview_wiring.lua`).

---

## 2. Invariants (with current enforcement point and honest status)

- **I1 - Single authoritative value.** REVISED, not realized as written.
  `_la_equips_by_peer` is the sole PEER-FACING authority (every module takes
  the same table on a single-assignment proof), but the local durable owners
  were deliberately kept (persistence, loadout_cache, offhand session state)
  and the invariant now holds at the SEAM: `Policy.local_snapshot_ready` /
  `compose_local_snapshot` refuse to publish until every owner agrees, and
  `Policy.build_records` replays only the synced stores. The old D1-D7
  divergences (HISTORICAL LAYER) are closed by gating, not by store collapse.
- **I2 - Every mutation broadcasts, including revert.** HELD:
  `mod._send_la_revert` -> `mod._la_apply_revert_recv` (#265, closed). Residual:
  armor un-paint defers to native resync (`_cos_la_apply_runtime.lua:721-724`).
- **I3 - Every render reconciles against the store.** HELD: `mod._la_reconcile`
  is the single entry point (#264, closed) and the bounded-edge replay
  reconciler covers the lifecycle edges; #233 remains the open umbrella for
  proving the husk cells in-game (verify-fix, coop-required).
- **I4 - One apply path, one gate set, one target.** HELD:
  `_wearer_unit_for_peer` targeting (#268, closed), #698 career-scope gate,
  #514 weapon-identity guard, #14 char gate - each exists exactly once in the
  funnel.
- **I5 - Weapon identity never affects availability.** NOT YET: #266 open
  (verify-fix). The per-weapon offhand pools still exist in `_la_bridge.lua`.
- **I6 - Every decision logs, boundedly.** HELD and TIGHTENED: engine `printf`
  with dedup'd/capped markers - `[la-state]`, `[cos:replay]`, `[cos:698]`,
  `[cos:481]`, `[cos:sync]` probes - each once per key, so evidence survives
  mod-logging-off without log storms.
- **I7 - Mesh and paint are atomic per apply.** HELD in reconcile contexts:
  safe contexts pulse-then-paint, wield contexts defer to the pending drain,
  and the #1145 coalescer serializes pulses per wearer per frame. The
  spawn-time `get_item_units` mesh-swap decision still lives in the entry and
  its gate parity is [unverified] in this recensus (old Slice 3 territory).
- **I8 - Persistence mirrors the authoritative value.** NOT through-set:
  restore still enters via its own `extensions_ready` injection
  (`_la_persistence.lua:256` per the census citation), but the publish gate
  (`offhand_restore_ready`, `local_snapshot_ready`) now sequences it so a
  half-restored state cannot publish (the #629 class).
- **I9 - Delivery is confirmed, not fire-and-forget.** HELD: the joiner-driven
  `cos_la_state_req` pull with `cos_la_state_ack`, bounded attempts, and
  edge-scoped re-arm after exhaustion (#267, closed;
  `_cos_la_replay_runtime.lua:69-76`).

Two invariants EARNED since the original nine:

- **I10 - Reconciliation is edge-driven and coalesced, never per-frame.** One
  apply per (peer, slot, hand, generation); `defer` waits for the next bounded
  edge (`_cos_la_replay_policy.lua:263-423`).
- **I11 - A fail-closed refusal is named and boundedly recoverable.** Every
  gate refusal prints which gate ate the cosmetic, and recovery leases are
  structurally restricted to vanilla per-unit weapon packages, once per
  session (`_cos_la_gate_recovery.lua`; #481).

---

## 3. Coverage accounting: census + contracts (supersedes the old event matrix)

The 2026-07 hand-maintained "event x action inventory" is superseded by two
machine-checked surfaces:

- **`_cos_appearance_census.lua`** (schema v2, re-keyed 2026-08-04 by #1157,
  `:14-45`, `schema_version = 2` at `:178`): 8 families x 17 surfaces x 8+
  lifecycle edges as an explicit surface-x-edge MATRIX, because the pre-#1157
  independent vectors could not express "husk AT mission transition" - the
  exact recurring failure class (#233 LA replay, #738 pre-join replay). The
  truthfulness rule (`:35-39`): a pair is "implemented" ONLY with a citable
  code path; forced-honest husk pairs (`peer_ready`, `customize`,
  `mission_transition` on EVERY family, `:116-121`) stay unsupported until
  in-game proof lands. Pure data, loaded by
  `qa/lua/tests/test_appearance_census.lua`. The #481 ship earned exactly one
  cell: `offhand_shield_swaps.cim_preview.preview_open` (`:248`, `:257-259`);
  every other cim_preview edge remains unsupported pending proof.
- **`qa/appearance_contracts.psd1`** (SchemaVersion 1): the per-issue contracts
  registry - 17 surfaces, 17 replay edges, 9 concerns, dispositions
  covered/deferred/not-applicable (`:14-63`), name authority owned by
  `tools/shared_lib/_lib_appearance_descriptor.lua` +
  `_lib_appearance_name_authority.lua` and validated by
  `check_appearance_contracts.ps1` (`:4-10`). 17 contracts today, including
  the LA-sync-relevant `cosmetics.issue481.cim-exact-offhand-preview`
  (`:1173`, three concerns: unit_identity / material / transform),
  `cosmetics.issue698.career-scoped-husk-material` (`:1444`),
  `cosmetics.issue48.cim-exact-glow-persistence` (`:1362`), and
  `shared.issue749.borrowed-renderer-residency` (`:146`). Every concern must
  declare EVERY cell; omission is never success.

When adding or claiming an LA-sync behavior, update the census cell and the
relevant contract in the same change - that pair, not this document, is the
per-cell truth surface. This document owns the invariants and the cross-cutting
mechanism map.

---

## 4. Issue matrix (states re-pulled 2026-08-16)

| Issue | Symptom (one line) | Invariant | State 2026-08-16 | Mechanism now |
|---|---|---|---|---|
| #149 | LA shield reverts at mission start | I3/I7 | closed (historical) | pending-queue + reconcile funnel |
| #203 | Own shield drops on entry/switch-back | I3 | closed (historical) | local wield -> `_la_reconcile`; 3P+1P paint (`_cos_la_apply_runtime.lua:381-390`) |
| #204 | Texture warps onto un-swapped mesh | I4/I7 | closed (historical) | `_offhand_paint_mesh_ok` inside the funnel (`:406`) |
| #233 | Late/transition husk meshes not reapplied | I3/I7/I9 | **OPEN, verify-fix, 0-critical, coop-required** | bounded-edge replay + state pull; husk census cells stay forced-unsupported until this passes |
| #234 | Mid-mission model change fails | I3/I7 | closed Fixed | `_ensure_offhand_mesh` via reconcile |
| #235 | In-mission preview blank | none (not sync) | closed | preview-world path; still excluded from this core |
| #264 | Switch-back loses cosmetic on peers | I3 | closed Fixed | `mod._la_reconcile` (Slice 2, 0.9.70-dev) |
| #265 | Revert never propagates | I2 | closed | `_send_la_revert` + `_la_apply_revert_recv` (Slice 1, 0.9.69-dev); armor repaint residual noted at `:721-724` |
| #266 | Kruber shield availability parity | I5 | **OPEN, verify-fix** | per-weapon pools remain in `_la_bridge.lua` |
| #267 | Hot-join gets no state (pre-ingame race) | I9 | closed Fixed | `cos_la_state_req`/`ack` pull-on-ready + edge re-arm |
| #268 | One equip pulses co-peer/bot units | I4 | closed Fixed | `_wearer_unit_for_peer` scoping in reconcile |
| #373 | LA skins on Weavebound shields | I4/I7 | OPEN, verify-fix | husk offhand channel disproven for LA-shield case (census `offhand_shield_swaps.husk` note) |
| #416 | Vanilla offhand mesh on husks | I1/I3 | shipped | `_offhand_mesh_by_peer` store + `offhand_unit` payload + replay records |
| #481 | LA skins vanish from Athanor previews | I11 | **OPEN, verify-fix** (0.9.212-dev shipped 2026-08-15) | exact CIM preview context + `_cos_la_gate_recovery` bounded lease; census earned `preview_open` only |
| #514 | Guard dead on local wearer (husk-only field) | I4 | shipped | `mod._la_wielded_item_matches`, restrictive-on-unresolvable |
| #518 | LA render stomps deus upgrade skin | I4 | shipped | terminal deus-yield gate in funnel + reconcile |
| #629 | GK Purpure/Azure set (hat-only cold join) | I1-seam | OPEN, verify-fix | `local_snapshot_ready` three-owner gate |
| #660 | Unify appearance across render surfaces | umbrella | **OPEN, 0-critical, blocked/not-started** | W0 census + W1 shipped; S3 reconciler live; W2 pilot + #741 next (see `project_vt2_appearance_unification`) |
| #698 | Husk repaints GK armor on wrong career | I4 | closed Fixed | `wearer_career` on records + `entry_matches_career` gate in reconcile |
| #738 | Host cosmetics skipped as bot alias | I4 | OPEN, not-started | census husk `peer_ready` note; pre-join replay audit |
| #1088 | Refresh this audit | - | this recensus | - |
| #1145 | Same-frame husk respawn / re-wield storm | I7/I10 | OPEN, verify-fix, 0-critical, coop-required | `mod._cos_rewield` per-wearer coalescer; all pulses defer through it |
| #1157 | Re-key census to surface x edge | - | closed | census schema v2 |
| #1159 | Owner-module decomposition | - | shipped | the module table in section 1 |

Reading of the matrix: the 2026-07 bug cluster (#264/#265/#267/#268) is closed
and its fixes are structural (single funnel, single reconcile, wearer scoping,
revert broadcast, confirmed delivery). What remains open is (a) the PROOF
class - #233's husk cells and everything the census keeps forced-unsupported
until an in-game pass, (b) the PARITY directive #266, (c) the #660 umbrella,
and (d) the preview-surface class #481/#373 where fail-closed gates now at
least name themselves and recover boundedly.

---

## 5. Delegation map

- `docs/CROSS_MOD_ARCHITECTURE.md:244` - delegates LA sync-state invariants +
  migration status to THIS document (do not duplicate the invariants there).
- `cosmetics_tweaker/LA_SYNC_MODEL.md` - LA bridge architecture; section 6 is
  the gotcha catalogue (kind=texture/unit, husk RPC race, offhand preload,
  hook_safe shadow); its header (`:8`) points here for invariants.
- `cosmetics_tweaker/ENGINE_SURFACE.md` - every vanilla (Class, method) hook
  this mod owns; read before adding a hook.
- `docs/WEAPON_APPEARANCE_STANDARD.md` - the normative surface/descriptor
  contract; `_cos_appearance_census.lua` + `qa/appearance_contracts.psd1` are
  its machine-checked instances (name authority:
  `tools/shared_lib/_lib_appearance_descriptor.lua`).
- `cosmetics_tweaker/DEVELOPMENT.md:57` - `_cos_la_gate_recovery.lua` row.

---

## 6. Disposition of the 2026-07 migration plan

| Slice (as designed 2026-07) | Disposition 2026-08-16 |
|---|---|
| 0 - instrument store + emit routing | SHIPPED (0.9.69-dev) and evolved into the bounded-marker discipline (I6). |
| 1 - revert broadcast (#265) | SHIPPED (0.9.69-dev); lives in `_cos_la_apply_runtime.lua:607-729` + `mod._send_la_revert`. |
| 2 - single reconcile, wearer-scoped (#264/#268) | SHIPPED (0.9.70-dev); lives as `mod._la_reconcile` (`:745`). |
| 2b - confirmed delivery / pull-on-ready (#267) | SHIPPED; `cos_la_state_req`/`cos_la_state_ack` + edge re-arm. |
| 3 - fold gate into primitive incl. spawn path | PARTIAL: gates are inside the funnel and the pulse helper; the spawn-time `get_item_units` swap decision's gate parity is [unverified]. |
| 4 - collapse redundant local stores | SUPERSEDED, deliberately: stores kept, publication gated by `Policy.local_snapshot_ready` / `compose_local_snapshot` (see I1). |
| 5 - persistence through `set` | NOT DONE as designed; restore still injects at `extensions_ready`, but is sequenced by the publish gate (I8). |
| 6 - Kruber shield data parity (#266) | OPEN (verify-fix). |

The plan's successor is not another slice list here: per-cell work is tracked
by the census + contracts (section 3) and the #660 umbrella.

---

---

# HISTORICAL LAYER - 2026-07-03 / 2026-07-06 audit (preserved evidence)

> Everything below is the dated empirical record the invariants were derived
> from. Line numbers in this layer cite the PRE-DECOMPOSITION monolith
> (`cosmetics_tweaker.lua`, 9,440 lines at 2026-07-03) and NO LONGER RESOLVE
> against current source; the current mechanism map is sections 1-6 above.

**Motivating problem (user, 2026-07-03):** "These cosmetic issues have been so
persistent, with slow progress. It seems there should be some kind of logic that
governs all these interactions which is common sense that's not being applied
... It's like we're chipping away at issues on the surface instead of getting at
the core logic of what's wrong here." The audit named that core logic (the
invariants), showed where the then-current code violated it, and proposed the
consolidation that sections 1-6 above record as shipped/adapted.

**Migration status as recorded 2026-07-06:** Slices 0, 1, 2, and 2b implemented
and shipped: slices 0+1 in cosmetics_tweaker **0.9.69-dev** (`[la-state]`
instrumentation incl. emit routing + husk wield gates; revert broadcast, #265;
plus the #268 wearer-scoping pulled forward), slices 2+2b in **0.9.70-dev**
(`mod._la_reconcile` single entry point with all five triggers repointed, #264;
`cos_la_state_req` pull-on-ready, #267). Source correction found during
implementation, relevant to #373: weave `_magic_NN` items carry the SAME
`item_type` as their base weapon (`item_master_list_lake.lua:594-608`,
`item_type = "es_1h_sword_shield_breton"`), so the family-map concern does NOT
extend to weave keys - the weave gap is in the apply path (different
`left_hand_unit` mesh, `wpn_emp_gk_shield_01_magic_01`), not availability.

## H.1 Session evidence (2026-07-03 21:30, both 0.9.65-dev, user HOSTING as `11000010ef3befb`; logs `console-2026-07-03-21.30.34-47da7f2a` host / `console-2026-07-03-21.35.13-20df4bd5` client)

- **#267 hot-join pre-ingame race** (delivery timing). The join-triggered
  self-re-emit fired at 21:36:53.220, 17ms BEFORE the client's `peer_ingame`
  flip at 21:36:53.237, so the "all" send never reached the joiner; the
  joiner's empty `_la_equips_by_peer` meant cache self-heal could not cover it.
  Same race class as #233's 25ms transition race; generalizes to every
  broadcast timed off "peer appeared" rather than "peer confirmed ingame".
  Became invariant I9 and the pull-on-ready design (now shipped).
- **#268 cross-unit contamination** (targeting). Wire-only: one host equip
  pulsed `_ensure_offhand_mesh` on THREE owner units (21:39:01.166-167,
  21:41:01.423-424), including a Saltzpyre-bot Witch Hunter shield
  (`from_mesh=wpn_wh_shield_01_t1_magic_3p`) and a `from_mesh=<none>` unit, all
  force-swapped to Kruber empire meshes, all ok=true. Root: the recv handler
  looped ALL players at the wearer peer; a host peer owns its bots. Became the
  I4 targeting clause (now `_wearer_unit_for_peer` in reconcile). Likely the
  true mechanism behind several #204 "stretched skin" sightings.
- **#264 confirmed bidirectional.** The HOST kept an LA shield into mission
  (client rendered it 21:41:01), swapped to secondary and back, and the client
  lost it permanently - the mirror image of the earlier client-side case. Ruled
  out host/client asymmetry; purely the missing reconcile-on-wield.
- **Mid-mission wearer-initiated emit loss** (transport, cross-ref #234/#264).
  Client's mission-time `EMIT-ON-EXIT` fired 21:41:18 / 21:42:31 / 21:42:42;
  the HOST log showed NO `RECV` after 21:41:00 and the client's own echo for
  the last one arrived 79s late (21:44:01). The routing branch logged only via
  `_dbg`/`_trace` (invisible with mod logging off) - the finding that made
  "instrument the emit routing with printf" Slice 0's second half and hardened
  I6.
- **Hat shares this machinery.** Host log 21:34:47-21:36:11 showed a kind=hat
  RECV family (slot_hat, `Kruber_SunsetBonnet`/Worthy helm keys, incl. an
  `applied=false` at 21:36:32.660 = wearer-not-spawned retry). Hat, armor,
  illusion, and offhand were confirmed to ride one state machine - which is why
  the current funnel dispatches all four kinds.

## H.2 The five-store divergence table (as-was; the empirical case for I1)

At 2026-07-03 five overlapping runtime stores answered "what cosmetic does peer
P want in slot S", each keyed differently, each written by a different event
subset: `_la_equips_by_peer` (synced, template-or-slot keyed),
`_offhand_selection` (local, backend_id keyed), `_local_la_equips` (local,
unit+slot keyed), `mod.loadout_cache` (local, career keyed), and the
persistence file. The observed divergence pairs:

| # | Divergence (as observed) | Bug |
|---|---|---|
| D1 | Local body painted from `_offhand_selection`; peers read `_la_equips_by_peer` - local paint lost on entry/switch while the synced copy was intact | #203 |
| D2 | Offhand revert restored the local baseline and dropped the queued emit; remote stores kept the stale LA key forever | #265 |
| D3 | Hat/armor vanilla revert cleared the local cache with no broadcast | #265 |
| D4 | Host's post-transition broadcast raced a still-loading client and was dropped; nothing re-sent | #233 |
| D5 | Rendered husk mesh set once at spawn; the store updated on every apply - mid-mission changes left mesh behind store | #234/#264/#233 |
| D6 | Offhand slot key = wielded TEMPLATE, `_offhand_selection` key = backend_id; two shields sharing a template collided (the v0.9.8.9 mirror-write crash) | latent |
| D7 | Persistence `illusions[bid]` vs live picks: disagreed until next equip if the live pick changed without a save/clear | latent |

Resolution as shipped: D2/D3 by the revert broadcast (I2); D1/D4/D5 by the
single reconcile + bounded-edge replay + confirmed delivery (I3/I9); D6 managed
(not eliminated) by the #514 weapon-identity guard, since the multi-namespace
keys still exist; D7 sequenced by the publish gate (I8). The store-collapse
answer to D1/D6 (old Slice 4) was deliberately replaced by the
composition-gate design - see I1.

## H.3 Structural readings that became invariants

1. **The revert row was empty on the viewer side** - every equip event had an
   emit and a remote apply; every revert event had neither. -> I2.
2. **Reconcile was wired per-trigger, not once** - four+ separate re-apply call
   sites, each added for one reported trigger; #264 (a trigger nobody added)
   fell through all of them. -> I3.
3. **Broadcasts were fire-and-forget against an unconfirmed receiver** - sends
   raced the receiver's `peer_ingame` flip by 17-25ms with no ack and no
   re-send, and a hot-joiner's empty store could not self-heal. -> I9.
4. **Apply targeted co-peer units, not just the wearer** - the recv pulse
   looped every player at the peer; a host peer owns its bots. -> I4.

#235 (in-mission preview blank) was established as NOT a sync-state bug (a 2D
tonemapping env with no 3D scene light in the mission preview world) and stays
permanently excluded from this core.
