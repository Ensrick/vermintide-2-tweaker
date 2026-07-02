local mod = get_mod("enemy_tweaker")

-- ============================================================================
-- Boss Mechanic Tweaks (received from general_tweaker_dev 2026-06-20)
-- ============================================================================
-- Load-time data mutations that change how a boss attack behaves (not a
-- difficulty level). Source citations into the decompiled vanilla source at
-- C:\Users\danjo\source\repos\Vermintide-2-Source-Code.

-- ----------------------------------------------------------------------------
-- Halescourge / Nurgloth fly disable ("cloud of flies") duration
-- ----------------------------------------------------------------------------
-- Both Burblespue Halescourge (breed `chaos_exalted_sorcerer`) and Nurgloth the
-- Eternal (breed `chaos_exalted_sorcerer_drachenfels`) can lock a player in the
-- overpowered "to_cloud_of_flies" disable (player_character_state_overpowered.lua:22).
-- It is produced by TWO different code paths, with two different vanilla
-- durations -- so one multiplier (default 1.0 = vanilla) scales both:
--
--   1. NURGLOTH melee fly-swarm (BT action `swarm_players`):
--      BreedActions.chaos_exalted_sorcerer_drachenfels.swarm_players.duration = 8
--      (breed_chaos_exalted_sorcerer_drachenfels.lua:2018). bt_swarm_action.lua:73
--      spawns the overpowering blob with action.duration as its life_time.
--
--   2. SEEKING INSECT-SWARM BOMB missile (the "rare" ranged fly attack -- BOTH
--      bosses). Attack `seeking_bomb_missile` fires projectile
--      `insect_swarm_missile_01`; on hit the explosion
--      chaos_slow_bomb_missile (Halescourge; ai_breed_snippets.lua:1091/1093) or
--      chaos_slow_bomb_missile_new ("fly_bomb"; Nurgloth/Drachenfels;
--      penny_ai_breed_snippets.lua:178) spawns the same fly-blob with
--      duration = TrueFlightTemplates.sorcerer_slow_bomb_missile.attached_life_time = 10
--      (true_flight_templates.lua:121; explosion_templates.lua:1325/1355).
--
-- Both blobs carry health 5, so the disable can still be ended early by killing
-- the fly cloud -- this only scales the maximum length. We mutate the data
-- fields at load (and on setting change); the spawn paths read them live, so no
-- per-cast hook is needed (and no mod:hook is registered here -- pure data
-- mutation, so no duplicate-hook concern with enemy_tweaker's existing hooks).

local SWARM_VANILLA_DURATION = 8   -- Nurgloth melee swarm (BT action)
local MISSILE_VANILLA_LIFE   = 10  -- seeking insect-swarm bomb (both bosses)

local function _et_apply_fly_disable()
    local mult = mod:get("et_fly_disable_mult")
    if type(mult) ~= "number" then
        mult = 1.0
    end

    -- 1. Nurgloth melee fly-swarm BT action duration.
    local breed_actions = rawget(_G, "BreedActions")
    local actions = breed_actions and breed_actions.chaos_exalted_sorcerer_drachenfels
    local swarm = actions and actions.swarm_players
    if swarm then
        swarm._et_vanilla_duration = swarm._et_vanilla_duration or swarm.duration or SWARM_VANILLA_DURATION
        swarm.duration = swarm._et_vanilla_duration * mult
    end

    -- 2. Seeking insect-swarm bomb missile life_time (Halescourge + Nurgloth).
    local tft = rawget(_G, "TrueFlightTemplates")
    local missile = tft and tft.sorcerer_slow_bomb_missile
    if missile then
        missile._et_vanilla_life = missile._et_vanilla_life or missile.attached_life_time or MISSILE_VANILLA_LIFE
        missile.attached_life_time = missile._et_vanilla_life * mult
    end

    mod:debug("[et:boss] fly-disable mult=%.2f -> Nurgloth swarm=%.1fs, seeking-bomb missile=%.1fs",
        mult,
        (swarm and swarm.duration) or -1,
        (missile and missile.attached_life_time) or -1)

    return (swarm ~= nil) or (missile ~= nil)
end

-- Expose so enemy_tweaker.lua's on_setting_changed chain can re-apply on a
-- mid-session slider edit (the data fields are read live by the spawn paths).
mod._et_apply_fly_disable = _et_apply_fly_disable

-- Apply now -- BreedActions / TrueFlightTemplates are boot-time globals.
_et_apply_fly_disable()
