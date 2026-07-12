local mod = get_mod("crt")

-- ============================================================
-- Tourney Balance Testing -> crt port (PHASE 1: clean per-career data mutations)
-- ============================================================
-- Faithful, opt-in (default-OFF) ports of the "Tourney Balance Testing" Workshop
-- mod's CAREER/TALENT changes, transcribed from its decompiled source and verified
-- against the vanilla decompile. Each entry mutates BuffTemplates[name].buffs[1]
-- fields with vanilla-value snapshot/restore, via the same engine pattern as
-- career_tweaker_balance.lua. Loaded as a 3rd {apply,restore,active_count} module
-- alongside balance + big_rebalance.
--
-- NetworkLookup determinism: any BRAND-NEW BuffTemplate a port introduces is
-- registered UNCONDITIONALLY as a no-op stub at load (alphabetical order), exactly
-- like crt_balance's _CRT_BUFF_NAMES, so peers stay index-consistent regardless of
-- toggle state (the rpc_add_buff divergence crash class). custom_apply installs the
-- real body; custom_restore stubs it back.
--
-- Generated 2026-06-17 from misc-vermintide-mods/_scratch/tourney_2545022878.

local function _crt_make_stub()
    return { buffs = {}, _crt_pending = true }
end

-- New BuffTemplates introduced by the Saltzpyre ports. Registered UNCONDITIONALLY
-- as stubs (alphabetical, load-bearing for NetworkLookup index determinism).
local _TRN_BUFF_NAMES = {
    "victor_bountyhunter_blessed_melee_attack_speed_buff",
    "victor_priest_5_2_speed_buff",
}
if BuffTemplates and NetworkLookup and NetworkLookup.buff_templates then
    for _, name in ipairs(_TRN_BUFF_NAMES) do
        if BuffTemplates[name] == nil then
            BuffTemplates[name] = _crt_make_stub()
        end
        if not rawget(NetworkLookup.buff_templates, name) then
            local idx = #NetworkLookup.buff_templates + 1
            NetworkLookup.buff_templates[idx] = name
            NetworkLookup.buff_templates[name] = idx
        end
    end
end

-- Issue 425: add this module's registrations to the mod-wide registered-name
-- registry (seeded by career_tweaker_balance.lua, which loads first; create-if-
-- missing keeps this order-robust). The hot-join replay filter and the
-- /crt_regression_test raw-networked-func sweep key off it -- these names have
-- NO crt_ prefix, so a prefix check alone misses them.
mod._crt_mod_registered_buff_names = mod._crt_mod_registered_buff_names or {}
for _, name in ipairs(_TRN_BUFF_NAMES) do
    mod._crt_mod_registered_buff_names[name] = true
end

-- Cross-toggle conflicts: a trn_ entry that patches the SAME buff field as an
-- existing crt rework_ toggle. If the user's own rework is ON, the Tourney entry
-- is SKIPPED entirely (the engine never snapshots/applies it) so the two can't
-- corrupt each other's vanilla snapshot. Documented in the tooltips.
local _CONFLICTS = {
    trn_es_huntsman   = { "rework_es_huntsman_crit_aura_unlimited_range" },
    trn_wh_bountyhunter = { "rework_wh_bountyhunter_double_shotted_80" },
    trn_wh_zealot     = { "rework_wh_zealot_power_5_to_10" },
    trn_bw_adept      = { "rework_bw_adept_famished_flames_buffed", "rework_bw_adept_fires_from_ash_1pct_plus_thp" },
}
local function _conflict_active(setting_id)
    local list = _CONFLICTS[setting_id]
    if not list then return false end
    for _, other in ipairs(list) do
        if mod:get(other) then return true end
    end
    return false
end

local TOURNEY_MODS = {
    trn_es_mercenary = {
    character = "markus",
    career    = "es_mercenary",
    patches   = {},
    custom_apply = function(saved)
        if not BuffTemplates then return end
        -- Paced Strikes Master attack-speed buff 0.2 -> 0.1; targets 4 -> 3.
        -- Tourney 8F12F3A7BF288DD0/EDDF553A1613BD2F.lua:276-281
        -- (modify_talent_buff_template "markus_mercenary_passive_improved").
        -- Vanilla buff_tweak_data: multiplier 0.2, targets 4
        -- (talent_settings_markus.lua:217-221).
        local t = BuffTemplates.markus_mercenary_passive_improved
        local b = t and t.buffs and t.buffs[1]
        if not b then return end
        saved.merc_improved_multiplier = b.multiplier
        saved.merc_improved_targets    = b.targets
        b.multiplier = 0.1
        b.targets    = 3
    end,
    custom_restore = function(saved)
        local t = BuffTemplates and BuffTemplates.markus_mercenary_passive_improved
        local b = t and t.buffs and t.buffs[1]
        if b then
            if saved.merc_improved_multiplier ~= nil then b.multiplier = saved.merc_improved_multiplier end
            if saved.merc_improved_targets    ~= nil then b.targets    = saved.merc_improved_targets end
        end
        saved.merc_improved_multiplier = nil
        saved.merc_improved_targets    = nil
    end,
},

    trn_es_huntsman = {
    character = "markus",
    career    = "es_huntsman",
    patches   = {},
    custom_apply = function(saved)
        if not BuffTemplates then return end
        -- Crit aura range 5 -> 20.
        -- Tourney EDDF553A1613BD2F.lua:288-290 (modify_talent_buff_template
        -- "markus_huntsman_passive_crit_aura"). Vanilla buff_tweak_data range 5
        -- (talent_settings_markus.lua:14-16); read as buff.range by
        -- activate_buff_on_distance.
        local aura = BuffTemplates.markus_huntsman_passive_crit_aura
        local ab = aura and aura.buffs and aura.buffs[1]
        if ab then
            saved.hunt_crit_aura_range = ab.range
            ab.range = 20
        end
        -- Prowl reload-speed buff -0.4 -> -0.25 (base variant).
        -- Tourney EDDF553A1613BD2F.lua:299-301. Vanilla buffs[1].multiplier =
        -- buff_tweak_data.markus_huntsman_activated_ability.reload_speed_multiplier
        -- = -0.4 (talent_settings_markus.lua:30, 388-398).
        local rs = BuffTemplates.markus_huntsman_activated_ability_increased_reload_speed
        local rsb = rs and rs.buffs and rs.buffs[1]
        if rsb then
            saved.hunt_reload_mult = rsb.multiplier
            rsb.multiplier = -0.25
        end
        -- Prowl reload-speed buff -0.4 -> -0.25 (longer-duration variant).
        -- Tourney EDDF553A1613BD2F.lua:302-304
        -- ("markus_huntsman_activated_ability_increased_reload_speed_duration").
        -- Vanilla -0.4 (talent_settings_markus.lua:538-548).
        local rsd = BuffTemplates.markus_huntsman_activated_ability_increased_reload_speed_duration
        local rsdb = rsd and rsd.buffs and rsd.buffs[1]
        if rsdb then
            saved.hunt_reload_dur_mult = rsdb.multiplier
            rsdb.multiplier = -0.25
        end
    end,
    custom_restore = function(saved)
        local aura = BuffTemplates and BuffTemplates.markus_huntsman_passive_crit_aura
        local ab = aura and aura.buffs and aura.buffs[1]
        if ab and saved.hunt_crit_aura_range ~= nil then ab.range = saved.hunt_crit_aura_range end
        local rs = BuffTemplates and BuffTemplates.markus_huntsman_activated_ability_increased_reload_speed
        local rsb = rs and rs.buffs and rs.buffs[1]
        if rsb and saved.hunt_reload_mult ~= nil then rsb.multiplier = saved.hunt_reload_mult end
        local rsd = BuffTemplates and BuffTemplates.markus_huntsman_activated_ability_increased_reload_speed_duration
        local rsdb = rsd and rsd.buffs and rsd.buffs[1]
        if rsdb and saved.hunt_reload_dur_mult ~= nil then rsdb.multiplier = saved.hunt_reload_dur_mult end
        saved.hunt_crit_aura_range = nil
        saved.hunt_reload_mult     = nil
        saved.hunt_reload_dur_mult = nil
    end,
},

    trn_es_knight = {
    character = "markus",
    career    = "es_knight",
    patches   = {},
    custom_apply = function(saved)
        if not BuffTemplates then return end
        local function snap_set(key, buff_name, field, new_value)
            local t = BuffTemplates[buff_name]
            local b = t and t.buffs and t.buffs[1]
            if not b then return end
            saved[key] = b[field]
            b[field] = new_value
        end
        -- Protective Presence: aura range 5 -> 20 (markus_knight_passive),
        -- aura DR 0.15 -> 0.10 (markus_knight_passive_defence_aura),
        -- increased-range variant range 10 -> 40 (markus_knight_passive_range),
        -- its DR 0.15 -> 0.10 (markus_knight_passive_defence_aura_range).
        -- Tourney 8F12F3A7BF288DD0.lua:4-18. Vanilla buff_tweak_data:
        -- markus_knight_passive.range 5 (talent_settings_markus.lua:94-96),
        -- markus_knight_passive_defence_aura.multiplier -0.15 (103-105),
        -- markus_knight_passive_range.range = passive.range*2 = 10 (1179),
        -- markus_knight_passive_defence_aura_range.multiplier -0.15 (109-111).
        snap_set("fk_passive_range",            "markus_knight_passive",                  "range",      20)
        snap_set("fk_passive_aura_mult",        "markus_knight_passive_defence_aura",     "multiplier", -0.1)
        snap_set("fk_passive_range_range",      "markus_knight_passive_range",            "range",      40)
        snap_set("fk_passive_aura_range_mult",  "markus_knight_passive_defence_aura_range","multiplier", -0.1)
        -- Have At Them aura cluster range 5 -> 20. Tourney 8F12F3A7BF288DD0.lua:
        -- 20-42 (markus_knight_guard_defence / markus_knight_guard /
        -- markus_knight_damage_taken_ally_proximity). Vanilla ranges all 5
        -- (talent_settings_markus.lua:1199,1219,1286); update_funcs Tourney
        -- writes are already the vanilla values, so range is the only live change.
        snap_set("fk_guard_defence_range",      "markus_knight_guard_defence",            "range",      20)
        snap_set("fk_guard_range",              "markus_knight_guard",                    "range",      20)
        snap_set("fk_ally_prox_range",          "markus_knight_damage_taken_ally_proximity","range",    20)
        -- Cooldown-on-damage-taken bonus 0.5 -> 0.35. Tourney EDDF553A1613BD2F.lua:
        -- 522-524. Vanilla buff_tweak_data bonus 0.5 (talent_settings_markus.lua:91-93).
        snap_set("fk_cd_on_dmg_bonus",          "markus_knight_ability_cooldown_on_damage_taken","bonus", 0.35)
        -- Power-on-stagger-elite buff duration 10 -> 15. Tourney EDDF553A:525-527.
        -- Vanilla duration 10 (talent_settings_markus.lua:121-124).
        snap_set("fk_stagger_power_dur",        "markus_knight_power_level_on_stagger_elite_buff","duration", 15)
        -- Attack-speed-on-push buff duration 3 -> 5. Tourney EDDF553A:539-541.
        -- Vanilla duration 3 (talent_settings_markus.lua:129-132).
        snap_set("fk_push_as_dur",              "markus_knight_attack_speed_on_push_buff","duration",   5)
        -- Power-level-impact (stagger power) multiplier 0.35 -> 0.2. Tourney
        -- EDDF553A:581-583. Vanilla multiplier 0.35 (talent_settings_markus.lua:115-117).
        snap_set("fk_power_impact_mult",        "markus_knight_power_level_impact",       "multiplier", 0.2)
        -- Stagger cooldown-regen buff duration 0.5 -> 1.5 (multiplier stays 2).
        -- Tourney EDDF553A:588-592. Vanilla duration 0.5 (talent_settings_markus.lua:125-128).
        snap_set("fk_cooldown_buff_dur",        "markus_knight_cooldown_buff",            "duration",   1.5)
    end,
    custom_restore = function(saved)
        local function restore(key, buff_name, field)
            if saved[key] == nil then return end
            local t = BuffTemplates and BuffTemplates[buff_name]
            local b = t and t.buffs and t.buffs[1]
            if b then b[field] = saved[key] end
            saved[key] = nil
        end
        restore("fk_passive_range",           "markus_knight_passive",                   "range")
        restore("fk_passive_aura_mult",       "markus_knight_passive_defence_aura",      "multiplier")
        restore("fk_passive_range_range",     "markus_knight_passive_range",             "range")
        restore("fk_passive_aura_range_mult", "markus_knight_passive_defence_aura_range","multiplier")
        restore("fk_guard_defence_range",     "markus_knight_guard_defence",             "range")
        restore("fk_guard_range",             "markus_knight_guard",                     "range")
        restore("fk_ally_prox_range",         "markus_knight_damage_taken_ally_proximity","range")
        restore("fk_cd_on_dmg_bonus",         "markus_knight_ability_cooldown_on_damage_taken","bonus")
        restore("fk_stagger_power_dur",       "markus_knight_power_level_on_stagger_elite_buff","duration")
        restore("fk_push_as_dur",             "markus_knight_attack_speed_on_push_buff", "duration")
        restore("fk_power_impact_mult",       "markus_knight_power_level_impact",        "multiplier")
        restore("fk_cooldown_buff_dur",       "markus_knight_cooldown_buff",             "duration")
    end,
},

    trn_es_questingknight = {
    character = "markus",
    career    = "es_questingknight",
    patches   = {},
    custom_apply = function(saved)
        if not BuffTemplates then return end
        -- Crit insta-kill damage threshold x4 -> x3.
        -- Tourney 8F12F3A7BF288DD0.lua:177-179 (modify_talent_buff_template
        -- "markus_questing_knight_crit_can_insta_kill"). Vanilla buff_tweak_data
        -- damage_multiplier 4 (talent_settings_lake_empire_soldier.lua:31-35);
        -- read by check_for_instantly_killing_crit (buff_settings_lake.lua:285).
        local ik = BuffTemplates.markus_questing_knight_crit_can_insta_kill
        local ikb = ik and ik.buffs and ik.buffs[1]
        if ikb then
            saved.gk_instakill_mult = ikb.damage_multiplier
            ikb.damage_multiplier = 3
        end
        -- Kill move-speed buff duration 15 -> 25.
        -- Tourney EDDF553A1613BD2F.lua:594-596
        -- ("markus_questing_knight_ability_buff_on_kill_movement_speed").
        -- Vanilla duration 15 (talent_settings_lake_empire_soldier.lua:62-65).
        local ms = BuffTemplates.markus_questing_knight_ability_buff_on_kill_movement_speed
        local msb = ms and ms.buffs and ms.buffs[1]
        if msb then
            saved.gk_killms_dur = msb.duration
            msb.duration = 25
        end
        -- Delayed health-refund fraction 0.5 -> 0.25.
        -- Tourney EDDF553A1613BD2F.lua:609-611
        -- ("markus_questing_knight_health_refund_over_time"). Vanilla
        -- heal_amount_fraction 0.5 (talent_settings_lake_empire_soldier.lua:45-47);
        -- read by add_heal_percent_of_damage_taken_over_time_buff
        -- (buff_settings_lake.lua:258).
        local hr = BuffTemplates.markus_questing_knight_health_refund_over_time
        local hrb = hr and hr.buffs and hr.buffs[1]
        if hrb then
            saved.gk_healfrac = hrb.heal_amount_fraction
            hrb.heal_amount_fraction = 0.25
        end
    end,
    custom_restore = function(saved)
        local ik = BuffTemplates and BuffTemplates.markus_questing_knight_crit_can_insta_kill
        local ikb = ik and ik.buffs and ik.buffs[1]
        if ikb and saved.gk_instakill_mult ~= nil then ikb.damage_multiplier = saved.gk_instakill_mult end
        local ms = BuffTemplates and BuffTemplates.markus_questing_knight_ability_buff_on_kill_movement_speed
        local msb = ms and ms.buffs and ms.buffs[1]
        if msb and saved.gk_killms_dur ~= nil then msb.duration = saved.gk_killms_dur end
        local hr = BuffTemplates and BuffTemplates.markus_questing_knight_health_refund_over_time
        local hrb = hr and hr.buffs and hr.buffs[1]
        if hrb and saved.gk_healfrac ~= nil then hrb.heal_amount_fraction = saved.gk_healfrac end
        saved.gk_instakill_mult = nil
        saved.gk_killms_dur     = nil
        saved.gk_healfrac       = nil
    end,
},

    trn_dr_ranger = {
        character = "bardin",
        career    = "dr_ranger",
        patches   = {
            -- EDDF553A1613BD2F.lua:620-622 — bardin_ranger_attack_speed multiplier 0.05 -> 0.15
            { buff = "bardin_ranger_attack_speed", field = "multiplier", value = 0.15 },
            -- EDDF553A1613BD2F.lua:753-755 — bardin_ranger_reduced_damage_taken_headshot_buff multiplier -0.3 -> -0.2
            { buff = "bardin_ranger_reduced_damage_taken_headshot_buff", field = "multiplier", value = -0.2 },
            -- EDDF553A1613BD2F.lua:767-770 — bardin_ranger_ability_free_grenade_buff add duration=10 + refresh_durations (vanilla had neither)
            { buff = "bardin_ranger_ability_free_grenade_buff", field = "duration",          value = 10 },
            { buff = "bardin_ranger_ability_free_grenade_buff", field = "refresh_durations", value = true },
        },
        custom_apply = function(saved)
            -- Pure buffs[1] field patches above; nothing outside BuffTemplates to snapshot.
            -- Framework already snapshotted each patched field's old_value (incl. nil) for restore.
            return
        end,
        custom_restore = function(saved)
            -- Framework restores each patched buffs[1] field from its snapshot; nothing extra to undo.
            return
        end,
    },

    trn_dr_ironbreaker = {
        character = "bardin",
        career    = "dr_ironbreaker",
        patches   = {
            -- EDDF553A1613BD2F.lua:790-792 — bardin_ironbreaker_ability_cooldown_on_damage_taken bonus 0.5 -> 0.4
            { buff = "bardin_ironbreaker_ability_cooldown_on_damage_taken", field = "bonus", value = 0.4 },
            -- EDDF553A1613BD2F.lua:908-910 — bardin_ironbreaker_stacking_buff_gromril update_frequency 7 -> 2
            { buff = "bardin_ironbreaker_stacking_buff_gromril", field = "update_frequency", value = 2 },
            -- EDDF553A1613BD2F.lua:911-914 — bardin_ironbreaker_gromril_attack_speed duration 10 -> 15
            { buff = "bardin_ironbreaker_gromril_attack_speed", field = "duration",   value = 15 },
            -- EDDF553A1613BD2F.lua:911-914 — bardin_ironbreaker_gromril_attack_speed multiplier 0.08 -> 0.048
            { buff = "bardin_ironbreaker_gromril_attack_speed", field = "multiplier", value = 0.048 },
        },
        custom_apply = function(saved)
            -- Pure buffs[1] field patches; nothing outside BuffTemplates to snapshot.
            return
        end,
        custom_restore = function(saved)
            -- Framework restores each patched buffs[1] field from its snapshot.
            return
        end,
    },

    trn_dr_slayer = {
        character = "bardin",
        career    = "dr_slayer",
        patches   = {
            -- EDDF553A1613BD2F.lua:1091-1094 — bardin_slayer_push_on_dodge add stat_buff="damage_taken" (vanilla had none)
            { buff = "bardin_slayer_push_on_dodge", field = "stat_buff",  value = "damage_taken" },
            -- EDDF553A1613BD2F.lua:1091-1094 — bardin_slayer_push_on_dodge add multiplier=-0.15 (vanilla had none)
            { buff = "bardin_slayer_push_on_dodge", field = "multiplier", value = -0.15 },
        },
        custom_apply = function(saved)
            -- stat_buff/multiplier were nil in vanilla; framework snapshotted nil for both,
            -- so restore nils them back. Nothing outside BuffTemplates to snapshot.
            return
        end,
        custom_restore = function(saved)
            -- Framework restores stat_buff/multiplier to their snapshotted nil.
            return
        end,
    },

    trn_we_waywatcher = {
    character = "kerillian",
    career    = "we_waywatcher",
    patches   = {},
    custom_apply = function(saved)
        if not BuffTemplates then return end
        local t = BuffTemplates.kerillian_waywatcher_attack_speed_on_ranged_headshot_buff
        local b = t and t.buffs and t.buffs[1]
        if not b then return end
        saved.ww_qs_multiplier = b.multiplier
        saved.ww_qs_duration   = b.duration
        b.multiplier = 0.2
        b.duration   = 10
    end,
    custom_restore = function(saved)
        local t = BuffTemplates and BuffTemplates.kerillian_waywatcher_attack_speed_on_ranged_headshot_buff
        local b = t and t.buffs and t.buffs[1]
        if b then
            if saved.ww_qs_multiplier ~= nil then b.multiplier = saved.ww_qs_multiplier end
            if saved.ww_qs_duration   ~= nil then b.duration   = saved.ww_qs_duration   end
        end
        saved.ww_qs_multiplier, saved.ww_qs_duration = nil, nil
    end,
},

    trn_we_maidenguard = {
    character = "kerillian",
    career    = "we_maidenguard",
    patches   = {},
    custom_apply = function(saved)
        if not BuffTemplates then return end
        local function _b(name) local t = BuffTemplates[name]; return t and t.buffs and t.buffs[1] end
        local aura = _b("kerillian_maidenguard_passive_stamina_regen_aura")
        if aura then saved.mg_aura_range = aura.range; aura.range = 20 end
        local cd = _b("kerillian_maidenguard_power_level_on_unharmed_cooldown")
        if cd then saved.mg_unharmed_cd_duration = cd.duration; cd.duration = 4 end
        local push = _b("kerillian_maidenguard_speed_on_push")
        if push then
            saved.mg_push_msbs = push.max_sub_buff_stacks; saved.mg_push_ata = push.amount_to_add
            push.max_sub_buff_stacks = 3; push.amount_to_add = 3
        end
        local block = _b("kerillian_maidenguard_speed_on_block")
        if block then
            saved.mg_block_msbs = block.max_sub_buff_stacks; saved.mg_block_ata = block.amount_to_add
            block.max_sub_buff_stacks = 3; block.amount_to_add = 3
        end
        local dummy = _b("kerillian_maidenguard_speed_on_block_dummy_buff")
        if dummy then saved.mg_dummy_max_stacks = dummy.max_stacks; dummy.max_stacks = 3 end
        local dodge = _b("kerillian_maidenguard_power_on_dodge")
        if dodge then
            saved.mg_dodge_multiplier = dodge.multiplier; saved.mg_dodge_duration = dodge.duration
            dodge.multiplier = 0.15; dodge.duration = 3.5
        end
        local hp = _b("kerillian_maidenguard_max_health")
        if hp then saved.mg_max_health_multiplier = hp.multiplier; hp.multiplier = 0.2 end
        local ammo = _b("kerillian_maidenguard_max_ammo")
        if ammo then saved.mg_max_ammo_multiplier = ammo.multiplier; ammo.multiplier = 0.7 end
    end,
    custom_restore = function(saved)
        if not BuffTemplates then return end
        local function _b(name) local t = BuffTemplates[name]; return t and t.buffs and t.buffs[1] end
        local aura = _b("kerillian_maidenguard_passive_stamina_regen_aura")
        if aura and saved.mg_aura_range ~= nil then aura.range = saved.mg_aura_range end
        local cd = _b("kerillian_maidenguard_power_level_on_unharmed_cooldown")
        if cd and saved.mg_unharmed_cd_duration ~= nil then cd.duration = saved.mg_unharmed_cd_duration end
        local push = _b("kerillian_maidenguard_speed_on_push")
        if push then
            if saved.mg_push_msbs ~= nil then push.max_sub_buff_stacks = saved.mg_push_msbs end
            if saved.mg_push_ata  ~= nil then push.amount_to_add       = saved.mg_push_ata  end
        end
        local block = _b("kerillian_maidenguard_speed_on_block")
        if block then
            if saved.mg_block_msbs ~= nil then block.max_sub_buff_stacks = saved.mg_block_msbs end
            if saved.mg_block_ata  ~= nil then block.amount_to_add       = saved.mg_block_ata  end
        end
        local dummy = _b("kerillian_maidenguard_speed_on_block_dummy_buff")
        if dummy and saved.mg_dummy_max_stacks ~= nil then dummy.max_stacks = saved.mg_dummy_max_stacks end
        local dodge = _b("kerillian_maidenguard_power_on_dodge")
        if dodge then
            if saved.mg_dodge_multiplier ~= nil then dodge.multiplier = saved.mg_dodge_multiplier end
            if saved.mg_dodge_duration   ~= nil then dodge.duration   = saved.mg_dodge_duration   end
        end
        local hp = _b("kerillian_maidenguard_max_health")
        if hp and saved.mg_max_health_multiplier ~= nil then hp.multiplier = saved.mg_max_health_multiplier end
        local ammo = _b("kerillian_maidenguard_max_ammo")
        if ammo and saved.mg_max_ammo_multiplier ~= nil then ammo.multiplier = saved.mg_max_ammo_multiplier end
        saved.mg_aura_range, saved.mg_unharmed_cd_duration = nil, nil
        saved.mg_push_msbs, saved.mg_push_ata, saved.mg_block_msbs, saved.mg_block_ata = nil, nil, nil, nil
        saved.mg_dummy_max_stacks, saved.mg_dodge_multiplier, saved.mg_dodge_duration = nil, nil, nil
        saved.mg_max_health_multiplier, saved.mg_max_ammo_multiplier = nil, nil
    end,
},

    trn_we_shade = {
    character = "kerillian",
    career    = "we_shade",
    patches   = {},
    custom_apply = function(saved)
        if not BuffTemplates then return end
        local function _b(name) local t = BuffTemplates[name]; return t and t.buffs and t.buffs[1] end
        saved.shade_ult_durations = {}
        local ult_buffs = {
            "kerillian_shade_activated_ability_phasing",
            "kerillian_shade_activated_ability_short_blocker",
            "kerillian_shade_activated_ability",
            "kerillian_shade_activated_ability_restealth",
        }
        for _, name in ipairs(ult_buffs) do
            local b = _b(name)
            if b then
                saved.shade_ult_durations[name] = b.duration
                b.duration = 2.5
            end
        end
        local parry = _b("kerillian_shade_passive_stealth_parry")
        if parry then saved.shade_parry_event = parry.event; parry.event = "on_timed_block_long" end
        local crit = _b("kerillian_shade_increased_critical_strike_damage")
        if crit then saved.shade_crit_multiplier = crit.multiplier; crit.multiplier = 0.8 end
    end,
    custom_restore = function(saved)
        if not BuffTemplates then return end
        local function _b(name) local t = BuffTemplates[name]; return t and t.buffs and t.buffs[1] end
        if saved.shade_ult_durations then
            for name, original in pairs(saved.shade_ult_durations) do
                local b = _b(name)
                if b then b.duration = original end
            end
        end
        local parry = _b("kerillian_shade_passive_stealth_parry")
        if parry and saved.shade_parry_event ~= nil then parry.event = saved.shade_parry_event end
        local crit = _b("kerillian_shade_increased_critical_strike_damage")
        if crit and saved.shade_crit_multiplier ~= nil then crit.multiplier = saved.shade_crit_multiplier end
        saved.shade_ult_durations, saved.shade_parry_event, saved.shade_crit_multiplier = nil, nil, nil
    end,
},

    trn_we_thornsister = {
    character = "kerillian",
    career    = "we_thornsister",
    patches   = {},
    custom_apply = function(saved)
        if not BuffTemplates then return end
        local function _b(name) local t = BuffTemplates[name]; return t and t.buffs and t.buffs[1] end
        local aura = _b("kerillian_thorn_sister_team_buff_aura")
        if aura then saved.thorn_aura_duration = aura.duration; aura.duration = 20 end
        local funnel = _b("kerillian_thorn_sister_passive_temp_health_funnel_aura_buff")
        if funnel then saved.thorn_funnel_multiplier = funnel.multiplier; funnel.multiplier = 0.1 end
    end,
    custom_restore = function(saved)
        if not BuffTemplates then return end
        local function _b(name) local t = BuffTemplates[name]; return t and t.buffs and t.buffs[1] end
        local aura = _b("kerillian_thorn_sister_team_buff_aura")
        if aura and saved.thorn_aura_duration ~= nil then aura.duration = saved.thorn_aura_duration end
        local funnel = _b("kerillian_thorn_sister_passive_temp_health_funnel_aura_buff")
        if funnel and saved.thorn_funnel_multiplier ~= nil then funnel.multiplier = saved.thorn_funnel_multiplier end
        saved.thorn_aura_duration, saved.thorn_funnel_multiplier = nil, nil
    end,
},

    trn_wh_bountyhunter = {
        character = "victor",
        career    = "wh_bountyhunter",
        patches   = {
            { buff = "victor_bountyhunter_activated_ability_railgun_delayed_add", field = "multiplier", value = 0.8 },
            { buff = "victor_bountyhunter_stacking_damage_reduction_on_elite_or_special_kill_buff", field = "max_stacks", value = 20 },
            { buff = "victor_bountyhunter_activated_ability_passive_cooldown_reduction", field = "cooldown", value = 4.5 },
        },
        custom_apply = function(saved)
            -- (d1) Merge the attack-speed proc fields onto the melee-kill template's buffs[1].
            -- Tourney sets buff_to_add + activation_buff + update_func (merge, keeps buff_func/event).
            -- [tourney EDDF553A1613BD2F.lua:1497-1501]
            local tmpl = BuffTemplates and BuffTemplates.victor_bountyhunter_activate_passive_on_melee_kill
            local b1 = tmpl and tmpl.buffs and tmpl.buffs[1]
            if b1 then
                saved.bk_buff_to_add_original    = b1.buff_to_add
                saved.bk_activation_buff_original = b1.activation_buff
                saved.bk_update_func_original     = b1.update_func
                saved.bk_fields_set = true
                b1.buff_to_add    = "victor_bountyhunter_blessed_melee_attack_speed_buff"
                b1.activation_buff = "victor_bountyhunter_blessed_melee_damage_buff"
                b1.update_func     = "activate_buff_on_other_buff"
            end
            -- (d2) Register the new +15% attack-speed buff if missing (stub or unregistered).
            -- [tourney EDDF553A1613BD2F.lua:1502-1506]
            if BuffTemplates and (BuffTemplates.victor_bountyhunter_blessed_melee_attack_speed_buff == nil or BuffTemplates.victor_bountyhunter_blessed_melee_attack_speed_buff._crt_pending) then
                BuffTemplates.victor_bountyhunter_blessed_melee_attack_speed_buff = {
                    buffs = {
                        {
                            name       = "victor_bountyhunter_blessed_melee_attack_speed_buff",
                            max_stacks = 1,
                            multiplier = 0.15,
                            stat_buff  = "attack_speed",
                        },
                    },
                }
                saved.bk_as_buff_created = true
            end
            -- (d3) Make Blessed Kill innate: append the melee-kill proc to the BH passive buffs list.
            -- [tourney 8F12F3A7BF288DD0.lua:144]
            local passive = rawget(_G, "PassiveAbilitySettings")
            local wh2 = passive and passive.wh_2
            if wh2 and wh2.buffs then
                local present = false
                for _, b in ipairs(wh2.buffs) do
                    if b == "victor_bountyhunter_activate_passive_on_melee_kill" then present = true; break end
                end
                if not present then
                    saved.bk_passive_buffs_count = #wh2.buffs
                    table.insert(wh2.buffs, "victor_bountyhunter_activate_passive_on_melee_kill")
                end
            end
        end,
        custom_restore = function(saved)
            local passive = rawget(_G, "PassiveAbilitySettings")
            local wh2 = passive and passive.wh_2
            if wh2 and wh2.buffs and saved.bk_passive_buffs_count then
                while #wh2.buffs > saved.bk_passive_buffs_count do table.remove(wh2.buffs) end
            end
            local tmpl = BuffTemplates and BuffTemplates.victor_bountyhunter_activate_passive_on_melee_kill
            local b1 = tmpl and tmpl.buffs and tmpl.buffs[1]
            if b1 and saved.bk_fields_set then
                b1.buff_to_add    = saved.bk_buff_to_add_original
                b1.activation_buff = saved.bk_activation_buff_original
                b1.update_func     = saved.bk_update_func_original
            end
            if saved.bk_as_buff_created and BuffTemplates then
                BuffTemplates.victor_bountyhunter_blessed_melee_attack_speed_buff = _crt_make_stub()
            end
            saved.bk_passive_buffs_count = nil
            saved.bk_buff_to_add_original, saved.bk_activation_buff_original, saved.bk_update_func_original = nil, nil, nil
            saved.bk_fields_set = nil
            saved.bk_as_buff_created = nil
        end,
    },

    trn_wh_zealot = {
        character = "victor",
        career    = "wh_zealot",
        patches   = {
            { buff = "victor_zealot_power", field = "multiplier", value = 0.2 },
            { buff = "victor_zealot_power", field = "stat_buff",  value = "power_level_melee" },
        },
    },

    trn_wh_priest = {
        character = "victor",
        career    = "wh_priest",
        -- issue 425: the WP 5-2 aura driver (activate_buff_on_distance,
        -- buff_function_templates.lua:2759) grants buff_to_add as a
        -- SERVER-CONTROLLED buff (:2801) -- rpc_add_buff broadcast + hot-join
        -- replay -- and this patch points it at a MOD-registered name that a
        -- non-crt peer cannot decode. Gated on peer parity (engine below), and
        -- the driver is swapped to the crt wire-safe wrapper (registered in
        -- career_tweaker_balance.lua) so a live aura buff consults the live
        -- parity check per tick and strips its own stacks on degrade.
        network_unsafe = true,
        patches   = {
            { buff = "victor_priest_5_2", field = "buff_to_add", value = "victor_priest_5_2_speed_buff" },
            { buff = "victor_priest_5_2", field = "update_func", value = "crt_wire_safe_distance_aura_driver" },
        },
        custom_apply = function(saved)
            -- Register the new +10% movement-speed aura buff if missing (stub or unregistered).
            -- [tourney EDDF553A1613BD2F.lua:1616-1624]
            if BuffTemplates and (BuffTemplates.victor_priest_5_2_speed_buff == nil or BuffTemplates.victor_priest_5_2_speed_buff._crt_pending) then
                BuffTemplates.victor_priest_5_2_speed_buff = {
                    buffs = {
                        {
                            name             = "victor_priest_5_2_speed_buff",
                            max_stacks       = 1,
                            multiplier       = 1.1,
                            apply_buff_func  = "apply_movement_buff",
                            remove_buff_func = "remove_movement_buff",
                            path_to_movement_setting_to_modify = { "move_speed" },
                        },
                    },
                }
                saved.priest_speed_buff_created = true
            end
        end,
        custom_restore = function(saved)
            if saved.priest_speed_buff_created and BuffTemplates then
                BuffTemplates.victor_priest_5_2_speed_buff = _crt_make_stub()
            end
            saved.priest_speed_buff_created = nil
        end,
    },

    trn_bw_adept = {
    character = "sienna",
    career    = "bw_adept",
    patches   = {
        -- Famished Flames: burn DoT 100%->150%, non-burn -15%->-30%
        -- src: EDDF553A1613BD2F.lua:1673-1677  (vanilla talent_settings_sienna.lua:136-141)
        { buff = "sienna_adept_increased_burn_damage",                 field = "multiplier", value = 1.5  },
        { buff = "sienna_adept_reduced_non_burn_damage",               field = "multiplier", value = -0.3 },
        -- Ignite DR: vanilla -8%/stack max 3 -> -5%/stack max 4
        -- src: EDDF553A1613BD2F.lua:1692-1694  (vanilla talent_settings_sienna.lua:127-131)
        { buff = "sienna_adept_damage_reduction_on_ignited_enemy_buff", field = "max_stacks", value = 4    },
        { buff = "sienna_adept_damage_reduction_on_ignited_enemy_buff", field = "multiplier", value = -0.05 },
        -- Fires from Ash: cooldown refund 3%->2% per burning enemy killed
        -- src: EDDF553A1613BD2F.lua:1706-1707  (vanilla talent_settings_sienna.lua:132-135)
        { buff = "sienna_adept_cooldown_reduction_on_burning_enemy_killed", field = "cooldown_reduction", value = 0.02 },
        -- Burning Vigour: melee AS buff trigger threshold 4 -> 1 target
        -- src: EDDF553A1613BD2F.lua:1722-1723  (vanilla talent_settings_sienna.lua:111-112)
        { buff = "sienna_adept_attack_speed_on_enemies_hit",          field = "required_targets", value = 1 },
    },
    custom_apply = function(saved)
        if not BuffTemplates then return end
        saved.trn_bw_adept_fields = {}
        local function snap(buff_name, field, value)
            local t = BuffTemplates[buff_name]
            local b = t and t.buffs and t.buffs[1]
            if not b then return end
            saved.trn_bw_adept_fields[#saved.trn_bw_adept_fields + 1] = { buff = buff_name, field = field, old = b[field] }
            b[field] = value
        end
        snap("sienna_adept_increased_burn_damage",                  "multiplier",       1.5)
        snap("sienna_adept_reduced_non_burn_damage",                "multiplier",      -0.3)
        snap("sienna_adept_damage_reduction_on_ignited_enemy_buff", "max_stacks",       4)
        snap("sienna_adept_damage_reduction_on_ignited_enemy_buff", "multiplier",      -0.05)
        snap("sienna_adept_cooldown_reduction_on_burning_enemy_killed", "cooldown_reduction", 0.02)
        snap("sienna_adept_attack_speed_on_enemies_hit",            "required_targets", 1)
    end,
    custom_restore = function(saved)
        if not saved.trn_bw_adept_fields then return end
        for i = #saved.trn_bw_adept_fields, 1, -1 do
            local e = saved.trn_bw_adept_fields[i]
            local t = BuffTemplates and BuffTemplates[e.buff]
            if t and t.buffs and t.buffs[1] then
                t.buffs[1][e.field] = e.old
            end
        end
        saved.trn_bw_adept_fields = nil
    end,
},

    trn_bw_scholar = {
    character = "sienna",
    career    = "bw_scholar",
    patches   = {
        -- Martial Study attack-speed talent 5%->10%
        -- src: EDDF553A1613BD2F.lua:1741-1742  (vanilla talent_settings_sienna.lua:43-45)
        { buff = "sienna_scholar_increased_attack_speed", field = "multiplier", value = 0.1 },
    },
    custom_apply = function(saved)
        if not BuffTemplates then return end
        local t = BuffTemplates.sienna_scholar_increased_attack_speed
        local b = t and t.buffs and t.buffs[1]
        if not b then return end
        saved.trn_bw_scholar_as_old = b.multiplier
        b.multiplier = 0.1
    end,
    custom_restore = function(saved)
        if saved.trn_bw_scholar_as_old == nil then return end
        local t = BuffTemplates and BuffTemplates.sienna_scholar_increased_attack_speed
        local b = t and t.buffs and t.buffs[1]
        if b then b.multiplier = saved.trn_bw_scholar_as_old end
        saved.trn_bw_scholar_as_old = nil
    end,
},

    trn_bw_necromancer = {
    character = "sienna",
    career    = "bw_necromancer",
    patches   = {
        -- Row-2 spell-cast buff: power_level_ranged -> increased_weapon_damage_ranged
        -- (stat_buff TYPE swap; multiplier 0.05 / dur 6 / max_stacks 5 unchanged)
        -- src: EDDF553A1613BD2F.lua:1864-1865  (vanilla talent_settings_shovel.lua:184-191)
        { buff = "sienna_necromancer_2_2_buff", field = "stat_buff", value = "increased_weapon_damage_ranged" },
        -- Crit-cleave talent: drop +25% crit power bonus (keep unlimited-cleave perk)
        -- src: EDDF553A1613BD2F.lua:1872-1873  (vanilla talent_settings_shovel.lua:32-34, 193-201)
        { buff = "sienna_necromancer_2_3", field = "multiplier", value = 0 },
        -- Cursed Blood crit-burst: propagation 25%->10% of damage dealt
        -- src: EDDF553A1613BD2F.lua:1972-1973  (vanilla talent_settings_shovel.lua:203-211; proc buff_settings_shovel.lua:1068 reads template.propagation_multiplier)
        { buff = "sienna_necromancer_4_1_cursed_blood", field = "propagation_multiplier", value = 0.1 },
    },
    custom_apply = function(saved)
        if not BuffTemplates then return end
        saved.trn_bw_necro_fields = {}
        local function snap(buff_name, field, value)
            local t = BuffTemplates[buff_name]
            local b = t and t.buffs and t.buffs[1]
            if not b then return end
            saved.trn_bw_necro_fields[#saved.trn_bw_necro_fields + 1] = { buff = buff_name, field = field, old = b[field] }
            b[field] = value
        end
        snap("sienna_necromancer_2_2_buff",        "stat_buff",              "increased_weapon_damage_ranged")
        snap("sienna_necromancer_2_3",             "multiplier",             0)
        snap("sienna_necromancer_4_1_cursed_blood", "propagation_multiplier", 0.1)
    end,
    custom_restore = function(saved)
        if not saved.trn_bw_necro_fields then return end
        for i = #saved.trn_bw_necro_fields, 1, -1 do
            local e = saved.trn_bw_necro_fields[i]
            local t = BuffTemplates and BuffTemplates[e.buff]
            if t and t.buffs and t.buffs[1] then
                t.buffs[1][e.field] = e.old
            end
        end
        saved.trn_bw_necro_fields = nil
    end,
},
}

-- ============================================================
-- Field-patch apply/restore engine (mirrors career_tweaker_balance.lua)
-- ============================================================
local _originals = {}

local function apply_tourney_mods()
    if not BuffTemplates then return end

    -- restore everything first, then re-apply only the ON (and non-conflicted) ones
    for setting_id, saved in pairs(_originals) do
        local def = TOURNEY_MODS[setting_id]
        if def and def.custom_restore then def.custom_restore(saved) end
        for _, entry in ipairs(saved) do
            local template = BuffTemplates[entry.buff]
            if template and template.buffs and template.buffs[1] then
                template.buffs[1][entry.field] = entry.old_value
            end
        end
    end
    _originals = {}

    -- issue 425 peer-parity gate, same contract as career_tweaker_balance.lua:
    -- entries tagged network_unsafe only apply while the beacon's settled state
    -- is enabled (solo counts as parity). Issue 506: read pp:applied_state()
    -- directly now that the shared lib commits _applied before firing the gate
    -- callbacks -- the old mod._crt_parity_settled_enabled mirror flag is gone.
    -- Saved settings are never overwritten.
    local pp = mod._crt_peer_parity
    local parity_ok = (pp ~= nil and pp:applied_state() == "enabled")

    for setting_id, def in pairs(TOURNEY_MODS) do
        if mod:get(setting_id) and not _conflict_active(setting_id) then
            if def.network_unsafe and not parity_ok then
                pcall(printf, "[crt:425] parity gate: tourney entry %s held at vanilla (a lobby peer lacks crt)", setting_id)
            else
                local saved = {}
                for _, patch in ipairs(def.patches) do
                    local template = BuffTemplates[patch.buff]
                    if template and template.buffs and template.buffs[1] then
                        saved[#saved + 1] = {
                            buff      = patch.buff,
                            field     = patch.field,
                            old_value = template.buffs[1][patch.field],
                        }
                        template.buffs[1][patch.field] = patch.value
                    end
                end
                if def.custom_apply then def.custom_apply(saved) end
                _originals[setting_id] = saved
            end
        end
    end
end

local function restore_all_tourney_mods()
    if not BuffTemplates then return end
    for setting_id, saved in pairs(_originals) do
        local def = TOURNEY_MODS[setting_id]
        if def and def.custom_restore then def.custom_restore(saved) end
        for _, entry in ipairs(saved) do
            local template = BuffTemplates[entry.buff]
            if template and template.buffs and template.buffs[1] then
                template.buffs[1][entry.field] = entry.old_value
            end
        end
    end
    _originals = {}
end

local function get_active_count()
    local count = 0
    for setting_id, _ in pairs(TOURNEY_MODS) do
        if mod:get(setting_id) then count = count + 1 end
    end
    return count
end

return {
    TOURNEY_MODS = TOURNEY_MODS,
    TOGGLE_IDS   = (function() local t = {}; for id in pairs(TOURNEY_MODS) do t[#t+1] = id end; return t end)(),
    apply        = apply_tourney_mods,
    restore      = restore_all_tourney_mods,
    active_count = get_active_count,
}
