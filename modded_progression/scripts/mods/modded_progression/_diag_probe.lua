local mod = get_mod("mp")

-- _diag_probe.lua — passive, default-on diagnostic emitter.
--
-- Purpose (team-lead brief 2026-07-01): attribution probe for the #174 bot /
-- player loadout replace-on-startup bug. The user playtests and hands over the
-- console log afterward; they run with VMF mod logging OFF and never type a
-- chat command, so every probe here:
--   * is armed at mod load (no toggle, no command),
--   * writes via engine `printf` (VMF mod:info / mod:debug / mod:warning route
--     through VMF's gated logging pipeline and can be invisible with logging
--     off; `printf` always lands in the engine console log),
--   * is rate-limited so a per-frame / per-unit caller can never flood the log,
--   * changes ZERO gameplay behaviour (pure observation).
--
-- Channel emitted through here (grep the user's log by the bracket tag):
--   [174:loadout]  — who writes/restores a loadout item (task 1)
--
-- Rate-limit model: each distinct dedup `key` logs on first sight and whenever
-- its payload CHANGES. During a startup window (WINDOW_S seconds after load)
-- unchanged repeats also log, so the startup burst is captured in full. A hard
-- GLOBAL_CAP bounds total lines per session as a flood backstop. Pass key=nil
-- to always emit (still subject to the global cap).

local M = {}

local WINDOW_S   = 90    -- "log freely" window (seconds after load) for repeats
local PERKEY_CAP = 4     -- within the window, at most this many UNCHANGED logs/key
local GLOBAL_CAP = 900   -- hard ceiling on probe lines emitted this session

local _load_t = os.time()
local _count  = 0
local _last   = {}       -- dedup key -> last payload string logged
local _kcount = {}       -- dedup key -> unchanged logs emitted (window budget)

local function _raw(line)
    if _count >= GLOBAL_CAP then return end
    _count = _count + 1
    -- printf takes a C-style format string; pass the built line as a %s ARG so a
    -- literal % inside an item key / traceback can't be read as a format spec.
    if printf then
        printf("%s", line)
    elseif mod and mod.info then
        mod:info("%s", line)
    end
end

-- tag:     channel tag, e.g. "174:loadout" (no brackets).
-- key:     dedup key (nil = always emit, subject only to the global cap).
-- payload: preformatted field string (already-stringified values).
--
-- Keyed emits always log a first-sight or a changed payload (the attribution
-- signal). An UNCHANGED payload logs only during the startup window AND only up
-- to PERKEY_CAP times per key -- so a per-frame / hot read path can never flood
-- (bounded by PERKEY_CAP*distinct-keys, then GLOBAL_CAP as a backstop).
function M.emit(tag, key, payload)
    payload = payload or ""
    if key ~= nil then
        local changed = (_last[key] ~= payload)
        _last[key] = payload
        if not changed then
            if (os.time() - _load_t) >= WINDOW_S then return end
            local c = _kcount[key] or 0
            if c >= PERKEY_CAP then return end
            _kcount[key] = c + 1
        end
    end
    _raw("[" .. tostring(tag) .. "] " .. payload)
end

-- Single-line, sanitized caller hint: "basename:line<-basename:line<-...".
-- Walks up the stack from `start` for `depth` frames. pcall-guarded — a C frame
-- returns nil, we stop.
function M.caller_hint(start, depth)
    start = start or 2
    depth = depth or 4
    local parts = {}
    for lvl = start, start + depth - 1 do
        local ok, info = pcall(debug.getinfo, lvl, "Sl")
        if not ok or not info then break end
        local src = tostring(info.short_src or info.source or "?")
        src = src:gsub("^.*[/\\]", ""):gsub("%s+", "")
        parts[#parts + 1] = src .. ":" .. tostring(info.currentline)
    end
    if #parts == 0 then return "<no-frames>" end
    return table.concat(parts, "<-")
end

return M
