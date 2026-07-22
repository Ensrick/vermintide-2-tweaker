-- Canonical appearance fade enrollment adapter (issue #922).
--
-- Stingray's FadeSystem does not discover units linked after a player fade
-- extension is initialized.  Callers submit one complete, current snapshot of
-- 3P inventory and cosmetic attachment units at bounded lifecycle edges.  The
-- adapter is engine-agnostic: each standalone mod injects its own safe engine
-- accessors, and any unavailable/foreign extension fails open.

local M = {}

local INVENTORY_FIELDS = {
	"right_hand_wielded_unit_3p",
	"right_hand_ammo_unit_3p",
	"left_hand_wielded_unit_3p",
	"left_hand_ammo_unit_3p",
}

local function add_live(units, seen, unit, alive)
	if unit == nil or seen[unit] then return end
	local ok, is_live = pcall(alive, unit)
	if ok and is_live then
		seen[unit] = true
		units[#units + 1] = unit
	end
end

function M.collect(context, alive)
	context = context or {}
	alive = alive or function(unit) return unit ~= nil end
	local units, seen = {}, {}
	local equipment = context.equipment
		or (context.inventory_extension and context.inventory_extension._equipment)

	for _, field in ipairs(INVENTORY_FIELDS) do
		add_live(units, seen, equipment and equipment[field], alive)
	end

	local attachments = context.attachments
		or (context.attachment_extension and context.attachment_extension._attachments)
	local slots = attachments and attachments.slots
	if type(slots) == "table" then
		local names = {}
		for name in pairs(slots) do
			names[#names + 1] = { key = name, sort_key = tostring(name) }
		end
		table.sort(names, function(a, b) return a.sort_key < b.sort_key end)
		for _, name in ipairs(names) do
			local row = slots[name.key]
			add_live(units, seen, row and row.unit, alive)
		end
	end

	for _, unit in ipairs(context.extra_units or {}) do
		add_live(units, seen, unit, alive)
	end

	return units
end

local function fingerprint(units)
	local parts = {}
	for i, unit in ipairs(units) do parts[i] = tostring(unit) end
	return table.concat(parts, "|")
end

function M.new(deps)
	deps = deps or {}
	local instance = {
		_last_by_owner = setmetatable({}, { __mode = "k" }),
		_last_report_by_owner = setmetatable({}, { __mode = "k" }),
		_diag_seen = {},
		_diag_remaining = tonumber(deps.diag_budget) or 0,
	}

	local function report_once(report)
		if type(deps.report) ~= "function" or instance._diag_remaining <= 0
				or report.reason == "unchanged" or report.reason == "no_linked_units" then
			return
		end
		local signature = table.concat({
			tostring(report.edge), tostring(report.reason),
			tostring(report.count), tostring(report.error),
		}, "|")
		if instance._diag_seen[signature] then return end
		instance._diag_seen[signature] = true
		instance._diag_remaining = instance._diag_remaining - 1
		pcall(deps.report, report)
	end

	local function finish(owner, ok, report)
		if owner ~= nil then instance._last_report_by_owner[owner] = report end
		report_once(report)
		return ok, report
	end

	local function extension(owner, name)
		if type(deps.get_extension) ~= "function" then return nil end
		local ok, value = pcall(deps.get_extension, owner, name)
		return ok and value or nil
	end

	function instance:enroll(owner, edge, context)
		context = context or {}
		local alive = deps.alive or function(unit) return unit ~= nil end
		local ok_owner, owner_live = pcall(alive, owner)
		if not ok_owner or not owner_live then
			return finish(owner, false,
				{ edge = edge, reason = "dead_owner", count = 0 })
		end

		context.inventory_extension = context.inventory_extension
			or extension(owner, "inventory_system")
		context.attachment_extension = context.attachment_extension
			or extension(owner, "attachment_system")
		local units = M.collect(context, alive)
		if #units == 0 then
			return finish(owner, false,
				{ edge = edge, reason = "no_linked_units", count = 0 })
		end

		-- `FadeSystem.new_linked_units` crosses directly into
		-- EngineOptimizedExtensions. Prove that this owner was registered with
		-- the fade system before crossing that native boundary; foreign/custom
		-- character units can legitimately have inventory-shaped extensions but
		-- no player fade extension.
		if not extension(owner, "fade_system") then
			return finish(owner, false, {
				edge = edge,
				reason = "owner_fade_extension_unavailable",
				count = #units,
			})
		end

		local current = fingerprint(units)
		if not context.force and self._last_by_owner[owner] == current then
			return finish(owner, true, {
				edge = edge,
				reason = "unchanged",
				count = #units,
				fingerprint = current,
			})
		end

		local fade_system
		if type(deps.get_fade_system) == "function" then
			local ok, value = pcall(deps.get_fade_system)
			if ok then fade_system = value end
		end
		if not fade_system or type(fade_system.new_linked_units) ~= "function" then
			return finish(owner, false,
				{ edge = edge, reason = "fade_system_unavailable", count = #units })
		end

		local ok, err = pcall(fade_system.new_linked_units,
			fade_system, owner, units)
		local report = {
			edge = edge,
			reason = ok and "applied" or "apply_failed",
			count = #units,
			fingerprint = current,
			error = ok and nil or tostring(err),
		}
		if ok then self._last_by_owner[owner] = current end
		return finish(owner, ok, report)
	end

	function instance:last_report(owner)
		return owner and self._last_report_by_owner[owner] or nil
	end

	return instance
end

M.INVENTORY_FIELDS = INVENTORY_FIELDS

return M
