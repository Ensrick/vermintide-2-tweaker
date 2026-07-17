-- Provider-neutral career-ability action integration for private/cross-career
-- weapon templates. Standalone-safe: no engine globals or mod state.
local M = {}

function M.collect(careers, career_settings, action_templates)
	local report = {
		ok = false,
		actions = {},
		names = {},
		missing_actions = {},
		missing_careers = {},
	}
	if type(careers) ~= "table" or type(career_settings) ~= "table"
			or type(action_templates) ~= "table" then
		report.skipped = "ability_tables_unavailable"
		return report
	end
	for _, career_name in ipairs(careers) do
		local career = career_settings[career_name]
		if type(career) ~= "table" then
			report.missing_careers[#report.missing_careers + 1] = career_name
		else
			for _, ability in ipairs(career.activated_ability or {}) do
				local action_name = type(ability) == "table" and ability.action_name
				if type(action_name) == "string" and report.actions[action_name] == nil then
					local action = action_templates[action_name]
					if type(action) ~= "table" then
						report.missing_actions[#report.missing_actions + 1] = action_name
					else
						report.actions[action_name] = action
						report.names[#report.names + 1] = action_name
					end
				end
			end
		end
	end
	report.ok = #report.missing_actions == 0 and #report.missing_careers == 0
	return report
end

function M.install(template, careers, career_settings, action_templates)
	local report = M.collect(careers, career_settings, action_templates)
	report.installed_names = {}
	report.existing_names = {}
	if type(template) ~= "table" or type(template.actions) ~= "table" then
		report.ok = false
		report.skipped = report.skipped or "weapon_template_unavailable"
		return report
	end
	for _, action_name in ipairs(report.names) do
		if template.actions[action_name] ~= nil then
			report.existing_names[#report.existing_names + 1] = action_name
		else
			template.actions[action_name] = report.actions[action_name]
			report.installed_names[#report.installed_names + 1] = action_name
		end
	end
	report.required = #report.names
	report.installed = #report.installed_names
	report.existing = #report.existing_names
	return report
end

return M
