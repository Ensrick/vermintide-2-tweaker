-- _cwv_outrider_projectile_wire.lua -- #1320 Outrider Grenade Launcher projectile wire.
--
-- The Outrider clone deep-copies its donor (dr_deus_01_template_1), so every
-- sub_action.lookup_data still names the DONOR template: vanilla stamps
-- lookup_data at boot (weapons.lua:308-315), before the clone exists. The fire
-- action forwards that name (action_grenade_thrower.lua:75), so
-- ProjectileSystem.spawn_player_projectile (projectile_system.lua:178-249)
-- resolves the DONOR's projectile_info and spawns the Trollhammer torpedo UNIT
-- instead of Projectiles.cwv_outrider_grenade_projectile, and the host encodes
-- the donor id for peers (game_object_initializers_extractors.lua:755).
--
-- This owner re-stamps the CLONE-private lookup_data rows to the clone name and
-- registers that name in NetworkLookup.item_template_names through the shared
-- #428 helper (idempotent, bidirectional, fail-closed). Registration happens at
-- one fixed mod-load site so the appended index is deterministic on every peer
-- running this build. FAIL-CLOSED: without a proven lookup row the re-stamp is
-- skipped entirely and the donor name keeps riding the wire (today's behavior)
-- rather than crashing the strict lookup __index on first fire. Action tables
-- the clone shares BY IDENTITY with vanilla ActionTemplates (action_inspect /
-- action_wield) are never written: weapons.lua stamps those shared tables
-- last-writer-wins for native weapons, so writing them would leak the clone
-- name onto vanilla items.
--
-- Owned by: character_weapon_variants.lua entry point, reached through
-- _cwv_item_identity_transport_owner (the item-identity wire owner; the entry
-- manifest is frozen at its decomposition ceiling). Consumed via one
-- mod:dofile + M.install call there. Pure planners stay engine-free for the
-- offline suite.
local M = {}

M.TEMPLATE_KEY = "outrider_grenade_launcher_template"
M.DONOR_TEMPLATE_KEY = "dr_deus_01_template_1"

-- Pure: collect the clone-private lookup_data tables eligible for the
-- re-stamp. `shared_actions` is an identity set of action tables that must
-- never be written (vanilla ActionTemplates references). Returns the rows plus
-- the count of skipped shared action tables.
function M.plan_restamp(template, shared_actions)
	local rows, skipped = {}, 0
	if type(template) ~= "table" or type(template.actions) ~= "table" then
		return rows, skipped
	end
	shared_actions = shared_actions or {}
	for _, sub_actions in pairs(template.actions) do
		if type(sub_actions) == "table" then
			if shared_actions[sub_actions] then
				skipped = skipped + 1
			else
				for _, sub_action in pairs(sub_actions) do
					if type(sub_action) == "table"
							and type(sub_action.lookup_data) == "table" then
						rows[#rows + 1] = sub_action.lookup_data
					end
				end
			end
		end
	end
	return rows, skipped
end

-- Pure: stamp item_template_name on every planned row. action_name /
-- sub_action_name are position-correct from the deep copies and stay untouched.
function M.apply_restamp(rows, template_key)
	local changed = 0
	for index = 1, #rows do
		if rows[index].item_template_name ~= template_key then
			rows[index].item_template_name = template_key
			changed = changed + 1
		end
	end
	return changed
end

-- Identity set of every vanilla ActionTemplates action table.
function M.shared_action_set(action_templates)
	local shared = {}
	if type(action_templates) == "table" then
		for _, action_table in pairs(action_templates) do
			if type(action_table) == "table" then shared[action_table] = true end
		end
	end
	return shared
end

function M.install(mod, ctx)
	ctx = ctx or {}
	local om = assert(ctx.om, "outrider projectile wire requires om")
	local network_lookup = assert(ctx.network_lookup,
		"outrider projectile wire requires the shared network_lookup helper")
	local emit = ctx.printf or function() end
	local state = { registered = false, reason = "not_attempted" }
	om.outrider_projectile_wire = state

	local weapons = rawget(_G, "Weapons")
	local template = type(weapons) == "table" and rawget(weapons, M.TEMPLATE_KEY) or nil
	if type(template) ~= "table" then
		-- Donor DLC absent: the clone was never built, so there is no wire to own.
		state.reason = "template_missing"
		return state
	end
	local index, _, reason = network_lookup.register_named(
		rawget(_G, "NetworkLookup"), "item_template_names", M.TEMPLATE_KEY)
	if not index then
		state.reason = "lookup:" .. tostring(reason)
		pcall(emit,
			"[cwv:1320] fail-closed: item_template_names %s; donor lookup_data retained",
			tostring(reason))
		return state
	end
	local rows, skipped = M.plan_restamp(template,
		M.shared_action_set(rawget(_G, "ActionTemplates")))
	local changed = M.apply_restamp(rows, M.TEMPLATE_KEY)
	state.registered = true
	state.reason = "registered"
	state.lookup_index = index
	state.rows = #rows
	state.restamped = changed
	state.shared_skipped = skipped
	pcall(emit,
		"[cwv:1320] outrider projectile wire: item_template_names id=%d rows=%d restamped=%d shared_skipped=%d",
		index, #rows, changed, skipped)
	return state
end

return M
