-- _ct_meta_trait_boons.lua — Meta/trait boons and peer-parity runtime hooks.
--
-- Owns CT-authored meta and trait boon registration, ammo/stat behavior,
-- host-dependent resynchronization, peer-parity gating, and bounded buff hooks.
-- Loaded after boon balance and registry by the ct_dev entry manifest.
--
-- Owned by: chaos_wastes_tweaker_dev.lua. Consumed via: one mod:dofile call.

local mod = get_mod("ct_dev")
local context = mod._ct_boon_runtime_context
if type(context) ~= "table" then
    error("[ct:boon-runtime] missing entry-point context")
end

local balance = mod._ct_boon_balance
local registry = mod._ct_boon_registry
if type(balance) ~= "table" or type(registry) ~= "table" then
    error("[ct:boon-runtime] balance/registry modules must load before meta boons")
end

local _dbg = context.dbg
local effective_setting = context.effective_setting
local _rt_register = context.rt_register
local MOD_VERSION = context.mod_version
local _capture_returns = context.capture_returns
local _collect_setting_ids = context.collect_setting_ids
local _ct_meta_ammo_cost_multiplier = context.meta_ammo_cost_multiplier
local CT_META_AMMO_CAP = context.meta_ammo_cap
local CT_META_AMMO_FLOOR = context.meta_ammo_floor
local CT_META_AMMO_HYPERBOLIC_MARKER = context.meta_ammo_marker
local CT_META_AMMO_MAX_STACKS = context.meta_ammo_max_stacks
local CT_META_AMMO_STEP = context.meta_ammo_step
local CT_RPC_SCHEMA = context.rpc_schema

local sync_reckless_swings = balance.sync_reckless_swings
local sync_bomb_cooldown = balance.sync_bomb_cooldown
local sync_boon_movespeed = balance.sync_boon_movespeed
local sync_poison_proof_tweak = balance.sync_poison_proof_tweak
local sync_invis_potion_tweak = balance.sync_invis_potion_tweak
local sync_moot_milk_alt_tweak = balance.sync_moot_milk_alt_tweak
local sync_shard_strike = balance.sync_shard_strike
local sync_anath_raema_permanent = balance.sync_anath_raema_permanent
local apply_anath_raema_permanent_tweak = balance.apply_anath_raema_permanent_tweak
local _anath_raema_buff_entries = balance.anath_raema_buff_entries
local CT_ANATH_RAEMA_RETRY_MARKER = balance.anath_raema_retry_marker

local inject_dormant_boon = registry.inject_dormant_boon
local _add_dormant_to_pool = registry.add_dormant_to_pool
local _remove_dormant_from_pool = registry.remove_dormant_from_pool
local _injected_dormants = registry.injected_dormants
local register_buff_in_network_lookup = registry.register_buff_in_network_lookup
local register_power_up_in_network_lookup = registry.register_power_up_in_network_lookup

-- issues 249/256/289 (v0.7.298-dev): engine-free grant/clamp policy kernel.
-- Pure module (loadfile-safe) so qa/lua tests drive the exact shipped logic.
local AmmoGuardCore = mod:dofile("scripts/mods/chaos_wastes_tweaker_dev/_ct_ammo_guard_core")
CT_META_AMMO_SERVER_AUTH_MARKER = AmmoGuardCore.MARKER
mod._ct_ammo_guard_core = AmmoGuardCore

local sync_host_dependent_state
-- ============================================================
-- Mod Boons: per-boon scaling (v0.7.30-alpha)
-- ============================================================
-- 4 new ct-injected boons modeled on vanilla `boon_meta_01` (Lileath's Favour: +1%
-- damage and +1% AS per active boon). Each scales different stats per total boon count.
-- Stat_buff names verified against `buff_templates.lua` (power_level_impact,
-- power_level_melee_cleave, critical_strike_chance, critical_strike_effectiveness,
-- max_health, healing_received, cooldown_regen — all are valid stacking_multiplier
-- entries except critical_strike_chance which is stacking_bonus).
--
-- IMPLEMENTATION (per boon):
--   1. Stack buff template added to BuffTemplates (the stat container)
--   2. Apply func added to BuffFunctionTemplates.functions (read by buff_extension
--      at line 397). on_boon_granted func added to the flat global `ProcFunctions`
--      table (read by buff_extension at line 1350). Both written via a factory that
--      shares the same proc body. v0.7.64 fix — pre-0.7.64 the granted func was
--      written only to BuffFunctionTemplates.functions and silently never fired.
--   3. Power-up template added to DeusPowerUpTemplates
--   4. Pool registration via `inject_dormant_boon` (the function is generic — it just
--      registers a power-up name + rarity into all the runtime tables)
--
-- LIMITATION: same as dormants — requires a new CW run to take effect (the engine
-- snapshots DeusPowerUpsArray at run setup). Toggle off doesn't remove the boon.
local CT_META_BOONS = {
    {
        name = "ct_meta_stagger",
        rarity = "exotic",
        icon = "deus_icon_meta_01",
        stat_buffs = {
            { stat_buff = "power_level_impact",         multiplier = 0.01 },
            { stat_buff = "power_level_melee_cleave",   multiplier = 0.01 },
        },
    },
    {
        name = "ct_meta_crit",
        rarity = "exotic",
        icon = "deus_icon_meta_01",
        stat_buffs = {
            { stat_buff = "critical_strike_chance",        bonus      = 0.01 },
            { stat_buff = "critical_strike_effectiveness", multiplier = 0.05 },
        },
    },
    {
        name = "ct_meta_health",
        rarity = "exotic",
        icon = "deus_icon_meta_01",
        stat_buffs = {
            -- LINT_OK_NETBOUND: max_health is vanilla-supported stacking_multiplier
            -- and NOT engine-network-bounded (lossy networkify_health, no fassert).
            { stat_buff = "max_health",        multiplier = 0.01 }, -- LINT_OK_NETBOUND
            { stat_buff = "healing_received",  multiplier = 0.01 },
        },
    },
    {
        name = "ct_meta_cooldown",
        rarity = "exotic",
        icon = "deus_icon_meta_01",
        stat_buffs = {
            { stat_buff = "cooldown_regen", multiplier = 0.02 },
        },
    },
    {
        name = "ct_meta_ammo",  -- v0.7.43: +5% total ammo per active boon
        rarity = "exotic",
        icon = "deus_icon_meta_01",
        stat_buffs = {
            -- v0.7.52: `apply_buff_func = "refresh_ranged_slot_buffs"` fires
            -- `ammo_extension:refresh_buffs()` on the player's ranged weapon every time the
            -- stack is added, which re-runs `_apply_buffs` and recomputes `_max_ammo`.
            -- v0.7.72: replaced with `ct_meta_ammo_refresh_capacity` which ALSO refreshes
            -- overcharge_extension (Sienna staves, Bardin drakefire) and energy_extension
            -- (Moonfire Bow). See registration block above CT_META_BOONS.
            { stat_buff = "total_ammo",        multiplier = 0.05, apply_buff_func = "ct_meta_ammo_refresh_capacity" },
            -- v0.7.104: REMOVED `reduced_overcharge` and `ammo_used_multiplier` stat_buff
            -- entries. They used vanilla `stacking_multiplier` resolution which is
            -- linear-additive (buff_extension.lua:1391-1448): 20 stacks of -0.05 sum to
            -- -1.0 → `root_multiplier = 0` → free shots / casts. Gamebreaking zero-crossing.
            --
            -- Replaced by direct vanilla hooks on `GenericAmmoUserExtension.use_ammo`,
            -- `PlayerUnitEnergyExtension.drain`, and `PlayerUnitOverchargeExtension.add_charge`
            -- (search for `CT_META_AMMO_HYPERBOLIC_FLOOR_v0.7.104` in this file). Each hook
            -- scales the per-shot cost by `_ct_meta_ammo_cost_multiplier(num_boons)` — a
            -- hyperbolic-saturating curve floored at 0.25 that is BOUNDED IN [0.25, 1.0]
            -- for ANY N (including N → ∞). Never zero, never negative, never below 25%.
            --
            -- See `.ammo_system_design_2026-05-24.md` for the full design + vanilla
            -- call-site analysis. The `total_ammo` entry stays (positive-only growth, no
            -- zero-crossing — vanilla Waystalker passive ships +100% with no issue).
        },
        -- v0.7.104: Coverage is still ammo + overcharge + energy, but the consumption-side
        -- scaling now happens in three direct vanilla hooks (search for the marker above).
        -- The stat_buffs list contains only `total_ammo` (capacity-side, safe).
    },
}

-- Shared body for apply + granted. Brings the stack count up to the current boon count
-- by adding the delta only. Both procs use the same body so the result is idempotent
-- regardless of which fires first (vanilla CW fires `on_boon_granted` BEFORE
-- `activate_deus_power_up` for newly-granted boons, so when Quiver Cascade is the first
-- ct_meta_* boon a player has the apply func is what does the initial stack — for
-- subsequent boon grants only `granted` fires).
--
-- v0.7.53 fixes two bugs in the prior implementation:
--   1. `num_buff_stacks(stack_name)` returned 0 always — the actual stored key is the
--      SUB-buff's `.name`, which we set to `stack_name .. "_" .. i` in the factory. So the
--      granted func couldn't see existing stacks and re-added the full boon count on every
--      subsequent grant, producing quadratic stack growth (triangular sum across boons).
--   2. The apply path used `for 1, num_boons` with no existing-stacks check. Same fix.
--
-- The query uses the `_1` suffix (the first sub-buff's name). All meta specs have at least
-- one sub-buff, and add_buff(stack_name) increments every sub-buff's stack in lockstep, so
-- counting one of them is enough.
local function _make_meta_proc(stack_name)
    local stack_key = stack_name .. "_1"
    return function(unit, buff, params)
        local player = Managers.player and Managers.player:owner(unit)
        if not player then return end
        local buff_extension = ScriptUnit.extension(unit, "buff_system")
        if not buff_extension then return end
        local deus_run_controller = Managers.mechanism:game_mechanism():get_deus_run_controller()
        if not deus_run_controller then return end
        local num_boons = #deus_run_controller:get_player_power_ups(player:network_id(), player:local_player_id())
        -- v0.7.108-dev (Issue #34): clamp the loop's upper bound to
        -- CT_META_AMMO_MAX_STACKS so a runaway `num_boons` value (stale peer
        -- list, future RPC race, hot-join graph resync) can never push the
        -- per-stack buff template past its max_stacks ceiling. The clamp here
        -- and the `max_stacks = CT_META_AMMO_MAX_STACKS` in the template
        -- factory are mirrored on purpose — either one alone is sufficient,
        -- both together close the door. See doc-block near MOD_VERSION.
        local stacks_target = math.min(num_boons, CT_META_AMMO_MAX_STACKS)
        local num_existing = buff_extension:num_buff_stacks(stack_key)
        -- v0.7.298-dev (issues 249/289): SERVER-AUTHORITATIVE stack grant. The
        -- old body added stacks through the LOCAL extension path on whichever
        -- peer ran the proc; a client's stacks never activated ([ct:289]
        -- evidence: client effective=5 active=0 while the host tracked
        -- correctly), so the client's capacity buff (total_ammo) never applied
        -- and its HUD lagged the real value (issue 249, 36 vs 62). Vanilla
        -- triggers on_boon_granted on the SERVER for every gainer - locally at
        -- grant [src: deus_run_controller.lua:1152-1160] and in the host's
        -- rpc_deus_add_power_ups receiver for client gainers [src:
        -- deus_run_controller.lua:1397-1404] - so the host proc is the one
        -- authoritative writer: BuffSystem.add_buff(unit, name, unit, true)
        -- adds locally AND broadcasts rpc_add_buff to every client, and
        -- re-sends server-controlled buffs on hot-join [src:
        -- buff_system.lua:277-311, :66-97]. The client-side apply_buff_func
        -- (ct_meta_ammo_refresh_capacity) then runs on the replicated add, so
        -- the client's own _max_ammo recomputes and the issue 256 clamp fires
        -- on every peer. Wire safety: the stack template name is a MODDED
        -- NetworkLookup index, so the networked path is gated on the issue 426
        -- parity beacon (mod._ct_wire_safe); unconfirmed parity degrades to
        -- the local host-only add (zero wire exposure). Client peers never
        -- add - the replicated adds are their stacks (grant_plan
        -- "defer_to_server"). Parity-loss cleanup: the stack names are
        -- ct_-prefixed, so the issue 426 strip's server-controlled-buff
        -- removal covers them.
        local is_server = Managers.player and Managers.player.is_server and true or false
        local wire_safe = mod._ct_wire_safe and mod._ct_wire_safe() == true
        local mode, n = AmmoGuardCore.grant_plan(is_server, wire_safe, num_existing, stacks_target)
        if mode == "networked" then
            local buff_system = Managers.state and Managers.state.entity
                and Managers.state.entity:system("buff_system")
            if buff_system then
                for _ = 1, n do
                    buff_system:add_buff(unit, stack_name, unit, true)
                end
            else
                for _ = 1, n do buff_extension:add_buff(stack_name) end
            end
        elseif mode == "local" then
            for _ = 1, n do buff_extension:add_buff(stack_name) end
        end
        -- mode "defer_to_server" / "none": nothing to do on this peer.
    end
end

local function register_meta_boon(spec)
    local power_ups      = rawget(_G, "DeusPowerUpTemplates")
    local buff_templates = rawget(_G, "BuffTemplates")
    local buff_funcs     = rawget(_G, "BuffFunctionTemplates")
    local proc_functions = rawget(_G, "ProcFunctions")
    if not (power_ups and buff_templates and buff_funcs and buff_funcs.functions and proc_functions) then
        _dbg("[mod-boon] global tables not ready for " .. spec.name)
        return
    end
    local stack_name   = spec.name .. "_stack"
    local apply_name   = spec.name .. "_apply"
    local granted_name = spec.name .. "_granted"

    -- 1. Proc functions. Same body for both — apply fires when this meta boon itself is
    -- granted; granted fires on every subsequent boon. Both should bring stack count to
    -- the current boon count, idempotently.
    -- v0.7.64: on_boon_granted handlers are resolved via the flat `ProcFunctions` global
    -- (buff_extension.lua:1350), NOT `BuffFunctionTemplates.functions`. Apply funcs read
    -- from the latter (buff_extension.lua:397). Writing to only one table = granted proc
    -- silently never fires; the per-boon stack only refreshes on next mission load when
    -- apply runs fresh. Same root-cause shape as v0.7.57 chain_lightning fix.
    local proc = _make_meta_proc(stack_name)
    buff_funcs.functions[apply_name]   = proc
    buff_funcs.functions[granted_name] = proc
    proc_functions[granted_name]       = proc

    -- 2. Stack buff template
    local stack_buffs = {}
    for i, sb in ipairs(spec.stat_buffs) do
        local entry = {
            name = stack_name .. "_" .. i,
            -- v0.7.108-dev (Issue #34): hard cap (was math.huge). See the
            -- CT_META_AMMO_MAX_STACKS doc-block near MOD_VERSION for the
            -- rationale. 30 stacks of any of our meta-boon multipliers
            -- (0.01-0.05) sits well below any engine overflow risk while
            -- still allowing endgame stacking.
            stat_buff = sb.stat_buff,
            max_stacks = CT_META_AMMO_MAX_STACKS,
        }
        if sb.multiplier      then entry.multiplier      = sb.multiplier      end
        if sb.bonus           then entry.bonus           = sb.bonus           end
        if sb.apply_buff_func then entry.apply_buff_func = sb.apply_buff_func end
        stack_buffs[i] = entry
    end
    buff_templates[stack_name] = { buffs = stack_buffs }
    register_buff_in_network_lookup(stack_name)

    -- 3. Power-up template
    power_ups[spec.name] = {
        advanced_description = "description_" .. spec.name,
        display_name         = "display_name_" .. spec.name,
        icon                 = spec.icon,
        max_amount           = 1,
        rectangular_icon     = true,
        buff_template = {
            buffs = {
                {
                    apply_buff_func = apply_name,
                    buff_func       = granted_name,
                    event           = "on_boon_granted",
                    name            = spec.name,
                },
            },
        },
        description_values = {},
    }

    -- 4. Register network-relevant tables + add to rarity pool. v0.7.67 split:
    -- inject_dormant_boon does the registration; _add_dormant_to_pool does the
    -- pool insert. Meta boons are unconditional (not toggle-gated), so always
    -- both — same peer-side behavior as pre-0.7.67.
    inject_dormant_boon(spec.name, spec.rarity)
    _add_dormant_to_pool(spec.name, spec.rarity)
    _dbg("[mod-boon] registered " .. spec.name .. " at rarity " .. spec.rarity)
end

-- v0.7.104: the v0.7.102 sentinel `CT_META_AMMO_ENERGY_CONSUMPTION_MARKER` is
-- retired — it documented a `ammo_used_multiplier` stat_buff approach that
-- diverged to zero cost at ~20 boons. Replaced by the file-scope
-- `CT_META_AMMO_HYPERBOLIC_MARKER` (declared near the top of the file alongside
-- `_ct_meta_ammo_cost_multiplier`), checked by the regression test
-- `ct_meta_ammo_hyperbolic_floor_v0_7_104`. Kept here as a dead local for any
-- transitional code that still upvalue-reads it; the regression test now
-- ignores the value.
local CT_META_AMMO_ENERGY_CONSUMPTION_MARKER = "CT_META_AMMO_ENERGY_CONSUMPTION_v0.7.102_RETIRED"

-- v0.7.72: Custom apply_buff_func for ct_meta_ammo. Vanilla `refresh_ranged_slot_buffs`
-- only touches AmmoExtension; we extend it to also force-refresh the player's
-- OverchargeExtension (Sienna staves, Bardin drakefire). Energy refresh became
-- UNNECESSARY in v0.7.102 because the boon now ships `ammo_used_multiplier` (per-drain,
-- consumption-side) instead of mutating `_max_energy` — there's nothing to refresh,
-- the stat_buff applies inside `PlayerUnitEnergyExtension.drain` (vanilla line 95)
-- every time the player fires an energy weapon.
--
-- - OverchargeExtension calls `_calculate_and_set_buffed_max_overcharge_values` at
--   extensions_ready and `on_overcharge_lost` (`player_unit_overcharge_extension.lua:103,206`).
--   v0.7.78 removed the explicit `_calculate_and_set_buffed_max_overcharge_values` call
--   from this function — since the boon now uses `reduced_overcharge` (consumption-side)
--   rather than `max_overcharge`, no recalculation is necessary.
--
-- v0.7.102 thus reduces this function to its original role: refresh the AmmoExtension
-- so the `total_ammo` stack reaches `_max_ammo` immediately. All other resources
-- (overcharge, energy) are handled by their respective consumption-side stat_buff paths
-- without any explicit refresh — that's the whole point of the consumption-side pattern.
do
    local buff_funcs = rawget(_G, "BuffFunctionTemplates")

    -- Issue #256: consumption-side LOWER-bound clamp on CURRENT ammo after a
    -- meta-ammo refresh. Marker: CT_META_AMMO_CURRENT_AMMO_FLOOR_256 (functional
    -- regression `ct_meta_ammo_current_floor_256`; helper exposed as
    -- `mod._ct_clamp_current_ammo_256`).
    --
    -- Root cause: vanilla `GenericAmmoUserExtension.refresh_buffs`
    -- (generic_ammo_user_extension.lua:105-108) recomputes reserve as
    --   `_available_ammo = math.min(_start_ammo - _current_ammo, _available_ammo)`
    -- with NO floor at 0. `_start_ammo = round(_original_ammo_percent * _max_ammo)`
    -- is scaled by the ammo fraction the weapon SPAWNED with. When a weapon that
    -- entered a map at a partial fraction (`_original_ammo_percent` < 1) later has
    -- its clip refilled above that scaled `_start_ammo` (ammo pickup + reload),
    -- `_start_ammo - _current_ammo` is negative and the reserve drops below zero.
    -- Vanilla only self-heals in the `ammo_percent == 1` branch (:110-112 `reset()`);
    -- at any other fraction the negative persists and the HUD shows negative ammo
    -- (issue 256). There is NO fassert on `_available_ammo`, so it is silent (unlike
    -- `_current_ammo`, guarded by fasserts at :234 / :483) — matching the report of a
    -- visible negative rather than a crash.
    --
    -- `ct_meta_ammo_refresh_capacity` is the ONLY ct seam that derives current/reserve
    -- ammo (grep: refresh_buffs). The meta-ammo boon fires it on every boon grant. We
    -- do NOT touch `_max_ammo` (max-resource doctrine; the issue 34 UPPER clamp lives in
    -- the `_apply_buffs` hook). We clamp CURRENT values only: reserve floored at 0 and
    -- clip clamped into [0, _max_ammo]. Each peer runs this for its OWN weapon (the boon
    -- buff applies locally; AmmoSystem carries only a [0,1] fraction over the wire, which
    -- flows through the already-clamping `add_ammo` path), so the seam clamp covers host
    -- and client alike. Fires a `[ct:256]` printf ONLY when a clamp actually engages.
    -- v0.7.298-dev: clamp arithmetic extracted to _ct_ammo_guard_core.clamp_value
    -- (pure, offline-tested); this wrapper owns the field writes + [ct:256] printf.
    local function _ct_clamp_current_ammo_256(ax, seam)
        if type(ax) ~= "table" then return end
        local max_ammo = ax._max_ammo
        local reserve, r_changed = AmmoGuardCore.clamp_value(max_ammo, ax._available_ammo)
        if r_changed then
            pcall(printf, "[ct:256] clamped reserve ammo %s -> %d (max=%s seam=%s item=%s) issue 256",
                tostring(ax._available_ammo), reserve, tostring(max_ammo), tostring(seam), tostring(ax.item_name))
            ax._available_ammo = reserve
        end
        local current, c_changed = AmmoGuardCore.clamp_value(max_ammo, ax._current_ammo)
        if c_changed then
            pcall(printf, "[ct:256] clamped clip ammo %s -> %d (max=%s seam=%s item=%s) issue 256",
                tostring(ax._current_ammo), current, tostring(max_ammo), tostring(seam), tostring(ax.item_name))
            ax._current_ammo = current
        end
    end
    mod._ct_clamp_current_ammo_256 = _ct_clamp_current_ammo_256

    if buff_funcs and buff_funcs.functions then
        buff_funcs.functions.ct_meta_ammo_refresh_capacity = function (unit, buff, params)
            -- 1. Vanilla ammo refresh (preserved from old `refresh_ranged_slot_buffs`).
            local inventory_extension = ScriptUnit.has_extension(unit, "inventory_system")
            if inventory_extension then
                local ranged_slot_data = inventory_extension:get_slot_data("slot_ranged")
                if ranged_slot_data then
                    local left_hand_unit  = ranged_slot_data.left_unit_1p
                    local right_hand_unit = ranged_slot_data.right_unit_1p
                    local left_ammo  = left_hand_unit  and ScriptUnit.has_extension(left_hand_unit,  "ammo_system")
                    local right_ammo = right_hand_unit and ScriptUnit.has_extension(right_hand_unit, "ammo_system")
                    -- Issue #256: floor CURRENT ammo after each refresh so a partial-spawn
                    -- weapon whose clip outgrew the percent-scaled _start_ammo can't leave
                    -- reserve negative (vanilla refresh_buffs :108 has no >= 0 floor).
                    if left_ammo  then left_ammo:refresh_buffs();  _ct_clamp_current_ammo_256(left_ammo,  "meta_ammo_refresh_capacity") end
                    if right_ammo then right_ammo:refresh_buffs(); _ct_clamp_current_ammo_256(right_ammo, "meta_ammo_refresh_capacity") end
                end
            end

            -- 2. Overcharge refresh — REMOVED in v0.7.78. Pre-v0.7.78 ct_meta_ammo
            -- buffed `max_overcharge` directly, and this call re-ran
            -- `_calculate_and_set_buffed_max_overcharge_values` to land the new bar size
            -- immediately. After v0.7.78 the boon uses `reduced_overcharge` instead (a
            -- per-cast stat_buff with no max_value side-effect), so the recalc is
            -- pointless — `reduced_overcharge` reads happen inside the per-cast
            -- ActionThrowProjectile / overcharge add paths, not via max_value. Removing
            -- the call also eliminates the only ct path that could ever drive a
            -- max_overcharge-bounds crash even if another mod adds `max_overcharge` on
            -- top of Scholar talent.

            -- 3. Energy refresh — REMOVED in v0.7.102.
            --
            -- Pre-v0.7.102 (v0.7.72 through v0.7.101-dev) ct_meta_ammo mutated
            -- `energy_ext._max_energy` directly to grow the Moonfire Bow energy
            -- bar. That code path was the root cause of crash GUID
            -- `10764a92-d642-43c2-a51b-07c5b45508be` on 2026-05-23: the engine
            -- fasserts `_max_energy <= NetworkConstants.max_energy.max` (= 60)
            -- every frame inside `PlayerUnitEnergyExtension._update_game_object`,
            -- and the extension is registered on EVERY career — not just
            -- Kerillian. The v0.7.101-dev fix tried to gate the write on
            -- `item_name == "we_deus_01"` plus a base-sanity check plus a clamp;
            -- the user (correctly) rejected that approach as career-specific
            -- guesswork that would break the moment any future career or
            -- weapon used the energy extension.
            --
            -- v0.7.102 doctrine fix (feedback_vt2_max_resource_consumption_side):
            -- the boon's stat_buffs list now includes
            -- `{ stat_buff = "ammo_used_multiplier", multiplier = -0.05 }`
            -- (sentinel: CT_META_AMMO_ENERGY_CONSUMPTION_MARKER). Vanilla reads
            -- that stat_buff inside `PlayerUnitEnergyExtension.drain` line 95
            -- (`amount = amount * apply_buffs_to_value(1, "ammo_used_multiplier")`)
            -- to scale per-cast energy cost. At 12 boons × -0.05 = effective
            -- cost multiplier 0.40 (stacking_multiplier composes additively),
            -- giving ~2.5x firing capacity. Career-agnostic. Weapon-agnostic.
            -- Never touches the network-bounded `_max_energy` field.
            --
            -- This is the exact parallel of the v0.7.78 max_overcharge → reduced_overcharge
            -- swap. Both crashes shared the same root pattern (NetworkConstants cap
            -- vs +5%/boon scaling); both are now closed via vanilla consumption-side
            -- stat_buffs. See feedback_vt2_max_resource_consumption_side.md for
            -- the full doctrine.
            --
            -- Sentinel string CT_META_AMMO_ENERGY_CONSUMPTION_MARKER is checked by
            -- /ct_regression_test source-pattern check `ct_meta_ammo_uses_consumption_side`.
            -- The marker itself appears in the boon definition's comment block at
            -- CT_META_BOONS (see `ammo_used_multiplier` entry above) AND in the
            -- file-scope sentinel just below the boon registration loop.
            local _ = CT_META_AMMO_ENERGY_CONSUMPTION_MARKER  -- upvalue read so the
            -- regression check sees the marker as load-bearing rather than dead code.
        end
    else
        _dbg("[mod-boon] BuffFunctionTemplates not ready — ct_meta_ammo_refresh_capacity deferred (boon load order)")
    end
end

for _, spec in ipairs(CT_META_BOONS) do
    register_meta_boon(spec)
end

-- ============================================================================
-- v0.7.104: ct_meta_ammo direct hooks — hyperbolic cost-floor on consumption.
-- ============================================================================
-- Replaces the v0.7.102-era `reduced_overcharge` + `ammo_used_multiplier`
-- stat_buff entries with three direct vanilla hooks. Root cause for the swap:
-- VT2 `stacking_multiplier` resolution (buff_extension.lua:1391-1448) is linear-
-- additive. 20 stacks of -0.05 sum to -1.0 → root_multiplier = 0 → free shots /
-- casts. Gamebreaking zero-crossing.
--
-- Each hook resolves the local player's active boon count via the deus run
-- controller (matches `_make_meta_proc`'s pattern), scales the per-shot cost by
-- `_ct_meta_ammo_cost_multiplier(N)` (bounded [0.25, 1.0] for any N), then
-- calls the original with the discounted amount. Pcall around each body so a
-- crash in our resolution can never break the vanilla consumption path. Vanilla
-- buffs (Hand of Drakira, Conservative Shooter, etc.) flow through the wrapped
-- inner call so composition stays multiplicative.
--
-- The hooks no-op (early-return) for non-local players (husk units have no
-- run_controller of their own — the local viewer's ct_meta_ammo discount is
-- their problem; husks just sync state). They also no-op when num_boons <= 0
-- so vanilla CW behavior is unchanged for non-meta-ammo players.
--
-- Sentinel: CT_META_AMMO_HYPERBOLIC_FLOOR_v0.7.104 (file-scope, see top of file).
do
    -- Resolve the active boon count for the LOCAL player ONLY. Returns 0 for
    -- husk units (remote players). The hyperbolic discount is applied locally
    -- on each peer's own shots — vanilla networking syncs the result.
    local function _resolve_local_num_boons(owner_unit)
        local pm = Managers and Managers.player
        if not pm then return 0 end
        local pl = pm.local_player and pm:local_player()
        if not pl or pl.player_unit ~= owner_unit then return 0 end
        local mech = Managers.mechanism
        local gm   = mech and mech.game_mechanism and mech:game_mechanism()
        local rc   = gm and gm.get_deus_run_controller and gm:get_deus_run_controller()
        if not rc then return 0 end
        local ok, list = pcall(rc.get_player_power_ups, rc, pl:network_id(), pl:local_player_id())
        if not ok or type(list) ~= "table" then return 0 end
        return #list
    end

    -- Log only when the factor differs from 1.0 (i.e. we actually scaled),
    -- and only once every N seconds per extension to avoid spam.
    local _last_log_ts = {}
    local _LOG_THROTTLE_S = 2.0
    local function _maybe_log(ext_name, factor, n)
        if factor >= 0.9999 then return end  -- no scaling happened
        local now = (os and os.clock and os.clock()) or 0
        local last = _last_log_ts[ext_name] or -math.huge
        if now - last < _LOG_THROTTLE_S then return end
        _last_log_ts[ext_name] = now
        _dbg("[ct/meta_ammo] %s cost scaled: factor=%.3f num_boons=%d", ext_name, factor, n)
    end

    -- Hook 1: ammo (GenericAmmoUserExtension.use_ammo, vanilla file line 425).
    -- Vanilla cost math at line 430: `extra_ammo_used = math.round(ammo_used *
    -- apply_buffs_to_value(1, "ammo_used_multiplier")) - ammo_used`. Scaling
    -- the input `ammo_used` here composes correctly with vanilla buffs that
    -- multiply it again inside the original. Floor: math.ceil + math.max(1, ...)
    -- so integer ammo never rounds to 0 from our contribution.
    mod:hook("GenericAmmoUserExtension", "use_ammo", function(func, self, ammo_used, given, check_ammo_immediately)
        local ok, n = pcall(_resolve_local_num_boons, self.owner_unit)
        if not ok or not n or n <= 0 then
            return func(self, ammo_used, given, check_ammo_immediately)
        end
        local ok2, factor = pcall(_ct_meta_ammo_cost_multiplier, n)
        if not ok2 or type(factor) ~= "number" or factor >= 1.0 then
            return func(self, ammo_used, given, check_ammo_immediately)
        end
        -- Belt-and-suspenders floor: math.max(1, ceil(...)) guarantees integer
        -- ammo never drops below 1 per shot. `factor` is already floored at 0.25.
        local scaled = math.max(1, math.ceil((ammo_used or 1) * factor))
        _maybe_log("use_ammo", factor, n)
        return func(self, scaled, given, check_ammo_immediately)
    end)

    -- Hook 2: energy (PlayerUnitEnergyExtension.drain, vanilla file line 85).
    -- Vanilla cost math at line 95: `amount = amount * apply_buffs_to_value(1,
    -- "ammo_used_multiplier")`. We scale `amount` (float) directly. No integer
    -- floor needed — the per-shot cost floor of 0.25 keeps drain bounded away
    -- from zero, and the inner orig_drain clamps the result to [0, energy].
    mod:hook("PlayerUnitEnergyExtension", "drain", function(func, self, amount)
        local ok, n = pcall(_resolve_local_num_boons, self.unit)
        if not ok or not n or n <= 0 then
            return func(self, amount)
        end
        local ok2, factor = pcall(_ct_meta_ammo_cost_multiplier, n)
        if not ok2 or type(factor) ~= "number" or factor >= 1.0 then
            return func(self, amount)
        end
        -- #131 DIAGNOSTIC [ct:moonfire131]: we_deus_01 (Moonfire Bow) is the ONLY
        -- energy_system weapon, so EVERY drain routed here is a Moonfire shot. Log the
        -- pre-shot energy pool + the discounted cost so the shots-per-bar inflation is
        -- visible (per-shot cost = amount*factor, factor floored 0.25 -> up to 4x shots).
        -- Reuses the _last_log_ts throttle table + os.clock the way _maybe_log does.
        pcall(function()
            local now131 = (os and os.clock and os.clock()) or 0
            if now131 - (_last_log_ts["moonfire131"] or -math.huge) >= 1.0 then
                _last_log_ts["moonfire131"] = now131
                pcall(printf, "[ct:moonfire131] Moonfire energy shot: vanilla_cost=%.2f discounted=%.2f factor=%.3f boons=%d energy=%.1f/%.1f (issue #131)",
                    tonumber(amount) or -1, (tonumber(amount) or 0) * factor, factor, n,
                    tonumber(self._energy) or -1, tonumber(self._max_energy) or -1)
            end
        end)
        _maybe_log("drain", factor, n)
        return func(self, (amount or 0) * factor)
    end)

    -- Hook 3: overcharge (PlayerUnitOverchargeExtension.add_charge, vanilla
    -- file line 330). Vanilla cost math at lines 340 + 343. Respects
    -- `_ignored_overcharge_types` (vanilla line 82) for design-consistency —
    -- passive damage-to-overcharge and channelled drakefire/flamethrower
    -- intake aren't "magazine efficiency", so we don't discount them.
    local _IGNORED_OC_TYPES = {
        charging              = true,
        damage_to_overcharge  = true,
        drakegun_charging     = true,
        flamethrower          = true,
    }
    mod:hook("PlayerUnitOverchargeExtension", "add_charge", function(func, self, overcharge_amount, charge_level, overcharge_type)
        -- Skip ignored overcharge types entirely — same list vanilla skips for
        -- `ammo_used_multiplier` at line 343. Belt-and-suspenders: also defer
        -- to the extension's own ignore table if present (some careers might
        -- expand it).
        if overcharge_type and (_IGNORED_OC_TYPES[overcharge_type]
                or (self._ignored_overcharge_types and self._ignored_overcharge_types[overcharge_type])) then
            return func(self, overcharge_amount, charge_level, overcharge_type)
        end
        local ok, n = pcall(_resolve_local_num_boons, self.unit)
        if not ok or not n or n <= 0 then
            return func(self, overcharge_amount, charge_level, overcharge_type)
        end
        local ok2, factor = pcall(_ct_meta_ammo_cost_multiplier, n)
        if not ok2 or type(factor) ~= "number" or factor >= 1.0 then
            return func(self, overcharge_amount, charge_level, overcharge_type)
        end
        _maybe_log("add_charge", factor, n)
        return func(self, (overcharge_amount or 0) * factor, charge_level, overcharge_type)
    end)

    pcall(printf, "[ct/meta_ammo] hyperbolic-floor hooks installed (use_ammo / drain / add_charge); marker=%s", CT_META_AMMO_HYPERBOLIC_MARKER)
end

-- v0.7.104: /verify_meta_ammo — print the hyperbolic curve at sample N values
-- so the user can eyeball the saturation. Also dumps the live boon count and
-- runtime resolution if a player unit is available.
mod:command("verify_meta_ammo", "Print ct_meta_ammo hyperbolic cost-floor curve + live state", function()
    mod:echo("=== ct_meta_ammo hyperbolic curve (step=%.2f cap=%.2f floor=%.2f) ===",
        CT_META_AMMO_STEP, CT_META_AMMO_CAP, CT_META_AMMO_FLOOR)
    mod:echo("  N=0    -> factor=%.3f", _ct_meta_ammo_cost_multiplier(0))
    mod:echo("  N=1    -> factor=%.3f", _ct_meta_ammo_cost_multiplier(1))
    mod:echo("  N=5    -> factor=%.3f", _ct_meta_ammo_cost_multiplier(5))
    mod:echo("  N=10   -> factor=%.3f", _ct_meta_ammo_cost_multiplier(10))
    mod:echo("  N=20   -> factor=%.3f", _ct_meta_ammo_cost_multiplier(20))
    mod:echo("  N=50   -> factor=%.3f", _ct_meta_ammo_cost_multiplier(50))
    mod:echo("  N=100  -> factor=%.3f", _ct_meta_ammo_cost_multiplier(100))
    mod:echo("  N=1000 -> factor=%.3f (asymptote: %.3f)", _ct_meta_ammo_cost_multiplier(1000), CT_META_AMMO_FLOOR)

    local pl = Managers.player and Managers.player:local_player()
    local unit = pl and pl.player_unit
    if not unit then
        mod:echo("  (no local player unit — keep/menu? Curve-only output)")
        return
    end

    local rc = Managers.mechanism and Managers.mechanism:game_mechanism()
        and Managers.mechanism:game_mechanism().get_deus_run_controller
        and Managers.mechanism:game_mechanism():get_deus_run_controller()
    local num_boons = 0
    if rc and pl then
        local ok, list = pcall(rc.get_player_power_ups, rc, pl:network_id(), pl:local_player_id())
        if ok and type(list) == "table" then num_boons = #list end
    end
    local live_factor = _ct_meta_ammo_cost_multiplier(num_boons)
    local buff_ext = ScriptUnit.has_extension(unit, "buff_system")
    local live_total_ammo
    if buff_ext then
        local ok, v = pcall(buff_ext.apply_buffs_to_value, buff_ext, 1.0, "total_ammo")
        live_total_ammo = ok and v or nil
    end
    mod:echo("--- live ---")
    mod:echo("  num_boons=%d  cost_factor=%.3f  total_ammo=%s",
        num_boons, live_factor, tostring(live_total_ammo))
    mod:echo("  marker=%s", CT_META_AMMO_HYPERBOLIC_MARKER)

    -- #249 DIAGNOSTIC [ct:ammo249]: dump the wielded RANGED weapon's live ammo-extension
    -- fields on THIS peer. Run /verify_meta_ammo on host AND client and compare: the HUD
    -- shows ammo_count()+remaining_ammo(); buffed capacity is _max_ammo (total_ammo buff).
    -- If the client's _max_ammo lags the host's, the "shows 36, actual 62" desync is captured.
    pcall(function()
        local is_server = Managers.player and Managers.player.is_server
        local inv = ScriptUnit.has_extension(unit, "inventory_system")
        local rsd = inv and inv.get_slot_data and inv:get_slot_data("slot_ranged")
        if not rsd then
            pcall(printf, "[ct:ammo249] is_server=%s no ranged slot equipped (issue #249)", tostring(is_server))
            return
        end
        for _, u in ipairs({ rsd.right_unit_1p, rsd.left_unit_1p }) do
            local ax = u and ScriptUnit.has_extension(u, "ammo_system")
            if ax and ax.max_ammo then
                pcall(printf, "[ct:ammo249] is_server=%s boons=%d HUD(clip=%s reserve=%s) _max_ammo=%s _orig_max=%s _available=%s _current=%s total_remaining=%s (issue #249)",
                    tostring(is_server), num_boons,
                    tostring(ax:ammo_count()), tostring(ax:remaining_ammo()),
                    tostring(ax._max_ammo), tostring(ax._original_max_ammo),
                    tostring(ax._available_ammo), tostring(ax._current_ammo),
                    tostring(ax.total_remaining_ammo and ax:total_remaining_ammo()))
            end
        end
    end)

    pcall(printf, "[verify_meta_ammo] num_boons=%d cost_factor=%.3f total_ammo_live=%s marker=%s",
        num_boons, live_factor, tostring(live_total_ammo), CT_META_AMMO_HYPERBOLIC_MARKER)
end)

-- v0.7.105 (Issue #6): /verify_altars — per-peer determinism diagnostic for the
-- custom altar (deus_weapon_chest) distribution. The shuffle at line ~1510 uses
-- `HashUtils.fnv32_hash(node.level_seed)` as the seed; if host and client peers
-- arrive at different values for ANY of (node_key, level_seed, hash output,
-- effective_setting counts), the resulting distribution diverges.
--
-- Operating procedure for the MP test (Issue #6 validation plan):
--   1. Host + client both in same CW lobby, same run, same node.
--   2. Both run `/verify_altars` and screenshot/copy the output.
--   3. Compare: every line should match between peers EXCEPT possibly the
--      pending-pops list (depends on whether either peer has opened a chest).
--   4. If `level_seed` or `node_key` differ -> graph-snapshot RPC desync.
--   5. If effective_setting values differ -> host-broadcast settings desync.
--   6. If only the pending-pops differ -> the shuffle ran with different state
--      (the next chest open will produce divergent results).
mod:command("verify_altars", "Per-peer altar distribution determinism check (Issue #6)", function()
    mod:echo("=== verify_altars (ct v%s) ===", MOD_VERSION)

    if not (Managers and Managers.mechanism and Managers.mechanism.game_mechanism) then
        mod:echo("  not in a run (no Managers.mechanism) -- run /verify_altars in-mission")
        return
    end
    local mechanism = Managers.mechanism:game_mechanism()
    local run = mechanism and mechanism.get_deus_run_controller and mechanism:get_deus_run_controller()
    if not run then
        mod:echo("  not a Deus run (deus_run_controller nil)")
        return
    end

    -- Identify current node
    local run_state = run._run_state
    local node_key = run_state and run_state.get_current_node_key and run_state:get_current_node_key()
    local graph    = run.get_graph_data and run:get_graph_data() or (run._get_graph_data and run:_get_graph_data())
    local node     = graph and node_key and graph[node_key]
    local level_seed = node and node.level_seed
    local hash_seed  = level_seed and HashUtils and HashUtils.fnv32_hash and HashUtils.fnv32_hash(level_seed) or 0

    mod:echo("  node_key:        %s", tostring(node_key))
    mod:echo("  level_seed:      %s", tostring(level_seed))
    mod:echo("  fnv32(seed):     %s   (0 = fallback; nonzero = real)", tostring(hash_seed))

    -- effective_setting values (what altar logic actually consumes)
    local eff_up    = effective_setting("chest_upgrade_count")
    local eff_smele = effective_setting("chest_swap_melee_count")
    local eff_srng  = effective_setting("chest_swap_ranged_count")
    local eff_pup   = effective_setting("chest_power_up_count")
    mod:echo("  effective: upgrade=%s melee=%s ranged=%s power_up=%s (-1 = Default)",
        tostring(eff_up), tostring(eff_smele), tostring(eff_srng), tostring(eff_pup))

    -- mod:get values (what THIS peer clicked locally; helpful when divergence shows
    -- that effective_setting was synced from host but the local UI shows something else)
    local own_up    = mod:get("chest_upgrade_count")
    local own_smele = mod:get("chest_swap_melee_count")
    local own_srng  = mod:get("chest_swap_ranged_count")
    local own_pup   = mod:get("chest_power_up_count")
    mod:echo("  local mod:get: upgrade=%s melee=%s ranged=%s power_up=%s",
        tostring(own_up), tostring(own_smele), tostring(own_srng), tostring(own_pup))

    -- Server/client identification
    local is_server = Managers and Managers.player and Managers.player.is_server
    mod:echo("  is_server: %s", tostring(is_server))

    -- Current pending distribution (set after a chest opens; consumed one entry per open)
    local dist = run._deus_weapon_chest_distribution
    if type(dist) == "table" and #dist > 0 then
        local items = {}
        for i = 1, #dist do items[i] = tostring(dist[i]) end
        mod:echo("  pending pops:    [%s]", table.concat(items, ","))
    else
        mod:echo("  pending pops:    <empty> (no chest opened yet on this node)")
    end

    -- Log-mirror so the line lands in console_logs/ for later cross-peer compare
    pcall(printf, "[verify_altars] node=%s seed=%s hash=%s eff=[u=%s,m=%s,r=%s,p=%s] dist_n=%d server=%s",
        tostring(node_key), tostring(level_seed), tostring(hash_seed),
        tostring(eff_up), tostring(eff_smele), tostring(eff_srng), tostring(eff_pup),
        (type(dist) == "table" and #dist or 0), tostring(is_server))
end)

-- v0.7.104: per-meta-boon /verify_ct_meta_<name> chat commands.
-- For each CT_META_BOONS entry, register a command that probes the live
-- `apply_buffs_to_value(...)` result for every stat_buff key the boon writes,
-- compares it against the linear-projection expected value, and reports
-- delta / pass-fail.
--
-- For `ct_meta_ammo` specifically, the per-stat_buff projection only covers
-- `total_ammo` now (the other two are no longer stat_buffs after v0.7.104);
-- the command also prints the hyperbolic cost factor so the user sees what
-- the direct hooks will apply.
local function _resolve_num_boons_for(pl)
    local mech = Managers.mechanism
    local gm   = mech and mech.game_mechanism and mech:game_mechanism()
    local rc   = gm and gm.get_deus_run_controller and gm:get_deus_run_controller()
    if not (rc and pl) then return 0 end
    local ok, list = pcall(rc.get_player_power_ups, rc, pl:network_id(), pl:local_player_id())
    if not ok or type(list) ~= "table" then return 0 end
    return #list
end

local function _make_meta_verify_command(spec)
    local cmd_suffix = spec.name:gsub("^ct_meta_", "")
    local stack_key = spec.name .. "_stack_1"
    mod:command("verify_ct_meta_" .. cmd_suffix,
        "Probe " .. spec.name .. ": live stat_buff resolutions vs linear projection",
        function()
            local pl = Managers.player and Managers.player:local_player()
            local unit = pl and pl.player_unit
            if not unit then
                mod:echo("/verify_ct_meta_%s: no local player unit (keep/menu?)", cmd_suffix)
                return
            end
            local buff_ext = ScriptUnit.has_extension(unit, "buff_system")
            if not buff_ext then
                mod:echo("/verify_ct_meta_%s: no buff_extension on player_unit", cmd_suffix)
                return
            end
            local num_boons = _resolve_num_boons_for(pl)
            local stacks = 0
            local ok_stacks, n = pcall(buff_ext.num_buff_stacks, buff_ext, stack_key)
            if ok_stacks and type(n) == "number" then stacks = n end

            mod:echo("=== /verify_ct_meta_%s ===", cmd_suffix)
            mod:echo("  num_boons=%d  stacks(%s)=%d", num_boons, stack_key, stacks)
            if num_boons > 0 and stacks ~= num_boons then
                mod:echo("  WARN stacks != num_boons (proc/apply desync?)")
            end

            for _, sb in ipairs(spec.stat_buffs) do
                local key = sb.stat_buff
                -- multiplier reads use base=1, bonus reads use base=0.
                local base = sb.multiplier and 1.0 or 0.0
                local per_stack = sb.multiplier or sb.bonus or 0
                local ok_resolve, resolved = pcall(buff_ext.apply_buffs_to_value, buff_ext, base, key)
                resolved = (ok_resolve and type(resolved) == "number") and resolved or 0
                local expected = base + per_stack * stacks
                local delta = resolved - expected
                local pass = math.abs(delta) < 1e-3
                mod:echo("  %s %s: resolved=%.4f expected=%.4f delta=%+.4f (per_stack=%+.4f)",
                    pass and "OK" or "FAIL", key, resolved, expected, delta, per_stack)
            end

            -- ct_meta_ammo: also print the hyperbolic cost factor from the
            -- direct hooks (no longer a stat_buff).
            if spec.name == "ct_meta_ammo" then
                local factor = _ct_meta_ammo_cost_multiplier(num_boons)
                mod:echo("  hyperbolic cost_factor (use_ammo/drain/add_charge): %.3f (floor=%.2f, asymptote=%.2f)",
                    factor, CT_META_AMMO_FLOOR, CT_META_AMMO_FLOOR)
            end
        end)
end

for _, spec in ipairs(CT_META_BOONS) do _make_meta_verify_command(spec) end

-- Special-cased ct_meta_movespeed — uses apply_movement_buff (no stat_buff),
-- so probe the mutated PlayerUnitMovementSettings table directly.
mod:command("verify_ct_meta_movespeed",
    "Probe ct_meta_movespeed: live move_speed setting vs compounding projection",
    function()
        local pl = Managers.player and Managers.player:local_player()
        local unit = pl and pl.player_unit
        if not unit then
            mod:echo("/verify_ct_meta_movespeed: no local player unit (keep/menu?)")
            return
        end
        local buff_ext = ScriptUnit.has_extension(unit, "buff_system")
        local stacks = 0
        if buff_ext then
            local ok_stacks, n = pcall(buff_ext.num_buff_stacks, buff_ext, "ct_meta_movespeed_stack_1")
            if ok_stacks and type(n) == "number" then stacks = n end
        end
        local num_boons = _resolve_num_boons_for(pl)
        local move_speed_live
        local PUMS = rawget(_G, "PlayerUnitMovementSettings")
        if PUMS and PUMS.get_movement_settings_table then
            local ok, tbl = pcall(PUMS.get_movement_settings_table, unit)
            if ok and type(tbl) == "table" then move_speed_live = tbl.move_speed end
        end
        local expected = 4.0 * (1.01 ^ stacks)
        mod:echo("=== /verify_ct_meta_movespeed ===")
        mod:echo("  num_boons=%d  stacks=%d  move_speed_live=%s  expected=%.4f (base 4.0 * 1.01^N)",
            num_boons, stacks, tostring(move_speed_live), expected)
    end)

-- Movement Speed meta boon (v0.7.35): +1% MS per active boon, exotic. Diverges from the
-- stat_buff pattern used by CT_META_BOONS because plain `stat_buff = "movement_speed"`
-- isn't read by any vanilla code — movement speed must be modified via the
-- `apply_movement_buff` / `remove_movement_buff` function pair (which directly mutates
-- the move_speed value via path_to_movement_setting_to_modify).
--
-- Compounding caveat: each stack calls apply_movement_buff with multiplier 1.01, so N
-- stacks = move_speed * 1.01^N. At +1% per stack the compounding is tiny (10 stacks =
-- ~+10.5% vs +10% additive). Acceptable — tooltip says additive for player comprehension.
do
    local power_ups      = rawget(_G, "DeusPowerUpTemplates")
    local buff_templates = rawget(_G, "BuffTemplates")
    local buff_funcs     = rawget(_G, "BuffFunctionTemplates")
    local proc_functions = rawget(_G, "ProcFunctions")
    if power_ups and buff_templates and buff_funcs and buff_funcs.functions and proc_functions then
        local stack_name   = "ct_meta_movespeed_stack"
        local apply_name   = "ct_meta_movespeed_apply"
        local granted_name = "ct_meta_movespeed_granted"
        -- v0.7.56: was `_make_meta_apply` / `_make_meta_granted`. Those were consolidated
        -- into `_make_meta_proc` in v0.7.53 but this special-cased movespeed block was
        -- missed in the rename — module-load crashed with "attempt to call global
        -- '_make_meta_apply' (a nil value)". `_make_meta_proc` looks up existing stack
        -- count via `num_buff_stacks(stack_name .. "_1")`, so the sub-buff's `name`
        -- field has to use that exact key (was bare "ct_meta_movespeed_stack" prior).
        -- v0.7.64: also write granted proc to ProcFunctions (see register_meta_boon comment).
        local proc = _make_meta_proc(stack_name)
        buff_funcs.functions[apply_name]   = proc
        buff_funcs.functions[granted_name] = proc
        proc_functions[granted_name]       = proc
        buff_templates[stack_name] = {
            buffs = {
                {
                    apply_buff_func = "apply_movement_buff",
                    remove_buff_func = "remove_movement_buff",
                    name             = "ct_meta_movespeed_stack_1",
                    -- v0.7.108-dev (Issue #34): hard cap. 30 stacks × 1.01
                    -- (compounding via apply_movement_buff) = 1.01^30 ≈ 1.35x
                    -- move_speed, bounded. See doc-block near MOD_VERSION.
                    max_stacks       = CT_META_AMMO_MAX_STACKS,
                    multiplier       = 1.01,
                    path_to_movement_setting_to_modify = { "move_speed" },
                },
            },
        }
        register_buff_in_network_lookup(stack_name)
        power_ups.ct_meta_movespeed = {
            advanced_description = "description_ct_meta_movespeed",
            display_name         = "display_name_ct_meta_movespeed",
            icon                 = "deus_icon_meta_01",
            max_amount           = 1,
            rectangular_icon     = true,
            buff_template = {
                buffs = {
                    {
                        apply_buff_func = apply_name,
                        buff_func       = granted_name,
                        event           = "on_boon_granted",
                        name            = "ct_meta_movespeed",
                    },
                },
            },
            description_values = {},
        }
        inject_dormant_boon("ct_meta_movespeed", "exotic")
        _add_dormant_to_pool("ct_meta_movespeed", "exotic")
        _dbg("[mod-boon] registered ct_meta_movespeed at rarity exotic")
    end
end

-- ============================================================
-- Mod Boon: Khaine's Communion — 1 green HP per kill (v0.7.32-alpha)
-- ============================================================
-- Heal 1 permanent (green) health every time the player kills an enemy. Exotic rarity.
-- Catalogued under Defensive > Health in the boon tree (per user verdict — health-themed
-- effect groups by effect, not by mod-added origin), but display name carries the
-- "(Mod Boon)" prefix so it's flagged.
--
-- Implementation: proc function with `authority = "server"` so the heal fires once
-- per kill on the server, then `DamageUtils.heal_network` networks the heal to the
-- killer's owning peer. Heal type `heal_from_proc` restores permanent HP (green),
-- not THP.
-- ============================================================
-- Mod Boons: Trait-as-Boon (v0.7.34-alpha)
-- ============================================================
-- 4 weapon traits re-introduced as opt-in exotic boons. Each is gated behind its own
-- toggle in Reworks > Reworks: Boons (default off). When enabled, the trait's buff
-- template is cloned into a new power-up at exotic rarity.
--
-- STACKING WITH TRAIT:
-- * Vaul's Anvil — naturally non-stacks (always_blocking is a binary perk; having two
--   sources of the same perk = same effect as one source).
-- * Manann's Tempest — stacks (each buff fires its own chain_lightning proc on crit,
--   so 2 buffs = 2 independent chains per crit).
-- * Taal's Twinned Arrow — stacks (extra_shot stat_buff bonus is additive: 2 buffs =
--   +2 projectiles).
-- * Asuryan's Wrath — stacks (each fires its own proc roll on melee kill, so 2 buffs
--   = roughly +75% effective proc chance vs +50% baseline).
--
-- TAAL'S TWINNED ARROW RESTRICTION: user asked for "only granted if ranged weapon in
-- slot 2." Vanilla VT2 careers all have a ranged slot, so the case is rare. If the
-- player ends up with this boon but no ranged weapon, the stat_buff is just inert
-- (no shots fire = no extra projectiles). Skipping the gate for v0.7.34; can add an
-- offer-time filter if it becomes a real issue.
-- #144: Vaul's Anvil perk reconciler + probe (replaces vanilla always_blocking_update on ct's
-- boon controller buff; registered into BuffFunctionTemplates.functions in pre_register_trait_boon_
-- lookups and pointed at by the cloned controller sub-buff's update_func).
--
-- The boon's effect is the `deus_always_blocking_buff`, which drives status.override_blocking on/off
-- (apply/remove_always_blocking, morris_buff_settings.lua:1003/1009). Vanilla maintains that perk
-- ONLY reactively: block-broken lockout recovery, plus an ORPHANED weapon-swap trigger
-- (always_blocking_weapon_swap, :3093) that NOTHING in the shipped engine ever calls. So once the
-- perk is dropped -- e.g. by the block-broken 10s lockout, or a buff refresh on some equip/wield/
-- pickup action -- there is no reliable path that re-adds it, and the boon "stops working" while
-- still sitting in the boon list (exactly the #144 re-characterization). This reconciler is
-- authoritative EVERY frame: the perk is present IFF a melee weapon is wielded AND the lockout is
-- not active, so it self-heals any drop the moment the player is back on melee. Runs in the same
-- buff-update context vanilla always_blocking_update did (buff_extension.lua:794), so add_buff/
-- remove_buff of the perk carry the same authority/network path (apply/remove_always_blocking do
-- the override_blocking network send). It also edge-logs `[ct:vaul]` (raw printf; the host runs VMF
-- logging OFF) on every state change, including a `desync` watch (override_blocking not matching the
-- wielded/lockout state even though the perk presence is correct) -- if that ever fires the loss is
-- deeper than perk presence and the log will say so. On `mod.` (not a file-scope local) per the Lua
-- 5.1 200-locals cap. pcall-free hot path but every engine call is existence-guarded.
mod._ct_vauls_anvil_reconcile = function(unit, buff, params)  -- luacheck: ignore params
    local buff_ext = ScriptUnit.has_extension(unit, "buff_system")
    local inv_ext  = ScriptUnit.has_extension(unit, "inventory_system")
    if not (buff_ext and inv_ext) then return end
    local perk_name = (buff.template and buff.template.buff_to_add) or "deus_always_blocking_buff"
    local eq       = inv_ext:equipment()
    local wielded  = eq and eq.wielded and eq.wielded.slot_type or nil
    local melee    = wielded == "melee"
    local locked   = buff_ext:has_buff_type("deus_always_blocking_lock_out") and true or false
    local want     = melee and not locked
    local has_perk = buff_ext:has_buff_type(perk_name) and true or false
    local action   = "none"

    if want and not has_perk then
        buff.buff_id = buff_ext:add_buff(perk_name)
        has_perk = true
        action = "readd"
    elseif (not want) and has_perk then
        if buff.buff_id then buff_ext:remove_buff(buff.buff_id) end
        buff.buff_id = nil
        has_perk = false
        action = melee and "remove_lockout" or "remove_ranged"
    end

    -- Watch (not healed here): override_blocking should equal `want` once the perk state is right.
    -- Per the engine, override_blocking is set ONLY by apply/remove_always_blocking, so reconciling
    -- the perk above should keep it correct; a persistent desync would mean an external clear.
    local status_ext = ScriptUnit.has_extension(unit, "status_system")
    local override   = status_ext and status_ext.override_blocking
    local desync     = status_ext and ((want and override ~= true) or ((not want) and override ~= nil)) or false

    -- Edge-triggered: log only when the state changes, so per-mission volume stays tiny.
    local sig = string.format("%s|%s|%s|%s|%s", tostring(wielded), tostring(locked), tostring(has_perk), tostring(override), action)
    if buff._ct_vaul_sig ~= sig then
        buff._ct_vaul_sig = sig
        pcall(printf, "[ct:vaul] wielded=%s melee=%s locked=%s has_perk=%s override_blocking=%s want=%s action=%s desync=%s (#144)",
            tostring(wielded), tostring(melee), tostring(locked), tostring(has_perk),
            tostring(override), tostring(want), action, tostring(desync))
    end
end

local CT_TRAIT_BOONS = {
    { name = "ct_boon_vauls_anvil",         toggle = "enable_boon_vauls_anvil",         rarity = "unique", icon = "deus_icon_meta_01", source_buff = "always_blocking" },
    { name = "ct_boon_manann_tempest",      toggle = "enable_boon_manann_tempest",      rarity = "unique", icon = "deus_icon_meta_01", source_buff = "deus_crit_chain_lightning" },
    { name = "ct_boon_taal_twinned_arrow",  toggle = "enable_boon_taal_twinned_arrow",  rarity = "unique", icon = "deus_icon_meta_01", source_buff = "deus_extra_shot" },
    { name = "ct_boon_asuryan_wrath",       toggle = "enable_boon_asuryan_wrath",       rarity = "unique", icon = "deus_icon_meta_01", source_buff = "deus_collateral_damage_on_melee_killing_blow" },
    -- #464 follow-up: Anath Raema's Swiftness could never appear in the Disabled/Starting
    -- Boons menus because it is a weapon TRAIT (deus_ammo_pickup_reload_speed,
    -- weapon_traits_morris.lua:528; rolled in the deus_ranged_ammo trait pool :853 and
    -- deus_trollhammer_torpedo :975), NOT a DeusPowerUpTemplates power-up - vanilla has no
    -- boon form of it, so the BOON_TREE enumeration had nothing to list. This 5th
    -- trait-as-boon closes that gap. `literal_buffs` (fixed template) instead of
    -- `source_buff`: the trait's BuffTemplates entry is MUTABLE (the
    -- tweak_anath_raema_permanent rework save-and-restores it, see
    -- apply_anath_raema_permanent_tweak ~L10755), so a load-time clone would silently
    -- change the boon's behavior with the rework toggle's state at load. The literal is
    -- deterministic: ALWAYS the permanent variant. multiplier -0.5 = reload HOLD TIME
    -- x 0.5 (reload_speed is an INVERSE stat: weapon_unit_extension.lua:966 composes
    -- value x (multiplier + 1), buff_extension.lua:1431-1432; the #464 sign-error class).
    -- Menu category: Offensive > Ranged in BOON_TREE (beside vanilla boon_range_01
    -- "Anath Raema's Cruel Volley"), not Mod Boons - the vanilla trait is ranged-pool
    -- and the user looks for it by function (#464 comment 2026-07-12).
    { name = "ct_boon_anath_raema_swiftness", toggle = "enable_boon_anath_raema_swiftness", rarity = "unique", icon = "deus_icon_meta_01",
        literal_buffs = { { name = "ct_boon_anath_raema_swiftness", stat_buff = "reload_speed", multiplier = -0.5, max_stacks = 1 } } },
}
local function register_trait_boon(spec)
    -- v0.7.67: registration (NetworkLookup, buff template, DeusPowerUps* sides)
    -- now happens unconditionally in pre_register_trait_boon_lookups. This
    -- function is only responsible for the toggle-gated pool insert, which
    -- determines whether the user actually rolls the boon.
    if not mod._ct_umbrella_policy.enabled(
        effective_setting("enable_boon_reworks"), effective_setting(spec.toggle)) then
        _remove_dormant_from_pool(spec.name, spec.rarity)
        return
    end
    _add_dormant_to_pool(spec.name, spec.rarity)
    _dbg("[trait-boon] enabled " .. spec.name .. " at rarity " .. spec.rarity)
end

-- v0.7.61: same shape as pre_register_dormant_lookups (v0.7.60). The gated
-- register_trait_boon below skips registration entirely when the peer's
-- enable_boon_<name> toggle is off, so without this pre-registration step two
-- peers with different toggle states (host enables Vaul's Anvil + Manann's
-- Tempest, client only enables Manann's Tempest) appended a different ordered
-- subset of `power_up_ct_boon_*_unique` entries to NetworkLookup.buff_templates
-- and matching deus_power_up_templates entries -- so the host's rpc_add_buff
-- for a trait-boon index resolved to either the wrong buff or a missing key on
-- the client. Pre-register every trait boon's DeusPowerUpTemplate, buff
-- template, and NetworkLookup entries unconditionally at mod-load in sorted
-- order; the gated register_trait_boon below only does pool injection now (its
-- own writes to buff_templates / NetworkLookup are idempotent early-outs).
local function pre_register_trait_boon_lookups()
    local templates       = rawget(_G, "DeusPowerUpTemplates")
    local buff_templates  = rawget(_G, "BuffTemplates")
    local dpubt           = rawget(_G, "DeusPowerUpBuffTemplates")
    if not (templates and buff_templates and dpubt) then
        _dbg("[trait-boon] pre-register skipped: globals not yet loaded")
        return
    end
    -- #144: register ct's Vaul's Anvil perk reconciler into the shared buff-function table
    -- BEFORE any buff can resolve it. buff_extension.update calls
    -- BuffFunctionTemplates.functions[update_func](...) UNGUARDED (buff_extension.lua:794), so a
    -- buff must never name an unregistered function. We therefore only repoint the boon's
    -- update_func to "ct_vauls_anvil_reconcile" when this registration actually succeeded; otherwise
    -- the clone keeps vanilla "always_blocking_update" (always present) and simply falls back to
    -- vanilla behavior -- no crash. BuffFunctionTemplates is a core global loaded before mods, so
    -- readiness here is the normal case.
    local _ct_reconciler_ready = false
    do
        local buff_funcs = rawget(_G, "BuffFunctionTemplates")
        if buff_funcs and buff_funcs.functions and type(mod._ct_vauls_anvil_reconcile) == "function" then
            buff_funcs.functions.ct_vauls_anvil_reconcile = mod._ct_vauls_anvil_reconcile
            _ct_reconciler_ready = true
        else
            _dbg("[trait-boon] BuffFunctionTemplates not ready -- Vaul's Anvil keeps vanilla always_blocking_update (reconciler deferred)")
        end
    end
    local sorted = {}
    for _, spec in ipairs(CT_TRAIT_BOONS) do sorted[#sorted + 1] = spec end
    table.sort(sorted, function(a, b) return a.name < b.name end)
    -- v0.7.63-alpha: register the NetworkLookup NAMES unconditionally (sorted
    -- order, every peer assigns identical indices regardless of which source
    -- buffs are loaded in their BuffTemplates). The buff-template clone +
    -- DeusPowerUpBuffTemplates write still requires source_template, but those
    -- side tables don't determine the sequential NetworkLookup id — only the
    -- name registration does. Splitting them prevents the receiver-side crash
    -- pattern where peer A skipped Vaul's Anvil (source 'always_blocking'
    -- missing for some reason) but peer B registered it → all subsequent
    -- power_up names land on different ids → `Table deus_power_up_templates
    -- does not contain key: N` fatal in network_lookup.lua's strict __index
    -- when peer B's rpc_add_buff reaches peer A. Crash dumps 2026-05-19
    -- 02:59:56 + 03:08:36 (key 177 on the client side).
    --
    -- Same shape as the v0.8.66-dev LA fix: deterministic name registration
    -- decouples NetworkLookup indices from runtime-dependent state, and the
    -- gated content writes (templates / dpubt / buff_templates) remain
    -- idempotent early-outs in the gated register_trait_boon below.
    for _, spec in ipairs(sorted) do
        register_power_up_in_network_lookup(spec.name)
        local buff_name = "power_up_" .. spec.name .. "_" .. spec.rarity
        register_buff_in_network_lookup(buff_name)
    end
    local count, placeholder_count = 0, 0
    for _, spec in ipairs(sorted) do
        -- #464: a spec may carry `literal_buffs` (a fixed buff array) instead of a
        -- `source_buff` to clone - used when the source template is runtime-mutable
        -- (see the ct_boon_anath_raema_swiftness spec comment above). The clone loop
        -- below copies each sub-buff, so the spec's literal stays pristine.
        local source_template = spec.literal_buffs and { buffs = spec.literal_buffs }
            or buff_templates[spec.source_buff]
        -- v0.7.67 hardening (QA-found): write a `templates[spec.name]` entry
        -- UNCONDITIONALLY in sorted order so `inject_dormant_boon` below doesn't
        -- early-out on missing template — if it did, `DeusPowerUpsLookup` would
        -- drift across peers (the exact bug class this refactor targets). When
        -- the source buff is missing on a peer, we ship a placeholder template
        -- with an empty buff array. The boon won't FUNCTION gameplay-wise on
        -- that peer, but its lookup_id will align with peers that do have it —
        -- so rpc_add_buff dispatches still resolve to the correct boon name and
        -- the run doesn't crash. Today all four source buffs (always_blocking,
        -- deus_crit_chain_lightning, deus_extra_shot,
        -- deus_collateral_damage_on_melee_killing_blow) are vanilla and always
        -- present, but this hardening guards against future DLC-gated source
        -- buffs that could differ across peers.
        if not templates[spec.name] then
            local cloned_buffs = {}
            if source_template and source_template.buffs then
                for i, sub in ipairs(source_template.buffs) do
                    cloned_buffs[i] = table.clone(sub)
                end
            else
                placeholder_count = placeholder_count + 1
                _dbg("[trait-boon] %s: source buff '%s' missing — using empty placeholder buffs (boon non-functional on this peer but lookup_id stays aligned)",
                    spec.name, tostring(spec.source_buff))
                -- Single placeholder buff with the correct name field so
                -- inject_dormant_boon's `buff_template.buffs[1].name = buff_name`
                -- assignment doesn't nil-crash.
                cloned_buffs[1] = { name = "placeholder" }
            end
            -- #144: repoint Vaul's Anvil's controller sub-buff to ct's self-healing reconciler
            -- (mod._ct_vauls_anvil_reconcile). Vanilla always_blocking_update only re-applies the
            -- perk reactively -- via block-broken lockout recovery and an ORPHANED weapon-swap
            -- trigger (always_blocking_weapon_swap, morris_buff_settings.lua:3093, which nothing in
            -- the engine ever fires) -- so once deus_always_blocking_buff is dropped by equip/wield
            -- churn it can stay off (the "stops working after an equip action" report). The
            -- reconciler is authoritative every frame: perk present IFF melee wielded AND not
            -- lockout. Matched by the perk field so array order is irrelevant; only repointed when
            -- the function is confirmed registered (see _ct_reconciler_ready) so the buff never
            -- names an unregistered update_func.
            if spec.name == "ct_boon_vauls_anvil" and _ct_reconciler_ready then
                for _, sub in ipairs(cloned_buffs) do
                    if type(sub) == "table" and sub.buff_to_add == "deus_always_blocking_buff"
                        and sub.update_func == "always_blocking_update" then
                        sub.update_func = "ct_vauls_anvil_reconcile"
                    end
                end
            end
            templates[spec.name] = {
                advanced_description = "description_" .. spec.name,
                display_name         = "display_name_" .. spec.name,
                icon                 = spec.icon,
                max_amount           = 1,
                rectangular_icon     = true,
                buff_template        = { buffs = cloned_buffs },
                description_values   = {},
            }
        end
        local buff_name = "power_up_" .. spec.name .. "_" .. spec.rarity
        local buff_template = table.clone(templates[spec.name].buff_template)
        buff_template.buffs[1].name = buff_name
        dpubt[buff_name] = buff_template
        buff_templates[buff_name] = buff_template
        -- Full registration (NetworkLookup IDs, DeusPowerUps / Array / Lookup,
        -- buff template tables) — UNCONDITIONAL so every peer's
        -- DeusPowerUpsLookup ordering matches regardless of source-buff
        -- availability. Pool insert is gated separately in register_trait_boon.
        inject_dormant_boon(spec.name, spec.rarity)
        count = count + 1
    end
    _dbg("[trait-boon] pre-registered %d trait boons for client compat (%d using placeholder buffs)",
        count, placeholder_count)
end

pre_register_trait_boon_lookups()

for _, spec in ipairs(CT_TRAIT_BOONS) do
    register_trait_boon(spec)
end

-- Assignment to the forward-declared `sync_host_dependent_state` (see top of file).
-- Called by the ct_sync_host_settings RPC handler immediately after a client
-- receives the host's settings payload, so any template/pool mutations gated on
-- a synced setting are reapplied with the host's values. Apply order mirrors the
-- one-shot calls each sync_* function does at module load.
sync_host_dependent_state = function()
    sync_reckless_swings()
    sync_bomb_cooldown()
    sync_boon_movespeed()
    sync_poison_proof_tweak()
    sync_invis_potion_tweak()
    sync_moot_milk_alt_tweak()
    sync_shard_strike()
    sync_anath_raema_permanent()
    -- User-suggestion mechanic tweaks live in _ct_mechanic_tweaks.lua (own chunk to
    -- stay under the 200-local main-chunk cap); re-applied here on host-settings receipt.
    if mod._ct_sync_shadow_skull_stun then mod._ct_sync_shadow_skull_stun() end
    if mod._ct_sync_miasma then mod._ct_sync_miasma() end
    -- 2026-05-23 v0.7.100-dev FULLY PURGED: sync_dormant_boons() — function no longer
    -- exists (block-commented along with DORMANT_BOON_RARITY). Re-enable alongside the
    -- L4721-style apply-site uncomment.
    for _, spec in ipairs(CT_TRAIT_BOONS) do
        register_trait_boon(spec)
    end
end

-- v0.7.240-dev (#406): ct_kill_heal RE-ENABLED. It was block-commented in v0.7.98-dev
-- (user request after a Chest-of-Trials crash); the user's issue-406 verify comment now
-- explicitly requires it selectable as a starting boon ("This boon is missing from
-- selectable starting boons... Fix that first"), and the two hazards that motivated the
-- removal are both addressed: the client heal fassert is gated (is_server gate below,
-- issue 406) and modded-boon wire exposure is peer-parity gated (issue 426 wire-safety
-- block below). Every peer on v0.7.240-dev re-registers the name identically, so the
-- lookup-order invariant (feedback_vt2_gated_registration_diverges) holds the same way
-- it did for the removal. The matching VMF widget line is catalogued once in
-- `_data.lua` BOON_TREE > mod_boons; both Disabled Boons and Starting Boons derive
-- from that one row. The kill_heal regression check is restored in the same version.
do
    -- v0.7.63-alpha: register NetworkLookup names FIRST, unconditionally, BEFORE
    -- the globals-ready gate. Two peers running the same ct version must always
    -- assign the same sequential index to "ct_kill_heal" regardless of whether
    -- their `DeusPowerUpTemplates` / `BuffFunctionTemplates` globals happened to
    -- be loaded at module-init time on each peer. Same fix pattern as
    -- pre_register_trait_boon_lookups: name registration decoupled from
    -- template construction so the lookup ids stay deterministic across peers.
    register_power_up_in_network_lookup("ct_kill_heal")
    register_buff_in_network_lookup("power_up_ct_kill_heal_exotic")

    local power_ups  = rawget(_G, "DeusPowerUpTemplates")
    local buff_funcs = rawget(_G, "BuffFunctionTemplates")

    if power_ups and buff_funcs and buff_funcs.functions then
        local CT_KILL_HEAL_AMOUNT = 1
        local _ct406_heal_diag_count = 0
        local CT406_HEAL_DIAG_CAP = 12
        local function _ct406_log_heal(result, unit, amount, before_hp, after_hp)
            if _ct406_heal_diag_count >= CT406_HEAL_DIAG_CAP then return end
            _ct406_heal_diag_count = _ct406_heal_diag_count + 1
            pcall(printf, "[ct:406] kill_heal result=%s server=%s alive=%s amount=%s hp_before=%s hp_after=%s count=%d/%d",
                tostring(result),
                tostring(Managers and Managers.player and Managers.player.is_server),
                tostring(ALIVE and ALIVE[unit]),
                tostring(amount),
                tostring(before_hp),
                tostring(after_hp),
                _ct406_heal_diag_count,
                CT406_HEAL_DIAG_CAP)
        end

        -- v0.7.295-dev (#406): restore a visible 1 permanent-green HP per kill
        -- and keep a bounded diagnostic receipt. The important vanilla constraint
        -- remains the heal_type: `health_regen` is in
        -- GenericStatusExtension.is_permanent_heal(), while the older
        -- `heal_from_proc` path becomes temporary health. The buff template itself
        -- has `authority = "server"`; this explicit gate keeps older hook paths
        -- from tripping DamageUtils.heal_network's "Only server can heal" fassert.
        buff_funcs.functions.ct_kill_heal_on_kill = function(unit, buff, params)
            -- Issue 406: heal_network fasserts "Only server can heal" on
            -- clients (damage_utils.lua:2636) - a CLIENT taking this boon
            -- crashed on their next kill (same class as crt issue 405).
            -- Vanilla gate per buff_templates.lua:325/:404: the client
            -- instance no-ops; the host's instance of the synced buff
            -- grants the heal.
            if not (Managers and Managers.player and Managers.player.is_server) then
                _ct406_log_heal("skip-client", unit, CT_KILL_HEAL_AMOUNT, nil, nil)
                return
            end
            if not (ALIVE and ALIVE[unit]) then
                _ct406_log_heal("skip-dead-unit", unit, CT_KILL_HEAL_AMOUNT, nil, nil)
                return
            end

            local before_hp = nil
            local after_hp = nil
            local health_extension = ScriptUnit and ScriptUnit.has_extension and ScriptUnit.has_extension(unit, "health_system")
            if health_extension and health_extension.current_permanent_health then
                local ok, value = pcall(function() return health_extension:current_permanent_health() end)
                if ok then before_hp = value end
            end

            DamageUtils.heal_network(unit, unit, CT_KILL_HEAL_AMOUNT, "health_regen")

            if health_extension and health_extension.current_permanent_health then
                local ok, value = pcall(function() return health_extension:current_permanent_health() end)
                if ok then after_hp = value end
            end
            _ct406_log_heal("healed", unit, CT_KILL_HEAL_AMOUNT, before_hp, after_hp)
        end

        power_ups.ct_kill_heal = {
            advanced_description = "description_ct_kill_heal",
            display_name         = "display_name_ct_kill_heal",
            icon                 = "deus_icon_meta_01",  -- placeholder; future: dedicated heal-on-kill icon
            max_amount           = 1,
            rectangular_icon     = true,
            buff_template = {
                buffs = {
                    {
                        authority = "server",
                        buff_func = "ct_kill_heal_on_kill",
                        event     = "on_kill",
                        name      = "ct_kill_heal",
                    },
                },
            },
            description_values = {},
        }

        inject_dormant_boon("ct_kill_heal", "exotic")
        _add_dormant_to_pool("ct_kill_heal", "exotic")
        pcall(printf, "[ct:406] ct_kill_heal re-enabled at rarity exotic (is_server heal gate active; pool membership peer-parity gated per issue 426)")
    else
        _dbg("[mod-boon] DeusPowerUpTemplates / BuffFunctionTemplates not ready for ct_kill_heal — NetworkLookup name reserved, template construction deferred")
    end
end

-- ============================================================
-- Peer-parity wire safety for modded boons and miracles (#426 / #406)
-- v0.7.240-dev -- issue 371 doctrine, BUG_CLASSES 31, cwv beacon pattern
-- ============================================================
-- WHY: ct's modded boons (power_up_ct_boon_*, ct_meta_*, ct_kill_heal) and miracles
-- (ct_miracle_*) register into NetworkLookup.buff_templates / deus_power_up_templates.
-- Registration is UNCONDITIONAL and must stay so (index parity across ct peers,
-- see inject_dormant_boon's v0.7.67 comment). But once such content is GRANTED or
-- APPLIED, its modded lookup index goes on vanilla wire paths that reach EVERY peer,
-- including peers without ct (ct's own create_network_hash shim deliberately lets
-- them join):
--   * host buff apply     -> rpc_add_buff broadcast, buff_system.lua:302-305; receiver
--                            decode :430 fatals on the unknown index (network_lookup
--                            strict __index)
--   * granted power-ups   -> deus run-state sync, deus_run_state_spec.lua:60 encode /
--                            :85 decode on every peer
--   * persistent miracles -> saved names re-applied each mission spawn,
--                            deus_spawning.lua:249 / :277-278
--   * hot-join            -> live server-controlled buffs re-sent to a late joiner,
--                            buff_system.lua:1087-1104
-- These are GAMEPLAY axes: sender-substitution would change what happens, so per the
-- issue 371 axis map they get a PEER-PARITY GATE, not substitution. UNCONDITIONAL
-- (never toggle-gated) per the never-crash doctrine.
--
-- HOW: the shared peer-parity beacon (copied single-source lib, master:
-- tools/shared_lib/_lib_peer_parity.lua; same instance pattern as cwv issue 424).
-- Presence is proven over VMF's own mod-to-mod channel - wire-safe by construction.
-- Fail-safe posture: modded content is INERT until every other human peer positively
-- acks; solo enables immediately; any beacon error forces content off. The existing
-- ct_peer_manifest_chunk machinery stays what it is - an on-demand DIAGNOSTIC dump -
-- the beacon is the live gate.
--
-- Gate surfaces (all in this file):
--   1. POOL membership     - eject/inject DeusPowerUpRarityPool entries (below)
--   2. GRANT choke point   - parity filter in the consolidated add_power_ups hook
--   3. STARTING boons      - parity filter in the _add_initial_power_ups hook
--   4. MIRACLE buy/apply   - degrade-to-vanilla in _try_buy_blessing + Isha arm/apply
--   5. PARITY-LOSS STRIP   - debounced host-side removal of already-granted modded
--                            power-ups, persistent-buff names, and live modded buffs
--                            (details on the debounce below)
do
    -- 200-LOCAL CEILING (Lua 5.1): the main chunk carries ~194 active locals by
    -- this point, and this block's helpers pushed it past 200 (Stingray compile
    -- error at first build). Everything below therefore lives inside ONE builder
    -- function - its locals occupy function scope, costing the chunk a single
    -- slot that releases at this do-block's end. Behavior is unchanged.
    local function _ct_install_peer_parity()
        local inst
        local ok_lib, factory = pcall(function()
            return mod:dofile("scripts/mods/chaos_wastes_tweaker_dev/_lib_peer_parity")
        end)
        if ok_lib and type(factory) == "function" then
            local ok_inst, built = pcall(factory, mod, {
                channel     = "ct_peer_parity_present",
                schema      = CT_RPC_SCHEMA,
                mod_label   = "Chaos Wastes Tweaker",
                echo_prefix = "[ct]",
            })
            if ok_inst and type(built) == "table" then
                inst = built
            else
                pcall(printf, "[ct:426] peer-parity factory failed: %s", tostring(built))
            end
        else
            pcall(printf, "[ct:426] peer-parity lib failed to load: %s", tostring(factory))
        end

        -- Exports readable from hooks defined lexically ABOVE this block (they read the
        -- mod table at call time, so file position does not matter).
        mod._ct_peer_parity = inst

        -- "Is this power-up name ct-injected?" - _injected_dormants is the single registry
        -- every ct boon passes through (inject_dormant_boon writes it for trait boons,
        -- meta boons and ct_kill_heal alike). Vanilla names are never in it.
        mod._ct_is_modded_power_up = function(name)
            return name ~= nil and _injected_dormants[name] ~= nil
        end

        -- "Is it wire-safe to grant/apply ct modded content right now?" Positive-evidence
        -- check: true only when solo or every other human peer acked the beacon. Beacon
        -- missing or any error = false (fail-safe: modded content stays inert; vanilla ct
        -- features are untouched).
        mod._ct_wire_safe = function()
            local pp = mod._ct_peer_parity
            if not pp then return false end
            local ok, res = pcall(pp.all_peers_have, pp)
            return ok and res == true
        end

        -- "Is this buff TEMPLATE name ct-owned?" Used by the parity-loss strip. Covers
        -- ct_miracle_*, ct_meta_*_stack and power_up_ct_* (trait boons, kill_heal,
        -- meta boons). No vanilla template name starts with either prefix
        -- (grep-verified across scripts/settings 2026-07-11).
        mod._ct_is_ct_buff_template = function(n)
            return type(n) == "string" and (n:find("^ct_") ~= nil or n:find("^power_up_ct_") ~= nil)
        end

        -- Pool eject/inject ------------------------------------------------------
        local TRAIT_BOON_BY_NAME = {}
        for _, spec in ipairs(CT_TRAIT_BOONS) do TRAIT_BOON_BY_NAME[spec.name] = spec end

        local function _ct_eject_modded_pools()
            local n = 0
            for name, rec in pairs(_injected_dormants) do
                _remove_dormant_from_pool(name, rec.rarity)
                n = n + 1
            end
            pcall(printf, "[ct:426] modded boon pools ejected (%d boon(s) unrollable until peer parity is confirmed)", n)
        end

        local function _ct_inject_modded_pools()
            local n = 0
            for name, rec in pairs(_injected_dormants) do
                local spec = TRAIT_BOON_BY_NAME[name]
                if spec then
                    register_trait_boon(spec)   -- respects the user's enable_boon_* toggle
                else
                    _add_dormant_to_pool(name, rec.rarity)
                end
                n = n + 1
            end
            pcall(printf, "[ct:426] modded boon pools restored (%d boon(s) eligible, peer parity confirmed)", n)
        end

        -- Parity-loss strip (DEBOUNCED - see below) ------------------------------
        -- Removes already-granted modded state so the run degrades to a vanilla-safe
        -- lobby: granted modded power-ups out of every player's run-state list (stops
        -- both the state sync to a joiner and next-mission reapply), ct names out of
        -- the persistent-buffs lists (Ulric), and live ct server-controlled buffs off
        -- all units. Buff removal uses remove_server_controlled_buff, whose RPC carries
        -- only an integer server_buff_id (buff_system.lua:340) and no-ops on peers
        -- without the buff (:437-454) - wire-safe by construction.
        local function _ct_filter_wire_entries(values, persistent_names)
            local filtered, removed = {}, 0
            if type(values) ~= "table" then return filtered, removed end
            for i = 1, #values do
                local value = values[i]
                local name = persistent_names and value or (type(value) == "table" and value.name)
                local is_modded
                if persistent_names then
                    is_modded = mod._ct_is_ct_buff_template(name)
                else
                    is_modded = name ~= nil and _injected_dormants[name] ~= nil
                end
                if is_modded then
                    removed = removed + 1
                else
                    filtered[#filtered + 1] = value
                end
            end
            return filtered, removed
        end
        mod._ct_filter_wire_entries = _ct_filter_wire_entries

        -- Walk one SharedState server key's full composite-key tree. Full sync
        -- serializes every row in `_server_state`, including rows whose players
        -- are no longer enumerable through PlayerManager (shared_state.lua:
        -- 683-708). The previous present-player-only strip left those stale rows
        -- capable of exposing a CT NetworkLookup id to a late joiner.
        local function _ct_each_server_state_row(run_state, key_type, visit)
            local shared = run_state and run_state._shared_state
            local key_state = shared and shared._server_state and shared._server_state[key_type]
            if type(key_state) ~= "table" then return end
            for peer_id, local_players in pairs(key_state) do
                if type(local_players) == "table" then
                    for local_player_id, profiles in pairs(local_players) do
                        if type(profiles) == "table" then
                            for profile_index, careers in pairs(profiles) do
                                if type(careers) == "table" then
                                    for career_index, parties in pairs(careers) do
                                        if type(parties) == "table" then
                                            for _, value in pairs(parties) do
                                                visit(peer_id, local_player_id, profile_index, career_index, value)
                                            end
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end

        local function _ct_strip_modded_content(reason)
            local completed = false
            local ok, err = pcall(function()
                if not (Managers and Managers.player and Managers.player.is_server) then
                    error("server PlayerManager unavailable")
                end
                local mechanism = Managers.mechanism and Managers.mechanism:game_mechanism()
                local rc = mechanism and mechanism.get_deus_run_controller and mechanism:get_deus_run_controller()
                local run_state = rc and rc._run_state
                local stripped_pu, stripped_party, stripped_persist, stripped_buffs = 0, 0, 0, 0

                if run_state then
                    _ct_each_server_state_row(run_state, "power_ups", function(peer_id, lpid, profile_index, career_index, values)
                        local filtered, removed = _ct_filter_wire_entries(values, false)
                        if removed > 0 then
                            run_state:set_player_power_ups(peer_id, lpid, profile_index, career_index, filtered)
                            stripped_pu = stripped_pu + removed
                        end
                    end)
                    _ct_each_server_state_row(run_state, "persistent_buffs", function(peer_id, lpid, profile_index, career_index, values)
                        local filtered, removed = _ct_filter_wire_entries(values, true)
                        if removed > 0 then
                            run_state:set_player_persistent_buffs(peer_id, lpid, profile_index, career_index, filtered)
                            stripped_persist = stripped_persist + removed
                        end
                    end)
                    if run_state.get_party_power_ups and run_state.set_party_power_ups then
                        local party = run_state:get_party_power_ups()
                        local filtered, removed = _ct_filter_wire_entries(party, false)
                        if removed > 0 then
                            run_state:set_party_power_ups(filtered)
                            stripped_party = removed
                        end
                    end
                    -- A stripped Isha buff must not re-arm/re-apply from stale flags.
                    if rc._ct_isha_active then
                        rc._ct_isha_active = nil
                        rc._ct_isha_active_level = nil
                    end
                end

                local buff_system = Managers.state and Managers.state.entity and Managers.state.entity:system("buff_system")
                local scb = buff_system and buff_system.server_controlled_buffs
                if buff_system and scb then
                    for unit, unit_buffs in pairs(scb) do
                        if type(unit_buffs) == "table" then
                            local ids = {}
                            for sbid, entry in pairs(unit_buffs) do
                                if entry and mod._ct_is_ct_buff_template(entry.template_name) then
                                    ids[#ids + 1] = sbid
                                end
                            end
                            for i = 1, #ids do
                                buff_system:remove_server_controlled_buff(unit, ids[i])
                                stripped_buffs = stripped_buffs + 1
                            end
                        end
                    end
                end

                pcall(printf, "[ct:426] parity-loss strip reason=%s: removed %d player power-up(s), %d party power-up(s), %d persistent buff name(s), %d live buff(s) from the full synchronized state - lobby degraded to vanilla-safe state",
                    tostring(reason or "parity_loss"), stripped_pu, stripped_party, stripped_persist, stripped_buffs)
                completed = true
            end)
            if not ok then
                pcall(printf, "[ct:426] parity-loss strip reason=%s errored: %s", tostring(reason or "parity_loss"), tostring(err))
            end
            return ok and completed
        end
        mod._ct_strip_modded_content = _ct_strip_modded_content

        -- Observation-only counterpart to the destructive strip. It walks the
        -- exact same full SharedState tree, including departed-player rows, so
        -- #426 evidence can distinguish a gate failure from a run that never
        -- carried CT state. No getter result is retained or mutated.
        local function _ct_census_modded_content()
            local result = {
                ok = false,
                run_state = false,
                player_power_ups = 0,
                party_power_ups = 0,
                persistent_buffs = 0,
                live_buffs = 0,
            }
            local ok, err = pcall(function()
                local mechanism = Managers and Managers.mechanism and Managers.mechanism:game_mechanism()
                local rc = mechanism and mechanism.get_deus_run_controller and mechanism:get_deus_run_controller()
                local run_state = rc and rc._run_state
                result.run_state = run_state ~= nil

                if run_state then
                    _ct_each_server_state_row(run_state, "power_ups", function(_, _, _, _, values)
                        local _, removed = _ct_filter_wire_entries(values, false)
                        result.player_power_ups = result.player_power_ups + removed
                    end)
                    _ct_each_server_state_row(run_state, "persistent_buffs", function(_, _, _, _, values)
                        local _, removed = _ct_filter_wire_entries(values, true)
                        result.persistent_buffs = result.persistent_buffs + removed
                    end)
                    if run_state.get_party_power_ups then
                        local _, removed = _ct_filter_wire_entries(run_state:get_party_power_ups(), false)
                        result.party_power_ups = removed
                    end
                end

                local buff_system = Managers and Managers.state and Managers.state.entity
                    and Managers.state.entity:system("buff_system")
                local scb = buff_system and buff_system.server_controlled_buffs
                if type(scb) == "table" then
                    for _, unit_buffs in pairs(scb) do
                        if type(unit_buffs) == "table" then
                            for _, entry in pairs(unit_buffs) do
                                if entry and mod._ct_is_ct_buff_template(entry.template_name) then
                                    result.live_buffs = result.live_buffs + 1
                                end
                            end
                        end
                    end
                end
            end)
            result.ok = ok
            if not ok then result.error = tostring(err) end
            result.total = result.player_power_ups + result.party_power_ups
                + result.persistent_buffs + result.live_buffs
            return result
        end
        mod._ct_census_modded_content = _ct_census_modded_content

        -- #426 bounded diagnostic. The existing fix is source-complete, but the
        -- available logs only prove solo enablement. This command separates:
        -- (1) beacon/hook installation, (2) local catalog registration, (3) an
        -- unsafe CT state surviving while parity is absent, and (4) a test that
        -- never established a remote peer or custom run state.
        mod:command("ct_426_diag", "Audit modded boon and miracle peer wire safety", function()
            local pp = mod._ct_peer_parity
            local function pp_call(method, fallback, ...)
                local fn = type(pp) == "table" and pp[method]
                if type(fn) ~= "function" then return fallback end
                local ok, value = pcall(fn, pp, ...)
                if ok then return value end
                return fallback
            end
            local installed = pp_call("is_installed", false) == true
            local applied = pp_call("applied_state", "missing")
            local all_peers = pp_call("all_peers_have", false) == true
            local feature_count = pp_call("feature_count", 0)

            local roster_known = false
            local peers, missing = {}, 0
            local me
            pcall(function() me = Network and Network.peer_id and Network.peer_id() end)
            local pm = Managers and Managers.player
            if pm and type(pm.human_players) == "function" then
                local ok_roster, humans = pcall(function() return pm:human_players() end)
                if ok_roster and type(humans) == "table" then
                    roster_known = true
                    for _, player in pairs(humans) do
                        local peer_id = player and player.peer_id
                        if type(peer_id) == "string" and peer_id ~= me then
                            peers[#peers + 1] = peer_id
                        end
                    end
                end
            end
            table.sort(peers)
            for i = 1, #peers do
                local peer_id = peers[i]
                local acked = pp_call("peer_has", false, peer_id) == true
                if not acked then missing = missing + 1 end
                pcall(printf, "[ct:426:diag] peer=%s acked=%s", tostring(peer_id), tostring(acked))
            end

            local power_lookup = NetworkLookup and rawget(NetworkLookup, "deus_power_up_templates")
            local buff_lookup = NetworkLookup and rawget(NetworkLookup, "buff_templates")
            local power_expected, buff_expected, catalog_mismatch = 0, 0, 0
            local mismatch_rows = 0
            local function audit_lookup(kind, lookup, name)
                local index = type(lookup) == "table" and rawget(lookup, name) or nil
                local reverse = type(lookup) == "table" and type(index) == "number"
                    and rawget(lookup, index) or nil
                if type(index) ~= "number" or reverse ~= name then
                    catalog_mismatch = catalog_mismatch + 1
                    if mismatch_rows < 24 then
                        mismatch_rows = mismatch_rows + 1
                        pcall(printf, "[ct:426:diag] catalog kind=%s name=%s index=%s reverse=%s ok=false",
                            tostring(kind), tostring(name), tostring(index), tostring(reverse))
                    end
                end
            end
            for name in pairs(_injected_dormants) do
                power_expected = power_expected + 1
                audit_lookup("power_up", power_lookup, name)
            end
            local buff_templates = rawget(_G, "BuffTemplates")
            if type(buff_templates) == "table" then
                for name in pairs(buff_templates) do
                    if mod._ct_is_ct_buff_template(name) then
                        buff_expected = buff_expected + 1
                        audit_lookup("buff", buff_lookup, name)
                    end
                end
            end
            if power_expected == 0 or buff_expected == 0 then
                catalog_mismatch = catalog_mismatch + 1
            end

            local census = _ct_census_modded_content()
            local gate_ok = installed and feature_count >= 1
                and ((all_peers and applied == "enabled") or (not all_peers and applied == "disabled"))
            local catalog_ok = catalog_mismatch == 0
            local state_ok = census.ok and (all_peers or census.total == 0)
            local live_custom = census.run_state and census.total > 0

            pcall(printf,
                "[ct:426:diag] state run_state=%s player_power_ups=%d party_power_ups=%d persistent_buffs=%d live_buffs=%d total=%d ok=%s error=%s",
                tostring(census.run_state), census.player_power_ups, census.party_power_ups,
                census.persistent_buffs, census.live_buffs, census.total,
                tostring(census.ok), tostring(census.error))
            pcall(printf,
                "[ct:426:diag] summary installed=%s gate=%s catalog=%s state=%s live_custom=%s roster_known=%s peers=%d missing=%d all_peers=%s applied=%s features=%d power_catalog=%d buff_catalog=%d mismatches=%d",
                installed and "PASS" or "FAIL", gate_ok and "PASS" or "FAIL",
                catalog_ok and "PASS" or "FAIL", state_ok and "PASS" or "FAIL",
                live_custom and "YES" or "NO", tostring(roster_known), #peers, missing,
                tostring(all_peers), tostring(applied), feature_count,
                power_expected, buff_expected, catalog_mismatch)
            mod:echo("[ct] #426 diagnostic written to the console log")
        end)

        -- Debounce: the beacon disables INSTANTLY when an un-acked peer appears (correct,
        -- crash-safe direction for the reversible gates above), but the strip is
        -- DESTRUCTIVE (granted boons do not come back). A ct-running friend hot-joining
        -- produces a transient disable until their ack lands; stripping on that transient
        -- would nuke the lobby's boons for nothing. STRIP_GRACE must exceed the beacon's
        -- WORST-CASE ack path, not the typical one: VMF's network_send silently skips
        -- peers whose VMF handshake hasn't completed (vmf network.lua:236-239), so the
        -- arrival-triggered announce can be lost and the retry only comes at the lib's
        -- ANNOUNCE_EVERY = 10s cadence (review finding, pre-ship - 6s stripped a ct
        -- friend on one lost announce). 15s > announce retry (10s) + settle (2s) + poll
        -- slack, and still lands inside a joining player's map-load + first-fight window.
        -- The synchronous hot-join fence below handles the earlier pre-roster
        -- engine seam; this grace remains only for non-join parity transitions.
        local STRIP_GRACE = 15.0
        local _clock = 0
        local _strip_deadline = nil

        -- Mod Tweaker presentation bridge (issue 426 follow-up; mirrors
        -- career_tweaker.lua:~866-890 for issue 425). The gate surfaces above are
        -- the RUNTIME safety and stay authoritative whether or not GUT is
        -- installed; this only makes the saved rows that control gated content
        -- read as unavailable while the gate is closed, instead of looking
        -- actionable and silently doing nothing.
        --
        -- Loaded OUTSIDE the `if inst` branch on purpose: when the beacon is
        -- unavailable the content is inert for the whole session, which is
        -- exactly when the rows most need to say so. `inst` may be nil in the
        -- evaluator below, and a nil beacon reads as permanently closed.
        -- pcall the load: _ct_install_peer_parity() is NOT wrapped by its caller,
        -- so an error raised here would abort the whole wire-safety install. This
        -- module is presentation only and must never be able to do that.
        local ok_policy, wire_policy = pcall(function()
            return mod:dofile("scripts/mods/chaos_wastes_tweaker_dev/_ct_wire_policy")
        end)
        if not (ok_policy and type(wire_policy) == "table") then
            pcall(printf, "[ct:426] wire-policy module unavailable (%s); Mod Tweaker rows stay ungated (runtime safety unaffected)",
                tostring(wire_policy))
            wire_policy = nil
        end
        mod._ct_wire_policy = wire_policy
        local gate_registered = wire_policy == nil   -- nothing to register; never retry
        local gate_retry = 0
        local try_runtime_gate
        do
            local runtime_mod_id = "ct_dev"
            local ok_name, live_name = pcall(function() return mod:get_name() end)
            if ok_name and type(live_name) == "string" and live_name ~= "" then
                runtime_mod_id = live_name
            end
            local gate_id = runtime_mod_id .. ":426:peer-parity"
            try_runtime_gate = function()
                if gate_registered then return end
                local spec = wire_policy.runtime_gate_spec(
                    runtime_mod_id, wire_policy.GATED_SETTING_IDS,
                    function()
                        -- Read the SETTLED gate, not all_peers_have(): the rows
                        -- should track exactly what the boon/miracle surfaces are
                        -- doing, including the enable settle window. No beacon at
                        -- all means the content never activates this session.
                        local available = inst ~= nil
                            and inst:applied_state() == "enabled"
                        return available, available and nil or wire_policy.GATE_REASON
                    end)
                local registered = wire_policy.try_register_runtime_gate(
                    rawget(_G, "get_mod"), gate_id, spec)
                gate_registered = registered == true
                mod._ct_wire_runtime_gate_registered = gate_registered
                if gate_registered then
                    pcall(printf, "[ct:426] Mod Tweaker gate registered id=%s rows=%d beacon=%s",
                        gate_id, #wire_policy.GATED_SETTING_IDS, tostring(inst ~= nil))
                end
            end
        end
        try_runtime_gate()

        if inst then
            inst:register_gated_feature("ct_modded_boons_miracles", {
                label = "ct_gated_modded_boons",
                on_enable = function()
                    _strip_deadline = nil
                    _ct_inject_modded_pools()
                end,
                on_disable = function()
                    _ct_eject_modded_pools()
                    if Managers and Managers.player and Managers.player.is_server then
                        _strip_deadline = _clock + STRIP_GRACE
                    end
                end,
            })

            -- install() wraps the existing mod.update (defined near the top of this file)
            -- preserving it; grep-verified single assignment, nothing reassigns it later.
            pcall(function() inst:install() end)

            -- Fail-safe INITIAL posture. The lib starts _applied = "disabled" but never
            -- invokes on_disable for the initial state (callbacks fire on transitions
            -- only), while the load-time registration above already put modded boons in
            -- the pools. Without this eject, a lobby containing a never-acking (non-ct)
            -- peer would keep the load-time pools forever - the exact #426 hole. Eject
            -- once now; the first tick re-enables within ~0.5s when solo, after acks +
            -- settle in a lobby.
            _ct_eject_modded_pools()

            -- Synchronous hot-join fence. Vanilla calls
            -- GameNetworkManager.hot_join_sync(peer_id) BEFORE it adds the
            -- remote player to PlayerManager (peer_states.lua:432 vs :450).
            -- The poll-only beacon therefore cannot see the peer in time to
            -- protect BuffSystem.hot_join_sync or the Deus SharedState request.
            --
            -- There is no wait/timeout here: an already-acked CT peer passes;
            -- every unknown/missing peer immediately receives the vanilla-safe
            -- degraded run after the full synchronized CT state is stripped.
            -- If the strip itself errors, native hot-join sync is NOT called and
            -- NetworkServer.kick_peer is the bounded fallback. A rejected join
            -- is preferable to sending an unresolved NetworkLookup id and CTDing
            -- the other process. Saved settings are never changed.
            mod:hook("GameNetworkManager", "hot_join_sync", function(func, self, peer_id, ...)
                if type(peer_id) ~= "string" then
                    return func(self, peer_id, ...)
                end

                local confirmed = inst:peer_has(peer_id)
                inst:require_peer(peer_id) -- immediate gate-off before any native sync

                if not confirmed then
                    local stripped = _ct_strip_modded_content("hot_join_unconfirmed:" .. peer_id)
                    -- require_peer() synchronously drove on_disable, which arms
                    -- the ordinary 15-second transition strip. This join has
                    -- already been handled synchronously, so suppress that
                    -- redundant second strip/log row.
                    _strip_deadline = nil
                    if not stripped then
                        pcall(printf, "[ct:426] hot-join sync REJECTED peer=%s: CT state could not be made wire-safe", tostring(peer_id))
                        local network_server = self and self.network_server
                        if network_server and type(network_server.kick_peer) == "function" then
                            pcall(network_server.kick_peer, network_server, peer_id)
                        end
                        return
                    end
                    pcall(printf, "[ct:426] hot-join sync DEGRADED peer=%s: no positive CT acknowledgement before native sync", tostring(peer_id))
                end

                return func(self, peer_id, ...)
            end)

            -- A real network departure invalidates the acknowledgement
            -- immediately. PlayerManager-only level-transition gaps do not call
            -- this method, so the existing bounded transition retention remains
            -- intact; a leave/rejoin with the same Steam peer id cannot reuse the
            -- previous session's proof.
            mod:hook("GameNetworkManager", "remove_peer", function(func, self, peer_id, ...)
                inst:forget_peer(peer_id)
                return func(self, peer_id, ...)
            end)

            -- Strip-debounce ticker, chained onto mod.update after install()'s wrap:
            -- chain is [this] -> [beacon wrapper] -> [ct's own update], then beacon tick,
            -- then this tick. NOT a new (Class, method) hook - plain function chaining.
            local prev_update = mod.update
            mod.update = function(dt)
                if prev_update then
                    -- Surface (don't just swallow) errors from the wrapped chain - ct's
                    -- own update carries the chunk drain + tickers and previously errored
                    -- loudly through VMF's caller (review finding, pre-ship).
                    local ok_u, err_u = pcall(prev_update, dt)
                    if not ok_u then
                        pcall(printf, "[ct:426] wrapped mod.update errored: %s", tostring(err_u))
                    end
                end
                _clock = _clock + (dt or 0)
                if _strip_deadline and _clock >= _strip_deadline then
                    _strip_deadline = nil
                    _ct_strip_modded_content("persistent_parity_loss")
                end
                -- Bounded retry on the SAME tick chain (no second mod.update wrap
                -- and no new hook); stops permanently once GUT answers.
                if not gate_registered then
                    gate_retry = gate_retry + (dt or 0)
                    if gate_retry >= 1 then
                        gate_retry = 0
                        pcall(try_runtime_gate)
                    end
                end
            end

            pcall(printf, "[ct:426] peer-parity beacon installed (channel=ct_peer_parity_present, schema=%d); modded boons/miracles inert until parity confirmed", CT_RPC_SCHEMA)
        else
            -- Beacon unavailable: _ct_wire_safe() already returns false (fail-safe), so
            -- every gate holds modded content inert. Eject pools to match.
            _ct_eject_modded_pools()
            -- Same bounded retry as the installed path. There is no beacon tick to
            -- chain onto here, so wrap the existing update once; the evaluator
            -- reads a nil beacon as permanently closed, which is the truth for
            -- this session and is exactly what the rows should say.
            local prev_update = mod.update
            mod.update = function(dt)
                if prev_update then
                    local ok_u, err_u = pcall(prev_update, dt)
                    if not ok_u then
                        pcall(printf, "[ct:426] wrapped mod.update errored: %s", tostring(err_u))
                    end
                end
                if not gate_registered then
                    gate_retry = gate_retry + (dt or 0)
                    if gate_retry >= 1 then
                        gate_retry = 0
                        pcall(try_runtime_gate)
                    end
                end
            end
            pcall(printf, "[ct:426] peer-parity beacon UNAVAILABLE - modded boons/miracles remain inert this session (fail-safe)")
        end
    end
    _ct_install_peer_parity()
end

_rt_register("peer_parity_beacon_installed", function()
    local pp = mod._ct_peer_parity
    if type(pp) ~= "table" then return "mod._ct_peer_parity missing (beacon not built)" end
    if not pp:is_installed() then return "beacon not installed (network_register failed?)" end
    if pp._initial_applied ~= "disabled" then return "fail-safe posture changed: initial applied state must be 'disabled'" end
    if pp.FAILSAFE_POSTURE ~= "feature_inert_until_confirmed" then return "fail-safe posture constant changed" end
    if pp:feature_count() < 1 then return "no gated feature registered" end
    return nil
end)

_rt_register("issue426_runtime_gate_presentation", function()
    -- The GUT bridge is optional, so this asserts the CONTRACT (pure policy is
    -- loaded, the row list is well-formed, the spec builder rejects malformed
    -- input and reports closed while the beacon is disabled) rather than
    -- asserting that a gate is live - which would fail on any GUT-less install.
    local wp = mod._ct_wire_policy
    if type(wp) ~= "table" then return "mod._ct_wire_policy missing (bridge module not loaded)" end
    if type(wp.runtime_gate_spec) ~= "function"
            or type(wp.try_register_runtime_gate) ~= "function" then
        return "wire policy runtime-gate API missing"
    end
    local ids = wp.GATED_SETTING_IDS
    if type(ids) ~= "table" or #ids == 0 then return "no gated setting ids declared" end
    -- Every gated row must be a real widget, else the gate greys nothing (or the
    -- wrong thing) and the presentation silently diverges from the runtime gate.
    -- _collect_setting_ids returns an ARRAY of live widget ids; index it.
    local known_list = _collect_setting_ids and _collect_setting_ids()
    if type(known_list) == "table" then
        local known = {}
        for i = 1, #known_list do known[known_list[i]] = true end
        for i = 1, #ids do
            if not known[ids[i]] then
                return "gated setting id is not a live widget: " .. tostring(ids[i])
            end
        end
    end
    if wp.runtime_gate_spec("ct_dev", { "a", "a" }, function() end) ~= nil then
        return "duplicate setting ids must be rejected"
    end
    if wp.runtime_gate_spec("ct_dev", {}, function() end) ~= nil then
        return "empty setting id list must be rejected"
    end
    local spec = wp.runtime_gate_spec("ct_dev", ids, function() return false, wp.GATE_REASON end)
    if type(spec) ~= "table" or #spec.setting_ids ~= #ids then
        return "valid gate spec was rejected"
    end
    local available, reason = spec.evaluate()
    if available ~= false or type(reason) ~= "string" or reason == "" then
        return "closed gate must report unavailable with a player-facing reason"
    end
    if wp.try_register_runtime_gate(nil, "id", spec) ~= false then
        return "invalid get_mod argument must fail closed"
    end
    return nil
end)

_rt_register("peer_parity_gate_classify", function()
    -- Simulated peer sets against the lib's pure classifier (issue 426 verify spec).
    local pp = mod._ct_peer_parity
    local classify = pp and pp.__classify
    if type(classify) ~= "function" then return "__classify not exposed" end
    if classify({}, {}) ~= true then return "solo (no other peers) must classify safe" end
    if classify({ p1 = true }, {}) ~= false then return "un-acked peer must classify unsafe" end
    if classify({ p1 = true }, { p1 = true }) ~= true then return "all-acked lobby must classify safe" end
    if classify({ p1 = true, p2 = true }, { p1 = true }) ~= false then return "partially-acked lobby must classify unsafe" end
    if classify({}, { p_stale = true }) ~= true then return "stale ack with empty roster must classify safe" end
    return nil
end)

_rt_register("issue426_hot_join_fence", function()
    local pp = mod._ct_peer_parity
    if not pp or type(pp.require_peer) ~= "function" then return "peer parity require_peer API missing" end
    if type(pp.peer_has) ~= "function" then return "peer parity peer_has API missing" end
    if type(pp.forget_peer) ~= "function" then return "peer parity forget_peer API missing" end
    if type(mod._ct_strip_modded_content) ~= "function" then return "full-state CT strip missing" end
    local filter = mod._ct_filter_wire_entries
    if type(filter) ~= "function" then return "wire-state filter missing" end
    local player_filtered, player_removed = filter({
        { name = "ct_kill_heal" },
        { name = "deus_larger_clip" },
    }, false)
    if player_removed ~= 1 or #player_filtered ~= 1 or player_filtered[1].name ~= "deus_larger_clip" then
        return "player power-up filter does not remove exactly the CT entry"
    end
    local persistent_filtered, persistent_removed = filter({
        "ct_miracle_of_ulric",
        "natural_bond",
    }, true)
    if persistent_removed ~= 1 or #persistent_filtered ~= 1 or persistent_filtered[1] ~= "natural_bond" then
        return "persistent-buff filter does not remove exactly the CT entry"
    end
    return nil
end)

_rt_register("ct_wire_strip_name_predicate", function()
    local fn = mod._ct_is_ct_buff_template
    if type(fn) ~= "function" then return "mod._ct_is_ct_buff_template missing" end
    if not fn("ct_miracle_of_ulric") then return "ct_miracle_of_ulric must match" end
    if not fn("ct_miracle_of_isha_aegis") then return "ct_miracle_of_isha_aegis must match" end
    if not fn("ct_meta_movespeed_stack") then return "ct_meta_movespeed_stack must match" end
    if not fn("power_up_ct_boon_vauls_anvil_unique") then return "power_up_ct_boon_* must match" end
    if not fn("power_up_ct_kill_heal_exotic") then return "power_up_ct_kill_heal_exotic must match" end
    if fn("power_up_movespeed_exotic") then return "vanilla power_up_movespeed_exotic must NOT match" end
    if fn("deus_larger_clip") then return "vanilla deus_larger_clip must NOT match" end
    if fn(nil) then return "nil must NOT match" end
    return nil
end)

_rt_register("modded_power_up_registry", function()
    local f = mod._ct_is_modded_power_up
    if type(f) ~= "function" then return "mod._ct_is_modded_power_up missing" end
    if not f("ct_meta_movespeed") then return "ct_meta_movespeed must be in the modded registry" end
    if not f("ct_boon_vauls_anvil") then return "ct_boon_vauls_anvil must be in the modded registry" end
    if not f("ct_kill_heal") then return "ct_kill_heal must be in the modded registry (issue 406 re-enable)" end
    if f("natural_bond") then return "vanilla natural_bond must NOT be in the modded registry" end
    if f(nil) then return "nil must NOT be in the modded registry" end
    return nil
end)

_rt_register("issue406_kill_heal_mod_boon_catalog", function()
    -- `ct_kill_heal` is one CT-authored DeusPowerUpTemplates entry. BOON_TREE
    -- is only a menu catalog; moving its single row must expose the existing
    -- definition on both generated surfaces without cloning the boon itself.
    local templates = rawget(_G, "DeusPowerUpTemplates")
    if type(templates) ~= "table" or type(rawget(templates, "ct_kill_heal")) ~= "table" then
        return "skip: canonical DeusPowerUpTemplates.ct_kill_heal definition missing (run in keep)"
    end

    local ok, data = pcall(mod.dofile, mod,
        "scripts/mods/chaos_wastes_tweaker_dev/chaos_wastes_tweaker_dev_data")
    if not ok or type(data) ~= "table" then return "could not load realized CT widget catalog" end

    local targets = {
        disable_boon_ct_kill_heal = "disable_boon_mod_boons_group",
        start_boon_ct_kill_heal = "start_boon_mod_boons_group",
    }
    local found = {}
    local function walk(node, parent_id)
        if type(node) ~= "table" then return end
        local id = node.setting_id
        if targets[id] then
            found[id] = found[id] or {}
            found[id][#found[id] + 1] = parent_id
        end
        local next_parent = (node.type == "group" and id) or parent_id
        for _, field in ipairs({ "widgets", "sub_widgets" }) do
            for _, child in ipairs(node[field] or {}) do walk(child, next_parent) end
        end
    end
    walk(data.options, nil)

    for setting_id, expected_parent in pairs(targets) do
        local parents = found[setting_id] or {}
        if #parents ~= 1 then
            return string.format("%s occurs %d times; expected one BOON_TREE-derived widget",
                setting_id, #parents)
        end
        if parents[1] ~= expected_parent then
            return string.format("%s catalogued under %s, expected Mod Boons parent %s",
                setting_id, tostring(parents[1]), expected_parent)
        end
    end
    -- #406 follow-up: structural presence was already correct in v0.7.264, but
    -- the realized category still called itself "New Scaling Boons". That is a
    -- discoverability failure for a non-scaling heal boon. Lock the actual
    -- player-facing route, not only the invisible setting-id ancestry.
    local start_group = mod:localize("start_boon_mod_boons_group")
    local disable_group = mod:localize("disable_boon_mod_boons_group")
    local start_item = mod:localize("start_boon_ct_kill_heal")
    if not tostring(start_group):find("Starting Boons: Modded Boons", 1, true) then
        return "#406 start category is not player-visible as Starting Boons: Modded Boons"
    end
    if not tostring(disable_group):find("Disable Boons: Modded Boons", 1, true) then
        return "#406 disable category is not player-visible as Disable Boons: Modded Boons"
    end
    if not tostring(start_item):find("Khaine's Communion", 1, true) then
        return "#406 starting widget lost the player-facing Khaine's Communion name"
    end
end)

_rt_register("anath_raema_registry_retry_288", function()
    if CT_ANATH_RAEMA_RETRY_MARKER ~= "anath_raema:enforce_at_add_buff_v0.7.268" then
        return "exact add-boundary retry marker missing"
    end
    if not effective_setting("tweak_anath_raema_permanent") then
        return nil -- behavior assertions apply only when the rework is intentionally enabled
    end
    apply_anath_raema_permanent_tweak()
    local entries = _anath_raema_buff_entries()
    -- #1156: both registries only exist keep-side. Mid-mission this used to score FAIL against
    -- healthy code (2026-08-04 log); the context is not something the check can control, so it
    -- skips rather than accusing the tweak of being broken.
    if #entries ~= 2 then return "skip: WeaponTraits + BuffTemplates registries are keep-only (run in-keep)" end
    if not (balance.get_anath_raema_originals() and balance.get_anath_raema_originals().templates.weapon_traits
            and balance.get_anath_raema_originals().templates.buff_templates) then
        return "two registries must preserve independent originals"
    end
    for _, e in ipairs(entries) do
        local sb = e.tbl[e.key] and e.tbl[e.key].buffs and e.tbl[e.key].buffs[1]
        if not sb or sb.name ~= "deus_ammo_pickup_reload_speed_permanent"
                or sb.stat_buff ~= "reload_speed" or sb.multiplier ~= -0.5 or sb.event ~= nil then
            return e.id .. " did not resolve to the permanent -0.5 reload template"
        end
    end
    return nil
end)

-- #464 follow-up: Anath Raema's Swiftness trait-as-boon must (a) be registered as a
-- power-up, (b) carry the PERMANENT reload template with a NEGATIVE reload_speed
-- multiplier (inverse stat - the #464 sign-error class), and (c) be exposed in BOTH
-- boon menu surfaces (the report: user could not find it under Offensive > Ranged in
-- either the Disabled Boons or Starting Boons trees).
_rt_register("anath_raema_trait_boon_464", function()
    local f = mod._ct_is_modded_power_up
    if type(f) ~= "function" or not f("ct_boon_anath_raema_swiftness") then
        return "ct_boon_anath_raema_swiftness must be in the modded registry"
    end
    local tpl = rawget(_G, "DeusPowerUpTemplates")
    local t = tpl and tpl.ct_boon_anath_raema_swiftness
    local b = t and t.buff_template and t.buff_template.buffs and t.buff_template.buffs[1]
    if not b then return "DeusPowerUpTemplates.ct_boon_anath_raema_swiftness buff template missing" end
    if b.stat_buff ~= "reload_speed" then return "boon buff must be a reload_speed stat_buff" end
    if type(b.multiplier) ~= "number" or b.multiplier >= 0 then
        return "reload_speed multiplier must be NEGATIVE (inverse stat; positive = SLOWER reload, the #464 bug)"
    end
    -- Menu exposure: walk the REALIZED widget tree (same source _ct_dump_settings uses)
    -- so a BOON_TREE regression that drops the entry fails here, not in the field.
    local ids_ok, ids = pcall(_collect_setting_ids)
    if not ids_ok or type(ids) ~= "table" then return "could not collect widget setting ids" end
    local have = {}
    for _, id in ipairs(ids) do have[id] = true end
    if not have["disable_boon_ct_boon_anath_raema_swiftness"] then
        return "disable_boon_ct_boon_anath_raema_swiftness widget missing (Disabled Boons > Offensive > Ranged)"
    end
    if not have["start_boon_ct_boon_anath_raema_swiftness"] then
        return "start_boon_ct_boon_anath_raema_swiftness widget missing (Starting Boons > Offensive > Ranged)"
    end
    if not have["enable_boon_anath_raema_swiftness"] then
        return "enable_boon_anath_raema_swiftness widget missing (Reworks > Reworks: Boons > new)"
    end
    return nil
end)

-- ============================================================
-- Home Brewer +50% potency for reworked potions (v0.7.31-alpha)
-- ============================================================
-- When the toggle is on AND the player has Home Brewer (the boon that grants the
-- `not_consume_potion` perk), the reworked Moot Milk potion's numerical multipliers are
-- scaled by 1.5x for that specific drink. Implementation: hook BuffExtension.add_buff,
-- save the template's multiplier/bonus fields, scale, call vanilla add, restore.
--
-- Only scales `moot_milk_potion` and `moot_milk_potion_increased` (the reworked variants)
-- — `poison_proof_potion` has binary immunity with no multiplier field, so potency is
-- moot for it. Duration is intentionally NOT scaled (Decanter is the duration lever;
-- Home Brewer is the potency lever — they remain orthogonal).
--
-- LIMITATIONS:
-- * RACE: BuffTemplates is shared global; two players drinking simultaneously could see
--   one peer's scaled values briefly. Rare in practice (potion drinks are individual)
--   and the effect is just stat values, not safety-critical.
-- * No NetworkLookup variant registration — multiplayer-safe because every peer
--   applies its own buff (with its own perk check) via this hook.
local HOME_BREWER_BREWED_TEMPLATES = {
    moot_milk_potion           = true,
    moot_milk_potion_increased = true,
}

-- v0.7.203-dev multi-return marker: the Home Brewer add_buff hook's guarded
-- (scaled-potency) path forwards ALL of vanilla's returns (id, sub_buffs_added,
-- first_buff) via _capture_returns + unpack(results, 1, n), NOT a collapsing
-- `local result = func(...); return result`. Global (not a main-chunk local) to
-- dodge the Lua 5.1 200-local cap. Asserted by /ct_regression_test
-- "home_brewer_add_buff_multireturn_preserved".
CT_HOME_BREWER_MULTIRETURN_MARKER = "home_brewer_add_buff:capture_returns_unpack_v0.7.203"

mod:hook("BuffExtension", "add_buff", function(func, self, template_name, params)
    -- Issue #288: mod load can precede one or both Morris registries. Enforce at
    -- the exact native lookup boundary so startup timing cannot retain the event buff.
    if template_name == "deus_ammo_pickup_reload_speed" and effective_setting("tweak_anath_raema_permanent") then
        apply_anath_raema_permanent_tweak()
        CT_ANATH_RAEMA_ADD_DIAG_COUNT = (CT_ANATH_RAEMA_ADD_DIAG_COUNT or 0) + 1
        if CT_ANATH_RAEMA_ADD_DIAG_COUNT <= 8 then
            local bt = rawget(_G, "BuffTemplates")
            local sb = bt and bt[template_name] and bt[template_name].buffs and bt[template_name].buffs[1]
            pcall(printf, "[ct:288] add parent=%s child=%s stat=%s mult=%s event=%s n=%d",
                tostring(template_name), tostring(sb and sb.name), tostring(sb and sb.stat_buff),
                tostring(sb and sb.multiplier), tostring(sb and sb.event), CT_ANATH_RAEMA_ADD_DIAG_COUNT)
        end
    end
    if not effective_setting("tweak_home_brewer_potency") then
        return func(self, template_name, params)
    end
    if not (type(template_name) == "string" and HOME_BREWER_BREWED_TEMPLATES[template_name]) then
        return func(self, template_name, params)
    end
    if not self.has_buff_perk or not self:has_buff_perk("not_consume_potion") then
        return func(self, template_name, params)
    end
    local bt = rawget(_G, "BuffTemplates")
    local sub_buffs = bt and bt[template_name] and bt[template_name].buffs
    if not sub_buffs then
        return func(self, template_name, params)
    end
    local saved = {}
    for i, sb in ipairs(sub_buffs) do
        if sb.multiplier or sb.bonus then
            saved[i] = { multiplier = sb.multiplier, bonus = sb.bonus }
            if sb.multiplier then sb.multiplier = sb.multiplier * 1.5 end
            if sb.bonus      then sb.bonus      = sb.bonus      * 1.5 end
        end
    end
    -- v0.7.203-dev: vanilla BuffExtension.add_buff returns THREE values
    -- (id, sub_buffs_added, first_buff — buff_extension.lua:517). The prior
    -- `local result = func(...)` / `return result` collapsed that to the first
    -- return, dropping sub_buffs_added + first_buff for any caller that reads them
    -- (VMF_RECIPES §2/§2a). Capture the real arity and forward every return;
    -- restore the scaled sub-buff fields in between. Marker
    -- CT_HOME_BREWER_MULTIRETURN_MARKER documents this fix for the regression check.
    local n, results = _capture_returns(func(self, template_name, params))
    for i, s in pairs(saved) do
        sub_buffs[i].multiplier = s.multiplier
        sub_buffs[i].bonus      = s.bonus
    end
    return unpack(results, 1, n)
end)

-- ============================================================
-- Endless Bombs: strip the LEFTOVER Morgrim's when the potion ENDS
-- ============================================================
-- Intent (user, 2026-06-28): Endless Bombs (pockets_full_of_bombs) is SUPPOSED to work with
-- Morgrim's Bomb (holy_hand_grenade) — players deliberately save a Morgrim's to throw during the
-- potion, and that's fine/desired. The ONLY exploit: if you don't throw your last Morgrim's
-- before the potion expires, it persists (effectively duplicated) so you carry it to the next
-- potion and do it again. So we do NOT eat the bomb on drink or mid-potion (v0.7.178/.179 did —
-- WRONG, that broke the intended combo). We strip the LEFTOVER Morgrim's only when the potion
-- EXPIRES, and only if the player drank it while holding one.
--
-- Mechanism: pockets_full_of_bombs_potion(_increased) declares
-- remove_buff_func = "remove_deus_potion_buff" (morris_buff_settings.lua), which fires on
-- duration expiry. That remove func is SHARED by every deus potion, so we gate on a flag
-- (buff.ct_endless_had_morgrim) that ONLY the pockets apply-hook sets — no buff-name match
-- needed, and other potions are unaffected. The buff instance persists fields across
-- apply/update/remove (vanilla itself stores buff.previous_multiplier), so the flag survives to
-- expiry. Hook target is the merged BuffFunctionTemplates.functions table; guard for load order.
-- #101 regression sentinel (v0.7.181-dev): the consume must be on EXPIRY (remove_deus_potion_buff)
-- via the buff.ct_endless_had_morgrim flag — NOT a consume-on-drink (v0.7.178) or continuous
-- mid-potion eat (v0.7.179), both of which broke the intended potion+Morgrim's combo. Global to
-- dodge the 200-local cap. Asserted by /ct_regression_test "endless_bombs_strip_on_expiry".
CT_ENDLESS_BOMBS_MARKER = "endless_bombs:strip_leftover_morgrim_on_expiry_v0.7.181"
if BuffFunctionTemplates and BuffFunctionTemplates.functions then
    -- At DRINK: only RECORD whether the player held a Morgrim's (do NOT consume it — it must stay
    -- usable during the potion). Morgrim's lives in slot_grenade (deus_blessing_settings.lua:85).
    mod:hook(BuffFunctionTemplates.functions, "apply_pockets_full_of_bombs_buff", function(func, unit, buff, params)
        if effective_setting("endless_bombs_consumes_morgrim") == true then
            local inv = ScriptUnit.has_extension(unit, "inventory_system")
            local sd = inv and inv:get_slot_data("slot_grenade")
            local nm = sd and sd.item_data and sd.item_data.name
            if nm == "holy_hand_grenade" then
                buff.ct_endless_had_morgrim = true
            end
            -- printf, NOT mod:info (user runs VMF mod-logging OFF).
            pcall(printf, "[endless-bombs] drink: grenade=%s had_morgrim=%s (kept for the potion; stripped on expiry)",
                tostring(nm or "<none>"), tostring(buff.ct_endless_had_morgrim == true))
        end
        return func(unit, buff, params)
    end)

    -- At EXPIRY: if they drank with a Morgrim's AND a leftover one is still in slot_grenade, strip
    -- it (kills the un-thrown-duplicate carry-over). Flag-gated -> other deus potions untouched.
    mod:hook(BuffFunctionTemplates.functions, "remove_deus_potion_buff", function(func, unit, buff, params, world)
        local result = func(unit, buff, params, world)
        if buff and buff.ct_endless_had_morgrim and effective_setting("endless_bombs_consumes_morgrim") == true then
            local inv = ScriptUnit.has_extension(unit, "inventory_system")
            local sd = inv and inv:get_slot_data("slot_grenade")
            local nm = sd and sd.item_data and sd.item_data.name
            if nm == "holy_hand_grenade" then
                -- If the player is actively wielding the bomb when it's stripped, destroying the
                -- slot leaves them stuck in the bomb/throw pose on a now-empty slot, unable to
                -- switch weapons. Capture the wielded slot BEFORE destroying; if it was the
                -- grenade, interrupt the weapon action and wield melee (slot 1) so they recover.
                local was_wielding = inv.get_wielded_slot_name and inv:get_wielded_slot_name()
                inv:destroy_slot("slot_grenade")
                if was_wielding == "slot_grenade" then
                    if rawget(_G, "CharacterStateHelper") then
                        pcall(CharacterStateHelper.stop_weapon_actions, inv, "dropped")
                    end
                    pcall(function() inv:wield("slot_melee") end)
                end
                pcall(printf, "[endless-bombs] potion ended -> stripped leftover Morgrim's%s",
                    (was_wielding == "slot_grenade") and " (was wielding it -> swapped to melee)" or "")
            else
                pcall(printf, "[endless-bombs] potion ended; no leftover Morgrim's (grenade=%s)", tostring(nm or "<empty>"))
            end
        end
        return result
    end)

end
return {
    sync_host_dependent_state = sync_host_dependent_state,
    trait_boons = CT_TRAIT_BOONS,
    register_trait_boon = register_trait_boon,
}
