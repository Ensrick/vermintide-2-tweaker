-- _cos_offhand_state_runtime.lua - independent-offhand catalog state runtime.
--
-- Owns the mutable state transitions that turn authored offhand catalogs into
-- exact-instance selections: one-shot LA catalog merge, bounded persisted-state
-- restoration, lazy dual-pool resolution, and the receiver-side exact-unit
-- compatibility boundary.  These operations travel together because they all
-- read the same canonical `_offhand_options` / `_offhand_selection` tables and
-- restoration must rebuild the exact option records produced by the merge.
--
-- The installer runs once at the former merge declaration site.  It registers
-- no hook, RPC, command, lifecycle callback, or frame callback.  The entry's
-- existing scheduler remains the sole caller of merge/restore.  Runtime engine
-- globals cross through getters so early module installation cannot freeze an
-- unavailable backend or ItemMasterList.

local OffhandStateRuntime = {}

function OffhandStateRuntime.install(mod, deps)
    deps = deps or {}

    local GK_SET                       = deps.gk_set
    local LA_BRIDGE                    = assert(deps.la_bridge, "la_bridge is required")
    local LA_PERSIST                   = assert(deps.la_persist, "la_persist is required")
    local OFFHAND_NAMES                = assert(deps.offhand_names, "offhand_names is required")
    local _decorate_shield_option      = assert(deps.decorate_shield_option, "decorate_shield_option is required")
    local _get_item_master_list        = assert(deps.get_item_master_list, "get_item_master_list is required")
    local _get_managers                = assert(deps.get_managers, "get_managers is required")
    local get_mod                      = assert(deps.get_mod, "get_mod is required")
    local _offhand_options             = assert(deps.offhand_options, "offhand_options is required")
    local _offhand_selection           = assert(deps.offhand_selection, "offhand_selection is required")
    local _preload_offhand_for_option  = assert(deps.preload_offhand_for_option, "preload_offhand_for_option is required")
    local _preload_offhand_package     = assert(deps.preload_offhand_package, "preload_offhand_package is required")
    local _now                         = deps.now or os.clock
    local _printf                      = deps.printf

    -- Legacy "one shield at a time" testing whitelist. Empty means every
    -- bridge option is visible; populate only while isolating authored data.
    local _LA_FOCUS_KEYS = {}
    local _la_offhand_merged = false

    local function _merge_la_offhand_options()
        if _la_offhand_merged then return end
        if not LA_BRIDGE.registered then return end
        if type(LA_BRIDGE.la_offhand_options_by_weapon_type) ~= "table" then return end
        local has_focus, appended, duplicates = next(_LA_FOCUS_KEYS) ~= nil, 0, 0
        for weapon_key, la_hand_pools in pairs(LA_BRIDGE.la_offhand_options_by_weapon_type) do
            local hand_target = _offhand_options[weapon_key]
            if not hand_target then hand_target = {}; _offhand_options[weapon_key] = hand_target end
            for hand_field, la_pool in pairs(la_hand_pools) do
                local target = hand_target[hand_field]
                if not target then target = {}; hand_target[hand_field] = target end
                for _, la_opt in ipairs(la_pool) do
                    if (not has_focus) or _LA_FOCUS_KEYS[la_opt.armoury_key] then
                        local candidate = {
                            name             = la_opt.name .. " (LA)",
                            la_armoury_key   = la_opt.armoury_key,
                            vanilla_skin     = la_opt.vanilla_skin,
                            target_item_type = la_opt.target_item_type or weapon_key,
                            intended_unit    = la_opt.intended_unit,
                            authored_family = la_opt.authored_family,
                            variant_kind    = la_opt.variant_kind,
                            rarity           = "promo",
                        }
                        _decorate_shield_option(candidate)
                        if OFFHAND_NAMES.merge_unique(target, candidate, hand_field) then
                            appended = appended + 1
                        else
                            duplicates = duplicates + 1
                        end
                    end
                end
            end
        end
        _la_offhand_merged = true
        mod:info("[offhand] merged LA shield options (focus gate: %d keys, appended=%d duplicate_identity=%d)",
            (function()
                local n = 0
                for _ in pairs(_LA_FOCUS_KEYS) do n = n + 1 end
                return n
            end)(), appended, duplicates)
    end

    local function _get_offhand_options(item_key)
        if mod._ensure_independent_dual_pool then
            mod._ensure_independent_dual_pool(item_key)
        end
        return _offhand_options[item_key]
    end

    -- Receiver-side compatibility boundary for #583. A stale or malformed
    -- direct mesh payload may only override a registered dual hand when that
    -- exact unit remains in the item's compatible pool.
    mod._dual_offhand_unit_allowed = function(item_type, hand_field, unit_path)
        if not (mod._independent_dual_item_types
                and mod._independent_dual_item_types[item_type]) then
            return true
        end
        if hand_field ~= "left_hand_unit" then return false end
        local pools = mod._ensure_independent_dual_pool(item_type)
        local pool = pools and pools[hand_field]
        for _, opt in ipairs(pool or {}) do
            if opt.unit == unit_path and unit_path ~= "" then return true end
        end
        return false
    end

    -- Restore persisted offhand picks only after their catalog and exact backend
    -- instance are available. Retries are bounded to 15 seconds; stale or
    -- ambiguous records fail closed instead of attaching a sibling component.
    mod._la_restore_offhand_selections = function()
        if mod._la_offhand_restore_done then return end
        if not (LA_PERSIST and LA_PERSIST.get_saved_offhands) then return end
        local restore_now = _now()
        if mod._la_offhand_restore_retry_at
                and restore_now < mod._la_offhand_restore_retry_at then return end
        mod._la_offhand_restore_retry_at = restore_now + 0.5
        mod._la_offhand_restore_deadline = mod._la_offhand_restore_deadline
            or (restore_now + 15)
        local saved = LA_PERSIST.get_saved_offhands()
        if not next(saved) then mod._la_offhand_restore_done = true return end
        local la_pools = LA_BRIDGE and LA_BRIDGE.registered
            and LA_BRIDGE.la_offhand_options_by_weapon_type or nil
        local needs_la, needs_item = false, false
        for _, hands in pairs(saved) do
            for _, rec in pairs(hands) do
                if rec and rec.armoury_key
                        and not (GK_SET and GK_SET.resolve_variant(rec.armoury_key)) then
                    needs_la = true
                end
                if rec then needs_item = true end
            end
        end
        if needs_la and type(la_pools) ~= "table" then return end
        local managers = _get_managers()
        local backend_mgr = managers and managers.backend
        local backend_items = backend_mgr and backend_mgr._interfaces
            and backend_mgr._interfaces.items and backend_mgr:get_interface("items")
        if needs_item and not (backend_items and backend_items.get_item_from_id) then return end
        if get_mod("character_weapon_variants") and mod._discover_cwv_dual_offhand_pools then
            mod._discover_cwv_dual_offhand_pools()
        end
        local by_target = mod._la_option_icon_policy.index_by_target(la_pools)
        for item_type, hand_pools in pairs(_offhand_options) do
            for hand_field, pool in pairs(hand_pools) do
                for _, opt in ipairs(pool) do
                    if opt.la_armoury_key and opt.cos_authored
                            and not mod._la_option_icon_policy.lookup(by_target, item_type,
                                hand_field, opt.la_armoury_key) then
                        by_target[item_type] = by_target[item_type] or {}
                        by_target[item_type][hand_field] =
                            by_target[item_type][hand_field] or {}
                        by_target[item_type][hand_field][opt.la_armoury_key] = {
                            name = opt.name,
                            armoury_key = opt.la_armoury_key,
                            vanilla_skin = opt.vanilla_skin,
                            intended_unit = opt.intended_unit,
                            authored_family = opt.authored_family,
                            variant_kind = opt.variant_kind,
                            inventory_icon = opt.inventory_icon,
                            cos_authored = true,
                        }
                    end
                end
            end
        end
        local n, miss, deferred = 0, 0, 0
        local item_master_list = _get_item_master_list()
        for backend_id, hands in pairs(saved) do
            local ok_item, item = pcall(backend_items.get_item_from_id,
                backend_items, backend_id)
            local item_data = ok_item and item and (item.data
                or (item.key and item_master_list and rawget(item_master_list, item.key)))
            local item_type = item_data and item_data.item_type
            local exact_skin = ok_item and item and item.skin or nil
            if not exact_skin and ok_item and item and backend_items.get_skin then
                local ok_skin, backend_skin = pcall(backend_items.get_skin,
                    backend_items, backend_id)
                if ok_skin then exact_skin = backend_skin end
            end
            local item_pending = not (ok_item and item)
                and restore_now < mod._la_offhand_restore_deadline
            for hand_field, rec in pairs(hands) do
                local la_opt = rec and rec.armoury_key
                    and mod._la_option_icon_policy.lookup(by_target, item_type,
                        hand_field, rec.armoury_key)
                local mesh_opt = nil
                local this_deferred = item_pending
                if item_pending then deferred = deferred + 1 end
                if rec and type(rec.unit_path) == "string" and rec.unit_path ~= "" then
                    if ok_item and item then
                        local pools = item_type and mod._ensure_independent_dual_pool
                            and mod._ensure_independent_dual_pool(item_type)
                        local pool = pools and pools[hand_field]
                        local unit_fallback, unit_ambiguous = nil, false
                        for _, candidate in ipairs(pool or {}) do
                            if candidate.unit == rec.unit_path then
                                local component_key = candidate.skin_key
                                    or candidate.source_skin_key
                                if rec.vanilla_key and component_key == rec.vanilla_key then
                                    mesh_opt = candidate
                                    break
                                elseif not unit_fallback then
                                    unit_fallback = candidate
                                else
                                    unit_ambiguous = true
                                end
                            end
                        end
                        if not mesh_opt and unit_fallback and not unit_ambiguous then
                            mesh_opt = unit_fallback
                        end
                        if not mesh_opt and (not pool or #pool == 0)
                                and restore_now < mod._la_offhand_restore_deadline then
                            deferred = deferred + 1
                            this_deferred = true
                        end
                    else
                        local cim = get_mod("cim_dev") or get_mod("cim")
                        local pending_cim = cim and cim._cim_get_craft
                            and cim._cim_get_craft(backend_id) ~= nil
                        if not this_deferred and pending_cim
                                and restore_now < mod._la_offhand_restore_deadline then
                            deferred = deferred + 1
                            this_deferred = true
                        end
                    end
                end
                if la_opt then
                    local restored = {
                        name             = la_opt.name .. " (LA)",
                        la_armoury_key   = la_opt.armoury_key,
                        target_item_type = la_opt.target_item_type or item_type,
                        intended_unit    = la_opt.intended_unit,
                        authored_family  = la_opt.authored_family,
                        variant_kind     = la_opt.variant_kind,
                        inventory_icon   = la_opt.inventory_icon,
                        cos_authored     = la_opt.cos_authored == true,
                        rarity           = "promo",
                    }
                    if not restored.cos_authored then
                        local la_mod = get_mod("Loremasters-Armoury")
                        restored = mod._la_option_icon_policy.resolve_for_item(restored,
                            item_type, exact_skin,
                            la_mod and la_mod.SKIN_LIST,
                            LA_BRIDGE.normalize_weapon_type)
                    end
                    _offhand_selection[backend_id] = _offhand_selection[backend_id] or {}
                    _offhand_selection[backend_id][hand_field] = restored
                    if la_opt.intended_unit then _preload_offhand_package(la_opt.intended_unit) end
                    n = n + 1
                elseif mesh_opt then
                    _offhand_selection[backend_id] = _offhand_selection[backend_id] or {}
                    _offhand_selection[backend_id][hand_field] = mesh_opt
                    _preload_offhand_for_option(mesh_opt)
                    n = n + 1
                elseif not this_deferred then
                    miss = miss + 1
                end
            end
        end
        if n > 0 then mod._la_self_rebroadcast_pending = true end
        mod._la_offhand_restore_done = deferred == 0
            or restore_now >= mod._la_offhand_restore_deadline
        if mod._la_offhand_restore_done then
            mod._la_offhand_restore_retry_at = nil
        end
        local summary = string.format("%d|%d|%d|%s", n, miss, deferred,
            tostring(mod._la_offhand_restore_done))
        if _printf and summary ~= mod._la_offhand_restore_last_summary then
            mod._la_offhand_restore_last_summary = summary
            _printf("[la-state] OFFHAND-RESTORE restored=%d unresolvable=%d deferred=%d done=%s",
                n, miss, deferred, tostring(mod._la_offhand_restore_done))
        end
    end

    return {
        merge_la_offhand_options = _merge_la_offhand_options,
        get_offhand_options = _get_offhand_options,
    }
end

return OffhandStateRuntime
