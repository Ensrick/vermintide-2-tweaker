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
M.RELEASE_SOUND = "Play_winds_death_gameplay_spirit_release"
M.LOOP_SOUND = "Play_winds_death_gameplay_spirit_loop"
M.EXPLODE_SOUND = "Play_winds_death_gameplay_spirit_explode"
M.EXPLOSION = "death_spirit_bomb"

-- Rank-one Shyish values from WindSettings.death.spirit_settings.  The weapon
-- is not a Weave and therefore has no wind strength to index; the bounded
-- rank-one values preserve the native behavior without consulting backend or
-- run progression state.
M.CONVERT_AMOUNT = 5
M.DELAY_TIME = 3
M.CHASE_SPEED = 1
M.CHASE_TIME = 6
M.HIT_DISTANCE = 1
M.SPAWN_OFFSET_Z = 1
M.MAX_ACTIVE = 32
M.POISON_ATTRIBUTION_TTL = 4

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

-- Native Shyish leaves one permanent health when the spirit reaches its
-- target (`mutator_death.lua:update_spirits`). PlayerUnitHealthExtension's
-- conversion API preserves total health, so clamp the requested conversion
-- to that same one-green-health floor before calling it.
function M.convert_amount(current_permanent_health)
	if type(current_permanent_health) ~= "number" then return 0 end
	return math.max(math.min(M.CONVERT_AMOUNT,
		current_permanent_health - 1), 0)
end

return M
