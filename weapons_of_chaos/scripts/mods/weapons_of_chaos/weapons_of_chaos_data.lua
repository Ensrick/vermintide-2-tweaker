local mod = get_mod("WOC")
local _moveset = mod:dofile("scripts/mods/weapons_of_chaos/_woc_blightreaper_moveset")

-- VMF widget tree. `enable_blightreaper` gates registration of the Blightreaper
-- item (takes effect on game restart; registration is boot/keep-time). WOC has no
-- debug-logging checkbox: it uses the VMF-native debug channels (mod:debug /
-- mod:warning) gated by VMF output_mode_debug / output_mode_warning, migrated in
-- v0.1.2-dev (PROJECT_STANDARDS.md § 3.6).

-- Blightreaper Combat: attack-order dropdowns consumed by `_woc_attack_order`.
-- Options/defaults come from the single-source chain descriptor; option tables
-- are built fresh per widget and never mutated after registration
-- (docs/VMF_RECIPES.md). Values are unit ids, not engine sub_action names, so a
-- stale user_settings.config entry fails closed to the native order.
local _descriptor = _moveset.chain_descriptor()

local function _fresh_options(units)
	local options = {}
	for i = 1, #units do
		options[i] = { text = units[i].label, value = units[i].id }
	end
	return options
end

local function _native_at(positions, index)
	local native = positions[index]
	return type(native) == "table" and native.native or native
end

local function _combat_widgets()
	local rows = {}
	for i = 1, #_descriptor.light_positions do
		rows[#rows + 1] = {
			setting_id    = "woc_blightreaper_light_" .. i,
			type          = "dropdown",
			default_value = _native_at(_descriptor.light_positions, i),
			tooltip       = "woc_blightreaper_light_tooltip",
			options       = _fresh_options(_descriptor.lights),
		}
	end
	for i = 1, #_descriptor.heavy_positions do
		rows[#rows + 1] = {
			setting_id    = "woc_blightreaper_heavy_" .. i,
			type          = "dropdown",
			default_value = _native_at(_descriptor.heavy_positions, i),
			tooltip       = "woc_blightreaper_heavy_tooltip",
			options       = _fresh_options(_descriptor.heavies),
		}
	end
	-- Push follow-up: the crowbill graph authors exactly ONE follow-up unit
	-- (light_attack_bopp), and VMF hard-rejects dropdowns with fewer than two
	-- options - a single-option widget here aborted the ENTIRE mod's options
	-- init (issue 822 regression, 2026-07-19: no Blightreaper anywhere because
	-- WOC never loaded). Re-add this dropdown only when a second follow-up
	-- unit exists in the descriptor.
	if type(_descriptor.push) == "table" and #_descriptor.push >= 2 then
		rows[#rows + 1] = {
			setting_id    = "woc_blightreaper_push_follow",
			type          = "dropdown",
			default_value = _native_at(_descriptor.push_positions, 1),
			tooltip       = "woc_blightreaper_push_tooltip",
			options       = _fresh_options(_descriptor.push),
		}
	end
	return rows
end

return {
	name           = "Weapons of Chaos",
	description     = mod:localize("mod_description"),
	is_togglable    = true,
	custom_gui_textures = {
		textures = {
			"icon_bg_cursed",
			"icon_wpn_blightreaper",
		},
		ui_renderer_injections = {
			-- `icon_bg_cursed` is an item-card rarity background. Inject it into
			-- the same ten renderer creators proven by CIM's `icon_bg_modded`.
			-- The authored weapon icon keeps its narrower four-renderer contract.
			{ "ingame_ui", "materials/ui/icon_bg_cursed", "materials/ui/icon_wpn_blightreaper" },
			{ "ingame_ui_settings", "materials/ui/icon_bg_cursed" },
			{ "hero_view", "materials/ui/icon_bg_cursed", "materials/ui/icon_wpn_blightreaper" },
			{ "hero_view_state_loot", "materials/ui/icon_bg_cursed" },
			{ "hero_view_state_store", "materials/ui/icon_bg_cursed" },
			{ "hero_view_state_weave_forge", "materials/ui/icon_bg_cursed" },
			{ "start_game_state_settings_overview", "materials/ui/icon_bg_cursed" },
			{ "level_end_view_base", "materials/ui/icon_bg_cursed" },
			{ "level_end_view_versus", "materials/ui/icon_bg_cursed" },
			{ "ui_manager", "materials/ui/icon_bg_cursed" },
			{ "loading_view", "materials/ui/icon_wpn_blightreaper" },
			{ "popup_manager", "materials/ui/icon_wpn_blightreaper" },
		},
	},
	options = {
		widgets = {
			{
				setting_id    = "enable_blightreaper",
				type          = "checkbox",
				default_value = true,
				tooltip       = "enable_blightreaper_tooltip",
			},
			{
				setting_id  = "blightreaper_combat",
				type        = "group",
				sub_widgets = _combat_widgets(),
			},
		},
	},
}
