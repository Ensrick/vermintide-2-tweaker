return function(H, repo_root)
	local policy = dofile(repo_root
		.. "/character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_musket_ammo_hud.lua")

	local function fixture()
		local owner = {}
		local ammo_unit = {}
		local item_data = { name = "Old Musket" }
		local slot_data = {
			item_data = item_data,
			right_unit_1p = ammo_unit,
		}
		local equipment = {
			wielded_slot = "slot_melee",
			slots = { slot_melee = slot_data },
		}
		local controller = {
			extension_for = function(_, queried_owner, slot_name)
				if queried_owner == owner and slot_name == "slot_melee" then
					return { unit = ammo_unit }
				end
			end,
		}
		local get_template = function()
			return { ammo_data = { ammo_hand = "right" } }
		end
		return owner, ammo_unit, item_data, slot_data, equipment, controller, get_template
	end

	H.test("CWV #1108 selects the wielded primary-slot Old Musket extension", function()
		local owner, _, item_data, slot_data, equipment, controller, get_template = fixture()
		local selected_item, selected_slot, extension = policy.select(
			controller, owner, equipment, get_template)
		H.equal(selected_item, item_data)
		H.equal(selected_slot, slot_data)
		H.truthy(extension)
	end)

	H.test("CWV #1108 rejects ranged, non-ammo, and mismatched primary slots", function()
		local owner, _, _, slot_data, equipment, controller, get_template = fixture()
		equipment.wielded_slot = "slot_ranged"
		H.equal(policy.select(controller, owner, equipment, get_template), nil)
		equipment.wielded_slot = "slot_melee"
		H.equal(policy.select(controller, owner, equipment, function() return {} end), nil)
		slot_data.right_unit_1p = {}
		H.equal(policy.select(controller, owner, equipment, get_template), nil)
	end)

	H.test("CWV #1108 refreshes count and focus once from controller state", function()
		local owner, _, item_data, slot_data, equipment, controller, get_template = fixture()
		local inventory = { equipment = function() return equipment end }
		local updates, focuses = 0, 0
		local ui = {
			player = { player_unit = owner },
			_update_ammo_count = function(_, selected_item, selected_slot, selected_owner)
				updates = updates + 1
				H.equal(selected_item, item_data)
				H.equal(selected_slot, slot_data)
				H.equal(selected_owner, owner)
			end,
			_set_ammo_text_focus = function(_, focused)
				focuses = focuses + 1
				H.truthy(focused)
			end,
		}
		local adapter = policy.new(controller, {
			get_item_template = get_template,
			get_inventory = function() return inventory end,
		})
		H.truthy(adapter:refresh(ui))
		H.equal(updates, 1)
		H.equal(focuses, 1)
	end)

	H.test("CWV #1108 installs one post-sync hook per native HUD", function()
		local hooks = {}
		local mod = {
			hook_safe = function(_, class_name, method_name)
				hooks[#hooks + 1] = class_name .. "." .. method_name
			end,
		}
		local adapter = policy.install(mod, { extension_for = function() end })
		H.equal(#hooks, 2)
		H.equal(hooks[1], "EquipmentUI._sync_player_equipment")
		H.equal(hooks[2], "GamePadEquipmentUI._sync_player_equipment")
		H.equal(adapter:contract_error(), nil)
	end)
end
