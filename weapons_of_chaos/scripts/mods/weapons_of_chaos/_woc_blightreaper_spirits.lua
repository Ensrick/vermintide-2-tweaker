-- Native Shyish death-spirit policy for Blightreaper (#632).
--
-- The runtime owner remains weapons_of_chaos.lua because it has the game-state
-- lifecycle and same-mod loadout identity sideband.  This module deliberately
-- contains only the bounded constants and pure eligibility/audio policy so the
-- dangerous network-unit boundary stays small and regression-testable.

local M = {}

-- Source: scripts/settings/mutators/mutator_death.lua:7-21, 31-115, 205-224.
M.UNIT = "units/fx/vfx_animation_death_spirit_02"
M.UNIT_TEMPLATE = "position_synched_dummy_unit"
-- Hash-verified installed bundle `64E79277358D543D` contains UNIT and is the
-- real DLC package declared by DLCSettings.mutators_batch_04. Unlike a unit
-- path, this is a valid PackageManager package name.
M.PACKAGE = "resource_packages/dlcs/mutators_batch_04"
M.PACKAGE_REFERENCE = "woc_blightreaper_spirits"
M.RELEASE_SOUND = "Play_winds_death_gameplay_spirit_release"
M.LOOP_SOUND = "Play_winds_death_gameplay_spirit_loop"
M.EXPLODE_SOUND = "Play_winds_death_gameplay_spirit_explode"
M.EXPLOSION = "death_spirit_bomb"
M.DAMAGE_TYPE = "death_explosion"
M.DAMAGE_SOURCE = "undefined"
M.HEAL_TYPE = "mutator"

-- Rank-one Shyish values from WindSettings.death.spirit_settings.  The weapon
-- is not a Weave and therefore has no wind strength to index; the bounded
-- rank-one values preserve the native behavior without consulting backend or
-- run progression state.
M.SPIRIT_DAMAGE = 5
M.CONVERT_AMOUNT = M.SPIRIT_DAMAGE
M.DELAY_TIME = 3
M.CHASE_SPEED = 1
M.CHASE_TIME = 6
M.HIT_DISTANCE = 1
M.SPAWN_OFFSET_Z = 1
M.MAX_ACTIVE = 32
M.POISON_ATTRIBUTION_TTL = 4

function M.package_contract(dlc_settings)
	local settings = type(dlc_settings) == "table"
		and dlc_settings.mutators_batch_04
	if type(settings) ~= "table" or settings.package_name ~= M.PACKAGE then
		return nil, "dlc_package_contract_missing"
	end
	return M.PACKAGE, "source_backed"
end

function M.package_ready(package_manager)
	if type(package_manager) ~= "table"
			or type(package_manager.has_loaded) ~= "function" then
		return false, "package_manager_missing"
	end
	local ok, loaded = pcall(package_manager.has_loaded, package_manager,
		M.PACKAGE, M.PACKAGE_REFERENCE)
	if not ok then return false, "package_query_rejected" end
	return loaded == true, loaded == true and "loaded" or "load_pending"
end

function M.kill_is_attributable(wielding_relic, damage_type,
		poison_owner_matches, poison_age)
	if wielding_relic then return true, "direct_or_wielded" end
	if damage_type ~= "arrow_poison_dot" or poison_owner_matches ~= true then
		return false, "not_blightreaper"
	end
	if type(poison_age) ~= "number" or poison_age < 0
		or poison_age > M.POISON_ATTRIBUTION_TTL then
		return false, "stale_poison"
	end
	return true, "hagbane_dot"
end

function M.audio_contract()
	return {
		release = M.RELEASE_SOUND,
		loop = M.LOOP_SOUND,
		explode = M.EXPLODE_SOUND,
	}
end

-- Exact mutator_death.lua contact amount: damage five when that is below total
-- health; otherwise damage permanent health minus one. The paired native
-- `mutator` heal turns the accepted damage into temporary health.
function M.contact_damage(current_permanent_health, current_temporary_health)
	if type(current_permanent_health) ~= "number"
			or type(current_temporary_health) ~= "number"
			or current_permanent_health <= 0 then return 0 end
	if M.SPIRIT_DAMAGE < current_permanent_health + current_temporary_health then
		return M.SPIRIT_DAMAGE
	end
	return math.max(current_permanent_health - 1, 0)
end

function M.convert_amount(current_permanent_health)
	return M.contact_damage(current_permanent_health, 0)
end

return M
