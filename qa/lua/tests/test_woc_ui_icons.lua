-- #1687: every atlas icon WOC hands to the vanilla UI must exist in the live
-- atlas. VT2 6.13.0 removed the 6.12.1 key the Poisoned Edge row used, and a
-- missing atlas name reaches Gui_bitmap (ui_renderer.lua:117), the
-- "Material 'X' not found in Gui" fatal (docs/BUG_CLASSES.md section 23).

return function(H, repo_root)
	local root = repo_root .. "/weapons_of_chaos/scripts/mods/weapons_of_chaos/"
	local moveset = dofile(root .. "_woc_blightreaper_moveset.lua")
	local REMOVED_6130 = "kerillian_shade_increased_damage_on_poisoned_or_bleeding_enemy"

	local function read(path)
		local file = assert(io.open(path, "rb"))
		local value = file:read("*a")
		file:close()
		return value
	end

	local function load_guard()
		return assert(loadfile(root .. "_woc_ui_icons.lua"), "_woc_ui_icons.lua missing")()
	end

	-- Test-local seam for UIAtlasHelper.has_atlas_settings_by_texture_name
	-- (ui_atlas_helper.lua:605): names present at Game Version 6.13.0 (93dea911).
	local ATLAS_6130 = {
		shade_2_2 = true,                  -- gui_icons_atlas.lua:8684
		mutator_icon_death_spirits = true, -- gui_icons_atlas.lua:3182
		icons_placeholder = true,          -- gui_icons_atlas.lua:5674
		icon_wpn_emp_sword_02_t1 = true,   -- gui_items_atlas.lua:19226
	}
	local function atlas(names)
		return {
			has_atlas_settings_by_texture_name = function(name)
				return names[name] == true
			end,
		}
	end
	local function without(names, removed)
		local copy = {}
		for key, value in pairs(names) do
			if key ~= removed then copy[key] = value end
		end
		return copy
	end

	H.test("WOC trait icon constants resolve in the 6.13.0 atlas", function()
		H.truthy(moveset.POISON_TRAIT_ICON ~= REMOVED_6130,
			"Poisoned Edge still uses the atlas key 6.13.0 removed")
		H.truthy(ATLAS_6130[moveset.POISON_TRAIT_ICON],
			"Poisoned Edge icon " .. tostring(moveset.POISON_TRAIT_ICON) .. " not in 6.13.0 atlas")
		H.truthy(ATLAS_6130[moveset.SHYISH_CURSE_ICON],
			"Shyish curse icon " .. tostring(moveset.SHYISH_CURSE_ICON) .. " not in 6.13.0 atlas")
	end)

	H.test("WOC trait rows install with resident icons and no rewrite", function()
		local guard = load_guard()
		local weapon_traits = { traits = {} }
		local ok, reason, rewrites = guard.install_trait_rows(moveset, weapon_traits, {},
			atlas(ATLAS_6130))
		H.equal(ok, true)
		H.equal(reason, "installed")
		H.equal(#rewrites, 0)
		H.equal(weapon_traits.traits[moveset.POISON_TRAIT].icon, "shade_2_2")
		H.equal(weapon_traits.traits[moveset.SHYISH_CURSE_TRAIT].icon, "mutator_icon_death_spirits")
		H.equal(guard.audit(atlas(ATLAS_6130), {
			{ label = "Poisoned Edge", icon = "shade_2_2", preferred = moveset.POISON_TRAIT_ICON },
		}), nil)
	end)

	H.test("WOC guard rewrites a kept 6.12.1 row and falls back on atlas drift", function()
		local guard = load_guard()
		-- A row an earlier install kept with the removed key is repaired.
		local weapon_traits = { traits = {
			[moveset.POISON_TRAIT] = { name = moveset.POISON_TRAIT, icon = REMOVED_6130 },
		} }
		local logged = {}
		local ok, _, rewrites = guard.install_trait_rows(moveset, weapon_traits, {},
			atlas(ATLAS_6130), function(row) logged[#logged + 1] = row end)
		H.equal(ok, true)
		H.equal(#rewrites, 1)
		H.equal(#logged, 1)
		H.deep_equal(rewrites[1], { key = moveset.POISON_TRAIT, from = REMOVED_6130,
			to = guard.FALLBACK_ICON, reason = "fallback" })
		H.equal(weapon_traits.traits[moveset.POISON_TRAIT].icon, "icons_placeholder")

		-- A future patch that drops shade_2_2: the row falls back, the live icon
		-- still resolves, and the audit reports the drift instead of passing.
		local drifted = atlas(without(ATLAS_6130, "shade_2_2"))
		local fresh = { traits = {} }
		guard.install_trait_rows(moveset, fresh, {}, drifted)
		H.equal(fresh.traits[moveset.POISON_TRAIT].icon, "icons_placeholder")
		H.equal(fresh.traits[moveset.SHYISH_CURSE_TRAIT].icon, "mutator_icon_death_spirits")
		local failure = guard.audit(drifted, {
			{ label = "Poisoned Edge", icon = fresh.traits[moveset.POISON_TRAIT].icon,
				preferred = moveset.POISON_TRAIT_ICON },
		})
		H.truthy(failure and failure:find("left the UI atlas", 1, true), tostring(failure))
		failure = guard.audit(atlas(ATLAS_6130), {
			{ label = "Poisoned Edge", icon = REMOVED_6130 },
		})
		H.truthy(failure and failure:find("Gui_bitmap fatal", 1, true), tostring(failure))
	end)

	H.test("WOC audit rows cover both traits and the Athanor fallback icon", function()
		local guard = load_guard()
		local weapon_traits = { traits = {} }
		local ok = guard.install_and_log(moveset, weapon_traits, {}, atlas(ATLAS_6130), "offline")
		H.equal(ok, true)
		local masters = {
			es_1h_sword = { inventory_icon = "icon_wpn_emp_sword_02_t1" },
			woc_blightreaper = { cim_inventory_icon_fallback = "icon_wpn_emp_sword_02_t1" },
		}
		local rows = guard.woc_icon_rows(weapon_traits.traits, moveset, masters,
			"woc_blightreaper", "es_1h_sword")
		H.equal(#rows, 3)
		H.equal(guard.audit(atlas(ATLAS_6130), rows), nil)
		-- The pre-fix Poisoned Edge row is the audited crash.
		weapon_traits.traits[moveset.POISON_TRAIT].icon = REMOVED_6130
		rows = guard.woc_icon_rows(weapon_traits.traits, moveset, masters,
			"woc_blightreaper", "es_1h_sword")
		H.truthy(guard.audit(atlas(ATLAS_6130), rows):find("Poisoned Edge icon", 1, true))
		-- Blightreaper disabled: no item row, traits are still audited.
		H.equal(#guard.woc_icon_rows(weapon_traits.traits, moveset, {},
			"woc_blightreaper", "es_1h_sword"), 2)
	end)

	H.test("WOC icon guard fails closed without a usable atlas helper", function()
		local guard = load_guard()
		H.deep_equal({ guard.resolve(nil, "shade_2_2") },
			{ "icons_placeholder", "atlas_unavailable" })
		local throwing = { has_atlas_settings_by_texture_name = function() error("boom") end }
		H.deep_equal({ guard.resolve(throwing, "shade_2_2") },
			{ "icons_placeholder", "atlas_unavailable" })
		H.deep_equal({ guard.resolve(atlas({}), "missing") },
			{ "icons_placeholder", "fallback_unverified" })
		H.deep_equal({ guard.resolve(atlas(ATLAS_6130), "icon_wpn_emp_sword_02_t1") },
			{ "icon_wpn_emp_sword_02_t1", "present" })
		H.truthy(guard.audit(nil, {}):find("unavailable", 1, true))
		H.truthy(guard.CUSTOM_MATERIAL_ICONS.icon_wpn_blightreaper)
		H.truthy(guard.CUSTOM_MATERIAL_ICONS.icon_bg_cursed)
	end)

	H.test("WOC routes every trait-row install and atlas fallback through the guard", function()
		local main = read(root .. "weapons_of_chaos.lua")
		local owner = read(root .. "_woc_relic_registration_owner.lua")
		local package = read(repo_root
			.. "/weapons_of_chaos/resource_packages/weapons_of_chaos/weapons_of_chaos.package")
		for label, source in pairs({ main = main, owner = owner }) do
			H.equal(source:find("_moveset.install_intrinsic_trait_rows(", 1, true), nil,
				label .. " installs trait rows without the atlas guard")
			H.truthy(source:find("_ui_icons.install_and_log(_moveset,", 1, true), label)
		end
		H.truthy(owner:find("entry.cim_inventory_icon_fallback = (_ui_icons.resolve(", 1, true))
		H.truthy(main:find('mod:dofile("scripts/mods/weapons_of_chaos/_woc_ui_icons")', 1, true))
		local check = main:match('_rt_register%("issue655_blightreaper_trait_contract".-\nend%)')
		H.truthy(check, "issue655 check missing")
		H.truthy(check:find('_ui_icons.audit(rawget(_G, "UIAtlasHelper"), _ui_icons.woc_icon_rows(',
			1, true), "issue655 check does not audit WOC atlas icons")
		H.truthy(package:find('"scripts/mods/weapons_of_chaos/_woc_ui_icons"', 1, true))
	end)

	local vanilla = "C:/Users/danjo/source/repos/Vermintide-2-Source-Code/"
		.. "scripts/ui/atlas_settings/gui_icons_atlas.lua"
	local probe = io.open(vanilla, "rb")
	if probe then probe:close() end
	H.test_if(probe ~= nil, "WOC trait icons exist in the decompiled vanilla atlas", function()
		local source = read(vanilla)
		for _, name in ipairs({ moveset.POISON_TRAIT_ICON, moveset.SHYISH_CURSE_ICON,
				"icons_placeholder" }) do
			H.truthy(source:find("\n\t" .. name .. " = {", 1, true), name)
		end
		H.equal(source:find("\n\t" .. REMOVED_6130 .. " = {", 1, true), nil)
	end, "optional decompiled vanilla source is unavailable")
end
