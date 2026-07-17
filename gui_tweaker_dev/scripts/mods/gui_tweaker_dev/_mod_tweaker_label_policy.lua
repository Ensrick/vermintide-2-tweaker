-- Compatibility policy for labels owned by sibling Workshop mods.
--
-- Verification state belongs in GitHub, not the player UI.  During a staggered
-- Workshop rollout an older sibling bundle can still return a leading status
-- prefix even after Mod Tweaker itself has been updated.  Keep that migration
-- defence at the existing label-resolution boundary; do not mutate the source
-- mod's localization table or touch functional qualifiers.

local M = {}

local EXACT_STATUS = {
    working = true,
    confirmedworking = true,
    untested = true,
    verifyfix = true,
    verifyfixcoop = true,
    diagnosticsarmed = true,
    diag = true,
    crash = true,
    needsoffsets = true,
    wip = true,
    workinprogress = true,
    experimental = true,
    testing = true,
    prototype = true,
    fixed = true,
    unverified = true,
    notstarted = true,
}

local function _is_status_token(token)
    local lower = string.lower(token or "")
    local compact = string.gsub(lower, "[%s_%-]+", "")
    if EXACT_STATUS[compact] then return true end
    if string.match(compact, "^issue[%d#]") then return true end
    if string.match(compact, "^needsanimations") then return true end
    return false
end

function M.clean(value)
    if type(value) ~= "string" then return value end
    local result = value
    while true do
        local token, rest = string.match(result, "^%s*%[([^%]]+)%]%s*(.*)$")
        if token and _is_status_token(token) then
            result = rest
        else
            token, rest = string.match(result, "^%s*%(([^%)]+)%)%s*(.*)$")
            if token and _is_status_token(token) then
                result = rest
            else
                local prefix
                prefix, token = string.match(result, "^(.-)%s*%(([^%(%)]+)%)%s*$")
                if token and _is_status_token(token) then
                    result = prefix
                else
                    return result
                end
            end
        end
    end
end

return M
