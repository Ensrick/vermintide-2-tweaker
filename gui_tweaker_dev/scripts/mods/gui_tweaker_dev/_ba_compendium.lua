--[[
	_ba_compendium.lua  (Bestiary & Armory feature entry, inside gut)

	Owns the merged Armory (weapon compendium) + Bestiary (enemy compendium)
	feature: dynamic data providers, chat commands, and (in a later build phase)
	the custom HeroViewState + Overview buttons.

	Data layer is PURE-DYNAMIC — weapons enumerated live from ItemMasterList,
	enemies from Breeds — so newer content appears automatically with no
	hardcoded roster. Origin: a merge of the standalone Armory + Bestiary mods,
	rebuilt and migrated into Tweaker: GUI.

	Build phases (see _ba_* files):
	  [done] data providers + dump commands (_ba_weapon_provider, _ba_enemy_provider, _ba_attack_labeler)
	  [next] HeroViewState "compendium" + scenegraph + viewport + previewer
	  [next] weapon/enemy panel controllers, statistics tracking, DLC gate, VMF options
]]

local mod = get_mod("gut_dev")

local M = {}

M.weapons = mod:dofile("scripts/mods/gui_tweaker_dev/_ba_weapon_provider")
M.enemies = mod:dofile("scripts/mods/gui_tweaker_dev/_ba_enemy_provider")

-- Debug probes: verify the live enumeration in-game without the UI.
mod:command("ba_dump_weapons", "Bestiary&Armory: dump live weapon enumeration to console", function()
	M.weapons.dump()
end)

mod:command("ba_dump_breeds", "Bestiary&Armory: dump live enemy-breed enumeration to console", function()
	M.enemies.dump()
end)

-- Open commands. Phase 0: open the HeroViewStateCompendium stub panel in the hero
-- menu (registered by _ba_heroview_inject.lua). The Armory/Bestiary split + lists
-- + 3D preview land in later phases; the data layer (/ba_dump_*) is already live.
local function _gut_cmd_armory()
	if mod._gut_open_compendium then mod._gut_open_compendium("armory")
	else mod:echo("Compendium not ready (inject module didn't load).") end
end

local function _gut_cmd_bestiary()
	if mod._gut_open_compendium then mod._gut_open_compendium("bestiary")
	else mod:echo("Compendium not ready (inject module didn't load).") end
end

-- (#212) The short names collide with the standalone Armory / Bestiary mods: VMF
-- rejects the second registration of a taken name with an error, and which mod
-- loses depends on load order (registering "armory" here unconditionally would
-- break the standalone mod on machines where gut loads first). So the prefixed
-- commands are always registered, and the short aliases are claimed in
-- on_all_mods_loaded (chained, same pattern as gui_tweaker_dev.lua) ONLY when the
-- owning mod is absent -- get_mod() is definitive at that point.
mod:command("gut_armory", "Open the Armory (weapon compendium)", _gut_cmd_armory)
mod:command("gut_bestiary", "Open the Bestiary (enemy compendium)", _gut_cmd_bestiary)

local _ba_prev_on_all_mods_loaded = mod.on_all_mods_loaded
mod.on_all_mods_loaded = function(...)
	if _ba_prev_on_all_mods_loaded then _ba_prev_on_all_mods_loaded(...) end
	if not get_mod("armory") then
		mod:command("armory", "Open the Armory (weapon compendium)", _gut_cmd_armory)
	end
	if not get_mod("bestiary") then
		mod:command("bestiary", "Open the Bestiary (enemy compendium)", _gut_cmd_bestiary)
	end
end

-- Phase 1 (#217): the hero-menu top-tab buttons (Armory / Bestiary). Loaded from
-- here (an _ba_ feature file the concurrent menu/localization sweep does NOT touch)
-- rather than the main lua, to keep the contended main-file edit down to the
-- MOD_VERSION bump. Runs AFTER _ba_heroview_inject dofiled mod._gut_open_compendium
-- (main dofile order), which the tabs' click handler calls.
M.tabs = mod:dofile("scripts/mods/gui_tweaker_dev/_ba_compendium_tabs")

return M
