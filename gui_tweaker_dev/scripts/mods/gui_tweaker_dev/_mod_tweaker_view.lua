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

local UIRenderer = UIRenderer
local UISceneGraph = UISceneGraph
local ShowCursorStack = ShowCursorStack
local UIWidget = UIWidget
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
    ct      = { starting_coins   = 25 },  -- CW starting pilgrim's coins (range 0-3000)
    ct_dev  = { starting_coins   = 25 },
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
end

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
    -- HideBuffs deliberately NOT whitelisted (#312): UI Tweaks options live in
    -- gut's OWN menu under the "UI Tweaks" group (gut_hide_hud_ui_group), not as a
    -- separate Mod Tweaker tab. Re-adding it would resurrect the duplicate tab.
    -- Crosshair Kill Confirmation deliberately NOT whitelisted (#339, was wrongly a
    -- tab under #313): its options are injected INTO gut's Interface tab under the HUD
    -- group by _inject_ckc_into_gut, exactly like the UI Tweaks precedent. A THIRD-PARTY
    -- integration is NEVER a top-level tab -- see gui_tweaker_dev/MOD_TWEAKER_INTEGRATION.md.
}

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
        if ok and type(s) == "string" and s ~= "" and not string.find(s, "^<") then return s end
    end
    return key
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

-- (#123) Keybind capture: collect the currently-held keyboard buttons by VT2 name and
-- return the VMF combo array {modifiers..., main_key} once a non-modifier key is held,
-- else nil. Names come straight from Keyboard.button_name (the same naming VMF matches
-- against), modifiers first. Mouse/gamepad ignored. NOTE: exact name normalisation
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
    if not main then return nil end
    local combo = { main }                                  -- VMF: primary key FIRST
    for _, m in ipairs(mods) do combo[#combo + 1] = m end   -- then normalised modifiers
    return combo
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
-- collapsible "Equipment" tab when 2+ are active (present AND enabled). Roles:
--   cosmetics_tweaker -> Cosmetics ; cim/cim_dev -> Crafting ; wt -> Weapons ;
--   character_weapon_variants -> Career Weapon Variants.
-- Sections render top-level (Cosmetics, Crafting, Weapons); CWV nests UNDER Weapons
-- when wt is also active, else sits top-level. N=1-only-CWV just relabels that one tab
-- "Weapons". The synthesized category is FLAT (_flat=true) with a parallel `_depths`
-- array (so each member keeps its own internal group/gear nesting, shifted under its
-- section header) + a `_owners[setting_id]` map so get/set/stage/apply route per-node to
-- the owning mod object (see _owner + the staged-change helpers). TWIN of the HeroView
-- sub-state's identical block — keep both in sync.
-- ---------------------------------------------------------------
local _EQUIP_ROLE = {
    cosmetics_tweaker = "cosmetics",
    cim = "crafting", cim_dev = "crafting",
    wt = "weapons",
    character_weapon_variants = "cwv",
}

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
    -- Active (enabled) members by role; dedupe Crafting (cim vs cim_dev -> first seen).
    local members = {}
    for _, c in ipairs(cats) do
        local role = _EQUIP_ROLE[c.mod_id]
        if role and c.enabled and not members[role] then members[role] = c end
    end
    local n = 0
    for _ in pairs(members) do n = n + 1 end
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
    local function _add_header(setting_id, label, header_depth)
        widgets[#widgets + 1] = { setting_id = setting_id, type = "group", title = label }
        depths[#depths + 1] = header_depth
    end
    -- A member's setting nodes (skipping its synthesized VMF header at [1]), rebased so the
    -- member's SHALLOWEST node renders at `target_top_depth` (one level under its section
    -- header), with internal nesting preserved. Records each node's owner.
    local function _add_member(member, target_top_depth)
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
        _add_header("__equip_cosmetics", _equip_loc("gut_equip_cosmetics", "Cosmetics"), 0)
        _add_member(members.cosmetics, 1)
    end
    if members.crafting then
        _add_header("__equip_crafting", _equip_loc("gut_equip_crafting", "Crafting"), 0)
        _add_member(members.crafting, 1)
    end
    if members.weapons then
        _add_header("__equip_weapons", _equip_loc("gut_equip_weapons", "Weapons"), 0)
        _add_member(members.weapons, 1)
        if members.cwv then
            -- CWV nested UNDER Weapons (header depth 1, its settings depth 2+).
            _add_header("__equip_cwv", _equip_loc("gut_equip_cwv", "Career Weapon Variants"), 1)
            _add_member(members.cwv, 2)
        end
    elseif members.cwv then
        -- No wt: CWV sits at the TOP LEVEL of Equipment (no Weapons wrapper).
        _add_header("__equip_cwv", _equip_loc("gut_equip_cwv", "Career Weapon Variants"), 0)
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

    -- Locate the HUD group node + the end of its child block in gut's flat list.
    local src = gut_cat.widgets
    local hud_idx, hud_depth
    for i = 1, #src do
        if _nf(src[i], "setting_id") == "gut_hide_hud_ui_group" then
            hud_idx = i; hud_depth = _nf(src[i], "depth") or 0; break
        end
    end
    if not hud_idx then return end
    local end_idx = #src + 1
    for i = hud_idx + 1, #src do
        if (_nf(src[i], "depth") or 0) <= hud_depth then end_idx = i; break end
    end

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

    -- Splice the block into a COPY of gut's widget list at the end of the HUD child block.
    local new_w = {}
    for i = 1, end_idx - 1 do new_w[#new_w + 1] = src[i] end
    for i = 1, #block do new_w[#new_w + 1] = block[i] end
    for i = end_idx, #src do new_w[#new_w + 1] = src[i] end

    gut_cat.widgets = new_w
    gut_cat._owners = owners
    gut_cat._owner_mod_ids = { gut_cat.mod_id, _CKC_NAME }   -- MIXED: flush BOTH buffers
    -- gut_cat.mod_obj stays = gut (its own settings fall back via _owner)
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
        if type(mod_name) == "string" and _MY_MODS[mod_name] then
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
            -- #318: a VMF-DISABLED mod must NOT get a Mod Tweaker tab at all. The
            -- old behavior added it and greyed the tab out (dead-code paths below at
            -- the tab builder), which the user rejected. Skip it entirely so only
            -- enabled whitelisted mods become tabs. `enabled` stays true when
            -- is_enabled is absent/errors, so an indeterminate mod still shows
            -- rather than silently vanishing.
            if enabled then
                out[#out + 1] = {
                    mod_id = mod_name, label = label, widgets = list,
                    mod_obj = mod_obj, enabled = enabled, _flat = true,
                }
            end
        end
    end
    -- (#339) Fold Crosshair Kill Confirmation into gut's Interface tab under HUD (NOT a
    -- tab). No-op when CKC is absent. Before the sort (it mutates the existing gut cat).
    _inject_ckc_into_gut(out)
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
    local ids = category._owner_mod_ids
    if ids then
        local committed = {}   -- setting_id -> value across all members (for keybind re-reg)
        local any = false
        for i = 1, #ids do
            local mid = ids[i]
            local p = self._pending[mid]
            if p and next(p) ~= nil then
                for id, value in pairs(p) do _cat_set(category, id, value); committed[id] = value end
                self._pending[mid] = {}
                any = true
            end
        end
        if not any then return end
        -- (#123) Keybinds need VMF re-registration, not just a value set.
        for _, row in ipairs(self._rows or {}) do
            if row._is_keybind and row._setting_id and committed[row._setting_id] ~= nil then
                _commit_keybind(row, committed[row._setting_id])
            end
        end
        self._dirty = true
        self:_update_apply_button()
        self:_build_rows(category)
        _play_click()
        mod:debug("[mt:apply] committed Equipment buffers {%s}", table.concat(ids, ", "))
        return
    end
    local key = _cat_key(category)
    local p = self._pending[key]
    if not p or next(p) == nil then return end
    for id, value in pairs(p) do _cat_set(category, id, value) end
    -- (#123) Keybinds need VMF re-registration, not just a value set: register any keybind
    -- whose value was in THIS committed buffer (vmf.add_mod_keybind + generate_keybinds).
    for _, row in ipairs(self._rows or {}) do
        if row._is_keybind and row._setting_id and p[row._setting_id] ~= nil then
            _commit_keybind(row, p[row._setting_id])
        end
    end
    self._pending[key] = {}
    self._dirty = true   -- a LIVE write happened -> export the TOML on exit
    self:_update_apply_button()
    -- Rebuild the rows so each reads its new live value (the mod's on_setting_changed
    -- may have snapped/clamped further, e.g. ct's 25-coin rounding).
    self:_build_rows(category)
    _play_click()
    mod:debug("[mt:apply] committed pending buffer for '%s'", tostring(key))
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

function ModTweakerView:_build_node_row(w, category, base_offset, depth)
    depth = depth or 0
    local setting_id = _nf(w, "setting_id")
    local wtype = _nf(w, "type")
    -- (#208) Resolve the node's OWNER mod_obj for label/tooltip localization (the merged
    -- Equipment tab spans four mods); for a normal category _owner returns category.mod_obj.
    local owner_mod_obj = _owner(category, setting_id)
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
            -- (#164) Fixed per-click / snap increment for this slider. Resolved by
            -- _resolve_step: an explicit widget-def `step` field first, else the gut-side
            -- STEP_OVERRIDES registry (the working path for a foreign VMF mod — VMF strips a
            -- custom `step` field off foreign widgets, see STEP_OVERRIDES), else the natural
            -- unit (1 / 10^-decimals). The track/arrows step by this; _snap_and_clamp snaps the
            -- value to the grid (anchored at range min). A pre-existing off-step value (e.g. a
            -- 324-coin value dialed in VMF's own fine-grained menu) is shown as-is here and
            -- only snaps once the user moves it. #152: this replaced the old ~range/40 over-jump.
            local step = _resolve_step(w, category and category.mod_id, setting_id or _nf(w, "setting_id"), dec)
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
        row._mod_id = category.mod_id
        row._setting_id = setting_id
        row._wtype = wtype
        row._category = category
        row._list_y = base_offset[2]  -- this row's Y (factory just decremented to it)
        -- (#207) Hover-popup text: TITLE = the row label, DESC = the localized tooltip.
        row._tip_title = label
        row._tip_desc = tooltip
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
    -- (#163) Keep the flat node/depth arrays for the auto-collapse handler — sibling + descendant
    -- detection needs the tree shape; the group toggle in _handle_input reads these.
    self._build_nodes, self._build_depths, self._build_category = nodes, depths, category

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
        local matched = {}
        for i = 1, #nodes do if keep[i] then matched[#matched + 1] = i end end
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
                if _nf(nodes[i], "type") == "group" then
                    self._expanded[self:_group_key(nodes[i], category)] = true
                end
                local row, err, wtype, setting_id = self:_build_node_row(nodes[i], category, base_offset, depths[i])
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

-- Per-mod tab-label overrides (keyed by mod_id, both stable + dev ids). An entry
-- here REPLACES the derived label outright (applied BEFORE the "Tweaker: " prefix
-- strip + truncation), so the tab reads EXACTLY the override string. Extend by
-- adding a `<mod_id> = "LABEL"` line. gt/gt_dev are deliberately absent — their
-- VMF name already reads "General", so the prefix-strip path yields "General".
local _TAB_LABEL_OVERRIDE = {
    cim = "CRAFTING", cim_dev = "CRAFTING",
    character_weapon_variants = "CWV", character_weapon_variants_dev = "CWV",
}

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

    -- (#313) One-shot tab focus: if another feature (e.g. the CKC options gear button)
    -- asked the Mod Tweaker to open on a specific mod's tab, honor it now. May re-slice
    -- to another page; the request is cleared inside before any re-entry so _rebuild
    -- can't recurse into focus.
    self:_apply_focus_request()

    -- (Fix 5, v0.2.149-dev) The bottom hint text was removed (native Options has no hint).

    mod:debug("[mt] rebuild: total=%d page=%d/%d displayed=%d selected=%d rows=%d",
        total, self._page + 1, self._page_count, #self._categories, self._selected, #self._rows)
end

-- (#313) Consume mod._gut_mt_focus_request (a mod_id string). Locate that mod in the
-- FULL pre-pagination category list, flip to its page if the strip paginates, and
-- select its tab. One-shot: cleared whether or not the mod was found, so a stale
-- request never sticks. A cross-page jump re-runs _rebuild ONCE (request already
-- cleared -> no recursion). No-op when nothing requested.
function ModTweakerView:_apply_focus_request()
    local req = mod._gut_mt_focus_request
    if not req then return end
    local cats = self._all_categories
    if type(cats) ~= "table" then mod._gut_mt_focus_request = nil; return end
    -- (#339) CKC options live under the gut "Interface" tab's HUD group, not a CKC tab.
    -- Redirect a CKC focus request (from the vanilla-Options gear) to the gut category,
    -- and expand the HUD + CKC sub-group so the user lands on CKC's options.
    local expand_ckc = false
    if req == "Crosshair Kill Confirmation" then
        expand_ckc = true
        req = nil
        for i = 1, #cats do
            local mid = cats[i] and cats[i].mod_id
            if mid == "gut" or mid == "gut_dev" then req = mid; break end
        end
        if not req then mod._gut_mt_focus_request = nil; return end
    end
    local full_idx
    for i = 1, #cats do
        if cats[i] and cats[i].mod_id == req then full_idx = i; break end
    end
    if not full_idx then mod._gut_mt_focus_request = nil; return end  -- mod not present/whitelisted: drop it
    if expand_ckc then
        self._expanded = self._expanded or {}
        self._expanded[req .. ":gut_hide_hud_ui_group"] = true
        self._expanded[req .. ":gut_ckc_group"] = true
    end
    local paged = (self._page_count or 1) > 1
    local per_page = paged and (MAX_TABS - 1) or #cats
    if per_page < 1 then per_page = 1 end
    local target_page = math.floor((full_idx - 1) / per_page)
    local local_idx = full_idx - target_page * per_page
    mod._gut_mt_focus_request = nil  -- consume BEFORE any re-entry
    if paged and target_page ~= (self._page or 0) then
        self._page = target_page
        self._selected = local_idx
        self:_rebuild()  -- re-slice to the target page (request already cleared)
        return
    end
    self._selected = math.clamp(local_idx, 1, math.max(1, #self._categories))
    self:_build_rows(self._categories[self._selected])
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
-- Render-state probe (debug-gated). Logs on-screen geometry so the log alone
-- shows whether elements are positioned/sized/visible — no screenshot needed.
-- ---------------------------------------------------------------
function ModTweakerView:_dump_state(reason)
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
    mod:info("[mt:dump] (%s) active=%s alpha=%s categories=%d selected=%d tabs=%d rows=%d chrome=%d exit=%s scrollbar=%s",
        tostring(reason), tostring(self._active), tostring(self.render_settings.alpha_multiplier),
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
-- Logs the REAL runtime scrollbar render-state so the next in-game repro reveals
-- (a) the actual menu background color to contrast the bar against (the prior
-- "fix" INFERRED ~{10,10,10} from a code comment — never measured; the real
-- `background` chrome rect is {255,15,15,15}, panels are {10,10,10}), (b) whether
-- the bar is drawn at all and WHERE (on-screen vs off-panel / behind a widget),
-- and (c) whether the thumb height is sane. Mirrors the _dump_state geometry
-- helpers; fired once per open from the SAME site as _dump_state.
-- ---------------------------------------------------------------
function ModTweakerView:_dump_scrollbar(reason)
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
    -- Resolve a widget's first style table that carries a `.color` (handles both
    -- create_simple_rect's style_id "rect" and the scrollbar's "track"/"thumb").
    local function color_of(style_tbl)
        if type(style_tbl) ~= "table" then return "?" end
        local c = style_tbl.color
        if type(c) == "table" and c[1] then
            return string.format("{A%d,R%d,G%d,B%d}", c[1], c[2] or 0, c[3] or 0, c[4] or 0)
        end
        return "?"
    end

    -- (a) BACKGROUND chrome rect = the contrast baseline. CHROME_ORDER[1] is the
    -- dark `background` fill (create_simple_rect); its color lives at style.rect.color.
    local bg = self._chrome and self._chrome[1]
    local bg_style = bg and bg.style and bg.style.rect
    mod:info("[mt:scrollbar] (%s) BACKGROUND chrome[1] color=%s sg_world=%s sg_size=%s",
        tostring(reason), color_of(bg_style), wp("background"), sz("background"))
    -- Panels (the bar may visually sit over these too, depending on alignment).
    mod:info("[mt:scrollbar]   top_panel=%s(%s) bottom_panel=%s(%s) list_mask=%s(%s)",
        wp("background_top_panel"), sz("background_top_panel"),
        wp("background_bottom_panel"), sz("background_bottom_panel"),
        wp("list_mask"), sz("list_mask"))

    -- (b) The scrollbar widget itself: track + thumb color, scenegraph node world
    -- pos/size, and the styles' own z (offset[3]) for draw-order. defs.scrollbar_sg
    -- == "mt_scrollbar" (parented to list_mask, right-aligned, inset -30px).
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

    -- (c) Scroll math: is the bar even drawn (drawn only when _max_scroll>0), and is
    -- the thumb height sane? thumb_frac = visible/content (same formula as the draw
    -- path at ~:1682); thumb_px = track_h * clamp(frac, 0.06, 1) (offset_function).
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
    -- (v0.2.74-dev) Test against `background_frame` (the decorated panel the player
    -- sees), NOT `list_mask`. list_mask is a 1400px LEFT-aligned node whose right edge
    -- juts ~18px off-panel, so "inside list_mask" said nothing about whether the bar
    -- is on the visible frame — that mismatch is exactly what hid the old position bug.
    -- Also test the bar's CENTRE point (origin + half-size) rather than its bottom-left
    -- origin: math.point_is_inside_2d_box uses STRICT inequalities, so a node whose edge
    -- coincides with the box edge (the bar's bottom-left Y == the panel/list_mask Y when
    -- they share a vertical span) reports a FALSE on_screen=false. The centre point is
    -- unambiguous. (The old probe's on_screen=false in BOTH states was this strict-edge
    -- artifact, not proof the bar was off-screen.)
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

    self:_draw(dt, input_service)

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
            self._search_focused = false
            self._search_str = ""
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
local _EDIT_MAX_LEN = 16
-- (#497) Max search query length (free text; the numeric editor's cap is _EDIT_MAX_LEN).
local _SEARCH_MAX_LEN = 40

-- (#497 / #505) Shared raw-keystroke reader. Applies this frame's Keyboard.keystrokes() to a
-- query string: Backspace erases the last char, printable ASCII (32-126) appends up to max_len.
-- Returns (new_str, changed). Reused by the per-tab search box (#497) and the open-dropdown
-- type-to-filter (#505) — the SAME raw path the numeric type-to-edit uses; Enter (13) / ESC (27)
-- are sub-32 so they are ignored here and handled by their own callers.
local function _apply_keystrokes(str, max_len)
    local keystrokes = Keyboard.keystrokes()
    if not keystrokes or #keystrokes == 0 then return str, false end
    local s = str or ""
    local changed = false
    for _, stroke in ipairs(keystrokes) do
        if stroke == Keyboard.BACKSPACE then
            if #s > 0 then s = s:sub(1, #s - 1); changed = true end
        elseif type(stroke) == "string" and #stroke == 1 and #s < (max_len or _SEARCH_MAX_LEN) then
            local b = string.byte(stroke)
            if b and b >= 32 and b <= 126 then s = s .. stroke; changed = true end
        end
    end
    return s, changed
end

local function _format_value(value, num_decimals)
    return string.format("%." .. (num_decimals or 0) .. "f", value or 0)
end

function ModTweakerView:_begin_edit(row)
    if self._editing_row and self._editing_row ~= row then
        -- Committing the previously-focused row keeps a single active editor.
        self:_commit_edit(self._editing_row)
    end
    local c = row.content
    self._editing_row = row
    c.editing = true
    c.edit_str = _format_value(c.value, c.num_decimals)
    c.caret_idx = #c.edit_str   -- (#188) cursor starts at the END of the value
    c.caret_t = 0
    c.value_text = c.edit_str
    _play_click()
end

-- Append/filter ONE batch of keystrokes into c.edit_str (VMF rule set). Returns true if
-- the buffer changed this call (so live feedback only recomputes on change).
function ModTweakerView:_edit_apply_keystrokes(c)
    local keystrokes = Keyboard.keystrokes()
    if not keystrokes or #keystrokes == 0 then return false end
    local s   = c.edit_str or ""
    local idx = math.clamp(c.caret_idx or #s, 0, #s)   -- (#188) chars BEFORE the caret
    local nd  = c.num_decimals or 0
    local allow_neg = (c.min or 0) < 0
    local changed = false
    for _, stroke in ipairs(keystrokes) do
        if stroke == Keyboard.LEFT then
            if idx > 0 then idx = idx - 1; changed = true end
        elseif stroke == Keyboard.RIGHT then
            if idx < #s then idx = idx + 1; changed = true end
        elseif stroke == Keyboard.BACKSPACE then
            if idx > 0 then s = s:sub(1, idx - 1) .. s:sub(idx + 1); idx = idx - 1; changed = true end
        elseif stroke == Keyboard.DELETE then
            if idx < #s then s = s:sub(1, idx) .. s:sub(idx + 2); changed = true end
        elseif type(stroke) == "string" and #s < _EDIT_MAX_LEN then
            -- Insert AT the caret; accept only if the result stays a valid partial number
            -- (optional single leading '-', digits, <=1 '.', <= nd digits after the dot).
            local cand = s:sub(1, idx) .. stroke .. s:sub(idx + 1)
            local ok = false
            if stroke == "-" then
                ok = allow_neg and idx == 0 and not s:find("%-", 1, true)
            elseif stroke == "." then
                ok = nd > 0 and not s:find("%.", 1, true)
            elseif tonumber(stroke) then
                local dot = cand:find("%.")
                ok = (not dot) or (#cand - dot <= nd)
            end
            if ok then s = cand; idx = idx + 1; changed = true end
        end
    end
    if changed then c.edit_str = s; c.caret_idx = idx end
    return changed
end

-- (#497) Append/erase ONE batch of keystrokes into the search query. Mirrors the numeric
-- editor's Keyboard.keystrokes() capture but for FREE TEXT: printable ASCII (32..126) appends
-- at the end, Backspace erases the last char, capped at _SEARCH_MAX_LEN. The caret is always at
-- the end (no mid-string editing -- keeps the appended blink caret jitter-free), so no LEFT/
-- RIGHT/DELETE handling. Returns true if the query changed, so the caller re-filters only then.
function ModTweakerView:_search_apply_keystrokes()
    local s, changed = _apply_keystrokes(self._search_str or "", _SEARCH_MAX_LEN)
    if changed then self._search_str = s; self._search_caret_t = 0 end
    return changed
end

-- Live feedback for the active editor: mirror the typed string into value_text and tint
-- it red when the buffer is not a valid in-range number (a trailing bare "." is allowed
-- so the user can keep typing). Caret offset/alpha is driven by the definitions'
-- local_offset pass (it reads c._caret_renderer + c.caret_t, set/advanced here).
function ModTweakerView:_edit_live_feedback(row, dt)
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

function ModTweakerView:_commit_edit(row)
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

function ModTweakerView:_cancel_edit(row)
    local c = row.content
    -- Restore the displayed value from the (unchanged) committed value.
    c.value_text = _format_value(c.value, c.num_decimals)
    _play_click()
    self:_end_edit(row)
end

-- Shared teardown: clear edit flags + reset the value-text color to white so the next
-- frame's draw doesn't keep a red invalid-tint.
function ModTweakerView:_end_edit(row)
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

-- (#505) Recompute self._dd_visible = the array of ABSOLUTE option indices passing the current
-- filter (type-to-filter query AND active category chip). When neither is active this is the full
-- identity list, so the popup renders exactly like the unfiltered dropdown. Called on open and on
-- every query/chip change. Also re-clamps _dd_start into the (possibly shorter) filtered window.
function ModTweakerView:_recompute_dd_visible(row)
    local vals  = row._options_values or {}
    local texts = row._options_texts or {}
    local n = #texts
    local q = self._dd_query
    if type(q) == "string" then
        q = q:gsub("^%s+", ""):gsub("%s+$", "")
        q = (q == "") and nil or q:lower()
    else
        q = nil
    end
    local cat = (self._dd_cats and self._dd_cat) and self._dd_cats[self._dd_cat] or nil
    local vis = {}
    for i = 1, n do
        local keep = true
        if q then
            local t = texts[i]
            keep = type(t) == "string" and string.find(t:lower(), q, 1, true) ~= nil
        end
        if keep and cat and type(cat.match) == "function" then
            local ok, r = pcall(cat.match, vals[i], texts[i])
            keep = ok and r and true or false
        end
        if keep then vis[#vis + 1] = i end
    end
    self._dd_visible = vis
    local num_draws = math.min(#vis, 10)
    self._dd_start = math.clamp(self._dd_start or 1, 1, math.max(1, #vis - num_draws + 1))
    -- The option set changed, so drop the sticky hover index (#158b); it re-seeds to the selected
    -- (or first) option on the next _position_dropdown_highlight and can't point past the new list.
    self._dd_hl_k = nil
end

-- (#505) The chip descriptors for the open dropdown's header, or nil when it has no registered
-- categories (a length-only filterable dropdown shows just the search line, no chips). Chip 1 is
-- always the implicit "All" (clears the category), chips 2..n are the registered categories.
function ModTweakerView:_dd_chips()
    local cats = self._dd_cats
    if not (cats and #cats > 0) then return nil end
    local chips = { { label = "All", active = (self._dd_cat == nil) } }
    for i = 1, #cats do
        chips[#chips + 1] = { label = cats[i].label or ("Category " .. i), active = (self._dd_cat == i) }
    end
    return chips
end

-- (Re)build the popup overlay widget for the open dropdown at the current start_index. When the
-- dropdown is filterable (#505) the visible options are the filtered subset and a header band
-- (search line + chips) is attached; otherwise it is the full list with no header (unchanged path).
function ModTweakerView:_refresh_dropdown_list()
    local row = self._open_dropdown
    if not row then self._dd_list = nil; return end
    local start = self._dd_start or 1
    if not row._dd_filterable then
        -- Plain dropdown: full list, selected index in absolute space, no header.
        local ok, w = pcall(defs.create_dropdown_list, row._options_texts or {}, row._option_idx or 1,
                            row._list_y or 0, start)
        self._dd_list = (ok and w) or nil
        return
    end
    -- Filtered dropdown: map the visible subset to display texts + the selected option's FILTERED
    -- index (or -1 when the selection is filtered out, so nothing renders gold).
    local vis = self._dd_visible or {}
    local all_texts = row._options_texts or {}
    local texts, cur = {}, -1
    for fi = 1, #vis do
        texts[fi] = all_texts[vis[fi]] or ""
        if vis[fi] == row._option_idx then cur = fi end
    end
    self._dd_no_match = (#texts == 0)
    if self._dd_no_match then texts = { "(no matches)" }; cur = -1 end
    local header = { query = self._dd_query or "", chips = self:_dd_chips() }
    local ok, w = pcall(defs.create_dropdown_list, texts, cur, row._list_y or 0, start, header)
    self._dd_list = (ok and w) or nil
end

function ModTweakerView:_open_dropdown_popup(row)
    -- Committing any active type-edit first keeps a single modal surface.
    if self._editing_row then self:_commit_edit(self._editing_row) end
    self._open_dropdown = row
    self._dd_hl_k = nil   -- (#158b) reset the sticky highlight index for this open
    row.content.active = true
    -- (#505) Fresh per-open filter state. Look up any registered category chips for this
    -- (mod_id, setting_id); a dropdown is filterable when it is long OR has categories.
    self._dd_query = ""
    self._dd_cat = nil
    self._dd_cats = nil
    self._dd_no_match = false
    self._dd_caret_t = 0
    local mt = _mt()
    if mt and mt.get_dropdown_categories then
        local ok, cats = pcall(mt.get_dropdown_categories, mt, row._mod_id, row._setting_id)
        if ok and type(cats) == "table" and #cats > 0 then self._dd_cats = cats end
    end
    local n = #(row._options_texts or {})
    row._dd_filterable = (n >= DD_FILTER_MIN) or (self._dd_cats ~= nil)
    self._dd_start = 1
    if row._dd_filterable then
        self:_recompute_dd_visible(row)
        -- Scroll the FILTERED window so the selected option is visible (native start_index clamp).
        local vis, sel_fi = self._dd_visible, nil
        for fi = 1, #vis do if vis[fi] == row._option_idx then sel_fi = fi; break end end
        local num_draws = math.min(#vis, 10)
        if sel_fi then
            self._dd_start = math.clamp(sel_fi - num_draws + 1, 1, math.max(1, #vis - num_draws + 1))
            if sel_fi <= num_draws then self._dd_start = 1 end
        end
    else
        local num_draws = math.min(n, 10)
        self._dd_start = math.clamp((row._option_idx or 1) - num_draws + 1, 1, math.max(1, n - num_draws + 1))
        if (row._option_idx or 1) <= num_draws then self._dd_start = 1 end
    end
    self:_refresh_dropdown_list()
    _play_click()
end

function ModTweakerView:_close_dropdown_popup()
    local row = self._open_dropdown
    if row then row.content.active = false end
    self._open_dropdown = nil
    self._dd_list = nil
    -- (#505) Drop the per-open filter state so a later plain dropdown can't read a stale query/cat.
    self._dd_query = nil
    self._dd_cat = nil
    self._dd_cats = nil
    self._dd_visible = nil
    self._dd_no_match = false
    -- (#158) The closing click's on_release stays LATCHED on the shared mt_list_start node; block
    -- ALL row input until the next fresh left-press (read by _handle_input) so it can't bleed
    -- through to the row behind the just-closed popup, nor re-open the dropdown.
    self._dd_block_until_press = true
end

function ModTweakerView:_commit_dropdown(opt_i)
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
function ModTweakerView:_position_dropdown_highlight()
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
    -- (#158b) STICKY highlight. The bug: every frame the cursor's hover briefly dropped (crossing
    -- between rows, an is_hover flicker, or leaving the popup) the old code SNAPPED the highlight to
    -- the selected option — which for a top/None-selected dropdown is row 1 — i.e. the "flicker to
    -- the top". Fix: when an option IS hovered, remember it (_dd_hl_k); when nothing is hovered,
    -- KEEP the last index instead of snapping. Seed at the selected option only on the first frame
    -- after open (_dd_hl_k reset to nil in _open_dropdown_popup). The highlight only ever moves to a
    -- row the cursor actually hovered.
    if hovered_k then
        self._dd_hl_k = hovered_k
    elseif self._dd_hl_k == nil then
        -- (#505) Seed from the FILTERED-space selected index the popup was built with (w._dd_cur);
        -- for a plain dropdown that equals row._option_idx in absolute space (unchanged). -1 = the
        -- selection is filtered out, so no seed and the highlight stays hidden until a hover.
        local oi = w._dd_cur
        if oi and oi >= 1 then
            local sel_k = oi - (w._dd_start or 1) + 1
            if sel_k >= 1 and sel_k <= num_draws then self._dd_hl_k = sel_k end
        end
    end
    local k = self._dd_hl_k
    if k and k >= 1 and k <= num_draws and w.style and w.style.hl then
        w.style.hl.offset[2] = (w._dd_list_top or 0) - k * (w._dd_row_h or 24)
        c.hl_visible = true
    else
        c.hl_visible = false
    end
end

-- MODAL popup input. Returns true if it consumed the frame (caller returns early).
-- Handles: wheel-scroll of a long option list, per-option click (commit), and
-- click-away (close without committing). The popup widget's hotspots fire
-- on_left_release (shared-node semantics, same as the rows).
function ModTweakerView:_handle_dropdown_input(input_service)
    local row = self._open_dropdown
    if not row then return false end
    local w = self._dd_list
    if not w then self:_close_dropdown_popup(); return true end
    local c = w.content
    local n = w._dd_total or 0
    local num_draws = w._dd_num_draws or 0

    -- (#505) FILTER HEADER input (only for a filterable dropdown): category-chip clicks +
    -- type-to-filter keystrokes. Handled before wheel/option/click-away so a filtering keystroke
    -- or chip click is never also read as an option interaction. Chat input is blocked each frame
    -- so keys/Enter don't leak to game chat (the modal device block doesn't cover chat_input).
    if row._dd_filterable then
        if Managers.chat and Managers.chat.block_chat_input_for_one_frame then
            pcall(function() Managers.chat:block_chat_input_for_one_frame() end)
        end
        local chip_count = w._dd_chip_count or 0
        for ci = 1, chip_count do
            local hs = c["chip_" .. ci]
            if hs and (hs.on_release or hs.on_left_release) then
                -- Chip 1 = "All" (clear the category); chips 2..n = category (ci - 1).
                self._dd_cat = (ci == 1) and nil or (ci - 1)
                self._dd_start = 1
                self:_recompute_dd_visible(row)
                self:_refresh_dropdown_list()
                _play_click()
                return true
            end
        end
        local newq, changed = _apply_keystrokes(self._dd_query or "", _SEARCH_MAX_LEN)
        if changed then
            self._dd_query = newq
            self._dd_caret_t = 0
            self._dd_start = 1
            self:_recompute_dd_visible(row)
            self:_refresh_dropdown_list()
            return true
        end
    end

    -- Wheel scrolls the visible option window (only when the list overflows). n is the FILTERED
    -- option count (w._dd_total), so this clamps against what is actually shown.
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

    -- Per-option click -> commit. For a filtered dropdown, the visible row k maps through
    -- self._dd_visible back to the ABSOLUTE option index; for a plain dropdown _dd_visible is nil
    -- and the click is the absolute index directly (unchanged). A "(no matches)" placeholder row
    -- maps to nil and is ignored.
    for k = 1, num_draws do
        local hs = c["opt_" .. k]
        if hs and (hs.on_release or hs.on_left_release) then
            local fi = (w._dd_start or 1) + k - 1
            local abs
            if row._dd_filterable then
                abs = self._dd_visible and self._dd_visible[fi]   -- nil for the "(no matches)" row
            else
                abs = fi
            end
            if abs then self:_commit_dropdown(abs) else self:_close_dropdown_popup() end
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

function ModTweakerView:_handle_input(input_service)
    -- (v0.2.69-dev) MODAL dropdown popup: while a dropdown is open, the popup owns input
    -- (option click / wheel-scroll / click-away). Short-circuit so no other row reacts.
    if self._open_dropdown then
        if self:_handle_dropdown_input(input_service) then return end
    end

    -- (#158) After a dropdown popup closes, the closing click's on_release stays LATCHED on the
    -- shared mt_list_start node for an UNBOUNDED number of frames (the old 6-frame swallow was too
    -- short -> the row BEHIND got clicked, and clicking an open dropdown re-opened it). Block ALL
    -- row input until the next FRESH left-press begins a new click cycle; the stale latch always
    -- clears long before the user clicks again. Mouse.pressed(0) = a genuinely new press.
    if Mouse.pressed(0) then self._dd_block_until_press = false end
    if self._dd_block_until_press then return end

    -- (#497) SEARCH BOX focus + typing. A left-press ON the box focuses it (committing any
    -- active numeric edit first); a left-press anywhere ELSE drops focus (the filter stays
    -- applied). While focused, printable keystrokes edit the query and the list re-filters live;
    -- chat input is blocked each frame so keys/Enter never leak to game chat (the numeric editor
    -- needs the same lever, ChatManager.block_chat_input_for_one_frame -- the modal device block
    -- does not cover the independent chat_input service), and Enter drops focus keeping the
    -- filter. Placed before the scroll/button/row handling so a filtering keystroke is never
    -- also read as a row interaction.
    do
        local sc = self._search and self._search.content
        local shs = sc and sc.hotspot
        if Mouse.pressed(0) then
            if shs and shs.is_hover then
                if not self._search_focused then
                    if self._editing_row then self:_commit_edit(self._editing_row) end
                    self._capturing_keybind = nil
                    self._search_focused = true
                    self._search_caret_t = 0
                    _play_click()
                end
            else
                self._search_focused = false
            end
        end
        if self._search_focused then
            if Managers.chat and Managers.chat.block_chat_input_for_one_frame then
                pcall(function() Managers.chat:block_chat_input_for_one_frame() end)
            end
            if Keyboard.released(13) then   -- Enter: keep the filter, drop focus
                self._search_focused = false
                _play_click()
                return
            end
            if self:_search_apply_keystrokes() then
                self._scroll_y = 0
                self:_build_rows(self._categories[self._selected])
                return
            end
        end
    end

    -- Scroll: mouse wheel (1 notch ~= 1 row) + scrollbar thumb drag. The wheel reads
    -- scroll_axis off the menu input service; the thumb drag tracks the cursor like
    -- the vanilla scrollbar held_function (inverse-scaled cursor vs the track top).
    if (self._max_scroll or 0) > 0 then
        local wheel = input_service and input_service:get("scroll_axis")
        if wheel and wheel.y and wheel.y ~= 0 then
            self._scroll_y = math.clamp((self._scroll_y or 0) - wheel.y * 46, 0, self._max_scroll)
        end
        -- Thumb drag (#91): the hotspot pass sets is_held while the LMB is held over
        -- the scrollbar (its own node, so unlike the shared-node rows this fires fine).
        --
        -- OLD bug: mapped the cursor's ABSOLUTE position on the track straight to
        -- scroll_value (`rel = (track_top - cursor)/visible_h`), with NO grab-offset and
        -- ignoring the thumb's own height. So grabbing the thumb anywhere snapped its TOP
        -- to the cursor — clicking the lower part of the thumb jumped it up to the top.
        --
        -- FIX: record a grab-offset on the first held frame (the scroll_value at grab +
        -- the cursor Y at grab), then track the cursor DELTA over the thumb's real travel
        -- (track_h * (1 - thumb_frac), the only distance the thumb top can move). +Y is up,
        -- so cursor moving DOWN (decreasing Y) increases scroll. This keeps the point you
        -- grabbed under the cursor and respects the thumb size.
        local hs = self._scrollbar and self._scrollbar.content.hotspot
        if hs and hs.is_held then
            local cursor = input_service and input_service:get("cursor")
            if cursor then
                local c = UIInverseScaleVectorToResolution(cursor)
                local track_h = math.max(1, self._visible_h or 700)
                local thumb_frac = (self._content_h and self._content_h > 0)
                    and math.clamp(track_h / self._content_h, 0.06, 1) or 1
                local travel = track_h * (1 - thumb_frac)   -- px the thumb top can move
                if not self._sb_dragging then
                    -- First held frame: anchor the grab so the thumb doesn't jump.
                    self._sb_dragging = true
                    self._sb_grab_cursor_y = c[2]
                    self._sb_grab_scroll_value = (self._max_scroll > 0)
                        and (self._scroll_y / self._max_scroll) or 0
                end
                if travel > 0 then
                    -- cursor DOWN (c[2] < grab) => positive delta => more scroll.
                    local dv = (self._sb_grab_cursor_y - c[2]) / travel
                    local sv = math.clamp((self._sb_grab_scroll_value or 0) + dv, 0, 1)
                    self._scroll_y = sv * self._max_scroll
                end
            end
        else
            -- Hold released: clear the grab anchor so the next press re-anchors.
            self._sb_dragging = false
        end
    end

    -- Exit (X) button.
    if self._exit and self._exit.content.button_hotspot and self._exit.content.button_hotspot.on_release then
        _play_click()
        -- (#124) The X closes the whole menu -> return to the GAME (exit(true) ->
        -- "exit_menu"), same as the final ESC close. Origin capture stays exit()'s fallback.
        self:exit(true)
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

    -- (Fix 3, v0.2.151-dev) RESTORE DEFAULTS button: show a native confirm popup FIRST.
    -- Only the CONFIRM result runs reset_to_defaults (current tab only); the result is
    -- polled in update() via _check_reset_popup.
    do
        local rh = self._reset and self._reset.content.button_hotspot
        if rh and (rh.on_release or rh.on_left_release) then
            self:_queue_reset_popup()
            return
        end
    end

    -- Tab clicks. The "More" tab advances the page; mod tabs switch selection. (#151)
    -- Clicking a tab while drilled into an advanced/gear view EXITS the drill and switches —
    -- the old code disabled tabs mid-drill (it read as "the tabs are broken"). Clear _drill on
    -- any tab/page click so the new selection always opens on its normal list.
    for i = 1, #self._tabs do
        local bt = self._tabs[i].content.hotspot
        if bt and bt.on_release then
            _play_click()
            mod:debug("[mt:dump] input: tab[%d] clicked (was %d, drill=%s)", i, self._selected or -1, tostring(self._drill ~= nil))
            if self._more_tab_index and i == self._more_tab_index then
                self._drill = nil
                self._search_str = ""; self._search_focused = false   -- (#497) fresh tab, fresh search
                self._page = ((self._page or 0) + 1) % math.max(1, self._page_count or 1)
                self._selected = 1
                self._scroll_y = 0
                self:_rebuild()
                return
            elseif (i ~= self._selected or self._drill) and self._categories[i] then
                self._drill = nil
                self._search_str = ""; self._search_focused = false   -- (#497) fresh tab, fresh search
                self._selected = i
                self._scroll_y = 0
                self:_build_rows(self._categories[i])
                return
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

    -- (#slider-modal) Detect a slider being DRAGGED before processing rows, so the drag is MODAL:
    -- while held, no OTHER row reacts to clicks/releases (releasing over a checkbox was toggling
    -- it) and only the dragged row highlights. track_hs.is_held is set by the engine each frame.
    self._slider_dragging = nil
    for i = 1, #self._rows do
        local r = self._rows[i]
        local cc = r.content
        -- is_held = mid-drag. r._dragging stays true THROUGH the release frame (the slider branch
        -- below clears it), so the modal also covers the RELEASE frame — that release was landing
        -- on a checkbox behind the cursor and toggling it.
        if (cc and cc.track_hs and cc.track_hs.is_held) or r._dragging then self._slider_dragging = r; break end
    end

    -- Rows. Persist on change via _cat_set (routes to the real VMF mod object, or
    -- the gut controller for the dogfood category).
    for i = 1, #self._rows do
        local row = self._rows[i]
        -- Skip rows culled this frame (outside the list_mask) so a click on a scrolled-away row
        -- can't register. While a slider is dragging, ALSO skip every OTHER row (modal drag) so
        -- the cursor can't toggle/click anything else mid-drag.
        if not row._readonly and row._middle_visible ~= false
           and not (self._slider_dragging and row ~= self._slider_dragging) then
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
                    local gid = row._group_key
                    local now_expanded = not self._expanded[gid]
                    self._expanded[gid] = now_expanded or nil
                    -- (#163) Auto-collapse (default ON): opening closes same-level siblings; closing
                    -- collapses nested descendants — one branch open per level.
                    if self:_auto_collapse_on() then
                        self:_auto_collapse_apply(gid, now_expanded)
                    end
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
                    -- (#446) Mutually-exclusive group: turning a member ON stages its
                    -- siblings OFF, then rebuild so the switched-off rows repaint (checkbox
                    -- display is cached -- only a row rebuild re-reads the staged flag). Same
                    -- rebuild+return shape as the group-header toggle above. Turning a member
                    -- OFF (c.flag=false) is the "select None" path and touches no sibling.
                    -- Block row input until the next FRESH press so this release's still-
                    -- latched on_left_release on the shared mt_list_start node can't re-toggle
                    -- the rebuilt rows next frame (same latch class as the dropdown #158 /
                    -- slider-modal guard).
                    if c.flag and self:_enforce_exclusive(row._category, row._setting_id) then
                        self._dd_block_until_press = true
                        self:_build_rows(self._categories[self._selected])
                        return
                    end
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
            elseif row._wtype == "keybind" then
                -- (#123) Left-click -> capture; right-click -> clear (like native options);
                -- Esc-while-capturing clears via the top-level ESC handler. Chat is blocked
                -- while capturing so Enter / letters can't leak to the game chat box.
                if self._capturing_keybind == row then
                    if Managers.chat and Managers.chat.block_chat_input_for_one_frame then
                        pcall(function() Managers.chat:block_chat_input_for_one_frame() end)
                    end
                    local combo = _poll_keybind_combo()
                    if combo then
                        self._capturing_keybind = nil
                        self:stage_set(row._category, row._setting_id, combo)   -- (#123) STAGE; registers on APPLY
                        row.content.value_text = _format_keybind_value(combo)
                        _play_click()
                        return
                    end
                elseif c.hotspot and c.hotspot.is_hover and Mouse.released(1) then
                    -- RIGHT-CLICK -> clear the binding (unbind), like native options. STAGED; applies on APPLY.
                    self:stage_set(row._category, row._setting_id, {})
                    row.content.value_text = _format_keybind_value({})
                    _play_click()
                    return
                elseif c.hotspot and (c.hotspot.on_release or c.hotspot.on_left_release) then
                    if self._editing_row then self:_commit_edit(self._editing_row) end
                    self._capturing_keybind = row
                    row.content.value_text = "PRESS A KEY..."
                    _play_click()
                    return
                end
            elseif row._wtype == "slider" or row._wtype == "numeric" then
                local cur = (type(c.value) == "number") and c.value or (c.min or 0)
                local moved, commit, play_sound = false, false, false
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
                if ths and ths.is_held and c.track_w then
                    -- DRAG: follow the cursor ONLY while the LMB is HELD (visual; commit on release).
                    local cursor = input_service and input_service:get("cursor")
                    if cursor then
                        local anchor = UISceneGraph.get_world_position(self.ui_scenegraph, defs.list_sg)
                        local cx = UIInverseScaleVectorToResolution(cursor)[1]
                        local frac = math.clamp((cx - (anchor[1] + (c.track_x or 0))) / math.max(1, c.track_w), 0, 1)
                        cur = (c.min or 0) + frac * ((c.max or 1) - (c.min or 0))
                        -- (#164) snap the dragged value to the step grid (anchored at range
                        -- min), or to decimals when no step — the SAME math the arrow + text-
                        -- entry paths use, so drag/arrow/type all land on identical grid points.
                        cur = _snap_and_clamp(c, cur)
                        moved = true
                        row._dragging = true
                    end
                elseif row._dragging then
                    -- (#167) DRAG ENDED (is_held dropped): commit + play the sound EXACTLY ONCE,
                    -- edge-latched. The old code keyed off on_left_release, which stays LATCHED on
                    -- the shared node for several frames -> it re-ran the cursor math (slider kept
                    -- "following" after release) AND fired commit+_play_click each frame (the 3-6
                    -- machine-gun increment clicks). is_held is the live held state and drops cleanly.
                    -- (#slider-modal) Block other rows' input until the next fresh press, so the
                    -- release's still-LATCHED on_release on a checkbox behind the cursor can't toggle
                    -- it once the drag-modal disengages next frame (same latch class as dropdown #158).
                    self._dd_block_until_press = true
                    row._dragging = false
                    commit = true; play_sound = true
                end
                -- (#152) Arrow step = ONE natural increment per click (1 for ints, 10^-dec),
                -- NOT the old ~range/40. Edge-latched so the multi-frame on_release latch can't
                -- step more than once per physical click (the "single click moves too much" +
                -- "auto-moves" bug). A HELD arrow then repeats after a delay and accelerates,
                -- matching the vanilla feel. The hold path uses is_held: if the dec/inc hotspots
                -- don't expose it, it's simply inert and the click path still gives 1-per-click.
                local nd = c.num_decimals or 0
                local unit = c.step or ((nd > 0) and (10 ^ -nd) or 1)  -- (#164) honor the slider's declared step
                local rel_dir = (c.dec and (c.dec.on_release or c.dec.on_left_release) and -1)
                             or (c.inc and (c.inc.on_release or c.inc.on_left_release) and 1) or 0
                if rel_dir ~= 0 then
                    if not row._arrow_latched then
                        row._arrow_latched = true
                        cur = _snap_and_clamp(c, cur + rel_dir * unit); moved = true; commit = true; play_sound = true  -- (#164) step + snap to grid (min-anchored)
                        _printf("[gut:slider-arrow] %s CLICK dir=%d step=%s -> %s", tostring(row._setting_id), rel_dir, tostring(unit), tostring(cur))
                    end
                else
                    row._arrow_latched = false
                end
                local hold_dir = (c.dec and c.dec.is_held and -1) or (c.inc and c.inc.is_held and 1) or 0
                if hold_dir ~= 0 then
                    row._arrow_hf = (row._arrow_hf or 0) + 1
                    if row._arrow_hf >= (row._arrow_hnext or 22) then   -- ~0.37s delay before first repeat
                        cur = _snap_and_clamp(c, cur + hold_dir * unit); moved = true; commit = true  -- (#164) step + snap to grid (min-anchored)
                        row._arrow_hnext = row._arrow_hf + math.max(2, 11 - math.floor(row._arrow_hf / 20))  -- accelerate
                        _printf("[gut:slider-arrow] %s HOLD-REPEAT f=%d dir=%d -> %s", tostring(row._setting_id), row._arrow_hf, hold_dir, tostring(cur))
                    end
                else
                    row._arrow_hf, row._arrow_hnext = 0, 22
                end
                -- Visual tracks the value every frame (smooth drag); persistence waits.
                if moved and cur ~= c.value then
                    c.value = cur
                    local span = (c.max or 1) - (c.min or 0)
                    c.internal_value = (span > 0) and math.clamp((cur - c.min) / span, 0, 1) or 0
                    c.value_text = string.format("%." .. (c.num_decimals or 0) .. "f", cur)
                    -- PROBE: confirms the drag handler updates internal_value (drives the
                    -- thumb) every frame. If internal_value sweeps 0->1 here but the thumb
                    -- visually doesn't move, the defect is the thumb's offset_function /
                    -- material, NOT the input math. thumb_x is what the offset_function
                    -- should compute (TRACK_X + TRACK_W*internal).
                    mod:debug("[mt:slider] DRAG '%s' val=%s internal=%.3f thumb_x~=%.0f (track_x=%s track_w=%s)",
                        tostring(row._setting_id), tostring(cur), c.internal_value,
                        (c.track_x or 0) + (c.track_w or 0) * c.internal_value,
                        tostring(c.track_x), tostring(c.track_w))
                end
                if commit then
                    -- (#152b) Click sound on the CLICK / drag-release EDGE only, NEVER on every
                    -- hold-repeat increment (that was the "machine-gun click-click-click").
                    if play_sound then _play_click() end
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
-- settings_arrow_clicked on hover) was REMOVED. The vanilla options menu does NOT
-- hard-swap a stepper/slider arrow to its bright "clicked" sprite on mere hover —
-- it fades a soft glow overlay's alpha (on_stepper_arrow_hover, options_view.lua:
-- 4335-4351) and otherwise relies on the row highlight. gut's instant swap read as
-- a pressed-down button under the cursor. Hover feedback now comes solely from the
-- whole-row playerlist_hover highlight (kept below), which the user confirmed looks
-- right. The arrows therefore stay on settings_arrow_normal at all times (the
-- factory's default), so nothing here touches left_arrow/right_arrow anymore.
function ModTweakerView:_apply_row_hover(row)
    local c = row.content
    if not c then return end
    -- (#158 / #slider-modal) While a dropdown popup is OPEN, or a slider is being dragged, it's
    -- MODAL: suppress every OTHER row's hover highlight + hover sound, so the menu doesn't light up
    -- phantom rows behind the popup or under the cursor mid-drag.
    if self._open_dropdown or (self._slider_dragging and row ~= self._slider_dragging) then
        if c.is_highlighted ~= nil then c.is_highlighted = false end
        row._was_hovered = false
        return
    end
    -- (1) row highlight from whichever hotspot the row exposes.
    local row_hot = c.hotspot or c.track_hs
    local hovered = (row_hot and row_hot.is_hover) and true or false
    if (c.dec and c.dec.is_hover) or (c.inc and c.inc.is_hover) then hovered = true end
    -- (row highlight) Full-row hover hotspot (added in _append_highlight) so dropdown / slider /
    -- keybind rows highlight when the cursor is over their LABEL, not only the control.
    if c.row_hs and c.row_hs.is_hover then hovered = true end
    -- (Fix 4, v0.2.149-dev) An EXPANDED collapsible group stays lit (row highlight bar +
    -- arrow glow) even when not hovered, so the open section reads as active. Thread the LIVE
    -- expanded state (self._expanded[row._group_key] — the same source the row toggle uses)
    -- into content.expanded so create_group_header's glow driver sees it each frame.
    if row._is_group then
        local exp = self._expanded[row._group_key] and true or false
        c.expanded = exp
        if exp then hovered = true end
    end
    if c.is_highlighted ~= nil then c.is_highlighted = hovered end
    -- (#165) Collapsible arrow brightening now lives in create_group_header's local_offset driver
    -- (mutates the live ui_style at draw-time); the pre-draw row.style write here didn't render.
    -- (2) hover-enter edge sound (debounced on the row's own _was_hovered flag).
    if hovered and not row._was_hovered then _play_hover() end
    row._was_hovered = hovered
end

-- (#207) HOVER INFO POPUP fade + draw. Replicates the native option-tooltip fade EXACTLY
-- (ui_settings.lua:22-23 -> tooltip_wait_duration = 0.1, tooltip_fade_in_speed = 4): on a
-- tooltip'd row becoming hovered, wait 0.1s (alpha 0), then ramp progress by dt*4 and set
-- alpha = math.easeOutCubic(progress); on no-hover OR a different row, reset progress = 0 +
-- wait = 0.1 -> alpha 0 -> instant disappear. `hover_row` is the hovered tooltip row this
-- frame (or nil); `hover_world_y` its bottom-edge world Y (for layout's on-screen flip).
-- Drawn on the SAME borrowed renderer the rows use, inside the protected begin/end_pass.
local TT_WAIT, TT_SPEED = 0.1, 4
function ModTweakerView:_update_tooltip(dt, hover_row, hover_world_y, renderer)
    -- Modal suppression: no tooltip while a dropdown popup is open, a slider is being
    -- dragged, or a numeric field is being edited (matches _apply_row_hover's suppression).
    if self._open_dropdown or self._slider_dragging or self._editing_row then hover_row = nil end

    if hover_row and hover_row == self._tt_row then
        if (self._tt_wait or 0) > 0 then
            self._tt_wait = self._tt_wait - dt
            self._tt_alpha = 0
        else
            self._tt_progress = math.min((self._tt_progress or 0) + dt * TT_SPEED, 1)
            self._tt_alpha = math.easeOutCubic(self._tt_progress)
        end
    else
        -- De-hover OR moved to a different row: reset (instant disappear) + adopt the new row.
        self._tt_progress = 0
        self._tt_wait = TT_WAIT
        self._tt_alpha = 0
        self._tt_row = hover_row
    end

    local row = self._tt_row
    if not (row and (self._tt_alpha or 0) > 0 and self._tooltip) then return end
    local ok = pcall(defs.layout_tooltip, self._tooltip, renderer,
        row._tip_title or (row.content and row.content.label) or "", row._tip_desc or "",
        row._list_y or 0, hover_world_y or 0, self._tt_alpha)
    if ok then UIRenderer.draw_widget(renderer, self._tooltip) end
end

-- ---------------------------------------------------------------
-- Draw (single begin_pass/end_pass on the borrowed top renderer)
-- ---------------------------------------------------------------

function ModTweakerView:_draw(dt, input_service)
    -- Draw on ui_top_renderer (top_ingame_view world) — the SAME renderer OptionsView
    -- and IngameView use. The old code drew on ui_renderer (level_world / in-mission
    -- HUD renderer); gut was the ONLY ESC-flow view touching level_world, and the
    -- state it left there polluted IngameView's chrome on the next frame, so the ESC
    -- menu came back as flat "deprecated" buttons (root cause: workflow wf_8504e8ba).
    -- Our rows were already rebuilt to use only atlas-safe materials (matchmaking_
    -- checkbox / slider_thumb / rect / border), which resolve on ui_top_renderer, so
    -- the original reason for level_world (the raw OVD checkbox materials) no longer
    -- applies.
    local renderer = self.ui_top_renderer or self.ui_renderer
    local scenegraph = self.ui_scenegraph

    -- (Fix 2) Tab text color matches the VANILLA options tabs (UIWidgets.create_text_button,
    -- ui_widgets.lua:9200-9229): NORMAL = font_button_normal {255,160,146,101}; SELECTED OR
    -- HOVERED = white {255,255,255,255} (native text_hover fires on is_hover OR is_selected).
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
            if tab.content.disabled then
                -- (VMF-disabled mod) tab greyed out: dim + low alpha, regardless of hover/selected.
                st.text_color[1] = 110; st.text_color[2] = 90; st.text_color[3] = 90; st.text_color[4] = 90
            elseif active then
                -- selected OR hovered -> white (vanilla text_hover).
                st.text_color[1], st.text_color[2], st.text_color[3], st.text_color[4] = 255, 255, 255, 255
            else
                -- idle -> font_button_normal (vanilla text).
                st.text_color[1], st.text_color[2], st.text_color[3], st.text_color[4] = 255, 160, 146, 101
            end
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
            -- (v0.2.157-dev) EXACT vanilla colours FARMED from the live game's ready Apply
            -- button ([opt-apply] probe, OptionsView.update_apply_button): ready = cheeseburger
            -- {255,255,168,0}, hover = white {255,255,255,255}, disabled = gray a50
            -- {50,128,128,128}. (Format is {A,R,G,B}.) The prior font_button_normal/font_default
            -- values were a wrong guess -- vanilla's Apply is cheeseburger when ready, NOT the tab
            -- colour; and disabled is gray a50, NOT font_default a75.
            if not enabled then
                t[1], t[2], t[3], t[4] = 50, 128, 128, 128            -- gray a50 (vanilla disabled)
            elseif hovered then
                t[1], t[2], t[3], t[4] = 255, 255, 255, 255           -- white on hover
            else
                t[1], t[2], t[3], t[4] = 255, 255, 168, 0             -- cheeseburger (vanilla ready)
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

    -- (v0.2.148-dev) RESTORE DEFAULTS button per-frame styling. Always enabled; brighten the
    -- text to white on hover (else font_default grey), and play the hover-enter sound edge-
    -- debounced on self._reset._was_hovered — mirroring the APPLY button feedback.
    if self._reset then
        local rc = self._reset.content
        local rsty = self._reset.style
        local r_hov = rc.button_hotspot and rc.button_hotspot.is_hover
        if r_hov and not self._reset._was_hovered then _play_hover() end
        self._reset._was_hovered = r_hov
        if rsty.text and rsty.text.text_color then
            local t = rsty.text.text_color
            -- (Fix 3, v0.2.149-dev) Match the TAB / Apply create_text_button scheme:
            -- idle = font_button_normal {255,160,146,101} (was font_default {255,181,181,181}),
            -- white {255,255,255,255} on hover. Always enabled.
            if r_hov then
                t[1], t[2], t[3], t[4] = 255, 255, 255, 255         -- white on hover
            else
                t[1], t[2], t[3], t[4] = 255, 160, 146, 101         -- font_button_normal (idle)
            end
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
    -- the borrowed ui_renderer is left mid-pass and the ESC menu's own chrome (which
    -- draws on the SAME ui_renderer / level_world) renders without its background —
    -- that's the "main menu looks deprecated (just buttons)" after leaving here.
    local _draw_ok, _draw_err = pcall(function()

    for i = 1, #(self._chrome or {}) do
        UIRenderer.draw_widget(renderer, self._chrome[i])
    end
    -- (Fix 5, v0.2.149-dev) bottom hint widget removed — nothing to draw here.
    for i = 1, #self._tabs do
        UIRenderer.draw_widget(renderer, self._tabs[i])
    end
    -- v0.2.65-dev: no title to draw — removed to match native Options (tabs span the
    -- full top band).
    if self._exit then UIRenderer.draw_widget(renderer, self._exit) end
    -- (v0.2.70-dev) APPLY button (bottom-right of the bottom panel). Drawn with the chrome
    -- so it's never culled by the list_mask (it lives outside the scrolling list).
    if self._apply then UIRenderer.draw_widget(renderer, self._apply) end
    -- (v0.2.148-dev) RESTORE DEFAULTS button (to the LEFT of Apply). Same render path.
    if self._reset then UIRenderer.draw_widget(renderer, self._reset) end

    -- (#497) SEARCH box: update its text (query + blink caret, or the placeholder) + focus
    -- emphasis, then draw it as fixed chrome above the list. Drawn every frame so its hotspot
    -- flags populate for _handle_input (which runs after _draw). It lives on mt_search (its own
    -- fixed node above list_mask), so it never overlaps or culls with the scrolling rows.
    if self._search then
        local sc  = self._search.content
        local sty = self._search.style
        local q = self._search_str or ""
        local focused = self._search_focused
        self._search_caret_t = (self._search_caret_t or 0) + (dt or 0)
        if q == "" and not focused then
            sc.text = "Search this tab... (click, then type to filter)"
            if sty.text and sty.text.text_color then
                sty.text.text_color[1], sty.text.text_color[2], sty.text.text_color[3], sty.text.text_color[4] = 160, 120, 120, 120
            end
        else
            local blink = focused and (self._search_caret_t % 1.0) < 0.5
            sc.text = q .. (blink and "|" or "")
            if sty.text and sty.text.text_color then
                sty.text.text_color[1], sty.text.text_color[2], sty.text.text_color[3], sty.text.text_color[4] = 255, 255, 255, 255
            end
        end
        if sty.bg_inner and sty.bg_inner.color then
            local v = focused and 26 or 14
            sty.bg_inner.color[2], sty.bg_inner.color[3], sty.bg_inner.color[4] = v, v, v
        end
        UIRenderer.draw_widget(renderer, self._search)
    end

    -- Cull + draw rows against the list_mask box (CPU position-cull; no GPU mask).
    -- World positions are valid here because begin_pass re-evaluated the scenegraph
    -- with the scroll offset set above.
    local mask_pos  = UISceneGraph.get_world_position(scenegraph, defs.list_mask_sg)
    local mask_size = UISceneGraph.get_size(scenegraph, defs.list_mask_sg)
    local anchor    = UISceneGraph.get_world_position(scenegraph, defs.list_sg)  -- mt_list_start (scrolled)
    -- (#207) The hovered row that carries a tooltip becomes the active popup target.
    local tt_hover_row, tt_hover_world_y
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
            -- (#207) Capture the hovered tooltip'd row (+ its bottom-edge world Y for the
            -- on-screen flip test). Either the full-row hover hotspot (row_hs, added by
            -- _append_highlight) or the row's own hotspot counts as "hovered".
            if row._tip_desc and row._tip_desc ~= "" then
                local rc = row.content
                if (rc.row_hs and rc.row_hs.is_hover) or (rc.hotspot and rc.hotspot.is_hover) then
                    tt_hover_row, tt_hover_world_y = row, py
                end
            end
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
        -- (#505) Live search-line text + blink caret for a filterable popup's header (same
        -- per-frame update the fixed search box uses). content.search_text only exists when the
        -- popup was built with a header, so guard on it — a plain dropdown has no header band.
        local dc = self._dd_list.content
        if dc and dc.search_text ~= nil then
            self._dd_caret_t = (self._dd_caret_t or 0) + (dt or 0)
            local q = self._dd_query or ""
            if q == "" then
                dc.search_text = "Type to filter..."
            else
                local blink = (self._dd_caret_t % 1.0) < 0.5
                dc.search_text = q .. (blink and "|" or "")
            end
        end
        self:_position_dropdown_highlight()
        UIRenderer.draw_widget(renderer, self._dd_list)
    end

    -- (#207) HOVER INFO POPUP — fade + draw last (over the rows; suppressed while a
    -- dropdown popup is open). Mutually exclusive with the dropdown popup in practice.
    self:_update_tooltip(dt, tt_hover_row, tt_hover_world_y, renderer)

    end)  -- close pcall(function()
    UIRenderer.end_pass(renderer)  -- ALWAYS runs, even if a draw above errored
    if not _draw_ok then
        mod:warning("[mt] draw error (end_pass protected so the menu chrome survives): %s", tostring(_draw_err))
    end
end

-- (#164) Exposed for /gut_regression_test (mod_tweaker_step_resolution): the pure step-resolution
-- + grid-snap helpers, unit-testable without building a live view. Statics, not methods.
ModTweakerView._resolve_step = _resolve_step
ModTweakerView._snap_and_clamp = _snap_and_clamp

return ModTweakerView
