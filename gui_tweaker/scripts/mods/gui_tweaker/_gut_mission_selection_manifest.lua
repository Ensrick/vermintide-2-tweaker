-- Independent mission-selection feature owners: one failure must not suppress the other.
local mod = get_mod("gut")
pcall(mod.dofile, mod, "scripts/mods/gui_tweaker/_gut_mission_map")
pcall(mod.dofile, mod, "scripts/mods/gui_tweaker/_gut_guard649_mission_completion")
return true
