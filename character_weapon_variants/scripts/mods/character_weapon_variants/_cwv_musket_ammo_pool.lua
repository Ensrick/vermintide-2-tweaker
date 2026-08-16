-- Owner-scoped shared reserve for the Old Musket (#932, #1107).
--
-- Native VT2 gives each weapon unit an independent GenericAmmoUserExtension.
-- This controller keeps the native extensions and their chambers, but owns one
-- reserve value for the Old Muskets in a single player's melee/ranged slots.
-- It never mutates `_max_ammo`; public max-ammo queries are adapted by the
-- installed hook while the controller synchronizes `_available_ammo` only.
--
-- #1107: vanilla's reload completion refills the chamber unconditionally but
-- charges `_available_ammo` only inside `if buff_extension then`
-- (generic_ammo_user_extension.lua:164-175), and `apply_buffs` assigns
-- `owner_buff_extension` for slot_ranged/slot_career_skill_weapon only
-- (:83-89). A melee-slot musket therefore reloads for free. The update hook
-- below tracks the chamber across the vanilla call and charges the pool for
-- any refill vanilla did not charge itself (consumption-side only).

local M = {}

local VALID_SLOTS = {
	slot_melee = true,
	slot_ranged = true,
}

local function clamp_integer(value, maximum)
	value = type(value) == "number" and value or 0
	maximum = type(maximum) == "number" and maximum or 0
	return math.floor(math.max(0, math.min(value, maximum)))
end

function M.new(options)
	options = options or {}
	local controller = {
		reserve_per_musket = options.reserve_per_musket or 10,
		_alive = options.alive or function() return true end,
		_log = options.log or function() end,
		_pools = setmetatable({}, { __mode = "kv" }),
		-- A live engine extension strongly retains its pool through this weak-key
		-- index. Once the engine releases every extension, neither index alone
		-- keeps the owner/pool generation alive.
		extensions = setmetatable({}, { __mode = "k" }),
		hooks_installed = false,
	}

	function controller:_pool_for_owner(owner, create)
		if owner == nil then return nil end
		local pool = self._pools[owner]
		if not pool and create then
			pool = { reserve = 0, slots = {} }
			self._pools[owner] = pool
		end
		return pool
	end

	function controller:_active_record(ext)
		local pool = self.extensions[ext]
		local slot_name = ext and ext._cwv_musket_pool_slot
		local record = pool and slot_name and pool.slots[slot_name]
		if record and record.ext == ext then return pool, record end
		return nil, nil
	end

	function controller:_member_count(pool)
		local count = 0
		for slot_name, record in pairs(pool and pool.slots or {}) do
			if VALID_SLOTS[slot_name] and record and record.ext then count = count + 1 end
		end
		return count
	end

	function controller:_capacity(pool)
		return self:_member_count(pool) * self.reserve_per_musket
	end

	function controller:_sync(pool)
		if not pool then return end
		pool.reserve = clamp_integer(pool.reserve, self:_capacity(pool))
		for slot_name, record in pairs(pool.slots) do
			local ext = record and record.ext
			if VALID_SLOTS[slot_name] and ext and self._alive(ext.unit) then
				ext._available_ammo = pool.reserve
			end
		end
	end

	function controller:register(ext, owner, slot_name)
		owner = owner or (ext and ext.owner_unit)
		slot_name = slot_name or (ext and ext.slot_name)
		if not ext or not owner or not VALID_SLOTS[slot_name] or not self._alive(ext.unit) then
			return false
		end
		local pool = self:_pool_for_owner(owner, true)
		local previous = pool.slots[slot_name]
		if previous and previous.ext == ext then
			self:_sync(pool)
			return true
		end
		if previous and previous.ext then
			self.extensions[previous.ext] = nil
			previous.ext._cwv_musket_pool_member = nil
			previous.ext._cwv_musket_pool_slot = nil
		end
		if not previous then
			pool.reserve = pool.reserve + clamp_integer(ext._available_ammo, self.reserve_per_musket)
		end
		pool.slots[slot_name] = { ext = ext }
		self.extensions[ext] = pool
		ext._cwv_musket_pool_member = true
		ext._cwv_musket_pool_slot = slot_name
		self:_sync(pool)
		self._log("register", owner, slot_name, pool.reserve, self:_capacity(pool))
		return true
	end

	function controller:unregister_slot(owner, slot_name)
		if not owner or not VALID_SLOTS[slot_name] then return false end
		local pool = self:_pool_for_owner(owner, false)
		local record = pool and pool.slots[slot_name]
		if not record then return false end
		if record.ext then
			self.extensions[record.ext] = nil
			record.ext._cwv_musket_pool_member = nil
			record.ext._cwv_musket_pool_slot = nil
		end
		pool.slots[slot_name] = nil
		self:_sync(pool)
		self._log("unregister", owner, slot_name, pool.reserve, self:_capacity(pool))
		return true
	end

	function controller:capacity_for(ext_or_owner)
		local pool = ext_or_owner and self.extensions[ext_or_owner]
			or self:_pool_for_owner(ext_or_owner, false)
		return pool and self:_capacity(pool) or 0
	end

	function controller:reserve_for(ext)
		local pool = self:_active_record(ext)
		return pool and pool.reserve or nil
	end

	-- Presentation consumers may resolve only the exact currently registered
	-- extension for one owner+slot. A stale replacement or dead weapon unit is
	-- never allowed to stand in for the live primary-slot Old Musket (#1108).
	function controller:extension_for(owner, slot_name)
		if not owner or not VALID_SLOTS[slot_name] then return nil end
		local pool = self:_pool_for_owner(owner, false)
		local record = pool and pool.slots[slot_name]
		local ext = record and record.ext
		if not ext or self.extensions[ext] ~= pool or not self._alive(ext.unit) then
			return nil
		end
		return ext
	end

	function controller:begin_mutation(ext)
		local pool = self:_active_record(ext)
		if not pool then return nil end
		self:_sync(pool)
		return pool.reserve
	end

	function controller:end_delta(ext, before)
		local pool = self:_active_record(ext)
		if not pool or before == nil then return end
		local after = type(ext._available_ammo) == "number" and ext._available_ammo or before
		pool.reserve = before + (after - before)
		self:_sync(pool)
	end

	-- #1107: charge the pool for a reload that vanilla completed WITHOUT
	-- draining reserve (melee-slot muskets have a nil `owner_buff_extension`
	-- for their whole life, so vanilla's decrement at
	-- generic_ammo_user_extension.lua:174 never runs for them). Returns the
	-- number of rounds drained. `exempt_fn(ext)` mirrors vanilla's
	-- no-consumption buffs (:169-173) and is only consulted when an
	-- uncharged refill actually happened. Never touches `_max_ammo`.
	function controller:end_reload_drain(ext, chamber_before, exempt_fn)
		local pool = self:_active_record(ext)
		if not pool or chamber_before == nil then return 0 end
		if ext.owner_buff_extension then return 0 end -- vanilla already charged reserve
		local chamber_after = (tonumber(ext._current_ammo) or 0) - (tonumber(ext._shots_fired) or 0)
		local refill = chamber_after - chamber_before
		if refill <= 0 then return 0 end
		if exempt_fn and exempt_fn(ext) then
			self._log("reload_drain_exempt", ext.owner_unit, ext._cwv_musket_pool_slot,
				pool.reserve, self:_capacity(pool))
			return 0
		end
		local reserve = type(ext._available_ammo) == "number" and ext._available_ammo or pool.reserve
		local drained = math.min(refill, math.max(reserve, 0))
		ext._available_ammo = reserve - drained
		return drained
	end

	function controller:end_add(ext, before, amount)
		local pool = self:_active_record(ext)
		if not pool or before == nil then return end
		local context = pool.pickup
		local delta
		if context then
			if context.applied then
				delta = 0
			else
				context.applied = true
				if type(context.refill_percentage) == "number" then
					delta = self:_capacity(pool) * context.refill_percentage
				else
					delta = context.refill_amount or amount
				end
			end
		elseif amount == nil then
			delta = self:_capacity(pool) - before
		else
			delta = amount
		end
		pool.reserve = before + (type(delta) == "number" and delta or 0)
		self:_sync(pool)
	end

	function controller:end_remove(ext, before, amount)
		local pool = self:_active_record(ext)
		if not pool or before == nil then return end
		pool.reserve = before - (type(amount) == "number" and amount or 0)
		self:_sync(pool)
	end

	function controller:end_reset(ext)
		local pool = self:_active_record(ext)
		if not pool then return end
		pool.reserve = self:_capacity(pool)
		self:_sync(pool)
	end

	function controller:end_preserve(ext, before)
		local pool = self:_active_record(ext)
		if not pool or before == nil then return end
		pool.reserve = before
		self:_sync(pool)
	end

	function controller:begin_pickup(owner, pickup_settings)
		local pool = self:_pool_for_owner(owner, false)
		if not pool then return end
		pickup_settings = pickup_settings or {}
		pool.pickup = {
			refill_percentage = pickup_settings.refill_percentage,
			refill_amount = pickup_settings.refill_amount,
			applied = false,
		}
	end

	function controller:end_pickup(owner)
		local pool = self:_pool_for_owner(owner, false)
		if pool then pool.pickup = nil end
	end

	function controller:max_ammo_for(ext)
		local pool = self:_active_record(ext)
		if not pool then return nil end
		return self:_capacity(pool) + (ext._ammo_per_clip or 0)
	end

	function controller:contract_error()
		if not self.hooks_installed then return "musket ammo controller hooks are not installed" end
		if type(self.end_reload_drain) ~= "function" then
			return "melee-slot reload reserve drain (#1107) is missing"
		end
		if type(self.extension_for) ~= "function" then
			return "owner-slot extension selection (#1108) is missing"
		end
		if self.reserve_per_musket ~= 10 then return "Old Musket reserve contribution is not 10" end
		if not VALID_SLOTS.slot_melee or not VALID_SLOTS.slot_ranged then
			return "musket ammo controller does not own both equipment slots"
		end
	end

	return controller
end

function M.install(mod, options)
	local controller = M.new(options)

	-- #1107 parity with the vanilla reload block's buff exemptions
	-- (generic_ammo_user_extension.lua:169-173): a reload that vanilla would
	-- not charge to reserve on the ranged slot must not drain the pool from
	-- the melee slot either.
	local function _reload_drain_exempt(ext)
		local owner_unit = ext.owner_unit
		local script_unit = rawget(_G, "ScriptUnit")
		local buff_extension = owner_unit and script_unit and script_unit.has_extension
			and script_unit.has_extension(owner_unit, "buff_system")
		if not buff_extension then return false end
		return (buff_extension:has_buff_type("no_ammo_consumed")
			or buff_extension:has_buff_type("markus_huntsman_activated_ability")
			or buff_extension:has_buff_type("markus_huntsman_activated_ability_duration")
			or buff_extension:has_buff_type("twitch_no_overcharge_no_ammo_reloads")) and true or false
	end

	mod:hook("GenericAmmoUserExtension", "update", function(orig, self, ...)
		local before = controller:begin_mutation(self)
		-- #1107: chamber count (`ammo_count()`) only grows inside vanilla
		-- update via the reload refill at generic_ammo_user_extension.lua:166;
		-- `_check_ammo` reconciles `_shots_fired` into `_current_ammo` without
		-- changing the difference. A positive delta across the call is exactly
		-- the completed reload amount.
		local chamber_before
		if before ~= nil then
			chamber_before = (tonumber(self._current_ammo) or 0) - (tonumber(self._shots_fired) or 0)
		end
		local result = orig(self, ...)
		if chamber_before ~= nil then
			local drained = controller:end_reload_drain(self, chamber_before, _reload_drain_exempt)
			if drained > 0 then
				pcall(printf, "[cwv:1107] melee-slot musket reload drained %d round(s): reserve %d -> %d",
					drained, before, tonumber(self._available_ammo) or 0)
			end
		end
		controller:end_delta(self, before)
		return result
	end)

	mod:hook("GenericAmmoUserExtension", "add_ammo", function(orig, self, amount)
		local before = controller:begin_mutation(self)
		local result = orig(self, amount)
		controller:end_add(self, before, amount)
		return result
	end)

	mod:hook("GenericAmmoUserExtension", "remove_ammo", function(orig, self, amount)
		local before = controller:begin_mutation(self)
		local result = orig(self, amount)
		controller:end_remove(self, before, amount)
		return result
	end)

	mod:hook("GenericAmmoUserExtension", "add_ammo_to_reserve", function(orig, self, amount)
		local before = controller:begin_mutation(self)
		local result = orig(self, amount)
		controller:end_add(self, before, amount)
		return result
	end)

	mod:hook("GenericAmmoUserExtension", "instant_reload", function(orig, self, ...)
		local before = controller:begin_mutation(self)
		local result = orig(self, ...)
		controller:end_delta(self, before)
		return result
	end)

	mod:hook("GenericAmmoUserExtension", "refresh_buffs", function(orig, self, ...)
		local before = controller:begin_mutation(self)
		local result = orig(self, ...)
		controller:end_preserve(self, before)
		return result
	end)

	mod:hook("GenericAmmoUserExtension", "reset", function(orig, self, ...)
		local result = orig(self, ...)
		controller:end_reset(self)
		return result
	end)

	mod:hook("GenericAmmoUserExtension", "max_ammo", function(orig, self, ...)
		return controller:max_ammo_for(self) or orig(self, ...)
	end)

	mod:hook("SimpleInventoryExtension", "add_ammo_from_pickup", function(orig, self, pickup_settings)
		local owner = self._unit
		controller:begin_pickup(owner, pickup_settings)
		local ok, error_message = pcall(orig, self, pickup_settings)
		controller:end_pickup(owner)
		if not ok then error(error_message) end
	end)

	controller.hooks_installed = true
	return controller
end

return M
