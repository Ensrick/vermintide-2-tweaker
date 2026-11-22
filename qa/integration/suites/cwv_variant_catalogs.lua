-- qa/integration/suites/cwv_variant_catalogs.lua (WP-T-03): Character Weapon Variants' data catalogs against the real
-- vanilla tables. Every _cwv_*.lua module of the mod that loads with loadfile and returns a table with a VARIANTS
-- list is checked (others, such as the main catalog that needs the entry file's context, are counted as not data):
-- each variant's base_weapon is in ItemMasterList; its template, when it has one, is in Weapons or starts with cwv_
-- (a CWV-registered template); every career in careers or default_careers, and in the module's ALL_CAREERS, is in
-- CareerSettings. Loading runs the module's top level under the stubs and the fake VMF; nothing it defines is used.
-- The module list comes from qa/check_integration.ps1 (ctx.files.cwv_modules). Planted (selftest): one variant whose
-- base_weapon does not exist.
local DIR = "/character_weapon_variants/scripts/mods/character_weapon_variants"

return function(ctx)
    local problems, notes, checked = {}, {}, 0
    local catalogs, skipped = {}, 0
    for _, file in ipairs(ctx.files.cwv_modules or {}) do
        local chunk = loadfile(ctx.repo .. DIR .. "/" .. file)
        local ok, module = false, nil
        if chunk then ok, module = pcall(chunk) end
        if ok and type(module) == "table" and type(rawget(module, "VARIANTS")) == "table" then
            catalogs[#catalogs + 1] = { file = file, module = module }
        else
            skipped = skipped + 1
        end
    end
    if #catalogs == 0 then problems[#problems + 1] = "no CWV catalog module with a VARIANTS list could be loaded" end
    if ctx.plant and catalogs[1] then
        local planted = {}
        for i, v in ipairs(catalogs[1].module.VARIANTS) do planted[i] = v end
        planted[#planted + 1] = { key = "vt2_planted_variant", base_weapon = "vt2_planted_missing_item" }
        catalogs[1] = { file = catalogs[1].file, module = setmetatable({ VARIANTS = planted }, { __index = catalogs[1].module }) }
    end

    for _, catalog in ipairs(catalogs) do
        local m = catalog.module
        for _, variant in ipairs(m.VARIANTS) do
            local key = tostring(variant.key or variant.item_key or "?")
            if variant.base_weapon ~= nil then
                checked = checked + 1
                if not rawget(ItemMasterList, variant.base_weapon) then
                    problems[#problems + 1] = catalog.file .. ": " .. key .. ": base_weapon " .. tostring(variant.base_weapon) .. " is not in ItemMasterList"
                end
            end
            if type(variant.template) == "string" then
                checked = checked + 1
                if variant.template:sub(1, 4) ~= "cwv_" and not rawget(Weapons, variant.template) then
                    problems[#problems + 1] = catalog.file .. ": " .. key .. ": template " .. variant.template .. " is not in Weapons"
                end
            end
            for _, field in ipairs({ "careers", "default_careers" }) do
                for _, career in ipairs(type(variant[field]) == "table" and variant[field] or {}) do
                    checked = checked + 1
                    if not rawget(CareerSettings, career) then problems[#problems + 1] = catalog.file .. ": " .. key .. ": " .. field .. " names unknown career " .. tostring(career) end
                end
            end
        end
        for _, career in ipairs(type(m.ALL_CAREERS) == "table" and m.ALL_CAREERS or {}) do
            checked = checked + 1
            if not rawget(CareerSettings, career) then problems[#problems + 1] = catalog.file .. ": ALL_CAREERS names unknown career " .. tostring(career) end
        end
    end
    local files = {}
    for _, c in ipairs(catalogs) do files[#files + 1] = c.file end
    notes[#notes + 1] = string.format("catalogs checked: %s; %d other _cwv_ modules are not data catalogs", table.concat(files, ", "), skipped)
    return { name = "cwv_variant_catalogs", checked = checked, problems = problems, notes = notes }
end
