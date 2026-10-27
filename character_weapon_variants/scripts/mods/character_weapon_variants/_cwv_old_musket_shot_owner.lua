-- _cwv_old_musket_shot_owner.lua — #428 local Old Musket shot transaction.
--
-- Owns one derived profile, its exact template consumers and retained firing
-- authority. The entry binds the canonical lookup helper once, then injects the
-- private factory into the Musket installer; no module is loaded here. Loading
-- or binding performs no registry mutation, hook or RPC. Healthy damage math and
-- profile order remain unchanged; rejected authority degrades or denies locally.
--
-- Owned by: character_weapon_variants.lua entry point.
-- Consumed via: entry mod:dofile("scripts/mods/character_weapon_variants/_cwv_old_musket_shot_owner") and private binding.
local M = {}
local KEY, NATIVE, TEMPLATE = "cwv_old_musket_shot", "shot_sniper", "old_musket_template"
local function integer(value)
    return type(value) == "number" and value == value and value >= 0
        and value < 9007199254740991 and value % 1 == 0
end
local function number(value)
    return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end
local function capture(value)
    local nodes, seen, cells = {}, {}, 0
    local function visit(t)
        if seen[t] then return true end
        if #nodes >= 64 then return false end
        seen[t] = true
        local row = { target = t, meta = getmetatable(t), cells = {}, count = 0 }
        nodes[#nodes + 1] = row
        for key, child in next, t do
            cells = cells + 1; if cells > 512 then return false end
            row.count = row.count + 1; row.cells[#row.cells + 1] = { key, child }
            if type(child) == "table" and not visit(child) then return false end
        end
        return true
    end
    return type(value) == "table" and visit(value) and nodes or nil
end
local function intact(nodes)
    if not nodes then return false end
    for i = 1, #nodes do
        local row, count = nodes[i], 0
        if getmetatable(row.target) ~= row.meta then return false end
        for j = 1, #row.cells do
            local cell = row.cells[j]
            if rawget(row.target, cell[1]) ~= cell[2] then return false end
        end
        for _ in next, row.target do count = count + 1; if count > row.count then return false end end
        if count ~= row.count then return false end
    end
    return true
end
local function native_shape(profile)
    if type(profile) ~= "table" then return false end
    local cleave, target = rawget(profile, "cleave_distribution"), rawget(profile, "default_target")
    if type(cleave) ~= "table" or not number(cleave.attack) or not number(cleave.impact)
            or type(target) ~= "table" then return false end
    for _, name in ipairs({ "power_distribution_near", "power_distribution_far" }) do
        local power = rawget(target, name)
        if type(power) ~= "table" or not number(power.attack) or not number(power.impact) then return false end
    end
    for _, name in ipairs({ "armor_modifier_near", "armor_modifier_far" }) do
        local armor = rawget(profile, name)
        if type(armor) ~= "table" or type(armor.attack) ~= "table" then return false end
        for index = 1, 6 do if not number(armor.attack[index]) then return false end end
    end
    return true
end

function M.new(opts)
    local state, helper = assert(opts.state), assert(opts.lookup_helper)
    local read, write = opts.read or rawget, opts.write or rawset
    local owned, selected, template, weapons, shot_rows, selected_key, failure
    local denied, emitted, logged = setmetatable({}, { __mode = "k" }), 0, {}
    local C = {}
    local function emit(reason, mode)
        if emitted >= 16 or logged[reason] then return end
        logged[reason], emitted = true, emitted + 1
        if type(opts.emit) == "function" then pcall(opts.emit,
            "[cwv:428] owner=old_musket_shot reason=%s mode=%s count=%d/16", reason, mode or "denied", emitted) end
    end
    local function native()
        local profiles, lookup = opts.profiles(), opts.lookup()
        if type(profiles) ~= "table" or type(lookup) ~= "table" then return nil end
        local profile, id = rawget(profiles, NATIVE), rawget(lookup, NATIVE)
        if not native_shape(profile) or not integer(id) or id == 0 or rawget(lookup, id) ~= NATIVE then return nil end
        local snapshot = capture(profile); if not snapshot then return nil end
        return { profiles = profiles, lookup = lookup, profile = profile, id = id, snapshot = snapshot }
    end
    local function native_intact(row)
        return row and opts.profiles() == row.profiles and opts.lookup() == row.lookup
            and rawget(row.profiles, NATIVE) == row.profile
            and rawget(row.lookup, NATIVE) == row.id and rawget(row.lookup, row.id) == NATIVE and intact(row.snapshot)
    end
    local function custom_intact()
        local map, generation = rawget(state, "_cwv_damage_profile_wire_source"), rawget(state, "_cwv_damage_profile_generation")
        return owned and opts.profiles() == owned.profiles and opts.lookup() == owned.lookup
            and rawget(owned.profiles, KEY) == owned.profile and intact(owned.snapshot)
            and rawget(owned.lookup, KEY) == owned.id and rawget(owned.lookup, owned.id) == KEY
            and map == owned.map and rawget(map, KEY) == NATIVE
            and integer(generation) and generation >= owned.generation
            and rawget(state, "_cwv_wire_fallback_profile_id") == owned.fallback
    end
    local function fallback(reason)
        selected = native(); failure = reason
        selected_key = selected and NATIVE or nil
        emit(reason, selected and "native" or "denied")
        return selected_key, reason
    end
    local function scale_profile(source)
        local clone = opts.clone(source)
        if type(clone) ~= "table" or clone == source then return nil end
        local before, after = capture(source), capture(clone)
        if not before or not after then return nil end
        for i = 1, #before do for j = 1, #after do
            if before[i].target == after[j].target then return nil end
        end end
        local function scale(pd)
            if not pd then return end
            if pd.attack then pd.attack = pd.attack * (opts.damage_multiplier or 1.5) end
            if pd.impact then pd.impact = pd.impact * (opts.damage_multiplier or 1.5) end
        end
        if clone.default_target then
            scale(clone.default_target.power_distribution_near)
            scale(clone.default_target.power_distribution_far)
            scale(clone.default_target.power_distribution)
        end
        if type(clone.targets) == "table" then
            for _, target in ipairs(clone.targets) do
                scale(target.power_distribution_near); scale(target.power_distribution_far); scale(target.power_distribution)
            end
        end
        if clone.cleave_distribution then clone.cleave_distribution.attack, clone.cleave_distribution.impact = 1.5, 0.6 end
        for _, name in ipairs({ "armor_modifier_near", "armor_modifier_far" }) do
            local armor = clone[name]
            if armor and armor.attack then
                for index = 4, 6 do if armor.attack[index] then armor.attack[index] = armor.attack[index] + 0.2 end end
            end
        end
        return clone
    end
    local function prepare()
        if owned then
            if custom_intact() then selected_key = KEY; return KEY, "owned" end
            return fallback("retained_custom_lost")
        end
        local donor = native(); if not donor then return fallback("native_unproven") end
        local profiles, lookup = donor.profiles, donor.lookup
        local map, generation = rawget(state, "_cwv_damage_profile_wire_source"), rawget(state, "_cwv_damage_profile_generation")
        local first = rawget(state, "_cwv_wire_fallback_profile_id")
        if type(map) ~= "table" or not integer(generation) or generation >= 9007199254740990 then return fallback("source_state_unproven") end
        if rawget(profiles, KEY) ~= nil or rawget(lookup, KEY) ~= nil or rawget(map, KEY) ~= nil then return fallback("foreign_custom_state") end
        if first ~= nil then
            local name = integer(first) and first > 0 and rawget(lookup, first)
            if type(name) ~= "string" or name:sub(1, 4) == "cwv_" or rawget(lookup, name) ~= first then return fallback("fallback_state_unproven") end
        end
        local detached = {}; for key, value in next, lookup do detached[key] = value end
        local id = helper.register(detached, KEY)
        if not integer(id) or id == 0 then return fallback("lookup_plan_rejected") end
        local clone = scale_profile(donor.profile)
        local snapshot = clone and capture(clone)
        if not snapshot then return fallback("clone_unproven") end
        local fallback_id = first or donor.id
        local changes = {
            { profiles, KEY, clone, "profile" }, { lookup, id, KEY, "numeric" }, { lookup, KEY, id, "reverse" },
            { map, KEY, NATIVE, "source" }, { state, "_cwv_damage_profile_generation", generation + 1, "generation" },
        }
        if first == nil then changes[#changes + 1] = { state, "_cwv_wire_fallback_profile_id", donor.id, "fallback" } end
        for i = 1, #changes do changes[i].before = rawget(changes[i][1], changes[i][2]) end
        local ok = pcall(function()
            for i = 1, #changes do
                local row = changes[i]; write(row[1], row[2], row[3], row[4])
                if read(row[1], row[2], row[4]) ~= row[3] then error("write readback rejected") end
            end
        end)
        if not ok then
            for i = #changes, 1, -1 do local row = changes[i]; rawset(row[1], row[2], row.before) end
            return fallback("commit_rejected")
        end
        owned = { profiles = profiles, lookup = lookup, profile = clone, snapshot = snapshot,
            id = id, map = map, generation = generation + 1, fallback = fallback_id }
        local proven, retained = pcall(custom_intact)
        if not proven or not retained then
            owned = nil
            for i = #changes, 1, -1 do local row = changes[i]; rawset(row[1], row[2], row.before) end
            return fallback("retained_readback_rejected")
        end
        selected, selected_key, failure = nil, KEY, nil
        return KEY, "committed"
    end
    function C.prepare()
        local ok, key, reason = pcall(prepare)
        if ok then return key, reason end
        local recovered, result = pcall(fallback, "preparation_error")
        return recovered and result or nil, "preparation_error"
    end
    function C.reject(reason)
        failure = reason
        emit(reason, "denied")
    end
    local function row_intact(row)
        return rawget(row.action, "damage_profile") == row.key
            and ((row.key == KEY and custom_intact()) or (row.key == NATIVE and native_intact(row.native)))
    end
    function C.publish_template(target, value, rows)
        if type(target) ~= "table" or rawget(target, TEMPLATE) ~= nil or type(value) ~= "table"
                or type(rows) ~= "table" or #rows == 0 or not selected_key then failure = "template_collision_or_unready"; return false end
        if not ((selected_key == KEY and custom_intact()) or (selected_key == NATIVE and native_intact(selected))) then return false end
        local captured = {}
        for i = 1, #rows do
            local row = rows[i]
            if type(row.action) ~= "table" or rawget(row.action, "damage_profile") ~= selected_key then return false end
            captured[i] = { action = row.action, group = row.group, name = row.name, key = selected_key, native = selected }
        end
        local ok = pcall(function()
            write(target, TEMPLATE, value, "template")
            if read(target, TEMPLATE, "template") ~= value then error("template readback rejected") end
        end)
        if not ok then rawset(target, TEMPLATE, nil); failure = "template_publication_rejected"; return false end
        template, weapons, shot_rows = value, target, captured
        return true
    end
    function C.admit(def)
        local ok, ready = pcall(function()
            if type(def) ~= "table" or def.item_key ~= "cwv_es_musket_old" or def.template ~= TEMPLATE or not template
                    or opts.weapons() ~= weapons or rawget(weapons, TEMPLATE) ~= template then return false end
            local actions = rawget(template, "actions")
            for i = 1, #shot_rows do
                local row, group = shot_rows[i], actions and rawget(actions, shot_rows[i].group)
                if type(group) ~= "table" or rawget(group, row.name) ~= row.action or not row_intact(row) then return false end
            end
            return true
        end)
        return ok and ready == true
    end
    function C.check(wrapper)
        if not C.admit({ item_key = "cwv_es_musket_old", template = TEMPLATE }) then return "#428 Old Musket construction/admission unproven: " .. tostring(failure or "retained_authority_lost") end
        if wrapper ~= nil then
            local called = false
            local probe = { current_action = shot_rows[1].action, action_start_t = false, state = "shooting" }
            local ok = pcall(wrapper, function() called = true end, probe, 0, 0, nil, false)
            if not ok or called then return "#428 registered Handgun guard did not contain an unproven start" end
        end
    end
    function C.guard(self, t)
        local action = self and self.current_action
        local row
        for i = 1, #(shot_rows or {}) do if shot_rows[i].action == action then row = shot_rows[i]; break end end
        if not row then return true, "foreign" end
        local start = self.action_start_t
        local previous = denied[self]
        if previous and previous.action == action and previous.start == start then return false, "quarantined" end
        local firing = self.state == "shooting" or (self.state == "waiting_to_shoot"
            and (not number(t) or not number(self.time_to_shoot) or t >= self.time_to_shoot))
        if not firing then return true, "not_firing" end
        local ok, allowed, reason = pcall(function()
            if not number(start) then return false, "start_unproven" end
            if not number(t) or (self.state == "waiting_to_shoot" and not number(self.time_to_shoot)) then return false, "cadence_unproven" end
            if row_intact(row) then return true, row.key == KEY and "custom" or "native" end
            if rawget(action, "damage_profile") ~= row.key then return false, "foreign_action_field" end
            local proof = native(); if not proof then return false, "no_firing_authority" end
            local old = row.key
            local applied = pcall(function()
                write(action, "damage_profile", NATIVE, "action_fallback")
                if read(action, "damage_profile", "action_fallback") ~= NATIVE then error("action readback rejected") end
            end)
            if not applied then rawset(action, "damage_profile", old); return false, "action_fallback_rejected" end
            row.key, row.native = NATIVE, proof
            emit("firing_native_fallback", "native")
            return true, "native"
        end)
        if ok and allowed then return true, reason end
        denied[self] = { action = action, start = start }
        emit(ok and reason or "firing_guard_error", "quarantined")
        return false, ok and reason or "firing_guard_error"
    end
    return C
end
function M.bind(lookup_helper)
    assert(type(lookup_helper) == "table" and type(lookup_helper.register) == "function", "Old Musket lookup helper disconnected")
    return { network_lookup = lookup_helper, new = function(opts)
        local private = {}; for key, value in next, opts do private[key] = value end
        private.lookup_helper = lookup_helper
        return M.new(private)
    end }
end
return M
