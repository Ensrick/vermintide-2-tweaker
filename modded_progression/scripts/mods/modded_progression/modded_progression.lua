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
-- [mem-probe] temp Lua-footprint baseline (lua_heap 1 GiB cap diagnostic).
-- File-local (was a bare _G global pre-0.2.14; issue 434 / audit F7): read only
-- at the bottom of this same chunk, so no _G or cross-file exposure is needed.
local _MEM_PROBE_T0_MP = collectgarbage("count")

local MOD_VERSION = "0.2.19-dev"
-- Startup banner: log-only, NOT chat. The applied marker line further down
-- ([mp] enabled v<X> settings_fp=<hash>) is the canonical version surface
-- (PROJECT_STANDARDS.md § 3.6 "Chat-echo policy").
mod:info("Modded Progression v%s loaded", MOD_VERSION)

-- Two-helper debug-logging policy (PROJECT_STANDARDS.md § 3.6).
-- Routed through VMF logging channels; visible via VMF output_mode_debug / output_mode_warning.
-- `_dbg` is for confirmation / expected behavior — mod:debug channel.
-- `_dbg_alert` is for unexpected / wrong / mismatch. Log-only via engine printf (#427).
local function _dbg(fmt, ...)
    mod:debug("[mp:dbg] " .. fmt, ...)
end

-- Issue #427/#240: mod:warning posts to CHAT under VMF defaults (logging.lua
-- warning mode >= 2), so a "log-only" alert spammed chat. Route through
-- pcall-guarded engine printf (log-only, survives mod-logging-OFF; pcall so a
-- format slip never faults the caller). Reserve chat for a deliberate
-- _chat_alert (none defined here).
local function _dbg_alert(fmt, ...)
    if not pcall(printf, "[mp:dbg] " .. fmt, ...) then
        pcall(printf, "[mp:dbg] (alert format error: %s)", tostring(fmt))
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
    local ok = pcall(_dbg, "smoke test")
    if not ok then return "_dbg raised on call" end
    ok = pcall(_dbg_alert, "smoke test")
    if not ok then return "_dbg_alert raised on call" end
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
-- NB: the `eac_flag_restored_after_throw` check is registered AFTER `_with_eac_off`
-- is defined (search "issue 434 regression") to avoid a forward-ref on the local.
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
-- MP-owned daily lifecycle (issues #568/#573)
-- ============================================================
local Dailies = mod:dofile("scripts/mods/modded_progression/mp_dailies")
local _local_quest_rewards = {}
local _local_poll_serial = 0

local function _shallow_copy(source)
    local copy = {}
    for key, value in pairs(source or {}) do copy[key] = value end
    return copy
end

local function _find_daily_entry(id)
    return Dailies.find_by_id(id)
end

local function _local_claim(ids)
    local granted, total_or_reason = Dailies.claim(ids)
    if not granted then
        _dbg_alert("simulated daily claim rejected: %s", tostring(total_or_reason))
        return nil, total_or_reason
    end

    _local_poll_serial = _local_poll_serial + 1
    local poll_id = string.format("mp_local_daily_claim_%d", _local_poll_serial)
    _local_quest_rewards[poll_id] = {
        quest_key = granted,
        loot = {{
            type = "currency",
            currency_code = Dailies.REWARD_KIND,
            amount = total_or_reason,
        }},
    }
    _dbg("simulated daily claim persisted count=%d poll=%s backend=none", #granted, poll_id)
    return poll_id
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
    local balance = kind == Dailies.REWARD_KIND and Dailies.balance() or get_currency(kind)
    return balance >= (amount or 0)
end

mod.spend = function(kind, amount)
    amount = amount or 0
    if not mod.has_currency(kind, amount) then return false end
    if kind == Dailies.REWARD_KIND then return Dailies.spend(amount) end
    _set_currency(kind, get_currency(kind) - amount)
    return true
end

mod.credit = function(kind, amount)
    amount = amount or 0
    if kind == Dailies.REWARD_KIND then return Dailies.credit(amount) end
    _set_currency(kind, get_currency(kind) + amount)
end

mod.get_currency = function(kind)
    return kind == Dailies.REWARD_KIND and Dailies.balance() or get_currency(kind)
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

-- #174: track whether we are currently inside a `_with_eac_off` window (the
-- realm is un-gated for a vanilla progression call). Depth counter mirrors the
-- eac-flag set/restore bracket exactly so behaviour is byte-identical. Read by
-- cosmetics' #174 chokepoint hook.
mod._mp_eac_depth = 0
-- Distinct from `_mp_eac_depth`: the generic bracket also runs in official
-- realm, so it cannot identify realm ownership. This counter increments only
-- when the bracket actually cleared a true eac-untrusted flag.
mod._mp_modded_depth = 0
mod.is_eac_window = function() return (mod._mp_eac_depth or 0) > 0 end

-- issue 434: the flag AND the depth counter MUST be restored on EVERY exit path.
-- A throw inside `func` used to skip both the decrement and the flag restore,
-- leaving `script_data["eac-untrusted"] = nil` globally; the commit-suppression
-- sites (playfab_mirror_base.lua:2826/2839/2857) gate on that flag, so a leaked
-- nil re-enables real-account PlayFab writes -- exactly what mp exists to prevent.
-- `AchievementManager.trigger_event` (a hot per-mission hook) is the highest
-- throw-exposure wrapped fn. We pcall the inner call, restore both in finally
-- style, then re-raise the original error transparently so callers behave as
-- vanilla would have (the only difference is the realm is re-gated first).
local function _with_eac_off(func, self, ...)
    local orig = script_data["eac-untrusted"]
    script_data["eac-untrusted"] = nil
    mod._mp_eac_depth = mod._mp_eac_depth + 1
    if orig == true then mod._mp_modded_depth = mod._mp_modded_depth + 1 end
    -- _capture over pcall: results[1] is the pcall `ok`; func's own returns
    -- (nil holes preserved via the explicit count `n`) start at index 2.
    local n, results = _capture(pcall(func, self, ...))
    mod._mp_eac_depth = mod._mp_eac_depth - 1
    if orig == true then mod._mp_modded_depth = mod._mp_modded_depth - 1 end
    script_data["eac-untrusted"] = orig
    if not results[1] then
        _dbg_alert("_with_eac_off: wrapped fn threw; eac flag restored, re-raising: %s", tostring(results[2]))
        error(results[2], 0)  -- re-raise with the original message, no added position
    end
    return unpack(results, 2, n)
end

-- issue 434 regression: a throw inside `_with_eac_off` must restore the
-- eac-untrusted flag AND the depth counter on ALL paths, and re-raise. If the
-- flag leaks nil, real-account PlayFab commits fire (playfab_mirror_base.lua
-- :2826/2839/2857). Registered here (not up with the other checks) because
-- `_with_eac_off` is a file-local defined just above -- registering earlier
-- would forward-ref a nil global.
_rt_register("eac_flag_restored_after_throw", function()
    local saved    = script_data["eac-untrusted"]
    local depth0   = mod._mp_eac_depth
    local sentinel = {}                       -- unique identity; unambiguous restore check
    script_data["eac-untrusted"] = sentinel
    local ok = pcall(_with_eac_off, function() error("mp_rt_boom") end, nil)
    local restored = script_data["eac-untrusted"]
    local depth1   = mod._mp_eac_depth
    script_data["eac-untrusted"] = saved      -- put the global back before any verdict
    if ok then return "wrapper swallowed the throw; it must re-raise" end
    if restored ~= sentinel then return "eac-untrusted flag NOT restored after throw" end
    if depth1 ~= depth0 then return "eac depth counter leaked after throw" end
    if mod.is_eac_window() then return "is_eac_window() still true after throw unwound" end
end)

-- issue 509 backfill: two more locks on the _with_eac_off contract plus the
-- sibling-API surface that CWV / cosmetics_tweaker consume. Registered here beside
-- _with_eac_off (a file-local just above); the sibling API (mod.*) is assigned
-- earlier in this chunk and resolved at call time.
_rt_register("eac_off_preserves_multi_return_nil_holes", function()
    -- _with_eac_off wraps 9 vanilla fns whose returns include nil holes (see the
    -- NIL-HOLE PRESERVATION note above). Exercise the select("#")/unpack machinery
    -- end-to-end: a 1, nil, 3 return must survive unchanged. This is the wt
    -- v0.12.77/.78 multi-return-collapse class in mp's chokepoint.
    local a, b, c = _with_eac_off(function() return 1, nil, 3 end, nil)
    if a ~= 1 then return "first return dropped by _with_eac_off" end
    if b ~= nil then return "nil hole not preserved (2nd return should be nil)" end
    if c ~= 3 then return "trailing return after a nil hole was truncated" end
end)

_rt_register("eac_window_closed_at_rest", function()
    -- Baseline the cosmetics #174 chokepoint depends on: outside any _with_eac_off
    -- call the eac window is CLOSED -- depth 0, is_eac_window() false. A leaked
    -- window (unbalanced depth) would make cosmetics treat every frame as a
    -- vanilla-progression call.
    if type(mod.is_eac_window) ~= "function" then return "mod.is_eac_window sibling API missing" end
    if (mod._mp_eac_depth or 0) ~= 0 then
        return "eac depth counter is " .. tostring(mod._mp_eac_depth) .. " at rest (expected 0) -- a _with_eac_off window leaked"
    end
    if mod.is_eac_window() ~= false then
        return "is_eac_window() is true at rest -- eac window leaked"
    end
end)

_rt_register("sibling_api_surface_present", function()
    -- Cross-mod contract: character_weapon_variants and cosmetics_tweaker call
    -- these via get_mod("mp"). A rename/removal silently breaks the consumer. Assert
    -- presence + a behavior smoke: spend must return false (not raise) when the
    -- wallet cannot cover the amount.
    for _, name in ipairs({ "is_unlocked", "mark_unlocked", "has_currency",
                            "spend", "credit", "get_currency", "grant_item",
                            "is_eac_window" }) do
        if type(mod[name]) ~= "function" then
            return "sibling API function mod." .. name .. " missing (CWV/cosmetics depend on it)"
        end
    end
    local ok, res = pcall(mod.spend, "SM", 999999999999)
    if not ok then return "mod.spend raised instead of returning false on insufficient funds" end
    if res ~= false then return "mod.spend did not return false for an unaffordable amount" end
end)

-- A depth > 0 means a modded-realm UI call is currently inside our temporary
-- EAC-un-gate.  Without this second condition `_create_entries` would briefly
-- look like official realm and leak the vanilla daily list back into MP.
local function _is_mp_realm()
    return script_data["eac-untrusted"] == true or (mod._mp_modded_depth or 0) > 0
end

_rt_register("simulated_daily_realm_boundary", function()
    local saved = script_data["eac-untrusted"]
    local official_seen, modded_seen
    script_data["eac-untrusted"] = nil
    _with_eac_off(function() official_seen = _is_mp_realm() end, nil)
    script_data["eac-untrusted"] = true
    _with_eac_off(function() modded_seen = _is_mp_realm() end, nil)
    script_data["eac-untrusted"] = saved
    if official_seen then return "official-realm UI bracket classified as modded" end
    if not modded_seen then return "modded-realm UI bracket lost ownership state" end
    if (mod._mp_modded_depth or 0) ~= 0 then return "modded realm depth leaked" end
end)

-- Replace only the daily slice. Weekly/event quests retain their vanilla read
-- surface, but are never locally claimed; official realm remains byte-for-byte
-- vanilla. The returned daily ids are all MP namespaced and locally owned.
mod:hook("BackendInterfaceQuestsPlayfab", "get_quests", function(func, self, ...)
    local quests = func(self, ...)
    if not _is_mp_realm() or type(quests) ~= "table" then return quests end

    local local_quests = _shallow_copy(quests)
    local_quests.daily = Dailies.quest_slice()
    return local_quests
end)

mod:hook("BackendInterfaceQuestsPlayfab", "get_quest_key", function(func, self, quest_id, ...)
    if _is_mp_realm() then
        local entry = _find_daily_entry(quest_id)
        if entry then return entry.key end
    end
    return func(self, quest_id, ...)
end)

mod:hook("BackendInterfaceQuestsPlayfab", "get_quest_by_key", function(func, self, key, ...)
    if _is_mp_realm() then
        local quest = Dailies.quest_by_key(key)
        if quest then return quest end
    end
    return func(self, key, ...)
end)

-- The vanilla evaluator supplies names/descriptions/icons from the source
-- templates. Only objective state is replaced with MP's persisted counters.
mod:hook("QuestManager", "get_data_by_id", function(func, self, id, ...)
    local data, err = func(self, id, ...)
    if _is_mp_realm() and Dailies.is_owned_id(id) then
        return Dailies.decorate_quest_data(id, data), err
    end
    return data, err
end)

-- QuestManager dispatches daily, weekly, and event slices separately. Consume
-- MP daily events locally and never create vanilla StatisticsDB quest slots.
mod:hook("QuestManager", "_increment_quest_stats", function(func, self, quests, stats_id, ...)
    if not _is_mp_realm() or type(quests) ~= "table" then
        return func(self, quests, stats_id, ...)
    end
    local local_quests, vanilla_quests = {}, {}
    for key, quest in pairs(quests) do
        if type(quest) == "table" and Dailies.is_owned_id(quest.name) then
            local_quests[key] = quest
        else
            vanilla_quests[key] = quest
        end
    end
    if next(local_quests) then Dailies.increment(local_quests, ...) end
    if next(vanilla_quests) then return func(self, vanilla_quests, stats_id, ...) end
end)

mod:hook("BackendInterfaceQuestsPlayfab", "get_daily_quest_update_time", function(func, self, ...)
    if _is_mp_realm() then return Dailies.seconds_until_reset() end
    return func(self, ...)
end)

-- Every native Silver Shilling read used by the Emporium passes this method.
-- Returning the local ledger makes the visible number realm-correct without
-- ever copying or merging self._chips.SM. Purchases remain blocked below until
-- the item-grant half can be made backend-free as a separate issue.
mod:hook("BackendInterfacePeddlerPlayFab", "get_chips", function(func, self, chip_type, ...)
    if _is_mp_realm() and chip_type == Dailies.REWARD_KIND then return Dailies.balance() end
    return func(self, chip_type, ...)
end)

mod:hook("BackendInterfacePeddlerPlayFab", "exchange_chips", function(func, self, item_id, chip_type, price, callback_fn, ...)
    if _is_mp_realm() and chip_type == Dailies.REWARD_KIND then
        _dbg_alert("blocked official SM purchase item=%s price=%s; local item grant not armed", tostring(item_id), tostring(price))
        if callback_fn then callback_fn(false) end
        return
    end
    return func(self, item_id, chip_type, price, callback_fn, ...)
end)

-- Native reward presentation asks the quest interface for the completed poll's
-- loot. Synthetic ids exist only in this in-memory map and never enter PlayFab.
mod:hook("BackendInterfaceQuestsPlayfab", "get_quest_rewards", function(func, self, id, ...)
    local rewards = _local_quest_rewards[id]
    if rewards then
        _local_quest_rewards[id] = nil
        return rewards
    end
    return func(self, id, ...)
end)

-- Exact individual UI interception identified in VT2 source:
-- HeroViewStateAchievements._claim_quest_reward -> QuestManager.claim_reward
-- -> BackendInterfaceQuestsPlayfab.claim_quest_rewards -> generateQuestRewards.
-- MP-owned ids stop at the first method. Unknown/official ids are blocked in
-- modded play, while official-realm calls retain the original implementation.
mod:hook("HeroViewStateAchievements", "_claim_quest_reward", function(func, self, id, ...)
    if not _is_mp_realm() then return func(self, id, ...) end
    if not Dailies.is_owned_id(id) then
        _dbg_alert("blocked non-MP quest claim id=%s backend=none", tostring(id))
        return nil, "Only Modded Progression simulated dailies can be claimed in modded play."
    end
    return _local_claim({ id })
end)

mod:hook("HeroViewStateAchievements", "_claim_multiple_quest_rewards", function(func, self, ids, ...)
    if not _is_mp_realm() then return func(self, ids, ...) end
    for _, id in ipairs(ids or {}) do
        if not Dailies.is_owned_id(id) then
            _dbg_alert("blocked mixed/non-MP claim-all id=%s backend=none", tostring(id))
            return nil, "Claim-all contained a quest not owned by Modded Progression."
        end
    end
    return _local_claim(ids or {})
end)

-- Defense in depth: no quest reward request of any identity may reach PlayFab
-- while MP owns the modded-realm surface. These hooks should be unreachable for
-- normal UI claims; the alert identifies a missed caller without crashing out.
mod:hook("BackendInterfaceQuestsPlayfab", "claim_quest_rewards", function(func, self, key, ...)
    if _is_mp_realm() then
        _dbg_alert("blocked backend single quest claim key=%s (generateQuestRewards suppressed)", tostring(key))
        return nil
    end
    return func(self, key, ...)
end)

mod:hook("BackendInterfaceQuestsPlayfab", "claim_multiple_quest_rewards", function(func, self, keys, ...)
    if _is_mp_realm() then
        _dbg_alert("blocked backend quest claim-all count=%d (generateQuestRewards suppressed)", type(keys) == "table" and #keys or 0)
        return nil
    end
    return func(self, keys, ...)
end)

_rt_register("simulated_daily_backend_boundary", function()
    if Dailies.is_owned_id("daily_collect_tomes") then return "vanilla id classified as MP-owned" end
    if not Dailies.is_owned_id("mp_daily_v2_20647_1_daily_collect_tomes") then return "MP namespace not recognized" end
    -- The only cloud function strings allowed in this chunk are documentation
    -- and suppression diagnostics; local claims resolve to mp_local poll ids.
    local before = _local_poll_serial
    if before < 0 then return "invalid local poll serial" end
end)

_rt_register("daily_rotation_is_deterministic_and_clock_monotonic", function()
    local period = Dailies._test.utc_period(1783900800)
    if Dailies._test.utc_period(1783900800) ~= period then return "UTC period is not deterministic" end
    local state = Dailies._test.new_state(period, nil, "regression")
    if state.period ~= period or state.next_reset_at ~= (period + 1) * 86400 then
        return "daily reset boundary is not the next UTC period"
    end
    if state.ledger.balance ~= 0 or next(state.ledger.transactions) ~= nil then
        return "new MP ledger was not isolated/empty"
    end
end)

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
        if type(v) == "number" then
            mod:echo(string.format("  %s = %d", k, v))
        end
    end
end)

mod:command("mp_reset", "Modded Progression: wipe local store (does NOT touch PlayFab)", function()
    mod:set("currency", {}, false)
    mod:set("unlocks", {}, false)
    mod:set("inventory", {}, false)
    Dailies.reset()
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

mod:info("[mem-probe] mp boot_lua=+%.1f MB (of ~1024 MB lua_heap cap)", (collectgarbage("count") - _MEM_PROBE_T0_MP) / 1024)
