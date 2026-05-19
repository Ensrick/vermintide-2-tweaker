# cosmetics_tweaker × LA host/client sync — Prior Attempts Timeline

Forensic triage of the LA peer-sync bug across **2026-05-15 → 2026-05-19** (4-day
window, cosmetics_tweaker `v0.8.51-dev` → `v0.8.67-dev`).

Source of truth for everything below: `cosmetics_tweaker/CHANGELOG.md`. Git only
has commits up to v0.7.58 territory (March-area work) — the v0.8.x line was
never committed; CHANGELOG is the only record. Memory files
(`reference_la_offhand_paint.md`, `reference_la_kind_unit_pipeline.md`,
`reference_la_custom_mesh_pattern.md`, `feedback_la_custom_mesh_unsupported.md`)
were re-read but are older than the sync work (5/8/11/6 days old, all
pre-2026-05-15) and only document the LOCAL render pipeline, not the peer-sync
saga. The crash class is shared with `feedback_vt2_gated_registration_diverges.md`
(ct lessons re-applied to cosmetics in v0.8.66).

Big-doc analysis files (`CROSS_MOD_ARCHITECTURE.md`, `REVIEW_AGGREGATE.md`,
`CONSISTENCY_REVIEW.md`, `cosmetics_tweaker/CODE_REVIEW.md`) are all dated
2026-05-01/2026-05-02, ~2 weeks before the sync work. They cover the LA-clone
loadout-cache architecture (used by host/clone equip) and the three local
render paths, but **do not address peer-sync at all** — that surface only
emerged when a friend tried to host on 2026-05-16 (crash GUID fa479a72).

---

## 1. Timeline

| Date | Version | Change (one-liner) | Outcome |
|---|---|---|---|
| 2026-05-13 | 0.8.50-dev | `cim` coexistence: yield illusion-swap to crafting_in_modded | **OK** — not sync-related, listed for context |
| 2026-05-16 | 0.8.51-dev | Public-alpha prep, full `kind="unit"` LA shield coverage (20 entries), W2 dual-wield offhand picker | **OK** — still single-player surface |
| 2026-05-16 | 0.8.52-dev | Same-character-only shield pools | OK |
| 2026-05-16 | 0.8.53-dev | Open the LA focus gate, show every LA shield | OK |
| 2026-05-16 | 0.8.54-dev | Per-character cross-pool for LA shields | OK |
| 2026-05-16 | 0.8.55-dev | Fix main-hand cycle swapping shield preview | OK |
| 2026-05-16 | 0.8.56-dev | Independent offhand swap for ALL dual-wields | OK |
| 2026-05-16 | 0.8.57-dev | Family-aware cross-pollination + bow filter | OK |
| **2026-05-16** | **0.8.58-dev** | **PEER CRASH FIX A**: hook `CosmeticUtils.update_cosmetic_slot` to substitute LA backend_id → vanilla (stop network-syncing local LA `item_names` indices to peers) | **FAILED** — silent. `CosmeticUtils` is a plain table; string-form hook never registered |
| 2026-05-16 | 0.8.59-dev | **RE-FIX**: switch to table-form `mod:hook(CosmeticUtils, ...)` | Partial — hook fires, but the equip path also goes through `LoadoutUtils.sync_loadout_slot` which still leaked |
| 2026-05-16 | 0.8.60-dev | **PEER CRASH FIX B**: also substitute in `LoadoutUtils.sync_loadout_slot` (table-form) | OK for this path; subsequent audit found 3 more |
| 2026-05-16 | 0.8.61-dev | **AUDIT**: cover 3 more raw `NetworkLookup.item_names[backend_id]` sites — `PUAE.game_object_initialized`, `PUAE.spawn_resynced_loadout`, `AttachmentUtils.hot_join_sync`. Added hook-registration startup verification | OK — closes the crash side of the bug |
| 2026-05-17 | 0.8.62-dev | **VISIBILITY FIX (hats)**: new VMF custom RPC `cos_la_attach` after every `rpc_create_attachment` so LA-aware peers spawn the LA mesh on top of the vanilla substitute | Partial — hats only; armor+shields punted; verified flicker but worked |
| 2026-05-17 | 0.8.63-dev | Experimental Third-Person Equipment (unrelated to sync) | – |
| 2026-05-18 | 0.8.64-dev | **UNIFICATION**: `cos_la_attach` → `cos_la_apply` covering hats/armor/offhand. Also closes weapon-skin leak (5th arg `skin_name`) and adds 3P path verification (`<path>_3p`) | Partial — peer-broadcast model, host bypass observed |
| 2026-05-18 | 0.8.65-dev | DLC paywall fix on custom-illusion loop (unrelated to sync) | OK |
| 2026-05-18 | 0.8.66-dev | **TWO BUNDLES**: (a) `pre_register_la_inventory_packages` — sorted-key, unconditional registration of every `kind="unit"` LA variant's units in `NetworkLookup.inventory_packages` to fix the divergent-indices `inventory_packages does not contain key: 2296` host crash on lynnd's machine; (b) armor + weapon-illusion `cos_la_apply` kinds, `apply_gate` bracketed with `_bridge_active=true/false`, `find_active_clone_for_unit_path` reads `loadout_cache` first | Partial — fixed shield-equip host crash, but the apply broadcast was reaching the host yet silently bailing for texture-changes-not-appearing-on-host case |
| **2026-05-19** | **0.8.67-dev** | **SERVER-AUTHORITATIVE ROUTING**: client → host (`cos_la_apply_req`); host validates, records into `_la_equips_by_peer[sender_peer_id]`, broadcasts authoritative `cos_la_apply` to ALL (incl. originator). Identity over wire = `wearer_peer_id` (not `go_id`). Late-spawn races queued in `_la_pending_apply` with 5-second TTL, drained from `mod.update`. Receivers reject any `cos_la_apply` whose sender ≠ host | **CURRENT** — claimed fix; in-game verification pending |

---

## 2. Approach Taxonomy

### Family A — "Stop the crash by not syncing LA indices"
(replace LA backend_id → vanilla in every outgoing SyncData / RPC)

Hooked sites (all currently in place, all required):
- `CosmeticUtils.update_cosmetic_slot` — 4th arg `item_name` AND 5th arg `skin_name` (v0.8.58 fixed in v0.8.59, skin_name added v0.8.64)
- `LoadoutUtils.sync_loadout_slot` — table-form, with `LoadoutUtils.hot_join_sync` (v0.8.60)
- `PlayerUnitAttachmentExtension.game_object_initialized` (v0.8.61) — mutate `slot_data.item_data.name`, restore in `pcall`
- `PlayerUnitAttachmentExtension.spawn_resynced_loadout` (v0.8.61)
- `AttachmentUtils.hot_join_sync` (v0.8.61) — same mutate/restore pattern

**Status:** fully tried. Believed complete; covered by v0.8.61 startup
hook-registration verification (chat warning if any failed to register).
**Out-of-scope verified safe:** pickup-projectile extractors (resolve from
`AllPickups`, no LA keys can reach them) and Versus mode (unreachable from
Adventure/CW).

### Family B — "Peer-broadcast LA visuals via parallel VMF RPC"

- **B1 (v0.8.62)** `cos_la_attach` — fired AFTER every `rpc_create_attachment`,
  hats only, payload `{go_id, slot, key=la_backend_id}`. Each peer resolves
  LA path locally via `LA_BRIDGE.backend_to_armoury` → `SKIN_LIST[ak].new_units[1]`.
  **Outcome:** worked for hats with brief flicker.
- **B2 (v0.8.64)** Unified `cos_la_apply` — payload `{go_id, slot, kind, ak, vk}`,
  `kind ∈ {hat, armor, offhand}`. Used **armoury_key** as the wire identity
  (not la_backend_id, because la_backend_id has silent-bail on
  `ItemMasterList[la_backend_id]` lookup miss).
- **B3 (v0.8.66)** Added `kind="illusion"` (weapon-illusion paint via
  `apply_new_skin_from_texture` on `right_hand_wielded_unit_3p` /
  `left_hand_wielded_unit_3p`), bracketed apply with `_bridge_active=true/false`
  so the apply_gate at `_la_bridge.lua:568` doesn't block the receiver's husk paint.

**Status:** peer-broadcast model abandoned at v0.8.67 in favour of Family C
(below). Code from B2/B3 is preserved as the receiver core
(`_apply_la_on_unit`), but `_send_la_apply` no longer emits "others"; it
either short-circuits to "all" (host) or sends `cos_la_apply_req` to "server"
(client).

### Family C — "Server-authoritative routing" (CURRENT, v0.8.67)

- Single source of truth: host. Only the host emits `cos_la_apply`.
- Clients send `cos_la_apply_req` to "server"; host validates against
  `LA_BRIDGE.armoury_to_backend`, records into `_la_equips_by_peer[sender_peer_id][slot]`,
  broadcasts authoritative `cos_la_apply` to "all" (including the requester
  — wearer waits one RTT before painting locally to stay in lockstep).
- Receivers reject any `cos_la_apply` whose `sender_peer_id ≠ host_peer_id`.
- Identity over wire: `wearer_peer_id` (deterministic), resolved on receiver via
  `Managers.player:players_at_peer(wearer_peer_id)`. NOT `go_id`
  (host-relative, broke on late-spawn).
- **Late-spawn handling**: `_la_pending_apply` queue with 5-second TTL,
  drained per-frame from `mod.update`. Prevents the "joiner sees vanilla
  because their unit hadn't spawned when the broadcast arrived" race.

**Status:** in place; user-side game verification pending.

### Family D — "Fix divergent NetworkLookup indices across peers"
(crash class shared with ct v0.7.60/61/62)

- **v0.8.66** — `pre_register_la_inventory_packages` iterates `SKIN_LIST` in
  sorted key order, registers every `kind="unit"` variant's `new_units[1]` +
  `new_units[2]` in `NetworkLookup.inventory_packages` **unconditionally**
  (no `_is_supported_variant` / `can_get` filtering). Previously the
  `pairs(la().SKIN_LIST)` iteration was unordered AND filtered by a
  timing-dependent `Application.can_get("unit", ...)` check, so different
  peers assigned the same path to different indices. Same fix-pattern applied
  to the existing `pairs(la().SKIN_LIST)` loops in `register_all` and
  `build_offhand_options` so `NetworkLookup.item_names` appends are also
  deterministic across peers.

**Status:** Fixed for shields. Same fix-pattern (sorted-key,
unconditional pre-register) is the doctrine — if any future LA category lands
in `NetworkLookup` via per-user-toggle conditionals, it will re-introduce the
bug.

---

## 3. Dead Ends (do not retry without new evidence)

1. **String-form hook on plain tables** (`CosmeticUtils`, `LoadoutUtils`,
   `AttachmentUtils`, `PUAE`). Silently never registers. v0.8.58 cost a version.
   Mitigation: hook-registration startup verification (v0.8.61).
2. **Peer-broadcast LA visuals from the equipping client** (Family B). Reaches
   the host via VMF's host-relay BUT silently bails on the host. Replaced by
   Family C in v0.8.67. Specific issues observed:
   - `go_id` as identity is host-relative and unreliable across the
     equip → spawn → broadcast race.
   - Late-spawn on join: peer drops the message with no retry.
   - Hot-join replay was per-peer with no central authority — drops or
     duplicates couldn't be reconciled.
3. **Calling `LA.apply_new_skin_from_texture` on receivers without bracketing
   `_bridge_active = true`**. The `apply_gate` (`_la_bridge.lua:568`) blocks
   LA-managed `armoury_key`s when `_bridge_active=false`. v0.8.66 caught this
   for `kind="armor"`; v0.8.67's unified `_apply_la_on_unit` brackets all
   branches.
4. **Per-user-toggle gating on shared global tables.** Any `NetworkLookup` /
   `BuffTemplates` / `DeusPowerUp*` write conditional on `mod:get(...)` at
   load time → indices diverge across peers → strict `__index` fatal.
   Doctrine: pre-register unconditionally in sorted order, gate only the
   user-facing pool. v0.8.66 retrofit of this rule for LA inventory packages.
5. **Reading the loadout in `find_active_clone_for_unit_path` via
   `items_iface:get_loadout()`.** The `get_loadout` hook rewrites LA
   backend_ids back to vanilla for net-safety, so the LA-key lookup misses,
   so `apply_direct` never fires, so `_bridge_active` stays false, so LA's
   own update-loop apply is blocked → wearer sees vanilla on themselves.
   Fix (v0.8.66): consult `cosmetics_tweaker.mod.loadout_cache` first, fall
   back to vanilla loadout.

---

## 4. Untried Angles (suggested by docs but not in v0.8.67)

1. **Pre-emptive armoury-key wire dictionary.** Currently the host validates
   `armoury_key ∈ LA_BRIDGE.armoury_to_backend`, but receivers still resolve
   each apply via `LA().SKIN_LIST[armoury_key]` on the wire. If the host has
   a newer LA version than the peer, the peer silently bails at this lookup
   with no diagnostic. Adding a `cos_la_handshake` exchange on lobby-join
   that swaps the host's `LA().SKIN_LIST` keyset vs each peer's keyset would
   pre-classify "this peer can render X variants" and let the host degrade
   gracefully per-peer (broadcast vanilla-substitute for variants the peer
   lacks) instead of silently dropping at receive time.
2. **`kind="unit"` shield husk-side mesh swap.** v0.8.64-66 explicitly defers
   `kind="unit"` on peers — vanilla mesh stays. Husk-side mesh swap would
   require despawning/respawning a network-coupled unit. Documented as
   acceptable for ship; could be tackled if user complains.
3. **Post-host-migration `LootItemUnitPreviewer.spawn_units` re-fire.** v0.8.66
   "Known issue" — after a host-migration kick, every subsequent `[LA paint]`
   reports `ok=false` because `_offhand_selection` lookup fails (loadout
   reference changed after migration). v0.8.67 changelog flags this as still
   open. Likely fix: switch the `mod:hook` to `hook_safe` per
   `feedback_loot_previewer_hook_not_safe.md` — but that contradicts the
   `_spawned_units` capture-on-return rule. Needs a separate session to
   resolve the timing/capture tradeoff. **Not investigated yet.**
4. **Hot-join replay using the host's authoritative state.** v0.8.67 has
   `_la_equips_by_peer[sender_peer_id]` on the host but no documented
   replay-on-join path. `AttachmentUtils.hot_join_sync` was updated in v0.8.64
   to emit per-slot via `_local_la_equips`, but that's still local-state-based,
   not the new authoritative store. Host-side hot-join should walk
   `_la_equips_by_peer` and broadcast `cos_la_apply` to the joiner for every
   recorded entry. Doesn't appear in CHANGELOG.
5. **Host-less degradation.** Documented "Known limitation" in v0.8.67: if
   the HOST doesn't have cosmetics_tweaker, NO peer sees LA visuals (the
   `cos_la_apply_req` dies at the host's missing dispatcher). Substitute
   hooks still keep peers crash-free. No mitigation attempted — could expose
   a setting "fallback to local-paint when host lacks cosmetics_tweaker" but
   wasn't built.
6. **VMF RPC payload size.** Server-authoritative routing keeps payloads
   small (`{wearer_peer_id, slot, kind, armoury_key, vanilla_key}`), so the
   `STRING_MAX=500` cap (`reference_vmf_rpc_string_cap.md`) is not at risk.
   Worth keeping in mind if `_la_equips_by_peer` ever needs to be
   broadcast as one snapshot (would exceed 500 chars rapidly with multiple
   peers).

---

## 5. Outstanding Regressions / Suspected Still-Broken

| Item | Last touched | Status |
|---|---|---|
| Post-host-migration `[LA paint] ok=false` for offhand selection | v0.8.66 documented, v0.8.67 unaddressed | **Still broken** — flagged for v0.8.67-dev tracking |
| Hot-join replay using host authoritative state | v0.8.67 has the store but no documented broadcast-on-join | **Untried** — local-state hot_join_sync from v0.8.64 still runs but isn't re-routed through Family C |
| Host without cosmetics_tweaker = peers see nothing | v0.8.67 documented limitation | **Will not fix this release** per CHANGELOG ("Documented; ship as-is") |
| `kind="unit"` LA shields on peers (vanilla mesh stays) | v0.8.64 deferred | **Deferred indefinitely** |
| Brief visual flicker on peer-side as vanilla → LA | v0.8.62-64 acknowledged tradeoff | **Won't fix** — accepted |
| `LootItemUnitPreviewer.spawn_units` hook is `mod:hook` not `hook_safe` (per CLAUDE.md and `feedback_loot_previewer_hook_not_safe.md`) | Used since v0.7.74 | Working, but if v0.8.67's `_la_pending_apply` ever needs to read `_spawned_units` it must use hook (full wrapper) not hook_safe — the rule still applies |
| v0.8.67's "wearer waits one RTT before local apply" | New tradeoff in v0.8.67 | Wearer briefly sees vanilla on themselves; acceptable per CHANGELOG, but worth in-game eyeballing |

---

## Summary (250 words)

Between **2026-05-16 and 2026-05-19** the cosmetics_tweaker LA host/client
sync went through three architectural families across ten versions (v0.8.58 →
v0.8.67). Family A ("stop the crash") substitutes LA backend_ids with vanilla
in 5 outgoing-sync hook sites — fully tried, complete, protected by a
startup hook-registration verifier. The string-form-on-plain-table footgun
cost v0.8.58 (silent no-op) and is now caught by the verifier.

Family B (peer-broadcast `cos_la_attach` / `cos_la_apply`) was tried for hats
(v0.8.62), unified across hat/armor/offhand (v0.8.64), and extended to
weapon illusions + armor with `_bridge_active` bracketing (v0.8.66). It worked
for hats but silently bailed on the host in observable cases, mostly because
`go_id` is host-relative and late-spawn races weren't retried.

Family C (server-authoritative routing, v0.8.67) replaces B: only the host
emits `cos_la_apply`; clients send `cos_la_apply_req`; identity is
`wearer_peer_id`; late spawns are queued with a 5-second TTL. This is the
current claimed fix and is **unverified in-game**.

A parallel Family D (v0.8.66) ported the ct v0.7.60-62 doctrine: sorted-key
unconditional pre-registration in `NetworkLookup.inventory_packages` to
fix a `kind="unit"` shield host crash from divergent indices.

**Open**: post-host-migration paint-broken, hot-join replay via authoritative
store, and host-without-cosmetics_tweaker degradation. **Untried angle worth
considering**: `cos_la_handshake` SKIN_LIST keyset exchange so the host
classifies per-peer renderability instead of silently dropping unknown
armoury_keys at receive.
