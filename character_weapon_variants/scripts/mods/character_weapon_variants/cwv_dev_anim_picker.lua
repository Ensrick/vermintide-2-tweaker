-- Developer-facing 3P animation picker for CWV cross-character weapons.
-- CWV's variants share vanilla templates, so picks are resolved per receiver
-- before vanilla serializes the 3P event; shared template data is never mutated.

local mod = get_mod("character_weapon_variants")
local M = {}
local UNSET = "__cwv_anim_unset__"

local _SOURCE_EVENTS = {
	"attack_swing_heavy_right", "attack_swing_charge_diagonal",
	"attack_swing_charge_left", "attack_swing_down", "attack_swing_heavy",
	"attack_swing_heavy_left_diagonal", "attack_swing_charge_right",
	"attack_swing_right", "attack_swing_left_diagonal", "attack_push",
	"attack_swing_right_diagonal", "attack_swing_left",
}

-- Closed vocabularies from the receiver-native templates. Unit.has_animation_event
-- is deliberately not used because it can report state-machine stubs.
-- Values are the authored `anim_event` sets in dual_wield_axe_falchion.lua:122-1365
-- and dual_wield_hammer_sword.lua:19-1530 in the 2026-07-11 decompile.
local _VOCAB = {
	saltz_axe_falchion = {
		"attack_swing_heavy_down", "attack_swing_charge_down",
		"attack_swing_down", "attack_swing_heavy_left", "attack_push",
		"attack_swing_charge_left", "attack_swing_left_diagonal",
		"attack_swing_right", "attack_swing_right_diagonal",
		"attack_swing_down_left",
	},
	kruber_mace_sword = {
		"attack_swing_charge_right", "attack_swing_charge_left",
		"attack_swing_heavy_left_diagonal", "attack_swing_heavy_right_diagonal",
		"attack_swing_left_diagonal", "attack_swing_down", "attack_swing_left",
		"attack_swing_right", "attack_swing_right_diagonal", "attack_push",
	},
}

local _ENTRIES = {
	{ id = "saltz_dual_axes", label = "Saltzpyre: Dual Axes [Axe and Falchion]",
		item_key = "dr_dual_wield_axes", variant_key = "cwv_wh_dual_axes",
		career_prefix = "wh_", vocab = "saltz_axe_falchion" },
	{ id = "kruber_dual_axes", label = "Kruber: Dual Axes [Mace and Sword]",
		item_key = "dr_dual_wield_axes", variant_key = "cwv_es_dual_axes",
		career_prefix = "es_", vocab = "kruber_mace_sword" },
}

local _SOURCE_EVENT_SET = {}
for _, event in ipairs(_SOURCE_EVENTS) do _SOURCE_EVENT_SET[event] = true end

local _VOCAB_SETS = {}
for name, vocab in pairs(_VOCAB) do
	local set = {}
	for _, event in ipairs(vocab) do set[event] = true end
	_VOCAB_SETS[name] = set
end

local function _sid_group(entry)
	return "cwv_dev_anim_group_" .. entry.id
end

local function _sid_event(entry, source_event)
	return "cwv_dev_anim_" .. entry.id .. "_" .. source_event
end

local function _fresh_options(vocab)
	local options = { { text = "(use baked/default event)", value = UNSET } }
	for _, event in ipairs(vocab) do
		options[#options + 1] = { text = event, value = event }
	end
	return options
end

function M.build_widget_tree()
	local groups = {}
	for _, entry in ipairs(_ENTRIES) do
		local rows = {}
		for _, source_event in ipairs(_SOURCE_EVENTS) do
			rows[#rows + 1] = {
				setting_id = _sid_event(entry, source_event), type = "dropdown",
				default_value = UNSET, options = _fresh_options(_VOCAB[entry.vocab]),
				tooltip = "cwv_dev_anim_attack_tooltip",
			}
		end
		groups[#groups + 1] = {
			setting_id = _sid_group(entry), type = "group", sub_widgets = rows,
		}
	end
	return groups
end


function M.loc_keys()
	local keys = {
		cwv_dev_anim_attack_tooltip = { en = "Select a receiver-native third-person event for this source attack. The next attack uses it immediately and vanilla replicates the same event to observers." },
		["(use baked/default event)"] = { en = "(use baked/default event)" },
	}
	for _, vocab in pairs(_VOCAB) do
		for _, event in ipairs(vocab) do keys[event] = keys[event] or { en = event } end
	end
	for _, entry in ipairs(_ENTRIES) do
		keys[_sid_group(entry)] = { en = entry.label }
		for _, event in ipairs(_SOURCE_EVENTS) do
			keys[_sid_event(entry, event)] = { en = event }
		end
	end
	return keys
end

-- Returning nil preserves CWV's baked mapping or vanilla fall-through.
function M.resolve(item_key, career, source_event)
	if not mod:get("enable_cwv_dev_anim_picker")
		or type(career) ~= "string"
		or type(source_event) ~= "string"
		or not _SOURCE_EVENT_SET[source_event] then
		return nil
	end
	for _, entry in ipairs(_ENTRIES) do
		if (item_key == entry.item_key or item_key == entry.variant_key)
			and career:sub(1, 3) == entry.career_prefix then
			local value = mod:get(_sid_event(entry, source_event))
			-- user_settings.config is external input. Decline a stale or hand-edited
			-- value unless it belongs to the receiver template's closed vocabulary.
			if value ~= nil and value ~= UNSET and _VOCAB_SETS[entry.vocab][value] then
				return value
			end
			return nil
		end
	end
	return nil
end


function M.dump()
	mod:info("[cwv:317] ==== CWV 3P animation picker ====")
	for _, entry in ipairs(_ENTRIES) do
		mod:info("[cwv:317] %s", entry.label)
		for _, source_event in ipairs(_SOURCE_EVENTS) do
			local value = mod:get(_sid_event(entry, source_event))
			if value ~= nil and value ~= UNSET then
				mod:info("[cwv:317]   %s = %q,", source_event, value)
			end
		end
	end
	mod:info("[cwv:317] ==== end ====")
end


function M.regression_check()
	local seen = {}
	local seen_source = {}
	for _, source_event in ipairs(_SOURCE_EVENTS) do
		if seen_source[source_event] then return "duplicate source event: " .. source_event end
		seen_source[source_event] = true
	end
	for _, entry in ipairs(_ENTRIES) do
		local allowed = _VOCAB_SETS[entry.vocab] or {}
		if next(allowed) == nil then return "empty closed vocabulary: " .. entry.id end
		for _, source_event in ipairs(_SOURCE_EVENTS) do
			local sid = _sid_event(entry, source_event)
			if seen[sid] then return "duplicate setting id: " .. sid end
			seen[sid] = true
			local value = mod:get(sid)
			if value ~= nil and value ~= UNSET and not allowed[value] then
				return string.format("%s stores out-of-vocabulary event %s", sid, tostring(value))
			end
		end
	end
end


function M.install()
	mod:command("cwv_dump_anim_picks", "Dump saved CWV third-person animation picks", M.dump)
	mod:info("[cwv:317] 3P animation picker installed: %d receiver/weapon surfaces", #_ENTRIES)
end

return M
