local mod = get_mod("gut")

-- _gut_cutscenes.lua — Skip Cutscenes (Aussiemon "Skip Cutscenes" port)
--
-- MIGRATED from general_tweaker (gt) 2026-06-25 (issue #106): this feature moved
-- out of gt and into gut. Behavior is UNCHANGED from gt's _gt_cutscenes.lua — the
-- CW/deus gating and the deferred-skip teardown logic are preserved verbatim. The
-- only additions are a printf-based [gut:cutscene] DIAGNOSTIC (see below) and gt->gut
-- namespacing (setting ids gt_skip_cutscenes_* -> gut_skip_cutscenes_*; chat command
-- /gt_skipcutscenes -> /gut_skipcutscenes; mod.gt_skip_cutscenes_toggle ->
-- mod.gut_skip_cutscenes_toggle).
--
-- VT2's CutsceneSystem gates the ESC/Space skip behind
-- `script_data.skippable_cutscenes`. Flipping that flag is enough to let the
-- player dismiss any cutscene manually; in "auto" mode we additionally trigger
-- the cutscene's own skip event the moment activation flows fire, so the player
-- never sits through the cutscene at all.
--
-- Hooks (all guarded; PRE-FLIGHT verified disjoint from the rest of gut — a
-- whole-mod grep before migration found NO other gut hook on CutsceneSystem or on
-- ShowCursorStack.pop; gut only CALLS ShowCursorStack.show/.hide, never hooks .pop):
--   * CutsceneSystem.flow_cb_cutscene_effect   (table-form, guarded by `if CutsceneSystem`)
--   * CutsceneSystem.flow_cb_activate_cutscene_logic
--   * CutsceneSystem.skip_pressed
--   * ShowCursorStack.pop                       (table-form, guarded)
--
-- gut has NO central update registry (unlike gt's mod._gt_register_update), so the
-- deferred auto-skip processor CHAINS mod.update (capture-prev / call-prev-first),
-- the same idiom _hide_ui.lua uses. Exposes mod.gut_skip_cutscenes_toggle. The main
-- file's on_setting_changed has no branch for these ids — the only place that needs
-- to flip script_data.skippable_cutscenes is the toggle/command/load path here, plus
-- this module's own hooks, so dispatch is self-contained.
--
-- ============================================================================
-- DIAGNOSTIC (issue #106 — Blood-in-the-Darkness / `dlc_castle` stuck cutscene in CW)
-- ============================================================================
-- Symptom: a Drachenfels (dlc_castle) cutscene injected into a Chaos Wastes run gets
-- STUCK — black letterbox bars + a forced camera + the loading icon stay on screen and
-- the skip is broken. This module is the INSTRUMENT to diagnose it (NOT a fix yet).
--
-- WHY printf, not mod:info: the user runs with mod logging OFF most of the time;
-- gt's [gt:cutscene] mod:info lines were COMPLETELY SUPPRESSED in that mode, so a CW
-- repro captured ZERO cutscene lines. `printf` is the Stingray engine global, written
-- to console + game log regardless of any mod log level. EVERY diagnostic line below
-- is tagged `[gut:cutscene]` (grep-friendly) and uses printf.
--
-- The lines capture, across activate -> (attempted) skip -> teardown:
--   * level_key (Managers.state.game_mode:level_key()), in_deus (the CW gate result),
--     script_data.skippable_cutscenes, active_camera present?, event_on_activate /
--     event_on_skip names, each fade-effect `name`, ShowCursorStack.stack_depth.
--   * The readable CutsceneSystem teardown state BEFORE and AFTER skip, so we can see
--     which teardown step never fires on the stuck dlc_castle cutscene. Source-cited
--     field/method names (Vermintide-2-Source-Code/scripts/entity_system/systems/
--     cutscene/cutscene_system.lua):
--       - self.active_camera         (the forced camera; nil once cameras deactivate)
--       - self:is_active()           (== self.active_camera ~= nil, :83-85)
--       - self.ingame_hud_enabled    (restored to true by deactivate_cutscene_cameras :157)
--       - self._should_hide_loading_icon (drives the stuck LOADING ICON, :140 / :159-162)
--       - self.event_on_skip         (the level flow event; niled at skip, :105/:196)
--       - script_data.skippable_cutscenes (the engine skip gate, :98)
--     NOTE on LETTERBOX (the black bars): there is NO `letterbox_enabled` FIELD on the
--     CutsceneSystem — letterbox is driven by QUEUING `set_letterbox_enabled` onto
--     self.ui_event_queue (:150 enable, :173 disable in flow_cb_deactivate_cutscene_cameras),
--     consumed by the cutscene UI layer. So the diagnostic for "bars stuck on" is the
--     proxy `is_active=true AFTER skip` (== flow_cb_deactivate_cutscene_cameras never ran,
--     so the disable was never queued). We log the queue object's presence too.
-- Bounded: log on activate, on each fade effect, on the skip attempt (before+after),
-- and on the deferred tick — NOT every frame.

local _printf = rawget(_G, "printf") or function(fmt, ...) print(string.format(fmt, ...)) end

local function _level_key()
    local lvl = "?"
    pcall(function()
        local gm = Managers.state and Managers.state.game_mode
        lvl = (gm and gm.level_key and gm:level_key()) or "?"
    end)
    return lvl
end

-- Readable CutsceneSystem teardown-state snapshot (source-cited fields above).
local function _cs_snapshot(self)
    local is_active = "?"
    pcall(function() is_active = tostring(self.is_active and self:is_active()) end)
    return string.format(
        "active_camera=%s is_active=%s ingame_hud_enabled=%s should_hide_loading_icon=%s event_on_skip=%s ui_event_queue=%s skippable=%s",
        tostring(self.active_camera ~= nil), is_active,
        tostring(self.ingame_hud_enabled), tostring(self._should_hide_loading_icon),
        tostring(self.event_on_skip), tostring(self.ui_event_queue ~= nil),
        tostring(script_data and script_data.skippable_cutscenes))
end

-- ============================================================
-- Skip Cutscenes (Aussiemon "Skip Cutscenes" port)
-- ============================================================
-- Implementation notes (preserved from gt):
--   * `flow_cb_cutscene_effect` with name="fx_fade" produces the long
--     unskippable cross-fades that bracket each cutscene. We swallow the
--     next fade after a programmatic skip so the screen doesn't darken for
--     a beat after auto-skipping.
--   * `ShowCursorStack.pop` is guarded because cutscene skip + other mods
--     popping the cursor stack in the same frame can underflow it.
--   * `_skip_next_fade` is module-scoped (not a CutsceneSystem field) so
--     the flag survives system teardown across missions.
--
-- Naming: chat command and keybind both flip the VMF toggle so they stay in
-- sync. Setting id `gut_skip_cutscenes_enabled` to avoid colliding with the
-- standalone Skip Cutscenes / Skip Cutscenes Please mod settings.

local _skip_next_fade = false
-- Deferred auto-skip state. Bug 2026-05-22 (Devious Delvings intro):
-- the previous auto-skip path fired `event_on_skip` (the level's own
-- teardown flow event) inline from `flow_cb_activate_cutscene_logic` but
-- NEVER called the CutsceneSystem's cleanup methods. Vanilla's
-- `skip_pressed` does both — it fires event_on_skip AND calls
-- `flow_cb_deactivate_cutscene_cameras` (which queues set_letterbox_enabled=false,
-- removing the black bars) and `flow_cb_deactivate_cutscene_logic` (which
-- restores player input). Without those, the letterbox bars stayed onscreen
-- and player audio/input state never recovered.
--
-- Fix: defer the skip one mod.update tick so the cutscene's full setup
-- (camera activation → letterbox apply → audio ducking) has time to land,
-- then call `skip_pressed` which runs the full teardown.
local _pending_auto_skip_system = nil
-- gt v0.2.102-dev: outside CW the deferred auto-skip force-unlocks (skips even
-- author-locked cutscenes); in CW it does NOT force-unlock (force=false), so
-- vanilla skip_pressed honors the author lock — ordinary CW cutscenes skip,
-- boss/phase cinematics don't.
local _pending_auto_skip_force = false

local function _gut_cutscene_skip_active()
    return mod:get("gut_skip_cutscenes_enabled") and true or false
end

-- gt v0.2.95-dev / v0.2.102-dev: in a Chaos Wastes (deus) run, do NOT FORCE-UNLOCK
-- the author lock (but DO still auto-skip author-SKIPPABLE cutscenes — the hook
-- below defers to vanilla skip_pressed in CW). CW boss intro / phase cinematics
-- (Nurgloth on Enchanter's Lair, etc.) live in the LEVEL flow, not the breed code,
-- and are author-LOCKED (skippable_cutscenes=false) precisely because skipping
-- them desyncs the fight: CutsceneSystem.skip_pressed fires the cutscene's
-- `event_on_skip` LEVEL flow event early (cutscene_system.lua:97-105), and on a
-- boss level that flow event is what drives the boss's phase/state -- so an
-- auto-skip (or our force-unlock of the author lock) jumps the boss to a later
-- phase and deadlocks it (reported 2026-06-18, Enchanter's Lair / Nurgloth).
-- Detect a CW run via the deus run controller (the same probe ct uses). In CW we
-- only suppress the FORCE-UNLOCK (the unskippable-override); both auto-skip and
-- manual skip still work for author-SKIPPABLE cutscenes via vanilla skip_pressed.
local function _gut_in_deus()
    local mechanism = Managers and Managers.mechanism and Managers.mechanism.game_mechanism
        and Managers.mechanism:game_mechanism()
    return mechanism and mechanism.get_deus_run_controller
        and mechanism:get_deus_run_controller() ~= nil or false
end

if CutsceneSystem then
    mod:hook(CutsceneSystem, "flow_cb_cutscene_effect", function(func, self, name, ...)
        -- DIAGNOSTIC (#106): every fade/text effect the cutscene queues. The stuck
        -- dlc_castle bars are an fx_fade that never gets a matching disable.
        _printf("[gut:cutscene] effect | name=%s skip_next_fade=%s level=%s",
            tostring(name), tostring(_skip_next_fade), _level_key())
        if _skip_next_fade and name == "fx_fade" then
            _skip_next_fade = false
            return
        end
        return func(self, name, ...)
    end)

    mod:hook(CutsceneSystem, "flow_cb_activate_cutscene_logic", function(func, self, player_input_enabled, event_on_activate, event_on_skip)
        local result = func(self, player_input_enabled, event_on_activate, event_on_skip)
        -- DIAGNOSTIC (#106): log every CutsceneSystem activation (on_activate/on_skip
        -- event names + level + deus gate + readable teardown state). The boss-phase
        -- cutscene lives in the LEVEL flow (not the breed code), and skipping it fires
        -- its `event_on_skip` early -> boss desync; the in_deus gate below stops that.
        do
            local in_deus = _gut_in_deus()
            local auto = _gut_cutscene_skip_active() and mod:get("gut_skip_cutscenes_auto") and true or false
            _printf("[gut:cutscene] ACTIVATE | level=%s in_deus=%s auto_skip=%s input=%s on_activate=%s on_skip=%s | %s",
                _level_key(), tostring(in_deus), tostring(auto),
                tostring(player_input_enabled), tostring(event_on_activate), tostring(event_on_skip),
                _cs_snapshot(self))
        end
        if _gut_cutscene_skip_active() and mod:get("gut_skip_cutscenes_auto") then
            -- gt v0.2.102-dev: auto-skip now ALSO runs in a Chaos Wastes (deus) run,
            -- but WITHOUT force-unlocking the author lock there. In CW we defer to
            -- vanilla skip_pressed and let the engine's own
            -- `script_data.skippable_cutscenes` check decide — so author-SKIPPABLE
            -- cutscenes (e.g. forest_ambush_belakor_path1 / cs_01_skip, a path
            -- intro) auto-skip, while author-LOCKED boss/phase cinematics (Nurgloth
            -- on Enchanter's Lair) are left alone (skipping them desyncs the fight).
            -- This is exactly "auto-press the skip key" — same path as manual.
            -- Outside CW we force-unlock + skip everything, as before.
            local in_deus = _gut_in_deus()
            if not in_deus then
                script_data.skippable_cutscenes = true   -- force-unlock outside CW
            end
            -- gt v0.2.104-dev: swallow the cutscene's fade-IN when it will actually skip
            -- (skippable now: forced true outside CW; the level's own value in CW). A
            -- CW author-LOCKED cutscene reads false here -> leave its fade
            -- alone. Pairs with the same set in the deferred processor (fade-OUT) so
            -- an auto-skipped cutscene shows no blackscreen.
            if script_data.skippable_cutscenes then
                _skip_next_fade = true
            end
            -- Don't fire event_on_skip directly here — defer to skip_pressed
            -- on the next tick so vanilla's full teardown runs (letterbox
            -- off + cameras deactivated + logic deactivated + event_on_skip).
            _pending_auto_skip_system = self
            _pending_auto_skip_force  = not in_deus
        end
        return result
    end)

    -- `skip_pressed` is the canonical user-skip path. With the toggle on we
    -- temporarily flip `script_data.skippable_cutscenes` for the duration of
    -- the call so vanilla's `if self.active_camera and script_data.skippable_cutscenes`
    -- branch fires regardless of the level's own author intent.
    mod:hook(CutsceneSystem, "skip_pressed", function(func, self, ...)
        -- DIAGNOSTIC (#106): the KEY instrument. Log the readable teardown state
        -- BEFORE and AFTER the vanilla skip_pressed, plus the cursor stack depth, so
        -- we can see which teardown step never fires on the stuck dlc_castle cutscene.
        -- If AFTER still shows is_active=true, flow_cb_deactivate_cutscene_cameras
        -- never ran (bars + forced camera + loading icon stay).
        local in_deus = _gut_in_deus()
        local stack_depth = (ShowCursorStack and ShowCursorStack.stack_depth) or "?"
        _printf("[gut:cutscene] SKIP-PRESSED before | level=%s in_deus=%s active=%s stack_depth=%s | %s",
            _level_key(), tostring(in_deus), tostring(_gut_cutscene_skip_active()),
            tostring(stack_depth), _cs_snapshot(self))
        -- gt v0.2.95-dev: in a CW run, fall through to vanilla skip_pressed (which
        -- only skips author-SKIPPABLE cutscenes) -- do NOT force-unlock the author
        -- lock, so boss intro/phase cinematics can't be skipped (auto OR manual)
        -- into a desync. Outside CW, force-unlock as before.
        if _gut_cutscene_skip_active() and not in_deus then
            local saved = script_data.skippable_cutscenes
            script_data.skippable_cutscenes = true
            _skip_next_fade = true
            local result = func(self, ...)
            script_data.skippable_cutscenes = saved
            -- If we deferred a skip from flow_cb_activate_cutscene_logic and
            -- the user happened to press skip themselves first, the auto-
            -- skip is now unnecessary — cancel it.
            _pending_auto_skip_system = nil
            _printf("[gut:cutscene] SKIP-PRESSED after (force-unlock) | %s", _cs_snapshot(self))
            return result
        end
        local result = func(self, ...)
        _printf("[gut:cutscene] SKIP-PRESSED after (vanilla/CW) | %s", _cs_snapshot(self))
        return result
    end)
end

-- Deferred auto-skip processor. Fires one tick after a cutscene activates with
-- auto-skip on. gut has NO central update registry, so we CHAIN mod.update
-- (capture-prev / call-prev-first), the same idiom _hide_ui.lua uses — never
-- clobbering another feature's tick. This module dofile's after _hide_ui.lua so
-- `mod.update` here is already the hide-ui chain.
local _gut_cutscene_prev_update = mod.update
mod.update = function(dt)
    if _gut_cutscene_prev_update then _gut_cutscene_prev_update(dt) end
    if _pending_auto_skip_system then
        local sys = _pending_auto_skip_system
        local force = _pending_auto_skip_force
        _pending_auto_skip_system = nil
        _pending_auto_skip_force  = false
        -- Guard against pcall failure tearing down our state — we already
        -- cleared the pending flags above. Vanilla skip_pressed checks
        -- `self.active_camera and script_data.skippable_cutscenes` itself,
        -- but we also guard here so we don't blow up if the cutscene was
        -- already torn down before our tick fired (race with another mod
        -- or the cutscene ending naturally).
        local ok, err = pcall(function()
            if sys.active_camera then
                local saved = script_data.skippable_cutscenes
                -- Outside CW: force-unlock so even author-locked cutscenes skip.
                -- In CW (force=false): do NOT force — let vanilla skip_pressed honor
                -- the author lock, so boss cinematics aren't auto-skipped into a
                -- desync while ordinary CW cutscenes still skip.
                if force then script_data.skippable_cutscenes = true end
                -- gt v0.2.104-dev: swallow the post-skip fade-OUT when the cutscene
                -- will actually skip (skippable after the optional force-unlock).
                -- An author-LOCKED cutscene skip_pressed leaves alone (CW boss) keeps
                -- its own fade.
                if script_data.skippable_cutscenes then
                    _skip_next_fade = true
                end
                -- DIAGNOSTIC (#106): the deferred tick + before/after teardown state.
                _printf("[gut:cutscene] AUTO-SKIP deferred-tick firing | level=%s force_unlock=%s skippable=%s | before: %s",
                    _level_key(), tostring(force), tostring(script_data.skippable_cutscenes), _cs_snapshot(sys))
                sys:skip_pressed()
                _printf("[gut:cutscene] AUTO-SKIP deferred-tick done | after: %s", _cs_snapshot(sys))
                script_data.skippable_cutscenes = saved
            end
        end)
        if not ok then
            _printf("[gut:cutscene] deferred skip failed: %s (cutscene state likely already torn down — harmless)", tostring(err))
        end
    end
end

-- Underflow guard. Other mods (or vanilla code paths) sometimes pop the
-- cursor stack to 0 mid-cutscene; a follow-up pop would crash. Reproduce
-- the warning + early-return that Skip Cutscenes Please ships.
if ShowCursorStack then
    mod:hook(ShowCursorStack, "pop", function(func, ...)
        if ShowCursorStack.stack_depth <= 0 then
            return
        end
        return func(...)
    end)
end

mod.gut_skip_cutscenes_toggle = function()
    local new_val = not mod:get("gut_skip_cutscenes_enabled")
    mod:set("gut_skip_cutscenes_enabled", new_val)
    script_data.skippable_cutscenes = new_val or nil
    mod:echo("Skip cutscenes: " .. (new_val and "ON" or "OFF"))
end

mod:command("gut_skipcutscenes", "Toggle skipping cutscenes (auto-skip if 'Auto-skip' is enabled in settings, otherwise just allows ESC/Space)", function()
    mod.gut_skip_cutscenes_toggle()
end)

-- Apply once at load if the user kept the setting on across sessions.
if mod:get("gut_skip_cutscenes_enabled") then
    script_data.skippable_cutscenes = true
end

mod:info("[gut] Skip Cutscenes installed (migrated from gt, issue #106; [gut:cutscene] printf diagnostic active; toggle: %s, auto: %s)",
    tostring(mod:get("gut_skip_cutscenes_enabled")), tostring(mod:get("gut_skip_cutscenes_auto")))

return {}
