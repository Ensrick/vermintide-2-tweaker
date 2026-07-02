local mod = get_mod("ct")
local AdventurePool = mod:dofile("scripts/mods/chaos_wastes_tweaker/_adventure_pool")

-- ============================================================
-- Boon categorization tree (single source of truth)
-- ============================================================
-- Drives both the `disable_boons` and `starting_boons` menu trees. Each entry is one
-- top-level category. `items` are setting-id tails (without the disable_boon_/start_boon_
-- prefix). `sub` (optional) lets a category nest one or more sub-categories.
-- Categories render in the order listed; recursive_sort alphabetizes items inside each
-- group at build time.

local BOON_TREE = {
    {
        category_id = "properties",
        items = {
            "attack_speed", "crit_boost", "crit_chance", "curse_resistance", "fatigue_regen",
            "movespeed", "power_vs_armoured", "power_vs_chaos", "power_vs_frenzy",
            "power_vs_large", "power_vs_skaven", "power_vs_unarmoured", "respawn_speed",
            "revive_speed",
            -- Recovered (mechanically Properties, were mis-grouped pre-v0.7.27b):
            "block_cost", "push_block_arc", "stamina",
            "protection_aoe", "protection_chaos", "protection_skaven",
            "boon_deus_coins_greed",
        },
    },
    {
        category_id = "talents",
        items = {
            "talent_1_1", "talent_1_2", "talent_1_3",
            "talent_2_1", "talent_2_2", "talent_2_3",
            "talent_3_1", "talent_3_2", "talent_3_3",
            "talent_4_1", "talent_4_2", "talent_4_3",
            "talent_5_1", "talent_5_2", "talent_5_3",
            "talent_6_1", "talent_6_2", "talent_6_3",
        },
    },
    -- Vermintide Skulls Event boons (boon_skulls_01..08 + 2 set bonuses) are intentionally
    -- omitted: they only roll during the seasonal Skulls of Vermintide event (~October),
    -- and several rely on Daemon Skull pickups that don't drop in normal CW play. Their
    -- setting_ids and localization entries remain for forward compat — if a future version
    -- needs them, just add a category entry back here.
    {
        category_id = "sets",
        items = {
            "boonset_crit_set_bonus", "boonset_drone_part1", "boonset_drone_part2",
            "boonset_drone_part3", "boonset_drone_part4",
        },
    },
    {
        category_id = "orbs",
        items = {
            "focused_accuracy", "health_orbs", "protection_orbs",
            "sharing_is_caring", "static_charge",
        },
    },
    {
        category_id = "bomb_bubbles",
        items = {
            "boon_supportbomb_concentration_01", "boon_supportbomb_crit_01",
            "boon_supportbomb_healing_01", "boon_supportbomb_speed_01",
            "boon_supportbomb_strenght_01",
        },
    },
    {
        category_id = "auras",
        items = {
            "boon_aura_01", "boon_aura_02", "boon_teamaura_01", "boon_teamaura_02",
            "deus_guard_aura_check", "comradery", "wolfpack",
        },
    },
    {
        category_id = "defensive_boons",
        sub = {
            {
                category_id = "health",
                items = {
                    "hand_of_shallya", "power_up_of_shallya", "tenacious",
                    "curative_empowerment", "deus_ammo_pickup_heal", "deus_health_regeneration",
                    "deus_increased_healing_taken", "deus_max_health", "healers_touch",
                    "heal_on_dot_damage_dealt", "health", "invigorating_strike",
                    "natural_bond", "transfer_temp_health_at_full",
                    -- 2026-05-23 v0.7.98-dev DISABLED: ct_kill_heal mod boon removed per user
                    -- request after Chest-of-Trials crash. Re-add this line when re-enabling
                    -- the ct_kill_heal block in chaos_wastes_tweaker.lua (~L5698).
                    -- "ct_kill_heal",  -- v0.7.32 Mod Boon: 1 green HP per kill (exotic)
                },
            },
            {
                category_id = "stamina_and_parry",
                items = {
                    "deus_block_procs_parry", "deus_extra_stamina", "deus_infinite_dodges",
                    "deus_parry_damage_immune", "deus_push_cost_reduction", "skill_by_block",
                    "speed_over_stamina", "static_blade",
                },
            },
            {
                category_id = "damage_reduction",
                items = {
                    "missing_health_power_up", "deus_uninterruptable_attacks",
                    "barkskin", "deus_standing_still_damage_reduction",
                },
            },
            {
                category_id = "save_revive",
                items = {
                    "boon_aura_03", "bad_breath", "blazing_revenge",
                    "deus_damage_reduction_on_incapacitated", "deus_knockdown_damage_immunity_aura",
                    "deus_revive_regen", "deus_second_wind", "hidden_escape",
                    "boulder_bro", "indomitable", "last_player_standing_power_reg", "resolve",
                },
            },
        },
    },
    {
        category_id = "offensive_boons",
        sub = {
            {
                category_id = "crit",
                items = { "lucky", "deus_crit_on_damage_taken", "pent_up_anger" },
            },
            {
                category_id = "attack_speed",
                items = { "attack_speed_per_cooldown", "deus_powerup_attack_speed", "melee_killing_spree_speed" },
            },
            {
                category_id = "ranged",
                items = { "boon_range_01", "boon_range_02", "deus_more_head_less_body_damage" },
            },
            {
                category_id = "damage_and_power",
                items = {
                    "pyrrhic_strength", "deus_reckless_swings", "deus_target_full_health_damage_mult",
                    "thorn_skin", "triple_melee_headshot_power", "staggering_force",
                    "detect_weakness", "surprise_strike", "boon_meta_01",
                },
            },
            {
                category_id = "aoe",
                items = {
                    "melee_wave", "deus_push_increased_cleave", "explosive_kills_on_elite_kills",
                    "boon_dot_burning_01", "deus_push_charge",
                },
            },
        },
    },
    {
        category_id = "utility_boons",
        sub = {
            {
                category_id = "potions",
                items = { "decanter", "home_brewer", "deus_free_potion_use_on_ability" },
            },
            {
                category_id = "bombs",
                items = {
                    "boon_bomb_heavy_01", "cluster_barrel", "deus_barrel_power",
                    "deus_grenade_multi_throw", "explosive_ordinance", "grenadier",
                    "pyrotechnical_echo", "shrapnel",
                },
            },
            {
                category_id = "career_skill",
                items = {
                    "cooldown_on_friendly_ability", "deus_cooldown_reg_not_hit",
                    "deus_cooldown_regen", "deus_skill_on_special_kill",
                    "friendly_cooldown_on_ability", "boon_careerskill_06",
                    "drop_item_on_ability_use", "movement_speed_on_active_ability_use",
                },
                sub = {
                    {
                        category_id = "career_skill_aoe",
                        items = {
                            "boon_careerskill_01", "boon_careerskill_02", "boon_careerskill_03",
                            "boon_careerskill_04", "boon_careerskill_07",
                        },
                    },
                },
            },
            {
                category_id = "coins_and_ammo",
                items = { "money_magnet" },
            },
            {
                category_id = "chest_triggers",
                items = { "boon_aoe_02", "boon_aoe_03" },
            },
            {
                category_id = "gamble_misc",
                items = { "boon_weaponrarity_01", "boon_weaponrarity_02", "deus_power_up_quest_granted_test_01" },
            },
        },
    },
    {
        category_id = "mod_boons",
        items = {
            "ct_meta_stagger",
            "ct_meta_crit",
            "ct_meta_health",
            "ct_meta_cooldown",
            "ct_meta_movespeed",  -- v0.7.35: +1% MS per active boon
            "ct_meta_ammo",       -- v0.7.43: +5% total ammo per active boon (ranged-only effect)
            -- v0.7.34 Trait-as-Boon (gated by Reworks > Reworks: Boons > enable_boon_* toggles)
            "ct_boon_vauls_anvil",
            "ct_boon_manann_tempest",
            "ct_boon_taal_twinned_arrow",
            "ct_boon_asuryan_wrath",
        },
    },
}

-- Dormant boons: defined in vanilla DeusPowerUpTemplates but NOT registered in
-- DeusPowerUpRarityPool, so they never roll in the active CW loot pool. Excluded from
-- the disable tree (you can't disable what can't roll). Appear in the start tree only,
-- with " (Dormant)" appended to the display name.
local DORMANT_BOONS = {
    "deus_ammo_pickup_give_allies_ammo",
    "deus_coin_pickup_regen",
    "deus_large_ammo_pickup_infinite_ammo",
    "deus_larger_clip",
    "deus_throw_speed_increase",
    "deus_timed_block_free_shot",
    "deus_transmute_into_coins",
    "explosive_pushes_on_damage_taken",
    "squats",
}

-- Boons whose localization has no _tooltip entry. Suppress the tooltip key on these so
-- VMF doesn't render `<<missing_key>>` in the tooltip popup.
local NO_TOOLTIP = {
    squats = true,
    deus_power_up_quest_granted_test_01 = true,
}
for i = 1, 6 do
    for j = 1, 3 do
        NO_TOOLTIP["talent_" .. i .. "_" .. j] = true
    end
end

local function build_widget(prefix, boon_id)
    local sid = prefix .. "_" .. boon_id
    local w = { setting_id = sid, type = "checkbox", default_value = false }
    if not NO_TOOLTIP[boon_id] then
        w.tooltip = sid .. "_tooltip"
    end
    return w
end

local function build_category_group(prefix, entry)
    local sub_widgets = {}
    for _, boon_id in ipairs(entry.items or {}) do
        sub_widgets[#sub_widgets + 1] = build_widget(prefix, boon_id)
    end
    if entry.sub then
        for _, sub_entry in ipairs(entry.sub) do
            sub_widgets[#sub_widgets + 1] = build_category_group(prefix, sub_entry)
        end
    end
    return {
        setting_id = prefix .. "_" .. entry.category_id .. "_group",
        type = "group",
        sub_widgets = sub_widgets,
    }
end

local function build_disable_tree()
    local groups = {}
    for _, entry in ipairs(BOON_TREE) do
        groups[#groups + 1] = build_category_group("disable_boon", entry)
    end
    return groups
end

local function build_start_tree()
    local groups = {}
    for _, entry in ipairs(BOON_TREE) do
        groups[#groups + 1] = build_category_group("start_boon", entry)
    end
    -- 2026-05-23 v0.7.98-dev DISABLED: start_boon_dormant_group removed because the dormant
    -- boons themselves are no longer registered (see chaos_wastes_tweaker.lua ~L4448). A
    -- starting boon checkbox for an unregistered boon would silently no-op and mislead users.
    -- Re-enable alongside the dormant injection code.
    --[[
    -- Dormant boons appear in start tree only, in their own group.
    local dormant_widgets = {}
    for _, boon_id in ipairs(DORMANT_BOONS) do
        dormant_widgets[#dormant_widgets + 1] = build_widget("start_boon", boon_id)
    end
    groups[#groups + 1] = {
        setting_id = "start_boon_dormant_group",
        type = "group",
        sub_widgets = dormant_widgets,
    }
    --]]
    return groups
end

-- Computed from BOON_TREE so adding a category doesn't require a parallel SORT_GROUPS
-- update. Groups whose sub_widgets are alphabetized by display name at widget-build time.
local SORT_GROUPS = {}
local function _add_sort_group(prefix, entry)
    SORT_GROUPS[prefix .. "_" .. entry.category_id .. "_group"] = true
    if entry.sub then
        for _, sub_entry in ipairs(entry.sub) do
            _add_sort_group(prefix, sub_entry)
        end
    end
end
for _, entry in ipairs(BOON_TREE) do
    _add_sort_group("disable_boon", entry)
    _add_sort_group("start_boon", entry)
end
-- 2026-05-23 v0.7.98-dev DISABLED: start_boon_dormant_group no longer registered (see
-- build_start_tree above). Sort registration is harmless either way, but commented for clarity.
-- SORT_GROUPS["start_boon_dormant_group"] = true

local function sort_key(widget)
    local sid = widget.setting_id or ""
    local label = mod:localize(sid)
    if not label or label == "<" .. sid .. ">" then
        return sid:lower()
    end
    return label:lower()
end

local function recursive_sort(widgets)
    if type(widgets) ~= "table" then return end
    for _, w in ipairs(widgets) do
        if w.sub_widgets then
            if SORT_GROUPS[w.setting_id] then
                table.sort(w.sub_widgets, function(a, b)
                    return sort_key(a) < sort_key(b)
                end)
            end
            recursive_sort(w.sub_widgets)
        end
    end
end

-- `text` values are localization keys (resolved by VMF via mod:localize). VMF wraps any missing
-- key in `<<>>`, so even numeric labels like "1".."9" need explicit loc entries — see
-- _localization.lua. v0.7.65: value=-1 is the sentinel meaning "leave vanilla random distribution
-- untouched" (was value=0 in 0.7.64 and earlier — see chaos_wastes_tweaker.lua
-- get_deus_weapon_chest_type). value=0 is now a distinct option meaning "literally zero altars of
-- this type" — the user-facing split between "let CW decide" and "force zero" requested
-- 2026-05-19. Existing user settings stored as 0 will surface as "0 altars" after this change
-- rather than "Default" — the change is documented in CHANGELOG so users can re-pick "Default"
-- if that's what they wanted.
local altar_count_options = {
    { text = "altar_count_default", value = -1 },
    { text = "0", value = 0 },
    { text = "1", value = 1 },
    { text = "2", value = 2 },
    { text = "3", value = 3 },
    { text = "4", value = 4 },
    { text = "5", value = 5 },
    { text = "6", value = 6 },
    { text = "7", value = 7 },
    { text = "8", value = 8 },
    { text = "9", value = 9 },
}

-- v0.7.66: Miracle of Isha behavior dropdown. Replaces the v0.7.65 checkbox
-- (boolean) — string values let us add the third "unlimited wounds" variant
-- without restructuring later. Old boolean storage is migrated in the runtime
-- read helper (`_get_isha_mode` in chaos_wastes_tweaker.lua).
local isha_alternative_options = {
    { text = "isha_alt_vanilla", value = "vanilla" },
    { text = "isha_alt_aegis",   value = "aegis"   },
    { text = "isha_alt_wounds",  value = "wounds"  },
}

-- v0.7.65: Chests-of-Trials and arena-ammo dropdown options. Same shape as
-- altar_count_options but with a higher max (10) since vanilla numeric versions
-- allowed up to 10. value=-1 is the "use vanilla count" sentinel matching the
-- altar dropdowns' Default semantics.
local count_with_default_options = {
    { text = "altar_count_default", value = -1 },
    { text = "0", value = 0 },
    { text = "1", value = 1 },
    { text = "2", value = 2 },
    { text = "3", value = 3 },
    { text = "4", value = 4 },
    { text = "5", value = 5 },
    { text = "6", value = 6 },
    { text = "7", value = 7 },
    { text = "8", value = 8 },
    { text = "9", value = 9 },
    { text = "10", value = 10 },
}

local data = {
    name = mod:localize("mod_name"),
    description = mod:localize("mod_description"),
    is_togglable = true,
    options = {
        widgets = {
            {
                setting_id = "pilgrims_coin_group",
                type = "group",
                sub_widgets = {
                    { setting_id = "coin_multiplier", type = "numeric", default_value = 1, range = { 0.1, 5 }, decimals_number = 2 },
                    -- starting_coins snaps to the nearest multiple of 25 via on_setting_changed (chaos_wastes_tweaker.lua).
                    { setting_id = "starting_coins", type = "numeric", default_value = 0, range = { 0, 3000 }, decimals_number = 0 },
                },
            },
            {
                setting_id = "shrines_altars_chests_group",
                type = "group",
                sub_widgets = {
                    { setting_id = "shrine_boon_count", type = "numeric", default_value = 4, range = { 1, 5 }, decimals_number = 0 },
                    { setting_id = "chest_boon_count", type = "numeric", default_value = 3, range = { 1, 5 }, decimals_number = 0 },
                    { setting_id = "chest_upgrade_count", type = "dropdown", default_value = -1, options = altar_count_options, tooltip = "altar_count_tooltip" },
                    { setting_id = "chest_swap_melee_count", type = "dropdown", default_value = -1, options = altar_count_options, tooltip = "altar_count_tooltip" },
                    { setting_id = "chest_swap_ranged_count", type = "dropdown", default_value = -1, options = altar_count_options, tooltip = "altar_count_tooltip" },
                    { setting_id = "chest_power_up_count", type = "dropdown", default_value = -1, options = altar_count_options, tooltip = "altar_count_tooltip" },
                    { setting_id = "cursed_chest_count", type = "dropdown", default_value = -1, options = count_with_default_options, tooltip = "cursed_chest_count_tooltip" },
                    { setting_id = "respawn_on_chest_complete", type = "checkbox", default_value = false, tooltip = "respawn_on_chest_complete_tooltip" },
                },
            },
            {
                setting_id = "adventure_maps_group",
                type = "group",
                sub_widgets = {
                    { setting_id = "inject_adventure_maps", type = "checkbox", default_value = false, tooltip = "inject_adventure_maps_tooltip" },
                    { setting_id = "replace_shrines_with_missions", type = "checkbox", default_value = false, tooltip = "replace_shrines_with_missions_tooltip" },
                    {
                        setting_id = "available_missions_group",
                        type = "group",
                        sub_widgets = {
                            {
                                setting_id = "cw_scenarios_group",
                                type = "group",
                                sub_widgets = AdventurePool.build_cw_scenario_widgets(),
                            },
                            {
                                setting_id = "campaign_scenarios_group",
                                type = "group",
                                sub_widgets = AdventurePool.build_campaign_dlc_group_widgets(),
                            },
                            {
                                setting_id = "event_missions_group",
                                type = "group",
                                sub_widgets = AdventurePool.build_event_mission_widgets(),
                            },
                        },
                    },
                },
            },
            {
                setting_id = "curses_group",
                type = "group",
                sub_widgets = {
                    { setting_id = "force_belakor", type = "checkbox", default_value = false },
                    { setting_id = "disable_dominant_god", type = "checkbox", default_value = true, tooltip = "disable_dominant_god_tooltip" },
                    { setting_id = "finale_dominant_god", type = "numeric", default_value = 0, range = { 0, 4 }, decimals_number = 0 },
                    { setting_id = "cursed_mission_count", type = "numeric", default_value = 0, range = { 0, 30 }, decimals_number = 0, tooltip = "cursed_mission_count_tooltip" },
                    {
                        setting_id = "disabled_curses_group",
                        type = "group",
                        sub_widgets = {
                            { setting_id = "disable_curse_abundance_of_life", type = "checkbox", default_value = false },
                            { setting_id = "disable_curse_belakor_totems", type = "checkbox", default_value = false },
                            { setting_id = "disable_curse_blood_storm", type = "checkbox", default_value = false },
                            { setting_id = "disable_curse_bolt_of_change", type = "checkbox", default_value = false },
                            { setting_id = "disable_curse_change_of_tzeentch", type = "checkbox", default_value = false },
                            { setting_id = "disable_curse_corrupted_flesh", type = "checkbox", default_value = false },
                            { setting_id = "disable_curse_egg_of_tzeentch", type = "checkbox", default_value = false },
                            { setting_id = "disable_curse_empathy", type = "checkbox", default_value = false },
                            { setting_id = "disable_curse_greed_pinata", type = "checkbox", default_value = false },
                            { setting_id = "disable_curse_khorne_champions", type = "checkbox", default_value = false },
                            { setting_id = "disable_curse_rotten_miasma", type = "checkbox", default_value = false },
                            { setting_id = "disable_curse_shadow_homing_skulls", type = "checkbox", default_value = false },
                            { setting_id = "disable_curse_skulking_sorcerer", type = "checkbox", default_value = false },
                            { setting_id = "disable_curse_skulls_of_fury", type = "checkbox", default_value = false },
                        },
                    },
                    {
                        setting_id = "boss_grudge_marks_group",
                        type = "group",
                        sub_widgets = {
                            { setting_id = "ban_grudge_mark_commander",       type = "checkbox", default_value = false, tooltip = "ban_grudge_mark_commander_tooltip" },
                            { setting_id = "ban_grudge_mark_crippling",       type = "checkbox", default_value = false, tooltip = "ban_grudge_mark_crippling_tooltip" },
                            { setting_id = "ban_grudge_mark_crushing",        type = "checkbox", default_value = false, tooltip = "ban_grudge_mark_crushing_tooltip" },
                            { setting_id = "ban_grudge_mark_frenzy",          type = "checkbox", default_value = false, tooltip = "ban_grudge_mark_frenzy_tooltip" },
                            { setting_id = "ban_grudge_mark_intangible",      type = "checkbox", default_value = false, tooltip = "ban_grudge_mark_intangible_tooltip" },
                            { setting_id = "ban_grudge_mark_periodic_curse",  type = "checkbox", default_value = false, tooltip = "ban_grudge_mark_periodic_curse_tooltip" },
                            { setting_id = "ban_grudge_mark_periodic_shield", type = "checkbox", default_value = false, tooltip = "ban_grudge_mark_periodic_shield_tooltip" },
                            { setting_id = "ban_grudge_mark_raging",          type = "checkbox", default_value = false, tooltip = "ban_grudge_mark_raging_tooltip" },
                            { setting_id = "ban_grudge_mark_ranged_immune",   type = "checkbox", default_value = false, tooltip = "ban_grudge_mark_ranged_immune_tooltip" },
                            { setting_id = "ban_grudge_mark_regenerating",    type = "checkbox", default_value = false, tooltip = "ban_grudge_mark_regenerating_tooltip" },
                            { setting_id = "ban_grudge_mark_unstaggerable",   type = "checkbox", default_value = false, tooltip = "ban_grudge_mark_unstaggerable_tooltip" },
                            { setting_id = "ban_grudge_mark_vampiric",        type = "checkbox", default_value = false, tooltip = "ban_grudge_mark_vampiric_tooltip" },
                            { setting_id = "ban_grudge_mark_warping",         type = "checkbox", default_value = false, tooltip = "ban_grudge_mark_warping_tooltip" },
                        },
                    },
                },
            },
            {
                setting_id = "reworks_group",
                type = "group",
                sub_widgets = {
                    { setting_id = "arena_ammo_count", type = "dropdown", default_value = -1, options = count_with_default_options, tooltip = "arena_ammo_count_tooltip" },
                    { setting_id = "any_trait_any_weapon", type = "checkbox", default_value = false, tooltip = "any_trait_any_weapon_tooltip" },
                    { setting_id = "tweak_trait_tier_by_rarity", type = "checkbox", default_value = false, tooltip = "tweak_trait_tier_by_rarity_tooltip" },
                    { setting_id = "tweak_shard_strike_duration", type = "numeric", default_value = 16, range = { 1, 16 }, decimals_number = 0, tooltip = "tweak_shard_strike_duration_tooltip" },
                    {
                        setting_id = "reworks_boons_group",
                        type = "group",
                        sub_widgets = {
                            { setting_id = "tweak_reckless_swings", type = "checkbox", default_value = false, tooltip = "tweak_reckless_swings_tooltip" },
                            { setting_id = "tweak_boon_movespeed", type = "checkbox", default_value = false, tooltip = "tweak_boon_movespeed_tooltip" },
                            { setting_id = "bomb_boon_cooldown", type = "numeric", default_value = 0, range = { 0, 600 }, decimals_number = 0, tooltip = "bomb_boon_cooldown_tooltip" },
                            { setting_id = "bomb_boon_exclusive", type = "checkbox", default_value = false, tooltip = "bomb_boon_exclusive_tooltip" },
                            { setting_id = "endless_bombs_consumes_morgrim", type = "checkbox", default_value = false, tooltip = "endless_bombs_consumes_morgrim_tooltip" },
                            { setting_id = "rv_no_save_morgrim", type = "checkbox", default_value = false, tooltip = "rv_no_save_morgrim_tooltip" },
                            { setting_id = "enable_boon_vauls_anvil",         type = "checkbox", default_value = false, tooltip = "enable_boon_vauls_anvil_tooltip" },
                            { setting_id = "enable_boon_manann_tempest",      type = "checkbox", default_value = false, tooltip = "enable_boon_manann_tempest_tooltip" },
                            { setting_id = "tweak_manann_tempest_cooldown",   type = "checkbox", default_value = false, tooltip = "tweak_manann_tempest_cooldown_tooltip" },
                            { setting_id = "enable_boon_taal_twinned_arrow",  type = "checkbox", default_value = false, tooltip = "enable_boon_taal_twinned_arrow_tooltip" },
                            { setting_id = "enable_boon_asuryan_wrath",       type = "checkbox", default_value = false, tooltip = "enable_boon_asuryan_wrath_tooltip" },
                            { setting_id = "tweak_anath_raema_permanent",     type = "checkbox", default_value = false, tooltip = "tweak_anath_raema_permanent_tooltip" },
                            { setting_id = "tweak_defeat_recovery",           type = "checkbox", default_value = false, tooltip = "tweak_defeat_recovery_tooltip" },
                            { setting_id = "tweak_miracle_of_ulric_persistent", type = "checkbox", default_value = false, tooltip = "tweak_miracle_of_ulric_persistent_tooltip" },
                            { setting_id = "ulric_pack_unlimited_range", type = "checkbox", default_value = false, tooltip = "ulric_pack_unlimited_range_tooltip" },
                            { setting_id = "tweak_wildfire_generations_cap", type = "numeric", default_value = 3, range = { 1, 10 }, decimals_number = 0, tooltip = "tweak_wildfire_generations_cap_tooltip" },
                            -- Miracle of Isha — mutex cluster `isha_choice`.
                            -- v0.7.81: replaced the legacy `tweak_miracle_of_isha_alternative`
                            -- dropdown with these two checkboxes per LOCALIZATION_STANDARD.md § 10.
                            -- Both unchecked = vanilla revive-once behavior. Toggling one auto-
                            -- unchecks the other (enforced in on_setting_changed via
                            -- chaos_wastes_tweaker_mutex). Labels use the "    (A) / (B)" prefix
                            -- convention with 4-space leading indent so the multiple-choice
                            -- relationship reads visually in the VMF UI.
                            { setting_id = "tweak_miracle_of_isha_aegis",  type = "checkbox", default_value = false, tooltip = "tweak_miracle_of_isha_aegis_tooltip" },
                            { setting_id = "tweak_miracle_of_isha_wounds", type = "checkbox", default_value = false, tooltip = "tweak_miracle_of_isha_wounds_tooltip" },
                            { setting_id = "bots_mirror_host_boons", type = "checkbox", default_value = false, tooltip = "bots_mirror_host_boons_tooltip" },
                            -- v0.7.120-dev: mutex alternative to mirror. Bots roll INDEPENDENT random boons each
                            -- time the host claims one. Mutex group "bots_boon_mode" — declared in chaos_wastes_tweaker.lua.
                            { setting_id = "bots_get_random_boons",            type = "checkbox", default_value = false, tooltip = "bots_get_random_boons_tooltip" },
                            -- v0.7.120-dev: mirror host weapon-chest interactions onto every bot. Swap chests
                            -- generate a random weapon for the bot's career; upgrade chests upgrade the bot's
                            -- currently-equipped CW weapon to the same target rarity.
                            { setting_id = "bots_mirror_host_weapon_upgrades", type = "checkbox", default_value = false, tooltip = "bots_mirror_host_weapon_upgrades_tooltip" },
                            -- Host-only chat readout: prints which boon each bot receives while
                            -- mirror/random bot boons are on, so the host can see what bots got.
                            { setting_id = "announce_bot_boons",               type = "checkbox", default_value = false, tooltip = "announce_bot_boons_tooltip" },
                        },
                    },
                    {
                        setting_id = "reworks_potions_group",
                        type = "group",
                        sub_widgets = {
                            { setting_id = "tweak_poison_proof_duration", type = "checkbox", default_value = false, tooltip = "tweak_poison_proof_duration_tooltip" },
                            { setting_id = "tweak_moot_milk_alt", type = "checkbox", default_value = false, tooltip = "tweak_moot_milk_alt_tooltip" },
                            { setting_id = "tweak_home_brewer_potency", type = "checkbox", default_value = false, tooltip = "tweak_home_brewer_potency_tooltip" },
                            { setting_id = "tweak_invis_potion_2x", type = "checkbox", default_value = false, tooltip = "tweak_invis_potion_2x_tooltip" },
                            { setting_id = "enable_campaign_potions", type = "checkbox", default_value = false },
                        },
                    },
                },
            },
                {
                    setting_id = "disabled_boons_group",
                    type = "group",
                    sub_widgets = build_disable_tree(),
                },
                {
                    setting_id = "starting_boons_group",
                    type = "group",
                    sub_widgets = build_start_tree(),
                },
                -- 2026-05-23 v0.7.98-dev DISABLED: Activate Dormant Boons + Skulls Event Boons
                -- VMF groups removed per user request after Chest-of-Trials crash. The
                -- corresponding lua implementation is block-commented in
                -- `chaos_wastes_tweaker.lua` (~L4448 dormants, ~L4724 Skulls). The
                -- "start_boon_dormant_group" widget (above, in build_start_tree) is also
                -- effectively unused now — those dormants will not register, so picking a
                -- starting boon from that list would fail to apply. Keeping the start-tree
                -- widget visible would mislead users; consider commenting build_start_tree's
                -- dormant_widgets too if dormant disable becomes permanent.
                -- To re-enable: uncomment the block below AND uncomment the matching loc keys
                -- (activate_dormant_*, enable_skulls_event_boons, skulls_event_boons_group) AND
                -- uncomment the apply-site calls in chaos_wastes_tweaker.lua.
                --[[
                {
                    setting_id = "activate_dormant_boons_group",
                    type = "group",
                    sub_widgets = (function()
                        local widgets = {}
                        for _, boon_id in ipairs(DORMANT_BOONS) do
                            local sid = "activate_dormant_" .. boon_id
                            widgets[#widgets + 1] = {
                                setting_id = sid,
                                type = "checkbox",
                                default_value = false,
                                tooltip = sid .. "_tooltip",
                            }
                        end
                        return widgets
                    end)(),
                },
                {
                    setting_id = "skulls_event_boons_group",
                    type = "group",
                    sub_widgets = {
                        {
                            setting_id = "enable_skulls_event_boons",
                            type = "checkbox",
                            default_value = false,
                            tooltip = "enable_skulls_event_boons_tooltip",
                        },
                    },
                },
                --]]
            {
                setting_id = "banned_traits_group",
                type = "group",
                sub_widgets = {
                    {
                        setting_id = "ban_trait_vanilla_group",
                        type = "group",
                        sub_widgets = {
                            { setting_id = "ban_trait_melee_attack_speed_on_crit",                 type = "checkbox", default_value = false, tooltip = "ban_trait_melee_attack_speed_on_crit_tooltip" },
                            { setting_id = "ban_trait_melee_counter_push_power",                   type = "checkbox", default_value = false, tooltip = "ban_trait_melee_counter_push_power_tooltip" },
                            { setting_id = "ban_trait_melee_heal_on_crit",                         type = "checkbox", default_value = false, tooltip = "ban_trait_melee_heal_on_crit_tooltip" },
                            { setting_id = "ban_trait_melee_increase_damage_on_block",             type = "checkbox", default_value = false, tooltip = "ban_trait_melee_increase_damage_on_block_tooltip" },
                            { setting_id = "ban_trait_melee_reduce_cooldown_on_crit",              type = "checkbox", default_value = false, tooltip = "ban_trait_melee_reduce_cooldown_on_crit_tooltip" },
                            { setting_id = "ban_trait_melee_shield_on_assist",                     type = "checkbox", default_value = false, tooltip = "ban_trait_melee_shield_on_assist_tooltip" },
                            { setting_id = "ban_trait_melee_timed_block_cost",                     type = "checkbox", default_value = false, tooltip = "ban_trait_melee_timed_block_cost_tooltip" },
                            { setting_id = "ban_trait_ranged_consecutive_hits_increase_power",     type = "checkbox", default_value = false, tooltip = "ban_trait_ranged_consecutive_hits_increase_power_tooltip" },
                            { setting_id = "ban_trait_ranged_increase_power_level_vs_armour_crit", type = "checkbox", default_value = false, tooltip = "ban_trait_ranged_increase_power_level_vs_armour_crit_tooltip" },
                            { setting_id = "ban_trait_ranged_reduce_cooldown_on_crit",             type = "checkbox", default_value = false, tooltip = "ban_trait_ranged_reduce_cooldown_on_crit_tooltip" },
                            { setting_id = "ban_trait_ranged_reduced_overcharge",                  type = "checkbox", default_value = false, tooltip = "ban_trait_ranged_reduced_overcharge_tooltip" },
                            { setting_id = "ban_trait_ranged_remove_overcharge_on_crit",           type = "checkbox", default_value = false, tooltip = "ban_trait_ranged_remove_overcharge_on_crit_tooltip" },
                            { setting_id = "ban_trait_ranged_replenish_ammo_headshot",             type = "checkbox", default_value = false, tooltip = "ban_trait_ranged_replenish_ammo_headshot_tooltip" },
                            { setting_id = "ban_trait_ranged_replenish_ammo_on_crit",              type = "checkbox", default_value = false, tooltip = "ban_trait_ranged_replenish_ammo_on_crit_tooltip" },
                            { setting_id = "ban_trait_ranged_restore_stamina_headshot",            type = "checkbox", default_value = false, tooltip = "ban_trait_ranged_restore_stamina_headshot_tooltip" },
                        },
                    },
                    {
                        setting_id = "ban_trait_chaos_wastes_group",
                        type = "group",
                        sub_widgets = {
                            { setting_id = "ban_trait_always_blocking",                            type = "checkbox", default_value = false, tooltip = "ban_trait_always_blocking_tooltip" },
                            { setting_id = "ban_trait_armor_breaker",                              type = "checkbox", default_value = false, tooltip = "ban_trait_armor_breaker_tooltip" },
                            { setting_id = "ban_trait_bloodthirst",                                type = "checkbox", default_value = false, tooltip = "ban_trait_bloodthirst_tooltip" },
                            { setting_id = "ban_trait_crescendo_strike",                           type = "checkbox", default_value = false, tooltip = "ban_trait_crescendo_strike_tooltip" },
                            { setting_id = "ban_trait_deus_ammo_pickup_reload_speed",              type = "checkbox", default_value = false, tooltip = "ban_trait_deus_ammo_pickup_reload_speed_tooltip" },
                            { setting_id = "ban_trait_deus_big_swing_stagger",                     type = "checkbox", default_value = false, tooltip = "ban_trait_deus_big_swing_stagger_tooltip" },
                            { setting_id = "ban_trait_deus_collateral_damage_on_melee_killing_blow", type = "checkbox", default_value = false, tooltip = "ban_trait_deus_collateral_damage_on_melee_killing_blow_tooltip" },
                            { setting_id = "ban_trait_deus_crit_chain_lightning",                  type = "checkbox", default_value = false, tooltip = "ban_trait_deus_crit_chain_lightning_tooltip" },
                            { setting_id = "ban_trait_deus_extra_shot",                            type = "checkbox", default_value = false, tooltip = "ban_trait_deus_extra_shot_tooltip" },
                            { setting_id = "ban_trait_deus_ranged_crit_explosion",                 type = "checkbox", default_value = false, tooltip = "ban_trait_deus_ranged_crit_explosion_tooltip" },
                            { setting_id = "ban_trait_follow_up",                                  type = "checkbox", default_value = false, tooltip = "ban_trait_follow_up_tooltip" },
                            { setting_id = "ban_trait_headhunter",                                 type = "checkbox", default_value = false, tooltip = "ban_trait_headhunter_tooltip" },
                            { setting_id = "ban_trait_home_run",                                   type = "checkbox", default_value = false, tooltip = "ban_trait_home_run_tooltip" },
                            { setting_id = "ban_trait_piercing_projectiles",                       type = "checkbox", default_value = false, tooltip = "ban_trait_piercing_projectiles_tooltip" },
                            { setting_id = "ban_trait_refilling_shot",                             type = "checkbox", default_value = false, tooltip = "ban_trait_refilling_shot_tooltip" },
                            { setting_id = "ban_trait_serrated_blade",                             type = "checkbox", default_value = false, tooltip = "ban_trait_serrated_blade_tooltip" },
                            { setting_id = "ban_trait_shield_of_isha",                             type = "checkbox", default_value = false, tooltip = "ban_trait_shield_of_isha_tooltip" },
                            { setting_id = "ban_trait_shield_splinters",                           type = "checkbox", default_value = false, tooltip = "ban_trait_shield_splinters_tooltip" },
                            { setting_id = "ban_trait_stagger_aoe_on_crit",                        type = "checkbox", default_value = false, tooltip = "ban_trait_stagger_aoe_on_crit_tooltip" },
                        },
                    },
                },
            },
        },
    },
}

recursive_sort(data.options.widgets)

return data
