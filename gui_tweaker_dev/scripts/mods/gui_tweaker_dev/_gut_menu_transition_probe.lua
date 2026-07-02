local mod = get_mod("gut_dev")

-- ============================================================================
-- MENU-TRANSITION probe (#124) — DIAGNOSTIC ONLY, no behavior change
-- ============================================================================
-- Makes the #124 fix ("Mod Tweaker exit returns to the GAME, not the equipment /
-- HeroView screen") SELF-VERIFYING. Instead of trusting the code-read that
-- exit(true) -> "exit_menu" lands the player in gameplay, this probe MEASURES the
-- real fired transition + the view the player actually lands on, every time the
-- Mod Tweaker is opened/closed. When the user exits, the [gut-menu-probe] EXIT line
-- shows the fired transition and the resulting current_view (nil == GAME) — proof,
-- not assumption.
--
-- ---- WHY printf (not mod:info) ---------------------------------------------
-- The user runs with mod logging OFF most of the time; mod:info is then invisible
-- (it already cost us the cutscene #106 and keybind #123 captures). `printf` is the
-- Stingray engine global, written to console + game log regardless of mod log level.
-- Tag: [gut-menu-probe] (grep-friendly).
--
-- ---- WHY NOT mod:hook_safe("ModTweakerView", ...) --------------------------
-- ModTweakerView is NEITHER a _G global NOR a dofile singleton:
--   * It's `local ModTweakerView = class(ModTweakerView)` (_mod_tweaker_view.lua:22)
--     with no _G publish — class.lua:23-49 builds a FRESH table because the global is
--     nil — so a VMF string-hook would error "trying to hook object that doesn't exist".
--   * `mod:dofile` re-executes the chunk + returns a FRESH class table each call (the
--     same gotcha _gut_glow_probe.lua:39-43 documents), so a table-hook on any one
--     dofile'd copy would miss the LIVE attached instance.
-- So enter/exit capture WRAPS the LIVE attached instance's own exit/on_enter
-- (instance-level shadow fields — isolated to that one instance, idempotent), reached
-- via the canonical IngameUI.views.mod_tweaker_view handle. The actual transition
-- sequence is captured on the stable engine globals below.
--
-- ---- HOOK PRE-FLIGHT (VMF no-duplicate-hook rule) --------------------------
-- Hooks IngameUI.transition_with_fade + IngameUI.handle_transition (both hook_safe).
-- Whole-mod grep before adding: gut hooks IngameUI.setup_views
-- (gui_tweaker_dev.lua) and IngameUI.update (_gut_glow_probe.lua) — DIFFERENT methods,
-- so no (Class,method) collision. transition_with_fade / handle_transition are hooked
-- NOWHERE ELSE in gut. IngameUI is loaded in keep AND mission, so the string-form hook
-- resolves in both (unlike the in-mission-only hud_ui classes).

local _printf = rawget(_G, "printf") or function(fmt, ...) print(string.format(fmt, ...)) end

-- Bounded: cap total emitted lines so a long session can't spam the log unbounded.
local _MAX_LINES = 600
local _n = 0
local function _log(fmt, ...)
    if _n >= _MAX_LINES then return end
    _n = _n + 1
    local ok, s = pcall(string.format, "[gut-menu-probe] " .. fmt, ...)
    _printf(ok and s or ("[gut-menu-probe] (format error) " .. tostring(fmt)))
    if _n == _MAX_LINES then
        _printf(string.format("[gut-menu-probe] line cap (%d) reached; suppressing further lines", _MAX_LINES))
    end
end

local MT_VIEW = "mod_tweaker_view"

-- (#173 Probe B3) Read-only residency check for the character-selection level backdrop.
-- HISTORY: the first B3 revision passed a "gut_probe" reference_name to has_loaded --
-- reference-scoped semantics (package_manager.lua:286-294: with a ref it is true ONLY if
-- THAT ref loaded it) made it always-false, so all data it produced was VOID. Now queries
-- global residency (no ref). ALSO: the 2026-07-02 bundle listing
-- (vt2_bundle_unpacker/all_bundles_listing.txt) proved there is NO
-- `resource_packages/levels/ui_character_selection.package` anywhere in the game files --
-- the .level exists only inside hub/menu bundles -- so has_loaded on this path is expected
-- false/void everywhere; the load-bearing signal is the Application.can_get("level", ...)
-- boolean added to the same line (vanilla's non-faulting existence check; arg order
-- (type, name) per pickup_system.lua:882). can_get=true where the level is actually
-- gettable (keep) vs false in missions is the residency ground truth the C7 rewire
-- (_gut_mission_hero_select.lua) forks on.
local CHARSEL_PKG   = "resource_packages/levels/ui_character_selection"
local CHARSEL_LEVEL = "levels/ui_character_selection/world"
local _b3_last = nil   -- edge latch: "<level_key>|<residency>|<can_get>" already logged (de-spam)

-- Module state: are we currently INSIDE the Mod Tweaker view (per the engine)? Set on
-- open, used so the very next transition away is recognised + logged as the EXIT.
local _in_mt = false

-- A transition is probe-relevant if it OPENS the Mod Tweaker or FIRES FROM it.
local function _relevant(target, origin)
    return target == MT_VIEW or origin == MT_VIEW
end

-- Wrap the LIVE attached ModTweakerView instance's exit/on_enter so we can read the
-- view-internal values the #124 fix turns on (return_to_game, params.exit_transition,
-- self._exit_transition, the computed final transition). Instance-level shadow fields
-- (not the class table) keep this isolated to the one live instance; idempotent guard.
local function _instrument_live_view(ingame_ui)
    local view = ingame_ui and ingame_ui.views and ingame_ui.views[MT_VIEW]
    if type(view) ~= "table" or rawget(view, "_gut_menu_probe_wrapped") then return end

    -- exit(return_to_game): mirror the view's own transition math so we log the EXACT
    -- string about to fire, BEFORE vanilla fires it.
    local orig_exit = view.exit  -- resolves the class method via __index (instance has none yet)
    if type(orig_exit) == "function" then
        view.exit = function(self, return_to_game, ...)
            pcall(function()
                local transition = (return_to_game and "exit_menu") or self._exit_transition or "ingame_menu"
                _log("VIEW:exit return_to_game=%s self._exit_transition=%s -> final_transition=%s",
                    tostring(return_to_game), tostring(self._exit_transition), tostring(transition))
            end)
            return orig_exit(self, return_to_game, ...)
        end
    end

    -- on_enter(params): run vanilla first so _exit_transition has settled, then log.
    local orig_on_enter = view.on_enter
    if type(orig_on_enter) == "function" then
        view.on_enter = function(self, params, ...)
            local a, b, c = orig_on_enter(self, params, ...)
            pcall(function()
                local iu = Managers and Managers.ui and Managers.ui._ingame_ui
                _log("VIEW:on_enter params.exit_transition=%s self._exit_transition=%s live_current_view=%s",
                    tostring(params and params.exit_transition), tostring(self._exit_transition),
                    tostring(iu and iu.current_view))
            end)
            return a, b, c
        end
    end

    rawset(view, "_gut_menu_probe_wrapped", true)
    _log("instrumented live ModTweakerView instance (exit/on_enter wrapped)")
end

-- (a) Intent: transition_with_fade is the INITIAL request (the fade hasn't yet fired
-- handle_transition, so self.current_view is still the ORIGIN here). The view's exit()
-- routes through this (self.ingame_ui:transition_with_fade(transition)), so the exit's
-- fired target shows up here too.
mod:hook_safe("IngameUI", "transition_with_fade", function(self, new_transition, params)
    pcall(function()
        local origin = self.current_view
        if not _relevant(new_transition, origin) then return end
        local view = self.views and self.views[MT_VIEW]
        _log("FADE-REQUEST target=%s origin_current_view=%s params.exit_transition=%s view._exit_transition=%s view._active=%s",
            tostring(new_transition), tostring(origin),
            tostring(params and params.exit_transition),
            tostring(view and view._exit_transition), tostring(view and view._active))
    end)
end)

-- (b) Landing: handle_transition (hook_safe = AFTER vanilla) — self.current_view is now
-- the RESULTING view. This is where the player actually lands. transition_with_fade
-- routes here once the fade completes, and non-fade transitions come straight here.
mod:hook_safe("IngameUI", "handle_transition", function(self, new_transition, params)
    pcall(function()
        local landing = self.current_view  -- post-vanilla: the resulting view (nil == game)
        local view = self.views and self.views[MT_VIEW]
        if new_transition == MT_VIEW or landing == MT_VIEW then
            _in_mt = true
            _instrument_live_view(self)
            _log("OPEN  fired_target=%s -> current_view=%s view._exit_transition=%s view._active=%s",
                tostring(new_transition), tostring(landing),
                tostring(view and view._exit_transition), tostring(view and view._active))
        elseif _in_mt then
            -- We were in the Mod Tweaker and just transitioned away = the EXIT. This is
            -- the #124 verification line: fired_target + where the player landed.
            _in_mt = false
            local where = (landing == nil) and "GAME (current_view=nil)" or ("MENU:" .. tostring(landing))
            _log("EXIT  fired_target=%s -> landed=%s view._exit_transition=%s",
                tostring(new_transition), where, tostring(view and view._exit_transition))
        end
    end)

    -- (#173 Probe B3) Independent read-only residency probe -- own pcall so it can never
    -- affect the #124 logic above. Fires on any menu-open transition (a view is now
    -- current), edge-latched per (level_key, residency, can_get). CONCLUSION MAP:
    -- can_get=true in a mission = the native charsel backdrop level is gettable there and
    -- the C7 rewire's native fork may fire vanilla unswapped; can_get=false = the
    -- inventory-preview backdrop swap path is required (expected in ALL missions per the
    -- bundle evidence). has_loaded on CHARSEL_PKG is kept for the record but that package
    -- does not exist in the game files, so expect false/pcall_error everywhere.
    pcall(function()
        local landing = self.current_view
        if landing == nil then return end          -- only when a menu view is open
        local pm = Managers and Managers.package
        if not (pm and pm.has_loaded) then return end
        local gm = Managers.state and Managers.state.game_mode
        local level_key = (gm and gm.level_key and gm:level_key()) or "?"
        local ok, resident = pcall(pm.has_loaded, pm, CHARSEL_PKG)   -- NO ref: true residency
        local res_s = ok and tostring(resident) or ("pcall_error:" .. tostring(resident))
        local can_get = Application and Application.can_get
        local ok_cg, cg = pcall(can_get, "level", CHARSEL_LEVEL)
        local cg_s = can_get and (ok_cg and tostring(cg) or ("pcall_error:" .. tostring(cg))) or "unavailable"
        local key = tostring(level_key) .. "|" .. res_s .. "|" .. cg_s
        if _b3_last == key then return end          -- once per (level, residency, can_get)
        _b3_last = key
        printf("[gut:173] B3 has_loaded(%s)=%s can_get('level',%s)=%s level_key=%s view=%s (can_get true=native charsel backdrop gettable here; false=swap path required; has_loaded is void -- no such .package exists)",
            CHARSEL_PKG, res_s, CHARSEL_LEVEL, cg_s, tostring(level_key), tostring(landing))
    end)
end)

_log("loaded (v0.2.95-dev) — watching Mod Tweaker open/exit transitions")
