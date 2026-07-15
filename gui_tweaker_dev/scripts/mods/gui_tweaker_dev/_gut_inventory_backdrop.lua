local mod = get_mod("gut_dev")

-- Inventory character-preview lighting (#522).
--
-- The old implementation rewrote HeroWindowCharacterPreview's cached viewport
-- definition to mount alternate levels. In-game verification proved that this
-- was visually inert and targeted the wrong layer. This replacement leaves the
-- vanilla package, level, geometry, camera, and shading-environment resource
-- untouched. It changes only the exposure produced for the previewer's own
-- world after ScriptWorld has performed its normal environment blend.
--
-- Source boundary (Vermintide-2-Source-Code):
--   * HeroWindowCharacterPreview.post_update creates MenuWorldPreviewer and
--     stores it as self.world_previewer (hero_window_character_preview.lua).
--   * MenuWorldPreviewer.setup_viewport exposes the viewport pass world as
--     self.world (menu_world_previewer.lua).
--   * ScriptWorld.render blends the world's normal shading settings, invokes
--     World data key "shading_callback", then applies/renders the environment
--     (foundation/scripts/util/script_world.lua). A one-off scalar write before
--     that blend would be overwritten; a world-local callback is the native
--     post-blend seam.
--
-- The callback is allocated/installed once per live preview world. Its hot path
-- allocates nothing: it chains the exact prior callback, reads exposure, and
-- multiplies it. Setting changes update one captured number. Vanilla, window
-- exit, and mod disable restore the exact prior callback (or remove our data key
-- when the world originally had none). No keep/mission world is ever looked up.

local _pf = rawget(_G, "printf") or function(fmt, ...) print(string.format(fmt, ...)) end

local SETTING_ID = "gut_inventory_backdrop"
local PROFILES = {
    vanilla = 1,
    dim = 0.65,
    dark = 0.4,
}
local LEGACY_CHOICES = {
    dark_camp = "dim",
    victory_camp = "dark",
}

local function _normalize_choice(value)
    value = LEGACY_CHOICES[value] or value
    if PROFILES[value] == nil then
        return "vanilla"
    end
    return value
end

local function _selected_choice()
    return _normalize_choice(mod:get(SETTING_ID))
end

-- Weak keys keep a destroyed vanilla window/world from being retained if an
-- engine teardown bypasses the ordinary on_exit path.
local _active_windows = setmetatable({}, { __mode = "k" })
local _world_states = setmetatable({}, { __mode = "k" })
local _warned_missing_api = false

local function _preview_world(window)
    local previewer = window and window.world_previewer
    return previewer and previewer.world or nil
end

local function _restore_world(world, reason)
    local state = world and _world_states[world]
    if not state then
        return false
    end

    local WorldApi = rawget(_G, "World")
    if not WorldApi or type(WorldApi.get_data) ~= "function" or type(WorldApi.set_data) ~= "function" then
        _world_states[world] = nil
        return false
    end

    -- Never overwrite a callback another system installed after ours. Under
    -- normal ownership this equality is true and restoration is byte-exact.
    local current = WorldApi.get_data(world, "shading_callback")
    if current == state.callback then
        WorldApi.set_data(world, "shading_callback", state.had_prior and state.prior or nil)
        _pf("[gut_dev:522] inventory preview lighting RESTORE (%s)", tostring(reason or "unspecified"))
    else
        _pf("[gut_dev:522] inventory preview callback ownership changed; restore skipped")
    end

    _world_states[world] = nil
    return current == state.callback
end

local function _bind_world(world, choice)
    local multiplier = PROFILES[choice]
    if not world or not multiplier then
        return false
    end

    local state = _world_states[world]
    if choice == "vanilla" then
        if state then
            _restore_world(world, "Vanilla selected")
        end
        return true
    end

    if state then
        if state.choice ~= choice then
            state.choice = choice
            state.multiplier = multiplier
            _pf("[gut_dev:522] inventory preview lighting UPDATE: %s (exposure x%.2f)", choice, multiplier)
        end
        return true
    end

    local WorldApi = rawget(_G, "World")
    local ShadingApi = rawget(_G, "ShadingEnvironment")
    if not WorldApi
        or type(WorldApi.has_data) ~= "function"
        or type(WorldApi.get_data) ~= "function"
        or type(WorldApi.set_data) ~= "function"
        or not ShadingApi
        or type(ShadingApi.scalar) ~= "function"
        or type(ShadingApi.set_scalar) ~= "function"
    then
        if not _warned_missing_api then
            _warned_missing_api = true
            _pf("[gut_dev:522] inventory preview lighting unavailable: shading callback API missing")
        end
        return false
    end

    local had_prior = WorldApi.has_data(world, "shading_callback")
    local prior = had_prior and WorldApi.get_data(world, "shading_callback") or nil
    state = {
        choice = choice,
        multiplier = multiplier,
        had_prior = had_prior,
        prior = prior,
    }

    -- Zero-allocation hot path. ScriptWorld invokes this after its normal blend
    -- and calls ShadingEnvironment.apply immediately afterward.
    state.callback = function(callback_world, shading_env, viewport)
        if state.prior then
            state.prior(callback_world, shading_env, viewport)
        end
        if shading_env then
            local exposure = ShadingApi.scalar(shading_env, "exposure")
            if type(exposure) == "number" then
                ShadingApi.set_scalar(shading_env, "exposure", exposure * state.multiplier)
            end
        end
    end

    _world_states[world] = state
    WorldApi.set_data(world, "shading_callback", state.callback)
    _pf("[gut_dev:522] inventory preview lighting APPLY: %s (exposure x%.2f)", choice, multiplier)
    return true
end

local function _apply_window(window, reason)
    if not window then
        return false
    end
    _active_windows[window] = true

    local world = _preview_world(window)
    local prior_world = window._gut_522_preview_world
    if prior_world and prior_world ~= world then
        _restore_world(prior_world, "preview world replaced")
    end
    window._gut_522_preview_world = world

    if not world then
        return false
    end
    return _bind_world(world, _selected_choice(), reason)
end

local function _release_window(window, reason)
    if not window then
        return
    end
    local world = window._gut_522_preview_world or _preview_world(window)
    if world then
        _restore_world(world, reason)
    end
    window._gut_522_preview_world = nil
    _active_windows[window] = nil
end

-- Exposed for the runtime regression harness and the source-backed Lua suite.
mod._gut_inv_lighting_profiles = PROFILES
mod._gut_inv_lighting_normalize = _normalize_choice
mod._gut_inv_lighting_apply = _apply_window
mod._gut_inv_lighting_restore = _release_window

-- The first post_update that creates MenuWorldPreviewer binds the world. Later
-- frames hit only identity/table checks; no closure/table is allocated again.
mod:hook("HeroWindowCharacterPreview", "post_update", function(func, self, ...)
    func(self, ...)
    _apply_window(self, "post_update")
end)

-- Restore before vanilla destroys MenuWorldPreviewer and its world.
mod:hook("HeroWindowCharacterPreview", "on_exit", function(func, self, ...)
    _release_window(self, "window exit")
    return func(self, ...)
end)

local _prev_setting_changed = mod.on_setting_changed
mod.on_setting_changed = function(setting_id, ...)
    if _prev_setting_changed then
        _prev_setting_changed(setting_id, ...)
    end
    if setting_id == SETTING_ID then
        for window in pairs(_active_windows) do
            _apply_window(window, "setting changed")
        end
    end
end

local _prev_on_disabled = mod.on_disabled
mod.on_disabled = function(...)
    if _prev_on_disabled then
        _prev_on_disabled(...)
    end
    for window in pairs(_active_windows) do
        _release_window(window, "mod disabled")
    end
end

local M = { rt_checks = {} }

M.rt_checks[#M.rt_checks + 1] = {
    name = "inventory_preview_lighting_522",
    fn = function()
        if PROFILES.vanilla ~= 1 or PROFILES.dim ~= 0.65 or PROFILES.dark ~= 0.4 then
            return "issue 522 exposure profiles drifted"
        end
        if _normalize_choice("dark_camp") ~= "dim" or _normalize_choice("victory_camp") ~= "dark" then
            return "issue 522 legacy setting migration drifted"
        end
        local cls = rawget(_G, "HeroWindowCharacterPreview")
        if type(cls) ~= "table" or type(cls.post_update) ~= "function" or type(cls.on_exit) ~= "function" then
            return "HeroWindowCharacterPreview lifecycle missing (lighting hook orphaned)"
        end
        if type(mod._gut_inv_lighting_apply) ~= "function" or type(mod._gut_inv_lighting_restore) ~= "function" then
            return "issue 522 lighting lifecycle not wired"
        end
    end,
}

return M
