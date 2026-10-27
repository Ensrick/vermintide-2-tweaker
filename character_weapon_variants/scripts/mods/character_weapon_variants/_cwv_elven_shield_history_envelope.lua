-- _cwv_elven_shield_history_envelope.lua -- Six finite native shield history axes.
--
-- Delegates only the exact native six-cell WT history tuple; the CWV clone
-- remains authored Current. Runtime/catalog/ledger identity is semantic
-- authority, not cryptographic producer-origin or gameplay-body attestation.
-- No live donor write, graph resnapshot, loader, hook or registry lives here.
-- Owned by: character_weapon_variants.lua entry point.
-- Consumed via: one manifest load and private fourth Elven factory argument.
local M = {}
local DONOR, FAMILY, SETTING = "one_handed_sword_shield_template_1", "kruber_sword_and_shield", "wt_history_kruber_sword_and_shield"
local ROUTES = {
    { "heavy_attack_right", "damage_profile", "medium_slashing_tank_1h", "medium_slashing_linesman_1h", true },
    { "light_attack_stab_postpush", "damage_window_end", 0.32, 0.28, true },
    { "light_attack_stab_postpush", "damage_window_start", 0.22, 0.18, true },
    { "light_attack_stab_postpush", "dedicated_target_range", 2.8, 2.5, true },
    { "light_attack_stab_postpush", "range_mod", 1.3, 1.2, true },
    { "light_attack_stab_postpush", "range_mod_add", 0.2, nil, false },
}
local STATES = {
    ["5_1_1"] = { first = 1, revision = "8224b4436e20905a6ba463cb28fa2d7771bb2330", blob = "77a83dd12e5ec0c4dc169f0e1bff50af67b7d9e2" },
    ["5_2_0"] = { first = 2, revision = "4f496970e2e7514bef7d612ab91331aa065d5e52", blob = "6d6847d78dc04b22ad228b5c7c4902239aff6c2c" },
    ["5_6_1"] = { first = 2, revision = "f64ecd2495bd26b1b0a4d296970bef0a0d7a06a9", blob = "70e77acd479b141c577eadf37097f6f909f4de6d" },
}
local LEDGER_KEYS = { applied_snapshot = true, applied_value = true, key = true, operation = true,
    original_present = true, original_value = true, owner_object = true, parent = true,
    root_name = true, root_object = true, template_name = true }
function M.bind(graph, producer)
    local capture, intact, disjoint = assert(graph.capture), assert(graph.intact), assert(graph.disjoint)
    local make_binding, binding_intact, resolve = assert(producer.capture_runtime), assert(producer.intact_runtime), assert(producer.resolve)
    local plain, dense = assert(producer.plain), assert(producer.dense)
    local function operation_ok(operation, state_id, index)
        local spec, route = STATES[state_id], ROUTES[index]
        local official = state_id == "5_6_1" or index == 1
        local change_id = state_id == "5_6_1" and "P600-KRUBER-SS-POSTPUSH"
            or (index == 1 and "P520-SS-H3" or "source_anchor_drift:kruber_sword_and_shield")
        if not plain(operation) or rawget(operation, "root") ~= "Weapons" or rawget(operation, "template") ~= DONOR
                or rawget(operation, "family_id") ~= FAMILY or rawget(operation, "state_id") ~= state_id
                or rawget(operation, "expected_present") ~= true or rawget(operation, "expected_current") ~= route[3]
                or rawget(operation, "result_present") ~= route[5] or rawget(operation, "result") ~= route[4]
                or rawget(operation, "change_class") ~= (official and "official_weapon_balance" or "source_anchor_drift")
                or rawget(operation, "official_change_id") ~= change_id
                or rawget(operation, "source_path") ~= "scripts/settings/equipment/weapon_templates/1h_swords_shield.lua"
                or rawget(operation, "source_revision") ~= spec.revision or rawget(operation, "source_blob") ~= spec.blob
                or rawget(operation, "current_source_blob") ~= "aed608e09cb504a3ac403e01e3a207630233044c" then return false end
        local path = rawget(operation, "path")
        return dense(path, 4) == 4 and rawget(path, 1) == "actions" and rawget(path, 2) == "action_one"
            and rawget(path, 3) == route[1] and rawget(path, 4) == route[2]
    end
    local function binding(mod, runtime)
        local common = make_binding(mod, runtime)
        if not common then return nil end
        local family = rawget(common.families, FAMILY)
        local templates, states = plain(family) and rawget(family, "templates"), plain(family) and rawget(family, "states")
        if not plain(family) or rawget(family, "id") ~= FAMILY or rawget(family, "setting_id") ~= SETTING
                or dense(templates, 1) ~= 1 or rawget(templates, 1) ~= DONOR or not plain(states) then return nil end
        local selected, count = {}, 0
        for id, spec in next, STATES do
            local state = rawget(states, id)
            if state ~= nil then
                local operations = plain(state) and rawget(state, "operations")
                if dense(operations, 6) ~= 7 - spec.first or dense(rawget(state, "profile_names"), 0) ~= 0
                        or dense(rawget(state, "direct_profile_names"), 0) ~= 0 then return nil end
                for index = spec.first, 6 do
                    if not operation_ok(rawget(operations, index - spec.first + 1), id, index) then return nil end
                end
                local snapshot = capture(state, 256, 2048)
                if not snapshot then return nil end
                selected[id] = { value = state, operations = operations, snapshot = snapshot }
                count = count + 1
            end
        end
        if count == 0 then return nil end
        common.family, common.templates, common.states, common.selected = family, templates, states, selected
        common.ledgers, common.active, common.boot = rawget(runtime, "ledgers"), rawget(runtime, "active"), rawget(runtime, "boot_selections")
        return common
    end
    local function bound(p, b)
        if not binding_intact(b, p.weapons) or not rawequal(rawget(b.families, FAMILY), b.family)
                or not plain(b.family) or rawget(b.family, "id") ~= FAMILY or rawget(b.family, "setting_id") ~= SETTING
                or not rawequal(rawget(b.family, "templates"), b.templates) or dense(b.templates, 1) ~= 1
                or rawget(b.templates, 1) ~= DONOR or not rawequal(rawget(b.family, "states"), b.states) or not plain(b.states) then return false end
        if not rawequal(rawget(b.runtime, "ledgers"), b.ledgers) or not rawequal(rawget(b.runtime, "active"), b.active)
                or not rawequal(rawget(b.runtime, "boot_selections"), b.boot) then return false end
        local count, found = dense(b.list, 128), 0
        if not count then return false end
        for index = 1, count do if rawequal(rawget(b.list, index), b.family) then found = found + 1 end end
        if found ~= 1 then return false end
        for id, row in next, b.selected do
            if not rawequal(rawget(b.states, id), row.value) or not intact(row.snapshot) then return false end
        end
        local boot = rawget(rawget(b.runtime, "boot_selections"), SETTING)
        return boot == "current" or b.selected[boot] ~= nil
    end
    local function tuple(p, state_id)
        local first = state_id and STATES[state_id].first or 7
        for index, route in ipairs(ROUTES) do
            local expected = route[3]
            if index >= first then expected = route[4] end
            if rawget(p.parents[index], route[2]) ~= expected then return false end
        end
        return true
    end
    local function historical(p, b, id)
        local selected, spec = b.selected[id], STATES[id]
        if not selected or not spec or not tuple(p, id) then return false end
        local runtime, count = b.runtime, 7 - spec.first
        local ledger = rawget(rawget(runtime, "ledgers"), FAMILY)
        local active = rawget(rawget(runtime, "active"), FAMILY)
        if dense(ledger, 6) ~= count or not plain(active) or rawget(active, "state") ~= id
                or type(rawget(active, "parity")) ~= "boolean"
                or rawget(rawget(runtime, "boot_selections"), SETTING) ~= id then return false end
        for key in next, active do if key ~= "state" and key ~= "parity" then return false end end
        for index = spec.first, 6 do
            local row, route = rawget(ledger, index - spec.first + 1), ROUTES[index]
            if not plain(row) then return false end
            for key in next, row do if not LEDGER_KEYS[key] then return false end end
            if not rawequal(rawget(row, "operation"), rawget(selected.operations, index - spec.first + 1))
                    or not rawequal(rawget(row, "parent"), p.parents[index])
                    or not rawequal(rawget(row, "root_object"), p.weapons) or not rawequal(rawget(row, "owner_object"), p.source)
                    or rawget(row, "key") ~= route[2] or rawget(row, "root_name") ~= "Weapons" or rawget(row, "template_name") ~= DONOR
                    or rawget(row, "original_present") ~= true or rawget(row, "original_value") ~= route[3]
                    or rawget(row, "applied_value") ~= route[4] or rawget(row, "applied_snapshot") ~= route[4] then return false end
        end
        local ok, problem = pcall(b.verify)
        return ok and problem == nil
    end
    local function valid(p)
        if not p or not rawequal(rawget(p.weapons, DONOR), p.source)
                or not rawequal(rawget(p.source, "actions"), p.actions)
                or not rawequal(rawget(p.actions, "action_one"), p.one) then return false end
        for index, route in ipairs(ROUTES) do
            if not rawequal(rawget(p.one, route[1]), p.parents[index])
                    or not rawequal(getmetatable(p.parents[index]), p.metas[index]) then return false end
        end
        local current, authorized = tuple(p), false
        for _, id in ipairs({ "wt", "wt_dev" }) do
            local ok, mod = resolve(id)
            local prior = p.bindings[id]
            if ok and mod ~= nil then
                if type(mod) ~= "table" then return false end
                local runtime = rawget(mod, "_wt_history_runtime")
                if runtime ~= nil then
                    if prior and not rawequal(prior.mod, mod) then return false end
                    local b = prior or binding(mod, runtime)
                    if not b or not bound(p, b) then return false end
                    if not prior then p.bindings[id] = b end
                    local ledger = rawget(rawget(runtime, "ledgers"), FAMILY)
                    local active = rawget(rawget(runtime, "active"), FAMILY)
                    if active ~= nil or (ledger ~= nil and dense(ledger, 0) ~= 0) then
                        if not plain(active) or not historical(p, b, rawget(active, "state")) then return false end
                        authorized = true
                    end
                elseif prior then return false end
            end
        end
        -- Native Current/restored values need no active ledger. Historical
        -- values need a live pinned finite producer; same-shaped origin forgery
        -- is intentionally not distinguished by this semantic contract.
        return current or authorized
    end
    local function make(source, weapons)
        local actions = type(source) == "table" and rawget(source, "actions")
        local one = type(actions) == "table" and rawget(actions, "action_one")
        if type(one) ~= "table" then return nil end
        local p = { source = source, weapons = weapons, actions = actions, one = one, parents = {}, metas = {}, bindings = {} }
        for index, route in ipairs(ROUTES) do
            local parent = rawget(one, route[1])
            if type(parent) ~= "table" then return nil end
            p.parents[index], p.metas[index] = parent, getmetatable(parent)
        end
        p.nodes = capture(source, 4096, 32768)
        if not p.nodes or not valid(p) then return nil end
        return p
    end
    local function prepare_clone(p, template)
        if not valid(p) or type(template) ~= "table" or rawequal(template, p.source) then return false end
        local actions = rawget(template, "actions")
        local one = type(actions) == "table" and rawget(actions, "action_one")
        local nodes = capture(template, 4096, 32768)
        if type(one) ~= "table" or not nodes or not disjoint(p.nodes, nodes) then return false end
        local parents, before = {}, {}
        for index, route in ipairs(ROUTES) do
            local parent = rawget(one, route[1])
            local value = rawget(p.parents[index], route[2])
            if type(parent) ~= "table" or rawget(parent, route[2]) ~= value then return false end
            parents[index], before[index] = parent, { value = value }
        end
        -- Only detached validated values are normalized, all prechecked before
        -- any write. The native source and its original full precommit graph
        -- stay untouched; the original seven/six CWV recipe remains unchanged.
        for index, route in ipairs(ROUTES) do rawset(parents[index], route[2], route[3]) end
        for index, route in ipairs(ROUTES) do
            if rawget(parents[index], route[2]) ~= route[3]
                    or rawget(p.parents[index], route[2]) ~= before[index].value then return false end
        end
        return true
    end
    return { capture = make, intact = valid, prepare_clone = prepare_clone, include = function(p, t, key)
        for index, route in ipairs(ROUTES) do if rawequal(t, p.parents[index]) and key == route[2] then return false end end
        return true
    end }
end
return M
