-- Live owner for Crowbill Weapon-Special mode.
-- Gameplay template choice stays local to the owning inventory. Peers receive
-- only a bounded pick/hammer presentation edge and render from local assets.
local M = {}

M.SLOT = "slot_melee"
M.PICK_TEMPLATE_KEY = "cwv_crowbill_pick_template"

local function _valid_family_key(family, key)
	return type(key) == "string" and family and family.is_family_key(key)
end

local function _bid(item_data, backend_id)
	local value = backend_id or (item_data and (item_data.backend_id
		or (item_data.mod_data and item_data.mod_data.backend_id)))
	return type(value) == "string" and value or nil
end

local function _is_source_crowbill(family, item_data)
	if type(item_data) ~= "table" then return false end
	return item_data.template == family.SOURCE_TEMPLATE
		or item_data.name == family.SOURCE_ITEM
		or item_data.key == family.SOURCE_ITEM
		or item_data.item_type == family.SOURCE_ITEM
end

function M.classify(family, item_data, backend_id, cwv_key_for_item)
	if type(item_data) ~= "table" then return nil end
	local bid = _bid(item_data, backend_id)
	local cwv_key = type(cwv_key_for_item) == "function"
		and cwv_key_for_item(bid, item_data) or item_data.cwv_key
	if _valid_family_key(family, cwv_key) and cwv_key ~= family.SOURCE_ITEM then
		return cwv_key, bid or cwv_key
	end
	-- Crowbill mode is a family capability, not a saved preference. The native
	-- Sienna donor and every authored CWV variant always enter the same mode
	-- owner while CWV itself is enabled.
	if _is_source_crowbill(family, item_data) then
		return family.SOURCE_ITEM, bid or family.SOURCE_ITEM
	end
	return nil
end

function M.valid_wire(policy, family, schema, op, slot_name, mode, identity, family_key)
	if schema ~= policy.SCHEMA or (op ~= "state" and op ~= "query") then return false end
	if op == "query" then return true end
	return slot_name == M.SLOT
		and (mode == policy.MODE_PICK or mode == policy.MODE_HAMMER)
		and type(identity) == "string" and #identity > 0
		and #identity <= policy.MAX_IDENTITY_LENGTH
		and identity:match("^[%w_:%-%.]+$") ~= nil
		and _valid_family_key(family, family_key)
end

function M.install(mod, om)
	if M._installed then return M end
	local policy, family = om.crowbill_hammer_mode, om.crowbill_family
	local weapons = rawget(_G, "Weapons")
	local profiles = rawget(_G, "DamageProfileTemplates")
	local powers = rawget(_G, "PowerLevelTemplates")
	if not (policy and family and weapons and profiles and powers
			and weapons[policy.SOURCE_TEMPLATE_KEY]) then
		return nil, "Crowbill runtime prerequisites missing"
	end

	local function clone(value) return table.clone(value, true) end
	local function register_profile(name)
		local lookup = rawget(_G, "NetworkLookup") and NetworkLookup.damage_profiles
		if type(name) ~= "string" or not lookup or rawget(lookup, name) then return end
		local index = #lookup + 1
		rawset(lookup, index, name)
		rawset(lookup, name, index)
	end
	local source_template = weapons[policy.SOURCE_TEMPLATE_KEY]
	local pick_template = clone(source_template)
	local hammer_template, generated = policy.build_hammer_template(
		source_template, profiles, powers, clone,
		om._record_cwv_dp_source, register_profile)
	if not hammer_template then return nil, generated end
	weapons[M.PICK_TEMPLATE_KEY] = pick_template
	weapons[policy.HAMMER_TEMPLATE_KEY] = hammer_template

	local state = policy.new()
	om.crowbill_mode_state = state
	local enabled = true
	local restoring_source = false

	local function classify(item_data, backend_id)
		return M.classify(family, item_data, backend_id, om._cwv_key_for_item)
	end

	local function item_mode(item_data, identity)
		local mode = item_data and item_data.mod_data and item_data.mod_data.cwv_crowbill_mode
		if mode == policy.MODE_HAMMER or mode == policy.MODE_PICK then return mode end
		return state:mode(identity)
	end

	local function set_item_mode(item_data, identity, mode)
		item_data.mod_data = item_data.mod_data or {}
		item_data.mod_data.cwv_crowbill_mode = mode
		return state:set_mode(identity, mode)
	end

	local function send(recipient, op, slot_name, mode, identity, family_key)
		if type(mod.network_send) ~= "function" then return false end
		return pcall(function()
			mod:network_send(policy.CHANNEL, recipient or "others", policy.SCHEMA,
				op, slot_name or "", mode or "", identity or "", family_key or "")
		end)
	end

	local function owner_equipment(owner_unit)
		if not owner_unit or not Unit.alive(owner_unit) then return nil end
		local ok, inv = pcall(ScriptUnit.extension, owner_unit, "inventory_system")
		if not ok or not inv or not inv.equipment then return nil end
		return inv, inv:equipment()
	end

	local function apply_presentation(owner_unit, slot_name, identity, mode, remote)
		if not om._apply_crowbill_presentation then return false end
		local _, equipment = owner_equipment(owner_unit)
		if not equipment or equipment.wielded_slot ~= slot_name then return false end
		local marker = { crowbill_mode_family = family.HAMMER_MODE_FAMILY }
		if not remote then
			om._apply_crowbill_presentation(equipment.right_hand_wielded_unit, marker,
				identity, "owner_1p", nil, mode)
		end
		return om._apply_crowbill_presentation(equipment.right_hand_wielded_unit_3p,
			marker, identity, remote and "remote_husk" or "owner_3p", nil, mode)
	end

	local function peer_for_owner(owner_unit)
		local pm = Managers and Managers.player
		local ok, player = pm and pcall(pm.owner, pm, owner_unit)
		player = ok and player or nil
		if not player then return nil end
		if type(player.peer_id) == "string" then return player.peer_id end
		local nok, value = pcall(player.network_id, player)
		return nok and value or nil
	end

	local function safe_token(value)
		return tostring(value or "unknown"):gsub("[^%w_%-%.]", "_"):sub(1, 40)
	end

	function M.identity_for_peer(peer_id, slot_name, family_key)
		return safe_token(family_key) .. ":" .. safe_token(peer_id)
			.. ":" .. safe_token(slot_name)
	end

	function M.remote_identity(owner_unit, slot_name, family_key)
		return M.identity_for_peer(peer_for_owner(owner_unit), slot_name, family_key)
	end

	local function local_peer_id(owner_unit)
		return peer_for_owner(owner_unit) or "local"
	end

	local function publish_item(owner_unit, slot_name, item_data, recipient, reason)
		local family_key, local_identity = classify(item_data)
		if not family_key then return false end
		local mode = item_mode(item_data, local_identity)
		local identity = safe_token(family_key) .. ":" .. safe_token(local_peer_id(owner_unit))
			.. ":" .. safe_token(slot_name)
		local ok = send(recipient, "state", slot_name, mode, identity, family_key)
		if ok then
			pcall(printf, "[cwv:604] mode tx slot=%s mode=%s family=%s reason=%s",
				tostring(slot_name), tostring(mode), tostring(family_key), tostring(reason))
		end
		return ok
	end

	local function publish_loadout(recipient, reason)
		local pm = Managers and Managers.player
		local ok, player = pm and pcall(pm.local_player, pm, 1)
		player = ok and player or nil
		local owner_unit = player and player.player_unit
		local _, equipment = owner_equipment(owner_unit)
		local slot = equipment and equipment.slots and equipment.slots[M.SLOT]
		return slot and publish_item(owner_unit, M.SLOT, slot.item_data, recipient, reason) or false
	end

	local function rewield(player_unit, desired_mode, publish, forced_family_key, forced_identity, force_rebuild)
		local inv, equipment = owner_equipment(player_unit)
		local slot_name = equipment and equipment.wielded_slot
		local slot = slot_name and equipment.slots and equipment.slots[slot_name]
		local item_data = slot and slot.item_data
		local family_key, identity = classify(item_data)
		family_key, identity = family_key or forced_family_key, identity or forced_identity
		if slot_name ~= M.SLOT or not family_key then return false end
		local previous = item_mode(item_data, identity)
		if previous == desired_mode and not force_rebuild then return false end
		set_item_mode(item_data, identity, desired_mode)
		local ok_destroy = pcall(inv.destroy_slot, inv, slot_name, true)
		local ok_add = ok_destroy and pcall(inv.add_equipment, inv, slot_name, item_data)
		local ok_wield = ok_add and pcall(inv.wield, inv, slot_name)
		if not ok_wield then
			set_item_mode(item_data, identity, previous)
			pcall(printf, "[cwv:604] mode rebuild failed; restored=%s family=%s",
				tostring(previous), tostring(family_key))
			return false
		end
		apply_presentation(player_unit, slot_name, identity, desired_mode, false)
		if publish then publish_item(player_unit, slot_name, item_data, nil, "toggle") end
		return true
	end

	local function toggle(attacker_unit)
		local inv, equipment = owner_equipment(attacker_unit)
		local slot = equipment and equipment.wielded_slot
		local item_data = slot and equipment.slots and equipment.slots[slot]
		item_data = item_data and item_data.item_data
		local _, identity = classify(item_data)
		if not identity then return end
		local current = item_mode(item_data, identity)
		local desired = current == policy.MODE_HAMMER and policy.MODE_PICK or policy.MODE_HAMMER
		rewield(attacker_unit, desired, true)
	end

	local function install_special(template, template_name)
		template.actions = template.actions or {}
		template.actions.action_three = {
			default = {
				kind = "dummy",
				total_time = 0.15,
				anim_end_event = "attack_finished",
				enter_function = function(attacker_unit)
					toggle(attacker_unit)
				end,
				allowed_chain_actions = {},
				lookup_data = {
					item_template_name = template_name,
					action_name = "action_three",
					sub_action_name = "default",
				},
			},
		}
		if mod._cwv_old_musket_interrupt then
			mod._cwv_old_musket_interrupt.install(template, "action_three")
		end
	end

	install_special(pick_template, M.PICK_TEMPLATE_KEY)
	install_special(hammer_template, policy.HAMMER_TEMPLATE_KEY)

	function M.resolve_template(item_data, backend_id)
		if not enabled then return nil end
		local _, identity = classify(item_data, backend_id)
		if not identity then return nil end
		if restoring_source then return weapons[policy.SOURCE_TEMPLATE_KEY] end
		return item_mode(item_data, identity) == policy.MODE_HAMMER
			and weapons[policy.HAMMER_TEMPLATE_KEY] or weapons[M.PICK_TEMPLATE_KEY]
	end

	function M.on_local_wield(inventory, slot_name, item_data)
		if not enabled or slot_name ~= M.SLOT then return false end
		local _, identity = classify(item_data)
		if not identity then return false end
		apply_presentation(inventory.owner_unit, slot_name, identity,
			item_mode(item_data, identity), false)
		publish_item(inventory.owner_unit, slot_name, item_data, nil, "wield")
		return true
	end

	function M.on_husk_wield(inventory, slot_name)
		if not enabled or slot_name ~= M.SLOT then return false end
		local owner_unit = inventory and (inventory._unit or inventory.owner_unit)
		local _, equipment = owner_equipment(owner_unit)
		local slot = equipment and equipment.slots and equipment.slots[slot_name]
		local item_data = slot and slot.item_data
		if not _is_source_crowbill(family, item_data) then return false end
		-- A husk's wire item is the vanilla Crowbill and cannot identify which
		-- CWV family produced it. Reapply only an explicitly cached hammer edge;
		-- the canonical spawn resolver already owns pick/default presentation.
		for _, variant in ipairs(family.VARIANTS) do
			local identity = M.remote_identity(owner_unit, slot_name, variant.key)
			if state.modes[identity] == policy.MODE_HAMMER then
				return apply_presentation(owner_unit, slot_name, identity, policy.MODE_HAMMER, true)
			end
		end
		local vanilla_identity = M.remote_identity(owner_unit, slot_name, family.SOURCE_ITEM)
		if state.modes[vanilla_identity] == policy.MODE_HAMMER then
			return apply_presentation(owner_unit, slot_name, vanilla_identity,
				policy.MODE_HAMMER, true)
		end
		return false
	end

	function M.request_states(reason)
		if not enabled then return false end
		send("others", "query")
		return publish_loadout(nil, reason or "state_boundary")
	end

	function M.restore_local(reason)
		local pm = Managers and Managers.player
		local ok, player = pm and pcall(pm.local_player, pm, 1)
		player = ok and player or nil
		local unit = player and player.player_unit
		if not unit then return false end
		return rewield(unit, policy.MODE_PICK, true, nil, nil, true)
	end

	function M.set_enabled(value)
		value = not not value
		if enabled == value then return end
		if not value then
			restoring_source = true
			M.restore_local("disabled")
			restoring_source = false
		end
		enabled = value
		if value then
			M.restore_local("enabled_refresh")
			M.request_states("enabled")
		end
	end

	if type(mod.network_register) == "function" then
		pcall(function()
			mod:network_register(policy.CHANNEL,
				function(sender_peer_id, schema, op, slot_name, mode, identity, family_key)
					if not M.valid_wire(policy, family, schema, op, slot_name, mode, identity, family_key) then return end
					if op == "query" then
						publish_loadout(sender_peer_id, "query_reply")
						return
					end
					local pm = Managers and Managers.player
					local ok, player = pm and pcall(pm.player_from_peer_id, pm, sender_peer_id, 1)
					player = ok and player or nil
					local owner_unit = player and player.player_unit
					if not owner_unit then return end
					local _, equipment = owner_equipment(owner_unit)
					local slot = equipment and equipment.slots and equipment.slots[slot_name]
					if not slot or not _is_source_crowbill(family, slot.item_data) then return end
					local expected = safe_token(family_key) .. ":" .. safe_token(sender_peer_id)
						.. ":" .. safe_token(slot_name)
					if identity ~= expected then return end
					if mod._cwv_crowbill_apply_remote_mode then
						mod._cwv_crowbill_apply_remote_mode({
							channel = policy.CHANNEL,
							schema = policy.SCHEMA,
							identity = identity,
							mode = mode,
						})
					else
						state:apply_remote({ channel = policy.CHANNEL, schema = policy.SCHEMA,
							identity = identity, mode = mode })
					end
					apply_presentation(owner_unit, slot_name, identity, mode, true)
				end)
		end)
	end

	if mod._cwv_peer_parity and type(mod._cwv_peer_parity.register_gated_feature) == "function" then
		mod._cwv_peer_parity:register_gated_feature("cwv_crowbill_mode_sync", {
			label = "Crowbill mode synchronization",
			on_enable = function() M.request_states("peer_parity") end,
		})
	end

	M._state = state
	M._generated = generated
	M._installed = true
	return M
end

return M
