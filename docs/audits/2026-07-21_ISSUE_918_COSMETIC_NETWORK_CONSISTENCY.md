# Issue #918: cosmetic network consistency

Date: 2026-07-21
Status: source candidate only; no version, build, upload, deployment, or live-test claim

## Disposition

Issue #918 is a concrete leaf of the open appearance architecture umbrella #660.
It is not a duplicate of #737 (unsafe numeric session-score skin identity) or
#749 (borrowed GUI renderer residency). It is the visible consequence of the
necessary #421 mixed-lobby safety boundary: Cosmetics removes `ct_*` skin keys
from vanilla `rpc_add_equipment`, but previously supplied no semantic replacement
for Cosmetics-capable observers.

The bounded owner is Cosmetics' custom-illusion-to-husk adapter. The existing
`cos_la_apply` / `cos_la_apply_req` `offhand_unit` channel from #416 already owns
per-hand semantic mesh transport, host relay, late-join replay, receiver storage,
package gating, and husk re-render. No new RPC or renderer cache is warranted.

## Evidence

The attached owner/client log records the selected backend instance and skin:

- `explicit_saved ... item=es_2h_heavy_spear skin=ct_es_heavy_spear_deus_01`
- local resolution applies `wpn_es_deus_spear_01`
- the same session then records `[cos:421] wire skin null` on
  `spawn_resynced_loadout`, `update_cosmetic_slot`, and
  `game_object_initialized`

The observer log resolves the safe base heavy-spear appearance and contains no
semantic custom-illusion descriptor. That makes the report a deterministic
missing-adapter policy gap, not evidence of packet loss.

Repository evidence agrees: `_cos_appearance_census.lua` explicitly described
custom-illusion husks as unsupported because all custom skin keys were nulled.
The four registered custom illusions have complete authored hand-unit paths in
`_cos_illusions.lua`, and the #416 channel can already carry those paths without
placing a mod key on the vanilla wire.

## Source candidate

`_cos_custom_illusion_sync.lua` is the pure adapter policy. It accepts only keys
registered in Cosmetics' `custom_skin_keys`, requires an exact
`matching_item_key` family match, and yields the authored right/left hand units.
Unknown, incomplete, or cross-family data resolves to no semantic override.

The runtime publishes that descriptor before #421 temporarily nulls the vanilla
skin at initial spawn, resync, and hot-join senders. State-transition replay and
the loadout sync edge use the same adapter. Removing or changing the illusion
emits an explicit empty-path clear, including across a respawn. A committed
per-instance `_offhand_selection` remains the final writer for its claimed hand.
Bots remain excluded because the peer-keyed #416 store intentionally represents
human wearers; bots sharing a host peer must never overwrite that identity.

The semantic publisher is fail-open. An adapter exception is logged once at the
wire boundary and the safe vanilla continuation still executes. `ct_*` values
remain unconditionally absent from vanilla numeric skin traffic, so peers without
Cosmetics continue to render the base weapon and cannot decode a modded index.

This change does not query, mutate, or require Pusfume. Cosmetics-owned custom
skin definitions are the only source of semantic appearance, while absent or
external definitions fall through to vanilla appearance.

## Falsifiable fallback paths

1. **Peer lacks Cosmetics.** Equip `ct_es_heavy_spear_deus_01` while a vanilla
   peer observes. The observer must remain connected and render the base Tuskgor
   spear. Any `ct_*` value in vanilla equipment traffic falsifies the boundary.
2. **Definition or package is unavailable.** Remove/withhold the exact custom
   skin definition or fail its unit-package readiness probe. The observer must
   retain the base mesh, with no crash and no cross-family mesh. A custom mesh
   from a different weapon family falsifies the resolver floor.
3. **Custom illusion is removed or changed across respawn.** Publish a custom
   spear, switch to a vanilla skin, then respawn or transition. The remote cache
   must receive an empty-path clear and render the base spear. A lingering Deus
   spear falsifies wearer/template state reconciliation.
4. **Exact per-instance hand override coexists.** On a two-hand definition,
   commit an `_offhand_selection` for one hand while a custom skin supplies the
   other. The selected hand must remain the instance choice and the unclaimed
   hand must follow the skin. A baseline STORE/CLEAR overwriting the selected
   hand falsifies writer precedence.
5. **Bot shares the host peer.** Equip a custom illusion on the host human while
   a bot exists. The human husk may receive semantic state; the bot must retain
   its own vanilla loadout. The bot receiving the host mesh falsifies the
   human-only identity gate.

## Verification boundary

Pure policy tests cover exact-family resolution, wrong-family rejection,
missing-definition degradation, replay/clear planning, and per-instance writer
precedence. Wire tests cover semantic publication before numeric null and the
skinless resync clear path. The runtime regression suite also asserts the live
installer, exact known-spear resolution, explicit clear planning, and all three
vanilla sender seams without emitting an RPC. Runtime multiplayer confirmation
remains required; this audit makes no live-session or packaged-build claim.
