-- Behavior-neutral early balance catalogue extracted from career_tweaker_balance.lua.
-- Built through the bounded catalogue composition owner; no hooks or lifecycle callbacks.

local function build(ctx)
    local mod = assert(ctx.mod, "crt early catalog mod required")
    local _crt_make_stub = assert(ctx.make_stub, "crt early catalog make_stub required")
    local _crt_ensure_wire_safe_funcs = assert(ctx.ensure_wire_safe_funcs, "crt early catalog wire helper required")
    local _MIN_THP_ON_KILL = assert(ctx.min_thp_on_kill, "crt early catalog THP floor required")

-- ============================================================
-- Helper: stat-buff "double the small percent" reworks
-- ============================================================
-- The pattern across multiple talents is: a career-specific buff template
-- with a single sub-buff whose value is sourced from `buff_tweak_data.<name>`
-- and merged in at game-init via BuffUtils.apply_buff_tweak_data. The talent
-- tooltip's description_values[1].value is statically frozen on the talent
-- entry at the same init pass. To swap a 5% talent to 10%:
--   1. patch BuffTemplates[talent_name].buffs[1][buff_field] (runtime effect)
--   2. rewrite Talents[hero][id].description_values[1].value (tooltip text)
--
-- This builder factors both into a {patches, custom_apply, custom_restore}
-- triple compatible with the apply/restore engine below. Assumes the buff
-- template name matches the talent's `name` (true for victor_zealot_power,
-- bardin_ranger_attack_speed, kerillian_maidenguard_crit_chance — verify
-- before adding a new entry).
local function _build_stat_buff_rework(talent_name, buff_field, new_value)
    return {
        patches = {
            { buff = talent_name, field = buff_field, value = new_value },
        },
        custom_apply = function(saved)
            if not Talents or not TalentIDLookup then return end
            local lookup = TalentIDLookup[talent_name]
            if not lookup then return end
            local hero_talents = Talents[lookup.hero_name]
            local talent = hero_talents and hero_talents[lookup.talent_id]
            local dv = talent and talent.description_values and talent.description_values[1]
            if not dv then return end
            saved.tooltip_original = dv.value
            dv.value = new_value
        end,
        custom_restore = function(saved)
            if saved.tooltip_original == nil then return end
            if not Talents or not TalentIDLookup then return end
            local lookup = TalentIDLookup[talent_name]
            if not lookup then return end
            local hero_talents = Talents[lookup.hero_name]
            local talent = hero_talents and hero_talents[lookup.talent_id]
            local dv = talent and talent.description_values and talent.description_values[1]
            if not dv then return end
            dv.value = saved.tooltip_original
            saved.tooltip_original = nil
        end,
    }
end

local function _focused_spirit_talent()
    if not Talents or not TalentIDLookup then return nil end
    local lookup = TalentIDLookup.kerillian_maidenguard_power_level_on_unharmed
    local hero_talents = lookup and Talents[lookup.hero_name]
    return hero_talents and hero_talents[lookup.talent_id]
end

local BALANCE_MODS = {
    -- Waystalker: Serrated Shots works on EVERY arrow type.
    -- Serrated Shots (talent kerillian_waywatcher_critical_bleed, perk
    -- "kerillian_critical_bleed_dot") makes critical ranged hits bleed. The
    -- bleed is gated in damage_utils.lua:3698:
    --   has_perk("kerillian_critical_bleed_dot")
    --     and damage_profile.charge_value == "projectile"
    --     and not has_perk("kerillian_critical_bleed_dot_disable")
    -- EVERY Kerillian arrow damage profile uses charge_value="projectile"
    -- (arrow_carbine / arrow_sniper / *_shortbow / *_trueflight -- verified in
    -- damage_profile_templates.lua), so the ONLY thing that disables the bleed by
    -- "arrow type" is the disable perk, which Hagbane (shortbows_hagbane.lua:301-303
    -- server_buffs) and the Chaos Wastes we_deus_01 bow grant via the buff
    -- "we_deus_01_kerillian_critical_bleed_dot_disable" (morris_buff_settings.lua:6332
    -- -- its ONLY effect is that one perk). Clearing that buff's perks list
    -- neutralizes the disable, so Serrated Shots also applies on Hagbane /
    -- we_deus_01. Takes effect on next weapon equip / mission load.
    rework_we_waywatcher_serrated_shots_all_arrows = {
        character = "kerillian",
        patches = {
            { buff = "we_deus_01_kerillian_critical_bleed_dot_disable", field = "perks", value = {} },
        },
    },
    rework_wh_zealot_smite_random_crits = {
        character = "victor",
        career    = "wh_zealot",
        patches   = {},
    },
    -- #447 Flagellation is implemented by _crt_flagellation.lua. Keep an
    -- empty owner entry here so the native rework engine and #445's Ensrick
    -- family master treat the hook-owned toggle as part of the live catalog.
    rework_wh_zealot_flagellation = {
        character = "victor",
        career    = "wh_zealot",
        patches   = {},
    },
    -- Zealot's row-1 +5% power talent (victor_zealot_power, multiplier 0.05).
    -- Career-specific template — patch doesn't bleed into other careers'
    -- equivalents.
    rework_wh_zealot_power_5_to_10 = _build_stat_buff_rework("victor_zealot_power", "multiplier", 0.10),
    -- Issue #999: vanilla Feel Nothing has max_stacks=1 but omits
    -- refresh_durations. BuffExtension therefore rejects a second application
    -- while the first five-second buff is active without moving its end time.
    -- This opt-in patch uses the engine's native refresh path; no replacement
    -- buff, RPC, timer, or per-frame hook is needed.
    rework_wh_zealot_feel_nothing_refresh = {
        character = "victor",
        career = "wh_zealot",
        patches = {
            { buff = "victor_zealot_activated_ability_ignore_death", field = "refresh_durations", value = true },
        },
    },
    -- Ranger Veteran's row-2 +5% attack speed talent
    -- (bardin_ranger_attack_speed, multiplier 0.05). Career-specific.
    rework_dr_ranger_attack_speed_5_to_10 = _build_stat_buff_rework("bardin_ranger_attack_speed", "multiplier", 0.10),
    -- Ranger Veteran ale (#366): vanilla gives both the damage-reduction and
    -- attack-speed sub-buffs `refresh_durations = true`. BuffExtension then
    -- rewrites every existing stack's start/end time before adding a new stack
    -- (buff_extension.lua:520-533), making all stacks expire together. False
    -- leaves each application on its own authored 300-second clock.
    rework_dr_ranger_ale_independent_decay = {
        character = "bardin",
        career = "dr_ranger",
        patches = {
            { buff = "bardin_survival_ale_buff", sub_index = 1, field = "refresh_durations", value = false },
            { buff = "bardin_survival_ale_buff", sub_index = 2, field = "refresh_durations", value = false },
        },
        custom_apply = function()
            pcall(printf, "[crt:366] applied independent 300-second timers to 2 Ranger ale sub-buffs")
        end,
    },
    -- Ranger Veteran ale (#367): WeaponUnitExtension divides both action
    -- completion and the 1P/3P animation by `anim_time_scale`
    -- (weapon_unit_extension.lua:486-489, 580-600). The stock action has
    -- total_time=1.9 and no authored scale. Deriving the scale as stock / 0.75
    -- makes the complete drink last 0.75 seconds without letting gameplay
    -- finish ahead of the visible animation. The standard buff/RPC path is
    -- untouched.
    rework_dr_ranger_ale_one_second_drink = {
        character = "bardin",
        career = "dr_ranger",
        patches = {},
        custom_apply = function(saved)
            local template = WeaponTemplates and WeaponTemplates.bardin_survival_ale
            local action = template and template.actions and template.actions.action_one
                and template.actions.action_one.default
            local stock_duration = action and tonumber(action.total_time)
            local target_duration = 0.75
            if stock_duration ~= 1.9 then return end
            saved.ale_anim_time_scale_had_value = action.anim_time_scale ~= nil
            saved.ale_anim_time_scale_original = action.anim_time_scale
            action.anim_time_scale = stock_duration / target_duration
            pcall(printf,
                "[crt:367] applied Ranger ale speed: stock=%.2fs target=%.2fs anim_time_scale=%.6f",
                stock_duration, target_duration, action.anim_time_scale)
        end,
        custom_restore = function(saved)
            local template = WeaponTemplates and WeaponTemplates.bardin_survival_ale
            local action = template and template.actions and template.actions.action_one
                and template.actions.action_one.default
            if not action or saved.ale_anim_time_scale_had_value == nil then return end
            action.anim_time_scale = saved.ale_anim_time_scale_had_value
                and saved.ale_anim_time_scale_original or nil
            saved.ale_anim_time_scale_had_value = nil
            saved.ale_anim_time_scale_original = nil
        end,
    },
    -- Ranger Veteran's base HP pool: vanilla 100 → 125 (+25). Patches
    -- `CareerSettings.dr_ranger.attributes.max_hp`, the table that
    -- `PlayerUnitHealthExtension._get_base_max_health` reads via
    -- `SPProfiles[profile].careers[index].attributes.max_hp` — same table
    -- reference (SPProfiles.dwarf_ranger.careers entries are direct refs to
    -- CareerSettings.dr_* — see sp_profiles.lua:163). Takes effect on the
    -- next mission load / hero respawn (max health is recalculated in
    -- `PlayerUnitHealthExtension.init`); doesn't retroactively bump an
    -- already-spawned Ranger's max in the current mission.
    rework_dr_ranger_base_hp_plus_25 = {
        character = "bardin",
        career    = "dr_ranger",
        patches   = {},
        custom_apply = function(saved)
            local cs = CareerSettings and CareerSettings.dr_ranger
            local attrs = cs and cs.attributes
            if not attrs or type(attrs.max_hp) ~= "number" then return end
            saved.ranger_max_hp_original = attrs.max_hp
            attrs.max_hp = attrs.max_hp + 25
        end,
        custom_restore = function(saved)
            if saved.ranger_max_hp_original == nil then return end
            local cs = CareerSettings and CareerSettings.dr_ranger
            local attrs = cs and cs.attributes
            if not attrs then return end
            attrs.max_hp = saved.ranger_max_hp_original
            saved.ranger_max_hp_original = nil
        end,
    },
    -- Handmaiden's row-2 +5% crit chance talent
    -- (kerillian_maidenguard_crit_chance, bonus 0.05). Career-specific.
    -- Buff field is `bonus` not `multiplier` — critical_strike_chance stat_buff
    -- consumes bonus additively at the buff_extension level.
    rework_we_maidenguard_crit_chance_5_to_10 = _build_stat_buff_rework("kerillian_maidenguard_crit_chance", "bonus", 0.10),
    -- Focused Spirit (#472): start on the vanilla 10-second cooldown, then add
    -- one 5% power stack per completed no-damage window (max five). The proc
    -- wrapper / one-stack removal live in career_tweaker_armor_overcharge.lua;
    -- these reversible patches only shape the vanilla buff and talent entry.
    rework_we_maidenguard_focused_spirit_stacks = {
        character = "kerillian",
        career = "we_maidenguard",
        patches = {
            { buff = "kerillian_maidenguard_power_level_on_unharmed", field = "multiplier", value = 0.05 },
            { buff = "kerillian_maidenguard_power_level_on_unharmed", field = "max_stacks", value = 5 },
            { buff = "kerillian_maidenguard_power_level_on_unharmed", field = "remove_on_proc", value = false },
            { buff = "kerillian_maidenguard_power_level_on_unharmed", field = "apply_buff_func", value = "crt_focused_spirit_arm_growth" },
        },
        custom_apply = function(saved)
            local talent = _focused_spirit_talent()
            if not talent then return end
            saved.focused_talent_buff_original = talent.buffs and talent.buffs[1]
            saved.focused_talent_description_original = talent.description
            saved.focused_talent_description_values_original = talent.description_values
            if talent.buffs then
                talent.buffs[1] = "kerillian_maidenguard_power_level_on_unharmed_cooldown"
            end
            talent.description = "crt_kerillian_maidenguard_focused_spirit_stacks_desc"
            talent.description_values = {}
        end,
        custom_restore = function(saved)
            local talent = _focused_spirit_talent()
            if not talent then return end
            if talent.buffs and saved.focused_talent_buff_original ~= nil then
                talent.buffs[1] = saved.focused_talent_buff_original
            end
            if saved.focused_talent_description_original ~= nil then
                talent.description = saved.focused_talent_description_original
                talent.description_values = saved.focused_talent_description_values_original
            end
            saved.focused_talent_buff_original = nil
            saved.focused_talent_description_original = nil
            saved.focused_talent_description_values_original = nil
        end,
    },
    -- Dance of Blades (#473): vanilla `kerillian_maidenguard_versatile_dodge`
    -- grants its power reward on a non-blocking dodge. Replace that branch with
    -- one +2% damage / +2% damage-taken pair per hostile hit, up to 15 independently
    -- expiring two-second stacks, while preserving the native blocking-dodge
    -- distance/speed buffs. The server-authoritative stack add uses rpc_add_buff,
    -- so peer parity is mandatory and the live proc wrapper remains the final
    -- send gate.
    rework_we_maidenguard_dance_of_blades = {
        character = "kerillian",
        career = "we_maidenguard",
        network_unsafe = true,
        patches = {},
        custom_apply = function(saved)
            if not BuffTemplates or not Talents or not TalentIDLookup then return end
            local policy = mod._crt.dance_of_blades
            if type(policy) ~= "table" or type(policy.templates) ~= "function" then return end
            _crt_ensure_wire_safe_funcs()
            local templates = policy.templates()
            saved.dance_created_names = {}
            for _, name in ipairs({ policy.dodge_buff, policy.proc_buff, policy.stack_buff }) do
                local existing = rawget(BuffTemplates, name)
                if existing == nil or existing._crt_pending then
                    BuffTemplates[name] = templates[name]
                    saved.dance_created_names[#saved.dance_created_names + 1] = name
                end
            end
            local lookup = TalentIDLookup.kerillian_maidenguard_versatile_dodge
            local talent = lookup and Talents[lookup.hero_name]
                and Talents[lookup.hero_name][lookup.talent_id]
            if talent and talent.buffs then
                saved.dance_talent_buffs_original = {}
                for i = 1, #talent.buffs do
                    saved.dance_talent_buffs_original[i] = talent.buffs[i]
                end
                talent.buffs = { policy.dodge_buff, policy.proc_buff }
            end
            pcall(printf, "[crt:473] Dance of Blades applied: damage=2%% vulnerability=2%% stacks=15 duration=2s independent=true writer=server buckets=damage/damage_taken")
        end,
        custom_restore = function(saved)
            local policy = mod._crt.dance_of_blades
            local lookup = TalentIDLookup and TalentIDLookup.kerillian_maidenguard_versatile_dodge
            local talent = lookup and Talents and Talents[lookup.hero_name]
                and Talents[lookup.hero_name][lookup.talent_id]
            if talent and saved.dance_talent_buffs_original then
                talent.buffs = saved.dance_talent_buffs_original
            end
            if BuffTemplates and saved.dance_created_names then
                for _, name in ipairs(saved.dance_created_names) do
                    BuffTemplates[name] = _crt_make_stub()
                end
            end
            saved.dance_talent_buffs_original = nil
            saved.dance_created_names = nil
        end,
    },
    rework_es_mercenary_hellborgs_tutelage = {
        character = "markus",
        career    = "es_mercenary",
        patches   = {},
    },
    -- Huntsman's passive +5% crit aura (`markus_huntsman_passive_crit_aura`):
    -- the buff is applied to the Huntsman on spawn with `range = 5`, and
    -- `activate_buff_on_distance` (buff_function_templates.lua:2759) tests
    -- `distance_squared <= range * range` every tick to decide which allies get
    -- the +5% crit chance buff. Patching the runtime template field to
    -- math.huge makes `range_squared` infinite — every ally on the side is
    -- always inside the aura. Re-application happens on the next mission load /
    -- hero respawn, since the buff itself is added at career-passive-init time.
    -- No tooltip mutation: the talent has no description_values entry that
    -- displays the 5m distance number, so there's nothing to rewrite.
    rework_es_huntsman_crit_aura_unlimited_range = {
        character = "markus",
        career    = "es_huntsman",
        patches   = {
            { buff = "markus_huntsman_passive_crit_aura", field = "range", value = math.huge },
        },
    },
    rework_wh_captain_parry_window = {
        character = "victor",
        career    = "wh_captain",
        patches   = {},
    },
    -- Double-Shotted (victor_bountyhunter_activated_ability_railgun): the
    -- talent's runtime effect is gated by the buff template's `multiplier`
    -- field on `victor_bountyhunter_activated_ability_railgun_delayed_add`
    -- (consumed by buff_function_templates.victor_bountyhunter_activated_ability_railgun_delayed,
    -- which calls career_extension:reduce_activated_ability_cooldown_percent(buff.multiplier)).
    -- Patching that template field 0.6 → 0.8 lifts the refund from 60% to 80%.
    --
    -- The displayed "60%" in the inventory talent tooltip is sourced from
    -- Talents.victor[talent_id].description_values[1].value (set at game-init
    -- from `buff_tweak_data.victor_bountyhunter_activated_ability_railgun.multiplier`,
    -- so by the time mods run that value is already frozen on the talent entry).
    -- The custom_apply hook walks TalentIDLookup to find the talent's table
    -- and rewrites the description_values entry in place; custom_restore puts
    -- it back. The tooltip refresh isn't instant — players need to close and
    -- re-enter the talent panel after toggling, same as Hellborg's Tutelage.
    rework_wh_bountyhunter_double_shotted_80 = {
        character = "victor",
        career    = "wh_bountyhunter",
        patches   = {
            { buff = "victor_bountyhunter_activated_ability_railgun_delayed_add", field = "multiplier", value = 0.8 },
        },
        custom_apply = function(saved)
            if not Talents or not TalentIDLookup then return end
            local lookup = TalentIDLookup["victor_bountyhunter_activated_ability_railgun"]
            if not lookup then return end
            local hero_talents = Talents[lookup.hero_name]
            local talent = hero_talents and hero_talents[lookup.talent_id]
            local dv = talent and talent.description_values and talent.description_values[1]
            if not dv then return end
            saved.double_shotted_tooltip_original = dv.value
            dv.value = 0.8
        end,
        custom_restore = function(saved)
            if saved.double_shotted_tooltip_original == nil then return end
            if not Talents or not TalentIDLookup then return end
            local lookup = TalentIDLookup["victor_bountyhunter_activated_ability_railgun"]
            if not lookup then return end
            local hero_talents = Talents[lookup.hero_name]
            local talent = hero_talents and hero_talents[lookup.talent_id]
            local dv = talent and talent.description_values and talent.description_values[1]
            if not dv then return end
            dv.value = saved.double_shotted_tooltip_original
            saved.double_shotted_tooltip_original = nil
        end,
    },
    -- Stagger THP rework: +50% per-target THP (base_value 1 -> 1.5) and caps
    -- the per-swing target count at 3 instead of 5. Light/medium/heavy stagger
    -- heal 0.375 / 1.5 / 3 THP per target; a perfect heavy swing across 3
    -- enemies caps at 9 THP, a typical medium swing across 3 caps at 4.5 THP.
    -- Trades the vanilla horde-feast (5 medium staggers = 5 THP) for a
    -- smaller-but-richer payout that also rewards light/heavy stagger more
    -- meaningfully without ballooning into the OP territory of the +100% rework.
    rework_general_stagger_thp = {
        character = "any",
        career    = "any (Heal-on-Stagger talents)",
        patches   = {
            { buff = "thp_tank", field = "base_value",  value = 1.5 },
            { buff = "thp_tank", field = "max_targets", value = 3 },
        },
    },
    -- Minimum THP-on-kill floor: clamps every breed's bloodlust_health (the
    -- per-enemy THP-on-kill amount used by Heal-on-Kill traits, Bloodlust
    -- talents, and the Warrior Priest aftershock heal) to at least
    -- _MIN_THP_ON_KILL. Vanilla slaves/hordes drop 0..1 THP which feels
    -- worthless; flooring at 1 gives any trash kill a meaningful payout
    -- without touching elites/specials/monsters. Each breed file copies its
    -- number out of BreedTweaks.bloodlust_health at game-load time
    -- (e.g. breed_chaos_warrior.lua:134), so we mutate breed tables directly.
    -- Snapshot per breed_name → restored on disable / re-toggle.
    rework_general_thp_kill_minimum = {
        character = "any",
        career    = "any (THP-on-kill traits/talents)",
        patches   = {},
        custom_apply = function(saved)
            if not Breeds then return end
            local floor = _MIN_THP_ON_KILL
            saved.breed_thp_originals = {}
            for breed_name, breed in pairs(Breeds) do
                local v = breed and breed.bloodlust_health
                if type(v) == "number" and v < floor then
                    saved.breed_thp_originals[breed_name] = v
                    breed.bloodlust_health = floor
                end
            end
        end,
        custom_restore = function(saved)
            if not Breeds or not saved.breed_thp_originals then return end
            for breed_name, original in pairs(saved.breed_thp_originals) do
                local breed = Breeds[breed_name]
                if breed then
                    breed.bloodlust_health = original
                end
            end
            saved.breed_thp_originals = nil
        end,
    },

    -- ============================================================
    -- Shade: Hungry Wind (level 30) — bigger / longer
    -- ============================================================
    -- Talent `kerillian_shade_activated_ability_phasing` grants a post-stealth
    -- buff: vanilla +10% move-speed + +15% power for 10s. Rework: +20% / +20%
    -- / 20s. Three buff templates carry the values, all sourced from
    -- buff_tweak_data and merged into buffs[1] at boot
    -- (talent_settings_kerillian.lua:750-774, buff_utils.lua:13-21):
    --   * kerillian_shade_movespeed_buff   — multiplier 1.1, duration 10
    --   * kerillian_shade_power_buff       — multiplier 0.15, duration 10
    --   * kerillian_shade_phasing_buff     — duration 10 (noclip wrapper)
    -- Each gets a buffs[1] field patch via the standard engine. Tooltip values
    -- live in `Talents.wood_elf[<id>].description_values[1..3]` and need a
    -- custom_apply rewrite — they're frozen at game-init from buff_tweak_data
    -- (lines 1770-1782).
    rework_we_shade_hungry_wind_buffed = {
        character = "kerillian",
        career    = "we_shade",
        patches   = {
            { buff = "kerillian_shade_movespeed_buff", field = "multiplier", value = 1.2 },
            { buff = "kerillian_shade_movespeed_buff", field = "duration",   value = 20 },
            { buff = "kerillian_shade_power_buff",     field = "multiplier", value = 0.20 },
            { buff = "kerillian_shade_power_buff",     field = "duration",   value = 20 },
        },
        custom_apply = function(saved)
            if not Talents or not TalentIDLookup then return end
            local lookup = TalentIDLookup["kerillian_shade_activated_ability_phasing"]
            if not lookup then return end
            local talent = Talents[lookup.hero_name] and Talents[lookup.hero_name][lookup.talent_id]
            local dv = talent and talent.description_values
            if not dv then return end
            saved.hw_dv1 = dv[1] and dv[1].value
            saved.hw_dv2 = dv[2] and dv[2].value
            saved.hw_dv3 = dv[3] and dv[3].value
            if dv[1] then dv[1].value = 1.2  end
            if dv[2] then dv[2].value = 0.20 end
            if dv[3] then dv[3].value = 20   end
        end,
        custom_restore = function(saved)
            if not Talents or not TalentIDLookup then return end
            local lookup = TalentIDLookup["kerillian_shade_activated_ability_phasing"]
            if not lookup then return end
            local talent = Talents[lookup.hero_name] and Talents[lookup.hero_name][lookup.talent_id]
            local dv = talent and talent.description_values
            if not dv then return end
            if dv[1] and saved.hw_dv1 ~= nil then dv[1].value = saved.hw_dv1 end
            if dv[2] and saved.hw_dv2 ~= nil then dv[2].value = saved.hw_dv2 end
            if dv[3] and saved.hw_dv3 ~= nil then dv[3].value = saved.hw_dv3 end
            saved.hw_dv1, saved.hw_dv2, saved.hw_dv3 = nil, nil, nil
        end,
    },

    -- ============================================================
    -- Huntsman: +25 base HP (clone of Ranger Veteran HP pattern)
    -- ============================================================
    -- Vanilla 100 → 125 (matches Witch Hunter Captain). Same data path as
    -- `rework_dr_ranger_base_hp_plus_25`. Takes effect on next mission load /
    -- hero respawn (max_health is recalculated in PlayerUnitHealthExtension.init).
    rework_es_huntsman_base_hp_plus_25 = {
        character = "markus",
        career    = "es_huntsman",
        patches   = {},
        custom_apply = function(saved)
            local cs = CareerSettings and CareerSettings.es_huntsman
            local attrs = cs and cs.attributes
            if not attrs or type(attrs.max_hp) ~= "number" then return end
            saved.huntsman_max_hp_original = attrs.max_hp
            attrs.max_hp = attrs.max_hp + 25
        end,
        custom_restore = function(saved)
            if saved.huntsman_max_hp_original == nil then return end
            local cs = CareerSettings and CareerSettings.es_huntsman
            local attrs = cs and cs.attributes
            if not attrs then return end
            attrs.max_hp = saved.huntsman_max_hp_original
            saved.huntsman_max_hp_original = nil
        end,
    },

    -- ============================================================
    -- Huntsman: Prowl grants +50% power vs. monsters
    -- ============================================================
    -- During Prowl (Huntsman's active ability), inject an extra sub-buff into
    -- `BuffTemplates.markus_huntsman_activated_ability.buffs` that grants
    -- `stat_buff = "power_level_large"`, multiplier 1.5. VT2 resolves boss
    -- breeds to armor_category=3, which the damage pipeline reads via
    -- `apply_buffs_to_value(..., "power_level_large")` at
    -- action_utils.lua:346, stacking additively into the per-target power
    -- multiplier (`stacked_multiplier += (returned_multiplier - 1)`,
    -- action_utils.lua:353). So multiplier=1.5 yields +50% damage vs.
    -- monsters. CAVEAT: this applies to both melee and ranged attacks vs.
    -- monsters during Prowl — VT2 has no `power_level_ranged_vs_large`
    -- stat_buff, and a ranged-only gate would require hooking damage profile
    -- resolution. Acceptable trade since Huntsman during Prowl is almost
    -- always shooting; melee-vs-monster while stealthed is a corner case.
    rework_es_huntsman_prowl_monster_power = {
        character = "markus",
        career    = "es_huntsman",
        patches   = {},
        custom_apply = function(saved)
            if not BuffTemplates then return end
            local template = BuffTemplates.markus_huntsman_activated_ability
            if not template or not template.buffs then return end
            saved.prowl_buffs_original_count = #template.buffs
            table.insert(template.buffs, {
                stat_buff  = "power_level_large",
                multiplier = 1.5,
                name       = "crt_huntsman_prowl_monster_power",
                max_stacks = 1,
            })
        end,
        custom_restore = function(saved)
            if saved.prowl_buffs_original_count == nil then return end
            local template = BuffTemplates and BuffTemplates.markus_huntsman_activated_ability
            if template and template.buffs then
                while #template.buffs > saved.prowl_buffs_original_count do
                    table.remove(template.buffs)
                end
            end
            saved.prowl_buffs_original_count = nil
        end,
    },

    -- ============================================================
    -- Ranger Veteran: Exuberance — stacking DR
    -- ============================================================
    -- Vanilla: one ranged headshot grants -30% damage taken for 7s
    -- (talent `bardin_ranger_reduced_damage_taken_headshot`, applies buff
    -- `bardin_ranger_reduced_damage_taken_headshot_buff`).
    -- Rework: -6% per stack, max 5 stacks; one stack per shot (the proc fires
    -- once per shot regardless of pierce/cleave count, damage_utils.lua:2088);
    -- taking damage removes one stack (custom stack-remover buff template
    -- registered at apply time, mirrors `kerillian_shade_stealth_crits_remover`
    -- in talent_settings_kerillian.lua:306-320 — uses `remove_buff_stack`
    -- proc with `remove_buff_stack_data` array, see buff_function_templates.lua:2172).
    rework_dr_ranger_exuberance_stacking_dr = {
        character = "bardin",
        career    = "dr_ranger",
        patches   = {
            { buff = "bardin_ranger_reduced_damage_taken_headshot_buff", field = "max_stacks", value = 5 },
            { buff = "bardin_ranger_reduced_damage_taken_headshot_buff", field = "multiplier", value = -0.06 },
        },
        custom_apply = function(saved)
            if BuffTemplates and (BuffTemplates.crt_bardin_ranger_exuberance_stack_remover == nil or BuffTemplates.crt_bardin_ranger_exuberance_stack_remover._crt_pending) then
                BuffTemplates.crt_bardin_ranger_exuberance_stack_remover = {
                    buffs = {
                        {
                            buff_func = "remove_buff_stack",
                            event     = "on_damage_taken",
                            name      = "crt_bardin_ranger_exuberance_stack_remover",
                            remove_buff_func = "remove_buff_stack",
                            remove_buff_stack_data = {
                                {
                                    buff_to_remove   = "bardin_ranger_reduced_damage_taken_headshot_buff",
                                    num_stacks       = 1,
                                    server_controlled = false,
                                },
                            },
                        },
                    },
                }
                saved.crt_exuberance_remover_created = true
            end
            if Talents and TalentIDLookup then
                local lookup = TalentIDLookup["bardin_ranger_reduced_damage_taken_headshot"]
                if lookup then
                    local talent = Talents[lookup.hero_name] and Talents[lookup.hero_name][lookup.talent_id]
                    if talent and talent.buffs then
                        local already = false
                        for _, b in ipairs(talent.buffs) do
                            if b == "crt_bardin_ranger_exuberance_stack_remover" then already = true; break end
                        end
                        if not already then
                            saved.exuberance_talent_buffs_count = #talent.buffs
                            table.insert(talent.buffs, "crt_bardin_ranger_exuberance_stack_remover")
                        end
                    end
                    local dv = talent and talent.description_values and talent.description_values[1]
                    if dv then
                        saved.exuberance_tooltip_original = dv.value
                        dv.value = 0.06
                    end
                end
            end
        end,
        custom_restore = function(saved)
            if Talents and TalentIDLookup then
                local lookup = TalentIDLookup["bardin_ranger_reduced_damage_taken_headshot"]
                if lookup then
                    local talent = Talents[lookup.hero_name] and Talents[lookup.hero_name][lookup.talent_id]
                    if talent and talent.buffs and saved.exuberance_talent_buffs_count then
                        while #talent.buffs > saved.exuberance_talent_buffs_count do
                            table.remove(talent.buffs)
                        end
                    end
                    local dv = talent and talent.description_values and talent.description_values[1]
                    if dv and saved.exuberance_tooltip_original ~= nil then
                        dv.value = saved.exuberance_tooltip_original
                    end
                end
            end
            if saved.crt_exuberance_remover_created and BuffTemplates then
                BuffTemplates.crt_bardin_ranger_exuberance_stack_remover = _crt_make_stub()
            end
            saved.exuberance_talent_buffs_count = nil
            saved.exuberance_tooltip_original  = nil
            saved.crt_exuberance_remover_created = nil
        end,
    },

    -- ============================================================
    -- Bounty Hunter: Blessed Combat (level 20) — 15% → 25% stacks
    -- ============================================================
    -- Talent `victor_bountyhunter_weapon_swap_buff`. Vanilla: melee hits stack
    -- ranged-damage buff (+15%/stack, max 6); ranged hits stack melee-damage
    -- buff (+15%/stack). Rework: both lift to +25%/stack. Tooltip values at
    -- description_values[2] and [4] (lines 1845/1852 of talent_settings_victor.lua)
    -- both need rewriting. NOTE: the user also asked that the
    -- "melee kills reset blessed-shots cooldown" effect (currently bundled into
    -- Blessed Combat via the `victor_bountyhunter_activate_passive_on_melee_kill`
    -- buff on line 1857) become innate regardless of which level-20 talent is
    -- selected — handled here by appending the same buff to the OTHER two
    -- level-20 talents' `buffs` lists when the toggle is on.
    rework_wh_bountyhunter_blessed_combat_25_and_passive_melee_reset = {
        character = "victor",
        career    = "wh_bountyhunter",
        patches   = {
            { buff = "victor_bountyhunter_blessed_melee_damage_buff",  field = "multiplier", value = 0.25 },
            { buff = "victor_bountyhunter_blessed_ranged_damage_buff", field = "multiplier", value = 0.25 },
        },
        custom_apply = function(saved)
            if not Talents or not TalentIDLookup then return end
            local lookup = TalentIDLookup["victor_bountyhunter_weapon_swap_buff"]
            if lookup then
                local talent = Talents[lookup.hero_name] and Talents[lookup.hero_name][lookup.talent_id]
                local dv = talent and talent.description_values
                if dv then
                    if dv[2] then saved.bc_dv2 = dv[2].value; dv[2].value = 0.25 end
                    if dv[4] then saved.bc_dv4 = dv[4].value; dv[4].value = 0.25 end
                end
            end
            -- Promote melee-kill cooldown reset to passive: append buff to the
            -- OTHER two level-20 talents (col 2 = passive_reduced_cooldown,
            -- col 3 = passive_infinite_ammo).
            saved.bc_appended = {}
            local function _append(talent_name, buff_name)
                local lk = TalentIDLookup[talent_name]
                if not lk then return end
                local t = Talents[lk.hero_name] and Talents[lk.hero_name][lk.talent_id]
                if not t or not t.buffs then return end
                for _, b in ipairs(t.buffs) do
                    if b == buff_name then return end
                end
                saved.bc_appended[talent_name] = #t.buffs
                table.insert(t.buffs, buff_name)
            end
            _append("victor_bountyhunter_passive_reduced_cooldown", "victor_bountyhunter_activate_passive_on_melee_kill")
            _append("victor_bountyhunter_passive_infinite_ammo",    "victor_bountyhunter_activate_passive_on_melee_kill")
        end,
        custom_restore = function(saved)
            if not Talents or not TalentIDLookup then return end
            local lookup = TalentIDLookup["victor_bountyhunter_weapon_swap_buff"]
            if lookup then
                local talent = Talents[lookup.hero_name] and Talents[lookup.hero_name][lookup.talent_id]
                local dv = talent and talent.description_values
                if dv then
                    if dv[2] and saved.bc_dv2 ~= nil then dv[2].value = saved.bc_dv2 end
                    if dv[4] and saved.bc_dv4 ~= nil then dv[4].value = saved.bc_dv4 end
                end
            end
            if saved.bc_appended then
                for talent_name, original_count in pairs(saved.bc_appended) do
                    local lk = TalentIDLookup[talent_name]
                    local t = lk and Talents[lk.hero_name] and Talents[lk.hero_name][lk.talent_id]
                    if t and t.buffs then
                        while #t.buffs > original_count do table.remove(t.buffs) end
                    end
                end
            end
            saved.bc_dv2, saved.bc_dv4, saved.bc_appended = nil, nil, nil
        end,
    },

    -- ============================================================
    -- Bounty Hunter: Rile the Mob → permanent +10% move speed
    -- ============================================================
    -- Vanilla: ranged crit grants the team +10% move speed for 10s. Rework:
    -- replace with a permanent self-only +10% move speed while the talent is
    -- selected. Swaps the outer `victor_bountyhunter_party_movespeed_on_ranged_crit`
    -- buff template's buffs[1] entry from a conditional crit-trigger
    -- (`add_team_buff_on_ranged_critical_hit`) to a direct apply_movement_buff
    -- entry with no duration. The talent's `buffs` list already references
    -- the outer buff template by name (line 1896), so swapping its buffs[1]
    -- changes what the player gets at talent-apply time.
    rework_wh_bountyhunter_rile_the_mob_movement = {
        character = "victor",
        career    = "wh_bountyhunter",
        patches   = {},
        custom_apply = function(saved)
            local outer = BuffTemplates and BuffTemplates.victor_bountyhunter_party_movespeed_on_ranged_crit
            if not outer or not outer.buffs or not outer.buffs[1] then return end
            saved.rile_outer_buffs1_original = outer.buffs[1]
            outer.buffs[1] = {
                apply_buff_func  = "apply_movement_buff",
                remove_buff_func = "remove_movement_buff",
                name             = "crt_rile_the_mob_permanent_movespeed",
                max_stacks       = 1,
                multiplier       = 1.1,
                path_to_movement_setting_to_modify = { "move_speed" },
            }
        end,
        custom_restore = function(saved)
            if not saved.rile_outer_buffs1_original then return end
            local outer = BuffTemplates and BuffTemplates.victor_bountyhunter_party_movespeed_on_ranged_crit
            if outer and outer.buffs then
                outer.buffs[1] = saved.rile_outer_buffs1_original
            end
            saved.rile_outer_buffs1_original = nil
        end,
    },

    -- ============================================================
    -- Bounty Hunter: Salvaged Ammunition — drop out-of-ammo gate +
    -- passive melee-reload
    -- ============================================================
    -- Vanilla Salvaged Ammunition restores 20% of max ammo on Elite kill (any
    -- attack type -- buff_tweak_data ammo_bonus_fraction = 0.2,
    -- talent_settings_victor.lua:127-129) BUT only when you're completely out
    -- of ammo (gate at buff_templates.lua:3052:
    -- `if current_ammo < 1 and clip_ammo < 1`). It also reloads your ranged
    -- weapon on every melee kill (buff_templates.lua:2798).
    -- Rework: drop the out-of-ammo gate (function override below in the hook
    -- section), and make the reload-on-melee-kill effect innate (append it to
    -- the OTHER level-25 talents' buffs lists, mirroring the Blessed Combat
    -- passive-promotion pattern).
    rework_wh_bountyhunter_salvaged_ammo_no_gate_and_passive_reload = {
        character = "victor",
        career    = "wh_bountyhunter",
        patches   = {},
        custom_apply = function(saved)
            if not Talents or not TalentIDLookup then return end
            saved.sa_appended = {}
            local function _append(talent_name, buff_name)
                local lk = TalentIDLookup[talent_name]
                if not lk then return end
                local t = Talents[lk.hero_name] and Talents[lk.hero_name][lk.talent_id]
                if not t or not t.buffs then return end
                for _, b in ipairs(t.buffs) do
                    if b == buff_name then return end
                end
                saved.sa_appended[talent_name] = #t.buffs
                table.insert(t.buffs, buff_name)
            end
            _append("victor_bountyhunter_party_movespeed_on_ranged_crit",                "victor_bountyhunter_reload_on_kill")
            _append("victor_bountyhunter_stacking_damage_reduction_on_elite_or_special_kill", "victor_bountyhunter_reload_on_kill")
        end,
        custom_restore = function(saved)
            if not Talents or not TalentIDLookup then return end
            if saved.sa_appended then
                for talent_name, original_count in pairs(saved.sa_appended) do
                    local lk = TalentIDLookup[talent_name]
                    local t = lk and Talents[lk.hero_name] and Talents[lk.hero_name][lk.talent_id]
                    if t and t.buffs then
                        while #t.buffs > original_count do table.remove(t.buffs) end
                    end
                end
            end
            saved.sa_appended = nil
        end,
    },

    -- ============================================================
    -- Bounty Hunter: Job Well Done — innate + special-kill stacking DR
    -- ============================================================
    -- Vanilla Job Well Done (`victor_bountyhunter_stacking_damage_reduction_on_elite_or_special_kill`):
    -- on elite OR special kill, gain stacking damage taken reduction
    -- (-1%/stack, max 30 stacks). Rework: that vanilla effect becomes innate
    -- (appended to the OTHER two level-25 talents' buffs lists, like
    -- Blessed Combat / Salvaged Ammo); the talent slot itself swaps its
    -- payload to a NEW special-kill DR stacking buff at -5%/stack, max 6
    -- stacks, with one stack removed per damage taken (stack remover added
    -- to the talent's buffs list via the kerillian-shade pattern).
    rework_wh_bountyhunter_job_well_done_passive_and_special_kill_dr = {
        character = "victor",
        career    = "wh_bountyhunter",
        -- issue 425: the DR-stack add rides rpc_add_buff (via the special-kill
        -- proc); gated on peer parity + wire-safe proc wrapper.
        network_unsafe = true,
        patches   = {},
        custom_apply = function(saved)
            if not BuffTemplates or not Talents or not TalentIDLookup then return end
            _crt_ensure_wire_safe_funcs()
            -- Register the new special-kill DR stacking buff if missing.
            if BuffTemplates.crt_bh_jwd_special_kill_dr_proc == nil or BuffTemplates.crt_bh_jwd_special_kill_dr_proc._crt_pending then
                BuffTemplates.crt_bh_jwd_special_kill_dr_proc = {
                    buffs = {
                        {
                            buff_func     = "crt_wire_safe_add_buff_on_special_kill",
                            buff_to_add   = "crt_bh_jwd_special_kill_dr_stack",
                            event         = "on_kill",
                            name          = "crt_bh_jwd_special_kill_dr_proc",
                        },
                    },
                }
                saved.jwd_created_proc = true
            end
            if BuffTemplates.crt_bh_jwd_special_kill_dr_stack == nil or BuffTemplates.crt_bh_jwd_special_kill_dr_stack._crt_pending then
                BuffTemplates.crt_bh_jwd_special_kill_dr_stack = {
                    buffs = {
                        {
                            stat_buff   = "damage_taken",
                            multiplier  = -0.05,
                            max_stacks  = 6,
                            duration    = 60,
                            refresh_durations = true,
                            name        = "crt_bh_jwd_special_kill_dr_stack",
                        },
                    },
                }
                saved.jwd_created_stack = true
            end
            if BuffTemplates.crt_bh_jwd_stack_remover == nil or BuffTemplates.crt_bh_jwd_stack_remover._crt_pending then
                BuffTemplates.crt_bh_jwd_stack_remover = {
                    buffs = {
                        {
                            buff_func = "remove_buff_stack",
                            event     = "on_damage_taken",
                            name      = "crt_bh_jwd_stack_remover",
                            remove_buff_func = "remove_buff_stack",
                            remove_buff_stack_data = {
                                {
                                    buff_to_remove   = "crt_bh_jwd_special_kill_dr_stack",
                                    num_stacks       = 1,
                                    server_controlled = false,
                                },
                            },
                        },
                    },
                }
                saved.jwd_created_remover = true
            end
            -- Talent payload swap: replace the talent's buffs list (was the
            -- vanilla 1%/stack proc) with the new 5%/stack proc + remover.
            local lookup = TalentIDLookup["victor_bountyhunter_stacking_damage_reduction_on_elite_or_special_kill"]
            if lookup then
                local talent = Talents[lookup.hero_name] and Talents[lookup.hero_name][lookup.talent_id]
                if talent and talent.buffs then
                    saved.jwd_talent_buffs_original = {}
                    for i = 1, #talent.buffs do saved.jwd_talent_buffs_original[i] = talent.buffs[i] end
                    talent.buffs = { "crt_bh_jwd_special_kill_dr_proc", "crt_bh_jwd_stack_remover" }
                end
            end
            -- Promote vanilla effect to innate: append vanilla buff to the
            -- OTHER two level-25 talents.
            saved.jwd_appended = {}
            local function _append(talent_name, buff_name)
                local lk = TalentIDLookup[talent_name]
                if not lk then return end
                local t = Talents[lk.hero_name] and Talents[lk.hero_name][lk.talent_id]
                if not t or not t.buffs then return end
                for _, b in ipairs(t.buffs) do
                    if b == buff_name then return end
                end
                saved.jwd_appended[talent_name] = #t.buffs
                table.insert(t.buffs, buff_name)
            end
            _append("victor_bountyhunter_party_movespeed_on_ranged_crit",
                    "victor_bountyhunter_stacking_damage_reduction_on_elite_or_special_kill")
            _append("victor_bountyhunter_reload_on_kill",
                    "victor_bountyhunter_stacking_damage_reduction_on_elite_or_special_kill")
        end,
        custom_restore = function(saved)
            if not Talents or not TalentIDLookup then return end
            local lookup = TalentIDLookup["victor_bountyhunter_stacking_damage_reduction_on_elite_or_special_kill"]
            if lookup and saved.jwd_talent_buffs_original then
                local talent = Talents[lookup.hero_name] and Talents[lookup.hero_name][lookup.talent_id]
                if talent then talent.buffs = saved.jwd_talent_buffs_original end
            end
            if saved.jwd_appended then
                for talent_name, original_count in pairs(saved.jwd_appended) do
                    local lk = TalentIDLookup[talent_name]
                    local t = lk and Talents[lk.hero_name] and Talents[lk.hero_name][lk.talent_id]
                    if t and t.buffs then
                        while #t.buffs > original_count do table.remove(t.buffs) end
                    end
                end
            end
            if BuffTemplates then
                if saved.jwd_created_proc    then BuffTemplates.crt_bh_jwd_special_kill_dr_proc = _crt_make_stub() end
                if saved.jwd_created_stack   then BuffTemplates.crt_bh_jwd_special_kill_dr_stack = _crt_make_stub() end
                if saved.jwd_created_remover then BuffTemplates.crt_bh_jwd_stack_remover = _crt_make_stub() end
            end
            saved.jwd_talent_buffs_original = nil
            saved.jwd_appended = nil
            saved.jwd_created_proc, saved.jwd_created_stack, saved.jwd_created_remover = nil, nil, nil
        end,
    },

    -- ============================================================
    -- Bounty Hunter: Just Reward — 10s cooldown gate → 5s
    -- ============================================================
    -- Talent `victor_bountyhunter_activated_ability_reset_cooldown_on_stacks`
    -- attaches buff `victor_bountyhunter_activated_ability_passive_cooldown_reduction`
    -- (line 1982). The proc func at buff_templates.lua:3593-3614 reads
    -- `template.cooldown` (10 by default, merged in from buff_tweak_data) and
    -- gates the next proc to `t > buff.cooldown` where `buff.cooldown = t +
    -- template.cooldown`. Patching the template's `cooldown` field to 5
    -- halves the gate. Tooltip cooldown lives in description_values[2].
    rework_wh_bountyhunter_just_reward_5s_cooldown = {
        character = "victor",
        career    = "wh_bountyhunter",
        patches   = {
            { buff = "victor_bountyhunter_activated_ability_passive_cooldown_reduction", field = "cooldown", value = 5 },
        },
        custom_apply = function(saved)
            if not Talents or not TalentIDLookup then return end
            local lookup = TalentIDLookup["victor_bountyhunter_activated_ability_reset_cooldown_on_stacks"]
            if not lookup then return end
            local talent = Talents[lookup.hero_name] and Talents[lookup.hero_name][lookup.talent_id]
            local dv = talent and talent.description_values and talent.description_values[2]
            if not dv then return end
            saved.jr_tooltip_original = dv.value
            dv.value = 5
        end,
        custom_restore = function(saved)
            if saved.jr_tooltip_original == nil then return end
            if not Talents or not TalentIDLookup then return end
            local lookup = TalentIDLookup["victor_bountyhunter_activated_ability_reset_cooldown_on_stacks"]
            if not lookup then return end
            local talent = Talents[lookup.hero_name] and Talents[lookup.hero_name][lookup.talent_id]
            local dv = talent and talent.description_values and talent.description_values[2]
            if not dv then return end
            dv.value = saved.jr_tooltip_original
            saved.jr_tooltip_original = nil
        end,
    },

    -- ============================================================
    -- Bounty Hunter: Double-Shotted damage doubling (stacks with 80% rework)
    -- ============================================================
    -- Independent toggle from `rework_wh_bountyhunter_double_shotted_80`. Adds
    -- +100% ranged power for a short window after the BH ability is activated,
    -- so the next ranged shot deals double damage. Implementation: register a
    -- buff template `crt_bh_double_shotted_damage_buff` with stat_buff
    -- "power_level_ranged", multiplier 1.0 (= +100% damage when stacking
    -- additively via apply_buffs_to_value, action_utils.lua:353), 3s duration;
    -- inject it into the railgun talent's buffs list so it's added to the
    -- player when Double-Shotted is selected — but we want it to apply on
    -- ability activation, not all the time, so we instead hook
    -- CareerAbilityWHBountyHunter:_run_ability below (see runtime hooks).
    -- This BALANCE_MODS entry only registers the template; the hook activates it.
    rework_wh_bountyhunter_double_shotted_damage_double = {
        character = "victor",
        career    = "wh_bountyhunter",
        patches   = {},
        custom_apply = function(saved)
            if not BuffTemplates then return end
            if BuffTemplates.crt_bh_double_shotted_damage_buff == nil or BuffTemplates.crt_bh_double_shotted_damage_buff._crt_pending then
                BuffTemplates.crt_bh_double_shotted_damage_buff = {
                    buffs = {
                        {
                            stat_buff  = "power_level_ranged",
                            multiplier = 1.0,
                            max_stacks = 1,
                            duration   = 3,
                            refresh_durations = true,
                            name       = "crt_bh_double_shotted_damage_buff",
                        },
                    },
                }
                saved.dsd_created = true
            end
        end,
        custom_restore = function(saved)
            if saved.dsd_created and BuffTemplates then
                BuffTemplates.crt_bh_double_shotted_damage_buff = _crt_make_stub()
            end
            saved.dsd_created = nil
        end,
    },

    -- ============================================================
    -- Bounty Hunter: Indiscriminate Blast — 1% cooldown refund per kill
    -- ============================================================
    -- Talent `victor_bountyhunter_activated_ability_blast_shotgun` already
    -- adds `victor_bounty_blast_streak_buff` on kills to grant cooldown
    -- reduction at stack thresholds. Rework adds, on top of vanilla, a flat
    -- 1% cooldown refund per kill the BH ability scores. Implemented in the
    -- runtime hook section below — wraps `ProcFunctions.victor_bounty_blast_streak_activation`
    -- (buff_templates.lua:line of definition near the BH proc cluster) and,
    -- when the kill's damage source is `victor_bountyhunter_career_skill_weapon`,
    -- additionally calls `career_extension:reduce_activated_ability_cooldown_percent(0.01)`.
    -- This BALANCE_MODS entry is a stub so the toggle appears in active_count
    -- and the apply/restore engine knows about it (no field patches needed).
    rework_wh_bountyhunter_indiscriminate_blast_refund_per_kill = {
        character = "victor",
        career    = "wh_bountyhunter",
        patches   = {},
    },

    -- ============================================================
    -- Universal: Enhanced Power (level 15) — every career 7.5% → 10%
    -- ============================================================
    -- All 15 base careers' level-15 Enhanced Power talents attach the shared
    -- `power_level_unbalance` buff template (buff_templates.lua:5857). One
    -- field patch updates the multiplier for every career simultaneously. Each
    -- career's tooltip reads the value from `BuffUtils.get_buff_template(
    -- "power_level_unbalance", "adventure").buffs[1].multiplier` at file load
    -- time, so the per-talent `description_values[1].value` is frozen at 0.075
    -- and must be rewritten per career. 15 base careers (DLC careers either
    -- don't have this talent or use a different naming convention — they're
    -- silently skipped if TalentIDLookup doesn't resolve).
    rework_general_enhanced_power_10pct = {
        character = "any",
        career    = "any",
        patches   = {
            { buff = "power_level_unbalance", field = "multiplier", value = 0.10 },
        },
        custom_apply = function(saved)
            if not Talents or not TalentIDLookup then return end
            saved.enh_pwr_tooltips = {}
            local talent_names = {
                "bardin_ironbreaker_power_level_unbalance",
                "bardin_slayer_power_level_unbalance",
                "bardin_ranger_power_level_unbalance",
                "markus_huntsman_power_level_unbalance",
                "markus_knight_power_level_unbalance",
                "markus_mercenary_power_level_unbalance",
                "kerillian_shade_power_level_unbalance",
                "kerillian_maidenguard_power_level_unbalance",
                "kerillian_waystalker_power_level_unbalance",
                "victor_zealot_power_level_unbalance",
                "victor_bounty_hunter_power_level_unbalance",
                "victor_witchhunter_power_level_unbalance",
                "sienna_scholar_power_level_unbalance",
                "sienna_adept_power_level_unbalance",
                "sienna_unchained_power_level_unbalance",
            }
            for _, talent_name in ipairs(talent_names) do
                local lookup = TalentIDLookup[talent_name]
                if lookup then
                    local talent = Talents[lookup.hero_name] and Talents[lookup.hero_name][lookup.talent_id]
                    local dv = talent and talent.description_values and talent.description_values[1]
                    if dv then
                        saved.enh_pwr_tooltips[talent_name] = dv.value
                        dv.value = 0.10
                    end
                end
            end
        end,
        custom_restore = function(saved)
            if not Talents or not TalentIDLookup or not saved.enh_pwr_tooltips then return end
            for talent_name, original in pairs(saved.enh_pwr_tooltips) do
                local lookup = TalentIDLookup[talent_name]
                if lookup then
                    local talent = Talents[lookup.hero_name] and Talents[lookup.hero_name][lookup.talent_id]
                    local dv = talent and talent.description_values and talent.description_values[1]
                    if dv then dv.value = original end
                end
            end
            saved.enh_pwr_tooltips = nil
        end,
    },

    -- ============================================================
    -- Battle Wizard: Famished Flames (lvl 25) — burn 100→150%, non-burn 15→30%
    -- ============================================================
    -- Talent `sienna_adept_increased_burn_damage_reduced_non_burn_damage`
    -- attaches two separate buff templates: `sienna_adept_increased_burn_damage`
    -- (multiplier 1.0 = +100% burn damage) and `sienna_adept_reduced_non_burn_damage`
    -- (multiplier -0.15 = -15% non-burn). User's "level 10" terminology is a
    -- mis-recall — the talent lives at row 5 (level 25) on Battle Wizard (bw_adept).
    rework_bw_adept_famished_flames_buffed = {
        character = "sienna",
        career    = "bw_adept",
        patches   = {
            { buff = "sienna_adept_increased_burn_damage",     field = "multiplier", value = 1.5  },
            { buff = "sienna_adept_reduced_non_burn_damage",   field = "multiplier", value = -0.30 },
        },
        custom_apply = function(saved)
            if not Talents or not TalentIDLookup then return end
            local lookup = TalentIDLookup["sienna_adept_increased_burn_damage_reduced_non_burn_damage"]
            if not lookup then return end
            local talent = Talents[lookup.hero_name] and Talents[lookup.hero_name][lookup.talent_id]
            local dv = talent and talent.description_values
            if not dv then return end
            if dv[1] then saved.ff_dv1 = dv[1].value; dv[1].value = 1.5  end
            if dv[2] then saved.ff_dv2 = dv[2].value; dv[2].value = 0.30 end
        end,
        custom_restore = function(saved)
            if not Talents or not TalentIDLookup then return end
            local lookup = TalentIDLookup["sienna_adept_increased_burn_damage_reduced_non_burn_damage"]
            if not lookup then return end
            local talent = Talents[lookup.hero_name] and Talents[lookup.hero_name][lookup.talent_id]
            local dv = talent and talent.description_values
            if not dv then return end
            if dv[1] and saved.ff_dv1 ~= nil then dv[1].value = saved.ff_dv1 end
            if dv[2] and saved.ff_dv2 ~= nil then dv[2].value = saved.ff_dv2 end
            saved.ff_dv1, saved.ff_dv2 = nil, nil
        end,
    },

    -- ============================================================
    -- Battle Wizard: Volcanic Force (lvl 20) — full-charge +50% → +100%
    -- ============================================================
    -- Talent `sienna_adept_power_level_on_full_charge`. Buff template's
    -- multiplier holds the +50% (0.5) bonus on fully-charged spells.
    -- User said "level 10" — actual is row 4 (level 20) on Battle Wizard (bw_adept).
    rework_bw_adept_volcanic_force_doubled = {
        character = "sienna",
        career    = "bw_adept",
        patches   = {
            { buff = "sienna_adept_power_level_on_full_charge", field = "multiplier", value = 1.0 },
        },
        custom_apply = function(saved)
            if not Talents or not TalentIDLookup then return end
            local lookup = TalentIDLookup["sienna_adept_power_level_on_full_charge"]
            if not lookup then return end
            local talent = Talents[lookup.hero_name] and Talents[lookup.hero_name][lookup.talent_id]
            local dv = talent and talent.description_values and talent.description_values[1]
            if not dv then return end
            saved.vf_orig = dv.value
            dv.value = 1.0
        end,
        custom_restore = function(saved)
            if saved.vf_orig == nil then return end
            if not Talents or not TalentIDLookup then return end
            local lookup = TalentIDLookup["sienna_adept_power_level_on_full_charge"]
            if not lookup then return end
            local talent = Talents[lookup.hero_name] and Talents[lookup.hero_name][lookup.talent_id]
            local dv = talent and talent.description_values and talent.description_values[1]
            if not dv then return end
            dv.value = saved.vf_orig
            saved.vf_orig = nil
        end,
    },

    -- ============================================================
    -- Battle Wizard: Fires from Ash — 3% → 1% CDR + 0.5 THP per burning kill
    -- ============================================================
    -- Talent `sienna_adept_cooldown_reduction_on_burning_enemy_killed`.
    -- Field patch on the cooldown_reduction multiplier (0.03→0.01); the
    -- additional +0.5 THP grant per burning kill is layered in via a wrapper
    -- on the proc func `sienna_adept_reduce_activated_ability_cooldown_on_burning_enemy_killed`
    -- (see runtime hook below). User's "level 25" matches vanilla.
    rework_bw_adept_fires_from_ash_1pct_plus_thp = {
        character = "sienna",
        career    = "bw_adept",
        patches   = {
            { buff = "sienna_adept_cooldown_reduction_on_burning_enemy_killed", field = "cooldown_reduction", value = 0.01 },
        },
        custom_apply = function(saved)
            if not Talents or not TalentIDLookup then return end
            local lookup = TalentIDLookup["sienna_adept_cooldown_reduction_on_burning_enemy_killed"]
            if not lookup then return end
            local talent = Talents[lookup.hero_name] and Talents[lookup.hero_name][lookup.talent_id]
            local dv = talent and talent.description_values and talent.description_values[1]
            if not dv then return end
            saved.ffa_tooltip = dv.value
            dv.value = 0.01
        end,
        custom_restore = function(saved)
            if saved.ffa_tooltip == nil then return end
            if not Talents or not TalentIDLookup then return end
            local lookup = TalentIDLookup["sienna_adept_cooldown_reduction_on_burning_enemy_killed"]
            if not lookup then return end
            local talent = Talents[lookup.hero_name] and Talents[lookup.hero_name][lookup.talent_id]
            local dv = talent and talent.description_values and talent.description_values[1]
            if not dv then return end
            dv.value = saved.ffa_tooltip
            saved.ffa_tooltip = nil
        end,
    },

    -- ============================================================
    -- Necromancer: Lost Souls passive — double radius (5 → 10)
    -- ============================================================
    -- "Lost Souls" is the Necromancer's career PASSIVE perk
    -- (`sienna_necromancer_perk_1`), not a talent. Devours 15% max HP of nearby
    -- enemies within a 5m radius — patch doubles the radius.
    rework_bw_necromancer_lost_souls_double_radius = {
        character = "sienna",
        career    = "bw_necromancer",
        patches   = {
            { buff = "sienna_necromancer_perk_1", field = "radius", value = 10 },
        },
    },

    -- ============================================================
    -- Necromancer: Withering Touch — 15s → 30s duration
    -- ============================================================
    -- Talent `sienna_necromancer_4_3` attaches buff
    -- `sienna_necromancer_4_3_withering_touch`. Duration field merged from
    -- SHOVEL_BUFF_TWEAK_DATA at boot.
    rework_bw_necromancer_withering_touch_30s = {
        character = "sienna",
        career    = "bw_necromancer",
        patches   = {
            { buff = "sienna_necromancer_4_3_withering_touch", field = "duration", value = 30 },
        },
        custom_apply = function(saved)
            if not Talents or not TalentIDLookup then return end
            local lookup = TalentIDLookup["sienna_necromancer_4_3"]
            if not lookup then return end
            local talent = Talents[lookup.hero_name] and Talents[lookup.hero_name][lookup.talent_id]
            local dv = talent and talent.description_values and talent.description_values[1]
            if not dv then return end
            saved.wt_orig = dv.value
            dv.value = 30
        end,
        custom_restore = function(saved)
            if saved.wt_orig == nil then return end
            if not Talents or not TalentIDLookup then return end
            local lookup = TalentIDLookup["sienna_necromancer_4_3"]
            if not lookup then return end
            local talent = Talents[lookup.hero_name] and Talents[lookup.hero_name][lookup.talent_id]
            local dv = talent and talent.description_values and talent.description_values[1]
            if not dv then return end
            dv.value = saved.wt_orig
            saved.wt_orig = nil
        end,
    },

    -- ============================================================
    -- Necromancer: Malediction of Nagash — 8 souls → 5 souls for crit
    -- ============================================================
    -- Talent `sienna_necromancer_4_2` (level 20). Stack threshold lives on
    -- buff `sienna_necromancer_4_2_soul_rip_stack.max_stacks` (8 vanilla).
    rework_bw_necromancer_malediction_5_souls = {
        character = "sienna",
        career    = "bw_necromancer",
        patches   = {
            { buff = "sienna_necromancer_4_2_soul_rip_stack", field = "max_stacks", value = 5 },
        },
        custom_apply = function(saved)
            if not Talents or not TalentIDLookup then return end
            local lookup = TalentIDLookup["sienna_necromancer_4_2"]
            if not lookup then return end
            local talent = Talents[lookup.hero_name] and Talents[lookup.hero_name][lookup.talent_id]
            local dv = talent and talent.description_values and talent.description_values[1]
            if not dv then return end
            saved.mn_orig = dv.value
            dv.value = 5
        end,
        custom_restore = function(saved)
            if saved.mn_orig == nil then return end
            if not Talents or not TalentIDLookup then return end
            local lookup = TalentIDLookup["sienna_necromancer_4_2"]
            if not lookup then return end
            local talent = Talents[lookup.hero_name] and Talents[lookup.hero_name][lookup.talent_id]
            local dv = talent and talent.description_values and talent.description_values[1]
            if not dv then return end
            dv.value = saved.mn_orig
            saved.mn_orig = nil
        end,
    },

    -- ============================================================
    -- Necromancer: Vanhel's Danse Macabre — +12% binary → +2%/stack cap 24%
    -- ============================================================
    -- Vanilla talent `sienna_necromancer_2_1` works binary: at ≥4 skeletons
    -- raised, gain +12% attack speed (max_stacks = 1). User's spec changes the
    -- mechanic to per-skeleton stacking: +2%/stack up to 12 stacks (+24% cap).
    -- Patches: multiplier 0.12→0.02, max_stacks 1→12. The proc functions
    -- `thank_you_skeletal_add` and `thank_you_skeletal_remove` are overridden
    -- in the runtime hook section below to add/remove one stack per skeleton
    -- raised/removed (vanilla gates on threshold; rework drops the gate).
    rework_bw_necromancer_vanhels_per_skeleton_as = {
        character = "sienna",
        career    = "bw_necromancer",
        patches   = {
            { buff = "sienna_necromancer_2_1_attack_speed", field = "multiplier", value = 0.02 },
            { buff = "sienna_necromancer_2_1_attack_speed", field = "max_stacks", value = 12   },
        },
        custom_apply = function(saved)
            if not Talents or not TalentIDLookup then return end
            local lookup = TalentIDLookup["sienna_necromancer_2_1"]
            if not lookup then return end
            local talent = Talents[lookup.hero_name] and Talents[lookup.hero_name][lookup.talent_id]
            local dv = talent and talent.description_values
            if not dv then return end
            if dv[1] then saved.vdm_dv1 = dv[1].value; dv[1].value = 0.02 end
            if dv[2] then saved.vdm_dv2 = dv[2].value; dv[2].value = 12   end
        end,
        custom_restore = function(saved)
            if not Talents or not TalentIDLookup then return end
            local lookup = TalentIDLookup["sienna_necromancer_2_1"]
            if not lookup then return end
            local talent = Talents[lookup.hero_name] and Talents[lookup.hero_name][lookup.talent_id]
            local dv = talent and talent.description_values
            if not dv then return end
            if dv[1] and saved.vdm_dv1 ~= nil then dv[1].value = saved.vdm_dv1 end
            if dv[2] and saved.vdm_dv2 ~= nil then dv[2].value = saved.vdm_dv2 end
            saved.vdm_dv1, saved.vdm_dv2 = nil, nil
        end,
    },

    -- ============================================================
    -- Waystalker: Kurnous' Reward — 30% → 5% ammo per ability special/elite
    -- ============================================================
    -- Talent `kerillian_waywatcher_activated_ability_restore_ammo_on_career_skill_special_kill`.
    -- Vanilla ammo_bonus_fraction = 0.3 (30% of max ammo on each special/elite
    -- killed by the ability shot). Rework lowers to 5% per spec.
    rework_we_waywatcher_kurnous_reward_5pct = {
        character = "kerillian",
        career    = "we_waywatcher",
        patches   = {
            { buff = "kerillian_waywatcher_activated_ability_restore_ammo_on_career_skill_special_kill", field = "ammo_bonus_fraction", value = 0.05 },
        },
        custom_apply = function(saved)
            if not Talents or not TalentIDLookup then return end
            local lookup = TalentIDLookup["kerillian_waywatcher_activated_ability_restore_ammo_on_career_skill_special_kill"]
            if not lookup then return end
            local talent = Talents[lookup.hero_name] and Talents[lookup.hero_name][lookup.talent_id]
            local dv = talent and talent.description_values and talent.description_values[1]
            if not dv then return end
            saved.kr_orig = dv.value
            dv.value = 0.05
        end,
        custom_restore = function(saved)
            if saved.kr_orig == nil then return end
            if not Talents or not TalentIDLookup then return end
            local lookup = TalentIDLookup["kerillian_waywatcher_activated_ability_restore_ammo_on_career_skill_special_kill"]
            if not lookup then return end
            local talent = Talents[lookup.hero_name] and Talents[lookup.hero_name][lookup.talent_id]
            local dv = talent and talent.description_values and talent.description_values[1]
            if not dv then return end
            dv.value = saved.kr_orig
            saved.kr_orig = nil
        end,
    },

    -- ============================================================
    -- Waystalker: Drakira's Alacrity → flat passive +10% attack speed
    -- ============================================================
    -- "Drakira's Alacrity" doesn't exist by that exact name in vanilla; the
    -- closest is `kerillian_waywatcher_attack_speed_on_ranged_headshot` (level
    -- 10, conditional +15% AS for 5s on ranged headshot). Rework replaces the
    -- talent's payload with a permanent +10% attack speed buff (no trigger).
    -- Mirrors `rework_wh_bountyhunter_rile_the_mob_movement` swap pattern.
    rework_we_waywatcher_drakiras_alacrity_passive_as = {
        character = "kerillian",
        career    = "we_waywatcher",
        patches   = {},
        custom_apply = function(saved)
            if not BuffTemplates then return end
            -- Register the permanent passive buff template if missing.
            if BuffTemplates.crt_waywatcher_drakiras_alacrity_passive == nil or BuffTemplates.crt_waywatcher_drakiras_alacrity_passive._crt_pending then
                BuffTemplates.crt_waywatcher_drakiras_alacrity_passive = {
                    buffs = {
                        {
                            stat_buff  = "attack_speed",
                            multiplier = 0.10,
                            max_stacks = 1,
                            name       = "crt_waywatcher_drakiras_alacrity_passive",
                        },
                    },
                }
                saved.drakira_created = true
            end
            -- Swap the talent's buffs list to point at the new permanent buff.
            if Talents and TalentIDLookup then
                local lookup = TalentIDLookup["kerillian_waywatcher_attack_speed_on_ranged_headshot"]
                if lookup then
                    local talent = Talents[lookup.hero_name] and Talents[lookup.hero_name][lookup.talent_id]
                    if talent and talent.buffs then
                        saved.drakira_orig_buffs = {}
                        for i, b in ipairs(talent.buffs) do saved.drakira_orig_buffs[i] = b end
                        talent.buffs = { "crt_waywatcher_drakiras_alacrity_passive" }
                    end
                end
            end
        end,
        custom_restore = function(saved)
            if Talents and TalentIDLookup and saved.drakira_orig_buffs then
                local lookup = TalentIDLookup["kerillian_waywatcher_attack_speed_on_ranged_headshot"]
                if lookup then
                    local talent = Talents[lookup.hero_name] and Talents[lookup.hero_name][lookup.talent_id]
                    if talent then talent.buffs = saved.drakira_orig_buffs end
                end
            end
            if saved.drakira_created and BuffTemplates then
                BuffTemplates.crt_waywatcher_drakiras_alacrity_passive = _crt_make_stub()
            end
            saved.drakira_orig_buffs, saved.drakira_created = nil, nil
        end,
    },

    -- ============================================================
    -- Waystalker: Ricochet — 3 → 5 bounces (+ FF safety hook)
    -- ============================================================
    -- Talent `kerillian_waywatcher_projectile_ricochet` (level 20, col 2).
    -- Vanilla bounce buff has `bonus = 3` consumed by
    -- player_projectile_unit_extension.lua:986 via
    -- `apply_buffs_to_value(buffed_bounces, "projectile_bounces")`. Simple
    -- patch lifts it to 5. Bounced projectiles route through `hit_player()`
    -- when they touch teammates, which already gates friendly fire via
    -- `DamageUtils.allow_friendly_fire_ranged(...)` — so vanilla bounces are
    -- already FF-respecting by architecture. NOTE (issue 443 audit): no extra
    -- FF-skip hook was ever shipped for this rework — bounces follow the
    -- difficulty's normal friendly-fire rules; do not document a no-FF
    -- guarantee anywhere.
    rework_we_waywatcher_ricochet_no_ff_5_bounces = {
        character = "kerillian",
        career    = "we_waywatcher",
        patches   = {
            { buff = "kerillian_waywatcher_projectile_ricochet", field = "bonus", value = 5 },
        },
        custom_apply = function(saved)
            if not Talents or not TalentIDLookup then return end
            local lookup = TalentIDLookup["kerillian_waywatcher_projectile_ricochet"]
            if not lookup then return end
            local talent = Talents[lookup.hero_name] and Talents[lookup.hero_name][lookup.talent_id]
            local dv = talent and talent.description_values and talent.description_values[1]
            if not dv then return end
            saved.ricochet_orig = dv.value
            dv.value = 5
        end,
        custom_restore = function(saved)
            if saved.ricochet_orig == nil then return end
            if not Talents or not TalentIDLookup then return end
            local lookup = TalentIDLookup["kerillian_waywatcher_projectile_ricochet"]
            if not lookup then return end
            local talent = Talents[lookup.hero_name] and Talents[lookup.hero_name][lookup.talent_id]
            local dv = talent and talent.description_values and talent.description_values[1]
            if not dv then return end
            dv.value = saved.ricochet_orig
            saved.ricochet_orig = nil
        end,
    },

    -- ============================================================
    -- Necromancer: Death Ascendant — stack duration 6s → 10s
    -- ============================================================
    -- Talent `sienna_necromancer_5_1` (level 25). Attached buff
    -- `sienna_necromancer_5_1_buff` has `duration = 6` (merged from
    -- SHOVEL_BUFF_TWEAK_DATA at boot). max_stacks = 1, refresh_durations =
    -- true, stat_buff = "cooldown_regen".
    rework_bw_necromancer_death_ascendant_10s = {
        character = "sienna",
        career    = "bw_necromancer",
        patches   = {
            { buff = "sienna_necromancer_5_1_buff", field = "duration", value = 10 },
        },
    },

    -- ============================================================
    -- Engineer: Ingenious Ordnance (lvl 10) — 80s → 240s tick
    -- ============================================================
    -- Talent `bardin_engineer_improved_explosives` (row 2). Vanilla grants a
    -- weak crafted bomb every 80s via the `bardin_engineer_bomb_grant` proc
    -- attached to buff `bardin_engineer_2_1_cooldown` (duration field 80,
    -- merged from buff_tweak_data). Rework lifts tick interval to 240s.
    -- NOTE: the "random regular bomb" portion (frag/fire instead of the
    -- weak crafted) requires overriding the bomb-grant proc — deferred for
    -- the next iteration. This v1 only changes the interval; user keeps the
    -- weak crafted bomb but receives it less frequently. Will follow up
    -- once we confirm desired bomb pool semantics.
    rework_dr_engineer_ingenious_ordnance_240s = {
        character = "bardin",
        career    = "dr_engineer",
        patches   = {
            { buff = "bardin_engineer_2_1_cooldown", field = "duration", value = 240 },
        },
    },

    -- ============================================================
    -- Engineer: Leading Shots (legacy talent restore) — replaces Ingenious Ordnance
    -- ============================================================
    -- Restores the pre-Patch-5.2.0 "Leading Shots": every 4th ranged shot is a
    -- GUARANTEED CRIT. Replaces the Ingenious Ordnance talent
    -- (bardin_engineer_improved_explosives, level-10 slot [2,1]).
    --
    -- Crank Gun: the Steam-Assisted Crank Gun career skill uses NO ammo, so we
    -- count on `on_hit` filtered to ranged projectile attack types (NOT
    -- on_ammo_used, which the ammo-less Crank Gun never fires). The Crank Gun's
    -- bullets are ranged projectiles → they DO trigger on_hit → they count.
    --
    -- Chain (all STOCK buff funcs — no custom code):
    --   counter (add_buff_on_first_target_hit, on_hit, ranged-only) -> adds a
    --   stack of accumulator each ranged shot -> accumulator (max_stacks 4,
    --   reset_on_max) -> on the 4th grants the crit buff -> crit buff
    --   (guaranteed_crit perk, consumed on the next on_critical_action).
    -- Modeled on Mercenary Paced Strikes + the engineer's own Scavenged-Shot
    -- accumulator (talent_settings_cog_dwarf_ranger.lua:331-360).
    --
    -- Additive: the OTHER 3 shots keep their normal random crit chance (the
    -- faithful "removes random crit" needs a crit-resolver hook; not done).
    -- Mutually-soft with rework_dr_engineer_ingenious_ordnance_240s: when this is
    -- ON the talent no longer references bardin_engineer_2_1_cooldown, so the 240s
    -- toggle has no visible effect (no crash — they touch different things).
    rework_dr_engineer_leading_shots = {
        character = "bardin",
        career    = "dr_engineer",
        patches   = {},
        custom_apply = function(saved)
            local buff_perks = require("scripts/unit_extensions/default_player_unit/buffs/settings/buff_perk_names")
            local AT = rawget(_G, "AttackTypes")
            if not (BuffTemplates and buff_perks and AT) then return end

            -- Ranged projectile shots only (covers the Crank Gun; excludes melee + grenades).
            local ranged_only = {
                [AT.projectile] = true,
                [AT.instant_projectile] = true,
                [AT.heavy_instant_projectile] = true,
            }

            local function _ensure(name, def)
                if BuffTemplates[name] == nil or BuffTemplates[name]._crt_pending then
                    BuffTemplates[name] = def
                    saved["ls_created_" .. name] = true
                end
            end

            _ensure("crt_engineer_leading_shots_counter", {
                buffs = { {
                    name               = "crt_engineer_leading_shots_counter",
                    buff_func          = "add_buff_on_first_target_hit",
                    buff_to_add        = "crt_engineer_leading_shots_accumulator",
                    event              = "on_hit",
                    valid_attack_types = ranged_only,
                    client_side        = true,
                } },
            })
            _ensure("crt_engineer_leading_shots_accumulator", {
                buffs = { {
                    name                = "crt_engineer_leading_shots_accumulator",
                    icon                = "bardin_engineer_ranged_crit_count",
                    max_stacks          = 4,
                    on_max_stacks_func  = "add_remove_buffs",
                    reset_on_max_stacks = true,
                    max_stack_data      = { buffs_to_add = { "crt_engineer_leading_shots_crit" } },
                } },
            })
            _ensure("crt_engineer_leading_shots_crit", {
                buffs = { {
                    name           = "crt_engineer_leading_shots_crit",
                    buff_func      = "dummy_function",
                    event          = "on_critical_action",
                    icon           = "bardin_engineer_ranged_crit_count",
                    max_stacks     = 1,
                    priority_buff  = true,
                    remove_on_proc = true,
                    perks          = { buff_perks.guaranteed_crit },
                } },
            })

            -- Repoint the Ingenious Ordnance talent at the Leading Shots counter.
            if not (Talents and TalentIDLookup) then return end
            local lookup = TalentIDLookup["bardin_engineer_improved_explosives"]
            if not lookup then return end  -- non-COG owner: talent absent → no-op
            local talent = Talents[lookup.hero_name] and Talents[lookup.hero_name][lookup.talent_id]
            if not talent then return end

            saved.ls_buffs = talent.buffs
            saved.ls_icon  = talent.icon
            saved.ls_desc  = talent.description
            saved.ls_dv    = talent.description_values
            saved.ls_dname = talent.display_name  -- usually nil (vanilla talent has only `name`)
            talent.buffs              = { "crt_engineer_leading_shots_counter" }
            talent.icon               = "bardin_engineer_ranged_crit_count"
            -- Title resolves as Localize(display_name or name) (hero_window_talents.lua:328);
            -- the vanilla `name` still localizes to "Ingenious Ordnance", so set
            -- display_name (it takes precedence) to show "Leading Shots".
            talent.display_name       = "crt_engineer_leading_shots_name"
            talent.description        = "crt_engineer_leading_shots_desc"
            talent.description_values = { { value = 4 } }
        end,
        custom_restore = function(saved)
            if Talents and TalentIDLookup then
                local lookup = TalentIDLookup["bardin_engineer_improved_explosives"]
                local talent = lookup and Talents[lookup.hero_name] and Talents[lookup.hero_name][lookup.talent_id]
                if talent and saved.ls_buffs then
                    talent.buffs              = saved.ls_buffs
                    talent.icon               = saved.ls_icon
                    talent.display_name       = saved.ls_dname
                    talent.description        = saved.ls_desc
                    talent.description_values = saved.ls_dv
                end
            end
            if BuffTemplates then
                for _, n in ipairs({
                    "crt_engineer_leading_shots_counter",
                    "crt_engineer_leading_shots_accumulator",
                    "crt_engineer_leading_shots_crit",
                }) do
                    if saved["ls_created_" .. n] then BuffTemplates[n] = _crt_make_stub() end
                end
            end
            saved.ls_buffs, saved.ls_icon, saved.ls_desc, saved.ls_dv, saved.ls_dname = nil, nil, nil, nil, nil
        end,
    },

    -- ============================================================
    -- Engineer: Full Head of Steam — 15% → 4% AS per pump stack
    -- ============================================================
    -- Best match: `bardin_engineer_power_on_max_pump` talent (row 4 col 1)
    -- attaches buff `bardin_engineer_4_1_buff` with stat_buff =
    -- "attack_speed", multiplier 0.15 (merged from
    -- buff_tweak_data.bardin_engineer_power_on_max_pump_buff.multiplier).
    -- Rework drops it to 0.04 per stack. NOTE: vanilla talent name is "power
    -- on max pump" — the user's "Full Head of Steam" likely refers to the
    -- same talent's in-game display name. Verify in-game.
    rework_dr_engineer_full_head_of_steam_4pct = {
        character = "bardin",
        career    = "dr_engineer",
        patches   = {
            { buff = "bardin_engineer_4_1_buff", field = "multiplier", value = 0.04 },
        },
        custom_apply = function(saved)
            if not Talents or not TalentIDLookup then return end
            local lookup = TalentIDLookup["bardin_engineer_power_on_max_pump"]
            if not lookup then return end
            local talent = Talents[lookup.hero_name] and Talents[lookup.hero_name][lookup.talent_id]
            local dv = talent and talent.description_values
            if not dv then return end
            -- The talent has one or two description_values; rewrite the one
            -- that holds the AS multiplier (typically [2] when the stack
            -- count is [1], but be defensive).
            for i = 1, #dv do
                if dv[i] and dv[i].value == 0.15 then
                    saved["fhos_dv_" .. i] = dv[i].value
                    dv[i].value = 0.04
                end
            end
        end,
        custom_restore = function(saved)
            if not Talents or not TalentIDLookup then return end
            local lookup = TalentIDLookup["bardin_engineer_power_on_max_pump"]
            if not lookup then return end
            local talent = Talents[lookup.hero_name] and Talents[lookup.hero_name][lookup.talent_id]
            local dv = talent and talent.description_values
            if not dv then return end
            for k, v in pairs(saved) do
                local i = tonumber(string.match(k, "^fhos_dv_(%d+)$"))
                if i and dv[i] then dv[i].value = v end
                if i then saved[k] = nil end
            end
        end,
    },

    -- ============================================================
    -- Universal: Mainstay — +15% stagger power for all careers
    -- ============================================================
    -- No talent literally named "Mainstay" exists in the decompiled source.
    -- Implementation: register a universal `crt_mainstay_universal_stagger`
    -- buff (`power_level_impact` stat_buff, multiplier 0.15) once at first
    -- apply; the runtime hook below on `TalentExtension:apply_buffs_from_talents`
    -- adds the buff to every player whenever the toggle is on, regardless of
    -- career or talent selection. Effective universal +15% stagger.
    rework_general_mainstay_stagger_15pct = {
        character = "any",
        career    = "any",
        patches   = {},
        custom_apply = function(saved)
            if not BuffTemplates then return end
            if BuffTemplates.crt_mainstay_universal_stagger == nil or BuffTemplates.crt_mainstay_universal_stagger._crt_pending then
                BuffTemplates.crt_mainstay_universal_stagger = {
                    buffs = {
                        {
                            stat_buff  = "power_level_impact",
                            multiplier = 0.15,
                            max_stacks = 1,
                            name       = "crt_mainstay_universal_stagger",
                        },
                    },
                }
                saved.mainstay_created = true
            end
        end,
        custom_restore = function(saved)
            if saved.mainstay_created and BuffTemplates then
                BuffTemplates.crt_mainstay_universal_stagger = _crt_make_stub()
            end
            saved.mainstay_created = nil
        end,
    },
}

    return BALANCE_MODS
end

return build
