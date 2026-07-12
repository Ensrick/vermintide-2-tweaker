local mod = get_mod("crt")

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
-- Cross-peer behavior with this fix:
--   * Host toggle ON, client toggle OFF: both have stub-or-real bodies
--     present + identical NetworkLookup indices. Host sends add_buff(N).
--     Client resolves N -> name -> stub body -> apply iterates `buffs={}`
--     and no-ops. No crash.
--   * Host + client both ON: both have real bodies. Normal behavior.
--   * Host + client both OFF: nothing ever sends add_buff for these names.
--     The registrations sit inert.
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
        if NL and NL.buff_templates and not rawget(NL.buff_templates, name) then
            local idx = #NL.buff_templates + 1
            NL.buff_templates[idx]  = name
            NL.buff_templates[name] = idx
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
-- Plus the hot-join replay filter (mod:hook BuffSystem.hot_join_sync at the end
-- of this file): the server replays every server-controlled buff to a joining
-- peer BEFORE any parity ack can exist, so crt_* entries are hidden from that
-- one replay pass (wire-safe by construction; a crt joiner re-syncs via the
-- driver's remove/re-add cycle when parity re-establishes).

-- Live parity read for the wire guards. Fail-safe: beacon missing or erroring
-- counts as "not safe" and blocks the modded send (solo still passes -- the
-- classifier treats a lobby with no OTHER humans as all-present).
local function _crt_wire_parity_live()
    local pp = mod._crt_peer_parity
    if not pp then return false end
    local ok, res = pcall(pp.all_peers_have, pp)
    return ok and res == true
end

-- Settled-state read for the feature gate (debounced by the beacon: disable is
-- instant, enable waits the settle window). Distinct from the live read above
-- on purpose: apply/restore churn follows the settled state, while every
-- individual send consults the instant live state.
--
-- Reads the beacon's committed settled state via pp:applied_state(). Issue 506:
-- the shared lib now writes _applied BEFORE firing the gated-feature callbacks
-- (_lib_peer_parity.lua _apply), so this read is correct even when it runs from
-- inside the beacon's on_enable/on_disable -- which is exactly when the apply
-- engines call it. This replaced the old mod._crt_parity_settled_enabled mirror
-- flag the callbacks set to work around a stale applied_state() read. Fail-safe:
-- no beacon (factory failed) -> nil -> networked reworks stay vanilla/inert.
local function _crt_parity_gate_ok()
    local pp = mod._crt_peer_parity
    return pp ~= nil and pp:applied_state() == "enabled"
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
end
_crt_ensure_wire_safe_funcs()

-- ============================================================
-- Talent Rework Framework
-- ============================================================
-- Each entry in BALANCE_MODS is a user-togglable talent rework.
-- The setting_id key must match a checkbox in career_tweaker_data.lua.
--
-- Structure:
--   patches = { { buff = "buff_template_name", field = "field_name", value = new_value }, ... }
--   custom_apply(originals)   — optional, for changes beyond simple field patches
--   custom_restore(originals) — optional, paired with custom_apply
--
-- Patches mutate BuffTemplates[buff].buffs[1][field] at runtime.
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

-- Hellborg's Tutelage rework: how much to subtract from random crit chance
-- while the talent is selected. Mercenary's base crit chance is 5% (0.05),
-- so a flat 10% reduction zeroes the random-crit roll at base but stays
-- meaningfully positive once crit-chance stacking is applied (weapon traits,
-- properties, bench buffs).
local _HELLBORGS_CRIT_PENALTY = 0.10

-- ============================================================
-- Helper: stat-buff "double the small percent" reworks
-- ============================================================
-- The pattern across multiple talents is: a career-specific buff template
-- with a single sub-buff whose value is sourced from `buff_tweak_data.<name>`
-- and merged in at game-init via BuffUtils.apply_buff_tweak_data. The talent
-- tooltip's description_values[1].value is statically frozen on the talent
-- entry at the same init pass. To swap a 5% talent to 10%:
--   1. patch BuffTemplates[talent_name].buffs[1][buff_field] (runtime effect)
--   2. rewrite Talents[hero][id].description_values[1].value (tooltip text)
--
-- This builder factors both into a {patches, custom_apply, custom_restore}
-- triple compatible with the apply/restore engine below. Assumes the buff
-- template name matches the talent's `name` (true for victor_zealot_power,
-- bardin_ranger_attack_speed, kerillian_maidenguard_crit_chance — verify
-- before adding a new entry).
local function _build_stat_buff_rework(talent_name, buff_field, new_value)
    return {
        patches = {
            { buff = talent_name, field = buff_field, value = new_value },
        },
        custom_apply = function(saved)
            if not Talents or not TalentIDLookup then return end
            local lookup = TalentIDLookup[talent_name]
            if not lookup then return end
            local hero_talents = Talents[lookup.hero_name]
            local talent = hero_talents and hero_talents[lookup.talent_id]
            local dv = talent and talent.description_values and talent.description_values[1]
            if not dv then return end
            saved.tooltip_original = dv.value
            dv.value = new_value
        end,
        custom_restore = function(saved)
            if saved.tooltip_original == nil then return end
            if not Talents or not TalentIDLookup then return end
            local lookup = TalentIDLookup[talent_name]
            if not lookup then return end
            local hero_talents = Talents[lookup.hero_name]
            local talent = hero_talents and hero_talents[lookup.talent_id]
            local dv = talent and talent.description_values and talent.description_values[1]
            if not dv then return end
            dv.value = saved.tooltip_original
            saved.tooltip_original = nil
        end,
    }
end

local BALANCE_MODS = {
    -- Waystalker: Serrated Shots works on EVERY arrow type.
    -- Serrated Shots (talent kerillian_waywatcher_critical_bleed, perk
    -- "kerillian_critical_bleed_dot") makes critical ranged hits bleed. The
    -- bleed is gated in damage_utils.lua:3698:
    --   has_perk("kerillian_critical_bleed_dot")
    --     and damage_profile.charge_value == "projectile"
    --     and not has_perk("kerillian_critical_bleed_dot_disable")
    -- EVERY Kerillian arrow damage profile uses charge_value="projectile"
    -- (arrow_carbine / arrow_sniper / *_shortbow / *_trueflight -- verified in
    -- damage_profile_templates.lua), so the ONLY thing that disables the bleed by
    -- "arrow type" is the disable perk, which Hagbane (shortbows_hagbane.lua:301-303
    -- server_buffs) and the Chaos Wastes we_deus_01 bow grant via the buff
    -- "we_deus_01_kerillian_critical_bleed_dot_disable" (morris_buff_settings.lua:6332
    -- -- its ONLY effect is that one perk). Clearing that buff's perks list
    -- neutralizes the disable, so Serrated Shots also applies on Hagbane /
    -- we_deus_01. Takes effect on next weapon equip / mission load.
    rework_we_waywatcher_serrated_shots_all_arrows = {
        character = "kerillian",
        patches = {
            { buff = "we_deus_01_kerillian_critical_bleed_dot_disable", field = "perks", value = {} },
        },
    },
    rework_wh_zealot_smite_random_crits = {
        character = "victor",
        career    = "wh_zealot",
        patches   = {},
    },
    -- Zealot's row-1 +5% power talent (victor_zealot_power, multiplier 0.05).
    -- Career-specific template — patch doesn't bleed into other careers'
    -- equivalents.
    rework_wh_zealot_power_5_to_10 = _build_stat_buff_rework("victor_zealot_power", "multiplier", 0.10),
    -- Ranger Veteran's row-2 +5% attack speed talent
    -- (bardin_ranger_attack_speed, multiplier 0.05). Career-specific.
    rework_dr_ranger_attack_speed_5_to_10 = _build_stat_buff_rework("bardin_ranger_attack_speed", "multiplier", 0.10),
    -- Ranger Veteran's base HP pool: vanilla 100 → 125 (+25). Patches
    -- `CareerSettings.dr_ranger.attributes.max_hp`, the table that
    -- `PlayerUnitHealthExtension._get_base_max_health` reads via
    -- `SPProfiles[profile].careers[index].attributes.max_hp` — same table
    -- reference (SPProfiles.dwarf_ranger.careers entries are direct refs to
    -- CareerSettings.dr_* — see sp_profiles.lua:163). Takes effect on the
    -- next mission load / hero respawn (max health is recalculated in
    -- `PlayerUnitHealthExtension.init`); doesn't retroactively bump an
    -- already-spawned Ranger's max in the current mission.
    rework_dr_ranger_base_hp_plus_25 = {
        character = "bardin",
        career    = "dr_ranger",
        patches   = {},
        custom_apply = function(saved)
            local cs = CareerSettings and CareerSettings.dr_ranger
            local attrs = cs and cs.attributes
            if not attrs or type(attrs.max_hp) ~= "number" then return end
            saved.ranger_max_hp_original = attrs.max_hp
            attrs.max_hp = attrs.max_hp + 25
        end,
        custom_restore = function(saved)
            if saved.ranger_max_hp_original == nil then return end
            local cs = CareerSettings and CareerSettings.dr_ranger
            local attrs = cs and cs.attributes
            if not attrs then return end
            attrs.max_hp = saved.ranger_max_hp_original
            saved.ranger_max_hp_original = nil
        end,
    },
    -- Handmaiden's row-2 +5% crit chance talent
    -- (kerillian_maidenguard_crit_chance, bonus 0.05). Career-specific.
    -- Buff field is `bonus` not `multiplier` — critical_strike_chance stat_buff
    -- consumes bonus additively at the buff_extension level.
    rework_we_maidenguard_crit_chance_5_to_10 = _build_stat_buff_rework("kerillian_maidenguard_crit_chance", "bonus", 0.10),
    rework_es_mercenary_hellborgs_tutelage = {
        character = "markus",
        career    = "es_mercenary",
        patches   = {},
    },
    -- Huntsman's passive +5% crit aura (`markus_huntsman_passive_crit_aura`):
    -- the buff is applied to the Huntsman on spawn with `range = 5`, and
    -- `activate_buff_on_distance` (buff_function_templates.lua:2759) tests
    -- `distance_squared <= range * range` every tick to decide which allies get
    -- the +5% crit chance buff. Patching the runtime template field to
    -- math.huge makes `range_squared` infinite — every ally on the side is
    -- always inside the aura. Re-application happens on the next mission load /
    -- hero respawn, since the buff itself is added at career-passive-init time.
    -- No tooltip mutation: the talent has no description_values entry that
    -- displays the 5m distance number, so there's nothing to rewrite.
    rework_es_huntsman_crit_aura_unlimited_range = {
        character = "markus",
        career    = "es_huntsman",
        patches   = {
            { buff = "markus_huntsman_passive_crit_aura", field = "range", value = math.huge },
        },
    },
    rework_wh_captain_parry_window = {
        character = "victor",
        career    = "wh_captain",
        patches   = {},
    },
    -- Double-Shotted (victor_bountyhunter_activated_ability_railgun): the
    -- talent's runtime effect is gated by the buff template's `multiplier`
    -- field on `victor_bountyhunter_activated_ability_railgun_delayed_add`
    -- (consumed by buff_function_templates.victor_bountyhunter_activated_ability_railgun_delayed,
    -- which calls career_extension:reduce_activated_ability_cooldown_percent(buff.multiplier)).
    -- Patching that template field 0.6 → 0.8 lifts the refund from 60% to 80%.
    --
    -- The displayed "60%" in the inventory talent tooltip is sourced from
    -- Talents.victor[talent_id].description_values[1].value (set at game-init
    -- from `buff_tweak_data.victor_bountyhunter_activated_ability_railgun.multiplier`,
    -- so by the time mods run that value is already frozen on the talent entry).
    -- The custom_apply hook walks TalentIDLookup to find the talent's table
    -- and rewrites the description_values entry in place; custom_restore puts
    -- it back. The tooltip refresh isn't instant — players need to close and
    -- re-enter the talent panel after toggling, same as Hellborg's Tutelage.
    rework_wh_bountyhunter_double_shotted_80 = {
        character = "victor",
        career    = "wh_bountyhunter",
        patches   = {
            { buff = "victor_bountyhunter_activated_ability_railgun_delayed_add", field = "multiplier", value = 0.8 },
        },
        custom_apply = function(saved)
            if not Talents or not TalentIDLookup then return end
            local lookup = TalentIDLookup["victor_bountyhunter_activated_ability_railgun"]
            if not lookup then return end
            local hero_talents = Talents[lookup.hero_name]
            local talent = hero_talents and hero_talents[lookup.talent_id]
            local dv = talent and talent.description_values and talent.description_values[1]
            if not dv then return end
            saved.double_shotted_tooltip_original = dv.value
            dv.value = 0.8
        end,
        custom_restore = function(saved)
            if saved.double_shotted_tooltip_original == nil then return end
            if not Talents or not TalentIDLookup then return end
            local lookup = TalentIDLookup["victor_bountyhunter_activated_ability_railgun"]
            if not lookup then return end
            local hero_talents = Talents[lookup.hero_name]
            local talent = hero_talents and hero_talents[lookup.talent_id]
            local dv = talent and talent.description_values and talent.description_values[1]
            if not dv then return end
            dv.value = saved.double_shotted_tooltip_original
            saved.double_shotted_tooltip_original = nil
        end,
    },
    -- Stagger THP rework: +50% per-target THP (base_value 1 -> 1.5) and caps
    -- the per-swing target count at 3 instead of 5. Light/medium/heavy stagger
    -- heal 0.375 / 1.5 / 3 THP per target; a perfect heavy swing across 3
    -- enemies caps at 9 THP, a typical medium swing across 3 caps at 4.5 THP.
    -- Trades the vanilla horde-feast (5 medium staggers = 5 THP) for a
    -- smaller-but-richer payout that also rewards light/heavy stagger more
    -- meaningfully without ballooning into the OP territory of the +100% rework.
    rework_general_stagger_thp = {
        character = "any",
        career    = "any (Heal-on-Stagger talents)",
        patches   = {
            { buff = "thp_tank", field = "base_value",  value = 1.5 },
            { buff = "thp_tank", field = "max_targets", value = 3 },
        },
    },
    -- Minimum THP-on-kill floor: clamps every breed's bloodlust_health (the
    -- per-enemy THP-on-kill amount used by Heal-on-Kill traits, Bloodlust
    -- talents, and the Warrior Priest aftershock heal) to at least
    -- _MIN_THP_ON_KILL. Vanilla slaves/hordes drop 0..1 THP which feels
    -- worthless; flooring at 1 gives any trash kill a meaningful payout
    -- without touching elites/specials/monsters. Each breed file copies its
    -- number out of BreedTweaks.bloodlust_health at game-load time
    -- (e.g. breed_chaos_warrior.lua:134), so we mutate breed tables directly.
    -- Snapshot per breed_name → restored on disable / re-toggle.
    rework_general_thp_kill_minimum = {
        character = "any",
        career    = "any (THP-on-kill traits/talents)",
        patches   = {},
        custom_apply = function(saved)
            if not Breeds then return end
            local floor = _MIN_THP_ON_KILL
            saved.breed_thp_originals = {}
            for breed_name, breed in pairs(Breeds) do
                local v = breed and breed.bloodlust_health
                if type(v) == "number" and v < floor then
                    saved.breed_thp_originals[breed_name] = v
                    breed.bloodlust_health = floor
                end
            end
        end,
        custom_restore = function(saved)
            if not Breeds or not saved.breed_thp_originals then return end
            for breed_name, original in pairs(saved.breed_thp_originals) do
                local breed = Breeds[breed_name]
                if breed then
                    breed.bloodlust_health = original
                end
            end
            saved.breed_thp_originals = nil
        end,
    },

    -- ============================================================
    -- Shade: Hungry Wind (level 30) — bigger / longer
    -- ============================================================
    -- Talent `kerillian_shade_activated_ability_phasing` grants a post-stealth
    -- buff: vanilla +10% move-speed + +15% power for 10s. Rework: +20% / +20%
    -- / 20s. Three buff templates carry the values, all sourced from
    -- buff_tweak_data and merged into buffs[1] at boot
    -- (talent_settings_kerillian.lua:750-774, buff_utils.lua:13-21):
    --   * kerillian_shade_movespeed_buff   — multiplier 1.1, duration 10
    --   * kerillian_shade_power_buff       — multiplier 0.15, duration 10
    --   * kerillian_shade_phasing_buff     — duration 10 (noclip wrapper)
    -- Each gets a buffs[1] field patch via the standard engine. Tooltip values
    -- live in `Talents.wood_elf[<id>].description_values[1..3]` and need a
    -- custom_apply rewrite — they're frozen at game-init from buff_tweak_data
    -- (lines 1770-1782).
    rework_we_shade_hungry_wind_buffed = {
        character = "kerillian",
        career    = "we_shade",
        patches   = {
            { buff = "kerillian_shade_movespeed_buff", field = "multiplier", value = 1.2 },
            { buff = "kerillian_shade_movespeed_buff", field = "duration",   value = 20 },
            { buff = "kerillian_shade_power_buff",     field = "multiplier", value = 0.20 },
            { buff = "kerillian_shade_power_buff",     field = "duration",   value = 20 },
        },
        custom_apply = function(saved)
            if not Talents or not TalentIDLookup then return end
            local lookup = TalentIDLookup["kerillian_shade_activated_ability_phasing"]
            if not lookup then return end
            local talent = Talents[lookup.hero_name] and Talents[lookup.hero_name][lookup.talent_id]
            local dv = talent and talent.description_values
            if not dv then return end
            saved.hw_dv1 = dv[1] and dv[1].value
            saved.hw_dv2 = dv[2] and dv[2].value
            saved.hw_dv3 = dv[3] and dv[3].value
            if dv[1] then dv[1].value = 1.2  end
            if dv[2] then dv[2].value = 0.20 end
            if dv[3] then dv[3].value = 20   end
        end,
        custom_restore = function(saved)
            if not Talents or not TalentIDLookup then return end
            local lookup = TalentIDLookup["kerillian_shade_activated_ability_phasing"]
            if not lookup then return end
            local talent = Talents[lookup.hero_name] and Talents[lookup.hero_name][lookup.talent_id]
            local dv = talent and talent.description_values
            if not dv then return end
            if dv[1] and saved.hw_dv1 ~= nil then dv[1].value = saved.hw_dv1 end
            if dv[2] and saved.hw_dv2 ~= nil then dv[2].value = saved.hw_dv2 end
            if dv[3] and saved.hw_dv3 ~= nil then dv[3].value = saved.hw_dv3 end
            saved.hw_dv1, saved.hw_dv2, saved.hw_dv3 = nil, nil, nil
        end,
    },

    -- ============================================================
    -- Huntsman: +25 base HP (clone of Ranger Veteran HP pattern)
    -- ============================================================
    -- Vanilla 100 → 125 (matches Witch Hunter Captain). Same data path as
    -- `rework_dr_ranger_base_hp_plus_25`. Takes effect on next mission load /
    -- hero respawn (max_health is recalculated in PlayerUnitHealthExtension.init).
    rework_es_huntsman_base_hp_plus_25 = {
        character = "markus",
        career    = "es_huntsman",
        patches   = {},
        custom_apply = function(saved)
            local cs = CareerSettings and CareerSettings.es_huntsman
            local attrs = cs and cs.attributes
            if not attrs or type(attrs.max_hp) ~= "number" then return end
            saved.huntsman_max_hp_original = attrs.max_hp
            attrs.max_hp = attrs.max_hp + 25
        end,
        custom_restore = function(saved)
            if saved.huntsman_max_hp_original == nil then return end
            local cs = CareerSettings and CareerSettings.es_huntsman
            local attrs = cs and cs.attributes
            if not attrs then return end
            attrs.max_hp = saved.huntsman_max_hp_original
            saved.huntsman_max_hp_original = nil
        end,
    },

    -- ============================================================
    -- Huntsman: Prowl grants +50% power vs. monsters
    -- ============================================================
    -- During Prowl (Huntsman's active ability), inject an extra sub-buff into
    -- `BuffTemplates.markus_huntsman_activated_ability.buffs` that grants
    -- `stat_buff = "power_level_large"`, multiplier 1.5. VT2 resolves boss
    -- breeds to armor_category=3, which the damage pipeline reads via
    -- `apply_buffs_to_value(..., "power_level_large")` at
    -- action_utils.lua:346, stacking additively into the per-target power
    -- multiplier (`stacked_multiplier += (returned_multiplier - 1)`,
    -- action_utils.lua:353). So multiplier=1.5 yields +50% damage vs.
    -- monsters. CAVEAT: this applies to both melee and ranged attacks vs.
    -- monsters during Prowl — VT2 has no `power_level_ranged_vs_large`
    -- stat_buff, and a ranged-only gate would require hooking damage profile
    -- resolution. Acceptable trade since Huntsman during Prowl is almost
    -- always shooting; melee-vs-monster while stealthed is a corner case.
    rework_es_huntsman_prowl_monster_power = {
        character = "markus",
        career    = "es_huntsman",
        patches   = {},
        custom_apply = function(saved)
            if not BuffTemplates then return end
            local template = BuffTemplates.markus_huntsman_activated_ability
            if not template or not template.buffs then return end
            saved.prowl_buffs_original_count = #template.buffs
            table.insert(template.buffs, {
                stat_buff  = "power_level_large",
                multiplier = 1.5,
                name       = "crt_huntsman_prowl_monster_power",
                max_stacks = 1,
            })
        end,
        custom_restore = function(saved)
            if saved.prowl_buffs_original_count == nil then return end
            local template = BuffTemplates and BuffTemplates.markus_huntsman_activated_ability
            if template and template.buffs then
                while #template.buffs > saved.prowl_buffs_original_count do
                    table.remove(template.buffs)
                end
            end
            saved.prowl_buffs_original_count = nil
        end,
    },

    -- ============================================================
    -- Ranger Veteran: Exuberance — stacking DR
    -- ============================================================
    -- Vanilla: one ranged headshot grants -30% damage taken for 7s
    -- (talent `bardin_ranger_reduced_damage_taken_headshot`, applies buff
    -- `bardin_ranger_reduced_damage_taken_headshot_buff`).
    -- Rework: -6% per stack, max 5 stacks; one stack per shot (the proc fires
    -- once per shot regardless of pierce/cleave count, damage_utils.lua:2088);
    -- taking damage removes one stack (custom stack-remover buff template
    -- registered at apply time, mirrors `kerillian_shade_stealth_crits_remover`
    -- in talent_settings_kerillian.lua:306-320 — uses `remove_buff_stack`
    -- proc with `remove_buff_stack_data` array, see buff_function_templates.lua:2172).
    rework_dr_ranger_exuberance_stacking_dr = {
        character = "bardin",
        career    = "dr_ranger",
        patches   = {
            { buff = "bardin_ranger_reduced_damage_taken_headshot_buff", field = "max_stacks", value = 5 },
            { buff = "bardin_ranger_reduced_damage_taken_headshot_buff", field = "multiplier", value = -0.06 },
        },
        custom_apply = function(saved)
            if BuffTemplates and (BuffTemplates.crt_bardin_ranger_exuberance_stack_remover == nil or BuffTemplates.crt_bardin_ranger_exuberance_stack_remover._crt_pending) then
                BuffTemplates.crt_bardin_ranger_exuberance_stack_remover = {
                    buffs = {
                        {
                            buff_func = "remove_buff_stack",
                            event     = "on_damage_taken",
                            name      = "crt_bardin_ranger_exuberance_stack_remover",
                            remove_buff_func = "remove_buff_stack",
                            remove_buff_stack_data = {
                                {
                                    buff_to_remove   = "bardin_ranger_reduced_damage_taken_headshot_buff",
                                    num_stacks       = 1,
                                    server_controlled = false,
                                },
                            },
                        },
                    },
                }
                saved.crt_exuberance_remover_created = true
            end
            if Talents and TalentIDLookup then
                local lookup = TalentIDLookup["bardin_ranger_reduced_damage_taken_headshot"]
                if lookup then
                    local talent = Talents[lookup.hero_name] and Talents[lookup.hero_name][lookup.talent_id]
                    if talent and talent.buffs then
                        local already = false
                        for _, b in ipairs(talent.buffs) do
                            if b == "crt_bardin_ranger_exuberance_stack_remover" then already = true; break end
                        end
                        if not already then
                            saved.exuberance_talent_buffs_count = #talent.buffs
                            table.insert(talent.buffs, "crt_bardin_ranger_exuberance_stack_remover")
                        end
                    end
                    local dv = talent and talent.description_values and talent.description_values[1]
                    if dv then
                        saved.exuberance_tooltip_original = dv.value
                        dv.value = 0.06
                    end
                end
            end
        end,
        custom_restore = function(saved)
            if Talents and TalentIDLookup then
                local lookup = TalentIDLookup["bardin_ranger_reduced_damage_taken_headshot"]
                if lookup then
                    local talent = Talents[lookup.hero_name] and Talents[lookup.hero_name][lookup.talent_id]
                    if talent and talent.buffs and saved.exuberance_talent_buffs_count then
                        while #talent.buffs > saved.exuberance_talent_buffs_count do
                            table.remove(talent.buffs)
                        end
                    end
                    local dv = talent and talent.description_values and talent.description_values[1]
                    if dv and saved.exuberance_tooltip_original ~= nil then
                        dv.value = saved.exuberance_tooltip_original
                    end
                end
            end
            if saved.crt_exuberance_remover_created and BuffTemplates then
                BuffTemplates.crt_bardin_ranger_exuberance_stack_remover = _crt_make_stub()
            end
            saved.exuberance_talent_buffs_count = nil
            saved.exuberance_tooltip_original  = nil
            saved.crt_exuberance_remover_created = nil
        end,
    },

    -- ============================================================
    -- Bounty Hunter: Blessed Combat (level 20) — 15% → 25% stacks
    -- ============================================================
    -- Talent `victor_bountyhunter_weapon_swap_buff`. Vanilla: melee hits stack
    -- ranged-damage buff (+15%/stack, max 6); ranged hits stack melee-damage
    -- buff (+15%/stack). Rework: both lift to +25%/stack. Tooltip values at
    -- description_values[2] and [4] (lines 1845/1852 of talent_settings_victor.lua)
    -- both need rewriting. NOTE: the user also asked that the
    -- "melee kills reset blessed-shots cooldown" effect (currently bundled into
    -- Blessed Combat via the `victor_bountyhunter_activate_passive_on_melee_kill`
    -- buff on line 1857) become innate regardless of which level-20 talent is
    -- selected — handled here by appending the same buff to the OTHER two
    -- level-20 talents' `buffs` lists when the toggle is on.
    rework_wh_bountyhunter_blessed_combat_25_and_passive_melee_reset = {
        character = "victor",
        career    = "wh_bountyhunter",
        patches   = {
            { buff = "victor_bountyhunter_blessed_melee_damage_buff",  field = "multiplier", value = 0.25 },
            { buff = "victor_bountyhunter_blessed_ranged_damage_buff", field = "multiplier", value = 0.25 },
        },
        custom_apply = function(saved)
            if not Talents or not TalentIDLookup then return end
            local lookup = TalentIDLookup["victor_bountyhunter_weapon_swap_buff"]
            if lookup then
                local talent = Talents[lookup.hero_name] and Talents[lookup.hero_name][lookup.talent_id]
                local dv = talent and talent.description_values
                if dv then
                    if dv[2] then saved.bc_dv2 = dv[2].value; dv[2].value = 0.25 end
                    if dv[4] then saved.bc_dv4 = dv[4].value; dv[4].value = 0.25 end
                end
            end
            -- Promote melee-kill cooldown reset to passive: append buff to the
            -- OTHER two level-20 talents (col 2 = passive_reduced_cooldown,
            -- col 3 = passive_infinite_ammo).
            saved.bc_appended = {}
            local function _append(talent_name, buff_name)
                local lk = TalentIDLookup[talent_name]
                if not lk then return end
                local t = Talents[lk.hero_name] and Talents[lk.hero_name][lk.talent_id]
                if not t or not t.buffs then return end
                for _, b in ipairs(t.buffs) do
                    if b == buff_name then return end
                end
                saved.bc_appended[talent_name] = #t.buffs
                table.insert(t.buffs, buff_name)
            end
            _append("victor_bountyhunter_passive_reduced_cooldown", "victor_bountyhunter_activate_passive_on_melee_kill")
            _append("victor_bountyhunter_passive_infinite_ammo",    "victor_bountyhunter_activate_passive_on_melee_kill")
        end,
        custom_restore = function(saved)
            if not Talents or not TalentIDLookup then return end
            local lookup = TalentIDLookup["victor_bountyhunter_weapon_swap_buff"]
            if lookup then
                local talent = Talents[lookup.hero_name] and Talents[lookup.hero_name][lookup.talent_id]
                local dv = talent and talent.description_values
                if dv then
                    if dv[2] and saved.bc_dv2 ~= nil then dv[2].value = saved.bc_dv2 end
                    if dv[4] and saved.bc_dv4 ~= nil then dv[4].value = saved.bc_dv4 end
                end
            end
            if saved.bc_appended then
                for talent_name, original_count in pairs(saved.bc_appended) do
                    local lk = TalentIDLookup[talent_name]
                    local t = lk and Talents[lk.hero_name] and Talents[lk.hero_name][lk.talent_id]
                    if t and t.buffs then
                        while #t.buffs > original_count do table.remove(t.buffs) end
                    end
                end
            end
            saved.bc_dv2, saved.bc_dv4, saved.bc_appended = nil, nil, nil
        end,
    },

    -- ============================================================
    -- Bounty Hunter: Rile the Mob → permanent +10% move speed
    -- ============================================================
    -- Vanilla: ranged crit grants the team +10% move speed for 10s. Rework:
    -- replace with a permanent self-only +10% move speed while the talent is
    -- selected. Swaps the outer `victor_bountyhunter_party_movespeed_on_ranged_crit`
    -- buff template's buffs[1] entry from a conditional crit-trigger
    -- (`add_team_buff_on_ranged_critical_hit`) to a direct apply_movement_buff
    -- entry with no duration. The talent's `buffs` list already references
    -- the outer buff template by name (line 1896), so swapping its buffs[1]
    -- changes what the player gets at talent-apply time.
    rework_wh_bountyhunter_rile_the_mob_movement = {
        character = "victor",
        career    = "wh_bountyhunter",
        patches   = {},
        custom_apply = function(saved)
            local outer = BuffTemplates and BuffTemplates.victor_bountyhunter_party_movespeed_on_ranged_crit
            if not outer or not outer.buffs or not outer.buffs[1] then return end
            saved.rile_outer_buffs1_original = outer.buffs[1]
            outer.buffs[1] = {
                apply_buff_func  = "apply_movement_buff",
                remove_buff_func = "remove_movement_buff",
                name             = "crt_rile_the_mob_permanent_movespeed",
                max_stacks       = 1,
                multiplier       = 1.1,
                path_to_movement_setting_to_modify = { "move_speed" },
            }
        end,
        custom_restore = function(saved)
            if not saved.rile_outer_buffs1_original then return end
            local outer = BuffTemplates and BuffTemplates.victor_bountyhunter_party_movespeed_on_ranged_crit
            if outer and outer.buffs then
                outer.buffs[1] = saved.rile_outer_buffs1_original
            end
            saved.rile_outer_buffs1_original = nil
        end,
    },

    -- ============================================================
    -- Bounty Hunter: Salvaged Ammunition — drop out-of-ammo gate +
    -- passive melee-reload
    -- ============================================================
    -- Vanilla Salvaged Ammunition restores 5% ammo on melee elite kill BUT
    -- only when you're completely out of ammo (gate at buff_templates.lua:3052:
    -- `if current_ammo < 1 and clip_ammo < 1`). It also reloads your ranged
    -- weapon on every melee kill (buff_templates.lua:2798).
    -- Rework: drop the out-of-ammo gate (function override below in the hook
    -- section), and make the reload-on-melee-kill effect innate (append it to
    -- the OTHER level-25 talents' buffs lists, mirroring the Blessed Combat
    -- passive-promotion pattern).
    rework_wh_bountyhunter_salvaged_ammo_no_gate_and_passive_reload = {
        character = "victor",
        career    = "wh_bountyhunter",
        patches   = {},
        custom_apply = function(saved)
            if not Talents or not TalentIDLookup then return end
            saved.sa_appended = {}
            local function _append(talent_name, buff_name)
                local lk = TalentIDLookup[talent_name]
                if not lk then return end
                local t = Talents[lk.hero_name] and Talents[lk.hero_name][lk.talent_id]
                if not t or not t.buffs then return end
                for _, b in ipairs(t.buffs) do
                    if b == buff_name then return end
                end
                saved.sa_appended[talent_name] = #t.buffs
                table.insert(t.buffs, buff_name)
            end
            _append("victor_bountyhunter_party_movespeed_on_ranged_crit",                "victor_bountyhunter_reload_on_kill")
            _append("victor_bountyhunter_stacking_damage_reduction_on_elite_or_special_kill", "victor_bountyhunter_reload_on_kill")
        end,
        custom_restore = function(saved)
            if not Talents or not TalentIDLookup then return end
            if saved.sa_appended then
                for talent_name, original_count in pairs(saved.sa_appended) do
                    local lk = TalentIDLookup[talent_name]
                    local t = lk and Talents[lk.hero_name] and Talents[lk.hero_name][lk.talent_id]
                    if t and t.buffs then
                        while #t.buffs > original_count do table.remove(t.buffs) end
                    end
                end
            end
            saved.sa_appended = nil
        end,
    },

    -- ============================================================
    -- Bounty Hunter: Job Well Done — innate + special-kill stacking DR
    -- ============================================================
    -- Vanilla Job Well Done (`victor_bountyhunter_stacking_damage_reduction_on_elite_or_special_kill`):
    -- on elite OR special kill, gain stacking damage taken reduction
    -- (-1%/stack, max 30 stacks). Rework: that vanilla effect becomes innate
    -- (appended to the OTHER two level-25 talents' buffs lists, like
    -- Blessed Combat / Salvaged Ammo); the talent slot itself swaps its
    -- payload to a NEW special-kill DR stacking buff at -5%/stack, max 6
    -- stacks, with one stack removed per damage taken (stack remover added
    -- to the talent's buffs list via the kerillian-shade pattern).
    rework_wh_bountyhunter_job_well_done_passive_and_special_kill_dr = {
        character = "victor",
        career    = "wh_bountyhunter",
        -- issue 425: the DR-stack add rides rpc_add_buff (via the special-kill
        -- proc); gated on peer parity + wire-safe proc wrapper.
        network_unsafe = true,
        patches   = {},
        custom_apply = function(saved)
            if not BuffTemplates or not Talents or not TalentIDLookup then return end
            _crt_ensure_wire_safe_funcs()
            -- Register the new special-kill DR stacking buff if missing.
            if BuffTemplates.crt_bh_jwd_special_kill_dr_proc == nil or BuffTemplates.crt_bh_jwd_special_kill_dr_proc._crt_pending then
                BuffTemplates.crt_bh_jwd_special_kill_dr_proc = {
                    buffs = {
                        {
                            buff_func     = "crt_wire_safe_add_buff_on_special_kill",
                            buff_to_add   = "crt_bh_jwd_special_kill_dr_stack",
                            event         = "on_kill",
                            name          = "crt_bh_jwd_special_kill_dr_proc",
                        },
                    },
                }
                saved.jwd_created_proc = true
            end
            if BuffTemplates.crt_bh_jwd_special_kill_dr_stack == nil or BuffTemplates.crt_bh_jwd_special_kill_dr_stack._crt_pending then
                BuffTemplates.crt_bh_jwd_special_kill_dr_stack = {
                    buffs = {
                        {
                            stat_buff   = "damage_taken",
                            multiplier  = -0.05,
                            max_stacks  = 6,
                            duration    = 60,
                            refresh_durations = true,
                            name        = "crt_bh_jwd_special_kill_dr_stack",
                        },
                    },
                }
                saved.jwd_created_stack = true
            end
            if BuffTemplates.crt_bh_jwd_stack_remover == nil or BuffTemplates.crt_bh_jwd_stack_remover._crt_pending then
                BuffTemplates.crt_bh_jwd_stack_remover = {
                    buffs = {
                        {
                            buff_func = "remove_buff_stack",
                            event     = "on_damage_taken",
                            name      = "crt_bh_jwd_stack_remover",
                            remove_buff_func = "remove_buff_stack",
                            remove_buff_stack_data = {
                                {
                                    buff_to_remove   = "crt_bh_jwd_special_kill_dr_stack",
                                    num_stacks       = 1,
                                    server_controlled = false,
                                },
                            },
                        },
                    },
                }
                saved.jwd_created_remover = true
            end
            -- Talent payload swap: replace the talent's buffs list (was the
            -- vanilla 1%/stack proc) with the new 5%/stack proc + remover.
            local lookup = TalentIDLookup["victor_bountyhunter_stacking_damage_reduction_on_elite_or_special_kill"]
            if lookup then
                local talent = Talents[lookup.hero_name] and Talents[lookup.hero_name][lookup.talent_id]
                if talent and talent.buffs then
                    saved.jwd_talent_buffs_original = {}
                    for i = 1, #talent.buffs do saved.jwd_talent_buffs_original[i] = talent.buffs[i] end
                    talent.buffs = { "crt_bh_jwd_special_kill_dr_proc", "crt_bh_jwd_stack_remover" }
                end
            end
            -- Promote vanilla effect to innate: append vanilla buff to the
            -- OTHER two level-25 talents.
            saved.jwd_appended = {}
            local function _append(talent_name, buff_name)
                local lk = TalentIDLookup[talent_name]
                if not lk then return end
                local t = Talents[lk.hero_name] and Talents[lk.hero_name][lk.talent_id]
                if not t or not t.buffs then return end
                for _, b in ipairs(t.buffs) do
                    if b == buff_name then return end
                end
                saved.jwd_appended[talent_name] = #t.buffs
                table.insert(t.buffs, buff_name)
            end
            _append("victor_bountyhunter_party_movespeed_on_ranged_crit",
                    "victor_bountyhunter_stacking_damage_reduction_on_elite_or_special_kill")
            _append("victor_bountyhunter_reload_on_kill",
                    "victor_bountyhunter_stacking_damage_reduction_on_elite_or_special_kill")
        end,
        custom_restore = function(saved)
            if not Talents or not TalentIDLookup then return end
            local lookup = TalentIDLookup["victor_bountyhunter_stacking_damage_reduction_on_elite_or_special_kill"]
            if lookup and saved.jwd_talent_buffs_original then
                local talent = Talents[lookup.hero_name] and Talents[lookup.hero_name][lookup.talent_id]
                if talent then talent.buffs = saved.jwd_talent_buffs_original end
            end
            if saved.jwd_appended then
                for talent_name, original_count in pairs(saved.jwd_appended) do
                    local lk = TalentIDLookup[talent_name]
                    local t = lk and Talents[lk.hero_name] and Talents[lk.hero_name][lk.talent_id]
                    if t and t.buffs then
                        while #t.buffs > original_count do table.remove(t.buffs) end
                    end
                end
            end
            if BuffTemplates then
                if saved.jwd_created_proc    then BuffTemplates.crt_bh_jwd_special_kill_dr_proc = _crt_make_stub() end
                if saved.jwd_created_stack   then BuffTemplates.crt_bh_jwd_special_kill_dr_stack = _crt_make_stub() end
                if saved.jwd_created_remover then BuffTemplates.crt_bh_jwd_stack_remover = _crt_make_stub() end
            end
            saved.jwd_talent_buffs_original = nil
            saved.jwd_appended = nil
            saved.jwd_created_proc, saved.jwd_created_stack, saved.jwd_created_remover = nil, nil, nil
        end,
    },

    -- ============================================================
    -- Bounty Hunter: Just Reward — 10s cooldown gate → 5s
    -- ============================================================
    -- Talent `victor_bountyhunter_activated_ability_reset_cooldown_on_stacks`
    -- attaches buff `victor_bountyhunter_activated_ability_passive_cooldown_reduction`
    -- (line 1982). The proc func at buff_templates.lua:3593-3614 reads
    -- `template.cooldown` (10 by default, merged in from buff_tweak_data) and
    -- gates the next proc to `t > buff.cooldown` where `buff.cooldown = t +
    -- template.cooldown`. Patching the template's `cooldown` field to 5
    -- halves the gate. Tooltip cooldown lives in description_values[2].
    rework_wh_bountyhunter_just_reward_5s_cooldown = {
        character = "victor",
        career    = "wh_bountyhunter",
        patches   = {
            { buff = "victor_bountyhunter_activated_ability_passive_cooldown_reduction", field = "cooldown", value = 5 },
        },
        custom_apply = function(saved)
            if not Talents or not TalentIDLookup then return end
            local lookup = TalentIDLookup["victor_bountyhunter_activated_ability_reset_cooldown_on_stacks"]
            if not lookup then return end
            local talent = Talents[lookup.hero_name] and Talents[lookup.hero_name][lookup.talent_id]
            local dv = talent and talent.description_values and talent.description_values[2]
            if not dv then return end
            saved.jr_tooltip_original = dv.value
            dv.value = 5
        end,
        custom_restore = function(saved)
            if saved.jr_tooltip_original == nil then return end
            if not Talents or not TalentIDLookup then return end
            local lookup = TalentIDLookup["victor_bountyhunter_activated_ability_reset_cooldown_on_stacks"]
            if not lookup then return end
            local talent = Talents[lookup.hero_name] and Talents[lookup.hero_name][lookup.talent_id]
            local dv = talent and talent.description_values and talent.description_values[2]
            if not dv then return end
            dv.value = saved.jr_tooltip_original
            saved.jr_tooltip_original = nil
        end,
    },

    -- ============================================================
    -- Bounty Hunter: Double-Shotted damage doubling (stacks with 80% rework)
    -- ============================================================
    -- Independent toggle from `rework_wh_bountyhunter_double_shotted_80`. Adds
    -- +100% ranged power for a short window after the BH ability is activated,
    -- so the next ranged shot deals double damage. Implementation: register a
    -- buff template `crt_bh_double_shotted_damage_buff` with stat_buff
    -- "power_level_ranged", multiplier 1.0 (= +100% damage when stacking
    -- additively via apply_buffs_to_value, action_utils.lua:353), 3s duration;
    -- inject it into the railgun talent's buffs list so it's added to the
    -- player when Double-Shotted is selected — but we want it to apply on
    -- ability activation, not all the time, so we instead hook
    -- CareerAbilityWHBountyHunter:_run_ability below (see runtime hooks).
    -- This BALANCE_MODS entry only registers the template; the hook activates it.
    rework_wh_bountyhunter_double_shotted_damage_double = {
        character = "victor",
        career    = "wh_bountyhunter",
        patches   = {},
        custom_apply = function(saved)
            if not BuffTemplates then return end
            if BuffTemplates.crt_bh_double_shotted_damage_buff == nil or BuffTemplates.crt_bh_double_shotted_damage_buff._crt_pending then
                BuffTemplates.crt_bh_double_shotted_damage_buff = {
                    buffs = {
                        {
                            stat_buff  = "power_level_ranged",
                            multiplier = 1.0,
                            max_stacks = 1,
                            duration   = 3,
                            refresh_durations = true,
                            name       = "crt_bh_double_shotted_damage_buff",
                        },
                    },
                }
                saved.dsd_created = true
            end
        end,
        custom_restore = function(saved)
            if saved.dsd_created and BuffTemplates then
                BuffTemplates.crt_bh_double_shotted_damage_buff = _crt_make_stub()
            end
            saved.dsd_created = nil
        end,
    },

    -- ============================================================
    -- Bounty Hunter: Indiscriminate Blast — 1% cooldown refund per kill
    -- ============================================================
    -- Talent `victor_bountyhunter_activated_ability_blast_shotgun` already
    -- adds `victor_bounty_blast_streak_buff` on kills to grant cooldown
    -- reduction at stack thresholds. Rework adds, on top of vanilla, a flat
    -- 1% cooldown refund per kill the BH ability scores. Implemented in the
    -- runtime hook section below — wraps `ProcFunctions.victor_bounty_blast_streak_activation`
    -- (buff_templates.lua:line of definition near the BH proc cluster) and,
    -- when the kill's damage source is `victor_bountyhunter_career_skill_weapon`,
    -- additionally calls `career_extension:reduce_activated_ability_cooldown_percent(0.01)`.
    -- This BALANCE_MODS entry is a stub so the toggle appears in active_count
    -- and the apply/restore engine knows about it (no field patches needed).
    rework_wh_bountyhunter_indiscriminate_blast_refund_per_kill = {
        character = "victor",
        career    = "wh_bountyhunter",
        patches   = {},
    },

    -- ============================================================
    -- Universal: Enhanced Power (level 15) — every career 7.5% → 10%
    -- ============================================================
    -- All 15 base careers' level-15 Enhanced Power talents attach the shared
    -- `power_level_unbalance` buff template (buff_templates.lua:5857). One
    -- field patch updates the multiplier for every career simultaneously. Each
    -- career's tooltip reads the value from `BuffUtils.get_buff_template(
    -- "power_level_unbalance", "adventure").buffs[1].multiplier` at file load
    -- time, so the per-talent `description_values[1].value` is frozen at 0.075
    -- and must be rewritten per career. 15 base careers (DLC careers either
    -- don't have this talent or use a different naming convention — they're
    -- silently skipped if TalentIDLookup doesn't resolve).
    rework_general_enhanced_power_10pct = {
        character = "any",
        career    = "any",
        patches   = {
            { buff = "power_level_unbalance", field = "multiplier", value = 0.10 },
        },
        custom_apply = function(saved)
            if not Talents or not TalentIDLookup then return end
            saved.enh_pwr_tooltips = {}
            local talent_names = {
                "bardin_ironbreaker_power_level_unbalance",
                "bardin_slayer_power_level_unbalance",
                "bardin_ranger_power_level_unbalance",
                "markus_huntsman_power_level_unbalance",
                "markus_knight_power_level_unbalance",
                "markus_mercenary_power_level_unbalance",
                "kerillian_shade_power_level_unbalance",
                "kerillian_maidenguard_power_level_unbalance",
                "kerillian_waystalker_power_level_unbalance",
                "victor_zealot_power_level_unbalance",
                "victor_bounty_hunter_power_level_unbalance",
                "victor_witchhunter_power_level_unbalance",
                "sienna_scholar_power_level_unbalance",
                "sienna_adept_power_level_unbalance",
                "sienna_unchained_power_level_unbalance",
            }
            for _, talent_name in ipairs(talent_names) do
                local lookup = TalentIDLookup[talent_name]
                if lookup then
                    local talent = Talents[lookup.hero_name] and Talents[lookup.hero_name][lookup.talent_id]
                    local dv = talent and talent.description_values and talent.description_values[1]
                    if dv then
                        saved.enh_pwr_tooltips[talent_name] = dv.value
                        dv.value = 0.10
                    end
                end
            end
        end,
        custom_restore = function(saved)
            if not Talents or not TalentIDLookup or not saved.enh_pwr_tooltips then return end
            for talent_name, original in pairs(saved.enh_pwr_tooltips) do
                local lookup = TalentIDLookup[talent_name]
                if lookup then
                    local talent = Talents[lookup.hero_name] and Talents[lookup.hero_name][lookup.talent_id]
                    local dv = talent and talent.description_values and talent.description_values[1]
                    if dv then dv.value = original end
                end
            end
            saved.enh_pwr_tooltips = nil
        end,
    },

    -- ============================================================
    -- Battle Wizard: Famished Flames (lvl 25) — burn 100→150%, non-burn 15→30%
    -- ============================================================
    -- Talent `sienna_adept_increased_burn_damage_reduced_non_burn_damage`
    -- attaches two separate buff templates: `sienna_adept_increased_burn_damage`
    -- (multiplier 1.0 = +100% burn damage) and `sienna_adept_reduced_non_burn_damage`
    -- (multiplier -0.15 = -15% non-burn). User's "level 10" terminology is a
    -- mis-recall — the talent lives at row 5 (level 25) on Battle Wizard (bw_adept).
    rework_bw_adept_famished_flames_buffed = {
        character = "sienna",
        career    = "bw_adept",
        patches   = {
            { buff = "sienna_adept_increased_burn_damage",     field = "multiplier", value = 1.5  },
            { buff = "sienna_adept_reduced_non_burn_damage",   field = "multiplier", value = -0.30 },
        },
        custom_apply = function(saved)
            if not Talents or not TalentIDLookup then return end
            local lookup = TalentIDLookup["sienna_adept_increased_burn_damage_reduced_non_burn_damage"]
            if not lookup then return end
            local talent = Talents[lookup.hero_name] and Talents[lookup.hero_name][lookup.talent_id]
            local dv = talent and talent.description_values
            if not dv then return end
            if dv[1] then saved.ff_dv1 = dv[1].value; dv[1].value = 1.5  end
            if dv[2] then saved.ff_dv2 = dv[2].value; dv[2].value = 0.30 end
        end,
        custom_restore = function(saved)
            if not Talents or not TalentIDLookup then return end
            local lookup = TalentIDLookup["sienna_adept_increased_burn_damage_reduced_non_burn_damage"]
            if not lookup then return end
            local talent = Talents[lookup.hero_name] and Talents[lookup.hero_name][lookup.talent_id]
            local dv = talent and talent.description_values
            if not dv then return end
            if dv[1] and saved.ff_dv1 ~= nil then dv[1].value = saved.ff_dv1 end
            if dv[2] and saved.ff_dv2 ~= nil then dv[2].value = saved.ff_dv2 end
            saved.ff_dv1, saved.ff_dv2 = nil, nil
        end,
    },

    -- ============================================================
    -- Battle Wizard: Volcanic Force (lvl 20) — full-charge +50% → +100%
    -- ============================================================
    -- Talent `sienna_adept_power_level_on_full_charge`. Buff template's
    -- multiplier holds the +50% (0.5) bonus on fully-charged spells.
    -- User said "level 10" — actual is row 4 (level 20) on Battle Wizard (bw_adept).
    rework_bw_adept_volcanic_force_doubled = {
        character = "sienna",
        career    = "bw_adept",
        patches   = {
            { buff = "sienna_adept_power_level_on_full_charge", field = "multiplier", value = 1.0 },
        },
        custom_apply = function(saved)
            if not Talents or not TalentIDLookup then return end
            local lookup = TalentIDLookup["sienna_adept_power_level_on_full_charge"]
            if not lookup then return end
            local talent = Talents[lookup.hero_name] and Talents[lookup.hero_name][lookup.talent_id]
            local dv = talent and talent.description_values and talent.description_values[1]
            if not dv then return end
            saved.vf_orig = dv.value
            dv.value = 1.0
        end,
        custom_restore = function(saved)
            if saved.vf_orig == nil then return end
            if not Talents or not TalentIDLookup then return end
            local lookup = TalentIDLookup["sienna_adept_power_level_on_full_charge"]
            if not lookup then return end
            local talent = Talents[lookup.hero_name] and Talents[lookup.hero_name][lookup.talent_id]
            local dv = talent and talent.description_values and talent.description_values[1]
            if not dv then return end
            dv.value = saved.vf_orig
            saved.vf_orig = nil
        end,
    },

    -- ============================================================
    -- Battle Wizard: Fires from Ash — 3% → 1% CDR + 0.5 THP per burning kill
    -- ============================================================
    -- Talent `sienna_adept_cooldown_reduction_on_burning_enemy_killed`.
    -- Field patch on the cooldown_reduction multiplier (0.03→0.01); the
    -- additional +0.5 THP grant per burning kill is layered in via a wrapper
    -- on the proc func `sienna_adept_reduce_activated_ability_cooldown_on_burning_enemy_killed`
    -- (see runtime hook below). User's "level 25" matches vanilla.
    rework_bw_adept_fires_from_ash_1pct_plus_thp = {
        character = "sienna",
        career    = "bw_adept",
        patches   = {
            { buff = "sienna_adept_cooldown_reduction_on_burning_enemy_killed", field = "cooldown_reduction", value = 0.01 },
        },
        custom_apply = function(saved)
            if not Talents or not TalentIDLookup then return end
            local lookup = TalentIDLookup["sienna_adept_cooldown_reduction_on_burning_enemy_killed"]
            if not lookup then return end
            local talent = Talents[lookup.hero_name] and Talents[lookup.hero_name][lookup.talent_id]
            local dv = talent and talent.description_values and talent.description_values[1]
            if not dv then return end
            saved.ffa_tooltip = dv.value
            dv.value = 0.01
        end,
        custom_restore = function(saved)
            if saved.ffa_tooltip == nil then return end
            if not Talents or not TalentIDLookup then return end
            local lookup = TalentIDLookup["sienna_adept_cooldown_reduction_on_burning_enemy_killed"]
            if not lookup then return end
            local talent = Talents[lookup.hero_name] and Talents[lookup.hero_name][lookup.talent_id]
            local dv = talent and talent.description_values and talent.description_values[1]
            if not dv then return end
            dv.value = saved.ffa_tooltip
            saved.ffa_tooltip = nil
        end,
    },

    -- ============================================================
    -- Necromancer: Lost Souls passive — double radius (5 → 10)
    -- ============================================================
    -- "Lost Souls" is the Necromancer's career PASSIVE perk
    -- (`sienna_necromancer_perk_1`), not a talent. Devours 15% max HP of nearby
    -- enemies within a 5m radius — patch doubles the radius.
    rework_bw_necromancer_lost_souls_double_radius = {
        character = "sienna",
        career    = "bw_necromancer",
        patches   = {
            { buff = "sienna_necromancer_perk_1", field = "radius", value = 10 },
        },
    },

    -- ============================================================
    -- Necromancer: Withering Touch — 15s → 30s duration
    -- ============================================================
    -- Talent `sienna_necromancer_4_3` attaches buff
    -- `sienna_necromancer_4_3_withering_touch`. Duration field merged from
    -- SHOVEL_BUFF_TWEAK_DATA at boot.
    rework_bw_necromancer_withering_touch_30s = {
        character = "sienna",
        career    = "bw_necromancer",
        patches   = {
            { buff = "sienna_necromancer_4_3_withering_touch", field = "duration", value = 30 },
        },
        custom_apply = function(saved)
            if not Talents or not TalentIDLookup then return end
            local lookup = TalentIDLookup["sienna_necromancer_4_3"]
            if not lookup then return end
            local talent = Talents[lookup.hero_name] and Talents[lookup.hero_name][lookup.talent_id]
            local dv = talent and talent.description_values and talent.description_values[1]
            if not dv then return end
            saved.wt_orig = dv.value
            dv.value = 30
        end,
        custom_restore = function(saved)
            if saved.wt_orig == nil then return end
            if not Talents or not TalentIDLookup then return end
            local lookup = TalentIDLookup["sienna_necromancer_4_3"]
            if not lookup then return end
            local talent = Talents[lookup.hero_name] and Talents[lookup.hero_name][lookup.talent_id]
            local dv = talent and talent.description_values and talent.description_values[1]
            if not dv then return end
            dv.value = saved.wt_orig
            saved.wt_orig = nil
        end,
    },

    -- ============================================================
    -- Necromancer: Malediction of Nagash — 8 souls → 5 souls for crit
    -- ============================================================
    -- Talent `sienna_necromancer_4_2` (level 20). Stack threshold lives on
    -- buff `sienna_necromancer_4_2_soul_rip_stack.max_stacks` (8 vanilla).
    rework_bw_necromancer_malediction_5_souls = {
        character = "sienna",
        career    = "bw_necromancer",
        patches   = {
            { buff = "sienna_necromancer_4_2_soul_rip_stack", field = "max_stacks", value = 5 },
        },
        custom_apply = function(saved)
            if not Talents or not TalentIDLookup then return end
            local lookup = TalentIDLookup["sienna_necromancer_4_2"]
            if not lookup then return end
            local talent = Talents[lookup.hero_name] and Talents[lookup.hero_name][lookup.talent_id]
            local dv = talent and talent.description_values and talent.description_values[1]
            if not dv then return end
            saved.mn_orig = dv.value
            dv.value = 5
        end,
        custom_restore = function(saved)
            if saved.mn_orig == nil then return end
            if not Talents or not TalentIDLookup then return end
            local lookup = TalentIDLookup["sienna_necromancer_4_2"]
            if not lookup then return end
            local talent = Talents[lookup.hero_name] and Talents[lookup.hero_name][lookup.talent_id]
            local dv = talent and talent.description_values and talent.description_values[1]
            if not dv then return end
            dv.value = saved.mn_orig
            saved.mn_orig = nil
        end,
    },

    -- ============================================================
    -- Necromancer: Vanhel's Danse Macabre — +12% binary → +2%/stack cap 24%
    -- ============================================================
    -- Vanilla talent `sienna_necromancer_2_1` works binary: at ≥4 skeletons
    -- raised, gain +12% attack speed (max_stacks = 1). User's spec changes the
    -- mechanic to per-skeleton stacking: +2%/stack up to 12 stacks (+24% cap).
    -- Patches: multiplier 0.12→0.02, max_stacks 1→12. The proc functions
    -- `thank_you_skeletal_add` and `thank_you_skeletal_remove` are overridden
    -- in the runtime hook section below to add/remove one stack per skeleton
    -- raised/removed (vanilla gates on threshold; rework drops the gate).
    rework_bw_necromancer_vanhels_per_skeleton_as = {
        character = "sienna",
        career    = "bw_necromancer",
        patches   = {
            { buff = "sienna_necromancer_2_1_attack_speed", field = "multiplier", value = 0.02 },
            { buff = "sienna_necromancer_2_1_attack_speed", field = "max_stacks", value = 12   },
        },
        custom_apply = function(saved)
            if not Talents or not TalentIDLookup then return end
            local lookup = TalentIDLookup["sienna_necromancer_2_1"]
            if not lookup then return end
            local talent = Talents[lookup.hero_name] and Talents[lookup.hero_name][lookup.talent_id]
            local dv = talent and talent.description_values
            if not dv then return end
            if dv[1] then saved.vdm_dv1 = dv[1].value; dv[1].value = 0.02 end
            if dv[2] then saved.vdm_dv2 = dv[2].value; dv[2].value = 12   end
        end,
        custom_restore = function(saved)
            if not Talents or not TalentIDLookup then return end
            local lookup = TalentIDLookup["sienna_necromancer_2_1"]
            if not lookup then return end
            local talent = Talents[lookup.hero_name] and Talents[lookup.hero_name][lookup.talent_id]
            local dv = talent and talent.description_values
            if not dv then return end
            if dv[1] and saved.vdm_dv1 ~= nil then dv[1].value = saved.vdm_dv1 end
            if dv[2] and saved.vdm_dv2 ~= nil then dv[2].value = saved.vdm_dv2 end
            saved.vdm_dv1, saved.vdm_dv2 = nil, nil
        end,
    },

    -- ============================================================
    -- Waystalker: Kurnous' Reward — 30% → 5% ammo per ability special/elite
    -- ============================================================
    -- Talent `kerillian_waywatcher_activated_ability_restore_ammo_on_career_skill_special_kill`.
    -- Vanilla ammo_bonus_fraction = 0.3 (30% of max ammo on each special/elite
    -- killed by the ability shot). Rework lowers to 5% per spec.
    rework_we_waywatcher_kurnous_reward_5pct = {
        character = "kerillian",
        career    = "we_waywatcher",
        patches   = {
            { buff = "kerillian_waywatcher_activated_ability_restore_ammo_on_career_skill_special_kill", field = "ammo_bonus_fraction", value = 0.05 },
        },
        custom_apply = function(saved)
            if not Talents or not TalentIDLookup then return end
            local lookup = TalentIDLookup["kerillian_waywatcher_activated_ability_restore_ammo_on_career_skill_special_kill"]
            if not lookup then return end
            local talent = Talents[lookup.hero_name] and Talents[lookup.hero_name][lookup.talent_id]
            local dv = talent and talent.description_values and talent.description_values[1]
            if not dv then return end
            saved.kr_orig = dv.value
            dv.value = 0.05
        end,
        custom_restore = function(saved)
            if saved.kr_orig == nil then return end
            if not Talents or not TalentIDLookup then return end
            local lookup = TalentIDLookup["kerillian_waywatcher_activated_ability_restore_ammo_on_career_skill_special_kill"]
            if not lookup then return end
            local talent = Talents[lookup.hero_name] and Talents[lookup.hero_name][lookup.talent_id]
            local dv = talent and talent.description_values and talent.description_values[1]
            if not dv then return end
            dv.value = saved.kr_orig
            saved.kr_orig = nil
        end,
    },

    -- ============================================================
    -- Waystalker: Drakira's Alacrity → flat passive +10% attack speed
    -- ============================================================
    -- "Drakira's Alacrity" doesn't exist by that exact name in vanilla; the
    -- closest is `kerillian_waywatcher_attack_speed_on_ranged_headshot` (level
    -- 10, conditional +15% AS for 5s on ranged headshot). Rework replaces the
    -- talent's payload with a permanent +10% attack speed buff (no trigger).
    -- Mirrors `rework_wh_bountyhunter_rile_the_mob_movement` swap pattern.
    rework_we_waywatcher_drakiras_alacrity_passive_as = {
        character = "kerillian",
        career    = "we_waywatcher",
        patches   = {},
        custom_apply = function(saved)
            if not BuffTemplates then return end
            -- Register the permanent passive buff template if missing.
            if BuffTemplates.crt_waywatcher_drakiras_alacrity_passive == nil or BuffTemplates.crt_waywatcher_drakiras_alacrity_passive._crt_pending then
                BuffTemplates.crt_waywatcher_drakiras_alacrity_passive = {
                    buffs = {
                        {
                            stat_buff  = "attack_speed",
                            multiplier = 0.10,
                            max_stacks = 1,
                            name       = "crt_waywatcher_drakiras_alacrity_passive",
                        },
                    },
                }
                saved.drakira_created = true
            end
            -- Swap the talent's buffs list to point at the new permanent buff.
            if Talents and TalentIDLookup then
                local lookup = TalentIDLookup["kerillian_waywatcher_attack_speed_on_ranged_headshot"]
                if lookup then
                    local talent = Talents[lookup.hero_name] and Talents[lookup.hero_name][lookup.talent_id]
                    if talent and talent.buffs then
                        saved.drakira_orig_buffs = {}
                        for i, b in ipairs(talent.buffs) do saved.drakira_orig_buffs[i] = b end
                        talent.buffs = { "crt_waywatcher_drakiras_alacrity_passive" }
                    end
                end
            end
        end,
        custom_restore = function(saved)
            if Talents and TalentIDLookup and saved.drakira_orig_buffs then
                local lookup = TalentIDLookup["kerillian_waywatcher_attack_speed_on_ranged_headshot"]
                if lookup then
                    local talent = Talents[lookup.hero_name] and Talents[lookup.hero_name][lookup.talent_id]
                    if talent then talent.buffs = saved.drakira_orig_buffs end
                end
            end
            if saved.drakira_created and BuffTemplates then
                BuffTemplates.crt_waywatcher_drakiras_alacrity_passive = _crt_make_stub()
            end
            saved.drakira_orig_buffs, saved.drakira_created = nil, nil
        end,
    },

    -- ============================================================
    -- Waystalker: Ricochet — 3 → 5 bounces (+ FF safety hook)
    -- ============================================================
    -- Talent `kerillian_waywatcher_projectile_ricochet` (level 20, col 2).
    -- Vanilla bounce buff has `bonus = 3` consumed by
    -- player_projectile_unit_extension.lua:986 via
    -- `apply_buffs_to_value(buffed_bounces, "projectile_bounces")`. Simple
    -- patch lifts it to 5. Bounced projectiles route through `hit_player()`
    -- when they touch teammates, which already gates friendly fire via
    -- `DamageUtils.allow_friendly_fire_ranged(...)` — so vanilla bounces are
    -- already FF-respecting by architecture. Defensive hook added in the
    -- runtime section forces FF-skip for bounced projectiles when the rework
    -- is enabled regardless of difficulty FF setting.
    rework_we_waywatcher_ricochet_no_ff_5_bounces = {
        character = "kerillian",
        career    = "we_waywatcher",
        patches   = {
            { buff = "kerillian_waywatcher_projectile_ricochet", field = "bonus", value = 5 },
        },
        custom_apply = function(saved)
            if not Talents or not TalentIDLookup then return end
            local lookup = TalentIDLookup["kerillian_waywatcher_projectile_ricochet"]
            if not lookup then return end
            local talent = Talents[lookup.hero_name] and Talents[lookup.hero_name][lookup.talent_id]
            local dv = talent and talent.description_values and talent.description_values[1]
            if not dv then return end
            saved.ricochet_orig = dv.value
            dv.value = 5
        end,
        custom_restore = function(saved)
            if saved.ricochet_orig == nil then return end
            if not Talents or not TalentIDLookup then return end
            local lookup = TalentIDLookup["kerillian_waywatcher_projectile_ricochet"]
            if not lookup then return end
            local talent = Talents[lookup.hero_name] and Talents[lookup.hero_name][lookup.talent_id]
            local dv = talent and talent.description_values and talent.description_values[1]
            if not dv then return end
            dv.value = saved.ricochet_orig
            saved.ricochet_orig = nil
        end,
    },

    -- ============================================================
    -- Necromancer: Death Ascendant — stack duration 6s → 10s
    -- ============================================================
    -- Talent `sienna_necromancer_5_1` (level 25). Attached buff
    -- `sienna_necromancer_5_1_buff` has `duration = 6` (merged from
    -- SHOVEL_BUFF_TWEAK_DATA at boot). max_stacks = 1, refresh_durations =
    -- true, stat_buff = "cooldown_regen".
    rework_bw_necromancer_death_ascendant_10s = {
        character = "sienna",
        career    = "bw_necromancer",
        patches   = {
            { buff = "sienna_necromancer_5_1_buff", field = "duration", value = 10 },
        },
    },

    -- ============================================================
    -- Engineer: Ingenious Ordnance (lvl 10) — 80s → 240s tick
    -- ============================================================
    -- Talent `bardin_engineer_improved_explosives` (row 2). Vanilla grants a
    -- weak crafted bomb every 80s via the `bardin_engineer_bomb_grant` proc
    -- attached to buff `bardin_engineer_2_1_cooldown` (duration field 80,
    -- merged from buff_tweak_data). Rework lifts tick interval to 240s.
    -- NOTE: the "random regular bomb" portion (frag/fire instead of the
    -- weak crafted) requires overriding the bomb-grant proc — deferred for
    -- the next iteration. This v1 only changes the interval; user keeps the
    -- weak crafted bomb but receives it less frequently. Will follow up
    -- once we confirm desired bomb pool semantics.
    rework_dr_engineer_ingenious_ordnance_240s = {
        character = "bardin",
        career    = "dr_engineer",
        patches   = {
            { buff = "bardin_engineer_2_1_cooldown", field = "duration", value = 240 },
        },
    },

    -- ============================================================
    -- Engineer: Leading Shots (legacy talent restore) — replaces Ingenious Ordnance
    -- ============================================================
    -- Restores the pre-Patch-5.2.0 "Leading Shots": every 4th ranged shot is a
    -- GUARANTEED CRIT. Replaces the Ingenious Ordnance talent
    -- (bardin_engineer_improved_explosives, level-10 slot [2,1]).
    --
    -- Crank Gun: the Steam-Assisted Crank Gun career skill uses NO ammo, so we
    -- count on `on_hit` filtered to ranged projectile attack types (NOT
    -- on_ammo_used, which the ammo-less Crank Gun never fires). The Crank Gun's
    -- bullets are ranged projectiles → they DO trigger on_hit → they count.
    --
    -- Chain (all STOCK buff funcs — no custom code):
    --   counter (add_buff_on_first_target_hit, on_hit, ranged-only) -> adds a
    --   stack of accumulator each ranged shot -> accumulator (max_stacks 4,
    --   reset_on_max) -> on the 4th grants the crit buff -> crit buff
    --   (guaranteed_crit perk, consumed on the next on_critical_action).
    -- Modeled on Mercenary Paced Strikes + the engineer's own Scavenged-Shot
    -- accumulator (talent_settings_cog_dwarf_ranger.lua:331-360).
    --
    -- Additive: the OTHER 3 shots keep their normal random crit chance (the
    -- faithful "removes random crit" needs a crit-resolver hook; not done).
    -- Mutually-soft with rework_dr_engineer_ingenious_ordnance_240s: when this is
    -- ON the talent no longer references bardin_engineer_2_1_cooldown, so the 240s
    -- toggle has no visible effect (no crash — they touch different things).
    rework_dr_engineer_leading_shots = {
        character = "bardin",
        career    = "dr_engineer",
        patches   = {},
        custom_apply = function(saved)
            local buff_perks = require("scripts/unit_extensions/default_player_unit/buffs/settings/buff_perk_names")
            local AT = rawget(_G, "AttackTypes")
            if not (BuffTemplates and buff_perks and AT) then return end

            -- Ranged projectile shots only (covers the Crank Gun; excludes melee + grenades).
            local ranged_only = {
                [AT.projectile] = true,
                [AT.instant_projectile] = true,
                [AT.heavy_instant_projectile] = true,
            }

            local function _ensure(name, def)
                if BuffTemplates[name] == nil or BuffTemplates[name]._crt_pending then
                    BuffTemplates[name] = def
                    saved["ls_created_" .. name] = true
                end
            end

            _ensure("crt_engineer_leading_shots_counter", {
                buffs = { {
                    name               = "crt_engineer_leading_shots_counter",
                    buff_func          = "add_buff_on_first_target_hit",
                    buff_to_add        = "crt_engineer_leading_shots_accumulator",
                    event              = "on_hit",
                    valid_attack_types = ranged_only,
                    client_side        = true,
                } },
            })
            _ensure("crt_engineer_leading_shots_accumulator", {
                buffs = { {
                    name                = "crt_engineer_leading_shots_accumulator",
                    icon                = "bardin_engineer_ranged_crit_count",
                    max_stacks          = 4,
                    on_max_stacks_func  = "add_remove_buffs",
                    reset_on_max_stacks = true,
                    max_stack_data      = { buffs_to_add = { "crt_engineer_leading_shots_crit" } },
                } },
            })
            _ensure("crt_engineer_leading_shots_crit", {
                buffs = { {
                    name           = "crt_engineer_leading_shots_crit",
                    buff_func      = "dummy_function",
                    event          = "on_critical_action",
                    icon           = "bardin_engineer_ranged_crit_count",
                    max_stacks     = 1,
                    priority_buff  = true,
                    remove_on_proc = true,
                    perks          = { buff_perks.guaranteed_crit },
                } },
            })

            -- Repoint the Ingenious Ordnance talent at the Leading Shots counter.
            if not (Talents and TalentIDLookup) then return end
            local lookup = TalentIDLookup["bardin_engineer_improved_explosives"]
            if not lookup then return end  -- non-COG owner: talent absent → no-op
            local talent = Talents[lookup.hero_name] and Talents[lookup.hero_name][lookup.talent_id]
            if not talent then return end

            saved.ls_buffs = talent.buffs
            saved.ls_icon  = talent.icon
            saved.ls_desc  = talent.description
            saved.ls_dv    = talent.description_values
            saved.ls_dname = talent.display_name  -- usually nil (vanilla talent has only `name`)
            talent.buffs              = { "crt_engineer_leading_shots_counter" }
            talent.icon               = "bardin_engineer_ranged_crit_count"
            -- Title resolves as Localize(display_name or name) (hero_window_talents.lua:328);
            -- the vanilla `name` still localizes to "Ingenious Ordnance", so set
            -- display_name (it takes precedence) to show "Leading Shots".
            talent.display_name       = "crt_engineer_leading_shots_name"
            talent.description        = "crt_engineer_leading_shots_desc"
            talent.description_values = { { value = 4 } }
        end,
        custom_restore = function(saved)
            if Talents and TalentIDLookup then
                local lookup = TalentIDLookup["bardin_engineer_improved_explosives"]
                local talent = lookup and Talents[lookup.hero_name] and Talents[lookup.hero_name][lookup.talent_id]
                if talent and saved.ls_buffs then
                    talent.buffs              = saved.ls_buffs
                    talent.icon               = saved.ls_icon
                    talent.display_name       = saved.ls_dname
                    talent.description        = saved.ls_desc
                    talent.description_values = saved.ls_dv
                end
            end
            if BuffTemplates then
                for _, n in ipairs({
                    "crt_engineer_leading_shots_counter",
                    "crt_engineer_leading_shots_accumulator",
                    "crt_engineer_leading_shots_crit",
                }) do
                    if saved["ls_created_" .. n] then BuffTemplates[n] = _crt_make_stub() end
                end
            end
            saved.ls_buffs, saved.ls_icon, saved.ls_desc, saved.ls_dv, saved.ls_dname = nil, nil, nil, nil, nil
        end,
    },

    -- ============================================================
    -- Engineer: Full Head of Steam — 15% → 4% AS per pump stack
    -- ============================================================
    -- Best match: `bardin_engineer_power_on_max_pump` talent (row 4 col 1)
    -- attaches buff `bardin_engineer_4_1_buff` with stat_buff =
    -- "attack_speed", multiplier 0.15 (merged from
    -- buff_tweak_data.bardin_engineer_power_on_max_pump_buff.multiplier).
    -- Rework drops it to 0.04 per stack. NOTE: vanilla talent name is "power
    -- on max pump" — the user's "Full Head of Steam" likely refers to the
    -- same talent's in-game display name. Verify in-game.
    rework_dr_engineer_full_head_of_steam_4pct = {
        character = "bardin",
        career    = "dr_engineer",
        patches   = {
            { buff = "bardin_engineer_4_1_buff", field = "multiplier", value = 0.04 },
        },
        custom_apply = function(saved)
            if not Talents or not TalentIDLookup then return end
            local lookup = TalentIDLookup["bardin_engineer_power_on_max_pump"]
            if not lookup then return end
            local talent = Talents[lookup.hero_name] and Talents[lookup.hero_name][lookup.talent_id]
            local dv = talent and talent.description_values
            if not dv then return end
            -- The talent has one or two description_values; rewrite the one
            -- that holds the AS multiplier (typically [2] when the stack
            -- count is [1], but be defensive).
            for i = 1, #dv do
                if dv[i] and dv[i].value == 0.15 then
                    saved["fhos_dv_" .. i] = dv[i].value
                    dv[i].value = 0.04
                end
            end
        end,
        custom_restore = function(saved)
            if not Talents or not TalentIDLookup then return end
            local lookup = TalentIDLookup["bardin_engineer_power_on_max_pump"]
            if not lookup then return end
            local talent = Talents[lookup.hero_name] and Talents[lookup.hero_name][lookup.talent_id]
            local dv = talent and talent.description_values
            if not dv then return end
            for k, v in pairs(saved) do
                local i = tonumber(string.match(k, "^fhos_dv_(%d+)$"))
                if i and dv[i] then dv[i].value = v end
                if i then saved[k] = nil end
            end
        end,
    },

    -- ============================================================
    -- Universal: Mainstay — +15% stagger power for all careers
    -- ============================================================
    -- No talent literally named "Mainstay" exists in the decompiled source.
    -- Implementation: register a universal `crt_mainstay_universal_stagger`
    -- buff (`power_level_impact` stat_buff, multiplier 0.15) once at first
    -- apply; the runtime hook below on `TalentExtension:apply_buffs_from_talents`
    -- adds the buff to every player whenever the toggle is on, regardless of
    -- career or talent selection. Effective universal +15% stagger.
    rework_general_mainstay_stagger_15pct = {
        character = "any",
        career    = "any",
        patches   = {},
        custom_apply = function(saved)
            if not BuffTemplates then return end
            if BuffTemplates.crt_mainstay_universal_stagger == nil or BuffTemplates.crt_mainstay_universal_stagger._crt_pending then
                BuffTemplates.crt_mainstay_universal_stagger = {
                    buffs = {
                        {
                            stat_buff  = "power_level_impact",
                            multiplier = 0.15,
                            max_stacks = 1,
                            name       = "crt_mainstay_universal_stagger",
                        },
                    },
                }
                saved.mainstay_created = true
            end
        end,
        custom_restore = function(saved)
            if saved.mainstay_created and BuffTemplates then
                BuffTemplates.crt_mainstay_universal_stagger = _crt_make_stub()
            end
            saved.mainstay_created = nil
        end,
    },

    -- ============================================================
    -- Necromancer: Army of the Dead — 110s → 55s cooldown + 20s → 40s decay
    -- ============================================================
    -- Two changes, both touch non-buff fields (custom_apply):
    --   * `ActivatedAbilitySettings.bw_necromancer[1].cooldown` 110 → 55
    --   * `BuffTemplates.sienna_pet_spawn_charge.buffs[1].duration` 20 → 40
    --     (decay duration of the extra AoD skeletons before they despawn)
    rework_bw_necromancer_army_of_dead_buffed = {
        character = "sienna",
        career    = "bw_necromancer",
        patches   = {
            { buff = "sienna_pet_spawn_charge", field = "duration", value = 40 },
        },
        custom_apply = function(saved)
            if ActivatedAbilitySettings and ActivatedAbilitySettings.bw_necromancer and ActivatedAbilitySettings.bw_necromancer[1] then
                saved.aod_cooldown = ActivatedAbilitySettings.bw_necromancer[1].cooldown
                ActivatedAbilitySettings.bw_necromancer[1].cooldown = 55
            end
        end,
        custom_restore = function(saved)
            if saved.aod_cooldown ~= nil and ActivatedAbilitySettings and ActivatedAbilitySettings.bw_necromancer and ActivatedAbilitySettings.bw_necromancer[1] then
                ActivatedAbilitySettings.bw_necromancer[1].cooldown = saved.aod_cooldown
            end
            saved.aod_cooldown = nil
        end,
    },

    -- ============================================================
    -- Zealot: Holy Fortitude (best-guess = lvl 20 healing talent) → +30 max HP
    -- ============================================================
    -- "Holy Fortitude" isn't in the decompiled source by that name. The
    -- closest match is `victor_zealot_passive_healing_received` (level 20,
    -- one of three Zealot row-4 talents). Rework: swap that talent's
    -- payload to a single +30 max HP buff (`max_health` stat_buff, bonus
    -- 30). Original buffs are saved + restored on disable. Note: stat_buff
    -- `max_health` uses `bonus` field for flat additive HP (vanilla VT2
    -- convention).
    rework_wh_zealot_holy_fortitude_30_max_hp = {
        character = "victor",
        career    = "wh_zealot",
        patches   = {},
        custom_apply = function(saved)
            if not BuffTemplates or not Talents or not TalentIDLookup then return end
            if BuffTemplates.crt_zealot_holy_fortitude_max_hp == nil or BuffTemplates.crt_zealot_holy_fortitude_max_hp._crt_pending then
                BuffTemplates.crt_zealot_holy_fortitude_max_hp = {
                    buffs = {
                        {
                            stat_buff  = "max_health",
                            bonus      = 30,
                            max_stacks = 1,
                            name       = "crt_zealot_holy_fortitude_max_hp",
                        },
                    },
                }
                saved.hf_created = true
            end
            local lookup = TalentIDLookup["victor_zealot_passive_healing_received"]
            if lookup then
                local talent = Talents[lookup.hero_name] and Talents[lookup.hero_name][lookup.talent_id]
                if talent and talent.buffs then
                    saved.hf_orig_buffs = {}
                    for i, b in ipairs(talent.buffs) do saved.hf_orig_buffs[i] = b end
                    talent.buffs = { "crt_zealot_holy_fortitude_max_hp" }
                end
            end
        end,
        custom_restore = function(saved)
            if Talents and TalentIDLookup and saved.hf_orig_buffs then
                local lookup = TalentIDLookup["victor_zealot_passive_healing_received"]
                if lookup then
                    local talent = Talents[lookup.hero_name] and Talents[lookup.hero_name][lookup.talent_id]
                    if talent then talent.buffs = saved.hf_orig_buffs end
                end
            end
            if saved.hf_created and BuffTemplates then
                BuffTemplates.crt_zealot_holy_fortitude_max_hp = _crt_make_stub()
            end
            saved.hf_orig_buffs, saved.hf_created = nil, nil
        end,
    },

    -- ============================================================
    -- Slayer: Trophy Hunter bundle — 30 stacks @ 1%/hit + Impatience scale
    -- ============================================================
    -- Trophy Hunter (`bardin_slayer_passive_stacking_damage_buff`) vanilla
    -- is 10% damage per hit × 3 stacks × 2s. Rework: 1% × 30 stacks × 2s
    -- (each stack independent timer remains via vanilla refresh_durations
    -- semantics). Cap stays at +30% damage but ramps in 1% increments
    -- instead of 10% jumps. ALSO patches Impatience-equivalent buff
    -- (`bardin_slayer_passive_increased_max_stacks`) multiplier 0.1 → 0.01
    -- so its bonus scales to the new stack count instead of stacking
    -- ridiculously high (per user spec).
    -- DEFERRED for next pass: (a) "High Tally +10 stacks/kill" — vanilla
    -- increment-per-kill lives in the buff_func code (slayer extension or
    -- buff_function_templates), not in buff_tweak_data; needs proc-hook;
    -- (b) "Adrenaline Surge requires 30 stacks" — the vanilla threshold
    -- check is likely hardcoded against max_stacks, so it MAY auto-scale
    -- when max_stacks is 30 instead of 3, but verify in-game; if not,
    -- needs a separate proc-hook in next pass.
    rework_dr_slayer_trophy_hunter_30_stacks_bundle = {
        character = "bardin",
        career    = "dr_slayer",
        patches   = {
            { buff = "bardin_slayer_passive_stacking_damage_buff",  field = "max_stacks", value = 30   },
            { buff = "bardin_slayer_passive_stacking_damage_buff",  field = "multiplier", value = 0.01 },
            { buff = "bardin_slayer_passive_increased_max_stacks",  field = "multiplier", value = 0.01 },
        },
    },

    -- ============================================================
    -- Slayer: Dawi Drop — airborne damage 150% → 200%
    -- ============================================================
    -- `bardin_slayer_activated_ability_leap_damage_buff.multiplier` 1.5 → 2.0.
    -- DEFERRED for next pass: "airborne time +50%" — no buff template
    -- with an airborne-duration field surfaced in the available decompile.
    -- May live in the Leap action code or jump physics layer.
    rework_dr_slayer_dawi_drop_buffed = {
        character = "bardin",
        career    = "dr_slayer",
        patches   = {
            { buff = "bardin_slayer_activated_ability_leap_damage_buff", field = "multiplier", value = 2.0 },
        },
    },

    -- ============================================================
    -- Slayer: No Escape — ability duration 10s → 15s
    -- ============================================================
    -- `bardin_slayer_activated_ability.duration` 10 → 15. Simple patch.
    rework_dr_slayer_no_escape_15s = {
        character = "bardin",
        career    = "dr_slayer",
        patches   = {
            { buff = "bardin_slayer_activated_ability", field = "duration", value = 15 },
        },
    },

    -- ============================================================
    -- Slayer: Adrenaline Surge nerf — cooldown bonus 200% → 150%
    -- ============================================================
    -- `bardin_slayer_passive_cooldown_reduction_on_max_stacks.multiplier`
    -- 2.0 → 1.5 (cooldown regen rate at max Trophy Hunter stacks).
    rework_dr_slayer_adrenaline_surge_150pct_nerf = {
        character = "bardin",
        career    = "dr_slayer",
        patches   = {
            { buff = "bardin_slayer_passive_cooldown_reduction_on_max_stacks", field = "multiplier", value = 1.5 },
        },
    },

    -- ============================================================
    -- Zealot: Fiery Faith — +1% power per 5 missing HP, max 30 stacks
    -- ============================================================
    -- Vanilla Zealot's missing-HP power scaling (`victor_zealot_passive_increased_damage`
    -- parent + `victor_zealot_passive_damage` child) uses a chunked system:
    -- vanilla chunk_size=25 (every 25 HP missing = 1 stack), max_stacks=6,
    -- multiplier=0.05 per stack (= +30% cap at 150 HP missing). The vanilla
    -- update_func `activate_buff_stacks_based_on_health_chunks` already reads
    -- MISSING hp (via `health_extension:get_damage_taken("uncursed_max_health")`),
    -- so we just shrink the chunk to 5 and widen max_stacks to 30. Multiplier
    -- per stack drops to 0.01 so cap (+30%) stays the same — but ramps in
    -- smoother 1% increments instead of 5% jumps.
    rework_wh_zealot_fiery_faith_1pct_per_5_hp_max_30 = {
        character = "victor",
        career    = "wh_zealot",
        patches   = {
            { buff = "victor_zealot_passive_increased_damage", field = "chunk_size",  value = 5    },
            -- The chunk gate (num_chunks cap) lives on template.max_stacks of the PARENT
            -- (victor_zealot_passive_increased_damage), vanilla = 6. Without widening the
            -- parent too, the documented "30 stacks / +30% cap" is silently gated to 6 (+6%).
            -- No crash here (unlike Castigate -- vanilla parent already has max_stacks=6), but
            -- the same wrong-target class: the gate is on the parent, not the child _buff.
            { buff = "victor_zealot_passive_increased_damage", field = "max_stacks",  value = 30   },
            { buff = "victor_zealot_passive_damage",            field = "max_stacks", value = 30   },
            { buff = "victor_zealot_passive_damage",            field = "multiplier", value = 0.01 },
        },
        custom_apply = function(saved)
            if not Talents or not TalentIDLookup then return end
            local lookup = TalentIDLookup["victor_zealot_passive_increased_damage"]
            if not lookup then return end
            local talent = Talents[lookup.hero_name] and Talents[lookup.hero_name][lookup.talent_id]
            local dv = talent and talent.description_values
            if not dv then return end
            -- Description displays the multiplier and possibly stack count;
            -- rewrite defensively across all description_values entries.
            saved.ff_orig = {}
            for i, entry in ipairs(dv) do
                if type(entry.value) == "number" then
                    saved.ff_orig[i] = entry.value
                end
            end
            if dv[1] then dv[1].value = 0.01 end
            if dv[2] and type(dv[2].value) == "number" then dv[2].value = 30 end
        end,
        custom_restore = function(saved)
            if not Talents or not TalentIDLookup then return end
            local lookup = TalentIDLookup["victor_zealot_passive_increased_damage"]
            if not lookup then return end
            local talent = Talents[lookup.hero_name] and Talents[lookup.hero_name][lookup.talent_id]
            local dv = talent and talent.description_values
            if not dv or not saved.ff_orig then return end
            for i, v in pairs(saved.ff_orig) do
                if dv[i] then dv[i].value = v end
            end
            saved.ff_orig = nil
        end,
    },

    -- ============================================================
    -- Zealot: Castigate — +4% AS per Fiery Faith stack, cap +20% (5 stacks)
    -- ============================================================
    -- Vanilla `victor_zealot_attack_speed_on_health_percent` (talent at row 2)
    -- uses a threshold-based update_func (`victor_zealot_activate_buff_stacks_based_on_health_percent`)
    -- that adds 1 stack at <50% HP and 2 stacks at <20% HP (each = +10% AS).
    -- Rework: switch the update_func to `activate_buff_stacks_based_on_health_chunks`
    -- (same one Fiery Faith uses), with chunk_size = 30 (every 30 HP missing
    -- = 1 stack of Castigate). At 150 HP missing (full Zealot max), that's
    -- 5 stacks; child buff is patched to +4%/stack max 5 = +20% AS cap.
    -- The chunk function reads max-stacks from the template, so even at 30
    -- HP missing the count is gated correctly.
    rework_wh_zealot_castigate_4pct_as_per_fiery_faith = {
        character = "victor",
        career    = "wh_zealot",
        patches   = {
            { buff = "victor_zealot_attack_speed_on_health_percent",        field = "update_func", value = "activate_buff_stacks_based_on_health_chunks" },
            { buff = "victor_zealot_attack_speed_on_health_percent",        field = "chunk_size",  value = 30   },
            -- CRASH FIX (bad argument #2 to 'min'): activate_buff_stacks_based_on_health_chunks
            -- reads max_stacks from buff.template -- the PARENT buff carrying update_func, NOT
            -- the child _buff (buff_function_templates.lua:2591-2596). The vanilla parent used
            -- the threshold update_func and has NO max_stacks field, so without this line
            -- template.max_stacks is nil and `math.min(..., nil)` throws. Mirror the canonical
            -- victor_zealot_passive_move_speed shape: parent carries buff_to_add (vanilla) +
            -- chunk_size + max_stacks + update_func together. 30 HP/chunk * 5 = 150 HP missing.
            { buff = "victor_zealot_attack_speed_on_health_percent",        field = "max_stacks",  value = 5    },
            { buff = "victor_zealot_attack_speed_on_health_percent_buff",   field = "max_stacks",  value = 5    },
            { buff = "victor_zealot_attack_speed_on_health_percent_buff",   field = "multiplier",  value = 0.04 },
        },
        custom_apply = function(saved)
            if not Talents or not TalentIDLookup then return end
            local lookup = TalentIDLookup["victor_zealot_attack_speed_on_health_percent"]
            if not lookup then return end
            local talent = Talents[lookup.hero_name] and Talents[lookup.hero_name][lookup.talent_id]
            local dv = talent and talent.description_values
            if not dv then return end
            saved.cast_orig = {}
            for i, entry in ipairs(dv) do
                if type(entry.value) == "number" then saved.cast_orig[i] = entry.value end
            end
            -- Rewrite per-stack multiplier display if it's the first dv entry.
            if dv[1] and type(dv[1].value) == "number" then dv[1].value = 0.04 end
        end,
        custom_restore = function(saved)
            if not Talents or not TalentIDLookup then return end
            local lookup = TalentIDLookup["victor_zealot_attack_speed_on_health_percent"]
            if not lookup then return end
            local talent = Talents[lookup.hero_name] and Talents[lookup.hero_name][lookup.talent_id]
            local dv = talent and talent.description_values
            if not dv or not saved.cast_orig then return end
            for i, v in pairs(saved.cast_orig) do
                if dv[i] then dv[i].value = v end
            end
            saved.cast_orig = nil
        end,
    },

    -- ============================================================
    -- Grail Knight: Virtue of the Ideal — 3%/kill, max 10, indep. 10s
    -- ============================================================
    -- Vanilla `markus_questing_knight_kills_buff_power_stacking_buff`:
    -- multiplier 0.08, max_stacks 3, duration 10, refresh_durations true.
    -- Rework: 3%/stack, max 10 stacks, 10s INDEPENDENT duration (each stack
    -- expires on its own clock instead of refreshing). Three field patches
    -- plus tooltip rewrites (description_values[1] holds multiplier, [2] the
    -- max stacks; the duration value isn't changed).
    rework_es_questingknight_virtue_of_ideal_3pct_per_kill = {
        character = "markus",
        career    = "es_questingknight",
        patches   = {
            { buff = "markus_questing_knight_kills_buff_power_stacking_buff", field = "multiplier",       value = 0.03 },
            { buff = "markus_questing_knight_kills_buff_power_stacking_buff", field = "max_stacks",       value = 10   },
            { buff = "markus_questing_knight_kills_buff_power_stacking_buff", field = "refresh_durations", value = false },
        },
        custom_apply = function(saved)
            if not Talents or not TalentIDLookup then return end
            local lookup = TalentIDLookup["markus_questing_knight_kills_buff_power_stacking"]
            if not lookup then return end
            local talent = Talents[lookup.hero_name] and Talents[lookup.hero_name][lookup.talent_id]
            local dv = talent and talent.description_values
            if not dv then return end
            if dv[1] then saved.voi_dv1 = dv[1].value; dv[1].value = 0.03 end
            if dv[2] and type(dv[2].value) == "number" then saved.voi_dv2 = dv[2].value; dv[2].value = 10 end
        end,
        custom_restore = function(saved)
            if not Talents or not TalentIDLookup then return end
            local lookup = TalentIDLookup["markus_questing_knight_kills_buff_power_stacking"]
            if not lookup then return end
            local talent = Talents[lookup.hero_name] and Talents[lookup.hero_name][lookup.talent_id]
            local dv = talent and talent.description_values
            if not dv then return end
            if dv[1] and saved.voi_dv1 ~= nil then dv[1].value = saved.voi_dv1 end
            if dv[2] and saved.voi_dv2 ~= nil then dv[2].value = saved.voi_dv2 end
            saved.voi_dv1, saved.voi_dv2 = nil, nil
        end,
    },

    -- ============================================================
    -- Grail Knight: Virtue of Discipline — double parry window, no power
    -- ============================================================
    -- Vanilla `markus_questing_knight_parry_increased_power_buff` grants +20%
    -- power on successful timed block. Rework drops the power bonus
    -- (multiplier → 0) and the parry-window hook below is extended to fire
    -- for GK + this talent (mirrors the existing WHC parry-window mechanism
    -- via `ActionBlock:client_owner_start_action` and `ActionMeleeStart:client_owner_post_update`).
    rework_es_questingknight_virtue_of_discipline_double_parry = {
        character = "markus",
        career    = "es_questingknight",
        patches   = {
            { buff = "markus_questing_knight_parry_increased_power_buff", field = "multiplier", value = 0 },
        },
    },

    -- ============================================================
    -- Grail Knight: Virtue of the Impetuous Knight — 20s + MS/AS/power
    -- ============================================================
    -- Vanilla `markus_questing_knight_ability_buff_on_kill_movement_speed`:
    -- multiplier 1.35 (+35% MS via apply_movement_buff), duration 15s, max 1,
    -- refresh_durations true. Rework:
    --   * Patch movespeed multiplier 1.35 → 1.2 (+20%) and duration 15 → 20s
    --   * Register two new buff templates for AS and power (also +20%, 20s)
    --   * Register two on-kill proc templates that add those buffs
    --   * Append the new procs to the talent's buffs list
    -- Talent name: `markus_questing_knight_ability_buff_on_kill` (lvl 30).
    rework_es_questingknight_virtue_of_impetuous_buffed = {
        character = "markus",
        career    = "es_questingknight",
        -- issue 425: the two on-kill procs push crt_* names onto rpc_add_buff;
        -- gated on peer parity + wire-safe proc wrapper. (The movespeed field
        -- patches ride a VANILLA buff name and stay wire-safe on their own.)
        network_unsafe = true,
        patches   = {
            { buff = "markus_questing_knight_ability_buff_on_kill_movement_speed", field = "multiplier", value = 1.2 },
            { buff = "markus_questing_knight_ability_buff_on_kill_movement_speed", field = "duration",   value = 20 },
        },
        custom_apply = function(saved)
            if not BuffTemplates or not Talents or not TalentIDLookup then return end
            _crt_ensure_wire_safe_funcs()
            -- AS buff
            if BuffTemplates.crt_questingknight_impetuous_as == nil or BuffTemplates.crt_questingknight_impetuous_as._crt_pending then
                BuffTemplates.crt_questingknight_impetuous_as = {
                    buffs = {
                        { stat_buff = "attack_speed", multiplier = 0.2, duration = 20, max_stacks = 1,
                          refresh_durations = true, name = "crt_questingknight_impetuous_as" },
                    },
                }
                saved.imp_created_as = true
            end
            -- Power buff
            if BuffTemplates.crt_questingknight_impetuous_power == nil or BuffTemplates.crt_questingknight_impetuous_power._crt_pending then
                BuffTemplates.crt_questingknight_impetuous_power = {
                    buffs = {
                        { stat_buff = "power_level", multiplier = 0.2, duration = 20, max_stacks = 1,
                          refresh_durations = true, name = "crt_questingknight_impetuous_power" },
                    },
                }
                saved.imp_created_power = true
            end
            -- AS proc
            if BuffTemplates.crt_questingknight_impetuous_as_proc == nil or BuffTemplates.crt_questingknight_impetuous_as_proc._crt_pending then
                BuffTemplates.crt_questingknight_impetuous_as_proc = {
                    buffs = {
                        { buff_func = "crt_wire_safe_add_buff", buff_to_add = "crt_questingknight_impetuous_as",
                          event = "on_kill", name = "crt_questingknight_impetuous_as_proc" },
                    },
                }
                saved.imp_created_as_proc = true
            end
            -- Power proc
            if BuffTemplates.crt_questingknight_impetuous_power_proc == nil or BuffTemplates.crt_questingknight_impetuous_power_proc._crt_pending then
                BuffTemplates.crt_questingknight_impetuous_power_proc = {
                    buffs = {
                        { buff_func = "crt_wire_safe_add_buff", buff_to_add = "crt_questingknight_impetuous_power",
                          event = "on_kill", name = "crt_questingknight_impetuous_power_proc" },
                    },
                }
                saved.imp_created_power_proc = true
            end
            -- Append the two new procs to the talent's buffs list
            local lookup = TalentIDLookup["markus_questing_knight_ability_buff_on_kill"]
            if lookup then
                local talent = Talents[lookup.hero_name] and Talents[lookup.hero_name][lookup.talent_id]
                if talent and talent.buffs then
                    saved.imp_orig_count = #talent.buffs
                    local already_as, already_pwr = false, false
                    for _, b in ipairs(talent.buffs) do
                        if b == "crt_questingknight_impetuous_as_proc"    then already_as  = true end
                        if b == "crt_questingknight_impetuous_power_proc" then already_pwr = true end
                    end
                    if not already_as  then table.insert(talent.buffs, "crt_questingknight_impetuous_as_proc")    end
                    if not already_pwr then table.insert(talent.buffs, "crt_questingknight_impetuous_power_proc") end
                end
                -- Tooltip: rewrite multiplier shown (vanilla 1.35 baked %)
                local dv = talent and talent.description_values
                if dv and dv[1] then saved.imp_dv1 = dv[1].value; dv[1].value = 1.2 end
                if dv and dv[2] then saved.imp_dv2 = dv[2].value; dv[2].value = 20  end
            end
        end,
        custom_restore = function(saved)
            if Talents and TalentIDLookup then
                local lookup = TalentIDLookup["markus_questing_knight_ability_buff_on_kill"]
                if lookup then
                    local talent = Talents[lookup.hero_name] and Talents[lookup.hero_name][lookup.talent_id]
                    if talent and talent.buffs and saved.imp_orig_count then
                        while #talent.buffs > saved.imp_orig_count do table.remove(talent.buffs) end
                    end
                    local dv = talent and talent.description_values
                    if dv then
                        if dv[1] and saved.imp_dv1 ~= nil then dv[1].value = saved.imp_dv1 end
                        if dv[2] and saved.imp_dv2 ~= nil then dv[2].value = saved.imp_dv2 end
                    end
                end
            end
            if BuffTemplates then
                if saved.imp_created_as         then BuffTemplates.crt_questingknight_impetuous_as = _crt_make_stub() end
                if saved.imp_created_power      then BuffTemplates.crt_questingknight_impetuous_power = _crt_make_stub() end
                if saved.imp_created_as_proc    then BuffTemplates.crt_questingknight_impetuous_as_proc = _crt_make_stub() end
                if saved.imp_created_power_proc then BuffTemplates.crt_questingknight_impetuous_power_proc = _crt_make_stub() end
            end
            saved.imp_orig_count, saved.imp_dv1, saved.imp_dv2 = nil, nil, nil
            saved.imp_created_as, saved.imp_created_power, saved.imp_created_as_proc, saved.imp_created_power_proc = nil, nil, nil, nil
        end,
    },

    -- ============================================================
    -- Foot Knight: Protective Presence 5m → 10m, Rock of the Reickland → 20m
    -- ============================================================
    -- Vanilla baseline Protective Presence aura range is 5m
    -- (`markus_knight_passive_defence_aura.buffs[1].range`, merged from
    -- `buff_tweak_data.markus_knight_passive.range` at boot). Rock of the
    -- Reickland (talent `markus_knight_passive_block_cost_aura`) adds the
    -- `markus_knight_passive_range` buff which carries `range = 10`
    -- (vanilla = baseline × 2, baked in at file-load time). Rework doubles
    -- the baseline and the talent's range simultaneously: base 5→10, talent
    -- 10→20. Two field patches via the existing engine — both buff templates
    -- expose `range` on buffs[1].
    rework_es_knight_protective_presence_10m_rock_20m = {
        character = "markus",
        career    = "es_knight",
        patches   = {
            { buff = "markus_knight_passive_defence_aura", field = "range", value = 10 },
            { buff = "markus_knight_passive_range",        field = "range", value = 20 },
        },
    },

    -- ============================================================
    -- Foot Knight: Valiant Charge 30s → 45s base + Battering Ram returns to 30s
    -- ============================================================
    -- Patch `ActivatedAbilitySettings.es_2[1].cooldown` 30 → 45 in
    -- custom_apply (not a buff template). The hook below
    -- (`CareerExtension:start_activated_ability_cooldown`) detects FK +
    -- Battering Ram (`markus_knight_wide_charge`) + toggle, and refunds 1/3
    -- of the cooldown so the player ends up at 30s effective when they have
    -- Battering Ram selected — preserving the talent's vanilla doubled-width
    -- effect (driven by the talent code path in `career_ability_es_knight.lua`).
    -- DEFERRED: the "always charges through great foes" portion requires
    -- modifying the lunge/collision gate, which lives in lunge_handler / C++
    -- and isn't visible in the available decompile. Queued for next pass.
    rework_es_knight_valiant_charge_great_foes_45s_battering_ram_30s = {
        character = "markus",
        career    = "es_knight",
        patches   = {},
        custom_apply = function(saved)
            if ActivatedAbilitySettings and ActivatedAbilitySettings.es_2 and ActivatedAbilitySettings.es_2[1] then
                saved.vc_cooldown = ActivatedAbilitySettings.es_2[1].cooldown
                ActivatedAbilitySettings.es_2[1].cooldown = 45
            end
        end,
        custom_restore = function(saved)
            if saved.vc_cooldown ~= nil and ActivatedAbilitySettings and ActivatedAbilitySettings.es_2 and ActivatedAbilitySettings.es_2[1] then
                ActivatedAbilitySettings.es_2[1].cooldown = saved.vc_cooldown
            end
            saved.vc_cooldown = nil
        end,
    },

    -- ============================================================
    -- Foot Knight: Counter-Punch — +30%/stack stagger on block, max 5x
    -- ============================================================
    -- The user named "Counter-Punch" maps closest to the level-25 talent
    -- `markus_knight_free_pushes_on_block` (free push on block). Rework
    -- replaces the talent's payload with: each successful block grants
    -- +30% stagger (power_level_impact stat_buff) stacking up to 5x with a
    -- 5-second window per stack (so stacks decay if you don't follow up
    -- the block with an attack/push promptly). Three new buff templates
    -- registered (`crt_knight_counter_punch_stack`, `_proc`); talent's
    -- buffs list is swapped to point at the new proc. NOTE: "consumed on
    -- next attack/push" semantics are approximated as a short window —
    -- precise consume-on-attack semantics would require a separate
    -- on_swing remover proc, not currently implemented.
    rework_es_knight_counter_punch_stagger_stack = {
        character = "markus",
        career    = "es_knight",
        patches   = {},
        custom_apply = function(saved)
            if not BuffTemplates or not Talents or not TalentIDLookup then return end
            if BuffTemplates.crt_knight_counter_punch_stack == nil or BuffTemplates.crt_knight_counter_punch_stack._crt_pending then
                BuffTemplates.crt_knight_counter_punch_stack = {
                    buffs = {
                        {
                            stat_buff  = "power_level_impact",
                            multiplier = 0.30,
                            max_stacks = 5,
                            duration   = 5,
                            refresh_durations = true,
                            name       = "crt_knight_counter_punch_stack",
                        },
                    },
                }
                saved.cp_created_stack = true
            end
            if BuffTemplates.crt_knight_counter_punch_proc == nil or BuffTemplates.crt_knight_counter_punch_proc._crt_pending then
                BuffTemplates.crt_knight_counter_punch_proc = {
                    buffs = {
                        {
                            buff_func   = "add_buff_local",
                            buff_to_add = "crt_knight_counter_punch_stack",
                            event       = "on_block",
                            name        = "crt_knight_counter_punch_proc",
                        },
                    },
                }
                saved.cp_created_proc = true
            end
            local lookup = TalentIDLookup["markus_knight_free_pushes_on_block"]
            if lookup then
                local talent = Talents[lookup.hero_name] and Talents[lookup.hero_name][lookup.talent_id]
                if talent and talent.buffs then
                    saved.cp_orig_buffs = {}
                    for i, b in ipairs(talent.buffs) do saved.cp_orig_buffs[i] = b end
                    talent.buffs = { "crt_knight_counter_punch_proc" }
                end
            end
        end,
        custom_restore = function(saved)
            if Talents and TalentIDLookup and saved.cp_orig_buffs then
                local lookup = TalentIDLookup["markus_knight_free_pushes_on_block"]
                if lookup then
                    local talent = Talents[lookup.hero_name] and Talents[lookup.hero_name][lookup.talent_id]
                    if talent then talent.buffs = saved.cp_orig_buffs end
                end
            end
            if BuffTemplates then
                if saved.cp_created_stack then BuffTemplates.crt_knight_counter_punch_stack = _crt_make_stub() end
                if saved.cp_created_proc  then BuffTemplates.crt_knight_counter_punch_proc = _crt_make_stub() end
            end
            saved.cp_orig_buffs = nil
            saved.cp_created_stack, saved.cp_created_proc = nil, nil
        end,
    },

    -- ============================================================
    -- Warrior Priest: Shield of Faith 10s / 110s CD + Unyielding 20s
    -- ============================================================
    -- Vanilla Shield of Faith (WP career ability) lasts 5s with a 70s
    -- cooldown. Unyielding Blessing (talent `victor_priest_6_1`, level 30)
    -- extends the duration by an additional 10s. Rework triples the package:
    --   * base duration   5 → 10s    (CareerConstants.wh_priest.ability_base_duration)
    --   * cooldown        70 → 110s  (ActivatedAbilitySettings.wh_priest[1].cooldown)
    --   * Unyielding +10  → +20s     (CareerConstants.wh_priest.talent_6_1_improved_ability_duration)
    -- All three patches mutate non-buff-template tables, so the engine's
    -- patches list isn't usable here — everything happens in custom_apply.
    rework_wh_priest_shield_of_faith_10s_110s_cd_plus_unyielding_20s = {
        character = "victor",
        career    = "wh_priest",
        patches   = {},
        custom_apply = function(saved)
            if CareerConstants and CareerConstants.wh_priest then
                saved.sof_base_duration   = CareerConstants.wh_priest.ability_base_duration
                saved.sof_unyielding_bonus = CareerConstants.wh_priest.talent_6_1_improved_ability_duration
                CareerConstants.wh_priest.ability_base_duration            = 10
                CareerConstants.wh_priest.talent_6_1_improved_ability_duration = 20
            end
            if ActivatedAbilitySettings and ActivatedAbilitySettings.wh_priest and ActivatedAbilitySettings.wh_priest[1] then
                saved.sof_cooldown = ActivatedAbilitySettings.wh_priest[1].cooldown
                ActivatedAbilitySettings.wh_priest[1].cooldown = 110
            end
            -- Tooltip rewrite for Unyielding Blessing (talent_6_1)
            if Talents and TalentIDLookup then
                local lookup = TalentIDLookup["victor_priest_6_1"]
                if lookup then
                    local talent = Talents[lookup.hero_name] and Talents[lookup.hero_name][lookup.talent_id]
                    local dv = talent and talent.description_values and talent.description_values[1]
                    if dv then saved.sof_unyielding_tooltip = dv.value; dv.value = 20 end
                end
            end
        end,
        custom_restore = function(saved)
            if CareerConstants and CareerConstants.wh_priest then
                if saved.sof_base_duration    ~= nil then CareerConstants.wh_priest.ability_base_duration            = saved.sof_base_duration end
                if saved.sof_unyielding_bonus ~= nil then CareerConstants.wh_priest.talent_6_1_improved_ability_duration = saved.sof_unyielding_bonus end
            end
            if saved.sof_cooldown ~= nil and ActivatedAbilitySettings and ActivatedAbilitySettings.wh_priest and ActivatedAbilitySettings.wh_priest[1] then
                ActivatedAbilitySettings.wh_priest[1].cooldown = saved.sof_cooldown
            end
            if saved.sof_unyielding_tooltip ~= nil and Talents and TalentIDLookup then
                local lookup = TalentIDLookup["victor_priest_6_1"]
                if lookup then
                    local talent = Talents[lookup.hero_name] and Talents[lookup.hero_name][lookup.talent_id]
                    local dv = talent and talent.description_values and talent.description_values[1]
                    if dv then dv.value = saved.sof_unyielding_tooltip end
                end
            end
            saved.sof_base_duration, saved.sof_unyielding_bonus, saved.sof_cooldown, saved.sof_unyielding_tooltip = nil, nil, nil, nil
        end,
    },

    -- ============================================================
    -- Warrior Priest: Prayer of Vengeance — self +40% / others +20% vs monsters
    -- ============================================================
    -- Talent `victor_priest_5_1` (level 25) applies aura buff
    -- `victor_priest_5_1_buff` (stat_buff = "power_level_large", multiplier
    -- 0.15) to teammates within ~100m. Rework: bump aura multiplier to 0.20
    -- (so everyone gets +20%); ALSO register a self-only +20% buff and append
    -- it to the talent's buffs list so the WP himself gets a stacked +40%
    -- total (0.20 from aura + 0.20 from self-only = +40% additive via
    -- action_utils.lua:353's stacking formula).
    rework_wh_priest_prayer_of_vengeance_self_40_others_20 = {
        character = "victor",
        career    = "wh_priest",
        patches   = {
            { buff = "victor_priest_5_1_buff", field = "multiplier", value = 0.20 },
        },
        custom_apply = function(saved)
            if not BuffTemplates then return end
            -- Self-only +20% buff template
            if BuffTemplates.crt_priest_prayer_self_extra == nil or BuffTemplates.crt_priest_prayer_self_extra._crt_pending then
                BuffTemplates.crt_priest_prayer_self_extra = {
                    buffs = {
                        {
                            stat_buff  = "power_level_large",
                            multiplier = 0.20,
                            max_stacks = 1,
                            name       = "crt_priest_prayer_self_extra",
                        },
                    },
                }
                saved.pov_created_self = true
            end
            -- Append to talent's buffs list
            if Talents and TalentIDLookup then
                local lookup = TalentIDLookup["victor_priest_5_1"]
                if lookup then
                    local talent = Talents[lookup.hero_name] and Talents[lookup.hero_name][lookup.talent_id]
                    if talent and talent.buffs then
                        local already = false
                        for _, b in ipairs(talent.buffs) do
                            if b == "crt_priest_prayer_self_extra" then already = true; break end
                        end
                        if not already then
                            saved.pov_orig_count = #talent.buffs
                            table.insert(talent.buffs, "crt_priest_prayer_self_extra")
                        end
                    end
                    -- Tooltip rewrite: aura value is now 0.20
                    local dv = talent and talent.description_values and talent.description_values[1]
                    if dv then saved.pov_tooltip = dv.value; dv.value = 0.20 end
                end
            end
        end,
        custom_restore = function(saved)
            if Talents and TalentIDLookup then
                local lookup = TalentIDLookup["victor_priest_5_1"]
                if lookup then
                    local talent = Talents[lookup.hero_name] and Talents[lookup.hero_name][lookup.talent_id]
                    if talent and talent.buffs and saved.pov_orig_count then
                        while #talent.buffs > saved.pov_orig_count do table.remove(talent.buffs) end
                    end
                    if saved.pov_tooltip ~= nil and talent and talent.description_values and talent.description_values[1] then
                        talent.description_values[1].value = saved.pov_tooltip
                    end
                end
            end
            if saved.pov_created_self and BuffTemplates then
                BuffTemplates.crt_priest_prayer_self_extra = _crt_make_stub()
            end
            saved.pov_created_self, saved.pov_orig_count, saved.pov_tooltip = nil, nil, nil
        end,
    },

    -- ============================================================
    -- Unchained: Wildfire — +50% initial burst damage + 25% burn radius
    -- ============================================================
    -- Vanilla Wildfire talent (`sienna_unchained_activated_ability_fire_aura`,
    -- row 6 col 2) switches the ult's explosion to the larger-radius variant
    -- `explosion_bw_unchained_ability_increased_radius` (radius = 5) and uses
    -- damage profile `overcharge_explosion_strong_ability` (power_distribution
    -- .attack = 0.15). Rework: when toggle is on, lift the variant explosion's
    -- radius to 6.25 (+25%) and the damage profile's attack to 0.225 (+50%).
    -- These tables are ExplosionTemplates / DamageProfileTemplates, not
    -- BuffTemplates, so all mutations happen in custom_apply.
    -- DEFERRED: the "make Wildfire effect innate" portion (remove the
    -- talent gate in career_ability_bw_unchained.lua:158) requires a runtime
    -- hook on the ability's explosion selection — queued for next pass.
    rework_bw_unchained_wildfire_burst_and_radius = {
        character = "sienna",
        career    = "bw_unchained",
        patches   = {},
        custom_apply = function(saved)
            if ExplosionTemplates and ExplosionTemplates.explosion_bw_unchained_ability_increased_radius then
                local t = ExplosionTemplates.explosion_bw_unchained_ability_increased_radius
                if type(t.radius) == "number" then
                    saved.wf_explosion_radius = t.radius
                    t.radius = t.radius * 1.25
                end
            end
            if DamageProfileTemplates and DamageProfileTemplates.overcharge_explosion_strong_ability then
                local dp = DamageProfileTemplates.overcharge_explosion_strong_ability
                if dp.power_distribution and type(dp.power_distribution.attack) == "number" then
                    saved.wf_damage_attack = dp.power_distribution.attack
                    dp.power_distribution.attack = dp.power_distribution.attack * 1.5
                end
            end
        end,
        custom_restore = function(saved)
            if saved.wf_explosion_radius and ExplosionTemplates and ExplosionTemplates.explosion_bw_unchained_ability_increased_radius then
                ExplosionTemplates.explosion_bw_unchained_ability_increased_radius.radius = saved.wf_explosion_radius
            end
            if saved.wf_damage_attack and DamageProfileTemplates and DamageProfileTemplates.overcharge_explosion_strong_ability then
                DamageProfileTemplates.overcharge_explosion_strong_ability.power_distribution.attack = saved.wf_damage_attack
            end
            saved.wf_explosion_radius, saved.wf_damage_attack = nil, nil
        end,
    },

    -- ============================================================
    -- Unchained: Numb to Pain — 4x stacks, burn-elite-kill gain, lose on hit
    -- ============================================================
    -- Vanilla talent `sienna_unchained_reduced_damage_taken_after_venting_2`
    -- (row 4 col 3) grants stacking DR on vent. Rework swaps the entire
    -- payload: register a new stacking buff (`crt_sienna_numb_to_pain_stack`,
    -- max_stacks=4, multiplier=-0.05, infinite duration), plus a proc
    -- (`crt_sienna_numb_to_pain_proc`, fires on elite-or-special burn-kill),
    -- plus a stack-remover (`crt_sienna_numb_to_pain_remover`, removes 1
    -- stack per damage taken). Talent's buffs list swapped at apply time.
    -- The "kill must be a burning enemy + elite or special" filter lives in
    -- the proc's buff_func (`add_buff_on_burning_special_or_elite_kill`,
    -- runtime override below).
    -- ============================================================
    -- Unchained: Unstable Strength rescale  (10% melee power / 5 overcharge,
    -- up to 6x  -- vs vanilla 12% / 6 overcharge, up to 5x)
    -- ============================================================
    -- Unstable Strength is the career PASSIVE, not a tree talent: the driver
    -- `sienna_unchained_passive_increased_melee_power_on_overcharge` (buffs[1]
    -- .chunk_size = 6, .max_sub_buff_stacks default 5) runs
    -- activate_server_buff_stacks_based_on_overcharge_chunks to add up to N stacks
    -- of `sienna_unchained_passive_melee_power_on_overcharge` (buffs[1].max_stacks
    -- = 5, .multiplier = 0.12, stat power_level_melee). Rescale = chunk 6->5,
    -- max 5->6 (on BOTH the driver's max_sub_buff_stacks AND the stack buff's
    -- max_stacks, or the driver caps at the lower), multiplier 0.12->0.10.
    -- This is the "master" toggle the other Unchained reworks read to pick their
    -- per-stack math (5%/6x when on, 6%/5x when off). Pure runtime field patch on
    -- shared BuffTemplates; restored on toggle-off.
    rework_bw_unchained_unstable_strength_rescale = {
        character = "sienna",
        career    = "bw_unchained",
        patches   = {},
        custom_apply = function(saved)
            if not BuffTemplates then return end
            local drv = BuffTemplates.sienna_unchained_passive_increased_melee_power_on_overcharge
            local drv_b = drv and drv.buffs and drv.buffs[1]
            if drv_b then
                saved.us_chunk = drv_b.chunk_size
                saved.us_maxsub = drv_b.max_sub_buff_stacks
                drv_b.chunk_size = 5
                drv_b.max_sub_buff_stacks = 6
            end
            local stk = BuffTemplates.sienna_unchained_passive_melee_power_on_overcharge
            local stk_b = stk and stk.buffs and stk.buffs[1]
            if stk_b then
                saved.us_maxstacks = stk_b.max_stacks
                saved.us_mult = stk_b.multiplier
                stk_b.max_stacks = 6
                stk_b.multiplier = 0.10
            end
        end,
        custom_restore = function(saved)
            if not BuffTemplates then return end
            local drv = BuffTemplates.sienna_unchained_passive_increased_melee_power_on_overcharge
            local drv_b = drv and drv.buffs and drv.buffs[1]
            if drv_b and saved.us_chunk ~= nil then
                drv_b.chunk_size = saved.us_chunk
                drv_b.max_sub_buff_stacks = saved.us_maxsub
            end
            local stk = BuffTemplates.sienna_unchained_passive_melee_power_on_overcharge
            local stk_b = stk and stk.buffs and stk.buffs[1]
            if stk_b and saved.us_maxstacks ~= nil then
                stk_b.max_stacks = saved.us_maxstacks
                stk_b.multiplier = saved.us_mult
            end
            saved.us_chunk, saved.us_maxsub, saved.us_maxstacks, saved.us_mult = nil, nil, nil, nil
        end,
    },

    -- ============================================================
    -- Unchained: Unstable Strength stacks ALSO grant burn-DoT damage
    -- ============================================================
    -- Adds a 2nd stat_buff entry (increased_burn_dot_damage, the burn-DoT scaler)
    -- to the US stack buff, so every US stack grants +12% DoT damage (10% up to 6x
    -- when the US-rescale toggle #1 is on, matching its per-stack cadence). The
    -- driver adds N US-buff instances per overcharge chunk; each now applies the
    -- DoT bonus too. Idempotent: strips any prior crt_us_dot entry before adding.
    rework_bw_unchained_unstable_strength_dot = {
        character = "sienna",
        career    = "bw_unchained",
        patches   = {},
        custom_apply = function(saved)
            if not BuffTemplates then return end
            local stk = BuffTemplates.sienna_unchained_passive_melee_power_on_overcharge
            if not (stk and stk.buffs) then return end
            local us_on = mod:get("rework_bw_unchained_unstable_strength_rescale")
            local dot   = us_on and 0.10 or 0.12
            local maxn  = us_on and 6 or 5
            for i = #stk.buffs, 1, -1 do
                if stk.buffs[i].name == "crt_us_dot" then table.remove(stk.buffs, i) end
            end
            stk.buffs[#stk.buffs + 1] = { stat_buff = "increased_burn_dot_damage", multiplier = dot, max_stacks = maxn, name = "crt_us_dot" }
            saved.dot_added = true
        end,
        custom_restore = function(saved)
            if not BuffTemplates then return end
            local stk = BuffTemplates.sienna_unchained_passive_melee_power_on_overcharge
            if stk and stk.buffs then
                for i = #stk.buffs, 1, -1 do
                    if stk.buffs[i].name == "crt_us_dot" then table.remove(stk.buffs, i) end
                end
            end
            saved.dot_added = nil
        end,
    },

    -- ============================================================
    -- Unchained: Chain Reaction explosions IGNITE nearby enemies
    -- ============================================================
    -- Chain Reaction's on-burning-kill explosion uses the no_damage push profile
    -- `slayer_leap_landing` (pure stagger, zero damage -- see MECHANICS). Giving
    -- the explosion a `dot_template_name` makes it apply a burn DoT to everything
    -- caught, so it actually lights nearby enemies on fire. Pure data patch on the
    -- shared ExplosionTemplates entry; restored on toggle-off.
    rework_bw_unchained_chain_reaction_ignite = {
        character = "sienna",
        career    = "bw_unchained",
        patches   = {},
        custom_apply = function(saved)
            local ET = rawget(_G, "ExplosionTemplates")
            local e = ET and ET.sienna_unchained_burning_enemies_explosion
            local exp = e and e.explosion
            if exp and exp.dot_template_name == nil then
                exp.dot_template_name = "burning_dot_3tick"
                saved.cr_dot_added = true
            end
            -- Bigger spread: the vanilla burst (radius 0.5..1.5) is HALF the vanilla
            -- fire explosion (lamp_oil radius 3), so almost nothing catches the burn DoT.
            -- Widen to lamp_oil scale so the ignite actually spreads to a cluster.
            if exp and saved.cr_radius_orig == nil then
                saved.cr_radius_orig = { exp.radius_min, exp.radius_max, exp.max_damage_radius_min, exp.max_damage_radius_max }
                exp.radius_min, exp.radius_max = 1.5, 3
                exp.max_damage_radius_min, exp.max_damage_radius_max = 1, 3
            end
            -- More often: the burning-kill explosion fires on only 40% of burning enemy
            -- deaths by default (talent sienna_unchained_exploding_burning_enemies,
            -- proc_chance 0.4). Bump to 100% so the chain actually chains.
            local BT = rawget(_G, "BuffTemplates")
            local b = BT and BT.sienna_unchained_exploding_burning_enemies
            local sub = b and b.buffs and b.buffs[1]
            if sub and saved.cr_proc_orig == nil then
                saved.cr_proc_orig = sub.proc_chance
                sub.proc_chance = 1.0
            end
        end,
        custom_restore = function(saved)
            local ET = rawget(_G, "ExplosionTemplates")
            local e = ET and ET.sienna_unchained_burning_enemies_explosion
            local exp = e and e.explosion
            if exp and saved.cr_dot_added then
                exp.dot_template_name = nil
                saved.cr_dot_added = nil
            end
            if exp and saved.cr_radius_orig then
                local o = saved.cr_radius_orig
                exp.radius_min, exp.radius_max = o[1], o[2]
                exp.max_damage_radius_min, exp.max_damage_radius_max = o[3], o[4]
                saved.cr_radius_orig = nil
            end
            local BT = rawget(_G, "BuffTemplates")
            local b = BT and BT.sienna_unchained_exploding_burning_enemies
            local sub = b and b.buffs and b.buffs[1]
            if sub and saved.cr_proc_orig ~= nil then
                sub.proc_chance = saved.cr_proc_orig
                saved.cr_proc_orig = nil
            end
        end,
    },

    -- ============================================================
    -- Unchained: Natural Talent -> +ranged power per Unstable Strength stack
    -- ============================================================
    -- Replaces vanilla Natural Talent (sienna_unchained_reduced_overcharge, -10%
    -- vent overcharge) with +6% ranged power per US stack (5% up to 6x when #1 is
    -- on). Same overcharge-chunk driver pattern as Numb to Pain (#5): a crt driver
    -- (update_func activate_server_buff_stacks_based_on_overcharge_chunks) keeps N
    -- stacks of a power_level_ranged buff in sync with overcharge.
    rework_bw_unchained_natural_talent_ranged = {
        character = "sienna",
        career    = "bw_unchained",
        -- issue 425: the overcharge-chunk driver adds SERVER-CONTROLLED crt_*
        -- stacks (broadcast on rpc_add_buff + replayed to hot-joiners); gated
        -- on peer parity + the wire-safe driver wrapper (which also strips its
        -- own stacks when parity degrades).
        network_unsafe = true,
        patches   = {},
        custom_apply = function(saved)
            if not BuffTemplates or not Talents or not TalentIDLookup then return end
            _crt_ensure_wire_safe_funcs()
            local us_on = mod:get("rework_bw_unchained_unstable_strength_rescale")
            local chunk = us_on and 5 or 6
            local maxn  = us_on and 6 or 5
            local rng   = us_on and 0.05 or 0.06
            BuffTemplates.crt_sienna_natural_talent_ranged_stack = {
                buffs = { { stat_buff = "power_level_ranged", multiplier = rng, max_stacks = maxn, name = "crt_sienna_natural_talent_ranged_stack" } },
            }
            BuffTemplates.crt_sienna_natural_talent_ranged_driver = {
                buffs = { { update_func = "crt_wire_safe_overcharge_chunks_driver", chunk_size = chunk, buff_to_add = "crt_sienna_natural_talent_ranged_stack", max_sub_buff_stacks = maxn, name = "crt_sienna_natural_talent_ranged_driver" } },
            }
            saved.nt_created = true
            local lookup = TalentIDLookup["sienna_unchained_reduced_overcharge"]
            if lookup then
                local talent = Talents[lookup.hero_name] and Talents[lookup.hero_name][lookup.talent_id]
                if talent and talent.buffs then
                    saved.nt_orig_buffs = {}
                    for i, b in ipairs(talent.buffs) do saved.nt_orig_buffs[i] = b end
                    talent.buffs = { "crt_sienna_natural_talent_ranged_driver" }
                end
            end
        end,
        custom_restore = function(saved)
            if Talents and TalentIDLookup and saved.nt_orig_buffs then
                local lookup = TalentIDLookup["sienna_unchained_reduced_overcharge"]
                if lookup then
                    local talent = Talents[lookup.hero_name] and Talents[lookup.hero_name][lookup.talent_id]
                    if talent then talent.buffs = saved.nt_orig_buffs end
                end
            end
            if BuffTemplates and saved.nt_created then
                BuffTemplates.crt_sienna_natural_talent_ranged_stack = _crt_make_stub()
                BuffTemplates.crt_sienna_natural_talent_ranged_driver = _crt_make_stub()
            end
            saved.nt_orig_buffs = nil
            saved.nt_created = nil
        end,
    },

    -- ============================================================
    -- Unchained: Abandon -> innate, slot becomes "Flame Unending" (CDR per US stack)
    -- ============================================================
    -- (a) Abandon's effect (sienna_unchained_health_to_ult, overcharge->cooldown)
    --     becomes base kit: append that buff to PassiveAbilitySettings.bw_3.buffs
    --     (the always-on career passive list, career_ability_settings.lua:599).
    -- (b) The lvl-25 talent slot (talent name == buff name "sienna_unchained_
    --     health_to_ult") becomes "Flame Unending": the career skill RECHARGES
    --     +6% faster per US stack (5% up to 6x = +30% at full stacks when #1 on),
    --     via the same overcharge-chunk driver. Uses `cooldown_regen` -- the
    --     CONTINUOUS decay-rate stat (cooldown_speed = apply_buffs_to_value(1,
    --     "cooldown_regen"), POSITIVE = faster) -- so recharge accelerates as US
    --     stacks build during the cooldown. NOT `activated_cooldown`, which only
    --     trims the cooldown ONCE at activation (cost-gated, one-shot) and never
    --     sped the passive recharge. Same activated_cooldown-vs-cooldown_regen
    --     distinction as the OE fix (career_tweaker_oe_cooldown.lua). Both reverted on toggle-off.
    rework_bw_unchained_abandon_innate_flame_unending = {
        character = "sienna",
        career    = "bw_unchained",
        -- issue 425: same server-controlled overcharge-chunk driver class as
        -- rework_bw_unchained_natural_talent_ranged; gated on peer parity.
        -- (The Abandon-innate PassiveAbilitySettings append is a vanilla buff
        -- name and stays wire-safe on its own.)
        network_unsafe = true,
        patches   = {},
        custom_apply = function(saved)
            if not BuffTemplates or not Talents or not TalentIDLookup then return end
            _crt_ensure_wire_safe_funcs()
            local PAS = rawget(_G, "PassiveAbilitySettings")
            local pa = PAS and PAS.bw_3
            if pa and pa.buffs then
                local present = false
                for _, b in ipairs(pa.buffs) do if b == "sienna_unchained_health_to_ult" then present = true break end end
                if not present then
                    pa.buffs[#pa.buffs + 1] = "sienna_unchained_health_to_ult"
                    saved.abandon_innate_added = true
                end
            end
            -- Show Abandon in the passive section's perk list (loc keys overridden via
            -- the shared _G.Localize hook). Idempotent against re-apply.
            if pa and pa.perks then
                local perk_present = false
                for _, p in ipairs(pa.perks) do if p.display_name == "crt_abandon_perk_name" then perk_present = true break end end
                if not perk_present then
                    pa.perks[#pa.perks + 1] = { description = "crt_abandon_perk_desc", display_name = "crt_abandon_perk_name" }
                    saved.abandon_perk_added = true
                end
            end
            local us_on = mod:get("rework_bw_unchained_unstable_strength_rescale")
            local chunk = us_on and 5 or 6
            local maxn  = us_on and 6 or 5
            -- cooldown_regen MULTIPLIER, POSITIVE = faster recharge (stacking_multiplier;
            -- N stacks accumulate N*cdr into the decay-speed root). 6x0.05 (rescale) or
            -- 5x0.06 = +30% recharge speed at full Unstable Strength stacks.
            local cdr   = us_on and 0.05 or 0.06
            BuffTemplates.crt_sienna_flame_unending_stack = {
                buffs = { { stat_buff = "cooldown_regen", multiplier = cdr, max_stacks = maxn, name = "crt_sienna_flame_unending_stack" } },
            }
            BuffTemplates.crt_sienna_flame_unending_driver = {
                buffs = { { update_func = "crt_wire_safe_overcharge_chunks_driver", chunk_size = chunk, buff_to_add = "crt_sienna_flame_unending_stack", max_sub_buff_stacks = maxn, name = "crt_sienna_flame_unending_driver" } },
            }
            saved.fu_created = true
            local lookup = TalentIDLookup["sienna_unchained_health_to_ult"]
            if lookup then
                local talent = Talents[lookup.hero_name] and Talents[lookup.hero_name][lookup.talent_id]
                if talent and talent.buffs then
                    saved.fu_orig_buffs = {}
                    for i, b in ipairs(talent.buffs) do saved.fu_orig_buffs[i] = b end
                    talent.buffs = { "crt_sienna_flame_unending_driver" }
                end
            end
        end,
        custom_restore = function(saved)
            local PAS = rawget(_G, "PassiveAbilitySettings")
            local pa = PAS and PAS.bw_3
            if pa and pa.buffs and saved.abandon_innate_added then
                for i = #pa.buffs, 1, -1 do
                    if pa.buffs[i] == "sienna_unchained_health_to_ult" then table.remove(pa.buffs, i) break end
                end
            end
            if pa and pa.perks and saved.abandon_perk_added then
                for i = #pa.perks, 1, -1 do
                    if pa.perks[i].display_name == "crt_abandon_perk_name" then table.remove(pa.perks, i) break end
                end
            end
            if Talents and TalentIDLookup and saved.fu_orig_buffs then
                local lookup = TalentIDLookup["sienna_unchained_health_to_ult"]
                if lookup then
                    local talent = Talents[lookup.hero_name] and Talents[lookup.hero_name][lookup.talent_id]
                    if talent then talent.buffs = saved.fu_orig_buffs end
                end
            end
            if BuffTemplates and saved.fu_created then
                BuffTemplates.crt_sienna_flame_unending_stack = _crt_make_stub()
                BuffTemplates.crt_sienna_flame_unending_driver = _crt_make_stub()
            end
            saved.abandon_innate_added = nil
            saved.abandon_perk_added = nil
            saved.fu_orig_buffs = nil
            saved.fu_created = nil
        end,
    },

    -- ============================================================
    -- Mercenary: Enhanced Training -> tiered Paced Strikes (2/3/4 targets)
    -- ============================================================
    -- Vanilla Enhanced Training (markus_mercenary_passive_improved) requires 4
    -- targets for a flat buff and gives nothing at 3. Rework: with Enhanced
    -- Training taken, a light/heavy hitting >=2 targets grants `target_number`
    -- stacks (cap 4) of a 5% attack-speed buff (6s) -> 2 tgt=10%, 3=15%, 4=20%;
    -- <2 = none. Base Paced Strikes (no Enhanced Training) and the other proc
    -- branches keep vanilla behaviour (>=3 target gate). Done by pointing
    -- markus_mercenary_passive.buff_func at a crt ProcFunction (registered below)
    -- that replicates vanilla except the Enhanced-Training branch; the AS buff is
    -- crt_merc_enhanced_training_as (attack_speed 0.05, max 4, 6s).
    rework_es_mercenary_enhanced_training_tiered = {
        character = "markus",
        career    = "es_mercenary",
        -- issue 425: crt_enhanced_training_proc adds crt_merc_enhanced_training_as
        -- via BuffSystem:add_buff (rpc_add_buff broadcast); gated on peer parity,
        -- with the parity fallback inline in the proc (exact vanilla ET branch).
        network_unsafe = true,
        patches   = { { buff = "markus_mercenary_passive", field = "buff_func", value = "crt_enhanced_training_proc" } },
        custom_apply = function(saved)
            if not BuffTemplates then return end
            BuffTemplates.crt_merc_enhanced_training_as = {
                buffs = { { stat_buff = "attack_speed", multiplier = 0.05, max_stacks = 4, duration = 6, name = "crt_merc_enhanced_training_as" } },
            }
            saved.et_created = true
        end,
        custom_restore = function(saved)
            if BuffTemplates and saved.et_created then BuffTemplates.crt_merc_enhanced_training_as = _crt_make_stub() end
            saved.et_created = nil
        end,
    },

    -- ============================================================
    -- Unchained: Numb to Pain -> -DR + less Blood-Magic overcharge per Unstable
    -- Strength stack  (REPLACES the prior burn-elite-kill DR-stack design)
    -- ============================================================
    -- Per Unstable Strength stack (= per overcharge chunk, mirroring US's own
    -- driver): -6% damage taken AND -12% overcharge generated by Blood Magic (the
    -- Unchained damage->overcharge passive; stat `reduced_overcharge_from_passive`,
    -- distinct from `reduced_overcharge` which is the venting/casting one). When
    -- the US-rescale toggle (#1) is on, US runs 5oc/6x so this mirrors it at
    -- -5%/-10% up to 6x. Reuses the pre-registered crt buffs:
    --   crt_sienna_numb_to_pain_stack = per-stack buff, two stat_buffs (damage_taken
    --       + reduced_overcharge_from_passive).
    --   crt_sienna_numb_to_pain_proc  = REPURPOSED as the overcharge-chunk DRIVER
    --       (update_func activate_server_buff_stacks_based_on_overcharge_chunks --
    --       the same engine func Unstable Strength uses), keeps N stacks in sync
    --       with current overcharge.
    --   crt_sienna_numb_to_pain_remover = now unused; left as a stub (the driver
    --       auto-tracks stacks up AND down, so no on-hit remover is needed).
    -- setting_id kept (legacy name) to avoid data/loc churn; label/desc updated.
    rework_bw_unchained_numb_to_pain_4x_burn_kill_lose_on_hit = {
        character = "sienna",
        career    = "bw_unchained",
        -- issue 425: same server-controlled overcharge-chunk driver class as
        -- rework_bw_unchained_natural_talent_ranged; gated on peer parity.
        network_unsafe = true,
        patches   = {},
        custom_apply = function(saved)
            if not BuffTemplates or not Talents or not TalentIDLookup then return end
            _crt_ensure_wire_safe_funcs()
            local us_on   = mod:get("rework_bw_unchained_unstable_strength_rescale")
            local chunk   = us_on and 5 or 6
            local maxn    = us_on and 6 or 5
            local dmg_mul = us_on and -0.05 or -0.06
            local oc_mul  = us_on and -0.10 or -0.12
            BuffTemplates.crt_sienna_numb_to_pain_stack = {
                buffs = {
                    { stat_buff = "damage_taken",                    multiplier = dmg_mul, max_stacks = maxn, name = "crt_sienna_numb_to_pain_stack" },
                    { stat_buff = "reduced_overcharge_from_passive", multiplier = oc_mul,  max_stacks = maxn, name = "crt_sienna_numb_to_pain_stack_oc" },
                },
            }
            saved.ntp_created_stack = true
            BuffTemplates.crt_sienna_numb_to_pain_proc = {
                buffs = {
                    {
                        update_func         = "crt_wire_safe_overcharge_chunks_driver",
                        chunk_size          = chunk,
                        buff_to_add         = "crt_sienna_numb_to_pain_stack",
                        max_sub_buff_stacks = maxn,
                        name                = "crt_sienna_numb_to_pain_proc",
                    },
                },
            }
            saved.ntp_created_proc = true
            -- Keep the remover registered as an (unused) stub for NetworkLookup determinism.
            if BuffTemplates.crt_sienna_numb_to_pain_remover == nil or BuffTemplates.crt_sienna_numb_to_pain_remover._crt_pending then
                BuffTemplates.crt_sienna_numb_to_pain_remover = _crt_make_stub()
            end
            local lookup = TalentIDLookup["sienna_unchained_reduced_damage_taken_after_venting_2"]
            if lookup then
                local talent = Talents[lookup.hero_name] and Talents[lookup.hero_name][lookup.talent_id]
                if talent and talent.buffs then
                    saved.ntp_orig_buffs = {}
                    for i, b in ipairs(talent.buffs) do saved.ntp_orig_buffs[i] = b end
                    talent.buffs = { "crt_sienna_numb_to_pain_proc" }
                end
            end
        end,
        custom_restore = function(saved)
            if Talents and TalentIDLookup and saved.ntp_orig_buffs then
                local lookup = TalentIDLookup["sienna_unchained_reduced_damage_taken_after_venting_2"]
                if lookup then
                    local talent = Talents[lookup.hero_name] and Talents[lookup.hero_name][lookup.talent_id]
                    if talent then talent.buffs = saved.ntp_orig_buffs end
                end
            end
            if BuffTemplates then
                if saved.ntp_created_stack then BuffTemplates.crt_sienna_numb_to_pain_stack = _crt_make_stub() end
                if saved.ntp_created_proc  then BuffTemplates.crt_sienna_numb_to_pain_proc = _crt_make_stub() end
            end
            saved.ntp_orig_buffs = nil
            saved.ntp_created_stack, saved.ntp_created_proc = nil, nil
        end,
    },

    -- ============================================================
    -- Mercenary: Blade Barrier — 0.5%/stack DR, 60 stacks, -10 per hit
    -- ============================================================
    -- Vanilla `markus_mercenary_passive_defence_on_proc` (row 5 col 2) grants
    -- -25% DR for 6s on proc, no stacking. Rework swaps the entire payload:
    -- register stacking buff (`crt_merc_blade_barrier_stack`, -0.5%/stack,
    -- max 60, no refresh), an on-kill proc (`crt_merc_blade_barrier_proc`),
    -- and a stack-remover that strips TEN stacks per damage taken via the
    -- kerillian-shade `remove_buff_stack_data` pattern with num_stacks=10.
    rework_es_mercenary_blade_barrier_60x_minus_10_on_hit = {
        character = "markus",
        career    = "es_mercenary",
        -- issue 425: the on-kill stack add rides rpc_add_buff; gated on peer
        -- parity + wire-safe proc wrapper. (The remover is remove_buff_stack
        -- with server_controlled=false -- local-only, wire-safe.)
        network_unsafe = true,
        patches   = {},
        custom_apply = function(saved)
            if not BuffTemplates or not Talents or not TalentIDLookup then return end
            _crt_ensure_wire_safe_funcs()
            if BuffTemplates.crt_merc_blade_barrier_stack == nil or BuffTemplates.crt_merc_blade_barrier_stack._crt_pending then
                BuffTemplates.crt_merc_blade_barrier_stack = {
                    buffs = {
                        {
                            stat_buff  = "damage_taken",
                            multiplier = -0.005,
                            max_stacks = 60,
                            name       = "crt_merc_blade_barrier_stack",
                        },
                    },
                }
                saved.bb_created_stack = true
            end
            if BuffTemplates.crt_merc_blade_barrier_proc == nil or BuffTemplates.crt_merc_blade_barrier_proc._crt_pending then
                BuffTemplates.crt_merc_blade_barrier_proc = {
                    buffs = {
                        {
                            buff_func  = "crt_wire_safe_add_buff",
                            buff_to_add = "crt_merc_blade_barrier_stack",
                            event       = "on_kill",
                            name        = "crt_merc_blade_barrier_proc",
                        },
                    },
                }
                saved.bb_created_proc = true
            end
            if BuffTemplates.crt_merc_blade_barrier_remover == nil or BuffTemplates.crt_merc_blade_barrier_remover._crt_pending then
                BuffTemplates.crt_merc_blade_barrier_remover = {
                    buffs = {
                        {
                            buff_func = "remove_buff_stack",
                            event     = "on_damage_taken",
                            name      = "crt_merc_blade_barrier_remover",
                            remove_buff_func = "remove_buff_stack",
                            remove_buff_stack_data = {
                                {
                                    buff_to_remove    = "crt_merc_blade_barrier_stack",
                                    num_stacks        = 10,
                                    server_controlled = false,
                                },
                            },
                        },
                    },
                }
                saved.bb_created_remover = true
            end
            local lookup = TalentIDLookup["markus_mercenary_passive_defence_on_proc"]
            if lookup then
                local talent = Talents[lookup.hero_name] and Talents[lookup.hero_name][lookup.talent_id]
                if talent and talent.buffs then
                    saved.bb_orig_buffs = {}
                    for i, b in ipairs(talent.buffs) do saved.bb_orig_buffs[i] = b end
                    talent.buffs = { "crt_merc_blade_barrier_proc", "crt_merc_blade_barrier_remover" }
                end
            end
        end,
        custom_restore = function(saved)
            if Talents and TalentIDLookup and saved.bb_orig_buffs then
                local lookup = TalentIDLookup["markus_mercenary_passive_defence_on_proc"]
                if lookup then
                    local talent = Talents[lookup.hero_name] and Talents[lookup.hero_name][lookup.talent_id]
                    if talent then talent.buffs = saved.bb_orig_buffs end
                end
            end
            if BuffTemplates then
                if saved.bb_created_stack   then BuffTemplates.crt_merc_blade_barrier_stack = _crt_make_stub() end
                if saved.bb_created_proc    then BuffTemplates.crt_merc_blade_barrier_proc = _crt_make_stub() end
                if saved.bb_created_remover then BuffTemplates.crt_merc_blade_barrier_remover = _crt_make_stub() end
            end
            saved.bb_orig_buffs = nil
            saved.bb_created_stack, saved.bb_created_proc, saved.bb_created_remover = nil, nil, nil
        end,
    },

    -- ============================================================
    -- Waystalker: Fervent Huntress → flat passive +10% movement speed
    -- ============================================================
    -- Like Drakira's: target the conditional movespeed talent
    -- `kerillian_waywatcher_movement_speed_on_special_kill` (level 25, +15% MS
    -- for 10s on elite/special kill) and replace its payload with a permanent
    -- +10% MS buff via the apply_movement_buff pattern.
    rework_we_waywatcher_fervent_huntress_passive_ms = {
        character = "kerillian",
        career    = "we_waywatcher",
        patches   = {},
        custom_apply = function(saved)
            if not BuffTemplates then return end
            if BuffTemplates.crt_waywatcher_fervent_huntress_passive == nil or BuffTemplates.crt_waywatcher_fervent_huntress_passive._crt_pending then
                BuffTemplates.crt_waywatcher_fervent_huntress_passive = {
                    buffs = {
                        {
                            apply_buff_func  = "apply_movement_buff",
                            remove_buff_func = "remove_movement_buff",
                            path_to_movement_setting_to_modify = { "move_speed" },
                            multiplier = 1.10,
                            max_stacks = 1,
                            name = "crt_waywatcher_fervent_huntress_passive",
                        },
                    },
                }
                saved.fervent_created = true
            end
            if Talents and TalentIDLookup then
                local lookup = TalentIDLookup["kerillian_waywatcher_movement_speed_on_special_kill"]
                if lookup then
                    local talent = Talents[lookup.hero_name] and Talents[lookup.hero_name][lookup.talent_id]
                    if talent and talent.buffs then
                        saved.fervent_orig_buffs = {}
                        for i, b in ipairs(talent.buffs) do saved.fervent_orig_buffs[i] = b end
                        talent.buffs = { "crt_waywatcher_fervent_huntress_passive" }
                    end
                end
            end
        end,
        custom_restore = function(saved)
            if Talents and TalentIDLookup and saved.fervent_orig_buffs then
                local lookup = TalentIDLookup["kerillian_waywatcher_movement_speed_on_special_kill"]
                if lookup then
                    local talent = Talents[lookup.hero_name] and Talents[lookup.hero_name][lookup.talent_id]
                    if talent then talent.buffs = saved.fervent_orig_buffs end
                end
            end
            if saved.fervent_created and BuffTemplates then
                BuffTemplates.crt_waywatcher_fervent_huntress_passive = _crt_make_stub()
            end
            saved.fervent_orig_buffs, saved.fervent_created = nil, nil
        end,
    },
}

-- ============================================================
-- Hook: per-career suppression of the no_random_crits perk
-- ============================================================
-- The Zealot (Smite) and Mercenary (Hellborg's Tutelage) "crit every 5 hits"
-- talents both attach the perk { "no_random_crits" }. ActionUtils.is_critical_strike
-- short-circuits the chance roll to false when this perk is present.
--
-- The hook differentiates by `self._career_name`: each rework toggle only
-- suppresses the perk for its own career, so Zealot's setting doesn't lift
-- Mercenary's restriction and vice versa. Both hooks idempotently re-read
-- mod:get() on every call, so toggling takes effect on the next attack.
mod:hook("TalentExtension", "has_talent_perk", function(func, self, perk)
    if perk == "no_random_crits" then
        local career = self._career_name
        if career == "wh_zealot" and mod:get("rework_wh_zealot_smite_random_crits") then
            return false
        end
        if career == "es_mercenary" and mod:get("rework_es_mercenary_hellborgs_tutelage") then
            return false
        end
    end
    return func(self, perk)
end)

-- ============================================================
-- Hook: Hellborg's Tutelage random crit-chance reduction
-- ============================================================
-- When the rework is active and the player is on Mercenary with Hellborg's
-- Tutelage (`markus_mercenary_crit_count`) selected, subtract
-- _HELLBORGS_CRIT_PENALTY from the final crit chance after vanilla buffs run.
-- The has_talent_perk hook above lifts the hard-zero short-circuit; this hook
-- supplies the trade-off (a smaller pool of random crits instead of none).
--
-- ActionUtils is a plain global table, so use table-form hooking per
-- CLAUDE.md hooking rules and docs/engine/10 ("plain-table target: hook at file
-- load, not lazily"). Table-form can't hook a nil target, so the presence guard
-- stays; in practice the helpers file loads at game boot, long before any VMF
-- mod, so this installs every session. Issue 507: to catch a future load-order
-- shift that would make ActionUtils absent at crt load (silent feature-loss --
-- the hook would just be skipped), we record whether it installed. The
-- /crt_regression_test check `crt_hellborgs_crit_hook_installed` fails loudly if
-- this marker is ever false, and the else-branch logs the loss at runtime.
if ActionUtils and ActionUtils.get_critical_strike_chance then
    mod:hook(ActionUtils, "get_critical_strike_chance", function(func, unit, action, overrides)
        local chance = func(unit, action, overrides)
        if not mod:get("rework_es_mercenary_hellborgs_tutelage") then
            return chance
        end
        local talent_ext = ScriptUnit.has_extension(unit, "talent_system")
        if not talent_ext or talent_ext._career_name ~= "es_mercenary" then
            return chance
        end
        if not talent_ext:has_talent("markus_mercenary_crit_count") then
            return chance
        end
        local reduced = chance - _HELLBORGS_CRIT_PENALTY
        if reduced < 0 then reduced = 0 end
        return reduced
    end)
    mod._crt_hellborgs_crit_hook_installed = true
else
    mod._crt_hellborgs_crit_hook_installed = false
    pcall(printf, "[crt] WARNING ActionUtils.get_critical_strike_chance unavailable at load; Hellborg's Tutelage crit-chance reduction is INACTIVE this session (load-order shift)")
end

-- ============================================================
-- Hook: _G.Localize override for Hellborg's Tutelage description
-- ============================================================
-- The vanilla talent description text is rendered through Localize() and then
-- post-formatted by UIUtils.format_localized_description with the talent's
-- `description_values`. Mercenary crit_count has one description value
-- (buff_on_stacks = 5), so the override string takes one %d slot. Literal
-- percent signs MUST be `%%` because the result is re-fed through string.format
-- — a bare `%` becomes "[Invalid String Format]". See
-- feedback_vt2_localize_string_format_pipeline.md.
local _HELLBORGS_DESC_OVERRIDE =
    "Critical Strike every %d melee hits. Random Critical Strike chance reduced by 10%%."

-- ============================================================
-- Talent description text overrides (centralised Localize hook)
-- ============================================================
-- When a rework toggle is active, the vanilla talent description in the
-- inventory tooltip should reflect the NEW mechanic, not the vanilla one.
-- VT2 reads `Localize("<talent_name>_desc")` for the text, then formats it
-- via string.format with the talent's description_values. So:
--   * Literal `%` MUST be `%%` (else "[Invalid String Format]" - see
--     feedback_vt2_localize_string_format_pipeline.md).
--   * If a vanilla desc uses %s/%d placeholders, replace them with concrete
--     values or keep placeholders that match the rewritten description_values.
-- Single lookup table keyed by `<talent>_desc`; each entry pairs a setting id
-- with a static override string. ALL reworks share the same Localize hook
-- below (per `feedback_vmf_hook_safe_no_chain.md` two hooks on _G.Localize
-- would silently shadow).
local CRT_DESC_OVERRIDES = {
    -- ------ Universal ------
    ["markus_mercenary_crit_count_desc"] = {
        setting = "rework_es_mercenary_hellborgs_tutelage",
        text = _HELLBORGS_DESC_OVERRIDE,
    },
    -- ------ Bardin: Ranger Veteran ------
    ["bardin_ranger_reduced_damage_taken_headshot_desc"] = {
        setting = "rework_dr_ranger_exuberance_stacking_dr",
        text = "Ranged headshots grant -6%% damage taken per stack, stacking up to 5x for 7 seconds. One stack per shot regardless of how many enemies it hits. Taking damage removes one stack.",
    },
    -- ------ Bardin: Slayer ------
    ["bardin_slayer_passive_stacking_damage_desc"] = {
        setting = "rework_dr_slayer_trophy_hunter_30_stacks_bundle",
        text = "Trophy Hunter: melee hits grant +1%% damage per stack, stacking up to 30x. Each stack lasts 2 seconds.",
    },
    -- ------ Bardin: Outcast Engineer ------
    ["bardin_engineer_power_on_max_pump_desc"] = {
        setting = "rework_dr_engineer_full_head_of_steam_4pct",
        text = "Full Head of Steam: +4%% attack speed per pump stack while at maximum pump.",
    },
    -- Leading Shots (replaces Ingenious Ordnance). The talent UI resolves the
    -- title + description via the GLOBAL Localize, which does NOT see crt's
    -- _localization.lua keys (VMF mod-loc scope) — so the talent's
    -- display_name/description keys must be supplied HERE, through the shared
    -- _G.Localize hook, like every other rework. The "4" is hardcoded (no %s) to
    -- match the other entries and skip the string.format path entirely.
    -- See TALENT_TEXT_RENDERING.md for the full mechanism.
    ["crt_engineer_leading_shots_name"] = {
        setting = "rework_dr_engineer_leading_shots",
        text = "Leading Shots",
    },
    ["crt_engineer_leading_shots_desc"] = {
        setting = "rework_dr_engineer_leading_shots",
        text = "Every 4 ranged attacks (including the Crank Gun), your next ranged attack is a guaranteed critical hit.",
    },
    -- ------ Kruber: Huntsman ------
    ["markus_huntsman_passive_crit_aura_desc"] = {
        setting = "rework_es_huntsman_crit_aura_unlimited_range",
        text = "Huntsman grants +5%% Critical Strike Chance to all allies in the party at unlimited range.",
    },
    -- ------ Kruber: Foot Knight ------
    ["markus_knight_passive_block_cost_aura_desc"] = {
        setting = "rework_es_knight_protective_presence_10m_rock_20m",
        text = "Rock of the Reickland: extends Protective Presence aura range to 20 meters (base aura is now 10m).",
    },
    ["markus_knight_free_pushes_on_block_desc"] = {
        setting = "rework_es_knight_counter_punch_stagger_stack",
        text = "Counter-Punch: each successful block grants +30%% stagger power, stacking up to 5x. Each stack lasts 5 seconds.",
    },
    ["markus_knight_wide_charge_desc"] = {
        setting = "rework_es_knight_valiant_charge_great_foes_45s_battering_ram_30s",
        text = "Battering Ram: Valiant Charge is wider and refunds 1/3 of its 45-second cooldown so the effective cooldown returns to 30 seconds.",
    },
    -- ------ Kruber: Mercenary ------
    ["markus_mercenary_passive_defence_on_proc_desc"] = {
        setting = "rework_es_mercenary_blade_barrier_60x_minus_10_on_hit",
        text = "Blade Barrier: -0.5%% damage taken per kill, stacking up to 60x (-30%% at cap). Taking damage removes 10 stacks.",
    },
    ["markus_mercenary_passive_improved_desc"] = {
        setting = "rework_es_mercenary_enhanced_training_tiered",
        text = "Enhanced Training: hitting 2 / 3 / 4 enemies with a melee attack grants 2 / 3 / 4 stacks of +5%% attack speed for 6 seconds (up to +20%%). Hitting fewer than 2 grants no bonus.",
    },
    -- ------ Kruber: Grail Knight ------
    ["markus_questing_knight_kills_buff_power_stacking_desc"] = {
        setting = "rework_es_questingknight_virtue_of_ideal_3pct_per_kill",
        text = "Virtue of the Ideal: each enemy killed grants +3%% power, stacking up to 10x. Each stack lasts 10 seconds independently.",
    },
    ["markus_questing_knight_parry_increased_power_desc"] = {
        setting = "rework_es_questingknight_virtue_of_discipline_double_parry",
        text = "Virtue of Discipline: doubles your parry timing window (0.5s to 1.0s). No power bonus.",
    },
    ["markus_questing_knight_ability_buff_on_kill_desc"] = {
        setting = "rework_es_questingknight_virtue_of_impetuous_buffed",
        text = "Virtue of the Impetuous Knight: killing an enemy grants +20%% movement speed, +20%% attack speed, and +20%% power for 20 seconds.",
    },
    -- ------ Kerillian: Waystalker ------
    ["kerillian_waywatcher_attack_speed_on_ranged_headshot_desc"] = {
        setting = "rework_we_waywatcher_drakiras_alacrity_passive_as",
        text = "Drakira's Alacrity: gain a permanent +10%% attack speed while this talent is selected. No trigger required.",
    },
    ["kerillian_waywatcher_movement_speed_on_special_kill_desc"] = {
        setting = "rework_we_waywatcher_fervent_huntress_passive_ms",
        text = "Fervent Huntress: gain a permanent +10%% movement speed while this talent is selected. No trigger required.",
    },
    ["kerillian_waywatcher_projectile_ricochet_desc"] = {
        setting = "rework_we_waywatcher_ricochet_no_ff_5_bounces",
        text = "Ricochet: Career Skill arrows bounce to up to 5 additional targets and never trigger friendly fire on bounce.",
    },
    ["kerillian_waywatcher_activated_ability_restore_ammo_on_career_skill_special_kill_desc"] = {
        setting = "rework_we_waywatcher_kurnous_reward_5pct",
        text = "Kurnous' Reward: Career Skill restores 5%% of maximum ammunition for every Special or Elite it kills.",
    },
    -- ------ Kerillian: Shade ------
    ["kerillian_shade_activated_ability_phasing_desc"] = {
        setting = "rework_we_shade_hungry_wind_buffed",
        text = "Hungry Wind: after exiting stealth, gain +20%% movement speed and +20%% power for 20 seconds.",
    },
    -- ------ Victor: Zealot ------
    ["victor_zealot_passive_increased_damage_desc"] = {
        setting = "rework_wh_zealot_fiery_faith_1pct_per_5_hp_max_30",
        text = "Fiery Faith: gain +1%% power for every 5 health missing, stacking up to 30 times (+30%% maximum at full damage).",
    },
    ["victor_zealot_attack_speed_on_health_percent_desc"] = {
        setting = "rework_wh_zealot_castigate_4pct_as_per_fiery_faith",
        text = "Castigate: gain +4%% attack speed for every Fiery Faith stack, up to a maximum of +20%%.",
    },
    ["victor_zealot_passive_healing_received_desc"] = {
        setting = "rework_wh_zealot_holy_fortitude_30_max_hp",
        text = "Holy Fortitude: gain +30 maximum health.",
    },
    -- ------ Victor: Bounty Hunter ------
    ["victor_bountyhunter_weapon_swap_buff_desc"] = {
        setting = "rework_wh_bountyhunter_blessed_combat_25_and_passive_melee_reset",
        text = "Blessed Combat: melee hits grant +25%% ranged damage per stack and ranged hits grant +25%% melee damage per stack (max 6 each). Melee kills reset the Blessed Shots cooldown - this effect is innate regardless of which level 20 talent is selected.",
    },
    ["victor_bountyhunter_party_movespeed_on_ranged_crit_desc"] = {
        setting = "rework_wh_bountyhunter_rile_the_mob_movement",
        text = "Rile the Mob: gain a permanent +10%% movement speed while this talent is selected.",
    },
    ["victor_bountyhunter_reload_on_kill_desc"] = {
        setting = "rework_wh_bountyhunter_salvaged_ammo_no_gate_and_passive_reload",
        text = "Salvaged Ammunition: melee Elite kills restore 5%% of maximum ammunition (no out-of-ammo requirement). Melee kills reload your ranged weapon - this is innate regardless of which level 25 talent is selected.",
    },
    ["victor_bountyhunter_stacking_damage_reduction_on_elite_or_special_kill_desc"] = {
        setting = "rework_wh_bountyhunter_job_well_done_passive_and_special_kill_dr",
        text = "Job Well Done: killing a Special grants -5%% damage taken per stack (max 6x). Taking damage removes one stack. The vanilla Elite/Special kill DR is innate across every level 25 talent.",
    },
    ["victor_bountyhunter_activated_ability_reset_cooldown_on_stacks_2_desc"] = {
        setting = "rework_wh_bountyhunter_just_reward_5s_cooldown",
        text = "Just Reward: ranged Critical Strikes refund Career Skill cooldown. Tightened to once every 5 seconds.",
    },
    ["victor_bountyhunter_activated_ability_railgun_desc_2"] = {
        setting = "rework_wh_bountyhunter_double_shotted_damage_double",
        text = "Double-Shotted: in addition to its cooldown refund, activating Career Skill grants +100%% ranged power for 3 seconds (doubles the damage of the next shot).",
    },
    ["victor_bountyhunter_activated_ability_blast_shotgun_desc"] = {
        setting = "rework_wh_bountyhunter_indiscriminate_blast_refund_per_kill",
        text = "Indiscriminate Blast: Career Skill becomes a wide blast and each kill it scores refunds an additional 1%% of cooldown.",
    },
    -- ------ Victor: Warrior Priest ------
    ["victor_priest_6_1_desc"] = {
        setting = "rework_wh_priest_shield_of_faith_10s_110s_cd_plus_unyielding_20s",
        text = "Unyielding Blessing: Shield of Faith lasts an additional 20 seconds (base duration is now 10 seconds; base cooldown is now 110 seconds).",
    },
    ["victor_priest_5_1_desc"] = {
        setting = "rework_wh_priest_prayer_of_vengeance_self_40_others_20",
        text = "Prayer of Vengeance: the Warrior Priest gains +40%% damage versus Monsters; nearby allies gain +20%%.",
    },
    -- ------ Sienna: Battle Wizard ------
    ["sienna_adept_increased_burn_damage_reduced_non_burn_damage_desc"] = {
        setting = "rework_bw_adept_famished_flames_buffed",
        text = "Famished Flames: burning enemies take +150%% damage; non-burning enemies take -30%% damage.",
    },
    ["sienna_adept_power_level_on_full_charge_desc"] = {
        setting = "rework_bw_adept_volcanic_force_doubled",
        text = "Volcanic Force: fully charging a spell increases its power by +100%%.",
    },
    ["sienna_adept_cooldown_reduction_on_burning_enemy_killed_desc"] = {
        setting = "rework_bw_adept_fires_from_ash_1pct_plus_thp",
        text = "Fires from Ash: killing a burning enemy reduces Career Skill cooldown by 1%% and grants 0.5 temporary health.",
    },
    -- ------ Sienna: Necromancer ------
    ["sienna_necromancer_4_3_desc"] = {
        setting = "rework_bw_necromancer_withering_touch_30s",
        text = "Withering Touch: the buff now lasts 30 seconds.",
    },
    ["sienna_necromancer_4_2_desc"] = {
        setting = "rework_bw_necromancer_malediction_5_souls",
        text = "Malediction of Nagash: 5 soul stacks trigger a guaranteed Critical Strike.",
    },
    ["sienna_necromancer_2_1_desc"] = {
        setting = "rework_bw_necromancer_vanhels_per_skeleton_as",
        text = "Vanhel's Danse Macabre: gain +2%% attack speed for every skeleton currently raised, up to a maximum of +24%% (12 stacks).",
    },
    ["sienna_necromancer_5_1_desc"] = {
        setting = "rework_bw_necromancer_death_ascendant_10s",
        text = "Death Ascendant: cooldown regeneration buff stacks now last 10 seconds.",
    },
    ["sienna_necromancer_6_1_desc"] = {
        setting = "rework_bw_necromancer_army_of_dead_buffed",
        text = "Army of the Dead: Career Skill cooldown is halved (55 seconds) and the extra skeletons last 40 seconds before despawning.",
    },
    -- ------ Sienna: Unchained ------
    ["sienna_unchained_activated_ability_fire_aura_desc"] = {
        setting = "rework_bw_unchained_wildfire_burst_and_radius",
        text = "Wildfire: Career Skill explosion radius increased by +25%% and initial burst damage increased by +50%%.",
    },
    -- Numb to Pain. NOTE: key is the talent's `description` FIELD
    -- (sienna_unchained_reduced_damage_taken_after_venting_desc_2), which
    -- UIUtils.get_talent_description Localizes -- NOT <talent_name>_desc. The old
    -- entry keyed "..._venting_2_desc" was DEAD (wrong key); fixed here + retext to
    -- the v0.3.36 rework.
    ["sienna_unchained_reduced_damage_taken_after_venting_desc_2"] = {
        setting = "rework_bw_unchained_numb_to_pain_4x_burn_kill_lose_on_hit",
        text = "Numb to Pain: per Unstable Strength stack, -6%% damage taken AND -12%% overcharge generated by Blood Magic (-5%%/-10%% with the Unstable Strength rescale active).",
    },
    ["sienna_unchained_reduced_overcharge_desc"] = {
        setting = "rework_bw_unchained_natural_talent_ranged",
        text = "Natural Talent: +6%% ranged power per Unstable Strength stack (5%% with the Unstable Strength rescale active).",
    },
    ["sienna_unchained_exploding_burning_enemies_desc"] = {
        setting = "rework_bw_unchained_chain_reaction_ignite",
        text = "Chain Reaction: killing a burning enemy triggers an explosion that staggers and sets nearby enemies on fire.",
    },
    ["sienna_unchained_activated_ability_power_on_enemies_hit_desc"] = {
        setting = "rework_bw_unchained_fuel_for_the_fire_vent",
        text = "Fuel for the Fire: enemies hit by your Career Skill take increased damage, and your Career Skill now clears only 25%% of your overcharge instead of all of it.",
    },
    -- Flame Unending REPLACES Abandon in the lvl-25 slot. The talent has no
    -- display_name field, so the title resolves via Localize(name) -- override the
    -- name key too. Abandon itself becomes innate (shown as a passive perk).
    ["sienna_unchained_health_to_ult"] = {
        setting = "rework_bw_unchained_abandon_innate_flame_unending",
        text = "Flame Unending",
    },
    ["sienna_unchained_health_to_ult_desc"] = {
        setting = "rework_bw_unchained_abandon_innate_flame_unending",
        text = "Flame Unending: -6%% Career Skill cooldown per Unstable Strength stack (-5%% with the Unstable Strength rescale active). Abandon is now part of your base kit.",
    },
    -- Abandon, shown as a passive perk (appended to PassiveAbilitySettings.bw_3.perks
    -- by the rework's custom_apply) while #3 is active.
    ["crt_abandon_perk_name"] = {
        setting = "rework_bw_unchained_abandon_innate_flame_unending",
        text = "Abandon",
    },
    ["crt_abandon_perk_desc"] = {
        setting = "rework_bw_unchained_abandon_innate_flame_unending",
        text = "Abandon: your Career Skill cooldown is reduced based on your current overcharge.",
    },
}

mod:hook(_G, "Localize", function(func, key, ...)
    if type(key) == "string" then
        local entry = CRT_DESC_OVERRIDES[key]
        if entry and mod:get(entry.setting) then
            return entry.text
        end
    end
    return func(key, ...)
end)

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

-- ============================================================
-- Hook: Zealot ability converts permanent → temporary health
-- ============================================================
-- When the toggle is on, every Zealot ability activation (Holy Fervour) moves
-- the player's current permanent (green) HP into temporary (white) HP. Uses
-- vanilla `PlayerUnitHealthExtension.convert_to_temp`, which self-routes:
--   * server  → mutates GameSession fields directly
--   * client  → sends `rpc_request_convert_temp` to the server, which calls
--               the server-side convert and the result replicates back.
-- Server-side `convert_to_temp` clamps via `math.min(current_health, amount)`,
-- so passing the read-back permanent value is safe (no overflow, no negative).
-- Existing THP is preserved (the field is added to, not overwritten).
--
-- hook_safe on `_run_ability` runs after vanilla has fired the ability buffs
-- and lunge — the conversion lands during the post-activation frame, so the
-- ignore-death talent (`victor_zealot_activated_ability_ignore_death`) is
-- already up if the player has it.
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
            if template and template.buffs and template.buffs[1] then
                template.buffs[1][entry.field] = entry.old_value
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
            if def.network_unsafe and not parity_ok then
                parity_skipped = parity_skipped or {}
                parity_skipped[#parity_skipped + 1] = setting_id
            else
                local saved = {}
                for _, patch in ipairs(def.patches) do
                    local template = BuffTemplates[patch.buff]
                    if template and template.buffs and template.buffs[1] then
                        saved[#saved + 1] = {
                            buff      = patch.buff,
                            field     = patch.field,
                            old_value = template.buffs[1][patch.field],
                        }
                        template.buffs[1][patch.field] = patch.value
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
        pcall(printf, "[crt:425] parity gate: %d networked rework(s) held at vanilla (a lobby peer lacks crt): %s",
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
            if template and template.buffs and template.buffs[1] then
                template.buffs[1][entry.field] = entry.old_value
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

-- ============================================================
-- Issue 425: hot-join replay filter (sender-side, UNCONDITIONAL)
-- ============================================================
-- BuffSystem.hot_join_sync (buff_system.lua:66-97) replays EVERY entry in
-- server_controlled_buffs to a joining peer via rpc_add_buff, encoding
-- NetworkLookup.buff_templates[template_name] at :87. That replay fires during
-- the join handshake, BEFORE any parity ack can exist for the joiner, so a
-- non-crt joiner would decode a crt_* index and fatal instantly -- no gate that
-- reacts to the roster can win that race. Sender-side filter instead: hide
-- crt_* entries from the one replay pass. A crt-running joiner merely misses
-- the replayed crt stacks; the wire-safe driver strips + re-adds them when
-- parity re-establishes (broadcast reaches the joiner), so state self-heals.
-- Pre-flight (NON-NEGOTIABLE 8): grep confirms crt has no other hook on
-- BuffSystem (career_tweaker mod-wide, 2026-07-11).
mod:hook("BuffSystem", "hot_join_sync", function(func, self, peer_id)
    if not self.is_server then
        return func(self, peer_id)
    end
    -- Filter predicate: the mod-registered-name registry (covers tourney's
    -- vanilla-prefixed registrations) plus the crt_ prefix as belt-and-
    -- suspenders for any name registered after this module loaded.
    local registry = mod._crt_mod_registered_buff_names
    local stashed = {}
    pcall(function()
        for _, data in pairs(self.server_controlled_buffs) do
            for sid, bdata in pairs(data) do
                local n = bdata and bdata.template_name
                if type(n) == "string" and ((registry and registry[n]) or n:sub(1, 4) == "crt_") then
                    -- clearing an existing key mid-pairs is legal in Lua 5.1
                    stashed[#stashed + 1] = { data = data, sid = sid, bdata = bdata }
                    data[sid] = nil
                end
            end
        end
    end)
    -- pcall the wrapped sync so the restore below is UNCONDITIONAL -- a throw
    -- mid-replay must not leave the stashed entries permanently hidden (they
    -- would orphan their stacks and dodge later removal). Rethrow afterwards to
    -- preserve vanilla failure semantics.
    local ok, err = pcall(func, self, peer_id)
    for i = 1, #stashed do
        local s = stashed[i]
        s.data[s.sid] = s.bdata
    end
    if #stashed > 0 then
        pcall(printf, "[crt:425] hot-join filter: withheld %d mod buff(s) from replay to joining peer %s (their client may not resolve modded indices)",
            #stashed, tostring(peer_id))
    end
    if not ok then
        error(err, 0)
    end
end)

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
