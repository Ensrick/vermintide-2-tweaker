-- _cos_diag_deus_yield.lua -- bounded solo-visible Chaos Wastes appearance-yield diagnostics.
--
-- The pinned #518 live-test falsifier is "the log records the wielded weapon
-- with a non-empty skin= value", but no solo-visible skin= emitter existed in
-- this mod (the only skin= printf repo-wide is CWV's husk-wield line,
-- remote-only) and both #518 failure-path decisions logged via _dbg only
-- (invisible with user mod-logging OFF). This module owns the bounded emitter
-- plus three diagnostic entry points consumed by the local-wield, offhand-
-- apply, and equipment-assembly runtime owners:
--   mod._cos518_owner_wield  - local player's wield in a Chaos Wastes run
--                              (mechanism "deus"): item key + resolved skin +
--                              deus-yield verdict; deduped per (item,skin).
--   mod._cos518_paint_skip   - ingame LA paint yielded to the deus skin.
--   mod._cos518_husk_miss    - husk mesh-swap authored variant unavailable.
-- Every line routes through mod._cos518_emit: engine printf ONLY (rawget-
-- guarded, no chat), [cos:518] prefix, deduped per caller key, capped at 16
-- records per channel so a long run cannot flood the console log.
--
-- Owned by: cosmetics_tweaker.lua entry point. Consumed via: mod:dofile.
-- Shared state: reads mod._la_deus_weapon_yield (the yield-policy owner's gate) at
-- call time; keeps bounded dedupe state in mod._cos518_probe_state.

local mod = get_mod("cosmetics_tweaker")

mod._cos518_emit = function(channel, dedupe_key, fmt, ...)
    local pf = rawget(_G, "printf")
    if not pf then return false end
    local state = mod._cos518_probe_state
    if not state then state = {}; mod._cos518_probe_state = state end
    local ch = state[channel]
    if not ch then ch = { seen = {}, count = 0 }; state[channel] = ch end
    if ch.seen[dedupe_key] or ch.count >= 16 then return false end
    ch.seen[dedupe_key] = true
    ch.count = ch.count + 1
    pf("[cos:518] " .. fmt, ...)
    return true
end

-- OWNER-WIELD probe. Called from the entry's consolidated
-- SimpleInventoryExtension._wield_slot hook_safe body (VMF drops a second
-- hook on the same Class+method, so this must ride the existing
-- registration; the entry has already gated on the LOCAL player unit).
-- Fires on every local wield anywhere in a Chaos Wastes run (mechanism
-- "deus": Pilgrimage Chamber, map, mission) and logs the wielded item key +
-- the resolved skin the render path consumes (slot_data.skin -
-- simple_inventory_extension.lua:259,2106; item_data.key -
-- spawning_helper.lua:80) plus the deus-yield verdict, so one Solo run
-- discriminates upgrade-selection vs local-rendering vs saved-identity.
mod._cos518_owner_wield = function(slot_data, wielded_slot)
    local mm = Managers and Managers.mechanism
    if not (mm and mm.current_mechanism_name) then return end
    local mech_ok, mechanism_name = pcall(mm.current_mechanism_name, mm)
    if not mech_ok or mechanism_name ~= "deus" then return end
    local item_data = slot_data and slot_data.item_data
    local item_key = item_data and item_data.key
    if not item_key then return end
    local skin = slot_data and slot_data.skin
    mod._cos518_emit("wield",
        tostring(item_key) .. "|" .. tostring(skin),
        "OWNER-WIELD slot=%s item=%s skin=%s deus_yield=%s",
        tostring(wielded_slot), tostring(item_key), tostring(skin),
        tostring(mod._la_deus_weapon_yield()))
end

-- Local paint-skip promotion: the ingame LA-paint deus-yield skip in
-- _apply_la_offhand_to_units was _dbg-only, so a Solo log could not show
-- whether the LA paint path yielded to the deus skin or simply never ran.
-- Deduped per backend_id (the _dbg line is retained at the call site).
mod._cos518_paint_skip = function(bid)
    mod._cos518_emit("paint-skip", tostring(bid),
        "PAINT-SKIP ctx=ingame bid=%s (deus run: CW upgrade cosmetics win)",
        tostring(bid))
end

-- Husk-side miss promotion: the get_item_units authored-variant-unavailable
-- miss was _dbg-only, so a log could not distinguish "variant unresolvable"
-- from "swap never reached". Deduped per armoury_key (the _dbg line and the
-- existing dedup'd chat warning are retained at the call site).
mod._cos518_husk_miss = function(armoury_key, wearer_peer, template)
    mod._cos518_emit("husk-miss", tostring(armoury_key),
        "HUSK-MISS authored variant %s unavailable (wearer=%s template=%s)",
        tostring(armoury_key), tostring(wearer_peer), tostring(template))
end
