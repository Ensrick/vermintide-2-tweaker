local mod = get_mod("gut_dev")

-- _gut_mod_tweaker_contracts.lua - runtime contracts for Mod Tweaker integration.
--
-- Owns the engine-live regression registrations for the ESC/view transition,
-- registry, controls, crafting bridge, compendium access, and Cosmetics mount.
-- The main entry installs these contracts once through a two-function API; this
-- module owns no hooks, commands, or lifecycle callback.
--
-- Owned by: gui_tweaker_dev.lua. Consumed via: mod:dofile + install.

local M = {}

function M.install(api)
    local _rt_register = assert(api.register, "Mod Tweaker contracts require register")
    local _rt_src_read = assert(api.src_read, "Mod Tweaker contracts require src_read")
    local math = math

_rt_register("issue605_dialogue_collapse_and_tristate", function()
    local dialogue = mod:dofile("scripts/mods/gui_tweaker_dev/_mod_tweaker_dialogue")
    if dialogue.next_expanded("kruber", "kruber") ~= nil then
        return "active dialogue group cannot collapse to nil"
    end
    if dialogue.next_expanded("bardin", "kruber") ~= "kruber" then
        return "dialogue group expansion did not select the requested speaker"
    end
    if dialogue.next_line_state(nil) ~= true
       or dialogue.next_line_state(true) ~= false
       or dialogue.next_line_state(false) ~= nil then
        return "dialogue line tri-state transition lost true, false, or nil"
    end
end)

_rt_register("issue630_dx12_fence_probe", function()
    local module = mod:dofile("scripts/mods/gui_tweaker_dev/_gut_dx12_fence630")
    if type(module) ~= "table" or type(module.new) ~= "function"
        or type(module.runtime_info) ~= "function" then
        return "#630 diagnostics module contract is unavailable"
    end
    local probe = mod._gut_dx12_fence630
    if type(probe) ~= "table" then return "#630 runtime probe was not installed" end
    for _, name in ipairs({ "enter", "before_draw", "after_draw", "leave", "snapshot" }) do
        if type(probe[name]) ~= "function" then
            return string.format("#630 runtime probe missing %s", name)
        end
    end
    local snapshot = probe:snapshot()
    if snapshot.line_cap ~= module.DEFAULT_LINE_CAP then
        return "#630 diagnostics line cap drifted"
    end
end)

_rt_register("mod_tweaker_esc_entry_hook", function()
    local logic_class = rawget(_G, "IngameViewLayoutLogic")
    if not logic_class then return "IngameViewLayoutLogic global not present" end
    if type(logic_class.setup_button_layout) ~= "function" then
        return "IngameViewLayoutLogic.setup_button_layout missing"
    end
    -- Build a fake instance and a layout_data with an Options-shaped entry,
    -- run setup_button_layout, then verify our entry was inserted above it.
    local fake = setmetatable({ _params = {} }, { __index = logic_class })
    local layout = {
        { display_name = "return_to_game_button_name", transition = "exit_menu" },
        { display_name = "options_menu_button_name",   transition = "options_menu" },
        { display_name = "quit_menu_button_name",      transition = "quit_game" },
    }
    local ok = pcall(logic_class.setup_button_layout, fake, layout)
    if not ok then return "setup_button_layout raised on probe layout" end
    local got = fake.active_button_data
    if type(got) ~= "table" then return "active_button_data not populated" end
    local mt_idx, opt_idx = nil, nil
    for i = 1, #got do
        if got[i].transition == "mod_tweaker_view" then mt_idx = i end
        if got[i].transition == "options_menu"     then opt_idx = i end
    end
    if not mt_idx then return "mod_tweaker entry not injected" end
    if not opt_idx then return "options entry vanished (engine change?)" end
    if mt_idx >= opt_idx then return string.format("mod_tweaker entry not above options (mt=%d, opt=%d)", mt_idx, opt_idx) end
end)

_rt_register("mod_tweaker_transition_registered", function()
    local settings = package.loaded["scripts/ui/views/ingame_ui_settings"]
    if not settings then return "ingame_ui_settings not in package.loaded" end
    if not settings.transitions then return "settings.transitions missing" end
    if type(settings.transitions.mod_tweaker_view) ~= "function" then
        return "transitions.mod_tweaker_view is not a function"
    end
    -- Smoke (IN-MISSION fallback, build 2): force is_in_inn=false and supply NO
    -- transition_with_fade so the closure takes the standalone-ModTweakerView branch.
    -- Pre-seed views.mod_tweaker_view so _attach_view short-circuits (idempotent
    -- early-return) without needing a real renderer; the closure must then set
    -- current_view. (The keep branch routes via transition_with_fade -> hero_view
    -- sub-state and is covered by mod_tweaker_substate_registered below.)
    local fake = {
        ingame_ui_context = { is_in_inn = false },
        views = { mod_tweaker_view = { _exit_transition = nil } },
    }
    settings.transitions.mod_tweaker_view(fake)
    if fake.current_view ~= "mod_tweaker_view" then
        return "in-mission transition did not set current_view = mod_tweaker_view"
    end

    -- ORIGIN-CAPTURE (v0.2.58-dev): the in-mission exit must return to whichever
    -- menu the player opened. The closure reads self.current_view (the engine's
    -- pre-closure origin snapshot) and routes "hero_view" origin -> "hero_view",
    -- everything else -> "ingame_menu". Assert both branches so a regression that
    -- re-hardcodes "ingame_menu" (the deprecated-bare-menu bug) is caught.
    local function _exit_for(origin)
        local f = {
            current_view = origin,
            ingame_ui_context = { is_in_inn = false },
            views = { mod_tweaker_view = { _exit_transition = nil } },
        }
        settings.transitions.mod_tweaker_view(f)
        return f.views.mod_tweaker_view._exit_transition
    end
    local et_hero = _exit_for("hero_view")
    if et_hero ~= "hero_view" then
        return string.format("hero_view origin did not set _exit_transition = hero_view (got %s)", tostring(et_hero))
    end
    local et_legacy = _exit_for("ingame_menu")
    if et_legacy ~= "ingame_menu" then
        return string.format("ingame_menu origin did not set _exit_transition = ingame_menu (got %s)", tostring(et_legacy))
    end

    -- KEEP branch (v0.2.60-dev): in the keep (is_in_inn ~= false) the closure must route
    -- to the hero_view sub-state via transition_with_fade WITH force_open = true and
    -- menu_state_name = "gut_mod_tweaker". Dropping force_open is the regression that made
    -- the ESC button darken-then-open-nothing (the keep ESC menu IS hero_view, so without
    -- force_open IngameUI.handle_transition skips the re-enter and menu_state_name is
    -- ignored). Capture the call to assert both params survive.
    if rawget(_G, "HeroViewStateModTweaker") then
        local captured
        local fake_keep = {
            ingame_ui_context = { is_in_inn = true },
            transition_with_fade = function(_self, transition, params)
                captured = { transition = transition, params = params or {} }
            end,
        }
        settings.transitions.mod_tweaker_view(fake_keep)
        if not captured then
            return "keep branch did not call transition_with_fade"
        end
        if captured.transition ~= "hero_view" then
            return string.format("keep branch transition not 'hero_view' (got %s)", tostring(captured.transition))
        end
        if captured.params.menu_state_name ~= "gut_mod_tweaker" then
            return string.format("keep branch menu_state_name not 'gut_mod_tweaker' (got %s)", tostring(captured.params.menu_state_name))
        end
        if captured.params.force_open ~= true then
            return "keep branch missing force_open = true (the darken-then-nothing regression)"
        end
    end
end)

-- Build 2: the Mod Tweaker KEEP sub-state must register exactly like the compendium —
-- the class global exists and the gut_mod_tweaker screen descriptor is appended in the
-- SINGLE HeroView.init hook (no duplicate hook). This marker mirrors the compendium's
-- registration invariant.
_rt_register("mod_tweaker_substate_registered", function()
    if not rawget(_G, "HeroViewStateModTweaker") then
        return "HeroViewStateModTweaker class global not defined (state dofile failed)"
    end
    local C = rawget(_G, "HeroViewStateModTweaker")
    for _, name in ipairs({ "on_enter", "update", "post_update", "on_exit",
                            "input_service", "close_menu" }) do
        if type(C[name]) ~= "function" then
            return string.format("HeroViewStateModTweaker:%s is not a function (got %s)",
                name, type(C[name]))
        end
    end
    if type(mod._gut_open_mod_tweaker) ~= "function" then
        return "mod._gut_open_mod_tweaker opener not defined (inject module didn't load)"
    end
    return nil
end)

_rt_register("mod_tweaker_api_present", function()
    local MT = mod.mod_tweaker
    if not MT then return "mod.mod_tweaker not set; install path failed" end
    for _, name in ipairs({ "register_category", "is_registered", "list_categories",
                            "get_category", "get", "set" }) do
        if type(MT[name]) ~= "function" then
            return string.format("mod.mod_tweaker:%s is not a function (got %s)",
                name, type(MT[name]))
        end
    end
    -- Smoke: register a throwaway category, read back, ensure idempotent rejection.
    local probe_id = "__mt_rt_probe__"
    -- Defensively scrub before registering — _rt_check may have been run already.
    local Settings = mod:dofile("scripts/mods/gui_tweaker_dev/_mod_tweaker_settings")
    if Settings and MT:is_registered(probe_id) then
        -- No public unregister yet; if the probe is still registered from a
        -- prior run, just re-use it (the api is supposed to be idempotent on
        -- this call shape and the smoke is still meaningful).
    else
        local ok = MT:register_category({
            mod_id = probe_id,
            label  = "rt probe",
            widgets = { { setting_id = "probe_flag", type = "checkbox", default = false } },
        })
        if not ok then return "register_category returned false on first call" end
    end
    if not MT:is_registered(probe_id) then return "is_registered() false after register" end
    MT:set(probe_id, "probe_flag", true)
    if MT:get(probe_id, "probe_flag") ~= true then return "get() did not reflect set()" end
end)

-- (#525) Register the engine-free tab-label policy's live check once.
do
    local labels = mod:dofile("scripts/mods/gui_tweaker_dev/_mod_tweaker_tab_labels")
    for _, c in ipairs(labels.rt_checks or {}) do _rt_register(c.name, c.fn) end
end

-- (#559) Search expansion is a transaction, not a write-through rendering shortcut. Exercise the
-- production pure helper in the live Lua 5.1 runtime and assert the view exposes every lifecycle
-- seam that begins, restores, and commits the transaction.
_rt_register("issue559_search_expansion_transaction", function()
    local ok_s, Search = pcall(mod.dofile, mod, "scripts/mods/gui_tweaker_dev/_mod_tweaker_search")
    if not ok_s or type(Search) ~= "table" then return "search transaction module unavailable" end
    for _, name in ipairs({ "begin", "restore", "commit", "finish", "group_keys", "ancestors" }) do
        if type(Search[name]) ~= "function" then return "Search." .. name .. " missing" end
    end

    local expanded = { old_outer = true, old_inner = true, foreign = true }
    local tx = Search.begin(expanded, { "old_outer", "old_inner", "result_outer" }, "probe")
    Search.commit(expanded, tx, { "result_outer" }, true)
    if expanded.old_outer or expanded.old_inner or not expanded.result_outer or not expanded.foreign then
        return "auto-collapse commit did not isolate the result ancestor chain"
    end

    expanded = { old_outer = true, old_inner = true, foreign = true }
    tx = Search.begin(expanded, { "old_outer", "old_inner", "result_outer" }, "probe")
    Search.commit(expanded, tx, { "result_outer" }, false)
    if not expanded.old_outer or not expanded.old_inner or not expanded.result_outer or not expanded.foreign then
        return "non-auto-collapse commit did not preserve snapshot plus result ancestors"
    end

    expanded = { old_outer = true, foreign = true }
    tx = Search.begin(expanded, { "old_outer", "top_outer", "changed_outer" }, "probe")
    Search.finish(expanded, tx, { "changed_outer" }, { "top_outer" }, true)
    if expanded.old_outer or expanded.top_outer or not expanded.changed_outer or not expanded.foreign then
        return "dismissal did not prefer the last changed result branch"
    end

    local ok_v, View = pcall(mod.dofile, mod, "scripts/mods/gui_tweaker_dev/_mod_tweaker_view")
    if not ok_v or type(View) ~= "table" then return "ModTweakerView unavailable" end
    for _, name in ipairs({ "_search_restore", "_search_clear_restore", "_search_finish",
                            "_search_note_setting" }) do
        if type(View[name]) ~= "function" then return "ModTweakerView:" .. name .. " missing" end
    end
end)

_rt_register("issue572_mod_tweaker_native_search_icon", function()
    local ok, defs = pcall(mod.dofile, mod, "scripts/mods/gui_tweaker_dev/_mod_tweaker_definitions")
    if not ok or type(defs) ~= "table" or type(defs.create_search_box) ~= "function" then
        return "Mod Tweaker search definitions unavailable"
    end
    local contract = defs.search_icon_contract
    if type(contract) ~= "table" or contract.texture ~= "search_filters_icon"
        or contract.source ~= "HeroWindowCraftingInventoryConsole"
        or contract.native_size ~= 128 or contract.size ~= 95
        or contract.previous_size ~= 112 or contract.scale_from_previous ~= (95 / 112)
        or contract.scale ~= 0.7421875 or contract.icon_x ~= -28 or contract.icon_y ~= -3
        or contract.native_icon_y ~= -4
        or contract.icon_y ~= math.floor((contract.native_icon_y * contract.size / contract.native_size) + 0.5)
        or contract.visible_left ~= 8 or contract.visible_right ~= 32 then
        return "inventory magnifier material/source contract drifted"
    end
    if type(defs.search_icon_visible) ~= "function"
        or not defs.search_icon_visible({ search_focused = false })
        or defs.search_icon_visible({ search_focused = true }) then
        return "search magnifier focus visibility contract drifted"
    end
    local built, widget = pcall(defs.create_search_box)
    if not built or type(widget) ~= "table" then
        return "search widget build failed: " .. tostring(widget)
    end
    if not widget.content or widget.content.search_icon ~= contract.texture then
        return "search widget does not bind the native inventory texture"
    end
    if widget.content.search_focused ~= false then
        return "search widget does not default to unfocused icon visibility"
    end
    local icon = widget.style and widget.style.search_icon
    local text = widget.style and widget.style.text
    if not icon or not icon.texture_size or icon.texture_size[1] ~= contract.size
        or icon.texture_size[2] ~= contract.size or icon.offset[1] ~= contract.icon_x
        or icon.offset[2] ~= contract.icon_y then
        return "search icon size/padding drifted"
    end
    if not text or not text.offset or text.offset[1] < contract.text_x then
        return "search text can overlap the magnifier"
    end
    local ok_v, View = pcall(mod.dofile, mod, "scripts/mods/gui_tweaker_dev/_mod_tweaker_view")
    if not ok_v or type(View) ~= "table" or type(View._search_placeholder) ~= "function"
        or View._search_placeholder({ _selected = 1, _tabs = { { content = { text = "PROGRESSION" } } } })
            ~= "Search PROGRESSION" then
        return "active-tab search placeholder drifted"
    end
    local hotspot = widget.style and widget.style.hotspot
    if not widget.content.hotspot or not hotspot or not hotspot.size
        or hotspot.size[1] ~= contract.hotspot_w or hotspot.size[2] ~= contract.hotspot_h
        or not hotspot.offset or hotspot.offset[1] ~= 0 or hotspot.offset[2] ~= 0 then
        return "search focus hotspot changed while adding passive icon"
    end
end)

-- (#446) Mutually-exclusive group API + enforcement wiring. Runtime-only (no source
-- read): registers a throwaway 2-member group, verifies the reverse membership lookup
-- resolves both members (and rejects a non-member + malformed shapes), and asserts the
-- view class exposes the _enforce_exclusive method the checkbox toggle handler calls to
-- sweep siblings. A regression that drops the registry surface or unwires enforcement
-- fails here.
_rt_register("mod_tweaker_exclusive_group_api", function()
    local MT = mod.mod_tweaker
    if not MT then return "mod.mod_tweaker not set" end
    for _, name in ipairs({ "register_exclusive_group", "get_exclusive_group_id",
        "get_exclusive_members", "get_exclusive_presentation" }) do
        if type(MT[name]) ~= "function" then
            return string.format("mod.mod_tweaker:%s is not a function (got %s)", name, type(MT[name]))
        end
    end
    local gid = "__mt_rt_excl__"
    local ok, err = MT:register_exclusive_group(gid, {
        { mod = "__mt_rt_a__", setting = "flag_a" },
        { mod = "__mt_rt_a__", setting = "flag_b" },
    }, { control = "radio", label = "RT group", none_label = "RT none" })
    if not ok then return "register_exclusive_group returned false: " .. tostring(err) end
    if MT:get_exclusive_group_id("__mt_rt_a__", "flag_a") ~= gid then return "member flag_a did not resolve to its group" end
    if MT:get_exclusive_group_id("__mt_rt_a__", "flag_b") ~= gid then return "member flag_b did not resolve to its group" end
    if MT:get_exclusive_group_id("__mt_rt_a__", "not_a_member") ~= nil then return "non-member resolved to a group" end
    local members = MT:get_exclusive_members(gid)
    if type(members) ~= "table" or #members ~= 2 then return "get_exclusive_members did not return the 2-member list" end
    local presentation = MT:get_exclusive_presentation(gid)
    if type(presentation) ~= "table" or presentation.control ~= "radio"
        or presentation.label ~= "RT group" or presentation.none_label ~= "RT none" then
        return "radio presentation metadata did not round-trip"
    end
    -- Reject shapes: empty id, single member.
    if MT:register_exclusive_group("", { { mod = "x", setting = "y" }, { mod = "x", setting = "z" } }) then
        return "empty group_id was not rejected"
    end
    if MT:register_exclusive_group("__mt_rt_solo__", { { mod = "x", setting = "y" } }) then
        return "single-member group was not rejected"
    end
    if MT:register_exclusive_group("__mt_rt_bad_radio__", {
        { mod = "x", setting = "y" }, { mod = "x", setting = "z" },
    }, { control = "radio" }) then
        return "radio presentation without label was not rejected"
    end
    -- Enforcement is wired: the standalone view class carries the sweep method.
    local ok_v, V = pcall(mod.dofile, mod, "scripts/mods/gui_tweaker_dev/_mod_tweaker_view")
    if not ok_v or type(V) ~= "table" or type(V._enforce_exclusive) ~= "function" then
        return "ModTweakerView:_enforce_exclusive missing (enforcement not wired)"
    end
    local ok_d, defs = pcall(mod.dofile, mod,
        "scripts/mods/gui_tweaker_dev/_mod_tweaker_definitions")
    if not ok_d or type(defs) ~= "table" or type(defs.create_radio) ~= "function" then
        return "Mod Tweaker radio-row factory missing"
    end
end)

-- (#505) Filtered/searchable dropdown API + view + defs wiring. Runtime-only (no source read):
-- registers throwaway categories (function form + key-list form), verifies the reverse lookup +
-- rejects malformed shapes, asserts the public API + the view's filter machinery + the defs popup
-- factory's header support are all present. A regression that drops the registry, unwires the
-- filter path, or reverts the header-capable create_dropdown_list fails here.
_rt_register("mod_tweaker_dropdown_filter_api", function()
    local MT = mod.mod_tweaker
    if not MT then return "mod.mod_tweaker not set" end
    for _, name in ipairs({ "register_dropdown_categories", "get_dropdown_categories" }) do
        if type(MT[name]) ~= "function" then
            return string.format("mod.mod_tweaker:%s is not a function (got %s)", name, type(MT[name]))
        end
    end
    local ok, err = MT:register_dropdown_categories("__mt_rt_dd__", "pick", {
        { label = "Even",  match = function(value) return (value % 2) == 0 end },
        { label = "Named", match = { "alpha", "beta" } },   -- key-list form
    })
    if not ok then return "register_dropdown_categories returned false: " .. tostring(err) end
    local cats = MT:get_dropdown_categories("__mt_rt_dd__", "pick")
    if type(cats) ~= "table" or #cats ~= 2 then return "get_dropdown_categories did not return the 2 categories" end
    if type(cats[1].match) ~= "function" or not cats[1].match(4) or cats[1].match(3) then
        return "function-form category match did not normalize correctly"
    end
    if type(cats[2].match) ~= "function" or not cats[2].match("beta") or cats[2].match("gamma") then
        return "key-list category match did not normalize to a membership predicate"
    end
    -- Reject shapes: missing setting_id, empty category list, label-less / matchless entry.
    if MT:register_dropdown_categories("__mt_rt_dd__", "", { { label = "x", match = {} } }) then
        return "empty setting_id was not rejected"
    end
    if MT:register_dropdown_categories("__mt_rt_dd__", "empty", {}) then
        return "empty category list was not rejected"
    end
    if MT:register_dropdown_categories("__mt_rt_dd__", "bad", { { match = function() return true end } }) then
        return "label-less category was not rejected"
    end
    -- View filter machinery is wired.
    local ok_v, V = pcall(mod.dofile, mod, "scripts/mods/gui_tweaker_dev/_mod_tweaker_view")
    if not ok_v or type(V) ~= "table" then return "could not load ModTweakerView" end
    for _, m in ipairs({ "_recompute_dd_visible", "_dd_chips", "_refresh_dropdown_list", "_handle_dropdown_input" }) do
        if type(V[m]) ~= "function" then return "ModTweakerView:" .. m .. " missing (filter path unwired)" end
    end
    -- The defs popup factory must accept a header spec and emit the search-line content id +
    -- chip hotspots. Build a probe popup with 2 chips and assert its shape.
    local ok_d, D = pcall(mod.dofile, mod, "scripts/mods/gui_tweaker_dev/_mod_tweaker_definitions")
    if not ok_d or type(D) ~= "table" or type(D.create_dropdown_list) ~= "function" then
        return "defs.create_dropdown_list missing"
    end
    local header = { query = "ab", chips = { { label = "All", active = true }, { label = "X", active = false } } }
    local ok_w, popup = pcall(D.create_dropdown_list, { "one", "two", "three" }, 1, -100, 1, header)
    if not ok_w or type(popup) ~= "table" then return "create_dropdown_list(header) errored" end
    if popup._dd_chip_count ~= 2 then return "header chips not built (chip_count ~= 2)" end
    if not (popup.content and popup.content.search_text ~= nil) then return "header search_text content missing" end
    if not (popup.content.chip_1 and popup.content.chip_2) then return "chip hotspots missing" end
    -- A plain (no-header) call still works and grows no header band.
    local ok_p, plain = pcall(D.create_dropdown_list, { "one", "two" }, 1, -100, 1)
    if not ok_p or type(plain) ~= "table" then return "create_dropdown_list(no header) errored" end
    if (plain._dd_header_h or 0) ~= 0 or (plain._dd_chip_count or 0) ~= 0 then
        return "plain dropdown grew a header band (backward-compat broken)"
    end
end)

-- v0.2.59-dev — the gear "Advanced Settings" drill-down + the slider thumb-move fix.
-- (1) The defs module must export the gear + back-row factories, and a built gear must
--     carry a hotspot pass WITH an explicit style.hotspot (rows share the mt_list_start
--     node, so a missing style collapses the hit target to 1x1).
-- (2) The slider must drive its thumb/fill via a `local_offset` pass — the ONLY pass
--     type the engine invokes `offset_function` for (ui_passes.lua:4587). A regression
--     that re-attaches offset_function to a texture/rect pass (where it's ignored, the
--     build-3 "thumb doesn't move" bug) would have NO local_offset pass and is caught here.
_rt_register("mod_tweaker_gear_and_slider", function()
    local defs = mod:dofile("scripts/mods/gui_tweaker_dev/_mod_tweaker_definitions")
    if type(defs.create_gear_button) ~= "function" then return "create_gear_button factory missing" end
    if type(defs.create_back_row) ~= "function" then return "create_back_row factory missing" end

    local gear = defs.create_gear_button(-46)
    if type(gear) ~= "table" then return "create_gear_button did not return a widget" end
    local g_has_hotspot, g_styled = false, false
    for _, p in ipairs(gear.element.passes) do
        if p.pass_type == "hotspot" then g_has_hotspot = true; if p.style_id then g_styled = true end end
    end
    if not g_has_hotspot then return "gear widget has no hotspot pass" end
    if not g_styled then return "gear hotspot lacks style_id (hit target would collapse to 1x1)" end
    if not (gear.style and gear.style.hotspot and gear.style.hotspot.size) then
        return "gear hotspot has no explicit style.hotspot.size"
    end

    -- A slider must contain a local_offset pass carrying an offset_function.
    local base = { 0, -10, 0 }
    local slider = defs.create_slider("rt probe", "", base)
    local has_local_offset = false
    for _, p in ipairs(slider.element.passes) do
        if p.pass_type == "local_offset" and type(p.offset_function) == "function" then
            has_local_offset = true
        end
    end
    if not has_local_offset then
        return "slider has no local_offset pass with offset_function (thumb/fill would not move)"
    end
end)

-- #575: caret placement is measured geometry, not character-count or fixed-pixel
-- approximation. Engine-facing defs must expose the exact-metric helpers; the
-- pure module locks centered glyph-origin and proportional-boundary behavior.
_rt_register("mod_tweaker_numeric_caret_geometry", function()
    local defs = mod:dofile("scripts/mods/gui_tweaker_dev/_mod_tweaker_definitions")
    if type(defs.numeric_caret_x) ~= "function" then return "numeric_caret_x missing" end
    if type(defs.numeric_caret_index) ~= "function" then return "numeric_caret_index missing" end
    local N = mod:dofile("scripts/mods/gui_tweaker_dev/_mod_tweaker_numeric_editor")
    if N.caret_x(100, 50, 20, 2, 7) ~= 120 then
        return "centered origin/prefix caret contract drifted"
    end
    local advances = { 0, 5, 12, 19, 22, 29, 36 }
    if N.nearest_index(60.6, 40, advances) ~= 4 then
        return "proportional sign/decimal click boundary drifted"
    end
end)

-- (#164) Mod Tweaker per-setting slider STEP: the resolver's precedence (widget-def `step`
-- field > gut STEP_OVERRIDES registry > natural 1/10^-decimals) and the grid-snap math
-- (anchored at RANGE MIN, clamped to range). The two seeded consumers are ct starting_coins
-- and cim base_power_level, both step 25 via the registry (VMF strips a custom `step` field
-- off a foreign mod's widget, so the registry is the working path — see _resolve_step /
-- STEP_OVERRIDES comments). Chest-of-Trials cost joins those consumers for #826. Guards
-- against a regression that reverts the registry keys to
-- directory names (which silently never match) or drops the min-anchoring.
_rt_register("mod_tweaker_arrow_edge_latch_hold_repeat", function()
    -- (#152) Mod Tweaker slider arrows: a single click = ONE natural increment, EDGE-LATCHED
    -- (one step per physical press, no auto-move on press), and a HELD arrow repeats after a
    -- delay and ACCELERATES - matching the vanilla options slider. Guard the accelerating
    -- hold-repeat by source-pattern on _mod_tweaker_view.lua (path via View._resolve_step).
    -- Split needle so this line can't self-match. No-op if the source is unreadable.
    local ok_view, View = pcall(mod.dofile, mod, "scripts/mods/gui_tweaker_dev/_mod_tweaker_view")
    if not ok_view or type(View) ~= "table" or type(View._resolve_step) ~= "function" then return end
    local ok, info = pcall(debug.getinfo, View._resolve_step, "S")
    if not ok or type(info) ~= "table" or not info.source then return end
    local src_path = info.source:sub(1, 1) == "@" and info.source:sub(2) or info.source
    local txt = _rt_src_read(src_path)  -- (#511) io-safe; nil in retail sandbox => skip
    if not txt then return end
    local hold_needle = "row._arrow_hnext = row._arrow" .. "_hf + math.max(2,"
    if not txt:find(hold_needle, 1, true) then
        return "#152 REGRESSION: the accelerating arrow hold-repeat is gone (Mod Tweaker slider arrows over-adjust / auto-move on press again)"
    end
end)

_rt_register("mod_tweaker_step_resolution", function()
    local ok_view, View = pcall(mod.dofile, mod, "scripts/mods/gui_tweaker_dev/_mod_tweaker_view")
    if not ok_view or type(View) ~= "table" then return "view module unavailable" end
    local resolve, snap = View._resolve_step, View._snap_and_clamp
    if type(resolve) ~= "function" then return "_resolve_step not exposed on the view module" end
    if type(snap) ~= "function" then return "_snap_and_clamp not exposed on the view module" end

    -- (1) Precedence: an explicit widget-def `step` field wins over the registry.
    if resolve({ step = 10 }, "ct_dev", "starting_coins", 0) ~= 10 then
        return "widget-def `step` field did not take precedence over the registry"
    end
    -- (2) Registry hit for every seeded consumer, on stable AND dev ids (by new_mod id).
    for _, case in ipairs({ { "ct", "starting_coins" }, { "ct_dev", "starting_coins" },
                            { "ct", "cot_cost_amount" }, { "ct_dev", "cot_cost_amount" },
                            { "cim", "base_power_level" }, { "cim_dev", "base_power_level" } }) do
        local got = resolve({}, case[1], case[2], 0)
        if got ~= 25 then
            return string.format("registry %s:%s resolved step=%s (want 25) -- key regressed to a directory name?",
                case[1], case[2], tostring(got))
        end
    end
    -- (3) Default: no field, no registry -> natural unit (1 for ints, 10^-decimals otherwise).
    if resolve({}, "some_other_mod", "some_setting", 0) ~= 1 then return "int default step is not 1" end
    if math.abs(resolve({}, "some_other_mod", "x", 2) - 0.01) > 1e-9 then return "2-decimal default step is not 0.01" end

    -- (4) Snap is anchored at RANGE MIN (not 0) and clamps to range. min=10,step=25: 20 rounds
    -- toward 10 (|20-10|/25 < 0.5), NOT to 25 (which is what a 0-anchored snap would give).
    if snap({ min = 10, max = 200, step = 25, num_decimals = 0 }, 20) ~= 10 then
        return "snap not anchored at range min (min=10,step=25,value=20 should snap to 10)"
    end
    -- 324 with min=0,step=25 -> nearest grid multiple 325 (this is the "then snap" on move;
    -- the pre-existing 324 shows as-is at build time, only snapping once the user moves it).
    if snap({ min = 0, max = 3000, step = 25, num_decimals = 0 }, 324) ~= 325 then
        return "snap(324) with step 25 did not land on 325"
    end
    -- Clamp to range.
    if snap({ min = 0, max = 100, step = 25, num_decimals = 0 }, 999) ~= 100 then
        return "snap did not clamp to range max"
    end
end)

-- (#95) Keybind / table read-only values must route through _format_keybind_value
-- in _mod_tweaker_view.lua, NOT tostring(), or a VMF keybind (a Lua TABLE like
-- {"left alt"}) renders its raw address ("CYCLE HUD MODE: table: 0x..."). Source
-- guard: read the VIEW file (anchored via debug.getinfo on a ModTweakerView method)
-- and assert BOTH (a) the formatter helper is present and (b) the read-only branch
-- routes keybind/table values through it. Needles are split across two literals so
-- this test's own source can't self-match. Degrades to a no-op when source
-- introspection is unavailable (deploy/bundle paths ship no readable .lua).
_rt_register("mod_tweaker_keybind_render", function()
    local ok_view, View = pcall(mod.dofile, mod, "scripts/mods/gui_tweaker_dev/_mod_tweaker_view")
    if not ok_view or type(View) ~= "table" or type(View._handle_input) ~= "function" then
        return  -- can't reach the view module; skip
    end
    local ok, info = pcall(debug.getinfo, View._handle_input, "S")
    if not ok or type(info) ~= "table" or not info.source then return end
    local src_path = info.source:sub(1, 1) == "@" and info.source:sub(2) or info.source
    local txt = _rt_src_read(src_path)  -- (#511) io-safe; nil in retail sandbox => skip
    if not txt then return end
    -- (a) the formatter helper must exist.
    local helper_needle = "_format_keybind" .. "_value"
    if not txt:find(helper_needle, 1, true) then
        return "#95 regression: _format_keybind_value is absent from _mod_tweaker_view.lua (keybinds would render a raw table address)"
    end
    -- (b) the read-only branch must route wtype=="keybind" OR a table value through it.
    local branch_needle = 'wtype == "keybind" or type(val)' .. ' == "table"'
    if not txt:find(branch_needle, 1, true) then
        return "#95 regression: read-only row no longer routes keybind/table values through _format_keybind_value (raw 'table: 0x...' would reach the label)"
    end
    local routed_needle = ': " .. _format_keybind' .. "_value(val)"
    if not txt:find(routed_needle, 1, true) then
        return "#95 regression: the keybind/table branch does not call _format_keybind_value(val)"
    end
end)

-- (issue 631) Mouse buttons 1-5 must be capturable as keybind primaries. The Mod Tweaker's
-- keybind capture (_poll_keybind_combo) originally polled only Keyboard, so mouse binds could
-- never be set even though VMF dispatch already resolves "mouse *" key-ids. Source guard on
-- _mod_tweaker_view.lua: the VMF-vocabulary mouse map must be present, the poll must read
-- Mouse.button, and the caller must DEFER the commit (release-committed, so Mouse 1/2 can't
-- self-trigger the enter/clear hotspots). Split needles avoid self-match; no-op when source
-- unreadable (retail io sandbox, #511).
_rt_register("issue631_keybind_mouse_capture", function()
    local ok_view, View = pcall(mod.dofile, mod, "scripts/mods/gui_tweaker_dev/_mod_tweaker_view")
    if not ok_view or type(View) ~= "table" or type(View._handle_input) ~= "function" then
        return  -- can't reach the view module; skip
    end
    local ok, info = pcall(debug.getinfo, View._handle_input, "S")
    if not ok or type(info) ~= "table" or not info.source then return end
    local src_path = info.source:sub(1, 1) == "@" and info.source:sub(2) or info.source
    local txt = _rt_src_read(src_path)  -- (#511) io-safe; nil in retail sandbox => skip
    if not txt then return end
    -- (a) the VMF-vocabulary mouse key-id map must exist (dispatch resolves these names).
    if not txt:find("_MOUSE" .. "_KEYID", 1, true) then
        return "issue 631 regression: _MOUSE_KEYID map is absent (mouse binds would not capture)"
    end
    if not txt:find("mouse extra 1", 1, true) then
        return "issue 631 regression: VMF mouse key-id 'mouse extra 1' missing from the mouse map"
    end
    -- (b) the capture poll must actually read the mouse device.
    if not txt:find("Mouse" .. ".button, idx", 1, true) then
        return "issue 631 regression: _poll_keybind_combo no longer polls Mouse.button (keyboard-only capture)"
    end
    -- (c) mouse binds must be RELEASE-committed via the deferred-hold field, else the entering
    -- left-click self-binds Mouse 1 / the release wipes Mouse 2 through the clear branch.
    if not txt:find("_kb_mouse" .. "_pending", 1, true) then
        return "issue 631 regression: deferred mouse commit (_kb_mouse_pending) is gone (Mouse 1/2 would misfire)"
    end
end)

-- (#91) Scrollbar thumb drag must use a GRAB-OFFSET anchor (the cursor-Y at grab +
-- the scroll_value at grab), then track the cursor DELTA over the thumb's travel —
-- NOT the old absolute-position snap that jumped the thumb top to the cursor.
-- Source guard on _mod_tweaker_view.lua's _handle_input: assert both grab-anchor
-- fields survive. Split needles to avoid self-match; no-op when source unreadable.
_rt_register("mod_tweaker_scrollbar_grab_offset", function()
    local ok_view, View = pcall(mod.dofile, mod, "scripts/mods/gui_tweaker_dev/_mod_tweaker_view")
    if not ok_view or type(View) ~= "table" or type(View._handle_input) ~= "function" then
        return
    end
    local ok, info = pcall(debug.getinfo, View._handle_input, "S")
    if not ok or type(info) ~= "table" or not info.source then return end
    local src_path = info.source:sub(1, 1) == "@" and info.source:sub(2) or info.source
    local txt = _rt_src_read(src_path)  -- (#511) io-safe; nil in retail sandbox => skip
    if not txt then return end
    local cursor_anchor = "_sb_grab_cursor" .. "_y"
    local scroll_anchor = "_sb_grab_scroll" .. "_value"
    if not txt:find(cursor_anchor, 1, true) or not txt:find(scroll_anchor, 1, true) then
        return "#91 regression: scrollbar thumb drag no longer records a grab-offset anchor (reverted to absolute-position snapping — grabbing the thumb jumps it)"
    end
end)

-- (#92 corrected) The stepper/slider arrow glow must match the VANILLA GAME SETTINGS
-- menu (create_stepper_widget, options_view_definitions.lua:3054), NOT VMF. Native draws
-- TWO sprites per arrow: a base `settings_arrow_normal` at FULL alpha (font_default,255 —
-- :3415/:3457) that is NEVER dimmed at idle, plus a separate `settings_arrow_clicked`
-- OVERLAY seeded color {0,255,255,255} = alpha 0 (:3428-3433/:3470-3475) that fades up to
-- 255 on hover (OptionsView.on_stepper_arrow_hover, options_view.lua:4335-4369). The glow
-- is the _clicked overlay APPEARING, not an alpha ramp on the base. Table-introspection of
-- a built slider (which calls _append_arrows) asserts: (a) the base arrows draw
-- settings_arrow_normal at FULL alpha 255 (NOT dim); (b) the _clicked hover OVERLAYS exist
-- drawing settings_arrow_clicked seeded at alpha 0; (c) a local_offset pass with an
-- offset_function drives the overlay alpha 0->255.
_rt_register("mod_tweaker_arrow_hover_glow", function()
    local defs = mod:dofile("scripts/mods/gui_tweaker_dev/_mod_tweaker_definitions")
    if type(defs.create_slider) ~= "function" then return "create_slider factory missing" end
    local base = { 0, -10, 0 }
    local slider = defs.create_slider("rt probe", "", base)
    if type(slider) ~= "table" or not (slider.element and slider.element.passes) then
        return "create_slider did not return a renderable widget"
    end
    -- (a) base arrows draw settings_arrow_normal at FULL alpha (idle must NOT be dimmed —
    -- native :3415/:3457 are font_default,255).
    local la = slider.content and slider.content.left_arrow
    if not (la and la.texture_id == "settings_arrow_normal") then
        return "#92 regression: base left arrow no longer draws settings_arrow_normal"
    end
    local las = slider.style and slider.style.left_arrow
    if not (las and las.color and las.color[1] == 255) then
        return "#92 regression: base arrow not at FULL idle alpha 255 (vanilla draws the idle sprite full; a dimmed idle is the wrong-menu VMF ramp)"
    end
    -- (b) the _clicked hover OVERLAYS must exist, drawing settings_arrow_clicked seeded at
    -- alpha 0 (native left_arrow_hover/right_arrow_hover color {0,...}).
    local lah = slider.content and slider.content.left_arrow_hover
    if not (lah and lah.texture_id == "settings_arrow_clicked") then
        return "#92 regression: missing _clicked hover overlay (vanilla glow = settings_arrow_clicked overlay fading in over the base)"
    end
    local lahs = slider.style and slider.style.left_arrow_hover
    if not (lahs and lahs.color and lahs.color[1] == 0) then
        return "#92 regression: _clicked hover overlay not seeded at alpha 0 (native seed {0,255,255,255}; it ramps to 255 on hover)"
    end
    -- (c) a local_offset pass with an offset_function must drive the overlay alpha ramp
    -- (only a local_offset pass's offset_function runs each frame).
    local has_local_offset = false
    for _, p in ipairs(slider.element.passes) do
        if p.pass_type == "local_offset" and type(p.offset_function) == "function" then
            has_local_offset = true
        end
    end
    if not has_local_offset then
        return "#92 regression: no local_offset pass with an offset_function — the _clicked overlay alpha ramp cannot run"
    end
end)

-- (#92 corrected) The COLLAPSED dropdown arrow must match the VANILLA GAME SETTINGS
-- dropdown (create_drop_down_widget, options_view_definitions.lua:2299): a visible arrow
-- in BOTH states (down sprite when closed, up-flip when open — it never disappears), with
-- the brighter drop_down_menu_arrow_clicked glow sprite layering on hover/open. Asserts:
-- (a) base arrow_down + arrow_up passes both exist and are gated on content.active so one
-- is ALWAYS drawn; (b) an arrow_glow pass draws drop_down_menu_arrow_clicked; (c) the base
-- arrows are at FULL alpha (never gated to a blank/dimmed open state).
_rt_register("mod_tweaker_dropdown_arrow_glow", function()
    local defs = mod:dofile("scripts/mods/gui_tweaker_dev/_mod_tweaker_definitions")
    if type(defs.create_dropdown) ~= "function" then return "create_dropdown factory missing" end
    local dd = defs.create_dropdown("rt probe dd", { 0, -10, 0 }, 0)
    if type(dd) ~= "table" or not (dd.element and dd.element.passes) then
        return "create_dropdown did not return a renderable widget"
    end
    -- (a) both base arrows present; one drawn when closed, one when open -> never blank.
    local has_down, has_up, has_glow = false, false, false
    local down_check, up_check = nil, nil
    for _, p in ipairs(dd.element.passes) do
        if p.style_id == "arrow_down" then has_down = true; down_check = p.content_check_function end
        if p.style_id == "arrow_up"   then has_up   = true; up_check   = p.content_check_function end
        if p.style_id == "arrow_glow" then has_glow = true end
    end
    if not (has_down and has_up) then
        return "#92 regression: dropdown missing a base down/up arrow pass (the arrow must stay visible when open — never gate the only arrow off active)"
    end
    -- The closed pass shows when NOT active, the open pass shows when active -> exactly one
    -- base arrow is always drawn, so opening can never blank the arrow.
    if not (down_check and up_check and down_check({ active = false }) and up_check({ active = true })
            and not down_check({ active = true }) and not up_check({ active = false })) then
        return "#92 regression: dropdown arrow gating wrong (closed must draw the down arrow, open the up arrow — the open state must not be blank)"
    end
    -- (b) the _clicked glow sprite overlay exists (drop_down_menu_arrow_clicked).
    local glowc = dd.content and dd.content.arrow_glow
    if not (has_glow and glowc and glowc.texture_id == "drop_down_menu_arrow_clicked") then
        return "#92 regression: dropdown missing the drop_down_menu_arrow_clicked glow overlay (native hover/open glow sprite)"
    end
    -- (c) base arrows at FULL alpha in both states (native style.arrow color = font_default,255).
    local ad, au = dd.style and dd.style.arrow_down, dd.style and dd.style.arrow_up
    if not (ad and ad.color and ad.color[1] == 255 and au and au.color and au.color[1] == 255) then
        return "#92 regression: dropdown base arrows not at FULL alpha (native arrow is font_default,255 closed AND open; a dim/0 open arrow is the disappearing-arrow defect)"
    end
end)

-- (#93) Compact-ESC menu compaction is now an UNCONDITIONAL implicit feature — the
-- gut_compact_esc_menu TOGGLE + setting were removed (2026-06-24) and the
-- HeroWindowIngameView._update_presentation hook always runs (no-op below the
-- overflow threshold). This guard FAILS if a real setting-READ for that toggle is
-- reintroduced (gating the feature again). It checks the setting-read shape, not the
-- bare string, so the explanatory comment naming the removed toggle does not trip it.
-- Anchored on mod.on_setting_changed (a `mod.` field in the MAIN file). Split needle;
-- no-op when source unreadable.
_rt_register("mod_tweaker_compact_esc_implicit", function()
    local ok, info = pcall(debug.getinfo, mod.on_setting_changed or function() end, "S")
    if not ok or type(info) ~= "table" or not info.source then return end
    local src_path = info.source:sub(1, 1) == "@" and info.source:sub(2) or info.source
    local txt = _rt_src_read(src_path)  -- (#511) io-safe; nil in retail sandbox => skip
    if not txt then return end
    -- A reintroduced gate would read the setting via mod:get(...) on that toggle id.
    -- (The read-shape needle is assembled below from two literals so this very line
    -- and the comment naming the removed toggle can't make the test self-match.)
    local read_needle = 'mod:get("gut_compact_esc' .. '_menu")'
    if txt:find(read_needle, 1, true) then
        return "#93 regression: the gut_compact_esc_menu setting/toggle was reintroduced (the ESC-menu compaction must run unconditionally now)"
    end
end)

-- Bench-in-mission option moved from cim (2026-07-02, user direction): gut owns the
-- widget (cim-gated in _data.lua) and must write through to cim's `allow_in_mission`
-- setting, both on change and at load. Source-pattern guard on both halves; no-op
-- when source unreadable. Split needles so this check never self-matches.
_rt_register("cim_bench_write_through_present", function()
    local ok, info = pcall(debug.getinfo, mod.on_setting_changed or function() end, "S")
    if not ok or type(info) ~= "table" or not info.source then return end
    local src_path = info.source:sub(1, 1) == "@" and info.source:sub(2) or info.source
    local read_all = _rt_src_read  -- (#511) io-safe; nil in retail sandbox => skip
    local main_txt = read_all(src_path)
    if main_txt then
        local wt_needle = 'cim:set("allow_in_' .. 'mission"'
        local n_hits = select(2, main_txt:gsub(wt_needle:gsub("%p", "%%%0"), ""))
        if n_hits < 2 then
            return "cim-bench regression: expected the allow_in_mission write-through in BOTH on_setting_changed and on_all_mods_loaded (found " .. tostring(n_hits) .. ")"
        end
    end
    local dir = src_path:match("^(.*[/\\])[^/\\]*$")
    if dir then
        local data_txt = read_all(dir .. "gui_tweaker_dev_data.lua")
        if data_txt and not data_txt:find('setting_id    = "gut_cim_bench' .. '_in_mission"', 1, true) then
            return "cim-bench regression: gut_cim_bench_in_mission widget missing from gut's In-Mission Menus"
        end
    end
end)

-- (#80) The in-mission Crafting TAB must be gated on gut's OWN
-- gut_cim_bench_in_mission toggle + cim presence (not a bare cim-presence check),
-- and tb[3].disable_button must be driven by that result BOTH ways. Source-pattern
-- guard on _gut_mission_inventory.lua (located via mod.gut_open_mission_inventory,
-- defined there). Split needles so this check can't self-match. No-op if unreadable.
_rt_register("crafting_tab_honors_bench_toggle", function()
    local ok, info = pcall(debug.getinfo, mod.gut_open_mission_inventory or function() end, "S")
    if not ok or type(info) ~= "table" or not info.source then return end
    local src_path = info.source:sub(1, 1) == "@" and info.source:sub(2) or info.source
    local txt = _rt_src_read(src_path)  -- (#511) io-safe; nil in retail sandbox => skip
    if not txt then return end
    local gate_needle = 'mod:get("gut_cim_bench' .. '_in_mission")'
    local tab_needle  = "tb[3].content.button_hotspot.disable" .. "_button = not bench_ok"
    if not txt:find(gate_needle, 1, true) then
        return "#80 regression: the in-mission Crafting tab no longer reads gut_cim_bench_in_mission (bench toggle stopped gating the tab)"
    end
    if not txt:find(tab_needle, 1, true) then
        return "#80 regression: the Crafting tab (tb[3]) disable_button is no longer driven by bench_ok"
    end
end)

-- (#363/#80) In-mission Salvage/Crafting page store-atlas injection. The vanilla
-- Salvage craft page draws its auto-fill rarity buttons (store_tag_icon_weapon_*) out
-- of gui_store_menu_atlas, which lives in materials/ui/ui_1080p_store_menu -- a
-- keep-only (ui_materials_in_inn) resource, so in a mission the ingame renderer lacks it
-- and the draw takes an uncatchable "Material not found in Gui" C-fatal
-- (ui_passes.lua:194). The store package IS resident in-mission (dlcs/store force-loaded
-- at boot), so _gut_gui_material_guard.lua injects it into ingame ui/ui_top renderers
-- when can_get confirms residency (mirrors the pose-atlas #155 injection). This guard
-- FAILS if any of the three load-bearing pieces (STORE_MAT declaration, the append_store
-- residency gate, the token append into the Gui material list) is removed -- the Salvage
-- page would crash in-mission again. The guard file has no addressable mod.* function
-- (it's an anonymous UIRenderer.create hook + `return {}`), so locate it as a sibling of
-- _gut_mission_inventory.lua (via mod.gut_open_mission_inventory) in the same dir. Split
-- needles so this check can't self-match. No-op when source unreadable.
_rt_register("salvage_store_atlas_injected", function()
    local ok, info = pcall(debug.getinfo, mod.gut_open_mission_inventory or function() end, "S")
    if not ok or type(info) ~= "table" or not info.source then return end
    local src_path = info.source:sub(1, 1) == "@" and info.source:sub(2) or info.source
    local dir = src_path:match("^(.*[/\\])[^/\\]*$")
    if not dir then return end
    local txt = _rt_src_read(dir .. "_gut_gui_material_guard.lua")  -- (#511) io-safe; nil in retail => skip
    if not txt then return end
    local decl_needle   = "STORE" .. '_MAT = "materials/ui/ui_1080p_store_menu"'
    local gate_needle   = "if append" .. "_store then"
    local append_needle = "out[oi] = STORE" .. "_MAT"
    if not txt:find(decl_needle, 1, true) then
        return "#363 regression: the store-atlas material path (materials/ui/ui_1080p_store_menu) is gone from the GUI guard"
    end
    if not txt:find(gate_needle, 1, true) then
        return "#363 regression: the append_store residency gate is gone -- store atlas no longer injected into ingame renderers (Salvage page would C-fatal in-mission)"
    end
    if not txt:find(append_needle, 1, true) then
        return "#363 regression: the store-atlas token is no longer appended to the ingame Gui material list (Salvage-page tag icons can't draw in-mission)"
    end
end)

-- (2026-07-02) The Compendium (Armory + Bestiary) must open + work mid-mission with
-- NO keep gate: the is_in_inn keep-block is gone from mod._gut_open_compendium, and
-- the tab-state pass no longer greys the compendium tabs out of the keep. Source-
-- pattern guard on _ba_heroview_inject.lua (via mod._gut_open_compendium) + its
-- sibling _ba_compendium_tabs.lua. Split needles so this check can't self-match.
_rt_register("compendium_mission_access_ungated", function()
    local ok, info = pcall(debug.getinfo, mod._gut_open_compendium or function() end, "S")
    if not ok or type(info) ~= "table" or not info.source then return end
    local inject_path = info.source:sub(1, 1) == "@" and info.source:sub(2) or info.source
    local read_all = _rt_src_read  -- (#511) io-safe; nil in retail sandbox => skip
    local inject_txt = read_all(inject_path)
    if inject_txt then
        -- The compendium-specific keep echo is gone (the Mod Tweaker path keeps its
        -- own distinct message, so this needle is specific to the compendium).
        local keepgate_needle = "The Compendium only opens in the " .. "keep/inn."
        if inject_txt:find(keepgate_needle, 1, true) then
            return "compendium regression: the is_in_inn keep-gate was reintroduced in _gut_open_compendium (mid-mission open blocked again)"
        end
    end
    local tabs_path = inject_path:gsub("_ba_heroview_inject%.lua$", "_ba_compendium_tabs.lua")
    if tabs_path ~= inject_path then
        local tabs_txt = read_all(tabs_path)
        if tabs_txt then
            local grey_needle = "disable_button = not in" .. "_keep"
            if tabs_txt:find(grey_needle, 1, true) then
                return "compendium regression: _apply_tab_state greys the compendium tabs out of the keep again (mid-mission tabs disabled)"
            end
        end
    end
end)

-- (#155/#172) In-mission Cosmetics split: the TAB is vanilla UI (enabled unconditionally,
-- pose items filtered when the atlas isn't resident so no gui_pose_items_atlas C-fatal), the
-- gear-icon customize is gated on cosmetics_tweaker specifically. Source-pattern guard on
-- _gut_mission_inventory.lua (via mod.gut_open_mission_inventory). Split needles so this check
-- can't self-match. No-op if unreadable.
_rt_register("cosmetics_split_tab_ungated_gear_gated", function()
    local ok, info = pcall(debug.getinfo, mod.gut_open_mission_inventory or function() end, "S")
    if not ok or type(info) ~= "table" or not info.source then return end
    local src_path = info.source:sub(1, 1) == "@" and info.source:sub(2) or info.source
    local txt = _rt_src_read(src_path)  -- (#511) io-safe; nil in retail sandbox => skip
    if not txt then return end
    -- (a) Cosmetics tab (tb[4]) enabled unconditionally mid-mission.
    local tab_needle = "tb[4].content.button_hotspot.disable" .. "_button = false"
    if not txt:find(tab_needle, 1, true) then
        return "#172 regression: the in-mission Cosmetics tab (tb[4]) is no longer enabled unconditionally"
    end
    -- (a) Pose items filtered from the grid when the atlas isn't resident.
    local filter_needle = "slot.type == _POSE" .. "_SLOT_TYPE"
    if not txt:find(filter_needle, 1, true) then
        return "#155 regression: the pose-item grid filter (_equip_item_presentation) is gone -- gui_pose_items_atlas C-fatal could return"
    end
    -- (b) Gear-icon customize gated on cosmetics_tweaker specifically (NOT cim).
    local gate_needle = 'return in_keep or (get_mod("cosmetics' .. '_tweaker") ~= nil)'
    if not txt:find(gate_needle, 1, true) then
        return "#172 regression: the gear-icon customize gate is no longer keyed on cosmetics_tweaker specifically"
    end
end)

_rt_register("issue89_cosmetics_only_customize_mount", function()
    -- #89's original implementation plan said Cosmetics had to copy CIM's two
    -- mount hooks before GUT could permit the gear icon. #84 superseded that
    -- architecture: GUT owns the only mid-mission entry and now owns the two
    -- level-free mount hooks itself, while Cosmetics owns the render/apply path.
    -- Assert the live cross-mod contract directly; no retail source I/O.
    if type(mod._gut89_customize_allowed) ~= "function" then
        return "#89 customize policy missing"
    end
    if type(mod._gut89_mount_fix_active) ~= "function" then
        return "#89 mount policy missing"
    end
    local surfaces = mod._gut89_mount_surfaces
    if type(surfaces) ~= "table"
        or surfaces.create_item_preview_widget_definition ~= true
        or surfaces.register_object_sets ~= true
    then
        return "#89 level-free mount sender surfaces incomplete"
    end

    local in_keep = rawget(_G, "DamageUtils") and DamageUtils.is_in_inn or false
    if not in_keep then
        local has_cosmetics = get_mod("cosmetics_tweaker") ~= nil
        if has_cosmetics and mod._gut89_customize_allowed() ~= true then
            return "#89 Cosmetics present but in-mission gear icon remains blocked"
        end
        local has_cim = get_mod("cim_dev") ~= nil or get_mod("cim") ~= nil
        if not has_cim and mod._gut89_mount_fix_active() ~= true then
            return "#89 no-CIM mission path did not activate GUT's level-free mount"
        end
    end
end)

    return true
end

return M
