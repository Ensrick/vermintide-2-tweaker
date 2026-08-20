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
		local ranged_item = { name = "es_crossbow", backend_id = "native-ranged" }
		local ranged_slot = { item_data = ranged_item, right_unit_1p = {} }
		f.equipment.slots.slot_ranged = ranged_slot
		local inventory = { equipment = function() return f.equipment end }
		local updates, focuses, edges = 0, 0, {}
		local adapter = policy.new(f.controller, {
			get_item_template = f.get_template,
			get_inventory = function(owner)
				H.equal(owner, f.owner)
				return inventory
			end,
			is_alive = function(owner) return owner == f.owner end,
			log = function(edge) edges[#edges + 1] = edge end,
		})
		local function new_ui(player_field)
			return {
				player = player_field,
				_update_ammo_count = function(_, item, slot, owner)
					updates = updates + 1
					if item == f.item_data then
						H.equal(slot, f.slot_data)
					else
						H.equal(item, ranged_item)
						H.equal(slot, ranged_slot)
					end
					H.equal(owner, f.owner)
				end,
				_set_ammo_text_focus = function(_, focused)
					focuses = focuses + 1
					H.equal(type(focused), "boolean")
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
		H.equal(updates, 3)
		H.equal(focuses, 3)
		H.equal(#edges, 2)
		H.equal(edges[2], "release")

		f.equipment.wielded_slot = "slot_melee"
		local spectator_ui = new_ui(nil)
		spectator_ui._is_spectator = true
		spectator_ui._spectated_player = { player_unit = f.owner }
		H.truthy(adapter:refresh(spectator_ui))
		H.equal(updates, 4)
		H.equal(focuses, 4)
	end)

	H.test("CWV #1108 adapter fails closed without UI or inventory dependencies", function()
		local f = fixture("right")
		local adapter = policy.new(f.controller, {
			get_item_template = f.get_template,
			get_inventory = function() return nil end,
			is_alive = function() return true end,
		})
		H.equal(adapter:refresh(nil), false)
		H.equal(adapter:refresh({ player = {} }), false)
		H.equal(adapter:refresh({ player = { player_unit = f.owner } }), false)

		local missing_methods = policy.new(f.controller, {
			get_item_template = f.get_template,
			get_inventory = function()
				return { equipment = function() return f.equipment end }
			end,
			is_alive = function() return true end,
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
			is_alive = function() return true end,
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

	local function restoration_fixture()
		local f = fixture("right")
		local ranged_item = { name = "es_crossbow", backend_id = "native-ranged" }
		local ranged_slot = { item_data = ranged_item, right_unit_1p = {} }
		f.equipment.slots.slot_ranged = ranged_slot
		local inventory = { equipment = function() return f.equipment end }
		local alive = true
		local inventory_available = true
		local template_throws = false
		local edges = {}
		local adapter = policy.new(f.controller, {
			get_item_template = function(item)
				if template_throws then error("template reader") end
				if item == f.item_data then return f.get_template() end
				return { ammo_data = { ammo_hand = "right" } }
			end,
			get_inventory = function()
				if inventory_available == "throw" then error("inventory reader") end
				return inventory_available and inventory or nil
			end,
			is_alive = function() return alive end,
			log = function(edge, _, reason, result)
				edges[#edges + 1] = { edge = edge, reason = reason, result = result }
			end,
		})
		local calls = {}
		local ui = {
			player = { player_unit = f.owner },
			_draw_ammo = true,
			_show_ammo_meter = true,
			_ammo_dirty = false,
			_update_ammo_count = function(_, item)
				calls[#calls + 1] = { kind = "update", item = item }
			end,
			_set_ammo_text_focus = function(_, focus)
				calls[#calls + 1] = { kind = "focus", focus = focus }
			end,
		}
		return {
			f = f, ranged_item = ranged_item, ranged_slot = ranged_slot,
			inventory = inventory, adapter = adapter, ui = ui, calls = calls,
			edges = edges,
			set_alive = function(value) alive = value end,
			set_inventory = function(value) inventory_available = value end,
			set_template_throw = function(value) template_throws = value end,
		}
	end

	H.test("CWV #1108 restores native ranged count and exact focus before release", function()
		local x = restoration_fixture()
		H.truthy(x.adapter:refresh(x.ui))
		H.truthy(x.adapter:is_active(x.ui))
		x.f.equipment.wielded_slot = "slot_ranged"
		x.f.equipment.wielded = x.ranged_item
		H.equal(x.adapter:refresh(x.ui), false)
		H.equal(x.calls[3].kind, "update")
		H.equal(x.calls[3].item, x.ranged_item)
		H.equal(x.calls[4].kind, "focus")
		H.equal(x.calls[4].focus, true)
		H.equal(x.adapter:is_active(x.ui), false)
		H.equal(#x.edges, 2)
		H.equal(x.edges[2].edge, "release")
		H.equal(x.edges[2].result, "native_ranged_focused")
	end)

	H.test("CWV #1108 restores unfocused ranged count on melee stance exit", function()
		local x = restoration_fixture()
		H.truthy(x.adapter:refresh(x.ui))
		x.f.controller.extension_for = function() return nil end
		x.f.equipment.wielded_slot = "slot_melee"
		x.f.equipment.wielded = x.f.item_data
		H.equal(x.adapter:refresh(x.ui), false)
		H.equal(x.calls[3].item, x.ranged_item)
		H.equal(x.calls[4].focus, false)
		H.equal(x.edges[2].result, "native_ranged_unfocused")
	end)

	H.test("CWV #1108 hides stale Musket presentation when native state is unreadable", function()
		for _, mode in ipairs({ "dead", "inventory_unavailable", "inventory_throw",
				"equipment_throw" }) do
			local x = restoration_fixture()
			H.truthy(x.adapter:refresh(x.ui), mode .. " engage")
			if mode == "dead" then
				x.set_alive(false)
			elseif mode == "inventory_unavailable" then
				x.set_inventory(false)
			elseif mode == "inventory_throw" then
				x.set_inventory("throw")
			elseif mode == "equipment_throw" then
				x.inventory.equipment = function() error("equipment reader") end
			end
			H.equal(x.adapter:refresh(x.ui), false, mode)
			H.equal(x.adapter:is_active(x.ui), false, mode .. " inactive")
			H.equal(x.ui._draw_ammo, false, mode .. " draw hidden")
			H.equal(x.ui._show_ammo_meter, false, mode .. " meter hidden")
			H.equal(x.ui._ammo_dirty, true, mode .. " dirtied")
			H.equal(x.edges[#x.edges].edge, "release", mode .. " release")
			H.truthy(x.edges[#x.edges].result:find("hidden_", 1, true), mode)
		end
	end)

	H.test("CWV #1108 restores native state after selector, replacement, and unit mismatch", function()
		for _, mode in ipairs({ "template_throw", "unregistered", "replaced", "unit_mismatch" }) do
			local x = restoration_fixture()
			H.truthy(x.adapter:refresh(x.ui), mode .. " engage")
			if mode == "template_throw" then
				x.set_template_throw(true)
			elseif mode == "unregistered" then
				x.f.controller.extension_for = function() return nil end
			elseif mode == "replaced" then
				x.f.slot_data.item_data = { name = "es_sword" }
				x.f.controller.extension_for = function() return nil end
			else
				x.f.slot_data.right_unit_1p = {}
			end
			x.f.equipment.wielded_slot = "slot_melee"
			x.f.equipment.wielded = x.f.slot_data.item_data
			H.equal(x.adapter:refresh(x.ui), false, mode)
			H.equal(x.adapter:is_active(x.ui), false, mode .. " inactive")
			H.equal(x.calls[3].kind, "update", mode)
			H.equal(x.calls[3].item, x.ranged_item, mode)
			H.equal(x.calls[4].kind, "focus", mode)
			H.equal(x.calls[4].focus, false, mode)
			H.equal(x.edges[#x.edges].edge, "release", mode)
			H.equal(x.edges[#x.edges].result, "native_ranged_unfocused", mode)
		end
	end)

	H.test("CWV #1108 never mutates a UI the adapter never engaged", function()
		local x = restoration_fixture()
		x.f.equipment.wielded_slot = "slot_ranged"
		x.f.equipment.wielded = x.ranged_item
		H.equal(x.adapter:refresh(x.ui), false)
		H.equal(#x.calls, 0)
		H.equal(#x.edges, 0)
		H.equal(x.ui._draw_ammo, true)
		H.equal(x.ui._show_ammo_meter, true)
	end)

	H.test("CWV #1108 installed GamePad callback restores after cached native early return", function()
		local x = restoration_fixture()
		local hooks = {}
		local mod = {
			hook_safe = function(_, class_name, method_name, callback)
				hooks[class_name .. "." .. method_name] = callback
			end,
		}
		local alive = true
		local adapter = policy.install(mod, x.f.controller, {
			get_item_template = function(item)
				return item == x.f.item_data and x.f.get_template()
					or { ammo_data = { ammo_hand = "right" } }
			end,
			get_inventory = function() return x.inventory end,
			is_alive = function() return alive end,
			log = function() end,
		})
		local callback = hooks["GamePadEquipmentUI._sync_player_equipment"]
		H.equal(type(callback), "function")
		callback(x.ui)
		H.truthy(adapter:is_active(x.ui))
		alive = false
		-- The vanilla GamePad method may have returned from its cached
		-- _check_equipment_changed gate; hook_safe still invokes this callback.
		callback(x.ui)
		H.equal(adapter:is_active(x.ui), false)
		H.equal(x.ui._draw_ammo, false)
	end)
end
