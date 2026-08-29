-- _crt_balance_catalog_engineer.lua — Outcast Engineer balance definitions
--
-- Owns exactly the three Outcast Engineer catalogue rows extracted for issue #2.
-- It depends only on the injected restore-stub factory captured by Leading Shots.
-- Construction is synchronous and hook-neutral; the composer retains duplicate-key
-- rejection, while each returned apply/restore callback preserves its prior body.
--
-- Owned by: career_tweaker_balance.lua. Consumed via: _crt_balance_catalog.lua mod:dofile.

local function build(ctx)
    assert(type(ctx) == "table", "crt Engineer catalog context required")
    local _crt_make_stub = assert(ctx.make_stub, "crt Engineer catalog make_stub required")

local BALANCE_MODS = {
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

}

    return BALANCE_MODS
end

return build
