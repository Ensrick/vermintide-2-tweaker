-- qa/integration/suites/wt_unlock_map.lua (WP-T-03): weapon_tweaker's unlock rows against the real vanilla tables.
-- For both streams (mod id wt -> weapon_tweaker, wt_dev -> weapon_tweaker_dev), loaded the way the mods load it
-- (mod:dofile of wt_unlock_data): every career key of weapon_unlock_map is in CareerSettings; every weapon key is in
-- ItemMasterList or starts with cwv_ (registered by Character Weapon Variants at run time); the item's template is
-- in Weapons. A row naming a weapon the career already wields in vanilla is reported as a note, never a problem: on
-- 2026-11-13, 260 of the 930 rows were such rows (known result, docs/program/wp/T.md WP-T-03 guardrails).
-- Planted (selftest): one row with an item key that does not exist.
local STREAMS = {
    { id = "wt", path = "scripts/mods/weapon_tweaker/wt_unlock_data" },
    { id = "wt_dev", path = "scripts/mods/weapon_tweaker_dev/wt_unlock_data" },
}

return function(ctx)
    local problems, notes, checked = {}, {}, 0
    for _, stream in ipairs(STREAMS) do
        local data = ctx.get_mod(stream.id):dofile(stream.path)
        local map = data and data.weapon_unlock_map
        if type(map) ~= "table" then
            problems[#problems + 1] = stream.id .. ": wt_unlock_data has no weapon_unlock_map table"
        else
            local careers = {}
            for career in pairs(map) do careers[#careers + 1] = career end
            table.sort(careers)
            local redundant, cwv = 0, 0
            for _, career in ipairs(careers) do
                local weapons = map[career]
                if ctx.plant and career == careers[1] then
                    weapons = { unpack(weapons) }
                    weapons[#weapons + 1] = "vt2_planted_missing_item"
                end
                if not rawget(CareerSettings, career) then problems[#problems + 1] = stream.id .. ": unknown career " .. tostring(career) end
                for _, key in ipairs(weapons) do
                    checked = checked + 1
                    local item = rawget(ItemMasterList, key)
                    if type(key) ~= "string" then
                        problems[#problems + 1] = stream.id .. ": " .. career .. ": a weapon key is not a string"
                    elseif key:sub(1, 4) == "cwv_" then
                        cwv = cwv + 1
                    elseif not item then
                        problems[#problems + 1] = stream.id .. ": " .. career .. ": " .. key .. " is not in ItemMasterList"
                    else
                        local template = ctx.real(item.template or item.temporary_template, key .. ".template")
                        if not rawget(Weapons, template) then
                            problems[#problems + 1] = stream.id .. ": " .. career .. ": " .. key .. " template " .. tostring(template) .. " is not in Weapons"
                        end
                        for _, c in ipairs(item.can_wield or {}) do
                            if ctx.real(c, key .. ".can_wield") == career then redundant = redundant + 1 end
                        end
                    end
                end
            end
            notes[#notes + 1] = string.format("%s: %d rows name a weapon the career already wields in vanilla (reported, not a failure); %d cwv_ rows", stream.id, redundant, cwv)
        end
    end
    return { name = "wt_unlock_map", checked = checked, problems = problems, notes = notes }
end
