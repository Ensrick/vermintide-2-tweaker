-- Required source-qualified Javelin construction harness, not native ABI proof.
-- Engine/package/wire collaborators are explicit test ledgers; complete native
-- Javelin statements/callbacks and the actual complete CWV installers execute.
local M = {}
local REL = "character_weapon_variants/scripts/mods/character_weapon_variants/"
local function raw_read(path)
    local file = assert(io.open(path, "rb"), "required Javelin fixture/source missing: " .. path)
    local source = file:read("*a"); file:close(); return source
end
local function normalize(source) return (source:gsub("\r\n", "\n")) end
local function split(source)
    assert(source:sub(-1) == "\n", "strict patch requires complete newline-terminated source")
    local result = {}; for line in source:gmatch("([^\n]*)\n") do result[#result + 1] = line end
    return result
end
-- Both ordinary suite and the mandatory PS preflight use THIS reconstructor.
-- Numeric hunks consume every expected preimage line; no fuzzy apply/fallback.
function M.reconstruct(current, patch)
    local input, rows = split(normalize(current)), split(normalize(patch))
    assert(rows[1] == "--- a/" .. REL .. "_cwv_javelin_runtime_owner.lua")
    assert(rows[2] == "+++ b/" .. REL .. "_cwv_javelin_runtime_owner.lua")
    local result, cursor, at, hunks = {}, 1, 3, 0
    while at <= #rows do
        local from, count, target, target_count = rows[at]:match("^@@ %-(%d+),(%d+) %+(%d+),(%d+) @@$")
        assert(from, "invalid reverse hunk header")
        from, count, target, target_count = tonumber(from), tonumber(count), tonumber(target), tonumber(target_count)
        assert(from >= cursor and from <= #input + 1, "reverse hunk position invalid")
        while cursor < from do result[#result + 1] = input[cursor]; cursor = cursor + 1 end
        assert(#result + 1 == target, "reverse target position invalid")
        local consumed, produced = 0, 0; at, hunks = at + 1, hunks + 1
        while at <= #rows and rows[at]:sub(1, 2) ~= "@@" do
            local kind, value = rows[at]:sub(1, 1), rows[at]:sub(2)
            assert(kind == " " or kind == "+" or kind == "-", "invalid reverse payload")
            if kind ~= "+" then
                assert(input[cursor] == value, "reverse preimage mismatch at line " .. cursor)
                cursor, consumed = cursor + 1, consumed + 1
            end
            if kind ~= "-" then result[#result + 1] = value; produced = produced + 1 end
            at = at + 1
        end
        assert(consumed == count and produced == target_count, "reverse hunk count mismatch")
    end
    assert(hunks > 0, "empty reverse delta")
    while cursor <= #input do result[#result + 1] = input[cursor]; cursor = cursor + 1 end
    return table.concat(result, "\n") .. "\n"
end
function M.prior_source(root)
    return M.reconstruct(raw_read(root .. "/" .. REL .. "_cwv_javelin_runtime_owner.lua"),
        raw_read(root .. "/qa/lua/fixtures/cwv_javelin_construction_prior.reverse.patch"))
end
if arg and arg[1] == "--export-prior-javelin" then
    assert(type(arg[2]) == "string" and arg[3] == nil, "fixed Javelin exporter arguments required")
    io.write(M.prior_source(arg[2])); return
end
function M.new(H, root, config)
    config = config or {}
    local quiet = setmetatable({ test = function() end, test_if = function() end }, { __index = H })
    local T = dofile(root .. "/qa/lua/tests/test_cwv_old_musket_shot_owner.lua")(quiet, root)
    local graph
    local c = T.installed(function(context)
        if config.get_mod then context.env.get_mod = config.get_mod end
        local original = context.mod.dofile
        context.mod.dofile = function(self, name)
            local value = original(self, name)
            if name:match("/_cwv_profile_graph_transaction$") then graph = value end
            return value
        end
    end)
    local env, om = c.env, c.state
    c.T, c.graph, c.root, c.ledger = T, assert(graph), root, { packages = {}, wire = {}, ordered = {} }
    c.commands = {}
    c.mod.command = function(_, name, description, callback)
        H.equal(c.commands[name], nil, "command registered once")
        c.commands[name] = { description = description, callback = callback }
    end
    local fixture = assert(loadfile(root .. "/qa/lua/fixtures/cwv_javelin_construction_source.lua"))()
    assert(type(fixture.javelin) == "string" and type(fixture.donor_rows) == "string" and type(fixture.resolve) == "string")
    -- Native construction collaborators, not physics/engine implementations.
    env.Projectiles = { javelin = { gravity_settings = "javelin" } }
    env.ProjectileGravitySettings = { javelin = 9.8 }
    env.AttachmentNodeLinking.javelin = {}
    env.math = setmetatable({ easeInCubic = function(v) return v end, ease_out_quad = function(v) return v end }, { __index = math })
    env.fassert = function(ok, message, ...) assert(ok, string.format(message, ...)) end
    local private = setmetatable({ DamageProfileTemplates = {}, PowerLevelTemplates = {} }, { __index = env })
    T.run("DamageProfileTemplates = {\n" .. fixture.donor_rows .. "\n}\n", private, "native6.13-four-verbatim-woods-donors")
    T.run(fixture.resolve, private, "native6.13-complete-profile-resolution-loop")
    c.names = { "medium_javelin_smiter_stab", "medium_javelin_smiter_stab_bleed", "heavy_javelin_smiter_stab_bleed", "thrown_javelin" }
    for _, name in ipairs(c.names) do
        env.DamageProfileTemplates[name] = assert(private.DamageProfileTemplates[name])
        local id = #c.lookup + 1; c.lookup[id], c.lookup[name] = name, id
    end
    env.PowerLevelTemplates = {}
    local native = T.run(fixture.javelin, env, "tracked-native6.13-complete-Javelin")
    env.Weapons.javelin_template = assert(native.javelin_template)
    env.Weapons.javelin_template_vs = assert(native.javelin_template_vs)
    -- Model the pre-mod native weapons.lua:282-323 identity cells explicitly.
    -- The complete engine global finalizer is NOT executed/claimed by this test.
    for _, name in ipairs({ "javelin_template", "javelin_template_vs" }) do
        local template = env.Weapons[name]; template.name = name
        for group_name, group in pairs(template.actions) do
            if type(group) == "table" then for action_name, action in pairs(group) do
                if type(action) == "table" then action.lookup_data = { item_template_name = name, action_name = group_name, sub_action_name = action_name } end
            end end
        end
    end
    om.combat_style_policy = {}
    local init_start = assert(c.entry:find("local _core_template_construction = mod:dofile(", 1, true))
    local init_end = assert(c.entry:find("\n_core_template_construction = mod:dofile(", init_start, true))
    local initialize = T.run("return function(mod, _cwv_profile_graph)\n" .. c.entry:sub(init_start, init_end - 1)
        .. "\nreturn _core_template_construction end", env, "actual-entry-history-binding")
    local history_binding = initialize(c.mod, graph)
    local core = c.load("_cwv_core_templates")(c.mod, { om = om, Weapons = env.Weapons, history_producer_binding = history_binding,
        DamageProfileTemplates = env.DamageProfileTemplates, PowerLevelTemplates = env.PowerLevelTemplates,
        NetworkLookup = env.NetworkLookup, ItemMasterList = env.ItemMasterList, AttachmentNodeLinking = env.AttachmentNodeLinking,
        Projectiles = env.Projectiles, ActionTemplates = env.ActionTemplates, printf = env.printf })
    H.equal(core.history_producer_binding, history_binding); c.history_binding = history_binding
    c.core = core
    env.ProjectileUnits, env.Pickups, env.AllPickups = {}, { ammo = {}, grenades = {} }, {}
    env.WeaponSkins = { skins = {} }
    for _, name in ipairs({ "projectile_units", "husks", "pickup_names" }) do env.NetworkLookup[name] = {} end
    env.Managers = { package = { load = function(_, ...)
        c.ledger.packages[#c.ledger.packages + 1] = { ... }; c.ledger.ordered[#c.ledger.ordered + 1] = "package"
    end } }
    om.exact_wire_runtime = { install_thrown = function(_, state, globals, spec)
        H.equal(state, om); H.equal(globals, env); H.truthy(spec)
        c.ledger.wire[#c.ledger.wire + 1] = "exact"; c.ledger.ordered[#c.ledger.ordered + 1] = "wire"
    end }
    om.javelin_gate = { fence_pickup = function(key) c.ledger.fenced_pickup = key end, install = function(options)
        H.equal(options.om, om); H.equal(options.globals, env)
        c.ledger.wire[#c.ledger.wire + 1] = "gate"
    end }
    local scalar_factory = core.detached_scalar_factory
    local owner_module = c.load("_cwv_javelin_construction_owner")
    local factory
    c.options, c.owner = nil, nil
    local wrapped = function(options)
        c.options = options
        if config.options then config.options(options, c) end
        c.owner = factory(options)
        if config.owner then config.owner(c.owner, c) end
        return c.owner
    end
    local original_load = c.mod.dofile
    c.mod.dofile = function(self, name)
        if name:match("/_cwv_javelin_construction_owner$") then
            return { bind = function(helper, mechanics, detached, envelope, history)
                factory = owner_module.bind(helper, mechanics, detached, envelope, history)
                H.equal(helper, c.capsule.network_lookup); H.equal(mechanics, graph); H.equal(detached, scalar_factory); H.equal(envelope, c.career_envelope)
                return wrapped
            end }
        end
        return original_load(self, name)
    end
    c.events = {}
    local record = om._record_cwv_dp_source
    om._record_cwv_dp_source = function(name, source)
        c.events[#c.events + 1] = { name, source }; return record(name, source)
    end
    function c.install()
        if config.prior then
            c.runtime = T.run(M.prior_source(root), env, "exact-reconstructed-prior-complete-Javelin-installer")(c.mod,
                { om = om, dbg = function() end, clone_damage_profile = core.clone_damage_profile })
        else
            local entry = c.entry
            local a = assert(entry:find('local _javelin_factory = mod:dofile(', 1, true))
            local b = assert(entry:find("\nlocal _always_false = _javelin_runtime.always_false", a, true))
            local bind = T.run("return function(mod, _om, _dbg, _variant_install, _core_template_construction, _cwv_profile_graph, _clone_damage_profile, _cwv_career_envelope)\n"
                .. entry:sub(a, b - 1) .. "\nreturn _javelin_runtime end", env, "actual-entry-Javelin-private-wiring")
            c.runtime = bind(c.mod, om, function() end, c.capsule, core, graph, core.clone_damage_profile, c.career_envelope)
        end
        c.template = env.Weapons.tuskgor_javelin_template
        return c
    end
    function c.audit()
        for index = 1, 20 do
            local name, value = debug.getupvalue(om._cwv_profile_multiplier_check, index)
            if name == "multiplier_audit" then return value end
            if name == nil then break end
        end
        error("actual core audit ledger not found")
    end
    function c.items()
        om.greataxe, om.dawi_maces = c.load("_cwv_greataxe"), c.load("_cwv_dawi_maces")
        om.crowbill_family, om.crowbill_hammer_mode = c.load("_cwv_crowbill_family"), c.load("_cwv_crowbill_hammer_mode")
        om.crowbill_runtime = c.load("_cwv_crowbill_runtime")
        local catalog = c.load("_cwv_variant_catalog")({ om = om }).definitions
        local defs = {}; for _, def in ipairs(catalog) do
            if def.item_key == "cwv_es_javelin" or def.item_key == "cwv_wh_javelin" or def.item_key == "cwv_es_musket_old" then defs[#defs + 1] = def end
        end
        H.equal(#defs, 3)
        env.ItemMasterList.we_javelin = { name = "we_javelin", item_type = "we_javelin", template = "javelin_template", slot_type = "ranged", can_wield = {} }
        local source = T.read(root .. "/" .. REL .. "_cwv_item_registration_owner.lua")
        local a = assert(source:find("local function install(mod, ctx)", 1, true))
        local b = assert(source:find("local function _auto_register_all()", a, true))
        local export = assert(source:find("_om.item_registration = {", b, true))
        local actual = T.run(source:sub(a, b - 1) .. source:sub(export), env, "actual-registration-prefix-export-no-goto-rewrite")
        local loader = c.mod.dofile
        c.mod.dofile = function(self, name) if name:match("/_cwv_item_registration_owner$") then return actual end; return loader(self, name) end
        c.mod._cwv_acquisition = c.load("_cwv_acquisition")
        local entry, checks = c.entry, {}
        a = assert(entry:find('_variant_install =\n\tmod:dofile("scripts/mods/character_weapon_variants/_cwv_variant_bootstrap_owner")', 1, true))
        b = assert(entry:find("\n-- Skin/illusion registrars", a, true)); local bootstrap = entry:sub(a, b - 1)
        a = assert(entry:find("_variant_install = _variant_install.after_skins(_custom_skin_keys, _rt_register)", b, true))
        b = assert(entry:find("\n", a, true)); local phases = entry:sub(a, b - 1)
        a = assert(entry:find('_variant_install.install_items(mod:dofile("scripts/mods/character_weapon_variants/_cwv_item_registration_owner")', b, true))
        b = assert(entry:find("\n})", a, true)) + 3
        local bind = T.run("return function(mod, _om, _variant_definitions, _variant_install, _javelin_runtime, _rt_register, _core_template_construction)\n"
            .. "local _custom_skin_keys, _dbg, _dbg_alert = {}, function() end, function() end\n"
            .. bootstrap .. "\n" .. phases .. "\nreturn function()\n" .. entry:sub(a, b) .. "\nend end", env, "actual-entry-private-Javelin-admission")
        local install = bind(c.mod, om, defs, c.capsule, c.runtime, function(name, fn) checks[name] = fn end, c.core)
        if config.after_bind then config.after_bind(c) end
        install()
        return defs, om.item_registration.build_entry, checks
    end
    if config.before then config.before(c) end
    c.before = { generation = om._cwv_damage_profile_generation, fallback = om._cwv_wire_fallback_profile_id,
        profiles = T.shape(env.DamageProfileTemplates), lookup = T.shape(c.lookup),
        map = T.shape(om._cwv_damage_profile_wire_source), levels = T.shape(env.PowerLevelTemplates), state = T.shape(om) }
    return c
end
return M
