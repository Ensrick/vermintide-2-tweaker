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
engine("Script"); engine("Gui"); engine("Material"); engine("Mesh"); engine("Window"); engine("Keyboard"); engine("Mouse"); engine("Pad1")
engine("PhysicsWorld"); engine("GwNavQueries"); engine("GwNavWorld"); engine("EngineOptimized"); engine("EngineOptimizedExtensions")
engine("Profiler"); engine("Renderer"); engine("ShadingEnvironment"); engine("LineObject"); engine("Light")
engine("Localizer"); engine("NetworkConstants"); engine("Crashify", { print_exception = function() end })
engine("Development", { parameter = function() return nil end, set_parameter = function() end })
engine("ResourcePackage"); engine("Viewport"); engine("Clipboard"); engine("Stats"); engine("Achievement"); engine("Friends")
engine("Presence"); engine("Benchmark"); engine("Vector3Aux"); engine("Matrix4x4"); engine("Rectangle2D")

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

-- 4. Real vanilla foundation utilities (plain Lua), in engine boot order.
for _, name in ipairs({
    "foundation/scripts/util/error",
    "foundation/scripts/util/class",
    "foundation/scripts/util/table",
    "foundation/scripts/util/math",
    "foundation/scripts/util/string",
    "foundation/scripts/util/local_require",
    "foundation/scripts/util/misc_util",
    "foundation/scripts/util/callback",
}) do
    local ok, err = pcall(load_module, name, false)
    if not ok then io.write("PREAMBLE FAILED " .. name .. ": " .. tostring(err) .. "\n") end
end
for _, name in ipairs({ "scripts/settings/dlc_settings", "scripts/helpers/dlc_utils" }) do
    local ok, err = pcall(load_module, name, false)
    if not ok then io.write("PREAMBLE FAILED " .. name .. ": " .. tostring(err) .. "\n") end
end
