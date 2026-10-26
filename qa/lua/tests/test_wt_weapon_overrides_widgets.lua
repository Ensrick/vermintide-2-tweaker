-- Complete production menu construction versus the frozen inline descriptor.
-- The independent literal is a data oracle, not a copied gameplay algorithm.
return function(H, repo_root)
    local INLINE = [==[
            {
                setting_id = "weapon_overrides",
                type = "group",
                -- Leaves sorted A->Z by display label (repo standing sort rule).
                sub_widgets = {
                    {
                        setting_id = "wt_rework_master_group",
                        type = "group",
                        sub_widgets = {
                            { setting_id = "wt_rework_master_ensrick", type = "checkbox", default_value = false },
                        },
                    },
                    { setting_id = "authentic_brace_of_pistols", type = "checkbox", default_value = false },
                    { setting_id = "wt_one_hand_axe_cleave_nerf", type = "checkbox", default_value = false },
                    { setting_id = "wt_cog_hammer_heavy_speed_nerf", type = "checkbox", default_value = false },
                    { setting_id = "wt_dual_axes_cleave", type = "checkbox", default_value = true },
                    { setting_id = "wt_dual_axes_light_crit", type = "checkbox", default_value = true },
                    { setting_id = "wt_executioner_light_headshot_bonus", type = "checkbox", default_value = false },
                    -- #942: absolute heat, direct damage only; settings stay editable on mismatch.
                    { setting_id = "wt_fire_sword_heat", type = "checkbox", default_value = false,
                        sub_widgets = {
                            { setting_id = "wt_fire_sword_heat_armor", type = "checkbox", default_value = false },
                            { setting_id = "wt_fire_sword_heat_cleave_percent", type = "numeric", default_value = 2, range = { 0, 10 }, decimals_number = 2 },
                            { setting_id = "wt_fire_sword_heat_damage_percent", type = "numeric", default_value = 1, range = { 0, 10 }, decimals_number = 2 },
                            { setting_id = "wt_fire_sword_heat_armor_threshold", type = "numeric", default_value = 25, range = { 0, 100 }, decimals_number = 1 },
                        },
                    },
                    -- Issue #943: independent Fire Sword heavy projections (both default off).
                    { setting_id = "wt_fire_sword_nova_slowdown", type = "checkbox", default_value = false },
                    { setting_id = "wt_fire_sword_sweep_opener", type = "checkbox", default_value = false },
                    { setting_id = "wt_greataxe_light_crit", type = "checkbox", default_value = true },
                    { setting_id = "wt_mace_sword_speed_nerf", type = "checkbox", default_value = false },
                    { setting_id = "wt_bolt_staff_primary_overcharge_reduction", type = "checkbox", default_value = false },
                    -- Explicit tooltip: the loc key ends in _tooltip, which VMF does NOT
                    -- auto-resolve (auto path only tries <setting_id>_description).
                    { setting_id = "wt_brett_sword_shield_buff", type = "checkbox", default_value = false, tooltip = "wt_brett_sword_shield_buff_tooltip" },
                    -- Issue #348: revert 6.11.0 Kruber Empire 1h sword push-attack combo.
                    -- Uses the auto-resolved <setting_id>_description loc key for its tooltip.
                    { setting_id = "wt_revert_1h_sword_push_combo", type = "checkbox", default_value = false },
                    { setting_id = "moonfire_aoe_revert", type = "checkbox", default_value = false },
                    { setting_id = "wt_priest_punch_buff", type = "checkbox", default_value = false },
                },
            }
]==]
    local streams = { "weapon_tweaker", "weapon_tweaker_dev" }
    local function read(path)
        local file = assert(io.open(path, "rb"))
        local source = file:read("*a"); file:close()
        return source:gsub("\r\n", "\n")
    end
    local function replace_once(source, before, after)
        local first, last = assert(source:find(before, 1, true))
        assert(not source:find(before, last + 1, true), "duplicate data-owner call")
        return source:sub(1, first - 1) .. after .. source:sub(last + 1)
    end
    local function fixture(ns, options)
        options = options or {}
        local prefix = "scripts/mods/" .. ns .. "/"
        local child_path = prefix .. "_wt_weapon_overrides_widgets"
        local log, writes, child_loads, child_builds = {}, 0, 0, 0
        local env = setmetatable({}, { __index = _G })
        env._G, env.Managers, env.Unit, env.Weapons = env, nil, nil, nil
        local mod = { _wt = {}, _wt_loc_raw = {} }
        local cwv = options.cwv and {
            is_enabled = function() return options.cwv == "active" end,
        } or nil
        env.get_mod = function(id)
            if id == "wt" or id == "wt_dev" then return mod end
            if id == "character_weapon_variants" then return cwv end
        end
        env.printf = function() end
        local function forbidden() error("data construction touched gameplay/settings", 0) end
        mod.hook, mod.hook_safe, mod.network_send, mod.command = forbidden, forbidden, forbidden, forbidden
        mod.set = function() writes = writes + 1; forbidden() end
        mod.get = function() return nil end
        mod.debug, mod.warning = function() end, function() end
        mod.localize = function(_, id) return id end
        local function execute(path, source)
            local chunk = source and assert(loadstring(source, "@" .. path))
                or assert(loadfile(path))
            setfenv(chunk, env)
            return chunk()
        end
        local child
        function mod:dofile(path)
            assert(path:sub(1, #prefix) == prefix, "foreign data dependency")
            local stem = path:sub(#prefix + 1)
            assert(not stem:find("^_wt_fire_sword") and not stem:find("^_wt_priest"),
                "data module eagerly loaded gameplay")
            log[#log + 1] = path
            if path == child_path then
                child_loads = child_loads + 1
                if options.loader_error then error(options.loader_error, 0) end
                if options.factory_error then
                    return { build = function() child_builds = child_builds + 1; error(options.factory_error, 0) end }
                end
                if options.missing_build then return {} end
                if not child or not options.cache_child then
                    child = execute(repo_root .. "/" .. ns .. "/" .. path .. ".lua")
                end
                local actual_build = child.build
                return { build = function()
                    child_builds = child_builds + 1
                    return actual_build()
                end }
            end
            if options.empty_cwv and stem == "wt_cwv_variant_catalog" then return {} end
            if options.history_error and stem == "_wt_history_2_0_6_catalog" then
                error(options.history_error, 0)
            end
            return execute(repo_root .. "/" .. ns .. "/" .. path .. ".lua")
        end
        env.dofile = function(path) return execute(repo_root .. "/" .. path) end
        local function run(inline)
            local path = repo_root .. "/" .. ns .. "/" .. prefix .. ns .. "_data.lua"
            if not inline then return execute(path) end
            local source = read(path)
            if inline then
                source = replace_once(source, 'mod:dofile("' .. child_path .. '").build()', INLINE)
            end
            return execute(path, source)
        end
        return {
            run = run, mod = mod, log = log,
            counts = function() return writes, child_loads, child_builds end,
            child_path = child_path,
        }
    end
    local function find_all(data, id)
        local matches = {}
        local function visit(node)
            if node.setting_id == id then matches[#matches + 1] = node end
            for _, child in ipairs(node.sub_widgets or {}) do visit(child) end
        end
        for _, node in ipairs(data.options.widgets) do visit(node) end
        return matches
    end
    local function one(data, id)
        local rows = find_all(data, id)
        H.equal(#rows, 1, "setting must occur exactly once: " .. id)
        return rows[1]
    end
    for _, namespace in ipairs(streams) do
        local ns = namespace
        for _, configuration in ipairs({
            { label = "absent" },
            { label = "disabled", cwv = "disabled" },
            { label = "active", cwv = "active" },
            { label = "empty catalog", cwv = "active", empty_cwv = true },
            { label = "history unavailable", history_error = {} },
        }) do
            local options = configuration
            H.test("WT complete " .. ns .. " menu preserves frozen inline tree: " .. options.label, function()
                local actual, expected = fixture(ns, options), fixture(ns, options)
                local tree, before = actual.run(false), expected.run(true)
                H.deep_equal(tree, before, "complete returned menu shape/order/defaults changed")
                local loads = {}
                for _, path in ipairs(actual.log) do
                    if path ~= actual.child_path then loads[#loads + 1] = path end
                end
                H.deep_equal(loads, expected.log, "surrounding registration dependency order changed")
                local writes, child_loads, child_builds = actual.counts()
                H.equal(writes, 0); H.equal(child_loads, 1); H.equal(child_builds, 1)
                H.equal(#find_all(tree, "cwv_variant_availability"),
                    options.cwv == "active" and not options.empty_cwv and 1 or 0)
                H.equal(#find_all(tree, "wt_history_patch_versions"), options.history_error and 0 or 1)
            end)
        end
        H.test("WT " .. ns .. " complete menu retains exact heat schema and unrelated group ordering", function()
            local tree = fixture(ns).run(false)
            local group = one(tree, "weapon_overrides")
            local oracle = assert(loadstring("return " .. INLINE))()
            H.deep_equal(group, oracle)
            local heat = one(tree, "wt_fire_sword_heat")
            H.equal(heat.default_value, false); H.equal(#heat.sub_widgets, 4)
            local expected = {
                { "wt_fire_sword_heat_armor", "checkbox", false },
                { "wt_fire_sword_heat_cleave_percent", "numeric", 2, { 0, 10 }, 2 },
                { "wt_fire_sword_heat_damage_percent", "numeric", 1, { 0, 10 }, 2 },
                { "wt_fire_sword_heat_armor_threshold", "numeric", 25, { 0, 100 }, 1 },
            }
            for index, schema in ipairs(expected) do
                local row = one(tree, schema[1])
                H.equal(heat.sub_widgets[index], row)
                H.deep_equal({ row.setting_id, row.type, row.default_value, row.range, row.decimals_number }, schema)
            end
            H.equal(one(tree, "wt_fire_sword_nova_slowdown").default_value, false)
            H.equal(one(tree, "wt_fire_sword_sweep_opener").default_value, false)
            H.equal(one(tree, "wt_priest_punch_buff").default_value, false)
        end)
        H.test("WT " .. ns .. " data owner remains fresh under cached module and repeated full menu loads", function()
            local api = fixture(ns, { cache_child = true })
            local first = api.run(false)
            one(first, "wt_fire_sword_heat").sub_widgets[1].default_value = true
            one(first, "weapon_overrides").sub_widgets[1].setting_id = "mutated private tree"
            local second = api.run(false)
            H.deep_equal(one(second, "weapon_overrides"), assert(loadstring("return " .. INLINE))())
            local writes, loads, builds = api.counts()
            H.equal(writes, 0); H.equal(loads, 2); H.equal(builds, 2)
            H.equal(#find_all(second, "weapon_overrides"), 1)
        end)
        H.test("WT " .. ns .. " pure factory needs no globals and does not share nested descriptors", function()
            local path = repo_root .. "/" .. ns .. "/scripts/mods/" .. ns .. "/_wt_weapon_overrides_widgets.lua"
            local chunk = assert(loadfile(path))
            setfenv(chunk, setmetatable({}, { __index = function(_, key) error("factory read global " .. key) end }))
            local owner = chunk()
            local first, second = owner.build(), owner.build()
            H.deep_equal(first, second); H.truthy(first ~= second)
            first.sub_widgets[1].sub_widgets[1].default_value = "private mutation"
            H.equal(second.sub_widgets[1].sub_widgets[1].default_value, false)
        end)
        for _, field in ipairs({ "loader_error", "factory_error" }) do
            local key = field
            H.test("WT " .. ns .. " complete data preserves " .. key .. " identity without retry", function()
                local sentinel, options = {}, {}
                options[key] = sentinel
                local api = fixture(ns, options)
                local ok, result = pcall(api.run, false)
                H.equal(ok, false); H.equal(result, sentinel)
                local writes, loads, builds = api.counts()
                H.equal(writes, 0); H.equal(loads, 1)
                H.equal(builds, key == "factory_error" and 1 or 0)
                H.equal(#api.log, 2, "postprocessing must not run after owner failure")
            end)
        end
        H.test("WT " .. ns .. " missing required factory does not silently omit setting registration", function()
            local api = fixture(ns, { missing_build = true })
            local ok = pcall(api.run, false)
            H.equal(ok, false)
            local writes, loads, builds = api.counts()
            H.equal(writes, 0); H.equal(loads, 1); H.equal(builds, 0)
        end)
    end
end
