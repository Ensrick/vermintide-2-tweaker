local mod = get_mod("gut")

-- ============================================================================
-- Mod Tweaker — HeroView SUB-STATE (KEEP path)
-- ============================================================================
-- A second presentation of the Mod Tweaker that lives INSIDE the already-open
-- hero_view as a sub-state (modeled on HeroViewStateCompendium / the old Armory
-- mod's HeroViewStateArmory), instead of as a standalone IngameUI view reached by
-- leaving + re-entering hero_view.
--
-- WHY THIS EXISTS (build 2, v0.2.57-dev). The standalone ModTweakerView
-- (_mod_tweaker_view.lua) exited via ingame_ui:transition_with_fade(...), which
-- RECREATES hero_view's renderer; VMF then re-injects Loremaster's Armoury's
-- armoury_atlas into the fresh renderer, a C-level fatal (crash 42c81d84), AND
-- the recreation dumped the player into the deprecated bare IngameView menu. A
-- HeroView sub-state never leaves hero_view and never recreates the renderer, so
-- it kills BOTH symptoms. The standalone view STAYS as the in-mission path (there
-- is no hero_view in a mission); this sub-state is the keep/inn path only.
--
-- The DATA / REGISTRY / DRAW / INPUT substance is ported verbatim from
-- _mod_tweaker_view.lua — only the lifecycle shell changes to the sub-state
-- contract (renderer borrowed from ctx, input read from the parent's shared
-- service, exit via parent:close_menu, no self-made input service / cursor push).

local defs = mod:dofile("scripts/mods/gui_tweaker/_mod_tweaker_definitions")
local ordering = mod:dofile("scripts/mods/gui_tweaker/_mod_tweaker_ordering")

local UIRenderer = UIRenderer
local UISceneGraph = UISceneGraph
local math = math

-- ---------------------------------------------------------------
-- Registry access (through the controller — single source of truth)
-- ---------------------------------------------------------------

local function _mt()
    return mod.mod_tweaker
end

-- Depth-aware nested walk (gut's NESTED/controller categories). Flattens the tree
-- into `out` + a PARALLEL `depths` array so the drill-down detection logic can run
-- the SAME "next node is deeper" test the VMF flat path uses (VMF already ships a
-- `depth` field; gut's hand-authored tree does not, so we synthesize it here). A
-- node with sub_widgets is appended AND its children are appended at depth+1 — the
-- build loop then skips those children inline (a group collapses them; a non-group
-- parent gets a gear that drills into them).
local function _walk_nested(node, out, depths, d)
    if type(node) ~= "table" then return end
    if type(node.setting_id) == "string" then
        out[#out + 1] = node
        depths[#depths + 1] = d
    end
    if type(node.sub_widgets) == "table" then
        for i = 1, #node.sub_widgets do _walk_nested(node.sub_widgets[i], out, depths, d + 1) end
    end
    if type(node.widgets) == "table" then
        for i = 1, #node.widgets do _walk_nested(node.widgets[i], out, depths, d) end
    end
end

-- ---------------------------------------------------------------
-- VMF auto-discovery. Every installed VMF mod becomes a tab populated from its
-- REAL options, edited live on the real mod object. VMF ships as bytecode, so the
-- runtime shape was reverse-engineered (workflow 2026-06-18): mods are in
-- get_mod("VMF")._mods_unloading_order; each mod's FLATTENED widget list is in
-- get_mod("VMF").options_widgets_data, matched by list[1].mod_name. Field reads
-- are defensive (flat OR content-wrapped) + pcall-guarded so an unexpected shape
-- degrades gracefully instead of crashing — the [mt] debug dump reveals reality.
-- ---------------------------------------------------------------
local MAX_TABS = 8   -- tab nodes that fit the window width; >MAX => paginate

-- The Mod Tweaker is for the USER'S OWN mods only — there isn't room for a tab per
-- installed VMF mod. Whitelist of this author's mod ids (new_mod registration ids).
-- verminious_dreams_lighting (+ _dev) are intentionally OMITTED — they keep their
-- own normal VMF menu and don't belong as a Mod Tweaker tab.
local _MY_MODS = {
    gut = true, gut_dev = true, wt = true, ct = true, ct_dev = true, gt = true, gt_dev = true,
    cim = true, cim_dev = true, crt = true, cosmetics_tweaker = true,
    dynamic_cosmetic_portraits = true, enemy_tweaker = true,
    character_weapon_variants = true, event_tweaker = true, mp = true, bt = true,
}

local function _nf(node, key)  -- defensive node-field read
    if type(node) ~= "table" then return nil end
    local v = node[key]
    if v == nil and type(node.content) == "table" then v = node.content[key] end
    return v
end

-- (#389) Stable keep-substate twin of the Mod Tweaker foreign-slider registry.
local STEP_OVERRIDES = {
    cim = { base_power_level = 25 }, cim_dev = { base_power_level = 25 },
    ct = { starting_coins = 25 }, ct_dev = { starting_coins = 25 },
}

local function _resolve_step(node, mod_id, setting_id, dec)
    local field = _nf(node, "step")
    if type(field) == "number" and field > 0 then return field end
    local by_mod = mod_id and STEP_OVERRIDES[mod_id]
    local fixed = by_mod and setting_id and by_mod[setting_id]
    if type(fixed) == "number" and fixed > 0 then return fixed end
    return (dec and dec > 0) and (10 ^ -dec) or 1
end

local function _vmf_label(node, mod_obj)
    local t = _nf(node, "title") or _nf(node, "text") or _nf(node, "setting_id") or "?"
    -- title may be a raw loc key or already display text; localize and keep the
    -- result only if it isn't a "<missing>" marker (works either way).
    if mod_obj and mod_obj.localize then
        local ok, s = pcall(mod_obj.localize, mod_obj, t)
        if ok and type(s) == "string" and s ~= "" and not string.find(s, "^<") then t = s end
    end
    return tostring(t)
end

local function _cat_get(category, setting_id)
    if category.mod_obj then
        local ok, v = pcall(category.mod_obj.get, category.mod_obj, setting_id)
        return ok and v or nil
    end
    local MT = _mt()
    return MT and MT:get(category.mod_id, setting_id)
end

local function _cat_set(category, setting_id, value)
    if category.mod_obj then
        -- 3rd arg true => fire the mod's on_setting_changed so it reacts live
        -- (matches stock VMF options behaviour). Persistence is automatic.
        pcall(category.mod_obj.set, category.mod_obj, setting_id, value, true)
        return
    end
    local MT = _mt()
    if MT then MT:set(category.mod_id, setting_id, value) end
end

-- Native menu sound feedback. The real Options menu fires Wwise events on the
-- view's wwise_world: "Play_hud_select" on a commit (options_view.lua:544 etc.)
-- and "Play_hud_hover" on hover-enter (options_view.lua:423 etc.). We resolve a
-- wwise_world off the music_world (pcall-guarded; a missing world is silent, never
-- a crash). A one-time debug probe logs which worlds expose a usable wwise_world,
-- so if Play_hud_* are inaudible the log shows whether the handle resolved.
local _wwise_probed = false
local function _wwise_world()
    local world = Managers.world and Managers.world:world("music_world")
    return world and World.wwise_world(world)
end
local function _wwise_probe()
    if _wwise_probed then return end
    _wwise_probed = true
    pcall(function()
        local names = { "music_world", "top_ingame_view", "level_world" }
        for i = 1, #names do
            local w = Managers.world and Managers.world:has_world(names[i]) and Managers.world:world(names[i])
            local ww = w and World.wwise_world(w)
            mod:info("[mt:wwise] world '%s' present=%s wwise_world=%s",
                names[i], tostring(w ~= nil), tostring(ww ~= nil))
        end
    end)
end
local function _play_event(event)
    pcall(function()
        local ww = _wwise_world()
        if ww then WwiseWorld.trigger_event(ww, event) end
    end)
end
-- Commit/click sound (checkbox flip, arrow click, dropdown cycle, slider release).
local function _play_click() _play_event("Play_hud_select") end
-- Hover sound — fire on the EDGE (hover-enter) only, never every frame.
local function _play_hover() _play_event("Play_hud_hover") end

local function _vmf_categories()
    local out = {}
    local vmf = get_mod("VMF")
    if not vmf then return out end

    -- VMF is bytecode; field names are reverse-engineered. Probe once (debug only)
    -- so the log reveals the real shape if these guesses are wrong.
    if not vmf._gut_mt_probed then
        vmf._gut_mt_probed = true
        local tk = {}
        for k, v in pairs(vmf) do if type(v) == "table" then tk[#tk + 1] = tostring(k) end end
        mod:debug("[mt] vmf table fields: {%s}", table.concat(tk, ", "))
        local wd = vmf.options_widgets_data
        if type(wd) == "table" then
            mod:debug("[mt] vmf options_widgets_data: %d mod lists", #wd)
            -- header (n,1) + first real setting node (n,2) for whichever list has one
            for li = 1, math.min(#wd, 4) do
                local list = wd[li]
                if type(list) == "table" and type(list[2]) == "table" then
                    local nk = {}
                    for k, v in pairs(list[2]) do nk[#nk + 1] = tostring(k) .. "=" .. type(v) end
                    mod:debug("[mt] vmf node[%d][2] (%s) keys: {%s}", li,
                        tostring(_nf(list[1], "mod_name")), table.concat(nk, ", "))
                    break
                end
            end
        end
    end

    -- Iterate the per-mod widget lists directly (confirmed in-game 2026-06-19).
    -- Each entry is one mod's flattened widget list: list[1] is a synthesized
    -- header carrying mod_name + readable_mod_name; list[2..] are the setting
    -- nodes. The owning mod object (for get/set) is get_mod(mod_name).
    local widget_data = vmf.options_widgets_data
    if type(widget_data) ~= "table" then return out end
    for _, list in ipairs(widget_data) do
        local header = (type(list) == "table") and list[1]
        local mod_name = header and _nf(header, "mod_name")
        if type(mod_name) == "string" and _MY_MODS[mod_name] then
            local mod_obj = get_mod(mod_name)
            local label = _nf(header, "readable_mod_name") or mod_name
            local enabled = true
            if mod_obj and mod_obj.is_enabled then
                local ok_en, en = pcall(mod_obj.is_enabled, mod_obj)
                if ok_en then enabled = en and true or false end
            end
            out[#out + 1] = {
                mod_id = mod_name, label = label, widgets = list,
                mod_obj = mod_obj, enabled = enabled, _flat = true,
            }
        end
    end
    table.sort(out, function(a, b)
        if a.enabled ~= b.enabled then return a.enabled end
        return tostring(a.label) < tostring(b.label)
    end)
    return out
end

HeroViewStateModTweaker = class(HeroViewStateModTweaker)
HeroViewStateModTweaker.NAME = "HeroViewStateModTweaker"

-- ---------------------------------------------------------------
-- STAGED-CHANGE model (v0.2.70-dev). Native Options stages every edit in
-- `changed_user_settings` and only writes live on APPLY (options_view.lua:1789-1939,
-- 3129-3196). gut used to write live via _cat_set on EVERY change. These four helpers
-- convert it to staged:
--   * stage_set   — a row edit writes here (NOT _cat_set), into the per-category buffer.
--   * get_staged  — a row read/repaint prefers the staged value, falling back to live.
--   * _update_apply_button — recomputes the APPLY button's enabled/greyed state from
--                            whether the ACTIVE category's buffer is non-empty.
--   * apply_pending — the APPLY click; the ONLY place _cat_set runs (commits the buffer).
-- The buffer is keyed by mod_id (stable string), so it survives the category-table
-- rebuild on a tab switch and isolates per category.
-- ---------------------------------------------------------------

-- Stable buffer key for a category (the category table is rebuilt on _rebuild; the
-- mod_id string is stable across rebuilds).
local function _cat_key(category)
    return category and category.mod_id or "?"
end

-- Stage one edit into the per-category pending buffer (replaces the live _cat_set on
-- every row edit). Records the value + refreshes the APPLY button dirty state.
function HeroViewStateModTweaker:stage_set(category, setting_id, value)
    local key = _cat_key(category)
    self._pending[key] = self._pending[key] or {}
    self._pending[key][setting_id] = value
    -- NOTE: do NOT set self._dirty here. self._dirty drives the auto-save-to-log on exit,
    -- which must reflect LIVE writes only — a pending (unapplied) edit was never written,
    -- so exiting with only-pending edits must NOT export. apply_pending sets _dirty.
    self:_update_apply_button()
end

-- Read a setting's EFFECTIVE value: the staged value if one is pending, else the live
-- value passed in (which the caller read via _cat_get). Mirrors native _get_setting
-- (assigned(pending, live)).
function HeroViewStateModTweaker:get_staged(category, setting_id, live_value)
    local p = self._pending[_cat_key(category)]
    if p and p[setting_id] ~= nil then return p[setting_id] end
    return live_value
end

-- True if the ACTIVE category has any pending edit (drives APPLY enabled/greyed).
function HeroViewStateModTweaker:_active_category_dirty()
    local cat = self._categories and self._categories[self._selected]
    local p = cat and self._pending[_cat_key(cat)]
    return (p ~= nil) and (next(p) ~= nil)
end

-- Recompute the APPLY button's disabled flag from the active category's buffer.
function HeroViewStateModTweaker:_update_apply_button()
    if self._apply then self._apply.content.disabled = not self:_active_category_dirty() end
end

-- APPLY: commit the whole pending buffer for `category` through the existing _cat_set
-- path (the ONLY place _cat_set runs on edit — a stray slider drag never takes effect
-- until clicked), clear the buffer, grey the button, and repaint the rows from the new
-- live values. Native handle_apply_button -> apply_changes (options_view.lua:1919).
function HeroViewStateModTweaker:apply_pending(category)
    local key = _cat_key(category)
    local p = self._pending[key]
    if not p or next(p) == nil then return end
    for id, value in pairs(p) do _cat_set(category, id, value) end
    self._pending[key] = {}
    self._dirty = true   -- a LIVE write happened -> export the TOML on exit
    self:_update_apply_button()
    -- Rebuild the rows so each reads its new live value (the mod's on_setting_changed
    -- may have snapped/clamped further, e.g. ct's 25-coin rounding).
    self:_build_rows(category)
    _play_click()
    mod:debug("[mt:apply] committed pending buffer for '%s'", tostring(key))
end

-- ---------------------------------------------------------------
-- Lifecycle (sub-state contract — driven by HeroView, NOT IngameUI)
-- ---------------------------------------------------------------
-- on_enter reads the borrowed renderer from params.ingame_ui_context and captures
-- the parent (HeroView) for input + close. NEVER creates a renderer, NEVER pushes
-- the cursor (HeroView owns it), NEVER makes its own modal input service.

HeroViewStateModTweaker.on_enter = function (self, params)
    self.parent = params.parent
    local ctx = params.ingame_ui_context
    self.ingame_ui_context = ctx
    self.ui_renderer       = ctx.ui_renderer
    self.ui_top_renderer   = ctx.ui_top_renderer or ctx.ui_renderer
    self.input_manager     = ctx.input_manager
    self.voting_manager    = ctx.voting_manager
    self.ingame_ui         = ctx.ingame_ui
    self.render_settings   = { alpha_multiplier = 1, snap_pixel_positions = false }

    self.ui_scenegraph = UISceneGraph.init_scenegraph(defs.scenegraph_definition)

    -- Static chrome built once (the native window).
    self._chrome    = defs.build_chrome()
    self._exit      = defs.build_exit_button()
    self._scrollbar = defs.build_scrollbar_rect()
    -- (v0.2.70-dev) STAGED-CHANGE model. Edits write to a per-category PENDING buffer
    -- (self._pending[mod_id][setting_id] = staged_value) instead of live; the APPLY
    -- button (bottom-right) commits the whole buffer via _cat_set. Keyed by mod_id (a
    -- stable string) NOT the category table — category tables are rebuilt on every
    -- _rebuild (_vmf_categories re-creates them), so keying by the table would lose the
    -- buffer on a tab switch. mod_id survives, and gives per-category isolation for free.
    self._pending   = self._pending or {}
    self._apply     = defs.create_apply_button()
    -- v0.2.65-dev: no "MOD TWEAKER" title widget — native Options has none and the
    -- tab strip now spans the full top band (see defs: mt_title node + build_title
    -- factory removed).
    self._hint      = defs.build_hint("")

    self._tabs = {}
    self._rows = {}
    self._selected = 1

    -- Scroll state (the list scrolls like the vanilla settings menu: a pixel offset
    -- on the mt_list node + position-culling against list_mask + the rect scrollbar).
    self._scroll_y = 0        -- pixel offset applied to mt_list.offset[2]
    self._max_scroll = 0      -- content_height - visible_height (>= 0)
    self._content_h = 0       -- total stacked row height
    self._visible_h = 0       -- list_mask height (read at runtime)
    self._sb_dragging = false -- scrollbar thumb being dragged
    self._drill = nil         -- gear drill-down state: nil = normal list; { setting_id, label } = drilled in

    self._draw_frames = 0
    self._dirty = false

    -- DEFENSIVE re-pin LA's atlas + instrument on every open (sub-state site).
    -- Even though a sub-state never recreates hero_view's renderer (the whole point
    -- of this build), the keepalive re-pin is cheap and pcall-guarded, and keeps the
    -- has_loaded force-load guard intact (NEVER force-loads a non-resident LA
    -- package). `self` here is the HeroViewStateModTweaker, whose
    -- ui_renderer/ui_top_renderer are logged by the probe to prove the borrowed
    -- renderer is the SAME instance across opens (it is, because we never recreate it).
    if mod._gut_mt_repin_la then pcall(mod._gut_mt_repin_la, self, "substate_on_enter") end

    self:_rebuild()
    self:_dump_state("substate_on_enter"); self:_dump_scrollbar("substate_on_enter"); _wwise_probe()
    -- Native menu-open feedback — the exact event both vanilla OptionsView.on_enter
    -- (options_view.lua:1615) and the VMF options view fire when the settings menu
    -- opens. Routed through the parent hero_view's play_sound (its wwise_world is the
    -- reliable handle at the keep). pcall-guarded, so a missing/renamed Wwise event is
    -- silent, never a crash. Matches the view twin's _play_open() for parity.
    pcall(function() self:play_sound("Play_hud_button_open") end)
    mod:info("[mt] HeroViewStateModTweaker entered (sub-state)")
end

HeroViewStateModTweaker.update = function (self, dt, t)
    local input_service = self:input_service()
    if not input_service then return end

    self:_draw(dt, input_service)

    self._draw_frames = (self._draw_frames or 0) + 1
    if self._draw_frames % 120 == 1 then
        local ok_sb, sbp = pcall(UISceneGraph.get_world_position, self.ui_scenegraph, defs.scrollbar_sg)
        local sbc = self._scrollbar and self._scrollbar.content
        local sbhs = sbc and sbc.hotspot
        mod:debug("[mt:dump] heartbeat frame=%d rows=%d scroll=%d/%d vis_h=%s cont_h=%d thumb_frac=%s scroll_value=%s sb_world=%s sb_hover=%s sb_held=%s",
            self._draw_frames, #self._rows, math.floor(self._scroll_y or 0), math.floor(self._max_scroll or 0),
            tostring(self._visible_h), math.floor(self._content_h or 0),
            sbc and tostring(sbc.thumb_frac) or "nil", sbc and tostring(sbc.scroll_value) or "nil",
            (ok_sb and sbp) and string.format("{%d,%d}", sbp[1], sbp[2]) or "?",
            tostring(sbhs and sbhs.is_hover), tostring(sbhs and sbhs.is_held))
    end

    -- A mission-start vote closes the menu (matches the compendium).
    if self:_has_active_level_vote() then
        self:close_menu(true)
        return
    end

    -- ESC / back / toggle closes the SUB-STATE (returns to whatever hero_view screen
    -- we came from). This is the key difference vs the standalone view: NO
    -- transition_with_fade("ingame_menu") — that's what produced the deprecated look.
    if input_service:get("toggle_menu", true) or input_service:get("back", true) then
        -- (v0.2.69-dev) ESC priority while a DROPDOWN POPUP is open: the FIRST ESC closes
        -- the popup (no commit) instead of closing the menu / leaving the drill.
        if self._open_dropdown then
            self:_close_dropdown_popup()
            _play_click()
            return
        end
        -- ESC priority while TYPE-EDITING (v0.2.66-dev): the FIRST ESC cancels the active
        -- numeric edit (restores the value) instead of closing the menu / leaving the drill.
        if self._editing_row then
            self:_cancel_edit(self._editing_row)
            return
        end
        -- ESC priority: if drilled into a setting's advanced options, the FIRST ESC
        -- drills OUT (back to the normal list); only a second ESC closes the menu.
        if self._drill then
            self._drill = nil
            self._scroll_y = 0
            _play_click()
            self:_build_rows(self._categories[self._selected])
            return
        end
        self:close_menu()
        return
    end

    self:_handle_input(input_service)
end

HeroViewStateModTweaker.post_update = function (self, dt, t) end

HeroViewStateModTweaker.input_service = function (self)
    -- The SHARED hero_view input service (HeroView manages devices + the cursor);
    -- we never make our own. Exactly the compendium pattern.
    return self.parent:input_service()
end

HeroViewStateModTweaker.play_sound = function (self, event)
    if self.parent and self.parent.play_sound then self.parent:play_sound(event) end
end

HeroViewStateModTweaker._has_active_level_vote = function (self)
    local vm = self.voting_manager
    if not vm then return false end
    local active = vm:vote_in_progress()
    local is_mission = active == "game_settings_vote" or active == "game_settings_deed_vote"
    return is_mission and not vm:has_voted(Network.peer_id())
end

HeroViewStateModTweaker.close_menu = function (self, ignore_sound)
    -- (v0.2.82-dev — ITEM 1) Native menu-close feedback to match the standalone view +
    -- the real OptionsView (options_view.lua:1691/:2594 fire Play_hud_button_close). Was
    -- Play_gui_achivements_menu_close (a different, achievements-screen close sound); use
    -- the settings-menu event so both Mod Tweaker presentations close with the same sound.
    if not ignore_sound then pcall(function() self:play_sound("Play_hud_button_close") end) end
    if self.parent and self.parent.close_menu then
        self.parent:close_menu(nil, true)
    end
end

HeroViewStateModTweaker.on_exit = function (self)
    -- Auto-save: if any setting changed while open, emit the TOML to the log so the
    -- companion watcher writes gut_mod_settings.toml (the mod can't write directly).
    -- PRESERVED from the standalone view's on_exit — exiting the sub-state must still
    -- persist edits.
    if self._dirty then
        self._dirty = false
        pcall(function()
            if mod._export_settings_to_log then mod._export_settings_to_log(true) end
        end)
    end
    self._widgets = nil
    self._widgets_by_name = nil
    self.ui_scenegraph = nil
    self._chrome = nil
    self._tabs = nil
    self._rows = nil
    self._scrollbar = nil
    self._exit = nil
    self._hint = nil
    self._apply = nil
    -- (v0.2.70-dev) DISCARD pending edits on exit. Nothing was written live (staged-change
    -- model), so discard = drop the buffer — no native apply_changes(original_*) re-apply
    -- is needed (that exists only for native's live video-preview). Unapplied edits vanish.
    self._pending = {}
end

-- ---------------------------------------------------------------
-- Build the row widgets for a category. VMF categories carry a FLAT node array;
-- gut's own dogfood category is NESTED (walk it). Every factory call is pcall'd
-- so one bad node can't blank the view. Editable: checkbox, numeric (stepper),
-- dropdown (option cycler). Read-only: group titles, keybind, text, unknown.
-- ---------------------------------------------------------------
-- (v0.2.82-dev — ITEM 5) Vertical gap inserted ABOVE each top-level (depth-0) group
-- header in the normal list (except the first row), so consecutive top-level
-- collapsible sections read as visually separated like the vanilla options sections.
-- Child rows inside a section are untouched (intra-section spacing stays tight). px.
-- TWIN of the standalone view's TOP_SECTION_GAP — keep both in sync.
local TOP_SECTION_GAP = 14
-- Build ONE row widget for a single settings node `w`. Factored out of _build_rows
-- so both the normal list AND the gear drill-down view (Back + parent + children)
-- build child rows through the identical path (no new persistence — _cat_get/_cat_set
-- and the same checkbox/slider/dropdown factories). Returns (row, err); row may be nil
-- (header) — that's not an error. `base_offset` is decremented by the factory.
-- `depth` (0-based nesting level) is threaded into the factories so nested child rows
-- get a per-depth LEFT-label indent (v0.2.67-dev). Defaults to 0 for the unindented
-- top level; the controls (arrows/value/track/gear) stay column-aligned regardless.
-- (v0.2.75-dev) Stable group expand/collapse key for a node, shared by _build_node_row
-- (which stores it on the group row) AND the drill planner's is_expanded predicate (which
-- must agree on the EXACT same key, or an expanded group reads as collapsed and its
-- children — incl. nested dropdowns — never render). Mirrors the original inline gid.
function HeroViewStateModTweaker:_group_key(w, category)
    local setting_id = _nf(w, "setting_id")
    local label = category._flat and _vmf_label(w, category.mod_obj)
                  or tostring(w.label or w.text or w.setting_id or "?")
    return (category.mod_id or "?") .. ":" .. tostring(setting_id or label)
end

function HeroViewStateModTweaker:_build_node_row(w, category, base_offset, depth)
    depth = depth or 0
    local setting_id = _nf(w, "setting_id")
    local wtype = _nf(w, "type")
    local label = category._flat and _vmf_label(w, category.mod_obj)
                  or tostring(w.label or w.text or w.setting_id or "?")
    local row, err

    if wtype == "header" then
        row = nil  -- VMF synthesizes a per-mod header; the tab already names the mod.
    elseif wtype == "group" then
        -- Collapsible group header (default COLLAPSED). The caller handles expand state.
        local gid = self:_group_key(w, category)
        local expanded = self._expanded[gid] and true or false
        local ok, r = pcall(defs.create_group_header, label, expanded, base_offset, depth)
        if ok and r then row = r; row._is_group = true; row._group_key = gid else err = r end
    elseif wtype == "checkbox" or wtype == "boolean" then
        local ok, r = pcall(defs.create_checkbox, label, base_offset, depth)
        if ok and r then
            row = r
            -- (v0.2.70-dev) buffer-first: show the staged value if an edit is pending.
            local live = _cat_get(category, setting_id)
            row.content.flag = self:get_staged(category, setting_id, live) and true or false
            row._last_flag = row.content.flag
        else err = r end
    elseif wtype == "slider" or wtype == "numeric" then
        local ok, r = pcall(defs.create_slider, label, "", base_offset, depth)
        if ok and r then
            row = r
            local range = _nf(w, "range")
            local min = (range and range[1]) or _nf(w, "min") or 0
            local max = (range and range[2]) or _nf(w, "max") or 1
            local dec = _nf(w, "decimals_number") or _nf(w, "num_decimals") or _nf(w, "decimals") or 0
            -- (v0.2.70-dev) buffer-first: show the staged value if an edit is pending.
            local val = self:get_staged(category, setting_id, _cat_get(category, setting_id))
            if type(val) ~= "number" then val = min end
            row.content.min, row.content.max, row.content.num_decimals = min, max, dec
            row.content.value = val
            row.content.internal_value = (max > min) and math.clamp((val - min) / (max - min), 0, 1) or 0
            -- ±step for the [<]/[>] glyphs: ~range/40 (coarse), at least the natural
            -- increment. The track gives fine/continuous control; after a commit we
            -- re-read the value so any mod-side snapping (ct rounds starting_coins to
            -- 25 in its on_setting_changed) is reflected — matching VMF's own slider.
            local step = _resolve_step(w, category and category.mod_id, setting_id, dec)
            row.content.step = step
            mod:debug("[mt:num] '%s' bounds=%s..%s dec=%s step=%s val=%s",
                tostring(setting_id), tostring(min), tostring(max), tostring(dec), tostring(step), tostring(val))
            row.content.value_text = string.format("%." .. dec .. "f", val)
            row._last_value = val
        else err = r end
    elseif wtype == "dropdown" then
        -- (v0.2.69-dev) REAL dropdown: a collapsed row (label + selected value + single
        -- down arrow) that opens a popup option list on click. Was a slider-arrow carousel.
        local options = _nf(w, "options")
        local ok, r = pcall(defs.create_dropdown, label, base_offset, depth)
        if ok and r and type(options) == "table" and #options > 0 then
            row = r
            -- (v0.2.70-dev) buffer-first: show the staged selection if an edit is pending.
            local cur = self:get_staged(category, setting_id, _cat_get(category, setting_id))
            local values, texts, idx = {}, {}, 1
            for k = 1, #options do
                local o = options[k]
                values[k] = _nf(o, "value")
                texts[k] = tostring(_nf(o, "text") or values[k])
                if values[k] == cur then idx = k end
            end
            row._options_values, row._options_texts, row._option_idx = values, texts, idx
            row.content.value_text = texts[idx]
            row.content.active = false        -- popup closed at build time
        elseif ok and r then
            row = r; row._readonly = true; row.content.value_text = "?"
        else err = r end
    else
        -- keybind / text / unknown: read-only label + current value.
        local val = setting_id and _cat_get(category, setting_id)
        local suffix = (val ~= nil) and (": " .. tostring(val))
                       or (wtype and ("  [" .. tostring(wtype) .. "]") or "")
        local ok, r = pcall(defs.create_section_title, label .. suffix, base_offset, depth)
        if ok and r then row = r; row._readonly = true else err = r end
    end

    if row then
        row._mod_id = category.mod_id
        row._setting_id = setting_id
        row._wtype = wtype
        row._category = category
        row._list_y = base_offset[2]  -- this row's Y (factory just decremented to it)
    end
    return row, err, wtype, setting_id, label
end

-- Append a row (+ optional gear) to self._rows and log build failures. Shared tail
-- of every row append so the drill view and normal list stay byte-identical.
function HeroViewStateModTweaker:_append_row(row, err, wtype, category, setting_id, base_offset, has_gear, parent_label)
    if row then
        self._rows[#self._rows + 1] = row
        if has_gear then
            -- Shrink the parent's full-width whole-row hotspot so it stops BEFORE the
            -- gear column — otherwise a click on the gear ALSO lands on the parent row's
            -- hotspot (they overlap) and would e.g. toggle a parent checkbox while
            -- drilling. The arrow/track hotspots sit left of the gear and are untouched.
            if row.style and row.style.hotspot and row.style.hotspot.size then
                row.style.hotspot.size[1] = math.max(1, (defs.row_w or 800) - (defs.gear_col_w or 50))
            end
            -- 3rd-column gear: a SEPARATE widget at the SAME row Y; clicking it drills in.
            local ok, g = pcall(defs.create_gear_button, base_offset[2])
            if ok and g then
                g._is_gear = true
                g._list_y = base_offset[2]
                g._drill_setting = setting_id
                g._drill_label = parent_label or tostring(setting_id)
                g._category = category
                self._rows[#self._rows + 1] = g
            end
        end
    elseif wtype ~= "header" then
        mod:warning("[mt] row build failed for %s.%s (type=%s): %s",
            tostring(category.mod_id), tostring(setting_id), tostring(wtype), tostring(err))
    end
end

local function _order_category_nodes(category, nodes, depths)
    return ordering.order_flat(nodes, depths, {
        preserve_all = category.mod_id == "gut_equipment",
        get_type = function(node) return _nf(node, "type") end,
        is_generated_header = function(node) return _nf(node, "mod_name") ~= nil end,
        get_label = function(node) return _vmf_label(node, category.mod_obj) end,
        has_explicit_order = function(node)
            return _nf(node, "mod_tweaker_preserve_order") == true
                or _nf(node, "mod_tweaker_order") ~= nil
                or _nf(node, "mod_tweaker_before") ~= nil
                or _nf(node, "mod_tweaker_after") ~= nil
                or _nf(node, "depends_on") ~= nil
                or _nf(node, "dependency") ~= nil
        end,
    })
end

function HeroViewStateModTweaker:_build_rows(category)
    self._rows = {}
    -- Any in-progress type-edit is abandoned on a rebuild (tab switch / drill / collapse):
    -- the old row widget is discarded here, so drop the dangling editor reference too.
    self._editing_row = nil
    -- (v0.2.69-dev) An open dropdown popup is likewise abandoned on a rebuild — its
    -- collapsed row widget is being discarded, so drop the dangling open-dropdown refs.
    self._open_dropdown = nil
    self._dd_list = nil
    if not category or type(category.widgets) ~= "table" then return end
    self._expanded = self._expanded or {}   -- group_key -> true (expanded); default collapsed

    -- Flatten into parallel node + depth arrays. The VMF flat list ships its own
    -- `depth`; the gut nested tree gets a synthesized depth from _walk_nested. Both
    -- then feed the SAME drill-detection ("the next node is deeper") + inline-skip.
    local nodes, depths = {}, {}
    if category._flat then
        for i = 1, #category.widgets do
            nodes[#nodes + 1] = category.widgets[i]
            depths[#depths + 1] = _nf(category.widgets[i], "depth") or 0
        end
    else
        for i = 1, #category.widgets do _walk_nested(category.widgets[i], nodes, depths, 0) end
    end
    nodes, depths = _order_category_nodes(category, nodes, depths)

    local base_offset = { 0, -10, 0 }

    -- DRILLED-IN advanced view: render only Back + parent + that parent's children.
    if self._drill then
        local ok_b, back = pcall(defs.create_back_row, self._drill.label, base_offset)
        if ok_b and back then
            back._is_back = true
            back._list_y = base_offset[2]
            self._rows[#self._rows + 1] = back
        end
        -- Re-locate the parent node by setting_id (the widget list is stable across
        -- rebuilds), render it (no gear — we're already inside it), then its children.
        local p_idx
        for i = 1, #nodes do
            if _nf(nodes[i], "setting_id") == self._drill.setting_id then p_idx = i; break end
        end
        if p_idx then
            -- Drilled-in: the parent + its descendants are shown as a flat list with the
            -- parent at depth 0 (the Back row supplies the context). (v0.2.75-dev) The
            -- child rows come from the SHARED plan_drill_children planner, which walks the
            -- WHOLE subtree with the normal list's group-collapse / gear-parent rules — so a
            -- dropdown nested THREE deep (VMF wt anim picker: checkbox -> set-group ->
            -- per-attack dropdown) is finally built and its options surface. The old loop
            -- rendered the parent's DIRECT children only (`depths[j] == pdepth + 1`), so the
            -- depth-3 dropdown nodes never existed as rows (the "no options" symptom).
            local prow, perr, pwtype, psid = self:_build_node_row(nodes[p_idx], category, base_offset, 0)
            self:_append_row(prow, perr, pwtype, category, psid, base_offset, false)
            local pdepth = depths[p_idx]
            local plan = defs.plan_drill_children(nodes, depths, p_idx, pdepth,
                function(node) return _nf(node, "type") end,
                function(node, _flat_depth, _row_depth)
                    -- A group is expanded iff the user toggled its [+]/[-]. Use the SAME
                    -- _group_key _build_node_row stamps onto the group row, so the planner
                    -- and the rendered row agree. Default collapsed.
                    return self._expanded[self:_group_key(node, category)] and true or false
                end)
            for k = 1, #plan do
                local p = plan[k]
                local crow, cerr, cwtype, csid, clabel =
                    self:_build_node_row(nodes[p.index], category, base_offset, p.depth)
                self:_append_row(crow, cerr, cwtype, category, csid, base_offset, p.has_gear, clabel)
            end
        end
        self._content_h = math.abs(base_offset[2]) + 20
        self:_recompute_scroll_bounds()
        self._scroll_y = math.clamp(self._scroll_y or 0, 0, self._max_scroll)
        return
    end

    -- NORMAL list. A node has children when the NEXT node is deeper (flat) or it's a
    -- non-group node with sub_widgets (nested → _walk_nested already deepened them, so
    -- the same "next is deeper" test holds). A group COLLAPSES its children inline (the
    -- existing [+]/[-] behaviour); a non-group PARENT skips its children inline and
    -- shows a GEAR that drills into them.
    local skip_below = nil   -- depth: while set, skip deeper nodes (collapsed group OR gear parent)
    for i = 1, #nodes do
        local w = nodes[i]
        local depth = depths[i]
        local skip = skip_below and depth > skip_below

        -- Inside a collapsed group / gear parent: render nothing until we climb out.
        if not skip then
            skip_below = nil
            local wtype = _nf(w, "type")
            local has_children = (depths[i + 1] ~= nil) and (depths[i + 1] > depth)
            -- (v0.2.82-dev — ITEM 5) Vertical padding BETWEEN top-level collapsible sections.
            -- Decrement the running offset by TOP_SECTION_GAP before a depth-0 group header so
            -- a gap opens above it — but ONLY when content already exists above (skip the gap
            -- before the FIRST row). Applied before _build_node_row decrements base_offset by
            -- ROW_H so the gap lands above the header. Top-level ONLY (child rows untouched).
            -- TWIN of the standalone view's identical block — keep both in sync.
            if wtype == "group" and depth == 0 and #self._rows > 0 then
                base_offset[2] = base_offset[2] - TOP_SECTION_GAP
            end
            local row, err, _wt, setting_id, label = self:_build_node_row(w, category, base_offset, depth)

            if wtype == "group" then
                -- Group: collapsible (no gear). Skip descendants inline while collapsed.
                local expanded = row and self._expanded[row._group_key] and true or false
                self:_append_row(row, err, wtype, category, setting_id, base_offset, false)
                if not expanded then skip_below = depth end
            -- Exclude "header": the VMF per-mod header node is immediately followed by
            -- ALL the mod's (deeper) setting nodes, so without this guard the header is
            -- treated as a gear-parent and skip_below hides EVERY setting -> rows=0 blank
            -- menu (build-4 gear regression; fixed v0.2.61-dev).
            elseif has_children and wtype ~= "header" then
                -- Non-group parent with nested options: GEAR + skip children inline.
                self:_append_row(row, err, wtype, category, setting_id, base_offset, true, label)
                skip_below = depth
            else
                self:_append_row(row, err, wtype, category, setting_id, base_offset, false)
            end
        end
    end

    -- Total content height (origin -10 down to the last row's Y, + bottom pad), then
    -- recompute how far we can scroll and clamp the current offset into range.
    self._content_h = math.abs(base_offset[2]) + 20
    self:_recompute_scroll_bounds()
    self._scroll_y = math.clamp(self._scroll_y or 0, 0, self._max_scroll)
end

-- Visible window height = list_mask height (read at runtime); max scroll is how far
-- the content overflows it.
--
-- (v0.2.80-dev) BOTTOM SCROLL PADDING. A dropdown opened on a row near the bottom of
-- the list drops DOWNWARD from its row (create_dropdown_list anchors the popup one
-- ROW_H below the collapsed row and descends); the popup is drawn outside the row-cull
-- loop so it's NOT clipped to list_mask, but when the row is already at the bottom of
-- the scroll range there's no headroom to scroll that row UP into view, so the open
-- popup hangs past the panel's bottom edge with nothing behind it. Burned the wt anim
-- picker's per-attack dropdown (Sienna's Mace). Fix: extend the scrollable content by a
-- fixed empty-space pad so max_scroll grows and any near-bottom row can be scrolled up
-- far enough that its open popup fits inside the visible list. The pad is empty space
-- below the last real row (the user scrolls into it). Sized to comfortably clear the
-- tallest popup (DD_MAX_ROWS * DD_ROW_H ~= 10*24 = 240px) plus a margin — TUNABLE.
-- _content_h itself is extended so the scrollbar thumb_frac (visible/_content_h, draw
-- path) stays correct: the thumb just gets a bit smaller, which is fine.
local BOTTOM_SCROLL_PAD = 300   -- px of empty scroll headroom below the last row (tunable)
function HeroViewStateModTweaker:_recompute_scroll_bounds()
    local ok, s = pcall(UISceneGraph.get_size, self.ui_scenegraph, defs.list_mask_sg)
    self._visible_h = (ok and s and s[2]) or 700
    -- Add the empty-space pad ONLY when the real row stack already overflows the visible
    -- window — so a short list whose rows all fit doesn't grow a spurious scrollbar / phantom
    -- scroll into empty space. When it does overflow, the pad gives the headroom to scroll a
    -- near-bottom row (and its open dropdown) up into view. Idempotent per rebuild: _build_rows
    -- resets _content_h to the unpadded row-stack height immediately before calling this, so
    -- the pad is applied exactly once per recompute, never compounded.
    if (self._content_h or 0) > self._visible_h then
        self._content_h = self._content_h + BOTTOM_SCROLL_PAD
    end
    self._max_scroll = math.max(0, (self._content_h or 0) - self._visible_h)
    -- (v0.2.77-dev) Fire the scrollbar probe once per overflow-state TRANSITION (none ->
    -- overflow or back) so the next in-game repro captures the OVERFLOW state — on_enter
    -- alone often samples before the list has overflowed. Guarded so it fires on the edge,
    -- not every recompute (this runs on every row rebuild).
    local overflowing = self._max_scroll > 0
    if overflowing ~= self._sb_probe_overflowing then
        self._sb_probe_overflowing = overflowing
        self:_dump_scrollbar(overflowing and "scroll-bound:overflow" or "scroll-bound:fits")
    end
end

local function _truncate(s, n)
    s = tostring(s or "")
    if #s > n then return string.sub(s, 1, n - 1) .. "." end
    return s
end

-- Per-mod tab-label overrides (keyed by mod_id, both stable + dev ids). An entry
-- here REPLACES the derived label outright (applied BEFORE the "Tweaker: " prefix
-- strip + truncation), so the tab reads EXACTLY the override string. Extend by
-- adding a `<mod_id> = "LABEL"` line. gt/gt_dev are deliberately absent — their
-- VMF name already reads "General", so the prefix-strip path yields "General".
local _TAB_LABEL_OVERRIDE = {
    cim = "CRAFTING", cim_dev = "CRAFTING",
}

function HeroViewStateModTweaker:_rebuild()
    -- Every VMF mod becomes a category (gut included, via its real settings);
    -- then any controller-registered category VMF didn't already provide.
    local cats = {}
    local seen = {}
    local ok_vmf, vmf_cats = pcall(_vmf_categories)
    if ok_vmf and type(vmf_cats) == "table" then
        for _, c in ipairs(vmf_cats) do cats[#cats + 1] = c; seen[c.mod_id] = true end
    end
    local MT = _mt()
    for _, c in ipairs((MT and MT:list_categories()) or {}) do
        if not seen[c.mod_id] then cats[#cats + 1] = c; seen[c.mod_id] = true end
    end

    -- Pin priority mods to the front of the tab strip (v0.2.56). General Tweaker
    -- ("gt" stable / "gt_dev" dev) is the leftmost tab regardless of the source
    -- ordering above; everything else keeps its existing relative order. Implemented
    -- as a STABLE partition keyed by an explicit priority list so it's trivial to
    -- extend later (lower index = further left). A mod gets the priority of whichever
    -- of its ids is present; non-listed mods sort after all listed ones, order kept.
    local TAB_PRIORITY = { "gt", "gt_dev" }
    local _prio_rank = {}
    for i = 1, #TAB_PRIORITY do _prio_rank[TAB_PRIORITY[i]] = i end
    do
        local pinned, rest = {}, {}
        for _, c in ipairs(cats) do
            if _prio_rank[c.mod_id] then pinned[#pinned + 1] = c else rest[#rest + 1] = c end
        end
        -- Stable order among pinned mods follows the priority list index.
        table.sort(pinned, function(a, b)
            return (_prio_rank[a.mod_id] or math.huge) < (_prio_rank[b.mod_id] or math.huge)
        end)
        local ordered = {}
        for _, c in ipairs(pinned) do ordered[#ordered + 1] = c end
        for _, c in ipairs(rest) do ordered[#ordered + 1] = c end
        cats = ordered
    end

    self._all_categories = cats

    -- (v0.2.71-dev) Paginate the top tab strip ONLY when the MEASURED total tab width
    -- overflows the strip — NOT on a fixed tab COUNT. Tabs are text-aware (variable width,
    -- see _layout_tabs), so the old `total > MAX_TABS` over-paginated (showed a "More 1/2"
    -- tab) even when every label comfortably fit. Pre-measure each label the SAME way
    -- _layout_tabs does (the create_tab text style is hell_shark / size 20 / upper_case;
    -- UIFontByResolution + UIRenderer.text_size + a literal 20px gap each) and sum; if the
    -- sum fits the usable strip (panel width minus the x0 anchor minus a right margin for
    -- the exit-X / More tab), DON'T paginate — show all tabs (per_page = total). The
    -- measure is pcall-guarded; a borrowed-renderer failure falls back to "fits" (measured
    -- stays 0 -> not paged), the desired default now that the set fits. MAX_TABS survives
    -- only as the per-page size for the rare genuine overflow.
    local total = #cats
    local TAB_X0, RIGHT_MARGIN, GAP = 65, 120, 20
    local strip_w = (defs.window and defs.window.w or 1400) - TAB_X0 - RIGHT_MARGIN
    local measured = 0
    pcall(function()
        local renderer = self.ui_top_renderer or self.ui_renderer
        if not renderer then return end
        -- Match create_tab's text style exactly (defs create_tab: hell_shark/20/upper_case).
        local ts = { font_type = "hell_shark", font_size = 20, upper_case = true }
        local font, scaled = UIFontByResolution(ts)
        for _, c in ipairs(cats) do
            local override = _TAB_LABEL_OVERRIDE[c.mod_id]
            local lbl
            if override then
                lbl = override
            else
                local raw = tostring(c.label or c.mod_id):gsub("^Tweaker:%s*", "")
                lbl = _truncate(raw, 16)
            end
            if c.enabled == false then lbl = lbl .. "*" end
            if TextToUpper then lbl = TextToUpper(lbl) end
            measured = measured + UIRenderer.text_size(renderer, lbl, font[1], scaled) + GAP
        end
    end)
    local paged = measured > strip_w
    local per_page = paged and (MAX_TABS - 1) or total
    self._page_count = paged and math.ceil(total / per_page) or 1
    self._page = math.clamp(self._page or 0, 0, math.max(0, self._page_count - 1))

    self._categories = {}
    local start_i = self._page * per_page
    for k = 1, per_page do
        local c = cats[start_i + k]
        if c then self._categories[k] = c end
    end
    self._selected = math.clamp(self._selected or 1, 1, math.max(1, #self._categories))

    self._tabs = {}
    for i = 1, #self._categories do
        local cat = self._categories[i]
        -- A label override (e.g. cim/cim_dev -> "CRAFTING") wins outright and is
        -- applied BEFORE the prefix-strip/truncate so the tab reads exactly the
        -- override; otherwise drop the "Tweaker: " prefix (this menu is all my
        -- tweaker mods) and truncate to fit the tab.
        local override = _TAB_LABEL_OVERRIDE[cat.mod_id]
        local lbl
        if override then
            lbl = override
        else
            local raw = tostring(cat.label or cat.mod_id):gsub("^Tweaker:%s*", "")
            lbl = _truncate(raw, 16)
        end
        if cat.enabled == false then lbl = lbl .. "*" end
        local tab = defs.create_tab(lbl, i)
        if tab then self._tabs[i] = tab end
    end
    self._more_tab_index = nil
    if paged then
        local idx = #self._categories + 1
        local more = defs.create_tab(string.format("More %d/%d >", self._page + 1, self._page_count), idx)
        if more then self._tabs[idx] = more; self._more_tab_index = idx end
    end

    -- (v0.2.67-dev) Text-aware tab widths: measure each label + pack left-to-right with a
    -- 20px gap, exactly like native (options_view.lua:986-994). Replaces the fixed-width
    -- TAB_W slots so short mod names don't leave huge dead gaps between tabs.
    self:_layout_tabs()

    self:_build_rows(self._categories[self._selected])

    if total == 0 then
        self._hint.content.text = "No mods with options found."
    elseif paged then
        self._hint.content.text = string.format(
            "%d mods, page %d/%d.  Last tab = next page.  Click a setting; ESC closes.  ( * = mod disabled )",
            total, self._page + 1, self._page_count)
    else
        self._hint.content.text = "Click a tab to pick a mod.  Click a checkbox / use [<] [>].  ESC closes.  ( * = disabled )"
    end

    mod:debug("[mt] rebuild: total=%d page=%d/%d displayed=%d selected=%d rows=%d",
        total, self._page + 1, self._page_count, #self._categories, self._selected, #self._rows)
end

-- ---------------------------------------------------------------
-- (v0.2.67-dev) Measure each tab's label width and pack the tabs left-to-right with a
-- 20px gap, mirroring native OptionsView._setup_text_buttons_width (options_view.lua:986-
-- 994 / 997-1027): width = first return of UIRenderer.text_size(renderer, text, font[1],
-- scaled_font_size) where font,scaled = UIFontByResolution(text_style); x = running total;
-- running += width + 20. We write each tab scenegraph node's size[1] (= measured width)
-- and local_position[1] (= packed x). The whole thing is pcall-guarded — a borrowed-
-- renderer measure failure leaves the fixed-width fallback layout untouched.
-- ---------------------------------------------------------------
function HeroViewStateModTweaker:_layout_tabs()
    local renderer = self.ui_top_renderer or self.ui_renderer
    local sg = self.ui_scenegraph
    if not (renderer and sg and self._tabs) then return end
    pcall(function()
        -- Anchor: the first tab node's original packed x (= TAB_X0 = 65 from the defs).
        local first_node = sg["mt_tab_1"]
        local total = (first_node and first_node.local_position and first_node.local_position[1]) or 65
        for i = 1, #self._tabs do
            local tab = self._tabs[i]
            local node = sg["mt_tab_" .. i]
            if tab and node then
                local ts = tab.style and tab.style.text
                local text = tostring(tab.content.text or "")
                -- Match the rendered string: tabs are upper_case (TextToUpper), no localize.
                if ts and ts.upper_case and TextToUpper then text = TextToUpper(text) end
                local font, scaled = UIFontByResolution(ts)
                local w = UIRenderer.text_size(renderer, text, font[1], scaled)
                node.size[1] = w
                node.local_position[1] = total
                total = total + w + 20   -- literal 20px gap (options_view.lua:993)
            end
        end
    end)
end

-- ---------------------------------------------------------------
-- Render-state probe (debug-gated). Logs on-screen geometry so the log alone
-- shows whether elements are positioned/sized/visible — no screenshot needed.
-- ---------------------------------------------------------------
function HeroViewStateModTweaker:_dump_state(reason)
    local sg = self.ui_scenegraph
    local function wp(id)
        local ok, p = pcall(UISceneGraph.get_world_position, sg, id)
        if ok and p then return string.format("{%.0f,%.0f,%.0f}", p[1], p[2], p[3]) end
        return "?"
    end
    local function sz(id)
        local ok, s = pcall(UISceneGraph.get_size, sg, id)
        if ok and s then return string.format("{%.0f,%.0f}", s[1], s[2]) end
        return "?"
    end
    mod:info("[mt:dump] (%s) substate categories=%d selected=%d tabs=%d rows=%d chrome=%d exit=%s scrollbar=%s",
        tostring(reason),
        #(self._categories or {}), self._selected or -1, #(self._tabs or {}), #(self._rows or {}),
        #(self._chrome or {}), tostring(self._exit ~= nil), tostring(self._scrollbar ~= nil))
    mod:info("[mt:dump] world: background=%s(%s) top_panel=%s(%s) list_mask=%s(%s) list_start=%s | screen=1920x1080",
        wp("background"), sz("background"), wp("background_top_panel"), sz("background_top_panel"),
        wp("list_mask"), sz("list_mask"), wp("mt_list_start"))
    for i = 1, math.min(#(self._tabs or {}), 8) do
        mod:info("[mt:dump]   tab[%d] '%s' world=%s", i, tostring(self._tabs[i].content.text_field), wp("mt_tab_" .. i))
    end
    for i = 1, math.min(#(self._rows or {}), 12) do
        local row = self._rows[i]
        local off = row.style and row.style.offset
        mod:info("[mt:dump]   row[%d] type=%s id=%s flag=%s value=%s offset=%s",
            i, tostring(row._wtype), tostring(row._setting_id),
            tostring(row.content.flag), tostring(row.content.value),
            off and string.format("{%.0f,%.0f}", off[1], off[2]) or "?")
    end
end

-- ---------------------------------------------------------------
-- Scrollbar probe (v0.2.73-dev, debug-gated, INSTRUMENT ONLY — no behavior change).
-- TWIN of ModTweakerView:_dump_scrollbar (standalone in-mission view). Logs the REAL
-- runtime scrollbar render-state so the next in-game repro reveals (a) the actual menu
-- background color to contrast the bar against (the prior "fix" INFERRED ~{10,10,10}
-- from a comment — never measured; the real `background` chrome rect is {255,15,15,15},
-- panels are {10,10,10}), (b) whether the bar is drawn at all and WHERE (on-screen vs
-- off-panel / behind a widget), and (c) whether the thumb height is sane. Fired once per
-- open from the SAME site as _dump_state.
-- ---------------------------------------------------------------
function HeroViewStateModTweaker:_dump_scrollbar(reason)
    local sg = self.ui_scenegraph
    local function wp(id)
        local ok, p = pcall(UISceneGraph.get_world_position, sg, id)
        if ok and p then return string.format("{%.0f,%.0f,%.0f}", p[1], p[2], p[3]) end
        return "?"
    end
    local function sz(id)
        local ok, s = pcall(UISceneGraph.get_size, sg, id)
        if ok and s then return string.format("{%.0f,%.0f}", s[1], s[2]) end
        return "?"
    end
    local function color_of(style_tbl)
        if type(style_tbl) ~= "table" then return "?" end
        local c = style_tbl.color
        if type(c) == "table" and c[1] then
            return string.format("{A%d,R%d,G%d,B%d}", c[1], c[2] or 0, c[3] or 0, c[4] or 0)
        end
        return "?"
    end

    -- (a) BACKGROUND chrome rect = the contrast baseline (CHROME_ORDER[1], color at style.rect.color).
    local bg = self._chrome and self._chrome[1]
    local bg_style = bg and bg.style and bg.style.rect
    mod:info("[mt:scrollbar] (%s) BACKGROUND chrome[1] color=%s sg_world=%s sg_size=%s",
        tostring(reason), color_of(bg_style), wp("background"), sz("background"))
    mod:info("[mt:scrollbar]   top_panel=%s(%s) bottom_panel=%s(%s) list_mask=%s(%s)",
        wp("background_top_panel"), sz("background_top_panel"),
        wp("background_bottom_panel"), sz("background_bottom_panel"),
        wp("list_mask"), sz("list_mask"))

    -- (b) The scrollbar widget: track + thumb color, node world pos/size, styles' z (offset[3]).
    local sb = self._scrollbar
    local st = sb and sb.style
    local track_z = st and st.track and st.track.offset and st.track.offset[3]
    local thumb_z = st and st.thumb and st.thumb.offset and st.thumb.offset[3]
    mod:info("[mt:scrollbar]   TRACK color=%s sg=%s world=%s size=%s track_z=%s thumb_z=%s",
        color_of(st and st.track), defs.scrollbar_sg, wp(defs.scrollbar_sg), sz(defs.scrollbar_sg),
        tostring(track_z), tostring(thumb_z))
    -- THUMB style.size[2] is the RESOLVED height AFTER the local_offset pass mutated it
    -- (v0.2.77-dev). If this still reads the full track_h on an overflowing menu, the
    -- offset_function isn't running (the exact bug fixed in v0.2.77). _resolved_thumb_h
    -- in content is written by that same pass as a cross-check.
    local resolved_h = sb and sb.content and sb.content._resolved_thumb_h
    local resolved_off = sb and sb.content and sb.content._resolved_thumb_off
    mod:info("[mt:scrollbar]   THUMB color=%s style_size=%s style_off=%s resolved_h=%s resolved_off=%s",
        color_of(st and st.thumb),
        (st and st.thumb and st.thumb.size) and string.format("{%.0f,%.0f}", st.thumb.size[1], st.thumb.size[2]) or "?",
        (st and st.thumb and st.thumb.offset) and string.format("{%.0f,%.0f,%.0f}", st.thumb.offset[1], st.thumb.offset[2], st.thumb.offset[3]) or "?",
        resolved_h and string.format("%.1f", resolved_h) or "nil(pass-not-run)",
        resolved_off and string.format("%.1f", resolved_off) or "nil")
    -- (v0.2.78-dev) THUMB WORLD-Y top+bottom so position is verifiable from data. The
    -- node is +Y-up; the thumb's bottom-left origin sits `resolved_off` above the node
    -- world Y, the top is +resolved_h further up. Compare against the track world-Y span
    -- (node_y .. node_y + track_h): on overflow the thumb should be flush at the TOP
    -- (scroll=0) i.e. thumb_top ~= track_top, and flush at the BOTTOM (scroll=1) i.e.
    -- thumb_bottom ~= track_bottom, never outside [track_y, track_y + track_h].
    do
        local ok_n, np = pcall(UISceneGraph.get_world_position, sg, defs.scrollbar_sg)
        local track_h = (st and st.track and st.track.size and st.track.size[2]) or 0
        if ok_n and np and resolved_off and resolved_h then
            local node_y = np[2]
            local thumb_bottom = node_y + resolved_off
            local thumb_top = thumb_bottom + resolved_h
            mod:info("[mt:scrollbar]   THUMB world-Y bottom=%.1f top=%.1f vs TRACK span [%.1f, %.1f] scroll_value=%s",
                thumb_bottom, thumb_top, node_y, node_y + track_h,
                sb and sb.content and tostring(sb.content.scroll_value) or "nil")
        else
            mod:info("[mt:scrollbar]   THUMB world-Y=? (node world pos or resolved thumb values unavailable — pass not run yet?)")
        end
    end

    -- (c) Scroll math: drawn only when _max_scroll>0; thumb_frac = visible/content; thumb_px = track_h * clamp(frac,0.06,1).
    local content_h = self._content_h or 0
    local visible_h = self._visible_h or 0
    local max_scroll = self._max_scroll or 0
    local track_h = (sb and sb.style and sb.style.track and sb.style.track.size and sb.style.track.size[2]) or 0
    local thumb_frac = (content_h > 0) and (visible_h / content_h) or 1
    local clamped = math.clamp(thumb_frac, 0.06, 1)
    local thumb_px = track_h * clamped
    mod:info("[mt:scrollbar]   content_h=%.0f visible_h=%.0f max_scroll=%.0f track_h=%.0f thumb_frac=%.3f (clamped %.3f) thumb_px=%.1f will_draw=%s",
        content_h, visible_h, max_scroll, track_h, thumb_frac, clamped, thumb_px, tostring(max_scroll > 0))

    -- On-screen check: is the mt_scrollbar node inside the VISIBLE panel box?
    --
    -- (v0.2.74-dev) Test the bar's CENTRE against `background_frame` (the decorated
    -- panel the player sees), NOT its bottom-left origin against `list_mask`. list_mask
    -- is a 1400px LEFT-aligned node whose right edge juts ~18px off-panel, and
    -- math.point_is_inside_2d_box uses STRICT inequalities so a shared edge reports a
    -- FALSE on_screen=false. Centre-vs-frame is the unambiguous test. (The old probe's
    -- on_screen=false in BOTH states was this strict-edge artifact, not proof the bar
    -- was off-screen.) Kept in sync with the view twin.
    local ok_sbp, sbp = pcall(UISceneGraph.get_world_position, sg, defs.scrollbar_sg)
    local ok_sbs, sbs = pcall(UISceneGraph.get_size, sg, defs.scrollbar_sg)
    local ok_fp, fp = pcall(UISceneGraph.get_world_position, sg, "background_frame")
    local ok_fs, fs = pcall(UISceneGraph.get_size, sg, "background_frame")
    if ok_sbp and sbp and ok_sbs and sbs and ok_fp and fp and ok_fs and fs then
        local cx, cy = sbp[1] + sbs[1] * 0.5, sbp[2] + sbs[2] * 0.5
        local inside = math.point_is_inside_2d_box({ cx, cy }, fp, fs)
        mod:info("[mt:scrollbar]   on_screen=%s sb_centre={%.0f,%.0f} vs frame origin={%.0f,%.0f} size={%.0f,%.0f}",
            tostring(inside), cx, cy, fp[1], fp[2], fs[1], fs[2])
    else
        mod:info("[mt:scrollbar]   on_screen=? (world/size lookup failed)")
    end
end

-- ---------------------------------------------------------------
-- Input (hotspot flags are populated during the draw pass)
-- ---------------------------------------------------------------

-- ---------------------------------------------------------------
-- TYPE-TO-EDIT a slider's numeric value (v0.2.66-dev). Click the value box to focus,
-- type digits (+ optional "." / "-" per the slider's decimals/range), commit on Enter
-- or focus-loss, cancel on Escape. ADDITIVE over the existing drag + arrow stepping —
-- those are suppressed only while THIS row is the active editor. Only ONE row edits at
-- a time (self._editing_row). Filter mirrors VMF (vmf_options_view.lua:4532-4556):
-- digits capped at num_decimals after the dot, "-" gated on min<0, "." once when
-- decimals>0, Backspace, 16-char cap. PORTED VERBATIM from _mod_tweaker_view.lua so the
-- standalone view (in-mission) and this HeroView sub-state (keep) behave identically.
local _EDIT_MAX_LEN = 16

local function _format_value(value, num_decimals)
    return string.format("%." .. (num_decimals or 0) .. "f", value or 0)
end

function HeroViewStateModTweaker:_begin_edit(row)
    if self._editing_row and self._editing_row ~= row then
        -- Committing the previously-focused row keeps a single active editor.
        self:_commit_edit(self._editing_row)
    end
    local c = row.content
    self._editing_row = row
    c.editing = true
    c.edit_str = _format_value(c.value, c.num_decimals)
    c.caret_t = 0
    c.value_text = c.edit_str
    _play_click()
end

-- Append/filter ONE batch of keystrokes into c.edit_str (VMF rule set). Returns true if
-- the buffer changed this call (so live feedback only recomputes on change).
function HeroViewStateModTweaker:_edit_apply_keystrokes(c)
    local keystrokes = Keyboard.keystrokes()
    if not keystrokes or #keystrokes == 0 then return false end
    local s = c.edit_str or ""
    local nd = c.num_decimals or 0
    local changed = false
    for _, stroke in ipairs(keystrokes) do
        if type(stroke) == "string" then
            if #s < _EDIT_MAX_LEN then
                if tonumber(stroke) then
                    -- digit: allowed before the dot, or while < nd digits sit after it.
                    local dot = string.find(s, "%.")
                    if not dot or #s < dot + nd then s = s .. stroke; changed = true end
                elseif stroke == "-" then
                    -- minus toggle, only when the range actually allows negatives.
                    if (c.min or 0) < 0 then
                        if string.find(s, "%-") then s = string.gsub(s, "%-", "")
                        else s = "-" .. s end
                        changed = true
                    end
                elseif stroke == "." and nd > 0 and not string.find(s, "%.") then
                    s = s .. "."; changed = true
                end
            end
        elseif stroke == Keyboard.BACKSPACE and #s > 0 then
            s = string.sub(s, 1, -2); changed = true
        end
    end
    if changed then c.edit_str = s end
    return changed
end

-- Live feedback for the active editor: mirror the typed string into value_text and tint
-- it red when the buffer is not a valid in-range number (a trailing bare "." is allowed
-- so the user can keep typing). Caret offset/alpha is driven by the definitions'
-- local_offset pass (it reads c._caret_renderer + c.caret_t, set/advanced here).
function HeroViewStateModTweaker:_edit_live_feedback(row, dt)
    local c = row.content
    c.caret_t = (c.caret_t or 0) + (dt or 0)
    c._caret_renderer = self.ui_top_renderer or self.ui_renderer
    c.value_text = c.edit_str or ""
    local vs = row.style and row.style.value
    if vs and vs.text_color then
        local n = tonumber(c.edit_str)
        local bad = (n == nil) or (n < (c.min or 0)) or (n > (c.max or 1))
        vs.text_color[1] = 255
        vs.text_color[2] = 255
        vs.text_color[3] = bad and 70 or 255
        vs.text_color[4] = bad and 70 or 255
    end
end

-- Snap n to the slider's step grid (same math the drag/arrow paths use), then clamp.
local function _snap_and_clamp(c, n)
    n = math.clamp(n, c.min or 0, c.max or 1)
    local nd = c.num_decimals or 0
    if c.step and c.step > 0 then
        local base = c.min or 0
        n = base + math.floor((n - base) / c.step + 0.5) * c.step
    else
        local m = (nd > 0) and (10 ^ nd) or 1
        n = math.floor(n * m + 0.5) / m
    end
    return math.clamp(n, c.min or 0, c.max or 1)
end

function HeroViewStateModTweaker:_commit_edit(row)
    local c = row.content
    local n = tonumber(c.edit_str)
    if n == nil then
        -- not a number -> treat as cancel (restore the live value).
        self:_cancel_edit(row)
        return
    end
    n = _snap_and_clamp(c, n)
    -- (v0.2.70-dev) STAGE the typed value (was a live _cat_set + re-read). Nothing is
    -- written live until APPLY, so there's no mod-side on_setting_changed snap to re-read
    -- here — the snapped/clamped typed value IS the staged value, and the row reflects it.
    c.value = n
    _play_click()
    self:stage_set(row._category, row._setting_id, n)
    local span = (c.max or 1) - (c.min or 0)
    c.internal_value = (span > 0) and math.clamp((n - (c.min or 0)) / span, 0, 1) or 0
    c.value_text = _format_value(n, c.num_decimals)
    self:_end_edit(row)
end

function HeroViewStateModTweaker:_cancel_edit(row)
    local c = row.content
    -- Restore the displayed value from the (unchanged) committed value.
    c.value_text = _format_value(c.value, c.num_decimals)
    _play_click()
    self:_end_edit(row)
end

-- Shared teardown: clear edit flags + reset the value-text color to white so the next
-- frame's draw doesn't keep a red invalid-tint.
function HeroViewStateModTweaker:_end_edit(row)
    local c = row.content
    c.editing = false
    c.edit_str = ""
    c._caret_renderer = nil
    local vs = row.style and row.style.value
    if vs and vs.text_color then vs.text_color[1] = 255; vs.text_color[2] = 255; vs.text_color[3] = 255; vs.text_color[4] = 255 end
    if self._editing_row == row then self._editing_row = nil end
end

-- ---------------------------------------------------------------
-- REAL DROPDOWN open/select/close (v0.2.69-dev). One dropdown is open at a time
-- (self._open_dropdown = the collapsed row). While open it's MODAL: _handle_input
-- short-circuits to the popup so other rows don't react. The popup widget itself
-- (self._dd_list) is rebuilt by _refresh_dropdown_list whenever the visible window
-- (start_index) changes, and drawn in _draw after the rows so it overlays everything.
-- ---------------------------------------------------------------

-- (Re)build the popup overlay widget for the open dropdown at the current start_index.
function HeroViewStateModTweaker:_refresh_dropdown_list()
    local row = self._open_dropdown
    if not row then self._dd_list = nil; return end
    local texts = row._options_texts or {}
    local cur   = row._option_idx or 1
    local start = self._dd_start or 1
    local ok, w = pcall(defs.create_dropdown_list, texts, cur, row._list_y or 0, start)
    self._dd_list = (ok and w) or nil
end

function HeroViewStateModTweaker:_open_dropdown_popup(row)
    -- Committing any active type-edit first keeps a single modal surface.
    if self._editing_row then self:_commit_edit(self._editing_row) end
    self._open_dropdown = row
    row.content.active = true
    local n = #(row._options_texts or {})
    local num_draws = math.min(n, 10)
    -- Scroll the window so the selected option is visible (native start_index clamp).
    self._dd_start = math.clamp((row._option_idx or 1) - num_draws + 1, 1, math.max(1, n - num_draws + 1))
    if (row._option_idx or 1) <= num_draws then self._dd_start = 1 end
    self:_refresh_dropdown_list()
    _play_click()
end

function HeroViewStateModTweaker:_close_dropdown_popup()
    local row = self._open_dropdown
    if row then row.content.active = false end
    self._open_dropdown = nil
    self._dd_list = nil
end

function HeroViewStateModTweaker:_commit_dropdown(opt_i)
    local row = self._open_dropdown
    if not row then return end
    local vals = row._options_values or {}
    if vals[opt_i] ~= nil then
        row._option_idx = opt_i
        row.content.value_text = (row._options_texts or {})[opt_i] or ""
        -- (v0.2.70-dev) STAGE the selection (was a live _cat_set). Commits on APPLY.
        self:stage_set(row._category, row._setting_id, vals[opt_i])
        _play_click()
        mod:debug("[mt:dump] input: dropdown '%s' -> %s (staged)", tostring(row._setting_id), tostring(vals[opt_i]))
    end
    self:_close_dropdown_popup()
end

-- Position the popup's single highlight sprite under the hovered option (or the
-- currently-selected one if nothing is hovered) and show/hide it. Runs each draw frame.
function HeroViewStateModTweaker:_position_dropdown_highlight()
    local w = self._dd_list
    local row = self._open_dropdown
    if not (w and row) then return end
    local c = w.content
    local num_draws = w._dd_num_draws or 0
    local hovered_k = nil
    for k = 1, num_draws do
        local hs = c["opt_" .. k]
        if hs and hs.is_hover then hovered_k = k; break end
    end
    -- Fall back to the selected option's slot (if it's in the visible window).
    if not hovered_k then
        local sel_k = (row._option_idx or 1) - (w._dd_start or 1) + 1
        if sel_k >= 1 and sel_k <= num_draws then hovered_k = sel_k end
    end
    if hovered_k and w.style and w.style.hl then
        local row_h = w._dd_row_h or 24
        w.style.hl.offset[2] = (w._dd_list_top or 0) - hovered_k * row_h
        c.hl_visible = true
    else
        c.hl_visible = false
    end
end

-- MODAL popup input. Returns true if it consumed the frame (caller returns early).
-- Handles: wheel-scroll of a long option list, per-option click (commit), and
-- click-away (close without committing). The popup widget's hotspots fire
-- on_left_release (shared-node semantics, same as the rows).
function HeroViewStateModTweaker:_handle_dropdown_input(input_service)
    local row = self._open_dropdown
    if not row then return false end
    local w = self._dd_list
    if not w then self:_close_dropdown_popup(); return true end
    local c = w.content
    local n = w._dd_total or 0
    local num_draws = w._dd_num_draws or 0

    -- Wheel scrolls the visible option window (only when the list overflows).
    if n > num_draws then
        local wheel = input_service and input_service:get("scroll_axis")
        if wheel and wheel.y and wheel.y ~= 0 then
            local new_start = math.clamp((self._dd_start or 1) - (wheel.y > 0 and 1 or -1),
                                         1, math.max(1, n - num_draws + 1))
            if new_start ~= self._dd_start then
                self._dd_start = new_start
                self:_refresh_dropdown_list()
            end
            return true
        end
    end

    -- Per-option click -> commit that absolute option index.
    for k = 1, num_draws do
        local hs = c["opt_" .. k]
        if hs and (hs.on_release or hs.on_left_release) then
            self:_commit_dropdown((w._dd_start or 1) + k - 1)
            return true
        end
    end

    -- Click-away (LMB released, not on any option row) closes WITHOUT committing.
    if Mouse.released(0) then
        self:_close_dropdown_popup()
        _play_click()
        return true
    end
    return true   -- modal: swallow all other row input while the popup is open
end

function HeroViewStateModTweaker:_handle_input(input_service)

    -- (v0.2.69-dev) MODAL dropdown popup: while a dropdown is open, the popup owns input
    -- (option click / wheel-scroll / click-away). Short-circuit so no other row reacts.
    if self._open_dropdown then
        if self:_handle_dropdown_input(input_service) then return end
    end

    -- Scroll: mouse wheel (1 notch ~= 1 row) + scrollbar thumb drag. The wheel reads
    -- scroll_axis off the menu input service; the thumb drag tracks the cursor like
    -- the vanilla scrollbar held_function (inverse-scaled cursor vs the track top).
    if (self._max_scroll or 0) > 0 then
        local wheel = input_service and input_service:get("scroll_axis")
        if wheel and wheel.y and wheel.y ~= 0 then
            self._scroll_y = math.clamp((self._scroll_y or 0) - wheel.y * 46, 0, self._max_scroll)
        end
        -- Thumb drag: the hotspot pass sets is_held while the LMB is held over the
        -- scrollbar (its own node, so unlike the shared-node rows this fires fine).
        local hs = self._scrollbar and self._scrollbar.content.hotspot
        if hs and hs.is_held then
            local cursor = input_service and input_service:get("cursor")
            if cursor then
                local sb_pos = UISceneGraph.get_world_position(self.ui_scenegraph, defs.scrollbar_sg)
                local c = UIInverseScaleVectorToResolution(cursor)
                local rel = math.clamp((sb_pos[2] - c[2]) / math.max(1, self._visible_h or 700), 0, 1)
                self._scroll_y = math.clamp(rel * self._max_scroll, 0, self._max_scroll)
            end
        end
    end

    -- Exit (X) button.
    if self._exit and self._exit.content.button_hotspot and self._exit.content.button_hotspot.on_release then
        _play_click()
        self:close_menu()
        return
    end

    -- (v0.2.70-dev) APPLY button: commit the active category's pending buffer. Only when
    -- ENABLED (the active category has staged edits) — a click on the greyed button is a
    -- no-op. This is the ONLY path that runs _cat_set on edit.
    do
        local ah = self._apply and self._apply.content.button_hotspot
        if ah and (ah.on_release or ah.on_left_release) and not self._apply.content.disabled then
            self:apply_pending(self._categories[self._selected])
            return
        end
    end

    -- Tab clicks. The "More" tab advances the page; mod tabs switch selection.
    -- GUARDED while drilled: tab/page switching is disabled inside an advanced view so
    -- the player can't half-switch mods mid-drill (use Back / ESC to exit the drill first).
    if not self._drill then
        for i = 1, #self._tabs do
            local bt = self._tabs[i].content.hotspot
            if bt and bt.on_release then
                _play_click()
                mod:debug("[mt:dump] input: tab[%d] clicked (was %d)", i, self._selected or -1)
                if self._more_tab_index and i == self._more_tab_index then
                    self._page = ((self._page or 0) + 1) % math.max(1, self._page_count or 1)
                    self._selected = 1
                    self._scroll_y = 0
                    self:_rebuild()
                    return
                elseif i ~= self._selected and self._categories[i] then
                    self._selected = i
                    self._scroll_y = 0
                    self:_build_rows(self._categories[i])
                    return
                end
            end
        end
    end

    -- Diagnostic for "can't change any option": are row hotspots receiving cursor
    -- input at all? Logs the hovered / clicked row index (and visible count) so the
    -- next log shows whether the cursor reaches the rows or the click never fires.
    do
        local hov, rel, mv = -1, -1, 0
        for i = 1, #self._rows do
            local r = self._rows[i]
            if r._middle_visible then mv = mv + 1 end
            local c = r.content
            if c then
                local h = c.hotspot or c.dec or c.inc
                if h and h.is_hover then hov = i end
                if (c.hotspot and c.hotspot.on_release) or (c.dec and c.dec.on_release)
                   or (c.inc and c.inc.on_release) then rel = i end
            end
        end
        if hov >= 0 or rel >= 0 then
            mod:debug("[mt:dbg] row input: hover=%d release=%d visible=%d/%d", hov, rel, mv, #self._rows)
        end
    end

    -- Rows. Persist on change via _cat_set (routes to the real VMF mod object, or
    -- the gut controller for the dogfood category).
    for i = 1, #self._rows do
        local row = self._rows[i]
        -- Skip rows culled this frame (outside the list_mask) so a click on a
        -- scrolled-away row can't register.
        if not row._readonly and row._middle_visible ~= false then
            local c = row.content
            if row._is_gear then
                -- GEAR click: drill INTO this setting's advanced sub-options. Captures
                -- the parent setting_id + label, resets scroll, and rebuilds the list as
                -- Back + parent + children (see _build_rows' _drill branch).
                if c.hotspot and (c.hotspot.on_release or c.hotspot.on_left_release) then
                    _play_click()
                    self._drill = { setting_id = row._drill_setting, label = row._drill_label }
                    self._scroll_y = 0
                    self:_build_rows(self._categories[self._selected])
                    mod:debug("[mt:dump] input: gear drill into '%s'", tostring(row._drill_setting))
                    return
                end
            elseif row._is_back then
                -- BACK row click: drill OUT to the normal list (same as the first ESC).
                if c.hotspot and (c.hotspot.on_release or c.hotspot.on_left_release) then
                    _play_click()
                    self._drill = nil
                    self._scroll_y = 0
                    self:_build_rows(self._categories[self._selected])
                    return
                end
            elseif row._is_group then
                -- Collapsible group header: toggle expand/collapse, then rebuild.
                if c.hotspot and (c.hotspot.on_release or c.hotspot.on_left_release) then
                    _play_click()
                    self._expanded[row._group_key] = not self._expanded[row._group_key]
                    self:_build_rows(self._categories[self._selected])
                    return
                end
            elseif row._wtype == "checkbox" or row._wtype == "boolean" then
                -- on_left_release (not on_release): rows share the mt_list_start node,
                -- which doesn't persist the hotspot input_pressed state, so on_release
                -- never fires for them; on_left_release fires on release-over-widget.
                -- The ON/OFF switch's two arrow hotspots (dec/inc) are alternate hit
                -- zones over the same row — either toggles the flag.
                local row_click = c.hotspot and (c.hotspot.on_release or c.hotspot.on_left_release)
                local arrow_click = (c.dec and (c.dec.on_release or c.dec.on_left_release))
                                 or (c.inc and (c.inc.on_release or c.inc.on_left_release))
                local clicked = row_click or arrow_click
                -- (v0.2.71-dev) ON/OFF FLICKER FIX — edge-latch the toggle so it fires ONCE
                -- per physical release. The rows share the mt_list_start node, which keeps
                -- on_release/on_left_release latched true for SEVERAL consecutive draw frames;
                -- the old unconditional `c.flag = not c.flag` re-inverted the flag on each of
                -- those frames (on->off->on->off), the visible "negotiating" flicker. The
                -- displayed word follows content.flag directly (defs on_text/off_text passes),
                -- so each extra toggle is visible. row._toggle_armed gates the flip to the
                -- press edge and clears when all three hotspots' release flags drop. Mirrors
                -- the row._was_hovered hover debounce.
                if clicked and not row._toggle_armed then
                    row._toggle_armed = true
                    c.flag = not c.flag
                    _play_click()
                    -- (v0.2.70-dev) STAGE the toggle (was a live _cat_set). Commits on APPLY.
                    self:stage_set(row._category, row._setting_id, c.flag)
                    mod:debug("[mt:dump] input: checkbox '%s' -> %s (staged)", tostring(row._setting_id), tostring(c.flag))
                elseif not clicked then
                    row._toggle_armed = false
                end
            elseif row._wtype == "dropdown" then
                -- (v0.2.69-dev) Click the collapsed row -> OPEN the popup option list. The
                -- modal popup (handled at the top of _handle_input) does select/close.
                local vals = row._options_values
                if vals and #vals > 0 and c.hotspot
                   and (c.hotspot.on_release or c.hotspot.on_left_release) then
                    self:_open_dropdown_popup(row)
                    mod:debug("[mt:dump] input: dropdown '%s' opened", tostring(row._setting_id))
                    return
                end
            elseif row._wtype == "slider" or row._wtype == "numeric" then
                local cur = (type(c.value) == "number") and c.value or (c.min or 0)
                local moved, commit = false, false
                -- TYPE-TO-EDIT focus (v0.2.66-dev): a click on the value box enters edit
                -- mode for this row. Checked even when not currently editing; the value_hs
                -- hotspot is separate from track_hs/dec/inc so it never triggers a drag.
                local vhs = c.value_hs
                local vhs_clicked = vhs and (vhs.on_release or vhs.on_left_release)
                if c.editing then
                    -- ACTIVE EDITOR branch — suppress drag/arrows entirely (spec §6.6).
                    self:_edit_apply_keystrokes(c)
                    -- CONSUME Enter / stray keys so they COMMIT and never open game chat
                    -- (v0.2.67-dev). Chat reads keyboard Enter on the INDEPENDENT chat_input
                    -- service, which gut's own Keyboard.released(13) commit can't block. The
                    -- engine-sanctioned lever is ChatManager.block_chat_input_for_one_frame()
                    -- (chat_manager.lua:390-397 -> chat_gui.lua:541-543/560), re-asserted EVERY
                    -- frame the edit is active (it auto-clears each frame). This blocks chat
                    -- activation for the whole edit (Enter-commit AND stray y/letters), self-
                    -- clears when editing ends, and is ChatGuiNull-safe via pcall.
                    if Managers.chat and Managers.chat.block_chat_input_for_one_frame then
                        pcall(function() Managers.chat:block_chat_input_for_one_frame() end)
                    end
                    if Keyboard.released(13) then            -- Enter -> commit
                        self:_commit_edit(row)
                        return
                    elseif Keyboard.released(27) then        -- Escape -> cancel
                        self:_cancel_edit(row)
                        return
                    elseif Mouse.released(0) and not vhs_clicked then
                        -- Click outside this value box = focus-loss -> commit (Enter-equiv).
                        self:_commit_edit(row)
                        return
                    end
                    -- Still editing: skip the drag/arrow handling for this row this frame.
                elseif vhs_clicked then
                    self:_begin_edit(row)
                    return
                else
                -- Draggable track. During the HOLD we only move the VISUAL; we COMMIT
                -- (mod:set -> the mod's on_setting_changed) ONLY on release. Some
                -- handlers are heavy — ct's `starting_coins` broadcasts the entire
                -- ~18KB config to clients — so firing it every drag frame floods the
                -- network and crashes. One commit on release matches VMF's behaviour.
                local ths = c.track_hs
                if ths and (ths.is_held or ths.on_left_release) and c.track_w then
                    local cursor = input_service and input_service:get("cursor")
                    if cursor then
                        local anchor = UISceneGraph.get_world_position(self.ui_scenegraph, defs.list_sg)
                        local cx = UIInverseScaleVectorToResolution(cursor)[1]
                        local frac = math.clamp((cx - (anchor[1] + (c.track_x or 0))) / math.max(1, c.track_w), 0, 1)
                        cur = (c.min or 0) + frac * ((c.max or 1) - (c.min or 0))
                        local nd = c.num_decimals or 0
                        local m = (nd > 0) and (10 ^ nd) or 1
                        cur = math.floor(cur * m + 0.5) / m
                        moved = true
                        if ths.on_left_release then commit = true end  -- drag ended
                    end
                end
                if c.dec and (c.dec.on_release or c.dec.on_left_release) then cur = math.clamp(cur - (c.step or 1), c.min, c.max); moved = true; commit = true end
                if c.inc and (c.inc.on_release or c.inc.on_left_release) then cur = math.clamp(cur + (c.step or 1), c.min, c.max); moved = true; commit = true end
                -- Visual tracks the value every frame (smooth drag); persistence waits.
                if moved and cur ~= c.value then
                    c.value = cur
                    local span = (c.max or 1) - (c.min or 0)
                    c.internal_value = (span > 0) and math.clamp((cur - c.min) / span, 0, 1) or 0
                    c.value_text = string.format("%." .. (c.num_decimals or 0) .. "f", cur)
                    mod:debug("[mt:slider] DRAG '%s' val=%s internal=%.3f thumb_x~=%.0f (track_x=%s track_w=%s)",
                        tostring(row._setting_id), tostring(cur), c.internal_value,
                        (c.track_x or 0) + (c.track_w or 0) * c.internal_value,
                        tostring(c.track_x), tostring(c.track_w))
                end
                if commit then
                    _play_click()
                    -- (v0.2.70-dev) STAGE the slider value (was a live _cat_set + re-read).
                    -- Nothing is written live until APPLY, so there's no mod-side
                    -- on_setting_changed snap to re-read here — the dragged/stepped value
                    -- (already grid-snapped above) IS the staged value, and the bar shows it.
                    self:stage_set(row._category, row._setting_id, c.value)
                    mod:debug("[mt:dump] input: slider '%s' -> %s (staged)", tostring(row._setting_id), tostring(c.value))
                end
                end  -- close the `else` (not-editing) drag/arrow branch
            end
        end
    end
end

-- Per-frame hover polish for one visible row: (1) whole-row highlight
-- ("playerlist_hover") gated on content.is_highlighted, set from the row hotspot's
-- is_hover; (2) Play_hud_hover sound on the hover-enter EDGE only. The factories
-- created the passes/content; the view just flips the per-frame flags.
--
-- (v0.2.82-dev — ITEM 4) The inc/dec arrow texture-swap (settings_arrow_normal ->
-- settings_arrow_clicked on hover) was REMOVED — see the standalone-view twin's
-- _apply_row_hover for the full rationale. Vanilla never hard-swaps a stepper/slider
-- arrow to its bright "clicked" sprite on mere hover; gut's swap read as a pressed-
-- down button. Hover feedback now comes solely from the whole-row playerlist_hover
-- highlight (kept below). The arrows stay on settings_arrow_normal at all times.
function HeroViewStateModTweaker:_apply_row_hover(row)
    local c = row.content
    if not c then return end
    -- (1) row highlight from whichever hotspot the row exposes.
    local row_hot = c.hotspot or c.track_hs
    local hovered = (row_hot and row_hot.is_hover) and true or false
    if (c.dec and c.dec.is_hover) or (c.inc and c.inc.is_hover) then hovered = true end
    if c.is_highlighted ~= nil then c.is_highlighted = hovered end
    -- (2) hover-enter edge sound (debounced on the row's own _was_hovered flag).
    if hovered and not row._was_hovered then _play_hover() end
    row._was_hovered = hovered
end

-- ---------------------------------------------------------------
-- Draw (single begin_pass/end_pass on the borrowed top renderer)
-- ---------------------------------------------------------------

function HeroViewStateModTweaker:_draw(dt, input_service)
    -- Draw on ui_top_renderer (top_ingame_view world) — the SAME renderer OptionsView
    -- and the hero menu use. Our rows use only atlas-safe materials (matchmaking_
    -- checkbox / slider_thumb / rect / border), which resolve on this renderer.
    local renderer = self.ui_top_renderer or self.ui_renderer
    local scenegraph = self.ui_scenegraph
    if not (renderer and scenegraph and self._chrome) then return end

    -- Highlight the active tab: gold when selected / on hover, dim grey otherwise.
    for i = 1, #self._tabs do
        local tab = self._tabs[i]
        local st = tab.style and tab.style.text
        -- (v0.2.71-dev) hover-enter sound on TABS (was unwired — _play_hover only fired
        -- for rows via _apply_row_hover). Edge-debounced on the tab's own _was_hovered.
        local hov = tab.content.hotspot and tab.content.hotspot.is_hover
        if hov and not tab._was_hovered then _play_hover() end
        tab._was_hovered = hov
        if st and st.text_color then
            local active = (i == self._selected) or hov
            st.text_color[1] = 255
            st.text_color[2] = active and 255 or 140
            st.text_color[3] = active and 215 or 140
            st.text_color[4] = active and 90 or 140
        end
    end

    -- (v0.2.70-dev) APPLY button per-frame styling. Recompute the disabled flag from the
    -- active category's buffer (cheap; keeps it correct even if a rebuild changed the
    -- active category). Gold text ("cheeseburger") + brighter border when enabled; dim
    -- grey + faint border when disabled. Hover brightens the bg fill when enabled.
    self:_update_apply_button()
    if self._apply then
        local ac = self._apply.content
        local asty = self._apply.style
        local enabled = not ac.disabled
        local hovered = ac.button_hotspot and ac.button_hotspot.is_hover
        -- (v0.2.71-dev) hover-enter sound on the APPLY button (was unwired). Edge-debounced
        -- on self._apply._was_hovered. Gated on `enabled` so the greyed (no-pending-edits)
        -- button stays silent — only an actionable hover plays.
        if enabled and hovered and not self._apply._was_hovered then _play_hover() end
        self._apply._was_hovered = hovered
        if asty.text and asty.text.text_color then
            local t = asty.text.text_color
            if enabled then
                t[1], t[2], t[3], t[4] = 255, 255, 168, 0           -- cheeseburger gold
            else
                t[1], t[2], t[3], t[4] = 255, 110, 110, 110         -- dim grey (disabled)
            end
        end
        if asty.bg and asty.bg.color then
            asty.bg.color[1] = (enabled and hovered) and 235 or 200
            local v = (enabled and hovered) and 28 or 10
            asty.bg.color[2], asty.bg.color[3], asty.bg.color[4] = v, v, v
        end
        if asty.border and asty.border.color then
            local b = enabled and 130 or 50
            asty.border.color[1] = 255
            asty.border.color[2], asty.border.color[3], asty.border.color[4] = b, b, b
        end
    end

    -- (v0.2.71-dev) hover-enter sound on the EXIT (X) button (was unwired). Edge-debounced
    -- on self._exit._was_hovered. Mirrors the tab/APPLY hover edges added this version.
    if self._exit then
        local xh = self._exit.content.button_hotspot
        local x_hov = xh and xh.is_hover
        if x_hov and not self._exit._was_hovered then _play_hover() end
        self._exit._was_hovered = x_hov
    end

    -- Apply scroll: translate the list container node; all rows move with it.
    -- Positive Y shifts the stack up (reveals lower rows) — same sign convention as
    -- OptionsView.update_scrollbar. Set BEFORE begin_pass so world positions (used
    -- for culling below) reflect the scroll this frame.
    local list_node = scenegraph[defs.list_node]
    if list_node then
        list_node.offset = list_node.offset or { 0, 0, 0 }
        list_node.offset[2] = self._scroll_y or 0
    end

    UIRenderer.begin_pass(renderer, scenegraph, input_service, dt, nil, self.render_settings)

    -- Protect end_pass: if any draw_widget below errors, end_pass MUST still run, or
    -- the borrowed renderer is left mid-pass and HeroView's own chrome (which draws on
    -- the SAME renderer on its next pass) renders without its background — that's the
    -- "menu looks deprecated (just buttons)" symptom. CRITICAL on a borrowed renderer.
    local _draw_ok, _draw_err = pcall(function()

    for i = 1, #(self._chrome or {}) do
        UIRenderer.draw_widget(renderer, self._chrome[i])
    end
    if self._hint then UIRenderer.draw_widget(renderer, self._hint) end
    for i = 1, #self._tabs do
        UIRenderer.draw_widget(renderer, self._tabs[i])
    end
    -- v0.2.65-dev: no title to draw — removed to match native Options (tabs span the
    -- full top band).
    if self._exit then UIRenderer.draw_widget(renderer, self._exit) end
    -- (v0.2.70-dev) APPLY button (bottom-right of the bottom panel). Drawn with the chrome
    -- so it's never culled by the list_mask (it lives outside the scrolling list).
    if self._apply then UIRenderer.draw_widget(renderer, self._apply) end

    -- Cull + draw rows against the list_mask box (CPU position-cull; no GPU mask).
    -- World positions are valid here because begin_pass re-evaluated the scenegraph
    -- with the scroll offset set above.
    local mask_pos  = UISceneGraph.get_world_position(scenegraph, defs.list_mask_sg)
    local mask_size = UISceneGraph.get_size(scenegraph, defs.list_mask_sg)
    local anchor    = UISceneGraph.get_world_position(scenegraph, defs.list_sg)  -- mt_list_start (scrolled)
    for i = 1, #self._rows do
        local row = self._rows[i]
        local ry = row._list_y or 0
        local px, py = anchor[1], anchor[2] + ry
        -- Draw a row only when its CENTRE is inside the mask. Since we don't GPU-clip,
        -- a "lower-or-top" test would overdraw half-rows past the panel edges; centre-
        -- only keeps rows fully (or nearly) inside, so the list fits the window.
        local middle = math.point_is_inside_2d_box({ px, py + 23 }, mask_pos, mask_size)  -- ROW_H/2
        row._middle_visible = middle
        if middle then
            self:_apply_row_hover(row)
            -- TYPE-TO-EDIT live feedback (v0.2.66-dev): advance the caret pulse + mirror
            -- the typed buffer into the value text + red-tint on invalid, for the active
            -- editor row only. Runs in draw so it ticks every frame regardless of input.
            if row.content and row.content.editing then self:_edit_live_feedback(row, dt) end
            UIRenderer.draw_widget(renderer, row)
        else
            -- Culled: clear stale click flags so a scrolled-away row can't fire.
            local c = row.content
            if c then
                if c.hotspot then c.hotspot.on_release = nil; c.hotspot.on_left_release = nil end
                if c.dec then c.dec.on_release = nil; c.dec.on_left_release = nil end
                if c.inc then c.inc.on_release = nil; c.inc.on_left_release = nil end
            end
        end
    end

    -- Scrollbar — only when the content overflows the window.
    if self._scrollbar and (self._max_scroll or 0) > 0 then
        local c = self._scrollbar.content
        c.scroll_value = (self._max_scroll > 0) and (self._scroll_y / self._max_scroll) or 0
        c.thumb_frac = (self._content_h > 0) and ((self._visible_h or 700) / self._content_h) or 1
        UIRenderer.draw_widget(renderer, self._scrollbar)
    end

    -- (v0.2.69-dev) OPEN DROPDOWN POPUP — drawn LAST (over the rows + scrollbar), and
    -- OUTSIDE the cull loop so it's never clipped by the list_mask. It anchors to the
    -- mt_dropdown node (same scroll as the rows) at the collapsed row's Y, so it tracks
    -- the row if the list scrolls under it. Position the hover/selected highlight before
    -- drawing: highlight the option row under the cursor, else the currently-selected one.
    if self._dd_list then
        self:_position_dropdown_highlight()
        UIRenderer.draw_widget(renderer, self._dd_list)
    end

    end)  -- close pcall(function()
    UIRenderer.end_pass(renderer)  -- ALWAYS runs, even if a draw above errored
    if not _draw_ok then
        mod:warning("[mt] draw error (end_pass protected so the menu chrome survives): %s", tostring(_draw_err))
    end
end

return { class_name = "HeroViewStateModTweaker" }
