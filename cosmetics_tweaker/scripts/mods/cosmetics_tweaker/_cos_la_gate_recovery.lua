-- Bounded-lease recovery for fail-closed LA preview refusals (#481).
--
-- The #617/#742/#749 gates fail closed by design: a refused paint or override
-- keeps the resident base presentation for THIS attempt. What was missing
-- (issue #481 audit 2026-08-03) is recovery: nothing leased the missing owner
-- after a refusal, so a failed shield stayed base/invisible all session.
--
-- Donor recipe: character_weapon_variants _cwv_husk_path.lua (#474) --
-- fail-closed residency plus ONE bounded Managers.package:load lease of the
-- refused variant's declared VANILLA parent package, so a later attempt
-- resolves. Two hard safety rules are structural here:
--
--   * Only vanilla per-unit weapon packages (units/weapons/player/...) are
--     ever leased. Fatshark ships those as loadable per-unit packages (cwv
--     #403 nuance, BUG_CLASSES 28). A mod-bundled or third-party package
--     (LA's own bundle included) is NEVER leased: force-loading a non-resident
--     package whose bundle we do not control is an async C-level fatal that
--     bypasses pcall (gut v0.2.53 crash GUID ca939793).
--   * One lease attempt per owner package per session. The lease reference is
--     held for the session (same lifetime as cwv's HUSK_OVERRIDE_REF donor
--     lease); it is a ref-count pin, not a per-previewer resource.
--
-- Every refusal also emits a bounded printf marker naming WHICH gate refused,
-- so a log alone answers "which gate ate the shield" without debug mode.
local M = {}

M.SAFE_LEASE_PREFIX = "units/weapons/player/"
M.LEASE_REF = "cosmetics_tweaker_gate_recovery_481"
M.MAX_MARKERS = 64

-- deps:
--   owner_package(armoury_key) -> declared vanilla parent package or nil
--   package_manager()          -> Managers.package or nil (resolved per call)
--   log(fmt, ...)              -> engine printf-style logger
function M.new(deps)
    deps = deps or {}
    local attempted = {}      -- owner package -> true (session-bounded lease)
    local marked = {}         -- gate .. "|" .. key -> true (bounded markers)
    local marked_count = 0

    local api = {}

    -- Records the refusal and, when the refused gate's missing owner is a
    -- declared lease-safe vanilla package, queues exactly one recovery lease.
    -- Returns the recovery verdict plus the owner considered (for tests).
    -- `allow_lease=false` marks gates whose missing owner is NOT the declared
    -- vanilla parent (e.g. LA-bundle textures/units): marker only, no lease.
    function api.recover(gate, armoury_key, context, reason, allow_lease)
        local owner = type(deps.owner_package) == "function"
            and deps.owner_package(armoury_key) or nil
        if type(owner) ~= "string" or owner == "" then owner = nil end

        local verdict
        if allow_lease == false then
            verdict = "lease-not-applicable"
        elseif not owner then
            verdict = "no-owner"
        elseif owner:find(M.SAFE_LEASE_PREFIX, 1, true) ~= 1 then
            verdict = "unsafe-owner"
        elseif attempted[owner] then
            verdict = "lease-held"
        else
            local manager = type(deps.package_manager) == "function"
                and deps.package_manager() or nil
            if type(manager) ~= "table" or type(manager.load) ~= "function" then
                verdict = "no-manager"
            else
                attempted[owner] = true
                -- cwv donor-lease arg shape (_cwv_husk_path.lua:405):
                -- (name, reference, callback=nil, asynchronous, prioritize).
                local ok = pcall(manager.load, manager,
                    owner, M.LEASE_REF, nil, true, true)
                verdict = ok and "lease-queued" or "lease-error"
            end
        end

        local mark_key = tostring(gate) .. "|" .. tostring(armoury_key)
        if not marked[mark_key] and marked_count < M.MAX_MARKERS
                and type(deps.log) == "function" then
            marked[mark_key] = true
            marked_count = marked_count + 1
            deps.log(
                "[cos:481] preview gate REFUSED gate=%s key=%s ctx=%s reason=%s owner=%s recovery=%s",
                tostring(gate), tostring(armoury_key), tostring(context),
                tostring(reason), tostring(owner), verdict)
        end
        return verdict, owner
    end

    function api.debug_state()
        return { attempted = attempted, marked = marked }
    end

    return api
end

return M
