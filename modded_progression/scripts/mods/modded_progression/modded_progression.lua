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

local MOD_VERSION = "0.2.1-dev"
mod:info("Modded Progression v%s loaded", MOD_VERSION)
mod:echo("Modded Progression v" .. MOD_VERSION)

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

local function _with_eac_off(func, self, ...)
    local orig = script_data["eac-untrusted"]
    script_data["eac-untrusted"] = nil
    local results = { func(self, ...) }
    script_data["eac-untrusted"] = orig
    return unpack(results)
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
