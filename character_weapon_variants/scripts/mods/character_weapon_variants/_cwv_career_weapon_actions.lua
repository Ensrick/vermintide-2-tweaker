-- Provider-neutral career-action reconciliation for completed CWV item rows.
-- Engine-free: callers inject every registry and the shared integration.
local M = {}

function M.install(pending, item_master_list, weapons, career_settings,
		action_templates, integration, effective_templates, owner)
	local result = {
		ok = true,
		failures = {},
		template_count = 0,
		prepared_templates = 0,
		restored_actions = 0,
		discarded_inherited_claims = 0,
	}
	local seen = {}
	local prepared = {}
	for _, row in ipairs(pending or {}) do
		local key = row.def and row.def.item_key
		local entry = key and rawget(item_master_list or {}, key)
		local plan = effective_templates.plan(entry, row.def)
		local base_key = row.def and row.def.base_weapon
		local base_entry = base_key and rawget(item_master_list or {}, base_key)
		local default_source_key = base_entry and base_entry.template
		for _, descriptor in ipairs(plan.templates) do
			local template_key = descriptor.name
			local template = template_key and weapons and weapons[template_key]
			local source_key = descriptor.source_template or default_source_key
			local source = source_key and weapons and weapons[source_key]
			if template_key and not prepared[template_key] then
				prepared[template_key] = true
				if template and source and template ~= source then
					local clone_report = integration.prepare_inherited_clone(
						template, source, action_templates,
						tostring(template_key) .. "<-" .. tostring(source_key))
					if clone_report.ok then
						result.prepared_templates = result.prepared_templates + 1
						result.restored_actions = result.restored_actions
							+ (clone_report.restored or 0)
						result.discarded_inherited_claims =
							result.discarded_inherited_claims
							+ (clone_report.discarded_claims or 0)
					else
						result.failures["clone:" .. tostring(key) .. ":"
							.. tostring(clone_report.skipped or "prepare_failed")] = true
					end
				elseif template and source_key and not source then
					result.failures["clone:" .. tostring(key) .. ":"
						.. tostring(template_key) .. ":source_template_unavailable"] = true
				end
			end
			local report = integration.install(template, plan.careers,
				career_settings, action_templates, owner)
			if template_key and (report.claimed or 0) > 0 then seen[template_key] = true end
			for _, name in ipairs(report.missing_actions or {}) do
				result.failures["action:" .. tostring(name)] = true
			end
			for _, name in ipairs(report.missing_careers or {}) do
				result.failures["career:" .. tostring(name)] = true
			end
			for _, name in ipairs(report.conflicting_names or {}) do
				result.failures["conflict:" .. tostring(name)
					.. "@" .. tostring(template_key)] = true
			end
			if report.skipped then
				result.failures["provider:" .. tostring(key) .. ":"
					.. tostring(template_key) .. ":" .. tostring(report.skipped)] = true
			end
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
