-- Actual Dev entry spans + complete installers/full VMF; private environment.
-- Required native fixture: missing/malformed inputs fail; no ignored/external dependency.
local F = {}
local prefix = "/crafting_in_modded_dev/scripts/mods/crafting_in_modded_dev/"

local function read(path)
    local file = assert(io.open(path, "rb"))
    local source = assert(file:read("*a"))
    file:close()
    return source:gsub("\r\n", "\n")
end

local function between(source, first, last)
    local a = assert(source:find(first, 1, true), first)
    local b = assert(source:find(last, a, true), last)
    return source:sub(a, b - 1)
end

function F.installed(repo_root, options)
    options = options or {}
    local source = assert(loadfile(repo_root .. "/qa/lua/fixtures/cim_dev_apply_native_6_13.lua"))()
    local hooks, order, loads, checks, errors, settings = {}, {}, {}, {}, {}, {}
    local env = setmetatable({}, { __index = _G })
    env._G = env
    env.MODDED_REALM = options.native
    if options.native == nil then env.MODDED_REALM = true end
    env.script_data = { ["eac-untrusted"] = options.legacy == true }
    env.GameSettingsDevelopment = { read_only_backend = true }
    env.Development = { application_parameter = {} }
    env.printf, env.Localize = function() end, function(value) return value end
    env.table = setmetatable({ clear = function(t)
        for key in pairs(t) do t[key] = nil end
    end }, { __index = table })
    env.math = setmetatable({ clamp = function(value, low, high)
        return math.max(low, math.min(value, high))
    end }, { __index = math })
    env.HeroWindowItemCustomization, env.MenuInputDescriptionUI = {}, {}
    local function execute(body, name, ...)
        local chunk = assert(loadstring(body, "@" .. name))
        setfenv(chunk, env)
        return chunk(...)
    end
    local actions = execute(source.native_actions, "native/customization_actions.lua")
    execute("local definitions = ...\n" .. source.native_bind .. source.native_pressed
        .. source.native_enable .. source.native_state .. source.native_gamepad
        .. source.native_action_setter, "native/customization_apply_closure.lua",
        { generic_input_actions = actions })
    env.local_require = function(name)
        assert(name == "scripts/ui/views/hero_view/windows/definitions/hero_window_item_customization_definitions")
        return { generic_input_actions = actions }
    end
    local mod = {}
    local mods = { cim_dev = mod }
    local function get_mod(name) return mods[name] end
    env.get_mod = get_mod
    local function register(kind, class, method, callback)
        local key = class .. "." .. method
        assert(hooks[key] == nil, "duplicate hook " .. key)
        if options.fail_hook == key then error(options.failure or "hook-registration-fixture", 0) end
        hooks[key] = callback
        order[#order + 1] = kind .. ":" .. key
    end
    function mod:hook(class, method, callback) register("hook", class, method, callback) end
    function mod:hook_safe(class, method, callback) register("safe", class, method, callback) end
    function mod:command(name)
        if options.fail_command == name then error(options.failure or "command-registration-fixture", 0) end
        order[#order + 1] = "command:" .. name
    end
    function mod:get(name) return settings[name] end
    function mod:set(name, value) settings[name] = value end
    function mod:info() end
    function mod:warning() end
    function mod:echo() end
    function mod:error(...) errors[#errors + 1] = { ... } end
    local function register_check(name, fn)
        if options.fail_check == name then error(options.failure or "check-registration-fixture", 0) end
        assert(checks[name] == nil, "duplicate named check")
        checks[name] = fn
        order[#order + 1] = "check:" .. name
    end
    mod._cim_rt_register = register_check
    local shared_modules = {}
    local proto, vmf = {}, {}
    env.VMFMod = proto
    env.Script = { callstack = function() return "tracked-dev-Apply-host-callstack" end }
    local resolver = env.get_mod
    env.get_mod = function(name)
        if name == "VMF" then return vmf end
        return resolver(name)
    end
    env.xpcall = function(fn, handler, ...)
        local args = { n = select("#", ...), ... }
        return xpcall(function() return fn(unpack(args, 1, args.n)) end, handler)
    end
    local function record_loaded(name, ...)
        shared_modules[name] = ...
        if options.after_load then options.after_load(name, ..., shared_modules) end
        if name == "scripts/mods/crafting_in_modded_dev/standard_forge" and options.forge_loader then
            return options.forge_loader(...)
        end
        return ...
    end
    env.dofile = function(name)
        loads[#loads + 1] = name
        -- Existing legacy salvage layout dependency, not Apply readiness.
        if name == "scripts/mods/crafting_in_modded_dev/_cim_salvage_modded_button" then return end
        if name == "scripts/mods/crafting_in_modded_dev/illusion_swap" and options.skip_illusion then return end
        return record_loaded(name, execute(read(repo_root .. "/crafting_in_modded_dev/" .. name .. ".lua"), name .. ".lua"))
    end
    execute(source.vmf_safe_calls, "vmf/modules/core/safe_calls.lua")
    setmetatable(mod, { __index = proto })

    local item = { key = "weapon", ItemId = "weapon", skin = "skin_a",
        CustomData = {}, data = { slot_type = "melee" } }
    env.ItemMasterList = {
        skin_a = { key = "skin_a", slot_type = "weapon_skin" },
        skin_b = { key = "skin_b", slot_type = "weapon_skin" },
        skin_dlc = { key = "skin_dlc", slot_type = "weapon_skin", required_dlc = "paid" },
    }
    env.WeaponSkins = { skins = {
        skin_a = { display_name = "A" }, skin_b = { display_name = "B" },
        skin_dlc = { display_name = "DLC" },
    }, default_skins = { weapon = "skin_a" } }
    local items = { get_item_from_id = function(_, id)
        if id == "weapon-bid" then return item end
    end, get_all_fake_backend_items = function() return {} end }
    env.Managers = { backend = {
        get_interface = function(_, name) if name == "items" then return items end end,
        dirtify_interfaces = function() end,
    }, unlock = { is_dlc_unlocked = function() return false end } }

    local entry = read(repo_root .. prefix .. "crafting_in_modded_dev.lua")
    local realm = between(entry, "local RealmAuthority = mod:dofile(", "local _FORGE_PREVIEW_POLICY = mod:dofile(")
    local contracts = between(entry, "mod._cim_synthetic_item_contract = mod:dofile(",
        "-- Pure source-backed mapping from the nine vanilla CW trait categories")
    local block = between(entry, "-- Standard Keep crafting", "-- SaveWeapon mod importer.")
    local capsule = execute("local mod, _rt_register = get_mod('cim_dev'), ...\n"
        .. realm .. contracts .. block .. "\nreturn _CIM_APPLY\n", "actual-dev-entry-apply-spans.lua", register_check)

    local lookup = hooks["BackendInterfaceItemPlayfab.get_weapon_skin_from_skin_key"]
    function items:get_weapon_skin_from_skin_key(skin)
        return lookup(function() return nil, nil end, self, skin)
    end
    local set_custom_active -- Dev late guard stays entry-owned and unchanged.
    local function widget()
        return { offset = { 0, 0 }, style = { texture_id = {} }, content = { visible = false } }
    end
    local window = { _state = "item_setting", _current_recipe_name = "apply_weapon_skin",
        _item_backend_id = "weapon-bid", _material_items = {}, _illusion_widgets = {},
        _ui_scenegraph = { button_top_edge_glow = { size = {} }, craft_button = {} },
        _weapon_illusion_base_widgets_by_name = { illusions_name = { content = {} } },
        _widgets_by_name = {},
        _spawn_item_unit = function() end, _play_sound = function() end,
        _get_item = function() return item end,
        _create_material_requirement_widgets = function() return true, 100 end,
    }
    for _, name in ipairs({ "button_top_edge_left", "button_top_edge_right", "button_top_edge_glow",
            "experience_bar", "experience_bar_edge", "craft_button" }) do
        window._widgets_by_name[name] = widget()
    end
    window._widgets_by_name.craft_button.content.button_hotspot = { disable_button = true }
    window._menu_input_description = { generic_actions = actions.default,
        current_console_selection_data = {}, set_input_description = function(self, data)
            assert(data == self.current_console_selection_data)
        end, change_generic_actions = env.MenuInputDescriptionUI.change_generic_actions }
    for _, skin in ipairs({ "skin_a", "skin_b", "skin_dlc" }) do
        window._illusion_widgets[#window._illusion_widgets + 1] = {
            content = { skin_key = skin, locked = true, button_hotspot = {} },
        }
    end
    for _, method in ipairs({ "_enable_craft_button", "_on_illusion_index_pressed", "_update_state_craft_button" }) do
        local native, hook = env.HeroWindowItemCustomization[method], hooks["HeroWindowItemCustomization." .. method]
        window[method] = function(self, ...)
            if hook then return hook(native, self, ...) end
            return native(self, ...)
        end
    end
    return { mod = mod, env = env, mods = mods, window = window, item = item,
        hooks = hooks, order = order, loads = loads, checks = checks, errors = errors,
        actions = actions, settings = settings, source = source, entry = entry,
        shared_modules = shared_modules, execute = execute, capsule = capsule,
        gamepad = env.HeroWindowItemCustomization._update_skin_gamepad_input,
        set_custom_active = set_custom_active }
end

return F
