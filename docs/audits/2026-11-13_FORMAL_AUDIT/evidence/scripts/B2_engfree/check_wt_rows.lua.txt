local P = ...
local REPO = "<repos>/vermintide-2-tweaker"
rawset(_G, "get_mod", function(id) return { dofile = function(_, path) return assert(loadfile(REPO .. "/weapon_tweaker/" .. path .. ".lua"))() end } end)
local data = get_mod("wt"):dofile("scripts/mods/weapon_tweaker/wt_unlock_data")
local n, missing, notemplate, native, cwv, careers = 0, 0, 0, 0, 0, 0
local per = {}
for career, weapons in pairs(data.weapon_unlock_map) do
    careers = careers + 1
    for _, key in ipairs(weapons) do
        n = n + 1
        local item = rawget(ItemMasterList, key)
        if key:sub(1, 4) == "cwv_" then cwv = cwv + 1
        elseif not item then missing = missing + 1
        elseif not rawget(Weapons, item.template or item.temporary_template) then notemplate = notemplate + 1
        else for _, c in ipairs(item.can_wield or {}) do if c == career then native = native + 1; per[career] = (per[career] or 0) + 1 end end end
    end
end
io.write(string.format("WT_ROWS careers=%d rows=%d cwv=%d missing=%d no_template=%d already_native=%d\n", careers, n, cwv, missing, notemplate, native))
local parts = {}
for c, v in pairs(per) do parts[#parts + 1] = c .. "=" .. v end
table.sort(parts)
io.write("WT_NATIVE_BY_CAREER " .. table.concat(parts, " ") .. "\n")
