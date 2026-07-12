-- _wt_trait_pools.lua -- Chaos Wastes weapon-trait pool filtering.
--
-- Owns the WeaponTraits.combinations[pool] rewrite machinery split out of the
-- god file in the v0.12.209-dev Phase 1 OOP decomposition: _trait_pool_sources,
-- the vanilla-pool snapshot, apply_trait_filters, and revert_trait_pools. The
-- apply path is currently a no-op stub (the "Weapon Traits (Adventure)" menu was
-- retired 2026-06-29) but the exports + call sites are kept so nothing dangles.
-- No behavior change from the pre-split god file -- the entry aliases
-- `local apply_trait_filters = mod._wt.apply_trait_filters` (and revert) so the
-- lifecycle-callback call sites are byte-identical.
--
-- Owned by: weapon_tweaker.lua entry point. Consumed via: mod:dofile.
-- Shared state: reads engine globals WeaponTraits only; exports
-- mod._wt.apply_trait_filters / .revert_trait_pools, and retains the legacy
-- belt-and-suspenders mod._apply_trait_filters / mod._revert_trait_pools flat
-- exports (no external readers, kept so nothing dangles).

local mod = get_mod("wt")
local WT = mod._wt

--[[
WEAPON-TRAIT POOL FILTERING
---------------------------
Lets the user enable/disable individual weapon traits from the VMF settings.
Adventure traits default ON (vanilla behaviour); Chaos Wastes traits default
OFF and only show in the UI when the `crafting_in_modded` mod is installed.

Mechanism: rewrite `WeaponTraits.combinations[pool]` (the table that
`crafting_in_modded` reads when rolling a trait on a crafted/rerolled weapon).
Every CW trait already lives in `WeaponTraits.traits` and `BuffTemplates`
because `weapon_traits_morris.lua` merges them in at load — they only fail to
appear in adventure because the vanilla `combinations.melee` / `.ranged_*`
pools don't list them. Adding them to those pools is sufficient.

`crafting_in_modded` does NOT hardcode any trait keys; it picks from
`WeaponTraits.combinations[master.trait_table_name]` at runtime
(see standard_forge.lua _reroll_traits + _make_craft_synth). So mutating
those tables here propagates to cim's reroll/craft UI automatically.

NOTE on load order (v0.12.209-dev OOP split — was inline in weapon_tweaker.lua):
dofile'd from the entry manifest BEFORE the lifecycle callbacks
(`on_game_state_changed`, `on_setting_changed`, `on_disabled`) are defined, so
their file-local aliases (`apply_trait_filters` / `revert_trait_pools` =
mod._wt.*) are in scope when those callbacks resolve them at call time.
]]

-- Trait-key membership per pool. The toggle for a trait controls every pool
-- it can appear in. CW-cross-pool traits (headhunter, stagger_aoe_on_crit,
-- shield_splinters, deus_crit_chain_lightning) are listed once per pool they
-- belong to so the rebuilder can pick them up; the user-facing widget is a
-- single checkbox under whichever group is most natural.
local _trait_pool_sources = {
    melee = {
        vanilla = {
            "melee_attack_speed_on_crit",
            "melee_timed_block_cost",
            "melee_counter_push_power",
            "melee_increase_damage_on_block",
            "melee_reduce_cooldown_on_crit",
            "melee_shield_on_assist",
        },
        cw = {
            "stagger_aoe_on_crit",
            "armor_breaker",
            "shield_of_isha",
            "bloodthirst",
            "headhunter",
            "home_run",
            "shield_splinters",
            "serrated_blade",
            "crescendo_strike",
            "follow_up",
            "always_blocking",
            "deus_big_swing_stagger",
            "deus_crit_chain_lightning",
            "deus_collateral_damage_on_melee_killing_blow",
            "melee_heal_on_crit",
        },
    },
    ranged_ammo = {
        vanilla = {
            "ranged_restore_stamina_headshot",
            "ranged_replenish_ammo_headshot",
            "ranged_reduce_cooldown_on_crit",
            "ranged_replenish_ammo_on_crit",
            "ranged_increase_power_level_vs_armour_crit",
            "ranged_consecutive_hits_increase_power",
        },
        cw = {
            "headhunter",
            "stagger_aoe_on_crit",
            "shield_splinters",
            "refilling_shot",
            "piercing_projectiles",
            "deus_extra_shot",
            "deus_crit_chain_lightning",
            "deus_ranged_crit_explosion",
            "deus_ammo_pickup_reload_speed",
        },
    },
    ranged_heat = {
        vanilla = {
            "ranged_restore_stamina_headshot",
            "ranged_reduced_overcharge",
            "ranged_reduce_cooldown_on_crit",
            "ranged_remove_overcharge_on_crit",
            "ranged_increase_power_level_vs_armour_crit",
            "ranged_consecutive_hits_increase_power",
        },
        cw = {
            "headhunter",
            "stagger_aoe_on_crit",
            "shield_splinters",
            "piercing_projectiles",
            "deus_extra_shot",
            "deus_crit_chain_lightning",
            "deus_ranged_crit_explosion",
        },
    },
    trollhammer_torpedo = {
        vanilla = {
            "ranged_restore_stamina_headshot",
            "ranged_reduce_cooldown_on_crit",
            "ranged_increase_power_level_vs_armour_crit",
            "ranged_consecutive_hits_increase_power",
            "melee_timed_block_cost",
            "melee_increase_damage_on_block",
        },
        cw = {
            "headhunter",
            "stagger_aoe_on_crit",
            "shield_splinters",
            "refilling_shot",
            "piercing_projectiles",
            "deus_extra_shot",
            "deus_crit_chain_lightning",
            "deus_ranged_crit_explosion",
            "deus_ammo_pickup_reload_speed",
        },
    },
}

-- Snapshot of vanilla pools. Captured the first time apply_trait_filters runs
-- (so DLC/morris additions are already merged in). Used to revert on
-- on_disabled and to detect "no managed pool yet" cases.
local _initial_trait_pools = nil

local function _snapshot_trait_pools()
    if _initial_trait_pools then return end
    if not WeaponTraits or not WeaponTraits.combinations then return end
    _initial_trait_pools = {}
    for pool_key, _ in pairs(_trait_pool_sources) do
        local existing = WeaponTraits.combinations[pool_key]
        if existing then
            local copy = {}
            for i, entry in ipairs(existing) do
                copy[i] = { entry[1] }
            end
            _initial_trait_pools[pool_key] = copy
        end
    end
end

local function _trait_enabled(trait_key, is_cw)
    local prefix = is_cw and "cw_trait_" or "trait_"
    return mod:get(prefix .. trait_key) == true
end

local function apply_trait_filters()
    -- RETIRED 2026-06-29 (user request): the "Weapon Traits (Adventure)" menu was
    -- removed, so there are no toggles to honor — leave the vanilla trait roll pools
    -- untouched. Kept as a no-op stub (+ the mod._apply_trait_filters / _revert exports
    -- and call sites) so nothing dangles; the dead _trait_pool_sources / snapshot
    -- helpers below can be deleted in a later cleanup pass.
    if true then return end
    if not WeaponTraits or not WeaponTraits.combinations then return end
    _snapshot_trait_pools()
    if not _initial_trait_pools then return end

    for pool_key, sources in pairs(_trait_pool_sources) do
        local current = WeaponTraits.combinations[pool_key]
        if current then
            local seen = {}
            local rebuilt = {}
            local function _push(trait_key, is_cw)
                if seen[trait_key] then return end
                if not _trait_enabled(trait_key, is_cw) then return end
                if not WeaponTraits.traits[trait_key] then return end
                seen[trait_key] = true
                rebuilt[#rebuilt + 1] = { trait_key }
            end
            for _, t in ipairs(sources.vanilla) do _push(t, false) end
            for _, t in ipairs(sources.cw) do _push(t, true) end

            -- Empty pool → fall back to vanilla snapshot to avoid "no traits
            -- to roll" stalls in cim. Users who want zero traits can disable
            -- the mod outright.
            if #rebuilt == 0 and _initial_trait_pools[pool_key] then
                for i, entry in ipairs(_initial_trait_pools[pool_key]) do
                    rebuilt[i] = { entry[1] }
                end
            end

            -- Mutate in place so any code holding a reference to the pool
            -- table sees the new contents.
            for i = #current, 1, -1 do current[i] = nil end
            for i, entry in ipairs(rebuilt) do current[i] = entry end
        end
    end
end

local function revert_trait_pools()
    if not _initial_trait_pools then return end
    if not WeaponTraits or not WeaponTraits.combinations then return end
    for pool_key, snapshot in pairs(_initial_trait_pools) do
        local current = WeaponTraits.combinations[pool_key]
        if current then
            for i = #current, 1, -1 do current[i] = nil end
            for i, entry in ipairs(snapshot) do current[i] = { entry[1] } end
        end
    end
end

mod._apply_trait_filters = apply_trait_filters
mod._revert_trait_pools = revert_trait_pools

WT.apply_trait_filters = apply_trait_filters
WT.revert_trait_pools  = revert_trait_pools
