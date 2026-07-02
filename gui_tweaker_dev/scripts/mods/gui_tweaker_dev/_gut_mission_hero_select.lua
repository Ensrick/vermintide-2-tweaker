local mod = get_mod("gut_dev")

-- _gut_mission_hero_select.lua -- in-mission HERO/CAREER SELECT access (#173, C7).
--
-- Rewritten 2026-07-02. The previous revision of this file deliberately opened the
-- HeroView TALENTS layout and called that "Hero Select" -- that was the #173 bug.
-- This module now opens the REAL hero/career selection screen mid-mission: the
-- top-level `character_selection` view (CharacterSelectionView -- the grid where you
-- pick character/career, the keep "C"-key screen), via the exact vanilla transition
-- the keep character pedestal fires:
--     Managers.ui:handle_transition("character_selection_force",
--         { menu_state_name = "character", use_fade = true })
-- (interactions.lua:2312-2320 `characters_access`; transition body sets
-- current_view = "character_selection" + exit_to_game = true,
-- ingame_ui_settings.lua:476-479; the "C" hotkey_hero maps to the same transition,
-- ingame_ui_settings.lua:769-776.)
--
-- ============================================================================
-- WHY the transition is NOT fired blind: the keep-only backdrop WORLD (C7 design)
-- ============================================================================
-- Full research: gui_tweaker_dev/HERO_SELECT_RESEARCH_173.md (source-cited; updated
-- 2026-07-02 with the bundle-listing + B7 findings summarized here).
--
-- (1) CharacterSelectionView has NO keep-only code gate. No fassert/early-out on
--     is_in_inn anywhere in the view (it only stores the flag,
--     character_selection_view.lua:35); the confirm button's one environmental
--     requirement is an active Network.game_session()
--     (character_selection_state_character.lua:1503-1507), which exists mid-mission.
--
-- (2) Its ONLY mission blocker is a resource: post_update_on_enter
--     (character_selection_view.lua:519-539) unconditionally builds the viewport
--     widget, whose style mounts level_name = "levels/ui_character_selection/world"
--     (character_selection_view_definitions.lua:385). That style carries NO
--     level_package_name and NO shading_environment (verified: defs :370-408 --
--     level_name is the def's single resource field; the viewport pass reads
--     style.shading_environment nil-safe and style.level_name -> spawn_level,
--     ui_passes.lua:2443-2458).
--
-- (3) BUNDLE EVIDENCE (2026-07-02, vt2_bundle_unpacker/all_bundles_listing.txt):
--     `levels/ui_character_selection/world.level` exists ONLY in hub/menu bundles
--     (inn/keep bundle 8e0929053dd7ecd0, morris_hub bundle 4ed8509e0f030866,
--     keep-menu/store bundles). NO mission bundle contains it, and there is NO
--     `resource_packages/levels/ui_character_selection.package` anywhere in the game
--     files -- so a Managers.package:load preload of the native backdrop is
--     IMPOSSIBLE, and a blind mid-mission transition = C-level resource fatal at the
--     level mount (bypasses pcall).
--
-- (4) THE FIX (C7): `levels/ui_inventory_preview/world` DOES have a managed package
--     (`resource_packages/levels/ui_inventory_preview`), and HeroView's
--     character-preview window force-loads it mid-mission via
--     Managers.package:load(pkg, ref, cb, async) + gates on has_loaded
--     (hero_window_character_preview.lua:100-105,163). gut's in-mission inventory
--     feature has proven that world mission-safe many times over. So mid-mission we:
--       a. async-load that package under our OWN reference ("gut_hero_select"),
--       b. swap the CACHED defs table's viewport level_name to the inventory-preview
--          world (+ set its shading env, "environment/ui_inventory_preview", the env
--          hero_window_character_preview_definitions.lua:227 pairs with that level),
--       c. fire the vanilla character_selection_force transition,
--       d. restore the original def values the moment the viewport widget is built
--          (post_update_on_enter hook below), so the keep's native opens always get
--          the native world.
--     The defs table mutated is the SAME table the view reads: the view binds
--     `local widget_definitions = definitions.widgets_definitions` from
--     local_require (character_selection_view.lua:8-9), and local_require caches in
--     package.loaded exactly like require (foundation/scripts/util/local_require.lua:5-17).
--
-- (5) CAREER SWAP IS IN-PLACE, NOT A TELEPORT. The Select button routes
--     CharacterSelectionStateCharacter._change_profile ->
--     ProfileRequester:request_profile(..., force_respawn = true)
--     (character_selection_state_character.lua:1509,1602-1615). EMPIRICALLY PROVEN
--     by gut's live B7 probe (_gut_173_probes.lua; 2026-07-02 logs, multiple
--     firings): post-respawn moved=0.0 -- the respawn happens IN PLACE. The old
--     "force_respawn teleports you to level start" rationale in this file's previous
--     revision is REFUTED; do not re-add it.
--
-- RESIDENCY CHECK: before choosing a path we pcall
-- Application.can_get("level", "levels/ui_character_selection/world") -- vanilla's
-- own non-faulting existence check (arg order (type, name) verified at
-- pickup_system.lua:882 can_get("unit", ...) and cosmetic_utils.lua:133
-- can_get("package", ...); same pre-filter mechanic as _gut_gui_material_guard.lua).
-- NO vanilla call site uses the "level" resource type, so a `true` is trusted ONLY
-- after a self-test: can_get("level", <the current mission's own level_name>) must
-- also be true (that level is resident by definition). If the self-test fails, the
-- "level" type is not trustworthy in this build and we treat the native world as
-- never-resident in missions -- which is what the bundle evidence says anyway -- and
-- take the swap path. A false NEGATIVE just means an unnecessary backdrop swap
-- (safe); only a trusted `true` may route to the native, unswapped mount.
--
-- PACKAGE RETENTION (deliberate): once loaded, our "gut_hero_select" reference on
-- resource_packages/levels/ui_inventory_preview is kept for the REST OF THE SESSION
-- (no unload on view exit). Rationale: PackageManager.unload asserts on unknown
-- refs and interleaves badly with HeroView's own load/unload cycle on the same
-- package (hero_window_character_preview.lua:131), the package is the small
-- inventory-preview backdrop the keep loads constantly anyway, and a resident level
-- also makes any def-swap leak crash-proof. Reload latency on reopen: zero.
-- PackageManager.load on an already-loaded package just bumps the refcount and fires
-- the callback synchronously (package_manager.lua:26-27,56-58).
--
-- ============================================================================
-- HOOK PRE-FLIGHT (VMF no-duplicate-hook rule)
-- ============================================================================
-- Whole-mod grep 2026-07-02 for "CharacterSelection": every hit is a comment
-- (this file, _gut_career_swap.lua, _gut_173_probes.lua, gui_tweaker_dev.lua) --
-- gut_dev registers ZERO hooks on CharacterSelectionView anywhere else. The two
-- hook_safe registrations below (post_update_on_enter, on_exit) are therefore
-- singletons. _gut_173_probes.lua hooks GameModeAdventure.force_respawn only.
--
-- DISPATCH WIRING (unchanged):
--   * mod.gut_open_mission_hero_select is a PUBLIC `mod.` field, so the VMF keybind
--     `function_name = "gut_open_mission_hero_select"` resolves it at invoke time,
--     and the /hero_select command (registered below) calls it directly.
--   * The old HeroView-era InventorySettings loadout-access force-flip is GONE:
--     CharacterSelectionView reads only static InventorySettings tables (slot
--     names/loadouts), not inventory_loadout_access_supported_game_modes (that gate
--     is hero_view.lua:323 -- HeroView-only).
--
-- EXIT: 100% vanilla. character_selection_force sets exit_to_game = true
-- (ingame_ui_settings.lua:478), so ESC/back routes straight back to the mission.

local _pf = rawget(_G, "printf") or function(fmt, ...) print(string.format(fmt, ...)) end

local CHARSEL_DEFS_PATH = "scripts/ui/views/character_selection_view/character_selection_view_definitions"
local CHARSEL_LEVEL     = "levels/ui_character_selection/world"       -- native backdrop (hub/menu bundles only)
local PREVIEW_PKG       = "resource_packages/levels/ui_inventory_preview"  -- managed package (mission-loadable)
local PREVIEW_LEVEL     = "levels/ui_inventory_preview/world"         -- mission-safe backdrop level
local PREVIEW_ENV       = "environment/ui_inventory_preview"          -- its paired shading env (hero_window_character_preview_definitions.lua:227)
local PKG_REF           = "gut_hero_select"                            -- OUR PackageManager reference name

-- Saved originals for the def swap (module-scope; captured once, restored on every
-- restore point). _swap_active tracks whether the shared defs table is currently dirty.
local _orig = nil
local _swap_active = false
local _load_in_flight = false

-- The CACHED definitions module table -- the same one the view's file-local
-- widget_definitions upvalue points into (local_require shares package.loaded with
-- require). Read from package.loaded directly (same pattern as
-- _gut_mission_inventory.lua's _get_in_game_layouts); it is populated at boot by
-- ingame_ui's require chain, long before any mod code runs.
local function _viewport_style()
    local loaded = package and package.loaded
    local defs = loaded and loaded[CHARSEL_DEFS_PATH]
    local widgets = defs and defs.widgets_definitions
    local viewport = widgets and widgets.viewport
    return viewport and viewport.style and viewport.style.viewport
end

-- Trusted residency check for the native charsel backdrop. Returns true ONLY when
-- Application.can_get supports the "level" type in this build (self-tested against
-- the current level, which is resident by definition) AND reports the native world
-- gettable. Any other outcome -> false (mission-safe swap path; a false negative
-- costs only an unneeded backdrop swap, a false positive would be a C-fatal).
local function _native_world_gettable()
    local can_get = Application and Application.can_get
    if not can_get then
        _pf("[gut:heroselect] Application.can_get unavailable -> treating native charsel world as not resident")
        return false
    end
    -- Self-test: the mission's own level resource must be gettable, else the "level"
    -- resource type is not trustworthy here (no vanilla call site uses it; see docstring).
    local gm = Managers.state and Managers.state.game_mode
    local level_key = gm and gm.level_key and gm:level_key()
    local settings = level_key and rawget(_G, "LevelSettings") and LevelSettings[level_key]
    local current_level_name = settings and settings.level_name
    if not current_level_name then
        _pf("[gut:heroselect] no current level_name for self-test (level_key=%s) -> not trusting can_get('level'); using swap path", tostring(level_key))
        return false
    end
    local ok_self, self_avail = pcall(can_get, "level", current_level_name)
    if not (ok_self and self_avail == true) then
        _pf("[gut:heroselect] can_get('level') self-test FAILED on resident level %s (ok=%s avail=%s) -> type untrustworthy; using swap path",
            tostring(current_level_name), tostring(ok_self), tostring(self_avail))
        return false
    end
    local ok, avail = pcall(can_get, "level", CHARSEL_LEVEL)
    _pf("[gut:heroselect] can_get('level', %s) -> ok=%s avail=%s (self-test passed on %s)",
        CHARSEL_LEVEL, tostring(ok), tostring(avail), tostring(current_level_name))
    return ok and avail == true
end

-- Swap the cached def's backdrop to the mission-safe inventory-preview world.
-- Captures the originals once (level_name; shading_environment is nil in the native
-- def -- defs :381-405 -- so restore puts nil back).
local function _apply_backdrop_swap()
    local vp = _viewport_style()
    if not vp then
        _pf("[gut:heroselect] DEF-SWAP FAILED: charsel defs module not in package.loaded (path=%s)", CHARSEL_DEFS_PATH)
        return false
    end
    if not _orig then
        _orig = { level_name = vp.level_name, shading_environment = vp.shading_environment }
    end
    vp.level_name = PREVIEW_LEVEL
    vp.shading_environment = PREVIEW_ENV
    _swap_active = true
    _pf("[gut:heroselect] def-swap APPLIED: viewport level_name %s -> %s (env -> %s)",
        tostring(_orig.level_name), PREVIEW_LEVEL, PREVIEW_ENV)
    return true
end

local function _restore_backdrop(reason)
    if not _swap_active then return end
    local vp = _viewport_style()
    if vp and _orig then
        vp.level_name = _orig.level_name
        vp.shading_environment = _orig.shading_environment   -- nil in the native def -> cleared
    end
    _swap_active = false
    _pf("[gut:heroselect] def-swap RESTORED (level_name=%s) -- %s",
        tostring(_orig and _orig.level_name), tostring(reason))
end

-- The vanilla keep-pedestal transition, verbatim (interactions.lua:2312-2320).
local function _fire_transition(ctx)
    local ok, err = pcall(function()
        Managers.ui:handle_transition("character_selection_force", {
            menu_state_name = "character",
            use_fade        = true,
        })
    end)
    _pf("[gut:heroselect] character_selection_force fired (%s) -> ok=%s%s",
        tostring(ctx), tostring(ok), ok and "" or (" err=" .. tostring(err)))
    if not ok then
        mod:echo("Could not open hero select: " .. tostring(err))
    end
end

-- ============================================================
-- Open Hero Select In Mission (real CharacterSelectionView)
-- ============================================================
mod.gut_open_mission_hero_select = function()
    if not (Managers.ui and Managers.ui.handle_transition) then
        mod:echo("UI manager not available (not in-game?).")
        return
    end
    if not mod:get("gut_mission_hero_select_enabled") then
        _pf("[gut:heroselect] keybind fired but gut_mission_hero_select_enabled=false -> ignored")
        mod:echo("In-Mission Hero Select is disabled in the mod settings.")
        return
    end
    -- (#173) IN-MISSION ONLY -- the keep already has a native hero-select keybind. ROBUST keep
    -- detection: primary = level_key == "inn_level" (the keep level; this is what gut's cutscene
    -- code uses reliably), backup = DamageUtils.is_in_inn. printf so the next log shows EXACTLY
    -- the context this keybind fired in.
    local gm  = Managers.state and Managers.state.game_mode
    local lvl = (gm and gm.level_key) and gm:level_key() or nil
    local dui = rawget(_G, "DamageUtils") and DamageUtils.is_in_inn or false
    local in_keep = (lvl == "inn_level") or dui or false
    _pf("[gut:heroselect] keybind fired -> in_keep=%s level_key=%s is_in_inn=%s (bail=%s)",
        tostring(in_keep), tostring(lvl), tostring(dui), tostring(in_keep))
    if in_keep then
        return  -- in the keep: do nothing; the native keep keybind handles hero select
    end
    -- CHAOS WASTES BLOCK: a mid-CW-run career swap would desync the deus profile /
    -- boon state (CW loadouts + boons are managed by the deus system per profile).
    -- Covers the /hero_select command + the gut_open_hero_select_hotkey keybind
    -- (both route here).
    local mech = Managers.mechanism and Managers.mechanism:current_mechanism_name()
    if mech == "deus" then
        _pf("[gut:heroselect] blocked: mechanism=deus (career swap would desync deus profile/boon state)")
        mod:echo("In-mission hero select is disabled in Chaos Wastes - a career swap mid-run would desync your boons/loadout. Adventure only.")
        return
    end
    -- Residency fork: native world gettable (keep-adjacent contexts) -> vanilla
    -- verbatim; otherwise (normal missions, per the bundle evidence) -> swap path.
    if _native_world_gettable() then
        _restore_backdrop("native world resident; opening unswapped")  -- no-op unless a swap leaked
        _fire_transition("native backdrop")
        return
    end
    local pm = Managers.package
    if not (pm and pm.load and pm.has_loaded) then
        _pf("[gut:heroselect] Managers.package unavailable -> cannot take the swap path; aborting")
        mod:echo("Could not open hero select (package manager unavailable).")
        return
    end
    -- Already pinned by US -> swap + fire immediately. has_loaded(pkg, ref) is
    -- reference-scoped: true only if THAT ref holds it (package_manager.lua:286-294).
    if pm:has_loaded(PREVIEW_PKG, PKG_REF) then
        _pf("[gut:heroselect] %s already loaded (ref=%s) -> proceeding", PREVIEW_PKG, PKG_REF)
        if _apply_backdrop_swap() then
            _fire_transition("swapped backdrop, package resident")
        else
            mod:echo("Could not open hero select (definitions module unavailable).")
        end
        return
    end
    -- Load in flight (our ref) -> the pending callback will open the view; don't
    -- double-load (each load call adds a refcount + a callback firing = double open).
    if _load_in_flight or (pm.is_loading and pm:is_loading(PREVIEW_PKG, PKG_REF)) then
        _pf("[gut:heroselect] %s load already in flight (ref=%s) -> ignoring re-press", PREVIEW_PKG, PKG_REF)
        return
    end
    -- Async managed load under OUR reference, mirroring HeroView's own mid-mission
    -- force-load of this exact package (hero_window_character_preview.lua:100-105).
    -- If the package is resident via someone else's ref, load() just bumps our
    -- refcount and fires the callback synchronously (package_manager.lua:26-27,56-58).
    _load_in_flight = true
    _pf("[gut:heroselect] async load START: %s (ref=%s)", PREVIEW_PKG, PKG_REF)
    local on_loaded = function()
        _load_in_flight = false
        _pf("[gut:heroselect] async load COMPLETE: %s (ref=%s)", PREVIEW_PKG, PKG_REF)
        local ok, err = pcall(function()
            if not (Managers.ui and Managers.ui.handle_transition) then
                _pf("[gut:heroselect] UI manager gone at load-complete -> not opening")
                return
            end
            if _apply_backdrop_swap() then
                _fire_transition("swapped backdrop, post-load")
            end
        end)
        if not ok then
            _pf("[gut:heroselect] load-complete handler error: %s", tostring(err))
        end
    end
    local ok_load, err_load = pcall(pm.load, pm, PREVIEW_PKG, PKG_REF, on_loaded, true)
    if not ok_load then
        _load_in_flight = false
        _pf("[gut:heroselect] Managers.package:load FAILED: %s", tostring(err_load))
        mod:echo("Could not open hero select (backdrop package failed to load).")
    end
end

-- ============================================================
-- Restore points (both hook_safe; singletons per the pre-flight above)
-- ============================================================
-- (a) The def values are consumed exactly once, at UIWidget.init inside
-- post_update_on_enter (character_selection_view.lua:519-522) -- the level spawns in
-- UIPasses.viewport.init at that moment (ui_passes.lua:2447-2458). Restore
-- immediately after, so the shared defs table is dirty only for the fade-to-mount
-- window and every later native open (keep "C" key) gets the native world.
mod:hook_safe("CharacterSelectionView", "post_update_on_enter", function(self)
    _restore_backdrop("post_update_on_enter (viewport widget built)")
end)

-- (b) Belt-and-suspenders: if the view exits without post_update_on_enter ever
-- firing (aborted transition), clear the dirty def here. Idempotent no-op otherwise.
-- Our package reference is deliberately NOT released here (see PACKAGE RETENTION in
-- the docstring).
mod:hook_safe("CharacterSelectionView", "on_exit", function(self)
    _restore_backdrop("on_exit")
end)

mod:command("hero_select", "Open the hero/career selection screen mid-mission (the real character-select grid; picking a career respawns you in place). Adventure only.", function()
    mod.gut_open_mission_hero_select()
end)
