-- #645 retained Tuskgor-on-Elf-Spear construction; no selectable style admission.
-- Borrows action_one + native FP graph declaration, retaining the receiver's
-- non-attack body, block/inspect/wield actions, stamina/dodge and push radius.
-- Existing private scalar factory and graph journal own math/audit/publication.
-- No style catalogue, resource request, actor admission, persistence or event map.
local M = {}
local DONOR, RECEIVER = "two_handed_heavy_spears_template", "two_handed_spears_elf_template_1"
local KEY, PREFIX = "cwv_645_tuskgor_spear_style", "cwv_645_tuskgor_spear_"
local MODIFIERS = { damage = 1, stagger = .85, cleave = .85 }
local NODES = {
    { "default", "melee_start" }, { "default_left", "melee_start" },
    { "default_last_1", "melee_start" }, { "default_last_2", "melee_start" },
    { "heavy_attack_tank", "sweep", "heavy_slashing_tank", .8 },
    { "heavy_attack_left", "sweep", "heavy_slashing_smiter_stab_polearm", .84 },
    { "light_attack_left", "sweep", "medium_spear_smiter_stab", .76 },
    { "light_attack_right", "sweep", "medium_slashing_linesman_spear", .88 },
    { "light_attack_stab_1", "sweep", "medium_spear_smiter_stab", .68 },
    { "light_attack_stab_2", "sweep", "medium_spear_smiter_stab", .8 },
    { "light_attack_bopp", "sweep", "heavy_slashing_tank", .8 },
    { "push", "push_stagger", "medium_push", nil, "light_push" },
}
local SOURCES = { "heavy_slashing_tank", "heavy_slashing_smiter_stab_polearm",
    "medium_spear_smiter_stab", "medium_slashing_linesman_spear", "medium_push", "light_push" }
local CRITICAL = { heavy_slashing_tank = 5, heavy_slashing_smiter_stab_polearm = 5,
    medium_spear_smiter_stab = 5, medium_slashing_linesman_spear = 5 }
local PROFILE_FIELDS = { "cleave_distribution", "default_target", "targets", "critical_strike", "armor_modifier" }
local SCALED = { cleave_distribution = true, default_target = true, targets = true, critical_strike = true }
local HAND_FIELDS = { "damage_profile_left", "damage_profile_right", "damage_profile_inner_left",
    "damage_profile_inner_right", "damage_profile_outer_left", "damage_profile_outer_right" }
local function finite(n) return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge end
local function integer(n) return finite(n) and n >= 0 and n < 9007199254740991 and n % 1 == 0 end
local function plain(t) return type(t) == "table" and getmetatable(t) == nil end
local function close(a, b) return finite(a) and math.abs(a - b) <= 1e-12 end
local function array(t, n)
    if not plain(t) then return false end
    local count = 0
    for k, v in next, t do
        if not integer(k) or k < 1 or k > n or not finite(v) then return false end
        count = count + 1
    end
    return count == n
end
local function resolved(profile, levels, key)
    local v = rawget(profile, key); return type(v) == "string" and rawget(levels, v) or v
end
local function target(t)
    local p = plain(t) and rawget(t, "power_distribution")
    return plain(p) and finite(rawget(p, "attack")) and finite(rawget(p, "impact"))
end
local function profile_shape(p, levels, name)
    if not plain(p) or type(rawget(p, "charge_value")) ~= "string" then return false end
    local c, d = resolved(p, levels, "cleave_distribution"), resolved(p, levels, "default_target")
    if not plain(c) or not finite(rawget(c, "attack")) or not finite(rawget(c, "impact")) or not target(d) then return false end
    local critical, rows = resolved(p, levels, "critical_strike"), resolved(p, levels, "targets")
    if CRITICAL[name] then
        if not plain(critical) or not array(rawget(critical, "attack_armor_power_modifer"), 5)
                or not array(rawget(critical, "impact_armor_power_modifer"), CRITICAL[name]) then return false end
        local n = 0; for k in next, critical do
            if k ~= "attack_armor_power_modifer" and k ~= "impact_armor_power_modifer" then return false end
            n = n + 1
        end
        if n ~= 2 or not plain(rows) then return false end
    elseif critical ~= nil or rawget(p, "no_damage") ~= true or rawget(p, "is_push") ~= true then return false end
    if rows ~= nil then
        if not plain(rows) then return false end
        for k, row in next, rows do if type(k) == "number" and not target(row) then return false end end
    end
    return true
end
function M.bind(helper, graph, history, career, integration, canonical_for)
    local register = assert(helper.register)
    local capture, intact, disjoint, commit = assert(graph.capture), assert(graph.intact), assert(graph.disjoint), assert(graph.commit)
    assert(type(history) == "table", "Tuskgor typed history capability required")
    local history_capture, history_intact, history_include = assert(history.capture), assert(history.intact), assert(history.include)
    assert(type(history_capture) == "function" and type(history_intact) == "function" and type(history_include) == "function",
        "Tuskgor typed history functions required")
    -- Omitted career dependencies preserve the strict-native leaf contract.
    -- The installed family supplies all three; partial wiring never falls back.
    local career_capture, career_intact, prepare_clone
    if career ~= nil or integration ~= nil or canonical_for ~= nil then
        assert(plain(career) and plain(integration) and type(canonical_for) == "function",
            "Tuskgor typed career capability required")
        career_capture, career_intact = rawget(career, "capture"), rawget(career, "intact")
        prepare_clone = rawget(integration, "prepare_inherited_clone")
        assert(type(career_capture) == "function" and type(career_intact) == "function"
            and type(prepare_clone) == "function", "Tuskgor typed career functions required")
    end
    return function(o)
        local clone, scalar, state = assert(o.clone), assert(o.scalar_factory), assert(o.state)
        local pf, lf, nf, wf = assert(o.profiles), assert(o.power_levels), assert(o.lookup), assert(o.weapons)
        local read, write = o.read or rawget, o.write or rawset
        local owned, failure
        local history_attempted, history_claim
        local function pair(t, name, id) return integer(id) and id > 0 and rawget(t, name) == id and rawget(t, id) == name end
        local function roots(p)
            return rawequal(pf(), p.profiles) and rawequal(lf(), p.levels) and rawequal(nf(), p.lookup) and rawequal(wf(), p.weapons)
                and rawequal(rawget(state, "_cwv_damage_profile_wire_source"), p.map)
                and rawequal(getmetatable(p.profiles), p.metas[1]) and rawequal(getmetatable(p.levels), p.metas[2])
                and rawequal(getmetatable(p.lookup), p.metas[3]) and rawequal(getmetatable(p.weapons), p.metas[4])
                and rawequal(getmetatable(p.map), p.metas[5])
        end
        local function retained(p)
            if not p or not roots(p) or not integer(rawget(state, "_cwv_damage_profile_generation"))
                    or rawget(state, "_cwv_damage_profile_generation") < p.generation
                    or rawget(state, "_cwv_wire_fallback_profile_id") ~= p.fallback then return false end
            if not history_intact(p.history) then return false end
            for _, r in ipairs(p.sources) do
                if not rawequal(rawget(r.root, r.key), r.value) then return false end
                if r.career then
                    if not career_intact(r.career) then return false end
                elseif not intact(r.snapshot) then return false end
            end
            for name, id in next, p.native_pairs do if not pair(p.lookup, name, id) then return false end end
            for _, r in ipairs(p.custom) do
                if not rawequal(rawget(p.profiles, r.name), r.value) or not intact(r.snapshot)
                        or not pair(p.lookup, r.name, r.id) or rawget(p.map, r.name) ~= r.source then return false end
            end
            for _, r in ipairs(p.power) do if not rawequal(rawget(p.levels, r.name), r.value) or not intact(r.snapshot) then return false end end
            if not rawequal(rawget(p.weapons, KEY), p.template) then return false end
            if p.career_template then return career_intact(p.career_template) end
            return intact(p.template_snapshot)
        end
        local function construct()
            local p = { profiles = pf(), levels = lf(), lookup = nf(), weapons = wf(),
                map = rawget(state, "_cwv_damage_profile_wire_source"), sources = {}, custom = {}, power = {}, detached = {}, native_pairs = {} }
            local generation, first = rawget(state, "_cwv_damage_profile_generation"), rawget(state, "_cwv_wire_fallback_profile_id")
            assert(type(p.profiles) == "table" and type(p.levels) == "table" and type(p.lookup) == "table"
                and type(p.weapons) == "table" and type(p.map) == "table" and integer(generation)
                and generation <= 9007199254740981, "Tuskgor roots/generation unavailable")
            p.metas = { getmetatable(p.profiles), getmetatable(p.levels), getmetatable(p.lookup), getmetatable(p.weapons), getmetatable(p.map) }
            p.generation, p.fallback = generation + 9, first
            local map_before = assert(capture(p.map, 2048, 8192))
            if not history_attempted then
                history_attempted = true
                history_claim = history_capture(rawget(p.weapons, DONOR), p.weapons)
            end
            assert(history_claim and history_intact(history_claim), "Tuskgor typed history unavailable")
            p.history = history_claim
            local changes = {}
            local function stage(t, k, v, tag, before) changes[#changes + 1] = { t, k, v, tag, before = before } end
            local function source(root, key, max_nodes, max_cells)
                local value = rawget(root, key); assert(type(value) == "table", "Tuskgor source missing: " .. key)
                local include
                if rawequal(root, p.weapons) and key == DONOR then
                    include = function(t, field) return history_include(p.history, t, field) end
                end
                local snapshot = assert(capture(value, max_nodes, max_cells, include), "Tuskgor source graph bound")
                local career_proof
                if career_capture and rawequal(root, p.weapons) then
                    assert(key == DONOR or key == RECEIVER, "Tuskgor unsupported career source")
                    career_proof = assert(career_capture(value, { role = "source", include = include }),
                        "Tuskgor career source capture refused")
                    assert(career_intact(career_proof), "Tuskgor career source invalid")
                end
                p.sources[#p.sources + 1] = { root = root, key = key, value = value,
                    snapshot = snapshot, career = career_proof }
                return value, snapshot
            end
            local donor, donor_snapshot = source(p.weapons, DONOR, 4096, 32768)
            local receiver, receiver_snapshot = source(p.weapons, RECEIVER, 4096, 32768)
            assert(rawget(p.weapons, KEY) == nil and donor ~= receiver, "Tuskgor foreign template")
            assert(rawget(donor, "state_machine") == "units/beings/player/first_person_base/state_machines/melee/polearm"
                and rawget(donor, "wield_anim") == "to_polearm", "Tuskgor native FP declaration changed")
            local da, ra = rawget(donor, "actions"), rawget(receiver, "actions")
            local dg, rg = plain(da) and rawget(da, "action_one"), plain(ra) and rawget(ra, "action_one")
            assert(plain(dg) and plain(rg) and plain(rawget(rg, "push")), "Tuskgor/Elf action graph missing")
            local radius = rawget(rawget(rg, "push"), "push_radius")
            assert(close(radius, 2.4) and rawget(receiver, "max_fatigue_points") == 6, "Elf native non-attack retention source changed")
            local buffs = rawget(receiver, "buffs")
            assert(plain(buffs) and plain(rawget(buffs, "change_dodge_distance")) and plain(rawget(buffs, "change_dodge_speed"))
                and close(rawget(rawget(buffs, "change_dodge_distance"), "external_optional_multiplier"), 1.15)
                and close(rawget(rawget(buffs, "change_dodge_speed"), "external_optional_multiplier"), 1.15)
                and rawget(receiver, "dodge_count") == 3 and rawget(receiver, "block_angle") == 180
                and rawget(receiver, "outer_block_angle") == 360 and rawget(receiver, "block_fatigue_point_multiplier") == .5
                and rawget(receiver, "outer_block_fatigue_point_multiplier") == 2, "Elf native non-attack stats changed")
            local template = clone(receiver); local actions = rawget(template, "actions")
            assert(disjoint(receiver_snapshot, capture(template, 4096, 32768)) and plain(actions), "Elf clone aliases source")
            local attack = clone(dg)
            assert(disjoint(donor_snapshot, capture(attack, 4096, 32768)), "Tuskgor attack clone aliases donor")
            rawset(actions, "action_one", attack)
            rawset(template, "state_machine", rawget(donor, "state_machine")); rawset(template, "wield_anim", rawget(donor, "wield_anim"))
            local expected = {}; for _, r in ipairs(NODES) do expected[r[1]] = true end
            local count = 0; for k in next, dg do assert(expected[k], "Tuskgor extra attack node"); count = count + 1 end
            assert(count == 12, "Tuskgor incomplete attack graph")
            local dp, dl, detached_lookup, native_by_name, native_snapshots, power_seen, destinations = {}, {}, {}, {}, {}, {}, {}
            for k, v in next, p.lookup do detached_lookup[k] = v end
            local initial_max = #p.lookup
            if first ~= nil then
                local name = rawget(p.lookup, first)
                assert(type(name) == "string" and name:sub(1, 4) ~= "cwv_" and pair(p.lookup, name, first)
                    and type(rawget(p.profiles, name)) == "table", "Tuskgor existing fallback unavailable")
            end
            for _, name in ipairs(SOURCES) do
                local value, snap = source(p.profiles, name, 256, 2048)
                local id = rawget(p.lookup, name); local actual, inserted = register(detached_lookup, name)
                assert(profile_shape(value, p.levels, name) and pair(p.lookup, name, id) and actual == id and not inserted,
                    "Tuskgor native profile/pair shape unavailable: " .. name)
                assert(rawget(p.profiles, PREFIX .. name) == nil and rawget(p.lookup, PREFIX .. name) == nil
                    and rawget(p.map, PREFIX .. name) == nil, "Tuskgor foreign profile destination")
                dp[name] = clone(value); assert(disjoint(snap, capture(dp[name], 256, 2048)))
                p.detached[#p.detached + 1] = assert(capture(dp[name], 256, 2048)); native_by_name[name] = id
                native_snapshots[name], p.native_pairs[name] = snap, id
                for _, field in ipairs(PROFILE_FIELDS) do
                    local ref = rawget(value, field)
                    if type(ref) == "string" and not power_seen[ref] then
                        local original, original_snapshot = source(p.levels, ref, 256, 2048)
                        power_seen[ref] = true; dl[ref] = clone(original)
                        assert(disjoint(original_snapshot, capture(dl[ref], 256, 2048)))
                        p.detached[#p.detached + 1] = assert(capture(dl[ref], 256, 2048))
                    end
                    if type(ref) == "string" and SCALED[field] then
                        assert(rawget(p.levels, PREFIX .. ref) == nil, "Tuskgor foreign power destination"); destinations[PREFIX .. ref] = true
                    end
                end
            end
            local encounters, emitted = 0, {}
            local planner = scalar({ profiles = dp, power_levels = dl,
                record_source = function(name, original)
                    assert(native_by_name[original] and name == PREFIX .. original, "Tuskgor scalar route changed")
                    encounters = encounters + 1; if p.fallback == nil then p.fallback = native_by_name[original] end
                end,
                register = function(name, value)
                    local original = name:sub(#PREFIX + 1)
                    assert(native_by_name[original] and name == PREFIX .. original and not emitted[original])
                    local id, inserted = register(detached_lookup, name); local snapshot = assert(capture(value, 256, 2048))
                    assert(inserted and integer(id) and id > initial_max and disjoint(native_snapshots[original], snapshot))
                    emitted[original] = true; dp[name] = value
                    p.custom[#p.custom + 1] = { name = name, source = original, value = value, snapshot = snapshot, id = id }
                    stage(p.profiles, name, value, "profile:" .. name); stage(p.lookup, id, name, "numeric:" .. name)
                    stage(p.lookup, name, id, "reverse:" .. name); stage(p.map, name, original, "source:" .. name)
                    return true
                end })
            for _, row in ipairs(NODES) do
                local original, action = rawget(dg, row[1]), rawget(attack, row[1])
                assert(plain(original) and plain(action) and rawget(original, "kind") == row[2]
                    and rawget(action, "kind") == row[2], "Tuskgor native action kind changed")
                for _, field in ipairs(HAND_FIELDS) do assert(rawget(original, field) == nil, "Tuskgor unsupported per-hand profile") end
                if row[2] ~= "sweep" then assert(rawget(original, "damage_profile") == nil, "Tuskgor unexpected main profile") end
                if row[2] ~= "push_stagger" then assert(rawget(original, "damage_profile_inner") == nil
                    and rawget(original, "damage_profile_outer") == nil, "Tuskgor unexpected push profile") end
                local speed = rawget(original, "anim_time_scale")
                assert(rawget(action, "anim_time_scale") == speed, "Tuskgor clone scale changed")
                if row[2] == "melee_start" then assert(speed == nil, "Tuskgor native charge scale changed")
                elseif row[2] == "sweep" then assert(close(speed, row[4]), "Tuskgor native sweep scale changed") end
                if row[2] == "melee_start" or row[2] == "sweep" then
                    rawset(action, "anim_time_scale", (speed or 1) * 1.15)
                end
                if row[2] == "sweep" then
                    assert(rawget(original, "damage_profile") == row[3], "Tuskgor native sweep profile changed")
                    rawset(action, "damage_profile", planner.clone_damage_profile(row[3], PREFIX, MODIFIERS))
                elseif row[2] == "push_stagger" then
                    assert(rawget(original, "damage_profile_inner") == row[3] and rawget(original, "damage_profile_outer") == row[5], "Tuskgor push axes changed")
                    rawset(action, "damage_profile_inner", planner.clone_damage_profile(row[3], PREFIX, MODIFIERS))
                    rawset(action, "damage_profile_outer", planner.clone_damage_profile(row[5], PREFIX, MODIFIERS))
                    rawset(action, "push_radius", radius)
                end
            end
            assert(encounters == 9 and #p.custom == 6 and planner.check() == nil, "Tuskgor scalar count/audit failed")
            for name in next, destinations do
                local value = rawget(dl, name); local snapshot = assert(capture(value, 256, 2048))
                p.power[#p.power + 1] = { name = name, value = value, snapshot = snapshot }; stage(p.levels, name, value, "power:" .. name)
            end
            if career_capture then
                -- Only this detached receiver clone is normalized. Initial clone/
                -- attack/profile disjointness was checked before canonical aliasing.
                local token = KEY .. "<-" .. RECEIVER
                local report = prepare_clone(template, receiver, canonical_for(), token)
                assert(type(report) == "table" and rawget(report, "ok") == true,
                    "Tuskgor inherited career preparation refused")
                p.career_template = assert(career_capture(template,
                    { role = "clone", source = receiver, token = token }),
                    "Tuskgor career clone capture refused")
                assert(career_intact(p.career_template), "Tuskgor career clone invalid")
            end
            p.template, p.template_snapshot = template, assert(capture(template, 4096, 32768))
            stage(p.weapons, KEY, template, "template:" .. KEY)
            assert(planner.append_live_audit_changes(changes) == true, "Tuskgor private audit handoff failed")
            stage(state, "_cwv_damage_profile_generation", p.generation, "generation", generation)
            if first == nil then stage(state, "_cwv_wire_fallback_profile_id", p.fallback, "fallback") end
            local function before()
                assert(roots(p) and intact(map_before) and rawget(state, "_cwv_damage_profile_generation") == generation
                    and rawget(state, "_cwv_wire_fallback_profile_id") == first, "Tuskgor root/scalar preimage changed")
                assert(history_intact(p.history), "Tuskgor typed history changed during prepare")
                for _, r in ipairs(p.sources) do assert(rawequal(rawget(r.root, r.key), r.value) and intact(r.snapshot), "Tuskgor source changed during prepare") end
                for name, id in next, p.native_pairs do assert(pair(p.lookup, name, id), "Tuskgor native pair changed during prepare") end
                for _, snapshot in ipairs(p.detached) do assert(intact(snapshot), "Tuskgor detached source changed") end
                assert(intact(p.template_snapshot), "Tuskgor prepared template changed")
            end
            assert(commit(changes, before, function()
                -- Lifetime protocol permission cannot authorize mid-commit drift.
                for _, r in ipairs(p.sources) do
                    assert(rawequal(rawget(r.root, r.key), r.value) and intact(r.snapshot),
                        "Tuskgor source graph changed during commit")
                end
                assert(intact(p.template_snapshot), "Tuskgor prepared template changed during commit")
                assert(rawget(state, "_cwv_damage_profile_generation") == p.generation and retained(p), "Tuskgor publication readback failed")
            end, read, write), "Tuskgor transaction rejected")
            owned, failure = p, nil; return true
        end
        local C = {}
        function C.construct()
            if owned then local ok, value = pcall(retained, owned); return ok and value == true end
            local ok, value = pcall(construct); if ok and value == true then return true end
            failure = tostring(value); return false
        end
        function C.template()
            local ok, ready = pcall(retained, owned); if ok and ready then return KEY, owned.template end
        end
        function C.check()
            local ok, ready = pcall(retained, owned); if not ok or not ready then return failure or "Tuskgor retained construction missing/drifted" end
        end
        return C
    end
end
return M
