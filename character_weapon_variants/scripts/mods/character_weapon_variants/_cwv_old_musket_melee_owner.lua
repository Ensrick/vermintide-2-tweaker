-- _cwv_old_musket_melee_owner.lua — #428 bounded bayonet construction owner.
--
-- Owns one four-profile family and the complete effective melee template as
-- an atomic boot transaction. Native donors, paired lookup IDs, source-map
-- generation and the finished interrupt/stance template are retained proofs;
-- native degradation requires the complete donor family, never unchecked names.
-- The private entry-bound guard consumes only this owner's seven action rows;
-- construction proof and retained native action proof remain distinct.
-- Later career reconciliation needs exact canonical references/claims; a
-- career-looking action name alone never exempts a foreign addition.
--
-- Owned by: character_weapon_variants.lua entry point.
-- Consumed via: entry mod:dofile("scripts/mods/character_weapon_variants/_cwv_old_musket_melee_owner") and private factory injection.
local M = {}
local TEMPLATE, DONOR = "old_musket_template_melee", "two_handed_heavy_spears_template"
local PREFIX = "cwv_old_musket_melee_"
local CLAIMS = "__vt2_tweaker_career_action_claims"
local CLONE_SOURCE = "__vt2_tweaker_career_action_clone_source"
local CAREER_SOURCE = TEMPLATE .. "<-" .. DONOR
local SOURCES = { heavy_slashing_tank = true, heavy_slashing_smiter_stab_polearm = true,
    medium_spear_smiter_stab = true, medium_slashing_linesman_spear = true }
local ACTION_FIELDS = { "kind", "damage_profile", "damage_profile_left", "damage_profile_right",
    "weapon_mode_key", "weapon_mode_overrides", "lookup_data", "buff_data", "finish_function",
    "keep_block", "action_aborted_flow_event", "cooldown", "enter_function", "action_selector",
    "baked_sweep", "baked_sweep_left", "baked_sweep_right", "damage_window_start", "damage_window_end",
    "anim_end_event", "anim_end_event_1p", "anim_end_event_3p", "anim_end_event_condition_func", "looping_anim" }
local CLEANUP_FIELDS = { "finish_function", "keep_block", "action_aborted_flow_event", "cooldown" }
local CLEANUP_READS = { "kind", "buff_data", "anim_end_event", "anim_end_event_1p", "anim_end_event_3p",
    "anim_end_event_condition_func", "looping_anim" }
local function finite(value)
    return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end
local function integer(value)
    return finite(value) and value >= 0 and value < 9007199254740991 and value % 1 == 0
end
local function career_key(key)
    return type(key) == "string" and key:sub(1, 14) == "action_career_"
end
local function template_proof(template, capture)
    local actions = rawget(template, "actions")
    local initial = { claims = rawget(template, CLAIMS), source = rawget(template, CLONE_SOURCE), rows = {} }
    initial.claims_snapshot = type(initial.claims) == "table" and capture(initial.claims, 256, 2048)
    for key, value in next, actions do
        if career_key(key) then
            initial.rows[key] = { value = value, snapshot = capture(value, 256, 2048) }
        end
    end
    local function include(t, key)
        return not ((t == template and (key == CLAIMS or key == CLONE_SOURCE)) or (t == actions and career_key(key)))
    end
    return capture(template, 1024, 8192, include), initial
end
local function extensions_intact(proof, action_templates, intact)
    local template, initial = proof.template, proof.extensions
    local actions = rawget(template, "actions")
    if type(actions) ~= "table" then return false end
    local unchanged = rawget(template, CLAIMS) == initial.claims and rawget(template, CLONE_SOURCE) == initial.source
        and (initial.claims == nil or (initial.claims_snapshot and intact(initial.claims_snapshot)))
    for name, row in next, initial.rows do
        if rawget(actions, name) ~= row.value or not intact(row.snapshot) then unchanged = false end
    end
    for name in next, actions do
        if career_key(name) and not initial.rows[name] then unchanged = false end
    end
    if unchanged then return true end
    if type(action_templates) ~= "table" or rawget(template, CLONE_SOURCE) ~= CAREER_SOURCE then return false end
    local claims, donor_actions = rawget(template, CLAIMS), rawget(proof.source, "actions")
    if type(claims) ~= "table" or getmetatable(claims) ~= nil or type(donor_actions) ~= "table" then return false end
    local count = 0
    local function owned_claim(name, canonical)
        local row = rawget(claims, name)
        return type(row) == "table" and rawget(row, "value") == canonical
            and type(rawget(row, "baseline_present")) == "boolean"
            and type(rawget(row, "owners")) == "table"
            and rawget(rawget(row, "owners"), "character_weapon_variants") == true
    end
    for name, value in next, actions do
        if career_key(name) then
            count = count + 1
            local canonical = rawget(action_templates, name)
            if count > 64 or type(canonical) ~= "table" or value ~= canonical then return false end
            local inherited = initial.rows[name] and rawget(donor_actions, name) == canonical
            if not inherited and not owned_claim(name, canonical) then return false end
        end
    end
    count = 0
    for name in next, claims do
        count = count + 1
        local canonical = career_key(name) and rawget(action_templates, name)
        if count > 64 or type(canonical) ~= "table" or rawget(actions, name) ~= canonical
                or not owned_claim(name, canonical) then return false end
    end
    return true
end
local function profile_shape(profile)
    if type(profile) ~= "table" or type(rawget(profile, "charge_value")) ~= "string" then return false end
    local cleave, armor, target = rawget(profile, "cleave_distribution"), rawget(profile, "armor_modifier"), rawget(profile, "default_target")
    if type(cleave) ~= "table" or not finite(rawget(cleave, "attack")) or not finite(rawget(cleave, "impact"))
            or type(armor) ~= "table" or type(target) ~= "table" then return false end
    for _, key in ipairs({ "attack", "impact" }) do
        local values = rawget(armor, key)
        if type(values) ~= "table" then return false end
        -- Base 6.13 PowerLevel melee arrays have five authored armor entries;
        -- the ranged owner's six-entry shape is not a melee authority contract.
        for i = 1, 5 do if not finite(rawget(values, i)) then return false end end
        if rawget(values, 6) ~= nil and not finite(rawget(values, 6)) then return false end
    end
    local function target_shape(row)
        if type(row) ~= "table" then return false end
        local found = false
        for _, key in ipairs({ "power_distribution", "power_distribution_near", "power_distribution_far" }) do
            local pd = rawget(row, key)
            if pd ~= nil then
                if type(pd) ~= "table" or not finite(rawget(pd, "attack")) or not finite(rawget(pd, "impact")) then return false end
                found = true
            end
        end
        return found
    end
    if not target_shape(target) then return false end
    local targets = rawget(profile, "targets")
    if type(targets) ~= "table" then return false end
    for index, row in next, targets do
        if not integer(index) or index == 0 or not target_shape(row) then return false end
    end
    return true
end

function M.new(opts)
    local helper, state = assert(opts.lookup_helper), assert(opts.state)
    local mechanics = assert(opts.mechanics, "Old Musket private graph mechanics missing")
    local capture, intact = mechanics.capture, mechanics.intact
    local disjoint, commit = mechanics.disjoint, mechanics.commit
    local sweep_factory = assert(opts.sweep_guard_factory, "Old Musket private retained Sweep factory missing")
    local read, write = opts.read or rawget, opts.write or rawset
    local owned, failure, emitted = nil, "not_constructed", {}
    local C = {}
    local function sweep_capability(proof)
        local actions, by_action, paths, total = rawget(proof.template, "actions"), {}, {}, 0
        for group_name, group in next, actions do
            if type(group) == "table" then
                for name, action in next, group do
                    if type(action) == "table" and rawget(action, "kind") == "sweep" then
                        -- Native7 are plain tables. Raw-absent cleanup cells
                        -- cannot prove an inherited __index callback harmless.
                        if getmetatable(action) ~= nil then return nil end
                        local key = rawget(action, "damage_profile")
                        local source = proof.mode == "custom" and type(key) == "string" and key:sub(#PREFIX + 1) or key
                        local selected = proof.mode == "custom" and proof.custom[source] or proof.native[source]
                        if not selected or by_action[action] then return nil end
                        local row = { action = action, group = group, group_name = group_name, name = name,
                            key = key, source = source, id = selected.id, profile = selected.profile, snapshot = selected.snapshot,
                            meta = getmetatable(action), values = {}, cleanup_values = {}, lookup = rawget(action, "lookup_data") }
                        for i = 1, #ACTION_FIELDS do row.values[i] = rawget(action, ACTION_FIELDS[i]) end
                        for i = 1, #CLEANUP_READS do row.cleanup_values[i] = rawget(action, CLEANUP_READS[i]) end
                        for i = 1, #CLEANUP_FIELDS do if rawget(action, CLEANUP_FIELDS[i]) ~= nil then return nil end end
                        if rawget(action, "weapon_mode_key") ~= nil or rawget(action, "weapon_mode_overrides") ~= nil
                                or rawget(action, "damage_profile_left") ~= nil or rawget(action, "damage_profile_right") ~= nil then return nil end
                        row.lookup_snapshot = capture(row.lookup, 4, 16)
                        local buff = rawget(action, "buff_data")
                        row.buff_snapshot = buff ~= nil and capture(buff, 16, 64) or nil
                        if not row.lookup_snapshot or (buff ~= nil and not row.buff_snapshot) then return nil end
                        paths[group_name] = paths[group_name] or {}; paths[group_name][name] = row
                        by_action[action], total = row, total + 1
                    end
                end
            end
        end
        if total ~= 7 then return nil end
        local function cleanup(row)
            if getmetatable(row.action) ~= row.meta then return false end
            for i = 1, #CLEANUP_FIELDS do if rawget(row.action, CLEANUP_FIELDS[i]) ~= nil then return false end end
            for i = 1, #CLEANUP_READS do if rawget(row.action, CLEANUP_READS[i]) ~= row.cleanup_values[i] then return false end end
            if row.buff_snapshot and not intact(row.buff_snapshot, true) then return false end
            return true
        end
        local function valid(row)
            if opts.profiles() ~= proof.profiles or opts.lookup() ~= proof.lookup or opts.weapons() ~= proof.weapons
                    or rawget(proof.weapons, TEMPLATE) ~= proof.template or rawget(proof.template, "actions") ~= actions
                    or rawget(actions, row.group_name) ~= row.group or rawget(row.group, row.name) ~= row.action
                    or getmetatable(row.action) ~= row.meta then return false end
            for i = 1, #ACTION_FIELDS do if rawget(row.action, ACTION_FIELDS[i]) ~= row.values[i] then return false end end
            if not intact(row.lookup_snapshot, true) or (row.buff_snapshot and not intact(row.buff_snapshot, true))
                    or rawget(proof.profiles, row.key) ~= row.profile or not intact(row.snapshot, true)
                    or rawget(proof.lookup, row.key) ~= row.id or rawget(proof.lookup, row.id) ~= row.key then return false end
            if proof.mode == "custom" then
                local generation = rawget(state, "_cwv_damage_profile_generation")
                if rawget(state, "_cwv_damage_profile_wire_source") ~= proof.map or not integer(generation)
                        or generation < proof.generation or rawget(proof.map, row.key) ~= row.source
                        or rawget(state, "_cwv_wire_fallback_profile_id") ~= proof.fallback then return false end
            end
            return true
        end
        return {
            member = function(action) return by_action[action] end,
            classify = function(root, group_name, name)
                local group = type(root) == "table" and rawget(root, group_name)
                local action = type(group) == "table" and rawget(group, name)
                local row = root == actions and paths[group_name] and paths[group_name][name] or by_action[action]
                if row and (root ~= actions or group_name ~= row.group_name or name ~= row.name) then return nil, true end
                return row, row ~= nil
            end,
            valid = function(row) local ok, result = pcall(valid, row); return ok and result == true end,
            cleanup = cleanup,
        }
    end
    local function emit(reason, mode)
        if emitted[reason] then return end
        local count = 0
        for _ in next, emitted do count = count + 1 end
        if count >= 16 then return end
        emitted[reason] = true
        if type(opts.emit) == "function" then pcall(opts.emit,
            "[cwv:428] owner=old_musket_melee reason=%s mode=%s profiles=4 records=7 count=%d/16", reason, mode, count + 1) end
    end
    local function native_rows(profiles, lookup)
        if type(profiles) ~= "table" or type(lookup) ~= "table" then return nil end
        local rows = {}
        for name in next, SOURCES do
            local profile, id = rawget(profiles, name), rawget(lookup, name)
            if not profile_shape(profile) or not integer(id) or id == 0 or rawget(lookup, id) ~= name then return nil end
            local snapshot = capture(profile, 64, 512)
            if not snapshot then return nil end
            rows[name] = { profile = profile, id = id, snapshot = snapshot }
        end
        return rows
    end
    local function native_intact(proof)
        for name, row in next, proof.native do
            if rawget(proof.profiles, name) ~= row.profile or not intact(row.snapshot)
                    or rawget(proof.lookup, name) ~= row.id or rawget(proof.lookup, row.id) ~= name then return false end
        end
        return true
    end
    local function retained(proof)
        if not proof or opts.profiles() ~= proof.profiles or opts.lookup() ~= proof.lookup
                or opts.weapons() ~= proof.weapons or rawget(proof.weapons, TEMPLATE) ~= proof.template
                or not intact(proof.template_snapshot)
                or not extensions_intact(proof, opts.action_templates and opts.action_templates(), intact) then return false end
        if proof.mode == "native" then return native_intact(proof) end
        if rawget(state, "_cwv_damage_profile_wire_source") ~= proof.map
                or not integer(rawget(state, "_cwv_damage_profile_generation"))
                or rawget(state, "_cwv_damage_profile_generation") < proof.generation
                or rawget(state, "_cwv_wire_fallback_profile_id") ~= proof.fallback then return false end
        for name, row in next, proof.custom do
            local key = PREFIX .. name
            if rawget(proof.profiles, key) ~= row.profile or not intact(row.snapshot)
                    or rawget(proof.lookup, key) ~= row.id or rawget(proof.lookup, row.id) ~= key
                    or rawget(proof.map, key) ~= name then return false end
        end
        return true
    end
    function C.ready()
        local ok, result = pcall(retained, owned)
        return ok and result == true
    end
    function C.template()
        return C.runtime_admitted() and owned.template or nil
    end
    function C.install_sweep_guard(mod) return owned and owned.guard.install(mod) == true or false end
    function C.runtime_admitted() return C.ready() and owned.guard.ready() end
    function C.register_sweep_check(register)
        register("issue428_old_musket_retained_sweep", function()
            if not owned then return "#428 Old Musket retained Sweep capability not constructed" end
            return owned.guard.check()
        end)
    end
    local function construct(source, finish, mode)
        local profiles, lookup, weapons = opts.profiles(), opts.lookup(), opts.weapons()
        local donors = native_rows(profiles, lookup)
        if not donors or type(weapons) ~= "table" or rawget(weapons, DONOR) ~= source
                or rawget(weapons, TEMPLATE) ~= nil then return false, "native_or_template_unproven" end
        local source_snapshot = capture(source, 1024, 8192)
        local template = opts.clone(source)
        if not disjoint(source_snapshot, capture(template, 1024, 8192)) then return false, "template_clone_unproven" end
        local actions = rawget(template, "actions")
        if type(actions) ~= "table" then return false, "actions_unproven" end
        local map, generation = rawget(state, "_cwv_damage_profile_wire_source"), rawget(state, "_cwv_damage_profile_generation")
        local first = rawget(state, "_cwv_wire_fallback_profile_id")
        local captured_first = first
        local detached, custom, changes, records, seen = {}, {}, {}, 0, {}
        for key, value in next, lookup do detached[key] = value end
        local function stage(t, key, value, tag)
            changes[#changes + 1] = { t, key, value, tag, before = rawget(t, key) }
        end
        if mode == "custom" then
            if type(map) ~= "table" or not integer(generation) or generation > 9007199254740983 then return false, "source_state_unproven" end
            if first ~= nil then
                local name = integer(first) and first > 0 and rawget(lookup, first)
                if type(name) ~= "string" or name:sub(1, 4) == "cwv_" or rawget(lookup, name) ~= first then return false, "fallback_unproven" end
            end
        end
        -- Keep the original clone's actual pairs encounter order: IDs are not sorted.
        for _, group in pairs(actions) do
            if type(group) == "table" then
                for _, action in pairs(group) do
                    if type(action) == "table" then
                        if action.range_mod then action.range_mod = 1.2 end
                        local name = action.damage_profile
                        if name ~= nil then
                            if type(name) ~= "string" or not SOURCES[name] or action.kind ~= "sweep" then return false, "consumer_unproven" end
                            records = records + 1
                            seen[name] = true
                            if mode == "custom" then
                                local key = PREFIX .. name
                                if not custom[name] then
                                    if rawget(profiles, key) ~= nil or rawget(lookup, key) ~= nil or rawget(map, key) ~= nil then return false, "foreign_custom_state" end
                                    local id = helper.register(detached, key)
                                    if not integer(id) or id == 0 then return false, "lookup_plan_rejected" end
                                    local clone = opts.clone(donors[name].profile)
                                    if not disjoint(donors[name].snapshot, capture(clone, 64, 512)) then return false, "profile_clone_unproven" end
                                    local function scale(target)
                                        if not target then return end
                                        for _, field in ipairs({ "power_distribution", "power_distribution_near", "power_distribution_far" }) do
                                            local pd = target[field]
                                            if pd and pd.attack then pd.attack = pd.attack * 0.9 end
                                        end
                                    end
                                    scale(clone.default_target)
                                    for _, target in ipairs(clone.targets) do scale(target) end
                                    custom[name] = { profile = clone, id = id, snapshot = capture(clone, 64, 512) }
                                    stage(profiles, key, clone, "profile:" .. name)
                                    stage(lookup, id, key, "numeric:" .. name)
                                    stage(lookup, key, id, "reverse:" .. name)
                                    stage(map, key, name, "source:" .. name)
                                end
                                if first == nil then first = donors[name].id end
                                action.damage_profile = key
                            end
                        end
                    end
                end
            end
        end
        local unique = 0
        for _ in next, seen do unique = unique + 1 end
        if records ~= 7 or unique ~= 4 then return false, "consumer_family_changed" end
        -- This includes stance callback, interrupt installation and lookup metadata.
        if finish(template) ~= true then return false, "template_finish_rejected" end
        local template_snapshot, extensions = template_proof(template, capture)
        if not template_snapshot then return false, "finished_template_unproven" end
        if mode == "custom" then
            -- The production finish is pure, but it remains an injected owner
            -- boundary. Never adopt post-finish raw preimages or rewind a
            -- generation/source authority changed while the template finished.
            if rawget(state, "_cwv_damage_profile_wire_source") ~= map
                    or rawget(state, "_cwv_damage_profile_generation") ~= generation
                    or rawget(state, "_cwv_wire_fallback_profile_id") ~= captured_first then
                return false, "finish_source_preimage_changed"
            end
            stage(state, "_cwv_damage_profile_generation", generation + records, "generation")
            if captured_first == nil then stage(state, "_cwv_wire_fallback_profile_id", first, "fallback") end
        end
        stage(weapons, TEMPLATE, template, "template")
        local proof = { mode = mode, profiles = profiles, lookup = lookup, weapons = weapons,
            template = template, template_snapshot = template_snapshot, extensions = extensions, source = source, native = donors,
            custom = custom, map = map, generation = mode == "custom" and generation + records, fallback = first }
        local capability = sweep_capability(proof)
        if not capability then return false, "sweep_capability_unproven" end
        proof.guard = sweep_factory(capability)
        local ok = commit(changes, function()
            if opts.profiles() ~= profiles or opts.lookup() ~= lookup or opts.weapons() ~= weapons
                    or rawget(weapons, DONOR) ~= source or not intact(source_snapshot)
                    or not native_intact(proof) then error("source changed during construction") end
        end, function()
            if not retained(proof) then error("complete retained proof rejected") end
        end, read, write)
        if not ok then return false, "family_commit_rejected" end
        owned, failure = proof, nil
        emit("constructed", mode)
        return true
    end
    function C.construct(source, finish)
        if owned then return C.ready(), owned.mode end
        local ok, result, reason = pcall(construct, source, finish, "custom")
        if ok and result then return true, "custom" end
        failure = ok and reason or "construction_error"
        local rejected = failure
        local native_ok, native_result = pcall(construct, source, finish, "native")
        if native_ok and native_result then emit(rejected, "native"); return true, "native" end
        emit(failure, "denied")
        return false
    end
    function C.check()
        if not C.ready() then return "#428 Old Musket melee construction unproven: " .. tostring(failure or "retained_authority_lost") end
    end
    return C
end
function M.bind(helper, mechanics, sweep_guard_factory)
    assert(type(helper) == "table" and type(helper.register) == "function", "Old Musket melee lookup helper missing")
    local register = helper.register
    assert(type(sweep_guard_factory) == "function", "Old Musket private retained Sweep factory missing")
    local guard_factory = sweep_guard_factory
    local captured = {}
    for _, name in ipairs({ "capture", "intact", "disjoint", "commit" }) do
        local value = type(mechanics) == "table" and rawget(mechanics, name)
        assert(type(value) == "function", "Old Musket private graph function missing: " .. name)
        captured[name] = value
    end
    return function(opts)
        local private = {}
        for key, value in pairs(opts) do private[key] = value end
        private.lookup_helper = { register = register }
        private.mechanics = captured
        private.sweep_guard_factory = guard_factory
        return M.new(private)
    end
end
return M
