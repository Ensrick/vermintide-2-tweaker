-- _cos_composite_icons.lua -- exact-instance layered weapon-icon policy.
--
-- Produces immutable-by-copy presentation descriptors; render adapters decide
-- how to place the declared layers between native rarity and frame passes.
-- No renderer globals are touched here, so the policy is offline-testable.
--
-- Owned by: cosmetics_tweaker.lua. Public seam: mod._cos_composite_icons.

local M = {}

local function _copy_array(values)
    local out = {}
    for index, value in ipairs(values or {}) do out[index] = value end
    return out
end

local function _copy_color(color)
    return color and { color[1], color[2], color[3], color[4] } or nil
end

local function _copy_descriptor(value)
    if not value then return nil end
    return {
        backend_id = value.backend_id,
        fingerprint = value.fingerprint,
        inventory_icon = value.inventory_icon,
        primary_texture = value.primary_texture,
        offhand_texture = value.offhand_texture,
        glow_texture = value.glow_texture,
        glow_color = _copy_color(value.glow_color),
        glow_source = value.glow_source,
        shield_glow = value.shield_glow and {
            unit_path = value.shield_glow.unit_path,
            variable = value.shield_glow.variable,
            brightness = value.shield_glow.brightness,
            clear = value.shield_glow.clear,
            r = value.shield_glow.r,
            g = value.shield_glow.g,
            b = value.shield_glow.b,
            intensity = value.shield_glow.intensity,
        } or nil,
        layer_order = _copy_array(value.layer_order),
    }
end

local function _byte(value)
    if type(value) ~= "number" then return nil end
    value = math.max(0, math.min(255, value))
    return math.floor(value + 0.5)
end

function M.new(catalog)
    catalog = type(catalog) == "table" and catalog or {}
    local cache = {}
    -- Renderer publication and bounded telemetry belong to this extracted
    -- subsystem. Keeping them here avoids spending top-level locals in the
    -- already-large VMF entry chunk (Lua 5.1 hard-limits a function to 200).
    local descriptors = setmetatable({}, { __mode = "k" })
    local diagnostic_seen = {}
    local diagnostic_count = 0
    local api = {}

    function api.publish(item, descriptor)
        if type(item) ~= "table" then return end
        descriptors[item] = descriptor
    end

    function api.descriptor_for(item)
        if type(item) ~= "table" then return nil end
        return descriptors[item]
    end

    function api.claim_diagnostic(reason, args)
        if type(args) ~= "table" or args.item_type ~= "es_1h_mace_shield" then
            return false
        end
        local key = table.concat({
            tostring(reason), tostring(args.skin), tostring(args.offhand_unit),
            tostring(args.offhand_armoury_key), tostring(args.glow_source),
        }, "|")
        if diagnostic_seen[key] or diagnostic_count >= 32 then return false end
        diagnostic_seen[key] = true
        diagnostic_count = diagnostic_count + 1
        return true
    end

    function api.resolve_detailed(args)
        args = type(args) == "table" and args or {}
        local backend_id = args.backend_id
        if backend_id == nil or tostring(backend_id) == ""
                or args.exact_instance ~= true then
            return nil, "missing-exact-instance"
        end
        if not (catalog.compatible_item_types
                and catalog.compatible_item_types[args.item_type]) then
            return nil, "unsupported-item-type"
        end
        local primary = catalog.primary_by_skin and catalog.primary_by_skin[args.skin]
        local offhand = catalog.offhand_by_unit and catalog.offhand_by_unit[args.offhand_unit]
        if not offhand and args.offhand_armoury_key then
            offhand = catalog.offhand_by_armoury
                and catalog.offhand_by_armoury[args.offhand_armoury_key]
        end
        if type(primary) ~= "string" then
            return nil, "unmapped-primary"
        end
        if type(offhand) ~= "table" or type(offhand.texture) ~= "string" then
            return nil, "unmapped-offhand"
        end
        local glow_texture, glow_color, shield_glow
        local glow = offhand.glow_style and catalog.glow_styles
            and catalog.glow_styles[offhand.glow_style]
        local component = glow and type(args.glow_state) == "table"
            and args.glow_state[glow.component]
        if type(component) == "table" and args.glow_state.disabled ~= true
                and (tonumber(component.intensity) or 0) > 0 then
            local r, g, b = _byte(component.r), _byte(component.g), _byte(component.b)
            if r and g and b and type(glow.texture) == "string"
                    and type(glow.material_variable) == "string"
                    and type(glow.material_brightness) == "number" then
                glow_texture = glow.texture
                glow_color = { 255, r, g, b }
                shield_glow = {
                    unit_path = args.offhand_unit,
                    variable = glow.material_variable,
                    brightness = glow.material_brightness,
                    r = r,
                    g = g,
                    b = b,
                    intensity = tonumber(component.intensity),
                }
            end
        elseif glow and args.glow_source == "committed"
                and type(args.glow_state) == "table"
                and type(glow.material_variable) == "string" then
            -- A committed disabled/zero state is an explicit material clear,
            -- not absence of policy. The icon mask disappears while the held
            -- runed shield is zeroed through this same descriptor.
            shield_glow = {
                unit_path = args.offhand_unit,
                variable = glow.material_variable,
                brightness = tonumber(glow.material_brightness) or 0,
                clear = true,
                r = 0,
                g = 0,
                b = 0,
                intensity = 0,
            }
        end

        local fingerprint = table.concat({
            tostring(backend_id), tostring(args.skin), tostring(args.offhand_unit),
            tostring(args.offhand_armoury_key), primary, offhand.texture,
            tostring(glow_texture), glow_color and table.concat(glow_color, ",") or "",
            tostring(shield_glow and shield_glow.variable),
            tostring(shield_glow and shield_glow.unit_path),
            tostring(shield_glow and shield_glow.clear),
            tostring(shield_glow and shield_glow.intensity),
            tostring(args.glow_source),
        }, "|")
        local key = tostring(backend_id)
        if cache[key] and cache[key].fingerprint == fingerprint then
            return _copy_descriptor(cache[key]), "cache-hit"
        end
        local descriptor = {
            backend_id = backend_id,
            fingerprint = fingerprint,
            inventory_icon = primary,
            primary_texture = primary,
            offhand_texture = offhand.texture,
            glow_texture = glow_texture,
            glow_color = glow_color,
            glow_source = args.glow_source,
            shield_glow = shield_glow,
            layer_order = _copy_array(catalog.layer_order),
        }
        cache[key] = descriptor
        return _copy_descriptor(descriptor), "composed"
    end

    function api.resolve(args)
        local descriptor = api.resolve_detailed(args)
        return descriptor
    end

    -- Renderer residency is a consumer concern, not part of the canonical
    -- exact-instance appearance. Held material application must not disappear
    -- merely because a particular Gui cannot draw one of the icon layers.
    function api.icon_ready(descriptor, available)
        if type(descriptor) ~= "table" then return false, "missing-descriptor" end
        if type(available) ~= "function" then return false, "missing-resource-check" end
        if available(descriptor.primary_texture) ~= true then
            return false, "missing-primary-resource"
        end
        if available(descriptor.offhand_texture) ~= true then
            return false, "missing-offhand-resource"
        end
        if descriptor.glow_texture and available(descriptor.glow_texture) ~= true then
            return false, "missing-glow-resource"
        end
        return true, "ready"
    end

    function api.invalidate(backend_id)
        if backend_id == nil then return end
        cache[tostring(backend_id)] = nil
    end

    function api.invalidate_all()
        cache = {}
    end

    -- Stateful grid-cell policy: remember the last vanilla icon before an
    -- authored primary replaces it, then restore that baseline when a reused
    -- cell receives an unsupported item or the descriptor disappears.
    function api.resolve_cell(cell_state, args)
        cell_state = type(cell_state) == "table" and cell_state or {}
        args = type(args) == "table" and args or {}
        local identity = args.identity
        local current_icon = args.current_icon
        if cell_state.identity ~= identity then
            cell_state = { identity = identity, native_icon = current_icon }
        elseif current_icon ~= cell_state.applied_icon then
            cell_state.native_icon = current_icon
        end
        local descriptor = args.descriptor
        if type(descriptor) == "table" and descriptor.primary_texture then
            cell_state.applied_icon = descriptor.primary_texture
            return descriptor.primary_texture, cell_state
        end
        local icon = current_icon
        if cell_state.applied_icon and current_icon == cell_state.applied_icon then
            icon = cell_state.native_icon
        end
        cell_state.applied_icon = nil
        return icon, cell_state
    end

    return api
end

return M
