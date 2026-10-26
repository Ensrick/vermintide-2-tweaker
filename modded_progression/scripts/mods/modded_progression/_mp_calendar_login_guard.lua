-- #1684: calendar login claims have no local grant transaction.
-- Native 6.13 HeroWindowGotwfOverview._claim_daily_reward:818-840 blocks
-- parent input AFTER calling the peddler. Its suppressed backend callback
-- cannot release that UI latch. Refuse before native state changes.
local M = { CHECK_NAME = "issue1684_calendar_login_action_boundary" }

function M.install(mod, deps)
    assert(type(mod) == "table" and type(mod.hook) == "function", "MP hook owner missing")
    assert(type(deps) == "table" and type(deps.is_modded_realm) == "function",
        "MP calendar realm query missing")
    assert(type(deps.rt_register) == "function", "MP calendar check registrar missing")
    local query, warned = deps.is_modded_realm, {}
    local function claim(func, self, reward_offset, ...)
        local ok, value = pcall(query)
        if ok and value == false then return func(self, reward_offset, ...) end
        local reason = ok and value == true and "local_login_rewards_unavailable" or "realm_unavailable"
        if not warned[reason] then
            warned[reason] = true
            if type(deps.print_log) == "function" then
                pcall(deps.print_log,
                    "[mp:1684] calendar_login_claim_denied reason=%s backend=none", reason)
            end
        end
        return nil
    end
    mod:hook("HeroWindowGotwfOverview", "_claim_daily_reward", claim)
    deps.rt_register(M.CHECK_NAME, M.runtime_check)
    return { claim_callback = claim }
end

-- Detached component check: uses the installed production callback. No live
-- class, realm global, player, UI, backend, schedule or reward state is touched.
function M.runtime_check()
    local hook, query = nil, function() return true end
    local calls, logs = 0, 0
    local owner = M.install({ hook = function(_, class, method, fn)
        if class ~= "HeroWindowGotwfOverview" or method ~= "_claim_daily_reward" then
            error("calendar hook target changed")
        end
        hook = fn
    end }, { is_modded_realm = function() return query() end,
        rt_register = function() end, print_log = function() logs = logs + 1 end })
    if hook ~= owner.claim_callback then return "calendar installed callback identity changed" end
    local native = function() calls = calls + 1; return "official", nil, 3, nil end
    local poison = setmetatable({}, { __index = function() error("calendar UI read") end,
        __newindex = function() error("calendar UI write") end })
    if hook(native, poison, 0) ~= nil or hook(native, poison, 0) ~= nil
            or calls ~= 0 or logs ~= 1 then return "modded calendar action was not bounded before UI" end
    for _, reader in ipairs({ function() return nil end, function() return "false" end,
            function() error("realm unreadable") end }) do
        query = reader
        if hook(native, poison, 0) ~= nil or calls ~= 0 then
            return "unreadable calendar authority entered native"
        end
    end
    if logs ~= 2 then return "calendar denial logging was not reason-bounded" end
    query = function() return false end
    local function capture(...) return select("#", ...), { ... } end
    local count, values = capture(hook(native, {}, -1))
    if calls ~= 1 or count ~= 4 or values[1] ~= "official"
            or values[2] ~= nil or values[3] ~= 3 or values[4] ~= nil then
        return "official calendar return tuple changed"
    end
    local failure = {}
    local ok, err = pcall(hook, function() error(failure) end, {}, 0)
    if ok or err ~= failure then return "official calendar exception changed" end
end

return M
