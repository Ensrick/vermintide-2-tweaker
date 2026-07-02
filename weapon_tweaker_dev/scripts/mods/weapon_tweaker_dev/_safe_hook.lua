--[[
weapon_tweaker / _safe_hook.lua — pcall-isolated hook wrapper (Issue #26).

Why this exists
---------------
VMF's hook chain dispatch (`scripts/mods/vmf/modules/core/hooks.lua`) wraps
each registered `mod:hook` body so multiple mods can stack on the same
`(Class, method)`. Internally it does `hook_data.handler(previous_hook, ...)`
WITHOUT pcall — the only xpcall layer is VMF's outermost `safe_call_nr` for
the `HOOK_TYPE_SAFE` post-callback, NOT the chain-walking path that every
`mod:hook` consumer uses.

Consequence: a single raise inside consumer A's `mod:hook` body propagates
up the chain, kills every later consumer's `mod:hook` registration on the
same target silently (no log, no error, just stops working), and may pollute
the engine's call stack mid-frame.

In-the-wild symptom (Issue #26): cosmetics_tweaker hook A raises -> wt hook
B never fires -> user sees a missing feature with no diagnostic, no error
log line, no Crashify entry. The diagnostic-cost is hours.

What this helper does
---------------------
`mod:safe_hook(Class, method, handler)` is a drop-in replacement for
`mod:hook` — same signature, same chaining semantics. It installs a thin
VMF `mod:hook` wrapper that runs `handler(func, ...)` under xpcall. On error
it logs via `mod:error("[wt:safe_hook] ...")` + stack trace, then calls the
inner `func(...)` so the original engine path continues. The chain is NOT
broken — subsequent mods' hooks still fire.

`mod:safe_hook_safe(Class, method, handler)` is the analogous wrapper for
`mod:hook_safe`. VMF already runs hook_safe bodies under xpcall internally
(`HOOK_TYPE_SAFE` path in hooks.lua), so this layer is mostly redundant for
isolation — but it adds the same per-mod-prefixed error log line so a raise
attributes to the right consumer in the log.

Lua 5.1 multi-return preservation
---------------------------------
This wrapper is exposed to a bug class warned about in
`VMF_RECIPES.md § 2a`: variadic capture also needs nil-hole-safe unpack.
DO NOT "simplify" the capture pattern in `mod.safe_hook` without re-reading
that section. Three load-bearing rules drive the current shape:

1. `xpcall(handler, _error_handler, func, ...)` returns
   `(ok, r1, r2, ..., rN)` — the success flag is **positional index 1**.
   Anything that wants `handler`'s actual returns has to start at index 2
   AND know where to stop, because real returns may be nil anywhere.
2. Bare `unpack(results, 2)` is the WRONG fix and was tried in v0.12.78.
   It defaults to `j = #results`, and Lua 5.1's `#table` is **undefined**
   for arrays with nil holes — the result of `#{true, w3p, nil, w1p, nil}`
   may resolve to 1, 2, 4, or 5 depending on table history. Truncation is
   silent; downstream consumers see randomly-nil unit handles.
3. The right fix uses `select("#", ...)` to read the **actual** arity from
   the source variadic at the point it's captured (before nils become
   indistinguishable from "no entry"), then passes that count as `j` to
   `unpack(results, 2, n)`. See the `_capture` closure inside `mod.safe_hook`
   below — that's the canonical pattern.

Canonical 4-return example with nil holes: `GearUtils.spawn_inventory_unit`
(`Vermintide-2-Source-Code/scripts/unit_extensions/default_player_unit/inventory/gear_utils.lua:273`)
returns `(weapon_3p, ammo_3p, weapon_1p, ammo_1p)` where the two `ammo_*`
slots are nil for melee weapons. That nil-hole tuple was exactly what
broke the v0.12.78 implementation; the v0.12.79 fix below preserves it.

Burn history: v0.12.77 (Issue #26) introduced `safe_hook` with returns 2+
collapsed → v0.12.78 swapped to `unpack(results, 2)` → v0.12.79 added
`select("#", ...)` to get a real `j`. All shipped on 2026-05-25, two hours
apart. See `VMF_RECIPES.md § 2a`, `CLAUDE.md` § "High-frequency engine
quirks" (`#table` quirk bullet), and `PROJECT_STANDARDS.md § 9.9` for the
cross-doc treatment.

Consumer-isolation principle
----------------------------
A consumer's bug should kill that consumer's behavior ONLY. It must not
silently take out unrelated downstream mod hooks on the same target. This
helper enforces that contract for `mod:hook`. Wider rollout (cross-mod
sharing, VMF-side patch) is a Wave-2 concern; for v1 this is self-contained
per mod by design.

Layer 3: traced_hook (v0.12.84-dev)
-----------------------------------
`mod:traced_hook(class, method, handler)` and
`mod:traced_hook_safe(class, method, handler)` are Layer-3 wrappers that
delegate to `safe_hook` / `safe_hook_safe` (Layer 2) AND emit structured
`[wt:trace] event=enter|exit class=<C> method=<m> n_args=N` log lines
routed through `mod:debug` (VMF output_mode_debug controls visibility).
The wrapper is semantically identical to `safe_hook` — same multi-return
preservation (delegated to safe_hook's `select("#", ...)` + explicit-`j`
unpack pattern, not re-implemented here), same pcall isolation, same error
log prefix.

Adopt `traced_hook` when you want fire-confirmation + return-shape
visibility at a specific Class.method (i.e. "did the hook fire? did it
return what I expected?"). The wt safe_hook v0.12.77 / v0.12.78 bug
cycle would have surfaced in one /wt_regression_test run with the trace
lines on — that's the use case.

RATE-LIMIT CAVEAT: do NOT wrap per-frame hooks (`mod.update`, frame-rate
state hooks, etc.) in `traced_hook`. They fire 60+ times/sec and would
flood the log when the toggle is on. Per-frame hooks stay on `safe_hook`
and document the why in a comment.

See also: `VMF_RECIPES.md` "Pcall-isolated hooks (mod:safe_hook)".
Issue: https://github.com/Ensrick/vermintide-2-tweaker/issues/26
]]

local mod = get_mod("wt_dev")

-- Marker constant the /wt_regression_test "wt_safe_hook_installed" check
-- reads to prove this module was loaded and `mod.safe_hook` was attached.
-- Format mirrors the v0.12.73 RAWGET marker convention.
CT_WT_SAFE_HOOK_MARKER_v0_12_74 = "wt-safe-hook-pcall-isolated"

-- Error handler for xpcall. Returns a string so the outer caller can log it.
-- Capturing the callstack inside the handler (BEFORE the stack unwinds) is the
-- whole reason xpcall exists — by the time pcall's `false, err` returns, the
-- stack is already gone.
local function _error_handler(err)
    local trace = (Script and Script.callstack and Script.callstack()) or "<no callstack>"
    return tostring(err) .. "\n" .. tostring(trace)
end

-- Drop-in replacement for `mod:hook(class, method, handler)`.
-- Signature: handler(func, ...) -> any returns (just like vanilla mod:hook).
-- On error: logs `[wt:safe_hook] <class>.<method> raised: <err>` and calls
-- func(...) so the chain continues with original behavior.
--
-- Args:
--   class:   string or table (whatever mod:hook accepts).
--   method:  string method name.
--   handler: function(func, ...) -> returns.
function mod.safe_hook(self, class, method, handler)
    if type(handler) ~= "function" then
        self:error("[wt:safe_hook] handler for %s.%s is not a function (got %s)",
            tostring(class), tostring(method), type(handler))
        return
    end
    return self:hook(class, method, function(func, ...)
        -- v0.12.79 SECOND-PASS FIX: v0.12.78's `unpack(results, 2)` was still
        -- broken — without an explicit `j` argument, unpack defaults to
        -- `j = #results`. In Lua 5.1, `#t` is UNDEFINED for arrays with nil
        -- holes (`{true, weapon_3p, nil, weapon_1p, nil}` from
        -- `GearUtils.spawn_inventory_unit`'s melee-weapon return has non-
        -- deterministic length). Truncation was random — caused intermittent
        -- nil-weapon-units → infinity ammo HUD + corrupted 1P rendering, only
        -- visible when CWV's chained `mod:hook` consumed the truncated tuple
        -- and re-emitted the nil values.
        --
        -- Fix: capture the actual return count via `select("#", ...)` and pass
        -- it as `j` to unpack so nil holes are preserved.
        local function _capture(...) return select("#", ...), { ... } end
        local n, results = _capture(xpcall(handler, _error_handler, func, ...))
        if results[1] then
            return unpack(results, 2, n)  -- explicit j preserves nil holes
        end
        -- Body raised. Log + fall through to vanilla so the engine path and
        -- every later consumer in the chain stays intact.
        self:error("[wt:safe_hook] %s.%s raised: %s",
            tostring(class), tostring(method), tostring(results[2]))
        return func(...)
    end)
end

-- Drop-in replacement for `mod:hook_safe(class, method, handler)`.
-- Signature: handler(...) -> ignored (no return value, runs after the chain).
-- On error: logs and swallows (matches VMF's existing hook_safe semantics).
function mod.safe_hook_safe(self, class, method, handler)
    if type(handler) ~= "function" then
        self:error("[wt:safe_hook_safe] handler for %s.%s is not a function (got %s)",
            tostring(class), tostring(method), type(handler))
        return
    end
    return self:hook_safe(class, method, function(...)
        local ok, err = xpcall(handler, _error_handler, ...)
        if not ok then
            self:error("[wt:safe_hook_safe] %s.%s raised: %s",
                tostring(class), tostring(method), tostring(err))
        end
    end)
end

-- v0.12.84-dev: Layer 3 marker. /wt_regression_test "wt_traced_hook_present"
-- reads this to prove the traced_hook module was loaded and both methods
-- were attached. Format mirrors CT_WT_SAFE_HOOK_MARKER_v0_12_74.
CT_WT_TRACED_HOOK_MARKER_v0_12_84 = "wt-traced-hook-layer3-installed"

-- Layer 3: traced_hook — safe_hook PLUS structured entry/exit log lines
-- gated on `enable_debug_logging`. Use when you want fire-confirmation +
-- return-shape visibility at a specific Class.method. Do NOT use on
-- per-frame hooks — see header "RATE-LIMIT CAVEAT".
--
-- Delegates to safe_hook for pcall isolation + multi-return preservation.
-- Does NOT re-implement either — there's one canonical
-- select("#", ...) + unpack(..., j) site, in safe_hook.
--
-- Args:
--   class:   string or table (whatever mod:hook accepts).
--   method:  string method name.
--   handler: function(func, ...) -> returns.
function mod.traced_hook(self, class, method, handler)
    if type(handler) ~= "function" then
        self:error("[wt:traced_hook] handler for %s.%s is not a function (got %s)",
            tostring(class), tostring(method), type(handler))
        return
    end
    -- Layer 2 (safe_hook) is the base. We layer the trace lines on top by
    -- wrapping the user's handler in a tracing closure, then handing that
    -- closure to safe_hook. safe_hook owns the pcall + select("#", ...) +
    -- unpack-with-explicit-j contract; we just observe.
    return self:safe_hook(class, method, function(func, ...)
        local n_args = select("#", ...)
        mod:debug("[wt:trace] event=enter class=%s method=%s n_args=%d",
            tostring(class), tostring(method), n_args)
        -- Run the user handler. Capture every return into a packed array +
        -- explicit count so we can both log n_returned AND return the tuple
        -- intact. Same idiom safe_hook uses internally for xpcall returns.
        local function _capture(...) return select("#", ...), { ... } end
        local n_returned, results = _capture(handler(func, ...))
        mod:debug("[wt:trace] event=exit  class=%s method=%s n_returned=%d",
            tostring(class), tostring(method), n_returned)
        -- Explicit j (n_returned) preserves nil holes — same Lua 5.1 #table
        -- quirk that motivated safe_hook's unpack(results, 2, n) pattern.
        return unpack(results, 1, n_returned)
    end)
end

-- Layer 3 analog for hook_safe (post-callback, no return-value handling).
-- Delegates to safe_hook_safe. Same trace lines, routed through mod:debug.
function mod.traced_hook_safe(self, class, method, handler)
    if type(handler) ~= "function" then
        self:error("[wt:traced_hook_safe] handler for %s.%s is not a function (got %s)",
            tostring(class), tostring(method), type(handler))
        return
    end
    return self:safe_hook_safe(class, method, function(...)
        local n_args = select("#", ...)
        mod:debug("[wt:trace] event=enter class=%s method=%s n_args=%d",
            tostring(class), tostring(method), n_args)
        handler(...)
        mod:debug("[wt:trace] event=exit  class=%s method=%s n_returned=0",
            tostring(class), tostring(method))
    end)
end

mod:info("[wt:safe_hook] installed (marker=%s)", CT_WT_SAFE_HOOK_MARKER_v0_12_74)
mod:info("[wt:traced_hook] installed (marker=%s)", CT_WT_TRACED_HOOK_MARKER_v0_12_84)
