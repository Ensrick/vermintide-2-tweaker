-- Source-qualified portable6.13 base inputs for required Old Musket QA.
-- Tracked resolved donors and verbatim native templates/callback are mandatory.
-- Optional external provenance reexecutes raw definitions/PowerLevel resolution.
-- DLC additions, Stingray ABI and native playback remain unproven.
local M = {}
M.names = { "heavy_slashing_tank", "heavy_slashing_smiter_stab_polearm",
    "medium_spear_smiter_stab", "medium_slashing_linesman_spear" }
local function read(path)
    local f = assert(io.open(path, "rb")); local s = f:read("*a"); f:close()
    s = s:gsub("\r\n", "\n")
    if s:sub(1, 3) == string.char(239, 187, 191) then s = s:sub(4) end
    return s
end
local function run(source, env, name)
    local chunk = assert(loadstring(source, "@" .. name)); setfenv(chunk, env); return chunk()
end
function M.external_available(root)
    local path = (os.getenv("VT2_SOURCE_ROOT") or root .. "/../Vermintide-2-Source-Code")
        .. "/scripts/settings/equipment/power_level_templates.lua"
    local f = io.open(path, "rb"); if f then f:close(); return true end
    return false
end
function M.load_external(env, root, lookup)
    local native = os.getenv("VT2_SOURCE_ROOT") or root .. "/../Vermintide-2-Source-Code"
    local prefix = native .. "/scripts/settings/equipment/"
    local private = setmetatable({ table = env.table, DLCUtils = { require_list = function(name)
        assert(name == "power_level_template_files_names")
    end }, fassert = function(ok, message, ...) assert(ok, string.format(message, ...)) end }, { __index = env })
    private._G = private
    private.require = function(name) assert(name == "scripts/settings/equipment/power_level_templates") end
    run(read(prefix .. "power_level_templates.lua"), private, prefix .. "power_level_templates.lua")
    local source = read(prefix .. "damage_profile_templates.lua")
    local stop = assert(source:find("DamageProfileTemplates.maidenguard_dash_ability =", 1, true))
    local resolve = assert(source:find("for name, damage_profile in pairs(DamageProfileTemplates) do", stop, true))
    local resolve_end = assert(source:find("\nlocal no_damage_templates =", resolve, true))
    run(source:sub(1, stop - 1) .. source:sub(resolve, resolve_end - 1), private, "exact-native-raw-donors-and-resolution")
    for _, name in ipairs(M.names) do
        env.DamageProfileTemplates[name] = assert(private.DamageProfileTemplates[name])
        if lookup then
            assert(rawget(lookup, name) == nil)
            local index = #lookup + 1
            rawset(lookup, index, name); rawset(lookup, name, index)
        end
    end
    local weapons = run(read(prefix .. "weapon_templates/2h_heavy_spears.lua"), env,
        prefix .. "weapon_templates/2h_heavy_spears.lua")
    env.Weapons.two_handed_heavy_spears_template = assert(weapons.two_handed_heavy_spears_template)
    return private
end
function M.snapshot(root)
    local filename = root .. "/qa/lua/fixtures/cwv_old_musket_native_6_13.lua"
    local value = assert(loadfile(filename), "required tracked Old Musket native fixture missing")()
    assert(type(value) == "table" and type(value.handguns) == "string"
        and type(value.tuskgor) == "string" and type(value.handgun_post_update) == "string"
        and type(value.resolved_profiles) == "table", "required tracked native fixture malformed")
    return value
end
function M.available(root)
    M.snapshot(root) -- Required input: absence is a failure, never a green skip.
    return true
end
function M.load(env, root, lookup)
    local snapshot = M.snapshot(root)
    for _, name in ipairs(M.names) do
        env.DamageProfileTemplates[name] = env.table.clone(assert(snapshot.resolved_profiles[name]), true)
        if lookup then
            assert(rawget(lookup, name) == nil)
            local index = #lookup + 1
            rawset(lookup, index, name); rawset(lookup, name, index)
        end
    end
    local weapons = run(snapshot.tuskgor, env, "tracked-native6.13-complete-Tuskgor")
    env.Weapons.two_handed_heavy_spears_template = assert(weapons.two_handed_heavy_spears_template)
    return snapshot
end
return M
