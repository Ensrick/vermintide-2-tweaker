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
mod:command("armory", "Open the Armory (weapon compendium)", function()
	if mod._gut_open_compendium then mod._gut_open_compendium("armory")
	else mod:echo("Compendium not ready (inject module didn't load).") end
end)

mod:command("bestiary", "Open the Bestiary (enemy compendium)", function()
	if mod._gut_open_compendium then mod._gut_open_compendium("bestiary")
	else mod:echo("Compendium not ready (inject module didn't load).") end
end)

return M
