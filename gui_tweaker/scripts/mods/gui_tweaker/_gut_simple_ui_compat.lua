local mod = get_mod("gut")
local Policy = mod:dofile("scripts/mods/gui_tweaker/_gut_simple_ui_bounds_policy")

-- Simple UI (Workshop 1389872347) compatibility, #314 phase 1.
--
-- Upstream's window template writes cursor-derived coordinates directly in
-- `window.drag` and accepts them without a viewport clamp. The resize path can
-- also leave an over-tall title above the screen. We intentionally do NOT copy
-- or fork the unlicensed upstream implementation. This compatibility tick uses
-- only its documented/public runtime surface: SimpleUI.windows.list and each
-- window's position/size fields. It mutates the existing position table in
-- place, preserving references held by consumer mods.

local Compat = {
    policy = Policy,
    source_workshop_id = "1389872347",
    phase = 1,
}

local _reported = setmetatable({}, { __mode = "k" })

local function _screen_size()
    local resolution = rawget(_G, "UIResolution")
    if type(resolution) ~= "function" then return nil, nil end
    local ok, width, height = pcall(resolution)
    if not ok then return nil, nil end
    return width, height
end

function Compat.tick()
    local simple_ui = get_mod("SimpleUI")
    if simple_ui and type(simple_ui.is_enabled) == "function" then
        local ok, enabled = pcall(simple_ui.is_enabled, simple_ui)
        if ok and not enabled then return 0 end
    end
    local windows = simple_ui and simple_ui.windows and simple_ui.windows.list
    if type(windows) ~= "table" then return 0 end

    local screen_width, screen_height = _screen_size()
    if not screen_width then return 0 end

    local corrected = 0
    for _, window in pairs(windows) do
        local result = window and Policy.confine(window.position, window.size, screen_width, screen_height)
        if result and result.changed then
            local old_x, old_y = window.position[1], window.position[2]
            window.position[1], window.position[2] = result.x, result.y
            corrected = corrected + 1

            -- One raw-console breadcrumb per window+resolution. Holding a drag
            -- against an edge can request an invalid coordinate every frame;
            -- never turn that into log spam.
            local signature = tostring(screen_width) .. "x" .. tostring(screen_height)
            if _reported[window] ~= signature then
                _reported[window] = signature
                local out = rawget(_G, "printf")
                if type(out) == "function" then
                    pcall(out,
                        "[gut:314] recovered SimpleUI window=%s pos=(%.1f,%.1f)->(%.1f,%.1f) screen=%s",
                        tostring(window.name), old_x, old_y, result.x, result.y, signature)
                end
            end
        end
    end
    return corrected
end

-- GUT has several established update-chain owners. Append to the final chain;
-- no external Class.method hook or SimpleUI function replacement is required.
local _previous_update = mod.update
mod.update = function(dt)
    if _previous_update then _previous_update(dt) end
    Compat.tick()
end

mod._gut_simple_ui_compat = Compat
mod._gut_simple_ui_bounds_policy = Policy

return Compat
