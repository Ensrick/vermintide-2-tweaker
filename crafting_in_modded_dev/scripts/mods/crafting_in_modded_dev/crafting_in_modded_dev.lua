--[[
crafting_in_modded — modded crafting menus for Vermintide 2.

Currently surfaces the Athanor (Winds of Magic forge) UI as a custom weapon-
crafting menu. Future versions may add additional surfaces (e.g. the Keep's
standard forge / Smithy). Split out of weapon_tweaker on 2026-05-05.

Major sections (search by name to jump):
  * NetworkLookup.rarities patch                — adds "promo" rarity for crafted items
  * Forge core (`_forge_*`)                     — persistence, item creation, MIL injection
  * Athanor section                             — UI hooks, _custom_forge_active flag, B hotkey opener
  * BackendInterfaceWeavesPlayFab hooks         — redirect weave loadout queries to real items
  * HeroWindowWeaveForgeWeapons hooks           — replace weapon list, equip → craft, etc.
  * Diagnostic commands (`cim forge_dump`, etc.)
  * Manual console crafting (`cim forge`, `cim forge_confirm`)
]]

local mod = get_mod("cim_dev")
local _FORGE_PREVIEW_POLICY = mod:dofile(
    "scripts/mods/crafting_in_modded_dev/_cim_forge_preview_policy")
mod._cim_forge_preview_policy = _FORGE_PREVIEW_POLICY
local _FORGE_PREVIEW = mod:dofile(
    "scripts/mods/crafting_in_modded_dev/_cim_forge_preview")
mod._cim_forge_preview = _FORGE_PREVIEW
mod._cim959_accessory_property_policy = mod:dofile(
    "scripts/mods/crafting_in_modded_dev/_cim_accessory_property_policy")
local _BULK_ACCESSORY_CRAFT = mod:dofile("scripts/mods/crafting_in_modded_dev/_cim_bulk_accessory_craft")
_MEM_PROBE_T0_CIMD = collectgarbage("count")  -- [mem-probe] temp Lua-footprint baseline (lua_heap 1 GiB cap diagnostic)

local MOD_VERSION = "0.8.128-dev"
local _bootstrap = mod:dofile(
    "scripts/mods/crafting_in_modded_dev/_cim_bootstrap_runtime")({
        mod = mod,
        version = MOD_VERSION,
        print_line = function(fmt, ...) printf(fmt, ...) end,
    })
local CIM_RPC_SCHEMA = _bootstrap.rpc_schema
local _dbg = _bootstrap.dbg
local _dbg_alert = _bootstrap.dbg_alert
local _rt_register = _bootstrap.rt_register
local _rt_src_read = _bootstrap.rt_src_read

-- #947: persisted Chaos Wastes traits may execute in Adventure, where vanilla
-- does not retain the Morris gameplay package that owns their hit-time particle
-- strings. Acquire one exact, session-long package reference before any crafted
-- weapon can trigger the native WorldApi boundary. The controller retries only
-- on lifecycle edges if PackageManager was not ready at module evaluation.
local _cim947_trait_residency = mod:dofile(
    "scripts/mods/crafting_in_modded_dev/_cim_cw_trait_residency")({
        mod = mod,
        rt_register = _rt_register,
        get_package_manager = function()
            return Managers and Managers.package
        end,
        print_line = function(fmt, ...)
            printf(fmt, ...)
        end,
    })
mod._cim947_trait_residency = _cim947_trait_residency
_cim947_trait_residency.ensure()

-- Register the "modded" rarity (and any future custom rarities) BEFORE
-- anything else loads — sibling modules will create items with this rarity.
local _ok_rr, _err_rr = pcall(mod.dofile, mod, "scripts/mods/crafting_in_modded_dev/modded_rarities")
if not _ok_rr then mod:error("Failed to load modded_rarities: %s", tostring(_err_rr)) end

-- #628: one engine-free identity contract shared by both craft surfaces,
-- provider acquisition selectors, inventory/salvage, persistence and deletion.
-- Keep it on `mod` so split modules consume the same singleton at runtime.
mod._cim_synthetic_item_contract = mod:dofile(
    "scripts/mods/crafting_in_modded_dev/_cim_synthetic_item_contract")
mod._cim_temper_transaction = mod:dofile(
    "scripts/mods/crafting_in_modded_dev/_cim_temper_transaction")
-- issues 628/682/793: declare this entry's routed provider-gate surfaces at
-- install time (gate calls re-register at run time; blacksmith_list/salvage
-- register from their modules; cw_conversion stays unrouted -> self-report).
mod._cim_synthetic_item_contract.register_enumerators(
    "athanor_list", "mirror_restore", "mirror_injection")
mod._cim_external_trait_policy = mod:dofile(
    "scripts/mods/crafting_in_modded_dev/_cim_external_trait_policy")

-- Pure source-backed mapping from the nine vanilla CW trait categories to
-- their owning weapon slot. Load before standard_forge, which consumes it.
local _ok_tsp, _trait_slot_policy = pcall(mod.dofile, mod, "scripts/mods/crafting_in_modded_dev/_cim_trait_slot_policy")
if _ok_tsp then
    mod._cim_trait_slot_policy = _trait_slot_policy
else
    mod:error("Failed to load _cim_trait_slot_policy: %s", tostring(_trait_slot_policy))
end

-- Pure #244 conversion between the Athanor's absolute Weave bubble values and
-- the normalized interpolation parameter stored on ordinary Adventure items.
-- Keep it on `mod`: the entry chunk is close to Lua 5.1's 200-local limit.
mod._cim244_property_value_policy = mod:dofile(
    "scripts/mods/crafting_in_modded_dev/_cim_property_value_policy")
mod.CIM244_PROPERTY_VALUE_POLICY_MARKER_v0_8_74 = true

-- #524 render-seam diagnostic (issue-keyed, tier c). Dumps the FINAL native
-- Craft Item picker list at the inject seam so a single log proves which rows the
-- user actually sees and where each came from. Loaded before standard_forge,
-- which calls it from mod._cim_inject_templates. Always-on in dev, engine printf.
mod._cim_diag_524 = mod:dofile("scripts/mods/crafting_in_modded_dev/_cim_diag_524")

-- Standard Keep crafting — same Athanor pattern: mutations are session-only because
-- we block PlayFab commits while the forge is open. v0.2.0 crashed because we left
-- the commit alive and PlayFab's anti-tamper rejected the modified inventory state.
local _ok_sf, _err_sf = pcall(mod.dofile, mod, "scripts/mods/crafting_in_modded_dev/standard_forge")
if not _ok_sf then mod:error("Failed to load standard_forge: %s", tostring(_err_sf)) end

-- #617: the Athanor list draws inventory icons on ui_top_renderer with the
-- masked+saturated atlas path. Keep renderer/material proof in a pure module so
-- no provider icon can reach Gui.bitmap_uv unless the exact live Gui owns the
-- resolved material. Unknown/unavailable custom icons fall back fail-closed.
mod._cim_resource_residency = mod:dofile(
    "scripts/mods/crafting_in_modded_dev/_lib_resource_residency")
mod._cim_athanor_icon_policy = mod:dofile(
    "scripts/mods/crafting_in_modded_dev/_cim_athanor_icon_policy")
mod._cim_athanor_icon_policy.set_resource_residency(mod._cim_resource_residency)
mod._cim83_forge_widget_policy = mod:dofile(
    "scripts/mods/crafting_in_modded_dev/_cim_forge_widget_material_policy")

function mod._cim_resolve_provider_inventory_icon(icon_id, renderer_name)
    local ok, provider = pcall(get_mod, "character_weapon_variants")
    local registry = ok and provider and provider._cwv_inventory_icons
    if type(registry) == "table" and type(registry.resolve) == "function" then
        return registry.resolve(icon_id, renderer_name)
    end
    return icon_id, false
end

-- Modded-realm illusion swap (migrated from cosmetics_tweaker v0.8.49).
-- Must load AFTER the forge core so `mod._cim_*` helpers are defined when
-- the craft hook fires.
local _ok_is, _err_is = pcall(mod.dofile, mod, "scripts/mods/crafting_in_modded_dev/illusion_swap")
if not _ok_is then mod:error("Failed to load illusion_swap: %s", tostring(_err_is)) end

-- SaveWeapon mod importer. One-shot chat command (and bindable VMF keybind)
-- that pulls every weapon the player saved via the SaveWeapon mod into cim's
-- forged_weapons table. Idempotent; safe to re-run.
local _ok_sw, _err_sw = pcall(mod.dofile, mod, "scripts/mods/crafting_in_modded_dev/saveweapon_import")
if not _ok_sw then mod:error("Failed to load saveweapon_import: %s", tostring(_err_sw)) end

-- Accessory craft panel — 3 per-slot craft buttons (own-scenegraph overlay,
-- mirrors cosmetics_tweaker's _glow_picker pattern). Returns the Panel table;
-- the _draw hook + craft callback are wired further down (after the amulet
-- helpers + _custom_forge_active are declared).
local _ok_acp, _AccessoryPanel = pcall(mod.dofile, mod, "scripts/mods/crafting_in_modded_dev/_accessory_craft_panel")
if not _ok_acp then
    mod:error("Failed to load _accessory_craft_panel: %s", tostring(_AccessoryPanel))
    _AccessoryPanel = nil
end

-- #1360: Ranald's Gift browser. Keep these on the mod namespace instead of
-- adding entry-chunk locals (Lua 5.1's 200-local ceiling is already close).
-- The browser owns no hook; _cim_forge_ui_owner drives its draw pass from the
-- existing single HeroViewStateWeaveForge.update seam.
mod._cim_ranalds_catalog = mod:dofile(
    "scripts/mods/crafting_in_modded_dev/_cim_ranalds_catalog")
mod._cim_ranalds_firestore = mod:dofile(
    "scripts/mods/crafting_in_modded_dev/_cim_ranalds_firestore")
mod._cim_ranalds_fetcher = mod._cim_ranalds_firestore.new({
        catalog = mod._cim_ranalds_catalog,
        get_curl = function() return Managers and Managers.curl end,
        get_json = function() return rawget(_G, "cjson") end,
    })
mod._cim_ranalds_browser = mod:dofile(
    "scripts/mods/crafting_in_modded_dev/_cim_ranalds_browser")
mod._cim_ranalds_browser.configure({
    catalog = mod._cim_ranalds_catalog,
    fetcher = mod._cim_ranalds_fetcher,
    current_career_id = function()
        local player = Managers.player and Managers.player:local_player()
        local profile_index = player and player:profile_index()
        local career_index = player and player:career_index()
        local profile = SPProfiles and profile_index and SPProfiles[profile_index]
        local career_name = profile and profile.careers and career_index
            and profile.careers[career_index] and profile.careers[career_index].name
        for id, name in pairs(mod._cim_ranalds_catalog.CAREERS) do
            if name == career_name then return id end
        end
        return 1
    end,
    career_label = function(career_id)
        local career_name = mod._cim_ranalds_catalog.CAREERS[career_id]
        local settings = career_name and CareerSettings and CareerSettings[career_name]
        local display_name = settings and settings.display_name
        if display_name and type(Localize) == "function" then
            local ok, label = pcall(Localize, display_name)
            if ok and type(label) == "string" then return label end
        end
        return tostring(career_name or "Unknown career")
    end,
    import_build = function(build)
        local importer = mod._cim_ranalds_import
        if not importer then return false, "importer not ready" end
        return importer.apply(build)
    end,
})

-- Debug autodumps. Sub-module exposes `mod._cim_autodump_*` helpers; every one
-- is a fast no-op when the `debug_mode` setting is OFF. Hooks below call into
-- them at well-known UI transitions / state changes.
local _ok_dbg, _err_dbg = pcall(mod.dofile, mod, "scripts/mods/crafting_in_modded_dev/cim_debug")
if not _ok_dbg then mod:error("Failed to load cim_debug: %s", tostring(_err_dbg)) end

-- ============================================================
-- Phase 1 OOP split modules (v0.8.55-dev) -- three self-contained concerns
-- extracted verbatim from this entry (PROJECT_STANDARDS 2.2a). Each module
-- self-publishes its flat mod._cim_* fields and registers its own hooks/commands;
-- the entry consumes them only through that namespace at runtime. mod:dofile is
-- NOT a singleton, so each loads exactly once here. See DEVELOPMENT.md "Module map".
-- ============================================================
local _ok_inv, _err_inv = pcall(mod.dofile, mod, "scripts/mods/crafting_in_modded_dev/_cim_inventory_filter")
if not _ok_inv then mod:error("Failed to load _cim_inventory_filter: %s", tostring(_err_inv)) end
local _ok_mfs, _err_mfs = pcall(mod.dofile, mod, "scripts/mods/crafting_in_modded_dev/_cim_mission_forge_safety")
if not _ok_mfs then mod:error("Failed to load _cim_mission_forge_safety: %s", tostring(_err_mfs)) end
local _ok_kfi, _keep_forge_interaction = pcall(mod.dofile, mod,
    "scripts/mods/crafting_in_modded_dev/_cim_keep_forge_interaction")
if _ok_kfi then
    mod._cim_keep_forge_interaction = _keep_forge_interaction
    mod._cim_install_keep_forge_interaction = function()
        return _keep_forge_interaction.install(mod, rawget(_G, "InteractionDefinitions"))
    end
    local installed, install_err = mod._cim_install_keep_forge_interaction()
    if not installed then
        printf("[cim:624] Keep forge interaction not installed: %s", tostring(install_err))
    end
else
    mod:error("Failed to load _cim_keep_forge_interaction: %s", tostring(_keep_forge_interaction))
end
local _ok_dumpc, _err_dumpc = pcall(mod.dofile, mod, "scripts/mods/crafting_in_modded_dev/_cim_dump_commands")
if not _ok_dumpc then mod:error("Failed to load _cim_dump_commands: %s", tostring(_err_dumpc)) end
local _ok_tab, _err_tab = pcall(mod.dofile, mod, "scripts/mods/crafting_in_modded_dev/_cim_tab_preview")
if not _ok_tab then mod:error("Failed to load _cim_tab_preview: %s", tostring(_err_tab)) end
-- Entry alias for the mid-mission keep detector (published by _cim_mission_forge_safety
-- above). The HDR regression checks in `_cim_regression_checks.lua` receive this
-- same helper through the late installer context.
local _is_in_keep = mod._cim_is_in_keep
-- Pure destructive-cleanup policy (#277), shared with the offline Lua suite.
-- Loaded once and kept on the mod table to preserve entry-chunk local headroom.
mod._cim277_bulk_core = mod:dofile("scripts/mods/crafting_in_modded_dev/_cim_bulk_cleanup_core")
mod._cim277_owned_deletion = mod:dofile(
    "scripts/mods/crafting_in_modded_dev/_cim_owned_deletion")
mod.CIM277_BULK_CLEANUP_MARKER_v0_8_68 = true
-- Backward-compat: pre-v0.7.0 cim used `rarity = "promo"` for crafts. Keep
-- "promo" registered in NetworkLookup.rarities too so legacy saved items can
-- still round-trip through inventory sync until they get re-crafted/migrated.
local NL = rawget(_G, "NetworkLookup")
if NL and NL.rarities and not rawget(NL.rarities, "promo") then
    local t = NL.rarities
    local idx = #t + 1
    t[idx] = "promo"
    rawset(t, "promo", idx)
end

-- #1001: exact-instance favorite persistence policy (pure capture/restore).
-- Loaded before the forge state owner, which installs it with the live record
-- store, persist function, and both engine seams.
mod._cim_favorite_persistence = mod:dofile(
    "scripts/mods/crafting_in_modded_dev/_cim_favorite_persistence")

-- ============================================================
-- Forge state owner (persistence + item creation)
-- ============================================================
-- These callbacks are bound later in the entry. The forge owner resolves them
-- only when BackendManagerPlayFab rebuilds its interfaces.
local _athanor_inject_all
local _restore_modded_loadout
local _bubble_cap
local _cim_restore_forge_freedom

local _forge_state = mod:dofile(
    "scripts/mods/crafting_in_modded_dev/_cim_forge_state_owner")({
        mod = mod,
        rt_register = _rt_register,
        print_line = function(fmt, ...) printf(fmt, ...) end,
        get_athanor_inject_all = function() return _athanor_inject_all end,
        get_restore_modded_loadout = function() return _restore_modded_loadout end,
    })
local _forge_create_item = _forge_state.create_item
local _forge_detect_mil = _forge_state.detect_mil
local _forge_inject_item = _forge_state.inject_item
local _forge_load = _forge_state.load
local _forge_save = _forge_state.save
-- ============================================================
-- Vanilla-safe loadout wire owner
-- ============================================================
local _loadout_wire = mod:dofile(
    "scripts/mods/crafting_in_modded_dev/_cim_loadout_wire_owner")({
        mod = mod,
        rpc_schema = CIM_RPC_SCHEMA,
        dbg_alert = _dbg_alert,
        print_line = function(fmt, ...) printf(fmt, ...) end,
    })
local _persist_loadouts_enabled = _loadout_wire.persist_loadouts_enabled
-- ============================================================
-- Modded inventory filter + loadout restore
-- ============================================================
-- The mod-realm view: hide vanilla weapons from the inventory grid (toggleable),
-- and remember the last modded item the player equipped on each (career, slot)
-- so that switching to vanilla and back doesn't wipe their modded loadout.
--
-- The persisted store, its flat -> indexed migration, the stale purge, both
-- set_loadout_item capture hooks (#22), the restore/re-equip pass, the #562
-- auto-equip helpers, and the three loadout commands all live in one owner
-- installed HERE, at the exact point that block used to execute. The forge
-- store is injected as an accessor because _forge_load rebinds it on every
-- backend _create_interfaces pass.
local _install_modded_loadout_owner = mod:dofile(
    "scripts/mods/crafting_in_modded_dev/_cim_modded_loadout_owner")
local _LOADOUT_OWNER = _install_modded_loadout_owner({
    mod = mod,
    persist_loadouts_enabled = _persist_loadouts_enabled,
    get_forged_weapons = _forge_state.get_forged_weapons,
})
-- Bind the forward-declared local the _create_interfaces hook already closes over.
_restore_modded_loadout = _LOADOUT_OWNER.restore_modded_loadout
-- Consumed by mod.update (deferred post-LA install) and the late owner installers.
local _install_backendutils_capture = _LOADOUT_OWNER.install_backendutils_capture
local _modded_loadout_save = _LOADOUT_OWNER.modded_loadout_save
local _modded_loadout_load = _LOADOUT_OWNER.modded_loadout_load


-- ============================================================
-- Athanor (Winds of Magic forge) — UI hooks
-- ============================================================
local _custom_forge_active = false
local _forge_loadout = {}
local _forge_item_props = {}
-- Issue #88: one-shot handshake between mod.open_standard_crafting and the
-- HeroView.on_enter hook. Set true immediately before cim's standard-crafting
-- transition; the on_enter hook applies the inventory_loadout_access flip ONLY
-- for that one view open (save -> vanilla read -> restore) and clears it, so
-- the persistent global mutation that leaked the inventory onto ESC-menu
-- backout mid-mission is gone.
local _cim_open_standard_inv_pending = false
local _forge_panel_styled = false
local _forge_bg_colored = false

-- Per-amulet-slot dirty tracking. Declared here (above the on_exit hook that
-- resets it) so the hook closure captures this local rather than reading a
-- nil global. The actual assignment lives further down with the amulet helpers.
local _amulet_dirty = { false, false, false }

mod.open_forge = function()
    if not Managers.ui then
        mod:echo("Forge: UI not available")
        return
    end
    local ingame_ui = Managers.ui._ingame_ui
    if not ingame_ui then
        mod:echo("Forge: not in game")
        return
    end
    if ingame_ui:pending_transition() then return end

    -- Keep gate. HeroViewStateWeaveForge was never authored to run mid-mission
    -- and several code paths still fault even with the gamepad +
    -- shading_environment shims in place. Default-off opt-in lets curious
    -- players test in-mission and report crash logs.
    -- DamageUtils.is_in_inn covers all hub levels: inn_level + 4 cosmetic
    -- variants (celebrate/halloween/skulls/sonnstill) + morris_hub (CW staging).
    -- Versus access lives inside inn_level, no extra check needed.
    --
    -- Chaos Wastes staging hub (morris_hub) is NOW ALLOWED. The blanket
    -- `mech == "deus" -> block` rule from 2026-05-22 (crash GUID
    -- fa1ec6f8-7385-4221-869b-ed4f2893c97c) was added because tabbing from
    -- the Athanor to the standard Customization view crashed on
    -- `levels/ui_store_preview/world` not being loaded — same crash class as
    -- issue #50 (general_tweaker's mid-mission gear icon). v0.7.45-alpha
    -- rewrote `_create_item_preview_widget_definition` to skip the un-loaded
    -- preview level entirely when not in keep, which lifts the underlying
    -- fatal. With that gone, the keep-gate (is_in_inn) is sufficient:
    -- morris_hub passes (it's a hub), active Deus levels do not (still
    -- gated by allow_in_mission). User report 2026-05-25 EOD: requested
    -- access in the CW staging area where the menu should be available.
    local in_keep = rawget(_G, "DamageUtils") and DamageUtils.is_in_inn or false
    -- In-mission Athanor is OPT-IN via `allow_in_mission` (the "Allow crafting
    -- bench in mission" toggle in Tweaker: GUI's In-Mission Menus, which writes
    -- through to cim's setting — issue #96). Re-enabled for #83 in v0.8.48-dev:
    -- the v0.8.23 HARD keep-gate existed because a render-level fatal
    -- (`script_world` blend) survived the Fix B/B2..B6 material/HDR hardening.
    -- That fatal is now root-caused (via #228/#235): native
    -- ShadingEnvironment.blend on a shading-env VARIATION the mission-
    -- substituted env does not define is an ACCESS VIOLATION (a missing env
    -- RESOURCE is a clean fatal instead), and the sole variation writer on
    -- this surface is HeroWindowItemCustomization._update_environment. Both
    -- layers are closed by the residency-probed env picker
    -- (_cim_pick_mission_env) + the _update_environment variation pin below.
    -- Fix B (no HDR worlds in mission) and the B2..B6 draw-site suppressions
    -- stay unchanged — the mission forge draws on the base renderer.
    if not in_keep and not mod:get("allow_in_mission") then
        mod:echo("The Athanor opens in the Keep by default. Enable 'Allow crafting bench in mission' " ..
                 "in Tweaker: GUI's In-Mission Menus to open it mid-run (experimental), " ..
                 "or use the standard crafting bench (/cim_craft_standard).")
        return
    end

    _custom_forge_active = true
    _forge_loadout = {}
    _forge_item_props = {}
    ingame_ui:transition_with_fade("hero_view_force", {
        menu_state_name = "weave_forge",
    })
end

-- ============================================================
-- Standard crafting bench (Keep Smithy) — in-mission entry
-- ============================================================
-- Opens the VANILLA standard crafting bench (`HeroWindowCrafting`, the
-- `forge` page in HeroView's window layout) mid-mission. This is the
-- salvage / craft / re-roll-properties / re-roll-traits / upgrade-rarity /
-- apply-illusion / convert-dust bench — NOT the Athanor (weave forge).
--
-- Why this is a SEPARATE, CLEAN path from `open_forge` (Athanor):
--   The Athanor (`weave_forge` state) is materially entangled with the keep:
--   its windows hardcode `shading_environment = "environment/ui_weave_forge_preview"`
--   (an inn-only resource) and draw inn-only raw materials
--   (`forge_overview_top_glow_effect_smoke_*`, `athanor_skilltree_*`,
--   `weave_menu_*`) that a mission Gui can't resolve. That class of crash
--   was chased across v0.7.13 → v0.8.20 (Fixes B/B2..B6) and is why
--   `open_forge` is opt-in + "[untested] may crash".
--
--   The standard bench shares NONE of that. `HeroWindowCrafting`
--   (hero_window_crafting.lua:302-324) draws plain atlas widgets
--   (`crafting_bg*`, `crafting_fg*`, `item_grid_fg`, standard window-frame /
--   button materials — hero_window_crafting_definitions.lua:552-586) on
--   `ui_top_renderer` with NO viewport, NO create_world, NO
--   shading_environment, NO HDR Gui, NO preview render-target. The crash
--   material `forge_overview_top_glow_effect_smoke_1` lives ONLY in the
--   weave-forge / weave-background definition files (grep-verified: 4 files,
--   all `weave`). The craft sub-pages (`craft_page_*`) are icon-based, no
--   spawned-unit preview world. So the standard bench renders flat in a
--   mission with no material/shading shims at all.
--
-- The modded-crafting LOGIC already exists and is keep-tested: standard_forge.lua's
-- `HeroWindowCrafting`/`HeroWindowCraftingConsole`/`HeroWindowItemCustomization`
-- on_enter hooks (standard_forge.lua:222-239) + the synth paths fire on the
-- WINDOW lifecycle, not gated to the keep — so opening the `forge` page in a
-- mission activates all of it automatically. The only missing piece was an
-- in-mission entry point, added here.
--
-- Template: gt's `gt_open_mission_inventory` (general_tweaker_dev/_gt_mission_ui.lua:56-113),
-- the proven `handle_transition("hero_view_force", ...)` that bypasses the
-- hotkey gates the same way vanilla's ESC-menu "Open Inventory" does.
--
-- ONE trap avoided: do NOT route the in-mission flow onto the gear-icon
-- Customization view (`HeroWindowItemCustomization`), which pulls
-- `levels/ui_store_preview/world` (the preview-world crash class cim already
-- patched at v0.7.45 / gt #50). A direct transition to `menu_state_name="forge"`
-- lands on the crafting/inventory/options windows, none of which route there.
mod.open_standard_crafting = function()
    if not Managers.ui then
        mod:echo("Standard crafting: UI not available")
        return
    end
    local ingame_ui = Managers.ui._ingame_ui
    if not ingame_ui then
        mod:echo("Standard crafting: not in game")
        return
    end
    if ingame_ui:pending_transition() then return end

    -- Chaos Wastes guard. CW is loadout-locked via the deus boon system and
    -- its level package sets don't carry the keep crafting/preview resources;
    -- block the WHOLE run (hub + mission), mirroring gt_open_mission_inventory's
    -- adventure-exclusive directive (2026-06-18). Adventure / survival only.
    local mech = Managers.mechanism and Managers.mechanism:current_mechanism_name()
    if mech == "deus" then
        mod:echo("Standard crafting is disabled in Chaos Wastes (CW is loadout-locked). Adventure only.")
        return
    end

    -- Keep gate / opt-in. The standard bench is material-CLEAN in adventure
    -- missions, so there is no technical requirement for the keep — but the
    -- `forge` page also loads the `inventory` window (layout slot 3), which
    -- depends on the loadout_access_supported_game_modes patch. We honor the
    -- same `allow_in_mission` opt-in `open_forge` uses, so a single toggle
    -- governs both crafting surfaces. In the keep / CW hub it always opens.
    local in_keep = rawget(_G, "DamageUtils") and DamageUtils.is_in_inn or false
    if not in_keep and not mod:get("allow_in_mission") then
        mod:echo("Standard crafting opens in the Keep by default. " ..
                 "Enable 'Allow in mission' in the mod options to open it mid-run.")
        return
    end

    -- The `inventory` window (forge layout slot 3) + the loadout panel depend on
    -- InventorySettings.inventory_loadout_access_supported_game_modes — vanilla
    -- HeroView.on_enter -> _fetch_initial_loadout_index reads it once
    -- (hero_view.lua:323) and bails if the current game mode isn't supported.
    --
    -- Issue #88: cim USED to flip those flags PERMANENTLY here and never restore
    -- them. The single vanilla read site is HeroView.on_enter, so a persistent
    -- flip means EVERY subsequent HeroView open in the mission sees the mode as
    -- supported — including the ESC-menu / ingame-menu backout, which then pulls
    -- up the loadout inventory mid-mission (it should be Keep-only). Fix: don't
    -- mutate the global persistently. Set a ONE-SHOT pending flag; the
    -- HeroView.on_enter hook below applies the flip ONLY around cim's own view
    -- open (save -> vanilla on_enter reads it -> restore), so the ESC-menu
    -- HeroView reads the untouched vanilla values and bails as normal.
    _cim_open_standard_inv_pending = true

    ingame_ui:transition_with_fade("hero_view_force", {
        menu_state_name = "forge",   -- hosts HeroWindowCrafting; NOT "weave_forge"
    })
end


-- ============================================================
-- Issue #88: scope the inventory_loadout_access flip to cim's own view open
-- ============================================================
-- `mod.open_standard_crafting` needs the `forge` page's inventory window to
-- init in a mission, which depends on
-- InventorySettings.inventory_loadout_access_supported_game_modes[game_mode].
-- The ONLY vanilla read of that table is HeroView.on_enter ->
-- _fetch_initial_loadout_index (hero_view.lua:309/323). Previously cim flipped
-- the table PERMANENTLY in open_standard_crafting and never restored it, so the
-- ESC-menu / ingame-menu HeroView (which cim did NOT open) ALSO read the mode
-- as supported and pulled up the loadout inventory mid-mission (Issue #88 — it
-- should be Keep-only).
--
-- Fix: apply the flip ONLY around cim's own HeroView open, gated on the
-- one-shot `_cim_open_standard_inv_pending` flag set right before cim's
-- transition. Save the original values, let vanilla on_enter read the flipped
-- ones, then restore — even if vanilla raises (pcall) — and clear the flag.
-- Any OTHER HeroView open (ESC backout, hero select, etc.) sees the untouched
-- vanilla table and bails as normal. Keep / CW-hub opens are unaffected (the
-- mode is already supported there, and the flag is only set by cim's
-- in-mission standard-crafting entry).
--
-- No duplicate hook: cim's only other HeroView hooks are _setup_hdr_gui /
-- hdr_renderer / hdr_top_renderer (grep-verified) — none on on_enter.
mod:hook("HeroView", "on_enter", function(func, self, params)
    if not _cim_open_standard_inv_pending then
        return func(self, params)
    end
    -- Consume the one-shot flag up front so an early return / raise can't leave
    -- it set for a later, unrelated HeroView open.
    _cim_open_standard_inv_pending = false

    local modes = rawget(_G, "InventorySettings")
        and InventorySettings.inventory_loadout_access_supported_game_modes
    if not modes then
        return func(self, params)
    end

    local saved_adventure = modes.adventure
    local saved_survival  = modes.survival
    local saved_deus      = modes.deus
    modes.adventure = true
    modes.survival  = true
    modes.deus      = nil   -- CW stays blocked (open_standard_crafting bails on deus)

    local ok, err = pcall(func, self, params)

    -- Restore the vanilla values so the global table never stays mutated — this
    -- is what closes the ESC-backout leak.
    modes.adventure = saved_adventure
    modes.survival  = saved_survival
    modes.deus      = saved_deus

    if not ok then
        mod:warning("[cim] HeroView.on_enter raised under scoped inventory-access flip: %s", tostring(err))
    end
end)


mod:hook_safe("HeroViewStateWeaveForge", "on_exit", function(self)
    if mod._cim_ranalds_browser then mod._cim_ranalds_browser.close() end
    _custom_forge_active = false
    _forge_loadout = {}
    _forge_item_props = {}
    _forge_panel_styled = false
    _forge_bg_colored = false
    _amulet_dirty[1], _amulet_dirty[2], _amulet_dirty[3] = false, false, false
    -- Restore any weave trait/property category arrays the forge-freedom toggles
    -- widened, so real Weaves play is never polluted (injected display stubs are
    -- left in the *.traits/*.properties dicts, which is inert — real Weaves reads
    -- its own category arrays + Weave*ByCareer, neither referencing them).
    if _cim_restore_forge_freedom then pcall(_cim_restore_forge_freedom) end
end)

-- Hide the 3D amulet model in amulet mode (v0.7.32+). The vanilla previewer
-- gets created lazily by HeroWindowWeaveProperties._post_update_animations or
-- similar; once `_cim_skip_previewer = true` is set by the per-frame polish
-- pass, this hook intercepts the unit-previewer's update so the GPU never
-- draws the rotating amulet. The polish pass clears the flag when the user
-- selects a weapon (selected_item ~= nil), restoring the 3D model render.
mod:hook("HeroWindowWeaveProperties", "_create_unit_previewer", function(func, self, ...)
    if self._cim_skip_previewer then return nil end
    return func(self, ...)
end)

-- Athanor weapon-preview guard, correction, and diagnostics owner.
-- Install at the original boundary; mutable forge state stays accessor-backed.
mod:dofile("scripts/mods/crafting_in_modded_dev/_cim_forge_preview_owner")({
    mod = mod,
    is_active = function() return _custom_forge_active end,
    preview_policy = _FORGE_PREVIEW_POLICY,
    preview_runtime = _FORGE_PREVIEW,
    get_mod = get_mod,
    print_line = printf,
})


-- Athanor picker category owner. Install at the original hook boundary; its
-- stable backup owns every temporary category replacement until on_exit restores.
local _forge_picker_owner = mod:dofile(
    "scripts/mods/crafting_in_modded_dev/_cim_forge_picker_owner")({
        mod = mod,
        is_active = function() return _custom_forge_active end,
        get_global = function(name) return rawget(_G, name) end,
        get_setting = function(setting_id) return mod:get(setting_id) end,
        get_all_trait_entries = function()
            return mod._cim_all_trait_entries and mod._cim_all_trait_entries()
        end,
        get_cw_trait_entries = function(slot_type)
            return mod._cim_cw_trait_entries and mod._cim_cw_trait_entries(slot_type)
        end,
        get_all_property_keys = function()
            return mod._cim_all_property_keys and mod._cim_all_property_keys()
        end,
        print_line = printf,
    })
_cim_restore_forge_freedom = _forge_picker_owner.restore_forge_freedom

-- #239/#959: one extracted adapter owns the consolidated property-row cost,
-- category-aware usage/removal, and Clear hooks. Keeping the seam together
-- avoids VMF's same-mod duplicate-hook drop and keeps this oversized entry from
-- growing further.
mod:dofile("scripts/mods/crafting_in_modded_dev/_cim_accessory_property_runtime")({
    mod = mod,
    policy = mod._cim959_accessory_property_policy,
    is_custom_forge_active = function() return _custom_forge_active end,
})

-- Athanor presentation helpers and their two UI hooks share one stable owner.
mod._cim_forge_ui_owner = mod:dofile(
    "scripts/mods/crafting_in_modded_dev/_cim_forge_ui_owner")({
    mod = mod,
    accessory_panel = _AccessoryPanel,
    ranalds_browser = mod._cim_ranalds_browser,
    is_active = function() return _custom_forge_active end,
    get_bg_colored = function() return _forge_bg_colored end,
    set_bg_colored = function(value) _forge_bg_colored = value and true or false end,
    get_managers = function() return Managers end,
    get_profiles = function() return SPProfiles end,
    print_line = function(fmt, ...) printf(fmt, ...) end,
})

-- --- Backend safety hooks (prevent crashes for non-weave items) ---

local _install_weave_economy = mod:dofile(
    "scripts/mods/crafting_in_modded_dev/_cim_weave_economy")
_install_weave_economy({
    mod = mod,
    is_active = function() return _custom_forge_active end,
    bubble_cap = function(property_name) return _bubble_cap(property_name) end,
    build_zero_mastery_costs =
        mod._cim959_accessory_property_policy.build_zero_mastery_costs,
})

-- --- Forge loadout (redirect weave loadout to our own table) ---

mod:dofile("scripts/mods/crafting_in_modded_dev/_cim_immutable_relic_ui").install({
    mod = mod,
    contract = mod._cim_synthetic_item_contract,
    is_active = function() return _custom_forge_active end,
    get_loadout = function() return _forge_loadout end,
    get_items_backend = function()
        return Managers and Managers.backend and Managers.backend:get_interface("items")
    end,
})

-- --- Property/trait/talent storage (redirect to our own data) ---
--
-- The amulet slot map, the per-property bubble-cap math (#86/#244), the
-- seed/apply pass, and the TEN mutable `BackendInterfaceWeavesPlayFab` loadout
-- hooks are one owner installed at the exact point that block used to execute:
-- after the immutable-relic UI install, before the BackendManagerPlayFab commit
-- suppression (which stays here -- it is anti-tamper safety for BOTH craft
-- surfaces and must never be gated on this owner). Mutable forge state reaches
-- the owner as accessors because `mod.open_forge` and
-- `HeroViewStateWeaveForge.on_exit` rebind `_forge_item_props`, and
-- The forge state owner may replace its registry during reload, so consumers
-- retain its accessor rather than a snapshot of the table.
local _install_weave_loadout_owner = mod:dofile(
    "scripts/mods/crafting_in_modded_dev/_cim_weave_loadout_owner")
local _WEAVE_LOADOUT_OWNER = _install_weave_loadout_owner({
    mod = mod,
    is_active = function() return _custom_forge_active end,
    get_forge_item_props = function() return _forge_item_props end,
    get_forged_weapons = _forge_state.get_forged_weapons,
    get_amulet_dirty = function() return _amulet_dirty end,
    forge_save = _forge_save,
    temper_transaction = mod._cim_temper_transaction,
})
-- Bind the forward-declared local `_cim_weave_economy`'s cost hook closes over.
_bubble_cap = _WEAVE_LOADOUT_OWNER.bubble_cap
-- The remaining three have no consumer above the seam; the late
-- `_cim_regression_checks` installer reads them from here.
local _value_for_bubbles = _WEAVE_LOADOUT_OWNER.value_for_bubbles
local _store_property_slot = _WEAVE_LOADOUT_OWNER.store_property_slot
local _cap_grid_property_arrays = _WEAVE_LOADOUT_OWNER.cap_grid_property_arrays

-- CLARIFY: while either forge is open, suppress backend commits entirely so the
-- simulated mutations (Athanor property/trait edits, standard-forge salvage/upgrade/
-- skin/etc) don't leak to PlayFab and trigger the anti-tamper "Backend rejected
-- the challenge response -1" kick. The standard-forge module sets
-- `mod._cim_standard_forge_active` while its UI is open; we check both flags here.
-- Single registration: standard_forge.lua MUST NOT install its own commit hook,
-- otherwise VMF warns "Attempting to rehook active hook [commit]" and drops the
-- second registration → standard-forge mutations leak to PlayFab.
mod:hook("BackendManagerPlayFab", "commit", function(func, self, skip_queue, commit_complete_callback)
    if _custom_forge_active or mod._cim_standard_forge_active then return end
    return func(self, skip_queue, commit_complete_callback)
end)

-- --- Weapon list: show ALL weapons, not just weave "magic" rarity ---

mod:hook("HeroWindowWeaveForgeWeapons", "_setup_weapon_list", function(func, self)
    if not _custom_forge_active then return func(self) end

    local backend_items = Managers.backend:get_interface("items")
    local selected_slot_name = self._selected_slot_name
    local career_name = self._career_name
    -- v0.7.60-dev: guard the career/slot lookup. This is a full mod:hook
    -- wrapper, so an unknown/nil career_name (or a slot the career doesn't
    -- define) would error out of the wrapper and break the weapon-list render
    -- instead of degrading. Fall back to vanilla on any miss.
    local career_settings = career_name and rawget(CareerSettings, career_name)
    local item_slot_types = career_settings and career_settings.item_slot_types_by_slot_name
        and career_settings.item_slot_types_by_slot_name[selected_slot_name]
    if not item_slot_types then
        mod:info("[cim] _setup_weapon_list: no slot types for career=%s slot=%s — vanilla fallback",
            tostring(career_name), tostring(selected_slot_name))
        return func(self)
    end
    local weapon_layout = {}
    local seen_names = {}
    -- v0.8.6-dev: drop Versus carousel twins that shadow a real Adventure weapon
    -- (e.g. vs_wh_hammer_book hiding the real wh_hammer_book via the display_name
    -- dedup below). Unique vs_* weapons stay craftable. See _cim_versus_shadowed
    -- in standard_forge.lua + memory reference_vt2_versus_items_hidden_in_adventure.
    local real_names = mod._cim_real_display_names and mod._cim_real_display_names() or {}

    -- issues 682/793/628 (_cim_athanor_list_provider_gate): this walk was the
    -- #793 bypass - it never consulted the provider contract, so the immutable
    -- WOC relic `woc_blightreaper` rendered as a craftable row on every career
    -- and the craft then died at mirror injection (issue 682's confirmed FAIL
    -- boundary). Route every row through the registered gate; the contract
    -- logs rejections capped (`provider rejected before UI`) plus the
    -- unrouted-walk self-report (issue 628 scope 3).
    local gate_contract = mod._cim_synthetic_item_contract
    local gate_rejected = {}

    for key, item_data in pairs(ItemMasterList) do
        local slot_type = item_data.slot_type
        if slot_type and table.contains(item_slot_types, slot_type) then
            local can_wield = item_data.can_wield
            if can_wield and table.contains(can_wield, career_name) then
                local rarity = item_data.rarity
                local dlc_locked = mod._cim_item_requires_unowned_dlc
                    and mod._cim_item_requires_unowned_dlc(key)
                if item_data.item_type ~= "weapon_skin" and rarity ~= "magic" and rarity ~= "promo"
                   and not dlc_locked
                   and not (mod._cim_versus_shadowed and mod._cim_versus_shadowed(item_data, real_names))
                   and gate_contract.gate_enumerated_row("athanor_list", key, item_data, gate_rejected) then
                    local dn = item_data.display_name or key
                    if not seen_names[dn] then
                        seen_names[dn] = true
                        weapon_layout[#weapon_layout + 1] = {
                            key = key,
                            item_data = item_data,
                            backend_id = nil,
                        }
                    end
                end
            end
        end
    end

    gate_contract.log_gate_rejections(printf, "athanor_list", gate_rejected, 8)

    -- #617: do not let a catalog/provider icon reach the list widget until its
    -- actual masked+saturated material is proven in this exact ui_top_renderer.
    -- CWV optionally exports a descriptor with a paired vanilla fallback; the
    -- policy also resolves the inherited base ItemMasterList icon so CIM stays
    -- safe across mod load order and when CWV is absent.
    local icon_policy = mod._cim_athanor_icon_policy
    if type(icon_policy) ~= "table" or type(icon_policy.sanitize_layout) ~= "function" then
        mod:warning("[cim:617] Athanor icon policy unavailable; using vanilla weapon list")
        return func(self)
    end
    local safe_layout, icon_report = icon_policy.sanitize_layout(weapon_layout, {
        item_master_list = ItemMasterList,
        provider_resolve = mod._cim_resolve_provider_inventory_icon,
        has_texture = function(texture_name)
            return icon_policy.renderer_has_texture(
                self._ui_top_renderer,
                texture_name,
                rawget(_G, "UIAtlasHelper"),
                rawget(_G, "Gui"),
                { masked = true, saturated = true })
        end,
    })
    mod._cim_athanor_icon_report = icon_report
    printf("[cim:617] Athanor icon closure total=%d verified=%d fallback=%d omitted=%d",
        icon_report.total, icon_report.verified, icon_report.fallback, icon_report.omitted)
    for i = 1, math.min(#icon_report.changes, 12) do
        local change = icon_report.changes[i]
        -- (#481) gate= names which residency gate refused the original icon.
        printf("[cim:617] icon key=%s original=%s replacement=%s gate=%s material=%s",
            tostring(change.key), tostring(change.original), tostring(change.replacement),
            tostring(change.gate), tostring(change.material))
    end
    if #icon_report.changes > 12 then
        printf("[cim:617] icon changes omitted_from_log=%d", #icon_report.changes - 12)
    end

    self:_populate_list(safe_layout)

    -- v0.7.53-dev: comprehensive menu-state probe. Logs every weapon currently
    -- in the Athanor menu list PLUS a full ItemMasterList sweep against the
    -- same filters so user reports of "weapon X didn't appear" are
    -- diagnosable from the log alone — without further code changes.
    -- Gated on enable_debug_logging (zero cost when off).
    if mod._cim_autodump_weapon_list_setup then
        pcall(mod._cim_autodump_weapon_list_setup,
            career_name,
            selected_slot_name,
            item_slot_types,
            weapon_layout,
            mod._cim_item_requires_unowned_dlc)
    end

    -- Strip weave-specific "Magic Level: 100" and "1800" power text from each entry; this is just a crafting template list.
    local scrollbar_data = self._scrollbars and self._scrollbars.weapons
    local list_widgets = scrollbar_data and scrollbar_data.list_widgets
    if list_widgets then
        for _, widget in ipairs(list_widgets) do
            local c = widget.content
            c.level_title = ""
            c.power_text = ""
            c.power_title = ""
            c.magic_level = 0
            c.level_progress = 0
        end
    end
end)

-- Keep the level/power fields blank — vanilla `_sync_backend_loadout` repopulates them every refresh.
-- _cim703_consolidated_sync_backend_loadout_hook: single hook on this (Class, method); #703 CWV lock-clear rides this body.
mod:hook("HeroWindowWeaveForgeWeapons", "_sync_backend_loadout", function(func, self)
    func(self)
    if not _custom_forge_active then return end
    local scrollbar_data = self._scrollbars and self._scrollbars.weapons
    local list_widgets = scrollbar_data and scrollbar_data.list_widgets
    if list_widgets then
        for _, widget in ipairs(list_widgets) do
            local c = widget.content
            c.level_title = ""
            c.power_text = ""
            c.power_title = ""
            -- #703: only rows vanilla just locked, and only cwv-provider keys.
            if c.locked and mod._cim_synthetic_item_contract.is_cwv_provider_key(c.key) then c.locked = false end
        end
    end
end)

-- --- Weapon select: present item without locked/essence state ---

mod:hook("HeroWindowWeaveForgeWeapons", "_present_item", function(func, self, item_key, activate_spin)
    if not _custom_forge_active then return func(self, item_key, activate_spin) end

    local viewport_data = self._viewport_data
    if viewport_data and viewport_data.item_previewer then
        viewport_data.item_previewer:destroy()
        viewport_data.item_previewer = nil
    end

    local backend_items = Managers.backend:get_interface("items")
    local item = backend_items:get_item_from_key(item_key)
    local display_item = item

    if not display_item then
        local entry = rawget(ItemMasterList, item_key)
        if entry then
            local item_data = table.clone(entry)
            item_data.key = item_key
            display_item = { data = item_data, key = item_key }
        end
    end

    local viewport_widget = viewport_data.widget
    local item_previewer = self:_create_item_previewer(viewport_widget, display_item, activate_spin)
    viewport_data.item_previewer = item_previewer
    viewport_data.item = display_item

    local item_data = display_item.data
    -- Power preview always shows the WILL-BE power (= the base_power_level
    -- slider). The input item's own power doesn't matter once you click Craft;
    -- the new item is created at base_power_level. Feedback #9: pre-v0.7.24
    -- the preview showed the input's power (often 5 for blacksmith templates)
    -- and confused users into thinking the crafted item would be 5 power.
    local base_power = (mod._cim_base_power and mod._cim_base_power()) or 300
    local input_power = display_item.power_level or base_power
    local power_text = tostring(base_power)
    if input_power ~= base_power then
        power_text = tostring(input_power) .. " > " .. tostring(base_power)
    end

    local widgets_by_name = self._widgets_by_name
    widgets_by_name.viewport_level_value.content.visible = false
    widgets_by_name.viewport_level_title.content.visible = false
    widgets_by_name.viewport_power_value.content.text = power_text
    widgets_by_name.viewport_power_title.content.visible = true
    widgets_by_name.viewport_power_value.content.visible = true
    widgets_by_name.viewport_title.content.text = Localize(item_data.display_name)
    widgets_by_name.viewport_sub_title.content.text = Localize(item_data.item_type)

    self:_set_presentation_locked_state(false)
    self._selected_item_locked = false
    self:_setup_weapon_stats(display_item)

    return item_key
end)

-- --- Weapon select: never show locked/unlock UI in custom forge ---

mod:hook("HeroWindowWeaveForgeWeapons", "_set_presentation_locked_state", function(func, self, locked)
    if not _custom_forge_active then return func(self, locked) end
    func(self, false)
end)

-- --- Weapon select: "CRAFT" button instead of "Equip" ---

mod:hook("HeroWindowWeaveForgeWeapons", "_update_equip_button_status", function(func, self, equipable_item, is_item_equipped)
    if not _custom_forge_active then return func(self, equipable_item, is_item_equipped) end

    local viewport_data = self._viewport_data
    if viewport_data then
        local equip_button = viewport_data.equip_button
        equip_button.content.button_hotspot.disable_button = not self._selected_item_id
        equip_button.content.title_text = "CRAFT"
    end
end)

-- --- Weapon select: on_list_index_selected — always enable craft button ---

mod:hook("HeroWindowWeaveForgeWeapons", "_on_list_index_selected", function(func, self, index)
    if not _custom_forge_active then return func(self, index) end

    local scrollbars = self._scrollbars
    local scrollbar_data = scrollbars.weapons
    local list_widgets = scrollbar_data.list_widgets

    for i, widget in ipairs(list_widgets) do
        local content = widget.content
        local hotspot = content.button_hotspot
        local is_selected = i == index

        hotspot.is_selected = is_selected

        if is_selected then
            self._selected_backend_id = self:_present_item(content.key)
            self._selected_item_id = content.key
        end
    end

    self._selected_list_index = index
    self:_update_equip_button_status(true, false)
end)

-- Build an Athanor-crafted item via the PlayFab backend mirror so it shows up
-- as a real inventory item (purple `promo` rarity, eligible for cosmetic skin
-- changes). Unlike MoreItemsLibrary's `add_mod_items_to_local_backend`, this
-- path doesn't tag the entry as a mod template — so the cosmetics screen and
-- skin swapper treat it as a normal owned weapon.
-- v0.7.62-dev: make a crafted item visible + usable in the ADVENTURE keep
-- inventory grid. A crafted clone inherits its source key's ItemMasterList
-- entry, and two vanilla fields on that entry can hide the result from the
-- Adventure grid:
--
--  1. can_wield is intentionally NOT mutated here. Weapon availability belongs
--     to WT/native/CWV. A CIM-only append created a live eligibility/action
--     divergence: the item could be equipped by a career whose effective
--     template lacked that career's action_career_* row (#661).
--
--  2. mechanisms — THE 5-day "crafted but not in inventory" bug. The Versus
--     carousel weapons (vs_*, e.g. vs_es_bastard_sword = "Gallant's Blade",
--     vs_es_blunderbuss = "Soldier's Coach Gun") carry mechanisms = {"versus"}.
--     The Adventure grid's filter macro `available_in_mechanism_adventure`
--     (backend_interface_common.lua:524) returns
--     `is_cosmetic or not mechanisms or table.contains(mechanisms,"adventure")`
--     — a {"versus"} item has mechanisms ≠ nil and no "adventure", so it's
--     rejected. The craft succeeds, the item IS in the mirror
--     (get_all_backend_items / found_in_all=true — which is why older probes
--     reported success), but the Adventure inventory grid hides it. Clearing
--     `mechanisms` makes `not mechanisms` true → the item passes. This also
--     retroactively surfaces already-crafted vs_* weapons, because the
--     boot-time `_athanor_inject_all` re-runs this for every saved craft.
--
-- We deliberately do NOT clear required_dlc — that is the paid-DLC paywall.
-- cim's weapon list already filters out unowned-DLC items, so the player only
-- ever crafts DLC content they own; the field stays so the gate is respected.
--
-- Mutates ItemMasterList directly per repo rule (BackendUtils.can_wield_item is
-- not hookable from a Workshop mod). Idempotent — safe to re-run every craft +
-- every boot re-inject.
local function _ensure_item_adventure_visible(item_key, career_name)
    if not item_key then return end
    local entry = rawget(ItemMasterList, item_key)
    if not entry then return end

    -- (1) can_wield remains byte-for-byte owned by its availability provider.
    -- career_name stays in this API for save/backward-call compatibility.

    -- (2) mechanisms: clear any non-adventure scoping (e.g. {"versus"}) so the
    -- Adventure keep grid's mechanism filter stops hiding the crafted item.
    if entry.mechanisms ~= nil then
        mod:info("[cim] mechanisms clear: %s was {%s} — now adventure-visible",
            tostring(item_key),
            type(entry.mechanisms) == "table" and table.concat(entry.mechanisms, ",") or tostring(entry.mechanisms))
        entry.mechanisms = nil
    end
end

local function _athanor_inject_item(weapon_data, backend_id)
    local backend_mirror = Managers.backend and Managers.backend:get_backend_mirror()
    if not backend_mirror then return nil, "backend mirror not ready" end

    -- Pre-check ItemMasterList: backend_mirror:add_item calls
    -- `ItemMasterList[item.ItemId]` (playfab_mirror_base.lua:2504), and the
    -- table's __index Crashifies on unknown keys → game-closing crash.
    -- Saved crafts can reference cwv_* items that the
    -- character_weapon_variants mod hasn't registered yet at this stage of
    -- backend init. Skip injection for unknown keys (re-craft is recoverable).
    local item_key = weapon_data.item_key
    local master = item_key and rawget(ItemMasterList, item_key)
    if not item_key or not master then
        return nil, "item_key '" .. tostring(item_key) .. "' not in ItemMasterList yet"
    end

    -- Ensure the new item is visible in the Adventure keep grid BEFORE it
    -- enters the mirror by clearing non-adventure `mechanisms` scoping (the
    -- vs_* Versus weapons). Availability/can_wield remains provider-owned.
    -- Called unconditionally — career_name may be nil for boot re-injects of
    -- old saves, but the mechanisms clear still needs to run for those.
    _ensure_item_adventure_visible(item_key, weapon_data.career_name)

    local contract = mod._cim_synthetic_item_contract
    -- issue 682 root fix (confirmed boundary, FS logs 2026-07-18/19,
    -- dr_ranger + wh_bountyhunter crafting `woc_blightreaper`): the prior
    -- `contract and contract.normalize_record(...)` and/or collapse
    -- truncated the multi-return, so the relic rejection logged `reason=nil`
    -- and chat read "Craft failed: nil". gate_record guarantees a classified
    -- reason (`provider:immutable_relic`); the relic row is also excluded at
    -- the athanor_list gate in `_setup_weapon_list` (issue 793 bypass), so
    -- this boundary is defense-in-depth.
    local normalized, normalize_err = contract.gate_record("mirror_injection",
        backend_id, weapon_data, master)
    if not normalized then
        printf("[cim:628] rejected mirror injection bid=%s key=%s reason=%s",
            tostring(backend_id), tostring(item_key), tostring(normalize_err))
        return nil, normalize_err
    end
    local cjson_mod = rawget(_G, "cjson")
    local encoder = cjson_mod and cjson_mod.encode
    local item, payload_err = contract.build_mirror_payload(normalized, master, encoder)
    if not item then return nil, payload_err end

    local ok, err = pcall(backend_mirror.add_item, backend_mirror, backend_id, item)
    if not ok then return nil, err end

    -- v0.7.59-dev: mark backend interfaces dirty so the inventory UI re-queries
    -- and surfaces the newly-added item. mirror:add_item updates the underlying
    -- table but does NOT bump the interface dirty bit — the inventory grid
    -- keeps showing its cached pre-add state until something else triggers a
    -- refresh. This is why user reports "I crafted X but it's not in
    -- inventory" while every cim probe shows the item IS in the mirror:
    -- the UI is querying stale data.
    --
    -- standard_forge.lua's craft hook calls dirtify_interfaces after its own
    -- synth runs. The Athanor path (_equip_item → _athanor_inject_item) was
    -- missing it; so was the properties-view jewelry path
    -- (_cim_amulet_craft_one_slot → _athanor_inject_item). Putting the call
    -- HERE catches all 5 callers in one place: `_athanor_retry_pending` (3051),
    -- `_athanor_inject_all` (3074), `_equip_item` (3145),
    -- `_cim_amulet_craft_one_slot` (3313), and the weapon/jewelry branch of
    -- `_upgrade_magic_level` (3391). (saveweapon_import.lua injects via its own
    -- mirror:add_item and gets the equivalent dirtify call inline — v0.7.60.)
    --
    -- Idempotent + cheap. Boot-time `_athanor_inject_all` calls fire before
    -- the UI is even open, which is fine — the flag is just a "next query
    -- should hit fresh data" hint.
    if Managers.backend and Managers.backend.dirtify_interfaces then
        pcall(Managers.backend.dirtify_interfaces, Managers.backend)
    end
    -- v0.7.60-dev (Way 2 second belt): dirtify_interfaces marks the interface
    -- dirty so the NEXT query re-fetches, but force an explicit re-fetch too so
    -- an already-built filtered list (e.g. an inventory grid open in another
    -- panel) rebuilds immediately rather than waiting for its own refresh tick.
    -- Redundant with dirtify on purpose — the missed-refresh failure is silent.
    local items_iface = Managers.backend and Managers.backend:get_interface("items")
    if items_iface and items_iface._refresh then
        pcall(items_iface._refresh, items_iface)
    end
    return backend_id
end

-- Install the atomic community-build importer only after the canonical mirror
-- injection function exists. Every dependency is late-bound or owner-provided;
-- the browser can load earlier but cannot commit until this seam is ready.
mod:dofile("scripts/mods/crafting_in_modded_dev/_cim_ranalds_import").install({
    mod = mod,
    catalog = mod._cim_ranalds_catalog,
    contract = mod._cim_synthetic_item_contract,
    inject_item = _athanor_inject_item,
    guid = function() return Application.guid() end,
    get_managers = function() return Managers end,
    get_globals = function()
        return {
            ItemMasterList = ItemMasterList,
            CareerSettings = CareerSettings,
            WeaponProperties = WeaponProperties,
            WeaponTraits = WeaponTraits,
        }
    end,
})

_rt_register("issue1360_ranalds_build_import", function()
    local catalog = mod._cim_ranalds_catalog
    local fetcher = mod._cim_ranalds_fetcher
    local importer = mod._cim_ranalds_import
    if type(catalog) ~= "table" or type(fetcher) ~= "table"
            or type(importer) ~= "table" then
        return "Ranald browser services are not installed"
    end
    local career_count, weapon_count = 0, 0
    for _ in pairs(catalog.CAREERS or {}) do career_count = career_count + 1 end
    for _ in pairs(catalog.WEAPONS or {}) do weapon_count = weapon_count + 1 end
    if career_count ~= 20 or weapon_count ~= 83 then
        return string.format("catalog drift careers=%d weapons=%d", career_count, weapon_count)
    end
    for _, field in ipairs({
        "_cim_register_crafts_batch", "_cim_unregister_crafts_batch",
        "_cim_snapshot_exact_loadout", "_cim_write_exact_loadout_item",
        "_cim_finalize_exact_loadout",
    }) do
        if type(mod[field]) ~= "function" then return "missing transaction API " .. field end
    end
    if type(fetcher.fetch) ~= "function" or type(fetcher.cancel) ~= "function"
            or type(importer.preflight) ~= "function" or type(importer.apply) ~= "function" then
        return "Ranald fetch/import API incomplete"
    end
end)

-- Re-add every saved mirror-path craft (Athanor + standard forge) to the live
-- backend mirror after PlayFab finishes its sync. Items flagged `via_mirror = false`
-- go through the legacy MIL path via `_forge_inject_all` instead.
-- Tracks bids whose first injection attempt was skipped (ItemMasterList not
-- ready). Retried on each subsequent `_create_interfaces` call AND on game
-- state transitions, so once CWV / other mods finish loading their items,
-- the saved crafts make it back into the inventory.
local _pending_inject = {}

_athanor_inject_all = function()
    local count, skipped = 0, 0
    _pending_inject = {}
    for bid, w in pairs(_forge_state.get_forged_weapons()) do
        if w.via_mirror then
            local mirror = Managers.backend and Managers.backend:get_backend_mirror()
            -- If the item is already in the mirror (a previous _create_interfaces
            -- call already injected it), skip the re-add. add_item is idempotent
            -- but logging extra "restored" lines is misleading.
            local already_in = mirror and mirror._inventory_items and mirror._inventory_items[bid]
            if already_in then
                count = count + 1
            else
                local ok, err = _athanor_inject_item(w, bid)
                if ok then
                    count = count + 1
                else
                    skipped = skipped + 1
                    _pending_inject[bid] = w
                    mod:info("Skipped saved craft %s: %s", tostring(w.item_key), tostring(err))
                end
            end
        end
    end
    if count > 0 then mod:info("Restored %d crafted weapons (mirror path)", count) end
    if skipped > 0 then
        -- "Ignore items from inactive mods" routes this to the log instead of
        -- chat so toggling mods doesn't spam the user (the retry still runs).
        local _msg = string.format("[cim] %d saved crafts deferred (waiting for sibling mods to register their ItemMasterList entries — will retry on next state transition)", skipped)
        if mod:get("ignore_unloadable_items") then mod:info(_msg) else mod:echo(_msg) end
    end
end

-- Retry any deferred injections. Called on `_create_interfaces` re-fires and
-- on game-state changes. Cheap when `_pending_inject` is empty.
local function _athanor_retry_pending()
    if not next(_pending_inject) then return end
    local recovered = 0
    for bid, w in pairs(_pending_inject) do
        local ok = _athanor_inject_item(w, bid)
        if ok then
            _pending_inject[bid] = nil
            recovered = recovered + 1
        end
    end
    if recovered > 0 then
        local _msg = string.format("[cim] Re-injected %d previously-deferred craft(s)", recovered)
        if mod:get("ignore_unloadable_items") then mod:info(_msg) else mod:echo(_msg) end
    end
end

-- Timer for the deferred "let the mirror settle" loadout restore. Set by
-- on_game_state_changed; consumed in mod.update (chain added at file bottom).
-- Counts down in real time; once it hits 0 we retry _restore_modded_loadout.
-- This catches the case where PlayFab's _set_inital_career_data /
-- _fix_career_data path wipes the user's saved modded loadout AFTER our
-- _create_interfaces hook already ran the first restore pass.
local _cim_loadout_restore_timer = nil

mod.on_game_state_changed = function()
    _cim947_trait_residency.ensure()
    _athanor_retry_pending()
    if mod._cim563_reset_vanilla_skin_rehydrate then
        mod._cim563_reset_vanilla_skin_rehydrate()
    end
    -- Schedule a deferred loadout restore. 1.0s is empirically enough for
    -- PlayFab's signin → request_characters → _set_inital_career_data →
    -- _fix_career_data round-trip to complete and the mirror to settle.
    -- A second pass at 3.0s catches slow modded-realm signin cases.
    _cim_loadout_restore_timer = 1.0
end

mod.update = function(dt)
    -- #624: interaction tables normally exist before mods load, but a title
    -- transition or hot reload can rebuild the registry. Idempotently restore
    -- our one predicate wrapper; install() is one comparison after success.
    if mod._cim_install_keep_forge_interaction then
        mod._cim_install_keep_forge_interaction()
    end
    -- Install the BackendUtils.set_loadout_item capture once the backend (and LA
    -- bridge) are up. Cheap once-guarded no-op after install. Issue #22 root fix.
    _install_backendutils_capture()

    -- #563: server inventory refreshes restore CustomData.skin into the live
    -- mirror. Reapply exact-instance local overrides only on a confirmed
    -- PlayFab mirror-ready edge; the helper is a cheap no-op otherwise.
    if mod._cim563_update_vanilla_skin_overrides then
        mod._cim563_update_vanilla_skin_overrides()
    end

    if _cim_loadout_restore_timer then
        _cim_loadout_restore_timer = _cim_loadout_restore_timer - (dt or 0)
        if _cim_loadout_restore_timer <= 0 then
            _cim_loadout_restore_timer = nil
            if _restore_modded_loadout then
                -- Idempotent: set_loadout_item just rewrites the mirror entry
                -- if it already matches. Safer than gating on "did PlayFab
                -- wipe us?" detection.
                _restore_modded_loadout()
            end
        end
    end
    -- v0.7.52-dev: drain pending post-craft visibility checks (gated on
    -- enable_debug_logging — zero cost when off). Each scheduled check counts
    -- down `frames_until_check`; when zero, asserts the crafted BID is
    -- reachable through the same path the inventory grid uses.
    if mod._cim_autodump_run_visibility_checks then
        pcall(mod._cim_autodump_run_visibility_checks)
    end
end

-- --- Weapon select: craft item on equip press ---

mod:hook("HeroWindowWeaveForgeWeapons", "_equip_item", function(func, self, backend_id_or_key)
    if not _custom_forge_active then return func(self, backend_id_or_key) end

    local item_key = self._selected_item_id
    if not item_key then
        mod:warning("[cim] Craft failed: no weapon selected")
        return
    end

    -- Resolve the crafting career once for persisted provenance and diagnostic
    -- probes. CIM does not mutate can_wield; availability stays provider-owned.
    local career_name = self._career_name
    if not career_name then
        local pl = Managers.player and Managers.player:local_player()
        local profile_index = pl and pl:profile_index()
        local career_index = pl and pl:career_index()
        local profile = SPProfiles and profile_index and SPProfiles[profile_index]
        career_name = profile and profile.careers and career_index
            and profile.careers[career_index] and profile.careers[career_index].name or "<unknown>"
    end

    local new_backend_id = Application.guid()
    local weapon_data = {
        item_key = item_key,
        properties = {},
        traits = {},
        -- Honor the base_power_level setting (was hardcoded 300 — weapons ignored
        -- the slider while the amulet path already read _cim_base_power). 2026-06-30.
        power_level = (mod._cim_base_power and mod._cim_base_power()) or 300,
        rarity = "modded",
        via_mirror = true,
        career_name = career_name,  -- persisted provenance; no can_wield mutation
    }

    local injected, err = _athanor_inject_item(weapon_data, new_backend_id)
    if not injected then
        mod:warning("[cim] Craft failed: " .. tostring(err))
        -- v0.7.52-dev: probe the failure path too — capture what state we
        -- attempted with, so failed crafts are diagnosable from the log.
        if mod._cim_autodump_craft_synth_result then
            pcall(mod._cim_autodump_craft_synth_result, "athanor_equip_FAIL",
                career_name, item_key, new_backend_id, weapon_data, false, err)
        end
        return
    end

    local registered, register_err = mod._cim_register_craft(new_backend_id, weapon_data)
    if not registered then
        Managers.backend:get_backend_mirror():remove_item(new_backend_id)
        mod:warning("[cim] Craft persistence rejected: " .. tostring(register_err))
        return
    end
    if mod._cim_note_craft_bid then mod._cim_note_craft_bid(new_backend_id) end

    -- Issue #562: default-on auto-equip targets the forge button's exact slot
    -- (`slot_melee` / `slot_ranged`) and the exact newly-created backend id.
    -- `_auto_equip_crafted_weapon` performs BOTH the indexed loadout write and
    -- live-unit recreation, avoiding issue #12's historical icon-only update.
    -- With the setting OFF (or if the guarded equip degrades), the successful
    -- craft remains in the inventory exactly as before.
    local auto_equipped, auto_result = false, "helper unavailable"
    if mod._cim_auto_equip_crafted_weapon then
        auto_equipped, auto_result = mod._cim_auto_equip_crafted_weapon(
            career_name,
            self._selected_slot_name,
            new_backend_id
        )
    end
    if mod:get("auto_equip_new_weapons") and not auto_equipped then
        pcall(printf, "[cim:562] crafted but auto-equip skipped career=%s slot=%s bid=%s reason=%s",
            tostring(career_name), tostring(self._selected_slot_name), tostring(new_backend_id), tostring(auto_result))
    end

    local _master = rawget(ItemMasterList, item_key)
    local _name = (_master and _master.display_name) or item_key
    local _result_text = auto_equipped and " - equipped in " .. tostring(self._selected_slot_name)
        or " - available in inventory"
    mod:echo("Crafted & saved: " .. tostring(Localize(_name)) .. " [" .. tostring(weapon_data.rarity) .. "]" .. _result_text)
    -- v0.8.7-dev: audio feedback. Vanilla _equip_item plays an equip sound on its
    -- success path, but our custom-forge branch returns before reaching it, so the
    -- Athanor weapon-select CRAFT button was SILENT (the echo + _equip_pulse_duration
    -- give visual feedback only). _play_sound delegates to _parent:play_sound
    -- (hero_window_weave_forge_weapons.lua:581).
    if self._play_sound then pcall(self._play_sound, self, "play_gui_craft_forge_button_completed") end

    -- v0.7.52-dev: comprehensive post-craft diagnostic. Verifies mirror write,
    -- item resolution, career visibility, BID heuristic, persistence — and
    -- schedules a 2-frame-later visibility check. Gated on enable_debug_logging
    -- so it costs nothing when off. This is the data we use to diagnose
    -- "weapons don't appear after crafting" reports.
    if mod._cim_autodump_craft_synth_result then
        pcall(mod._cim_autodump_craft_synth_result, "athanor_equip",
            career_name, item_key, new_backend_id, weapon_data, true, nil)
    end

    self._equip_pulse_duration = 0.5
end)

-- --- Overview: show the amulet viewport (modded jewellery + talents editor entry point) ---
-- Vanilla gates the central amulet viewport behind the WoM tutorial via
-- `amulet_introduced`. For the modded forge we always want it visible — it's
-- the entry point to the jewellery + talents editor (see AMULET_OF_ASHUR.md).

mod:hook("HeroWindowWeaveForgeOverview", "_initialize_viewports", function(func, self)
    if _custom_forge_active then
        self.amulet_introduced = true
    end
    return func(self)
end)

-- --- Amulet (viewport_2) click: let vanilla open its native amulet layout ---
-- `HeroWindowWeaveProperties.on_enter` (line 167-196) selects between two
-- pre-built layouts based on `self:_selected_item()`:
--   * non-nil → `weapon_slot_layout` (1 trait + 10 properties — for melee/ranged)
--   * nil      → `amulet_slot_layout` (3 traits + 30 properties × 3 layers + 6 talents)
-- The amulet viewport's `data.item` is nil, so a click flows through to
-- `weave_properties` with `selected_item = nil` and the WoM-style 3-section
-- amulet layout renders automatically. We don't override the click anymore;
-- our `BackendInterfaceWeavesPlayFab` hooks supply the bubble grid's data.
--
-- The `_forge_seed_item` / `_forge_apply_to_item` chain handles the 3-item
-- case via the `career_name + nil item_backend_id` key (the amulet's params
-- carry no `item_backend_id`); we read all three accessory slots and write
-- back to all three on apply. (See _forge_seed_amulet below.)

-- Single-slot amulet craft helper. Clones the equipped item's current state
-- (already mutated by `_forge_apply_to_amulet` on each bubble click) into a
-- fresh modded item, registers it in cim's save layer, and equips it.
-- Shared between the 3 cim-injected craft buttons (one per slot) and the
-- legacy "Craft All" iteration in the `_upgrade_magic_level` hook below.
-- Per `feedback_lua_forward_reference`, exposed as `mod._cim_amulet_craft_one_slot`
-- so the button click probe (defined ~1500 lines above) can resolve it at
-- call time without a forward-declaration dance.
local function _cim_amulet_craft_one_slot(properties_win, slot_index, slot_name)
    if not (slot_index and slot_name) then return false, "missing args" end
    local backend_items = Managers.backend and Managers.backend:get_interface("items")
    local career_name = properties_win and properties_win._career_name
    if not backend_items or not career_name then
        mod:warning("[cim] Craft: backend / career not ready")
        return false
    end
    local src_bid = backend_items:get_loadout_item_id(career_name, slot_name)
    local src_item = src_bid and backend_items:get_item_from_id(src_bid)
    local src_key = src_item and (src_item.key or src_item.ItemId)
    if not src_key then
        mod:echo("[cim] Craft " .. slot_name .. ": no equipped item to clone from")
        return false
    end
    local new_props = {}
    if src_item.properties then
        for k, v in pairs(src_item.properties) do new_props[k] = v end
    end
    local new_traits = {}
    if src_item.traits then
        for i, t in ipairs(src_item.traits) do new_traits[i] = t end
    end
    local power = (mod._cim_base_power and mod._cim_base_power()) or 300
    local new_bid = Application.guid()
    local weapon_data = {
        item_key = src_key,
        properties = new_props,
        traits = new_traits,
        power_level = power,
        rarity = "modded",
        via_mirror = true,
        career_name = career_name,  -- persisted provenance; no can_wield mutation
    }
    local injected, err = _athanor_inject_item(weapon_data, new_bid)
    if not injected then
        mod:warning("[cim] Craft " .. slot_name .. " failed: " .. tostring(err))
        return false
    end
    local registered, register_err = mod._cim_register_craft(new_bid, weapon_data)
    if not registered then
        Managers.backend:get_backend_mirror():remove_item(new_bid)
        mod:warning("[cim] Craft " .. slot_name .. " persistence rejected: "
            .. tostring(register_err))
        return false
    end
    if mod._cim_note_craft_bid then mod._cim_note_craft_bid(new_bid) end
    -- Craft only — see issue #12. Player equips from inventory.
    _amulet_dirty[slot_index] = false
    mod:echo("[cim] Crafted new " .. slot_name:gsub("^slot_", ""):gsub("_1$", "") .. " — equip from inventory")
    return true
end
mod._cim_amulet_craft_one_slot = _cim_amulet_craft_one_slot

mod:dofile("scripts/mods/crafting_in_modded_dev/_cim_temper_runtime")({
    mod = mod,
    is_active = function() return _custom_forge_active end,
    transaction = mod._cim_temper_transaction,
    loadout = _WEAVE_LOADOUT_OWNER,
    bulk_accessory_craft = _BULK_ACCESSORY_CRAFT,
    craft_accessory = _cim_amulet_craft_one_slot,
    inject_item = _athanor_inject_item,
})

-- Console commands let the user pick which slot the amulet click edits.
-- Phase A.5 will replace these with on-screen buttons inside the editor.
mod:command("amulet_n", "Amulet edits necklace next click", function()
    mod._cim_amulet_slot = "slot_necklace"
    mod:echo("[cim] Amulet → necklace")
end)
mod:command("amulet_c", "Amulet edits charm next click", function()
    mod._cim_amulet_slot = "slot_charm"
    mod:echo("[cim] Amulet → charm")
end)
mod:command("amulet_t", "Amulet edits trinket next click", function()
    mod._cim_amulet_slot = "slot_trinket"
    mod:echo("[cim] Amulet → trinket")
end)

-- Diagnostic/manual forge commands and exact-owner cleanup live behind one
-- hook-free owner. Accessors preserve reassigned entry stores without widening
-- the established flat mod._cim_* public surface.
local _install_command_owner = mod:dofile(
    "scripts/mods/crafting_in_modded_dev/_cim_command_owner")
_install_command_owner({
    mod = mod,
    is_custom_forge_active = function() return _custom_forge_active end,
    get_forged_weapons = _forge_state.get_forged_weapons,
    get_modded_loadout = _LOADOUT_OWNER.get_modded_loadout,
    get_more_items_lib = _forge_state.get_more_items_lib,
    forge_inject_item = _forge_inject_item,
    forge_create_item = _forge_create_item,
    forge_detect_mil = _forge_detect_mil,
    forge_save = _forge_save,
    modded_loadout_save = _modded_loadout_save,
})

-- Regression registrations live in one late-loaded module so every production
-- helper/hook above is installed before its invariant closes over the shared state.
-- The installer receives narrow accessors for entry-local mutable stores; public
-- flat mod._cim_* APIs and runtime hook/load order remain unchanged.
local _install_cleanup_regression_checks = mod:dofile(
    "scripts/mods/crafting_in_modded_dev/_cim_regression_cleanup")
_install_cleanup_regression_checks({
    mod = mod,
    rt_register = _rt_register,
    rt_src_read = _rt_src_read,
    accessory_property_policy = mod._cim959_accessory_property_policy,
})

local _install_regression_checks = mod:dofile(
    "scripts/mods/crafting_in_modded_dev/_cim_regression_checks"
)
_install_regression_checks({
    mod = mod,
    rt_register = _rt_register,
    rt_src_read = _rt_src_read,
    dbg = _dbg,
    dbg_alert = _dbg_alert,
    bubble_cap = _bubble_cap,
    value_for_bubbles = _value_for_bubbles,
    cap_grid_property_arrays = _cap_grid_property_arrays,
    ensure_item_adventure_visible = _ensure_item_adventure_visible,
    forge_load = _forge_load,
    is_in_keep = _is_in_keep,
    store_property_slot = _store_property_slot,
    accessory_property_policy = mod._cim959_accessory_property_policy,
    accessory_panel = _AccessoryPanel,
    overview_btn_render_field = _OVERVIEW_BTN_RENDER_FIELD,
    overview_drawn_fields = _OVERVIEW_DRAWN_FIELDS,
    get_custom_forge_active = function() return _custom_forge_active end,
    get_forged_weapons = _forge_state.get_forged_weapons,
    set_forged_weapons = _forge_state.set_forged_weapons,
    get_modded_loadout = _LOADOUT_OWNER.get_modded_loadout,
    set_modded_loadout = _LOADOUT_OWNER.set_modded_loadout,
    modded_loadout_load = _modded_loadout_load,
    rpc_schema = CIM_RPC_SCHEMA,
})

mod:info("[mem-probe] cim_dev boot_lua=+%.1f MB (of ~1024 MB lua_heap cap)", (collectgarbage("count") - _MEM_PROBE_T0_CIMD) / 1024)
