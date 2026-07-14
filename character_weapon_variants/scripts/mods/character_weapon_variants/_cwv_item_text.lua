-- Canonical CWV item-text normalization. Some generated registrations pass a
-- title-prefixed description to both UI fields; strip exactly one redundant
-- heading while retaining the useful prose that follows it.
local M = {}

function M.description(title, description)
    if type(description) ~= "string" then return description end
    if type(title) ~= "string" or title == "" then return description end
    if description == title then return "A custom Career Weapon Variant." end
    if description:sub(1, #title) ~= title then return description end
    local rest = description:sub(#title + 1)
    rest = rest:gsub("^[%s:|%-]+", "")
    return rest ~= "" and rest or "A custom Career Weapon Variant."
end

return M
