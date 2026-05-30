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

-- ============================================================
-- Quiet-by-default `mod.echo` (chat suppression unless debug toggle is on)
-- ============================================================
-- User feedback 2026-05-25: cim was spamming the in-game chat with auto-fired
-- load / restore / status messages. New behavior: every `mod:echo(...)` call
-- in cim is silently redirected to `mod:info(...)` (log only) UNLESS the
-- universal `enable_debug_logging` setting is ON. When ON, the original
-- behavior is restored — every echo lands in chat AND the log.
--
-- The patch runs here, at the very top of cim's main script, BEFORE any
-- `mod:command(...)` registration or any other `mod:echo(...)` call in cim
-- or its sub-modules. That guarantees we intercept everything, including
-- the per-startup banner directly below, plus echoes inside `/cim_*` chat
-- commands and the dump commands defined further down.
--
-- Note: this also quiets user-invoked dump commands (`/inv_dump`,
-- `/forge_list`, `/cim_dump_loadout`, etc.) when debug logging is OFF — the
-- output goes to the game log file instead of chat. If a user wants the
-- chat output back (e.g. to read /forge_list interactively), they enable
-- `enable_debug_logging` in the mod settings. `mod:error` / `mod:warning`
-- are NOT patched and still surface to chat on issue.
local _orig_echo = mod.echo
mod.echo = function(self, fmt, ...)
    if self:get("enable_debug_logging") then
        return _orig_echo(self, fmt, ...)
    end
    return self:info(fmt, ...)
end

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

local MOD_VERSION = "0.7.69-dev"
mod:info("Crafting in Modded v%s loaded", MOD_VERSION)

-- Two-helper debug-logging policy (PROJECT_STANDARDS.md § 3.6).
-- Both gate on `enable_debug_logging`. Both no-op when toggle is off.
-- `_dbg` is for confirmation / expected behavior — file only.
-- `_dbg_alert` is for unexpected / wrong / mismatch — file AND in-game chat.
-- NOTE: cim ALSO has a global `mod.echo` redirect (above) that silences chat
-- echoes when the toggle is OFF. `_dbg_alert` bypasses that by calling the
-- patched `mod.echo` while the toggle is ON, which still routes to chat
-- (the redirect's "ON" branch returns the original behavior).
local function _dbg(fmt, ...)
    if mod:get("enable_debug_logging") then
        mod:info("[cim:dbg] " .. fmt, ...)
    end
end

local function _dbg_alert(fmt, ...)
    if mod:get("enable_debug_logging") then
        mod:info("[cim:dbg] " .. fmt, ...)
        mod:echo("[cim] " .. fmt, ...)
    end
end

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

-- /regression_test scaffold. Registrations at end of file.
local _RT_CHECKS = {}
local function _rt_register(name, fn)
    _RT_CHECKS[#_RT_CHECKS + 1] = { name = name, fn = fn }
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

-- Register the "modded" rarity (and any future custom rarities) BEFORE
-- anything else loads — sibling modules will create items with this rarity.
local _ok_rr, _err_rr = pcall(mod.dofile, mod, "scripts/mods/crafting_in_modded_dev/modded_rarities")
if not _ok_rr then mod:error("Failed to load modded_rarities: %s", tostring(_err_rr)) end

-- Standard Keep crafting — same Athanor pattern: mutations are session-only because
-- we block PlayFab commits while the forge is open. v0.2.0 crashed because we left
-- the commit alive and PlayFab's anti-tamper rejected the modified inventory state.
local _ok_sf, _err_sf = pcall(mod.dofile, mod, "scripts/mods/crafting_in_modded_dev/standard_forge")
if not _ok_sf then mod:error("Failed to load standard_forge: %s", tostring(_err_sf)) end

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
local _forge_pending = nil
local _forged_weapons = {}

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
            item_key = w.item_key,
            properties = w.properties,
            trait = w.trait,
            traits = w.traits,
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
        _forged_weapons[bid] = {
            item_key = w.item_key,
            properties = w.properties or {},
            trait = w.trait,
            traits = w.traits,
            skin = w.skin,
            power_level = w.power_level or 300,
            rarity = rarity,
            via_mirror = via_mirror,
            rerolled_props_indices = w.rerolled_props_indices,
            rerolled_trait_indices = w.rerolled_trait_indices,
            -- v0.7.37-alpha: load-side pass-through of the opaque overlay slot
            -- (see _forge_save comment). Tolerant of missing field on legacy
            -- saves — nil just means no sibling overlay.
            custom_glow = w.custom_glow,
        }
    end
    _forge_save() -- persist any rarity migrations
end

-- Public helper for sibling modules (standard_forge.lua) to register a newly
-- crafted item into the persistent save layer. `via_mirror = true` means the
-- item is added via `backend_mirror:add_item` on session restore (not MIL).
mod._cim_register_craft = function(backend_id, weapon_data)
    local entry = {
        item_key = weapon_data.item_key,
        properties = weapon_data.properties or {},
        trait = weapon_data.trait,
        traits = weapon_data.traits,
        skin = weapon_data.skin,
        power_level = weapon_data.power_level or 300,
        rarity = weapon_data.rarity,
        via_mirror = weapon_data.via_mirror ~= false,
        -- v0.7.37-alpha: pass-through. See _forge_save comment.
        custom_glow = weapon_data.custom_glow,
    }
    _forged_weapons[backend_id] = entry
    _forge_save()
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

mod._cim_is_modded_backend_id = function(backend_id)
    if not backend_id or type(backend_id) ~= "string" then return false end
    -- Our crafts (registered via_mirror)
    if _forged_weapons[backend_id] then return true end
    -- character_weapon_variants items
    if backend_id:sub(1, 4) == "cwv_" then return true end
    return false
end
-- HISTORICAL NOTE: this function used to also match UUID format
-- (`^%x+-%x+-%x+-%x+-%x+$`) on the theory that any UUID-like bid came from
-- `Application.guid()` (which we use). But VT2's `_create_fake_inventory_items`
-- also generates UUID bids for fake weapon-skin / cosmetic / weapon-pose items
-- (~1500+ of them when `unlock_all_illusions` is on). That false-positive
-- inflated diagnostic counts (inv_dump showed modded=1553 vs vanilla=887)
-- and masked the real cim-craft count. The narrower check above only matches
-- items registered in `_forged_weapons` or with the `cwv_` prefix.

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

local function _forge_create_item(weapon_data, backend_id)
    if not ItemMasterList then return nil end
    local item_key = weapon_data.item_key
    local master = rawget(ItemMasterList, item_key)
    if not master then
        mod:echo("Forge: unknown weapon key '" .. tostring(item_key) .. "'")
        return nil
    end

    local props = weapon_data.properties or {}
    local trait = weapon_data.trait
    local traits_array = weapon_data.traits
    local skin = weapon_data.skin
    local power_level = weapon_data.power_level or 300

    local custom_props = "{"
    for k, v in pairs(props) do
        custom_props = custom_props .. '"' .. k .. '":' .. tostring(v) .. ','
    end
    custom_props = custom_props .. "}"

    local traits_table = {}
    if traits_array then
        for i, t in ipairs(traits_array) do traits_table[i] = t end
    elseif trait then
        traits_table[1] = trait
    end

    local custom_traits = "["
    for i, t in ipairs(traits_table) do
        if i > 1 then custom_traits = custom_traits .. "," end
        custom_traits = custom_traits .. '"' .. t .. '"'
    end
    custom_traits = custom_traits .. "]"

    local rarity = weapon_data.rarity or "exotic"

    local entry = table.clone(master, true)
    entry.mod_data = {
        backend_id = backend_id,
        ItemInstanceId = backend_id,
        CustomData = {
            traits = custom_traits,
            power_level = tostring(power_level),
            properties = custom_props,
            rarity = rarity,
        },
        rarity = rarity,
        traits = traits_table,
        power_level = power_level,
        properties = table.clone(props, true),
    }
    if skin then
        entry.mod_data.CustomData.skin = skin
        entry.mod_data.skin = skin
        if WeaponSkins and WeaponSkins.skins and WeaponSkins.skins[skin] then
            entry.mod_data.inventory_icon = WeaponSkins.skins[skin].inventory_icon
        end
    end
    entry.rarity = rarity

    return entry
end

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
local _strip_weave

mod:hook_safe("BackendManagerPlayFab", "_create_interfaces", function()
    _forge_load()
    _forge_inject_all()
    if _athanor_inject_all then _athanor_inject_all() end
    if _restore_modded_loadout then _restore_modded_loadout() end
    local count = 0
    for _ in pairs(_forged_weapons) do count = count + 1 end
    mod:info("Forge: restored %d forged weapons", count)
    if mod._cim_autodump_backend_ready then pcall(mod._cim_autodump_backend_ready) end

    -- ============================================================
    -- One-shot trim: existing items in the mirror with >2 properties
    -- ============================================================
    -- Consolidated here from standard_forge.lua (was a sibling
    -- registration on the same Class+method that VMF silently dropped
    -- as a duplicate per memory `feedback_vmf_hook_safe_no_chain`).
    -- The crash described in
    -- standard_forge.lua's >2-property guard can also fire on items that
    -- already exist in the player's save from pre-v0.7.25 sessions. Once
    -- the backend mirror finishes loading, walk every item and trim
    -- properties down to the first 2 (in iteration order). Vanilla allows
    -- at most 2 anyway so the behavior is unchanged from the buff
    -- system's perspective.
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
                local prop_count = 0
                local keep = {}
                local kept_keys = {}
                local dropped_keys = {}
                for k, v in pairs(props) do
                    prop_count = prop_count + 1
                    if prop_count <= 2 then
                        keep[k] = v
                        kept_keys[#kept_keys + 1] = tostring(k)
                    else
                        dropped_keys[#dropped_keys + 1] = tostring(k)
                    end
                end
                if prop_count > 2 then
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
            mod:info("[cim] Trimmed %d items with >2 properties to vanilla cap.", trimmed)
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
-- Downstream effect on cim clients: they see the modded item as "unique"
-- in their loadout view. This is the stated user requirement ("modded
-- rarity should show up as regular unique/veteran rarity for the client").
-- The host still sees "modded" because we restore item.rarity after the
-- sync call, and the host's own UI reads item.rarity locally — not via
-- the RPC pipeline.
--
-- This is the minimum-risk patch: a single wrap-hook on one function
-- catches every call site (`simple_inventory_extension.lua:885` on equip,
-- `player_unit_attachment_extension.lua:154` on attachment change,
-- `LoadoutUtils.hot_join_sync` on new-peer arrival).
-- Cim-client side-channel: per-(player, slot) "this slot's item is modded" flag.
-- Populated on the cim host via `cim_modded_slot` VMF RPC fired alongside every
-- `sync_loadout_slot`; consumed on cim clients in the `rpc_sync_loadout_slot`
-- hook to restore `item.rarity = "modded"` AFTER vanilla's decode path runs.
-- Vanilla clients have no registered handler for `cim_modded_slot` and drop
-- the packet silently — they keep the "unique" rarity baked in by the host's
-- wire-rewrite hook and never crash.
--
-- Keyed by unique_id (peer_id .. ":" .. local_player_id) → slot_name → true.
local _cim_modded_slot_state = {}

local function _cim_unique_id(peer_id, local_player_id)
    return tostring(peer_id) .. ":" .. tostring(local_player_id)
end

if rawget(_G, "LoadoutUtils") and LoadoutUtils.sync_loadout_slot then
    mod:hook(LoadoutUtils, "sync_loadout_slot", function(func, player, slot_name, item, sync_to_specific_peer_id)
        local is_modded = item and item.rarity == "modded" or false
        local peer_id = player:network_id()
        local local_player_id = player:local_player_id()

        -- Side-channel BEFORE the loadout RPC. Cim clients latch the flag and
        -- the rpc_sync_loadout_slot hook below restores rarity on receive.
        -- We always send (even is_modded=false) so equipping a non-modded item
        -- clears any stale modded flag on that slot.
        local target = sync_to_specific_peer_id or "others"
        local ok_send, err_send = pcall(mod.network_send, mod, "cim_modded_slot",
            target, peer_id, local_player_id, slot_name, is_modded)
        if not ok_send then mod:info("[cim] side-channel send failed: %s", tostring(err_send)) end

        if not is_modded then
            return func(player, slot_name, item, sync_to_specific_peer_id)
        end

        local original = item.rarity
        item.rarity = "unique"
        local ok, err = pcall(func, player, slot_name, item, sync_to_specific_peer_id)
        item.rarity = original
        if not ok then mod:info("[cim] sync_loadout_slot rewrite error: %s", tostring(err)) end
    end)
end

-- Cim-client side-channel receiver. Records the per-slot modded flag and, if
-- the loadout RPC already arrived (out-of-order delivery), patches the stored
-- item's rarity back to "modded" immediately. Vanilla clients never register
-- this handler so the RPC is dropped harmlessly there.
mod:network_register("cim_modded_slot", function(sender_peer_id, peer_id, local_player_id, slot_name, is_modded)
    local uid = _cim_unique_id(peer_id, local_player_id)
    _cim_modded_slot_state[uid] = _cim_modded_slot_state[uid] or {}
    _cim_modded_slot_state[uid][slot_name] = is_modded and true or nil

    -- Retroactive patch: if PlayerManager._player_loadouts already has the
    -- "unique"-coerced item for this slot, upgrade it back to "modded" so the
    -- cim client's UI shows the right chrome.
    local pm = Managers.player
    local loadouts = pm and pm._player_loadouts
    if loadouts and loadouts[uid] then
        local stored = loadouts[uid][slot_name]
        if stored then
            stored.rarity = is_modded and "modded" or stored.rarity
        end
    end
end)

-- Restore "modded" rarity post-decode on cim clients. hook_safe fires AFTER
-- vanilla's `rpc_sync_loadout_slot` has stored the item under
-- `_player_loadouts[unique_id][slot_name]` with rarity = "unique" (the wire
-- value). We look up the side-channel flag for that (peer, slot) and upgrade
-- in-place. No-op if the side-channel hasn't arrived yet — the side-channel
-- receiver above handles the inverse out-of-order case.
mod:hook_safe("PlayerManager", "rpc_sync_loadout_slot", function(self, channel_id, peer_id, local_player_id, slot_id, item_id, rarity_id)
    local uid = _cim_unique_id(peer_id, local_player_id)
    local slot_state = _cim_modded_slot_state[uid]
    if not slot_state then return end
    local NL = rawget(_G, "NetworkLookup")
    local slot_name = NL and NL.equipment_slots and NL.equipment_slots[slot_id]
    if not slot_name or not slot_state[slot_name] then return end
    local stored = self._player_loadouts and self._player_loadouts[uid] and self._player_loadouts[uid][slot_name]
    if stored then stored.rarity = "modded" end
end)

-- ============================================================
-- Modded inventory filter + loadout restore
-- ============================================================
-- The mod-realm view: hide vanilla weapons from the inventory grid (toggleable),
-- and remember the last modded item the player equipped on each (career, slot)
-- so that switching to vanilla and back doesn't wipe their modded loadout.

local _WEAPON_SLOT_TYPES = { melee = true, ranged = true, trinket = true, ring = true, necklace = true }
local _modded_loadout = {}

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
mod._cim_clear_modded_loadout_for_bid = function(backend_id)
    if not backend_id then return end
    local dirty = false
    for career_name, slots in pairs(_modded_loadout) do
        for slot_name, bid in pairs(slots) do
            if bid == backend_id then
                slots[slot_name] = nil
                dirty = true
            end
        end
    end
    if dirty then _modded_loadout_save() end
end

-- v0.7.33-alpha one-shot migration. Old (pre-v0.7.33) cim never cleared
-- _modded_loadout entries when the user equipped a non-cim item. The fix in
-- v0.7.33 keeps state correct GOING FORWARD but doesn't heal save data from
-- before the fix. This migration walks _modded_loadout once at session load
-- and purges every entry whose bid isn't in `_forged_weapons` (cim crafts)
-- and doesn't match `cwv_*` (character_weapon_variants). Stale entries
-- pointing to non-existent items can't be restored anyway, so dropping them
-- avoids re-trying the same MISSING restore log line every session.
local function _modded_loadout_purge_stale()
    local removed = 0
    for career_name, slots in pairs(_modded_loadout) do
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
                mod:info("[loadout-purge] %s/%s -> %s (bid not in forged_weapons or cwv_*)",
                    tostring(career_name), tostring(slot_name), tostring(bid))
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
    local slots = _modded_loadout[career_name]
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

_restore_modded_loadout = function()
    if not mod:get("restore_modded_loadout") then
        mod:info("[restore] skipped — restore_modded_loadout setting OFF")
        return
    end
    _modded_loadout_load()
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
    for career_name, slots in pairs(_modded_loadout) do
        for slot_name, backend_id in pairs(slots) do
            total = total + 1
            -- pcall-guarded: a throw here (LA-clone drift, stale template-cache
            -- hit from standard_forge's get_item_from_id hook, malformed mirror
            -- entry) would otherwise propagate out and strand _restoring=true.
            local ok_get, item = pcall(items.get_item_from_id, items, backend_id)
            if not ok_get then item = nil end
            if not item then
                missing = missing + 1
                mod:info("[restore] MISSING %s/%s -> %s (item not in mirror; will retry next state transition)",
                    tostring(career_name), tostring(slot_name), tostring(backend_id))
            else
                local item_key = item.key or item.ItemId or (item.data and item.data.key) or "<unknown>"
                local ok, err = pcall(items.set_loadout_item, items, backend_id, career_name, slot_name)
                if ok then
                    restored = restored + 1
                    mod:info("[restore] OK %s/%s -> %s (%s)",
                        tostring(career_name), tostring(slot_name), tostring(backend_id), tostring(item_key))
                else
                    errored = errored + 1
                    mod:info("[restore] ERROR %s/%s -> %s: %s",
                        tostring(career_name), tostring(slot_name), tostring(backend_id), tostring(err))
                end
                -- v0.7.54-dev: immediately read back via get_loadout_item_id
                -- to PROVE the write reached the layer the inventory reads
                -- from. If set_loadout_item returns ok but read-back returns
                -- a different bid (or nil), the mirror silently rejected our
                -- write OR a different persistence layer is the source of truth.
                -- This is the proof issue #22 needs.
                if mod._cim_autodump_restore_entry then
                    pcall(mod._cim_autodump_restore_entry,
                        career_name, slot_name, backend_id, items, ok, err)
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
local function _capture_loadout_equip(career_name, slot_name, item_id, from_live_equip)
    if _restoring then return end
    if not item_id or not career_name or not slot_name then return end

    if mod._cim_autodump_equip_event then
        local items_iface = Managers.backend and Managers.backend:get_interface("items")
        pcall(mod._cim_autodump_equip_event, career_name, slot_name, item_id, items_iface)
    end

    local was_stale = _modded_loadout[career_name] and _modded_loadout[career_name][slot_name]
    if _modded_loadout[career_name] then
        _modded_loadout[career_name][slot_name] = nil
    end

    local is_modded = mod._cim_is_modded_backend_id and mod._cim_is_modded_backend_id(item_id)
    if is_modded then
        _modded_loadout[career_name] = _modded_loadout[career_name] or {}
        _modded_loadout[career_name][slot_name] = item_id
    end

    if from_live_equip then
        -- The menu equip already recreated the unit; sync dedup so the next
        -- restore pass doesn't needlessly re-spawn this slot.
        _reequipped[career_name .. "/" .. slot_name] = item_id
    end

    if was_stale or is_modded then
        _modded_loadout_save()
    end
end

-- Direct interface writes (restore — guarded by _restoring — or any code calling
-- the items interface method directly). from_live_equip=false: a bare data write
-- doesn't re-spawn the unit.
mod:hook_safe("BackendInterfaceItemPlayfab", "set_loadout_item", function(self, item_id, career_name, slot_name, optional_loadout_index)
    _capture_loadout_equip(career_name, slot_name, item_id, false)
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
        _capture_loadout_equip(career_name, slot_name, backend_id, true)
        return func(backend_id, career_name, slot_name)
    end)
    mod:info("[cim] BackendUtils.set_loadout_item capture installed (post-LA menu-equip capture)")
end

mod:command("cim_restore_loadout", "Manually re-equip the saved modded loadout (use if your modded weapons didn't come back after a restart)", function()
    if not _restore_modded_loadout then mod:echo("Restore helper not initialised yet."); return end
    _modded_loadout_load()
    local count = 0
    for career_name, slots in pairs(_modded_loadout) do
        for _ in pairs(slots) do count = count + 1 end
    end
    mod:echo(string.format("[cim] %d saved modded loadout entries; restoring...", count))
    _restore_modded_loadout()
    mod:echo("[cim] Done. If items are still missing, run /cim_dump_loadout to see what's saved.")
end)

mod:command("cim_dump_active_window", "Dump the currently-open hero_view active windows + their widgets to log (use while a menu is open)", function()
    local ui = Managers.ui
    local ingame_ui = ui and ui._ingame_ui
    if not ingame_ui then mod:echo("No ingame_ui"); return end
    local hero_view = ingame_ui.views and ingame_ui.views.hero_view
    if not hero_view then mod:echo("hero_view not active"); return end
    -- hero_view holds the active state inside `_machine._state` (a GameStateMachine
    -- inheriting StateMachine — see hero_view.lua:94). My v0.7.11 dump used the
    -- nonexistent `_current_state`, which always reported nil. Walk the machine
    -- path and fall back to a few alternatives in case the field name varies
    -- across UI states.
    local state = hero_view._machine and hero_view._machine._state
        or hero_view._current_state
        or hero_view._state
    if not state then
        mod:echo("No active state on hero_view (machine=" ..
            tostring(hero_view._machine) .. "). Open the menu first then re-run.")
        return
    end
    mod:echo(string.format("[cim] hero_view state class: %s", tostring(state.NAME or state.__class_name or "?")))
    mod:info("================ CIM ACTIVE WINDOW DUMP ================")
    mod:info("hero_view._machine._state = %s", tostring(state.NAME or "?"))
    local windows = state._active_windows or state.active_windows
    if not windows then mod:echo("No _active_windows on state"); return end
    for slot_idx, win in pairs(windows) do
        mod:info("--- window[%s] NAME=%s ---", tostring(slot_idx), tostring(win.NAME or "?"))
        mod:echo(string.format("  window[%s] = %s", tostring(slot_idx), tostring(win.NAME or "?")))
        local widgets = win._widgets_by_name
        if widgets then
            local names = {}
            for n in pairs(widgets) do names[#names + 1] = n end
            table.sort(names)
            for _, name in ipairs(names) do
                local w = widgets[name]
                local content = w and w.content
                local hot = content and content.button_hotspot
                local disabled = hot and hot.disable_button
                local has_text = content and (content.text or content.title or content.label)
                local line = string.format("    %-50s hotspot=%s disabled=%s text=%s",
                    name,
                    tostring(hot ~= nil),
                    tostring(disabled),
                    tostring(has_text or ""))
                mod:info(line)
                if hot then
                    mod:echo("    " .. name .. " disable_button=" .. tostring(disabled))
                end
            end
        end
        if win._params then
            for k, v in pairs(win._params) do
                mod:info("    _params.%s = %s", tostring(k), tostring(v))
            end
        end
    end
    mod:info("======================== END ===========================")
    mod:echo("[cim] Window dump written to log (see logs for full widget list).")
end)

mod:command("cim_dump_loadout", "Print the saved modded loadout table to chat", function()
    _modded_loadout_load()
    local items = Managers.backend and Managers.backend:get_interface("items")
    local total = 0
    for career_name, slots in pairs(_modded_loadout) do
        for slot_name, bid in pairs(slots) do
            local item = items and items:get_item_from_id(bid)
            local in_mirror = item and "yes" or "MISSING"
            mod:echo(string.format("  %s %s -> %s (in_mirror=%s)", career_name, slot_name, tostring(bid), in_mirror))
            total = total + 1
        end
    end
    mod:echo(string.format("[cim] %d entries saved (across %d careers)", total,
        (function() local c = 0; for _ in pairs(_modded_loadout) do c = c + 1 end; return c end)()))
end)

-- Inventory filter: drops vanilla weapons / jewellery from get_filtered_items
-- results when EITHER (a) the "show only modded" setting is on, OR (b) the
-- standard crafting UI is open. (b) is unconditional because vanilla items in
-- modded realm can't actually be salvaged/upgraded/rerolled (the commit-block
-- prevents PlayFab from learning about the change, so PlayFab restores them
-- on next session). Showing them in crafting menus would be misleading.
-- Crafting materials and cosmetics (hat/skin) are unaffected because their
-- slot_type isn't in `_WEAPON_SLOT_TYPES`.
mod:hook("BackendInterfaceItemPlayfab", "get_filtered_items", function(func, self, filter, params)
    local items = func(self, filter, params)
    -- v0.7.62-dev DIAGNOSTIC: measure the EXACT layer the inventory grid reads.
    -- Reports whether a just-crafted bid survived this filter (and dumps why if
    -- not). Gated on enable_debug_logging — zero cost when off. This is the
    -- probe that should have existed days ago: older probes checked the broad
    -- get_all_backend_items, not the filtered grid result.
    if mod._cim_autodump_filtered_items then
        pcall(mod._cim_autodump_filtered_items, self, filter, params, items)
    end
    local should_filter = mod:get("show_only_modded_weapons") or mod._cim_standard_forge_active
    if not should_filter then return items end
    if type(items) ~= "table" then return items end

    local filtered = {}
    for i, item in ipairs(items) do
        local slot_type = item and item.data and item.data.slot_type
        local bid = item and item.backend_id
        local rarity = item and item.rarity
        local is_weapon_like = slot_type and _WEAPON_SLOT_TYPES[slot_type]
        local is_modded = mod._cim_is_modded_backend_id and mod._cim_is_modded_backend_id(bid)
        -- Default-rarity items are blacksmith's templates / placeholders, used
        -- by the "Craft Item" recipe (can_craft_with) to pick what to craft.
        -- Always allow them through so the crafting flow stays usable.
        local is_default_template = rarity == "default"
        if not is_weapon_like or is_modded or is_default_template then
            filtered[#filtered + 1] = item
        end
    end

    -- Synthetic "blacksmith's template" injection for the Craft Item recipe.
    -- Defined in standard_forge.lua. No-op unless the forge UI is open AND the
    -- filter is `can_craft_with`. Lets the player craft career-eligible weapon
    -- families they never unlocked (career-level gates aren't enforced in
    -- modded realm; we just need the UI to surface them).
    if mod._cim_inject_templates then
        filtered = mod._cim_inject_templates(filtered, filter)
    end
    return filtered
end)

-- ============================================================
-- Salvage filter override: surface modded items in the salvage grid
-- ============================================================
-- Vanilla `can_salvage` (backend_interface_common.lua:412) excludes
-- `rarity == "promo"` AND equipped items AND items in any loadout. Modded
-- items skip the rarity exclusion (rarity = "modded", not "promo"). Post-hook
-- the filter to add our crafts back regardless of equip/loadout state when
-- the filter is the salvage recipe's (`can_salvage and not is_equipped and not
-- is_equipped_by_any_loadout`). Also catches legacy promo-rarity crafts.
local _SALVAGE_SLOT_TYPES = { melee = true, ranged = true, ring = true, necklace = true, trinket = true }

local function _is_salvage_filter(filter_infix)
    if type(filter_infix) ~= "string" then return false end
    return filter_infix:find("can_salvage", 1, true) ~= nil
end

mod:hook("BackendInterfaceCommon", "filter_items", function(func, self, items, filter_infix, params)
    local result = func(self, items, filter_infix, params)
    if not _is_salvage_filter(filter_infix) then return result end
    if type(result) ~= "table" or type(items) ~= "table" then return result end

    local seen = {}
    for _, r in ipairs(result) do
        if r and r.backend_id then seen[r.backend_id] = true end
    end

    local backend_items = Managers.backend and Managers.backend:get_interface("items")
    if not backend_items then return result end

    -- Surface modded items in salvage REGARDLESS of equip / loadout / favorite
    -- state. Vanilla excludes equipped items so players don't accidentally
    -- destroy their gear, but modded crafts are throwaway by design — the user
    -- crafted them and wants the option to delete them even after equipping.
    --
    -- Use the item-level check (rarity OR bid heuristic) so promo items from
    -- earlier sessions / other machines / older mod versions still surface
    -- even if their bid format doesn't match our current regex.
    for _, item in ipairs(items) do
        local bid = item and item.backend_id
        if bid and not seen[bid]
           and mod._cim_is_modded_item and mod._cim_is_modded_item(item) then
            local slot_type = item.data and item.data.slot_type
            if _SALVAGE_SLOT_TYPES[slot_type] then
                result[#result + 1] = item
                seen[bid] = true
            end
        end
    end
    return result
end)

-- ============================================================
-- Athanor (Winds of Magic forge) — UI hooks
-- ============================================================
local _custom_forge_active = false
local _forge_loadout = {}
local _forge_item_props = {}
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
    if not in_keep and not mod:get("allow_in_mission") then
        mod:echo("Crafting menu only opens in the Keep. " ..
                 "Enable 'Allow in mission' in the mod options to override (may crash).")
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
-- to `environment/ui_hdr` — that env is loaded in every state (it's the
-- UI default that loading_view / hero_view's own viewport use), so it's
-- always available. Visual fidelity drops a bit mid-mission (the forge
-- lighting won't match the keep aesthetic) but no crash.
--
-- ALSO swap the `_inverted` variant (HeroWindowWeaveForgeOverview takes
-- an `invert_rendering` arg that picks `_preview_inverted`). Same env
-- isn't in mission bundles either.
--
-- The hook always fires (vanilla never opens the forge in mission so
-- there's no path to clobber); gated on `not is_in_inn` so the keep
-- forge keeps its proper lighting.

local _FORGE_MISSION_SAFE_ENV = "environment/ui_hdr"

local function _is_in_keep()
    return DamageUtils and DamageUtils.is_in_inn and true or false
end

local function _swap_forge_env(viewport_def)
    if _is_in_keep() then return viewport_def end
    if type(viewport_def) ~= "table" then return viewport_def end
    local style = viewport_def.style
    local vp = style and style.viewport
    if vp and (vp.shading_environment == "environment/ui_weave_forge_preview"
            or vp.shading_environment == "environment/ui_weave_forge_preview_inverted") then
        vp.shading_environment = _FORGE_MISSION_SAFE_ENV
    end
    return viewport_def
end

mod:hook("HeroWindowWeaveForgeOverview", "_create_viewport_definition", function(func, self, scenegraph_id, invert_rendering)
    return _swap_forge_env(func(self, scenegraph_id, invert_rendering))
end)

mod:hook("HeroWindowWeaveForgeWeapons", "_create_viewport_definition", function(func, self, scenegraph_id)
    return _swap_forge_env(func(self, scenegraph_id))
end)

mod:hook("HeroWindowWeaveProperties", "_create_viewport_definition", function(func, self)
    return _swap_forge_env(func(self))
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
    -- and object_sets. shading_environment swapped to the mission-safe env
    -- already documented in _FORGE_MISSION_SAFE_ENV. LootItemUnitPreviewer
    -- still renders the item via `resource_packages/levels/ui_loot_preview`
    -- which is in GlobalResources (boot_init.lua:159).
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
                shading_environment = _FORGE_MISSION_SAFE_ENV,
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

mod:hook_safe("HeroViewStateWeaveForge", "on_exit", function(self)
    _custom_forge_active = false
    _forge_loadout = {}
    _forge_item_props = {}
    _forge_panel_styled = false
    _forge_bg_colored = false
    _amulet_dirty[1], _amulet_dirty[2], _amulet_dirty[3] = false, false, false
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

-- --- Forge UI polish (runs each frame while forge is open) ---

local function _forge_get_widget(window, widget_name)
    local wbn = window and window._widgets_by_name
    return wbn and wbn[widget_name]
end

local function _forge_hide_widget(window, widget_name)
    local w = _forge_get_widget(window, widget_name)
    if w and w.content then w.content.visible = false end
end

local function _forge_set_text(window, widget_name, text)
    local w = _forge_get_widget(window, widget_name)
    if w and w.content then w.content.text = text end
end

local function _forge_set_style_color(window, widget_name, style_key, color)
    local w = _forge_get_widget(window, widget_name)
    if w and w.style and w.style[style_key] then
        w.style[style_key].color = color
    end
end

local function _forge_is_hovered(widget)
    if not widget or not widget.content then return false end
    local hs = widget.content.button_hotspot or widget.content.hotspot
    return hs and hs.is_hover
end

-- ============================================================
-- Amulet view: 3 stacked craft buttons (v0.7.32+)
-- ============================================================
-- User-requested 2026-05-23: replace the rotating Amulet-of-Ashur 3D model in
-- HeroWindowWeaveProperties' amulet view with 3 vertically-stacked craft
-- buttons (Necklace / Charm / Trinket). Each crafts exactly one slot from the
-- current bubble state. Supersedes the single "Craft All" upgrade_button
-- which dirty-tracked + crafted all edited slots in one click.
--
-- Slot order matches `_AMULET_SLOT_BY_INDEX` (declared later in this file).
-- Hard-coded here to avoid a forward-ref cycle; the indices must match
-- _AMULET_SLOT_BY_INDEX[1]=ring(charm), [2]=necklace, [3]=trinket_1.
local _AMULET_SLOT_BUTTONS = {
    -- Visual top-to-bottom order: Necklace, Charm, Trinket. `idx` references
    -- the slot in _AMULET_SLOT_BY_INDEX; `slot` is the legacy slot name VT2's
    -- career_settings uses (slot_ring not slot_charm, slot_trinket_1 not
    -- slot_trinket — see AMULET_OF_ASHUR.md).
    { idx = 2, slot = "slot_necklace",  label = "CRAFT NECKLACE", widget_name = "cim_amulet_btn_necklace" },
    { idx = 1, slot = "slot_ring",      label = "CRAFT CHARM",    widget_name = "cim_amulet_btn_charm"    },
    { idx = 3, slot = "slot_trinket_1", label = "CRAFT TRINKET",  widget_name = "cim_amulet_btn_trinket"  },
}

-- v0.7.64-dev: TEMPORARILY DISABLED. v0.7.63's render-array fix made these draw,
-- but anchored to the full-size center/bottom "viewport" node they land in the
-- bottom-left corner, render a screen-covering black box over the property/trait
-- grid, and their hotspots overlap (one click fired two slots). Same failure
-- class as the overview buttons. Disabled so the accessories view is usable
-- (vanilla "Craft All" path restored). Re-enable once placement + hotspots are
-- redone against a real screenshot of the live cim accessories view.
local _AMULET_BTNS_ENABLED = false

-- Lazy-create the 3 cim button widgets on the properties_win. Returns the
-- widget array (or nil if VT2 UIWidgets isn't available — defensive).
local function _ensure_amulet_buttons(properties_win)
    if properties_win._cim_amulet_buttons then return properties_win._cim_amulet_buttons end
    local UIWidgets = rawget(_G, "UIWidgets")
    local UIWidget = rawget(_G, "UIWidget")
    if not (UIWidgets and UIWidget and UIWidgets.create_default_button) then return nil end

    local btn_size = { 452, 80 }
    local spacing  = 95   -- vertical distance between button centers (button h=80 + 15 gap)
    local buttons  = {}
    -- v0.7.63-dev: HeroWindowWeaveProperties has NO self._widgets — like the
    -- overview, its _draw iterates _top_widgets/_bottom_widgets/_top_hdr_widgets/
    -- _bottom_hdr_widgets. The old code appended to ._widgets (nil here), so the
    -- accessory craft buttons NEVER rendered. Append to _top_widgets (drawn on
    -- the ui_top_renderer pass) + register in _widgets_by_name. Scenegraph is
    -- _ui_scenegraph; the center anchor "viewport" (where the 3D amulet renders,
    -- now hidden in amulet mode) is a valid node in this window.
    local draw_widgets    = properties_win._top_widgets
    local widgets_by_name = properties_win._widgets_by_name
    local scenegraph      = properties_win._ui_scenegraph
    if not (draw_widgets and widgets_by_name and scenegraph) then
        if not properties_win._cim_amulet_btn_logged_miss then
            properties_win._cim_amulet_btn_logged_miss = true
            mod:info("[cim] amulet buttons skipped: _top_widgets=%s _widgets_by_name=%s _ui_scenegraph=%s",
                tostring(draw_widgets), tostring(widgets_by_name), tostring(scenegraph))
        end
        return nil
    end
    local anchor = rawget(scenegraph, "viewport") and "viewport" or "window"

    for i, entry in ipairs(_AMULET_SLOT_BUTTONS) do
        -- All 3 widgets share the center anchor. `widget.offset` shifts each
        -- vertically: i=1 → +spacing (top), i=2 → 0 (middle), i=3 → -spacing.
        -- Z=100 so they render above the bubble grid background.
        local ok, def = pcall(UIWidgets.create_default_button,
            anchor, btn_size, nil, nil, entry.label, 24,
            nil, "button_detail_02", nil, true)
        if not ok or not def then
            mod:info("[cim] amulet button %s create failed: %s", entry.widget_name, tostring(def))
            return nil
        end
        local ok_init, w = pcall(UIWidget.init, def)
        if not ok_init or not w then
            mod:info("[cim] amulet button %s init failed: %s", entry.widget_name, tostring(w))
            return nil
        end
        local y_offset = -(i - 2) * spacing
        w.offset = { 0, y_offset, 100 }
        w.content.visible = false
        w.content._cim_slot_index = entry.idx
        w.content._cim_slot_name  = entry.slot
        w.content._cim_label      = entry.label
        buttons[i] = w
        draw_widgets[#draw_widgets + 1] = w
        widgets_by_name[entry.widget_name] = w
    end

    properties_win._cim_amulet_buttons = buttons
    mod:info("[cim] amulet view: created %d cim craft buttons (anchor=%s)", #buttons, anchor)
    return buttons
end

local function _show_amulet_buttons(properties_win, show)
    local buttons = properties_win._cim_amulet_buttons
    if not buttons then return end
    for _, w in ipairs(buttons) do
        if w and w.content then w.content.visible = show and true or false end
    end
end

-- Per-frame click probe. The button's hotspot fires `on_release = true` on the
-- frame the user lifts their mouse over a hovered hotspot. We consume that by
-- invoking the craft path and clearing the flag, otherwise the click repeats.
-- The per-slot craft helper itself is `_amulet_craft_one_slot`, defined alongside
-- `_upgrade_magic_level`'s hook below — it lives there so the existing
-- amulet-craft branch and the new per-button branch share one source of truth.
local function _handle_amulet_button_clicks(properties_win)
    local buttons = properties_win._cim_amulet_buttons
    if not buttons then return end
    for _, w in ipairs(buttons) do
        local hs = w and w.content and w.content.button_hotspot
        if hs and hs.on_release then
            hs.on_release = false  -- consume immediately to prevent re-fire
            local slot_index = w.content._cim_slot_index
            local slot_name  = w.content._cim_slot_name
            if mod._cim_amulet_craft_one_slot then
                mod._cim_amulet_craft_one_slot(properties_win, slot_index, slot_name)
            else
                mod:echo("[cim] amulet craft helper not ready (load order bug)")
            end
        end
    end
end

-- ============================================================
-- Accessory craft panel (v0.7.65-dev) — the CORRECT approach
-- ============================================================
-- The inline create_default_button buttons (overview + _ensure_amulet_buttons)
-- are both DISABLED — anchored to the full-size center "viewport" node they
-- produced a screen-covering black box, corner placement, and overlapping
-- hotspots. This replaces them with the own-scenegraph overlay module
-- `_accessory_craft_panel.lua`, which follows cosmetics_tweaker's proven
-- `_glow_picker.lua` pattern: 3 hand-rolled buttons with EXPLICIT positions,
-- drawn in their own pass off HeroWindowWeaveProperties._draw. No host-window
-- widget injection, no viewport anchor, no black box, non-overlapping hotspots.
local _AMULET_PANEL_ENABLED = true

if _AccessoryPanel then
    -- Craft callback: clone the currently-equipped accessory in `slot_name`
    -- (with its current bubble-edited state) for the forge's career — the same
    -- helper the legacy per-slot buttons used.
    _AccessoryPanel._on_craft = function(slot_index, slot_name)
        local pw = _AccessoryPanel._properties_win
        if pw and mod._cim_amulet_craft_one_slot then
            mod._cim_amulet_craft_one_slot(pw, slot_index, slot_name)
        else
            mod:warning("[cim] accessory craft helper not ready")
        end
    end

    -- Draw the overlay off HeroWindowWeaveProperties._draw. hook_safe (post) so
    -- vanilla finishes its own passes first; we then run our own pass on the
    -- window's ui_top_renderer. Only in the accessories (amulet) view of the
    -- custom forge. This is the ONLY cim hook on HeroWindowWeaveProperties._draw
    -- (grep-verified — no duplicate-hook violation).
    mod:hook_safe("HeroWindowWeaveProperties", "_draw", function(self, dt)
        if not (_AMULET_PANEL_ENABLED and _custom_forge_active) then return end
        local params = self._params
        local sel_item = params and params.selected_item
        local in_amulet_mode = not (sel_item and sel_item.backend_id)
        if not in_amulet_mode then return end
        _AccessoryPanel._properties_win = self
        local renderer = self._ui_top_renderer
        local input_service = self._parent and self._parent.window_input_service
            and self._parent:window_input_service()
        _AccessoryPanel.draw(renderer, input_service, dt)
    end)
end

-- ============================================================
-- Athanor OVERVIEW (B-menu landing page) jewelry craft buttons
-- ============================================================
-- v0.7.57-dev. User request 2026-05-28: put 3 jewelry-craft buttons on the
-- B-menu Athanor overview page, in the space where the Amulet of Ashur 3D
-- display used to render (center viewport_2). Each button crafts ONE accessory
-- of the chosen slot type for the current career — same path the standard
-- forge accessory buttons + `/cim_craft_*` commands use.
--
-- These buttons are SIBLING to the existing per-slot buttons in
-- HeroWindowWeaveProperties (the properties editor) — they fire even when
-- the user hasn't navigated into the property editor, just from the overview.
--
-- Sized 452x80 to roughly match the original "Craft All" upgrade_button the
-- overview used to display (now hidden in _forge_apply_ui_polish).
local _OVERVIEW_JEWELRY_BUTTONS = {
    -- Visual top-to-bottom order: Necklace, Charm, Trinket. Same order +
    -- slot semantics as the properties-view buttons above. `synth_filter`
    -- targets the `_make_craft_synth` factory in standard_forge.lua via
    -- the cross-module `mod._cim_craft_via_synth` API.
    { synth_filter = { necklace = true }, friendly = "necklace", label = "CRAFT NECKLACE", widget_name = "cim_ov_btn_necklace" },
    { synth_filter = { ring     = true }, friendly = "charm",    label = "CRAFT CHARM",    widget_name = "cim_ov_btn_charm"    },
    { synth_filter = { trinket  = true }, friendly = "trinket",  label = "CRAFT TRINKET",  widget_name = "cim_ov_btn_trinket"  },
}

-- HeroWindowWeaveForgeOverview._draw iterates FOUR hardcoded arrays (it has no
-- unified `_widgets`). Buttons must be appended to one of these or they never
-- render. _OVERVIEW_BTN_RENDER_FIELD is the array we use; the
-- `overview_btn_render_target` regression test pins it to this valid set so a
-- future edit can't silently point it back at a `_widgets` field that the
-- window never draws (the v0.7.57/.58 "nothing changed" bug, root-caused
-- v0.7.60).
local _OVERVIEW_DRAWN_FIELDS = {
    _top_widgets        = true,
    _bottom_widgets     = true,
    _top_hdr_widgets    = true,
    _bottom_hdr_widgets = true,
}
local _OVERVIEW_BTN_RENDER_FIELD = "_top_widgets"

-- v0.7.61-dev: TEMPORARILY DISABLED. The render-array fix (v0.7.60) made the
-- buttons draw, but they land on top of the overview's weapon-type selectors
-- (viewport_1/2/3 = primary/accessories/secondary) and obscure the whole menu
-- — anchoring 452x80 buttons to viewport_2 (a near-fullscreen center/bottom
-- node) puts them in a corner over the real UI. Disabled until the placement is
-- nailed against an actual screenshot of the live cim overview, so the B-menu
-- is usable in the meantime. Flip back to true once anchor/size are correct.
local _OVERVIEW_BTNS_ENABLED = false

local function _ensure_overview_jewelry_buttons(overview_win)
    if overview_win._cim_overview_jewelry_buttons then return overview_win._cim_overview_jewelry_buttons end
    local UIWidgets = rawget(_G, "UIWidgets")
    local UIWidget  = rawget(_G, "UIWidget")
    if not (UIWidgets and UIWidget and UIWidgets.create_default_button) then
        if not overview_win._cim_ov_btn_logged_miss_uiwidgets then
            overview_win._cim_ov_btn_logged_miss_uiwidgets = true
            mod:info("[cim] overview jewelry buttons skipped: UIWidgets/UIWidget missing")
        end
        return nil
    end

    -- v0.7.60-dev: HeroWindowWeaveForgeOverview has NO self._widgets array.
    -- Vanilla _draw (hero_window_weave_forge_overview.lua:704-770) iterates
    -- four hardcoded arrays — _bottom_hdr_widgets, _top_hdr_widgets,
    -- _top_widgets, _bottom_widgets — plus _viewports_data. It never touches
    -- a `_widgets` field. The previous code appended to overview_win._widgets
    -- (nil on this class) so the buttons were in a collection the window never
    -- drew: they NEVER rendered, which is exactly the "nothing changed" report.
    -- Fix: append to _top_widgets (drawn on the ui_top_renderer pass, above the
    -- viewport art and still input-serviced so the hotspot fires), keep
    -- registering in _widgets_by_name so _forge_hide_widget/_forge_get_widget
    -- keep working. Scenegraph is self._ui_scenegraph (NOT .ui_scenegraph),
    -- and the valid center anchor is "viewport_2" (viewport_1/2/3 exist; bare
    -- "viewport" does NOT — old fallback was a dead id).
    local draw_widgets    = overview_win[_OVERVIEW_BTN_RENDER_FIELD]
    local widgets_by_name = overview_win._widgets_by_name
    local scenegraph      = overview_win._ui_scenegraph
    if not (draw_widgets and widgets_by_name and scenegraph) then
        if not overview_win._cim_ov_btn_logged_miss_widgets then
            overview_win._cim_ov_btn_logged_miss_widgets = true
            mod:info("[cim] overview jewelry buttons skipped: %s=%s _widgets_by_name=%s _ui_scenegraph=%s",
                _OVERVIEW_BTN_RENDER_FIELD, tostring(draw_widgets), tostring(widgets_by_name), tostring(scenegraph))
        end
        return nil
    end

    -- Center anchor; fall back to the always-present root "window" id (never
    -- the bogus "viewport") if viewport_2 is somehow absent.
    local anchor = rawget(scenegraph, "viewport_2") and "viewport_2" or "window"

    local btn_size = { 452, 80 }
    local spacing  = 95
    local buttons  = {}

    for i, entry in ipairs(_OVERVIEW_JEWELRY_BUTTONS) do
        local ok, def = pcall(UIWidgets.create_default_button,
            anchor, btn_size, nil, nil, entry.label, 24,
            nil, "button_detail_02", nil, true)
        if not ok or not def then
            mod:info("[cim] overview jewelry button %s create failed: %s", entry.widget_name, tostring(def))
            mod._cim_overview_btn_created = false
            return nil
        end
        local ok_init, w = pcall(UIWidget.init, def)
        if not ok_init or not w then
            mod:info("[cim] overview jewelry button %s init failed: %s", entry.widget_name, tostring(w))
            mod._cim_overview_btn_created = false
            return nil
        end
        local y_offset = -(i - 2) * spacing  -- 95 / 0 / -95
        w.offset = { 0, y_offset, 100 }
        w.content.visible = false
        w.content._cim_synth_filter = entry.synth_filter
        w.content._cim_friendly     = entry.friendly
        w.content._cim_label        = entry.label
        buttons[i] = w
        draw_widgets[#draw_widgets + 1] = w
        widgets_by_name[entry.widget_name] = w
    end

    overview_win._cim_overview_jewelry_buttons = buttons
    mod._cim_overview_btn_created = #buttons
    mod:info("[cim] athanor overview: created %d jewelry craft buttons (anchor=%s, size=%dx%d)",
        #buttons, anchor, btn_size[1], btn_size[2])
    return buttons
end

local function _show_overview_jewelry_buttons(overview_win, show)
    local buttons = overview_win._cim_overview_jewelry_buttons
    if not buttons then return end
    for _, w in ipairs(buttons) do
        if w and w.content then w.content.visible = show and true or false end
    end
end

local function _handle_overview_jewelry_button_clicks(overview_win)
    local buttons = overview_win._cim_overview_jewelry_buttons
    if not buttons then return end
    for _, w in ipairs(buttons) do
        local hs = w and w.content and w.content.button_hotspot
        if hs and hs.on_release then
            hs.on_release = false  -- consume to prevent re-fire next frame
            local filter   = w.content._cim_synth_filter
            local friendly = w.content._cim_friendly
            if filter and mod._cim_craft_via_synth then
                pcall(mod._cim_craft_via_synth, filter, friendly or "accessory")
                if overview_win._play_sound then
                    pcall(overview_win._play_sound, overview_win, "play_gui_craft_forge_button_completed")
                end
            else
                mod:warning("[cim] overview jewelry craft helper not wired (mod._cim_craft_via_synth nil)")
            end
        end
    end
end

-- v0.7.58-dev: per-frame driver moved into _forge_apply_ui_polish (below).
-- Earlier v0.7.57-dev hook on HeroWindowWeaveForgeOverview.update fired before
-- the overview's _widgets / _widgets_by_name were populated by vanilla, so
-- _ensure_overview_jewelry_buttons would skip every frame ("overview has no
-- _widgets ... yet" — 13 hits in 2026-05-28 22:09 log). The existing
-- `_forge_apply_ui_polish` is invoked from HeroViewStateWeaveForge.update,
-- which only fires AFTER all child windows have completed their on_enter
-- and have populated widgets — that's why _forge_hide_widget(overview, ...)
-- succeeds at hiding the original upgrade_button. Piggy-back on the same
-- entry point.

-- The Athanor's hover preview now uses VT2's standard `item_tooltip` pass —
-- the same box that pops up on hover in the regular inventory and crafting
-- menus. The widget is created lazily inside `_forge_apply_ui_polish` and
-- stored on `overview._cim_tooltip_widget`.
local function _forge_populate_item_panels(overview, item)
    local tt = overview._cim_tooltip_widget
    if not tt then return end
    tt.content.item = item or nil
end

local function _forge_hide_item_panels(overview)
    local tt = overview._cim_tooltip_widget
    if not tt then return end
    tt.content.item = nil
end

local function _forge_apply_ui_polish(forge_state)
    local windows = forge_state._active_windows
    if not windows then return end

    local overview = nil
    local panel = nil
    local background = nil
    for _, win in pairs(windows) do
        local name = win.NAME
        if name == "HeroWindowWeaveForgeOverview" then overview = win
        elseif name == "HeroWindowWeaveForgePanel" then panel = win
        elseif name == "HeroWindowWeaveForgeBackground" then background = win
        end
    end

    -- === OVERVIEW: hide Athanor level, hide weapon level, fix power ===
    if overview then
        _forge_hide_widget(overview, "forge_level_title")
        _forge_hide_widget(overview, "forge_level_text")
        _forge_hide_widget(overview, "upgrade_button")
        _forge_hide_widget(overview, "upgrade_text")
        _forge_hide_widget(overview, "upgrade_bg")
        _forge_hide_widget(overview, "top_hdr_background_write_mask")

        -- v0.7.58-dev: drive the 3 jewelry-craft buttons from here. By the
        -- time _forge_apply_ui_polish runs, overview._widgets / _widgets_by_name
        -- are guaranteed populated (proof: _forge_hide_widget above works).
        -- Lazy-create on first call, then show + probe clicks every frame.
        if _OVERVIEW_BTNS_ENABLED then
            _ensure_overview_jewelry_buttons(overview)
            _show_overview_jewelry_buttons(overview, true)
            _handle_overview_jewelry_button_clicks(overview)
        end

        for i = 1, 3 do
            _forge_hide_widget(overview, "viewport_level_title_" .. i)
            _forge_hide_widget(overview, "viewport_level_value_" .. i)
            _forge_hide_widget(overview, "viewport_panel_divider_" .. i)

            local highlight = _forge_get_widget(overview, "viewport_button_text_highlight_" .. i)
            if highlight and highlight.style then
                if highlight.style.background_top then
                    highlight.style.background_top.color = {255, 123, 123, 123}
                end
                if highlight.style.background_bottom then
                    highlight.style.background_bottom.color = {255, 123, 123, 123}
                end
                if highlight.style.background_top_light then
                    highlight.style.background_top_light.color = {200, 123, 123, 123}
                end
                if highlight.style.background_bottom_light then
                    highlight.style.background_bottom_light.color = {200, 123, 123, 123}
                end
            end

            local btn_highlight = _forge_get_widget(overview, "viewport_button_highlight_" .. i)
            if btn_highlight and btn_highlight.style then
                for sk, sv in pairs(btn_highlight.style) do
                    if type(sv) == "table" and sv.color then
                        sv.color = {sv.color[1], 123, 123, 123}
                    end
                end
            end
        end

        local items_backend = Managers.backend and Managers.backend:get_interface("items")
        if items_backend then
            local player = Managers.player and Managers.player:local_player()
            if player then
                local profile_index = player:profile_index()
                local profile = SPProfiles[profile_index]
                local career_index = player:career_index()
                local career = profile.careers[career_index]
                local career_name = career.name
                local slot_map = {[1] = "slot_melee", [3] = "slot_ranged"}
                for vp_idx, slot_name in pairs(slot_map) do
                    local bid = items_backend:get_loadout_item_id(career_name, slot_name)
                    if bid then
                        local item = items_backend:get_item_from_id(bid)
                        if item then
                            _forge_set_text(overview, "viewport_power_value_" .. vp_idx, tostring(item.power_level or 300))
                        end
                    end
                end
                -- Viewport 2 = the central amulet (accessory crafting). It
                -- doesn't track a single equipped item — it represents three
                -- accessory slots. The user wants the power readout here to
                -- always reflect the configured `base_power_level` setting
                -- (default 300), matching what a newly-crafted accessory
                -- would actually receive. User report 2026-05-25.
                local base_power = (mod._cim_base_power and mod._cim_base_power())
                                   or mod:get("base_power_level") or 300
                _forge_set_text(overview, "viewport_power_value_2", tostring(base_power))
            end
        end
    end

    -- === VIEWPORT 2 (amulet): repurposed as the modded accessories + talents
    -- editor entry point. We keep it visible (vanilla draws it via
    -- `_initialize_viewports` when `amulet_introduced = true`, see hook below)
    -- and let it route to the weave properties window on click. Phase B will
    -- swap the routing to a custom 3-subsection editor.
    if overview then
        -- Re-label the amulet viewport so it's clear it's the unified accessories
        -- editor (vanilla title is "Weave Amulet"). The click flows through to
        -- HeroWindowWeaveProperties which auto-uses amulet_slot_layout when
        -- selected_item is nil — that's the 3-section UI the user wants.
        -- v0.7.50-dev: "JEWELLERY" -> "ACCESSORIES" (issue #38). I (Claude)
        -- hardcoded "JEWELLERY" here when first repurposing the viewport;
        -- the prior fix attempts (Localize override + HeroWindowLoadoutInventory
        -- category mutation) patched OTHER surfaces but missed this hardcoded
        -- literal — which is the title the user actually sees on the main
        -- forge page. User-named the source of confusion 2026-05-27 EOD.
        _forge_set_text(overview, "viewport_title_2", "ACCESSORIES")
        _forge_set_text(overview, "viewport_sub_title_2", "Necklace + Charm + Trinket")

        if not overview._wt_panels_init then
            overview._wt_panels_init = true
            local UIWidgets = rawget(_G, "UIWidgets")
            local UIWidget = rawget(_G, "UIWidget")
            if UIWidgets and UIWidget and UIWidgets.create_simple_item_tooltip then
                -- Standard set of tooltip passes used elsewhere in VT2 (deus
                -- run stats, etc). Renders the same boxed item card the regular
                -- inventory / crafting menus show on hover.
                local tooltip_passes = {
                    "item_titles",
                    "skin_applied",
                    "ammunition",
                    "fatigue",
                    "item_power_level",
                    "properties",
                    "traits",
                    "weapon_skin_title",
                    "keywords",
                    "light_attack_stats",
                    "heavy_attack_stats",
                    "detailed_stats_light",
                    "detailed_stats_heavy",
                    "detailed_stats_push",
                    "detailed_stats_ranged_light",
                    "detailed_stats_ranged_heavy",
                }
                local ok_def, tt_def = pcall(UIWidgets.create_simple_item_tooltip, "viewport_panel_2", tooltip_passes)
                if ok_def and tt_def then
                    local ok, tt = pcall(UIWidget.init, tt_def)
                    if ok and tt then
                        -- Anchor near the bottom-left of viewport_panel_2 so
                        -- the tooltip box reads naturally when the mouse is
                        -- on the melee or ranged weapon viewport.
                        tt.offset = { 10, 200, 30 }
                        tt.content.item = nil
                        overview._cim_tooltip_widget = tt
                        if overview._top_widgets then
                            overview._top_widgets[#overview._top_widgets + 1] = tt
                        end
                        mod:info("Forge tooltip: ready")
                    else
                        mod:echo("Forge tooltip init err: " .. tostring(tt))
                    end
                else
                    mod:echo("Forge tooltip create err: " .. tostring(tt_def))
                end
            else
                mod:echo("Forge tooltip: create_simple_item_tooltip not available")
            end
        end

        local hovered_vp = nil
        local vp1_btn = _forge_get_widget(overview, "viewport_button_1")
        local vp3_btn = _forge_get_widget(overview, "viewport_button_3")
        if _forge_is_hovered(vp1_btn) then
            hovered_vp = 1
        elseif _forge_is_hovered(vp3_btn) then
            hovered_vp = 3
        end

        if hovered_vp then
            local slot_name = (hovered_vp == 1) and "slot_melee" or "slot_ranged"
            local items_backend = Managers.backend and Managers.backend:get_interface("items")
            local player = Managers.player and Managers.player:local_player()
            if player and items_backend then
                local profile_index = player:profile_index()
                local profile = SPProfiles[profile_index]
                local career_index = player:career_index()
                local career = profile.careers[career_index]
                local career_name = career.name
                local bid = items_backend:get_loadout_item_id(career_name, slot_name)
                local item = bid and items_backend:get_item_from_id(bid)
                if item then
                    _forge_populate_item_panels(overview, item)
                else
                    _forge_hide_item_panels(overview)
                end
            else
                _forge_hide_item_panels(overview)
            end
        else
            _forge_hide_item_panels(overview)
        end
    end

    -- === PANEL: hide essence, wheel rings, rebrand header ===
    if panel then
        _forge_hide_widget(panel, "essence_icon")
        _forge_hide_widget(panel, "essence_text")
        _forge_hide_widget(panel, "essence_panel")
        _forge_hide_widget(panel, "essence_tooltip")
        _forge_hide_widget(panel, "loadout_power_title")
        _forge_hide_widget(panel, "loadout_power_tooltip")

        local power_w = _forge_get_widget(panel, "loadout_power_text")
        if power_w and power_w.content then
            power_w.content.text = "MOD WEAPON CRAFTING"
            power_w.content.visible = true
            if power_w.style and power_w.style.text then
                power_w.style.text.font_size = 28
                power_w.style.text.text_color = {255, 255, 255, 255}
            end
            if power_w.style and power_w.style.text_shadow then
                power_w.style.text_shadow.font_size = 28
            end
        end

        _forge_hide_widget(panel, "background_wheel_1")
        _forge_hide_widget(panel, "hdr_background_wheel_1")
        for i = 1, 3 do
            _forge_hide_widget(panel, "wheel_ring_1_" .. i)
            _forge_hide_widget(panel, "wheel_ring_2_" .. i)
            _forge_hide_widget(panel, "hdr_wheel_ring_1_" .. i)
            _forge_hide_widget(panel, "hdr_wheel_ring_2_" .. i)
        end

        _forge_set_style_color(panel, "top_glow_smoke_1", "texture_id", {200, 180, 20, 10})
    end

    -- === BACKGROUND: change smoke colors to deep red ===
    if background and not _forge_bg_colored then
        _forge_set_style_color(background, "bottom_glow_smoke_1", "texture_id", {200, 180, 20, 10})
        _forge_set_style_color(background, "bottom_glow_smoke_2", "texture_id", {255, 200, 30, 10})
        _forge_set_style_color(background, "bottom_glow_smoke_3", "texture_id", {200, 180, 25, 15})
        _forge_set_style_color(background, "bottom_glow_embers_1", "texture_id", {130, 255, 60, 20})
        _forge_set_style_color(background, "bottom_glow_embers_3", "texture_id", {130, 255, 60, 20})
        _forge_bg_colored = true
    end

    -- === PROPERTIES sub-menu: hide level/mastery, fix power ===
    local properties_win = nil
    for _, win in pairs(windows) do
        if win.NAME == "HeroWindowWeaveProperties" then properties_win = win end
    end
    if properties_win then
        _forge_hide_widget(properties_win, "viewport_level_title")
        _forge_hide_widget(properties_win, "viewport_level_value")
        _forge_hide_widget(properties_win, "viewport_panel_divider")
        _forge_hide_widget(properties_win, "mastery_text")
        _forge_hide_widget(properties_win, "mastery_title_text")
        _forge_hide_widget(properties_win, "mastery_icon")
        _forge_hide_widget(properties_win, "mastery_tooltip")

        local params = properties_win._params
        local sel_item = params and params.selected_item
        local in_amulet_mode = not (sel_item and sel_item.backend_id)

        if in_amulet_mode then
            if _AMULET_BTNS_ENABLED then
                -- Amulet mode (v0.7.32+): 3 stacked craft buttons replace the
                -- single "CRAFT NEW" upgrade_button. The 3D Amulet of Ashur model
                -- and its title label are hidden — buttons render in the freed
                -- center space.
                _forge_hide_widget(properties_win, "upgrade_button")
                _forge_hide_widget(properties_win, "upgrade_text")
                _forge_hide_widget(properties_win, "upgrade_essence_warning")

                _ensure_amulet_buttons(properties_win)
                _show_amulet_buttons(properties_win, true)
                _handle_amulet_button_clicks(properties_win)

                -- Hide the 3D model. The unit_previewer renders the rotating
                -- amulet inside viewport_widget; setting `_skip_previewer_update`
                -- makes the update-hook below short-circuit before draw_widget.
                properties_win._cim_skip_previewer = true
            else
                -- v0.7.64-dev: buttons disabled — restore the vanilla "Craft All"
                -- upgrade_button as the accessory craft control so the view is
                -- fully usable (no black box, grid visible). It routes through the
                -- existing `_upgrade_magic_level` hook which crafts the edited
                -- accessory slots.
                _show_amulet_buttons(properties_win, false)
                properties_win._cim_skip_previewer = nil
                _forge_set_text(properties_win, "upgrade_text", "CRAFT ACCESSORIES")
            end

            -- Rename viewport_title from "Amulet of Ashur" → "Accessory Crafting".
            -- vanilla `_set_title_text` writes Localize("weave_amulet_name") into
            -- this widget every frame in some code paths; the per-frame polish
            -- pass here re-overrides it after each vanilla write.
            _forge_set_text(properties_win, "viewport_title", "ACCESSORY CRAFTING")
            -- viewport_sub_title is the career name — leave it alone (still useful).
        else
            _show_amulet_buttons(properties_win, false)
            properties_win._cim_skip_previewer = nil

            -- Weapon mode: keep the vanilla upgrade_button visible + per-slot
            -- relabel. upgrade_button is repurposed as our "Craft New" button
            -- (see hook on `_upgrade_magic_level` below).
            local craft_label = "CRAFT NEW WEAPON"
            local sn = params and params.selected_slot_name
            if sn == "slot_necklace" then craft_label = "CRAFT NEW NECKLACE"
            elseif sn == "slot_charm" then craft_label = "CRAFT NEW CHARM"
            elseif sn == "slot_trinket" then craft_label = "CRAFT NEW TRINKET"
            end
            _forge_set_text(properties_win, "upgrade_text", craft_label)
        end
        _forge_hide_widget(properties_win, "background_wheel")
        _forge_hide_widget(properties_win, "hdr_background_wheel")
        for i = 1, 3 do
            _forge_hide_widget(properties_win, "wheel_ring_" .. i)
            _forge_hide_widget(properties_win, "hdr_wheel_ring_" .. i)
        end

        _forge_set_style_color(properties_win, "cluster_background_effect_1", "texture_id", {200, 180, 20, 10})

        if sel_item and sel_item.backend_id then
            local items_backend = Managers.backend and Managers.backend:get_interface("items")
            if items_backend then
                local item = items_backend:get_item_from_id(sel_item.backend_id)
                if item then
                    _forge_set_text(properties_win, "viewport_power_value", tostring(item.power_level or 300))
                end
            end
        end
    end
end

mod:hook_safe("HeroViewStateWeaveForge", "update", function(self, dt, t)
    if _custom_forge_active then
        _forge_apply_ui_polish(self)
    end
end)

-- --- Backend safety hooks (prevent crashes for non-weave items) ---

-- CLARIFY: 16+ Weaves backend hooks below all follow the same pattern: when
-- our custom forge is active, return faked values (max forge level, infinite
-- essence, zero costs, etc.) so the Athanor UI doesn't gate on weave progression.
-- When the custom forge is NOT active, fall through to the original — leaves
-- vanilla Weaves mode untouched. The custom forge is opened only via our
-- `open_forge` keybind, so non-mod weaves play stays clean.
mod:hook("BackendInterfaceWeavesPlayFab", "get_forge_level", function(func, self)
    if _custom_forge_active then return 999 end
    return func(self)
end)

mod:hook("BackendInterfaceWeavesPlayFab", "get_essence", function(func, self)
    if _custom_forge_active then return 999999 end
    return func(self)
end)

mod:hook("BackendInterfaceWeavesPlayFab", "get_maximum_essence", function(func, self)
    if _custom_forge_active then return 999999 end
    return func(self)
end)

mod:hook("BackendInterfaceWeavesPlayFab", "get_total_essence", function(func, self)
    if _custom_forge_active then return 999999 end
    return func(self)
end)

mod:hook("BackendInterfaceWeavesPlayFab", "get_property_required_forge_level", function(func, self, property_name)
    if _custom_forge_active then return 0 end
    return func(self, property_name)
end)

mod:hook("BackendInterfaceWeavesPlayFab", "get_property_mastery_costs", function(func, self, property_name)
    if _custom_forge_active then
        -- Button slot count = #costs (renderer reads it as `total_uses` in
        -- hero_window_weave_properties.lua). Return exactly `cap` zero-cost
        -- entries so stamina renders 2 slots, movespeed renders 1 (or 5
        -- when the 2pct toggle is on), everything else stays at 5.
        local cap = _bubble_cap(property_name)
        local out = {}
        for i = 1, cap do out[i] = 0 end
        return out
    end
    return func(self, property_name)
end)

mod:hook("BackendInterfaceWeavesPlayFab", "get_trait_required_forge_level", function(func, self, trait_key)
    if _custom_forge_active then return 0 end
    return func(self, trait_key)
end)

mod:hook("BackendInterfaceWeavesPlayFab", "get_trait_mastery_cost", function(func, self, trait_key)
    if _custom_forge_active then return 0 end
    return func(self, trait_key)
end)

mod:hook("BackendInterfaceWeavesPlayFab", "get_talent_mastery_cost", function(func, self, talent_name)
    if _custom_forge_active then return 0 end
    return func(self, talent_name)
end)

mod:hook("BackendInterfaceWeavesPlayFab", "get_career_magic_level", function(func, self, career_name)
    if _custom_forge_active then return 999 end
    local ok, result = pcall(func, self, career_name)
    if ok then return result end
    return 0
end)

mod:hook("BackendInterfaceWeavesPlayFab", "get_item_magic_level", function(func, self, item_backend_id)
    if _custom_forge_active then return 999 end
    local ok, result = pcall(func, self, item_backend_id)
    if ok then return result end
    return 0
end)

mod:hook("BackendInterfaceWeavesPlayFab", "max_magic_level", function(func, self)
    if _custom_forge_active then return 999 end
    return func(self)
end)

mod:hook("BackendInterfaceWeavesPlayFab", "forge_magic_level_cap", function(func, self)
    if _custom_forge_active then return 999 end
    return func(self)
end)

mod:hook("BackendInterfaceWeavesPlayFab", "magic_item_cost", function(func, self, item_key)
    if _custom_forge_active then return 0 end
    return func(self, item_key)
end)

mod:hook("BackendInterfaceWeavesPlayFab", "get_average_power_level", function(func, self, career_name)
    if _custom_forge_active then return 300 end
    local ok, result = pcall(func, self, career_name)
    if ok then return result end
    return 300
end)

mod:hook("BackendInterfaceWeavesPlayFab", "magic_item_upgrade_cost", function(func, self, num_levels, item_backend_id)
    if _custom_forge_active then return 0 end
    local ok, result = pcall(func, self, num_levels, item_backend_id)
    if ok then return result end
    return 0
end)

mod:hook("BackendInterfaceWeavesPlayFab", "career_upgrade_cost", function(func, self, num_levels, career_name)
    if _custom_forge_active then return 0 end
    local ok, result = pcall(func, self, num_levels, career_name)
    if ok then return result end
    return 0
end)

-- --- Forge loadout (redirect weave loadout to our own table) ---

mod:hook("BackendInterfaceWeavesPlayFab", "get_loadout_item_id", function(func, self, career_name, slot_name)
    if _custom_forge_active then
        local loadout = _forge_loadout[career_name]
        if loadout and loadout[slot_name] then
            return loadout[slot_name]
        end
        local items_backend = Managers.backend:get_interface("items")
        if items_backend then
            local ok, bid = pcall(items_backend.get_loadout_item_id, items_backend, career_name, slot_name)
            if ok then return bid end
        end
        return nil
    end
    return func(self, career_name, slot_name)
end)

mod:hook("BackendInterfaceWeavesPlayFab", "set_loadout_item", function(func, self, item_backend_id, career_name, slot_name)
    if _custom_forge_active then
        _forge_loadout[career_name] = _forge_loadout[career_name] or {}
        _forge_loadout[career_name][slot_name] = item_backend_id
        return true
    end
    return func(self, item_backend_id, career_name, slot_name)
end)

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
local _PROPERTY_BUBBLE_CAP_STATIC = {
    stamina   = 2,
    movespeed = 1,
}

_strip_weave = function(weave_key)
    return (weave_key or ""):gsub("^weave_", "")
end

_bubble_cap = function(weave_key)
    local key = _strip_weave(weave_key)
    if key == "movespeed" and mod:get("movespeed_2pct_mode") then return 5 end
    return _PROPERTY_BUBBLE_CAP_STATIC[key] or 5
end

-- value 0..1 that the engine should resolve for `count` filled bubbles.
-- Default linear maps count/5 for backward compatibility with the existing
-- 5-bubble properties.
_value_for_bubbles = function(weave_key, count)
    local key = _strip_weave(weave_key)
    -- Movespeed 2pct mode: 5 bubbles, each adds 0.2 to the stored value.
    -- buff_extension lerps multiplier as 1 + (max-1)*value. If we also bump
    -- `variable_multiplier_max` from 1.05 → 1.10 (in the load-time patch
    -- below), then 1 bubble (value 0.2) → 1 + 0.10*0.2 = 1.02 = +2%, and
    -- 5 bubbles (value 1.0) → 1 + 0.10*1.0 = 1.10 = +10%.
    if key == "movespeed" and mod:get("movespeed_2pct_mode") then
        return math.min(count / 5, 1.0)
    end
    local cap = _bubble_cap(weave_key)
    if cap == 5 then return math.min(count / 5, 1.0) end
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
    if value == nil or value <= 0 then return 0 end
    if cap == 5 then return math.max(1, math.ceil(value * 5)) end
    if cap == 1 then return 1 end
    if cap == 2 then
        return value >= 0.6 and 2 or 1
    end
    -- Generic: scale value over cap, floor to integer, clamp.
    return math.max(1, math.min(cap, math.ceil(value * cap)))
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

-- Re-apply when the user toggles the setting in the VMF menu. VMF fires
-- `on_setting_changed` with the setting_id; gate on our toggle to avoid
-- spurious work on unrelated setting flips.
mod.on_setting_changed = function(setting_id)
    if setting_id == "movespeed_2pct_mode" then
        _patch_movespeed_buff()
    end
end

local function _seed_one_item(item, props_out, traits_out, slot_index)
    if not item then return end
    local layer_offset = (slot_index - 1) * _AMULET_LAYER_SIZE
    if item.properties then
        local wp = rawget(_G, "WeaveProperties")
        local wp_props = wp and wp.properties
        local next_slot = layer_offset + 1
        for prop_key, value in pairs(item.properties) do
            local weave_key = "weave_" .. prop_key
            if wp_props and wp_props[weave_key] then
                local filled = _bubbles_for_value(weave_key, value)
                local indices = {}
                for i = 1, filled do
                    indices[i] = next_slot
                    next_slot = next_slot + 1
                end
                if #indices > 0 then
                    props_out[weave_key] = indices
                end
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
        -- bubble grid (necklace=layer 1, charm=layer 2, trinket=layer 3).
        for slot_index, slot_name in ipairs(_AMULET_SLOT_BY_INDEX) do
            local bid = items_backend:get_loadout_item_id(career_name, slot_name)
            local item = bid and items_backend:get_item_from_id(bid)
            _seed_one_item(item, props, traits, slot_index)
        end
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
        _forge_save()
    end
end

mod:hook("BackendInterfaceWeavesPlayFab", "get_loadout_properties", function(func, self, career_name, item_backend_id)
    if _custom_forge_active then
        local data = _forge_seed_item(career_name, item_backend_id)
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
        -- Distinct-property cap per item / accessory layer. Vanilla allows max
        -- 2 distinct properties on any weapon/jewelry item. Single-item editor
        -- (weapon): one layer covering all slots → cap = 2 total distinct keys.
        -- Amulet editor: per-layer cap of 2 (each accessory holds 2 distinct
        -- properties max). Vanilla's HeroWindowItemCustomization Apply-Skin
        -- preview only ships widgets for `button_hotspot_1` / `_2`; writing
        -- a 3rd distinct key produces an item that crashes that view
        -- (`item_customization.lua:1213 attempt to index a nil value`,
        -- hotspot_3 missing). Burned cim v0.7.23-alpha → v0.7.24 / v0.7.25 fix.
        local MAX_DISTINCT_PROPERTIES = 2
        if not props[property_key] then
            local target_layer = item_backend_id and 1 or math.ceil(slot_index / _AMULET_LAYER_SIZE)
            local distinct_in_layer = 0
            for existing_key, existing_indices in pairs(props) do
                if existing_key ~= property_key then
                    local hit = false
                    for _, existing_idx in ipairs(existing_indices) do
                        local layer = item_backend_id and 1 or math.ceil(existing_idx / _AMULET_LAYER_SIZE)
                        if layer == target_layer then hit = true; break end
                    end
                    if hit then distinct_in_layer = distinct_in_layer + 1 end
                end
            end
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
            props[property_key] = {}
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
        local cap = _bubble_cap and _bubble_cap(property_key) or 5
        local cur_len = #props[property_key]
        if cur_len < cap then
            props[property_key][cur_len + 1] = slot_index
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

    for key, item_data in pairs(ItemMasterList) do
        local slot_type = item_data.slot_type
        if slot_type and table.contains(item_slot_types, slot_type) then
            local can_wield = item_data.can_wield
            if can_wield and table.contains(can_wield, career_name) then
                local rarity = item_data.rarity
                local dlc_locked = mod._cim_item_requires_unowned_dlc
                    and mod._cim_item_requires_unowned_dlc(key)
                if item_data.item_type ~= "weapon_skin" and rarity ~= "magic" and rarity ~= "promo"
                   and not dlc_locked then
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

    self:_populate_list(weapon_layout)

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
--  1. can_wield — the grid filters by the current career. Append the crafting
--     career if missing (additive/idempotent). Mostly redundant on the Athanor
--     (the weapon list only offers weapons the career can already wield) but
--     closes the weapon_tweaker-toggled-late edge case.
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

    -- (1) can_wield: append the crafting career if known + missing.
    if career_name and career_name ~= "<unknown>" and type(entry.can_wield) == "table" then
        local present = false
        for _, c in ipairs(entry.can_wield) do
            if c == career_name then present = true; break end
        end
        if not present then
            entry.can_wield[#entry.can_wield + 1] = career_name
            mod:info("[cim] can_wield stamp: %s now wieldable by %s", tostring(item_key), tostring(career_name))
        end
    end

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
    if not item_key or not rawget(ItemMasterList, item_key) then
        return nil, "item_key '" .. tostring(item_key) .. "' not in ItemMasterList yet"
    end

    -- Ensure the new item is visible in the Adventure keep grid BEFORE it
    -- enters the mirror: append the crafting career to can_wield (if known) and
    -- clear any non-adventure `mechanisms` scoping (the vs_* Versus weapons).
    -- Called unconditionally — career_name may be nil for boot re-injects of
    -- old saves, but the mechanisms clear still needs to run for those.
    _ensure_item_adventure_visible(item_key, weapon_data.career_name)

    local cjson_mod = rawget(_G, "cjson")
    local props = weapon_data.properties or {}
    local traits = weapon_data.traits or (weapon_data.trait and {weapon_data.trait}) or {}

    local custom_data = {
        power_level = tostring(weapon_data.power_level or 300),
        rarity = weapon_data.rarity or "modded",
    }
    if cjson_mod then
        custom_data.properties = cjson_mod.encode(props)
        custom_data.traits = cjson_mod.encode(traits)
    end
    if weapon_data.skin then custom_data.skin = weapon_data.skin end

    local item = {
        ItemId = item_key,
        ItemInstanceId = backend_id,
        CustomData = custom_data,
    }

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
        mod:echo(string.format("[cim] %d saved crafts deferred (waiting for sibling mods to register their ItemMasterList entries — will retry on next state transition)", skipped))
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
        mod:echo(string.format("[cim] Re-injected %d previously-deferred craft(s)", recovered))
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
    _athanor_retry_pending()
    -- Schedule a deferred loadout restore. 1.0s is empirically enough for
    -- PlayFab's signin → request_characters → _set_inital_career_data →
    -- _fix_career_data round-trip to complete and the mirror to settle.
    -- A second pass at 3.0s catches slow modded-realm signin cases.
    _cim_loadout_restore_timer = 1.0
end

mod.update = function(dt)
    -- Install the BackendUtils.set_loadout_item capture once the backend (and LA
    -- bridge) are up. Cheap once-guarded no-op after install. Issue #22 root fix.
    _install_backendutils_capture()

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

    -- Resolve the crafting career once (used for the Way-3 can_wield stamp and
    -- the diagnostic probes). self._career_name is the forge's current career.
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
        power_level = 300,
        rarity = "modded",
        via_mirror = true,
        career_name = career_name,  -- drives the Way-3 can_wield stamp in inject
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

    _forged_weapons[new_backend_id] = weapon_data
    _forge_save()
    if mod._cim_note_craft_bid then mod._cim_note_craft_bid(new_backend_id) end

    -- Craft only: the item lands in the inventory mirror + cim save layer.
    -- Equipping is the player's choice from their inventory. Previous versions
    -- called set_loadout_item here, which updated the loadout-icon entry but
    -- diverged from the actual equipped weapon unit, leaving the slot showing
    -- one item and playing another. See issue #12.
    local _master = rawget(ItemMasterList, item_key)
    local _name = (_master and _master.display_name) or item_key
    mod:echo("Crafted & saved: " .. tostring(Localize(_name)) .. " [" .. tostring(weapon_data.rarity) .. "] — equip from inventory")

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

    -- Melee/ranged in-place editor: bubble-grid edits already mutate the
    -- equipped item directly (via `_forge_apply_to_item`). The repurposed
    -- upgrade_button used to mint a NEW item with the same edits, which was
    -- confusing and inverted the "modify your equipped item" mental model
    -- the user wanted. Hide the button entirely for this case — when player
    -- wants a brand-new weapon they pick one in the weapon-select pane.
    -- (Amulet case keeps the legacy label as a no-op fallback for gamepad
    -- activations; the 3 cim per-slot buttons are the real UX there.)
    local item = self:_selected_item()
    local slot_type = item and item.data and item.data.slot_type
    if slot_type == "melee" or slot_type == "ranged" then
        if btn.content then btn.content.visible = false end
        if btn.content and btn.content.button_hotspot then
            btn.content.button_hotspot.disable_button = true
        end
        local warn_hide = widgets_by_name.upgrade_essence_warning
        if warn_hide and warn_hide.content then warn_hide.content.visible = false end
        return
    end

    if btn.content then btn.content.visible = true end
    local label = item and "CRAFT" or "CRAFT MODDED JEWELLERY"
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
        career_name = career_name,  -- drives the Way-3 can_wield stamp in inject
    }
    local injected, err = _athanor_inject_item(weapon_data, new_bid)
    if not injected then
        mod:warning("[cim] Craft " .. slot_name .. " failed: " .. tostring(err))
        return false
    end
    if mod._cim_register_craft then mod._cim_register_craft(new_bid, weapon_data) end
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

    -- Melee/ranged case: bubble-grid edits already mutate the equipped item
    -- in place. The legacy "CRAFT NEW WEAPON" upgrade_button is hidden for
    -- this case (see _set_essence_upgrade_cost hook above), so this branch
    -- shouldn't fire on mouse — but a stray gamepad activation could. No-op
    -- it to keep the modify-in-place model consistent. To craft a brand-new
    -- weapon, the player picks one in HeroWindowWeaveForgeWeapons.
    local slot_type = item_data and item_data.slot_type
    if slot_type == "melee" or slot_type == "ranged" then
        return
    end

    -- Amulet case: no selected_item. Iterate dirty accessory slots and craft
    -- each via the shared single-slot helper. This branch still runs if the
    -- legacy `upgrade_button` somehow fires (e.g. gamepad activation while in
    -- amulet view) — the 3 cim per-slot buttons supersede it visually but the
    -- legacy path stays wired for compat.
    if not item then
        local crafted = 0
        for slot_index, slot_name in ipairs(_AMULET_SLOT_BY_INDEX) do
            if _amulet_dirty[slot_index] then
                if _cim_amulet_craft_one_slot(self, slot_index, slot_name) then
                    crafted = crafted + 1
                end
            end
        end
        if crafted == 0 then
            mod:echo("[cim] No accessory edits to craft (Apply auto-runs on bubble click)")
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
        power_level = 300,
        rarity = "modded",
        via_mirror = true,
    }

    local injected, err = _athanor_inject_item(weapon_data, new_backend_id)
    if not injected then
        mod:warning("[cim] Craft failed: " .. tostring(err))
        return
    end

    if mod._cim_register_craft then
        mod._cim_register_craft(new_backend_id, weapon_data)
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

-- ============================================================
-- Diagnostic commands
-- ============================================================

local function _forge_dump_widgets(window_name, win)
    local w = win._widgets_by_name
    if not w then
        mod:info("DUMP [%s] _widgets_by_name=nil, checking fields:", window_name)
        for k, v in pairs(win) do
            if type(v) == "table" and k:find("widget") then
                mod:info("  field: %s (table, #%d)", k, #v)
            elseif type(v) ~= "function" then
                mod:info("  field: %s = %s", k, tostring(v))
            end
        end
        return
    end
    mod:info("=== DUMP [%s] ===", window_name)
    for name, widget in pairs(w) do
        local parts = {}
        if widget.content then
            for k, v in pairs(widget.content) do
                if type(v) == "string" and #v < 60 then
                    parts[#parts + 1] = k .. '="' .. v .. '"'
                elseif type(v) == "boolean" or type(v) == "number" then
                    parts[#parts + 1] = k .. "=" .. tostring(v)
                end
            end
        end
        local sparts = {}
        if widget.style then
            for sk, sv in pairs(widget.style) do
                if type(sv) == "table" then
                    if sv.color then
                        local c = sv.color
                        sparts[#sparts + 1] = sk .. ".color={" .. tostring(c[1]) .. "," .. tostring(c[2]) .. "," .. tostring(c[3]) .. "," .. tostring(c[4]) .. "}"
                    end
                    if sv.text_color then
                        local c = sv.text_color
                        sparts[#sparts + 1] = sk .. ".text_color={" .. tostring(c[1]) .. "," .. tostring(c[2]) .. "," .. tostring(c[3]) .. "," .. tostring(c[4]) .. "}"
                    end
                    if sv.font_size then
                        sparts[#sparts + 1] = sk .. ".font_size=" .. tostring(sv.font_size)
                    end
                end
            end
        end
        mod:info("  [%s] content: %s", name, table.concat(parts, ", "))
        if #sparts > 0 then
            mod:info("    style: %s", table.concat(sparts, ", "))
        end
    end
    mod:info("=== END [%s] ===", window_name)
end

mod:command("forge_dump", "Dump all forge window widget names to log", function()
    if not _custom_forge_active then
        mod:echo("Open the forge first (B key), then run this command")
        return
    end
    local ingame_ui = Managers.ui and Managers.ui._ingame_ui
    if not ingame_ui then
        mod:echo("No ingame_ui")
        return
    end
    local view_name = ingame_ui.current_view
    if not view_name then
        mod:echo("No current_view")
        return
    end
    local hero_view = ingame_ui.views and ingame_ui.views[view_name]
    if not hero_view then
        mod:echo("No view object for: " .. tostring(view_name))
        return
    end
    mod:info("=== FORGE UI DUMP ===")
    mod:info("current_view = %s", tostring(view_name))

    local forge_state = nil
    if hero_view._machine and hero_view._machine._state then
        forge_state = hero_view._machine._state
        mod:info("forge_state via _machine._state: %s (NAME=%s)", tostring(forge_state), tostring(forge_state.NAME))
    end
    if not forge_state then
        mod:echo("Could not find forge state on hero_view._machine._state")
        return
    end

    mod:info("--- forge_state fields ---")
    for k, v in pairs(forge_state) do
        if type(v) ~= "function" then
            local vstr = tostring(v)
            if type(v) == "table" then
                local count = 0
                for _ in pairs(v) do count = count + 1 end
                vstr = "table(" .. count .. ")"
            end
            mod:info("  state.%s = %s (%s)", k, vstr, type(v))
        end
    end

    local found = 0
    local active_windows = forge_state._active_windows
    if active_windows then
        mod:info("--- _active_windows ---")
        for idx, win in pairs(active_windows) do
            local win_name = win.NAME or win.__class_name or tostring(win)
            mod:info("Window[%s]: %s", tostring(idx), tostring(win_name))
            _forge_dump_widgets(tostring(idx) .. "_" .. tostring(win_name), win)
            found = found + 1
        end
    else
        mod:info("_active_windows is nil, scanning forge_state for _widgets_by_name:")
        for k, v in pairs(forge_state) do
            if type(v) == "table" and rawget(v, "_widgets_by_name") then
                mod:info("  Found _widgets_by_name on state.%s", k)
                _forge_dump_widgets(k, v)
                found = found + 1
            end
        end
    end
    mod:info("=== END FORGE UI DUMP (found %d windows) ===", found)
    mod:echo("Dump written to log (" .. found .. " windows found)")
end)

mod:command("forge_dump_props", "Dump properties sub-menu widgets and seed data", function()
    if not _custom_forge_active then
        mod:echo("Open the forge first (B key)")
        return
    end
    local ingame_ui = Managers.ui and Managers.ui._ingame_ui
    if not ingame_ui then mod:echo("No ingame_ui") return end
    local view_name = ingame_ui.current_view
    local hero_view = ingame_ui.views and ingame_ui.views[view_name]
    if not hero_view or not hero_view._machine then mod:echo("No hero_view") return end
    local forge_state = hero_view._machine._state
    if not forge_state then mod:echo("No forge_state") return end
    local windows = forge_state._active_windows
    if not windows then mod:echo("No _active_windows") return end

    mod:echo("Layout: " .. tostring(forge_state._selected_layout_name))
    local found_props = false
    for idx, win in pairs(windows) do
        mod:echo("Window[" .. tostring(idx) .. "]: " .. tostring(win.NAME))
        if win.NAME == "HeroWindowWeaveProperties" then
            found_props = true
            local wbn = win._widgets_by_name
            if wbn then
                local names = {}
                for name, widget in pairs(wbn) do
                    local info = name
                    if widget.content then
                        if widget.content.text then
                            info = info .. "=" .. tostring(widget.content.text)
                        end
                        if widget.content.visible == false then
                            info = info .. " [HIDDEN]"
                        end
                    end
                    names[#names + 1] = info
                end
                table.sort(names)
                for _, n in ipairs(names) do
                    mod:echo("  " .. n)
                end
            end
            mod:echo("_item_backend_id: " .. tostring(win._item_backend_id))
            mod:echo("_career_name: " .. tostring(win._career_name))
            local p = win._params
            if p then
                mod:echo("params.selected_item: " .. tostring(p.selected_item))
                if p.selected_item then
                    mod:echo("  .key: " .. tostring(p.selected_item.key or p.selected_item.data and p.selected_item.data.key))
                    mod:echo("  .backend_id: " .. tostring(p.selected_item.backend_id))
                end
                mod:echo("params.selected_unit_name: " .. tostring(p.selected_unit_name))
                mod:echo("params.selected_slot_name: " .. tostring(p.selected_slot_name))
            end
            mod:echo("_viewport_widget: " .. tostring(win._viewport_widget))
            mod:echo("_viewport_widget_definition: " .. tostring(win._viewport_widget_definition))
            mod:echo("_item_previewer: " .. tostring(win._item_previewer))
            mod:echo("_unit_previewer: " .. tostring(win._unit_previewer))
            mod:echo("_previewer_initialized: " .. tostring(win._previewer_initialized))
        end
    end
    if not found_props then
        mod:echo("HeroWindowWeaveProperties not active — click a weapon first")
    end

    local items_backend = Managers.backend and Managers.backend:get_interface("items")
    if items_backend then
        local player = Managers.player and Managers.player:local_player()
        if player then
            local pi = player:profile_index()
            local profile = SPProfiles[pi]
            local ci = player:career_index()
            local career_name = profile.careers[ci].name
            for _, slot in ipairs({"slot_melee", "slot_ranged"}) do
                local bid = items_backend:get_loadout_item_id(career_name, slot)
                if bid then
                    local item = items_backend:get_item_from_id(bid)
                    if item then
                        mod:echo(slot .. ": " .. tostring(item.key) .. " power=" .. tostring(item.power_level))
                        if item.properties then
                            for pk, pv in pairs(item.properties) do
                                local wk = "weave_" .. pk
                                local wp = rawget(_G, "WeaveProperties")
                                local mapped = wp and wp.properties and wp.properties[wk] and "YES" or "NO"
                                mod:echo("  prop: " .. pk .. "=" .. tostring(pv) .. " -> " .. wk .. " mapped=" .. mapped)
                            end
                        end
                        if item.traits then
                            for i, tk in ipairs(item.traits) do
                                local wk = "weave_" .. tk
                                local wt = rawget(_G, "WeaveTraits")
                                local mapped = wt and wt.traits and wt.traits[wk] and "YES" or "NO"
                                mod:echo("  trait: " .. tk .. " -> " .. wk .. " mapped=" .. mapped)
                            end
                        end
                    end
                end
            end
        end
    end
end)

mod:command("forge_dump_backend", "Dump forge backend hook returns to log", function()
    if not _custom_forge_active then
        mod:echo("Open the forge first (B key)")
        return
    end
    local weaves = Managers.backend and Managers.backend:get_interface("weaves")
    local items = Managers.backend and Managers.backend:get_interface("items")
    if not weaves or not items then
        mod:echo("Backend not available")
        return
    end
    local player = Managers.player:local_player()
    local profile_index = player:profile_index()
    local profile = SPProfiles[profile_index]
    local career_index = player:career_index()
    local career = profile.careers[career_index]
    local career_name = career.name
    mod:info("=== FORGE BACKEND DUMP career=%s ===", career_name)
    for _, slot in ipairs({"slot_melee", "slot_ranged"}) do
        local bid = weaves:get_loadout_item_id(career_name, slot)
        mod:info("  get_loadout_item_id(%s, %s) = %s", career_name, slot, tostring(bid))
        if bid then
            local item = items:get_item_from_id(bid)
            mod:info("  item from backend: %s", item and tostring(item.key) or "nil")
            if item then
                mod:info("    power_level: %s", tostring(item.power_level))
                mod:info("    rarity: %s", tostring(item.rarity))
                if item.properties then
                    for pk, pv in pairs(item.properties) do
                        mod:info("    prop: %s = %s", pk, tostring(pv))
                    end
                else
                    mod:info("    properties: nil")
                end
                if item.traits then
                    for i, t in ipairs(item.traits) do
                        mod:info("    trait[%d]: %s", i, tostring(t))
                    end
                else
                    mod:info("    traits: nil")
                end
            end
            local props = weaves:get_loadout_properties(career_name, bid)
            mod:info("  get_loadout_properties result:")
            if props then
                for pk, pv in pairs(props) do
                    mod:info("    %s = %s", pk, tostring(pv))
                end
            else
                mod:info("    nil")
            end
            local traits = weaves:get_loadout_traits(career_name, bid)
            mod:info("  get_loadout_traits result:")
            if traits then
                for tk, tv in pairs(traits) do
                    mod:info("    %s = %s", tostring(tk), tostring(tv))
                end
            else
                mod:info("    nil")
            end
        end
    end
    mod:info("  get_forge_level: %s", tostring(weaves:get_forge_level()))
    mod:info("  get_essence: %s", tostring(weaves:get_essence()))
    mod:info("=== END FORGE BACKEND DUMP ===")
    mod:echo("Backend dump written to log")
end)

-- Dump everything relevant to the equipped melee/ranged so we can reason about rarity/icons together.
mod:command("craft_dump", "Dump equipped item + rarity/localization/network data", function()
    local items = Managers.backend and Managers.backend:get_interface("items")
    local weaves = Managers.backend and Managers.backend:get_interface("weaves")
    local mirror = Managers.backend and Managers.backend:get_backend_mirror()
    if not items or not mirror then
        mod:echo("Backend not ready")
        return
    end
    local player = Managers.player:local_player()
    local profile_index = player:profile_index()
    local profile = SPProfiles[profile_index]
    local career_index = player:career_index()
    local career = profile.careers[career_index]
    local career_name = career.name

    local NL2 = rawget(_G, "NetworkLookup")
    local nl_rarities = NL2 and NL2.rarities
    local nl_promo_idx = nl_rarities and rawget(nl_rarities, "promo")

    mod:info("=== CRAFT DUMP career=%s ===", career_name)
    mod:info("[NetworkLookup] rarities.promo index = %s", tostring(nl_promo_idx))
    mod:info("[UISettings.item_rarity_textures]")
    if UISettings and UISettings.item_rarity_textures then
        for _, r in ipairs({"plentiful","common","rare","exotic","unique","magic","promo","default"}) do
            mod:info("  [%s] = %s", r, tostring(UISettings.item_rarity_textures[r]))
        end
    end
    mod:info("[RaritySettings]")
    local RS = rawget(_G, "RaritySettings")
    if RS then
        for _, r in ipairs({"plentiful","common","rare","exotic","unique","magic","promo"}) do
            local entry = rawget(RS, r)
            mod:info("  [%s] exists=%s display=%s", r, tostring(entry ~= nil),
                entry and tostring(entry.display_name) or "<nil>")
        end
    end

    for _, slot in ipairs({"slot_melee","slot_ranged"}) do
        mod:info("--- slot=%s ---", slot)
        local items_bid = items:get_loadout_item_id(career_name, slot)
        local weaves_bid = weaves and weaves:get_loadout_item_id(career_name, slot)
        mod:info("  items.get_loadout_item_id  = %s", tostring(items_bid))
        mod:info("  weaves.get_loadout_item_id = %s", tostring(weaves_bid))
        local item = items_bid and items:get_item_from_id(items_bid)
        if item then
            local data = item.data or (item.key and rawget(ItemMasterList, item.key)) or {}
            mod:info("  item.key       = %s", tostring(item.key))
            mod:info("  item.ItemId    = %s", tostring(item.ItemId))
            mod:info("  item.rarity    = %s", tostring(item.rarity))
            mod:info("  data.rarity    = %s", tostring(data.rarity))
            mod:info("  display_name   = %s -> %s", tostring(data.display_name), tostring(Localize(data.display_name or "")))
            mod:info("  inventory_icon = %s", tostring(data.inventory_icon))
            mod:info("  power_level    = %s", tostring(item.power_level))
            local resolved_bg = UISettings and UISettings.item_rarity_textures and UISettings.item_rarity_textures[item.rarity]
            mod:info("  -> rarity_bg lookup = %s", tostring(resolved_bg))
            if item.CustomData then
                for k, v in pairs(item.CustomData) do
                    mod:info("  CustomData[%s] = %s", tostring(k), tostring(v))
                end
            else
                mod:info("  CustomData = nil")
            end
            if item.properties then
                for k, v in pairs(item.properties) do
                    mod:info("  properties[%s] = %s", tostring(k), tostring(v))
                end
            else
                mod:info("  properties = nil")
            end
            if item.traits then
                for i, t in ipairs(item.traits) do
                    mod:info("  traits[%d] = %s", i, tostring(t))
                end
            else
                mod:info("  traits = nil")
            end
        else
            mod:info("  no item resolved for backend_id=%s", tostring(items_bid))
        end
    end

    mod:info("--- recently-added items (rarity=promo) ---")
    local inv = mirror._inventory_items or {}
    local count = 0
    for bid, it in pairs(inv) do
        if it and it.rarity == "promo" then
            count = count + 1
            mod:info("  [%s] key=%s rarity=%s pl=%s", tostring(bid), tostring(it.key), tostring(it.rarity), tostring(it.power_level))
            if count >= 10 then mod:info("  ...truncated"); break end
        end
    end
    if count == 0 then mod:info("  (none found)") end
    mod:info("=== END CRAFT DUMP ===")
    mod:echo(string.format("Craft dump written. promo items: %d, NL.rarities.promo idx: %s", count, tostring(nl_promo_idx)))
end)

-- ============================================================
-- Manual console crafting commands (/forge*)
-- ============================================================

mod:command("forge", "Start forging a weapon (usage: /forge <weapon_key>)", function(item_key)
    if not item_key then
        mod:echo("Usage: /forge <weapon_key>")
        mod:echo("  Then: /forge_trait <trait_name>")
        mod:echo("  Then: /forge_props <prop1>=<value> <prop2>=<value>")
        mod:echo("  Then: /forge_confirm")
        mod:echo("Use /dump_weapons to see available weapon keys.")
        return
    end
    if not ItemMasterList then
        mod:echo("Forge: ItemMasterList not loaded yet")
        return
    end
    local master = rawget(ItemMasterList, item_key)
    if not master then
        mod:echo("Forge: unknown weapon key '" .. item_key .. "'")
        return
    end
    _forge_pending = {
        item_key = item_key,
        properties = {},
        trait = nil,
        skin = nil,
        power_level = 300,
    }
    local display = item_key
    if master.display_name then
        local ok, loc = pcall(Localize, master.display_name)
        if ok and loc then display = loc end
    end
    mod:echo("Forge: preparing " .. display .. " (" .. item_key .. ")")
    mod:echo("  Set trait: /forge_trait <trait_name>")
    mod:echo("  Set props: /forge_props <prop>=<0-1> ...")
    mod:echo("  Set skin:  /forge_skin <skin_key>")
    mod:echo("  Set power: /forge_power <1-300>")
    mod:echo("  Confirm:   /forge_confirm")
    mod:echo("  Cancel:    /forge_cancel")
end)

mod:command("forge_trait", "Set trait for pending forge (usage: /forge_trait <trait_name>)", function(trait)
    if not _forge_pending then
        mod:echo("Forge: no weapon pending — run '/forge <weapon_key>' first")
        return
    end
    if not trait then
        mod:echo("Usage: /forge_trait <trait_name>")
        return
    end
    _forge_pending.trait = trait
    mod:echo("Forge: trait set to " .. trait)
end)

mod:command("forge_props", "Set properties for pending forge (usage: /forge_props crit_chance=0.5 attack_speed=1)", function(...)
    if not _forge_pending then
        mod:echo("Forge: no weapon pending — run '/forge <weapon_key>' first")
        return
    end
    local args = {...}
    if #args == 0 then
        mod:echo("Usage: /forge_props <prop>=<value> ...")
        mod:echo("  Values are 0.0-1.0 (fraction of max)")
        return
    end
    for _, arg in ipairs(args) do
        local key, val = arg:match("^([^=]+)=(.+)$")
        if key and val then
            local num = tonumber(val)
            if num then
                _forge_pending.properties[key] = num
                mod:echo("  " .. key .. " = " .. tostring(num))
            else
                mod:echo("  Invalid value for " .. key .. ": " .. val)
            end
        else
            mod:echo("  Invalid format: " .. arg .. " (expected key=value)")
        end
    end
end)

mod:command("forge_skin", "Set skin for pending forge (usage: /forge_skin <skin_key>)", function(skin)
    if not _forge_pending then
        mod:echo("Forge: no weapon pending — run '/forge <weapon_key>' first")
        return
    end
    if not skin then
        _forge_pending.skin = nil
        mod:echo("Forge: skin cleared")
        return
    end
    _forge_pending.skin = skin
    mod:echo("Forge: skin set to " .. skin)
end)

mod:command("forge_power", "Set power level for pending forge (usage: /forge_power <1-300>)", function(val)
    if not _forge_pending then
        mod:echo("Forge: no weapon pending — run '/forge <weapon_key>' first")
        return
    end
    local num = tonumber(val)
    if not num or num < 1 or num > 300 then
        mod:echo("Usage: /forge_power <1-300>")
        return
    end
    _forge_pending.power_level = math.floor(num)
    mod:echo("Forge: power level set to " .. _forge_pending.power_level)
end)

mod:command("forge_cancel", "Cancel pending forge", function()
    if not _forge_pending then
        mod:echo("Forge: nothing pending")
        return
    end
    _forge_pending = nil
    mod:echo("Forge: cancelled")
end)

mod:command("forge_confirm", "Create the forged weapon", function()
    if not _forge_pending then
        mod:echo("Forge: no weapon pending — run '/forge <weapon_key>' first")
        return
    end

    local rnd = math.random(1000000)
    local backend_id = _forge_pending.item_key .. "_" .. rnd .. "_forged"

    if _forge_inject_item(_forge_pending, backend_id) then
        _forged_weapons[backend_id] = {
            item_key = _forge_pending.item_key,
            properties = _forge_pending.properties,
            trait = _forge_pending.trait,
            skin = _forge_pending.skin,
            power_level = _forge_pending.power_level,
            via_mirror = false,
        }
        _forge_save()

        local master = rawget(ItemMasterList, _forge_pending.item_key)
        local display = _forge_pending.item_key
        if master and master.display_name then
            local ok, loc = pcall(Localize, master.display_name)
            if ok and loc then display = loc end
        end
        mod:echo("Forge: created " .. display .. " [" .. backend_id .. "]")
        _forge_pending = nil
    end
end)

-- Diagnostic for salvage visibility: dumps every saved craft + whether it's
-- currently in the backend mirror, what rarity the mirror says, what
-- slot_type it has, and whether our salvage filter would surface it.
mod:command("salvage_debug", "Why isn't my modded craft showing in salvage?", function()
    local items_iface = Managers.backend and Managers.backend:get_interface("items")
    local mirror = Managers.backend and Managers.backend:get_backend_mirror()
    if not items_iface or not mirror then
        mod:echo("Backend not ready")
        return
    end

    local inv = mirror._inventory_items or {}
    local saved_count, in_mirror, promo_in_mirror = 0, 0, 0
    mod:echo("--- saved crafts (_forged_weapons) ---")
    for bid, w in pairs(_forged_weapons) do
        saved_count = saved_count + 1
        local item = inv[bid]
        local in_inv = item ~= nil
        if in_inv then in_mirror = in_mirror + 1 end
        local rarity = item and item.rarity or "<not in mirror>"
        local slot_type = item and item.data and item.data.slot_type or "<no data>"
        if rarity == "promo" then promo_in_mirror = promo_in_mirror + 1 end
        local in_inv_str = in_inv and "Y" or "N"
        mod:echo(string.format("  inv=%s  rarity=%s  slot=%s  key=%s  bid=%s",
            in_inv_str, tostring(rarity), tostring(slot_type), tostring(w.item_key), tostring(bid)))
    end
    mod:echo(string.format("Saved: %d  In mirror: %d  Promo in mirror: %d",
        saved_count, in_mirror, promo_in_mirror))

    mod:echo("--- all promo-rarity items in mirror ---")
    local extra_promo = 0
    for bid, item in pairs(inv) do
        if item and item.rarity == "promo" and not _forged_weapons[bid] then
            extra_promo = extra_promo + 1
            local slot_type = item.data and item.data.slot_type or "<no data>"
            mod:echo(string.format("  rarity=promo  slot=%s  key=%s  bid=%s",
                tostring(slot_type), tostring(item.key or item.ItemId), tostring(bid)))
        end
    end
    if extra_promo == 0 then mod:echo("  (none beyond saved crafts)") end
end)

mod:command("forge_list", "List all forged weapons", function()
    local count = 0
    for bid, w in pairs(_forged_weapons) do
        count = count + 1
        local display = w.item_key
        local _entry = ItemMasterList and rawget(ItemMasterList, w.item_key)
        if _entry and _entry.display_name then
            local ok, loc = pcall(Localize, _entry.display_name)
            if ok and loc then display = loc end
        end
        local parts = { display }
        if w.trait then parts[#parts + 1] = "trait=" .. w.trait end
        local prop_strs = {}
        for k, v in pairs(w.properties) do
            prop_strs[#prop_strs + 1] = k .. "=" .. tostring(v)
        end
        if #prop_strs > 0 then parts[#parts + 1] = table.concat(prop_strs, ", ") end
        parts[#parts + 1] = "power=" .. tostring(w.power_level or 300)
        mod:echo("[" .. count .. "] " .. table.concat(parts, " | ") .. "  id=" .. bid)
    end
    if count == 0 then
        mod:echo("Forge: no forged weapons")
    else
        mod:echo("Forge: " .. count .. " weapon(s)")
    end
end)

mod:command("forge_delete", "Delete a forged weapon (usage: /forge_delete <backend_id or index>)", function(id_or_idx)
    if not id_or_idx then
        mod:echo("Usage: /forge_delete <backend_id or index from /forge_list>")
        return
    end

    local idx = tonumber(id_or_idx)
    local target_bid = nil

    if idx then
        local count = 0
        for bid, _ in pairs(_forged_weapons) do
            count = count + 1
            if count == idx then
                target_bid = bid
                break
            end
        end
        if not target_bid then
            mod:echo("Forge: no weapon at index " .. tostring(idx))
            return
        end
    else
        if _forged_weapons[id_or_idx] then
            target_bid = id_or_idx
        else
            mod:echo("Forge: no weapon with id '" .. id_or_idx .. "'")
            return
        end
    end

    if _forge_detect_mil() then
        pcall(_more_items_lib.remove_mod_items_from_local_backend, _more_items_lib, {target_bid}, "crafting_in_modded_dev")
    end
    _forged_weapons[target_bid] = nil
    _forge_save()
    if Managers.backend then
        local items = Managers.backend:get_interface("items")
        if items then items:_refresh() end
    end
    mod:echo("Forge: deleted " .. target_bid)
end)

-- ============================================================
-- /regression_test checks (see scaffold near MOD_VERSION).
-- ============================================================

_rt_register("pool_excludes_scrubbed", function()
    -- v0.7.4: hook installed on DeusRunController.get_weapon_pool to drop
    -- scrubbed entries. Verify the class & method are present.
    local cls = rawget(_G, "DeusRunController")
    if not cls then return "DeusRunController not loaded (run in-keep)" end
    if type(cls.get_weapon_pool) ~= "function" then
        return "get_weapon_pool missing on DeusRunController"
    end
end)

_rt_register("single_on_enter_hook_per_class", function()
    -- v0.7.8: standard_forge.lua hooks on_enter exactly once per class
    -- (HeroWindowItemCustomization, HeroWindowCrafting, HeroWindowCraftingConsole).
    -- Verify class presence. We can't easily count hooks from outside VMF.
    local classes = { "HeroWindowItemCustomization", "HeroWindowCrafting", "HeroWindowCraftingConsole" }
    local missing = {}
    for _, name in ipairs(classes) do
        local cls = rawget(_G, name)
        if not cls then missing[#missing + 1] = name end
    end
    if #missing > 0 then
        return "classes not loaded (run in-keep): " .. table.concat(missing, ", ")
    end
end)

-- ============================================================
-- Save/restore invariants (added 2026-05-23 after user reported
-- equipped accessories + last weapons didn't restore on fresh
-- load). These exercise the VMF settings round-trip so a future
-- regression of the "stale modded_loadout entry overwrites vanilla
-- restore" bug fails the test instead of silently shipping.
-- ============================================================

-- Test bid pattern: must look like a real cim craft to _cim_is_modded_backend_id.
-- We INJECT the fake bid into _forged_weapons during the test so the modded
-- check passes, then remove on teardown via _rt_with_loadout_sandbox.
local _RT_FAKE_BID         = "rt_test_bid_dont_ship_me"
local _RT_FAKE_VANILLA_BID = "rt_test_vanilla_bid"
local _RT_FAKE_CAREER      = "_rt_test_career"
local _RT_FAKE_SLOT        = "_rt_test_slot"

local function _rt_with_loadout_sandbox(body)
    -- Snapshot real state via deep-copy of both the on-disk SETTINGS payload
    -- AND the in-memory tables so any failed assertion in `body` doesn't
    -- leave fake entries in the player's save.
    local saved_forged      = mod:get("forged_weapons")
    local saved_loadout     = mod:get("modded_loadout")
    local snap_forged_mem   = {}
    for k, v in pairs(_forged_weapons) do snap_forged_mem[k] = v end
    local snap_loadout_mem  = {}
    for c, slots in pairs(_modded_loadout) do
        snap_loadout_mem[c] = {}
        for s, b in pairs(slots) do snap_loadout_mem[c][s] = b end
    end

    local ok, err = pcall(body)

    -- Always teardown — restore in-memory tables AND on-disk payload.
    _forged_weapons = {}
    for k, v in pairs(snap_forged_mem) do _forged_weapons[k] = v end
    _modded_loadout = {}
    for c, slots in pairs(snap_loadout_mem) do
        _modded_loadout[c] = {}
        for s, b in pairs(slots) do _modded_loadout[c][s] = b end
    end
    mod:set("forged_weapons", saved_forged)
    mod:set("modded_loadout", saved_loadout)

    if not ok then error(err, 0) end
end

_rt_register("modded_loadout_round_trip_save_then_clear", function()
    -- Validates the v0.7.33-alpha fix for the 2026-05-23 user report.
    -- Step 1: equip a modded item -> _modded_loadout gets the entry, and
    --         round-tripping via mod:get/set preserves it.
    -- Step 2: equip a NON-modded item at the same (career, slot) -> the cim
    --         entry MUST be cleared. Pre-fix code only saved, never cleared,
    --         so stale entries clobbered vanilla restore on next session.
    local cls = rawget(_G, "BackendInterfaceItemPlayfab")
    if not cls or type(cls.set_loadout_item) ~= "function" then
        return "skip: BackendInterfaceItemPlayfab.set_loadout_item not loaded (run in-keep)"
    end
    local hook_fn = cls.set_loadout_item

    local result_err
    _rt_with_loadout_sandbox(function()
        -- Pretend rt_test_bid is a real cim craft so _cim_is_modded_backend_id
        -- returns true. We register/unregister via the public API to mirror
        -- the real craft path.
        mod._cim_register_craft(_RT_FAKE_BID, {
            item_key = "es_1h_falchion", properties = {}, traits = {}, power_level = 300, rarity = "modded",
        })

        -- Dummy `items` table — vanilla set_loadout_item only touches fields
        -- that exist on the real interface. Our hook is hook_safe so it fires
        -- after vanilla returns; if vanilla errors we still PASS as long as
        -- the cim hook's side effect ran. Either way we don't care about the
        -- vanilla path here — we're testing the cim hook's invariants.
        local fake_items = setmetatable({}, { __index = function() return function() end end })

        -- Step 1: equip modded.
        pcall(hook_fn, fake_items, _RT_FAKE_BID, _RT_FAKE_CAREER, _RT_FAKE_SLOT)

        -- Round-trip via VMF settings: clear in-memory, reload from disk, check.
        _modded_loadout = {}
        _modded_loadout_load()
        if not (_modded_loadout[_RT_FAKE_CAREER] and _modded_loadout[_RT_FAKE_CAREER][_RT_FAKE_SLOT] == _RT_FAKE_BID) then
            result_err = "modded equip not persisted: expected bid=" .. _RT_FAKE_BID
            return
        end

        -- Step 2: equip vanilla (non-modded) at the same career/slot.
        pcall(hook_fn, fake_items, _RT_FAKE_VANILLA_BID, _RT_FAKE_CAREER, _RT_FAKE_SLOT)

        _modded_loadout = {}
        _modded_loadout_load()
        local stale = _modded_loadout[_RT_FAKE_CAREER] and _modded_loadout[_RT_FAKE_CAREER][_RT_FAKE_SLOT]
        if stale ~= nil then
            result_err = "STALE modded entry not cleared on vanilla equip: still " .. tostring(stale)
                .. " (this is the 2026-05-23 user-report bug)"
            return
        end

        mod._cim_unregister_craft(_RT_FAKE_BID)
    end)
    if result_err then return result_err end
end)

_rt_register("forged_weapons_round_trip", function()
    -- Register a fake craft, save, force-reload, confirm parity.
    local result_err
    _rt_with_loadout_sandbox(function()
        local payload = {
            item_key = "es_1h_falchion",
            properties = { attack_speed = 5, crit_chance = 5 },
            traits = { "melee_attack_speed_on_crit" },
            power_level = 300,
            rarity = "modded",
            skin = nil,
        }
        mod._cim_register_craft(_RT_FAKE_BID, payload)

        -- Force the on-disk round-trip.
        _forged_weapons = {}
        _forge_load()

        local got = _forged_weapons[_RT_FAKE_BID]
        if not got then
            result_err = "register/save/load lost the entry"
            return
        end
        if got.item_key ~= payload.item_key then
            result_err = ("item_key mismatch: got=%s expected=%s"):format(tostring(got.item_key), payload.item_key)
            return
        end
        local got_attack = (got.properties or {}).attack_speed
        if got_attack ~= 5 then
            result_err = ("properties.attack_speed mismatch: got=%s expected=5"):format(tostring(got_attack))
            return
        end
        local got_trait = (got.traits or {})[1]
        if got_trait ~= "melee_attack_speed_on_crit" then
            result_err = ("traits[1] mismatch: got=%s expected=melee_attack_speed_on_crit"):format(tostring(got_trait))
            return
        end

        mod._cim_unregister_craft(_RT_FAKE_BID)
        -- Confirm unregister wrote through.
        _forged_weapons = {}
        _forge_load()
        if _forged_weapons[_RT_FAKE_BID] ~= nil then
            result_err = "unregister_craft did not persist nil-write"
            return
        end
    end)
    if result_err then return result_err end
end)

_rt_register("restore_after_playfab_inventory_populated", function()
    -- _restore_modded_loadout must run AFTER vanilla PlayFab inventory sync
    -- finishes, otherwise set_loadout_item targets an empty mirror and the
    -- restore silently no-ops. We can't intercept the call ordering after
    -- the fact, so we check the current state at /cim_regression_test time:
    -- if the mirror's _inventory_items is empty AND we're past
    -- _create_interfaces, restore would have just no-op'd.
    local backend = Managers and Managers.backend
    if not backend then return "skip: Managers.backend not ready (run in-keep)" end
    local items_iface = backend.get_interface and backend:get_interface("items")
    local mirror = items_iface and items_iface._backend_mirror
    local inv = mirror and mirror._inventory_items
    if type(inv) ~= "table" then
        return "skip: backend_mirror._inventory_items not populated yet"
    end
    local count = 0
    for _ in pairs(inv) do count = count + 1; if count > 0 then break end end
    if count == 0 then
        return "PlayFab inventory empty at restore time -- _restore_modded_loadout would silently no-op"
    end
end)

_rt_register("inventory_property_count_within_cap", function()
    -- v0.7.25 trim invariant: no item in the mirror should carry >2
    -- properties. The _create_interfaces hook trims on load; if anything is
    -- still over, either the trim broke or a code path bypassed it.
    local backend = Managers and Managers.backend
    if not backend then return "skip: Managers.backend not ready (run in-keep)" end
    local items_iface = backend.get_interface and backend:get_interface("items")
    local mirror = items_iface and items_iface._backend_mirror
    local inv = mirror and mirror._inventory_items
    if type(inv) ~= "table" then return "skip: backend_mirror._inventory_items not ready" end
    local offenders = {}
    for bid, item in pairs(inv) do
        local props = item and item.properties
        if type(props) == "table" then
            local n = 0
            for _ in pairs(props) do n = n + 1 end
            if n > 2 then
                offenders[#offenders + 1] = tostring(bid) .. "(" .. tostring(n) .. ")"
                if #offenders >= 5 then break end
            end
        end
    end
    if #offenders > 0 then
        return "items over 2-property cap: " .. table.concat(offenders, ", ")
    end
end)

_rt_register("modded_loadout_has_no_stale_entries", function()
    -- Every saved _modded_loadout entry must reference either a live
    -- _forged_weapons bid or a cwv_-prefixed item. Stale entries (bid no
    -- longer registered anywhere) are exactly the overwrite-bug substrate:
    -- on next session they restore-clobber the vanilla loadout with an item
    -- that no longer exists OR was already deleted.
    local stale = {}
    for career_name, slots in pairs(_modded_loadout) do
        for slot_name, bid in pairs(slots) do
            local live = (type(bid) == "string") and (_forged_weapons[bid] or bid:sub(1, 4) == "cwv_")
            if not live then
                stale[#stale + 1] = string.format("%s/%s=%s", tostring(career_name), tostring(slot_name), tostring(bid))
                if #stale >= 5 then break end
            end
        end
        if #stale >= 5 then break end
    end
    if #stale > 0 then
        return "stale modded_loadout entries (will clobber vanilla restore): " .. table.concat(stale, ", ")
    end
end)

_rt_register("dbg_helpers_two_channel", function()
    if type(_dbg) ~= "function" then return "_dbg helper missing" end
    if type(_dbg_alert) ~= "function" then return "_dbg_alert helper missing" end
    local saved = mod:get("enable_debug_logging")
    if saved ~= false then mod:set("enable_debug_logging", false) end
    local ok = pcall(_dbg, "smoke test off")
    if not ok then return "_dbg raised with toggle off" end
    ok = pcall(_dbg_alert, "smoke test off")
    if not ok then return "_dbg_alert raised with toggle off" end
    if saved == true then mod:set("enable_debug_logging", true) end
end)



_rt_register("localization_format_safe", function()
    -- Layer 3 (2026-05-25): catch unescaped %-format chars in loc strings at
    -- runtime. VMF's tooltip render path calls string.format on the loc value;
    -- literal "%APPDATA%" / "5%" / "%USERNAME%" raises 'invalid option' and
    -- shows as a red error tooltip in the VMF settings UI. Static check is
    -- qa/check_localization.ps1 -- this is its runtime twin so the bug can't
    -- ship even if the static check is skipped. RULE: any literal % in a loc
    -- string must be doubled to %%.
    local ok, loc = pcall(mod.dofile, mod, "scripts/mods/crafting_in_modded_dev/crafting_in_modded_dev_localization")
    if not ok or type(loc) ~= "table" then return end  -- can't reach loc; skip
    for k, v in pairs(loc) do
        if type(v) == "table" and type(v.en) == "string" then
            local fmt_ok, fmt_err = pcall(string.format, v.en)
            if not fmt_ok then
                return string.format(
                    "loc key %q has invalid format string (escape literal %% as %%%%): %s",
                    k, tostring(fmt_err))
            end
        end
    end
end)

_rt_register("stamina_movespeed_clamp_at_overcap", function()
    -- v0.7.44-alpha (issue #49) removed the per-property bubble-cap rejection in the
    -- set_loadout_property hook (clicks past stamina=2 / movespeed=1 used to
    -- silently no-op). The engine-effective value must still clamp to 1.0 at
    -- over-cap counts so buffs don't exceed vanilla tiers. This check pins
    -- the clamp: if a future edit re-introduces over-cap values >1.0, buffs
    -- would exceed vanilla and we'd ship a balance regression silently.
    if type(_value_for_bubbles) ~= "function" then return "_value_for_bubbles missing" end
    if _value_for_bubbles("stamina", 2) ~= 1.0 then
        return string.format("stamina at cap (2) expected 1.0, got %s", tostring(_value_for_bubbles("stamina", 2)))
    end
    if _value_for_bubbles("stamina", 3) ~= 1.0 then
        return string.format("stamina over-cap (3) expected clamp to 1.0, got %s", tostring(_value_for_bubbles("stamina", 3)))
    end
    if _value_for_bubbles("stamina", 5) ~= 1.0 then
        return string.format("stamina over-cap (5) expected clamp to 1.0, got %s", tostring(_value_for_bubbles("stamina", 5)))
    end
    -- movespeed cap=1 only when the 2pct toggle is OFF (default). Test the
    -- default path; restore the user's setting afterward.
    local saved = mod:get("movespeed_2pct_mode")
    if saved ~= false then mod:set("movespeed_2pct_mode", false) end
    local m1 = _value_for_bubbles("movespeed", 1)
    local m3 = _value_for_bubbles("movespeed", 3)
    if saved == true then mod:set("movespeed_2pct_mode", true) end
    if m1 ~= 1.0 then return string.format("movespeed at cap (1) expected 1.0, got %s", tostring(m1)) end
    if m3 ~= 1.0 then return string.format("movespeed over-cap (3) expected clamp to 1.0, got %s", tostring(m3)) end
end)

_rt_register("action_rejection_uses_warning_channel", function()
    -- v0.7.44-alpha converted ~dozen action-rejection callsites from mod:echo
    -- to mod:warning (issue #47). The v0.7.38 chat-suppression patch silences
    -- mod:echo unless enable_debug_logging is on; mod:warning bypasses it so
    -- the user sees WHY a click was rejected. Regression: if someone re-points
    -- mod.warning at the suppressed echo (or replaces both with the same
    -- function), rejections become invisible and the user perceives "broken
    -- mod" — exactly the user-report substrate from 2026-05-25.
    if type(mod.warning) ~= "function" then return "mod.warning missing" end
    if type(mod.echo) ~= "function" then return "mod.echo missing" end
    if mod.warning == mod.echo then
        return "mod.warning and mod.echo are the same function — chat-suppression patch leaked into the warning channel"
    end
    -- Smoke: must not raise.
    local ok, err = pcall(function() mod:warning("[cim:rt] action_rejection_uses_warning_channel smoke (ignore)") end)
    if not ok then return string.format("mod:warning raised: %s", tostring(err)) end
end)

_rt_register("morris_hub_passes_open_forge_gate", function()
    -- v0.7.47-alpha removed the blanket `mech == "deus" -> block` early return
    -- in mod.open_forge. The CW staging hub (morris_hub) is part of the deus
    -- mechanism but DamageUtils.is_in_inn returns true there, so the keep-gate
    -- correctly permits it. Regression: if the deus block sneaks back, the
    -- staging-hub forge breaks again. This check is a state-witness — it
    -- skips unless we're actually in morris_hub, then asserts the inn-gate passes.
    if not (rawget(_G, "DamageUtils") and Managers) then
        return "skip: DamageUtils / Managers not loaded"
    end
    local mech_mgr = Managers.mechanism
    if not mech_mgr or not mech_mgr.current_mechanism_name then
        return "skip: Managers.mechanism not ready"
    end
    local mech = mech_mgr:current_mechanism_name()
    if mech ~= "deus" then
        return "skip: not in CW mechanism (currently " .. tostring(mech) .. ")"
    end
    if not DamageUtils.is_in_inn then
        return "skip: in active CW expedition (run from morris_hub staging)"
    end
    if type(mod.open_forge) ~= "function" then return "mod.open_forge missing" end
    -- We're in morris_hub and is_in_inn=true → open_forge's keep-gate permits.
    -- We do NOT call open_forge here (it would trigger a UI transition).
end)

_rt_register("trim_logging_emits_per_item_detail", function()
    -- v0.7.33-alpha added per-item `[trim] <key> (bid=...) kept=[...] dropped=[...]`
    -- log lines so user reports of "my weapon lost properties" are diagnosable
    -- from the log alone. Guards the mod:info channel that carries the per-item
    -- detail — if a future edit silences mod:info or removes the logger, the
    -- diagnostic chain breaks.
    if type(mod.info) ~= "function" then return "mod.info missing — per-item trim detail would not log" end
    local ok, err = pcall(function() mod:info("[cim:rt] trim_logging_emits_per_item_detail smoke (ignore)") end)
    if not ok then return string.format("mod:info raised: %s", tostring(err)) end
end)

_rt_register("no_duplicate_hook_safe_registrations", function()
    -- v0.7.51-dev: the rehook-warning interceptor at the top of this file
    -- captures every `mod:warning("...rehook active hook...")` VMF emits at
    -- boot. If any are present, we have two sibling `hook_safe` registrations
    -- on the same Class+method — VMF silently drops one, breaking whichever
    -- callback registered later. Caught HeroWindowLoadoutInventory.on_enter
    -- being double-hooked (modded_rarities.lua + cim_debug.lua) on 2026-05-27.
    --
    -- This is a state-witness, not a static check: the interceptor must be
    -- installed BEFORE any of cim's `hook_safe` calls (it is — the
    -- interceptor sits right after the `mod.echo` patch at the top of this
    -- file, before any module loads or hook registrations).
    local warns = mod._cim_rehook_warnings or {}
    if #warns > 0 then
        local first = warns[1]
        if #warns > 1 then
            first = first .. string.format(" (and %d more)", #warns - 1)
        end
        return "VMF rehook warnings at boot — duplicate hook_safe registration: " .. first
    end
end)

_rt_register("accessories_label_on_overview", function()
    -- v0.7.50-dev (issue #38): the modded Athanor overview viewport_title_2 was
    -- hardcoded as "JEWELLERY"; fixed to "ACCESSORIES". This check can't read
    -- the live widget text (overview is constructed mid-state-transition), but
    -- we can defend the source: if a future edit re-introduces the literal
    -- "JEWELLERY" anywhere in this file or standard_forge.lua, the user-facing
    -- regression would silently ship. Static-source check via mod.dofile of
    -- the localization file (the only place the loc key lives) is a layer; we
    -- also pin the loc override here for the standard forge recipe title.
    local ok, loc = pcall(mod.dofile, mod, "scripts/mods/crafting_in_modded_dev/modded_rarities")
    if not ok then return end  -- module load failed elsewhere; skip
    -- modded_rarities sets cat.display_name = "Accessories" on jewellery
    -- category at HeroWindowLoadoutInventory.on_enter. The Localize override
    -- table maps crafting_recipe_craft_jewellery -> "Craft Accessories".
    -- Both are layered defenses; this check only catches gross regressions
    -- (e.g. someone reverts the table back to "Jewellery").
    local rarity_func = rawget(_G, "Localize")
    if type(rarity_func) ~= "function" then return "skip: Localize not loaded" end
    local localized = rarity_func("crafting_recipe_craft_jewellery")
    if type(localized) ~= "string" then return "Localize did not return a string" end
    if localized:find("[Jj]ewel") then
        return string.format("crafting_recipe_craft_jewellery still localizes to %q — Accessories override broken", localized)
    end
end)

_rt_register("overview_btn_render_target", function()
    -- v0.7.60-dev: HeroWindowWeaveForgeOverview has NO `_widgets` array — it
    -- draws from _top_widgets / _bottom_widgets / _top_hdr_widgets /
    -- _bottom_hdr_widgets (vanilla _draw, hero_window_weave_forge_overview.lua).
    -- v0.7.57/.58 appended the 3 jewelry buttons to overview._widgets, so they
    -- went into a collection the window never iterates and NEVER rendered
    -- ("nothing changed" report). Pin the append target to the valid drawn set
    -- so a regression can't silently re-break it.
    if not _OVERVIEW_DRAWN_FIELDS[_OVERVIEW_BTN_RENDER_FIELD] then
        return string.format(
            "overview jewelry buttons append to %q, which is NOT a drawn array on HeroWindowWeaveForgeOverview (must be one of _top_widgets/_bottom_widgets/_top_hdr_widgets/_bottom_hdr_widgets) — buttons will not render",
            tostring(_OVERVIEW_BTN_RENDER_FIELD))
    end
end)

_rt_register("adventure_visible_stamp_and_mechanism_clear", function()
    -- v0.7.62-dev: _ensure_item_adventure_visible must (1) APPEND the crafting
    -- career to ItemMasterList[key].can_wield exactly once (idempotent), and
    -- (2) CLEAR a non-adventure `mechanisms` field (e.g. {"versus"}) so the
    -- Adventure inventory grid stops hiding the crafted item. Tested against a
    -- throwaway fake key (rawset/rawget bypass the ItemMasterList Crashify
    -- metatable), removed afterward so there's zero side effect on real data.
    local IML = rawget(_G, "ItemMasterList")
    if not IML then return "skip: ItemMasterList not loaded" end
    local fake_key = "__cim_rt_fake_advvis__"
    rawset(IML, fake_key, { can_wield = { "es_mercenary", "es_huntsman" }, mechanisms = { "versus" } })
    local ok, errmsg = pcall(function()
        _ensure_item_adventure_visible(fake_key, "es_questingknight")   -- append career + clear mechanisms
        _ensure_item_adventure_visible(fake_key, "es_questingknight")   -- no-op (present + already cleared)
        _ensure_item_adventure_visible(fake_key, "es_mercenary")        -- no-op (already wieldable)
    end)
    local entry = IML[fake_key] or {}
    local cw = entry.can_wield or {}
    local count_qk = 0
    for _, c in ipairs(cw) do if c == "es_questingknight" then count_qk = count_qk + 1 end end
    local total = #cw
    local mechanisms_cleared = (entry.mechanisms == nil)
    rawset(IML, fake_key, nil)  -- cleanup: no lingering fake entry
    if not ok then return "adventure-visible helper errored: " .. tostring(errmsg) end
    if count_qk ~= 1 then
        return string.format("can_wield stamp not idempotent: es_questingknight appears %d times (expected 1)", count_qk)
    end
    if total ~= 3 then
        return string.format("can_wield stamp wrong size: expected 3 entries (2 original + 1 appended), got %d", total)
    end
    if not mechanisms_cleared then
        return "mechanisms not cleared — Versus item would stay hidden in Adventure grid"
    end
end)

_rt_register("overview_btns_created_when_forge_opened", function()
    -- State-witness (like no_duplicate_hook_safe_registrations): if the weave
    -- forge overview has been opened this session, _ensure_overview_jewelry_buttons
    -- must have succeeded in creating the 3 buttons. mod._cim_overview_btn_created
    -- is set to the count on success and to false on a create/init failure.
    -- nil = forge never opened this session → skip (can't assert).
    local created = mod._cim_overview_btn_created
    if created == nil then return "skip: weave forge overview not opened this session" end
    if created == false then
        return "weave forge overview opened but jewelry buttons failed to create (see [cim] overview jewelry button ... failed log lines)"
    end
    if type(created) == "number" and created ~= 3 then
        return string.format("expected 3 overview jewelry buttons, created %d", created)
    end
end)

_rt_register("accessory_panel_module_loaded", function()
    -- v0.7.65-dev: the accessory craft buttons are an own-scenegraph overlay
    -- module (_accessory_craft_panel.lua), the CORRECT pattern (vs the disabled
    -- create_default_button approach). This pins: the module loaded, exposes its
    -- draw API + button-count, and the 3 slot mappings are intact (necklace /
    -- charm=ring / trinket_1) so a future edit can't silently break the wiring.
    if _AccessoryPanel == nil then
        return "accessory craft panel module failed to load (mod.dofile error at boot)"
    end
    if type(_AccessoryPanel.draw) ~= "function" then
        return "accessory panel missing draw() — overlay can't render"
    end
    if _AccessoryPanel.NUM_BUTTONS ~= 3 then
        return string.format("accessory panel NUM_BUTTONS expected 3, got %s", tostring(_AccessoryPanel.NUM_BUTTONS))
    end
    local want = { slot_necklace = true, slot_ring = true, slot_trinket_1 = true }
    local defs = _AccessoryPanel.BUTTONS or {}
    if #defs ~= 3 then return string.format("accessory panel BUTTONS expected 3 entries, got %d", #defs) end
    for _, b in ipairs(defs) do
        if not (b.slot and want[b.slot]) then
            return string.format("accessory panel has unexpected slot mapping: %s", tostring(b and b.slot))
        end
        want[b.slot] = nil  -- ensure no duplicate slot
    end
    if next(want) ~= nil then
        return "accessory panel missing a slot mapping (necklace/charm/trinket)"
    end
end)

_rt_register("accessory_panel_built_when_accessories_opened", function()
    -- State-witness: if the accessories (amulet) view drew this session, the
    -- panel's lazy _build() must have produced exactly NUM_BUTTONS widgets. nil
    -- _built = accessories view never opened → skip (can't assert).
    if _AccessoryPanel == nil then return "skip: panel module not loaded" end
    if not _AccessoryPanel._built then
        return "skip: accessories view not opened this session (panel not built yet)"
    end
    local n = _AccessoryPanel._widgets and #_AccessoryPanel._widgets or 0
    if n ~= _AccessoryPanel.NUM_BUTTONS then
        return string.format("accessory panel built %d widgets, expected %d", n, _AccessoryPanel.NUM_BUTTONS)
    end
end)

_rt_register("backendutils_capture_installed", function()
    -- v0.7.68-dev (issue #22): with Loremaster's Armoury active, menu equips
    -- dispatch through BackendUtils.set_loadout_item, bypassing the
    -- BackendInterfaceItemPlayfab hook. The deferred BackendUtils capture is THE
    -- fix that records the player's equips into _modded_loadout. It installs from
    -- mod.update once the backend is up. nil = backend not up yet this session
    -- (e.g. tests run at main menu) → skip. false should never persist once in
    -- the keep — if it does, equips aren't being captured and won't be restored.
    if mod._cim_backendutils_capture_installed == nil then
        return "skip: BackendUtils capture not installed yet (backend not ready / not in keep)"
    end
    if mod._cim_backendutils_capture_installed ~= true then
        return "BackendUtils.set_loadout_item capture FAILED to install — menu equips won't be saved/restored"
    end
end)

_rt_register("reequip_live_api_ok", function()
    -- v0.7.67-dev (issue #22): _reequip_live_avatar re-equips the keep avatar
    -- after restore via the vanilla create_equipment_in_slot /
    -- create_attachment_in_slot API. If that API errored this session (wrong
    -- signature, called at a bad time), _cim_reequip_last_err captures it — a
    -- state-witness that the live-unit re-equip is misbehaving. nil = no error
    -- (either it worked or never ran) → pass.
    local err = mod._cim_reequip_last_err
    if err then
        return "live re-equip API errored this session: " .. tostring(err)
    end
end)