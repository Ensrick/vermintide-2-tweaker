-- ============================================================
-- Mutex checkbox cluster framework
-- ============================================================
-- Pattern for declaring "pick one of N alternatives" UI groups using
-- VMF's native `checkbox` widget. VMF has no radio/multi-choice
-- widget; `dropdown` truncates labels and provides no per-option
-- tooltip. The checkbox cluster gets you full localized labels + full
-- multi-line tooltips per alternative at the cost of one enforcer
-- call from `on_setting_changed`.
--
-- Defaults convention: every member of a cluster defaults to `false`
-- (= vanilla / unmodified behavior). Toggling one on triggers the
-- enforcer, which programmatically unchecks its siblings.
--
-- Standard reference: see `LOCALIZATION_STANDARD.md` § "Mutex cluster
-- pattern" at the repo root for the full convention (group labels,
-- tooltip phrasing, naming).
--
-- Why a separate file: the cluster table is data, and the enforcer
-- is a tiny pure function — keeping them out of the main mod file
-- avoids visual noise in `chaos_wastes_tweaker_dev.lua` and lets future mods
-- copy the helper verbatim if they want the same pattern.

local mod = get_mod("ct_dev")

local M = {}

-- Cluster table:
--   group_id -> { setting_id_1, setting_id_2, ..., setting_id_N }
-- Populated by `M.declare(group_id, members)` at module-load time
-- below. Read by `M.enforce(setting_id)` on every setting change.
--
-- Why we key by `group_id` and not just dump everything into a flat
-- list: the group_id is the logical name of the choice (e.g.
-- "bh_passive_choice"), and grouping aids both debugging (the enforcer
-- can log "mutex group X fired") and future tooling (e.g. a dump
-- command that lists every mutex group + current selection).
M.CLUSTERS = {}

-- Re-entry guard. When `mod:set(other, false)` fires inside `enforce`,
-- VMF re-fires `on_setting_changed(other)`, which calls back into
-- `enforce`. Without the guard we'd recurse N times and possibly
-- corrupt state. With it, the recursive `enforce` call short-circuits
-- on entry. Set/cleared around the actual `mod:set` loop.
local _enforcing = false

-- Declare a mutex cluster. Call from module load (top-of-file in the
-- main mod script, near where existing widget tables live).
--
-- Args:
--   group_id : string  -- short logical name, used for telemetry / dump
--   members  : table   -- array of setting_id strings (≥2)
--
-- Idempotent: re-declaring the same group_id silently overwrites.
function M.declare(group_id, members)
    if type(group_id) ~= "string" or group_id == "" then
        mod:warning("[mutex] declare: group_id must be a non-empty string (got %s)", tostring(group_id))
        return
    end
    if type(members) ~= "table" or #members < 2 then
        mod:warning("[mutex] declare: group %q needs >=2 members (got %d)", group_id, members and #members or 0)
        return
    end
    M.CLUSTERS[group_id] = members
end

-- Enforce single-select for the cluster containing `setting_id`. No-op
-- if `setting_id` is not in any cluster, or if its new value is false
-- (= vanilla; nothing to deselect), or if we're already inside an
-- enforcement pass.
--
-- Call from the main mod's `on_setting_changed` dispatcher.
function M.enforce(setting_id)
    if _enforcing then return end
    if not setting_id or not mod:get(setting_id) then return end

    for group_id, members in pairs(M.CLUSTERS) do
        for _, m in ipairs(members) do
            if m == setting_id then
                _enforcing = true
                for _, other in ipairs(members) do
                    if other ~= setting_id and mod:get(other) then
                        mod:set(other, false)
                        mod:info("[mutex] group %q: %s -> false (mutex with %s)", group_id, other, setting_id)
                    end
                end
                _enforcing = false
                return
            end
        end
    end
end

-- Diagnostic: returns the active member of a cluster, or nil if all
-- members are unchecked (= vanilla). Useful for /cw_status or a
-- future dump command.
function M.active(group_id)
    local members = M.CLUSTERS[group_id]
    if not members then return nil end
    for _, m in ipairs(members) do
        if mod:get(m) then return m end
    end
    return nil
end

-- Diagnostic: returns the full cluster -> active-member map.
function M.snapshot()
    local out = {}
    for group_id, _ in pairs(M.CLUSTERS) do
        out[group_id] = M.active(group_id)
    end
    return out
end

return M
