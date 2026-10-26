-- #428: one atomic damage-profile/lookup/fallback owner, at the old load position.
-- No native table is passed to clone/helper code. The canonical lookup helper
-- plans against a shadow; only its two proven append cells are committed.
local M = {}
local KEY, SOURCE = "wt_priest_punch_buffed", "light_blunt_smiter_stab"
local TEMPLATE = "two_handed_hammer_priest_template"
local OWNER, CALLBACK = "_wt428_priest_punch_owner", "wt_apply_priest_punch_buff"
local FALLBACK = "_wt431_custom_profile_fallback"

local function copy(value, seen)
    if type(value) ~= "table" then
        local kind = type(value)
        assert(kind == "nil" or kind == "boolean" or kind == "string"
            or (kind == "number" and value == value and value ~= math.huge and value ~= -math.huge),
            "profile-value")
        return value
    end
    seen = seen or {}
    assert(not seen[value], "profile-cycle")
    seen[value] = true
    local result = {}
    for key, item in next, value do
        assert(type(key) == "string" or (type(key) == "number" and key == key
            and key ~= math.huge and key ~= -math.huge), "profile-key")
        rawset(result, key, copy(item, seen))
    end
    seen[value] = nil
    return result
end

local function equal(left, right, plain)
    if left == right then return true end
    if type(left) ~= "table" or type(right) ~= "table" then return false end
    if plain and (getmetatable(left) ~= nil or getmetatable(right) ~= nil) then return false end
    for key, value in next, left do
        if not equal(value, rawget(right, key), plain) then return false end
    end
    for key in next, right do
        if rawget(left, key) == nil then return false end
    end
    return true
end

local function shallow(value)
    local result = {}
    for key, item in next, value do result[key] = item end
    return result
end

local function restore(target, before)
    for key in next, target do rawset(target, key, nil) end
    for key, value in next, before do rawset(target, key, value) end
end

local function finite(value)
    return type(value) == "number" and value == value
        and value ~= math.huge and value ~= -math.huge
end

function M.install(mod, deps)
    deps = deps or {}
    local globals = deps.globals or _G
    local read = deps.read or rawget
    local write = deps.write or rawset
    local clone = deps.clone or function(value) return table.clone(value, true) end
    local helper
    local prior = rawget(mod, OWNER)
    if prior ~= nil then
        if type(prior) == "table" and rawget(prior, "token") == M
                and rawget(mod, CALLBACK) == rawget(prior, "apply") then
            local valid, ready = pcall(rawget(prior, "validate"))
            if valid and ready then return prior, "already-installed" end
            return nil, "owner-authority-lost"
        end
        return nil, "owner-foreign"
    end

    local prepared, plan = pcall(function()
        helper = deps.lookup or mod:dofile("scripts/mods/weapon_tweaker_dev/_lib_network_lookup")
        assert(mod[CALLBACK] == nil, "callback-foreign")
        local profiles = read(globals, "DamageProfileTemplates")
        local powers = read(globals, "PowerLevelTemplates")
        local network = read(globals, "NetworkLookup")
        local weapons = read(globals, "Weapons")
        assert(type(profiles) == "table" and type(powers) == "table"
            and type(network) == "table" and type(weapons) == "table", "registry-missing")
        local lookup = read(network, "damage_profiles")
        local donor = read(profiles, SOURCE)
        local template = read(weapons, TEMPLATE)
        assert(type(lookup) == "table" and type(donor) == "table"
            and type(template) == "table", "source-missing")
        local actions = read(template, "actions")
        assert(type(actions) == "table", "actions-missing")
        local slots, seen = {}, {}
        for _, group in next, actions do
            local punch = type(group) == "table" and read(group, "punch")
            if punch ~= nil then
                assert(type(punch) == "table", "punch-malformed")
                local original = read(punch, "damage_profile")
                assert(original == nil or original == SOURCE, "punch-foreign")
                if not seen[punch] then
                    slots[#slots + 1] = { action = punch, original = original }
                    seen[punch] = true
                end
            end
        end
        assert(#slots > 0, "punch-missing")
        local fallback = rawget(mod, FALLBACK)
        assert(fallback ~= nil or mod[FALLBACK] == nil, "fallback-foreign")
        assert(fallback == nil or type(fallback) == "table", "fallback-malformed")
        assert(rawget(profiles, KEY) == nil and rawget(lookup, KEY) == nil
            and (not fallback or rawget(fallback, KEY) == nil), "registration-partial-or-foreign")
        local detached = copy(donor)
        local profile = clone(copy(detached))
        assert(type(profile) == "table" and equal(profile, detached), "clone-malformed")
        -- Clone output is copied again: a hostile clone cannot retain a mutable
        -- alias to the eventual registered profile or a native power-level node.
        profile = copy(profile)
        local function scaled(node)
            if type(node) == "string" then node = read(powers, node) end
            assert(type(node) == "table", "target-missing")
            local result = copy(node)
            local distribution = rawget(result, "power_distribution")
            assert(type(distribution) == "table"
                and finite(rawget(distribution, "attack"))
                and finite(rawget(distribution, "impact")), "distribution-malformed")
            distribution.attack, distribution.impact = distribution.attack * 2, distribution.impact * 3
            assert(finite(distribution.attack) and finite(distribution.impact), "distribution-overflow")
            return result
        end
        profile.default_target = scaled(rawget(profile, "default_target"))
        local targets = rawget(profile, "targets")
        if type(targets) == "string" then targets = read(powers, targets) end
        assert(type(targets) == "table", "targets-missing")
        local count = 0
        for key in next, targets do
            assert(finite(key) and key >= 1 and key % 1 == 0, "targets-malformed")
            count = count + 1
        end
        profile.targets = {}
        for index = 1, count do profile.targets[index] = scaled(rawget(targets, index)) end

        local before, shadow = shallow(lookup), shallow(lookup)
        assert(type(helper) == "table" and type(helper.register) == "function", "helper-missing")
        local index, inserted = helper.register(shadow, KEY)
        assert(finite(index) and index > 0 and index % 1 == 0 and inserted == true
            and rawget(shadow, index) == KEY and rawget(shadow, KEY) == index
            and rawget(before, index) == nil, "lookup-plan-rejected")
        rawset(shadow, index, nil)
        rawset(shadow, KEY, nil)
        assert(equal(shadow, before), "lookup-plan-foreign-write")
        local source_index = rawget(before, SOURCE)
        assert(finite(source_index) and source_index > 0 and source_index % 1 == 0
            and rawget(before, source_index) == SOURCE, "source-pair-missing")
        return { profiles = profiles, powers = powers, network = network, weapons = weapons,
            lookup = lookup, donor = donor, template = template, actions = actions, slots = slots, slot_set = seen,
            fallback = fallback or {}, fallback_before = fallback, profile = profile,
            expected = copy(profile), index = index, source_index = source_index, lookup_before = before }
    end)
    if not prepared then return nil, tostring(plan) end

    local owner = { token = M, ready = false }
    local function authority()
        if not owner.ready or rawget(mod, OWNER) ~= owner or rawget(mod, CALLBACK) ~= owner.apply
            or read(globals, "DamageProfileTemplates") ~= plan.profiles
            or read(globals, "PowerLevelTemplates") ~= plan.powers
            or read(globals, "NetworkLookup") ~= plan.network
            or read(globals, "Weapons") ~= plan.weapons
            or read(plan.network, "damage_profiles") ~= plan.lookup
            or read(plan.weapons, TEMPLATE) ~= plan.template
            or read(plan.template, "actions") ~= plan.actions
            or read(plan.profiles, SOURCE) ~= plan.donor
            or rawget(plan.profiles, KEY) ~= plan.profile
            or not equal(plan.profile, plan.expected, true)
            or rawget(mod, FALLBACK) ~= plan.fallback
            or rawget(plan.fallback, KEY) ~= SOURCE then return false end
        local seen, count = {}, 0
        for _, group in next, plan.actions do
            local punch = type(group) == "table" and read(group, "punch")
            if punch ~= nil then
                if not plan.slot_set[punch] then return false end
                if not seen[punch] then seen[punch], count = true, count + 1 end
            end
        end
        if count ~= #plan.slots then return false end
        local shadow = shallow(plan.lookup)
        local index, inserted = helper.register(shadow, KEY)
        return index == plan.index and inserted == false and equal(shadow, plan.lookup)
            and rawget(plan.lookup, SOURCE) == plan.source_index
            and rawget(plan.lookup, plan.source_index) == SOURCE
    end
    owner.apply = function()
        local allowed, enabled = false, false
        local ok = pcall(function()
            allowed = authority() and type(mod._wt431_profiles_allowed) == "function"
                and mod._wt431_profiles_allowed() == true
            enabled = allowed and mod:get("wt_priest_punch_buff") and true or false
        end)
        if not ok then enabled = false end
        local before = {}
        for index, slot in ipairs(plan.slots) do before[index] = { rawget(slot.action, "damage_profile") } end
        local applied, failure = pcall(function()
            for _, slot in ipairs(plan.slots) do
                local current = rawget(slot.action, "damage_profile")
                -- Never clobber an independently replaced action/profile.
                if current == slot.original or current == SOURCE or current == KEY then
                    local desired = enabled and KEY or (slot.original or SOURCE)
                    write(slot.action, "damage_profile", desired)
                    assert(rawget(slot.action, "damage_profile") == desired, "action-write-rejected")
                elseif enabled then error("action-authority-lost") end
            end
        end)
        if not applied then
            for index, slot in ipairs(plan.slots) do
                local original = before[index][1]
                rawset(slot.action, "damage_profile", original == KEY and (slot.original or SOURCE) or original)
            end
            return false, tostring(failure)
        end
        return true
    end
    owner.validate = function()
        local ok, valid = pcall(authority)
        return ok and valid == true
    end
    local snapshots = {
        { plan.profiles, shallow(plan.profiles) }, { plan.lookup, plan.lookup_before },
        { plan.fallback, shallow(plan.fallback) }, { mod, shallow(mod) },
    }
    for _, slot in ipairs(plan.slots) do snapshots[#snapshots + 1] = { slot.action, shallow(slot.action) } end
    local committed, failure = pcall(function()
        local function put(target, key, value)
            write(target, key, value)
            assert(rawget(target, key) == value, "commit-write-rejected")
        end
        put(plan.profiles, KEY, plan.profile)
        put(plan.lookup, plan.index, KEY)
        put(plan.lookup, KEY, plan.index)
        put(plan.fallback, KEY, SOURCE)
        put(mod, FALLBACK, plan.fallback)
        put(mod, OWNER, owner)
        put(mod, CALLBACK, owner.apply)
        owner.ready = true
        assert(authority(), "commit-authority-lost")
        local applied, apply_error = owner.apply()
        assert(applied, apply_error)
    end)
    if not committed then
        owner.ready = false
        for _, snapshot in ipairs(snapshots) do restore(snapshot[1], snapshot[2]) end
        return nil, tostring(failure)
    end
    return owner, "installed"
end

return M
