--[[
modded_progression (mp) — re-enables 100% of vanilla Vermintide 2's
progression systems in the modded realm. All state persisted locally
via VMF settings; the real PlayFab account is never written to.

Full design: modded_progression/PLAN.md.

Status (v0.1.0-dev): SCAFFOLDING ONLY. No PlayFab interceptions wired.
No mirror overlay applied. No UI gates un-gated. The sibling API
functions return sane defaults so co-installed mods don't crash.

Major sections (search by name to jump):
  * Settings / schema versioning      — VMF settings access + migration hook
  * Currency store                    — has_currency / spend / credit + read helpers
  * Unlock store                      — is_unlocked / mark_unlocked
  * Inventory store (locally-granted) — grant_item / get_inventory
  * Mirror overlay (STUB)             — boot-time hydration from VMF → backend_mirror
  * Serialization (STUB)              — mirror mutation → VMF write-back
  * Sibling API surface               — what CWV / cosmetics_tweaker call into
  * Diagnostic commands               — mp_dump, mp_reset
]]

local mod = get_mod("mp")

local MOD_VERSION = "0.2.9-dev"
-- Startup banner: log-only, NOT chat. The applied marker line further down
-- ([mp] enabled v<X> settings_fp=<hash>) is the canonical version surface
-- (PROJECT_STANDARDS.md § 3.6 "Chat-echo policy").
mod:info("Modded Progression v%s loaded", MOD_VERSION)

-- Two-helper debug-logging policy (PROJECT_STANDARDS.md § 3.6).
-- Both gate on `enable_debug_logging`. Both no-op when toggle is off.
-- `_dbg` is for confirmation / expected behavior — file only.
-- `_dbg_alert` is for unexpected / wrong / mismatch — file AND in-game chat.
local function _dbg(fmt, ...)
    if mod:get("enable_debug_logging") then
        mod:info("[mp:dbg] " .. fmt, ...)
    end
end

local function _dbg_alert(fmt, ...)
    if mod:get("enable_debug_logging") then
        mod:info("[mp:dbg] " .. fmt, ...)
        mod:echo("[mp] " .. fmt, ...)
    end
end

-- Applied marker (PROJECT_STANDARDS.md § 3.6 "Applied marker line (universal)").
-- Walks the data widget tree, FNV-1a-32 hashes setting=value pairs, prints
-- one mod:info line at load. ALWAYS fires (operational telemetry).
local function _settings_fingerprint()
    local ok, data = pcall(require, "scripts/mods/modded_progression/modded_progression_data")
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

mod:info("[mp:LOAD] v%s enabled fp=%s OK", MOD_VERSION, _settings_fingerprint())

-- Per PROJECT_STANDARDS § 3.6 + § 14a: dev/alpha/beta/0.x versions print
-- version to chat on load so the user can see what's active. Stable
-- (>=1.0.0) versions stay silent. Detect via MOD_VERSION string match.
if MOD_VERSION:find("-dev$") or MOD_VERSION:find("-alpha$") or MOD_VERSION:find("-beta$") or MOD_VERSION:find("-rc%d*$") or MOD_VERSION:find("^0%.") then
    mod:echo(string.format("[mp] v%s loaded", MOD_VERSION))
end

-- v0.2.4-dev: regression test scaffold (mp had none).
local _RT_CHECKS = {}
local function _rt_register(name, fn)
    _RT_CHECKS[#_RT_CHECKS + 1] = { name = name, fn = fn }
end
mod:command("mp_regression_test", "Run regression smoke checks for past bugs", function()
    local pass, fail = 0, 0
    mod:echo("=== mp regression_test (v%s) ===", MOD_VERSION)
    for _, c in ipairs(_RT_CHECKS) do
        local ok, err = pcall(c.fn)
        if ok and err == nil then
            mod:echo("  PASS: %s", c.name); pass = pass + 1
            mod:info("[regression] PASS %s", c.name)
        else
            local msg = (not ok and tostring(err)) or tostring(err)
            mod:echo("  FAIL: %s -- %s", c.name, msg); fail = fail + 1
            mod:warning("[regression] FAIL %s: %s", c.name, msg)
        end
    end
    mod:echo("=== %d passed, %d failed ===", pass, fail)
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
    local ok, loc = pcall(mod.dofile, mod, "scripts/mods/modded_progression/modded_progression_localization")
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
-- ============================================================
-- Settings / schema versioning
-- ============================================================
-- Bump SCHEMA_VERSION whenever the stored data shape changes; the
-- migration function (TODO) reads the stored version and upgrades.
local SCHEMA_VERSION = 1

local function get_schema_version()
    return mod:get("schema_version") or 0
end

local function set_schema_version(v)
    mod:set("schema_version", v, false)
end

local function get_starting_state()
    return mod:get("starting_state") or "fresh"
end

local function is_seeded()
    return mod:get("seeded") == true
end

local function mark_seeded()
    mod:set("seeded", true, false)
end

-- ============================================================
-- Currency store (read/write through VMF settings)
-- ============================================================
-- Kinds match the vanilla codes used by peddler_interface:set_chips
-- (`SM` shillings, `VS` versus tokens) and the crafting material item
-- ids (`scrap`, `green_dust`, `blue_dust`, `orange_dust`, `red_dust`,
-- `essence`). Stored as a single table under settings key "currency".
local CURRENCY_KINDS = {
    SM         = true,  -- shillings
    VS         = true,  -- versus tokens
    scrap      = true,
    green_dust = true,
    blue_dust  = true,
    orange_dust = true,
    red_dust   = true,
    essence    = true,
}

local function get_currency_store()
    return mod:get("currency") or {}
end

local function set_currency_store(t)
    mod:set("currency", t, false)
end

local function get_currency(kind)
    local store = get_currency_store()
    return store[kind] or 0
end

local function _set_currency(kind, amount)
    if not CURRENCY_KINDS[kind] then
        mod:warning("set_currency: unknown kind '%s'", tostring(kind))
        return
    end
    local store = get_currency_store()
    store[kind] = math.max(0, math.floor(amount))
    set_currency_store(store)
end

-- ============================================================
-- Unlock store
-- ============================================================
-- Tracks which item_keys / skin_keys / cosmetic_keys / decoration_keys
-- have been earned in modded sessions. Siblings consult this via
-- mod.is_unlocked() to gate their content.
local function get_unlock_store()
    return mod:get("unlocks") or {}
end

local function set_unlock_store(t)
    mod:set("unlocks", t, false)
end

local function _mark_unlocked(key)
    local store = get_unlock_store()
    store[key] = true
    set_unlock_store(store)
end

-- ============================================================
-- Inventory store (locally-granted items)
-- ============================================================
-- Items the player has earned in modded sessions that weren't in the
-- real PlayFab account. Boot-time overlay re-injects these into the
-- backend mirror. Schema mirrors the vanilla item shape so add_item
-- can consume it directly.
local function get_inventory_store()
    return mod:get("inventory") or {}
end

local function set_inventory_store(t)
    mod:set("inventory", t, false)
end

-- ============================================================
-- Mirror overlay (STUB — wired in build-order step 3+)
-- ============================================================
-- Boot sequence (per PLAN.md):
--   1. PlayFab sign-in completes, backend_mirror initializes from real account.
--   2. We detect modded realm.
--   3. First-time entry: apply starting-state seed; mark seeded.
--   4. Returning entry: overwrite modded-tracked mirror fields with VMF shadow.
--
-- Hook target TBD — needs a callback when Managers.backend:ready() flips
-- or when PlayFabMirrorBase finishes _verify_account_data. For now, the
-- function is callable but no-ops.
local _overlay_applied = false

local function apply_mirror_overlay()
    if _overlay_applied then return end
    -- TODO step 1.b: implement
    --   * If not is_seeded(): run starting-state seed, write to VMF
    --   * Else: read VMF stores, write through backend_mirror mutators
    _overlay_applied = true
end

-- ============================================================
-- Serialization (STUB — wired in build-order step 3+)
-- ============================================================
-- Every backend_mirror mutator that we trigger from a local replacement
-- should also re-serialize the relevant slice back to VMF settings.
-- Centralized helpers here so the interception sites stay small.
local function serialize_currency_from_mirror()
    -- TODO step 1.b: read peddler chips + essence from mirror, write to VMF
end

local function serialize_inventory_from_mirror()
    -- TODO step 1.b: read mirror inventory delta vs. real-account baseline, write to VMF
end

local function serialize_xp_from_mirror()
    -- TODO step 1.b: read per-career experience from mirror read_only_data, write to VMF
end

-- ============================================================
-- Sibling API surface
-- ============================================================
-- Called by character_weapon_variants and cosmetics_tweaker via
-- get_mod("mp"). Returning sensible defaults when not yet seeded
-- avoids breaking siblings during scaffolding.

mod.is_unlocked = function(item_key)
    if not is_seeded() then return true end  -- pre-seed: don't gate anything
    return get_unlock_store()[item_key] == true
end

mod.mark_unlocked = function(item_key)
    _mark_unlocked(item_key)
end

mod.has_currency = function(kind, amount)
    return get_currency(kind) >= (amount or 0)
end

mod.spend = function(kind, amount)
    amount = amount or 0
    if not mod.has_currency(kind, amount) then return false end
    _set_currency(kind, get_currency(kind) - amount)
    return true
end

mod.credit = function(kind, amount)
    amount = amount or 0
    _set_currency(kind, get_currency(kind) + amount)
end

mod.get_currency = function(kind)
    return get_currency(kind)
end

mod.grant_item = function(item_data)
    -- TODO step 3+: write through backend_mirror:add_item, mirror into VMF
    -- For scaffolding: just record into inventory store.
    if not item_data or not item_data.ItemId then return nil end
    local store = get_inventory_store()
    local backend_id = item_data.ItemInstanceId or ("mp_" .. tostring(item_data.ItemId) .. "_" .. tostring(os.time()) .. "_" .. tostring(math.random(1, 99999)))
    store[backend_id] = item_data
    set_inventory_store(store)
    return backend_id
end

-- ============================================================
-- UI gate overrides (build-order step 2)
-- ============================================================
-- Vanilla has ~10 sites that read script_data["eac-untrusted"] to grey
-- out UI buttons and skip reward popups. Strategy: hook each enclosing
-- function, set the flag to nil while the original body runs, restore
-- on exit. The flag stays globally true outside our wrapped calls, so
-- commit suppression in playfab_mirror_base (lines 2826/2839/2857) and
-- the DLC-update gate in unlock_manager.lua:719 remain intact.
--
-- Multi-return handled via table-pack/unpack so wrappers don't collapse
-- secondary returns (see feedback_hook_multi_return_collapse).
--
-- NIL-HOLE PRESERVATION: `_with_eac_off` wraps 9 different vanilla functions
-- (init / UI / AchievementManager.trigger_event / etc.) — some have implicit
-- early `return` (zero values), some return values from method calls. A bare
-- `{ func(...) }` table loses its length tracking on internal nils, and
-- `unpack(results)` then stops at the first nil, silently truncating
-- subsequent returns. Same bug class that burned weapon_tweaker v0.12.77/.78.
-- Use select("#") to capture the true return count, then unpack with explicit
-- bounds so nil holes survive.
local function _capture(...) return select("#", ...), { ... } end

local function _with_eac_off(func, self, ...)
    local orig = script_data["eac-untrusted"]
    script_data["eac-untrusted"] = nil
    local n, results = _capture(func(self, ...))
    script_data["eac-untrusted"] = orig
    return unpack(results, 1, n)
end

-- Level-end reward popups (level-up, deed, deus, keep-decoration,
-- event, win-track, versus-level-up — all skipped in init when
-- is_untrusted is true; flipping the flag during init runs the body).
mod:hook("LevelEndViewBase", "init", _with_eac_off)

-- Okri's Challenges UI:
--   _create_entries (line 646)  — `completed` flag on each entry
--   _handle_claim_all_challenges (line 2992) — claim-all button visibility
mod:hook("HeroViewStateAchievements", "_create_entries", _with_eac_off)
mod:hook("HeroViewStateAchievements", "_handle_claim_all_challenges", _with_eac_off)

-- Lohner's Emporium:
--   _set_unlock_button_states (line 1873) — buy button enable
--   _create_ui_elements (line 1149)       — popup buy button disable flag
--   _create_ui_elements (line 57)         — login-rewards claim button
mod:hook("StoreWindowItemPreview", "_set_unlock_button_states", _with_eac_off)
mod:hook("StoreItemPurchasePopup", "_create_ui_elements", _with_eac_off)
mod:hook("StoreLoginRewardsPopup", "_create_ui_elements", _with_eac_off)

-- Vanilla keep crafting bench:
--   _enable_craft_button (line 1878)        — flips `enable` arg to false
--   _update_state_craft_button (line 1928)  — button-hotspot disable flag
mod:hook("HeroWindowItemCustomization", "_enable_craft_button", _with_eac_off)
mod:hook("HeroWindowItemCustomization", "_update_state_craft_button", _with_eac_off)

-- Generic in-game UI guard. The function literally returns
-- `not script_data["eac-untrusted"]`; we want it always true.
mod:hook("IngameUI", "not_in_modded", function(func, self) return true end)

-- Achievement progress tracking — CRITICAL. Without this, kill counts
-- and mission-completion events don't tick the challenge progress
-- counters, so claiming a challenge later is pointless. The DEDICATED_SERVER
-- branch of the gate still holds (we only flip the eac-untrusted half).
mod:hook("AchievementManager", "trigger_event", _with_eac_off)

-- AchievementManager.update (line 294) drives the Steam-platform push
-- loop. Left gated intentionally — local progression doesn't need Steam
-- to register the achievements.

-- ============================================================
-- Diagnostic commands
-- ============================================================
mod:command("mp_dump", "Modded Progression: dump current state", function()
    mod:echo(string.format("schema=%d, seeded=%s, starting_state=%s",
        get_schema_version(), tostring(is_seeded()), tostring(get_starting_state())))
    local cur = get_currency_store()
    local n_currency = 0
    for _ in pairs(cur) do n_currency = n_currency + 1 end
    local n_unlocks = 0
    for _ in pairs(get_unlock_store()) do n_unlocks = n_unlocks + 1 end
    local n_inv = 0
    for _ in pairs(get_inventory_store()) do n_inv = n_inv + 1 end
    mod:echo(string.format("currency kinds=%d, unlocks=%d, inventory=%d", n_currency, n_unlocks, n_inv))
    for k, v in pairs(cur) do
        mod:echo(string.format("  %s = %d", k, v))
    end
end)

mod:command("mp_reset", "Modded Progression: wipe local store (does NOT touch PlayFab)", function()
    mod:set("currency", {}, false)
    mod:set("unlocks", {}, false)
    mod:set("inventory", {}, false)
    mod:set("seeded", false, false)
    set_schema_version(0)
    mod:echo("Modded Progression: local store wiped. Restart the game to re-seed.")
end)

-- ============================================================
-- Schema migration on first load (no-op at v1)
-- ============================================================
if get_schema_version() < SCHEMA_VERSION then
    -- TODO: real migrations as schema evolves
    set_schema_version(SCHEMA_VERSION)
end

-- Boot-time overlay is gated on backend readiness — defer.
-- TODO step 1.b: wire to Managers.backend:ready() or PlayFabMirrorBase init completion.
-- apply_mirror_overlay() will fire from that hook once available.
