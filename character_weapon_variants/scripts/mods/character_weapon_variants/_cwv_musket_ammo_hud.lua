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
		is_alive = runtime.is_alive,
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
				or type(self.get_inventory) ~= "function"
				or type(self.is_alive) ~= "function" then
			return "Old Musket ammo HUD runtime dependencies are missing"
		end
		if self.hook_count ~= #HUD_CLASSES
				or not self.hook_classes.EquipmentUI
				or not self.hook_classes.GamePadEquipmentUI then
			return "Old Musket ammo HUD does not own both native HUD classes"
		end
	end

	function adapter:_context(ui)
		local player = ui and (ui._is_spectator and ui._spectated_player or ui.player)
		local player_unit = player and player.player_unit
		if not player_unit then return nil, "player_unavailable" end
		local ok_alive, alive = pcall(self.is_alive, player_unit)
		if not ok_alive or alive ~= true then return nil, "player_dead" end

		local ok_inventory, inventory_extension = pcall(self.get_inventory, player_unit)
		if not ok_inventory then return nil, "inventory_error" end
		if not inventory_extension or type(inventory_extension.equipment) ~= "function" then
			return nil, "inventory_unavailable"
		end
		local ok_equipment, equipment = pcall(inventory_extension.equipment,
			inventory_extension)
		if not ok_equipment then return nil, "equipment_error" end
		if type(equipment) ~= "table" then return nil, "equipment_unavailable" end
		return {
			player_unit = player_unit,
			inventory = inventory_extension,
			equipment = equipment,
		}
	end

	function adapter:_apply(ui)
		local context, context_reason = self:_context(ui)
		if not context then return false, nil, context_reason, false end
		local ok_select, item_data, slot_data = pcall(M.select,
			self.controller, context.player_unit, context.equipment,
			self.get_item_template)
		if not ok_select then return false, nil, "selector_error", false end
		if not item_data then return false, nil, "not_primary_musket", false end
		if type(ui._update_ammo_count) ~= "function"
				or type(ui._set_ammo_text_focus) ~= "function" then
			return false, nil, "ui_methods_unavailable", false
		end

		-- From this point the adapter may have changed native presentation even
		-- when the engine method raises part-way through. Report `touched=true`
		-- so refresh() restores or hides before releasing ownership.
		local touched = true
		local ok_update = pcall(ui._update_ammo_count, ui, item_data,
			slot_data, context.player_unit)
		if not ok_update then return false, item_data, "musket_update_error", touched end
		local ok_focus = pcall(ui._set_ammo_text_focus, ui, true)
		if not ok_focus then return false, item_data, "musket_focus_error", touched end
		return true, item_data, "primary_musket", touched
	end

	function adapter:_hide_owned(ui)
		if type(ui) ~= "table" then return false end
		local changed = false
		if type(ui._set_ammo_text_focus) == "function" then
			local ok = pcall(ui._set_ammo_text_focus, ui, false)
			changed = ok or changed
		end
		-- Desktop focus(false) hides the non-persistent counter. Gamepad focus
		-- only marks it dirty, so also hide the exact ammo widgets when present.
		if type(ui._set_widget_visibility) == "function"
				and type(ui._ammo_widgets_by_name) == "table" then
			for _, name in ipairs({ "ammo_text_clip", "ammo_text_remaining",
					"ammo_text_center", "reload_tip_text" }) do
				local widget = ui._ammo_widgets_by_name[name]
				if widget then
					local ok = pcall(ui._set_widget_visibility, ui, widget, false)
					changed = ok or changed
				end
			end
		end
		if type(ui._set_widget_visibility) == "function"
				and type(ui._widgets_by_name) == "table"
				and ui._widgets_by_name.ammo_background then
			local ok = pcall(ui._set_widget_visibility, ui,
				ui._widgets_by_name.ammo_background, false)
			changed = ok or changed
		end
		if ui._draw_ammo ~= nil then ui._draw_ammo = false; changed = true end
		if ui._show_ammo_meter ~= nil then ui._show_ammo_meter = false; changed = true end
		if ui._ammo_dirty ~= nil then ui._ammo_dirty = true; changed = true end
		if changed and type(ui.set_dirty) == "function" then pcall(ui.set_dirty, ui) end
		return changed
	end

	function adapter:_restore_native(ui)
		local context, context_reason = self:_context(ui)
		if context and type(ui._update_ammo_count) == "function"
				and type(ui._set_ammo_text_focus) == "function" then
			local equipment = context.equipment
			local ranged = equipment.slots and equipment.slots.slot_ranged
			local ranged_item = ranged and ranged.item_data
			if ranged_item then
				local ok_update = pcall(ui._update_ammo_count, ui, ranged_item,
					ranged, context.player_unit)
				if ok_update then
					local focused = equipment.wielded_slot == "slot_ranged"
						or (equipment.wielded ~= nil and equipment.wielded == ranged_item)
					local ok_focus = pcall(ui._set_ammo_text_focus, ui, focused)
					if ok_focus then
						return true, focused and "native_ranged_focused"
							or "native_ranged_unfocused"
					end
					context_reason = "native_focus_error"
				else
					context_reason = "native_update_error"
				end
			else
				context_reason = "native_ranged_unavailable"
			end
		end
		if self:_hide_owned(ui) then
			return true, "hidden_" .. tostring(context_reason or "unavailable")
		end
		return false, "restore_failed_" .. tostring(context_reason or "unavailable")
	end

	function adapter:is_active(ui)
		return type(ui) == "table" and self._active_by_ui[ui] == true
	end

	function adapter:refresh(ui)
		local applied, item_data, reason, touched = self:_apply(ui)
		applied = applied == true
		if ui then
			local was_active = self._active_by_ui[ui] == true
			if applied then
				self._active_by_ui[ui] = true
				if not was_active then self.log("engage", item_data, reason) end
			elseif was_active or touched then
				local restored, restore_reason = self:_restore_native(ui)
				if restored then
					self._active_by_ui[ui] = nil
					self.log("release", item_data, reason, restore_reason)
				else
					-- Keep ownership so the next native callback retries restoration;
					-- never claim a release while stale Musket presentation may remain.
					self._active_by_ui[ui] = true
				end
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
		is_alive = function(player_unit)
			return Unit.alive(player_unit)
		end,
		log = function(edge, item_data, reason, restore_reason)
			if edge == "engage" then
				local identity = item_data
					and (item_data.backend_id or item_data.key or item_data.name)
				pcall(printf,
					"[cwv:1108] HUD ammo counter reads wielded primary-slot musket (%s)",
					tostring(identity or "?"))
			else
				pcall(printf,
					"[cwv:1108] HUD ammo counter released cause=%s result=%s",
					tostring(reason), tostring(restore_reason))
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
