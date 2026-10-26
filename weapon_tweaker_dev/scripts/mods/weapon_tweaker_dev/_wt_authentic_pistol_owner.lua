-- #428: local composite registration, not a peer-parity or wire-capacity proof.
-- Called at the original unconditional pistol append position, before Priest.
local M = {}
-- Same-module reentry proves the original closures, never mutable method fields.
local installed = setmetatable({}, { __mode = "k" })
local KEY, SOURCE = "wt_authentic_pistol", "shot_sniper"
local OWNER, CALLBACK = "_wt428_authentic_pistol_owner", "_wt431_brace_repoint"
local FALLBACK, SLOTS = "_wt431_custom_profile_fallback", "_wt431_brace_profile_slots"
local function finite(value)
    return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end
local function copy(value, seen)
    if type(value) ~= "table" then
        assert(type(value) == "nil" or type(value) == "boolean" or type(value) == "string" or finite(value), "profile-value")
        return value
    end
    seen = seen or {}; assert(not seen[value], "profile-cycle"); seen[value] = true
    local result = {}
    for key, item in next, value do
        assert(type(key) == "string" or finite(key), "profile-key")
        rawset(result, key, copy(item, seen))
    end
    seen[value] = nil
    return result
end
local function equal(left, right)
    if left == right then return true end
    if type(left) ~= "table" or type(right) ~= "table" or getmetatable(left) ~= nil then return false end
    for key, value in next, left do if not equal(value, rawget(right, key)) then return false end end
    for key in next, right do if rawget(left, key) == nil then return false end end
    return true
end
local function collect(value, seen)
    if type(value) ~= "table" or seen[value] then return end
    seen[value] = true; for _, item in next, value do collect(item, seen) end
end
local function disjoint(value, forbidden, seen)
    if type(value) ~= "table" then return end
    assert(not forbidden[value] and getmetatable(value) == nil, "clone-alias-or-metatable")
    seen = seen or {}; assert(not seen[value], "clone-cycle"); seen[value] = true
    for _, item in next, value do disjoint(item, forbidden, seen) end
    seen[value] = nil
end
local function shallow(value)
    local result = {}; for key, item in next, value do result[key] = item end; return result
end
local function restore(target, before)
    for key in next, target do rawset(target, key, nil) end
    for key, value in next, before do rawset(target, key, value) end
end
function M.install(mod, deps)
    deps = deps or {}
    local globals, read, write = deps.globals or _G, deps.read or rawget, deps.write or rawset
    local clone = deps.clone or function(value) return table.clone(value, true) end
    local prior = rawget(mod, OWNER)
    if prior ~= nil then
        local retained = installed[mod]
        if type(prior) == "table" and retained and prior == retained.owner
            and rawget(prior, "token") == M and rawget(mod, CALLBACK) == retained.repoint
            and rawget(prior, "repoint") == retained.repoint and rawget(prior, "validate") == retained.validate then
            local ok, valid = pcall(retained.validate)
            if ok and valid then return prior, "already-installed" end
            return nil, "owner-authority-lost"
        end
        return nil, "owner-foreign"
    end
    local prepared, plan = pcall(function()
        assert(mod[CALLBACK] == nil, "callback-foreign")
        local helper = deps.lookup or mod:dofile("scripts/mods/weapon_tweaker_dev/_lib_network_lookup")
        local profiles, network = read(globals, "DamageProfileTemplates"), read(globals, "NetworkLookup")
        assert(type(profiles) == "table" and type(network) == "table", "registry-missing")
        local lookup, donor = read(network, "damage_profiles"), read(profiles, SOURCE)
        assert(type(lookup) == "table" and type(donor) == "table", "source-missing")
        local fallback = rawget(mod, FALLBACK)
        assert(fallback ~= nil or mod[FALLBACK] == nil, "fallback-inherited")
        assert(fallback == nil or type(fallback) == "table", "fallback-malformed")
        assert(rawget(profiles, KEY) == nil and rawget(lookup, KEY) == nil and (not fallback or rawget(fallback, KEY) == nil), "registration-partial-or-foreign")
        local detached = copy(donor)
        local input, forbidden = copy(detached), {}
        collect(donor, forbidden); collect(input, forbidden)
        local profile = clone(input)
        disjoint(profile, forbidden)
        assert(type(profile) == "table" and equal(profile, detached), "clone-malformed")
        profile = copy(profile)
        local near = rawget(profile, "armor_modifier_near")
        assert(near == nil or type(near) == "table", "armor-malformed")
        if near then profile.armor_modifier_far = copy(near) end
        local target = rawget(profile, "default_target")
        assert(type(target) == "table", "target-missing")
        local power = rawget(target, "power_distribution_near")
        assert(power == nil or type(power) == "table", "power-malformed")
        if power then target.power_distribution_far = copy(power) end
        target.range_modifier_settings = nil
        local cleave = rawget(profile, "cleave_distribution")
        assert(type(cleave) == "table" and finite(rawget(cleave, "attack")) and finite(rawget(cleave, "impact")), "cleave-malformed")
        -- Preserve existing 0.3 -> 0.15 values; this migration changes no balance.
        cleave.attack, cleave.impact = cleave.attack / 2, cleave.impact / 2
        local before, shadow = shallow(lookup), shallow(lookup)
        assert(type(helper) == "table" and type(helper.register) == "function", "helper-missing")
        local index, inserted = helper.register(shadow, KEY)
        assert(finite(index) and index > 0 and index % 1 == 0 and inserted == true and rawget(shadow, index) == KEY and rawget(shadow, KEY) == index and rawget(before, index) == nil, "lookup-plan-rejected")
        rawset(shadow, index, nil); rawset(shadow, KEY, nil)
        assert(equal(shadow, before), "lookup-plan-foreign-write")
        local source_index = rawget(before, SOURCE)
        assert(finite(source_index) and source_index > 0 and source_index % 1 == 0 and rawget(before, source_index) == SOURCE, "source-pair-missing")
        return { profiles=profiles, network=network, lookup=lookup, donor=donor, helper=helper,
            fallback=fallback or {}, fallback_before=fallback, profile=profile, expected=copy(profile),
            index=index, source_index=source_index, lookup_before=before }
    end)
    if not prepared then return nil, tostring(plan) end
    local owner = { token=M, ready=false }
    local validate, repoint
    local function authority()
        if not owner.ready or rawget(mod, OWNER) ~= owner or rawget(mod, CALLBACK) ~= repoint
            or rawget(owner, "validate") ~= validate or rawget(owner, "repoint") ~= repoint
            or read(globals, "DamageProfileTemplates") ~= plan.profiles or read(globals, "NetworkLookup") ~= plan.network
            or read(plan.network, "damage_profiles") ~= plan.lookup or read(plan.profiles, SOURCE) ~= plan.donor
            or rawget(plan.profiles, KEY) ~= plan.profile or not equal(plan.profile, plan.expected)
            or rawget(mod, FALLBACK) ~= plan.fallback or rawget(plan.fallback, KEY) ~= SOURCE then return false end
        local shadow = shallow(plan.lookup)
        local index, inserted = plan.helper.register(shadow, KEY)
        return index == plan.index and inserted == false and equal(shadow, plan.lookup)
            and rawget(plan.lookup, SOURCE) == plan.source_index and rawget(plan.lookup, plan.source_index) == SOURCE
    end
    validate = function() local ok, valid = pcall(authority); return ok and valid == true end
    owner.validate = validate
    local binding
    local function capture()
        local slots = rawget(mod, SLOTS)
        if slots == nil then return nil end
        assert(type(slots) == "table", "slots-malformed")
        local count = 0
        for key in next, slots do assert(finite(key) and key >= 1 and key <= 3 and key % 1 == 0, "slots-axis"); count=count+1 end
        if count == 0 then assert(not binding, "slots-replaced"); return nil end
        if binding then assert(slots == binding.slots and count == #binding.rows, "slots-replaced") end
        local rows = {}
        for index=1,count do
            local row = rawget(slots, index)
            assert(type(row) == "table" and type(rawget(row, "impact_data")) == "table" and rawget(row, "custom") == KEY, "slot-malformed")
            local original = rawget(row, "original")
            assert(original == nil or type(original) == "string", "slot-original")
            if binding then
                local old = binding.rows[index]
                assert(row == old.row and rawget(row, "impact_data") == old.action and original == old.original, "slot-replaced")
            end
            rows[index] = {row=row,action=rawget(row,"impact_data"),original=original}
        end
        if not binding then binding={slots=slots,rows=rows} end
        return binding.rows
    end
    repoint = function()
        local ok, rows = pcall(capture)
        local allowed = false
        if ok and rows then
            local safe, value = pcall(function() return authority() and type(mod._wt431_profiles_allowed) == "function" and mod._wt431_profiles_allowed() == true end)
            allowed = safe and value == true
        end
        local actions = binding and binding.rows or {}
        local before = {}
        for index, slot in ipairs(actions) do before[index] = shallow(slot.action) end
        local changed, failure = pcall(function()
            for _, slot in ipairs(actions) do
                local current = rawget(slot.action, "damage_profile")
                if current == KEY or current == slot.original then
                    local desired = allowed and KEY or slot.original
                    write(slot.action, "damage_profile", desired)
                    assert(rawget(slot.action, "damage_profile") == desired, "action-write-rejected")
                elseif allowed then error("action-authority-lost") end
            end
        end)
        if not changed or not ok then
            for index, slot in ipairs(actions) do
                restore(slot.action, before[index])
                if rawget(slot.action,"damage_profile") == KEY then rawset(slot.action,"damage_profile",slot.original) end
            end
            return
        end
    end
    owner.repoint = repoint
    local snapshots = { {plan.profiles,shallow(plan.profiles)}, {plan.lookup,plan.lookup_before}, {plan.fallback,shallow(plan.fallback)}, {mod,shallow(mod)} }
    local committed, failure = pcall(function()
        local function put(target,key,value) write(target,key,value);assert(rawget(target,key)==value,"commit-write-rejected") end
        put(plan.profiles,KEY,plan.profile);put(plan.lookup,plan.index,KEY);put(plan.lookup,KEY,plan.index)
        put(plan.fallback,KEY,SOURCE);put(mod,FALLBACK,plan.fallback);put(mod,OWNER,owner);put(mod,CALLBACK,repoint)
        owner.ready=true;assert(authority(),"commit-authority-lost")
    end)
    if not committed then
        owner.ready=false;for _, snapshot in ipairs(snapshots) do restore(snapshot[1],snapshot[2]) end
        return nil,tostring(failure)
    end
    installed[mod] = { owner=owner, validate=validate, repoint=repoint }
    return owner,"installed"
end
return M
