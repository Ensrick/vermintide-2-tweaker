-- qa/integration/suites/vanilla_selfcheck.lua (WP-T-03): proves the loaded tables are the real vanilla data.
-- Every melee or ranged ItemMasterList entry has a Weapons template (its template or temporary_template), every
-- career it can be wielded by is in CareerSettings, and the tables are at least as large as on game 6.13.0
-- (decompile 93dea911): ItemMasterList 2979, Weapons 183, BuffTemplates 1547, Breeds 79, CareerSettings 30.
-- empire_soldier_tutorial is the prologue's hero, wielded by tutorial items but not a CareerSettings career.
-- Planted (selftest): one extra melee item whose template does not exist.
local MINIMUM = { ItemMasterList = 2979, Weapons = 183, BuffTemplates = 1547, Breeds = 79, CareerSettings = 30 }

return function(ctx)
    local problems, checked = {}, 0
    local items = {}
    for key, item in pairs(ItemMasterList) do items[#items + 1] = { key, item } end
    table.sort(items, function(a, b) return a[1] < b[1] end)
    if ctx.plant then items[#items + 1] = { "vt2_planted_item", { slot_type = "melee", template = "vt2_planted_missing_template", can_wield = { "es_knight" } } } end

    for _, pair in ipairs(items) do
        local key, item = pair[1], pair[2]
        local slot = ctx.real(item.slot_type, key .. ".slot_type")
        if slot == "melee" or slot == "ranged" then
            checked = checked + 1
            local template = ctx.real(item.template or item.temporary_template, key .. ".template")
            if not rawget(Weapons, template) then problems[#problems + 1] = key .. ": template " .. tostring(template) .. " is not in Weapons" end
            for _, career in ipairs(item.can_wield or {}) do
                if not rawget(CareerSettings, ctx.real(career, key .. ".can_wield")) and career ~= "empire_soldier_tutorial" then
                    problems[#problems + 1] = key .. ": can_wield names unknown career " .. tostring(career)
                end
            end
        end
    end
    for name, minimum in pairs(MINIMUM) do
        checked = checked + 1
        local n = ctx.count(rawget(_G, name))
        if n < minimum then problems[#problems + 1] = string.format("%s has %d entries, fewer than the %d of game 6.13.0", name, n, minimum) end
    end
    return { name = "vanilla_selfcheck", checked = checked, problems = problems, notes = {} }
end
