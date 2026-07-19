-- Provider-neutral planner for weapon families whose effective template can
-- differ from ItemMasterList[item_key].template at runtime (stance/style
-- switches are the common case). Standalone-safe: no engine globals/mod state.
local M = {}

local function add_template(result, seen, descriptor)
	local name
	local source_template
	if type(descriptor) == "string" then
		name = descriptor
	elseif type(descriptor) == "table" then
		name = descriptor.name or descriptor.template
		source_template = descriptor.source_template
	end
	if type(name) ~= "string" or name == "" or seen[name] then return end
	seen[name] = true
	result[#result + 1] = {
		name = name,
		source_template = source_template,
	}
end

-- Explicit effective templates come first so their donor provenance wins when
-- the primary ItemMasterList template is also listed. The primary is always a
-- fallback, keeping ordinary one-template weapons zero-configuration.
function M.templates(item, definition)
	local result = {}
	local seen = {}
	for _, descriptor in ipairs(
		(type(definition) == "table" and definition.effective_templates) or {}) do
		add_template(result, seen, descriptor)
	end
	add_template(result, seen, type(item) == "table" and item.template)
	return result
end

-- Runtime can_wield is authoritative. Catalog declarations describe the menu
-- surface, but other providers and late settings reconciliation can make the
-- live set differ; career actions must follow the live item contract.
function M.careers(item)
	local result = {}
	local seen = {}
	for _, career in ipairs((type(item) == "table" and item.can_wield) or {}) do
		if type(career) == "string" and career ~= "" and not seen[career] then
			seen[career] = true
			result[#result + 1] = career
		end
	end
	return result
end

function M.plan(item, definition)
	return {
		templates = M.templates(item, definition),
		careers = M.careers(item),
	}
end

return M
