-- #760: receiver-specific third-person presentation for the Outrider.
--
-- The weapon keeps its authored first-person launcher state machine. Only the
-- Saltzpyre body/preview stance changes; Kruber retains the blunderbuss stance.
local M = {}

M.ITEM_KEY = "cwv_es_outrider_grenade_launcher"
M.TEMPLATE_KEY = "outrider_grenade_launcher_template"
M.SALTZPYRE_WIELD_3P = "to_repeater_pistol"
M.EVIDENCE_LIMIT = 16
M.EVIDENCE_FIELD_LIMIT = 120
M.SALTZPYRE_CAREERS = {
	"wh_captain",
	"wh_bountyhunter",
	"wh_zealot",
}

local SALTZPYRE_CAREER_SET = {}
for _, career in ipairs(M.SALTZPYRE_CAREERS) do
	SALTZPYRE_CAREER_SET[career] = true
end

local evidence_count = 0
local evidence_seen = {}

local function bounded(value)
	local text = tostring(value)
	if #text > M.EVIDENCE_FIELD_LIMIT then
		return text:sub(1, M.EVIDENCE_FIELD_LIMIT)
	end
	return text
end

function M.runtime_event_available(anim_lookup)
	if type(anim_lookup) ~= "table" then return false end
	local id = anim_lookup[M.SALTZPYRE_WIELD_3P]
	return type(id) == "number" and anim_lookup[id] == M.SALTZPYRE_WIELD_3P
end

function M.apply_template(template, anim_lookup)
	if type(template) ~= "table" then return 0, "template_missing" end
	if not M.runtime_event_available(anim_lookup) then
		return 0, "network_event_unavailable"
	end
	if template.wield_anim_career_3p ~= nil
			and type(template.wield_anim_career_3p) ~= "table" then
		return 0, "career_map_invalid"
	end
	template.wield_anim_career_3p = template.wield_anim_career_3p or {}
	local applied = 0
	for _, career in ipairs(M.SALTZPYRE_CAREERS) do
		template.wield_anim_career_3p[career] = M.SALTZPYRE_WIELD_3P
		applied = applied + 1
	end
	return applied, nil
end

function M.preview_event(item_key, career)
	if item_key == M.ITEM_KEY and SALTZPYRE_CAREER_SET[career] then
		return M.SALTZPYRE_WIELD_3P
	end
	return nil
end

function M.runtime_event(item_key, career, anim_lookup)
	local event = M.preview_event(item_key, career)
	if not event then return nil, nil end
	if not M.runtime_event_available(anim_lookup) then
		return nil, "network_event_unavailable"
	end
	return event, nil
end

function M.husk_event(descriptor, career, anim_lookup)
	if type(descriptor) ~= "table" then return nil, nil end
	return M.runtime_event(descriptor.variant_key, career, anim_lookup)
end

function M.dispatch_event(unit, event, unit_api)
	if not unit or type(event) ~= "string" then
		return false, "dispatch_contract_missing"
	end
	local api_ok, alive_fn, event_fn = pcall(function()
		return unit_api and unit_api.alive,
			unit_api and unit_api.animation_event
	end)
	if not api_ok or type(alive_fn) ~= "function" or type(event_fn) ~= "function" then
		return false, "dispatch_contract_missing"
	end
	local alive_ok, alive = pcall(alive_fn, unit)
	if not alive_ok or alive ~= true then return false, "unit_not_alive" end
	local dispatch_ok = pcall(event_fn, unit, event)
	if not dispatch_ok then return false, "dispatch_error" end
	return true, "dispatched_unverified"
end

function M.emit_evidence(logger, surface, career, event, result, source)
	if type(logger) ~= "function" then return false end
	local fields = {
		bounded(surface), bounded(career), bounded(event), bounded(result), bounded(source),
	}
	local key = table.concat(fields, "\31")
	if evidence_seen[key] or evidence_count >= M.EVIDENCE_LIMIT then return false end
	evidence_seen[key] = true
	evidence_count = evidence_count + 1
	pcall(logger,
		"[cwv:760] surface=%s career=%s event=%s result=%s source=%s evidence=%d/%d visual=unverified",
		fields[1], fields[2], fields[3], fields[4], fields[5],
		evidence_count, M.EVIDENCE_LIMIT)
	return true
end

function M._reset_evidence_for_tests()
	evidence_count = 0
	evidence_seen = {}
end

function M.template_contract(template, anim_lookup)
	if type(template) ~= "table" then return false, "template missing" end
	if not M.runtime_event_available(anim_lookup) then
		return false, "network event unavailable"
	end
	if type(template.wield_anim_career_3p) ~= "table" then
		return false, "career map invalid"
	end
	for _, career in ipairs(M.SALTZPYRE_CAREERS) do
		if template.wield_anim_career_3p[career] ~= M.SALTZPYRE_WIELD_3P then
			return false, career .. " loaded stance missing"
		end
	end
	if template.wield_anim_career_3p.wh_priest == M.SALTZPYRE_WIELD_3P then
		return false, "wh_priest stance leaked"
	end
	for _, career in ipairs({ "es_mercenary", "es_huntsman", "es_knight", "es_questingknight" }) do
		if template.wield_anim_career_3p[career] == M.SALTZPYRE_WIELD_3P then
			return false, career .. " stance leaked"
		end
	end
	return true
end

return M
