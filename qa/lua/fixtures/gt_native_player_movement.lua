-- Small retained native fixture; not derived from the mod implementation under test.
-- Source: sibling Vermintide-2-Source-Code/scripts/settings/player_movement_settings.lua
-- Getter caches per-unit (:7-12); register_unit shallow-clones native defaults (:15-17).
-- Exact default assignments retained from lines 44,46-49; read 2026-11-03.
local M = {}
M.defaults = {
    player_speed_scale = 1,
    crouch_move_speed = 1.4,
    walk_move_speed = 1.9,
    move_speed = 4,
    backward_move_scale = 0.75,
}

function M.copy_defaults()
    local copy = {}
    for key, value in pairs(M.defaults) do copy[key] = value end
    return copy
end

-- Native per-unit cache shape, player_movement_settings.lua:7-17.
function M.new_settings_api()
    local units = {}
    return { get_movement_settings_table = function(unit)
        if not units[unit] then units[unit] = M.copy_defaults() end
        return units[unit]
    end }
end

-- Source: GenericStatusExtension.current_move_speed_multiplier:2343-2347.
-- Math.smoothstep is quintic (foundation/scripts/util/math.lua:124-130),
-- not the commonly substituted cubic approximation. Pure retained fixture.
function M.current_move_speed_multiplier(status)
    local x = math.max(0, math.min(status.move_speed_multiplier_timer, 1))
    local p = x * x * x * (x * (x * 6 - 15) + 10)
    return status.move_speed_multiplier * (1 - p) + p
end

function M.verify_optional_source(path)
    local file = io.open(path, "rb")
    if not file then return nil, "sibling native source unavailable" end
    local bytes = file:read("*a"); file:close()
    for key, expected in pairs(M.defaults) do
        local pattern = "PlayerUnitMovementSettings%." .. key .. "%s*=%s*([%d%.]+)"
        local actual = tonumber(bytes:match(pattern))
        assert(actual == expected, "native fixture drift: " .. key)
    end
    assert(bytes:find("PlayerUnitMovementSettings.get_movement_settings_table = function (unit)",
        1, true), "native per-unit settings getter missing")
    assert(bytes:find("units_player_movement_setting[unit] = table.clone(PlayerUnitMovementSettings)",
        1, true), "native per-unit clone contract changed")
    local root = assert(path:match("^(.-)scripts/settings/player_movement_settings%.lua$"))
    local function read(relative)
        local stream = assert(io.open(root .. relative, "rb"), "native provenance file missing")
        local result = stream:read("*a"); stream:close(); return result
    end
    for _, relative in ipairs({
        "scripts/unit_extensions/default_player_unit/player_input_extension.lua",
        "scripts/unit_extensions/default_player_unit/player_unit_first_person.lua",
        "scripts/unit_extensions/default_player_unit/player_unit_locomotion_extension.lua",
        "scripts/unit_extensions/generic/generic_camera_state_machine_extension.lua",
    }) do
        assert(read(relative):find("self.unit = unit", 1, true), "native unit field drift: " .. relative)
    end
    local status = read("scripts/unit_extensions/generic/generic_status_extension.lua")
    assert(status:find("math.smoothstep(self.move_speed_multiplier_timer, 0, 1)", 1, true))
    assert(status:find("math.lerp(self.move_speed_multiplier, 1, lerp_t)", 1, true))
    local math_source = read("foundation/scripts/util/math.lua")
    assert(math_source:find("return x * x * x * (x * (x * 6 - 15) + 10)", 1, true))
    assert(math_source:find("return a * (1 - p) + b * p", 1, true))
    return true
end

return M
