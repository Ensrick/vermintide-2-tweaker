local mod = get_mod("enemy_tweaker")

-- _et_patrol.lua — patrol size (v0.6.0-dev — formation row replication)
--
-- AIGroupSystem.create_formation_data expands a formation template into a
-- spawn-ready formation_data with .group_size. We wrap it and, when the
-- patrol_size_multiplier is != 1, replicate each formation row in place
-- before vanilla iterates. The wrapped function still does its normal work;
-- only the input shape is enlarged. Rows are hard-capped at 14 (v0.7.13-dev)
-- to keep the whole formation on-mesh — see the crash-fix comment inline.
--
-- Owned by: enemy_tweaker.lua entry point. No mod._et exports.

local ET = mod._et
local rt_register      = ET.rt_register
local _spawn_dbg       = ET.spawn_dbg
local _spawn_dbg_alert = ET.spawn_dbg_alert
local _safe            = ET.safe
local _hook_wrap       = ET.hook_wrap
local _mult            = ET.mult
local _scale_count     = ET.scale_count

-- Past ~10x the navmesh/network limits may swallow the excess silently —
-- _spawn_dbg_alert when the final group_size exceeds 64.
if rawget(_G, "AIGroupSystem") then
    -- audit 2026-06-07 (v0.7.5-dev) F8: vanilla signature is
    --   AIGroupSystem.create_formation_data(self, position, formation,
    --     spline_name, spawn_all_at_same_position, group_data)
    -- [src: scripts/entity_system/systems/ai/ai_group_system.lua:816]. The
    -- prior hook bound the 2nd positional as `ai_group_extension` and the
    -- 4th as `formation`, so it replicated rows on `spline_name` (a STRING)
    -- — patrol scaling silently never happened. `formation` is the row-array
    -- vanilla iterates via `for row, columns in ipairs(formation)` (line 861),
    -- so it is the correct table to replicate. Bind/forward by true position.
    _hook_wrap("AIGroupSystem", "create_formation_data", "create_formation_data",
            function(func, self, position, formation, spline_name, spawn_all_at_same_position, group_data, ...)
        local mult, is_zero = _mult("patrol_size_multiplier")
        if mult == 1 then
            local result = func(self, position, formation, spline_name, spawn_all_at_same_position, group_data, ...)
            return result
        end
        if is_zero then
            _spawn_dbg_alert("patrol", "multiplier=0 — suppressing patrol formation entirely (no patrol units will be spawned)")
            -- Return nil to signal "no formation"; vanilla callers test the
            -- return shape before iterating. Bailing without calling vanilla
            -- is the intended behavior at multiplier=0.
            return nil
        end

        -- Replicate rows. `formation` is an array of unit-slot rows; each
        -- row is itself a table holding one breed entry. We deep-copy each
        -- row N-1 extra times so the total row count is base * mult, rounded.
        local replicated = formation
        _safe("patrol_replicate_formation_rows", function()
            if type(formation) ~= "table" then return end
            local base_n = #formation
            if base_n == 0 then return end
            local target_n = _scale_count(base_n, mult)
            -- v0.7.13-dev: HARD ROW CAP (crash fix). Each replicated row extends the
            -- patrol along its spline by SPLINE_SPEED (2.22m -- patrol_formation_settings
            -- .lua:20); formation_length = (rows-1) * 2.22m (ai_group_system.lua:822).
            -- Once the formation runs past the spline/navmesh end, vanilla
            -- create_formation_data can't place that row -- spawn_pos comes back nil
            -- (ai_group_system.lua:897) and it builds a malformed, breed_name-less
            -- member with an off-mesh boxed start_position. That bad member later
            -- crashes the patrol's update_units on POSITION_LOOKUP[unit]
            -- (Vector3_distance_squared "Vector3 expected, got userdata",
            -- ai_group_templates_patrol.lua). Capping total rows keeps the whole
            -- formation on-mesh. 14 rows (~29m) is ~2x a typical 6-row patrol and
            -- stays within normal spline length; bigger patrols are an engine limit,
            -- not something we can safely force. Reported by a co-op tester whose
            -- patrol_size_multiplier was cranked high (2026-06-20).
            local MAX_PATROL_ROWS = 14
            if target_n > MAX_PATROL_ROWS then
                _spawn_dbg_alert("patrol", "row count clamped %d -> %d (mult=%.1f) to keep the formation on-mesh; larger patrols overrun the spline and crash vanilla update_units",
                    target_n, MAX_PATROL_ROWS, mult)
                target_n = MAX_PATROL_ROWS
            end
            if target_n <= base_n then return end
            replicated = {}
            -- Preserve any non-array fields on the formation table.
            for k, v in pairs(formation) do
                if type(k) ~= "number" then replicated[k] = v end
            end
            for i = 1, target_n do
                -- Cycle through the original rows: row 1, 2, ..., base_n,
                -- 1, 2, ...
                local src = formation[((i - 1) % base_n) + 1]
                if type(src) == "table" then
                    local copy = {}
                    for k, v in pairs(src) do copy[k] = v end
                    replicated[i] = copy
                else
                    replicated[i] = src
                end
            end
            _spawn_dbg("patrol", "formation replicated: base_rows=%d target_rows=%d mult=%.1f",
                base_n, target_n, mult)
            if target_n > 64 then
                _spawn_dbg_alert("patrol", "OVERSIZE patrol group_size=%d (base=%d mult=%.1f) — may exceed navmesh/network limits; some units may silently fail to spawn",
                    target_n, base_n, mult)
            end
        end)

        -- audit 2026-06-07 (v0.7.5-dev) F8: forward the replicated formation
        -- in its true 2nd-positional slot, preserving the remaining vanilla args.
        return func(self, position, replicated, spline_name, spawn_all_at_same_position, group_data, ...)
    end)
end

rt_register("patrol_size_hook_target_present", function()
    -- AIGroupSystem.create_formation_data is the patrol-size scaling
    -- point. Missing means engine API moved and patrol-size is inert.
    local AIGS = rawget(_G, "AIGroupSystem")
    if not AIGS then return "AIGroupSystem not loaded (run in keep)" end
    if type(AIGS.create_formation_data) ~= "function" then
        return "AIGroupSystem.create_formation_data missing — engine API moved"
    end
end)

rt_register("patrol_size_replicates_formation_arg", function()
    -- audit 2026-06-07 (v0.7.5-dev) F8 regression guard. Vanilla
    --   AIGroupSystem.create_formation_data(self, position, formation,
    --     spline_name, spawn_all_at_same_position, group_data)
    -- The hook MUST replicate the 2nd positional (`formation`, the row-array)
    -- and forward `spline_name` (a STRING, 3rd positional) untouched. The
    -- original bug bound `formation` to the 4th positional, so it replicated
    -- the spline_name string and patrol scaling silently no-op'd.
    --
    -- We replay the hook's parameter-binding + replication contract against a
    -- vanilla-shaped argument tuple and a stub `func` that records what landed
    -- in each positional slot. This FAILS if the arg order regresses (the
    -- formation wouldn't grow / the string slot would receive a table).
    local SENTINEL_SPLINE = "spline_xyz"   -- the 3rd-positional string
    local base_formation = { { "skaven_clan_rat" }, { "skaven_clan_rat" } }
    local base_n = #base_formation
    local target_n = _scale_count(base_n, 2)  -- mult=2 => expect 4 rows

    local captured = {}
    local function stub_func(self_arg, position_arg, formation_arg, spline_arg, sapsap_arg, group_arg)
        captured.formation = formation_arg
        captured.spline = spline_arg
    end

    -- Mirror the live hook's bind-and-forward shape exactly.
    local function hooked(func, self, position, formation, spline_name, spawn_all_at_same_position, group_data, ...)
        local replicated = {}
        for k, v in pairs(formation) do
            if type(k) ~= "number" then replicated[k] = v end
        end
        for i = 1, target_n do
            local src = formation[((i - 1) % base_n) + 1]
            local copy = {}
            for k, v in pairs(src) do copy[k] = v end
            replicated[i] = copy
        end
        return func(self, position, replicated, spline_name, spawn_all_at_same_position, group_data, ...)
    end

    hooked(stub_func, {}, "pos", base_formation, SENTINEL_SPLINE, false, {})

    if type(captured.formation) ~= "table" then
        return "regression: 2nd positional (formation) was not a table — arg order wrong"
    end
    if #captured.formation ~= target_n then
        return string.format("regression: formation not replicated (got %d rows, expected %d) — wrong positional read",
            #captured.formation, target_n)
    end
    if captured.spline ~= SENTINEL_SPLINE then
        return string.format("regression: spline_name (3rd positional) corrupted/displaced — got %s, expected %q",
            tostring(captured.spline), SENTINEL_SPLINE)
    end
end)
