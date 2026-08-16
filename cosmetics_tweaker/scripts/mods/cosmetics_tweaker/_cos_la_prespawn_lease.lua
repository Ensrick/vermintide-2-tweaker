-- _cos_la_prespawn_lease.lua -- pre-spawn parent-package lease for the four
-- traced LA units (#696).
--
-- Log #940 proved the invariant MeshObject warnings fire at NATIVE spawn time,
-- BEFORE Material-Hijack's traced Unit.set_material brackets ([cos:696]
-- bind-start/bind-end), for exactly these resolved unit paths: the LA message
-- board (units/decorations/LA_message_board_mesh), its back board
-- (units/decorations/LA_message_board_back_board), the visible quest letter
-- (units/decorations/letters/LA_quest_message_stage01_visable) and the Kruber
-- Empire shield02 pair (units/empire_shield/Kruber_Empire_shield02_mesh[_3p]).
-- The warned material IDs are the murmur64 upper-32 hashes of the AUTHORED
-- slot names, verified 2026-08-16: 5a0213f3 = "LA_message_board_texture",
-- 6e98026a = "LA_message_board_papers_texture", c61ad6e5 = "shield"
-- (b6d0945a = "rifle_mat" stays under #742).
--
-- This module implements #696 path 1: queue ONE bounded session lease per
-- declared vanilla parent material package for those exact unit paths, at the
-- all-mods-loaded edge -- well before the keep spawns the decorations -- so
-- the parent material closure is resident when the engine constructs those
-- units' MeshObjects. Valid binds are untouched: nothing here substitutes,
-- suppresses, or reorders any material bind; the lease is a ref-count pin.
--
-- Safety contract (inherited from _cos_la_gate_recovery.lua / cwv #474):
--   * only DECLARED vanilla packages are leased: the Breton black_and_gold
--     skin package is vanilla's own material_changes.package_name
--     [src: scripts/settings/dlcs/lake/cosmetics_lake.lua:36] and the shield
--     donors are per-unit units/weapons/player/... packages (the proven
--     cwv lease class); mod-bundled/third-party packages are NEVER leased
--     (async C-level fatal past pcall, gut GUID ca939793);
--   * every lease is preflighted with Application.can_get("package", ...) and
--     skipped (receipt, no crash) when the resource is absent;
--   * one lease attempt per package per session; the reference is held for
--     the session (PackageManager.destroy releases it, #282 rationale);
--   * leases queue only when Loremaster's Armoury is actually present -- the
--     traced units cannot spawn without it.
--
-- Owned by: _material_hijack_embedded.lua (the owner of the
-- UnitSpawner.spawn_local_unit seam and the [cos:696] bind trace).
-- Consumed via: mod:dofile(...).new(deps) -- pure factory, offline-testable
-- (qa/lua/tests/test_cos_la_prespawn_lease.lua).

local M = {}

M.LEASE_REF = "cosmetics_tweaker_prespawn_696"
M.MAX_RECEIPTS = 24

-- Vanilla parent of the message-board/letter mat_to_use material
-- (mtr_outfit_black_and_gold_3p): the skin package vanilla itself loads for
-- the Questing Knight black_and_gold outfit [cosmetics_lake.lua:36-38].
M.BRETON_SKIN_PACKAGE =
    "units/beings/player/empire_soldier_breton/skins/black_and_gold/chr_empire_soldier_breton_black_and_gold"

-- Resolved unit path (log #940 trace, verbatim) -> declared vanilla parent
-- material packages that must be resident before that unit spawns.
M.UNIT_PARENT_PACKAGES = {
    ["units/decorations/LA_message_board_mesh"] = { M.BRETON_SKIN_PACKAGE },
    ["units/decorations/LA_message_board_back_board"] = { M.BRETON_SKIN_PACKAGE },
    ["units/decorations/letters/LA_quest_message_stage01_visable"] = { M.BRETON_SKIN_PACKAGE },
    ["units/empire_shield/Kruber_Empire_shield02_mesh"] = {
        "units/weapons/player/wpn_empire_handgun_02_t2/wpn_empire_handgun_02_t2",
    },
    ["units/empire_shield/Kruber_Empire_shield02_mesh_3p"] = {
        "units/weapons/player/wpn_empire_handgun_02_t2/wpn_empire_handgun_02_t2_3p",
    },
}

-- deps:
--   package_manager() -> Managers.package or nil (resolved per call)
--   can_get(kind, path) -> preflight (Application.can_get); nil dep = allow
--   la_present() -> true when Loremaster's Armoury is loaded
--   log(fmt, ...) -> engine printf-style logger
function M.new(deps)
    deps = deps or {}
    local attempted = {}       -- package -> verdict (one lease attempt/session)
    local observed = {}        -- unit path -> true (bounded observe receipts)
    local receipts = 0

    local api = {}

    local function _log(fmt, ...)
        if receipts >= M.MAX_RECEIPTS then return end
        if type(deps.log) ~= "function" then return end
        receipts = receipts + 1
        deps.log(fmt, ...)
    end

    local function _package_gettable(pkg)
        if type(deps.can_get) ~= "function" then return true end
        local ok, gettable = pcall(deps.can_get, "package", pkg)
        return ok and gettable == true
    end

    local function _lease_one(pkg)
        if attempted[pkg] then return "held" end
        if not _package_gettable(pkg) then
            attempted[pkg] = "not-gettable"
            return "not-gettable"
        end
        local manager = type(deps.package_manager) == "function"
            and deps.package_manager() or nil
        if type(manager) ~= "table" or type(manager.load) ~= "function" then
            return "no-manager"   -- retryable: not recorded as attempted
        end
        -- cwv donor-lease arg shape (_cwv_husk_path.lua:405):
        -- (name, reference, callback=nil, asynchronous, prioritize).
        local ok = pcall(manager.load, manager, pkg, M.LEASE_REF, nil, true, true)
        attempted[pkg] = ok and "queued" or "error"
        return attempted[pkg]
    end

    -- Queue the session leases for every declared parent package. Called at
    -- the all-mods-loaded edge (and again from the spawn observer as a
    -- belt-and-suspenders retry if the manager was unavailable at boot).
    function api.lease_all()
        local verdicts = {}
        if type(deps.la_present) == "function" and not deps.la_present() then
            _log("[cos:696] pre-spawn lease skipped: Loremaster's Armoury not present")
            return verdicts, "la-absent"
        end
        local seen = {}
        for _, packages in pairs(M.UNIT_PARENT_PACKAGES) do
            for _, pkg in ipairs(packages) do
                if not seen[pkg] then
                    seen[pkg] = true
                    local previous = attempted[pkg]
                    local verdict = _lease_one(pkg)
                    verdicts[pkg] = verdict
                    if verdict ~= "held" or previous == nil then
                        _log("[cos:696] pre-spawn lease pkg=%s verdict=%s ref=%s",
                            pkg, verdict, M.LEASE_REF)
                    end
                end
            end
        end
        return verdicts, "leased"
    end

    -- Spawn-boundary observer: for a traced unit path, record (once, bounded)
    -- whether its parent packages were resident BEFORE this spawn. Pure
    -- diagnostics -- never blocks or reorders the spawn.
    --   has_loaded(pkg) -> engine PackageManager.has_loaded flag via deps.
    function api.observe_spawn(unit_name)
        local packages = type(unit_name) == "string"
            and M.UNIT_PARENT_PACKAGES[unit_name] or nil
        if not packages then return nil end
        if observed[unit_name] then return "observed" end
        observed[unit_name] = true
        for _, pkg in ipairs(packages) do
            local resident = false
            if type(deps.has_loaded) == "function" then
                local ok, flag = pcall(deps.has_loaded, pkg)
                resident = ok and flag == true
            end
            _log("[cos:696] pre-spawn observe unit=%s pkg=%s resident=%s lease=%s",
                tostring(unit_name), pkg, tostring(resident),
                tostring(attempted[pkg] or "not-attempted"))
            if not attempted[pkg] then
                -- Late-heal: LA appeared after boot or the boot lease found no
                -- manager. Too late for THIS spawn; the session still heals.
                _lease_one(pkg)
            end
        end
        return "recorded"
    end

    function api.debug_state()
        return { attempted = attempted, observed = observed }
    end

    return api
end

return M
