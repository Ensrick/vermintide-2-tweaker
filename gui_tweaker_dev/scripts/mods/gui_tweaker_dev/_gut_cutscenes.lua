local mod = get_mod("gut_dev")

-- _gut_cutscenes.lua — Skip Cutscenes (Aussiemon "Skip Cutscenes" port)
--
-- MIGRATED from general_tweaker (gt) 2026-06-25 (issue #106): this feature moved
-- out of gt and into gut. Behavior is UNCHANGED from gt's _gt_cutscenes.lua — the
-- CW/deus gating and the deferred-skip teardown logic are preserved verbatim. The
-- only additions are a printf-based [gut:cutscene] DIAGNOSTIC (see below) and gt->gut
-- namespacing (setting ids gt_skip_cutscenes_* -> gut_skip_cutscenes_*; chat command
-- /gt_skipcutscenes -> /skipcutscenes; mod.gt_skip_cutscenes_toggle ->
-- mod.gut_skip_cutscenes_toggle).
--
-- VT2's CutsceneSystem gates the ESC/Space skip behind
-- `script_data.skippable_cutscenes` (cutscene_system.lua:98). ISSUE 274 POLICY:
-- gut only unlocks/skips the exact authored mission-intro event (`cs_01_skip`);
-- that flag is
-- SCOPE-unlocked just around the skip_pressed call, never latched on globally.
-- Mid-mission, phase, and outro cinematics are preserved even when they carry
-- some other wired event_on_skip. Unknown identities fail closed. See the
-- `_gut_cutscene_is_intro` gate below.
--
-- Hooks (all guarded; PRE-FLIGHT verified disjoint from the rest of gut — a
-- whole-mod grep before migration found NO other gut hook on CutsceneSystem or on
-- ShowCursorStack.pop; gut only CALLS ShowCursorStack.show/.hide, never hooks .pop):
--   * CutsceneSystem.flow_cb_cutscene_effect   (table-form, guarded by `if CutsceneSystem`;
--     #140 round-2 guard-swallow merged into the SAME hook body 2026-07-02 - VMF drops a
--     second hook on the same (Class, method), so never add another hook on this method)
--   * CutsceneSystem.flow_cb_activate_cutscene_logic
--   * CutsceneSystem.skip_pressed
--   * CutsceneSystem.flow_cb_activate_cutscene_camera    (#106 post-skip guard + lifecycle
--     log, added 2026-07-01; #140 fade-arm added 2026-07-02; dup-check re-run: whole-mod
--     grep found no other hook on it — only comment references in _gut_camera.lua)
--
-- #140 (Parting of the Waves brief fade-IN, user-confirmed 2026-07-02, reproduces in
-- official/vanilla Adventure). LEVEL-KEY CORRECTION: "A Parting of the Waves" is
-- `dlc_dwarf_whaling` (NOT dlc_portals - earlier docs had this wrong; the clean trace
-- below logs level=dlc_dwarf_whaling on every line).
--   ROUND 1 (camera-node fade-arm, 2026-07-02): gut armed the fade-swallow
--   (_skip_next_fade) only in flow_cb_activate_cutscene_logic, but this map's native
--   fade-in fires around the EARLIER flow_cb_activate_cutscene_camera node - at which
--   point _skip_next_fade is still false, so the fade-in played. Fix: arm
--   _skip_next_fade at the camera node too (Aussiemon SkipCutscenes.lua:8 pattern),
--   gated on "will this cutscene actually skip" so a CW author-LOCKED boss cinematic
--   that plays through keeps its fade.
--   ROUND 2 (guard-based swallow, v0.2.178-dev; clean user trace 2026-07-02 22:04,
--   v0.2.175-dev, no other cutscene mods): the auto-skip itself works (deferred skip
--   fires, fade #1 swallowed via _skip_next_fade, teardown clean, post-skip guard
--   _skipped_cutscene_system ARMED), but the map's flow keeps firing delayed node
--   groups AFTER the skip, and in each group the fx_fade effect fires ~97 ms BEFORE
--   its flow_cb_activate_cutscene_camera node (PROVEN ordering on dlc_dwarf_whaling):
--     22:04:39.972 effect | name=fx_fade skip_next_fade=false -> PLAYED (the bug)
--     22:04:40.069 camera node -> fade-arm + CAMERA-ACTIVATE suppressed (97 ms too late)
--     22:04:45.417 fade #3 swallowed only by luck (leftover flag from the 40.069 arm)
--   The single-shot _skip_next_fade armed at the camera node can never catch a fade
--   that PRECEDES its own camera node. Fix: in flow_cb_cutscene_effect, while the #106
--   post-skip guard is armed (_skipped_cutscene_system == self), swallow EVERY fx_fade
--   on that system. The one-shot _skip_next_fade branch stays - it handles the fade
--   that arrives during skip_pressed BEFORE the guard arms (trace 22:04:36.434).
--   TRADE-OFF (accepted): while the guard is armed (from skip until the next cutscene
--   activation or level change), any scripted standalone fx_fade routed through
--   CutsceneSystem is also swallowed - a cosmetic pop instead of a masking fade.
--   Accepted vs. the erroneous black screen.
--   ROUND 3 (issues 257 + 274, per-episode order-independent rework): the round-2
--   guard was still ORDER-dependent - it armed only at skip time and released only at
--   flow_cb_activate_cutscene_logic or a fixed timeout, so (a) an intro fade that
--   precedes BOTH activation callbacks fell outside every armed window (issue 257,
--   The Well of Dreams = dlc_termite_3), and (b) stragglers later than the fixed
--   timeout leaked while a legitimate later cutscene depended on that same timeout
--   for release (issue 274 class, dlc_dwarf_whaling ending). The guard state now
--   lives in _gut_cutscene_skipwindow.lua (pure, offline-tested): per-system cutscene
--   EPISODES with one release condition (new episode opens, or the rolling-grace /
--   hard-cap deadline passes). During a skipped episode's window EVERY fx_fade is
--   swallowed and EVERY camera activation is suppressed regardless of arrival order;
--   a deferred-skip PENDING window swallows fades between the intro's logic node and
--   the deferred skip_pressed tick (the old one-shot only caught the first); and a
--   bounded pre-identity INTRO WATCH swallows an auto-skip-armed mission's first
--   fades before any identity is knowable (the 257 shape). The issue-275/274
--   intro-only SKIP policy (_gut_cutscene_policy274.is_intro, nil on_skip = never
--   skip) is UNCHANGED - the watch affects fades only, never whether a cutscene
--   skips.
--   * CutsceneSystem.flow_cb_deactivate_cutscene_cameras (hook_safe, lifecycle log only;
--     same dup-check, no other hook)
--   * ShowCursorStack.pop                       (table-form, guarded)
--
-- This file's mod.update chain also carries the ALWAYS-ON [gut:frametime] heartbeat
-- (2026-07-01): one printf every 30 s with avg/worst frame ms + frame count, so FPS
-- complaints can finally be anchored to log timestamps (neither machine's log carried
-- any frame-time data). Not cutscene-specific — it lives here because this file already
-- owns a chained mod.update tick plus the _printf/_level_key helpers.
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
local _probe257 = mod:dofile("scripts/mods/gui_tweaker_dev/_gut_cutscene_probe257")
local _probe257_state = _probe257.new()
local _policy274 = mod:dofile("scripts/mods/gui_tweaker_dev/_gut_cutscene_policy274")
local _skipwindow = mod:dofile("scripts/mods/gui_tweaker_dev/_gut_cutscene_skipwindow")

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

-- Automatic #257 evidence, silent outside The Well of Dreams and hard-capped at
-- 32 callback records plus one cap marker per CutsceneSystem instance. This records
-- authored flow identity/order only; it does not alter any cutscene decision.
local function _trace257(self, phase, fields)
    local level = _level_key()
    local e = _probe257.record(_probe257_state, level, self, phase, fields)
    if not e then return end
    _printf("[gut:257] seq=%s phase=%s level=%s disposition=%s skip_next=%s guard=%s active_camera=%s on_activate=%s on_skip=%s hud=%s letterbox=%s fade_in=%s hold=%s fade_out=%s auto=%s capped=%s",
        tostring(e.seq), tostring(e.phase), level, tostring(e.disposition),
        tostring(e.skip_next), tostring(e.guard), tostring(e.active_camera),
        tostring(e.on_activate), tostring(e.on_skip), tostring(e.hud),
        tostring(e.letterbox), tostring(e.fade_in), tostring(e.hold),
        tostring(e.fade_out), tostring(e.auto), tostring(e.capped))
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

-- issue 537 / issue 275 / issue 274: own-or-pin ownership of the shared engine skip gate
-- `script_data.skippable_cutscenes`. It is a GLOBAL on the engine settings table, read at
-- exactly one runtime site (CutsceneSystem.skip_pressed, cutscene_system.lua:98) and
-- shared with vanilla (the debug menu preset sets it, debug_screen_config.lua:742) and any
-- co-installed cutscene mod. gut must NEVER persistently latch it on -- the hooks below
-- scope-unlock it only around the authored `cs_01_skip` mission intro and restore the
-- at-rest value on every path. Capture the pre-gut value ONCE, before any gut hook
-- installs, so that disabling the feature restores whatever a co-installed mod / the debug
-- menu set instead of clobbering it to a hardcoded nil. Guarded by a boolean flag (a nil
-- captured value is legitimate = retail default) so a re-dofile of this module can't
-- re-capture. Caveat: captured at this module's load; a cutscene mod that sets the flag
-- LATER in the boot order would not be seen, but the retail default is unset and nothing
-- else in this repo touches the flag.
if not mod._gut_pre_skippable_captured then
    mod._gut_pre_skippable_captured = true
    mod._gut_pre_skippable_cutscenes = script_data and script_data.skippable_cutscenes
end

-- Restore the shared skip gate to its captured pre-gut value. Called when the user turns
-- Skip Cutscenes OFF (from the VMF checkbox via on_setting_changed, or the /skipcutscenes
-- chat command / keybind). NEVER sets the gate on -- enabling relies entirely on the
-- per-skip scope-unlock in the hooks below (issue 275). Idempotent; safe to call twice.
mod._gut_restore_skippable_cutscenes = function()
    if script_data then
        script_data.skippable_cutscenes = mod._gut_pre_skippable_cutscenes
        _printf("[gut:537] Skip Cutscenes disabled -> engine skip gate restored to pre-gut value=%s",
            tostring(mod._gut_pre_skippable_cutscenes))
    end
end

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
-- issue 275 (0.2.209-dev): the old `_pending_auto_skip_force` flag (the deus-vs-
-- adventure force-unlock split) is gone. Under issue 274's intro-only policy the
-- deferred processor only ever fires for the exact `cs_01_skip` intro event, and it
-- scope-unlocks script_data.skippable_cutscenes around that single skip_pressed call
-- every time (then restores the at-rest value on every path, including a throw).
-- gut v0.2.159-dev (#106, bastion re-arm variant, 2026-07-01): post-skip camera guard.
-- HOST log 2026-07-01 21:09:26 (dlc_bastion_nurgle_path1): gut's auto-skip completed
-- clean in 16 ms, but the LEVEL's flow timeline kept firing DELAYED camera-activate
-- nodes that are NOT gated on the skip event — vanilla
-- flow_cb_activate_cutscene_camera (cutscene_system.lua:129-151) unconditionally
-- re-set active_camera / ingame_hud_enabled=false / _should_hide_loading_icon=true and
-- re-queued the letterbox, re-locking the player TWICE after the skip until the
-- timeline ran out at the cutscene's natural ~35.5 s duration. Vanilla skip_pressed
-- (:97-109) tears down only the CURRENT camera; it never short-circuits pending flow
-- nodes. Map wiring defect; distinct from the dlc_termite deferred-teardown variant
-- fixed above.
--
-- Guard shape (ROUND 3, issues 257 + 274): per-system cutscene EPISODES in the pure
-- _gut_cutscene_skipwindow state machine. A skip PROVEN executed (before-state had an
-- active_camera and the after-state doesn't - vanilla's teardown really ran; covers
-- BOTH the deferred auto-skip and a manual player skip, since both route through the
-- hooked skip_pressed) marks the CURRENT episode skipped and opens its straggler
-- window. Every later flow_cb_* on that system CLASSIFIES against the episode instead
-- of assuming an arrival order: fades swallow, camera activations suppress. ONE
-- release condition (checked inside the state machine): the window ends when a new
-- episode opens on that system (flow_cb_activate_cutscene_logic, or a camera
-- activation carrying a DIFFERENT non-nil identity) or when its deadline passes -
-- a rolling GRACE_SECONDS grace re-granted by each classified straggler (the flow
-- timeline is still replaying the skipped cutscene) under a MAX_WINDOW_SECONDS hard
-- cap from the skip moment, so the issue-274 class (a legitimate later cutscene
-- suppressed - the dlc_dwarf_whaling ENDING) is structurally impossible: its window
-- is long dead. Level transitions stay IMPLICIT via instance keying (every level
-- constructs a FRESH CutsceneSystem, cutscene_system.lua:11-24; episodes are held
-- under weak keys so dead systems never leak).
local _sw_state = _skipwindow.new()
-- Monotonic clock for the window deadlines: accumulated dt from the chained
-- mod.update below. Absolute-time deadlines make the classification callbacks
-- order-independent (no per-tick decay coupling).
local _sw_now = 0
-- Last system whose window armed, for the one-shot expiry log in mod.update.
local _sw_last_armed_system = nil

local function _post_skip_guard_active(system)
    return _skipwindow.window_active(_sw_state, system, _sw_now)
end

local function _gut_cutscene_skip_active()
    return mod:get("gut_skip_cutscenes_enabled") and true or false
end

-- issue 274: gut may only unlock/skip the exact authored mission-intro event
-- `cs_01_skip`. The engine's skip has no per-cutscene lock -- it gates
-- the whole thing behind `if self.active_camera and script_data.skippable_cutscenes`
-- (cutscene_system.lua:98). `event_on_skip` is the LEVEL author's own skip/teardown
-- flow event: on skip the engine fires it early (cutscene_system.lua:99-105). A
-- mission-INTRO cutscene ships one (e.g. cs_01_skip) -> skipping is safe. Nurgloth's
-- mid-mission boss cinematic on The Enchanter's Lair (dlc_castle) ships
-- `event_on_skip=nil` -> there is NO legal skip path, and terminating it early leaves
-- the level's cinematic flow sequence dangling; the boss fight state machine desyncs
-- and his health floors at ~66% forever (softlock, reported 2026-06-18 / repro
-- 2026-07-05). A merely non-nil event is not proof that a cinematic is an intro:
-- Parting of the Waves and Well of Dreams outro paths demonstrated the failure.
-- Exact `cs_01_skip` = intro; nil/unknown/other = preserve. `_gut_in_deus` survives only
-- to keep the `in_deus` field in the [gut:cutscene] probe output for log continuity.
local function _gut_in_deus()
    local mechanism = Managers and Managers.mechanism and Managers.mechanism.game_mechanism
        and Managers.mechanism:game_mechanism()
    return mechanism and mechanism.get_deus_run_controller
        and mechanism:get_deus_run_controller() ~= nil or false
end

-- issue 274 gate: a cutscene is eligible for gut's forced skip ONLY if its
-- `event_on_skip` is exactly `cs_01_skip`. The engine stores it on the instance as
-- `self.event_on_skip` in flow_cb_activate_cutscene_logic (cutscene_system.lua:183)
-- and nils it on skip / deactivate (:105 / :196). Every unknown identity fails
-- closed. The compatibility export retains its old name for the existing runtime
-- scaffold, but its semantics are now intentionally intro-only.
local function _gut_cutscene_is_intro(cutscene_system)
    return cutscene_system ~= nil and _policy274.is_intro(cutscene_system.event_on_skip)
end
-- Compatibility export retained for the existing #275 runtime check. Its
-- semantics are deliberately narrower now: a wired event is not sufficient;
-- only the authored mission-intro event may be unlocked by gut.
mod._gut_cutscene_has_wired_skip = _gut_cutscene_is_intro
mod._gut_cutscene_is_intro = _gut_cutscene_is_intro

if CutsceneSystem then
    mod:hook(CutsceneSystem, "flow_cb_cutscene_effect", function(func, self, name, flow_params, ...)
        local auto = _gut_cutscene_skip_active() and mod:get("gut_skip_cutscenes_auto") and true or false
        local pending = _pending_auto_skip_system == self
        -- ROUND 3 order-independent classification (_gut_cutscene_fade_swallow_site;
        -- issues 140/257/274, see the header docstring): classify this fade against
        -- the system's live EPISODE instead of assuming arrival order. Exactly one
        -- classification per callback; the #257 trace records the real verdict.
        --   swallow_one_shot    - armed just before a skip_pressed call so the fade
        --                         fired INSIDE vanilla's skip teardown is swallowed
        --                         (issue 140 trace 22:04:36.434 proves this branch
        --                         is load-bearing). Cleared on use AND after every
        --                         proven skip so it can never leak forward.
        --   swallow_pending     - deferred intro auto-skip queued for THIS system:
        --                         the fade belongs to the cutscene about to skip
        --                         (covers EVERY fade between the logic node and the
        --                         deferred tick, not just the first).
        --   swallow_window      - skipped episode's straggler window live (the
        --                         issue-140 round-2 swallow, now with a rolling
        --                         grace + hard cap instead of a fixed timeout).
        --   swallow_intro_watch - pre-identity mission-intro watch (issue 257):
        --                         auto-skip armed and this system's first cutscene
        --                         has not yet identified itself; bounded to
        --                         INTRO_WATCH_SECONDS from first contact.
        -- Trade-offs (accepted, documented in header + CHANGELOG): a scripted
        -- standalone fx_fade during a live window, or during the intro watch of a
        -- mission whose first cinematic is locked, is also swallowed - a cosmetic
        -- pop instead of a masking fade. Skip POLICY (issue 275) is untouched.
        local verdict
        if name ~= "fx_fade" then
            verdict = "pass_nonfade"
            _skipwindow.note_contact(_sw_state, self, _sw_now)
        elseif _skip_next_fade then
            verdict = "swallow_one_shot"
        else
            verdict = _skipwindow.classify_fade(_sw_state, self, pending, auto, _sw_now)
            if verdict == "pass" then
                verdict = "pass_fade"
            end
        end
        _trace257(self, "effect", {
            disposition = verdict,
            skip_next = _skip_next_fade,
            guard = _post_skip_guard_active(self),
            active_camera = self.active_camera ~= nil,
            on_skip = self.event_on_skip,
            fade_in = flow_params and flow_params.fade_in_time,
            hold = flow_params and flow_params.hold_time,
            fade_out = flow_params and flow_params.fade_out_time,
            auto = auto,
        })
        -- DIAGNOSTIC (#106): every fade/text effect the cutscene queues. The stuck
        -- dlc_castle bars are an fx_fade that never gets a matching disable.
        _printf("[gut:cutscene] effect | name=%s skip_next_fade=%s level=%s",
            tostring(name), tostring(_skip_next_fade), _level_key())
        if verdict == "swallow_one_shot" then
            _skip_next_fade = false
            return
        end
        if verdict ~= "pass_fade" and verdict ~= "pass_nonfade" then
            _printf("[gut:cutscene] fx_fade swallowed (%s) | level=%s", verdict, _level_key())
            return
        end
        return func(self, name, flow_params, ...)
    end)

    mod:hook(CutsceneSystem, "flow_cb_activate_cutscene_logic", function(func, self, player_input_enabled, event_on_activate, event_on_skip)
        _trace257(self, "logic_activate", {
            disposition = _policy274.classify(event_on_skip),
            guard = _post_skip_guard_active(self),
            active_camera = self.active_camera ~= nil,
            on_activate = event_on_activate,
            on_skip = event_on_skip,
            auto = _gut_cutscene_skip_active() and mod:get("gut_skip_cutscenes_auto") and true or false,
        })
        -- #106 bastion fix, ROUND 3 shape: a genuinely NEW cutscene episode opens
        -- BEFORE the auto-skip evaluation below (the release half of the single
        -- skip-window release condition), so this cutscene's camera activates
        -- normally and, if auto-skip fires, the skip re-arms the window itself.
        -- This also resolves the system's first-episode identity, closing the
        -- issue-257 pre-identity intro fade watch.
        do
            local release, gen = _skipwindow.note_logic_activate(
                _sw_state, self, event_on_skip, _sw_now)
            if release == "released" then
                _printf("[gut:274] skip window released (new cutscene episode gen=%s) | level=%s",
                    tostring(gen), _level_key())
            end
        end
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
            -- issue 275: only queue an auto-skip for a cutscene that carries a WIRED
            -- event_on_skip (the param the flow just passed; vanilla stored it on
            -- self.event_on_skip at cutscene_system.lua:183). A locked boss/phase
            -- cinematic (event_on_skip=nil, e.g. Nurgloth on dlc_castle) is left to
            -- play out vanilla -- skipping it fires the level flow's event_on_skip
            -- early and desyncs the fight into a ~66%-health softlock. deus and
            -- adventure are treated identically now; the intro-identity gate is the sole
            -- arbiter (the old in_deus force-unlock split is gone with the global
            -- latch it relied on).
            if _policy274.is_intro(event_on_skip) then
                -- Don't fire event_on_skip directly here -- defer to skip_pressed on
                -- the next tick so vanilla's full teardown runs (letterbox off +
                -- cameras deactivated + logic deactivated + event_on_skip). The
                -- deferred processor scope-unlocks script_data.skippable_cutscenes
                -- only around that skip_pressed call. ROUND 3: the old one-shot
                -- `_skip_next_fade = true` arm here is gone - while
                -- _pending_auto_skip_system == self, classify_fade swallows EVERY
                -- fade in the logic-to-deferred-tick gap (the one-shot missed all
                -- but the first); the deferred processor still arms the one-shot
                -- for the fade fired INSIDE its skip_pressed call.
                _pending_auto_skip_system = self
            else
                _printf("[gut:274] NOT-INTRO (cutscene preserved) | level=%s disposition=%s on_skip=%s in_deus=%s",
                    _level_key(), _policy274.classify(event_on_skip), tostring(event_on_skip),
                    tostring(_gut_in_deus()))
            end
        end
        return result
    end)

    -- `skip_pressed` is the canonical user-skip path. With the toggle on we
    -- temporarily flip `script_data.skippable_cutscenes` for the duration of
    -- the call so vanilla's `if self.active_camera and script_data.skippable_cutscenes`
    -- branch fires regardless of the level's own author intent.
    mod:hook(CutsceneSystem, "skip_pressed", function(func, self, ...)
        _trace257(self, "skip_before", {
            disposition = _gut_cutscene_is_intro(self) and "intro_skip" or "preserve_non_intro",
            skip_next = _skip_next_fade,
            guard = _post_skip_guard_active(self),
            active_camera = self.active_camera ~= nil,
            on_skip = self.event_on_skip,
            auto = _gut_cutscene_skip_active() and mod:get("gut_skip_cutscenes_auto") and true or false,
        })
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
        -- #106 bastion fix: detect whether this call ACTUALLY skipped. Vanilla
        -- skip_pressed acts only when `self.active_camera and script_data.skippable_cutscenes`,
        -- and its teardown nils active_camera (cutscene_system.lua:97-109 ->
        -- flow_cb_deactivate_cutscene_cameras :156). So before=camera / after=no-camera
        -- is exactly "a skip executed" — an orphan press (no active cutscene) or an
        -- author-locked CW cutscene falling through vanilla does NOT arm the guard.
        local had_camera = self.active_camera ~= nil
        local was_intro = _gut_cutscene_is_intro(self)
        -- Captured BEFORE the vanilla call: skip_pressed fires event_on_skip early
        -- and then NILS the field (cutscene_system.lua:99-105), so the skipped
        -- episode's identity must be read here for the window's later
        -- new-identity release comparison.
        local pre_skip_identity = self.event_on_skip
        local function _arm_post_skip_guard()
            if was_intro and had_camera and self.active_camera == nil then
                _skipwindow.note_skip_executed(_sw_state, self, pre_skip_identity, _sw_now)
                _sw_last_armed_system = self
                -- The window now owns every post-skip fade; a stale unconsumed
                -- one-shot must not leak into a later cutscene's legitimate fade.
                _skip_next_fade = false
                _trace257(self, "guard_armed", {
                    disposition = "post_skip_guard",
                    skip_next = _skip_next_fade,
                    guard = true,
                    active_camera = false,
                    on_skip = self.event_on_skip,
                    auto = _gut_cutscene_skip_active() and mod:get("gut_skip_cutscenes_auto") and true or false,
                })
                _printf("[gut:cutscene] post-skip camera guard ARMED (window grace=%ss cap=%ss) | level=%s",
                    tostring(_skipwindow.GRACE_SECONDS), tostring(_skipwindow.MAX_WINDOW_SECONDS), _level_key())
            end
        end
        -- issue 274: force-unlock (scope-only) ONLY for exact mission intros. A
        -- boss/phase/outro cinematic has no gut-owned skip path; unlocking it can fire
        -- level flow early, desync a fight, or suppress the outro camera. For any
        -- non-intro cutscene
        -- we fall through to vanilla skip_pressed with script_data.skippable_cutscenes
        -- unset (retail default), so vanilla's own gate refuses the skip and the
        -- cutscene plays out. deus and adventure are treated identically now.
        if _gut_cutscene_skip_active() and _gut_cutscene_is_intro(self) then
            local saved = script_data.skippable_cutscenes
            script_data.skippable_cutscenes = true
            _skip_next_fade = true
            local result = func(self, ...)
            script_data.skippable_cutscenes = saved
            -- If we deferred a skip from flow_cb_activate_cutscene_logic and
            -- the user happened to press skip themselves first, the auto-
            -- skip is now unnecessary — cancel it.
            _pending_auto_skip_system = nil
            _arm_post_skip_guard()
            _printf("[gut:cutscene] SKIP-PRESSED after (unlock, intro-only) | %s", _cs_snapshot(self))
            return result
        end
        -- Non-intro cutscene: log the decision, then preserve vanilla behavior without
        -- gut force-unlocking the global skip gate.
        if _gut_cutscene_skip_active() and had_camera and not _gut_cutscene_is_intro(self) then
            _printf("[gut:274] NOT-INTRO skip press preserved | level=%s disposition=%s on_skip=%s in_deus=%s",
                _level_key(), _policy274.classify(self.event_on_skip),
                tostring(self.event_on_skip), tostring(in_deus))
        end
        local result = func(self, ...)
        _arm_post_skip_guard()
        _printf("[gut:cutscene] SKIP-PRESSED after (vanilla) | %s", _cs_snapshot(self))
        return result
    end)

    -- #106 bastion fix (gut v0.2.159-dev): suppress the LEVEL flow's late
    -- camera-activate nodes after a successful skip. Vanilla
    -- flow_cb_activate_cutscene_camera (cutscene_system.lua:129-151) unconditionally
    -- re-sets active_camera / ingame_hud_enabled / _should_hide_loading_icon and
    -- re-queues set_letterbox_enabled — on dlc_bastion those nodes fire AFTER the skip
    -- already tore the cutscene down, re-locking the player (HOST log 2026-07-01).
    -- The early return here deliberately REMOVES vanilla's mutation
    -- (PROJECT_STANDARDS § 4.2 documented consequence): every field it would set is
    -- the re-lock itself, and the skip's teardown already restored the consistent
    -- post-cutscene state (1P camera, HUD on, letterbox off, input on) — so skipping
    -- the re-arm leaves nothing inconsistent. Guard is instance-keyed and cleared by
    -- flow_cb_activate_cutscene_logic, so a legitimate new cutscene is never affected.
    -- PRE-FLIGHT dup check 2026-07-01: no other gut hook on this method (grep: only
    -- comment references in _gut_camera.lua).
    -- Also the CAMERA-ACTIVATE lifecycle log: flow_cb_activate_cutscene_logic never
    -- fires CLIENT-side (2026-07-01 session: exactly 2 [gut:cutscene] lines in the
    -- client's entire 7-mission log), so this camera-level line is what closes the
    -- client instrumentation blind spot.
    mod:hook(CutsceneSystem, "flow_cb_activate_cutscene_camera", function(func, self, camera_unit, transition_data, ingame_hud_enabled, letterbox_enabled)
        -- ROUND 3 classification: while the skipped episode's window is live, a
        -- camera activation with NO new identity visible (vanilla niled the skipped
        -- event_on_skip at cutscene_system.lua:105, and stragglers never re-set it)
        -- is a straggler of the SKIPPED cutscene - suppress it, order-independent
        -- of the fade/camera sequence inside each straggler group. A DIFFERENT
        -- non-nil identity proves a new cutscene instance (its logic node already
        -- stored a fresh event_on_skip, cutscene_system.lua:183) - release + pass.
        -- The window's rolling grace + hard cap bound the worst case, so a
        -- legitimate later cutscene (the issue-274 dlc_dwarf_whaling ENDING,
        -- minutes after the intro skip) always finds the window dead and passes.
        -- NOTE (ROUND 3): the old #140 round-1 CAMERA-NODE one-shot fade-arm that
        -- lived here is gone - by the time an intro identity is visible on this
        -- system the deferred-skip PENDING window already swallows those fades,
        -- and the pre-identity case is the issue-257 intro watch's job.
        local verdict = _skipwindow.classify_camera(_sw_state, self, self.event_on_skip, _sw_now)
        _trace257(self, "camera_activate", {
            disposition = verdict == "suppress" and "suppress_post_skip"
                or verdict == "released_pass" and "released_pass" or "pass_camera",
            skip_next = _skip_next_fade,
            guard = _post_skip_guard_active(self),
            active_camera = self.active_camera ~= nil,
            on_skip = self.event_on_skip,
            hud = ingame_hud_enabled,
            letterbox = letterbox_enabled,
            auto = _gut_cutscene_skip_active() and mod:get("gut_skip_cutscenes_auto") and true or false,
        })
        if verdict == "suppress" then
            _printf("[gut:cutscene] CAMERA-ACTIVATE suppressed (post-skip window) | level=%s hud=%s letterbox=%s | %s",
                _level_key(), tostring(ingame_hud_enabled), tostring(letterbox_enabled), _cs_snapshot(self))
            return nil
        end
        if verdict == "released_pass" then
            _printf("[gut:274] skip window released (new identity at camera node: %s) | level=%s",
                tostring(self.event_on_skip), _level_key())
        end
        local result = func(self, camera_unit, transition_data, ingame_hud_enabled, letterbox_enabled)
        _printf("[gut:cutscene] CAMERA-ACTIVATE | level=%s hud=%s letterbox=%s | %s",
            _level_key(), tostring(ingame_hud_enabled), tostring(letterbox_enabled), _cs_snapshot(self))
        return result
    end)

    -- Companion CAMERA-DEACTIVATE lifecycle log. hook_safe (post-callback, no return
    -- override, zero behavior change) — fires on BOTH the skip teardown path
    -- (skip_pressed -> :107) and the natural flow-driven end, host and client alike.
    -- PRE-FLIGHT dup check 2026-07-01: no other gut hook on this method.
    mod:hook_safe(CutsceneSystem, "flow_cb_deactivate_cutscene_cameras", function(self)
        _skipwindow.note_contact(_sw_state, self, _sw_now)
        _trace257(self, "camera_deactivate", {
            disposition = "observed",
            skip_next = _skip_next_fade,
            guard = _post_skip_guard_active(self),
            active_camera = self.active_camera ~= nil,
            on_skip = self.event_on_skip,
            auto = _gut_cutscene_skip_active() and mod:get("gut_skip_cutscenes_auto") and true or false,
        })
        _printf("[gut:cutscene] CAMERA-DEACTIVATE | level=%s | %s", _level_key(), _cs_snapshot(self))
    end)
end

-- Frame-time heartbeat accumulators (2026-07-01, same forensics pass as #106):
-- both machines had FPS complaints that could not be anchored to timestamps because
-- neither log contained ANY frame-time data. One [gut:frametime] printf every 30 s
-- (avg/worst frame ms + frame count; ~2 lines/min, negligible; ALWAYS-ON via printf
-- so it survives VMF-logging-off). Accumulators reset each beat.
local _ft_accum_ms = 0
local _ft_worst_ms = 0
local _ft_frames = 0
local _ft_elapsed = 0

-- Deferred auto-skip processor. Fires one tick after a cutscene activates with
-- auto-skip on. gut has NO central update registry, so we CHAIN mod.update
-- (capture-prev / call-prev-first), the same idiom _hide_ui.lua uses — never
-- clobbering another feature's tick. This module dofile's after _hide_ui.lua so
-- `mod.update` here is already the hide-ui chain. This SAME chained function also
-- carries the [gut:frametime] heartbeat below (extending the existing chain link,
-- not adding another mod.update assignment).
local _gut_cutscene_prev_update = mod.update
mod.update = function(dt)
    if _gut_cutscene_prev_update then _gut_cutscene_prev_update(dt) end
    -- [gut:frametime] heartbeat. dt is seconds; VMF calls mod.update every frame.
    local d = dt or 0
    -- ROUND 3: the skip-window deadlines are absolute against this monotonic
    -- clock (no per-tick decay); advance it, then emit the one-shot expiry log
    -- for the last armed system so the trace still shows when a window closed.
    _sw_now = _sw_now + d
    if _sw_last_armed_system and not _post_skip_guard_active(_sw_last_armed_system) then
        _printf("[gut:274] post-skip window closed (deadline or release) | level=%s", _level_key())
        _sw_last_armed_system = nil
    end
    local ms = d * 1000
    _ft_frames = _ft_frames + 1
    _ft_accum_ms = _ft_accum_ms + ms
    if ms > _ft_worst_ms then _ft_worst_ms = ms end
    _ft_elapsed = _ft_elapsed + d
    if _ft_elapsed >= 30 then
        -- _ft_frames >= 1 here (incremented above before the beat check).
        _printf("[gut:frametime] level=%s avg_ms=%.1f worst_ms=%.1f frames=%d",
            _level_key(), _ft_accum_ms / _ft_frames, _ft_worst_ms, _ft_frames)
        _ft_accum_ms, _ft_worst_ms, _ft_frames, _ft_elapsed = 0, 0, 0, 0
    end
    if _pending_auto_skip_system then
        local sys = _pending_auto_skip_system
        _pending_auto_skip_system = nil
        -- Capture the at-rest skip gate value OUTSIDE the pcall so we can restore it on
        -- EVERY path below (issue 275): a throw inside skip_pressed must never leak a
        -- latched script_data.skippable_cutscenes = true. Vanilla skip_pressed checks
        -- `self.active_camera and script_data.skippable_cutscenes` itself, but we also
        -- guard here so we don't blow up if the cutscene was already torn down before
        -- our tick fired (race with another mod or the cutscene ending naturally).
        local saved_skippable = script_data.skippable_cutscenes
        local ok, err = pcall(function()
            -- Re-verify the exact intro event at fire time. The field is niled on
            -- skip/deactivate, so a still-live intro retains it here. Any changed or
            -- unknown identity is preserved.
            if sys.active_camera and _gut_cutscene_is_intro(sys) then
                -- Scope-unlock ONLY around this skip_pressed. At rest
                -- script_data.skippable_cutscenes stays unset (retail default, issue
                -- 275); we set it true just so vanilla's gate
                -- `if self.active_camera and script_data.skippable_cutscenes` fires.
                -- Also swallow the post-skip fade-OUT.
                script_data.skippable_cutscenes = true
                _skip_next_fade = true
                -- DIAGNOSTIC (#106): the deferred tick + before/after teardown state.
                -- force_unlock is always true here now: we only reach this for a
                -- exact intro event (issue 274).
                _printf("[gut:cutscene] AUTO-SKIP deferred-tick firing | level=%s force_unlock=%s skippable=%s | before: %s",
                    _level_key(), tostring(true), tostring(script_data.skippable_cutscenes), _cs_snapshot(sys))
                sys:skip_pressed()
                _printf("[gut:cutscene] AUTO-SKIP deferred-tick done | after: %s", _cs_snapshot(sys))
            elseif sys.active_camera then
                _printf("[gut:274] pending cutscene no longer identifies as intro; preserved | level=%s on_skip=%s",
                    _level_key(), tostring(sys.event_on_skip))
            end
        end)
        -- Restore the at-rest skip gate unconditionally (see saved_skippable note above).
        script_data.skippable_cutscenes = saved_skippable
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
    -- issue 275 / issue 537: do NOT latch script_data.skippable_cutscenes ON. At rest the
    -- engine skip gate stays at its pre-gut value; the hooks scope-unlock it only around a
    -- skip_pressed call on the exact `cs_01_skip` mission intro. When disabling,
    -- restore the captured pre-gut value via the shared own-or-pin helper (same path the
    -- VMF checkbox uses in on_setting_changed) rather than clobbering a co-installed mod's
    -- set to a hardcoded nil.
    if not new_val then mod._gut_restore_skippable_cutscenes() end
    mod:echo("Skip cutscenes: " .. (new_val and "ON" or "OFF"))
end

mod:command("skipcutscenes", "Toggle mission-intro skipping (auto-skip if 'Auto-skip' is enabled; otherwise allows ESC/Space during the intro)", function()
    mod.gut_skip_cutscenes_toggle()
end)

-- issue 275: NO load-time latch. Previously gut set script_data.skippable_cutscenes
-- = true at load whenever the toggle was on, which force-unlocked EVERY cutscene
-- engine-wide (including author-locked boss cinematics like Nurgloth on dlc_castle).
-- At rest the flag now stays unset, exactly like retail; the hooks scope-unlock it
-- only around an exact `cs_01_skip` mission intro.

mod:info("[gut] Skip Cutscenes installed (migrated from gt, issue #106; [gut:cutscene] printf diagnostic active; toggle: %s, auto: %s)",
    tostring(mod:get("gut_skip_cutscenes_enabled")), tostring(mod:get("gut_skip_cutscenes_auto")))

local _rt_checks = {}
for i = 1, #(_probe257.rt_checks or {}) do
    _rt_checks[#_rt_checks + 1] = _probe257.rt_checks[i]
end
_rt_checks[#_rt_checks + 1] = {
    name = "issue274_intro_only_cutscene_policy",
    fn = function()
        if not _policy274.is_intro("cs_01_skip") then
            return "issue 274 regression: canonical mission intro is no longer skippable"
        end
        if _policy274.is_intro(nil) then
            return "issue 274 regression: unidentified cutscene accepted"
        end
        local forbidden = {
            "cs_02_skip",
            "boss_phase_skip",
            "dlc_dwarf_whaling_outro",
            "well_of_dreams_outro",
        }
        for i = 1, #forbidden do
            if _policy274.is_intro(forbidden[i]) then
                return "issue 274 regression: non-intro cutscene accepted: "
                    .. tostring(forbidden[i])
            end
        end
    end,
}
_rt_checks[#_rt_checks + 1] = {
    name = "issue274_post_intro_guard_bounded",
    fn = function()
        -- ROUND 3: the guard is the _gut_cutscene_skipwindow episode window.
        -- Bounds: rolling grace positive, hard cap covers >= one grace and stays
        -- finite (dlc_dwarf_whaling's skipped timeline runs ~35.5 s; anything
        -- past the cap must pass so a legitimate later cutscene is never eaten).
        if _skipwindow.GRACE_SECONDS <= 0
            or _skipwindow.MAX_WINDOW_SECONDS < _skipwindow.GRACE_SECONDS
            or _skipwindow.MAX_WINDOW_SECONDS > 60 then
            return "issue 274 regression: skip window bounds drifted (grace="
                .. tostring(_skipwindow.GRACE_SECONDS) .. " cap="
                .. tostring(_skipwindow.MAX_WINDOW_SECONDS) .. ")"
        end
        local state, sys = _skipwindow.new(), {}
        _skipwindow.note_skip_executed(state, sys, "cs_01_skip", 0)
        if not _skipwindow.window_active(state, sys, 1) then
            return "issue 274 regression: skip window does not arm on a proven skip"
        end
        local release = _skipwindow.note_logic_activate(state, sys, "cs_02_skip", 2)
        if release ~= "released" or _skipwindow.window_active(state, sys, 2) then
            return "issue 274 regression: a new cutscene episode does not release the window"
        end
        _skipwindow.note_skip_executed(state, sys, "cs_01_skip", 10)
        if _skipwindow.window_active(state, sys, 10 + _skipwindow.MAX_WINDOW_SECONDS + 1) then
            return "issue 274 regression: skip window survives its hard cap"
        end
    end,
}

return { rt_checks = _rt_checks }
