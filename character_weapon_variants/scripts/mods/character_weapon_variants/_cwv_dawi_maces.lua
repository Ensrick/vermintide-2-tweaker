-- Issue #602: pure registration policy for the Dawi Mace family.
--
-- Gameplay is intentionally decoupled from the pending custom-asset review.
-- These resident vanilla placeholders are safe for public Workshop builds;
-- the BY-NC Tower Mace and the unprovenanced UUID model are not referenced.
local M = {}

M.ALL_CAREERS = {
	"es_mercenary", "es_huntsman", "es_knight", "es_questingknight",
	"dr_ranger", "dr_ironbreaker", "dr_slayer", "dr_engineer",
	"we_waywatcher", "we_maidenguard", "we_shade", "we_thornsister",
	"wh_captain", "wh_bountyhunter", "wh_zealot", "wh_priest",
	"bw_adept", "bw_scholar", "bw_unchained", "bw_necromancer",
}

M.NATIVE_ONE_HANDED = { "dr_ranger", "dr_ironbreaker", "dr_slayer" }
M.NATIVE_SHIELD = { "dr_ranger", "dr_ironbreaker" }

M.PLACEHOLDER_MACE = "units/weapons/player/wpn_dw_hammer_01_t1/wpn_dw_hammer_01_t1"
M.PLACEHOLDER_SHIELD = "units/weapons/player/wpn_dw_shield_01_t1/wpn_dw_shield_01"

M.VARIANTS = {
	{
		key = "cwv_dr_dawi_mace",
		base_weapon = "es_1h_mace",
		template = "one_handed_hammer_template_1",
		default_careers = M.NATIVE_ONE_HANDED,
	},
	{
		key = "cwv_dr_dawi_mace_shield",
		base_weapon = "es_mace_shield",
		template = "one_handed_hammer_shield_template_1",
		default_careers = M.NATIVE_SHIELD,
	},
	{
		key = "cwv_dr_dawi_dual_maces",
		base_weapon = "dr_dual_wield_hammers",
		template = "cwv_dual_maces_template",
		default_careers = M.NATIVE_ONE_HANDED,
	},
}

function M.default_career_set(defaults)
	local result = {}
	for _, career in ipairs(defaults or {}) do result[career] = true end
	return result
end

function M.conditional_careers(defaults)
	local native = M.default_career_set(defaults)
	local result = {}
	for _, career in ipairs(M.ALL_CAREERS) do
		if not native[career] then result[#result + 1] = career end
	end
	return result
end

return M
