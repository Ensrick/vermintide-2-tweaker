-- qa/integration/stubs.lua (WP-T-03): the engine surface that vanilla data tables need under plain Lua 5.1, then the
-- real vanilla preamble in engine boot order.
--
-- The exact set the 2026-11-13 B2 prototype (stubs3.lua) found sufficient, listed in docs/program/wp/T.md WP-T-03.
-- Every stub is declared here, so the list is the measured cost. Values that data files compute with (platform
-- constants, Application.can_get, Script.new_map, the math shims) return real values; everything else is an inert
-- recording stub from loader.lua (make_stub), whose values suites must never assert on (run.lua's ctx.real).
-- Called as dofile(...)(L, here) with L from loader.lua and here the folder of this file.
return function(L, here)
    local make_stub = L.make_stub
    local STUBS = {}
    local function engine(name, impl)
        STUBS[#STUBS + 1] = name
        local stub = make_stub(name)
        if impl then for k, v in pairs(impl) do rawset(stub, k, v) end end
        rawset(_G, name, stub)
        return stub
    end
    local function const(name, value) STUBS[#STUBS + 1] = name; rawset(_G, name, value) end

    -- 1. platform and build constants (normally set by scripts/boot_init.lua from Application.*)
    const("PLATFORM", "win32"); const("BUILD", "release")
    const("IS_WINDOWS", true); const("IS_CONSOLE", false); const("IS_LINUX", false); const("IS_XB1", false); const("IS_PS4", false)
    const("IS_NOT_CONSOLE", true); const("IS_NOT_WINDOWS", false); const("IS_NOT_LINUX", true); const("IS_NOT_XB1", true); const("IS_NOT_PS4", true)
    const("HAS_STEAM", true); const("DEDICATED_SERVER", false); const("LEVEL_EDITOR_TEST", false); const("LAUNCH_MODE", "game")
    const("script_data", {})
    const("GLOBAL_MUSIC_WORLD", false)
    const("Development", {})

    -- 2. engine C API namespaces: inert, with the few functions whose return values data files use
    engine("Application", {
        platform = function() return "win32" end,
        build = function() return "release" end,
        argv = function() return end,
        user_setting = function() return nil end,
        is_dedicated_server = function() return false end,
        settings = function() return {} end,
        bundled = function() return true end,
        -- resource probe: a Lua resource exists when the decompile has the file
        can_get = function(kind, name)
            if kind == "lua" and type(name) == "string" then
                local f = io.open(L.root .. "/" .. name .. ".lua", "rb")
                if f then f:close(); return true end
                return false
            end
            return true
        end,
        make_hash = function() return "hash" end,
        time_since_launch = function() return 0 end,
        sysinfo = function() return "" end,
        process_id = function() return 1 end,
        guid = function() return "00000000-0000-0000-0000-000000000000" end,
        set_user_setting = function() end,
        save_user_settings = function() end,
    })
    engine("Script", {
        new_map = function() return {} end, new_array = function() return {} end,
        temp_count = function() return 0, 0, 0 end, set_temp_count = function() end, callstack = function() return "" end,
        configure_garbage_collection = function() end,
    })
    engine("Math", {
        random = math.random,
        random_range = function(a) return a end,
        -- the engine's seeded generator is C; this stand-in is NOT the engine sequence
        next_random = function(seed, lo, hi)
            seed = (1103515245 * (seed or 0) + 12345) % 2147483648
            local unit = seed / 2147483648
            if lo and hi then return seed, lo + math.floor(unit * (hi - lo + 1)) end
            if lo then return seed, 1 + math.floor(unit * lo) end
            return seed, unit
        end,
    })
    engine("Crashify", { print_exception = function() end })
    for _, name in ipairs({
        "Managers", "Wwise", "WwiseWorld", "Unit", "World", "Level", "Actor", "Mover", "Camera", "Network", "GameSession",
        "LanClient", "Steam", "SteamHelper", "Gui", "Material", "Mesh", "Window", "Keyboard", "Mouse", "Pad1", "PhysicsWorld",
        "GwNavQueries", "GwNavWorld", "EngineOptimized", "EngineOptimizedExtensions", "Profiler", "Renderer",
        "ShadingEnvironment", "LineObject", "Light", "Localizer", "NetworkConstants", "ResourcePackage", "Viewport",
        "Clipboard", "Stats", "Achievement", "Friends",
        -- manager-layer globals that data files read at file scope; their real files pull the backend stack
        "BackendUtils", "Presence", "Benchmark", "Vector3Aux", "Matrix4x4", "Rectangle2D",
    }) do engine(name) end

    -- 3. LuaJIT's bit library (the engine runs LuaJIT; PUC Lua 5.1 has none)
    do
        local function tobit(x) x = x % 4294967296; if x >= 2147483648 then x = x - 4294967296 end; return x end
        local function bitop(a, b, f)
            a = a % 4294967296; b = b % 4294967296
            local r, p = 0, 1
            for _ = 1, 32 do
                local x, y = a % 2, b % 2
                if f(x, y) then r = r + p end
                a = (a - x) / 2; b = (b - y) / 2; p = p * 2
            end
            return tobit(r)
        end
        local function fold(f) return function(a, b, ...)
            local r = bitop(a, b or 0, f)
            for i = 1, select("#", ...) do r = bitop(r, (select(i, ...)), f) end
            return r
        end end
        const("bit", {
            tobit = tobit,
            band = fold(function(x, y) return x == 1 and y == 1 end),
            bor = fold(function(x, y) return x == 1 or y == 1 end),
            bxor = fold(function(x, y) return x ~= y end),
            bnot = function(a) return tobit(4294967295 - (a % 4294967296)) end,
            lshift = function(a, n) return tobit((a % 4294967296) * 2 ^ n) end,
            rshift = function(a, n) return tobit(math.floor((a % 4294967296) / 2 ^ n)) end,
        })
    end

    -- 4. value types: functional Vector3/Quaternion (data files do vector math at load time), plain constructors
    do
        local shim = assert(loadfile(here .. "/mathshim.lua"))()
        const("Vector3", shim.Vector3); const("Quaternion", shim.Quaternion)
        const("Vector3Box", shim.Vector3Box); const("QuaternionBox", shim.QuaternionBox)
        const("Vector2", function(x, y) return { x, y } end)
        const("Vector4", function(x, y, z, w) return { x, y, z, w } end)
        const("Matrix4x4Box", function(...) return { unbox = function() return {} end, store = function() end, ... } end)
        const("Color", function(...) return { ... } end)
    end
    -- class tables whose keys feed two Versus-only lookups (carousel_common_settings.lua:121-124); their real files pull
    -- scripts/ui/ui_renderer.lua, which uses LuaJIT goto (unparseable in PUC Lua 5.1)
    const("GameModeInnVs", {}); const("GameModeVersus", {})
    const("Localize", function(key) return "<" .. tostring(key) .. ">" end)
    for _, name in ipairs({ "printf", "print_warning", "print_error", "cprint", "cprintf", "visual_assert" }) do const(name, function() end) end

    L.STUBS = STUBS

    -- 5. the real vanilla preamble, in engine boot order (scripts/boot.lua:250-262, :387, :516)
    local preamble_failures = {}
    local function real(name)
        local ok, err = pcall(L.load_module, name, false)
        if not ok then preamble_failures[#preamble_failures + 1] = name .. ": " .. tostring(err) end
        return ok
    end
    real("foundation/scripts/util/user_setting")
    if Development.init_user_settings then pcall(Development.init_user_settings) end
    real("foundation/scripts/util/application_parameter")
    if Development.init_application_parameters then pcall(Development.init_application_parameters, {}, true) end
    real("foundation/scripts/util/development_parameter")
    if Development.init_parameters then pcall(Development.init_parameters) end
    for _, name in ipairs({
        "error", "patches", "class", "callback", "misc_util", "table", "math", "string", "local_require", "stack",
        "circular_queue", "grow_queue", "vector3", "quaternion", "frame_table", "path", "rectangle", "state_machine",
        "script_unit",
    }) do real("foundation/scripts/util/" .. name) end
    real("scripts/settings/dlc_settings")
    real("scripts/helpers/dlc_utils")
    do -- scripts/boot.lua:387: every DLC's additional settings populate DLCSettings lists
        local ok, err = pcall(function() return DLCUtils.require_list("additional_settings") end)
        if not ok then preamble_failures[#preamble_failures + 1] = "DLCUtils.require_list(additional_settings): " .. tostring(err) end
    end
    for _, name in ipairs({ "scripts/utils/colors", "scripts/utils/global_utils", "scripts/utils/loaded_dice",
        "scripts/unit_extensions/human/ai_player_unit/ai_utils" }) do real(name) end
    L.preamble_failures = preamble_failures
    L.preamble_files = #L.order
end
