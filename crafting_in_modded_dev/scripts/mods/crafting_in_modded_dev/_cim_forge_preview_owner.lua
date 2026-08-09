-- Athanor weapon-preview guard, placement, and bounded diagnostics owner.
-- Vanilla's LootItemUnitPreviewer loads held-unit packages before spawning and
-- later creates the display/link unit and attached item units.  Keep all five
-- hooks on that one lifecycle in their original registration order.
return function(ctx)
    assert(type(ctx) == "table", "CIM forge preview owner requires context")
    local mod = assert(ctx.mod, "CIM forge preview owner requires mod")
    local state = mod._cim_forge_preview_owner_state
    if not state then
        state = { warned = {} }
        mod._cim_forge_preview_owner_state = state
    end

    state.is_active = assert(ctx.is_active, "CIM forge preview owner requires active accessor")
    state.preview_policy = assert(ctx.preview_policy, "CIM forge preview owner requires policy")
    state.preview_runtime = assert(ctx.preview_runtime, "CIM forge preview owner requires runtime")
    state.get_mod = assert(ctx.get_mod, "CIM forge preview owner requires mod resolver")
    state.print_line = assert(ctx.print_line, "CIM forge preview owner requires logger")

    local function authored_preview_mode(item, can_get)
        local cwv = state.get_mod("character_weapon_variants")
        local resolver = cwv and cwv._cwv_resolve_preview_descriptor
        local policy = cwv and cwv._cwv_preview_descriptor
        if type(resolver) ~= "function" or type(policy) ~= "table"
                or type(policy.resource_mode) ~= "function" then
            return nil, "no_authored_descriptor", false
        end
        local ok, descriptor = pcall(resolver, item)
        if not ok or type(descriptor) ~= "table" then
            return nil, ok and "not_authored" or "descriptor_error", false
        end
        local mode, reason = state.preview_policy.authored_mode(
            descriptor, policy.resource_mode, can_get)
        return mode, reason, true
    end

    local function preview_unsafe(item)
        local ok, unsafe = pcall(function()
            if not item then return true end

            local authored_mode, _, authored = authored_preview_mode(
                item, Application and Application.can_get)
            if authored then return authored_mode == nil end

            local item_key = item.key or (item.data and item.data.key)
            if not item_key then return true end
            local master = rawget(ItemMasterList, item_key)
            if not master then return true end

            local skin = item.skin or item_key
            local skins = rawget(_G, "WeaponSkins")
            local skin_template = skins and skins.skins and skins.skins[skin]
            local display_unit = (skin_template and skin_template.display_unit)
                or master.display_unit
            if display_unit and display_unit ~= ""
                    and not Application.can_get("unit", display_unit) then
                return true
            end

            local BU = rawget(_G, "BackendUtils")
            local item_units = BU and BU.get_item_units
                and BU.get_item_units(master, item.backend_id, item.skin, nil)
            if item_units then
                local function pkg_missing(unit_name)
                    if not unit_name or unit_name == "" then return false end
                    local path = unit_name .. "_3p"
                    local loadable = state.preview_policy.unit_loadable(
                        path, Application and Application.can_get)
                    return not loadable
                end
                if item_units.is_ammo_weapon then
                    if pkg_missing(item_units.ammo_unit) then return true end
                else
                    if pkg_missing(item_units.left_hand_unit) then return true end
                    if pkg_missing(item_units.right_hand_unit) then return true end
                end
            end
            return false
        end)
        if not ok then return true end
        if unsafe then
            local key = (item and (item.key or (item.data and item.data.key))) or "<?>"
            if not state.warned[key] then
                state.warned[key] = true
                state.print_line("[cim:481] forge 3D preview skipped for '%s' — its preview units aren't loadable in the forge world (would CTD). Stat editing still works.", tostring(key))
            end
        end
        return unsafe
    end

    state.authored_preview_mode = authored_preview_mode
    state.preview_unsafe = preview_unsafe
    mod._cim_forge_authored_preview_mode = function(...)
        return state.authored_preview_mode(...)
    end
    mod._cim_forge_preview_unsafe = function(...)
        return state.preview_unsafe(...)
    end

    local function refresh_preview_runtime()
        local preview_ok, preview_reason = state.preview_runtime.install_runtime(
            mod, state.preview_policy, function() return state.is_active() end)
        mod._cim404_preview_install_ok = preview_ok == true
        if not preview_ok then
            state.print_line("[cim:404] ranged preview correction unavailable: %s",
                tostring(preview_reason))
        end
    end

    if state.installed then
        refresh_preview_runtime()
        return false
    end

    mod:hook("LootItemUnitPreviewer", "_spawn_link_unit", function(func, self, item)
        if state.is_active() and state.preview_unsafe(item) then return nil end
        return func(self, item)
    end)

    mod:hook("LootItemUnitPreviewer", "_load_item_units", function(func, self, item)
        if state.is_active() and state.preview_unsafe(item) then return {} end
        local units_to_spawn = func(self, item)
        if state.is_active() then
            pcall(function()
                local key = (item and (item.key or (item.data and item.data.key))) or "<?>"
                local count = (type(units_to_spawn) == "table" and #units_to_spawn) or 0
                state.print_line("[cim:481] forge _load_item_units key=%s skin=%s bid=%s n_entries=%d",
                    tostring(key), tostring(item and item.skin),
                    tostring(item and item.backend_id), count)
                if type(units_to_spawn) == "table" then
                    for i, data in ipairs(units_to_spawn) do
                        local unit_name = data and data.unit_name
                        state.print_line("[cim:481]   entry[%d] unit=%s pkg_res=%s unit_res=%s",
                            i, tostring(unit_name),
                            tostring(unit_name and Application.can_get("package", unit_name)),
                            tostring(unit_name and Application.can_get("unit", unit_name)))
                    end
                end
            end)
        end
        return units_to_spawn
    end)

    refresh_preview_runtime()

    mod:hook("LootItemUnitPreviewer", "spawn_units", function(func, self, spawn_data)
        local units = func(self, spawn_data)
        if not state.is_active() then return units end
        pcall(function()
            local item = self._item
            local data = item and item.data
            local key = (data and data.key) or (item and item.key) or "<?>"
            local slot_type = data and data.slot_type
            state.print_line("[cim:404] forge preview key=%s slot_type=%s skin=%s bid=%s n_data=%s n_units=%s",
                tostring(key), tostring(slot_type), tostring(item and item.skin),
                tostring(item and item.backend_id),
                tostring(spawn_data and #spawn_data or 0), tostring(units and #units or 0))
            local link_unit = self._link_unit
            if not (link_unit and Unit.alive(link_unit)) then return end
            local link_position = Unit.world_position(link_unit, 0)
            state.print_line("[cim:404]   pivot world=(%.3f, %.3f, %.3f)",
                Vector3.x(link_position), Vector3.y(link_position), Vector3.z(link_position))
            for i, unit in ipairs(units or {}) do
                if unit and Unit.alive(unit) then
                    local position = Unit.world_position(unit, 0)
                    local name = spawn_data and spawn_data[i] and spawn_data[i].unit_name
                    state.print_line("[cim:404]   unit[%d]=%s world=(%.3f, %.3f, %.3f) delta_x=%.3f delta_z=%.3f",
                        i, tostring(name), Vector3.x(position), Vector3.y(position), Vector3.z(position),
                        Vector3.x(position) - Vector3.x(link_position),
                        Vector3.z(position) - Vector3.z(link_position))
                end
            end
        end)
        return units
    end)

    mod:hook_safe("LootItemUnitPreviewer", "update", function(self, dt, t, input_service)
        if not state.is_active() or self._cim481_snapped then return end
        local spawned = self._spawned_units
        if not spawned or #spawned == 0 then return end
        self._cim481_snapped = true
        pcall(function()
            local item = self._item
            local data = item and item.data
            local key = (data and data.key) or (item and item.key) or "<?>"
            local link_unit = self._link_unit
            local link_position = link_unit and Unit.alive(link_unit)
                and Unit.world_position(link_unit, 0)
            state.print_line("[cim:481] forge post-cosmetics snapshot key=%s n_spawned=%d pivot=%s",
                tostring(key), #spawned,
                link_position and string.format("(%.3f, %.3f, %.3f)",
                    Vector3.x(link_position), Vector3.y(link_position), Vector3.z(link_position)) or "<none>")
            local units_to_spawn = self._units_to_spawn
            for i, unit in ipairs(spawned) do
                if unit and Unit.alive(unit) then
                    local position = Unit.world_position(unit, 0)
                    local scale = Unit.local_scale(unit, 0)
                    local name = units_to_spawn and units_to_spawn[i]
                        and units_to_spawn[i].unit_name
                    state.print_line("[cim:481]   unit[%d]=%s world=(%.3f, %.3f, %.3f)%s scale=(%.2f, %.2f, %.2f)",
                        i, tostring(name), Vector3.x(position), Vector3.y(position), Vector3.z(position),
                        link_position and string.format(" delta_x=%.3f delta_z=%.3f",
                            Vector3.x(position) - Vector3.x(link_position),
                            Vector3.z(position) - Vector3.z(link_position)) or "",
                        Vector3.x(scale), Vector3.y(scale), Vector3.z(scale))
                else
                    state.print_line("[cim:481]   unit[%d] NOT ALIVE", i)
                end
            end
        end)
    end)

    state.installed = true
    mod._cim_forge_preview_owner_installed = true
    return true
end
