-- Per-instance Combat Style policy and runtime owner (issue #620).
--
-- A style is an immutable package of template, balance, presentation, and
-- receiver-animation metadata. The persisted value is only the stable style id
-- keyed by exact backend item id. Runtime transitions rebuild the equipped slot
-- once; peers receive one bounded family/style edge and never a template table.
local M = {}

M.SETTING_KEY = "cwv_combat_style_state"
M.CHANNEL = "cwv_combat_style_v1"
M.SCHEMA = 1
M.MAX_TOKEN = 96
M.KERILLIAN_TEMPLATE = "cwv_combat_style_kerillian_greatsword"
M.KERILLIAN_SPEED_MULT = 0.85
M.KERILLIAN_STAGGER_MULT = 1.15
M.KERILLIAN_CLEAVE_MULT = 1.15

M.FAMILIES = {
	greatsword = {
		styles = {
			greatsword = { label = "Greatsword Combat Style", template = "two_handed_swords_template_1" },
			longsword = { label = "Longsword Combat Style", template = "imperial_longsword_template", transform = "imperial_longsword" },
			bretonnian = { label = "Bretonnian Combat Style", template = "bastard_sword_template" },
			kerillian = {
				label = "Kerillian Greatsword Combat Style",
				template = M.KERILLIAN_TEMPLATE,
				modifiers = { attack_speed = M.KERILLIAN_SPEED_MULT, stagger = M.KERILLIAN_STAGGER_MULT, cleave = M.KERILLIAN_CLEAVE_MULT },
			},
		},
		members = {
			es_2h_sword = { default = "greatsword", order = { "greatsword", "longsword", "bretonnian", "kerillian" } },
			es_bastard_sword = { default = "bretonnian", order = { "bretonnian", "kerillian", "greatsword", "longsword" } },
			cwv_es_longsword = { default = "longsword", order = { "longsword", "bretonnian", "kerillian", "greatsword" } },
			cwv_es_longsword_blackguard = { default = "longsword", order = { "longsword", "bretonnian", "kerillian", "greatsword" } },
		},
	},
	greathammer = {
		styles = {
			kruber = { label = "Kruber Greathammer Combat Style", template = "two_handed_hammers_template_1" },
			warrior_priest = { label = "Warrior Priest Greathammer Combat Style", template = "two_handed_hammer_priest_template" },
		},
		members = {
			es_2h_hammer = { default = "kruber", order = { "kruber", "warrior_priest" } },
			wh_2h_hammer = { default = "warrior_priest", order = { "warrior_priest", "kruber" } },
			cwv_es_priest_greathammer = { default = "warrior_priest", order = { "warrior_priest", "kruber" } },
		},
	},
	spear = {
		styles = {
			hunter = { label = "Hunter Combat Style", template = "two_handed_heavy_spears_template" },
			infantry = { label = "Infantry Combat Style", template = "cwv_infantry_spear_template" },
		},
		members = {
			es_2h_heavy_spear = { default = "hunter", order = { "hunter", "infantry" } },
			-- Hidden legacy row: old exact CIM instances retain their UUID and
			-- Infantry default until the bounded migration rewrites them in-place.
			cwv_es_infantry_spear = { default = "infantry", order = { "infantry", "hunter" } },
		},
	},
}

-- Canonical, lossless retirement map. These rows remain registered only as
-- restore bridges; CIM must never offer them as new craft choices. Planning is
-- deliberately pure so every target/illusion can be validated before the
-- caller mutates one persisted record.
M.LEGACY_MIGRATIONS = {
	cwv_es_infantry_spear = {
		target_item = "es_2h_heavy_spear", style_id = "infantry",
		default_skin = "cwv_tuskgor_spear_01",
		map_skin = function(skin)
			if type(skin) ~= "string" then return skin end
			if skin == "cwv_es_infantry_spear_skin" then return "cwv_tuskgor_spear_01" end
			return skin:gsub("^cwv_es_infantry_spear_", "cwv_tuskgor_spear_")
		end,
	},
	cwv_es_longsword = {
		target_item = "es_2h_sword", style_id = "longsword",
		default_skin = "cwv_es_longsword_skin",
	},
	cwv_es_longsword_blackguard = {
		target_item = "es_2h_sword", style_id = "longsword",
		default_skin = "cwv_es_longsword_blackguard_skin",
	},
}

local function valid_token(value)
	return type(value) == "string" and #value > 0 and #value <= M.MAX_TOKEN
		and value:match("^[%w_:%-%.]+$") ~= nil
end

function M.plan_legacy_migrations(saved, target_exists, skin_exists)
	if type(saved) ~= "table" then return {}, nil end
	local patches = {}
	for identity, persisted in pairs(saved) do
		local spec = type(persisted) == "table" and M.LEGACY_MIGRATIONS[persisted.item_key]
		if spec then
			if not valid_token(identity) then return nil, "invalid legacy identity" end
			if type(target_exists) == "function" and not target_exists(spec.target_item) then
				return nil, "missing migration target " .. spec.target_item
			end
			local skin = persisted.skin or spec.default_skin
			if spec.map_skin then skin = spec.map_skin(skin) end
			if skin and type(skin_exists) == "function" and not skin_exists(skin, spec.target_item) then
				return nil, "missing migration skin " .. tostring(skin)
			end
			patches[#patches + 1] = {
				identity = identity, source_item = persisted.item_key,
				target_item = spec.target_item, style_id = spec.style_id,
				old_skin = persisted.skin, skin = skin,
			}
		end
	end
	table.sort(patches, function(a, b) return a.identity < b.identity end)
	return patches, nil
end

function M.member(item_key)
	if type(item_key) ~= "string" then return nil end
	for family_id, family in pairs(M.FAMILIES) do
		local member = family.members[item_key]
		if member then return family_id, family, member end
	end
	return nil
end

function M.style(item_key, stored_style)
	local family_id, family, member = M.member(item_key)
	if not family_id then return nil end
	local style_id = family.styles[stored_style] and stored_style or member.default
	return style_id, family.styles[style_id], family_id, member
end

function M.next_style(item_key, current)
	local style_id, _, family_id, member = M.style(item_key, current)
	if not style_id then return nil end
	for index, candidate in ipairs(member.order) do
		if candidate == style_id then
			local next_id = member.order[index % #member.order + 1]
			return next_id, M.FAMILIES[family_id].styles[next_id], family_id
		end
	end
	return member.order[1], M.FAMILIES[family_id].styles[member.order[1]], family_id
end

function M.normalize_store(value)
	local result = { schema = M.SCHEMA, items = {} }
	if type(value) ~= "table" then return result end
	local source = value.schema == M.SCHEMA and value.items or value
	if type(source) ~= "table" then return result end
	for identity, style_id in pairs(source) do
		if valid_token(identity) and type(style_id) == "string" then
			result.items[identity] = style_id
		end
	end
	return result
end

function M.set(store, identity, item_key, style_id)
	if type(store) ~= "table" or type(store.items) ~= "table" or not valid_token(identity) then
		return false, "invalid identity"
	end
	local resolved, _, _, member = M.style(item_key, style_id)
	if resolved ~= style_id then return false, "unsupported style" end
	if style_id == member.default then style_id = nil end
	if store.items[identity] == style_id then return false end
	store.items[identity] = style_id
	return true
end

function M.valid_wire(schema, op, slot_name, family_id, style_id)
	if schema ~= M.SCHEMA or (op ~= "state" and op ~= "query") then return false end
	if op == "query" then return true end
	local family = M.FAMILIES[family_id]
	return (slot_name == "slot_melee" or slot_name == "slot_ranged")
		and family ~= nil and family.styles[style_id] ~= nil
end

function M.build_kerillian_template(weapons, clone, clone_damage_profile)
	local donor = weapons and weapons.two_handed_swords_wood_elf_template
	if type(donor) ~= "table" then return nil, "Kerillian Greatsword template missing" end
	if type(clone) ~= "function" or type(clone_damage_profile) ~= "function" then
		return nil, "clone dependencies missing"
	end
	local template = clone(donor)
	for _, action_group in pairs(template.actions or {}) do
		if type(action_group) == "table" then
			for _, action in pairs(action_group) do
				if type(action) == "table" then
					if type(action.anim_time_scale) == "number" then
						action.anim_time_scale = action.anim_time_scale * M.KERILLIAN_SPEED_MULT
					end
					if type(action.damage_profile) == "string" then
						action.damage_profile = clone_damage_profile(action.damage_profile,
							"cwv_style_kerillian_gs_", { damage = 1, stagger = M.KERILLIAN_STAGGER_MULT, cleave = M.KERILLIAN_CLEAVE_MULT })
					end
				end
			end
		end
	end
	-- The donor's first-person state machine remains exact. Only the 3P wield
	-- event is receiver-localized for Kruber; action redirects remain available
	-- to CWV/WT's existing network-bound animation funnel.
	template.wield_anim_career_3p = template.wield_anim_career_3p or {}
	for _, career in ipairs({ "es_mercenary", "es_huntsman", "es_knight", "es_questingknight" }) do
		template.wield_anim_career_3p[career] = "to_bastard_sword"
	end
	return template
end

function M.install(mod, deps)
	deps = deps or {}
	local store = M.normalize_store(mod:get(M.SETTING_KEY))
	local remote = {}
	local imperial_transform = deps.imperial_transform
	local runtime = { store = store, remote = remote }

	local function item_identity(item, backend_id)
		local data = item and (item.data or item)
		local value = backend_id or (item and (item.backend_id or item.ItemId))
			or (data and (data.backend_id or (data.mod_data and data.mod_data.backend_id)))
		return valid_token(value) and value or nil
	end

	local function item_key(item, backend_id)
		local data = item and (item.data or item)
		local cwv_key = type(deps.cwv_key_for_item) == "function"
			and deps.cwv_key_for_item(item_identity(item, backend_id), data) or nil
		if M.member(cwv_key) then return cwv_key end
		-- Do not collect these into an ipairs table: optional leading fields are
		-- commonly nil and would stop traversal before the native item name.
		for _, field in ipairs({ "cwv_key", "key", "name", "item_type" }) do
			local value = data and data[field]
			if M.member(value) then return value end
		end
		return nil
	end

	function runtime:describe(item, backend_id)
		local key = item_key(item, backend_id)
		local identity = item_identity(item, backend_id)
		if not key or not identity then return nil end
		local saved = self.store.items[identity]
		local style_id, style, family_id, member = M.style(key, saved)
		return { item_key = key, identity = identity, style_id = style_id, style = style,
			family_id = family_id, member = member, item_data = item.data or item }
	end

	function runtime:resolve_template(item, backend_id)
		local row = self:describe(item, backend_id)
		local weapons = rawget(_G, "Weapons")
		if row then return weapons and weapons[row.style.template] or nil end
		-- Remote husk items intentionally have no backend id. The consolidated
		-- husk-wield wrapper supplies a strictly synchronous owner+slot context so
		-- the same BackendUtils seam can select that peer's received style without
		-- ever guessing from a bare base item outside the wield transaction.
		local context = self.husk_context
		local key = context and item_key(item, backend_id)
		local family_id = key and M.member(key)
		if not (context and family_id == context.family_id) then return nil end
		local family = M.FAMILIES[family_id]
		local style = family and family.styles[context.style_id]
		return style and weapons and weapons[style.template] or nil
	end

	function runtime:begin_husk_wield(inventory, slot_name)
		local owner = inventory and (inventory._unit or inventory.owner_unit)
		local peer_id = type(deps.peer_for_owner) == "function" and deps.peer_for_owner(owner) or nil
		local row = peer_id and remote[peer_id] and remote[peer_id][slot_name]
		self.husk_context = row and { family_id = row.family_id, style_id = row.style_id } or nil
		return self.husk_context ~= nil
	end

	function runtime:end_husk_wield()
		self.husk_context = nil
	end

	-- Returns nil for unsupported, false to suppress the legacy CWV transform,
	-- or the exact style-owned transform definition to apply.
	function runtime:transform_decision(item, backend_id)
		local row = self:describe(item, backend_id)
		if not row then return nil end
		if row.style.transform == "imperial_longsword" then return imperial_transform end
		return false
	end

	function runtime:effective_remap_key(item, backend_id)
		local row = self:describe(item, backend_id)
		if row and row.family_id == "spear" and row.style_id == "infantry" then
			return "cwv_es_infantry_spear"
		end
		return row and row.item_key or nil
	end

	function runtime:remote_transform(owner_unit, slot_name)
		if type(deps.peer_for_owner) ~= "function" then return nil end
		local peer_id = deps.peer_for_owner(owner_unit)
		local row = peer_id and remote[peer_id] and remote[peer_id][slot_name]
		if not row or row.family_id ~= "greatsword" then return nil end
		return row.style_id == "longsword" and imperial_transform or false
	end

	local function persist()
		mod:set(M.SETTING_KEY, store, false)
	end

	function runtime:migrate_identity(identity, item_key, style_id)
		local changed, err = M.set(store, identity, item_key, style_id)
		if changed then persist() end
		return changed, err
	end

	function runtime:migrate_identities(rows)
		local count = 0
		for _, row in ipairs(rows or {}) do
			local changed = M.set(store, row.identity, row.item_key, row.style_id)
			if changed then count = count + 1 end
		end
		if count > 0 then persist() end
		return count
	end

	local function send(recipient, op, slot_name, family_id, style_id)
		if type(mod.network_send) ~= "function" then return false end
		return pcall(mod.network_send, mod, M.CHANNEL, recipient or "others", M.SCHEMA,
			op, slot_name or "", family_id or "", style_id or "")
	end

	local function local_equipment()
		local pm = rawget(_G, "Managers") and Managers.player
		local player = pm and pm.local_player and pm:local_player(1)
		local unit = player and player.player_unit
		if not unit or not Unit.alive(unit) then return nil end
		local ok, inventory = pcall(ScriptUnit.extension, unit, "inventory_system")
		return ok and inventory or nil, unit
	end

	local function action_active(equipment)
		for _, unit in ipairs({ equipment and equipment.right_hand_wielded_unit,
				equipment and equipment.left_hand_wielded_unit }) do
			if unit and Unit.alive(unit) and ScriptUnit.has_extension(unit, "weapon_system") then
				local ok, extension = pcall(ScriptUnit.extension, unit, "weapon_system")
				if ok and extension and extension.has_current_action and extension:has_current_action() then
					return true
				end
			end
		end
		return false
	end

	function runtime:publish(inventory, slot_name, item, recipient, reason)
		local row = self:describe(item)
		if not row then return false end
		local ok = send(recipient, "state", slot_name, row.family_id, row.style_id)
		if ok then pcall(printf, "[cwv:620] style tx slot=%s family=%s style=%s reason=%s",
			tostring(slot_name), row.family_id, row.style_id, tostring(reason)) end
		return ok
	end

	function runtime:set_item_style(item, backend_id, desired, reason, rebuild)
		local row = self:describe(item, backend_id)
		if not row then return false, "unsupported item" end
		local resolved = M.style(row.item_key, desired)
		if resolved ~= desired then return false, "unsupported style" end
		local inventory, equipment, slot_name, live_item
		if rebuild then
			inventory = local_equipment()
			equipment = inventory and inventory:equipment()
			slot_name = equipment and equipment.wielded_slot
			local slot = slot_name and equipment.slots and equipment.slots[slot_name]
			live_item = slot and slot.item_data
			local live = live_item and self:describe(live_item)
			if live and live.identity == row.identity and action_active(equipment) then
				pcall(printf, "[cwv:620] style deferred: active action item=%s", row.identity)
				return false, "active action"
			end
		end
		local changed, err = M.set(store, row.identity, row.item_key, desired)
		if not changed then return false, err or "unchanged" end
		persist()
		row.item_data.mod_data = row.item_data.mod_data or {}
		row.item_data.mod_data.cwv_combat_style = desired
		pcall(printf, "[cwv:620] style commit item=%s family=%s %s->%s reason=%s",
			row.identity, row.family_id, row.style_id, desired, tostring(reason))
		if rebuild then
			local live = live_item and self:describe(live_item)
			if live and live.identity == row.identity then
				local ok_destroy = pcall(inventory.destroy_slot, inventory, slot_name, true)
				local ok_add = ok_destroy and pcall(inventory.add_equipment, inventory, slot_name, live_item)
				local ok_wield = ok_add and pcall(inventory.wield, inventory, slot_name)
				if not ok_wield then
					-- Restore the previous policy before a best-effort equipment repair;
					-- persistence must never claim a transition the live slot rejected.
					M.set(store, row.identity, row.item_key, row.style_id)
					persist()
					row.item_data.mod_data.cwv_combat_style = row.style_id
					pcall(inventory.destroy_slot, inventory, slot_name, true)
					pcall(inventory.add_equipment, inventory, slot_name, live_item)
					pcall(inventory.wield, inventory, slot_name)
					pcall(printf, "[cwv:620] style rollback: rebuild failed item=%s", row.identity)
					return false, "rebuild failed"
				end
				self:publish(inventory, slot_name, item, nil, reason or "transition")
			end
		end
		return true
	end

	function runtime:cycle_item(item, backend_id, reason, rebuild)
		local row = self:describe(item, backend_id)
		if not row then return false, "unsupported item" end
		local next_id = M.next_style(row.item_key, row.style_id)
		return self:set_item_style(item, backend_id, next_id, reason, rebuild)
	end

	function runtime:cycle_wielded()
		local inventory = local_equipment()
		local equipment = inventory and inventory:equipment()
		local slot_name = equipment and equipment.wielded_slot
		local slot = slot_name and equipment.slots and equipment.slots[slot_name]
		if not slot then return false end
		return self:cycle_item(slot.item_data, nil, "hotkey", true)
	end

	function runtime:on_local_wield(inventory, slot_name, item)
		local row = self:describe(item)
		if not row then return false end
		item.mod_data = item.mod_data or {}
		item.mod_data.cwv_combat_style = row.style_id
		return self:publish(inventory, slot_name, item, nil, "wield")
	end

	function runtime:on_husk_wield(inventory, slot_name)
		local owner = inventory and (inventory._unit or inventory.owner_unit)
		local decision = self:remote_transform(owner, slot_name)
		if decision == nil then return false end
		-- The ordinary husk rebuild/spawn has already consumed remote state. This
		-- callback is an observation marker; the receiver below rewields on edges.
		return true
	end

	function runtime:publish_loadout(recipient, reason)
		local inventory = local_equipment()
		local equipment = inventory and inventory:equipment()
		for _, slot_name in ipairs({ "slot_melee", "slot_ranged" }) do
			local slot = equipment and equipment.slots and equipment.slots[slot_name]
			if slot then self:publish(inventory, slot_name, slot.item_data, recipient, reason or "query") end
		end
	end

	function runtime:request_states(reason)
		send("others", "query")
		self:publish_loadout(nil, reason or "query")
	end

	if type(mod.network_register) == "function" then
		mod:network_register(M.CHANNEL, function(sender_peer_id, schema, op, slot_name, family_id, style_id)
			if not M.valid_wire(schema, op, slot_name, family_id, style_id) then return end
			if op == "query" then runtime:publish_loadout(sender_peer_id, "query_reply"); return end
			remote[sender_peer_id] = remote[sender_peer_id] or {}
			local previous = remote[sender_peer_id][slot_name]
			if previous and previous.family_id == family_id and previous.style_id == style_id then return end
			remote[sender_peer_id][slot_name] = { family_id = family_id, style_id = style_id }
			pcall(printf, "[cwv:620] style rx peer=%s slot=%s family=%s style=%s",
				tostring(sender_peer_id), slot_name, family_id, style_id)
			if type(deps.rebuild_remote) == "function" then deps.rebuild_remote(sender_peer_id, slot_name) end
		end)
	end

	return runtime
end

-- Adds one contextual control to the mouse/keyboard hero loadout bar. The
-- vanilla module captures these definition tables by reference, so mutating
-- the cached tables before a HeroWindowLoadout instance is created is enough;
-- no copied view or custom renderer is introduced.
function M.install_loadout_ui(mod, runtime)
	if M._ui_installed or type(runtime) ~= "table" then return false end
	local ok, definitions = pcall(local_require,
		"scripts/ui/views/hero_view/windows/definitions/hero_window_loadout_definitions")
	if not ok or type(definitions) ~= "table" then return false end
	local scenegraph = definitions.scenegraph_definition
	local widgets = definitions.widgets
	if type(scenegraph) ~= "table" or type(widgets) ~= "table" then return false end

	scenegraph.cwv_combat_style_button = scenegraph.cwv_combat_style_button or {
		parent = "loadout_background",
		horizontal_alignment = "center",
		vertical_alignment = "bottom",
		size = { 390, 46 },
		position = { 0, 122, 30 },
	}
	widgets.cwv_combat_style_button = widgets.cwv_combat_style_button or {
		scenegraph_id = "cwv_combat_style_button",
		element = { passes = {
			{ pass_type = "hotspot", content_id = "button_hotspot", content_check_function = function(content) return content.visible end },
			{ pass_type = "rect", style_id = "background", content_check_function = function(content) return content.visible end },
			{ pass_type = "rect", style_id = "border", content_check_function = function(content) return content.visible end },
			{ pass_type = "text", text_id = "button_text", style_id = "button_text", content_check_function = function(content) return content.visible end },
			{ pass_type = "text", text_id = "button_text", style_id = "button_text_shadow", content_check_function = function(content) return content.visible end },
		} },
		content = { visible = false, button_hotspot = {}, button_text = "" },
		style = {
			background = { color = { 220, 32, 38, 40 }, offset = { 2, 2, 2 }, size = { 386, 42 } },
			border = { color = { 255, 160, 146, 101 }, offset = { 0, 0, 1 }, size = { 390, 46 } },
			button_text = { font_type = "hell_shark", font_size = 22,
				horizontal_alignment = "center", vertical_alignment = "center",
				text_color = { 255, 255, 255, 255 }, offset = { 0, 2, 4 }, size = { 390, 46 } },
			button_text_shadow = { font_type = "hell_shark", font_size = 22,
				horizontal_alignment = "center", vertical_alignment = "center",
				text_color = { 255, 0, 0, 0 }, offset = { 2, 0, 3 }, size = { 390, 46 } },
		},
	}

	local function selected(window)
		local parent = window and window.parent
		local index = parent and parent.get_selected_loadout_slot_index
			and parent:get_selected_loadout_slot_index()
		local item = index and window._equipment_items and window._equipment_items[index]
		return item, index
	end

	local function refresh(window)
		local widget = window and window._widgets_by_name
			and window._widgets_by_name.cwv_combat_style_button
		if not widget then return end
		local item = selected(window)
		local row = item and runtime:describe(item, item.backend_id)
		widget.content.visible = row ~= nil
		if row then
			local _, next_style = M.next_style(row.item_key, row.style_id)
			widget.content.button_text = "Switch to: " .. (next_style and next_style.label or row.style.label)
			widget.content.button_hotspot.disable_button = false
		end
	end

	mod:hook("HeroWindowLoadout", "_populate_loadout", function(func, self, ...)
		local result = func(self, ...)
		refresh(self)
		return result
	end)
	mod:hook("HeroWindowLoadout", "_handle_input", function(func, self, ...)
		local r1, r2, r3, r4 = func(self, ...)
		refresh(self)
		local widget = self._widgets_by_name and self._widgets_by_name.cwv_combat_style_button
		local hotspot = widget and widget.content and widget.content.button_hotspot
		if widget and widget.content.visible and hotspot and hotspot.on_release then
			hotspot.on_release = false
			local item = selected(self)
			local changed = item and runtime:cycle_item(item, item.backend_id,
				"inventory_button", true)
			if changed then
				if self.parent then
					self.parent.loadout_sync_id = (self.parent.loadout_sync_id or 0) + 1
				end
				pcall(function() self:_play_sound("play_gui_equipment_selection_click") end)
			end
			refresh(self)
		end
		return r1, r2, r3, r4
	end)

	M._ui_installed = true
	return true
end

return M
