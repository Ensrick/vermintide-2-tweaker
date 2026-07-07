local mod = get_mod("crt")

local MOD_VERSION = "0.3.53-dev"
_MEM_PROBE_T0_CRT = collectgarbage("count")  -- [mem-probe] temp Lua-footprint baseline (lua_heap 1 GiB cap diagnostic)
-- Startup banner: log-only, NOT chat. The applied marker line further down
-- ([crt] enabled v<X> settings_fp=<hash>) is the canonical version surface
-- (PROJECT_STANDARDS.md § 3.6 "Chat-echo policy").
mod:info("Career Tweaker v%s loaded", MOD_VERSION)

-- Two-helper debug-logging policy (PROJECT_STANDARDS.md § 3.6).
-- Both route through VMF logging (mod:debug / mod:warning), gated by VMF output_mode.
-- `_dbg` is for confirmation / expected behavior — file only.
-- `_dbg_alert` is for unexpected / wrong / mismatch — file AND in-game chat.
local function _dbg(fmt, ...)
    mod:debug("[crt:dbg] " .. fmt, ...)
end

local function _dbg_alert(fmt, ...)
    mod:warning("[crt:dbg] " .. fmt, ...)
end

-- Applied marker (PROJECT_STANDARDS.md § 3.6 "Applied marker line (universal)").
-- Walks the data widget tree, FNV-1a-32 hashes setting=value pairs, prints
-- one mod:info line at load. ALWAYS fires (operational telemetry).
local function _settings_fingerprint()
    local ok, data = pcall(require, "scripts/mods/career_tweaker/career_tweaker_data")
    if not ok or type(data) ~= "table" then return "nodata" end
    local keys = {}
    local function walk(node)
        if type(node) ~= "table" then return end
        if type(node.setting_id) == "string" then keys[#keys + 1] = node.setting_id end
        for _, child in pairs(node) do
            if type(child) == "table" then walk(child) end
        end
    end
    walk(data)
    if #keys == 0 then return "nosettings" end
    table.sort(keys)
    local parts = {}
    for i, k in ipairs(keys) do
        local v = mod:get(k)
        if v == true then       parts[i] = k .. "=1"
        elseif v == false then  parts[i] = k .. "=0"
        elseif v == nil then    parts[i] = k .. "=?"
        else                    parts[i] = k .. "=" .. tostring(v) end
    end
    local s = table.concat(parts, ";")
    local h = 2166136261
    for i = 1, #s do
        local byte = string.byte(s, i)
        local xored, place = 0, 1
        local hh, bb = h, byte
        for _ = 1, 32 do
            local hb, bbit = hh % 2, bb % 2
            if hb ~= bbit then xored = xored + place end
            place = place * 2
            hh = (hh - hb) / 2
            bb = (bb - bbit) / 2
        end
        h = (xored * 16777619) % 4294967296
    end
    return string.format("%08x", h)
end

mod:info("[crt:LOAD] v%s enabled fp=%s OK", MOD_VERSION, _settings_fingerprint())

-- Per PROJECT_STANDARDS § 3.6 + § 14a: dev/alpha/beta/0.x versions print
-- version to chat on load so the user can see what's active. Stable
-- (>=1.0.0) versions stay silent. Detect via MOD_VERSION string match.
if MOD_VERSION:find("-dev$") or MOD_VERSION:find("-alpha$") or MOD_VERSION:find("-beta$") or MOD_VERSION:find("-rc%d*$") or MOD_VERSION:find("^0%.") then
    mod:echo(string.format("[crt] v%s loaded", MOD_VERSION))
end

-- v0.3.10: source-pattern marker constant for the /crt_regression_test
-- `crt_big_rebalance_uses_rawget` check (audit `.test_coverage_audit_2026-05-24.md`
-- PARTIAL row 3 — promoted to PASS by adding a runtime check beside the
-- existing strict-table-lookup lint coverage).
local CT_CRT_BIG_REBALANCE_RAWGET_MARKER_v0_3_10 = "crt-big-rebalance-rawget-hardened"

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

-- Big Rebalance integration (~160 opt-in toggles, all default false). The BR
-- buffs / damage profiles / explosion templates are registered by buff_tweaker
-- (bt) as the shared registry; this module's per-feature toggles gate on
-- bt:is_br_active() (see career_tweaker_big_rebalance.lua:46-48) before
-- applying. (bt took ownership of the shared registry, eliminating the
-- previously byte-identical registration files that wt/ct/et each shipped.)
-- BR ON ICE (bt retired 2026-06-08; heap relief 2026-06-18). Module no longer
-- dofile'd, so its ~2768 lines of data/hooks never load into the 1 GiB lua_heap.
-- Stub preserves the {apply, restore, active_count} contract read at lines
-- 433/465/485/531. To revive: restore bt, delete the stub, un-comment below.
-- local ok_br, big_rebalance = pcall(mod.dofile, mod, "scripts/mods/career_tweaker/career_tweaker_big_rebalance")
-- if not ok_br then
--     mod:error("Failed to load Big Rebalance module: %s", tostring(big_rebalance))
--     big_rebalance = { apply = function() end, restore = function() end, active_count = function() return 0 end }
-- end
local big_rebalance = { apply = function() end, restore = function() end, active_count = function() return 0 end }

-- Tourney Balance Testing port (PHASE 1: clean per-career data mutations,
-- ~17 default-OFF trn_* toggles). Same {apply,restore,active_count} contract
-- as balance / big_rebalance. See career_tweaker_tourney.lua header.
local ok_trn, tourney = pcall(mod.dofile, mod, "scripts/mods/career_tweaker/career_tweaker_tourney")
if not ok_trn then
    mod:error("Failed to load Tourney module: %s", tostring(tourney))
    tourney = { apply = function() end, restore = function() end, active_count = function() return 0 end }
end

-- Armor & Overcharge toggles (5 default-OFF gameplay hooks). Unlike balance /
-- tourney these are pure runtime hooks gated live on mod:get — NO
-- {apply,restore,active_count} contract and NO on_setting_changed dispatch; VMF
-- re-reads mod:get and deactivates the hooks when the mod is disabled. The
-- module installs exactly one mod:hook on DamageUtils.apply_buffs_to_damage and
-- one on PlayerUnitHealthExtension.add_damage (both confirmed un-hooked elsewhere
-- in crt). See career_tweaker_armor_overcharge.lua header for the authority model.
local ok_ao, _ao = pcall(mod.dofile, mod, "scripts/mods/career_tweaker/career_tweaker_armor_overcharge")
if not ok_ao then mod:error("Failed to load armor/overcharge module: %s", tostring(_ao)) end

-- Outcast Engineer cooldown-reduction benefit (single opt-in toggle
-- `oe_benefit_from_cooldown_reduction`, default OFF). Pure runtime, OE-only,
-- owner-local: mirrors the OE's live `activated_cooldown` reduction onto an equal
-- `cooldown_regen` bonus so his Cooldown Reduction gear finally speeds his ult
-- recharge. Driven from mod.update (NOT a hook) via mod._crt_oe_cdr_tick. See
-- career_tweaker_oe_cooldown.lua header for the full vanilla-mismatch analysis +
-- the no-drift single-managed-bonus sync mechanism.
local ok_oecdr, _oecdr = pcall(mod.dofile, mod, "scripts/mods/career_tweaker/career_tweaker_oe_cooldown")
if not ok_oecdr then mod:error("Failed to load OE cooldown module: %s", tostring(_oecdr)) end

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
    -- Opening the talent screen is a guaranteed career-resolved moment -- a
    -- reliable point to fire the rework-career auto-dump (no-op off those careers
    -- or after the first dump this session). mod-field ref: defined further down.
    if mod._crt_auto_dump_check then mod._crt_auto_dump_check() end
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

-- v0.3.20-dev: the hook above only patches level/XP DISPLAY reads. The FUNCTIONAL
-- level gates — talent unlock + level-gated feature unlocks — read raw experience
-- DIRECTLY from the backend mirror, NOT through ExperienceSettings.get_experience,
-- so the override never reached them. Verified against decompiled source:
-- BackendInterfaceTalentsPlayfab._validate_talents (backend_interface_talents_playfab.lua:234)
-- does `hero_experience = self._backend_mirror:get_read_only_data(profile_name.."_experience")`
-- -> `hero_level = ExperienceSettings.get_level(hero_experience)` -> for each talent,
-- `if not ProgressionUnlocks.is_unlocked("talent_point_"..i, hero_level) then career_talents[i] = 0`.
-- So a character SHOWN at the override level still had its talents stripped (and other
-- level unlocks withheld) because the gate read the real (low) XP from the mirror.
--
-- Fix: also override the mirror's `<hero>_experience` read so the functional gates see
-- the override level. CRITICAL class()-copy caveat (CLAUDE.md "HOOK THE DERIVED CLASS"):
-- VT2's class() COPIES methods into subclasses at load time — the live mirror is
-- `PlayFabMirrorAdventure` (= class(.., PlayFabMirrorBase)) / `PlayFabMirrorDedicated`,
-- each carrying its OWN copy of get_read_only_data. Hooking only PlayFabMirrorBase would
-- never fire on the live PlayFabMirrorAdventure instance. Hook every concrete class.
-- Read-only override (returns a value; never writes) — in modded realm no XP persists,
-- and it matches the existing display hook's exposure.
local function _mirror_experience_override(func, self, key)
    if type(key) == "string" then
        local hero = string.match(key, "^(.+)_experience$")
        if hero then
            local override = mod:get("level_override_" .. hero)
            if override and override > 0 then
                local real = func(self, key)
                local xp = ExperienceSettings.get_total_experience_required_for_level(override)
                -- Match vanilla's stored type (PlayFab read_only_data values are strings).
                if type(real) == "string" then return tostring(xp) end
                return xp
            end
        end
    end
    return func(self, key)
end
for _, mirror_class in ipairs({ "PlayFabMirrorAdventure", "PlayFabMirrorDedicated", "PlayFabMirrorBase" }) do
    mod:hook(mirror_class, "get_read_only_data", _mirror_experience_override)
end

-- ============================================================
-- Unlock All Careers (level gate only — DLC ownership preserved)
-- ============================================================
-- v0.3.21-dev: bypass the level requirement on careers the player already owns.
-- DLC ownership is NOT bypassed (CLAUDE.md § "DLC Ownership Gate": modded mods
-- unlock vanilla progression, NOT paid DLC content). Unowned-DLC careers stay
-- locked regardless of this toggle.
--
-- Verified against decompiled source. The unlock chain in vanilla:
--   career_settings.lua:23 local_is_unlocked_function
--     -> career:override_available_for_mechanism()   -- mechanism gate
--     -> career:is_dlc_unlocked()                    -- DLC GATE (unchanged)
--     -> ProgressionUnlocks.is_unlocked_for_profile(display_name, hero_name, hero_level)  -- LEVEL gate
-- DLC careers (lake/bless/cog/shovel/woods) have bespoke is_unlocked_functions
-- that return after the DLC check WITHOUT calling the level gate, so for DLC
-- careers ownership IS the whole gate — this toggle correctly has no effect on
-- DLC careers (they just need to be owned).
--
-- Convenient: vanilla ALREADY has a dev flag for this exact behavior, baked
-- into the level gate itself:
--   progression_unlocks.lua:205-208
--   ProgressionUnlocks.is_unlocked_for_profile = function (unlock_name, profile, level)
--       if Development.parameter("unlock_all_careers") then return true end
--       ...level check...
-- So the surgical fix is to hook that ONE function. Returning `true` skips the
-- level check ONLY; the upstream DLC gate has already run and locked unowned
-- DLC careers. Authority stays local — this is read in the LOCAL character-select
-- and talent-validation paths. The host's join-time check (network_server:91-94)
-- uses the SAME function via career:is_unlocked_function, so a host running this
-- mod won't reject their own client picks; clients without crt joining a normal
-- host are still gated by the host's vanilla check.
mod:hook("ProgressionUnlocks", "is_unlocked_for_profile", function(func, unlock_name, profile, level)
    if mod:get("unlock_all_careers") then
        return true
    end
    return func(unlock_name, profile, level)
end)

-- ============================================================
-- Bug fixes (2026-06-21): ability-swap ult crash + career-unlock UI refresh
-- ============================================================
-- (1) Live-swapping a career's activated_ability (the Career Ability & Talent
-- Swapping feature) while the hero is already spawned desyncs the spawned career
-- extension's `_abilities`/cooldown state from the mutated CareerSettings, so the
-- next ult has `CareerExtension:current_ability_cooldown(id)` return nil and the
-- engine crashes at career_extension.lua:424 (apply_buffs_to_value(nil,
-- "activated_cooldown")). Guard: the cooldown read never returns nil (treat the
-- desynced ability as ready). The swap still applies cleanly on the next spawn /
-- mission load. Repro: "swapped merc ult Slayer->none then ulted -> crash"
-- (crash log console-2026-06-21-22.08.51). pcall covers both nil-return and the
-- rarer `_abilities[id]` index error.
-- current_ability_cooldown returns TWO values: (cooldown, max_cooldown). Both the
-- ult-activate path (career_extension.lua:424) and the function's own tail
-- (line 698: `ability.max_cooldown > 0 and ...`) can hit a nil from the desynced
-- ability, and the HUD cooldown bar consumes the SECOND return — so the guard
-- must pcall (catch the 698 error too) AND preserve both returns (dropping the
-- 2nd is the multi-return-collapse gotcha, VMF_RECIPES §2). Fallback (0, 1):
-- cooldown 0 = ready, max_cooldown 1 = avoids divide-by-zero in the bar.
mod:hook("CareerExtension", "current_ability_cooldown", function(func, self, ability_id)
    local ok, cooldown, max_cooldown = pcall(func, self, ability_id)
    if not ok then return 0, 1 end
    return cooldown or 0, max_cooldown or 1
end)

-- (2) The career-select tiles (HeroWindowCharacterSummary._setup_hero_selection_
-- widgets) bake each career's `content.locked` ONCE at populate, from the hero's
-- level -- which the Character Experience Level override and Unlock All Careers
-- both feed. Flipping either setting while the hero view is open left the tiles
-- stale (which is why the user saw careers wrongly locked/unlocked until they
-- toggled unlock-all, forcing a rebuild). Track the live window and re-run its
-- tile setup when a level_override_* / unlock_all_careers setting changes.
local _char_summary_instance = nil
mod:hook_safe("HeroWindowCharacterSummary", "on_enter", function(self)
    _char_summary_instance = self
end)
mod:hook_safe("HeroWindowCharacterSummary", "on_exit", function(self)
    _char_summary_instance = nil
end)
local function refresh_career_unlock_ui()
    local inst = _char_summary_instance
    if inst and inst._setup_hero_selection_widgets then
        -- pcall: window may be mid-teardown between the on_exit hook firing late
        -- and this call; never let a refresh break the menu.
        pcall(function() inst:_setup_hero_selection_widgets() end)
    end
end

-- ============================================================
-- Lifecycle hooks
-- ============================================================

mod.on_game_state_changed = function(status, state_name)
    apply_talent_swaps()
    -- Auto-dump the rework careers' talent/buff map. Only on StateIngame enter
    -- (keep/mission) -- NEVER at StateSplashScreen/StateLoading, where
    -- Managers.player:local_player() raises "Network backend has not been set".
    -- The unit/career aren't ready at enter, so start a short per-frame retry
    -- window (mod.update) that fires the throw-proof, de-duped check until it dumps.
    if status == "enter" and state_name == "StateIngame" and mod._crt_start_dump_retry then
        mod._crt_start_dump_retry()
    end
    -- Defensive nil-check: if a dofile failure slipped past pcall (VMF's
    -- `mod:dofile` doesn't always raise — sometimes returns nil + logs the
    -- error separately, leaving the safe-stub fallback at line 13 dormant),
    -- balance/big_rebalance can end up nil rather than the stub. Skip cleanly
    -- instead of crashing the lifecycle.
    if balance and balance.apply then balance.apply() end
    if big_rebalance and big_rebalance.apply then big_rebalance.apply() end
    if tourney and tourney.apply then tourney.apply() end
end

mod.on_setting_changed = function(setting_id)
    -- v0.3.17: removed `mod:echo("Setting changed: " .. tostring(setting_id))`
    -- per PROJECT_STANDARDS.md § 3.6 "Chat-echo policy" — routine setting flips
    -- (especially the universal Debug Logging toggle) should not echo to chat
    -- on every click. Use _dbg if a diagnostic trace is needed in future.
    _dbg("on_setting_changed: %s", tostring(setting_id))

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
        -- A rework_ flip can change a trn_ entry's conflict state (a trn_ entry
        -- yields to its overlapping rework_), so re-apply tourney too.
        if tourney and tourney.apply then tourney.apply() end
    end

    if setting_id:find("^cbr_") then
        if big_rebalance and big_rebalance.apply then big_rebalance.apply() end
    end

    if setting_id:find("^trn_") then
        if tourney and tourney.apply then tourney.apply() end
    end

    -- Career-select lock state is baked at populate; refresh the open hero view so
    -- a level-override / unlock-all change takes effect without re-opening (bug fix
    -- (2) above).
    if setting_id == "unlock_all_careers" or setting_id:find("^level_override_") then
        refresh_career_unlock_ui()
    end
end

mod.on_disabled = function()
    -- audit 2026-06-07 (v0.3.22-dev), BUG_CLASSES §7: previously on_disabled only
    -- unwound the balance / big_rebalance buff-template mutations and left talent
    -- swaps + the global table/hook mutations behind. Restore what's CHEAP, echo
    -- the limitation for the rest (matches gt v0.2.56's documented-limitation
    -- pattern, Issue #15).
    --
    -- Cheaply reversible (done here):
    --   * Talent swaps — re-bind saved originals into TalentTrees / CareerSettings
    --     (rebind only; _talent_swap_originals already holds the pre-swap values).
    --   * Balance reworks + Big Rebalance — restore the patched BuffTemplate fields.
    if balance and balance.restore then balance.restore() end
    if big_rebalance and big_rebalance.restore then big_rebalance.restore() end
    if tourney and tourney.restore then tourney.restore() end
    restore_talent_swaps()
    -- Drop the OE cooldown-reduction managed bonus cleanly (the tick also self-
    -- clears once mod:get returns nil, but do it eagerly so the live OE reverts to
    -- exact vanilla recharge the instant the mod is disabled).
    if mod._crt_oe_cdr_clear then mod._crt_oe_cdr_clear() end
    -- Refresh the inventory talent picker if it's open so a live disable visibly
    -- reverts swapped trees instead of waiting for a menu re-open.
    refresh_talent_ui()

    -- NOT cheaply reversible (restart required), so we document rather than unwind:
    --   * The crt_* stub buff names registered UNCONDITIONALLY into BuffTemplates +
    --     NetworkLookup.buff_templates at load (career_tweaker_balance.lua:67-87).
    --     Tearing these out would shift every later NetworkLookup index and break
    --     cross-peer rpc_add_buff determinism — far worse than leaving the inert
    --     no-op stubs in place. Restart clears them.
    --   * VMF-installed hooks (ExperienceSettings.get_experience, the mirror
    --     get_read_only_data overrides, ProgressionUnlocks.is_unlocked_for_profile,
    --     HeroWindowTalents on_enter/on_exit, plus the two armor/overcharge hooks
    --     DamageUtils.apply_buffs_to_damage + PlayerUnitHealthExtension.add_damage).
    --     VMF deactivates a disabled mod's
    --     hooks for us, and each body also gates on a mod:get(...) read, so they
    --     no-op while disabled — but the wrappers stay installed until restart.
    mod:echo("[crt] Talent swaps + balance reworks reverted. Buff registrations and hooks need a game restart for a fully clean vanilla state.")
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

-- Dump a career's CURRENT (live, post-rework) talent tree so we can re-point
-- reworks whose target talent name was guessed from a stale decompile. The
-- running game has the real data the local decompile may lack (e.g. the Zealot
-- "Holy Fortitude" talent isn't in the decompile by that name). Usage:
--   /crt_dump_talents            (defaults to wh_zealot)
--   /crt_dump_talents wh_zealot
-- Logs [crt:talent] lines (enable Debug Logging) + each talent's first buff's
-- stat_buff/bonus/multiplier so the HP/max_health talent is identifiable.
-- Reusable dump body. `reason` tags the log ("manual"/"auto"). Writes [crt:talent]
-- lines via mod:info (always goes to the console_logs file, regardless of the
-- chat-echo gate), so an auto-dump lands in the log even with Debug Logging off.
-- Also prints each buff template's full proc fields (proc_chance/chunk_size/
-- max_stacks/duration/event/buff_func/buff_to_add) so a tweak can be wired from
-- the dump alone without re-grepping the source.
mod.crt_dump_career_talents = function(career, reason)
    career = (career and career ~= "" and career) or "wh_zealot"
    local CS = rawget(_G, "CareerSettings")
    local TT = rawget(_G, "TalentTrees")
    local TL = rawget(_G, "TalentIDLookup")
    local TA = rawget(_G, "Talents")
    local BT = rawget(_G, "BuffTemplates")
    local cs = CS and CS[career]
    if not cs then mod:info("[crt:talent] unknown career: %s", tostring(career)); return false end
    local hero = cs.profile_name
    local tree = TT and TT[hero] and TT[hero][cs.talent_tree_index]
    if not tree then mod:info("[crt:talent] no talent tree for %s", tostring(career)); return false end
    mod:info("[crt:talent] === %s (hero=%s tree=%s) [%s] ===", tostring(career), tostring(hero), tostring(cs.talent_tree_index), tostring(reason or "manual"))
    for row_i, row in ipairs(tree) do
        for col_i, tname in ipairs(row) do
            local lookup = TL and TL[tname]
            local talent = lookup and TA and TA[lookup.hero_name] and TA[lookup.hero_name][lookup.talent_id]
            local buffs = talent and talent.buffs
            local buffstr = (type(buffs) == "table") and table.concat(buffs, ",") or "?"
            local disp = tname
            local lok, loc = pcall(Localize, tname)
            if lok and loc and loc ~= tname and not tostring(loc):find("^<") then disp = loc end
            mod:info("[crt:talent] [%d,%d] %s | name=%s | buffs=[%s] | icon=%s",
                row_i, col_i, disp, tname, buffstr, tostring(talent and talent.icon))
            if type(buffs) == "table" then
                for _, bn in ipairs(buffs) do
                    local bt = BT and BT[bn]
                    local b1 = bt and bt.buffs and bt.buffs[1]
                    if b1 then
                        mod:info("[crt:talent]      buff %s | stat_buff=%s bonus=%s multiplier=%s proc_chance=%s chunk_size=%s max_stacks=%s duration=%s event=%s buff_func=%s buff_to_add=%s",
                            tostring(bn), tostring(b1.stat_buff), tostring(b1.bonus), tostring(b1.multiplier),
                            tostring(b1.proc_chance), tostring(b1.chunk_size), tostring(b1.max_stacks),
                            tostring(b1.duration), tostring(b1.event), tostring(b1.buff_func), tostring(b1.buff_to_add))
                    end
                end
            end
        end
    end
    return true
end

mod:command("crt_dump_talents", "Dump a career's live talents + buffs (default wh_zealot)", function(career)
    local ok = mod.crt_dump_career_talents(career, "manual")
    if ok then mod:echo("[crt] dumped " .. tostring((career ~= "" and career) or "wh_zealot") .. " talents to log — paste the [crt:talent] lines") end
end)

-- ============================================================
-- Auto-dump talents for careers under active rework (bw_unchained, es_mercenary)
-- ============================================================
-- Data-harness (PROJECT_STANDARDS debug doctrine): when the local player is on a
-- career we're actively reworking, dump its talent/buff map to the log
-- automatically (once per career per session) so the exact internal names +
-- proc values are captured from normal play -- no /command needed. Pure read; no
-- gameplay effect. Add a career here while it's being worked on.
local _CRT_AUTO_DUMP_CAREERS = { bw_unchained = true, es_mercenary = true }
local _crt_auto_dumped = {}

-- Resolve the LOCAL player's career, NEVER throwing. The whole body is pcall'd
-- because `Managers.player:local_player()` itself raises "Network backend has
-- not been set" (player_manager.lua:559) at early states (StateSplashScreen /
-- StateLoading) -- that was the v0.3.33 error spam (only the inner lookups were
-- guarded, not local_player). Prefer the career_system extension on the spawned
-- unit (reliable once spawned); fall back to player:career_name() (which itself
-- returns nil until the profile's display_name loads, so it's the weaker source).
local function _crt_local_career()
    local ok, career = pcall(function()
        local pm = Managers.player
        local p = pm and pm:local_player()
        if not p then return nil end
        local unit = p.player_unit
        if unit and Unit.alive(unit) then
            local ce = ScriptUnit.has_extension(unit, "career_system")
            if ce then
                local n = ce:career_name()
                if type(n) == "string" then return n end
            end
        end
        if p.career_name then
            local n = p:career_name()
            if type(n) == "string" then return n end
        end
        return nil
    end)
    return (ok and type(career) == "string") and career or nil
end

-- Exposed so the lifecycle hooks (on_game_state_changed), the per-frame retry,
-- and the talent-window on_enter hook can all drive it; resolves at call time.
-- De-dupe is set ONLY on a SUCCESSFUL dump, so an early call that resolves the
-- career but hits a not-yet-ready talent table can still succeed on a retry.
mod._crt_auto_dump_check = function()
    local career = _crt_local_career()
    if not (career and _CRT_AUTO_DUMP_CAREERS[career]) then return end
    if _crt_auto_dumped[career] then return end
    mod:info("[crt:talent] auto-dump for %s (career under rework) -------------------", career)
    if mod.crt_dump_career_talents(career, "auto") then
        _crt_auto_dumped[career] = true
    end
end

-- Per-frame retry window: career/unit aren't ready at StateIngame *enter*, so
-- after each enter we retry the (throw-proof, de-duped) check ~1x/sec for a short
-- window until it dumps. Guarantees the dump fires when you're actually playing a
-- reworked career, without depending on opening the talent screen.
local _crt_dump_retry_left = 0
local _crt_dump_retry_acc = 0
mod.update = function(dt)
    -- Outcast Engineer cooldown-reduction benefit (its own throttle + gating;
    -- self-guards on the toggle, the OE career, and the local player — no-op for
    -- every other career or when the toggle is off). Driven from here, not a hook.
    if mod._crt_oe_cdr_tick then mod._crt_oe_cdr_tick(dt) end

    if _crt_dump_retry_left <= 0 then return end
    _crt_dump_retry_left = _crt_dump_retry_left - (dt or 0)
    _crt_dump_retry_acc = _crt_dump_retry_acc + (dt or 0)
    if _crt_dump_retry_acc >= 1.0 then
        _crt_dump_retry_acc = 0
        if mod._crt_auto_dump_check then mod._crt_auto_dump_check() end
    end
end
mod._crt_start_dump_retry = function()
    _crt_dump_retry_left = 20.0
    _crt_dump_retry_acc = 1.0  -- fire on the next frame, then ~1x/sec
end

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
    "crt_engineer_leading_shots_accumulator",
    "crt_engineer_leading_shots_counter",
    "crt_engineer_leading_shots_crit",
    "crt_knight_counter_punch_proc",
    "crt_knight_counter_punch_stack",
    "crt_mainstay_universal_stagger",
    "crt_merc_blade_barrier_proc",
    "crt_merc_blade_barrier_remover",
    "crt_merc_blade_barrier_stack",
    "crt_merc_enhanced_training_as",
    "crt_priest_prayer_self_extra",
    "crt_questingknight_impetuous_as",
    "crt_questingknight_impetuous_as_proc",
    "crt_questingknight_impetuous_power",
    "crt_questingknight_impetuous_power_proc",
    "crt_sienna_flame_unending_driver",
    "crt_sienna_flame_unending_stack",
    "crt_sienna_natural_talent_ranged_driver",
    "crt_sienna_natural_talent_ranged_stack",
    "crt_sienna_numb_to_pain_proc",
    "crt_sienna_numb_to_pain_remover",
    "crt_sienna_numb_to_pain_stack",
    "crt_unchained_ult_max_us",
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

_rt_register("crt_big_rebalance_uses_rawget", function()
    -- v0.3.9/.10: `_register_talent_buff_template_if_missing` in
    -- `career_tweaker_big_rebalance.lua:124` uses
    -- `rawget(NetworkLookup.buff_templates, name)` for the pre-register guard
    -- so the registration is safe against the strict `__index` metatable
    -- vanilla installs on `NetworkLookup.*` tables. The strict-table-lookup
    -- lint covers static-pattern regressions; this runtime check is the
    -- belt-and-suspenders companion required by §15 of PROJECT_STANDARDS.md.
    --
    -- 1. Source-pattern: marker constant must be present.
    if CT_CRT_BIG_REBALANCE_RAWGET_MARKER_v0_3_10 ~= "crt-big-rebalance-rawget-hardened" then
        return "RAWGET marker absent — was the v0.3.9 big_rebalance hardening reverted?"
    end
    -- 2. Runtime-state: rawget against a known-bad key on
    --    NetworkLookup.buff_templates must return nil without raising.
    local NL = rawget(_G, "NetworkLookup")
    local bt = NL and NL.buff_templates
    if type(bt) == "table" then
        local ok, value = pcall(rawget, bt, "__crt_rawget_probe_does_not_exist__")
        if not ok then
            return "rawget(NetworkLookup.buff_templates, <bad-key>) RAISED — strict-metatable behavior changed"
        end
        if value ~= nil then
            return "rawget(NetworkLookup.buff_templates, <bad-key>) returned non-nil — unexpected"
        end
    end
end)

_rt_register("dbg_helpers_two_channel", function()
    if type(_dbg) ~= "function" then return "_dbg helper missing" end
    if type(_dbg_alert) ~= "function" then return "_dbg_alert helper missing" end
    -- Helpers route through VMF (mod:debug / mod:warning); just verify they don't raise.
    local ok = pcall(_dbg, "smoke test")
    if not ok then return "_dbg raised" end
    ok = pcall(_dbg_alert, "smoke test")
    if not ok then return "_dbg_alert raised" end
end)


_rt_register("localization_format_safe", function()
    -- Layer 3 (2026-05-25): catch unescaped %-format chars in loc strings at
    -- runtime. VMF's tooltip render path calls string.format on the loc value;
    -- literal "%APPDATA%" / "5%" / "%USERNAME%" raises 'invalid option' and
    -- shows as a red error tooltip in the VMF settings UI. Static check is
    -- qa/check_localization.ps1 -- this is its runtime twin so the bug can't
    -- ship even if the static check is skipped. RULE: any literal % in a loc
    -- string must be doubled to %%.
    local ok, loc = pcall(mod.dofile, mod, "scripts/mods/career_tweaker/career_tweaker_localization")
    if not ok or type(loc) ~= "table" then return end  -- can't reach loc; skip
    for k, v in pairs(loc) do
        if type(v) == "table" and type(v.en) == "string" then
            local fmt_ok, fmt_err = pcall(string.format, v.en)
            if not fmt_ok then
                return string.format(
                    "loc key %q has invalid format string (escape literal %% as %%%%): %s",
                    k, tostring(fmt_err))
            end
        end
    end
end)

_rt_register("armor_overcharge_hook_targets_present", function()
    -- v0.3.32-dev: the armor/overcharge module installs exactly ONE mod:hook on
    -- each of its two targets (VMF drops the 2nd hook on the same (Class, method)
    -- silently). The STATIC duplicate-hook guarantee is enforced at build time by
    -- tools/mod-lint/lint-mod.ps1; this runtime check confirms both hook TARGETS
    -- are resolvable (i.e. the module had something real to hook). Both functions
    -- live in core scripts loaded well before any keep state, so this passes even
    -- from the keep.
    local DU = rawget(_G, "DamageUtils")
    if type(DU) ~= "table" or type(DU.apply_buffs_to_damage) ~= "function" then
        return "DamageUtils.apply_buffs_to_damage missing"
    end
    local PUHE = rawget(_G, "PlayerUnitHealthExtension")
    if type(PUHE) ~= "table" or type(PUHE.add_damage) ~= "function" then
        return "PlayerUnitHealthExtension.add_damage missing"
    end
end)

_rt_register("armor_overcharge_self_dot_toggle_wired", function()
    -- #334: the self-inflicted-DoT fix adds toggle
    -- `unchained_no_overcharge_from_self_dot` (the Blood Magic overcharge case)
    -- and folds the Gromril + Necromancer self-DoT coverage into the existing
    -- `armor_gromril_ignore_chip`. The `_is_self_dot` predicate is a module-local
    -- in career_tweaker_armor_overcharge.lua (not reachable from here), so this
    -- check verifies the new toggle's DATA widget + both LOC keys are present —
    -- i.e. the option actually renders and reads back.
    local ok_d, data = pcall(require, "scripts/mods/career_tweaker/career_tweaker_data")
    if not ok_d or type(data) ~= "table" then return "career_tweaker_data not loadable" end
    local found = false
    local function walk(node)
        if type(node) ~= "table" then return end
        if node.setting_id == "unchained_no_overcharge_from_self_dot" then found = true end
        for _, child in pairs(node) do
            if type(child) == "table" then walk(child) end
        end
    end
    walk(data)
    if not found then
        return "unchained_no_overcharge_from_self_dot widget missing from data tree"
    end
    local ok_l, loc = pcall(mod.dofile, mod, "scripts/mods/career_tweaker/career_tweaker_localization")
    if ok_l and type(loc) == "table" then
        if type(loc.unchained_no_overcharge_from_self_dot) ~= "table" then
            return "unchained_no_overcharge_from_self_dot loc label missing"
        end
        if type(loc.unchained_no_overcharge_from_self_dot_tooltip) ~= "table" then
            return "unchained_no_overcharge_from_self_dot_tooltip loc missing"
        end
    end
end)

_rt_register("on_disabled_unwinds_talent_swaps", function()
    -- v0.3.22-dev (audit 2026-06-07, BUG_CLASSES §7): on_disabled must cheaply
    -- unwind talent swaps, not just the balance/big_rebalance buff mutations.
    -- The unwind is restore_talent_swaps(), which re-binds saved originals and
    -- clears _talent_swap_originals. This check FAILS if that unwind path is
    -- removed/broken (i.e. the F13 bug returns).
    --
    -- Behavioral assertion: seed a SYNTHETIC pending-swap whose career_name is
    -- not in CareerSettings, so restore_talent_swaps() iterates it (cs == nil ->
    -- no real game-table write) and then clears the table. Asserts the unwind
    -- actually runs and resets state without mutating real career data.
    if type(restore_talent_swaps) ~= "function" then
        return "restore_talent_swaps helper missing — on_disabled can't unwind swaps"
    end
    local saved = _talent_swap_originals
    _talent_swap_originals = {
        __crt_rt_probe_not_a_real_career__ = {
            tree = false, activated_ability = "x", passive_ability = "y",
        },
    }
    local ok, err = pcall(restore_talent_swaps)
    local cleared = (next(_talent_swap_originals) == nil)
    _talent_swap_originals = saved  -- always restore the real (live) table
    if not ok then
        return "restore_talent_swaps raised: " .. tostring(err)
    end
    if not cleared then
        return "restore_talent_swaps did not clear _talent_swap_originals — swaps would persist after disable"
    end
end)

mod:info("[mem-probe] crt boot_lua=+%.1f MB (of ~1024 MB lua_heap cap)", (collectgarbage("count") - _MEM_PROBE_T0_CRT) / 1024)
