-- ============================================================
-- Career Tweaker — Core's Big Rebalance integration
-- ============================================================
-- Implements ~160 opt-in toggles from Core's Big Rebalance for career-side
-- content (talent reworks, passive lists, ult overhauls, career-tagged buffs).
-- Cross-cutting hooks (DamageUtils.stagger_ai / calculate_damage / etc.) are
-- intentionally NOT here — they live in et per user direction.
-- SpicyEnemies content is intentionally excluded.
--
-- Architecture:
--   1. On master toggle (`cbr_master_enable_registrations`), pre-register every
--      BR_REGISTRATIONS name (BuffTemplates / TalentBuffTemplates /
--      NewDamageProfileTemplates / NewExplosionTemplates) UNCONDITIONALLY in
--      alphabetical order on every peer. Stub bodies — vanilla-compatible
--      defaults so the buff/profile/explosion exists even when individual
--      content toggles are off. Per-toggle apply logic OVERLAYS richer content
--      into the stub at toggle-on time. Per memory rule
--      `feedback_vt2_gated_registration_diverges`, the registration index
--      sequence MUST be deterministic across peers.
--   2. Each individual toggle is opt-in (default false). When on, it overlays
--      its content (talent rewire, field patches, hook gates) on the pre-
--      registered foundation. Description-only changes ride with their parent
--      behavioral toggle (no standalone description toggles).
--   3. on_setting_changed re-runs apply when any `cbr_*` toggle changes.

local mod = get_mod("crt")

-- BR ON ICE (bt retired 2026-06-08). Belt-and-suspenders: if any stray loader
-- still dofile's this module, return the inert stub immediately so its ~2768
-- lines of data/hooks never run or consume lua_heap. Matches the {apply, restore,
-- active_count} shape read in career_tweaker.lua. To revive BR, delete this line.
if true then return { apply = function() end, restore = function() end, active_count = function() return 0 end } end

-- Canonical registration list moved to the new `bt` (buff_tweaker) mod.
-- ct no longer ships its own copy nor performs the master pre-register
-- pass. It reads bt's `is_br_active()` public API to gate per-feature
-- toggles; bt is responsible for writing buffs / damage profiles /
-- explosion templates / statbuff methods into vanilla tables and
-- NetworkLookup in deterministic order on every peer.
--
-- The legacy `BR` table (BR_BUFF_TEMPLATES / BR_DAMAGE_PROFILES /
-- BR_EXPLOSION_TEMPLATES / BR_STAT_BUFF_METHODS) used to be loaded here
-- and consumed by the now-removed _pre_register_all function. It's
-- unused below — every individual ct apply function works against
-- already-registered names from bt.
local BR = { BR_BUFF_TEMPLATES = {}, BR_DAMAGE_PROFILES = {}, BR_EXPLOSION_TEMPLATES = {}, BR_STAT_BUFF_METHODS = {} }

-- Bridge to bt's master toggle. Returns false if bt isn't installed or
-- if its master is off; true once bt has performed the registration
-- pass and the master is still on.
local function _br_master_active()
    local bt = get_mod("bt")
    if not (bt and bt.is_br_active) then return false end
    return bt:is_br_active() == true
end

-- ============================================================
-- Stub builders — minimal-correct content so a pre-registered name
-- can be add_buffed without crashing even if its content toggle is off.
-- ============================================================
-- A stub buff is a no-op stat buff (multiplier 0) that the engine accepts.
local function _stub_buff_table(name)
    return {
        buffs = {
            {
                name = name,
                stat_buff = "power_level",
                multiplier = 0,
                max_stacks = 1,
            },
        },
    }
end

-- Stub explosion template: tiny no-damage explosion that won't fatal at apply
-- time. Real content overlays via individual toggles.
local function _stub_explosion_template(name)
    return {
        explosion = {
            radius        = 1,
            attack_template = "light_blunt",
            damage_profile = "default",
            damage_type   = "kinetic",
            player_push_speed = 0,
            sound_event = "Play_fire_explosion_small",
        },
    }
end

-- Stub damage profile: relies on M8 normalisation loop (Weapon_Balance_main.lua)
-- which BR provides. Since ct doesn't have that loop, use a fully-formed shape
-- compatible with the vanilla DamageProfileTemplates post-process: default_target
-- with a power_distribution, charge_value, no_damage_reduction flag.
local function _stub_damage_profile_template(name)
    return {
        charge_value = "n/a",
        no_stagger   = true,
        default_target = {
            power_distribution = { attack = 0, impact = 0 },
            boost_curve_type   = "linear_curve",
        },
        targets = {},
    }
end

-- ============================================================
-- Master pre-registration loop
-- ============================================================
-- Idempotent — registers each name once; skipped if entry already exists.
local _br_registered = false

local function _register_buff_template_if_missing(name)
    if not BuffTemplates then return end
    if BuffTemplates[name] then return end
    BuffTemplates[name] = _stub_buff_table(name)
    if NetworkLookup and NetworkLookup.buff_templates then
        local idx = #NetworkLookup.buff_templates + 1
        NetworkLookup.buff_templates[idx] = name
        NetworkLookup.buff_templates[name] = idx
    end
end

local function _register_talent_buff_template_if_missing(name, hero)
    if not TalentBuffTemplates then return end
    TalentBuffTemplates[hero] = TalentBuffTemplates[hero] or {}
    if TalentBuffTemplates[hero][name] then return end
    local t = _stub_buff_table(name)
    TalentBuffTemplates[hero][name] = t
    BuffTemplates[name] = t
    if NetworkLookup and NetworkLookup.buff_templates and not rawget(NetworkLookup.buff_templates, name) then
        local idx = #NetworkLookup.buff_templates + 1
        NetworkLookup.buff_templates[idx] = name
        NetworkLookup.buff_templates[name] = idx
    end
end

local function _register_explosion_template_if_missing(name)
    if not NewExplosionTemplates then _G.NewExplosionTemplates = {} end
    if not ExplosionTemplates then return end
    if ExplosionTemplates[name] then return end
    local stub = _stub_explosion_template(name)
    ExplosionTemplates[name] = stub
    NewExplosionTemplates[name] = stub
end

local function _register_damage_profile_template_if_missing(name)
    if not NewDamageProfileTemplates then _G.NewDamageProfileTemplates = {} end
    if not DamageProfileTemplates then return end
    if DamageProfileTemplates[name] then return end
    local stub = _stub_damage_profile_template(name)
    DamageProfileTemplates[name] = stub
    NewDamageProfileTemplates[name] = stub
    if NetworkLookup and NetworkLookup.damage_profiles then
        local idx = #NetworkLookup.damage_profiles + 1
        NetworkLookup.damage_profiles[idx] = name
        NetworkLookup.damage_profiles[name] = idx
    end
end

local function _pre_register_all()
    if _br_registered then return end
    if not _br_master_active() then return end
    -- Registrations now happen in bt; ct's local pass is a defensive
    -- no-op that just marks `_br_registered` so the apply engine knows
    -- the names are live.
    _br_registered = true
    if true then return end
    -- Legacy body below kept inert for reference.

    -- Canonical four-table structure. Plain buff entries (no `hero`) register
    -- into BuffTemplates only; talent entries (with `hero`) ALSO register into
    -- TalentBuffTemplates[hero]. Per memory rule
    -- `feedback_vt2_dormant_buff_template_dual_register` — vanilla merges
    -- TalentBuffTemplates into BuffTemplates at engine boot before mods load,
    -- so runtime-added talent buffs must write to BOTH tables.
    for _, entry in ipairs(BR.BR_BUFF_TEMPLATES) do
        if entry.hero then
            _register_talent_buff_template_if_missing(entry.name, entry.hero)
        else
            _register_buff_template_if_missing(entry.name)
        end
    end
    for _, name in ipairs(BR.BR_DAMAGE_PROFILES) do
        _register_damage_profile_template_if_missing(name)
    end
    for _, name in ipairs(BR.BR_EXPLOSION_TEMPLATES) do
        _register_explosion_template_if_missing(name)
    end
    -- BR_STAT_BUFF_METHODS does NOT enter NetworkLookup but is mirrored for
    -- cross-mod symmetry. wt owns the StatBuffApplicationMethods writes;
    -- ct's apply is a no-op here so the canonical list is symmetric.

    _br_registered = true
    mod:info("BR pre-registration complete: %d buff/talent entries, %d damage profiles, %d explosions",
        #BR.BR_BUFF_TEMPLATES,
        #BR.BR_DAMAGE_PROFILES,
        #BR.BR_EXPLOSION_TEMPLATES
    )
end

-- ============================================================
-- BR_TOGGLES — per-setting apply logic
-- ============================================================
-- Each entry: setting_id -> { apply = function() end, restore = function() end }
-- apply() runs when the toggle is on; restore() reverts. on_setting_changed
-- triggers a full sweep: every toggle's restore runs first to revert, then
-- toggles that are still on re-apply. This snapshot/revert pattern mirrors the
-- existing BALANCE_MODS engine in career_tweaker_balance.lua.

local _br_originals = {} -- setting_id -> saved state table

-- ============================================================
-- Small helper utilities
-- ============================================================
local function _safe_set_buff_field(saved, buff_name, field, value)
    if not BuffTemplates or not BuffTemplates[buff_name] then return end
    local b = BuffTemplates[buff_name].buffs and BuffTemplates[buff_name].buffs[1]
    if not b then return end
    saved.fields = saved.fields or {}
    saved.fields[#saved.fields + 1] = { buff = buff_name, field = field, old = b[field] }
    b[field] = value
end

local function _restore_buff_fields(saved)
    if not saved.fields then return end
    for i = #saved.fields, 1, -1 do
        local entry = saved.fields[i]
        local t = BuffTemplates and BuffTemplates[entry.buff]
        if t and t.buffs and t.buffs[1] then
            t.buffs[1][entry.field] = entry.old
        end
    end
    saved.fields = nil
end

local function _safe_set_table_field(saved, table_ref, key, value)
    if not table_ref then return end
    saved.table_fields = saved.table_fields or {}
    saved.table_fields[#saved.table_fields + 1] = { tbl = table_ref, key = key, old = table_ref[key] }
    table_ref[key] = value
end

local function _restore_table_fields(saved)
    if not saved.table_fields then return end
    for i = #saved.table_fields, 1, -1 do
        local entry = saved.table_fields[i]
        entry.tbl[entry.key] = entry.old
    end
    saved.table_fields = nil
end

local function _safe_modify_talent(saved, career_name, tier, index, new_data)
    if not CareerSettings or not CareerSettings[career_name] then return end
    local cs = CareerSettings[career_name]
    local hero_name = cs.profile_name
    local talent_tree_index = cs.talent_tree_index
    if not TalentTrees[hero_name] or not TalentTrees[hero_name][talent_tree_index] then return end
    local talent_name = TalentTrees[hero_name][talent_tree_index][tier][index]
    if not talent_name then return end
    local lookup = TalentIDLookup[talent_name]
    if not lookup then return end
    local talent = Talents[lookup.hero_name] and Talents[lookup.hero_name][lookup.talent_id]
    if not talent then return end
    saved.talent_snapshots = saved.talent_snapshots or {}
    local snapshot = {}
    for k, v in pairs(new_data) do
        snapshot[k] = talent[k]
        talent[k] = v
    end
    saved.talent_snapshots[#saved.talent_snapshots + 1] = { ref = talent, snap = snapshot }
end

local function _restore_modified_talents(saved)
    if not saved.talent_snapshots then return end
    for i = #saved.talent_snapshots, 1, -1 do
        local entry = saved.talent_snapshots[i]
        for k, v in pairs(entry.snap) do
            entry.ref[k] = v
        end
    end
    saved.talent_snapshots = nil
end

-- Append a buff to a passive ability settings list (and snapshot for restore).
local function _safe_append_passive_buff(saved, career_key, buff_name)
    if not PassiveAbilitySettings or not PassiveAbilitySettings[career_key] then return end
    local p = PassiveAbilitySettings[career_key]
    p.buffs = p.buffs or {}
    for _, b in ipairs(p.buffs) do if b == buff_name then return end end
    saved.passive_appends = saved.passive_appends or {}
    saved.passive_appends[#saved.passive_appends + 1] = { ref = p.buffs, count = #p.buffs }
    table.insert(p.buffs, buff_name)
end

local function _restore_passive_appends(saved)
    if not saved.passive_appends then return end
    for i = #saved.passive_appends, 1, -1 do
        local e = saved.passive_appends[i]
        while #e.ref > e.count do table.remove(e.ref) end
    end
    saved.passive_appends = nil
end

-- Save and restore wholesale passive buffs list (for full reflows).
local function _safe_replace_passive_buffs(saved, career_key, new_buffs)
    if not PassiveAbilitySettings or not PassiveAbilitySettings[career_key] then return end
    local p = PassiveAbilitySettings[career_key]
    saved.passive_replaced = saved.passive_replaced or {}
    saved.passive_replaced[career_key] = p.buffs
    p.buffs = new_buffs
end

local function _restore_passive_replacements(saved)
    if not saved.passive_replaced then return end
    for career_key, old in pairs(saved.passive_replaced) do
        if PassiveAbilitySettings[career_key] then
            PassiveAbilitySettings[career_key].buffs = old
        end
    end
    saved.passive_replaced = nil
end

-- ============================================================
-- BR_TOGGLES table
-- ============================================================
-- Each entry has setting_id, apply, restore. Built progressively below.
local BR_TOGGLES = {}

-- ----------------------------------------------------------------------------
-- Generic helper to define a simple buff-field patch toggle
-- ----------------------------------------------------------------------------
local function _toggle_field_patches(setting_id, patches)
    BR_TOGGLES[setting_id] = {
        apply = function(saved)
            for _, p in ipairs(patches) do
                _safe_set_buff_field(saved, p.buff, p.field, p.value)
            end
        end,
        restore = function(saved)
            _restore_buff_fields(saved)
        end,
    }
end

-- Generic helper for table-key patches (CareerSettings / ActivatedAbilitySettings / etc.)
local function _toggle_table_patches(setting_id, patches_fn)
    BR_TOGGLES[setting_id] = {
        apply = function(saved)
            patches_fn(function(tbl, key, value) _safe_set_table_field(saved, tbl, key, value) end)
        end,
        restore = function(saved)
            _restore_table_fields(saved)
        end,
    }
end

-- Helper for talent-modify-only toggles
local function _toggle_talent_modify(setting_id, modifications)
    BR_TOGGLES[setting_id] = {
        apply = function(saved)
            for _, m in ipairs(modifications) do
                _safe_modify_talent(saved, m[1], m[2], m[3], m[4])
            end
        end,
        restore = function(saved)
            _restore_modified_talents(saved)
        end,
    }
end

-- ============================================================
-- 1. General / framework toggles (13)
-- ============================================================

-- cbr_master_enable_registrations: special — handled by _pre_register_all,
-- no apply/restore entry needed.

-- THP talent rework — overlays content into pre-registered rebaltourn_* stubs
-- and rewires tier-1 talents per the source's talent_first_row groups.
BR_TOGGLES.cbr_thp_talents_rebalanced = {
    apply = function(saved)
        if not BuffTemplates then return end
        -- Overlay real bodies into pre-registered stubs.
        local function _set(name, body)
            local t = BuffTemplates[name]
            if not t then return end
            saved.thp_buffs = saved.thp_buffs or {}
            saved.thp_buffs[name] = t.buffs[1]
            t.buffs[1] = body
        end
        _set("rebaltourn_regrowth", {
            name = "regrowth", event_buff = true, buff_func = "rebaltourn_heal_finesse_damage_on_melee",
            event = "on_hit",
        })
        _set("rebaltourn_vanguard", {
            name = "vanguard", multiplier = 1, event_buff = true,
            buff_func = "rebaltourn_heal_stagger_targets_on_melee", event = "on_stagger",
        })
        _set("rebaltourn_reaper", {
            name = "reaper", multiplier = -0.05, event_buff = true,
            buff_func = "heal_damage_targets_on_melee", event = "on_player_damage_dealt",
            max_targets = 5, bonus = 0.25,
        })
        _set("rebaltourn_bloodlust", {
            name = "bloodlust", multiplier = 0.2, event_buff = true,
            buff_func = "heal_percentage_of_enemy_hp_on_melee_kill", event = "on_kill",
        })

        -- Tier-1 rewires (talent_first_row from thp_stagger_changes.lua:1791)
        local row_a = { "es_knight", "es_mercenary", "es_questingknight", "dr_ironbreaker",
            "wh_zealot", "bw_unchained", "wh_priest", "dr_engineer", "dr_ranger" }
        local row_b = { "es_huntsman", "bw_scholar", "bw_adept" }
        local row_c = { "wh_captain", "dr_slayer", "we_shade", "we_maidenguard",
            "we_waywatcher", "wh_bountyhunter", "we_thornsister" }
        local row_d = { "bw_necromancer" }
        for _, c in ipairs(row_a) do
            _safe_modify_talent(saved, c, 1, 1, { buffs = { "rebaltourn_vanguard" } })
            _safe_modify_talent(saved, c, 1, 2, { buffs = { "rebaltourn_reaper" } })
            _safe_modify_talent(saved, c, 1, 3, { buffs = { "rebaltourn_bloodlust" } })
        end
        for _, c in ipairs(row_b) do
            _safe_modify_talent(saved, c, 1, 1, { buffs = { "rebaltourn_vanguard" } })
            _safe_modify_talent(saved, c, 1, 2, { buffs = { "rebaltourn_reaper" } })
            _safe_modify_talent(saved, c, 1, 3, { buffs = { "rebaltourn_regrowth" } })
        end
        for _, c in ipairs(row_c) do
            _safe_modify_talent(saved, c, 1, 1, { buffs = { "rebaltourn_reaper" } })
            _safe_modify_talent(saved, c, 1, 2, { buffs = { "rebaltourn_bloodlust" } })
            _safe_modify_talent(saved, c, 1, 3, { buffs = { "rebaltourn_regrowth" } })
        end
        for _, c in ipairs(row_d) do
            _safe_modify_talent(saved, c, 1, 1, { buffs = { "rebaltourn_vanguard" } })
            _safe_modify_talent(saved, c, 1, 2, { buffs = { "rebaltourn_bloodlust" } })
            _safe_modify_talent(saved, c, 1, 3, { buffs = { "rebaltourn_regrowth" } })
        end
    end,
    restore = function(saved)
        if saved.thp_buffs then
            for name, original in pairs(saved.thp_buffs) do
                if BuffTemplates[name] then BuffTemplates[name].buffs[1] = original end
            end
            saved.thp_buffs = nil
        end
        _restore_modified_talents(saved)
    end,
}

-- Stagger talent rework — overlays real bodies + rewires tier-3 (talent_third_row)
BR_TOGGLES.cbr_stagger_talents_rebalanced = {
    apply = function(saved)
        if not BuffTemplates then return end
        local function _set(name, body)
            local t = BuffTemplates[name]
            if not t then return end
            saved.stagger_buffs = saved.stagger_buffs or {}
            saved.stagger_buffs[name] = t.buffs[1]
            t.buffs[1] = body
        end
        _set("rebaltourn_smiter_unbalance", {
            name = "smiter_unbalance", display_multiplier = 0.2, max_display_multiplier = 0.4,
        })
        _set("rebaltourn_finesse_unbalance", {
            name = "finesse_unbalance", display_multiplier = 0.2, max_display_multiplier = 0.4,
        })
        _set("rebaltourn_tank_unbalance", {
            name = "tank_unbalance", display_multiplier = 0.2, max_display_multiplier = 0.4,
            event_buff = true, buff_func = "rebaltourn_unbalance_debuff_on_stagger", event = "on_stagger",
        })
        _set("rebaltourn_tank_unbalance_buff", {
            name = "tank_unbalance_buff", stat_buff = "unbalanced_damage_taken",
            bonus = 0.15, duration = 5, max_stacks = 1, refresh_durations = true,
        })
        _set("rebaltourn_power_level_unbalance", {
            name = "power_level_unbalance", stat_buff = "power_level", multiplier = 0.1, max_stacks = 1,
        })

        local row_a = { "es_mercenary", "es_huntsman", "dr_ranger", "dr_slayer",
            "we_waywatcher", "we_shade", "we_thornsister", "wh_captain",
            "wh_bountyhunter", "wh_zealot", "bw_scholar", "we_maidenguard" }
        local row_b = { "es_knight", "es_questingknight", "dr_ironbreaker", "dr_engineer",
            "bw_adept", "bw_unchained", "wh_priest", "bw_necromancer" }
        for _, c in ipairs(row_a) do
            _safe_modify_talent(saved, c, 3, 1, { buffs = { "rebaltourn_smiter_unbalance" } })
            _safe_modify_talent(saved, c, 3, 2, { buffs = { "rebaltourn_finesse_unbalance" } })
            _safe_modify_talent(saved, c, 3, 3, { buffs = { "rebaltourn_power_level_unbalance" } })
        end
        for _, c in ipairs(row_b) do
            _safe_modify_talent(saved, c, 3, 1, { buffs = { "rebaltourn_smiter_unbalance" } })
            _safe_modify_talent(saved, c, 3, 2, { buffs = { "rebaltourn_tank_unbalance" } })
            _safe_modify_talent(saved, c, 3, 3, { buffs = { "rebaltourn_power_level_unbalance" } })
        end
    end,
    restore = function(saved)
        if saved.stagger_buffs then
            for name, original in pairs(saved.stagger_buffs) do
                if BuffTemplates[name] then BuffTemplates[name].buffs[1] = original end
            end
            saved.stagger_buffs = nil
        end
        _restore_modified_talents(saved)
    end,
}

-- Timed-block (parry) framework — hook gating handled via mod:get checks below.
BR_TOGGLES.cbr_timed_block_framework = { apply = function() end, restore = function() end }

-- dodge_count = 2 default — hook gating
BR_TOGGLES.cbr_default_dodge_count_2 = { apply = function() end, restore = function() end }

-- infinite_wounds perk gate — hook gating
BR_TOGGLES.cbr_infinite_wounds_perk = { apply = function() end, restore = function() end }

-- Grab-proof (ledge_self_rescue) — hook gating
BR_TOGGLES.cbr_grab_proof_ledge_self_rescue = { apply = function() end, restore = function() end }

-- Variable zoom on melee action_three — hook gating
BR_TOGGLES.cbr_melee_action_three_zoom = { apply = function() end, restore = function() end }

-- Extended power-level multipliers — hook gating (H3 hook below)
BR_TOGGLES.cbr_power_level_on_hit_extended = { apply = function() end, restore = function() end }

-- Damage-pipeline extras (et prerequisite — log warning and no-op)
BR_TOGGLES.cbr_damage_taken_pipeline_extras = {
    apply = function(saved)
        -- ct cannot install these alone; et owns the H4 base rewrite.
        -- Branches below in et hook will conditionally check this toggle. ct
        -- only logs.
        if not mod._cbr_damage_extras_warned then
            mod:info("cbr_damage_taken_pipeline_extras: depends on et's damage-taken hook being on")
            mod._cbr_damage_extras_warned = true
        end
    end,
    restore = function() end,
}

-- weak_bomb explosion + dot — overlay content into stubs
BR_TOGGLES.cbr_weak_bomb_template = {
    apply = function(saved)
        if BuffTemplates and BuffTemplates.burning_dot_weak_bomb then
            saved.weak_bomb_dot_old = BuffTemplates.burning_dot_weak_bomb.buffs[1]
            BuffTemplates.burning_dot_weak_bomb.buffs[1] = {
                name = "burning_dot_weak_bomb",
                damage_type = "burninating_aoe_dot",
                dot_damage_profile = "burning_dot_low",
                duration = 4,
                time_between_dot_damages = 0.5,
                perks = { "burning" },
            }
        end
    end,
    restore = function(saved)
        if saved.weak_bomb_dot_old and BuffTemplates and BuffTemplates.burning_dot_weak_bomb then
            BuffTemplates.burning_dot_weak_bomb.buffs[1] = saved.weak_bomb_dot_old
            saved.weak_bomb_dot_old = nil
        end
    end,
}

-- Conqueror necklace trait rename (S14)
BR_TOGGLES.cbr_trait_conqueror_rename = {
    apply = function(saved)
        if not WeaponTraits or not WeaponTraits.traits or not WeaponTraits.traits.necklace_heal_self_on_heal_other then return end
        local trait = WeaponTraits.traits.necklace_heal_self_on_heal_other
        saved.conq_ad = trait.advanced_description
        saved.conq_bn = trait.buff_name
        trait.advanced_description = "conqueror_desc_3"
        trait.buff_name = "conqueror"
    end,
    restore = function(saved)
        if not WeaponTraits or not WeaponTraits.traits or not WeaponTraits.traits.necklace_heal_self_on_heal_other then return end
        local trait = WeaponTraits.traits.necklace_heal_self_on_heal_other
        if saved.conq_ad ~= nil then trait.advanced_description = saved.conq_ad end
        if saved.conq_bn ~= nil then trait.buff_name = saved.conq_bn end
        saved.conq_ad, saved.conq_bn = nil, nil
    end,
}

-- Force-load DLC career packages (from experimental_talent_changes.lua intro)
BR_TOGGLES.cbr_force_load_dlc_packages = {
    apply = function(saved)
        if not Managers or not Managers.package then return end
        local packages = {
            "resource_packages/careers/wh_priest",
            "resource_packages/careers/bw_unchained",
            "resource_packages/dlcs/wizards_part_2",
            "resource_packages/mutators/mutators_batch_04",
            "resource_packages/levels/morris_ingame",
            "resource_packages/mutators/mutator_curse_skulls_of_fury",
            "resource_packages/mutators/mutator_curse_blood_storm",
        }
        saved.loaded_packages = {}
        for _, pkg in ipairs(packages) do
            local ok = pcall(function()
                Managers.package:load(pkg, "global", nil, true)
            end)
            if ok then saved.loaded_packages[#saved.loaded_packages + 1] = pkg end
        end
    end,
    restore = function(saved)
        -- Package unload is risky in mid-mission; leave them loaded once loaded.
        saved.loaded_packages = nil
    end,
}

-- ============================================================
-- 2. Kruber > Mercenary (12)
-- ============================================================
_toggle_talent_modify("cbr_merc_row2_talent_2_2_desc", {
    { "es_mercenary", 2, 2, { description_values = { { value = 1, value_type = "percent" } } } },
})
_toggle_talent_modify("cbr_merc_row2_talent_2_3_clear_perks", {
    { "es_mercenary", 2, 3, { perks = {} } },
})
_toggle_talent_modify("cbr_merc_row4_talent_4_1_desc", {
    { "es_mercenary", 4, 1, { description_values = { { value = 0.2 } } } },
})
BR_TOGGLES.cbr_merc_row5_talent_5_3_ammo_on_elite_melee = {
    apply = function(saved)
        _safe_modify_talent(saved, "es_mercenary", 5, 3, { buffs = { "gs_merc_ammo_on_melee_kills" } })
    end,
    restore = function(saved) _restore_modified_talents(saved) end,
}
BR_TOGGLES.cbr_merc_row6_talent_6_3_ult_revive = {
    apply = function(saved)
        _safe_modify_talent(saved, "es_mercenary", 6, 3, { buffs = { "gs_markus_mercenary_activated_ability_revive" } })
    end,
    restore = function(saved) _restore_modified_talents(saved) end,
}
_toggle_field_patches("cbr_merc_passive_paced_strikes_single_target", {
    { buff = "markus_mercenary_passive_improved", field = "targets", value = 1 },
})
_toggle_field_patches("cbr_merc_passive_custom_proc", {
    { buff = "markus_mercenary_passive", field = "buff_func", value = "gs_gain_markus_mercenary_passive_proc" },
})
_toggle_field_patches("cbr_merc_passive_power_level", {
    { buff = "markus_mercenary_passive_power_level", field = "multiplier", value = 0.2 },
})
_toggle_field_patches("cbr_merc_cdr_on_damage_taken", {
    { buff = "markus_mercenary_ability_cooldown_on_damage_taken", field = "bonus", value = 0.25 },
})
_toggle_field_patches("cbr_merc_power_cleave_multiplier_1", {
    { buff = "markus_mercenary_power_level_cleave", field = "multiplier", value = 1 },
})
_toggle_field_patches("cbr_merc_dodge_range_infinite_dodges", {
    { buff = "markus_mercenary_dodge_range", field = "perks", value = { "infinite_dodge" } },
})
_toggle_table_patches("cbr_merc_ult_cooldown_40", function(set)
    if ActivatedAbilitySettings and ActivatedAbilitySettings.es_2 and ActivatedAbilitySettings.es_2[1] then
        set(ActivatedAbilitySettings.es_2[1], "cooldown", 40)
    end
end)

-- ============================================================
-- 3. Kruber > Foot Knight (~22)
-- ============================================================
_toggle_talent_modify("cbr_fk_row2_talent_2_3_buffer_both", {
    { "es_knight", 2, 3, { buffer = "both" } },
})
BR_TOGGLES.cbr_fk_row5_talent_5_1_ult_cdr_on_incap = {
    apply = function(saved)
        _safe_modify_talent(saved, "es_knight", 5, 1, {
            buffer = "both",
            buffs = { "markus_knight_movement_speed_on_incapacitated_allies", "markus_knight_cooldown_on_incapacitated_allies_buff" },
        })
    end,
    restore = function(saved) _restore_modified_talents(saved) end,
}
BR_TOGGLES.cbr_fk_row5_talent_5_2_piston = {
    apply = function(saved)
        _safe_modify_talent(saved, "es_knight", 5, 2, { buffs = { "gs_fk_piston" } })
    end,
    restore = function(saved) _restore_modified_talents(saved) end,
}
BR_TOGGLES.cbr_fk_row6_talent_6_2_heavy_buff = {
    apply = function(saved)
        _safe_modify_talent(saved, "es_knight", 6, 2, { buffs = { "markus_knight_heavy_buff" } })
    end,
    restore = function(saved) _restore_modified_talents(saved) end,
}
_toggle_field_patches("cbr_fk_passive_dr_15", {
    { buff = "markus_knight_passive_damage_reduction", field = "multiplier", value = -0.15 },
})
_toggle_field_patches("cbr_fk_aura_range_dr_10", {
    { buff = "markus_knight_passive_defence_aura_range", field = "multiplier", value = -0.1 },
})
_toggle_field_patches("cbr_fk_aura_dr_10", {
    { buff = "markus_knight_passive_defence_aura", field = "multiplier", value = -0.1 },
})
_toggle_field_patches("cbr_fk_passive_range_10", {
    { buff = "markus_knight_passive", field = "range", value = 10 },
})
_toggle_field_patches("cbr_fk_passive_range_config", {
    { buff = "markus_knight_passive_range", field = "range", value = 20 },
})
_toggle_field_patches("cbr_fk_passive_guard_defence_config", {
    { buff = "markus_knight_guard_defence", field = "multiplier", value = -0.1 },
})
_toggle_field_patches("cbr_fk_passive_guard_power_config", {
    { buff = "markus_knight_guard", field = "multiplier", value = 0.15 },
})
_toggle_field_patches("cbr_fk_passive_proximity_stacks_config", {
    { buff = "markus_knight_damage_taken_ally_proximity", field = "update_func", value = "activate_party_buff_stacks_on_ally_proximity" },
})
_toggle_field_patches("cbr_fk_passive_proximity_dr_per_ally", {
    { buff = "markus_knight_damage_taken_ally_proximity_buff", field = "multiplier", value = -0.033 },
})
_toggle_field_patches("cbr_fk_cdr_on_damage_taken_35", {
    { buff = "markus_knight_ability_cooldown_on_damage_taken", field = "bonus", value = 0.35 },
})
_toggle_field_patches("cbr_fk_on_stagger_changed_to_on_kill", {
    { buff = "markus_knight_power_level_on_stagger_elite", field = "event", value = "on_kill" },
    { buff = "markus_knight_power_level_on_stagger_elite_buff", field = "duration", value = 3 },
})
_toggle_field_patches("cbr_fk_attack_speed_on_cleave_hit2", {
    { buff = "markus_knight_attack_speed_on_push", field = "multiplier", value = 0.05 },
    { buff = "markus_knight_attack_speed_on_push", field = "event", value = "on_player_damage_dealt" },
})
_toggle_field_patches("cbr_fk_free_push_duration_2", {
    { buff = "markus_knight_free_pushes_on_block_buff", field = "duration", value = 2 },
})
_toggle_field_patches("cbr_fk_cdr_on_stagger_elite_func", {
    { buff = "markus_knight_cooldown_on_stagger_elite", field = "buff_func", value = "markus_knight_cooldown_on_stagger_elite" },
})
_toggle_field_patches("cbr_fk_cdr_on_stagger_elite_buff_config", {
    { buff = "markus_knight_cooldown_buff", field = "bonus", value = 0.05 },
    { buff = "markus_knight_cooldown_buff", field = "duration", value = 1 },
})
_toggle_field_patches("cbr_fk_ult_invuln_4s_ledge_rescue", {
    { buff = "markus_knight_ability_invulnerability_buff", field = "duration", value = 4 },
    { buff = "markus_knight_ability_invulnerability_buff", field = "perks", value = { "ledge_self_rescue" } },
})
_toggle_field_patches("cbr_fk_ult_as_per_hit_2pc", {
    { buff = "markus_knight_ability_attack_speed_enemy_hit_buff", field = "multiplier", value = 0.02 },
})
BR_TOGGLES.cbr_fk_ult_charge_overhaul = { apply = function() end, restore = function() end }

-- ============================================================
-- 4. Kruber > Huntsman (~15)
-- ============================================================
_toggle_table_patches("cbr_huntsman_ult_cooldown_60", function(set)
    if ActivatedAbilitySettings and ActivatedAbilitySettings.es_1 and ActivatedAbilitySettings.es_1[1] then
        set(ActivatedAbilitySettings.es_1[1], "cooldown", 60)
    end
end)
BR_TOGGLES.cbr_huntsman_passive_buff_list_overhaul = {
    apply = function(saved)
        _safe_replace_passive_buffs(saved, "es_1", {
            "markus_huntsman_passive",
            "markus_huntsman_passive_crit_aura",
            "markus_huntsman_passive_temp_health_on_headshot",
            "markus_huntsman_reload_passive",
            "monster_limiter",
            "friend_protection",
            "guaranteed_ranged_crit_huntsman",
            "markus_huntsman_passive_block_cost",
            "markus_huntsman_increased_zoom",
            "markus_huntsman_increased_ammo",
            "markus_huntsman_passive_no_overcharge_decay_delay",
        })
    end,
    restore = function(saved) _restore_passive_replacements(saved) end,
}
_toggle_field_patches("cbr_huntsman_cdr_on_damage_taken_25", {
    { buff = "markus_huntsman_ability_cooldown_on_damage_taken", field = "bonus", value = 0.25 },
})
_toggle_field_patches("cbr_huntsman_passive_crit_aura_range_10", {
    { buff = "markus_huntsman_passive_crit_aura", field = "range", value = 10 },
})
_toggle_field_patches("cbr_huntsman_passive_icon_stacks", {
    { buff = "markus_huntsman_passive", field = "max_stacks", value = 3 },
})
_toggle_field_patches("cbr_huntsman_thp_on_ranged_kill_bloodlust", {
    { buff = "markus_huntsman_passive_temp_health_on_headshot", field = "event", value = "on_kill" },
    { buff = "markus_huntsman_passive_temp_health_on_headshot", field = "buff_func", value = "gs_heal_on_ranged_kill" },
})
BR_TOGGLES.cbr_huntsman_row2_talent_2_2_haste = {
    apply = function(saved)
        _safe_modify_talent(saved, "es_huntsman", 2, 2, { buffs = { "gs_haste" } })
    end,
    restore = function(saved) _restore_modified_talents(saved) end,
}
_toggle_talent_modify("cbr_huntsman_row4_talent_4_3_desc", {
    { "es_huntsman", 4, 3, { description_values = { { value = 0.5 } } } },
})
BR_TOGGLES.cbr_huntsman_row5_talent_5_1_bleed_on_crit = {
    apply = function(saved)
        _safe_modify_talent(saved, "es_huntsman", 5, 1, { buffs = { "markus_huntsman_bleed_on_hit" } })
    end,
    restore = function(saved) _restore_modified_talents(saved) end,
}
BR_TOGGLES.cbr_huntsman_row5_talent_5_2_dr_on_elite_kill = {
    apply = function(saved)
        _safe_modify_talent(saved, "es_huntsman", 5, 2, {
            buffs = { "markus_huntsman_damage_taken_on_elite_or_special_kill" }
        })
    end,
    restore = function(saved) _restore_modified_talents(saved) end,
}
BR_TOGGLES.cbr_huntsman_row5_talent_5_3_sniper_perfect_accuracy = {
    apply = function(saved)
        _safe_modify_talent(saved, "es_huntsman", 5, 3, {
            buffs = { "gs_sniper_buff_1", "gs_sniper_buff_2", "gs_sniper_buff_3", "gs_sniper_buff_4" }
        })
    end,
    restore = function(saved) _restore_modified_talents(saved) end,
}
_toggle_talent_modify("cbr_huntsman_row6_talent_6_1_add_ult_penetration", {
    { "es_huntsman", 6, 1, { buffs = { "markus_huntsman_activated_ability", "gs_markus_huntsman_activated_ability_extra_penetration" } } },
})
BR_TOGGLES.cbr_huntsman_row6_talent_6_2_ult_pierce_big = {
    apply = function(saved)
        _safe_modify_talent(saved, "es_huntsman", 6, 2, {
            buffs = { "gs_markus_huntsman_activated_ability_extra_penetration_big" }
        })
    end,
    restore = function(saved) _restore_modified_talents(saved) end,
}
BR_TOGGLES.cbr_huntsman_row6_talent_6_3_ult_pierce = {
    apply = function(saved)
        _safe_modify_talent(saved, "es_huntsman", 6, 3, {
            buffs = { "gs_markus_huntsman_activated_ability_extra_penetration" }
        })
    end,
    restore = function(saved) _restore_modified_talents(saved) end,
}
-- Huntsman > Ult: explosion overhaul (data overlay only).
-- Source: experimental_talent_changes.lua:480/494 (explosions) +
-- kruber_changes.lua:1216/1230 (buffs). The buffs reference BR-installed
-- proc/buff funcs (huntsman_activated_ability_explosion,
-- end_gs_huntsman_activated_ability, etc.) — if bt doesn't install them
-- the overlay is harmless (dispatcher no-ops). The vanilla
-- CareerAbilityESHuntsman._run_ability hook (which dispatches the actual
-- explosion at activation) is NOT installed here — see Deferred list. Bodies
-- still ride in so re-toggling without a restart picks up the deferred hook
-- once it lands.
BR_TOGGLES.cbr_huntsman_ult_explosion_overhaul = {
    apply = function(saved)
        saved.huntsman_old = {}
        if ExplosionTemplates and ExplosionTemplates.huntsman_ability_explosion then
            saved.huntsman_old.expl_basic = ExplosionTemplates.huntsman_ability_explosion.explosion
            ExplosionTemplates.huntsman_ability_explosion.explosion = {
                use_attacker_power_level = true,
                radius = 10,
                effect_name = "fx/chr_kruber_shockwave",
                no_prop_damage = true,
                alert_enemies = true,
                alert_enemies_radius = 10,
                attack_template = "drakegun",
                sound_event_name = "player_combat_weapon_grenade_explosion",
                damage_profile = "ability_push",
                no_friendly_fire = true,
            }
        end
        if ExplosionTemplates and ExplosionTemplates.huntsman_ability_explosion_debuff then
            saved.huntsman_old.expl_debuff = ExplosionTemplates.huntsman_ability_explosion_debuff.explosion
            ExplosionTemplates.huntsman_ability_explosion_debuff.explosion = {
                use_attacker_power_level = true,
                radius = 10,
                effect_name = "fx/chr_kruber_shockwave",
                no_prop_damage = true,
                attack_template = "drakegun",
                sound_event_name = "player_combat_weapon_grenade_explosion",
                damage_profile = "ability_push",
                no_friendly_fire = true,
                enemy_debuff = { "defence_debuff_enemies_huntsman_explosion" },
            }
        end
        if BuffTemplates and BuffTemplates.gs_markus_huntsman_activated_ability then
            saved.huntsman_old.buff_main = BuffTemplates.gs_markus_huntsman_activated_ability.buffs[1]
            BuffTemplates.gs_markus_huntsman_activated_ability.buffs[1] = {
                name = "markus_huntsman_activated_ability",
                buff_to_add = "gs_markus_huntsman_activated_ability_remover",
                multiplier = 3,
                stat_buff = "increased_weapon_damage_ranged",
                buff_func = "huntsman_activated_ability_explosion",
                event = "on_hit",
                remove_buff_func = "end_huntsman_activated_ability",
                apply_buff_func = "apply_huntsman_activated_ability",
                duration = 6,
                continuous_effect = "fx/screenspace_huntsman_skill_01",
                max_stacks = 1,
                icon = "markus_huntsman_activated_ability",
            }
        end
        if BuffTemplates and BuffTemplates.gs_markus_huntsman_activated_ability_remover then
            saved.huntsman_old.buff_remover = BuffTemplates.gs_markus_huntsman_activated_ability_remover.buffs[1]
            BuffTemplates.gs_markus_huntsman_activated_ability_remover.buffs[1] = {
                name = "gs_markus_huntsman_activated_ability_remover",
                max_stacks = 1,
                remove_buff_func = "end_gs_huntsman_activated_ability",
                refresh_durations = true,
                duration = 0.1,
            }
        end
    end,
    restore = function(saved)
        if not saved.huntsman_old then return end
        if saved.huntsman_old.expl_basic and ExplosionTemplates and ExplosionTemplates.huntsman_ability_explosion then
            ExplosionTemplates.huntsman_ability_explosion.explosion = saved.huntsman_old.expl_basic
        end
        if saved.huntsman_old.expl_debuff and ExplosionTemplates and ExplosionTemplates.huntsman_ability_explosion_debuff then
            ExplosionTemplates.huntsman_ability_explosion_debuff.explosion = saved.huntsman_old.expl_debuff
        end
        if saved.huntsman_old.buff_main and BuffTemplates and BuffTemplates.gs_markus_huntsman_activated_ability then
            BuffTemplates.gs_markus_huntsman_activated_ability.buffs[1] = saved.huntsman_old.buff_main
        end
        if saved.huntsman_old.buff_remover and BuffTemplates and BuffTemplates.gs_markus_huntsman_activated_ability_remover then
            BuffTemplates.gs_markus_huntsman_activated_ability_remover.buffs[1] = saved.huntsman_old.buff_remover
        end
        saved.huntsman_old = nil
    end,
}

-- ============================================================
-- 5. Kruber > Grail Knight (~8)
-- ============================================================
_toggle_table_patches("cbr_gk_ult_cooldown_60", function(set)
    if ActivatedAbilitySettings and ActivatedAbilitySettings.es_4 and ActivatedAbilitySettings.es_4[1] then
        set(ActivatedAbilitySettings.es_4[1], "cooldown", 60)
    end
end)
_toggle_talent_modify("cbr_gk_row2_talent_2_2_crit_insta_kill", {
    { "es_questingknight", 2, 2, { buffs = { "markus_questing_knight_crit_insta_kill" } } },
})
BR_TOGGLES.cbr_gk_row2_talent_2_3_first_target_45pc = {
    apply = function(saved)
        _safe_modify_talent(saved, "es_questingknight", 2, 3, {
            buffs = { "gs_markus_questing_knight_first_target_increase" }
        })
    end,
    restore = function(saved) _restore_modified_talents(saved) end,
}
_toggle_talent_modify("cbr_gk_row5_talent_5_2_infinite_dodges", {
    { "es_questingknight", 5, 2, { buffs = { "markus_mercenary_dodge_range" } } },
})
BR_TOGGLES.cbr_gk_row6_talent_6_2_cdr_30pc = {
    apply = function(saved)
        _safe_modify_talent(saved, "es_questingknight", 6, 2, {
            buffs = { "gs_markus_cooldown_reduction" }
        })
    end,
    restore = function(saved) _restore_modified_talents(saved) end,
}
_toggle_field_patches("cbr_gk_ult_kill_buff_no_ranged_knockback", {
    { buff = "markus_questing_knight_ability_buff_on_kill_movement_speed", field = "perks", value = {} },
})
BR_TOGGLES.cbr_gk_ult_vfx_and_kill_buff = { apply = function() end, restore = function() end }
BR_TOGGLES.cbr_gk_side_quest_rework_strength_potion = { apply = function() end, restore = function() end }

-- ============================================================
-- 6. Bardin > Ironbreaker (~9)
-- ============================================================
-- IB > Ult: gromril delay buff (data overlay only).
-- Source: bardin_changes.lua:325. The wholesale
-- CareerAbilityDRIronbreaker._run_ability rewrite that triggers this buff is
-- deferred (see Deferred list). The duration_end_func `add_buff_local` is
-- a vanilla buff func. Safe to overlay.
BR_TOGGLES.cbr_ib_ult_overhaul_50pc_dr_talents = {
    apply = function(saved)
        if BuffTemplates and BuffTemplates.bardin_ironbreaker_gromril_delay_long then
            saved.ib_gromril_old = BuffTemplates.bardin_ironbreaker_gromril_delay_long.buffs[1]
            BuffTemplates.bardin_ironbreaker_gromril_delay_long.buffs[1] = {
                buff_to_add = "bardin_ironbreaker_gromril_armour",
                name = "gromril_delay_long",
                is_cooldown = true,
                duration_end_func = "add_buff_local",
                max_stacks = 1,
                refresh_durations = true,
                icon = "bardin_ironbreaker_gromril_armour",
                duration = 25,
            }
        end
    end,
    restore = function(saved)
        if saved.ib_gromril_old and BuffTemplates and BuffTemplates.bardin_ironbreaker_gromril_delay_long then
            BuffTemplates.bardin_ironbreaker_gromril_delay_long.buffs[1] = saved.ib_gromril_old
            saved.ib_gromril_old = nil
        end
    end,
}
_toggle_field_patches("cbr_ib_passive_overcharge_no_slow", {
    { buff = "bardin_ironbreaker_passive_increased_defence", field = "perks", value = {} },
})
BR_TOGGLES.cbr_ib_row2_talent_2_1_drakefire_heat_and_speed = {
    apply = function(saved)
        _safe_modify_talent(saved, "dr_ironbreaker", 2, 1, {
            buffs = { "gs_ib_decreased_heat_cost", "gs_ib_increased_drakefire_speed" }
        })
    end,
    restore = function(saved) _restore_modified_talents(saved) end,
}
_toggle_field_patches("cbr_ib_passive_power_on_ally_75pc_range_10", {
    { buff = "bardin_ironbreaker_power_on_nearby_allies", field = "range", value = 10 },
    { buff = "bardin_ironbreaker_power_on_nearby_allies_buff", field = "multiplier", value = 0.075 },
})
_toggle_field_patches("cbr_ib_party_power_on_block_3pc_15s", {
    { buff = "bardin_ironbreaker_party_power_on_blocked_attacks_buff", field = "multiplier", value = 0.03 },
    { buff = "bardin_ironbreaker_party_power_on_blocked_attacks_buff", field = "duration", value = 15 },
})
_toggle_field_patches("cbr_ib_rising_anger_3pc_as", {
    { buff = "bardin_ironbreaker_gromril_rising_anger", field = "stat_buff", value = "attack_speed" },
    { buff = "bardin_ironbreaker_gromril_rising_anger", field = "multiplier", value = 0.03 },
})
_toggle_field_patches("cbr_ib_gromril_as_6pc_15s", {
    { buff = "bardin_ironbreaker_gromril_attack_speed", field = "duration", value = 15 },
    { buff = "bardin_ironbreaker_gromril_attack_speed", field = "multiplier", value = 0.06 },
})
_toggle_talent_modify("cbr_ib_row5_talent_5_3_piston_power", {
    { "dr_ironbreaker", 5, 3, { buffer = "both", buffs = { "bardin_engineer_piston_powered" } } },
})
_toggle_field_patches("cbr_ib_piston_icon_swaps", {
    { buff = "bardin_engineer_piston_powered_delay", field = "icon", value = "bardin_engineer_piston_powered_delay" },
    { buff = "bardin_engineer_piston_powered_ready", field = "icon", value = "bardin_engineer_piston_powered_ready" },
})

-- ============================================================
-- 7. Bardin > Ranger Veteran (~11)
-- ============================================================
BR_TOGGLES.cbr_ranger_row2_talent_2_1_dupe_10pc = {
    apply = function(saved)
        _safe_modify_talent(saved, "dr_ranger", 2, 1, {
            buffs = { "gs_increased_dupe_healing", "gs_increased_dupe_potion", "gs_increased_dupe_bomb" }
        })
    end,
    restore = function(saved) _restore_modified_talents(saved) end,
}
BR_TOGGLES.cbr_ranger_row2_talent_2_3_as_on_empty_clip = {
    apply = function(saved)
        _safe_modify_talent(saved, "dr_ranger", 2, 3, {
            buffs = { "gs_attack_speed_on_empty_clip" }
        })
    end,
    restore = function(saved) _restore_modified_talents(saved) end,
}
_toggle_field_patches("cbr_ranger_passive_custom_drops", {
    { buff = "bardin_ranger_passive", field = "buff_func", value = "gs_bardin_ranger_scavenge_proc" },
})
BR_TOGGLES.cbr_ranger_passive_throwing_axes_ammo = {
    apply = function(saved) _safe_append_passive_buff(saved, "dr_3", "gs_ammo_on_melee_kills_throwing_axes_buff") end,
    restore = function(saved) _restore_passive_appends(saved) end,
}
BR_TOGGLES.cbr_ranger_row5_talent_5_1_sniper_perfect_accuracy = {
    apply = function(saved)
        _safe_modify_talent(saved, "dr_ranger", 5, 1, {
            buffs = { "gs_dr_sniper_buff_1", "gs_dr_sniper_buff_2", "gs_dr_sniper_buff_3", "gs_dr_sniper_buff_4" }
        })
    end,
    restore = function(saved) _restore_modified_talents(saved) end,
}
_toggle_field_patches("cbr_ranger_thp_headshot_dr_20pc", {
    { buff = "bardin_ranger_reduced_damage_taken_headshot_buff", field = "multiplier", value = -0.2 },
})
_toggle_talent_modify("cbr_ranger_row5_talent_5_2_desc", {
    { "dr_ranger", 5, 2, { description_values = { { value = 0.1 } } } },
})
BR_TOGGLES.cbr_ranger_extended_ranged_boost_multipliers = { apply = function() end, restore = function() end }
BR_TOGGLES.cbr_ranger_row6_talent_6_3_free_grenade_on_disengage = {
    apply = function(saved)
        _safe_modify_talent(saved, "dr_ranger", 6, 3, {
            buffs = { "1_grenade_start", "bardin_ranger_increased_ult_cooldown" }
        })
    end,
    restore = function(saved) _restore_modified_talents(saved) end,
}
_toggle_field_patches("cbr_ranger_free_grenade_buff_10s", {
    { buff = "bardin_ranger_ability_free_grenade_buff", field = "duration", value = 10 },
    { buff = "bardin_ranger_ability_free_grenade_buff", field = "refresh_durations", value = true },
})
-- Ranger > Ult: smoke screen buff (data overlay only).
-- Source: bardin_changes.lua:617. The
-- ActionCareerDRRanger._create_smoke_screen hook that ADDS this buff to the
-- ult is deferred (see Deferred list). The buff body still rides in so once
-- the hook lands the +1 ranged penetration stat is fully wired.
BR_TOGGLES.cbr_ranger_smoke_screen_buff_additions = {
    apply = function(saved)
        if BuffTemplates and BuffTemplates.bardin_ranger_activated_ability_stealth_outside_of_smoke_pierce then
            saved.ranger_smoke_old = BuffTemplates.bardin_ranger_activated_ability_stealth_outside_of_smoke_pierce.buffs[1]
            BuffTemplates.bardin_ranger_activated_ability_stealth_outside_of_smoke_pierce.buffs[1] = {
                name = "bardin_ranger_activated_ability_stealth_outside_of_smoke_pierce",
                duration = 10,
                stat_buff = "ranged_additional_penetrations",
                max_stacks = 1,
                refresh_durations = true,
                bonus = 1,
            }
        end
    end,
    restore = function(saved)
        if saved.ranger_smoke_old and BuffTemplates and BuffTemplates.bardin_ranger_activated_ability_stealth_outside_of_smoke_pierce then
            BuffTemplates.bardin_ranger_activated_ability_stealth_outside_of_smoke_pierce.buffs[1] = saved.ranger_smoke_old
            saved.ranger_smoke_old = nil
        end
    end,
}
-- Ranger > Ult: fire/AOE explosion templates (overlay into pre-registered stubs).
-- Source: experimental_talent_changes.lua:376 / 393. Notes the _aoe variant's
-- dot_template_name references `long_burn_low_damage` which is owned by the
-- cross-buffs section (cbr_buff_long_burn_low_damage). If that toggle is off,
-- the dot key still resolves to an existing pre-registered buff so no fatal —
-- just the dot won't trigger the BR-tuned ticks.
BR_TOGGLES.cbr_ranger_ult_explosion_templates = {
    apply = function(saved)
        if not ExplosionTemplates then return end
        saved.ranger_expl_old = {}
        if ExplosionTemplates.bardin_ranger_activated_ability_fire then
            saved.ranger_expl_old.fire = ExplosionTemplates.bardin_ranger_activated_ability_fire
            ExplosionTemplates.bardin_ranger_activated_ability_fire = {
                name = "bardin_ranger_activated_ability_fire",
                is_grenade = true,
                explosion = {
                    always_hurt_players = false,
                    radius = 7,
                    no_prop_damage = true,
                    max_damage_radius = 2,
                    use_attacker_power_level = true,
                    alert_enemies_radius = 15,
                    sound_event_name = "Play_bardin_ranger_smoke_grenade_ability",
                    attack_template = "drakegun",
                    alert_enemies = true,
                    damage_profile = "ability_push",
                    no_friendly_fire = true,
                },
            }
        end
        if ExplosionTemplates.bardin_ranger_activated_ability_aoe then
            saved.ranger_expl_old.aoe = ExplosionTemplates.bardin_ranger_activated_ability_aoe
            ExplosionTemplates.bardin_ranger_activated_ability_aoe = {
                name = "bardin_ranger_activated_ability_aoe",
                explosion = {
                    attack_template = "fire_grenade_dot",
                    radius = 6,
                    create_nav_tag_volume = true,
                    nav_tag_volume_layer = "fire_grenade",
                    dot_template_name = "long_burn_low_damage",
                    sound_event_name = "player_combat_weapon_fire_grenade_explosion",
                    damage_interval = 0.2,
                    duration = 10,
                    area_damage_template = "explosion_template_aoe",
                    nav_mesh_effect = {
                        particle_radius = 10,
                        particle_spacing = 0.9,
                        particle_name = "fx/wpnfx_fire_grenade_impact_remains",
                    },
                },
            }
        end
    end,
    restore = function(saved)
        if not saved.ranger_expl_old then return end
        if saved.ranger_expl_old.fire and ExplosionTemplates then
            ExplosionTemplates.bardin_ranger_activated_ability_fire = saved.ranger_expl_old.fire
        end
        if saved.ranger_expl_old.aoe and ExplosionTemplates then
            ExplosionTemplates.bardin_ranger_activated_ability_aoe = saved.ranger_expl_old.aoe
        end
        saved.ranger_expl_old = nil
    end,
}

-- ============================================================
-- 8. Bardin > Slayer (~11)
-- ============================================================
BR_TOGGLES.cbr_slayer_passive_perks_reflow = {
    apply = function(saved)
        _safe_append_passive_buff(saved, "dr_2", "gs_ammo_on_melee_kills_throwing_axes_buff")
        _safe_append_passive_buff(saved, "dr_2", "gs_bardin_slayer_increased_defence")
    end,
    restore = function(saved) _restore_passive_appends(saved) end,
}
_toggle_field_patches("cbr_slayer_melee_charge_dr_25pc", {
    { buff = "bardin_slayer_damage_reduction_on_melee_charge_action_buff", field = "multiplier", value = -0.25 },
})
_toggle_talent_modify("cbr_slayer_row5_talent_5_2_desc", {
    { "dr_slayer", 5, 2, { description_values = { { value = 0.2 } } } },
})
_toggle_talent_modify("cbr_slayer_row2_talent_2_1_dual_wield_combos", {
    { "dr_slayer", 2, 1, { buffs = { "bardin_slayer_dual_wield_combos" } } },
})
BR_TOGGLES.cbr_slayer_row2_talent_2_2_add_max_stacks = {
    apply = function(saved)
        _safe_modify_talent(saved, "dr_slayer", 2, 2, {
            buffs = { "gs_bardin_slayer_passive_increased_max_stacks" }
        })
    end,
    restore = function(saved) _restore_modified_talents(saved) end,
}
BR_TOGGLES.cbr_slayer_row2_talent_2_3_crit_below_hp = {
    apply = function(saved)
        _safe_modify_talent(saved, "dr_slayer", 2, 3, {
            buffs = { "gs_bardin_slayer_crit_chance", "gs_bardin_slayer_crit_chance_2" }
        })
    end,
    restore = function(saved) _restore_modified_talents(saved) end,
}
_toggle_field_patches("cbr_slayer_passive_custom_stack_proc", {
    { buff = "bardin_slayer_passive_stacking_damage_buff_on_hit", field = "buff_func", value = "gs_add_bardin_slayer_passive_buff" },
})
BR_TOGGLES.cbr_slayer_row4_talent_4_2_add_blood_drunk = {
    apply = function(saved)
        _safe_modify_talent(saved, "dr_slayer", 4, 2, {
            buffs = { "gs_bardin_slayer_passive_stacking_crit_buff" }
        })
    end,
    restore = function(saved) _restore_modified_talents(saved) end,
}
_toggle_talent_modify("cbr_slayer_row4_talent_4_3_desc", {
    { "dr_slayer", 4, 3, { description_values = { { value = 0.1 } } } },
})
BR_TOGGLES.cbr_slayer_row5_talent_5_3_scaling_dr = {
    apply = function(saved)
        _safe_modify_talent(saved, "dr_slayer", 5, 3, {
            buffs = { "gs_bardin_slayer_dr_scaling" }
        })
    end,
    restore = function(saved) _restore_modified_talents(saved) end,
}
BR_TOGGLES.cbr_slayer_ult_double_leap_overhaul = { apply = function() end, restore = function() end }

-- ============================================================
-- 9. Bardin > Engineer (~10)
-- ============================================================
_toggle_table_patches("cbr_engineer_max_hp_125", function(set)
    if CareerSettings and CareerSettings.dr_engineer and CareerSettings.dr_engineer.attributes then
        set(CareerSettings.dr_engineer.attributes, "max_hp", 125)
    end
end)
_toggle_table_patches("cbr_engineer_base_crit_10pc", function(set)
    if CareerSettings and CareerSettings.dr_engineer and CareerSettings.dr_engineer.attributes then
        set(CareerSettings.dr_engineer.attributes, "base_critical_strike_chance", 0.1)
    end
end)
BR_TOGGLES.cbr_engineer_passive_add_falling_stacks = {
    apply = function(saved) _safe_append_passive_buff(saved, "dr_4", "falling_stacks_engineer") end,
    restore = function(saved) _restore_passive_appends(saved) end,
}
_toggle_field_patches("cbr_engineer_pump_buff_no_timeout", {
    { buff = "bardin_engineer_pump_buff", field = "duration", value = false },
})
BR_TOGGLES.cbr_engineer_row2_talent_2_3_clip_size_vs_power = {
    apply = function(saved)
        _safe_modify_talent(saved, "dr_engineer", 2, 3, { buffs = { "bardin_engineer_clip_size" } })
    end,
    restore = function(saved) _restore_modified_talents(saved) end,
}
BR_TOGGLES.cbr_engineer_row4_talent_4_1_as_and_crank_debuff = {
    apply = function(saved)
        _safe_modify_talent(saved, "dr_engineer", 4, 1, {
            buffs = { "bardin_engineer_4_1_buff", "bardin_engineer_melee_attack_speed_buff", "bardin_engineer_crank_gun_debuff" }
        })
        _safe_set_buff_field(saved, "bardin_engineer_4_1_buff", "multiplier", 0.04)
    end,
    restore = function(saved) _restore_modified_talents(saved); _restore_buff_fields(saved) end,
}
BR_TOGGLES.cbr_engineer_row5_talent_5_3_crit_heavy_explosion = {
    apply = function(saved)
        _safe_modify_talent(saved, "dr_engineer", 5, 3, {
            buffs = { "gs_bardin_engineer_passive_heavy_explosion", "gs_bardin_engineer_crit_chance" }
        })
    end,
    restore = function(saved) _restore_modified_talents(saved) end,
}
BR_TOGGLES.cbr_engineer_row6_talent_6_2_ability_check = {
    apply = function(saved)
        _safe_modify_talent(saved, "dr_engineer", 6, 2, {
            buffs = { "bardin_engineer_ability_check", "bardin_engineer_ability_buff" }
        })
    end,
    restore = function(saved) _restore_modified_talents(saved) end,
}
BR_TOGGLES.cbr_engineer_crank_gun_no_slowdown_ramp = { apply = function() end, restore = function() end }
-- Engineer > Misc: survival ale 3-buff rework.
-- Source: bardin_changes.lua:547-561. Direct field tweaks on vanilla
-- BuffTemplates.bardin_survival_ale_buff.buffs[1/2] (DR / AS) plus inserting
-- a new buffs[3] (heal-over-time using BR's bardin_ranger_heal_smoke buff
-- func). If bt doesn't install that func, buffs[3] is inert; buffs[1/2]
-- tweaks are pure data.
BR_TOGGLES.cbr_engineer_survival_ale_buffs = {
    apply = function(saved)
        if not BuffTemplates or not BuffTemplates.bardin_survival_ale_buff then return end
        local ale = BuffTemplates.bardin_survival_ale_buff
        saved.ale_old = { b1 = {}, b2 = {}, b3 = ale.buffs[3] }
        for _, f in ipairs({ "multiplier", "max_stacks", "duration" }) do
            saved.ale_old.b1[f] = ale.buffs[1] and ale.buffs[1][f]
            saved.ale_old.b2[f] = ale.buffs[2] and ale.buffs[2][f]
        end
        if ale.buffs[1] then
            ale.buffs[1].multiplier = -0.05
            ale.buffs[1].max_stacks = 2
            ale.buffs[1].duration = 420
        end
        if ale.buffs[2] then
            ale.buffs[2].multiplier = 0.075
            ale.buffs[2].max_stacks = 2
            ale.buffs[2].duration = 420
        end
        ale.buffs[3] = {
            time_between_heals = 1,
            name = "ale_heal",
            heal_amount = 2,
            update_func = "bardin_ranger_heal_smoke",
            max_stacks = 1,
            refresh_durations = true,
            duration = 5,
        }
    end,
    restore = function(saved)
        if not saved.ale_old or not BuffTemplates or not BuffTemplates.bardin_survival_ale_buff then return end
        local ale = BuffTemplates.bardin_survival_ale_buff
        if ale.buffs[1] then
            for f, v in pairs(saved.ale_old.b1) do ale.buffs[1][f] = v end
        end
        if ale.buffs[2] then
            for f, v in pairs(saved.ale_old.b2) do ale.buffs[2][f] = v end
        end
        ale.buffs[3] = saved.ale_old.b3
        saved.ale_old = nil
    end,
}

-- ============================================================
-- 10. Kerillian > Waywatcher (~17)
-- ============================================================
_toggle_table_patches("cbr_ww_ult_cd_60", function(set)
    if ActivatedAbilitySettings and ActivatedAbilitySettings.we_3 and ActivatedAbilitySettings.we_3[1] then
        set(ActivatedAbilitySettings.we_3[1], "cooldown", 60)
    end
end)
BR_TOGGLES.cbr_ww_passive_zoom = {
    apply = function(saved) _safe_append_passive_buff(saved, "we_1", "kerillian_waywatcher_passive_increased_zoom") end,
    restore = function(saved) _restore_passive_appends(saved) end,
}
BR_TOGGLES.cbr_ww_passive_faster_bows = {
    apply = function(saved) _safe_append_passive_buff(saved, "we_3", "faster_bows") end,
    restore = function(saved) _restore_passive_appends(saved) end,
}
_toggle_field_patches("cbr_ww_passive_ammo_50pct", {
    { buff = "kerillian_waywatcher_passive_increased_ammunition", field = "multiplier", value = 0.5 },
})
_toggle_field_patches("cbr_ww_amaranthe_rework", {
    { buff = "kerillian_waywatcher_passive", field = "heal_amount", value = 0.5 },
})
_toggle_field_patches("cbr_ww_rangedhs_as_20", {
    { buff = "kerillian_waywatcher_attack_speed_on_ranged_headshot_buff", field = "multiplier", value = 0.2 },
    { buff = "kerillian_waywatcher_attack_speed_on_ranged_headshot_buff", field = "duration", value = 10 },
})
BR_TOGGLES.cbr_ww_row2_talent_2_2_poison_on_special = {
    apply = function(saved)
        _safe_modify_talent(saved, "we_waywatcher", 2, 2, {
            buffs = { "gs_poison_explosion_on_special" }
        })
    end,
    restore = function(saved) _restore_modified_talents(saved) end,
}
_toggle_talent_modify("cbr_ww_row2_talent_2_3_desc", {
    { "we_waywatcher", 2, 3, { description_values = { { value = 0.1 } } } },
})
_toggle_talent_modify("cbr_ww_row4_talent_4_1_desc", {
    { "we_waywatcher", 4, 1, { description_values = { { value = 0.2 } } } },
})
_toggle_talent_modify("cbr_ww_row4_talent_4_2_desc", {
    { "we_waywatcher", 4, 2, { description_values = { { value = 0.1 } } } },
})
BR_TOGGLES.cbr_ww_row5_talent_5_1_hs_dmg = {
    apply = function(saved)
        _safe_modify_talent(saved, "we_waywatcher", 5, 1, {
            buffs = { "gs_increased_headshot_damage_waywatcher" }, buffer = "both",
        })
    end,
    restore = function(saved) _restore_modified_talents(saved) end,
}
BR_TOGGLES.cbr_ww_row5_talent_5_2_ricochet_plus_crit = {
    apply = function(saved)
        _safe_modify_talent(saved, "we_waywatcher", 5, 2, {
            buffs = { "kerillian_waywatcher_projectile_ricochet", "gs_extra_crit" }
        })
    end,
    restore = function(saved) _restore_modified_talents(saved) end,
}
BR_TOGGLES.cbr_ww_row5_talent_5_3_ammo_on_melee_kills = {
    apply = function(saved)
        _safe_modify_talent(saved, "we_waywatcher", 5, 3, {
            buffs = { "gs_way_ammo_on_melee_kills", "gs_display_buff_way_ammo" }
        })
    end,
    restore = function(saved) _restore_modified_talents(saved) end,
}
_toggle_talent_modify("cbr_ww_row6_talent_6_3_clear_buffs", {
    { "we_waywatcher", 6, 3, { buffs = {} } },
})
BR_TOGGLES.cbr_ww_extra_shots_loop = { apply = function() end, restore = function() end }
BR_TOGGLES.cbr_ww_cd_on_headshot_proc = { apply = function() end, restore = function() end }
BR_TOGGLES.cbr_ww_throw_speed_action_time_scale = { apply = function() end, restore = function() end }

-- ============================================================
-- 11. Kerillian > Handmaiden (~26)
-- ============================================================
_toggle_table_patches("cbr_hm_ult_cd_40", function(set)
    if ActivatedAbilitySettings and ActivatedAbilitySettings.we_2 and ActivatedAbilitySettings.we_2[1] then
        set(ActivatedAbilitySettings.we_2[1], "cooldown", 40)
    end
end)
_toggle_field_patches("cbr_hm_cdr_on_damage_25", {
    { buff = "kerillian_maidenguard_ability_cooldown_on_damage_taken", field = "bonus", value = 0.25 },
})
BR_TOGGLES.cbr_hm_passive_zoom = {
    apply = function(saved) _safe_append_passive_buff(saved, "we_2", "kerillian_waywatcher_passive_increased_zoom") end,
    restore = function(saved) _restore_passive_appends(saved) end,
}
BR_TOGGLES.cbr_hm_dash_toggle = {
    apply = function(saved) _safe_append_passive_buff(saved, "we_2", "gs_dash_ult_toggle_function") end,
    restore = function(saved) _restore_passive_appends(saved) end,
}
BR_TOGGLES.cbr_hm_banner_as = {
    apply = function(saved) _safe_append_passive_buff(saved, "we_2", "banner_attack_speed") end,
    restore = function(saved) _restore_passive_appends(saved) end,
}
BR_TOGGLES.cbr_hm_banner_as_large = {
    apply = function(saved) _safe_append_passive_buff(saved, "we_2", "banner_attack_speed_large") end,
    restore = function(saved) _restore_passive_appends(saved) end,
}
BR_TOGGLES.cbr_hm_passive_perks_rework = {
    apply = function(saved)
        if PassiveAbilitySettings and PassiveAbilitySettings.we_2 then
            saved.hm_perks_old = PassiveAbilitySettings.we_2.perks
            PassiveAbilitySettings.we_2.perks = {
                { description = "kerillian_maidenguard_perk_1_desc", icon = "kerillian_maidenguard_perk_1" },
                { description = "kerillian_maidenguard_perk_2_desc", icon = "kerillian_maidenguard_perk_2" },
                { description = "kerillian_maidenguard_perk_3_desc", icon = "kerillian_maidenguard_perk_3" },
            }
        end
    end,
    restore = function(saved)
        if saved.hm_perks_old and PassiveAbilitySettings and PassiveAbilitySettings.we_2 then
            PassiveAbilitySettings.we_2.perks = saved.hm_perks_old
            saved.hm_perks_old = nil
        end
    end,
}
_toggle_field_patches("cbr_hm_stam_aura_range_10", {
    { buff = "kerillian_maidenguard_passive_stamina_regen_aura", field = "range", value = 10 },
})
_toggle_field_patches("cbr_hm_stam_aura_50pct", {
    { buff = "kerillian_maidenguard_passive_stamina_regen_aura_buff", field = "multiplier", value = 0.5 },
})
BR_TOGGLES.cbr_hm_banner_ult_rework = { apply = function() end, restore = function() end }
_toggle_field_patches("cbr_hm_power_on_unharmed_20", {
    { buff = "kerillian_maidenguard_power_level_on_unharmed", field = "multiplier", value = 0.2 },
})
_toggle_field_patches("cbr_hm_unharmed_cd_5", {
    { buff = "kerillian_maidenguard_power_level_on_unharmed_cooldown", field = "duration", value = 5 },
})
BR_TOGGLES.cbr_hm_row2_talent_2_2_crit_allies = {
    apply = function(saved)
        _safe_modify_talent(saved, "we_maidenguard", 2, 2, {
            buffs = { "gs_kerillian_maidenguard_crit_chance_allies" }
        })
    end,
    restore = function(saved) _restore_modified_talents(saved) end,
}
_toggle_talent_modify("cbr_hm_row2_talent_2_3_desc", {
    { "we_maidenguard", 2, 3, { description_values = { { value = 0.1 } } } },
})
_toggle_field_patches("cbr_hm_block_speed_stacks_3", {
    { buff = "kerillian_maidenguard_speed_on_block", field = "max_stacks", value = 3 },
})
_toggle_field_patches("cbr_hm_push_speed_stacks_3", {
    { buff = "kerillian_maidenguard_speed_on_push", field = "max_stacks", value = 3 },
})
_toggle_field_patches("cbr_hm_block_speed_20pct", {
    { buff = "kerillian_maidenguard_speed_on_block_buff", field = "multiplier", value = 0.2 },
})
_toggle_field_patches("cbr_hm_block_cleave_75pct", {
    { buff = "kerillian_maidenguard_power_on_block_buff", field = "stat_buff", value = "power_level_cleave" },
    { buff = "kerillian_maidenguard_power_on_block_buff", field = "multiplier", value = 0.75 },
})
_toggle_field_patches("cbr_hm_block_dummy_stacks_3", {
    { buff = "kerillian_maidenguard_speed_on_block_dummy_buff", field = "max_stacks", value = 3 },
})
BR_TOGGLES.cbr_hm_row4_talent_4_3_armoured_on_dodge = {
    apply = function(saved)
        _safe_modify_talent(saved, "we_maidenguard", 4, 3, {
            buffs = { "gs_kerillian_maidenguard_passive_dr_on_dodge" }
        })
    end,
    restore = function(saved) _restore_modified_talents(saved) end,
}
BR_TOGGLES.cbr_hm_row5_talent_5_3_moonbow_speed_plus_ammo = {
    apply = function(saved)
        _safe_modify_talent(saved, "we_maidenguard", 5, 3, {
            buffs = { "kerillian_maidenguard_moonbow_speed", "kerillian_maidenguard_moonbow_damage" }
        })
    end,
    restore = function(saved) _restore_modified_talents(saved) end,
}
_toggle_field_patches("cbr_hm_max_ammo_50pct", {
    { buff = "kerillian_maidenguard_max_ammo", field = "multiplier", value = 0.5 },
})
_toggle_talent_modify("cbr_hm_row6_talent_6_1_aoe_immunity", {
    { "we_maidenguard", 6, 1, { description_values = { { value = 0.5 } } } },
})
_toggle_talent_modify("cbr_hm_row6_talent_6_2_max_hp_50", {
    { "we_maidenguard", 6, 2, { description_values = { { value = 0.5 } } } },
})
_toggle_talent_modify("cbr_hm_row6_talent_6_3_grabber_immunity", {
    { "we_maidenguard", 6, 3, { buffs = {} } },
})

-- ============================================================
-- 12. Kerillian > Shade (~8)
-- ============================================================
_toggle_table_patches("cbr_shade_max_hp_125", function(set)
    if CareerSettings and CareerSettings.we_shade and CareerSettings.we_shade.attributes then
        set(CareerSettings.we_shade.attributes, "max_hp", 125)
    end
end)
BR_TOGGLES.cbr_shade_passive_zoom = {
    apply = function(saved) _safe_append_passive_buff(saved, "wh_1", "kerillian_waywatcher_passive_increased_zoom") end,
    restore = function(saved) _restore_passive_appends(saved) end,
}
BR_TOGGLES.cbr_shade_passive_parry_crit = {
    apply = function(saved)
        _safe_append_passive_buff(saved, "wh_1", "kerillian_shade_passive_stealth_parry_buff_remover")
    end,
    restore = function(saved) _restore_passive_appends(saved) end,
}
_toggle_field_patches("cbr_shade_hs_stack_20_5", {
    { buff = "kerillian_shade_stacking_headshot_damage_on_headshot_buff", field = "max_stacks", value = 5 },
    { buff = "kerillian_shade_stacking_headshot_damage_on_headshot_buff", field = "multiplier", value = 0.2 },
})
_toggle_field_patches("cbr_shade_poison_bleed_dmg_30", {
    { buff = "kerillian_shade_increased_damage_on_poisoned_or_bleeding_enemy", field = "multiplier", value = 0.3 },
})
_toggle_field_patches("cbr_shade_crit_dmg_75", {
    { buff = "kerillian_shade_increased_critical_strike_damage", field = "multiplier", value = 0.75 },
})
_toggle_field_patches("cbr_shade_backstab_ammo_5", {
    { buff = "kerillian_shade_backstabs_replenishes_ammunition", field = "ammo_bonus_fraction", value = 0.05 },
})
_toggle_field_patches("cbr_shade_ult_phasing_restealth", {
    { buff = "kerillian_shade_activated_ability_phasing", field = "perks", value = { "ledge_self_rescue" } },
})

-- ============================================================
-- 13. Kerillian > Thornsister (~17)
-- ============================================================
BR_TOGGLES.cbr_ts_passive_zoom = {
    apply = function(saved) _safe_append_passive_buff(saved, "we_thornsister", "kerillian_waywatcher_passive_increased_zoom") end,
    restore = function(saved) _restore_passive_appends(saved) end,
}
BR_TOGGLES.cbr_ts_vent_nerf = {
    apply = function(saved) _safe_append_passive_buff(saved, "we_thornsister", "thorn_sister_vent_nerf") end,
    restore = function(saved) _restore_passive_appends(saved) end,
}
_toggle_table_patches("cbr_ts_ult_cd_50", function(set)
    if ActivatedAbilitySettings and ActivatedAbilitySettings.we_4 and ActivatedAbilitySettings.we_4[1] then
        set(ActivatedAbilitySettings.we_4[1], "cooldown", 50)
    end
end)
_toggle_field_patches("cbr_ts_poison_debuff_15", {
    { buff = "thorn_sister_passive_poison", field = "multiplier", value = 0.15 },
})
_toggle_field_patches("cbr_ts_poison_debuff_improved_15", {
    { buff = "thorn_sister_passive_poison_improved", field = "multiplier", value = 0.15 },
})
_toggle_field_patches("cbr_ts_cdr_on_hit_35", {
    { buff = "kerillian_thorn_sister_cooldown_on_hit", field = "bonus", value = 0.35 },
})
_toggle_field_patches("cbr_ts_cdr_on_damage_25", {
    { buff = "kerillian_thorn_sister_cooldown_on_damage_taken", field = "bonus", value = 0.25 },
})
_toggle_field_patches("cbr_ts_set_back_3s", {
    { buff = "thorn_sister_set_back", field = "duration", value = 3 },
})
BR_TOGGLES.cbr_ts_temp_health_funnel_40 = {
    apply = function(saved)
        _safe_set_buff_field(saved, "kerillian_thorn_sister_passive_temp_health_funnel_aura_buff", "multiplier", 0.4)
    end,
    restore = function(saved) _restore_buff_fields(saved) end,
}
BR_TOGGLES.cbr_ts_row2_talent_2_1_as_on_health_stack = {
    apply = function(saved)
        _safe_modify_talent(saved, "we_thornsister", 2, 1, {
            buffs = { "gs_activate_buff_stacks_based_on_health_percentage" }
        })
    end,
    restore = function(saved) _restore_modified_talents(saved) end,
}
_toggle_field_patches("cbr_ts_as_on_full_5_per_25", {
    { buff = "kerillian_thorn_sister_attack_speed_on_full_buff", field = "multiplier", value = 0.05 },
    { buff = "kerillian_thorn_sister_attack_speed_on_full_buff", field = "max_stacks", value = 5 },
})
_toggle_field_patches("cbr_ts_crit_on_ability_3", {
    { buff = "kerillian_thorn_sister_crit_on_any_ability", field = "amount_to_add", value = 3 },
})
_toggle_talent_modify("cbr_ts_row2_talent_2_3_desc", {
    { "we_thornsister", 2, 3, { description_values = { { value = 0.05 } } } },
})
BR_TOGGLES.cbr_ts_row6_talent_6_1_drain_bush = {
    apply = function(saved)
        _safe_modify_talent(saved, "we_thornsister", 6, 1, {
            buffs = { "gs_regen_drain_bush" }
        })
    end,
    restore = function(saved) _restore_modified_talents(saved) end,
}
_toggle_table_patches("cbr_ts_wall_radius_5_5", function(set)
    if ExplosionTemplates and ExplosionTemplates.we_thornsister_career_skill_explosive_wall_explosion
       and ExplosionTemplates.we_thornsister_career_skill_explosive_wall_explosion.explosion then
        set(ExplosionTemplates.we_thornsister_career_skill_explosive_wall_explosion.explosion, "radius", 5.5)
    end
end)
_toggle_table_patches("cbr_ts_wall_radius_improved_5_5", function(set)
    if ExplosionTemplates and ExplosionTemplates.we_thornsister_career_skill_explosive_wall_explosion_improved
       and ExplosionTemplates.we_thornsister_career_skill_explosive_wall_explosion_improved.explosion then
        set(ExplosionTemplates.we_thornsister_career_skill_explosive_wall_explosion_improved.explosion, "radius", 5.5)
    end
end)
BR_TOGGLES.cbr_ts_wall_overhaul = { apply = function() end, restore = function() end }

-- ============================================================
-- 14. Victor > Witch Hunter Captain (~10)
-- ============================================================
BR_TOGGLES.cbr_whc_row2_talent_2_1_add_push_power = {
    apply = function(saved)
        _safe_modify_talent(saved, "wh_captain", 2, 1, {
            buffs = { "gs_whc_power" }
        })
    end,
    restore = function(saved) _restore_modified_talents(saved) end,
}
_toggle_field_patches("cbr_whc_parry_trigger_long", {
    { buff = "victor_witchhunter_guaranteed_crit_on_timed_block_add", field = "event", value = "on_timed_block_long" },
})
_toggle_field_patches("cbr_whc_parry_crit_duration_3", {
    { buff = "victor_witchhunter_guaranteed_crit_on_timed_block_buff", field = "duration", value = 3 },
})
BR_TOGGLES.cbr_whc_row5_talent_5_3_ammo_on_melee = {
    apply = function(saved)
        _safe_modify_talent(saved, "wh_captain", 5, 3, {
            buffs = { "gs_whc_ammo_on_melee_kills" }
        })
    end,
    restore = function(saved) _restore_modified_talents(saved) end,
}
BR_TOGGLES.cbr_whc_row6_talent_6_1_tag_on_hit = {
    apply = function(saved)
        _safe_modify_talent(saved, "wh_captain", 6, 1, {
            buffs = { "victor_witchhunter_activated_ability_refund_cooldown_on_enemies_hit_tag" }
        })
    end,
    restore = function(saved) _restore_modified_talents(saved) end,
}
_toggle_field_patches("cbr_whc_ult_party_crit_15", {
    { buff = "victor_witchhunter_activated_ability_crit_buff", field = "bonus", value = 0.15 },
})
-- WHC > Ult: explosion rework (direct wholesale replacement of vanilla
-- ExplosionTemplates.victor_captain_activated_ability_stagger.explosion).
-- Source: victor_changes.lua:137. Pure data (no proc/buff func refs).
BR_TOGGLES.cbr_whc_ult_explosion_rework = {
    apply = function(saved)
        if not ExplosionTemplates or not ExplosionTemplates.victor_captain_activated_ability_stagger then return end
        saved.whc_expl_old = ExplosionTemplates.victor_captain_activated_ability_stagger.explosion
        ExplosionTemplates.victor_captain_activated_ability_stagger.explosion = {
            always_hurt_players = false,
            radius = 10,
            no_prop_damage = true,
            max_damage_radius = 3,
            attack_template = "drakegun",
            attacker_power_level_offset = 0.01,
            damage_type = "grenade",
            alert_enemies_radius = 15,
            use_attacker_power_level = true,
            alert_enemies = true,
            damage_profile = "ability_push",
            ignore_attacker_unit = true,
            no_friendly_fire = true,
        }
    end,
    restore = function(saved)
        if saved.whc_expl_old and ExplosionTemplates and ExplosionTemplates.victor_captain_activated_ability_stagger then
            ExplosionTemplates.victor_captain_activated_ability_stagger.explosion = saved.whc_expl_old
            saved.whc_expl_old = nil
        end
    end,
}
-- WHC > Ult: 2 new buffs (data overlay only).
-- Source: victor_changes.lua:2035 + 2189. The wholesale
-- CareerAbilityWHCaptain._run_ability hook that adds these buffs is
-- deferred (see Deferred list). Pure stat-buff bodies.
BR_TOGGLES.cbr_whc_ult_rework = {
    apply = function(saved)
        saved.whc_ult_old = {}
        if BuffTemplates and BuffTemplates.victor_witchhunter_activated_ability_crit_self_buff then
            saved.whc_ult_old.crit_self = BuffTemplates.victor_witchhunter_activated_ability_crit_self_buff.buffs[1]
            BuffTemplates.victor_witchhunter_activated_ability_crit_self_buff.buffs[1] = {
                name = "victor_witchhunter_activated_ability_crit_self_buff",
                refresh_durations = true,
                duration = 6,
                stat_buff = "critical_strike_chance",
                bonus = 0.1,
            }
        end
        if BuffTemplates and BuffTemplates.victor_witchhunter_activated_ability_mute_ping then
            saved.whc_ult_old.mute = BuffTemplates.victor_witchhunter_activated_ability_mute_ping.buffs[1]
            BuffTemplates.victor_witchhunter_activated_ability_mute_ping.buffs[1] = {
                name = "victor_witchhunter_activated_ability_mute_ping",
                duration = 5,
                icon = "victor_priest_4_1",
                max_stacks = 1,
            }
        end
    end,
    restore = function(saved)
        if not saved.whc_ult_old then return end
        if saved.whc_ult_old.crit_self and BuffTemplates and BuffTemplates.victor_witchhunter_activated_ability_crit_self_buff then
            BuffTemplates.victor_witchhunter_activated_ability_crit_self_buff.buffs[1] = saved.whc_ult_old.crit_self
        end
        if saved.whc_ult_old.mute and BuffTemplates and BuffTemplates.victor_witchhunter_activated_ability_mute_ping then
            BuffTemplates.victor_witchhunter_activated_ability_mute_ping.buffs[1] = saved.whc_ult_old.mute
        end
        saved.whc_ult_old = nil
    end,
}
BR_TOGGLES.cbr_whc_ping_persist = { apply = function() end, restore = function() end }
BR_TOGGLES.cbr_whc_ping_handle_rework = { apply = function() end, restore = function() end }

-- ============================================================
-- 15. Victor > Zealot (~14)
-- ============================================================
BR_TOGGLES.cbr_zealot_passive_rework = {
    apply = function(saved)
        _safe_replace_passive_buffs(saved, "wh_1", {
            "victor_zealot_passive",
            "victor_zealot_passive_damage",
            "victor_zealot_passive_increased_damage",
            "victor_zealot_passive_movement_speed",
            "gs_infinite_wounds",
            "gs_deus_reckless_swings",
            "victor_zealot_invulnerability_cooldown_short",
            "gs_victor_zealot_health_increase",
            "gs_victor_zealot_damage_on_hit",
        })
    end,
    restore = function(saved) _restore_passive_replacements(saved) end,
}
BR_TOGGLES.cbr_zealot_passive_perks_rework = {
    apply = function(saved)
        if PassiveAbilitySettings and PassiveAbilitySettings.wh_1 then
            saved.zealot_perks_old = PassiveAbilitySettings.wh_1.perks
            PassiveAbilitySettings.wh_1.perks = {
                { description = "victor_zealot_perk_1_desc", icon = "victor_zealot_perk_1" },
                { description = "victor_zealot_perk_2_desc", icon = "victor_zealot_perk_2" },
                { description = "victor_zealot_perk_3_desc", icon = "victor_zealot_perk_3" },
            }
        end
    end,
    restore = function(saved)
        if saved.zealot_perks_old and PassiveAbilitySettings and PassiveAbilitySettings.wh_1 then
            PassiveAbilitySettings.wh_1.perks = saved.zealot_perks_old
            saved.zealot_perks_old = nil
        end
    end,
}
BR_TOGGLES.cbr_zealot_row2_talent_2_1_as_scaling = {
    apply = function(saved)
        _safe_modify_talent(saved, "wh_zealot", 2, 1, {
            buffs = { "gs_victor_zealot_attack_speed_scaling" }
        })
    end,
    restore = function(saved) _restore_modified_talents(saved) end,
}
_toggle_talent_modify("cbr_zealot_row2_talent_2_2_perks_clear", {
    { "wh_zealot", 2, 2, { perks = {} } },
})
BR_TOGGLES.cbr_zealot_row2_talent_2_3_first_target = {
    apply = function(saved)
        _safe_modify_talent(saved, "wh_zealot", 2, 3, {
            buffs = { "gs_victor_zealot_increased_damage_to_first_target" }
        })
    end,
    restore = function(saved) _restore_modified_talents(saved) end,
}
_toggle_talent_modify("cbr_zealot_row4_talent_4_1_heart_iron_rework", {
    { "wh_zealot", 4, 1, { buffer = "both", buffs = {} } },
})
BR_TOGGLES.cbr_zealot_row4_talent_4_2_high_health_as = {
    apply = function(saved)
        _safe_modify_talent(saved, "wh_zealot", 4, 2, {
            buffs = { "gs_victor_zealot_attack_speed_high_health" }
        })
    end,
    restore = function(saved) _restore_modified_talents(saved) end,
}
BR_TOGGLES.cbr_zealot_row4_talent_4_3_dr_low_hp = {
    apply = function(saved)
        _safe_modify_talent(saved, "wh_zealot", 4, 3, {
            buffs = { "gs_victor_zealot_dr", "gs_deus_reckless_swings_extra" }
        })
    end,
    restore = function(saved) _restore_modified_talents(saved) end,
}
BR_TOGGLES.cbr_zealot_row5_talent_5_1_as_on_hit = {
    apply = function(saved)
        _safe_modify_talent(saved, "wh_zealot", 5, 1, {
            buffs = { "gs_victor_attack_speed_on_hit" }
        })
    end,
    restore = function(saved) _restore_modified_talents(saved) end,
}
BR_TOGGLES.cbr_zealot_row5_talent_5_2_power_on_hit = {
    apply = function(saved)
        _safe_modify_talent(saved, "wh_zealot", 5, 2, {
            buffs = { "gs_victor_power_on_hit" }
        })
    end,
    restore = function(saved) _restore_modified_talents(saved) end,
}
BR_TOGGLES.cbr_zealot_row5_talent_5_3_cleave_on_hit = {
    apply = function(saved)
        _safe_modify_talent(saved, "wh_zealot", 5, 3, {
            buffs = { "gs_victor_cleave_power_on_hit" }
        })
    end,
    restore = function(saved) _restore_modified_talents(saved) end,
}
_toggle_field_patches("cbr_zealot_ult_power_2_5", {
    { buff = "victor_zealot_activated_ability_power_on_hit_buff", field = "multiplier", value = 0.025 },
})
-- Zealot > Misc: big-hit buff set (3 talent buff template overlays).
-- Source: victor_changes.lua:719/728/734. The trigger references
-- `dummy_function` (vanilla buff_func) and the _removal references
-- `delayed_buff_removal_gs` + `mark_for_delayed_deletion` (BR-installed via
-- mod.add_buff_function). If bt doesn't install those funcs, the
-- field-overlay is harmless (dispatcher no-ops on unknown fn names) but the
-- removal-on-melee-hit won't fire. Bodies are pure data.
BR_TOGGLES.cbr_zealot_big_hit_buffs = {
    apply = function(saved)
        saved.zealot_big_hit_old = {}
        if BuffTemplates and BuffTemplates.zealot_big_hit then
            saved.zealot_big_hit_old.trigger = BuffTemplates.zealot_big_hit.buffs[1]
            BuffTemplates.zealot_big_hit.buffs[1] = {
                name = "zealot_big_hit",
                event = "on_melee_hit",
                max_stacks = 1,
                stat_buff = "critical_strike_chance_melee",
                buff_func = "dummy_function",
                remove_on_proc = true,
                priority_buff = true,
                bonus = 1,
            }
        end
        if BuffTemplates and BuffTemplates.zealot_big_hit_buff then
            saved.zealot_big_hit_old.buff = BuffTemplates.zealot_big_hit_buff.buffs[1]
            BuffTemplates.zealot_big_hit_buff.buffs[1] = {
                name = "zealot_big_hit_buff",
                max_stacks = 1,
                multiplier = 2,
                stat_buff = "power_level_melee",
                icon = "victor_zealot_activated_ability_ignore_death",
            }
        end
        if BuffTemplates and BuffTemplates.zealot_big_hit_buff_removal then
            saved.zealot_big_hit_old.removal = BuffTemplates.zealot_big_hit_buff_removal.buffs[1]
            BuffTemplates.zealot_big_hit_buff_removal.buffs[1] = {
                name = "zealot_big_hit_buff_removal",
                update_func = "delayed_buff_removal_gs",
                max_stacks = 1,
                buff_func = "mark_for_delayed_deletion",
                event = "on_melee_hit",
                deletion_delay = 0.05,
                reference_buff = "zealot_big_hit_buff",
            }
        end
    end,
    restore = function(saved)
        if not saved.zealot_big_hit_old then return end
        if saved.zealot_big_hit_old.trigger and BuffTemplates and BuffTemplates.zealot_big_hit then
            BuffTemplates.zealot_big_hit.buffs[1] = saved.zealot_big_hit_old.trigger
        end
        if saved.zealot_big_hit_old.buff and BuffTemplates and BuffTemplates.zealot_big_hit_buff then
            BuffTemplates.zealot_big_hit_buff.buffs[1] = saved.zealot_big_hit_old.buff
        end
        if saved.zealot_big_hit_old.removal and BuffTemplates and BuffTemplates.zealot_big_hit_buff_removal then
            BuffTemplates.zealot_big_hit_buff_removal.buffs[1] = saved.zealot_big_hit_old.removal
        end
        saved.zealot_big_hit_old = nil
    end,
}
BR_TOGGLES.cbr_zealot_ult_rework = { apply = function() end, restore = function() end }

-- ============================================================
-- 16. Victor > Bounty Hunter (~15)
-- ============================================================
BR_TOGGLES.cbr_bh_passive_melee_kill = {
    apply = function(saved) _safe_append_passive_buff(saved, "wh_2", "victor_bountyhunter_activate_passive_on_melee_kill") end,
    restore = function(saved) _restore_passive_appends(saved) end,
}
BR_TOGGLES.cbr_bh_passive_perks_rework = {
    apply = function(saved)
        if PassiveAbilitySettings and PassiveAbilitySettings.wh_2 then
            saved.bh_perks_old = PassiveAbilitySettings.wh_2.perks
            PassiveAbilitySettings.wh_2.perks = {
                { description = "victor_bountyhunter_perk_1_desc", icon = "victor_bountyhunter_perk_1" },
                { description = "victor_bountyhunter_perk_2_desc", icon = "victor_bountyhunter_perk_2" },
                { description = "victor_bountyhunter_perk_3_desc", icon = "victor_bountyhunter_perk_3" },
            }
        end
    end,
    restore = function(saved)
        if saved.bh_perks_old and PassiveAbilitySettings and PassiveAbilitySettings.wh_2 then
            PassiveAbilitySettings.wh_2.perks = saved.bh_perks_old
            saved.bh_perks_old = nil
        end
    end,
}
_toggle_field_patches("cbr_bh_railgun_delayed_80", {
    { buff = "victor_bountyhunter_activated_ability_railgun_delayed_add", field = "multiplier", value = 0.8 },
})
BR_TOGGLES.cbr_bh_row6_talent_6_3_shotgun_cdr = {
    apply = function(saved)
        _safe_modify_talent(saved, "wh_bountyhunter", 6, 3, {
            buffs = { "victor_bountyhunter_activated_ability_blast_shotgun_cdr" }
        })
    end,
    restore = function(saved) _restore_modified_talents(saved) end,
}
BR_TOGGLES.cbr_bh_row2_talent_2_2_as_every_3_shots = {
    apply = function(saved)
        _safe_modify_talent(saved, "wh_bountyhunter", 2, 2, {
            buffs = { "gs_victor_bounty_melee_on_ranged" }
        })
    end,
    restore = function(saved) _restore_modified_talents(saved) end,
}
BR_TOGGLES.cbr_bh_row5_talent_5_1_party_heal_on_crit = {
    apply = function(saved)
        _safe_modify_talent(saved, "wh_bountyhunter", 5, 1, {
            buffs = { "gs_victor_bounty_heal_on_crit_hs_delay" }
        })
    end,
    restore = function(saved) _restore_modified_talents(saved) end,
}
_toggle_field_patches("cbr_bh_clip_power_rework", {
    { buff = "victor_bountyhunter_power_level_on_clip_size", field = "update_func", value = "update_buff_clip_power" },
})
_toggle_talent_modify("cbr_bh_row4_talent_4_1_blessed_combat_desc", {
    { "wh_bountyhunter", 4, 1, { description_values = { { value = 0.25 } } } },
})
_toggle_field_patches("cbr_bh_reload_on_melee_kill", {
    { buff = "victor_bountyhunter_reload_on_kill", field = "ammo_bonus_fraction", value = 0.1 },
})
_toggle_field_patches("cbr_bh_ammo_on_elite_when_empty", {
    { buff = "victor_bountyhunter_restore_ammo_on_elite_kill", field = "ammo_bonus_fraction", value = 0.05 },
})
_toggle_field_patches("cbr_bh_stacking_dr_20", {
    { buff = "victor_bountyhunter_stacking_damage_reduction_on_elite_or_special_kill_buff", field = "max_stacks", value = 20 },
})
_toggle_talent_modify("cbr_bh_row5_talent_5_3_desc", {
    { "wh_bountyhunter", 5, 3, { description_values = { { value = 0.05 } } } },
})
BR_TOGGLES.cbr_bh_row6_talent_6_1_locked_loaded_buffs = {
    apply = function(saved)
        _safe_modify_talent(saved, "wh_bountyhunter", 6, 1, {
            buffs = { "gs_bounty_hunter_clip_size_buff", "gs_bounty_hunter_ranged_crit_buff",
                      "gs_victor_bounty_hunter_buff_on_locked_and_loaded" }
        })
    end,
    restore = function(saved) _restore_modified_talents(saved) end,
}
BR_TOGGLES.cbr_bh_clip_full_fix = { apply = function() end, restore = function() end }
BR_TOGGLES.cbr_bh_railgun_cd_proc = { apply = function() end, restore = function() end }

-- ============================================================
-- 17. Victor > Warrior Priest (~21)
-- ============================================================
_toggle_field_patches("cbr_wp_super_armour_50", {
    { buff = "victor_priest_super_armour_damage", field = "multiplier", value = 0.5 },
})
-- WP > Misc: monster damage buff (talent buff template overlay)
-- Source: victor_changes.lua:1435 — power_level_large +25% buff. Used by the
-- WP "Smite the wicked" passive — buff is added by an existing WP buff_func
-- chain in vanilla, so no proc/buff_func registration needed here.
BR_TOGGLES.cbr_wp_monster_damage_buff = {
    apply = function(saved)
        if BuffTemplates and BuffTemplates.victor_priest_monster_damage then
            saved.wp_monster_old = BuffTemplates.victor_priest_monster_damage.buffs[1]
            BuffTemplates.victor_priest_monster_damage.buffs[1] = {
                name = "victor_priest_monster_damage",
                stat_buff = "power_level_large",
                multiplier = 0.25,
                max_stacks = 1,
            }
        end
    end,
    restore = function(saved)
        if saved.wp_monster_old and BuffTemplates and BuffTemplates.victor_priest_monster_damage then
            BuffTemplates.victor_priest_monster_damage.buffs[1] = saved.wp_monster_old
            saved.wp_monster_old = nil
        end
    end,
}
BR_TOGGLES.cbr_wp_row2_talent_2_2_charge_power_rework = {
    apply = function(saved)
        _safe_set_buff_field(saved, "victor_priest_2_2_buff", "multiplier", 0.4)
        _safe_modify_talent(saved, "wh_priest", 2, 2, {
            buffs = { "victor_priest_2_2_buff", "victor_priest_2_2_delay" }
        })
    end,
    restore = function(saved) _restore_buff_fields(saved); _restore_modified_talents(saved) end,
}
_toggle_field_patches("cbr_wp_row2_talent_2_3_buff_tune", {
    { buff = "victor_priest_2_3_buff", field = "multiplier", value = 0.25 },
})
_toggle_talent_modify("cbr_wp_row2_talent_2_3_desc", {
    { "wh_priest", 2, 3, { description_values = { { value = 0.25 } } } },
})
_toggle_field_patches("cbr_wp_row5_talent_5_1_cleave_power_20", {
    { buff = "victor_priest_5_1_buff", field = "stat_buff", value = "power_level_cleave" },
    { buff = "victor_priest_5_1_buff", field = "multiplier", value = 0.2 },
})
_toggle_field_patches("cbr_wp_row5_talent_5_2_as_5", {
    { buff = "victor_priest_5_2_buff", field = "stat_buff", value = "attack_speed" },
    { buff = "victor_priest_5_2_buff", field = "multiplier", value = 0.05 },
})
_toggle_field_patches("cbr_wp_aftershock_hit_force", {
    { buff = "victor_priest_passive_aftershock", field = "stat_buff", value = "hit_force" },
})
_toggle_field_patches("cbr_wp_aftershock_mult_10", {
    { buff = "victor_priest_passive_aftershock", field = "multiplier", value = 10 },
})
-- WP > Misc: activated noclip pulse buff (data overlay only).
-- Source: victor_changes.lua:1497. The buff references BR-installed funcs
-- (victor_priest_activated_noclip_apply/remove/update); without bt providing
-- them the buff is inert. The engine reads stagger_impact / no_clip_filter
-- as plain data (no dispatch crash). stagger_types.medium = 2, .none = 0
-- (inlined from scripts/utils/stagger_types.lua).
BR_TOGGLES.cbr_wp_activated_noclip = {
    apply = function(saved)
        if BuffTemplates and BuffTemplates.victor_priest_activated_noclip then
            saved.wp_noclip_old = BuffTemplates.victor_priest_activated_noclip.buffs[1]
            BuffTemplates.victor_priest_activated_noclip.buffs[1] = {
                stagger_distance = 1,
                push_radius = 1.5,
                name = "victor_priest_activated_noclip_improved",
                push_cooldown = 1,
                remove_buff_func = "victor_priest_activated_noclip_remove",
                apply_buff_func = "victor_priest_activated_noclip_apply",
                icon = "victor_priest_6_1",
                update_func = "victor_priest_activated_noclip_update",
                refresh_durations = true,
                max_stacks = 1,
                duration = 5,
                update_frequency = 0.1,
                perks = { "no_ranged_knockback" },
                stagger_impact = { 2, 0, 0, 0, 0 },
                no_clip_filter = { true, false, false, false, false, false },
            }
        end
    end,
    restore = function(saved)
        if saved.wp_noclip_old and BuffTemplates and BuffTemplates.victor_priest_activated_noclip then
            BuffTemplates.victor_priest_activated_noclip.buffs[1] = saved.wp_noclip_old
            saved.wp_noclip_old = nil
        end
    end,
}
_toggle_talent_modify("cbr_wp_row6_talent_6_1_desc", {
    { "wh_priest", 6, 1, { description_values = { { value = 10 } } } },
})
_toggle_field_patches("cbr_wp_row6_talent_6_3_heal_window_4", {
    { buff = "victor_priest_6_3_buff", field = "heal_window", value = 4 },
})
BR_TOGGLES.cbr_wp_prayer_toggle = {
    apply = function(saved) _safe_append_passive_buff(saved, "wh_priest", "gs_priest_prayer_toggle_function") end,
    restore = function(saved) _restore_passive_appends(saved) end,
}
-- WP > Misc: attack speed on fury (talent buff template overlay)
-- Source: victor_changes.lua:1931. Power-level-melee stacking buff; the
-- proc that adds it is part of the fury rework hook (deferred separately).
-- Pre-registered name; only the template body is overlaid here.
BR_TOGGLES.cbr_wp_attack_speed_on_fury = {
    apply = function(saved)
        if BuffTemplates and BuffTemplates.wh_priest_attack_speed_on_fury_buff then
            saved.wp_as_fury_old = BuffTemplates.wh_priest_attack_speed_on_fury_buff.buffs[1]
            BuffTemplates.wh_priest_attack_speed_on_fury_buff.buffs[1] = {
                name = "wh_priest_attack_speed_on_fury_buff",
                max_stacks = 10,
                icon = "victor_priest_passive",
                stat_buff = "power_level_melee",
                multiplier = 0.02,
            }
        end
    end,
    restore = function(saved)
        if saved.wp_as_fury_old and BuffTemplates and BuffTemplates.wh_priest_attack_speed_on_fury_buff then
            BuffTemplates.wh_priest_attack_speed_on_fury_buff.buffs[1] = saved.wp_as_fury_old
            saved.wp_as_fury_old = nil
        end
    end,
}
-- WP > Ult: fury on ult (talent buff template overlay)
-- Source: victor_changes.lua:2008 — simple 4s timed buff applied by the
-- 6_1-talent target buff list (which itself is part of the fury rework hook,
-- deferred). Template body only.
BR_TOGGLES.cbr_wp_fury_on_ult = {
    apply = function(saved)
        if BuffTemplates and BuffTemplates.victor_priest_fury_on_ult then
            saved.wp_fury_ult_old = BuffTemplates.victor_priest_fury_on_ult.buffs[1]
            BuffTemplates.victor_priest_fury_on_ult.buffs[1] = {
                name = "victor_priest_fury_on_ult",
                duration = 4,
                max_stacks = 1,
            }
        end
    end,
    restore = function(saved)
        if saved.wp_fury_ult_old and BuffTemplates and BuffTemplates.victor_priest_fury_on_ult then
            BuffTemplates.victor_priest_fury_on_ult.buffs[1] = saved.wp_fury_ult_old
            saved.wp_fury_ult_old = nil
        end
    end,
}
BR_TOGGLES.cbr_wp_fury_rework = { apply = function() end, restore = function() end }
BR_TOGGLES.cbr_wp_target_action_init = { apply = function() end, restore = function() end }
BR_TOGGLES.cbr_wp_target_buff_list = { apply = function() end, restore = function() end }
_toggle_table_patches("cbr_wp_nuke_enemy_debuff", function(set)
    if ExplosionTemplates and ExplosionTemplates.victor_priest_activated_ability_nuke
       and ExplosionTemplates.victor_priest_activated_ability_nuke.explosion then
        set(ExplosionTemplates.victor_priest_activated_ability_nuke.explosion, "enemy_debuff",
            "defence_debuff_enemies_warrior_priest_bubble")
    end
end)
-- WP > Misc: lightning explosion templates (overlay into pre-registered stubs).
-- Source: experimental_talent_changes.lua:284 / 310. Two NewExplosionTemplates
-- entries. The _strong variant references `defence_debuff_enemies_warrior_priest_lightning`
-- which is a separate buff toggle (cbr_buff_wp_lightning_debuff) — its name is
-- pre-registered regardless.
BR_TOGGLES.cbr_wp_lightning_explosion_templates = {
    apply = function(saved)
        if not ExplosionTemplates then return end
        saved.wp_lit_old = {}
        if ExplosionTemplates.warrior_priest_lightning_explosion then
            saved.wp_lit_old.basic = ExplosionTemplates.warrior_priest_lightning_explosion.explosion
            ExplosionTemplates.warrior_priest_lightning_explosion.explosion = {
                always_hurt_players = false,
                radius = 10,
                attack_template = "drakegun",
                max_damage_radius = 3,
                use_attacker_power_level = true,
                attacker_power_level_offset = 1,
                sound_event_name = "Play_mutator_enemy_split_large",
                alert_enemies_radius = 30,
                buildup_effect_name = "fx/magic_wind_heavens_lightning_strike_02",
                damage_profile_glance = "overcharge_explosion_glance_ability",
                effect_name = "fx/magic_wind_heavens_lightning_strike_01",
                alert_enemies = true,
                damage_profile = "warrior_priest_explosion_damage",
                ignore_attacker_unit = true,
                no_friendly_fire = true,
                camera_effect = {
                    near_distance = 5,
                    far_scale = 0.15,
                    shake_name = "lightning_strike",
                    near_scale = 1,
                    far_distance = 20,
                },
            }
        end
        if ExplosionTemplates.warrior_priest_lightning_explosion_strong then
            saved.wp_lit_old.strong = ExplosionTemplates.warrior_priest_lightning_explosion_strong.explosion
            ExplosionTemplates.warrior_priest_lightning_explosion_strong.explosion = {
                use_attacker_power_level = true,
                radius = 10,
                effect_name = "fx/magic_wind_heavens_lightning_strike_01",
                attack_template = "drakegun",
                sound_event_name = "Play_mutator_enemy_split_large",
                alert_enemies_radius = 30,
                alert_enemies = true,
                ignore_attacker_unit = true,
                no_friendly_fire = true,
                always_hurt_players = false,
                max_damage_radius = 3,
                attacker_power_level_offset = 1,
                damage_profile_glance = "overcharge_explosion_glance_ability",
                damage_profile = "warrior_priest_explosion_damage_strong",
                buildup_effect_name = "fx/magic_wind_heavens_lightning_strike_02",
                camera_effect = {
                    near_distance = 5,
                    far_scale = 0.15,
                    shake_name = "lightning_strike",
                    near_scale = 1,
                    far_distance = 20,
                },
                enemy_debuff = {
                    "defence_debuff_enemies_warrior_priest_lightning",
                },
            }
        end
    end,
    restore = function(saved)
        if not saved.wp_lit_old then return end
        if saved.wp_lit_old.basic and ExplosionTemplates and ExplosionTemplates.warrior_priest_lightning_explosion then
            ExplosionTemplates.warrior_priest_lightning_explosion.explosion = saved.wp_lit_old.basic
        end
        if saved.wp_lit_old.strong and ExplosionTemplates and ExplosionTemplates.warrior_priest_lightning_explosion_strong then
            ExplosionTemplates.warrior_priest_lightning_explosion_strong.explosion = saved.wp_lit_old.strong
        end
        saved.wp_lit_old = nil
    end,
}

-- ============================================================
-- 18. Sienna > Adept (Battle Wizard) (~10)
-- ============================================================
_toggle_table_patches("cbr_adept_ult_cooldown_60", function(set)
    if ActivatedAbilitySettings and ActivatedAbilitySettings.bw_2 and ActivatedAbilitySettings.bw_2[1] then
        set(ActivatedAbilitySettings.bw_2[1], "cooldown", 60)
    end
end)
BR_TOGGLES.cbr_adept_passive_zoom = {
    apply = function(saved) _safe_append_passive_buff(saved, "bw_2", "kerillian_waywatcher_passive_increased_zoom") end,
    restore = function(saved) _restore_passive_appends(saved) end,
}
BR_TOGGLES.cbr_adept_row5_talent_5_2_dr_from_overcharge = {
    apply = function(saved)
        _safe_modify_talent(saved, "bw_adept", 5, 2, {
            buffs = { "increased_dr_from_overcharge" }
        })
    end,
    restore = function(saved) _restore_modified_talents(saved) end,
}
-- Adept > Ult: ability trail buff (data overlay only).
-- Source: sienna_changes.lua:998. The wholesale
-- CareerAbilityBWAdept._run_ability hook and the damage-profile portion
-- (kaboom_push) are deferred (see Deferred list). The buff body uses vanilla
-- buff funcs (start_dot_damage / apply_dot_damage / reapply_buff). Safe.
BR_TOGGLES.cbr_adept_ult_rework = {
    apply = function(saved)
        if BuffTemplates and BuffTemplates.sienna_adept_ability_trail then
            saved.adept_trail_old = BuffTemplates.sienna_adept_ability_trail.buffs[1]
            BuffTemplates.sienna_adept_ability_trail.buffs[1] = {
                apply_buff_func = "start_dot_damage",
                name = "sienna_adept_ability_trail",
                end_flow_event = "smoke",
                time_between_dot_damages = 0.75,
                on_max_stacks_overflow_func = "reapply_buff",
                death_flow_event = "burn_death",
                start_flow_event = "burn",
                update_start_delay = 0.25,
                max_stacks = 1,
                leave_linger_time = 1.5,
                damage_type = "burninating",
                damage_profile = "burning_dot",
                update_func = "apply_dot_damage",
                perks = { "burning" },
            }
        end
    end,
    restore = function(saved)
        if saved.adept_trail_old and BuffTemplates and BuffTemplates.sienna_adept_ability_trail then
            BuffTemplates.sienna_adept_ability_trail.buffs[1] = saved.adept_trail_old
            saved.adept_trail_old = nil
        end
    end,
}
_toggle_field_patches("cbr_adept_burn_damage_100", {
    { buff = "sienna_adept_increased_burn_damage", field = "multiplier", value = 1 },
})
_toggle_talent_modify("cbr_adept_row2_talent_2_2_burn_damage", {
    { "bw_adept", 2, 2, { description_values = { { value = 1 } } } },
})
_toggle_field_patches("cbr_adept_tranquility_attack_speed", {
    { buff = "sienna_adept_improved_tranquility", field = "stat_buff", value = "attack_speed" },
})
_toggle_field_patches("cbr_adept_dr_on_ignite_rework", {
    { buff = "sienna_adept_damage_reduction_on_ignited_enemy_buff", field = "multiplier", value = -0.1 },
})
_toggle_talent_modify("cbr_adept_row5_talent_5_1_dr_on_ignite_desc", {
    { "bw_adept", 5, 1, { description_values = { { value = 0.1 } } } },
})
BR_TOGGLES.cbr_adept_row6_talent_6_3_double_firewalk = {
    apply = function(saved)
        _safe_modify_talent(saved, "bw_adept", 6, 3, {
            buffs = { "sienna_adept_increased_ult_cooldown" }
        })
        _safe_set_buff_field(saved, "sienna_adept_increased_ult_cooldown", "multiplier", 0.5)
    end,
    restore = function(saved) _restore_modified_talents(saved); _restore_buff_fields(saved) end,
}

-- ============================================================
-- 19. Sienna > Scholar (Pyromancer) (~5)
-- ============================================================
_toggle_table_patches("cbr_scholar_ult_cooldown_40", function(set)
    if ActivatedAbilitySettings and ActivatedAbilitySettings.bw_1 and ActivatedAbilitySettings.bw_1[1] then
        set(ActivatedAbilitySettings.bw_1[1], "cooldown", 40)
    end
end)
BR_TOGGLES.cbr_scholar_passive_zoom = {
    apply = function(saved) _safe_append_passive_buff(saved, "bw_1", "kerillian_waywatcher_passive_increased_zoom") end,
    restore = function(saved) _restore_passive_appends(saved) end,
}
BR_TOGGLES.cbr_scholar_row4_talent_4_3_spawn_heads = {
    apply = function(saved)
        _safe_modify_talent(saved, "bw_scholar", 4, 3, {
            buffs = { "sienna_scholar_spawn_heads" }
        })
    end,
    restore = function(saved) _restore_modified_talents(saved) end,
}
_toggle_field_patches("cbr_scholar_attack_speed_10", {
    { buff = "sienna_scholar_increased_attack_speed", field = "multiplier", value = 0.1 },
})
BR_TOGGLES.cbr_scholar_row5_talent_5_3_first_hit_and_proj_speed = {
    apply = function(saved)
        _safe_modify_talent(saved, "bw_scholar", 5, 3, {
            buffs = { "sienna_scholar_first_hit_damage", "sienna_scholar_increased_projectile_speed" }
        })
    end,
    restore = function(saved) _restore_modified_talents(saved) end,
}

-- ============================================================
-- 20. Sienna > Unchained (~18)
-- ============================================================
-- Unchained > Passive: overcharge_exploding on_exit rewrite (direct method
-- replacement on PlayerCharacterStateOverchargeExploding). No buff/proc
-- dependencies — self-contained.
-- Source: sienna_changes.lua:780.
BR_TOGGLES.cbr_unchained_overcharge_explode_onexit_rewrite = {
    apply = function(saved)
        if not _G.PlayerCharacterStateOverchargeExploding then return end
        saved.oc_onexit_old = _G.PlayerCharacterStateOverchargeExploding.on_exit
        _G.PlayerCharacterStateOverchargeExploding.on_exit = function(self, unit, input, dt, context, t, next_state)
            if not Managers.state.network:game() or not next_state then
                return
            end
            CharacterStateHelper.play_animation_event(unit, "cooldown_end")
            CharacterStateHelper.play_animation_event_first_person(self.first_person_extension, "cooldown_end")
            local career_extension = ScriptUnit.extension(unit, "career_system")
            local _ = career_extension and career_extension:career_name()
            if self.falling and next_state ~= "falling" then
                ScriptUnit.extension(unit, "whereabouts_system"):set_no_landing()
            end
            return
        end
    end,
    restore = function(saved)
        if saved.oc_onexit_old and _G.PlayerCharacterStateOverchargeExploding then
            _G.PlayerCharacterStateOverchargeExploding.on_exit = saved.oc_onexit_old
            saved.oc_onexit_old = nil
        end
    end,
}
BR_TOGGLES.cbr_unchained_passive_zoom = {
    apply = function(saved) _safe_append_passive_buff(saved, "bw_3", "kerillian_waywatcher_passive_increased_zoom") end,
    restore = function(saved) _restore_passive_appends(saved) end,
}
BR_TOGGLES.cbr_unchained_passive_health_to_ult = {
    apply = function(saved) _safe_append_passive_buff(saved, "bw_3", "sienna_unchained_health_to_ult") end,
    restore = function(saved) _restore_passive_appends(saved) end,
}
BR_TOGGLES.cbr_unchained_passive_overcharge_on_melee_kills = {
    apply = function(saved) _safe_append_passive_buff(saved, "bw_3", "gs_add_overcharge_on_melee_kills") end,
    restore = function(saved) _restore_passive_appends(saved) end,
}
_toggle_field_patches("cbr_unchained_passive_melee_power_rework", {
    { buff = "sienna_unchained_passive_melee_power_on_overcharge", field = "max_stacks", value = 3 },
    { buff = "sienna_unchained_passive_melee_power_on_overcharge", field = "multiplier", value = 0.1 },
})
_toggle_field_patches("cbr_unchained_health_to_cooldown_rewrite", {
    { buff = "sienna_unchained_health_to_cooldown_buff", field = "update_func", value = "update_unchained_health_to_cooldown" },
})
BR_TOGGLES.cbr_unchained_talent_2_1_flaming_weapons_headshot = {
    apply = function(saved)
        _safe_modify_talent(saved, "bw_unchained", 2, 1, {
            buffs = { "gs_burning_enemies_on_headshot" }
        })
    end,
    restore = function(saved) _restore_modified_talents(saved) end,
}
BR_TOGGLES.cbr_unchained_talent_2_2_explode_on_elite_kill = {
    apply = function(saved)
        _safe_modify_talent(saved, "bw_unchained", 2, 2, {
            buffs = { "gs_exploding_enemies_on_kill" }
        })
    end,
    restore = function(saved) _restore_modified_talents(saved) end,
}
-- Unchained > Misc: exploding burning enemies rework (buff field-patch +
-- explosion overwrite on vanilla `sienna_unchained_burning_enemies_explosion`).
-- Source: sienna_changes.lua:1183 / 1189. The buff_func string
-- `gs_sienna_on_melee_kill_explosion` is a BR-installed proc function (added
-- via `mod.add_proc_function`); if bt doesn't install proc functions the
-- field-patch is harmless (dispatcher silently no-ops) but the rework won't
-- fire. Explosion overlay references damage_profile `long_burn_explosion`
-- (pre-registered in canonical_BR_REGISTRATIONS).
BR_TOGGLES.cbr_unchained_exploding_burning_enemies_rework = {
    apply = function(saved)
        _safe_set_buff_field(saved, "sienna_unchained_exploding_burning_enemies", "buff_func", "gs_sienna_on_melee_kill_explosion")
        _safe_set_buff_field(saved, "sienna_unchained_exploding_burning_enemies", "proc_chance", 1)
        if ExplosionTemplates and ExplosionTemplates.sienna_unchained_burning_enemies_explosion then
            saved.uc_expl_old = ExplosionTemplates.sienna_unchained_burning_enemies_explosion.explosion
            ExplosionTemplates.sienna_unchained_burning_enemies_explosion.explosion = {
                use_attacker_power_level = true,
                radius_min = 1,
                alert_enemies = true,
                radius_max = 2.5,
                no_friendly_fire = true,
                attacker_power_level_offset = 0.01,
                max_damage_radius_min = 0.5,
                alert_enemies_radius = 3,
                damage_profile_glance = "long_burn_explosion_glance",
                max_damage_radius_max = 2,
                sound_event_name = "fireball_big_hit",
                damage_profile = "long_burn_explosion",
                effect_name = "fx/wpnfx_flaming_flail_hit_01",
            }
        end
    end,
    restore = function(saved)
        _restore_buff_fields(saved)
        if saved.uc_expl_old and ExplosionTemplates and ExplosionTemplates.sienna_unchained_burning_enemies_explosion then
            ExplosionTemplates.sienna_unchained_burning_enemies_explosion.explosion = saved.uc_expl_old
            saved.uc_expl_old = nil
        end
    end,
}
_toggle_talent_modify("cbr_unchained_talent_4_1_attack_speed_high_oc", {
    { "bw_unchained", 4, 1, { buffs = { "sienna_unchained_attack_speed_on_overcharge" } } },
})
BR_TOGGLES.cbr_unchained_talent_4_2_team_burn = {
    apply = function(saved)
        _safe_modify_talent(saved, "bw_unchained", 4, 2, {
            buffs = { "gs_sienna_flaming_weapons_to_allies" }
        })
    end,
    restore = function(saved) _restore_modified_talents(saved) end,
}
-- Unchained > Misc: max-health on burn kill (2 talent buff templates).
-- Source: sienna_changes.lua:1229 / 1234. The trigger buff references
-- buff_func `gs_sienna_increase_max_health_on_burning_enemy_killed`
-- (BR-installed proc fn) — if bt doesn't install proc fns the buff is a
-- harmless no-op; the stat buff body is pure data.
BR_TOGGLES.cbr_unchained_talent_max_health_on_burn_kill = {
    apply = function(saved)
        saved.uc_maxhp_old = {}
        if BuffTemplates and BuffTemplates.gs_sienna_unchained_increase_max_health_on_kill then
            saved.uc_maxhp_old.trigger = BuffTemplates.gs_sienna_unchained_increase_max_health_on_kill.buffs[1]
            BuffTemplates.gs_sienna_unchained_increase_max_health_on_kill.buffs[1] = {
                name = "gs_sienna_unchained_increase_max_health_on_kill",
                event = "on_kill",
                buff_to_add = "gs_sienna_unchained_increase_max_health_on_kill_buff",
                buff_func = "gs_sienna_increase_max_health_on_burning_enemy_killed",
            }
        end
        if BuffTemplates and BuffTemplates.gs_sienna_unchained_increase_max_health_on_kill_buff then
            saved.uc_maxhp_old.stat = BuffTemplates.gs_sienna_unchained_increase_max_health_on_kill_buff.buffs[1]
            BuffTemplates.gs_sienna_unchained_increase_max_health_on_kill_buff.buffs[1] = {
                name = "gs_sienna_unchained_increase_max_health_on_kill_buff",
                refresh_durations = true,
                multiplier = 0.03,
                stat_buff = "max_health",
                icon = "sienna_unchained_reduced_vent_damage",
                max_stacks = 10,
                duration = 10,
            }
        end
    end,
    restore = function(saved)
        if not saved.uc_maxhp_old then return end
        if saved.uc_maxhp_old.trigger and BuffTemplates and BuffTemplates.gs_sienna_unchained_increase_max_health_on_kill then
            BuffTemplates.gs_sienna_unchained_increase_max_health_on_kill.buffs[1] = saved.uc_maxhp_old.trigger
        end
        if saved.uc_maxhp_old.stat and BuffTemplates and BuffTemplates.gs_sienna_unchained_increase_max_health_on_kill_buff then
            BuffTemplates.gs_sienna_unchained_increase_max_health_on_kill_buff.buffs[1] = saved.uc_maxhp_old.stat
        end
        saved.uc_maxhp_old = nil
    end,
}
_toggle_talent_modify("cbr_unchained_talent_5_2_overcharged_blocks", {
    { "bw_unchained", 5, 2, { buffs = { "sienna_unchained_overcharged_blocks" } } },
})
BR_TOGGLES.cbr_unchained_thorn_skin = {
    apply = function(saved)
        if not mod._cbr_thornskin_warned then
            mod:info("cbr_unchained_thorn_skin: damage-profile portion lives in wt; ct only registers the buff")
            mod._cbr_thornskin_warned = true
        end
    end,
    restore = function() end,
}
BR_TOGGLES.cbr_unchained_talent_4_3_overcharge_decay_and_cd = {
    apply = function(saved)
        _safe_modify_talent(saved, "bw_unchained", 4, 3, {
            buffs = { "sienna_unchained_reduced_overcharge_decay", "sienna_unchained_increased_ult_cooldown",
                      "sienna_unchained_ult_cooldown_on_overcharge" }
        })
    end,
    restore = function(saved) _restore_modified_talents(saved) end,
}
BR_TOGGLES.cbr_unchained_talent_5_3_blood_magic_tradeoff = {
    apply = function(saved)
        _safe_modify_talent(saved, "bw_unchained", 5, 3, {
            buffs = { "sienna_unchained_reduced_overcharge", "sienna_unchained_increased_health" }
        })
    end,
    restore = function(saved) _restore_modified_talents(saved) end,
}
BR_TOGGLES.cbr_unchained_talent_6_1_cd_reduction = {
    apply = function(saved)
        _safe_modify_talent(saved, "bw_unchained", 6, 1, {
            buffs = { "gs_sienna_unchained_reduced_cd" }
        })
    end,
    restore = function(saved) _restore_modified_talents(saved) end,
}
_toggle_talent_modify("cbr_unchained_talent_6_2_fire_aura", {
    { "bw_unchained", 6, 2, { buffs = { "sienna_unchained_activated_ability_fire_aura" } } },
})

-- ============================================================
-- 21. Sienna > Necromancer (~13)
-- ============================================================
_toggle_table_patches("cbr_necromancer_max_hp_125", function(set)
    if CareerSettings and CareerSettings.bw_necromancer and CareerSettings.bw_necromancer.attributes then
        set(CareerSettings.bw_necromancer.attributes, "max_hp", 125)
    end
end)
BR_TOGGLES.cbr_necromancer_passive_zoom = {
    apply = function(saved) _safe_append_passive_buff(saved, "bw_4", "kerillian_waywatcher_passive_increased_zoom") end,
    restore = function(saved) _restore_passive_appends(saved) end,
}
BR_TOGGLES.cbr_necromancer_crit_burst = {
    apply = function(saved)
        _safe_set_buff_field(saved, "sienna_necromancer_4_1_cursed_blood", "propagation_multiplier", 0.1)
    end,
    restore = function(saved) _restore_buff_fields(saved) end,
}
BR_TOGGLES.cbr_necromancer_stagger_zero_set = {
    apply = function(saved)
        if not mod._cbr_necro_stagger_warned then
            mod:info("cbr_necromancer_stagger_zero_set: damage-profile portion lives in wt; ct only registers gates")
            mod._cbr_necro_stagger_warned = true
        end
    end,
    restore = function() end,
}
_toggle_field_patches("cbr_necromancer_talent_2_3_unlimited_crit_cleave", {
    { buff = "sienna_necromancer_2_3", field = "multiplier", value = 0 },
})
_toggle_field_patches("cbr_necromancer_talent_2_1_as_per_skeleton", {
    { buff = "sienna_necromancer_2_1_attack_speed", field = "multiplier", value = 0.02 },
    { buff = "sienna_necromancer_2_1_attack_speed", field = "max_stacks", value = 12 },
})
_toggle_field_patches("cbr_necromancer_talent_2_2_ranged_power", {
    { buff = "sienna_necromancer_2_2_buff", field = "multiplier", value = 0.06 },
})
_toggle_field_patches("cbr_necromancer_talent_4_2_soul_rip_stacks_6", {
    { buff = "sienna_necromancer_4_2_soul_rip_stack", field = "max_stacks", value = 6 },
})
BR_TOGGLES.cbr_necromancer_talent_4_3_buffed_dot = {
    apply = function(saved)
        _safe_set_buff_field(saved, "sienna_necromancer_4_3_withering_touch", "dot_template_name",
            "sienna_necromancer_4_3_dot_buffed")
    end,
    restore = function(saved) _restore_buff_fields(saved) end,
}
_toggle_field_patches("cbr_necromancer_talent_5_1_cd_on_elite_kill", {
    { buff = "sienna_necromancer_5_1_reduced_overcharge", field = "multiplier", value = 0.05 },
})
BR_TOGGLES.cbr_necromancer_talent_5_2_big_hit_protection = {
    apply = function(saved)
        _safe_modify_talent(saved, "bw_necromancer", 5, 2, {
            buffs_to_add = { "necro_big_hit_protection" }
        })
    end,
    restore = function(saved) _restore_modified_talents(saved) end,
}
BR_TOGGLES.cbr_necromancer_talent_6_1_extra_skeletons_40s = {
    apply = function(saved)
        _safe_set_buff_field(saved, "necromancer_skeleton_timer", "duration", 40)
        _safe_set_buff_field(saved, "necromancer_pet_army", "duration", 40)
        _safe_set_buff_field(saved, "necromancer_pet_army_client", "duration", 40)
    end,
    restore = function(saved) _restore_buff_fields(saved) end,
}
_toggle_field_patches("cbr_necromancer_cursed_blood_propagation_10pct", {
    { buff = "sienna_necromancer_4_1_cursed_blood", field = "propagation_multiplier", value = 0.1 },
})

-- ============================================================
-- 22. Cross-character buffs (15 leaf-content toggles)
-- ============================================================
-- Each toggle overlays a richer body into the pre-registered stub.
local function _cross_buff_toggle(setting_id, buff_name, body)
    BR_TOGGLES[setting_id] = {
        apply = function(saved)
            if BuffTemplates and BuffTemplates[buff_name] then
                saved.cross_old = BuffTemplates[buff_name].buffs[1]
                BuffTemplates[buff_name].buffs[1] = body
            end
        end,
        restore = function(saved)
            if saved.cross_old and BuffTemplates and BuffTemplates[buff_name] then
                BuffTemplates[buff_name].buffs[1] = saved.cross_old
                saved.cross_old = nil
            end
        end,
    }
end

_cross_buff_toggle("cbr_buff_zealot_burning_debuff", "zealot_burning_debuff", {
    name = "zealot_burning_debuff", stat_buff = "damage_taken", multiplier = 0.1,
    duration = 5, max_stacks = 1, refresh_durations = true,
})
_cross_buff_toggle("cbr_buff_wp_fury_burn", "warrior_priest_fury_burn", {
    name = "warrior_priest_fury_burn", damage_type = "burninating",
    duration = 4, time_between_dot_damages = 0.5, perks = { "burning" },
})
_cross_buff_toggle("cbr_buff_engineer_melee_burn", "engineer_melee_explosion_burn", {
    name = "engineer_melee_explosion_burn", damage_type = "burninating",
    duration = 4, time_between_dot_damages = 0.5, perks = { "burning" },
})
_cross_buff_toggle("cbr_buff_huntsman_defence_debuff", "defence_debuff_enemies_huntsman_explosion", {
    name = "defence_debuff_enemies_huntsman_explosion", stat_buff = "damage_taken",
    multiplier = 0.2, duration = 6, max_stacks = 1, refresh_durations = true,
})
_cross_buff_toggle("cbr_buff_wp_lightning_debuff", "defence_debuff_enemies_warrior_priest_lightning", {
    name = "defence_debuff_enemies_warrior_priest_lightning", stat_buff = "damage_taken",
    multiplier = 0.15, duration = 5, max_stacks = 1, refresh_durations = true,
})
_cross_buff_toggle("cbr_buff_wp_bubble_debuff", "attack_debuff_enemies_warrior_priest_bubble", {
    name = "attack_debuff_enemies_warrior_priest_bubble", stat_buff = "damage_dealt",
    multiplier = -0.25, duration = 5, max_stacks = 1, refresh_durations = true,
})
_cross_buff_toggle("cbr_buff_wp_tome_debuff", "defence_debuff_enemies_warrior_priest_tome", {
    name = "defence_debuff_enemies_warrior_priest_tome", stat_buff = "damage_taken",
    multiplier = 0.1, duration = 5, max_stacks = 1, refresh_durations = true,
})
_cross_buff_toggle("cbr_buff_shield_bash_debuff", "attack_debuff_enemies_shield_bash", {
    name = "attack_debuff_enemies_shield_bash", stat_buff = "damage_dealt",
    multiplier = -0.2, duration = 3, max_stacks = 1, refresh_durations = true,
})
_cross_buff_toggle("cbr_buff_long_burn_low_damage", "long_burn_low_damage", {
    name = "long_burn_low_damage", damage_type = "burninating",
    duration = 8, time_between_dot_damages = 1, perks = { "burning" },
})
_cross_buff_toggle("cbr_buff_long_burn_extra_low_damage", "long_burn_extra_low_damage", {
    name = "long_burn_extra_low_damage", damage_type = "burninating",
    duration = 8, time_between_dot_damages = 1, perks = { "burning" },
})
_cross_buff_toggle("cbr_buff_burning_magma_dot", "burning_magma_dot", {
    name = "burning_magma_dot", damage_type = "burninating",
    duration = 4, time_between_dot_damages = 0.5, perks = { "burning" },
})
_cross_buff_toggle("cbr_buff_unchained_push_burn", "burning_1W_dot_unchained_push", {
    name = "burning_1W_dot_unchained_push", damage_type = "burninating",
    duration = 4, time_between_dot_damages = 0.5, perks = { "burning" },
})
BR_TOGGLES.cbr_buff_infinite_burn_dot_clones = { apply = function() end, restore = function() end }
-- explosion toggles (overlay into existing pre-registered ExplosionTemplates stubs)
-- Cross > Explosions: warp lightning strike (delayed).
-- Source: experimental_talent_changes.lua:355. Overlay into pre-registered stub.
BR_TOGGLES.cbr_buff_warp_lightning_strike_delayed = {
    apply = function(saved)
        if not ExplosionTemplates or not ExplosionTemplates.warp_lightning_strike_delayed then return end
        saved.warp_lit_old = ExplosionTemplates.warp_lightning_strike_delayed
        ExplosionTemplates.warp_lightning_strike_delayed = {
            name = "warp_lightning_strike_delayed",
            time_to_explode = 2,
            follow_time = 3,
            explosion = {
                always_hurt_players = true,
                radius = 2,
                alert_enemies = false,
                sound_event_name = "fireball_big_hit",
                max_damage_radius_min = 0.5,
                attack_template = "chaos_magic_missile",
                max_damage_radius_max = 1,
                damage_type = "grenade",
                damage_interval = 0,
                power_level = 1000,
                effect_name = "fx/warp_lightning_bolt_impact",
                immune_breeds = { all = true },
            },
        }
    end,
    restore = function(saved)
        if saved.warp_lit_old and ExplosionTemplates then
            ExplosionTemplates.warp_lightning_strike_delayed = saved.warp_lit_old
            saved.warp_lit_old = nil
        end
    end,
}
-- Cross > Explosions: timed warp explosion.
-- Source: experimental_talent_changes.lua:509. Overlay into pre-registered stub.
BR_TOGGLES.cbr_buff_timed_warp_explosion = {
    apply = function(saved)
        if not ExplosionTemplates or not ExplosionTemplates.timed_warp_explosion then return end
        saved.timed_warp_old = ExplosionTemplates.timed_warp_explosion
        ExplosionTemplates.timed_warp_explosion = {
            name = "timed_warp_explosion",
            time_to_explode = 3,
            explosion = {
                alert_enemies = true,
                radius = 4,
                allow_friendly_fire_override = true,
                max_damage_radius = 4,
                alert_enemies_radius = 15,
                sound_event_name = "Play_enemy_combat_warpfire_backpack_explode",
                damage_profile = "warpfire_thrower_explosion",
                power_level = 1000,
                effect_name = "fx/chr_warp_fire_explosion_01",
            },
        }
    end,
    restore = function(saved)
        if saved.timed_warp_old and ExplosionTemplates then
            ExplosionTemplates.timed_warp_explosion = saved.timed_warp_old
            saved.timed_warp_old = nil
        end
    end,
}

-- ============================================================
-- Apply / restore engine
-- ============================================================

local function apply_br()
    -- Restore everything first (snapshot/revert)
    for setting_id, saved in pairs(_br_originals) do
        local def = BR_TOGGLES[setting_id]
        if def and def.restore then def.restore(saved) end
    end
    _br_originals = {}

    -- Pre-register if master is on (delegates to bt now).
    _pre_register_all()

    if not _br_master_active() then return end

    for setting_id, def in pairs(BR_TOGGLES) do
        if mod:get(setting_id) then
            local saved = {}
            if def.apply then def.apply(saved) end
            _br_originals[setting_id] = saved
        end
    end
end

local function restore_br()
    for setting_id, saved in pairs(_br_originals) do
        local def = BR_TOGGLES[setting_id]
        if def and def.restore then def.restore(saved) end
    end
    _br_originals = {}
end

local function count_active()
    local count = 0
    if _br_master_active() then count = count + 1 end
    for setting_id, _ in pairs(BR_TOGGLES) do
        if mod:get(setting_id) then count = count + 1 end
    end
    return count
end

return {
    apply        = apply_br,
    restore      = restore_br,
    active_count = count_active,
    TOGGLES      = BR_TOGGLES,
}
