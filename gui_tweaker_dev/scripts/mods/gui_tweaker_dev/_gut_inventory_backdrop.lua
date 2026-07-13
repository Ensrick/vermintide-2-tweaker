local mod = get_mod("gut_dev")

-- _gut_inventory_backdrop.lua -- inventory character-preview backdrop dropdown (#522).
--
-- Lets the user swap the environment shown behind the hero in the inventory
-- character preview (the HeroView "overview" layout's preview pane) from the
-- vanilla stage to one of the game's darker menu scenes.
--
-- ============================================================================
-- HOW VANILLA MOUNTS THE PREVIEW BACKDROP (all citations = decompiled source)
-- ============================================================================
-- HeroWindowCharacterPreview is the preview pane. Its lifecycle is a textbook
-- managed-package mount, and we ride it UNCHANGED -- the swap below only edits
-- WHICH package/level/env the vanilla machinery handles:
--   * The viewport widget def carries the resource triplet:
--       level_name          = "levels/ui_inventory_preview/world"
--       level_package_name  = "resource_packages/levels/ui_inventory_preview"
--       shading_environment = "environment/ui_inventory_preview"
--     (hero_window_character_preview_definitions.lua:225-227).
--   * create_ui_elements captures self._level_package_name FROM THE DEF and
--     async-loads it under ref "HeroWindowCharacterPreview"
--     (hero_window_character_preview.lua:100-105).
--   * post_update builds the viewport widget ONLY once
--     Managers.package:has_loaded(self._level_package_name, ref) is true
--     (hero_window_character_preview.lua:163-164) -- the loading overlay covers
--     the wait. UIWidget.init runs UIPasses.viewport.init, which creates the
--     world with style.shading_environment and ScriptWorld.spawn_level's the
--     style.level_name (ui_passes.lua:2436-2458). An unresident level here is
--     the C-level "Level not loaded" fatal (the 0.2.190 lesson, issue 336) --
--     which is exactly why the swap NEVER bypasses the has_loaded gate.
--   * on_exit unloads self._level_package_name symmetrically
--     (hero_window_character_preview.lua:131).
-- The def table is consumed via a FILE-SCOPE local (viewport_widget_definition,
-- hero_window_character_preview.lua:8), so the TABLE cannot be replaced -- but
-- its inner fields are read at call time, so mutating them in a pre-hook works.
-- The defs module is cached in package.loaded (local_require caches like
-- require, foundation/scripts/util/local_require.lua:5-17; same access pattern
-- as _gut_mission_hero_select.lua), and grep of the decompile shows that window
-- file is the defs module's ONLY consumer.
--
-- ============================================================================
-- WHY THESE TWO ALTERNATIVES AND NO OTHERS (candidate audit 2026-07-13)
-- ============================================================================
-- A candidate backdrop MUST have its own standalone managed .package (memory
-- rule: package:load needs a .package path), because the swap makes vanilla
-- load it through the has_loaded gate above -- resident-in-the-keep-by-luck is
-- not enough (gut also opens this same window MID-MISSION via
-- _gut_mission_inventory, where hub bundles are absent).
--   * levels/end_screen/world ("dark camp"): the dark camp scene. Package
--     resource_packages/levels/ui_end_screen -- a standalone managed package
--     the game itself async-loads MID-MISSION at every adventure round end
--     (adventure_mechanism.lua:363-365 -> level_end_view_wrapper.lua:30-44,
--     has_loaded-checked at end_view_state_summary.lua:92; deus too,
--     deus_mechanism.lua:726). The keep's chest-opening screen mounts this very
--     level through the SAME UIPasses.viewport pass with object_sets
--     {"flow_victory"} (hero_view_state_loot_definitions.lua:1104-1115), which
--     we mirror verbatim. This is the "standard backdrop with the dark
--     lighting" the issue asks for. Env: environment/ui_end_screen
--     (level_end_view_base.lua:1502) -- already proven crash-safe by gut's own
--     mission-map fallback def, which shipped with that env (issue 336 work).
--   * levels/end_screen_victory/world ("victory camp"): the celebration scene.
--     Package resource_packages/levels/ui_end_screen_victory -- the weave end
--     view's standalone managed package (adventure_mechanism.lua:357-361, same
--     wrapper load path), level mounted at level_end_view_weave.lua:347. Same
--     env. No object sets passed (ScriptWorld.spawn_level takes object_sets or
--     {}, script_world.lua:385-387 -- nil is safe).
-- REJECTED candidates (do not re-add without new evidence):
--   * levels/ui_character_selection/world: NO .package exists anywhere in the
--     game files (bundle listing evidence in HERO_SELECT_RESEARCH_173.md) --
--     cannot be residency-gated. Hub bundles only.
--   * levels/ui_store_preview/world: no managed load site in the whole
--     decompile (hub bundles only); mounting it mid-mission is the documented
--     Customize-gear-icon C-fatal (crash GUID ef637399, _gut_mission_inventory
--     docstring). Same class as ui_keep_menu (issue 336).
--
-- ============================================================================
-- SAFETY LADDER (no crash path)
-- ============================================================================
--   1. Setting = vanilla (default): the def is RESTORED to captured originals
--      on every open -- byte-identical vanilla behavior.
--   2. Alternate chosen: Application.can_get("package", pkg) is pcall'd first
--      -- the vanilla existence pre-check for loadable packages (11+ call
--      sites, e.g. cosmetic_utils.lua:133, hero_view_state_store.lua:2031). A
--      miss (future patch removes the package, or the check itself errors)
--      degrades to the vanilla backdrop for that open, with a printf.
--   3. Alternate applied: vanilla loads the alternate package itself and the
--      has_loaded gate + loading overlay + symmetric unload all run vanilla.
--      Worst case on a stalled load is vanilla's own worst case (overlay stays
--      up), never a mount of an unresident level.
--   4. Mod disabled: chained on_disabled restores the def originals, so a
--      disabled gut leaves the window fully vanilla.
--
-- HOOK PRE-FLIGHT (VMF no-duplicate-hook rule): whole-repo grep 2026-07-13 for
-- "HeroWindowCharacterPreview" -- gut_dev's only hit is a doc line in
-- HERO_SELECT_RESEARCH_173.md; no gut hook exists on this class anywhere. The
-- single mod:hook below is a singleton.
--
-- Module dofile's from gui_tweaker_dev.lua after the main chunk; returns
-- { rt_checks = ... } for the /gut_regression_test harness (native-loadouts
-- pattern). Chains mod.on_disabled (capture-prev idiom).

local _pf = rawget(_G, "printf") or function(fmt, ...) print(string.format(fmt, ...)) end

local SETTING_ID = "gut_inventory_backdrop"
local DEFS_PATH  = "scripts/ui/views/hero_view/windows/definitions/hero_window_character_preview_definitions"

-- Backdrop catalog. `object_sets` nil = spawn with none (script_world.lua:387
-- `object_sets or {}`); dark_camp mirrors the keep chest-opening viewport def
-- verbatim (hero_view_state_loot_definitions.lua:1113-1115).
local BACKDROPS = {
    dark_camp = {
        package     = "resource_packages/levels/ui_end_screen",
        level       = "levels/end_screen/world",
        env         = "environment/ui_end_screen",
        object_sets = { "flow_victory" },
    },
    victory_camp = {
        package     = "resource_packages/levels/ui_end_screen_victory",
        level       = "levels/end_screen_victory/world",
        env         = "environment/ui_end_screen",
        object_sets = nil,
    },
}
mod._gut_inv_backdrops = BACKDROPS   -- consumed by /gut_regression_test

-- The cached defs module's viewport style table -- the same table the window's
-- file-local viewport_widget_definition points into (see docstring).
local function _viewport_style()
    local loaded = package and package.loaded
    local defs = loaded and loaded[DEFS_PATH]
    local vp_widget = defs and defs.viewport_widget
    return vp_widget and vp_widget.style and vp_widget.style.viewport
end

-- Captured vanilla def values (once, before the first mutation). object_sets is
-- nil in the vanilla def (defs :217-251 carry no object_sets key) -- restoring
-- nil puts the key back to absent, which is the vanilla shape.
local _orig = nil
local function _capture(vp)
    if not _orig then
        _orig = {
            level_name          = vp.level_name,
            level_package_name  = vp.level_package_name,
            shading_environment = vp.shading_environment,
            object_sets         = vp.object_sets,
        }
    end
end

-- Write the chosen backdrop's triplet into the shared def (bd = catalog entry),
-- or restore the captured vanilla values (bd = nil). Allocates a fresh
-- object_sets table per apply so the shared def never aliases the catalog.
local function _apply(vp, bd)
    _capture(vp)
    if not bd then
        vp.level_name          = _orig.level_name
        vp.level_package_name  = _orig.level_package_name
        vp.shading_environment = _orig.shading_environment
        vp.object_sets         = _orig.object_sets
        return
    end
    vp.level_name          = bd.level
    vp.level_package_name  = bd.package
    vp.shading_environment = bd.env
    if bd.object_sets then
        local sets = {}
        for i = 1, #bd.object_sets do sets[i] = bd.object_sets[i] end
        vp.object_sets = sets
    else
        vp.object_sets = nil
    end
end
mod._gut_inv_backdrop_apply = _apply   -- rt-check source anchor (debug.getinfo)

-- Vanilla existence pre-check for the alternate's package: can_get("package",
-- name) is the resource type vanilla itself trusts (cosmetic_utils.lua:133 and
-- 10+ siblings). Returns true only on a clean, positive answer.
local function _package_gettable(pkg)
    local can_get = Application and Application.can_get
    if not can_get then return false end
    local ok, avail = pcall(can_get, "package", pkg)
    return (ok and avail == true) or false
end

-- Singleton pre-hook (full wrapper; always delegates). Mutates the shared def
-- BEFORE vanilla reads level_package_name from it (:100), so vanilla's own
-- load / has_loaded-gate / unload machinery handles the chosen package end to
-- end. Runs on EVERY window open, so flipping the dropdown between opens
-- always lands (vanilla choice actively restores the originals -- the def is
-- never left dirty across a selection change).
mod:hook("HeroWindowCharacterPreview", "create_ui_elements", function(func, self, ...)
    local choice = mod:get(SETTING_ID)
    local bd = (choice and choice ~= "vanilla") and BACKDROPS[choice] or nil
    local vp = _viewport_style()
    if not vp then
        if bd then
            _pf("[gut_dev:invbd] defs module not in package.loaded (path=%s) -> vanilla backdrop this open", DEFS_PATH)
        end
        return func(self, ...)
    end
    if bd and not _package_gettable(bd.package) then
        _pf("[gut_dev:invbd] backdrop '%s' package %s not gettable -> vanilla backdrop this open (issue 522 degrade path)",
            tostring(choice), bd.package)
        bd = nil
    end
    _apply(vp, bd)
    if bd then
        _pf("[gut_dev:invbd] inventory preview backdrop SWAP: %s (level=%s pkg=%s env=%s sets=%d) -- vanilla load/has_loaded gate handles residency",
            tostring(choice), bd.level, bd.package, bd.env, bd.object_sets and #bd.object_sets or 0)
    end
    return func(self, ...)
end)

-- Mod disabled -> put the shared def back to vanilla (VMF disables the hook
-- above with the mod, so nothing would re-apply/restore afterwards; without
-- this a dirty def would keep swapping the backdrop while gut is off).
local _prev_on_disabled = mod.on_disabled
mod.on_disabled = function(...)
    if _prev_on_disabled then _prev_on_disabled(...) end
    if _orig then
        local vp = _viewport_style()
        if vp then
            _apply(vp, nil)
            _pf("[gut_dev:invbd] mod disabled -> inventory preview def restored to vanilla")
        end
    end
end

-- ============================================================
-- rt checks (registered by the main chunk via the returned table)
-- ============================================================
-- (#511) local io-safe source reader (the main chunk's _rt_src_read is a
-- file-local there; same guard, retail sandbox has no io library).
local function _src_read(path)
    local io_lib = rawget(_G, "io")
    if type(io_lib) ~= "table" or type(io_lib.open) ~= "function" then return nil end
    local f = io_lib.open(path, "r")
    if not f then return nil end
    local t = f:read("*a")
    f:close()
    return t
end

local M = { rt_checks = {} }

M.rt_checks[#M.rt_checks + 1] = {
    name = "inventory_backdrop_swap_522",
    fn = function()
        -- Runtime markers: catalog wired + shaped, vanilla surface intact.
        local cat = mod._gut_inv_backdrops
        if type(cat) ~= "table" then return "backdrop catalog missing (module not wired)" end
        for _, key in ipairs({ "dark_camp", "victory_camp" }) do
            local bd = cat[key]
            if type(bd) ~= "table" then return key .. " missing from the backdrop catalog" end
            if type(bd.package) ~= "string" or not bd.package:find("resource_packages/levels/", 1, true) then
                return key .. ": package is not a resource_packages/levels/ path (package:load needs a .package path)"
            end
            if type(bd.level) ~= "string" or bd.level:sub(1, 7) ~= "levels/" then
                return key .. ": level path malformed"
            end
            if type(bd.env) ~= "string" or bd.env:sub(1, 12) ~= "environment/" then
                return key .. ": shading environment malformed"
            end
        end
        local choice = mod:get(SETTING_ID)
        if choice ~= nil and choice ~= "vanilla" and cat[choice] == nil then
            return "dropdown value '" .. tostring(choice) .. "' has no catalog entry (open would silently fall back)"
        end
        local w = rawget(_G, "HeroWindowCharacterPreview")
        if type(w) ~= "table" then return "HeroWindowCharacterPreview class missing (vanilla drift; hook orphaned)" end
        if type(w.create_ui_elements) ~= "function" then return "create_ui_elements missing (vanilla drift; swap hook orphaned)" end
        if type(w.post_update) ~= "function" then return "post_update missing (vanilla drift; the has_loaded widget gate lives there)" end
        if type(mod._gut_inv_backdrop_apply) ~= "function" then return "_gut_inv_backdrop_apply not wired" end
        -- Source needles (dev/CI only; io-safe skip in retail). Split so this
        -- check cannot self-match.
        local ok, info = pcall(debug.getinfo, mod._gut_inv_backdrop_apply, "S")
        if not ok or type(info) ~= "table" or not info.source then return end
        local path = info.source:sub(1, 1) == "@" and info.source:sub(2) or info.source
        local txt = _src_read(path)
        if not txt then return end
        if not txt:find('can_get, "pack' .. 'age"', 1, true) then
            return "issue 522 regression: the can_get('package') existence gate is gone (a removed package would hit PackageManager.load unchecked)"
        end
        if not txt:find("vp.level_package" .. "_name  = bd.package", 1, true) then
            return "issue 522 regression: the def swap no longer routes the package through vanilla's load/has_loaded gate"
        end
    end,
}

return M
