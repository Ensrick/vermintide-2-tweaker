-- Pure attribution policy for issue #438. Kept engine-free so Lua 5.1 QA can
-- prove the no-double-credit boundary without constructing live unit storage.
local M = {}

function M.should_repair(context)
    if type(context) ~= "table" then return false end
    if context.is_server ~= true then return false end
    if context.has_talent ~= true then return false end
    if context.was_career_revivable ~= true then return false end
    if type(context.revives_before) ~= "number" then return false end
    if type(context.revives_after) ~= "number" then return false end
    return context.revives_after == context.revives_before
end

return M
