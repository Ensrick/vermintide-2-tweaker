local mod = get_mod("enemy_tweaker")

-- _et_lifecycle.lua — VMF lifecycle callbacks
--
-- on_setting_changed / on_disabled / on_enabled: the re-apply / restore
-- chains over every provider module. VMF allows exactly ONE assignment of
-- each callback mod-wide and they live HERE — never assign them in another
-- file.
--
-- Owned by: enemy_tweaker.lua entry point (dofile'd after every provider it
-- consumes: presets, swaps, mimic, roaming, champion, banner). No mod._et
-- exports.

local ET = mod._et
local _dbg_alert = ET.dbg_alert
local _safe      = ET.safe

local _restore_compositions  = ET.restore_compositions
local _apply_horde_preset    = ET.apply_horde_preset
local _apply_roaming_size_multiplier  = ET.apply_roaming_size_multiplier
local _restore_size_of_interest_point = ET.restore_size_of_interest_point
local _apply_banner_bearer_stagger_toggle = ET.apply_banner_bearer_stagger_toggle
local _apply_banner_camera_jerk_toggle    = ET.apply_banner_camera_jerk_toggle
local _build_swap_map         = ET.build_swap_map
local _build_faction_swap_map = ET.build_faction_swap_map
local _apply_faction_swap_to_current_horde_settings = ET.apply_faction_swap_to_chs
local _apply_champion_breed_overrides = ET.apply_champion_breed_overrides
local _apply_difficulty_mimic = ET.apply_difficulty_mimic
local _original_compositions_pacing_ref = ET.original_compositions_pacing

local function _reapply_via_active_cd()
    -- For settings whose effect lives on the Current* tables (faction-swap,
    -- difficulty-mimic), we need an active ConflictDirector to re-patch
    -- against. If we're in the keep / no mission active, the next mission's
    -- init hook will pick up new settings automatically.
    local active = Managers.state and Managers.state.conflict
    if active then
        _apply_difficulty_mimic(active)
        _apply_faction_swap_to_current_horde_settings()
    end
end

local function _apply_setting_changes(setting_ids, latest_setting_id)
    local setting_count = #setting_ids
    local trigger = setting_count > 1
        and string.format("batch:%d:last=%s", setting_count, tostring(latest_setting_id))
        or tostring(latest_setting_id)
    -- v0.6.0-dev: wrapped in _safe so any single sub-step failure (corrupt
    -- composition, missing global, etc.) is logged via mod:warning and
    -- the rest of the chain still runs. Previously a crash in one apply
    -- function could leave Current* settings half-applied with no log.
    if not _original_compositions_pacing_ref() then
        _dbg_alert("on_setting_changed: _original_compositions_pacing nil (mod loaded but compositions never backed up) — skipping composition reapply")
    else
        _safe("on_setting_changed:restore",       _restore_compositions)
        _safe("on_setting_changed:apply_preset",  _apply_horde_preset)
        _safe("on_setting_changed:apply_roaming", _apply_roaming_size_multiplier)
        _safe("on_setting_changed:apply_banner",  _apply_banner_bearer_stagger_toggle)
        _safe("on_setting_changed:apply_banner_camera", _apply_banner_camera_jerk_toggle)
        _safe("on_setting_changed:build_swap",    _build_swap_map)
        _safe("on_setting_changed:build_faction", _build_faction_swap_map)
        _safe("on_setting_changed:reapply_active_cd", _reapply_via_active_cd)
        -- Issue #18: mid-session setting edits previously left the
        -- ConflictDirector's threat-value cache and CurrentHordeSettings
        -- stale until the next zone boundary. on_enabled already reseeds;
        -- mirror the same reseed here for any setting change. Permissive
        -- trigger (any et setting) — every group (horde / mimic / specials /
        -- breed-swap / faction-swap) can plausibly influence the cache,
        -- and a no-op refresh between zones is cheap.
        _safe("on_setting_changed:refresh_cd", function()
            local active = Managers.state and Managers.state.conflict
            if active then
                active:refresh_conflict_director_patches("on_setting_changed:" .. trigger)
            end
        end)
        mod:info("[et] settings updated (setting=%s)", trigger)
    end
    -- Re-apply the boss fly-disable multiplier on any setting change (spawn
    -- paths read the data fields live). Guarded: the boss-tweaks module is
    -- dofile'd after this one in the manifest, so mod._et_apply_fly_disable
    -- may be nil for the very first on_setting_changed if it somehow fires
    -- pre-load.
    if mod._et_apply_fly_disable then
        _safe("on_setting_changed:fly_disable", mod._et_apply_fly_disable)
    end
    -- #450 boss balance toggles — same nil-guard rationale as fly-disable
    -- (the _et_boss_balance module is dofile'd after this one). Re-applies
    -- health/armor/warp-lightning from the pristine vanilla snapshot per the
    -- current toggle state (recompute-from-snapshot = revert-safe).
    if mod._et_apply_boss_balance then
        _safe("on_setting_changed:boss_balance", mod._et_apply_boss_balance)
    end
    -- #369: one live rescale per queued settings transaction. This runs after
    -- boss-balance data restoration so current and future enemies agree.
    if mod._et_apply_health_multipliers then
        _safe("on_setting_changed:health_multiplier", mod._et_apply_health_multipliers)
    end
    if ET.personal_handicap_setting_changed then
        _safe("on_setting_changed:personal_handicap", ET.personal_handicap_setting_changed)
    end
    -- Champion elite-pool retune — outside the compositions guard (independent of
    -- composition backup state; idempotent, only writes on a toggle-state change).
    _safe("on_setting_changed:champion", _apply_champion_breed_overrides)
    printf("[et:560] applied settings=%d trigger=%s lua_kb=%.0f",
        setting_count, trigger, collectgarbage("count"))
end

-- Issue #560: one DEFAULT reset generated 249 synchronous VMF notifications.
-- Each old callback restored/copied every composition and refreshed the active
-- director; the game exhausted its 1 GiB Lua heap after only 34 callbacks. Both
-- ordinary VMF events and Mod Tweaker's opt-in batch callback now enqueue into
-- one next-frame apply. The one-frame delay is the transaction boundary.
local _settings_queue = ET.SettingsQueue.new(_apply_setting_changes)
ET.settings_queue = _settings_queue

mod.on_setting_changed = function(setting_id)
    _settings_queue.enqueue(setting_id)
end

mod.on_settings_batch_changed = function(setting_ids)
    _settings_queue.enqueue_many(setting_ids)
end

local _previous_update = mod.update
mod.update = function(dt)
    if _previous_update then _previous_update(dt) end
    _settings_queue.drain()
    if ET.personal_handicap_update then ET.personal_handicap_update() end
    -- #450 registers this provider after the lifecycle module loads. Dynamic
    -- dispatch keeps the single mod.update owner while monitoring the one live
    -- Halescourge unit for its Cataclysm half-health threshold.
    if ET.boss_behavior_update then ET.boss_behavior_update() end
end

ET.rt_register("issue560_settings_reapply_coalesced", function()
    if type(mod.on_settings_batch_changed) ~= "function" then
        return "batch completion callback missing"
    end
    if type(ET.settings_queue) ~= "table" or type(ET.settings_queue.drain) ~= "function" then
        return "settings queue is not wired to lifecycle"
    end
end)

mod.on_disabled = function()
    _settings_queue.clear()
    if ET.personal_handicap_clear then ET.personal_handicap_clear() end
    _safe("on_disabled:restore_compositions",      _restore_compositions)
    _safe("on_disabled:restore_size_of_interest",  _restore_size_of_interest_point)
    -- v0.7.2-dev: explicitly restore vanilla bearer stagger-immunity if we
    -- had patched it. Setting read returns falsy when the toggle is off OR
    -- when the mod is disabled, so calling _apply_ does the right thing.
    _safe("on_disabled:restore_banner_bearer_stagger", _apply_banner_bearer_stagger_toggle)
    _safe("on_disabled:restore_banner_camera", function() _apply_banner_camera_jerk_toggle(true) end)
    ET.clear_swap_maps()
    -- Note: we can't undo the in-place CurrentHordeSettings rewrite from here
    -- without rebuilding it from director.horde. The next refresh_conflict_director_patches
    -- (zone change, level transition) will rebuild it from scratch — and our
    -- hook will be inactive, so no swap is re-applied. Within the same active
    -- CD, the swap remains until the next refresh.
    -- Restore the vanilla Champion breed (mod:get returns falsy when disabled,
    -- so _apply_ takes the restore branch).
    _safe("on_disabled:champion", _apply_champion_breed_overrides)
    -- #450: mod:get returns falsy while disabled, so _apply_ restores every
    -- boss field to its vanilla snapshot.
    if mod._et_apply_boss_balance then
        _safe("on_disabled:boss_balance", mod._et_apply_boss_balance)
    end
    if mod._et_apply_health_multipliers then
        _safe("on_disabled:health_multiplier", mod._et_apply_health_multipliers)
    end
    mod:echo("Enemy Tweaker disabled — compositions restored")
end

mod.on_enabled = function()
    if ET.personal_handicap_setting_changed then ET.personal_handicap_setting_changed() end
    if not _original_compositions_pacing_ref() then
        _dbg_alert("on_enabled: _original_compositions_pacing nil — mod loaded but ConflictDirector.init hasn't fired yet; will apply on next mission load")
    else
        _safe("on_enabled:apply_preset",       _apply_horde_preset)
        _safe("on_enabled:apply_roaming",      _apply_roaming_size_multiplier)
        _safe("on_enabled:apply_banner",       _apply_banner_bearer_stagger_toggle)
        _safe("on_enabled:apply_banner_camera", _apply_banner_camera_jerk_toggle)
        _safe("on_enabled:build_swap",         _build_swap_map)
        _safe("on_enabled:build_faction",      _build_faction_swap_map)
        _safe("on_enabled:reapply_active_cd",  _reapply_via_active_cd)
        -- Issue #9: reseed ConflictDirector's threat-value cache on re-enable.
        -- When the mod is toggled OFF then back ON mid-mission, the director's
        -- Current* settings were baked at init (when hooks were inactive). Call
        -- refresh_conflict_director_patches to invalidate the threat-value cache
        -- and performance-manager state — zone-boundary auto-fixes it, but we
        -- harden the seeding here to feel less broken until then.
        _safe("on_enabled:refresh_cd", function()
            local active = Managers.state and Managers.state.conflict
            if active then
                active:refresh_conflict_director_patches("on_enabled")
                mod:info("[et:on_enabled] reseeded threat-values via refresh_conflict_director_patches (%s)", os.date())
            end
        end)
        mod:echo("Enemy Tweaker enabled")
    end
    -- Outside the guard: re-assert the Champion retune per its saved toggle.
    _safe("on_enabled:champion", _apply_champion_breed_overrides)
    -- #450: re-assert boss balance toggles per their saved state on re-enable.
    if mod._et_apply_boss_balance then
        _safe("on_enabled:boss_balance", mod._et_apply_boss_balance)
    end
    if mod._et_apply_health_multipliers then
        _safe("on_enabled:health_multiplier", mod._et_apply_health_multipliers)
    end
end
