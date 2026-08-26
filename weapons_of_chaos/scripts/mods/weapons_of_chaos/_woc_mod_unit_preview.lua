-- WOC preview residency, exact TeamPreviewer identity, and retained pose owner.
--
-- Workshop units are resident through WOC's master bundle, not discoverable as
-- standalone global packages. Previewers therefore borrow a vanilla package
-- lease while retaining the authored unit in spawn data. TeamPreviewer gets its
-- wearer only from the accepted host lease snapshot; its vanilla/net-safe sword
-- row is never treated as proof of Blightreaper identity.
local M = {}

function M.install(policy, appearance, options)
	options = options or {}
	local mod = options.mod or get_mod("WOC")
	if mod._woc_mod_unit_preview_installed then
		return mod._woc_mod_unit_preview_runtime
	end
	mod._woc_mod_unit_preview_installed = true

	local transform_owner = options.transform_owner
	local team_identity = options.team_identity
	local identity_for_peer = options.identity_for_peer
	local item_key = options.item_key
	local backend_id = options.backend_id
	local team_records = setmetatable({}, { __mode = "k" })
	local identity_pending = setmetatable({}, { __mode = "k" })
	local animation_pending = setmetatable({}, { __mode = "k" })
	local transformed = setmetatable({}, { __mode = "k" })
	local diag_budget = 16

	local function diag(format, ...)
		if diag_budget <= 0 then return end
		diag_budget = diag_budget - 1
		pcall(printf, "[WOC:613] " .. format, ...)
	end

	local function alias_for(name)
		return policy.preview_package_alias(name)
	end

	local function resident(name)
		local ok, value = pcall(Application.can_get, "unit", name)
		return ok and value == true
	end

	local function character_surface(previewer)
		if previewer and previewer._woc_team_preview then
			return previewer._woc_team_peer_source == "score_snapshot"
				and "score-preview" or "lobby-preview"
		end
		return "character-preview"
	end

	local function item_surface(previewer)
		return previewer and previewer._woc_cim_preview
			and "cim-preview" or "item-preview"
	end

	local function apply(unit, name, surface)
		local policy_ok, custom = pcall(policy.is_custom_unit_name, name)
		if not policy_ok or custom ~= true then return false end
		if unit == nil or transformed[unit] then return false end
		local perspective = name == policy.UNIT_3P and "3p" or "1p"
		local spec = policy.TRANSFORM
		if type(policy.transform_for) == "function" then
			local spec_ok, resolved = pcall(policy.transform_for, perspective)
			if not spec_ok then
				diag("preview transform policy rejected surface=%s perspective=%s",
					tostring(surface), tostring(perspective))
				return false
			end
			spec = resolved
		end
		local call_ok, applied = false, false
		if appearance and type(appearance.apply) == "function" then
			call_ok, applied = pcall(appearance.apply,
				unit, spec, perspective, surface)
		end
		local ok = call_ok and applied == true
		if not call_ok then
			diag("preview appearance callback rejected surface=%s perspective=%s",
				tostring(surface), tostring(perspective))
		end
		if ok then transformed[unit] = true end
		return ok
	end

	local function forget_unit(unit)
		if unit == nil then return end
		transformed[unit] = nil
		if transform_owner and type(transform_owner.forget) == "function" then
			local ok = pcall(transform_owner.forget, transform_owner, unit)
			if not ok then diag("preview transform forget callback rejected") end
		end
	end

	local function each_equipment_unit(previewer, fn)
		local seen = setmetatable({}, { __mode = "k" })
		for _, slot in pairs(previewer and previewer._equipment_units or {}) do
			if type(slot) == "table" then
				for _, hand in ipairs({ "right", "left" }) do
					local unit = slot[hand]
					if unit ~= nil and not seen[unit] then
						seen[unit] = true
						fn(unit)
					end
				end
			end
		end
	end

	local function queue_post_animation(previewer, edge)
		if previewer then
			animation_pending[previewer] = {
				edge = edge,
				world = previewer.world,
				session_id = previewer._session_id,
			}
		end
	end

	local function flush_post_animation(previewer)
		local pending = animation_pending[previewer]
		animation_pending[previewer] = nil
		if not pending or previewer.world == nil
				or previewer.world ~= pending.world
				or previewer._session_id ~= pending.session_id
				or not transform_owner
				or type(transform_owner.reapply) ~= "function" then return 0 end
		local retained = 0
		each_equipment_unit(previewer, function(unit)
			local call_ok, ok, reason = pcall(transform_owner.reapply,
				transform_owner, unit,
				"preview-post-animation:" .. tostring(pending.edge))
			if call_ok and ok then retained = retained + 1
			elseif not call_ok then
				diag("preview post-animation callback rejected edge=%s",
					tostring(pending.edge))
			elseif reason ~= "untracked" and reason ~= "dead" then
				diag("preview post-animation miss edge=%s reason=%s",
					tostring(pending.edge), tostring(reason))
			end
		end)
		return retained
	end

	local warned = {}
	local function warn_once(name, fallback)
		if warned[name] then return end
		warned[name] = true
		pcall(printf, "[WOC:613] custom unit not resident; preview fallback unit=%s fallback=%s",
			tostring(name), tostring(fallback))
	end

	local function snapshot_for(record)
		if not record or type(record.peer_id) ~= "string"
				or type(identity_for_peer) ~= "function" then return nil, nil end
		local ok, snapshot = pcall(identity_for_peer, record.peer_id)
		if not ok or type(team_identity) ~= "table"
				or type(team_identity.snapshot_token) ~= "function" then return nil, nil end
		local token = team_identity.snapshot_token(snapshot, record.peer_id, item_key)
		return token and snapshot or nil, token
	end

	local function slot_name_for(slot)
		if type(slot) ~= "table" then return nil end
		if slot.name == "slot_melee" or slot.name == "slot_ranged" then
			return slot.name
		end
		if slot.type == "melee" or slot.type == "ranged" then
			return "slot_" .. slot.type
		end
		return nil
	end

	local function resolve_team_peer(hero_data, context)
		if type(team_identity) ~= "table" or type(hero_data) ~= "table" then
			return nil, "resolver_unavailable"
		end
		local profile_index, career_index =
			hero_data.profile_index, hero_data.career_index
		local scores = context and context.players_session_score
		if type(scores) == "table" then
			return team_identity.resolve_score_peer(
				profile_index, career_index, scores)
		end
		local pm = Managers and Managers.player
		if not (pm and type(pm.human_players) == "function") then
			return nil, "live_unavailable"
		end
		local ok_players, players = pcall(pm.human_players, pm)
		if not ok_players then return nil, "live_unavailable" end
		local synchronizer = context and context.profile_synchronizer
		if not synchronizer then
			local network = Managers.state and Managers.state.network
			synchronizer = network and network.profile_synchronizer
		end
		local function profile_for(player)
			if synchronizer and type(synchronizer.profile_by_peer) == "function" then
				local local_id = 1
				if type(player.local_player_id) == "function" then
					local ok_id, value = pcall(player.local_player_id, player)
					if not ok_id or type(value) ~= "number" then return nil end
					local_id = value
				elseif type(player.local_player_id) == "number" then
					local_id = player.local_player_id
				elseif type(player._local_player_id) == "number" then
					local_id = player._local_player_id
				else
					return nil
				end
				local ok, pi, ci = pcall(synchronizer.profile_by_peer,
					synchronizer, player.peer_id, local_id)
				if ok and pi ~= nil and ci ~= nil then return pi, ci, local_id end
			end
			local pi, ci, local_id
			if type(player.profile_index) == "function" then
				local ok, value = pcall(player.profile_index, player)
				if ok then pi = value end
			end
			if type(player.career_index) == "function" then
				local ok, value = pcall(player.career_index, player)
				if ok then ci = value end
			end
			if type(player.local_player_id) == "function" then
				local ok, value = pcall(player.local_player_id, player)
				if ok then local_id = value end
			elseif type(player.local_player_id) == "number" then
				local_id = player.local_player_id
			elseif type(player._local_player_id) == "number" then
				local_id = player._local_player_id
			end
			return pi, ci, local_id
		end
		return team_identity.resolve_live_peer(
			profile_index, career_index, players, profile_for)
	end

	local function valid_team_record(previewer, record)
		return record and team_records[previewer] == record
			and previewer.world ~= nil
			and previewer._session_id == record.session_id
	end

	local function flush_identity(previewer)
		local pending = identity_pending[previewer]
		identity_pending[previewer] = nil
		local record = team_records[previewer]
		if not pending or pending.record ~= record
				or not valid_team_record(previewer, record) then
			return false, "stale-consumer"
		end
		local snapshot, token = snapshot_for(record)
		if not snapshot or token ~= pending.token then
			return false, "stale-generation"
		end
		record.reapplying = true
		local count, failures = 0, 0
		for _, slot_name in ipairs({ "slot_melee", "slot_ranged" }) do
			local base = record.base_by_slot[slot_name]
			local slot = InventorySettings and InventorySettings.slots_by_name
				and InventorySettings.slots_by_name[slot_name]
			if base and slot and type(previewer.equip_item) == "function" then
				local ok = pcall(previewer.equip_item, previewer,
					base.item_name, slot, base.backend_id,
					base.skin, base.skip_wield_anim)
				if ok then count = count + 1 else failures = failures + 1 end
			end
		end
		record.reapplying = false
		if failures > 0 then
			-- This is a WOC-owned asynchronous replay, so a rejected preview row
			-- must not bring down the UI. Release the dedupe token so a later
			-- authoritative generation may retry, but do not poll every frame.
			record.notified_token = nil
			diag("team preview identity replay rejected peer=%s failures=%d chat=false",
				tostring(record.peer_id), failures)
			return false, "replay-error"
		end
		if count > 0 then
			diag("team preview identity replay peer=%s generation=%s rows=%d source=%s chat=false",
				tostring(record.peer_id), tostring(snapshot.generation), count,
				tostring(record.source))
		end
		return count > 0, count > 0 and "replayed" or "no-items"
	end

	-- ProfileSynchronizer treats collected unit paths as package identities.
	mod:hook(WeaponUtils, "get_weapon_packages", function(func, ...)
		local packages = func(...)
		policy.alias_collected_packages(packages)
		return packages
	end)

	local function load_character_packages(func, self, packages)
		for i, name in ipairs(packages or {}) do
			local alias = alias_for(name)
			if alias then
				packages[i] = alias
				if not resident(name) then
					warn_once(name, alias)
					for _, slot in pairs(self._item_info_by_slot or {}) do
						for _, spawn in ipairs(slot.spawn_data or {}) do
							if spawn.unit_name == name then spawn.unit_name = alias end
						end
					end
				end
			end
		end
		return func(self, packages)
	end
	mod:hook("HeroPreviewer", "_load_packages", load_character_packages)
	mod:hook("MenuWorldPreviewer", "_load_packages", load_character_packages)

	-- Resolve the wearer before TeamPreviewer starts its asynchronous hero spawn,
	-- then stamp the consumer after vanilla's synchronous request path has called
	-- HeroPreviewer:clear_units(). Stamping earlier would let that mandatory clear
	-- retire the new record before the delayed package callback can equip items.
	-- Score rows use the immutable end-view snapshot; live lobby rows require an
	-- exact human profile+career match. The custom render key comes only from the
	-- separately authenticated host lease snapshot below.
	mod:hook("TeamPreviewer", "_spawn_hero",
			function(func, self, hero_previewer, hero_data)
		local peer_id, source = resolve_team_peer(hero_data, self and self._context)
		local result = func(self, hero_previewer, hero_data)
		if hero_previewer then
			hero_previewer._woc_team_preview = true
			hero_previewer._woc_team_wearer_peer = peer_id
			hero_previewer._woc_team_peer_source = source
			team_records[hero_previewer] = {
				peer_id = peer_id,
				source = source,
				base_by_slot = {},
				items_seen = false,
				session_id = hero_previewer._session_id,
			}
		end
		return result
	end)

	-- TeamPreviewer's `preview_items` deliberately carry vanilla/net-safe keys.
	-- Substitute the immutable local WOC item only when this exact wearer+slot is
	-- active in the current accepted host snapshot. Original row data is retained
	-- so a later authoritative release can rebuild the vanilla preview once.
	local function equip_team_item(func, self, item_name_arg, slot,
			backend_id_arg, skin, skip_wield_anim, ...)
		local item_name, selected_backend = item_name_arg, backend_id_arg
		local record = team_records[self]
		local slot_name = slot_name_for(slot)
		if record and slot_name then
			if not record.reapplying and not record.base_by_slot[slot_name] then
				record.base_by_slot[slot_name] = {
					item_name = item_name_arg,
					backend_id = backend_id_arg,
					skin = skin,
					skip_wield_anim = skip_wield_anim,
				}
			end
			record.items_seen = true
			local snapshot, token = snapshot_for(record)
			if snapshot and team_identity.active_for_slot(
					snapshot, record.peer_id, item_key, slot_name) then
				item_name, selected_backend, skin = item_key, backend_id, nil
			end
			record.applied_token = token
		end
		return func(self, item_name, slot, selected_backend, skin,
			skip_wield_anim, ...)
	end
	mod:hook("HeroPreviewer", "equip_item", equip_team_item)

	-- Character previews (inventory, lobby, score/end). Hook the parent and the
	-- copy-derived MenuWorldPreviewer because VT2 copies class methods at boot.
	local function transform_character_items(func, self, item_name, spawn_data)
		local result = func(self, item_name, spawn_data)
		for _, spawn in ipairs(spawn_data or {}) do
			if policy.is_custom_unit_name(spawn.unit_name) then
				local slot = self._equipment_units and self._equipment_units[spawn.slot_index]
				local unit = type(slot) == "table"
					and (spawn.right_hand and slot.right or spawn.left_hand and slot.left)
				apply(unit, spawn.unit_name, character_surface(self))
			end
		end
		return result
	end
	mod:hook("HeroPreviewer", "_spawn_item", transform_character_items)
	mod:hook("MenuWorldPreviewer", "_spawn_item", transform_character_items)

	-- Animation events can update linked child poses after the initial spawn
	-- callback. Queue one next-post_update absolute reapply/readback; repeated
	-- animation calls before that frame coalesce to the newest concrete edge.
	local function install_animation_hooks(class_name)
		for _, method in ipairs({
			"play_character_animation", "trigger_pose_animation", "reset_pose_animation",
		}) do
			local method_name = method
			mod:hook(class_name, method_name, function(func, self, ...)
				local result = func(self, ...)
				queue_post_animation(self, method_name)
				return result
			end)
		end
		mod:hook(class_name, "post_update", function(func, self, ...)
			local result = func(self, ...)
			flush_identity(self)
			flush_post_animation(self)
			return result
		end)
		mod:hook(class_name, "_destroy_item_units_by_slot",
				function(func, self, slot_type, ...)
			local info = self._item_info_by_slot and self._item_info_by_slot[slot_type]
			for _, row in ipairs(info and info.spawn_data or {}) do
				local slot = self._equipment_units and self._equipment_units[row.slot_index]
				if type(slot) == "table" then
					if row.right_hand or row.despawn_both_hands_units then
						forget_unit(slot.right)
					end
					if row.left_hand or row.despawn_both_hands_units then
						forget_unit(slot.left)
					end
				end
			end
			return func(self, slot_type, ...)
		end)
		-- TeamPreviewer teardown and HeroPreviewer respawn both call clear_units
		-- directly; neither is required to traverse the slot-specific destroy
		-- method above. Retire every durable record before vanilla destroys the
		-- units so cleanup is deterministic rather than waiting for weak GC.
		mod:hook(class_name, "clear_units", function(func, self, ...)
			each_equipment_unit(self, forget_unit)
			team_records[self] = nil
			identity_pending[self] = nil
			animation_pending[self] = nil
			return func(self, ...)
		end)
		mod:hook(class_name, "on_exit", function(func, self, ...)
			team_records[self] = nil
			identity_pending[self] = nil
			animation_pending[self] = nil
			return func(self, ...)
		end)
	end
	install_animation_hooks("HeroPreviewer")
	install_animation_hooks("MenuWorldPreviewer")

	-- Mark only the exact previewer returned by CIM's Athanor factory. The
	-- vararg wrapper preserves the engine method's complete signature and avoids
	-- misclassifying generic LootItemUnitPreviewer instances as Athanor.
	mod:hook("HeroWindowWeaveProperties", "_create_item_previewer",
			function(func, self, ...)
		local previewer = func(self, ...)
		if previewer then previewer._woc_cim_preview = true end
		return previewer
	end)

	-- Generic item/illusion browser and the exactly marked Athanor preview. One
	-- custom key owns one borrowed lease.
	mod:hook("LootItemUnitPreviewer", "load_package", function(func, self, name)
		local alias = alias_for(name)
		if not alias then return func(self, name) end
		if type(self._packages_to_load) ~= "table" then
			diag("preview package load rejected reason=pending-table-unavailable")
			return
		end
		if self._packages_to_load[name] ~= nil then return end
		self._packages_to_load[name] = true
		self._woc_preview_aliases = self._woc_preview_aliases or {}
		self._woc_preview_aliases[name] = alias
		if not resident(name) then
			self._woc_preview_fallbacks = self._woc_preview_fallbacks or {}
			self._woc_preview_fallbacks[name] = alias
			warn_once(name, alias)
		end
		local reference = "LootItemUnitPreviewer" .. tostring(self._unique_id or "")
		local package_manager = Managers and Managers.package
		if not package_manager or type(package_manager.load) ~= "function" then
			self._packages_to_load[name] = nil
			self._woc_preview_aliases[name] = nil
			if self._woc_preview_fallbacks then
				self._woc_preview_fallbacks[name] = nil
			end
			diag("preview package load rejected reason=manager-unavailable")
			return
		end
		local loaded = pcall(package_manager.load, package_manager,
			alias, reference, function()
			if self._packages_to_load and self._packages_to_load[name] ~= nil then
				local complete = type(self._on_load_complete) == "function"
					and pcall(self._on_load_complete, self, name)
				if not complete then
					-- The borrowed lease is live even if a foreign callback rejects.
					-- Preserve vanilla's two-table completion shape so teardown can
					-- release the exact alias and the preview can fail open.
					self._loaded_packages = self._loaded_packages or {}
					self._loaded_packages[name] = true
					self._packages_to_load[name] = false
					diag("preview package completion callback rejected")
				end
			end
		end, true)
		if not loaded then
			self._packages_to_load[name] = nil
			self._woc_preview_aliases[name] = nil
			if self._woc_preview_fallbacks then
				self._woc_preview_fallbacks[name] = nil
			end
			diag("preview package load callback rejected")
		end
	end)

	mod:hook("LootItemUnitPreviewer", "spawn_units", function(func, self, spawn_data)
		for _, spawn in ipairs(spawn_data or {}) do
			local fallback = self._woc_preview_fallbacks
				and self._woc_preview_fallbacks[spawn.unit_name]
			if fallback then spawn.unit_name = fallback end
		end
		local units = func(self, spawn_data)
		for index, spawn in ipairs(spawn_data or {}) do
			apply(units and units[index], spawn.unit_name, item_surface(self))
		end
		return units
	end)

	mod:hook("LootItemUnitPreviewer", "_destroy_units", function(func, self, ...)
		for _, unit in ipairs(self._spawned_units or {}) do forget_unit(unit) end
		return func(self, ...)
	end)

	mod:hook("LootItemUnitPreviewer", "_unload_packages", function(func, self)
		local loaded = self._loaded_packages or {}
		local pending = self._packages_to_load or {}
		for custom, alias in pairs(self._woc_preview_aliases or {}) do
			if loaded[custom] ~= nil then loaded[custom], loaded[alias] = nil, true end
			if pending[custom] ~= nil then
				local still_loading = pending[custom] == true
				pending[custom], pending[alias] = nil, still_loading
			end
		end
		local result = func(self)
		self._woc_preview_aliases = nil
		self._woc_preview_fallbacks = nil
		return result
	end)

	local runtime = {}

	function runtime:notify_identity(peer_id, snapshot, reason)
		if type(team_identity) ~= "table"
				or type(team_identity.snapshot_token) ~= "function" then return 0 end
		local token = team_identity.snapshot_token(snapshot, peer_id, item_key)
		if not token then return 0 end
		local queued = 0
		for previewer, record in pairs(team_records) do
			if record.peer_id == peer_id and valid_team_record(previewer, record)
					and record.items_seen and record.notified_token ~= token then
				record.notified_token = token
				identity_pending[previewer] = {
					token = token, reason = reason, record = record,
				}
				queued = queued + 1
			end
		end
		return queued
	end

	if options.test_api then
		function runtime:test_snapshot(previewer)
			local record = team_records[previewer]
			return {
				record = record,
				identity_pending = identity_pending[previewer],
				animation_pending = animation_pending[previewer],
			}
		end
	end

	mod._woc_mod_unit_preview_runtime = runtime
	return runtime
end

return M
