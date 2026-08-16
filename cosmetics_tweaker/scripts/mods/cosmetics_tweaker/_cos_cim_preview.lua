-- Exact Cosmetics adapter for CIM's Athanor preview context (#481).
--
-- CIM publishes a stack-scoped context while each of its three real
-- _create_item_previewer constructors executes, then attaches the same context
-- to the returned LootItemUnitPreviewer.  This adapter bridges those two phases
-- without inferring Athanor ownership from the shared previewer class or item.
--
-- Safety contract:
--   * only exact backend id, item key, item type, and supplied skin are admitted;
--   * only a currently owned Loremaster selection may replace a hand unit;
--   * custom units must already be resident and their known parent package must
--     already be loaded before a ref-count lease is taken (never force-load);
--   * spawn_data is the hand/mesh truth source;
--   * material/texture application is bounded and generation-scoped; and
--   * timeout/destroy/stale identity performs no native write and retains the
--     spawned unit's resident compiled/base presentation.

local M = {}

M.CONTRACT = "cim_preview_context_v1"
M.MAX_RECORDS = 32
M.MAX_ATTEMPTS = 8
M.RETRY_WINDOW = 2

local function nonempty(value)
    return type(value) == "string" and value ~= ""
end

local function context_token(context)
    if type(context) ~= "table" or type(context.generation) ~= "number" then
        return nil
    end
    return tostring(context.provider) .. ":" .. tostring(context.generation)
end

local function valid_context(context)
    return type(context) == "table"
        and context.contract == M.CONTRACT
        and context.surface == "cim_preview"
        and context.provider == "cim_dev"
        and type(context.generation) == "number"
        and context.generation > 0
        and (context.constructor == "overview"
            or context.constructor == "weapons"
            or context.constructor == "properties")
end

M.valid_context = valid_context

local function call_bool(fn, ...)
    if type(fn) ~= "function" then return false end
    local ok, value = pcall(fn, ...)
    return ok and value == true
end

function M.new(deps)
    deps = deps or {}
    local get_mod = assert(deps.get_mod, "get_mod is required")
    local get_application = assert(deps.get_application,
        "get_application is required")
    local get_package_manager = assert(deps.get_package_manager,
        "get_package_manager is required")
    local get_offhand_options = assert(deps.get_offhand_options,
        "get_offhand_options is required")
    local migrate_selection = assert(deps.migrate_selection,
        "migrate_selection is required")
    local offhand_selection = assert(deps.offhand_selection,
        "offhand_selection is required")
    local instance_policy = assert(deps.instance_policy,
        "instance_policy is required")
    local resolve_variant = assert(deps.resolve_variant,
        "resolve_variant is required")
    local apply_exact = assert(deps.apply_exact, "apply_exact is required")
    local is_unit = assert(deps.is_unit, "is_unit is required")
    local la_bridge = assert(deps.la_bridge, "la_bridge is required")
    local now = assert(deps.now, "now is required")
    local log = deps.log or function() end
    local max_attempts = tonumber(deps.max_attempts) or M.MAX_ATTEMPTS
    local retry_window = tonumber(deps.retry_window) or M.RETRY_WINDOW

    local records = {}
    local record_order = {}
    local previewers = setmetatable({}, { __mode = "k" })
    local jobs = setmetatable({}, { __mode = "k" })
    local leases = setmetatable({}, { __mode = "k" })

    local function current_context()
        -- CIM Dev is the sole producer of this exact contract. Stable CIM can
        -- adopt a distinct provider/version later without being guessed here.
        local ok_mod, provider = pcall(get_mod, "cim_dev")
        local accessor = ok_mod and provider
            and provider._cim_preview_context_current or nil
        if type(accessor) == "function" then
            local ok_context, context = pcall(accessor)
            if ok_context and context ~= nil then return context, true end
        end
        return nil, false
    end

    local function remember(context)
        local token = context_token(context)
        if not token then return nil end
        local record = records[token]
        if not record then
            record = { context = context, hands = {} }
            records[token] = record
            record_order[#record_order + 1] = token
            while #record_order > M.MAX_RECORDS do
                local expired = table.remove(record_order, 1)
                records[expired] = nil
            end
        elseif record.context ~= context then
            -- A generation token is process-unique. Reuse by a different table
            -- means a provider reload/collision whose ownership cannot be proven.
            return nil
        end
        return record, token
    end

    local function actual_item_key(item_data)
        if type(item_data) ~= "table" then return nil end
        return item_data.key or item_data.name
    end

    local api = {}

    -- Returns (context, reason, scoped). `scoped=true` means a CIM scope was
    -- present even when identity failed; callers must then retain vanilla/base
    -- rather than falling through to generic customization-screen identity.
    function api.resolve_scoped_identity(item_data, backend_id, item_type, skin)
        local context, scoped = current_context()
        if not scoped then return nil, "not-cim", false end
        if not valid_context(context) then return nil, "invalid-contract", true end
        if context.exact_backend_identity ~= true
                or not nonempty(context.backend_id)
                or not nonempty(backend_id) then
            return nil, "backendless", true
        end
        if backend_id ~= context.backend_id then
            return nil, "foreign-backend", true
        end
        local key = actual_item_key(item_data)
        if not nonempty(key) or not nonempty(context.item_key)
                or key ~= context.item_key then
            return nil, "foreign-item", true
        end
        if not nonempty(item_type) or not nonempty(context.item_type)
                or item_type ~= context.item_type then
            return nil, "foreign-item-type", true
        end
        if nonempty(context.skin) and skin ~= context.skin then
            return nil, "foreign-skin", true
        end
        if not remember(context) then
            return nil, "invalid-generation", true
        end
        return context, "exact", true
    end

    local function unit_resident(path)
        local application = get_application()
        return application and call_bool(application.can_get, "unit", path)
    end

    local function package_loaded(path, reference_name)
        local manager = get_package_manager()
        if not manager or type(manager.has_loaded) ~= "function" then return false end
        if reference_name ~= nil then
            return call_bool(manager.has_loaded, manager, path, reference_name)
        end
        return call_bool(manager.has_loaded, manager, path)
    end

    local function preview_path(unit_path, variant)
        if not nonempty(unit_path) then return nil end
        if unit_path:sub(-3) == "_3p" then return unit_path end
        local authored = type(variant) == "table" and variant.new_units or nil
        if type(authored) == "table" and authored[1] == unit_path
                and nonempty(authored[2]) then
            return authored[2]
        end
        return unit_path .. "_3p"
    end

    -- Called only after the equipment owner has independently proven selection
    -- ownership.  It strengthens readiness for the Athanor surface and records
    -- the exact hand/path the later spawn adapter is allowed to touch.
    function api.prepare_override(context, hand_field, selection, resolved_unit,
            _generic_ready, resolved_item_type)
        if not valid_context(context)
                or type(selection) ~= "table"
                or not nonempty(selection.la_armoury_key)
                or not nonempty(hand_field) then
            return false, "unsupported-selection"
        end
        local variant, source = resolve_variant(selection.la_armoury_key)
        if type(variant) ~= "table" then return false, "missing-variant" end
        if source ~= "loremaster" then return false, "foreign-provider" end
        local authored = variant.new_units
        if type(authored) == "table" and nonempty(authored[1])
                and resolved_unit ~= authored[1] then
            return false, "foreign-unit"
        end
        local path = preview_path(resolved_unit, variant)
        if not path or not unit_resident(path) then
            return false, "unit-not-resident"
        end
        -- The generic equipment gate also requires the 1P unit. Athanor never
        -- spawns it, so its exact surface contract deliberately depends only
        -- on the queued 3P resource and ignores a false generic_ready value.

        local parent
        if variant.kind == "unit" then
            parent = la_bridge.la_kind_unit_parent_packages
                and la_bridge.la_kind_unit_parent_packages[
                    selection.la_armoury_key] or nil
            if not nonempty(parent) or not package_loaded(parent) then
                return false, "parent-not-loaded"
            end
        end

        local record = remember(context)
        if not record then return false, "invalid-generation" end
        record.hands[hand_field] = {
            armoury_key = selection.la_armoury_key,
            vanilla_skin = selection.vanilla_skin,
            unit_path = path,
            parent_package = parent,
            item_type = resolved_item_type,
        }
        return true, "ready"
    end

    local function bind_previewer(previewer, context)
        local token = context_token(context)
        local record = token and records[token] or nil
        if not record or record.context ~= context then return nil end
        previewers[previewer] = { token = token, generation = context.generation }
        return record, token
    end

    local function exact_current_or_marker(previewer)
        local current, scoped = current_context()
        if scoped then
            return valid_context(current) and current or nil, true
        end
        local marker = type(previewer) == "table"
            and previewer._cim_preview_context or nil
        if marker ~= nil then
            return valid_context(marker) and marker or nil, true
        end
        return nil, false
    end

    local function retain_parent(previewer, context, parent)
        if not parent then return true end
        local manager = get_package_manager()
        if not manager or type(manager.load) ~= "function"
                or type(manager.unload) ~= "function" then
            return false
        end
        -- This is the no-force-load boundary.  A false probe retains the
        -- resident base result and never calls PackageManager.load.
        if not package_loaded(parent) then return false end
        local reference = "CosmeticsCimPreview" .. tostring(context.generation)
        local held = leases[previewer]
        if held and held[parent] == reference then return true end
        local ok = pcall(manager.load, manager, parent, reference, nil, false)
        if not ok then return false end
        if not package_loaded(parent, reference) then
            pcall(manager.unload, manager, parent, reference)
            return false
        end
        held = held or {}
        held[parent] = reference
        leases[previewer] = held
        return true
    end

    -- Invoked from LootItemUnitPreviewer.load_package while the CIM constructor
    -- scope is still active.  Returning true means the caller may gate-flip a
    -- resident bundled unit instead of issuing a phantom standalone load.
    function api.capture_load(previewer, package_name)
        local context, scoped = exact_current_or_marker(previewer)
        if not context then
            return false, scoped and "invalid-contract" or "not-cim", scoped
        end
        local record = bind_previewer(previewer, context)
        if not record then return false, "unowned-generation", true end
        for _, hand in pairs(record.hands) do
            if hand.unit_path == package_name then
                if not unit_resident(package_name) then
                    return false, "unit-not-resident", true
                end
                if not retain_parent(previewer, context, hand.parent_package) then
                    return false, "parent-lease-failed", true
                end
                local application = get_application()
                if application and call_bool(application.can_get,
                        "package", package_name) then
                    -- A real standalone package remains vanilla-owned. The
                    -- parent lease above still protects its material dependency.
                    return false, "native-package", true
                end
                return true, "captured", true
            end
        end
        return false, "unowned-path", true
    end

    function api.surface(previewer)
        local marker = type(previewer) == "table"
            and previewer._cim_preview_context or nil
        -- The private marker's presence is enough to suppress generic preview
        -- fallbacks. Its contents still must pass valid_context before any
        -- mesh/material work can occur.
        return marker ~= nil and "cim_preview" or "illusion_browser"
    end

    local function current_selection(record, hand_field, hand)
        local backend_id = record.context.backend_id
        migrate_selection(backend_id)
        local by_hand = offhand_selection[backend_id]
        local selection = type(by_hand) == "table" and by_hand[hand_field] or nil
        local pools = get_offhand_options(hand.item_type)
        local pool = type(pools) == "table" and pools[hand_field] or nil
        if type(selection) ~= "table"
                or selection.la_armoury_key ~= hand.armoury_key
                or not instance_policy.selection_owned(selection, pool) then
            return nil
        end
        return selection
    end

    local function generation_current(previewer, job)
        local marker = type(previewer) == "table"
            and previewer._cim_preview_context or nil
        local bound = previewers[previewer]
        return valid_context(marker)
            and marker == job.record.context
            and marker.generation == job.generation
            and bound and bound.generation == job.generation
            and bound.token == job.token
    end

    local function reconcile(previewer)
        local queue = jobs[previewer]
        if not queue then return false, "none" end
        local current_time = now()
        local kept = {}
        local applied_any = false
        local terminal_reason = "pending"
        for _, job in ipairs(queue) do
            if not generation_current(previewer, job) then
                terminal_reason = "stale-generation"
            elseif current_time >= job.deadline or job.attempts >= max_attempts then
                terminal_reason = "timeout-base-retained"
                log("[cos:481] cim preview reconcile timeout bid=%s generation=%s hand=%s",
                    tostring(job.backend_id), tostring(job.generation),
                    tostring(job.hand_field))
            else
                job.attempts = job.attempts + 1
                local selection = current_selection(job.record, job.hand_field, job.hand)
                local parent_ready = not job.hand.parent_package
                    or package_loaded(job.hand.parent_package,
                        job.parent_reference)
                if not selection then
                    terminal_reason = "selection-changed"
                elseif not parent_ready or not unit_resident(job.hand.unit_path)
                        or not is_unit(job.unit) then
                    kept[#kept + 1] = job
                else
                    local invoked, ok = pcall(apply_exact, job.world, job.unit,
                        job.hand.armoury_key, job.hand.vanilla_skin,
                        "cim_preview")
                    if invoked and ok == true then
                        applied_any = true
                        terminal_reason = "applied"
                        log("[cos:481] cim preview reconcile applied bid=%s generation=%s hand=%s attempt=%d",
                            tostring(job.backend_id), tostring(job.generation),
                            tostring(job.hand_field), job.attempts)
                    else
                        kept[#kept + 1] = job
                    end
                end
            end
        end
        jobs[previewer] = #kept > 0 and kept or nil
        return applied_any, (#kept > 0 and "pending" or terminal_reason)
    end

    -- Pair only exact spawn_data paths with returned units.  No runtime mesh
    -- introspection is used as evidence and no guessed array index is painted.
    function api.spawn(previewer, spawn_data, units, world)
        local marker = type(previewer) == "table"
            and previewer._cim_preview_context or nil
        if not valid_context(marker) then return false, "not-cim" end
        local record, token = bind_previewer(previewer, marker)
        if not record or type(spawn_data) ~= "table" or type(units) ~= "table" then
            return false, "no-owned-spawn"
        end
        local queue = {}
        local held = leases[previewer] or {}
        for hand_field, hand in pairs(record.hands) do
            for index, data in ipairs(spawn_data) do
                if type(data) == "table" and data.unit_name == hand.unit_path
                        and units[index] ~= nil then
                    queue[#queue + 1] = {
                        token = token,
                        generation = marker.generation,
                        backend_id = marker.backend_id,
                        hand_field = hand_field,
                        hand = hand,
                        record = record,
                        unit = units[index],
                        world = world,
                        parent_reference = hand.parent_package
                            and held[hand.parent_package] or nil,
                        attempts = 0,
                        deadline = now() + retry_window,
                    }
                end
            end
        end
        if #queue == 0 then return false, "path-mismatch" end
        jobs[previewer] = queue
        return reconcile(previewer)
    end

    function api.update(previewer)
        return reconcile(previewer)
    end

    function api.destroy(previewer)
        jobs[previewer] = nil
        previewers[previewer] = nil
        local held = leases[previewer]
        leases[previewer] = nil
        if held then
            local manager = get_package_manager()
            if manager and type(manager.unload) == "function" then
                for parent, reference in pairs(held) do
                    pcall(manager.unload, manager, parent, reference)
                end
            end
        end
        return true
    end

    function api.debug_state()
        return {
            records = records,
            previewers = previewers,
            jobs = jobs,
            leases = leases,
        }
    end

    return api
end

return M
