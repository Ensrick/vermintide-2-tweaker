local mod = get_mod("crt")
local DamageClass = mod._crt and mod._crt.damage_classification

-- ============================================================
-- Armor & Overcharge toggles (hook-based)  [crt v0.3.52-dev]
-- ============================================================
-- Seven gameplay toggles that exempt certain damage from
-- consuming Ironbreaker Gromril Armour / Necromancer Cursed Armor counters, or
-- from feeding Sienna Unchained's overcharge passive / resetting Handmaiden's
-- Focused Spirit. Six are pure runtime
-- hooks gated on `mod:get(...)` — no {apply,restore,active_count} lifecycle
-- contract (VMF re-reads mod:get live and deactivates the hooks when the mod is
-- disabled). The Focused Spirit stacking toggle uses the balance module's
-- reversible template-patch lifecycle; its damage handling still routes through
-- this module's existing add_damage hook. dofile'd from career_tweaker.lua.
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
local FOCUSED_SPIRIT  = "kerillian_maidenguard_power_level_on_unharmed"
local FOCUSED_COOLDOWN = "kerillian_maidenguard_power_level_on_unharmed_cooldown"

-- The Cursed Armor counter is consumed by ONE proc buff
-- (sienna_necromancer_5_2_counter_remover, talent_settings_shovel.lua:347-360)
-- whose buff_func is the GENERIC "remove_buff_stack" (shared by many buffs). We
-- re-point ONLY that template's proc entry through a crt-owned ProcFunctions
-- wrapper (installed below) so an exempt tick can suppress the counter's own
-- consume without swallowing any other on_damage_taken proc.
local NECRO_COUNTER_REMOVER    = "sienna_necromancer_5_2_counter_remover"
local CRT_COUNTER_REMOVER_FUNC = "crt_cursed_armor_counter_remover"
local CRT_FOCUSED_PROC_FUNC    = "crt_focused_spirit_damage_taken"
local CRT_FOCUSED_GROW_FUNC    = "crt_focused_spirit_arm_growth"

-- ── Predicate helpers (all damage-context reads nil-guarded) ─────────────────

-- Shared #334 policy is manifest-loaded and engine-free. Keeping these aliases
-- means the proven Gromril / Cursed Armor / Blood Magic boundary is unchanged
-- while Focused Spirit can consume the same classifier (#472).
local _is_chip_or_aoe = DamageClass.is_chip_or_aoe
local _is_self_dot = DamageClass.is_self_dot
local _focused_spirit_ignores = DamageClass.focused_spirit_ignores

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

-- ── Handmaiden Focused Spirit (#472) ────────────────────────────────────────
-- Vanilla's event proc sees only (attacker, amount, damage_type), while the
-- source identity needed to distinguish Ratling fire lives one frame higher in
-- PlayerUnitHealthExtension.add_damage. The existing hook below therefore
-- publishes a synchronous, per-victim context for this proc wrapper. Ignored
-- chip damage returns false (preserves vanilla's active buff). Under the opt-in
-- stacking rework, one ordinary hit removes exactly one stack and re-arms the
-- vanilla 10-second cooldown; the remaining stack procs no-op for that hit.
local function _focused_spirit_has_talent(unit)
    local te = unit and ScriptUnit.has_extension(unit, "talent_system")
    return te and te.has_talent
        and te:has_talent("kerillian_maidenguard_power_level_on_unharmed")
end

local _focused_rearm = setmetatable({}, { __mode = "k" })

local function _focused_stack_count(be)
    local stacks = be and be.get_stacking_buff and be:get_stacking_buff(FOCUSED_SPIRIT)
    return stacks and #stacks or 0
end

local function _focused_add_local_cooldown(unit, be)
    if not (unit and be and be.add_buff) then return end
    be:add_buff(FOCUSED_COOLDOWN, { attacker_unit = unit })
end

local function _focused_request_cooldown(unit, attacker_unit, damage_amount)
    local PF = rawget(_G, "ProcFunctions")
    local vanilla = PF and PF.maidenguard_reset_unharmed_buff
    if vanilla then
        -- The vanilla proc does not inspect `buff`; it uses these params to
        -- choose server-local add_buff vs client rpc_add_buff.
        vanilla(unit, nil, { attacker_unit, damage_amount })
    end
end

local function _crt_install_focused_spirit_wrapper()
    local PF = rawget(_G, "ProcFunctions")
    local BFT = rawget(_G, "BuffFunctionTemplates")
    local BT = rawget(_G, "BuffTemplates")
    local fns = BFT and BFT.functions
    if type(PF) ~= "table" or type(fns) ~= "table" or type(BT) ~= "table" then return end

    -- Called after each newly-added power stack. Cooldown expiry adds the next
    -- stack from inside remove_buff, before the expiring cooldown is physically
    -- removed, so re-arm on the next frame rather than refreshing a dying buff.
    fns[CRT_FOCUSED_GROW_FUNC] = function(owner_unit)
        if not mod:get("rework_we_maidenguard_focused_spirit_stacks") then return end
        local be = ScriptUnit.has_extension(owner_unit, "buff_system")
        if be and _focused_stack_count(be) < 5 then
            _focused_rearm[owner_unit] = true
        end
    end

    PF[CRT_FOCUSED_PROC_FUNC] = function(owner_unit, buff, params, world, proc_event_params)
        local vanilla = PF.maidenguard_reset_unharmed_buff
        local ctx = mod._crt_focused_spirit_damage_context
        if ctx and ctx.unit == owner_unit and ctx.ignored then
            return false
        end
        if not mod:get("rework_we_maidenguard_focused_spirit_stacks") then
            return vanilla and vanilla(owner_unit, buff, params, world, proc_event_params)
        end

        -- Preserve vanilla's real-hit boundary: self damage and zero-damage
        -- notifications neither consume a stack nor restart its growth timer.
        local attacker_unit = params and params[1]
        local damage_amount = params and params[2]
        if attacker_unit == owner_unit or damage_amount == 0 then
            return false
        end

        if not ctx or ctx.unit ~= owner_unit or ctx.handled then
            return false
        end
        ctx.handled = true

        local be = ScriptUnit.has_extension(owner_unit, "buff_system")
        if be and buff and buff.id then
            be:remove_buff(buff.id)
        end
        -- Reuse vanilla's authority-aware cooldown add / RPC path. Returning
        -- false prevents BuffExtension.trigger_procs from removing more stacks.
        if vanilla then
            vanilla(owner_unit, buff, params, world, proc_event_params)
        end
        return false
    end

    local tmpl = rawget(BT, FOCUSED_SPIRIT)
    local sub = tmpl and tmpl.buffs and tmpl.buffs[1]
    if type(sub) == "table"
       and (sub.buff_func == "maidenguard_reset_unharmed_buff"
            or sub.buff_func == CRT_FOCUSED_PROC_FUNC) then
        sub.buff_func = CRT_FOCUSED_PROC_FUNC
    end
end
_crt_install_focused_spirit_wrapper()

-- One-frame deferred cooldown re-arm used only by the stacking rework. The
-- entry's single mod.update calls this field; no extra update assignment/hook.
mod._crt_focused_spirit_tick = function()
    local alive = rawget(_G, "ALIVE")
    for unit in pairs(_focused_rearm) do
        _focused_rearm[unit] = nil
        if mod:get("rework_we_maidenguard_focused_spirit_stacks")
           and alive and alive[unit] then
            local be = ScriptUnit.has_extension(unit, "buff_system")
            if be and _focused_stack_count(be) < 5 then
                _focused_add_local_cooldown(unit, be)
            end
        end
    end
end

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
    local set_focused_context, prev_focused_context = false, nil
    local unit = self.unit
    local be = unit and ScriptUnit.has_extension(unit, "buff_system")

    if mod:get("armor_gromril_ignore_chip") then
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

    -- Focused Spirit's vanilla proc lacks damage_source_name, so carry the full
    -- add_damage context across the synchronous trigger_procs call. Temporary
    -- health degeneration never fires on_damage_taken and is excluded here too.
    local focused_ignore_on = mod:get("maidenguard_focused_spirit_ignore_chip_damage")
    local focused_rework_on = mod:get("rework_we_maidenguard_focused_spirit_stacks")
    if (focused_ignore_on or focused_rework_on)
       and damage_amount and damage_amount > 0
       and damage_source_name ~= "temporary_health_degen"
       and _focused_spirit_has_talent(unit) then
        local ignored = focused_ignore_on
            and _focused_spirit_ignores(attacker_unit, unit, damage_source_name, damage_type)
        prev_focused_context = mod._crt_focused_spirit_damage_context
        mod._crt_focused_spirit_damage_context = {
            unit = unit,
            ignored = ignored,
            handled = false,
        }
        set_focused_context = true

        -- At zero stacks there is no event buff to run the proc wrapper. A real
        -- hit still restarts the ten-second no-damage window; ignored chip does
        -- not touch the timer. Route through vanilla so its server/RPC authority
        -- split refreshes the max_stacks=1 cooldown.
        if focused_rework_on and not ignored and attacker_unit ~= unit
           and be and _focused_stack_count(be) == 0 then
            _focused_request_cooldown(unit, attacker_unit, damage_amount)
        end
    end

    -- add_damage returns nothing meaningful, but wrap in pcall so the exempt flag
    -- is always cleared even if vanilla raises mid-call.
    local ok, err = pcall(func, self, attacker_unit, damage_amount, hit_zone_name, damage_type, hit_position,
        damage_direction, damage_source_name, hit_ragdoll_actor, source_attacker_unit, hit_react_type,
        is_critical_strike, added_dot, first_hit, total_hits, attack_type, backstab_multiplier, target_index)

    if set_exempt then mod._crt_cursed_armor_exempt_unit = prev_exempt end
    if set_focused_context then
        mod._crt_focused_spirit_damage_context = prev_focused_context
    end

    if not ok then
        error(err, 0)
    end
end)

mod:info("[crt] armor/overcharge module loaded (7 toggles, 2 hooks)")
