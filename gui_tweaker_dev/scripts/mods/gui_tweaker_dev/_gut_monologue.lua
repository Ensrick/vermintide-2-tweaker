local mod = get_mod("gut_dev")

-- _gut_monologue.lua — Disable Loading-Screen Monologues
--
-- MIGRATED from general_tweaker (gt) 2026-06-29 (issue #192): the cutscene SKIP
-- half of gt's "Cutscenes & Monologues" group moved to gut earlier (issue #106,
-- _gut_cutscenes.lua); this is the REMAINDER — the loading-screen monologue toggle.
-- Behavior is UNCHANGED from gt's _gt_godmode_qol.lua monologue block; only the
-- gt->gut namespacing changed (setting id gt_disable_intro_monologue ->
-- gut_disable_intro_monologue; chat command /gt_intromono -> /intromono).
--
-- Setting `script_data.disable_level_intro_dialogue` to true makes
-- state_loading.lua:585 + :635 skip Lohner/Olesya/weave-loading VO. This is the
-- same flag the vanilla debug screen exposes ("Visual/audio -> Disables the level
-- introduction by Lohner / Olesya"), so it's the canonical no-monologue toggle —
-- no hooks required.

local function _apply(enabled)
    script_data = script_data or {}
    script_data.disable_level_intro_dialogue = enabled and true or nil
end

-- Apply the persisted value at load (covers the first level before any toggle).
_apply(mod:get("gut_disable_intro_monologue"))

mod.gut_intro_monologue_toggle = function()
    local new_val = not mod:get("gut_disable_intro_monologue")
    mod:set("gut_disable_intro_monologue", new_val)
    _apply(new_val)
    mod:echo("Loading-screen monologues: " .. (new_val and "DISABLED" or "enabled"))
end

-- Chain on_setting_changed (capture-prev / call-prev-first). Dofile'd after the
-- main file defines mod.on_setting_changed, so `prev` captures it.
do
    local prev = mod.on_setting_changed
    mod.on_setting_changed = function(setting_id)
        if prev then prev(setting_id) end
        if setting_id == "gut_disable_intro_monologue" then
            _apply(mod:get("gut_disable_intro_monologue"))
        end
    end
end

mod:command("intromono", "Toggle the Lohner/Olesya loading-screen monologues", function()
    mod.gut_intro_monologue_toggle()
end)
