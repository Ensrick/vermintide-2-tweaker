-- Native HUD selection for an Old Musket equipped in the primary slot (#1108).
--
-- EquipmentUI and GamePadEquipmentUI refresh ammunition only from
-- `slot_ranged`. The gameplay pool already owns the authoritative extension;
-- this adapter selects that extension only when the primary slot is wielded
-- and its effective template's ammo hand resolves to the exact registered
-- unit. It owns no ammo state, update loop, or network traffic.

local M = {}

local HUD_CLASSES = {
	"EquipmentUI",
	"GamePadEquipmentUI",
}

function M.select(controller, owner, equipment, get_item_template)
	if type(controller) ~= "table"
			or type(controller.extension_for) ~= "function"
			or not owner
			or type(equipment) ~= "table"
			or equipment.wielded_slot ~= "slot_melee"
			or type(get_item_template) ~= "function" then
		return nil
	end

	local slot_data = equipment.slots and equipment.slots.slot_melee
	local item_data = slot_data and slot_data.item_data
	if not item_data then return nil end

	local extension = controller:extension_for(owner, "slot_melee")
	if not extension then return nil end

	local item_template = get_item_template(item_data)
	local ammo_data = item_template and item_template.ammo_data
	local ammo_hand = ammo_data and ammo_data.ammo_hand
	local ammo_unit
	if ammo_hand == "left" then
		ammo_unit = slot_data.left_unit_1p
	elseif ammo_hand == "right" then
		ammo_unit = slot_data.right_unit_1p
	else
		return nil
	end
	if not ammo_unit or ammo_unit ~= extension.unit then return nil end

	return item_data, slot_data, extension
end

function M.new(controller, runtime)
	runtime = runtime or {}
	local adapter = {
		controller = controller,
		get_item_template = runtime.get_item_template,
		get_inventory = runtime.get_inventory,
		log = runtime.log or function() end,
		hook_count = 0,
		hook_classes = {},
		-- Weak per-HUD-instance state makes the diagnostic edge-triggered even
		-- though the native sync is visited from the HUD update path.
		_active_by_ui = setmetatable({}, { __mode = "k" }),
	}

	function adapter:contract_error()
		if type(self.controller) ~= "table"
				or type(self.controller.extension_for) ~= "function" then
			return "Old Musket ammo HUD has no owner-slot controller"
		end
		if type(self.get_item_template) ~= "function"
				or type(self.get_inventory) ~= "function" then
			return "Old Musket ammo HUD runtime dependencies are missing"
		end
		if self.hook_count ~= #HUD_CLASSES
				or not self.hook_classes.EquipmentUI
				or not self.hook_classes.GamePadEquipmentUI then
			return "Old Musket ammo HUD does not own both native HUD classes"
		end
	end

	function adapter:_apply(ui)
		local player = ui and (ui._is_spectator and ui._spectated_player or ui.player)
		local player_unit = player and player.player_unit
		if not player_unit or type(self.get_inventory) ~= "function" then return false end

		local inventory_extension = self.get_inventory(player_unit)
		if not inventory_extension or type(inventory_extension.equipment) ~= "function" then
			return false
		end
		local equipment = inventory_extension:equipment()
		local item_data, slot_data = M.select(
			self.controller, player_unit, equipment, self.get_item_template)
		if not item_data then return false end
		if type(ui._update_ammo_count) ~= "function"
				or type(ui._set_ammo_text_focus) ~= "function" then
			return false
		end

		ui:_update_ammo_count(item_data, slot_data, player_unit)
		ui:_set_ammo_text_focus(true)
		return true, item_data
	end

	function adapter:refresh(ui)
		local applied, item_data = self:_apply(ui)
		applied = applied == true
		if ui then
			local was_active = self._active_by_ui[ui] == true
			if was_active ~= applied then
				self._active_by_ui[ui] = applied or nil
				self.log(applied and "engage" or "release", item_data)
			end
		end
		return applied
	end

	return adapter
end

function M.install(mod, controller, runtime)
	runtime = runtime or {
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
		log = function(edge, item_data)
			if edge == "engage" then
				local identity = item_data
					and (item_data.backend_id or item_data.key or item_data.name)
				pcall(printf,
					"[cwv:1108] HUD ammo counter reads wielded primary-slot musket (%s)",
					tostring(identity or "?"))
			else
				pcall(printf,
					"[cwv:1108] HUD ammo counter released to native ranged-slot path")
			end
		end,
	}
	local adapter = M.new(controller, runtime)

	for _, class_name in ipairs(HUD_CLASSES) do
		mod:hook_safe(class_name, "_sync_player_equipment", function(ui)
			adapter:refresh(ui)
		end)
		adapter.hook_count = adapter.hook_count + 1
		adapter.hook_classes[class_name] = true
	end

	return adapter
end

return M
