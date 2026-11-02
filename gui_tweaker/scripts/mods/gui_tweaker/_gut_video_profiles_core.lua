-- _gut_video_profiles_core.lua - engine-free Video-options profile transforms.
--
-- Captures native OptionsView widget values by their stable callback names and
-- plans a replay only against widgets that exist on the current machine. This
-- keeps capability-specific rows and monitor resolutions fail-closed.
--
-- Owned by: _gut_video_profiles.lua. Consumed via: mod:dofile and qa/lua.

local M = { SCHEMA = 1, MAX_SLOTS = 5 }

local function copy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local out = {}
    seen[value] = out
    for k, v in pairs(value) do out[copy(k, seen)] = copy(v, seen) end
    return out
end

local function equal(a, b, seen)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    seen = seen or {}
    if seen[a] == b then return true end
    seen[a] = b
    for k, v in pairs(a) do
        if not equal(v, b[k], seen) then return false end
    end
    for k in pairs(b) do
        if a[k] == nil then return false end
    end
    return true
end

function M.slot(value)
    local n = math.floor(tonumber(value) or 1)
    if n < 1 then return 1 end
    if n > M.MAX_SLOTS then return M.MAX_SLOTS end
    return n
end

function M.active_key() return "gut_video_profile_active" end
function M.slot_key(slot) return "gut_video_profile_slot_" .. M.slot(slot) end
function M.name_key(slot) return "gut_video_profile_name_" .. M.slot(slot) end

local function identity(widget)
    local content = type(widget) == "table" and widget.content
    local definition = type(content) == "table" and content.definition
    local callback_name = type(definition) == "table" and definition.callback
    if type(callback_name) ~= "string" or definition.gut_video_profile_control then return nil end
    if callback_name == "cb_graphics_quality" then return nil end
    return callback_name, widget.type, content
end

function M.capture(widgets)
    local values, count = {}, 0
    for i = 1, type(widgets) == "table" and #widgets or 0 do
        local callback_name, kind, content = identity(widgets[i])
        local value
        if callback_name and kind == "slider" then
            value = content.value
        elseif callback_name and type(content.options_values) == "table" then
            value = content.options_values[content.current_selection]
        end
        if value ~= nil then
            values[callback_name] = { kind = kind, value = copy(value) }
            count = count + 1
        end
    end
    return { schema = M.SCHEMA, values = values }, count
end

function M.plan(widgets, profile)
    local operations, missing = {}, 0
    local values = type(profile) == "table" and profile.schema == M.SCHEMA and profile.values
    if type(values) ~= "table" then return operations, missing, "invalid profile" end

    for i = 1, type(widgets) == "table" and #widgets or 0 do
        local callback_name, kind, content = identity(widgets[i])
        local saved = callback_name and values[callback_name]
        if type(saved) == "table" and saved.kind == kind then
            if kind == "slider" and type(saved.value) == "number" then
                operations[#operations + 1] = { widget = widgets[i], value = saved.value }
            elseif type(content.options_values) == "table" then
                local selection
                for j = 1, #content.options_values do
                    if equal(content.options_values[j], saved.value) then selection = j; break end
                end
                if selection then
                    operations[#operations + 1] = { widget = widgets[i], selection = selection }
                else
                    missing = missing + 1
                end
            end
        end
    end
    return operations, missing
end

function M.copy(value) return copy(value) end
function M.equal(a, b) return equal(a, b) end

return M
