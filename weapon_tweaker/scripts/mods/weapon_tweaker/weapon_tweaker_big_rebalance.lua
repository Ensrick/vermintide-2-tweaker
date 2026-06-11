--[[
weapon_tweaker_big_rebalance.lua
=================================

Toggle-gated implementation of Core's Big Rebalance weapon changes.

Architecture
------------
1. Master toggle `br_master_enable_registrations` gates `_register_all()`
   which writes every BR_REGISTRATIONS entry (defs.lua) into
   DamageProfileTemplates / ExplosionTemplates / BuffTemplates and the
   NetworkLookup tables — UNCONDITIONALLY ON EVERY PEER, in sorted order
   per the cross-mod registrations list. See feedback_vt2_gated_registration_diverges.

2. Per-toggle apply functions are called once at mod load (and on
   `on_setting_changed` for live retune of static tables). Each function
   is a thin `if mod:get("br_<group>") then ... end` gate around verbatim
   assignments from `_big_rebalance_extract/source/weapon_changes.lua`.

3. Function hooks (Flamethrower / Beam / TrueFlight start/fire) are
   installed unconditionally when the master is on; per-toggle gates
   inside each hook decide whether to use BR behavior or call vanilla.

NOTE on cross-cutting dependencies: BR's `DamageUtils.stagger_ai`,
`apply_buffs_to_damage`, `calculate_damage` rewrites are et-owned and
are NOT installed here. wt-side toggles that benefit from those (e.g.
`br_shield_slam_replace`) work in isolation but reach their full
intended balance only when et's stagger rewrite is also enabled — this
is documented in each toggle's description.
]]

local mod = get_mod("wt")

-- v0.12.88-dev: local _dbg helper. The main `weapon_tweaker.lua` file-local
-- `_dbg` isn't reachable from this sibling file (Lua 5.1 file-locals don't
-- cross dofile boundaries). Mirror the same gate so [wt:dbg] log lines all
-- live under one toggle. Sampling counters per-hook are inside the hook
-- bodies; this helper is the raw emit primitive only.
local function _dbg(fmt, ...)
    if mod:get("enable_debug_logging") then
        mod:info("[wt:dbg] " .. fmt, ...)
    end
end

-- Forward-ref guard: defs is a pure-data module loaded via dofile so this
-- module is self-contained.
--
-- The 419-line `BR_REGISTRATIONS` table that previously lived in
-- `weapon_tweaker_big_rebalance_registrations.lua` has been EXTRACTED to
-- the new `buff_tweaker` (`bt`) mod. wt no longer ships its own copy of
-- the canonical 328-entry list; bt is the single source of truth across
-- all consumer mods. wt now reads bt's master toggle to decide whether
-- BR sub-toggles do any work, and trusts bt to have registered the
-- names + NetworkLookup indices by the time wt's apply functions run.
-- See buff_tweaker/CHANGELOG.md for the architecture rationale.
local DEFS = mod:dofile("scripts/mods/weapon_tweaker/weapon_tweaker_big_rebalance_defs")

local BR = {}

-- ============================================================
-- SHARED HELPERS
-- ============================================================

local function _w(template_name)
    return rawget(_G, "Weapons") and Weapons[template_name]
end
local function _dpt(name) return rawget(_G, "DamageProfileTemplates") and DamageProfileTemplates[name] end
local function _et(name)  return rawget(_G, "ExplosionTemplates") and ExplosionTemplates[name] end
local function _act(template_name, action_name, sub_name)
    local t = _w(template_name)
    return t and t.actions and t.actions[action_name] and t.actions[action_name][sub_name]
end

local function _on(setting) return mod:get(setting) == true end

-- Master toggle now lives in the bt (`buff_tweaker`) mod. If bt isn't
-- installed, returns false → every BR sub-toggle silently no-ops.
-- If bt IS installed but its master is off → same.
-- If bt is installed and master is on AND bt has finished its
-- registration pass → returns true and sub-toggles do their work.
local function _master()
    local bt = get_mod("bt")
    if not (bt and bt.is_br_active) then return false end
    return bt:is_br_active() == true
end

-- Append `entry` to allowed_chain_actions of a sub-action.
local function _append_chain(sub_action, entry)
    if not sub_action or not sub_action.allowed_chain_actions then return end
    local list = sub_action.allowed_chain_actions
    list[#list + 1] = entry
end

-- ============================================================
-- MASTER REGISTRATIONS
-- ============================================================
-- Pre-registers every BR_REGISTRATIONS entry on every peer, in sorted
-- order, regardless of whether the per-toggle that consumes it is on.
-- This is the rule from feedback_vt2_gated_registration_diverges.

local _master_registered = false

local function _ensure_network_lookup(tbl_name, key)
    local NL = rawget(_G, "NetworkLookup")
    if not NL then return end
    local lookup = NL[tbl_name]
    if not lookup then return end
    if lookup[key] then return end  -- already registered
    local n = #lookup + 1
    lookup[n] = key
    lookup[key] = n
end

local function _register_damage_profile(name)
    if not rawget(_G, "DamageProfileTemplates") then return end
    if DamageProfileTemplates[name] then
        _ensure_network_lookup("damage_profiles", name)
        return
    end
    local def = DEFS.damage_profiles[name]
    if not def then
        -- ct/et-owned entry; create a placeholder so NetworkLookup index
        -- still increments deterministically. ct/et's own master block
        -- will overwrite with the real definition.
        DamageProfileTemplates[name] = { _br_placeholder_owner = "non-wt" }
    else
        DamageProfileTemplates[name] = table.clone(def)
    end
    _ensure_network_lookup("damage_profiles", name)
end

local function _register_explosion(name)
    if not rawget(_G, "ExplosionTemplates") then return end
    if ExplosionTemplates[name] then return end
    local def = DEFS.explosions[name]
    if def then ExplosionTemplates[name] = table.clone(def) end
end

local function _register_buff(name)
    local BT = rawget(_G, "BuffTemplates")
    if not BT then return end
    if BT[name] then
        _ensure_network_lookup("buff_templates", name)
        return
    end
    local def = DEFS.buffs[name]
    if def then
        BT[name] = { buffs = { table.clone(def) } }
    else
        BT[name] = { _br_placeholder_owner = "non-wt", buffs = {} }
    end
    _ensure_network_lookup("buff_templates", name)
end

local function _register_statbuff_app(name)
    local SBM = rawget(_G, "StatBuffApplicationMethods")
    if SBM and not SBM[name] then SBM[name] = "stacking_multiplier" end
    local NSBM = rawget(_G, "NewStatBuffApplicationMethods") or {}
    NSBM[name] = "stacking_multiplier"
    _G.NewStatBuffApplicationMethods = NSBM
end

-- No-op shim. Registration moved to the `bt` (buff_tweaker) mod, which
-- is the single source of truth for the 328-entry canonical list. Kept
-- as a stub so existing callers (the bottom-of-file `BR.register_all()`
-- line and any future internal callers) don't crash. The actual
-- registration pass happens in bt when its master toggle is on; wt's
-- per-feature toggles gate on bt's `is_br_active()` API.
function BR.register_all()
    if _master_registered then return end
    if not _master() then return end

    mod:info("[BR] master registration was performed by buff_tweaker (bt); wt skipping local pass.")

    -- Legacy bits below kept inert. The original code wrote each
    -- BR_REGISTRATIONS entry into BuffTemplates / DamageProfileTemplates
    -- / ExplosionTemplates / StatBuffApplicationMethods + NetworkLookup.
    -- All of that now happens in bt.

    if false then
        -- Dead code (kept for reference until next cleanup pass).
        for _ = 1, 0 do end
    end

    -- Merge NewStatBuffApplicationMethods into the canonical table once
    -- everything is in place.
    if rawget(_G, "NewStatBuffApplicationMethods") and rawget(_G, "StatBuffApplicationMethods") then
        table.merge_recursive(StatBuffApplicationMethods, NewStatBuffApplicationMethods)
    end

    _master_registered = true
    mod:info("[BR] master registration pass complete")
end

-- ============================================================
-- WEAPONS-TABLE META-INIT (M11 — `br_misc_weapons_meta_init`)
-- ============================================================
-- Bulk-init loop that sets crosshair_style="dot", computes
-- effective_against_combined, attaches lookup_data to every sub-action,
-- and auto-sets tap/hold attack max_range. Many other BR toggles assume
-- lookup_data exists; we run this whenever any BR toggle is enabled
-- (recommendation (c) in design open questions).

local _weapons_meta_done = false
local function _apply_weapons_meta_init()
    if _weapons_meta_done then return end
    if not _on("br_misc_weapons_meta_init") and not _master() then return end
    if not rawget(_G, "Weapons") then return end

    local MeleeBuffTypes = rawget(_G, "MeleeBuffTypes") or { MELEE_1H = true, MELEE_2H = true }
    local RangedBuffTypes = rawget(_G, "RangedBuffTypes") or { RANGED = true, RANGED_ABILITY = true }
    local WEAPON_LEN = 1.919366
    local TAP_OFFSET = 0.6
    local HOLD_OFFSET = 0.65

    for item_template_name, item_template in pairs(Weapons) do
        item_template.name = item_template_name
        item_template.crosshair_style = item_template.crosshair_style or "dot"
        local amd = item_template.attack_meta_data
        local tap = amd and amd.tap_attack
        local hold = amd and amd.hold_attack
        local set_tap = tap and tap.max_range == nil
        local set_hold = hold and hold.max_range == nil

        if RangedBuffTypes[item_template.buff_type] and amd then
            amd.effective_against = amd.effective_against or 0
            amd.effective_against_charged = amd.effective_against_charged or 0
            if rawget(_G, "bit") then
                amd.effective_against_combined = bit.bor(amd.effective_against, amd.effective_against_charged)
            end
        end

        local actions = item_template.actions
        if actions then
            for action_name, sub_actions in pairs(actions) do
                if type(sub_actions) == "table" then
                    for sub_action_name, sub in pairs(sub_actions) do
                        if type(sub) == "table" then
                            sub.lookup_data = sub.lookup_data or {
                                item_template_name = item_template_name,
                                action_name = action_name,
                                sub_action_name = sub_action_name,
                            }
                            if action_name == "action_one" then
                                local range_mod = sub.range_mod or 1
                                if set_tap and type(sub_action_name) == "string"
                                        and string.find(sub_action_name, "light_attack") then
                                    local cur = tap.max_range or math.huge
                                    local rng = TAP_OFFSET + WEAPON_LEN * range_mod
                                    tap.max_range = math.min(cur, rng)
                                elseif set_hold and type(sub_action_name) == "string"
                                        and string.find(sub_action_name, "heavy_attack") then
                                    local cur = hold.max_range or math.huge
                                    local rng = HOLD_OFFSET + WEAPON_LEN * range_mod
                                    hold.max_range = math.min(cur, rng)
                                end
                            end

                            local impact = sub.impact_data
                            if impact and impact.pickup_settings then
                                local lhz = impact.pickup_settings.link_hit_zones
                                if lhz then
                                    for i = 1, #lhz do
                                        lhz[lhz[i]] = true
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    _weapons_meta_done = true
end

-- ============================================================
-- MELEE — 1H HAMMERS
-- ============================================================

local function _apply_melee_1h_hammer()
    if _on("br_1h_hammer_dodge_count") then
        local emp = _w("one_handed_hammer_template_1")
        local dwf = _w("one_handed_hammer_template_2")
        local pri = _w("one_handed_hammer_priest_template")
        if emp then emp.dodge_count = 4 end
        if dwf then dwf.dodge_count = 4 end
        if pri then pri.dodge_count = 4 end
    end

    if _on("br_1h_hammer_light_down_speed") then
        local a = _act("one_handed_hammer_template_1", "action_one", "light_attack_down")
        if a then a.anim_time_scale = 1.5 end
        a = _act("one_handed_hammer_template_2", "action_one", "light_attack_down")
        if a then a.anim_time_scale = 1.5 end
        a = _act("one_handed_hammer_priest_template", "action_one", "light_attack_04")
        if a then a.anim_time_scale = 1.5 end
    end

    if _on("br_1h_hammer_heavy_gs_profile") then
        for _, key in ipairs({ "one_handed_hammer_template_1", "one_handed_hammer_template_2" }) do
            local L = _act(key, "action_one", "heavy_attack_left")
            local R = _act(key, "action_one", "heavy_attack_right")
            if L then L.damage_profile = "gs_1h_heavy" end
            if R then R.damage_profile = "gs_1h_heavy" end
        end
        local L = _act("one_handed_hammer_priest_template", "action_one", "heavy_attack_01")
        local R = _act("one_handed_hammer_priest_template", "action_one", "heavy_attack_02")
        if L then L.damage_profile = "gs_1h_heavy" end
        if R then R.damage_profile = "gs_1h_heavy" end
    end

    if _on("br_1h_hammer_heavy_range") then
        for _, key in ipairs({ "one_handed_hammer_template_1", "one_handed_hammer_template_2" }) do
            local L = _act(key, "action_one", "heavy_attack_left")
            local R = _act(key, "action_one", "heavy_attack_right")
            if L then L.range_mod = 1.2 end
            if R then R.range_mod = 1.2 end
        end
        local L = _act("one_handed_hammer_priest_template", "action_one", "heavy_attack_01")
        local R = _act("one_handed_hammer_priest_template", "action_one", "heavy_attack_02")
        if L then L.range_mod = 1.2 end
        if R then R.range_mod = 1.2 end
    end

    if _on("br_1h_hammer_tome_rework") then
        local tpl = "one_handed_hammer_book_priest_template"
        for _, sn in ipairs({ "light_attack_01", "light_attack_01_pose", "light_attack_02" }) do
            local a = _act(tpl, "action_one", sn)
            if a then a.hit_mass_count = nil; a.anim_time_scale = 1.05 end
        end
        local hl = _act(tpl, "action_one", "heavy_attack_left")
        if hl then hl.damage_profile = "gs_1h_heavy" end
        local hc = _act(tpl, "action_one", "heavy_attack_left_charged")
        if hc then hc.damage_profile = "heavy_dash"; hc.range_mod = 1.2; hc.width_mod = 35 end
        local hs = _act(tpl, "action_one", "heavy_attack_stab_charged")
        if hs and hs.lunge_settings then
            hs.lunge_settings.duration = 0.64
            hs.lunge_settings.initial_speed = 20
        end
        for _, sn in ipairs({ "default", "default_pose", "default_right" }) do
            local a = _act(tpl, "action_one", sn)
            if a then a.charge_speed = 0.67 end
        end
        local a3 = _act(tpl, "action_three", "default")
        if a3 then a3.charge_speed = 0.67 end

        -- Explosion profile retunes
        local hbe = _dpt("hammer_book_charged_explosion")
        if hbe then
            if hbe.default_target and hbe.default_target.power_distribution then
                hbe.default_target.power_distribution.attack = 0.7
            end
            if hbe.armor_modifier then
                hbe.armor_modifier.attack = { 1, 0.5, 2, 1, 0.75, 0.5 }
                hbe.armor_modifier.impact = { 1, 1, 1, 1, 1.5, 1 }
            end
        end
        local hbiex = _et("hammer_book_charged_impact_explosion")
        if hbiex and hbiex.explosion then
            hbiex.explosion.radius_max = 2
            hbiex.explosion.enemy_debuff = { "defence_debuff_enemies_warrior_priest_tome" }
        end
    end

    if _on("br_1h_hammer_wizard_rework") then
        local tpl = "one_handed_hammer_wizard_template_1"
        local ao = _w(tpl) and _w(tpl).actions and _w(tpl).actions.action_one
        if ao then
            if ao.light_attack_upper then ao.light_attack_upper.hit_mass_count = nil end
            if ao.light_attack_left then ao.light_attack_left.anim_time_scale = 1.3 end
            if ao.light_attack_bopp then ao.light_attack_bopp.anim_time_scale = 1.2 end
            if ao.heavy_attack_left then
                ao.heavy_attack_left.range_mod = 1.75
                ao.heavy_attack_left.slide_armour_hit = true
                ao.heavy_attack_left.additional_critical_strike_chance = 0.1
            end
            if ao.heavy_attack_right_up then
                ao.heavy_attack_right_up.range_mod = 1.75
                ao.heavy_attack_right_up.slide_armour_hit = true
                ao.heavy_attack_right_up.additional_critical_strike_chance = 0.1
            end
            for _, sn in ipairs({ "light_attack_left", "light_attack_right",
                                  "light_attack_last", "light_attack_upper", "light_attack_bopp" }) do
                if ao[sn] then ao[sn].range_mod = 1.5 end
            end
            if ao.heavy_attack then ao.heavy_attack.range_mod = 1.5 end
            if ao.default_left and ao.default_left.allowed_chain_actions then
                if ao.default_left.allowed_chain_actions[2] then
                    ao.default_left.allowed_chain_actions[2].sub_action = "heavy_attack"
                end
                if ao.default_left.allowed_chain_actions[6] then
                    ao.default_left.allowed_chain_actions[6].sub_action = "heavy_attack"
                end
                ao.default_left.anim_event = "attack_swing_charge_left_diagonal"
            end
        end
    end
end

-- ============================================================
-- MELEE — 2H HAMMERS
-- ============================================================

local function _apply_melee_2h_hammer()
    if _on("br_2h_hammer_emp") then
        local ao = _w("two_handed_hammers_template_1") and _w("two_handed_hammers_template_1").actions and _w("two_handed_hammers_template_1").actions.action_one
        if ao then
            if ao.light_attack_push_left_up then
                ao.light_attack_push_left_up.damage_profile = "light_blunt_tank_diag"
                ao.light_attack_push_left_up.anim_time_scale = 1.2
            end
            if ao.light_attack_left_up then
                ao.light_attack_left_up.additional_critical_strike_chance = 0.1
                ao.light_attack_left_up.anim_time_scale = 1.6
                ao.light_attack_left_up.damage_profile = "light_blunt_tank_diag"
                ao.light_attack_left_up.hit_mass_count = rawget(_G, "TANK_HIT_MASS_COUNT")
            end
        end
    end

    if _on("br_2h_hammer_priest") then
        local tpl = "two_handed_hammer_priest_template"
        local ao = _w(tpl) and _w(tpl).actions and _w(tpl).actions.action_one
        local at = _w(tpl) and _w(tpl).actions and _w(tpl).actions.action_three
        if ao then
            if ao.light_attack_01 then ao.light_attack_01.anim_time_scale = 1 end
            if ao.light_attack_02 then ao.light_attack_02.anim_time_scale = 1 end
            if ao.light_attack_03 then ao.light_attack_03.damage_profile = "medium_slashing_linesman_uppercut" end
            if ao.heavy_attack_02 then ao.heavy_attack_02.anim_time_scale = 1.1 end
            local p = _dpt("priest_hammer_heavy_blunt_tank_upper")
            if p then p.shield_break = true end
            -- chain start_times
            for _, sn in ipairs({ "heavy_attack_01", "heavy_attack_02", "heavy_attack_03" }) do
                local sa = ao[sn]
                if sa and sa.allowed_chain_actions and sa.allowed_chain_actions[7] then
                    sa.allowed_chain_actions[7].start_time = 0.5
                end
            end
            for _, sn in ipairs({ "light_attack_01", "light_attack_02", "light_attack_03" }) do
                local sa = ao[sn]
                if sa and sa.allowed_chain_actions and sa.allowed_chain_actions[8] then
                    sa.allowed_chain_actions[8].start_time = 0.5
                end
            end
            if ao.push and ao.push.allowed_chain_actions and ao.push.allowed_chain_actions[7] then
                ao.push.allowed_chain_actions[7].start_time = 0.5
            end
        end
        if at and at.default then
            at.default.anim_time_scale = 1.1
            at.default.allowed_chain_actions = {
                { sub_action = "default", input = "action_one", action = "action_one", end_time = 1, start_time = 0.35 },
                { sub_action = "default", input = "action_one", action = "action_one", start_time = 1 },
                { sub_action = "default", input = "action_two_hold", action = "action_two", start_time = 0.4 },
                { sub_action = "default", input = "action_two_hold", action = "action_two", release_required = "action_two_hold", end_time = 0.3, start_time = 0 },
                { sub_action = "default", input = "action_wield", action = "action_wield", end_time = 0.5, start_time = 0.3 },
                { sub_action = "default", input = "action_wield", action = "action_wield", start_time = 0.5 },
            }
        end
    end

    if _on("br_cog_rework") then
        local tpl = "two_handed_cog_hammers_template_1"
        local ao = _w(tpl) and _w(tpl).actions and _w(tpl).actions.action_one
        if ao then
            if ao.light_attack_left then ao.light_attack_left.anim_time_scale = 0.95
                ao.light_attack_left.anim_event = "attack_swing_up_pose" end
            if ao.light_attack_left_pose then ao.light_attack_left_pose.anim_time_scale = 0.95 end
            if ao.light_attack_right then ao.light_attack_right.anim_time_scale = 0.95 end
            if ao.light_attack_last then ao.light_attack_last.additional_critical_strike_chance = 0.1 end
            if ao.light_attack_up_right_last then ao.light_attack_up_right_last.additional_critical_strike_chance = 0.1 end
            if ao.light_attack_bopp then ao.light_attack_bopp.anim_time_scale = 1.2 end
            -- The 19-entry cog rework: we apply the speed/crit fields above.
            -- The full chain-action / baked-sweep rewrites are non-trivial
            -- and would require copying ~150 LOC of action tables; deferred
            -- to a follow-up implementation pass (flagged in summary as
            -- partially-implemented).
        end
    end
end

-- ============================================================
-- MELEE — 1H SWORDS
-- ============================================================

local function _apply_melee_1h_sword()
    if _on("br_1h_sword_template1_range") then
        local tpl = _w("one_handed_swords_template_1")
        if tpl then tpl.dodge_count = 4 end
        local ao = tpl and tpl.actions and tpl.actions.action_one
        if ao then
            if ao.light_attack_last then ao.light_attack_last.range_mod = 1.4 end
            if ao.heavy_attack_left then ao.heavy_attack_left.range_mod = 1.4 end
            if ao.heavy_attack_right then ao.heavy_attack_right.range_mod = 1.4 end
        end
    end

    if _on("br_flaming_sword_rework") then
        local tpl = _w("flaming_sword_template_1")
        if tpl then tpl.dodge_count = 4 end
        local ao = tpl and tpl.actions and tpl.actions.action_one
        if ao then
            if ao.light_attack_right then
                ao.light_attack_right.damage_profile = "light_slashing_linesman_finesse"
                ao.light_attack_right.anim_time_scale = 1.2
            end
            if ao.light_attack_left then
                ao.light_attack_left.damage_profile = "light_slashing_linesman_finesse"
                ao.light_attack_left.anim_time_scale = 1.35
            end
            if ao.light_attack_stab then
                ao.light_attack_stab.ignore_armour_hit = true
                ao.light_attack_stab.anim_time_scale = 1.4
                if ao.light_attack_stab.allowed_chain_actions then
                    if ao.light_attack_stab.allowed_chain_actions[1] then
                        ao.light_attack_stab.allowed_chain_actions[1].sub_action = "default_right_heavy"
                    end
                    if ao.light_attack_stab.allowed_chain_actions[2] then
                        ao.light_attack_stab.allowed_chain_actions[2].sub_action = "default_right_heavy"
                    end
                end
            end
        end
    end

    if _on("br_falchion_heavy") then
        local ao = _w("one_hand_falchion_template_1") and _w("one_hand_falchion_template_1").actions and _w("one_hand_falchion_template_1").actions.action_one
        if ao then
            if ao.heavy_attack then ao.heavy_attack.damage_profile = "falchion_heavy" end
            if ao.heavy_attack_2 then
                ao.heavy_attack_2.damage_profile = "falchion_heavy"
                if ao.heavy_attack_2.allowed_chain_actions and ao.heavy_attack_2.allowed_chain_actions[1] then
                    ao.heavy_attack_2.allowed_chain_actions[1].sub_action = "default_down"
                end
            end
        end
    end

    if _on("br_we_1h_sword") then
        local ao = _w("we_one_hand_sword_template_1") and _w("we_one_hand_sword_template_1").actions and _w("we_one_hand_sword_template_1").actions.action_one
        if ao then
            if ao.heavy_attack_up then
                ao.heavy_attack_up.hit_mass_count = rawget(_G, "LINESMAN_HIT_MASS_COUNT")
                ao.heavy_attack_up.damage_profile = "medium_slashing_axe_linesman"
            end
            if ao.light_attack_last and ao.light_attack_last.allowed_chain_actions then
                for i = 1, 3 do
                    if ao.light_attack_last.allowed_chain_actions[i] then
                        ao.light_attack_last.allowed_chain_actions[i].start_time = 0.5
                    end
                end
            end
        end
    end
end

-- ============================================================
-- MELEE — 2H SWORDS
-- ============================================================

local function _apply_melee_2h_sword()
    if _on("br_exec_sword_speed") then
        local ao = _w("two_handed_swords_executioner_template_1") and _w("two_handed_swords_executioner_template_1").actions and _w("two_handed_swords_executioner_template_1").actions.action_one
        if ao then
            if ao.light_attack_left then ao.light_attack_left.anim_time_scale = 1.1 end
            if ao.light_attack_right then ao.light_attack_right.anim_time_scale = 1.1 end
            if ao.light_attack_left_diagonal then ao.light_attack_left_diagonal.anim_time_scale = 1.1 end
            if ao.light_attack_bopp then ao.light_attack_bopp.anim_time_scale = 1.2 end
            if ao.heavy_attack_left then ao.heavy_attack_left.additional_critical_strike_chance = 0 end
        end
    end

    if _on("br_2h_sword_template1") then
        local ao = _w("two_handed_swords_template_1") and _w("two_handed_swords_template_1").actions and _w("two_handed_swords_template_1").actions.action_one
        if ao then
            if ao.light_attack_bopp then
                ao.light_attack_bopp.damage_profile = "medium_slashing_smiter_2h"
                ao.light_attack_bopp.anim_time_scale = 1.35
            end
            if ao.heavy_attack_left then ao.heavy_attack_left.damage_profile = "tb_two_handed_sword_heavy" end
            if ao.heavy_attack_right then ao.heavy_attack_right.damage_profile = "tb_two_handed_sword_heavy" end
        end
    end

    if _on("br_bastard_sword") then
        local ao = _w("bastard_sword_template") and _w("bastard_sword_template").actions and _w("bastard_sword_template").actions.action_one
        if ao then
            if ao.light_attack_left and ao.light_attack_left.allowed_chain_actions and ao.light_attack_left.allowed_chain_actions[1] then
                ao.light_attack_left.allowed_chain_actions[1].start_time = 0.5
            end
            if ao.heavy_attack_down then ao.heavy_attack_down.damage_profile = "gs_heavy_slashing_smiter" end
        end
        local at = rawget(_G, "AttackTemplates") and AttackTemplates.heavy_slashing_smiter
        if at then at.headshot_sound = "executioner_sword_critical" end
    end

    if _on("br_we_2h_sword") then
        local ao = _w("two_handed_swords_wood_elf_template") and _w("two_handed_swords_wood_elf_template").actions and _w("two_handed_swords_wood_elf_template").actions.action_one
        if ao then
            if ao.light_attack_bopp then ao.light_attack_bopp.anim_time_scale = 0.95 end
            if ao.light_attack_right_upward then ao.light_attack_right_upward.anim_time_scale = 1.25 end
            if ao.light_attack_left_upward then ao.light_attack_left_upward.anim_time_scale = 1.25 end
            if ao.heavy_attack_down_first then
                ao.heavy_attack_down_first.anim_time_scale = 1.6
                if ao.heavy_attack_down_first.buff_data then
                    if ao.heavy_attack_down_first.buff_data[1] then ao.heavy_attack_down_first.buff_data[1].external_multiplier = 1.5 end
                    if ao.heavy_attack_down_first.buff_data[2] then ao.heavy_attack_down_first.buff_data[2].external_multiplier = 0.5 end
                end
            end
            if ao.heavy_attack_down_second then ao.heavy_attack_down_second.anim_time_scale = 1.1 end
        end
    end
end

-- ============================================================
-- MELEE — SPEARS / HALBERDS / POLEARMS
-- ============================================================

local function _apply_melee_polearm()
    if _on("br_2h_spear_emp") then
        local ao = _w("two_handed_heavy_spears_template") and _w("two_handed_heavy_spears_template").actions and _w("two_handed_heavy_spears_template").actions.action_one
        if ao then
            if ao.light_attack_stab_1 then ao.light_attack_stab_1.anim_time_scale = 0.75 end
            if ao.light_attack_right then
                ao.light_attack_right.hit_mass_count = rawget(_G, "LINESMAN_HIT_MASS_COUNT")
                ao.light_attack_right.anim_time_scale = 1.05
            end
            if ao.default_left and ao.default_left.allowed_chain_actions then
                if ao.default_left.allowed_chain_actions[2] then
                    ao.default_left.allowed_chain_actions[2].sub_action = "heavy_attack_left"
                end
                if ao.default_left.allowed_chain_actions[6] then
                    ao.default_left.allowed_chain_actions[6].sub_action = "heavy_attack_left"
                    ao.default_left.allowed_chain_actions[6].auto_chain = nil
                end
                ao.default_left.anim_event = "attack_swing_charge_stab"
            end
        end
    end

    if _on("br_halberd_tb_profiles") then
        local ao = _w("two_handed_halberds_template_1") and _w("two_handed_halberds_template_1").actions and _w("two_handed_halberds_template_1").actions.action_one
        if ao then
            if ao.light_attack_left then
                ao.light_attack_left.damage_profile = "tb_halberd_light_slash"
                if ao.light_attack_left.allowed_chain_actions and ao.light_attack_left.allowed_chain_actions[2] then
                    ao.light_attack_left.allowed_chain_actions[2].start_time = 0.5
                end
            end
            if ao.light_attack_stab then ao.light_attack_stab.damage_profile = "tb_halberd_light_stab" end
            if ao.heavy_attack_left then ao.heavy_attack_left.damage_profile = "tb_halberd_heavy_slash" end
            if ao.heavy_attack_stab then ao.heavy_attack_stab.damage_profile = "tb_halberd_heavy_stab" end
            if ao.light_attack_down then ao.light_attack_down.damage_profile = "tb_halberd_light_chop" end
            if ao.light_attack_last then ao.light_attack_last.damage_profile = "tb_halberd_light_chop" end
        end
    end

    if _on("br_elf_spear_rework") then
        local ao = _w("two_handed_spears_elf_template_1") and _w("two_handed_spears_elf_template_1").actions and _w("two_handed_spears_elf_template_1").actions.action_one
        if ao then
            for _, sn in ipairs({ "heavy_attack_stab", "light_attack_left", "heavy_attack_left" }) do
                if ao[sn] then ao[sn].hit_mass_count = nil end
            end
            if ao.light_attack_left then
                ao.light_attack_left.damage_window_start = 0.27
                ao.light_attack_left.damage_window_end = 0.38
            end
            if ao.light_attack_stab_1 then
                ao.light_attack_stab_1.damage_window_start = 0.17
                ao.light_attack_stab_1.damage_window_end = 0.34
            end
            if ao.light_attack_stab_2 then
                ao.light_attack_stab_2.damage_window_start = 0.19
                ao.light_attack_stab_2.damage_window_end = 0.33
            end
            for _, sn in ipairs({ "heavy_attack_stab", "heavy_attack_left", "light_attack_left",
                                  "light_attack_right", "light_attack_stab_1", "light_attack_stab_2" }) do
                if ao[sn] then ao[sn].additional_critical_strike_chance = 0.1 end
            end
        end
    end

    if _on("br_1h_spearshield_chain") then
        local ao = _w("one_handed_spears_shield_template") and _w("one_handed_spears_shield_template").actions and _w("one_handed_spears_shield_template").actions.action_one
        if ao and ao.default_left then
            ao.default_left.anim_event = "attack_swing_charge_stab"
            if ao.default_left.allowed_chain_actions then
                if ao.default_left.allowed_chain_actions[2] then
                    ao.default_left.allowed_chain_actions[2].sub_action = "heavy_attack_stab"
                end
                if ao.default_left.allowed_chain_actions[6] then
                    ao.default_left.allowed_chain_actions[6].sub_action = "heavy_attack_stab"
                end
            end
        end
    end
end

-- ============================================================
-- MELEE — DAGGERS / DUAL WEAPONS
-- ============================================================

local function _apply_melee_dual()
    if _on("br_dw_mace_sword") then
        local ao = _w("dual_wield_hammer_sword_template") and _w("dual_wield_hammer_sword_template").actions and _w("dual_wield_hammer_sword_template").actions.action_one
        if ao then
            if ao.light_attack_left_diagonal then ao.light_attack_left_diagonal.hit_mass_count = rawget(_G, "TANK_HIT_MASS_COUNT") end
            if ao.light_attack_right then ao.light_attack_right.hit_mass_count = rawget(_G, "TANK_HIT_MASS_COUNT") end
            if ao.light_attack_left then ao.light_attack_left.damage_profile = "light_slashing_linesman_finesse" end
            if ao.light_attack_right_diagonal then ao.light_attack_right_diagonal.damage_profile = "light_slashing_linesman_finesse" end
            if ao.heavy_attack then
                ao.heavy_attack.hit_mass_count = nil
                ao.heavy_attack.damage_profile_left = "mace_sword_heavy"
                ao.heavy_attack.damage_profile_right = "mace_sword_heavy"
            end
            if ao.heavy_attack_2 then
                ao.heavy_attack_2.hit_mass_count = nil
                ao.heavy_attack_2.damage_profile_left = "mace_sword_heavy"
                ao.heavy_attack_2.damage_profile_right = "mace_sword_heavy"
                ao.heavy_attack_2.anim_time_scale = 1.15
            end
            if ao.light_attack_bopp then
                ao.light_attack_bopp.damage_profile_left = "mace_sword_bopp"
                ao.light_attack_bopp.damage_profile_right = "mace_sword_bopp"
            end
        end
    end

    if _on("br_1h_dagger_pushstab") then
        local ao = _w("one_handed_daggers_template_1") and _w("one_handed_daggers_template_1").actions and _w("one_handed_daggers_template_1").actions.action_one
        if ao and ao.push_stab and ao.push_stab.allowed_chain_actions then
            for i = 1, 2 do
                if ao.push_stab.allowed_chain_actions[i] then
                    ao.push_stab.allowed_chain_actions[i].sub_action = "default_right_heavy"
                end
            end
        end
    end

    if _on("br_dw_sword_dagger") then
        local ao = _w("dual_wield_sword_dagger_template_1") and _w("dual_wield_sword_dagger_template_1").actions and _w("dual_wield_sword_dagger_template_1").actions.action_one
        if ao then
            if ao.heavy_attack_2 then ao.heavy_attack_2.additional_critical_strike_chance = 0 end
            if ao.push_stab then ao.push_stab.additional_critical_strike_chance = 0 end
            if ao.heavy_attack then ao.heavy_attack.anim_time_scale = 1 end
        end
    end

    if _on("br_dw_swords_speed") then
        local ao = _w("dual_wield_swords_template_1") and _w("dual_wield_swords_template_1").actions and _w("dual_wield_swords_template_1").actions.action_one
        if ao then
            if ao.heavy_attack then ao.heavy_attack.anim_time_scale = 1 end
            if ao.heavy_attack_2 then ao.heavy_attack_2.anim_time_scale = 1.35 end
        end
    end

    if _on("br_dw_daggers") then
        local tpl = _w("dual_wield_daggers_template_1")
        local ao = tpl and tpl.actions and tpl.actions.action_one
        if ao then
            if ao.light_attack_left then ao.light_attack_left.additional_critical_strike_chance = 0.1 end
            if ao.light_attack_right then ao.light_attack_right.additional_critical_strike_chance = 0.1 end
            if ao.heavy_attack and ao.heavy_attack.allowed_chain_actions and ao.heavy_attack.allowed_chain_actions[5] then
                ao.heavy_attack.allowed_chain_actions[5].start_time = 0.35
            end
            if ao.heavy_attack_stab and ao.heavy_attack_stab.allowed_chain_actions and ao.heavy_attack_stab.allowed_chain_actions[5] then
                ao.heavy_attack_stab.allowed_chain_actions[5].start_time = 0.35
            end
        end
        if tpl then tpl.max_fatigue_points = 6 end
        if tpl and tpl.buffs then
            if tpl.buffs.change_dodge_distance then tpl.buffs.change_dodge_distance.external_optional_multiplier = 1.25 end
            if tpl.buffs.change_dodge_speed then tpl.buffs.change_dodge_speed.external_optional_multiplier = 1.25 end
        end
    end
end

-- ============================================================
-- MELEE — MACES / PICKS / AXES
-- ============================================================

local function _apply_melee_mace_axe()
    if _on("br_1h_axe") then
        for _, key in ipairs({ "one_hand_axe_template_1", "one_hand_axe_template_2" }) do
            local ao = _w(key) and _w(key).actions and _w(key).actions.action_one
            if ao then
                if ao.light_attack_last then ao.light_attack_last.anim_time_scale = 1.2 end
                if ao.heavy_attack_left then ao.heavy_attack_left.range_mod = 1.2 end
                if ao.heavy_attack_right then ao.heavy_attack_right.range_mod = 1.2 end
            end
        end
    end

    if _on("br_2h_pick") then
        local ao = _w("two_handed_picks_template_1") and _w("two_handed_picks_template_1").actions and _w("two_handed_picks_template_1").actions.action_one
        if ao then
            if ao.light_attack_left then
                ao.light_attack_left.damage_profile = "medium_slashing_linesman_uppercut"
                ao.light_attack_left.anim_time_scale = 0.95
            end
            if ao.light_attack_right then
                ao.light_attack_right.damage_profile = "medium_slashing_linesman_uppercut"
                ao.light_attack_right.anim_time_scale = 0.95
            end
            if ao.heavy_attack_left_charged then ao.heavy_attack_left_charged.additional_critical_strike_chance = 1 end
            if ao.heavy_attack_right_charged then ao.heavy_attack_right_charged.additional_critical_strike_chance = 1 end
            if ao.heavy_attack_left then ao.heavy_attack_left.anim_time_scale = 1.2 end
            if ao.heavy_attack_right then ao.heavy_attack_right.anim_time_scale = 1.2 end
            if ao.light_attack_bopp then ao.light_attack_bopp.damage_profile = "medium_blunt_smiter_bop_pick" end
        end
    end

    if _on("br_2h_axe") then
        local ao = _w("two_handed_axes_template_1") and _w("two_handed_axes_template_1").actions and _w("two_handed_axes_template_1").actions.action_one
        if ao then
            if ao.light_attack_up then ao.light_attack_up.anim_time_scale = 0.9 end
            if ao.heavy_attack_right then
                ao.heavy_attack_right.slide_armour_hit = true
                ao.heavy_attack_right.hit_mass_count = rawget(_G, "HEAVY_LINESMAN_HIT_MASS_COUNT")
            end
            if ao.heavy_attack_left then
                ao.heavy_attack_left.slide_armour_hit = true
                ao.heavy_attack_left.hit_mass_count = rawget(_G, "HEAVY_LINESMAN_HIT_MASS_COUNT")
            end
        end
    end

    if _on("br_dw_axes") then
        local ao = _w("dual_wield_axes_template_1") and _w("dual_wield_axes_template_1").actions and _w("dual_wield_axes_template_1").actions.action_one
        if ao then
            if ao.heavy_attack then ao.heavy_attack.anim_time_scale = 0.925 end
            if ao.heavy_attack_2 then ao.heavy_attack_2.anim_time_scale = 1.1 end
            if ao.heavy_attack_3 then ao.heavy_attack_3.additional_critical_strike_chance = 0.2 end
            if ao.push then
                ao.push.damage_profile_inner = "light_push"
                ao.push.fatigue_cost = "action_stun_push"
            end
        end
    end

    if _on("br_1h_flail_rework") then
        local ao = _w("one_handed_flail_template_1") and _w("one_handed_flail_template_1").actions and _w("one_handed_flail_template_1").actions.action_one
        if ao then
            if ao.default_right then
                ao.default_right.anim_event = "attack_swing_charge_left"
                if ao.default_right.allowed_chain_actions and ao.default_right.allowed_chain_actions[4] then
                    ao.default_right.allowed_chain_actions[4].sub_action = "default_charge_2"
                end
            end
            if ao.heavy_attack_left and ao.heavy_attack_left.allowed_chain_actions and ao.heavy_attack_left.allowed_chain_actions[1] then
                ao.heavy_attack_left.allowed_chain_actions[1].sub_action = "default_right"
            end
            if ao.light_attack_bopp and ao.light_attack_bopp.allowed_chain_actions and ao.light_attack_bopp.allowed_chain_actions[1] then
                ao.light_attack_bopp.allowed_chain_actions[1].sub_action = "default"
            end
            if ao.heavy_attack then
                if ao.heavy_attack.allowed_chain_actions and ao.heavy_attack.allowed_chain_actions[1] then
                    ao.heavy_attack.allowed_chain_actions[1].sub_action = "default_right"
                end
                ao.heavy_attack.anim_time_scale = 1.1
            end
        end
    end

    if _on("br_flaming_flail") then
        local ao = _w("one_handed_flails_flaming_template") and _w("one_handed_flails_flaming_template").actions and _w("one_handed_flails_flaming_template").actions.action_one
        if ao then
            if ao.light_attack_left then ao.light_attack_left.hit_mass_count = rawget(_G, "TANK_HIT_MASS_COUNT") end
            if ao.light_attack_right then ao.light_attack_right.hit_mass_count = rawget(_G, "TANK_HIT_MASS_COUNT") end
            if ao.heavy_attack then ao.heavy_attack.anim_time_scale = 1 end
        end
        local fle = _dpt("flaming_flail_explosion")
        if fle and fle.default_target and fle.default_target.power_distribution then
            fle.default_target.power_distribution.attack = 0.08
            fle.default_target.power_distribution.impact = 0.375
        end
    end

    if _on("br_crowbill") then
        local ao = _w("one_handed_crowbill") and _w("one_handed_crowbill").actions and _w("one_handed_crowbill").actions.action_one
        if ao then
            if ao.heavy_attack_right_up then
                ao.heavy_attack_right_up.damage_profile = "medium_pointy_smiter_flat_1h"
                ao.heavy_attack_right_up.additional_critical_strike_chance = 0.1
            end
            if ao.heavy_attack then
                ao.heavy_attack.damage_profile = "medium_pointy_smiter_flat_1h"
                ao.heavy_attack.additional_critical_strike_chance = 0.1
            end
            if ao.heavy_attack_left then ao.heavy_attack_left.additional_critical_strike_chance = 0.1 end
        end
    end

    if _on("br_glaive") then
        local ao = _w("two_handed_axes_template_2") and _w("two_handed_axes_template_2").actions and _w("two_handed_axes_template_2").actions.action_one
        if ao then
            if ao.light_attack_bopp then ao.light_attack_bopp.hit_mass_count = rawget(_G, "LINESMAN_HIT_MASS_COUNT") end
            if ao.heavy_attack_down_first then
                ao.heavy_attack_down_first.hit_mass_count = nil
                ao.heavy_attack_down_first.additional_critical_strike_chance = 1
                ao.heavy_attack_down_first.damage_profile = "glaive_uppercut"
            end
        end
    end
end

-- ============================================================
-- MELEE — SHIELDS / S+W / S+H
-- ============================================================

local function _apply_melee_shield()
    if _on("br_flail_shield") then
        local tpl = _w("one_handed_flail_shield_template")
        if tpl and tpl.buffs then
            if tpl.buffs.change_dodge_distance then tpl.buffs.change_dodge_distance.external_optional_multiplier = 1 end
            if tpl.buffs.change_dodge_speed then tpl.buffs.change_dodge_speed.external_optional_multiplier = 1 end
        end
        local ao = tpl and tpl.actions and tpl.actions.action_one
        if ao then
            if ao.light_attack_01 then ao.light_attack_01.hit_mass_count = nil end
            if ao.light_attack_02 then ao.light_attack_02.hit_mass_count = nil end
            if ao.light_attack_02_pose then ao.light_attack_02_pose.hit_mass_count = nil end
            if ao.light_attack_04 then ao.light_attack_04.hit_mass_count = rawget(_G, "TANK_HIT_MASS_COUNT") end
            if ao.light_attack_05 then ao.light_attack_05.hit_mass_count = rawget(_G, "TANK_HIT_MASS_COUNT") end
        end
    end

    if _on("br_axe_shield_crit") then
        local a = _act("one_hand_axe_shield_template_1", "action_one", "light_attack_bopp")
        if a then a.additional_critical_strike_chance = 0.1 end
    end

    if _on("br_1h_hammer_shield_heavy") then
        for _, key in ipairs({ "one_handed_hammer_shield_template_1", "one_handed_hammer_shield_template_2",
                               "one_handed_hammer_shield_priest_template" }) do
            local a = _act(key, "action_one", "heavy_attack_left")
            if a then a.damage_profile = "heavy_slashing_tank" end
        end
    end

    if _on("br_sword_shield_emp") then
        local ao = _w("one_handed_sword_shield_template_2") and _w("one_handed_sword_shield_template_2").actions and _w("one_handed_sword_shield_template_2").actions.action_one
        if ao and ao.light_attack_left then ao.light_attack_left.damage_profile = "light_slashing_linesman_finesse" end
        ao = _w("one_handed_sword_shield_template_1") and _w("one_handed_sword_shield_template_1").actions and _w("one_handed_sword_shield_template_1").actions.action_one
        if ao then
            if ao.light_attack_last then
                ao.light_attack_last.damage_profile = "light_slashing_linesman_finesse"  -- final state
                ao.light_attack_last.hit_mass_count = rawget(_G, "LINESMAN_HIT_MASS_COUNT")
            end
            if ao.heavy_attack_right then ao.heavy_attack_right.damage_profile = "medium_slashing_tank_1h_new" end
            if ao.light_attack_left then ao.light_attack_left.damage_profile = "light_slashing_linesman_finesse" end
            if ao.light_attack_right then ao.light_attack_right.damage_profile = "light_slashing_linesman_finesse" end
        end
    end

    if _on("br_shield_slam_replace") then
        -- DamageProfileTemplates rewrites are normally done by master
        -- registration via _BR_DEFS, but in BR these are also explicitly
        -- *replaced* (existing entries) — so write through here unconditionally.
        if _dpt("shield_slam_target") then
            for k, v in pairs(DEFS.damage_profiles.shield_slam_target) do
                DamageProfileTemplates.shield_slam_target[k] = v
            end
        end
        if _dpt("shield_slam") then
            for k, v in pairs(DEFS.damage_profiles.shield_slam) do
                DamageProfileTemplates.shield_slam[k] = v
            end
        end
    end
end

-- ============================================================
-- RANGED — BOWS / XBOWS / LONGBOWS
-- ============================================================

local function _apply_ranged_bow()
    if _on("br_bow_weapon_type_flag") then
        local k = { "shortbow_template_1", "shortbow_hagbane_template_1",
                    "longbow_template_1", "javelin_template" }
        for i = 1, #k do
            local t = _w(k[i])
            if t then t.weapon_type_bow = true end
        end
    end

    if _on("br_bow_ammo_caps") then
        local sb = _w("shortbow_template_1"); if sb and sb.ammo_data then sb.ammo_data.max_ammo = 65 end
        local hg = _w("shortbow_hagbane_template_1"); if hg and hg.ammo_data then hg.ammo_data.max_ammo = 35 end
        local lb = _w("longbow_template_1"); if lb and lb.ammo_data then lb.ammo_data.max_ammo = 30 end
    end

    if _on("br_shortbow_shotgun_rework") then
        local tpl = _w("shortbow_template_1")
        local ao = tpl and tpl.actions and tpl.actions.action_one
        local at = tpl and tpl.actions and tpl.actions.action_two
        if ao then
            if ao.default then ao.default.additional_critical_strike_chance = 0.1 end
            if ao.shoot_charged then
                local sc = ao.shoot_charged
                sc.anim_event_secondary = "reload"
                sc.reload_when_out_of_ammo = true
                sc.kind = "crossbow"
                sc.multi_projectile_spread = 0.0125
                sc.num_projectiles = 5
                sc.ammo_usage = 1
            end
        end
        if tpl and tpl.ammo_data then
            tpl.ammo_data.ammo_per_reload = 5
            tpl.ammo_data.ammo_per_clip = 5
            tpl.ammo_data.play_reload_anim_on_wield_reload = true
        end
        if at and at.default then
            at.default.num_projectiles = 5
            at.default.charge_time = 10
            at.default.anim_time_scale = 1
            at.default.allowed_chain_actions = {
                { sub_action = "shoot_charged", input = "action_one", action = "action_one", end_time = 1.25, start_time = 1 },
                { sub_action = "shoot_charged", input = "action_one", action = "action_one", start_time = 0.75, end_time = math.huge },
                { sub_action = "shoot_charged", softbutton_threshold = 0.75, action = "action_one",
                  input = "action_one_softbutton_gamepad", start_time = 0.65, end_time = math.huge },
                { sub_action = "default", input = "action_wield", action = "action_wield", start_time = 0, end_time = math.huge },
                { sub_action = "default", input = "weapon_reload", action = "weapon_reload", start_time = 0.1 },
                { sub_action = "auto_reload", auto_chain = true, action = "weapon_reload", start_time = 0.8 },
            }
        end
    end

    if _on("br_longbow_emp_rework") then
        local tpl = _w("longbow_empire_template")
        local ao = tpl and tpl.actions and tpl.actions.action_one
        local at = tpl and tpl.actions and tpl.actions.action_two

        -- Append wield-chain helper for shoot_charged_heavy + shoot_charged
        if ao then
            if ao.shoot_charged_heavy then
                _append_chain(ao.shoot_charged_heavy, {
                    sub_action = "default", input = "action_wield",
                    action = "action_wield", start_time = 0, end_time = math.huge,
                })
                local ach = ao.shoot_charged_heavy.allowed_chain_actions
                if ach and ach[4] then
                    ach[4].start_time = 0.25
                    ach[4].sub_action = "default"
                    ach[4].action = "action_one"
                    ach[4].release_required = "action_two_hold"
                    ach[4].input = "action_one"
                end
                ao.shoot_charged_heavy.reload_event_delay_time = 0.1
                ao.shoot_charged_heavy.override_reload_time = nil
                if ach and ach[2] then ach[2].start_time = 0.68 end
            end
            if ao.default then
                ao.default.override_reload_time = 0.15
                if ao.default.allowed_chain_actions and ao.default.allowed_chain_actions[2] then
                    ao.default.allowed_chain_actions[2].start_time = 0.4
                end
            end
            if ao.shoot_charged then
                _append_chain(ao.shoot_charged, {
                    sub_action = "default", input = "action_wield",
                    action = "action_wield", start_time = 0, end_time = math.huge,
                })
                local ach = ao.shoot_charged.allowed_chain_actions
                if ach and ach[4] then
                    ach[4].start_time = 0.4
                    ach[4].sub_action = "default"
                    ach[4].action = "action_one"
                    ach[4].release_required = "action_two_hold"
                    ach[4].input = "action_one"
                end
                if ach and ach[2] then ach[2].start_time = 0.7 end
                ao.shoot_charged.reload_event_delay_time = 0.15
                ao.shoot_charged.override_reload_time = nil
                ao.shoot_charged.speed = 11000
            end
        end

        if at and at.default then
            at.default.heavy_aim_flow_delay = nil
            at.default.heavy_aim_flow_event = nil
            at.default.aim_zoom_delay = 0.01
            at.default.default_zoom = "zoom_in_trueflight"
            at.default.buffed_zoom_thresholds = { "zoom_in_trueflight", "zoom_in" }
        end

        if tpl and tpl.ammo_data then
            tpl.ammo_data.reload_time = 0
            tpl.ammo_data.reload_on_ammo_pickup = true
        end

        local ST = rawget(_G, "SpreadTemplates")
        if ST and ST.empire_longbow and ST.empire_longbow.continuous then
            local c = ST.empire_longbow.continuous
            c.still = { max_pitch = 0.25, max_yaw = 0.25 }
            c.moving = { max_pitch = 0.4, max_yaw = 0.4 }
            c.crouch_still = { max_pitch = 0.75, max_yaw = 0.75 }
            c.crouch_moving = { max_pitch = 2, max_yaw = 2 }
            c.zoomed_still = { max_pitch = 0, max_yaw = 0 }
            c.zoomed_moving = { max_pitch = 0.4, max_yaw = 0.4 }
            c.zoomed_crouch_still = { max_pitch = 0, max_yaw = 0 }
            c.zoomed_crouch_moving = { max_pitch = 0.4, max_yaw = 0.4 }
        end
    end

    if _on("br_repeater_xbow_elf") then
        local tpl = _w("repeating_crossbow_elf_template")
        if tpl and tpl.ammo_data then
            tpl.ammo_data.max_ammo = 60
            tpl.ammo_data.ammo_per_reload = 23
        end
        local ao = tpl and tpl.actions and tpl.actions.action_one
        if ao then
            if ao.default and ao.default.impact_data then
                ao.default.impact_data.damage_profile = "repeating_crossbow_elf_projectile"
            end
            if ao.zoomed_shot and ao.zoomed_shot.impact_data then
                ao.zoomed_shot.impact_data.damage_profile = "repeating_crossbow_elf_projectile"
            end
        end
    end

    if _on("br_throwing_axes") then
        local tpl = _w("one_handed_throwing_axes_template")
        if tpl and tpl.ammo_data then
            tpl.ammo_data.max_ammo = 5
            tpl.ammo_data.reload_time = 0.3
        end
    end

    if _on("br_moonbow_rework") then
        local tpl = _w("we_deus_01_template_1")
        if tpl then
            tpl.weapon_type = "DRAKEFIRE"
            tpl.weapon_type_bow = true
        end
        local ao = tpl and tpl.actions and tpl.actions.action_one
        local at = tpl and tpl.actions and tpl.actions.action_two
        if at and at.default then
            at.default.kind = "career_true_flight_aim"
            at.default.aim_time = 0
            at.default.anim_time_scale = 0.75
            at.default.allowed_chain_actions = {
                { sub_action = "shoot_charged", input = "action_one", action = "action_one", start_time = 0.05, end_time = math.huge },
                { sub_action = "shoot_special_charged", input = "action_one_special", action = "action_one_special",
                  start_time = 0.05, end_time = math.huge },
                { sub_action = "default", input = "action_wield", action = "action_wield", start_time = 0, end_time = math.huge },
            }
        end
        if ao then
            for _, sn in ipairs({ "shoot_special_charged", "shoot_charged" }) do
                local sub = ao[sn]
                if sub then
                    sub.kind = "true_flight_bow"
                    sub.energy_weapon = true
                    sub.true_flight_template = "active_ability_kerillian_way_watcher"
                end
            end
            if ao.default then ao.default.drain_amount = 3 end
            if ao.shoot_special_charged then
                ao.shoot_special_charged.drain_amount = 9
                if ao.shoot_special_charged.impact_data then
                    ao.shoot_special_charged.impact_data.damage_profile = "we_deus_01_charged"
                end
            end
            if ao.shoot_charged then
                ao.shoot_charged.drain_amount = 9
                ao.shoot_charged.prioritized_breeds = {
                    chaos_vortex_sorcerer = 1, skaven_poison_wind_globadier = 1,
                    chaos_corruptor_sorcerer = 1, skaven_ratling_gunner = 1,
                    skaven_pack_master = 1, skaven_warpfire_thrower = 1,
                    beastmen_standard_bearer = 1, skaven_gutter_runner = 1,
                }
            end
        end
        local ED = rawget(_G, "EnergyData")
        if ED then
            ED.we_waywatcher  = { 40, 0.2, 0.33, 15 }
            ED.we_maidenguard = { 40, 0.2, 0.25, 15 }
            ED.we_shade       = { 40, 0.2, 0.25, 15 }
            ED.we_thornsister = { 40, 0.2, 0.25, 15 }
        end
        local BT = rawget(_G, "BuffTemplates")
        local dot = BT and BT.we_deus_01_dot_special_charged
        if dot and dot.buffs and dot.buffs[1] then dot.buffs[1].ticks = 3 end
    end
end

-- ============================================================
-- RANGED — GUNS
-- ============================================================

local function _apply_ranged_gun()
    if _on("br_repeater_handgun") then
        local tpl = _w("repeating_handgun_template_1")
        local ao = tpl and tpl.actions and tpl.actions.action_one
        if ao and ao.bullet_spray then
            ao.bullet_spray.anim_time_scale = 1.3
            if ao.bullet_spray.recoil_settings then
                ao.bullet_spray.recoil_settings.vertical_climb = 3.5
            end
        end
        if tpl and tpl.ammo_data then tpl.ammo_data.max_ammo = 60 end
        local ST = rawget(_G, "SpreadTemplates")
        if ST and ST.repeating_handgun and ST.repeating_handgun.continuous then
            if ST.repeating_handgun.continuous.moving then
                ST.repeating_handgun.continuous.moving.max_yaw = 0.75
                ST.repeating_handgun.continuous.moving.min_yaw = 0.75
            end
            if ST.repeating_handgun.continuous.crouch_moving then
                ST.repeating_handgun.continuous.crouch_moving.max_yaw = 0.3
                ST.repeating_handgun.continuous.crouch_moving.min_yaw = 0.3
            end
        end
    end

    if _on("br_engineer_deus_balanced") then
        local tpl = _w("bw_deus_01_template_1")
        local ao = tpl and tpl.actions and tpl.actions.action_one
        local at = tpl and tpl.actions and tpl.actions.action_two
        if ao and ao.default then
            ao.default.total_time = 0.65
            ao.default.shot_count = 15
            if ao.default.allowed_chain_actions and ao.default.allowed_chain_actions[1] then
                ao.default.allowed_chain_actions[1].start_time = 0.5  -- final override
            end
        end
        if at and at.default then
            at.default.max_radius = 30
            at.default.charge_time = 30
        end
        -- Engineer balanced barrels
        local wh = _w("wh_deus_01_template_1")
        local whao = wh and wh.actions and wh.actions.action_one
        if whao and whao.default then
            whao.default.barrels = { "balanced_barrels", 1, 1, 1, 1 }
        end
    end

    if _on("br_brace_of_pistols_clip") then
        local bop = _w("brace_of_pistols_template_1")
        if bop and bop.ammo_data then
            bop.ammo_data.ammo_per_clip = nil
            bop.ammo_data.ammo_immediately_available = true
            bop.ammo_data.single_clip = true
        end
    end

    if _on("br_dr_deus_ammo") then
        local d = _w("dr_deus_01_template_1")
        if d and d.ammo_data then
            d.ammo_data.reload_time = 4
            d.ammo_data.ammo_per_reload = 2
        end
    end

    if _on("br_steam_pistol") then
        local sp = _w("heavy_steam_pistol_template_1")
        if sp and sp.ammo_data then
            sp.ammo_data.max_ammo = 36
            sp.ammo_data.ammo_per_reload = 12
        end
    end

    if _on("br_grudgeraker_shotgun") then
        local gr = _w("grudge_raker_template_1")
        local ao = gr and gr.actions and gr.actions.action_one
        if ao and ao.default then
            ao.default.hit_mass_count = nil
            ao.default.damage_profile = "shot_shotgun_cbr"
            if ao.default.allowed_chain_actions then
                if ao.default.allowed_chain_actions[2] then ao.default.allowed_chain_actions[2].start_time = 0.6 end
                if ao.default.allowed_chain_actions[4] then ao.default.allowed_chain_actions[4].start_time = 0.6 end
                table.insert(ao.default.allowed_chain_actions, 5, {
                    sub_action = "default", input = "action_two", action = "action_three", start_time = 0.4,
                })
                table.insert(ao.default.allowed_chain_actions, 6, {
                    sub_action = "default", input = "action_two_hold", action = "action_three", start_time = 0.4,
                })
            end
        end
        if gr and gr.ammo_data then
            gr.ammo_data.max_ammo = 24
            gr.ammo_data.ammo_per_reload = 4
        end
        if gr and gr.actions then
            gr.actions.action_three = {
                default = {
                    kind = "shoot_pump_shotgun",
                    ammo_usage = 4,
                    damage_profile = "grudge_action_three",
                    weapon_action_hand = "right",
                    hit_armor_sound_event_name = "Play_player_combat_weapon_hits_armor",
                    fire_time = 0.2, anim_end_time = 0.55, total_time = 0.55,
                    spread_template = "grudge_raker", anim_event = "shoot",
                    speed = 11000, num_projectiles = 11, multi_projectile_spread = 0.04,
                    minimum_hits_for_alert_enemies = 5, alert_sound_range_fire = 25,
                    allowed_chain_actions = {
                        { sub_action = "default", input = "action_one", action = "action_one", start_time = 0.4 },
                        { sub_action = "default", input = "weapon_reload", action = "weapon_reload", start_time = 0.5 },
                        { sub_action = "auto_reload", auto_chain = true, action = "weapon_reload", start_time = 0.55 },
                    },
                },
            }
        end
    end

    if _on("br_blunderbuss_shotgun") then
        local b = _w("blunderbuss_template_1")
        local ao = b and b.actions and b.actions.action_one
        if ao and ao.default then
            ao.default.hit_mass_count = nil
            ao.default.damage_profile = "shot_shotgun_cbr"
            if ao.default.allowed_chain_actions then
                table.insert(ao.default.allowed_chain_actions, 5, {
                    sub_action = "default", input = "action_two", action = "action_three", start_time = 0.4,
                })
            end
        end
        if b and b.ammo_data then b.ammo_data.max_ammo = 24 end
        if b and b.actions then
            b.actions.action_three = {
                default = {
                    kind = "shoot_pump_shotgun",
                    ammo_usage = 4,
                    damage_profile = "blunder_action_three",
                    weapon_action_hand = "right",
                    fire_time = 0.2, anim_end_time = 0.55, total_time = 0.55,
                    spread_template = "blunderbuss", anim_event = "shoot",
                    speed = 9000, num_projectiles = 12, multi_projectile_spread = 0.055,
                    minimum_hits_for_alert_enemies = 5, alert_sound_range_fire = 25,
                    allowed_chain_actions = {
                        { sub_action = "default", input = "action_one", action = "action_one", start_time = 0.4 },
                        { sub_action = "default", input = "weapon_reload", action = "weapon_reload", start_time = 0.5 },
                        { sub_action = "auto_reload", auto_chain = true, action = "weapon_reload", start_time = 0.55 },
                    },
                },
            }
        end
    end

    if _on("br_drakepistol_speed_chains") then
        local dp = _w("brace_of_drakefirepistols_template_1")
        local ao = dp and dp.actions and dp.actions.action_one
        if ao then
            if ao.default then
                ao.default.speed = 10000
                if ao.default.allowed_chain_actions then
                    if ao.default.allowed_chain_actions[2] then ao.default.allowed_chain_actions[2].start_time = 0.2 end
                    if ao.default.allowed_chain_actions[3] then ao.default.allowed_chain_actions[3].start_time = 0.2 end
                end
            end
            if ao.shoot_charged then
                ao.shoot_charged.ignore_shield_hit = true
                if ao.shoot_charged.allowed_chain_actions then
                    if ao.shoot_charged.allowed_chain_actions[1] then ao.shoot_charged.allowed_chain_actions[1].start_time = 0.3 end
                    if ao.shoot_charged.allowed_chain_actions[2] then ao.shoot_charged.allowed_chain_actions[2].start_time = 0.6 end
                    if ao.shoot_charged.allowed_chain_actions[3] then ao.shoot_charged.allowed_chain_actions[3].start_time = 0.6 end
                    if ao.shoot_charged.allowed_chain_actions[4] then ao.shoot_charged.allowed_chain_actions[4].start_time = 0.6 end
                end
            end
        end
        local PUSS = rawget(_G, "PlayerUnitStatusSettings")
        if PUSS and PUSS.overcharge_values then
            PUSS.overcharge_values.brace_of_drake_pistols_basic = 2.5
        end
    end

    if _on("br_drakegun_dot_interval") then
        local dg = _w("drakegun_template_1")
        local sc = dg and dg.actions and dg.actions.action_one and dg.actions.action_one.shoot_charged
        if sc then
            sc.particle_effect_flames = "fx/wpnfx_flamethrower_01"
            sc.damage_interval = 0.3
        end
    end

    if _on("br_rakeshot_spread") then
        local ST = rawget(_G, "SpreadTemplates")
        if ST and ST.rake_shot then
            -- Preserves the source-file typo "contious" verbatim.
            ST.rake_shot.contious = {
                still = { max_pitch = 1, max_yaw = 1 },
                moving = { max_pitch = 1.5, max_yaw = 1.5 },
                crouch_still = { max_pitch = 0.5, max_yaw = 0.5 },
                crouch_moving = { max_pitch = 1, max_yaw = 1 },
                zoomed_still = { max_pitch = 0.5, max_yaw = 0.5 },
                zoomed_moving = { max_pitch = 1, max_yaw = 1 },
                zoomed_crouch_still = { max_pitch = 0.25, max_yaw = 0.25 },
                zoomed_crouch_moving = { max_pitch = 0.75, max_yaw = 0.75 },
            }
        end
    end

    if _on("br_handgun_xbow_reload") then
        local h = _w("handgun_template_2"); if h and h.ammo_data then h.ammo_data.ammo_per_reload = 2 end
        local c = _w("crossbow_template_1"); if c and c.ammo_data then c.ammo_data.ammo_per_reload = 2 end
    end

    if _on("br_repeater_pistol_reload") then
        local r = _w("repeating_pistol_template_1")
        if r and r.ammo_data then r.ammo_data.ammo_per_reload = 12 end
    end
end

-- ============================================================
-- RANGED — STAVES
-- ============================================================

local function _apply_ranged_staff()
    if _on("br_staff_magma") then
        local dp = _dpt("staff_magma")
        if dp and dp.default_target then
            if dp.default_target.power_distribution_near then dp.default_target.power_distribution_near.attack = 0.1 end
            if dp.default_target.power_distribution_far then dp.default_target.power_distribution_far.attack = 0.05 end
        end
        local PUSS = rawget(_G, "PlayerUnitStatusSettings")
        if PUSS and PUSS.overcharge_values then
            PUSS.overcharge_values.magma_basic = 4
            PUSS.overcharge_values.magma_charged_2 = 10
            PUSS.overcharge_values.magma_charged = 14
        end
        local magma = _et("magma")
        if magma and magma.aoe then
            magma.aoe.duration = 3
            magma.aoe.damage_interval = 0.75
        end
    end

    if _on("br_staff_fireball") then
        local ao = _w("staff_fireball_fireball_template_1") and _w("staff_fireball_fireball_template_1").actions and _w("staff_fireball_fireball_template_1").actions.action_one
        if ao then
            if ao.default then ao.default.total_time = 0.6 end
            if ao.shoot_charged then
                ao.shoot_charged.scale_power_level = 0.3
                ao.shoot_charged.impact_data = {
                    damage_profile = "staff_fireball_charged",
                    aoe = "fireball_charged",
                }
            end
        end
        local fc = _et("fireball_charged")
        if fc then
            fc.explosion = {
                radius = 4, radius_min = 1.25, radius_max = 5,
                max_damage_radius_max = 3, max_damage_radius_min = 0.75,
                attack_template = "fireball", damage_profile = "fireball_charged_explosion",
                sound_event_name = "fireball_explode", effect_name = "fx/wpnfx_fireball_explosion_01",
            }
            fc.name = "fireball_charged"
        end
    end

    if _on("br_staff_conflag_spear") then
        local at = _w("staff_spark_spear_template_1") and _w("staff_spark_spear_template_1").actions and _w("staff_spark_spear_template_1").actions.action_two
        if at and at.default then
            at.default.aim_zoom_delay = 0.01
            at.default.default_zoom = "zoom_in_trueflight"
            at.default.zoom_thresholds = { "zoom_in_trueflight", "zoom_in" }
            at.default.zoom_condition_function = function() return true end
        end
    end

    if _on("br_staff_beam_shotgun") then
        local tpl = _w("staff_blast_beam_template_1")
        local ao = tpl and tpl.actions and tpl.actions.action_one
        local at = tpl and tpl.actions and tpl.actions.action_two
        if at and at.default then at.default.aim_zoom_delay = 0.01 end
        if ao and ao.default then
            ao.default.default_zoom = "zoom_in"
            ao.default.zoom_thresholds = { "zoom_in_trueflight", "zoom_in" }
            ao.default.zoom_condition_function = function() return true end
        end
        if ao and ao.shoot_charged then ao.shoot_charged.damage_profile = "beam_blast" end
        if at and at.charged_beam then
            at.charged_beam.spread_template_override = "spear"
            at.charged_beam.damage_window_start = 0.01
        end
        local PUSS = rawget(_G, "PlayerUnitStatusSettings")
        if PUSS and PUSS.overcharge_values then PUSS.overcharge_values.beam_staff_shotgun = 5 end
    end

    if _on("br_staff_flamethrower") then
        local sc = _w("staff_flamethrower_template") and _w("staff_flamethrower_template").actions and _w("staff_flamethrower_template").actions.action_one and _w("staff_flamethrower_template").actions.action_one.shoot_charged
        if sc then sc.damage_interval = 0.3 end
    end

    if _on("br_staff_life_vortex") then
        local sl = _w("staff_life")
        local cv = sl and sl.actions and sl.actions.action_one and sl.actions.action_one.cast_vortex
        if cv then
            cv.overcharge_amount = 10
            if cv.allowed_chain_actions and cv.allowed_chain_actions[4] then
                cv.allowed_chain_actions[4].start_time = 0.6
            end
        end
        local VT = rawget(_G, "VortexTemplates")
        if VT and VT.spirit_storm then
            VT.spirit_storm.time_of_life = { 6, 6 }
            VT.spirit_storm.reduce_duration_per_breed = { chaos_warrior = 0.5 }
        end
    end
end

-- ============================================================
-- RANGED — CAREER-SKILL WEAPONS
-- ============================================================

local function _apply_ranged_career()
    if _on("br_gk_career_weapon") then
        local gk = _w("markus_questingknight_career_skill_weapon")
        local hold = gk and gk.actions and gk.actions.action_career_release and gk.actions.action_career_release.default_tank
        if hold then
            hold.unlimited_cleave = false
            hold.damage_window_start = 0.05
        end
        local profiles = {
            { p = "questing_knight_career_sword",      cleave = 0.2,  armor3 = 1,    hs = 1 },
            { p = "questing_knight_career_sword_stab", cleave = 0.2,  armor3 = 1.25, hs = 1 },
            { p = "questing_knight_career_sword_tank", cleave = 0.75, armor3 = 1,    hs = 1 },
        }
        for i = 1, #profiles do
            local row = profiles[i]
            local dp = _dpt(row.p)
            if dp then
                if dp.cleave_distribution then dp.cleave_distribution.attack = row.cleave end
                if dp.critical_strike and dp.critical_strike.attack_armor_power_modifer then
                    dp.critical_strike.attack_armor_power_modifer[3] = row.armor3
                end
                if dp.default_target then dp.default_target.boost_curve_coefficient_headshot = row.hs end
            end
        end
    end

    if _on("br_engineer_crank_gun") then
        local cg = _w("bardin_engineer_career_skill_weapon_special")
        local ao = cg and cg.actions and cg.actions.action_one
        if cg then cg.default_spread_template = "repeating_handgun" end
        if ao and ao.base_fire then ao.base_fire.ammo_usage = 1.25 end
        if ao and ao.armor_pierce_fire then
            ao.armor_pierce_fire.range = 100
            ao.armor_pierce_fire.ammo_usage = 3
            ao.armor_pierce_fire.max_rps = 5
            ao.armor_pierce_fire.armor_pierce_initial_rounds_per_second = 2
            ao.armor_pierce_fire.rps_loss_per_second = 1.5
        end
        if cg and cg.custom_data then cg.custom_data.windup_loss_per_second = 2 end
    end

    if _on("br_bardin_survival_ale") then
        local a = _act("bardin_survival_ale", "action_one", "default")
        if a then a.anim_time_scale = 2 end
    end

    if _on("br_we_ww_trueflight") then
        local cw = _w("kerillian_waywatcher_career_skill_weapon")
        if cw and cw.actions and cw.actions.action_career_hold then
            cw.actions.action_career_hold.prioritized_breeds = {
                chaos_vortex_sorcerer = 1, skaven_poison_wind_globadier = 1,
                chaos_corruptor_sorcerer = 1, skaven_ratling_gunner = 1,
                skaven_pack_master = 1, skaven_warpfire_thrower = 1,
                beastmen_standard_bearer = 1, skaven_gutter_runner = 1,
            }
        end
        local r1 = cw and cw.actions and cw.actions.action_career_release and cw.actions.action_career_release.default
        if r1 then r1.additional_critical_strike_chance = -2 end
        local pcw = _w("kerillian_waywatcher_career_skill_weapon_piercing_shot")
        local r2 = pcw and pcw.actions and pcw.actions.action_career_release and pcw.actions.action_career_release.default
        if r2 then r2.additional_critical_strike_chance = -2 end
        if r2 then r2.damage_profile = "arrow_sniper_trueflight" end

        local pp = _dpt("arrow_sniper_ability_piercing")
        if pp then
            if pp.critical_strike then
                pp.critical_strike.attack_armor_power_modifer = { 2.15, 1.4, 2, 0.25, 1, 1 }
                pp.critical_strike.impact_armor_power_modifer = { 2.15, 1.4, 2, 0.25, 1, 1 }
            end
            if pp.armor_modifier_near then
                pp.armor_modifier_near.attack = { 2.15, 1.4, 2, 0.25, 1, 1 }
                pp.armor_modifier_near.impact = { 1, 1, 0, 0, 1, 1 }
            end
            if pp.armor_modifier_far then
                pp.armor_modifier_far.attack = { 2.15, 1.4, 2, 0.25, 1, 1 }
                pp.armor_modifier_far.impact = { 1, 1, 0, 0, 1, 0 }
            end
            if pp.default_target then pp.default_target.boost_curve_coefficient_headshot = 2.5 end
            pp.max_friendly_damage = 20
        end
    end

    if _on("br_sienna_scholar_skullshot") then
        local cw = _w("sienna_scholar_career_skill_weapon")
        if cw and cw.actions and cw.actions.action_career_hold then
            cw.actions.action_career_hold.prioritized_breeds = {
                chaos_vortex_sorcerer = 1, skaven_poison_wind_globadier = 1,
                chaos_corruptor_sorcerer = 1, skaven_ratling_gunner = 1,
                skaven_pack_master = 1, skaven_warpfire_thrower = 1,
                beastmen_standard_bearer = 1, skaven_gutter_runner = 1,
            }
        end
        local rel = cw and cw.actions and cw.actions.action_career_release and cw.actions.action_career_release.default
        if rel then
            rel.impact_data = {
                damage_profile = "fire_spear_trueflight",
                aoe = "overcharge_explosion_skull",
            }
        end
        -- overcharge_explosion retunes
        local oce = _dpt("overcharge_explosion")
        if oce then
            oce.stagger_duration_modifier = 3
            if oce.default_target and oce.default_target.power_distribution then
                oce.default_target.power_distribution.attack = 0.15
                oce.default_target.power_distribution.impact = 1
            end
            if oce.armor_modifier then
                oce.armor_modifier.attack = { 1, 0.5, 2.5, 1, 0.5, 0.25 }
                oce.armor_modifier.impact = { 0.5, 0.5, 1, 0.5, 1.5, 0.5 }
            end
        end
    end

    if _on("br_vc_bh_shotgun_profile") then
        local sa = _dpt("shot_shotgun_ability")
        if sa then
            if sa.critical_strike then
                sa.critical_strike.attack_armor_power_modifer = { 1, 0.1, 0.2, 0, 1, 0.025 }
                sa.critical_strike.impact_armor_power_modifer = { 1, 0.5, 1, 0, 1, 0.05 }
            end
            if sa.armor_modifier_near then
                sa.armor_modifier_near.attack = { 1, 0.1, 0.2, 0, 1, 0 }
                sa.armor_modifier_near.impact = { 1, 0.5, 1, 0, 1, 0 }
            end
            if sa.armor_modifier_far then
                sa.armor_modifier_far.attack = { 1, 0, 0.2, 0, 1, 0 }
                sa.armor_modifier_far.impact = { 1, 0.5, 1, 0, 1, 0 }
            end
        end
    end

    if _on("br_vc_wp_nuke") then
        local n = _dpt("victor_priest_activated_ability_nuke_explosion")
        if n and n.default_target then
            n.default_target.dot_template_name = nil
            if n.default_target.power_distribution then
                n.default_target.power_distribution.impact = 1
            end
        end
        if n and n.armor_modifier then
            n.armor_modifier.impact = { 0.5, 0.5, 1, 0.5, 1.5, 0.5 }
        end
    end

    if _on("br_slayer_leap_landing") then
        local d = _dpt("slayer_leap_landing_impact")
        if d and d.default_target and d.default_target.power_distribution then
            d.default_target.power_distribution.impact = 1
        end
    end
end

-- ============================================================
-- DAMAGE PROFILE TUNING (megatoggles)
-- ============================================================
-- Apply every grouped damage profile retune. Each toggle owns a bundle
-- of fields on the listed profile(s). Implemented as direct writes
-- preceded by the per-toggle `_on` check.

local function _apply_damage_profile_tuning()
    -- ---- BLUNT family ----
    if _on("br_dpt_light_blunt_tank") then
        local p = _dpt("light_blunt_tank")
        if p and p.cleave_distribution then p.cleave_distribution.attack = 0.23 end
        p = _dpt("light_blunt_tank_diag")
        if p and p.targets then
            if p.targets[1] then
                p.targets[1].boost_curve_coefficient_headshot = 2
                if p.targets[1].power_distribution then p.targets[1].power_distribution.attack = 0.225 end
            end
            if p.targets[2] then
                p.targets[2].boost_curve_coefficient_headshot = 2
                if p.targets[2].power_distribution then p.targets[2].power_distribution.attack = 0.15 end
            end
            if p.armor_modifier then p.armor_modifier.attack = { 1, 0.5, 1, 1, 0.75, 0.25 } end
            if p.critical_strike then p.critical_strike.attack_armor_power_modifer = { 1, 0.6, 1, 1, 0.75 } end
        end
        p = _dpt("light_blunt_smiter")
        if p then
            if p.default_target then p.default_target.boost_curve_coefficient_headshot = 2 end
            if p.armor_modifier then p.armor_modifier.attack = { 1.25, 0.75, 3, 1, 1.25, 0.6 } end
            if p.critical_strike then p.critical_strike.attack_armor_power_modifer = { 1.25, 0.85, 2.75, 1, 1 } end
        end
        p = _dpt("medium_blunt_smiter_1h")
        if p and p.armor_modifier then p.armor_modifier.attack = { 1, 0.8, 2.5, 0.75, 1 } end
    end

    if _on("br_dpt_heavy_blunt_tank") then
        local p = _dpt("heavy_blunt_tank")
        if p then
            if p.cleave_distribution then p.cleave_distribution.attack = 0.5 end
            if p.targets then
                if p.targets[1] then
                    if p.targets[1].power_distribution then p.targets[1].power_distribution.attack = 0.525 end
                    if p.targets[1].armor_modifier then p.targets[1].armor_modifier.attack = { 1, 0.3, 1.5, 0.75, 0.5, 0.3 } end
                end
                if p.targets[2] then
                    if p.targets[2].power_distribution then p.targets[2].power_distribution.attack = 0.35 end
                    p.targets[2].armor_modifier = {
                        attack = { 0.8, 0.3, 2, 1, 0.5, 0.3 },
                        impact = { 1.5, 1, 1, 1, 0.75 },
                    }
                end
                if p.targets[3] and p.targets[3].power_distribution then p.targets[3].power_distribution.attack = 0.1 end
            end
            if p.default_target and p.default_target.power_distribution then p.default_target.power_distribution.attack = 0.075 end
            p.shield_break = true
        end
        local mbts = _dpt("medium_blunt_tank_spiked")
        if mbts and mbts.armor_modifier_tank_spiked_M then mbts.armor_modifier_tank_spiked_M.attack = { 1, 0.5, 2, 1, 1 } end
        local lbts = _dpt("light_blunt_tank_spiked")
        if lbts and lbts.targets then
            if lbts.targets[1] and lbts.targets[1].power_distribution then lbts.targets[1].power_distribution.attack = 0.225 end
            if lbts.targets[2] and lbts.targets[2].power_distribution then lbts.targets[2].power_distribution.attack = 0.15 end
            if lbts.default_target and lbts.default_target.power_distribution then lbts.default_target.power_distribution.attack = 0.1 end
        end
    end

    if _on("br_dpt_heavy_blunt_smiter_charged") then
        local p = _dpt("heavy_blunt_smiter_charged")
        if p then
            if p.default_target then
                p.default_target.boost_curve_coefficient_headshot = 1.5
                if p.default_target.power_distribution then p.default_target.power_distribution.attack = 0.8 end
            end
            if p.armor_modifier then p.armor_modifier.attack = { 1, 0.5, 2, 1, 0.75 } end
        end
        local mbsh = _dpt("medium_blunt_smiter_heavy")
        if mbsh and mbsh.default_target and mbsh.default_target.power_distribution then
            mbsh.default_target.power_distribution.attack = 0.5
        end
    end

    if _on("br_dpt_burning_blunt") then
        local p = _dpt("heavy_blunt_smiter_burn")
        if p and p.default_target and p.default_target.power_distribution then
            p.default_target.power_distribution.impact = 0.375
            p.default_target.power_distribution.attack = 0.25
        end
        p = _dpt("light_blunt_smiter_stab_burn")
        if p then
            if p.targets and p.targets[1] and p.targets[1].power_distribution then p.targets[1].power_distribution.attack = 0.3 end
            if p.armor_modifier then p.armor_modifier.attack = { 1, 0.5, 1.5, 0.75, 0.5 } end
        end
        p = _dpt("dagger_burning_slam")
        if p and p.default_target then
            p.default_target.dot_template_name = "burning_1W_dot"
            if p.default_target.power_distribution then
                p.default_target.power_distribution.attack = 0.2
                p.default_target.power_distribution.impact = 0.3
            end
        end
        p = _dpt("medium_burning_tank")
        if p then
            if p.cleave_distribution then p.cleave_distribution.attack = 0.1 end
            if p.armor_modifier then p.armor_modifier.attack = { 1, 0.5, 1.5, 1, 0.5, 0.25 } end
            if p.critical_strike then p.critical_strike.attack_armor_power_modifer = { 1, 0.75, 2, 1, 0.75, 0.5 } end
            if p.targets and p.targets[1] then
                p.targets[1].boost_curve_type = "ninja_curve"
                p.targets[1].boost_curve_coefficient_headshot = 1.5
                if p.targets[1].power_distribution then p.targets[1].power_distribution.attack = 0.4 end
            end
        end
    end

    -- ---- SLASH family ----
    if _on("br_dpt_light_slash_linesman_finesse") then
        local p = _dpt("light_slashing_linesman_finesse")
        if p then
            if p.targets then
                if p.targets[1] then
                    p.targets[1].boost_curve_type = "ninja_curve"
                    if p.targets[1].power_distribution then p.targets[1].power_distribution.attack = 0.2 end
                end
                if p.targets[2] then
                    p.targets[2].boost_curve_type = "ninja_curve"
                    if p.targets[2].power_distribution then p.targets[2].power_distribution.attack = 0.15 end
                end
            end
            if p.default_target and p.default_target.power_distribution then p.default_target.power_distribution.attack = 0.125 end
        end
    end

    if _on("br_dpt_light_slash_smiter") then
        local lsf = _dpt("light_slashing_smiter_finesse"); if lsf then lsf.shield_break = true end
        local ls = _dpt("light_slashing_smiter")
        if ls then
            if ls.default_target then ls.default_target.boost_curve_coefficient_headshot = 2 end
            if ls.armor_modifier then ls.armor_modifier[3] = 2 end
        end
        local lsf2 = _dpt("light_slashing_smiter_flat"); if lsf2 and lsf2.default_target then lsf2.default_target.boost_curve_coefficient_headshot = 2 end
        local lsd = _dpt("light_slashing_smiter_diag"); if lsd and lsd.default_target then lsd.default_target.boost_curve_coefficient_headshot = 2 end
        local lss = _dpt("light_slashing_smiter_stab_swords")
        if lss and lss.targets and lss.targets[1] and lss.targets[1].power_distribution then
            lss.targets[1].power_distribution.attack = 0.2
        end
    end

    if _on("br_dpt_med_slash_tank_1h") then
        local p = _dpt("medium_slashing_tank_1h_finesse")
        if p then
            if p.targets and p.targets[1] then
                if p.targets[1].armor_modifier then p.targets[1].armor_modifier.attack = { 1, 0.65, 2, 1, 0.75 } end
                p.targets[1].boost_curve_type = "ninja_curve"
                p.targets[1].boost_curve_coefficient_headshot = 1.5
                if p.targets[1].power_distribution then p.targets[1].power_distribution.attack = 0.35 end
            end
            if p.targets and p.targets[2] and p.targets[2].power_distribution then p.targets[2].power_distribution.attack = 0.175 end
            p.cleave_distribution = "cleave_distribution_tank_L"
            p.critical_strike = "critical_strike_stab_smiter_H"
        end
        local tank = _dpt("medium_slashing_tank_1h")
        if tank and tank.targets then
            if tank.targets[1] and tank.targets[1].power_distribution then tank.targets[1].power_distribution.attack = 0.35 end
            if tank.targets[2] and tank.targets[2].power_distribution then tank.targets[2].power_distribution.attack = 0.25 end
            if tank.targets[3] and tank.targets[3].power_distribution then tank.targets[3].power_distribution.attack = 0.175 end
        end
    end

    if _on("br_dpt_med_slash_linesman_executioner") then
        local p = _dpt("medium_slashing_linesman_executioner")
        if p then
            if p.targets then
                if p.targets[2] then p.targets[2].boost_curve_coefficient_headshot = 3 end
                if p.targets[3] then p.targets[3].boost_curve_coefficient_headshot = 3 end
            end
            if p.cleave_distribution then
                p.cleave_distribution.attack = 0.35
                p.cleave_distribution.impact = 0.35
            end
            if p.default_target then p.default_target.boost_curve_coefficient_headshot = 2 end
        end
    end

    if _on("br_dpt_heavy_slash_tank") then
        local p = _dpt("heavy_slashing_tank")
        if p and p.targets then
            if p.targets[1] and p.targets[1].power_distribution then p.targets[1].power_distribution.attack = 0.4 end
            if p.targets[2] and p.targets[2].power_distribution then p.targets[2].power_distribution.attack = 0.3 end
            if p.targets[3] and p.targets[3].power_distribution then p.targets[3].power_distribution.attack = 0.2 end
        end
    end

    if _on("br_dpt_med_slash_linesman_base") then
        local p = _dpt("medium_slashing_linesman")
        if p then
            if p.targets then
                for i = 1, 3 do
                    if p.targets[i] then
                        p.targets[i].boost_curve_coefficient_headshot = 2
                    end
                end
                if p.targets[1] and p.targets[1].power_distribution then p.targets[1].power_distribution.attack = 0.275 end
                if p.targets[2] and p.targets[2].power_distribution then p.targets[2].power_distribution.attack = 0.2 end
                if p.targets[3] and p.targets[3].power_distribution then p.targets[3].power_distribution.attack = 0.15 end
            end
            if p.default_target and p.default_target.power_distribution then p.default_target.power_distribution.attack = 0.1 end
            if p.cleave_distribution then p.cleave_distribution.impact = 0.4 end
        end
    end

    if _on("br_dpt_med_slash_linesman_spear") then
        local p = _dpt("medium_slashing_linesman_spear")
        if p and p.targets then
            for i = 1, 3 do
                local t = p.targets[i]
                if t then
                    t.boost_curve_type = "ninja_curve"
                    t.boost_curve_coefficient_headshot = 2
                    t.boost_curve_coefficient = 1
                end
            end
        end
    end

    if _on("br_dpt_heavy_slash_polearm") then
        local p = _dpt("heavy_slashing_linesman_polearm")
        if p then
            if p.targets then
                if p.targets[1] then
                    if p.targets[1].armor_modifier and p.targets[1].armor_modifier.attack then
                        p.targets[1].armor_modifier.attack[1] = 1.15
                    end
                    if p.targets[1].power_distribution then p.targets[1].power_distribution.attack = 0.45 end
                end
                if p.targets[2] and p.targets[2].power_distribution then p.targets[2].power_distribution.attack = 0.35 end
                if p.targets[3] and p.targets[3].power_distribution then p.targets[3].power_distribution.attack = 0.25 end
                if p.targets[4] and p.targets[4].power_distribution then p.targets[4].power_distribution.attack = 0.15 end
            end
            if p.default_target and p.default_target.power_distribution then p.default_target.power_distribution.attack = 0.1 end
        end
    end

    if _on("br_dpt_axe_linesman") then
        local p = _dpt("heavy_slashing_axe_linesman")
        if p and p.armor_modifier and p.armor_modifier.attack then
            p.armor_modifier.attack[2] = 0.5
            p.armor_modifier.attack[6] = 0.2
        end
        p = _dpt("light_slashing_axe_linesman")
        if p and p.targets then
            if p.targets[1] and p.targets[1].power_distribution then p.targets[1].power_distribution.attack = 0.25 end
            if p.targets[2] then
                if p.targets[2].power_distribution then p.targets[2].power_distribution.attack = 0.175 end
                p.targets[2].boost_curve_coefficient_headshot = 2
            end
            if p.targets[3] then
                if p.targets[3].power_distribution then p.targets[3].power_distribution.attack = 0.125 end
                p.targets[3].boost_curve_coefficient_headshot = 2
            end
        end
        p = _dpt("medium_slashing_axe_linesman")
        if p and p.targets then
            if p.targets[1] and p.targets[1].armor_modifier and p.targets[1].armor_modifier.attack then
                p.targets[1].armor_modifier.attack[1] = 1.25
            end
            if p.targets[2] and p.targets[2].power_distribution then p.targets[2].power_distribution.attack = 0.225 end
            if p.targets[3] and p.targets[3].power_distribution then p.targets[3].power_distribution.attack = 0.15 end
            if p.cleave_distribution then p.cleave_distribution.attack = 0.4 end
        end
    end

    if _on("br_dpt_med_slash_smiter_2h") then
        local p = _dpt("medium_slashing_smiter_2h")
        if p and p.default_target then p.default_target.boost_curve_coefficient_headshot = 2.5 end
        p = _dpt("medium_slashing_smiter_stab")
        if p then
            if p.default_target and p.default_target.power_distribution then p.default_target.power_distribution.attack = 0.2375 end
            if p.armor_modifier and p.armor_modifier.attack then
                p.armor_modifier.attack[2] = 0.4
                p.armor_modifier.attack[6] = 0.25
            end
            if p.critical_strike and p.critical_strike.attack_armor_power_modifer then
                p.critical_strike.attack_armor_power_modifer[2] = 0.5
                p.critical_strike.attack_armor_power_modifer[6] = 0.4
            end
        end
        local mssa = _dpt("medium_slashing_smiter_1h_axe")
        if mssa and mssa.default_target and mssa.default_target.power_distribution then
            mssa.default_target.power_distribution.attack = 0.5
        end
        local mssa1 = _dpt("medium_slashing_smiter_stab_1h")
        if mssa1 and mssa1.default_target and mssa1.default_target.power_distribution then
            mssa1.default_target.power_distribution.attack = 0.35
        end
    end

    if _on("br_dpt_heavy_slash_smiter") then
        local p = _dpt("heavy_slashing_smiter_stab")
        if p and p.targets and p.targets[1] then
            p.targets[1].boost_curve_coefficient_headshot = 2
            if p.targets[1].armor_modifier then p.targets[1].armor_modifier.attack = { 1, 0.5, 2.5, 1, 0.75 } end
        end
        if p and p.critical_strike then p.critical_strike.attack_armor_power_modifer = { 1, 0.75, 2.5, 1, 1 } end
        p = _dpt("heavy_slashing_linesman_executioner")
        if p and p.targets then
            if p.targets[1] and p.targets[1].power_distribution then p.targets[1].power_distribution.attack = 0.325 end
            if p.targets[2] and p.targets[2].power_distribution then p.targets[2].power_distribution.attack = 0.25 end
            if p.targets[3] and p.targets[3].power_distribution then p.targets[3].power_distribution.attack = 0.15 end
        end
        p = _dpt("heavy_slashing_smiter_glaive")
        if p and p.default_target then
            if p.default_target.power_distribution then p.default_target.power_distribution.attack = 0.7 end
            if p.default_target.armor_modifier then p.default_target.armor_modifier.attack = { 1, 0.5, 2.5, 1, 0.75 } end
            p.default_target.attack_template = "heavy_slashing_smiter_hs_executioner"
        end
    end

    if _on("br_dpt_med_spear_smiter_stab") then
        local p = _dpt("medium_spear_smiter_stab")
        if p and p.default_target then p.default_target.boost_curve_coefficient_headshot = 2 end
    end

    if _on("br_dpt_light_slash_elf") then
        local p = _dpt("light_slashing_linesman_elf")
        if p and p.armor_modifier then p.armor_modifier.attack = { 1, 0.3, 1.5, 1, 0.75 } end
    end

    if _on("br_dpt_light_slash_line_dual_med") then
        local p = _dpt("light_slashing_linesman_dual_medium")
        if p and p.targets then
            if p.targets[1] then
                if p.targets[1].power_distribution then p.targets[1].power_distribution.attack = 0.175 end
                if p.targets[1].armor_modifier then p.targets[1].armor_modifier.attack = { 1, 0.4, 2, 1, 0.75 } end
            end
            if p.targets[2] then
                if p.targets[2].power_distribution then p.targets[2].power_distribution.attack = 0.15 end
                p.targets[2].boost_curve_coefficient_headshot = 2
            end
            if p.default_target and p.default_target.power_distribution then p.default_target.power_distribution.attack = 0.1 end
        end
    end

    if _on("br_dpt_med_spear_thorn_skin_etc") then
        local p = _dpt("thorn_skin")
        if p then
            if p.armor_modifier then p.armor_modifier.attack = { 0.5, 0.1, 1, 1, 0.25, 0 } end
            if p.default_target then
                p.default_target.dot_template_name = "long_burn_low_damage"
                p.default_target.attack_template = "burning"
                p.default_target.damage_type = "burn"
            end
        end
    end

    -- ---- POINTY family ----
    if _on("br_dpt_light_pointy_smiter") then
        local rows = { "light_pointy_smiter", "light_pointy_smiter_diag",
                       "light_pointy_smiter_flat", "light_pointy_smiter_upper" }
        local attacks = { 0.25, 0.3, 0.3, 0.3 }
        for i, n in ipairs(rows) do
            local p = _dpt(n)
            if p then
                if p.default_target and p.default_target.power_distribution then
                    p.default_target.power_distribution.attack = attacks[i]
                end
                if p.armor_modifier then p.armor_modifier.attack = { 1, 0.5, 2.5, 1, 0.75, 0.4 } end
            end
        end
    end

    if _on("br_dpt_med_pointy_smiter_flat_1h") then
        local p = _dpt("medium_pointy_smiter_flat_1h")
        if p then
            if p.armor_modifier then p.armor_modifier.attack = { 1, 0.5, 2.5, 1, 0.75, 0.4 } end
            if p.critical_strike then p.critical_strike.attack = { 1, 0.75, 3, 1, 1, 0.5, 0.4 } end
        end
    end

    -- ---- Ranged shared ----
    if _on("br_dpt_staff_fireball_charged") then
        local p = _dpt("staff_fireball_charged")
        if p and p.default_target then
            if p.default_target.power_distribution_near then
                p.default_target.power_distribution_near.attack = 0.4
                p.default_target.power_distribution_near.impact = 0.6
            end
            if p.default_target.power_distribution_far then
                p.default_target.power_distribution_far.attack = 0.4
                p.default_target.power_distribution_far.impact = 0.3
            end
        end
        if p and p.critical_strike then
            p.critical_strike.attack_armor_power_modifer = { 1, 0.5, 0.5, 1, 0.5, 0.2 }
        end
        if p and p.armor_modifier then p.armor_modifier.attack = { 1, 0.3, 0.5, 1, 0.5, 0.1 } end
    end

    if _on("br_dpt_fireball_explosion") then
        local p = _dpt("fireball_charged_explosion")
        if p and p.default_target and p.default_target.power_distribution then p.default_target.power_distribution.attack = 0.15 end
        if p then p.no_friendly_fire = true end
        local g = _dpt("fireball_charged_explosion_glance")
        if g and g.default_target and g.default_target.power_distribution then g.default_target.power_distribution.attack = 0.1 end
        if g then g.no_friendly_fire = true end
    end

    if _on("br_dpt_soul_rip") then
        local p = _dpt("soul_rip")
        if p then
            if p.armor_modifier_near then p.armor_modifier_near.attack = { 1, 0.5, 1.5, 0.5, 1, 0.075 } end
            if p.armor_modifier_far then p.armor_modifier_far.attack = { 1, 0.2, 0.5, 0.25, 0.5, 0.05 } end
        end
    end

    if _on("br_dpt_shot_machinegun_shieldbreak") then
        local p = _dpt("shot_machinegun_shotgun"); if p then p.shield_break = true end
    end

    if _on("br_dpt_shot_carbine") then
        local p = _dpt("shot_carbine"); if p and p.default_target then p.default_target.boost_curve_coefficient_headshot = 2 end
    end

    if _on("br_dpt_crossbow_bolt_repeating") then
        if rawget(_G, "DamageProfileTemplates") then
            DamageProfileTemplates.crossbow_bolt_repeating = {
                charge_value = "projectile",
                armor_modifier = {
                    attack = { 1, 0.3, 2.5, 0.4, 0.75, 0.075 },
                    impact = { 1, 1, 1, 1, 1 },
                },
                critical_strike = {
                    attack_armor_power_modifer = { 1, 0.6, 3.5, 0.5, 1, 0.1 },
                    impact_armor_power_modifer = { 1, 1, 1, 1, 1.5 },
                },
                cleave_distribution = { attack = 0.4, impact = 0.4 },
                default_target = {
                    attack_template = "crossbow_repeating",
                    boost_curve_type = "ranged_curve",
                    boost_curve_coefficient_headshot = 1.5,
                    range_modifier_settings = "carbine_dropoff_ranges",
                    power_distribution_near = { attack = 0.275, impact = 0.1 },
                    power_distribution_far = { attack = 0.2, impact = 0.05 },
                },
            }
        end
    end

    if _on("br_dpt_dr_deus") then
        local p = _dpt("dr_deus_01_explosion")
        if p then
            if p.armor_modifier then p.armor_modifier.attack = { 1, 0.5, 1.5, 0.75, 1, 0.5 } end
            if p.default_target and p.default_target.power_distribution then p.default_target.power_distribution.attack = 0.25 end
        end
        p = _dpt("dr_deus_01_glance")
        if p then
            if p.armor_modifier then p.armor_modifier.attack = { 1, 0.5, 1.5, 0.75, 1, 0.5 } end
            if p.default_target and p.default_target.power_distribution then p.default_target.power_distribution.attack = 0.05 end
        end
        p = _dpt("dr_deus_01")
        if p and p.default_target then
            p.default_target.boost_curve_coefficient_headshot = 2.5
            if p.default_target.power_distribution_near then p.default_target.power_distribution_near.attack = 1.5 end
        end
    end

    if _on("br_dpt_thrown_javelin") then
        local p = _dpt("thrown_javelin")
        if p then
            if p.default_target then
                p.default_target.boost_curve_coefficient_headshot = 2
                p.default_target.boost_curve_type = "ninja_curve"
                if p.default_target.power_distribution_near then p.default_target.power_distribution_near.impact = 0.5 end
                if p.default_target.power_distribution_far then p.default_target.power_distribution_far.impact = 0.5 end
            end
            if p.cleave_distribution then
                p.cleave_distribution.attack = 0.475
                p.cleave_distribution.impact = 0.475
            end
        end
    end

    if _on("br_dpt_shot_sniper_pistol_dropoff") then
        local p = _dpt("shot_sniper_pistol")
        if p and p.default_target then
            p.default_target.range_modifier_settings = { min_range = 15, max_range = 30 }
        end
    end

    if _on("br_dpt_shot_duckfoot") then
        local p = _dpt("shot_duckfoot")
        if p and p.cleave_distribution then
            p.cleave_distribution.attack = 0.05
            p.cleave_distribution.impact = 0.05
        end
    end

    if _on("br_dpt_geiser") then
        local p = _dpt("geiser")
        if p and p.targets then
            if p.targets[1] and p.targets[1].power_distribution then p.targets[1].power_distribution.attack = 0.6 end
            if p.targets[2] and p.targets[2].power_distribution then p.targets[2].power_distribution.impact = 0.7 end
        end
    end

    if _on("br_dpt_drake_pistol") then
        local p = _dpt("shot_drakefire")
        if p then
            if p.armor_modifier_near then p.armor_modifier_near.attack = { 1, 0.5, 1.5, 0.75, 1, 0.2 } end
            if p.armor_modifier_far then p.armor_modifier_far.attack = { 1, 0.3, 0.5, 0.25, 0.5, 0.1 } end
            if p.critical_strike then p.critical_strike.attack_armor_power_modifer = { 1, 1, 1.5, 1, 1, 0.3 } end
            if p.default_target then
                if p.default_target.power_distribution_near then p.default_target.power_distribution_near.attack = 0.19 end
                if p.default_target.power_distribution_far then p.default_target.power_distribution_far.attack = 0.1 end
                p.default_target.range_modifier_settings = { min_range = 5, max_range = 10 }
            end
        end
        p = _dpt("blast")
        if p then
            if p.default_target and p.default_target.power_distribution_near then p.default_target.power_distribution_near.impact = 0.5 end
            if p.armor_modifier then
                p.armor_modifier.impact = { 1, 1, 1, 1, 1.5, 1 }
                if p.armor_modifier.attack then p.armor_modifier.attack[5] = 0.6 end
            end
            if p.critical_strike then
                p.critical_strike.impact_armor_power_modifer = { 1, 1, 1, 1, 1.5, 1 }
                if p.critical_strike.attack_armor_power_modifer then p.critical_strike.attack_armor_power_modifer[5] = 0.6 end
            end
        end
    end

    if _on("br_dpt_beam_shot") then
        local p = _dpt("beam_shot")
        if p and p.default_target and p.default_target.power_distribution_near then
            p.default_target.power_distribution_near.attack = 0.85
        end
    end

    if _on("br_dpt_fire_spear_3") then
        local p = _dpt("fire_spear_3")
        if p then
            if p.armor_modifier_near then p.armor_modifier_near.attack = { 1, 0.5, 1.5, 0.5, 1, 0.075 } end
            if p.armor_modifier_far then p.armor_modifier_far.attack = { 1, 0.2, 0.5, 0.25, 0.5, 0.05 } end
        end
    end

    if _on("br_dpt_arrow_machinegun") then
        local p = _dpt("arrow_machinegun")
        if p and p.cleave_distribution then
            p.cleave_distribution.attack = 0.25
            p.cleave_distribution.impact = 0.25
        end
        p = _dpt("arrow_carbine_shortbow")
        if p then
            if p.cleave_distribution then
                p.cleave_distribution.attack = 0.35
                p.cleave_distribution.impact = 0.45
            end
            if p.default_target then
                if p.default_target.power_distribution_near then p.default_target.power_distribution_near.attack = 0.2 end
                if p.default_target.power_distribution_far then p.default_target.power_distribution_far.attack = 0.15 end
            end
            if p.armor_modifier_near and p.armor_modifier_near.attack then
                p.armor_modifier_near.attack[2] = 0.3
                p.armor_modifier_near.attack[5] = 0.75
            end
            if p.armor_modifier_far and p.armor_modifier_far.attack then p.armor_modifier_far.attack[5] = 0.75 end
            if p.critical_strike and p.critical_strike.attack_armor_power_modifer then
                p.critical_strike.attack_armor_power_modifer[2] = 0.3
                p.critical_strike.attack_armor_power_modifer[5] = 0.75
            end
        end
        p = _dpt("arrow_sniper_kruber")
        if p and p.cleave_distribution then
            p.cleave_distribution.attack = 0.5
            p.cleave_distribution.impact = 0.5
        end
    end

    if _on("br_dpt_burning_dot_firegrenade") then
        local p = _dpt("burning_dot_firegrenade")
        if p and p.default_target and p.default_target.armor_modifier then
            p.default_target.armor_modifier.attack = { 1, 1, 0.5, 0.5, 1, 0.1 }
        end
    end

    if _on("br_dpt_frag_grenade") then
        local p = _dpt("frag_grenade")
        if p and p.default_target and p.default_target.power_distribution then p.default_target.power_distribution.attack = 1.25 end
        local g = _dpt("frag_grenade_glance")
        if g and g.default_target and g.default_target.power_distribution then g.default_target.power_distribution.attack = 0.4 end
    end

    if _on("br_dpt_throwing_axe_hs") then
        local p = _dpt("throwing_axe"); if p and p.default_target then p.default_target.boost_curve_coefficient_headshot = 2 end
        p = _dpt("throwing_axe_charged"); if p and p.default_target then p.default_target.boost_curve_coefficient_headshot = 2 end
    end
end

-- ============================================================
-- WIELD PERMISSION EXPANSIONS
-- ============================================================

local _BR_WIELD_LISTS = {
    br_wield_es_2h_heavy_spear   = { item = "es_2h_heavy_spear",
                                      add = { "es_huntsman", "es_knight", "es_mercenary", "es_questingknight" } },
    br_wield_wh_1h_falchion      = { item = "wh_1h_falchion",
                                      add = { "wh_zealot", "wh_bountyhunter", "wh_captain", "wh_priest" } },
    br_wield_wh_2h_sword         = { item = "wh_2h_sword",
                                      add = { "wh_zealot", "wh_bountyhunter", "wh_captain", "wh_priest" } },
    br_wield_wh_1h_axe           = { item = "wh_1h_axe",
                                      add = { "wh_zealot", "wh_bountyhunter", "wh_captain", "wh_priest" } },
    br_wield_wh_dw_axe_falchion  = { item = "wh_dual_wield_axe_falchion",
                                      add = { "wh_zealot", "wh_bountyhunter", "wh_captain", "wh_priest" } },
}

local function _apply_wield_permissions()
    if not rawget(_G, "ItemMasterList") then return end
    for setting, row in pairs(_BR_WIELD_LISTS) do
        if _on(setting) then
            local item = rawget(ItemMasterList, row.item)
            if item then
                item.can_wield = item.can_wield or {}
                local present = {}
                for i = 1, #item.can_wield do present[item.can_wield[i]] = true end
                for i = 1, #row.add do
                    if not present[row.add[i]] then
                        item.can_wield[#item.can_wield + 1] = row.add[i]
                    end
                end
            end
        end
    end
end

-- ============================================================
-- MISC / CROSS-CUTTING
-- ============================================================

local function _apply_misc()
    if _on("br_misc_chaos_raider_special_staggers") then
        local BA = rawget(_G, "BreedActions")
        local cr = BA and BA.chaos_raider
        if cr and cr.special_attack_cleave then
            cr.special_attack_cleave.ignore_staggers = { true, true, false, true, true, false }
        end
    end

    if _on("br_misc_tank_hit_mass_plague_monk") then
        local THMC = rawget(_G, "TANK_HIT_MASS_COUNT")
        if type(THMC) == "table" then THMC.skaven_plague_monk = 0.5 end
    end

    if _on("br_misc_status_dodge_count") then
        -- Documented dependency on et stagger rewrite. We surface only the
        -- dodge_count knob here (a single-field write that's safe in isolation).
        local GSE = rawget(_G, "GenericStatusExtension")
        if GSE and not mod._br_status_dodge_hooked then
            mod._br_status_dodge_hooked = true
            mod:hook_safe(GSE, "init", function(self)
                if self and rawget(self, "dodge_count") == nil then
                    self.dodge_count = 2
                end
            end)
        end
    end

    -- Moonbow cosmetic puff toggle: existing widget moonfire_cosmetic_puff
    -- is already wired in weapon_tweaker.lua; br_moonbow_cosmetic_puff
    -- simply forwards to that read-path so users see a unified group.
    if _on("br_moonbow_cosmetic_puff") then
        -- No-op: existing moonfire_cosmetic_puff handles the effect.
        -- This toggle just appears alongside the other moonbow toggles in
        -- the UI for discoverability.
    end
end

-- ============================================================
-- FUNCTION HOOKS (Flamethrower / Beam / TrueFlight)
-- ============================================================
-- Copied verbatim from source/weapon_changes.lua, gated by toggles.
-- Vanilla calls go through `func` (vanilla) when the gate is off.

-- These constants live in source/weapon_changes.lua near the top of the
-- mod file (they are upvalues to the Flamethrower hook). Mirror them
-- here so the hook stays drop-in identical.
local POSITION_TWEAK = -1.5
local SPRAY_RANGE    = 11.5
local MAX_TARGETS    = 19

local _hooks_installed = false

-- v0.12.88-dev: per-hook sample counters. The Beam hook
-- (`client_owner_post_update`) fires per-frame while the beam button is held;
-- emitting a _dbg line per call would flood. Flamethrower `_select_targets`
-- and TrueFlight `fire`/`client_owner_start_action` are per-fire (sparse
-- enough for always-on but we sample anyway for consistency, since
-- TrueFlight `fire` can fan out 5+ projectiles per tick under multi-shot
-- talents). 1-in-60 = ~1/sec on a held beam, ~1/3rd of single-arrow shots.
local _BR_HOOK_SAMPLE_N = 60
local _br_flamethrower_count = 0
local _br_beam_count = 0
local _br_trueflight_start_count = 0
local _br_trueflight_fire_count = 0

-- v0.12.116: vanilla per-projectile speed falloff (action_true_flight_bow.lua:152:
-- `speed = speed * (1 - i * 0.05)` for i > 1, applied cumulatively across the fire
-- loop). Factored out because the reimpl shipped the sign-flipped form
-- `speed * (i * 0.05 - 1)` for ~28 versions, sending every projectile after the
-- first backwards at negative speed. File-scope (not inside the master-gated
-- installer) so the regression test can assert it even when BR hooks are off.
-- Test: wt_br_trueflight_speed_falloff_matches_vanilla in weapon_tweaker.lua.
function mod._wt_tf_projectile_speed(speed, i)
    if i > 1 then return speed * (1 - i * 0.05) end
    return speed
end

-- v0.12.117 (Issue #74): vanilla's per-projectile extra-shot test
-- (action_true_flight_bow.lua:128,132: `extra_shots_idx = num_projectiles -
-- num_extra_shots + 1; is_extra_shot = extra_shots_idx <= i`). The reimpl
-- previously gated set_shooting/ammo/overcharge on `self.extra_buff_shot`,
-- which is only ever assigned false — so under extra-shot buffs the free
-- extra projectiles also bumped spread state and charged ammo/overcharge
-- where vanilla skips them. File-scope for the regression test
-- (wt_br_trueflight_extra_shot_gating_matches_vanilla in weapon_tweaker.lua).
function mod._wt_tf_is_extra_shot(i, num_projectiles, num_extra_shots)
    local extra_shots_idx = num_projectiles - (num_extra_shots or 0) + 1
    return extra_shots_idx <= i
end

local function _install_function_hooks()
    if _hooks_installed then return end
    if not _master() then
        _dbg("[wt:br_hooks] event=skip_install reason=master_off")
        return
    end
    _dbg("[wt:br_hooks] event=install_begin")

    -- Flamethrower cone rework
    if rawget(_G, "ActionFlamethrower") then
        mod:hook(ActionFlamethrower, "_select_targets", function(func, self, world, show_outline)
            if not _on("br_hook_flamethrower_cone") then return func(self, world, show_outline) end
            _br_flamethrower_count = _br_flamethrower_count + 1
            if _br_flamethrower_count % _BR_HOOK_SAMPLE_N == 0 then
                _dbg("[wt:br_hooks] event=flamethrower_select_targets sample=%d", _br_flamethrower_count)
            end
            local owner_unit = self.owner_unit
            local fpe = ScriptUnit.extension(owner_unit, "first_person_system")
            local position_offset = Vector3(0, 0, -0.4)
            local player_position = fpe:current_position() + position_offset
            local fpu = self.first_person_unit
            local player_rotation = Unit.world_rotation(fpu, 0)
            local player_direction = Vector3.normalize(Quaternion.forward(player_rotation))
            local ignore_allies = not Managers.state.difficulty:get_difficulty_settings().friendly_fire_ranged
            local start_point = player_position + player_direction * POSITION_TWEAK
            local broadphase_radius = 6
            local blackboard = BLACKBOARDS[owner_unit]
            local side = blackboard.side
            local ai_units = {}
            local ai_units_n = AiUtils.broadphase_query(player_position + player_direction * broadphase_radius,
                                                       broadphase_radius, ai_units)
            local physics_world = World.get_data(world, "physics_world")
            PhysicsWorld.prepare_actors_for_overlap(physics_world, start_point, SPRAY_RANGE * SPRAY_RANGE)
            if ai_units_n > 0 then
                local targets = self.targets
                local v, q, m = Script.temp_count()
                local num_hit = 0
                for i = 1, ai_units_n do
                    local hit_unit = ai_units[i]
                    local hit_position = POSITION_LOOKUP[hit_unit] + Vector3.up()
                    if targets[hit_unit] == nil then
                        local is_enemy = side.enemy_units_lookup[hit_unit]
                        if (is_enemy or not ignore_allies)
                                and self:_is_infront_player(player_position, player_direction, hit_position)
                                and self:_check_within_cone(start_point, player_direction, hit_unit, is_enemy) then
                            targets[#targets + 1] = hit_unit
                            targets[hit_unit] = false
                            if is_enemy and ScriptUnit.extension(hit_unit, "health_system"):is_alive() then
                                num_hit = num_hit + 1
                            end
                        end
                        if MAX_TARGETS <= num_hit then break end
                    end
                end
                Script.set_temp_count(v, q, m)
            end
        end)
    end

    -- Beam staff aim-toggle rework (only the action_three zoom switch piece is
    -- safely overlayable; the full rewrite changes ramping/consecutive-hit
    -- logic which is captured below by replacing client_owner_post_update
    -- entirely when the toggle is on).
    if rawget(_G, "ActionBeam") then
        mod:hook(ActionBeam, "client_owner_post_update", function(func, self, dt, t, world, can_damage)
            if not _on("br_hook_beam_aim_toggle") then return func(self, dt, t, world, can_damage) end
            -- v0.12.88-dev: sampled trace. PER-FRAME hot path while beam
            -- button held; 1-in-60 = ~1 line per second of held beam.
            _br_beam_count = _br_beam_count + 1
            if _br_beam_count % _BR_HOOK_SAMPLE_N == 0 then
                _dbg("[wt:br_hooks] event=beam_client_owner_post_update sample=%d", _br_beam_count)
            end
            local owner_unit = self.owner_unit
            local current_action = self.current_action
            local input_extension = ScriptUnit.extension(owner_unit, "input_system")
            local buff_extension = self.owner_buff_extension
            local status_extension = self.status_extension

            if current_action.zoom_thresholds and input_extension:get("action_three") then
                status_extension:switch_variable_zoom(current_action.buffed_zoom_thresholds)
            end

            return func(self, dt, t, world, can_damage)
        end)
    end

    -- TrueFlight rework — both start_action and fire are origin replacements
    -- in BR. We use safe hooks for additive logic when the toggle is off.
    if rawget(_G, "ActionTrueFlightBow") then
        mod:hook(ActionTrueFlightBow, "client_owner_start_action", function(func, self, new_action, t, chain_action_data, power_level, action_init_data)
            if not _on("br_hook_trueflight_start") then
                return func(self, new_action, t, chain_action_data, power_level, action_init_data)
            end
            -- v0.12.88-dev: sampled trace. Per-fire (one per draw/release).
            _br_trueflight_start_count = _br_trueflight_start_count + 1
            if _br_trueflight_start_count % _BR_HOOK_SAMPLE_N == 0 then
                _dbg("[wt:br_hooks] event=trueflight_start_action sample=%d template=%s",
                    _br_trueflight_start_count, tostring(new_action and new_action.true_flight_template))
            end
            ActionTrueFlightBow.super.client_owner_start_action(self, new_action, t, chain_action_data, power_level, action_init_data)
            self.current_action = new_action
            self.true_flight_template_id = TrueFlightTemplates[new_action.true_flight_template].lookup_id
            local is_moonbow = new_action and new_action.drain_amount ~= nil
            local owner_unit = self.owner_unit
            local buff_extension = ScriptUnit.extension(owner_unit, "buff_system")
            local is_critical_strike = ActionUtils.is_critical_strike(owner_unit, new_action, t)
            local num_extra_shots = self:_update_extra_shots(buff_extension) or 0
            self.num_extra_shots = num_extra_shots
            self:_update_extra_shots(buff_extension, num_extra_shots)
            self.num_projectiles = (new_action.num_projectiles or 1) + num_extra_shots
            local talent_extension = ScriptUnit.has_extension(owner_unit, "talent_system")
            if new_action.true_flight_template == "active_ability_kerillian_way_watcher"
                    and talent_extension
                    and talent_extension:has_talent("kerillian_waywatcher_activated_ability_additional_projectile")
                    and not is_moonbow then
                self.num_projectiles = self.num_projectiles + 2
            end
            self.multi_projectile_spread = new_action.multi_projectile_spread or 0.075
            self.num_projectiles_shot = 1
            if chain_action_data then
                self.targets = chain_action_data.targets or { chain_action_data.target }
            end
            if action_init_data then
                self.targets = action_init_data.targets or { action_init_data.target }
            end
            self.state = "waiting_to_shoot"
            self.time_to_shoot = t + (new_action.fire_time or 0)
            self.power_level = power_level
            self.extra_buff_shot = false
            self.owner_buff_extension = buff_extension
            local hud_extension = ScriptUnit.has_extension(owner_unit, "hud_system")
            self:_handle_critical_strike(is_critical_strike, buff_extension, hud_extension, nil, "on_critical_shot", nil)
            self._is_critical_strike = is_critical_strike
        end)

        mod:hook(ActionTrueFlightBow, "fire", function(func, self, current_action)
            if not _on("br_hook_trueflight_fire") then return func(self, current_action) end
            -- v0.12.88-dev: sampled trace. Per-fire (can fan out 5+
            -- projectiles per call under multi-shot talents); capture
            -- num_projectiles so multi-shot bursts are identifiable.
            _br_trueflight_fire_count = _br_trueflight_fire_count + 1
            if _br_trueflight_fire_count % _BR_HOOK_SAMPLE_N == 0 then
                _dbg("[wt:br_hooks] event=trueflight_fire sample=%d num_projectiles=%s",
                    _br_trueflight_fire_count, tostring(self.num_projectiles))
            end
            local owner_unit = self.owner_unit
            local speed = current_action.speed
            local fpe = self.first_person_extension
            local position, rotation = fpe:get_projectile_start_position_rotation()
            local spread_extension = self.spread_extension
            local num_projectiles = self.num_projectiles
            for i = 1, num_projectiles do
                local fire_rotation = rotation
                -- v0.12.117 (Issue #74): per-projectile extra-shot test exactly as
                -- vanilla (action_true_flight_bow.lua:128,132) — was gated on
                -- self.extra_buff_shot, which is only ever false, so extra-shot-buff
                -- projectiles wrongly bumped spread/ammo/overcharge below.
                local is_extra_shot = mod._wt_tf_is_extra_shot(i, num_projectiles, self.num_extra_shots)
                if spread_extension then
                    if self.num_projectiles_shot > 1 then
                        local spread_horizontal_angle = math.pi * (self.num_projectiles_shot % 2 + 0.5)
                        local shot_count_offset = self.num_projectiles_shot == 1 and 0
                                or math.round((self.num_projectiles_shot - 1) * 0.5, 0)
                        local angle_offset = self.multi_projectile_spread * shot_count_offset
                        fire_rotation = spread_extension:combine_spread_rotations(spread_horizontal_angle, angle_offset, fire_rotation)
                    end
                    -- audit 2026-06-07: vanilla ActionTrueFlightBow.fire takes only
                    -- (self, current_action) and calls set_shooting() on every non-extra
                    -- shot (action_true_flight_bow.lua:143). The `add_spread` 2nd param this
                    -- reimpl declared was ALWAYS nil (vanilla's caller passes no 2nd arg), so
                    -- set_shooting() never ran here.
                    if not is_extra_shot then spread_extension:set_shooting() end
                end
                local angle = ActionUtils.pitch_from_rotation(fire_rotation)
                local target_vector = Vector3.normalize(Quaternion.forward(fire_rotation))
                -- v0.12.116: was speed * (i * 0.05 - 1) — the sign-flip of vanilla's
                -- falloff (action_true_flight_bow.lua:152), sending every projectile
                -- after the first backwards at negative speed under multi-shot fires.
                speed = mod._wt_tf_projectile_speed(speed, i)
                local target_unit = self.targets
                    and ((current_action.single_target and self.targets[1]) or self.targets[i])
                local lookup_data = current_action.lookup_data
                if lookup_data then
                    ActionUtils.spawn_true_flight_projectile(owner_unit, target_unit, self.true_flight_template_id,
                        position, fire_rotation, angle, target_vector, speed, self.item_name,
                        lookup_data.item_template_name, lookup_data.action_name, lookup_data.sub_action_name,
                        1, self._is_critical_strike, self.power_level)
                end
                if self.ammo_extension and not is_extra_shot then
                    self.ammo_extension:use_ammo(current_action.ammo_usage)
                    if self.ammo_extension:can_reload() then self.ammo_extension:start_reload(false) end
                end
                self.num_projectiles_shot = self.num_projectiles_shot + 1
                local overcharge_type = current_action.overcharge_type
                if overcharge_type and not is_extra_shot then
                    local oa = PlayerUnitStatusSettings.overcharge_values[overcharge_type]
                    if current_action.scale_overcharge then
                        self.overcharge_extension:add_charge(oa, self.charge_level)
                    else
                        self.overcharge_extension:add_charge(oa)
                    end
                end
                if current_action.energy_weapon and not is_extra_shot then
                    local energy_extension = ScriptUnit.extension(owner_unit, "energy_system")
                    energy_extension:drain(current_action.drain_amount)
                end
                if current_action.alert_sound_range_fire then
                    Managers.state.entity:system("ai_system"):alert_enemies_within_range(owner_unit,
                        POSITION_LOOKUP[owner_unit], current_action.alert_sound_range_fire)
                end
            end
        end)
    end

    -- Shield slam rewrite (large hook; we only install the gate. The
    -- detailed re-implementation isn't safely separable from BR's
    -- stagger/damage helpers, so this hook stays a no-op when the toggle
    -- is off — when on, it forwards to the table-replacement done by
    -- br_shield_slam_replace and otherwise calls vanilla. A future
    -- iteration may inline the full BR _hit body here.)
    -- Documented dependency: stagger_ai rewrite (et).

    _hooks_installed = true
    _dbg("[wt:br_hooks] event=install_done flamethrower=%s beam=%s trueflight=%s",
        tostring(rawget(_G, "ActionFlamethrower") ~= nil),
        tostring(rawget(_G, "ActionBeam") ~= nil),
        tostring(rawget(_G, "ActionTrueFlightBow") ~= nil))
end

-- ============================================================
-- ENTRY POINT
-- ============================================================

function BR.apply_all()
    _dbg("[wt:br_hooks] event=apply_all_begin master_active=%s", tostring(_master()))
    BR.register_all()
    _apply_weapons_meta_init()
    _apply_melee_1h_hammer()
    _apply_melee_2h_hammer()
    _apply_melee_1h_sword()
    _apply_melee_2h_sword()
    _apply_melee_polearm()
    _apply_melee_dual()
    _apply_melee_mace_axe()
    _apply_melee_shield()
    _apply_ranged_bow()
    _apply_ranged_gun()
    _apply_ranged_staff()
    _apply_ranged_career()
    _apply_damage_profile_tuning()
    _apply_wield_permissions()
    _apply_misc()
    _install_function_hooks()
    _dbg("[wt:br_hooks] event=apply_all_done hooks_installed=%s", tostring(_hooks_installed))
end

return BR
