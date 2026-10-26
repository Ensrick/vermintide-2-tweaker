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
    local right_unit = equipment.right_hand_wielded_unit_3p
    local left_unit = equipment.left_hand_wielded_unit_3p
    observed.right_live = alive(deps.unit_api, right_unit)
    observed.left_live = alive(deps.unit_api, left_unit)
	if type(deps.observed_unit_name) == "function" then
		local rok, right_name = pcall(deps.observed_unit_name,
			right_unit, unit, slot_name, "right")
		local lok, left_name = pcall(deps.observed_unit_name,
			left_unit, unit, slot_name, "left")
		observed.right_unit = rok and right_name or nil
		observed.left_unit = lok and left_name or nil
	end
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
	local wrong_units = {}
	if expected.right_unit and observed.right_unit ~= expected.right_unit then
		wrong_units[#wrong_units + 1] = "right"
	end
	if expected.left_unit and observed.left_unit ~= expected.left_unit then
		wrong_units[#wrong_units + 1] = "left"
	end
	if #wrong_units > 0 then
		return M.PARTIAL, string.format("wrong-unit=%s expected=%s/%s observed=%s/%s %s",
			table.concat(wrong_units, "+"), tostring(expected.right_unit),
			tostring(expected.left_unit), tostring(observed.right_unit),
			tostring(observed.left_unit), hands)
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

-- #660 bounded Greatsword HUSK adapter. The wire descriptor stays unchanged:
-- its generation participates in the semantic fingerprint, so a peer-local
-- counter must never be inserted into that transport contract. This owner's
-- observation generation is private and advances only at a real fresh spawn.
-- Capture precedes CWV's first transform write; the queued post-wield callback
-- repairs measured drift with the existing shared writer and then independently
-- reads every pose channel. This is not next-frame or whole-family adoption.
function M.new_retained(opts)
    local D, WA = assert(opts.descriptor), assert(opts.writer)
    local U, V, Q = assert(opts.unit), assert(opts.vector), assert(opts.quaternion)
    local rows = setmetatable({}, { __mode = "k" })
    local latest = setmetatable({}, { __mode = "k" })
    local generation, emitted, last = 0, 0, nil
    local C = {}
    local function finite(x)
        return type(x) == "number" and x == x and x ~= math.huge and x ~= -math.huge
    end
    local function elements(api, value, count)
        if type(api.to_elements) ~= "function" then return nil end
        local ok, x, y, z, w = pcall(api.to_elements, value)
        if not ok or not finite(x) or not finite(y) or not finite(z)
                or (count == 4 and not finite(w)) then return nil end
        if count == 4 then
            local norm = x * x + y * y + z * z + w * w
            if not finite(norm) or norm <= 0 then return nil end
        end
        return count == 4 and { x, y, z, w } or { x, y, z }
    end
    local function read_pose(unit)
        if not alive(U, unit) then return nil end
        local okp, p = pcall(U.local_position, unit, 0)
        local oks, s = pcall(U.local_scale, unit, 0)
        local okr, r = pcall(U.local_rotation, unit, 0)
        p = okp and elements(V, p, 3) or nil
        s = oks and elements(V, s, 3) or nil
        r = okr and elements(Q, r, 4) or nil
        return p and s and r and { position = p, scale = s, rotation = r } or nil
    end
    local function near(a, b, count)
        if not a or not b then return false end
        if count == 4 then
            local dot, aa, bb = 0, 0, 0
            for i = 1, 4 do
                dot, aa, bb = dot + a[i] * b[i], aa + a[i] * a[i], bb + b[i] * b[i]
            end
            return aa > 0 and bb > 0 and math.abs(math.abs(dot / math.sqrt(aa * bb)) - 1) <= 0.003
        end
        for i = 1, count do if math.abs(a[i] - b[i]) > 0.002 then return false end end
        return true
    end
    local function observed(row)
        local pose = read_pose(row.refs.unit)
        local p = pose and near(pose.position, row.target.position, 3) or false
        local s = pose and near(pose.scale, row.target.scale, 3) or false
        local r = pose and near(pose.rotation, row.target.rotation, 4) or false
        return { retained = p and s and r, position = p, scale = s, rotation = r,
            actual = pose, reason = p and s and r and "retained" or "pose-readback-failed" }
    end
    local function tuple(value)
        if type(value) ~= "table" then return "unavailable" end
        local out = {}
        for i = 1, #value do out[i] = string.format("%.5f", value[i]) end
        return table.concat(out, ",")
    end
    local function admitted(row, descriptor, owner, slot_name)
        if not alive(U, owner) then return false, "owner-dead" end
        local by_slot = latest[owner]
        if not row or row.refs.owner ~= owner or row.slot ~= slot_name
                or not by_slot or by_slot[slot_name] ~= row then return false, "spawn-generation-stale" end
        if not D.raw(descriptor) or descriptor.fingerprint ~= row.source_fingerprint then
            return false, "descriptor-foreign"
        end
        local ok, current, state = pcall(opts.current_descriptor, owner, slot_name, descriptor.base_item_key)
        if not ok or state ~= "exact" or not D.raw(current)
                or current.fingerprint ~= row.source_fingerprint then return false, "identity-no-longer-exact" end
        local inventory = row.refs.inventory
        if inventory then
            local equipment = inventory._equipment or inventory.equipment
            if type(equipment) ~= "table" or equipment.right_hand_wielded_unit_3p ~= row.refs.unit
                    or (inventory.wielded_slot or equipment.wielded_slot) ~= slot_name then
                return false, "render-target-replaced"
            end
        end
        return alive(U, row.refs.unit), "unit-dead"
    end
    local reconciler = D.new_reconciler({ max_attempts = 1,
        apply = function(_, _, _, unit, context)
            local row = context.row
            if observed(row).retained then return { ok = true, unchanged = true } end
            return WA.apply_report(unit, { position = row.target.position, scale = row.target.scale,
                rotation = { unbox = function()
                    return Q.from_elements(unpack(row.target.rotation, 1, 4))
                end } })
        end,
        observe = function(_, _, _, _, context)
            local row = context.row
            local ok, reason = admitted(row, row.source, row.refs.owner, row.slot)
            if not ok then return { retained = false, reason = reason } end
            return observed(row)
        end,
    })
    function C.capture(descriptor, unit, owner, slot_name, hand, unit_name)
        if not D.raw(descriptor) or descriptor.provider ~= "cwv_style"
                or descriptor.style_family ~= "greatsword" or hand ~= "right"
                or descriptor.left_hand_unit ~= nil then return false, "outside-family" end
        if descriptor.transform_3p == nil then return false, "native-transform-unmanaged" end
        local right = descriptor.right_hand_unit
        if type(right) ~= "table" or unit_name ~= right.unit_3p
                or not alive(U, owner) then return false, "spawn-identity" end
        local old = rows[unit]
        if old then
            return old.refs.owner == owner and old.slot == slot_name
                and old.source_fingerprint == descriptor.fingerprint, "already-captured"
        end
        local target = read_pose(unit)
        if not target then return false, "native-baseline-unreadable" end
        local transform = descriptor.transform_3p
        if transform then
            for _, name in ipairs({ "scale", "offset", "rotation" }) do
                local value = transform[name]
                if value and (not finite(value[1]) or not finite(value[2]) or not finite(value[3])) then
                    return false, "authored-transform-invalid"
                end
            end
            if transform.scale then target.scale = transform.scale end
            if transform.offset then
                for i = 1, 3 do target.position[i] = target.position[i] + transform.offset[i] end
            end
            if transform.rotation then
                local ok, value = pcall(Q.from_euler_angles_xyz, unpack(transform.rotation, 1, 3))
                target.rotation = ok and elements(Q, value, 4) or nil
                if not target.rotation then return false, "authored-rotation-unreadable" end
            end
        end
        if generation >= 9007199254740991 then return false, "observation-generation-exhausted" end
        generation = generation + 1
        local data = D.raw(descriptor)
        data.generation = generation
        local runtime = D.build(data)
        if not runtime then return false, "runtime-descriptor-rejected" end
        -- Lua 5.1 weak-key values must not point strongly back to their keys.
        -- Keep engine handles weak even in the bounded latest-evidence record.
        local row = { refs = setmetatable({ unit = unit, owner = owner }, { __mode = "v" }),
            slot = slot_name, target = target, source = descriptor,
            source_fingerprint = descriptor.fingerprint, generation = generation, runtime = runtime }
        rows[unit] = row
        latest[owner] = latest[owner] or {}
        latest[owner][slot_name] = row
        return true
    end
    function C.reconcile(descriptor, owner, inventory, slot_name)
        if not D.raw(descriptor) or descriptor.provider ~= "cwv_style"
                or descriptor.style_family ~= "greatsword" then return false, "outside-family" end
        -- A native/unmodified style has no authored absolute pose to restore.
        -- Its final animation-owned attachment must remain untouched.
        if descriptor.transform_3p == nil then return true, "native-transform-unmanaged" end
        local equipment = inventory and (inventory._equipment or inventory.equipment)
        local unit = type(equipment) == "table" and equipment.right_hand_wielded_unit_3p
        local row = unit and rows[unit]
        -- A failed active attempt still belongs in the named check: absence of
        -- capture/authority is not the same thing as no managed target tried.
        last = { refs = setmetatable({ owner = owner, inventory = inventory }, { __mode = "v" }), slot = slot_name }
        local ok, reason = admitted(row, descriptor, owner, slot_name)
        if not ok then return false, reason end
        row.refs.inventory = inventory
        -- A fresh queued callback must read the renderer again, not reuse an
        -- old successful record. The coalescer/settled flag already bounds calls.
        reconciler.forget(unit)
        -- The contract's post-wield edge refines the canonical equip axis.
        local result = reconciler.reconcile(row.runtime, "husk", "equip", unit, { row = row })
        if emitted < 64 then
            emitted = emitted + 1
            local o = result.observation or {}
            local actual = o.actual or {}
            emit(opts, "[cwv:660] family=greatsword surface=husk edge=post_wield observation_generation=%d semantic_generation=%s descriptor=%s retained=%s position=%s scale=%s rotation=%s actual_position=[%s] expected_position=[%s] actual_scale=[%s] expected_scale=[%s] actual_rotation=[%s] expected_rotation=[%s] count=%d/64",
                row.generation, tostring(descriptor.generation), row.source_fingerprint,
                tostring(result.retained == true), tostring(o.position), tostring(o.scale), tostring(o.rotation),
                tuple(actual.position), tuple(row.target.position), tuple(actual.scale), tuple(row.target.scale),
                tuple(actual.rotation), tuple(row.target.rotation), emitted)
        end
        return result.retained == true, result.reason
    end
    if type(opts.rt_register) == "function" then
        opts.rt_register("issue660_greatsword_husk_retained", function()
            if not last then return "skip: no Greatsword remote post-wield observed this session" end
            local ok, result = pcall(function()
                local owner = last.refs.owner
                if owner == nil then return "skip: observed Greatsword owner was released" end
                local read, live = pcall(U.alive, owner)
                if not read then return "#660 current Greatsword owner liveness unreadable" end
                if live == false then return "skip: observed Greatsword owner was destroyed" end
                if live ~= true then return "#660 current Greatsword owner liveness unreadable" end
                local inventory = last.refs.inventory
                local equipment = inventory and (inventory._equipment or inventory.equipment)
                if type(equipment) ~= "table" or type(equipment.slots) ~= "table" then
                    return "#660 current Greatsword inventory unreadable"
                end
                local wielded = inventory.wielded_slot or equipment.wielded_slot
                if type(wielded) ~= "string" or wielded == "" then return "#660 current wielded slot unreadable" end
                if wielded ~= last.slot then return "skip: observed Greatsword slot is not wielded" end
                local slot = equipment.slots[last.slot]
                local item = type(slot) == "table" and slot.item_data
                local key = type(item) == "table" and item.name
                if type(key) ~= "string" or key == "" then return "#660 current Greatsword item unreadable" end
                if opts.family_for_item(key) ~= "greatsword" then return "skip: wielded item is outside Greatsword family" end
                local descriptor, state = opts.current_descriptor(owner, last.slot, key)
                if state == "native" and descriptor == nil then return "skip: replicated native appearance is unmanaged" end
                if state ~= "exact" or not D.raw(descriptor) then return "#660 active Greatsword identity is not exact" end
                if descriptor.provider ~= "cwv_style" or descriptor.style_family ~= "greatsword" then
                    return "#660 active Greatsword descriptor family is foreign"
                end
                if descriptor.base_item_key ~= key then return "#660 active Greatsword descriptor base is foreign" end
                if descriptor.transform_3p == nil then
                    if opts.native_style(descriptor) then return "skip: current Greatsword style has no authored transform" end
                    return "#660 active Greatsword authored transform is missing"
                end
                local row = rows[equipment.right_hand_wielded_unit_3p]
                if not row then return "#660 current Greatsword husk evidence unavailable: render-target-replaced" end
                local accepted, reason = admitted(row, descriptor, owner, last.slot)
                if not accepted then return "#660 current Greatsword husk evidence unavailable: " .. tostring(reason) end
                row.refs.inventory = inventory
                if not observed(row).retained then return "#660 current Greatsword husk pose was not retained" end
            end)
            if not ok then return "#660 active Greatsword lifecycle read failed" end
            return result
        end)
    end
    return C
end

-- Own retained construction and context assembly alongside the queued adapter,
-- keeping the entry a wiring boundary rather than growing a second owner.
function M.bind_retained(om, deps, vector, quaternion, rt_register)
    local retained = M.new_retained({
        descriptor = om.appearance_descriptor, writer = om.weapon_appearance,
        unit = deps.unit_api, vector = vector, quaternion = quaternion,
        printf = deps.printf, rt_register = rt_register,
        family_for_item = function(key) return deps.policy.member(key) end,
        native_style = function(descriptor)
            local package = deps.policy.package(descriptor.base_item_key, descriptor.style_id)
            return package and package.template == descriptor.effective_template and package.presentation == nil
        end,
        current_descriptor = function(owner, slot, base)
            if not om._husk_identity_descriptor then return nil end
            return om._husk_identity_descriptor(owner, slot, base)
        end,
    })
    om._greatsword_husk_retained = retained
    deps.retained_reconcile = retained.reconcile
    return deps
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
function M.queue_rebuild(deps, peer_id, slot_name, family_id, style_id, on_verdict,
		descriptor)
    local coalescer = deps.coalescer
    if type(coalescer) ~= "table"
            or type(coalescer.request_peer_rewield) ~= "function" then
        return false, "coalescer unavailable"
    end
	local wearer, reason = M.resolve_wearer(deps, peer_id, slot_name)
	if not wearer then return false, reason end
	local item_key = M.slot_item_key(deps, wearer.inventory, slot_name)
	local expectation, expect_err
	if descriptor ~= nil and type(deps.descriptor_expectation) == "function" then
		local ok
		ok, expectation, expect_err = pcall(deps.descriptor_expectation, descriptor)
		if not ok then expectation, expect_err = nil, tostring(expectation) end
		if expectation and (expectation.family_id ~= family_id
				or expectation.style_id ~= style_id
				or expectation.item_key ~= item_key) then
			expectation, expect_err = nil, "descriptor expectation mismatch"
		end
	else
		expectation, expect_err = M.expectation(
			deps.policy, family_id, style_id, item_key)
	end
	if not expectation then return false, expect_err end
    M.probe_residency(deps, deps.probe_state, family_id, style_id)
    local settled = false
    local _, why = coalescer.request_peer_rewield(peer_id, slot_name, {
		tag = "cwv-style:" .. tostring(family_id) .. ":" .. tostring(style_id)
			.. ":" .. tostring(expectation.fingerprint or "legacy"),
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
            if status == M.OK and family_id == "greatsword" and descriptor ~= nil
                    and type(deps.retained_reconcile) == "function" then
                local ok, retained, retained_reason = pcall(deps.retained_reconcile,
                    descriptor, unit or wearer.unit, inventory or wearer.inventory, slot_name)
                if not ok or retained ~= true then
                    status, detail = M.PARTIAL, "retained-pose: " .. tostring(ok and retained_reason or retained)
                end
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
