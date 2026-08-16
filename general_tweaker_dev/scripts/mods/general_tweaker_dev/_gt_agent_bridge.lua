local mod = get_mod("gt_dev")

-- _gt_agent_bridge.lua -- Claude agent bridge, Phase 1: outbound live telemetry + clipboard probe (issue #1338)
--
-- DEV-ONLY module: never promoted to public gt (promote.ps1 default-skips
-- dev-only files). Gives an external Claude session eyes on the running game:
-- framed, greppable engine-printf output that tools/agent-bridge/
-- agent-bridge-watch.ps1 tails from console-*.log and materializes into files.
-- Command-only plus ONE registered update consumer; NO vanilla hooks, so zero
-- hook-collision surface. All output uses engine printf so it lands in the
-- log even with mod-logging OFF (CLAUDE.md non-negotiable #9).
--
-- Commands (armed state defaults OFF; nothing runs until /agent_arm):
--   /agent_probe_clipboard        - Phase 2 gate: is Clipboard.get/put live in retail?
--   /agent_arm [seconds]          - start heartbeat telemetry (default 2s period)
--   /agent_disarm                 - stop heartbeat
--   /agent_dump <dotted.path> [depth] - serialize a _G-reachable value between
--                                   BEGIN/END frame markers (read-only walk)
--
-- Frame protocol (keep in sync with tools/agent-bridge/agent-bridge-watch.ps1):
--   [agent:hb] seq=N t=... state=... level=... pos=x,y,z hp=...   (single line)
--   [agent:dump:<seq>] BEGIN <path>
--     <payload lines, Lua-literal-ish>
--   [agent:dump:<seq>] END
--   [agent:probe] k=v ...                                          (single lines)
--
-- Owned by: general_tweaker_dev.lua entry point. Consumed via: mod:dofile.

-- ============================================================
-- Output helpers
-- ============================================================
-- Serialized payloads can contain '%', so never feed them to printf as the
-- format string; always route through "%s".
local function _raw(line)
    pcall(printf, "%s", line)
end

local function _out(fmt, ...)
    local ok, line = pcall(string.format, fmt, ...)
    if ok then
        _raw(line)
    end
end

-- ============================================================
-- Bridge state (on the mod table: no new main-chunk locals, and readable
-- from /gt_regression_test or sibling modules if ever needed)
-- ============================================================
mod._agent_bridge = mod._agent_bridge or {
    armed = false,
    interval = 2,
    acc = 0,
    hb_seq = 0,
    dump_seq = 0,
}
local state = mod._agent_bridge

-- ============================================================
-- Serializer (depth/size-capped Lua-literal-ish dump)
-- ============================================================
local MAX_LINES = 500
local MAX_KEYS_PER_TABLE = 80

local function _scalar_repr(v)
    local tv = type(v)
    if tv == "string" then
        if #v > 200 then
            v = string.sub(v, 1, 200) .. "...<truncated>"
        end
        return string.format("%q", v)
    end
    -- number/boolean/nil/function/userdata/thread: tostring is safe under pcall
    -- (Stingray userdata like Vector3 stringify fine).
    local ok, s = pcall(tostring, v)
    return ok and s or ("<" .. tv .. ": tostring failed>")
end

local function _serialize(value, depth_cap, lines, seen, indent, prefix)
    if #lines >= MAX_LINES then
        return
    end
    if type(value) ~= "table" or depth_cap <= 0 then
        lines[#lines + 1] = indent .. prefix .. _scalar_repr(value)
            .. (type(value) == "table" and " -- <table, depth cap>" or "")
        return
    end
    if seen[value] then
        lines[#lines + 1] = indent .. prefix .. "<cycle: " .. tostring(value) .. ">"
        return
    end
    seen[value] = true
    lines[#lines + 1] = indent .. prefix .. "{"
    local n = 0
    for k, v in pairs(value) do
        n = n + 1
        if n > MAX_KEYS_PER_TABLE then
            lines[#lines + 1] = indent .. "  ...<" .. MAX_KEYS_PER_TABLE .. "+ keys, capped>"
            break
        end
        if #lines >= MAX_LINES then
            lines[#lines + 1] = indent .. "  ...<line cap " .. MAX_LINES .. " hit>"
            break
        end
        local kr = (type(k) == "string") and k or ("[" .. _scalar_repr(k) .. "]")
        _serialize(v, depth_cap - 1, lines, seen, indent .. "  ", kr .. " = ")
    end
    if n == 0 then
        lines[#lines] = lines[#lines] .. "}"
    else
        lines[#lines + 1] = indent .. "}"
    end
    seen[value] = nil
end

-- ============================================================
-- Dotted-path resolver (read-only; no loadstring in Phase 1)
-- ============================================================
local function _resolve_path(path)
    local cur = _G
    for seg in string.gmatch(path, "[^%.]+") do
        local key = tonumber(seg) or seg
        local ok, nxt = pcall(function()
            return cur[key]
        end)
        if not ok then
            return nil, "index error at segment '" .. seg .. "': " .. tostring(nxt)
        end
        if nxt == nil then
            return nil, "nil at segment '" .. seg .. "'"
        end
        cur = nxt
    end
    return cur, nil
end

-- ============================================================
-- Heartbeat
-- ============================================================
local function _hb_fields()
    local fields = {}
    -- Identity (same guarded reads as /dump_level's identity section).
    pcall(function()
        local gm = Managers and Managers.state and Managers.state.game_mode
        fields.state = (gm and gm.game_mode_key and tostring(gm:game_mode_key())) or "?"
    end)
    pcall(function()
        local lth = rawget(_G, "Managers") and Managers.level_transition_handler
        fields.level = (lth and lth.get_current_level_key and tostring(lth:get_current_level_key())) or "?"
    end)
    -- Local hero: live world_position (POSITION_LOOKUP is stale for the local
    -- player in some phases), health via extension method-existence checks.
    pcall(function()
        local player = Managers and Managers.player and Managers.player:local_player()
        local unit = player and player.player_unit
        if unit and Unit.alive(unit) then
            local okp, pos = pcall(Unit.world_position, unit, 0)
            if okp and pos then
                fields.pos = string.format("%.1f,%.1f,%.1f", pos.x, pos.y, pos.z)
            end
            local ext = ScriptUnit.has_extension and ScriptUnit.has_extension(unit, "health_system")
            if ext and ext.current_health_percent then
                local okh, hp = pcall(ext.current_health_percent, ext)
                if okh and type(hp) == "number" then
                    fields.hp = string.format("%.2f", hp)
                end
            end
        end
    end)
    return fields
end

local function _hb_tick(dt)
    if not state.armed then
        return
    end
    state.acc = state.acc + (dt or 0)
    if state.acc < state.interval then
        return
    end
    state.acc = 0
    state.hb_seq = state.hb_seq + 1
    local f = _hb_fields()
    _out("[agent:hb] seq=%d t=%s state=%s level=%s pos=%s hp=%s",
        state.hb_seq,
        tostring((os and os.time and os.time()) or "?"),
        f.state or "?", f.level or "?", f.pos or "?", f.hp or "?")
end

if mod._gt_register_update then
    mod._gt_register_update("agent_bridge_hb", _hb_tick)
else
    _raw("[agent] ERROR: mod._gt_register_update unavailable; heartbeat disabled")
end

-- ============================================================
-- Commands
-- ============================================================
mod:command("agent_arm", "Agent bridge: start heartbeat telemetry to the console log (optional period in seconds, default 2)", function(seconds)
    local period = tonumber(seconds)
    if period and period >= 0.25 then
        state.interval = period
    end
    state.armed = true
    state.acc = 0
    _out("[agent] ARMED interval=%s version=%s", tostring(state.interval), tostring(mod.MOD_VERSION))
    mod:echo("Agent bridge armed (heartbeat every %ss).", tostring(state.interval))
end)

mod:command("agent_disarm", "Agent bridge: stop heartbeat telemetry", function()
    state.armed = false
    _raw("[agent] DISARMED")
    mod:echo("Agent bridge disarmed.")
end)

mod:command("agent_dump", "Agent bridge: serialize a _G-reachable value to the console log, e.g. /agent_dump Managers.state.game_mode 2", function(path, depth)
    if not path or path == "" then
        mod:echo("Usage: /agent_dump <dotted.path> [depth 1-6]")
        return
    end
    local depth_cap = math.min(math.max(tonumber(depth) or 3, 1), 6)
    state.dump_seq = state.dump_seq + 1
    local seq = state.dump_seq
    local value, err = _resolve_path(path)
    -- Every payload line carries the [agent:d] marker so the watcher can
    -- filter deterministically even if unrelated log lines interleave.
    _out("[agent:dump:%d] BEGIN %s", seq, path)
    if err then
        _raw("[agent:d] error = " .. string.format("%q", err))
    else
        local lines = {}
        _serialize(value, depth_cap, lines, {}, "", "")
        for i = 1, #lines do
            _raw("[agent:d] " .. lines[i])
        end
    end
    _out("[agent:dump:%d] END", seq)
    mod:echo("Dumped '%s' (frame %d) to the console log.", path, seq)
end)

mod:command("agent_probe_clipboard", "Agent bridge: probe whether Clipboard.get/put is live in retail (Phase 2 gate, issue #1338)", function()
    local cb = rawget(_G, "Clipboard")
    _out("[agent:probe] clipboard_type=%s", type(cb))
    if type(cb) ~= "table" and type(cb) ~= "userdata" then
        _raw("[agent:probe] verdict=ABSENT")
        mod:echo("Clipboard API absent.")
        return
    end
    _out("[agent:probe] get_type=%s put_type=%s", type(cb.get), type(cb.put))
    local ok_get, orig = pcall(cb.get)
    -- Never log clipboard CONTENT (may be user-sensitive) -- length only.
    _out("[agent:probe] get_ok=%s orig_type=%s orig_len=%s",
        tostring(ok_get), type(orig), tostring(type(orig) == "string" and #orig or "n/a"))
    local token = "VT2A_PROBE_" .. tostring((os and os.time and os.time()) or 0)
    local ok_put, put_err = pcall(cb.put, token)
    _out("[agent:probe] put_ok=%s%s", tostring(ok_put), ok_put and "" or (" err=" .. tostring(put_err)))
    local verdict = "DEAD"
    if ok_put then
        local ok_get2, rt = pcall(cb.get)
        if ok_get2 and rt == token then
            verdict = "LIVE"
        elseif ok_get2 then
            verdict = "PUT_NOOP (roundtrip len=" .. tostring(type(rt) == "string" and #rt or type(rt)) .. ")"
        end
        -- Best-effort restore of whatever the user had.
        if ok_get and type(orig) == "string" then
            pcall(cb.put, orig)
        end
    end
    _out("[agent:probe] verdict=%s", verdict)
    mod:echo("Clipboard probe verdict: %s (details in console log).", verdict)
end)

_raw("[agent] bridge module loaded (Phase 1: /agent_arm /agent_dump /agent_probe_clipboard)")
