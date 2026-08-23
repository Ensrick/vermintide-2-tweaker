local mod = get_mod("crt")
mod._crt.dance_of_blades = mod:dofile("scripts/mods/career_tweaker/_crt_dance_of_blades")
local foot_knight_policy = mod:dofile("scripts/mods/career_tweaker/_crt_foot_knight_policy")
local wire_policy = mod._crt.wire_policy
local wire_runtime = mod:dofile("scripts/mods/career_tweaker/_crt_wire_runtime")
local network_lookup = mod._crt.network_lookup

-- ============================================================
-- crt_* buff name pre-registration (UNCONDITIONAL)
-- ============================================================
-- Per memory rule `feedback_vt2_gated_registration_diverges`: any mod-load
-- write to BuffTemplates / NetworkLookup gated on a per-user toggle causes
-- per-peer index divergence and crashes on `rpc_add_buff(integer)`. The 22
-- talent-rework `BuffTemplates.crt_*` entries below were each conditionally
-- registered inside their custom_apply blocks, which meant:
--   * NetworkLookup index N was claimed only on peers whose toggle was ON
--   * Toggle-off peers received `rpc_add_buff(N)` and resolved N to a
--     different name (or nil) → crash at `network_lookup.lua:2521`
--     ("Table buff_templates does not contain key: crt_X")
--
-- Fix: register every name UNCONDITIONALLY in alphabetical order at mod
-- load. Bodies are pre-seeded as no-op stubs (`{ buffs = {} }` + the
-- `_crt_pending` marker). Per-toggle `custom_apply` replaces the stub with
-- the real body and saves a "created" flag; per-toggle `custom_restore`
-- writes a fresh stub back so the NetworkLookup entry still resolves to a
-- valid (no-op) buff template even when the toggle is OFF.
--
-- Stub-or-real bodies preserve the same names and indices on every CRT peer;
-- toggles change behavior only, never the lookup catalog.
--
-- Burned ct v0.7.59 + v0.7.60 with this same bug class against DeusPowerUp
-- registrations; the `crt_*` talent rework code shipped the same flawed
-- pattern before the BR registration audit caught it. Fixed 2026-05-21.

local function _crt_make_stub()
    return { buffs = {}, _crt_pending = true }
end

-- Alphabetically sorted — order is load-bearing for cross-peer NetworkLookup
-- index determinism. NEVER reorder without bumping versions in lockstep.
local _CRT_BUFF_NAMES = {
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
    "crt_maidenguard_dance_of_blades_dodge",
    "crt_maidenguard_dance_of_blades_proc",
    "crt_maidenguard_dance_of_blades_stack",
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

-- Read-only export of the canonical registration list (v0.3.54-dev, issue 425 coverage).
-- The /crt_regression_test catalog-parity + sorted-order checks live in career_tweaker.lua,
-- which cannot see this file-local; expose the exact list they register against so a drift
-- between the two catalogs (or a reorder that breaks cross-peer NetworkLookup determinism)
-- is caught. Never mutate through this handle.
mod._crt_registered_buff_names = _CRT_BUFF_NAMES

local function _crt_pre_register_buffs()
    if not BuffTemplates then return end
    local NL = rawget(_G, "NetworkLookup")
    -- CRITICAL: NetworkLookup tables get a metatable with __index that ERRORS
    -- on missing keys (network_lookup.lua:2361). Read access via `t[key]`
    -- triggers the error; must use `rawget(t, key)` for existence checks.
    -- Hit 2026-05-22 — crashed crt's dofile on first iteration, cascaded into
    -- balance-is-nil errors at career_tweaker.lua:199 every state change.
    for _, name in ipairs(_CRT_BUFF_NAMES) do
        if rawget(BuffTemplates, name) == nil then
            BuffTemplates[name] = _crt_make_stub()
        end
        if NL and rawget(NL, "buff_templates") then
            -- #428: rejection remains visible to the exact-catalog fail-safe.
            network_lookup.register(rawget(NL, "buff_templates"), name)
        end
    end
end

_crt_pre_register_buffs()

-- Mod-registered buff-name REGISTRY (issue 425): every buff-template name this
-- mod (any module) registers into NetworkLookup.buff_templates, whatever its
-- prefix. Consumed by the hot-join replay filter below -- a prefix check alone
-- missed career_tweaker_tourney.lua's vanilla-prefixed registrations
-- (victor_priest_5_2_speed_buff; adversarial review 2026-07-11) -- and by the
-- /crt_regression_test no-raw-networked-funcs sweep. Modules ADD to it at load;
-- never remove (registrations are permanent for index determinism).
mod._crt_mod_registered_buff_names = mod._crt_mod_registered_buff_names or {}
for _, name in ipairs(_CRT_BUFF_NAMES) do
    mod._crt_mod_registered_buff_names[name] = true
end

-- ============================================================
-- Issue 425 wire safety: peer-parity gate + wire-safe proc/driver wrappers
-- ============================================================
-- The stub pre-registration above protects crt<->crt peers only. A peer WITHOUT
-- crt has NO entry at our NetworkLookup.buff_templates indices, so ANY networked
-- add that encodes a crt_* name fatals them on decode (BuffSystem.rpc_add_buff,
-- buff_system.lua:430, strict __index). Verified networked reach points in this
-- mod (the rest of the crt_* catalog is applied via LOCAL buff_extension:add_buff
-- / talent-apply paths and never rides an RPC):
--   * ProcFunctions.add_buff              (buff_templates.lua:1964-1972) -> rpc_add_buff
--   * ProcFunctions.add_buff_on_special_kill (buff_templates.lua:2251-2259) -> rpc_add_buff
--   * BuffSystem.add_buff                 (buff_system.lua:302-307)      -> rpc_add_buff
--   * BuffFunctionTemplates.functions.activate_server_buff_stacks_based_on_
--     overcharge_chunks (buff_function_templates.lua:2569) -> server-controlled
--     BuffSystem.add_buff -> rpc_add_buff broadcast + hot-join replay
--     (BuffSystem.hot_join_sync, buff_system.lua:80-93).
-- BOTH directions crash: a crt client's send reaches a non-crt host (and is
-- relayed to every other client, buff_system.lua:419-424); a crt host's send
-- reaches every non-crt client.
--
-- Fix shape (issue 371 gameplay-axis doctrine): the buff/boon axis cannot be
-- sender-substituted without changing gameplay, so the networked reworks go
-- INERT unless EVERY other human peer is positively confirmed to run crt
-- (peer-parity beacon, _lib_peer_parity.lua). Two layers, both UNCONDITIONAL
-- (never coupled to a menu toggle -- memory reference_vt2_wire_safety_never_
-- toggle_gated):
--   1. WIRE GUARDS (this block): the unsafe templates' buff_func/update_func
--      point at crt_wire_safe_* wrappers registered below. Function names are
--      resolved PER CALL (ProcFunctions[buff_func] buff_extension.lua:1351;
--      BuffFunctionTemplates.functions[update_func] buff_extension.lua:794),
--      so even a LIVE buff instance -- whose captured template subtable
--      survives a restore -- consults the live parity check on every proc/tick.
--      This closes the hot-join hole for procs already sitting on player units.
--   2. FEATURE GATE (apply engine below): BALANCE_MODS entries tagged
--      `network_unsafe = true` only apply while the beacon's settled state is
--      "enabled"; the beacon's on_enable/on_disable callbacks re-run apply so
--      the talent tables degrade to vanilla for the lobby state and re-apply
--      when parity returns.
-- `_career_tweaker_balance_hooks.lua` also filters server-controlled CRT buffs
-- from the pre-ack hot-join replay; drivers resync after parity returns.

-- The two parity reads for this file. Both route through the entry file's
-- composite floors (#1158), not the beacon directly, so an uncommitted
-- transport or a post-boot catalog shift blocks them too. A missing or erroring
-- floor counts as "not safe", and solo passes both (the classifier treats a
-- lobby with no OTHER humans as all-present).
--
-- The split is load-bearing. Every individual send consults the LIVE read,
-- which re-evaluates the roster per call. Apply/restore churn and the tourney
-- port follow the SETTLED read, which the beacon debounces so talent tables do
-- not flicker on an ack race. Collapsing live onto settled would keep sending
-- for up to one 0.5s poll after a non-crt peer joins; wire_live in
-- _crt_wire_policy.lua carries that rationale, and issue 506 (the lib commits
-- _applied before firing callbacks) is what keeps the settled read correct when
-- an apply engine calls it from inside one.
local function _crt_wire_parity_live()
    return type(mod._crt_wire_live) == "function"
        and mod._crt_wire_live() == true
end

local function _crt_parity_gate_ok()
    return type(mod._crt_wire_safe) == "function"
        and mod._crt_wire_safe() == true
end

-- [crt:425] diagnostics: engine printf (user runs with mod-logging OFF), fired
-- on state TRANSITIONS only so an on_kill proc storm can't spam the log.
local _crt_wire_block_logged = {}
local function _crt_log_wire_block(site)
    if _crt_wire_block_logged[site] then return end
    _crt_wire_block_logged[site] = true
    pcall(printf, "[crt:425] wire guard: blocked modded buff send at %s (a lobby peer lacks crt); vanilla behavior for this session state", tostring(site))
end

local function _crt_log_wire_clear()
    if next(_crt_wire_block_logged) == nil then return end
    _crt_wire_block_logged = {}
    pcall(printf, "[crt:425] wire guard: parity restored, modded buff sends re-enabled")
end

-- Wire-safe wrapper registrations. Idempotent ensure so the unsafe reworks'
-- custom_apply can re-run it (belt-and-suspenders against load-order surprises
-- on the host tables); registered once at file load in the normal case.
local function _crt_ensure_wire_safe_funcs()
    local PF = rawget(_G, "ProcFunctions")
    if PF then
        wire_runtime.ensure_timed_proc(PF, wire_policy, _crt_wire_parity_live,
            _crt_log_wire_block, _crt_log_wire_clear)
        if PF.crt_wire_safe_add_buff == nil then
            -- Same contract as vanilla ProcFunctions.add_buff; consulted per
            -- call by name so live buffs obey the gate too.
            PF.crt_wire_safe_add_buff = function(unit, buff, params)
                if not _crt_wire_parity_live() then
                    _crt_log_wire_block("add_buff")
                    return
                end
                _crt_log_wire_clear()
                return PF.add_buff(unit, buff, params)
            end
        end
        if PF.crt_wire_safe_add_buff_on_special_kill == nil then
            PF.crt_wire_safe_add_buff_on_special_kill = function(owner_unit, buff, params)
                -- Cheap pre-filter mirroring vanilla's special gate
                -- (buff_templates.lua:2244) so a non-special kill neither logs a
                -- block nor pays the parity check. The delegate re-checks it.
                local killed_breed = params and params[2]
                if not (killed_breed and killed_breed.special) then return end
                if not _crt_wire_parity_live() then
                    _crt_log_wire_block("add_buff_on_special_kill")
                    return
                end
                _crt_log_wire_clear()
                return PF.add_buff_on_special_kill(owner_unit, buff, params)
            end
        end
    end
    local BFT = rawget(_G, "BuffFunctionTemplates")
    local fns = BFT and BFT.functions
    if fns and fns.crt_wire_safe_overcharge_chunks_driver == nil then
        -- Wraps activate_server_buff_stacks_based_on_overcharge_chunks
        -- (buff_function_templates.lua:2544). Under parity: exact vanilla
        -- behavior. Parity missing: degrade to zero chunks by stripping this
        -- driver's own server-controlled stacks -- remove_server_controlled_buff
        -- sends only integer ids (buff_system.lua:340), wire-safe for every
        -- receiver (nil-guarded lookup at :442-444) -- so the stacks AND their
        -- registry entries (the hot-join replay source) self-clean on degrade.
        fns.crt_wire_safe_overcharge_chunks_driver = function(unit, buff, params, world)
            if _crt_wire_parity_live() then
                _crt_log_wire_clear()
                return fns.activate_server_buff_stacks_based_on_overcharge_chunks(unit, buff, params, world)
            end
            if not (Managers.state.network and Managers.state.network.is_server) then return end
            local ids = buff.stack_server_ids
            if ids and #ids > 0 then
                _crt_log_wire_block("overcharge_chunks_driver")
                local buff_system = Managers.state.entity:system("buff_system")
                for _ = 1, #ids do
                    local sid = table.remove(ids)
                    if sid then
                        pcall(function() buff_system:remove_server_controlled_buff(unit, sid) end)
                    end
                end
            end
        end
    end
    if fns and fns.crt_wire_safe_distance_aura_driver == nil then
        -- Wraps activate_buff_on_distance (buff_function_templates.lua:2759) --
        -- the server-only aura driver that grants buff_to_add as a
        -- SERVER-CONTROLLED buff (:2801) to every side unit in range. Used by
        -- trn_wh_priest, whose patched buff_to_add is a mod-registered name
        -- (career_tweaker_tourney.lua). Under parity: exact vanilla behavior.
        -- Parity missing: strip the aura's existing server-controlled stacks
        -- from every side unit (mirrors vanilla's own out-of-range removal
        -- branch, :2789-2797 -- integer-id RPC, wire-safe on every receiver)
        -- and add nothing, until the tourney gate's restore lands and the
        -- vanilla driver takes back over.
        fns.crt_wire_safe_distance_aura_driver = function(owner_unit, buff, params)
            if _crt_wire_parity_live() then
                _crt_log_wire_clear()
                return fns.activate_buff_on_distance(owner_unit, buff, params)
            end
            if not (Managers.state.network and Managers.state.network.is_server) then return end
            local template = buff.template
            local buff_to_add = template and template.buff_to_add
            if type(buff_to_add) ~= "string" then return end
            local side = Managers.state.side and Managers.state.side.side_by_unit[owner_unit]
            if not side then return end
            local units = side.PLAYER_AND_BOT_UNITS
            if not units then return end
            local buff_system = Managers.state.entity:system("buff_system")
            local removed = false
            for i = 1, #units do
                local unit = units[i]
                if Unit.alive(unit) then
                    local be = ScriptUnit.has_extension(unit, "buff_system")
                    local b = be and be:get_non_stacking_buff(buff_to_add)
                    local sid = b and b.server_id
                    if sid then
                        pcall(function() buff_system:remove_server_controlled_buff(unit, sid) end)
                        removed = true
                    end
                end
            end
            if removed then _crt_log_wire_block("distance_aura_driver") end
        end
    end
    if fns and fns.crt_maidenguard_dance_blocking_dodge == nil then
        -- Dance of Blades (#473): retain only vanilla's blocking-dodge branch.
        -- The replacement hostile-hit proc is a separate server-authoritative,
        -- wire-gated talent buff, so a non-blocking dodge deliberately grants no
        -- power and sends no RPC.
        fns.crt_maidenguard_dance_blocking_dodge = function(owner_unit, buff)
            if not (owner_unit and Unit.alive(owner_unit)) then return end
            local status = ScriptUnit.has_extension(owner_unit, "status_system")
            if not (status and status.blocking) then return end
            local extension = ScriptUnit.has_extension(owner_unit, "buff_system")
            local names = buff.template and buff.template.dodge_buffs_to_add
            if not (extension and type(names) == "table") then return end
            for i = 1, #names do extension:add_buff(names[i]) end
        end
    end
end
_crt_ensure_wire_safe_funcs()

-- ============================================================
-- Talent Rework Framework
-- ============================================================
-- Each entry in BALANCE_MODS is a user-togglable talent rework.
-- The setting_id key must match a checkbox in career_tweaker_data.lua.
--
-- Structure:
--   patches = { { buff = "buff_template_name", sub_index = 1, field = "field_name", value = new_value }, ... }
--   custom_apply(originals)   — optional, for changes beyond simple field patches
--   custom_restore(originals) — optional, paired with custom_apply
--
-- Patches mutate BuffTemplates[buff].buffs[sub_index or 1][field] at runtime.
-- Changes take effect next time TalentExtension.apply_buffs_from_talents() runs
-- (i.e. next mission load or talent change).
--
-- Hook-based reworks check their setting via mod:get() on every call,
-- so they activate/deactivate without needing apply/restore cycles.

-- Minimum value bloodlust_health gets clamped to when the
-- rework_general_thp_kill_minimum toggle is on. Vanilla minimum is skaven_horde
-- (slaves) at 1; beastmen_horde / chaos_horde sit at 1.5; skaven_roamer at 2.
-- Floor of 1.5 lifts slaves to match the other hordes without touching roamers
-- or anything above.
local _MIN_THP_ON_KILL = 1.5

-- Declarative talent/buff rework definitions live in one dependency-injected
-- catalogue owner. Hook registration and apply/restore order stay below.
local _build_balance_catalog = mod:dofile("scripts/mods/career_tweaker/_crt_balance_catalog")
local BALANCE_MODS = _build_balance_catalog({
    mod = mod,
    wire_policy = wire_policy,
    make_stub = _crt_make_stub,
    ensure_wire_safe_funcs = _crt_ensure_wire_safe_funcs,
    min_thp_on_kill = _MIN_THP_ON_KILL,
})

-- Hook-only talent presentation, crit policy, and hot-join wire safety live in
-- one load-once module so the balance catalogue remains a data/apply concern.
mod:dofile("scripts/mods/career_tweaker/_career_tweaker_balance_hooks")

-- ============================================================
-- Hook: Extend parry window when WHC parry-crit rework is on
-- ============================================================
-- Vanilla parry window is 0.5s (hardcoded in ActionBlock and ActionMeleeStart).
-- Extended window doubles it to 1.0s when the toggle is enabled.
local _PARRY_WINDOW_EXTENDED_S = 1.0

-- ActionBlock.client_owner_start_action sets `status_extension.timed_block = t + 0.5`
-- (action_block.lua:45). hook_safe runs AFTER the original, so our overwrite to
-- t + _PARRY_WINDOW_EXTENDED_S lands last and wins.
-- Helper: detect "Grail Knight + Virtue of Discipline selected" via the
-- status extension's owner unit. Read each call so toggling is live.
local function _gk_virtue_of_discipline_active(status_extension)
    if not mod:get("rework_es_questingknight_virtue_of_discipline_double_parry") then return false end
    if not status_extension then return false end
    local owner = status_extension.unit
    if not owner then return false end
    local talent_ext = ScriptUnit.has_extension(owner, "talent_system")
    if not talent_ext or talent_ext._career_name ~= "es_questingknight" then return false end
    return talent_ext:has_talent("markus_questing_knight_parry_increased_power", "empire_soldier", true)
end

mod:hook_safe("ActionBlock", "client_owner_start_action", function(self, new_action, t)
    local status_extension = self._status_extension
    if mod:get("rework_wh_captain_parry_window") or _gk_virtue_of_discipline_active(status_extension) then
        if status_extension and status_extension.timed_block then
            status_extension.timed_block = t + _PARRY_WINDOW_EXTENDED_S
        end
    end
end)

-- ActionMeleeStart's charge-block is set in client_owner_post_update (action_melee_start.lua:42)
-- via `status_extension.timed_block = t + 0.5`. We hook_safe the same method so our extended
-- write lands AFTER the original on every tick that the charge-block branch fires.
-- Note: ActionMeleeStart inherits from ActionDummy and stores its extension as
-- `self.status_extension` (no underscore — action_dummy.lua:9), unlike ActionBlock above.
mod:hook_safe("ActionMeleeStart", "client_owner_post_update", function(self, dt, t, world)
    local status_extension = self.status_extension
    if mod:get("rework_wh_captain_parry_window") or _gk_virtue_of_discipline_active(status_extension) then
        if status_extension and status_extension.timed_block then
            status_extension.timed_block = t + _PARRY_WINDOW_EXTENDED_S
        end
    end
end)

-- Zealot Holy Fervour green-to-THP rework. The vanilla convert_to_temp route
-- mutates GameSession on the server or requests the server from a client,
-- clamps to current permanent health, and adds rather than replaces THP.
-- hook_safe runs after the ability buffs/lunge, so Feel Nothing is already up.
mod:hook_safe("CareerAbilityWHZealot", "_run_ability", function(self)
    if not mod:get("rework_wh_zealot_ability_green_to_thp") then return end
    local owner_unit = self._owner_unit
    if not owner_unit then return end
    local health_extension = ScriptUnit.has_extension(owner_unit, "health_system")
    if not health_extension then return end
    local permanent = health_extension:current_permanent_health()
    if permanent and permanent > 0 then
        health_extension:convert_to_temp(permanent)
    end
end)

-- ============================================================
-- Hook: Salvaged Ammunition gate removal (mutate ProcFunctions)
-- ============================================================
-- Vanilla `victor_bounty_hunter_ammo_fraction_gain_out_of_ammo` (defined in
-- buff_templates.lua under the global `ProcFunctions` table, line 3031) only
-- restores ammo on melee elite kill when BOTH reserve and clip are empty
-- (`if current_ammo < 1 and clip_ammo < 1`, line 3052). We replace the table
-- entry with a wrapper: with the rework toggle OFF (the default) it delegates
-- to the captured vanilla fn (`_orig_salvaged_ammo_fn`); with it ON it runs a
-- gate-less version. `_orig_salvaged_ammo_fn` is the LIVE toggle-off delegate,
-- read on every proc via the mod:get gate below, NOT a dormant restore handle.
-- There is no apply/restore pair and none is needed: flipping the toggle off
-- returns vanilla behavior on the next proc (issue 507; the earlier comment
-- mischaracterized this save as a never-wired shutdown restore).
if ProcFunctions and ProcFunctions.victor_bounty_hunter_ammo_fraction_gain_out_of_ammo then
    local _orig_salvaged_ammo_fn = ProcFunctions.victor_bounty_hunter_ammo_fraction_gain_out_of_ammo
    ProcFunctions.victor_bounty_hunter_ammo_fraction_gain_out_of_ammo = function(owner_unit, buff, params)
        if not mod:get("rework_wh_bountyhunter_salvaged_ammo_no_gate_and_passive_reload") then
            return _orig_salvaged_ammo_fn(owner_unit, buff, params)
        end
        -- Gate-less version: replicate vanilla minus the out-of-ammo check.
        -- `is_local` is a file-local helper in vanilla DLC source — inlined here.
        local _player = Managers.player and Managers.player:owner(owner_unit)
        if not _player or _player.remote then return end
        if not ALIVE[owner_unit] then return end
        local killed_unit_breed_data = params and params[2]
        if not killed_unit_breed_data or not killed_unit_breed_data.elite then return end
        local buff_template = buff and buff.template
        if not buff_template then return end
        local weapon_slot = "slot_ranged"
        local inventory_extension = ScriptUnit.has_extension(owner_unit, "inventory_system")
        if not inventory_extension then return end
        local slot_data = inventory_extension:get_slot_data(weapon_slot)
        if not slot_data then return end
        local right_hand_ammo_extension = ScriptUnit.has_extension(slot_data.right_unit_1p, "ammo_system")
        local left_hand_ammo_extension  = ScriptUnit.has_extension(slot_data.left_unit_1p,  "ammo_system")
        local ammo_extension = right_hand_ammo_extension or left_hand_ammo_extension
        if not ammo_extension then return end
        local fraction = buff_template.ammo_bonus_fraction
        if type(fraction) ~= "number" then return end
        local ammo_amount = math.max(math.round(ammo_extension:max_ammo() * fraction), 1)
        ammo_extension:add_ammo_to_reserve(ammo_amount)
    end
end

-- ============================================================
-- Hook: Indiscriminate Blast — refund 1% cooldown per ability kill
-- ============================================================
-- Wraps `ProcFunctions.victor_bounty_blast_streak_activation` (the on-kill
-- proc bound to talent `victor_bountyhunter_activated_ability_blast_shotgun`).
-- The vanilla proc handles stack-based cooldown rewards; we additionally call
-- `career_extension:reduce_activated_ability_cooldown_percent(0.01)` when the
-- killing blow's damage source is the BH ability weapon (matches the
-- detection at buff_templates.lua:3586 for the existing cooldown-on-kill proc).
if ProcFunctions and ProcFunctions.victor_bounty_blast_streak_activation then
    local _orig_blast_streak_fn = ProcFunctions.victor_bounty_blast_streak_activation
    ProcFunctions.victor_bounty_blast_streak_activation = function(owner_unit, buff, params)
        _orig_blast_streak_fn(owner_unit, buff, params)
        if not mod:get("rework_wh_bountyhunter_indiscriminate_blast_refund_per_kill") then return end
        if not ALIVE[owner_unit] then return end
        local killing_blow = params and params[1]
        if not killing_blow or not DamageDataIndex then return end
        local source = killing_blow[DamageDataIndex.DAMAGE_SOURCE_NAME]
        if source ~= "victor_bountyhunter_career_skill_weapon"
           and source ~= "victor_bountyhunter_career_skill_weapon_vs" then
            return
        end
        local career_extension = ScriptUnit.has_extension(owner_unit, "career_system")
        if not career_extension then return end
        career_extension:reduce_activated_ability_cooldown_percent(0.01)
    end
end

-- ============================================================
-- Hook: Double-Shotted damage doubling — apply buff on BH ability activation
-- ============================================================
-- `CareerExtension.start_activated_ability_cooldown` fires once per ability
-- activation, on every career, so we filter for BH + Double-Shotted talent +
-- the toggle, then add the registered `crt_bh_double_shotted_damage_buff`
-- (registered in BALANCE_MODS custom_apply — must be enabled for the buff
-- template to exist). The buff carries `stat_buff = "power_level_ranged"`
-- multiplier 1.0 (= +100% ranged damage when consumed additively via
-- action_utils.lua:353's stacking formula), 3s duration — wide enough for
-- the ability shot itself plus a brief overhang.
-- CAVEAT: any ranged shot during the 3s window gets the bonus, not strictly
-- the ability shot. The "buff arrives in time for the ability shot" property
-- relies on `start_activated_ability_cooldown` being invoked at the START of
-- the ability flow (verified in CareerAbilityWHZealot:_run_ability:254 and
-- equivalents) — for the BH weapon-based ability, the cooldown call happens
-- inside the career skill weapon's fire action which runs before damage
-- calculation, so timing is correct.
-- NOTE: This hook is the SINGLE consolidation point for every rework that
-- needs `CareerExtension:start_activated_ability_cooldown`. Per memory
-- `feedback_vmf_hook_safe_no_chain.md`, two `mod:hook_safe(Class, method,
-- ...)` for the same Class+method silently shadow each other — they must be
-- consolidated into one callback. Add new gated branches inside this body
-- instead of registering a second hook_safe.
mod:hook_safe("CareerExtension", "start_activated_ability_cooldown", function(self)
    local owner_unit = self._owner_unit
    if not owner_unit then return end
    local talent_extension = ScriptUnit.has_extension(owner_unit, "talent_system")

    -- Branch: Foot Knight Valiant Charge — Battering Ram talent refunds 1/3
    -- so the 45s baseline returns to 30s effective.
    if mod:get("rework_es_knight_valiant_charge_great_foes_45s_battering_ram_30s")
       and self._career_name == "es_knight"
       and talent_extension
       and talent_extension:has_talent("markus_knight_wide_charge", "empire_soldier", true) then
        self:reduce_activated_ability_cooldown_percent(1/3)
    end

    -- Branch: BH Double-Shotted damage doubling — apply the registered
    -- ranged-power buff for 3 seconds after activation.
    if not mod:get("rework_wh_bountyhunter_double_shotted_damage_double") then return end
    if self._career_name ~= "wh_bountyhunter" then return end
    if not talent_extension then return end
    if not talent_extension:has_talent("victor_bountyhunter_activated_ability_railgun", "witch_hunter", true) then
        return
    end
    local buff_extension = ScriptUnit.has_extension(owner_unit, "buff_system")
    -- Pre-registered stub is always present after mod load; check `_crt_pending`
    -- to detect "toggle not applied" so the real buff body isn't there yet.
    local bt = BuffTemplates and BuffTemplates.crt_bh_double_shotted_damage_buff
    if not buff_extension or not bt or bt._crt_pending then
        return
    end
    buff_extension:add_buff("crt_bh_double_shotted_damage_buff")
end)

-- ============================================================
-- Hook: Fires from Ash — add +0.5 THP per burning kill
-- ============================================================
-- Wraps `ProcFunctions.sienna_adept_reduce_activated_ability_cooldown_on_burning_enemy_killed`
-- (buff_templates.lua:3737) — the proc that fires when Sienna kills a burning
-- enemy. After the vanilla cooldown reduction (already patched to 1% via
-- BALANCE_MODS), additionally grants +0.5 THP to Sienna via
-- DamageUtils.heal_network (matches the THP-grant pattern used by
-- `thp_tank_stagger_func` at buff_templates.lua:681+).
if ProcFunctions and ProcFunctions.sienna_adept_reduce_activated_ability_cooldown_on_burning_enemy_killed then
    local _orig_fires_from_ash_fn = ProcFunctions.sienna_adept_reduce_activated_ability_cooldown_on_burning_enemy_killed
    ProcFunctions.sienna_adept_reduce_activated_ability_cooldown_on_burning_enemy_killed = function(owner_unit, buff, params)
        _orig_fires_from_ash_fn(owner_unit, buff, params)
        if not mod:get("rework_bw_adept_fires_from_ash_1pct_plus_thp") then return end
        if not ALIVE[owner_unit] then return end
        -- Issue 405: heal_network fasserts "Only server can heal" on clients
        -- (damage_utils.lua:2636). Every vanilla heal_from_proc call site gates
        -- on Managers.player.is_server (buff_templates.lua:325/:404/...); the
        -- proc also runs on the host for a client's kill, so the host instance
        -- grants the THP and the client instance must no-op.
        if not (Managers and Managers.player and Managers.player.is_server) then return end
        if DamageUtils and DamageUtils.heal_network then
            DamageUtils.heal_network(owner_unit, owner_unit, 0.5, "heal_from_proc")
        end
    end
end
-- Issue 405 post-fix regression marker: the Fires-from-Ash proc heal above
-- carries the is_server gate (without it, clients CTD on the heal_network
-- fassert "Only server can heal", damage_utils.lua:2636). Set at LOAD beside
-- the gate so /crt_regression_test can assert it without a source read
-- (issue 511 pattern); asserted by issue405_heal_network_is_server_gated.
mod._crt405_heal_is_server_gated = true

-- ============================================================
-- Hook: Vanhel's Danse Macabre per-skeleton stacks
-- ============================================================
-- Vanilla `thank_you_skeletal_add` (buff_settings_shovel.lua:952) gates on
-- `num_controlled >= 4` and applies the (max_stacks=1) buff once. With the
-- rework on, drop the gate and add one stack every time a skeleton is raised
-- (the BALANCE_MODS patch lifts max_stacks to 12 and lowers multiplier to
-- 0.02, so 12 skeletons → 24% AS cap). Mirror gating-off for the remove proc.
if ProcFunctions and ProcFunctions.thank_you_skeletal_add then
    local _orig_thank_you_add = ProcFunctions.thank_you_skeletal_add
    ProcFunctions.thank_you_skeletal_add = function(owner_unit, buff, params)
        if not mod:get("rework_bw_necromancer_vanhels_per_skeleton_as") then
            return _orig_thank_you_add(owner_unit, buff, params)
        end
        local buff_extension = ScriptUnit.has_extension(owner_unit, "buff_system")
        if not buff_extension or not buff or not buff.template then return end
        local buff_to_add = buff.template.buff_to_add
        if buff_to_add then
            buff_extension:add_buff(buff_to_add)
        end
    end
end

if ProcFunctions and ProcFunctions.thank_you_skeletal_remove then
    local _orig_thank_you_remove = ProcFunctions.thank_you_skeletal_remove
    ProcFunctions.thank_you_skeletal_remove = function(owner_unit, buff, params)
        if not mod:get("rework_bw_necromancer_vanhels_per_skeleton_as") then
            return _orig_thank_you_remove(owner_unit, buff, params)
        end
        local buff_extension = ScriptUnit.has_extension(owner_unit, "buff_system")
        if not buff_extension or not buff or not buff.template then return end
        local buff_to_remove = buff.template.buff_to_remove
        if not buff_to_remove then return end
        local stacking = buff_extension:get_stacking_buff(buff_to_remove)
        if stacking and #stacking > 0 then
            buff_extension:remove_buff(stacking[1].id)
        end
    end
end

-- ============================================================
-- Hook: Engineer Gromril Plated Shot — minigun starts at full speed
-- ============================================================
-- Engineer's minigun normally spools up: action sets `self._current_rps` to
-- `self._initial_rps` and lerps toward `self._max_rps` over a spinup window.
-- When the rework is on AND the player has the Gromril Plated Shot talent
-- (`bardin_engineer_armor_piercing_ability`), force `_current_rps` to
-- `_max_rps` immediately at action start so first shot fires at full rate.
-- ActionCareerDREngineer inherits from ActionMinigun
-- (action_career_dr_engineer.lua:3). hook_safe runs after the original
-- start sets the lerp values; our overwrite lands last.
mod:hook_safe("ActionCareerDREngineer", "client_owner_start_action", function(self)
    if not mod:get("rework_dr_engineer_gromril_plated_shot_full_speed") then return end
    local owner = self.owner_unit or self._owner_unit
    if not owner then return end
    local talent_ext = ScriptUnit.has_extension(owner, "talent_system")
    if not talent_ext or not talent_ext:has_talent("bardin_engineer_armor_piercing_ability", "dwarf_ranger", true) then
        return
    end
    if self._max_rps then
        self._current_rps = self._max_rps
    end
end)

-- Visual spinup is handled by ActionCareerDREngineerSpin — bypass it too so
-- the windup animation doesn't lag behind the actual fire rate.
mod:hook_safe("ActionCareerDREngineerSpin", "client_owner_start_action", function(self)
    if not mod:get("rework_dr_engineer_gromril_plated_shot_full_speed") then return end
    local owner = self.owner_unit or self._owner_unit
    if not owner then return end
    local talent_ext = ScriptUnit.has_extension(owner, "talent_system")
    if not talent_ext or not talent_ext:has_talent("bardin_engineer_armor_piercing_ability", "dwarf_ranger", true) then
        return
    end
    if self._visual_spinup_max then
        self._visual_spinup = self._visual_spinup_max
    end
    if self._visual_spinup_time then
        self._visual_spinup_time = 0.001
    end
end)

-- Foot Knight Battering Ram cooldown refund is now consolidated into the
-- shared `start_activated_ability_cooldown` hook above (see the FK branch).
-- Two `mod:hook_safe` calls on the same Class+method silently shadow per
-- `feedback_vmf_hook_safe_no_chain.md`; the consolidation fixes the silent
-- shadow that previously disabled the BH Double-Shotted damage-doubling
-- branch in v0.2.27 → v0.2.32 (logged as "Attempting to rehook active hook"
-- warning at mod load).

-- ============================================================
-- Hook: Universal Mainstay — apply +15% stagger to every player
-- ============================================================
-- Vanilla VT2 has no universal level-15 stagger talent, so this rework
-- applies the buff DIRECTLY to every player whenever the toggle is on,
-- regardless of career or talent selection. Hooks `TalentExtension:apply_buffs_from_talents`
-- (the function vanilla calls after rolling out talent buffs) and adds the
-- `crt_mainstay_universal_stagger` buff (registered in BALANCE_MODS) if it
-- isn't already on the player. The buff template stub is always pre-
-- registered at mod load (see top-of-file _crt_pre_register_buffs), so the
-- guard checks `_crt_pending` instead of nil to detect "toggle not applied"
-- (real body hasn't replaced the stub yet).
mod:hook_safe("TalentExtension", "apply_buffs_from_talents", function(self)
    if not mod:get("rework_general_mainstay_stagger_15pct") then return end
    local bt = BuffTemplates and BuffTemplates.crt_mainstay_universal_stagger
    if not bt or bt._crt_pending then return end
    local owner_unit = self._unit or self.unit
    if not owner_unit then return end
    local buff_extension = ScriptUnit.has_extension(owner_unit, "buff_system")
    if not buff_extension then return end
    if buff_extension:has_buff_type("crt_mainstay_universal_stagger") then return end
    buff_extension:add_buff("crt_mainstay_universal_stagger")
end)

-- ============================================================
-- Custom proc: burning elite/special kill (for Unchained Numb to Pain)
-- ============================================================
-- Registers `crt_add_buff_on_burning_special_or_elite_kill` in ProcFunctions
-- the first time the mod loads. Idempotent — if the entry already exists we
-- leave it alone (the function reads `mod:get` per call so re-registration
-- isn't required when the toggle changes). Mirrors the burning-detection
-- pattern from `sienna_adept_reduce_activated_ability_cooldown_on_burning_enemy_killed`
-- (buff_templates.lua:3737-3759): inspect killed unit's buff_extension for
-- any of the four burning perk names; require killed breed to be elite or
-- special; add the buff_to_add.
if ProcFunctions and ProcFunctions.crt_add_buff_on_burning_special_or_elite_kill == nil then
    ProcFunctions.crt_add_buff_on_burning_special_or_elite_kill = function(owner_unit, buff, params)
        if not ALIVE[owner_unit] then return end
        local killing_blow      = params and params[1]
        local killed_breed_data = params and params[2]
        if not killing_blow or not killed_breed_data then return end
        if not (killed_breed_data.elite or killed_breed_data.special) then return end
        local killed_unit = killing_blow[DamageDataIndex.HIT_UNIT]
        if not killed_unit then return end
        local victim_buff_ext = ScriptUnit.has_extension(killed_unit, "buff_system")
        local was_burning = false
        if victim_buff_ext then
            local burning_perks = { "burning", "burning_balefire", "burning_elven_magic", "burning_warpfire" }
            for i = 1, #burning_perks do
                if victim_buff_ext:has_buff_perk(burning_perks[i]) then was_burning = true; break end
            end
        end
        if not was_burning then return end
        local owner_buff_ext = ScriptUnit.has_extension(owner_unit, "buff_system")
        if not owner_buff_ext or not buff or not buff.template then return end
        local buff_to_add = buff.template.buff_to_add
        if buff_to_add then owner_buff_ext:add_buff(buff_to_add) end
    end
end

-- Mercenary Enhanced Training proc (rework_es_mercenary_enhanced_training_tiered).
-- Replicates vanilla gain_markus_mercenary_passive_proc (buff_templates.lua:3522)
-- EXACTLY except the Enhanced-Training branch: with markus_mercenary_passive_improved
-- taken, a light/heavy hitting >=2 targets grants min(target_number,4) stacks of
-- crt_merc_enhanced_training_as (5% AS, 6s). The outer gate is lowered to >=2 so
-- the ET branch can see 2 targets; every other branch still requires
-- >= buff.template.targets (3), so base Paced Strikes is unchanged. target_number
-- is params[4], attack_type params[2].
if ProcFunctions and ProcFunctions.crt_enhanced_training_proc == nil then
    ProcFunctions.crt_enhanced_training_proc = function(owner_unit, buff, params)
        if not Managers.state.network.is_server then return end
        if not ALIVE[owner_unit] then return end
        local buff_template = buff.template
        local target_number = params[4]
        local attack_type   = params[2]
        if not (target_number and (attack_type == "light_attack" or attack_type == "heavy_attack")) then return end
        local buff_system = Managers.state.entity:system("buff_system")
        local talent_extension = ScriptUnit.extension(owner_unit, "talent_system")
        local buff_to_add = buff_template.buff_to_add
        local buff_applied = true
        if talent_extension:has_talent("markus_mercenary_passive_improved", "empire_soldier", true) then
            if not _crt_wire_parity_live() then
                -- issue 425: a lobby peer lacks crt, so the crt_* stack name may
                -- not ride rpc_add_buff. Degrade this branch to the EXACT vanilla
                -- Enhanced Training behavior (gain_markus_mercenary_passive_proc,
                -- buff_templates.lua:3537-3542): >= 4 targets grants the flat
                -- vanilla improved buff, else no proc.
                _crt_log_wire_block("crt_enhanced_training_proc")
                if target_number >= 4 then
                    buff_system:add_buff(owner_unit, "markus_mercenary_passive_improved", owner_unit, false)
                else
                    buff_applied = false
                end
            elseif target_number >= 2 then
                _crt_log_wire_clear()
                local stacks = math.min(target_number, 4)
                for _ = 1, stacks do
                    buff_system:add_buff(owner_unit, "crt_merc_enhanced_training_as", owner_unit, false)
                end
            else
                buff_applied = false
            end
        elseif target_number >= buff_template.targets then
            if talent_extension:has_talent("markus_mercenary_passive_group_proc", "empire_soldier", true) then
                local side = Managers.state.side.side_by_unit[owner_unit]
                local units = side and side.PLAYER_AND_BOT_UNITS
                if units then
                    for i = 1, #units do
                        if HEALTH_ALIVE[units[i]] then buff_system:add_buff(units[i], buff_to_add, owner_unit, false) end
                    end
                end
            elseif talent_extension:has_talent("markus_mercenary_passive_power_level_on_proc", "empire_soldier", true) then
                buff_system:add_buff(owner_unit, "markus_mercenary_passive_power_level", owner_unit, false)
                buff_system:add_buff(owner_unit, buff_to_add, owner_unit, false)
            else
                buff_system:add_buff(owner_unit, buff_to_add, owner_unit, false)
            end
        else
            buff_applied = false
        end
        if buff_applied and target_number >= buff_template.targets
            and talent_extension:has_talent("markus_mercenary_passive_defence_on_proc", "empire_soldier", true) then
            buff_system:add_buff(owner_unit, "markus_mercenary_passive_defence", owner_unit, false)
        end
    end
end

-- crt_unchained_ult_max_us (#8): static buff added on Unchained career-skill use
-- when rework_bw_unchained_career_skill_max_us is on. +60% melee power for 10s ==
-- the max Unstable Strength melee bonus (6x10% == 5x12% == 0.60) regardless of
-- current overcharge. Filled here (real template) over the pre-registered stub.
if BuffTemplates and (BuffTemplates.crt_unchained_ult_max_us == nil or (rawget(BuffTemplates, "crt_unchained_ult_max_us") or {})._crt_pending) then
    BuffTemplates.crt_unchained_ult_max_us = {
        buffs = { { stat_buff = "power_level_melee", multiplier = 0.60, duration = 10, name = "crt_unchained_ult_max_us", icon = "sienna_unchained_activated_ability_power_on_enemies_hit" } },
    }
end

-- Unchained career-ability hook (#7 Fuel for the Fire vent 25% + #8 max US stacks).
-- ONE hook on CareerAbilityBWUnchained._run_ability serving both, each gated on its
-- own toggle read per-call (no apply/restore -- VMF deactivates the hook when crt
-- is disabled). #7: only when the Fuel for the Fire talent is equipped, capture
-- overcharge before the original (which calls overcharge_extension:reset()), then
-- restore 75% afterward so the ult clears only 25%. #8: add the max-US burst buff.
-- (Distinct class from the existing CareerAbilityWHZealot._run_ability hook above,
-- so no VMF duplicate-hook collision.)
mod:hook("CareerAbilityBWUnchained", "_run_ability", function(func, self, ...)
    local owner_unit = self._owner_unit
    local oce, oc_before
    if owner_unit and ALIVE[owner_unit] and mod:get("rework_bw_unchained_fuel_for_the_fire_vent") then
        local talent_ext = ScriptUnit.has_extension(owner_unit, "talent_system")
        if talent_ext and talent_ext:has_talent("sienna_unchained_activated_ability_power_on_enemies_hit", "bright_wizard", true) then
            oce = ScriptUnit.has_extension(owner_unit, "overcharge_system")
            if oce then oc_before = oce:get_overcharge_value() end
        end
    end
    func(self, ...)
    if oce and oc_before and oc_before > 0 then
        oce.overcharge_value = oc_before * 0.75
        pcall(function() oce:set_animation_variable() end)
    end
    if owner_unit and ALIVE[owner_unit] and mod:get("rework_bw_unchained_career_skill_max_us") then
        local be = self._buff_extension or ScriptUnit.has_extension(owner_unit, "buff_system")
        if be then pcall(function() be:add_buff("crt_unchained_ult_max_us") end) end
    end
end)

-- ============================================================
-- Field-patch apply/restore engine
-- ============================================================

local _originals = {}

local function apply_balance_mods()
    if not BuffTemplates then return end

    for setting_id, saved in pairs(_originals) do
        for _, entry in ipairs(saved) do
            local template = BuffTemplates[entry.buff]
            local sub_buff = template and template.buffs and template.buffs[entry.sub_index or 1]
            if sub_buff then
                sub_buff[entry.field] = entry.old_value
            end
        end
        local def = BALANCE_MODS[setting_id]
        if def and def.custom_restore then
            def.custom_restore(saved)
        end
    end
    _originals = {}

    -- issue 425 peer-parity gate: entries tagged `network_unsafe = true` put
    -- crt_* names onto vanilla networked buff paths, so they only apply while
    -- the beacon's settled state is "enabled" (solo counts as parity). The gate
    -- is SAFETY infrastructure, deliberately not a menu toggle; the user's
    -- saved setting is never overwritten -- the entry just stays vanilla for
    -- this apply pass and re-applies when the beacon flips back (its
    -- on_enable/on_disable callbacks re-run this function).
    local parity_ok = _crt_parity_gate_ok()
    local parity_skipped = nil

    for setting_id, def in pairs(BALANCE_MODS) do
        if mod:get(setting_id) then
            local ok_available, available = true, true
            if type(def.available) == "function" then ok_available, available = pcall(def.available) end
            if (def.network_unsafe and not parity_ok) or not (ok_available and available == true) then
                parity_skipped = parity_skipped or {}
                parity_skipped[#parity_skipped + 1] = setting_id
            else
                local saved = {}
                for _, patch in ipairs(def.patches) do
                    local template = BuffTemplates[patch.buff]
                    local sub_index = patch.sub_index or 1
                    local sub_buff = template and template.buffs and template.buffs[sub_index]
                    if sub_buff then
                        saved[#saved + 1] = {
                            buff      = patch.buff,
                            sub_index = sub_index,
                            field     = patch.field,
                            old_value = sub_buff[patch.field],
                        }
                        sub_buff[patch.field] = patch.value
                    end
                end
                if def.custom_apply then
                    def.custom_apply(saved)
                end
                _originals[setting_id] = saved
            end
        end
    end

    if parity_skipped then
        table.sort(parity_skipped)
        pcall(printf, "[crt:425] parity gate: %d networked rework(s) held at vanilla (peer identity or configuration unavailable): %s",
            #parity_skipped, table.concat(parity_skipped, ", "))
    end
end

local function restore_all_balance_mods()
    if not BuffTemplates then return end

    for setting_id, saved in pairs(_originals) do
        local def = BALANCE_MODS[setting_id]
        if def and def.custom_restore then
            def.custom_restore(saved)
        end
        for _, entry in ipairs(saved) do
            local template = BuffTemplates[entry.buff]
            local sub_buff = template and template.buffs and template.buffs[entry.sub_index or 1]
            if sub_buff then
                sub_buff[entry.field] = entry.old_value
            end
        end
    end
    _originals = {}
end

local function get_active_count()
    local count = 0
    for setting_id, _ in pairs(BALANCE_MODS) do
        if mod:get(setting_id) then
            count = count + 1
        end
    end
    return count
end


return {
    BALANCE_MODS = BALANCE_MODS,
    apply        = apply_balance_mods,
    restore      = restore_all_balance_mods,
    active_count = get_active_count,
    -- issue 425 introspection (consumed by career_tweaker.lua: the beacon's
    -- gated-feature callbacks + /crt_regression_test). Read-only.
    parity_gate_ok   = _crt_parity_gate_ok,
    wire_parity_live = _crt_wire_parity_live,
    network_unsafe_ids = (function()
        local ids = {}
        for setting_id, def in pairs(BALANCE_MODS) do
            if def.network_unsafe then ids[#ids + 1] = setting_id end
        end
        table.sort(ids)
        return ids
    end)(),
}
