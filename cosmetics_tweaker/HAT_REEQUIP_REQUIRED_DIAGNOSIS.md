# LA `kind="texture"` Hat Re-Equip Required — Diagnosis (v0.9.0.7-hotfix)

**Symptom:** Host equips an LA `kind="texture"` hat (e.g. `Kruber_Hippogryph_helm_white`). Client `[cos_la_apply hat] paint ... ok=true` fires and `[cos_la_apply recv] applied=true` fires. **But the client's view of the host husk still shows vanilla hat colors until host unequips & re-equips.**

Codebase studied: `cosmetics_tweaker.lua` v0.9.0.7-hotfix (lines 3756-4102 server-authoritative cos_la_apply path), `_la_bridge.lua` (apply gate + paint helpers), VT2 source code `scripts/unit_extensions/default_player_unit/attachment/player_unit_attachment_extension.lua` and `player_husk_attachment_extension.lua`, `scripts/helpers/attachment_utils.lua`, `scripts/entity_system/systems/attachment/attachment_system.lua`, plus PC-B log `pcb-log.log`.

---

## Hypothesis confirmation

### H1 — Husk attachment uses different extension class (`PlayerHuskAttachmentExtension`)

**Partially confirmed but NOT load-bearing for this bug.**

`PlayerHuskAttachmentExtension` exists (`player_husk_attachment_extension.lua:3`) and is a parallel class to `PlayerUnitAttachmentExtension` per `attachment_system.lua:13-16` (`extension_list = { "PlayerUnitAttachmentExtension", "PlayerHuskAttachmentExtension" }`). Husks of remote players carry the husk variant.

**However, the field shape is compatible** for CT's code. `PlayerHuskAttachmentExtension._attachments.slots[slot_name]` exists (line 14-16 and is populated at line 75) and `slot_data.unit` is the spawned hat unit (line 38-44 in `attachment_utils.lua`). CT's teardown code at `cosmetics_tweaker.lua:3870-3876` reads/writes the right field, and `ext:create_attachment` dispatches to the husk's implementation (line 45-92) — which DOES respect `item_data.unit` override via `BackendUtils.get_item_units` (`backend_utils.lua:144-215`).

So the husk's slot bookkeeping works the same way the host's does — H1 is not the bug.

### H2 — Hat unit lazy-spawned, paint runs before mesh is bound

**Refuted.** The PC-B log line 3476 (host inventory sync) shows `es_gk_hat_03` already marked as loaded on PC-B *before* the very first `cos_la_apply` paint at line 3479. `Unit.num_meshes(unit)` in `apply_new_skin_from_texture` (`funcs.lua:7-9`) would still iterate 0 meshes and silently succeed if the unit weren't ready, but the texture write at `Material.set_texture` writes to whichever mesh materials exist. PCB log shows ok=true and the hat IS visible (vanilla colors) — meshes are bound.

### H3 — CT teardown nils slot but husk-side respawn loses the LA unit (race vs `rpc_create_attachment`)

**MOST LIKELY ROOT CAUSE.** Detail in the next section.

### H4 — Paint binds per-unit; if husk's hat unit is later replaced, paint is lost

**Confirmed mechanism, but its trigger is H3** (vanilla `rpc_create_attachment` arriving AFTER `cos_la_apply` on the wire from host to client). `apply_new_skin_from_texture` calls `Material.set_texture(mat, slot, path)` per mesh material; the write is bound to whatever material instance is currently on the unit. When the husk's `PlayerHuskAttachmentExtension.create_attachment` re-fires with vanilla item, line 52-56 destroys the existing (LA) attachment via `self:remove_attachment(slot_name)` → `AttachmentUtils.destroy_attachment` → `mark_for_deletion` — taking the textured LA unit with it. The fresh vanilla unit spawned at line 65 carries vanilla materials, no LA texture.

---

## Actual root cause

**Race between vanilla `rpc_create_attachment` and CT `cos_la_apply` on the client when host equips a LA hat in keep inventory.**

Trace from host side (`HeroViewStateOverview` invokes `attachment_extension:create_attachment_in_slot(slot_name, backend_id)` per `hero_view_state_overview.lua:714`):

1. **PUAE `create_attachment_in_slot`** (`player_unit_attachment_extension.lua:241-265`) — queues `_item_to_spawn`, sets `resync_loadout_needed = true`.
2. **PUAE `update_resync_loadout`** runs next tick (line 267-293) → resync completes → calls **`spawn_resynced_loadout`** (line 295-323):
   - Line 305: `network_transmit:send_rpc_clients("rpc_create_attachment", unit_object_id, slot_id, item_id)` — VANILLA RPC sent to all clients. CT's `spawn_resynced_loadout` wrapper at `cosmetics_tweaker.lua:4445-4463` has already substituted `item_data.name` to the vanilla key, so `item_id` is the vanilla NetworkLookup id.
   - Line 323: `self:create_attachment(slot_name, item_data)` — local host-side spawn. Inside this call:
     - Line 149: `CosmeticUtils.update_cosmetic_slot(self._player, slot_name, item_data.name)` → CT's hook at `cosmetics_tweaker.lua:3489` fires → calls `_send_la_apply(...)` → host short-circuits and broadcasts `cos_la_apply` via `mod:network_send("cos_la_apply", "all", payload)` (`cosmetics_tweaker.lua:3789`).
   - After `func` returns, CT's `spawn_resynced_loadout` wrapper also calls `_send_la_apply` (line 4458) — suppressed by the 0.5s `_EMIT_DEDUP_WINDOW` at line 3754.

Both RPCs travel the same reliable channel; the vanilla one is sent first. **On a healthy network they arrive in send order: vanilla → mod.** That's the path CT was designed around — CT's teardown at `cosmetics_tweaker.lua:3870-3876` *expects* a stale slot to be present and destroys it before respawning the LA unit.

**But the slot CT is destroying is the just-arrived vanilla hat unit, and the bug is on the *re-entry side*: after CT spawns the LA unit and paints it, no further vanilla `rpc_create_attachment` arrives, so the LA paint is the final state — and that DOES work, which is exactly why the SECOND equip works.**

The first-equip failure is actually the *opposite* race:

- For the **very first** hat-state delivered to a client (hot_join_sync replay, OR the host equipping a hat that the client has never seen), the cos_la_apply emit fires through one of the helper paths (`CosmeticUtils.update_cosmetic_slot` hook OR `AttachmentUtils.hot_join_sync` wrapper at line 4471-4511), **and these can fire BEFORE the host's PUAE `game_object_initialized` rpc_create_attachment has reached the client** (PUAE.game_object_initialized is the path that sends rpc_create_attachment for already-attached slots at unit spawn time, line 55-84). The order then becomes:

1. **Client receives `cos_la_apply` first** → CT's `_apply_la_on_unit` → husk slot is empty → CT calls `ext:create_attachment` → husk's create_attachment line 65 spawns LA unit (because `item_data.unit = la_unit_path`) → CT paints it. **Visible result: LA-colored hat.**
2. **Client receives vanilla `rpc_create_attachment` after** (the late one — was queued before, but on a different RPC handler dispatch) → husk's `create_attachment` line 52-56 sees `old_slot_data = LA unit` → calls `self:remove_attachment(slot_name)` (line 94-104) → `AttachmentUtils.destroy_attachment` → `mark_for_deletion(unit)` on the LA unit. Then spawns the VANILLA hat unit at line 65 with `item_data` derived from the vanilla item id (no `unit` override). **Net result: vanilla-colored hat, LA paint discarded with the destroyed unit.**

Re-equip works because by the time the user re-equips:
- The slot is currently the vanilla unit (no late vanilla RPC outstanding).
- Both vanilla rpc_create_attachment (from the new equip) and the new cos_la_apply arrive in send order — vanilla first, CT teardown destroys vanilla, CT spawns + paints LA. **No further vanilla RPC follows**, so the LA paint survives.

This also explains why the PC-B log shows `paint ok=true` but the user reports the LA color isn't visible — the paint *does* succeed (texture write on the LA unit's material), but the LA unit is then destroyed by the husk's `remove_attachment` triggered when the late vanilla `rpc_create_attachment` arrives.

---

## Code patch suggestion

Two complementary fixes; pick either or apply both for belt-and-suspenders.

### Fix A — Hook `PlayerHuskAttachmentExtension.create_attachment` to short-circuit vanilla respawn when an LA paint is already cached for that wearer+slot

In `cosmetics_tweaker.lua`, near the existing PUAE hook block at line 4408-4443, add a husk twin:

```lua
mod:hook("PlayerHuskAttachmentExtension", "create_attachment", function(func, self, slot_name, item_data)
    if slot_name ~= "slot_hat" then
        return func(self, slot_name, item_data)
    end
    -- Check if the wearer-peer has a cached LA hat equip. If so, override
    -- item_data.unit to the LA unit BEFORE the husk spawn runs, so the
    -- vanilla rpc_create_attachment that races AFTER our cos_la_apply
    -- doesn't replace the LA unit with the vanilla one.
    local pm = Managers and Managers.player
    local owner = pm and pm.owner and pm:owner(self._unit)
    local wearer_peer = owner and owner.peer_id
    local cached = wearer_peer and _la_equips_by_peer[wearer_peer]
                   and _la_equips_by_peer[wearer_peer][slot_name]
    if cached and cached.kind == "hat" and cached.armoury_key then
        local variant = _resolve_la_variant(cached.armoury_key)
        local la_unit = variant and variant.new_units and variant.new_units[1]
        if la_unit then
            -- Patch in place; func() spawns the LA unit instead of vanilla.
            local prev_unit = item_data.unit
            item_data.unit = la_unit
            local ok, err = pcall(func, self, slot_name, item_data)
            item_data.unit = prev_unit  -- restore for any caller that retains the table
            if not ok then error(err) end
            -- Now paint, since the slot we just created carries the LA unit.
            local la = get_mod("Loremasters-Armoury")
            local slot_data = self._attachments.slots[slot_name]
            local hat_unit = slot_data and slot_data.unit
            local world = _level_world()
            if la and world and hat_unit and Unit.alive(hat_unit) then
                LA_BRIDGE._bridge_active = true
                pcall(la.apply_new_skin_from_texture, cached.armoury_key, world,
                      cached.vanilla_key, hat_unit)
                LA_BRIDGE._bridge_active = false
            end
            return
        end
    end
    return func(self, slot_name, item_data)
end)
```

This makes the husk `create_attachment` LA-aware: whenever the wearer has a cached LA hat selection (which `_la_equips_by_peer` now holds on every client per the v0.9.0.7-hotfix mirror write at line 4085-4088), the late vanilla `rpc_create_attachment` spawns the LA unit + paints it in place of the vanilla. The race-loser becomes idempotent with the race-winner.

### Fix B — Defer CT's `_apply_la_on_unit` for hats by one frame

In `cosmetics_tweaker.lua:4090`, instead of calling `_try_apply_by_peer(...)` synchronously, push a small delay (e.g. 0.1s) into `_la_pending_apply` for all hat kinds and let the pending-queue runner pick it up. This lets any in-flight vanilla `rpc_create_attachment` settle first. Lower fidelity than Fix A (peers see one frame of vanilla color before LA paint), and you still want Fix A for hot_join_sync where the race window is wider.

```lua
-- in mod:network_register("cos_la_apply", ...) around line 4090
if kind == "hat" then
    -- Defer hats by one frame to outrun vanilla rpc_create_attachment
    -- arrival order. Without this, the late vanilla RPC destroys the
    -- LA-spawned unit we just painted.
    _la_pending_apply[#_la_pending_apply + 1] = {
        wearer, slot_name, kind, armoury_key, vanilla_key, os.clock() + 5,
    }
    mod:info("[cos_la_apply recv] HAT deferred from=%s wearer=%s key=%s",
        tostring(sender_peer_id), tostring(wearer), tostring(armoury_key))
    return
end
local applied = _try_apply_by_peer(wearer, slot_name, kind, armoury_key, vanilla_key)
```

### Recommendation

**Apply Fix A.** It addresses the underlying issue (race-loser overwrites race-winner) and works for both ordering paths. Fix B is a workaround that masks the symptom without preventing future regressions if the dedup or hot_join_sync emit paths change order.

---

## Cross-references

- `feedback_vt2_husk_extension_class_pair.md` — confirms the parallel class architecture for husks
- `reference_la_hat_kind_texture.md` — documents why texture-variant hats need the explicit `apply_new_skin_from_texture` call
- `feedback_redundant_safeguards_ok.md` — endorses Fix A's belt-and-suspenders character
- `cosmetics_tweaker/CHANGELOG.md` v0.9.0.7-hotfix — the mirror-write fix that prepared `_la_equips_by_peer` for client-side use; Fix A leverages that cache
