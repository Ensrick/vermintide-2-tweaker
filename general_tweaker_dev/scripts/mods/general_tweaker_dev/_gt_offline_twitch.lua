local mod = get_mod("gt_dev")
local policy = mod:dofile("scripts/mods/general_tweaker_dev/_gt_offline_twitch_policy")

-- Issue #333: the native debug-voting lifecycle, without requiring IRC.
mod._GT333_OFFLINE_TWITCH_MARKER = "gt-333-native-offline-votes-single-whitelist-gate"

local function _enabled()
    return mod:get("gt_offline_twitch_enabled") == true
end

local function _host()
    local network = Managers.state and Managers.state.network
    return network and network.is_server == true
end

local function _allowed_categories()
    return {
        buffs = mod:get("gt_offline_twitch_allow_buffs") == true,
        items = mod:get("gt_offline_twitch_allow_items") == true,
        mutators = mod:get("gt_offline_twitch_allow_mutators") == true,
        spawns = mod:get("gt_offline_twitch_allow_spawns") == true,
    }
end

-- Vanilla has registered the delegate and validated the mode when this resumes.
-- Only synthesize connectivity for an offline host; a real Twitch connection is
-- left intact. Vanilla still owns timers, effects, UI, game objects and RPCs.
mod:hook("TwitchManager", "activate_twitch_game_mode", function(func, self, network_event_delegate, game_mode_key, ...)
    local result = func(self, network_event_delegate, game_mode_key, ...)
    local game_mode_class = rawget(_G, "TwitchGameMode")
    if _enabled() and _host() and not self._connected and not self._twitch_game_mode
            and game_mode_class and self:game_mode_supported(game_mode_key) then
        self._twitch_game_mode = game_mode_class:new(self)
        self:_load_sound_bank()
        self._activated = true
        self._connected = true
        self._gt333_offline_active = true
        mod:info("[gt:333] offline Twitch active; native timers/RPCs, local random resolution")
    end
    return result
end)

-- An absent IRC connection must not tear down deliberate offline voting or show
-- Twitch's return-to-inn popup.
mod:hook("TwitchManager", "cb_on_notify_connected", function(func, self, connected, ...)
    if self._gt333_offline_active and not connected then
        self._connecting = false
        return
    end
    -- A genuine late connection takes ownership of manager connectivity. Keep
    -- the already-running game mode, but let vanilla disconnect it normally.
    if self._gt333_offline_active and connected then
        self._gt333_offline_active = nil
    end
    return func(self, connected, ...)
end)

-- Vanilla first destroys votes and unregisters the delegate. Clearing synthetic
-- connectivity afterwards prevents a later manager disconnect from touching IRC.
mod:hook("TwitchManager", "deactivate_twitch_game_mode", function(func, self, ...)
    local offline = self._gt333_offline_active
    local result = func(self, ...)
    if offline then
        self._gt333_offline_active = nil
        self._connected = false
    end
    return result
end)

-- This gate is shared by standard and forced positive/negative selection. The
-- filters intentionally also apply to a linked account while the option is on.
mod:hook("TwitchGameMode", "_in_whitelist", function(func, self, template_name, ...)
    if not func(self, template_name, ...) then return false end
    if not _enabled() then return true end
    local templates = rawget(_G, "TwitchVoteTemplates")
    local template = templates and templates[template_name]
    return policy.is_allowed(template_name, template, _allowed_categories())
end)

mod._gt_rt_register("issue333_offline_twitch_policy", function()
    if mod._GT333_OFFLINE_TWITCH_MARKER ~= "gt-333-native-offline-votes-single-whitelist-gate" then
        return "issue 333 provenance marker missing"
    end
    if policy.category("twitch_give_potion", {}) ~= "items"
            or policy.category("twitch_spawn_rat_ogre", { boss = true }) ~= "spawns"
            or policy.category("x", { description = "description_mutator_splitting_enemies" }) ~= "mutators" -- name-integrity: non-rendered-test-data
            or policy.category("twitch_vote_speed", {}) ~= "buffs" then
        return "issue 333 vote classifier contract failed"
    end
end)
