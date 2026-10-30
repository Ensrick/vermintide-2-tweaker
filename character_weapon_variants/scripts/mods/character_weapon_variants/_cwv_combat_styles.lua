-- Per-instance Combat Style policy and runtime owner (issue #620).
--
-- A style is an immutable package of template, balance, presentation, and
-- receiver-animation metadata. The persisted value is only the stable style id
-- keyed by exact backend item id. Runtime transitions rebuild the equipped slot
-- once; peers receive one bounded family/style edge and never a template table.
local M = {}
function M.is_sword_item(key) return key == "es_1h_sword" or key == "we_1h_sword" end
local function sword_family(family_id)
	local empire, elven = M.member("es_1h_sword"), M.member("we_1h_sword")
	return family_id ~= nil and (family_id == empire or family_id == elven)
end
function M.is_sword_identity(row)
	if type(row) ~= "table" or not M.is_sword_item(row.base_item_key) then return false end
	return (row.provider == "cwv_style" and M.is_sword_item(row.item_key or row.variant_key))
		or sword_family(M.decode_style_rider(row.style or row.style_rider))
		or (row.provider == "" and row.item_key == "" and row.style == "")
end

M.SETTING_KEY = "cwv_combat_style_state"
M.CHANNEL = "cwv_combat_style_v1"
M.SCHEMA = 1
M.MAX_TOKEN = 96
M.INPUT_DESCRIPTION_CAPACITY = 7
M.KERILLIAN_TEMPLATE = "cwv_combat_style_kerillian_greatsword"
M.BRETONNIAN_GREATSWORD_TEMPLATE = "cwv_combat_style_bretonnian_greatsword"
M.SALTZ_BRETONNIAN_TEMPLATE = "cwv_combat_style_saltz_bretonnian_greatsword"
M.EMPIRE_SPEAR_SHIELD_TEMPLATE = "cwv_combat_style_empire_spear_shield"
M.ELVEN_SPEAR_SHIELD_TEMPLATE = "cwv_combat_style_elven_spear_shield"
M.DIAGNOSTIC_EVENT_CAP = 32
M.MISSION_UI_DIAGNOSTIC_CAP = 24
M.REMOTE_REFRESH_INTERVAL = 0.25
M.MAX_REMOTE_REFRESH_ATTEMPTS = 8
-- #786: how long a bare `cwv_combat_style_v1` arrival waits for the delivering
-- cwv_item_identity payload that carries the same edge before it rebuilds on
-- its own. One REMOTE_REFRESH_INTERVAL; the two sends leave the owner in the
-- same tick, so this only ever fires for a peer that never gets the rider.
M.STYLE_IDENTITY_GRACE = 0.25
-- #786: one compact style axis rides the identity payload, mirroring the #474
-- `musket_mode` rider. ONE field rather than two: a style id is meaningless
-- outside its family so the pair is never consumed apart, one key costs 21
-- fewer characters of JSON than `style_family` + `style_id` against VMF's
-- 500-char RPC cap (docs/VMF_RECIPES.md), and there is a single validate site.
M.STYLE_RIDER_MAX = 64
M.IMPERIAL_SPEED_MULT = 1.15
M.IMPERIAL_DAMAGE_MULT = 0.85
M.IMPERIAL_STAGGER_MULT = 0.85
M.IMPERIAL_CLEAVE_MULT = 1.15
M.KERILLIAN_SPEED_MULT = 0.85
M.KERILLIAN_DAMAGE_MULT = 1.075
M.KERILLIAN_STAGGER_MULT = 1.25
M.KERILLIAN_CLEAVE_MULT = 1.25
M.BRETONNIAN_GREATSWORD_STAGGER_MULT = 1.25
M.BRETONNIAN_GREATSWORD_CLEAVE_MULT = 0.75
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
	kerillian_greatsword_to_saltz = {
		events = {
			attack_swing_charge = "attack_swing_charge_left_diagonal",
			attack_swing_right = "attack_swing_right_diagonal",
			attack_swing_left = "attack_swing_left_diagonal",
			attack_swing_heavy = "attack_swing_heavy_left_diagonal",
			attack_swing_heavy_right = "attack_swing_heavy_right_diagonal",
		},
	},
	bretonnian_greatsword_to_saltz = {
		events = {
			attack_push = "attack_push",
			attack_swing_charge_down_pose = "attack_swing_charge_diagonal_right",
			attack_swing_charge_left_diagonal = "attack_swing_charge_diagonal_left",
			attack_swing_charge_left_diagonal_pose = "attack_swing_charge_diagonal_left",
			attack_swing_charge_right_diagonal_pose = "attack_swing_charge_diagonal_right",
			attack_swing_down = "attack_swing_down_right",
			attack_swing_down_right = "attack_swing_down_right",
			attack_swing_heavy_down = "attack_swing_down_right",
			attack_swing_heavy_left_diagonal = "attack_swing_heavy_left_diagonal",
			attack_swing_heavy_right_diagonal = "attack_swing_heavy_right_diagonal",
			attack_swing_right = "attack_swing_right_diagonal",
			attack_swing_up_left = "attack_swing_left_diagonal",
			parry_pose = "parry_pose",
			swap_charge_stance = "attack_swing_charge_diagonal",
		},
	},
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
	one_handed_swords = {
		styles = {
			empire = { label = "Empire Sword Combat Style", template = "one_handed_swords_template_1",
				resource = "units/beings/player/first_person_base/state_machines/melee/1h_sword",
				receivers = { we_1h_sword = { template = "cwv_645_empire_sword_style" } } },
			elven = { label = "Elven Sword Combat Style", template = "we_one_hand_sword_template_1",
				resource = "units/beings/player/first_person_base/state_machines/melee/1h_sword",
				receivers = { es_1h_sword = { template = "cwv_645_elven_sword_style" } } },
			mace = { label = "Mace Combat Style", template = "one_handed_hammer_template_1",
				resource = "units/beings/player/first_person_base/state_machines/melee/1h_hammer",
				receivers = { es_1h_sword = { template = "cwv_645_mace_sword_style" } } },
		},
		members = {
			es_1h_sword = { default = "empire", order = { "empire", "elven", "mace" } },
			we_1h_sword = { default = "elven", order = { "elven", "empire" } },
		},
	},
	greatsword = {
		styles = {
			greatsword = { label = "Greatsword Combat Style", template = "two_handed_swords_template_1",
				resource = "units/beings/player/first_person_base/state_machines/melee/2h_sword",
				receivers = {
					-- The native Bretonnian mesh is already proportioned for its
					-- native grip. Greatsword-family state machines need the exact
					-- reciprocal of the Greatsword -> Bretonnian presentation.
					es_bastard_sword = {
						template = M.BRETONNIAN_GREATSWORD_TEMPLATE,
						presentation = { transform_key = "bretonnian_greatsword_inverse" },
					},
				},
			},
			longsword = { label = "Longsword Combat Style", template = "imperial_longsword_template",
				presentation = { transform_key = "imperial_longsword" },
				resource = "units/beings/player/first_person_base/state_machines/melee/2h_sword" },
			bretonnian = {
				label = "Bretonnian Combat Style",
				template = "bastard_sword_template",
				resource = "units/beings/player/first_person_base/state_machines/melee/bastard_sword",
				receivers = {
					-- The native Greatsword mesh needs the proven Imperial
					-- Longsword proportions when the Bretonnian grip graph owns it.
					-- This presentation is 3P-only; first person remains wholly
					-- owned by the selected donor state machine.
					es_2h_sword = {
						presentation = { transform_key = "greatsword_bretonnian" },
					},
					wh_2h_sword = {
						template = M.SALTZ_BRETONNIAN_TEMPLATE,
						remap_key = "bretonnian_greatsword_to_saltz",
					},
				},
			},
			kerillian = {
				label = "Kerillian Greatsword Combat Style",
				template = M.KERILLIAN_TEMPLATE,
				resource = "units/beings/player/first_person_base/state_machines/melee/2h_sword_we",
				modifiers = { attack_speed = M.KERILLIAN_SPEED_MULT, damage = M.KERILLIAN_DAMAGE_MULT,
					stagger = M.KERILLIAN_STAGGER_MULT, cleave = M.KERILLIAN_CLEAVE_MULT },
				receivers = {
					es_bastard_sword = {
						presentation = { transform_key = "bretonnian_greatsword_inverse" },
					},
					wh_2h_sword = { remap_key = "kerillian_greatsword_to_saltz" },
				},
			},
			-- #916 Half-Swording: the selected sword model keeps rendering while
			-- the action graph comes from CWV's maul_template (the burn-scrubbed
			-- one_handed_hammer_wizard_template_1 clone in _cwv_core_templates).
			-- The donor 1P state machine is authored by vanilla at
			-- 1h_hammers_wizard.lua:1520; maul_template already carries the
			-- Kruber-safe two-handed linking, the closed-vocabulary 3P remap onto
			-- the Kruber greathammer event set, and wield_anim_3p=to_2h_hammer.
			-- Saltzpyre plays that same greathammer vocabulary natively (the
			-- greathammer family offers wh_2h_hammer the kruber style with no
			-- receiver), so no receiver remap or transform is required here.
			half_swording = {
				label = "Half-Swording Combat Style",
				template = "maul_template",
				resource = "units/beings/player/first_person_base/state_machines/melee/brw_hammer",
			},
		},
		members = {
			-- Imperial Longsword remains a persistence/migration style for
			-- pre-#620 exact instances, but it shares the native Greatsword
			-- action graph and therefore is not a second public moveset choice.
			-- Keep Bretonnian third, matching the authored equipment ordinal.
			-- #916: Half-Swording APPENDS after every existing ordinal so no
			-- saved cycle position moves.
			es_2h_sword = { default = "greatsword", order = { "greatsword", "kerillian", "bretonnian", "half_swording" } },
			wh_2h_sword = { default = "greatsword", order = { "greatsword", "kerillian", "bretonnian", "half_swording" } },
			es_bastard_sword = { default = "bretonnian", order = { "bretonnian", "greatsword", "kerillian", "half_swording" } },
			cwv_es_longsword = { default = "longsword", order = { "longsword", "bretonnian", "kerillian", "greatsword", "half_swording" } },
			cwv_es_longsword_blackguard = { default = "longsword", order = { "longsword", "bretonnian", "kerillian", "greatsword", "half_swording" } },
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
		-- #786: authored ground truth for the re-wield postcondition. A shield
		-- family MUST come back with both 3P hand units; the old
		-- `right_live or left_live` predicate passed a shield style that
		-- rebuilt without its off-hand.
		off_hand = true,
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
	sword_shield = {
		off_hand = true,   -- #786: see spear_shield above.
		styles = {
			empire = {
				label = "Empire Sword and Shield Combat Style",
				template = "one_handed_sword_shield_template_1",
				resource = "units/beings/player/first_person_base/state_machines/melee/1h_sword_shield",
			},
			bretonnian = {
				label = "Bretonnian Sword and Shield Combat Style",
				template = "one_handed_sword_shield_template_2",
				resource = "units/beings/player/first_person_base/state_machines/melee/1h_sword_shield_breton",
				required_dlc = "lake",
			},
		},
		members = {
			es_sword_shield = { default = "empire", order = { "empire", "bretonnian" } },
			es_sword_shield_breton = { default = "bretonnian", order = { "bretonnian", "empire" } },
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
	local style_id = member.default
	if not M.is_sword_item(item_key) then
		if family.styles[stored_style] then style_id = stored_style end
	else
		for _, candidate in ipairs(member.order) do
			if candidate == stored_style and family.styles[candidate] then
				style_id = candidate
				break
			end
		end
	end
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
		template = receiver and receiver.template or style.template,
		resource = style.resource,
		required_dlc = style.required_dlc,
		presentation = receiver and receiver.presentation or style.presentation,
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

function M.style_ordinal(item_key, current, owns_dlc)
	local style_id, _, _, member = M.style(item_key, current)
	if not style_id then return nil end
	local _, family = M.member(item_key)
	local available = {}
	for _, candidate in ipairs(member.order) do
		local row = family.styles[candidate]
		if M.style_available(row, owns_dlc) then available[#available + 1] = candidate end
	end
	for index, candidate in ipairs(available) do
		if candidate == style_id then return index, #available end
	end
	return nil
end

function M.moveset_indicator(item_key, current, owns_dlc, compact)
	local index, total = M.style_ordinal(item_key, current, owns_dlc)
	if not index then return nil end
	return compact and string.format("%d / %d", index, total)
		or string.format("Moveset %d / %d", index, total)
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
		-- #786: the re-wield postcondition reads this. An accidental falsy or
		-- non-boolean value would silently downgrade a shield family back to
		-- the single-hand expectation the OR predicate used to accept.
		if family.off_hand ~= nil and family.off_hand ~= true then
			return false, "invalid off_hand " .. tostring(family_id)
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
				local remap_valid = receiver.remap_key == nil or M.REMAPS[receiver.remap_key] ~= nil
				local template_valid = receiver.template == nil or valid_token(receiver.template)
				local presentation_valid = receiver.presentation == nil
					or valid_token(receiver.presentation.transform_key)
				if not family.members[member_key] or not remap_valid or not template_valid
						or not presentation_valid then
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
	local actor = type(runtime.console_actor) == "function" and runtime:console_actor(parent_content) or nil
	local ok, row = pcall(runtime.describe, runtime, item, item.backend_id, actor)
	if ok and row and M.is_sword_item(row.item_key) then
		if type(runtime.next_style) ~= "function" then return nil end
		local ready, next_id = pcall(runtime.next_style, runtime, row.item_key, row.style_id)
		if not ready or next_id == nil or next_id == row.style_id then return nil end
	end
	return ok and row or nil
end

local function ui_probe_text(value)
	value = tostring(value or "")
	if #value > M.MAX_TOKEN then return string.sub(value, 1, M.MAX_TOKEN) end
	return value
end

-- Pure, bounded record for the #774 mission-mounted loadout diagnostic. No item
-- table or backend payload is retained; the runtime logger deduplicates this
-- compact projection and never transports it over the network.
function M.mission_ui_probe(surface, stage, item, row, suffix, detail)
	local data = item and (item.data or item) or {}
	local raw_identity = item and (item.backend_id or item.ItemId)
		or data.backend_id or (data.mod_data and data.mod_data.backend_id)
	return {
		surface = ui_probe_text(surface),
		stage = ui_probe_text(stage),
		item_key = ui_probe_text(data.cwv_key or data.key or data.name or data.item_type),
		raw_identity = ui_probe_text(raw_identity),
		identity = ui_probe_text(row and row.identity),
		family = ui_probe_text(row and row.family_id),
		style = ui_probe_text(row and row.style_id),
		row = ui_probe_text(suffix),
		detail = ui_probe_text(detail),
	}
end

function M.mission_ui_probe_key(probe)
	probe = type(probe) == "table" and probe or {}
	return table.concat({ probe.surface or "", probe.stage or "", probe.item_key or "",
		probe.raw_identity or "", probe.identity or "", probe.family or "",
		probe.style or "", probe.row or "", probe.detail or "" }, "|")
end

function M.new_mission_ui_probe_sink(emit, cap)
	cap = math.min(M.MISSION_UI_DIAGNOSTIC_CAP,
		math.max(0, math.floor(tonumber(cap) or M.MISSION_UI_DIAGNOSTIC_CAP)))
	local seen = {}
	local count = 0
	return function(probe)
		if count >= cap then return false, count end
		local key = M.mission_ui_probe_key(probe)
		if seen[key] then return false, count end
		seen[key] = true
		count = count + 1
		if type(emit) == "function" then pcall(emit, probe, count, cap) end
		return true, count
	end
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
				local status_name = "cwv_style_status" .. suffix
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
				passes[#passes + 1] = {
					pass_type = "text", text_id = status_name, style_id = status_name,
					content_check_function = function(parent_content)
						local row = console_row(runtime, parent_content, row_suffix)
						local status_key = "cwv_style_status" .. row_suffix
						if row then
							if type(runtime.moveset_indicator) == "function" then
								parent_content[status_key] = runtime:moveset_indicator(
									row.item_key, row.style_id, true) or ""
							else
								parent_content[status_key] = M.moveset_indicator(
									row.item_key, row.style_id, nil, true) or ""
							end
						end
						return row ~= nil
					end,
				}

				content[hotspot_name] = { drag_texture_size = copy_pair(M.CONSOLE_STYLE_BUTTON.hitbox_size) }
				content[status_name] = ""
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
				style[status_name] = {
					font_type = "hell_shark", font_size = 14,
					horizontal_alignment = "center", vertical_alignment = "center",
					text_color = { 235, 225, 215, 190 },
					size = { 58, 20 },
					offset = { layout.style_hitbox_offset[1] - 4,
						layout.style_hitbox_offset[2] + M.CONSOLE_STYLE_BUTTON.hitbox_size[2],
						layout.style_hitbox_offset[3] + 2 },
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

-- #786 B1. Compact style axis for the cwv_item_identity payload. Encoding is
-- closed over the authored catalogue at both ends, so a malformed or unknown
-- pair never reaches the receiver's state. Worst authored pair is
-- `greathammer:warrior_priest`, i.e. 36 characters of JSON including the key.
function M.encode_style_rider(family_id, style_id)
	if type(family_id) ~= "string" or type(style_id) ~= "string" then return nil end
	local family = M.FAMILIES[family_id]
	if not family or not family.styles[style_id] then return nil end
	local rider = family_id .. ":" .. style_id
	if #rider > M.STYLE_RIDER_MAX then return nil end
	return rider
end

function M.decode_style_rider(rider)
	if type(rider) ~= "string" or #rider > M.STYLE_RIDER_MAX then return nil end
	local family_id, style_id = rider:match("^([%a][%w_]*):([%a][%w_]*)$")
	if not family_id then return nil end
	local family = M.FAMILIES[family_id]
	if not family or not family.styles[style_id] then return nil end
	return family_id, style_id
end

-- A style edge may arrive before the ordinary equipment-slot RPC has finished
-- populating the husk. Calling SimpleHuskInventoryExtension:wield in that gap
-- enters vanilla's wield path (stopping FX/attached units and updating wield
-- state) even though `_wield_slot` rejects the empty item. Do not start that
-- partial transition; let the next natural wield consume the cached style.
function M.remote_refresh_readiness(inventory, slot_name)
	if type(inventory) ~= "table" or type(slot_name) ~= "string" then
		return false, "inventory unavailable"
	end
	local equipment = inventory._equipment or inventory.equipment
	if type(equipment) ~= "table" or type(equipment.slots) ~= "table" then
		return false, "equipment unavailable"
	end
	local wielded_slot = inventory.wielded_slot or equipment.wielded_slot
	if wielded_slot ~= slot_name then return false, "slot not wielded" end
	local slot = equipment.slots[slot_name]
	if type(slot) ~= "table" or type(slot.item_data) ~= "table" then
		return false, "slot not ready"
	end
	return true, "ready"
end

-- Only lifecycle-not-ready outcomes receive a short local retry. A style for an
-- unwielded slot is already cached and will be consumed by the next natural
-- wield; engine errors and post-wield missing meshes need separate evidence and
-- must not be hammered repeatedly (#786/#660).
local RETRYABLE_REMOTE_REFRESH = {
	["player manager unavailable"] = true,
	["player unavailable"] = true,
	["player unit unavailable"] = true,
	["inventory extension unavailable"] = true,
	["inventory unavailable"] = true,
	["equipment unavailable"] = true,
	["slot not ready"] = true,
}

function M.remote_refresh_retryable(reason)
	return RETRYABLE_REMOTE_REFRESH[reason] == true
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

local function action_identity(extension)
	local settings = extension and extension.current_action_settings
	if not settings and extension and type(extension.get_current_action_settings) == "function" then
		local ok, value = pcall(extension.get_current_action_settings, extension)
		if ok then settings = value end
	end
	local lookup = settings and settings.lookup_data
	return extension and extension.current_action_name or lookup and lookup.action_name,
		settings and settings.kind
end

local function is_career_action(action_name, action_kind)
	local function matches(value)
		return type(value) == "string"
			and (string.find(value, "^action_career") or string.find(value, "^career_"))
	end
	return matches(action_name) or matches(action_kind) or false
end

-- End the exact wielded weapon actions through the engine's canonical action
-- lifecycle before a style rebuild. Both hands are preflighted before either is
-- touched, and career actions fail closed rather than being cancelled by a
-- presentation/moveset control. `extension_for_unit` keeps the policy testable
-- without engine globals and lets the runtime own unit-extension lookup.
function M.interrupt_equipment_actions(equipment, extension_for_unit)
	if type(extension_for_unit) ~= "function" then
		return false, "weapon extension resolver unavailable"
	end
	local active, seen = {}, {}
	for _, hand in ipairs({ "right_hand_wielded_unit", "left_hand_wielded_unit" }) do
		local unit = equipment and equipment[hand]
		local extension = unit and extension_for_unit(unit)
		if extension and not seen[extension] then
			seen[extension] = true
			local has_action = extension.current_action_settings ~= nil
			if type(extension.has_current_action) == "function" then
				local ok, value = pcall(extension.has_current_action, extension)
				if not ok then return false, "action state unavailable" end
				has_action = value == true
			end
			if has_action then
				local action_name, action_kind = action_identity(extension)
				if action_name == nil and action_kind == nil then
					return false, "action identity unavailable"
				end
				if is_career_action(action_name, action_kind) then
					return false, "career action active"
				end
				if type(extension.stop_action) ~= "function" then
					return false, "weapon action cannot be interrupted"
				end
				active[#active + 1] = extension
			end
		end
	end
	for _, extension in ipairs(active) do
		local ok = pcall(extension.stop_action, extension, "interrupted")
		if not ok then return false, "weapon action interrupt failed" end
		local still_active = extension.current_action_settings ~= nil
		if type(extension.has_current_action) == "function" then
			local checked, value = pcall(extension.has_current_action, extension)
			if not checked then return false, "action state unavailable after interrupt" end
			still_active = value == true
		end
		if still_active then return false, "weapon action remained active" end
	end
	return true, #active
end

function M.attack_range_signature(template)
	local seen = {}
	for _, action_group in pairs(type(template) == "table" and template.actions or {}) do
		for _, action in pairs(type(action_group) == "table" and action_group or {}) do
			if type(action) == "table" and type(action.damage_profile) == "string"
					and type(action.range_mod) == "number" then
				seen[action.range_mod] = true
			end
		end
	end
	local result = {}
	for value in pairs(seen) do result[#result + 1] = value end
	table.sort(result)
	return result
end

local function same_numeric_list(left, right)
	if #left ~= #right then return false end
	for index, value in ipairs(left) do
		if math.abs(value - right[index]) > 0.000001 then return false end
	end
	return true
end

function M.build_bretonnian_greatsword_template(weapons, clone, clone_damage_profile)
	local donor = weapons and weapons.two_handed_swords_template_1
	local receiver = weapons and weapons.bastard_sword_template
	if type(donor) ~= "table" then return nil, "Kruber Greatsword template missing" end
	if type(receiver) ~= "table" then return nil, "Bretonnian Longsword template missing" end
	local donor_ranges = M.attack_range_signature(donor)
	local receiver_ranges = M.attack_range_signature(receiver)
	if #donor_ranges == 0 or not same_numeric_list(donor_ranges, receiver_ranges) then
		return nil, "Greatsword/Bretonnian attack-range signature drift"
	end
	return build_modified_template(donor, clone, clone_damage_profile,
		"cwv_style_bretonnian_gs_", 1, {
			damage = 1,
			stagger = M.BRETONNIAN_GREATSWORD_STAGGER_MULT,
			cleave = M.BRETONNIAN_GREATSWORD_CLEAVE_MULT,
		})
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

-- Saltzpyre can own the native Greatsword through Weapon Tweaker, but the
-- Bretonnian donor's wield event is not present on his standard career state
-- machines. Clone the donor and select Saltzpyre's proven native Greatsword
-- wield route; action-event translation remains descriptor-owned above.
function M.build_saltz_bretonnian_template(weapons, clone)
	local donor = weapons and weapons.bastard_sword_template
	if type(donor) ~= "table" then return nil, "Bretonnian Longsword template missing" end
	if type(clone) ~= "function" then return nil, "template clone dependency missing" end
	local template = clone(donor)
	template.wield_anim_career_3p = template.wield_anim_career_3p or {}
	for _, career in ipairs({ "wh_captain", "wh_bountyhunter", "wh_zealot" }) do
		template.wield_anim_career_3p[career] = "to_2h_sword"
	end
	return template
end

function M.build_kerillian_template(weapons, clone, clone_damage_profile)
	local donor = weapons and weapons.two_handed_swords_wood_elf_template
	if type(donor) ~= "table" then return nil, "Kerillian Greatsword template missing" end
	local template, err = build_modified_template(donor, clone, clone_damage_profile,
		"cwv_style_kerillian_gs_", M.KERILLIAN_SPEED_MULT,
		{ damage = M.KERILLIAN_DAMAGE_MULT, stagger = M.KERILLIAN_STAGGER_MULT,
			cleave = M.KERILLIAN_CLEAVE_MULT })
	if not template then return nil, err end
	-- The donor's first-person state machine remains exact. Only the 3P wield
	-- event is receiver-localized for Kruber and Saltzpyre; action redirects remain available
	-- to CWV/WT's existing network-bound animation funnel.
	template.wield_anim_career_3p = template.wield_anim_career_3p or {}
	for _, career in ipairs({ "es_mercenary", "es_huntsman", "es_knight", "es_questingknight" }) do
		template.wield_anim_career_3p[career] = "to_bastard_sword"
	end
	for _, career in ipairs({ "wh_captain", "wh_bountyhunter", "wh_zealot" }) do
		template.wield_anim_career_3p[career] = "to_2h_sword"
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
	-- _cwv_style_rewield owns the verdict vocabulary; the fallback keeps this
	-- runtime testable stand-alone without duplicating the status strings.
	local rewield = type(deps.rewield) == "table" and deps.rewield
		or { OK = "ok", succeeded = function(status) return status == "ok" end }
	local runtime = { store = store, remote = remote, pending = {}, pending_remote = {},
		fallback_remote = {}, diagnostic_counts = {}, diagnostic_seen = {} }
	local actor_admission = deps.actor_admission
	local sword_owner = deps.sword_family
	local sword_package = type(sword_owner) == "table" and sword_owner.package or nil
	function runtime:package(key, selected)
		local package = M.package(key, selected)
		if not package or not M.is_sword_item(key) then return package end
		if type(sword_package) ~= "function" then return nil end
		local ok, name, value = pcall(sword_package, sword_owner, key, package.style_id)
		local weapons = rawget(_G, "Weapons")
		if not ok or name ~= package.template or type(value) ~= "table" or type(weapons) ~= "table"
				or not rawequal(rawget(weapons, name), value) then return nil end
		return package
	end
	function runtime:actor_admitted(key, item, backend_id, actor)
		if not M.is_sword_item(key) then return true end
		if type(actor_admission) ~= "table" or type(actor_admission.admit) ~= "function" then return false end
		local ok, admitted = pcall(actor_admission.admit, actor_admission, key, item, backend_id, actor)
		return ok and admitted == true
	end
	function runtime:loadout_actor(window)
		return function() return actor_admission and actor_admission:selected_profile(window) end
	end
	function runtime:console_actor(content)
		if type(content) == "table" and type(content.cwv_style_actor) == "function" then return content.cwv_style_actor end
		return function() return actor_admission and actor_admission:console_profile(content) end
	end
	function runtime:remote_actor_admitted(peer_id, slot_name, key, family_id, style_id)
		if not M.is_sword_item(key) and not sword_family(family_id) then return true end
		if type(actor_admission) ~= "table" or type(actor_admission.slot) ~= "function" then return false end
		local ok, item = pcall(actor_admission.slot, actor_admission, peer_id, slot_name)
		local physical = ok and type(item) == "table" and item.name or nil
		if not M.is_sword_item(physical) or (key ~= nil and key ~= physical) then return false end
		if not self:actor_admitted(physical, item, nil, function() return actor_admission:peer_profile(peer_id) end) then return false end
		if style_id == nil then return true end -- actor-only query, not selection authority
		local package = type(self.package) == "function" and self:package(physical, style_id) or nil
		if not package or (family_id ~= nil and package.family_id ~= family_id) then return false end
		return true, package
	end
	function runtime:queued_style_admitted(peer_id, slot_name, key, family_id, style_id)
		local row = remote[peer_id] and remote[peer_id][slot_name]
		if not row or row.family_id ~= family_id or row.style_id ~= style_id then return false end
		return self:remote_actor_admitted(peer_id, slot_name, key, family_id, style_id)
	end
	function runtime:descriptor_actor_admitted(peer_id, slot_name, descriptor)
		if type(descriptor) ~= "table" then return false end
		if not M.is_sword_identity(descriptor) then return true end
		local family_id, style_id = descriptor.style_family, descriptor.style_id
		if style_id == nil then family_id, style_id = M.decode_style_rider(descriptor.style or descriptor.style_rider) end
		if descriptor.provider == "" then
			local _, _, member = M.member(descriptor.base_item_key)
			family_id, style_id = M.member(descriptor.base_item_key), member and member.default
		end
		if style_id == nil or type(self.remote_actor_admitted) ~= "function" then return false end
		local allowed, package = self:remote_actor_admitted(peer_id, slot_name, descriptor.base_item_key, family_id, style_id)
		return allowed == true and package ~= nil
			and (descriptor.effective_template == nil or descriptor.effective_template == package.template)
	end

	local function remote_refresh_key(peer_id, slot_name)
		return tostring(peer_id) .. "|" .. tostring(slot_name)
	end

	function runtime:_emit_verdict(pending, status, detail, terminal)
		pcall(printf,
			"[cwv:786] verdict %s peer=%s slot=%s family=%s style=%s edge=%s attempt=%d/%d terminal=%s detail=%s",
			tostring(status), tostring(pending.peer_id), tostring(pending.slot_name),
			tostring(pending.family_id), tostring(pending.style_id),
			tostring(pending.edge), tonumber(pending.attempts) or 0,
			M.MAX_REMOTE_REFRESH_ATTEMPTS,
			terminal == nil and "retry" or tostring(terminal), tostring(detail))
	end

	-- #786 A1. The rebuild is DEFERRED into the #1145 per-wearer coalescer, so
	-- this call can only report whether the request was ACCEPTED. The verdict is
	-- produced post-drain and lands on `pending.verdict`, which `step()`
	-- consumes below. Never synthesize a synchronous success here.
	function runtime:_enqueue_remote_refresh(pending)
		if not self:remote_actor_admitted(pending.peer_id, pending.slot_name, nil, pending.family_id, pending.style_id) then
			return false, "actor unavailable"
		end
		if type(deps.rebuild_remote) ~= "function" then
			return false, "remote rebuild unavailable"
		end
		local key = remote_refresh_key(pending.peer_id, pending.slot_name)
		pending.verdict, pending.verdict_detail = nil, nil
		local ok, queued, reason = pcall(deps.rebuild_remote, pending.peer_id,
			pending.slot_name, pending.family_id, pending.style_id,
			function(status, detail)
				-- A verdict for a superseded ledger entry is discarded: the newer
				-- entry owns this (peer, slot) and will queue its own rebuild.
				if self.pending_remote[key] ~= pending then return end
				pending.verdict = status or "failed"
				pending.verdict_detail = detail
			end, pending.descriptor)
		if not ok then queued, reason = false, tostring(queued) end
		if queued ~= true then
			reason = tostring(reason or "not queued")
			-- Bounded: at most MAX_REMOTE_REFRESH_ATTEMPTS rows per style edge.
			pcall(printf,
				"[cwv:786] rebuild deferred peer=%s slot=%s family=%s style=%s edge=%s attempt=%d/%d reason=%s retryable=%s",
				tostring(pending.peer_id), tostring(pending.slot_name),
				tostring(pending.family_id), tostring(pending.style_id),
				tostring(pending.edge), tonumber(pending.attempts) or 0,
				M.MAX_REMOTE_REFRESH_ATTEMPTS, reason,
				tostring(M.remote_refresh_retryable(reason)))
			return false, reason
		end
		pending.phase, pending.elapsed = "verify", 0
		pcall(printf,
			"[cwv:786] rebuild queued peer=%s slot=%s family=%s style=%s edge=%s attempt=%d/%d",
			tostring(pending.peer_id), tostring(pending.slot_name),
			tostring(pending.family_id), tostring(pending.style_id),
			tostring(pending.edge), tonumber(pending.attempts) or 0,
			M.MAX_REMOTE_REFRESH_ATTEMPTS)
		return true, reason
	end

	-- Start (or restart) the ONE bounded ledger for a (peer, slot) style edge.
	-- #786 A3: the controller's step() is the only retry driver; the coalescer
	-- owns the wield and the mid-destroy guard. There is no second timer.
	function runtime:refresh_remote(peer_id, slot_name, edge)
		local key = remote_refresh_key(peer_id, slot_name)
		local state = remote[peer_id] and remote[peer_id][slot_name]
		if not state then
			self.pending_remote[key] = nil
			return false, "no style state"
		end
		if not self:remote_actor_admitted(peer_id, slot_name, nil, state.family_id, state.style_id) then
			self.pending_remote[key] = nil
			return false, "actor unavailable"
		end
		local pending = {
			peer_id = peer_id,
			slot_name = slot_name,
			family_id = state.family_id,
			style_id = state.style_id,
			token = state.token,
			descriptor = state.descriptor,
			edge = edge or "state",
			attempts = 1,
			elapsed = 0,
			phase = "enqueue",
		}
		self.pending_remote[key] = pending
		local queued, reason = self:_enqueue_remote_refresh(pending)
		if queued then return false, "queued" end
		pending.last_reason = reason
		if not M.remote_refresh_retryable(reason) then
			self.pending_remote[key] = nil
			self:_emit_verdict(pending, "failed", reason, true)
		end
		return false, reason
	end

	function runtime:_step_fallbacks(dt)
		for key, armed in pairs(self.fallback_remote) do
			local current = remote[armed.peer_id] and remote[armed.peer_id][armed.slot_name]
			armed.elapsed = armed.elapsed + dt
			if not current or current.token ~= armed.token
					or not self:remote_actor_admitted(armed.peer_id, armed.slot_name, nil, armed.family_id, armed.style_id)
					or current.owner == "identity" then
				self.fallback_remote[key] = nil
			elseif armed.elapsed >= M.STYLE_IDENTITY_GRACE then
				self.fallback_remote[key] = nil
				self:refresh_remote(armed.peer_id, armed.slot_name, "style_channel_fallback")
			end
		end
	end

	function runtime:step(dt)
		dt = type(dt) == "number" and math.max(dt, 0) or 0
		local completed, expired = 0, 0
		self:_step_fallbacks(dt)
		for key, pending in pairs(self.pending_remote) do
			local current = remote[pending.peer_id]
				and remote[pending.peer_id][pending.slot_name]
			pending.elapsed = pending.elapsed + dt
			if not current or current.token ~= pending.token
					or not self:remote_actor_admitted(pending.peer_id, pending.slot_name, nil, pending.family_id, pending.style_id) then
				-- The style moved on (or the peer left). A newer edge owns its
				-- own ledger entry; this one must not keep re-wielding.
				self.pending_remote[key] = nil
			elseif pending.verdict ~= nil then
				local status, detail = pending.verdict, pending.verdict_detail
				pending.verdict, pending.verdict_detail = nil, nil
				if rewield.succeeded(status) then
					self.pending_remote[key] = nil
					completed = completed + 1
					self:_emit_verdict(pending, status, detail, true)
				elseif pending.attempts >= M.MAX_REMOTE_REFRESH_ATTEMPTS then
					self.pending_remote[key] = nil
					expired = expired + 1
					self:_emit_verdict(pending, status, detail, true)
				else
					-- Partial application is failure and stays retryable.
					self:_emit_verdict(pending, status, detail, nil)
					pending.phase, pending.elapsed = "enqueue", 0
				end
			elseif pending.elapsed >= M.REMOTE_REFRESH_INTERVAL then
				pending.elapsed = 0
				if pending.attempts >= M.MAX_REMOTE_REFRESH_ATTEMPTS then
					self.pending_remote[key] = nil
					expired = expired + 1
					self:_emit_verdict(pending, "failed",
						pending.phase == "verify" and "no verdict before timeout"
							or tostring(pending.last_reason), true)
				else
					pending.attempts = pending.attempts + 1
					local queued, reason = self:_enqueue_remote_refresh(pending)
					if not queued then
						pending.phase, pending.last_reason = "enqueue", reason
						if not M.remote_refresh_retryable(reason) then
							self.pending_remote[key] = nil
							expired = expired + 1
							self:_emit_verdict(pending, "failed", reason, true)
						end
					end
				end
			end
		end
		return completed, expired
	end

	function runtime:pending_remote_refresh_count()
		local count = 0
		for _ in pairs(self.pending_remote) do count = count + 1 end
		return count
	end

	-- Called by the consolidated PlayerManager.remove_player owner. Style
	-- descriptors are authenticated by the exact identity lifecycle, so their
	-- per-peer state and every deferred retry/fallback must end in the same
	-- teardown transaction. No global clear: other peers keep their accepted
	-- state and bounded ledgers.
	function runtime:clear_peer(peer_id)
		if type(peer_id) ~= "string" or peer_id == "" then return 0 end
		local removed = self.remote[peer_id] and 1 or 0
		self.remote[peer_id] = nil
		local prefix = peer_id .. "|"
		for key in pairs(self.pending_remote) do
			if key:sub(1, #prefix) == prefix then
				self.pending_remote[key] = nil
				removed = removed + 1
			end
		end
		for key in pairs(self.fallback_remote) do
			if key:sub(1, #prefix) == prefix then
				self.fallback_remote[key] = nil
				removed = removed + 1
			end
		end
		if self.husk_context and self.husk_context.peer_id == peer_id then
			self.husk_context = nil
			removed = removed + 1
		end
		return removed
	end

	-- ONE writer for both style channels (#786 B3/B4). `source` is
	-- "style_channel" (cwv_combat_style_v1) or "identity" (the compact style
	-- rider on the delivering cwv_item_identity payload). Both converge on the
	-- same per-peer/slot state, and only ONE of them starts the rebuild ledger.
	function runtime:accept_style_edge(peer_id, slot_name, family_id, style_id, source,
			descriptor)
		if not M.valid_wire(M.SCHEMA, "state", slot_name, family_id, style_id) then
			return false, nil
		end
		-- Unknown actor must not consume a token, dedupe row, grace or generation.
		if not self:remote_actor_admitted(peer_id, slot_name, nil, family_id, style_id) then return false, nil end
		if descriptor ~= nil and (type(descriptor) ~= "table"
				or descriptor.provider ~= "cwv_style"
				or descriptor.style_family ~= family_id
				or descriptor.style_id ~= style_id
				or type(descriptor.fingerprint) ~= "string"
				or descriptor.fingerprint == "") then
			return false, nil
		end
		if descriptor ~= nil and sword_family(family_id)
				and (not M.is_sword_item(descriptor.base_item_key)
					or not M.is_sword_identity(descriptor)
					or not self:descriptor_actor_admitted(peer_id, slot_name, descriptor)) then return false, nil end
		local by_slot = remote[peer_id] or {}
		remote[peer_id] = by_slot
		local token = family_id .. ":" .. style_id
		local previous = by_slot[slot_name]
		local changed = not previous or previous.token ~= token
		local key = remote_refresh_key(peer_id, slot_name)
		pcall(printf, "[cwv:786] style rx peer=%s slot=%s family=%s style=%s source=%s changed=%s",
			tostring(peer_id), tostring(slot_name), family_id, style_id,
			tostring(source), tostring(changed))
		if source == "identity" then
			local descriptor_changed = descriptor ~= nil and (not previous
				or not previous.descriptor
				or previous.descriptor.fingerprint ~= descriptor.fingerprint)
			by_slot[slot_name] = { family_id = family_id, style_id = style_id,
				token = token, owner = source, descriptor = descriptor }
			-- The identity path is the guarded authority: it carries the item
			-- identity the husk must rebuild against, so it cancels the style
			-- channel's fallback for this exact edge and owns the rebuild --
			-- including when the style channel already stored the same token.
			local armed = self.fallback_remote[key]
			local owned = armed ~= nil and armed.token == token
			self.fallback_remote[key] = nil
			if changed or owned or descriptor_changed
					or not previous or previous.owner ~= "identity" then
				self:refresh_remote(peer_id, slot_name,
					changed and "identity" or "identity_after_style")
				return true, token
			end
			return false, token
		end
		-- Once the identity transaction owns this exact edge, a later duplicate
		-- style-channel message cannot erase its descriptor or arm a weaker
		-- catalogue-derived rebuild.
		if previous and previous.owner == "identity" and not changed then
			return false, token
		end
		by_slot[slot_name] = { family_id = family_id, style_id = style_id,
			token = token, owner = source }
		if not changed then return false, token end
		-- Style-channel arrival. Do NOT rebuild inline: the sender republishes
		-- identity for the same edge in the same tick and that payload is what
		-- the husk must rebuild against. Arm a bounded grace so a peer that only
		-- ever receives this channel (older build, or a dropped identity
		-- payload) still recovers through the same guarded path.
		self.fallback_remote[key] = { peer_id = peer_id, slot_name = slot_name,
			family_id = family_id, style_id = style_id, token = token, elapsed = 0 }
		return changed, token
	end

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
		-- An explicit CWV identity owns its complete authored template. Never
		-- fall through to the clone's inherited vanilla `name`, or native style
		-- families would silently replace custom CWV balance/action graphs.
		if cwv_key ~= nil then return M.member(cwv_key) and cwv_key or nil end
		-- Do not collect these into an ipairs table: optional leading fields are
		-- commonly nil and would stop traversal before the native item name.
		for _, field in ipairs({ "cwv_key", "key", "name", "item_type" }) do
			local value = data and data[field]
			if M.member(value) then return value end
		end
		return nil
	end

	function runtime:describe(item, backend_id, actor)
		local key = item_key(item, backend_id)
		local identity = item_identity(item, backend_id)
		if not key or not identity then return nil end
		if not self:actor_admitted(key, item, backend_id, actor) then return nil end
		local saved = self.store.items[identity]
		local package = self:package(key, saved)
		if not package then return nil end
		local style_id, style, family_id, member = package.style_id, package.style,
			package.family_id, package.member
		return { item_key = key, identity = identity, style_id = style_id, style = style,
			family_id = family_id, member = member, package = package, item_data = item.data or item }
	end

	-- #786: the authored style-family member key for a concrete item. A husk
	-- item carries no backend identity, so the re-wield expectation cannot go
	-- through `describe`. Read-only; returns nil for a non-member item.
	function runtime:member_key(item, backend_id)
		return item_key(item, backend_id)
	end

	function runtime:owns_style(style)
		return M.style_available(style, deps.owns_dlc)
	end

	function runtime:next_style(item_key_value, current)
		local next_id, row, family = M.next_style(item_key_value, current, deps.owns_dlc)
		if not M.is_sword_item(item_key_value) then return next_id, row, family end
		local _, _, member = M.member(item_key_value)
		if not member or not next_id then return next_id, row, family end
		for _ = 1, #member.order do
			if self:package(item_key_value, next_id) then return next_id, row, family end
			next_id, row, family = M.next_style(item_key_value, next_id, deps.owns_dlc)
			if not next_id then break end
		end
		local selected, style = M.style(item_key_value, current)
		return selected, style, family
	end

	function runtime:moveset_indicator(item_key_value, current, compact)
		if M.is_sword_item(item_key_value) then
			local selected, _, _, member = M.style(item_key_value, current)
			local index, total = nil, 0
			for _, id in ipairs(member.order) do
				if self:package(item_key_value, id) then
					total = total + 1
					if id == selected then index = total end
				end
			end
			if not index then return nil end
			return compact and string.format("%d / %d", index, total) or string.format("Moveset %d / %d", index, total)
		end
		return M.moveset_indicator(item_key_value, current, deps.owns_dlc, compact)
	end

	function runtime:resolve_template(item, backend_id)
		local key = item_key(item, backend_id)
		local actor
		if M.is_sword_item(key) and self.husk_context then
			local context = self.husk_context
			if context.family_id == nil or context.style_id == nil then return nil end
			if not self:remote_actor_admitted(context.peer_id, context.slot_name, key, context.family_id, context.style_id) then return nil end
			local package = self:package(key, context.style_id)
			local weapons = rawget(_G, "Weapons")
			return package and weapons and weapons[package.template] or nil
		end
		if M.is_sword_item(key) and actor_admission and actor_admission.creation ~= nil then
			actor = function() return actor_admission:creation_profile(item) end
		end
		local row = self:describe(item, backend_id, actor)
		local weapons = rawget(_G, "Weapons")
		if row then
			if M.is_sword_item(row.item_key) then return weapons and weapons[row.package.template] or nil end
			local descriptor = type(deps.local_style_descriptor) == "function"
				and deps.local_style_descriptor(row.identity) or nil
			local template_name = descriptor
				and descriptor.style_family == row.family_id
				and descriptor.style_id == row.style_id
				and descriptor.effective_template or row.package.template
			return weapons and weapons[template_name] or nil
		end
		-- Remote husk items intentionally have no backend id. The consolidated
		-- husk-wield wrapper supplies a strictly synchronous owner+slot context so
		-- the same BackendUtils seam can select that peer's received style without
		-- ever guessing from a bare base item outside the wield transaction.
		local context = self.husk_context
		local key = context and item_key(item, backend_id)
		local family_id = key and M.member(key)
		if not (context and family_id == context.family_id) then return nil end
		if context.descriptor
				and context.descriptor.base_item_key == key
				and type(context.descriptor.effective_template) == "string" then
			return weapons and weapons[context.descriptor.effective_template] or nil
		end
		local package = self:package(key, context.style_id)
		return package and weapons and weapons[package.template] or nil
	end

	-- Cross-mod contract for WT's 3P remap owner. Return only CWV's authored
	-- active donor template name; the consumer owns validation and native
	-- fallback. Owner items resolve through their exact backend identity. Husk
	-- items resolve their bounded synchronized (peer, slot, family, style) edge
	-- against the concrete item being rendered.
	function runtime:effective_template_name(item, backend_id, owner_unit, slot_name)
		-- Prefer a synchronized remote edge whenever this render owner identifies
		-- one. An incidental backend-like field on a remote payload must not make
		-- this viewer's unrelated persistence/default style authoritative.
		if type(slot_name) == "string" and type(deps.peer_for_owner) == "function" then
			local peer_id = deps.peer_for_owner(owner_unit)
			local remote_row = peer_id and remote[peer_id] and remote[peer_id][slot_name]
			local key = remote_row and item_key(item, backend_id)
			local family_id = key and M.member(key)
			if remote_row and family_id == remote_row.family_id then
				if not self:remote_actor_admitted(peer_id, slot_name, key, family_id, remote_row.style_id) then return nil end
				if M.is_sword_item(key) then
					local package = self:package(key, remote_row.style_id)
					return package and package.template or nil
				end
				if remote_row.descriptor
						and remote_row.descriptor.base_item_key == key then
					return remote_row.descriptor.effective_template
				end
				local package = self:package(key, remote_row.style_id)
				if package then return package.template end
			end
		end
		local row = self:describe(item, backend_id)
		if row and M.is_sword_item(row.item_key) and owner_unit ~= nil
				and (not actor_admission or not actor_admission:is_local_unit(owner_unit)) then return nil end
		if not row then return nil end
		if M.is_sword_item(row.item_key) then return row.package.template end
		local descriptor = type(deps.local_style_descriptor) == "function"
			and deps.local_style_descriptor(row.identity) or nil
		if descriptor and descriptor.style_family == row.family_id
				and descriptor.style_id == row.style_id then
			return descriptor.effective_template
		end
		return row.package.template
	end

	function runtime:begin_husk_wield(inventory, slot_name)
		local owner = inventory and (inventory._unit or inventory.owner_unit)
		local peer_id = type(deps.peer_for_owner) == "function" and deps.peer_for_owner(owner) or nil
		local row = peer_id and remote[peer_id] and remote[peer_id][slot_name]
		if row and not self:remote_actor_admitted(peer_id, slot_name, nil, row.family_id, row.style_id) then row = nil end
		local equipment = inventory and inventory._equipment
		local slot = equipment and equipment.slots and equipment.slots[slot_name]
		local key = slot and item_key(slot.item_data)
		if M.is_sword_item(key) then
			-- A denied/early Sword husk context shadows any viewer-local item.
			self.husk_context = { peer_id = peer_id, slot_name = slot_name,
				family_id = row and row.family_id, style_id = row and row.style_id,
				descriptor = row and row.descriptor }
			return row ~= nil
		end
		self.husk_context = row and { peer_id = peer_id, family_id = row.family_id,
			slot_name = slot_name, style_id = row.style_id, descriptor = row.descriptor } or nil
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
		if M.is_sword_item(row.item_key) then return false end
		if type(deps.local_style_descriptor) == "function"
				and type(deps.style_descriptor_transform) == "function" then
			local descriptor = deps.local_style_descriptor(row.identity)
			if descriptor and descriptor.style_family == row.family_id
					and descriptor.style_id == row.style_id then
				return deps.style_descriptor_transform(descriptor)
			end
		end
		local key = row.package.presentation and row.package.presentation.transform_key
		if key then return presentations[key] or false end
		return false
	end

	-- Read-only-by-convention regression seam for a registered presentation.
	-- Runtime checks must never persist a synthetic exact-instance style merely
	-- to inspect its transform descriptor.
	function runtime:presentation(transform_key)
		return type(transform_key) == "string" and presentations[transform_key] or nil
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
		pcall(type(deps.emit_candidate_diagnostic) == "function" and deps.emit_candidate_diagnostic or printf,
			"[cwv:645] candidate=%s item=%s career=%s owner_event=%s sample=%d/%d reason=%s",
			candidate_id, tostring(item_key_value), tostring(career), source_event,
			count + 1, M.DIAGNOSTIC_EVENT_CAP, candidate.reason)
		return true
	end

	function runtime:remote_transform(owner_unit, slot_name, item)
		if type(deps.peer_for_owner) ~= "function" then return nil end
		local peer_id = deps.peer_for_owner(owner_unit)
		local row = peer_id and remote[peer_id] and remote[peer_id][slot_name]
		if not row then return nil end
		if not self:remote_actor_admitted(peer_id, slot_name, nil, row.family_id, row.style_id) then return nil end
		if sword_family(row.family_id) then return false end
		if row.descriptor and type(deps.style_descriptor_transform) == "function" then
			return deps.style_descriptor_transform(row.descriptor, "3p")
		end
		local presentation
		if item ~= nil then
			local key = item_key(item)
			local family_id = key and M.member(key)
			if family_id ~= row.family_id then return nil end
			local package = self:package(key, row.style_id)
			presentation = package and package.presentation
		else
			-- Compatibility for observation-only callers that do not own the
			-- spawned item. Receiver-specific presentation requires the concrete
			-- member and is resolved by the husk transform consumer below.
			local family = M.FAMILIES[row.family_id]
			local style = family and family.styles[row.style_id]
			presentation = style and style.presentation
		end
		local key = presentation and presentation.transform_key
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
		-- The override is used only by the named #774/#944 runtime regression.
		-- It lets that check drive the exact production transaction with detached
		-- inventory/weapon objects instead of interrupting the player's live item.
		if type(deps.local_equipment) == "function" then
			return deps.local_equipment()
		end
		local pm = rawget(_G, "Managers") and Managers.player
		local player = pm and pm.local_player and pm:local_player(1)
		local unit = player and player.player_unit
		if not unit or not Unit.alive(unit) then return nil end
		local ok, inventory = pcall(ScriptUnit.extension, unit, "inventory_system")
		return ok and inventory or nil, unit
	end

	local function weapon_extension(unit)
		if type(deps.weapon_extension) == "function" then
			return deps.weapon_extension(unit)
		end
		if not unit or not Unit.alive(unit)
				or not ScriptUnit.has_extension(unit, "weapon_system") then return nil end
		local ok, extension = pcall(ScriptUnit.extension, unit, "weapon_system")
		return ok and extension or nil
	end

	function runtime:publish(inventory, slot_name, item, recipient, reason)
		-- inventory is the real event caller, including initial extensions_ready.
		local row = self:describe(item, nil, function() return actor_admission and actor_admission:inventory_profile(inventory, slot_name, item) end)
		if not row then return false end
		local ok = send(recipient, "state", slot_name, row.family_id, row.style_id)
		if ok then pcall(printf, "[cwv:786] style tx slot=%s family=%s style=%s recipient=%s reason=%s",
			tostring(slot_name), row.family_id, row.style_id,
			tostring(recipient or "others"), tostring(reason)) end
		return ok
	end

	-- Owner-side style axis for one of the LOCAL player's slots, resolved
	function runtime:local_descriptor_actor_admitted(descriptor, identity)
		local key = type(descriptor) == "table" and descriptor.base_item_key
		if not M.is_sword_identity(descriptor) then return true end
		local family_id, style_id = descriptor.style_family, descriptor.style_id
		if style_id == nil then family_id, style_id = M.decode_style_rider(descriptor.style or descriptor.style_rider) end
		local inventory = local_equipment()
		local equipment = inventory and inventory:equipment()
		for _, slot_name in ipairs({ "slot_melee", "slot_ranged" }) do
			local slot = equipment and equipment.slots and equipment.slots[slot_name]
			local row = slot and self:describe(slot.item_data)
			if row and row.item_key == key and (identity == nil or row.identity == identity)
					and (descriptor.slot == nil or descriptor.slot == slot_name)
					and (descriptor.provider == "" or (row.family_id == family_id and row.style_id == style_id))
					and (descriptor.effective_template == nil or descriptor.effective_template == row.package.template) then return true end
		end
		return false
	end

	-- exactly the way the #474 musket wire resolves its stance rider (through
	-- `local_equipment`, never a new resolver). `identity_key` is the payload's
	-- own item identity, so a bot payload published from this peer -- or a slot
	-- that changed under the publish -- can never inherit this player's style.
	function runtime:local_style_rider(slot_name, identity_key)
		local inventory = local_equipment()
		local equipment = inventory and inventory:equipment()
		local slot = equipment and equipment.slots and equipment.slots[slot_name]
		local item_data = slot and slot.item_data
		local row = item_data and self:describe(item_data)
		if not row then return nil end
		if identity_key ~= nil and row.item_key ~= identity_key then return nil end
		return M.encode_style_rider(row.family_id, row.style_id)
	end

	function runtime:set_item_style(item, backend_id, desired, reason, rebuild, actor)
		local row = self:describe(item, backend_id, actor)
		if not row then return false, "unsupported item" end
		local resolved, family_ok, descriptor_family = M.style(row.item_key, desired), true, row.family_id == "greatsword"
		if resolved ~= desired then return false, "unsupported style" end
		if not self:package(row.item_key, desired) then return false, "construction unavailable" end
		if type(deps.style_descriptor_family) == "function" then family_ok, descriptor_family = pcall(deps.style_descriptor_family, row.family_id) elseif deps.style_descriptor_family ~= nil then family_ok = false end
		if not family_ok or type(descriptor_family) ~= "boolean" then return false, "appearance family unavailable" end
		local inventory, equipment, slot_name, live_item
		if rebuild then
			inventory = local_equipment()
			equipment = inventory and inventory:equipment()
			slot_name = equipment and equipment.wielded_slot
			local slot = slot_name and equipment.slots and equipment.slots[slot_name]
			live_item = slot and slot.item_data
			local live = live_item and self:describe(live_item)
			if live and live.identity == row.identity then
				local interrupted, detail = M.interrupt_equipment_actions(equipment, weapon_extension)
				if not interrupted then
					pcall(printf, "[cwv:944] style interrupt rejected item=%s reason=%s",
						row.identity, tostring(detail))
					return false, detail
				end
				if detail > 0 then
					pcall(printf, "[cwv:944] style interrupted actions item=%s count=%d",
						row.identity, detail)
				end
			end
		end
		if not self:actor_admitted(row.item_key, item, backend_id, actor) then return false, "actor unavailable" end
		if not self:package(row.item_key, desired) then return false, "construction unavailable" end
		if deps.before_style_commit ~= nil then
			if type(deps.before_style_commit) ~= "function" then return false, "style boundary unavailable" end
			deps.before_style_commit(row, desired)
		end
		local changed, err = M.set(store, row.identity, row.item_key, desired)
		if not changed then return false, err or "unchanged" end
		row.item_data.mod_data = row.item_data.mod_data or {}
		row.item_data.mod_data.cwv_combat_style = desired
		local live_row = live_item and self:describe(live_item)
		if rebuild and live_row and live_row.identity == row.identity and descriptor_family then
			local prepared = false
			if type(deps.prepare_style_descriptor) == "function"
					and equipment and equipment.slots then
				local ok, value = pcall(deps.prepare_style_descriptor, equipment.slots, row.identity, desired)
				prepared = ok and value == true
			end
			if not prepared then
				M.set(store, row.identity, row.item_key, row.style_id)
				row.item_data.mod_data.cwv_combat_style = row.style_id
				pcall(printf,
					"[cwv:660] style transaction rejected item=%s family=%s style=%s reason=descriptor_prepare",
					tostring(row.identity), tostring(row.family_id), tostring(desired))
				return false, "appearance descriptor unavailable"
			end
		end
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
				-- #786 B2: the style axis joins the identity TRANSACTION. The
				-- five scalars above are state only; re-publishing identity on
				-- the same commit is what re-states the item the husk must
				-- rebuild against and drives the guarded re-wield. Same caller
				-- shape as the #474 musket edge, and forced because a style
				-- toggle leaves the identity signature byte-identical.
				if type(deps.send_identity_slots) == "function"
						and equipment and equipment.slots then
					pcall(deps.send_identity_slots, equipment.slots, "combat_style", true)
				end
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

	function runtime:request_item_style(item, backend_id, desired, reason, rebuild, complete, actor)
		local row = self:describe(item, backend_id, actor)
		if not row then return false, "unsupported item" end
		if self.pending[row.identity] then return false, "transition pending" end
		local resolved, style = M.style(row.item_key, desired)
		if resolved ~= desired then return false, "unsupported style" end
		if not self:owns_style(style) then return false, "required DLC unavailable" end
		local package = self:package(row.item_key, desired)
		if not package then return false, "construction unavailable" end
		local resource = package and package.resource
		if not (rebuild and resource) then
			local changed, err = self:set_item_style(item, backend_id, desired, reason, rebuild, actor)
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
			local current = runtime:describe(item, backend_id, actor)
			if not ready or not current or current.identity ~= tx.identity
					or current.item_key ~= tx.item_key or current.style_id ~= tx.from then
				local err = load_err or "stale transition"
				pcall(printf, "[cwv:620] style load rejected item=%s resource=%s reason=%s",
					tx.identity, tx.resource, tostring(err))
				if type(complete) == "function" then complete(false, err) end
				return
			end
			local changed, err = runtime:set_item_style(item, backend_id, tx.desired, reason, rebuild, actor)
			if type(complete) == "function" then complete(changed, err) end
		end
		local ok, accepted, acquire_err = pcall(acquire, resource, finish)
		if not ok or accepted == false then
			finish(false, acquire_err or accepted or "resource load rejected")
			return false, acquire_err or "resource load rejected"
		end
		return true, "transition pending"
	end

	function runtime:cycle_item(item, backend_id, reason, rebuild, complete, actor)
		local row = self:describe(item, backend_id, actor)
		if not row then return false, "unsupported item" end
		local next_id = self:next_style(row.item_key, row.style_id)
		if not next_id or next_id == row.style_id then return false, "no available alternate style" end
		return self:request_item_style(item, backend_id, next_id, reason, rebuild, complete, actor)
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
		local row = self:describe(item, nil, function() return actor_admission and actor_admission:inventory_profile(inventory, slot_name, item) end)
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
			-- #786 B4: this channel keeps state storage, the query/reply replay
			-- and the vanilla-safe fallback, but it no longer triggers its own
			-- unguarded rebuild. `accept_style_edge` dedupes both channels on
			-- one edge token and arms the bounded fallback.
			runtime:accept_style_edge(sender_peer_id, slot_name, family_id, style_id,
				"style_channel")
		end)
	end

	-- Stable dot-call API: cwv.get_effective_combat_style_template_name(item,
	-- backend_id, owner_unit, slot_name). Do not expose the policy catalogue;
	-- sibling consumers must not duplicate or infer style knowledge.
	mod.get_effective_combat_style_template_name = function(item, backend_id,
			owner_unit, slot_name)
		return runtime:effective_template_name(item, backend_id, owner_unit, slot_name)
	end

	return runtime
end

-- The private UI owner receives this policy and its exact row resolver.
function M.install_loadout_ui(mod, runtime, installer)
	if type(installer) ~= "function" then return false end
	return installer(M, console_row, mod, runtime)
end

return M
