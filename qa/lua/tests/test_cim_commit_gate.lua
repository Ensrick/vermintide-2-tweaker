-- WP-CIM-02 (#80): the BackendManagerPlayFab.commit gate never drops a commit
-- that carries a completion callback. Vanilla registers that callback and
-- fires it from _check_current_commit
-- (Vermintide-2-Source-Code/scripts/managers/backend_playfab/backend_manager_playfab.lua:933-937,
-- playfab_mirror_base.lua:2714-2752, :1847-1868); the end-of-mission screen
-- is activated inside such a callback (scripts/game_state/state_ingame_running.lua:718-737).

local function recorder(result)
    local calls = {}
    local function func(...)
        calls[#calls + 1] = { n = select("#", ...), ... }
        return result
    end
    return func, calls
end

return function(H, repo_root)
    local path = repo_root
        .. "/crafting_in_modded_dev/scripts/mods/crafting_in_modded_dev/_cim_commit_gate.lua"

    local function load_gate()
        local chunk, err = loadfile(path)
        assert(chunk, "cim commit gate module is missing: " .. tostring(err))
        local M = chunk()
        assert(type(M) == "table", "cim commit gate must return a table")
        return M
    end

    H.test("cim commit gate: should_suppress only drops callback-less commits while a forge is open", function()
        local M = load_gate()
        H.equal(M.should_suppress(true, nil), true)
        H.equal(M.should_suppress(true, function() end), false)
        H.equal(M.should_suppress(false, nil), false)
        H.equal(M.should_suppress(false, function() end), false)
    end)

    H.test("cim commit gate: forge open with a callback reaches vanilla once with the same arguments", function()
        local M = load_gate()
        local func, calls = recorder("commit-id-7")
        local self_sentinel, cb = {}, function() end
        local result = M.hook(func, self_sentinel, true, cb, true)
        H.equal(result, "commit-id-7", "vanilla return value is returned")
        H.equal(#calls, 1, "vanilla called once")
        H.equal(calls[1].n, 3, "exactly three arguments")
        H.truthy(rawequal(calls[1][1], self_sentinel), "self forwarded")
        H.equal(calls[1][2], true, "skip_queue forwarded")
        H.truthy(rawequal(calls[1][3], cb), "callback forwarded")
    end)

    H.test("cim commit gate: forge open without a callback is suppressed", function()
        local M = load_gate()
        local func, calls = recorder("commit-id-8")
        local result = M.hook(func, {}, false, nil, true)
        H.equal(result, nil, "suppressed commit returns nil")
        H.equal(#calls, 0, "vanilla not called")
    end)

    H.test("cim commit gate: forge closed always reaches vanilla", function()
        local M = load_gate()
        local func, calls = recorder("commit-id-9")
        H.equal(M.hook(func, {}, false, nil, false), "commit-id-9")
        local cb = function() end
        H.equal(M.hook(func, {}, true, cb, false), "commit-id-9")
        H.equal(#calls, 2)
        H.equal(calls[1][3], nil)
        H.truthy(rawequal(calls[2][3], cb))
    end)

    H.test("cim commit gate: the in-mod self check passes on the shipped module", function()
        local M = load_gate()
        H.equal(type(M.self_check), "function")
        H.equal(M.self_check(), nil)
    end)
end
