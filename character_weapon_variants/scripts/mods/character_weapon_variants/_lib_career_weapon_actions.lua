-- Provider-neutral career-ability action integration for private/cross-career
-- weapon templates. Standalone-safe: no engine globals or mod state.
local M = {}

-- The registry lives on the shared weapon template so separately bundled
-- copies of this library still coordinate.  Keep it off `template.actions`:
-- the engine treats every key in that table as an executable action row.
local CLAIMS_KEY = "__vt2_tweaker_career_action_claims"

local function claims_for(template)
	local claims = rawget(template, CLAIMS_KEY)
	if type(claims) ~= "table" then
		claims = {}
		rawset(template, CLAIMS_KEY, claims)
	end
	return claims
end

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

function M.install(template, careers, career_settings, action_templates, owner)
	local report = M.collect(careers, career_settings, action_templates)
	report.installed_names = {}
	report.existing_names = {}
	report.claimed_names = {}
	report.conflicting_names = {}
	if type(template) ~= "table" or type(template.actions) ~= "table" then
		report.ok = false
		report.skipped = report.skipped or "weapon_template_unavailable"
		return report
	end
	local claims = type(owner) == "string" and claims_for(template) or nil
	for _, action_name in ipairs(report.names) do
		local action = report.actions[action_name]
		local existing = template.actions[action_name]
		if existing ~= nil then
			report.existing_names[#report.existing_names + 1] = action_name
			if existing ~= action then
				report.conflicting_names[#report.conflicting_names + 1] = action_name
			else
				local claim = claims and claims[action_name]
				if claims and not claim then
					claim = {
						baseline_present = true,
						value = action,
						owners = {},
					}
					claims[action_name] = claim
				end
				if claim then
					claim.owners[owner] = true
					report.claimed_names[#report.claimed_names + 1] = action_name
				end
			end
		else
			template.actions[action_name] = action
			report.installed_names[#report.installed_names + 1] = action_name
			if claims then
				claims[action_name] = claims[action_name] or {
					baseline_present = false,
					value = action,
					owners = {},
				}
				claims[action_name].owners[owner] = true
				report.claimed_names[#report.claimed_names + 1] = action_name
			end
		end
	end
	report.required = #report.names
	report.installed = #report.installed_names
	report.existing = #report.existing_names
	report.claimed = #report.claimed_names
	if #report.conflicting_names > 0 then report.ok = false end
	return report
end

-- Release only this provider's claims.  An injected row is removed only when
-- no provider still claims it and nobody has replaced it since installation.
-- Native/pre-existing rows are never removed.
function M.release(template, owner)
	local report = { removed_names = {}, retained_names = {}, changed_names = {} }
	if type(template) ~= "table" or type(template.actions) ~= "table"
			or type(owner) ~= "string" then
		report.skipped = "weapon_template_or_owner_unavailable"
		return report
	end
	local claims = rawget(template, CLAIMS_KEY)
	if type(claims) ~= "table" then return report end
	for action_name, claim in pairs(claims) do
		if type(claim) == "table" and type(claim.owners) == "table"
				and claim.owners[owner] then
			claim.owners[owner] = nil
			if next(claim.owners) then
				report.retained_names[#report.retained_names + 1] = action_name
			else
				if claim.baseline_present ~= true then
					if template.actions[action_name] == claim.value then
						template.actions[action_name] = nil
						report.removed_names[#report.removed_names + 1] = action_name
					else
						report.changed_names[#report.changed_names + 1] = action_name
					end
				end
				claims[action_name] = nil
			end
		end
	end
	if next(claims) == nil then rawset(template, CLAIMS_KEY, nil) end
	table.sort(report.removed_names)
	table.sort(report.retained_names)
	table.sort(report.changed_names)
	return report
end

return M
