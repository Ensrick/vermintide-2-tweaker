-- #645: detached proof of the installed observation route and donor action graph.
-- No saved settings, live diagnostic ledger, global field, Unit or RPC mutation.
local M = {}
local NODE_FIELDS = {
    "kind", "anim_event", "anim_end_event", "attack_hold_input",
    "weapon_action_hand", "anim_end_event_condition_func",
}
local CHAIN_FIELDS = { "action", "sub_action", "input", "hold_required" }

local function same(a, b, seen)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    seen = seen or {}
    if seen[a] then return seen[a] == b end
    seen[a] = b
    for key, value in pairs(a) do
        if not same(value, b[key], seen) then return false end
    end
    for key in pairs(b) do if a[key] == nil then return false end end
    return true
end

function M.check_spear_graphs(policy, weapons)
    if type(weapons) ~= "table" then return "#645 weapon templates unavailable" end
    for _, pair in ipairs({
        { policy.EMPIRE_SPEAR_SHIELD_TEMPLATE, "es_deus_01_template" },
        { policy.ELVEN_SPEAR_SHIELD_TEMPLATE, "one_handed_spears_shield_template" },
    }) do
        local port, donor = rawget(weapons, pair[1]), rawget(weapons, pair[2])
        if type(port) ~= "table" or type(donor) ~= "table"
                or type(port.actions) ~= "table" or type(donor.actions) ~= "table" then
            return "#645 Spear and Shield donor/action graph missing"
        end
        if port.state_machine ~= donor.state_machine or port.wield_anim ~= donor.wield_anim then
            return "#645 Spear and Shield first-person routing drifted"
        end
        local block = port.actions.action_two and port.actions.action_two.default
        if type(block) ~= "table" or block.kind ~= "block" then
            return "#645 Spear and Shield block entry missing"
        end
        for group_name, group in pairs(donor.actions) do
            if type(group) == "table" then
                local target = port.actions[group_name]
                if type(target) ~= "table" then return "#645 action group missing" end
                for name, action in pairs(group) do
                    if type(action) == "table" then
                        local copy = target[name]
                        if type(copy) ~= "table" then return "#645 action node missing" end
                        for _, field in ipairs(NODE_FIELDS) do
                            if not same(copy[field], action[field]) then
                                return "#645 first-person action field drifted: " .. field
                            end
                        end
                        local chains, actual = action.allowed_chain_actions, copy.allowed_chain_actions
                        if (type(chains) == "table") ~= (type(actual) == "table") then
                            return "#645 action chain list missing"
                        end
                        if type(chains) == "table" then
                            if #chains ~= #actual then return "#645 action chain count drifted" end
                            for index, edge in ipairs(chains) do
                                if type(actual[index]) ~= "table" then return "#645 action chain edge missing" end
                                for _, field in ipairs(CHAIN_FIELDS) do
                                    if not same(actual[index][field], edge[field]) then
                                        return "#645 action chain edge drifted: " .. field
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
end

function M.check(policy, owner, weapons)
    if type(owner) ~= "table" or owner.networked_3p_remap_installed ~= true
            or type(owner.networked_3p_anim_callback) ~= "function"
            or type(owner.probe_candidate_action) ~= "function" then
        return "#645 installed candidate observer owner missing"
    end
    local cap = policy.DIAGNOSTIC_EVENT_CAP
    if type(cap) ~= "number" or cap < 1 or cap > 32 or cap ~= math.floor(cap) then
        return "#645 diagnostic cap invalid"
    end
    local logs, delegated = {}, 0
    local runtime = policy.install({ get = function() end,
        set = function() error("#645 probe tried to persist") end }, {
        diagnostics_enabled = function() return true end,
        emit_candidate_diagnostic = function(format, ...)
            logs[#logs + 1] = string.format(format, ...)
        end,
    })
    local function run(item, event)
        local ok, a, b, c = owner.probe_candidate_action(runtime, item,
            "we_maidenguard", event, function(_, actual, ...)
                delegated = delegated + 1
                if actual ~= event then error("#645 probe changed the native event") end
                return nil, "native", nil
            end)
        return ok == true and a == nil and b == "native" and c == nil
    end
    if not run("we_2h_axe", "issue645_probe_1") or #logs ~= 1 or delegated ~= 1 then
        return "#645 installed candidate observer route disconnected"
    end
    if not logs[1]:find("item=we_2h_axe career=we_maidenguard owner_event=issue645_probe_1", 1, true) then
        return "#645 installed candidate context was not forwarded"
    end
    if not run("we_2h_axe", "issue645_probe_1") or #logs ~= 1 then
        return "#645 installed candidate observation was not deduplicated"
    end
    if not run("es_2h_sword", "issue645_probe_control") or #logs ~= 1 then
        return "#645 installed candidate observation admitted a non-candidate"
    end
    for index = 2, cap + 3 do
        if not run("we_2h_axe", "issue645_probe_" .. index) then
            return "#645 installed candidate route lost native delegation"
        end
    end
    if #logs ~= cap then return "#645 installed candidate observations are not capped" end
    return M.check_spear_graphs(policy, weapons)
end
return M
