-- qa/runtime/_shared/official_mirror.lua: the official-save invariant as scripted assertions (WP-H-14).
--
-- Verbatim from docs/program/vp/D4.md section 0.4. The rig sends every qa/runtime/_shared/*.lua file with the
-- plan; a case gets this one with  local OM = T.shared("official_mirror") , and the driver takes OM.snapshot()
-- at KEEP READY and calls OM.restore() at the end of the run, before it quits, as a second line of defence
-- behind the backend write shield. Raw field reads and writes only: it never calls an items-interface method
-- and never commits. Top level has no engine access (the functions read Managers only when called).
--
-- Engine reads: Managers.backend:get_backend_mirror() (Vermintide-2-Source-Code/scripts/managers/backend_playfab/
-- backend_manager_playfab.lua:1222); _career_data written by set_character_data (playfab_mirror_base.lua:1928-1941);
-- _career_data_mirror, the copy the server acknowledged (playfab_mirror_base.lua:1934-1936).
local OM = {}
local function mirror() return Managers.backend:get_backend_mirror() end      -- backend_manager_playfab.lua:1222
local function is_slot(key) return type(key) == "string" and key:sub(1, 5) == "slot_" end

-- true when `id` could not have come from the official account
function OM.minted(id)
    if type(id) ~= "string" then return false end
    local row = rawget(mirror()._inventory_items, id)                           -- B4
    if row == nil then return true, "not in _inventory_items" end               -- vanilla's own broken-slot rule, playfab_mirror_base.lua:1617
    local custom = type(row.CustomData) == "table" and row.CustomData
    if custom and custom.cim_provider ~= nil then return true, "cim row" end    -- _cim_synthetic_item_contract.lua:353
    if id:match("^cwv_.+_%d%d%d$") then return true, "cwv id" end               -- _gut_native_loadout_policy.lua:17-19
    for _, mod_id in ipairs({ "cim", "cim_dev" }) do
        local owner = get_mod(mod_id)
        local store = owner and owner:get("forged_weapons")                     -- L3
        if type(store) == "table" and store[id] ~= nil then return true, mod_id .. " forged_weapons" end
    end
    return false
end

function OM.snapshot()
    local out = {}
    for career, rows in pairs(mirror()._career_data) do                         -- B1
        out[career] = {}
        for index, row in pairs(rows) do
            out[career][index] = {}
            for key, value in pairs(row) do out[career][index][key] = value end
        end
    end
    return out
end

local function walk(fn)
    local m = mirror()
    for career, rows in pairs(m._career_data) do
        for index, row in pairs(rows) do
            local acked = m._career_data_mirror[career] and m._career_data_mirror[career][index]   -- B2
            for key, value in pairs(row) do fn(career, index, key, value, acked and acked[key]) end
        end
    end
end

function OM.baseline_clean()
    local clean = true
    walk(function(_, _, key, value, acked)
        if is_slot(key) and (OM.minted(value) or value ~= acked) then clean = false end
    end)
    return clean
end

-- INV-A: no slot of any official row holds a mod-minted id.
-- INV-B: no official row differs from the acknowledged copy, so the engine's next commit sends no loadout.
-- slots_only = true limits INV-B to item slots (use it only in a case that changes talents on purpose).
function OM.assert_clean(T, label, slots_only)
    walk(function(career, index, key, value, acked)
        local where = string.format("%s %s[%s].%s", label, career, tostring(index), key)
        if is_slot(key) then
            local minted, why = OM.minted(value)
            T.expect(not minted, "INV-A " .. where .. " holds a mod-minted id (" .. tostring(why) .. ")")
        end
        if is_slot(key) or not slots_only then
            T.expect(value == acked, "INV-B " .. where .. " differs from _career_data_mirror (pending official write)")
        end
    end)
end

function OM.assert_untouched(T, snap)
    walk(function(career, index, key, value)
        local before = snap[career] and snap[career][index] and snap[career][index][key]
        T.expect(value == before, string.format("official row changed during the case: %s[%s].%s", career, tostring(index), key))
    end)
end

-- Cleanup only. Raw field writes back to the snapshot, so the engine has nothing to send. Not a commit.
function OM.restore(snap)
    local m = mirror()
    for career, rows in pairs(snap) do
        for index, row in pairs(rows) do
            for key, value in pairs(row) do
                if m._career_data[career] and m._career_data[career][index] then
                    m._career_data[career][index][key] = value
                end
            end
        end
    end
end
return OM
