local mod = get_mod("crt")
-- Shared namespace for the Phase-1 module split (v0.3.57-dev). Every _crt_*.lua
-- concern module and this entry's lifecycle callbacks read/write it.
mod._crt = mod._crt or {}

local MOD_VERSION = "0.4.9-beta"
mod._crt.MOD_VERSION = MOD_VERSION

-- VMF mod-to-mod RPC schema (VMF_RECIPES section 10). Issue #776 appends the
-- exact wire-catalog identity to the issue-425 beacon transport.
local CRT_RPC_SCHEMA = 2
_MEM_PROBE_T0_CRT = collectgarbage("count")  -- [mem-probe] temp Lua-footprint baseline (lua_heap 1 GiB cap diagnostic)
-- Startup banner: log-only, NOT chat. The applied marker line further down
-- ([crt] enabled v<X> settings_fp=<hash>) is the canonical version surface
-- (PROJECT_STANDARDS.md § 3.6 "Chat-echo policy").
mod:info("Career Tweaker v%s loaded", MOD_VERSION)

-- Two-helper debug-logging policy (PROJECT_STANDARDS.md § 3.6).
-- `_dbg` is for confirmation / expected behavior — mod:debug (file only,
-- gated by VMF output_mode_debug).
-- `_dbg_alert` is for unexpected / wrong / mismatch — LOG-ONLY via
-- pcall-guarded engine printf (#427/issue 240: mod:warning posts to CHAT
-- under VMF defaults - logging.lua warning mode 3, send_to_chat = mode >= 2;
-- printf always lands in console-*.log, even with mod logging OFF, and never
-- in chat; pcall so a format slip never faults the caller).
local function _dbg(fmt, ...)
    mod:debug("[crt:dbg] " .. fmt, ...)
end

local function _dbg_alert(fmt, ...)
    if not pcall(printf, "[crt:dbg] " .. fmt, ...) then
        pcall(printf, "[crt:dbg] (alert format error: %s)", tostring(fmt))
    end
end
-- Exported for _crt_regression.lua's dbg_helpers_two_channel check. The entry
-- still calls the file-locals directly (on_setting_changed).
mod._crt.dbg = _dbg
mod._crt.dbg_alert = _dbg_alert

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

-- ============================================================
-- Concern modules (Phase 1 OOP split, v0.3.57-dev)
-- ============================================================
-- Pure damage-category policy must load before the armor/overcharge consumer.
-- It contains no hooks or engine reads and is shared through mod._crt.
mod._crt.damage_classification = mod:dofile("scripts/mods/career_tweaker/_crt_damage_classification")
-- Pure issue-776 wire contract. The balance catalog consumes its timed-buff
-- constants; the beacon and receiver floor consume its exact catalog policy.
mod._crt.wire_policy = mod:dofile("scripts/mods/career_tweaker/_crt_wire_policy")

-- Safe-stub fallback (CHANGELOG 0.2.2): if dofile fails we substitute no-op
-- functions so on_game_state_changed / on_setting_changed / on_disabled
-- (which all call balance.apply / balance.restore) don't crash.
local ok, balance = pcall(mod.dofile, mod, "scripts/mods/career_tweaker/career_tweaker_balance")
if not ok then
    mod:error("Failed to load balance module: %s", tostring(balance))
    balance = { apply = function() end, restore = function() end, active_count = function() return 0 end }
end
-- Export for _crt_regression.lua (crt_network_unsafe_catalog_parity reads
-- balance.network_unsafe_ids / parity_gate_ok / wire_parity_live). Real module
-- or the safe-stub above -- either way a table honoring the read contract.
mod._crt.balance = balance

-- Big Rebalance was retired under #321 and its unreachable implementation was
-- deleted under #433. Old cbr_* saved values remain untouched and reserved;
-- reactivation requires a new reviewed architecture recovered from git history.

-- Tourney Balance Testing port (PHASE 1: clean per-career data mutations,
-- ~17 default-OFF trn_* toggles). Same {apply,restore,active_count} contract
-- as the native balance engine. See career_tweaker_tourney.lua header.
local ok_trn, tourney = pcall(mod.dofile, mod, "scripts/mods/career_tweaker/career_tweaker_tourney")
if not ok_trn then
    mod:error("Failed to load Tourney module: %s", tostring(tourney))
    tourney = { apply = function() end, restore = function() end, active_count = function() return 0 end }
end

-- Issue #445: family-wide rework masters. The policy is engine-free and owns
-- catalog normalization/planning; this file owns the bounded VMF setting batch
-- and one final apply per engine. Retired cbr_* entries are deliberately absent.
local ok_rmp, rework_master_module = pcall(mod.dofile, mod,
    "scripts/mods/career_tweaker/_crt_rework_master_policy")
local rework_master_policy
if ok_rmp and type(rework_master_module) == "table" and type(rework_master_module.new) == "function" then
    rework_master_policy = rework_master_module.new(
        balance and balance.BALANCE_MODS or {},
        tourney and (tourney.TOGGLE_IDS or tourney.TOURNEY_MODS) or {})
else
    mod:error("Failed to load rework-master policy: %s", tostring(rework_master_module))
    rework_master_module = {
        MASTER_ENSRICK = "rework_master_ensrick",
        MASTER_TOURNEY = "rework_master_tourney",
    }
    rework_master_policy = {
        ensrick_ids = {}, tourney_ids = {},
        is_member = function() return nil end,
        plan = function() return {} end,
        derive_masters = function() return {} end,
    }
end

local _rework_master_batch = false

-- Public-beta boundary: the #221 ownership census is an investigation probe,
-- not player-facing behavior. Its policy source remains available for future
-- development, but the beta neither loads it nor registers its command.
-- Former development call retained only as an audit breadcrumb:
-- umbrella_audit.snapshot(...), exposed through /crt_umbrella_audit.
mod._crt.PUBLIC_BETA_UMBRELLA_AUDIT_DISABLED = true

local function _rework_master_snapshot()
    local state = {}
    for _, id in ipairs(rework_master_policy.ensrick_ids or {}) do state[id] = mod:get(id) and true or false end
    for _, id in ipairs(rework_master_policy.tourney_ids or {}) do state[id] = mod:get(id) and true or false end
    state[rework_master_module.MASTER_ENSRICK] = mod:get(rework_master_module.MASTER_ENSRICK) and true or false
    state[rework_master_module.MASTER_TOURNEY] = mod:get(rework_master_module.MASTER_TOURNEY) and true or false
    return state
end

local function _write_rework_master_changes(changes)
    _rework_master_batch = true
    local ok, err = pcall(function()
        for i = 1, #changes do mod:set(changes[i].id, changes[i].value) end
    end)
    _rework_master_batch = false
    if not ok then
        mod:warning("[crt:445] family preset setting batch failed: %s", tostring(err))
        return false
    end
    return true
end

local function _apply_rework_master(family, enabled)
    local changes = rework_master_policy:plan(family, enabled, _rework_master_snapshot())
    if not _write_rework_master_changes(changes) then return end
    -- Every nested on_setting_changed callback returned under the batch guard;
    -- run each owner exactly once after the complete desired state is visible.
    if balance and balance.apply then balance.apply() end
    if tourney and tourney.apply then tourney.apply() end
    pcall(printf, "[crt:445] family=%s enabled=%s writes=%d ensrick=%d tourney=%d",
        tostring(family), tostring(enabled), #changes,
        #(rework_master_policy.ensrick_ids or {}), #(rework_master_policy.tourney_ids or {}))
end

local function _sync_rework_master_indicators()
    local desired = rework_master_policy:derive_masters(_rework_master_snapshot())
    local changes = {}
    for _, id in ipairs({ rework_master_module.MASTER_ENSRICK, rework_master_module.MASTER_TOURNEY }) do
        local value = desired[id] and true or false
        if (mod:get(id) and true or false) ~= value then
            changes[#changes + 1] = { id = id, value = value }
        end
    end
    _write_rework_master_changes(changes)
end

mod._crt.rework_master_policy = rework_master_policy
mod._crt.rework_master_module = rework_master_module

-- Issue #619: Foot Knight's capability-aware career mechanics load before the
-- armor module because that module owns crt's singleton
-- DamageUtils.apply_buffs_to_damage hook and delegates its outgoing multiplier
-- to this concern.  Custom buffs remain local-only and never enter NetworkLookup.
local ok_fk, foot_knight = pcall(mod.dofile, mod,
    "scripts/mods/career_tweaker/_crt_foot_knight")
if not ok_fk or type(foot_knight) ~= "table" then
    mod:error("Failed to load Foot Knight module: %s", tostring(foot_knight))
    foot_knight = {
        tick = function() end,
        apply_settings = function() end,
        restore = function() end,
        reset_mission_state = function() end,
        outgoing_damage_multiplier = function() return 1 end,
    }
end
mod._crt.foot_knight = foot_knight

-- Armor, Overcharge & Focused Spirit toggles (one default-ON exemption plus
-- six opt-in controls). Six controls are runtime hooks gated live on mod:get;
-- the stacking option's reversible template fields are owned by the balance
-- lifecycle. VMF re-reads the runtime settings when the mod is disabled. The
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
-- Expose the cluster registry for /crt_regression_test (issue 446 end-to-end
-- verify) and future diagnostics. CLUSTERS is the single source of truth for
-- every same-talent rival group crt declares.
mod._crt.mutex = mutex

-- Public-beta boundary: career talent/ability casting-transposition is excluded.
-- Do not load `_crt_talent_swap.lua`: loading it installs HeroWindowTalents
-- hooks and exposes apply/restore entry points. VMF retains the old saved
-- `talent_swap_*` values in user settings, but this beta never reads, writes,
-- clears, or applies them. A later redesign can therefore migrate the data.
mod._crt.PUBLIC_BETA_TALENT_SWAPS_DISABLED = true
mod._crt.apply_talent_swaps = nil
mod._crt.restore_talent_swaps = nil
mod._crt.refresh_talent_ui = nil
mod._crt.ALL_CAREERS = nil

-- Read-only talent/buff diagnostics: /crt_dump_talents + the auto-dump harness.
-- Exposes mod.crt_dump_career_talents, mod._crt_auto_dump_check,
-- mod._crt_dump_retry_tick, mod._crt_start_dump_retry (all mod-field-guarded at
-- their call sites, so load order relative to the lifecycle callbacks is free).
local ok_dg, _dg = pcall(mod.dofile, mod, "scripts/mods/career_tweaker/_crt_diagnostics")
if not ok_dg then mod:error("Failed to load diagnostics module: %s", tostring(_dg)) end

-- Public-beta boundary: the #440 co-op investigation probe is intentionally
-- inert. Its source remains available for a later diagnostic build, but no
-- gameplay/AI hooks are installed in this public beta.
mod._crt.PUBLIC_BETA_BARDIN_PROBE_DISABLED = true

-- Live #445/#446 group. Unlike the old BH example, both members are active and
-- visible; the retired cbr_* catalog is never used as a UI dependency.
mutex.declare("rework_family_master_choice", {
    rework_master_module.MASTER_ENSRICK,
    rework_master_module.MASTER_TOURNEY,
}, {
    control = "radio",
    label = "rework_family_master_choice_radio_group",
    none_label = "rework_choice_none_default",
})

-- #447 supplies the second Zealot green-to-THP design anticipated by #446.
-- They are alternative conversion models, so selecting one disables the other
-- in both the stock VMF options and Mod Tweaker's checkbox-radio bridge.
mutex.declare("zealot_thp_conversions", {
    "rework_wh_zealot_ability_green_to_thp",
    "rework_wh_zealot_flagellation",
}, {
    control = "radio",
    label = "zealot_thp_conversions_radio_group",
    none_label = "rework_choice_none_default",
})

-- ============================================================
-- Mod Tweaker mutually-exclusive groups (issue 446, Part 2)
-- ============================================================
-- Bridge crt's same-talent rival mutex clusters into gut's Mod Tweaker
-- "mutually-exclusive group" API (shipped gut_dev 0.2.222-dev). Inside the Mod
-- Tweaker menu, clicking one cluster member ON makes gut stage the siblings OFF
-- and repaint the rows -- a radio group over ordinary checkboxes (all-off = the
-- "None" state). This sits on TOP of crt's own on_setting_changed enforcement
-- (mutex.enforce), which also covers VMF's stock options menu; both layers agree
-- on the same siblings, so both firing on one flip is idempotent.
--
-- Best-effort, NO hard dependency: if gut is absent, or its mod_tweaker API is
-- missing, this is a silent no-op and crt behaves exactly as before. gut needs
-- no per-group code -- the registry is data-driven.
--
-- Single source of truth is crt's own mutex.CLUSTERS, so every cluster declared
-- via mutex.declare auto-registers here with no extra code. The first live group
-- is #445's native-vs-Tourney family preset pair. The earlier #446 demonstration
-- referenced a hidden cbr_* sibling and was removed when Big Rebalance retired.
--
-- Pre-existing both-ON state: neither layer reconciles a saved config where two
-- siblings are already ON at boot (both are change-triggered, not boot-sweeping).
-- We deliberately do NOT mod:set members at load -- the UI already prevents
-- both-ON, and the gut contract does not prescribe a boot sweep; enforcement
-- kicks in on the next member toggle.
--
-- dev/stable id resolution: external refs normally target the stable id, but the
-- user runs gut_dev and the mod_tweaker table lives on whichever gut variant is
-- installed. Resolve BOTH defensively and use whichever exposes the API.
mod._crt_exclusive_groups_ran    = false
mod._crt_exclusive_groups_status = "pending"
mod._crt_exclusive_groups_count  = 0
do
    local function _resolve_mod_tweaker()
        for _, gut_id in ipairs({ "gut_dev", "gut" }) do
            local gut = get_mod(gut_id)
            local mt  = gut and gut.mod_tweaker
            if mt and type(mt.register_exclusive_group) == "function" then
                return mt, gut_id
            end
        end
        return nil
    end

    local function _register_exclusive_groups()
        mod._crt_exclusive_groups_ran = true
        local mt, gut_id = _resolve_mod_tweaker()
        if not mt then
            mod._crt_exclusive_groups_status = "gut-absent"
            pcall(printf, "[crt:446] gut Mod Tweaker not present; exclusive-group registration skipped (crt unchanged)")
            return
        end
        local ok_all, count = true, 0
        for group_id, members in pairs(mutex.CLUSTERS or {}) do
            if type(members) == "table" and #members >= 2 then
                local payload = {}
                for i = 1, #members do
                    payload[i] = { mod = "crt", setting = members[i] }
                end
                local ok, err = mt:register_exclusive_group(
                    "crt_" .. group_id, payload, mutex.PRESENTATIONS[group_id])
                if ok then
                    count = count + 1
                else
                    ok_all = false
                    mod:warning("[crt:446] register_exclusive_group(crt_%s) rejected: %s", group_id, tostring(err))
                end
            end
        end
        mod._crt_exclusive_groups_count  = count
        mod._crt_exclusive_groups_status = ok_all and "ok" or "partial-fail"
        pcall(printf, "[crt:446] Mod Tweaker exclusive groups registered=%d via %s status=%s",
            count, gut_id, mod._crt_exclusive_groups_status)
    end

    -- on_all_mods_loaded fires once after every mod's main file has run, so gut's
    -- mod.mod_tweaker (set at gut load) is guaranteed present by now. crt defines
    -- no other on_all_mods_loaded, so a direct assignment is safe.
    mod.on_all_mods_loaded = function()
        local ok, err = pcall(_register_exclusive_groups)
        if not ok then
            mod._crt_exclusive_groups_status = "partial-fail"
            mod:warning("[crt:446] exclusive-group registration errored: %s", tostring(err))
        end
    end
end

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
    -- Auto-dump the rework careers' talent/buff map. Only on StateIngame enter
    -- (keep/mission) -- NEVER at StateSplashScreen/StateLoading, where
    -- Managers.player:local_player() raises "Network backend has not been set".
    -- The unit/career aren't ready at enter, so start a short per-frame retry
    -- window (mod.update) that fires the throw-proof, de-duped check until it dumps.
    if status == "enter" and state_name == "StateIngame" and mod._crt_start_dump_retry then
        mod._crt_start_dump_retry()
    end
    if status == "enter" and state_name == "StateIngame" then
        foot_knight.reset_mission_state()
    end
    -- Defensive nil-check: VMF's `mod:dofile` can return nil after logging an
    -- error instead of raising, so skip cleanly rather than crashing lifecycle.
    if balance and balance.apply then balance.apply() end
    if tourney and tourney.apply then tourney.apply() end
    foot_knight.apply_settings()
end

mod.on_setting_changed = function(setting_id)
    -- v0.3.17: removed `mod:echo("Setting changed: " .. tostring(setting_id))`
    -- per PROJECT_STANDARDS.md § 3.6 "Chat-echo policy" — routine setting flips
    -- (especially the universal Debug Logging toggle) should not echo to chat
    -- on every click. Use _dbg if a diagnostic trace is needed in future.
    _dbg("on_setting_changed: %s", tostring(setting_id))

    -- Programmatic leaf writes from a family preset are synchronous VMF
    -- callbacks. Suppress them so a 60+ setting preset remains one bounded
    -- owner apply rather than repeating full restore/apply work per leaf.
    if _rework_master_batch then return end

    if setting_id == rework_master_module.MASTER_ENSRICK then
        _apply_rework_master("ensrick", mod:get(setting_id) and true or false)
        return
    elseif setting_id == rework_master_module.MASTER_TOURNEY then
        _apply_rework_master("tourney", mod:get(setting_id) and true or false)
        return
    end

    -- Mutex enforcement runs BEFORE the apply dispatch. If `setting_id` is a
    -- member of a declared cluster and was just toggled on, the enforcer
    -- programmatically unchecks its siblings (which re-fires on_setting_changed
    -- for each sibling — the apply dispatch below handles that fan-out
    -- naturally because each fired setting_id matches its family prefix).
    -- Re-entry guard inside `mutex.enforce` keeps the recursion
    -- bounded to one level.
    mutex.enforce(setting_id)

    if setting_id:find("^rework_") then
        if balance and balance.apply then balance.apply() end
        -- A rework_ flip can change a trn_ entry's conflict state (a trn_ entry
        -- yields to its overlapping rework_), so re-apply tourney too.
        if tourney and tourney.apply then tourney.apply() end
        foot_knight.apply_settings()
    end

    if setting_id:find("^trn_") then
        if tourney and tourney.apply then tourney.apply() end
    end

    if rework_master_policy:is_member(setting_id) then
        _sync_rework_master_indicators()
    end

    -- Career-select lock state is baked at populate; refresh the open hero view so
    -- a level-override / unlock-all change takes effect without re-opening (bug fix
    -- (2) above).
    if setting_id == "unlock_all_careers" or setting_id:find("^level_override_") then
        refresh_career_unlock_ui()
    end
end

mod.on_disabled = function()
    -- Cheaply reversible (done here):
    --   * Native + Tourney balance reworks — restore patched BuffTemplate fields.
    if balance and balance.restore then balance.restore() end
    if tourney and tourney.restore then tourney.restore() end
    foot_knight.restore()
    -- Drop the OE cooldown-reduction managed bonus cleanly (the tick also self-
    -- clears once mod:get returns nil, but do it eagerly so the live OE reverts to
    -- exact vanilla recharge the instant the mod is disabled).
    if mod._crt_oe_cdr_clear then mod._crt_oe_cdr_clear() end
    -- NOT cheaply reversible (restart required), so we document rather than unwind:
    --   * The crt_* stub buff names registered UNCONDITIONALLY into BuffTemplates +
    --     NetworkLookup.buff_templates at load (career_tweaker_balance.lua:67-87).
    --     Tearing these out would shift every later NetworkLookup index and break
    --     cross-peer rpc_add_buff determinism — far worse than leaving the inert
    --     no-op stubs in place. Restart clears them.
    --   * VMF-installed hooks (ExperienceSettings.get_experience, the mirror
    --     get_read_only_data overrides, ProgressionUnlocks.is_unlocked_for_profile,
    --     plus the two armor/overcharge hooks
    --     DamageUtils.apply_buffs_to_damage + PlayerUnitHealthExtension.add_damage).
    --     VMF deactivates a disabled mod's
    --     hooks for us, and each body also gates on a mod:get(...) read, so they
    --     no-op while disabled — but the wrappers stay installed until restart.
    mod:echo("[crt] Balance reworks reverted. Buff registrations and hooks need a game restart for a fully clean vanilla state.")
end

-- ============================================================
-- Console command: ct_status (typed literally; VMF commands are flat, not prefixed)
-- ============================================================
-- REVIEW: Comment said "crt status" but the command is named "ct_status" —
-- mismatch fixed in this comment. Note "ct_" prefix is shared with
-- chaos_wastes_tweaker convention; consider renaming to "crt_status" to
-- disambiguate from chaos_wastes_tweaker commands (none currently collide).

mod:command("ct_status", "Show Career Tweaker version and active balance mods", function()
    mod:echo("Career Tweaker v" .. MOD_VERSION)
    local bal_count = (balance and balance.active_count and balance.active_count()) or 0
    mod:echo("  Balance mods active: " .. tostring(bal_count))
end)

-- ============================================================
-- Per-frame lifecycle pump
-- ============================================================
-- The single VMF mod.update. Drives the OE cooldown-reduction tick (owned by
-- career_tweaker_oe_cooldown.lua) and the auto-dump retry pump (owned by
-- _crt_diagnostics.lua); both are mod-field-guarded no-ops until their module
-- arms them. MUST stay defined BEFORE the issue-425 beacon block below --
-- _lib_peer_parity's install() WRAPS mod.update and would capture nil earlier.
mod.update = function(dt)
    -- Outcast Engineer cooldown-reduction benefit (self-throttled + self-gated on
    -- the toggle, the OE career, and the local player). Driven here, not a hook.
    if mod._crt_oe_cdr_tick then mod._crt_oe_cdr_tick(dt) end
    -- Focused Spirit's stack-growth cooldown re-arms one frame after the old
    -- cooldown's remove callback, avoiding refresh of a buff being removed.
    if mod._crt_focused_spirit_tick then mod._crt_focused_spirit_tick(dt) end
    -- Auto-dump retry pump for reworked careers (no-op unless armed at StateIngame).
    if mod._crt_dump_retry_tick then mod._crt_dump_retry_tick(dt) end
    -- #440 automatic profile summaries; self-throttled to once per second.
    if mod._crt_bardin_disabler_tick then pcall(mod._crt_bardin_disabler_tick, dt) end
    foot_knight.tick(dt)
end

-- ============================================================
-- Issue 425: peer-parity beacon (shared lib, issue 371 framework)
-- ============================================================
-- COPIED single-source lib (master: tools/shared_lib/_lib_peer_parity.lua; the
-- standalone invariant forbids a get_mod() runtime dep). Proves "does every
-- lobby peer have this exact CRT name+numeric catalog?" over VMF's own
-- mod-to-mod channel -- wire-safe by construction, no vanilla NetworkLookup
-- key, no vanilla RPC. Consumed by
-- career_tweaker_balance.lua: the network_unsafe reworks (the seven whose crt_*
-- buffs ride rpc_add_buff) apply only under settled parity, and the wire-safe
-- proc/driver wrappers consult the live state per send. Fail-safe: features
-- inert until every peer is positively confirmed; any beacon error forces OFF.
--
-- ORDER MATTERS: this block must sit AFTER the mod.update definition above --
-- install() wraps the existing mod.update (preserving the OE cooldown tick +
-- dump retry) and would capture nil if run earlier.
do
    local wire_identity, wire_identity_err, wire_names =
        mod._crt.wire_policy.build_wire_identity(
            mod._crt_mod_registered_buff_names,
            NetworkLookup and NetworkLookup.buff_templates)
    mod._crt.wire_catalog_identity = wire_identity
    mod._crt.wire_catalog_count = wire_names and #wire_names or 0
    if not wire_identity then
        pcall(printf, "[crt:776] WARNING exact wire-catalog identity unavailable (%s); networked reworks stay vanilla (fail-safe)",
            tostring(wire_identity_err))
    else
        pcall(printf, "[crt:776] wire catalog identity=%s entries=%d",
            wire_identity, mod._crt.wire_catalog_count)
    end

    local ok, factory = false, nil
    local parity_transport = nil
    if wire_identity then
        local wire_runtime = mod:dofile("scripts/mods/career_tweaker/_crt_wire_runtime")
        parity_transport = wire_runtime and wire_runtime.wrap_parity_transport
            and wire_runtime.wrap_parity_transport(mod, wire_identity)
        ok, factory = pcall(function()
            return mod:dofile("scripts/mods/career_tweaker/_lib_peer_parity")
        end)
    end
    if wire_identity and parity_transport and ok and type(factory) == "function" then
        local ok2, inst = pcall(factory, parity_transport, {
            channel     = "crt_peer_parity_present",
            schema      = CRT_RPC_SCHEMA,
            mod_label   = "Career Tweaker",
            echo_prefix = "[crt]",
        })
        if ok2 and type(inst) == "table" then
            mod._crt_peer_parity = inst
            parity_transport:_bind_parity_instance(inst)
            mod._crt_wire_transport_identity = wire_identity
            pcall(function() inst:install() end)
            pcall(printf, "[crt:425] peer-parity beacon installed (channel=crt_peer_parity_present schema=%d exact_identity=%s)",
                CRT_RPC_SCHEMA, wire_identity)
            -- ONE gated feature covering every networked_unsafe entry (seven
            -- balance reworks + the trn_wh_priest tourney port). On a parity
            -- transition the beacon fires these callbacks; each just re-runs the
            -- two apply engines, which read the beacon's settled state directly
            -- via pp:applied_state(). Issue 506: the shared lib now commits
            -- _applied BEFORE firing callbacks, so an applied_state() read from
            -- inside apply reflects the transition being delivered -- crt no
            -- longer needs the private mod._crt_parity_settled_enabled mirror
            -- flag it formerly set here to dodge the stale read (removed).
            -- The lib chat-echoes the user-facing disable/re-enable notice; the
            -- printf lines are the log-side [crt:425] trail.
            inst:register_gated_feature("crt_networked_reworks", {
                label = "networked talent reworks",
                on_enable = function()
                    pcall(printf, "[crt:425] parity established: re-applying networked talent reworks per settings")
                    if balance and balance.apply then pcall(balance.apply) end
                    if tourney and tourney.apply then pcall(tourney.apply) end
                end,
                on_disable = function()
                    pcall(printf, "[crt:425] parity degraded (peer set changed or peer lacks crt): networked talent reworks fall back to vanilla")
                    if balance and balance.apply then pcall(balance.apply) end
                    if tourney and tourney.apply then pcall(tourney.apply) end
                end,
            })
        else
            pcall(printf, "[crt:425] WARNING peer-parity factory failed (%s); networked reworks stay vanilla (fail-safe)", tostring(inst))
        end
    elseif wire_identity then
        pcall(printf, "[crt:425] WARNING peer-parity lib failed to load (%s); networked reworks stay vanilla (fail-safe)", tostring(factory))
    end
end

-- ============================================================
-- Regression smoke suite (/crt_regression_test)
-- ============================================================
local ok_flagellation, flagellation_err = pcall(mod.dofile, mod,
    "scripts/mods/career_tweaker/_crt_flagellation")
if not ok_flagellation then
    mod:error("Failed to load Flagellation rework: %s", tostring(flagellation_err))
end

-- Split to _crt_regression.lua (v0.3.57-dev). LAST in the manifest: its check
-- bodies capture mod._crt.balance + the talent-swap restore/accessors + the
-- _dbg helpers + MOD_VERSION at load, all populated above. Keep this before the
-- mem-probe so the boot-footprint line still accounts for the suite.
local ok_rt, _rt = pcall(mod.dofile, mod, "scripts/mods/career_tweaker/_crt_regression")
if not ok_rt then mod:error("Failed to load regression module: %s", tostring(_rt)) end

mod:info("[mem-probe] crt boot_lua=+%.1f MB (of ~1024 MB lua_heap cap)", (collectgarbage("count") - _MEM_PROBE_T0_CRT) / 1024)
