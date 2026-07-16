return function(H, repo_root)
	local function read(path)
		local file = assert(io.open(path, "rb"))
		local value = file:read("*a")
		file:close()
		return value
	end

	local root = repo_root .. "/weapons_of_chaos/"
	local Policy = assert(loadfile(root
		.. "scripts/mods/weapons_of_chaos/_woc_inventory_icons.lua"))()
	local main = read(root .. "scripts/mods/weapons_of_chaos/weapons_of_chaos.lua")
	local data = read(root .. "scripts/mods/weapons_of_chaos/weapons_of_chaos_data.lua")
	local package = read(root .. "resource_packages/weapons_of_chaos/weapons_of_chaos.package")

	H.test("WOC Blightreaper icon is safe only in injected renderers", function()
		local icon, custom = Policy.resolve(Policy.ICON, "hero_view", "vanilla_sword")
		H.equal(icon, Policy.ICON)
		H.equal(custom, true)
		icon, custom = Policy.resolve(Policy.ICON, "athanor_top", "vanilla_sword")
		H.equal(icon, "vanilla_sword")
		H.equal(custom, true)
		H.equal(Policy.resolve("vanilla_icon", "hero_view", "fallback"), "vanilla_icon")
	end)

	H.test("WOC packages and injects the authored Blightreaper icon", function()
		H.truthy(data:find('"icon_wpn_blightreaper"', 1, true))
		for _, renderer in ipairs({ "ingame_ui", "hero_view", "loading_view", "popup_manager" }) do
			H.truthy(data:find('"' .. renderer
				.. '", "materials/ui/icon_wpn_blightreaper"', 1, true), renderer)
		end
		H.truthy(package:find('"materials/ui/icon_wpn_blightreaper"', 1, true))
		H.truthy(package:find(
			'"gui/1080p/single_textures/weapons_of_chaos/icon_wpn_blightreaper"', 1, true))
		local png = assert(io.open(root
			.. "gui/1080p/single_textures/weapons_of_chaos/icon_wpn_blightreaper.png", "rb"))
		local signature = png:read(8)
		png:close()
		H.equal(signature, "\137PNG\13\10\26\10")
	end)

	H.test("WOC item owns custom icon and resident Athanor fallback", function()
		H.truthy(main:find("entry.inventory_icon  = INVENTORY_ICON", 1, true))
		H.truthy(main:find("entry.cim_inventory_icon_fallback = base.inventory_icon", 1, true))
		H.truthy(main:find("issue613_blightreaper_inventory_icon_contract", 1, true))
		H.truthy(main:find('local BASE_WEAPON = "es_1h_sword"', 1, true))
	end)
end
