-- Offline proof for #1656: five /cim_regression_test checks FAILed on a plain
-- keep session (RainReligion, cim 0.8.135-dev) for harness reasons, not product
-- defects. Every case runs the SHIPPED check through the shipped installers,
-- wired to the real production owner the check depends on:
--   modded_loadout_round_trip_save_then_clear: vanilla set_loadout_item
--     (transcribed below from backend_interface_item_playfab.lua:635-670)
--     raised on the all-no-op stub before the hook_safe capture could run;
--   inventory_property_count_within_cap: pinned the pre-#86 2-property ceiling;
--   localization_format_safe: probed placeholder strings with no arguments;
--   default_property_cap_is_five_bubbles: asserted pre-#244 linear storage;
--   overview_btn_render_target: indexed nil (the entry passed undeclared
--     globals instead of the forge UI owner's locals).
-- No global is written: production chunks run under a test-local environment
-- whose _G is the environment itself (incident #1643).
return function(H, repo_root)
    local root = repo_root .. "/crafting_in_modded_dev/scripts/mods/crafting_in_modded_dev/"
    local gut_root = repo_root .. "/gui_tweaker_dev/scripts/mods/gui_tweaker_dev/"
    local MOD_PREFIX = "scripts/mods/crafting_in_modded_dev/"
    local CAREER, SLOT = "_rt_test_career", "_rt_test_slot"

    local function read(path)
        local file = assert(io.open(path, "rb"))
        local source = file:read("*a")
        file:close()
        return source
    end

    -- Runs a production chunk with `globals` visible as its globals (rawget(_G)
    -- included); everything else falls through to the standard library.
    local function load_in(path, globals)
        local chunk = assert(loadfile(path))
        local env = setmetatable({}, { __index = _G })
        for name, value in pairs(globals or {}) do env[name] = value end
        env._G = env
        setfenv(chunk, env)
        return chunk(), env
    end

    local noop = function() end

    local function fake_mod(settings)
        local m = { _settings = settings or {}, safe_hooks = {}, commands = {} }
        function m:get(key) return self._settings[key] end
        function m:set(key, value) self._settings[key] = value end
        function m:info() end
        function m:warning() end
        function m:echo() end
        function m:debug() end
        function m:hook() end
        function m:hook_safe(target, method, callback)
            self.safe_hooks[tostring(target) .. "." .. tostring(method)] = callback
        end
        function m:command(name) self.commands[#self.commands + 1] = name end
        -- VMF resolves mod:dofile paths inside the mod's bundle.
        function m:dofile(path)
            H.equal(path:sub(1, #MOD_PREFIX), MOD_PREFIX, "dofile outside the mod")
            return assert(loadfile(root .. path:sub(#MOD_PREFIX + 1) .. ".lua"))()
        end
        return m
    end

    -- Transcription of vanilla BackendInterfaceItemPlayfab.set_loadout_item
    -- (backend_interface_item_playfab.lua:635-670; cosmetic slots from
    -- cosmetic_utils.lua:77-81). fassert becomes assert.
    local COSMETIC_SLOTS = { slot_frame = true, slot_hat = true, slot_skin = true }
    local function vanilla_set_loadout_item(self, item_id, career_name, slot_name, optional_loadout_index)
        local all_items = self:get_all_backend_items()
        local item
        if item_id then
            item = all_items[item_id]
            assert(item, "Trying to equip item that doesn't exist")
        end
        if not item then return false end
        if item.rarity == "magic" then return false end
        if COSMETIC_SLOTS[slot_name] then item_id = item.override_id or item.ItemId end
        if slot_name == "slot_pose" then item_id = item.override_id or item.ItemId end
        self._backend_mirror:set_character_data(career_name, slot_name, item_id, nil, optional_loadout_index)
        self._dirty = true
        return true
    end

    -- The shipped regression suite with the real modded-loadout, weave-loadout
    -- and forge-UI owners behind it. `options.globals` reach the check chunks.
    local function build_suite(options)
        options = options or {}
        local settings = {}
        local mod = fake_mod(settings)
        local forged = {}
        mod._cim_register_craft = function(bid, data)
            if forged[bid] then return false, "backend_id_exists" end
            forged[bid] = data
            mod:set("forged_weapons", forged)
            return true, data
        end
        mod._cim_unregister_craft = function(bid) forged[bid] = nil end
        mod._cim_is_modded_backend_id = function(bid)
            return type(bid) == "string" and forged[bid] ~= nil
        end
        mod._cim_persist_loadouts_enabled = function()
            if options.gate_leaks then return false end
            return mod:get("persist_modded_loadouts") == true
        end

        -- Real persisted-loadout owner: its hook_safe is the capture under test.
        local loadout_install = assert(loadfile(root .. "_cim_modded_loadout_owner.lua"))()
        local loadout = loadout_install({
            mod = mod,
            persist_loadouts_enabled = function()
                if options.gate_leaks then return true end
                return mod:get("persist_modded_loadouts") == true
            end,
            get_forged_weapons = function() return forged end,
        })
        local capture = assert(mod.safe_hooks["BackendInterfaceItemPlayfab.set_loadout_item"])
        -- VMF hook_safe semantics: the safe hook runs after the hooked chain
        -- returns and its own errors are contained; a raise in the chain skips it.
        local cls = {
            set_loadout_item = function(self, ...)
                local results = { vanilla_set_loadout_item(self, ...) }
                pcall(capture, self, ...)
                return unpack(results)
            end,
        }

        -- Real weave-loadout owner under the vanilla property tables.
        local function adventure(range)
            return { description_values = { { value_type = "percent", value = range } } }
        end
        local function weave(max)
            return { description_values = { { value_type = "percent", value = max } } }
        end
        -- weapon_properties.lua:6-26/78-83/108-119, weave_properties.lua:6-14/39-41/54-59.
        local property_globals = {
            WeaponProperties = { properties = {
                fatigue_regen = adventure({ 0.1, 0.3 }),
                crit_chance = adventure({ 0.03, 0.03, 0.04, 0.04, 0.05 }),
                attack_speed = adventure({ 0.03, 0.05 }),
                block_cost = adventure({ -0.1, -0.3 }),
                power_vs_chaos = adventure({ 0.05, 0.1 }),
            } },
            WeaveProperties = { properties = {
                weave_fatigue_regen = weave(0.3),
                weave_crit_chance = weave(0.05),
                weave_attack_speed = weave(0.05),
                weave_block_cost = weave(-0.3),
                weave_power_vs_chaos = weave(0.1),
            } },
        }
        local weave_mod = fake_mod(settings)
        weave_mod.dofile = function() return { install = noop } end
        weave_mod._cim244_property_value_policy =
            assert(loadfile(root .. "_cim_property_value_policy.lua"))()
        local weave_install = load_in(root .. "_cim_weave_loadout_owner.lua", property_globals)
        local weave_owner = weave_install({
            mod = weave_mod,
            is_active = function() return false end,
            get_forge_item_props = function() return {} end,
            get_forged_weapons = function() return forged end,
            get_amulet_dirty = function() return { false, false, false } end,
            forge_save = noop,
            temper_transaction = assert(loadfile(root .. "_cim_temper_transaction.lua"))(),
            get_raw_mirror_item = function() return nil end,
        })

        -- Real forge UI owner: its exports are what the overview check reads.
        local ui_mod = { hook = noop, hook_safe = noop, info = noop, warning = noop, echo = noop,
            get = function() return 300 end }
        local ui_install = assert(loadfile(root .. "_cim_forge_ui_owner.lua"))()
        mod._cim_forge_ui_owner = ui_install({
            mod = ui_mod,
            is_active = function() return false end,
            get_bg_colored = function() return false end,
            set_bg_colored = noop,
            get_managers = function() return {} end,
            get_profiles = function() return {} end,
        })

        local checks = {}
        local context = {
            mod = mod,
            rt_register = function(name, check) checks[name] = check end,
            rt_src_read = noop,
            dbg = noop,
            dbg_alert = noop,
            bubble_cap = weave_owner.bubble_cap,
            value_for_bubbles = weave_owner.value_for_bubbles,
            cap_grid_property_arrays = weave_owner.cap_grid_property_arrays,
            ensure_item_adventure_visible = noop,
            forge_load = noop,
            is_in_keep = function() return true end,
            store_property_slot = weave_owner.store_property_slot,
            accessory_property_policy = { count_slots = noop, last_slot = noop, collect_property_slots = noop },
            accessory_panel = {},
            weave_loadout = weave_owner,
            get_custom_forge_active = function() return false end,
            get_forged_weapons = function() return forged end,
            set_forged_weapons = function(store) forged = store end,
            get_modded_loadout = loadout.get_modded_loadout,
            set_modded_loadout = loadout.set_modded_loadout,
            modded_loadout_load = loadout.modded_loadout_load,
            rpc_schema = 1,
        }
        local globals = { BackendInterfaceItemPlayfab = cls }
        for name, value in pairs(options.globals or {}) do globals[name] = value end
        local core_install, core_env = load_in(root .. "_cim_regression_checks.lua", globals)
        local support = core_install(context)
        context.with_loadout_sandbox = support.with_loadout_sandbox
        local surfaces_install = load_in(root .. "_cim_regression_forge_surfaces.lua", globals)
        surfaces_install(context)
        return {
            checks = checks, mod = mod, settings = settings, forged = function() return forged end,
            loadout = loadout, weave = weave_owner, core_env = core_env,
        }
    end

    local function run(suite, name)
        local check = suite.checks[name]
        H.truthy(check, name .. " is not registered")
        local ok, result = pcall(check)
        if not ok then return "RAISED: " .. tostring(result) end
        return result
    end

    local function managers_with(inventory)
        return {
            backend = {
                get_interface = function()
                    return { _backend_mirror = { _inventory_items = inventory } }
                end,
            },
        }
    end

    -- 1. modded_loadout_round_trip_save_then_clear --------------------------

    H.test("CIM #1656 the old all-no-op stub makes vanilla set_loadout_item raise before the capture", function()
        local old_stub = setmetatable({}, { __index = function() return function() end end })
        local ok, err = pcall(vanilla_set_loadout_item, old_stub, "rt_test_bid", CAREER, SLOT, 2)
        H.equal(ok, false, "vanilla must reject the old stub")
        H.truthy(tostring(err):find("attempt to index", 1, true), tostring(err))
    end)

    H.test("CIM #1656 the stub serves exactly what vanilla set_loadout_item reads", function()
        local fixtures = assert(loadfile(root .. "_cim_regression_fixtures.lua"))()
        local stub, writes = fixtures.loadout_interface_stub({ "a_bid" })
        H.equal(vanilla_set_loadout_item(stub, "a_bid", CAREER, SLOT, 2), true)
        H.equal(#writes, 1)
        H.deep_equal(writes[1], { career_name = CAREER, slot_name = SLOT, item_id = "a_bid", loadout_index = 2 })
        H.equal(stub._dirty, true)
        H.equal(rawget(stub, "get_all_backend_items") ~= nil, true,
            "rows must be an instance field so class hooks on get_all_backend_items are bypassed")
    end)

    H.test("CIM #1656 modded_loadout_round_trip_save_then_clear passes on the real capture", function()
        local suite = build_suite()
        local result = run(suite, "modded_loadout_round_trip_save_then_clear")
        H.equal(result, nil, tostring(result))
        -- The sandbox restored the player's store and toggle.
        H.equal(suite.settings.persist_modded_loadouts, nil)
        H.equal(next(suite.loadout.get_modded_loadout()), nil)
    end)

    H.test("CIM #1656 the round trip still fails when the capture stops clearing", function()
        local suite = build_suite()
        -- A capture that only saves (the 2026-05-23 bug) must be caught.
        local real = suite.mod._cim_is_modded_backend_id
        suite.mod._cim_is_modded_backend_id = function() return true end
        local result = run(suite, "modded_loadout_round_trip_save_then_clear")
        suite.mod._cim_is_modded_backend_id = real
        H.truthy(type(result) == "string" and result:find("STALE modded entry not cleared", 1, true),
            tostring(result))
    end)

    H.test("CIM #1656 persist_loadouts_gate_off_is_passthrough is no longer vacuous", function()
        H.equal(run(build_suite(), "persist_loadouts_gate_off_is_passthrough"), nil)
        local leaking = run(build_suite({ gate_leaks = true }), "persist_loadouts_gate_off_is_passthrough")
        H.truthy(type(leaking) == "string" and leaking:find("OFF gate leaked a capture", 1, true),
            "a leaking gate must FAIL now that vanilla accepts the stub: " .. tostring(leaking))
    end)

    -- 2. inventory_property_count_within_cap --------------------------------

    H.test("CIM #1656 inventory_property_count_within_cap follows the #86 ten-property ceiling", function()
        local three = {}
        for i = 1, 5 do
            three["bid_" .. i] = { properties = { attack_speed = 0.5, crit_chance = 0.5, block_cost = 0.5 } }
        end
        local suite = build_suite({ globals = { Managers = managers_with(three) } })
        H.equal(run(suite, "inventory_property_count_within_cap"), nil,
            "five 3-property items are #86 policy, not a trim failure")

        local over = { bid_over = { properties = {} } }
        for i = 1, 11 do over.bid_over.properties["p" .. i] = 0.5 end
        suite = build_suite({ globals = { Managers = managers_with(over) } })
        H.equal(run(suite, "inventory_property_count_within_cap"),
            "1 item(s) over the 10-property cap: bid_over(11)")

        suite = build_suite({ globals = { Managers = managers_with(nil) } })
        H.equal(run(suite, "inventory_property_count_within_cap"),
            "skip: backend_mirror._inventory_items not ready")
    end)

    H.test("CIM #1656 the check ceiling is the trimmer's and the Athanor gate's", function()
        local fixtures = assert(loadfile(root .. "_cim_regression_fixtures.lua"))()
        H.equal(fixtures.ITEM_PROPERTY_CEILING, 10)
        H.truthy(read(root .. "_cim_forge_state_owner.lua"):find("local keep_limit = 10\n", 1, true),
            "load-time trimmer keep_limit drifted from the check ceiling")
        H.truthy(read(root .. "_cim_weave_loadout_owner.lua"):find("local MAX_DISTINCT_PROPERTIES = 10\n", 1, true),
            "Athanor distinct-property gate drifted from the check ceiling")
        local offenders, total = fixtures.property_count_offenders({
            c = { properties = { 1, 2, 3 } }, a = { properties = { 1, 2, 3 } },
            b = { properties = { 1, 2, 3 } }, d = { properties = { 1 } }, e = "junk",
        }, 2, 2)
        H.deep_equal(offenders, { "a(3)", "b(3)" })
        H.equal(total, 3)
    end)

    -- 3. localization_format_safe ------------------------------------------

    local function formatter_shadow(loc)
        local values, hits = {}, { n = 0 }
        for _, entry in pairs(loc) do
            if type(entry) == "table" then
                for _, value in pairs(entry) do
                    if type(value) == "string" then values[value] = true end
                end
            end
        end
        local shadow = setmetatable({
            format = function(fmt, ...)
                if values[fmt] then hits.n = hits.n + 1 end
                return string.format(fmt, ...)
            end,
        }, { __index = string })
        return shadow, hits
    end

    H.test("CIM #1656 localization_format_safe scans and never formats a loc string", function()
        local loc = assert(loadfile(root .. "crafting_in_modded_dev_localization.lua"))()
        H.equal(loc.ranalds_importing.en, "Importing %s...")
        H.equal((pcall(string.format, loc.ranalds_importing.en)), false,
            "the bare probe rejects a legitimate placeholder")
        local shadow, hits = formatter_shadow(loc)
        local suite = build_suite({ globals = { string = shadow } })
        H.equal(run(suite, "localization_format_safe"), nil)
        H.equal(hits.n, 0, "the check called the formatter with a loc string")
    end)

    H.test("CIM #1656 the loc scanner still rejects an unescaped percent", function()
        local M = assert(loadfile(root .. "_cim_loc_format.lua"))()
        local loc = assert(loadfile(root .. "crafting_in_modded_dev_localization.lua"))()
        H.equal(M.scan(loc), nil)
        loc.cim_rt1656_probe = { en = "Saved to %APPDATA%" }
        local why = M.scan(loc)
        H.truthy(why and why:find(
            'loc key "cim_rt1656_probe" (en) has invalid format string (escape literal % as %%)', 1, true),
            tostring(why))
        H.truthy(type(M.validate("10% chance")) == "string")
        H.equal(M.validate("PAGE %d / %d"), nil)
        H.equal(M.validate("+2%% each (max +10%%)"), nil)
    end)

    H.test("CIM #1656 the cim scanner stays identical to the gut #1651 scanner", function()
        local function body(path)
            local source = read(path)
            local at = assert(source:find("\nlocal M = {}\n", 1, true), path .. " has no module body")
            return source:sub(at)
        end
        H.equal(body(root .. "_cim_loc_format.lua"), body(gut_root .. "_gut_loc_format.lua"),
            "port drifted from _gut_loc_format.lua")
        local code = read(root .. "_cim_loc_format.lua"):gsub("%-%-[^\n]*", "")
        H.equal(code:find("string.format", 1, true), nil, "no formatter call in the scanner")
    end)

    -- 4. default_property_cap_is_five_bubbles -------------------------------

    H.test("CIM #1656 one fatigue_regen bubble has no storable Adventure value", function()
        local suite = build_suite()
        H.equal(suite.weave.value_for_bubbles("weave_fatigue_regen", 1), 0,
            "6% clamps to the 10% range start (#244)")
        local low, high = suite.weave.representable_bubble_range("weave_fatigue_regen")
        H.equal(low, 2)
        H.equal(high, 5)
    end)

    H.test("CIM #1656 default_property_cap_is_five_bubbles passes on the #244 policy", function()
        local suite = build_suite()
        H.equal(run(suite, "default_property_cap_is_five_bubbles"), nil)
    end)

    H.test("CIM #1656 the scaling verdict still catches a flat or single-bubble row", function()
        local fixtures = assert(loadfile(root .. "_cim_regression_fixtures.lua"))()
        local flat = {
            value_for_bubbles = function(_, count) return count >= 5 and 1 or 0.5 end,
            bubbles_for_value = function(_, value) return value >= 1 and 5 or 4 end,
            representable_bubble_range = function() return 4, 5 end,
        }
        H.equal(fixtures.bubble_scaling_failure("k", 5, flat), nil)
        flat.bubbles_for_value = function() return 5 end
        H.truthy(fixtures.bubble_scaling_failure("k", 5, flat):find("read back as 5", 1, true))
        local short = {
            value_for_bubbles = function() return 1 end,
            bubbles_for_value = function() return 1 end,
            representable_bubble_range = function() return 1, 1 end,
        }
        H.truthy(fixtures.bubble_scaling_failure("k", 5, short):find("ends at 1 bubbles", 1, true))
        local empty = { representable_bubble_range = function() return nil end }
        H.truthy(fixtures.bubble_scaling_failure("k", 5, empty):find("no storable bubble count", 1, true))
        local not_full = {
            value_for_bubbles = function(_, count) return count / 10 end,
            bubbles_for_value = function(_, value) return math.floor(value * 10 + 0.5) end,
            representable_bubble_range = function() return 1, 5 end,
        }
        H.truthy(fixtures.bubble_scaling_failure("k", 5, not_full):find("expected 1.0 (max)", 1, true))
        local falling = {
            value_for_bubbles = function(_, count) return count == 5 and 1 or 1 - count / 10 end,
            bubbles_for_value = function(_, value)
                if value == 1 then return 5 end
                return math.floor((1 - value) * 10 + 0.5)
            end,
            representable_bubble_range = function() return 1, 5 end,
        }
        H.truthy(fixtures.bubble_scaling_failure("k", 5, falling):find("scaling broken", 1, true))
    end)

    -- 5. overview_btn_render_target ----------------------------------------

    H.test("CIM #1656 overview_btn_render_target reads the forge UI owner's exports", function()
        local suite = build_suite()
        H.equal(run(suite, "overview_btn_render_target"), nil)
        local exports = suite.mod._cim_forge_ui_owner
        H.equal(exports.overview_btn_render_field, "_top_widgets")
        exports.overview_btn_render_field = "_widgets"
        local result = run(suite, "overview_btn_render_target")
        H.truthy(type(result) == "string" and result:find('append to "_widgets"', 1, true), tostring(result))
        exports.overview_btn_render_field = nil
        H.equal(run(suite, "overview_btn_render_target"),
            "forge UI owner does not export overview_drawn_fields / overview_btn_render_field")
    end)

    H.test("CIM #1656 the entry no longer passes undeclared overview globals", function()
        local entry = read(root .. "crafting_in_modded_dev.lua")
        H.equal(entry:find("_OVERVIEW_DRAWN_FIELDS", 1, true), nil)
        H.equal(entry:find("_OVERVIEW_BTN_RENDER_FIELD", 1, true), nil)
        H.truthy(entry:find("weave_loadout = _WEAVE_LOADOUT_OWNER,", 1, true),
            "the regression context must carry the weave-loadout owner")
    end)
end
