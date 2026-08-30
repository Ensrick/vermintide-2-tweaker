-- _cim_mission_forge_safety.lua -- mid-mission forge / customization render safety.
--
-- Owns every guard that lets the Athanor (repurposed weave forge) and the
-- gear-icon item-customization preview OPEN WITHOUT CRASHING while the player is
-- in a MISSION, where the keep-only render resources are not resident. Families:
--   * shading_environment substitution (keep-only ui_weave_forge_preview env ->
--     a residency-probed mission env; issue 83/228/235, the uncatchable-AV class),
--   * HeroWindowItemCustomization preview-level strip + blend-variation pin,
--   * HeroViewStateWeaveForge gamepad-GUI guard + get_ui_renderer fallback,
--   * HeroView HDR-gui skip + hdr_renderer/hdr_top_renderer fallback (issue 73,
--     the Loremaster's Armoury armoury_atlas HDR-world crash), and the HDR-glow /
--     skilltree-ring / bloom-pulse / upgrade-anim draw-site suppressors (Fix B..B5).
-- Every guard gates on _is_in_keep(): the KEEP path is byte-unchanged (full HDR).
--
-- Extracted verbatim from crafting_in_modded_dev.lua (v0.8.55-dev OOP split,
-- PROJECT_STANDARDS 2.2a). Publishes the mid-mission helpers on the established
-- flat mod._cim_* namespace (cross-file surface consumed by cim_debug.lua's
-- on_enter re-suppression and the HDR checks in
-- `_cim_regression_forge_surfaces.lua`).
-- The issue-88 inventory-access HeroView.on_enter hook stays in the entry (it
-- shares the entry-local _cim_open_standard_inv_pending with open_standard_crafting).
--
-- Owned by: crafting_in_modded_dev.lua entry point. Consumed via: mod:dofile
-- (manifest, exactly once -- NOT a singleton). One hook per (Class, method) mod-wide.
local mod = get_mod("cim_dev")

-- Local copy of the entry's routine debug-logging helper (PROJECT_STANDARDS 3.6):
-- routes through VMF's debug channel, file only, gated by VMF output_mode.
local function _dbg(fmt, ...)
    mod:debug("[cim:dbg] " .. fmt, ...)
end
-- ============================================================
-- Mid-mission forge: shading_environment substitution
-- ============================================================
-- The three weave-forge windows (`HeroWindowWeaveForgeOverview`,
-- `HeroWindowWeaveForgeWeapons`, `HeroWindowWeaveProperties`) hardcode
-- `shading_environment = "environment/ui_weave_forge_preview"` in their
-- `_create_viewport_definition`. That resource is only packaged with the
-- keep level — mission bundles don't load it — and the engine fatals on
-- the first viewport setup with:
--   [Engine Error]: Resource not loaded, type: #ID[fe73c7dcff8a7ca5]
--   ('shading_environment'), name: #ID[77526267a1844129]
--   ('environment/ui_weave_forge_preview')
-- (Both hashes brute-confirmed via the bundle unpacker per
-- `reference_vt2_hash_reverse_lookup`.)
--
-- Workaround: hook each window's `_create_viewport_definition` with a
-- full mod:hook wrapper. Call the original, then if we're NOT in the
-- keep, rewrite the returned table's `style.viewport.shading_environment`
-- to a MISSION-RESIDENT env (picker below). Visual fidelity drops a bit
-- mid-mission (the forge lighting won't match the keep aesthetic) but no
-- crash.
--
-- ALSO swap the `_inverted` variant (HeroWindowWeaveForgeOverview takes
-- an `invert_rendering` arg that picks `_preview_inverted`). Same env
-- isn't in mission bundles either.
--
-- The hook always fires (vanilla never opens the forge in mission so
-- there's no path to clobber); gated on `not is_in_inn` so the keep
-- forge keeps its proper lighting.
--
-- v0.8.48-dev (#83 re-enable): the substitute is no longer the fixed
-- "environment/ui_hdr". Two findings from the #228/#235 investigation
-- (cosmetics_tweaker 0.9.62..0.9.66-dev) improved the choice:
--   * ui_hdr is a 2D-UI tonemapping env with no 3D radiance — item
--     previews render pure BLACK on it mid-mission (#235 instrument
--     data: a 160x exposure boost stayed black, host log 2026-07-03).
--   * environment/ui_store_preview (the keep's studio-lit item-preview
--     env) probed RESIDENT mid-mission (Application.can_get, same log)
--     and is the env that defines the per-weapon blend variations, so
--     it is both lit and blend-safe.
--   * environment/blank is the engine default (GameSettingsDevelopment.
--     default_environment, game_settings_development.lua:33), created at
--     boot from resource_packages/boot_assets (boot.lua:137/598); it is
--     resident in EVERY context and is what vanilla's own gamepad forge
--     world uses (hero_view_state_weave_forge.lua:145). Flat lighting,
--     structurally crash-free — the final fallback.
-- Preference: ui_store_preview (lit) -> ui_hdr (proven mountable) ->
-- blank. Residency is probed at USE time (it can differ per level) via
-- Application.can_get("shading_environment", name) — vanilla's
-- non-faulting existence check (pickup_system.lua:882 pattern),
-- pcall-wrapped so an unsupported type string can never fatal.
local _FORGE_ENV_FALLBACK = "environment/blank"
local _FORGE_ENV_CANDIDATES = { "environment/ui_store_preview", "environment/ui_hdr" }

local function _cim_env_resident(name)
    local residency = mod._cim_resource_residency
    return residency and type(residency.shading_environment_resident) == "function"
        and residency.shading_environment_resident(
            name, Application, nil, "cim_mission_forge") == true
end

-- Parameterized + exposed so /cim_regression_test can drive the preference
-- order with an injected probe (the real probe needs a live engine).
function mod._cim_pick_mission_env(resident_fn)
    resident_fn = resident_fn or _cim_env_resident
    for _, name in ipairs(_FORGE_ENV_CANDIDATES) do
        if resident_fn(name) then return name end
    end
    return _FORGE_ENV_FALLBACK
end

local function _is_in_keep()
    return DamageUtils and DamageUtils.is_in_inn and true or false
end

-- Exposed for cross-file callers (e.g. cim_debug.lua's HeroWindowWeaveProperties
-- on_enter hook, which re-suppresses the skill-tree cluster HDR glow after
-- _create_slot_grid re-appends it — Fix B2). cim_debug.lua loads via mod.dofile
-- BEFORE this line runs, but its hook BODIES only execute at runtime (in-game),
-- by which point this assignment has long completed.
mod._cim_is_in_keep = _is_in_keep

local function _swap_forge_env(viewport_def)
    if _is_in_keep() then return viewport_def end
    if type(viewport_def) ~= "table" then return viewport_def end
    local style = viewport_def.style
    local vp = style and style.viewport
    if vp and (vp.shading_environment == "environment/ui_weave_forge_preview"
            or vp.shading_environment == "environment/ui_weave_forge_preview_inverted") then
        local picked = mod._cim_pick_mission_env()
        -- Always-on dev probe (#83): which env each mission forge world gets,
        -- with the residency readouts that drove the choice. printf reaches the
        -- console log even with mod-logging off.
        if printf then
            printf("[cim:83] forge viewport env: %s -> %s (resident: store=%s hdr=%s)",
                tostring(vp.shading_environment), picked,
                tostring(_cim_env_resident("environment/ui_store_preview")),
                tostring(_cim_env_resident("environment/ui_hdr")))
        end
        vp.shading_environment = picked
    end
    return viewport_def
end

mod:hook("HeroWindowWeaveForgeOverview", "_create_viewport_definition", function(func, self, scenegraph_id, invert_rendering)
    local definition = func(self, scenegraph_id, invert_rendering)
    -- #882: retain the native viewport role before the mission-safe environment
    -- substitution erases the only visual distinction between primary and
    -- secondary. UIWidget.init preserves definition.content on widget.content.
    mod._cim_forge_preview_policy.mark_overview_viewport_role(
        definition, invert_rendering)
    return _swap_forge_env(definition)
end)

-- #882: the native overview gives both equipped weapons x=-0.8 and mirrors the
-- secondary viewport through the keep-only `_inverted` shading environment.
-- Mission safety replaces both keep environments with one resident fallback,
-- removing that mirror and placing secondary directly over primary. Preserve
-- the viewport role captured above instead of inferring it from item.slot_type:
-- dual-melee careers and cross-slot loadouts make that inference false.
mod:hook("HeroWindowWeaveForgeOverview", "_create_item_previewer",
    function(func, self, viewport_widget, item, x_offset, invert_start_rotation)
        local data = item and item.data
        local adjusted_x, mirrored_viewport =
            mod._cim_forge_preview_policy.overview_preview_x_from_widget(
                viewport_widget, x_offset, _is_in_keep())
        if adjusted_x ~= x_offset and printf then
            printf("[cim:882] mission overview secondary preview mirrored key=%s native_x=%.3f target_x=%.3f",
                tostring((data and data.key) or (item and item.key) or "<?>"),
                tonumber(x_offset) or 0, tonumber(adjusted_x) or 0)
        end
        local preview_runtime = mod._cim_forge_preview
        if type(preview_runtime) == "table"
                and type(preview_runtime.invoke_constructor) == "function" then
            return preview_runtime.invoke_constructor(mod, "overview", func, self,
                viewport_widget, item, adjusted_x, invert_start_rotation)
        end
        return func(self, viewport_widget, item, adjusted_x, invert_start_rotation)
    end)

mod:hook("HeroWindowWeaveForgeWeapons", "_create_viewport_definition", function(func, self, scenegraph_id)
    return _swap_forge_env(func(self, scenegraph_id))
end)

mod:hook("HeroWindowWeaveProperties", "_create_viewport_definition", function(func, self)
    return _swap_forge_env(func(self))
end)

-- ============================================================
-- Mid-mission forge: dynamic list-widget material closure (#83)
-- ============================================================
-- `HeroWindowWeaveForgeWeapons._setup_weapon_stats` creates a fresh local
-- widget array every time the selected item changes, then assigns it to
-- `self._scrollbars.stats.list_widgets`. These widgets do not exist when the
-- create_ui_elements guard below prunes the static arrays. The shipped crash
-- (session 10bc42ac-d630-48e0-95d8-f5de4cdc727c) was one such late widget:
-- its rotated_texture pass tried to draw raw `icon_block_arch_masked` on the
-- mission ui_top_renderer, whose Gui did not own that material.
--
-- Renderer-proof every texture-bearing pass in every dynamic scrollbar list
-- immediately after the vanilla producer finishes. Unsafe passes receive an
-- always-false content check; text/hotspots and renderer-proven textures remain
-- byte-unchanged. This is producer-boundary protection, not a broad _draw or
-- UIRenderer hook. The Keep path is untouched.
function mod._cim83_sanitize_dynamic_forge_widgets(window, in_keep)
    if in_keep or type(window) ~= "table" then return nil end
    local policy = mod._cim83_forge_widget_policy
    local icon_policy = mod._cim_athanor_icon_policy
    local scrollbars = window._scrollbars
    local renderer = window._ui_top_renderer
    if type(policy) ~= "table" or type(policy.sanitize_widgets) ~= "function"
            or type(icon_policy) ~= "table"
            or type(icon_policy.renderer_has_texture) ~= "function"
            or type(scrollbars) ~= "table" then
        return nil
    end

    local combined = { widgets_scanned = 0, texture_passes = 0, verified = 0,
        suppressed = 0, materials = {} }
    local material_seen = {}
    local function has_texture(texture, flags)
        local target = renderer
        if flags and flags.retained and type(renderer) == "table"
                and renderer.gui_retained ~= nil then
            target = { gui = renderer.gui_retained }
        end
        return icon_policy.renderer_has_texture(
            target, texture, UIAtlasHelper, Gui, flags)
    end

    for _, scrollbar in pairs(scrollbars) do
        local widgets = type(scrollbar) == "table" and scrollbar.list_widgets
        if type(widgets) == "table" then
            local report = policy.sanitize_widgets(widgets, has_texture)
            combined.widgets_scanned = combined.widgets_scanned + report.widgets_scanned
            combined.texture_passes = combined.texture_passes + report.texture_passes
            combined.verified = combined.verified + report.verified
            combined.suppressed = combined.suppressed + report.suppressed
            for i = 1, #report.materials do
                local name = report.materials[i]
                if not material_seen[name] then
                    material_seen[name] = true
                    combined.materials[#combined.materials + 1] = name
                end
            end
        end
    end

    if combined.suppressed > 0 and printf then
        window._cim83_reported_materials = window._cim83_reported_materials or {}
        for i = 1, #combined.materials do
            local texture = combined.materials[i]
            if not window._cim83_reported_materials[texture] then
                window._cim83_reported_materials[texture] = true
                printf("[cim:83] suppressed non-resident dynamic forge material: %s",
                    tostring(texture))
            end
        end
    end
    return combined
end

mod:hook("HeroWindowWeaveForgeWeapons", "_setup_weapon_stats", function(func, self, ...)
    return mod._cim83_forge_widget_policy.call_then(
        function(...) return func(self, ...) end,
        function() mod._cim83_sanitize_dynamic_forge_widgets(self, _is_in_keep()) end,
        ...)
end)

-- Diagnostics only (#83 re-enable). The ONE remaining ShadingEnvironment
-- write on the weave-forge surface is set_fullscreen_effect_enable_state:
-- set_scalar("fullscreen_blur_*") + apply on the BASE ui world's env
-- (hero_view_state_weave_forge.lua:879-881, vanilla nil-guards the env).
-- Never implicated in a crash, but if the user's in-mission test still dies
-- on a shading path this breadcrumb says whether the blur toggle fired.
-- hook_safe post-fire, printf-only, no behavior change.
-- Pre-flight (repo hook rule): cim hooks HeroViewStateWeaveForge.
-- set_fullscreen_effect_enable_state NOWHERE else (grep 2026-07-05).
mod:hook_safe("HeroViewStateWeaveForge", "set_fullscreen_effect_enable_state", function(self, enabled)
    if _is_in_keep() then return end
    if printf then
        printf("[cim:83] weave-forge set_fullscreen_effect_enable_state(%s) fired in mission", tostring(enabled))
    end
end)

-- ============================================================
-- Mid-mission item customization: preview-level substitution
-- ============================================================
-- HeroWindowItemCustomization is the gear-icon "Customize" screen on
-- the loadout panel (illusion swap + reroll properties / traits).
-- Vanilla `_create_item_preview_widget_definition` hard-codes
--   level_name          = "levels/ui_store_preview/world"
--   shading_environment = "environment/ui_store_preview"
--   object_sets         = LevelResource.object_set_names("levels/ui_store_preview/world")
-- That level is loaded as a transitive dep of the inn bundle, not by
-- any mission level. Mid-mission, opening the gear icon fatals at
-- `object_set_names`:
--   hero_window_item_customization.lua:357: Level not loaded:
--   levels/ui_store_preview/world
-- Crash GUID ef637399-8862-46dc-b7fb-8c6f9c475cf4 (dlc_dwarf_interior,
-- 2026-05-24). gt_open_mission_inventory had blocked Chaos Wastes only
-- (CW levels exhibit the same fault for the same reason); regular
-- adventure missions fell straight through to the crash.
--
-- Loading the package on demand isn't viable — its package name doesn't
-- hash to any file in the game's `bundle/` directory (verified against
-- every plausible spelling via the bundle unpacker), so it's a
-- transitive dep with no exposed handle a mod can pass to
-- `Managers.package:load`. Substitute strategy mirrors the weave-forge
-- env swap above: strip the level reference entirely mid-mission.
-- Without `level_name`, `ScriptWorld.spawn_level` (ui_passes.lua:2456)
-- is skipped and the viewport gets just a world + shading environment.
-- The item still renders because `LootItemUnitPreviewer` uses
-- `resource_packages/levels/ui_loot_preview`, which is in
-- `GlobalResources` (boot_init.lua:159) and therefore loaded
-- everywhere.
--
-- Two call sites that touch the level:
--   1. `_create_item_preview_widget_definition` — strip `level_name`
--      + `object_sets`; swap `shading_environment` to the mission-safe
--      env when the store-preview env is requested.
--   2. `_register_object_sets` — vanilla calls
--      `LevelResource.object_set_names(level_name)` again. When the
--      level was stripped, skip the call and seed an empty
--      `object_set_data`. Vanilla's immediate trailing
--      `_show_object_set(nil, true)` iterates that empty table and
--      no-ops.
--
-- Visual cost: clean empty backdrop instead of the keep's store-studio
-- lighting. The item itself spins / re-skins / re-rolls exactly as in
-- the keep. Keep behavior unchanged (gated on `_is_in_keep()`).

mod:hook("HeroWindowItemCustomization", "_create_item_preview_widget_definition", function(func, self)
    if _is_in_keep() then return func(self) end

    -- Mid-mission: SKIP the vanilla call entirely. Vanilla's body
    -- (hero_window_item_customization.lua:382-435) calls
    -- `LevelResource.object_set_names("levels/ui_store_preview/world")` at
    -- line 410 while building the style table — that fatals because the
    -- preview level isn't loaded in any mission. Previous implementation
    -- called vanilla then post-stripped level_name/object_sets, but the
    -- crash fires inside vanilla BEFORE the strip can run. User report
    -- 2026-05-25 + crash GUID 3bd92d07 (issue #50).
    --
    -- Substitute: mirror vanilla's widget shape exactly, minus level_name
    -- and object_sets. shading_environment comes from the residency-probed
    -- mission-env picker (_cim_pick_mission_env above) — preferring the
    -- studio-lit environment/ui_store_preview when resident, so the
    -- mid-mission 3D preview is LIT instead of ui_hdr-black (#235).
    -- LootItemUnitPreviewer still renders the item via
    -- `resource_packages/levels/ui_loot_preview` which is in
    -- GlobalResources (boot_init.lua:159).
    return {
        element = {
            passes = {
                { pass_type = "viewport",  style_id    = "viewport"        },
                { content_id = "button_hotspot", pass_type = "hotspot"     },
            },
        },
        content = {
            activated     = true,
            button_hotspot = {},
        },
        style = {
            viewport = {
                enable_sub_gui      = true,
                fov                 = 65,
                layer               = 962,
                shading_environment = mod._cim_pick_mission_env(),
                viewport_name       = "item_preview",
                viewport_type       = "default_forward",
                world_name          = "item_preview",
                camera_position     = { 0, 0, 0 },
                camera_lookat       = { 0, 0, 0 },
            },
        },
        offset        = { 0, 0, 0 },
        scenegraph_id = "item_preview",
    }
end)

mod:hook("HeroWindowItemCustomization", "_register_object_sets", function(func, self, viewport_widget, viewport_definition)
    local vp = viewport_definition and viewport_definition.style and viewport_definition.style.viewport
    if vp and vp.level_name then
        return func(self, viewport_widget, viewport_definition)
    end
    -- Mid-mission path: viewport has no level. Seed an empty
    -- object_set_data so vanilla's _show_object_set(nil, true) below
    -- iterates an empty pairs() and exits cleanly. World/level still
    -- read from pass_data in case downstream code dereferences them.
    local element = viewport_widget.element
    local pass_data = element and element.pass_data and element.pass_data[1]
    viewport_widget.content.object_set_data = {
        world = pass_data and pass_data.world or nil,
        level = pass_data and pass_data.level or nil,
        object_sets = {},
        level_name = nil,
    }
    self:_show_object_set(nil, true)
end)

-- ------------------------------------------------------------
-- Mid-mission item customization: blend-variation pin (#83 / #228 class)
-- ------------------------------------------------------------
-- THE root cause of the "script_world blend" fatal that forced the v0.8.23
-- keep-only Athanor gate, per the corrected #228/#235 analysis
-- (cosmetics_tweaker 0.9.66-dev): `ScriptWorld.render` blends the world's
-- `shading_settings` every frame (script_world.lua:122); vanilla
-- `_present_item` -> `_update_environment` writes a PER-WEAPON variation
-- (`weapons_default_01`, hero_window_item_customization.lua:1377-1381 /
-- :583-594) into that blend target. On the keep's env that variation is
-- defined; on the mission-substituted world it may not be — and native
-- `ShadingEnvironment.blend` on an UNDEFINED variation is an access
-- violation (0xc0000005), not a catchable Lua error. (A missing env
-- RESOURCE, by contrast, is a clean "Resource not loaded" fatal — the
-- original forge symptom above.) The weave-forge windows themselves never
-- write blend variations (grep-verified: their only ShadingEnvironment
-- call is the set_scalar blur toggle in set_fullscreen_effect_enable_state),
-- so `_update_environment` is the SOLE writer on the forge/customization
-- surface, and this one hook covers every re-present (reroll / illusion tabs).
--
-- Decision: allow vanilla's requested variation only when the preview
-- world's env actually defines it — i.e. environment/ui_store_preview
-- (keep witnesses: store_window_item_preview.lua:88+1367,
-- hero_window_gotwf_item_preview.lua:67+607,
-- hero_window_item_customization.lua:406+1378) — or when cosmetics_tweaker's
-- #235 re-point already moved the world onto it (World data flag
-- `cos_preview_env_repointed`, cosmetics_tweaker.lua ~2690). Anything else
-- (ui_hdr, blank, unknown) pins force_default=true so the blend only ever
-- asks for "default", which every create_world env carries
-- (world_manager.lua:44 hard-codes the "default" mood).
--
-- Cross-mod: cosmetics_tweaker hooks this same method with the same
-- fail-safe direction; VMF chains hooks from DIFFERENT mods, and once any
-- layer passes force_default=true the pin sticks — co-installation is safe
-- in both orders.
-- Pre-flight (repo hook rule): cim hooks HeroWindowItemCustomization.
-- _update_environment NOWHERE else (grep 2026-07-05: existing cim hooks on
-- this class are _create_item_preview_widget_definition,
-- _register_object_sets, _enable_craft_button, _on_illusion_index_pressed,
-- _update_state_craft_button, _update_property_option, on_enter).
--
-- Exposed decision helper so /cim_regression_test can pin the truth table.
function mod._cim_env_allows_variation(env_name, repointed)
    return env_name == "environment/ui_store_preview" or repointed == true
end

mod:hook("HeroWindowItemCustomization", "_update_environment", function(func, self, item_preview_environment, force_default)
    if _is_in_keep() then
        return func(self, item_preview_environment, force_default)
    end
    local pw = self and self._preview_widget
    local vp_style = pw and pw.style and pw.style.viewport
    local env_name = vp_style and vp_style.shading_environment
    local world = pw and pw.element and pw.element.pass_data and pw.element.pass_data[1]
        and pw.element.pass_data[1].world
    local repointed = (world and World.has_data(world, "cos_preview_env_repointed")
        and World.get_data(world, "cos_preview_env_repointed")) or false
    local allow = mod._cim_env_allows_variation(env_name, repointed)
    -- Always-on dev probe (#83): one line per distinct requested env.
    if printf then
        mod._cim_seen_variation_req = mod._cim_seen_variation_req or {}
        local k = tostring(item_preview_environment) .. "|" .. tostring(env_name)
        if not mod._cim_seen_variation_req[k] then
            mod._cim_seen_variation_req[k] = true
            printf("[cim:83] _update_environment(mission): requested=%s world_env=%s repointed=%s -> %s",
                tostring(item_preview_environment), tostring(env_name), tostring(repointed),
                allow and "ALLOW (env defines it)" or "pin \"default\" (AV-safe)")
        end
    end
    if allow then
        return func(self, item_preview_environment, force_default)
    end
    return func(self, item_preview_environment, true)
end)

-- ============================================================
-- Mid-mission forge: gamepad GUI setup + cursor renderer guard
-- ============================================================
-- Crash trace (skittergate level, Steam Controller plugged in, cim open_forge):
--
--   hero_view_state_weave_forge.lua:120: attempt to index field '_gui_data' (a nil value)
--   [1] get_ui_renderer:120
--   [2] draw_gamepad_cursor:784
--   [3] hook_chain:628  (state update path)
--
-- Vanilla `_setup_gamepad_gui` (`hero_view_state_weave_forge.lua:141-154`)
-- gates the entire body on `if self.is_in_inn then ... self._gui_data = ... end`.
-- In mission `is_in_inn` is false, so `_gui_data` is never assigned. When the
-- player has any gamepad-class input device active (Steam Controller, vJoy, an
-- actual gamepad), `_gamepad_style_active` is true and `get_ui_renderer` later
-- dereferences `_gui_data.bottom.renderer` → fatal.
--
-- The v0.7.13 shading_environment swap let the forge windows mount in mission,
-- but didn't address this gate. Two-layer fix:
--
-- 1. Hook `_setup_gamepad_gui` and temporarily flip `self.is_in_inn = true` for
--    the duration of the call so the gui_data branch runs. The renderer's
--    `is_in_inn` arg ends up true too, which matches what every other code
--    path inside the forge expects.
-- 2. Defensive guard on `get_ui_renderer`: if for any reason `_gui_data` is
--    still nil when the cursor draws, fall back to the parent's `ui_renderer`.
--    Gamepad cursor visuals may be slightly off but the menu stays usable
--    and no crash.

mod:hook("HeroViewStateWeaveForge", "_setup_gamepad_gui", function(func, self, ...)
    if self.is_in_inn then
        return func(self, ...)
    end
    -- Temporarily lie to the gate so the gui_data path runs. Restore afterwards
    -- so vanilla code outside this hook continues to see the truthful flag.
    self.is_in_inn = true
    local ok, err = pcall(func, self, ...)
    self.is_in_inn = false
    if not ok then
        mod:info("[cim] _setup_gamepad_gui in mission failed: %s", tostring(err))
    end
end)

mod:hook("HeroViewStateWeaveForge", "get_ui_renderer", function(func, self, ...)
    -- Vanilla only crashes when gamepad style is active AND gui_data missing.
    -- Mirror that condition exactly so non-crash paths stay unchanged.
    if self._gamepad_style_active and not self._gui_data then
        return self.ui_renderer
    end
    return func(self, ...)
end)

-- ------------------------------------------------------------
-- Mid-mission forge: parent HeroView HDR gui setup + renderer guard
-- ------------------------------------------------------------
-- Crash trace (user 2026-06-07, in mission, cim open_forge with Allow in
-- mission enabled):
--
--   hero_view.lua:175: attempt to index local 'hdr_gui_data' (a nil value)
--   (HeroView.hdr_renderer / HeroView.hdr_top_renderer — line number shifts by
--    game build; the cited local is `self._hdr_gui_data` being indexed.)
--
-- Same bug class as the _setup_gamepad_gui fix above, but one level UP on the
-- parent HeroView instead of the forge state. Vanilla `HeroView._setup_hdr_gui`
-- (hero_view.lua:136-165) gates its ENTIRE body on
-- `if self.is_in_inn then ... self._hdr_gui_data = ... end`. In mission
-- is_in_inn is false, so `_hdr_gui_data` is never built. The Athanor forge
-- windows (HeroWindowWeaveForgeOverview/Panel/Weapons, HeroWindowWeaveProperties)
-- call `parent:hdr_renderer()` / `parent:hdr_top_renderer()` every draw frame,
-- and those accessors (hero_view.lua:183-195) do
-- `local hdr_data = self._hdr_gui_data.bottom` → fatal nil-index.
--
-- Why the hook fires: cim's open_forge does
-- `transition_with_fade("hero_view_force", {menu_state_name="weave_forge"})`
-- with NO force_ingame_menu, so HeroView.on_enter (hero_view.lua:278) takes the
-- `not self._force_ingame_menu` branch and DOES call _setup_hdr_gui. (The
-- game's own in-mission ESC→character path sets force_ingame_menu=IS_WINDOWS at
-- ingame_ui.lua:642 and skips it — but that path doesn't open the forge.)
--
-- Cleanup is leak-safe: HeroView.destroy_hdr_gui (hero_view.lua:639) guards on
-- `if self._hdr_gui_data then ... Managers.world:destroy_world(world) end` — NOT
-- on is_in_inn — so the HDR worlds we build in mission are torn down on view
-- close.
--
-- Two-layer fix:
--   1. Hook _setup_hdr_gui; in mission, SKIP the vanilla call entirely so the
--      HDR worlds are NEVER built mid-mission. (Superseded the earlier
--      flip-is_in_inn-and-force-build approach in v0.8.16-dev — force-building
--      the worlds is exactly what crashes when Loremaster's Armoury injects its
--      global armoury_atlas into the fresh world; see the hook body below.)
--   2. Defensive guard on hdr_renderer/hdr_top_renderer: with _hdr_gui_data left
--      nil in mission (step 1), these fall back to the view's own
--      ui_renderer/ui_top_renderer so the forge stays usable. This is now the
--      NORMAL in-mission path, not just a failsafe — it drops the HDR glow layer
--      in mission only but is crash-safe.
-- Regression: heroview_hdr_renderer_guard_failsafe +
-- heroview_hdr_not_forcebuilt_in_mission (/cim_regression_test).
-- v0.7.73 (Issue #73): destroy-on-failure sweep — RETAINED as a no-op safety net.
-- With Fix B (v0.8.16-dev) the in-mission path no longer builds the HDR worlds,
-- so this is no longer reached on the mission path; it stays in case any future
-- path force-builds and fails. Historic rationale: if a pcall'd vanilla call
-- fails AFTER creating a world but BEFORE `self._hdr_gui_data = hdr_gui_data`
-- (vanilla's last statement, hero_view.lua:163), the half-built world is leaked
-- unreferenced — destroy_hdr_gui never releases it and the NEXT forge open dies
-- on world_manager's "World already exists" fassert (engine-fatal, bypasses
-- pcall). Sweep by name: WorldManager.destroy_world accepts the name string
-- (world_manager.lua:64) and destroying the world releases its viewport/guis
-- engine-side. Parameterized for the regression test
-- (heroview_hdr_failed_setup_sweeps_leaked_worlds).
local _HDR_WORLD_NAMES = { "hero_view_hdr", "hero_view_hdr_top" }
function mod._cim_sweep_leaked_hdr_worlds(world_manager, hdr_gui_data)
    if hdr_gui_data then return 0 end  -- worlds are referenced; destroy_hdr_gui owns them
    if not (world_manager and world_manager.has_world and world_manager.destroy_world) then return 0 end
    local swept = 0
    for _, world_name in ipairs(_HDR_WORLD_NAMES) do
        if world_manager:has_world(world_name) then
            local destroy_ok = pcall(function() world_manager:destroy_world(world_name) end)
            -- Ungated: this only runs on an already-failing path the user needs
            -- to see in the log without Debug Logging on.
            mod:warning("[cim] swept half-built HDR world '%s' after failed in-mission setup (destroy ok=%s)",
                world_name, tostring(destroy_ok))
            swept = swept + 1
        end
    end
    return swept
end

mod:hook("HeroView", "_setup_hdr_gui", function(func, self, ...)
    if self.is_in_inn then
        return func(self, ...)
    end
    -- v0.8.16-dev (Issue: LA armoury_atlas HDR-world crash) — DO NOT force-build
    -- the in-mission HDR worlds anymore.
    --
    -- Previous behavior flipped is_in_inn=true and pcall'd vanilla so the
    -- `hero_view_hdr` / `hero_view_hdr_top` worlds were created mid-mission to
    -- get the forge's HDR glow layer. That is the crash trigger when
    -- Loremaster's Armoury is installed: building those worlds calls
    -- UIRenderer.create_screen_gui, and VMF's custom_textures
    -- (custom_textures.lua:228) injects every mod-registered GLOBAL UI texture —
    -- including LA's `materials/Loremasters-Armoury/armoury_atlas` — into the
    -- brand-new world. A mid-mission world cannot resolve that global atlas, so
    -- the engine fatally asserts at c_api_world.cpp:568
    -- (`world.resource_manager().can_get(material_type, name)`). Because that is a
    -- C-level assert, NOT a Lua error, the old code's pcall around vanilla could
    -- not catch it -> hard crash (session b688f241, 2026-06-22). Repros ONLY with
    -- LA installed +
    -- `allow_in_mission` ON (the opt-in path the menu already labels "may crash").
    --
    -- Fix B (stable, lower-risk): in mission, skip vanilla _setup_hdr_gui
    -- entirely. _hdr_gui_data stays nil, so the hdr_renderer / hdr_top_renderer
    -- hooks below (the heroview_hdr_renderer_guard_failsafe fallback) return
    -- self.ui_renderer / self.ui_top_renderer. The forge opens against the
    -- standard renderer instead of the LA-incompatible HDR world — it drops the
    -- HDR glow layer IN MISSION ONLY, but never calls create_screen_gui on a
    -- world that can't host LA's material. The keep (is_in_inn) path above is
    -- unchanged: full HDR there.
    --
    -- The leaked-world sweep (mod._cim_sweep_leaked_hdr_worlds, Issue #73) is
    -- retained as a no-op safety net but is no longer reached on this path since
    -- we never build the worlds in mission.
    _dbg("HeroView._setup_hdr_gui skipped in mission (Fix B: avoid LA armoury_atlas HDR-world crash); using ui_renderer fallback")
end)

mod:hook("HeroView", "hdr_renderer", function(func, self, ...)
    if not self._hdr_gui_data then
        return self.ui_renderer
    end
    return func(self, ...)
end)

mod:hook("HeroView", "hdr_top_renderer", function(func, self, ...)
    if not self._hdr_gui_data then
        return self.ui_top_renderer
    end
    return func(self, ...)
end)

-- ------------------------------------------------------------
-- Mid-mission forge: suppress the keep-only HDR glow widgets at the draw site
-- ------------------------------------------------------------
-- v0.8.17-dev (Issue: weave_menu_* "Material not found in Gui" cascade) —
-- completes Fix B's "drops the HDR glow layer in mission only" contract at the
-- DRAW SITE.
--
-- After Fix B (v0.8.16-dev), the in-mission forge no longer builds the keep's
-- HDR worlds; `_hdr_gui_data` stays nil and the hdr_renderer / hdr_top_renderer
-- hooks above fall through to the BASE mission renderer (self.ui_renderer /
-- self.ui_top_renderer). That base renderer is created once at IngameUI.init
-- (ingame_ui.lua:76-77) with is_in_inn=false, so the inn-only material block in
-- ingame_ui_settings.lua is skipped — and three RAW (non-atlas) materials the
-- forge's HDR widgets draw live ONLY in that inn-only block:
--     weave_menu_upgrade_skull_circle
--     weave_menu_upgrade_skull_circle_shade   <- the reported crash
--     weave_menu_athanor_upgrade_bg
-- (Everything else the forge draws is atlas-backed in gui_menus_atlas, which
-- rides in the always-loaded materials/ui/ui_1080p_menu_atlas_textures, so it
-- never faults.) The four forge windows draw their _bottom_hdr_widgets /
-- _top_hdr_widgets on parent:hdr_renderer() (e.g.
-- hero_window_weave_forge_overview.lua:704-737). On the base mission renderer
-- those three materials aren't resident, so the texture pass fatals at
-- ui_passes.lua:134 (`Material `weave_menu_upgrade_skull_circle_shade` not
-- found in Gui`), session 35046c6c.
--
-- A Stingray Gui resolves materials ONLY from the fixed list baked in at
-- World.create_screen_gui() time (ui_renderer.lua:246-251); there is no API to
-- add a material to a live Gui, and Managers.package:load cannot retro-add one
-- either — so this is NOT a package-residency problem and the
-- la_package_force_load guard is moot (no force-load is needed or possible).
--
-- Fix: in mission, EMPTY the two HDR draw arrays (`_top_hdr_widgets` /
-- `_bottom_hdr_widgets`) right after the window builds them in
-- create_ui_elements. The vanilla _draw loops then iterate nothing, so the
-- three keep-only materials are never resolved (UIRenderer.draw_widget only
-- calls a pass's draw — and thus Gui.material — when the widget is visible and
-- present; an empty array skips the loop entirely). We prefer emptying the
-- arrays over setting content.visible=false / alpha=0 because those still leave
-- the widget in the iterated array (alpha=0 in particular still resolves the
-- material). The widgets remain registered in _widgets_by_name, so the existing
-- _forge_apply_ui_polish _forge_hide_widget("upgrade_bg" / "top_hdr_background_
-- write_mask") calls stay valid no-ops.
--
-- KEEP path is fully unchanged: gated on `not _is_in_keep()`, so in the keep the
-- HDR arrays are left intact and the forge keeps its full HDR glow (drawn on the
-- real keep HDR renderer that DOES carry the inn-only materials).
--
-- Visual cost in mission: the decorative skull-circle glow ring and the athanor
-- upgrade-panel background glow are absent. The forge is otherwise fully drawn
-- and usable. Regression: hdr_glow_widgets_suppressed_in_mission
-- (/cim_regression_test).
--
-- Helper is parameterized + exposed so the regression test can drive it
-- synthetically against a fake window without needing a live forge.
function mod._cim_suppress_hdr_glow_in_mission(window, in_keep)
    if in_keep then return false end
    if type(window) ~= "table" then return false end
    local cleared = false
    if type(window._top_hdr_widgets) == "table" and #window._top_hdr_widgets > 0 then
        window._top_hdr_widgets = {}
        cleared = true
    end
    if type(window._bottom_hdr_widgets) == "table" and #window._bottom_hdr_widgets > 0 then
        window._bottom_hdr_widgets = {}
        cleared = true
    end
    return cleared
end

-- Mid-mission forge: renderer-proof the static non-HDR widget arrays
-- ------------------------------------------------------------
-- Prior crashes proved that raw skill-tree rings and smoke materials can be
-- absent from a mission Gui. The arrays also contain functional atlas-backed
-- panel passes, so they cannot be emptied wholesale. Static widgets are created
-- both in create_ui_elements and again during Properties.on_enter; both existing
-- call sites invoke this helper after their respective producer completes.
-- #404 corrected the old prefix assumption with source and renderer evidence:
-- `gui_menus_atlas.lua` contains athanor trait/property backgrounds, frames,
-- power backgrounds, decoration corners/headlines, connectors, and slots. The
-- old "every athanor_* except slot is raw" rule therefore removed legitimate
-- panels. Prove each pass against the exact Gui that draws it instead. Unsafe
-- texture passes are suppressed clone-on-write; safe texture passes, text, and
-- hotspots survive. Function name is retained for existing call sites/checks.
function mod._cim_suppress_skilltree_rings_in_mission(window, in_keep)
    if in_keep then return false end
    if type(window) ~= "table" then return false end

    local policy = mod._cim83_forge_widget_policy
    local icon_policy = mod._cim_athanor_icon_policy
    if type(policy) ~= "table" or type(policy.sanitize_widgets) ~= "function"
            or type(icon_policy) ~= "table"
            or type(icon_policy.renderer_has_texture) ~= "function" then
        return false
    end

    local suppressed_any = false
    local arrays = {
        { widgets = window._bottom_widgets, renderer = window._ui_renderer },
        { widgets = window._top_widgets, renderer = window._ui_top_renderer },
    }
    window._cim404_reported_materials = window._cim404_reported_materials or {}
    for i = 1, #arrays do
        local entry = arrays[i]
        local renderer = entry.renderer
        local report = policy.sanitize_widgets(entry.widgets, function(texture, flags)
            local target = renderer
            if flags and flags.retained and type(renderer) == "table"
                    and renderer.gui_retained ~= nil then
                target = { gui = renderer.gui_retained }
            end
            return icon_policy.renderer_has_texture(
                target, texture, UIAtlasHelper, Gui, flags)
        end)
        if report.suppressed > 0 then
            suppressed_any = true
            if printf then
                for j = 1, #report.materials do
                    local texture = report.materials[j]
                    if not window._cim404_reported_materials[texture] then
                        window._cim404_reported_materials[texture] = true
                        printf("[cim:404] suppressed non-resident static forge material: %s",
                            tostring(texture))
                    end
                end
            end
        end
    end
    return suppressed_any
end

-- The four weave-forge windows that build HDR glow arrays in create_ui_elements.
-- (HeroWindowWeaveForgeBackground builds none and is intentionally omitted.)
-- create_ui_elements assigns self._top_hdr_widgets / self._bottom_hdr_widgets as
-- its LAST step, so a post (hook_safe) hook sees them populated. None of these
-- (Class, "create_ui_elements") pairs is hooked elsewhere in cim
-- (grep-verified — no duplicate-hook violation).
for _, _hdr_window_class in ipairs({
    "HeroWindowWeaveForgeOverview",
    "HeroWindowWeaveProperties",
    "HeroWindowWeaveForgeWeapons",
    "HeroWindowWeaveForgePanel",
}) do
    mod:hook_safe(_hdr_window_class, "create_ui_elements", function(self)
        local in_keep = _is_in_keep()
        mod._cim_suppress_hdr_glow_in_mission(self, in_keep)
        -- Fix B5 (+v0.8.49 extension): drop raw keep-only textures (athanor_*
        -- non-slot AND forge_overview_top_glow_effect_*) from BOTH non-HDR draw
        -- arrays (_bottom_widgets + _top_widgets). Properties builds skill-tree
        -- rings in _bottom_widgets; the Panel mixes smoke into _bottom_widgets
        -- and power-bg/corners into _top_widgets (session 9cc7ebf2); a no-op on
        -- clean arrays.
        mod._cim_suppress_skilltree_rings_in_mission(self, in_keep)
    end)
end

-- Mid-mission forge: no-op the per-frame HDR bloom-pulse set_scalar (Fix B3)
-- ------------------------------------------------------------
-- v0.8.18-dev (Issue: hero_window_weave_forge_panel.lua:392 "bad argument #1 to
-- 'set_scalar' (userdata expected, got nil)", crashify 12a6d563) — a THIRD
-- keep-only-HDR-object deref surfacing because Fix B (v0.8.16) skips building
-- the HDR worlds in mission.
--
-- Distinct from the B/B2 draw-array vector. The B2 helper empties the HDR DRAW
-- arrays (_top_hdr_widgets / _bottom_hdr_widgets) so the vanilla _draw loops skip
-- the missing materials. But two windows ALSO run a per-frame bloom-pulse that
-- reads `_widgets_by_name` DIRECTLY (not the draw arrays) and writes a material
-- scalar on the HDR Gui, so emptying the draw arrays does not cover it:
--
--   HeroWindowWeaveForgePanel._set_background_bloom_intensity
--     (hero_window_weave_forge_panel.lua:408-437)
--   HeroWindowWeaveProperties._set_background_bloom_intensity
--     (hero_window_weave_properties.lua:1218-1248)
--
-- Both do, every frame:
--     local gui = parent:hdr_renderer().gui
--     local m   = Gui.material(gui, widgets_by_name.<wheel>.content.texture_id)
--     Material.set_scalar(m, "noise_intensity", value)
--
-- After Fix B, `parent:hdr_renderer()` falls through to the BASE mission renderer
-- (hdr_renderer hook returns self.ui_renderer when _hdr_gui_data is nil). That
-- Gui's baked material list (built at create_screen_gui time with is_in_inn=false)
-- does NOT contain the raw, inn-only weave-forge wheel materials
-- (weave_menu_* — the same three the B/B2 fix dodged at the draw site). So
-- `Gui.material(gui, <texture>)` returns NIL, and `Material.set_scalar(nil, ...)`
-- fatals with exactly the reported `userdata expected, got nil`. The crashify
-- cites a _draw line number (392) because the build's line table shifts, but the
-- only set_scalar in this window is in _set_background_bloom_intensity.
--
-- Call chains that reach it every frame in mission:
--   Panel:      update -> _draw -> (if _draw_background_wheel) _update_background_
--               animations -> _set_background_bloom_intensity. _draw_background_
--               wheel is set true by _set_background_wheel_visibility for every
--               layout EXCEPT "weave_properties" (i.e. the default overview), so
--               the panel crashes as soon as the forge opens in mission.
--   Properties: _update_animations -> _update_background_animations ->
--               _set_background_bloom_intensity (UNCONDITIONAL — no _draw_
--               background_wheel gate), so the properties editor crashes the
--               moment a weapon's skill tree is opened in mission.
--
-- Fix: full mod:hook (not hook_safe — we must SKIP the vanilla body, not run
-- after it) on _set_background_bloom_intensity for both windows; in mission,
-- return without calling vanilla. The bloom pulse is purely the decorative wheel
-- glow intensity — dropping it in mission matches Fix B's "HDR glow layer is
-- intentionally absent in mission" contract (the wheel widgets are already
-- emptied from the draw arrays by B2, so nothing visible is lost beyond what
-- B/B2 already removed). KEEP path (is_in_inn) runs vanilla untouched: full
-- bloom pulse there.
--
-- Neither (HeroWindowWeaveForgePanel, _set_background_bloom_intensity) nor
-- (HeroWindowWeaveProperties, _set_background_bloom_intensity) is hooked
-- anywhere else in cim (grep-verified — no duplicate-hook violation; cim's
-- existing HeroWindowWeaveProperties hooks are on _create_viewport_definition /
-- _create_unit_previewer / _setup_menu_options / _sync_backend_loadout / _draw /
-- _set_essence_upgrade_cost / _upgrade_magic_level / create_ui_elements /
-- on_enter, none of them this method).
--
-- Regression: hdr_bloom_setscalar_skipped_in_mission (/cim_regression_test).
function mod._cim_skip_bloom_intensity_in_mission(window)
    -- Returns true when the per-frame bloom-pulse set_scalar must be SKIPPED
    -- (in mission, HDR Gui lacks the inn-only wheel materials -> nil material ->
    -- Material.set_scalar(nil,...) fatal). Returns false in the keep (full HDR).
    if _is_in_keep() then return false end
    return true
end

for _, _bloom_window_class in ipairs({
    "HeroWindowWeaveForgePanel",
    "HeroWindowWeaveProperties",
}) do
    mod:hook(_bloom_window_class, "_set_background_bloom_intensity", function(func, self, ...)
        if mod._cim_skip_bloom_intensity_in_mission(self) then
            -- In mission: skip the vanilla body. parent:hdr_renderer() would
            -- return the base mission renderer whose Gui has no weave_menu_*
            -- wheel materials, so Gui.material(...) -> nil -> set_scalar fatal.
            return
        end
        return func(self, ...)
    end)
end

-- Mid-mission forge: skip the keep-only "upgrade" transition animation (Fix B4)
-- ------------------------------------------------------------
-- v0.8.18-dev (same crash CLASS as B3, second deref site) — the forge-upgrade
-- transition animation's init/update closures ALSO do the keep-only HDR-material
-- deref, on a DIFFERENT path than the per-frame bloom pulse:
--
--   hero_window_weave_forge_overview_definitions.lua animation_definitions.upgrade
--     (sub-anims dissolve_in / dissolve_out / intensity)
--   hero_window_weave_forge_weapons_definitions.lua  animation_definitions.upgrade
--     (sub-anim intensity_out)
--
-- Each closure does `local gui = params.parent:hdr_renderer().gui` then
-- `Gui.material(gui, <skull_circle / upgrade_effect>.content.texture_id)` then
-- `Material.set_scalar(<material>, "progress"/"intensity", value)`. The textures
-- (weave_menu_upgrade_skull_circle[_shade], the athanor upgrade effect) are the
-- same raw, inn-only materials that are absent from the base mission Gui after
-- Fix B, so `Gui.material(...)` returns nil and `Material.set_scalar(nil, ...)`
-- fatals — identical signature to B3, just fired by the upgrade flow instead of
-- the idle bloom pulse.
--
-- Trigger: pressing the athanor / weave UPGRADE button and the backend call
-- SUCCEEDING runs `_upgrade_forge_done` / `_upgrade_item_done` ->
-- `_start_transition_animation("upgrade")` (overview line 815, weapons line 950),
-- which starts the `upgrade` animation group -> its HDR closures deref the nil
-- material. So this only fires when the player actually upgrades mid-mission, but
-- it IS reachable through the cim forge.
--
-- Fix: full mod:hook on `_start_transition_animation` for the two windows whose
-- `upgrade` animation touches HDR materials (overview + weapons). In mission,
-- DROP only the `"upgrade"` animation — every other animation name these windows
-- start ("on_enter", text fades, font tweens) touches no HDR material, so they
-- run untouched. The visible cost in mission is the skull-circle dissolve / glow
-- flourish on upgrade; the upgrade itself (backend + loadout sync) is unaffected
-- because that work happens in _upgrade_forge_done BEFORE the animation starts.
--
-- HeroWindowWeaveProperties is intentionally NOT in this list: its animation
-- definitions contain NO HDR Material.set_scalar (grep-verified — its only HDR
-- set_scalar was the bloom pulse handled by B3 above), so its "upgrade"/"on_enter"
-- animations are safe in mission and must run for the normal fade-in.
--
-- KEEP path (is_in_inn) runs vanilla untouched: full upgrade flourish there.
-- Neither (HeroWindowWeaveForgeOverview, _start_transition_animation) nor
-- (HeroWindowWeaveForgeWeapons, _start_transition_animation) is hooked elsewhere
-- in cim (grep-verified — no duplicate-hook violation).
--
-- Regression: hdr_upgrade_anim_skipped_in_mission (/cim_regression_test).
function mod._cim_skip_upgrade_anim_in_mission(animation_name)
    -- The "upgrade" transition animation's HDR closures deref the inn-only
    -- weave_menu_* materials via parent:hdr_renderer().gui. Skip it ONLY in
    -- mission and ONLY for that animation name; everything else is HDR-free.
    if _is_in_keep() then return false end
    return animation_name == "upgrade"
end

for _, _upgrade_anim_class in ipairs({
    "HeroWindowWeaveForgeOverview",
    "HeroWindowWeaveForgeWeapons",
}) do
    mod:hook(_upgrade_anim_class, "_start_transition_animation", function(func, self, animation_name, ...)
        if mod._cim_skip_upgrade_anim_in_mission(animation_name) then
            -- In mission: do not start the "upgrade" HDR flourish. Its closures
            -- would deref a nil weave_menu_* material -> Material.set_scalar fatal.
            return
        end
        return func(self, animation_name, ...)
    end)
end
