-- Engine-free resource policy for CIM's LootItemUnitPreviewer/Athanor gate.
local M = {}

local function available(can_get, kind, path)
    if type(can_get) ~= "function" or type(path) ~= "string" or path == "" then
        return false
    end
    local ok, result = pcall(can_get, kind, path)
    return ok and result == true
end

-- Vanilla held units have standalone packages. Mod-authored LA/Cosmetics units
-- may instead already be resident through a master bundle; either condition is
-- sufficient for World.spawn_unit, and neither condition may be guessed.
function M.unit_loadable(unit_path, can_get)
    if type(unit_path) ~= "string" or unit_path == "" then return true, "empty" end
    if available(can_get, "package", unit_path) then return true, "package" end
    if available(can_get, "unit", unit_path) then return true, "resident_unit" end
    return false, "missing"
end

function M.authored_mode(descriptor, resource_mode, can_get)
    if type(descriptor) ~= "table" or type(resource_mode) ~= "function" then
        return nil, "unsupported"
    end
    local ok, mode, reason = pcall(resource_mode, descriptor, can_get)
    if not ok then return nil, "resolver_error" end
    if mode == "custom" or mode == "fallback" then return mode, reason end
    return nil, reason or "unavailable"
end

-- HeroWindowWeaveProperties uses {-0.85, 3, 0} for every item while the
-- sibling native HeroWindowWeaveForgeWeapons browser centers its preview at
-- x=0.  Keep the properties layout's authored depth/height, but use the
-- native centered x position for ranged weapons whose long meshes otherwise
-- sit at the far-left edge.  Returning nil leaves every other slot on the
-- untouched vanilla path.
function M.properties_preview_position(slot_type, native_position)
    if slot_type ~= "ranged" or type(native_position) ~= "table"
            or type(native_position[1]) ~= "number"
            or type(native_position[2]) ~= "number"
            or type(native_position[3]) ~= "number" then
        return nil
    end

    return {
        0,
        native_position[2],
        native_position[3],
    }
end

-- The overview normally puts both equipped weapons at x=-0.8 and marks the
-- third/secondary viewport `invert_rendering`; its keep-only inverted shading
-- environment mirrors the final image.  The mission-safe environment fallback
-- cannot preserve that resource, so mirror the viewport which vanilla marked,
-- regardless of the weapon's slot_type.  Grail Knight, Slayer, Warrior Priest,
-- and cross-slot loadouts can legitimately put a melee item in slot_ranged.
function M.overview_preview_x(mirrored_viewport, native_x, in_keep)
    if in_keep or mirrored_viewport ~= true or type(native_x) ~= "number" then
        return native_x
    end
    return -native_x
end

return M
