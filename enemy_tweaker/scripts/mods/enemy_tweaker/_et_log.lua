local mod = get_mod("enemy_tweaker")

-- _et_log.lua — logging helpers: dbg / alert / chat / spawn channels + printf probe
--
-- Two-helper debug-logging policy (PROJECT_STANDARDS.md § 3.6, et log-only
-- alert variant per Issue #240), the per-spawn debug channels, and the
-- rate-limited engine-printf probe that survives mod-logging-OFF sessions.
--
-- Owned by: enemy_tweaker.lua entry point (dofile'd before _et_protect — the
-- protective wrappers alert through dbg_alert). Consumed via mod._et exports:
-- dbg, dbg_alert, chat_alert, spawn_dbg, spawn_dbg_alert, et_probe.

local ET = mod._et
local rt_register = ET.rt_register

-- `_dbg` is for confirmation / expected behavior — mod:debug channel
-- (log-only under VMF defaults; off unless the user raises VMF's log level).
local function _dbg(fmt, ...)
    mod:debug("[et:dbg] " .. fmt, ...)
end

-- v0.7.25-dev (#240): _dbg_alert is now ACTUALLY log-only, via engine printf.
-- v0.7.0-dev routed it through mod:warning believing the warning channel was
-- file-only; it is not — VMF logging.lua load_logging_settings() defaults
-- warning to mode 3 with send_to_chat = mode >= 2, so every alert posted to
-- chat (the 2026-07-02 chat-spam report: roaming-plateau line on every
-- mission load). printf always lands in console-*.log (even with mod logging
-- OFF) and never in chat. pcall-guarded like _et_probe so a format slip can
-- never fault the caller. Chat is reserved for `_chat_alert` below —
-- genuinely surprising conditions only.
mod._et_alerts_log_only_marker = "et-alert-helpers-log-only-printf-240"
local function _dbg_alert(fmt, ...)
    if not pcall(printf, "[et:dbg] " .. fmt, ...) then
        pcall(printf, "[et:dbg] (alert format error: %s)", tostring(fmt))
    end
end

-- _chat_alert(fmt, ...) — chat + log. ONLY call from genuinely surprising
-- paths the user must see live: hook fallback fired (pcall'd vanilla
-- errored), boss-skip in event replication, ambients_ignore_threat
-- clobbering vanilla state, hook install failure.
-- v0.7.25-dev (#240): dropped the mod:warning half — VMF's echo channel
-- (default mode 3) already writes chat AND log, so warning + echo
-- double-posted to chat under default settings.
local function _chat_alert(fmt, ...)
    mod:echo("[et] " .. fmt, ...)
end

-- _spawn_dbg(channel, fmt, ...) — aggressive per-spawn debug trace, routed
-- through mod:debug (gated by VMF output_mode_debug). Channels: paced / event / roaming / patrol /
-- unit / refresh. Stable prefix lets post-mission logs be grepped per
-- channel: `grep '\[et:spawn:event\]' console_log-*.log`.
local function _spawn_dbg(channel, fmt, ...)
    mod:debug("[et:spawn:" .. tostring(channel) .. "] " .. fmt, ...)
end

-- _spawn_dbg_alert(channel, fmt, ...) — _spawn_dbg variant for unexpected
-- spawn-side conditions: missing pack data, oversize patrols past navmesh
-- limits, breed-swap miss, fallback paths. The "we did something but it
-- might not have done what you wanted" moments.
-- v0.7.25-dev (#240): ACTUALLY log-only via engine printf (see _dbg_alert
-- above). v0.7.0-dev's mod:warning routing posted to chat under VMF default
-- logging — these fire per-IP / per-spawn-event / per-pack, dozens of chat
-- lines per zone load at high multipliers. Use `_chat_alert` for
-- chat-worthy surprises.
local function _spawn_dbg_alert(channel, fmt, ...)
    local prefix = "[et:spawn:" .. tostring(channel) .. "] "
    if not pcall(printf, prefix .. fmt, ...) then
        pcall(printf, prefix .. "(alert format error: %s)", tostring(fmt))
    end
end

-- _et_probe(key, fmt, ...) — direct engine console print for diagnostics that
-- MUST survive a mod-logging-OFF session. The user plays with VMF logging OFF,
-- so mod:info / mod:warning / mod:debug NEVER reach the handed-over console log
-- (memory reference_vt2_diagnostics_use_printf_not_modinfo). The engine global
-- `printf` (used by vanilla itself, e.g. scripts/managers/conflict_director/
-- breed_freezer.lua:119) always writes to console-*.log regardless of VMF state.
-- Rate-limited per `key` to a few lines/min so a hot path cannot flood the log;
-- pcall-guarded so a format slip can never fault the caller. Reserve for probes
-- that must be visible with logging off — routine confirmation still uses _dbg.
local _PROBE_MIN_INTERVAL = 12  -- seconds between prints of the same key (~5/min)
local _probe_last_t = {}
local function _et_probe(key, fmt, ...)
    local t
    if Managers and Managers.time then
        local ok, tt = pcall(Managers.time.time, Managers.time, "game")
        if ok and type(tt) == "number" then t = tt end
    end
    if t then
        local last = _probe_last_t[key]
        if last and (t - last) < _PROBE_MIN_INTERVAL then return end
        _probe_last_t[key] = t
    end
    -- t == nil (no game clock yet): fail OPEN and print, never drop the datum.
    if not pcall(printf, "[et] " .. fmt, ...) then
        pcall(printf, "[et] (probe format error, key=%s)", tostring(key))
    end
end

ET.dbg = _dbg
ET.dbg_alert = _dbg_alert
ET.chat_alert = _chat_alert
ET.spawn_dbg = _spawn_dbg
ET.spawn_dbg_alert = _spawn_dbg_alert
ET.et_probe = _et_probe

rt_register("dbg_helpers_two_channel", function()
    if type(_dbg) ~= "function" then return "_dbg helper missing" end
    if type(_dbg_alert) ~= "function" then return "_dbg_alert helper missing" end
    local ok = pcall(_dbg, "smoke test off")
    if not ok then return "_dbg raised with toggle off" end
    ok = pcall(_dbg_alert, "smoke test off")
    if not ok then return "_dbg_alert raised with toggle off" end
end)

rt_register("et_alert_helpers_log_only_240", function()
    -- Issue #240: _dbg_alert/_spawn_dbg_alert must never post to chat. They
    -- route through raw engine printf (log-only, survives mod-logging-OFF);
    -- the marker guards a revert to the v0.7.0-dev mod:warning routing, which
    -- VMF sends to CHAT under default settings (logging.lua
    -- load_logging_settings: warning mode 3, send_to_chat = mode >= 2).
    if mod._et_alerts_log_only_marker ~= "et-alert-helpers-log-only-printf-240" then
        return "log-only alert marker missing - alert helpers may have reverted to chat-visible mod:warning"
    end
    if type(_chat_alert) ~= "function" then return "_chat_alert helper missing" end
    local ok = pcall(_spawn_dbg_alert, "rt", "regression smoke %d", 240)
    if not ok then return "_spawn_dbg_alert raised on smoke call" end
end)

rt_register("et_freeze_probe_present", function()
    -- Issue #213: the double-freeze guard's probe must reach engine printf so it
    -- is visible with mod logging OFF. Guards against a revert that drops the
    -- _et_probe helper (which would send the probe back through invisible VMF
    -- logging) or removes the per-frame suppression counter.
    if type(_et_probe) ~= "function" then return "_et_probe helper missing" end
    local ok = pcall(_et_probe, "rt_smoke", "regression smoke")
    if not ok then return "_et_probe raised on smoke call" end
end)
