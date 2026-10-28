-- _gut_mod_tweaker_shell.lua -- closed native Mod Tweaker menu shell.
-- Owned by: gui_tweaker_dev.lua's ordered three-phase menu handoff.
-- Consumed via: one inert entry load and private captured collaborators in bind.
-- No module loads, lifecycle ownership, new public fields, or renderer policy here.
local M = {}

function M.bind(config)
    local mod = config.mod
    local _dbg = config.dbg
    local _dbg_alert = config.dbg_alert
    local _rt_register = config.register
    local load_view = config.load_view
    local load_localization = config.load_localization
    local get_la_keepalive = config.get_la_keepalive

    local function install_api(ok_mt, ModTweaker)
        -- ============================================================
        -- Mod Tweaker (v0.1 scaffold) -- replacement settings menu surface
        -- exposed at `get_mod("gut_dev").mod_tweaker`. v0.1 just stands up the API
        -- and registry; the ESC entry, view rendering, and widget factories
        -- arrive in follow-up tasks. Authors detect with:
        --   local gut = get_mod("gut_dev")
        --   if gut and gut.mod_tweaker then
        --       gut.mod_tweaker:register_category({ mod_id = "...", label = "...", widgets = {...} })
        --   end
        -- ============================================================

        if ok_mt and type(ModTweaker) == "table" then
            local ok_install, install_err = pcall(ModTweaker.install, _dbg, _dbg_alert)
            if ok_install then
                mod.mod_tweaker = ModTweaker
                _dbg("[gui_tweaker] mod_tweaker: installed (api version v0.1)")
            else
                _dbg_alert("[gui_tweaker] mod_tweaker install failed: %s", tostring(install_err))
            end
        else
            _dbg_alert("[gui_tweaker] mod_tweaker dofile failed: %s", tostring(ModTweaker))
        end

        -- Dogfood category so the view renders real content (and proves the end-to-end:
        -- open -> change -> persist -> on_change). gut's own demo settings live in the
        -- Mod Tweaker keyspace (mt::gut::*). Replace/extend once per-mod registration (or
        -- VMF auto-mirror) lands.
        if mod.mod_tweaker and not mod.mod_tweaker:is_registered("gut_dev") then
            mod.mod_tweaker:register_category({
                mod_id = "gut_dev",
                label  = "Tweaker: GUI dev",
                widgets = {
                    {
                        setting_id = "mt_demo_slider",
                        type       = "slider",
                        label      = "Demo slider (proof of render)",
                        default    = 5,
                        range      = { 0, 20 },
                        decimals   = 0,
                    },
                },
            })
        end

        -- ESC menu entry injection. Hook the central layout consumer
        -- (IngameViewLayoutLogic.setup_button_layout) so we catch every layout variant
        -- the engine swaps through: alone / host / client / demo / tutorial / offline /
        -- full_access, plus the chat-button injected case. Vanilla source:
        -- scripts/ui/views/ingame_view_layout_logic.lua:17-60. hook_safe is correct
        -- here because setup_button_layout doesn't return -- it mutates
        -- self.active_button_data, which we extend after the iteration runs.
        mod:hook_safe("IngameViewLayoutLogic", "setup_button_layout", function(self, layout_data)
            local entries = self.active_button_data
            if type(entries) ~= "table" then return end
            -- Don't double-insert if the hook re-fires on the same active_button_data
            -- (layout swap during gameplay clears + rebuilds — safe to re-add).
            for i = 1, #entries do
                if entries[i].transition == "mod_tweaker_view" then return end
            end
            local insert_at = #entries + 1
            -- Place above Options for visual grouping; if Options isn't in this layout
            -- (e.g. console invert-controls demo), fall through to append.
            for i = 1, #entries do
                if entries[i].transition == "options_menu" then
                    insert_at = i
                    break
                end
            end
            table.insert(entries, insert_at, {
                -- display_name is a LOC KEY (resolved to "Mod Tweaker" via our
                -- append_backend_localizations). Do NOT add a display_name_func returning the
                -- resolved string: the MODERN menu (hero_window_ingame_view.lua:473) does
                -- `text_field = display_name_func() or display_name` and then LOCALIZES
                -- text_field — so a func returning "Mod Tweaker" gets re-localized into
                -- "<Mod Tweaker>". The key path localizes correctly in BOTH menus.
                display_name = "mod_tweaker_button_name",
                fade         = true,
                transition   = "mod_tweaker_view",
            })
            -- Diagnostic for the "ESC menu looks deprecated after leaving the Mod Tweaker"
            -- report: log the full button list each time the layout is built, so we can see
            -- if the count grows (accumulation) or the set changes after the Mod Tweaker.
            local ts = {}
            for i = 1, #entries do ts[#ts + 1] = tostring(entries[i].transition) end
            mod:debug("[mt:esc] setup_button_layout -> %d buttons: [%s]", #entries, table.concat(ts, ", "))
        end)
    end

    local function install_routing()
        -- Build + attach the Mod Tweaker view into an IngameUI instance's `views` table.
        -- Idempotent. Used by BOTH the setup_views hook (early attempt) and the
        -- transition closure (lazy, on demand). At transition time the IngameUI is fully
        -- initialised (self.views populated, self.ingame_ui_context set at
        -- ingame_ui.lua:138), so the lazy path is the reliable one — the setup_views
        -- post-call hook's timing vs self.views shifted after the game's Versus update,
        -- so it now sees self.views as not-yet-a-table and silently bails.
        local function _attach_view(self, ctx_arg)
            if not self or type(self.views) ~= "table" then return false end
            if self.views.mod_tweaker_view then return true end
            local ctx = ctx_arg or self.ingame_ui_context
            if not ctx then
                ctx = {
                    ui_renderer     = self.ui_renderer,
                    ui_top_renderer = self.ui_top_renderer,
                    ingame_ui       = self,
                    input_manager   = self.input_manager,
                    world_manager   = self.world_manager,
                }
            end
            if not (ctx.ui_renderer or ctx.ui_top_renderer) then
                _dbg_alert("[mt] attach: no usable ui_renderer in context; cannot build view")
                return false
            end
            local ok_view, ModTweakerView = load_view()
            if not ok_view or type(ModTweakerView) ~= "table" then
                _dbg_alert("[mt] attach: view dofile failed: %s", tostring(ModTweakerView))
                return false
            end
            local ok_new, view_or_err = pcall(ModTweakerView.new, ModTweakerView, ctx)
            if not ok_new then
                _dbg_alert("[mt] attach: ModTweakerView:new raised: %s", tostring(view_or_err))
                return false
            end
            self.views.mod_tweaker_view = view_or_err
            _dbg("[mt] attach: ModTweakerView attached")
            return true
        end

        -- The entry owns LA's forward-declared keepalive upvalue and assigns it only
        -- at its unchanged late dofile site. The captured getter reads that same cell
        -- so this transition (and the on_enter re-pin in _mod_tweaker_view.lua) can
        -- defensively re-pin LA's atlas + log on every Mod Tweaker open (v0.2.56),
        -- without eagerly freezing nil or a method. `_mt_open_count` remains the
        -- per-install open counter for instrumentation (shows 1st/2nd/3rd/4th open).
        local _mt_open_count = 0

        -- Re-pin LA's atlas package (pcall-guarded) + log the residency/renderer state on
        -- every Mod Tweaker open. The Mod Tweaker BORROWS the long-lived IngameUI renderer
        -- (does NOT recreate it), and the keepalive's premise that "LA unloads its own
        -- package" means the atlas can go missing between opens — so a one-time pin on
        -- StateInGameRunning.on_enter isn't enough; we re-pin on each open. The keepalive's
        -- own `has_loaded` force-load guard stays intact (it NEVER force-loads a non-resident
        -- LA package — that re-introduces the 0.2.54 crash). `self` is the IngameUI (site i)
        -- or the ModTweakerView (site ii) — both expose ui_renderer/ui_top_renderer for the
        -- renderer-identity probe. Exposed as mod._gut_mt_repin_la so the view module can
        -- call the SAME path.
        local function _gut_mt_repin_la(self, site)
            _mt_open_count = _mt_open_count + 1
            local pm = Managers and Managers.package
            local resident = "?"
            if pm and pm.has_loaded then
                local ok_r, r = pcall(pm.has_loaded, pm, "resource_packages/Loremasters-Armoury/Loremasters-Armoury")
                resident = ok_r and tostring(r) or ("err:" .. tostring(r))
            end
            local pinned = "?"
            if get_la_keepalive() and get_la_keepalive().is_pinned then
                local ok_p, p = pcall(get_la_keepalive().is_pinned)
                pinned = ok_p and tostring(p) or ("err:" .. tostring(p))
            end
            mod:debug("[gut:la] mod-tweaker open #%d (site=%s): LA_resident=%s gut_pinned=%s ui_renderer=%s ui_top_renderer=%s",
                _mt_open_count, tostring(site), resident, pinned,
                tostring(self and self.ui_renderer), tostring(self and self.ui_top_renderer))
            if get_la_keepalive() and get_la_keepalive().pin then
                local ok_pin, err_pin = pcall(get_la_keepalive().pin)
                if not ok_pin then
                    mod:warning("[gut:la] re-pin pcall raised on open #%d: %s", _mt_open_count, tostring(err_pin))
                end
            end
        end
        mod._gut_mt_repin_la = _gut_mt_repin_la

        -- Transition + view registration. Two halves:
        --   (a) transitions table -- mutated directly via package.loaded so the
        --       upvalue `transitions` captured at ingame_ui.lua:50 sees the new entry.
        --       The transition closure just sets self.current_view; vanilla pattern
        --       is at ingame_ui_settings.lua:537 (options_menu).
        --   (b) views table -- hook IngameUI.setup_views post-call (ingame_ui.lua:145)
        --       and inject our view instance, mirroring how
        --       view_settings.views_function builds the canonical map.
        -- (#1652) Keep-routing policy, published for the regression contracts: false since the
        -- v0.2.62-dev sub-state bounce revert (closure below), so the keep ESC entry never fades.
        local _USE_KEEP_SUBSTATE = false
        mod._gut_mt_keep_substate_routing = _USE_KEEP_SUBSTATE
        local ok_settings_inject, settings_inject_err = pcall(function()
            local settings = package.loaded["scripts/ui/views/ingame_ui_settings"]
            if not settings or not settings.transitions then
                error("ingame_ui_settings not in package.loaded; mod likely loaded too early")
            end
            if settings.transitions.mod_tweaker_view then
                _dbg("[mt] transition mod_tweaker_view already registered (idempotent)")
                return
            end
            settings.transitions.mod_tweaker_view = function(self)
                -- BUILD 2 ROUTING (v0.2.57-dev). The ESC "Mod Tweaker" button has TWO targets:
                --
                --   * IN THE KEEP/INN -> open the HeroView SUB-STATE (gut_mod_tweaker,
                --     _mod_tweaker_state.lua). A sub-state stays INSIDE the already-open
                --     hero_view and never recreates its renderer, so it eliminates BOTH the
                --     deprecated bare-IngameView look on exit AND the LA armoury_atlas
                --     renderer-recreation crash (42c81d84) that the leave/re-enter
                --     standalone-view path triggered. This is the proper fix the old TODO
                --     described.
                --
                --   * IN A MISSION -> there is NO hero_view, so we KEEP the existing standalone
                --     ModTweakerView path (the pre-build-2 behaviour). In a mission the
                --     standalone view's exit routes to "ingame_menu" (never crashed there; no
                --     hero_view to recreate), preserving in-mission access exactly as before.
                --
                -- Keep/inn detection matches _ba_heroview_inject: ingame_ui_context.is_in_inn.
                local ctx = self.ingame_ui_context
                local in_keep = not (ctx and ctx.is_in_inn == false)
                -- v0.2.62-dev REVERT: the keep HeroView sub-state (build 2) reliably OPENED (rows
                -- built) but the HeroView state machine immediately BOUNCED it back to
                -- HeroViewStateOverview (log: overview -> gut_mod_tweaker on_enter rows=13 ->
                -- overview), so it never stayed visible from the ESC button — the "doesn't open
                -- from the main menu" regression. The STANDALONE ModTweakerView opens reliably (it
                -- always did in-mission), and build-3's origin-capture exit (below) returns to the
                -- modern hero_view menu rather than the deprecated bare one, so the sub-state is no
                -- longer needed to avoid the deprecated look. Route the KEEP through the standalone
                -- view too. (HeroViewStateModTweaker + _ba_heroview_inject stay registered for the
                -- /mod_tweaker command.) Flip _USE_KEEP_SUBSTATE back only after the sub-state
                -- bounce is root-caused.
                if _USE_KEEP_SUBSTATE and in_keep and self.transition_with_fade and rawget(_G, "HeroViewStateModTweaker") then
                    _dbg("[mt] ESC entry in keep -> hero_view sub-state gut_mod_tweaker")
                    -- force_open = true is LOAD-BEARING. The ESC "Mod Tweaker" button fires from
                    -- INSIDE the already-open keep ESC menu, which IS hero_view (the ingame_menu
                    -- window inside HeroViewStateOverview), so self.current_view == "hero_view"
                    -- ALREADY. Without force_open, IngameUI.handle_transition's guard
                    -- `if old_view ~= new_view or force_open` (ingame_ui.lua:953) is false→false,
                    -- so it SKIPS HeroView:on_enter / post_update_on_enter — and post_update_on_enter
                    -- is the ONLY path that reads menu_state_name (hero_view.lua:504-508). Result
                    -- (the reported bug): the fade plays but the gut_mod_tweaker sub-state never
                    -- opens. force_open forces the re-enter so menu_state_name is honored. This is
                    -- the EXACT vanilla keep-button flow: every keep ESC menu button (Inventory,
                    -- Loot, ...) uses transition="hero_view" + transition_state=<screen> +
                    -- force_open=true (ingame_view_menu_layout_console.lua:742-745).
                    self:transition_with_fade("hero_view", {
                        menu_state_name = "gut_mod_tweaker",
                        force_open = true,
                    })
                    return
                end

                -- In-mission path (or sub-state unavailable): standalone ModTweakerView.
                -- DEFENSIVE re-pin LA's atlas + instrument BEFORE attaching/showing the view
                -- (site i). The borrowed renderer is long-lived, so the atlas can be unloaded
                -- between opens; re-pin every open (pcall-guarded, has_loaded-gated inside).
                pcall(_gut_mt_repin_la, self, "transition")
                -- Lazy-attach on demand: at click time the IngameUI is fully initialised, so
                -- this is the reliable build point. Idempotent. Only switch if the view
                -- actually attached, so a build failure stays a harmless no-op.
                _attach_view(self)
                if self.views and self.views.mod_tweaker_view then
                    -- Capture the ORIGIN menu so exit returns to it. In a mission ESC opens
                    -- EITHER the modern HeroView menu (current_view == "hero_view", the default
                    -- when use_pc_menu_layout=false) OR the legacy IngameView (current_view ==
                    -- "ingame_menu"). self.current_view is still the origin here — the engine
                    -- snapshots old_view BEFORE invoking this closure (ingame_ui.lua:946) — so
                    -- reading it now gives the menu the player actually opened. Hard-coding
                    -- "ingame_menu" dumped modern-menu players into the deprecated bare
                    -- IngameView on exit. ModTweakerView:exit already safely handles the
                    -- "hero_view" target (supplies { menu_state_name = "overview" }).
                    local origin = self.current_view
                    self.views.mod_tweaker_view._exit_transition =
                        (origin == "hero_view") and "hero_view" or "ingame_menu"
                    self.current_view = "mod_tweaker_view"
                else
                    _dbg_alert("[mt] transition: view not attached; ESC entry is a no-op")
                end
            end
            _dbg("[mt] transition registered: mod_tweaker_view")
        end)
        if not ok_settings_inject then
            _dbg_alert("[mt] transitions injection failed: %s", tostring(settings_inject_err))
        end

        -- ============================================================
        -- Open the Mod Tweaker from gameplay (#125) — hotkey + chat command
        -- ============================================================
        -- The Mod Tweaker settings menu is reachable from the ESC menu's "Mod Tweaker"
        -- button (the IngameViewLayoutLogic.setup_button_layout injection above). This
        -- exposes a DIRECT opener so a function-call keybind + a chat command can open it
        -- without going through the ESC menu first.
        --
        -- It drives the SAME `mod_tweaker_view` transition the ESC button uses (registered
        -- just above), via Managers.ui:handle_transition — so there is NO new hook and NO
        -- duplicated open logic. The transition closure handles attach + origin-capture +
        -- current_view, and works from raw gameplay (current_view is nil there, so the
        -- closure sets _exit_transition = "ingame_menu" as the FALLBACK only). With the
        -- #124 change the view's exit always routes to "exit_menu" (game), so a hotkey-
        -- opened menu — which has no originating menu — correctly returns to gameplay on
        -- exit. Mirrors the sibling in-mission inventory/hero-select openers
        -- (Managers.ui:handle_transition(..., { use_fade = true })).
        --
        -- SCOPE: keep AND mid-mission. The Mod Tweaker is a borrowed-renderer settings
        -- LIST (not a preview world), so it is NOT subject to the keep-only preview-world
        -- crash class that gates the hero-select/inventory features — the standalone
        -- ModTweakerView already opens reliably in-mission via the ESC button, and this
        -- reuses that exact path. No Chaos Wastes/deus gate is needed (no loadout surface).
        -- (In-mission behavior still wants the user's in-game confirmation.)
        mod.gut_open_mod_tweaker = function()
            if not (Managers.ui and Managers.ui.handle_transition) then
                mod:echo("UI manager not available (not in-game?).")
                return
            end
            local ok, err = pcall(function()
                Managers.ui:handle_transition("mod_tweaker_view", { use_fade = true })
            end)
            if not ok then
                mod:echo("Could not open the Mod Tweaker: " .. tostring(err))
            end
        end

        mod:command("mod_tweaker", "Open the Mod Tweaker settings menu (works in the keep and mid-mission). Same as the gut_open_mod_tweaker_hotkey keybind and the ESC-menu 'Mod Tweaker' button.", function()
            mod.gut_open_mod_tweaker()
        end)

        -- NOTE the second param: IngameUI.init passes the context to setup_views as an
        -- ARGUMENT (ingame_ui.lua:107) and does NOT store self.ingame_ui_context until
        -- later, so reading self.ingame_ui_context here is nil — that nil context made
        -- ModTweakerView:new throw, the view never attached, and transitioning to the
        -- (missing) view crashed IngameUI at ingame_ui.lua:625. Capture the arg instead.
        -- Early attach attempt. May no-op if self.views isn't populated yet at this
        -- hook's timing (the transition lazy-attach is the guaranteed path).
        mod:hook_safe("IngameUI", "setup_views", function(self, ingame_ui_context)
            _attach_view(self, ingame_ui_context)
        end)

        -- The ESC-menu "Mod Tweaker" button is the raw key "mod_tweaker_button_name"
        -- (ingame_view.lua:252 content.title_text = data.display_name, :138
        -- title_text.localize = true), localized at draw by the engine localizer. VMF mod
        -- loc is NOT in the engine tables, so it rendered as "<mod_tweaker_button_name>".
        --
        -- TWO prior HOOK fixes FAILED: (a) hooking _G.Localize — the global is set via
        -- rawset in LocalizationManager.init, so a re-init blows the VMF wrapper away; and
        -- (b) hooking LocalizationManager.lookup — the button's text pass ALSO localizes
        -- via LocalizationManager.simple_lookup (ui_passes.lua:1599), a SIBLING method that
        -- `lookup` never routes through. Both are interception; both miss a path.
        --
        -- ROOT-CAUSE FIX (workflow wf_8504e8ba): SUPPLY the string instead of intercepting.
        -- LocalizationManager._base_lookup checks self._backend_localizations FIRST
        -- (localization_manager.lua:50-51) and is the shared bottom of BOTH lookup and
        -- simple_lookup, so registering the string there resolves on every path natively —
        -- no wrapped closure to bypass. (LA already hooks _base_lookup in the field,
        -- confirming that table is the universal chokepoint.)
        --
        -- (#153/#292) The same defect class covers every gut key the ENGINE localizes:
        -- the hidden-passive perk rows render display_name/description through GLOBAL
        -- Localize (hero_window_talents.lua:477, hero_window_talents_console.lua:672),
        -- and the Video-tab profile widgets localize their title text, tooltip keys and
        -- the dropdown label (setup third return, consumed at options_view.lua:1280)
        -- through localize=true widget fields. Those keys lived only in VMF's mod-local
        -- table, so they drew as raw "<key>" text. Supply them to the SAME backend table
        -- here. The English strings are read from the mod localization file (single
        -- source of truth); VMF's "%%" escapes are collapsed to a literal "%" because
        -- the engine path has NO string.format pass for these strings (a perk row with
        -- no description_values returns Localize(str) untouched, ui_utils.lua:36-38).
        -- The dropdown OPTION texts are deliberately absent: they are pre-resolved via
        -- mod:localize inside the setup callbacks and never hit the engine localizer.
        local ENGINE_UI_LOC_KEYS = {
            -- #153 hidden career passives (native Perks rows).
            "gut_hidden_passive_whc_headshot_name",
            "gut_hidden_passive_whc_headshot_desc",
            "gut_hidden_passive_whc_crit_name",
            "gut_hidden_passive_whc_crit_desc",
            "gut_hidden_passive_whc_combined_name",
            "gut_hidden_passive_whc_combined_desc",
            -- #292 Video-tab profile controls (title, dropdown labels, tooltips).
            "gut_video_profiles_header",
            "gut_video_profile_selector",
            "gut_video_profile_selector_tooltip",
            "gut_video_profile_action",
            "gut_video_profile_action_tooltip",
        }

        local engine_ui_loc_cache  -- built once; re-registration re-USES it (dofile is not free)
        local function _engine_ui_localizations()
            if engine_ui_loc_cache then return engine_ui_loc_cache end
            local strings = {}
            local ok, loc_table = load_localization()
            if not ok or type(loc_table) ~= "table" then
                return strings
            end
            local complete = true
            for _, key in ipairs(ENGINE_UI_LOC_KEYS) do
                local entry = loc_table[key]
                local text = type(entry) == "table" and entry.en
                if type(text) == "string" then
                    strings[key] = text:gsub("%%%%", "%%")
                else
                    complete = false
                end
            end
            -- Cache only a complete harvest so a failed early read retries next call.
            if complete then engine_ui_loc_cache = strings end
            return strings
        end

        local function _register_button_loc()
            local loc = Managers and Managers.localizer
            if loc and loc.append_backend_localizations then
                pcall(loc.append_backend_localizations, loc, { mod_tweaker_button_name = "Mod Tweaker" })
                -- (#153/#292) engine-rendered gut UI keys (see ENGINE_UI_LOC_KEYS above).
                pcall(loc.append_backend_localizations, loc, _engine_ui_localizations())
                -- #352 uses the same native backend-localization path for the explicit
                -- legacy THP names. Re-supply them after language/localizer re-init.
                local thp_names = mod._gut_original_thp_names
                if thp_names and thp_names.register_backend_localizations then
                    thp_names.register_backend_localizations()
                end
                -- PROBE: after registering, what does the engine localizer actually return
                -- for the key? If this prints "Mod Tweaker", the append works and any <> the
                -- user still sees is a DIFFERENT element (not this ESC button). If it prints
                -- "<mod_tweaker_button_name>", the backend-loc path is NOT what this button
                -- localizes through and we need a different fix.
                local resolved = "?"
                if rawget(_G, "Localize") then pcall(function() resolved = Localize("mod_tweaker_button_name") end) end
                mod:info("[mt] registered backend loc; Localize('mod_tweaker_button_name') -> '%s'", tostring(resolved))
                return true
            end
            mod:info("[mt] backend-loc register SKIPPED (Managers.localizer not ready at this point)")
            return false
        end
        -- Register at boot if the localizer is already up; otherwise on_all_mods_loaded (below)
        -- and the IngameView.on_enter retry guarantee it's set before the ESC menu draws.
        _register_button_loc()
        -- _backend_localizations is reset to {} in LocalizationManager.init (a mid-session
        -- language switch re-inits), so re-register after any re-init. This is DATA, not a
        -- wrapped closure — immune to the rawset/VMF-chain fragility that killed both hooks.
        mod:hook_safe("LocalizationManager", "init", function()
            _register_button_loc()
        end)
        -- Belt-and-suspenders: register when the ESC menu opens (Managers.localizer is
        -- definitely up by then), so even if boot/on_all_mods_loaded missed, the key is set
        -- before the button's title_text is drawn. (gut hooks HeroView.on_enter, not
        -- IngameView.on_enter — distinct pair, no duplicate.)
        mod:hook_safe("IngameView", "on_enter", function()
            _register_button_loc()
        end)
        -- (#153/#292) Lock: every engine-rendered gut UI key must resolve through the
        -- GLOBAL localizer path (same structure as issue352's loc validation in
        -- _gut_original_thp_names.lua). FAILS whenever a key is missing from the loc
        -- file, still carries a VMF %% escape, or is not being served by the engine
        -- localizer (Localize falls through to "<key>" when unsupplied).
        _rt_register("issue153_292_engine_ui_loc_supplied", function()
            local strings = _engine_ui_localizations()
            for _, key in ipairs(ENGINE_UI_LOC_KEYS) do
                local text = strings[key]
                if type(text) ~= "string" then
                    return "engine-UI localization source missing key: " .. key
                end
                if text:find("%%%%") then
                    return "engine-UI localization still carries a VMF %% escape: " .. key
                end
            end
            local localize = rawget(_G, "Localize")
            if type(localize) ~= "function" then
                return "global Localize unavailable (engine-UI keys cannot resolve)"
            end
            for _, key in ipairs(ENGINE_UI_LOC_KEYS) do
                local ok, resolved = pcall(localize, key)
                if not ok or resolved ~= strings[key] then
                    return string.format("engine localizer does not serve %s (got %s)",
                        key, tostring(resolved))
                end
            end
        end)
        return ENGINE_UI_LOC_KEYS, _engine_ui_localizations
    end

    local function install_compaction()
        -- ESC/keep-menu button-overflow compaction (v0.2.56; REWRITTEN v0.2.64-dev — was
        -- hooking the WRONG class for 8 versions).
        --
        -- DIAGNOSIS of why the prior fix never worked:
        --   * The keep pause/ESC menu the user sees is NOT the legacy IngameView. The
        --     reported button list (character_selection / spoils_of_war /
        --     return_to_pc_menu_hero_view / quit_game_hero_view, 10 entries) is the MODERN
        --     HeroView sub-window `HeroWindowIngameView` (hero_window_ingame_view.lua) — the
        --     "Main Menu" screen inside hero_view. That class has NO set_background_height
        --     method; the gut hook on `IngameView.set_background_height` therefore NEVER
        --     FIRED for the keep menu. (Legacy IngameView is only the bare in-MISSION menu.)
        --   * Even on the legacy IngameView path the logo branch was dead: IngameView.
        --     create_ui_elements (ingame_view.lua:122-152) NEVER assigns self.logo — the logo
        --     widget isn't even instantiated there (it has no `logo` widget def), so
        --     `if self.logo ...` was always nil. The visible logo comes from the modern menu.
        --
        -- The modern menu lays out its button column + sizes its panel in
        -- HeroWindowIngameView._update_presentation (hero_window_ingame_view.lua:490-515):
        -- each title button gets `offset[2] = -(60 * index - 1)` (spacing = 60, line 504),
        -- and the background panel grows to `total_height + 90` (line 513). With 10 buttons
        -- the column runs `0 .. -540` and overflows off the bottom. The logo widget is
        -- `_widgets_by_name.logo` (definitions :287, scenegraph node "logo").
        --
        -- FIX: hook_safe `HeroWindowIngameView._update_presentation` (runs AFTER vanilla
        -- positions the column, so our shift/hide stick) and, once over the overflow
        -- threshold: (a) lift the whole button column up by re-walking the same index→offset
        -- math with a reduced spacing AND a positive top bias, and (b) hide the logo by
        -- zeroing its style.color alpha. hook_safe is correct (the vanilla method returns
        -- nothing; it mutates widget offsets + the scenegraph in place). This (Class,method)
        -- pair is hooked NOWHERE ELSE in gut — grep-verified before adding (the only other
        -- HeroView-family hook is HeroView.on_enter, a different class+method).
        --
        -- (#93) ALWAYS-ON implicit feature (2026-06-24): the `gut_compact_esc_menu` toggle +
        -- setting were removed — this was never meant to be optional (gut itself adds the Mod
        -- Tweaker ESC button that causes the overflow this fixes, so the fix should always run,
        -- like wt's auto-vent). The hook is only a no-op below the overflow threshold anyway, so
        -- there's nothing to gate. No setting read remains.
        --
        -- NOTE the COLUMN_SHIFT / SPACING numbers below are TUNE-IN-GAME values — they move
        -- the column the right DIRECTION (up) but the exact lift needs an in-game eyeball.
        local _MT_ESC_OVERFLOW_THRESHOLD = 8   -- vanilla keep menu is ~8 buttons; gut + VMF push it to 10
        mod:hook_safe("HeroWindowIngameView", "_update_presentation", function(self)
            local buttons = self._title_button_widgets
            local layout_logic = self.layout_logic
            if not (buttons and layout_logic) then return end
            local ok_ld, layout_data = pcall(layout_logic.layout_data, layout_logic)
            if not ok_ld or type(layout_data) ~= "table" then return end
            local num = #layout_data
            if num < _MT_ESC_OVERFLOW_THRESHOLD then return end

            -- Re-pack the column tighter so all `num` buttons fit, and bias the whole stack
            -- UP. Vanilla uses spacing = 60 starting near offset 0 (descending). We compress
            -- spacing and add a positive top bias = half the saved height, re-centring the
            -- shorter column. (Vanilla math: hero_window_ingame_view.lua:497-505.)
            local VANILLA_SPACING = 60
            local SPACING = 48                                  -- tighter rows (TUNE IN-GAME)
            local saved = (VANILLA_SPACING - SPACING) * num     -- total height reclaimed
            local TOP_BIAS = math.floor(saved / 2)              -- lift so the column re-centres
            for index = 1, num do
                local w = buttons[index]
                if w and w.offset then
                    -- mirrors vanilla `-(spacing * index - 1)` with our spacing + the up-bias.
                    w.offset[2] = -(SPACING * index - 1) + TOP_BIAS
                end
            end

            -- Hide the keep logo so the (now lifted) column has clear headroom. The logo
            -- widget is _widgets_by_name.logo (definitions :287, built via
            -- UIWidgets.create_simple_texture). create_simple_texture nests color under
            -- style.texture_id.color, NOT style.color (ui_widgets.lua:5302-5318) — the prior
            -- IngameView code read the wrong path, which was part of why "logo still shows".
            -- VT2 color tables are {A,R,G,B}, so alpha is index [1]. Idempotent — re-zeroing
            -- each presentation rebuild is harmless.
            local wbn = self._widgets_by_name
            local logo = wbn and wbn.logo
            local lstyle = logo and logo.style and logo.style.texture_id
            if lstyle and lstyle.color then
                lstyle.color[1] = 0
            end

            -- Lift the keep separator/divider by the same amount as the button column so it
            -- sits ABOVE the menu text instead of bleeding through it. _widgets_by_name.divider
            -- is the upper rule (hero_window_ingame_view_definitions.lua:279,
            -- UIWidgets.create_simple_texture("divider_01_top", "divider"); sg node "divider").
            -- NOT divider_bottom (:280, the lower rule). It's registered into _widgets_by_name
            -- in create_ui_elements (:161-169), so it's drawable/mutable here. The button
            -- column was lifted +TOP_BIAS via each button widget's render offset[2] (:1096);
            -- mutating the divider's render offset[2] the SAME {0,0,0} field keeps the shift
            -- isolated to the divider texture (does NOT cascade to the logo/panel/buttons that
            -- are scenegraph-parented to the "divider" node — a render-offset change doesn't
            -- touch the scenegraph). Idempotent: TOP_BIAS is recomputed each presentation
            -- rebuild and vanilla never resets this offset, so SET (not +=) to avoid drift.
            local divider = wbn and wbn.divider
            if divider and divider.offset then
                divider.offset[2] = TOP_BIAS
            end
        end)
    end

    return {
        install_api = install_api,
        load_view = load_view,
        install_routing = install_routing,
        install_compaction = install_compaction,
    }
end

return M
