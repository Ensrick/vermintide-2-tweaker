local mod = get_mod("crt")

-- ============================================================
-- Armor & Overcharge toggles (hook-based)  [crt v0.3.52-dev]
-- ============================================================
-- Five opt-in (default-OFF) gameplay toggles that exempt certain damage from
-- consuming Ironbreaker Gromril Armour / Necromancer Cursed Armor counters, or
-- from feeding Sienna Unchained's overcharge passive. All five are pure runtime
-- hooks gated on `mod:get(...)` — no {apply,restore,active_count} lifecycle
-- contract (VMF re-reads mod:get live and deactivates the hooks when the mod is
-- disabled). dofile'd from career_tweaker.lua, same as career_tweaker_tourney.
--
-- ── Self-inflicted DoT coverage (Issue #334) ─────────────────────────────────
-- The Chaos Wastes Slaanesh curse "Unquenchable Thirst" (internally
-- curse_abundance_of_life) ticks self-damage every 2s through a custom_dot_tick
-- that calls add_damage_network(unit, unit, damage, "torso", "wounded_dot", nil,
-- ...) — attacker == victim, damage_type "wounded_dot", damage_source NIL
-- (morris_buff_settings.lua:636-646). Because the source is nil the tick slips
-- past vanilla's own exemption sets (INVALID_GROMRIL_DAMAGE_SOURCE /
-- INVALID_DAMAGE_TO_OVERHEAT_DAMAGE_SOURCES, damage_utils.lua:2114-2127), so it
-- eats Gromril every tick, converts to overcharge under Unchained Blood Magic,
-- and eats a Necromancer Cursed Armor counter. Discriminator: damage_type ==
-- "wounded_dot" AND attacker == victim (`_is_self_dot`) — the only wounded_dot
-- self-tickers are curse/event/mutator DoTs (this curse, skulls_2023, Nurgle's
-- Rot). Toggle #1 folds the Gromril + Necromancer coverage in; toggle #5 adds
-- the Blood Magic overcharge case.
--
-- ── Authority model (load-bearing — determines correctness) ──────────────────
-- Two distinct removal paths, two distinct authority models:
--
--  * Gromril (toggles #1-gromril + #2) AND Unchained overcharge (#3 + #4) are
--    consumed inside `DamageUtils.apply_buffs_to_damage`, which runs on the
--    DAMAGE-AUTHORITY peer (host/server). The host removes gromril locally AND
--    fires `rpc_remove_gromril_armour` to clients; the client mirror
--    `BuffSystem.rpc_remove_gromril_armour` strips gromril UNCONDITIONALLY on
--    RPC receipt (buff_system.lua:569-587). ⇒ Gate the HOST side only: if the
--    host's apply_buffs_to_damage never removes gromril, the RPC is never sent,
--    so clients never strip either. Likewise the overcharge conversion either
--    applies locally or RPCs `rpc_damage_taken_overcharge` to the owning client.
--    ⇒ host-authoritative, NOT own-peer. CAVEAT: these toggles only take effect
--    when the player running crt is the HOST.
--
--  * Necromancer Cursed Armor (covered by toggle #1) counter stacks are consumed
--    by the `sienna_necromancer_5_2_counter_remover` proc on event
--    `on_damage_taken`, fired from `PlayerUnitHealthExtension.add_damage:702-703`,
--    which runs on the VICTIM's own player-unit peer (health extension is
--    per-unit local). ⇒ per-player own-peer; works for the local Necromancer
--    regardless of who hosts.
--
-- Net: TWO hook targets, not one (different functions, different authority).
--   * DamageUtils.apply_buffs_to_damage      → #1-gromril, #2, #3, #4, #5
--   * PlayerUnitHealthExtension.add_damage   → #1-necromancer
-- VMF no-duplicate-hook rule: grepped career_tweaker/ — neither target is hooked
-- anywhere else in crt. Exactly ONE mod:hook per (Class, method) below.
--
-- ── Interception technique (per-instance method shim) ────────────────────────
-- apply_buffs_to_damage / add_damage do their work via SIDE EFFECTS on the
-- victim's buff_extension + network sends; you can't cleanly post-filter. So we
-- WRAP the function and, for exempt hits, temporarily monkey-patch the ONE
-- buff_extension method the vanilla decision keys on, then restore it after the
-- wrapped call returns:
--   * Gromril:    shim `be.has_buff_type` to report the gromril marker absent
--                 → vanilla's `has_gromril_armor` reads false → no nullify-via-
--                 gromril, no consume, no RPC. (Chip still does its small damage;
--                 the armor stays up for the next real hit — exactly "chip
--                 doesn't break your armor".)  [damage_utils.lua:2322,2331,2335]
--   * Overcharge: shim `be.apply_buffs_to_value` to return the value unchanged
--                 for stat "damage_taken_to_overcharge" → `new_damage ==
--                 original_damage` → the `if new_damage < original_damage` branch
--                 never fires → no overcharge, no RPC.  [damage_utils.lua:2203-05]
--   * Necromancer: re-point the Cursed Armor counter-remover proc (ONLY that
--                 one proc) through a crt-owned ProcFunctions wrapper and flag
--                 the victim's tick exempt, so only the counter's own consume is
--                 skipped for that tick -- every OTHER on_damage_taken proc still
--                 fires. Proc funcs resolve by name per-fire from the writable
--                 global ProcFunctions (buff_extension.lua:1351), so re-pointing
--                 the template once at load re-routes every counter-remover
--                 instance. [player_unit_health_extension.lua:702-703 →
--                  counter_remover proc talent_settings_shovel.lua:347-360]
-- The gromril / overcharge shims are per-instance and live only for the duration
-- of one wrapped call; VT2 is single-threaded so there's no intra-frame
-- concurrency concern. The restore is done in a pcall-protected finally so an
-- error mid-call can't leave a poisoned buff_extension. The Necromancer path no
-- longer replaces be.trigger_procs -- that replacement swallowed EVERY buff's
-- on_damage_taken procs for the tick (the pre-v0.3.56 defect); the per-proc
-- wrapper below fixes it while preserving the counter's accounting exactly.

-- ── Source-verified constant sets (transcribed; do NOT rely on game globals) ──
-- Burning / fire DoTs hard-code damage_source = "dot_debuff" when there's no
-- source breed (buff_function_templates.lua:695). DoTs WITH a source breed use
-- the breed name instead, so this is the conservative chip key.
local DOT_SOURCE = "dot_debuff"

-- AOE damage_type set — globadier poison gas, stormfiend/warpfire-rat warpfire,
-- blightstorm vortex, bile troll bile, ratling area, plaguelord plague.
-- (weapons.lua:67-74)
local DAMAGE_TYPES_AOE = {
    plague_face   = true,
    poison        = true,
    vomit_face    = true,
    vomit_ground  = true,
    warpfire_face = true,
    warpfire_ground = true,
}

-- Special-disabler breed keys (documentation / clarity aid). The PRIMARY test is
-- the generic `rawget(Breeds, damage_source).special == true` — this set just
-- names the canonical disablers (Hookrat / Assassin / Leech). All carry
-- `special = true` (breed_skaven_pack_master.lua:50, breed_skaven_gutter_runner
-- .lua:45, breed_chaos_corruptor_sorcerer.lua:47).
local DISABLER_BREEDS = {
    skaven_pack_master       = true,  -- Hookrat
    skaven_gutter_runner     = true,  -- Assassin
    chaos_corruptor_sorcerer = true,  -- Leech
}

local GROMRIL_MARKER = "bardin_ironbreaker_gromril_armour"
local NECRO_COUNTER   = "sienna_necromancer_5_2_counter"

-- The Cursed Armor counter is consumed by ONE proc buff
-- (sienna_necromancer_5_2_counter_remover, talent_settings_shovel.lua:347-360)
-- whose buff_func is the GENERIC "remove_buff_stack" (shared by many buffs). We
-- re-point ONLY that template's proc entry through a crt-owned ProcFunctions
-- wrapper (installed below) so an exempt tick can suppress the counter's own
-- consume without swallowing any other on_damage_taken proc.
local NECRO_COUNTER_REMOVER    = "sienna_necromancer_5_2_counter_remover"
local CRT_COUNTER_REMOVER_FUNC = "crt_cursed_armor_counter_remover"

-- ── Predicate helpers (all damage-context reads nil-guarded) ─────────────────

-- True when this hit is a chip / DoT / AOE source that toggle #1 exempts.
local function _is_chip_or_aoe(damage_source, damage_type)
    if damage_source == DOT_SOURCE then return true end
    if damage_type and DAMAGE_TYPES_AOE[damage_type] then return true end
    return false
end

-- True for self-inflicted DoT ticks: CW curses (Unquenchable Thirst), event
-- mutator DoTs, Nurgle's Rot. These stamp damage_type "wounded_dot" with the
-- victim as its own attacker (e.g. morris_buff_settings.lua:636-646). Used to
-- exempt these ticks from consuming Gromril / Necromancer Cursed Armor and, via
-- toggle #5, from feeding Unchained Blood Magic overcharge (#334).
local function _is_self_dot(attacker_unit, attacked_unit, damage_type)
    return damage_type == "wounded_dot" and attacker_unit ~= nil and attacker_unit == attacked_unit
end

-- True when `damage_source` names a special breed (generic test + named set).
local function _is_special_source(damage_source)
    if type(damage_source) ~= "string" then return false end
    if DISABLER_BREEDS[damage_source] then return true end
    local Breeds = rawget(_G, "Breeds")
    local breed = Breeds and rawget(Breeds, damage_source)
    return breed ~= nil and breed.special == true
end

-- Gromril exemption predicate (toggles #1-gromril + #2). Pre-checks the victim
-- actually carries the marker so the shim is a no-op on non-Ironbreakers.
local function _gromril_hit_is_exempt(attacked_unit, attacker_unit, be, damage_source, damage_type)
    if not (be and be.has_buff_type and be:has_buff_type(GROMRIL_MARKER)) then
        return false
    end

    -- Chip branch (toggle #1): chip/DoT/AOE sources, plus self-inflicted curse /
    -- event / mutator DoT ticks (Unquenchable Thirst etc., #334) via _is_self_dot.
    if mod:get("armor_gromril_ignore_chip")
       and (_is_chip_or_aoe(damage_source, damage_type)
            or _is_self_dot(attacker_unit, attacked_unit, damage_type)) then
        return true
    end

    -- Special branch (toggle #2): specials don't break gromril UNLESS the
    -- Ironbreaker has the Gromril Curse talent (the level-20 cooldown pick,
    -- internally bardin_ironbreaker_max_gromril_delay — there is no literal
    -- "gromril_curse" in source). With that talent, specials break as normal.
    if mod:get("armor_specials_dont_break_gromril") and _is_special_source(damage_source) then
        local te = ScriptUnit.has_extension(attacked_unit, "talent_system")
        local has_curse = te and te.has_talent
            and te:has_talent("bardin_ironbreaker_max_gromril_delay", "dwarf_ranger", true)
        if not has_curse then
            return true
        end
    end

    return false
end

-- Sienna Unchained career gate: the passive grants buff_perk "sienna_unchained"
-- (talent_settings_sienna.lua:791-799). True only while the active career is
-- Unchained.
local function _is_sienna_unchained(be)
    return be and be.has_buff_perk and be:has_buff_perk("sienna_unchained")
end

-- Overcharge exemption predicate (toggles #3 + #4 + #5).
local function _overcharge_hit_is_exempt(attacked_unit, attacker_unit, damage_source, damage_type)
    -- Self-inflicted DoT (toggle #5): CW curses (Unquenchable Thirst), event
    -- mutator DoTs, Nurgle's Rot. None of these should build Blood Magic
    -- overcharge; they slip past vanilla's overheat exemption set because their
    -- damage_source is nil (#334, morris_buff_settings.lua:636-646).
    if mod:get("unchained_no_overcharge_from_self_dot")
       and _is_self_dot(attacker_unit, attacked_unit, damage_type) then
        return true
    end

    -- Friendly fire (toggle #3): attacker is an ally and not the victim itself.
    if mod:get("unchained_no_overcharge_from_ff") then
        local side_mgr = Managers.state and Managers.state.side
        local sbu = side_mgr and side_mgr.side_by_unit
        if sbu and attacker_unit and attacker_unit ~= attacked_unit
           and sbu[attacked_unit] ~= nil and sbu[attacked_unit] == sbu[attacker_unit] then
            return true
        end
    end

    -- Special disablers (toggle #4): mirror Tourney's disabler filter. Note
    -- vanilla already drops the leech drain ticks (life_drain/life_tap) via
    -- INVALID_DAMAGE_TO_OVERHEAT_DAMAGE_SOURCES and skips conversion entirely
    -- while pinned (is_disabled); this additionally blocks the grab/impact hit.
    if mod:get("unchained_no_overcharge_from_disablers") and _is_special_source(damage_source) then
        return true
    end

    return false
end

-- ── Hook #1: DamageUtils.apply_buffs_to_damage (gromril #1/#2 + overcharge #3/#4)
-- Single chokepoint for gromril consumption (damage_utils.lua:2335-2345) and
-- Unchained overcharge conversion (damage_utils.lua:2196-2224). Host-authoritative.
mod:hook(DamageUtils, "apply_buffs_to_damage", function(func, current_damage, attacked_unit, attacker_unit,
        damage_source, victim_units, damage_type, buff_attack_type, first_hit, source_attacker_unit)

    -- Fast early-out: if none of the five toggles is on, call straight through.
    if not (mod:get("armor_gromril_ignore_chip")
            or mod:get("armor_specials_dont_break_gromril")
            or mod:get("unchained_no_overcharge_from_ff")
            or mod:get("unchained_no_overcharge_from_disablers")
            or mod:get("unchained_no_overcharge_from_self_dot")) then
        return func(current_damage, attacked_unit, attacker_unit, damage_source,
                    victim_units, damage_type, buff_attack_type, first_hit, source_attacker_unit)
    end

    local be = ScriptUnit.has_extension(attacked_unit, "buff_system")

    local restore_htb = nil  -- original be.has_buff_type
    local restore_abv = nil  -- original be.apply_buffs_to_value

    if be then
        -- Gromril shim (#1-gromril / #2): hide the marker from the consume+nullify
        -- block so vanilla neither removes it nor RPCs the removal to clients.
        if (mod:get("armor_gromril_ignore_chip") or mod:get("armor_specials_dont_break_gromril"))
           and _gromril_hit_is_exempt(attacked_unit, attacker_unit, be, damage_source, damage_type) then
            local orig = be.has_buff_type
            restore_htb = orig
            be.has_buff_type = function(self, name)
                if name == GROMRIL_MARKER then return false end
                return orig(self, name)
            end
        end

        -- Overcharge shim (#3 / #4): make apply_buffs_to_value a no-op for the
        -- "damage_taken_to_overcharge" stat so no overcharge is gained (and no
        -- rpc_damage_taken_overcharge is sent), leaving every other stat intact.
        if _is_sienna_unchained(be)
           and (mod:get("unchained_no_overcharge_from_ff")
                or mod:get("unchained_no_overcharge_from_disablers")
                or mod:get("unchained_no_overcharge_from_self_dot"))
           and _overcharge_hit_is_exempt(attacked_unit, attacker_unit, damage_source, damage_type) then
            local orig_abv = be.apply_buffs_to_value
            restore_abv = orig_abv
            be.apply_buffs_to_value = function(self, value, stat_name, ...)
                if stat_name == "damage_taken_to_overcharge" then return value end
                return orig_abv(self, value, stat_name, ...)
            end
        end
    end

    -- Capture ALL returns (multi-return collapse rule, VMF_RECIPES § 2) and
    -- restore the shims even if func raises.
    local ok, a, b, c = pcall(func, current_damage, attacked_unit, attacker_unit, damage_source,
                              victim_units, damage_type, buff_attack_type, first_hit, source_attacker_unit)

    if restore_htb then be.has_buff_type = restore_htb end
    if restore_abv then be.apply_buffs_to_value = restore_abv end

    if not ok then
        -- Propagate the original error (a holds the error message).
        error(a, 0)
    end
    return a, b, c
end)

-- ── Cursed Armor counter-remover: crt-owned ProcFunctions wrapper ────────────
-- Necromancer Cursed Armor stacks are consumed by ONE proc buff
-- (sienna_necromancer_5_2_counter_remover) firing on on_damage_taken. The engine
-- resolves a proc's function BY NAME from the writable global ProcFunctions at
-- fire time (buff_extension.lua:1351), and buff.buff_func is snapshotted from the
-- template at add time (buff_extension.lua:421-423). So a one-time rewrite of
-- that template's proc entry at mod load re-routes every counter-remover instance
-- (all of them — no Necromancer buff exists before mod init) through a crt-owned
-- wrapper, WITHOUT touching be.trigger_procs. The wrapper delegates to the
-- vanilla remove_buff_stack proc (ProcFunctions.remove_buff_stack,
-- buff_templates.lua:3280) unless the victim's current tick is flagged exempt by
-- the add_damage hook below — in which case it skips the stack consume for THAT
-- tick only, leaving every other on_damage_taken proc untouched. Proc-function
-- names are never networked (only buff-template names + ids are, buff_system.lua
-- rpc_add_buff), so this is purely local: no NetworkLookup / wire-safety concern.
local function _crt_install_cursed_armor_wrapper()
    local PF = rawget(_G, "ProcFunctions")
    local BT = rawget(_G, "BuffTemplates")
    if type(PF) ~= "table" or type(BT) ~= "table" then return end

    -- Register the crt wrapper (idempotent). Signature mirrors the vanilla proc
    -- call convention (owner, buff, params, world, proc_event_params).
    if PF[CRT_COUNTER_REMOVER_FUNC] == nil then
        PF[CRT_COUNTER_REMOVER_FUNC] = function(owner, buff, params, world, proc_event_params)
            -- Exempt tick for THIS victim: skip the counter's own consume —
            -- exactly what the old be.trigger_procs swallow did, but scoped to
            -- this one proc so no other on_damage_taken proc is affected.
            if owner ~= nil and owner == mod._crt_cursed_armor_exempt_unit then
                return
            end
            local vanilla = PF.remove_buff_stack
            if vanilla then
                return vanilla(owner, buff, params, world, proc_event_params)
            end
        end
    end

    -- Re-point ONLY the Cursed Armor counter-remover's proc entry (idempotent):
    -- guarded on the vanilla value so a re-run (hot reload) is a no-op.
    local tmpl = rawget(BT, NECRO_COUNTER_REMOVER)
    local sub = tmpl and tmpl.buffs and tmpl.buffs[1]
    if type(sub) == "table" and sub.buff_func == "remove_buff_stack" then
        sub.buff_func = CRT_COUNTER_REMOVER_FUNC
    end
end
_crt_install_cursed_armor_wrapper()

-- ── Hook #2: PlayerUnitHealthExtension.add_damage (Necromancer Cursed Armor, #1)
-- The on_damage_taken proc that consumes a Cursed Armor counter fires from
-- player_unit_health_extension.lua:702-703. The proc only receives
-- (attacker_unit, damage_amount, damage_type) so we can't filter inside it —
-- intercept at add_damage where the full context is in scope (:530), flag the
-- victim's tick exempt, and let the crt-owned counter-remover wrapper (above)
-- skip ONLY the counter consume for that tick. Per-victim own-peer. FULL 18-param
-- signature (incl. self) verbatim so nothing is dropped.
mod:hook(PlayerUnitHealthExtension, "add_damage", function(func, self, attacker_unit, damage_amount, hit_zone_name,
        damage_type, hit_position, damage_direction, damage_source_name, hit_ragdoll_actor, source_attacker_unit,
        hit_react_type, is_critical_strike, added_dot, first_hit, total_hits, attack_type, backstab_multiplier, target_index)

    local set_exempt, prev_exempt = false, nil

    if mod:get("armor_gromril_ignore_chip") then
        local unit = self.unit
        local be = unit and ScriptUnit.has_extension(unit, "buff_system")
        if be and be.has_buff_type and be:has_buff_type(NECRO_COUNTER)
           and (_is_chip_or_aoe(damage_source_name, damage_type)
                or _is_self_dot(attacker_unit, self.unit, damage_type)) then
            -- Flag THIS victim's tick exempt for the duration of the wrapped
            -- call. Save/restore the prior value so a nested add_damage (should
            -- it ever occur) can't leak the flag. VT2 is single-threaded, so the
            -- flag lives only across this synchronous add_damage -> trigger_procs.
            prev_exempt = mod._crt_cursed_armor_exempt_unit
            mod._crt_cursed_armor_exempt_unit = unit
            set_exempt = true
        end
    end

    -- add_damage returns nothing meaningful, but wrap in pcall so the exempt flag
    -- is always cleared even if vanilla raises mid-call.
    local ok, err = pcall(func, self, attacker_unit, damage_amount, hit_zone_name, damage_type, hit_position,
        damage_direction, damage_source_name, hit_ragdoll_actor, source_attacker_unit, hit_react_type,
        is_critical_strike, added_dot, first_hit, total_hits, attack_type, backstab_multiplier, target_index)

    if set_exempt then mod._crt_cursed_armor_exempt_unit = prev_exempt end

    if not ok then
        error(err, 0)
    end
end)

mod:info("[crt] armor/overcharge module loaded (5 toggles, 2 hooks)")
