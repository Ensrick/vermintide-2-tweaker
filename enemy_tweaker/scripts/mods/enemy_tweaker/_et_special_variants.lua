local mod = get_mod("enemy_tweaker")

-- _et_special_variants.lua -- #452 read-only runtime feasibility census.
--
-- Premium Versus skins are player attachment meshes. They cannot safely be
-- assigned as an AI breed's base_unit. Before a later phase creates five new
-- networked breed clones, this module proves which source rows and units exist
-- in the current retail build. It installs no hook, setting, buff, or spawn.

local ET = mod._et
local Core = ET.SpecialVariantsCore
local rt_register = ET.rt_register
local _printf = rawget(_G, "printf") or function() end

local function _can_get_unit(path)
    local app = rawget(_G, "Application")
    if not app or type(app.can_get) ~= "function" then return false end
    return app.can_get("unit", path)
end

local function audit()
    return Core.audit({
        breeds = rawget(_G, "Breeds"),
        actions = rawget(_G, "BreedActions"),
        items = rawget(_G, "ItemMasterList"),
        cosmetics = rawget(_G, "Cosmetics"),
        can_get_unit = _can_get_unit,
    })
end

local function print_audit(reason)
    local rows, summary = audit()
    pcall(_printf,
        "[et:452] special-variants reason=%s candidates=%d missing=%d resident=%d behavior_changes=0 spawn_changes=0",
        tostring(reason), summary.candidates, summary.missing, summary.resident)
    for i = 1, #rows do
        local r = rows[i]
        pcall(_printf,
            "[et:452] %s base=%s actions=%s item=%s cosmetic=%s attachment=%s resident=%s player_attachment=%s boundary=%s",
            r.id, tostring(r.base_present), tostring(r.actions_present),
            tostring(r.item_present), tostring(r.cosmetic_present),
            tostring(r.attachment_unit), tostring(r.unit_resident),
            tostring(r.player_attachment), r.behavior_boundary)
    end
end

ET.special_variants_audit = audit
ET.SPECIAL_VARIANT_CANDIDATES = Core.CANDIDATES

-- Six bounded, log-only lines once per load. No chat pollution.
print_audit("mod_load")

rt_register("issue452_special_variant_assets_classified", function()
    local rows, summary = audit()
    if summary.candidates ~= 5 or #rows ~= 5 then
        return string.format("candidate count drifted: summary=%d rows=%d", summary.candidates, #rows)
    end
    if summary.missing > 0 then
        return string.format("%d/5 premium-special source structures are missing; inspect [et:452] lines", summary.missing)
    end
    for i = 1, #rows do
        local r = rows[i]
        if not r.player_attachment then
            return string.format("%s no longer resolves to a dark-pact player attachment; source re-audit required", r.id)
        end
    end
end)

return {
    audit = audit,
    print_audit = print_audit,
}
