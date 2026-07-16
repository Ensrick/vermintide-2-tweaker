-- Per-instance Combat Style policy and runtime owner (issue #620).
--
-- A style is an immutable package of template, balance, presentation, and
-- receiver-animation metadata. The persisted value is only the stable style id
-- keyed by exact backend item id. Runtime transitions rebuild the equipped slot
-- once; peers receive one bounded family/style edge and never a template table.
local M = {}

M.SETTING_KEY = "cwv_combat_style_state"
M.CHANNEL = "cwv_combat_style_v1"
M.SCHEMA = 1
M.MAX_TOKEN = 96
M.INPUT_DESCRIPTION_CAPACITY = 7
M.KERILLIAN_TEMPLATE = "cwv_combat_style_kerillian_greatsword"
M.EMPIRE_SPEAR_SHIELD_TEMPLATE = "cwv_combat_style_empire_spear_shield"
M.ELVEN_SPEAR_SHIELD_TEMPLATE = "cwv_combat_style_elven_spear_shield"
M.DIAGNOSTIC_EVENT_CAP = 32
M.IMPERIAL_SPEED_MULT = 1.15
M.IMPERIAL_DAMAGE_MULT = 0.85
M.IMPERIAL_STAGGER_MULT = 0.85
M.IMPERIAL_CLEAVE_MULT = 1.15
M.KERILLIAN_SPEED_MULT = 0.85
M.KERILLIAN_STAGGER_MULT = 1.15
M.KERILLIAN_CLEAVE_MULT = 1.15
M.CONSOLE_STYLE_BUTTON = {
	icon = "icon_switch",
	icon_size = { 42, 38 },
	hitbox_size = { 50, 45 },
	cog_shift_y = -27,
	style_shift_y = 35,
}

-- A remap key names one bounded, source-audited event translation. Styles
-- reference these keys from their per-member receiver descriptors; the cycle
-- controller never guesses from character prefixes or template names.
M.REMAPS = {
	spear_shield_to_deus = {
		events = { attack_swing_stab_lh = "attack_swing_stab" },
	},
	deus_to_spear_shield = {
		events = { attack_swing_up = "attack_swing_stab_lh" },
	},
}

-- These families are deliberately not members of FAMILIES. They are the
-- bounded diagnostic allow-list for #645: owner-side 3P action events can be
-- captured without exposing a partial style, changing a template, or putting
-- an unverified resource on PackageManager's asynchronous queue.
M.DIAGNOSTIC_CANDIDATES = {
	one_handed_axes = {
		members = { dr_1h_axe = true, wh_1h_axe = true, we_1h_axe = true },
		reason = "receiver remaps and transforms unproven",
	},
	glaive_great_axe = {
		members = { we_2h_axe = true, dr_2h_axe = true },
		reason = "different resources; reciprocal remaps unproven",
	},
	one_handed_swords = {
		members = { es_1h_sword = true, we_1h_sword = true },
		reason = "Empire and Elven action graphs need reciprocal remap evidence",
	},
	elf_tuskgor_spears = {
		members = { we_spear = true, es_2h_heavy_spear = true },
		reason = "spear and polearm resources need reciprocal remap evidence",
	},
}

-- HeroWindowLoadoutConsole constructs MenuInputDescriptionUI with exactly
-- seven widgets. A style-capable customizable row already has seven vanilla
-- generic actions, so appending `special_1` produces an eighth action and
-- crashes set_input_description when it indexes a nonexistent widget. Keep the
-- list bounded and replace the nonessential inventory-layout hint when full;
-- the underlying show_gamercard input remains handled by vanilla.
function M.bounded_style_actions(source, capacity)
	capacity = math.max(0, math.floor(tonumber(capacity) or 0))
	local list = {}
	for index, action in ipairs(type(source) == "table" and source or {}) do
		if index <= capacity then list[index] = action end
	end
	if capacity == 0 then return list, "empty" end
	for _, action in ipairs(list) do
		if action.input_action == "special_1" then return list, "existing" end
	end
	local style_action = {
		description_text = "cwv_cycle_combat_style_controller",
		input_action = "special_1",
	}
	if #list < capacity then
		style_action.priority = #list + 1
		list[#list + 1] = style_action
		return list, "appended"
	end
	local replace_index = capacity
	for index, action in ipairs(list) do
		if action.input_action == "show_gamercard" then
			replace_index = index
			break
		end
	end
	style_action.priority = list[replace_index] and list[replace_index].priority or replace_index
	list[replace_index] = style_action
	return list, "replaced"
end

M.FAMILIES = {
	greatsword = {
		styles = {
			greatsword = { label = "Greatsword Combat Style", template = "two_handed_swords_template_1",
				resource = "units/beings/player/first_person_base/state_machines/melee/2h_sword" },
			longsword = { label = "Longsword Combat Style", template = "imperial_longsword_template",
				presentation = { transform_key = "imperial_longsword" },
				resource = "units/beings/player/first_person_base/state_machines/melee/2h_sword" },
			bretonnian = { label = "Bretonnian Combat Style", template = "bastard_sword_template",
				resource = "units/beings/player/first_person_base/state_machines/melee/bastard_sword" },
			kerillian = {
				label = "Kerillian Greatsword Combat Style",
				template = M.KERILLIAN_TEMPLATE,
				resource = "units/beings/player/first_person_base/state_machines/melee/2h_sword_we",
				modifiers = { attack_speed = M.KERILLIAN_SPEED_MULT, stagger = M.KERILLIAN_STAGGER_MULT, cleave = M.KERILLIAN_CLEAVE_MULT },
			},
		},
		members = {
			es_2h_sword = { default = "greatsword", order = { "greatsword", "longsword", "bretonnian", "kerillian" } },
			es_bastard_sword = { default = "bretonnian", order = { "bretonnian", "kerillian", "greatsword", "longsword" } },
			cwv_es_longsword = { default = "longsword", order = { "longsword", "bretonnian", "kerillian", "greatsword" } },
			cwv_es_longsword_blackguard = { default = "longsword", order = { "longsword", "bretonnian", "kerillian", "greatsword" } },
		},
	},
	greathammer = {
		styles = {
			kruber = { label = "Kruber Greathammer Combat Style", template = "two_handed_hammers_template_1",
				resource = "units/beings/player/first_person_base/state_machines/melee/2h_hammer" },
			warrior_priest = { label = "Warrior Priest Greathammer Combat Style", template = "two_handed_hammer_priest_template",
				resource = "units/beings/player/first_person_base/state_machines/melee/2h_hammer_priest" },
		},
		members = {
			es_2h_hammer = { default = "kruber", order = { "kruber", "warrior_priest" } },
			wh_2h_hammer = { default = "warrior_priest", order = { "warrior_priest", "kruber" } },
			cwv_es_priest_greathammer = { default = "warrior_priest", order = { "warrior_priest", "kruber" } },
		},
	},
	spear = {
		styles = {
			hunter = { label = "Hunter Combat Style", template = "two_handed_heavy_spears_template",
				resource = "units/beings/player/first_person_base/state_machines/melee/polearm" },
			infantry = {
				label = "Infantry Combat Style",
				template = "cwv_infantry_spear_template",
				resource = "units/beings/player/first_person_base/state_machines/melee/spear",
			},
		},
		members = {
			es_2h_heavy_spear = { default = "hunter", order = { "hunter", "infantry" } },
		},
	},
	spear_shield = {
		styles = {
			empire = {
				label = "Kruber Spear and Shield Combat Style",
				template = M.EMPIRE_SPEAR_SHIELD_TEMPLATE,
				resource = "units/beings/player/first_person_base/state_machines/melee/es_deus_01",
				required_dlc = "grass",
				receivers = {
					we_1h_spears_shield = { remap_key = "deus_to_spear_shield" },
				},
			},
			elven = {
				label = "Elven Spear and Shield Combat Style",
				template = M.ELVEN_SPEAR_SHIELD_TEMPLATE,
				resource = "units/beings/player/first_person_base/state_machines/melee/1h_spear_shield",
				required_dlc = "scorpion",
				receivers = {
					es_deus_01 = { remap_key = "spear_shield_to_deus" },
				},
			},
		},
		members = {
			es_deus_01 = { default = "empire", order = { "empire", "elven" } },
			we_1h_spears_shield = { default = "elven", order = { "elven", "empire" } },
		},
	},
}

-- Canonical, lossless retirement map. These rows remain registered only as
-- restore bridges; CIM must never offer them as new craft choices. Planning is
-- deliberately pure so every target/illusion can be validated before the
-- caller mutates one persisted record.
M.LEGACY_MIGRATIONS = {
	cwv_es_infantry_spear = {
		target_item = "es_2h_heavy_spear", style_id = "infantry",
		default_skin = "cwv_tuskgor_spear_01",
		map_skin = function(skin)
			if type(skin) ~= "string" then return skin end
			if skin == "cwv_es_infantry_spear_skin" then return "cwv_tuskgor_spear_01" end
			return skin:gsub("^cwv_es_infantry_spear_", "cwv_tuskgor_spear_")
		end,
	},
	cwv_es_longsword = {
		target_item = "es_2h_sword", style_id = "longsword",
		default_skin = "cwv_es_longsword_skin",
	},
	cwv_es_longsword_blackguard = {
		target_item = "es_2h_sword", style_id = "longsword",
		default_skin = "cwv_es_longsword_blackguard_skin",
	},
}

local function valid_token(value)
	return type(value) == "string" and #value > 0 and #value <= M.MAX_TOKEN
		and value:match("^[%w_:%-%.]+$") ~= nil
end

function M.plan_legacy_migrations(saved, target_exists, skin_exists)
	if type(saved) ~= "table" then return {}, nil end
	local patches = {}
	for identity, persisted in pairs(saved) do
		local spec = type(persisted) == "table" and M.LEGACY_MIGRATIONS[persisted.item_key]
		if spec then
			if not valid_token(identity) then return nil, "invalid legacy identity" end
			if type(target_exists) == "function" and not target_exists(spec.target_item) then
				return nil, "missing migration target " .. spec.target_item
			end
			local skin = persisted.skin or spec.default_skin
			if spec.map_skin then skin = spec.map_skin(skin) end
			if skin and type(skin_exists) == "function" and not skin_exists(skin, spec.target_item) then
				return nil, "missing migration skin " .. tostring(skin)
			end
			patches[#patches + 1] = {
				identity = identity, source_item = persisted.item_key,
				target_item = spec.target_item, style_id = spec.style_id,
				old_skin = persisted.skin, skin = skin,
			}
		end
	end
	table.sort(patches, function(a, b) return a.identity < b.identity end)
	return patches, nil
end

function M.member(item_key)
	if type(item_key) ~= "string" then return nil end
	for family_id, family in pairs(M.FAMILIES) do
		local member = family.members[item_key]
		if member then return family_id, family, member end
	end
	return nil
end

function M.style(item_key, stored_style)
	local family_id, family, member = M.member(item_key)
	if not family_id then return nil end
	local style_id = family.styles[stored_style] and stored_style or member.default
	return style_id, family.styles[style_id], family_id, member
end

-- Resolve one immutable catalogue style for a concrete family member. A
-- receiver override may select a remap key, but cannot replace arbitrary
-- fields or introduce a resource outside the authored style row.
function M.package(item_key, stored_style)
	local style_id, style, family_id, member = M.style(item_key, stored_style)
	if not style_id then return nil end
	local receiver = type(style.receivers) == "table" and style.receivers[item_key] or nil
	return {
		style_id = style_id,
		family_id = family_id,
		member = member,
		style = style,
		template = style.template,
		resource = style.resource,
		required_dlc = style.required_dlc,
		presentation = style.presentation,
		remap_key = receiver and receiver.remap_key or style.remap_key,
	}
end

function M.style_available(style, owns_dlc)
	if type(style) ~= "table" then return false end
	if not style.required_dlc then return true end
	return type(owns_dlc) == "function" and owns_dlc(style.required_dlc) == true
end

function M.next_style(item_key, current, owns_dlc)
	local style_id, _, family_id, member = M.style(item_key, current)
	if not style_id then return nil end
	for index, candidate in ipairs(member.order) do
		if candidate == style_id then
			for offset = 1, #member.order do
				local next_id = member.order[(index - 1 + offset) % #member.order + 1]
				local next_row = M.FAMILIES[family_id].styles[next_id]
				if M.style_available(next_row, owns_dlc) then
					return next_id, next_row, family_id
				end
			end
			return style_id, M.FAMILIES[family_id].styles[style_id], family_id
		end
	end
	for _, candidate in ipairs(member.order) do
		local row = M.FAMILIES[family_id].styles[candidate]
		if M.style_available(row, owns_dlc) then return candidate, row, family_id end
	end
	return nil
end

function M.remap_event(item_key, stored_style, career, source_event)
	if type(career) ~= "string" or type(source_event) ~= "string" then return nil end
	local package = M.package(item_key, stored_style)
	local remap = package and package.remap_key and M.REMAPS[package.remap_key]
	return remap and remap.events and remap.events[source_event] or nil
end

function M.diagnostic_candidate(item_key)
	if type(item_key) ~= "string" then return nil end
	for candidate_id, candidate in pairs(M.DIAGNOSTIC_CANDIDATES) do
		if candidate.members[item_key] then return candidate_id, candidate end
	end
	return nil
end

-- Static catalogue validation is intentionally stricter than runtime use. A
-- malformed descriptor fails QA instead of becoming a partially visible UI
-- choice whose resource or animation behavior is missing.
function M.validate_catalogue()
	for family_id, family in pairs(M.FAMILIES) do
		if type(family.styles) ~= "table" or type(family.members) ~= "table" then
			return false, "invalid family " .. tostring(family_id)
		end
		for style_id, style in pairs(family.styles) do
			if not valid_token(style_id) or type(style.label) ~= "string"
					or not valid_token(style.template) or type(style.resource) ~= "string" then
				return false, "incomplete style " .. tostring(family_id) .. ":" .. tostring(style_id)
			end
			if style.presentation and not valid_token(style.presentation.transform_key) then
				return false, "invalid presentation " .. tostring(family_id) .. ":" .. tostring(style_id)
			end
			for member_key, receiver in pairs(style.receivers or {}) do
				if not family.members[member_key] or not M.REMAPS[receiver.remap_key] then
					return false, "invalid receiver remap " .. tostring(family_id) .. ":" .. tostring(style_id)
				end
			end
		end
		for member_key, member in pairs(family.members) do
			if not family.styles[member.default] or type(member.order) ~= "table" or #member.order < 2 then
				return false, "invalid member " .. tostring(member_key)
			end
			local seen = {}
			for _, style_id in ipairs(member.order) do
				if seen[style_id] or not family.styles[style_id] then
					return false, "invalid order " .. tostring(member_key)
				end
				seen[style_id] = true
			end
		end
	end
	return true
end

local function copy_triplet(value)
	return { value[1] or 0, value[2] or 0, value[3] or 0 }
end

local function copy_pair(value)
	return { value[1] or 0, value[2] or 0 }
end

-- Layout is always relative to the native cog. Unsupported rows are restored
-- byte-for-byte to that authored offset. On an eligible row the style control
-- sits above the cog and the cog moves down; neither control shifts sideways.
function M.console_style_layout(cog_offset)
	if type(cog_offset) ~= "table" then return nil end
	local original = copy_triplet(cog_offset)
	local cog = copy_triplet(cog_offset)
	cog[2] = cog[2] + M.CONSOLE_STYLE_BUTTON.cog_shift_y
	local style_hitbox = copy_triplet(cog_offset)
	style_hitbox[1] = style_hitbox[1] + math.floor((58 - M.CONSOLE_STYLE_BUTTON.hitbox_size[1]) * 0.5)
	style_hitbox[2] = style_hitbox[2] + M.CONSOLE_STYLE_BUTTON.style_shift_y
	local icon = copy_triplet(style_hitbox)
	icon[1] = icon[1] + math.floor((M.CONSOLE_STYLE_BUTTON.hitbox_size[1]
		- M.CONSOLE_STYLE_BUTTON.icon_size[1]) * 0.5)
	icon[2] = icon[2] + math.floor((M.CONSOLE_STYLE_BUTTON.hitbox_size[2]
		- M.CONSOLE_STYLE_BUTTON.icon_size[2]) * 0.5)
	icon[3] = icon[3] + 1
	return { original_cog_offset = original, cog_offset = cog,
		style_hitbox_offset = style_hitbox, icon_offset = icon }
end

local function console_row(runtime, parent_content, suffix)
	local item = type(parent_content) == "table" and parent_content["item" .. suffix]
	if not item or type(runtime) ~= "table" or type(runtime.describe) ~= "function" then return nil end
	local ok, row = pcall(runtime.describe, runtime, item, item.backend_id)
	return ok and row or nil
end

-- Decorate the definition returned by UIWidgets.create_loadout_grid_console.
-- This is deliberately definition-level: no copied window renderer, no global
-- item-row replacement, and no control on items without authored style data.
function M.decorate_console_grid(widget_def, runtime)
	if type(widget_def) ~= "table" or widget_def.cwv_combat_style_decorated then return false end
	local element = widget_def.element
	local passes = element and element.passes
	local content = widget_def.content
	local style = widget_def.style
	if type(passes) ~= "table" or type(content) ~= "table" or type(style) ~= "table"
			or type(runtime) ~= "table" or type(runtime.describe) ~= "function" then
		return false
	end

	local rows = tonumber(content.rows) or 0
	local columns = tonumber(content.columns) or 0
	local decorated = 0
	content.cwv_style_icon = M.CONSOLE_STYLE_BUTTON.icon
	content.cwv_style_icon_hover = M.CONSOLE_STYLE_BUTTON.icon
	content.cwv_style_rows = content.cwv_style_rows or {}

	for i = 1, rows do
		for k = 1, columns do
			local suffix = "_" .. tostring(i) .. "_" .. tostring(k)
			local customize_hotspot = "customize_hotspot" .. suffix
			local customize_hover = "customize_item_hover" .. suffix
			local cog_style = style[customize_hotspot]
			local cog_hover_style = style[customize_hover]
			local layout = cog_style and M.console_style_layout(cog_style.offset)
			if layout and cog_hover_style and type(cog_hover_style.offset) == "table" then
				local hotspot_name = "cwv_style_hotspot" .. suffix
				local icon_name = "cwv_style_icon" .. suffix
				local hover_name = "cwv_style_icon_hover" .. suffix
				local row_suffix = suffix
				passes[#passes + 1] = {
					pass_type = "hotspot", content_id = hotspot_name, style_id = hotspot_name,
					content_check_function = function(child_content)
						local parent = child_content and child_content.parent
						local row = console_row(runtime, parent, row_suffix)
						if row and child_content then
							local _, next_style
							if type(runtime.next_style) == "function" then
								_, next_style = runtime:next_style(row.item_key, row.style_id)
							else
								_, next_style = M.next_style(row.item_key, row.style_id)
							end
							child_content.cwv_next_style_label = "Switch to: "
								.. tostring(next_style and next_style.label or row.style.label)
						end
						return row ~= nil
					end,
				}
				passes[#passes + 1] = {
					pass_type = "texture", texture_id = "cwv_style_icon", style_id = icon_name,
					content_check_function = function(parent_content)
						local row = console_row(runtime, parent_content, row_suffix)
						local hotspot = parent_content and parent_content[hotspot_name]
						return row ~= nil and hotspot and not hotspot.is_hover
					end,
				}
				passes[#passes + 1] = {
					pass_type = "texture", texture_id = "cwv_style_icon_hover", style_id = hover_name,
					content_check_function = function(parent_content)
						local row = console_row(runtime, parent_content, row_suffix)
						local hotspot = parent_content and parent_content[hotspot_name]
						return row ~= nil and hotspot and hotspot.is_hover
					end,
				}

				content[hotspot_name] = { drag_texture_size = copy_pair(M.CONSOLE_STYLE_BUTTON.hitbox_size) }
				content.cwv_style_rows[suffix] = {
					original_cog_offset = copy_triplet(layout.original_cog_offset),
					original_hover_offset = copy_triplet(cog_hover_style.offset),
				}
				style[hotspot_name] = {
					horizontal_alignment = "left", vertical_alignment = "center",
					size = copy_pair(M.CONSOLE_STYLE_BUTTON.hitbox_size),
					offset = copy_triplet(layout.style_hitbox_offset),
				}
				style[icon_name] = {
					horizontal_alignment = "left", vertical_alignment = "center",
					color = { 255, 150, 150, 150 },
					size = copy_pair(M.CONSOLE_STYLE_BUTTON.icon_size),
					texture_size = copy_pair(M.CONSOLE_STYLE_BUTTON.icon_size),
					offset = copy_triplet(layout.icon_offset),
				}
				style[hover_name] = {
					horizontal_alignment = "left", vertical_alignment = "center",
					color = { 255, 255, 255, 255 },
					size = copy_pair(M.CONSOLE_STYLE_BUTTON.icon_size),
					texture_size = copy_pair(M.CONSOLE_STYLE_BUTTON.icon_size),
					offset = copy_triplet(layout.icon_offset),
				}
				decorated = decorated + 1
			end
		end
	end

	if decorated == 0 then return false end
	widget_def.cwv_combat_style_decorated = true
	return true, decorated
end

-- Re-evaluate eligibility after every vanilla loadout refresh. This owns all
-- row movement, so equipping, unequipping, swapping careers, or selecting a
-- different slot cannot leave a stale style control or displaced ordinary cog.
function M.refresh_console_row_layout(widget, runtime)
	local content = widget and widget.content
	local style = widget and widget.style
	local rows = content and content.cwv_style_rows
	if type(content) ~= "table" or type(style) ~= "table" or type(rows) ~= "table" then return 0 end
	local eligible = 0
	for suffix, authored in pairs(rows) do
		local row = console_row(runtime, content, suffix)
		local cog = style["customize_hotspot" .. suffix]
		local hover = style["customize_item_hover" .. suffix]
		local hotspot = content["cwv_style_hotspot" .. suffix]
		if cog and hover and hotspot then
			if row then
				local layout = M.console_style_layout(authored.original_cog_offset)
				cog.offset = copy_triplet(layout.cog_offset)
				hover.offset = copy_triplet(layout.cog_offset)
				hotspot.cwv_visible = true
				eligible = eligible + 1
			else
				cog.offset = copy_triplet(authored.original_cog_offset)
				hover.offset = copy_triplet(authored.original_hover_offset)
				hotspot.cwv_visible = false
				hotspot.on_pressed = false
				hotspot.on_release = false
			end
		end
	end
	return eligible
end

function M.consume_console_style_press(content, runtime)
	if type(content) ~= "table" then return nil end
	for i = 1, tonumber(content.rows) or 0 do
		for k = 1, tonumber(content.columns) or 0 do
			local suffix = "_" .. tostring(i) .. "_" .. tostring(k)
			local hotspot = content["cwv_style_hotspot" .. suffix]
			if hotspot and hotspot.cwv_visible then
				-- VMF exposes both edges for one physical click. Cycling on either
				-- edge advances twice, so press is observation-only and release is
				-- the single consumed commit edge (#644).
				local released = hotspot.on_release == true
				hotspot.on_pressed = false
				if released then hotspot.on_release = false end
				if released then
					local item = content["item" .. suffix]
					local row = console_row(runtime, content, suffix)
					if row then return item, suffix, row end
				end
			end
		end
	end
	return nil
end

function M.normalize_store(value)
	local result = { schema = M.SCHEMA, items = {} }
	if type(value) ~= "table" then return result end
	local source = value.schema == M.SCHEMA and value.items or value
	if type(source) ~= "table" then return result end
	for identity, style_id in pairs(source) do
		if valid_token(identity) and type(style_id) == "string" then
			result.items[identity] = style_id
		end
	end
	return result
end

function M.set(store, identity, item_key, style_id)
	if type(store) ~= "table" or type(store.items) ~= "table" or not valid_token(identity) then
		return false, "invalid identity"
	end
	local resolved, _, _, member = M.style(item_key, style_id)
	if resolved ~= style_id then return false, "unsupported style" end
	if style_id == member.default then style_id = nil end
	if store.items[identity] == style_id then return false end
	store.items[identity] = style_id
	return true
end

function M.valid_wire(schema, op, slot_name, family_id, style_id)
	if schema ~= M.SCHEMA or (op ~= "state" and op ~= "query") then return false end
	if op == "query" then return true end
	local family = M.FAMILIES[family_id]
	return (slot_name == "slot_melee" or slot_name == "slot_ranged")
		and family ~= nil and family.styles[style_id] ~= nil
end

local function build_modified_template(donor, clone, clone_damage_profile, prefix, speed, modifiers)
	if type(donor) ~= "table" then return nil, "donor template missing" end
	if type(clone) ~= "function" or type(clone_damage_profile) ~= "function" then
		return nil, "clone dependencies missing"
	end
	local template = clone(donor)
	for _, action_group in pairs(template.actions or {}) do
		if type(action_group) == "table" then
			for _, action in pairs(action_group) do
				if type(action) == "table" then
					if type(action.anim_time_scale) == "number" then
						action.anim_time_scale = action.anim_time_scale * speed
					end
					if type(action.damage_profile) == "string" then
						action.damage_profile = clone_damage_profile(action.damage_profile, prefix, modifiers)
					end
				end
			end
		end
	end
	return template
end

-- Imperial Longsword is the native Kruber Greatsword action graph with the
-- authored longsword balance and presentation. It must never inherit the
-- Bretonnian Longsword graph, which is the next, separate family entry (#644).
function M.build_imperial_template(weapons, clone, clone_damage_profile)
	local donor = weapons and weapons.two_handed_swords_template_1
	if type(donor) ~= "table" then return nil, "Kruber Greatsword template missing" end
	return build_modified_template(donor, clone, clone_damage_profile, "cwv_il_",
		M.IMPERIAL_SPEED_MULT, {
		damage = M.IMPERIAL_DAMAGE_MULT,
		stagger = M.IMPERIAL_STAGGER_MULT,
		cleave = M.IMPERIAL_CLEAVE_MULT,
	})
end

function M.build_kerillian_template(weapons, clone, clone_damage_profile)
	local donor = weapons and weapons.two_handed_swords_wood_elf_template
	if type(donor) ~= "table" then return nil, "Kerillian Greatsword template missing" end
	local template, err = build_modified_template(donor, clone, clone_damage_profile,
		"cwv_style_kerillian_gs_", M.KERILLIAN_SPEED_MULT,
		{ damage = 1, stagger = M.KERILLIAN_STAGGER_MULT, cleave = M.KERILLIAN_CLEAVE_MULT })
	if not template then return nil, err end
	-- The donor's first-person state machine remains exact. Only the 3P wield
	-- event is receiver-localized for Kruber; action redirects remain available
	-- to CWV/WT's existing network-bound animation funnel.
	template.wield_anim_career_3p = template.wield_anim_career_3p or {}
	for _, career in ipairs({ "es_mercenary", "es_huntsman", "es_knight", "es_questingknight" }) do
		template.wield_anim_career_3p[career] = "to_bastard_sword"
	end
	return template
end

-- Both donor templates are cloned byte-for-byte apart from receiver-specific
-- 3P wield routing. Action-event translation remains in the descriptor
-- registry above, so first-person actions and all native balance data stay
-- exact. Source: 1h_spears_shield.lua:1484-1485 and es_deus_01.lua:1749-1750.
function M.build_spear_shield_templates(weapons, clone)
	if type(weapons) ~= "table" or type(clone) ~= "function" then
		return nil, "template dependencies missing"
	end
	local empire_source = weapons.es_deus_01_template
	local elven_source = weapons.one_handed_spears_shield_template
	if type(empire_source) ~= "table" then return nil, "Kruber Spear and Shield template missing" end
	if type(elven_source) ~= "table" then return nil, "Elven Spear and Shield template missing" end

	local empire = clone(empire_source)
	empire.wield_anim_career_3p = empire.wield_anim_career_3p or {}
	for _, career in ipairs({ "we_waywatcher", "we_maidenguard", "we_shade", "we_thornsister" }) do
		empire.wield_anim_career_3p[career] = "to_1h_spear_shield"
	end

	local elven = clone(elven_source)
	elven.wield_anim_career_3p = elven.wield_anim_career_3p or {}
	for _, career in ipairs({ "es_mercenary", "es_huntsman", "es_knight", "es_questingknight" }) do
		elven.wield_anim_career_3p[career] = "to_es_deus_01"
	end

	return {
		[M.EMPIRE_SPEAR_SHIELD_TEMPLATE] = empire,
		[M.ELVEN_SPEAR_SHIELD_TEMPLATE] = elven,
	}
end

function M.install(mod, deps)
	deps = deps or {}
	local store = M.normalize_store(mod:get(M.SETTING_KEY))
	local remote = {}
	local presentations = type(deps.presentations) == "table" and deps.presentations or {}
	local runtime = { store = store, remote = remote, pending = {}, diagnostic_counts = {}, diagnostic_seen = {} }

	local function item_identity(item, backend_id)
		local data = item and (item.data or item)
		local value = backend_id or (item and (item.backend_id or item.ItemId))
			or (data and (data.backend_id or (data.mod_data and data.mod_data.backend_id)))
		return valid_token(value) and value or nil
	end

	local function item_key(item, backend_id)
		local data = item and (item.data or item)
		local cwv_key = type(deps.cwv_key_for_item) == "function"
			and deps.cwv_key_for_item(item_identity(item, backend_id), data) or nil
		if M.member(cwv_key) then return cwv_key end
		-- Do not collect these into an ipairs table: optional leading fields are
		-- commonly nil and would stop traversal before the native item name.
		for _, field in ipairs({ "cwv_key", "key", "name", "item_type" }) do
			local value = data and data[field]
			if M.member(value) then return value end
		end
		return nil
	end

	function runtime:describe(item, backend_id)
		local key = item_key(item, backend_id)
		local identity = item_identity(item, backend_id)
		if not key or not identity then return nil end
		local saved = self.store.items[identity]
		local package = M.package(key, saved)
		local style_id, style, family_id, member = package.style_id, package.style,
			package.family_id, package.member
		return { item_key = key, identity = identity, style_id = style_id, style = style,
			family_id = family_id, member = member, package = package, item_data = item.data or item }
	end

	function runtime:owns_style(style)
		return M.style_available(style, deps.owns_dlc)
	end

	function runtime:next_style(item_key_value, current)
		return M.next_style(item_key_value, current, deps.owns_dlc)
	end

	function runtime:resolve_template(item, backend_id)
		local row = self:describe(item, backend_id)
		local weapons = rawget(_G, "Weapons")
		if row then return weapons and weapons[row.package.template] or nil end
		-- Remote husk items intentionally have no backend id. The consolidated
		-- husk-wield wrapper supplies a strictly synchronous owner+slot context so
		-- the same BackendUtils seam can select that peer's received style without
		-- ever guessing from a bare base item outside the wield transaction.
		local context = self.husk_context
		local key = context and item_key(item, backend_id)
		local family_id = key and M.member(key)
		if not (context and family_id == context.family_id) then return nil end
		local family = M.FAMILIES[family_id]
		local style = family and family.styles[context.style_id]
		return style and weapons and weapons[style.template] or nil
	end

	function runtime:begin_husk_wield(inventory, slot_name)
		local owner = inventory and (inventory._unit or inventory.owner_unit)
		local peer_id = type(deps.peer_for_owner) == "function" and deps.peer_for_owner(owner) or nil
		local row = peer_id and remote[peer_id] and remote[peer_id][slot_name]
		self.husk_context = row and { family_id = row.family_id, style_id = row.style_id } or nil
		return self.husk_context ~= nil
	end

	function runtime:end_husk_wield()
		self.husk_context = nil
	end

	-- Returns nil for unsupported, false to suppress the legacy CWV transform,
	-- or the exact style-owned transform definition to apply.
	function runtime:transform_decision(item, backend_id)
		local row = self:describe(item, backend_id)
		if not row then return nil end
		local key = row.package.presentation and row.package.presentation.transform_key
		if key then return presentations[key] or false end
		return false
	end

	function runtime:effective_remap_key(item, backend_id)
		local row = self:describe(item, backend_id)
		if row and row.family_id == "spear" and row.style_id == "infantry" then
			return "cwv_es_infantry_spear"
		end
		return row and row.item_key or nil
	end

	function runtime:remap_event(item, backend_id, career, source_event)
		local row = self:describe(item, backend_id)
		if not row then return nil end
		local remap = row.package.remap_key and M.REMAPS[row.package.remap_key]
		return remap and remap.events and remap.events[source_event] or nil
	end

	function runtime:observe_candidate_action(item_key_value, career, source_event)
		if type(deps.diagnostics_enabled) ~= "function" or not deps.diagnostics_enabled() then
			return false
		end
		local candidate_id, candidate = M.diagnostic_candidate(item_key_value)
		if not candidate_id or type(source_event) ~= "string" then return false end
		local count = self.diagnostic_counts[candidate_id] or 0
		local key = candidate_id .. ":" .. tostring(career) .. ":" .. source_event
		if count >= M.DIAGNOSTIC_EVENT_CAP or self.diagnostic_seen[key] then return false end
		self.diagnostic_seen[key] = true
		self.diagnostic_counts[candidate_id] = count + 1
		pcall(printf,
			"[cwv:645] candidate=%s item=%s career=%s owner_event=%s sample=%d/%d reason=%s",
			candidate_id, tostring(item_key_value), tostring(career), source_event,
			count + 1, M.DIAGNOSTIC_EVENT_CAP, candidate.reason)
		return true
	end

	function runtime:remote_transform(owner_unit, slot_name)
		if type(deps.peer_for_owner) ~= "function" then return nil end
		local peer_id = deps.peer_for_owner(owner_unit)
		local row = peer_id and remote[peer_id] and remote[peer_id][slot_name]
		if not row then return nil end
		local family = M.FAMILIES[row.family_id]
		local style = family and family.styles[row.style_id]
		local key = style and style.presentation and style.presentation.transform_key
		return key and presentations[key] or false
	end

	local function persist()
		mod:set(M.SETTING_KEY, store, false)
	end

	function runtime:migrate_identity(identity, item_key, style_id)
		local changed, err = M.set(store, identity, item_key, style_id)
		if changed then persist() end
		return changed, err
	end

	function runtime:migrate_identities(rows)
		local count = 0
		for _, row in ipairs(rows or {}) do
			local changed = M.set(store, row.identity, row.item_key, row.style_id)
			if changed then count = count + 1 end
		end
		if count > 0 then persist() end
		return count
	end

	local function send(recipient, op, slot_name, family_id, style_id)
		if type(mod.network_send) ~= "function" then return false end
		return pcall(mod.network_send, mod, M.CHANNEL, recipient or "others", M.SCHEMA,
			op, slot_name or "", family_id or "", style_id or "")
	end

	local function local_equipment()
		local pm = rawget(_G, "Managers") and Managers.player
		local player = pm and pm.local_player and pm:local_player(1)
		local unit = player and player.player_unit
		if not unit or not Unit.alive(unit) then return nil end
		local ok, inventory = pcall(ScriptUnit.extension, unit, "inventory_system")
		return ok and inventory or nil, unit
	end

	local function action_active(equipment)
		for _, unit in ipairs({ equipment and equipment.right_hand_wielded_unit,
				equipment and equipment.left_hand_wielded_unit }) do
			if unit and Unit.alive(unit) and ScriptUnit.has_extension(unit, "weapon_system") then
				local ok, extension = pcall(ScriptUnit.extension, unit, "weapon_system")
				if ok and extension and extension.has_current_action and extension:has_current_action() then
					return true
				end
			end
		end
		return false
	end

	function runtime:publish(inventory, slot_name, item, recipient, reason)
		local row = self:describe(item)
		if not row then return false end
		local ok = send(recipient, "state", slot_name, row.family_id, row.style_id)
		if ok then pcall(printf, "[cwv:620] style tx slot=%s family=%s style=%s reason=%s",
			tostring(slot_name), row.family_id, row.style_id, tostring(reason)) end
		return ok
	end

	function runtime:set_item_style(item, backend_id, desired, reason, rebuild)
		local row = self:describe(item, backend_id)
		if not row then return false, "unsupported item" end
		local resolved = M.style(row.item_key, desired)
		if resolved ~= desired then return false, "unsupported style" end
		local inventory, equipment, slot_name, live_item
		if rebuild then
			inventory = local_equipment()
			equipment = inventory and inventory:equipment()
			slot_name = equipment and equipment.wielded_slot
			local slot = slot_name and equipment.slots and equipment.slots[slot_name]
			live_item = slot and slot.item_data
			local live = live_item and self:describe(live_item)
			if live and live.identity == row.identity and action_active(equipment) then
				pcall(printf, "[cwv:620] style deferred: active action item=%s", row.identity)
				return false, "active action"
			end
		end
		local changed, err = M.set(store, row.identity, row.item_key, desired)
		if not changed then return false, err or "unchanged" end
		row.item_data.mod_data = row.item_data.mod_data or {}
		row.item_data.mod_data.cwv_combat_style = desired
		if rebuild then
			local live = live_item and self:describe(live_item)
			if live and live.identity == row.identity then
				local ok_destroy = pcall(inventory.destroy_slot, inventory, slot_name, true)
				local ok_add = ok_destroy and pcall(inventory.add_equipment, inventory, slot_name, live_item)
				local ok_wield = ok_add and pcall(inventory.wield, inventory, slot_name)
				if not ok_wield then
					-- Restore the previous policy before a best-effort equipment repair;
					-- persistence must never claim a transition the live slot rejected.
					M.set(store, row.identity, row.item_key, row.style_id)
					persist()
					row.item_data.mod_data.cwv_combat_style = row.style_id
					pcall(inventory.destroy_slot, inventory, slot_name, true)
					pcall(inventory.add_equipment, inventory, slot_name, live_item)
					pcall(inventory.wield, inventory, slot_name)
					pcall(printf, "[cwv:620] style rollback: rebuild failed item=%s", row.identity)
					return false, "rebuild failed"
				end
				self:publish(inventory, slot_name, item, nil, reason or "transition")
			end
		end
		-- Persistence and the commit diagnostic intentionally happen only after
		-- the live slot accepted the rebuilt style. An engine resource gate runs
		-- before this function whenever a transition requires a new state machine.
		persist()
		pcall(printf, "[cwv:620] style commit item=%s family=%s %s->%s reason=%s",
			row.identity, row.family_id, row.style_id, desired, tostring(reason))
		return true
	end

	function runtime:request_item_style(item, backend_id, desired, reason, rebuild, complete)
		local row = self:describe(item, backend_id)
		if not row then return false, "unsupported item" end
		if self.pending[row.identity] then return false, "transition pending" end
		local resolved, style = M.style(row.item_key, desired)
		if resolved ~= desired then return false, "unsupported style" end
		if not self:owns_style(style) then return false, "required DLC unavailable" end
		local package = M.package(row.item_key, desired)
		local resource = package and package.resource
		if not (rebuild and resource) then
			local changed, err = self:set_item_style(item, backend_id, desired, reason, rebuild)
			if type(complete) == "function" then complete(changed, err) end
			return changed, err
		end

		local acquire = deps.acquire_style_resource
		if type(acquire) ~= "function" then return false, "resource loader unavailable" end
		local tx = { identity = row.identity, item_key = row.item_key,
			from = row.style_id, desired = desired, resource = resource }
		self.pending[row.identity] = tx
		local settled = false
		local function finish(ready, load_err)
			if settled then return end
			settled = true
			if runtime.pending[tx.identity] ~= tx then return end
			runtime.pending[tx.identity] = nil
			local current = runtime:describe(item, backend_id)
			if not ready or not current or current.identity ~= tx.identity
					or current.item_key ~= tx.item_key or current.style_id ~= tx.from then
				local err = load_err or "stale transition"
				pcall(printf, "[cwv:620] style load rejected item=%s resource=%s reason=%s",
					tx.identity, tx.resource, tostring(err))
				if type(complete) == "function" then complete(false, err) end
				return
			end
			local changed, err = runtime:set_item_style(item, backend_id, tx.desired, reason, rebuild)
			if type(complete) == "function" then complete(changed, err) end
		end
		local ok, accepted, acquire_err = pcall(acquire, resource, finish)
		if not ok or accepted == false then
			finish(false, acquire_err or accepted or "resource load rejected")
			return false, acquire_err or "resource load rejected"
		end
		return true, "transition pending"
	end

	function runtime:cycle_item(item, backend_id, reason, rebuild, complete)
		local row = self:describe(item, backend_id)
		if not row then return false, "unsupported item" end
		local next_id = self:next_style(row.item_key, row.style_id)
		if not next_id or next_id == row.style_id then return false, "no available alternate style" end
		return self:request_item_style(item, backend_id, next_id, reason, rebuild, complete)
	end

	function runtime:cycle_wielded()
		local inventory = local_equipment()
		local equipment = inventory and inventory:equipment()
		local slot_name = equipment and equipment.wielded_slot
		local slot = slot_name and equipment.slots and equipment.slots[slot_name]
		if not slot then return false end
		return self:cycle_item(slot.item_data, nil, "hotkey", true)
	end

	function runtime:on_local_wield(inventory, slot_name, item)
		local row = self:describe(item)
		if not row then return false end
		item.mod_data = item.mod_data or {}
		item.mod_data.cwv_combat_style = row.style_id
		return self:publish(inventory, slot_name, item, nil, "wield")
	end

	function runtime:on_husk_wield(inventory, slot_name)
		local owner = inventory and (inventory._unit or inventory.owner_unit)
		local decision = self:remote_transform(owner, slot_name)
		if decision == nil then return false end
		-- The ordinary husk rebuild/spawn has already consumed remote state. This
		-- callback is an observation marker; the receiver below rewields on edges.
		return true
	end

	function runtime:publish_loadout(recipient, reason)
		local inventory = local_equipment()
		local equipment = inventory and inventory:equipment()
		for _, slot_name in ipairs({ "slot_melee", "slot_ranged" }) do
			local slot = equipment and equipment.slots and equipment.slots[slot_name]
			if slot then self:publish(inventory, slot_name, slot.item_data, recipient, reason or "query") end
		end
	end

	function runtime:request_states(reason)
		send("others", "query")
		self:publish_loadout(nil, reason or "query")
	end

	if type(mod.network_register) == "function" then
		mod:network_register(M.CHANNEL, function(sender_peer_id, schema, op, slot_name, family_id, style_id)
			if not M.valid_wire(schema, op, slot_name, family_id, style_id) then return end
			if op == "query" then runtime:publish_loadout(sender_peer_id, "query_reply"); return end
			remote[sender_peer_id] = remote[sender_peer_id] or {}
			local previous = remote[sender_peer_id][slot_name]
			if previous and previous.family_id == family_id and previous.style_id == style_id then return end
			remote[sender_peer_id][slot_name] = { family_id = family_id, style_id = style_id }
			pcall(printf, "[cwv:620] style rx peer=%s slot=%s family=%s style=%s",
				tostring(sender_peer_id), slot_name, family_id, style_id)
			if type(deps.rebuild_remote) == "function" then deps.rebuild_remote(sender_peer_id, slot_name) end
		end)
	end

	return runtime
end

-- Adds one contextual control to the mouse/keyboard hero loadout bar. The
-- vanilla module captures these definition tables by reference, so mutating
-- the cached tables before a HeroWindowLoadout instance is created is enough;
-- no copied view or custom renderer is introduced.
function M.install_loadout_ui(mod, runtime)
	if M._ui_installed or type(runtime) ~= "table" then return false end
	local desktop_ok, definitions = pcall(local_require,
		"scripts/ui/views/hero_view/windows/definitions/hero_window_loadout_definitions")
	local scenegraph = desktop_ok and definitions and definitions.scenegraph_definition
	local widgets = desktop_ok and definitions and definitions.widgets

	if type(scenegraph) == "table" and type(widgets) == "table" then
		scenegraph.cwv_combat_style_button = scenegraph.cwv_combat_style_button or {
		parent = "loadout_background",
		horizontal_alignment = "center",
		vertical_alignment = "bottom",
		size = { 390, 46 },
		position = { 0, 122, 30 },
	}
		widgets.cwv_combat_style_button = widgets.cwv_combat_style_button or {
		scenegraph_id = "cwv_combat_style_button",
		element = { passes = {
			{ pass_type = "hotspot", content_id = "button_hotspot", content_check_function = function(content) return content.visible end },
			{ pass_type = "rect", style_id = "background", content_check_function = function(content) return content.visible end },
			{ pass_type = "rect", style_id = "border", content_check_function = function(content) return content.visible end },
			{ pass_type = "text", text_id = "button_text", style_id = "button_text", content_check_function = function(content) return content.visible end },
			{ pass_type = "text", text_id = "button_text", style_id = "button_text_shadow", content_check_function = function(content) return content.visible end },
		} },
		content = { visible = false, button_hotspot = {}, button_text = "" },
		style = {
			background = { color = { 220, 32, 38, 40 }, offset = { 2, 2, 2 }, size = { 386, 42 } },
			border = { color = { 255, 160, 146, 101 }, offset = { 0, 0, 1 }, size = { 390, 46 } },
			button_text = { font_type = "hell_shark", font_size = 22,
				horizontal_alignment = "center", vertical_alignment = "center",
				text_color = { 255, 255, 255, 255 }, offset = { 0, 2, 4 }, size = { 390, 46 } },
			button_text_shadow = { font_type = "hell_shark", font_size = 22,
				horizontal_alignment = "center", vertical_alignment = "center",
				text_color = { 255, 0, 0, 0 }, offset = { 2, 0, 3 }, size = { 390, 46 } },
		},
		}
	end

	local function selected(window)
		local parent = window and window.parent
		local index = parent and parent.get_selected_loadout_slot_index
			and parent:get_selected_loadout_slot_index()
		local item = index and window._equipment_items and window._equipment_items[index]
		return item, index
	end

	local function refresh(window)
		local widget = window and window._widgets_by_name
			and window._widgets_by_name.cwv_combat_style_button
		if not widget then return end
		local item = selected(window)
		local row = item and runtime:describe(item, item.backend_id)
		widget.content.visible = row ~= nil
		if row then
			local _, next_style
			if type(runtime.next_style) == "function" then
				_, next_style = runtime:next_style(row.item_key, row.style_id)
			else
				_, next_style = M.next_style(row.item_key, row.style_id)
			end
			widget.content.button_text = "Switch to: " .. (next_style and next_style.label or row.style.label)
			widget.content.button_hotspot.disable_button = false
		end
	end

	local function on_ui_transition_complete(window, changed)
		if not changed then return end
		local parent = window and window.parent
		if parent then parent.loadout_sync_id = (parent.loadout_sync_id or 0) + 1 end
		pcall(function() window:_play_sound("play_gui_equipment_selection_click") end)
	end

	if type(scenegraph) == "table" and type(widgets) == "table" then
		mod:hook("HeroWindowLoadout", "_populate_loadout", function(func, self, ...)
			local result = func(self, ...)
			refresh(self)
			return result
		end)
		mod:hook("HeroWindowLoadout", "_handle_input", function(func, self, ...)
			local r1, r2, r3, r4 = func(self, ...)
			refresh(self)
			local widget = self._widgets_by_name and self._widgets_by_name.cwv_combat_style_button
			local hotspot = widget and widget.content and widget.content.button_hotspot
			if widget and widget.content.visible and hotspot and hotspot.on_release then
				hotspot.on_release = false
				local item = selected(self)
				if item then runtime:cycle_item(item, item.backend_id,
					"inventory_button", true, function(changed)
						on_ui_transition_complete(self, changed)
					end)
				end
				refresh(self)
			end
			return r1, r2, r3, r4
		end)
	end

	local console_ok, console_definitions = pcall(local_require,
		"scripts/ui/views/hero_view/windows/definitions/hero_window_loadout_console_definitions")
	local console_installed = false
	if console_ok and type(console_definitions) == "table"
			and type(console_definitions.create_loadout_grid_func) == "function" then
		local original_create_grid = console_definitions.create_loadout_grid_func
		console_definitions.create_loadout_grid_func = function(...)
			local widget_def = original_create_grid(...)
			M.decorate_console_grid(widget_def, runtime)
			return widget_def
		end

		local actions = console_definitions.generic_input_actions
		for _, pair in ipairs({ { "default", "cwv_style" },
				{ "default_no_customization", "cwv_style_no_customization" } }) do
			local source = actions and actions[pair[1]]
			if type(source) == "table" then
				local list = M.bounded_style_actions(source, M.INPUT_DESCRIPTION_CAPACITY)
				actions[pair[2]] = list
			end
		end

		local function console_widget(window)
			return window and window._widgets_by_name and window._widgets_by_name.loadout_grid
		end

		local function refresh_console(window)
			local widget = console_widget(window)
			return widget and M.refresh_console_row_layout(widget, runtime) or 0
		end

		local function selected_console_item(window)
			local widget = console_widget(window)
			local content = widget and widget.content
			if not content then return nil end
			for i = 1, tonumber(content.rows) or 0 do
				for k = 1, tonumber(content.columns) or 0 do
					local suffix = "_" .. tostring(i) .. "_" .. tostring(k)
					local slot = content["hotspot" .. suffix]
					local row = slot and slot.is_selected and console_row(runtime, content, suffix)
					if row then return content["item" .. suffix], suffix, row end
				end
			end
			return nil
		end

		mod:hook("HeroWindowLoadoutConsole", "_populate_loadout", function(func, self, ...)
			local result = func(self, ...)
			refresh_console(self)
			return result
		end)

		mod:hook("HeroWindowLoadoutConsole", "_update_input_description", function(func, self, ...)
			local result = func(self, ...)
			local item = selected_console_item(self)
			if item and self._menu_input_description then
				local customizable = self._is_selected_item_customizable
					and self:_is_selected_item_customizable()
				local wanted = customizable and "cwv_style" or "cwv_style_no_customization"
				local list = actions and actions[wanted]
				if list and self._current_input_desc ~= wanted then
					local widgets = self._menu_input_description.console_input_description_widgets
					local capacity = type(widgets) == "table" and #widgets
						or M.INPUT_DESCRIPTION_CAPACITY
					local safe_list = M.bounded_style_actions(list, capacity)
					self._menu_input_description:change_generic_actions(safe_list)
					self._current_input_desc = wanted
				end
			end
			return result
		end)

		mod:hook("HeroWindowLoadoutConsole", "_handle_input", function(func, self, ...)
			refresh_console(self)
			local widget = console_widget(self)
			local item, suffix, row
			if widget then item, suffix, row = M.consume_console_style_press(widget.content, runtime) end
			if item then
				local accepted, err = runtime:cycle_item(item, item.backend_id,
					"equipment_style_button", true, function(changed, complete_err)
						on_ui_transition_complete(self, changed)
						if changed then
							pcall(printf, "[cwv:620] equipment style button item=%s family=%s row=%s",
								tostring(row.identity), tostring(row.family_id), tostring(suffix))
						elseif complete_err then
							pcall(printf, "[cwv:620] equipment style button rejected item=%s reason=%s",
								tostring(row.identity), tostring(complete_err))
						end
					end)
				if not accepted then
					pcall(printf, "[cwv:620] equipment style button deferred item=%s reason=%s",
						tostring(row.identity), tostring(err))
				end
				return
			end
			return func(self, ...)
		end)

		mod:hook("HeroWindowLoadoutConsole", "_handle_gamepad_input", function(func, self, ...)
			refresh_console(self)
			local input = self._input_service and self:_input_service()
			local item, _, row = selected_console_item(self)
			if item and input and input:get("special_1", true) then
				local accepted, err = runtime:cycle_item(item, item.backend_id,
					"equipment_style_controller", true, function(changed, complete_err)
						on_ui_transition_complete(self, changed)
						if not changed and complete_err then
							pcall(printf, "[cwv:620] controller style rejected item=%s reason=%s",
								tostring(row.identity), tostring(complete_err))
						end
					end)
				if not accepted then
					pcall(printf, "[cwv:620] controller style deferred item=%s reason=%s",
						tostring(row.identity), tostring(err))
				end
				return
			end
			return func(self, ...)
		end)
		console_installed = true
	end

	M._ui_installed = (type(scenegraph) == "table" and type(widgets) == "table") or console_installed
	M._console_ui_installed = console_installed
	return M._ui_installed
end

return M
