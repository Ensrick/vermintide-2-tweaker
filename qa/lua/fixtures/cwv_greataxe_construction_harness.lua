-- Required closed Greataxe constructor/prior oracle; no outside source fallback.
local M = {}
local REL = "character_weapon_variants/scripts/mods/character_weapon_variants/"
local function read(path)
    local file = assert(io.open(path, "rb"), "required Greataxe input missing: " .. path)
    local source = file:read("*a"); file:close(); return source
end
function M.prior_source(root, reader)
    reader = reader or read
    local Short = assert(loadfile(root .. "/qa/lua/fixtures/cwv_shortsword_construction_harness.lua"))()
    return Short.reconstruct(reader(root .. "/" .. REL .. "_cwv_core_templates.lua"),
        reader(root .. "/qa/lua/fixtures/cwv_greataxe_producer_prior.reverse.patch"))
end
if arg and arg[1] == "--export-prior-greataxe-core" then
    assert(type(arg[2]) == "string" and arg[3] == nil, "fixed Greataxe exporter arguments required")
    io.write(M.prior_source(arg[2])); return
end
function M.new(H, root, config)
    config = config or {}
    local Short = assert(loadfile(root .. "/qa/lua/fixtures/cwv_shortsword_construction_harness.lua"))()
    local native = assert(loadfile(root .. "/qa/lua/fixtures/cwv_greataxe_construction_source.lua"))()
    for _, key in ipairs({ "axe", "mass", "item" }) do assert(type(native[key]) == "string", "required Greataxe native field missing " .. key) end
    local owner, options, c
    c = Short.new(H, root, { get_mod = config.get_mod, before_core = function(context)
        c = context
        local env, T = c.env, c.T
        c.state.greataxe = c.load("_cwv_greataxe")
        env.AttachmentNodeLinking.two_handed_melee_weapon = {}
        T.run(native.mass, env, "exact-native-Greataxe-LINESMAN")
        env.Weapons.two_handed_axes_template_1 = assert(T.run(native.axe, env,
            "complete-native-Greataxe").two_handed_axes_template_1)
        T.run(native.item, env, "exact-native-dr-2h-axe-master")
        c.greataxe_source = env.Weapons.two_handed_axes_template_1
        c.greataxe_loads = {}
        local original = c.mod.dofile
        c.mod.dofile = function(self, name)
            local key = assert(name:match("/([^/]+)$"))
            c.greataxe_loads[key] = (c.greataxe_loads[key] or 0) + 1
            if config.prior and key == "_cwv_core_templates" then return T.run(M.prior_source(root), env, "exact-complete-approved-Elven-core") end
            local value = original(self, name)
            if key == "_cwv_greataxe_construction_owner" then
                if config.disconnected then return { bind = function() return false end } end
                return { bind = function(graph, envelope, crit)
                    H.truthy(rawequal(graph, c.graph)); H.truthy(rawequal(envelope, c.career_envelope))
                    local mechanics = config.mechanics and config.mechanics(graph, c) or graph
                    H.equal(type(crit), "table", "actual private crit dependency supplied")
                    local factory = value.bind(mechanics, envelope, crit)
                    return function(input)
                        options = input
                        if config.options then config.options(input, c) end
                        owner = factory(input)
                        local construct = owner.construct
                        owner.construct = function(prepare)
                            c.greataxe_before = M.snapshot(c)
                            local ready = construct(function(template)
                                local result = prepare(template)
                                if config.after_prepare then config.after_prepare(c, template) end
                                return result
                            end)
                            c.greataxe_immediate = M.snapshot(c)
                            c.greataxe_unchanged = {}
                            for name, proof in next, c.greataxe_before.proofs do c.greataxe_unchanged[name] = graph.intact(proof) end
                            c.greataxe_constructed = ready
                            return ready
                        end
                        return owner
                    end
                end }
            end
            return value
        end
        if config.before then config.before(c) end
    end })
    c.greataxe_owner, c.greataxe_options = owner, options
    c.greataxe_template = rawget(c.env.Weapons, "cwv_greataxe_template")
    local build, definition
    function c.greataxe_items()
        if not build then
            local _, _, actual, _, checks = c.T.private_items(c)
            build, c.greataxe_checks = actual, checks
            for _, row in ipairs(c.load("_cwv_variant_catalog")({ om = c.state }).definitions) do
                if row.item_key == "cwv_es_greataxe" then definition = row end
            end
            assert(definition, "actual Greataxe definition missing")
            if config.after_item_bind then config.after_item_bind(c) end
        end
        local item = build(definition)
        local seed, id, why = c.mod._cwv_acquisition.build_seed(definition, build,
            function(value) return c.env.table.clone(value, true) end, function() return false end)
        return definition, item, seed, id, why, build
    end
    return c
end
function M.snapshot(c)
    local roots = { profiles = c.env.DamageProfileTemplates, levels = c.env.PowerLevelTemplates,
        lookup = c.lookup, weapons = c.env.Weapons, map = c.state._cwv_damage_profile_wire_source,
        audit = c.audit and c.audit() }
    if not roots.audit then
        for index = 1, 30 do local name, value = debug.getupvalue(c.state._cwv_profile_multiplier_check, index)
            if name == "multiplier_audit" then roots.audit = value; break end
            if not name then break end
        end
    end
    assert(roots.audit, "actual core audit closure required")
    local result = { roots = roots, proofs = {}, generation = rawget(c.state, "_cwv_damage_profile_generation"),
        first = rawget(c.state, "_cwv_wire_fallback_profile_id") }
    for name, value in next, roots do result.proofs[name] = assert(c.graph.capture(value, 8192, 65536)) end
    return result
end
function M.no_profile_mutations(H, c)
    for _, name in ipairs({ "profiles", "levels", "lookup", "map", "audit" }) do
        H.truthy(c.greataxe_unchanged[name], "Greataxe must not write " .. name)
    end
    H.equal(c.greataxe_immediate.generation, c.greataxe_before.generation)
    H.equal(c.greataxe_immediate.first, c.greataxe_before.first)
end
return M
