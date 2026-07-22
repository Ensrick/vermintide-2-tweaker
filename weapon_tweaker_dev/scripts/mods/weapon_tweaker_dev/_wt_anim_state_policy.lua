-- Pure policy for deciding when a cached per-unit 3P remap must be rebuilt.
-- The receiver career is part of the animation state-machine identity: a
-- character/career swap can retain the same item key and template while the
-- valid 3P vocabulary changes completely.
local M = {}

function M.remap_identity(template_name, item_key, career_name)
    local weapon_identity = template_name or item_key
    if type(weapon_identity) ~= "string" or weapon_identity == "" then
        return nil
    end
    return table.concat({ weapon_identity, tostring(career_name or "?") }, "|")
end

return M
