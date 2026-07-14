local mod = get_mod("ct_dev")
local AdventurePool = mod:dofile("scripts/mods/chaos_wastes_tweaker_dev/_adventure_pool")
local DevMission = mod:dofile("scripts/mods/chaos_wastes_tweaker_dev/_ct_dev_mission_catalog")

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
    -- v0.7.159-dev Task 1: `bomb_bubbles` (the support-bomb boon set) MOVED to be a
    -- sub-category of `utility_boons` (see below), nested alongside `bombs`. It is no
    -- longer a top-level category. category_id + item setting-id tails are unchanged,
    -- so disable_boon_* / start_boon_* user values persist; only the menu position
    -- moves (group setting_id `*_bomb_bubbles_group` is identical either way).
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
                -- #464 follow-up: ct_boon_anath_raema_swiftness is ct's trait-as-boon for
                -- Anath Raema's Swiftness (trait deus_ammo_pickup_reload_speed - a RANGED
                -- weapon trait, deus_ranged_ammo pool, weapon_traits_morris.lua:853; it has
                -- NO vanilla power-up form, which is why it was absent from these menus).
                -- Listed HERE rather than in mod_boons: the user looks for it by function,
                -- beside vanilla boon_range_01 "Anath Raema's Cruel Volley". The four older
                -- ct_boon_* trait-boons stay in mod_boons (their shipped menu positions).
                items = { "boon_range_01", "boon_range_02", "deus_more_head_less_body_damage",
                    "ct_boon_anath_raema_swiftness" },
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
            -- v0.7.159-dev Task 1: support-bomb boon set, nested under utility >
            -- bomb bubbles (was a top-level category). Same category_id + items.
            {
                category_id = "bomb_bubbles",
                items = {
                    "boon_supportbomb_concentration_01", "boon_supportbomb_crit_01",
                    "boon_supportbomb_healing_01", "boon_supportbomb_speed_01",
                    "boon_supportbomb_strenght_01",
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
            -- #406: Khaine's Communion is authored by CT as
            -- DeusPowerUpTemplates.ct_kill_heal. Keep its one catalog row with
            -- the other mod-authored boons, not in the vanilla Health family.
            -- build_disable_tree/build_start_tree derive both menu surfaces from
            -- this row, including Single Mission Loader's Starting Boons flow.
            "ct_kill_heal",  -- 0.25 permanent green HP per kill (exotic)
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

-- Menu-layout rule (user, standing): collapsible sub-menus (`type == "group"`)
-- always render ABOVE loose options within the same parent. Enforced by a STABLE
-- partition — groups keep their relative order, loose options keep theirs; only the
-- group-vs-option split is normalized. Runs on every widget list (independent of
-- SORT_GROUPS alphabetization, which orders items WITHIN a sorted group).
local function _groups_first(widgets)
    local groups, rest = {}, {}
    for _, w in ipairs(widgets) do
        if w.type == "group" then
            groups[#groups + 1] = w
        else
            rest[#rest + 1] = w
        end
    end
    if #groups == 0 or #rest == 0 then return end  -- nothing to reorder
    local i = 0
    for _, w in ipairs(groups) do i = i + 1; widgets[i] = w end
    for _, w in ipairs(rest)   do i = i + 1; widgets[i] = w end
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
    -- After children are settled, lift any collapsible sub-groups above loose
    -- options at THIS level (the "collapsible above options" rule).
    _groups_first(widgets)
end

-- `text` values are localization keys (resolved by VMF via mod:localize). VMF wraps any missing
-- key in `<<>>`, so even numeric labels like "1".."9" need explicit loc entries — see
-- _localization.lua.
--
-- Chests-of-Trials and arena-ammo dropdown options (max 10, matching the vanilla numeric
-- versions). value=-1 is the "use vanilla count" / "leave vanilla distribution untouched"
-- sentinel (was value=0 pre-0.7.65 — see chaos_wastes_tweaker.lua get_deus_weapon_chest_type);
-- value=0 now means "force zero". (The v0.7.65 altar-count dropdown that shared this shape was
-- removed as dead code, along with the Miracle of Isha legacy-dropdown option table; only this
-- table remains.)
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

-- Finale God dropdown options. value = index into FINALE_GODS (chaos_wastes_tweaker_dev.lua:481
-- { "nurgle", "tzeentch", "khorne", "slaanesh" }); value 0 = no override, the `> 0` guard at
-- ~L3989 leaves the game's weekly rotation in place. Stored value is the same integer the old
-- numeric widget wrote, so existing saved settings carry over unchanged.
local finale_god_options = {
    { text = "finale_god_rotation", value = 0 },
    { text = "finale_god_nurgle",   value = 1 },
    { text = "finale_god_tzeentch", value = 2 },
    { text = "finale_god_khorne",   value = 3 },
    { text = "finale_god_slaanesh", value = 4 },
}

-- #146: Citadel APPROACH-map god (sig_citadel), separate from the finale arena.
-- value 0 = follow the finale god; 1-4 index FINALE_GODS just like finale_god_options.
local finale_approach_options = {
    { text = "finale_approach_same",  value = 0 },
    { text = "finale_god_nurgle",     value = 1 },
    { text = "finale_god_tzeentch",   value = 2 },
    { text = "finale_god_khorne",     value = 3 },
    { text = "finale_god_slaanesh",   value = 4 },
}

local data = {
    name = mod:localize("mod_name"),
    description = mod:localize("mod_description"),
    is_togglable = true,
    options = {
        -- Top-level groups are ordered A->Z by English display label (repo standing
        -- rule). recursive_sort() only alphabetizes WITHIN the boon trees (SORT_GROUPS);
        -- top-level and other groups keep this declared order. Deliberate-order blocks
        -- (mutex clusters, the god-grouped curse banlist, the paired altar-reuse rows)
        -- are flagged inline where they intentionally deviate from A->Z.
        widgets = {
            -- ============================================================
            -- #505 Single Mission Loader (host-only). Widget tree built in
            -- _ct_dev_mission_catalog.build_menu_group(); the keybind resolves
            -- mod.ct_dev_load_selected_mission. recursive_sort() places it by its
            -- localized "[untested] Dev: ..." title among the top-level groups.
            -- ============================================================
            DevMission.build_menu_group(),
            -- ============================================================
            -- Progressive Difficulty (deliberate top-of-list placement: a
            -- run-wide difficulty modifier, not one of the A-Z groups below)
            -- ============================================================
            {
                setting_id = "progressive_difficulty",
                type = "checkbox",
                default_value = false,
                tooltip = "progressive_difficulty_tooltip",
                sub_widgets = {
                    {
                        setting_id = "progressive_difficulty_increase",
                        type = "checkbox",
                        default_value = true,
                        tooltip = "progressive_difficulty_increase_tooltip",
                    },
                    {
                        setting_id = "progressive_coin_reduction",
                        type = "numeric",
                        default_value = -25,
                        range = { -100, 0 },
                        decimals_number = 0,
                        tooltip = "progressive_coin_reduction_tooltip",
                    },
                },
            },
            -- ============================================================
            -- Buy Starting Boons (#458): top-level like Progressive Difficulty
            -- (a run-start modifier, not one of the A-Z groups). The advanced
            -- sub-options tune this shrine independently of normal ones. Cost
            -- multiplier + pick limit are deferred (see chaos_wastes_tweaker_dev.lua
            -- "#458 remaining scope") so only the wired knobs appear here.
            -- ============================================================
            {
                setting_id = "ct_buy_starting_boons",
                type = "checkbox",
                default_value = false,
                tooltip = "ct_buy_starting_boons_tooltip",
                sub_widgets = {
                    { setting_id = "ct_start_shrine_boon_count",    type = "numeric", default_value = 4, range = { 0, 8 }, decimals_number = 0, tooltip = "ct_start_shrine_boon_count_tooltip" },
                    { setting_id = "ct_start_shrine_miracle_count", type = "numeric", default_value = 0, range = { 0, 3 }, decimals_number = 0, tooltip = "ct_start_shrine_miracle_count_tooltip" },
                    {
                        setting_id = "ct_start_shrine_miracle_pool_group",
                        type = "group",
                        sub_widgets = {
                            { setting_id = "ct_start_shrine_miracle_blessing_of_power",          type = "checkbox", default_value = true, tooltip = "ct_start_shrine_miracle_blessing_of_power_tooltip" },
                            { setting_id = "ct_start_shrine_miracle_blessing_of_shallya",        type = "checkbox", default_value = true, tooltip = "ct_start_shrine_miracle_blessing_of_shallya_tooltip" },
                            { setting_id = "ct_start_shrine_miracle_blessing_of_grimnir",        type = "checkbox", default_value = true, tooltip = "ct_start_shrine_miracle_blessing_of_grimnir_tooltip" },
                            { setting_id = "ct_start_shrine_miracle_blessing_of_isha",           type = "checkbox", default_value = true, tooltip = "ct_start_shrine_miracle_blessing_of_isha_tooltip" },
                            { setting_id = "ct_start_shrine_miracle_blessing_of_ranald",         type = "checkbox", default_value = true, tooltip = "ct_start_shrine_miracle_blessing_of_ranald_tooltip" },
                            { setting_id = "ct_start_shrine_miracle_blessing_of_abundance",      type = "checkbox", default_value = true, tooltip = "ct_start_shrine_miracle_blessing_of_abundance_tooltip" },
                            { setting_id = "ct_start_shrine_miracle_blessing_holy_hand_grenade", type = "checkbox", default_value = true, tooltip = "ct_start_shrine_miracle_blessing_holy_hand_grenade_tooltip" },
                            { setting_id = "ct_start_shrine_miracle_blessing_rally_flag",        type = "checkbox", default_value = true, tooltip = "ct_start_shrine_miracle_blessing_rally_flag_tooltip" },
                        },
                    },
                },
            },
            -- ============================================================
            -- Adventure Maps
            -- ============================================================
            {
                setting_id = "adventure_maps_group",
                type = "group",
                sub_widgets = {
                    -- inject_adventure_maps is the master for the mission-selection list:
                    -- _adventure_pool.lua:747 returns early (every per-mission toggle
                    -- ignored) when it is off, so nesting available_missions_group under
                    -- it only ever hides inert widgets. replace_shrines_with_missions is
                    -- NOT gated on inject (checked independently at
                    -- chaos_wastes_tweaker.lua:5661), so it stays a loose sibling.
                    {
                        setting_id = "inject_adventure_maps", type = "checkbox", default_value = false, tooltip = "inject_adventure_maps_tooltip",
                        sub_widgets = {
                            {
                                -- #457 "Revamp Mission Availability": each DLC / the
                                -- Helmgart campaign / the CW scenarios / the event missions
                                -- is a MASTER toggle. Campaign/DLC masters are grouped under
                                -- the "Campaign Scenarios" collapsible; the CW and Event
                                -- masters sit beside it (build_*_block returns a checkbox with
                                -- an advanced per-mission sub-list). A mission is enabled iff
                                -- its master is on AND (single-mission group, or its per-mission
                                -- toggle is on). enable_group_* changes re-run inject_pool via
                                -- is_pool_setting (chaos_wastes_tweaker_dev.lua). The pool floor
                                -- in inject_pool makes any "disable everything" config safe.
                                setting_id = "available_missions_group",
                                type = "group",
                                sub_widgets = {
                                    { setting_id = "campaign_scenarios_group", type = "group", sub_widgets = AdventurePool.build_campaign_dlc_group_widgets() },
                                    AdventurePool.build_cw_scenarios_block(),
                                    AdventurePool.build_event_missions_block(),
                                },
                            },
                        },
                    },
                    { setting_id = "replace_shrines_with_missions", type = "checkbox", default_value = false, tooltip = "replace_shrines_with_missions_tooltip" },
                },
            },
            -- ============================================================
            -- Banned Weapon Traits
            -- ============================================================
            {
                setting_id = "banned_traits_group",
                type = "group",
                -- Sub-groups A->Z: "Chaos Wastes Weapon Traits" before "Vanilla Weapon
                -- Traits". Per-trait boxes A->Z by display (trait) label.
                sub_widgets = {
                    {
                        setting_id = "ban_trait_chaos_wastes_group",
                        type = "group",
                        sub_widgets = {
                            { setting_id = "ban_trait_deus_ranged_crit_explosion",                 type = "checkbox", default_value = false, tooltip = "ban_trait_deus_ranged_crit_explosion_tooltip" },
                            { setting_id = "ban_trait_deus_ammo_pickup_reload_speed",              type = "checkbox", default_value = false, tooltip = "ban_trait_deus_ammo_pickup_reload_speed_tooltip" },
                            { setting_id = "ban_trait_piercing_projectiles",                       type = "checkbox", default_value = false, tooltip = "ban_trait_piercing_projectiles_tooltip" },
                            { setting_id = "ban_trait_refilling_shot",                             type = "checkbox", default_value = false, tooltip = "ban_trait_refilling_shot_tooltip" },
                            { setting_id = "ban_trait_deus_collateral_damage_on_melee_killing_blow", type = "checkbox", default_value = false, tooltip = "ban_trait_deus_collateral_damage_on_melee_killing_blow_tooltip" },
                            { setting_id = "ban_trait_bloodthirst",                                type = "checkbox", default_value = false, tooltip = "ban_trait_bloodthirst_tooltip" },
                            { setting_id = "ban_trait_headhunter",                                 type = "checkbox", default_value = false, tooltip = "ban_trait_headhunter_tooltip" },
                            { setting_id = "ban_trait_shield_of_isha",                             type = "checkbox", default_value = false, tooltip = "ban_trait_shield_of_isha_tooltip" },
                            { setting_id = "ban_trait_follow_up",                                  type = "checkbox", default_value = false, tooltip = "ban_trait_follow_up_tooltip" },
                            { setting_id = "ban_trait_serrated_blade",                             type = "checkbox", default_value = false, tooltip = "ban_trait_serrated_blade_tooltip" },
                            { setting_id = "ban_trait_deus_crit_chain_lightning",                  type = "checkbox", default_value = false, tooltip = "ban_trait_deus_crit_chain_lightning_tooltip" },
                            { setting_id = "ban_trait_deus_big_swing_stagger",                     type = "checkbox", default_value = false, tooltip = "ban_trait_deus_big_swing_stagger_tooltip" },
                            { setting_id = "ban_trait_home_run",                                   type = "checkbox", default_value = false, tooltip = "ban_trait_home_run_tooltip" },
                            { setting_id = "ban_trait_shield_splinters",                           type = "checkbox", default_value = false, tooltip = "ban_trait_shield_splinters_tooltip" },
                            { setting_id = "ban_trait_armor_breaker",                              type = "checkbox", default_value = false, tooltip = "ban_trait_armor_breaker_tooltip" },
                            { setting_id = "ban_trait_stagger_aoe_on_crit",                        type = "checkbox", default_value = false, tooltip = "ban_trait_stagger_aoe_on_crit_tooltip" },
                            { setting_id = "ban_trait_deus_extra_shot",                            type = "checkbox", default_value = false, tooltip = "ban_trait_deus_extra_shot_tooltip" },
                            { setting_id = "ban_trait_always_blocking",                            type = "checkbox", default_value = false, tooltip = "ban_trait_always_blocking_tooltip" },
                            { setting_id = "ban_trait_crescendo_strike",                           type = "checkbox", default_value = false, tooltip = "ban_trait_crescendo_strike_tooltip" },
                        },
                    },
                    {
                        setting_id = "ban_trait_vanilla_group",
                        type = "group",
                        sub_widgets = {
                            { setting_id = "ban_trait_ranged_consecutive_hits_increase_power",     type = "checkbox", default_value = false, tooltip = "ban_trait_ranged_consecutive_hits_increase_power_tooltip" },
                            { setting_id = "ban_trait_ranged_replenish_ammo_headshot",             type = "checkbox", default_value = false, tooltip = "ban_trait_ranged_replenish_ammo_headshot_tooltip" },
                            { setting_id = "ban_trait_ranged_remove_overcharge_on_crit",           type = "checkbox", default_value = false, tooltip = "ban_trait_ranged_remove_overcharge_on_crit_tooltip" },
                            { setting_id = "ban_trait_melee_shield_on_assist",                     type = "checkbox", default_value = false, tooltip = "ban_trait_melee_shield_on_assist_tooltip" },
                            { setting_id = "ban_trait_ranged_increase_power_level_vs_armour_crit", type = "checkbox", default_value = false, tooltip = "ban_trait_ranged_increase_power_level_vs_armour_crit_tooltip" },
                            { setting_id = "ban_trait_ranged_restore_stamina_headshot",            type = "checkbox", default_value = false, tooltip = "ban_trait_ranged_restore_stamina_headshot_tooltip" },
                            { setting_id = "ban_trait_melee_increase_damage_on_block",             type = "checkbox", default_value = false, tooltip = "ban_trait_melee_increase_damage_on_block_tooltip" },
                            { setting_id = "ban_trait_melee_counter_push_power",                   type = "checkbox", default_value = false, tooltip = "ban_trait_melee_counter_push_power_tooltip" },
                            { setting_id = "ban_trait_melee_timed_block_cost",                     type = "checkbox", default_value = false, tooltip = "ban_trait_melee_timed_block_cost_tooltip" },
                            { setting_id = "ban_trait_melee_heal_on_crit",                         type = "checkbox", default_value = false, tooltip = "ban_trait_melee_heal_on_crit_tooltip" },
                            { setting_id = "ban_trait_melee_reduce_cooldown_on_crit",              type = "checkbox", default_value = false, tooltip = "ban_trait_melee_reduce_cooldown_on_crit_tooltip" },
                            { setting_id = "ban_trait_ranged_reduce_cooldown_on_crit",             type = "checkbox", default_value = false, tooltip = "ban_trait_ranged_reduce_cooldown_on_crit_tooltip" },
                            { setting_id = "ban_trait_ranged_replenish_ammo_on_crit",              type = "checkbox", default_value = false, tooltip = "ban_trait_ranged_replenish_ammo_on_crit_tooltip" },
                            { setting_id = "ban_trait_melee_attack_speed_on_crit",                 type = "checkbox", default_value = false, tooltip = "ban_trait_melee_attack_speed_on_crit_tooltip" },
                            { setting_id = "ban_trait_ranged_reduced_overcharge",                  type = "checkbox", default_value = false, tooltip = "ban_trait_ranged_reduced_overcharge_tooltip" },
                        },
                    },
                },
            },
            -- ============================================================
            -- Curses
            -- ============================================================
            {
                setting_id = "curses_group",
                type = "group",
                -- Groups-first lifts the two banlist sub-groups above the loose curse
                -- options. Sub-groups A->Z ("Boss Grudge Marks Banlist" < "Disabled
                -- Curses"); loose options A->Z by display label.
                sub_widgets = {
                    {
                        setting_id = "boss_grudge_marks_group",
                        type = "group",
                        -- A->Z by "Ban: <Mark>" display label (matches setting_id order here).
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
                    {
                        setting_id = "miasma_group",
                        type = "group",
                        sub_widgets = {
                            { setting_id = "miasma_permanent_carrier", type = "checkbox", default_value = false, tooltip = "miasma_permanent_carrier_tooltip" },
                            { setting_id = "miasma_safe_radius", type = "numeric", default_value = 8, range = { 2, 30 }, decimals_number = 1, tooltip = "miasma_safe_radius_tooltip" },
                            { setting_id = "miasma_stack_interval", type = "numeric", default_value = 1.3, range = { 0.1, 5 }, decimals_number = 1, tooltip = "miasma_stack_interval_tooltip" },
                        },
                    },
                    {
                        setting_id = "disabled_curses_group",
                        type = "group",
                        -- DELIBERATE ORDER (not plain A->Z): grouped by host god, then
                        -- curse, matching vanilla deus_map_populate_settings.lua `all_curses`
                        -- and the "Disable: <God>: <Curse>" loc labels.
                        sub_widgets = {
                            { setting_id = "disable_curse_belakor_totems", type = "checkbox", default_value = false },        -- Belakor
                            { setting_id = "disable_curse_shadow_homing_skulls", type = "checkbox", default_value = false },  -- Belakor
                            { setting_id = "disable_curse_blood_storm", type = "checkbox", default_value = false },           -- Khorne
                            { setting_id = "disable_curse_khorne_champions", type = "checkbox", default_value = false },       -- Khorne
                            { setting_id = "disable_curse_skulls_of_fury", type = "checkbox", default_value = false },         -- Khorne
                            { setting_id = "disable_curse_corrupted_flesh", type = "checkbox", default_value = false },        -- Nurgle
                            { setting_id = "disable_curse_rotten_miasma", type = "checkbox", default_value = false },          -- Nurgle
                            { setting_id = "disable_curse_skulking_sorcerer", type = "checkbox", default_value = false },      -- Nurgle (NOT Tzeentch)
                            { setting_id = "disable_curse_empathy", type = "checkbox", default_value = false },               -- Slaanesh
                            { setting_id = "disable_curse_greed_pinata", type = "checkbox", default_value = false },          -- Slaanesh
                            { setting_id = "disable_curse_abundance_of_life", type = "checkbox", default_value = false },      -- Slaanesh (Unquenchable Thirst)
                            { setting_id = "disable_curse_bolt_of_change", type = "checkbox", default_value = false },         -- Tzeentch
                            { setting_id = "disable_curse_change_of_tzeentch", type = "checkbox", default_value = false },     -- Tzeentch
                            { setting_id = "disable_curse_egg_of_tzeentch", type = "checkbox", default_value = false },        -- Tzeentch
                        },
                    },
                    { setting_id = "force_belakor", type = "checkbox", default_value = false },
                    -- v0.7.200-dev (#104): host-side rolling-window cap on the Corrupted
                    -- Flesh curse's globadier-class gas clouds. 0 = vanilla/uncapped.
                    { setting_id = "flesh_guard_clouds_per_minute", type = "numeric", default_value = 6, range = { 0, 30 }, decimals_number = 0, tooltip = "flesh_guard_clouds_per_minute_tooltip" },
                    { setting_id = "cursed_mission_count", type = "numeric", default_value = 0, range = { 0, 30 }, decimals_number = 0, tooltip = "cursed_mission_count_tooltip" },
                    { setting_id = "disable_dominant_god", type = "checkbox", default_value = true, tooltip = "disable_dominant_god_tooltip" },
                    { setting_id = "finale_dominant_god", type = "dropdown", default_value = 0, options = finale_god_options, tooltip = "finale_dominant_god_tooltip" },
                    { setting_id = "finale_approach_god", type = "dropdown", default_value = 0, options = finale_approach_options, tooltip = "finale_approach_god_tooltip" },
                    -- #243: user brightness knob for the injected-map curse lighting
                    -- (CameraManager.shading_callback). 1.0 = baked profile as-is.
                    { setting_id = "curse_lighting_brightness", type = "numeric", default_value = 1.0, range = { 0.5, 2.5 }, decimals_number = 2, tooltip = "curse_lighting_brightness_tooltip" },
                },
            },
            -- ============================================================
            -- Disabled Boons (BOON_TREE-generated; internal order settled by recursive_sort)
            -- ============================================================
            {
                setting_id = "disabled_boons_group",
                type = "group",
                sub_widgets = build_disable_tree(),
            },
            -- ============================================================
            -- Pilgrim's Coin
            -- ============================================================
            {
                setting_id = "pilgrims_coin_group",
                type = "group",
                sub_widgets = {
                    { setting_id = "coin_multiplier", type = "numeric", default_value = 1, range = { 0.1, 5 }, decimals_number = 2 },
                    -- (#164) starting_coins is INTENTIONALLY a plain fine-grained slider here: VMF's own
                    -- options menu steps by 1 so the user can dial an exact value (e.g. 324). The coarse
                    -- 25-step lives ONLY in gut's Mod Tweaker (its STEP_OVERRIDES registry). Do NOT add a
                    -- `step` field or a 3rd range element to snap it:
                    --   * range MUST be exactly 2 elements -- VMF's validate_numeric_data FATALS on a 3rd
                    --     ('range' field must contain an array-like table with 2 elements) and aborts the
                    --     mod's ENTIRE options init (ct .188 was DEAD; reverted .189).
                    --   * a top-level `step` field is non-fatal but USELESS: VMF's initialize_numeric_data
                    --     (core/options.lua:439-448) rebuilds the widget copying only range/default_value/
                    --     decimals_number/unit_text, so `step` never reaches the Mod Tweaker anyway.
                    { setting_id = "starting_coins", type = "numeric", default_value = 0, range = { 0, 3000 }, decimals_number = 0 },
                },
            },
            -- ============================================================
            -- Bots (#331)
            -- ============================================================
            {
                setting_id = "bots_group",
                type = "group",
                sub_widgets = {
                    { setting_id = "ct_blessed_bots", type = "checkbox", default_value = false, tooltip = "ct_blessed_bots_tooltip" },
                    { setting_id = "bots_pick_up_pilgrims_coins", type = "checkbox", default_value = false, tooltip = "bots_pick_up_pilgrims_coins_tooltip" },
                    { setting_id = "announce_bot_boons", type = "checkbox", default_value = false, tooltip = "announce_bot_boons_tooltip" },
                    { setting_id = "bots_mirror_host_boons", type = "checkbox", default_value = false, tooltip = "bots_mirror_host_boons_tooltip" },
                    { setting_id = "bots_get_random_boons", type = "checkbox", default_value = false, tooltip = "bots_get_random_boons_tooltip" },
                    { setting_id = "bots_mirror_host_weapon_upgrades", type = "checkbox", default_value = false, tooltip = "bots_mirror_host_weapon_upgrades_tooltip" },
                },
            },
            -- ============================================================
            -- Reworks
            -- ============================================================
            {
                setting_id = "reworks_group",
                type = "group",
                -- Groups-first lifts the two Reworks sub-groups above the loose options.
                -- Sub-groups A->Z ("Reworks: Boons" < "Reworks: Potions"); loose options
                -- A->Z by display label.
                sub_widgets = {
                    {
                        setting_id = "reworks_boons_group",
                        type = "group",
                        -- v0.7.159-dev Task 1: split into two NESTED sub-groups --
                        --   (a) reworks_boons_existing_group: modify how an EXISTING
                        --       boon / property / bot-distribution behaves.
                        --   (b) reworks_boons_new_group: ADD a brand-new selectable boon
                        --       (the five `enable_boon_*` trait-as-boon toggles).
                        -- Sub-groups A->Z ("Existing" < "New"). All setting_ids preserved.
                        sub_widgets = {
                            {
                                setting_id = "reworks_boons_existing_group",
                                type = "group",
                                -- A->Z by display label ([untested] status tag ignored for
                                -- sort). The Miracle of Isha mutex cluster (isha_choice) keeps
                                -- its "    (A) / (B)" 4-space-indent labels and stays adjacent
                                -- in letter order (enforced in on_setting_changed via
                                -- chaos_wastes_tweaker_mutex); the leading indent sorts it first.
                                sub_widgets = {
                                    { setting_id = "tweak_miracle_of_isha_aegis",  type = "checkbox", default_value = false, tooltip = "tweak_miracle_of_isha_aegis_tooltip" },
                                    { setting_id = "tweak_miracle_of_isha_wounds", type = "checkbox", default_value = false, tooltip = "tweak_miracle_of_isha_wounds_tooltip" },
                                    { setting_id = "rv_no_save_morgrim", type = "checkbox", default_value = false, tooltip = "rv_no_save_morgrim_tooltip" },
                                    { setting_id = "bomb_boon_cooldown", type = "numeric", default_value = 0, range = { 0, 600 }, decimals_number = 0, tooltip = "bomb_boon_cooldown_tooltip" },
                                    { setting_id = "bomb_boon_exclusive", type = "checkbox", default_value = false, tooltip = "bomb_boon_exclusive_tooltip" },
                                    { setting_id = "tweak_miracle_of_ulric_persistent", type = "checkbox", default_value = false, tooltip = "tweak_miracle_of_ulric_persistent_tooltip" },
                                    { setting_id = "tweak_wildfire_generations_cap", type = "numeric", default_value = 3, range = { 1, 10 }, decimals_number = 0, tooltip = "tweak_wildfire_generations_cap_tooltip" },
                                    { setting_id = "endless_bombs_consumes_morgrim", type = "checkbox", default_value = false, tooltip = "endless_bombs_consumes_morgrim_tooltip" },
                                    { setting_id = "tweak_anath_raema_permanent",     type = "checkbox", default_value = false, tooltip = "tweak_anath_raema_permanent_tooltip" },
                                    { setting_id = "tweak_defeat_recovery",           type = "checkbox", default_value = false, tooltip = "tweak_defeat_recovery_tooltip" },
                                    { setting_id = "tweak_reckless_swings", type = "checkbox", default_value = false, tooltip = "tweak_reckless_swings_tooltip" },
                                    { setting_id = "tweak_manann_tempest_cooldown",   type = "checkbox", default_value = false, tooltip = "tweak_manann_tempest_cooldown_tooltip" },
                                    { setting_id = "tweak_boon_movespeed", type = "checkbox", default_value = false, tooltip = "tweak_boon_movespeed_tooltip" },
                                    { setting_id = "replacement_player_compensation", type = "checkbox", default_value = true, tooltip = "replacement_player_compensation_tooltip" },
                                    { setting_id = "ulric_pack_unlimited_range", type = "checkbox", default_value = false, tooltip = "ulric_pack_unlimited_range_tooltip" },
                                },
                            },
                            {
                                setting_id = "reworks_boons_new_group",
                                type = "group",
                                sub_widgets = {
                                    -- #464 follow-up: 5th trait-as-boon (Anath Raema's Swiftness,
                                    -- permanent reload variant). A->Z: anath < asuryan.
                                    { setting_id = "enable_boon_anath_raema_swiftness", type = "checkbox", default_value = false, tooltip = "enable_boon_anath_raema_swiftness_tooltip" },
                                    { setting_id = "enable_boon_asuryan_wrath",       type = "checkbox", default_value = false, tooltip = "enable_boon_asuryan_wrath_tooltip" },
                                    { setting_id = "enable_boon_manann_tempest",      type = "checkbox", default_value = false, tooltip = "enable_boon_manann_tempest_tooltip" },
                                    { setting_id = "enable_boon_taal_twinned_arrow",  type = "checkbox", default_value = false, tooltip = "enable_boon_taal_twinned_arrow_tooltip" },
                                    { setting_id = "enable_boon_vauls_anvil",         type = "checkbox", default_value = false, tooltip = "enable_boon_vauls_anvil_tooltip" },
                                },
                            },
                        },
                    },
                    {
                        setting_id = "reworks_potions_group",
                        type = "group",
                        sub_widgets = {
                            { setting_id = "enable_campaign_potions", type = "checkbox", default_value = false },
                            { setting_id = "tweak_home_brewer_potency", type = "checkbox", default_value = false, tooltip = "tweak_home_brewer_potency_tooltip" },
                            { setting_id = "tweak_invis_potion_2x", type = "checkbox", default_value = false, tooltip = "tweak_invis_potion_2x_tooltip" },
                            { setting_id = "tweak_moot_milk_alt", type = "checkbox", default_value = false, tooltip = "tweak_moot_milk_alt_tooltip" },
                            { setting_id = "tweak_poison_proof_duration", type = "checkbox", default_value = false, tooltip = "tweak_poison_proof_duration_tooltip" },
                        },
                    },
                    { setting_id = "any_trait_any_weapon", type = "checkbox", default_value = false, tooltip = "any_trait_any_weapon_tooltip" },
                    { setting_id = "arena_ammo_count", type = "dropdown", default_value = -1, options = count_with_default_options, tooltip = "arena_ammo_count_tooltip" },
                    { setting_id = "tweak_shard_strike_duration", type = "numeric", default_value = 16, range = { 1, 16 }, decimals_number = 0, tooltip = "tweak_shard_strike_duration_tooltip" },
                    { setting_id = "tweak_trait_tier_by_rarity", type = "checkbox", default_value = false, tooltip = "tweak_trait_tier_by_rarity_tooltip" },
                    { setting_id = "tweak_shadow_skull_stun_sec", type = "numeric", default_value = 2.5, range = { 0.0, 10.0 }, decimals_number = 1, tooltip = "tweak_shadow_skull_stun_sec_tooltip" },
                },
            },
            -- ============================================================
            -- Shrines, Altars and Chests
            -- ============================================================
            {
                setting_id = "shrines_altars_chests_group",
                type = "group",
                -- Every setting lives in a labeled collapsible (no loose options).
                -- Sub-groups A->Z by display label.
                sub_widgets = {
                    {
                        -- v0.7.127-dev: altar reuse. count = max times the altar can be
                        -- USED per visit (1 = vanilla). cost_mult = geometric multiplier
                        -- applied per subsequent use: cost_N = base_cost * (mult ^ (N-1)).
                        -- DELIBERATE ORDER: each altar's count row is followed by its
                        -- cost-multiplier row (intuitive pairing); the four altar names are
                        -- themselves A->Z (Boon shrine < Melee swap < Ranged swap < Weapon
                        -- upgrade). All values host-broadcast.
                        setting_id = "altar_reuse_group",
                        type = "group",
                        sub_widgets = {
                            { setting_id = "altar_reuse_count_power_up",     type = "numeric", default_value = 1,   range = { 1, 20 },  decimals_number = 0, tooltip = "altar_reuse_count_tooltip" },
                            { setting_id = "altar_reuse_cost_mult_power_up", type = "numeric", default_value = 1.0, range = { 0.1, 10 }, decimals_number = 1, tooltip = "altar_reuse_cost_mult_tooltip" },
                            { setting_id = "altar_reuse_count_swap_melee",     type = "numeric", default_value = 1,   range = { 1, 20 },  decimals_number = 0, tooltip = "altar_reuse_count_tooltip" },
                            { setting_id = "altar_reuse_cost_mult_swap_melee", type = "numeric", default_value = 1.0, range = { 0.1, 10 }, decimals_number = 1, tooltip = "altar_reuse_cost_mult_tooltip" },
                            { setting_id = "altar_reuse_count_swap_ranged",     type = "numeric", default_value = 1,   range = { 1, 20 },  decimals_number = 0, tooltip = "altar_reuse_count_tooltip" },
                            { setting_id = "altar_reuse_cost_mult_swap_ranged", type = "numeric", default_value = 1.0, range = { 0.1, 10 }, decimals_number = 1, tooltip = "altar_reuse_cost_mult_tooltip" },
                            { setting_id = "altar_reuse_count_upgrade",     type = "numeric", default_value = 1,   range = { 1, 20 },  decimals_number = 0, tooltip = "altar_reuse_count_upgrade_tooltip" },
                            { setting_id = "altar_reuse_cost_mult_upgrade", type = "numeric", default_value = 1.0, range = { 0.1, 10 }, decimals_number = 1, tooltip = "altar_reuse_cost_mult_tooltip" },
                        },
                    },
                    {
                        -- Per-mission spawn-count sliders. The 4 altar counts keep -1..9
                        -- (-1 = Default): -1 = "skip override", 0 = none, 1-9 = force N.
                        setting_id = "altar_chest_counts_group",
                        type = "group",
                        sub_widgets = {
                            { setting_id = "chest_power_up_count",     type = "numeric", default_value = -1, range = { -1, 9 }, decimals_number = 0, tooltip = "altar_count_tooltip" },
                            -- Chests of Trials: explicit 0..5 slider, default 1 (no -1/Default).
                            -- The consuming cap already maps -1 -> 1 (chaos_wastes_tweaker.lua:5447).
                            { setting_id = "cursed_chest_count",      type = "numeric", default_value = 1,  range = { 0, 5 },  decimals_number = 0, tooltip = "cursed_chest_count_tooltip" },
                            { setting_id = "chest_swap_melee_count",  type = "numeric", default_value = -1, range = { -1, 9 }, decimals_number = 0, tooltip = "altar_count_tooltip" },
                            { setting_id = "chest_swap_ranged_count", type = "numeric", default_value = -1, range = { -1, 9 }, decimals_number = 0, tooltip = "altar_count_tooltip" },
                            { setting_id = "chest_upgrade_count",     type = "numeric", default_value = -1, range = { -1, 9 }, decimals_number = 0, tooltip = "altar_count_tooltip" },
                        },
                    },
                    {
                        -- Number of boon CHOICES each shrine / chest offers (not spawn counts).
                        -- v0.7.199-dev: caps raised 5 -> 50; extra offerings scroll.
                        setting_id = "boons_offered_group",
                        type = "group",
                        sub_widgets = {
                            { setting_id = "chest_boon_count",  type = "numeric", default_value = 3, range = { 1, 50 }, decimals_number = 0 },
                            { setting_id = "shrine_boon_count", type = "numeric", default_value = 4, range = { 1, 50 }, decimals_number = 0 },
                        },
                    },
                    {
                        setting_id = "chest_of_trials_group",
                        type = "group",
                        sub_widgets = {
                            -- Per-Chest-of-Trials enemy spawn-count multiplier (Issue #64).
                            -- 1.0 = vanilla; applies only to the "cursed_chest_enemies" waves.
                            { setting_id = "cot_open_at_trial_start", type = "checkbox", default_value = false, tooltip = "cot_open_at_trial_start_tooltip" },
                            { setting_id = "cot_enemy_multiplier", type = "numeric", default_value = 1.0, range = { 0.5, 5.0 }, decimals_number = 1, tooltip = "cot_enemy_multiplier_tooltip" },
                            { setting_id = "respawn_on_chest_complete", type = "checkbox", default_value = false, tooltip = "respawn_on_chest_complete_tooltip" },
                        },
                    },
                },
            },
            -- ============================================================
            -- Starting Boons (BOON_TREE-generated; internal order settled by recursive_sort)
            -- ============================================================
            {
                setting_id = "starting_boons_group",
                type = "group",
                -- #461: the Tab-hold starting-boon preview toggle rides at the top of the
                -- Starting Boons group. It is a loose option, so _groups_first renders it
                -- BELOW the boon category collapsibles (standing menu rule); default ON.
                sub_widgets = (function()
                    local w = build_start_tree()
                    table.insert(w, 1, {
                        setting_id = "preview_starting_boons",
                        type = "checkbox",
                        default_value = true,
                        tooltip = "preview_starting_boons_tooltip",
                    })
                    return w
                end)(),
            },
            -- 2026-05-23 v0.7.98-dev DISABLED: Activate Dormant Boons + Skulls Event Boons
            -- VMF groups removed per user request after Chest-of-Trials crash. The
            -- corresponding lua implementation is block-commented in
            -- `chaos_wastes_tweaker.lua` (~L4448 dormants, ~L4724 Skulls). The
            -- "start_boon_dormant_group" widget (in build_start_tree) is also effectively
            -- unused now - those dormants will not register, so picking a starting boon
            -- from that list would fail to apply. Keeping the start-tree widget visible
            -- would mislead users; consider commenting build_start_tree's dormant_widgets
            -- too if dormant disable becomes permanent.
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
        },
    },
}

recursive_sort(data.options.widgets)

return data
