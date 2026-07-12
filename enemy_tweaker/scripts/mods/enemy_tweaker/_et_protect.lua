local mod = get_mod("enemy_tweaker")

-- _et_protect.lua — protective wrappers + multiplier math
--
-- Protective layer (v0.6.0-dev — PROJECT_STANDARDS § 4.1): nothing in
-- enemy_tweaker fails silently. Every hook body, every runtime apply
-- function, every global-table mutation is bracketed so that any unexpected
-- engine state produces a log entry rather than a silent no-op or an
-- unhandled crash. Also home of the issue 479 tick-guard variant: hooks on
-- NON-RE-RUNNABLE vanilla functions (ConflictDirector.update) must never
-- fall back to a second vanilla invocation for the same tick.
--
-- Owned by: enemy_tweaker.lua entry point (dofile'd after _et_log). Consumed
-- via mod._et exports: safe, hook_wrap, hook_wrap_table, hook_wrap_tick,
-- mult, scale_count; plus mod fields _et479_make_tick_guard /
-- _et479_call_with_override (exposed for the issue 479 regression check).

local ET = mod._et
local rt_register = ET.rt_register
local _dbg_alert  = ET.dbg_alert

-- Registration provenance (issue 479, v0.7.33-dev). Records which (class,
-- method) pairs were installed through each wrapper so the regression suite can
-- assert the CD tick uses the NO-RE-RUN tick guard (not the re-running
-- _hook_wrap) WITHOUT reading source. The VMF Lua sandbox exposes NO `io`
-- library (verified: the v0.7.31-dev io.open self-grep threw "attempt to index
-- global 'io' (a nil value)" and failed the whole check in-game), so source
-- self-grep is not a viable regression technique here. ConflictDirector and
-- BreedFreezer are boot globals (conflict_director.lua:70,
-- breed_freezer.lua:77 -- `class(...)` at file scope), so these markers are set
-- at mod load, before any mission, and are readable when /et_regression_test
-- runs at the keep.
ET.wrap_registry = ET.wrap_registry or { plain = {}, tick = {} }
local _wrap_registry = ET.wrap_registry
local function _reg_key(class, method) return tostring(class) .. "." .. tostring(method) end

-- _safe(label, fn, ...) — call fn(...) under pcall. On failure log a
-- mod:warning + a log-only _dbg_alert line (visible even with mod logging
-- OFF) and return nil. Use for any mod-side helper that touches engine
-- tables (Breeds, HordeCompositions*, ConflictDirectors, Current* settings,
-- SizeOfInterestPoint, PatrolFormationSettings).
local function _safe(label, fn, ...)
    local ok, a, b, c, d = pcall(fn, ...)
    if not ok then
        local err = tostring(a)
        mod:warning("[et:safe] %s failed: %s", tostring(label), err)
        _dbg_alert("safe-call %s failed: %s", tostring(label), err)
        return nil
    end
    return a, b, c, d
end

-- _hook_wrap(class, method, label, body) — wraps body in pcall and falls
-- through to vanilla `func(self, ...)` on any error. Logs mod:warning + an
-- _dbg_alert with the label. body receives (func, self, ...) same as
-- mod:hook. PROJECT_STANDARDS § 4.1 + § 4.2: bailing must call vanilla so
-- the engine's normal mutation still happens; an early-return guard is the
-- canonical regression class in this repo.
-- CAVEAT (issue 479): this fallback RE-RUNS vanilla, which is only safe for
-- IDEMPOTENT targets. For per-tick targets whose state mutates mid-call
-- (ConflictDirector.update's spawn queue), use _hook_wrap_tick below.
local function _hook_wrap(class, method, label, body)
    mod:hook(class, method, function(func, self, ...)
        local ok, r1, r2, r3, r4 = pcall(body, func, self, ...)
        if ok then return r1, r2, r3, r4 end
        local err = tostring(r1)
        mod:warning("[et:hook] %s (%s.%s) inner errored: %s — bailing to vanilla",
            tostring(label), tostring(class), tostring(method), err)
        _dbg_alert("hook %s (%s.%s) errored: %s", tostring(label), tostring(class), tostring(method), err)
        local fall_ok, fr1, fr2, fr3, fr4 = pcall(func, self, ...)
        if fall_ok then return fr1, fr2, fr3, fr4 end
        mod:warning("[et:hook] %s vanilla fallback ALSO errored: %s",
            tostring(label), tostring(fr1))
        _dbg_alert("hook %s vanilla fallback errored: %s", tostring(label), tostring(fr1))
        return nil
    end)
    _wrap_registry.plain[_reg_key(class, method)] = true
end

-- _hook_wrap_table(class_table, method, label, body) — table-form variant
-- for plain-table dispatchers (SpecialsPacing.setup_functions / .select_breed_functions).
-- body receives (func, ...) with NO `self` arg, matching the vanilla call
-- convention for these dispatcher tables.
local function _hook_wrap_table(class_table, method, label, body)
    mod:hook(class_table, method, function(func, ...)
        local ok, r1, r2, r3, r4 = pcall(body, func, ...)
        if ok then return r1, r2, r3, r4 end
        local err = tostring(r1)
        mod:warning("[et:hook] %s (table.%s) inner errored: %s — bailing to vanilla",
            tostring(label), tostring(method), err)
        _dbg_alert("hook %s errored: %s", tostring(label), err)
        local fall_ok, fr1, fr2, fr3, fr4 = pcall(func, ...)
        if fall_ok then return fr1, fr2, fr3, fr4 end
        mod:warning("[et:hook] %s vanilla fallback ALSO errored: %s",
            tostring(label), tostring(fr1))
        return nil
    end)
end

-- ============================================================
-- Issue 479 — tick-safe hook wrapper (NO vanilla re-run on error)
-- ============================================================
-- ConflictDirector.update is NOT re-runnable within a frame: its spawn-queue
-- bookkeeping runs AFTER _spawn_unit (ConflictDirector.update_spawn_queue,
-- conflict_director.lua:1835-1891 — num_queued_spawn_by_breed decrement,
-- spawn_queue_size decrement and first_spawn_index advance all happen after
-- the spawn call), so a spawn that throws stays queued; _hook_wrap's vanilla
-- fallback then re-ran the SAME tick, re-popped the same entry, re-threw,
-- and doubled partial state (evidence: the #470 crash session, i470.log
-- 158014-158017 — "inner errored ... bailing to vanilla" followed by
-- "vanilla fallback ALSO errored"). Guard-that-delegates class (issue 270).
--
-- _make_tick_guard builds the hook callback: body runs under pcall; on ANY
-- inner error the tick is SKIPPED — one [et:479] printf + mod:warning, no
-- second vanilla invocation. The body is responsible for restoring any
-- engine-global overrides on its own error path (see _et_pacing.lua's use of
-- _call_with_override). Factory is exposed for the regression check.
local function _make_tick_guard(class, method, label, body)
    return function(func, self, ...)
        local ok, r1, r2, r3, r4 = pcall(body, func, self, ...)
        if ok then return r1, r2, r3, r4 end
        local err = tostring(r1)
        mod:warning("[et:hook] %s (%s.%s) inner errored: %s — tick SKIPPED (issue 479: vanilla NOT re-run)",
            tostring(label), tostring(class), tostring(method), err)
        pcall(printf, "[et:479] skipped %s tick after inner error (no vanilla re-run; overrides restored): %s",
            tostring(label), err)
        return nil
    end
end
mod._et479_make_tick_guard = _make_tick_guard

local function _hook_wrap_tick(class, method, label, body)
    mod:hook(class, method, _make_tick_guard(class, method, label, body))
    _wrap_registry.tick[_reg_key(class, method)] = true
end

-- _call_with_override(rs, field, override, func, self, ...) — pure + testable
-- (issue 479): call `func(self, ...)` EXACTLY ONCE under pcall with
-- rs[field] temporarily set to `override` (skipped when override == nil);
-- the prior value is restored on BOTH the success and the error path — the
-- pre-479 code restored only on success, leaking the RecycleSettings
-- .max_grunts override for the session when vanilla threw. Returns the
-- pcall-shaped (ok, r1, r2, r3, r4).
local function _call_with_override(rs, field, override, func, self, ...)
    local original
    if rs and override ~= nil then
        original = rs[field]
        rs[field] = override
    end
    local ok, r1, r2, r3, r4 = pcall(func, self, ...)
    if rs and override ~= nil then
        rs[field] = original
    end
    return ok, r1, r2, r3, r4
end
mod._et479_call_with_override = _call_with_override

-- _mult(setting_id) — read a 0-15 decimal multiplier; clamp; default 1
-- on missing/invalid. Returns (multiplier, is_zero).
local function _mult(setting_id)
    local raw = mod:get(setting_id)
    local m
    if type(raw) == "number" then
        m = raw
    elseif raw == nil then
        m = 1
    else
        m = tonumber(raw)
        if m == nil then
            _dbg_alert("setting %s has non-numeric value %s — using 1",
                tostring(setting_id), tostring(raw))
            m = 1
        end
    end
    if m < 0 then m = 0 end
    if m > 15 then m = 15 end
    return m, (m == 0)
end

-- _scale_count(base, mult) — round-to-nearest with mult=1 fast path and
-- mult=0 hard suppress. Used by every spawn-scaling hook.
local function _scale_count(base, mult)
    if mult == 1 then return base end
    if mult == 0 then return 0 end
    return math.max(0, math.floor((base or 0) * mult + 0.5))
end

ET.safe = _safe
ET.hook_wrap = _hook_wrap
ET.hook_wrap_table = _hook_wrap_table
ET.hook_wrap_tick = _hook_wrap_tick
ET.mult = _mult
ET.scale_count = _scale_count

rt_register("spawn_scaling_helpers_present", function()
    if type(_mult) ~= "function"        then return "_mult helper missing" end
    if type(_scale_count) ~= "function" then return "_scale_count helper missing" end
    if type(_safe) ~= "function"        then return "_safe helper missing" end
    if type(_hook_wrap) ~= "function"   then return "_hook_wrap helper missing" end
    if type(ET.spawn_dbg) ~= "function"   then return "_spawn_dbg helper missing" end
    if type(ET.spawn_dbg_alert) ~= "function" then return "_spawn_dbg_alert helper missing" end
end)

rt_register("spawn_scaling_settings_registered", function()
    -- Each new slider must read back as a number with default 1.0 from
    -- mod:get. Default 1 = vanilla no-op; users who never touched the
    -- slider should see 1.0 here.
    for _, sid in ipairs({
        "horde_size_multiplier",
        "event_size_multiplier",
        "roaming_size_multiplier",
        "patrol_size_multiplier",
    }) do
        local v = mod:get(sid)
        if v == nil then return string.format("%s not registered (mod:get returned nil)", sid) end
        if type(v) ~= "number" then
            return string.format("%s returned non-number: %s (%s)", sid, type(v), tostring(v))
        end
        if v < 0 or v > 15 then
            return string.format("%s out of range [0, 15]: %s", sid, tostring(v))
        end
    end
end)

rt_register("scale_count_math", function()
    -- Sanity-check _scale_count: 0 suppresses, 1 passes through,
    -- decimal rounds to nearest.
    if _scale_count(10, 0) ~= 0      then return "_scale_count(10, 0) should be 0" end
    if _scale_count(10, 1) ~= 10     then return "_scale_count(10, 1) should be 10 (passthrough)" end
    if _scale_count(10, 1.5) ~= 15   then return "_scale_count(10, 1.5) should be 15" end
    if _scale_count(10, 0.1) ~= 1    then return "_scale_count(10, 0.1) should be 1" end
    if _scale_count(7, 15) ~= 105    then return "_scale_count(7, 15) should be 105" end
    if _scale_count(0, 5) ~= 0       then return "_scale_count(0, 5) should be 0" end
end)
