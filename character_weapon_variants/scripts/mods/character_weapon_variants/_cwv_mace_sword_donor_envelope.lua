-- _cwv_mace_sword_donor_envelope.lua -- closed Mace/Sword source provenance.
-- Uses actual private #599 state and full WT9/6 family ledgers. Normalizes only
-- detached clones. No hook, setting authority, native repair or movement lease.
-- Owned by: character_weapon_variants.lua. Consumed via the Mace family factory.
local M = {}
local MACE, BARDIN, PRIEST = "one_handed_hammer_template_1",
    "one_handed_hammer_template_2", "one_handed_hammer_priest_template"
local SWORD = "one_handed_swords_template_1"
local FAMILY, SETTING = "one_handed_hammer_shared", "wt_history_one_handed_hammer_shared"
local TEMPLATES = { MACE, BARDIN, PRIEST }
local OP_ORDER = { PRIEST, MACE, BARDIN }
local TIMING = {
    { "default" }, { "default_right" }, { "default_left" }, { "default_last" },
    { "heavy_attack_left", .9 * 1.2 }, { "heavy_attack_right", .9 * 1.2 },
    { "light_attack_left", .9 }, { "light_attack_right", .9 },
    { "light_attack_last", .9 }, { "light_attack_down", .9 * 1.35 },
    { "light_attack_bopp", .9 * 1.2 },
}
local STATE = {
    ["5_1_1"] = { count = 9, revision = "8224b4436e20905a6ba463cb28fa2d7771bb2330",
        mace_blob = "5bedc100e3587f460c59f05e2de62a8d7af7835d",
        priest_blob = "bc006d697cd67332a508dec244fc76a8e059aaa0", push = true },
    ["5_2_0"] = { count = 6, revision = "4f496970e2e7514bef7d612ab91331aa065d5e52",
        mace_blob = "22a786921157d0847c751cc1dc8d6c9f85aee3e1",
        priest_blob = "715ad21432d7c5bb208679101580c095f88fd649" },
}
local LEDGER = { applied_snapshot = true, applied_value = true, key = true, operation = true,
    original_present = true, original_value = true, owner_object = true, parent = true,
    root_name = true, root_object = true, template_name = true }
local function plain(t) return type(t) == "table" and getmetatable(t) == nil end
local function keys(t, allowed)
    if not plain(t) then return false end
    for key in next, t do if not allowed[key] then return false end end
    return true
end
local function equal(a, b)
    if type(b) ~= "table" then return rawequal(a, b) end
    if not plain(a) then return false end
    local n, m = 0, 0
    for key, value in next, b do n = n + 1; if not equal(rawget(a, key), value) then return false end end
    for _ in next, a do m = m + 1 end
    return n == m
end
local function one(template)
    local actions = type(template) == "table" and rawget(template, "actions")
    return type(actions) == "table" and rawget(actions, "action_one") or nil
end
local function route_rows(id)
    local result = {}
    for _, name in ipairs(OP_ORDER) do
        if STATE[id].push then
            result[#result + 1] = { name, { "actions", "action_one", "push", "fatigue_cost" },
                "action_stun_push", nil, true }
        end
        result[#result + 1] = { name, { "block_angle" }, 120, 90 }
        result[#result + 1] = { name, { "dodge_count" }, 4, 3 }
    end
    return result
end
local function parent(root, path)
    for index = 1, #path - 1 do
        root = type(root) == "table" and rawget(root, path[index]) or nil
    end
    return type(root) == "table" and root or nil
end
local function operation(op, id, row)
    local priest, spec = row[1] == PRIEST, STATE[id]
    local path = priest and "scripts/settings/equipment/weapon_templates/1h_hammers_priest.lua"
        or "scripts/settings/equipment/weapon_templates/1h_hammers.lua"
    local blob = priest and spec.priest_blob or spec.mace_blob
    local current = priest and "dbea759457f3949b685e9e98dfd98cf4063de488"
        or "a67eb83ad27bcb86f0b88f52dcf8d4a5c8650c6d"
    return plain(op) and rawget(op, "root") == "Weapons" and rawget(op, "template") == row[1]
        and rawget(op, "family_id") == FAMILY and rawget(op, "state_id") == id
        and equal(rawget(op, "path"), row[2]) and rawget(op, "expected_present") == true
        and equal(rawget(op, "expected_current"), row[3])
        and rawget(op, "result_present") == (row[4] ~= nil) and equal(rawget(op, "result"), row[4])
        and rawget(op, "source_path") == path and rawget(op, "source_revision") == spec.revision
        and rawget(op, "source_blob") == blob and rawget(op, "current_source_blob") == current
        and rawget(op, "change_class") == (row[5] and "official_weapon_balance" or "source_anchor_drift")
        and rawget(op, "official_change_id") == (row[5] and "P520-1HH-PUSH"
            or "source_anchor_drift:one_handed_hammer_shared")
end
function M.bind(graph, career, producer, integration, canonical_for, mhi_for, sword)
    local capture, intact = assert(graph.capture), assert(graph.intact)
    local ccapture, cintact = assert(career.capture), assert(career.intact)
    local make, common_ok, resolve = assert(producer.capture_runtime), assert(producer.intact_runtime), assert(producer.resolve)
    local dense, prepare = assert(producer.dense), assert(integration.prepare_inherited_clone)
    assert(type(canonical_for) == "function" and type(mhi_for) == "function")
    -- Trusted private owner at bind, not freshly admitted methods at construction.
    -- Missing/invalid authority remains a closed envelope, never native repair.
    local trusted_ok, trusted_state, trusted_policy = pcall(mhi_for)
    local trusted_methods = trusted_ok and plain(trusted_state) and {
        apply = rawget(trusted_state, "apply"),
        ensure = rawget(trusted_state, "ensure_cwv_dual_mace_template"),
        balanced = rawget(trusted_state, "_balanced_profile"),
    } or nil
    local trusted_policy_snapshot = trusted_methods and plain(trusted_policy)
        and capture(trusted_policy, 64, 512) or nil
    local function trusted_owner(state, policy)
        return trusted_policy_snapshot and rawequal(state, trusted_state)
            and rawequal(policy, trusted_policy) and intact(trusted_policy_snapshot)
            and rawget(state, "apply") == trusted_methods.apply
            and rawget(state, "ensure_cwv_dual_mace_template") == trusted_methods.ensure
            and rawget(state, "_balanced_profile") == trusted_methods.balanced
    end
    local dependencies = assert(capture({ career, producer, integration, sword }, 256, 2048))
    local function helpers() return intact(dependencies) end
    local function bind_runtime(mod, runtime)
        local b = make(mod, runtime)
        if not b then return nil end
        local family = rawget(b.families, FAMILY)
        if not plain(family) or rawget(family, "id") ~= FAMILY or rawget(family, "setting_id") ~= SETTING
                or not equal(rawget(family, "templates"), TEMPLATES)
                or not equal(rawget(family, "state_order"), { "5_1_1", "5_2_0" }) then return nil end
        local states, selected, n = rawget(family, "states"), {}, 0
        if not plain(states) then return nil end
        for id in next, states do if not STATE[id] then return nil end; n = n + 1 end
        if n ~= 2 then return nil end
        for id, spec in next, STATE do
            local state = rawget(states, id)
            local operations = plain(state) and rawget(state, "operations")
            local routes = route_rows(id)
            if dense(operations, 9) ~= spec.count or not equal(rawget(state, "profile_names"), {})
                    or not equal(rawget(state, "direct_profile_names"), {}) then return nil end
            for index, row in ipairs(routes) do
                if not operation(rawget(operations, index), id, row) then return nil end
            end
            selected[id] = { state = state, operations = operations, routes = routes,
                snapshot = capture(state, 256, 2048) }
            if not selected[id].snapshot then return nil end
        end
        b.family, b.states, b.selected = family, states, selected
        b.family_snapshot = capture(family, 512, 4096)
        b.ledgers, b.active, b.boot = rawget(runtime, "ledgers"), rawget(runtime, "active"), rawget(runtime, "boot_selections")
        return b.family_snapshot and b or nil
    end
    local function bound(p, b)
        if not common_ok(b, p.weapons) or not intact(b.family_snapshot)
                or not rawequal(rawget(b.families, FAMILY), b.family)
                or not rawequal(rawget(b.family, "states"), b.states)
                or not rawequal(rawget(b.runtime, "ledgers"), b.ledgers)
                or not rawequal(rawget(b.runtime, "active"), b.active)
                or not rawequal(rawget(b.runtime, "boot_selections"), b.boot) then return false end
        local found, count = 0, dense(b.list, 128)
        if not count then return false end
        for index = 1, count do if rawequal(rawget(b.list, index), b.family) then found = found + 1 end end
        local boot = rawget(b.boot, SETTING)
        return found == 1 and (boot == "current" or b.selected[boot] ~= nil)
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
    local function mhi(p)
        local ok, state, policy = pcall(mhi_for)
        if not ok or not trusted_owner(state, policy)
                or not rawequal(state, p.mhi) or not rawequal(policy, p.policy)
                or not intact(p.policy_snapshot) or rawget(state, "apply") ~= p.apply
                or rawget(state, "ensure_cwv_dual_mace_template") ~= p.ensure
                or rawget(state, "_balanced_profile") ~= p.balanced
                or type(rawget(state, "enabled")) ~= "boolean" then return false end
        local snapshots, enabled = rawget(state, "speed_snapshots"), rawget(state, "enabled")
        if not plain(snapshots) or rawget(policy, "MACE_SPEED_MULT") ~= 1.05 then return false end
        for _, row in ipairs(TIMING) do
            local node = rawget(p.one, row[1])
            if not plain(node) then return false end
            local original, snapshot = row[2], rawget(snapshots, node)
            if enabled then
                if not keys(snapshot, { had_value = true, value = true })
                        or rawget(snapshot, "had_value") ~= (original ~= nil)
                        or not rawequal(rawget(snapshot, "value"), original)
                        or rawget(node, "anim_time_scale") ~= (original or 1) * 1.05 then return false end
            elseif snapshot ~= nil or not rawequal(rawget(node, "anim_time_scale"), original) then return false end
        end
        return true
    end
    local function historical(p, b, id)
        local selected, spec = b.selected[id], STATE[id]
        local ledger, active = rawget(b.ledgers, FAMILY), rawget(b.active, FAMILY)
        if not spec or not selected or not keys(active, { state = true, parity = true })
                or rawget(active, "state") ~= id or type(rawget(active, "parity")) ~= "boolean"
                or rawget(b.boot, SETTING) ~= id or dense(ledger, 9) ~= spec.count then return false end
        for index, route in ipairs(selected.routes) do
            local row, template = rawget(ledger, index), rawget(p.weapons, route[1])
            local owner = p.owners[route[1]]
            local target, key = parent(owner, route[2]), route[2][#route[2]]
            if not target then return false end
            if not keys(row, LEDGER) or not rawequal(template, owner)
                    or not rawequal(rawget(row, "operation"), rawget(selected.operations, index))
                    or not rawequal(rawget(row, "root_object"), p.weapons)
                    or not rawequal(rawget(row, "owner_object"), owner)
                    or rawget(row, "root_name") ~= "Weapons" or rawget(row, "template_name") ~= route[1]
                    or not rawequal(rawget(row, "parent"), target) or rawget(row, "key") ~= key
                    or rawget(row, "original_present") ~= true or not rawequal(rawget(row, "original_value"), route[3])
                    or not rawequal(rawget(row, "applied_value"), route[4])
                    or not rawequal(rawget(row, "applied_snapshot"), route[4])
                    or not rawequal(rawget(target, key), route[4]) then return false end
        end
        local ok, problem = pcall(b.verify)
        return ok and problem == nil
    end
    local function current(p)
        for _, name in ipairs(TEMPLATES) do
            local t = rawget(p.weapons, name)
            local a = one(t)
            local push = type(a) == "table" and rawget(a, "push")
            if not rawequal(t, p.owners[name]) or not plain(push)
                    or rawget(push, "fatigue_cost") ~= "action_stun_push"
                    or rawget(t, "block_angle") ~= 120 or rawget(t, "dodge_count") ~= 4 then return false end
        end
        return true
    end
    local function valid(p)
        if not p or not helpers() or not rawequal(rawget(p.weapons, MACE), p.mace)
                or not rawequal(rawget(p.weapons, SWORD), p.sword)
                or not cintact(p.graph) or not sword.intact(p.sword_proof) or not mhi(p) or not discover(p) then return false end
        local authorized = false
        for _, b in next, p.bindings do
            local active, ledger = rawget(b.active, FAMILY), rawget(b.ledgers, FAMILY)
            if active ~= nil or ledger ~= nil and dense(ledger, 0) ~= 0 then
                if not plain(active) or not historical(p, b, rawget(active, "state")) then return false end
                authorized = true
            end
        end
        return current(p) or authorized
    end
    local function make_source(weapons)
        if not helpers() or not plain(weapons) then return nil end
        local mace, source_sword = rawget(weapons, MACE), rawget(weapons, SWORD)
        if not plain(mace) or not plain(source_sword) or not plain(one(mace)) then return nil end
        local ok, state, policy = pcall(mhi_for)
        if not ok or not plain(state) or not plain(policy) or not trusted_owner(state, policy) then return nil end
        local p = { weapons = weapons, mace = mace, sword = source_sword, one = one(mace),
            bindings = {}, owners = {}, mhi = state, policy = policy, apply = rawget(state, "apply"),
            ensure = rawget(state, "ensure_cwv_dual_mace_template"), balanced = rawget(state, "_balanced_profile") }
        if type(p.apply) ~= "function" or type(p.ensure) ~= "function" or type(p.balanced) ~= "function" then return nil end
        for _, name in ipairs(TEMPLATES) do
            p.owners[name] = rawget(weapons, name)
            if not plain(p.owners[name]) then return nil end
        end
        p.policy_snapshot = trusted_policy_snapshot
        p.sword_proof = sword.capture(source_sword, weapons, "empire_on_elf")
        if not p.policy_snapshot or not p.sword_proof then return nil end
        local push = rawget(p.one, "push")
        p.graph = ccapture(mace, { role = "source", include = function(t, key)
            if rawequal(t, mace) and (key == "block_angle" or key == "dodge_count") then return false end
            if rawequal(t, push) and key == "fatigue_cost" then return false end
            if key == "anim_time_scale" then
                for _, row in ipairs(TIMING) do if rawequal(t, rawget(p.one, row[1])) then return false end end
            end
            return true
        end })
        if not p.graph or not valid(p) then return nil end
        return p
    end
    return {
        capture = make_source, intact = valid,
        prepare_clone = function(p, mace_clone, sword_clone, token)
            if not valid(p) or not plain(mace_clone) or not plain(sword_clone)
                    or rawequal(mace_clone, p.mace) or rawequal(sword_clone, p.sword) then return false end
            local group = one(mace_clone)
            if not plain(group) then return false end
            for _, row in ipairs(TIMING) do
                local node = rawget(group, row[1])
                if not plain(node) or not rawequal(rawget(node, "anim_time_scale"),
                        rawget(rawget(p.one, row[1]), "anim_time_scale")) then return false end
                rawset(node, "anim_time_scale", row[2])
            end
            local push = rawget(group, "push")
            if not plain(push) or not rawequal(rawget(push, "fatigue_cost"),
                    rawget(rawget(p.one, "push"), "fatigue_cost")) then return false end
            rawset(push, "fatigue_cost", "action_stun_push")
            rawset(mace_clone, "block_angle", 120)
            rawset(mace_clone, "dodge_count", 4)
            local result = prepare(mace_clone, p.mace, canonical_for(), token)
            return type(result) == "table" and rawget(result, "ok") == true
                and sword.prepare_clone(p.sword_proof, sword_clone, token) == true and valid(p)
        end,
        capture_clone = function(p, template, token)
            return valid(p) and ccapture(template, { role = "clone", source = p.mace, token = token }) or nil
        end,
        clone_intact = function(proof) return helpers() and cintact(proof) end,
    }
end
return M
