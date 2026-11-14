-- Selective official CIM promotion: run the established semantic oracles
-- against the OFFICIAL production namespace, not against the Dev donor.
-- An optional CIM_OFFICIAL_OVERLAY path points at changed-only overlay files.
-- Every missing overlay production file resolves to the untouched official
-- tree, never Dev. This lets the same suite run before and after application.
return function(H, repo_root)
    local overlay = os.getenv("CIM_OFFICIAL_OVERLAY")
    local official = "/crafting_in_modded/scripts/mods/crafting_in_modded/"
    local donor = "/crafting_in_modded_dev/scripts/mods/crafting_in_modded_dev/"
    local raw_loadfile, raw_dofile, raw_open = loadfile, dofile, io.open
    local observed = {}

    local function map(path)
        if type(path) ~= "string" then return path end
        path = path:gsub("\\", "/")
        local at = path:find(donor, 1, true)
        if at then path = path:sub(1, at - 1) .. official .. path:sub(at + #donor) end
        -- The reusable installed-Forge fixture retains its historical filename.
        path = path:gsub("/fixtures/cim_apply_", "/fixtures/cim_dev_apply_")
        local changed_fixture = repo_root .. "/qa/lua/tests/_cim_temper_fixture.lua"
        if overlay and (path:sub(1, #repo_root + #official) == repo_root .. official
                or path == changed_fixture) then
            local candidate = overlay .. path:sub(#repo_root + 1)
            local file = raw_open(candidate, "rb")
            if file then file:close(); return candidate end
        end
        return path
    end

    local function load_selected(path)
        local physical = map(path)
        if physical:find("/qa/lua/", 1, true) then
            local file, err = raw_open(physical, "rb")
            if not file then return nil, err end
            local source = file:read("*a"); file:close()
            -- Only adapt stream identity in fixture/oracle code. Production
            -- bytes are NEVER rewritten by this test loader.
            source = source:gsub("crafting_in_modded_dev", "crafting_in_modded")
                :gsub("cim_dev", "cim")
            return loadstring(source, "@official-oracle:" .. physical)
        end
        if physical:find(official, 1, true) then observed[physical] = true end
        return raw_loadfile(physical)
    end

    local function with_production(body)
        local saved_loadfile, saved_dofile, saved_open = loadfile, dofile, io.open
        loadfile = load_selected
        dofile = function(path) return assert(load_selected(path))() end
        io.open = function(path, mode) return raw_open(map(path), mode) end
        local result = { pcall(body) }
        loadfile, dofile, io.open = saved_loadfile, saved_dofile, saved_open
        if not result[1] then error(result[2], 0) end
        return unpack(result, 2)
    end

    local proxy = setmetatable({}, { __index = H })
    proxy.test = function(name, body)
        H.test("Official CIM: " .. name, function() return with_production(body) end)
    end
    proxy.test_if = function(condition, name, body, reason)
        H.test_if(condition, "Official CIM: " .. name,
            function() return with_production(body) end, reason)
    end

    -- Unmodified assertion bodies exercise package acquisition, exact identity,
    -- rollback, favorite/equipped refusal, adversarial mirror ownership, draft
    -- isolation, installed callbacks, native realm and private Apply failures.
    for _, name in ipairs({
        "test_cim_cw_trait_residency",
        "test_cim_trait_slot_policy",
        "test_cim_bulk_cleanup",
        "test_cim_synthetic_item_contract",
        "test_cim_temper_transaction",
        "test_cim_temper_runtime",
        "test_cim_direct_craft",
        "test_cim_forge_preview_owner",
        "test_cim_forge_picker_owner",
        "test_cim_mission_forge_widget_safety",
        "test_cim_tab_preview",
        "test_cim_dev_forge_installation",
        "test_cim_forge_realm_diagnostic",
    }) do
        with_production(function()
            assert(load_selected(repo_root .. "/qa/lua/tests/" .. name .. ".lua"))()(proxy, repo_root)
        end)
    end

    -- Execute the exact public registrar and its real localization loader.
    -- This tests the instrument itself: a missing dependency cannot report PASS.
    local function base_power_check(spec)
        local checks, seen = {}, { loads = 0, settings = 0, powers = 0 }
        local mod = {}
        function mod:set() error("Base Power regression check wrote settings") end
        if not spec.missing_loader then
            function mod:dofile(path)
                seen.loads = seen.loads + 1
                H.equal(path, "scripts/mods/crafting_in_modded/crafting_in_modded_localization")
                if spec.load_error then error("localization unavailable") end
                if spec.localization ~= nil then return spec.localization end
                return assert(load_selected(repo_root .. official
                    .. "crafting_in_modded_localization.lua"))()
            end
        end
        if not spec.missing_setting then
            function mod:get(key)
                seen.settings = seen.settings + 1
                H.equal(key, "base_power_level")
                if spec.setting_error then error("setting unavailable") end
                return spec.setting
            end
        end
        if not spec.missing_power then
            mod._cim_base_power = function()
                seen.powers = seen.powers + 1
                if spec.power_error then error("power unavailable") end
                return spec.power
            end
        end
        local install = assert(load_selected(repo_root .. official .. "_cim_regression_checks.lua"))()
        install({ mod = mod, rt_register = function(name, fn)
            H.equal(checks[name], nil, "duplicate runtime check")
            checks[name] = fn
        end })
        return assert(checks.issue1530_base_power_step_wording,
            "public issue1530 registration missing"), seen
    end

    for _, values in ipairs({
        { name = "off-grid integer", setting = 324, power = 324 },
        { name = "off-grid fraction", setting = 324.5, power = 324.5 },
        { name = "low clamp", setting = -1, power = 0 },
        { name = "high clamp", setting = 951, power = 950 },
        { name = "nonnumeric default", setting = false, power = 300 },
        { name = "missing setting default", power = 300 },
    }) do
        local spec = values
        H.test("Official CIM issue1530 actual check accepts " .. spec.name, function()
            with_production(function()
                local check, seen = base_power_check(spec)
                H.equal(check(), nil)
                H.equal(seen.loads, 1); H.equal(seen.settings, 1); H.equal(seen.powers, 1)
                H.equal(check(), nil, "repeat should remain read-only")
                H.equal(seen.loads, 2)
            end)
        end)
    end
    for _, values in ipairs({
        { name = "missing loader", missing_loader = true },
        { name = "throwing loader", load_error = true },
        { name = "non-table localization", localization = false },
        { name = "missing description", localization = {} },
        { name = "stale tooltip", localization = {
            base_power_level_description = { en = "Power in steps of 50" },
        } },
        { name = "mixed stale tooltip", localization = {
            base_power_level_description = { en = "steps of 25 in Mod Tweaker; steps of 50" },
        } },
        { name = "missing setting reader", missing_setting = true },
        { name = "throwing setting reader", setting_error = true },
        { name = "missing craft reader", missing_power = true },
        { name = "throwing craft reader", power_error = true },
        { name = "missing craft result", setting = 300 },
        { name = "nonnumeric craft result", setting = 300, power = "300" },
        { name = "NaN craft result", setting = 300, power = 0 / 0 },
        { name = "infinite craft result", setting = 300, power = math.huge },
        { name = "out-of-range craft result", setting = 300, power = 951 },
        { name = "quantized integer", setting = 324, power = 325 },
        { name = "quantized fraction", setting = 324.5, power = 325 },
        { name = "incorrect clamp", setting = 951, power = 300 },
        { name = "incorrect default", setting = false, power = 0 },
    }) do
        local spec = values
        H.test("Official CIM issue1530 actual check refuses " .. spec.name, function()
            with_production(function()
                local check = base_power_check(spec)
                local result = check()
                H.equal(type(result), "string", "missing/broken proof reported PASS")
                H.truthy(#result > 0)
            end)
        end)
    end

    H.test("Official CIM production isolation and exclusions", function()
        H.truthy(next(observed), "no official production file was loaded")
        for path in pairs(observed) do
            H.equal(path:find(donor, 1, true), nil, "Dev runtime loaded")
        end
        local file = assert(raw_open(map(repo_root .. official .. "crafting_in_modded.lua"), "rb"))
        local source = file:read("*a"); file:close()
        H.equal(source:find("_cim_ranalds", 1, true), nil)
        H.equal(source:find("[cim:1654]", 1, true), nil)
        H.equal(source:find("[cim:1694]", 1, true), nil)
        H.equal(source:find("_note_restore_result", 1, true), nil)
        H.truthy(source:find("_CIM_APPLY.install_forge_loaded", 1, true))
        H.truthy(source:find("_CIM_APPLY.install_loaded", 1, true))
    end)

    H.test("Official CIM sender/receiver keep wire safe and clear explicit false", function()
        with_production(function()
            local saved = { LoadoutUtils = LoadoutUtils, NetworkLookup = NetworkLookup }
            local ok, err = pcall(function()
                local hooks, rpc, packets = {}, nil, {}
                local managers = { player = { _player_loadouts = {} } }
                local mod = { _cim246_tab_preview_core = assert(load_selected(
                    repo_root .. official .. "_cim_tab_preview_core.lua"))() }
                function mod:set() end
                function mod:get() return false end
                function mod:info() end
                function mod:hook(class, method, fn)
                    local key = type(class) == "table" and "sender" or class .. "." .. method
                    H.equal(hooks[key], nil, "duplicate wire hook")
                    hooks[key] = fn
                end
                function mod:network_register(name, fn) H.equal(name, "cim_modded_slot"); rpc = fn end
                function mod:network_send(...) packets[#packets + 1] = { ... } end
                LoadoutUtils = { sync_loadout_slot = function() end }
                NetworkLookup = { item_names = { [1] = "sword" }, equipment_slots = { [1] = "slot_melee" } }
                assert(load_selected(repo_root .. official .. "_cim_loadout_wire_owner.lua"))()({
                    mod = mod, rpc_schema = 1, dbg_alert = function() end,
                    print_line = function() end, get_managers = function() return managers end,
                })
                local player = { network_id = function() return "peer" end,
                    local_player_id = function() return 1 end }
                local item = { rarity = "modded", key = "sword" }
                local saw
                hooks.sender(function(_, _, wire) saw = wire.rarity; error("encoder failure") end,
                    player, "slot_melee", item)
                H.equal(saw, "unique"); H.equal(item.rarity, "modded")
                H.equal(mod._cim_modded_slot_state["peer:1"].slot_melee, true)
                hooks.sender(function(_, _, wire) H.equal(wire.rarity, "common") end,
                    player, "slot_melee", { rarity = "common", key = "sword" })
                H.equal(mod._cim_modded_slot_state["peer:1"].slot_melee, false)
                H.equal(packets[1][1], "cim_modded_slot")
                H.equal(#packets[1], 7, "unexpected resource/wire payload field")
                local decode_count = 0
                local function decode(self, _, peer, local_id, slot_id)
                    decode_count = decode_count + 1
                    self._player_loadouts[peer .. ":" .. local_id] = {
                        [NetworkLookup.equipment_slots[slot_id]] = { rarity = "unique" },
                    }
                end
                local receiver = hooks["PlayerManager.rpc_sync_loadout_slot"]
                receiver(decode, managers.player, "channel", "peer", 1, 1, 999, 1, 300, {}, {}, {})
                H.equal(decode_count, 0, "unknown identity reached decoder")
                rpc("transport", 99, "peer", 1, "slot_melee", true)
                H.equal(mod._cim_modded_slot_state["peer:1"].slot_melee, false)
                rpc("transport", 1, "peer", 1, "slot_melee", true)
                receiver(decode, managers.player, "channel", "peer", 1, 1, 1, 1, 300, {}, {}, {})
                H.equal(managers.player._player_loadouts["peer:1"].slot_melee.rarity, "modded")
                rpc("transport", 1, "peer", 1, "slot_melee", false)
                H.equal(managers.player._player_loadouts["peer:1"].slot_melee.rarity, "unique")
                H.equal(decode_count, 1)
            end)
            LoadoutUtils, NetworkLookup = saved.LoadoutUtils, saved.NetworkLookup
            if not ok then error(err, 0) end
        end)
    end)

    local function installed_forge(options)
        return assert(load_selected(repo_root .. "/qa/lua/fixtures/cim_dev_apply_installed.lua"))()
            .installed(repo_root, options)
    end

    local function no_new_apply(f)
        H.equal(f.mod._cim_illusion_swap_provider, nil)
        H.equal(f.mod._cim_illusion_apply_presentation_owner, nil)
        H.equal(f.hooks["HeroWindowItemCustomization._enable_craft_button"], nil)
        H.equal(f.hooks["HeroWindowItemCustomization._on_illusion_index_pressed"], nil)
        H.equal(f.checks.issue1465_illusion_apply_presentation, nil)
        local last = f.errors[#f.errors]
        H.equal(last[1], "Failed to load illusion_swap: %s")
        H.truthy(last[2]:find("required Forge installer incomplete", 1, true))
        H.equal(f.env.GameSettingsDevelopment.read_only_backend, true)
    end

    H.test("Official CIM extracted presentation preserves ordered once handoff and live synth", function()
        with_production(function()
            local f = installed_forge()
            H.equal(#f.errors, 0)
            local prefix = "scripts/mods/crafting_in_modded/"
            local count, at = 0, {}
            for i, name in ipairs(f.loads) do
                if name == prefix .. "_cim_standard_forge_presentation" then count = count + 1 end
                at[name] = i
            end
            H.equal(count, 1)
            H.truthy(at[prefix .. "standard_forge"] < at[prefix .. "_cim_standard_forge_presentation"])
            H.truthy(at[prefix .. "_cim_standard_forge_presentation"] < at[prefix .. "illusion_swap"])
            local order = {}; for i, name in ipairs(f.order) do order[name] = i end
            H.truthy(order["hook:HeroWindowItemCustomization._update_state_craft_button"]
                < order["hook:HeroWindowItemCustomization._update_property_option"])
            H.truthy(order["safe:HeroWindowCraftingInventoryConsole._update_crafting_material_panel"]
                < order["hook:BackendInterfaceCraftingPlayfab._get_valid_recipe"])

            local events = {}
            f.mod._cim_rebuild_template_cache = function() events[#events + 1] = "rebuild" end
            f.mod._cim_autodump_forge_open = function(class, window)
                H.equal(class, "HeroWindowCraftingConsole"); H.equal(window.tag, "window")
                events[#events + 1] = "dump"
            end
            local function pack(...) return { n = select("#", ...), ... } end
            local result = pack(f.hooks["HeroWindowCraftingConsole.on_enter"](function(self, marker)
                H.equal(marker, "argument"); H.equal(self.tag, "window")
                H.equal(f.mod._cim_standard_forge_active, true)
                events[#events + 1] = "native"
                return nil, "tail", nil
            end, { tag = "window" }, "argument"))
            H.equal(table.concat(events, ","), "rebuild,native,dump")
            H.equal(result.n, 3); H.equal(result[1], nil); H.equal(result[2], "tail"); H.equal(result[3], nil)

            f.env.Managers.backend.get_interface = function(_, name)
                H.equal(name, "items")
                return { get_item_masterlist_data = function(_, bid)
                    H.equal(bid, "charm-template"); return { slot_type = "ring" }
                end }
            end
            local page = { _craft_items = { "charm-template" },
                _widgets_by_name = { craft_button = { content = { button_text = "old" } },
                    material_text_1 = { content = { visible = true } },
                    material_icon_1 = { content = { visible = true } } },
                parent = { _widgets_by_name = { title_text = { content = {} } } },
                _set_craft_button_disabled = function(self, disabled) self.disabled = disabled end }
            f.hooks["CraftPageCraftItemConsole.setup_recipe_requirements"](page)
            H.equal(page._recipe_name, "craft_charm", "owner must read synth after late construction")
            H.equal(page._has_all_requirements, true); H.equal(page.disabled, false)
            H.equal(page._widgets_by_name.craft_button.content.title_text, "CRAFT CHARM")
            H.equal(page._widgets_by_name.craft_button.content.button_text, "CRAFT CHARM")
            H.equal(page.parent._widgets_by_name.title_text.content.text, "CRAFT CHARM")
            H.equal(page._widgets_by_name.material_text_1.content.visible, false)
            H.equal(page._widgets_by_name.material_icon_1.content.visible, false)
            local released
            f.mod._cim_illusion_apply_presentation_owner = { release = function(window, reason)
                released = window; H.equal(reason, "window-exit")
            end }
            f.hooks["HeroWindowItemCustomization.on_exit"](page)
            H.equal(released, page); H.equal(f.mod._cim_standard_forge_active, false)
        end)
    end)

    H.test("Official CIM extracted presentation keeps bounded widgets and guarded console feedback", function()
        with_production(function()
            local f = installed_forge({ after_load = function(name, module)
                if name == "scripts/mods/crafting_in_modded/_cim_standard_forge_presentation" then
                    local env = getfenv(module)
                    env.CraftPageSalvageConsole = {}
                    env.HeroWindowCraftingInventory = {}
                end
            end })
            H.equal(#f.errors, 0)
            f.env.WeaponProperties = { properties = { one = {}, two = {}, three = {} } }
            f.env.UIUtils = { get_property_description = function(key) return key .. " label" end }
            local content = { button_hotspot_1 = { disable_button = true },
                button_hotspot_2 = { disable_button = true } }
            local window = { _get_item = function() return { properties = { one = 1, two = 2, three = 3 } } end,
                _widgets_by_name = { item_properties = { content = content } } }
            f.hooks["HeroWindowItemCustomization._update_property_option"](function() error("native not expected") end, window)
            H.equal(content.button_hotspot_1.disable_button, false)
            H.equal(content.button_hotspot_2.disable_button, false)
            H.equal(content.button_hotspot_3, nil)
            H.equal(content.option_text_3, nil)
            H.truthy(content.option_text_1); H.truthy(content.option_text_2)
            local sounds = 0
            local page = { _presenting_rewards = true, _play_sound = function(_, name)
                H.equal(name, "play_gui_craft_forge_button_completed"); sounds = sounds + 1
            end }
            local feedback = f.hooks["CraftPageSalvageConsole._update_craft_items"]
            H.equal(type(feedback), "function")
            feedback(page); feedback(page); H.equal(sounds, 1)
            page._presenting_rewards = false; feedback(page)
            page._presenting_rewards = true; feedback(page); H.equal(sounds, 2)
            page._play_sound = function() error("audio unavailable") end
            page._presenting_rewards = false; feedback(page)
            page._presenting_rewards = true; feedback(page)
            local inventory = { _widgets_by_name = { material_text_1 = { content = { visible = true } } } }
            f.hooks["HeroWindowCraftingInventory._update_crafting_material_panel"](inventory)
            H.equal(inventory._widgets_by_name.material_text_1.content.visible, false)
            f.hooks["HeroWindowCraftingInventoryConsole._update_crafting_material_panel"]({})
        end)
    end)

    H.test("Official CIM presentation missing false empty and throwing handoffs deny Apply", function()
        with_production(function()
            for _, mode in ipairs({ "nil", "false", "empty", "false-result", "throw" }) do
                local failure = {}
                local f = installed_forge({ after_load = function(name, module)
                    if name == "scripts/mods/crafting_in_modded/_cim_illusion_apply_presentation" then
                        local bind = module.bind
                        module.bind = function(mod, ...)
                            local capsule = bind(mod, ...)
                            local raw = mod.dofile
                            mod.dofile = function(self, path, ...)
                                if path == "scripts/mods/crafting_in_modded/_cim_standard_forge_presentation" then
                                    if mode == "nil" then return nil end
                                    if mode == "false" then return false end
                                    if mode == "empty" then return function() end end
                                    if mode == "false-result" then return function() return false end end
                                    return function() error(failure, 0) end
                                end
                                return raw(self, path, ...)
                            end
                            return capsule
                        end
                    end
                end })
                no_new_apply(f)
                H.equal(f.errors[1][1], "Failed to load standard_forge: %s")
                if mode == "throw" then H.equal(f.errors[1][2], tostring(failure)) end
                H.equal(f.hooks["BackendInterfaceCraftingPlayfab._get_valid_recipe"], nil)
            end
        end)
    end)

    H.test("Official CIM presentation actual early middle and late hook faults keep Forge incomplete", function()
        with_production(function()
            for _, hook in ipairs({
                "HeroWindowItemCustomization._update_property_option",
                "CraftPageCraftItem.setup_recipe_requirements",
                "HeroWindowCraftingInventoryConsole._update_crafting_material_panel",
            }) do
                local failure = {}
                local f = installed_forge({ fail_hook = hook, failure = failure })
                H.equal(f.hooks[hook], nil)
                H.equal(f.errors[1][1], "Failed to load standard_forge: %s")
                H.equal(f.errors[1][2], tostring(failure))
                no_new_apply(f)
                H.equal(f.hooks["BackendInterfaceCraftingPlayfab._get_valid_recipe"], nil)
            end
        end)
    end)


    local function bootstrap_fixture(printer)
        local f = { commands = {}, raw = {}, info = {}, echo = {} }
        local env = setmetatable({
            require = function(name)
                H.equal(name, "scripts/mods/crafting_in_modded/crafting_in_modded_data")
                return {} -- no settings yields the exact existing "nosettings" fingerprint
            end,
            printf = function() error("bootstrap bypassed injected raw printer", 0) end,
        }, { __index = _G })
        env._G = env
        local function module(name)
            local chunk = assert(load_selected(repo_root .. official .. name .. ".lua"))
            setfenv(chunk, env)
            return chunk()
        end
        local mod = { warning = function() end, debug = function() end }
        function mod:get() return false end
        function mod:info(...) f.info[#f.info + 1] = { ... } end
        function mod:echo(...) f.echo[#f.echo + 1] = { ... } end
        function mod:command(name, _, callback)
            H.equal(f.commands[name], nil, "duplicate bootstrap command")
            f.commands[name] = callback
        end
        function mod:dofile(path)
            if path == "scripts/mods/crafting_in_modded/_lib_debug" then return module("_lib_debug") end
            H.equal(path, "scripts/mods/crafting_in_modded/crafting_in_modded_data")
            return { options = {} }
        end
        local install = module("_cim_bootstrap_runtime")
        f.install = function()
            f.owner = install({ mod = mod, version = "0.8.148",
                print_line = printer or function(fmt, ...)
                    f.raw[#f.raw + 1] = string.format(fmt, ...)
                end })
            return f.owner
        end
        f.mod = mod
        return f
    end

    H.test("Official CIM actual bootstrap LOAD uses injected raw printer with info and echo suppressed", function()
        with_production(function()
            local f = bootstrap_fixture()
            local owner = f.install()
            H.equal(type(owner.rt_register), "function")
            H.equal(f.raw[1], "[cim:LOAD] v0.8.148 enabled fp=nosettings OK")
            H.equal(f.raw[2], "[cim-settings] BEGIN phase=load v=0.8.148 count=0")
            H.equal(f.raw[3], "[cim-settings] END phase=load")
            local load_count = 0
            for _, line in ipairs(f.raw) do
                if line:find("[cim:LOAD]", 1, true) then load_count = load_count + 1 end
            end
            H.equal(load_count, 1)
            for _, call in ipairs(f.info) do
                H.equal(call[1]:find("[cim:LOAD]", 1, true), nil, "LOAD still depends on VMF info")
            end
            H.equal(#f.echo, 1, "no extra chat notification")
            H.equal(f.echo[1][1], "[cim] v0.8.148 loaded", "existing version echo changed")
            H.equal(type(f.commands.cim_dump_settings), "function")
            H.equal(type(f.commands.cim_regression_test), "function")
            f.commands.cim_dump_settings()
            H.equal(f.raw[4], "[cim-settings] BEGIN phase=command v=0.8.148 count=0")
            H.equal(f.raw[5], "[cim-settings] END phase=command")
            owner.rt_register("ordinary-pass", function() end)
            f.commands.cim_regression_test()
            for index = 2, #f.raw do
                H.equal(f.raw[index]:find("[cim:LOAD]", 1, true), nil,
                    "callback repeated permanent LOAD banner")
            end
        end)
    end)

    H.test("Official CIM actual bootstrap raw printer fault preserves error and cannot complete owner", function()
        with_production(function()
            local token, calls = {}, 0
            local f = bootstrap_fixture(function(fmt, ...)
                calls = calls + 1
                H.equal(string.format(fmt, ...), "[cim:LOAD] v0.8.148 enabled fp=nosettings OK")
                error(token, 0)
            end)
            local ok, err = pcall(f.install)
            H.equal(ok, false); H.equal(err, token)
            H.equal(calls, 1); H.equal(f.owner, nil)
            H.equal(next(f.commands), nil)
            H.equal(#f.echo, 0, "failed bootstrap added chat")
            H.equal(f.mod._cim_illusion_swap_provider, nil)
            H.equal(f.mod._cim_illusion_apply_presentation_owner, nil)
        end)
    end)

end
