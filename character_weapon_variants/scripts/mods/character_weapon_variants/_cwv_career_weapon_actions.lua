-- Provider-neutral career-action reconciliation for completed CWV item rows.
-- Engine-free: callers inject every registry and the shared integration.
local M = {}

function M.install(pending, item_master_list, weapons, career_settings,
		action_templates, integration, owner)
	local result = { ok = true, failures = {}, template_count = 0 }
	local seen = {}
	for _, row in ipairs(pending or {}) do
		local key = row.def and row.def.item_key
		local entry = key and rawget(item_master_list or {}, key)
		local template_key = entry and entry.template
		local template = template_key and weapons and weapons[template_key]
		local report = integration.install(template, entry and entry.can_wield,
			career_settings, action_templates, owner)
		if template_key and (report.claimed or 0) > 0 then seen[template_key] = true end
		for _, name in ipairs(report.missing_actions or {}) do
			result.failures["action:" .. tostring(name)] = true
		end
		for _, name in ipairs(report.missing_careers or {}) do
			result.failures["career:" .. tostring(name)] = true
		end
		for _, name in ipairs(report.conflicting_names or {}) do
			result.failures["conflict:" .. tostring(name)] = true
		end
		if report.skipped then
			result.failures["provider:" .. tostring(key) .. ":"
				.. tostring(report.skipped)] = true
		end
	end
	for _ in pairs(seen) do result.template_count = result.template_count + 1 end
	if next(result.failures) then
		result.ok = false
		for name in pairs(result.failures) do result[#result + 1] = name end
		table.sort(result)
	end
	return result
end

return M
