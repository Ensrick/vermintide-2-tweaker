# Loremaster's Armoury cosmetic sync - core-logic audit

Research and design only. No code was changed to produce this document.

**Motivating problem (user, 2026-07-03):** "These cosmetic issues have been so
persistent, with slow progress. It seems there should be some kind of logic that
governs all these interactions which is common sense that's not being applied ...
It's like we're chipping away at issues on the surface instead of getting at the
core logic of what's wrong here." This audit names that core logic (the
invariants), shows where the current code violates it, maps every open issue to
the violated invariant, and proposes a consolidation that makes the invariants
hold by construction.

**Sources (all claims cite file:line against these):**
- Mod: `cosmetics_tweaker/scripts/mods/cosmetics_tweaker/cosmetics_tweaker.lua` (9440 lines), `_la_bridge.lua` (1615), `_la_persistence.lua` (255).
- Issue history: `#149 #154 #203 #204 #233 #234 #235 #264 #265 #266` plus `#267` (hot-join pre-ingame race) and `#268` (cross-unit contamination), both from the 2026-07-03 21:30 session (Ensrick/vermintide-2-tweaker).
- Decompiled engine: `Vermintide-2-Source-Code` (cited where an engine claim is made; `[unverified]` where I could not confirm).
- Prior architecture notes: `cosmetics_tweaker/LA_SYNC_MODEL.md` section 6 (gotcha catalogue).

**Session addendum (2026-07-03 21:30, both 0.9.65-dev, user HOSTING as `11000010ef3befb`; logs `console-2026-07-03-21.30.34-47da7f2a` host / `console-2026-07-03-21.35.13-20df4bd5` client):** four findings folded in below.
- **#267 hot-join pre-ingame race** (delivery timing). The join-triggered self-re-emit fired at 21:36:53.220, 17ms BEFORE the client's `peer_ingame` flip at 21:36:53.237, so the "all" send never reached the joiner; the joiner's empty `_la_equips_by_peer` means cache self-heal cannot cover it. This is the SAME race class as #233's 25ms transition race and it generalizes: every broadcast timed off "peer appeared" rather than "peer confirmed ingame" loses it. New invariant I9 (section 3) + design change (section 5.6).
- **#268 cross-unit contamination** (targeting). Wire-only, user never saw it: one host equip pulsed `_ensure_offhand_mesh` on THREE owner units (21:39:01.166-167, 21:41:01.423-424), including a Saltzpyre-bot Witch Hunter shield (`from_mesh=wpn_wh_shield_01_t1_magic_3p`) and a `from_mesh=<none>` unit, all force-swapped to Kruber empire meshes, all ok=true. Root: the recv handler resolves wearer units via `pm:players_at_peer(wearer)` and loops ALL players (`cosmetics_tweaker.lua:6989`); the host peer owns the host player AND every host-controlled bot, so the pulse hits bots too. I4 violation (section 3), new #268 row (section 4). Likely the true mechanism behind several #204 "stretched skin" sightings.
- **#264 confirmed bidirectional.** This session the HOST kept an LA shield into mission (client rendered it 21:41:01), swapped to secondary and back, and the client lost it permanently - the mirror image of last session's client-side case. Matrix cell (section 2) marked confirmed both directions.
- **Mid-mission wearer-initiated emit loss** (transport, cross-ref #234/#264). Client's mission-time `EMIT-ON-EXIT` fired 21:41:18 / 21:42:31 / 21:42:42; the HOST log shows NO `RECV` after 21:41:00 and the client's own echo for the last one arrived 79s late (21:44:01). Wearer-initiated mid-mission changes are failing at the transport/queue layer. Link analysis in section 2 (new "wearer mid-mission change" row) and section 4.
- **Hat shares this machinery.** Host log 21:34:47-21:36:11 shows a kind=hat RECV family (slot_hat, `Kruber_SunsetBonnet`/Worthy helm keys, incl. an `applied=false` at 21:36:32.660 = wearer-not-spawned retry). Hat is already in the state model (1.1/1.3/1.4) and the apply function (`:6404`); the redesign in section 5 covers hat, armor, illusion, and offhand uniformly through the same `set`/`reconcile`. Called out explicitly so it is not treated as a separate subsystem.

**Two in-flight fixes to be aware of (other agents editing concurrently):**
1. A transition-walk repair around `cosmetics_tweaker.lua:884-899` (arming) and
   `:7951-8012` (drain) - the CLIENT-side re-apply of remote peers' offhand
   meshes after a level transition. This addresses **#233** within the current
   architecture (see section 4 note).
2. A preview-env re-point around `cosmetics_tweaker.lua:2589-2716`. This
   addresses **#235**. Note up front: **#235 is not an LA-sync-state bug at all**
   (it is an in-mission preview-world lighting problem: the mission preview world
   carries `environment/ui_hdr`, a 2D tonemapping env with no 3D scene light, so
   the weapon draws black - `cosmetics_tweaker.lua:2597-2609`). It is included in
   the case-study set but does not belong to the consolidation in section 5; it
   is called out separately in sections 4 and 5 so it is not accidentally folded
   into the state core.

---

## 1. State model (as-is)

Every piece of LA cosmetic state the mod maintains. "Owner" = which machine is
authoritative in principle. "Lifetime" = when it is cleared. The last column of
the disagreement list (1.13) is the load-bearing part: those are the places two
stores can hold different answers for the same question.

### 1.1 `_la_equips_by_peer[peer_id][slot_name]` - the synced desired-cosmetic store
- Value: `{ kind, armoury_key, vanilla_key, hand_field }`. `cosmetics_tweaker.lua:5910` (declared), populated at `:6030`.
- Owner: **host-authoritative in name, replicated on every peer in practice.** The host's `cos_la_apply_req` handler writes it (`:6812`); the host's `cos_la_apply` broadcast is mirrored into the identical table on every receiver, including clients (`:6901`, the v0.9.0.7 "MIRROR THE CACHE WRITE ON CLIENTS" fix).
- Lifetime: session. Cleared only on peer disconnect (`:6837`, `PlayerManager.remove_player`) and a per-slot purge of `slot_hat` on career change (`:6319`, `_purge_stale_peer_slot`). It **survives level transitions** by design (`:7957`).
- `slot_name` key semantics differ by kind: `slot_hat`/`slot_skin` for hat/armor; for offhand/illusion the key is the **wielded weapon TEMPLATE key** (e.g. `one_handed_sword_shield_template_2`), because the emit sends the template as the slot (`:2793`, `:7934`).
- Written: host emit `:6029`, deferred drain `:6125`, req handler `:6812`, recv mirror `:6901`.
- Read: husk wield re-apply `:7359`, husk hat create_attachment `:7454`, transition reapply `:7979`-`8003`, pending-apply tick `:8102`, local-body wield re-apply `:8810`, `get_item_units` husk mesh-swap `:3902`, hot-join targeted replay `:7789`.

This is the closest thing to a single authoritative value, and the design
intent (host broadcasts, everyone mirrors) is correct. The problems below are
that it is **not the only store**, that **not every mutation reaches it** (revert
does not - #265), and that **not every render reconciles against it** (#264).

### 1.2 `_offhand_selection[backend_id][hand_field]` - LOCAL per-weapon-instance shield pick
- Value: the option record `{ name, la_armoury_key, vanilla_skin, intended_unit, kind, ... }`. Declared `:2452`.
- Owner: **local only.** Keyed by the weapon's `backend_id` (per-instance), then by hand.
- Lifetime: session, in-memory. Never networked. Never persisted (LA illusions persist via a separate file, 1.10).
- Written: auto-select on customization open `:3393`, user press `:3638`, legacy migration `:2460`.
- Read: `get_item_units` resolve for the local body `:3380`/`:4091`, self-rebroadcast drain `:7927`, hot-join replay `:7829`, paint-skip check `:4906`.
- Cleared: `_restore_offhand_selection` on un-Applied exit `:2502`/`:2767`; stale-mesh discard during setup (`LA_SYNC_MODEL.md` 6.5 "Stale `_offhand_selection` entries ... discarded").

This is the local body's source of truth for shields, and it is a **different
store, keyed differently (backend_id vs template), than 1.1.** The local player
therefore has two independent records of their own shield.

### 1.3 `_local_la_equips[player_unit][slot]` - LOCAL hat/armor/illusion bid cache
- Value: the LA clone `backend_id`. Weak-keyed by unit, declared `:2522`.
- Owner: local. Populated only by the local player's `CosmeticUtils.update_cosmetic_slot` hook (`:5707` hat/armor, `:5733` illusion).
- Lifetime: session. Cleared on a vanilla re-equip over an LA item (`:5762`) - **local clear only, no broadcast**.
- Read: self-rebroadcast drain `:7894`, hot-join replay `:7758`.

A third store. For the local player's hat/armor/illusion it overlaps 1.1 but is
keyed by unit+slot and holds a bid, not the resolved `{kind, armoury_key}`.

### 1.4 `mod.loadout_cache[career_name][slot_name]` - LOCAL LA-bid-per-career
- Value: LA clone `backend_id`. Declared `:5454`, written by `BackendInterfaceItemPlayfab.set_loadout_item` hook `:5481`.
- Owner: local. Exists so the `get_loadout` net-safe rewrite (which swaps LA bids back to vanilla for wire safety, `:5522`) does not erase the local player's own LA hat/armor: the bids are re-injected on `get_loadout` (`:5531`) and consulted by the bridge's `find_active_clone_for_unit_path` (`_la_bridge.lua:686`).
- Cleared: LA-to-vanilla on `slot_hat`/`slot_skin` `:5487`.

A fourth store overlapping 1.1/1.3 for hat/armor.

### 1.5 `mod._pending_la_emit_on_exit[bid|hand]` - deferred offhand broadcast
- Value: `{ player_unit, weapon_key, template_key, hand_field, armoury_key, vanilla_key }`. Written on offhand press `:3726`.
- Owner: local, transient (customization-screen lifetime).
- Drained on `on_exit` `:2778` (fires `_send_la_apply` for weapon_key AND template_key, `:2790`/`:2793`).
- Cleared without sending if the pick was not Applied `:2768`; a vanilla press supersedes a queued LA entry `:3760`.

### 1.6 `_la_pending_apply[]` - apply retry queue
- Value: tuple `{ wearer, slot, kind, armoury, vanilla, deadline }`. Declared `:5914`.
- Written on recv-time apply failure (wearer not spawned) `:6999`, and on husk-hat skeleton-not-ready defer `:7569`.
- Drained per-frame with a 5s TTL `:8085`; the drain also drives a mesh re-swap via `_ensure_offhand_mesh` `:8099`.

### 1.7 `mod._la_deferred_emits[]` - client emit retry (no host yet)
- Written when a client has no resolvable host peer id at emit time `:6070`; drained `:6101` with a 300s TTL.

### 1.8 `_current_husk_wield` - thread-local husk-wield context
- Value: `{ wearer_peer, husk_unit, slot_name }`. Declared `:3880`, set around the husk `_wield_slot` body `:7249`, restored `:7344`.
- Read by the `BackendUtils.get_item_units` hook to decide the husk mesh-swap `:3900`.

### 1.9 Apply-gate snapshots: `mod._offhand_baseline[bid]` / `mod._offhand_committed[bid]`
- Baseline snapshot of `_offhand_selection` taken on screen open `:3438`; commit flag set on a genuine Apply. Used by `on_exit` to revert an un-Applied pick `:2764`. Cleared on exit `:2936`.

### 1.10 Persistence file - `la_persisted_equips` VMF setting
- Shape: `{ schema, careers = { [career] = { slot_hat, slot_skin } }, illusions = { [backend_id] = la_skin } }` (`_la_persistence.lua:9-14`).
- Owner: local, persistent across restarts.
- Written: `save_cosmetic` `_la_persistence.lua:102` (from the CosmeticUtils hook `:5714`), `save_illusion` `:131` (`:5745`). Cleared on vanilla revert `:5769` and `:113`/`:140`.
- Read: `restore_for_player` on player spawn (`_la_persistence.lua:168`, hooked at `extensions_ready` `:213`) and as an injection into `update_cosmetic_slot` on first equip `:5625`.

### 1.11 `_la_reapply_remote_until` / `_la_self_rebroadcast_pending` - transition timers
- `_la_self_rebroadcast_pending` armed on every game-state change `:884`, drained in `mod.update` `:7881` (re-emits the LOCAL player's equips from 1.3 and 1.2).
- `_la_reapply_remote_until` armed to `os.clock()+10` on every game-state change `:899`, drained `:7968` (re-applies REMOTE peers' offhand meshes from 1.1). This is in-flight fix #1.

### 1.12 Minor/parallel state
- `_last_emit_at[dedup_key]` emit-dedup window (0.5s) `:5990`, purged per-peer on disconnect `:6839`.
- `_offhand_reswap_state` (weak) per-owner pulse cooldown/try-cap `:6697`.
- `mod._glow_by_peer` - the glow channel's parallel of 1.1 (`:6849`); out of LA-cosmetic scope but structurally identical, and a candidate to fold into the same core.
- `LA_BRIDGE.backend_to_armoury` / `backend_to_vanilla` / `armoury_to_backend` / `unit_path_to_clones` - static registry maps built once at `register_all` (`_la_bridge.lua:571`); not per-peer runtime state.

### 1.13 Where two states can disagree (the core of the problem)

| # | Store A | Store B | How they diverge | Bug |
|---|---|---|---|---|
| D1 | `_offhand_selection[bid][hand]` (local, per-instance) `:2452` | `_la_equips_by_peer[local_peer][template]` (synced) `:5910` | Local body reads A to resolve/paint its own shield (`:3380`), but the peer-facing truth is B. On mission-entry / weapon-switch the local body has no re-apply from A, so A's paint is lost while B is intact. | #203 |
| D2 | `_offhand_selection` reverted to baseline on exit `:2767` | `_la_equips_by_peer` on **remote** peers still holds the prior LA key | Reverting the local pick does not send anything (`:2768` drops the queued emit), so remote peers keep the stale cosmetic forever. | #265 |
| D3 | `_local_la_equips[unit][slot]` cleared locally on vanilla revert `:5762` | `_la_equips_by_peer[peer][slot]` (synced) never cleared | Same as D2 for hat/armor: the local cache clear has no matching broadcast. | #265 (hat/armor analogue) |
| D4 | `_la_equips_by_peer` (host, updated on emit) | `_la_equips_by_peer` (client, updated on broadcast) | On a level transition the host's post-transition broadcast races ahead of a still-loading client and is dropped; nothing re-sends, so the client's copy goes stale relative to the host's rendered shield. | #233 |
| D5 | Rendered mesh on a husk (set once at `get_item_units` spawn) `:3900` | `_la_equips_by_peer[wearer][slot]` desired value | The store updates on every `cos_la_apply`, but the mesh only swaps at a spawn/wield; a mid-mission skin-to-skin change or a switch-back re-wield can leave the rendered mesh pointing at the previous model while the store already holds the new one. | #234, #264, #233 |
| D6 | `_la_equips_by_peer` slot key = wielded **template** (offhand) `:2793` | `_offhand_selection` key = **backend_id** | Two shields sharing a template collide in B; two instances of the same item_type were the v0.9.8.9 mirror-write crash (`:3650-3660`). Key spaces are not the same dimension. | latent |
| D7 | Persistence file `illusions[bid]` `:131` | live `_local_la_equips` / `_offhand_selection` | Restore path re-injects on first equip `:5625`; if the live pick changed without a save/clear the two disagree until next equip. | latent |

The headline: **there are five overlapping runtime stores (1.1-1.4, plus the
persistence file) for "what cosmetic does peer P want in slot S", each keyed
differently, each written by a different subset of events.** No single function
can answer the question, and no single function is responsible for keeping them
in agreement. Every open issue is a specific pair of them drifting.

---

## 2. Event x action inventory (as-is)

For each event that can change what a peer should see, what does the **wearer's**
machine do, and what does each **remote viewer's** machine do. "Emit" = a
`cos_la_apply(_req)` broadcast fires. "Reconcile" = the rendered unit is
re-derived from a store. Cells marked with a bug ref are known-broken; cells
marked `[gap]` are untested/absent mechanisms that are the next reports.

| Event | Wearer machine | Remote viewer machine | Veto/gate | Proof tag | Bug |
|---|---|---|---|---|---|
| Local equip LA **hat**/armor (menu) | `CosmeticUtils.update_cosmetic_slot` hook subs LA->vanilla, records `_local_la_equips` `:5707`, emits `:5709`, persists `:5714` | recv mirrors cache `:6901`, `_apply_la_on_unit` hat/armor `:6404`/`:6540`; husk `create_attachment` pre-patch `:7431` | char-mismatch gate `:6456`/`:7501`; skeleton-ready gate `:7555` | `[cos-la-sync] RECV` `:6927` | ok |
| Local equip LA **offhand shield** (menu, Apply) | local write `_offhand_selection` `:3638`; broadcast **deferred** to `on_exit` `:3726`; on exit emits weapon+template `:2790` and pulse-wields local body `:2913` | recv mirrors `:6901`; `_apply_la_on_unit` offhand paints wielded left unit `:6555`, mesh-gated `:6595`; husk `_wield_slot` re-applies `:7359`; kind=unit mesh swap in `get_item_units` `:3900`; recv also pulses `_ensure_offhand_mesh` on **every player at the wearer peer** `:6989` (host peer owns bots -> pulses bot units too) | offhand paint mesh-gate `:6595` (#204); **no wearer-scoping on the recv pulse `:6989`** | `RECV` `:6927`, `RE-SWAP` `:6758` | #204, #233, **#268** |
| Local equip LA **weapon illusion** (row-1) | CosmeticUtils hook subs skin `:5677`, records `_local_la_equips` `:5733`, emits kind=illusion `:5735`, persists `:5745` | recv mirrors `:6901`; `_apply_la_on_unit` illusion via LA paint `:6634`; husk `_wield_slot` re-apply `:7359` | none on paint | `RECV` `:6927` | #264 (switch-back) |
| **Revert to vanilla hat/armor** (menu) | local `_local_la_equips[slot]=nil` `:5762`, persistence clear `:5769`. **No emit.** | nothing (no broadcast arrives) - keeps stale LA | - | `clearing stale LA cache entry` `:5760` | **#265** |
| **Revert to vanilla offhand** (menu) | un-Applied: `_offhand_selection` reverted `:2767`, queued emit dropped `:2768`. Applied vanilla press: supersedes queued LA `:3760`. **No revert emit either way.** | nothing - keeps stale LA (`_la_equips_by_peer` never told) | - | `EXIT-QUEUE CLEAR` `:3757` | **#265** |
| **Weapon-slot switch away** (mission) | local `_wield_slot` fires `:8780` (diagnostics + offhand re-apply for the now-wielded slot) | husk `_wield_slot` fires `:7225`, sets `_current_husk_wield`, re-applies cached equips for the newly wielded template `:7359` | mesh-gate `:6595` | `HUSK wield_slot` `:7245` | - |
| **Weapon-slot switch back** to LA-cosmetic'd weapon (mission) | local `_wield_slot` re-applies offhand from `_la_equips_by_peer[local]` `:8810` (offhand only; illusion excluded `:8819`) | husk `_wield_slot` re-apply keyed `stored_key==wielded_template` `:7373`; **no emit (wearer changed nothing)** | template-equality match `:7373` | `HUSK wield-repaint` `:7382` | **#264 (confirmed BOTH directions: client-switch->host-view AND host-switch->client-view, 21:41:01)** |
| **Wearer mid-mission cosmetic change** (customization on_exit in mission) | `on_exit` drains `_pending_la_emit_on_exit` -> `_send_la_apply` (client -> `cos_la_apply_req`) `:2790` | host should RECV+rebroadcast; **evidence: no host RECV, wearer's own echo 79s late** | emit routing invisible with mod logging off (`:6085` is `_dbg`) | `EMIT-ON-EXIT` `:2787` (visible); `CLIENT->req` `:6085` (invisible) | **mid-mission transport loss (#264 comment / #234)** |
| **keep -> mission** transition | `on_game_state_changed` arms self-rebroadcast `:884`; drain re-emits local equips `:7881` | `_la_reapply_remote_until` armed `:899`; drain pulses remote offhand meshes via `_ensure_offhand_mesh` `:8003` (in-flight fix #1) | mesh-already-correct/cooldown self-gate in `_ensure_offhand_mesh` `:6722` | `RE-SWAP tag=transition` `:6758` | #233 (fix in flight) |
| **mission -> keep** transition | same self-rebroadcast `:884` | same remote-reapply window `:899` | same | same | #149, #233 |
| **Fresh spawn** (mission start) | persistence restore for hat/armor `_la_persistence.lua:168`; local equips re-emit on state change `:7881` | recv apply fails if wearer not spawned -> queued `:6999`; retried `:8085` + mesh re-swap `:8099` | `_kind_unit_paint_is_safe` `:1227`(bridge); mesh-gate `:6595` | `pending/... deferred-reapply` `:7006` | #149, #154 |
| **Hot-join: existing peer's POV of joiner** | joiner's `hot_join_sync` fires its own emits `:7739`/`:7770`/`:7833` | host records + targeted-replays to joiner `:7794` | armoury_key known-to-LA check `:6807` | `hot-join replay sent N` `:7806` | - |
| **Hot-join: joiner's POV of existing peers** | existing peers re-emit on their next state change `:884`; host targeted-replays `:7794` | joiner recv applies `:6913` - BUT the re-emit/replay fires ~17ms BEFORE the joiner's `peer_ingame` flip, so the "all" send never reaches it, and the joiner's empty `_la_equips_by_peer` gives self-heal nothing to work from | send is not gated on receiver-confirmed-ingame | `hot-join replay` `:7806` | **#267** (v0.9.0.12 targeted replay does not fix the pre-ingame race) |
| **Career/hero switch** | new career's `_local_la_equips` empty until re-equip; persistence restore for the new career `_la_persistence.lua:176` | `slot_hat` purged from `_la_equips_by_peer` on career change `:6319`; char-mismatch gate blocks wrong-skeleton hat `:6456` | char-mismatch `:6456`/`:7501` | `character mismatch` `:6458` | #14 (closed) |
| **Peer disconnect** | - | `remove_player` purges `_la_equips_by_peer[peer]` `:6837`, `_last_emit_at` `:6839`, `_glow_by_peer` `:6849` | - | `peer ... left - purging` `:6836` | - |
| **Host migration** | `[unverified]` - no dedicated handler found; relies on next state-change self-rebroadcast `:884` and the new host's empty `_la_equips_by_peer` being refilled by each peer's re-emit | `[unverified]` same | - | - | `[gap]` |
| **Cross-char WEAPON cosmetic on a husk** (weapon_tweaker-owned, not LA) | wt owns the mesh; cosmetics only warns | husk `_wield_slot` preflight WARN if resolved unit non-resident `:7326`; cosmetics does NOT swap (correctly out of scope) `:7276` | read-only diagnostic | `PREFLIGHT WARN` `:7326` | #154 |

Four structural readings of this matrix:
- **The revert row is empty on the viewer side.** Every "equip" event has an emit
  and a remote apply; every "revert" event has neither. That asymmetry is
  invariant I2 (below) and it is #265.
- **Reconcile is wired per-trigger, not once.** There are now at least four
  separate call sites that force an offhand mesh to re-derive from the store -
  the recv handler `:6986`, the pending-apply drain `:8099`, the transition
  window `:8003`, and (for paint) the husk/local `_wield_slot` bodies
  `:7359`/`:8810`. Each was added for one reported trigger (#233 recv, #233
  transition, #203 local wield). A trigger nobody added yet (the mid-mission
  weapon-switch-back with no emit and no transition, #264) falls through all of
  them. That is invariant I3.
- **Broadcasts are fire-and-forget against an unconfirmed receiver.** Both the
  hot-join replay (`:7794`) and the state-change re-emit (`:884`) send the instant
  the peer appears, 17-25ms before the receiver flips `peer_ingame` (#267 hot-join,
  #233 transition). A dropped send has no ack and no re-send, and a hot-joiner has
  an empty store so it cannot self-heal. That is invariant I9.
- **Apply targets co-peer units, not just the wearer.** The recv-time pulse loops
  every player at the wearer peer (`:6989`); on a host that peer owns the bots, so
  one equip force-swaps bot shields to the wearer's mesh (#268). That is an I4
  targeting violation - the apply primitive must resolve the ONE wearer unit
  (`_wearer_unit_for_peer` `:5964` already does this; the recv loop does not use it).

---

## 3. Invariants (to-be)

The governing rules. Stated so that each is either provably held by construction
or has a single place to enforce it. I refined the lead's I1-I6 and split out two
more (I7 mesh-vs-paint atomicity was implicit in the #204/#233/#234 cluster; I8
persistence coherence).

- **I1 - Single authoritative value.** For every `(peer, slot)` there is exactly
  ONE desired-cosmetic value, and every machine can name it with one lookup.
  Today five stores (1.1-1.4 + persistence) answer this; the invariant demands
  one. `slot` is normalized to a stable key (hat/armor use the cosmetic slot;
  weapon-side uses a single agreed key - either backend_id everywhere or template
  everywhere, never both as today, D6).

- **I2 - Every mutation broadcasts, including revert.** Any change to the I1 value
  - apply AND revert-to-vanilla - produces exactly one authoritative broadcast.
  Revert is `set(peer, slot, nil)`: it deletes the remote store entry and
  restores the native mesh via the existing pulse. #265 exists precisely because
  revert mutates only local stores (`:5762`, `:2768`, `:3760`) and never sends.

- **I3 - Every render reconciles against the store.** Every wield/spawn/attach of
  a peer's cosmetic-bearing unit, on any machine, reconciles the rendered unit
  against the I1 value - regardless of how the render was triggered (spawn,
  transition, weapon switch, skin-to-skin change, recv). One `reconcile(peer,
  slot)` entry point, called from every such trigger. #233/#234/#264 are three
  triggers that some current path does not cover.

- **I4 - One apply path, one mesh gate, one target.** Painting a texture and
  swapping a mesh are one operation with one gate: paint never lands on a
  mismatched mesh (#204), and mesh-swap availability never depends on which code
  path arrived (spawn-time-only mesh swap is the root of #233/#234). The gate
  (`_offhand_paint_mesh_ok`, currently applied at `:6595` for local/husk paint but
  bypassed on the spawn mesh-swap decision) is part of the single apply primitive,
  not bolted onto each caller. **And apply targets exactly the wearer's unit for
  `(peer, slot)` - never co-peer units.** #268 is this clause: the recv pulse
  loops every player at the wearer peer (`:6989`), so on a host it force-swaps the
  host's bots' shields; the primitive must resolve the one wearer unit
  (`_wearer_unit_for_peer` `:5964`) and, for bots, only apply the bot's OWN stored
  value.

- **I5 - Weapon identity never affects availability or correctness.** Option lists
  and all equip/sync/paint/mesh logic are shared and keyed by `(hand,
  armoury_key, mesh_kind)`, never per-weapon. A fix for one Kruber shield weapon
  is automatically a fix for all of them; an illusion offered on one shield
  weapon is offered on all applicable ones. #266 is the data-and-mechanism
  parity statement of this.

- **I6 - Every decision logs.** Every apply/skip/gate/reconcile emits a
  console-log line (engine `printf`, visible with mod logging off) naming the
  decision and the reason. A silent no-op is a bug: the 0.9.65 transition walk
  shipped effectively dead because it could skip silently before instrumentation
  was added. `[unverified]` decisions must degrade loudly, not quietly.

- **I7 - Mesh and paint are atomic per apply.** For a `kind="unit"` variant, the
  mesh swap and the heraldry paint either both happen or the apply reports "mesh
  not ready" and defers - never "painted onto the old mesh" (#204) and never
  "mesh swapped, paint refused, no retry" (#233). This is the corollary of I4 at
  the primitive level and is the reason the four scattered `_ensure_offhand_mesh`
  callers exist; under I3 they collapse into `reconcile`.

- **I8 - Persistence mirrors the authoritative value.** The on-disk store
  (1.10) is written by the same setter as I1 (apply writes, revert clears) so it
  can never hold a cosmetic the live value already dropped. Restore is just
  `set(local_peer, slot, saved)` at spawn, feeding the same broadcast+reconcile
  as any other mutation - not a separate injection path (`:5625`).

- **I9 - Delivery is confirmed, not fire-and-forget.** A broadcast either lands
  after the receiver is confirmed ingame, or the receiver pulls the full store on
  ready. A send timed off "peer appeared" is not delivery - the joiner/transitioning
  peer flips `peer_ingame` 17-25ms later (#267, #233) and the packet is lost with no
  ack and no re-send. Because a hot-joiner starts with an empty `_la_equips_by_peer`,
  cache self-heal cannot cover it: the correct shape is a joiner-driven **pull on
  ready** (joiner requests the full state once it is ingame) or a host **re-push
  gated on the joiner's confirmed-ingame flag**, not the current bare re-emit.

---

## 4. Bug-to-invariant map

| Issue | One-line symptom | Invariant(s) violated | Why the shipped/attempted fix was a point patch, not an invariant restoration |
|---|---|---|---|
| **#149** | LA shield reverts to default at mission start; host/client diverge | I3, I7 | Fixed by allowing the `network_husk`/`ingame` paint post-spawn (`_la_bridge.lua:1335`) + a pending-apply retry `:6999`. Restores rendering for the mission-start trigger only; every other non-spawn trigger needed its own patch afterward (#203/#233/#264). |
| **#154** | Cross-char WEAPON cosmetic not on husks; empty husk cache + non-resident unit | I1 (store has no entry), I3 | Correctly out of cosmetics' scope (weapon meshes are wt's, `:7276`); the mod only added a diagnostic `:7326`. But the shared root - "reconcile on wield finds an empty cache" - is the same I3 gap as the shield cases, in a store cosmetics does not own. |
| **#203** | Local player's own shield drops in-mission on entry + weapon switch-back | I3 (local body never reconciled) | v0.9.54 mirrored the husk re-apply into the LOCAL `_wield_slot` `:8794`. That is exactly "add reconcile to one more trigger" - it patched the local body's wield, leaving other local triggers (skin-to-skin, transition) to later fixes. Also exposed D1 (local body reads `_offhand_selection`, peers read `_la_equips_by_peer`). |
| **#204** | LA shield texture warps onto the un-swapped (wrong) mesh on peers | I4, I7 | v0.9.54 added `_offhand_paint_mesh_ok` to the husk/local paint `:6595`. Correct guard, but it is a guard bolted onto the paint caller, not a property of a single apply primitive - so the spawn-time mesh-swap decision (a different caller) still lacks it, which is #233/#234. |
| **#233** | Host's LA shield invisible to client at mission start; RECV lands, mesh never swapped, paint gate SKIPs | I3, I4, I7, I2 (transition re-send dropped) | In-flight fix #1 arms a bounded client-side re-apply window `:899`/`:7968` that pulses `_ensure_offhand_mesh`. This is a **fourth** per-trigger reconcile caller. It fixes the transition trigger; it does not make reconcile-on-every-wield a property of the system, so #264 (a non-transition trigger) survives it. |
| **#234** | Mid-mission LA skin-to-skin swap fails when the shield MODEL changes | I3, I7 | Same root as #233: mesh swaps only at spawn-time `get_item_units`; a same-weapon skin change only texture-paints and the #204 gate (correctly) refuses. `_ensure_offhand_mesh` at recv `:6986` is meant to cover it but is gated to kind=unit + package-resident + cooldown, and only fires from the recv path. |
| **#235** | In-mission cosmetic 3D preview panel blank/black | **none of I1-I8** | Not a sync-state bug. It is the in-mission preview world carrying a 2D tonemapping env (`ui_hdr`) with no 3D light (`:2597-2609`). In-flight fix #2 instruments this. Listed here only to record that it must NOT be folded into the state core. |
| **#264** | Weapon switch-back to an LA-cosmetic'd weapon: gone on peers' screens (**confirmed both directions**: client-switch and host-switch, 21:41:01) | I3 (reconcile-on-wield does not cover switch-back) | Open. The husk `_wield_slot` re-apply exists `:7359` but matches on `stored_key == wielded_template` `:7373` and no emit fires (wearer changed nothing); the switch-back wield evidently does not re-derive the mesh. The exact miss is `[unverified]` pending the fix, but the class is unambiguous: a wield trigger with no covering reconcile. The bidirectional confirmation rules out any host-vs-client asymmetry - it is purely the missing reconcile-on-wield. |
| **#264 comment** (mid-mission emit loss) | Wearer's mission-time cosmetic change never reaches the host: `EMIT-ON-EXIT` fires (21:41:18/21:42:31/21:42:42) but no host `RECV`; wearer's own echo 79s late | I2/I3 upstream at the **transport** link, plus I6 | Open. Distinct from #264's render gap: here the mutation does not even reach the store on other machines. The visible evidence (EMIT-ON-EXIT present `:2787`, host RECV absent, self-echo +79s) points at the client emit routing / deferred-emit queue (`_send_la_apply` `:6062` -> deferred `_la_deferred_emits` `:6070`, 300s TTL drain `:6101`), whose 79s-late self-echo matches a queue that drained long after the emit. The host-RECV absence is **inconclusive** because the host's RECV log is deduped on `(wearer,slot,armoury,applied)` `:6921` and the same tuple was logged earlier (keep equip). Decisive proof is blocked by I6: the emit-routing branch (`CLIENT->req` vs `DEFERRED+queued`) logs only via `_dbg`/`_trace` (`:6080`/`:6085`), invisible with mod logging off. Fix step 1 is a `printf` on that branch. |
| **#265** | Revert LA->vanilla never propagates; peers keep the stale LA cosmetic | **I2** (and I1: revert only touches local stores) | Open. This is the cleanest single-invariant case: the emit pipeline broadcasts APPLY only. Revert paths clear local state (`:5762` hat/armor, `:2768`/`:3760` offhand) and send nothing, so remote `_la_equips_by_peer` retains the entry until disconnect. |
| **#266** | Availability + fix parity across all Kruber shield weapons | **I5** | Directive, not a bug. Today offhand pools are built per weapon-type with cross-pollination tables (`_la_bridge.lua:333`-`485`) and several fixes were keyed to a weapon (bret vs empire). I5 makes the option set and every fix shared by `(hand, armoury_key, kind)`. |
| **#267** (new) | Hot-joiner never renders the host's already-equipped LA skin | **I9** (delivery timing) | Open. The join self-re-emit DOES exist and fired - 17ms before the joiner's `peer_ingame` flip (21:36:53.220 vs .237), so the "all" send never reached it, and the empty joiner store makes self-heal impossible. The existing v0.9.0.12 targeted replay `:7794` is still a bare fire-and-forget send, not gated on confirmed-ingame - same race as #233. Needs pull-on-ready or confirmed-ready re-push, not another timing tweak. |
| **#268** (new, wire-only) | One equip force-swaps co-peer BOT shields to the wearer's mesh | **I4** (targeting) | Open. The recv-time pulse loops every player at the wearer peer (`pm:players_at_peer(wearer)` -> `for _,p ... _ensure_offhand_mesh(p.player_unit,...)` `:6989`); a host peer owns its bots, so a single host shield equip pulses the bots too (Saltzpyre bot's WH shield -> Kruber empire mesh, ok=true). `_ensure_offhand_mesh` only checks mesh-already-correct/cooldown, never that this unit's wearer matches the equip. Likely the real mechanism behind several #204 "stretched skin" sightings (a bot rendered a wearer's texture on the wrong mesh). Fix: resolve the ONE wearer unit and apply each bot only its OWN stored value. |

Pattern across the column: with the sole exception of #265/#264-comment (I2 apply
asymmetry) and #235 (not a sync bug), **every issue is an I3 gap - a render
trigger that some code path does not reconcile - an I4/I7 gap - mesh and paint not
treated as one gated operation targeting exactly the wearer - or an I9 gap - a
broadcast that races the receiver's ready state.** The fixes have been "add
reconcile to trigger N", "add the gate to caller M", and "re-emit on event K",
which is why siblings keep recurring: N, M, and K are unbounded sets as long as
reconcile, apply, and delivery are scattered.

---

## 5. Consolidation design (to-be)

Make I1-I9 hold by construction with a single owned module. Nothing about the
wire format or the persistence format changes, so migration is shippable in
slices (section 6).

### 5.1 One module: `_la_state.lua`

A new file `scripts/mods/cosmetics_tweaker/_la_state.lua`, `mod:dofile`'d ONCE
and stored on `mod` (heed `reference_vmf_dofile_not_singleton.md`: `dofile`
returns a fresh module per call, so exactly one require site, kept on `mod._la_state`).

It owns exactly one runtime store and exposes a tiny surface:

```
M.store            -- = _la_equips_by_peer, the ONLY per-(peer,slot) desired value (I1)
M.set(peer, slot, desired)   -- desired = {kind,armoury_key,vanilla_key,hand_field} or nil
M.get(peer, slot)
M.reconcile(peer, slot)      -- re-derive the rendered unit from the store (I3/I4/I7)
M.reconcile_all(unit_or_peer)
```

- **`set(peer, slot, desired)`** is the single mutation point (I1/I2). It writes
  `store[peer][slot]`, persists via `LA_PERSIST` when `peer==local` (I8), and
  ALWAYS broadcasts: if we are host it sends `cos_la_apply` to `"all"`; if client
  it sends `cos_la_apply_req` to the host (the existing routing at `:6026`/`:6089`).
  `desired == nil` is revert: it deletes the store entry, broadcasts a nil-key
  apply (schema already tolerates optional fields), and the receiver's reconcile
  restores the native mesh via the existing pulse. **This one function closes
  #265** and removes the three local-only clear sites (`:5762`, `:2768`, `:3760`).

- **`reconcile(peer, slot)`** is the single render-derivation point (I3/I4). It
  reads `store[peer][slot]`, resolves **the one wearer unit** for that peer
  (`_wearer_unit_for_peer` `:5964`, NOT a `players_at_peer` sweep), and calls the
  single apply primitive (5.2). For a host-owned bot it reconciles that bot only
  against the bot's OWN `(peer, slot)` value - never a co-peer's - which closes
  #268 by construction (the current recv loop at `:6989` force-swaps every player
  at the peer). It is idempotent and self-gating (mesh-already-correct no-op,
  per-owner cooldown - the logic already in `_ensure_offhand_mesh` `:6700`-`6762`).
  Every existing render trigger calls it instead of its own bespoke re-apply:

| Existing trigger | Today | Under reconcile |
|---|---|---|
| `cos_la_apply` recv `:6913` | `_try_apply_by_peer` + `_ensure_offhand_mesh` `:6986` | `reconcile(wearer, slot)` |
| pending-apply drain `:8085` | `_try_apply_by_peer` + `_ensure_offhand_mesh` `:8099` | `reconcile` per queued entry |
| husk `_wield_slot` `:7359` | inline loop over cached equips | `reconcile(wearer, wielded_slot)` |
| local `_wield_slot` `:8794` | inline offhand re-apply | `reconcile(local, wielded_slot)` |
| husk hat `create_attachment` `:7431` | inline pre-patch + paint | `reconcile(wearer, slot_hat)` (pre-patch stays as the primitive's hat path) |
| transition window `:7968` (in-flight #1) | `_ensure_offhand_mesh` loop | `reconcile_all` over remote peers |
| spawn / `extensions_ready` `:6271` | spawn monitor | `reconcile_all(unit)` |

  #264 is closed because the weapon-switch-back wield is just another caller of
  `reconcile(wearer, wielded_slot)` - it no longer depends on an emit or a
  transition having happened.

### 5.2 One gated apply/mesh primitive

`reconcile` calls one primitive that, per `kind`, does mesh-swap AND paint as a
single gated unit (I4/I7):
- `kind="unit"` offhand: if the live mesh already matches the variant's
  `new_units`, no-op; else pulse-wield to re-run `get_item_units` (the sanctioned
  re-trigger, `_ensure_offhand_mesh` `:6755`), THEN paint - and the paint's
  mesh-gate (`_offhand_paint_mesh_ok`) lives inside the primitive so it is
  identical on spawn, wield, recv, and transition. This is the hard constraint the
  design must respect: **kind=unit meshes swap only via the `get_item_units`
  spawn path; the re-equip pulse is the only sanctioned re-trigger** (no
  `World.destroy_unit`, `:6682`). The primitive owns that pulse; callers never
  pulse directly.
- `kind="texture"` offhand: paint only, no pulse.
- hat: the existing `create_attachment` pre-patch + `apply_new_skin_from_texture`
  (`:6503`/`:7596`), behind the existing char-mismatch and skeleton-ready gates
  (`:6456`, `:7555`).
- armor / illusion: existing `apply_new_skin_from_texture` calls (`:6546`/`:6651`).

### 5.3 One shared option table keyed by `(hand, armoury_key, kind)` - #266

Replace the per-weapon-type pools + cross-pollination tables
(`_la_bridge.lua:306`-`539`) with a single per-character shield option set that is
offered identically on every applicable shield weapon for that character (I5).
The mesh-family split that currently gates cross-pollination
(`_LA_CHARACTER_SHIELD_FAMILIES` `:333`) is preserved as a **texture-correctness
property of the variant** (a kind=texture variant is only paint-valid on its
authored mesh family), not as a per-weapon list - so availability is uniform and
correctness is a property of the variant, not the weapon.

### 5.4 Confirmed delivery: pull-on-ready (I9) - closes #267, hardens #233

The one place where "one store + one setter + one reconcile" is not enough: a
peer that is not yet ingame cannot receive a push, and a hot-joiner has an empty
store so it cannot self-heal. Add one delivery primitive:

- **Joiner pull.** When a peer's OWN `on_game_state_changed` reaches the ingame
  state (`:851`), it sends one `cos_la_state_req` to the host. The host replies
  with a targeted `cos_la_apply` per `(peer, slot)` in `M.store` (the existing
  targeted-replay body at `:7789`-`7809`, but triggered by the joiner's confirmed
  ready instead of the host's guess about when the joiner appeared). Reuses the
  existing `cos_la_apply` broadcast, so no new render path.
- **This replaces the timing guesses**, not adds to them: the state-change
  self-rebroadcast (`:884`) and the hot-join targeted replay (`:7794`) both become
  redundant with a pull that fires exactly when the joiner is provably ready. Keep
  one bounded re-push as belt-and-suspenders (idempotent), but the pull is the
  correctness path.
- Respects the constraints: reuses `COS_RPC_SCHEMA`, adds one request RPC name
  (`cos_la_state_req`) analogous to the existing `cos_la_apply_req`, no new render
  path, no force-loads.

### 5.5 What gets DELETED / merged
- The three redundant local stores for hat/armor/illusion: `_local_la_equips`
  (1.3) and the parts of `loadout_cache` (1.4) used for LA replay collapse into
  reads of `M.store`. `loadout_cache`'s net-safe `get_loadout` role stays (that is
  a wire-safety concern, not cosmetic state).
- `_offhand_selection` (1.2) stays as the customization-UI's local pick buffer
  ONLY (it drives the previewer and the Apply commit), but on Apply it calls
  `M.set(local, slot, ...)` and stops being a parallel authoritative store - D1/D6
  dissolve because the body's rendered shield derives from `M.store`, not from
  `_offhand_selection`.
- The four scattered `_ensure_offhand_mesh` call sites (`:6986`, `:8099`,
  `:8003`, plus the local/husk wield inline loops) collapse into `reconcile`.
- The three revert-clear sites (`:5762`, `:2768`, `:3760`) collapse into
  `M.set(..., nil)`.

### 5.6 What explicitly does NOT change (keeps migration shippable)
- RPC names and schema: `cos_la_apply`, `cos_la_apply_req`, `COS_RPC_SCHEMA`
  stay unchanged. `set` sends the same payload shape (`:6038`); revert reuses it
  with a nil armoury_key (already tolerated by the optional-field decode `:6881`).
  The only additive wire change is one new request RPC `cos_la_state_req` (5.4),
  shaped exactly like the existing `cos_la_apply_req`; existing peers ignore an
  unknown RPC, so it is backward-compatible.
- Persistence format `la_persisted_equips` (1.10) stays byte-compatible.
- The hard engine constraints are respected: kind=unit mesh swap only via the
  `get_item_units` spawn path + re-equip pulse (`:6672`-`6695`); no
  `World.destroy_unit`; no package force-loads beyond the existing idempotent
  `_force_load_all_offhand_packages` (`:8059`); VMF duplicate `hook_safe` on a
  `(Class,method)` silently drops (so the existing single hooks on
  `SimpleHuskInventoryExtension._wield_slot` / `SimpleInventoryExtension._wield_slot`
  / `PlayerHuskAttachmentExtension.create_attachment` are re-used, not
  re-registered); networked hooks keep passing `skip_sync`/multi-returns through
  (`:7343`/`:7392`); diagnostics reach the console via `printf` (I6); the Lua
  200-local ceiling means `_la_state.lua` is its own chunk (its locals do not
  count against the main file, which is already near the limit -
  `reference_cwv_lua_200_local_ceiling.md` pattern).
- `#235` preview lighting is untouched by this work (different subsystem).

---

## 6. Migration plan

Ordered, each slice = one dev build the user can verify in-game. Riskier
consolidations land AFTER the diagnostics that would catch their failure. Scope
is an estimate of functions/lines touched.

**Slice 0 - Instrument the store + the emit routing (no behavior change). ~40 lines.**
Add a `printf` line to every current write of `_la_equips_by_peer` (`:6029`,
`:6125`, `:6812`, `:6901`) and every reconcile/apply decision that lacks one,
tagged `[la-state]`. **Also convert the two invisible emit-routing branches in
`_send_la_apply` to `printf` (`CLIENT->req` `:6085`, `DEFERRED+queued` `:6080`)
and add a host-side `printf` in the `cos_la_apply_req` handler `:6766` BEFORE the
recv-dedup.** This is what indicts the mid-mission transport-loss link (#264
comment): today the routing decision is `_dbg`/`_trace` (invisible with mod
logging off), so the user's log cannot show whether the client sent the req, the
host received it, or the host deduped its own echo. Gives a ground-truth trace of
store, render, AND transport before anything moves. Verify: the next mid-mission
wearer change shows exactly one of {client-req-sent, deferred, host-received} in
the log. (I6 first, so later slices' failures are visible.)

**Slice 1 - Revert broadcast (closes #265). ~40 lines, isolated.**
Introduce `M.set(peer, slot, desired)` wrapping the existing emit routing, with
`desired==nil` sending a revert. Route the three revert-clear sites (`:5762`,
`:2768`, `:3760`) and the CosmeticUtils vanilla-revert path through it. Do NOT yet
touch reconcile or the other stores. This is the highest-value, lowest-risk
slice: one invariant (I2), one user-visible bug, no render-path change. Verify:
host reverts an LA shield/hat, client's view returns to vanilla without a
disconnect.

**Slice 2 - Single reconcile entry point, wearer-scoped (closes #264 and #268, hardens #233/#234). ~130 lines.**
Extract `reconcile(peer, slot)` from the existing `_apply_la_on_unit` +
`_ensure_offhand_mesh` + husk re-apply logic (no new engine calls - it is the
same pulse + paint, relocated). **Resolve exactly the one wearer unit
(`_wearer_unit_for_peer` `:5964`); do NOT loop `players_at_peer` - that closes
#268** (the recv pulse at `:6989` currently force-swaps a host's bots). Repoint the
recv handler `:6986`, pending drain `:8099`, husk `_wield_slot` `:7359`, local
`_wield_slot` `:8794`, and the transition window `:8003` to call it. Land AFTER
slice 0 so a reconcile that skips is visible. This is the riskiest slice (touches
every render trigger); its safety net is slice 0's trace. Verify: mid-mission
skin-to-skin (#234), weapon switch-back both directions (#264), transition (#233)
all re-render on peers, AND no bot shield changes when a player equips (#268 -
check the log for `RE-SWAP` on only the wearer's owner unit).

**Slice 2b - Confirmed delivery / pull-on-ready (closes #267). ~50 lines.**
Add the `cos_la_state_req` request RPC (5.4): a peer sends it from its OWN
`on_game_state_changed` ingame flip (`:851`), the host replies with a targeted
`cos_la_apply` per `(peer, slot)` reusing the body at `:7789`. Land right after
Slice 2 so the joiner's replies drive the now-unified `reconcile`. This retires
the pre-ingame race for hot-join (#267) and transition (#233) by making delivery
depend on the receiver's confirmed-ready, not the sender's timing guess. Verify:
a peer joins a lobby where the host already wears an LA skin and renders it
without anyone re-equipping.

**Slice 3 - Fold the apply/mesh gate into the primitive (locks I4/I7). ~60 lines.**
Move `_offhand_paint_mesh_ok` inside the single apply primitive so mesh-swap and
paint share one gate on every path, including the spawn-time `get_item_units`
mesh-swap decision (`:3900`). Removes the possibility of a new caller forgetting
the gate. Verify: no warp on any shield weapon on any trigger (#204 generalized).

**Slice 4 - Collapse redundant local stores. ~80 lines, mechanical.**
Retire `_local_la_equips` (1.3) and the LA-replay use of `loadout_cache` (1.4) in
favor of `M.store` reads; keep `_offhand_selection` as a UI-only buffer that calls
`M.set` on Apply. Land last among the state slices because it is the widest edit
and purely a dedup once `set`/`reconcile` are the single paths. Verify: hot-join,
self-rebroadcast, persistence restore all still sync (they now read one store).

**Slice 5 - Persistence through `set` (I8). ~30 lines.**
Make restore-on-spawn call `M.set(local, slot, saved)` instead of the separate
`update_cosmetic_slot` injection (`:5625`), so persisted state enters the same
broadcast+reconcile pipeline. Verify: an LA hat/shield saved last session applies
AND syncs to peers on spawn without a manual re-equip.

**Slice 6 - Data + mechanism parity for Kruber shields (#266, I5). ~100 lines.**
Replace the per-weapon-type offhand pools + cross-pollination tables
(`_la_bridge.lua:306`-`539`) with one shared per-character option set keyed by
`(hand, armoury_key, kind)`, offered identically on all applicable Kruber shield
weapons. By this point every fix already lives in shared `set`/`reconcile`/apply
code, so mechanism parity is already true; this slice delivers data parity and
proves it with `/la_offhand_dump` (`_la_bridge.lua:545`) showing an identical
armoury-key set across `es_1h_sword_shield`, `es_1h_mace_shield`,
`es_1h_sword_shield_breton`, and `es_deus_01`.

**Not in this plan:** #235 (preview lighting - separate subsystem, in-flight fix
#2) and #154 (cross-char WEAPON mesh - weapon_tweaker-owned; once `reconcile`
exists, wt can call an analogous reconcile for its own store, but the mesh
ownership stays with wt).

---

## Appendix: executive summary

Three worst structural findings:
1. **Five overlapping stores, no single owner** (section 1.13). `_la_equips_by_peer`,
   `_offhand_selection`, `_local_la_equips`, `loadout_cache`, and the persistence
   file each answer "what cosmetic does peer P want in slot S" with a different
   key space and a different write set. No function keeps them in agreement; every
   open issue is a specific pair drifting.
2. **Revert never broadcasts** (I2). Every equip path emits; every revert path
   clears local state only (`:5762`, `:2768`, `:3760`). That single asymmetry is
   #265 and is the cleanest one-invariant fix in the set.
3. **Reconcile is wired per-trigger, not once** (I3). Four+ separate re-apply call
   sites, each added for one reported trigger; a trigger nobody added yet (#264
   weapon switch-back, now confirmed both directions) falls through all of them.
   #149/#203/#233/#234/#264 are all this one structural gap.

The 2026-07-03 21:30 session added two more structural axes, both folded above:
**delivery is fire-and-forget against an unconfirmed receiver** (I9 - the send
races the peer's `peer_ingame` flip by 17-25ms; #267 hot-join and #233 transition),
and **apply targets co-peer bot units, not just the wearer** (I4 targeting - one
host equip force-swaps the host's bots' shields; #268). It also surfaced a
mid-mission wearer-change **transport loss** (#264 comment) whose decisive proof
is currently blocked by I6 (the emit-routing branch logs only invisibly), which is
why Slice 0 now also instruments the emit path.

Recommended first migration slice: **Slice 1 (revert broadcast, closes #265)** -
highest value, lowest risk, one invariant, no render-path change - preceded by
**Slice 0 (instrument the store + emit routing)** so the riskier reconcile
consolidation (Slice 2, which also closes #268 by wearer-scoping) fails loudly
rather than silently, and so the mid-mission transport loss is pinned to a link.
