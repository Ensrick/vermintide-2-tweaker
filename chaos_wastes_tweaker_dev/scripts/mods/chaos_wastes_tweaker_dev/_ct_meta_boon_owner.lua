-- _ct_meta_boon_owner.lua — CT-authored scaling boons and ammo behavior.
-- Loaded synchronously by `_ct_meta_trait_boons.lua` after the balance and
-- registry owners. The installer owns all registration side effects here;
-- callers must invoke it exactly once and allow dependency errors to propagate.

return function(mod, deps)
    if type(deps) ~= "table" then
        error("[ct:meta-boons] missing dependency table")
    end

    local context = deps.context
    local registry = deps.registry
    if type(context) ~= "table" or type(registry) ~= "table" then
        error("[ct:meta-boons] context/registry dependencies are required")
    end

    local _dbg = context.dbg
    local effective_setting = context.effective_setting
    local MOD_VERSION = context.mod_version
    local _ct_meta_ammo_cost_multiplier = context.meta_ammo_cost_multiplier
    local CT_META_AMMO_CAP = context.meta_ammo_cap
    local CT_META_AMMO_FLOOR = context.meta_ammo_floor
    local CT_META_AMMO_HYPERBOLIC_MARKER = context.meta_ammo_marker
    local CT_META_AMMO_MAX_STACKS = context.meta_ammo_max_stacks
    local CT_META_AMMO_STEP = context.meta_ammo_step

    local inject_dormant_boon = registry.inject_dormant_boon
    local _add_dormant_to_pool = registry.add_dormant_to_pool
    local register_buff_in_network_lookup = registry.register_buff_in_network_lookup

    -- issues 249/256/289 (v0.7.298-dev): engine-free grant/clamp policy kernel.
    -- Pure module (loadfile-safe) so qa/lua tests drive the exact shipped logic.
    local AmmoGuardCore = mod:dofile("scripts/mods/chaos_wastes_tweaker_dev/_ct_ammo_guard_core")
    CT_META_AMMO_SERVER_AUTH_MARKER = AmmoGuardCore.MARKER
    mod._ct_ammo_guard_core = AmmoGuardCore

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


    return true
end
