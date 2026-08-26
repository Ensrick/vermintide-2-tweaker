-- Keyboard/mouse keybind capture shared owner (#123/#631).
-- Returns VMF's { primary, modifiers... } shape and identifies mouse primaries
-- so the interaction owner can commit them only after button release.

local M = {}

local MODIFIER = {
    ["left shift"] = "shift", ["right shift"] = "shift",
    ["left ctrl"] = "ctrl", ["right ctrl"] = "ctrl",
    ["left alt"] = "alt", ["right alt"] = "alt",
}

-- VMF PRIMARY_BINDABLE_KEYS.MOUSE indices 0..4.
local MOUSE_KEYID = {
    [0] = "mouse left",
    [1] = "mouse right",
    [2] = "mouse middle",
    [3] = "mouse extra 1",
    [4] = "mouse extra 2",
}

function M.poll()
    local count = 256
    local ok_count, runtime_count = pcall(function() return Keyboard.num_buttons() end)
    if ok_count and type(runtime_count) == "number" and runtime_count > 0 then
        count = runtime_count
    end

    local modifiers, seen, primary = {}, {}, nil
    for index = 0, count - 1 do
        local ok_button, down = pcall(Keyboard.button, index)
        if ok_button and type(down) == "number" and down > 0 then
            local ok_name, name = pcall(Keyboard.button_name, index)
            if ok_name and type(name) == "string" and name ~= "" and name ~= "esc" then
                local normalized = MODIFIER[name]
                if normalized then
                    if not seen[normalized] then
                        seen[normalized] = true
                        modifiers[#modifiers + 1] = normalized
                    end
                elseif not primary then
                    primary = name
                end
            end
        end
    end

    local primary_is_mouse = false
    if not primary then
        for index = 0, 4 do
            local ok_mouse, down = pcall(Mouse.button, index)
            if ok_mouse and type(down) == "number" and down > 0 then
                primary = MOUSE_KEYID[index]
                primary_is_mouse = true
                break
            end
        end
    end
    if not primary then return nil end

    local combo = { primary }
    for _, modifier in ipairs(modifiers) do combo[#combo + 1] = modifier end
    return combo, primary_is_mouse
end

return M
