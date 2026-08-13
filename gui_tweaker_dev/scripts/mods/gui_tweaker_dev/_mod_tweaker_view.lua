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

-- Third-party mod whose options fold into a gut category (NOT a tab). #339.
local _CKC_NAME = "Crosshair Kill Confirmation"

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
        return ok and v or nil
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

-- Native menu sound feedback. The real Options menu fires Wwise events on the
-- view's wwise_world: "Play_hud_select" on a commit (options_view.lua:544 etc.)
-- and "Play_hud_hover" on hover-enter (options_view.lua:423 etc.).
--
-- (v0.2.82-dev) ROOT-CAUSE FIX for "no menu sounds" (enter/exit/click/hover all
-- silent in the standalone in-mission view). The prior helper did
-- `World.wwise_world(Managers.world:world("music_world"))` — WRONG on PC. On
-- Windows `GLOBAL_MUSIC_WORLD = true` (boot_init.lua:23), so the music world is
-- NOT registered with Managers.world; it lives as the standalone boot globals
-- `MUSIC_WORLD` / `MUSIC_WWISE_WORLD` (boot_init.lua:31-33). `Managers.world:world
-- ("music_world")` therefore returns nil (or a foreign world) and the helper
-- yielded a nil/silent wwise_world, so every WwiseWorld.trigger_event no-op'd.
-- Resolve it EXACTLY as vanilla OptionsView does (options_view.lua:282-288):
-- prefer the pre-resolved MUSIC_WWISE_WORLD global when GLOBAL_MUSIC_WORLD is set,
-- else fall back to Managers.world:wwise_world(world). pcall-guarded; a missing
-- world is silent, never a crash. A one-time debug probe logs which worlds expose
-- a usable wwise_world, so if Play_hud_* are inaudible the log shows the resolution.
local _wwise_probed = false
local function _wwise_world()
    -- PC path: the boot-global music wwise world (vanilla's first branch).
    if rawget(_G, "GLOBAL_MUSIC_WORLD") and rawget(_G, "MUSIC_WWISE_WORLD") then
        return MUSIC_WWISE_WORLD
    end
    -- Fallback (consoles / dedicated): the music world registered with Managers.world,
    -- resolved via the MANAGER's wwise_world(world) accessor (matches options_view:287),
    -- not World.wwise_world(world) — the manager owns the per-world wwise handle.
    local world = Managers.world and Managers.world:has_world("music_world")
                  and Managers.world:world("music_world")
    return world and Managers.world:wwise_world(world)
end
local function _wwise_probe()
    if _wwise_probed then return end
    _wwise_probed = true
    pcall(function()
        -- (v0.2.82-dev) Log the boot-global music world FIRST — that's the one the
        -- real OptionsView uses on PC and the one _wwise_world() now resolves.
        mod:debug("[mt:wwise] GLOBAL_MUSIC_WORLD=%s MUSIC_WWISE_WORLD=%s resolved=%s",
            tostring(rawget(_G, "GLOBAL_MUSIC_WORLD")), tostring(rawget(_G, "MUSIC_WWISE_WORLD") ~= nil),
            tostring(_wwise_world() ~= nil))
        local names = { "music_world", "top_ingame_view", "level_world" }
        for i = 1, #names do
            local w = Managers.world and Managers.world:has_world(names[i]) and Managers.world:world(names[i])
            local ww = w and World.wwise_world(w)
            mod:debug("[mt:wwise] world '%s' present=%s wwise_world=%s",
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
-- Menu-open sound — the exact event vanilla OptionsView.on_enter
-- (options_view.lua:1615) fires when the settings menu opens. Plays once on
-- view-enter so the Mod Tweaker matches native menu feel.
local function _play_open() _play_event("Play_hud_button_open") end
-- Menu-close sound — the matching event vanilla OptionsView fires when the
-- settings menu closes (options_view.lua:1691 / :2594). Plays once on view-exit
-- so the Mod Tweaker's close matches native menu feel. (v0.2.82-dev — ITEM 1.)
local function _play_close() _play_event("Play_hud_button_close") end

-- ---------------------------------------------------------------
-- (#208) EQUIPMENT MERGE. The four inventory-management mods get folded into ONE
-- collapsible "Equipment" tab when 2+ are installed. Disabled members retain their
-- normal section header with no editable rows and a "Disabled in VMF" tooltip. Roles:
--   cosmetics_tweaker -> Cosmetics ; cim/cim_dev -> Crafting ; wt/wt_dev -> Weapons ;
--   character_weapon_variants -> Career Weapon Variants.
-- Sections render top-level (Cosmetics, Crafting, Weapons); CWV nests UNDER Weapons
-- when wt/wt_dev is also active, else sits top-level. N=1-only-CWV just relabels that one tab
-- "Weapons". The synthesized category is FLAT (_flat=true) with a parallel `_depths`
-- array (so each member keeps its own internal group/gear nesting, shifted under its
-- section header) + a `_owners[setting_id]` map so get/set/stage/apply route per-node to
-- the owning mod object (see _owner + the staged-change helpers). TWIN of the HeroView
-- sub-state's identical block — keep both in sync.
-- ---------------------------------------------------------------
-- Localize a gut_dev section/tab label; reject a "<missing-key>" marker + fall back to a
-- literal (same guard as _vmf_label). Safe at _rebuild time (loc is registered by then).
local function _equip_loc(key, fallback)
    if mod and mod.localize then
        local ok, s = pcall(mod.localize, mod, key)
        if ok and type(s) == "string" and s ~= "" and not string.find(s, "^<") then return s end
    end
    return fallback
end

-- Post-process the _vmf_categories() output (called just before its final sort).
local function _synthesize_equipment(cats)
    local members, n = disabled_sections.select_equipment_members(cats)
    if n == 0 then return cats end

    if n == 1 then
        -- Only the CWV-alone case changes: its single tab is relabeled "Weapons".
        if members.cwv then members.cwv.label = _equip_loc("gut_equip_weapons", "Weapons") end
        return cats
    end

    -- N >= 2: build the merged Equipment category; drop the folded members from the list.
    local folded = {}
    for _, c in pairs(members) do folded[c] = true end
    local rest = {}
    for _, c in ipairs(cats) do if not folded[c] then rest[#rest + 1] = c end end

    local widgets, depths, owners = {}, {}, {}
    local owner_ids, owner_seen = {}, {}
    local function _note_owner(mid)
        if not owner_seen[mid] then owner_seen[mid] = true; owner_ids[#owner_ids + 1] = mid end
    end
    -- One synthetic collapsible group header at `header_depth` (owns no setting).
    local function _add_header(setting_id, label, header_depth, enabled)
        widgets[#widgets + 1] = enabled == false
            and disabled_sections.disabled_header(setting_id, label, header_depth,
                _equip_loc("gut_disabled_in_vmf", disabled_sections.REASON))
            or { setting_id = setting_id, type = "group", title = label }
        depths[#depths + 1] = header_depth
    end
    -- A member's setting nodes (skipping its synthesized VMF header at [1]), rebased so the
    -- member's SHALLOWEST node renders at `target_top_depth` (one level under its section
    -- header), with internal nesting preserved. Records each node's owner.
    local function _add_member(member, target_top_depth)
        if not member or member.enabled == false then return end
        local src = member and member.widgets
        if type(src) ~= "table" then return end
        -- VMF mods' top content usually sits at NATURAL depth 1 (not 0), so blindly adding a
        -- base offset lands it a level too deep — which is why the nested CWV header (correctly
        -- at depth 1) looked un-indented beside wt's content (wrongly at depth 2). Rebase by the
        -- member's OWN minimum natural depth: its shallowest node renders exactly at
        -- target_top_depth (one level under its section header), preserving internal nesting. (#208)
        local min_d
        for i = 2, #src do
            local nd = _nf(src[i], "depth") or 0
            if not min_d or nd < min_d then min_d = nd end
        end
        min_d = min_d or 0
        for i = 2, #src do
            local node = src[i]
            widgets[#widgets + 1] = node
            depths[#depths + 1] = target_top_depth + ((_nf(node, "depth") or 0) - min_d)
            local sid = _nf(node, "setting_id")
            if type(sid) == "string" then
                owners[sid] = { mod_id = member.mod_id, mod_obj = member.mod_obj }
                _note_owner(member.mod_id)
            end
        end
    end

    -- Section order: Cosmetics -> Crafting -> Weapons (deliberate-order exception).
    if members.cosmetics then
        _add_header("__equip_cosmetics", _equip_loc("gut_equip_cosmetics", "Cosmetics"), 0,
            members.cosmetics.enabled)
        _add_member(members.cosmetics, 1)
    end
    if members.crafting then
        _add_header("__equip_crafting", _equip_loc("gut_equip_crafting", "Crafting"), 0,
            members.crafting.enabled)
        _add_member(members.crafting, 1)
    end
    if members.weapons then
        local weapons_header_enabled = members.weapons.enabled ~= false
            or (members.cwv and members.cwv.enabled ~= false)
        _add_header("__equip_weapons", _equip_loc("gut_equip_weapons", "Weapons"), 0,
            weapons_header_enabled)
        _add_member(members.weapons, 1)
        if members.cwv then
            -- CWV nested UNDER Weapons (header depth 1, its settings depth 2+).
            _add_header("__equip_cwv", _equip_loc("gut_equip_cwv", "Career Weapon Variants"), 1,
                members.cwv.enabled)
            _add_member(members.cwv, 2)
        end
    elseif members.cwv then
        -- No wt/wt_dev: CWV sits at the TOP LEVEL of Equipment (no Weapons wrapper).
        _add_header("__equip_cwv", _equip_loc("gut_equip_cwv", "Career Weapon Variants"), 0,
            members.cwv.enabled)
        _add_member(members.cwv, 1)
    end

    rest[#rest + 1] = {
        mod_id = "gut_equipment",
        label = _equip_loc("gut_equip_tab", "Equipment"),
        widgets = widgets,
        _depths = depths,             -- parallel depth array (consumed by _build_rows)
        _owners = owners,             -- setting_id -> { mod_id, mod_obj } (consumed by _owner)
        _owner_mod_ids = owner_ids,   -- member mod_ids (dirty-check + apply iteration)
        mod_obj = nil,                -- spans multiple mods; per-node ownership via _owners
        enabled = true,
        _flat = true,
    }
    return rest
end

-- (#339) Fold Crosshair Kill Confirmation's live options INTO gut's "Interface" tab
-- under the HUD group, as a "Crosshair Kill Confirmation" sub-collapsible -- NOT a
-- top-level tab (the mistake #313 made). Reuses the _synthesize_equipment `_owners`
-- mechanism to route CKC nodes to the real CKC mod, but MUTATES the existing gut
-- category instead of appending a new one. See MOD_TWEAKER_INTEGRATION.md.
--
-- Correctness notes (traps handled):
--   * NEVER mutate VMF's own list in place (it is reused every _rebuild) -- gut's widget
--     array is COPIED and CKC's nodes are shallow-COPIED before stamping depth.
--   * gut's category is MIXED-owner (its own settings + injected CKC settings), so
--     _owner_mod_ids MUST include BOTH gut's id and CKC -- else apply/dirty (which take
--     the `if _owner_mod_ids` branch) would flush ONLY CKC and silently drop every gut
--     Interface edit. mod_obj stays = gut so gut's own settings fall back via _owner.
--   * gut's category is _flat=true; the flat render path reads each node's own `depth`
--     (rebased by the tab's min depth), so injected nodes MUST carry a `depth` in gut's
--     natural depth space (HUD group depth + 1 for the sub-header, +2 for its options).
local function _inject_ckc_into_gut(out)
    local ckc = get_mod(_CKC_NAME)
    if not ckc then return end                        -- CKC not installed: nothing to fold
    local gut_cat
    for _, c in ipairs(out) do
        if c.mod_id == "gut" or c.mod_id == "gut_dev" then gut_cat = c; break end
    end
    if not gut_cat or type(gut_cat.widgets) ~= "table" then return end

    local vmf = get_mod("VMF")
    local wd = vmf and vmf.options_widgets_data
    if type(wd) ~= "table" then return end
    local ckc_list
    for _, list in ipairs(wd) do
        local h = (type(list) == "table") and list[1]
        if h and _nf(h, "mod_name") == _CKC_NAME then ckc_list = list; break end
    end
    if type(ckc_list) ~= "table" or #ckc_list < 2 then return end  -- no real options

    -- Locate the HUD group node in gut's flat list.
    local src = gut_cat.widgets
    local hud_idx, hud_depth
    for i = 1, #src do
        if _nf(src[i], "setting_id") == "gut_hide_hud_ui_group" then
            hud_idx = i; hud_depth = _nf(src[i], "depth") or 0; break
        end
    end
    if not hud_idx then return end
    -- (#527) [CKC-SPLICE-FIRST-527] The block splices at the START of the HUD child
    -- block (immediately after the HUD group header), not the end: collapsible
    -- sub-groups sort FIRST at their level (user doctrine, issue 527), and
    -- "Crosshair Kill Confirmation" precedes "UI Tweaks" A-Z, so the head of the
    -- block IS its alphabetical slot among the HUD sub-groups.
    local ins_idx = hud_idx + 1

    -- Build the CKC sub-group block: a group header at HUD+1, CKC options rebased to HUD+2.
    -- Title is the mod's proper name as a literal (a non-key string): _vmf_label localizes
    -- against gut, gets a "<...>" miss, and falls back to this literal. Keeps the injection
    -- self-contained without editing gut's loc file.
    local block = { { setting_id = "gut_ckc_group", type = "group",
                      title = _CKC_NAME, depth = hud_depth + 1 } }
    local ckc_min
    for i = 2, #ckc_list do
        local d = _nf(ckc_list[i], "depth") or 0
        if not ckc_min or d < ckc_min then ckc_min = d end
    end
    ckc_min = ckc_min or 0
    local owners = gut_cat._owners or {}
    for i = 2, #ckc_list do
        local node = ckc_list[i]
        local nn = {}                                 -- shallow copy (never mutate VMF's node)
        for k, v in pairs(node) do nn[k] = v end
        nn.depth = hud_depth + 2 + ((_nf(node, "depth") or 0) - ckc_min)
        block[#block + 1] = nn
        local sid = _nf(node, "setting_id")
        if type(sid) == "string" then owners[sid] = { mod_id = _CKC_NAME, mod_obj = ckc } end
    end

    -- Splice the block into a COPY of gut's widget list at the START of the HUD child
    -- block (#527; see [CKC-SPLICE-FIRST-527] above).
    local new_w = {}
    for i = 1, ins_idx - 1 do new_w[#new_w + 1] = src[i] end
    for i = 1, #block do new_w[#new_w + 1] = block[i] end
    for i = ins_idx, #src do new_w[#new_w + 1] = src[i] end

    gut_cat.widgets = new_w
    gut_cat._owners = owners
    gut_cat._owner_mod_ids = { gut_cat.mod_id, _CKC_NAME }   -- MIXED: flush BOTH buffers
    -- gut_cat.mod_obj stays = gut (its own settings fall back via _owner)
end

-- (#312) Fold the STOCK UI Tweaks (HideBuffs) live VMF widget tree into GUT and
-- route its setting get/set calls to the stock mod, never GUT's private fallback
-- copies. This is a dynamic tree splice, not a copied setting-id allow-list, so a
-- future supported widget type appears without editing GUT. Reads show HideBuffs'
-- live value; Apply commits through HB:set(id, v, true), firing its ordinary VMF
-- callback and persistence path. The per-node _owners model is shared with the
-- Equipment merge (#208) and CKC injection (#339).
-- HideBuffs becomes the single owner of its live tree. No-op when HideBuffs is absent
-- or disabled: gut's own copies drive its absorbed hb/ fork exactly as before. Runs AFTER
-- _inject_ckc_into_gut so it MERGES into any CKC-set _owner_mod_ids. Marker
-- [UITWEAKS-BRIDGE-312]. Byte-parallel twin with the one in _mod_tweaker_state.lua.
local function _bridge_uitweaks_to_stock(out)
    local HB = get_mod("HideBuffs")
    if not HB then return end                          -- stock UI Tweaks absent: gut owns its copies
    if type(HB.is_enabled) == "function" then
        local ok_en, en = pcall(HB.is_enabled, HB)
        if ok_en and en == false then
            local gut_cat
            for _, c in ipairs(out) do
                if c.mod_id == "gut" or c.mod_id == "gut_dev" then gut_cat = c; break end
            end
            if gut_cat then
                gut_cat.widgets = disabled_sections.disable_group_subtree(gut_cat.widgets,
                    "hb_group",
                    _equip_loc("gut_disabled_in_vmf", disabled_sections.REASON))
            end
            return                                    -- present but disabled: explained header only
        end
    end
    local gut_cat
    for _, c in ipairs(out) do
        if c.mod_id == "gut" or c.mod_id == "gut_dev" then gut_cat = c; break end
    end
    if not gut_cat or type(gut_cat.widgets) ~= "table" then return end

    -- Consume the stock mod's CURRENT VMF widget list, not the old absorbed fork's
    -- copied checkbox catalogue. A future UI Tweaks group, slider, dropdown, or
    -- keybind therefore appears without a GUT code change. The planner shallow-copies
    -- every VMF node, rebases it under hb_group, removes stale mirrored rows, and
    -- preserves GUT's own Sync & Vanilla Mirrors subgroup. [UITWEAKS-LIVE-TREE-312]
    local vmf = get_mod("VMF")
    local live = external_group.find_mod_list(vmf and vmf.options_widgets_data,
        "HideBuffs", _nf)
    local plan = external_group.replace_group_children({
        widgets = gut_cat.widgets,
        live_list = live,
        group_id = "hb_group",
        preserve_group_ids = { gut_uitweaks_integration_group = true },
        field = _nf,
        owners = gut_cat._owners,
        owner_mod_ids = gut_cat._owner_mod_ids,
        base_owner_id = gut_cat.mod_id,
        owner_id = "HideBuffs",
        owner_obj = HB,
        profile_excluded_owners = gut_cat._profile_excluded_owners,
        exclude_owner_from_profiles = true,
    })
    if not plan.changed then
        if not mod._gut_uitweaks_live_tree_missing_logged then
            mod._gut_uitweaks_live_tree_missing_logged = true
            _printf("[gut:312] live UI Tweaks tree unavailable reason=%s; keeping authored fallback",
                tostring(plan.reason))
        end
        local fallback = external_group.bridge_known_fallback({
            widgets = gut_cat.widgets,
            setting_names = HB.SETTING_NAMES,
            field = _nf,
            owners = gut_cat._owners,
            owner_mod_ids = gut_cat._owner_mod_ids,
            base_owner_id = gut_cat.mod_id,
            owner_id = "HideBuffs",
            owner_obj = HB,
            profile_excluded_owners = gut_cat._profile_excluded_owners,
            exclude_owner_from_profiles = true,
        })
        if fallback.changed then
            gut_cat._owners = fallback.owners
            gut_cat._owner_mod_ids = fallback.owner_mod_ids
            gut_cat._profile_excluded_owners = fallback.profile_excluded_owners
        end
        return
    end
    gut_cat.widgets = plan.widgets
    gut_cat._owners = plan.owners
    gut_cat._owner_mod_ids = plan.owner_mod_ids
    -- UI Tweaks owns its own profiles. Its live rows remain editable here, but
    -- GUT's ten per-tab profile slots never capture or restore HideBuffs values.
    gut_cat._profile_excluded_owners = plan.profile_excluded_owners
    -- gut_cat.mod_obj stays = gut (its own non-bridged settings fall back via _owner).
end

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
        if type(mod_name) == "string" and disabled_sections.is_author_mod(mod_name) then
            local mod_obj = get_mod(mod_name)
            local label = _nf(header, "readable_mod_name") or mod_name
            -- (Fix 3) gut's OWN Mod Tweaker tab reads "Interface" (this IS the interface/GUI
            -- menu), not the VMF readable_mod_name. Label-only override — the mod id, Workshop
            -- title, and .mod/cfg are untouched. Applies to both the stable + dev ids.
            if mod_name == "gut" or mod_name == "gut_dev" then label = "Interface" end
            local enabled = true
            if mod_obj and mod_obj.is_enabled then
                local ok_en, en = pcall(mod_obj.is_enabled, mod_obj)
                if ok_en then enabled = en and true or false end
            end
            -- #318 revised contract: retain installed disabled mods so synthesis can
            -- place an explained grey header in the normal merged section. An
            -- unsynthesized single-mod category retains the established disabled tab.
            out[#out + 1] = {
                mod_id = mod_name, label = label, widgets = list,
                mod_obj = mod_obj, enabled = enabled, _flat = true,
            }
        end
    end
    -- (#339) Fold Crosshair Kill Confirmation into gut's Interface tab under HUD (NOT a
    -- tab). No-op when CKC is absent. Before the sort (it mutates the existing gut cat).
    _inject_ckc_into_gut(out)
    -- (#312) Bridge gut's UI Tweaks toggles to the stock HideBuffs mod's live settings
    -- (own-or-pin) so the Mod Tweaker stays consistent with UI Tweaks' own VMF options.
    -- After CKC injection (it merges into any CKC-set _owner_mod_ids), before the sort.
    _bridge_uitweaks_to_stock(out)
    -- (#208) Fold the four inventory mods into one "Equipment" tab when 2+ are active
    -- (or relabel the N=1-only-CWV tab). Done BEFORE the sort so Equipment participates.
    out = _synthesize_equipment(out)
    table.sort(out, function(a, b)
        if a.enabled ~= b.enabled then return a.enabled end
        return tostring(a.label) < tostring(b.label)
    end)
    return out
end

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
-- DEFINED HERE (after the _cat_set / _play_click file-locals) — placing it right after
-- the class declaration would capture the GLOBAL (nil) _cat_set, because those locals
-- aren't yet in lexical scope there (forward-reference trap). The TWIN (state) defines
-- _cat_set BEFORE its class declaration, so it can place these earlier; the behaviour is
-- byte-identical either way.
-- ---------------------------------------------------------------

-- Stable buffer key for a category (the category table is rebuilt on _rebuild; the
-- mod_id string is stable across rebuilds).
local function _cat_key(category)
    return category and category.mod_id or "?"
end

-- Stage one edit into the pending buffer (replaces the live _cat_set on every row edit).
-- Records the value + refreshes the APPLY button dirty state. (#208) The buffer is keyed by
-- the OWNER mod_id resolved from the node, so an Equipment edit to e.g. a cosmetics setting
-- buffers under "cosmetics_tweaker"; for a normal category _owner returns category.mod_id, so
-- the key is _cat_key(category) exactly as before.
function ModTweakerView:stage_set(category, setting_id, value)
    local _, owner_id = _owner(category, setting_id)
    local key = owner_id or _cat_key(category)
    self._pending[key] = self._pending[key] or {}
    self._pending[key][setting_id] = value
    self:_search_note_setting(category, setting_id)
    -- NOTE: do NOT set self._dirty here. self._dirty drives the auto-save-to-log on exit,
    -- which must reflect LIVE writes only — a pending (unapplied) edit was never written,
    -- so exiting with only-pending edits must NOT export. apply_pending sets _dirty.
    self:_update_apply_button()
end

-- Read a setting's EFFECTIVE value: the staged value if one is pending, else the live
-- value passed in (which the caller read via _cat_get). Mirrors native _get_setting
-- (assigned(pending, live)). (#208) Reads from the OWNER mod_id's buffer (see stage_set).
function ModTweakerView:get_staged(category, setting_id, live_value)
    local _, owner_id = _owner(category, setting_id)
    local p = self._pending[owner_id or _cat_key(category)]
    if p and p[setting_id] ~= nil then return p[setting_id] end
    return live_value
end

-- True if the ACTIVE category has any pending edit (drives APPLY enabled/greyed). (#208) The
-- merged Equipment category buffers under EACH member mod_id, so it's dirty if ANY member's
-- buffer is non-empty; a normal category checks its single _cat_key buffer as before.
function ModTweakerView:_active_category_dirty()
    local cat = self._categories and self._categories[self._selected]
    if not cat then return false end
    if default_reset.is_armed(self, cat) then return true end
    local ids = cat._owner_mod_ids
    if ids then
        for i = 1, #ids do
            local p = self._pending[ids[i]]
            if p and next(p) ~= nil then return true end
        end
        return false
    end
    local p = self._pending[_cat_key(cat)]
    return (p ~= nil) and (next(p) ~= nil)
end

-- Recompute the APPLY button's disabled flag from the active category's buffer.
function ModTweakerView:_update_apply_button()
    if self._apply then self._apply.content.disabled = not self:_active_category_dirty() end
end

-- (#561) Profile snapshots are flat maps of owner-qualified setting ids. One
-- persisted map belongs to exactly one visible tab/slot, keeping VMF's deep-copy
-- cost bounded. Slot 1 lazily adopts the user's current live settings; an unused
-- slot starts from the tab's declared defaults.
function ModTweakerView:_profile_snapshot(category, defaults)
    local out = {}
    for i = 1, #(self._build_nodes or {}) do
        local node = self._build_nodes[i]
        local sid = _nf(node, "setting_id")
        local kind = _nf(node, "type")
        -- Keybinds are device/user-global input configuration, not gameplay/UI
        -- profile state; VMF also requires a separate binding registration path.
        if sid and kind ~= "group" and kind ~= "keybind" then
            local _, owner_id = _owner(category, sid)
            local value = defaults and _nf(node, "default_value") or _cat_get(category, sid)
            if value == nil and defaults then value = _cat_get(category, sid) end
            local excluded = category._profile_excluded_owners
            if owner_id and not (excluded and excluded[owner_id]) and value ~= nil then
                out[profiles.member_key(owner_id, sid)] = value
            end
        end
    end
    return out
end

function ModTweakerView:_profile_ensure(category)
    if not category then return end
    local tab_id = _cat_key(category)
    self._profile_slot = profiles.get_active(mod, tab_id)
    local ready_key = tab_id .. ":" .. tostring(self._profile_slot)
    if self._profile_ready[ready_key] then return end
    if not profile_runtime.migrate(profiles, mod, _printf) then
        self._profile_ready[ready_key] = true
        return
    end
    local values = profiles.load(mod, tab_id, self._profile_slot)
    if not values then
        local use_defaults = self._profile_slot ~= 1
        profiles.save(mod, tab_id, self._profile_slot,
            self:_profile_snapshot(category, use_defaults))
        _printf("[gut:561] initialized tab=%s profile=%d source=%s",
            tostring(tab_id), self._profile_slot, use_defaults and "defaults" or "live")
    else
        local merged, _, added, applied_ok, applied, failures, apply_err =
            profile_runtime.reconcile_and_apply({
                profiles = profiles, transactions = transactions,
                values = values, defaults = self:_profile_snapshot(category, true),
                category = category, owner = _owner, set_one = _cat_set })
        if added > 0 and not applied_ok then
            _printf("[gut:828] reconciliation deferred tab=%s profile=%d added=%d applied=%d failures=%d error=%s",
                tostring(tab_id), self._profile_slot, added, applied, failures, tostring(apply_err or "none"))
            self._profile_ready[ready_key] = true
            return
        end
        if added > 0 then
            profiles.save(mod, tab_id, self._profile_slot, merged)
            _printf("[gut:828] reconciled tab=%s profile=%d added=%d applied=%d", tostring(tab_id), self._profile_slot, added, applied)
        end
    end
    self._profile_ready[ready_key] = true
end

function ModTweakerView:_profile_capture(category)
    if not category then return end
    local tab_id = _cat_key(category)
    local slot = profiles.get_active(mod, tab_id)
    profiles.save(mod, tab_id, slot, self:_profile_snapshot(category, false))
    self._profile_ready[tab_id .. ":" .. tostring(slot)] = true
    self._profile_slot = slot
end

function ModTweakerView:_switch_profile(slot)
    local category = self._categories and self._categories[self._selected]
    if not category then return end
    local tab_id = _cat_key(category)
    local current = profiles.get_active(mod, tab_id)
    if slot == current then return end

    -- Profile switches are an explicit commit boundary: staged edits are applied
    -- to the profile they were made under before another profile is restored.
    if self:_active_category_dirty() then
        self:apply_pending(category)
        if self:_active_category_dirty() then _printf("[gut:1002] profile switch deferred tab=%s profile=%d pending transaction incomplete", tostring(tab_id), slot); return end
    end
    self:_profile_capture(category)

    if not profile_runtime.migrate(profiles, mod, _printf) then return end
    local values = profiles.load(mod, tab_id, slot)
    local reconciled_additions = {}
    if not values then
        values = self:_profile_snapshot(category, true)
        profiles.save(mod, tab_id, slot, values)
    else
        local reconciled, additions, added, applied_ok, applied, failures, apply_err =
            profile_runtime.reconcile_and_apply({
                profiles = profiles, transactions = transactions,
                values = values, defaults = self:_profile_snapshot(category, true),
                category = category, owner = _owner, set_one = _cat_set })
        if not applied_ok then
            _printf("[gut:828] profile switch deferred tab=%s profile=%d added=%d applied=%d failures=%d error=%s",
                tostring(tab_id), slot, added, applied, failures, tostring(apply_err or "none"))
            return
        end
        values = reconciled
        reconciled_additions = additions
        if added > 0 then profiles.save(mod, tab_id, slot, values) end
    end
    profiles.set_active(mod, tab_id, slot)
    self._profile_ready[tab_id .. ":" .. tostring(slot)] = true
    self._profile_slot = slot

    local staged = 0
    for member, value in pairs(values) do
        local owner_id, sid = profiles.split_member_key(member)
        local _, actual_owner = _owner(category, sid)
        local excluded = category._profile_excluded_owners
        if owner_id and sid and actual_owner == owner_id
                and reconciled_additions[member] == nil
                and not (excluded and excluded[owner_id]) then
            self:stage_set(category, sid, value)
            staged = staged + 1
        end
    end
    if staged > 0 then self:apply_pending(category) else self:_build_rows(category) end
    _printf("[gut:561] switched tab=%s profile=%d settings=%d", tostring(tab_id), slot, staged)
    local mt = _mt(); if mt and mt.emit_profile_diagnostic then mt:emit_profile_diagnostic(tab_id, "profile_switch") end
    _play_click()
end

-- (#446) Mutually-exclusive group enforcement. `setting_id` (a checkbox in `category`)
-- was just switched ON; stage every OTHER member of its registered exclusive group OFF,
-- so at most one member is ever ON. Members are keyed by their REGISTERED (mod_id,
-- setting_id) and staged DIRECTLY into the pending buffer under the member's OWN mod_id
-- -- the same key stage_set resolves via _owner for a same-mod member, and the correct
-- per-mod buffer for a cross-mod member, so a sibling living in another tab still commits
-- when that tab is applied. Only a member whose EFFECTIVE value (staged, else the member
-- mod's live get) is currently truthy is written, so we never manufacture a false-dirty
-- edit. Returns true if any sibling changed -- the caller then rebuilds so the switched-
-- off rows repaint (checkbox display is cached; only a row rebuild re-reads the staged
-- flag).
function ModTweakerView:_enforce_exclusive(category, setting_id)
    local MT = _mt()
    if not MT or type(MT.get_exclusive_group_id) ~= "function" then return false end
    local _, owner_id = _owner(category, setting_id)
    if not owner_id then return false end
    local gid = MT:get_exclusive_group_id(owner_id, setting_id)
    if not gid then return false end
    local members = MT:get_exclusive_members(gid)
    if type(members) ~= "table" then return false end
    local changed = false
    for i = 1, #members do
        local m = members[i]
        if not (m.mod_id == owner_id and m.setting_id == setting_id) then
            local p = self._pending[m.mod_id]
            local eff
            if p and p[m.setting_id] ~= nil then
                eff = p[m.setting_id]
            else
                local mo = get_mod(m.mod_id)
                if mo then local ok, v = pcall(mo.get, mo, m.setting_id); if ok then eff = v end end
                if eff == nil and MT.get then eff = MT:get(m.mod_id, m.setting_id) end
            end
            if eff then
                self._pending[m.mod_id] = self._pending[m.mod_id] or {}
                self._pending[m.mod_id][m.setting_id] = false
                changed = true
            end
        end
    end
    if changed then self:_update_apply_button() end
    return changed
end

-- APPLY: commit the whole pending buffer for `category` through the existing _cat_set
-- path (the ONLY place _cat_set runs on edit — a stray slider drag never takes effect
-- until clicked), clear the buffer, grey the button, and repaint the rows from the new
-- live values. Native handle_apply_button -> apply_changes (options_view.lua:1919).
-- (#208) For the merged Equipment category, flush EACH member mod_id's buffer (each edit
-- routes to its owner's mod_obj via _cat_set -> _owners), re-register any keybinds across
-- the committed settings, then clear them all.
function ModTweakerView:apply_pending(category)
    local MT = _mt()
    local ids = category._owner_mod_ids
    if MT and MT.prune_runtime_gated_pending and MT:prune_runtime_gated_pending(self._pending, ids or { _cat_key(category) }) > 0 then self:_update_apply_button() end
    if ids then
        local committed = {}   -- setting_id -> value across all members (for keybind re-reg)
        local any, wrote, failed = false, false, false
        for i = 1, #ids do
            local mid = ids[i]
            local p = self._pending[mid]
            if p and next(p) ~= nil then
                local count, batched, batch_err, complete = transactions.commit(category, p, _owner, _cat_set)
                wrote = wrote or count > 0
                if batched then
                    printf("[gut:560] owner=%s settings=%d notifications=%d complete=%s error=%s", tostring(mid), count, batch_err and 0 or 1, tostring(complete), tostring(batch_err or "none"))
                end
                if complete then for id, value in pairs(p) do committed[id] = value end; self._pending[mid] = {}
                else failed = true end
                any = true
            end
        end
        if not any and not default_reset.is_armed(self, category) then return end
        local reset_attempted, reset_complete, reset_err = default_reset.finish(
            self, category, not failed, mod._gut_reset_modded_loadouts)
        if reset_attempted then
            _printf("[gut:1033] surface=standalone reset_complete=%s error=%s",
                tostring(reset_complete), tostring(reset_err or "none"))
        end
        -- (#123) Keybinds need VMF re-registration, not just a value set.
        for _, row in ipairs(self._rows or {}) do
            if row._is_keybind and row._setting_id and committed[row._setting_id] ~= nil then
                _commit_keybind(row, committed[row._setting_id])
            end
        end
        self._dirty = self._dirty or wrote
        self:_update_apply_button()
        self:_build_rows(category)
        if not failed then self:_profile_capture(category) end
        _play_click()
        mod:debug("[mt:apply] Equipment buffers {%s} complete=%s", table.concat(ids, ", "), tostring(not failed))
        return
    end
    local key = _cat_key(category)
    local p = self._pending[key]
    if (not p or next(p) == nil) and not default_reset.is_armed(self, category) then return end
    if not p or next(p) == nil then
        local attempted, reset_complete, reset_err = default_reset.finish(
            self, category, true, mod._gut_reset_modded_loadouts)
        if attempted then
            _printf("[gut:1033] surface=standalone reset_complete=%s error=%s",
                tostring(reset_complete), tostring(reset_err or "none"))
        end
        self:_update_apply_button()
        self:_build_rows(category)
        _play_click()
        return
    end
    local count, batched, batch_err, complete = transactions.commit(category, p, _owner, _cat_set)
    if batched then
        printf("[gut:560] owner=%s settings=%d notifications=%d complete=%s error=%s", tostring(key), count, batch_err and 0 or 1, tostring(complete), tostring(batch_err or "none"))
    end
    if complete then
        for _, row in ipairs(self._rows or {}) do
            if row._is_keybind and row._setting_id and p[row._setting_id] ~= nil then
                _commit_keybind(row, p[row._setting_id])
            end
        end
    end
    if complete then self._pending[key] = {} end
    local reset_attempted, reset_complete, reset_err = default_reset.finish(
        self, category, complete, mod._gut_reset_modded_loadouts)
    if reset_attempted then
        _printf("[gut:1033] surface=standalone reset_complete=%s error=%s",
            tostring(reset_complete), tostring(reset_err or "none"))
    end
    self._dirty = self._dirty or count > 0
    self:_update_apply_button()
    self:_build_rows(category)
    if complete then self:_profile_capture(category) end
    _play_click()
    mod:debug("[mt:apply] pending buffer for '%s' complete=%s", tostring(key), tostring(complete))
end

-- (v0.2.148-dev) RESTORE DEFAULTS: stage every setting in the CURRENT tab back to its
-- default_value, then repaint the rows so the staged defaults show. This does NOT write
-- live — it STAGES (like a manual edit); the user clicks Apply to commit, at which point
-- apply_pending flushes the buffer through _cat_set. Because stage_set routes each edit to
-- its OWNER mod_id (_owner), the Equipment tab resets every member mod correctly.
-- Skips groups/headers (no setting_id), settings with no default_value, and keybinds
-- (type=="keybind", whose default_value is an empty table).
function ModTweakerView:reset_to_defaults()
    local nodes    = self._build_nodes
    local category = self._build_category
    if not nodes or not category then return end
    local n = 0
    for i = 1, #nodes do
        local node = nodes[i]
        local sid  = _nf(node, "setting_id")
        local dv   = _nf(node, "default_value")
        if sid and dv ~= nil and _nf(node, "type") ~= "keybind" then
            self:stage_set(category, sid, dv)
            n = n + 1
        end
    end
    default_reset.arm(self, category)
    self:_update_apply_button()
    self:_build_rows(category)
    _play_click()
    mod:debug("[mt:reset] staged %d default(s) for '%s'", n, tostring(_cat_key(category)))
end

-- (Fix 3, v0.2.151-dev) Show the native "restore defaults" CONFIRM popup before resetting.
-- Rendered by the game's own Managers.popup (its own manager + renderer — no borrowed-renderer
-- issue), the same mechanism vanilla OptionsView uses for its reset/apply confirms
-- (options_view.lua:3335). queue_popup(text, topic, result_1, button_1, result_2, button_2);
-- query_result later returns the chosen result key. Only the CONFIRM ("reset_values") result
-- runs reset_to_defaults (current tab only). Falls back to an immediate reset if the popup
-- manager is unavailable, so the button never dead-ends.
function ModTweakerView:_queue_reset_popup()
    _play_click()
    if self._reset_popup_id then return end   -- already showing
    if not (Managers and Managers.popup and Managers.popup.queue_popup) then
        self:reset_to_defaults()
        return
    end
    -- Mirror the VANILLA reset-settings popup (options_view.lua:3335) VERBATIM: the engine
    -- Localizes popup text, so RAW English strings render as `<raw string>`. Real vanilla loc
    -- keys (reset_settings_popup_text / popup_discard_changes_topic / button_ok / popup_choice_cancel)
    -- resolve correctly. CONFIRM result = "reset_values"; cancel = "revert_changes".
    local ok, id = pcall(function()
        local text = Localize("reset_settings_popup_text")
        return Managers.popup:queue_popup(text, Localize("popup_discard_changes_topic"), "reset_values", Localize("button_ok"), "revert_changes", Localize("popup_choice_cancel"))
    end)
    if ok and id then self._reset_popup_id = id else self:reset_to_defaults() end
end

-- (Fix 3, v0.2.151-dev) Poll the reset-confirm popup each frame; run the reset ONLY on the
-- CONFIRM ("reset_values") result. Any other result (cancel / click-away) just dismisses.
function ModTweakerView:_check_reset_popup()
    local id = self._reset_popup_id
    if not id then return end
    if not (Managers and Managers.popup) then self._reset_popup_id = nil; return end
    local result = Managers.popup:query_result(id)
    if result then
        Managers.popup:cancel_popup(id)
        self._reset_popup_id = nil
        if result == "reset_values" then self:reset_to_defaults() end
    end
end

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

function ModTweakerView:_build_node_row(w, category, base_offset, depth, display_expanded)
    depth = depth or 0
    local MT = _mt()
    local setting_id = _nf(w, "setting_id")
    local wtype = _nf(w, "type")
    -- (#208) Resolve the node's OWNER mod_obj for label/tooltip localization (the merged
    -- Equipment tab spans four mods); for a normal category _owner returns category.mod_obj.
    local owner_mod_obj, row_owner_mod_id = _owner(category, setting_id)
    local label = category._flat and _vmf_label(w, owner_mod_obj)
                  or tostring(w.label or w.text or w.setting_id or "?")
    -- (#207) The node's localized tooltip DESCRIPTION (mod_obj may be nil for gut's own
    -- nested categories — _vmf_tooltip then just uses the raw string). Stored on the row
    -- below so the draw loop can show a hover popup; nil = no popup for this row.
    -- (#208) Localize against the node's OWNER mod (see owner_mod_obj above).
    local tooltip = _vmf_tooltip(w, owner_mod_obj)
    local row, err

    if wtype == "header" then
        row = nil  -- VMF synthesizes a per-mod header; the tab already names the mod.
    elseif wtype == "group" then
        -- Collapsible group header (default COLLAPSED). The caller handles expand state.
        local gid = self:_group_key(w, category)
        local expanded = display_expanded
        if expanded == nil then expanded = self._expanded[gid] and true or false end
        local ok, r = pcall(defs.create_group_header, label, expanded, base_offset, depth)
        if ok and r then
            row = r; row._is_group = true; row._group_key = gid
            row._display_expanded = display_expanded
        else err = r end
    elseif wtype == "checkbox" or wtype == "boolean" then
        local ok, r = pcall(defs.create_checkbox, label, base_offset, depth)
        if ok and r then
            row = r
            -- (v0.2.70-dev) buffer-first: show the staged value if an edit is pending.
            local live = _cat_get(category, setting_id)
            row.content.flag = self:get_staged(category, setting_id, live) and true or false
            row._last_flag = row.content.flag
        else err = r end
    elseif wtype == "radio" then
        local ok, r = pcall(defs.create_radio, label, base_offset, depth)
        if ok and r then
            row = r
            local group_id = _nf(w, "_mt_exclusive_group")
            local is_none = _nf(w, "_mt_exclusive_none") == true
            local selected = false
            if is_none then
                selected = true
                local members = MT and MT:get_exclusive_members(group_id)
                for i = 1, #(members or {}) do
                    local member = members[i]
                    local live = _cat_get(category, member.setting_id)
                    if self:get_staged(category, member.setting_id, live) then
                        selected = false
                        break
                    end
                end
            else
                local live = _cat_get(category, setting_id)
                selected = self:get_staged(category, setting_id, live) and true or false
            end
            row.content.selected = selected
            row._mt_radio_group = group_id
            row._mt_radio_none = is_none
            row._mt_radio_member_mod = _nf(w, "_mt_exclusive_member_mod")
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
            -- (#164) Fixed per-click / snap increment for this slider. Resolved by
            -- _resolve_step: an explicit widget-def `step` field first, else the gut-side
            -- STEP_OVERRIDES registry (the working path for a foreign VMF mod — VMF strips a
            -- custom `step` field off foreign widgets, see STEP_OVERRIDES), else the natural
            -- unit (1 / 10^-decimals). The track/arrows step by this; _snap_and_clamp snaps the
            -- value to the grid (anchored at range min). A pre-existing off-step value (e.g. a
            -- 324-coin value dialed in VMF's own fine-grained menu) is shown as-is here and
            -- only snaps once the user moves it. #152: this replaced the old ~range/40 over-jump.
            -- (#389) The synthesized Equipment category is owned by gut_dev, but each
            -- row retains its real provider in category._owners.  Step policy belongs
            -- to that provider (for example CIM's Base Power Level = 25), so resolving
            -- against category.mod_id silently fell back to 1 for every merged row.
            local _, owner_mod_id = _owner(category, setting_id)
            local step = _resolve_step(w, owner_mod_id, setting_id or _nf(w, "setting_id"), dec)
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
        -- #605: large source-generated catalogues can be supplied lazily. The
        -- provider runs only when its tab is built, avoiding 34k dialogue option
        -- records at launcher/keep boot when the user never opens Dialogue.
        local options_provider = _nf(w, "options_provider")
        if type(options) ~= "table" and type(options_provider) == "function" then
            local ok_options, provided = pcall(options_provider)
            if ok_options and type(provided) == "table" then
                options = provided
            else
                mod:warning("[mt] options_provider failed for %s.%s: %s",
                    tostring(category.mod_id), tostring(setting_id), tostring(provided))
            end
        end
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
    elseif wtype == "action" then
        -- #605: immediate local action row for media controls and other operations
        -- that are not persistent settings. Uses the resident dropdown field-box
        -- chrome, but never opens a popup or enters the Apply transaction.
        local ok, r = pcall(defs.create_dropdown, label, base_offset, depth,
            { no_arrow = true, field_box = true })
        if ok and r then
            row = r
            row._is_action = true
            row._action = _nf(w, "on_activate")
            row.content.value_text = tostring(_nf(w, "button_text") or "RUN")
        else err = r end
    elseif wtype == "keybind" then
        -- (#123) Interactive keybind row (dropdown row shape: label + clickable value).
        -- Click -> capture; on capture/clear we apply IMMEDIATELY like VMF (set value +
        -- add_mod_keybind + generate_keybinds), NOT staged. #95 format via _format_keybind_value.
        -- _keybind_def carries the widget fields VMF's add_mod_keybind needs (see VMF_AND_USER_SETTINGS.md).
        local val = setting_id and self:get_staged(category, setting_id, _cat_get(category, setting_id))
        local ok, r = pcall(defs.create_dropdown, label, base_offset, depth, { no_arrow = true, field_box = true })
        if ok and r then
            row = r
            row._is_keybind = true
            row.content.value_text = _format_keybind_value(val)
            row._keybind_def = {
                keybind_type    = _nf(w, "keybind_type"),
                keybind_trigger = _nf(w, "keybind_trigger"),
                keybind_global  = _nf(w, "keybind_global"),
                function_name   = _nf(w, "function_name"),
                view_name       = _nf(w, "view_name"),
                transition_data = _nf(w, "transition_data"),
            }
        else err = r end
    else
        -- text / unknown: read-only label + current value.
        -- (#95) A keybind's value is a Lua TABLE — the VMF key-combo array (e.g.
        -- {"left alt"} or {}). The old code tostring()'d it, printing the raw table
        -- address ("CYCLE HUD MODE: table: 0x..."). Render the combo instead (joined,
        -- upper-cased) or "unbound" when empty, and NEVER tostring() a raw table for
        -- any other read-only widget either.
        local val = setting_id and _cat_get(category, setting_id)
        local suffix
        if wtype == "keybind" or type(val) == "table" then
            suffix = ": " .. _format_keybind_value(val)
        elseif val ~= nil then
            suffix = ": " .. tostring(val)
        else
            suffix = wtype and ("  [" .. tostring(wtype) .. "]") or ""
        end
        local ok, r = pcall(defs.create_section_title, label .. suffix, base_offset, depth)
        if ok and r then row = r; row._readonly = true else err = r end
    end

    if row then
        if _nf(w, "disabled") == true then
            row._readonly = true
            row._disabled_in_vmf = true
            local color = row.style and row.style.label and row.style.label.text_color
            if color then color[1], color[2], color[3], color[4] = 128, 128, 128, 128 end
        end
        row._mod_id = row_owner_mod_id or category.mod_id
        row._setting_id = setting_id
        row._wtype = wtype
        row._category = category
        row._list_y = base_offset[2]  -- this row's Y (factory just decremented to it)
        -- (#207) Hover-popup text: TITLE = the row label, DESC = the localized tooltip.
        row._tip_title = label
        row._tip_desc = tooltip
        if MT and MT.apply_runtime_gate then MT:apply_runtime_gate(row, row._mod_id, setting_id) end
        -- (v0.2.157-dev diag, temp) Farm any residual "<...>" marker. If the RAW node data or the
        -- RESOLVED label/desc still contains a "<", printf it so the exact culprit + owning mod are
        -- named next time the menu opens. With the _vmf_label/_vmf_tooltip hardening this should
        -- fire ZERO times; if it does not fire yet the user still sees "<>", the marker is coming
        -- from some OTHER element (value/dropdown/etc.), which this rules in or out.
        local _rt = _nf(w, "tooltip")
        local _rtt = _nf(w, "title") or _nf(w, "text")
        local function _hasmark(x) return type(x) == "string" and string.find(x, "<") end
        if _hasmark(_rt) or _hasmark(_rtt) or _hasmark(label) or _hasmark(tooltip) then
            printf("[gut:desc] MARKER mod=%s sid=%s type=%s raw_title=%q raw_tt=%q -> label=%q desc=%q",
                tostring(category.mod_id), tostring(setting_id), tostring(wtype),
                tostring(_rtt), tostring(_rt), tostring(label), tostring(tooltip))
        end
    end
    return row, err, wtype, setting_id, label
end

-- Append a row (+ optional gear) to self._rows and log build failures. Shared tail
-- of every row append so the drill view and normal list stay byte-identical.
function ModTweakerView:_append_row(row, err, wtype, category, setting_id, base_offset, has_gear, parent_label)
    if row then
        self._rows[#self._rows + 1] = row
        if has_gear then
            -- Advanced-option parents are navigation/selection headers as well
            -- as settings: enabled gear parents take the warm-tan chrome accent,
            -- disabled VMF rows keep their grey (#611). The decision lives in the
            -- ONE shared policy site defs.apply_gear_parent_accent so the mission
            -- and keep twins can never drift apart again (#717 twin parity).
            defs.apply_gear_parent_accent(row, has_gear)
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
return ModTweakerView
