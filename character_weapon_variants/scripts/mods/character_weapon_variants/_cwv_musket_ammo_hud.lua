-- Native HUD selection for an Old Musket equipped in the primary slot (#1108).
--
-- EquipmentUI and GamePadEquipmentUI refresh ammunition only from
-- `slot_ranged`. The gameplay pool already owns the authoritative extension;
-- this adapter selects that extension only when the primary slot is wielded
-- and its effective template's ammo hand resolves to the exact registered
-- unit. It owns no ammo state and adds no update loop or network traffic.

local M = {}

function M.select(controller, owner, equipment, get_item_template)
	if not controller or not owner or not equipment
			or equipment.wielded_slot ~= "slot_melee" then
		return nil
	end

	local slot_data = equipment.slots and equipment.slots.slot_melee
	local item_data = slot_data and slot_data.item_data
	local extension = controller:extension_for(owner, "slot_melee")
	if not item_data or not extension or type(get_item_template) ~= "function" then
		return nil
	end

	local item_template = get_item_template(item_data)
	local ammo_data = item_template and item_template.ammo_data
	local ammo_hand = ammo_data and ammo_data.ammo_hand
	local ammo_unit = ammo_hand == "left" and slot_data.left_unit_1p
		or ammo_hand == "right" and slot_data.right_unit_1p
	if not ammo_unit or ammo_unit ~= extension.unit then
		return nil
	end

	return item_data, slot_data, extension
end

function M.new(controller, runtime)
	runtime = runtime or {}
	local adapter = {
		controller = controller,
		get_item_template = runtime.get_item_template,
		get_inventory = runtime.get_inventory,
		hook_count = 0,
	}

	function adapter:contract_error()
		if type(self.controller) ~= "table"
				or type(self.controller.extension_for) ~= "function" then
			return "Old Musket ammo HUD has no owner-slot controller"
		end
		if self.hook_count ~= 2 then
			return "Old Musket ammo HUD does not own both native HUD classes"
		end
	end

	function adapter:refresh(ui)
		local player = ui and (ui._is_spectator and ui._spectated_player or ui.player)
		local player_unit = player and player.player_unit
		if not player_unit or type(self.get_inventory) ~= "function" then return false end
		local inventory_extension = self.get_inventory(player_unit)
		local equipment = inventory_extension and inventory_extension:equipment()
		local item_data, slot_data = M.select(
			self.controller, player_unit, equipment, self.get_item_template)
		if not item_data then return false end
		if type(ui._update_ammo_count) ~= "function"
				or type(ui._set_ammo_text_focus) ~= "function" then
			return false
		end
		ui:_update_ammo_count(item_data, slot_data, player_unit)
		ui:_set_ammo_text_focus(true)
		return true
	end

	return adapter
end

function M.install(mod, controller)
	local adapter = M.new(controller, {
		get_item_template = function(item_data)
			return BackendUtils.get_item_template(item_data)
		end,
		get_inventory = function(player_unit)
			if ScriptUnit.has_extension
					and not ScriptUnit.has_extension(player_unit, "inventory_system") then
				return nil
			end
			return ScriptUnit.extension(player_unit, "inventory_system")
		end,
	})

	for _, class_name in ipairs({ "EquipmentUI", "GamePadEquipmentUI" }) do
		mod:hook_safe(class_name, "_sync_player_equipment", function(self)
			adapter:refresh(self)
		end)
		adapter.hook_count = adapter.hook_count + 1
	end

	return adapter
end

return M
