-- Stub set 1: the minimal engine surface found (iteratively) to be needed to load
-- vanilla data tables under plain PUC Lua 5.1.5. Every stub is listed explicitly so
-- the count is the measured cost. Real foundation/util Lua is loaded, not stubbed.
local P, load_module, make_stub = ...
local STUBS = {}
local function engine(name, impl)
    STUBS[#STUBS + 1] = name
    local stub = make_stub(name)
    if impl then for k, v in pairs(impl) do rawset(stub, k, v) end end
    rawset(_G, name, stub)
    return stub
end
local function const(name, value) STUBS[#STUBS + 1] = name; rawset(_G, name, value) end

-- 1. Platform/build constants normally set by scripts/boot_init.lua from Application.*
const("PLATFORM", "win32"); const("BUILD", "release")
const("IS_WINDOWS", true); const("IS_CONSOLE", false); const("IS_LINUX", false); const("IS_XB1", false); const("IS_PS4", false)
const("IS_NOT_CONSOLE", true); const("IS_NOT_WINDOWS", false); const("IS_NOT_LINUX", true); const("IS_NOT_XB1", true); const("IS_NOT_PS4", true)
const("HAS_STEAM", true); const("DEDICATED_SERVER", false); const("LEVEL_EDITOR_TEST", false); const("LAUNCH_MODE", "game")
const("script_data", {})
const("GLOBAL_MUSIC_WORLD", false)

-- 2. Engine C API namespaces: inert objects with a few value-returning functions.
engine("Application", {
    platform = function() return "win32" end,
    build = function() return "release" end,
    argv = function() return end,
    user_setting = function() return nil end,
    is_dedicated_server = function() return false end,
    settings = function() return {} end,
    bundled = function() return true end,
    can_get = function() return true end,
    make_hash = function(...) return "hash" end,
    time_since_launch = function() return 0 end,
    sysinfo = function() return "" end,
    process_id = function() return 1 end,
    guid = function() return "00000000-0000-0000-0000-000000000000" end,
    set_user_setting = function() end,
    save_user_settings = function() end,
})
engine("Managers")
engine("Math", { random = math.random, random_range = function(a, b) return a end })
engine("Wwise"); engine("WwiseWorld")
engine("Unit"); engine("World"); engine("Level"); engine("Actor"); engine("Mover"); engine("Camera")
engine("Network"); engine("GameSession"); engine("LanClient"); engine("Steam"); engine("SteamHelper")
engine("Script", { new_map = function() return {} end, new_array = function() return {} end,
    temp_count = function() return 0, 0, 0 end, set_temp_count = function() end, callstack = function() return "" end,
    configure_garbage_collection = function() end }); engine("Gui"); engine("Material"); engine("Mesh"); engine("Window"); engine("Keyboard"); engine("Mouse"); engine("Pad1")
engine("PhysicsWorld"); engine("GwNavQueries"); engine("GwNavWorld"); engine("EngineOptimized"); engine("EngineOptimizedExtensions")
engine("Profiler"); engine("Renderer"); engine("ShadingEnvironment"); engine("LineObject"); engine("Light")
engine("Localizer"); engine("NetworkConstants"); engine("Crashify", { print_exception = function() end })
const("Development", {})
engine("ResourcePackage"); engine("Viewport"); engine("Clipboard"); engine("Stats"); engine("Achievement"); engine("Friends")
engine("Presence"); engine("Benchmark"); engine("Vector3Aux"); engine("Matrix4x4"); engine("Rectangle2D")

-- 2b. LuaJIT `bit` library (the engine runs LuaJIT; PUC Lua 5.1 has no bit ops). Pure-Lua shim.
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

-- 3. Math value types: plain tables are enough for data-table construction.
local function vec(...) return { ... } end
const("Vector3", setmetatable({ zero = function() return { 0, 0, 0 } end, up = function() return { 0, 0, 1 } end,
    forward = function() return { 0, 1, 0 } end, right = function() return { 1, 0, 0 } end,
    normalize = function(v) return v end, length = function() return 1 end }, { __call = function(_, ...) return vec(...) end }))
const("Vector2", function(...) return vec(...) end)
const("Vector4", function(...) return vec(...) end)
const("Vector3Box", function(...) return { unbox = function() return vec() end, store = function() end, ... } end)
const("QuaternionBox", function(...) return { unbox = function() return vec() end, store = function() end, ... } end)
const("Matrix4x4Box", function(...) return { unbox = function() return vec() end, store = function() end, ... } end)
const("Quaternion", setmetatable({ identity = function() return { 0, 0, 0, 1 } end, axis_angle = function() return { 0, 0, 0, 1 } end,
    from_euler_angles_xyz = function() return { 0, 0, 0, 1 } end, from_elements = function() return { 0, 0, 0, 1 } end,
    look = function() return { 0, 0, 0, 1 } end },
    { __call = function(_, ...) return vec(...) end }))
const("Color", function(...) return vec(...) end)
const("Localize", function(key) return "<" .. tostring(key) .. ">" end)
const("printf", function() end); const("print_warning", function() end); const("print_error", function() end)
const("cprint", function() end); const("cprintf", function() end)
const("visual_assert", function() end)

P.STUBS = STUBS
P.report = function()
    local hits = {}
    for name, n in pairs(P.stub_hits) do hits[#hits + 1] = { name, n } end
    table.sort(hits, function(a, b) return a[2] > b[2] end)
    local parts = {}
    for i = 1, math.min(#hits, 45) do parts[#parts + 1] = hits[i][1] .. " x" .. hits[i][2] end
    io.write("engine stub paths touched (top 45): " .. table.concat(parts, "; ") .. string.char(10))
    if P.first_failure then io.write("first failure: " .. P.first_failure .. string.char(10)) end
    io.write(string.format("explicit stubs declared: %d\n  %s\n", #STUBS, table.concat(STUBS, " ")))
end

-- 4. Real vanilla foundation utilities (plain Lua), in engine boot order
--    (scripts/boot.lua:250-262 and :516).
local function real(name)
    local ok, err = pcall(load_module, name, false)
    if not ok then io.write("PREAMBLE FAILED " .. name .. ": " .. tostring(err) .. string.char(10)) end
    return ok
end
real("foundation/scripts/util/user_setting")
if Development.init_user_settings then pcall(Development.init_user_settings) end
real("foundation/scripts/util/application_parameter")
if Development.init_application_parameters then pcall(Development.init_application_parameters, {}, true) end
real("foundation/scripts/util/development_parameter")
if Development.init_parameters then pcall(Development.init_parameters) end
for _, name in ipairs({
    "foundation/scripts/util/error", "foundation/scripts/util/patches", "foundation/scripts/util/class",
    "foundation/scripts/util/callback", "foundation/scripts/util/misc_util", "foundation/scripts/util/table",
    "foundation/scripts/util/math", "foundation/scripts/util/string", "foundation/scripts/util/local_require",
}) do real(name) end
real("scripts/settings/dlc_settings")
real("scripts/helpers/dlc_utils")
-- scripts/boot.lua:387: every DLC's additional settings files populate DLCSettings[...] lists
do
    local ok, err = pcall(DLCUtils.require_list, "additional_settings")
    if not ok then io.write("PREAMBLE FAILED DLC additional_settings: " .. tostring(err) .. string.char(10)) end
end
P.preamble_files = #P.order
for _, name in ipairs(P.EXTRA_PREREQS or {}) do real(name) end
