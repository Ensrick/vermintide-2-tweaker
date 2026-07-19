local M = {}

-- A pistol-less Rapier must not retain any of the base fencing sword's
-- ammunition contract. The stock HUD treats ammo_data as authoritative and
-- asks ammo_hand for an ammo_system extension; CWV deliberately does not spawn
-- that hand for this variant.
function M.disable_pistol(template, never)
	if type(template) ~= "table" then
		return false
	end

	local action_three = template.actions and template.actions.action_three
	if type(action_three) == "table" then
		for _, sub_action in pairs(action_three) do
			if type(sub_action) == "table" then
				sub_action.condition_func = never
				sub_action.chain_condition_func = never
			end
		end
	end

	template.ammo_data = nil

	return true
end

return M
