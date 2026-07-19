local mod = get_mod("crt")

-- Behavior-preserving extraction from career_tweaker_balance.lua.
-- Owns hook-only talent presentation, crit policy, and hot-join wire safety.

-- The policy module is engine-free and stateless; each consumer instantiates
-- its own copy via mod:dofile (same pattern as _crt_foot_knight.lua).
local foot_knight_policy = mod:dofile("scripts/mods/career_tweaker/_crt_foot_knight_policy")
local wire_policy = mod._crt.wire_policy

local _HELLBORGS_CRIT_PENALTY = 0.10

-- ============================================================
-- Hook: per-career suppression of the no_random_crits perk
-- ============================================================
-- The Zealot (Smite) and Mercenary (Hellborg's Tutelage) "crit every 5 hits"
-- talents both attach the perk { "no_random_crits" }. ActionUtils.is_critical_strike
-- short-circuits the chance roll to false when this perk is present.
--
-- The hook differentiates by `self._career_name`: each rework toggle only
-- suppresses the perk for its own career, so Zealot's setting doesn't lift
-- Mercenary's restriction and vice versa. Both hooks idempotently re-read
-- mod:get() on every call, so toggling takes effect on the next attack.
mod:hook("TalentExtension", "has_talent_perk", function(func, self, perk)
    if perk == "no_random_crits" then
        local career = self._career_name
        if career == "wh_zealot" and mod:get("rework_wh_zealot_smite_random_crits") then
            return false
        end
        if career == "es_mercenary" and mod:get("rework_es_mercenary_hellborgs_tutelage") then
            return false
        end
    end
    return func(self, perk)
end)

-- ============================================================
-- Hook: Hellborg's Tutelage random crit-chance reduction
-- ============================================================
-- When the rework is active and the player is on Mercenary with Hellborg's
-- Tutelage (`markus_mercenary_crit_count`) selected, subtract
-- _HELLBORGS_CRIT_PENALTY from the final crit chance after vanilla buffs run.
-- The has_talent_perk hook above lifts the hard-zero short-circuit; this hook
-- supplies the trade-off (a smaller pool of random crits instead of none).
--
-- ActionUtils is a plain global table, so use table-form hooking per
-- CLAUDE.md hooking rules and docs/engine/10 ("plain-table target: hook at file
-- load, not lazily"). Table-form can't hook a nil target, so the presence guard
-- stays; in practice the helpers file loads at game boot, long before any VMF
-- mod, so this installs every session. Issue 507: to catch a future load-order
-- shift that would make ActionUtils absent at crt load (silent feature-loss --
-- the hook would just be skipped), we record whether it installed. The
-- /crt_regression_test check `crt_hellborgs_crit_hook_installed` fails loudly if
-- this marker is ever false, and the else-branch logs the loss at runtime.
if ActionUtils and ActionUtils.get_critical_strike_chance then
    mod:hook(ActionUtils, "get_critical_strike_chance", function(func, unit, action, overrides)
        local chance = func(unit, action, overrides)
        if not mod:get("rework_es_mercenary_hellborgs_tutelage") then
            return chance
        end
        local talent_ext = ScriptUnit.has_extension(unit, "talent_system")
        if not talent_ext or talent_ext._career_name ~= "es_mercenary" then
            return chance
        end
        if not talent_ext:has_talent("markus_mercenary_crit_count") then
            return chance
        end
        local reduced = chance - _HELLBORGS_CRIT_PENALTY
        if reduced < 0 then reduced = 0 end
        return reduced
    end)
    mod._crt_hellborgs_crit_hook_installed = true
else
    mod._crt_hellborgs_crit_hook_installed = false
    pcall(printf, "[crt] WARNING ActionUtils.get_critical_strike_chance unavailable at load; Hellborg's Tutelage crit-chance reduction is INACTIVE this session (load-order shift)")
end

-- ============================================================
-- Hook: _G.Localize override for Hellborg's Tutelage description
-- ============================================================
-- The vanilla talent description text is rendered through Localize() and then
-- post-formatted by UIUtils.format_localized_description with the talent's
-- `description_values`. Mercenary crit_count has one description value
-- (buff_on_stacks = 5), so the override string takes one %d slot. Literal
-- percent signs MUST be `%%` because the result is re-fed through string.format
-- — a bare `%` becomes "[Invalid String Format]". See
-- feedback_vt2_localize_string_format_pipeline.md.
local _HELLBORGS_DESC_OVERRIDE =
    "Critical Strike every %d melee hits. Random Critical Strike chance reduced by 10%%."

-- ============================================================
-- Talent description text overrides (centralised Localize hook)
-- ============================================================
-- When a rework toggle is active, the vanilla talent description in the
-- inventory tooltip should reflect the NEW mechanic, not the vanilla one.
-- VT2 reads `Localize("<talent_name>_desc")` for the text, then formats it
-- via string.format with the talent's description_values. So:
--   * Literal `%` MUST be `%%` (else "[Invalid String Format]" - see
--     feedback_vt2_localize_string_format_pipeline.md).
--   * If a vanilla desc uses %s/%d placeholders, replace them with concrete
--     values or keep placeholders that match the rewritten description_values.
-- Single lookup table keyed by each talent's authored `description` field.
-- Most entries pair one setting id with a static override; composed mechanics
-- may instead provide live `enabled` / `text` functions. ALL reworks share the
-- same Localize hook
-- below (per `feedback_vmf_hook_safe_no_chain.md` two hooks on _G.Localize
-- would silently shadow).
local CRT_DESC_OVERRIDES = {
    -- ------ Universal ------
    ["markus_mercenary_crit_count_desc"] = {
        setting = "rework_es_mercenary_hellborgs_tutelage",
        text = _HELLBORGS_DESC_OVERRIDE,
    },
    -- ------ Bardin: Ranger Veteran ------
    ["bardin_ranger_reduced_damage_taken_headshot_desc"] = {
        setting = "rework_dr_ranger_exuberance_stacking_dr",
        text = "Ranged headshots reduce damage taken by 6%% for 7 seconds, stacking up to 5 times. Taking damage removes 1 stack.",
    },
    -- ------ Bardin: Slayer ------
    ["bardin_slayer_passive_stacking_damage_desc"] = {
        setting = "rework_dr_slayer_trophy_hunter_30_stacks_bundle",
        text = "Hitting an enemy grants 1%% melee damage for 2 seconds, stacking up to 30 times.",
    },
    -- ------ Bardin: Outcast Engineer ------
    -- NOTE: bardin_engineer_4_1_buff is a FLAT max_stacks=1 buff granted while
    -- the pump gauge sits at maximum (talent_settings_cog_dwarf_ranger.lua:140-153,
    -- 361-368) -- it is NOT per pump stack.
    ["bardin_engineer_power_on_max_pump_desc"] = {
        setting = "rework_dr_engineer_full_head_of_steam_4pct",
        text = "Attack speed is increased by 4%% while pressure is at maximum.",
    },
    -- Leading Shots (replaces Ingenious Ordnance). The talent UI resolves the
    -- title + description via the GLOBAL Localize, which does NOT see crt's
    -- _localization.lua keys (VMF mod-loc scope) — so the talent's
    -- display_name/description keys must be supplied HERE, through the shared
    -- _G.Localize hook, like every other rework. The "4" is hardcoded (no %s) to
    -- match the other entries and skip the string.format path entirely.
    -- See TALENT_TEXT_RENDERING.md for the full mechanism.
    ["crt_engineer_leading_shots_name"] = {
        setting = "rework_dr_engineer_leading_shots",
        text = "Leading Shots",
    },
    ["crt_engineer_leading_shots_desc"] = {
        setting = "rework_dr_engineer_leading_shots",
        text = "After 4 ranged attacks, the next ranged attack is a guaranteed Critical Strike. Crank Gun shots count too.",
    },
    -- ------ Kruber: Huntsman ------
    ["markus_huntsman_passive_crit_aura_desc"] = {
        setting = "rework_es_huntsman_crit_aura_unlimited_range",
        text = "Grants 5%% critical strike chance to all allies at any distance.",
    },
    -- ------ Kruber: Foot Knight ------
    ["markus_knight_passive_block_cost_aura_desc_2"] = {
        enabled = function()
            return foot_knight_policy.talent_description(
                foot_knight_policy.ROCK_DESCRIPTION_KEY,
                function(setting_id) return mod:get(setting_id) end) ~= nil
        end,
        text = function()
            return foot_knight_policy.talent_description(
                foot_knight_policy.ROCK_DESCRIPTION_KEY,
                function(setting_id) return mod:get(setting_id) end)
        end,
    },
    ["markus_knight_damage_taken_ally_proximity_desc_2"] = {
        enabled = function()
            return foot_knight_policy.talent_description(
                foot_knight_policy.TEAMWORK_DESCRIPTION_KEY,
                function(setting_id) return mod:get(setting_id) end) ~= nil
        end,
        text = function()
            return foot_knight_policy.talent_description(
                foot_knight_policy.TEAMWORK_DESCRIPTION_KEY,
                function(setting_id) return mod:get(setting_id) end)
        end,
    },
    ["markus_knight_free_pushes_on_block_desc"] = {
        setting = "rework_es_knight_counter_punch_stagger_stack",
        text = "Blocking an attack grants 30%% stagger power for 5 seconds, stacking up to 5 times.",
    },
    ["markus_knight_wide_charge_desc"] = {
        setting = "rework_es_knight_valiant_charge_great_foes_45s_battering_ram_30s",
        text = "Valiant Charge is wider and its cooldown is reduced from 45 to 30 seconds.",
    },
    -- ------ Kruber: Mercenary ------
    ["markus_mercenary_passive_defence_on_proc_desc"] = {
        setting = "rework_es_mercenary_blade_barrier_60x_minus_10_on_hit",
        text = "Killing an enemy reduces damage taken by 0.5%%, stacking up to 60 times. Taking damage removes 10 stacks.",
    },
    ["markus_mercenary_passive_improved_desc"] = {
        setting = "rework_es_mercenary_enhanced_training_tiered",
        text = "Paced Strikes triggers on hitting 2 or more enemies in one strike. Each enemy hit grants 5%% attack speed for 6 seconds, up to 4 stacks.",
    },
    -- ------ Kruber: Grail Knight ------
    ["markus_questing_knight_kills_buff_power_stacking_desc"] = {
        setting = "rework_es_questingknight_virtue_of_ideal_3pct_per_kill",
        text = "Killing an enemy grants 3%% power for 10 seconds, stacking up to 10 times. Each stack expires on its own timer.",
    },
    ["markus_questing_knight_parry_increased_power_desc"] = {
        setting = "rework_es_questingknight_virtue_of_discipline_double_parry",
        text = "The timing window for a parry is doubled to 1 second. Parries no longer grant power.",
    },
    -- NOTE: the vanilla movespeed buff keeps its ability-kill-only trigger
    -- (markus_questing_knight_ability_kill_buff_func gates on the career skill
    -- weapon, buff_settings_lake.lua:328-343); the crt AS/power procs fire on
    -- ANY kill. The description reflects that split.
    ["markus_questing_knight_ability_buff_on_kill_desc"] = {
        setting = "rework_es_questingknight_virtue_of_impetuous_buffed",
        text = "Killing an enemy grants 20%% attack speed and 20%% power for 20 seconds. Career Skill kills also grant 20%% movement speed for 20 seconds.",
    },
    -- ------ Kerillian: Waystalker ------
    ["kerillian_waywatcher_attack_speed_on_ranged_headshot_desc"] = {
        setting = "rework_we_waywatcher_drakiras_alacrity_passive_as",
        text = "Increases attack speed by 10%%.",
    },
    ["kerillian_waywatcher_movement_speed_on_special_kill_desc"] = {
        setting = "rework_we_waywatcher_fervent_huntress_passive_ms",
        text = "Increases movement speed by 10%%.",
    },
    ["kerillian_waywatcher_projectile_ricochet_desc"] = {
        setting = "rework_we_waywatcher_ricochet_no_ff_5_bounces",
        text = "Arrows bounce up to 5 times, hitting additional enemies.",
    },
    ["kerillian_waywatcher_activated_ability_restore_ammo_on_career_skill_special_kill_desc"] = {
        setting = "rework_we_waywatcher_kurnous_reward_5pct",
        text = "Killing a Special or Elite with the Career Skill restores 5%% of maximum ammunition.",
    },
    ["kerillian_maidenguard_versatile_dodge_desc"] = {
        setting = "rework_we_maidenguard_dance_of_blades",
        text = "Killing an enemy grants 2%% damage and increases damage taken by 2%% for 2 seconds, stacking up to 15 times. Each stack expires independently; dodging while blocking increases dodge distance by 20%%.",
    },
    -- ------ Kerillian: Shade ------
    ["kerillian_shade_activated_ability_phasing_desc"] = {
        setting = "rework_we_shade_hungry_wind_buffed",
        text = "Leaving stealth grants 20%% movement speed and 20%% power for 20 seconds.",
    },
    -- ------ Victor: Zealot ------
    ["victor_zealot_passive_increased_damage_desc"] = {
        setting = "rework_wh_zealot_fiery_faith_1pct_per_5_hp_max_30",
        text = "Gain 1%% power for every 5 health missing, stacking up to 30 times.",
    },
    -- NOTE: the rework counts 30 missing health per stack (chunk_size 30), which
    -- is NOT one Fiery Faith stack (5 HP per stack) -- the old text was wrong.
    ["victor_zealot_attack_speed_on_health_percent_desc"] = {
        setting = "rework_wh_zealot_castigate_4pct_as_per_fiery_faith",
        text = "Gain 4%% attack speed for every 30 health missing, stacking up to 5 times.",
    },
    ["victor_zealot_passive_healing_received_desc"] = {
        setting = "rework_wh_zealot_holy_fortitude_30_max_hp",
        text = "Increases max health by 30.",
    },
    -- ------ Victor: Bounty Hunter ------
    -- Issue 443: talent descriptions must not restate the talent title, must not
    -- mention which effects the mod made innate, and follow the 10 style rules
    -- (max 2 sentences, no +/-, no brackets, literal numbers, plain English).
    ["victor_bountyhunter_weapon_swap_buff_desc"] = {
        setting = "rework_wh_bountyhunter_blessed_combat_25_and_passive_melee_reset",
        text = "Melee strikes grant 25%% ranged power and ranged strikes grant 25%% melee power, stacking up to 6 times each. Melee killing blows reset the cooldown of Blessed Shots.",
    },
    ["victor_bountyhunter_party_movespeed_on_ranged_crit_desc"] = {
        setting = "rework_wh_bountyhunter_rile_the_mob_movement",
        text = "Increases movement speed by 10%%.",
    },
    -- Vanilla data: the elite ammo restore is 20%% of max ammo (buff_tweak_data
    -- victor_bountyhunter_restore_ammo_on_elite_kill.ammo_bonus_fraction = 0.2,
    -- talent_settings_victor.lua:127-129) and the vanilla proc gates only on
    -- breed.elite, not on melee (buff_templates.lua:3031-3060). The old "5%%,
    -- melee Elite kills" text was wrong on both counts.
    ["victor_bountyhunter_reload_on_kill_desc"] = {
        setting = "rework_wh_bountyhunter_salvaged_ammo_no_gate_and_passive_reload",
        text = "Melee killing blows reload your ranged weapon. Killing an Elite restores 20%% of maximum ammunition.",
    },
    ["victor_bountyhunter_stacking_damage_reduction_on_elite_or_special_kill_desc"] = {
        setting = "rework_wh_bountyhunter_job_well_done_passive_and_special_kill_dr",
        text = "Killing a Special reduces damage taken by 5%% for 60 seconds, stacking up to 6 times. Taking damage removes 1 stack.",
    },
    -- Vanilla Just Reward: on_critical_hit proc, non-melee attack types only,
    -- refunds template.multiplier = 0.2 of the ability cooldown, gated to once
    -- per template.cooldown seconds (buff_templates.lua:3593-3614; tweak data
    -- talent_settings_victor.lua:134-137). The rework only shortens the gate.
    ["victor_bountyhunter_activated_ability_reset_cooldown_on_stacks_2_desc"] = {
        setting = "rework_wh_bountyhunter_just_reward_5s_cooldown",
        text = "Ranged critical strikes reduce the cooldown of Locked and Loaded by 20%%. Can only trigger once every 5 seconds.",
    },
    ["victor_bountyhunter_activated_ability_railgun_desc_2"] = {
        setting = "rework_wh_bountyhunter_double_shotted_damage_double",
        text = "Headshots with Locked and Loaded refund part of its cooldown. Activating Locked and Loaded also grants 100%% ranged power for 3 seconds.",
    },
    ["victor_bountyhunter_activated_ability_blast_shotgun_desc"] = {
        setting = "rework_wh_bountyhunter_indiscriminate_blast_refund_per_kill",
        text = "Locked and Loaded fires a blast of shot. Hitting 4 or more enemies reduces its cooldown by 25%% and each enemy killed refunds 1%% more.",
    },
    -- ------ Victor: Warrior Priest ------
    ["victor_priest_6_1_desc"] = {
        setting = "rework_wh_priest_shield_of_faith_10s_110s_cd_plus_unyielding_20s",
        text = "Shield of Faith lasts 20 seconds longer.",
    },
    ["victor_priest_5_1_desc"] = {
        setting = "rework_wh_priest_prayer_of_vengeance_self_40_others_20",
        text = "You deal 40%% increased damage to Monsters. Nearby allies deal 20%% increased damage to Monsters.",
    },
    -- ------ Sienna: Battle Wizard ------
    -- Vanilla stat is increased_burn_dot_damage (burn damage over time dealt),
    -- NOT damage taken by burning enemies (talent_settings_sienna.lua:732-745).
    ["sienna_adept_increased_burn_damage_reduced_non_burn_damage_desc"] = {
        setting = "rework_bw_adept_famished_flames_buffed",
        text = "Increases burn damage over time by 150%%. All other damage is reduced by 30%%.",
    },
    ["sienna_adept_power_level_on_full_charge_desc"] = {
        setting = "rework_bw_adept_volcanic_force_doubled",
        text = "Fully charged spells gain 100%% power.",
    },
    ["sienna_adept_cooldown_reduction_on_burning_enemy_killed_desc"] = {
        setting = "rework_bw_adept_fires_from_ash_1pct_plus_thp",
        text = "Killing a burning enemy reduces Career Skill cooldown by 1%% and grants 0.5 temporary health.",
    },
    -- ------ Sienna: Necromancer ------
    ["sienna_necromancer_4_3_desc"] = {
        setting = "rework_bw_necromancer_withering_touch_30s",
        text = "Hitting an enemy afflicts it with a damage over time effect lasting 30 seconds.",
    },
    ["sienna_necromancer_4_2_desc"] = {
        setting = "rework_bw_necromancer_malediction_5_souls",
        text = "Gathering 5 souls makes your next attack a guaranteed Critical Strike.",
    },
    ["sienna_necromancer_2_1_desc"] = {
        setting = "rework_bw_necromancer_vanhels_per_skeleton_as",
        text = "Gain 2%% attack speed for each skeleton you control, up to 12 stacks.",
    },
    ["sienna_necromancer_5_1_desc"] = {
        setting = "rework_bw_necromancer_death_ascendant_10s",
        text = "The increased cooldown regeneration lasts 10 seconds.",
    },
    ["sienna_necromancer_6_1_desc"] = {
        setting = "rework_bw_necromancer_army_of_dead_buffed",
        text = "Career Skill cooldown is reduced to 55 seconds. The extra skeletons last 40 seconds.",
    },
    -- ------ Sienna: Unchained ------
    ["sienna_unchained_activated_ability_fire_aura_desc"] = {
        setting = "rework_bw_unchained_wildfire_burst_and_radius",
        text = "Career Skill explosion radius is increased by 25%% and its burst damage by 50%%.",
    },
    -- Numb to Pain. NOTE: key is the talent's `description` FIELD
    -- (sienna_unchained_reduced_damage_taken_after_venting_desc_2), which
    -- UIUtils.get_talent_description Localizes -- NOT <talent_name>_desc. The old
    -- entry keyed "..._venting_2_desc" was DEAD (wrong key); fixed here + retext to
    -- the v0.3.36 rework.
    -- The per-stack numbers below track the Unstable Strength rescale toggle
    -- (5%%/10%% when on, 6%%/12%% when off), so these entries use a text
    -- FUNCTION resolved per Localize call (see the hook below).
    ["sienna_unchained_reduced_damage_taken_after_venting_desc_2"] = {
        setting = "rework_bw_unchained_numb_to_pain_4x_burn_kill_lose_on_hit",
        text = function()
            if mod:get("rework_bw_unchained_unstable_strength_rescale") then
                return "Each stack of Unstable Strength reduces damage taken by 5%% and overcharge gained from Blood Magic by 10%%."
            end
            return "Each stack of Unstable Strength reduces damage taken by 6%% and overcharge gained from Blood Magic by 12%%."
        end,
    },
    ["sienna_unchained_reduced_overcharge_desc"] = {
        setting = "rework_bw_unchained_natural_talent_ranged",
        text = function()
            if mod:get("rework_bw_unchained_unstable_strength_rescale") then
                return "Each stack of Unstable Strength grants 5%% ranged power."
            end
            return "Each stack of Unstable Strength grants 6%% ranged power."
        end,
    },
    ["sienna_unchained_exploding_burning_enemies_desc"] = {
        setting = "rework_bw_unchained_chain_reaction_ignite",
        text = "Burning enemies explode on death, staggering and igniting nearby enemies.",
    },
    -- Vanilla Fuel for the Fire: SIENNA gains a power stack per enemy hit by
    -- the ability (5%% for 15s, up to 5x -- talent_settings_sienna.lua:214-218,
    -- 1012-1030); the old "enemies take increased damage" text had it backwards.
    ["sienna_unchained_activated_ability_power_on_enemies_hit_desc"] = {
        setting = "rework_bw_unchained_fuel_for_the_fire_vent",
        text = "Each enemy hit by Career Skill grants 5%% power for 15 seconds, stacking up to 5 times. Career Skill clears only 25%% of your overcharge.",
    },
    -- Flame Unending REPLACES Abandon in the lvl-25 slot. The talent has no
    -- display_name field, so the title resolves via Localize(name) -- override the
    -- name key too. Abandon itself becomes innate (shown as a passive perk).
    ["sienna_unchained_health_to_ult"] = {
        setting = "rework_bw_unchained_abandon_innate_flame_unending",
        text = "Flame Unending",
    },
    -- The buff is cooldown_regen (continuous recharge-rate stat), so the text
    -- says "recharges faster", not "-N%% cooldown" (the old text misstated it
    -- as a flat cooldown cut). Numbers track the Unstable Strength rescale.
    ["sienna_unchained_health_to_ult_desc"] = {
        setting = "rework_bw_unchained_abandon_innate_flame_unending",
        text = function()
            if mod:get("rework_bw_unchained_unstable_strength_rescale") then
                return "Career Skill recharges 5%% faster for each stack of Unstable Strength."
            end
            return "Career Skill recharges 6%% faster for each stack of Unstable Strength."
        end,
    },
    -- Abandon, shown as a passive perk (appended to PassiveAbilitySettings.bw_3.perks
    -- by the rework's custom_apply) while #3 is active. Vanilla Abandon: while
    -- overcharge sits at 40 or more (chunk_size 40), the ability cooldown drains
    -- 10%% per tick at the cost of max_health/20 health per tick
    -- (talent_settings_sienna.lua:974-991, buff_function_templates.lua:4516-4534).
    ["crt_abandon_perk_name"] = {
        setting = "rework_bw_unchained_abandon_innate_flame_unending",
        text = "Abandon",
    },
    ["crt_abandon_perk_desc"] = {
        setting = "rework_bw_unchained_abandon_innate_flame_unending",
        text = "At high overcharge, Career Skill recharges rapidly at the cost of health.",
    },
}

mod:hook(_G, "Localize", function(func, key, ...)
    -- Issue 447: if Devotion resolution was inconclusive at file load, retry
    -- exactly once at the first menu localization, when talent + loc data are
    -- certainly live. try_resolve clears lazy_retry_pending before localizing
    -- anything, so the retry cannot re-enter this hook path.
    local flagellation = mod._crt and mod._crt.flagellation
    if flagellation and flagellation.lazy_retry_pending and flagellation.try_resolve then
        flagellation.try_resolve()
    end
    if type(key) == "string" then
        local extra = mod._crt and mod._crt.extra_desc_overrides
        local entry = CRT_DESC_OVERRIDES[key] or (extra and extra[key])
        local enabled = entry and ((entry.enabled and entry.enabled())
            or (entry.setting and mod:get(entry.setting)))
        if enabled then
            local text = entry.text
            -- Entries whose numbers depend on another toggle store a function
            -- (issue 443); resolve it per call so toggling updates live.
            if type(text) == "function" then
                text = text()
            end
            if text ~= nil then return text end
        end
    end
    return func(key, ...)
end)

-- ============================================================
-- Issue 776: rpc_add_buff receiver floor (UNCONDITIONAL)
-- ============================================================
-- The three attached crash logs received positive server ids 12, 13, and 9 at
-- numeric lookup id 1574, which resolved locally to the timed Impetuous AS buff.
-- Current ProcFunctions.add_buff can only send server id 0, proving this was an
-- unrelated/older sender's numeric-id collision rather than the Impetuous proc
-- itself. The #425 presence beacon could not distinguish that catalog drift.
--
-- This floor owns only ids that resolve LOCALLY to CRT's registered names. It
-- drops them before vanilla when the sender has not proved the exact name+index
-- fingerprint, and independently enforces vanilla's positive-server-id rule:
-- timed sub-buffs are never legal server-controlled buffs. Unrelated names pass
-- through unchanged. Logs are bounded once per reason/template per session.
local _crt_rpc_floor_logged = {}
local function _crt_rpc_floor_log_once(reason, sender_peer_id, template_name,
        lookup_id, server_buff_id)
    local key = tostring(reason) .. ":" .. tostring(template_name)
    if _crt_rpc_floor_logged[key] then return end
    _crt_rpc_floor_logged[key] = true
    pcall(printf,
        "[crt:776] rpc_add_buff dropped reason=%s sender=%s template=%s lookup_id=%s server_buff_id=%s",
        tostring(reason), tostring(sender_peer_id), tostring(template_name),
        tostring(lookup_id), tostring(server_buff_id))
end

mod:hook("BuffSystem", "rpc_add_buff", function(func, self, channel_id, unit_id,
        buff_template_name_id, attacker_unit_id, server_buff_id, send_to_sender)
    local lookup = rawget(_G, "NetworkLookup")
    local buff_lookup = lookup and lookup.buff_templates
    local template_name = buff_lookup and rawget(buff_lookup, buff_template_name_id)
    local registry = mod._crt_mod_registered_buff_names
    local resolves_to_crt = type(template_name) == "string"
        and ((registry and registry[template_name]) or template_name:sub(1, 4) == "crt_")

    if resolves_to_crt and wire_policy then
        local channel_peers = rawget(_G, "CHANNEL_TO_PEER_ID")
        local sender_peer_id = channel_peers and channel_peers[channel_id]
        local parity = mod._crt_peer_parity
        local peer_catalog_exact = false
        if type(sender_peer_id) == "string" and parity ~= nil
                and type(parity.peer_has) == "function" then
            local ok, exact = pcall(parity.peer_has, parity, sender_peer_id)
            peer_catalog_exact = ok and exact == true
        end
        local templates = rawget(_G, "BuffTemplates")
        local template = templates and rawget(templates, template_name)
        local decision = wire_policy.rpc_add_buff_decision({
            resolves_to_crt = true,
            peer_catalog_exact = peer_catalog_exact,
            server_buff_id = server_buff_id,
            template = template,
        })
        if decision ~= "accept" then
            _crt_rpc_floor_log_once(decision, sender_peer_id, template_name,
                buff_template_name_id, server_buff_id)
            return
        end
    end

    return func(self, channel_id, unit_id, buff_template_name_id,
        attacker_unit_id, server_buff_id, send_to_sender)
end)
mod._crt_rpc_add_buff_floor_installed = true

-- ============================================================
-- Issue 425: hot-join replay filter (sender-side, UNCONDITIONAL)
-- ============================================================
-- BuffSystem.hot_join_sync (buff_system.lua:66-97) replays EVERY entry in
-- server_controlled_buffs to a joining peer via rpc_add_buff, encoding
-- NetworkLookup.buff_templates[template_name] at :87. That replay fires during
-- the join handshake, BEFORE any parity ack can exist for the joiner, so a
-- non-crt joiner would decode a crt_* index and fatal instantly -- no gate that
-- reacts to the roster can win that race. Sender-side filter instead: hide
-- crt_* entries from the one replay pass. A crt-running joiner merely misses
-- the replayed crt stacks; the wire-safe driver strips + re-adds them when
-- parity re-establishes (broadcast reaches the joiner), so state self-heals.
-- The receiver floor above is the only other CRT BuffSystem hook; the two own
-- distinct methods and are installed once by this load-once module.
mod:hook("BuffSystem", "hot_join_sync", function(func, self, peer_id)
    if not self.is_server then
        return func(self, peer_id)
    end
    -- Filter predicate: the mod-registered-name registry (covers tourney's
    -- vanilla-prefixed registrations) plus the crt_ prefix as belt-and-
    -- suspenders for any name registered after this module loaded.
    local registry = mod._crt_mod_registered_buff_names
    local stashed = {}
    pcall(function()
        for _, data in pairs(self.server_controlled_buffs) do
            for sid, bdata in pairs(data) do
                local n = bdata and bdata.template_name
                if type(n) == "string" and ((registry and registry[n]) or n:sub(1, 4) == "crt_") then
                    -- clearing an existing key mid-pairs is legal in Lua 5.1
                    stashed[#stashed + 1] = { data = data, sid = sid, bdata = bdata }
                    data[sid] = nil
                end
            end
        end
    end)
    -- pcall the wrapped sync so the restore below is UNCONDITIONAL -- a throw
    -- mid-replay must not leave the stashed entries permanently hidden (they
    -- would orphan their stacks and dodge later removal). Rethrow afterwards to
    -- preserve vanilla failure semantics.
    local ok, err = pcall(func, self, peer_id)
    for i = 1, #stashed do
        local s = stashed[i]
        s.data[s.sid] = s.bdata
    end
    if #stashed > 0 then
        pcall(printf, "[crt:425] hot-join filter: withheld %d mod buff(s) from replay to joining peer %s (their client may not resolve modded indices)",
            #stashed, tostring(peer_id))
    end
    if not ok then
        error(err, 0)
    end
end)

return true
