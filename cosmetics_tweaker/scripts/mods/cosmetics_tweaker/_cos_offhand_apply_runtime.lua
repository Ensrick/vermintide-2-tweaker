-- _cos_offhand_apply_runtime.lua - authored offhand local render adapter.
--
-- Owns the one local apply transaction shared by live equipment, hero preview,
-- and illusion preview. It resolves exact item type, validates that authored
-- paint matches the spawned mesh, then dispatches Cosmetics-authored or LA
-- material application. Keeping the gate and paint in one owner prevents a
-- caller from painting heraldry onto a mismatched shield mesh.
--
-- No hook, RPC, command, lifecycle callback, update callback, persistence
-- write, or package load is registered here. The three existing render owners
-- consume the returned functions at their original install positions.

local OffhandApplyRuntime = {}

function OffhandApplyRuntime.install(mod, deps)
    deps = deps or {}

    local GK_SET                             = deps.gk_set
    local LA_BRIDGE                          = assert(deps.la_bridge, "la_bridge is required")
    local PROBE                              = deps.probe
    local _dbg                               = assert(deps.dbg, "dbg is required")
    local _get_active_customization_backend_id = assert(
        deps.get_active_customization_backend_id,
        "get_active_customization_backend_id is required")
    local _get_item_master_list              = assert(deps.get_item_master_list, "get_item_master_list is required")
    local _get_offhand_options               = assert(deps.get_offhand_options, "get_offhand_options is required")
    local _is_unit                           = assert(deps.is_unit, "is_unit is required")
    local _offhand_selection                 = assert(deps.offhand_selection, "offhand_selection is required")
    local _offhand_session_state             = assert(deps.offhand_session_state, "offhand_session_state is required")
    local _resolve_authored_offhand_variant  = assert(deps.resolve_authored_offhand_variant, "resolve_authored_offhand_variant is required")
    local _trace                             = assert(deps.trace, "trace is required")
    local _trace_paint                       = assert(deps.trace_paint, "trace_paint is required")
    local _unit_mesh_name                    = assert(deps.unit_mesh_name, "unit_mesh_name is required")

    local function _resolve_item_type(item_data)
        if not item_data then return nil end
        local item_type = item_data.item_type
        local item_master_list = _get_item_master_list()
        if item_type == "weapon_skin" and item_data.matching_item_key
                and item_master_list then
            local wd = rawget(item_master_list, item_data.matching_item_key)
            if wd then item_type = wd.item_type end
        end
        return item_type
    end

    local function _offhand_paint_mesh_ok(u, armoury_key, proven_unit_path)
        local variant = _resolve_authored_offhand_variant(armoury_key)
        if not variant then return true end
        if proven_unit_path ~= nil and variant.new_units then
            return mod._la_instance_policy.preview_target_matches(
                proven_unit_path, variant)
        end
        local actual = _unit_mesh_name(u)
        if actual == "<no-unit_name>" or actual == "<not-unit>" then return true end
        if not variant.new_units then
            return LA_BRIDGE.resolve_texture_receiver(armoury_key, actual) == nil
        end
        return actual == tostring(variant.new_units[1])
            or (variant.new_units[2] ~= nil
                and actual == tostring(variant.new_units[2]))
    end

    local function _apply_authored_offhand_to_unit(world, unit, armoury_key,
            vanilla_skin, context)
        local authored = GK_SET and GK_SET.resolve_variant(armoury_key)
        if authored then
            return GK_SET.apply_variant_to_unit(authored, unit, context)
        end
        return LA_BRIDGE.apply_offhand_to_unit(
            world, unit, armoury_key, vanilla_skin, context)
    end

    local function _apply_la_offhand_to_units(world, item_data, units, has_skin,
            backend_id_arg, context, proven_unit_paths)
        if not LA_BRIDGE.registered then
            _dbg("[LA paint] skip: authored bridge not registered")
            return false
        end
        if not world or not item_data then
            _dbg("[LA paint] skip: world/item_data nil")
            return false
        end
        if not has_skin then
            _dbg("[LA paint] skip: has_skin=false")
            return false
        end
        local bid = backend_id_arg or item_data.backend_id
        if not bid then
            _dbg("[LA paint] skip: no backend_id")
            return false
        end
        local active_backend_id = _get_active_customization_backend_id()
        if context == "ingame" and active_backend_id ~= nil
                and bid == active_backend_id then
            _dbg("[LA paint] suppress ingame browse-paint for bid=%s (customization screen open)",
                tostring(bid))
            return false
        end
        if context == "ingame" and mod._la_deus_weapon_yield() then
            _dbg("[LA paint] skip: deus run - CW upgrade cosmetics win (#518) bid=%s",
                tostring(bid))
            mod._cos518_paint_skip(bid)
            return false
        end
        _offhand_session_state.migrate_legacy(bid)
        local per_hand_sel = _offhand_selection[bid]
        if type(per_hand_sel) ~= "table" then
            _dbg("[LA paint] skip: no _offhand_selection for backend_id=%s", tostring(bid))
            return false
        end
        local painted = false
        local component_claimed = false
        local item_type = _resolve_item_type(item_data)
        local hand_pools = item_type and _get_offhand_options(item_type)
        for hand_field, sel in pairs(per_hand_sel) do
            local pool = hand_pools and hand_pools[hand_field]
            if type(sel) == "table" then component_claimed = true end
            if type(sel) == "table" and sel.la_armoury_key
                    and mod._la_instance_policy.selection_owned(sel, pool) then
                _dbg("[LA paint] painting %s (%s) on %d units (backend_id=%s)",
                    tostring(sel.la_armoury_key), hand_field, #units, tostring(bid))
                for unit_index, u in ipairs(units) do
                    if u and _is_unit(u) then
                        if context ~= "network_husk"
                                and not _offhand_paint_mesh_ok(u, sel.la_armoury_key,
                                    proven_unit_paths and proven_unit_paths[unit_index]) then
                            _dbg("[LA paint]   SKIP unit=%s key=%s ctx=%s — mesh is NOT the swapped LA mesh; refusing to warp heraldry onto mismatched shield",
                                tostring(u), tostring(sel.la_armoury_key), tostring(context))
                            _trace_paint(context, context, bid, u,
                                sel.la_armoury_key, "SKIP-mesh-mismatch")
                            if PROBE then
                                PROBE.emit("cos:sync",
                                    "offhand_gate/" .. tostring(context) .. "/"
                                        .. tostring(sel.la_armoury_key) .. "/" .. tostring(u),
                                    string.format("peer=local ctx=%s key=%s unit=%s decision=SKIP reason=mesh-mismatch(warp-guard)",
                                        tostring(context), tostring(sel.la_armoury_key), tostring(u)))
                            end
                        else
                            local ok = _apply_authored_offhand_to_unit(
                                world, u, sel.la_armoury_key, sel.vanilla_skin, context)
                            _dbg("[LA paint]   unit=%s ok=%s", tostring(u), tostring(ok))
                            if PROBE then
                                PROBE.emit("cos:sync",
                                    "offhand_gate/" .. tostring(context) .. "/"
                                        .. tostring(sel.la_armoury_key) .. "/" .. tostring(u),
                                    string.format("peer=local ctx=%s key=%s unit=%s decision=PAINT outcome=%s",
                                        tostring(context), tostring(sel.la_armoury_key),
                                        tostring(u), tostring(ok)))
                            end
                            _trace_paint(context, context, bid, u,
                                sel.la_armoury_key, ok)
                        end
                    end
                end
                painted = true
            elseif type(sel) == "table" and sel.la_armoury_key then
                _trace("PAINT selection rejected bid=%s item_type=%s hand=%s ctx=%s reason=foreign-selection",
                    tostring(bid), tostring(item_type), tostring(hand_field),
                    tostring(context))
            end
        end
        return component_claimed, painted
    end

    return {
        resolve_item_type = _resolve_item_type,
        offhand_paint_mesh_ok = _offhand_paint_mesh_ok,
        apply_authored_offhand_to_unit = _apply_authored_offhand_to_unit,
        apply_la_offhand_to_units = _apply_la_offhand_to_units,
    }
end

return OffhandApplyRuntime
