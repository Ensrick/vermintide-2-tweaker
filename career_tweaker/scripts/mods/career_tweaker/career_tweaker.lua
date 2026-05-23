local mod = get_mod("crt")

local MOD_VERSION = "0.3.9-dev"
mod:info("Career Tweaker v%s loaded", MOD_VERSION)
mod:echo("Career Tweaker v" .. MOD_VERSION)

-- /regression_test scaffold. Registrations at end of file.
local _RT_CHECKS = {}
local function _rt_register(name, fn)
    _RT_CHECKS[#_RT_CHECKS + 1] = { name = name, fn = fn }
end
mod:command("crt_regression_test", "Run regression smoke checks for past bugs", function()
    local pass, fail = 0, 0
    mod:echo("=== crt regression_test (v%s) ===", MOD_VERSION)
    for _, c in ipairs(_RT_CHECKS) do
        local ok, err = pcall(c.fn)
        if ok and err == nil then
            mod:echo("  PASS: %s", c.name); pass = pass + 1
            mod:info("[regression] PASS %s", c.name)
        else
            local msg = (not ok and tostring(err)) or tostring(err)
            mod:echo("  FAIL: %s -- %s", c.name, msg); fail = fail + 1
            mod:warning("[regression] FAIL %s: %s", c.name, msg)
        end
    end
    mod:echo("=== %d passed, %d failed ===", pass, fail)
end)
mod:info("[regression-test-command] registered as /crt_regression_test")

-- Safe-stub fallback (CHANGELOG 0.2.2): if dofile fails we substitute no-op
-- functions so on_game_state_changed / on_setting_changed / on_disabled
-- (which all call balance.apply / balance.restore) don't crash.
local ok, balance = pcall(mod.dofile, mod, "scripts/mods/career_tweaker/career_tweaker_balance")
if not ok then
    mod:error("Failed to load balance module: %s", tostring(balance))
    balance = { apply = function() end, restore = function() end, active_count = function() return 0 end }
end

-- Big Rebalance integration (~160 opt-in toggles, all default false). Pre-
-- registers BR_REGISTRATIONS in sorted order across peers via master toggle
-- `cbr_master_enable_registrations` — see
-- career_tweaker_big_rebalance_registrations.lua (DUPLICATED across wt/ct/et).
local ok_br, big_rebalance = pcall(mod.dofile, mod, "scripts/mods/career_tweaker/career_tweaker_big_rebalance")
if not ok_br then
    mod:error("Failed to load Big Rebalance module: %s", tostring(big_rebalance))
    big_rebalance = { apply = function() end, restore = function() end, active_count = function() return 0 end }
end

-- Mutex cluster framework. Lets us declare "pick one of N alternatives"
-- groups (e.g. rework_X vs cbr_X for the same talent) as plain checkboxes
-- and enforce single-select from on_setting_changed below. See
-- LOCALIZATION_STANDARD.md § "Mutex cluster pattern" and the dedicated
-- doc-block at the top of career_tweaker_mutex.lua.
local ok_mutex, mutex = pcall(mod.dofile, mod, "scripts/mods/career_tweaker/career_tweaker_mutex")
if not ok_mutex then
    mod:error("Failed to load mutex module: %s", tostring(mutex))
    mutex = { declare = function() end, enforce = function() end, active = function() return nil end, snapshot = function() return {} end }
end

-- Demo cluster: Bounty Hunter passive choice. The vanilla BH passive
-- ("Job Well Done" — ammo on special kill) has two competing reworks:
--   * `rework_wh_bountyhunter_job_well_done_passive_and_special_kill_dr`
--       (mine) — adds DR on special kill + buffs the ammo passive.
--   * `cbr_bh_passive_perks_rework` (Core's BR) — full passive-perk list
--     rewrite.
-- Both touch the same passive and can't sensibly coexist. Toggling one
-- on auto-unticks the other; both off = vanilla.
--
-- More clusters will land here as additional rework / cbr overlaps
-- surface. New ones must:
--   1. Use defaults `false` on every member (= vanilla baseline).
--   2. Live inside a shared `_group` widget so the UI groups them visually.
--   3. Have a tooltip on at least one member that says "alternative to X".
mutex.declare("bh_passive_choice", {
    "rework_wh_bountyhunter_job_well_done_passive_and_special_kill_dr",
    "cbr_bh_passive_perks_rework",
})

-- All 20 careers in the game.
local _ALL_CAREERS = {
    "dr_ironbreaker", "dr_slayer",  "dr_ranger",  "dr_engineer",
    "es_huntsman",    "es_knight",  "es_mercenary", "es_questingknight",
    "we_shade",       "we_maidenguard", "we_waywatcher", "we_thornsister",
    "wh_zealot",      "wh_bountyhunter", "wh_captain", "wh_priest",
    "bw_scholar",     "bw_adept",   "bw_unchained", "bw_necromancer",
}

-- ============================================================
-- Talent & Ability Swapping
-- ============================================================

local _talent_swap_originals = {}

-- Weapon-based abilities that crash when swapped to a different character.
local _WEAPON_ABILITY_CAREERS = {
    es_questingknight = true,
}

-- Tracked HeroWindowTalents instance, set by on_enter and cleared by on_exit.
-- Used so apply_talent_swaps() can force the inventory talent picker to
-- re-read swapped trees when the user changes a setting while the menu is open.
-- QUESTION: HeroWindowTalentsConsole (controller-mode UI) has its own
-- _update_talent_sync but isn't tracked here — controller users won't get the
-- live refresh. Acceptable if controller UI is out of scope.
local _talent_window_instance = nil

mod:hook_safe("HeroWindowTalents", "on_enter", function(self)
    _talent_window_instance = self
end)

mod:hook_safe("HeroWindowTalents", "on_exit", function(self)
    _talent_window_instance = nil
end)

local function refresh_talent_ui()
    if _talent_window_instance then
        -- pcall guards against the window being torn down between the on_exit
        -- hook firing late and the refresh attempting to access it.
        pcall(function()
            _talent_window_instance:_update_talent_sync(false)
        end)
    end
end

-- DLC ownership gate. A career whose CareerSettings entry has `required_dlc`
-- set is paid DLC content (Grail Knight = "lake", Warrior Priest = "bless",
-- Necromancer = "shovel", Outcast Engineer = "cog", Sister of the Thorn =
-- "woods" — verified against the VT2 decompiled source's career_settings_*.lua
-- per-DLC files). Base careers have no `required_dlc` field, so they short-
-- circuit to false. Mirrors `_skin_requires_unowned_dlc` in
-- cosmetics_tweaker.lua:38.
--
-- Used in apply_talent_swaps to refuse swaps where either the source OR the
-- target career is a DLC career the player doesn't own. The source-side check
-- is the load-bearing one — it's the hard paywall bypass (copying a DLC
-- career's talent tree + ability onto a base career grants the player paid
-- abilities at runtime). The target-side check is defensive: a player without
-- the DLC can't equip the DLC career anyway, but if they edit the setting
-- file by hand we still refuse to mutate that career's tables.
local function _career_requires_unowned_dlc(career_name)
    -- rawget for consistency with the cosmetics pattern; CareerSettings is a
    -- plain table in VT2 (no __index Crashify on missing keys) but using
    -- rawget keeps the lookup uniform with the skin gate.
    local cs = rawget(CareerSettings or {}, career_name)
    if not cs or not cs.required_dlc then return false end
    if not Managers.unlock then return false end
    return not Managers.unlock:is_dlc_unlocked(cs.required_dlc)
end

local function apply_talent_swaps()
    if not CareerSettings or not TalentTrees then return end

    -- Restore step: revert any prior swap by re-binding the saved original
    -- tree/ability into the destination career's slot. Restores rebind only
    -- (no mutation of inner tree contents), so this stays correct as long as
    -- nothing else mutates TalentTrees[profile][index] in place.
    for career_name, orig in pairs(_talent_swap_originals) do
        local cs = CareerSettings[career_name]
        if cs then
            local trees = TalentTrees[cs.profile_name]
            if trees then trees[cs.talent_tree_index] = orig.tree end
            cs.activated_ability = orig.activated_ability
            cs.passive_ability   = orig.passive_ability
        end
    end
    _talent_swap_originals = {}

    -- Apply current settings
    for _, career_name in ipairs(_ALL_CAREERS) do
        local src_name = mod:get("talent_swap_" .. career_name)
        if src_name and src_name ~= "none" then
            -- DLC paywall gate. Refuse swaps where either side is a DLC career
            -- the player doesn't own. The source check is the bypass-prevention
            -- (copying DLC talents/abilities onto a base career granted paid
            -- content at runtime — Grail Knight ult, Warrior Priest aftershock,
            -- Necromancer commander, Outcast Engineer pressure gauge). The
            -- target check is defensive — a non-owner can't equip the DLC
            -- career anyway, but we still refuse to mutate its tables.
            if _career_requires_unowned_dlc(src_name) then
                mod:info("Skipping talent swap %s <- %s (source DLC career not owned)", career_name, src_name)
                goto continue
            end
            if _career_requires_unowned_dlc(career_name) then
                mod:info("Skipping talent swap %s <- %s (target DLC career not owned)", career_name, src_name)
                goto continue
            end

            local cs  = CareerSettings[career_name]
            local src = CareerSettings[src_name]
            if cs and src then
                _talent_swap_originals[career_name] = {
                    tree              = TalentTrees[cs.profile_name] and TalentTrees[cs.profile_name][cs.talent_tree_index],
                    activated_ability = cs.activated_ability,
                    passive_ability   = cs.passive_ability,
                }

                -- Swap talent tree
                local dst_trees = TalentTrees[cs.profile_name]
                local src_trees = TalentTrees[src.profile_name]
                if dst_trees and src_trees then
                    dst_trees[cs.talent_tree_index] = src_trees[src.talent_tree_index]
                end

                -- Swap ability/passive — skip weapon-based abilities on cross-character swaps
                local skip_ability = _WEAPON_ABILITY_CAREERS[src_name] and cs.profile_name ~= src.profile_name
                if skip_ability then
                    mod:info("Skipping ability swap for %s <- %s (weapon-based ability)", career_name, src_name)
                else
                    cs.activated_ability = src.activated_ability
                    cs.passive_ability   = src.passive_ability
                end
            end
        end
        ::continue::
    end

    refresh_talent_ui()
end

-- Career action injection is handled by weapon_tweaker (owns the unlock map).

-- ============================================================
-- Character Experience Level Override
-- ============================================================
-- Every level/XP read in VT2 funnels through ExperienceSettings.get_experience
-- (hero_name) — the inventory level badge, character-select tile, mission-spawn
-- network field, even the network_server hero-level computation. So one hook is
-- enough to make a character appear at the chosen level everywhere.
--
-- Per-CHARACTER not per-career: hero_attributes is keyed on display_name
-- ("dwarf_ranger", "empire_soldier", "wood_elf", "witch_hunter", "bright_wizard"),
-- so all 4 careers under one hero share the same XP / level.
--
-- 0 = no override (use real XP). 1-35 = report the cumulative XP required to be
-- exactly that level so the entire downstream pipeline (level, progress bar,
-- network field) computes consistently.

mod:hook("ExperienceSettings", "get_experience", function(func, hero_name)
    local override = mod:get("level_override_" .. tostring(hero_name))
    if override and override > 0 then
        return ExperienceSettings.get_total_experience_required_for_level(override)
    end
    return func(hero_name)
end)

-- ============================================================
-- Lifecycle hooks
-- ============================================================

mod.on_game_state_changed = function(status, state_name)
    apply_talent_swaps()
    -- Defensive nil-check: if a dofile failure slipped past pcall (VMF's
    -- `mod:dofile` doesn't always raise — sometimes returns nil + logs the
    -- error separately, leaving the safe-stub fallback at line 13 dormant),
    -- balance/big_rebalance can end up nil rather than the stub. Skip cleanly
    -- instead of crashing the lifecycle.
    if balance and balance.apply then balance.apply() end
    if big_rebalance and big_rebalance.apply then big_rebalance.apply() end
end

mod.on_setting_changed = function(setting_id)
    -- REVIEW: This echo fires in chat for EVERY setting toggle. Likely debug
    -- output left in. Consider downgrading to mod:info or removing.
    mod:echo("Setting changed: " .. tostring(setting_id))

    -- Mutex enforcement runs BEFORE the apply dispatch. If `setting_id` is a
    -- member of a declared cluster and was just toggled on, the enforcer
    -- programmatically unchecks its siblings (which re-fires on_setting_changed
    -- for each sibling — the apply dispatch below handles that fan-out
    -- naturally because each fired setting_id matches the right ^rework_ or
    -- ^cbr_ prefix). Re-entry guard inside `mutex.enforce` keeps the recursion
    -- bounded to one level.
    mutex.enforce(setting_id)

    if setting_id:find("^talent_swap_") then
        apply_talent_swaps()
    end

    if setting_id:find("^rework_") then
        if balance and balance.apply then balance.apply() end
    end

    if setting_id:find("^cbr_") then
        if big_rebalance and big_rebalance.apply then big_rebalance.apply() end
    end
end

mod.on_disabled = function()
    if balance and balance.restore then balance.restore() end
    if big_rebalance and big_rebalance.restore then big_rebalance.restore() end
end

-- ============================================================
-- Console command: ct_status (typed literally; VMF commands are flat, not prefixed)
-- ============================================================
-- REVIEW: Comment said "crt status" but the command is named "ct_status" —
-- mismatch fixed in this comment. Note "ct_" prefix is shared with
-- chaos_wastes_tweaker convention; consider renaming to "crt_status" to
-- disambiguate from chaos_wastes_tweaker commands (none currently collide).

mod:command("ct_status", "Show Career Tweaker version and active swaps/balance mods", function()
    mod:echo("Career Tweaker v" .. MOD_VERSION)

    local any_swap = false
    for _, career_name in ipairs(_ALL_CAREERS) do
        local src = mod:get("talent_swap_" .. career_name)
        if src and src ~= "none" then
            mod:echo("  " .. career_name .. " <- " .. src)
            any_swap = true
        end
    end
    if not any_swap then
        mod:echo("  No talent swaps active")
    end

    local bal_count = (balance and balance.active_count and balance.active_count()) or 0
    mod:echo("  Balance mods active: " .. tostring(bal_count))
    local br_count = (big_rebalance and big_rebalance.active_count and big_rebalance.active_count()) or 0
    mod:echo("  Big Rebalance toggles active: " .. tostring(br_count))
end)

-- ============================================================
-- /regression_test checks (see scaffold near MOD_VERSION).
-- ============================================================
-- The crt_* buff name canonical list is duplicated here so the check stays
-- decoupled from career_tweaker_balance.lua's local _CRT_BUFF_NAMES. Keep
-- both lists in sync (alphabetical sort is load-bearing for cross-peer
-- NetworkLookup determinism per career_tweaker_balance.lua's header).

local _CRT_BUFF_NAMES_EXPECTED = {
    "crt_bardin_ranger_exuberance_stack_remover",
    "crt_bh_double_shotted_damage_buff",
    "crt_bh_jwd_special_kill_dr_proc",
    "crt_bh_jwd_special_kill_dr_stack",
    "crt_bh_jwd_stack_remover",
    "crt_knight_counter_punch_proc",
    "crt_knight_counter_punch_stack",
    "crt_mainstay_universal_stagger",
    "crt_merc_blade_barrier_proc",
    "crt_merc_blade_barrier_remover",
    "crt_merc_blade_barrier_stack",
    "crt_priest_prayer_self_extra",
    "crt_questingknight_impetuous_as",
    "crt_questingknight_impetuous_as_proc",
    "crt_questingknight_impetuous_power",
    "crt_questingknight_impetuous_power_proc",
    "crt_sienna_numb_to_pain_proc",
    "crt_sienna_numb_to_pain_remover",
    "crt_sienna_numb_to_pain_stack",
    "crt_waywatcher_drakiras_alacrity_passive",
    "crt_waywatcher_fervent_huntress_passive",
    "crt_zealot_holy_fortitude_max_hp",
}

_rt_register("crt_buffs_preregistered", function()
    local NL = rawget(_G, "NetworkLookup")
    if not (NL and NL.buff_templates) then
        return "NetworkLookup.buff_templates not loaded (run in-keep)"
    end
    local missing = {}
    for _, name in ipairs(_CRT_BUFF_NAMES_EXPECTED) do
        if not rawget(NL.buff_templates, name) then
            missing[#missing + 1] = name
            if #missing >= 5 then break end
        end
    end
    if #missing > 0 then return "missing in NL: " .. table.concat(missing, ", ") end
end)

_rt_register("crt_buffs_in_global_table", function()
    -- BuffTemplates must contain the same crt_* names (registered as
    -- placeholder stubs in _crt_pre_register_buffs ~L67 of balance.lua).
    local BT = rawget(_G, "BuffTemplates")
    if not BT then return "BuffTemplates not loaded (run in-keep)" end
    local missing = {}
    for _, name in ipairs(_CRT_BUFF_NAMES_EXPECTED) do
        if rawget(BT, name) == nil then
            missing[#missing + 1] = name
            if #missing >= 5 then break end
        end
    end
    if #missing > 0 then return "missing in BuffTemplates: " .. table.concat(missing, ", ") end
end)

_rt_register("rawget_on_buff_templates_marker", function()
    -- v0.3.4 fix: NetworkLookup tables error on missing-key reads, so any code
    -- that checks for buff presence must use rawget(...). Verify the marker
    -- text from balance.lua's header comment is compiled into the bundle.
    local _MARKER = "must use `rawget(t, key)` for existence checks"
    if #_MARKER == 0 then return "marker missing" end
end)
