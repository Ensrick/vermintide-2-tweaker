-- _cwv_style_rewield.lua -- guarded remote Combat Style re-wield + honest
-- verdict (#786; BUG_CLASSES 58 "never OR setter results").
--
-- WHY. A Combat Style switch used to rebuild the remote husk INLINE from the
-- `cwv_combat_style_v1` receiver: `deps.rebuild_remote` called
-- `inventory.wield` directly (character_weapon_variants.lua, pre-0.1.4xx). Two
-- defects rode on that:
--
--   1. UNGUARDED WIELD. The inline call bypassed the #1145 per-wearer re-wield
--      coalescer, so it had no mid-destroy `go_alive` guard and no newest-wins
--      merge, and it ran its own competing 0.25s x 8 retry loop alongside the
--      coalescer's drain.
--   2. LYING PREDICATE. Success was `right_live or left_live` -- an OR of hand
--      liveness. A husk still rendering the PRE-SWITCH weapon, or a shield
--      style that came back without its off-hand, reported refreshed=true, so
--      the bounded retry ledger stopped on a lie and the observer kept the
--      stale mesh.
--
-- This module owns exactly the two halves the ledger needs:
--
--   * QUEUE (`queue_rebuild`). Resolve the wearer and run the readiness gate
--     NOW, then hand the wield to the coalescer. The coalescer DEFERS to its
--     next drain, so the verdict CANNOT be read in the same call. The wield
--     executor calls back post-drain (`on_verify`) and that callback is the
--     only place a verdict is produced. There is no synchronous success.
--   * VERDICT (`verdict`). AND-semantics over an expectation built from the
--     AUTHORED style catalogue (_cwv_combat_styles FAMILIES: template per
--     family+style+member, `off_hand` per family) -- never from the state the
--     wield just produced (PROJECT_STANDARDS 5.1d rule 1). Partial application
--     is failure and stays retryable inside the ledger's attempt cap.
--
-- The `wrong-template` arm is what the OR predicate could never see: when the
-- husk re-wields against the last published identity, the slot's item key (or
-- the resolved effective template) does not match the authored expectation for
-- the family+style the sender committed to, even though both hands are alive.
--
-- Owned by: character_weapon_variants.lua (loads this as `_om.style_rewield`
-- and hands it to _cwv_combat_styles' runtime as `deps.rebuild_remote`).
-- Engine-free: every engine surface arrives through `deps`.

local M = {}

M.MARKER = "cwv-style-rewield-and-semantics-v1"

M.OK = "ok"
M.PARTIAL = "partial"
M.WRONG_TEMPLATE = "wrong-template"
M.FAILED = "failed"

-- Stage C probe budget. Observation only: one line per (family, style,
-- resource) triple, hard-capped so a long session cannot drown console_logs.
M.RESIDENCY_PROBE_CAP = 32

local function alive(unit_api, unit)
    if unit == nil or type(unit_api) ~= "table"
            or type(unit_api.alive) ~= "function" then
        return false
    end
    local ok, live = pcall(unit_api.alive, unit)
    return ok and live == true
end

local function emit(deps, fmt, ...)
    -- Engine printf, bounded and always-on. Falls back to the global the same
    -- way the coalescer does, so a nil dep cannot silence #786 evidence.
    local printf_fn = (deps and deps.printf) or rawget(_G, "printf")
    if type(printf_fn) ~= "function" then return false end
    return pcall(printf_fn, fmt, ...) == true
end

-- INDEPENDENT GROUND TRUTH. Everything here comes from the authored catalogue
-- plus the concrete member key; nothing is read back from the husk.
function M.expectation(policy, family_id, style_id, item_key)
    if type(policy) ~= "table" or type(policy.member) ~= "function"
            or type(policy.package) ~= "function" then
        return nil, "policy unavailable"
    end
    if type(item_key) ~= "string" or item_key == "" then
        return nil, "slot not ready"
    end
    local member_family = policy.member(item_key)
    if member_family == nil then return nil, "item not a style member" end
    if member_family ~= family_id then return nil, "item family mismatch" end
    local package = policy.package(item_key, style_id)
    if type(package) ~= "table" or package.style_id ~= style_id then
        return nil, "style not authored"
    end
    local family = policy.FAMILIES and policy.FAMILIES[family_id]
    return {
        family_id = family_id,
        style_id = style_id,
        item_key = item_key,
        template = package.template,
        right = true,
        -- `off_hand` is authored per family in _cwv_combat_styles.FAMILIES and
        -- validated by validate_catalogue. Shield families must come back with
        -- BOTH hands; a two-hander must come back with the right hand.
        left = (type(family) == "table" and family.off_hand == true) or false,
    }
end

-- Post-wield readback. Only observation; never repairs and never re-wields.
function M.observe(deps, unit, inventory, slot_name)
    local observed = { slot = slot_name, wielded = false,
        right_live = false, left_live = false }
    if type(inventory) ~= "table" then return observed end
    local equipment = inventory._equipment or inventory.equipment
    if type(equipment) ~= "table" or type(equipment.slots) ~= "table" then
        return observed
    end
    local wielded_slot = inventory.wielded_slot or equipment.wielded_slot
    observed.wielded = wielded_slot == slot_name
    local slot = equipment.slots[slot_name]
    local item_data = type(slot) == "table" and slot.item_data or nil
    observed.right_live = alive(deps.unit_api, equipment.right_hand_wielded_unit_3p)
    observed.left_live = alive(deps.unit_api, equipment.left_hand_wielded_unit_3p)
    if item_data == nil then return observed end
    if type(deps.item_key) == "function" then
        local ok, key = pcall(deps.item_key, item_data)
        observed.item_key = ok and key or nil
    end
    if type(deps.effective_template) == "function" then
        local ok, template = pcall(deps.effective_template, item_data, unit, slot_name)
        observed.template = ok and template or nil
    end
    return observed
end

-- AND-semantics postcondition. Returns (status, detail). Only M.OK is success;
-- every other status is a retryable failure for the caller's bounded ledger.
function M.verdict(expected, observed)
    if type(expected) ~= "table" then return M.FAILED, "no expectation" end
    if type(observed) ~= "table" then return M.FAILED, "no observation" end
    local hands = string.format("right=%s/%s left=%s/%s",
        tostring(expected.right), tostring(observed.right_live),
        tostring(expected.left), tostring(observed.left_live))
    if observed.wielded ~= true then
        return M.FAILED, "slot not wielded " .. hands
    end
    if observed.item_key ~= expected.item_key then
        return M.WRONG_TEMPLATE, string.format("item expected=%s observed=%s %s",
            tostring(expected.item_key), tostring(observed.item_key), hands)
    end
    if observed.template ~= expected.template then
        return M.WRONG_TEMPLATE, string.format("template expected=%s observed=%s %s",
            tostring(expected.template), tostring(observed.template), hands)
    end
    local missing = {}
    if expected.right == true and observed.right_live ~= true then
        missing[#missing + 1] = "right"
    end
    if expected.left == true and observed.left_live ~= true then
        missing[#missing + 1] = "left"
    end
    if #missing > 0 then
        return M.PARTIAL, "missing=" .. table.concat(missing, "+") .. " " .. hands
    end
    return M.OK, string.format("template=%s %s", tostring(expected.template), hands)
end

function M.succeeded(status)
    return status == M.OK
end

-- Wearer resolution + the pre-wield readiness gate. Failure reasons stay in the
-- existing `_cwv_combat_styles.remote_refresh_retryable` vocabulary so the
-- ledger keeps its retry/terminal split.
function M.resolve_wearer(deps, peer_id, slot_name)
    local policy = deps.policy
    if type(policy) ~= "table"
            or type(policy.remote_refresh_readiness) ~= "function" then
        return nil, "policy unavailable"
    end
    if type(deps.peer_player) ~= "function" then
        return nil, "player manager unavailable"
    end
    local player, source = deps.peer_player(peer_id)
    if not player then return nil, source or "player unavailable" end
    local unit = player.player_unit
    if not alive(deps.unit_api, unit) then return nil, "player unit unavailable" end
    local script_unit = deps.script_unit
    if type(script_unit) ~= "table" or type(script_unit.extension) ~= "function" then
        return nil, "inventory extension unavailable"
    end
    local iok, inventory = pcall(script_unit.extension, unit, "inventory_system")
    if not iok or type(inventory) ~= "table" or type(inventory.wield) ~= "function" then
        return nil, "inventory extension unavailable"
    end
    local ready, reason = policy.remote_refresh_readiness(inventory, slot_name)
    if not ready then return nil, reason end
    return { unit = unit, inventory = inventory, source = source or "peer_player" }
end

function M.slot_item_key(deps, inventory, slot_name)
    local equipment = type(inventory) == "table"
        and (inventory._equipment or inventory.equipment) or nil
    local slots = type(equipment) == "table" and equipment.slots or nil
    local slot = type(slots) == "table" and slots[slot_name] or nil
    local item_data = type(slot) == "table" and slot.item_data or nil
    if item_data == nil or type(deps.item_key) ~= "function" then return nil end
    local ok, key = pcall(deps.item_key, item_data)
    return ok and key or nil
end

-- STAGE C PROBE (#786 seam 10, [unverified] -> evidence). `acquire_style_resource`
-- runs OWNER-SIDE ONLY, so an observer can be asked to re-wield toward a style
-- whose declared first-person state-machine package it never acquired. Report
-- whether that package is resident on THIS peer at the moment of the remote
-- rebuild. Read-only: reuses the same `Managers.package:has_loaded(path)` the
-- owner-side acquisition already uses (via `deps.style_resource_resident`),
-- acquires nothing, and never gates the rebuild.
function M.probe_residency(deps, state, family_id, style_id)
    if type(state) ~= "table" then return false, "no probe state" end
    local policy = deps.policy
    local family = type(policy) == "table" and policy.FAMILIES
        and policy.FAMILIES[family_id] or nil
    local style = type(family) == "table" and family.styles
        and family.styles[style_id] or nil
    local resource = type(style) == "table" and style.resource or nil
    if type(resource) ~= "string" or resource == "" then
        return false, "no authored resource"
    end
    state.seen = state.seen or {}
    state.count = state.count or 0
    local key = tostring(family_id) .. "|" .. tostring(style_id) .. "|" .. resource
    if state.seen[key] or state.count >= M.RESIDENCY_PROBE_CAP then
        return false, "probe budget"
    end
    -- `unknown` only when the package manager itself is absent (boot/menu). It
    -- is never conflated with a proved absence.
    local resident = "unknown"
    if type(deps.style_resource_resident) == "function" then
        local ok, value = pcall(deps.style_resource_resident, resource)
        if ok and value ~= nil then resident = value == true and "true" or "false" end
    end
    state.seen[key], state.count = true, state.count + 1
    emit(deps, "[cwv:786] style residency family=%s style=%s resource=%s resident=%s",
        tostring(family_id), tostring(style_id), resource, resident)
    return true, resident
end

-- Enqueue ONE guarded re-wield of `slot_name` on `peer_id`'s husk.
--
-- Returns (queued, reason, expectation):
--   * (false, reason)  -- nothing enqueued; `reason` is the ledger's existing
--                         retry vocabulary and `on_verdict` is NOT called.
--   * (true, "queued"|"merged", expectation) -- the wield runs at the next
--                         coalescer drain and `on_verdict(status, detail,
--                         observed)` fires from inside that drain.
--
-- A coalescer DROP (mid-destroy husk) never calls back at all; the caller's
-- ledger must time the pending verdict out rather than wait forever.
function M.queue_rebuild(deps, peer_id, slot_name, family_id, style_id, on_verdict)
    local coalescer = deps.coalescer
    if type(coalescer) ~= "table"
            or type(coalescer.request_peer_rewield) ~= "function" then
        return false, "coalescer unavailable"
    end
    local wearer, reason = M.resolve_wearer(deps, peer_id, slot_name)
    if not wearer then return false, reason end
    local item_key = M.slot_item_key(deps, wearer.inventory, slot_name)
    local expectation, expect_err = M.expectation(deps.policy, family_id, style_id, item_key)
    if not expectation then return false, expect_err end
    M.probe_residency(deps, deps.probe_state, family_id, style_id)
    local settled = false
    local _, why = coalescer.request_peer_rewield(peer_id, slot_name, {
        tag = "cwv-style:" .. tostring(family_id) .. ":" .. tostring(style_id),
        managers = deps.managers, unit_api = deps.unit_api,
        script_unit = deps.script_unit,
        on_verify = function(unit, inventory, _, wield_error)
            if settled then return end
            settled = true
            local observed = M.observe(deps, unit or wearer.unit,
                inventory or wearer.inventory, slot_name)
            local status, detail = M.verdict(expectation, observed)
            if wield_error ~= nil and status == M.OK then
                status, detail = M.FAILED, tostring(wield_error)
            end
            if type(on_verdict) == "function" then
                pcall(on_verdict, status, detail, observed, expectation)
            end
        end,
    })
    if why ~= "queued" and why ~= "merged" then
        return false, tostring(why or "not queued")
    end
    emit(deps, "[cwv:786] rebuild target peer=%s slot=%s family=%s style=%s item=%s resolver=%s merge=%s",
        tostring(peer_id), tostring(slot_name), tostring(family_id), tostring(style_id),
        tostring(item_key), tostring(wearer.source), tostring(why))
    return true, why, expectation
end

return M
