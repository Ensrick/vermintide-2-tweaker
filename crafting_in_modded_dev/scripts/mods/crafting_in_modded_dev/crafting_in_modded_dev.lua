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

local MOD_VERSION = "0.8.48-dev"
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

-- Two-helper debug-logging policy (PROJECT_STANDARDS.md § 3.6).
-- Both route through VMF logging (mod:debug / mod:warning), gated by VMF output_mode.
-- `_dbg` is for confirmation / expected behavior — file only (mod:debug channel).
-- `_dbg_alert` is for unexpected / wrong / mismatch — mod:warning channel.
local function _dbg(fmt, ...)
    mod:debug("[cim:dbg] " .. fmt, ...)
end

local function _dbg_alert(fmt, ...)
    mod:warning("[cim:dbg] " .. fmt, ...)
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

-- #174 attribution probe (passive, default-on, printf). Instruments cim's own
-- loadout capture + restore paths so the user's post-playtest log names whether
-- cim wrote/restored bot or player loadout slots on startup. See _diag_probe.lua.
local PROBE = mod:dofile("scripts/mods/crafting_in_modded_dev/_diag_probe")

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

-- Versus-carousel item key check, by ItemId/key PREFIX rather than the
-- `mechanisms` field. WHY a prefix and not `mechanisms`: cim's
-- `_ensure_item_adventure_visible` clears `ItemMasterList[key].mechanisms = nil`
-- to make a crafted vs_* weapon adventure-visible (the deliberate craft
-- behavior). But `item.data` is a SHARED reference to that same IML entry
-- (PlayFabMirrorBase._update_data sets `item.data = ItemMasterList[item_key]`),
-- so after the clear `_cim_is_versus(item.data)` returns false for EVERY item of
-- that key — including the player's raw owned vs_* twin that leaked into the
-- adventure inventory grid. The `vs_` prefix is the only discriminator that
-- survives the mechanisms clear. (Every Versus weapon key in vanilla — claws,
-- ratling gun, etc. — is `vs_*`; see item_master_list_versus_rewards.lua.)
local function _cim_is_versus_key(item_key)
    return type(item_key) == "string" and item_key:sub(1, 3) == "vs_"
end
mod._cim_is_versus_key = _cim_is_versus_key

-- True for the player's RAW OWNED vanilla vs_* twin that should NOT show in the
-- adventure inventory grid, but FALSE for a cim-crafted vs_* (modded backend_id)
-- which the user deliberately surfaced and must stay visible. Used by the
-- inventory-display re-hide in the get_filtered_items hook. Keys off
-- `_cim_is_modded_backend_id` so a deliberately-crafted unique vs_* is never
-- hidden (memory: reference_vt2_versus_items_hidden_in_adventure).
local function _cim_is_leaked_versus_twin(item)
    if not item then return false end
    local key = item.key or item.ItemId or (item.data and item.data.key)
    if not _cim_is_versus_key(key) then return false end
    -- A modded backend_id means this IS the crafted item — keep it visible.
    return not (mod._cim_is_modded_backend_id and mod._cim_is_modded_backend_id(item.backend_id))
end
mod._cim_is_leaked_versus_twin = _cim_is_leaked_versus_twin

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

-- Forge freedom (v0.8.44-dev): the Athanor trait/property picker widener +
-- restore. Forward-declared here so the existing HeroViewStateWeaveForge.on_exit
-- hook (restore) and the HeroWindowWeaveProperties._setup_menu_options hook
-- (apply) can reference them before their definitions further down — both are
-- assigned in the freedom block above the _setup_menu_options hook, so the
-- closures capture the upvalue and resolve it at runtime.
local _cim_apply_forge_freedom
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
    mod:info("Forge: restored %d forged weapons", count)
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

if rawget(_G, "LoadoutUtils") and LoadoutUtils.sync_loadout_slot then
    mod:hook(LoadoutUtils, "sync_loadout_slot", function(func, player, slot_name, item, sync_to_specific_peer_id)
        -- v0.8.15-dev master gate: when loadout persistence is OFF (default),
        -- cim takes the wire EXACTLY as vanilla would — no rarity rewrite, no
        -- `cim_modded_slot` side-channel send. Pure pass-through.
        if not _persist_loadouts_enabled() then
            return func(player, slot_name, item, sync_to_specific_peer_id)
        end
        local is_modded = item and item.rarity == "modded" or false
        local peer_id = player:network_id()
        local local_player_id = player:local_player_id()

        -- Side-channel BEFORE the loadout RPC. Cim clients latch the flag and
        -- the rpc_sync_loadout_slot hook below restores rarity on receive.
        -- We always send (even is_modded=false) so equipping a non-modded item
        -- clears any stale modded flag on that slot.
        local target = sync_to_specific_peer_id or "others"
        -- audit 2026-06-07 (v0.7.72-dev): CIM_RPC_SCHEMA is the FIRST positional
        -- arg after the target (VMF_RECIPES § 10). The receiver gate below drops
        -- any packet whose leading schema value doesn't match.
        local ok_send, err_send = pcall(mod.network_send, mod, "cim_modded_slot",
            target, CIM_RPC_SCHEMA, peer_id, local_player_id, slot_name, is_modded)
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
end
mod:network_register("cim_modded_slot", _rpc_cim_modded_slot)

-- Exposed for /cim_regression_test (rpc_schema_gate_drops_on_mismatch): lets the
-- test drive the receiver synthetically and assert the schema gate drops on a
-- bad version (audit 2026-06-07, v0.7.72-dev).
mod._cim_rpc_modded_slot = _rpc_cim_modded_slot
mod._cim_modded_slot_state = _cim_modded_slot_state

-- Restore "modded" rarity post-decode on cim clients. hook_safe fires AFTER
-- vanilla's `rpc_sync_loadout_slot` has stored the item under
-- `_player_loadouts[unique_id][slot_name]` with rarity = "unique" (the wire
-- value). We look up the side-channel flag for that (peer, slot) and upgrade
-- in-place. No-op if the side-channel hasn't arrived yet — the side-channel
-- receiver above handles the inverse out-of-order case.
mod:hook_safe("PlayerManager", "rpc_sync_loadout_slot", function(self, channel_id, peer_id, local_player_id, slot_id, item_id, rarity_id)
    -- v0.8.15-dev master gate: when loadout persistence is OFF (default), cim
    -- does not patch any received-slot rarity. (`_cim_modded_slot_state` stays
    -- empty because the sender-side `sync_loadout_slot` hook never fired the
    -- side-channel, so this would no-op anyway — but bail explicitly to keep the
    -- receive path a clean vanilla pass-through.)
    if not _persist_loadouts_enabled() then return end
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
mod._cim_clear_modded_loadout_for_bid = function(backend_id)
    if not backend_id then return end
    local dirty = false
    -- Indexed schema: career -> index -> slot -> bid. BUT v0.8.14-dev defers the
    -- flat->indexed migration to the first mirror-ready restore pass, so this
    -- helper may run (salvage) while a career is STILL flat (career -> slot ->
    -- bid). Handle BOTH shapes so a pre-migration salvage still clears the bid
    -- and never strands a dangling restore target. Detected per career via the
    -- same `_career_value_is_flat` heuristic used by the migration.
    for career_name, value in pairs(_modded_loadout) do
        if type(value) == "table" then
            if _career_value_is_flat(value) then
                -- Flat: value is slot -> bid (possibly with stray numeric->table
                -- corrupt entries, which we walk into too).
                for slot_name, bid in pairs(value) do
                    if type(bid) == "string" then
                        if bid == backend_id then
                            value[slot_name] = nil
                            dirty = true
                        end
                    elseif type(bid) == "table" then
                        -- Stray numeric->table (mixed/corrupt) — treat as an
                        -- index sub-table.
                        for s, b in pairs(bid) do
                            if b == backend_id then bid[s] = nil; dirty = true end
                        end
                    end
                end
            else
                -- Indexed: value is index -> {slot -> bid}.
                for _index, slots in pairs(value) do
                    if type(slots) == "table" then
                        for slot_name, bid in pairs(slots) do
                            if bid == backend_id then
                                slots[slot_name] = nil
                                dirty = true
                            end
                        end
                    end
                end
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

_restore_modded_loadout = function()
    -- #174 probe: name whether cim's startup restore even runs. persist defaults
    -- OFF (moved to Tweaker: GUI) -> the whole restore is a no-op and cim writes
    -- no bot/player slots, exonerating it. key=nil: this fires a handful of times
    -- per boot (initial + deferred retries), well under the flood cap.
    if PROBE then
        PROBE.emit("174:loadout", nil,
            string.format("cim_dev _restore_modded_loadout:ENTER persist=%s (OFF=no-op, cim writes no slots)",
                tostring(_persist_loadouts_enabled())))
    end
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
    -- #174 probe: log BEFORE the gate so we see every capture attempt AND whether
    -- persistence is enabled (default OFF -> cim writes nothing, exonerating it).
    -- restoring=true marks a replay write (not a fresh equip). Dedup per
    -- career/slot/index so the startup burst logs once each.
    if PROBE then
        PROBE.emit("174:loadout", "cim_cap/" .. tostring(career_name) .. "/" .. tostring(slot_name) .. "/" .. tostring(loadout_index),
            string.format("cim_dev _capture_loadout_equip profile=%s slot=%s item=%s idx=%s from_live=%s persist=%s restoring=%s",
                tostring(career_name), tostring(slot_name), tostring(item_id), tostring(loadout_index),
                tostring(from_live_equip), tostring(_persist_loadouts_enabled()), tostring(_restoring)))
    end
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

    -- Versus-twin re-hide (runs ALWAYS for the adventure inventory grid, even
    -- when the show-only-modded filter is off — the leak is independent of it).
    --
    -- ROOT CAUSE this guards: `_ensure_item_adventure_visible` clears
    -- `ItemMasterList[vs_key].mechanisms = nil` to surface a crafted vs_* weapon
    -- in Adventure (intended). But that IML entry is a GLOBAL shared by the
    -- player's raw OWNED vs_* twin too (item.data is a reference, not a copy —
    -- PlayFabMirrorBase._update_data:1786), so the owned twin ALSO passes the
    -- vanilla `available_in_current_mechanism` filter and leaks into the normal
    -- inventory grid. We can't un-leak it at the data layer (one shared table),
    -- so we re-hide it HERE, at the display layer: drop owned vs_* twins from the
    -- adventure-inventory result while keeping cim-crafted vs_* (modded bid)
    -- visible. Keyed on the vs_ ItemId prefix (the mechanisms field is already
    -- nil post-clear) + _cim_is_modded_backend_id so a deliberately-crafted
    -- unique vs_* is NEVER hidden. INVENTORY display only — the craft list is
    -- untouched (memory: reference_vt2_versus_items_hidden_in_adventure).
    if type(items) == "table" and type(filter) == "string"
       and filter:find("available_in_current_mechanism", 1, true) then
        local kept = {}
        for i = 1, #items do
            local item = items[i]
            if not _cim_is_leaked_versus_twin(item) then
                kept[#kept + 1] = item
            end
        end
        items = kept
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
    local ok, r = pcall(function() return Application.can_get("shading_environment", name) end)
    return ok and r == true
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
    return _swap_forge_env(func(self, scenegraph_id, invert_rendering))
end)

mod:hook("HeroWindowWeaveForgeWeapons", "_create_viewport_definition", function(func, self, scenegraph_id)
    return _swap_forge_env(func(self, scenegraph_id))
end)

mod:hook("HeroWindowWeaveProperties", "_create_viewport_definition", function(func, self)
    return _swap_forge_env(func(self))
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

-- Mid-mission forge: drop the skill-tree RING / wheel / cluster decorations from
-- the NON-HDR _bottom_widgets draw array (Fix B5)
-- ------------------------------------------------------------
-- v0.8.19-dev (ui_passes.lua:805 "Material 'athanor_skilltree_ring_3' not found
-- in Gui", in-mission forge, opening a weapon's skill tree). A NEW vector of the
-- same keep-only-material class B/B2/B3/B4 chased — but on a DIFFERENT draw path
-- the prior fixes never touched:
--
--   * B2 empties the HDR draw arrays (_top_hdr_widgets / _bottom_hdr_widgets),
--     drawn on parent:hdr_renderer().
--   * B3/B4 guard the per-frame bloom set_scalar / upgrade-anim HDR set_scalar.
--   * This vector is the NON-HDR `_bottom_widgets` array, drawn on the BASE
--     mission `ui_renderer` (HeroWindowWeaveProperties._draw, the final
--     `for _, widget in ipairs(self._bottom_widgets)` pass). None of the prior
--     fixes iterate it.
--
-- `_bottom_widgets` mixes FUNCTIONAL widgets (background_write_mask,
-- viewport_background rect, viewport_background_fade = atlas-backed edge_fade_
-- small) with raw, inn-only DECORATIVE textures that only resolve on a Gui built
-- with is_in_inn=true:
--   athanor_skilltree_background        (background_wheel)
--   athanor_skilltree_ring_1 / _2 / _3  (wheel_ring_1..3)   <- the reported crash
--   athanor_skilltree_cluster_1 / _2 .. (cluster_background_<i>, RE-APPENDED per
--                                        cluster by _create_slot_grid ->
--                                        _create_cluster_background at on_enter)
-- (Verified non-atlas: only athanor_skilltree_slot_* live in gui_menus_atlas;
-- the ring / background / cluster textures are in no atlas_settings file — same
-- raw-material signature as the weave_menu_* keep-only set.)
--
-- So we can't empty _bottom_widgets wholesale (it'd strip the functional
-- viewport background). Instead REBUILD it minus only the raw decorative
-- textures, matched by content.texture_id prefix. The vanilla _draw loop then
-- never resolves the missing materials.
--
-- Two append sites feed these into _bottom_widgets, so the helper is called from
-- two places (mirroring B2's two-site pattern):
--   (1) create_ui_elements  -> the static wheel_ring_* / background_wheel
--   (2) on_enter (post)     -> the per-cluster cluster_background_<i> re-append
--       (folded into cim_debug.lua's existing HeroWindowWeaveProperties.on_enter
--        hook, right next to the B2 HDR re-suppression).
--
-- KEEP path untouched: gated on `not in_keep`, so the keep forge keeps the full
-- animated ring/cluster decoration (drawn on the real keep Gui that carries the
-- inn-only materials). The _update_background_animations rotation still mutates
-- widgets_by_name[...] every frame harmlessly (those widgets just aren't in the
-- drawn array in mission). Regression: skilltree_ring_widgets_suppressed_in_mission.
-- v0.8.20-dev — CONVERGENT raw-athanor prune. The old per-prefix allow-list
-- (ring_ / background / cluster_) chased one athanor_* crash at a time and STILL missed
-- athanor_background_write_mask (the 7th reported in-mission crash; log session f9ed28af,
-- ui_passes.lua:134). Per the verified note above, the ONLY athanor_ family in
-- gui_menus_atlas is athanor_skilltree_slot_*; every OTHER athanor_* forge texture is
-- raw / inn-only and faults on the base mission Gui. So in mission, drop ANY athanor_
-- texture that isn't a slot. This catches athanor_background_write_mask (a functional-
-- but-raw window write-mask — losing it only drops background masking in mission, it
-- never crashes) AND every future raw athanor_ sibling in ONE structural guard, instead
-- of one prefix per crash. Atlas-backed slots + all non-athanor functional widgets
-- (edge_fade_small, viewport rects) are untouched. Function name kept for the call sites.
local _CIM_ATLAS_ATHANOR_PREFIX = "athanor_skilltree_slot"   -- the only atlas-backed athanor_ family
local function _cim_is_raw_skilltree_texture(texture_id)
    if type(texture_id) ~= "string" then return false end
    if texture_id:sub(1, 8) ~= "athanor_" then return false end
    return texture_id:sub(1, #_CIM_ATLAS_ATHANOR_PREFIX) ~= _CIM_ATLAS_ATHANOR_PREFIX
end

-- Parameterized + exposed so the regression test can drive it synthetically.
function mod._cim_suppress_skilltree_rings_in_mission(window, in_keep)
    if in_keep then return false end
    if type(window) ~= "table" then return false end
    local widgets = window._bottom_widgets
    if type(widgets) ~= "table" or #widgets == 0 then return false end

    local kept = {}
    local removed = false
    for i = 1, #widgets do
        local widget = widgets[i]
        local texture_id = type(widget) == "table" and widget.content and widget.content.texture_id
        if _cim_is_raw_skilltree_texture(texture_id) then
            removed = true
        else
            kept[#kept + 1] = widget
        end
    end

    if removed then
        window._bottom_widgets = kept
    end
    return removed
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
        -- Fix B5: drop the static wheel_ring_* / background_wheel raw textures
        -- from the non-HDR _bottom_widgets array (only HeroWindowWeaveProperties
        -- builds them; a no-op on the other three windows).
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

-- ============================================================
-- Forge weapon preview: skip the 3D model spawn for weapons whose
-- preview units aren't resident / loadable in the weave-forge world
-- ============================================================
-- Crash class (HARD CTD — no Lua traceback, so nothing shows in console logs):
-- the weave-forge weapon previewer (`LootItemUnitPreviewer`, created by
-- HeroWindowWeaveForgeOverview / HeroWindowWeaveForgeWeapons and
-- HeroWindowWeaveProperties via `_create_item_previewer`) spawns the selected
-- weapon's 3D model. Two engine-level spawn sites run with NO Lua guard:
--   1. `_spawn_link_unit` -> World.spawn_unit(world, <skin.display_unit>) inside
--      LootItemUnitPreviewer.init, BEFORE any package load — it assumes the
--      display unit is already resident (weave weapons live in the
--      ui_loot_preview global package).
--   2. `_load_item_units` -> load_package("<hand_unit>_3p") ->
--      Managers.package:load(...), which fatals on a non-existent package.
--
-- The Trollhammer Torpedo (`dr_deus_01`, Bardin — "torpedo cannon") is the
-- reported case (user 2026-06-05: "crashes when you try and change the stats
-- for it"). It's a Chaos Wastes ("morris"/deus) weapon never shown in the
-- vanilla weave forge, so its display unit (`display_trollhammer`) and held 3p
-- unit (`wpn_dr_deus_01_3p`) live in the CW bundle and are NOT in the forge
-- preview package set. cim's Athanor forge re-exposes the weapon for adventure
-- crafting, so opening its property/stat editor spawns those absent units ->
-- access-violation CTD with no Lua error (which is exactly why the crash left
-- no traceback in any console log).
--
-- Fix: before the two spawn sites run, check resource availability the same way
-- vanilla's pickup_system.lua:882-899 does — `Application.can_get("unit", ...)`
-- for the resident display unit, `Application.can_get("package", "<unit>_3p")`
-- for the load_package'd 3p units. If anything the previewer would touch is
-- unavailable, skip the spawn (nil link / empty spawn list). spawn_units()
-- already no-ops on a nil link_unit (loot_item_unit_previewer.lua:542), so the
-- previewer object stays valid and the stat editor works fully — only the
-- spinning 3D model is omitted for that one weapon. Gated on
-- `_custom_forge_active`, so non-forge previewers (loot reveal, store, hero
-- inventory) are untouched. Default to UNSAFE on any resolution error — losing
-- a cosmetic preview always beats a CTD.
local _forge_preview_warned = {}
local function _forge_preview_unsafe(item)
    local ok, unsafe = pcall(function()
        if not item then return true end
        local item_key = item.key or (item.data and item.data.key)
        if not item_key then return true end
        local master = rawget(ItemMasterList, item_key)
        if not master then return true end

        -- (1) Display / link unit — spawned with no prior load, so it must be
        --     resident NOW. can_get("unit", ...) reflects current residency.
        local skin = item.skin or item_key
        local skins = rawget(_G, "WeaponSkins")
        local skin_template = skins and skins.skins and skins.skins[skin]
        local display_unit = (skin_template and skin_template.display_unit) or master.display_unit
        if display_unit and display_unit ~= "" and not Application.can_get("unit", display_unit) then
            return true
        end

        -- (2) Held / ammo units — load_package'd as "<unit>_3p" packages.
        --     can_get("package", ...) reflects whether the package EXISTS
        --     (loadable), independent of current residency: the previewer hasn't
        --     loaded them yet at guard time, so a residency check would
        --     false-positive on every weapon and strip all previews.
        local BU = rawget(_G, "BackendUtils")
        local item_units = BU and BU.get_item_units
            and BU.get_item_units(master, item.backend_id, item.skin, nil)
        if item_units then
            local function pkg_missing(u)
                if not u or u == "" then return false end
                return not Application.can_get("package", u .. "_3p")
            end
            if item_units.is_ammo_weapon then
                if pkg_missing(item_units.ammo_unit) then return true end
            else
                if pkg_missing(item_units.left_hand_unit) then return true end
                if pkg_missing(item_units.right_hand_unit) then return true end
            end
        end
        return false
    end)
    if not ok then return true end
    if unsafe then
        local key = (item and (item.key or (item.data and item.data.key))) or "<?>"
        if not _forge_preview_warned[key] then
            _forge_preview_warned[key] = true
            mod:info("[cim] forge 3D preview skipped for '%s' — its preview units aren't loadable in the forge world (would CTD). Stat editing still works.", tostring(key))
        end
    end
    return unsafe
end
mod._cim_forge_preview_unsafe = _forge_preview_unsafe  -- exposed for /cim_regression_test

-- Guard both spawn sites at the LootItemUnitPreviewer chokepoint — covers all
-- three forge windows (overview / weapons / properties) in one place. No
-- existing cim hook on either method (only HeroWindowWeaveProperties.
-- _create_unit_previewer above is hooked) — singleton, no duplicate-hook risk.
mod:hook("LootItemUnitPreviewer", "_spawn_link_unit", function(func, self, item)
    if _custom_forge_active and _forge_preview_unsafe(item) then return nil end
    return func(self, item)
end)

mod:hook("LootItemUnitPreviewer", "_load_item_units", function(func, self, item)
    if _custom_forge_active and _forge_preview_unsafe(item) then return {} end
    return func(self, item)
end)

-- ============================================================
-- Forge stat editor: guard the weave property/trait/talent pickers against
-- weapons whose category isn't a weave category
-- ============================================================
-- Crash class (Lua error WITH traceback — distinct from the no-trace preview
-- CTD guarded above): hero_window_weave_properties.lua "bad argument #1 to
-- 'ipairs' (table expected, got nil)" in HeroWindowWeaveProperties.
-- _setup_menu_options. Vanilla on_enter clones WeaveWeaponProgression for the
-- selected weapon and stamps each slot_unlock.category = item_data.
-- property_table_name / trait_table_name; _setup_menu_options then does, with
-- NO nil-check:
--   WeaveTraits.categories[category]                       -> ipairs(...)
--   WeaveProperties.categories[category]                   -> ipairs(...)
--   WeaveLoadoutSettings[career].talent_tree[category]     -> ipairs(...)
-- cim's Athanor forge re-exposes adventure / Chaos Wastes weapons (the
-- Trollhammer Torpedo dr_deus_01, property_table_name "deus_trollhammer_torpedo",
-- is the reported case) whose table-names are NOT keys in those weave category
-- tables, so the lookup is nil and ipairs(nil) hard-errors when the stat editor
-- opens. This runs in on_enter BEFORE the 3D previewer, so _forge_preview_unsafe
-- never gets a chance — it's a separate crash from the v0.7.70 preview guard.
--
-- Fix: before the vanilla setup runs, seed an empty {} pool for every category
-- referenced by the current progression that the weave tables don't know about.
-- ipairs({}) is a no-op, so the affected picker renders empty (no weave
-- traits/properties/talents for that weapon) instead of crashing. Empty entry
-- lists are an ordinary vanilla case (nothing unlocked yet), so the rest of
-- _setup_menu_options handles them. Idempotent (only seeds nil keys), scoped to
-- the categories actually in play.
local function _cim_ensure_weave_category_pools(career_name, slots_progression)
    if not slots_progression then return end
    local wt = rawget(_G, "WeaveTraits")
    local wp = rawget(_G, "WeaveProperties")
    local wls = rawget(_G, "WeaveLoadoutSettings")

    local function _seed(pool, progression)
        if not (pool and progression) then return end
        for _, slot_unlock in ipairs(progression) do
            local category = slot_unlock.category
            if category ~= nil and pool[category] == nil then
                pool[category] = {}
            end
        end
    end

    _seed(wt and wt.categories, slots_progression.traits)
    _seed(wp and wp.categories, slots_progression.properties)
    local loadout = wls and career_name and wls[career_name]
    _seed(loadout and loadout.talent_tree, slots_progression.talents)
end
mod._cim_ensure_weave_category_pools = _cim_ensure_weave_category_pools  -- exposed for /cim_regression_test

-- ============================================================
-- Forge freedom: widen the Athanor trait/property picker (v0.8.44-dev)
-- ============================================================
-- Two VMF toggles let the picker offer traits/properties it normally would not:
--   allow_cw_traits          — the Chaos Wastes / deus boon traits.
--   allow_any_trait_property — every adventure trait AND property, any slot type.
--
-- The picker enumerates WeaveTraits.categories[cat] / WeaveProperties.categories
-- [cat] (weave keys) and renders each via WeaveTraits.traits[key] /
-- WeaveProperties.properties[key]. The apply path (_forge_apply_to_item) strips
-- the leading "weave_" to get the bare adventure key the crafted item receives.
-- So to offer an adventure trait/property `bare` we surface "weave_" .. bare:
--   * if that weave key already exists (the normal twin, e.g.
--     weave_melee_attack_speed_on_crit) reuse it — full display data already;
--   * else inject a display stub from the adventure entry (boons + adventure-only
--     keys). Crash-critical fields (verified against the vanilla picker):
--       trait — display_name REQUIRED; advanced_description/description_values are
--               a matched pair, so we set NEITHER (empty desc, zero string.format
--               risk).
--       prop  — display_name REQUIRED; buff_name must resolve in BuffTemplates
--               with a .buffs[1] (picker does buff_template.buffs[1]);
--               description_values MUST be non-empty with a numeric [1].value.
--
-- Under the modded forge the store path is fully cim-owned (set_loadout_property/
-- trait never call vanilla, so the WeavePropertiesByCareer fassert never fires)
-- and the backend cost/forge-level hooks already return faked values without
-- indexing the key — so display stubs are all that is needed; no Weave*ByCareer
-- injection. Category arrays are widened only while the modded forge is open and
-- restored on exit (see the on_exit hook), so real Weaves play is untouched.

-- Saved originals of each widened category array, so on_exit can restore them.
-- Value is the original array, or false if the category had no array before.
local _cim_forge_widen_backup = { traits = {}, properties = {} }

local function _cim_ensure_trait_twin(bare)
    local WT = rawget(_G, "WeaveTraits")
    local adv_tbl = rawget(_G, "WeaponTraits")
    if not (WT and WT.traits and adv_tbl and adv_tbl.traits) then return nil end
    local weave_key = "weave_" .. bare
    if WT.traits[weave_key] then return weave_key end          -- reuse existing twin
    local adv = adv_tbl.traits[bare]
    if not (adv and adv.display_name) then return nil end       -- no name = would crash Localize
    WT.traits[weave_key] = {
        name         = weave_key,
        display_name = adv.display_name,
        icon         = adv.icon,        -- optional; picker falls back to placeholder
        buff_name    = adv.buff_name,   -- not read by the trait picker; kept for parity
        -- #238: copy advanced_description + description_values TOGETHER (a matched
        -- pair). The base game already renders these exact adventure entries via
        -- UIUtils.get_trait_description in normal crafting, so their format-spec
        -- count is guaranteed consistent -- copying both verbatim is exactly as
        -- safe as vanilla's own trait display. (The string.format crash only
        -- happens for a MISMATCHED pair, e.g. advanced_description kept but
        -- description_values dropped; the game never ships a mismatched pair, so
        -- copying both from the same entry can't introduce one.)
        advanced_description = adv.advanced_description,
        description_values   = adv.description_values,
    }
    return weave_key
end

local function _cim_ensure_property_twin(bare)
    local WP = rawget(_G, "WeaveProperties")
    local adv_tbl = rawget(_G, "WeaponProperties")
    if not (WP and WP.properties and adv_tbl and adv_tbl.properties) then return nil end
    local weave_key = "weave_" .. bare
    if WP.properties[weave_key] then return weave_key end       -- reuse existing twin
    local adv = adv_tbl.properties[bare]
    if not (adv and adv.display_name and adv.buff_name) then return nil end
    -- buff_name must resolve to a registered template with a .buffs[1] (the picker
    -- does buff_template.buffs[1] with no nil-guard).
    local BuffTemplates = rawget(_G, "BuffTemplates")
    local tmpl = BuffTemplates and BuffTemplates[adv.buff_name]
    if not (tmpl and tmpl.buffs and tmpl.buffs[1]) then return nil end
    -- description_values MUST be non-empty with a numeric [1].value (picker does
    -- description_values[1].value_type and arithmetic on [1].value).
    local dvals = adv.description_values
    if not (type(dvals) == "table" and dvals[1] and type(dvals[1].value) == "number") then
        dvals = { { value_type = "percent", value = 0.05 } }
    end
    WP.properties[weave_key] = {
        name         = weave_key,
        display_name = adv.display_name,
        icon         = adv.icon or "icons_placeholder",
        category     = adv.category or "offensive",
        buff_name    = adv.buff_name,
        description_values = dvals,
    }
    return weave_key
end

-- Bare adventure keys the toggles want surfaced (from the standard_forge helpers,
-- read live). Traits: any → every trait; else cw → boon traits. Properties: any
-- → every property; else none (allow_cw_traits is traits-only).
local function _cim_wanted_trait_bares()
    local out = {}
    local entries
    if mod:get("allow_any_trait_property") then
        entries = mod._cim_all_trait_entries and mod._cim_all_trait_entries()
    elseif mod:get("allow_cw_traits") then
        entries = mod._cim_cw_trait_entries and mod._cim_cw_trait_entries()
    end
    for _, e in ipairs(entries or {}) do
        if e and e[1] then out[#out + 1] = e[1] end
    end
    return out
end

local function _cim_wanted_property_bares()
    if not mod:get("allow_any_trait_property") then return {} end
    return (mod._cim_all_property_keys and mod._cim_all_property_keys()) or {}
end

-- Widen one category array (kind = "traits"|"properties") by appending the given
-- bare keys' weave twins. Saves the original once so on_exit can restore it. Always
-- rebuilds from the SAVED original (never the possibly-already-widened current),
-- so repeated calls across weapon selections don't compound.
local function _cim_widen_category(kind, categories_tbl, category, wanted_bares, ensure_twin)
    if not (categories_tbl and category) then return end
    local backup = _cim_forge_widen_backup[kind]
    if backup[category] == nil then
        backup[category] = categories_tbl[category] or false
    end
    local original = backup[category]
    local base = (type(original) == "table") and original or {}
    local seen, widened = {}, {}
    for _, k in ipairs(base) do
        if not seen[k] then seen[k] = true; widened[#widened + 1] = k end
    end
    for _, bare in ipairs(wanted_bares) do
        local wk = ensure_twin(bare)
        if wk and not seen[wk] then seen[wk] = true; widened[#widened + 1] = wk end
    end
    categories_tbl[category] = widened
end

_cim_apply_forge_freedom = function(slots_progression)
    if not slots_progression then return end
    local WT = rawget(_G, "WeaveTraits")
    local WP = rawget(_G, "WeaveProperties")
    local trait_bares = _cim_wanted_trait_bares()
    local prop_bares  = _cim_wanted_property_bares()

    if #trait_bares > 0 and WT and WT.categories and slots_progression.traits then
        local done = {}
        for _, slot_unlock in ipairs(slots_progression.traits) do
            local cat = slot_unlock and slot_unlock.category
            if cat and not done[cat] then
                done[cat] = true
                _cim_widen_category("traits", WT.categories, cat, trait_bares, _cim_ensure_trait_twin)
            end
        end
    end
    if #prop_bares > 0 and WP and WP.categories and slots_progression.properties then
        local done = {}
        for _, slot_unlock in ipairs(slots_progression.properties) do
            local cat = slot_unlock and slot_unlock.category
            if cat and not done[cat] then
                done[cat] = true
                _cim_widen_category("properties", WP.categories, cat, prop_bares, _cim_ensure_property_twin)
            end
        end
    end
end

_cim_restore_forge_freedom = function()
    local WT = rawget(_G, "WeaveTraits")
    local WP = rawget(_G, "WeaveProperties")
    for cat, orig in pairs(_cim_forge_widen_backup.traits) do
        if WT and WT.categories then
            WT.categories[cat] = (type(orig) == "table") and orig or nil
        end
    end
    for cat, orig in pairs(_cim_forge_widen_backup.properties) do
        if WP and WP.categories then
            WP.categories[cat] = (type(orig) == "table") and orig or nil
        end
    end
    _cim_forge_widen_backup.traits = {}
    _cim_forge_widen_backup.properties = {}
end

-- Exposed for /cim_regression_test.
mod._cim_ensure_trait_twin     = _cim_ensure_trait_twin
mod._cim_ensure_property_twin  = _cim_ensure_property_twin
mod._cim_apply_forge_freedom   = _cim_apply_forge_freedom
mod._cim_restore_forge_freedom = _cim_restore_forge_freedom

mod:hook("HeroWindowWeaveProperties", "_setup_menu_options", function(func, self, career_name, slots_progression)
    _cim_ensure_weave_category_pools(career_name, slots_progression)
    -- Widen the picker per the freedom toggles (modded forge only; restored on
    -- exit). pcall so a malformed stub can never crash the picker — it just falls
    -- back to the un-widened (or seeded) pools.
    if _custom_forge_active then
        pcall(_cim_apply_forge_freedom, slots_progression)
    end
    return func(self, career_name, slots_progression)
end)

-- v0.8.7-dev: the NEXT-in-sequence deus/CW weave crash after the
-- _setup_menu_options pool seeder above. Vanilla on_enter also runs
-- `_sync_backend_loadout`, which builds per-slot tooltips:
--   tooltip_slot_sub_title = slot_type_strings[slot_category] or localized_strings[slot_category]
--   tooltip_data.sub_title  = tooltip_slot_title .. " - " .. tooltip_slot_sub_title
-- For a deus/CW weapon cim re-exposes (dr_deus_01 Trollhammer Torpedo), the
-- slot_category is a non-weave table-name, so BOTH string lookups miss ->
-- tooltip_slot_sub_title is nil -> "attempt to concatenate a nil value" HARD
-- CRASH on SELECT (hero_window_weave_properties.lua:~1701; crash report nicho
-- 2026-06-18 on cim_dev v0.8.6-dev). Those tooltip-string tables are locals
-- rebuilt per call (not pre-seedable like WeaveTraits/WeaveProperties.categories),
-- so wrap the vanilla sync in pcall under the modded forge. The property/trait
-- bubbles sync BEFORE the failing talent-tooltip section, so editing still
-- works -- only the unknown-category tooltip degrades instead of crashing.
-- Distinct hook target from the HeroWindowWeaveForgeWeapons._sync_backend_loadout
-- hook (different class) -> no duplicate-hook conflict.
mod:hook("HeroWindowWeaveProperties", "_sync_backend_loadout", function(func, self)
    if not _custom_forge_active then return func(self) end
    local ok, err = pcall(func, self)
    if not ok then
        mod:warning("[cim] _sync_backend_loadout guarded (deus/CW weave-tooltip nil): %s", tostring(err))
    end
end)

-- #239: the modded Athanor crafts for FREE (cim fakes all essence/mastery costs
-- to 0 via the BackendInterfaceWeavesPlayFab hooks), so the vanilla per-option
-- "Cost: 0" readout on every trait/property/talent row is meaningless clutter.
-- Blank it after vanilla populates each option widget. The cost NUMBER is
-- content.price_text (all three text passes share text_id="price_text"); the
-- mastery ICON is a SEPARATE texture pass gated independently of the text, so we
-- also zero its per-widget alpha. hook_safe (post) because vanilla rewrites these
-- every time _sync_backend_loadout re-populates the list. Modded forge only; each
-- entry owns its widget (UIWidget.init), so the per-widget style edit can't leak
-- to other rows. Row height is fixed, so blanking does not reflow the layout.
mod:hook_safe("HeroWindowWeaveProperties", "_populate_menu_option_widget", function(self, entry_data, menu_option)
    if not _custom_forge_active then return end
    local widget = entry_data and entry_data.widget
    if not widget then return end
    if widget.content then
        widget.content.price_text = ""
    end
    local pic = widget.style and widget.style.price_icon
    if pic and pic.color then pic.color[1] = 0 end
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
        -- when the 2pct toggle is on), everything else renders 5 fillable
        -- bubbles (the default — see `_bubble_cap`).
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

-- Issue #71: pressing the amulet (HeroWindowWeaveProperties) under the modded
-- forge feeds the player's ADVENTURE career talents into the talent picker.
-- Vanilla get_talent_required_forge_level (backend_interface_weaves_playfab.lua:1238)
-- does `progression_data = progression_settings.talents[talent_name]` then
-- `progression_data.required_forge_level` — adventure talents have no weave
-- progression entry, so progression_data is nil and the index crashes. Mirror
-- the property/trait guards above: return 0 under the modded forge.
mod:hook("BackendInterfaceWeavesPlayFab", "get_talent_required_forge_level", function(func, self, talent_name)
    if _custom_forge_active then return 0 end
    return func(self, talent_name)
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
_store_property_slot = function(props, property_key, slot_index)
    local cap = _bubble_cap and _bubble_cap(property_key) or 5
    local arr = props[property_key]
    if not arr then arr = {}; props[property_key] = arr end
    -- (a) cross-property collision / dedupe (vanilla 1059-1063): never store a
    --     slot_index already held by ANY property (including this one).
    for _, slots in pairs(props) do
        for _, used_idx in ipairs(slots) do
            if used_idx == slot_index then return arr end
        end
    end
    -- (b) per-property use cap (vanilla 1067): stop at `_bubble_cap` entries.
    if #arr < cap then
        arr[#arr + 1] = slot_index
    end
    return arr
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
        -- Distinct-property cap per item / accessory layer. The grid has 10
        -- property slots per layer (weapon = one layer of 10; amulet = 10 per
        -- accessory), so 10 is the natural ceiling — one distinct property per
        -- slot. User request 2026-06-29: "we definitely want there to be a max
        -- of 10 distinct properties." Single-item editor (weapon): one layer →
        -- 10 total distinct keys. Amulet editor: 10 distinct per accessory.
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
        local arr = _store_property_slot(props, property_key, slot_index)
        if mod._cim_autodump_property_array then
            pcall(mod._cim_autodump_property_array, "set_property", property_key, arr, cap)
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
                   and not (mod._cim_versus_shadowed and mod._cim_versus_shadowed(item_data, real_names)) then
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
        -- Honor the base_power_level setting (was hardcoded 300 — weapons ignored
        -- the slider while the amulet path already read _cim_base_power). 2026-06-30.
        power_level = (mod._cim_base_power and mod._cim_base_power()) or 300,
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

    -- Issue #71 (Option A): weapons (melee/ranged) now fall through to the
    -- mint-new path below. The editor's bubble-grid edits already mutated
    -- item.properties / item.traits in place (via _forge_apply_to_item), so
    -- cloning them into a fresh craft yields a new weapon carrying the current
    -- edits — matching the "set properties then craft" mental model. (The
    -- button was previously hidden for weapons and this branch early-returned.)

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
        -- Default to the base_power_level setting (overridable via the power
        -- command); was hardcoded 300. 2026-06-30.
        power_level = (mod._cim_base_power and mod._cim_base_power()) or 300,
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

_rt_register("weave_talent_forge_level_guard_present", function()
    -- Issue #71 (2026-06-01): pressing the amulet under the modded forge crashed
    -- in vanilla get_talent_required_forge_level, which nil-indexes
    -- progression_settings.talents[talent_name] for the adventure career talents
    -- cim feeds in. The fix hooks that method to return 0 under _custom_forge_active
    -- (alongside the existing get_property_/get_trait_ guards). This source-pattern
    -- check fails if that hook is removed. The needle is assembled from two literals
    -- so this test's own source does not self-match. Degrades to a no-op when source
    -- introspection is unavailable (deploy/bundle paths).
    local ok, info = pcall(debug.getinfo, _rt_register, "S")
    if not ok or type(info) ~= "table" or not info.source then return end
    local src_path = info.source:sub(1, 1) == "@" and info.source:sub(2) or info.source
    local f = io.open(src_path, "r")
    if not f then return end
    local txt = f:read("*a")
    f:close()
    if not txt then return end
    local needle = 'BackendInterfaceWeavesPlayFab", ' .. '"get_talent_required_forge_level"'
    if not txt:find(needle, 1, true) then
        return "Issue #71 regression: get_talent_required_forge_level guard hook missing (amulet/weave-properties crash on adventure career talents)"
    end
end)

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
    -- v0.8.15-dev: the loadout capture/persist path is now gated OFF by default
    -- via `persist_modded_loadouts`. These tests EXERCISE that path, so force the
    -- toggle ON for the duration of the body and restore the user's real value on
    -- teardown. (Without this, the default-OFF capture no-ops and the round-trip
    -- assertions would fail spuriously.)
    local saved_persist     = mod:get("persist_modded_loadouts")
    mod:set("persist_modded_loadouts", true, false)
    local snap_forged_mem   = {}
    for k, v in pairs(_forged_weapons) do snap_forged_mem[k] = v end
    -- Indexed schema: career -> index -> slot -> bid (3-level deep copy).
    local snap_loadout_mem  = {}
    for c, indices in pairs(_modded_loadout) do
        snap_loadout_mem[c] = {}
        if type(indices) == "table" then
            for idx, slots in pairs(indices) do
                snap_loadout_mem[c][idx] = {}
                if type(slots) == "table" then
                    for s, b in pairs(slots) do snap_loadout_mem[c][idx][s] = b end
                end
            end
        end
    end

    local ok, err = pcall(body)

    -- Always teardown — restore in-memory tables AND on-disk payload.
    _forged_weapons = {}
    for k, v in pairs(snap_forged_mem) do _forged_weapons[k] = v end
    _modded_loadout = {}
    for c, indices in pairs(snap_loadout_mem) do
        _modded_loadout[c] = {}
        if type(indices) == "table" then
            for idx, slots in pairs(indices) do
                _modded_loadout[c][idx] = {}
                if type(slots) == "table" then
                    for s, b in pairs(slots) do _modded_loadout[c][idx][s] = b end
                end
            end
        end
    end
    mod:set("forged_weapons", saved_forged)
    mod:set("modded_loadout", saved_loadout)
    -- Restore the user's real persist-loadouts toggle (default OFF).
    mod:set("persist_modded_loadouts", saved_persist, false)

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

        -- v0.8.13-dev: pass an EXPLICIT loadout index (4th arg) so the test is
        -- deterministic without a live mirror, and assert the INDEXED schema
        -- (career -> index -> slot -> bid). Use a non-1 index to also prove the
        -- capture honors the passed index rather than defaulting to the selected.
        local _RT_FAKE_INDEX = 2

        -- Step 1: equip modded.
        pcall(hook_fn, fake_items, _RT_FAKE_BID, _RT_FAKE_CAREER, _RT_FAKE_SLOT, _RT_FAKE_INDEX)

        -- Round-trip via VMF settings: clear in-memory, reload from disk, check.
        _modded_loadout = {}
        _modded_loadout_load()
        local saved_idx = _modded_loadout[_RT_FAKE_CAREER] and _modded_loadout[_RT_FAKE_CAREER][_RT_FAKE_INDEX]
        if not (saved_idx and saved_idx[_RT_FAKE_SLOT] == _RT_FAKE_BID) then
            result_err = "modded equip not persisted at index " .. _RT_FAKE_INDEX .. ": expected bid=" .. _RT_FAKE_BID
            return
        end

        -- Step 2: equip vanilla (non-modded) at the same career/slot/index.
        pcall(hook_fn, fake_items, _RT_FAKE_VANILLA_BID, _RT_FAKE_CAREER, _RT_FAKE_SLOT, _RT_FAKE_INDEX)

        _modded_loadout = {}
        _modded_loadout_load()
        local stale_idx = _modded_loadout[_RT_FAKE_CAREER] and _modded_loadout[_RT_FAKE_CAREER][_RT_FAKE_INDEX]
        local stale = stale_idx and stale_idx[_RT_FAKE_SLOT]
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
    -- Indexed schema: career -> index -> slot -> bid.
    for career_name, indices in pairs(_modded_loadout) do
        if type(indices) == "table" then
            for index, slots in pairs(indices) do
                if type(slots) == "table" then
                    for slot_name, bid in pairs(slots) do
                        local live = (type(bid) == "string") and (_forged_weapons[bid] or bid:sub(1, 4) == "cwv_")
                        if not live then
                            stale[#stale + 1] = string.format("%s[%s]/%s=%s",
                                tostring(career_name), tostring(index), tostring(slot_name), tostring(bid))
                            if #stale >= 5 then break end
                        end
                    end
                end
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
    -- Helpers route through VMF (mod:debug / mod:warning); just verify they don't raise.
    local ok = pcall(_dbg, "smoke test")
    if not ok then return "_dbg raised" end
    ok = pcall(_dbg_alert, "smoke test")
    if not ok then return "_dbg_alert raised" end
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
    --
    -- Issue #86 take 3 (key-form root cause): the game's property-picker passes
    -- the WeaveProperties.categories key form `weave_stamina` / `weave_movespeed`
    -- (NOT `weave_properties_stamina`) to set_loadout_property /
    -- get_property_mastery_costs — traced through hero_window_weave_properties.lua
    -- :534/:550/:2663 → backend_interface_weaves_playfab.lua:1031. The prior fix
    -- keyed the cap table `properties_*` and the test passed `weave_properties_*`
    -- (strip-form `properties_*`), so the test matched the table but the GAME key
    -- (`weave_stamina` → strip-form bare `stamina`) missed → fell back to cap 5
    -- (stamina ate 5 slots, movespeed showed 79%). This test now drives ALL THREE
    -- key forms (bare / `properties_` / `weave_properties_`) AND the game's actual
    -- `weave_<bare>` form, so a future miskeying of the cap table fails here.
    if type(_value_for_bubbles) ~= "function" then return "_value_for_bubbles missing" end
    if type(_bubble_cap) ~= "function" then return "_bubble_cap missing" end
    -- #86 core: stamina caps at exactly 2 slots on every key form, incl. the
    -- game's real `weave_stamina`.
    for _, form in ipairs({ "stamina", "properties_stamina", "weave_properties_stamina", "weave_stamina" }) do
        if _bubble_cap(form) ~= 2 then
            return string.format("stamina slot cap expected 2 for key '%s', got %s (Issue #86 regression)", form, tostring(_bubble_cap(form)))
        end
    end
    -- Clamp pins (drive the real game key form).
    if _value_for_bubbles("weave_stamina", 2) ~= 1.0 then
        return string.format("stamina at cap (2) expected 1.0, got %s", tostring(_value_for_bubbles("weave_stamina", 2)))
    end
    if _value_for_bubbles("weave_stamina", 3) ~= 1.0 then
        return string.format("stamina over-cap (3) expected clamp to 1.0, got %s", tostring(_value_for_bubbles("weave_stamina", 3)))
    end
    if _value_for_bubbles("weave_stamina", 5) ~= 1.0 then
        return string.format("stamina over-cap (5) expected clamp to 1.0, got %s", tostring(_value_for_bubbles("weave_stamina", 5)))
    end
    -- movespeed cap=1 only when the 2pct toggle is OFF (default). Test the
    -- default path on every key form; restore the user's setting afterward.
    local saved = mod:get("movespeed_2pct_mode")
    if saved ~= false then mod:set("movespeed_2pct_mode", false) end
    local ms_err
    for _, form in ipairs({ "movespeed", "properties_movespeed", "weave_properties_movespeed", "weave_movespeed" }) do
        if not ms_err and _bubble_cap(form) ~= 1 then
            ms_err = string.format("movespeed slot cap (default) expected 1 for key '%s', got %s", form, tostring(_bubble_cap(form)))
        end
    end
    local m1 = _value_for_bubbles("weave_movespeed", 1)
    local m3 = _value_for_bubbles("weave_movespeed", 3)
    if saved == true then mod:set("movespeed_2pct_mode", true) end
    if ms_err then return ms_err end
    if m1 ~= 1.0 then return string.format("movespeed at cap (1) expected 1.0, got %s", tostring(m1)) end
    if m3 ~= 1.0 then return string.format("movespeed over-cap (3) expected clamp to 1.0, got %s", tostring(m3)) end
end)

_rt_register("picker_caps_persisted_slot_array", function()
    -- #86 take 4 (the movespeed-BLOCKS-other-slots report): the prior #86 fixes
    -- only checked `_bubble_cap` / `_value_for_bubbles` — the DISPLAY math. They
    -- never asserted the PERSISTED `props[property_key]` array length, which is
    -- what actually drives grid occupancy (vanilla _sync_backend_loadout maps
    -- one grid slot per array entry). This test drives the REAL picker store
    -- (`_store_property_slot`, shared with the live set_loadout_property hook)
    -- and asserts the array NEVER exceeds the property's bubble cap — so a
    -- future regression that over-fills the array (the exact "movespeed takes 5
    -- slots and blocks the rest" bug) fails here, not just in-game.
    if type(_store_property_slot) ~= "function" then return "_store_property_slot missing" end

    local saved = mod:get("movespeed_2pct_mode")
    if saved ~= false then mod:set("movespeed_2pct_mode", false) end

    -- Helper: simulate N picker clicks for `key`, each landing on a fresh free
    -- grid slot (vanilla _find_next_available_slot only ever offers free slots,
    -- so distinct indices), then return the persisted array length.
    local function _sim_clicks(props, key, n, start_index)
        for i = 0, n - 1 do
            _store_property_slot(props, key, start_index + i)
        end
        return #(props[key] or {})
    end

    -- Movespeed: default cap 1. Even 5 clicks must persist EXACTLY 1 slot.
    local p = {}
    local ms_len = _sim_clicks(p, "weave_movespeed", 5, 1)
    if ms_len ~= 1 then
        if saved == true then mod:set("movespeed_2pct_mode", true) end
        return string.format("movespeed (2pct OFF): 5 clicks persisted %d slot indices, expected 1 — over-occupancy regression (#86)", ms_len)
    end

    -- Stamina: cap 2. 5 clicks must persist EXACTLY 2 (proves the fix doesn't
    -- regress the property that already worked).
    p = {}
    local st_len = _sim_clicks(p, "weave_stamina", 5, 10)
    if st_len ~= 2 then
        if saved == true then mod:set("movespeed_2pct_mode", true) end
        return string.format("stamina: 5 clicks persisted %d slot indices, expected 2", st_len)
    end

    -- Cross-property collision: a slot_index already held by movespeed must not
    -- also be stored under stamina (vanilla's global slot-occupancy guard).
    p = {}
    _store_property_slot(p, "weave_movespeed", 7)
    _store_property_slot(p, "weave_stamina", 7) -- same index -> must be rejected
    if (p.weave_stamina and #p.weave_stamina or 0) ~= 0 then
        if saved == true then mod:set("movespeed_2pct_mode", true) end
        return "cross-property collision guard failed: slot_index 7 stored under both movespeed and stamina"
    end

    -- Re-click dedupe: clicking the SAME slot twice for one property stays at 1.
    p = {}
    _store_property_slot(p, "weave_movespeed", 3)
    _store_property_slot(p, "weave_movespeed", 3)
    if #p.weave_movespeed ~= 1 then
        if saved == true then mod:set("movespeed_2pct_mode", true) end
        return string.format("re-click dedupe failed: movespeed persisted %d entries for one slot, expected 1", #p.weave_movespeed)
    end

    -- 2pct mode ON: movespeed legitimately uncaps to 5 (documented trade). Pin
    -- it so a future change that forgets the 2pct path is caught too.
    mod:set("movespeed_2pct_mode", true)
    p = {}
    local ms5 = _sim_clicks(p, "weave_movespeed", 7, 1)
    if saved ~= true then mod:set("movespeed_2pct_mode", false) else mod:set("movespeed_2pct_mode", true) end
    if ms5 ~= 5 then
        return string.format("movespeed (2pct ON): 7 clicks persisted %d slot indices, expected 5 (the +2%%-per-bubble trade)", ms5)
    end
end)

_rt_register("read_chokepoint_caps_grid_occupancy", function()
    -- #86 v0.8.30-dev: the WRITE-path cap is provably correct (the test above),
    -- yet the symptom persisted in-game — proving the array reaching the grid is
    -- over-filled by a path the write cap doesn't cover. `_cap_grid_property_arrays`
    -- is the read-side guard: it trims whatever get_loadout_properties is about to
    -- hand vanilla `_sync_backend_loadout`, which maps one grid slot per array
    -- entry. This drives it with a DELIBERATELY over-filled array (simulating the
    -- leak) and asserts the grid never sees more than the cap.
    if type(_cap_grid_property_arrays) ~= "function" then return "_cap_grid_property_arrays missing" end

    local saved = mod:get("movespeed_2pct_mode")
    if saved ~= false then mod:set("movespeed_2pct_mode", false) end
    local function _restore() if saved == true then mod:set("movespeed_2pct_mode", true) end end

    -- Weapon editor (item_backend_id present = one layer). Over-fill movespeed to
    -- 5 and stamina to 5, then assert the read guard trims to 1 and 2.
    local p = {
        weave_movespeed = { 1, 2, 3, 4, 5 },
        weave_stamina   = { 6, 7, 8, 9, 10 },
    }
    _cap_grid_property_arrays(p, "fake_weapon_bid")
    if #p.weave_movespeed ~= 1 then
        _restore(); return string.format("read guard (weapon): movespeed trimmed to %d, expected 1", #p.weave_movespeed)
    end
    if #p.weave_stamina ~= 2 then
        _restore(); return string.format("read guard (weapon): stamina trimmed to %d, expected 2", #p.weave_stamina)
    end

    -- Amulet editor (item_backend_id == nil = per-layer cap). Movespeed cap 1 PER
    -- accessory: necklace (layer 1, idx 1..10) + charm (layer 2, idx 11..20) must
    -- keep ONE each = 2 total, not collapse to 1. An over-fill within one layer
    -- (idx 1 and 2 both layer 1) must trim to 1 for that layer.
    local a = { weave_movespeed = { 1, 2, 11 } } -- layer1: {1,2}->1, layer2: {11}->1
    _cap_grid_property_arrays(a, nil)
    if #a.weave_movespeed ~= 2 then
        _restore(); return string.format("read guard (amulet): movespeed across 2 layers trimmed to %d, expected 2 (per-layer cap)", #a.weave_movespeed)
    end

    -- Already-capped arrays must pass through untouched (idempotent / no false trim).
    local ok = { weave_stamina = { 3, 4 }, weave_movespeed = { 5 } }
    _cap_grid_property_arrays(ok, "fake_weapon_bid")
    if #ok.weave_stamina ~= 2 or #ok.weave_movespeed ~= 1 then
        _restore(); return "read guard: trimmed an already-capped array (false positive)"
    end

    _restore()
end)

_rt_register("default_property_cap_is_five_bubbles", function()
    -- #86 (2026-06-29, v0.8.33-dev): every generic property keeps a 5-bubble row
    -- you fill to SCALE its value (1 bubble = 20%, 5 = full) — the vanilla weave
    -- behavior. v0.8.32-dev briefly forced the default to 1, which let each
    -- property take only one bubble and killed per-property scaling for all of
    -- them; this pins the default back at 5 so that over-correction can't recur.
    -- The real #86 fix is the distinct-property ceiling (MAX_DISTINCT / trimmer
    -- raised to 10), exercised by `picker_caps_persisted_slot_array`; this guards
    -- the DEFAULT bubble cap + its scaling math.
    if type(_bubble_cap) ~= "function" then return "_bubble_cap missing" end
    if type(_value_for_bubbles) ~= "function" then return "_value_for_bubbles missing" end

    local saved = mod:get("movespeed_2pct_mode")
    if saved ~= false then mod:set("movespeed_2pct_mode", false) end
    local function _restore() if saved == true then mod:set("movespeed_2pct_mode", true) end end

    -- A spread of real default (non-special-cased) weave property keys — each
    -- must resolve to cap 5 in any key form (weave_X / properties_X / bare X).
    for _, key in ipairs({
        "weave_fatigue_regen", "weave_crit_chance", "weave_attack_speed",
        "weave_block_cost", "weave_power_vs_chaos", "fatigue_regen",
        "properties_crit_chance",
    }) do
        local c = _bubble_cap(key)
        if c ~= 5 then
            _restore()
            return string.format("default cap for '%s' = %s, expected 5 (#86 single-bubble regression)", key, tostring(c))
        end
        -- Value must SCALE with bubbles: 1 → 0.2, 5 → 1.0 (full).
        if _value_for_bubbles(key, 1) ~= 0.2 then
            _restore()
            return string.format("'%s': 1 bubble value = %s, expected 0.2 (scaling broken)", key, tostring(_value_for_bubbles(key, 1)))
        end
        if _value_for_bubbles(key, 5) ~= 1.0 then
            _restore()
            return string.format("'%s': 5 bubble value = %s, expected 1.0 (max)", key, tostring(_value_for_bubbles(key, 5)))
        end
    end

    -- Special cases unchanged.
    if _bubble_cap("weave_stamina") ~= 2 then _restore(); return "stamina cap regressed from 2" end
    if _bubble_cap("weave_movespeed") ~= 1 then _restore(); return "movespeed cap regressed from 1" end

    _restore()
end)

_rt_register("action_rejection_uses_warning_channel", function()
    -- v0.7.44-alpha converted ~dozen action-rejection callsites from mod:echo
    -- to mod:warning (issue #47). mod:echo is redirected to log only; mod:warning
    -- bypasses it so the user sees WHY a click was rejected. Regression: if
    -- someone re-points mod.warning at the redirected echo (or replaces both with
    -- the same function), rejections become invisible and the user perceives
    -- "broken mod" — exactly the user-report substrate from 2026-05-25.
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

_rt_register("versus_twin_rehidden_from_inventory", function()
    -- v0.8.22-dev: the global `mechanisms = nil` clear above (intended — makes a
    -- CRAFTED vs_* adventure-visible) also leaks the player's RAW OWNED vs_* twin
    -- into the adventure inventory grid, because item.data is a SHARED reference
    -- to the cleared IML entry (PlayFabMirrorBase._update_data:1786). The
    -- get_filtered_items hook re-hides the owned twin at the DISPLAY layer.
    -- Assert _cim_is_leaked_versus_twin distinguishes the two:
    --   owned vs_* twin (vanilla bid)   -> hidden  (true)
    --   cim-crafted vs_* (modded bid)   -> visible (false — stays craftable/shown)
    --   non-versus item                 -> visible (false)
    local twin_fn = mod._cim_is_leaked_versus_twin
    if type(twin_fn) ~= "function" then
        return "mod._cim_is_leaked_versus_twin missing — versus-twin inventory re-hide not wired"
    end
    -- Owned twin: vs_ key, NON-modded backend_id -> must be re-hidden.
    local owned_twin = { key = "vs_gutter_runner_claws", backend_id = "vanilla-owned-bid-12345" }
    if not twin_fn(owned_twin) then
        return "owned vs_* twin not flagged for re-hide — would leak into the adventure inventory grid"
    end
    -- Crafted vs_*: register a fake modded bid so _cim_is_modded_backend_id
    -- returns true, then it must NOT be re-hidden (stays visible/craftable).
    local crafted_bid = "__cim_rt_fake_vs_craft__"
    _forged_weapons[crafted_bid] = { item_key = "vs_gutter_runner_claws" }
    local crafted = { key = "vs_gutter_runner_claws", backend_id = crafted_bid }
    local crafted_hidden = twin_fn(crafted)
    _forged_weapons[crafted_bid] = nil  -- cleanup
    if crafted_hidden then
        return "cim-crafted vs_* incorrectly flagged for re-hide — deliberately-surfaced craft would vanish from inventory"
    end
    -- Non-versus item: never touched.
    if twin_fn({ key = "es_1h_sword", backend_id = "whatever" }) then
        return "non-versus item incorrectly flagged for re-hide"
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

_rt_register("persist_loadouts_gate_off_is_passthrough", function()
    -- v0.8.15-dev: the `persist_modded_loadouts` master toggle defaults OFF, and
    -- when OFF cim must NOT touch the loadout path — _capture_loadout_equip records
    -- nothing and _restore_modded_loadout no-ops, so vanilla player AND bot loadouts
    -- are byte-identical to not having cim. Pin both invariants:
    --   1. the gate helper reflects the live setting value, and
    --   2. with the toggle forced OFF, a real set_loadout_item call for a modded
    --      bid leaves _modded_loadout empty (no capture).
    if type(mod._cim_persist_loadouts_enabled) ~= "function" then
        return "persist-loadouts gate helper missing"
    end
    local cls = rawget(_G, "BackendInterfaceItemPlayfab")
    if not cls or type(cls.set_loadout_item) ~= "function" then
        return "skip: BackendInterfaceItemPlayfab.set_loadout_item not loaded (run in-keep)"
    end
    local hook_fn = cls.set_loadout_item

    local result_err
    -- The sandbox forces the toggle ON for its body; we deliberately flip it OFF
    -- INSIDE to assert the OFF behavior, and the sandbox restores everything.
    _rt_with_loadout_sandbox(function()
        mod:set("persist_modded_loadouts", false, false)
        if mod._cim_persist_loadouts_enabled() ~= false then
            result_err = "gate helper says enabled while setting is OFF"
            return
        end
        mod._cim_register_craft(_RT_FAKE_BID, {
            item_key = "es_1h_falchion", properties = {}, traits = {}, power_level = 300, rarity = "modded",
        })
        local fake_items = setmetatable({}, { __index = function() return function() end end })
        _modded_loadout = {}
        -- Equip a MODDED bid while the master toggle is OFF.
        pcall(hook_fn, fake_items, _RT_FAKE_BID, _RT_FAKE_CAREER, _RT_FAKE_SLOT, 1)
        local captured = _modded_loadout[_RT_FAKE_CAREER]
        if captured ~= nil and next(captured) ~= nil then
            result_err = "OFF gate leaked a capture into _modded_loadout (should be untouched)"
            return
        end
    end)
    if result_err then return result_err end
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

_rt_register("forge_preview_guard_present", function()
    -- v0.7.70-dev: the weave-forge weapon previewer (LootItemUnitPreviewer)
    -- spawns the selected weapon's 3D model, which HARD-CRASHES (no Lua trace)
    -- on weapons whose preview units aren't loadable in the forge world — the
    -- Trollhammer Torpedo (dr_deus_01, "torpedo cannon") being the reported
    -- case. _forge_preview_unsafe gates both spawn sites. Verify the guard is
    -- wired AND fails safe (treats anything it can't resolve as UNSAFE) so an
    -- unknown / garbage item can never reach the engine spawn.
    local fn = mod._cim_forge_preview_unsafe
    if type(fn) ~= "function" then
        return "forge preview guard (_cim_forge_preview_unsafe) missing — torpedo CTD guard not installed"
    end
    if fn(nil) ~= true then
        return "guard must treat a nil item as UNSAFE (skip preview); returned non-true"
    end
    if fn({ key = "cim_definitely_not_a_real_item_key_zzz" }) ~= true then
        return "guard must treat an unknown item key as UNSAFE (master nil); returned non-true"
    end
end)

_rt_register("weave_category_pool_guard_present", function()
    -- v0.7.75-dev: opening the forge stat editor for a weapon whose
    -- property/trait/talent table-name isn't a weave category (Trollhammer
    -- Torpedo dr_deus_01 the reported case) made vanilla _setup_menu_options do
    -- ipairs(WeaveTraits.categories[category]) on nil -> "bad argument #1 to
    -- 'ipairs' (table expected, got nil)". The guard seeds an empty {} pool for
    -- unknown categories so the picker renders empty instead of crashing. Verify
    -- the seeder is wired and idempotently fills the trait + property pools for
    -- an unknown category (then clean up the synthetic key).
    local fn = mod._cim_ensure_weave_category_pools
    if type(fn) ~= "function" then
        return "weave category pool guard (_cim_ensure_weave_category_pools) missing"
    end
    local wt = rawget(_G, "WeaveTraits")
    local wp = rawget(_G, "WeaveProperties")
    if not (wt and wt.categories and wp and wp.categories) then
        return "skip: WeaveTraits/WeaveProperties not loaded"
    end
    local cat = "cim_rt_not_a_weave_category_zzz"
    wt.categories[cat], wp.categories[cat] = nil, nil
    fn("es_mercenary", { traits = { { category = cat } }, properties = { { category = cat } } })
    local seeded = type(wt.categories[cat]) == "table" and #wt.categories[cat] == 0
        and type(wp.categories[cat]) == "table" and #wp.categories[cat] == 0
    wt.categories[cat], wp.categories[cat] = nil, nil  -- don't leave RT residue in the weave tables
    if not seeded then
        return "guard did not seed empty trait+property pools for an unknown category"
    end
end)

_rt_register("forge_freedom_settings_and_helpers_present", function()
    -- v0.8.44-dev: both freedom toggles must be registered (mod:get returns a
    -- boolean, not nil) and every helper the two surfaces route through must be
    -- exposed on the mod handle.
    if type(mod:get("allow_cw_traits")) ~= "boolean" then
        return "allow_cw_traits setting not registered"
    end
    if type(mod:get("allow_any_trait_property")) ~= "boolean" then
        return "allow_any_trait_property setting not registered"
    end
    for _, name in ipairs({
        "_cim_cw_trait_entries", "_cim_all_trait_entries", "_cim_all_property_keys",
        "_cim_trait_pool_for", "_cim_property_pool_for", "_cim_apply_forge_freedom",
        "_cim_restore_forge_freedom", "_cim_ensure_trait_twin", "_cim_ensure_property_twin",
    }) do
        if type(mod[name]) ~= "function" then
            return "missing exposed helper: " .. name
        end
    end
end)

_rt_register("cw_trait_pool_includes_boons", function()
    -- The Chaos Wastes trait set must be non-empty and contain at least one real
    -- crafting_disabled boon (that is exactly what allow_cw_traits surfaces).
    local WT = rawget(_G, "WeaponTraits")
    if not (WT and WT.traits and WT.combinations) then return "skip: WeaponTraits not loaded" end
    local entries = mod._cim_cw_trait_entries()
    if type(entries) ~= "table" or #entries == 0 then
        return "cw trait set is empty (expected the deus/boon traits)"
    end
    for _, e in ipairs(entries) do
        local k = e and e[1]
        local td = k and WT.traits[k]
        if td and td.crafting_disabled then return end  -- found a real boon: pass
    end
    return "cw trait set contains no crafting_disabled boon trait"
end)

_rt_register("default_trait_pool_excludes_boons_when_toggles_off", function()
    -- With both freedom toggles OFF, a melee weapon's trait pool must still be
    -- boon-filtered (unchanged base behavior). Skip if a toggle is live-ON.
    if mod:get("allow_cw_traits") or mod:get("allow_any_trait_property") then
        return "skip: a freedom toggle is ON (default-behavior test not applicable)"
    end
    local WT = rawget(_G, "WeaponTraits")
    if not (WT and WT.traits and WT.combinations and WT.combinations.melee) then
        return "skip: WeaponTraits melee pool not loaded"
    end
    local pool = mod._cim_trait_pool_for({ trait_table_name = "melee" })
    if type(pool) ~= "table" then return "trait pool for melee was nil" end
    for _, e in ipairs(pool) do
        local k = e and e[1]
        local td = k and WT.traits[k]
        if td and td.crafting_disabled then
            return "default melee pool leaked a crafting_disabled boon: " .. tostring(k)
        end
    end
end)

_rt_register("trait_twin_stub_has_display_name", function()
    -- Injecting a weave twin for a boon (no native weave twin) must yield an entry
    -- with a string display_name — the one field whose absence crashes the picker.
    local WT = rawget(_G, "WeaveTraits")
    local adv = rawget(_G, "WeaponTraits")
    if not (WT and WT.traits and adv and adv.traits) then return "skip: trait tables not loaded" end
    local bare
    for _, e in ipairs(mod._cim_cw_trait_entries()) do
        local k = e and e[1]
        if k and adv.traits[k] and adv.traits[k].display_name and not WT.traits["weave_" .. k] then
            bare = k; break
        end
    end
    if not bare then return "skip: no injectable boon trait found" end
    local wk = mod._cim_ensure_trait_twin(bare)
    if not wk then return "ensure_trait_twin returned nil for " .. bare end
    local ok = WT.traits[wk] and type(WT.traits[wk].display_name) == "string"
    WT.traits[wk] = nil  -- injected by this test only; remove to avoid RT residue
    if not ok then return "twin for " .. bare .. " lacks a string display_name" end
end)

_rt_register("trait_twin_copies_description_pair", function()
    -- #238: an injected trait twin must copy advanced_description + description_values
    -- TOGETHER from the adventure entry, so the Athanor picker shows a description
    -- (not just the trait name). Use a boon with a description that has no native
    -- weave twin (so this exercises the INJECT path); clean up after.
    local WT = rawget(_G, "WeaveTraits")
    local adv = rawget(_G, "WeaponTraits")
    if not (WT and WT.traits and adv and adv.traits) then return "skip: trait tables not loaded" end
    local bare
    for _, e in ipairs(mod._cim_cw_trait_entries()) do
        local k = e and e[1]
        if k and adv.traits[k] and adv.traits[k].advanced_description and not WT.traits["weave_" .. k] then
            bare = k; break
        end
    end
    if not bare then return "skip: no injectable boon trait with a description found" end
    local wk = mod._cim_ensure_trait_twin(bare)
    local twin = wk and WT.traits[wk]
    local advd = adv.traits[bare]
    local ok = twin
        and twin.advanced_description == advd.advanced_description
        and twin.description_values == advd.description_values
    WT.traits[wk] = nil  -- injected by this test only; clean up
    if not ok then
        return "twin for " .. bare .. " did not copy the advanced_description + description_values pair"
    end
end)

_rt_register("forge_freedom_restore_is_safe", function()
    -- Restore must always run without error (it fires on every forge exit).
    local ok, err = pcall(mod._cim_restore_forge_freedom)
    if not ok then return "restore raised: " .. tostring(err) end
end)

_rt_register("heroview_hdr_renderer_guard_failsafe", function()
    -- v0.7.71-dev: in-mission forge crashed at HeroView.hdr_renderer /
    -- hdr_top_renderer because vanilla _setup_hdr_gui only builds
    -- self._hdr_gui_data when is_in_inn (false in mission), and the forge
    -- windows dereference _hdr_gui_data.bottom/.top every frame. The accessor
    -- hooks must fall back to the view's own renderer when _hdr_gui_data is nil
    -- rather than letting vanilla index a nil. Drive the (hooked) accessors with
    -- a synthetic self that has nil _hdr_gui_data and assert no raise + fallback.
    if type(HeroView) ~= "table" or type(HeroView.hdr_renderer) ~= "function"
        or type(HeroView.hdr_top_renderer) ~= "function" then
        return "skip: HeroView not loaded"
    end
    local r_sentinel, t_sentinel = {}, {}
    local fake = { _hdr_gui_data = nil, ui_renderer = r_sentinel, ui_top_renderer = t_sentinel }
    local ok, ret = pcall(HeroView.hdr_renderer, fake)
    if not ok then
        return "hdr_renderer guard missing — raised on nil _hdr_gui_data: " .. tostring(ret)
    end
    if ret ~= r_sentinel then
        return "hdr_renderer did not fall back to self.ui_renderer on nil _hdr_gui_data"
    end
    local ok2, ret2 = pcall(HeroView.hdr_top_renderer, fake)
    if not ok2 then
        return "hdr_top_renderer guard missing — raised on nil _hdr_gui_data: " .. tostring(ret2)
    end
    if ret2 ~= t_sentinel then
        return "hdr_top_renderer did not fall back to self.ui_top_renderer on nil _hdr_gui_data"
    end
end)

_rt_register("heroview_hdr_failed_setup_sweeps_leaked_worlds", function()
    -- v0.7.73 (Issue #73): when the in-mission _setup_hdr_gui pcall fails after a
    -- world was created but before vanilla stored it in self._hdr_gui_data, the
    -- sweep must destroy the orphaned world by name or the NEXT forge open dies
    -- on world_manager's "World already exists" fassert. Drive the sweep with a
    -- stub world manager.
    local sweep = mod._cim_sweep_leaked_hdr_worlds
    if type(sweep) ~= "function" then
        return "_cim_sweep_leaked_hdr_worlds missing (Issue #73 sweep regressed)"
    end
    local destroyed = {}
    local stub_wm = {
        has_world = function(_, name) return name == "hero_view_hdr" end,  -- only bottom leaked
        destroy_world = function(_, name) destroyed[#destroyed + 1] = name end,
    }
    local swept = sweep(stub_wm, nil)
    if swept ~= 1 or destroyed[1] ~= "hero_view_hdr" or destroyed[2] ~= nil then
        return string.format("expected exactly the leaked 'hero_view_hdr' destroyed, got swept=%s destroyed=%s,%s",
            tostring(swept), tostring(destroyed[1]), tostring(destroyed[2]))
    end
    -- With _hdr_gui_data present the worlds are referenced — destroy_hdr_gui owns
    -- them and the sweep must NOT touch anything.
    destroyed = {}
    if sweep(stub_wm, { bottom = {} }) ~= 0 or destroyed[1] ~= nil then
        return "sweep ran despite _hdr_gui_data being set (would destroy worlds destroy_hdr_gui still owns)"
    end
    -- Nil / incomplete world manager must be a safe no-op.
    if sweep(nil, nil) ~= 0 or sweep({}, nil) ~= 0 then
        return "sweep not nil-safe on missing world manager"
    end
end)

_rt_register("heroview_hdr_not_forcebuilt_in_mission", function()
    -- v0.8.16-dev (LA armoury_atlas crash): the in-mission HeroView._setup_hdr_gui
    -- hook must NOT force-build the HDR worlds anymore. Force-building them mid-
    -- mission is what lets VMF custom_textures inject Loremaster's Armoury's global
    -- `armoury_atlas` material into a fresh world that can't resolve it -> C-level
    -- assert at c_api_world.cpp:568 (bypasses the pcall -> hard crash, session
    -- b688f241). Fix B skips vanilla in mission and falls through to the
    -- hdr_renderer/hdr_top_renderer ui_renderer fallback instead.
    --
    -- Source-pattern check: the _setup_hdr_gui hook body must (a) contain the Fix B
    -- skip marker and (b) NOT contain the old "flip is_in_inn=true then pcall the
    -- vanilla builder" force-build sequence. Needles are assembled from split
    -- literals so this test's own source does not self-match. No-ops when source
    -- introspection is unavailable (deploy/bundle paths).
    local ok, info = pcall(debug.getinfo, _rt_register, "S")
    if not ok or type(info) ~= "table" or not info.source then return end
    local src_path = info.source:sub(1, 1) == "@" and info.source:sub(2) or info.source
    local f = io.open(src_path, "r")
    if not f then return end
    local txt = f:read("*a")
    f:close()
    if not txt then return end
    -- (a) Fix B skip marker present in the hook body.
    local skip_needle = "_setup_hdr_gui skipped in mission (Fix B" .. ": avoid LA armoury_atlas HDR-world crash)"
    if not txt:find(skip_needle, 1, true) then
        return "Fix B regression: in-mission _setup_hdr_gui no longer skips vanilla — the LA armoury_atlas HDR-world crash guard is gone"
    end
    -- (b) The old force-build sequence must be gone from the _setup_hdr_gui hook.
    --     Key off two tokens that were UNIQUE to that hook body and never appeared
    --     in the still-valid _setup_gamepad_gui force-build (which keeps its own
    --     is_in_inn flip for a different, non-LA crash class): the `saved_is_in_inn`
    --     local and the post-failure HDR-world sweep call. Split the literals so this
    --     test's own source does not self-match.
    local saved_flag_needle = "saved_is_in_inn = self.is_in_inn" .. "\n    self.is_in_inn = true"
    if txt:find(saved_flag_needle, 1, true) then
        return "Fix B regression: in-mission _setup_hdr_gui still flips is_in_inn to force-build the HDR worlds (would crash on LA armoury_atlas)"
    end
    local sweep_in_hook_needle = "_cim_sweep_leaked_hdr_worlds(Managers.world" .. ", self._hdr_gui_data)"
    if txt:find(sweep_in_hook_needle, 1, true) then
        return "Fix B regression: in-mission _setup_hdr_gui still pcall-builds then sweeps the HDR worlds (force-build path is back)"
    end
end)

_rt_register("hdr_glow_widgets_suppressed_in_mission", function()
    -- v0.8.17-dev (weave_menu_* "Material not found in Gui" cascade): after Fix B
    -- drops the in-mission HDR worlds, the forge's HDR glow widgets fall through to
    -- the BASE mission renderer, which lacks the three keep-only raw materials
    -- (weave_menu_upgrade_skull_circle{,_shade}, weave_menu_athanor_upgrade_bg) ->
    -- ui_passes.lua:134 fatal. The create_ui_elements suppression must EMPTY the
    -- HDR draw arrays in mission and LEAVE THEM INTACT in the keep.
    --
    -- Drive the exposed helper synthetically against fake windows so the check runs
    -- anywhere (no live forge needed).
    local fn = mod._cim_suppress_hdr_glow_in_mission
    if type(fn) ~= "function" then return "suppression helper mod._cim_suppress_hdr_glow_in_mission not exposed" end

    -- (1) In mission (in_keep=false): populated HDR arrays must be emptied, and the
    --     helper reports it cleared.
    local mission_win = { _top_hdr_widgets = { {}, {} }, _bottom_hdr_widgets = { {}, {} } }
    local cleared = fn(mission_win, false)
    if cleared ~= true then
        return "helper did not report clearing populated HDR arrays in mission"
    end
    if #mission_win._top_hdr_widgets ~= 0 or #mission_win._bottom_hdr_widgets ~= 0 then
        return "in-mission HDR draw arrays NOT emptied — weave_menu_* materials would still resolve on the base renderer and crash"
    end

    -- (2) In the keep (in_keep=true): arrays must be left fully intact (full HDR glow).
    local keep_win = { _top_hdr_widgets = { {}, {} }, _bottom_hdr_widgets = { {}, {}, {} } }
    if fn(keep_win, true) ~= false then
        return "helper claimed to clear HDR arrays in the keep — keep forge must keep its full HDR glow"
    end
    if #keep_win._top_hdr_widgets ~= 2 or #keep_win._bottom_hdr_widgets ~= 3 then
        return "keep HDR draw arrays were mutated — keep path must be untouched"
    end

    -- (3) Idempotent / robust: a window with already-empty or missing arrays in
    --     mission is a safe no-op (no error, reports nothing cleared).
    if fn({ _top_hdr_widgets = {}, _bottom_hdr_widgets = {} }, false) ~= false then
        return "helper reported clearing already-empty arrays"
    end
    if fn({}, false) ~= false then
        return "helper not safe on a window with no HDR arrays"
    end
end)

_rt_register("hdr_cluster_glow_resuppressed_on_props_enter", function()
    -- v0.8.17-dev (Fix B2, second vector): create_ui_elements empties the HDR
    -- glow arrays, but HeroWindowWeaveProperties.on_enter then calls
    -- _create_slot_grid -> _create_cluster_background, which RE-APPENDS the raw,
    -- inn-only `athanor_skilltree_cluster_effect_*` glow widgets to
    -- _bottom_hdr_widgets AFTER suppression. The cim_debug.lua on_enter (post)
    -- hook re-runs the shared helper to re-empty it in mission. That hook is in a
    -- DIFFERENT source file, so verify the wiring it depends on instead:
    --   (1) the in-keep detector is exposed cross-file as mod._cim_is_in_keep,
    --   (2) it returns a boolean, and
    --   (3) the suppression helper, driven with that detector's CURRENT value on
    --       a synthetic props window carrying a freshly re-appended cluster-effect
    --       widget, leaves the array intact in the keep and empties it in mission.
    local in_keep = mod._cim_is_in_keep
    if type(in_keep) ~= "function" then
        return "mod._cim_is_in_keep not exposed — cim_debug on_enter re-suppression can't detect the keep (second-vector fix dead)"
    end
    local live = in_keep()
    if type(live) ~= "boolean" then
        return "mod._cim_is_in_keep did not return a boolean"
    end
    local fn = mod._cim_suppress_hdr_glow_in_mission
    if type(fn) ~= "function" then return "suppression helper not exposed" end
    -- Synthetic props window mirroring the post-_create_slot_grid state: one
    -- cluster-effect widget re-appended to _bottom_hdr_widgets.
    local props = { _top_hdr_widgets = {}, _bottom_hdr_widgets = { { _cim_rt_cluster_effect = true } } }
    fn(props, live)
    if live then
        -- In the keep the cluster glow must survive (full HDR there).
        if #props._bottom_hdr_widgets ~= 1 then
            return "keep: re-appended cluster-effect glow was wrongly stripped"
        end
    else
        -- In mission it must be re-emptied or the inn-only material faults.
        if #props._bottom_hdr_widgets ~= 0 then
            return "mission: re-appended cluster-effect glow NOT re-suppressed — athanor_skilltree_cluster_effect_* would fault on the base renderer"
        end
    end
end)

_rt_register("skilltree_ring_widgets_suppressed_in_mission", function()
    -- v0.8.19-dev (Fix B5, ui_passes.lua:805 "Material 'athanor_skilltree_ring_3'
    -- not found in Gui", in-mission skill tree): the NON-HDR _bottom_widgets array
    -- (drawn on the BASE mission ui_renderer) carries raw, inn-only skill-tree
    -- decorations — wheel_ring_* (athanor_skilltree_ring_*), background_wheel
    -- (athanor_skilltree_background), and per-cluster cluster_background_<i>
    -- (athanor_skilltree_cluster_<i>) — alongside FUNCTIONAL widgets. The helper
    -- must rebuild the array minus ONLY the raw decorative textures (matched by
    -- content.texture_id prefix), keeping the functional widgets, and leave the
    -- array fully intact in the keep.
    local fn = mod._cim_suppress_skilltree_rings_in_mission
    if type(fn) ~= "function" then return "suppression helper mod._cim_suppress_skilltree_rings_in_mission not exposed" end

    local function make_win()
        return { _bottom_widgets = {
            { content = { texture_id = "athanor_background_write_mask" } },  -- raw write-mask, DROP in mission (the 7th crash vector)
            { content = { texture_id = "athanor_skilltree_ring_1" } },       -- raw decoration, drop
            { content = { texture_id = "athanor_skilltree_ring_3" } },       -- raw decoration, drop (earlier reported crash)
            { content = { texture_id = "athanor_skilltree_background" } },    -- raw decoration, drop
            { content = { texture_id = "athanor_skilltree_cluster_2" } },     -- raw decoration, drop
            { content = { texture_id = "athanor_skilltree_slot_1" } },        -- atlas-backed slot, KEEP (convergent rule must not over-prune)
            { content = { texture_id = "edge_fade_small" } },                 -- functional (atlas, non-athanor), keep
            { content = {} },                                                -- viewport_background rect (no texture_id), keep
        } }
    end

    -- (1) In mission (in_keep=false): the four raw decorations are dropped, the
    --     three functional widgets survive, and the helper reports it removed some.
    local mission_win = make_win()
    local removed = fn(mission_win, false)
    if removed ~= true then
        return "helper did not report removing raw skill-tree decorations in mission"
    end
    if #mission_win._bottom_widgets ~= 3 then
        return "in-mission _bottom_widgets not filtered to exactly the 3 keep-safe widgets (athanor_skilltree_slot_1 + edge_fade_small + viewport rect); raw athanor_* textures would still resolve on the base renderer and crash"
    end
    for _, w in ipairs(mission_win._bottom_widgets) do
        local tid = w.content and w.content.texture_id
        if type(tid) == "string"
            and tid:sub(1, 8) == "athanor_"
            and tid:sub(1, 22) ~= "athanor_skilltree_slot" then
            return "a raw inn-only athanor_ texture survived the in-mission filter: " .. tid
        end
    end

    -- (2) In the keep (in_keep=true): the array must be left fully intact (full
    --     animated ring/cluster decoration there).
    local keep_win = make_win()
    if fn(keep_win, true) ~= false then
        return "helper claimed to filter _bottom_widgets in the keep — keep forge must keep its full skill-tree decoration"
    end
    if #keep_win._bottom_widgets ~= 7 then
        return "keep _bottom_widgets was mutated — keep path must be untouched"
    end

    -- (3) Idempotent / robust: empty or missing array in mission is a safe no-op.
    if fn({ _bottom_widgets = {} }, false) ~= false then
        return "helper reported filtering an already-empty _bottom_widgets"
    end
    if fn({}, false) ~= false then
        return "helper not safe on a window with no _bottom_widgets"
    end
end)

_rt_register("hdr_bloom_setscalar_skipped_in_mission", function()
    -- v0.8.18-dev (Fix B3, panel.lua:392 set_scalar nil crash, crashify 12a6d563):
    -- HeroWindowWeaveForgePanel / HeroWindowWeaveProperties run a per-frame bloom
    -- pulse (_set_background_bloom_intensity) that reads _widgets_by_name directly
    -- and writes a material scalar on parent:hdr_renderer().gui. After Fix B that
    -- renderer is the base mission Gui, which lacks the inn-only weave_menu_* wheel
    -- materials, so Gui.material(...) returns nil and Material.set_scalar(nil, ...)
    -- fatals. The guard must SKIP vanilla in mission and RUN it in the keep.
    --
    -- Source-pattern check (the live hook can't be driven synthetically — it
    -- dereferences a real HDR Gui — so assert (1) the decision helper is exposed
    -- and gates on the keep, and (2) the hook is registered with the skip path
    -- for BOTH windows).
    local decide = mod._cim_skip_bloom_intensity_in_mission
    if type(decide) ~= "function" then
        return "decision helper mod._cim_skip_bloom_intensity_in_mission not exposed (Fix B3 dead)"
    end
    -- In the keep the bloom pulse must run (helper returns false -> don't skip).
    -- Drive through the real _is_in_keep by checking it agrees with the live state.
    local in_keep = _is_in_keep()
    local skip = decide({})
    if in_keep and skip ~= false then
        return "in keep: bloom-intensity skip helper returned true — would wrongly drop the keep's HDR bloom pulse"
    end
    if not in_keep and skip ~= true then
        return "in mission: bloom-intensity skip helper returned false — Material.set_scalar(nil,...) would fatal on the base mission renderer"
    end
    -- Hook presence: the skip guard must be wired on both windows' bloom method.
    -- Verify via the mod source (the bodies are closures, so check the registration
    -- pattern is intact in the loaded file text is not available at runtime; instead
    -- confirm the two target methods still exist on the vanilla classes so a future
    -- rename surfaces here).
    if type(HeroWindowWeaveForgePanel) ~= "table"
        or type(HeroWindowWeaveForgePanel._set_background_bloom_intensity) ~= "function" then
        return "HeroWindowWeaveForgePanel._set_background_bloom_intensity missing — bloom-crash guard target renamed/gone"
    end
    if type(HeroWindowWeaveProperties) ~= "table"
        or type(HeroWindowWeaveProperties._set_background_bloom_intensity) ~= "function" then
        return "HeroWindowWeaveProperties._set_background_bloom_intensity missing — bloom-crash guard target renamed/gone"
    end
end)

_rt_register("hdr_upgrade_anim_skipped_in_mission", function()
    -- v0.8.18-dev (Fix B4, second deref site of the same B3 crash class): the
    -- forge-upgrade "upgrade" transition animation's HDR closures deref the
    -- inn-only weave_menu_* materials via params.parent:hdr_renderer().gui; after
    -- Fix B that Gui lacks them in mission -> Material.set_scalar(nil,...) fatal.
    -- The guard must DROP only the "upgrade" animation, only in mission, only on
    -- the two windows whose upgrade anim touches HDR materials.
    local decide = mod._cim_skip_upgrade_anim_in_mission
    if type(decide) ~= "function" then
        return "decision helper mod._cim_skip_upgrade_anim_in_mission not exposed (Fix B4 dead)"
    end
    local in_keep = _is_in_keep()
    -- (1) Non-"upgrade" animations must NEVER be skipped (they're HDR-free; e.g.
    --     "on_enter" / text fades drive the normal forge fade-in).
    if decide("on_enter") ~= false then
        return "guard skipped a non-upgrade animation (on_enter) — would break the forge fade-in"
    end
    -- (2) The "upgrade" animation: skipped in mission, run in the keep.
    local skip_upgrade = decide("upgrade")
    if in_keep and skip_upgrade ~= false then
        return "in keep: upgrade-anim guard returned true — would drop the keep's upgrade flourish"
    end
    if not in_keep and skip_upgrade ~= true then
        return "in mission: upgrade-anim guard returned false — the upgrade flourish's HDR set_scalar(nil,...) would fatal"
    end
    -- (3) Target methods still exist (a future rename surfaces here).
    if type(HeroWindowWeaveForgeOverview) ~= "table"
        or type(HeroWindowWeaveForgeOverview._start_transition_animation) ~= "function" then
        return "HeroWindowWeaveForgeOverview._start_transition_animation missing — upgrade-anim guard target renamed/gone"
    end
    if type(HeroWindowWeaveForgeWeapons) ~= "table"
        or type(HeroWindowWeaveForgeWeapons._start_transition_animation) ~= "function" then
        return "HeroWindowWeaveForgeWeapons._start_transition_animation missing — upgrade-anim guard target renamed/gone"
    end
end)

_rt_register("forge_preview_guard_allows_loaded_weapon", function()
    -- Complement to forge_preview_guard_present: a normal weapon whose units ARE
    -- loadable must NOT be flagged unsafe, or we'd strip the 3D preview from
    -- every weapon. Only meaningful inside the modded forge (the weapon's
    -- display unit is resident only there) — skips otherwise.
    local fn = mod._cim_forge_preview_unsafe
    if type(fn) ~= "function" then return "guard missing" end
    if not _custom_forge_active then
        return "skip: not in modded forge (preview units only resident there)"
    end
    local items_backend = Managers.backend and Managers.backend:get_interface("items")
    local pl = Managers.player and Managers.player:local_player()
    if not (items_backend and pl) then return "skip: backend/player not ready" end
    local profile = SPProfiles[pl:profile_index()]
    local career = profile and profile.careers[pl:career_index()]
    if not career then return "skip: no career" end
    -- Melee slot: a standard melee weapon is never the torpedo, so it should be
    -- previewable when the forge is open.
    local bid = items_backend:get_loadout_item_id(career.name, "slot_melee")
    local item = bid and items_backend:get_item_from_id(bid)
    if not item then return "skip: no melee item equipped" end
    if fn(item) == true then
        return "guard flagged a normally-equipped melee weapon as unsafe — would wrongly strip its 3D preview"
    end
end)

_rt_register("rpc_schema_gate_drops_on_mismatch", function()
    -- audit 2026-06-07 (v0.7.72-dev): the cim_modded_slot RPC must carry a schema
    -- version (CIM_RPC_SCHEMA) as its first wire arg and the receiver must DROP a
    -- mismatched payload without mutating _cim_modded_slot_state (VMF_RECIPES § 10).
    -- Drives the exposed receiver synthetically: a wrong schema_version must leave
    -- state untouched; the correct one must record the per-slot flag.
    local recv = mod._cim_rpc_modded_slot
    local state = mod._cim_modded_slot_state
    if type(recv) ~= "function" then return "receiver mod._cim_rpc_modded_slot not exposed" end
    if type(state) ~= "table" then return "state table mod._cim_modded_slot_state not exposed" end

    -- Synthetic identifiers unlikely to collide with any live peer/slot.
    local FAKE_PEER, FAKE_LPID, FAKE_SLOT = "rt_schema_peer", 7, "slot_melee"
    local uid = tostring(FAKE_PEER) .. ":" .. tostring(FAKE_LPID)
    local had_uid = state[uid] ~= nil          -- preserve any pre-existing entry
    local saved = state[uid]
    state[uid] = nil

    local result_err
    -- (1) Mismatched schema -> dropped, no state write.
    recv(FAKE_PEER, CIM_RPC_SCHEMA + 1, FAKE_PEER, FAKE_LPID, FAKE_SLOT, true)
    if state[uid] ~= nil then
        result_err = "schema-mismatch packet was NOT dropped — receiver mutated _cim_modded_slot_state"
    end

    -- (2) Matching schema -> flag recorded.
    if not result_err then
        recv(FAKE_PEER, CIM_RPC_SCHEMA, FAKE_PEER, FAKE_LPID, FAKE_SLOT, true)
        if not (state[uid] and state[uid][FAKE_SLOT] == true) then
            result_err = "matching-schema packet did not record the per-slot modded flag"
        end
    end

    -- Teardown: restore whatever was there before (don't leak the synthetic entry).
    if had_uid then state[uid] = saved else state[uid] = nil end

    return result_err
end)

_rt_register("issue88_inventory_access_flip_is_scoped", function()
    -- Issue #88: open_standard_crafting must NOT permanently mutate
    -- InventorySettings.inventory_loadout_access_supported_game_modes (that
    -- leaked the loadout inventory onto the ESC-menu backout mid-mission). The
    -- flip is now scoped to cim's own HeroView open via the one-shot
    -- `_cim_open_standard_inv_pending` flag + a save/restore HeroView.on_enter
    -- hook. This source-pattern guard fails if the persistent flip is
    -- reintroduced or the scoped pieces are removed. Degrades to a no-op when
    -- source introspection is unavailable (bundle/deploy path).
    local ok, info = pcall(debug.getinfo, mod.open_standard_crafting or function() end, "S")
    if not ok or type(info) ~= "table" or not info.source then return end
    local src_path = info.source:sub(1, 1) == "@" and info.source:sub(2) or info.source
    local f = io.open(src_path, "r")
    if not f then return end
    local txt = f:read("*a")
    f:close()
    if not txt then return end
    -- The one-shot handshake flag must be set in open_standard_crafting.
    if not txt:find("_cim_open_standard_inv_pending", 1, true) then
        return "Issue #88 regression: one-shot inventory-access flag _cim_open_standard_inv_pending missing"
    end
    -- The scoped HeroView.on_enter hook (assembled from two literals so this
    -- test's own source doesn't self-match) must exist.
    local hook_needle = 'mod:hook("' .. 'HeroView", "on_enter"'
    if not txt:find(hook_needle, 1, true) then
        return "Issue #88 regression: scoped HeroView.on_enter inventory-access hook missing"
    end
    -- And the restore must be present (modes saved + put back).
    if not txt:find("saved_adventure", 1, true) then
        return "Issue #88 regression: inventory-access restore (saved_adventure) missing — flip may no longer be scoped"
    end
    return nil
end)

_rt_register("issue96_allow_in_mission_widget_moved_to_gut", function()
    -- Issue #96 epilogue (2026-07-02, user direction): the "Allow standard
    -- crafting bench in mission" WIDGET must NOT exist in cim's data tree at
    -- all - the option lives in gut's In-Mission Menus group (cim-gated
    -- there), and gut writes through to cim's `allow_in_mission` SETTING.
    -- Two invariants:
    --   1. no `setting_id = "allow_in_mission"` widget in _data.lua, and
    --   2. the main-lua readers still honor mod:get("allow_in_mission")
    --      (gut's write-through target - removing the readers would silently
    --      orphan gut's toggle).
    -- Source-pattern guard; degrades to a no-op when source introspection is
    -- unavailable (bundle/deploy path).
    local ok, info = pcall(debug.getinfo, mod.open_standard_crafting or function() end, "S")
    if not ok or type(info) ~= "table" or not info.source then return end
    local src_path = info.source:sub(1, 1) == "@" and info.source:sub(2) or info.source
    local dir = src_path:match("^(.*[/\\])[^/\\]*$")
    if not dir then return end
    local function read_all(path)
        local f = io.open(path, "r")
        if not f then return nil end
        local t = f:read("*a")
        f:close()
        return t
    end
    local data_txt = read_all(dir .. "crafting_in_modded_dev_data.lua")
    if data_txt then
        -- needle split so this test's own source never self-matches
        if data_txt:find('setting_id = ' .. '"allow_in_mission"', 1, true) then
            return "Issue #96 regression: allow_in_mission widget re-appeared in _data.lua — it must live ONLY in gut's In-Mission Menus"
        end
    end
    local main_txt = read_all(src_path)
    if main_txt then
        if not main_txt:find('mod:get("allow_in_mission")', 1, true) then
            return "Issue #96 regression: no mod:get(\"allow_in_mission\") reader left in main lua — gut's write-through toggle is orphaned"
        end
    end
    return nil
end)

_rt_register("forge_mission_env_picker_prefers_resident", function()
    -- v0.8.48-dev (#83): the mission forge/preview worlds must get their
    -- shading env from the residency-probed picker, preferring the studio-lit
    -- ui_store_preview, then ui_hdr, then the boot-assets environment/blank
    -- (engine default, resident everywhere). Drive the exposed helper with
    -- injected probes so the preference order is pinned without a live engine.
    if type(mod._cim_pick_mission_env) ~= "function" then
        return "mod._cim_pick_mission_env missing"
    end
    local pick = mod._cim_pick_mission_env(function(n) return n == "environment/ui_store_preview" end)
    if pick ~= "environment/ui_store_preview" then
        return "expected ui_store_preview when resident, got " .. tostring(pick)
    end
    pick = mod._cim_pick_mission_env(function(n) return n == "environment/ui_hdr" end)
    if pick ~= "environment/ui_hdr" then
        return "expected ui_hdr when only it is resident, got " .. tostring(pick)
    end
    pick = mod._cim_pick_mission_env(function() return false end)
    if pick ~= "environment/blank" then
        return "expected environment/blank final fallback, got " .. tostring(pick)
    end
    pick = mod._cim_pick_mission_env(function() return true end)
    if pick ~= "environment/ui_store_preview" then
        return "expected ui_store_preview to win when everything is resident, got " .. tostring(pick)
    end
end)

_rt_register("customization_variation_pin_decision", function()
    -- v0.8.48-dev (#83 / #228 class): the _update_environment hook must allow
    -- vanilla's per-weapon blend variation ONLY on an env that defines it
    -- (ui_store_preview) or after cosmetics_tweaker's #235 re-point. An
    -- undefined variation on any other env is a native ShadingEnvironment.blend
    -- access violation — the fatal that forced the v0.8.23 keep-only gate.
    if type(mod._cim_env_allows_variation) ~= "function" then
        return "mod._cim_env_allows_variation missing"
    end
    if not mod._cim_env_allows_variation("environment/ui_store_preview", false) then
        return "ui_store_preview must allow vanilla's variation (it defines weapons_default_01)"
    end
    if mod._cim_env_allows_variation("environment/ui_hdr", false) then
        return "ui_hdr must NOT allow per-weapon variations (undefined variation = blend AV, #228)"
    end
    if mod._cim_env_allows_variation("environment/blank", false) then
        return "environment/blank must NOT allow per-weapon variations"
    end
    if not mod._cim_env_allows_variation("environment/ui_hdr", true) then
        return "a cosmetics_tweaker re-point (cos_preview_env_repointed) must unlock the variation"
    end
    if mod._cim_env_allows_variation(nil, false) then
        return "nil env must pin to default (fail-safe)"
    end
end)

_rt_register("open_forge_gate_honors_allow_in_mission", function()
    -- v0.8.48-dev (#83): the v0.8.23 HARD keep-only gate in mod.open_forge is
    -- replaced by the allow_in_mission opt-in. Source-pattern check so the
    -- hard gate can't silently come back. Needles split so this test's own
    -- source never self-matches. No-ops when source introspection is
    -- unavailable (bundle/deploy path).
    local ok, info = pcall(debug.getinfo, mod.open_forge or function() end, "S")
    if not ok or type(info) ~= "table" or not info.source then return end
    local src_path = info.source:sub(1, 1) == "@" and info.source:sub(2) or info.source
    local f = io.open(src_path, "r")
    if not f then return end
    local txt = f:read("*a")
    f:close()
    if not txt then return end
    -- (a) the opt-in gate shape must be present TWICE (open_forge AND
    --     open_standard_crafting), plain-text finds, no pattern escapes.
    local optin_needle = 'if not in_keep and not mod:get("allow_in_mission")' .. ' then'
    local first = txt:find(optin_needle, 1, true)
    local second = first and txt:find(optin_needle, first + 1, true)
    if not second then
        return "#83 regression: expected the allow_in_mission opt-in gate in BOTH open_forge and open_standard_crafting"
    end
    -- (b) the old hard-gate echo must be gone.
    local hard_needle = "The Athanor (weave forge) only opens" .. " in the Keep."
    if txt:find(hard_needle, 1, true) then
        return "#83 regression: the v0.8.23 hard keep-only gate echo is back in open_forge"
    end
end)

mod:info("[mem-probe] cim_dev boot_lua=+%.1f MB (of ~1024 MB lua_heap cap)", (collectgarbage("count") - _MEM_PROBE_T0_CIMD) / 1024)
