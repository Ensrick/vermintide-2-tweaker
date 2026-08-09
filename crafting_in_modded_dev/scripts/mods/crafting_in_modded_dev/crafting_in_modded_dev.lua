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

-- ============================================================
-- Rehook-warning interceptor (v0.7.51-dev)
-- ============================================================
-- VMF emits `mod:warning("(hook_safe): Attempting to rehook active hook
-- [<method>].")` when a second `hook_safe` registers on a Class+method
-- pair already hooked by this mod. The duplicate is silently dropped — so
-- the bug is invisible at runtime unless you grep the log. Capture every
-- such warning at boot into a module-level list; the
-- `no_duplicate_hook_safe_registrations` regression check reads the list
-- and FAILs if non-empty. Caught HeroWindowLoadoutInventory.on_enter being
-- registered twice (modded_rarities.lua + cim_debug.lua) in v0.7.50-dev.
local _cim_rehook_warnings = {}
mod._cim_rehook_warnings = _cim_rehook_warnings
local _orig_warning = mod.warning
mod.warning = function(self, fmt, ...)
    -- Render the message to a string for substring matching. Guard against
    -- format failures (fmt may have no %-specifiers and no varargs).
    local rendered
    if select("#", ...) > 0 and type(fmt) == "string" then
        local ok, s = pcall(string.format, fmt, ...)
        rendered = ok and s or fmt
    else
        rendered = tostring(fmt)
    end
    if type(rendered) == "string" and rendered:find("rehook active hook", 1, true) then
        _cim_rehook_warnings[#_cim_rehook_warnings + 1] = rendered
    end
    return _orig_warning(self, fmt, ...)
end

local MOD_VERSION = "0.8.116-dev"
mod:info("Crafting in Modded v%s loaded", MOD_VERSION)

-- RPC schema version for cim's mod-to-mod VMF RPCs (VMF_RECIPES.md § 10,
-- BUG_CLASSES § 9). The `cim_modded_slot` side-channel RPC prepends this as the
-- FIRST positional arg of every send; the receiver validates the incoming value
-- against this constant and DROPS the packet on mismatch (audit 2026-06-07,
-- v0.7.72-dev — the RPC previously shipped with no schema arg or receiver gate,
-- so a future payload-shape change between peers running different cim builds
-- would silently mis-decode). Initial value is 1; never define lower. Bump when
-- the payload shape of any cim RPC changes.
local CIM_RPC_SCHEMA = 1

-- Copied shared debug helper (master: tools/shared_lib/_lib_debug.lua). The
-- bundled copy keeps cim_dev standalone while exact-drift QA prevents a local
-- edit from returning issue 240's mod:warning chat spam.
local _dbg, _dbg_alert = mod:dofile("scripts/mods/crafting_in_modded_dev/_lib_debug")(mod, "[cim:dbg]")

-- Applied marker (PROJECT_STANDARDS.md § 3.6 "Applied marker line (universal)").
-- Walks the data widget tree, FNV-1a-32 hashes setting=value pairs, prints
-- one mod:info line at load. ALWAYS fires (operational telemetry).
local function _settings_fingerprint()
    local ok, data = pcall(require, "scripts/mods/crafting_in_modded_dev/crafting_in_modded_dev_data")
    if not ok or type(data) ~= "table" then return "nodata" end
    local keys = {}
    local function walk(node)
        if type(node) ~= "table" then return end
        if type(node.setting_id) == "string" then keys[#keys + 1] = node.setting_id end
        for _, child in pairs(node) do
            if type(child) == "table" then walk(child) end
        end
    end
    walk(data)
    if #keys == 0 then return "nosettings" end
    table.sort(keys)
    local parts = {}
    for i, k in ipairs(keys) do
        local v = mod:get(k)
        if v == true then       parts[i] = k .. "=1"
        elseif v == false then  parts[i] = k .. "=0"
        elseif v == nil then    parts[i] = k .. "=?"
        else                    parts[i] = k .. "=" .. tostring(v) end
    end
    local s = table.concat(parts, ";")
    local h = 2166136261
    for i = 1, #s do
        local byte = string.byte(s, i)
        local xored, place = 0, 1
        local hh, bb = h, byte
        for _ = 1, 32 do
            local hb, bbit = hh % 2, bb % 2
            if hb ~= bbit then xored = xored + place end
            place = place * 2
            hh = (hh - hb) / 2
            bb = (bb - bbit) / 2
        end
        h = (xored * 16777619) % 4294967296
    end
    return string.format("%08x", h)
end

mod:info("[cim:LOAD] v%s enabled fp=%s OK", MOD_VERSION, _settings_fingerprint())

-- Per PROJECT_STANDARDS § 3.6 + § 14a: dev/alpha/beta/0.x versions print
-- version to chat on load so the user can see what's active. Stable
-- (>=1.0.0) versions stay silent. Detect via MOD_VERSION string match.
if MOD_VERSION:find("-dev$") or MOD_VERSION:find("-alpha$") or MOD_VERSION:find("-beta$") or MOD_VERSION:find("-rc%d*$") or MOD_VERSION:find("^0%.") then
    mod:echo(string.format("[cim] v%s loaded", MOD_VERSION))
end

-- ============================================================
-- UNCONDITIONAL settings dump (config visibility for triage).
-- ============================================================
-- cim's settings are PURELY LOCAL — every value is read via mod:get, there is no
-- host-sync of crafting settings (the mod's only network_send is the loadout-slot
-- side-channel, not settings). So a single on-load dump of each peer's own mod:get
-- values captures the full effective config; there is no host-authoritative phase.
--
-- Walks the REALIZED data widget tree (mod:dofile, NOT a static text-scrape) so the
-- conditionally-pruned `allow_in_mission` widget (dropped when gut is absent,
-- _data.lua:257-269) is reflected accurately — the dump shows exactly what's
-- registered. Descends sub_widgets/widgets and skips type=="group" containers,
-- mirroring ct's _collect_setting_ids walker.
--
-- Emits via RAW printf with a distinctive `[cim-settings]` prefix. printf
-- (foundation/scripts/util/misc_util.lua:29) is a vanilla engine global =
-- print(string.format(...)); it bypasses BOTH the VMF per-mod logging toggle AND
-- cim's own mod.echo chat-redirect, so the host's REAL config (movespeed_2pct_mode,
-- base_power_level, persist_modded_loadouts, etc.) lands in the log on any host
-- regardless of logging state. Bounded (one pass, NOT per-frame); pcall-guarded so a
-- dump failure can never break load. Attached to `mod` (not a main-chunk local) to
-- stay under the Lua 5.1 200-locals-per-function cap; the inner locals live in this
-- function's own scope.
function mod._cim_dump_settings(phase)
    local ok, err = pcall(function()
        local data = mod:dofile("scripts/mods/crafting_in_modded_dev/crafting_in_modded_dev_data")
        local ids, seen = {}, {}
        local function visit(node)
            if type(node) ~= "table" then return end
            if type(node.setting_id) == "string" and node.type and node.type ~= "group"
                and not seen[node.setting_id]
            then
                seen[node.setting_id] = true
                ids[#ids + 1] = node.setting_id
            end
            if node.sub_widgets then for _, w in ipairs(node.sub_widgets) do visit(w) end end
            if node.widgets then for _, w in ipairs(node.widgets) do visit(w) end end
        end
        if type(data) == "table" then visit(data.options) end
        table.sort(ids)
        local function fmtv(v)
            if v == true then return "1"
            elseif v == false then return "0"
            elseif v == nil then return "?"
            else return tostring(v) end
        end
        printf("[cim-settings] BEGIN phase=%s v=%s count=%d", tostring(phase), tostring(MOD_VERSION), #ids)
        for _, id in ipairs(ids) do
            printf("[cim-settings] %s get=%s", id, fmtv(mod:get(id)))
        end
        printf("[cim-settings] END phase=%s", tostring(phase))
    end)
    if not ok then
        printf("[cim-settings] DUMP FAILED phase=%s err=%s", tostring(phase), tostring(err))
    end
end

-- Auto-fire on load (the full local config; cim has no host-authoritative phase).
mod._cim_dump_settings("load")

mod:command("cim_dump_settings", "Dump every cim setting_id + value to the log via raw printf", function()
    mod._cim_dump_settings("command")
    mod:echo("[cim] settings dumped to log ([cim-settings] lines).")
end)

-- /regression_test scaffold. Registrations at end of file.
local _RT_CHECKS = {}
local function _rt_register(name, fn)
    _RT_CHECKS[#_RT_CHECKS + 1] = { name = name, fn = fn }
end
mod._cim_rt_register = _rt_register

-- (#511) io-safe source reader. The VMF retail Stingray VM registers no `io`
-- library (mods are loadstring'd into the game's shared _G; the engine registers
-- `os` but not `io`), so a bare `io.open` throws "attempt to index global 'io'
-- (a nil value)" and the regression runner's pcall reports it as a FALSE FAIL on
-- healthy code (issue 479/511). Every source-pattern check routes its source read
-- through this helper, which returns nil (-> the check's "unreadable source => skip"
-- branch, a PASS) instead of throwing. In retail the source-text half is skipped and
-- the runtime asserts each check makes (anchor function / vanilla class + method) are
-- authoritative; the source-text needles still run under the modding-tools build / CI
-- and are the QA-gate candidates (PROJECT_STANDARDS 2.2b tier a).
local function _rt_src_read(path)
    local io_lib = rawget(_G, "io")
    if type(io_lib) ~= "table" or type(io_lib.open) ~= "function" then
        return nil
    end
    local f = io_lib.open(path, "r")
    if not f then return nil end
    local t = f:read("*a")
    f:close()
    return t
end
-- A check function returns:
--   nil                        -> PASS
--   "skip: <reason>"           -> SKIP (preconditions not met; not in-session, etc.)
--   any other truthy string    -> FAIL
--   error / pcall failure      -> FAIL (caught)
mod:command("cim_regression_test", "Run regression smoke checks for past bugs", function()
    local pass, fail, skip = 0, 0, 0
    mod:echo("=== cim regression_test (v%s) ===", MOD_VERSION)
    for _, c in ipairs(_RT_CHECKS) do
        local ok, err = pcall(c.fn)
        if ok and err == nil then
            mod:echo("  PASS: %s", c.name); pass = pass + 1
            mod:info("[regression] PASS %s", c.name)
        elseif ok and type(err) == "string" and err:sub(1, 5) == "skip:" then
            mod:echo("  SKIP: %s -- %s", c.name, err:sub(6):gsub("^%s+", "")); skip = skip + 1
            mod:info("[regression] SKIP %s: %s", c.name, err)
        else
            local msg = (not ok and tostring(err)) or tostring(err)
            mod:echo("  FAIL: %s -- %s", c.name, msg); fail = fail + 1
            mod:warning("[regression] FAIL %s: %s", c.name, msg)
        end
    end
    mod:echo("=== %d passed, %d failed, %d skipped ===", pass, fail, skip)
end)
mod:info("[regression-test-command] registered as /cim_regression_test")

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

-- ============================================================
-- Forge core (persistence + item creation)
-- ============================================================
local _more_items_lib = nil
local _forged_weapons = {}; mod._cim_custom_glow_notice = mod:dofile("scripts/mods/crafting_in_modded_dev/_cim_custom_glow_notice").new()
local _external_trait_providers = {}

local function _external_provider_availability()
    local available = {}
    for provider_id, spec in pairs(_external_trait_providers) do
        local active = spec and spec.available == true
        if spec and type(spec.is_available) == "function" then
            local ok, result = pcall(spec.is_available)
            active = ok and result == true
        end
        available[provider_id] = active
    end
    return available
end

local function _partition_external_traits(record, source_parked)
    local policy = mod._cim_external_trait_policy
    if type(record) ~= "table" or type(policy) ~= "table" then return false end
    local combined = policy.merge_traits(record.traits, source_parked or record.external_traits)
    local active, parked = policy.partition(combined, _external_provider_availability())
    record.traits = active
    record.trait = active[1]
    record.external_traits = parked
    return true
end

local function _forge_detect_mil()
    if _more_items_lib then return true end
    local ok, lib = pcall(get_mod, "MoreItemsLibrary")
    if ok and lib then
        _more_items_lib = lib
        return true
    end
    return false
end

local function _forge_save()
    local save_data = {}
    for bid, w in pairs(_forged_weapons) do
        save_data[bid] = {
            schema_version = w.schema_version,
            owner = w.owner,
            provider = w.provider,
            slot_type = w.slot_type,
            item_key = w.item_key,
            properties = w.properties,
            trait = w.trait,
            traits = w.traits,
            -- Provider-owned selections are parked here while their owner mod
            -- is absent. They never enter the live backend item until the
            -- provider re-registers its capability after all mods load.
            external_traits = w.external_traits,
            skin = w.skin,
            power_level = w.power_level or 300,
            rarity = w.rarity,
            via_mirror = w.via_mirror,
            rerolled_props_indices = w.rerolled_props_indices,
            rerolled_trait_indices = w.rerolled_trait_indices,
            -- v0.7.37-alpha: opaque sibling-mod overlay slot. cosmetics_tweaker
            -- uses this to persist per-instance custom-glow blobs alongside
            -- the skin choice. CIM does NOT interpret the contents — pure
            -- pass-through so consumers can evolve their schema without
            -- coordinating with the forge save layer. When cosmetics_tweaker
            -- isn't installed, the field sits unread on the in-memory entry
            -- and no apply path runs; the weavebound skin renders with its
            -- vanilla baked materials, which is the correct fallback.
            custom_glow = w.custom_glow,
        }
    end
    mod:set("forged_weapons", save_data)
end

local function _forge_load()
    local save_data = mod:get("forged_weapons")
    if not save_data or type(save_data) ~= "table" then return end
    _forged_weapons = {}
    for bid, w in pairs(save_data) do
        -- Backward-compat: legacy entries without `via_mirror` were saved by the
        -- Athanor (rarity=promo, mirror path) or the legacy `cim forge_confirm`
        -- (rarity=exotic, MIL path). Default via_mirror to true for promo/modded so
        -- the mirror restore path picks it up.
        local via_mirror = w.via_mirror
        if via_mirror == nil then via_mirror = (w.rarity == "promo" or w.rarity == "modded") end
        -- v0.7.0 migration: rewrite legacy `promo` saves to `modded` so they get
        -- the new rarity's behaviors (cog enabled, full customization window) on
        -- next session.
        local rarity = w.rarity
        if rarity == "promo" then rarity = "modded" end
        -- issue 682: gate_record replaces the `contract and contract.
        -- normalize_record(...)` form, whose and/or collapse truncated the
        -- multi-return and logged every rejection as `reason=nil`. The
        -- contract is dofile'd unconditionally above, so no nil guard.
        local contract = mod._cim_synthetic_item_contract
        local normalized, err = contract.gate_record("mirror_restore", bid, {
            item_key = w.item_key,
            slot_type = w.slot_type,
            properties = w.properties or {},
            trait = w.trait,
            traits = w.traits,
            skin = w.skin,
            power_level = w.power_level or 300,
            rarity = rarity,
            via_mirror = via_mirror,
            rerolled_props_indices = w.rerolled_props_indices,
            rerolled_trait_indices = w.rerolled_trait_indices,
            custom_glow = w.custom_glow,
        })
        if normalized then
            _partition_external_traits(normalized, w.external_traits)
            _forged_weapons[bid] = normalized
        else
            printf("[cim:628] rejected saved synthetic item bid=%s reason=%s",
                tostring(bid), tostring(err))
        end
    end
    local glow_count, should_log = mod._cim_custom_glow_notice:observe(_forged_weapons, get_mod)
    if should_log then pcall(printf, "[cim] %d weapon(s) have saved custom_glow blobs that won't apply (Tweaker: Cosmetics not installed); weavebound skin will render with vanilla defaults", glow_count) end
    _forge_save() -- persist any rarity migrations
end

-- Public helper for sibling modules (standard_forge.lua) to register a newly
-- crafted item into the persistent save layer. `via_mirror = true` means the
-- item is added via `backend_mirror:add_item` on session restore (not MIL).
mod._cim_register_craft = function(backend_id, weapon_data)
    local contract = mod._cim_synthetic_item_contract
    local item_key = type(weapon_data) == "table" and weapon_data.item_key
    local master = item_key and ItemMasterList and rawget(ItemMasterList, item_key)
    -- issue 682: gate_record classifies every rejection (the prior
    -- `contract and contract.normalize_record(...)` and/or collapse
    -- truncated the multi-return, so rejections logged `reason=nil`).
    local entry, err = contract.gate_record("mirror_injection", backend_id, weapon_data, master)
    if not entry then
        printf("[cim:628] rejected synthetic item registration bid=%s key=%s reason=%s",
            tostring(backend_id), tostring(item_key), tostring(err))
        return false, err
    end
    entry.external_traits = type(weapon_data) == "table" and weapon_data.external_traits or nil
    _partition_external_traits(entry)
    _forged_weapons[backend_id] = entry
    _forge_save()
    return true, entry
end

-- v0.7.37-alpha: sibling-mod updater for the opaque overlay slot. Lets
-- cosmetics_tweaker amend just the custom_glow blob on an existing entry
-- without rebuilding the whole weapon_data, and persists immediately.
-- Returns true on write (entry existed), false if backend_id is unknown
-- (caller should fall back to passing custom_glow at register time).
mod._cim_set_custom_glow = function(backend_id, blob)
    local entry = _forged_weapons[backend_id]
    if not entry then return false end
    entry.custom_glow = blob  -- nil clears
    _forge_save()
    return true
end

mod._cim_unregister_craft = function(backend_id)
    if _forged_weapons[backend_id] then
        _forged_weapons[backend_id] = nil
        _forge_save()
    end
end

mod._cim_get_craft = function(backend_id)
    return _forged_weapons[backend_id]
end

mod._cim_persist_crafts = function()
    _forge_save()
end

-- Cross-mod trait capability handshake (#655). Providers register only after
-- every mod main file has run, so this is independent of launcher load order.
-- CIM owns offering/persistence; the provider owns metadata and the proc.
mod._cim_register_external_trait_provider = function(provider_id, spec)
    local policy = mod._cim_external_trait_policy
    local trait_key = type(spec) == "table" and spec.trait_key
    local required = type(policy) == "table" and policy.REQUIRED_CAPABILITY_BY_PROVIDER
        and policy.REQUIRED_CAPABILITY_BY_PROVIDER[provider_id]
    if type(provider_id) ~= "string" or type(trait_key) ~= "string"
            or not policy or policy.RESERVED_PROVIDER_BY_TRAIT[trait_key] ~= provider_id
            or not required or spec.capability ~= required then
        return false, "invalid_provider_contract"
    end
    local weapon_traits = rawget(_G, "WeaponTraits")
    if not (weapon_traits and weapon_traits.traits
            and rawget(weapon_traits.traits, trait_key)) then
        return false, "provider_trait_row_missing"
    end
    _external_trait_providers[provider_id] = spec
    local installed, reason = policy.add_combination(
        weapon_traits.combinations, spec.category or "melee", trait_key)
    if not installed then return false, reason end

    local backend = Managers and Managers.backend
    local items = backend and backend:get_interface("items")
    local cjson_mod = rawget(_G, "cjson")
    local activated = 0
    for backend_id, record in pairs(_forged_weapons) do
        local parked_before = #(record.external_traits or {})
        _partition_external_traits(record)
        if parked_before > #(record.external_traits or {}) then activated = activated + 1 end
        local live
        if items then pcall(function() live = items:get_item_from_id(backend_id) end) end
        if live then
            local traits = {}
            for i, value in ipairs(record.traits or {}) do traits[i] = value end
            live.traits = traits
            if cjson_mod and live.CustomData then
                live.CustomData.traits = cjson_mod.encode(traits)
            end
        end
    end
    _forge_save()
    printf("[cim:655] external trait provider=%s capability=%s pool=%s activated=%d",
        provider_id, spec.capability, tostring(reason), activated)
    return true, reason, activated
end

mod._cim_is_modded_backend_id = function(backend_id)
    if not backend_id or type(backend_id) ~= "string" then return false end
    -- #592: exact persistence is ownership. CWV prefixes describe a definition
    -- family, not an acquired item, and historical auto-grants must go stale.
    return _forged_weapons[backend_id] ~= nil
end
-- HISTORICAL NOTE: this function used to also match UUID format
-- (`^%x+-%x+-%x+-%x+-%x+$`) on the theory that any UUID-like bid came from
-- `Application.guid()` (which we use). But VT2's `_create_fake_inventory_items`
-- also generates UUID bids for fake weapon-skin / cosmetic / weapon-pose items
-- (~1500+ of them when `unlock_all_illusions` is on). That false-positive
-- inflated diagnostic counts (inv_dump showed modded=1553 vs vanilla=887)
-- and masked the real cim-craft count. The exact check above only matches
-- items registered in `_forged_weapons`; #592 also retired the cwv_ heuristic.

-- Item-level "is this a modded craft?" check. Same as the backend_id check,
-- plus a rarity-based fallback: any item with our custom rarity ("modded", or
-- the legacy "promo" we used pre-v0.7.0) is treated as modded regardless of
-- bid format. The rarity is the load-bearing visual cue we apply to crafts, so
-- it's a more reliable signal than guessing at bid heuristics — covers crafts
-- saved by older mod versions whose bid format doesn't match our current
-- regex, items the player crafted on another machine that synced down, etc.
mod._cim_is_modded_item = function(item)
    if not item then return false end
    if item.rarity == "modded" or item.rarity == "promo" then return true end
    return mod._cim_is_modded_backend_id(item.backend_id)
end

_rt_register("issue628_provider_contract", function()
    local contract = mod._cim_synthetic_item_contract
    if type(contract) ~= "table" then return "synthetic item contract is missing" end
    local keys = {
        "cwv_dr_dawi_mace",
        "cwv_dr_dawi_mace_shield",
        "cwv_dr_dawi_dual_maces",
        "cwv_es_longsword",
    }
    local checked = 0
    for i = 1, #keys do
        local key = keys[i]
        local master = ItemMasterList and rawget(ItemMasterList, key)
        if master then
            checked = checked + 1
            local ok, problems = contract.validate_provider(key, master)
            if not ok then
                return key .. " incomplete: " .. table.concat(problems, ",")
            end
        end
    end
    local woc = ItemMasterList and rawget(ItemMasterList, "woc_blightreaper")
    if woc then
        checked = checked + 1
        local ok, problems, provider = contract.validate_provider("woc_blightreaper", woc)
        if ok or provider ~= "woc" or problems[1] ~= "immutable_relic" then
            return "woc_blightreaper was not rejected as an immutable relic"
        end
    end
    if checked == 0 then return "skip: CWV/WOC provider rows are not loaded" end
end)

_rt_register("issue628_saved_instance_contract", function()
    local contract = mod._cim_synthetic_item_contract
    for backend_id, record in pairs(_forged_weapons) do
        if record.schema_version ~= contract.SCHEMA_VERSION
                or record.owner ~= contract.OWNER
                or record.backend_id ~= backend_id
                or type(record.item_key) ~= "string" then
            return "malformed saved instance: " .. tostring(backend_id)
        end
    end
end)

-- issue 628: the acquisition selector and salvage filter must resolve one
-- canonical identity. Prove the selector actually delegates to the contract's
-- resolver (not a drifted copy), and that a CWV row presented with its inherited
-- BASE `.key` still resolves to its variant so it stays salvageable.
_rt_register("issue628_identity_resolvers_unified", function()
    local contract = mod._cim_synthetic_item_contract
    local selector = mod._cim_template_selector
    if type(contract) ~= "table" or type(contract.canonical_item_key) ~= "function" then
        return "contract canonical_item_key is missing"
    end
    if type(selector) ~= "table" or type(selector.canonical_key) ~= "function" then
        return "template selector is missing"
    end
    local shapes = {
        { backend_id = "cwv_es_longsword_100", key = "es_bastard_sword" },
        { backend_id = "opaque", data = { key = "es_bastard_sword", cwv_key = "cwv_es_longsword" } },
        { ItemId = "cwv_dr_dawi_mace", key = "cwv_dr_dawi_mace",
          data = { cwv_key = "cwv_dr_dawi_mace", slot_type = "melee" } },
        { cim_acquisition_key = "cwv_dr_dawi_dual_maces", key = "dr_dual_hammers" },
        { ItemInstanceId = "48400000-0000-4000-8000-000000000484",
          key = "es_handgun", CustomData = {
              cim_acquisition_key = "cwv_es_musket_old",
              cwv_key = "cwv_es_musket_old",
          } },
        { ItemId = "es_1h_sword", key = "es_1h_sword" },
    }
    for i = 1, #shapes do
        local item = shapes[i]
        local c = contract.canonical_item_key(item)
        local s = selector.canonical_key(item)
        if c ~= s then
            return "selector/contract identity drift: contract=" .. tostring(c)
                .. " selector=" .. tostring(s)
        end
    end
    if contract.canonical_item_key(shapes[1]) ~= "cwv_es_longsword" then
        return "base-keyed CWV instance did not resolve to its variant"
    end
    local normalized_shapes = {
        {
            bid = "48400000-0000-4000-8000-000000000484",
            input = { key = "es_handgun", CustomData = {
                cim_acquisition_key = "cwv_es_musket_old",
            } },
            expected = "cwv_es_musket_old",
        },
        {
            bid = "opaque",
            input = { key = "es_bastard_sword", data = {
                cwv_key = "cwv_es_longsword",
            } },
            expected = "cwv_es_longsword",
        },
        {
            bid = "cwv_dr_dawi_mace_100",
            input = { key = "dr_1h_hammer" },
            expected = "cwv_dr_dawi_mace",
        },
    }
    for i = 1, #normalized_shapes do
        local shape = normalized_shapes[i]
        local record, err = contract.normalize_record(shape.bid, shape.input)
        if not record or record.item_key ~= shape.expected then
            return "normalization/identity drift: expected=" .. shape.expected
                .. " actual=" .. tostring(record and record.item_key)
                .. " error=" .. tostring(err)
        end
    end
end)

_rt_register("issue484_crafted_old_musket_identity", function()
    local contract = mod._cim_synthetic_item_contract
    if type(contract) ~= "table" then return "synthetic item contract missing" end
    local master = ItemMasterList and rawget(ItemMasterList, "cwv_es_musket_old") or {
        cwv_variant = true,
        slot_type = "ranged",
        can_wield = { "es_mercenary" },
        template = "old_musket_template",
        item_type = "cwv_es_musket_old",
        inventory_icon = "es_handgun_01",
    }
    local bid = "48400000-0000-4000-8000-000000000484"
    local record = contract.normalize_record(bid, {
        item_key = "cwv_es_musket_old", rarity = "modded",
    }, master)
    if not record then return "Old Musket synthetic record rejected" end
    local payload = contract.build_mirror_payload(record, master, function() return "{}" end)
    local custom = payload and payload.CustomData
    if not custom or custom.cim_acquisition_key ~= "cwv_es_musket_old"
            or custom.cwv_key ~= "cwv_es_musket_old" then
        return "mirror payload dropped the exact Old Musket identity"
    end
    local reconstructed = {
        ItemInstanceId = bid,
        key = "es_handgun",
        data = { key = "es_handgun" },
        CustomData = custom,
    }
    if contract.canonical_item_key(reconstructed) ~= "cwv_es_musket_old" then
        return "base-shaped reconstructed UUID did not recover Old Musket identity"
    end
    local selector = mod._cim_template_selector
    if not selector or selector.canonical_key(reconstructed) ~= "cwv_es_musket_old" then
        return "Athanor/forge selector drifted from the Old Musket identity contract"
    end
end)


-- Legacy MIL entry builder, extracted verbatim to
-- `_cim_mil_entry_builder.lua` (issue 682 gate + decomposition ceiling).
local _forge_create_item = mod:dofile(
    "scripts/mods/crafting_in_modded_dev/_cim_mil_entry_builder")

local function _forge_inject_item(weapon_data, backend_id)
    if not _forge_detect_mil() then
        mod:echo("Forge: MoreItemsLibrary not found — install it from the Workshop")
        return false
    end

    local entry = _forge_create_item(weapon_data, backend_id)
    if not entry then return false end

    _more_items_lib:add_mod_items_to_local_backend({entry}, "crafting_in_modded_dev")
    if Managers.backend then
        local items = Managers.backend:get_interface("items")
        if items then items:_refresh() end
    end
    if ItemHelper and ItemHelper.mark_backend_id_as_new then
        pcall(ItemHelper.mark_backend_id_as_new, backend_id)
    end
    return true
end

local function _forge_inject_all()
    if not _forge_detect_mil() then return end
    for bid, w in pairs(_forged_weapons) do
        -- Mirror-path crafts (Athanor + standard forge) go through
        -- `_athanor_inject_all`. MIL is reserved for legacy `cim forge_confirm`
        -- console crafts that explicitly opted into the MIL path.
        if not w.via_mirror then
            local entry = _forge_create_item(w, bid)
            if entry then
                _more_items_lib:add_mod_items_to_local_backend({entry}, "crafting_in_modded_dev")
            end
        end
    end
    if Managers.backend then
        local items = Managers.backend:get_interface("items")
        if items then items:_refresh() end
    end
end

_forge_load()

local _athanor_inject_all -- forward declaration; defined in the Athanor section below
local _restore_modded_loadout -- forward declaration; defined in the inventory section below
-- Forward-declared so the get_property_mastery_costs hook (registered at
-- line ~1205) can call them. Their canonical definitions live in the
-- per-property bubble cap section further down (line ~1390). The hook fires
-- after mod load, so the upvalue is bound by then. Without this forward
-- declaration the closure resolves `_bubble_cap` as a nil global and the
-- Athanor crashes the first time a property button asks for its cost array.
-- Burned by `feedback_lua_forward_reference`.
local _bubble_cap
local _value_for_bubbles
local _bubbles_for_value

-- Forge freedom restore is installed later by `_cim_forge_picker_owner`.
-- Keep one forward local because HeroViewStateWeaveForge.on_exit is registered
-- before that original owner boundary and resolves the dispatcher at callback time.
local _cim_restore_forge_freedom
local _strip_weave
-- Picker store helper (defined alongside the bubble-cap math; shared by the
-- live set_loadout_property hook and /cim_regression_test). Forward-declared
-- here so the hook closure binds the upvalue.
local _store_property_slot
-- Read-chokepoint cap (defined alongside `_store_property_slot`; called by the
-- get_loadout_properties hook to trim grid occupancy to the bubble cap right
-- before vanilla reads it — #86 read-path guard). Forward-declared here.
local _cap_grid_property_arrays

mod:hook_safe("BackendManagerPlayFab", "_create_interfaces", function()
    _forge_load()
    _forge_inject_all()
    if _athanor_inject_all then _athanor_inject_all() end
    if _restore_modded_loadout then _restore_modded_loadout() end
    local count = 0
    for _ in pairs(_forged_weapons) do count = count + 1 end
    mod:info("Forge: restored %d forged crafts", count)
    if mod._cim_autodump_backend_ready then pcall(mod._cim_autodump_backend_ready) end

    -- ============================================================
    -- One-shot trim: existing items in the mirror with >10 properties
    -- ============================================================
    -- Consolidated here from standard_forge.lua (was a sibling
    -- registration on the same Class+method that VMF silently dropped
    -- as a duplicate per memory `feedback_vmf_hook_safe_no_chain`).
    -- Safety net only: clamp any item to the 10-slot grid ceiling (= the
    -- MAX_DISTINCT_PROPERTIES gate). This used to trim to 2 to dodge the
    -- HeroWindowItemCustomization button_hotspot_3 crash, but that crash is
    -- now guarded directly in `_update_property_option` (standard_forge.lua),
    -- so the trim no longer needs to be destructive at 2 — it only fires on
    -- genuinely malformed items carrying more than the grid can hold (>10).
    -- WARNING: pairs() order is nondeterministic, so this drops ARBITRARY
    -- properties beyond the keep limit — keep the limit at the grid ceiling
    -- so a legitimately-forged 10-property item is never touched.
    local items_iface = Managers.backend and Managers.backend:get_interface("items")
    local mirror = items_iface and items_iface._backend_mirror
    local inv = mirror and mirror._inventory_items
    if type(inv) == "table" then
        local trimmed = 0
        -- v0.7.33-alpha: per-item log so user reports of "<X> item missing
        -- properties after restart" are diagnosable from the log alone.
        for bid, item in pairs(inv) do
            local props = item and item.properties
            if type(props) == "table" then
                local KEEP_LIMIT = 10  -- 10-slot grid ceiling = MAX_DISTINCT_PROPERTIES
                local prop_count = 0
                local keep = {}
                local kept_keys = {}
                local dropped_keys = {}
                for k, v in pairs(props) do
                    prop_count = prop_count + 1
                    if prop_count <= KEEP_LIMIT then
                        keep[k] = v
                        kept_keys[#kept_keys + 1] = tostring(k)
                    else
                        dropped_keys[#dropped_keys + 1] = tostring(k)
                    end
                end
                if prop_count > KEEP_LIMIT then
                    item.properties = keep
                    if item.CustomData then
                        local cjson_mod = rawget(_G, "cjson")
                        if cjson_mod then
                            item.CustomData.properties = cjson_mod.encode(keep)
                        end
                    end
                    trimmed = trimmed + 1
                    local item_key = item.key or item.ItemId
                                    or (item.data and item.data.key) or "<unknown>"
                    mod:info("[trim] %s (bid=%s) kept=[%s] dropped=[%s]",
                        tostring(item_key), tostring(bid),
                        table.concat(kept_keys, ","),
                        table.concat(dropped_keys, ","))
                end
            end
        end
        if trimmed > 0 then
            mod:info("[cim] Trimmed %d items exceeding the 10-property grid ceiling.", trimmed)
        end
    end
end)

-- ============================================================
-- Vanilla-client compat: rewrite "modded" rarity on the wire
-- ============================================================
-- When the host has a cim craft equipped, the loadout sync RPC
-- (`rpc_sync_loadout_slot`, encoded by `LoadoutUtils.sync_loadout_slot` in
-- `helpers/loadout_utils.lua:13-42`) sends `rarity_id =
-- NetworkLookup.rarities["modded"]`. cim appends "modded" to that table at
-- mod load (modded_rarities.lua:114-120), so the id is `<vanilla_count>+1`
-- on hosts that have cim — and undefined on clients that don't.
--
-- A vanilla client receiving that id reverse-looks up via
-- `NetworkLookup.rarities[rarity_id]` in
-- `LoadoutUtils.create_loadout_item_from_rpc_data:73`, gets nil, stores
-- `item.rarity = nil`, and the next code path that does
-- `RaritySettings[item.rarity].order` (e.g.
-- `deus_chest_extension.lua:232-233`, `reward_popup_ui.lua:451`) fatals.
--
-- Fix: wrap-hook `sync_loadout_slot`, temporarily swap `item.rarity` to
-- "unique" before the RPC encodes it, restore after the call returns. The
-- swap is invisible to the host's local code (it sees the original rarity
-- on every read outside this single sync call) and the wire payload
-- carries a `rarity_id` that exists in EVERY client's NetworkLookup
-- (cim-installed OR vanilla), because cim only APPENDS to the rarities
-- table — vanilla ids 1..N are unchanged.
--
-- Downstream safety effect on clients without CIM: they retain `unique` and
-- never resolve a custom rarity id. CIM installations separately restore
-- presentation from a boolean-only side channel. The owner's Hold-Tab row is
-- also reconstructed from PlayerManager loadout data, so it needs the same
-- boolean mirrored locally; restoring the backend item alone is insufficient
-- (#598, source: ingame_player_list_ui_v2.lua:1500-1512).
--
-- This is the minimum-risk patch: a single wrap-hook on one function
-- catches every call site (`simple_inventory_extension.lua:885` on equip,
-- `player_unit_attachment_extension.lua:154` on attachment change,
-- `LoadoutUtils.hot_join_sync` on new-peer arrival).
-- Cim-client side-channel: per-(player, slot) "this slot's item is modded" flag.
-- Populated by a boolean-only `cim_modded_slot` RPC beside vanilla loadout sync.
-- Unknown handlers and malformed payloads fail closed; no resource identity crosses the wire.
--
-- Keyed by unique_id → slot_name → boolean; false authoritatively clears stale modded state.
local _cim_modded_slot_state = {}
local _cim921_log_count = 0
local CIM921_LOG_LIMIT = 24

local function _cim_unique_id(peer_id, local_player_id)
    return tostring(peer_id) .. ":" .. tostring(local_player_id)
end

local function _cim_apply_modded_slot_metadata(peer_id, local_player_id, slot_name, is_modded, source)
    if type(slot_name) ~= "string" or (is_modded ~= true and is_modded ~= false) then
        if _cim921_log_count < CIM921_LOG_LIMIT then
            _cim921_log_count = _cim921_log_count + 1
            printf("[cim:921] dropped invalid rarity metadata source=%s peer=%s slot=%s value=%s count=%d/%d",
                tostring(source), tostring(peer_id), tostring(slot_name), tostring(is_modded), _cim921_log_count, CIM921_LOG_LIMIT)
        end
        return false
    end

    local uid = _cim_unique_id(peer_id, local_player_id)
    local slot_state = _cim_modded_slot_state[uid]
    if not slot_state then
        slot_state = {}
        _cim_modded_slot_state[uid] = slot_state
    end

    local prior = slot_state[slot_name]
    slot_state[slot_name] = is_modded -- retain explicit false; nil means not received yet

    local before, after
    local pm = Managers and Managers.player
    local loadouts = pm and pm._player_loadouts
    local stored = loadouts and loadouts[uid] and loadouts[uid][slot_name]
    if stored then
        before = stored.rarity
        local core = mod._cim246_tab_preview_core
        if core and core.resolve_rarity then
            after = core.resolve_rarity(before, true, is_modded)
        elseif is_modded then after = "modded"
        elseif before == "modded" then after = "unique"
        else after = before end
        stored.rarity = after
    end

    if _cim921_log_count < CIM921_LOG_LIMIT
            and (prior ~= is_modded or (before ~= nil and before ~= after)) then
        _cim921_log_count = _cim921_log_count + 1
        printf("[cim:921] rarity metadata source=%s peer=%s slot=%s prior=%s current=%s stored=%s->%s count=%d/%d",
            tostring(source), tostring(peer_id), tostring(slot_name), tostring(prior),
            tostring(is_modded), tostring(before), tostring(after),
            _cim921_log_count, CIM921_LOG_LIMIT)
    end

    return true
end
mod._cim_apply_modded_slot_metadata = _cim_apply_modded_slot_metadata

-- ============================================================
-- MASTER loadout gate (loadout persistence REMOVED 2026-06-30)
-- ============================================================
-- Loadout persistence never worked reliably and is being REPLACED by a proper
-- loadout system in Tweaker: GUI (gut). The `persist_modded_loadouts` /
-- `restore_modded_loadout` menu toggles are gone. cim now force-disables the
-- whole path: the force-OFF below resets any user who had previously enabled it
-- (no toggle remains to turn it back on), so every cim loadout hook stays a
-- pass-through / no-op and the boot/keep restore + flat->indexed migration do
-- nothing — vanilla player AND bot loadouts are byte-identical to not having cim
-- (a bot gets its DESIGNATED vanilla loadout, never a host clone).
--
-- The capture/sync/restore/migration machinery is kept dormant (gated off by
-- this helper) pending full excision once gut's loadout system lands. The gate
-- still READS the setting so the regression sandbox can exercise the dormant
-- round-trip logic; production is pinned OFF by this load-time reset.
mod:set("persist_modded_loadouts", false, false)

local function _persist_loadouts_enabled()
    return mod:get("persist_modded_loadouts") == true
end
-- Exposed read-only for the regression test / debug probes.
mod._cim_persist_loadouts_enabled = _persist_loadouts_enabled

-- Pure wire-safety decision (issue 278 / issue 371): the rarity a crafted "modded"
-- item MUST be encoded as on the loadout RPC so a non-cim peer can decode it. Takes
-- NO persistence argument by construction, so this crash-safety coercion can never be
-- gated by a toggle. Single-sourced here and asserted by /cim_regression_test
-- (wire_rarity_rewrite_ungated).
local function _cim_wire_safe_rarity(rarity)
    if rarity == "modded" then return "unique" end
    return rarity
end
mod._cim_wire_safe_rarity = _cim_wire_safe_rarity

if rawget(_G, "LoadoutUtils") and LoadoutUtils.sync_loadout_slot then
    mod:hook(LoadoutUtils, "sync_loadout_slot", function(func, player, slot_name, item, sync_to_specific_peer_id)
        -- WIRE-SAFETY INVARIANT (issue 278 / issue 371 — NEVER crash a non-mod peer).
        -- A "modded" rarity_id is undefined on clients that don't run cim, so putting
        -- it on the loadout RPC CTDs them cold (RaritySettings[nil].order via
        -- NetworkLookup.rarities reverse-lookup). Coercing "modded" -> "unique" on the
        -- WIRE is a crash-safety invariant, NOT a persistence feature — it must run
        -- REGARDLESS of persist_modded_loadouts. The v0.8.15 master gate wrongly bundled
        -- this rewrite behind the (default-OFF) persistence toggle, so a default cim host
        -- crashed every vanilla client the instant a crafted (always-"modded") item was
        -- equipped. Wire safety is hoisted OUT of the gate below; only the persistence
        -- side-channel stays gated.
        local is_modded = item and item.rarity == "modded" or false

        -- #598: safe PRESENTATION metadata is not loadout persistence. VMF delivers
        -- this mod channel only to a peer advertising the same CIM handler; the
        -- schema-gated payload contains a boolean and no icon/model/material name.
        -- Send unconditionally so CIM peers can restore the local modded frame while
        -- non-CIM peers retain the vanilla-safe `unique` wire rarity.
        do
            local peer_id = player:network_id()
            local local_player_id = player:local_player_id()
            -- `network_send(..., "others", ...)` excludes the sender. Prime the
            -- same tri-state locally before vanilla queues its self RPC so the
            -- owner and observers consume one identical presentation contract.
            _cim_apply_modded_slot_metadata(peer_id, local_player_id, slot_name,
                is_modded, "sender")
            -- Send even is_modded=false so equipping a non-modded item clears any stale
            -- modded flag on that slot. CIM_RPC_SCHEMA is the FIRST positional arg after
            -- the target (VMF_RECIPES § 10); the receiver gate drops shape mismatches.
            local target = sync_to_specific_peer_id or "others"
            local ok_send, err_send = pcall(mod.network_send, mod, "cim_modded_slot",
                target, CIM_RPC_SCHEMA, peer_id, local_player_id, slot_name, is_modded)
            if not ok_send then mod:info("[cim] side-channel send failed: %s", tostring(err_send)) end
        end

        if not is_modded then
            return func(player, slot_name, item, sync_to_specific_peer_id)
        end

        -- Unconditional wire rewrite: swap to a vanilla rarity for the RPC encode, then
        -- restore the host-local value immediately so the host's own UI is untouched.
        local original = item.rarity
        item.rarity = _cim_wire_safe_rarity(original)
        local ok, err = pcall(func, player, slot_name, item, sync_to_specific_peer_id)
        item.rarity = original
        if not ok then mod:info("[cim] sync_loadout_slot rewrite error: %s", tostring(err)) end
    end)
end

-- Cim-client side-channel receiver. Records the per-slot modded flag and, if
-- the loadout RPC already arrived (out-of-order delivery), patches the stored
-- item's rarity back to "modded" immediately. Vanilla clients never register
-- this handler so the RPC is dropped harmlessly there.
local function _rpc_cim_modded_slot(sender_peer_id, schema_version, peer_id, local_player_id, slot_name, is_modded)
    -- audit 2026-06-07 (v0.7.72-dev): schema gate (VMF_RECIPES § 10 / BUG_CLASSES
    -- § 9). VMF injects sender_peer_id; schema_version is the first WIRE arg. Drop
    -- (no state mutation) when a peer on a different cim build sends an incompatible
    -- payload shape, rather than mis-binding it to the wrong positional slots.
    if schema_version ~= CIM_RPC_SCHEMA then
        _dbg_alert("[rpc:schema] cim_modded_slot mismatch from peer=%s: peer sent v%s, we expect v%s. Dropping.",
            tostring(sender_peer_id), tostring(schema_version), tostring(CIM_RPC_SCHEMA))
        return
    end
    -- Record true AND false. This also reconciles an already-arrived vanilla
    -- loadout RPC, covering either ordering between the two reliable channels.
    _cim_apply_modded_slot_metadata(peer_id, local_player_id, slot_name,
        is_modded, "receiver")
end
mod:network_register("cim_modded_slot", _rpc_cim_modded_slot)

-- Exposed for /cim_regression_test (rpc_schema_gate_drops_on_mismatch): lets the
-- test drive the receiver synthetically and assert the schema gate drops on a
-- bad version (audit 2026-06-07, v0.7.72-dev).
mod._cim_rpc_modded_slot = _rpc_cim_modded_slot
mod._cim_modded_slot_state = _cim_modded_slot_state

-- _cim_consolidated_rpc_sync_loadout_slot_hook — the SOLE cim hook on
-- (PlayerManager, rpc_sync_loadout_slot). Two concerns share this one body
-- (VMF drops a second hook on the same pair from the same mod, CLAUDE.md
-- non-negotiable 8):
--
-- 1. v0.8.51-dev (issue 278) PRE-decode guard: vanilla's decode
--    (`LoadoutUtils.create_loadout_item_from_rpc_data`, loadout_utils.lua:72)
--    does `NetworkLookup.item_names[item_id]` on the NUMERIC wire id; a
--    missing index hits the strict __index error metamethod
--    (network_lookup.lua:2521) and CTDs this client. Modded item_names
--    entries are index-appended per peer, so a host whose mod set appended
--    MORE entries (e.g. Loremaster's Armoury clones via cosmetics_tweaker's
--    _la_bridge — enabled on the 07-04 host, disabled on the crashed client)
--    emits ids past our table's end. The primary fix is sender-side in CWV
--    0.1.365-dev (base_weapon key substitution); this guard is the second
--    layer so NO unknown id — from any mod, any peer — can CTD a cim client.
--    Dropping the RPC only means the remote loadout panel keeps the previous
--    item for that slot; nothing else consumes `_player_loadouts` on clients.
--    This hook was `mod:hook_safe` (post-decode only) before v0.8.51-dev; it
--    had to become a full wrap because a safe-hook cannot run BEFORE vanilla.
--
-- 2. Post-decode "modded" rarity restore (pre-existing behavior, unchanged):
--    fires AFTER vanilla has stored the item under
--    `_player_loadouts[unique_id][slot_name]` with rarity = "unique" (the
--    wire value). We look up the side-channel flag for that (peer, slot) and
--    upgrade in-place. No-op if the side-channel hasn't arrived yet — the
--    side-channel receiver above handles the inverse out-of-order case.
mod:hook("PlayerManager", "rpc_sync_loadout_slot", function(func, self, channel_id, peer_id, local_player_id, slot_id, item_id, rarity_id, power_level, buff_ids, buff_value_type_ids, buff_values)
    -- [cim:278] pre-decode guard. rawget bypasses NetworkLookup's strict
    -- __index error metamethod; nil = this peer never registered that index.
    local NL = rawget(_G, "NetworkLookup")
    local names = NL and NL.item_names
    if names and item_id ~= nil and rawget(names, item_id) == nil then
        printf("[cim:278] ALERT dropped rpc_sync_loadout_slot: item_names id %s unknown on this peer (from peer=%s slot_id=%s rarity_id=%s). Host/client modded-item registration diverges — make sure every peer runs the same mods and current builds.",
            tostring(item_id), tostring(peer_id), tostring(slot_id), tostring(rarity_id))
        return
    end

    -- Every vanilla param threaded through unchanged (player_manager.lua:69) —
    -- dropping trailing args from a wrap hook corrupts the relay
    -- (send_rpc_clients at player_manager.lua:83 re-sends them).
    func(self, channel_id, peer_id, local_player_id, slot_id, item_id, rarity_id, power_level, buff_ids, buff_value_type_ids, buff_values)

    -- #598: this is same-schema presentation metadata, independent of retired
    -- loadout persistence. Resource identities remain absent from this payload.
    local uid = _cim_unique_id(peer_id, local_player_id)
    local slot_state = _cim_modded_slot_state[uid]
    if not slot_state then return end
    local slot_name = NL and NL.equipment_slots and NL.equipment_slots[slot_id]
    if not slot_name or slot_state[slot_name] == nil then return end
    local stored = self._player_loadouts and self._player_loadouts[uid] and self._player_loadouts[uid][slot_name]
    if stored then
        local is_modded = slot_state[slot_name]
        stored.rarity = mod._cim246_tab_preview_core
            and mod._cim246_tab_preview_core.resolve_rarity(stored.rarity, true, is_modded)
            or (is_modded and "modded" or (stored.rarity == "modded" and "unique" or stored.rarity))
    end
end)
mod._cim_rpc_loadout_guard_installed = true

-- ============================================================
-- Modded inventory filter + loadout restore
-- ============================================================
-- The mod-realm view: hide vanilla weapons from the inventory grid (toggleable),
-- and remember the last modded item the player equipped on each (career, slot)
-- so that switching to vanilla and back doesn't wipe their modded loadout.


-- ============================================================
-- Persisted modded-loadout store — INDEX-AWARE schema (v0.8.13-dev)
-- ============================================================
-- Schema: _modded_loadout[career_name][loadout_index][slot_name] = backend_id.
--
-- WHY the index dimension exists (the v0.8.13-dev bot-loadout fix):
-- VT2 stores gear as PlayFabMirrorBase._career_data[career][loadout_index][slot].
-- `_career_loadouts[career]` is the player's SELECTED (active) index;
-- `PlayerData.loadout_selection.bot_equipment[career]` is a bot's DESIGNATED
-- index. Vanilla bot equip READS each bot's gear from its DESIGNATED index
-- (backend_interface_item_playfab.lua:150 →
-- get_character_data(career, slot, bot_loadout_index)).
--
-- The pre-0.8.13 store was FLAT (career -> slot -> bid) with no index. Both
-- capture hooks dropped `optional_loadout_index`, and restore wrote with no
-- index arg, so set_loadout_item/set_character_data DEFAULTED every write to
-- the SELECTED index (playfab_mirror_base.lua:1930). Result: a bot's
-- designated-index modded gear was never persisted/restored to that index ->
-- bots cloned the host's selected loadout; and the player's modded items got
-- conflated across loadout switches. Adding the index dimension fixes both:
-- captures store the bid under the index it was actually written to, and
-- restore stamps each saved item back into ITS index.
local _modded_loadout = {}

-- Resolve the LIVE selected loadout index for a career from the backend mirror,
-- LA-safe (same _backend_mirror access pattern used at ~:549). Returns an
-- integer index, or `fallback` (default 1) when the mirror / career isn't
-- available yet. Never throws — capture/restore call this at timing-fragile
-- moments where the mirror may be nil.
local function _resolve_selected_index(career_name, fallback)
    fallback = fallback or 1
    if not career_name then return fallback end
    local items_iface = Managers.backend and Managers.backend.get_interface
        and Managers.backend:get_interface("items")
    local mirror = items_iface and items_iface._backend_mirror
    if not mirror then return fallback end
    -- Prefer the direct table read; fall back to the public accessor.
    local ok, idx = pcall(function()
        if mirror._career_loadouts then
            return mirror._career_loadouts[career_name]
        end
    end)
    if ok and type(idx) == "number" then return idx end
    if mirror.get_career_loadouts then
        local ok2, sel = pcall(mirror.get_career_loadouts, mirror, career_name)
        if ok2 and type(sel) == "number" then return sel end
    end
    return fallback
end

-- Detect whether a career's stored value is the OLD flat shape
-- (slot_name -> bid string) vs the NEW indexed shape (index -> {slot -> bid}).
-- Heuristic, type-safe against partial/corrupt data:
--   * indexed: at least one entry keyed by a NUMBER whose value is a table.
--   * flat:    at least one entry keyed by a STRING (slot name) whose value is
--              a string bid (or nil).
-- A career table with only number->table entries is indexed; anything carrying
-- a string-keyed string value is treated as flat and migrated.
local function _career_value_is_flat(career_tbl)
    if type(career_tbl) ~= "table" then return false end
    for k, v in pairs(career_tbl) do
        if type(k) == "string" then
            -- A slot-name key. Flat shape (value should be a bid string, but
            -- even a stray non-table here means this isn't the indexed shape).
            return true
        elseif type(k) == "number" and type(v) ~= "table" then
            -- A numeric key pointing at a non-table = corrupt; not valid
            -- indexed data. Treat as flat so migration re-homes it safely.
            return true
        end
    end
    return false
end

-- v0.7.67-dev (issue #22): tracks the bid we last re-equipped onto the LIVE keep
-- avatar per "career/slot", so the repeated restore passes (1.0s + 3.0s deferred)
-- don't destroy+recreate the same weapon unit every pass (visible flicker). Keyed
-- "career/slot" → bid. Cleared for a slot when the equip-capture hook sees a
-- change there, so a later restore re-applies if needed.
local _reequipped = {}

-- True only while _restore_modded_loadout is replaying saved state. The capture
-- path checks this so restore's OWN set_loadout_item writes don't: (a) re-process
-- into _modded_loadout (and mutate it mid-pairs()-iteration), nor (b) pre-mark
-- _reequipped and starve the live re-equip (the v0.7.67 self-defeat bug that left
-- [reequip] empty).
local _restoring = false

local function _modded_loadout_save()
    mod:set("modded_loadout", _modded_loadout)
end

-- One-time, NO-DATA-LOSS migration from the old FLAT schema
-- (career -> slot -> bid) to the indexed schema
-- (career -> index -> slot -> bid). Existing users' saved data is flat; we
-- re-home each flat entry under the career's REAL (live selected) loadout index.
-- That's the safest target: pre-0.8.13 cim only ever stamped the SELECTED index,
-- so the flat entries WERE the selected-index gear — assigning them there
-- preserves the exact prior behavior for the player's active loadout while
-- unlocking per-index storage going forward.
--
-- ⚠ TIMING (v0.8.14-dev fix for the v0.8.13-dev blocker): this MUST run at a
-- MIRROR-READY moment, NOT at script-eval / boot. `_resolve_selected_index`
-- only returns the real per-career selected index once the backend mirror
-- exists; at boot it always falls back to 1, which would home EVERY migrated
-- flat entry under index 1. For a player whose actual selected index is not 1,
-- that re-homed their saved gear to the wrong loadout and the keep avatar
-- re-equipped vanilla (`_reequip_live_avatar` reads the live selected index and
-- found nothing there). The migration is therefore driven from
-- `_restore_modded_loadout` (mirror-confirmed) via `_run_loadout_migration`
-- below, NOT from `_modded_loadout_load`.
--
-- Mutates `data` in place (per career). Returns true if anything was migrated
-- (caller persists). Guards every step against partial/corrupt entries; never
-- drops a saved bid. The `mirror_ready` flag gates the fallback: when the mirror
-- is confirmed up we DO accept the resolved index (even if it's 1, that's the
-- real selected index); when it's NOT up we SKIP the career entirely and leave
-- it flat for a later pass (don't home to a guessed index).
local function _migrate_modded_loadout(data, mirror_ready)
    if type(data) ~= "table" then return false end
    local migrated = false
    for career_name, career_tbl in pairs(data) do
        if _career_value_is_flat(career_tbl) then
            if not mirror_ready then
                -- Mirror not up yet — DON'T guess an index. Leave this career
                -- flat; the next mirror-ready restore pass migrates it.
                mod:info("[loadout-migrate] %s deferred (mirror not ready)", tostring(career_name))
            else
                local index = _resolve_selected_index(career_name)
                local indexed = { [index] = {} }
                for slot_name, bid in pairs(career_tbl) do
                    -- Only re-home well-formed (string slot -> bid) entries; keep
                    -- any stray numeric->table entry (mixed/corrupt save) intact so
                    -- no data is lost.
                    if type(slot_name) == "string" then
                        indexed[index][slot_name] = bid
                    elseif type(slot_name) == "number" and type(bid) == "table" then
                        indexed[slot_name] = bid
                    end
                end
                data[career_name] = indexed
                migrated = true
                mod:info("[loadout-migrate] %s flat->indexed under live selected index %d",
                    tostring(career_name), index)
            end
        end
    end
    return migrated
end

-- One-shot guard: once a mirror-ready migration pass converts every flat career
-- and persists, this flips true so subsequent restore passes don't re-scan /
-- re-migrate. It is also idempotent WITHOUT the flag — `_career_value_is_flat`
-- returns false for already-indexed careers, so a re-run is a no-op — but the
-- flag avoids the per-pass walk and the redundant persist on the 1.0s/3.0s
-- deferred restore passes and the manual /cim_restore_loadout command.
local _loadout_migration_done = false

-- Mirror-ready migration driver. Called from `_restore_modded_loadout` (where
-- the backend mirror is confirmed loaded). Detects any remaining flat-shape
-- career, homes it to its REAL live selected index, and persists once. If the
-- mirror is somehow still unavailable, migrates nothing this pass and leaves the
-- one-shot flag UNSET so the next deferred pass re-attempts (no data lost).
local function _run_loadout_migration()
    if _loadout_migration_done then return end
    -- Confirm the mirror really is reachable before committing to an index.
    local items_iface = Managers.backend and Managers.backend.get_interface
        and Managers.backend:get_interface("items")
    local mirror_ready = (items_iface and items_iface._backend_mirror) and true or false
    local migrated = _migrate_modded_loadout(_modded_loadout, mirror_ready)
    if migrated then
        _modded_loadout_save()
    end
    -- Only declare the one-shot done once we've actually had a mirror-ready pass
    -- AND nothing flat remains. If the mirror wasn't ready, leave the flag unset
    -- so the next restore pass re-attempts.
    if mirror_ready then
        local any_flat = false
        for _, career_tbl in pairs(_modded_loadout) do
            if _career_value_is_flat(career_tbl) then any_flat = true break end
        end
        if not any_flat then _loadout_migration_done = true end
    end
end

-- Boot/script-eval load: pull the raw saved payload into memory AS-IS (flat or
-- indexed). NO migration here — migration is deferred to `_run_loadout_migration`
-- at the first mirror-ready restore pass (see the timing note above). Until then
-- `_modded_loadout` may carry the OLD flat shape for some careers; every early
-- consumer that walks it before the migration runs must tolerate the flat shape
-- (audited v0.8.14-dev: `_cim_clear_modded_loadout_for_bid` is the only such
-- pre-mirror consumer and now handles both shapes; the restore loop and
-- `_reequip_live_avatar` run AFTER `_run_loadout_migration` in the same call).
local function _modded_loadout_load()
    local data = mod:get("modded_loadout")
    if type(data) == "table" then
        _modded_loadout = data
    else
        _modded_loadout = {}
    end
end

_modded_loadout_load()

-- Public helper for sibling modules (standard_forge.lua salvage synth) to drop
-- a salvaged backend_id out of the saved loadout — otherwise loadout-restore
-- on next session would try to re-equip a non-existent item.
mod._cim_clear_modded_loadout_for_bids = function(backend_ids)
    local core = mod._cim277_bulk_core
    local dirty = core and core.clear_loadout_refs
        and core.clear_loadout_refs(_modded_loadout, backend_ids)
    if dirty then _modded_loadout_save() end
    return dirty and true or false
end

mod._cim_clear_modded_loadout_for_bid = function(backend_id)
    if not backend_id then return false end
    return mod._cim_clear_modded_loadout_for_bids({ backend_id })
end

-- v0.7.33-alpha one-shot migration. Old (pre-v0.7.33) cim never cleared
-- _modded_loadout entries when the user equipped a non-cim item. The fix in
-- v0.7.33 keeps state correct GOING FORWARD but doesn't heal save data from
-- before the fix. This migration walks _modded_loadout once at session load
-- and purges every entry whose bid isn't in `_forged_weapons` (cim crafts)
-- and doesn't match `cwv_*` (character_weapon_variants). Stale entries
-- pointing to non-existent items can't be restored anyway, so dropping them
-- avoids re-trying the same MISSING restore log line every session.
-- LOAD-BEARING compatibility exception, not ownership: see
-- docs/CROSS_MOD_ARCHITECTURE.md "CIM ↔ CWV backend-ID convention" and #70/#592.
local function _modded_loadout_purge_stale()
    local removed = 0
    -- Indexed schema: career -> index -> slot -> bid.
    for career_name, indices in pairs(_modded_loadout) do
        if type(indices) == "table" then
            for index, slots in pairs(indices) do
                if type(slots) == "table" then
                    for slot_name, bid in pairs(slots) do
                        local keep = false
                        if type(bid) == "string" then
                            if _forged_weapons[bid] then keep = true
                            elseif bid:sub(1, 4) == "cwv_" then keep = true
                            end
                        end
                        if not keep then
                            slots[slot_name] = nil
                            removed = removed + 1
                            mod:info("[loadout-purge] %s[%s]/%s -> %s (bid not in forged_weapons or cwv_*)",
                                tostring(career_name), tostring(index), tostring(slot_name), tostring(bid))
                        end
                    end
                end
            end
        end
    end
    if removed > 0 then
        _modded_loadout_save()
        mod:info("[loadout-purge] removed %d stale loadout entries", removed)
    end
end

-- Sibling-mod post-restore extension point. cosmetics_tweaker registers its
-- LA-illusion / paint / offhand reapply here so the re-apply runs AFTER cim
-- has restored the modded backend_ids to their loadout slots. Fires on every
-- restore pass (initial + 1.0s deferred + 3.0s deferred), so registered
-- callbacks must be idempotent. Public API: `mod._cim_register_restore_callback(fn)`.
local _restore_callbacks = {}
mod._cim_register_restore_callback = function(fn)
    if type(fn) ~= "function" then
        mod:info("[restore] register_restore_callback ignored: arg not a function")
        return false
    end
    _restore_callbacks[#_restore_callbacks + 1] = fn
    return true
end

-- Assigned to the forward-declared local at the top of the Forge core section,
-- so the `_create_interfaces` hook can call it.
--
-- v0.7.33-alpha: verbose per-entry logging. Previous versions only logged the
-- aggregate "Restored N modded loadout entries" count, which made it
-- impossible to diagnose user reports like "my <X> didn't come back". Now
-- every saved entry is logged with career + slot + bid + result (restored /
-- missing-from-mirror / pcall-error). Counts are still echoed for chat
-- visibility; the per-entry detail lives in `mod:info` (log only).

-- v0.7.67-dev (issue #22): re-equip the LIVE keep avatar after the loadout data
-- write. set_loadout_item updates what the inventory/loadout RECORDS as equipped,
-- but the keep character unit spawned BEFORE the deferred restore ran, so it's
-- still holding the pre-restore (vanilla/default) weapons. Replicate vanilla's
-- HeroViewStateOverview equip path (hero_view_state_overview.lua:707-715): for
-- the CURRENT career's restored slots, recreate the equipment/attachment on the
-- spawned unit so the visible weapon matches the saved loadout. Only the local
-- current career has a live unit; other careers re-read from data when next
-- selected/spawned. NOT the issue-#12 risk (that was craft-time divergence; here
-- we make the live unit MATCH already-correct data).
--
-- Guards: network game ready, a living local player_unit (in the keep), the
-- right extension present. Fully pcall-guarded — a transition-timing failure
-- degrades to "data correct, visual updates on next career select", never a
-- crash. Per-(career/slot/bid) dedup via _reequipped avoids re-spawning the same
-- unit on every deferred restore pass (flicker).
local function _reequip_live_avatar()
    local net = Managers.state and Managers.state.network
    if not (net and net.game and net:game()) then return end
    local pl = Managers.player and Managers.player:local_player()
    local unit = pl and pl.player_unit
    if not (unit and Unit.alive(unit)) then return end
    local profile_index = pl:profile_index()
    local career_index = pl:career_index()
    local profile = SPProfiles and SPProfiles[profile_index]
    local career = profile and profile.careers and profile.careers[career_index]
    local career_name = career and career.name
    if not career_name then return end
    -- The live keep unit shows the player's SELECTED loadout index, so only
    -- re-equip the slots saved under that index. (Bot-designated indices have
    -- no live local unit — they re-read from data when next spawned.)
    local sel_index = _resolve_selected_index(career_name, 1)
    local indices = _modded_loadout[career_name]
    local slots = type(indices) == "table" and indices[sel_index]
    if not slots then return end

    local items = Managers.backend and Managers.backend:get_interface("items")
    if not items then return end
    local inv_ext = ScriptUnit.has_extension(unit, "inventory_system")
    local att_ext = ScriptUnit.has_extension(unit, "attachment_system")

    for slot_name, backend_id in pairs(slots) do
        local key = career_name .. "/" .. slot_name
        if _reequipped[key] ~= backend_id then
            local item = items:get_item_from_id(backend_id)
            local slot_type = item and item.data and item.data.slot_type
            local ok, err
            if (slot_type == "melee" or slot_type == "ranged")
               and inv_ext and inv_ext.create_equipment_in_slot then
                ok, err = pcall(inv_ext.create_equipment_in_slot, inv_ext, slot_name, backend_id)
            elseif (slot_type == "trinket" or slot_type == "ring" or slot_type == "necklace")
               and att_ext and att_ext.create_attachment_in_slot then
                ok, err = pcall(att_ext.create_attachment_in_slot, att_ext, slot_name, backend_id)
            end
            if ok then
                _reequipped[key] = backend_id
                mod._cim_reequip_ok = (mod._cim_reequip_ok or 0) + 1
                mod:info("[reequip] live avatar %s -> %s (%s)", key, tostring(backend_id), tostring(slot_type))
            elseif err then
                -- Record for the reequip_live_api_ok regression check: if the
                -- vanilla create_equipment/attachment API signature ever drifts
                -- or we call it at the wrong time, this surfaces it from a log.
                mod._cim_reequip_last_err = tostring(err)
                mod:info("[reequip] FAILED %s (%s): %s", key, tostring(slot_type), tostring(err))
            end
        end
    end
end

-- Issue #562: equip the exact freshly-created backend id, not another item with
-- the same ItemMasterList key. The items interface accepts an explicit loadout
-- index and writes it through to set_character_data
-- (backend_interface_item_playfab.lua:635-667). The live keep avatar is a
-- separate surface: vanilla's inventory equip path writes the loadout and then
-- queues/recreates the equipment unit (hero_view_state_overview.lua:1070-1139).
-- Keep those two surfaces together here so craft-time auto-equip cannot regress
-- into issue #12's historical "new icon, old weapon unit" divergence.
local _AUTO_EQUIP_WEAPON_SLOTS = {
    slot_melee = "melee",
    slot_ranged = "ranged",
}

local function _auto_equip_slot_type(slot_name)
    return _AUTO_EQUIP_WEAPON_SLOTS[slot_name]
end

local function _auto_equip_crafted_weapon(career_name, slot_name, backend_id)
    if not mod:get("auto_equip_new_weapons") then return false, "disabled" end

    local expected_slot_type = _auto_equip_slot_type(slot_name)
    if not expected_slot_type then return false, "not a weapon slot" end
    if not career_name or not backend_id then return false, "missing craft identity" end

    local items = Managers.backend and Managers.backend:get_interface("items")
    if not items then return false, "items backend not ready" end

    local item = items:get_item_from_id(backend_id)
    local slot_type = item and item.data and item.data.slot_type
    if slot_type ~= expected_slot_type then
        return false, string.format("crafted slot mismatch (%s for %s)", tostring(slot_type), tostring(slot_name))
    end

    local loadout_index = _resolve_selected_index(career_name, 1)
    local ok_write, write_result = pcall(
        items.set_loadout_item,
        items,
        backend_id,
        career_name,
        slot_name,
        loadout_index
    )
    if not ok_write or write_result == false then
        return false, "loadout write failed: " .. tostring(write_result)
    end

    -- Recreate the current local career's weapon unit immediately. If the
    -- player unit is unavailable during a state transition, the indexed data
    -- write above remains authoritative and the next spawn reads the new bid.
    local live_equipped = false
    local pl = Managers.player and Managers.player:local_player()
    local unit = pl and pl.player_unit
    local profile_index = pl and pl:profile_index()
    local career_index = pl and pl:career_index()
    local profile = SPProfiles and profile_index and SPProfiles[profile_index]
    local current_career = profile and profile.careers and career_index
        and profile.careers[career_index] and profile.careers[career_index].name
    if current_career == career_name and unit and Unit.alive(unit) then
        local inv_ext = ScriptUnit.has_extension(unit, "inventory_system")
        if inv_ext and inv_ext.create_equipment_in_slot then
            local ok_live, live_err = pcall(
                inv_ext.create_equipment_in_slot,
                inv_ext,
                slot_name,
                backend_id
            )
            if ok_live then
                live_equipped = true
                _reequipped[career_name .. "/" .. slot_name] = backend_id
            else
                mod._cim_auto_equip_last_err = tostring(live_err)
                pcall(printf, "[cim:562] live auto-equip failed career=%s slot=%s bid=%s err=%s",
                    tostring(career_name), tostring(slot_name), tostring(backend_id), tostring(live_err))
            end
        end
    end

    local event = Managers.state and Managers.state.event
    if event and event.trigger then
        pcall(event.trigger, event, "event_set_loadout_items")
    end

    mod._cim_auto_equip_last = {
        backend_id = backend_id,
        career_name = career_name,
        slot_name = slot_name,
        loadout_index = loadout_index,
        live_equipped = live_equipped,
    }
    return true, live_equipped and "live" or "loadout"
end

mod._cim_auto_equip_crafted_weapon = _auto_equip_crafted_weapon
mod._cim_auto_equip_slot_type = _auto_equip_slot_type

_restore_modded_loadout = function()
    -- v0.8.15-dev MASTER gate: when loadout persistence is OFF (default), cim
    -- does NOT touch loadouts at all — no flat->indexed migration, no stale
    -- purge, no set_loadout_item writes, no live-avatar re-equip. The whole
    -- restore (and the migration it drives via _run_loadout_migration) is a
    -- no-op, leaving vanilla player AND bot loadouts exactly as the base game
    -- writes them.
    if not _persist_loadouts_enabled() then
        mod:info("[restore] skipped — loadout persistence removed from cim (moved to Tweaker: GUI)")
        return
    end
    _modded_loadout_load()
    -- v0.8.14-dev: run the flat->indexed migration HERE, at the first
    -- mirror-ready moment, so each migrated flat entry homes to the career's
    -- REAL live selected index (not the boot-time fallback of 1). One-shot +
    -- idempotent; re-attempts on a later deferred pass if the mirror still
    -- isn't up. MUST run before purge/restore below so those walk the indexed
    -- shape. (The v0.8.13-dev blocker: this used to run at script-eval where the
    -- mirror is absent, homing every entry to index 1 and breaking multi-loadout
    -- users whose selected index != 1.)
    _run_loadout_migration()
    -- Purge stale entries (bids no longer in _forged_weapons / cwv_*) before
    -- attempting restore. Idempotent — runs every restore pass; first session
    -- after v0.7.33-alpha may purge dozens of entries, subsequent sessions zero.
    _modded_loadout_purge_stale()
    local items = Managers.backend and Managers.backend:get_interface("items")
    if not items then
        mod:info("[restore] skipped — items backend interface not ready")
        return
    end

    -- v0.7.54-dev: dump full saved-loadout state at restore entry (gated on
    -- enable_debug_logging) so we see every (career, slot) that SHOULD be
    -- restored — not just the ones the loop iterates. Helps detect cases
    -- where `_modded_loadout` is missing entries the user expects.
    if mod._cim_autodump_restore_pass then
        pcall(mod._cim_autodump_restore_pass, "pre-restore", _modded_loadout)
    end

    -- Total entries seen vs restored vs skipped — diagnostic-only.
    local total, restored, missing, errored = 0, 0, 0, 0
    -- Guard the capture path off while we replay saved state (see _restoring).
    -- INVARIANT: _restoring MUST be reset to false before this function returns,
    -- or the equip-capture hook stays disabled for the whole session (no equips
    -- saved/restored). There are NO early returns between here and the reset at
    -- the bottom of the loop, and every call that can throw inside the bracket is
    -- pcall-guarded. Keep it that way: do not add an un-pcall'd throwing call here.
    _restoring = true
    -- Indexed schema: career -> index -> slot -> bid. Each saved item is
    -- restored to ITS OWN index by passing `loadout_index` as the 4th arg to
    -- set_loadout_item -> set_character_data(..., optional_loadout_index)
    -- (backend_interface_item_playfab.lua:665, playfab_mirror_base.lua:1928).
    -- This is the core bot fix: a bot's designated-index modded gear lands on
    -- that index instead of being stamped into the host's selected index.
    for career_name, indices in pairs(_modded_loadout) do
        if type(indices) == "table" then
            for loadout_index, slots in pairs(indices) do
                if type(slots) == "table" then
                    for slot_name, backend_id in pairs(slots) do
                        total = total + 1
                        -- pcall-guarded: a throw here (LA-clone drift, stale template-cache
                        -- hit from standard_forge's get_item_from_id hook, malformed mirror
                        -- entry) would otherwise propagate out and strand _restoring=true.
                        local ok_get, item = pcall(items.get_item_from_id, items, backend_id)
                        if not ok_get then item = nil end
                        if not item then
                            missing = missing + 1
                            mod:info("[restore] MISSING %s[%s]/%s -> %s (item not in mirror; will retry next state transition)",
                                tostring(career_name), tostring(loadout_index), tostring(slot_name), tostring(backend_id))
                        else
                            local item_key = item.key or item.ItemId or (item.data and item.data.key) or "<unknown>"
                            -- Pass the SAVED index as the 4th arg so the write targets
                            -- that index, not the live SELECTED one. Type-guard: only
                            -- pass a numeric index (a corrupt non-number key falls back
                            -- to vanilla's selected-index default rather than throwing).
                            local index_arg = (type(loadout_index) == "number") and loadout_index or nil
                            local ok, err = pcall(items.set_loadout_item, items, backend_id, career_name, slot_name, index_arg)
                            if ok then
                                restored = restored + 1
                                mod:info("[restore] OK %s[%s]/%s -> %s (%s)",
                                    tostring(career_name), tostring(loadout_index), tostring(slot_name), tostring(backend_id), tostring(item_key))
                            else
                                errored = errored + 1
                                mod:info("[restore] ERROR %s[%s]/%s -> %s: %s",
                                    tostring(career_name), tostring(loadout_index), tostring(slot_name), tostring(backend_id), tostring(err))
                            end
                            -- v0.7.54-dev: immediately read back via get_loadout_item_id
                            -- to PROVE the write reached the layer the inventory reads
                            -- from. If set_loadout_item returns ok but read-back returns
                            -- a different bid (or nil), the mirror silently rejected our
                            -- write OR a different persistence layer is the source of truth.
                            -- This is the proof issue #22 needs.
                            if mod._cim_autodump_restore_entry then
                                pcall(mod._cim_autodump_restore_entry,
                                    career_name, slot_name, backend_id, items, ok, err, index_arg)
                            end
                        end
                    end
                end
            end
        end
    end
    _restoring = false
    if total > 0 then
        mod:info("[restore] total=%d restored=%d missing=%d errored=%d",
            total, restored, missing, errored)
    end

    -- v0.7.67-dev (issue #22): after writing the loadout DATA, re-equip the live
    -- keep avatar for the current career so the visible weapon matches what we
    -- just restored (the unit spawned before this deferred pass). Pcall-guarded.
    pcall(_reequip_live_avatar)

    -- Fan out to sibling-mod restore callbacks (e.g. cosmetics_tweaker reapplies
    -- its persisted LA illusion / paint / offhand selections per (career, slot)
    -- now that the modded backend_ids are live in the mirror). Fires on EVERY
    -- restore pass — initial + 1.0s deferred + 3.0s deferred — so subscribers
    -- should make their re-apply idempotent. Wrapped in pcall so a broken
    -- callback can't take down cim's restore.
    if _restore_callbacks then
        for _, cb in ipairs(_restore_callbacks) do
            local ok, err = pcall(cb)
            if not ok then
                mod:info("[restore] sibling callback errored: %s", tostring(err))
            end
        end
    end

    -- Debug autodump: per-career summary of saved entries. No-op when
    -- debug_mode is OFF. Called after restore so the log reflects the
    -- post-restore state.
    if mod._cim_autodump_restore_done then
        pcall(mod._cim_autodump_restore_done, "post-restore")
    end
end

-- Capture each set_loadout_item call so we can track per-(career, slot) state.
--
-- Pre-v0.7.33-alpha bug (root cause of "didn't restore my equipped items"
-- user report 2026-05-23): this hook only saved entries when the new item was
-- modded — and NEVER cleared a slot when the user later equipped a non-cim
-- (vanilla / Save Weapon / Loadout Manager / etc.) item there. Stale modded
-- entries stayed in `_modded_loadout` indefinitely.
--
-- On next session boot, `_restore_modded_loadout` ran AFTER vanilla PlayFab
-- restored each slot — and faithfully re-equipped the stale modded item,
-- clobbering what the user had actually equipped at session-end.
--
-- Fix: ALWAYS clear the slot entry first. Then, only if the new item is
-- modded, re-save the entry. Vanilla equips clean up the cim record; modded
-- equips refresh it. Either way the saved state matches what's currently
-- equipped instead of frozen at first-modded-equip-ever.
-- Shared equip capture. Records the equipped item into _modded_loadout (clear
-- the slot first; re-save only if the new item is modded — so vanilla equips
-- clean up the cim record and modded equips refresh it). `from_live_equip` is
-- true for the BackendUtils menu path (vanilla already re-spawned the unit, so
-- sync the re-equip dedup map); false for bare interface writes.
--
-- Skipped entirely while restore replays saved state (_restoring): those writes
-- aren't new equips, must not mutate _modded_loadout mid-pairs()-iteration, and
-- must not pre-mark _reequipped (which would starve the live re-equip).
-- `loadout_index` is the index THIS equip wrote to. The 4-arg
-- BackendInterfaceItemPlayfab.set_loadout_item path carries it explicitly
-- (`optional_loadout_index`); the 3-arg BackendUtils menu path does NOT, so the
-- caller resolves the LIVE selected index off the mirror and passes it in. A nil
-- here falls back to the resolved selected index (matching vanilla's
-- get/set_character_data default) so the capture never lands index-less.
local function _capture_loadout_equip(career_name, slot_name, item_id, from_live_equip, loadout_index)
    -- v0.8.15-dev master gate: when loadout persistence is OFF (default), cim
    -- captures NOTHING — `_modded_loadout` is never read or written, so neither
    -- the BackendInterfaceItemPlayfab hook_safe nor the BackendUtils full hook
    -- perturbs the vanilla equip. The BackendUtils hook still calls func(...) so
    -- the underlying vanilla write is byte-identical; this just skips the record.
    if not _persist_loadouts_enabled() then return end
    if _restoring then return end
    if not item_id or not career_name or not slot_name then return end

    -- Resolve the index this write targets: explicit arg wins; otherwise the
    -- live selected index (vanilla's default target when no index is passed).
    if type(loadout_index) ~= "number" then
        loadout_index = _resolve_selected_index(career_name, 1)
    end

    if mod._cim_autodump_equip_event then
        local items_iface = Managers.backend and Managers.backend:get_interface("items")
        pcall(mod._cim_autodump_equip_event, career_name, slot_name, item_id, items_iface, from_live_equip, loadout_index)
    end

    -- Indexed schema: career -> index -> slot -> bid. Clear the (index, slot)
    -- first; re-save only if the new item is modded (vanilla equips clean up the
    -- cim record at THAT index, modded equips refresh it). Other indices for the
    -- same career/slot are untouched — that's the whole point of the fix.
    local career_tbl = _modded_loadout[career_name]
    local index_tbl = career_tbl and career_tbl[loadout_index]
    local was_stale = index_tbl and index_tbl[slot_name]
    if index_tbl then
        index_tbl[slot_name] = nil
    end

    local is_modded = mod._cim_is_modded_backend_id and mod._cim_is_modded_backend_id(item_id)
    if is_modded then
        _modded_loadout[career_name] = _modded_loadout[career_name] or {}
        _modded_loadout[career_name][loadout_index] = _modded_loadout[career_name][loadout_index] or {}
        _modded_loadout[career_name][loadout_index][slot_name] = item_id
    end

    if from_live_equip then
        -- The menu equip already recreated the unit; sync dedup so the next
        -- restore pass doesn't needlessly re-spawn this slot. The live keep unit
        -- only ever shows the selected index, and menu equips write the selected
        -- index, so the bare "career/slot" dedup key stays correct.
        _reequipped[career_name .. "/" .. slot_name] = item_id
    end

    if was_stale or is_modded then
        _modded_loadout_save()
    end
end

-- Direct interface writes (restore — guarded by _restoring — or any code calling
-- the items interface method directly). from_live_equip=false: a bare data write
-- doesn't re-spawn the unit. Capture the 4th arg `optional_loadout_index` so a
-- write to a NON-selected index (e.g. configuring a bot's designated loadout) is
-- recorded under that index, not the selected one.
mod:hook_safe("BackendInterfaceItemPlayfab", "set_loadout_item", function(self, item_id, career_name, slot_name, optional_loadout_index)
    _capture_loadout_equip(career_name, slot_name, item_id, false, optional_loadout_index)
end)

-- THE menu-equip capture (issue #22 root fix). With Loremaster's Armoury active,
-- HeroViewStateOverview._set_loadout_item → BackendUtils.set_loadout_item →
-- get_loadout_interface_by_slot(slot):set_loadout_item dispatches through an
-- LA-CLONED interface, so the BackendInterfaceItemPlayfab hook above NEVER fires
-- for the player's actual equips — _modded_loadout stayed frozen and nothing was
-- restored next session (confirmed from log 2026-05-30: user equipped every slot
-- on es_mercenary, zero equip_events captured). Hook the stable OUTER entry point
-- (BackendUtils — a plain table, so TABLE-form hook per the repo "Hooking" rule)
-- so we capture every menu equip BEFORE the LA dispatch. Installed deferred (once
-- backend interfaces exist, i.e. post-LA-bridge) from mod.update via
-- _install_backendutils_capture — same timing cosmetics_tweaker uses for its own
-- BackendUtils.set_loadout_item hook.
local _backendutils_capture_installed = false
local function _install_backendutils_capture()
    if _backendutils_capture_installed then return end
    local BU = rawget(_G, "BackendUtils")
    if not (BU and BU.set_loadout_item and Managers.backend and Managers.backend.get_interface) then return end
    local ok_iface = pcall(function() return Managers.backend:get_interface("items") end)
    if not ok_iface then return end
    _backendutils_capture_installed = true
    mod._cim_backendutils_capture_installed = true  -- for the regression check
    mod:hook(BU, "set_loadout_item", function(func, backend_id, career_name, slot_name)
        -- BackendUtils.set_loadout_item is 3-arg and always writes the SELECTED
        -- index, so pass nil for loadout_index — the capture helper resolves the
        -- live selected index off the mirror and stores the bid under it.
        _capture_loadout_equip(career_name, slot_name, backend_id, true, nil)
        return func(backend_id, career_name, slot_name)
    end)
    mod:info("[cim] BackendUtils.set_loadout_item capture installed (post-LA menu-equip capture)")
end

mod:command("cim_restore_loadout", "Manually re-equip the saved modded loadout (use if your modded weapons didn't come back after a restart)", function()
    if not _restore_modded_loadout then mod:echo("Restore helper not initialised yet."); return end
    _modded_loadout_load()
    local count = 0
    -- Indexed schema: career -> index -> slot -> bid.
    for career_name, indices in pairs(_modded_loadout) do
        if type(indices) == "table" then
            for _, slots in pairs(indices) do
                if type(slots) == "table" then
                    for _ in pairs(slots) do count = count + 1 end
                end
            end
        end
    end
    mod:echo(string.format("[cim] %d saved modded loadout entries; restoring...", count))
    _restore_modded_loadout()
    mod:echo("[cim] Done. If items are still missing, run /cim_dump_loadout to see what's saved.")
end)

-- Open the VANILLA standard crafting bench (salvage / craft / re-roll / upgrade
-- / apply-illusion). Works in the Keep always; in adventure missions when
-- 'Allow in mission' is ON. Material-clean (unlike the Athanor /forge_hotkey).
-- mod.open_standard_crafting is defined further down (Athanor section); the
-- command is registered at load and dispatches at runtime, so order is fine.
mod:command("cim_craft_standard", "Open the standard crafting bench (salvage / craft / re-roll properties + traits / upgrade rarity / apply illusion). Keep always; in mission with 'Allow in mission' ON. Adventure only.", function()
    if type(mod.open_standard_crafting) == "function" then
        mod.open_standard_crafting()
    else
        mod:echo("Standard crafting opener not initialised yet.")
    end
end)


mod:command("cim_dump_loadout", "Print the saved modded loadout table to chat", function()
    _modded_loadout_load()
    local items = Managers.backend and Managers.backend:get_interface("items")
    local total = 0
    -- Indexed schema: career -> index -> slot -> bid.
    for career_name, indices in pairs(_modded_loadout) do
        if type(indices) == "table" then
            for index, slots in pairs(indices) do
                if type(slots) == "table" then
                    for slot_name, bid in pairs(slots) do
                        local item = items and items:get_item_from_id(bid)
                        local in_mirror = item and "yes" or "MISSING"
                        mod:echo(string.format("  %s[%s] %s -> %s (in_mirror=%s)",
                            career_name, tostring(index), slot_name, tostring(bid), in_mirror))
                        total = total + 1
                    end
                end
            end
        end
    end
    mod:echo(string.format("[cim] %d entries saved (across %d careers)", total,
        (function() local c = 0; for _ in pairs(_modded_loadout) do c = c + 1 end; return c end)()))
end)


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
    is_active = function() return _custom_forge_active end,
    get_bg_colored = function() return _forge_bg_colored end,
    set_bg_colored = function(value) _forge_bg_colored = value and true or false end,
    get_managers = function() return Managers end,
    get_profiles = function() return SPProfiles end,
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

-- Maps amulet trait-slot index → adventure jewellery slot. The amulet layout
-- has 3 trait slots and 3 property layers; vanilla `WeaveCareerProgression`
-- (`weave_loadout_settings.lua:282-295`) orders them by accessory POOL:
--   slot 1 = offence_accessory (CHARM)
--   slot 2 = defence_accessory (NECKLACE)
--   slot 3 = utility_accessory (TRINKET)
-- The picker for slot N reads its `category` from that table and renders the
-- matching property/trait pool, so we MUST seed/apply against the same order
-- or the bubble grid shows charm options where the player sees necklace data.
--
-- VT2's career_settings names the charm slot `slot_ring` (legacy) and the
-- trinket slot `slot_trinket_1` (note the suffix). `slot_charm`/`slot_trinket`
-- return nil from `get_loadout_item_id`.
local _AMULET_SLOT_BY_INDEX = {
    [1] = "slot_ring",         -- offence_accessory → charm
    [2] = "slot_necklace",     -- defence_accessory → necklace
    [3] = "slot_trinket_1",    -- utility_accessory → trinket
}
local _AMULET_INDEX_BY_SLOT = {}
for idx, slot in pairs(_AMULET_SLOT_BY_INDEX) do _AMULET_INDEX_BY_SLOT[slot] = idx end
local _AMULET_LAYER_SIZE = 10  -- matches amulet_slot_layout's per-layer count

-- Per-slot dirty tracking for the amulet's CRAFT button. The auto-apply
-- mutates equipped items in-place on every bubble click (session-only for
-- vanilla), so the user's bubble edits are already applied by the time they
-- reach CRAFT — but for vanilla items those edits don't survive a restart.
-- CRAFT solves that by creating a new modded item per dirty slot. We mark a
-- slot dirty on any property/trait set/remove against the amulet (item_backend_id == nil).
-- (`_amulet_dirty` is forward-declared near the top of the Athanor section so
-- the on_exit hook can reset it; the table itself was created there.)

local function _mark_amulet_property_dirty(slot_index)
    local layer = math.ceil((slot_index or 0) / _AMULET_LAYER_SIZE)
    if layer >= 1 and layer <= 3 then _amulet_dirty[layer] = true end
end

local function _mark_amulet_trait_dirty(slot_index)
    if slot_index and slot_index >= 1 and slot_index <= 3 then
        _amulet_dirty[slot_index] = true
    end
end

-- ============================================================
-- Per-property bubble caps (stamina, movespeed, ...)
-- ============================================================
-- Most weave properties scale linearly: 5 bubbles maps to value 0.0..1.0,
-- engine reads value into a 5-tier variable_bonus / variable_multiplier_max
-- and gives a proportional effect. cim defaults to that.
--
-- A few adventure properties don't fit that mold:
--
--   `properties_stamina` has `variable_bonus = {1, 1, 1, 2, 2}` — three
--   tiers give +1, two tiers give +2. So 1, 2, or 3 filled bubbles ALL
--   map to "+1 stamina" (visible discontinuity the user reported); 4 or 5
--   bubbles to "+2". User-facing fix: cap stamina at 2 bubbles, each
--   bubble = one step (1 bubble = +1, 2 bubbles = +2).
--
--   `properties_movespeed` is a FLAT `multiplier = 1.05` — it doesn't
--   scale with the stored value at all, always +5% if applied. The cim
--   grid display read raw value-as-percent (so 4/5 bubbles showed "79%
--   movement speed") even though the actual buff was +5%. Cap at 1
--   bubble so there's no discrepancy.
--
-- Conversion math (`_value_for_bubbles`) for capped properties: place
-- each bubble's value at the midpoint of its target buff tier so the
-- resolver in buff_extension.lua:208-216 lands cleanly:
--   stamina 1/2 → value 0.4 → bonus_index = floor(0.4 / 0.2) + 1 = 3 → +1
--   stamina 2/2 → value 1.0 → bonus_index = #table = 5 → +2
--   movespeed 1/1 → value 1.0 → always +5% (no tier lookup)
-- Per-property bubble cap. Default `movespeed = 1` matches vanilla's single
-- +5% multiplier. The `movespeed_2pct_mode` VMF toggle uncaps to 5 (each
-- bubble = +2% multiplier, max +10%) so we read it dynamically.
-- Keyed by the BARE property name (`stamina` / `movespeed`). Issue #86 take 3:
-- the game's weave property-picker passes the `WeaveProperties.categories`
-- key form `weave_stamina` / `weave_movespeed` (NOT `weave_properties_stamina`)
-- to set_loadout_property / get_property_mastery_costs. Trace:
--   hero_window_weave_properties.lua:534 iterates WeaveProperties.categories[cat]
--     → keys are `weave_stamina` / `weave_movespeed` (weave_properties.lua:543+)
--   :550 stores entry.key = that
--   :2663 calls set_loadout_property(career, key, ...) with that exact form
--   backend_interface_weaves_playfab.lua:1031 receives it as `property_name`.
-- So every runtime caller passes the `weave_<bare>` form. `_strip_weave` strips
-- only `^weave_`, leaving the BARE `stamina` / `movespeed`. The prior fix keyed
-- the table `properties_stamina` / `properties_movespeed`, so `_bubble_cap`
-- MISSED for the real game key and fell back to the default 5 (stamina ate 5
-- slots; movespeed showed 79% — `|100*(1.05/5 - 1)|` with one bubble). The
-- previous regression test fooled itself by passing `weave_properties_stamina`,
-- whose strip-form `properties_stamina` happened to match the (then-misKEYED)
-- table — a key form the game never actually sends.
--
-- Robust fix: normalize ANY caller key form to the bare name and key the table
-- by bare names. `_bare_property` strips `^weave_` THEN `^properties_`, so it
-- collapses `weave_properties_X`, `weave_X`, `properties_X`, and bare `X` all to
-- `X`. `_bubble_cap`, `_value_for_bubbles`, and `_bubbles_for_value` then resolve
-- correctly regardless of which form reaches them.
local _PROPERTY_BUBBLE_CAP_STATIC = {
    stamina   = 2,
    movespeed = 1,
}

_strip_weave = function(weave_key)
    return (weave_key or ""):gsub("^weave_", "")
end

-- Collapse any property key form to its bare name (strip `weave_` then
-- `properties_`). Handles weave_properties_X / weave_X / properties_X / X.
local function _bare_property(weave_key)
    local k = _strip_weave(weave_key)
    return (k:gsub("^properties_", ""))
end

_bubble_cap = function(weave_key)
    local bare = _bare_property(weave_key)
    if bare == "movespeed" and mod:get("movespeed_2pct_mode") then return 5 end
    -- Default 5: each generic property has a 5-bubble row you fill to scale its
    -- value (1 bubble = 20%, 5 = full — see `_value_for_bubbles`), exactly like
    -- vanilla weaves. v0.8.32-dev briefly forced this to 1, which let each
    -- property take only a SINGLE bubble and destroyed per-property scaling for
    -- every property at once (#86 over-correction, reverted v0.8.33-dev). The
    -- real #86 fix is the distinct-property ceiling (MAX_DISTINCT_PROPERTIES /
    -- the load-time trimmer / KEEP_LIMIT, all raised 2 → 10), NOT the bubble cap.
    -- stamina (2) / movespeed (1) keep their explicit caps; the 10-slot grid is a
    -- shared budget, so 10 distinct properties only fit if you don't max-fill them.
    return _PROPERTY_BUBBLE_CAP_STATIC[bare] or 5
end

-- value 0..1 that the engine should resolve for `count` filled bubbles.
-- Default linear maps count/5 for backward compatibility with the existing
-- 5-bubble properties.
_value_for_bubbles = function(weave_key, count)
    local bare = _bare_property(weave_key)
    -- Movespeed 2pct mode: 5 bubbles, each adds 0.2 to the stored value.
    -- buff_extension lerps multiplier as 1 + (max-1)*value. If we also bump
    -- `variable_multiplier_max` from 1.05 → 1.10 (in the load-time patch
    -- below), then 1 bubble (value 0.2) → 1 + 0.10*0.2 = 1.02 = +2%, and
    -- 5 bubbles (value 1.0) → 1 + 0.10*1.0 = 1.10 = +10%.
    if bare == "movespeed" and mod:get("movespeed_2pct_mode") then
        return math.min(count / 5, 1.0)
    end
    local cap = _bubble_cap(weave_key)
    if cap == 5 then
        -- #244: the picker shows an ABSOLUTE fraction of the Weave maximum,
        -- but an Adventure item stores a NORMALIZED interpolation parameter.
        -- Attack speed 3/5 means 3%; storing 0.6 made the ordinary item path
        -- interpolate 60% across 3..5 and display/apply 4.2%.
        local policy = mod._cim244_property_value_policy
        local WP, Weave = rawget(_G, "WeaponProperties"), rawget(_G, "WeaveProperties")
        local adv = WP and WP.properties and WP.properties[bare]
        local weave = Weave and Weave.properties and Weave.properties["weave_" .. bare]
        local adv_value = adv and adv.description_values and adv.description_values[1]
        local weave_value = weave and weave.description_values and weave.description_values[1]
        local converted = policy and policy.storage_for_bubbles(
            adv_value and adv_value.value, weave_value and weave_value.value, count, cap)
        if converted ~= nil then return converted end
        return math.min(count / 5, 1.0)
    end
    if count <= 0 then return 0 end
    if count >= cap then return 1.0 end
    -- For stamina cap=2 and count=1: lands at 0.4 (vanilla tier 2 = +1).
    return (count * 2 - 1) / (cap * 2)
end

-- Bubble count to fill for an item that has property value `value`. Inverse
-- of the apply step — used during seeding. For stamina we use the engine's
-- own tier-breakpoint (>= 0.6 ⇒ +2) so the visible bubble count matches the
-- visible +N stamina readout.
_bubbles_for_value = function(weave_key, value)
    local cap = _bubble_cap(weave_key)
    if value == nil then return 0 end
    if cap == 5 then
        -- Symmetric #244 read path. Normalized zero is the range's valid low
        -- endpoint (3% attack speed), so it must seed three bubbles instead of
        -- making the property disappear on the next Athanor open.
        local bare = _bare_property(weave_key)
        local policy = mod._cim244_property_value_policy
        local WP, Weave = rawget(_G, "WeaponProperties"), rawget(_G, "WeaveProperties")
        local adv = WP and WP.properties and WP.properties[bare]
        local weave = Weave and Weave.properties and Weave.properties["weave_" .. bare]
        local adv_value = adv and adv.description_values and adv.description_values[1]
        local weave_value = weave and weave.description_values and weave.description_values[1]
        local converted = policy and policy.bubbles_for_storage(
            adv_value and adv_value.value, weave_value and weave_value.value, value, cap)
        if converted ~= nil then return converted end
        if value <= 0 then return 0 end
        return math.max(1, math.ceil(value * 5))
    end
    if value <= 0 then return 0 end
    if cap == 1 then return 1 end
    if cap == 2 then
        return value >= 0.6 and 2 or 1
    end
    -- Generic: scale value over cap, floor to integer, clamp.
    return math.max(1, math.min(cap, math.ceil(value * cap)))
end

-- Persist a clicked slot_index into the property picker's slot-index array,
-- applying the two vanilla guards (cross-property collision + per-property use
-- cap). Pure: mutates `props` only, no UI/backend side effects, so the
-- /cim_regression_test can drive it with synthetic tables and assert the
-- PERSISTED array length (the real grid-occupancy driver) — not just the
-- display value the prior #86 fixes wrongly trusted. Returns the array for the
-- property after the attempted store. Shared by the live `set_loadout_property`
-- hook so the test exercises the exact production path.
--
-- `props`        : the live `data.properties` table (weave_key -> {slot_index,...})
-- `property_key` : the game's key form (`weave_movespeed` / `weave_stamina` / ...)
-- `slot_index`   : the grid slot the game's _find_next_available_slot picked
local _cim959_store_diag_seen, _cim959_store_diag_count = {}, 0

_store_property_slot = function(props, property_key, slot_index, layer_size)
    local cap = _bubble_cap and _bubble_cap(property_key) or 5
    local policy = mod._cim959_accessory_property_policy
    if not policy or type(policy.store_property_slot) ~= "function" then
        error("#959 accessory property store policy missing")
    end

    local arr, stored, reason, used_in_scope = policy.store_property_slot(
        props, property_key, slot_index, cap, layer_size)

    -- Bounded log-only apply evidence: once per property/layer/outcome.
    if layer_size and _cim959_store_diag_count < 24 then
        local layer = math.ceil(slot_index / layer_size)
        local token = table.concat({
            tostring(property_key), tostring(layer), tostring(reason),
        }, "|")
        if not _cim959_store_diag_seen[token] then
            _cim959_store_diag_seen[token] = true
            _cim959_store_diag_count = _cim959_store_diag_count + 1
            printf("[cim:959] property store key=%s layer=%d slot=%d result=%s layer_uses=%d",
                tostring(property_key), layer, slot_index, tostring(reason),
                tonumber(used_in_scope) or 0)
        end
    end

    return arr, stored, reason, used_in_scope
end

-- v0.8.30-dev (#86, READ-CHOKEPOINT guard — the fix the prior four #86 attempts
-- never tried): grid occupancy is built by vanilla
-- HeroWindowWeaveProperties._sync_backend_loadout
-- (hero_window_weave_properties.lua:1478 reads get_loadout_properties(...),
-- :1551-1556 maps ONE grid slot per slot-index array entry). Every prior #86 fix
-- capped only the WRITE path (`_store_property_slot`). The write-path cap is
-- provably correct in source (see /cim_regression_test `picker_caps_persisted_slot_array`),
-- yet the user STILL sees stamina+movespeed eat 5 slots each — which can only mean
-- the array reaching the grid is over-filled by a path the write cap doesn't cover
-- (a deployed build predating the cap, a bypassed hook instance, or a stale seed).
-- This trims each property's array to its bubble cap at the EXACT point the grid
-- reads it, so occupancy can never exceed the cap regardless of how it got filled.
--
-- Layer-aware: the single-weapon editor (item_backend_id present) is one layer, so
-- cap the whole array. The amulet editor (item_backend_id == nil) lets one property
-- legitimately appear once per accessory layer (size `_AMULET_LAYER_SIZE`), so cap
-- PER LAYER — a blanket trim there would wrongly drop a property the user put on a
-- second accessory.
--
-- Self-reporting: when it actually has to trim (i.e. the over-fill leak is present)
-- it logs via engine `printf` BEFORE trimming. `printf` writes to the engine console
-- even with VMF mod-logging OFF (the user's normal config — which is why every prior
-- `mod:info`/autodump "verification" saw nothing). So if the symptom persists, the
-- console will carry the raw over-fill count and prove which path leaked, instead of
-- us guessing. Idempotent: once trimmed, the cached array stays capped, so it logs at
-- most once per leaking property, not every sync.
_cap_grid_property_arrays = function(props, item_backend_id)
    if type(props) ~= "table" then return props end
    for property_key, arr in pairs(props) do
        if type(arr) == "table" then
            local cap = _bubble_cap and _bubble_cap(property_key) or 5
            if item_backend_id then
                -- Single weapon: one layer. Keep the first `cap` entries.
                local n = #arr
                if n > cap then
                    printf("[cim #86] grid over-occupancy: key=%s slots=%d > cap=%d (weapon) — trimming to %d",
                        tostring(property_key), n, cap, cap)
                    for i = n, cap + 1, -1 do arr[i] = nil end
                end
            else
                -- Amulet: cap per accessory layer, preserve click order.
                local per_layer, kept, trimmed = {}, {}, false
                for _, idx in ipairs(arr) do
                    local layer = math.ceil(idx / _AMULET_LAYER_SIZE)
                    local c = per_layer[layer] or 0
                    if c < cap then
                        per_layer[layer] = c + 1
                        kept[#kept + 1] = idx
                    else
                        trimmed = true
                    end
                end
                if trimmed then
                    printf("[cim #86] grid over-occupancy: key=%s slots=%d > cap=%d/layer (amulet) — trimming to %d",
                        tostring(property_key), #arr, cap, #kept)
                    for i = #arr, 1, -1 do arr[i] = nil end
                    for i = 1, #kept do arr[i] = kept[i] end
                end
            end
        end
    end
    return props
end

-- ============================================================
-- Movespeed buff scaling — 2pct toggle apply path patch
-- ============================================================
-- Vanilla's `apply_buff_tweak_data` (buff_utils.lua:13-21) runs at engine
-- load and merges `buff_tweak_data.properties_movespeed = { multiplier = 1.05 }`
-- into `WeaponProperties.buff_templates.properties_movespeed.buffs[1]`. That
-- static multiplier short-circuits the variable-value lerp in
-- buff_extension.lua:200-237 — vanilla movespeed is binary, applied = +5%,
-- not applied = no buff.
--
-- For the `movespeed_2pct_mode` toggle to actually scale per-bubble (1 bubble
-- = +2%, 5 bubbles = +10%) we need the lerp path to fire. The lerp uses
-- `variable_multiplier_table = { min, max }` and computes
-- `multiplier = math.lerp(min, max, variable_value)`. So setting
-- `variable_multiplier = { 1.0, 1.10 }` with stored values 0.2 / 0.4 / 0.6
-- / 0.8 / 1.0 yields multipliers 1.02 / 1.04 / 1.06 / 1.08 / 1.10 — exactly
-- the +2% / +4% / +6% / +8% / +10% the user wants.
--
-- When toggle is OFF, restore the vanilla static `multiplier = 1.05` so the
-- buff still applies at +5% for the default 1-bubble case.
--
-- Called: once on mod load, once on every VMF setting change.
local function _patch_movespeed_buff()
    local WP = rawget(_G, "WeaponProperties")
    local tpl = WP and WP.buff_templates and WP.buff_templates.properties_movespeed
    local sub = tpl and tpl.buffs and tpl.buffs[1]
    if not sub then return end
    if mod:get("movespeed_2pct_mode") then
        sub.multiplier = nil
        sub.variable_multiplier = { 1.0, 1.10 }
    else
        sub.multiplier = 1.05
        sub.variable_multiplier = nil
    end
end

-- Apply once at mod load (the buff template is already populated by vanilla
-- at engine boot, so this just rewrites the multiplier shape).
_patch_movespeed_buff()

local _settings_runtime = mod:dofile("scripts/mods/crafting_in_modded_dev/_cim_settings_runtime")
_settings_runtime.install(mod, _patch_movespeed_buff, printf)

local function _seed_one_item(item, props_out, traits_out, slot_index)
    if not item then return end
    local layer_offset = (slot_index - 1) * _AMULET_LAYER_SIZE
    if item.properties then
        local wp = rawget(_G, "WeaveProperties")
        local wp_props = wp and wp.properties
        local policy = mod._cim959_accessory_property_policy
        local next_slot = layer_offset + 1
        for prop_key, value in pairs(item.properties) do
            local weave_key = "weave_" .. prop_key
            if wp_props and wp_props[weave_key] then
                -- #959: APPEND into the shared amulet aggregate (assignment
                -- here overwrote sibling-accessory indices for the same key on
                -- every reopen), clamped to this accessory's ten-slot layer.
                next_slot = policy.seed_property_indices(
                    props_out, weave_key, next_slot, _bubbles_for_value(weave_key, value),
                    layer_offset, _AMULET_LAYER_SIZE, printf)
            else
                mod:info("Forge seed: no weave mapping for prop '%s' (tried '%s')", prop_key, weave_key)
            end
        end
    end
    if item.traits and item.traits[1] then
        local wt = rawget(_G, "WeaveTraits")
        local wt_traits = wt and wt.traits
        local trait_key = item.traits[1]
        local weave_key = "weave_" .. trait_key
        if wt_traits and wt_traits[weave_key] then
            traits_out[weave_key] = slot_index
        else
            mod:info("Forge seed: no weave mapping for trait '%s' (tried '%s')", trait_key, weave_key)
        end
    end
end

local function _forge_seed_item(career_name, item_backend_id)
    local key = (career_name or "") .. "|" .. (item_backend_id or "")
    if _forge_item_props[key] then return _forge_item_props[key] end

    local props = {}
    local traits = {}
    local items_backend = Managers.backend:get_interface("items")

    if item_backend_id then
        -- Single-item case: weapon (melee/ranged) editor.
        local item = items_backend and items_backend:get_item_from_id(item_backend_id)
        if item then _seed_one_item(item, props, traits, 1) end
    elseif items_backend and career_name then
        -- Amulet case: aggregate the three equipped accessories into one
        -- bubble grid (charm=layer 1, necklace=layer 2, trinket=layer 3).
        for slot_index, slot_name in ipairs(_AMULET_SLOT_BY_INDEX) do
            local bid = items_backend:get_loadout_item_id(career_name, slot_name)
            local item = bid and items_backend:get_item_from_id(bid)
            _seed_one_item(item, props, traits, slot_index)
        end
        -- #959 evidence: bounded per-key layer census per Athanor open.
        mod._cim959_accessory_property_policy.log_seed_census(
            props, _AMULET_LAYER_SIZE, printf)
    end

    _forge_item_props[key] = {properties = props, traits = traits}
    return _forge_item_props[key]
end

-- Amulet apply: bubble-grid edits live under the (career, nil) key. Each
-- property's slot indices span 1..30 — layer N (size 10) = accessory N.
-- Group per-layer fills, convert back to fractional values, write to each
-- accessory's `item.properties` / `item.traits` (and persist if modded).
local function _forge_apply_to_amulet(career_name)
    local key = (career_name or "") .. "|"
    local data = _forge_item_props[key]
    if not data then return end

    local items_backend = Managers.backend:get_interface("items")
    if not items_backend then return end

    -- Group property fills by layer (= accessory slot 1/2/3). Per-property
    -- caps via `_value_for_bubbles` handle stamina/movespeed tier-snapping;
    -- everything else stays on the linear count/5 mapping.
    local per_slot_props = { {}, {}, {} }
    for weave_key, slot_indices in pairs(data.properties or {}) do
        local prop_key = _strip_weave(weave_key)
        local layer_counts = { 0, 0, 0 }
        for _, idx in ipairs(slot_indices) do
            local layer = math.ceil(idx / _AMULET_LAYER_SIZE)
            if layer >= 1 and layer <= 3 then
                layer_counts[layer] = layer_counts[layer] + 1
            end
        end
        for layer, count in ipairs(layer_counts) do
            if count > 0 then
                per_slot_props[layer][prop_key] = _value_for_bubbles(weave_key, count)
            end
        end
    end

    -- Map traits by slot index → accessory
    local per_slot_trait = {}
    for weave_key, slot_index in pairs(data.traits or {}) do
        if slot_index >= 1 and slot_index <= 3 then
            per_slot_trait[slot_index] = weave_key:gsub("^weave_", "")
        end
    end

    -- Apply to each accessory
    for slot_index, slot_name in ipairs(_AMULET_SLOT_BY_INDEX) do
        local bid = items_backend:get_loadout_item_id(career_name, slot_name)
        local item = bid and items_backend:get_item_from_id(bid)
        if item then
            local new_props = per_slot_props[slot_index] or {}
            local new_traits = per_slot_trait[slot_index] and { per_slot_trait[slot_index] } or {}
            item.properties = new_props
            item.traits = new_traits

            local cjson_mod = rawget(_G, "cjson")
            if cjson_mod and item.CustomData then
                item.CustomData.properties = cjson_mod.encode(new_props)
                item.CustomData.traits = cjson_mod.encode(new_traits)
            end

            local saved = _forged_weapons[bid]
            if saved then
                saved.properties = new_props
                saved.traits = new_traits
                saved.trait = new_traits[1]
                saved.external_traits = {}
                _forge_save()
            end
        end
    end
end

local function _forge_apply_to_item(career_name, item_backend_id)
    if not item_backend_id then
        _forge_apply_to_amulet(career_name)
        return
    end
    local items_backend = Managers.backend:get_interface("items")
    local item = items_backend and items_backend:get_item_from_id(item_backend_id)
    if not item then return end

    local data = _forge_seed_item(career_name, item_backend_id)

    local new_props = {}
    for weave_key, slots in pairs(data.properties) do
        local prop_key = _strip_weave(weave_key)
        new_props[prop_key] = _value_for_bubbles(weave_key, #slots)
    end
    item.properties = new_props

    local new_traits = {}
    for weave_key, _ in pairs(data.traits) do
        local trait_key = weave_key:gsub("^weave_", "")
        new_traits[#new_traits + 1] = trait_key
    end
    item.traits = new_traits

    local cjson_mod = rawget(_G, "cjson")
    if cjson_mod and item.CustomData then
        item.CustomData.properties = cjson_mod.encode(new_props)
        item.CustomData.traits = cjson_mod.encode(new_traits)
    end

    -- Persist edits to bubble grid back into our forged_weapons save entry.
    local saved = _forged_weapons[item_backend_id]
    if saved then
        saved.properties = new_props
        saved.traits = new_traits
        saved.trait = new_traits[1]
        saved.external_traits = {}
        _forge_save()
    end
end

mod:hook("BackendInterfaceWeavesPlayFab", "get_loadout_properties", function(func, self, career_name, item_backend_id)
    if _custom_forge_active then
        local data = _forge_seed_item(career_name, item_backend_id)
        -- #86 read-path guard: trim each property array to its bubble cap at the
        -- exact point vanilla _sync_backend_loadout reads it to build grid
        -- occupancy. Catches any over-fill the write-path cap missed.
        _cap_grid_property_arrays(data.properties, item_backend_id)
        return data.properties
    end
    return func(self, career_name, item_backend_id)
end)

mod:hook("BackendInterfaceWeavesPlayFab", "get_loadout_traits", function(func, self, career_name, item_backend_id)
    if _custom_forge_active then
        local data = _forge_seed_item(career_name, item_backend_id)
        return data.traits
    end
    return func(self, career_name, item_backend_id)
end)

-- Adventure-talent helpers. The amulet UI's talent picker runs against the
-- weave talent system, but `WeaveLoadoutSettings[career].talent_tree` is
-- literally `TalentTrees[profile][index]` (see weave_loadout_settings_*.lua),
-- i.e. the same tree adventure mode uses. So we can map the player's
-- adventure picks (numeric column 1..3 per row) into the
-- `{[talent_name] = row}` shape the bubble grid expects.
local function _get_career_talent_tree(career_name)
    local cs = CareerSettings[career_name]
    if not cs then return nil end
    local TalentTrees = rawget(_G, "TalentTrees")
    if not TalentTrees then return nil end
    local tree = TalentTrees[cs.profile_name]
    return tree and tree[cs.talent_tree_index]
end

mod:hook("BackendInterfaceWeavesPlayFab", "get_loadout_talents", function(func, self, career_name)
    if not _custom_forge_active then return func(self, career_name) end
    local talents_iface = Managers.backend and Managers.backend:get_interface("talents")
    if not talents_iface then return {} end
    local picks = talents_iface:get_talents(career_name)
    if not picks then return {} end
    local tree = _get_career_talent_tree(career_name)
    if not tree then return {} end

    local result = {}
    for row, pick in ipairs(picks) do
        local row_talents = tree[row]
        if row_talents and pick and row_talents[pick] then
            result[row_talents[pick]] = row
        end
    end
    return result
end)

mod:hook("BackendInterfaceWeavesPlayFab", "get_mastery", function(func, self, career_name, item_backend_id)
    if _custom_forge_active then return 0, 0 end
    local ok, a, b = pcall(func, self, career_name, item_backend_id)
    if ok then return a, b end
    return 0, 0
end)

mod:hook("BackendInterfaceWeavesPlayFab", "set_loadout_property", function(func, self, career_name, property_key, slot_index, item_backend_id)
    if mod._cim_autodump_property_write then
        pcall(mod._cim_autodump_property_write, "set_property", career_name, property_key, slot_index, item_backend_id)
    end
    if _custom_forge_active then
        local data = _forge_seed_item(career_name, item_backend_id)
        local props = data.properties
        local accessory_policy = mod._cim959_accessory_property_policy
        local layer_size = item_backend_id == nil and _AMULET_LAYER_SIZE or nil
        -- Ten slots cap distinct keys globally for a weapon and per accessory
        -- layer for the amulet editor (user request 2026-06-29).
        --
        -- Why 2 was the old value: vanilla's HeroWindowItemCustomization
        -- Apply-Skin preview indexes `content["button_hotspot_" .. N]` per
        -- property (hero_window_item_customization.lua:1210-1213); the widget
        -- only ships hotspots 1 and 2, so a 3rd distinct key used to crash that
        -- view ("attempt to index a nil value"). That crash is now INDEPENDENTLY
        -- guarded by cim's replacement `_update_property_option` hook
        -- (standard_forge.lua:192-220), which skips writes for missing hotspot
        -- widgets. With that guard in place the >2 ceiling is no longer load-
        -- bearing — extra properties simply aren't surfaced in that one preview
        -- tab, but they still apply to the buff system and render in the weave
        -- grid. So we can safely open the gate to the full 10-slot grid.
        local MAX_DISTINCT_PROPERTIES = 10
        local property_present_in_scope = accessory_policy.property_present_in_scope(
            props[property_key], slot_index, layer_size)
        if not property_present_in_scope then
            local distinct_in_layer = accessory_policy.count_distinct_properties(
                props, slot_index, layer_size)
            if distinct_in_layer >= MAX_DISTINCT_PROPERTIES then
                -- Use mod:warning (not mod:echo) so the user always sees WHY
                -- their click was rejected. `mod:echo` is silenced unless
                -- `enable_debug_logging` is on; warnings always surface to chat.
                -- Without visible feedback this looks like "I clicked, nothing
                -- happened, mod's broken" — root cause of user report
                -- 2026-05-25 (issue #47).
                mod:warning(string.format(
                    "[cim] Max %d distinct properties per %s. Remove one to add %s.",
                    MAX_DISTINCT_PROPERTIES,
                    item_backend_id and "item" or "accessory",
                    _strip_weave(property_key)))
                return
            end
            if not props[property_key] then props[property_key] = {} end
        end
        -- v0.7.44-alpha: per-property bubble cap rejection REMOVED (issue #49).
        -- Previously: clicks beyond `_bubble_cap(property_key)` for stamina (2)
        -- and movespeed (1) were silently rejected by this hook. The vanilla
        -- bubble grid still showed all 10 slots as clickable, so users would
        -- click "free" slots that did nothing, see no fill, and conclude the
        -- mod was broken. User report 2026-05-25 framed it as stamina/movespeed
        -- "blocking" other properties — really the silent rejection masking a
        -- click that the UI invited.
        --
        -- The game-effect value is still clamped at 1.0 by `_value_for_bubbles`
        -- (lines ~2003) — for stamina cap=2, count>=2 returns 1.0 (= +2 tier);
        -- for movespeed cap=1, count>=1 returns 1.0 (= +5%). So extra clicks
        -- write redundantly to the same value but bubbles fill in the UI and
        -- the user gets the visual feedback they expect.
        --
        -- Known inconsistency: on session reload, `_bubbles_for_value` seeds
        -- only the engine-max bubble count (2 for stamina, 1 for movespeed)
        -- from the persisted value, so "I had 5 stamina bubbles filled" loads
        -- back as 2. The game-effect value (+2 stamina) is correct throughout;
        -- only the displayed bubble count compresses on reload. Documented in
        -- CHANGELOG; full fix would need to persist click-count separately.
        --
        -- The distinct-property cap above (MAX_DISTINCT_PROPERTIES = 2) stays
        -- — it's a vanilla-crash gate for HeroWindowItemCustomization's
        -- Apply-Skin preview (only ships widgets for `button_hotspot_1` / `_2`).
        --
        -- v0.7.55-dev (issue #49 take 2): cap the slot_index array length at
        -- `_bubble_cap(property_key)`. Without this, vanilla's property picker
        -- auto-writes all 5 slot_indices when stamina is selected (each
        -- bubble click → one set_loadout_property call). v0.7.44 removed the
        -- per-click REJECTION so the visual bubble grid renders correctly
        -- (2 filled for stamina because `_value_for_bubbles` clamps), BUT
        -- the underlying props.stamina array now holds 5 slot_indices, which
        -- the inventory render treats as "5 of 10 slots used by stamina" —
        -- blocking a second property from being added even though
        -- MAX_DISTINCT_PROPERTIES would otherwise allow it.
        -- Fix: silently cap the array at the engine bubble cap. Visible
        -- bubble count is unchanged (still 2 for stamina, 1 for movespeed);
        -- only the persisted array is trimmed so the second-property slot
        -- accounting frees up. User report 2026-05-27 EOD framed it as
        -- "WHEN APPLIED IT TAKES 5" — matches this fix.
        -- v0.8.28-dev (#86 take 4 — the persisted-ARRAY over-occupancy bug,
        -- TRACED not assumed): the GRID's slot accounting is driven by the
        -- VALUES in this array, not by the visible bubble count. Vanilla
        -- `_sync_backend_loadout` (hero_window_weave_properties.lua:1553-1556)
        -- does `for _, slot_index in ipairs(slot_indices) do
        -- properties_index_map[slot_index] = key end` — EACH entry in
        -- `props[property_key]` marks ONE grid slot occupied. So a property
        -- occupies exactly `#props[property_key]` grid slots; any entry beyond
        -- its real use-count steals a slot another property could fill.
        -- Movespeed (cap 1) must hold exactly ONE slot_index, stamina (cap 2)
        -- two — and the store now re-applies vanilla's two dropped guards
        -- (cross-property collision + per-property use cap) via the shared
        -- `_store_property_slot` helper. The autodump below logs the resulting
        -- array length so the divergence is visible in-log without trusting the
        -- display. NOTE: with `movespeed_2pct_mode` ON, `_bubble_cap` returns 5
        -- for movespeed by design — it then legitimately occupies up to 5 slots
        -- (each +2%). That CONFIG, not this code, is the only path where
        -- movespeed consumes more than one slot.
        local cap = _bubble_cap and _bubble_cap(property_key) or 5
        local arr = _store_property_slot(props, property_key, slot_index, layer_size)
        if mod._cim_autodump_property_array then
            pcall(mod._cim_autodump_property_array, "set_property", property_key, arr, cap, layer_size)
        end
        if not item_backend_id then _mark_amulet_property_dirty(slot_index) end
        _forge_apply_to_item(career_name, item_backend_id)
        return
    end
    return func(self, career_name, property_key, slot_index, item_backend_id)
end)

mod:hook("BackendInterfaceWeavesPlayFab", "remove_loadout_property", function(func, self, career_name, property_key, slot_index, item_backend_id)
    if mod._cim_autodump_property_write then
        pcall(mod._cim_autodump_property_write, "remove_property", career_name, property_key, slot_index, item_backend_id)
    end
    if _custom_forge_active then
        local data = _forge_seed_item(career_name, item_backend_id)
        local slots = data.properties[property_key]
        if slots then
            for i, s in ipairs(slots) do
                if s == slot_index then
                    table.remove(slots, i)
                    break
                end
            end
            if #slots == 0 then
                data.properties[property_key] = nil
            end
        end
        if not item_backend_id then _mark_amulet_property_dirty(slot_index) end
        _forge_apply_to_item(career_name, item_backend_id)
        return
    end
    return func(self, career_name, property_key, slot_index, item_backend_id)
end)

mod:hook("BackendInterfaceWeavesPlayFab", "set_loadout_trait", function(func, self, career_name, trait_key, slot_index, item_backend_id)
    if mod._cim_autodump_property_write then
        pcall(mod._cim_autodump_property_write, "set_trait", career_name, trait_key, slot_index, item_backend_id)
    end
    if _custom_forge_active then
        local data = _forge_seed_item(career_name, item_backend_id)
        data.traits[trait_key] = slot_index
        if not item_backend_id then _mark_amulet_trait_dirty(slot_index) end
        _forge_apply_to_item(career_name, item_backend_id)
        return
    end
    return func(self, career_name, trait_key, slot_index, item_backend_id)
end)

mod:hook("BackendInterfaceWeavesPlayFab", "remove_loadout_trait", function(func, self, career_name, trait_key, item_backend_id)
    if mod._cim_autodump_property_write then
        pcall(mod._cim_autodump_property_write, "remove_trait", career_name, trait_key, nil, item_backend_id)
    end
    if _custom_forge_active then
        local data = _forge_seed_item(career_name, item_backend_id)
        local removed_slot = data.traits[trait_key]
        data.traits[trait_key] = nil
        if not item_backend_id then _mark_amulet_trait_dirty(removed_slot) end
        _forge_apply_to_item(career_name, item_backend_id)
        return
    end
    return func(self, career_name, trait_key, item_backend_id)
end)

mod:hook("BackendInterfaceWeavesPlayFab", "set_loadout_talent", function(func, self, career_name, talent_key, slot_index)
    if not _custom_forge_active then return func(self, career_name, talent_key, slot_index) end
    local tree = _get_career_talent_tree(career_name)
    local row_talents = tree and tree[slot_index]
    if not row_talents then return end

    -- Find which column in row `slot_index` this talent_key is.
    local column
    for c, t_name in ipairs(row_talents) do
        if t_name == talent_key then column = c; break end
    end
    if not column then return end

    local talents_iface = Managers.backend and Managers.backend:get_interface("talents")
    if not talents_iface then return end

    local picks = talents_iface:get_talents(career_name)
    if not picks then picks = {} end
    -- Adventure expects 6 picks; default missing rows to column 1 to avoid
    -- nil entries when serialized.
    for i = 1, 6 do
        if not picks[i] then picks[i] = 1 end
    end
    picks[slot_index] = column
    talents_iface:set_talents(career_name, picks)
end)

mod:hook("BackendInterfaceWeavesPlayFab", "remove_loadout_talent", function(func, self, career_name, talent_key)
    if not _custom_forge_active then return func(self, career_name, talent_key) end
    -- No-op: the bubble grid emits remove → set on each pick swap. We commit
    -- the new pick in `set_loadout_talent` directly; vanilla expected pair
    -- semantics aren't needed because adventure rows always have one talent.
end)

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
        printf("[cim:617] icon key=%s original=%s replacement=%s",
            tostring(change.key), tostring(change.original), tostring(change.replacement))
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
    for bid, w in pairs(_forged_weapons) do
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

-- --- Craft button (repurposed upgrade_button) ---
-- The properties window's upgrade_button is the most natural anchor for a
-- "Craft New" action. Hijack `_upgrade_magic_level` so pressing it instead
-- creates a new modded item with the player's current bubble-grid edits and
-- equips it in place of the existing item.
--
-- Vanilla's `_set_essence_upgrade_cost` (hero_window_weave_properties.lua:1856)
-- runs each refresh and sets:
--   * `button_content.title_text` = "Fully Upgraded" when `essence_amount` is
--     nil (it always is in modded — our weaves hooks return 0 essence).
--   * `disable_button = true` when `script_data["eac-untrusted"]` is true
--     (it always is in modded realm).
-- Post-hook to overwrite both so the button reads "CRAFT" and is clickable.
mod:hook_safe("HeroWindowWeaveProperties", "_set_essence_upgrade_cost", function(self, essence_amount, can_afford, magic_cap_reached)
    if not _custom_forge_active then return end
    local widgets_by_name = self._widgets_by_name
    local btn = widgets_by_name and widgets_by_name.upgrade_button
    if not btn then return end

    -- Issue #71 (Option A, 2026-06-17): the weapon (melee/ranged) editor's
    -- CRAFT button was previously HIDDEN. Bubble-grid edits mutate the
    -- in-editor item in place (via `_forge_apply_to_item`), and a brand-new
    -- weapon was only mintable from the weapon-select pane — which crafts a
    -- BLANK weapon (empty properties/traits). Users who set properties in the
    -- editor and then expected a "craft" to produce a weapon WITH those
    -- properties got a blank one (the reporter backed out to the weapon-select
    -- pane and crafted there). Re-enable the button for weapons so
    -- "set properties -> CRAFT" mints a new weapon carrying the current edits
    -- (the `_upgrade_magic_level` hook below clones item.properties /
    -- item.traits into the new craft, exactly like the amulet path).
    local item = self:_selected_item()

    if btn.content then btn.content.visible = true end
    local label = item and "CRAFT" or "CRAFT MODDED ACCESSORIES"
    btn.content.title_text = label
    btn.content.button_hotspot.disable_button = false
    if btn.style and btn.style.price_icon then btn.style.price_icon.color[1] = 0 end
    if btn.style and btn.style.price_icon_disabled then btn.style.price_icon_disabled.color[1] = 0 end
    -- Also clear the "not enough essence" warning that vanilla shows when cap
    -- is reached — we don't use essence in modded.
    local warn = widgets_by_name.upgrade_essence_warning
    if warn and warn.content then warn.content.visible = false end
end)

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

mod:hook("HeroWindowWeaveProperties", "_upgrade_magic_level", function(func, self)
    if not _custom_forge_active then return func(self) end

    local item = self:_selected_item()
    local item_data = item and item.data
    local item_key = item_data and (item_data.key or item_data.name)

    -- Issue #71 (Option A): weapons (melee/ranged) now fall through to the
    -- mint-new path below. The editor's bubble-grid edits already mutated
    -- item.properties / item.traits in place (via _forge_apply_to_item), so
    -- cloning them into a fresh craft yields a new weapon carrying the current
    -- edits — matching the "set properties then craft" mental model. (The
    -- button was previously hidden for weapons and this branch early-returned.)

    -- Amulet case: no selected_item. Clone all three equipped accessories via
    -- the same shared single-slot helper used by the individual buttons. This
    -- branch still runs if the
    -- legacy `upgrade_button` somehow fires (e.g. gamepad activation while in
    -- amulet view) — the 3 cim per-slot buttons supersede it visually but the
    -- legacy path stays wired for compat.
    if not item then
        local crafted = _BULK_ACCESSORY_CRAFT.craft_all(function(slot_index, slot_name)
            return _cim_amulet_craft_one_slot(self, slot_index, slot_name)
        end)
        if crafted == 0 then
            mod:echo("[cim] No equipped accessories could be crafted")
        end
        return
    end

    if not item_key then
        mod:echo("[cim] Craft: no selected item")
        return
    end

    -- The bubble-grid `_forge_apply_to_item` already mutated `item.properties`
    -- and `item.traits` in-place on each click, so the "current bubble state"
    -- IS the item's current properties/traits. Clone them into the new craft.
    local new_props = {}
    if item.properties then
        for k, v in pairs(item.properties) do new_props[k] = v end
    end
    local new_traits = {}
    if item.traits then
        for i, t in ipairs(item.traits) do new_traits[i] = t end
    end

    local new_backend_id = Application.guid()
    local weapon_data = {
        item_key = item_key,
        properties = new_props,
        traits = new_traits,
        -- Honor the base_power_level setting (was hardcoded 300 — weapons ignored
        -- the slider while the amulet path already read _cim_base_power). 2026-06-30.
        power_level = (mod._cim_base_power and mod._cim_base_power()) or 300,
        rarity = "modded",
        via_mirror = true,
    }

    local injected, err = _athanor_inject_item(weapon_data, new_backend_id)
    if not injected then
        mod:warning("[cim] Craft failed: " .. tostring(err))
        return
    end

    local registered, register_err = mod._cim_register_craft(new_backend_id, weapon_data)
    if not registered then
        Managers.backend:get_backend_mirror():remove_item(new_backend_id)
        mod:warning("[cim] Craft persistence rejected: " .. tostring(register_err))
        return
    end

    -- Craft only — see issue #12. Player equips from inventory.
    local slot_name = self._params and self._params.selected_slot_name
    local display = item_key
    local master = rawget(ItemMasterList, item_key)
    if master and master.display_name then
        local lok, loc = pcall(Localize, master.display_name)
        if lok and loc then display = loc end
    end
    mod:echo("[cim] Crafted new " .. tostring(slot_name and slot_name:gsub("^slot_", "") or "item")
             .. ": " .. display .. " [promo] — equip from inventory")
    -- v0.8.7-dev: audio feedback for the editor CRAFT button (the repurposed
    -- upgrade_button). Our hook crafts + returns without the vanilla completion
    -- sound, so this craft path was silent. _play_sound delegates to
    -- _parent:play_sound (hero_window_weave_properties.lua:2838).
    if self._play_sound then pcall(self._play_sound, self, "play_gui_craft_forge_button_completed") end
end)

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
    get_forged_weapons = function() return _forged_weapons end,
    get_modded_loadout = function() return _modded_loadout end,
    get_more_items_lib = function() return _more_items_lib end,
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
    get_forged_weapons = function() return _forged_weapons end,
    set_forged_weapons = function(value) _forged_weapons = value end,
    get_modded_loadout = function() return _modded_loadout end,
    set_modded_loadout = function(value) _modded_loadout = value end,
    modded_loadout_load = _modded_loadout_load,
    rpc_schema = CIM_RPC_SCHEMA,
})

mod:info("[mem-probe] cim_dev boot_lua=+%.1f MB (of ~1024 MB lua_heap cap)", (collectgarbage("count") - _MEM_PROBE_T0_CIMD) / 1024)
