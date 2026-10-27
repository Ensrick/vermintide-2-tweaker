-- Required bounded Elven Shield native/prior-core oracle; no external fallback.
local M = {}
local REL = "character_weapon_variants/scripts/mods/character_weapon_variants/"
local function read(path)
    local file = assert(io.open(path, "rb"), "required Elven shield fixture missing: " .. path)
    local source = file:read("*a"); file:close(); return source
end
local function normalize(source) return (source:gsub("\r\n", "\n")) end
function M.prior_source(root, reader)
    reader = reader or read
    local Short = assert(loadfile(root .. "/qa/lua/fixtures/cwv_shortsword_construction_harness.lua"))()
    return Short.reconstruct(reader(root .. "/" .. REL .. "_cwv_core_templates.lua"),
        reader(root .. "/qa/lua/fixtures/cwv_elven_shield_greataxe_producer_prior.reverse.patch"))
end
if arg and arg[1] == "--export-prior-elven-shield-core" then
    assert(type(arg[2]) == "string" and arg[3] == nil, "fixed prior Elven shield exporter arguments required")
    io.write(M.prior_source(arg[2])); return
end
local function upvalue(fn, key)
    for index = 1, 30 do local name, value = debug.getupvalue(fn, index)
        if name == key then return value end; if not name then break end end
    error("required private Elven shield upvalue missing " .. key)
end
function M.new(H, root, config)
    config = config or {}
    local Short = assert(loadfile(root .. "/qa/lua/fixtures/cwv_shortsword_construction_harness.lua"))()
    local native = assert(loadfile(root .. "/qa/lua/fixtures/cwv_elven_shield_construction_source.lua"))()
    for _, key in ipairs({ "weapon", "profiles", "power", "resolve", "item" }) do
        assert(type(native[key]) == "string", "required native Elven shield closure missing " .. key)
    end
    local owner, options, c, captured_graph
    c = Short.new(H, root, { get_mod = config.get_mod, before = function(context)
        c = context
        local env, T = c.env, c.T
        env.AttachmentNodeLinking.shield = {}
        local selected = setmetatable({ PowerLevelTemplates = {}, fassert = function(ok, message, ...)
            assert(ok, string.format(message, ...)) end }, { __index = env })
        T.run(native.power, selected, "required-native-Elven-shield-PowerLevel-fields")
        for name, row in next, selected.PowerLevelTemplates do
            if rawget(env.PowerLevelTemplates, name) ~= nil then H.deep_equal(env.PowerLevelTemplates[name], row)
            else env.PowerLevelTemplates[name] = row end
        end
        selected.PowerLevelTemplates = env.PowerLevelTemplates
        T.run(native.profiles, selected, "required-native-Elven-shield-profile-builders")
        T.run(native.resolve, selected, "complete-native-Elven-shield-profile-resolver")
        local keys = {}; for name in next, selected.DamageProfileTemplates do keys[#keys + 1] = name end; table.sort(keys)
        for _, name in ipairs(keys) do
            assert(rawget(env.DamageProfileTemplates, name) == nil, "selected native donor collision " .. name)
            env.DamageProfileTemplates[name] = selected.DamageProfileTemplates[name]
            local id = #c.lookup + 1; c.lookup[id], c.lookup[name] = name, id
        end
        env.Weapons.one_handed_sword_shield_template_1 = assert(T.run(native.weapon, env,
            "complete-required-native-SwordShield").one_handed_sword_shield_template_1)
        T.run(native.item, env, "complete-required-native-es-sword-shield-item")
        c.ess_source = env.Weapons.one_handed_sword_shield_template_1
        c.ess_tags, c.ess_loads = {}, {}
        local original_load = c.mod.dofile
        c.mod.dofile = function(self, name)
            local key = assert(name:match("/([^/]+)$")); c.ess_loads[key] = (c.ess_loads[key] or 0) + 1
            if config.prior and key == "_cwv_core_templates" then
                return T.run(M.prior_source(root), env, "exact-complete-prior-R3-core")
            end
            local value = original_load(self, name)
            if key == "_cwv_elven_shield_construction_owner" then
                if config.disconnected then return { bind = function() return false end } end
                return { bind = function(helper, graph, envelope, history)
                    H.equal(rawequal(helper, c.helper), true); H.equal(rawequal(graph, c.graph), true)
                    c.ess_envelope = envelope
                    c.ess_history = history
                    captured_graph = graph
                    local mechanics = config.mechanics and config.mechanics(graph, c) or graph
                    local factory = value.bind(helper, mechanics, envelope, history)
                    return function(input)
                        options = input
                        if config.options then config.options(input, c) end
                        owner = factory(input)
                        local construct = owner.construct
                        owner.construct = function(prepare)
                            c.ess_before = M.snapshot(c)
                            local ok = construct(function(template, scalar)
                                local ready = prepare(template, scalar)
                                if config.after_prepare then config.after_prepare(c, template, scalar) end
                                return ready
                            end)
                            c.ess_immediate = M.snapshot(c)
                            c.ess_raw_unchanged = {}
                            for key, proof in next, c.ess_before.proofs do
                                c.ess_raw_unchanged[key] = graph.intact(proof)
                            end
                            c.ess_constructed = ok
                            return ok
                        end
                        return owner
                    end
                end }
            end
            return value
        end
        if config.before then config.before(c) end
    end })
    c.ess_owner, c.ess_options, c.ess_graph = owner, options, captured_graph
    c.ess_template = rawget(c.env.Weapons, "elven_sword_shield_template")
    local build, defs
    function c.ess_items()
        if not build then
            local _, _, actual, _, checks = c.T.private_items(c)
            build, c.ess_checks = actual, checks
            defs = c.load("_cwv_variant_catalog")({ om = c.state }).definitions
        end
        local results = {}
        for _, def in ipairs(defs) do
            if def.item_key == "cwv_we_sword_shield" or def.item_key == "cwv_we_sword_shield_veteran" then
                local item = build(def)
                local seed, id, why = c.mod._cwv_acquisition.build_seed(def, build,
                    function(value) return c.env.table.clone(value, true) end, function() return false end)
                results[#results + 1] = { def = def, item = item, seed = seed, id = id, why = why }
            end
        end
        H.equal(#results, 2); return results, build
    end
    function c.ess_proof() return owner and upvalue(owner.check, "owned") end
    return c
end
function M.snapshot(c)
    local roots = { profiles = c.env.DamageProfileTemplates, levels = c.env.PowerLevelTemplates,
        lookup = c.lookup, weapons = c.env.Weapons, map = c.state._cwv_damage_profile_wire_source,
        audit = upvalue(c.state._cwv_profile_multiplier_check, "multiplier_audit") }
    local result = { roots = roots, proofs = {}, generation = rawget(c.state, "_cwv_damage_profile_generation"),
        first = rawget(c.state, "_cwv_wire_fallback_profile_id") }
    for key, value in next, roots do result.proofs[key] = assert(c.graph.capture(value, 8192, 65536)) end
    return result
end
function M.unchanged(H, c, before)
    local after = M.snapshot(c)
    for key, value in next, before.roots do
        H.equal(rawequal(after.roots[key], value), true, "same raw root " .. key)
        H.truthy(c.graph.intact(before.proofs[key]), "complete raw graph unchanged " .. key)
    end
    H.equal(after.generation, before.generation); H.equal(after.first, before.first)
end
M.upvalue, M.normalize = upvalue, normalize
return M
