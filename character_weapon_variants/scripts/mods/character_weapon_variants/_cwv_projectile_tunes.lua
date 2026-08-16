-- _cwv_projectile_tunes.lua
-- Pure decision: which weapon template owns a CWV variant's FIRED projectile (#1186).
--
-- THE GAP THIS EXISTS FOR. A projectile re-derives its own action data from the
-- item master list, not from the weapon that fired it:
--
--   local item_data = ItemMasterList[item_name]                    -- base key
--   local item_template = BackendUtils.get_item_template(item_data)
--   local current_action = item_template.actions[action_name][sub_action_name]
--   (player_projectile_unit_extension.lua:56-69)
--
-- `item_name` is the BASE weapon key, because a CWV clone inherits `entry.name`
-- from the item it was cloned off (memory `feedback_cwv_clone_name_clobber`).
-- The wielded-weapon side is fine - `WeaponUnitExtension` resolves its actions
-- from the equipped item's template, so a variant that authored a template gets
-- its own launch action - but everything the PROJECTILE reads about itself
-- (impact_data, its damage profile, projectile_info, timed_data, charge_data)
-- comes from the donor. A variant whose clone lives under a DIFFERENT template
-- name is therefore unreachable on that path and silently flies with donor
-- values: the Outrider Grenade Launcher's 0.65x damage clone never applied
-- (#1186), exactly the class the Tuskgor Javelin hit at v0.1.98.
--
-- A variant whose clone reuses the base's template NAME is not affected: the
-- base lookup finds the clone because the clone IS the registered entry under
-- that name. Only a RENAME is invisible, so that is the whole admission rule
-- here - derived from the authored catalog, never a hand-maintained key list, so
-- a future renamed-template variant is covered the day it is authored.
--
-- Owned by: character_weapon_variants.lua entry point, reached through
-- _cwv_javelin_runtime_owner (which owns the mod's single
-- PlayerProjectileUnitExtension.init registration - VMF silently DROPS a second
-- hook on one (Class, method) pair, so the arm has to live behind that one).
-- Engine-free by construction: no globals, no hooks, no side effects, so the
-- offline Lua suite can drive the whole contract.
local M = {}

-- Every def whose authored template is a RENAME of its base's template, keyed by
-- variant item_key -> clone template name.
--
-- `base_template_of(base_weapon)` yields the base item's template name; in
-- production that is `ItemMasterList[base].template`. A def with no template, an
-- unknown base, or a template that matches its base's is deliberately absent -
-- those resolve correctly through the vanilla base lookup already.
function M.renamed_template_defs(definitions, base_template_of)
	local overrides = {}
	if type(definitions) ~= "table" or type(base_template_of) ~= "function" then
		return overrides
	end
	for _, def in ipairs(definitions) do
		local key = type(def) == "table" and def.item_key or nil
		local template = type(def) == "table" and def.template or nil
		local base = type(def) == "table" and def.base_weapon or nil
		if type(key) == "string" and type(template) == "string"
				and type(base) == "string" then
			local base_template = base_template_of(base)
			if type(base_template) == "string" and base_template ~= template then
				overrides[key] = template
			end
		end
	end
	return overrides
end

-- Resolve the clone sub-action a projectile should have read.
--
-- Returns `(action, template_name)` on a hit and `(nil, reason)` otherwise.
-- Decline reasons: "not_cwv" (no variant owns the firing slot) | "no_rename"
-- (the variant's template is reachable from the base already) | "base_mismatch"
-- (this projectile did not come from that variant's donor - never re-point a
-- foreign weapon's projectile) | "template_missing" | "action_missing" (the
-- clone does not author this action pair; keep vanilla rather than guess) |
-- "already_clone" (idempotent: the engine already resolved our table).
function M.resolve(args)
	args = args or {}
	local key = args.variant_key
	if type(key) ~= "string" or key == "" then return nil, "not_cwv" end
	local overrides = args.overrides
	local template_name = type(overrides) == "table" and overrides[key] or nil
	if type(template_name) ~= "string" then return nil, "no_rename" end
	if type(args.item_name) ~= "string" or args.item_name ~= args.variant_base then
		return nil, "base_mismatch"
	end
	local weapons = args.weapons
	local template = type(weapons) == "table" and rawget(weapons, template_name) or nil
	if type(template) ~= "table" or type(template.actions) ~= "table" then
		return nil, "template_missing"
	end
	local lookup = args.lookup
	local action_name = type(lookup) == "table" and lookup.action_name or nil
	local sub_action_name = type(lookup) == "table" and lookup.sub_action_name or nil
	local group = type(action_name) == "string" and template.actions[action_name] or nil
	local action = type(group) == "table" and type(sub_action_name) == "string"
		and group[sub_action_name] or nil
	if type(action) ~= "table" then return nil, "action_missing" end
	if action == args.base_action then return nil, "already_clone" end
	return action, template_name
end

-- The field transfer, expressed against a plain table so it is testable without
-- a live extension. Mirrors the assignments vanilla `init` made from the DONOR
-- action (player_projectile_unit_extension.lua:69-99) so the projectile reads
-- the variant's authored values for the rest of its lifecycle.
--
-- `damage_profile_id(name)` maps a profile name to its NetworkLookup id;
-- production passes a rawget over `NetworkLookup.damage_profiles`, where the
-- variant's cloned profile is registered by `_clone_damage_profile`. A nil answer
-- KEEPS the donor id rather than writing nil - an unresolvable id on
-- `rpc_attack_hit` is the #423 class, and the sender-side wire policy
-- (_cwv_damage_profile_wire) is what substitutes a donor id for an unconfirmed
-- peer.
--
-- Returns the number of fields changed, so a caller can log a bounded receipt
-- and a test can prove the transfer was not a no-op.
function M.apply(projectile, action, damage_profile_id)
	if type(projectile) ~= "table" or type(action) ~= "table" then return 0 end
	local changed = 0
	local function set(field, value)
		if value ~= nil and projectile[field] ~= value then
			projectile[field] = value
			changed = changed + 1
		end
	end
	set("_current_action", action)
	set("charge_data", action.charge_data)
	set("chain_hit_settings", action.chain_hit_settings)
	set("projectile_info", action.projectile_info)
	local resolve_id = type(damage_profile_id) == "function" and damage_profile_id
		or function() return nil end
	local impact = action.impact_data
	if type(impact) == "table" then
		set("_impact_data", impact)
		set("_impact_damage_profile_id", resolve_id(impact.damage_profile or "default"))
	end
	local timed = action.timed_data
	if type(timed) == "table" then
		set("_timed_data", timed)
		set("_timed_damage_profile_id", resolve_id(timed.damage_profile or "default"))
	end
	return changed
end

return M
