-- Detached #624 proof: execute the production installer, never the live forge.
-- Private tables/callbacks only; no engine, realm flags, settings, UI or writes.
return function(policy)
    assert(type(policy) == "table" and type(policy.install) == "function",
        "#624 production forge installer missing")

    local first, third, fourth = {}, {}, {}
    local function fixture(realm, keep, native_result)
        local calls, reports = 0, {}
        local native = function(...)
            calls = calls + 1
            assert(select("#", ...) == 4, "#624 native argument count changed")
            local a, b, c, d = ...
            assert(a == first and b == nil and c == third and d == fourth,
                "#624 native arguments changed")
            -- Native currently returns one Boolean; extra returns are not part
            -- of the installed wrapper's contract and must not be claimed.
            return native_result
        end
        local stop, prompt = function() end, function() end
        local definitions = { forge_access = { client = {
            can_interact = native, stop = stop, hud_description = prompt,
        } } }
        local private = {
            _cim_is_modded_realm = realm,
            _cim_is_in_keep = keep,
        }
        local logger = function(message)
            reports[#reports + 1] = message
        end
        local installed, reason = policy.install(private, definitions, logger)
        assert(installed == true, "#624 private install failed: " .. tostring(reason))
        local client = definitions.forge_access.client
        local state = private._cim_keep_forge_interaction_state
        assert(type(state) == "table" and state.original_can_interact == native
            and state.installed_predicate == client.can_interact,
            "#624 installed predicate identity changed")
        assert(client.stop == stop and client.hud_description == prompt,
            "#624 native transition/prompt changed")
        local function call()
            return client.can_interact(first, nil, third, fourth)
        end
        return private, definitions, call, reports, function() return calls end, logger
    end
    local yes, no = function() return true end, function() return false end

    local private, definitions, call, reports, calls, logger = fixture(yes, yes, false)
    assert(call() == true, "#624 native-false modded Keep interaction not restored")
    assert(call() == true and calls() == 2, "#624 native predicate not called once per request")
    assert(#reports == 1 and reports[1]
        == "[cim:624] Keep forge interaction enabled; native forge transition retained",
        "#624 bounded native forge report changed")
    local installed = definitions.forge_access.client.can_interact
    assert(policy.install(private, definitions, logger) == true
        and definitions.forge_access.client.can_interact == installed,
        "#624 repeated install nested/replaced the predicate")

    for _, scope in ipairs({ { no, yes }, { yes, no }, { no, no } }) do
        local _, _, invoke, log, count = fixture(scope[1], scope[2], false)
        assert(invoke() == false and count() == 1 and #log == 0,
            "#624 official/non-Keep native-false boundary widened")
    end
    local _, _, native_true, native_log = fixture(no, no, true)
    assert(native_true() == true and #native_log == 0,
        "#624 native-true delegation changed")
    local _, _, native_nil = fixture(no, yes, nil)
    assert(select("#", native_nil()) == 1 and native_nil() == nil,
        "#624 native nil result contract changed")

    local _, _, realm_error, error_log = fixture(function() error("realm-reader") end, yes, false)
    assert(realm_error() == false and #error_log == 0,
        "#624 throwing realm reader did not retain native false")
    local _, _, missing_realm = fixture(nil, yes, false)
    assert(missing_realm() == false, "#624 missing realm reader enabled the forge")
    local _, _, unknown_realm = fixture(function() return "modded" end, yes, false)
    assert(unknown_realm() == false, "#624 non-Boolean realm result enabled the forge")
    local _, _, missing_keep = fixture(yes, nil, false)
    assert(missing_keep() == false, "#624 missing Keep reader enabled the forge")

    -- The current owner catches realm-reader errors only. Keep/native errors
    -- must remain the same error, not be swallowed or turned into availability.
    local keep_failure = {}
    local _, _, keep_error = fixture(yes, function() error(keep_failure) end, false)
    local ok, failure = pcall(keep_error)
    assert(not ok and failure == keep_failure, "#624 Keep-reader error contract changed")
    local native_failure, reads = {}, 0
    local original = function() error(native_failure) end
    local defs = { forge_access = { client = { can_interact = original } } }
    local isolated = {
        _cim_is_modded_realm = function() reads = reads + 1; return true end,
        _cim_is_in_keep = function() reads = reads + 1; return true end,
    }
    assert(policy.install(isolated, defs, function() error("unexpected report") end) == true)
    ok, failure = pcall(defs.forge_access.client.can_interact)
    assert(not ok and failure == native_failure and reads == 0,
        "#624 native error/order contract changed")
end
