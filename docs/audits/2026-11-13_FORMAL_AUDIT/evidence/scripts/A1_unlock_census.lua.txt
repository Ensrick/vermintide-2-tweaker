-- A1 read-only census. Run from repo root with the vendored lua5.1.exe.
-- Loads wt_unlock_data + native ownership + wield patches as pure data and reports
-- native vs cross pairs, widget coverage, and patches/bulk overlap.
local root = "weapon_tweaker/scripts/mods/weapon_tweaker/"
local data = dofile(root .. "wt_unlock_data.lua")
local native = dofile(root .. "_wt_native_weapon_ownership.lua")
local map = data.weapon_unlock_map
local total, nat, cross = 0, 0, 0
local careers = {}
for c in pairs(map) do careers[#careers+1] = c end
table.sort(careers)
local pairs_set = {}
for _, c in ipairs(careers) do
  local n, x = 0, 0
  for _, w in ipairs(map[c]) do
    total = total + 1
    pairs_set["unlock_" .. c .. "_" .. w] = native.is_native(c, w) and "native" or "cross"
    if native.is_native(c, w) then nat = nat + 1; n = n + 1 else cross = cross + 1; x = x + 1 end
  end
  print(string.format("%-18s total=%3d native=%3d cross=%3d", c, #map[c], n, x))
end
print(string.format("TOTAL pairs=%d native=%d cross=%d", total, nat, cross))
-- widget coverage
local f = assert(io.open(root .. "weapon_tweaker_data.lua", "r")); local src = f:read("*a"); f:close()
local widgets, wn = {}, 0
for id, def in src:gmatch('setting_id%s*=%s*"(unlock_[%w_]+)"%s*,%s*type%s*=%s*"checkbox"%s*,%s*default_value%s*=%s*([%w_]+)') do
  widgets[id] = def; wn = wn + 1
end
print("static unlock_* widgets in _data.lua:", wn)
local no_widget, no_reader, native_default_false, cross_default_true = {}, {}, {}, {}
for id, kind in pairs(pairs_set) do
  if not widgets[id] then no_widget[#no_widget+1] = id .. " (" .. kind .. ")"
  elseif kind == "native" and widgets[id] == "false" then native_default_false[#native_default_false+1] = id
  elseif kind == "cross" and widgets[id] == "true" then cross_default_true[#cross_default_true+1] = id end
end
for id in pairs(widgets) do if not pairs_set[id] then no_reader[#no_reader+1] = id end end
table.sort(no_widget); table.sort(no_reader); table.sort(native_default_false); table.sort(cross_default_true)
print("map pairs with NO static widget:", #no_widget); for i = 1, math.min(#no_widget, 25) do print("   " .. no_widget[i]) end
print("static widgets with NO map pair (setting without reader):", #no_reader); for i = 1, math.min(#no_reader, 40) do print("   " .. no_reader[i]) end
print("native pairs default OFF:", #native_default_false); for i = 1, math.min(#native_default_false, 25) do print("   " .. native_default_false[i]) end
print("cross pairs default ON:", #cross_default_true); for i = 1, math.min(#cross_default_true, 40) do print("   " .. cross_default_true[i]) end
-- wield patch overlap
local wp = dofile(root .. "wt_wield_patches.lua")
local overlap = 0
for tpl, row in pairs(wp.patches) do
  local b = wp.bulk[tpl]
  if b and b ~= row then
    for career, ev in pairs(row) do
      if b[career] and b[career] ~= ev then overlap = overlap + 1; print("CONFLICT patches vs bulk", tpl, career, ev, b[career]) end
    end
  end
end
local np, nb = 0, 0
for _ in pairs(wp.patches) do np = np + 1 end
for _ in pairs(wp.bulk) do nb = nb + 1 end
print("wield patches templates:", np, "bulk templates:", nb, "conflicting cells:", overlap)
