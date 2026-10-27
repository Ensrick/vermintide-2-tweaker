-- Required bounded Shortsword native/prior-core oracle; no external fallback.
local M = {}
local REL = "character_weapon_variants/scripts/mods/character_weapon_variants/"
local function raw_read(path)
    local file = assert(io.open(path, "rb"), "required Shortsword input missing: " .. path)
    local text = file:read("*a"); file:close(); return text
end
local function normalize(text)
    text = text:gsub("\r\n", "\n")
    return text:sub(1, 3) == string.char(239, 187, 191) and text:sub(4) or text
end
local function split(text)
    assert(text:sub(-1) == "\n", "required complete reverse-source newline")
    local rows = {}; for line in text:gmatch("([^\n]*)\n") do rows[#rows + 1] = line end; return rows
end
-- Fixed prior-core boundary; this exact function is also the mandatory exporter.
-- Equal context is encoded as consumed -value/+value pairs, not whitespace-only
-- lines in a tracked patch. Every hunk count/source position remains asserted.
function M.reconstruct(current, patch)
    local source, rows = split(normalize(current)), split(normalize(patch))
    assert(rows[1] == "--- a/" .. REL .. "_cwv_core_templates.lua")
    assert(rows[2] == "+++ b/" .. REL .. "_cwv_core_templates.lua")
    local result, cursor, at, hunks = {}, 1, 3, 0
    while at <= #rows do
        local from, count, target, produced = rows[at]:match("^@@ %-(%d+),(%d+) %+(%d+),(%d+) @@$")
        assert(from, "invalid Shortsword reverse hunk header")
        from, count, target, produced = tonumber(from), tonumber(count), tonumber(target), tonumber(produced)
        assert(from >= cursor and from <= #source + 1, "reverse source position invalid")
        while cursor < from do result[#result + 1] = source[cursor]; cursor = cursor + 1 end
        assert(#result + 1 == target, "reverse target position invalid")
        local consumed, added = 0, 0; at, hunks = at + 1, hunks + 1
        while at <= #rows and rows[at]:sub(1, 2) ~= "@@" do
            local kind, value = rows[at]:sub(1, 1), rows[at]:sub(2)
            assert(kind == "-" or kind == "+", "reverse context must be explicit consumed pairs")
            if kind == "-" then assert(source[cursor] == value, "reverse preimage mismatch at " .. cursor); cursor, consumed = cursor + 1, consumed + 1 end
            if kind == "+" then result[#result + 1] = value; added = added + 1 end
            at = at + 1
        end
        assert(consumed == count and added == produced, "reverse hunk count mismatch")
    end
    assert(hunks > 0, "empty Shortsword reverse delta")
    while cursor <= #source do result[#result + 1] = source[cursor]; cursor = cursor + 1 end
    return table.concat(result, "\n") .. "\n"
end
function M.prior_source(root, reader)
    reader = reader or raw_read
    return M.reconstruct(reader(root .. "/" .. REL .. "_cwv_core_templates.lua"),
        reader(root .. "/qa/lua/fixtures/cwv_shortsword_construction_prior.reverse.patch"))
end
if arg and arg[1] == "--export-prior-shortsword-core" then
    assert(type(arg[2]) == "string" and arg[3] == nil, "fixed prior-core exporter arguments required")
    io.write(M.prior_source(arg[2])); return
end
function M.new(H, root, config)
    config = config or {}
    local read = config.read_source or raw_read
    local function text(path) return normalize(read(path)) end
    -- The fixed read provider is an outside-overlay seam only. Normal/CI reads
    -- required tracked files; no ignored directory, native checkout or SKIP.
    local host = setmetatable({}, { __index = _G }); host._G = host
    host.io = setmetatable({ open = function(path, mode)
        if mode == "rb" then
            local ok, data = pcall(read, path)
            if not ok then return nil, data end
            return { read = function(_, format) assert(format == "*a"); return data end, close = function() end }
        end
        return io.open(path, mode)
    end }, { __index = io })
    host.loadfile = function(path)
        local chunk, failure = loadstring(text(path), "@" .. path)
        if chunk then setfenv(chunk, host) end
        return chunk, failure
    end
    host.dofile = function(path) return assert(host.loadfile(path))() end
    local quiet = setmetatable({ test = function() end, test_if = function() end }, { __index = H })
    local T = host.dofile(root .. "/qa/lua/tests/test_cwv_old_musket_shot_owner.lua")(quiet, root)
    local native = host.dofile(root .. "/qa/lua/fixtures/cwv_shortsword_construction_source.lua")
    for _, name in ipairs({ "dagger", "power", "profiles", "resolve", "item" }) do assert(type(native[name]) == "string", "required native closure missing " .. name) end
    local c, captured_helper, graph, owner, options, before, events
    local loads, source_events, core_order = {}, {}, {}
    c = T.installed(function(context)
        c = context
        c.T = T
        if config.get_mod then c.env.get_mod = config.get_mod end
        local env, om = c.env, c.state
        env.AttachmentNodeLinking.one_handed_melee_weapon = { right = {} }
        env.fassert = function(ok, message, ...) assert(ok, string.format(message, ...)) end
        T.run(native.power, env, "tracked-native-PowerLevel-fields")
        -- T.installed's other native donors are retained in its live registry.
        -- Merge the five source-qualified rows after isolated native resolution.
        local portable = setmetatable({ PowerLevelTemplates = env.PowerLevelTemplates, fassert = env.fassert }, { __index = env })
        T.run(native.profiles, portable, "private-five-native-donors")
        T.run(native.resolve, portable, "complete-native-resolution")
        local resolved = portable.DamageProfileTemplates
        -- Retain the original context's profile root and add only five rows.
        for _, name in ipairs({ "dagger_1h_light_linesman", "dagger_1h_light_smiter_stab", "light_fencer_stab", "medium_slashing_linesman", "medium_slashing_smiter_stab" }) do
            assert(rawget(env.DamageProfileTemplates, name) == nil)
            env.DamageProfileTemplates[name] = assert(resolved[name])
            local id = #c.lookup + 1; c.lookup[id], c.lookup[name] = name, id
        end
        local weapons = T.run(native.dagger, env, "complete-tracked-native-dagger")
        env.Weapons.one_handed_daggers_template_1 = assert(weapons.one_handed_daggers_template_1)
        T.run(native.item, env, "native-bw-dagger-master-assignment")
        om.combat_style_policy = {}
        local original_record = om._record_cwv_dp_source
        om._record_cwv_dp_source = function(name, donor)
            source_events[#source_events + 1] = { name, donor }
            return original_record(name, donor)
        end
        local original_load = c.mod.dofile
        c.mod.dofile = function(self, name)
            local key = assert(name:match("/([^/]+)$")); loads[#loads + 1] = key
            local value
            if config.prior and key == "_cwv_core_templates" then value = T.run(M.prior_source(root, read), env, "exact-reconstructed-prior-core")
            else value = original_load(self, name) end
            if key == "_cwv_shortsword_construction_owner" then
                return { bind = function(helper, mechanics, envelope)
                    H.equal(helper, captured_helper); H.equal(mechanics, graph)
                    H.equal(envelope, c.career_envelope)
                    local factory = value.bind(helper, mechanics, envelope)
                    return function(input)
                        options = input
                        if config.options then config.options(input, c) end
                        owner = factory(input)
                        if config.owner then config.owner(owner, c) end
                        return owner
                    end
                end }
            end
            return value
        end
        c.before_musket = function(helper, mechanics, envelope)
            captured_helper, graph = helper, mechanics
            c.graph, c.helper, c.career_envelope = graph, helper, envelope
            if config.before then config.before(c) end
            local function shape(value) return graph.capture(value, 8192, 65536) end
            before = { profiles = T.shape(env.DamageProfileTemplates), powers = T.shape(env.PowerLevelTemplates), lookup = T.shape(c.lookup),
                map = T.shape(om._cwv_damage_profile_wire_source), generation = om._cwv_damage_profile_generation,
                first = rawget(om, "_cwv_wire_fallback_profile_id"), source = shape(env.Weapons.one_handed_daggers_template_1) }
            if config.before_core then config.before_core(c) end
            local entry = text(root .. "/" .. REL .. "character_weapon_variants.lua")
            local a = assert(entry:find("local _core_template_construction = mod:dofile(", 1, true))
            local b = assert(entry:find("\nlocal _clone_damage_profile = _core_template_construction.clone_damage_profile", a, true))
            local bind = T.run("return function(mod, _om, _cwv_network_lookup, _cwv_profile_graph, _cwv_career_envelope)\n"
                .. entry:sub(a, b - 1) .. "\nreturn _core_template_construction end", env, "actual-entry-core-before-Musket")
            core_order[#core_order + 1] = "core"
            c.core = bind(c.mod, om, helper, mechanics, envelope)
            c.template = rawget(env.Weapons, "shortsword_template")
            c.construction_source_events = {}
            for i, row in ipairs(source_events) do c.construction_source_events[i] = row end
            if config.after_core then config.after_core(c) end
            core_order[#core_order + 1] = "musket"
        end
    end)
    c.T, c.graph, c.helper, c.owner, c.options = T, graph, captured_helper, owner, options
    c.before, c.loads_order, c.source_events, c.core_order = before, loads, source_events, core_order
    function c.audit()
        for index = 1, 20 do
            local name, value = debug.getupvalue(c.state._cwv_profile_multiplier_check, index)
            if name == "multiplier_audit" then return value end
            if not name then break end
        end
        error("actual core audit ledger missing")
    end
    function c.proof()
        if not c.owner then return nil end
        for index = 1, 20 do
            local name, value = debug.getupvalue(c.owner.check, index)
            if name == "owned" then return value end
            if not name then break end
        end
    end
    local definition, build
    function c.items()
        if not build then
            local _, _, actual, _, checks = T.private_items(c)
            build, c.checks = actual, checks
            local definitions = c.load("_cwv_variant_catalog")({ om = c.state }).definitions
            for _, row in ipairs(definitions) do if row.item_key == "cwv_es_shortsword" then definition = row end end
            assert(definition, "real Shortsword catalog row missing")
            if config.after_item_bind then config.after_item_bind(c) end
        end
        local entry = build(definition, nil)
        local seed, id, why = c.mod._cwv_acquisition.build_seed(definition, build,
            function(value) return c.env.table.clone(value, true) end, function() return false end)
        return definition, entry, seed, id, why, build
    end
    return c
end
return M
