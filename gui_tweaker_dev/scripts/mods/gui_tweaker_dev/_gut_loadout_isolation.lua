-- _gut_loadout_isolation.lua -- loadout isolation contract 1 for item-minting mods (#402).
--
-- Other mods that mint their own backend ids (crafting_in_modded, character_weapon_variants,
-- weapons_of_chaos, modded_progression) ask this contract before writing such an id into a
-- career loadout:
--     local gut = get_mod("gut") or get_mod("gut_dev")
--     local iso = gut and gut.loadout_isolation
--     local kept = iso and iso.contract == 1 and iso.safe_to_write_loadout()
-- The answer comes from a FUNCTIONAL probe through the real hook dispatch, never from a list the
-- module writes about itself: both Adventure loadout writers are called on a throwaway `self`
-- with a reserved career name. gut's live write hooks answer PROBE_TOKEN for that career before
-- touching anything; when they are not live (gut disabled, official realm, an older build),
-- vanilla runs on the throwaway table and errors at its first field read
-- (Vermintide-2-Source-Code/scripts/managers/backend_playfab/playfab_mirror_base.lua:1928-1930
-- and :3631-3633), which pcall catches. The live mirror is never passed to the probe.
--
-- Fail closed: any error, a missing class or writer, an unknown mode, a non-modded realm or a
-- live mirror that is missing or not on Adventure data make safe_to_write_loadout() false.
-- Pure: no VMF or game global; every engine read arrives in `deps`.
-- Offline tests: qa/lua/tests/test_gut_loadout_isolation.lua.

local Isolation = {}

Isolation.CONTRACT = 1
Isolation.PROBE_CAREER = "__gut_isolation_probe__"
Isolation.PROBE_TOKEN = "gut-captured"

local KNOWN_MODES = { off = true, store = true, readonly = true }

local function values_equal(a, b)
    if a == b then return true end
    if type(a) ~= "table" or type(b) ~= "table" then return false end
    for k, v in pairs(a) do
        if not values_equal(v, b[k]) then return false end
    end
    for k in pairs(b) do
        if a[k] == nil then return false end
    end
    return true
end

-- rows_clean(career_data, career_data_mirror, keys) -> true | false, detail | nil
--   career_data[career][row][key] against career_data_mirror[career][row][key] for each key.
--   A career or row present on one side only is not clean. A missing argument returns nil.
function Isolation.rows_clean(career_data, career_data_mirror, keys)
    if type(career_data) ~= "table" or type(career_data_mirror) ~= "table" or type(keys) ~= "table" then
        return nil
    end
    for career, rows in pairs(career_data) do
        local mirror_rows = career_data_mirror[career]
        if type(rows) ~= "table" or type(mirror_rows) ~= "table" then
            return false, string.format("career=%s rows missing on one side", tostring(career))
        end
        for row, data in pairs(rows) do
            local mirror_data = mirror_rows[row]
            if type(data) ~= "table" or type(mirror_data) ~= "table" then
                return false, string.format("career=%s row=%s present on one side only", tostring(career), tostring(row))
            end
            for i = 1, #keys do
                local key = keys[i]
                if not values_equal(data[key], mirror_data[key]) then
                    return false, string.format("career=%s row=%s key=%s differs", tostring(career), tostring(row), tostring(key))
                end
            end
        end
        for row in pairs(mirror_rows) do
            if rows[row] == nil then
                return false, string.format("career=%s row=%s present on one side only", tostring(career), tostring(row))
            end
        end
    end
    for career in pairs(career_data_mirror) do
        if career_data[career] == nil then
            return false, string.format("career=%s rows missing on one side", tostring(career))
        end
    end
    return true
end

-- Calls both writers on throwaway tables. Owned only when both calls succeed and both answer
-- PROBE_TOKEN. Returns owned, reason.
local function probe_chokepoint(class)
    if type(class) ~= "table" then return false, "writer class missing" end
    local set_character_data = class.set_character_data
    local set_career_read_only_data = class.set_career_read_only_data
    if type(set_character_data) ~= "function" or type(set_career_read_only_data) ~= "function" then
        return false, "writer method missing"
    end
    local ok1, r1 = pcall(set_character_data, { _characters_data_key = "characters_data" },
        Isolation.PROBE_CAREER, "slot_melee", "probe")
    local ok2, r2 = pcall(set_career_read_only_data, { _characters_data_key = "characters_data" },
        "probe", "slot_melee", "probe", Isolation.PROBE_CAREER)
    if ok1 and ok2 and r1 == Isolation.PROBE_TOKEN and r2 == Isolation.PROBE_TOKEN then
        return true
    end
    if not ok1 or not ok2 then return false, "writer probe reached the vanilla writer" end
    return false, "writer probe not answered by the capture hook"
end

local function call_bool(fn)
    if type(fn) ~= "function" then return false end
    local ok, value = pcall(fn)
    return ok and value == true
end

-- new(deps) -> contract object. deps:
--   class           : the Adventure mirror class whose writers gut hooks (PlayFabMirrorAdventure)
--   in_modded_realm : function() -> bool
--   mode            : function() -> "off" | "store" | "readonly"
--   mirror          : function() -> the live mirror or nil (read, never passed to the probe)
--   keys            : loadout row keys compared by official_rows_clean
-- status() and safe_to_write_loadout() ignore their arguments, so both `iso.status()` and
-- `iso:status()` work.
function Isolation.new(deps)
    deps = type(deps) == "table" and deps or {}
    local api = { contract = Isolation.CONTRACT }

    -- One evaluation. `adventure` is private: true only when the live mirror is readable and
    -- holds Adventure data. The capture hooks pass a Versus mirror (vs_characters_data,
    -- playfab_mirror_adventure.lua:25-29) through to vanilla, so a write there is not captured
    -- even though the probe (which carries the Adventure key) is answered.
    local function evaluate()
        local result = { contract = Isolation.CONTRACT, realm_modded = false, mode = "off",
            chokepoint_owned = false, official_rows_clean = nil, reason = nil }
        local adventure = false
        local ok, err = pcall(function()
            result.realm_modded = call_bool(deps.in_modded_realm)
            local mode_ok, mode = pcall(deps.mode)
            if mode_ok and KNOWN_MODES[mode] then
                result.mode = mode
            else
                result.reason = "unknown mode: " .. tostring(mode)
            end
            local owned, why = probe_chokepoint(deps.class)
            result.chokepoint_owned = owned == true
            result.reason = result.reason or why
            local mirror_ok, mirror = pcall(deps.mirror)
            if mirror_ok and type(mirror) == "table" then
                adventure = mirror._characters_data_key == "characters_data"
                local clean, detail = Isolation.rows_clean(mirror._career_data, mirror._career_data_mirror, deps.keys)
                result.official_rows_clean = clean
                if clean == false then result.reason = result.reason or detail end
            end
        end)
        if not ok then
            result.chokepoint_owned = false
            result.reason = "status error: " .. tostring(err)
            adventure = false
        end
        return result, adventure
    end

    function api.status()
        return (evaluate())
    end

    function api.safe_to_write_loadout()
        local ok, safe, reason = pcall(function()
            local s, adventure = evaluate()
            if not s.realm_modded then return false, "not the modded realm" end
            if s.mode == "off" then return false, s.reason or "loadout capture is off" end
            if not s.chokepoint_owned then return false, s.reason or "writer capture not live" end
            if not adventure then return false, "live backend mirror missing or not Adventure data" end
            return true, nil
        end)
        if not ok then return false, "safe_to_write_loadout error: " .. tostring(safe) end
        return safe == true, reason
    end

    return api
end

-- check(iso) -> nil on pass, or a failure string. In-game check issue402_isolation_contract:
-- modded realm => the capture must be live and the official rows must not be known dirty;
-- official realm => the probe must reach vanilla and writing must be reported unsafe.
function Isolation.check(iso)
    if type(iso) ~= "table" or iso.contract ~= Isolation.CONTRACT
        or type(iso.status) ~= "function" or type(iso.safe_to_write_loadout) ~= "function" then
        return "loadout isolation contract 1 not published"
    end
    local s = iso.status()
    if s.realm_modded then
        if s.chokepoint_owned ~= true then
            return "modded realm: loadout writers not captured (" .. tostring(s.reason) .. ")"
        end
        if s.official_rows_clean == false then
            return "modded realm: official loadout rows differ from the committed mirror (" .. tostring(s.reason) .. ")"
        end
        return nil
    end
    if s.chokepoint_owned then
        return "official realm: the writer probe was answered (mode gate broken)"
    end
    if iso.safe_to_write_loadout() ~= false then
        return "official realm: safe_to_write_loadout must be false"
    end
    return nil
end

return Isolation
