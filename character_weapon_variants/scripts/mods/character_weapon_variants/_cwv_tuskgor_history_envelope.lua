-- Private #645 Tuskgor history proof; no loader, hook, write or public admission.
-- Only the exact native donor block-cost cell is delegated to WT's real history
-- tuple. All other constructor source cells remain graph-owned. This is finite
-- semantic ownership, not cryptographic producer-origin/gameplay attestation.
-- Owned by: private Tuskgor constructor through the entry's dormant family owner.
-- Consumed via: its mandatory third bind argument, with existing producer proof.
local M = {}
local DONOR, FAMILY, SETTING = "two_handed_heavy_spears_template", "tuskgor_spear", "wt_history_tuskgor_spear"
local STATE, KEY, CURRENT, HISTORICAL = "pre_3_1_delta", "block_fatigue_point_multiplier", .5, .25
local LEDGER_KEYS = { applied_snapshot = true, applied_value = true, key = true, operation = true,
    original_present = true, original_value = true, owner_object = true, parent = true,
    root_name = true, root_object = true, template_name = true }
function M.bind(graph, producer)
    local capture, intact = assert(graph.capture), assert(graph.intact)
    local common_capture, common_intact, resolve = assert(producer.capture_runtime), assert(producer.intact_runtime), assert(producer.resolve)
    local plain, dense = assert(producer.plain), assert(producer.dense)
    local function operation_ok(row)
        local path = plain(row) and rawget(row, "path")
        return plain(row) and rawget(row, "root") == "Weapons" and rawget(row, "template") == DONOR
            and rawget(row, "family_id") == FAMILY and rawget(row, "state_id") == STATE
            and rawget(row, "expected_present") == true and rawget(row, "result_present") == true
            and rawget(row, "expected_current") == CURRENT and rawget(row, "result") == HISTORICAL
            and rawget(row, "change_class") == "official_weapon_balance"
            and rawget(row, "official_change_id") == "P310-TUSKGOR-BLOCK-COST"
            and rawget(row, "source_path") == "scripts/settings/equipment/weapon_templates/2h_heavy_spears.lua"
            and rawget(row, "source_revision") == "c96aa3858011ecd557d55d80b66fe3bb8342eeb2"
            and rawget(row, "source_blob") == "bdd5a9bed6cf3e4a826206318a090cc198ccf7de"
            and rawget(row, "current_source_blob") == "7575b5035a40d9957514667538d253af46e18c9a"
            and dense(path, 1) == 1 and rawget(path, 1) == KEY
    end
    local function binding(mod, runtime)
        local b = common_capture(mod, runtime)
        if not b then return nil end
        local family = rawget(b.families, FAMILY)
        local templates, states = plain(family) and rawget(family, "templates"), plain(family) and rawget(family, "states")
        local state = plain(states) and rawget(states, STATE)
        local operations = plain(state) and rawget(state, "operations")
        local operation = plain(operations) and rawget(operations, 1)
        local order = plain(family) and rawget(family, "state_order")
        if not plain(family) or rawget(family, "id") ~= FAMILY or rawget(family, "setting_id") ~= SETTING
                or dense(templates, 1) ~= 1 or rawget(templates, 1) ~= DONOR
                or dense(order, 1) ~= 1 or rawget(order, 1) ~= STATE
                or dense(operations, 1) ~= 1 or not operation_ok(operation)
                or dense(rawget(state, "profile_names"), 0) ~= 0
                or dense(rawget(state, "direct_profile_names"), 0) ~= 0 then return nil end
        local family_snapshot = capture(family, 64, 512)
        if not family_snapshot then return nil end
        b.family, b.family_snapshot, b.operation = family, family_snapshot, operation
        b.ledgers, b.active, b.boot = rawget(runtime, "ledgers"), rawget(runtime, "active"), rawget(runtime, "boot_selections")
        return b
    end
    local function bound(p, b)
        if not common_intact(b, p.weapons) or not rawequal(rawget(b.families, FAMILY), b.family)
                or not intact(b.family_snapshot) or not rawequal(rawget(b.runtime, "ledgers"), b.ledgers)
                or not rawequal(rawget(b.runtime, "active"), b.active)
                or not rawequal(rawget(b.runtime, "boot_selections"), b.boot)
                or rawget(b.runtime, "fatal_error") ~= nil or rawget(b.runtime, "last_error") ~= nil then return false end
        local count, found = dense(b.list, 128), 0
        if not count then return false end
        for index = 1, count do if rawequal(rawget(b.list, index), b.family) then found = found + 1 end end
        local boot = rawget(b.boot, SETTING)
        return found == 1 and (boot == "current" or boot == STATE)
    end
    local function history_row(p, b, ledger, active)
        local row = plain(ledger) and rawget(ledger, 1)
        if dense(ledger, 1) ~= 1 or not plain(row) or not plain(active)
                or rawget(active, "state") ~= STATE or type(rawget(active, "parity")) ~= "boolean"
                or rawget(b.boot, SETTING) ~= STATE then return false end
        for key in next, row do if not LEDGER_KEYS[key] then return false end end
        for key in next, active do if key ~= "state" and key ~= "parity" then return false end end
        return rawequal(rawget(row, "operation"), b.operation) and rawequal(rawget(row, "parent"), p.source)
            and rawequal(rawget(row, "owner_object"), p.source) and rawequal(rawget(row, "root_object"), p.weapons)
            and rawget(row, "root_name") == "Weapons" and rawget(row, "template_name") == DONOR
            and rawget(row, "key") == KEY and rawget(row, "original_present") == true
            and rawget(row, "original_value") == CURRENT and rawget(row, "applied_value") == HISTORICAL
            and rawget(row, "applied_snapshot") == HISTORICAL
    end
    local function valid(p)
        if not p or p.dead or not rawequal(rawget(p.weapons, DONOR), p.source)
                or not rawequal(getmetatable(p.source), p.source_meta) then return false end
        local value, authorized = rawget(p.source, KEY), false
        if value ~= CURRENT and value ~= HISTORICAL then return false end
        for _, id in ipairs({ "wt", "wt_dev" }) do
            local slot = p.slots[id]
            local ok, mod = resolve(id)
            if not ok or not rawequal(mod, slot.mod) then return false end
            if mod ~= nil then
                if not rawequal(getmetatable(mod), slot.mod_meta)
                        or not rawequal(rawget(mod, "_wt_history_runtime"), slot.runtime) then return false end
                if slot.binding then
                    local b = slot.binding
                    if not bound(p, b) then return false end
                    local ledger, active = rawget(b.ledgers, FAMILY), rawget(b.active, FAMILY)
                    if active ~= nil or (ledger ~= nil and dense(ledger, 0) ~= 0) then
                        if value ~= HISTORICAL or not history_row(p, b, ledger, active) then return false end
                        local verified, problem = pcall(b.verify)
                        if not verified or problem ~= nil then return false end
                        authorized = true
                    end
                else return false end
            end
        end
        return value == CURRENT or authorized
    end
    local function make(source, weapons)
        if type(source) ~= "table" or type(weapons) ~= "table" or not rawequal(rawget(weapons, DONOR), source) then return nil end
        local p = { source = source, weapons = weapons, source_meta = getmetatable(source), slots = {} }
        for _, id in ipairs({ "wt", "wt_dev" }) do
            local ok, mod = resolve(id)
            if not ok or (mod ~= nil and type(mod) ~= "table") then return nil end
            local runtime
            if mod ~= nil then
                runtime = rawget(mod, "_wt_history_runtime")
                if runtime == nil then return nil end
            end
            local b = runtime ~= nil and binding(mod, runtime) or nil
            if runtime ~= nil and not b then return nil end
            p.slots[id] = { mod = mod, mod_meta = mod and getmetatable(mod), runtime = runtime, binding = b }
        end
        return valid(p) and p or nil
    end
    return { capture = make, intact = function(p)
        local ok, ready = pcall(valid, p)
        if not ok or not ready then if p then p.dead = true end; return false end
        return true
    end, include = function(p, target, key)
        return not (rawequal(target, p.source) and key == KEY)
    end }
end
return M
