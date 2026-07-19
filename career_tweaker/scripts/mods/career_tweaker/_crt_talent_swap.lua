-- career_tweaker / _crt_talent_swap.lua
--
-- Responsibility: Dormant career talent-tree + ability/passive swapping. The
-- independent _crt_talent_menu_guard owns talent-window lifecycle hooks; this
-- module owns only the DLC gate and apply/restore engine that rebinds one
-- career's talent tree + activated/passive ability onto another.
--
-- Public surface (via mod._crt, consumed by the entry's lifecycle callbacks
-- and _crt_regression.lua):
--   mod._crt.ALL_CAREERS                -- ordered list of all 20 career ids
--   mod._crt.apply_talent_swaps()       -- restore-then-apply current settings
--   mod._crt.restore_talent_swaps()     -- rebind saved originals; clear pending
--   mod._crt.refresh_talent_ui()        -- re-read swapped trees in the open picker
--   mod._crt.get_talent_swap_originals()      -- read the pending-swap table
--   mod._crt.set_talent_swap_originals(t)     -- replace it (regression harness)
--
-- Manifest position: after the module dofiles (needs `mod`), before the entry
-- captures its `apply_talent_swaps` / `restore_talent_swaps` / `refresh_talent_ui`
-- lifecycle locals. Split out of career_tweaker.lua (v0.3.57-dev, Phase 1 OOP
-- decomposition); pure structural move, no behavior change.

local mod = get_mod("crt")
mod._crt = mod._crt or {}

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

-- The independent no-op guard tracks HeroWindowTalents on mod._crt so this
-- dormant engine can refresh it if a future redesign explicitly loads both.
-- QUESTION: HeroWindowTalentsConsole (controller-mode UI) has its own
-- _update_talent_sync but isn't tracked here — controller users won't get the
-- live refresh. Acceptable if controller UI is out of scope.

local function refresh_talent_ui()
    local talent_window_instance = mod._crt.talent_window_instance
    if talent_window_instance then
        -- pcall guards against the window being torn down between the on_exit
        -- hook firing late and the refresh attempting to access it.
        pcall(function()
            talent_window_instance:_update_talent_sync(false)
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

-- Revert any prior talent swap by re-binding the saved original tree/ability
-- into each destination career's slot. Restores rebind only (no mutation of
-- inner tree contents), so this stays correct as long as nothing else mutates
-- TalentTrees[profile][index] in place. Factored out of apply_talent_swaps
-- (audit 2026-06-07, v0.3.22-dev) so on_disabled can cheaply unwind talent
-- swaps too (BUG_CLASSES §7 — "restore what's cheap"). Safe to call when
-- _talent_swap_originals is empty (no-op).
local function restore_talent_swaps()
    if not CareerSettings or not TalentTrees then return end
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
end

local function apply_talent_swaps()
    if not CareerSettings or not TalentTrees then return end

    -- Restore step: revert any prior swap before re-applying current settings.
    restore_talent_swaps()

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

-- ------------------------------------------------------------
-- Exports (mod._crt namespace; see header)
-- ------------------------------------------------------------
mod._crt.ALL_CAREERS         = _ALL_CAREERS
mod._crt.apply_talent_swaps  = apply_talent_swaps
mod._crt.restore_talent_swaps = restore_talent_swaps
mod._crt.refresh_talent_ui   = refresh_talent_ui
-- The regression harness (_crt_regression.lua, on_disabled_unwinds_talent_swaps)
-- needs get/set access to the pending-swap table -- it save/replaces/restores it
-- to prove restore_talent_swaps() clears state without mutating real career data.
-- A plain table ref won't work because restore_talent_swaps() REASSIGNS the local
-- (`_talent_swap_originals = {}`), so expose accessor closures.
mod._crt.get_talent_swap_originals = function() return _talent_swap_originals end
mod._crt.set_talent_swap_originals = function(t) _talent_swap_originals = t end
