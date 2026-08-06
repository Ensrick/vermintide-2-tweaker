-- Behavior-neutral late balance catalogue extracted from career_tweaker_balance.lua.
-- Built through the bounded catalogue composition owner; no hooks or lifecycle callbacks.

local function build(ctx)
    local mod = assert(ctx.mod, "crt late catalog mod required")
    local wire_policy = assert(ctx.wire_policy, "crt late catalog wire_policy required")
    local _crt_make_stub = assert(ctx.make_stub, "crt late catalog make_stub required")
    local _crt_ensure_wire_safe_funcs = assert(ctx.ensure_wire_safe_funcs, "crt late catalog wire helper required")

local BALANCE_MODS = {
    -- ============================================================
    -- Necromancer: Army of the Dead — 110s → 55s cooldown + 20s → 40s decay
    -- ============================================================
    -- Two changes, both touch non-buff fields (custom_apply):
    --   * `ActivatedAbilitySettings.bw_necromancer[1].cooldown` 110 → 55
    --   * `BuffTemplates.sienna_pet_spawn_charge.buffs[1].duration` 20 → 40
    --     (decay duration of the extra AoD skeletons before they despawn)
    rework_bw_necromancer_army_of_dead_buffed = {
        character = "sienna",
        career    = "bw_necromancer",
        patches   = {
            { buff = "sienna_pet_spawn_charge", field = "duration", value = 40 },
        },
        custom_apply = function(saved)
            if ActivatedAbilitySettings and ActivatedAbilitySettings.bw_necromancer and ActivatedAbilitySettings.bw_necromancer[1] then
                saved.aod_cooldown = ActivatedAbilitySettings.bw_necromancer[1].cooldown
                ActivatedAbilitySettings.bw_necromancer[1].cooldown = 55
            end
        end,
        custom_restore = function(saved)
            if saved.aod_cooldown ~= nil and ActivatedAbilitySettings and ActivatedAbilitySettings.bw_necromancer and ActivatedAbilitySettings.bw_necromancer[1] then
                ActivatedAbilitySettings.bw_necromancer[1].cooldown = saved.aod_cooldown
            end
            saved.aod_cooldown = nil
        end,
    },

    -- ============================================================
    -- Zealot: Holy Fortitude (best-guess = lvl 20 healing talent) → +30 max HP
    -- ============================================================
    -- "Holy Fortitude" isn't in the decompiled source by that name. The
    -- closest match is `victor_zealot_passive_healing_received` (level 20,
    -- one of three Zealot row-4 talents). Rework: swap that talent's
    -- payload to a single +30 max HP buff (`max_health` stat_buff, bonus
    -- 30). Original buffs are saved + restored on disable. Note: stat_buff
    -- `max_health` uses `bonus` field for flat additive HP (vanilla VT2
    -- convention).
    rework_wh_zealot_holy_fortitude_30_max_hp = {
        character = "victor",
        career    = "wh_zealot",
        patches   = {},
        custom_apply = function(saved)
            if not BuffTemplates or not Talents or not TalentIDLookup then return end
            if BuffTemplates.crt_zealot_holy_fortitude_max_hp == nil or BuffTemplates.crt_zealot_holy_fortitude_max_hp._crt_pending then
                BuffTemplates.crt_zealot_holy_fortitude_max_hp = {
                    buffs = {
                        {
                            stat_buff  = "max_health",
                            bonus      = 30,
                            max_stacks = 1,
                            name       = "crt_zealot_holy_fortitude_max_hp",
                        },
                    },
                }
                saved.hf_created = true
            end
            local lookup = TalentIDLookup["victor_zealot_passive_healing_received"]
            if lookup then
                local talent = Talents[lookup.hero_name] and Talents[lookup.hero_name][lookup.talent_id]
                if talent and talent.buffs then
                    saved.hf_orig_buffs = {}
                    for i, b in ipairs(talent.buffs) do saved.hf_orig_buffs[i] = b end
                    talent.buffs = { "crt_zealot_holy_fortitude_max_hp" }
                end
            end
        end,
        custom_restore = function(saved)
            if Talents and TalentIDLookup and saved.hf_orig_buffs then
                local lookup = TalentIDLookup["victor_zealot_passive_healing_received"]
                if lookup then
                    local talent = Talents[lookup.hero_name] and Talents[lookup.hero_name][lookup.talent_id]
                    if talent then talent.buffs = saved.hf_orig_buffs end
                end
            end
            if saved.hf_created and BuffTemplates then
                BuffTemplates.crt_zealot_holy_fortitude_max_hp = _crt_make_stub()
            end
            saved.hf_orig_buffs, saved.hf_created = nil, nil
        end,
    },

    -- ============================================================
    -- Slayer: Trophy Hunter bundle — 30 stacks @ 1%/hit + Impatience scale
    -- ============================================================
    -- Trophy Hunter (`bardin_slayer_passive_stacking_damage_buff`) vanilla
    -- is 10% damage per hit × 3 stacks × 2s. Rework: 1% × 30 stacks × 2s
    -- (each stack independent timer remains via vanilla refresh_durations
    -- semantics). Cap stays at +30% damage but ramps in 1% increments
    -- instead of 10% jumps. ALSO patches Impatience-equivalent buff
    -- (`bardin_slayer_passive_increased_max_stacks`) multiplier 0.1 → 0.01
    -- so its bonus scales to the new stack count instead of stacking
    -- ridiculously high (per user spec).
    -- DEFERRED for next pass: (a) "High Tally +10 stacks/kill" — vanilla
    -- increment-per-kill lives in the buff_func code (slayer extension or
    -- buff_function_templates), not in buff_tweak_data; needs proc-hook;
    -- (b) "Adrenaline Surge requires 30 stacks" — the vanilla threshold
    -- check is likely hardcoded against max_stacks, so it MAY auto-scale
    -- when max_stacks is 30 instead of 3, but verify in-game; if not,
    -- needs a separate proc-hook in next pass.
    rework_dr_slayer_trophy_hunter_30_stacks_bundle = {
        character = "bardin",
        career    = "dr_slayer",
        patches   = {
            { buff = "bardin_slayer_passive_stacking_damage_buff",  field = "max_stacks", value = 30   },
            { buff = "bardin_slayer_passive_stacking_damage_buff",  field = "multiplier", value = 0.01 },
            { buff = "bardin_slayer_passive_increased_max_stacks",  field = "multiplier", value = 0.01 },
        },
    },

    -- ============================================================
    -- Slayer: Dawi Drop — airborne damage 150% → 200%
    -- ============================================================
    -- `bardin_slayer_activated_ability_leap_damage_buff.multiplier` 1.5 → 2.0.
    -- DEFERRED for next pass: "airborne time +50%" — no buff template
    -- with an airborne-duration field surfaced in the available decompile.
    -- May live in the Leap action code or jump physics layer.
    rework_dr_slayer_dawi_drop_buffed = {
        character = "bardin",
        career    = "dr_slayer",
        patches   = {
            { buff = "bardin_slayer_activated_ability_leap_damage_buff", field = "multiplier", value = 2.0 },
        },
    },

    -- ============================================================
    -- Slayer: No Escape — ability duration 10s → 15s
    -- ============================================================
    -- `bardin_slayer_activated_ability.duration` 10 → 15. Simple patch.
    rework_dr_slayer_no_escape_15s = {
        character = "bardin",
        career    = "dr_slayer",
        patches   = {
            { buff = "bardin_slayer_activated_ability", field = "duration", value = 15 },
        },
    },

    -- ============================================================
    -- Slayer: Adrenaline Surge nerf — cooldown bonus 200% → 150%
    -- ============================================================
    -- `bardin_slayer_passive_cooldown_reduction_on_max_stacks.multiplier`
    -- 2.0 → 1.5 (cooldown regen rate at max Trophy Hunter stacks).
    rework_dr_slayer_adrenaline_surge_150pct_nerf = {
        character = "bardin",
        career    = "dr_slayer",
        patches   = {
            { buff = "bardin_slayer_passive_cooldown_reduction_on_max_stacks", field = "multiplier", value = 1.5 },
        },
    },

    -- ============================================================
    -- Zealot: Fiery Faith — +1% power per 5 missing HP, max 30 stacks
    -- ============================================================
    -- Vanilla Zealot's missing-HP power scaling (`victor_zealot_passive_increased_damage`
    -- parent + `victor_zealot_passive_damage` child) uses a chunked system:
    -- vanilla chunk_size=25 (every 25 HP missing = 1 stack), max_stacks=6,
    -- multiplier=0.05 per stack (= +30% cap at 150 HP missing). The vanilla
    -- update_func `activate_buff_stacks_based_on_health_chunks` already reads
    -- MISSING hp (via `health_extension:get_damage_taken("uncursed_max_health")`),
    -- so we just shrink the chunk to 5 and widen max_stacks to 30. Multiplier
    -- per stack drops to 0.01 so cap (+30%) stays the same — but ramps in
    -- smoother 1% increments instead of 5% jumps.
    rework_wh_zealot_fiery_faith_1pct_per_5_hp_max_30 = {
        character = "victor",
        career    = "wh_zealot",
        patches   = {
            { buff = "victor_zealot_passive_increased_damage", field = "chunk_size",  value = 5    },
            -- The chunk gate (num_chunks cap) lives on template.max_stacks of the PARENT
            -- (victor_zealot_passive_increased_damage), vanilla = 6. Without widening the
            -- parent too, the documented "30 stacks / +30% cap" is silently gated to 6 (+6%).
            -- No crash here (unlike Castigate -- vanilla parent already has max_stacks=6), but
            -- the same wrong-target class: the gate is on the parent, not the child _buff.
            { buff = "victor_zealot_passive_increased_damage", field = "max_stacks",  value = 30   },
            { buff = "victor_zealot_passive_damage",            field = "max_stacks", value = 30   },
            { buff = "victor_zealot_passive_damage",            field = "multiplier", value = 0.01 },
        },
        custom_apply = function(saved)
            if not Talents or not TalentIDLookup then return end
            local lookup = TalentIDLookup["victor_zealot_passive_increased_damage"]
            if not lookup then return end
            local talent = Talents[lookup.hero_name] and Talents[lookup.hero_name][lookup.talent_id]
            local dv = talent and talent.description_values
            if not dv then return end
            -- Description displays the multiplier and possibly stack count;
            -- rewrite defensively across all description_values entries.
            saved.ff_orig = {}
            for i, entry in ipairs(dv) do
                if type(entry.value) == "number" then
                    saved.ff_orig[i] = entry.value
                end
            end
            if dv[1] then dv[1].value = 0.01 end
            if dv[2] and type(dv[2].value) == "number" then dv[2].value = 30 end
        end,
        custom_restore = function(saved)
            if not Talents or not TalentIDLookup then return end
            local lookup = TalentIDLookup["victor_zealot_passive_increased_damage"]
            if not lookup then return end
            local talent = Talents[lookup.hero_name] and Talents[lookup.hero_name][lookup.talent_id]
            local dv = talent and talent.description_values
            if not dv or not saved.ff_orig then return end
            for i, v in pairs(saved.ff_orig) do
                if dv[i] then dv[i].value = v end
            end
            saved.ff_orig = nil
        end,
    },

    -- ============================================================
    -- Zealot: Castigate — +4% AS per Fiery Faith stack, cap +20% (5 stacks)
    -- ============================================================
    -- Vanilla `victor_zealot_attack_speed_on_health_percent` (talent at row 2)
    -- uses a threshold-based update_func (`victor_zealot_activate_buff_stacks_based_on_health_percent`)
    -- that adds 1 stack at <50% HP and 2 stacks at <20% HP (each = +10% AS).
    -- Rework: switch the update_func to `activate_buff_stacks_based_on_health_chunks`
    -- (same one Fiery Faith uses), with chunk_size = 30 (every 30 HP missing
    -- = 1 stack of Castigate). At 150 HP missing (full Zealot max), that's
    -- 5 stacks; child buff is patched to +4%/stack max 5 = +20% AS cap.
    -- The chunk function reads max-stacks from the template, so even at 30
    -- HP missing the count is gated correctly.
    rework_wh_zealot_castigate_4pct_as_per_fiery_faith = {
        character = "victor",
        career    = "wh_zealot",
        patches   = {
            { buff = "victor_zealot_attack_speed_on_health_percent",        field = "update_func", value = "activate_buff_stacks_based_on_health_chunks" },
            { buff = "victor_zealot_attack_speed_on_health_percent",        field = "chunk_size",  value = 30   },
            -- CRASH FIX (bad argument #2 to 'min'): activate_buff_stacks_based_on_health_chunks
            -- reads max_stacks from buff.template -- the PARENT buff carrying update_func, NOT
            -- the child _buff (buff_function_templates.lua:2591-2596). The vanilla parent used
            -- the threshold update_func and has NO max_stacks field, so without this line
            -- template.max_stacks is nil and `math.min(..., nil)` throws. Mirror the canonical
            -- victor_zealot_passive_move_speed shape: parent carries buff_to_add (vanilla) +
            -- chunk_size + max_stacks + update_func together. 30 HP/chunk * 5 = 150 HP missing.
            { buff = "victor_zealot_attack_speed_on_health_percent",        field = "max_stacks",  value = 5    },
            { buff = "victor_zealot_attack_speed_on_health_percent_buff",   field = "max_stacks",  value = 5    },
            { buff = "victor_zealot_attack_speed_on_health_percent_buff",   field = "multiplier",  value = 0.04 },
        },
        custom_apply = function(saved)
            if not Talents or not TalentIDLookup then return end
            local lookup = TalentIDLookup["victor_zealot_attack_speed_on_health_percent"]
            if not lookup then return end
            local talent = Talents[lookup.hero_name] and Talents[lookup.hero_name][lookup.talent_id]
            local dv = talent and talent.description_values
            if not dv then return end
            saved.cast_orig = {}
            for i, entry in ipairs(dv) do
                if type(entry.value) == "number" then saved.cast_orig[i] = entry.value end
            end
            -- Rewrite per-stack multiplier display if it's the first dv entry.
            if dv[1] and type(dv[1].value) == "number" then dv[1].value = 0.04 end
        end,
        custom_restore = function(saved)
            if not Talents or not TalentIDLookup then return end
            local lookup = TalentIDLookup["victor_zealot_attack_speed_on_health_percent"]
            if not lookup then return end
            local talent = Talents[lookup.hero_name] and Talents[lookup.hero_name][lookup.talent_id]
            local dv = talent and talent.description_values
            if not dv or not saved.cast_orig then return end
            for i, v in pairs(saved.cast_orig) do
                if dv[i] then dv[i].value = v end
            end
            saved.cast_orig = nil
        end,
    },

    -- ============================================================
    -- Grail Knight: Virtue of the Ideal — 3%/kill, max 10, indep. 10s
    -- ============================================================
    -- Vanilla `markus_questing_knight_kills_buff_power_stacking_buff`:
    -- multiplier 0.08, max_stacks 3, duration 10, refresh_durations true.
    -- Rework: 3%/stack, max 10 stacks, 10s INDEPENDENT duration (each stack
    -- expires on its own clock instead of refreshing). Three field patches
    -- plus tooltip rewrites (description_values[1] holds multiplier, [2] the
    -- max stacks; the duration value isn't changed).
    rework_es_questingknight_virtue_of_ideal_3pct_per_kill = {
        character = "markus",
        career    = "es_questingknight",
        patches   = {
            { buff = "markus_questing_knight_kills_buff_power_stacking_buff", field = "multiplier",       value = 0.03 },
            { buff = "markus_questing_knight_kills_buff_power_stacking_buff", field = "max_stacks",       value = 10   },
            { buff = "markus_questing_knight_kills_buff_power_stacking_buff", field = "refresh_durations", value = false },
        },
        custom_apply = function(saved)
            if not Talents or not TalentIDLookup then return end
            local lookup = TalentIDLookup["markus_questing_knight_kills_buff_power_stacking"]
            if not lookup then return end
            local talent = Talents[lookup.hero_name] and Talents[lookup.hero_name][lookup.talent_id]
            local dv = talent and talent.description_values
            if not dv then return end
            if dv[1] then saved.voi_dv1 = dv[1].value; dv[1].value = 0.03 end
            if dv[2] and type(dv[2].value) == "number" then saved.voi_dv2 = dv[2].value; dv[2].value = 10 end
        end,
        custom_restore = function(saved)
            if not Talents or not TalentIDLookup then return end
            local lookup = TalentIDLookup["markus_questing_knight_kills_buff_power_stacking"]
            if not lookup then return end
            local talent = Talents[lookup.hero_name] and Talents[lookup.hero_name][lookup.talent_id]
            local dv = talent and talent.description_values
            if not dv then return end
            if dv[1] and saved.voi_dv1 ~= nil then dv[1].value = saved.voi_dv1 end
            if dv[2] and saved.voi_dv2 ~= nil then dv[2].value = saved.voi_dv2 end
            saved.voi_dv1, saved.voi_dv2 = nil, nil
        end,
    },

    -- ============================================================
    -- Grail Knight: Virtue of Discipline — double parry window, no power
    -- ============================================================
    -- Vanilla `markus_questing_knight_parry_increased_power_buff` grants +20%
    -- power on successful timed block. Rework drops the power bonus
    -- (multiplier → 0) and the parry-window hook below is extended to fire
    -- for GK + this talent (mirrors the existing WHC parry-window mechanism
    -- via `ActionBlock:client_owner_start_action` and `ActionMeleeStart:client_owner_post_update`).
    rework_es_questingknight_virtue_of_discipline_double_parry = {
        character = "markus",
        career    = "es_questingknight",
        patches   = {
            { buff = "markus_questing_knight_parry_increased_power_buff", field = "multiplier", value = 0 },
        },
    },

    -- ============================================================
    -- Grail Knight: Virtue of the Impetuous Knight — 20s + MS/AS/power
    -- ============================================================
    -- Vanilla `markus_questing_knight_ability_buff_on_kill_movement_speed`:
    -- multiplier 1.35 (+35% MS via apply_movement_buff), duration 15s, max 1,
    -- refresh_durations true. Rework:
    --   * Patch movespeed multiplier 1.35 → 1.2 (+20%) and duration 15 → 20s
    --   * Register two new buff templates for AS and power (also +20%, 20s)
    --   * Register two on-kill proc templates that add those buffs through the
    --     native LocalAndServer timed-sync path (#776)
    --   * Append the new procs to the talent's buffs list
    -- Talent name: `markus_questing_knight_ability_buff_on_kill` (lvl 30).
    rework_es_questingknight_virtue_of_impetuous_buffed = {
        character = "markus",
        career    = "es_questingknight",
        -- Issues 425/776: the two on-kill procs synchronize crt_* timed buffs;
        -- exact catalog parity gates the send and their dedicated wrapper uses
        -- add_buff_synced(LocalAndServer), never server-controlled rpc_add_buff.
        -- (The movespeed patch rides a vanilla buff name.)
        network_unsafe = true,
        patches   = {
            { buff = "markus_questing_knight_ability_buff_on_kill_movement_speed", field = "multiplier", value = 1.2 },
            { buff = "markus_questing_knight_ability_buff_on_kill_movement_speed", field = "duration",   value = 20 },
        },
        custom_apply = function(saved)
            if not BuffTemplates or not Talents or not TalentIDLookup then return end
            _crt_ensure_wire_safe_funcs()
            -- AS buff
            if BuffTemplates.crt_questingknight_impetuous_as == nil or BuffTemplates.crt_questingknight_impetuous_as._crt_pending then
                BuffTemplates.crt_questingknight_impetuous_as = {
                    _crt_sync_type = wire_policy.TIMED_SYNC_TYPE,
                    buffs = {
                        wire_policy.make_timed_stat_buff(
                            "crt_questingknight_impetuous_as", "attack_speed", 0.2),
                    },
                }
                saved.imp_created_as = true
            end
            -- Power buff
            if BuffTemplates.crt_questingknight_impetuous_power == nil or BuffTemplates.crt_questingknight_impetuous_power._crt_pending then
                BuffTemplates.crt_questingknight_impetuous_power = {
                    _crt_sync_type = wire_policy.TIMED_SYNC_TYPE,
                    buffs = {
                        wire_policy.make_timed_stat_buff(
                            "crt_questingknight_impetuous_power", "power_level", 0.2),
                    },
                }
                saved.imp_created_power = true
            end
            -- AS proc
            if BuffTemplates.crt_questingknight_impetuous_as_proc == nil or BuffTemplates.crt_questingknight_impetuous_as_proc._crt_pending then
                BuffTemplates.crt_questingknight_impetuous_as_proc = {
                    buffs = {
                        { buff_func = "crt_wire_safe_add_timed_buff", buff_to_add = "crt_questingknight_impetuous_as",
                          event = "on_kill", name = "crt_questingknight_impetuous_as_proc" },
                    },
                }
                saved.imp_created_as_proc = true
            end
            -- Power proc
            if BuffTemplates.crt_questingknight_impetuous_power_proc == nil or BuffTemplates.crt_questingknight_impetuous_power_proc._crt_pending then
                BuffTemplates.crt_questingknight_impetuous_power_proc = {
                    buffs = {
                        { buff_func = "crt_wire_safe_add_timed_buff", buff_to_add = "crt_questingknight_impetuous_power",
                          event = "on_kill", name = "crt_questingknight_impetuous_power_proc" },
                    },
                }
                saved.imp_created_power_proc = true
            end
            -- Append the two new procs to the talent's buffs list
            local lookup = TalentIDLookup["markus_questing_knight_ability_buff_on_kill"]
            if lookup then
                local talent = Talents[lookup.hero_name] and Talents[lookup.hero_name][lookup.talent_id]
                if talent and talent.buffs then
                    saved.imp_orig_count = #talent.buffs
                    local already_as, already_pwr = false, false
                    for _, b in ipairs(talent.buffs) do
                        if b == "crt_questingknight_impetuous_as_proc"    then already_as  = true end
                        if b == "crt_questingknight_impetuous_power_proc" then already_pwr = true end
                    end
                    if not already_as  then table.insert(talent.buffs, "crt_questingknight_impetuous_as_proc")    end
                    if not already_pwr then table.insert(talent.buffs, "crt_questingknight_impetuous_power_proc") end
                end
                -- Tooltip: rewrite multiplier shown (vanilla 1.35 baked %)
                local dv = talent and talent.description_values
                if dv and dv[1] then saved.imp_dv1 = dv[1].value; dv[1].value = 1.2 end
                if dv and dv[2] then saved.imp_dv2 = dv[2].value; dv[2].value = 20  end
            end
        end,
        custom_restore = function(saved)
            if Talents and TalentIDLookup then
                local lookup = TalentIDLookup["markus_questing_knight_ability_buff_on_kill"]
                if lookup then
                    local talent = Talents[lookup.hero_name] and Talents[lookup.hero_name][lookup.talent_id]
                    if talent and talent.buffs and saved.imp_orig_count then
                        while #talent.buffs > saved.imp_orig_count do table.remove(talent.buffs) end
                    end
                    local dv = talent and talent.description_values
                    if dv then
                        if dv[1] and saved.imp_dv1 ~= nil then dv[1].value = saved.imp_dv1 end
                        if dv[2] and saved.imp_dv2 ~= nil then dv[2].value = saved.imp_dv2 end
                    end
                end
            end
            if BuffTemplates then
                if saved.imp_created_as         then BuffTemplates.crt_questingknight_impetuous_as = _crt_make_stub() end
                if saved.imp_created_power      then BuffTemplates.crt_questingknight_impetuous_power = _crt_make_stub() end
                if saved.imp_created_as_proc    then BuffTemplates.crt_questingknight_impetuous_as_proc = _crt_make_stub() end
                if saved.imp_created_power_proc then BuffTemplates.crt_questingknight_impetuous_power_proc = _crt_make_stub() end
            end
            saved.imp_orig_count, saved.imp_dv1, saved.imp_dv2 = nil, nil, nil
            saved.imp_created_as, saved.imp_created_power, saved.imp_created_as_proc, saved.imp_created_power_proc = nil, nil, nil, nil
        end,
    },

    -- Issue #619 runtime-owned Foot Knight mechanics. Empty patch entries keep
    -- these independent toggles in the rework-master catalog; the bounded
    -- owner-local/server-bot state lives in _crt_foot_knight.lua.
    rework_es_knight_innate_uninterruptible_heavies = {
        character = "markus",
        career = "es_knight",
        patches = {},
    },
    rework_es_knight_rock_shield_offense = {
        character = "markus",
        career = "es_knight",
        patches = {},
    },
    rework_es_knight_teamwork_great_weapon_offense = {
        character = "markus",
        career = "es_knight",
        patches = {},
    },
    rework_es_knight_final_march = {
        character = "markus",
        career = "es_knight",
        patches = {},
    },
    rework_es_knight_secondary_melee = {
        character = "markus",
        career = "es_knight",
        patches = {},
    },

    -- ============================================================
    -- Foot Knight: Protective Presence 5m → 10m, Rock of the Reickland → 20m
    -- ============================================================
    -- Vanilla baseline Protective Presence range is carried by the
    -- `markus_knight_passive` proximity driver at 5m. Rock of Reikland adds
    -- two independently-authored 10m drivers: block-cost aura and replacement
    -- defense aura. Rework doubles all three exact range owners so both Rock
    -- effects reach 20m rather than leaving block-cost reduction at 10m.
    rework_es_knight_protective_presence_10m_rock_20m = {
        character = "markus",
        career    = "es_knight",
        patches   = {
            { buff = "markus_knight_passive",                 field = "range", value = 10 },
            { buff = "markus_knight_passive_block_cost_aura", field = "range", value = 20 },
            { buff = "markus_knight_passive_range",           field = "range", value = 20 },
        },
    },

    -- ============================================================
    -- Foot Knight: Valiant Charge 30s → 45s base + Battering Ram returns to 30s
    -- ============================================================
    -- Patch `ActivatedAbilitySettings.es_2[1].cooldown` 30 → 45 in
    -- custom_apply (not a buff template). The hook below
    -- (`CareerExtension:start_activated_ability_cooldown`) detects FK +
    -- Battering Ram (`markus_knight_wide_charge`) + toggle, and refunds 1/3
    -- of the cooldown so the player ends up at 30s effective when they have
    -- Battering Ram selected — preserving the talent's vanilla doubled-width
    -- effect (driven by the talent code path in `career_ability_es_knight.lua`).
    -- DEFERRED: the "always charges through great foes" portion requires
    -- modifying the lunge/collision gate, which lives in lunge_handler / C++
    -- and isn't visible in the available decompile. Queued for next pass.
    rework_es_knight_valiant_charge_great_foes_45s_battering_ram_30s = {
        character = "markus",
        career    = "es_knight",
        patches   = {},
        custom_apply = function(saved)
            if ActivatedAbilitySettings and ActivatedAbilitySettings.es_2 and ActivatedAbilitySettings.es_2[1] then
                saved.vc_cooldown = ActivatedAbilitySettings.es_2[1].cooldown
                ActivatedAbilitySettings.es_2[1].cooldown = 45
            end
        end,
        custom_restore = function(saved)
            if saved.vc_cooldown ~= nil and ActivatedAbilitySettings and ActivatedAbilitySettings.es_2 and ActivatedAbilitySettings.es_2[1] then
                ActivatedAbilitySettings.es_2[1].cooldown = saved.vc_cooldown
            end
            saved.vc_cooldown = nil
        end,
    },

    -- ============================================================
    -- Foot Knight: Counter-Punch — +30%/stack stagger on block, max 5x
    -- ============================================================
    -- The user named "Counter-Punch" maps closest to the level-25 talent
    -- `markus_knight_free_pushes_on_block` (free push on block). Rework
    -- replaces the talent's payload with: each successful block grants
    -- +30% stagger (power_level_impact stat_buff) stacking up to 5x with a
    -- 5-second window per stack (so stacks decay if you don't follow up
    -- the block with an attack/push promptly). Three new buff templates
    -- registered (`crt_knight_counter_punch_stack`, `_proc`); talent's
    -- buffs list is swapped to point at the new proc. NOTE: "consumed on
    -- next attack/push" semantics are approximated as a short window —
    -- precise consume-on-attack semantics would require a separate
    -- on_swing remover proc, not currently implemented.
    rework_es_knight_counter_punch_stagger_stack = {
        character = "markus",
        career    = "es_knight",
        patches   = {},
        custom_apply = function(saved)
            if not BuffTemplates or not Talents or not TalentIDLookup then return end
            if BuffTemplates.crt_knight_counter_punch_stack == nil or BuffTemplates.crt_knight_counter_punch_stack._crt_pending then
                BuffTemplates.crt_knight_counter_punch_stack = {
                    buffs = {
                        {
                            stat_buff  = "power_level_impact",
                            multiplier = 0.30,
                            max_stacks = 5,
                            duration   = 5,
                            refresh_durations = true,
                            name       = "crt_knight_counter_punch_stack",
                        },
                    },
                }
                saved.cp_created_stack = true
            end
            if BuffTemplates.crt_knight_counter_punch_proc == nil or BuffTemplates.crt_knight_counter_punch_proc._crt_pending then
                BuffTemplates.crt_knight_counter_punch_proc = {
                    buffs = {
                        {
                            buff_func   = "add_buff_local",
                            buff_to_add = "crt_knight_counter_punch_stack",
                            event       = "on_block",
                            name        = "crt_knight_counter_punch_proc",
                        },
                    },
                }
                saved.cp_created_proc = true
            end
            local lookup = TalentIDLookup["markus_knight_free_pushes_on_block"]
            if lookup then
                local talent = Talents[lookup.hero_name] and Talents[lookup.hero_name][lookup.talent_id]
                if talent and talent.buffs then
                    saved.cp_orig_buffs = {}
                    for i, b in ipairs(talent.buffs) do saved.cp_orig_buffs[i] = b end
                    talent.buffs = { "crt_knight_counter_punch_proc" }
                end
            end
        end,
        custom_restore = function(saved)
            if Talents and TalentIDLookup and saved.cp_orig_buffs then
                local lookup = TalentIDLookup["markus_knight_free_pushes_on_block"]
                if lookup then
                    local talent = Talents[lookup.hero_name] and Talents[lookup.hero_name][lookup.talent_id]
                    if talent then talent.buffs = saved.cp_orig_buffs end
                end
            end
            if BuffTemplates then
                if saved.cp_created_stack then BuffTemplates.crt_knight_counter_punch_stack = _crt_make_stub() end
                if saved.cp_created_proc  then BuffTemplates.crt_knight_counter_punch_proc = _crt_make_stub() end
            end
            saved.cp_orig_buffs = nil
            saved.cp_created_stack, saved.cp_created_proc = nil, nil
        end,
    },

    -- ============================================================
    -- Warrior Priest: Shield of Faith 10s / 110s CD + Unyielding 20s
    -- ============================================================
    -- Vanilla Shield of Faith (WP career ability) lasts 5s with a 70s
    -- cooldown. Unyielding Blessing (talent `victor_priest_6_1`, level 30)
    -- extends the duration by an additional 10s. Rework triples the package:
    --   * base duration   5 → 10s    (CareerConstants.wh_priest.ability_base_duration)
    --   * cooldown        70 → 110s  (ActivatedAbilitySettings.wh_priest[1].cooldown)
    --   * Unyielding +10  → +20s     (CareerConstants.wh_priest.talent_6_1_improved_ability_duration)
    -- All three patches mutate non-buff-template tables, so the engine's
    -- patches list isn't usable here — everything happens in custom_apply.
    rework_wh_priest_shield_of_faith_10s_110s_cd_plus_unyielding_20s = {
        character = "victor",
        career    = "wh_priest",
        patches   = {},
        custom_apply = function(saved)
            if CareerConstants and CareerConstants.wh_priest then
                saved.sof_base_duration   = CareerConstants.wh_priest.ability_base_duration
                saved.sof_unyielding_bonus = CareerConstants.wh_priest.talent_6_1_improved_ability_duration
                CareerConstants.wh_priest.ability_base_duration            = 10
                CareerConstants.wh_priest.talent_6_1_improved_ability_duration = 20
            end
            if ActivatedAbilitySettings and ActivatedAbilitySettings.wh_priest and ActivatedAbilitySettings.wh_priest[1] then
                saved.sof_cooldown = ActivatedAbilitySettings.wh_priest[1].cooldown
                ActivatedAbilitySettings.wh_priest[1].cooldown = 110
            end
            -- Tooltip rewrite for Unyielding Blessing (talent_6_1)
            if Talents and TalentIDLookup then
                local lookup = TalentIDLookup["victor_priest_6_1"]
                if lookup then
                    local talent = Talents[lookup.hero_name] and Talents[lookup.hero_name][lookup.talent_id]
                    local dv = talent and talent.description_values and talent.description_values[1]
                    if dv then saved.sof_unyielding_tooltip = dv.value; dv.value = 20 end
                end
            end
        end,
        custom_restore = function(saved)
            if CareerConstants and CareerConstants.wh_priest then
                if saved.sof_base_duration    ~= nil then CareerConstants.wh_priest.ability_base_duration            = saved.sof_base_duration end
                if saved.sof_unyielding_bonus ~= nil then CareerConstants.wh_priest.talent_6_1_improved_ability_duration = saved.sof_unyielding_bonus end
            end
            if saved.sof_cooldown ~= nil and ActivatedAbilitySettings and ActivatedAbilitySettings.wh_priest and ActivatedAbilitySettings.wh_priest[1] then
                ActivatedAbilitySettings.wh_priest[1].cooldown = saved.sof_cooldown
            end
            if saved.sof_unyielding_tooltip ~= nil and Talents and TalentIDLookup then
                local lookup = TalentIDLookup["victor_priest_6_1"]
                if lookup then
                    local talent = Talents[lookup.hero_name] and Talents[lookup.hero_name][lookup.talent_id]
                    local dv = talent and talent.description_values and talent.description_values[1]
                    if dv then dv.value = saved.sof_unyielding_tooltip end
                end
            end
            saved.sof_base_duration, saved.sof_unyielding_bonus, saved.sof_cooldown, saved.sof_unyielding_tooltip = nil, nil, nil, nil
        end,
    },

    -- ============================================================
    -- Warrior Priest: Prayer of Vengeance — self +40% / others +20% vs monsters
    -- ============================================================
    -- Talent `victor_priest_5_1` (level 25) applies aura buff
    -- `victor_priest_5_1_buff` (stat_buff = "power_level_large", multiplier
    -- 0.15) to teammates within ~100m. Rework: bump aura multiplier to 0.20
    -- (so everyone gets +20%); ALSO register a self-only +20% buff and append
    -- it to the talent's buffs list so the WP himself gets a stacked +40%
    -- total (0.20 from aura + 0.20 from self-only = +40% additive via
    -- action_utils.lua:353's stacking formula).
    rework_wh_priest_prayer_of_vengeance_self_40_others_20 = {
        character = "victor",
        career    = "wh_priest",
        patches   = {
            { buff = "victor_priest_5_1_buff", field = "multiplier", value = 0.20 },
        },
        custom_apply = function(saved)
            if not BuffTemplates then return end
            -- Self-only +20% buff template
            if BuffTemplates.crt_priest_prayer_self_extra == nil or BuffTemplates.crt_priest_prayer_self_extra._crt_pending then
                BuffTemplates.crt_priest_prayer_self_extra = {
                    buffs = {
                        {
                            stat_buff  = "power_level_large",
                            multiplier = 0.20,
                            max_stacks = 1,
                            name       = "crt_priest_prayer_self_extra",
                        },
                    },
                }
                saved.pov_created_self = true
            end
            -- Append to talent's buffs list
            if Talents and TalentIDLookup then
                local lookup = TalentIDLookup["victor_priest_5_1"]
                if lookup then
                    local talent = Talents[lookup.hero_name] and Talents[lookup.hero_name][lookup.talent_id]
                    if talent and talent.buffs then
                        local already = false
                        for _, b in ipairs(talent.buffs) do
                            if b == "crt_priest_prayer_self_extra" then already = true; break end
                        end
                        if not already then
                            saved.pov_orig_count = #talent.buffs
                            table.insert(talent.buffs, "crt_priest_prayer_self_extra")
                        end
                    end
                    -- Tooltip rewrite: aura value is now 0.20
                    local dv = talent and talent.description_values and talent.description_values[1]
                    if dv then saved.pov_tooltip = dv.value; dv.value = 0.20 end
                end
            end
        end,
        custom_restore = function(saved)
            if Talents and TalentIDLookup then
                local lookup = TalentIDLookup["victor_priest_5_1"]
                if lookup then
                    local talent = Talents[lookup.hero_name] and Talents[lookup.hero_name][lookup.talent_id]
                    if talent and talent.buffs and saved.pov_orig_count then
                        while #talent.buffs > saved.pov_orig_count do table.remove(talent.buffs) end
                    end
                    if saved.pov_tooltip ~= nil and talent and talent.description_values and talent.description_values[1] then
                        talent.description_values[1].value = saved.pov_tooltip
                    end
                end
            end
            if saved.pov_created_self and BuffTemplates then
                BuffTemplates.crt_priest_prayer_self_extra = _crt_make_stub()
            end
            saved.pov_created_self, saved.pov_orig_count, saved.pov_tooltip = nil, nil, nil
        end,
    },

    -- ============================================================
    -- Unchained: Wildfire — +50% initial burst damage + 25% burn radius
    -- ============================================================
    -- Vanilla Wildfire talent (`sienna_unchained_activated_ability_fire_aura`,
    -- row 6 col 2) switches the ult's explosion to the larger-radius variant
    -- `explosion_bw_unchained_ability_increased_radius` (radius = 5) and uses
    -- damage profile `overcharge_explosion_strong_ability` (power_distribution
    -- .attack = 0.15). Rework: when toggle is on, lift the variant explosion's
    -- radius to 6.25 (+25%) and the damage profile's attack to 0.225 (+50%).
    -- These tables are ExplosionTemplates / DamageProfileTemplates, not
    -- BuffTemplates, so all mutations happen in custom_apply.
    -- DEFERRED: the "make Wildfire effect innate" portion (remove the
    -- talent gate in career_ability_bw_unchained.lua:158) requires a runtime
    -- hook on the ability's explosion selection — queued for next pass.
    rework_bw_unchained_wildfire_burst_and_radius = {
        character = "sienna",
        career    = "bw_unchained",
        patches   = {},
        custom_apply = function(saved)
            if ExplosionTemplates and ExplosionTemplates.explosion_bw_unchained_ability_increased_radius then
                local t = ExplosionTemplates.explosion_bw_unchained_ability_increased_radius
                if type(t.radius) == "number" then
                    saved.wf_explosion_radius = t.radius
                    t.radius = t.radius * 1.25
                end
            end
            if DamageProfileTemplates and DamageProfileTemplates.overcharge_explosion_strong_ability then
                local dp = DamageProfileTemplates.overcharge_explosion_strong_ability
                if dp.power_distribution and type(dp.power_distribution.attack) == "number" then
                    saved.wf_damage_attack = dp.power_distribution.attack
                    dp.power_distribution.attack = dp.power_distribution.attack * 1.5
                end
            end
        end,
        custom_restore = function(saved)
            if saved.wf_explosion_radius and ExplosionTemplates and ExplosionTemplates.explosion_bw_unchained_ability_increased_radius then
                ExplosionTemplates.explosion_bw_unchained_ability_increased_radius.radius = saved.wf_explosion_radius
            end
            if saved.wf_damage_attack and DamageProfileTemplates and DamageProfileTemplates.overcharge_explosion_strong_ability then
                DamageProfileTemplates.overcharge_explosion_strong_ability.power_distribution.attack = saved.wf_damage_attack
            end
            saved.wf_explosion_radius, saved.wf_damage_attack = nil, nil
        end,
    },

    -- ============================================================
    -- Unchained: Numb to Pain — 4x stacks, burn-elite-kill gain, lose on hit
    -- ============================================================
    -- Vanilla talent `sienna_unchained_reduced_damage_taken_after_venting_2`
    -- (row 4 col 3) grants stacking DR on vent. Rework swaps the entire
    -- payload: register a new stacking buff (`crt_sienna_numb_to_pain_stack`,
    -- max_stacks=4, multiplier=-0.05, infinite duration), plus a proc
    -- (`crt_sienna_numb_to_pain_proc`, fires on elite-or-special burn-kill),
    -- plus a stack-remover (`crt_sienna_numb_to_pain_remover`, removes 1
    -- stack per damage taken). Talent's buffs list swapped at apply time.
    -- The "kill must be a burning enemy + elite or special" filter lives in
    -- the proc's buff_func (`add_buff_on_burning_special_or_elite_kill`,
    -- runtime override below).
    -- ============================================================
    -- Unchained: Unstable Strength rescale  (10% melee power / 5 overcharge,
    -- up to 6x  -- vs vanilla 12% / 6 overcharge, up to 5x)
    -- ============================================================
    -- Unstable Strength is the career PASSIVE, not a tree talent: the driver
    -- `sienna_unchained_passive_increased_melee_power_on_overcharge` (buffs[1]
    -- .chunk_size = 6, .max_sub_buff_stacks default 5) runs
    -- activate_server_buff_stacks_based_on_overcharge_chunks to add up to N stacks
    -- of `sienna_unchained_passive_melee_power_on_overcharge` (buffs[1].max_stacks
    -- = 5, .multiplier = 0.12, stat power_level_melee). Rescale = chunk 6->5,
    -- max 5->6 (on BOTH the driver's max_sub_buff_stacks AND the stack buff's
    -- max_stacks, or the driver caps at the lower), multiplier 0.12->0.10.
    -- This is the "master" toggle the other Unchained reworks read to pick their
    -- per-stack math (5%/6x when on, 6%/5x when off). Pure runtime field patch on
    -- shared BuffTemplates; restored on toggle-off.
    rework_bw_unchained_unstable_strength_rescale = {
        character = "sienna",
        career    = "bw_unchained",
        patches   = {},
        custom_apply = function(saved)
            if not BuffTemplates then return end
            local drv = BuffTemplates.sienna_unchained_passive_increased_melee_power_on_overcharge
            local drv_b = drv and drv.buffs and drv.buffs[1]
            if drv_b then
                saved.us_chunk = drv_b.chunk_size
                saved.us_maxsub = drv_b.max_sub_buff_stacks
                drv_b.chunk_size = 5
                drv_b.max_sub_buff_stacks = 6
            end
            local stk = BuffTemplates.sienna_unchained_passive_melee_power_on_overcharge
            local stk_b = stk and stk.buffs and stk.buffs[1]
            if stk_b then
                saved.us_maxstacks = stk_b.max_stacks
                saved.us_mult = stk_b.multiplier
                stk_b.max_stacks = 6
                stk_b.multiplier = 0.10
            end
        end,
        custom_restore = function(saved)
            if not BuffTemplates then return end
            local drv = BuffTemplates.sienna_unchained_passive_increased_melee_power_on_overcharge
            local drv_b = drv and drv.buffs and drv.buffs[1]
            if drv_b and saved.us_chunk ~= nil then
                drv_b.chunk_size = saved.us_chunk
                drv_b.max_sub_buff_stacks = saved.us_maxsub
            end
            local stk = BuffTemplates.sienna_unchained_passive_melee_power_on_overcharge
            local stk_b = stk and stk.buffs and stk.buffs[1]
            if stk_b and saved.us_maxstacks ~= nil then
                stk_b.max_stacks = saved.us_maxstacks
                stk_b.multiplier = saved.us_mult
            end
            saved.us_chunk, saved.us_maxsub, saved.us_maxstacks, saved.us_mult = nil, nil, nil, nil
        end,
    },

    -- ============================================================
    -- Unchained: Unstable Strength stacks ALSO grant burn-DoT damage
    -- ============================================================
    -- Adds a 2nd stat_buff entry (increased_burn_dot_damage, the burn-DoT scaler)
    -- to the US stack buff, so every US stack grants +12% DoT damage (10% up to 6x
    -- when the US-rescale toggle #1 is on, matching its per-stack cadence). The
    -- driver adds N US-buff instances per overcharge chunk; each now applies the
    -- DoT bonus too. Idempotent: strips any prior crt_us_dot entry before adding.
    rework_bw_unchained_unstable_strength_dot = {
        character = "sienna",
        career    = "bw_unchained",
        patches   = {},
        custom_apply = function(saved)
            if not BuffTemplates then return end
            local stk = BuffTemplates.sienna_unchained_passive_melee_power_on_overcharge
            if not (stk and stk.buffs) then return end
            local us_on = mod:get("rework_bw_unchained_unstable_strength_rescale")
            local dot   = us_on and 0.10 or 0.12
            local maxn  = us_on and 6 or 5
            for i = #stk.buffs, 1, -1 do
                if stk.buffs[i].name == "crt_us_dot" then table.remove(stk.buffs, i) end
            end
            stk.buffs[#stk.buffs + 1] = { stat_buff = "increased_burn_dot_damage", multiplier = dot, max_stacks = maxn, name = "crt_us_dot" }
            saved.dot_added = true
        end,
        custom_restore = function(saved)
            if not BuffTemplates then return end
            local stk = BuffTemplates.sienna_unchained_passive_melee_power_on_overcharge
            if stk and stk.buffs then
                for i = #stk.buffs, 1, -1 do
                    if stk.buffs[i].name == "crt_us_dot" then table.remove(stk.buffs, i) end
                end
            end
            saved.dot_added = nil
        end,
    },

    -- ============================================================
    -- Unchained: Chain Reaction explosions IGNITE nearby enemies
    -- ============================================================
    -- Chain Reaction's on-burning-kill explosion uses the no_damage push profile
    -- `slayer_leap_landing` (pure stagger, zero damage -- see MECHANICS). Giving
    -- the explosion a `dot_template_name` makes it apply a burn DoT to everything
    -- caught, so it actually lights nearby enemies on fire. Pure data patch on the
    -- shared ExplosionTemplates entry; restored on toggle-off.
    rework_bw_unchained_chain_reaction_ignite = {
        character = "sienna",
        career    = "bw_unchained",
        patches   = {},
        custom_apply = function(saved)
            local ET = rawget(_G, "ExplosionTemplates")
            local e = ET and ET.sienna_unchained_burning_enemies_explosion
            local exp = e and e.explosion
            if exp and exp.dot_template_name == nil then
                exp.dot_template_name = "burning_dot_3tick"
                saved.cr_dot_added = true
            end
            -- Bigger spread: the vanilla burst (radius 0.5..1.5) is HALF the vanilla
            -- fire explosion (lamp_oil radius 3), so almost nothing catches the burn DoT.
            -- Widen to lamp_oil scale so the ignite actually spreads to a cluster.
            if exp and saved.cr_radius_orig == nil then
                saved.cr_radius_orig = { exp.radius_min, exp.radius_max, exp.max_damage_radius_min, exp.max_damage_radius_max }
                exp.radius_min, exp.radius_max = 1.5, 3
                exp.max_damage_radius_min, exp.max_damage_radius_max = 1, 3
            end
            -- More often: the burning-kill explosion fires on only 40% of burning enemy
            -- deaths by default (talent sienna_unchained_exploding_burning_enemies,
            -- proc_chance 0.4). Bump to 100% so the chain actually chains.
            local BT = rawget(_G, "BuffTemplates")
            local b = BT and BT.sienna_unchained_exploding_burning_enemies
            local sub = b and b.buffs and b.buffs[1]
            if sub and saved.cr_proc_orig == nil then
                saved.cr_proc_orig = sub.proc_chance
                sub.proc_chance = 1.0
            end
        end,
        custom_restore = function(saved)
            local ET = rawget(_G, "ExplosionTemplates")
            local e = ET and ET.sienna_unchained_burning_enemies_explosion
            local exp = e and e.explosion
            if exp and saved.cr_dot_added then
                exp.dot_template_name = nil
                saved.cr_dot_added = nil
            end
            if exp and saved.cr_radius_orig then
                local o = saved.cr_radius_orig
                exp.radius_min, exp.radius_max = o[1], o[2]
                exp.max_damage_radius_min, exp.max_damage_radius_max = o[3], o[4]
                saved.cr_radius_orig = nil
            end
            local BT = rawget(_G, "BuffTemplates")
            local b = BT and BT.sienna_unchained_exploding_burning_enemies
            local sub = b and b.buffs and b.buffs[1]
            if sub and saved.cr_proc_orig ~= nil then
                sub.proc_chance = saved.cr_proc_orig
                saved.cr_proc_orig = nil
            end
        end,
    },

    -- ============================================================
    -- Unchained: Natural Talent -> +ranged power per Unstable Strength stack
    -- ============================================================
    -- Replaces vanilla Natural Talent (sienna_unchained_reduced_overcharge, -10%
    -- vent overcharge) with +6% ranged power per US stack (5% up to 6x when #1 is
    -- on). Same overcharge-chunk driver pattern as Numb to Pain (#5): a crt driver
    -- (update_func activate_server_buff_stacks_based_on_overcharge_chunks) keeps N
    -- stacks of a power_level_ranged buff in sync with overcharge.
    rework_bw_unchained_natural_talent_ranged = {
        character = "sienna",
        career    = "bw_unchained",
        -- issue 425: the overcharge-chunk driver adds SERVER-CONTROLLED crt_*
        -- stacks (broadcast on rpc_add_buff + replayed to hot-joiners); gated
        -- on peer parity + the wire-safe driver wrapper (which also strips its
        -- own stacks when parity degrades).
        network_unsafe = true,
        patches   = {},
        custom_apply = function(saved)
            if not BuffTemplates or not Talents or not TalentIDLookup then return end
            _crt_ensure_wire_safe_funcs()
            local us_on = mod:get("rework_bw_unchained_unstable_strength_rescale")
            local chunk = us_on and 5 or 6
            local maxn  = us_on and 6 or 5
            local rng   = us_on and 0.05 or 0.06
            BuffTemplates.crt_sienna_natural_talent_ranged_stack = {
                buffs = { { stat_buff = "power_level_ranged", multiplier = rng, max_stacks = maxn, name = "crt_sienna_natural_talent_ranged_stack" } },
            }
            BuffTemplates.crt_sienna_natural_talent_ranged_driver = {
                buffs = { { update_func = "crt_wire_safe_overcharge_chunks_driver", chunk_size = chunk, buff_to_add = "crt_sienna_natural_talent_ranged_stack", max_sub_buff_stacks = maxn, name = "crt_sienna_natural_talent_ranged_driver" } },
            }
            saved.nt_created = true
            local lookup = TalentIDLookup["sienna_unchained_reduced_overcharge"]
            if lookup then
                local talent = Talents[lookup.hero_name] and Talents[lookup.hero_name][lookup.talent_id]
                if talent and talent.buffs then
                    saved.nt_orig_buffs = {}
                    for i, b in ipairs(talent.buffs) do saved.nt_orig_buffs[i] = b end
                    talent.buffs = { "crt_sienna_natural_talent_ranged_driver" }
                end
            end
        end,
        custom_restore = function(saved)
            if Talents and TalentIDLookup and saved.nt_orig_buffs then
                local lookup = TalentIDLookup["sienna_unchained_reduced_overcharge"]
                if lookup then
                    local talent = Talents[lookup.hero_name] and Talents[lookup.hero_name][lookup.talent_id]
                    if talent then talent.buffs = saved.nt_orig_buffs end
                end
            end
            if BuffTemplates and saved.nt_created then
                BuffTemplates.crt_sienna_natural_talent_ranged_stack = _crt_make_stub()
                BuffTemplates.crt_sienna_natural_talent_ranged_driver = _crt_make_stub()
            end
            saved.nt_orig_buffs = nil
            saved.nt_created = nil
        end,
    },

    -- ============================================================
    -- Unchained: Abandon -> innate, slot becomes "Flame Unending" (CDR per US stack)
    -- ============================================================
    -- (a) Abandon's effect (sienna_unchained_health_to_ult, overcharge->cooldown)
    --     becomes base kit: append that buff to PassiveAbilitySettings.bw_3.buffs
    --     (the always-on career passive list, career_ability_settings.lua:599).
    -- (b) The lvl-25 talent slot (talent name == buff name "sienna_unchained_
    --     health_to_ult") becomes "Flame Unending": the career skill RECHARGES
    --     +6% faster per US stack (5% up to 6x = +30% at full stacks when #1 on),
    --     via the same overcharge-chunk driver. Uses `cooldown_regen` -- the
    --     CONTINUOUS decay-rate stat (cooldown_speed = apply_buffs_to_value(1,
    --     "cooldown_regen"), POSITIVE = faster) -- so recharge accelerates as US
    --     stacks build during the cooldown. NOT `activated_cooldown`, which only
    --     trims the cooldown ONCE at activation (cost-gated, one-shot) and never
    --     sped the passive recharge. Same activated_cooldown-vs-cooldown_regen
    --     distinction as the OE fix (career_tweaker_oe_cooldown.lua). Both reverted on toggle-off.
    rework_bw_unchained_abandon_innate_flame_unending = {
        character = "sienna",
        career    = "bw_unchained",
        -- issue 425: same server-controlled overcharge-chunk driver class as
        -- rework_bw_unchained_natural_talent_ranged; gated on peer parity.
        -- (The Abandon-innate PassiveAbilitySettings append is a vanilla buff
        -- name and stays wire-safe on its own.)
        network_unsafe = true,
        patches   = {},
        custom_apply = function(saved)
            if not BuffTemplates or not Talents or not TalentIDLookup then return end
            _crt_ensure_wire_safe_funcs()
            local PAS = rawget(_G, "PassiveAbilitySettings")
            local pa = PAS and PAS.bw_3
            if pa and pa.buffs then
                local present = false
                for _, b in ipairs(pa.buffs) do if b == "sienna_unchained_health_to_ult" then present = true break end end
                if not present then
                    pa.buffs[#pa.buffs + 1] = "sienna_unchained_health_to_ult"
                    saved.abandon_innate_added = true
                end
            end
            -- Show Abandon in the passive section's perk list (loc keys overridden via
            -- the shared _G.Localize hook). Idempotent against re-apply.
            if pa and pa.perks then
                local perk_present = false
                for _, p in ipairs(pa.perks) do if p.display_name == "crt_abandon_perk_name" then perk_present = true break end end
                if not perk_present then
                    pa.perks[#pa.perks + 1] = { description = "crt_abandon_perk_desc", display_name = "crt_abandon_perk_name" }
                    saved.abandon_perk_added = true
                end
            end
            local us_on = mod:get("rework_bw_unchained_unstable_strength_rescale")
            local chunk = us_on and 5 or 6
            local maxn  = us_on and 6 or 5
            -- cooldown_regen MULTIPLIER, POSITIVE = faster recharge (stacking_multiplier;
            -- N stacks accumulate N*cdr into the decay-speed root). 6x0.05 (rescale) or
            -- 5x0.06 = +30% recharge speed at full Unstable Strength stacks.
            local cdr   = us_on and 0.05 or 0.06
            BuffTemplates.crt_sienna_flame_unending_stack = {
                buffs = { { stat_buff = "cooldown_regen", multiplier = cdr, max_stacks = maxn, name = "crt_sienna_flame_unending_stack" } },
            }
            BuffTemplates.crt_sienna_flame_unending_driver = {
                buffs = { { update_func = "crt_wire_safe_overcharge_chunks_driver", chunk_size = chunk, buff_to_add = "crt_sienna_flame_unending_stack", max_sub_buff_stacks = maxn, name = "crt_sienna_flame_unending_driver" } },
            }
            saved.fu_created = true
            local lookup = TalentIDLookup["sienna_unchained_health_to_ult"]
            if lookup then
                local talent = Talents[lookup.hero_name] and Talents[lookup.hero_name][lookup.talent_id]
                if talent and talent.buffs then
                    saved.fu_orig_buffs = {}
                    for i, b in ipairs(talent.buffs) do saved.fu_orig_buffs[i] = b end
                    talent.buffs = { "crt_sienna_flame_unending_driver" }
                end
            end
        end,
        custom_restore = function(saved)
            local PAS = rawget(_G, "PassiveAbilitySettings")
            local pa = PAS and PAS.bw_3
            if pa and pa.buffs and saved.abandon_innate_added then
                for i = #pa.buffs, 1, -1 do
                    if pa.buffs[i] == "sienna_unchained_health_to_ult" then table.remove(pa.buffs, i) break end
                end
            end
            if pa and pa.perks and saved.abandon_perk_added then
                for i = #pa.perks, 1, -1 do
                    if pa.perks[i].display_name == "crt_abandon_perk_name" then table.remove(pa.perks, i) break end
                end
            end
            if Talents and TalentIDLookup and saved.fu_orig_buffs then
                local lookup = TalentIDLookup["sienna_unchained_health_to_ult"]
                if lookup then
                    local talent = Talents[lookup.hero_name] and Talents[lookup.hero_name][lookup.talent_id]
                    if talent then talent.buffs = saved.fu_orig_buffs end
                end
            end
            if BuffTemplates and saved.fu_created then
                BuffTemplates.crt_sienna_flame_unending_stack = _crt_make_stub()
                BuffTemplates.crt_sienna_flame_unending_driver = _crt_make_stub()
            end
            saved.abandon_innate_added = nil
            saved.abandon_perk_added = nil
            saved.fu_orig_buffs = nil
            saved.fu_created = nil
        end,
    },

    -- ============================================================
    -- Mercenary: Enhanced Training -> tiered Paced Strikes (2/3/4 targets)
    -- ============================================================
    -- Vanilla Enhanced Training (markus_mercenary_passive_improved) requires 4
    -- targets for a flat buff and gives nothing at 3. Rework: with Enhanced
    -- Training taken, a light/heavy hitting >=2 targets grants `target_number`
    -- stacks (cap 4) of a 5% attack-speed buff (6s) -> 2 tgt=10%, 3=15%, 4=20%;
    -- <2 = none. Base Paced Strikes (no Enhanced Training) and the other proc
    -- branches keep vanilla behaviour (>=3 target gate). Done by pointing
    -- markus_mercenary_passive.buff_func at a crt ProcFunction (registered below)
    -- that replicates vanilla except the Enhanced-Training branch; the AS buff is
    -- crt_merc_enhanced_training_as (attack_speed 0.05, max 4, 6s).
    rework_es_mercenary_enhanced_training_tiered = {
        character = "markus",
        career    = "es_mercenary",
        -- issue 425: crt_enhanced_training_proc adds crt_merc_enhanced_training_as
        -- via BuffSystem:add_buff (rpc_add_buff broadcast); gated on peer parity,
        -- with the parity fallback inline in the proc (exact vanilla ET branch).
        network_unsafe = true,
        patches   = { { buff = "markus_mercenary_passive", field = "buff_func", value = "crt_enhanced_training_proc" } },
        custom_apply = function(saved)
            if not BuffTemplates then return end
            BuffTemplates.crt_merc_enhanced_training_as = {
                buffs = { { stat_buff = "attack_speed", multiplier = 0.05, max_stacks = 4, duration = 6, name = "crt_merc_enhanced_training_as" } },
            }
            saved.et_created = true
        end,
        custom_restore = function(saved)
            if BuffTemplates and saved.et_created then BuffTemplates.crt_merc_enhanced_training_as = _crt_make_stub() end
            saved.et_created = nil
        end,
    },

    -- ============================================================
    -- Unchained: Numb to Pain -> -DR + less Blood-Magic overcharge per Unstable
    -- Strength stack  (REPLACES the prior burn-elite-kill DR-stack design)
    -- ============================================================
    -- Per Unstable Strength stack (= per overcharge chunk, mirroring US's own
    -- driver): -6% damage taken AND -12% overcharge generated by Blood Magic (the
    -- Unchained damage->overcharge passive; stat `reduced_overcharge_from_passive`,
    -- distinct from `reduced_overcharge` which is the venting/casting one). When
    -- the US-rescale toggle (#1) is on, US runs 5oc/6x so this mirrors it at
    -- -5%/-10% up to 6x. Reuses the pre-registered crt buffs:
    --   crt_sienna_numb_to_pain_stack = per-stack buff, two stat_buffs (damage_taken
    --       + reduced_overcharge_from_passive).
    --   crt_sienna_numb_to_pain_proc  = REPURPOSED as the overcharge-chunk DRIVER
    --       (update_func activate_server_buff_stacks_based_on_overcharge_chunks --
    --       the same engine func Unstable Strength uses), keeps N stacks in sync
    --       with current overcharge.
    --   crt_sienna_numb_to_pain_remover = now unused; left as a stub (the driver
    --       auto-tracks stacks up AND down, so no on-hit remover is needed).
    -- setting_id kept (legacy name) to avoid data/loc churn; label/desc updated.
    rework_bw_unchained_numb_to_pain_4x_burn_kill_lose_on_hit = {
        character = "sienna",
        career    = "bw_unchained",
        -- issue 425: same server-controlled overcharge-chunk driver class as
        -- rework_bw_unchained_natural_talent_ranged; gated on peer parity.
        network_unsafe = true,
        patches   = {},
        custom_apply = function(saved)
            if not BuffTemplates or not Talents or not TalentIDLookup then return end
            _crt_ensure_wire_safe_funcs()
            local us_on   = mod:get("rework_bw_unchained_unstable_strength_rescale")
            local chunk   = us_on and 5 or 6
            local maxn    = us_on and 6 or 5
            local dmg_mul = us_on and -0.05 or -0.06
            local oc_mul  = us_on and -0.10 or -0.12
            BuffTemplates.crt_sienna_numb_to_pain_stack = {
                buffs = {
                    { stat_buff = "damage_taken",                    multiplier = dmg_mul, max_stacks = maxn, name = "crt_sienna_numb_to_pain_stack" },
                    { stat_buff = "reduced_overcharge_from_passive", multiplier = oc_mul,  max_stacks = maxn, name = "crt_sienna_numb_to_pain_stack_oc" },
                },
            }
            saved.ntp_created_stack = true
            BuffTemplates.crt_sienna_numb_to_pain_proc = {
                buffs = {
                    {
                        update_func         = "crt_wire_safe_overcharge_chunks_driver",
                        chunk_size          = chunk,
                        buff_to_add         = "crt_sienna_numb_to_pain_stack",
                        max_sub_buff_stacks = maxn,
                        name                = "crt_sienna_numb_to_pain_proc",
                    },
                },
            }
            saved.ntp_created_proc = true
            -- Keep the remover registered as an (unused) stub for NetworkLookup determinism.
            if BuffTemplates.crt_sienna_numb_to_pain_remover == nil or BuffTemplates.crt_sienna_numb_to_pain_remover._crt_pending then
                BuffTemplates.crt_sienna_numb_to_pain_remover = _crt_make_stub()
            end
            local lookup = TalentIDLookup["sienna_unchained_reduced_damage_taken_after_venting_2"]
            if lookup then
                local talent = Talents[lookup.hero_name] and Talents[lookup.hero_name][lookup.talent_id]
                if talent and talent.buffs then
                    saved.ntp_orig_buffs = {}
                    for i, b in ipairs(talent.buffs) do saved.ntp_orig_buffs[i] = b end
                    talent.buffs = { "crt_sienna_numb_to_pain_proc" }
                end
            end
        end,
        custom_restore = function(saved)
            if Talents and TalentIDLookup and saved.ntp_orig_buffs then
                local lookup = TalentIDLookup["sienna_unchained_reduced_damage_taken_after_venting_2"]
                if lookup then
                    local talent = Talents[lookup.hero_name] and Talents[lookup.hero_name][lookup.talent_id]
                    if talent then talent.buffs = saved.ntp_orig_buffs end
                end
            end
            if BuffTemplates then
                if saved.ntp_created_stack then BuffTemplates.crt_sienna_numb_to_pain_stack = _crt_make_stub() end
                if saved.ntp_created_proc  then BuffTemplates.crt_sienna_numb_to_pain_proc = _crt_make_stub() end
            end
            saved.ntp_orig_buffs = nil
            saved.ntp_created_stack, saved.ntp_created_proc = nil, nil
        end,
    },

    -- ============================================================
    -- Mercenary: Blade Barrier — 0.5%/stack DR, 60 stacks, -10 per hit
    -- ============================================================
    -- Vanilla `markus_mercenary_passive_defence_on_proc` (row 5 col 2) grants
    -- -25% DR for 6s on proc, no stacking. Rework swaps the entire payload:
    -- register stacking buff (`crt_merc_blade_barrier_stack`, -0.5%/stack,
    -- max 60, no refresh), an on-kill proc (`crt_merc_blade_barrier_proc`),
    -- and a stack-remover that strips TEN stacks per damage taken via the
    -- kerillian-shade `remove_buff_stack_data` pattern with num_stacks=10.
    rework_es_mercenary_blade_barrier_60x_minus_10_on_hit = {
        character = "markus",
        career    = "es_mercenary",
        -- issue 425: the on-kill stack add rides rpc_add_buff; gated on peer
        -- parity + wire-safe proc wrapper. (The remover is remove_buff_stack
        -- with server_controlled=false -- local-only, wire-safe.)
        network_unsafe = true,
        patches   = {},
        custom_apply = function(saved)
            if not BuffTemplates or not Talents or not TalentIDLookup then return end
            _crt_ensure_wire_safe_funcs()
            if BuffTemplates.crt_merc_blade_barrier_stack == nil or BuffTemplates.crt_merc_blade_barrier_stack._crt_pending then
                BuffTemplates.crt_merc_blade_barrier_stack = {
                    buffs = {
                        {
                            stat_buff  = "damage_taken",
                            multiplier = -0.005,
                            max_stacks = 60,
                            name       = "crt_merc_blade_barrier_stack",
                        },
                    },
                }
                saved.bb_created_stack = true
            end
            if BuffTemplates.crt_merc_blade_barrier_proc == nil or BuffTemplates.crt_merc_blade_barrier_proc._crt_pending then
                BuffTemplates.crt_merc_blade_barrier_proc = {
                    buffs = {
                        {
                            buff_func  = "crt_wire_safe_add_buff",
                            buff_to_add = "crt_merc_blade_barrier_stack",
                            event       = "on_kill",
                            name        = "crt_merc_blade_barrier_proc",
                        },
                    },
                }
                saved.bb_created_proc = true
            end
            if BuffTemplates.crt_merc_blade_barrier_remover == nil or BuffTemplates.crt_merc_blade_barrier_remover._crt_pending then
                BuffTemplates.crt_merc_blade_barrier_remover = {
                    buffs = {
                        {
                            buff_func = "remove_buff_stack",
                            event     = "on_damage_taken",
                            name      = "crt_merc_blade_barrier_remover",
                            remove_buff_func = "remove_buff_stack",
                            remove_buff_stack_data = {
                                {
                                    buff_to_remove    = "crt_merc_blade_barrier_stack",
                                    num_stacks        = 10,
                                    server_controlled = false,
                                },
                            },
                        },
                    },
                }
                saved.bb_created_remover = true
            end
            local lookup = TalentIDLookup["markus_mercenary_passive_defence_on_proc"]
            if lookup then
                local talent = Talents[lookup.hero_name] and Talents[lookup.hero_name][lookup.talent_id]
                if talent and talent.buffs then
                    saved.bb_orig_buffs = {}
                    for i, b in ipairs(talent.buffs) do saved.bb_orig_buffs[i] = b end
                    talent.buffs = { "crt_merc_blade_barrier_proc", "crt_merc_blade_barrier_remover" }
                end
            end
        end,
        custom_restore = function(saved)
            if Talents and TalentIDLookup and saved.bb_orig_buffs then
                local lookup = TalentIDLookup["markus_mercenary_passive_defence_on_proc"]
                if lookup then
                    local talent = Talents[lookup.hero_name] and Talents[lookup.hero_name][lookup.talent_id]
                    if talent then talent.buffs = saved.bb_orig_buffs end
                end
            end
            if BuffTemplates then
                if saved.bb_created_stack   then BuffTemplates.crt_merc_blade_barrier_stack = _crt_make_stub() end
                if saved.bb_created_proc    then BuffTemplates.crt_merc_blade_barrier_proc = _crt_make_stub() end
                if saved.bb_created_remover then BuffTemplates.crt_merc_blade_barrier_remover = _crt_make_stub() end
            end
            saved.bb_orig_buffs = nil
            saved.bb_created_stack, saved.bb_created_proc, saved.bb_created_remover = nil, nil, nil
        end,
    },

    -- ============================================================
    -- Waystalker: Fervent Huntress → flat passive +10% movement speed
    -- ============================================================
    -- Like Drakira's: target the conditional movespeed talent
    -- `kerillian_waywatcher_movement_speed_on_special_kill` (level 25, +15% MS
    -- for 10s on elite/special kill) and replace its payload with a permanent
    -- +10% MS buff via the apply_movement_buff pattern.
    rework_we_waywatcher_fervent_huntress_passive_ms = {
        character = "kerillian",
        career    = "we_waywatcher",
        patches   = {},
        custom_apply = function(saved)
            if not BuffTemplates then return end
            if BuffTemplates.crt_waywatcher_fervent_huntress_passive == nil or BuffTemplates.crt_waywatcher_fervent_huntress_passive._crt_pending then
                BuffTemplates.crt_waywatcher_fervent_huntress_passive = {
                    buffs = {
                        {
                            apply_buff_func  = "apply_movement_buff",
                            remove_buff_func = "remove_movement_buff",
                            path_to_movement_setting_to_modify = { "move_speed" },
                            multiplier = 1.10,
                            max_stacks = 1,
                            name = "crt_waywatcher_fervent_huntress_passive",
                        },
                    },
                }
                saved.fervent_created = true
            end
            if Talents and TalentIDLookup then
                local lookup = TalentIDLookup["kerillian_waywatcher_movement_speed_on_special_kill"]
                if lookup then
                    local talent = Talents[lookup.hero_name] and Talents[lookup.hero_name][lookup.talent_id]
                    if talent and talent.buffs then
                        saved.fervent_orig_buffs = {}
                        for i, b in ipairs(talent.buffs) do saved.fervent_orig_buffs[i] = b end
                        talent.buffs = { "crt_waywatcher_fervent_huntress_passive" }
                    end
                end
            end
        end,
        custom_restore = function(saved)
            if Talents and TalentIDLookup and saved.fervent_orig_buffs then
                local lookup = TalentIDLookup["kerillian_waywatcher_movement_speed_on_special_kill"]
                if lookup then
                    local talent = Talents[lookup.hero_name] and Talents[lookup.hero_name][lookup.talent_id]
                    if talent then talent.buffs = saved.fervent_orig_buffs end
                end
            end
            if saved.fervent_created and BuffTemplates then
                BuffTemplates.crt_waywatcher_fervent_huntress_passive = _crt_make_stub()
            end
            saved.fervent_orig_buffs, saved.fervent_created = nil, nil
        end,
    },
}

    return BALANCE_MODS
end

return build
