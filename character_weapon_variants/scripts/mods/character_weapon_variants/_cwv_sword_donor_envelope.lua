-- _cwv_sword_donor_envelope.lua -- Typed native Sword producer boundary.
--
-- SOURCE PROPOSAL ONLY; whole Sword-family bootstrap must consume this binding.
-- Native restoration keeps actual WT state. Modified CWV styles are authored
-- Current, not a second application of WT history/private profiles/#348.
-- Only detached clones are normalized. No native writes, source-graph recapture, hook,
-- repair, proxy registry or gameplay-body/cryptographic origin attestation.
local M = {}
local EMPIRE, ELVEN = "one_handed_swords_template_1", "we_one_hand_sword_template_1"
local FAMILY, SETTING = "one_handed_sword_shared", "wt_history_one_handed_sword_shared"
local RECORD, COMBO_SETTING = "_wt348_sword_push_combo", "wt_revert_1h_sword_push_combo"
local PATH = "scripts/settings/equipment/weapon_templates/1h_swords.lua"
local CURRENT_BLOB = "8071d37830d043391dfcdcb864873f5059bc1d78"
local function movement(mult, name, finish, start)
    return { buff_name = name, end_time = finish, external_multiplier = mult, start_time = start }
end
local ROUTES = {
    { { "actions", "action_one", "light_attack_last" }, "buff_data",
        { movement(.85, "planted_fast_decrease_movement", .2, 0), movement(1.7, "planted_fast_decrease_movement", .4, .2), movement(.7, "planted_fast_decrease_movement", .5, .4) },
        { movement(.7, "planted_fast_decrease_movement", .2, 0), movement(1.7, "planted_fast_decrease_movement", .4, .2), movement(.7, "planted_fast_decrease_movement", .5, .4) } },
    { { "actions", "action_one", "light_attack_last" }, "damage_profile", "sword_1h_light_smiter_vertical", "light_slashing_smiter_finesse" },
    { { "actions", "action_one", "light_attack_left" }, "buff_data",
        { movement(.95, "planted_decrease_movement", .5, 0) }, { movement(.9, "planted_decrease_movement", .5, 0) } },
    { { "actions", "action_one", "light_attack_right" }, "buff_data",
        { movement(.95, "planted_decrease_movement", .5, 0) }, { movement(.9, "planted_decrease_movement", .5, 0) } },
    { { "actions", "action_one", "push" }, "charge_value", nil, "action_push" },
    { { "actions", "action_one", "push" }, "fatigue_cost", "action_stun_push", nil },
    { { "buffs", "change_dodge_distance" }, "external_optional_multiplier", 1.3, 1.2 },
    { { "buffs", "change_dodge_speed" }, "external_optional_multiplier", 1.3, 1.2 },
    { {}, "dodge_count", 6, 3 },
}
local AXES = {
    { "light_attack_left", "light_slashing_linesman_finesse" },
    { "light_attack_right", "light_slashing_linesman_finesse" },
    { "heavy_attack_left", "medium_slashing_tank_1h_finesse" },
    { "heavy_attack_right", "medium_slashing_tank_1h_finesse" },
}
local STATES = {
    ["5_1_1"] = { indices = { 1, 2, 3, 4, 5, 6, 7, 8, 9 }, axes = 1,
        revision = "8224b4436e20905a6ba463cb28fa2d7771bb2330", blob = "962bcfe504bb7c657c050e3641074cd8606dc224" },
    ["5_2_0"] = { indices = { 1, 2, 3, 4, 7, 8, 9 }, axes = 3,
        revision = "4f496970e2e7514bef7d612ab91331aa065d5e52", blob = "8a5fe3799041b780ea519844324349b5dd2d6a7f" },
}
local CURRENT_CHAIN = {
    { action = "action_one", end_time = 1.2, input = "action_one", release_required = "action_two_hold", start_time = .5, sub_action = "default_left" },
    { action = "action_two", input = "action_two_hold", start_time = .45, sub_action = "default" },
    { action = "action_one", input = "action_one", start_time = .85, sub_action = "default" },
    { action = "action_two", input = "action_two_hold", start_time = .55, sub_action = "default" },
    { action = "action_wield", input = "action_wield", start_time = .5, sub_action = "default" },
}
local REVERT_CHAIN = {
    { action = "action_one", end_time = 1.2, input = "action_one", release_required = "action_two_hold", start_time = .55, sub_action = "default" },
    { action = "action_one", end_time = 1.2, input = "action_one_hold", release_required = "action_two_hold", start_time = .55, sub_action = "default" },
    { action = "action_one", input = "action_one", start_time = .85, sub_action = "default" },
    { action = "action_two", input = "action_two_hold", start_time = .55, sub_action = "default" },
    { action = "action_wield", input = "action_wield", start_time = .5, sub_action = "default" },
}
local LEDGER = { applied_snapshot = true, applied_value = true, key = true, operation = true,
    original_present = true, original_value = true, owner_object = true, parent = true,
    root_name = true, root_object = true, template_name = true }
local SYNTHETIC = { expected_current = true, expected_present = true, family_id = true, path = true,
    result = true, result_present = true, root = true, state_id = true, synthetic_profile_route = true, template = true }
local RECORD_KEYS = { schema = true, setting_id = true, boot_enabled = true, weapons = true,
    source = true, action = true, before = true, applied = true }
local function plain(t) return type(t) == "table" and getmetatable(t) == nil end
-- Recursion is bounded by these authored constant tuples (maximum depth3/8keys).
local function equal(value, expected)
    if type(expected) ~= "table" then return rawequal(value, expected) end
    if not plain(value) then return false end
    local wanted, count = 0, 0
    for key, child in next, expected do
        wanted = wanted + 1
        if not equal(rawget(value, key), child) then return false end
    end
    for _ in next, value do count = count + 1; if count > wanted then return false end end
    return count == wanted
end
local function copy(value)
    if type(value) ~= "table" then return value end
    local out = {}; for key, child in next, value do out[key] = copy(child) end; return out
end
local function locate(root, path)
    local t = root
    for _, key in ipairs(path) do t = type(t) == "table" and rawget(t, key) or nil end
    return type(t) == "table" and t or nil
end
local function keys(t, allowed)
    if not plain(t) then return false end
    for key in next, t do if not allowed[key] then return false end end
    return true
end
local function operation_ok(op, state_id, index)
    local spec, route = STATES[state_id], ROUTES[index]
    if not plain(op) or rawget(op, "root") ~= "Weapons" or rawget(op, "template") ~= EMPIRE
            or rawget(op, "family_id") ~= FAMILY or rawget(op, "state_id") ~= state_id
            or rawget(op, "expected_present") ~= (route[3] ~= nil) or not equal(rawget(op, "expected_current"), route[3])
            or rawget(op, "result_present") ~= (route[4] ~= nil) or not equal(rawget(op, "result"), route[4])
            or rawget(op, "source_path") ~= PATH or rawget(op, "source_revision") ~= spec.revision
            or rawget(op, "source_blob") ~= spec.blob or rawget(op, "current_source_blob") ~= CURRENT_BLOB then return false end
    local official = state_id == "5_1_1" and (index == 2 or index == 5 or index == 6)
    if rawget(op, "change_class") ~= (official and "official_weapon_balance" or "source_anchor_drift")
            or rawget(op, "official_change_id") ~= (official and "P520-1HS" or "source_anchor_drift:one_handed_sword_shared") then return false end
    local path = copy(route[1]); path[#path + 1] = route[2]
    return equal(rawget(op, "path"), path)
end
function M.bind(graph, career, producer, integration, canonical_for)
    local capture, intact = assert(graph.capture), assert(graph.intact)
    local ccapture, cintact = assert(career.capture), assert(career.intact)
    local make, common_ok, resolve = assert(producer.capture_runtime), assert(producer.intact_runtime), assert(producer.resolve)
    local dense = assert(producer.dense)
    local prepare = assert(integration.prepare_inherited_clone)
    local helper_snapshot = assert(capture(integration, 32, 256))
    assert(type(canonical_for) == "function", "Sword canonical getter missing")
    local function helper_ok() return intact(helper_snapshot) and rawget(integration, "prepare_inherited_clone") == prepare end
    local function bind_runtime(mod, runtime)
        local b = make(mod, runtime)
        if not b then return nil end
        local family = rawget(b.families, FAMILY)
        local templates, states = plain(family) and rawget(family, "templates"), plain(family) and rawget(family, "states")
        if not plain(family) or rawget(family, "id") ~= FAMILY or rawget(family, "setting_id") ~= SETTING
                or dense(templates, 1) ~= 1 or rawget(templates, 1) ~= EMPIRE
                or not equal(rawget(family, "state_order"), { "5_1_1", "5_2_0" }) or not plain(states) then return nil end
        local selected, state_count = {}, 0
        for id in next, states do if not STATES[id] then return nil end; state_count = state_count + 1 end
        if state_count ~= 2 then return nil end
        for id, spec in next, STATES do
            local state = rawget(states, id)
            local operations = plain(state) and rawget(state, "operations")
            local profiles = spec.axes == 1 and { AXES[1][2], AXES[3][2] } or { AXES[3][2] }
            if dense(operations, 9) ~= #spec.indices or not equal(rawget(state, "profile_names"), profiles)
                    or not equal(rawget(state, "direct_profile_names"), profiles) then return nil end
            for position, index in ipairs(spec.indices) do if not operation_ok(rawget(operations, position), id, index) then return nil end end
            local snapshot = capture(state, 256, 2048)
            if not snapshot then return nil end
            for axis = spec.axes, 4 do
                local map = rawget(b.registration.private_by_state_name, id)
                if not plain(map) or rawget(map, AXES[axis][2]) ~= "wt_hist_" .. id .. "_" .. AXES[axis][2] then return nil end
            end
            selected[id] = { value = state, operations = operations, snapshot = snapshot }
        end
        b.family, b.templates, b.states, b.selected = family, templates, states, selected
        b.family_snapshot = capture(family, 512, 4096)
        if not b.family_snapshot then return nil end
        b.ledgers, b.active, b.boot = rawget(runtime, "ledgers"), rawget(runtime, "active"), rawget(runtime, "boot_selections")
        return b
    end
    local function bound(p, b)
        if not common_ok(b, p.weapons) or not intact(b.family_snapshot) or not rawequal(rawget(b.families, FAMILY), b.family)
                or rawget(b.family, "id") ~= FAMILY or rawget(b.family, "setting_id") ~= SETTING
                or not rawequal(rawget(b.family, "templates"), b.templates) or not equal(b.templates, { EMPIRE })
                or not rawequal(rawget(b.family, "states"), b.states) or not plain(b.states)
                or not equal(rawget(b.family, "state_order"), { "5_1_1", "5_2_0" })
                or not rawequal(rawget(b.runtime, "ledgers"), b.ledgers) or not rawequal(rawget(b.runtime, "active"), b.active)
                or not rawequal(rawget(b.runtime, "boot_selections"), b.boot) then return false end
        local count, found = dense(b.list, 128), 0
        if not count then return false end
        for index = 1, count do if rawequal(rawget(b.list, index), b.family) then found = found + 1 end end
        local states = 0; for id in next, b.states do if not b.selected[id] then return false end; states = states + 1 end
        for id, row in next, b.selected do if not rawequal(rawget(b.states, id), row.value) or not intact(row.snapshot) then return false end end
        local boot = rawget(b.boot, SETTING)
        return found == 1 and states == 2 and (boot == "current" or b.selected[boot] ~= nil)
    end
    local function discover(p)
        for _, id in ipairs({ "wt", "wt_dev" }) do
            local ok, mod = resolve(id)
            local prior = p.bindings[id]
            if ok and mod ~= nil then
                if type(mod) ~= "table" or prior and not rawequal(prior.mod, mod) then return false end
                local runtime = rawget(mod, "_wt_history_runtime")
                if runtime ~= nil then
                    local b = prior or bind_runtime(mod, runtime)
                    if not b or not bound(p, b) then return false end
                    if not prior then p.bindings[id] = b end
                elseif prior then return false end
            elseif prior then return false end
        end
        return true
    end
    local function base_row(p, row, operation, index)
        local route = ROUTES[index]
        return keys(row, LEDGER) and rawequal(rawget(row, "operation"), operation)
            and rawequal(rawget(row, "root_object"), p.weapons) and rawequal(rawget(row, "owner_object"), p.source)
            and rawget(row, "root_name") == "Weapons" and rawget(row, "template_name") == EMPIRE
            and rawequal(rawget(row, "parent"), p.parents[index]) and rawget(row, "key") == route[2]
            and rawget(row, "original_present") == (route[3] ~= nil) and equal(rawget(row, "original_value"), route[3])
    end
    local function combo_binding(p, mod, prior)
        local record = rawget(mod, RECORD)
        if record == nil then
            if prior == nil then return nil end
            return false
        end
        if not keys(record, RECORD_KEYS) or rawget(record, "schema") ~= 1
                or rawget(record, "setting_id") ~= COMBO_SETTING or type(rawget(record, "boot_enabled")) ~= "boolean"
                or not rawequal(rawget(record, "weapons"), p.weapons) or not rawequal(rawget(record, "source"), p.source)
                or not rawequal(rawget(record, "action"), p.bopp) then return false end
        local before, applied, enabled = rawget(record, "before"), rawget(record, "applied"), rawget(record, "boot_enabled")
        if not equal(before, CURRENT_CHAIN) or not equal(applied, enabled and REVERT_CHAIN or CURRENT_CHAIN)
                or (not enabled and not rawequal(before, applied)) or (enabled and rawequal(before, applied)) then return false end
        if prior and (not rawequal(prior.record, record) or prior.enabled ~= enabled
                or not rawequal(prior.before, before) or not rawequal(prior.applied, applied)) then return false end
        local before_snapshot = prior and prior.before_snapshot or capture(before, 32, 256)
        local applied_snapshot = prior and prior.applied_snapshot or capture(applied, 32, 256)
        if not before_snapshot or not applied_snapshot or not intact(before_snapshot) or not intact(applied_snapshot) then return false end
        return prior or { record = record, before = before, applied = applied, enabled = enabled,
            before_snapshot = before_snapshot, applied_snapshot = applied_snapshot }
    end
    local function combos(p, seeding)
        local value, authorized = rawget(p.bopp, "allowed_chain_actions"), false
        for id, b in next, p.bindings do
            local prior = p.combos[id]
            local binding = combo_binding(p, b.mod, prior)
            if binding == false then return false end
            if binding then
                if seeding and p.chain == nil then p.chain = binding.before end
                if not rawequal(binding.before, p.chain) then return false end
                if not prior then p.combos[id] = binding end
                if not rawequal(value, binding.applied) then return false end
                authorized = true
            end
        end
        if seeding and p.chain == nil and equal(value, CURRENT_CHAIN) then p.chain = value end
        return p.chain ~= nil and equal(p.chain, CURRENT_CHAIN)
            and (seeding or p.chain_snapshot ~= nil and intact(p.chain_snapshot))
            and (rawequal(value, p.chain) or authorized)
    end
    local function historical(p, b, id)
        local spec, selected = STATES[id], b.selected[id]
        local active, ledger = rawget(b.active, FAMILY), rawget(b.ledgers, FAMILY)
        if not spec or not selected or not keys(active, { state = true, parity = true })
                or rawget(active, "state") ~= id or type(rawget(active, "parity")) ~= "boolean"
                or rawget(b.boot, SETTING) ~= id or dense(ledger, 13) ~= #spec.indices + 5 - spec.axes then return false end
        local changed, seen = {}, {}
        for position, index in ipairs(spec.indices) do
            local row, route = rawget(ledger, position), ROUTES[index]
            if not base_row(p, row, rawget(selected.operations, position), index)
                    or not rawequal(rawget(row, "original_value"), p.current[index].value)
                    or not equal(rawget(row, "applied_value"), route[4]) or not equal(rawget(row, "applied_snapshot"), route[4])
                    or not rawequal(rawget(p.parents[index], route[2]), rawget(row, "applied_value")) then return false end
            changed[index] = true
        end
        for index, route in ipairs(ROUTES) do
            if not changed[index] and not rawequal(rawget(p.parents[index], route[2]), p.current[index].value) then return false end
        end
        for position = #spec.indices + 1, #ledger do
            local row = rawget(ledger, position)
            local op = type(row) == "table" and rawget(row, "operation")
            if not keys(row, LEDGER) or not keys(op, SYNTHETIC) then return false end
            local axis
            for index = spec.axes, 4 do
                if equal(rawget(op, "path"), { "actions", "action_one", AXES[index][1], "damage_profile" }) then axis = index end
            end
            if not axis or seen[axis] then return false end
            seen[axis] = true
            local native = AXES[axis][2]
            local expected = active.parity and "wt_hist_" .. id .. "_" .. native or native
            if rawget(op, "root") ~= "Weapons" or rawget(op, "template") ~= EMPIRE
                    or rawget(op, "family_id") ~= FAMILY or rawget(op, "state_id") ~= id
                    or rawget(op, "synthetic_profile_route") ~= true or rawget(op, "expected_present") ~= true
                    or rawget(op, "result_present") ~= true or rawget(op, "expected_current") ~= native or rawget(op, "result") ~= native
                    or not rawequal(rawget(row, "parent"), rawget(p.one, AXES[axis][1])) or rawget(row, "key") ~= "damage_profile"
                    or not rawequal(rawget(row, "root_object"), p.weapons) or not rawequal(rawget(row, "owner_object"), p.source)
                    or rawget(row, "root_name") ~= "Weapons" or rawget(row, "template_name") ~= EMPIRE
                    or rawget(row, "original_present") ~= true or rawget(row, "original_value") ~= native
                    or rawget(row, "applied_value") ~= expected or rawget(row, "applied_snapshot") ~= expected
                    or rawget(p.one[AXES[axis][1]], "damage_profile") ~= expected then return false end
        end
        for axis = 1, spec.axes - 1 do if rawget(p.one[AXES[axis][1]], "damage_profile") ~= AXES[axis][2] then return false end end
        local ok, problem = pcall(b.verify)
        if not ok or problem ~= nil then return false end
        -- One bounded cache per live ledger, not a growing source resnapshot log.
        -- Only already-validated typed producer payloads may replace this cache.
        local previous, payloads = b.payloads, {}
        for position, index in ipairs(spec.indices) do
            local value = rawget(rawget(ledger, position), "applied_value")
            if type(value) == "table" then
                local prior = previous and rawequal(previous.ledger, ledger) and previous.values[index]
                if prior and (not rawequal(prior.value, value) or not intact(prior.snapshot)) then return false end
                local snapshot = prior and prior.snapshot or capture(value, 32, 256)
                if not snapshot then return false end
                payloads[index] = { value = value, snapshot = snapshot }
            end
        end
        b.payloads = { ledger = ledger, values = payloads }
        return true
    end
    local function valid(p)
        if not p or not helper_ok() or not rawequal(rawget(p.weapons, p.donor), p.source)
                or not cintact(p.graph) then return false end
        if p.donor == ELVEN then return true end
        if not discover(p) or not combos(p) then return false end
        for _, row in ipairs(p.current) do if row.snapshot and not intact(row.snapshot) then return false end end
        local current = true
        for index, route in ipairs(ROUTES) do if not rawequal(rawget(p.parents[index], route[2]), p.current[index].value) then current = false end end
        for _, axis in ipairs(AXES) do if rawget(p.one[axis[1]], "damage_profile") ~= axis[2] then current = false end end
        local authorized = false
        for _, b in next, p.bindings do
            local ledger, active = rawget(b.ledgers, FAMILY), rawget(b.active, FAMILY)
            if active ~= nil or ledger ~= nil and dense(ledger, 0) ~= 0 then
                if not plain(active) or not historical(p, b, rawget(active, "state")) then return false end
                authorized = true
            end
        end
        return current or authorized
    end
    local function make_source(source, weapons, direction)
        local donor = direction == "empire_on_elf" and EMPIRE or direction == "elven_on_empire" and ELVEN
        if not donor or not helper_ok() or not plain(source) or not rawequal(rawget(weapons, donor), source) then return nil end
        local actions, one = rawget(source, "actions")
        one = type(actions) == "table" and rawget(actions, "action_one")
        if not plain(one) then return nil end
        local p = { donor = donor, source = source, weapons = weapons, actions = actions, one = one,
            parents = {}, current = {}, bindings = {}, combos = {} }
        if donor == EMPIRE then
            p.bopp = rawget(one, "light_attack_bopp")
            if not plain(p.bopp) then return nil end
            for index, route in ipairs(ROUTES) do
                p.parents[index] = locate(source, route[1])
                if not p.parents[index] then return nil end
                p.current[index] = { value = rawget(p.parents[index], route[2]) }
            end
            if not discover(p) or not combos(p, true) then return nil end
            p.chain_snapshot = capture(p.chain, 32, 256)
            if not p.chain_snapshot then return nil end
            for _, b in next, p.bindings do
                local active, ledger = rawget(b.active, FAMILY), rawget(b.ledgers, FAMILY)
                local id = plain(active) and rawget(active, "state")
                if id then
                    local spec, selected = STATES[id], b.selected[id]
                    if not spec or not selected or dense(ledger, 13) ~= #spec.indices + 5 - spec.axes then return nil end
                    for position, index in ipairs(spec.indices) do
                        local row = rawget(ledger, position)
                        if not base_row(p, row, rawget(selected.operations, position), index) then return nil end
                        local prior, value = p.current[index], rawget(row, "original_value")
                        if prior.seeded and not rawequal(prior.value, value) then return nil end
                        p.current[index] = { value = value, seeded = true }
                    end
                end
            end
            for index, route in ipairs(ROUTES) do
                local row = p.current[index]
                if not equal(row.value, route[3]) then return nil end
                if type(row.value) == "table" then row.snapshot = capture(row.value, 32, 256); if not row.snapshot then return nil end end
            end
        end
        p.graph = ccapture(source, { role = "source", include = function(t, key)
            if donor == EMPIRE then
                if rawequal(t, p.bopp) and key == "allowed_chain_actions" then return false end
                for index, route in ipairs(ROUTES) do if rawequal(t, p.parents[index]) and key == route[2] then return false end end
                for _, axis in ipairs(AXES) do if rawequal(t, rawget(p.one, axis[1])) and key == "damage_profile" then return false end end
            end
            return true
        end })
        if not p.graph or not valid(p) then return nil end
        return p
    end
    local function prepare_clone(p, template, token)
        if not valid(p) or not plain(template) or rawequal(template, p.source) then return false end
        if p.donor == EMPIRE then
            local targets = {}
            for index, route in ipairs(ROUTES) do
                targets[index] = locate(template, route[1])
                if not targets[index] or not equal(rawget(targets[index], route[2]), rawget(p.parents[index], route[2])) then return false end
            end
            local one = locate(template, { "actions", "action_one" })
            local bopp = one and rawget(one, "light_attack_bopp")
            if not plain(bopp) or not equal(rawget(bopp, "allowed_chain_actions"), rawget(p.bopp, "allowed_chain_actions")) then return false end
            for _, axis in ipairs(AXES) do
                local node = rawget(one, axis[1])
                if not plain(node) or rawget(node, "damage_profile") ~= rawget(p.one[axis[1]], "damage_profile") then return false end
            end
            for index, route in ipairs(ROUTES) do
                if not rawequal(rawget(p.parents[index], route[2]), p.current[index].value) then
                    rawset(targets[index], route[2], copy(p.current[index].value))
                end
            end
            for _, axis in ipairs(AXES) do rawset(rawget(one, axis[1]), "damage_profile", axis[2]) end
            if not rawequal(rawget(p.bopp, "allowed_chain_actions"), p.chain) then
                rawset(bopp, "allowed_chain_actions", copy(CURRENT_CHAIN))
            end
        end
        local report = prepare(template, p.source, canonical_for(), token)
        return type(report) == "table" and rawget(report, "ok") == true and valid(p)
    end
    return { capture = make_source, intact = valid, prepare_clone = prepare_clone,
        source_axis = function(p, node, key, expected)
            if not valid(p) then return false end
            if rawget(node, key) == expected then return true end
            if p.donor == EMPIRE and key == "damage_profile" then
                if rawequal(node, p.parents[2]) and expected == ROUTES[2][3] then return true end
                for _, axis in ipairs(AXES) do
                    if rawequal(node, rawget(p.one, axis[1])) and expected == axis[2] then return true end
                end
            end
            return false
        end,
        capture_clone = function(p, template, token)
            return valid(p) and ccapture(template, { role = "clone", source = p.source, token = token }) or nil
        end,
        clone_intact = function(proof) return helper_ok() and cintact(proof) end }
end
return M
