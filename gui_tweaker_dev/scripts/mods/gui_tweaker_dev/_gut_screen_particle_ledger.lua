-- _gut_screen_particle_ledger.lua — Pure screen-particle lifecycle ledger (#209 diagnostics).
--
-- Tracks first-person screen-space particle ids observed through the hooked
-- PlayerUnitFirstPerson surface (create/stop_spawning/destroy_screen_particles,
-- player_unit_first_person.lua:1073/:1081/:1089) so the #209 instrument in
-- _gut_camera.lua can print bounded [gut:209] lifecycle rows and a live-id
-- receipt at every third-person camera entry/exit. Engine-free and offline
-- tested; the caller owns all printf output. KNOWN BLIND SPOT (documented for
-- the receipt reader): owners that destroy through World.destroy_particles
-- directly (overcharge decay, player_unit_overcharge_extension.lua:155-159)
-- bypass this surface, so their entries can remain listed after death; the
-- gut-initiated #216 overcharge destroy IS reported to the ledger by its hook.

local Ledger = {}

-- Row budget for [gut:209] lifecycle prints per session; the receipt at
-- camera transitions is not counted against it.
Ledger.MAX_ROWS = 120

function Ledger.new()
    return { live = {}, count = 0, rows = 0, capped = false }
end

-- A create observed through the hooked surface. Nil ids (engine gate refused,
-- player_unit_first_person.lua:1074-1076, or gut 3P suppression) are counted
-- by the caller's row only, never stored.
function Ledger.note_create(state, id, effect)
    if id == nil then return false end
    state.live[id] = { effect = tostring(effect), status = "live" }
    state.count = state.count + 1
    return true
end

-- stop_spawning keeps the id alive (emission stops, particles persist).
function Ledger.note_stop(state, id)
    local entry = id ~= nil and state.live[id] or nil
    if not entry then return false end
    entry.status = "stopped"
    return true
end

function Ledger.note_destroy(state, id)
    if id == nil or state.live[id] == nil then return false end
    state.live[id] = nil
    state.count = state.count - 1
    return true
end

-- May this lifecycle event print a row? Returns allowed, capped_now; the
-- final allowed row should carry the capped marker so the log shows the
-- budget ran out rather than the events stopping.
function Ledger.row_allowed(state)
    if state.capped then return false, false end
    state.rows = state.rows + 1
    if state.rows >= Ledger.MAX_ROWS then
        state.capped = true
        return true, true
    end
    return true, false
end

-- Deterministic live-id listing for the camera-transition receipt, sorted by
-- stringified id: "id=effect(status)" joined with commas, or "none".
function Ledger.snapshot(state)
    local keys = {}
    for id in pairs(state.live) do
        keys[#keys + 1] = id
    end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    if #keys == 0 then return "none" end
    local parts = {}
    for i = 1, #keys do
        local entry = state.live[keys[i]]
        parts[i] = tostring(keys[i]) .. "=" .. entry.effect .. "(" .. entry.status .. ")"
    end
    return table.concat(parts, ",")
end

return Ledger
