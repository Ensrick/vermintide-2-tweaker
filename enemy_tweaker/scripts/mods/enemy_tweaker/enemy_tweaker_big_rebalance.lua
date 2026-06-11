-- ============================================================
-- Big Rebalance integration for enemy_tweaker
-- ============================================================
--
-- All Big Rebalance (Core's BR / "Weapon Balance" decompile) logic that et
-- owns lives here. See `design_et.md` and `inventory_system.md` in the
-- _big_rebalance_extract sibling repo for the per-row inventory and
-- ownership decisions.
--
-- The canonical alphabetical registration list lives in
-- `enemy_tweaker_big_rebalance_registrations.lua` (cross-mod diff-checked
-- against wt + ct). Registration happens unconditionally when the
-- master toggle (`br_master_enable_registrations`) is on, regardless of
-- which sub-toggles are flipped. Per-toggle work then patches data
-- tables that reference those pre-registered names.
--
-- SpicyEnemies content (mutator/curse rebalances E1-E8 from the
-- inventory) is DROPPED entirely per binding user decision #2. No
-- forced package preloads, no curse-aura templates, no Twitch
-- troll-reward retunes. Skipped at the file level.
--
-- For the three large cross-cutting hooks (DamageUtils.stagger_ai,
-- DamageUtils.calculate_damage, ActionShieldSlam._hit), we follow
-- the design rule: the hook is installed unconditionally when the
-- master toggle is on, but short-circuits to the original behavior
-- via `func(...)` when the per-feature toggle is off. This lets us
-- avoid VMF's "uninstall hook_origin" caveat.

local mod = get_mod("enemy_tweaker")

-- Canonical registration list moved to the new `bt` (buff_tweaker) mod.
-- et no longer ships its own copy nor performs the master pre-register
-- pass. It reads bt's `is_br_active()` public API to gate per-feature
-- toggles; bt writes buffs / damage profiles / explosion templates /
-- statbuff methods into vanilla tables in deterministic order.
-- The legacy REG table is replaced with empty stubs since et's
-- post-load code references it for length/iteration in a few spots.
local REG = { BR_BUFF_TEMPLATES = {}, BR_DAMAGE_PROFILES = {}, BR_EXPLOSION_TEMPLATES = {}, BR_STAT_BUFF_METHODS = {} }

local M = {}

-- ============================================================
-- Helpers / state
-- ============================================================

local _original_bloodlust_health = {}    -- breed_name -> prior value
local _original_trash            = {}    -- breed_name -> prior value
local _br_master_applied         = false
local _br_hooks_installed        = false

local function _info(fmt, ...)
    mod:info("[BR] " .. fmt, ...)
end

local function _warn(fmt, ...)
    mod:warning("[BR] " .. fmt, ...)
end

-- Local _dbg wrapper for the BR module — gated on enable_debug_logging (same
-- contract as the main file's helper, just lives here so we don't reach across
-- modules for hot per-event logging). Issue #17 auto-probe call sites.
local function _dbg(fmt, ...)
    if mod:get("enable_debug_logging") then
        mod:info("[et:dbg] [BR] " .. fmt, ...)
    end
end

-- Short hash of attacker_unit for log correlation. Stingray unit handles are
-- big ints — slice to last 4 hex chars so log lines stay readable.
local function _u_short(unit)
    if unit == nil then return "nil" end
    local s = tostring(unit)
    return s:sub(-6)
end

local function _peer_short()
    local pl = Managers and Managers.player and Managers.player.local_player and Managers.player:local_player()
    if not pl then return "?" end
    local pid = pl.peer_id and pl:peer_id() or pl.network_id and pl:network_id() or "?"
    return tostring(pid):sub(-6)
end

local function _is_server()
    return (Managers and Managers.player and Managers.player.is_server) or false
end

-- Per design_et.md: "When [master is] off, individual toggles are no-ops
-- even if checked (defensive — log a warning)."
-- Bridge to bt's master toggle. Returns false if bt isn't installed or
-- its master is off; true once bt has performed the registration pass.
local function _master_on()
    local bt = get_mod("bt")
    if not (bt and bt.is_br_active) then return false end
    return bt:is_br_active() == true
end

-- Per-feature gate: master on AND this feature on. Returns false (and
-- emits one warning per call site) if the feature is checked but master
-- isn't.
local function _feature_on(setting_id)
    if not mod:get(setting_id) then return false end
    if not _master_on() then
        _warn("'%s' is checked but master toggle is off — no-op", setting_id)
        return false
    end
    return true
end

-- ============================================================
-- Bloodlust class table (B1)
-- ============================================================

-- Always built so per-breed assignment can index into it; the toggle
-- only gates whether the table actually gets exposed at the global
-- NewBreedTweaks sink. Per design: "Defines `mod._bloodlust_health =
-- { ... }`. No effect on its own — assignment happens via the
-- per-breed toggle below."
local BLOODLUST_HEALTH = {
    beastmen_horde   = 1.5,
    skaven_elite     = 8,
    chaos_roamer     = 3,
    chaos_warrior    = 20,
    skaven_horde     = 1,
    chaos_special    = 10,
    skaven_roamer    = 2,
    chaos_horde      = 1.5,
    chaos_bulwark    = 20,
    skaven_special   = 8,
    beastmen_elite   = 15,
    beastmen_roamer  = 3,
    monster          = 35,
    chaos_elite      = 10,
}

mod._bloodlust_health = BLOODLUST_HEALTH

local function _apply_bloodlust_class_table()
    if not _feature_on("br_bloodlust_class_table") then return end
    -- Expose to the global sink so vanilla heal proc (which reads
    -- NewBreedTweaks.bloodlust_health when looking up scaled heal
    -- amounts) and per-breed assignments can both reach it.
    rawset(_G, "NewBreedTweaks", rawget(_G, "NewBreedTweaks") or {})
    _G.NewBreedTweaks.bloodlust_health = BLOODLUST_HEALTH
end

-- ============================================================
-- Per-breed bloodlust_health assignments (B2)
-- ============================================================

-- {breed_name, class_key} pairs from inventory_system.md B2.01-B2.45,
-- declared in the SAME order as the BR source so apply/restore stays
-- deterministic.
local BLOODLUST_ASSIGNMENTS = {
    { "beastmen_bestigor",                 "beastmen_elite"  },
    { "beastmen_gor",                      "beastmen_roamer" },
    { "beastmen_gor_dummy",                "beastmen_roamer" },
    { "beastmen_minotaur",                 "monster"         },
    { "beastmen_standard_bearer",          "beastmen_elite"  },
    { "beastmen_ungor_archer",             "beastmen_horde"  },
    { "beastmen_ungor",                    "beastmen_horde"  },
    { "beastmen_ungor_dummy",              "beastmen_horde"  },
    { "chaos_berzerker",                   "chaos_elite"     },
    { "chaos_corruptor_sorcerer",          "chaos_special"   },
    { "chaos_exalted_champion_warcamp",    "monster"         },
    { "chaos_exalted_sorcerer_drachenfels","monster"         },
    { "chaos_exalted_sorcerer",            "monster"         },
    { "chaos_fanatic",                     "chaos_horde"     },
    { "chaos_marauder_with_shield",        "chaos_roamer"    },
    { "chaos_marauder",                    "chaos_roamer"    },
    { "chaos_marauder_tutorial",           "chaos_roamer"    },
    { "chaos_mutator_sorcerer",            "chaos_special"   },
    { "chaos_raider",                      "chaos_elite"     },
    { "chaos_raider_tutorial",             "chaos_elite"     },
    { "chaos_spawn",                       "monster"         },
    { "chaos_troll",                       "monster"         },
    { "chaos_vortex_sorcerer",             "chaos_special"   },
    { "chaos_warrior",                     "chaos_warrior"   },
    { "skaven_clan_rat_with_shield",       "skaven_roamer"   },
    { "skaven_clan_rat",                   "skaven_roamer"   },
    { "skaven_clan_rat_tutorial",          "skaven_roamer"   },
    { "skaven_explosive_loot_rat",         "skaven_roamer"   },
    { "skaven_grey_seer",                  "monster"         },
    { "skaven_gutter_runner",              "skaven_special"  },
    { "skaven_loot_rat",                   "skaven_special"  },
    { "skaven_pack_master",                "skaven_special"  },
    { "skaven_plague_monk",                "skaven_elite"    },
    { "skaven_poison_wind_globadier",      "skaven_special"  },
    { "skaven_rat_ogre",                   "monster"         },
    { "skaven_ratling_gunner",             "skaven_special"  },
    { "skaven_slave",                      "skaven_horde"    },
    { "skaven_storm_vermin_champion",      "monster"         },
    { "skaven_storm_vermin_warlord",       "monster"         },
    { "skaven_storm_vermin_with_shield",   "skaven_elite"    },
    { "skaven_storm_vermin",               "skaven_elite"    },
    { "skaven_storm_vermin_commander",     "skaven_elite"    },
    { "skaven_stormfiend_boss",            "monster"         },
    { "skaven_stormfiend",                 "monster"         },
    { "skaven_warpfire_thrower",           "skaven_special"  },
}

local function _apply_bloodlust_per_breed()
    if not _feature_on("br_bloodlust_per_breed_assign") then return end
    local Breeds = rawget(_G, "Breeds")
    if not Breeds then return end
    for _, entry in ipairs(BLOODLUST_ASSIGNMENTS) do
        local name, class_key = entry[1], entry[2]
        local breed = Breeds[name]
        if breed then
            if _original_bloodlust_health[name] == nil then
                _original_bloodlust_health[name] = breed.bloodlust_health or false
            end
            breed.bloodlust_health = BLOODLUST_HEALTH[class_key]
        end
    end
end

local function _restore_bloodlust_per_breed()
    local Breeds = rawget(_G, "Breeds")
    if not Breeds then return end
    for name, prior in pairs(_original_bloodlust_health) do
        if Breeds[name] then
            Breeds[name].bloodlust_health = prior or nil
        end
    end
    _original_bloodlust_health = {}
end

-- ============================================================
-- Breed trash flags (B3)
-- ============================================================

local TRASH_BREEDS = {
    "beastmen_gor",
    "beastmen_ungor",
    "beastmen_ungor_archer",
    "chaos_fanatic",
    "chaos_marauder",
    "chaos_marauder_with_shield",
    "skaven_slave",
    "skaven_clan_rat",
    "skaven_clan_rat_with_shield",
    "skaven_dummy_clan_rat",
    "beastmen_gor_dummy",
}

local function _apply_trash_flags()
    if not _feature_on("br_breed_trash_flags") then return end
    local Breeds = rawget(_G, "Breeds")
    if not Breeds then return end
    for _, name in ipairs(TRASH_BREEDS) do
        local breed = Breeds[name]
        if breed then
            if _original_trash[name] == nil then
                _original_trash[name] = breed.trash or false
            end
            breed.trash = true
        end
    end
end

local function _restore_trash_flags()
    local Breeds = rawget(_G, "Breeds")
    if not Breeds then return end
    for name, prior in pairs(_original_trash) do
        if Breeds[name] then
            Breeds[name].trash = prior or nil
        end
    end
    _original_trash = {}
end

-- ============================================================
-- Master registration: BuffTemplates + NetworkLookup pre-register
-- ============================================================
--
-- Per binding decision #3: "et duplicates the same canonical sorted name
-- list as wt/ct will". Each new buff template name gets a STUB body
-- inserted into BuffTemplates and a sequential index pushed onto
-- NetworkLookup.buff_templates. Sub-toggles (or sibling-mod toggles in
-- ct/wt) can later fill in the buffs[] array for the templates they own.
-- A nil buffs[] array on an un-fleshed-out template is safe: vanilla
-- never iterates a BuffTemplate that no career/talent/proc references.
--
-- Index-stability across peers: every peer with master ON adds exactly
-- the same templates in the same alphabetical order. Sub-toggles only
-- decide whether to MUTATE the body — they do not gate the registration.
-- This is the canonical fix from `feedback_vt2_gated_registration_diverges.md`.

local function _stub_template(name)
    -- Vanilla buff entries are tables with a `buffs` array. We seed an empty
    -- one so subsequent code that does `BuffTemplates[name].buffs[1] = ...`
    -- (or table.merge) doesn't crash on a nil deref.
    return { buffs = {} }
end

local function _register_buff_templates()
    local BT  = rawget(_G, "BuffTemplates")
    local TBT = rawget(_G, "TalentBuffTemplates")
    local NL  = rawget(_G, "NetworkLookup")
    if not BT or not NL or not NL.buff_templates then
        _warn("BuffTemplates / NetworkLookup not loaded — skipping registration")
        return false
    end
    -- BR_BUFF_TEMPLATES entries are `{ name = "...", hero = "..."? }`. Plain
    -- entries (no `hero`) register into BuffTemplates only; talent entries
    -- ALSO mirror into TalentBuffTemplates[hero][name] so vanilla's boot-time
    -- merge logic (which has already run by now) doesn't matter — both tables
    -- carry the buff. Per memory rule
    -- `feedback_vt2_dormant_buff_template_dual_register`.
    for _, entry in ipairs(REG.BR_BUFF_TEMPLATES) do
        local name = entry.name
        if not BT[name] then
            BT[name] = _stub_template(name)
        end
        if entry.hero and TBT then
            TBT[entry.hero] = TBT[entry.hero] or {}
            if not TBT[entry.hero][name] then
                TBT[entry.hero][name] = BT[name]
            end
        end
        if not NL.buff_templates[name] then
            local idx = #NL.buff_templates + 1
            NL.buff_templates[idx]  = name
            NL.buff_templates[name] = idx
        end
    end
    return true
end

local function _register_damage_profiles()
    -- Empty list since SpicyEnemies dropped. Function kept as the
    -- documented extension point if BR_DAMAGE_PROFILES ever gets entries.
    local DPT = rawget(_G, "DamageProfileTemplates")
    local NL  = rawget(_G, "NetworkLookup")
    if not DPT or not NL or not NL.damage_profiles then return end
    for _, name in ipairs(REG.BR_DAMAGE_PROFILES) do
        if not DPT[name] then
            DPT[name] = { default_target = { attack_template = "light_blunt_tank" } }
        end
        if not NL.damage_profiles[name] then
            local idx = #NL.damage_profiles + 1
            NL.damage_profiles[idx]  = name
            NL.damage_profiles[name] = idx
        end
    end
end

local function _register_explosion_templates()
    -- Empty list since SpicyEnemies dropped. Extension point only.
    for _, name in ipairs(REG.BR_EXPLOSION_TEMPLATES) do
        local ET = rawget(_G, "ExplosionTemplates")
        if ET and not ET[name] then ET[name] = {} end
    end
end

local function _apply_master_registrations()
    if _br_master_applied then return end
    if not _master_on() then return end
    if not _register_buff_templates() then return end
    _register_damage_profiles()
    _register_explosion_templates()
    _br_master_applied = true
    _info("master registrations applied (%d buff templates)", #REG.BR_BUFF_TEMPLATES)
end

-- ============================================================
-- THP-source proc functions + template body fill-in (T1-T4)
-- ============================================================
--
-- These four toggles fill in the BuffTemplate body for the THP buffs
-- AND register the proc functions referenced by `buff_func`. ct owns
-- talent-slot assignment elsewhere; et only fills in the template so
-- ct's talent rewires have something to reference.
--
-- Per design_et.md: "splitting registration from slot-assignment is
-- the canonical fix for the 'Gated registration diverges across peers'
-- memory; et owns the template (since some buffs proc on breed-kill
-- or stagger, which is enemy-side)".

local BUFF_PERKS_PATH = "scripts/unit_extensions/default_player_unit/buffs/settings/buff_perk_names"

local function _buff_perks()
    -- Lazy require: VMF's mod loader pulls in buff_perk_names at boot,
    -- but a defensive lazy load is cheap.
    local ok, bp = pcall(require, BUFF_PERKS_PATH)
    if ok then return bp end
    return nil
end

local function _set_template_body(name, body)
    local BT = rawget(_G, "BuffTemplates")
    if not BT then return end
    -- Issue #19: collision warning before overwriting. Names are et-owned by
    -- convention (rebaltourn_*) but warn if any other mod (or future Fatshark
    -- patch) ever lands an entry under the same key, so the stomp is visible.
    if BT[name] then
        local existing_n = #((BT[name] and BT[name].buffs) or {})
        mod:warning("[et:set_template_body] '%s' already exists (n=%d entries) -- overwriting", name, existing_n)
    end
    BT[name] = { buffs = { body } }
end

local function _add_proc_function(fn_name, fn)
    local PF = rawget(_G, "ProcFunctions")
    if PF then PF[fn_name] = fn end
end

local function _apply_regrowth_template()
    if not _feature_on("br_thp_regrowth_template") then return end
    local bp = _buff_perks(); if not bp then return end
    _add_proc_function("rebaltourn_heal_finesse_damage_on_melee", function(owner_unit, buff, params)
        if not Managers.state.network.is_server then return end
        local heal_amount_crit = 1.5
        local heal_amount_hs   = 3
        local has_procced  = buff.has_procced
        local hit_unit     = params[1]
        local hit_zone_name = params[3]
        local target_number = params[4]
        local attack_type   = params[2]
        local critical_hit  = params[6]
        local breed = AiUtils.unit_breed(hit_unit)
        if target_number == 1 then
            buff.has_procced = false
            has_procced = false
        end
        if ALIVE[owner_unit] and breed
                and (attack_type == "light_attack" or attack_type == "heavy_attack")
                and not has_procced then
            if hit_zone_name == "head" or hit_zone_name == "neck" or hit_zone_name == "weakspot" then
                buff.has_procced = true
                DamageUtils.heal_network(owner_unit, owner_unit, heal_amount_hs, "heal_from_proc")
            end
            if critical_hit then
                DamageUtils.heal_network(owner_unit, owner_unit, heal_amount_crit, "heal_from_proc")
                buff.has_procced = true
            end
        end
    end)
    _set_template_body("rebaltourn_regrowth", {
        name = "rebaltourn_regrowth",
        event_buff = true,
        buff_func = "rebaltourn_heal_finesse_damage_on_melee",
        event = "on_hit",
        perks = { bp.ninja_healing },
    })
end

local function _apply_vanguard_template()
    if not _feature_on("br_thp_vanguard_template") then return end
    local bp = _buff_perks(); if not bp then return end
    _add_proc_function("rebaltourn_heal_stagger_targets_on_melee", function(owner_unit, buff, params)
        if not Managers.state.network.is_server then return end
        if not ALIVE[owner_unit] then return end
        local hit_unit       = params[1]
        local damage_profile = params[2]
        local attack_type    = damage_profile.charge_value
        local stagger_value  = params[6]
        local stagger_type   = params[4]
        local target_index   = params[8]
        local breed          = AiUtils.unit_breed(hit_unit)
        local multiplier     = buff.multiplier
        local is_push        = damage_profile.is_push
        local stagger_calc   = stagger_type or stagger_value
        local heal_amount    = stagger_calc * multiplier
        local death_extension = ScriptUnit.has_extension(hit_unit, "death_system")
        local is_corpse      = death_extension and (death_extension.death_is_done == false) or false

        if is_push then heal_amount = 0.6 end

        local inventory_extension = ScriptUnit.extension(owner_unit, "inventory_system")
        local equipment = inventory_extension:equipment()
        local slot_data = equipment.slots.slot_melee
        if slot_data then
            local item_data = slot_data.item_data
            local item_name = item_data.name
            if item_name == "wh_2h_billhook" and heal_amount == 9 then heal_amount = 2 end
            if item_name == "bw_flame_sword" and attack_type == "heavy_attack" and heal_amount == 1 then
                heal_amount = 2
            end
        end

        if target_index and target_index < 5 and breed and not breed.is_hero
                and (attack_type == "light_attack" or attack_type == "heavy_attack" or attack_type == "action_push")
                and not is_corpse then
            DamageUtils.heal_network(owner_unit, owner_unit, heal_amount, "heal_from_proc")
        end
    end)
    _set_template_body("rebaltourn_vanguard", {
        name = "rebaltourn_vanguard",
        multiplier = 1,
        event_buff = true,
        buff_func = "rebaltourn_heal_stagger_targets_on_melee",
        event = "on_stagger",
        perks = { bp.tank_healing },
    })
end

local function _apply_reaper_template()
    if not _feature_on("br_thp_reaper_template") then return end
    local bp = _buff_perks(); if not bp then return end
    _set_template_body("rebaltourn_reaper", {
        name = "rebaltourn_reaper",
        multiplier = -0.05,
        event_buff = true,
        buff_func = "heal_damage_targets_on_melee",  -- vanilla fn
        event = "on_player_damage_dealt",
        max_targets = 5,
        bonus = 0.25,
        perks = { bp.linesman_healing },
    })
end

local function _apply_bloodlust_template()
    if not _feature_on("br_thp_bloodlust_template") then return end
    local bp = _buff_perks(); if not bp then return end
    _set_template_body("rebaltourn_bloodlust", {
        name = "rebaltourn_bloodlust",
        multiplier = 0.2,
        event_buff = true,
        buff_func = "heal_percentage_of_enemy_hp_on_melee_kill",  -- vanilla fn
        event = "on_kill",
        perks = { bp.smiter_healing },
    })
end

-- ============================================================
-- Unbalance applied-to-enemy templates (S9 + S10)
-- ============================================================

local function _apply_unbalance_debuff_infra()
    if not _feature_on("br_unbalance_debuff_infra") then return end
    _add_proc_function("rebaltourn_unbalance_debuff_on_stagger", function(owner_unit, buff, params)
        local hit_unit = params[1]
        local is_dummy = Unit.get_data(hit_unit, "is_dummy")
        local buff_type = params[7]
        if (Unit.alive(owner_unit) and (is_dummy or Unit.alive(hit_unit)) and buff_type == "MELEE_1H")
                or buff_type == "MELEE_2H" then
            local buff_extension = ScriptUnit.extension(hit_unit, "buff_system")
            if buff_extension then
                buff_extension:add_buff("rebaltourn_tank_unbalance_buff")
            end
        end
    end)
    _set_template_body("rebaltourn_tank_unbalance", {
        name = "rebaltourn_tank_unbalance",
        max_display_multiplier = 0.4,
        event_buff = true,
        buff_func = "rebaltourn_unbalance_debuff_on_stagger",
        event = "on_stagger",
        display_multiplier = 0.2,
    })
    _set_template_body("rebaltourn_tank_unbalance_buff", {
        name = "rebaltourn_tank_unbalance_buff",
        duration = 5,
        stat_buff = "unbalanced_damage_taken",
        max_stacks = 1,
        refresh_durations = true,
        bonus = 0.15,
    })
end

-- ============================================================
-- Cross-cutting hook locals (copied from BR source verbatim)
-- ============================================================

local stagger_types = nil  -- lazy-loaded inside hook to avoid early require crash

local function _is_stagger_immune(blackboard, t)
    local stagger_immunity = blackboard.stagger_immunity
    if not stagger_immunity then return false end
    local health_percent = blackboard.current_health_percent
    local health_threshold = stagger_immunity.health_threshold
    if health_threshold and health_threshold < health_percent then
        return true
    end
    local damage_left = 0
    local stagger_immune_at_health = stagger_immunity.stagger_immune_at_health
    if stagger_immune_at_health then
        local damage_threshold = stagger_immunity.damage_threshold
        local damage_accumulated = stagger_immune_at_health - health_percent
        damage_left = damage_threshold - damage_accumulated
        stagger_immunity.debug_damage_left = damage_left
    end
    local time_left = 0
    local stagger_immune_at = stagger_immunity.stagger_immune_at
    if stagger_immune_at then
        local stagger_immune_until = stagger_immune_at + stagger_immunity.time or 0
        time_left = stagger_immune_until - t
    end
    if 0 < damage_left and 0 < time_left then
        return true
    end
    return false
end

local function _action_ignores_stagger(blackboard, attack_template, stagger_type, target_unit, is_player)
    local status_extension = ScriptUnit.has_extension(target_unit, "status_system")
    local action = (is_player and status_extension:breed_action()) or blackboard.action
    local ignore_staggers = action and action.ignore_staggers
    if blackboard.anim_cb_stagger_immune then return true end
    if not ignore_staggers or attack_template.always_stagger then return false end
    if ignore_staggers.allow_push and attack_template.is_push then return false end
    local ignore_stagger = ignore_staggers[stagger_type]
    if type(ignore_stagger) == "table" then
        local kind = ignore_stagger.type
        if kind == "ignore_by_health" then
            local health_percent = blackboard.current_health_percent
            local health_threshold = ignore_stagger.health
            return health_threshold.min < health_percent
                    and health_percent <= health_threshold.max
        elseif kind == "reset_attack" then
            blackboard.reset_attack = true
            blackboard.reset_attack_delay = ignore_stagger.delay
            return true
        end
    elseif type(ignore_stagger) == "boolean" then
        return ignore_stagger
    end
    return nil
end

local function _add_stagger_hit(blackboard, t)
    local stagger_immunity = blackboard.stagger_immunity
    if not stagger_immunity then return end
    local num_attacks_needed = stagger_immunity.num_attacks
    local num_hits = stagger_immunity.num_hits or 0
    num_hits = num_hits + 1
    if num_hits == num_attacks_needed then
        stagger_immunity.stagger_immune_at = t
        stagger_immunity.stagger_immune_at_health = blackboard.current_health_percent
        stagger_immunity.debug_damage_left = stagger_immunity.damage_threshold
        num_hits = 0
    end
    stagger_immunity.num_hits = num_hits
end

-- ============================================================
-- Stagger / damage math hooks (H1, H2, H6 + S4 + F5)
-- ============================================================
-- Installed unconditionally at master-on; each hook short-circuits via
-- `func(...)` when its own toggle is off. This is the documented
-- workaround for VMF's lack of clean origin-hook uninstall.

local function _apply_buffs_to_stagger_damage(attacker_unit, target_unit, target_index, hit_zone, is_critical_strike, stagger_number)
    local attacker_buff_extension = ScriptUnit.has_extension(attacker_unit, "buff_system")
    local new_stagger_number = stagger_number
    if attacker_buff_extension then
        local finesse_perk  = attacker_buff_extension:has_buff_perk("finesse_stagger_damage")
        local smiter_perk   = attacker_buff_extension:has_buff_perk("smiter_stagger_damage")
        local mainstay_perk = attacker_buff_extension:has_buff_perk("linesman_stagger_damage")
        if mainstay_perk and 0 < new_stagger_number then
            new_stagger_number = new_stagger_number + 1
        elseif (hit_zone == "head" or hit_zone == "neck") and finesse_perk then
            new_stagger_number = 2
        elseif smiter_perk then
            if target_index and target_index <= 1 then
                new_stagger_number = math.max(1, new_stagger_number)
            else
                new_stagger_number = stagger_number
            end
        end
    end
    return new_stagger_number
end

local function _do_damage_calculation(attacker_unit, damage_source, original_power_level, damage_output, hit_zone_name, damage_profile, target_index, boost_curve, boost_damage_multiplier, is_critical_strike, backstab_multiplier, breed, range_scalar_multiplier, static_base_damage, is_player_friendly_fire, has_power_boost, difficulty_level, target_unit_armor, target_unit_primary_armor, has_crit_head_shot_killing_blow_perk, has_crit_backstab_killing_blow_perk, target_max_health, target_unit)
    if damage_profile and damage_profile.no_damage then return 0 end
    local difficulty_settings = DifficultySettings[difficulty_level]
    local power_boost_damage = 0
    local head_shot_boost_damage = 0
    local head_shot_min_damage = 1
    local power_boost_min_damage = 1
    local multiplier_type = DamageUtils.get_breed_damage_multiplier_type(breed, hit_zone_name)
    local is_finesse_hit = multiplier_type == "headshot" or multiplier_type == "weakspot" or multiplier_type == "protected_weakspot"

    if is_finesse_hit or is_critical_strike or has_power_boost or (boost_damage_multiplier and 0 < boost_damage_multiplier) then
        local power_boost_armor
        if target_unit_armor == 2 or target_unit_armor == 5 or target_unit_armor == 6 then
            power_boost_armor = 1
        else
            power_boost_armor = target_unit_armor
        end
        local power_boost_target_damages = damage_output[power_boost_armor] or ((power_boost_armor ~= 0 or 0) and damage_output[1])
        local preliminary_boost_damage
        if type(power_boost_target_damages) == "table" then
            local power_boost_damage_range = power_boost_target_damages.max - power_boost_target_damages.min
            local power_boost_attack_power = ActionUtils.get_power_level_for_target(target_unit, original_power_level, damage_profile, target_index, is_critical_strike, attacker_unit, hit_zone_name, power_boost_armor, damage_source, breed, range_scalar_multiplier, difficulty_level, target_unit_armor, target_unit_primary_armor)
            local power_boost_percentage = ActionUtils.get_power_level_percentage(power_boost_attack_power)
            preliminary_boost_damage = power_boost_target_damages.min + power_boost_damage_range * power_boost_percentage
        else
            preliminary_boost_damage = power_boost_target_damages
        end
        if is_finesse_hit then head_shot_min_damage = preliminary_boost_damage * 0.5 end
        if is_critical_strike then head_shot_min_damage = preliminary_boost_damage * 0.5 end
        if has_power_boost or (boost_damage_multiplier and 0 < boost_damage_multiplier) then
            power_boost_damage = preliminary_boost_damage
        end
    end

    local damage, target_damages
    target_damages = (static_base_damage and ((type(damage_output) == "table" and damage_output[1]) or damage_output))
            or damage_output[target_unit_armor]
            or ((target_unit_armor ~= 0 or 0) and damage_output[1])

    if type(target_damages) == "table" then
        local damage_range = target_damages.max - target_damages.min
        local percentage = 0
        if damage_profile then
            local attack_power = ActionUtils.get_power_level_for_target(target_unit, original_power_level, damage_profile, target_index, is_critical_strike, attacker_unit, hit_zone_name, nil, damage_source, breed, range_scalar_multiplier, difficulty_level, target_unit_armor, target_unit_primary_armor)
            percentage = ActionUtils.get_power_level_percentage(attack_power)
        end
        damage = target_damages.min + damage_range * percentage
    else
        damage = target_damages
    end

    local backstab_damage
    if backstab_multiplier then
        backstab_damage = (power_boost_damage and damage < power_boost_damage and power_boost_damage * (backstab_multiplier - 1))
                or damage * (backstab_multiplier - 1)
    end

    if not static_base_damage then
        local power_boost_amount = 0
        local head_shot_boost_amount = 0
        if has_power_boost then
            if     target_unit_armor == 1 then power_boost_amount = power_boost_amount + 0.75
            elseif target_unit_armor == 2 then power_boost_amount = power_boost_amount + 0.6
            elseif target_unit_armor == 3 then power_boost_amount = power_boost_amount + 0.5
            elseif target_unit_armor == 4 then power_boost_amount = power_boost_amount + 0.5
            elseif target_unit_armor == 5 then power_boost_amount = power_boost_amount + 0.5
            elseif target_unit_armor == 6 then power_boost_amount = power_boost_amount + 0.3
            else                                power_boost_amount = power_boost_amount + 0.5
            end
        end
        if boost_damage_multiplier and 0 < boost_damage_multiplier then
            if     target_unit_armor == 1 then power_boost_amount = power_boost_amount + 0.75
            elseif target_unit_armor == 2 then power_boost_amount = power_boost_amount + 0.3
            elseif target_unit_armor == 3 then power_boost_amount = power_boost_amount + 0.75
            elseif target_unit_armor == 4 then power_boost_amount = power_boost_amount + 0.5
            elseif target_unit_armor == 5 then power_boost_amount = power_boost_amount + 0.5
            elseif target_unit_armor == 6 then power_boost_amount = power_boost_amount + 0.2
            else                                power_boost_amount = power_boost_amount + 0.5
            end
        end

        local target_settings = damage_profile and ((damage_profile.targets and damage_profile.targets[target_index]) or damage_profile.default_target)
        if is_finesse_hit then
            if 0 < damage then
                if target_unit_armor == 3 then
                    head_shot_boost_amount = head_shot_boost_amount + ((target_settings and (target_settings.headshot_boost_boss or target_settings.headshot_boost)) or 0.25)
                else
                    head_shot_boost_amount = head_shot_boost_amount + ((target_settings and target_settings.headshot_boost) or 0.5)
                end
            elseif target_unit_primary_armor == 6 and damage == 0 then
                head_shot_boost_amount = head_shot_boost_amount + (target_settings and (target_settings.headshot_boost_heavy_armor or 0.25))
            elseif target_unit_armor == 2 and damage == 0 then
                head_shot_boost_amount = head_shot_boost_amount + ((target_settings and (target_settings.headshot_boost_armor or target_settings.headshot_boost)) or 0.5)
            end
            if multiplier_type == "protected_weakspot" then
                head_shot_boost_amount = head_shot_boost_amount * 0.25
            end
        end
        if multiplier_type == "protected_spot" then
            power_boost_amount     = power_boost_amount - 0.5
            head_shot_boost_amount = head_shot_boost_amount - 0.5
        end
        if damage_profile and damage_profile.no_headshot_boost then head_shot_boost_amount = 0 end

        local crit_boost = 0
        if is_critical_strike then
            crit_boost = (damage_profile and damage_profile.crit_boost) or 0.5
            if damage_profile and damage_profile.no_crit_boost then crit_boost = 0 end
        end

        local attacker_buff_extension = attacker_unit and ScriptUnit.has_extension(attacker_unit, "buff_system")

        if boost_curve and (0 < power_boost_amount or 0 < head_shot_boost_amount or 0 < crit_boost) then
            local modified_boost_curve, modified_boost_curve_head_shot
            local boost_coefficient          = (target_settings and target_settings.boost_curve_coefficient)          or DefaultBoostCurveCoefficient
            local boost_coefficient_headshot = (target_settings and target_settings.boost_curve_coefficient_headshot) or DefaultBoostCurveCoefficient
            if boost_damage_multiplier and 0 < boost_damage_multiplier then
                if breed and breed.boost_curve_multiplier_override then
                    boost_damage_multiplier = math.clamp(boost_damage_multiplier, 0, breed.boost_curve_multiplier_override)
                end
                boost_coefficient          = boost_coefficient * boost_damage_multiplier
                boost_coefficient_headshot = boost_coefficient_headshot * boost_damage_multiplier
            end
            if 0 < power_boost_amount then
                modified_boost_curve = DamageUtils.get_modified_boost_curve(boost_curve, boost_coefficient)
                power_boost_amount = math.clamp(power_boost_amount, 0, 1)
                local boost_multiplier = DamageUtils.get_boost_curve_multiplier(modified_boost_curve or boost_curve, power_boost_amount)
                power_boost_damage = math.max(math.max(power_boost_damage, damage), power_boost_min_damage) * boost_multiplier
            end
            if 0 < head_shot_boost_amount or 0 < crit_boost then
                local target_unit_buff_extension = target_unit and ScriptUnit.has_extension(target_unit, "buff_system")
                modified_boost_curve_head_shot = DamageUtils.get_modified_boost_curve(boost_curve, boost_coefficient_headshot)
                head_shot_boost_amount = math.clamp(head_shot_boost_amount + crit_boost, 0, 1)
                local head_shot_boost_multiplier = DamageUtils.get_boost_curve_multiplier(modified_boost_curve_head_shot or boost_curve, head_shot_boost_amount)
                head_shot_boost_damage = math.max(math.max(power_boost_damage, damage), head_shot_min_damage) * head_shot_boost_multiplier
                if attacker_buff_extension and is_critical_strike then
                    head_shot_boost_damage = head_shot_boost_damage * attacker_buff_extension:apply_buffs_to_value(1, "critical_strike_effectiveness")
                end
                if attacker_buff_extension and is_finesse_hit then
                    head_shot_boost_damage = head_shot_boost_damage * attacker_buff_extension:apply_buffs_to_value(1, "headshot_multiplier")
                end
                if target_unit_buff_extension and is_finesse_hit then
                    head_shot_boost_damage = head_shot_boost_damage * target_unit_buff_extension:apply_buffs_to_value(1, "headshot_vulnerability")
                end
            end
        end

        if breed and breed.armored_boss_damage_reduction then
            damage = damage * 0.8
            power_boost_damage = power_boost_damage * 0.25
            backstab_damage = backstab_damage and backstab_damage * 0.5
        end
        if breed and breed.boss_damage_reduction then
            damage = damage * 0.45
            power_boost_damage = power_boost_damage * 0.5
            head_shot_boost_damage = head_shot_boost_damage * 0.5
            backstab_damage = backstab_damage and backstab_damage * 0.75
        end
        if breed and breed.lord_damage_reduction then
            damage = damage * 0.2
            power_boost_damage = power_boost_damage * 0.25
            head_shot_boost_damage = head_shot_boost_damage * 0.25
            backstab_damage = backstab_damage and backstab_damage * 0.5
        end

        damage = damage + power_boost_damage + head_shot_boost_damage
        if backstab_damage then damage = damage + backstab_damage end

        if attacker_buff_extension then
            if multiplier_type == "headshot" then
                damage = attacker_buff_extension:apply_buffs_to_value(damage, "headshot_damage")
            else
                damage = attacker_buff_extension:apply_buffs_to_value(damage, "non_headshot_damage")
            end
        end

        if is_critical_strike then
            local killing_blow_triggered
            if hit_zone_name == "head" and has_crit_head_shot_killing_blow_perk then
                killing_blow_triggered = true
            elseif backstab_multiplier and 1 < backstab_multiplier and has_crit_backstab_killing_blow_perk and damage_profile.charge_value == "heavy_attack" then
                killing_blow_triggered = true
            end
            if killing_blow_triggered and breed then
                local boss = breed.boss
                local primary_armor = breed.primary_armor_category
                if not boss and not primary_armor then
                    if target_max_health then
                        damage = target_max_health
                    else
                        local breed_health_table = breed.max_health
                        local difficulty_rank = difficulty_settings.rank
                        damage = breed_health_table[difficulty_rank]
                    end
                end
            end
        end
    end

    if is_player_friendly_fire then
        local friendly_fire_multiplier = difficulty_settings.friendly_fire_multiplier
        if damage_profile and damage_profile.friendly_fire_multiplier then
            friendly_fire_multiplier = friendly_fire_multiplier * damage_profile.friendly_fire_multiplier
        end
        if friendly_fire_multiplier then damage = damage * friendly_fire_multiplier end
    end

    local heavy_armor_damage = false
    return damage, heavy_armor_damage
end

local function _install_hooks()
    if _br_hooks_installed then return end

    -- Guard against the cross-cutting tables not being loaded yet. These
    -- globals (DamageUtils, ActionShieldSlam) are populated by the engine
    -- well before VMF runs mod.on_enabled, but a defensive nil check is
    -- cheap and matches CLAUDE.md's table-form hook doctrine.
    if not rawget(_G, "DamageUtils") or not rawget(_G, "ActionShieldSlam") then
        _warn("DamageUtils/ActionShieldSlam not loaded — hooks deferred")
        return
    end

    -- H2: DamageUtils.stagger_ai rewrite
    -- v0.6.0-dev: BR rewrite body wrapped in pcall — on inner error log
    -- mod:warning + bail to vanilla so a malformed enemy/attacker state
    -- doesn't crash the whole damage path. The master-gate short-circuit
    -- at the top stays as the cheap pre-check.
    mod:hook(DamageUtils, "stagger_ai", function(func, t, damage_profile, target_index, power_level, target_unit, attacker_unit, hit_zone_name, attack_direction, boost_curve_multiplier, is_critical_strike, blocked, damage_source, source_attacker_unit)
        if not mod:get("br_stagger_ai_rewrite") or not _master_on() then
            return func(t, damage_profile, target_index, power_level, target_unit, attacker_unit, hit_zone_name, attack_direction, boost_curve_multiplier, is_critical_strike, blocked, damage_source, source_attacker_unit)
        end
        local _et_br_ok, _et_br_r1 = pcall(function()
        -- Issue #17 auto-probe: entry log + one-shot fingerprint broadcast.
        if mod._br_fingerprint_broadcast_once then mod._br_fingerprint_broadcast_once() end
        _dbg("[stagger_ai] entry peer=%s host=%s fp=%s target=%s attacker=%s hit_zone=%s src=%s",
            _peer_short(), tostring(_is_server()),
            mod._br_settings_fingerprint and mod._br_settings_fingerprint() or "?",
            _u_short(target_unit), _u_short(attacker_unit),
            tostring(hit_zone_name), tostring(damage_source))
        if not stagger_types then
            stagger_types = require("scripts/utils/stagger_types")
        end
        if not damage_profile.always_stagger_ai and not DamageUtils.is_enemy(source_attacker_unit or attacker_unit, target_unit) then
            return
        end
        local ai_extension = ScriptUnit.has_extension(target_unit, "ai_system")
        local blackboard = (ai_extension and ai_extension:blackboard()) or BLACKBOARDS[target_unit]
        if not blackboard then return end
        local is_hero_player = blackboard.breed.is_hero and not ai_extension
        if is_hero_player then return end
        if _is_stagger_immune(blackboard, t) then return end
        local target_settings = (damage_profile.targets and damage_profile.targets[target_index]) or damage_profile.default_target
        local attack_template_name = target_settings.attack_template
        local attack_template = AttackTemplates[attack_template_name]
        local stagger_type, stagger_duration, stagger_length, stagger_value = DamageUtils.calculate_stagger_player(
            ImpactTypeOutput, target_unit, attacker_unit, hit_zone_name, power_level,
            boost_curve_multiplier, is_critical_strike, damage_profile, target_index, blocked, damage_source)
        local is_push = damage_profile.is_push
        if stagger_type == 0 then return end
        local is_player = blackboard.is_player and not ai_extension
        if _action_ignores_stagger(blackboard, attack_template, stagger_type, target_unit, is_player) then
            return
        end
        if not is_player then _add_stagger_hit(blackboard, t) end
        local stagger_angle = attack_template.stagger_angle
        local target_unit_position   = POSITION_LOOKUP[target_unit]   or Unit.world_position(target_unit, 0)
        local attacker_position      = POSITION_LOOKUP[attacker_unit] or Unit.world_position(attacker_unit, 0)
        if stagger_angle == "down" or (stagger_angle == "smiter" and blocked) then
            attack_direction = Vector3.normalize(target_unit_position - attacker_position)
            attack_direction.z = -1
        elseif stagger_angle == "stab" or stagger_angle == "smiter" or blocked then
            attack_direction = Vector3.normalize(target_unit_position - attacker_position)
        elseif stagger_angle == "pull" then
            attack_direction = Vector3.normalize(attacker_position - target_unit_position)
        end
        if stagger_types.none < stagger_type then
            if is_player then
                DamageUtils.stagger_player(target_unit, blackboard.breed, attack_direction, stagger_length, stagger_type, stagger_duration, attack_template.stagger_animation_scale, t, stagger_value, attack_template.always_stagger, is_push)
            else
                AiUtils.stagger(target_unit, blackboard, attacker_unit, attack_direction, stagger_length, stagger_type, stagger_duration, attack_template.stagger_animation_scale, t, stagger_value, attack_template.always_stagger, is_push)
            end
            local attacker_buff_extension = attacker_unit and ScriptUnit.has_extension(attacker_unit, "buff_system")
            if attacker_buff_extension then
                local item_data = rawget(ItemMasterList, damage_source)
                local weapon_template_name = item_data and item_data.template
                local weapon_template = weapon_template_name and WeaponUtils.get_weapon_template(weapon_template_name)
                local buff_type = (weapon_template and weapon_template.buff_type) or nil
                Managers.state.achievement:trigger_event("register_ai_stagger", target_unit, attacker_unit, damage_profile, is_push, stagger_type)
                attacker_buff_extension:trigger_procs("on_stagger", target_unit, damage_profile, attacker_unit, stagger_type, stagger_duration, stagger_value, buff_type, target_index)
            end
        end
        -- Issue #17 auto-probe exit (end-of-body only — early returns above are
        -- "stagger immune / no blackboard / not enemy" short-circuits that the
        -- entry-log already disambiguates by hit_zone + targets).
        _dbg("[stagger_ai] exit  peer=%s target=%s stagger_type=%s stagger_dur=%s",
            _peer_short(), _u_short(target_unit),
            tostring(stagger_type), tostring(stagger_duration))
        end) -- end of v0.6.0-dev pcall wrapper
        if not _et_br_ok then
            -- v0.7.0-dev: log-only. stagger_ai fires on every melee hit; if BR
            -- body errors, the chat echo would land on EVERY swing — pure spam.
            -- mod:warning still hits the log so post-mission triage works.
            mod:warning("[et:BR:stagger_ai] rewrite body errored: %s — bailing to vanilla", tostring(_et_br_r1))
            return func(t, damage_profile, target_index, power_level, target_unit, attacker_unit, hit_zone_name, attack_direction, boost_curve_multiplier, is_critical_strike, blocked, damage_source, source_attacker_unit)
        end
    end)

    -- H6: DamageUtils.calculate_damage rewrite
    -- v0.6.0-dev: BR rewrite body wrapped in pcall — on inner error log
    -- mod:warning + bail to vanilla. Crucial because calculate_damage
    -- runs on EVERY damage event; a hot crash here would brick the run.
    mod:hook(DamageUtils, "calculate_damage", function(func, damage_output, target_unit, attacker_unit, hit_zone_name, original_power_level, boost_curve, boost_damage_multiplier, is_critical_strike, damage_profile, target_index, backstab_multiplier, damage_source)
        if not mod:get("br_calculate_damage_rewrite") or not _master_on() then
            return func(damage_output, target_unit, attacker_unit, hit_zone_name, original_power_level, boost_curve, boost_damage_multiplier, is_critical_strike, damage_profile, target_index, backstab_multiplier, damage_source)
        end
        local _et_br_ok, _et_br_result = pcall(function()
        -- Issue #17 auto-probe: entry log + one-shot fingerprint broadcast.
        if mod._br_fingerprint_broadcast_once then mod._br_fingerprint_broadcast_once() end
        _dbg("[calculate_damage] entry peer=%s host=%s fp=%s target=%s attacker=%s hit_zone=%s power=%s crit=%s src=%s",
            _peer_short(), tostring(_is_server()),
            mod._br_settings_fingerprint and mod._br_settings_fingerprint() or "?",
            _u_short(target_unit), _u_short(attacker_unit),
            tostring(hit_zone_name), tostring(original_power_level),
            tostring(is_critical_strike), tostring(damage_source))
        local difficulty_settings = Managers.state.difficulty:get_difficulty_settings()
        local breed, dummy_unit_armor, is_dummy, unit_max_health
        if target_unit then
            breed = AiUtils.unit_breed(target_unit)
            dummy_unit_armor = Unit.get_data(target_unit, "armor")
            is_dummy = Unit.get_data(target_unit, "is_dummy")
            local target_unit_health_extension = ScriptUnit.has_extension(target_unit, "health_system")
            local is_invincible = target_unit_health_extension and target_unit_health_extension:get_is_invincible() and not is_dummy
            if is_invincible then return 0 end
            if target_unit_health_extension and not is_dummy then
                unit_max_health = target_unit_health_extension:get_max_health()
            elseif breed then
                unit_max_health = breed.max_health[difficulty_settings.rank]
            end
        end

        local attacker_breed = attacker_unit and Unit.get_data(attacker_unit, "breed") or nil
        local static_base_damage = not attacker_breed or not attacker_breed.is_hero
        local is_friendly_fire = not static_base_damage and Managers.state.side:is_ally(attacker_unit, target_unit)
        local target_is_hero = breed and breed.is_hero
        local range_scalar_multiplier = 0
        if damage_profile and not static_base_damage then
            local target_settings = (damage_profile.targets and damage_profile.targets[target_index]) or damage_profile.default_target
            range_scalar_multiplier = ActionUtils.get_range_scalar_multiplier(damage_profile, target_settings, attacker_unit, target_unit)
        end

        local buff_extension = attacker_unit and ScriptUnit.has_extension(attacker_unit, "buff_system")
        local has_power_boost = false
        local has_crit_head_shot_killing_blow_perk = false
        local has_crit_backstab_killing_blow_perk = false
        if buff_extension then
            has_power_boost                      = buff_extension:has_buff_perk("potion_armor_penetration")
            has_crit_head_shot_killing_blow_perk = buff_extension:has_buff_perk("crit_headshot_killing_blow")
            has_crit_backstab_killing_blow_perk  = buff_extension:has_buff_perk("crit_backstab_killing_blow")
        end

        local difficulty_level = Managers.state.difficulty:get_difficulty()
        local target_unit_armor, target_unit_primary_armor
        if target_is_hero then
            target_unit_armor = PLAYER_TARGET_ARMOR
        else
            target_unit_armor, _, target_unit_primary_armor, _ = ActionUtils.get_target_armor(hit_zone_name, breed, dummy_unit_armor)
        end

        local calculated_damage = _do_damage_calculation(attacker_unit, damage_source, original_power_level, damage_output, hit_zone_name, damage_profile, target_index, boost_curve, boost_damage_multiplier, is_critical_strike, backstab_multiplier, breed, range_scalar_multiplier, static_base_damage, is_friendly_fire, has_power_boost, difficulty_level, target_unit_armor, target_unit_primary_armor, has_crit_head_shot_killing_blow_perk, has_crit_backstab_killing_blow_perk, unit_max_health, target_unit)

        if damage_profile and not damage_profile.is_dot then
            local blackboard = BLACKBOARDS[target_unit]
            local stagger_number = 0
            if blackboard then
                local min_stagger_number = 0
                local max_stagger_number = 2
                if blackboard.is_climbing then
                    stagger_number = 2
                else
                    stagger_number = math.min(blackboard.stagger or min_stagger_number, max_stagger_number)
                end
                if damage_profile.no_stagger_damage_reduction_ranged then
                    stagger_number = math.max(1, stagger_number)
                end
                if not damage_profile.no_stagger_damage_reduction_ranged then
                    stagger_number = _apply_buffs_to_stagger_damage(attacker_unit, target_unit, target_index, hit_zone_name, is_critical_strike, stagger_number)
                end
            elseif dummy_unit_armor then
                local target_buff_extension = ScriptUnit.has_extension(target_unit, "buff_system")
                stagger_number = target_buff_extension:apply_buffs_to_value(0, "dummy_stagger")
                if damage_profile.no_stagger_damage_reduction_ranged then
                    stagger_number = math.max(1, stagger_number)
                end
                if not damage_profile.no_stagger_damage_reduction_ranged then
                    stagger_number = _apply_buffs_to_stagger_damage(attacker_unit, target_unit, target_index, hit_zone_name, is_critical_strike, stagger_number)
                end
            end
            local min_stagger_damage_coefficient = difficulty_settings.min_stagger_damage_coefficient
            local stagger_damage_multiplier = difficulty_settings.stagger_damage_multiplier
            if stagger_damage_multiplier then
                local bonus_damage_percentage = stagger_number * stagger_damage_multiplier
                local target_buff_extension = ScriptUnit.has_extension(target_unit, "buff_system")
                if target_buff_extension and not damage_profile.no_stagger_damage_reduction_ranged then
                    bonus_damage_percentage = target_buff_extension:apply_buffs_to_value(bonus_damage_percentage, "unbalanced_damage_taken")
                end
                calculated_damage = calculated_damage * (min_stagger_damage_coefficient + bonus_damage_percentage)
            end
        end

        local weave_manager = Managers.weave
        if target_is_hero and static_base_damage and weave_manager:get_active_weave() then
            local scaling_value = weave_manager:get_scaling_value("enemy_damage")
            calculated_damage = calculated_damage * (scaling_value + 1)
        end
        if target_is_hero and damage_profile and damage_profile.max_friendly_damage and damage_profile.max_friendly_damage < calculated_damage then
            calculated_damage = damage_profile.max_friendly_damage
        end
        -- Issue #17 auto-probe exit. Damage is the headline value for
        -- divergence triage (HUD damage-number desync is the visible symptom).
        _dbg("[calculate_damage] exit  peer=%s target=%s damage=%s",
            _peer_short(), _u_short(target_unit), tostring(calculated_damage))
        return calculated_damage
        end) -- end of v0.6.0-dev pcall wrapper
        if not _et_br_ok then
            -- v0.7.0-dev: log-only (see stagger_ai comment above — calculate_damage
            -- runs on every damage event, chat echo would be catastrophic spam).
            mod:warning("[et:BR:calculate_damage] rewrite body errored: %s — bailing to vanilla", tostring(_et_br_result))
            return func(damage_output, target_unit, attacker_unit, hit_zone_name, original_power_level, boost_curve, boost_damage_multiplier, is_critical_strike, damage_profile, target_index, backstab_multiplier, damage_source)
        end
        return _et_br_result
    end)

    -- H1: ActionShieldSlam._hit rewrite. Body copied verbatim (vanilla-style
    -- method form) — too large to reproduce inline a second time; the
    -- per-toggle short-circuit short-paths to the original.
    -- v0.6.0-dev: BR rewrite body wrapped in pcall — on inner error log
    -- mod:warning + bail to vanilla. PhysicsWorld lookups + actor iteration
    -- have a long history of edge-case nil returns on world transitions.
    mod:hook(ActionShieldSlam, "_hit", function(func, self, world, can_damage, owner_unit, current_action)
        if not mod:get("br_shield_slam_rewrite") or not _master_on() then
            return func(self, world, can_damage, owner_unit, current_action)
        end
        local _et_br_ok, _et_br_r1 = pcall(function()
        -- Issue #17 auto-probe: entry log + one-shot fingerprint broadcast.
        if mod._br_fingerprint_broadcast_once then mod._br_fingerprint_broadcast_once() end
        _dbg("[shield_slam] entry peer=%s host=%s fp=%s owner=%s can_damage=%s item=%s",
            _peer_short(), tostring(_is_server()),
            mod._br_settings_fingerprint and mod._br_settings_fingerprint() or "?",
            _u_short(owner_unit), tostring(can_damage), tostring(self.item_name))
        local network_manager = Managers.state.network
        local physics_world = World.get_data(world, "physics_world")
        local attacker_unit_id = network_manager:unit_game_object_id(owner_unit)
        local first_person_unit = self.first_person_unit
        local unit_forward = Quaternion.forward(Unit.local_rotation(first_person_unit, 0))
        local first_person_extension = ScriptUnit.extension(owner_unit, "first_person_system")
        local self_pos = first_person_extension:current_position()
        local forward_offset = current_action.forward_offset or 1
        local attack_pos = self_pos + unit_forward * forward_offset
        local radius = current_action.push_radius
        local collision_filter = "filter_melee_sweep"
        local actors, actors_n = PhysicsWorld.immediate_overlap(physics_world, "shape", "sphere", "position", attack_pos, "size", radius, "types", "dynamics", "collision_filter", collision_filter, "use_global_table")
        local inner_forward_offset = forward_offset + radius * 0.65
        local inner_attack_pos      = self_pos + unit_forward * inner_forward_offset
        local inner_attack_pos_near = self_pos + unit_forward
        local inner_radius = current_action.inner_push_radius or radius * 0.4
        local inner_radius_sq = inner_radius * inner_radius
        local inner_hit_units = self.inner_hit_units
        local hit_units = self.hit_units
        local unit_get_data = Unit.get_data

        if script_data.debug_weapons then
            self._drawer:sphere(attack_pos, radius, Color(255, 0, 0))
            self._drawer:sphere(inner_attack_pos_near, inner_radius, Color(0, 255, 0))
            self._drawer:sphere(inner_attack_pos, inner_radius, Color(0, 255, 0))
        end

        local target_breed_unit = self.target_breed_unit
        local target_breed_unit_health_extension = Unit.alive(target_breed_unit) and ScriptUnit.extension(target_breed_unit, "health_system")
        if target_breed_unit_health_extension then
            if not target_breed_unit_health_extension:is_alive() then
                target_breed_unit = nil
            end
        else
            target_breed_unit = nil
        end

        local side_manager = Managers.state.side
        local total_hits = 0
        local hit_unit_index = 1

        for i = 1, actors_n, 1 do
            local hit_actor = actors[i]
            local hit_unit = Actor.unit(hit_actor)
            if not hit_units[hit_unit] then
                hit_units[hit_unit] = true
                local target_is_friendly = side_manager:is_ally(owner_unit, hit_unit)
                if not target_is_friendly then
                    local breed = unit_get_data(hit_unit, "breed")
                    local dummy = not breed and unit_get_data(hit_unit, "is_dummy")
                    local hit_self = hit_unit == owner_unit
                    if breed or dummy then
                        hit_unit_index = total_hits
                        total_hits = total_hits + 1
                        self._num_targets_hit = self._num_targets_hit + 1
                        if hit_unit ~= target_breed_unit then
                            local node = Actor.node(hit_actor)
                            local hit_zone = breed and breed.hit_zones_lookup[node]
                            local target_hit_zone_name = (hit_zone and hit_zone.name) or "torso"
                            local target_hit_position = Unit.has_node(hit_unit, "j_spine") and Unit.world_position(hit_unit, Unit.node(hit_unit, "j_spine"))
                            local target_world_position = POSITION_LOOKUP[hit_unit] or Unit.world_position(hit_unit, 0)
                            local hit_position = target_hit_position or target_world_position
                            self.target_hit_zones_names[hit_unit] = target_hit_zone_name
                            self.target_hit_unit_positions[hit_unit] = hit_position
                            local attack_direction = Vector3.normalize(hit_position - self_pos)
                            local hit_unit_id = network_manager:unit_game_object_id(hit_unit)
                            local hit_zone_id = rawget(NetworkLookup.hit_zones, target_hit_zone_name)
                            if self:_is_infront_player(self_pos, unit_forward, hit_position) then
                                local distance_to_inner_position_sq = math.min(
                                    Vector3.distance_squared(target_hit_position, inner_attack_pos),
                                    Vector3.distance_squared(target_hit_position, inner_attack_pos_near))
                                if distance_to_inner_position_sq <= inner_radius_sq then
                                    inner_hit_units[hit_unit] = true
                                else
                                    local shield_blocked = AiUtils.attack_is_shield_blocked(hit_unit, owner_unit)
                                    local damage_source = self.item_name
                                    local damage_source_id = rawget(NetworkLookup.damage_sources, damage_source)
                                    local weapon_system = self.weapon_system
                                    local power_level = self.power_level
                                    local is_server = self.is_server
                                    local damage_profile = self.damage_profile_aoe
                                    local target_index = hit_unit_index
                                    local is_critical_strike = self._is_critical_strike
                                    if not dummy then
                                        self._overridable_settings = current_action
                                        ActionSweep._play_character_impact(self, is_server, owner_unit, hit_unit, breed, hit_position, target_hit_zone_name, current_action, damage_profile, target_index, power_level, attack_direction, shield_blocked, self.melee_boost_curve_multiplier, is_critical_strike)
                                    end
                                    weapon_system:send_rpc_attack_hit(damage_source_id, attacker_unit_id, hit_unit_id, hit_zone_id, hit_position, attack_direction, self.damage_profile_aoe_id, "power_level", power_level, "hit_target_index", target_index, "blocking", shield_blocked, "shield_break_procced", false, "boost_curve_multiplier", self.melee_boost_curve_multiplier, "is_critical_strike", self._is_critical_strike, "can_damage", true, "can_stagger", true, "first_hit", self._num_targets_hit == 1)
                                end
                            end
                        end
                    elseif not hit_self and ScriptUnit.has_extension(hit_unit, "health_system") then
                        local hit_unit_id, is_level_unit = network_manager:game_object_or_level_id(hit_unit)
                        if is_level_unit then
                            hit_units[hit_unit] = true
                            local no_player_damage = unit_get_data(hit_unit, "no_damage_from_players")
                            if not no_player_damage then
                                local target_hit_position = Unit.world_position(hit_unit, 0)
                                local distance_to_inner_position_sq = math.min(
                                    Vector3.distance_squared(target_hit_position, inner_attack_pos),
                                    Vector3.distance_squared(target_hit_position, inner_attack_pos_near))
                                if distance_to_inner_position_sq <= inner_radius_sq then
                                    inner_hit_units[hit_unit] = true
                                else
                                    local attack_direction = Vector3.normalize(target_hit_position - self_pos)
                                    DamageUtils.damage_level_unit(hit_unit, owner_unit, "full", self.power_level, self.melee_boost_curve_multiplier, self._is_critical_strike, self.damage_profile_aoe, 1, attack_direction, self.item_name)
                                end
                            end
                        else
                            hit_units[hit_unit] = true
                            local hit_position = POSITION_LOOKUP[hit_unit] or Unit.world_position(hit_unit, 0)
                            local distance_to_inner_position_sq = math.min(
                                Vector3.distance_squared(hit_position, inner_attack_pos),
                                Vector3.distance_squared(hit_position, inner_attack_pos_near))
                            if distance_to_inner_position_sq <= inner_radius_sq then
                                inner_hit_units[hit_unit] = true
                            end
                            local damage_source = self.item_name
                            local damage_source_id = rawget(NetworkLookup.damage_sources, damage_source)
                            local weapon_system = self.weapon_system
                            local power_level = self.power_level
                            local hit_zone_id = NetworkLookup.hit_zones.full
                            local attack_direction = Vector3.normalize(hit_position - self_pos)
                            weapon_system:send_rpc_attack_hit(damage_source_id, attacker_unit_id, hit_unit_id, hit_zone_id, hit_position, attack_direction, self.damage_profile_aoe_id, "power_level", power_level, "hit_target_index", nil, "boost_curve_multiplier", self.melee_boost_curve_multiplier, "is_critical_strike", self._is_critical_strike, "can_damage", true, "can_stagger", true)
                        end
                    end
                end
            end
        end

        if Unit.alive(target_breed_unit) and not self.hit_target_breed_unit then
            inner_hit_units[target_breed_unit] = true
        end

        local hit_index = 1
        for hit_unit, _ in pairs(inner_hit_units) do
            local breed = unit_get_data(hit_unit, "breed")
            local dummy = not breed and unit_get_data(hit_unit, "is_dummy")
            local hit_zone_name = self.target_hit_zones_names[hit_unit] or "torso"
            local target_hit_position = Unit.has_node(hit_unit, "j_spine") and Unit.world_position(hit_unit, Unit.node(hit_unit, "j_spine"))
            local target_world_position = POSITION_LOOKUP[hit_unit] or Unit.world_position(hit_unit, 0)
            local hit_position = target_hit_position or target_world_position
            local attack_direction = Vector3.normalize(hit_position - self_pos)
            local hit_unit_id, is_level_unit = network_manager:game_object_or_level_id(hit_unit)
            local hit_zone_id = rawget(NetworkLookup.hit_zones, hit_zone_name)

            if (breed or dummy) and self:_is_infront_player(self_pos, unit_forward, hit_position, current_action.push_dot) then
                local is_server = self.is_server
                local hit_default_target = hit_unit == target_breed_unit
                local damage_profile    = (hit_default_target and self.damage_profile_target)    or self.damage_profile
                local damage_profile_id = (hit_default_target and self.damage_profile_target_id) or self.damage_profile_id
                local target_index = 1
                local power_level = self.power_level
                local is_critical_strike = self._is_critical_strike
                local shield_blocked = AiUtils.attack_is_shield_blocked(hit_unit, owner_unit)
                local actor = Unit.find_actor(hit_unit, "c_spine") and Unit.actor(hit_unit, "c_spine")
                local actor_position_hit = actor and Actor.center_of_mass(actor)
                if not dummy and actor_position_hit then
                    self._overridable_settings = current_action
                    ActionSweep._play_character_impact(self, is_server, owner_unit, hit_unit, breed, actor_position_hit, hit_zone_name, current_action, damage_profile, target_index, power_level, attack_direction, shield_blocked, self.melee_boost_curve_multiplier, is_critical_strike)
                end
                local charge_value = damage_profile.charge_value or "heavy_attack"
                local buff_type = DamageUtils.get_item_buff_type(self.item_name)
                DamageUtils.buff_on_attack(owner_unit, hit_unit, charge_value, is_critical_strike, hit_zone_name, hit_index, true, buff_type)
                local damage_source_id = rawget(NetworkLookup.damage_sources, self.item_name)
                local weapon_system = self.weapon_system
                weapon_system:send_rpc_attack_hit(damage_source_id, attacker_unit_id, hit_unit_id, hit_zone_id, hit_position, attack_direction, damage_profile_id, "power_level", power_level, "hit_target_index", hit_index, "blocking", shield_blocked, "shield_break_procced", false, "boost_curve_multiplier", self.melee_boost_curve_multiplier, "is_critical_strike", is_critical_strike, "can_damage", true, "can_stagger", true, "first_hit", self._num_targets_hit == 1)
                if self.is_critical_strike and self.critical_strike_particle_id then
                    World.destroy_particles(self.world, self.critical_strike_particle_id)
                    self.critical_strike_particle_id = nil
                end
                if not Managers.player:owner(self.owner_unit).bot_player then
                    Managers.state.controller_features:add_effect("rumble", { rumble_effect = "handgun_fire" })
                end
                self.hit_target_breed_unit = true
                hit_index = hit_index + 1
            elseif ScriptUnit.has_extension(hit_unit, "health_system") then
                if is_level_unit then
                    local no_player_damage = unit_get_data(hit_unit, "no_damage_from_players")
                    if not no_player_damage then
                        local target_pos = Unit.world_position(hit_unit, 0)
                        local dir = Vector3.normalize(target_pos - self_pos)
                        DamageUtils.damage_level_unit(hit_unit, owner_unit, "full", self.power_level, self.melee_boost_curve_multiplier, self._is_critical_strike, self.damage_profile, 1, dir, self.item_name)
                    end
                else
                    local damage_source = self.item_name
                    local damage_source_id = rawget(NetworkLookup.damage_sources, damage_source)
                    local weapon_system = self.weapon_system
                    local power_level = self.power_level
                    hit_zone_id = NetworkLookup.hit_zones.full
                    local target_pos = Unit.world_position(hit_unit, 0)
                    local dir = Vector3.normalize(target_pos - self_pos)
                    weapon_system:send_rpc_attack_hit(damage_source_id, attacker_unit_id, hit_unit_id, hit_zone_id, target_pos, dir, self.damage_profile_id, "power_level", power_level, "hit_target_index", nil, "boost_curve_multiplier", self.melee_boost_curve_multiplier, "is_critical_strike", self._is_critical_strike, "can_damage", true, "can_stagger", true)
                end
            end
        end

        -- Issue #17 auto-probe exit. total_hits + num_targets_hit are the
        -- two cross-peer-comparable scalars for shield-slam result divergence.
        _dbg("[shield_slam] exit  peer=%s owner=%s total_hits=%s num_targets_hit=%s",
            _peer_short(), _u_short(owner_unit),
            tostring(total_hits), tostring(self._num_targets_hit))
        self.state = "hit"
        end) -- end of v0.6.0-dev pcall wrapper
        if not _et_br_ok then
            -- v0.7.0-dev: log-only (see stagger_ai comment above).
            mod:warning("[et:BR:shield_slam] rewrite body errored: %s — bailing to vanilla", tostring(_et_br_r1))
            return func(self, world, can_damage, owner_unit, current_action)
        end
    end)

    _br_hooks_installed = true
    _info("cross-cutting hooks installed (stagger_ai, calculate_damage, _hit)")
end

-- ============================================================
-- Public entry points
-- ============================================================

function M.on_enabled()
    _apply_master_registrations()
    _apply_bloodlust_class_table()
    _apply_bloodlust_per_breed()
    _apply_trash_flags()
    _apply_regrowth_template()
    _apply_vanguard_template()
    _apply_reaper_template()
    _apply_bloodlust_template()
    _apply_unbalance_debuff_infra()
    if _master_on() then _install_hooks() end
end

function M.on_setting_changed()
    -- Restore + re-apply table mutations. Registrations and hook bodies
    -- are persistent (registrations because un-registering would diverge
    -- indices; hook bodies because they're gated internally).
    _restore_bloodlust_per_breed()
    _restore_trash_flags()
    _apply_master_registrations()
    _apply_bloodlust_class_table()
    _apply_bloodlust_per_breed()
    _apply_trash_flags()
    _apply_regrowth_template()
    _apply_vanguard_template()
    _apply_reaper_template()
    _apply_bloodlust_template()
    _apply_unbalance_debuff_infra()
    if _master_on() then _install_hooks() end
end

function M.on_disabled()
    -- Restore breed mutations only. Buff templates and hooks stay (see
    -- on_setting_changed rationale).
    _restore_bloodlust_per_breed()
    _restore_trash_flags()
end

return M
