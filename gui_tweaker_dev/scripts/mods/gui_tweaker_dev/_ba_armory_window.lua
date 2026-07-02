local mod = get_mod("gut_dev")

-- ============================================================================
-- Armory in-menu window (Compendium, #217 follow-up) -- opens EXACTLY like the
-- vanilla Equipment/Talents/Cosmetics tabs: a WINDOW LAYOUT inside
-- HeroViewStateOverview, not a separate HeroViewState. Clicking the Armory tab
-- selects this layout via the overview's own set_layout_by_name (the same call
-- HeroWindowPanelConsole._on_panel_button_selected makes for vanilla tabs,
-- hero_window_panel_console.lua:452), so the tab strip + chrome stay put and ESC
-- behaves like the other tabs. No hero_view re-enter -> no #223 hero_view_hdr crash.
--
-- Vanilla layout mechanism mirrored: the console layout module
-- (hero_window_layout_console.lua) exports `windows` (name -> {class_name,...}) and
-- `window_layouts` (array of {name, windows = {win_name = position_index}}). The
-- overview captures both by reference in _setup_menu_layout
-- (hero_view_state_overview.lua:143-157), and set_layout composes the windows for a
-- layout (:368-408) by `rawget(_G, class_name):new()` + window:on_enter(params).
-- We register a `gut_armory` window + layout entry into those shared module tables
-- (same technique as the tab injection), so `set_layout_by_name("gut_armory")`
-- composes panel(tabs) + background(chrome) + our HeroWindowArmory content window.
--
-- Rendering is atlas-safe (rect/border/text/hotspot primitive passes only, drawn on
-- the window's ui_renderer like every vanilla window) -- avoids the raw-material Gui
-- crash class (reference_vt2_options_widgets_raw_materials). Button sound goes
-- through the parent chain's wwise world (reference_vt2_ui_button_sound_use_window).
-- ============================================================================

local UIRenderer   = UIRenderer
local UISceneGraph = UISceneGraph
local UIWidget     = UIWidget

local provider = mod:dofile("scripts/mods/gui_tweaker_dev/_ba_weapon_provider")

local LAYOUT_MODULE = "scripts/ui/views/hero_view/states/hero_window_layout_console"

-- Geometry (screen-space, from top-left of the 1920x1080 fit root).
local ROW_H       = 26
local LIST_X      = 90
local LIST_TOP    = 150
local LIST_W      = 460
local DETAIL_X    = 600
local DETAIL_TOP  = 150
local DETAIL_W    = 780
local MAX_DETAIL_LINES = 46

local COLOR_TITLE  = { 255, 255, 215, 90 }
local COLOR_HEADER = { 255, 255, 200, 120 }
local COLOR_STAT   = { 255, 210, 222, 236 }
local COLOR_TEXT   = { 255, 198, 198, 198 }

-- ----------------------------------------------------------------------------
-- Widget builders (primitive passes only).
-- ----------------------------------------------------------------------------
local function _text_widget(node, text, size, color, halign)
	return UIWidget.init({
		scenegraph_id = node,
		element = { passes = { { pass_type = "text", style_id = "text", text_id = "text" } } },
		content = { text = text or "" },
		style = { text = {
			font_type = "hell_shark", font_size = size, localize = false, upper_case = false,
			horizontal_alignment = halign or "left", vertical_alignment = "center",
			text_color = color, offset = { 0, 0, 2 },
		} },
		offset = { 0, 0, 0 },
	})
end

local function _row_button_widget(node, label)
	return UIWidget.init({
		scenegraph_id = node,
		element = { passes = {
			-- style_id REQUIRED so the hotspot uses style.hotspot.size, not node size
			-- (reference_vt2_options_widgets_raw_materials).
			{ pass_type = "hotspot", content_id = "hotspot", style_id = "hotspot" },
			{ pass_type = "rect",    style_id = "hl" },
			{ pass_type = "text",    style_id = "text", text_id = "text" },
		} },
		content = { hotspot = {}, text = label or "?" },
		style = {
			hotspot = { size = { LIST_W, ROW_H }, offset = { 0, 0, 0 } },
			-- alpha driven per-frame in update (0 idle / hover / selected)
			hl   = { color = { 0, 120, 150, 170 }, offset = { 0, 0, 1 } },
			text = { font_type = "hell_shark", font_size = 20, localize = false, upper_case = false,
				horizontal_alignment = "left", vertical_alignment = "center",
				text_color = { 255, 220, 220, 220 }, offset = { 10, 0, 3 } },
		},
		offset = { 0, 0, 0 },
	})
end

-- ----------------------------------------------------------------------------
-- Data helpers.
-- ----------------------------------------------------------------------------

-- Live, career-eligible weapon list for a hero (provider already dedupes cosmetics
-- and sorts melee-then-ranged by localized name). Career filter uses the engine's
-- own can_wield source of truth.
local function _career_weapons(hero, career_name)
	local list = provider.get_by_hero(hero)
	local out = {}
	for _, meta in ipairs(list) do
		if not career_name or (meta.can_wield and table.contains(meta.can_wield, career_name)) then
			out[#out + 1] = meta
		end
	end
	return out
end

-- The player's LIVE scaled cleave power level, so cleave counts reflect their actual
-- gear. All engine-sourced; pcall-guarded so a keep-time edge (no active difficulty
-- etc.) degrades to nil (cleave shown as "-") rather than erroring.
local function _resolve_cleave_power(hero_name, career_name)
	local power = 300
	local backend = rawget(_G, "BackendUtils")
	if backend and backend.get_total_power_level and career_name then
		local ok, p = pcall(backend.get_total_power_level, hero_name, career_name)
		if ok and type(p) == "number" and p > 0 then power = p end
	end
	local difficulty = "cataclysm"
	local ok_d, d = pcall(function()
		return Managers and Managers.state and Managers.state.difficulty and Managers.state.difficulty:get_difficulty()
	end)
	if ok_d and d then difficulty = d end
	local action_utils = rawget(_G, "ActionUtils")
	if action_utils and action_utils.scale_power_levels then
		local ok, scaled = pcall(action_utils.scale_power_levels, power, "cleave", nil, difficulty)
		if ok and type(scaled) == "number" then return scaled end
	end
	return nil
end

-- Build the right-panel detail lines for a weapon. Every number comes from the
-- provider's live template reads.
local function _build_detail_lines(meta, cleave_power)
	local lines = {}
	local function push(text, color, size)
		lines[#lines + 1] = { text = text, color = color or COLOR_TEXT, size = size or 20 }
	end

	push(string.format("%s  (%s)", tostring(meta.display_name),
		meta.slot_type == "ranged" and "Ranged" or "Melee"), COLOR_TITLE, 26)
	push("", COLOR_TEXT, 8)

	local stats = provider.get_base_stats(meta.item_name)
	if stats then
		push(string.format("Dodge: %d  (%+.0f%% distance)", stats.dodge_count or 1, stats.dodge_bonus or 0), COLOR_STAT)
		if stats.slot_type == "melee" then
			if stats.stamina then
				push(string.format("Stamina: %.0f shields", stats.stamina), COLOR_STAT)
			end
			if stats.block_angle then
				push(string.format("Block: %d deg   fatigue x%.1f inner / x%.1f outer",
					stats.block_angle, stats.block_inner or 1, stats.block_outer or 2), COLOR_STAT)
			end
			if stats.push_radius then
				push(string.format("Push: radius %.1f   arc %s / %s deg", stats.push_radius,
					tostring(stats.push_angle or "-"), tostring(stats.outer_push_angle or "-")), COLOR_STAT)
			end
		else
			if stats.max_ammo then
				push(string.format("Ammo: %d per clip, %d total   reload %.2fs",
					stats.ammo_per_clip or 1, stats.max_ammo, stats.reload_time or 0), COLOR_STAT)
			elseif stats.max_overcharge then
				push(string.format("Overcharge: %d max", stats.max_overcharge), COLOR_STAT)
			end
		end
	end

	push("", COLOR_TEXT, 8)
	push("Attacks", COLOR_HEADER, 22)
	local rows = provider.get_attack_rows(meta.item_name, cleave_power)
	for _, r in ipairs(rows) do
		local cleave = ""
		if r.cleave_damage then
			cleave = string.format("   cleave %.1f dmg / %.1f stagger", r.cleave_damage, r.cleave_stagger or 0)
		end
		local special = (r.special ~= "") and ("   [" .. r.special .. "]") or ""
		push(string.format("%s  (%s)%s%s", r.label, r.profile, cleave, special), COLOR_TEXT)
	end

	return lines
end

-- ----------------------------------------------------------------------------
-- HeroWindowArmory (vanilla hero-window lifecycle: on_enter/on_exit/update/
-- post_update/draw, drawn on ctx.ui_top_renderer like every console window).
-- ----------------------------------------------------------------------------
HeroWindowArmory = class(HeroWindowArmory)
HeroWindowArmory.NAME = "HeroWindowArmory"

HeroWindowArmory.on_enter = function (self, params, offset)
	self.parent = params.parent
	local ctx = params.ingame_ui_context
	self.ingame_ui_context = ctx
	self.ui_renderer = ctx.ui_top_renderer or ctx.ui_renderer
	self.render_settings = { snap_pixel_positions = true }

	local hero_name = params.hero_name
	local career_index = params.career_index
	local profile_index = FindProfileIndex(hero_name)
	local profile = profile_index and SPProfiles[profile_index]
	local career = profile and profile.careers and profile.careers[career_index]
	self._career_name = career and career.name
	self._hero = (self._career_name and string.sub(self._career_name, 1, 2)) or "es"
	self._cleave_power = _resolve_cleave_power(hero_name, self._career_name)
	self._weapons = _career_weapons(self._hero, self._career_name)
	self._selected_node = nil

	self:create_ui_elements(params, offset)

	printf("[gut:217] armory window on_enter: career=%s weapons=%d cleave_power=%s",
		tostring(self._career_name), #self._weapons, tostring(self._cleave_power))
end

HeroWindowArmory.create_ui_elements = function (self, params, offset)
	local sg = { root = { is_root = true, scale = "fit", size = { 1920, 1080 }, position = { 0, 0, 0 } } }

	local node_i = 0
	local function add_node(x, y, w)
		node_i = node_i + 1
		local id = "arm_n_" .. node_i
		sg[id] = {
			parent = "root", vertical_alignment = "top", horizontal_alignment = "left",
			size = { w, ROW_H }, position = { x, -y, 6 },
		}
		return id
	end

	-- List rows (headers + weapon buttons), stacked from the top of the list area.
	self._rows = {}
	local y = LIST_TOP
	local last_slot = nil
	for _, meta in ipairs(self._weapons) do
		if meta.slot_type ~= last_slot then
			local hnode = add_node(LIST_X, y, LIST_W)
			y = y + ROW_H
			self._rows[#self._rows + 1] = {
				kind = "header", node = hnode,
				label = (meta.slot_type == "ranged") and "RANGED" or "MELEE",
			}
			last_slot = meta.slot_type
		end
		local rnode = add_node(LIST_X, y, LIST_W)
		y = y + ROW_H
		self._rows[#self._rows + 1] = { kind = "weapon", node = rnode, meta = meta }
	end

	-- Detail lines (fixed pool; text set on selection).
	self._detail_nodes = {}
	for i = 1, MAX_DETAIL_LINES do
		self._detail_nodes[i] = add_node(DETAIL_X, DETAIL_TOP + (i - 1) * ROW_H, DETAIL_W)
	end

	self.ui_scenegraph = UISceneGraph.init_scenegraph(sg)

	-- Widgets.
	self._list_widgets = {}
	for _, row in ipairs(self._rows) do
		if row.kind == "header" then
			row.widget = _text_widget(row.node, row.label, 20, COLOR_HEADER, "left")
		else
			row.widget = _row_button_widget(row.node, row.meta.display_name or row.meta.item_name)
		end
		self._list_widgets[#self._list_widgets + 1] = row.widget
	end

	self._detail_widgets = {}
	for i = 1, MAX_DETAIL_LINES do
		self._detail_widgets[i] = _text_widget(self._detail_nodes[i], "", 20, COLOR_TEXT, "left")
	end

	-- Initial prompt in the detail panel.
	self._detail_widgets[1].content.text = "Select a weapon to view its stats."
	self._detail_widgets[1].style.text.text_color = COLOR_HEADER

	UIRenderer.clear_scenegraph_queue(self.ui_renderer)
end

HeroWindowArmory._select = function (self, row)
	self._selected_node = row.node
	pcall(function() self.parent:play_sound("play_gui_equipment_equip_hero") end)

	local lines = _build_detail_lines(row.meta, self._cleave_power)
	for i = 1, MAX_DETAIL_LINES do
		local w = self._detail_widgets[i]
		local ln = lines[i]
		if ln then
			w.content.text = ln.text
			w.style.text.text_color = ln.color
			w.style.text.font_size = ln.size
		else
			w.content.text = ""
		end
	end
	printf("[gut:217] armory select: %s (%s)", tostring(row.meta.item_name), tostring(row.meta.slot_type))
end

HeroWindowArmory.update = function (self, dt, t)
	-- Row highlight (selected > hover > idle).
	for _, row in ipairs(self._rows) do
		if row.kind == "weapon" and row.widget then
			local hs = row.widget.content.hotspot
			local alpha = 0
			if row.node == self._selected_node then
				alpha = 95
			elseif hs.is_hover then
				alpha = 45
			end
			row.widget.style.hl.color[1] = alpha
		end
	end
	self:draw(dt)
end

HeroWindowArmory.post_update = function (self, dt, t)
	self:_handle_input(dt, t)
end

HeroWindowArmory._handle_input = function (self, dt, t)
	for _, row in ipairs(self._rows) do
		if row.kind == "weapon" and row.widget then
			local hs = row.widget.content.hotspot
			if hs.on_release or hs.on_left_release then
				hs.on_release = false
				hs.on_left_release = false
				self:_select(row)
			end
		end
	end
end

HeroWindowArmory.draw = function (self, dt)
	local ui_renderer = self.ui_renderer
	local ui_scenegraph = self.ui_scenegraph
	if not (ui_renderer and ui_scenegraph) then return end
	local input_service = self.parent:window_input_service()
	UIRenderer.begin_pass(ui_renderer, ui_scenegraph, input_service, dt, nil, self.render_settings)
	if self._list_widgets then
		for i = 1, #self._list_widgets do UIRenderer.draw_widget(ui_renderer, self._list_widgets[i]) end
	end
	if self._detail_widgets then
		for i = 1, #self._detail_widgets do UIRenderer.draw_widget(ui_renderer, self._detail_widgets[i]) end
	end
	UIRenderer.end_pass(ui_renderer)
end

HeroWindowArmory.on_exit = function (self, params)
	self._list_widgets = nil
	self._detail_widgets = nil
	self._rows = nil
	self.ui_scenegraph = nil
end

-- ----------------------------------------------------------------------------
-- Layout registration + open helper (mutates the shared console-layout module,
-- same technique as the tab injection). Idempotent.
-- ----------------------------------------------------------------------------
function mod._gut_ensure_armory_layout()
	local layout = package and package.loaded and package.loaded[LAYOUT_MODULE]
	local windows = layout and layout.windows
	local window_layouts = layout and layout.window_layouts
	if type(windows) ~= "table" or type(window_layouts) ~= "table" then
		return false
	end
	if windows.gut_armory then
		return true
	end
	windows.gut_armory = { class_name = "HeroWindowArmory", ignore_alignment = true, name = "gut_armory" }
	for i = 1, #window_layouts do
		if window_layouts[i].name == "gut_armory" then
			return true
		end
	end
	window_layouts[#window_layouts + 1] = {
		name = "gut_armory",
		close_on_exit = true,
		sound_event_enter = "play_gui_equipment_button",
		sound_event_exit = "play_gui_equipment_close",
		windows = { panel = 1, background = 2, gut_armory = 3 },
	}
	printf("[gut:217] registered gut_armory in-menu window layout")
	return true
end

-- Open the Armory as an in-menu window layout on the given HeroViewStateOverview
-- (the panel window's self.parent). Returns true on success.
function mod._gut_open_armory_layout(overview)
	if not (overview and overview.set_layout_by_name) then
		return false
	end
	if not mod._gut_ensure_armory_layout() then
		printf("[gut:217] armory layout module not ready; cannot open in-menu")
		return false
	end
	local ok = pcall(overview.set_layout_by_name, overview, "gut_armory")
	if ok then
		printf("[gut:217] armory opened as in-menu window layout")
		return true
	end
	printf("[gut:217] set_layout_by_name('gut_armory') raised")
	return false
end

return { class_name = "HeroWindowArmory" }
