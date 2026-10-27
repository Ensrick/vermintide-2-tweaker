local mod = get_mod("gut_dev")
local _printf = rawget(_G, "printf") or function() end  -- engine printf (survives mod-logging-OFF); nil-guarded

-- Mod Tweaker view (v0.3 — native settings-menu chrome).
-- A native-style settings screen registered into IngameUI.views, opened from the
-- ESC "Mod Tweaker" entry. Borrows the IngameUI renderer (never makes its own),
-- registers a modal input service, draws in one begin_pass/end_pass, exits via
-- ingame_ui:transition_with_fade("ingame_menu"). The chrome (window frame,
-- panels, cogwheel, scrollbar, exit-X), the top tab strip, and the checkbox/
-- slider rows are the REAL OptionsView pieces (see _mod_tweaker_definitions).
-- Registry of categories/values is owned by the controller (mod.mod_tweaker).

local defs = mod:dofile("scripts/mods/gui_tweaker_dev/_mod_tweaker_definitions")
local transactions = mod:dofile("scripts/mods/gui_tweaker_dev/_mod_tweaker_transaction")
local default_reset = mod:dofile("scripts/mods/gui_tweaker_dev/_mod_tweaker_default_reset")
local Search = mod:dofile("scripts/mods/gui_tweaker_dev/_mod_tweaker_search")
local profiles = mod:dofile("scripts/mods/gui_tweaker_dev/_mod_tweaker_profiles")
local profile_runtime = mod:dofile("scripts/mods/gui_tweaker_dev/_mod_tweaker_profile_runtime")
local disabled_sections = mod:dofile("scripts/mods/gui_tweaker_dev/_mod_tweaker_disabled_sections")
local external_group = mod:dofile("scripts/mods/gui_tweaker_dev/_mod_tweaker_external_group")
local tab_labels = mod:dofile("scripts/mods/gui_tweaker_dev/_mod_tweaker_tab_labels")
local ordering = mod:dofile("scripts/mods/gui_tweaker_dev/_mod_tweaker_ordering")
local DialogueUI = mod:dofile("scripts/mods/gui_tweaker_dev/_mod_tweaker_dialogue")
local label_policy = mod:dofile("scripts/mods/gui_tweaker_dev/_mod_tweaker_label_policy")
local ExclusiveLayout = mod:dofile("scripts/mods/gui_tweaker_dev/_mod_tweaker_exclusive_layout")
local dx12_diag_module = mod:dofile("scripts/mods/gui_tweaker_dev/_gut_dx12_fence630")
local dx12_diag = mod._gut_dx12_fence630

local UIRenderer = UIRenderer
local UISceneGraph = UISceneGraph
local ShowCursorStack = ShowCursorStack
local math = math

-- (#164) gut-side per-setting slider STEP registry, keyed [mod_id][setting_id] = step.
-- This is the RELIABLE mechanism for a FOREIGN VMF mod's slider. Verified against the
-- decompiled VMF source (scripts/mods/vmf/modules/core/options.lua):
--   * A custom `step` field on a mod's numeric widget def is NON-fatal but INVISIBLE to us:
--     initialize_numeric_data (options.lua:439-448) rebuilds every numeric widget into a
--     FRESH table copying ONLY range/default_value/decimals_number/unit_text, so a `step`
--     field is stripped before it reaches vmf.options_widgets_data (the list gut reads at
--     _vmf_categories). It never arrives, so a foreign slider's step can't ride the widget def.
--   * A 3-element `range = {min,max,step}` is worse: validate_numeric_data FATALS on it
--     ("'range' field must contain an array-like table with 2 elements") and aborts the
--     mod's ENTIRE options init (ct .188 shipped this and was DEAD; reverted .189).
-- So a foreign slider's coarse step lives HERE, keyed by the mod's new_mod() id (NOT its
-- directory name — category.mod_id is the REGISTERED id: ct/ct_dev, cim/cim_dev). Both the
-- stable and dev ids are listed so the override matches whichever the user runs. The
-- widget-def `step` field is still honored FIRST (see _resolve_step) for any category gut
-- ever walks from RAW data (its own hand-authored tree), where VMF never touched the node.
local STEP_OVERRIDES = {
    cim     = { base_power_level = 25 },  -- crafting starting power level (range 0-950)
    cim_dev = { base_power_level = 25 },
    ct      = { starting_coins = 25, cot_cost_amount = 25 },
    ct_dev  = { starting_coins = 25, cot_cost_amount = 25 },
}

local SERVICE = "gut_mod_tweaker"

-- (#505) A dropdown gets the FILTER HEADER (type-to-filter search line, and category chips when
-- registered) when it has at least this many options OR carries registered categories. Below the
-- threshold with no categories, it stays the plain dropdown (unchanged) — small lists don't need it.
local DD_FILTER_MIN = 8

local ModTweakerView = class(ModTweakerView)
ModTweakerView.NAME = "mod_tweaker_view"

-- ---------------------------------------------------------------
-- Construction
-- ---------------------------------------------------------------

function ModTweakerView:init(ingame_ui_context)
    if not ingame_ui_context then
        error("ModTweakerView:init received nil ingame_ui_context")
    end
    self.ingame_ui_context = ingame_ui_context
    self.ui_renderer = ingame_ui_context.ui_renderer
    self.ui_top_renderer = ingame_ui_context.ui_top_renderer or ingame_ui_context.ui_renderer
    self.ingame_ui = ingame_ui_context.ingame_ui
    self.input_manager = ingame_ui_context.input_manager
    self.render_settings = { alpha_multiplier = 1, snap_pixel_positions = false }

    pcall(function()
        self.input_manager:create_input_service(SERVICE, "IngameMenuKeymaps", "IngameMenuFilters")
        self.input_manager:map_device_to_service(SERVICE, "keyboard")
        self.input_manager:map_device_to_service(SERVICE, "mouse")
        self.input_manager:map_device_to_service(SERVICE, "gamepad")
    end)

    self.ui_scenegraph = UISceneGraph.init_scenegraph(defs.scenegraph_definition)

    -- Static chrome built once (the native window).
    self._chrome = defs.build_chrome()
    self._exit = defs.build_exit_button()
    self._scrollbar = defs.build_scrollbar_rect()
    -- (v0.2.70-dev) STAGED-CHANGE model. Edits write to a per-category PENDING buffer
    -- (self._pending[mod_id][setting_id] = staged_value) instead of live; the APPLY
    -- button (bottom-right) commits the whole buffer via _cat_set. Keyed by mod_id (a
    -- stable string) NOT the category table — category tables are rebuilt on every
    -- _rebuild (_vmf_categories re-creates them), so keying by the table would lose the
    -- buffer on a tab switch. mod_id survives, and gives per-category isolation for free.
    self._pending = self._pending or {}
    self._apply = defs.create_apply_button()
    -- (v0.2.148-dev) RESTORE DEFAULTS button (bottom bar, to the LEFT of Apply). Clicking it
    -- STAGES every current-tab setting back to its default_value (see reset_to_defaults) — the
    -- user then clicks Apply to commit, exactly like a normal staged edit.
    self._reset = defs.create_default_button()
    self._profiles_label, self._profile_buttons = defs.create_profile_controls()
    self._profile_slot = 1
    self._profile_ready = {}
    -- (#207) Reusable hover-info popup widget (rect bg + frame + title/desc text). The draw
    -- loop sets its content + geometry + fade alpha each frame via defs.layout_tooltip.
    self._tooltip = defs.create_tooltip_popup()
    -- v0.2.65-dev: no "MOD TWEAKER" title widget — native Options has none and the
    -- tab strip now spans the full top band (see defs: mt_title node + build_title
    -- factory removed).
    -- (Fix 5, v0.2.149-dev) The bottom "Click a tab to pick a mod..." hint was removed to
    -- match the vanilla Options menu (no bottom hint). build_hint/self._hint are gone.

    self._tabs = {}
    self._rows = {}
    self._selected = 1
    self._active = false

    -- Scroll state (the list scrolls like the vanilla settings menu: a pixel offset
    -- on the mt_list node + position-culling against list_mask + the rect scrollbar).
    self._scroll_y = 0        -- pixel offset applied to mt_list.offset[2]
    self._max_scroll = 0      -- content_height - visible_height (>= 0)
    self._content_h = 0       -- total stacked row height
    self._visible_h = 0       -- list_mask height (read at runtime)
    self._sb_dragging = false -- scrollbar thumb being dragged
    self._drill = nil         -- gear drill-down state: nil = normal list; { setting_id, label } = drilled in

    -- (#497) Per-tab SEARCH filter. self._search is the fixed input box above the list;
    -- self._search_str is the raw typed query (lowercased for matching in _search_active).
    -- Focus is click-driven (self._search_focused); while focused printable keystrokes edit
    -- the query and _build_rows re-renders the current tab as a flat filtered list. Cleared on
    -- every open (on_enter) and on a tab switch, so search scope is always the current tab.
    self._search = defs.create_search_box()
    self._search_str = ""
    self._search_focused = false
    self._search_caret_t = 0
    self._search_tx = nil
    self._search_rebuild_pending = nil
    self._search_last_ancestors = nil
    self._search_top_ancestors = nil
end

-- ---------------------------------------------------------------
-- Registry access (through the controller — single source of truth)
-- ---------------------------------------------------------------

local function _mt() return mod.mod_tweaker end

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
-- installed VMF mod. The shared policy owns this author's registration ids so the
-- standalone and keep-substate presentation paths cannot drift apart (#636).
-- verminious_dreams_lighting (+ _dev) are intentionally OMITTED — they keep their
-- own normal VMF menu and don't belong as a Mod Tweaker tab.
-- HideBuffs and Crosshair Kill Confirmation remain deliberately excluded; their
-- settings are integrated into gut's Interface tab below.


local function _nf(node, key)  -- defensive node-field read
    if type(node) ~= "table" then return nil end
    local v = node[key]
    if v == nil and type(node.content) == "table" then v = node.content[key] end
    return v
end

-- (#164) Resolve the fixed step/increment for a numeric widget. Precedence:
--   1. an explicit `step` field on the widget def (canonical + self-documenting; only ever
--      reachable for a category gut walks from RAW data — VMF strips it off foreign mods,
--      see STEP_OVERRIDES),
--   2. the gut-side STEP_OVERRIDES[mod_id][setting_id] registry (the working path for a
--      foreign VMF mod like ct/cim), else
--   3. the natural increment: one unit for integers, 10^-decimals otherwise.
-- The value is snapped to this grid (anchored at range min) by _snap_and_clamp, NOT here;
-- this only picks the increment magnitude. (No range[3] fallback: a 3-element range is fatal
-- to VMF's own validator, so it can never appear on a live widget.)
local function _resolve_step(node, mod_id, setting_id, dec)
    local field = _nf(node, "step")
    if type(field) == "number" and field > 0 then return field end
    local m = mod_id and STEP_OVERRIDES[mod_id]
    local reg = m and setting_id and m[setting_id]
    if type(reg) == "number" and reg > 0 then return reg end
    return (dec and dec > 0) and (10 ^ -dec) or 1
end

local function _vmf_label(node, mod_obj)
    local t = _nf(node, "title") or _nf(node, "text") or _nf(node, "setting_id") or "?"
    if type(t) ~= "string" then return tostring(t) end
    -- Same "<...>" defence as _vmf_tooltip: VMF can freeze a "<key>" missing-marker into a
    -- title/text field. Strip it, re-localize the inner key now (all mods registered at render
    -- time), and NEVER surface a marker; fall back to the bare key text (a label must be non-nil).
    local inner = string.match(t, "^<(.-)>$")
    local key = inner or t
    if mod_obj and mod_obj.localize then
        local ok, s = pcall(mod_obj.localize, mod_obj, key)
        if ok and type(s) == "string" and s ~= "" and not string.find(s, "^<") then
            return label_policy.clean(s)
        end
    end
    return label_policy.clean(key)
end

-- (#207) The node's tooltip DESCRIPTION (the hover-popup body). In VMF widget data the
-- `tooltip` field is usually an ALREADY-localized display string (mods write
-- `tooltip = mod:localize("<id>_tooltip")` in their _data.lua), but it can occasionally be
-- a raw loc key — so mirror _vmf_label's pcall-localize and keep the localized result only
-- when it resolves cleanly (not a "<missing>" marker). Empty / absent tooltip -> nil (the
-- row then has no popup). Reads via _nf so it works for both flat (VMF) + nested (gut) nodes.
local function _vmf_tooltip(node, mod_obj)
    local t = _nf(node, "tooltip")
    if type(t) ~= "string" or t == "" then return nil end
    -- ROOT FIX for the recurring "<...>" in DESCRIPTIONS. VMF can FREEZE a missing-loc
    -- marker ("<key>") into node.tooltip when the tooltip key did not resolve at data-build
    -- time. The old code rejected re-localizing a "<...>" string but then FELL BACK to
    -- returning that same marker (the leak). Instead: strip the brackets to recover the key,
    -- re-localize it now (all mods are registered at render time), and NEVER surface a marker.
    local inner = string.match(t, "^<(.-)>$")   -- "<gut_x_tooltip>" -> "gut_x_tooltip"
    local key = inner or t
    if mod_obj and mod_obj.localize then
        local ok, s = pcall(mod_obj.localize, mod_obj, key)
        if ok and type(s) == "string" and s ~= "" and not string.find(s, "^<") then
            return s
        end
    end
    -- Could not localize. Never show a "<...>" marker as the description.
    if inner or string.find(t, "^<") then return nil end
    return t   -- raw value was already plain display text
end

-- (#95) Render a VMF keybind value (an ARRAY of key-name strings, e.g. {"left alt"}
-- or {"ctrl","f"}; {} = unbound) as a readable combo. Guards against the value being
-- nil, an empty table, or (defensively) a non-table so a raw "table: 0x..." address
-- can never reach the row label. Joined with " + " and upper-cased to read like a key
-- prompt ("LEFT ALT", "CTRL + F", "UNBOUND").
local function _format_keybind_value(val)
    if type(val) ~= "table" then
        return (val == nil) and "unbound" or string.upper(tostring(val))
    end
    local parts = {}
    for i = 1, #val do
        local k = val[i]
        if k ~= nil and k ~= "" then parts[#parts + 1] = string.upper(tostring(k)) end
    end
    if #parts == 0 then return "unbound" end
    return table.concat(parts, " + ")
end

-- (#123) Keybind capture: collect the currently-held keyboard/mouse buttons by VT2 name
-- and return the VMF combo array {main_key, modifiers...} once a non-modifier key is held,
-- else nil. Names come straight from Keyboard.button_name (the same naming VMF matches
-- against), modifiers first. Gamepad ignored; mouse buttons 1-5 ARE captured (issue 631,
-- see _MOUSE_KEYID). NOTE: exact name normalisation
-- ("left ctrl" vs "ctrl") is verified on dev — if a bind does not fire in-game, a single
-- native-menu rebind ([gut-keybind-probe] VMF) reveals VMF's exact stored format to match.
-- VMF stores binds as { primary_key, modifier... } — the MAIN key FIRST, then
-- NORMALISED modifiers ("ctrl"/"alt"/"shift", NOT "left ctrl"). Confirmed from working
-- binds in user_settings.config (e.g. {"c","ctrl"}, single key {"f8"}). v0.2.99 had the
-- order reversed with "left ctrl" names, so VMF couldn't register the bind (#123).
local _KB_MOD_NORMALIZE = {
    ["left shift"] = "shift", ["right shift"] = "shift",
    ["left ctrl"]  = "ctrl",  ["right ctrl"]  = "ctrl",
    ["left alt"]   = "alt",   ["right alt"]   = "alt",
}
-- (issue 631) Mouse buttons 1-5 as keybind primaries. The strings are VMF's own MOUSE
-- key-ids and the indices are VMF's own button indices, taken verbatim from
-- Vermintide-Mod-Framework/scripts/mods/vmf/modules/core/keybindings.lua:120-124
-- (PRIMARY_BINDABLE_KEYS.MOUSE). Storing e.g. {"mouse extra 1"} therefore resolves back
-- through KEYS_INFO to the MOUSE input-check functions at dispatch
-- (keybindings.lua:161-179, :311-314) — Mouse.pressed / Mouse.button — so the bind fires.
-- Held state is read the way the game's own code does (Mouse.button(idx) > 0, e.g. VT2
-- decompile scripts/managers/debug/debug_manager.lua:299). Mouse 1=left(0) 2=right(1)
-- 3=middle(2) 4=extra 1(3) 5=extra 2(4). Wheel (idx 10-13) is excluded: the issue asks
-- only for the 5 buttons, and a wheel tick has no held/release phase to capture or to
-- release-detect at dispatch.
local _MOUSE_KEYID = {
    [0] = "mouse left",
    [1] = "mouse right",
    [2] = "mouse middle",
    [3] = "mouse extra 1",
    [4] = "mouse extra 2",
}
-- Returns (combo, primary_is_mouse). primary_is_mouse lets the caller defer committing a
-- mouse bind until the button is RELEASED (VMF does the same, vmf_options_view.lua:3734-
-- 3751): committing a mouse primary on press would let the left-click that ENTERS capture
-- self-bind Mouse 1, and let the release fall through to the hotspot enter / right-click-
-- clear branches. A keyboard primary has no such overlap, so it still commits on press.
local function _poll_keybind_combo()
    local n = 256
    local ok_n, cnt = pcall(function() return Keyboard.num_buttons() end)
    if ok_n and type(cnt) == "number" and cnt > 0 then n = cnt end
    local mods, seen, main = {}, {}, nil
    for i = 0, n - 1 do
        local ok_b, down = pcall(Keyboard.button, i)
        if ok_b and type(down) == "number" and down > 0 then
            local ok_name, name = pcall(Keyboard.button_name, i)
            if ok_name and type(name) == "string" and name ~= "" and name ~= "esc" then
                local norm = _KB_MOD_NORMALIZE[name]
                if norm then
                    if not seen[norm] then seen[norm] = true; mods[#mods + 1] = norm end
                elseif not main then
                    main = name
                end
            end
        end
    end
    -- (issue 631) Mouse button as primary when no keyboard main key is held. Keyboard wins
    -- ties, mirroring VMF capture which checks Keyboard.any_pressed() before Mouse.any_pressed()
    -- (vmf_options_view.lua:3702-3712). Held keyboard ctrl/alt/shift still combine with a mouse
    -- primary (VMF supports modifier+mouse). Scanned low-to-high so left-click wins if two
    -- buttons are somehow held at once.
    local primary_is_mouse = false
    if not main then
        for idx = 0, 4 do
            local ok_m, down = pcall(Mouse.button, idx)
            if ok_m and type(down) == "number" and down > 0 then
                main = _MOUSE_KEYID[idx]
                primary_is_mouse = true
                break
            end
        end
    end
    if not main then return nil end
    local combo = { main }                                  -- VMF: primary key FIRST
    for _, m in ipairs(mods) do combo[#combo + 1] = m end   -- then normalised modifiers
    return combo, primary_is_mouse
end

-- (#123) Apply a keybind change THE WAY VMF DOES (vmf_options_view ~734): save the value,
-- re-register via the owning mod's add_mod_keybind, then generate_keybinds to activate. A
-- plain mod:set does NOT make the bind fire (that was the bug). keys={} unbinds. The printf
-- reports whether add_mod_keybind + generate_keybinds actually landed. See VMF_AND_USER_SETTINGS.md.
local function _commit_keybind(row, keys)
    local cat = row and row._category
    local sid = row and row._setting_id
    -- (#208) For the merged Equipment tab, resolve the keybind's OWNER mod object from the
    -- node (cat._owners[sid]); falls back to the category's single mod_obj for normal tabs.
    local owner = cat and cat._owners and sid and cat._owners[sid]
    local mod_obj = (owner and owner.mod_obj) or (cat and cat.mod_obj)
    local vmf = get_mod("VMF")
    if not mod_obj or not sid or not vmf then
        _printf("[gut:keybind] cannot commit: mod_obj=%s sid=%s vmf=%s", tostring(mod_obj), tostring(sid), tostring(vmf))
        return false
    end
    local d = row._keybind_def or {}
    -- VMF API (PROVEN by the v0.2.101 [gut:keybind] log: 'add_mod_keybind a nil value' on the
    -- mod object, generate_keybinds=true): add_mod_keybind is vmf.add_mod_keybind(mod, setting_id,
    -- data), NOT a mod method. generate_keybinds is vmf.generate_keybinds(). Register FIRST; only
    -- persist + generate if it landed, so a failed call can't leave an inconsistent keybind state.
    local reg_ok, reg_err = pcall(vmf.add_mod_keybind, mod_obj, sid, {
        keys            = keys,
        type            = d.keybind_type,
        trigger         = d.keybind_trigger,
        global          = d.keybind_global,
        function_name   = d.function_name,
        view_name       = d.view_name,
        transition_data = d.transition_data,
    })
    local gen_ok = false
    if reg_ok then
        pcall(function() mod_obj:set(sid, keys, true) end)   -- persist to user_settings.config
        if vmf.generate_keybinds then gen_ok = pcall(vmf.generate_keybinds) end
    end
    row.content.value_text = _format_keybind_value(keys)
    _printf("[gut:keybind] %s.%s -> %s | add_mod_keybind=%s%s generate_keybinds=%s",
        tostring(cat.mod_id), tostring(sid), _format_keybind_value(keys),
        tostring(reg_ok), reg_ok and "" or (" ERR=" .. tostring(reg_err)), tostring(gen_ok))
    return true
end

-- (#208) Per-NODE owner resolution for the synthesized "Equipment" category, which merges
-- up to four inventory mods (Cosmetics / Crafting / Weapons / Career Weapon Variants) into
-- one tab. A normal category has a single `mod_obj`/`mod_id`; the Equipment category instead
-- carries `_owners[setting_id] = { mod_id, mod_obj }` for every member setting so get/set/
-- stage/apply route to the OWNING mod object. For every NON-Equipment category `_owners` is
-- nil, so this returns `category.mod_obj` / `category.mod_id` — byte-for-byte the prior path.
local function _owner(category, setting_id)
    local owners = category and category._owners
    if owners and setting_id ~= nil then
        local o = owners[setting_id]
        if o then return o.mod_obj, o.mod_id end
    end
    return category and category.mod_obj, category and category.mod_id
end

local function _cat_get(category, setting_id)
    local mod_obj, mod_id = _owner(category, setting_id)
    if mod_obj then
        local ok, v = pcall(mod_obj.get, mod_obj, setting_id)
        if ok then return v end -- false is an owned setting, not absence
        return nil
    end
    local MT = _mt()
    return MT and MT:get(mod_id, setting_id)
end

local function _cat_set(category, setting_id, value)
    local mod_obj, mod_id = _owner(category, setting_id)
    if mod_obj then
        -- 3rd arg true => fire the mod's on_setting_changed so it reacts live
        -- (matches stock VMF options behaviour). Persistence is automatic.
        pcall(mod_obj.set, mod_obj, setting_id, value, true)
        return
    end
    local MT = _mt()
    if MT then MT:set(mod_id, setting_id, value) end
end

-- Native menu sound feedback. (v0.2.82-dev) fixed this twin's silent menu by
-- resolving the wwise world exactly as vanilla OptionsView does
-- (options_view.lua:282-288); (#1670) that resolver now lives in
-- _mod_tweaker_sound.lua so the keep sub-state (the /mod_tweaker command route)
-- fires on the same world instead of its own stale lookup.
local sound = mod:dofile("scripts/mods/gui_tweaker_dev/_mod_tweaker_sound")
local _wwise_probe = sound.new_probe("standalone")
local _play_event = sound.play
-- (#1670) Published for the issue1670_command_route_sound_path check.
ModTweakerView.gut_sound_resolve = sound.resolve
-- Commit/click sound (checkbox flip, arrow click, dropdown cycle, slider release).
local function _play_click() _play_event("Play_hud_select") end
-- Hover sound — fire on the EDGE (hover-enter) only, never every frame.
local function _play_hover() _play_event("Play_hud_hover") end
-- Menu-open sound — the exact event vanilla OptionsView.on_enter
-- (options_view.lua:1615) fires when the settings menu opens. Plays once on
-- view-enter so the Mod Tweaker matches native menu feel.
local function _play_open() _play_event("Play_hud_button_open") end
-- Menu-close sound — the matching event vanilla OptionsView fires when the
-- settings menu closes (options_view.lua:1691 / :2594). Plays once on view-exit
-- so the Mod Tweaker's close matches native menu feel. (v0.2.82-dev — ITEM 1.)
local function _play_close() _play_event("Play_hud_button_close") end

-- Category assembly keeps the existing deferred rebuild pcall boundary.
-- Rows, transactions and lifecycle remain in this presentation owner.
local CategoryCatalog = mod:dofile("scripts/mods/gui_tweaker_dev/_mod_tweaker_view_catalog")
local _vmf_categories = CategoryCatalog.bind({
    mod = mod, get_mod = function(...) return get_mod(...) end, nf = _nf,
    disabled_sections = disabled_sections, external_group = external_group,
    printf = _printf, math = math,
})

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
-- The entry installs this closed cluster from _mod_tweaker_view_pending before the
-- class can be constructed. Its private second-return binder below captures these
-- already-defined _cat_set / _play_click locals, never a forward global reference.
-- The TWIN (state) retains its own original installation point and behavior.
-- No staged method is called while the retained presentation children install.
-- ---------------------------------------------------------------

-- Stable buffer key for a category (the category table is rebuilt on _rebuild; the
-- mod_id string is stable across rebuilds).

-- ---------------------------------------------------------------
-- Build the row widgets for a category. VMF categories carry a FLAT node array;
-- gut's own dogfood category is NESTED (walk it). Every factory call is pcall'd
-- so one bad node can't blank the view. Editable: checkbox, numeric (stepper),
-- dropdown (option cycler). Read-only: group titles, keybind, text, unknown.
-- ---------------------------------------------------------------
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
function ModTweakerView:_group_key(w, category)
    local setting_id = _nf(w, "setting_id")
    -- (#208) Localize against the node's OWNER mod (Equipment members belong to four mods);
    -- _owner returns category.mod_obj for normal categories, so this is unchanged there.
    local label = category._flat and _vmf_label(w, (_owner(category, setting_id)))
                  or tostring(w.label or w.text or w.setting_id or "?")
    return (category.mod_id or "?") .. ":" .. tostring(setting_id or label)
end

-- (#163) Auto-collapse ("one branch open per level"). Gated on gut_mt_auto_collapse, default ON.
function ModTweakerView:_auto_collapse_on()
    local v = mod:get("gut_mt_auto_collapse")
    if v == nil then return true end
    return v and true or false
end

-- When a group is OPENED, collapse its SAME-LEVEL siblings (groups sharing the same parent block,
-- at the same depth). When a group is CLOSED, collapse its nested DESCENDANT groups (so re-opening
-- shows a clean collapsed sub-tree). Level-aware via the flat node/depth arrays saved at build.
function ModTweakerView:_auto_collapse_apply(gid, now_expanded)
    local nodes, depths, cat = self._build_nodes, self._build_depths, self._build_category
    if not (nodes and depths and cat) then return end
    local i
    for k = 1, #nodes do
        if _nf(nodes[k], "type") == "group" and self:_group_key(nodes[k], cat) == gid then i = k; break end
    end
    if not i then return end
    local d = depths[i]
    if now_expanded then
        -- siblings = depth==d groups inside this group's parent block (bounded by the nearest
        -- shallower node on each side; lo/hi=outside for top-level groups).
        local lo, hi = 0, #nodes + 1
        for j = i - 1, 1, -1 do if depths[j] < d then lo = j; break end end
        for j = i + 1, #nodes do if depths[j] < d then hi = j; break end end
        for j = lo + 1, hi - 1 do
            if j ~= i and depths[j] == d and _nf(nodes[j], "type") == "group" then
                self._expanded[self:_group_key(nodes[j], cat)] = nil
            end
        end
    else
        -- descendants = the contiguous run of deeper nodes immediately after i.
        for j = i + 1, #nodes do
            if depths[j] <= d then break end
            if _nf(nodes[j], "type") == "group" then
                self._expanded[self:_group_key(nodes[j], cat)] = nil
            end
        end
    end
end

-- #2: one hook-free owner builds setting rows and their adjacent gear widgets.
local ViewRows = mod:dofile("scripts/mods/gui_tweaker_dev/_mod_tweaker_view_rows")
ViewRows.install(ModTweakerView, {
    mod = mod, defs = defs, math = math,
    mt = _mt, nf = _nf, owner = _owner,
    vmf_label = _vmf_label, vmf_tooltip = _vmf_tooltip,
    cat_get = _cat_get, resolve_step = _resolve_step,
    format_keybind_value = _format_keybind_value,
})

-- (#497) Localized display label for a node, mirroring the label logic in _build_node_row
-- (flat/VMF categories localize via the owner mod; nested gut nodes use the raw field). The
-- search filter matches against the SAME text the row renders. Caller lowercases for matching.
local function _node_label(category, w)
    local setting_id = _nf(w, "setting_id")
    if category._flat then
        return _vmf_label(w, (_owner(category, setting_id)))
    end
    return tostring(w.label or w.text or w.setting_id or "?")
end

-- (#497) The active search term (lowercased, trimmed) or nil when the box is empty/whitespace.
-- _build_rows renders the filtered flat list only when this returns non-nil.
function ModTweakerView:_search_active()
    local s = self._search_str
    if type(s) ~= "string" then return nil end
    s = s:gsub("^%s+", ""):gsub("%s+$", "")
    if s == "" then return nil end
    return s:lower()
end

function ModTweakerView:_search_restore()
    if not self._search_tx then return false end
    Search.restore(self._expanded, self._search_tx)
    self._search_tx = nil
    self._search_rebuild_pending = nil
    self._search_last_ancestors = nil
    self._search_top_ancestors = nil
    return true
end

function ModTweakerView:_search_clear_restore()
    local changed = self:_search_restore()
    self._search_str = ""
    self._search_focused = false
    return changed
end

function ModTweakerView:_search_finish()
    if not self._search_tx then return false end
    Search.finish(self._expanded, self._search_tx, self._search_last_ancestors,
        self._search_top_ancestors, self:_auto_collapse_on())
    self._search_tx = nil
    self._search_str = ""
    self._search_focused = false
    self._search_rebuild_pending = nil
    self._search_last_ancestors = nil
    self._search_top_ancestors = nil
    return true
end

-- Result interactions keep search alive. Remember only settings that actually stage a value;
-- Escape/outside-click later retains this branch instead of whichever row was merely opened.
function ModTweakerView:_search_note_setting(category, setting_id)
    if not self._search_tx then return end
    for i = 1, #(self._rows or {}) do
        local row = self._rows[i]
        if row and row._category == category and row._setting_id == setting_id
           and type(row._search_ancestors) == "table" then
            self._search_last_ancestors = row._search_ancestors
            return
        end
    end
end

local function _hot(h)
    return h and (h.is_hover or h.is_held or h.on_release or h.on_left_release)
end

function ModTweakerView:_search_pointer_over_result()
    for i = 1, #(self._rows or {}) do
        local row = self._rows[i]
        local c = row and row.content
        if row and not row._readonly and row._middle_visible ~= false and c
           and (_hot(c.hotspot) or _hot(c.row_hs) or _hot(c.dec) or _hot(c.inc)
                or _hot(c.track_hs) or _hot(c.value_hs)) then
            return true
        end
    end
    return false
end

function ModTweakerView:_search_pointer_over_chrome()
    local function widget_hot(widget, hotspot)
        local c = widget and widget.content
        return c and _hot(c[hotspot])
    end
    if widget_hot(self._exit, "button_hotspot") or widget_hot(self._apply, "button_hotspot")
       or widget_hot(self._reset, "button_hotspot") or widget_hot(self._scrollbar, "hotspot") then
        return true
    end
    for i = 1, #(self._tabs or {}) do
        if widget_hot(self._tabs[i], "hotspot") then return true end
    end
    for i = 1, #(self._profile_buttons or {}) do
        if widget_hot(self._profile_buttons[i], "hotspot") then return true end
    end
    return false
end

local function _order_category_nodes(category, nodes, depths)
    return ordering.order_flat(nodes, depths, {
        preserve_all = category.mod_id == "gut_equipment",
        get_type = function(node) return _nf(node, "type") end,
        is_generated_header = function(node) return _nf(node, "mod_name") ~= nil end,
        get_label = function(node)
            local owner = _owner(category, _nf(node, "setting_id"))
            return _vmf_label(node, owner or category.mod_obj)
        end,
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

function ModTweakerView:_build_rows(category)
    self._rows = {}
    -- Any in-progress type-edit is abandoned on a rebuild (tab switch / drill / collapse):
    -- the old row widget is discarded here, so drop the dangling editor reference too.
    self._editing_row = nil
    -- (v0.2.69-dev) An open dropdown popup is likewise abandoned on a rebuild — its
    -- collapsed row widget is being discarded, so drop the dangling open-dropdown refs.
    self._open_dropdown = nil
    self._dd_list = nil
    -- (#207) The hovered tooltip row is one of the rows being discarded; drop the dangling
    -- reference so a stale widget can't be redrawn (the fade machine re-acquires next frame).
    self._tt_row = nil
    if not category or type(category.widgets) ~= "table" then return end
    self._expanded = self._expanded or {}   -- group_key -> true (expanded); default collapsed

    -- #605: the 34k-line Character Dialogue catalogue is a virtual data source,
    -- not a VMF widget tree. Build only the rows intersecting the scroll window.
    self._dialogue_category = false
    if DialogueUI.is_category(category) then
        DialogueUI.build(self, category, defs)
        return
    end

    -- Flatten into parallel node + depth arrays. The VMF flat list ships its own
    -- `depth`; the gut nested tree gets a synthesized depth from _walk_nested. Both
    -- then feed the SAME drill-detection ("the next node is deeper") + inline-skip.
    -- (#208) The synthesized Equipment category is flat too but carries a precomputed
    -- `_depths` array (its section headers + depth-shifted member nodes); use it when
    -- present, else fall back to each node's own `depth` field. (0 is truthy in Lua, so a
    -- depth-0 entry survives the `or` fallback.)
    local nodes, depths = {}, {}
    if category._flat then
        local pd = category._depths
        -- A plain VMF tab (no synthesized _depths) carries VMF's natural per-node `depth`,
        -- which starts at 1 for the mod's top-level content — indenting the WHOLE tab one level
        -- for no reason. Rebase by the tab's MINIMUM natural setting depth (excluding the
        -- non-rendered per-mod header) so its top-level rows render at depth 0 (no indent), the
        -- same as the Equipment tab. Equipment supplies its own already-rebased `_depths`. (#208)
        local min_d
        if not pd then
            for i = 1, #category.widgets do
                local w = category.widgets[i]
                if _nf(w, "type") ~= "header" then
                    local d = _nf(w, "depth")
                    if type(d) == "number" and (not min_d or d < min_d) then min_d = d end
                end
            end
            min_d = min_d or 0
        end
        for i = 1, #category.widgets do
            nodes[#nodes + 1] = category.widgets[i]
            if pd then
                depths[#depths + 1] = pd[i] or _nf(category.widgets[i], "depth") or 0
            else
                depths[#depths + 1] = (_nf(category.widgets[i], "depth") or 0) - min_d
            end
        end
    else
        for i = 1, #category.widgets do _walk_nested(category.widgets[i], nodes, depths, 0) end
    end
    nodes, depths = _order_category_nodes(category, nodes, depths)
    -- (#446) Upgrade a complete same-parent exclusive cluster from scattered VMF
    -- checkbox rows to one synthetic collapsible with a None/default radio row and
    -- one radio row per real setting. The pure planner fails closed for cross-mod,
    -- incomplete, or structurally scattered clusters, preserving checkbox behavior.
    local MT = _mt()
    if MT and type(MT.get_exclusive_group_id) == "function"
        and type(MT.get_exclusive_members) == "function"
        and type(MT.get_exclusive_presentation) == "function" then
        nodes, depths = ExclusiveLayout.plan(nodes, depths, {
            mod_id = category.mod_id,
            field = _nf,
            get_group_id = function(mod_id, setting_id)
                return MT:get_exclusive_group_id(mod_id, setting_id)
            end,
            get_members = function(group_id) return MT:get_exclusive_members(group_id) end,
            get_presentation = function(group_id)
                return MT:get_exclusive_presentation(group_id)
            end,
        })
    end
    -- (#163) Keep the flat node/depth arrays for the auto-collapse handler — sibling + descendant
    -- detection needs the tree shape; the group toggle in _handle_input reads these.
    self._build_nodes, self._build_depths, self._build_category = nodes, depths, category
    self:_profile_ensure(category)

    local base_offset = { 0, -10, 0 }

    -- (#497) SEARCH FILTER. When the per-tab search box has a term, render a FLAT filtered
    -- list instead of the normal collapse/gear/drill list. A node is kept when its localized
    -- label contains the term ("a setting OR collapsible that matches", case-insensitive),
    -- PLUS every ANCESTOR of a match (so a nested match stays reachable and shows its section
    -- context) and, for a matched GROUP (collapsible), its DESCENDANTS (so the matched
    -- section's contents show). No gears, no collapse, no drill -- results are always fully
    -- expanded and visible. Ancestors/descendants are found from the parallel depth array.
    local term = self:_search_active()
    if term then
        if not self._search_tx or self._search_tx.category ~= category then
            if self._search_tx then Search.restore(self._expanded, self._search_tx) end
            local group_keys = Search.group_keys(nodes,
                function(node) return _nf(node, "type") end,
                function(node) return self:_group_key(node, category) end)
            self._search_tx = Search.begin(self._expanded, group_keys, category)
            self._search_last_ancestors = nil
            self._search_top_ancestors = nil
        end
        self._drill = nil                       -- a search supersedes any drill-down
        local keep = {}
        for i = 1, #nodes do
            if _nf(nodes[i], "type") ~= "header" then
                local lbl = _node_label(category, nodes[i])
                if type(lbl) == "string" and string.find(lbl:lower(), term, 1, true) then
                    keep[i] = true
                end
            end
        end
        -- Freeze the direct-match set, then widen it to ancestors + matched-group descendants.
        local matched, direct = {}, {}
        for i = 1, #nodes do
            if keep[i] then
                matched[#matched + 1] = i
                direct[i] = true
            end
        end
        for _, i in ipairs(matched) do
            local need = depths[i]
            for j = i - 1, 1, -1 do
                if depths[j] < need then
                    keep[j] = true; need = depths[j]
                    if need <= 0 then break end
                end
            end
            if _nf(nodes[i], "type") == "group" then
                for j = i + 1, #nodes do
                    if depths[j] <= depths[i] then break end
                    keep[j] = true
                end
            end
        end
        -- Render kept nodes flat at their natural depth (no gear/collapse). A kept group is
        -- forced expanded (its children already show), so its [+]/[-] can't misread as closed.
        local shown = 0
        for i = 1, #nodes do
            if keep[i] and _nf(nodes[i], "type") ~= "header" then
                local is_group = _nf(nodes[i], "type") == "group"
                local row, err, wtype, setting_id = self:_build_node_row(
                    nodes[i], category, base_offset, depths[i], is_group and true or nil)
                if row then
                    row._search_ancestors = Search.ancestors(nodes, depths, i,
                        function(node) return _nf(node, "type") end,
                        function(node) return self:_group_key(node, category) end)
                    if direct[i] and not self._search_top_ancestors then
                        local path = {}
                        for p = 1, #row._search_ancestors do
                            path[p] = row._search_ancestors[p]
                        end
                        -- A directly matched collapsible is itself the result to retain.
                        if is_group then
                            path[#path + 1] = self:_group_key(nodes[i], category)
                        end
                        self._search_top_ancestors = path
                    end
                end
                self:_append_row(row, err, wtype, category, setting_id, base_offset, false)
                if row then shown = shown + 1 end
            end
        end
        if shown == 0 then
            local ok_n, nr = pcall(defs.create_section_title,
                "No settings match \"" .. tostring(self._search_str) .. "\"", base_offset, 0)
            if ok_n and nr then nr._readonly = true; self._rows[#self._rows + 1] = nr end
        end
        self._content_h = math.abs(base_offset[2]) + 20
        self:_recompute_scroll_bounds()
        self._scroll_y = math.clamp(self._scroll_y or 0, 0, self._max_scroll)
        return
    end

    -- Backspace-to-empty and programmatic clears finish like an explicit dismissal.
    if self._search_tx then
        Search.finish(self._expanded, self._search_tx, self._search_last_ancestors,
            self._search_top_ancestors, self:_auto_collapse_on())
        self._search_tx = nil
        self._search_rebuild_pending = nil
        self._search_last_ancestors = nil
        self._search_top_ancestors = nil
    end

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
            -- (v0.2.153-dev) The parent's OWN toggle row is NOT re-rendered here — you
            -- already toggle it on the main list and the "Advanced: <name>" Back row gives
            -- context, so repeating it was redundant. Children rebase to depth 0 below.
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
                    self:_build_node_row(nodes[p.index], category, base_offset, math.max(0, p.depth - 1))
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
            -- (#208) No special top-section gap — sections/groups stack with the same row
            -- rhythm as every other tab, so the Equipment tab's spacing matches other menus.
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
function ModTweakerView:_recompute_scroll_bounds()
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

function ModTweakerView:_rebuild()
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
            local override = tab_labels.exact(c.mod_id)
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
        local override = tab_labels.exact(cat.mod_id)
        local lbl
        if override then
            lbl = override
        else
            local raw = tostring(cat.label or cat.mod_id):gsub("^Tweaker:%s*", "")
            lbl = _truncate(raw, 16)
        end
        local tab = defs.create_tab(lbl, i)
        if tab then
            tab.content.disabled = (cat.enabled == false)  -- VMF-disabled mod -> greyed-out tab (driver dims it)
            self._tabs[i] = tab
        end
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

    -- (Fix 5, v0.2.149-dev) The bottom hint text was removed (native Options has no hint).

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
function ModTweakerView:_layout_tabs()
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
-- ---------------------------------------------------------------
-- Lifecycle (driven by IngameUI)
-- ---------------------------------------------------------------

function ModTweakerView:on_enter(params)
    -- PRESERVE the origin set by the transition closure (gui_tweaker.lua). on_enter
    -- runs AFTER the closure, so an unconditional assign here would wipe it back to
    -- nil (params.exit_transition is never supplied) and exit() would fall through to
    -- the hardcoded "ingame_menu" again — re-introducing the deprecated-menu bug.
    self._exit_transition = (params and params.exit_transition) or self._exit_transition
    self._active = true
    self._draw_frames = 0
    self._drill = nil   -- always open on the normal list, never a stale drill from a prior open
    self:_search_clear_restore() -- (#559) never carry a search transaction across menu opens
    self._search_str = ""       -- (#497) every open starts unfiltered, on the current tab
    self._search_focused = false
    -- DEFENSIVE re-pin LA's atlas + instrument on every open (site ii). The Mod
    -- Tweaker borrows the long-lived IngameUI renderer; the in-mission 3rd/4th-open
    -- crash on materials/Loremasters-Armoury/armoury_atlas happens because the atlas
    -- can be unloaded between opens. Routes through gut's shared re-pin path (same one
    -- the transition closure uses), which is pcall-guarded and keeps the keepalive's
    -- has_loaded force-load guard intact (NEVER force-loads a non-resident LA package).
    -- `self` here is the ModTweakerView, whose ui_renderer/ui_top_renderer are logged
    -- by the probe to prove the borrowed renderer is the same instance across opens.
    if mod._gut_mt_repin_la then pcall(mod._gut_mt_repin_la, self, "on_enter") end
    self:_rebuild()
    if dx12_diag then dx12_diag:enter(dx12_diag_module.runtime_info(self, "standalone")) end
    self:_dump_state("on_enter"); self:_dump_scrollbar("on_enter"); _wwise_probe()
    -- Native menu-open feedback (matches OptionsView / VMF options menu). pcall'd
    -- inside _play_event, so a missing world or renamed event is silent, never a crash.
    _play_open()

    pcall(function()
        ShowCursorStack.show("ModTweakerView")
        self._cursor_pushed = true
        self.input_manager:block_device_except_service(SERVICE, "keyboard", 1)
        self.input_manager:block_device_except_service(SERVICE, "mouse", 1)
        self.input_manager:block_device_except_service(SERVICE, "gamepad", 1)
    end)
end

function ModTweakerView:on_exit()
    if dx12_diag then dx12_diag:leave("on_exit", self) end
    self:_search_finish() -- (#559) retain last-changed/top-result branch on menu exit
    self._active = false
    self.exiting = nil
    -- (Fix 3, v0.2.151-dev) Cancel a dangling reset-confirm popup so it can't outlive the menu.
    if self._reset_popup_id then
        pcall(function()
            if Managers and Managers.popup then Managers.popup:cancel_popup(self._reset_popup_id) end
        end)
        self._reset_popup_id = nil
    end
    -- Auto-save: if any setting changed while open, emit the TOML to the log so the
    -- companion watcher writes gut_mod_settings.toml (the mod can't write directly).
    -- self._dirty is set ONLY by apply_pending (a LIVE write), never by a pending edit —
    -- so a buffer that was never APPLY'd leaves _dirty false and never exports.
    if self._dirty then
        self._dirty = false
        pcall(function()
            if mod._export_settings_to_log then mod._export_settings_to_log(true) end
        end)
    end
    -- (v0.2.70-dev) DISCARD pending edits on exit. Nothing was written live (staged-change
    -- model), so discard = drop the buffer — no native apply_changes(original_*) re-apply
    -- is needed (that exists only for native's live video-preview). Unapplied edits vanish.
    self._pending = {}
    self._profile_replay = nil -- explicit discard; never reuse a prepared plan
    default_reset.clear(self)
    -- #605: preview playback belongs to the Dialogue view session. Stop it on
    -- every close path without touching natural in-game dialogue.
    pcall(function()
        local cd = get_mod("character_dialogue")
        local api = cd and cd.character_dialogue_api
        if api and api.stop then api.stop() end
    end)
    pcall(function()
        if self._cursor_pushed then
            ShowCursorStack.hide("ModTweakerView")
            self._cursor_pushed = nil
        end
        self.input_manager:device_unblock_all_services("keyboard", 1)
        self.input_manager:device_unblock_all_services("mouse", 1)
        self.input_manager:device_unblock_all_services("gamepad", 1)
    end)
end

function ModTweakerView:exit(return_to_game)
    self:_search_finish() -- (#559) covers X, final Escape, and external exit routing
    self.exiting = true
    -- (v0.2.82-dev — ITEM 1) Native menu-close feedback. exit() is the single funnel
    -- for leaving (ESC, the X button, and return-to-game all route here), so one
    -- _play_close() covers every close path. Mirrors OptionsView's Play_hud_button_close
    -- (options_view.lua:1691/:2594). pcall'd inside _play_event — silent if no world.
    _play_close()
    local transition = (return_to_game and "exit_menu") or self._exit_transition or "ingame_menu"
    if self.ingame_ui and self.ingame_ui.transition_with_fade then
        if transition == "hero_view" then
            -- Re-entering "hero_view" with NO params routes through HeroView's
            -- post_update_on_enter else-branch -> _change_screen_by_index(1) ->
            -- _change_screen_by_name(name) with nil optional_params -> the overview
            -- state gets params.state_params=nil and crashes indexing
            -- .force_ingame_menu (hero_view_state_overview.lua:72, no nil guard).
            -- Supply menu_state_name so it takes the branch that threads our (table)
            -- params through as state_params (same pattern as _gut_open_compendium).
            self.ingame_ui:transition_with_fade(transition, { menu_state_name = "overview" })
        else
            self.ingame_ui:transition_with_fade(transition)
        end
    end
end

function ModTweakerView:transitioning()
    if self.exiting then return true end
    return not self._active
end

function ModTweakerView:input_service()
    return self.input_manager:get_service(SERVICE)
end

function ModTweakerView:post_update_on_enter(params) end
function ModTweakerView:post_update_on_exit(params, was_replaced) end
function ModTweakerView:post_update(dt, t) end

function ModTweakerView:update(dt, t)
    if not self._active then return end
    local input_service = self.input_manager:get_service(SERVICE)
    if not input_service then return end

    if dx12_diag then dx12_diag:before_draw(dx12_diag_module.runtime_info(self, "standalone")) end
    self:_draw(dt, input_service)
    if dx12_diag then dx12_diag:after_draw() end

    self._draw_frames = (self._draw_frames or 0) + 1
    if self._draw_frames % 120 == 1 then
        local ok_sb, sbp = pcall(UISceneGraph.get_world_position, self.ui_scenegraph, defs.scrollbar_sg)
        local sbc = self._scrollbar and self._scrollbar.content
        local sbhs = sbc and sbc.hotspot
        -- thumb_frac = visible/content (the fraction of the track the thumb should
        -- fill). If max_scroll>0 but thumb_frac is ~1 (or nil), the thumb never
        -- shrinks -> "full-size cosmetic scrollbar". scroll_value [0..1] is the
        -- thumb's position along the track.
        mod:debug("[mt:dump] heartbeat frame=%d rows=%d scroll=%d/%d vis_h=%s cont_h=%d thumb_frac=%s scroll_value=%s sb_world=%s sb_hover=%s sb_held=%s",
            self._draw_frames, #self._rows, math.floor(self._scroll_y or 0), math.floor(self._max_scroll or 0),
            tostring(self._visible_h), math.floor(self._content_h or 0),
            sbc and tostring(sbc.thumb_frac) or "nil", sbc and tostring(sbc.scroll_value) or "nil",
            (ok_sb and sbp) and string.format("{%d,%d}", sbp[1], sbp[2]) or "?",
            tostring(sbhs and sbhs.is_hover), tostring(sbhs and sbhs.is_held))
    end

    -- (Fix 3, v0.2.151-dev) While the reset-confirm popup is up, it's MODAL: only poll its
    -- result (the game popup owns input + renders itself); don't process ESC / row input.
    if self._reset_popup_id then
        self:_check_reset_popup()
        return
    end


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
        -- (#123) ESC while CAPTURING a keybind = CLEAR (unbind), like VMF. Consume so it
        -- does NOT also close the menu (the bug: ESC used to leave the menu).
        if self._capturing_keybind then
            local row = self._capturing_keybind
            self._capturing_keybind = nil
            self._kb_mouse_pending = nil   -- (issue 631) drop any deferred mouse hold on ESC-clear
            self:stage_set(row._category, row._setting_id, {})   -- (#123) STAGE the clear; applies on APPLY
            row.content.value_text = _format_keybind_value({})
            _play_click()
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
        -- (#497) ESC priority: if the search box is focused OR a filter is active, the FIRST ESC
        -- clears the search (restores the full tab) and stays in the menu; only a SUBSEQUENT ESC
        -- (no filter, nothing else pending) closes the menu. Ordered after edit/keybind/drill so
        -- ESC first cancels those, matching the "back out one level per ESC" model.
        if self._search_focused or (self._search_str and self._search_str ~= "") then
            self:_search_finish()
            self._scroll_y = 0
            _play_click()
            self:_build_rows(self._categories[self._selected])
            return
        end
        -- (#124) FINAL menu-close (no popup/edit/drill pending) -> return to the GAME via
        -- exit(true) -> "exit_menu", NOT the captured origin (equipment/HeroView). The
        -- origin capture (self._exit_transition) stays as exit()'s fallback, guarding the
        -- deprecated bare IngameView (the v0.2.46 fix). Awaiting in-game confirm —
        -- exit-routing is the v0.2.46-burned area; see _gut_menu_transition_probe.lua.
        self:exit(true)
        return
    end

    self:_handle_input(input_service)
end

function ModTweakerView:destroy()
    if dx12_diag and dx12_diag:snapshot().active then dx12_diag:leave("destroy", self) end
    -- #605: destruction can bypass on_exit during state replacement.
    DialogueUI.stop()
    pcall(function()
        if self._cursor_pushed then
            ShowCursorStack.hide("ModTweakerView")
            self._cursor_pushed = nil
        end
    end)
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
-- decimals>0, Backspace, 16-char cap.
local ViewDiagnostics = mod:dofile("scripts/mods/gui_tweaker_dev/_mod_tweaker_view_diagnostics")
ViewDiagnostics.install(ModTweakerView, {
    defs = defs, UISceneGraph = UISceneGraph, math = math,
})
local Interaction = mod:dofile("scripts/mods/gui_tweaker_dev/_mod_tweaker_view_interaction")
Interaction.install(ModTweakerView, {
    defs = defs,
    DialogueUI = DialogueUI,
    UIRenderer = UIRenderer,
    UISceneGraph = UISceneGraph,
    UIInverseScaleVectorToResolution = UIInverseScaleVectorToResolution,
    math = math,
    DD_FILTER_MIN = DD_FILTER_MIN,
    mt = _mt,
    resolve_step = _resolve_step,
    format_keybind_value = _format_keybind_value,
    poll_keybind_combo = _poll_keybind_combo,
    cat_set = _cat_set,
    cat_get = _cat_get,
    play_click = _play_click,
    play_hover = _play_hover,
    printf = _printf,
    slider_drag_edge = mod:dofile(
        "scripts/mods/gui_tweaker_dev/_mod_tweaker_slider_drag_edge"),
})
return ModTweakerView, function(install)
    return install(ModTweakerView, {
        mod = mod, transactions = transactions, default_reset = default_reset,
        profiles = profiles, profile_runtime = profile_runtime, DialogueUI = DialogueUI,
        owner = _owner, nf = _nf, cat_get = _cat_get, cat_set = _cat_set,
        mt = _mt, printf = _printf, play_click = _play_click, commit_keybind = _commit_keybind,
    })
end
