-- _et_custom_breed_scheduler.lua - #1915 deferred custom-breed registration.
--
-- At mod load the network capacity authority does not exist yet: the
-- registrar's capacity readers refuse with `damage_source_cap_unavailable`
-- because `Network.type_info` errors "Network config not loaded" and
-- `NetworkConstants` is created only by network_constants.lua, which vanilla
-- dofiles after LobbyInternal.init_client (state_loading_restart_network.lua:124,
-- :161) and in GameNetworkManager.init (game_network_manager.lua:59), both
-- after Boot loads mods (boot.lua:389-413). A capacity refusal is not
-- terminal in the registrar (TERMINAL is set only after a threat write), so
-- the same declared spec may be registered later.
--
-- The Warlord and Chosen owners queue `{ spec = ..., on_result = ... }` jobs in
-- manifest order (Warlord first, then Chosen: that order is the wire order of
-- the three NetworkLookup axes). This scheduler runs the whole queue exactly
-- once, on the first trigger whose `Registrar.capacity_verdicts()` reports
-- `cap:N` for all three axes, then calls `on_ready` once (identity capture and
-- exact parity install, owned by _et_custom_breed_parity.lua). Every later
-- trigger is a no-op. Engine-free: the registrar, job list, ready callback and
-- log sink are injected, so the same object runs in the unit tests.
--
-- Owned by: _et_custom_breed_parity.lua (its single load owner).

local M = {}

-- The three capacity axes build_plan proves (registrar capacity_verdicts keys).
M.AXES = { "damage_source_id", "statistics_path_lookup", "damage_hotjoin_sync" }
-- Bounded "still waiting" rows: one per trigger name, at most this many.
M.WAIT_LOG_CAP = 4
M.PREFIX = "[et:451]"

function M.caps_ready(verdicts)
    if type(verdicts) ~= "table" then return false, "verdicts_unavailable" end
    for i = 1, #M.AXES do
        local axis = M.AXES[i]
        local verdict = rawget(verdicts, axis)
        if type(verdict) ~= "string" or not verdict:match("^cap:%d+$") then
            return false, axis .. "=" .. tostring(verdict)
        end
    end
    return true
end

-- opts.registrar: table with capacity_verdicts() and register(spec).
-- opts.jobs:      list of { spec = table, on_result = function(ok, reason, trigger) }.
-- opts.on_ready:  function(trigger), called once after the queue ran.
-- opts.log:       function(fmt, ...) for one bounded row (production: printf).
function M.new(opts)
    assert(type(opts) == "table" and type(opts.registrar) == "table"
        and type(opts.jobs) == "table", "scheduler needs a registrar and a job list")
    local registrar, jobs = opts.registrar, opts.jobs
    local on_ready, log = opts.on_ready, opts.log
    local done, ran_trigger, ready_error = false, nil, nil
    local waited, wait_rows = {}, 0

    local function emit(fmt, ...)
        if type(log) ~= "function" then return end
        local ok, row = pcall(string.format, M.PREFIX .. " " .. fmt, ...)
        if ok then pcall(log, "%s", row) end
    end

    local scheduler = {}

    -- Returns true when this call ran the queue, false plus a reason otherwise.
    function scheduler.try(trigger)
        trigger = tostring(trigger or "unnamed")
        if done then return false, "done" end
        local verdict_fn = rawget(registrar, "capacity_verdicts")
        local verdicts_ok, verdicts = false, nil
        if type(verdict_fn) == "function" then
            verdicts_ok, verdicts = pcall(verdict_fn)
        end
        local ready, reason = M.caps_ready(verdicts_ok and verdicts or nil)
        if not ready then
            if not waited[trigger] and wait_rows < M.WAIT_LOG_CAP then
                waited[trigger] = true
                wait_rows = wait_rows + 1
                emit("custom-breed registration deferred trigger=%s waiting=%s",
                    trigger, tostring(reason))
            end
            return false, reason
        end

        -- Once-only from here: a refusal inside the queue is final for this
        -- module load, exactly like the old load-time call.
        done, ran_trigger = true, trigger
        local register = rawget(registrar, "register")
        for i = 1, #jobs do
            local job = jobs[i]
            local ok, result_reason
            if type(job) ~= "table" or type(register) ~= "function" then
                ok, result_reason = nil, "job_invalid"
            else
                local call_ok, first, second = pcall(register, job.spec)
                if call_ok then ok, result_reason = first, second
                else ok, result_reason = nil, "register_threw:" .. tostring(first) end
            end
            if type(job) == "table" and type(job.on_result) == "function" then
                pcall(job.on_result, ok, result_reason, trigger)
            end
        end
        if type(on_ready) == "function" then
            local ready_ok, err = pcall(on_ready, trigger)
            if not ready_ok then ready_error = tostring(err) end
        end
        emit("custom-breed registration ran trigger=%s jobs=%d ready=%s",
            trigger, #jobs, ready_error and ("error:" .. ready_error) or "ok")
        return true
    end

    function scheduler.done() return done end
    function scheduler.ran_trigger() return ran_trigger end
    function scheduler.ready_error() return ready_error end

    return scheduler
end

return M
