-- #428 follow-on: actual complete installer/constructor, not synthetic descriptors.
return function(H, root)
    local quiet = setmetatable({ test = function() end, test_if = function() end }, { __index = H })
    local T = dofile(root .. "/qa/lua/tests/test_cwv_old_musket_shot_owner.lua")(quiet, root)
    local Native = dofile(root .. "/qa/lua/fixtures/cwv_old_musket_native_melee.lua")
    local prefix = root .. "/character_weapon_variants/scripts/mods/character_weapon_variants/"
    local NAMES, KEY = Native.names, "old_musket_template_melee"
    local P = "cwv_old_musket_melee_"
    H.test("#428 bayonet manifest private wiring source ownership and registration position", function()
        local entry, runtime = T.read(prefix .. "character_weapon_variants.lua"), T.read(prefix .. "_cwv_musket_runtime.lua")
        local module = T.read(prefix .. "_cwv_old_musket_melee_owner.lua")
        local module_code = module:gsub("%-%-[^\n]*", "")
        local function count(s, needle)
            local n, at = 0, 1
            while true do local pos = s:find(needle, at, true); if not pos then return n end; n, at = n + 1, pos + #needle end
        end
        for _, name in ipairs({ "_cwv_old_musket_shot_owner", "_cwv_old_musket_melee_owner", "_cwv_profile_graph_transaction", "_cwv_guard428_old_musket_sweep", "_lib_network_lookup" }) do
            local token = 'mod:dofile("scripts/mods/character_weapon_variants/' .. name .. '")'
            H.equal(count(entry, token), 1); H.equal(count(runtime, token), 0); H.equal(count(module_code, token), 0)
        end
        H.equal(count(module_code, "mod:hook"), 0); H.equal(count(module_code, "mod:dofile"), 0)
        H.truthy(module:find("-- Owned by: character_weapon_variants.lua entry point.", 1, true))
        H.truthy(module:find("-- Consumed via:", 1, true))
        local shot = assert(entry:find('_variant_install = _variant_install.bind(_cwv_network_lookup)', 1, true))
        local melee = assert(entry:find('_variant_install.melee_factory = mod:dofile("scripts/mods/character_weapon_variants/_cwv_old_musket_melee_owner")\n_variant_install.melee_factory = _variant_install.melee_factory.bind(_variant_install.network_lookup,\n\t_cwv_profile_graph, mod:dofile("scripts/mods/character_weapon_variants/_cwv_guard428_old_musket_sweep"))', 1, true))
        local install = assert(entry:find('_variant_install = mod:dofile("scripts/mods/character_weapon_variants/_cwv_musket_runtime")', 1, true))
        local router = assert(entry:find('_variant_install.install_template_router()', 1, true))
        local equip = assert(entry:find('mod:dofile("scripts/mods/character_weapon_variants/_cwv_musket_equip_surface")', 1, true))
        local bootstrap = assert(entry:find('mod:dofile("scripts/mods/character_weapon_variants/_cwv_variant_bootstrap_owner")', 1, true))
        H.truthy(shot < melee and melee < install and install < router and router < equip and equip < bootstrap)
        H.equal(count(entry, 'mod:hook("BackendUtils", "get_item_template"'), 0)
        H.equal(count(runtime, 'mod:hook("BackendUtils", "get_item_template"'), 1)
        H.equal(count(runtime, "_variant_install"), 0, "no late phase-variable authority lookup")
        local body = assert(runtime:find('local function install_template_router()', 1, true))
        local native = assert(runtime:find('local template = func(item_data, backend_id)', body, true))
        local styles = assert(runtime:find('_om.combat_styles:resolve_template', native, true))
        local crowbill = assert(runtime:find('_om.crowbill_runtime.resolve_template(item_data, backend_id)', styles, true))
        H.truthy(body < native and native < styles and styles < crowbill)
        local count_lines = 0
        for line in entry:gmatch("[^\n]+") do if line:match("%S") then count_lines = count_lines + 1 end end
        H.truthy(count_lines <= 1490, "actual CWV ratchet, not generic1500")
    end)
    local function native_test(name, fn)
        local full_name = name:sub(1, 12) == "#428 bayonet" and name or "#428 bayonet " .. name
        H.test_if(T.available, full_name, fn, "required tracked native fixture unavailable")
    end
    local function hook_owner(c, patch)
        local original = c.mod.dofile
        c.mod.dofile = function(self, path)
            local value = original(self, path)
            if path:match("/_cwv_old_musket_melee_owner$") then
                local bind = value.bind
                return { bind = function(helper, mechanics, sweep_guard_factory)
                    local new = bind(helper, mechanics, sweep_guard_factory)
                    return function(opts)
                        if patch then patch(opts, c) end
                        local owner = new(opts)
                        c.melee_owner = owner
                        c.melee_new, c.melee_options = new, opts
                        local construct = owner.construct
                        owner.construct = function(...)
                            c.melee_finish = select(2, ...)
                            if c.before_construct then c.before_construct() end
                            c.before_melee = { generation = rawget(c.state, "_cwv_damage_profile_generation"),
                                fallback = rawget(c.state, "_cwv_wire_fallback_profile_id"),
                                profiles = T.shape(c.env.DamageProfileTemplates), lookup = T.shape(c.lookup),
                                source = T.shape(c.state._cwv_damage_profile_wire_source) }
                            if c.finish_counterfactual then
                                local source, finish = ...
                                return construct(source, function(template)
                                    local result = finish(template)
                                    c.finish_counterfactual()
                                    return result
                                end)
                            end
                            return construct(...)
                        end
                        return owner
                    end
                end }
            end
            return value
        end
    end
    local function raw_family(c)
        return { T.shape(c.env.DamageProfileTemplates), T.shape(c.lookup), T.shape(c.state),
            T.shape(c.state._cwv_damage_profile_wire_source), T.shape(c.env.Weapons) }
    end
    local function unchanged(rows) for _, row in ipairs(rows) do T.unchanged(row) end end
    local function install_route(c)
        local call = '_variant_install.install_template_router()'
        H.truthy(c.entry:find(call, 1, true), "actual entry router invocation")
        T.run("return function(_variant_install) " .. call .. " end", c.env, "actual-entry-router-invocation")(c.capsule)
        return assert(c.hooks['BackendUtils:get_item_template'])
    end
    local function action_callbacks(c, template)
        local results, player = {}, {}
        local inv = { equipment = function() return { wielded_slot = "slot_melee", slots = {
            slot_melee = { item_data = { template = "foreign" } } } } end }
        c.env.Unit = { alive = function(unit) return unit == player end }
        c.env.ScriptUnit = { extension = function(unit, system)
            H.equal(unit, player); H.equal(system, "inventory_system"); return inv
        end }
        local input = { reset_release_input = function() results.reset = (results.reset or 0) + 1; return "reset-result" end,
            reset_release_input_with_delay = function(_, remaining) results.delay = remaining; return "delay-result" end }
        local seen = {}
        for group_name, group in pairs(template.actions) do
            for action_name, action in pairs(group) do
                if type(action) == "table" then
                    for field, callback in pairs(action) do
                        if type(callback) == "function" then
                            local key = group_name .. "." .. action_name .. "." .. field
                            if field == "anim_end_event_condition_func" then
                                local row = {}
                                for _, reason in ipairs({ "new_interupting_action", "action_complete", "other" }) do row[#row + 1] = callback(player, reason) end
                                results[key] = row
                            elseif field == "enter_function" then
                                results[key] = { callback(player, input, 0.375) }
                            elseif field == "chain_condition_func" then
                                local original = c.env.ScriptUnit.extension
                                for _, fatigued in ipairs({ false, true }) do
                                    c.env.ScriptUnit.extension = function(unit, system)
                                        if system == "status_system" then return { fatigued = function() return fatigued end } end
                                        return original(unit, system)
                                    end
                                    results[key .. tostring(fatigued)] = callback(player, input)
                                end
                                c.env.ScriptUnit.extension = original
                            else error("unexercised native callback " .. key) end
                            seen[key] = true
                        end
                    end
                end
            end
        end
        local count = 0; for _ in pairs(seen) do count = count + 1 end
        H.truthy(count > 15, "native and stance callbacks were actually invoked")
        return results, count
    end
    local function comparable(value)
        if type(value) == "function" then return "<callback-tested-separately>" end
        if type(value) ~= "table" then return value end
        local clone = {}; for k, v in pairs(value) do clone[k] = comparable(v) end
        return clone
    end
    local function prior_installed()
        -- Required tracked complete pre-bayonet runtime, byte-exact from the
        -- approved rangedR2 producer; no ignored review tree or env override.
        local prior = root .. "/qa/lua/fixtures/cwv_old_musket_ranged_prior_runtime.lua"
        return T.installed(function(c)
            local original = c.mod.dofile
            c.mod.dofile = function(self, path)
                if path:match("/_cwv_musket_runtime$") then
                    return T.run(T.read(prior), c.env, "tracked-complete-ranged-prerequisite-runtime")
                end
                return original(self, path)
            end
        end)
    end
    H.test_if(Native.external_available(root), "#428 optional external native snapshot provenance", function()
        local c = T.installed()
        local snapshot = Native.snapshot(root)
        local external = setmetatable({ DamageProfileTemplates = {}, Weapons = {}, table = c.env.table }, { __index = c.env })
        Native.load_external(external, root)
        for _, name in ipairs(NAMES) do
            H.deep_equal(external.DamageProfileTemplates[name], snapshot.resolved_profiles[name], "actual native resolution " .. name)
        end
        local base = T.native_root .. "/scripts/settings/equipment/weapon_templates/"
        H.equal(T.read(base .. "handguns.lua"), snapshot.handguns, "verbatim native handgun template")
        H.equal(T.read(base .. "2h_heavy_spears.lua"), snapshot.tuskgor, "verbatim complete Tuskgor callbacks")
        local action = T.read(T.native_root .. "/scripts/unit_extensions/weapons/actions/action_handgun.lua")
        local a = assert(action:find("ActionHandgun.client_owner_post_update = function", 1, true))
        local b = assert(action:find("\nActionHandgun.finish =", a, true))
        H.equal(action:sub(a, b - 1), snapshot.handgun_post_update, "verbatim native firing callback")
    end, "optional external native checkout absent; required portable tests still run")
    native_test("finish preimages preserve intervening source authority", function()
        for _, axis in ipairs({ "generation", "map_root", "fallback" }) do
            local intervened, expected_generation, expected_map, expected_fallback = false
            local c = T.installed(function(row)
                hook_owner(row)
                row.finish_counterfactual = function()
                    if intervened then return end
                    intervened = true
                    expected_generation = rawget(row.state, "_cwv_damage_profile_generation")
                    expected_map = rawget(row.state, "_cwv_damage_profile_wire_source")
                    expected_fallback = rawget(row.state, "_cwv_wire_fallback_profile_id")
                    if axis == "generation" then
                        expected_generation = expected_generation + 100
                        rawset(row.state, "_cwv_damage_profile_generation", expected_generation)
                    elseif axis == "map_root" then
                        expected_map = { foreign_finish = true }
                        rawset(row.state, "_cwv_damage_profile_wire_source", expected_map)
                    else
                        expected_fallback = row.lookup[NAMES[1]]
                        rawset(row.state, "_cwv_wire_fallback_profile_id", expected_fallback)
                    end
                end
            end)
            H.truthy(intervened, "actual construction finish seam reached")
            H.equal(rawget(c.state, "_cwv_damage_profile_generation"), expected_generation, axis .. " intervening generation preserved")
            H.equal(rawget(c.state, "_cwv_damage_profile_wire_source"), expected_map, axis .. " intervening map preserved")
            H.equal(rawget(c.state, "_cwv_wire_fallback_profile_id"), expected_fallback, axis .. " intervening fallback preserved")
            H.truthy(c.melee_owner.ready(), "complete proven native fallback after rejected custom preparation")
            for _, name in ipairs(NAMES) do
                H.equal(rawget(c.env.DamageProfileTemplates, P .. name), nil, "stale preparation must not publish custom family")
                H.equal(rawget(c.lookup, P .. name), nil)
            end
            T.unchanged(c.before_melee.profiles); T.unchanged(c.before_melee.lookup); T.unchanged(c.before_melee.source)
        end
    end)
    native_test("actual old new complete healthy math IDs generation callbacks equivalent", function()
        local old, c = prior_installed(), T.installed()
        H.equal(c.capsule.check_old_musket(), nil, "complete constructor reason")
        H.deep_equal(c.lookup, old.lookup, "actual clone pairs encounter IDs/order preserved")
        H.deep_equal(c.state._cwv_damage_profile_wire_source, old.state._cwv_damage_profile_wire_source)
        H.equal(c.state._cwv_damage_profile_generation, 9, "2 earlier producers plus 7 occurrences, not 4")
        H.equal(c.state._cwv_damage_profile_generation, old.state._cwv_damage_profile_generation)
        H.equal(c.state._cwv_wire_fallback_profile_id, old.state._cwv_wire_fallback_profile_id)
        for _, name in ipairs(NAMES) do
            H.deep_equal(c.env.DamageProfileTemplates[P .. name], old.env.DamageProfileTemplates[P .. name])
            H.deep_equal(c.env.DamageProfileTemplates[name], old.env.DamageProfileTemplates[name], "native donor unchanged")
        end
        for _, name in ipairs({ KEY, "old_musket_template", "musket_template", "musket_template_melee" }) do
            H.deep_equal(comparable(c.env.Weapons[name]), comparable(old.env.Weapons[name]), name .. " full structure")
        end
        local old_callbacks, old_count = action_callbacks(old, old.env.Weapons[KEY])
        local callbacks, count = action_callbacks(c, c.env.Weapons[KEY])
        H.equal(count, old_count); H.deep_equal(callbacks, old_callbacks, "every authored callback behavior compared")
        H.truthy(c.mod._cwv_old_musket_interrupt.audit(c.env.Weapons[KEY], "action_three"))
        H.equal(c.capsule.check_old_musket(), nil)
    end)
    for _, name in ipairs(NAMES) do
        for _, cell in ipairs({ "profile", "numeric", "reverse", "source" }) do
            for _, kind in ipairs({ "write", "readback" }) do
                local selected, mode = cell .. ":" .. name, kind
                native_test("family rollback " .. selected .. " " .. mode, function()
                    local c = T.installed(function(row) hook_owner(row, function(opts, ctx)
                        local old_write, old_read = rawset, rawget
                        if mode == "write" then opts.write = function(t, k, v, tag)
                            old_write(t, k, v); if tag == selected then error("injected family write") end
                        end else opts.read = function(t, k, tag)
                            if tag == selected then return "readback-rejected" end; return old_read(t, k)
                        end end
                    end) end)
                    H.truthy(c.env.Weapons[KEY], "complete proven native fallback may publish")
                    for _, source in ipairs(NAMES) do
                        H.equal(rawget(c.env.DamageProfileTemplates, P .. source), nil)
                        H.equal(rawget(c.lookup, P .. source), nil)
                        H.equal(rawget(c.state._cwv_damage_profile_wire_source, P .. source), nil)
                    end
                    H.equal(#c.lookup, 7, "no partial custom numeric IDs")
                    H.equal(c.state._cwv_damage_profile_generation, 2)
                    H.equal(c.state._cwv_wire_fallback_profile_id, 1)
                    T.unchanged(c.before_melee.profiles); T.unchanged(c.before_melee.lookup); T.unchanged(c.before_melee.source)
                    for _, group in pairs(c.env.Weapons[KEY].actions) do for _, action in pairs(group) do
                        if type(action) == "table" and action.damage_profile then H.truthy(rawget(c.lookup, action.damage_profile)); H.truthy(rawget(c.env.DamageProfileTemplates, action.damage_profile)) end
                    end end
                    H.equal(c.capsule.check_old_musket(), nil)
                end)
            end
        end
    end
    for _, tag in ipairs({ "generation", "template" }) do
        for _, kind in ipairs({ "write", "readback" }) do
            local selected, mode = tag, kind
            native_test("family rollback " .. selected .. " " .. mode, function()
                local c = T.installed(function(row) hook_owner(row, function(opts)
                    if mode == "write" then opts.write = function(t, k, v, where)
                        rawset(t, k, v); if where == selected then error("injected final family write") end
                    end else opts.read = function(t, k, where)
                        if where == selected then return false end; return rawget(t, k)
                    end end
                end) end)
                for _, source in ipairs(NAMES) do
                    H.equal(rawget(c.env.DamageProfileTemplates, P .. source), nil)
                    H.equal(rawget(c.lookup, P .. source), nil)
                    H.equal(rawget(c.state._cwv_damage_profile_wire_source, P .. source), nil)
                end
                H.equal(c.state._cwv_damage_profile_generation, 2)
                if selected == "template" then
                    H.equal(rawget(c.env.Weapons, KEY), nil)
                    H.equal(c.capsule.admit_old_musket({ item_key = "cwv_es_musket_old", template = "old_musket_template" }), false)
                else H.truthy(c.env.Weapons[KEY]); H.equal(c.capsule.check_old_musket(), nil) end
            end)
        end
    end
    native_test("complete template interrupt construction failure leaves no custom family", function()
        for _, mode in ipairs({ "throw", "audit", "clone_alias", "template_foreign", "native_profile", "native_id" }) do
            local c = T.installed(function(row)
                hook_owner(row)
                if mode == "throw" then
                    local install = row.mod._cwv_old_musket_interrupt.install
                    row.mod._cwv_old_musket_interrupt.install = function(template, action)
                        if template.actions.action_one.heavy_attack_tank then error("interrupt construction rejected") end
                        return install(template, action)
                    end
                elseif mode == "audit" then row.mod._cwv_old_musket_interrupt.audit = function() return false end
                elseif mode == "template_foreign" then row.foreign = {}; row.env.Weapons[KEY] = row.foreign
                elseif mode == "native_profile" then row.env.DamageProfileTemplates[NAMES[1]] = nil
                elseif mode == "native_id" then row.lookup[NAMES[1]] = nil
                elseif mode == "clone_alias" then hook_owner(row, function(opts) opts.clone = function(v) return v end end) end
            end)
            H.equal(rawget(c.env.Weapons, KEY), c.foreign)
            for _, source in ipairs(NAMES) do H.equal(rawget(c.env.DamageProfileTemplates, P .. source), nil) end
            H.equal(c.state._cwv_damage_profile_generation, c.before_melee.generation, "no new melee generation on rejected family")
            H.equal(c.capsule.admit_old_musket({ item_key = "cwv_es_musket_old", template = "old_musket_template" }), false)
            H.truthy(c.capsule.check_old_musket())
        end
    end)
    native_test("#428 bayonet composite actual builder seed pending and retained closure by value", function()
        local c = T.installed(); local old, control, build, check = T.private_items(c)
        H.truthy(build(old)); H.equal(check(), nil)
        H.truthy(c.mod._cwv_acquisition.build_seed(old, build, function(v) return c.env.table.clone(v, true) end, function() return false end))
        local saved = { item_key = old.item_key, template = "old_musket_template", mod_data = { cwv_musket_stance = "melee" }, untouched = {} }
        local saved_shape, iml, names = T.shape(saved), T.shape(c.env.ItemMasterList), T.shape(c.env.NetworkLookup.item_names)
        c.env.DamageProfileTemplates[P .. NAMES[1]] = nil
        H.equal(build(old), nil); H.equal(c.mod._cwv_acquisition.build_seed(old, build,
            function(v) return c.env.table.clone(v, true) end, function() return false end), nil)
        H.truthy(build(control)); H.truthy(check()); T.unchanged(saved_shape); T.unchanged(iml); T.unchanged(names)
        local missing = T.installed(function(row) row.env.Weapons.two_handed_heavy_spears_template = nil end)
        old, control, build, check = T.private_items(missing)
        H.equal(build(old), nil); H.truthy(build(control)); H.truthy(check())
    end)
    native_test("first fallback transaction write readback and actual encounter choice", function()
        for _, mode in ipairs({ "healthy", "write", "readback" }) do
            local c = T.installed(function(row) hook_owner(row) end)
            local profiles, lookup, weapons, state = {}, {}, {}, { _cwv_damage_profile_wire_source = {}, _cwv_damage_profile_generation = 0 }
            for _, name in ipairs(NAMES) do
                profiles[name] = c.env.DamageProfileTemplates[name]
                local id = #lookup + 1; lookup[id], lookup[name] = name, id
            end
            weapons.two_handed_heavy_spears_template = c.env.Weapons.two_handed_heavy_spears_template
            local inherited = { [P .. NAMES[1]] = "inherited-not-authority" }
            setmetatable(profiles, { __index = inherited }); setmetatable(lookup, { __index = function() error("strict missing lookup") end })
            setmetatable(state, { __index = { _cwv_wire_fallback_profile_id = 999 } })
            local prior_profiles, prior_lookup, prior_map = T.shape(profiles), T.shape(lookup), T.shape(state._cwv_damage_profile_wire_source)
            local opts = { state = state, profiles = function() return profiles end, lookup = function() return lookup end,
                weapons = function() return weapons end, clone = function(v) return c.env.table.clone(v, true) end }
            if mode == "write" then opts.write = function(t, k, v, tag) rawset(t, k, v); if tag == "fallback" then error("fallback write rejected") end end
            elseif mode == "readback" then opts.read = function(t, k, tag) if tag == "fallback" then return false end; return rawget(t, k) end end
            local owner = c.melee_new(opts)
            H.truthy(owner.construct(weapons.two_handed_heavy_spears_template, c.melee_finish)); H.truthy(owner.ready())
            if mode == "healthy" then
                local first_name = assert(lookup[5]):sub(#P + 1)
                H.equal(state._cwv_wire_fallback_profile_id, lookup[first_name], "first clone pairs encounter, not alphabetic source order")
                H.equal(state._cwv_damage_profile_generation, 7)
            else
                T.unchanged(prior_profiles); T.unchanged(prior_lookup); T.unchanged(prior_map)
                H.equal(rawget(state, "_cwv_wire_fallback_profile_id"), nil, "raw absence restored, inherited value untouched")
                H.equal(state._cwv_damage_profile_generation, 0)
            end
            H.equal(getmetatable(profiles).__index, inherited)
        end
    end)
    native_test("final retained readback rolls complete family then publishes proven native", function()
        local c = T.installed(function(row) hook_owner(row, function(opts)
            opts.write = function(t, k, value, tag)
                rawset(t, k, value)
                if tag == "template" and value.actions.action_one.light_attack_left.damage_profile:sub(1, #P) == P then
                    value.actions.action_one.light_attack_left.range_mod = 99
                end
            end
        end) end)
        H.truthy(c.env.Weapons[KEY]); H.equal(c.capsule.check_old_musket(), nil)
        T.unchanged(c.before_melee.profiles); T.unchanged(c.before_melee.lookup); T.unchanged(c.before_melee.source)
        H.equal(c.state._cwv_damage_profile_generation, c.before_melee.generation)
    end)
    native_test("foreign family and fresh unsupported owner never become authority", function()
        for _, mode in ipairs({ "profile", "reverse", "source", "generation", "fallback" }) do
            local c = T.installed(function(row)
                hook_owner(row)
                row.before_construct = function()
                    if mode == "profile" then row.env.DamageProfileTemplates[P .. NAMES[1]] = { foreign = true }
                    elseif mode == "reverse" then row.lookup[99], row.lookup[P .. NAMES[1]] = P .. NAMES[1], 99
                    elseif mode == "source" then row.state._cwv_damage_profile_wire_source[P .. NAMES[1]] = NAMES[1]
                    elseif mode == "generation" then row.state._cwv_damage_profile_generation = "foreign"
                    elseif mode == "fallback" then row.state._cwv_wire_fallback_profile_id = 999 end
                end
            end)
            H.truthy(c.env.Weapons[KEY], "complete native closure may degrade without adopting custom state")
            T.unchanged(c.before_melee.profiles); T.unchanged(c.before_melee.lookup); T.unchanged(c.before_melee.source)
            H.equal(c.state._cwv_damage_profile_generation, c.before_melee.generation)
        end
        local c = T.installed(function(row) hook_owner(row) end)
        local fresh = c.melee_new(c.melee_options)
        local before = raw_family(c)
        H.equal(fresh.construct(c.env.Weapons.two_handed_heavy_spears_template, c.melee_finish), false)
        H.equal(fresh.ready(), false); unchanged(before)
    end)
    native_test("#428 bayonet actual CIM missing-master restore keeps exact saved record pending", function()
        local c = T.installed(function(row) row.env.Weapons.two_handed_heavy_spears_template = nil end)
        local old, _, build = T.private_items(c)
        H.equal(build(old), nil); H.equal(rawget(c.env.ItemMasterList, old.item_key), nil)
        local saved = { item_key = old.item_key, via_mirror = true, mod_data = { cwv_musket_stance = "melee" }, untouched = {} }
        local saved_shape, md_shape = T.shape(saved), T.shape(saved.mod_data)
        local source = T.read(root .. "/crafting_in_modded_dev/scripts/mods/crafting_in_modded_dev/crafting_in_modded_dev.lua")
        local a = assert(source:find("local function _athanor_inject_item(weapon_data, backend_id)", 1, true))
        local b = assert(source:find("\nlocal _DIRECT_CRAFT_OWNER =", a, true))
        local inject = source:sub(a, b - 1)
        a = assert(source:find("local _pending_inject = {}", b, true))
        b = assert(source:find("\n-- v0.7.28", a, true) or source:find("\nlocal _cim_loadout_restore_timer", a, true))
        local pending = source:sub(a, b - 1)
        local factory = T.run("return function(mod, _forge_state)\nlocal _athanor_inject_all\n" .. inject .. "\n" .. pending
            .. "\nreturn _athanor_inject_all, _athanor_retry_pending, function() return _pending_inject end end", c.env, "actual-CIM-missing-master-restore")
        local ledger = { adds = 0, save_writes = 0 }
        c.env.Managers = { backend = { get_backend_mirror = function() return { _inventory_items = {}, add_item = function() ledger.adds = ledger.adds + 1 end } end } }
        local mod = { info=function() end, echo=function() end, warning=function() end, get=function() return true end }
        local restore, retry, get_pending = factory(mod, { get_forged_weapons = function() return { persisted = saved } end })
        restore(); H.equal(get_pending().persisted, saved); retry(); H.equal(get_pending().persisted, saved)
        H.equal(ledger.adds, 0); H.equal(ledger.save_writes, 0)
        T.unchanged(saved_shape); T.unchanged(md_shape)
        H.truthy(mod._cim_restore_failures.persisted:find("not in ItemMasterList", 1, true))
    end)
    native_test("actual canonical career installer handoff accepts only proven extension cells", function()
        local function reconciled()
            local inherited = { default = { kind = "career-inherited-ledger" } }
            local c = T.installed(function(row)
                row.env.ActionTemplates.action_career_inherited = inherited
                row.env.Weapons.two_handed_heavy_spears_template.actions.action_career_inherited = inherited
            end)
            local old, _, build, check = T.private_items(c)
            c.private_check, c.private_build, c.old_definition = check, build, old
            local entry = assert(build(old)); c.env.ItemMasterList[old.item_key] = entry
            local canonical = { default = { kind = "career-canonical-ledger" } }
            c.env.ActionTemplates.action_career_owned = canonical
            local settings = {}
            for _, career in ipairs(entry.can_wield) do settings[career] = { activated_ability = { { action_name = "action_career_owned" } } } end
            local adapter = c.load("_cwv_career_weapon_actions")
            local integration = T.run(T.read(root .. "/tools/shared_lib/_lib_career_weapon_actions.lua"), c.env, "actual-career-integration")
            local effective = T.run(T.read(root .. "/tools/shared_lib/_lib_effective_weapon_templates.lua"), c.env, "actual-effective-template-planner")
            local report = adapter.install({ { def = old, entry = entry } }, c.env.ItemMasterList, c.env.Weapons,
                settings, c.env.ActionTemplates, integration, effective, "character_weapon_variants")
            H.truthy(report.ok); H.equal(report.template_count, 2)
            H.equal(c.env.Weapons[KEY].actions.action_career_owned, canonical)
            H.equal(c.env.Weapons[KEY].actions.action_career_inherited, inherited)
            H.equal(check(), nil, "actual career additions do not revoke construction authority")
            return c
        end
        local c = reconciled(); local route = install_route(c)
        H.equal(route(function() return c.env.Weapons.old_musket_template end,
            { template="old_musket_template", mod_data={cwv_musket_stance="melee"} }), c.env.Weapons[KEY])
        for index, tamper in ipairs({
            function(row) row.env.Weapons[KEY].actions.action_career_owned = {} end,
            function(row)
                local canonical = {}; row.env.ActionTemplates.action_career_foreign = canonical
                row.env.Weapons[KEY].actions.action_career_foreign = canonical
            end,
            function(row) row.env.Weapons[KEY].__vt2_tweaker_career_action_clone_source = "foreign" end,
            function(row) row.env.Weapons[KEY].__vt2_tweaker_career_action_claims.action_career_owned.value = {} end,
            function(row) row.env.Weapons[KEY].__vt2_tweaker_career_action_claims.action_career_owned.owners.character_weapon_variants = nil end,
            function(row) row.env.Weapons[KEY].actions.action_one.light_attack_left.range_mod = 99 end,
            function(row) row.env.Weapons[KEY].actions.action_three.default.allowed_chain_actions[1] = {} end,
        }) do
            local row = reconciled(); tamper(row)
            H.truthy(row.private_check(), "only exact canonical installer-owned extension cells accepted control=" .. index)
            H.equal(row.private_build(row.old_definition), nil)
        end
    end)
    local function stance(c, item, target_fail)
        local player, ledger = {}, { wire=0, ammo=0, destroy=0, add=0, wield=0 }
        local equipment = { wielded_slot = "slot_melee", slots = { slot_melee = { item_data = item } }, right_hand_wielded_unit = {} }
        local inv = { equipment = function() return equipment end,
            destroy_slot = function() ledger.destroy = ledger.destroy + 1 end,
            add_equipment = function() ledger.add = ledger.add + 1 end,
            wield = function() ledger.wield = ledger.wield + 1 end }
        c.env.Unit = { alive = function() return true end }
        c.env.ScriptUnit = { extension = function(_, system)
            if system == "inventory_system" then return inv end
            ledger.ammo = ledger.ammo + 1; return { _current_ammo=1, _available_ammo=8, _shots_fired=0 }
        end, has_extension = function() ledger.ammo = ledger.ammo + 1; return false end }
        c.state._old_musket_record_and_publish = function() ledger.wire = ledger.wire + 1 end
        if target_fail then target_fail(c) end
        local before = T.shape(item)
        local callback = c.env.Weapons.old_musket_template.actions.action_three.default.enter_function
        callback(player, {})
        return ledger, before
    end
    native_test("#428 bayonet target stance preflight precedes all item wire ammo slot mutations", function()
        local mutations = {
            function(c) c.env.DamageProfileTemplates[P .. NAMES[1]] = nil end,
            function(c) c.lookup[P .. NAMES[2]] = nil end,
            function(c) c.env.Weapons[KEY].actions.action_one.light_attack_left.damage_profile = "foreign" end,
            function(c) c.env.Weapons[KEY].actions.action_three.default.enter_function = function() end end,
        }
        for _, mutate in ipairs(mutations) do
            local c = T.installed(); local item = { template = "old_musket_template", backend_id = "cwv_es_musket_old_saved" }
            local ledger, before = stance(c, item, mutate)
            H.deep_equal(ledger, { wire=0, ammo=0, destroy=0, add=0, wield=0 }); T.unchanged(before)
        end
        local c = T.installed(); local item = { template = "old_musket_template", mod_data = { cwv_musket_stance = "melee" } }
        local md = T.shape(item.mod_data)
        local ledger = stance(c, item, function(row) row.env.DamageProfileTemplates.cwv_old_musket_shot = nil end)
        H.deep_equal(ledger, { wire=0, ammo=0, destroy=0, add=0, wield=0 }); T.unchanged(md)
        local regular = T.installed(); local regular_item = { template = "musket_template" }
        ledger = stance(regular, regular_item, function(row) row.env.Weapons[KEY] = nil end)
        H.equal(regular_item.mod_data.cwv_musket_stance, "melee"); H.equal(ledger.destroy, 1); H.equal(ledger.add, 1); H.equal(ledger.wield, 1)
        local healthy = T.installed(); local healthy_item = { template = "old_musket_template" }
        ledger = stance(healthy, healthy_item)
        H.equal(healthy_item.mod_data.cwv_musket_stance, "melee"); H.equal(ledger.wire, 1); H.equal(ledger.destroy, 1)
    end)
    native_test("#428 bayonet actual singleton router keeps native first precedence and finite authority", function()
        local c = T.installed(); local route = install_route(c)
        H.equal(c.hooks['BackendUtils:get_item_template'], route)
        local order, native_template, style_template, crow_template = {}, {}, {}, {}
        local function native(item, backend) order[#order + 1] = "native"; return native_template end
        c.state.combat_styles = { resolve_template = function(self, item, backend) order[#order + 1] = "style"; return style_template end }
        c.state.crowbill_runtime = { resolve_template = function(item, backend) order[#order + 1] = "crowbill"; return crow_template end }
        H.equal(route(native, { template = "old_musket_template" }, "id"), style_template)
        H.deep_equal(order, { "native", "style" })
        order = {}; c.state.combat_styles.resolve_template = function() order[#order + 1] = "style" end
        H.equal(route(native, { template = "old_musket_template" }, "id"), crow_template)
        H.deep_equal(order, { "native", "style", "crowbill" })
        c.state.crowbill_runtime = nil; c.state.combat_styles = nil
        H.equal(route(native, nil, "id"), native_template)
        H.equal(route(native, { template = "foreign" }, "id"), native_template)
        local item = { template = "old_musket_template", mod_data = { cwv_musket_stance = "melee" } }
        H.equal(route(native, item, "id"), c.env.Weapons[KEY])
        c.env.DamageProfileTemplates[P .. NAMES[1]] = nil
        H.equal(route(native, item, "id"), c.env.Weapons.old_musket_template, "only proven ranged fallback")
        c.env.DamageProfileTemplates.cwv_old_musket_shot = nil
        H.equal(pcall(route, native, item, "id"), false, "never return unproven native result/nil")
        local regular = { template = "musket_template", mod_data = { cwv_musket_stance = "melee" } }
        H.equal(route(native, regular, "id"), c.env.Weapons.musket_template_melee)
        H.equal(pcall(route, function() error("native assertion") end, regular, "id"), false, "native-first assertion is not claimed rescued")
    end)
end
