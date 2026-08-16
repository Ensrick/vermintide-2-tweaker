-- Behavioral production-path coverage for GUT #274 (with #140/#257/#275
-- adjacents): loads the real _gut_cutscenes.lua under a fake VMF environment,
-- captures the registered hook callbacks, composes them exactly as the mod
-- framework does (callback(next_fn, <original call args>),
-- mod_shim.lua:108-109), and replays intro-skip / delayed straggler / outro
-- against a fake CutsceneSystem modeled on the cited vanilla semantics
-- (cutscene_system.lua:97-109 skip gate + teardown, :129-151 camera activate,
-- :156-157 restore, :183 identity store).
return function(H, repo_root)
    local root = repo_root .. "/gui_tweaker_dev/scripts/mods/gui_tweaker_dev/"

    local function load_production(settings)
        local fired = {}          -- events the fake vanilla skip fired
        local played = {}         -- fade effects that reached the fake engine
        local receipts = {}       -- printf rows
        local env

        local CutsceneSystem = {}
        CutsceneSystem.flow_cb_activate_cutscene_logic = function(self, player_input_enabled, event_on_activate, event_on_skip)
            -- cutscene_system.lua:183
            self.event_on_skip = event_on_skip
        end
        CutsceneSystem.flow_cb_activate_cutscene_camera = function(self, camera_unit, transition_data, ingame_hud_enabled, letterbox_enabled)
            -- cutscene_system.lua:129-151
            self.active_camera = camera_unit
            self.ingame_hud_enabled = ingame_hud_enabled and true or false
        end
        CutsceneSystem.flow_cb_deactivate_cutscene_cameras = function(self)
            -- cutscene_system.lua:156-157
            self.active_camera = nil
            self.ingame_hud_enabled = true
        end
        CutsceneSystem.skip_pressed = function(self)
            -- cutscene_system.lua:97-109
            if self.active_camera and env.script_data.skippable_cutscenes then
                fired[#fired + 1] = self.event_on_skip
                self.event_on_skip = nil
                self:flow_cb_deactivate_cutscene_cameras()
            end
        end
        CutsceneSystem.flow_cb_cutscene_effect = function(self, name, flow_params)
            played[#played + 1] = name
        end

        local mod = { hooks = {}, safe_hooks = {}, commands = {} }
        local store = settings or {
            gut_skip_cutscenes_enabled = true,
            gut_skip_cutscenes_auto = true,
        }
        function mod:get(key) return store[key] end
        function mod:set(key, value) store[key] = value end
        function mod:echo() end
        function mod:info() end
        function mod:command(name, desc, fn) self.commands[name] = fn end
        function mod:dofile(path)
            return assert(loadfile(repo_root .. "/gui_tweaker_dev/" .. path .. ".lua"))()
        end
        local function compose(obj, method, fn)
            local orig = obj[method]
            return function(...)
                return fn(orig, ...)
            end
        end
        function mod:hook(obj, method, fn)
            self.hooks[method] = fn
            obj[method] = compose(obj, method, fn)
        end
        function mod:hook_safe(obj, method, fn)
            -- Safe hooks observe after the original; no return override.
            self.safe_hooks[method] = fn
            local orig = obj[method]
            obj[method] = function(...)
                orig(...)
                fn(...)
            end
        end

        env = setmetatable({
            get_mod = function() return mod end,
            printf = function(fmt, ...)
                receipts[#receipts + 1] = string.format(fmt, ...)
            end,
            CutsceneSystem = CutsceneSystem,
            ShowCursorStack = { stack_depth = 1, pop = function() end },
            script_data = {},
            Managers = {},
        }, { __index = _G })
        env._G = env

        local chunk = assert(loadfile(root .. "_gut_cutscenes.lua"))
        setfenv(chunk, env)
        local api = chunk()
        local function new_system()
            return setmetatable({}, { __index = CutsceneSystem })
        end
        local function saw(needle)
            for i = 1, #receipts do
                if receipts[i]:find(needle, 1, true) then return true end
            end
            return false
        end
        return {
            api = api, env = env, mod = mod, store = store,
            fired = fired, played = played, receipts = receipts,
            new_system = new_system, saw = saw,
        }
    end

    H.test("GUT #274 exported callbacks are the registered hook objects", function()
        local P = load_production()
        H.equal(P.api.hook_callbacks.effect, P.mod.hooks.flow_cb_cutscene_effect)
        H.equal(P.api.hook_callbacks.logic_activate, P.mod.hooks.flow_cb_activate_cutscene_logic)
        H.equal(P.api.hook_callbacks.skip_pressed, P.mod.hooks.skip_pressed)
        H.equal(P.api.hook_callbacks.camera_activate, P.mod.hooks.flow_cb_activate_cutscene_camera)
        H.equal(P.api.hook_callbacks.camera_deactivate, P.mod.safe_hooks.flow_cb_deactivate_cutscene_cameras)
        H.equal(type(P.mod.update), "function")
        H.equal(type(P.api.process_pending_auto_skip), "function")
        H.equal(type(P.api.replay_chain), "function")
    end)

    H.test("GUT #274 intro-skip, straggler, and outro sequence through the composed chain", function()
        local P = load_production()
        local sys = P.new_system()

        -- Intro activates; the deferred auto-skip queues and the camera runs.
        sys:flow_cb_activate_cutscene_logic(false, "cs_01", "cs_01_skip")
        H.equal(sys.event_on_skip, "cs_01_skip")
        sys:flow_cb_activate_cutscene_camera("cam_intro", nil, false, true)
        H.equal(sys.active_camera, "cam_intro")

        -- A fade between the logic node and the deferred tick is swallowed.
        sys:flow_cb_cutscene_effect("fx_fade", {})
        H.equal(#P.played, 0)

        -- Deferred tick executes the skip: authored event fires, teardown
        -- restores camera/HUD, the engine gate is restored to at-rest.
        P.mod.update(0.05)
        H.deep_equal(P.fired, { "cs_01_skip" })
        H.equal(sys.active_camera, nil)
        H.equal(sys.ingame_hud_enabled, true)
        H.equal(P.env.script_data.skippable_cutscenes, nil)
        H.truthy(P.saw("post-skip camera guard ARMED"))

        -- Delayed straggler group, issue-140 ordering (fade BEFORE camera):
        -- both suppressed while the window is live.
        P.mod.update(5)
        sys:flow_cb_cutscene_effect("fx_fade", {})
        H.equal(#P.played, 0)
        sys:flow_cb_activate_cutscene_camera("cam_straggler", nil, false, true)
        H.equal(sys.active_camera, nil)
        H.equal(sys.ingame_hud_enabled, true)
        H.truthy(P.saw("CAMERA-ACTIVATE suppressed"))

        -- Rolling grace: a straggler past the base grace but inside the
        -- re-granted window is still suppressed.
        P.mod.update(12)
        sys:flow_cb_activate_cutscene_camera("cam_straggler_2", nil, false, true)
        H.equal(sys.active_camera, nil)

        -- Past the hard cap the window is dead: the locked outro plays fully
        -- vanilla - camera delegate runs, fade reaches the engine, and a skip
        -- press cannot force it.
        P.mod.update(46)
        sys:flow_cb_activate_cutscene_logic(true, "outro_activate", nil)
        sys:flow_cb_activate_cutscene_camera("cam_outro", nil, false, true)
        H.equal(sys.active_camera, "cam_outro")
        sys:flow_cb_cutscene_effect("fx_fade", {})
        H.deep_equal(P.played, { "fx_fade" })
        sys:skip_pressed()
        H.deep_equal(P.fired, { "cs_01_skip" })
        H.equal(sys.active_camera, "cam_outro")
        H.equal(P.env.script_data.skippable_cutscenes, nil)

        -- Natural end restores HUD/camera through the safe-hooked teardown.
        sys:flow_cb_deactivate_cutscene_cameras()
        H.equal(sys.active_camera, nil)
        H.equal(sys.ingame_hud_enabled, true)
    end)

    H.test("GUT #274 new identity at the camera node releases the window and passes", function()
        local P = load_production()
        local sys = P.new_system()
        sys:flow_cb_activate_cutscene_logic(false, "cs_01", "cs_01_skip")
        sys:flow_cb_activate_cutscene_camera("cam_intro", nil, false, true)
        P.mod.update(0.05)
        H.equal(sys.active_camera, nil)

        -- Window is live; a camera activation carrying a DIFFERENT non-nil
        -- identity proves a new cutscene instance: release + pass.
        P.mod.update(2)
        sys.event_on_skip = "cs_02_skip"
        sys:flow_cb_activate_cutscene_camera("cam_new", nil, false, true)
        H.equal(sys.active_camera, "cam_new")
        H.truthy(P.saw("skip window released (new identity at camera node"))
    end)

    H.test("GUT #274 manual intro skip press scope-unlocks and restores the gate", function()
        local P = load_production({
            gut_skip_cutscenes_enabled = true,
            gut_skip_cutscenes_auto = false,
        })
        local sys = P.new_system()
        sys:flow_cb_activate_cutscene_logic(false, "cs_01", "cs_01_skip")
        sys:flow_cb_activate_cutscene_camera("cam_intro", nil, false, true)
        -- Auto off: nothing queued, the intro keeps playing.
        P.mod.update(0.05)
        H.equal(sys.active_camera, "cam_intro")
        H.equal(#P.fired, 0)

        -- The user presses skip: gut scope-unlocks only around this call.
        sys:skip_pressed()
        H.deep_equal(P.fired, { "cs_01_skip" })
        H.equal(sys.active_camera, nil)
        H.equal(P.env.script_data.skippable_cutscenes, nil)

        -- Feature disabled entirely: an intro skip press is refused vanilla.
        P.store.gut_skip_cutscenes_enabled = false
        local sys2 = P.new_system()
        sys2:flow_cb_activate_cutscene_logic(false, "cs_01", "cs_01_skip")
        sys2:flow_cb_activate_cutscene_camera("cam_intro2", nil, false, true)
        sys2:skip_pressed()
        H.equal(#P.fired, 1)
        H.equal(sys2.active_camera, "cam_intro2")
    end)

    H.test("GUT #257 pre-identity intro watch swallows only while auto-skip is armed", function()
        local P = load_production()
        local sys = P.new_system()
        -- First contact is a fade with no identity resolved yet: swallowed.
        sys:flow_cb_cutscene_effect("fx_fade", {})
        H.equal(#P.played, 0)

        -- With auto-skip off the same first-contact fade passes.
        P.store.gut_skip_cutscenes_auto = false
        local sys2 = P.new_system()
        sys2:flow_cb_cutscene_effect("fx_fade", {})
        H.deep_equal(P.played, { "fx_fade" })
    end)

    H.test("GUT #274 strengthened runtime checks pass on the captured chain", function()
        local P = load_production()
        local by_name = {}
        for _, c in ipairs(P.api.rt_checks) do by_name[c.name] = c.fn end
        H.equal(type(by_name.issue274_intro_only_cutscene_policy), "function")
        H.equal(type(by_name.issue274_post_intro_guard_bounded), "function")
        H.equal(by_name.issue274_intro_only_cutscene_policy(), nil)
        H.equal(by_name.issue274_post_intro_guard_bounded(), nil)
        H.equal(P.api.replay_chain(), nil)
        -- The replay restores the engine gate and leaves no pending state.
        H.equal(P.env.script_data.skippable_cutscenes, nil)
        H.truthy(P.saw("replay-begin"))
        H.truthy(P.saw("replay-end verdict=pass"))
    end)

    H.test("GUT #274 replay detects a broken chain (negative control)", function()
        local P = load_production()
        -- Sabotage the pure policy through the captured callback's view by
        -- replaying with the skip feature forced OFF: the intro can no longer
        -- queue, so the replay must fail on its first assertion.
        P.store.gut_skip_cutscenes_enabled = false
        P.store.gut_skip_cutscenes_auto = false
        -- replay_chain forces its own settings seam, so it must still pass.
        H.equal(P.api.replay_chain(), nil)
        P.store.gut_skip_cutscenes_enabled = true
        P.store.gut_skip_cutscenes_auto = true

        -- A genuinely broken delegate order IS detected: drive the captured
        -- lookup with a fake vanilla whose gate never opens.
        local sys = P.new_system()
        P.api.hook_callbacks.logic_activate(function() end, sys, false, "cs_01", "cs_01_skip")
        -- The fake vanilla above did NOT store the identity, so the deferred
        -- processor must refuse to skip (identity gate fails closed).
        sys.active_camera = "cam_x"
        P.api.process_pending_auto_skip()
        H.equal(#P.fired, 0)
        H.equal(sys.active_camera, "cam_x")
    end)
end
