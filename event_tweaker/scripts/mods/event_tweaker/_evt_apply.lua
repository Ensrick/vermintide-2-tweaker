local mod = get_mod("event_tweaker")

-- _evt_apply.lua — mid-game preset application (level reload plumbing)
--
-- The three hooked vanilla queries (get_special_events, get_active_events,
-- get_level_variation_data) are all consulted at level-load time, so a
-- preset change between loads is dormant until the next level swap.
-- Solution: when the user changes the preset, reload the current level.
--   - In a mission: retry_level() — re-runs append_live_event_mutators on
--     the new mutator list and rebuilds the mutator handler.
--   - In the keep, when the preset's target hub_level differs from the
--     current one: set_next_level(new_hub_level) + promote_next_level_data()
--     so AdventureMechanism.get_starting_level picks up the swap.
--   - In the keep, same hub_level (or no preset): retry_level() reloads
--     the current keep, which re-runs DialogueSystem's get_special_events
--     read; cheap and consistent.
-- Host-only. Vanilla clients re-sync via the standard level-load path.
-- Individual mutator checkboxes do NOT auto-reload (a quick pass of 5
-- checkboxes would trigger 5 reloads) — they use /event_apply.
--
-- Owned by: event_tweaker.lua entry point (dofile'd after _evt_selection).
-- Consumes mod._evt: active_preset, suppress_live_event. Owns the mod-wide
-- mod.on_setting_changed callback (VMF allows exactly one; do not assign it
-- anywhere else).

local ET = mod._evt

local active_preset       = ET.active_preset
local suppress_live_event = ET.suppress_live_event

local function is_host()
    return Managers.player and Managers.player.is_server
end

local function current_level_key()
    local lth = Managers.level_transition_handler
    return lth and lth:get_current_level_key()
end

local function is_in_hub()
    local key = current_level_key()
    local settings = key and LevelSettings and LevelSettings[key]
    return settings and settings.hub_level == true
end

local function target_hub_level()
    local preset = active_preset()
    if preset and preset.hub_level then
        return preset.hub_level
    end
    -- v0.4.10-dev: with suppress on (no preset), pin to vanilla "inn_level"
    -- so toggling suppress on while standing in inn_level_skulls/halloween
    -- triggers a keep swap back to the plain inn.
    if suppress_live_event() then
        return "inn_level"
    end
    -- Suppress off, no preset: don't dictate. apply_now will take the
    -- retry_level() branch and let Fatshark's get_level_variation_data
    -- pass through unchanged.
    return current_level_key()
end

local function apply_now(reason)
    if not is_host() then
        mod:echo("[event] only the lobby host can apply mid-game (vanilla mutator RPC sync requires host trigger)")
        return false
    end

    local game_mode = Managers.state and Managers.state.game_mode
    if not game_mode then
        mod:echo("[event] no active game mode — change will apply on next level load")
        return false
    end

    local cur = current_level_key()
    if is_in_hub() then
        local want = target_hub_level()
        if want ~= cur then
            -- Hub-level swap. set_next_level + promote queues the load;
            -- state_ingame's update loop picks it up via needs_level_load()
            -- and triggers the "load_next_level" transition.
            local lth = Managers.level_transition_handler
            lth:set_next_level(want)
            lth:promote_next_level_data()
            mod:echo("[event] %s — swapping keep %s -> %s", reason or "applying preset", tostring(cur), tostring(want))
            return true
        end
    end

    -- Mission, or keep with no hub_level change. retry_level reloads the
    -- current level key; on the way back in, append_live_event_mutators
    -- re-reads our hooked get_special_events.
    Managers.state.game_mode:retry_level()
    mod:echo("[event] %s — reloading %s", reason or "applying preset", tostring(cur))
    return true
end

mod:command("event_apply", "Reload the current level so preset + mutator changes take effect", function()
    apply_now("manual apply")
end)

mod.on_setting_changed = function(setting_id)
    -- Auto-reload on preset change and on suppress toggle. Individual
    -- mutator toggles use `event_apply` — otherwise a quick pass of 5
    -- checkboxes would trigger 5 reloads.
    if setting_id == "event_preset" then
        apply_now("event_preset changed")
    elseif setting_id == "suppress_live_event" then
        apply_now("suppress_live_event changed")
    end
end
