local P = ...
local function show(key)
    local item = rawget(ItemMasterList, key)
    io.write(key, " can_wield(", tostring(#item.can_wield), ")=", table.concat(item.can_wield, ","), " all=", tostring(item.can_wield == CanWieldAllItemTemplates), "\n")
end
show("es_2h_sword"); show("es_bastard_sword"); show("es_halberd"); show("dr_2h_axe"); show("we_longbow")
