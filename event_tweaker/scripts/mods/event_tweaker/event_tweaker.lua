local mod = get_mod("event_tweaker")
local _mem_probe_t0 = collectgarbage("count")  -- [mem-probe] temp Lua-footprint baseline (lua_heap 1 GiB cap diagnostic)

local MOD_VERSION = "0.4.34-dev"

-- Startup banner: log-only, NOT chat. The applied marker line further down
-- ([event_tweaker:LOAD] v<X> enabled fp=<hash> OK) is the canonical version
-- surface (PROJECT_STANDARDS.md § 3.6 "Chat-echo policy").
mod:info("Tweaker: Events v%s loaded", MOD_VERSION)

-- ============================================================
-- Module manifest (v0.4.26-dev structural split)
-- ============================================================
-- This entry file owns MOD_VERSION (the launcher parses it from THIS file),
-- the load-time banner/echo lines, and the dofile manifest below. All logic
-- lives in single-responsibility `_evt_*` modules in this directory (prefix
-- `_evt_` because `_et_` already belongs to enemy_tweaker's modules).
--
-- Cross-module contract: `mod._evt` is the shared namespace. Each module is
-- dofile'd EXACTLY ONCE, in the order below, and publishes its exports into
-- mod._evt. VMF's mod:dofile is NOT a singleton -- every call re-executes the
-- file and returns a fresh value -- so modules must never dofile each other;
-- only this manifest loads them. Load order is load-bearing:
--   * _evt_log first (later modules localize dbg/dbg_alert at their top),
--   * _evt_regression before any module that registers a check,
--   * _evt_dlc + the injection guards (413 weave / 455 boss-event / 430 curse
--     peer-parity) before _evt_selection (selection localizes their exports,
--     incl. curse_wire_safe, at its top),
--   * _evt_selection before the hook / diagnostics / apply modules that call
--     its gather/preset accessors.
-- Regression checks print in registration order, so reordering this manifest
-- reorders /event_tweaker_regression_test output.
--
-- Pure data shared with event_tweaker_data.lua / _localization.lua lives in
-- require()'d modules instead (event_tweaker_catalog.lua /
-- event_tweaker_curses.lua): VMF loads localization -> data -> script (script
-- LAST), so nothing set here -- mod fields OR mod._evt -- exists yet when
-- those two files evaluate. require() is evaluated once and cached, so all
-- three registered files see the same tables regardless of load order.
mod._evt = { version = MOD_VERSION }

mod:dofile("scripts/mods/event_tweaker/_evt_log")                  -- _dbg/_dbg_alert helpers + settings fingerprint

-- Applied marker (PROJECT_STANDARDS.md § 3.6 "Applied marker line (universal)").
-- ALWAYS fires (operational telemetry).
mod:info("[event_tweaker:LOAD] v%s enabled fp=%s OK", MOD_VERSION, mod._evt.settings_fingerprint())

-- Per PROJECT_STANDARDS § 3.6 + § 14a: dev/alpha/beta/0.x versions print
-- version to chat on load so the user can see what's active. Stable
-- (>=1.0.0) versions stay silent. Detect via MOD_VERSION string match.
if MOD_VERSION:find("-dev$") or MOD_VERSION:find("-alpha$") or MOD_VERSION:find("-beta$") or MOD_VERSION:find("-rc%d*$") or MOD_VERSION:find("^0%.") then
    mod:echo(string.format("[event_tweaker] v%s loaded", MOD_VERSION))
end

mod:dofile("scripts/mods/event_tweaker/_evt_regression")           -- /event_tweaker_regression_test harness + generic checks
mod:dofile("scripts/mods/event_tweaker/_evt_dlc")                  -- DLC ownership gate (injection side, fail-closed)
mod:dofile("scripts/mods/event_tweaker/_evt_guard413_weave")       -- issue 413: weave-only mutator injection gate
mod:dofile("scripts/mods/event_tweaker/_evt_guard455_boss_events") -- issue 455: boss-event mutator guard
mod:dofile("scripts/mods/event_tweaker/_evt_guard430_curse_parity") -- issue 430: Cursed Adventure curse wire-safety floor (peer-parity beacon)
mod:dofile("scripts/mods/event_tweaker/_evt_selection")            -- preset/checkbox/discovery selection -> gather_mutators
mod:dofile("scripts/mods/event_tweaker/_evt_preview")              -- issue 532: Tab-hold active-mutator preview (IngamePlayerListUI)
mod:dofile("scripts/mods/event_tweaker/_evt_missions")              -- issue 626: allowlisted event missions in Own Game
mod:dofile("scripts/mods/event_tweaker/_evt_backend_hooks")        -- the three live-event backend hooks
mod:dofile("scripts/mods/event_tweaker/_evt_guard386_pacing")      -- issue 386: scalar pacing sanitizer
mod:dofile("scripts/mods/event_tweaker/_evt_diagnostics")          -- /event_probe /event_active /event_clear + issue 393 snapshot
mod:dofile("scripts/mods/event_tweaker/_evt_apply")                -- mid-game preset application + on_setting_changed
mod:dofile("scripts/mods/event_tweaker/_evt_cursed_adventure")     -- curse package preload + cursed-sky lighting

mod:info("[mem-probe] event_tweaker boot_lua=+%.1f MB (of ~1024 MB lua_heap cap)", (collectgarbage("count") - _mem_probe_t0) / 1024)
