-- Owns boon-module installation plus the VMF setting and disable lifecycle.
return function(mod, ctx)
    local AdventurePool = ctx.adventure_pool
    local MOD_VERSION = ctx.mod_version
    local _ct_mutex = ctx.mutex
    local _dbg = ctx.dbg
    local _dump_pickup_system_state = ctx.dump_pickup_system_state
    local _rt_register = ctx.rt_register
    local effective_setting = ctx.effective_setting
    local sync_bomb_cooldown
    local sync_boon_movespeed
    local sync_grudge_marks = ctx.sync_grudge_marks
    local sync_host_dependent_state
    local is_pool_setting
    local sync_reckless_swings
    local sync_ulric_pack_unlimited_range

mod._ct_boon_balance = mod:dofile(
    "scripts/mods/chaos_wastes_tweaker_dev/_ct_boon_balance")
mod._ct_boon_registry = mod:dofile(
    "scripts/mods/chaos_wastes_tweaker_dev/_ct_boon_registry")
mod._ct_meta_trait_boons = mod:dofile(
    "scripts/mods/chaos_wastes_tweaker_dev/_ct_meta_trait_boons")
mod._ct_boon_runtime_context = nil
-- issue 249: parity-restore stack re-broadcast. Registers a second gated
-- feature on the beacon _ct_meta_trait_boons just installed, so this load
-- position (directly after it, before the first gate tick) is load-bearing.
mod:dofile("scripts/mods/chaos_wastes_tweaker_dev/_ct_stack_rebroadcast_owner")(mod, {
    rt_register = _rt_register,
})

-- Preserve the established forward-declared entry-chunk surfaces used by
-- earlier hook closures. VMF invokes those closures only after module load.
sync_reckless_swings = mod._ct_boon_balance.sync_reckless_swings
sync_bomb_cooldown = mod._ct_boon_balance.sync_bomb_cooldown
sync_ulric_pack_unlimited_range = mod._ct_boon_balance.sync_ulric_pack_unlimited_range
sync_boon_movespeed = mod._ct_boon_balance.sync_boon_movespeed
sync_host_dependent_state = mod._ct_meta_trait_boons.sync_host_dependent_state

_rt_register("issue2_boon_runtime_extracted", function()
    if mod._ct_boon_runtime_context ~= nil then
        return "short-lived boon runtime context was not cleared"
    end
    if type(mod._ct_boon_balance) ~= "table"
        or type(mod._ct_boon_registry) ~= "table"
        or type(mod._ct_meta_trait_boons) ~= "table" then
        return "one or more boon runtime owner modules did not load"
    end
    if sync_reckless_swings ~= mod._ct_boon_balance.sync_reckless_swings
        or sync_host_dependent_state ~= mod._ct_meta_trait_boons.sync_host_dependent_state then
        return "entry forward surfaces do not match extracted owners"
    end
end)

-- ============================================================
-- Combat / proc / Chest-of-Trials runtime hooks -> _ct_combat_hooks.lua
-- (repo issue #2 file-size refactor). Loaded HERE so hook registration and the
-- load-time trial injection keep their original execution point. Single dofile.
-- ============================================================
mod:dofile("scripts/mods/chaos_wastes_tweaker_dev/_ct_combat_hooks")

-- Pool-affecting settings: master toggle, per-CW-scenario toggles, and per-adventure
-- toggles. Re-run inject_pool() on any of these so changes take effect without a
-- restart. The engine reads LEVEL_AVAILABILITY at run setup (DeusMechanism._setup_run)
-- — changes only affect the NEXT expedition, not a CW run already underway.
is_pool_setting = function(setting_id)
    if setting_id == "inject_adventure_maps" then return true end
    if type(setting_id) ~= "string" then return false end
    return setting_id:find("^enable_adventure_") ~= nil
        or setting_id:find("^enable_cw_") ~= nil
        or setting_id:find("^enable_group_") ~= nil  -- #457 group master toggles
end

mod.on_setting_changed = function(setting_id)
    if mod._ct919_profile_setting_changed then
        mod._ct919_profile_setting_changed(setting_id)
    end
    -- Mutex cluster enforcement (v0.7.81 — see LOCALIZATION_STANDARD.md § 10).
    -- Runs BEFORE everything else so a cluster toggle-on programmatically
    -- unchecks its siblings before downstream apply logic dispatches on the
    -- now-canonical state.
    if _ct_mutex and _ct_mutex.enforce then _ct_mutex.enforce(setting_id) end

    -- Issue #6 auto-probe: log when any of the 4 chest_*_count settings change
    -- locally. Whatever the user just toggled has yet to be broadcast as
    -- effective_setting via ct_sync_host_settings_chunk — this line is the local
    -- "what I clicked" record so post-session log diff can attribute divergence
    -- to a per-peer mis-toggle vs an actual sync failure.
    if setting_id == "chest_upgrade_count" or setting_id == "chest_swap_melee_count"
            or setting_id == "chest_swap_ranged_count" or setting_id == "chest_power_up_count" then
        _dbg("[altar:setting_changed] %s = %s (broadcasting now via _ct_broadcast_host_settings)",
            setting_id, tostring(mod:get(setting_id)))
    end

    -- MIDRUN_SETTING_REBROADCAST_MARKER: on_setting_changed:rebroadcast-synced-host-settings
    -- Host edited a setting mid-run -> re-push the whole synced registry to all clients over
    -- the existing ct_sync_host_settings_chunk RPC, so their _ct_host_settings (and thus
    -- effective_setting) pick up the new value on the next boon/altar roll instead of staying
    -- frozen until the next setup_run (the boons-per-chest/shrine mid-run desync reported
    -- 2026-06-17). Gated to host + synced settings so per-peer / UI-only edits (e.g. the
    -- starting_coins snap below) don't spam the net; a client receiving duplicate values is a
    -- harmless no-op assignment.
    -- #205: mark dirty + (re)arm the debounce instead of broadcasting inline. The gut Mod
    -- Tweaker's Apply commits its whole staged batch at once, firing on_setting_changed
    -- hundreds of times in one frame; an inline broadcast per call meant hundreds of full
    -- 489-key encodes + 46-chunk enqueues in a single frame (the reliable-queue-overflow
    -- HOST CRASH — capped by the supersede guard, but still a heavy hitch). mod.update drains
    -- this ONCE after the burst settles. The ~0.5s sync latency for a lone edit is harmless
    -- (clients apply on the next roll, seconds away).
    do
        local is_server = Managers and Managers.player and Managers.player.is_server
        if is_server and type(setting_id) == "string"
            and mod._ct_synced_set and mod._ct_synced_set[setting_id] then
            mod._ct_settings_sync_pending = true
            mod._ct_settings_sync_countdown = 0.5
        end
    end

    if setting_id == "starting_coins" then
        -- (#164) NO snap here. VMF's own options menu is intentionally left at its natural
        -- fine granularity so the user can dial an exact value (e.g. 324); the coarse 25-step
        -- lives ONLY in gut's Mod Tweaker (its STEP_OVERRIDES registry). Whatever value is
        -- stored is applied verbatim as the run's starting coins at setup_run. The early
        -- return preserves the prior control flow (starting_coins drives none of the syncs below).
        return
    end
    if setting_id == "tweak_reckless_swings" then
        sync_reckless_swings()
    elseif setting_id == "bomb_boon_cooldown" then
        sync_bomb_cooldown()
    elseif setting_id == "ulric_pack_unlimited_range" then
        sync_ulric_pack_unlimited_range()
    elseif setting_id == "tweak_boon_movespeed" then
        sync_boon_movespeed()
    elseif setting_id == "tweak_poison_proof_duration" then
        mod._ct_boon_balance.sync_poison_proof_tweak()
    elseif setting_id == "tweak_invis_potion_2x" then
        mod._ct_boon_balance.sync_invis_potion_tweak()
    elseif setting_id == "tweak_moot_milk_alt" then
        mod._ct_boon_balance.sync_moot_milk_alt_tweak()
    elseif setting_id == "tweak_shard_strike_duration" then
        mod._ct_boon_balance.sync_shard_strike()
    elseif setting_id == "tweak_anath_raema_permanent" then
        mod._ct_boon_balance.sync_anath_raema_permanent()
    elseif setting_id == "tweak_shadow_skull_stun_sec" then
        if mod._ct_sync_shadow_skull_stun then mod._ct_sync_shadow_skull_stun() end
    elseif setting_id == "miasma_permanent_carrier"
        or setting_id == "miasma_safe_radius" or setting_id == "miasma_stack_interval" then
        if mod._ct_sync_miasma then mod._ct_sync_miasma() end
    -- 2026-05-23 v0.7.98-dev DISABLED: dormant + skulls event toggles removed from VMF menu.
    -- Their setting_id prefixes will never fire here because the widgets no longer exist, but
    -- comment them out to make the disable explicit (re-enable alongside data.lua + loc).
    -- elseif type(setting_id) == "string" and setting_id:find("^activate_dormant_") == 1 then
    --     sync_dormant_boons()
    elseif setting_id == "ban_all_grudge_marks"
        or (type(setting_id) == "string" and setting_id:find("^ban_grudge_mark_") == 1) then
        sync_grudge_marks()
    -- elseif setting_id == "enable_skulls_event_boons" then
    --     sync_skulls_event_boons()
    elseif setting_id == "enable_boon_reworks"
        or (type(setting_id) == "string" and setting_id:find("^enable_boon_") == 1) then
        for _, spec in ipairs(mod._ct_meta_trait_boons.trait_boons) do
            mod._ct_meta_trait_boons.register_trait_boon(spec)  -- idempotent; also ejects when either gate is off
        end
    elseif is_pool_setting(setting_id) then
        -- inject_pool() is idempotent: takes a one-time snapshot, resets to it on
        -- every call, then applies current toggle state. Master-off branch inside
        -- skips inject and leaves the pool at vanilla.
        AdventurePool.inject_pool()
    end
end

-- ============================================================
-- VMF UI fix (v0.7.120-dev — Issue #40; #39/#164 numeric-step hook REMOVED)
-- ============================================================
-- One hook on `VMFOptionsView` that drives widget DISPLAY state from inside the open
-- options menu. VMF's native widgets cache their display state (`is_checkbox_checked`)
-- independently of the persisted setting and only re-sync from `mod:get` on view re-open
-- (`update_picked_option_for_settings_list_widgets` runs only in `on_enter`).
--
-- (#164, v0.7.207-dev) The former `callback_draw_numeric_menu` pre-hook that snapped the
-- `starting_coins` slider to multiples of 25 inside VMF's OWN menu (Issue #39) was REMOVED,
-- together with the on_setting_changed snap that rounded the persisted value to 25. Per the
-- binding 2026-07-02 direction, VMF's own options view stays at its natural fine granularity
-- so the user can dial an exact value (e.g. 324); the coarse 25-step now lives ONLY in gut's
-- Mod Tweaker (its STEP_OVERRIDES registry, #164).
--
-- **Mutex checkbox visual sync** (Issue #40): when our `on_setting_changed` mutex enforcer
-- calls `mod:set(sibling, false)` to uncheck a cluster sibling, the underlying setting updates
-- but the open widget's `is_checkbox_checked` stays true — both checkboxes appear checked until
-- the menu is reopened. Fix: post-hook `callback_setting_changed` to call
-- `self:update_picked_option_for_settings_list_widgets()` after any ct setting change; it walks
-- all widgets and re-syncs display state from the persisted store in the same frame. Narrowly
-- gated (`mod_name == "ct_dev"` — the dev clone's registered id) + pcall-wrapped.
-- See memory `reference_vmf_checkbox_cached_display_state.md` for the mechanic.

-- Mutex / dependent-checkbox visual refresh.
-- Post-hook: original runs first (persists value, fires mod.on_setting_changed,
-- which runs the mutex enforcer that may have called mod:set on siblings).
-- After all that, force a widget-display refresh so the open menu reflects the
-- post-enforcement state.
mod:hook("VMFOptionsView", "callback_setting_changed", function(func, self, mod_name, setting_id, old_value, new_value)
    local a, b = func(self, mod_name, setting_id, old_value, new_value)
    pcall(function()
        if mod_name == "ct_dev" and self and self.update_picked_option_for_settings_list_widgets then
            self:update_picked_option_for_settings_list_widgets()
        end
    end)
    return a, b
end)

-- Clean disable: revert the persistent DeusPowerUpTemplates mutations (Khaine's Fury and bomb-boon
-- cooldowns) so toggling the mod off via VMF doesn't leave them in a tweaked state until restart.
-- All other mutations in this mod are scoped (save-and-restore inside hooks).
mod.on_disabled = function()
    -- #358: VMF stops the update ticker while disabled, so hide the two
    -- owner-local Manann presentation states synchronously. The display owner
    -- deliberately retains an unexpired same-unit deadline because the host
    -- gameplay bucket survives disable/re-enable too.
    local cooldown_display = mod._ct_bomb_cooldown_display
    if cooldown_display and type(cooldown_display.hide_manann_displays) == "function" then
        cooldown_display.hide_manann_displays()
    end
    mod._ct_boon_balance.revert_reckless_swings_tweak()
    mod._ct_boon_balance.revert_bomb_cooldown_tweak()
    mod._ct_boon_balance.revert_boon_movespeed_tweak()
    mod._ct_boon_balance.revert_poison_proof_tweak()
    mod._ct_boon_balance.revert_invis_potion_tweak()
    mod._ct_boon_balance.revert_moot_milk_alt_tweak()
    mod._ct_boon_balance.revert_shard_strike_tweak()
    mod._ct_boon_balance.revert_anath_raema_permanent_tweak()
    -- Drop the lazily-built, never-otherwise-invalidated trait-pool caches so a
    -- re-enable rebuilds them from current game data instead of serving a stale
    -- snapshot captured under the previous (possibly different-mod-set) session.
    mod._ct_reset_weapon_trait_generation_caches()
end

-- Debug command registrations are owned by one pure installer (#1159).
-- Keep this boundary after settings lifecycle and before the regression suite.
mod:dofile("scripts/mods/chaos_wastes_tweaker_dev/_ct_command_owner")({
    mod = mod,
    adventure_pool = AdventurePool,
    dump_pickup_system_state = _dump_pickup_system_state,
    effective_setting = effective_setting,
    mod_version = MOD_VERSION,
})


    return {
        sync_bomb_cooldown = sync_bomb_cooldown,
        sync_boon_movespeed = sync_boon_movespeed,
        sync_host_dependent_state = sync_host_dependent_state,
        sync_reckless_swings = sync_reckless_swings,
        sync_ulric_pack_unlimited_range = sync_ulric_pack_unlimited_range,
    }
end
