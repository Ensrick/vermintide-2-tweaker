local mod = get_mod("gut")

-- _gut_mainmenu.lua — Main Menu & Startup QoL
--
-- MIGRATED from general_tweaker (gt) 2026-06-29 (issue #190): this feature moved
-- out of gt and into gut. Behavior is UNCHANGED from gt's _gt_menu_qol.lua; only
-- the gt->gut namespacing changed (setting ids gt_skip_start_screen ->
-- gut_skip_start_screen, gt_return_to_menu_quits -> gut_return_to_menu_quits; chat
-- command /gt_quit -> /quit).
--
-- Reimplements the two behaviours of the "Straight to Keep & Quit Game" Workshop
-- mod (internal id "Goodbye Menu", by Amia) as two independent gut toggles (both
-- default OFF). Both are plain engine-data reassignments applied at load + on
-- setting change -- NOT hooks, so there is no VMF duplicate-hook concern. Each
-- captures the vanilla value once so the toggle can be turned back OFF cleanly.
--
-- Source citations into the decompiled vanilla source at
-- C:\Users\danjo\source\repos\Vermintide-2-Source-Code.

-- ----------------------------------------------------------------------------
-- A) Skip the launch start/title screen  ->  straight to the keep (main menu)
-- ----------------------------------------------------------------------------
-- `GameSettingsDevelopment.skip_start_screen` is read by the boot state machine
-- to bypass the "press any key" start screen and drop you at the main menu (the
-- keep hub): state_title_screen.lua:194/241/315/449, state_splash_screen.lua:349,
-- state_ingame.lua:1349, state_title_screen_main.lua:88/114/292. It's read during
-- boot, so the change takes effect on the NEXT game launch.
local _orig_skip_start
local _captured_skip = false
local function _apply_skip_start_screen(enabled)
    if not rawget(_G, "GameSettingsDevelopment") then return end
    if not _captured_skip then
        _orig_skip_start = GameSettingsDevelopment.skip_start_screen
        _captured_skip = true
    end
    if enabled then
        GameSettingsDevelopment.skip_start_screen = true
    else
        GameSettingsDevelopment.skip_start_screen = _orig_skip_start
    end
end

-- ----------------------------------------------------------------------------
-- B) "Return to Main Menu"  ->  Quit to Desktop
-- ----------------------------------------------------------------------------
-- The in-game ESC menu's "Return to Main Menu" entry runs the
-- `return_to_title_screen` transition, whose confirm-popup yes-action is
-- `do_return_to_title_screen` (scripts/ui/views/ingame_ui_settings.lua:104 +
-- :291). Pointing BOTH at the `quit_game` transition (:70) makes that menu entry
-- quit to desktop instead -- quit_game still shows the vanilla exit confirmation
-- popup, so it's not an unguarded instant exit. We reassign live fields on the
-- cached ingame_ui_settings.transitions table and capture the originals so the
-- toggle restores them.
local _ui_settings
local _orig_return, _orig_do_return
local _captured_transitions = false

local function _get_transitions()
    if not _ui_settings then
        local ok, settings = pcall(require, "scripts/ui/views/ingame_ui_settings")
        if ok then _ui_settings = settings end
    end
    return _ui_settings and _ui_settings.transitions
end

local function _apply_return_quits(enabled)
    local transitions = _get_transitions()
    if not transitions then return end
    if not _captured_transitions then
        _orig_return = transitions.return_to_title_screen
        _orig_do_return = transitions.do_return_to_title_screen
        _captured_transitions = true
    end
    if enabled then
        transitions.return_to_title_screen = transitions.quit_game
        transitions.do_return_to_title_screen = transitions.quit_game
    else
        transitions.return_to_title_screen = _orig_return
        transitions.do_return_to_title_screen = _orig_do_return
    end
end

-- Exposed on `mod` so the regression-style checks / future callers can drive them.
mod._gut_apply_skip_start_screen = _apply_skip_start_screen
mod._gut_apply_return_quits = _apply_return_quits

-- Apply persisted values at load so a friend who left either toggle ON gets the
-- behaviour without re-opening settings.
_apply_skip_start_screen(mod:get("gut_skip_start_screen"))
_apply_return_quits(mod:get("gut_return_to_menu_quits"))

-- Chain on_setting_changed (capture-prev / call-prev-first). Dofile'd after the
-- main file defines mod.on_setting_changed, so `prev` captures it.
do
    local prev = mod.on_setting_changed
    mod.on_setting_changed = function(setting_id)
        if prev then prev(setting_id) end
        if setting_id == "gut_skip_start_screen" then
            _apply_skip_start_screen(mod:get("gut_skip_start_screen"))
        elseif setting_id == "gut_return_to_menu_quits" then
            _apply_return_quits(mod:get("gut_return_to_menu_quits"))
        end
    end
end

-- Restore both behaviours on disable. Unlike most settings, the "Return to Main
-- Menu" remap silently changes a menu BUTTON's behaviour, so leaving it dangling
-- after disable would be especially confusing -- cheap to unwind.
do
    local prev = mod.on_disabled
    mod.on_disabled = function(...)
        if prev then prev(...) end
        _apply_return_quits(false)
        _apply_skip_start_screen(false)
    end
end

-- ----------------------------------------------------------------------------
-- Bonus: instant quit-to-desktop command (on-theme with "Quit Game")
-- ----------------------------------------------------------------------------
-- Application.quit() is the engine exit the game itself uses (boot.lua:906,
-- dedicated_server_commands.lua:176). This is a hard, immediate exit with no
-- confirmation -- deliberately, since it's a typed command. As host it drops the
-- lobby; clients just leave.
mod:command("quit", "Quit the game to desktop immediately (no confirmation).", function()
    if rawget(_G, "Application") and Application.quit then
        Application.quit()
    end
end)
