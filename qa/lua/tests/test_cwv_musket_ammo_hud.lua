return function(H, repo_root)
	local policy = dofile(repo_root
		.. "/character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_musket_ammo_hud.lua")

	local function fixture(ammo_hand)
		local owner = {}
		local ammo_unit = {}
		local item_data = { name = "es_handgun", backend_id = "cwv_es_musket_custom_001" }
		local slot_data = { item_data = item_data }
		slot_data[(ammo_hand or "right") .. "_unit_1p"] = ammo_unit
		local equipment = {
			wielded_slot = "slot_melee",
			slots = { slot_melee = slot_data },
		}
		local extension = { unit = ammo_unit }
		local controller = {
			extension_for = function(_, queried_owner, slot_name)
				if queried_owner == owner and slot_name == "slot_melee" then
					return extension
				end
			end,
		}
		local get_template = function()
			return { ammo_data = { ammo_hand = ammo_hand or "right" } }
		end
		return {
			owner = owner,
			ammo_unit = ammo_unit,
			item_data = item_data,
			slot_data = slot_data,
			equipment = equipment,
			extension = extension,
			controller = controller,
			get_template = get_template,
		}
	end

	H.test("CWV #1108 selects either exact ammo hand from the wielded primary slot", function()
		for _, ammo_hand in ipairs({ "right", "left" }) do
			local f = fixture(ammo_hand)
			local item, slot, extension = policy.select(
				f.controller, f.owner, f.equipment, f.get_template)
			H.equal(item, f.item_data, ammo_hand .. " item")
			H.equal(slot, f.slot_data, ammo_hand .. " slot")
			H.equal(extension, f.extension, ammo_hand .. " extension")
		end
	end)

	H.test("CWV #1108 rejects every unproven primary-slot selection", function()
		local f = fixture("right")
		H.equal(policy.select(nil, f.owner, f.equipment, f.get_template), nil)
		H.equal(policy.select(f.controller, nil, f.equipment, f.get_template), nil)
		f.equipment.wielded_slot = "slot_ranged"
		H.equal(policy.select(f.controller, f.owner, f.equipment, f.get_template), nil)
		f.equipment.wielded_slot = "slot_melee"
		H.equal(policy.select({ extension_for = function() end },
			f.owner, f.equipment, f.get_template), nil)
		H.equal(policy.select(f.controller, f.owner, f.equipment, function() return {} end), nil)
		H.equal(policy.select(f.controller, f.owner, f.equipment,
			function() return { ammo_data = { ammo_hand = "invalid" } } end), nil)
		f.slot_data.right_unit_1p = {}
		H.equal(policy.select(f.controller, f.owner, f.equipment, f.get_template), nil)
		f.slot_data.item_data = nil
		H.equal(policy.select(f.controller, f.owner, f.equipment, f.get_template), nil)
	end)

	H.test("CWV #1108 refreshes owner and spectator HUDs with edge-only receipts", function()
		local f = fixture("right")
		local inventory = { equipment = function() return f.equipment end }
		local updates, focuses, edges = 0, 0, {}
		local adapter = policy.new(f.controller, {
			get_item_template = f.get_template,
			get_inventory = function(owner)
				H.equal(owner, f.owner)
				return inventory
			end,
			log = function(edge) edges[#edges + 1] = edge end,
		})
		local function new_ui(player_field)
			return {
				player = player_field,
				_update_ammo_count = function(_, item, slot, owner)
					updates = updates + 1
					H.equal(item, f.item_data)
					H.equal(slot, f.slot_data)
					H.equal(owner, f.owner)
				end,
				_set_ammo_text_focus = function(_, focused)
					focuses = focuses + 1
					H.equal(focused, true)
				end,
			}
		end

		local owner_ui = new_ui({ player_unit = f.owner })
		H.truthy(adapter:refresh(owner_ui))
		H.truthy(adapter:refresh(owner_ui))
		H.equal(updates, 2)
		H.equal(focuses, 2)
		H.equal(#edges, 1)
		H.equal(edges[1], "engage")

		f.equipment.wielded_slot = "slot_ranged"
		H.equal(adapter:refresh(owner_ui), false)
		H.equal(adapter:refresh(owner_ui), false)
		H.equal(#edges, 2)
		H.equal(edges[2], "release")

		f.equipment.wielded_slot = "slot_melee"
		local spectator_ui = new_ui(nil)
		spectator_ui._is_spectator = true
		spectator_ui._spectated_player = { player_unit = f.owner }
		H.truthy(adapter:refresh(spectator_ui))
		H.equal(updates, 3)
		H.equal(focuses, 3)
	end)

	H.test("CWV #1108 adapter fails closed without UI or inventory dependencies", function()
		local f = fixture("right")
		local adapter = policy.new(f.controller, {
			get_item_template = f.get_template,
			get_inventory = function() return nil end,
		})
		H.equal(adapter:refresh(nil), false)
		H.equal(adapter:refresh({ player = {} }), false)
		H.equal(adapter:refresh({ player = { player_unit = f.owner } }), false)

		local missing_methods = policy.new(f.controller, {
			get_item_template = f.get_template,
			get_inventory = function()
				return { equipment = function() return f.equipment end }
			end,
		})
		H.equal(missing_methods:refresh({ player = { player_unit = f.owner } }), false)
	end)

	H.test("CWV #1108 installer drives both exact native post-sync wrappers", function()
		local f = fixture("right")
		local hooks = {}
		local mod = {
			hook_safe = function(_, class_name, method_name, callback)
				hooks[#hooks + 1] = {
					class_name = class_name,
					method_name = method_name,
					callback = callback,
				}
			end,
		}
		local inventory = { equipment = function() return f.equipment end }
		local adapter = policy.install(mod, f.controller, {
			get_item_template = f.get_template,
			get_inventory = function() return inventory end,
			log = function() end,
		})
		H.equal(adapter:contract_error(), nil)
		H.equal(#hooks, 2)
		H.equal(hooks[1].class_name, "EquipmentUI")
		H.equal(hooks[2].class_name, "GamePadEquipmentUI")
		for _, hook in ipairs(hooks) do
			H.equal(hook.method_name, "_sync_player_equipment")
		end

		local updates, focuses = 0, 0
		for _, hook in ipairs(hooks) do
			local ui = {
				player = { player_unit = f.owner },
				_update_ammo_count = function() updates = updates + 1 end,
				_set_ammo_text_focus = function() focuses = focuses + 1 end,
			}
			hook.callback(ui, "trailing native callback argument")
		end
		H.equal(updates, 2)
		H.equal(focuses, 2)
	end)
end
